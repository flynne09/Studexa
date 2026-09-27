-- UUID-based teacher Gemini credential RPCs for Supabase Auth.

create or replace function public.studexa_teacher_gemini_status(p_teacher_uid uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  credential private.teacher_gemini_credentials%rowtype;
  grace_used integer;
  fallback_used_today integer;
begin
  select * into credential
    from private.teacher_gemini_credentials
    where teacher_uid = p_teacher_uid;

  select count(*)::integer into grace_used
    from private.teacher_gemini_backup_sessions
    where teacher_uid = p_teacher_uid and reason = 'grace' and state = 'used';

  select count(*)::integer into fallback_used_today
    from private.teacher_gemini_backup_sessions
    where teacher_uid = p_teacher_uid
      and reason in ('personal_quota', 'provider_unavailable')
      and state = 'used'
      and used_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';

  return jsonb_build_object(
    'configured', credential.teacher_uid is not null,
    'maskedKey', case when credential.teacher_uid is null then null else '****' || credential.last_four end,
    'status', coalesce(credential.status, 'missing'),
    'updatedAt', credential.updated_at,
    'graceRemaining', greatest(0, 3 - grace_used),
    'fallbackRemainingToday', greatest(0, 2 - fallback_used_today)
  );
end;
$$;

create or replace function public.studexa_get_teacher_gemini_credential(p_teacher_uid uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select case when c.teacher_uid is null then null else jsonb_build_object(
    'apiKey', v.decrypted_secret,
    'lastFour', c.last_four,
    'status', c.status,
    'updatedAt', c.updated_at
  ) end
  from (select p_teacher_uid as requested_uid) request
  left join private.teacher_gemini_credentials c on c.teacher_uid = request.requested_uid
  left join vault.decrypted_secrets v on v.id = c.secret_id;
$$;

create or replace function public.studexa_upsert_teacher_gemini_credential(
  p_teacher_uid uuid,
  p_api_key text,
  p_last_four text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_secret_id uuid;
  saved_secret_id uuid;
begin
  if p_teacher_uid is null or char_length(p_api_key) < 20 or char_length(p_last_four) <> 4 then
    raise exception 'Invalid credential input';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_teacher_uid::text, 0));

  select secret_id into existing_secret_id
    from private.teacher_gemini_credentials
    where teacher_uid = p_teacher_uid
    for update;

  if existing_secret_id is null then
    saved_secret_id := vault.create_secret(
      p_api_key,
      null,
      'Studexa teacher Gemini credential'
    );
    insert into private.teacher_gemini_credentials (
      teacher_uid, secret_id, last_four, status, last_validated_at
    ) values (
      p_teacher_uid, saved_secret_id, p_last_four, 'valid', now()
    );
  else
    perform vault.update_secret(existing_secret_id, p_api_key);
    update private.teacher_gemini_credentials
      set last_four = p_last_four,
          status = 'valid',
          updated_at = now(),
          last_validated_at = now()
      where teacher_uid = p_teacher_uid;
    saved_secret_id := existing_secret_id;
  end if;

  return public.studexa_teacher_gemini_status(p_teacher_uid);
end;
$$;

create or replace function public.studexa_mark_teacher_gemini_invalid(p_teacher_uid uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update private.teacher_gemini_credentials
    set status = 'invalid', updated_at = now()
    where teacher_uid = p_teacher_uid;
$$;

create or replace function public.studexa_delete_teacher_gemini_credential(p_teacher_uid uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  deleted_secret_id uuid;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_teacher_uid::text, 0));
  delete from private.teacher_gemini_credentials
    where teacher_uid = p_teacher_uid
    returning secret_id into deleted_secret_id;
  if deleted_secret_id is not null then
    delete from vault.secrets where id = deleted_secret_id;
  end if;
  return public.studexa_teacher_gemini_status(p_teacher_uid);
end;
$$;

create or replace function public.studexa_get_backup_session(
  p_teacher_uid uuid,
  p_client_session_id text
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select case when s.teacher_uid is null then null else
    public.studexa_teacher_gemini_status(p_teacher_uid) || jsonb_build_object(
      'allowed', true,
      'existing', true,
      'reason', s.reason,
      'state', s.state
    ) end
  from (select p_teacher_uid as requested_uid, p_client_session_id as requested_session) request
  left join private.teacher_gemini_backup_sessions s
    on s.teacher_uid = request.requested_uid
   and s.client_session_id = request.requested_session;
$$;

create or replace function public.studexa_reserve_backup_session(
  p_teacher_uid uuid,
  p_client_session_id text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing private.teacher_gemini_backup_sessions%rowtype;
  active_count integer;
  allowance integer;
  status jsonb;
begin
  if p_reason not in ('grace', 'personal_quota', 'provider_unavailable') then
    raise exception 'Invalid backup reason';
  end if;

  -- Serialize reservations per teacher so concurrent devices cannot exceed
  -- either lifetime grace or daily fallback allowances.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_teacher_uid::text, 0));

  -- Expired reservations never consume allowance permanently.
  update private.teacher_gemini_backup_sessions
    set state = 'failed'
    where state = 'reserved' and reserved_at < now() - interval '15 minutes';

  select * into existing
    from private.teacher_gemini_backup_sessions
    where teacher_uid = p_teacher_uid and client_session_id = p_client_session_id
    for update;

  if existing.teacher_uid is not null and existing.state in ('reserved', 'used') then
    status := public.studexa_teacher_gemini_status(p_teacher_uid);
    return status || jsonb_build_object(
      'allowed', true,
      'existing', true,
      'reason', existing.reason,
      'state', existing.state
    );
  end if;

  if p_reason = 'grace' then
    allowance := 3;
    select count(*)::integer into active_count
      from private.teacher_gemini_backup_sessions
      where teacher_uid = p_teacher_uid
        and reason = 'grace'
        and state in ('reserved', 'used');
  else
    allowance := 2;
    select count(*)::integer into active_count
      from private.teacher_gemini_backup_sessions
      where teacher_uid = p_teacher_uid
        and reason in ('personal_quota', 'provider_unavailable')
        and state in ('reserved', 'used')
        and reserved_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';
  end if;

  if active_count >= allowance then
    status := public.studexa_teacher_gemini_status(p_teacher_uid);
    return status || jsonb_build_object('allowed', false, 'existing', false, 'reason', p_reason);
  end if;

  insert into private.teacher_gemini_backup_sessions (
    teacher_uid, client_session_id, reason, state, reserved_at, used_at
  ) values (
    p_teacher_uid, p_client_session_id, p_reason, 'reserved', now(), null
  )
  on conflict (teacher_uid, client_session_id) do update
    set reason = excluded.reason,
        state = 'reserved',
        reserved_at = now(),
        used_at = null;

  status := public.studexa_teacher_gemini_status(p_teacher_uid);
  return status || jsonb_build_object(
    'allowed', true,
    'existing', false,
    'reason', p_reason,
    'state', 'reserved'
  );
end;
$$;

create or replace function public.studexa_finish_backup_session(
  p_teacher_uid uuid,
  p_client_session_id text,
  p_success boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.teacher_gemini_backup_sessions
    set state = case when p_success then 'used' else 'failed' end,
        used_at = case when p_success then coalesce(used_at, now()) else null end
    where teacher_uid = p_teacher_uid
      and client_session_id = p_client_session_id
      and state = 'reserved';
  return public.studexa_teacher_gemini_status(p_teacher_uid);
end;
$$;

revoke all on function public.studexa_teacher_gemini_status(uuid) from public, anon, authenticated;
revoke all on function public.studexa_get_teacher_gemini_credential(uuid) from public, anon, authenticated;
revoke all on function public.studexa_upsert_teacher_gemini_credential(uuid, text, text) from public, anon, authenticated;
revoke all on function public.studexa_mark_teacher_gemini_invalid(uuid) from public, anon, authenticated;
revoke all on function public.studexa_delete_teacher_gemini_credential(uuid) from public, anon, authenticated;
revoke all on function public.studexa_get_backup_session(uuid, text) from public, anon, authenticated;
revoke all on function public.studexa_reserve_backup_session(uuid, text, text) from public, anon, authenticated;
revoke all on function public.studexa_finish_backup_session(uuid, text, boolean) from public, anon, authenticated;

grant execute on function public.studexa_teacher_gemini_status(uuid) to service_role;
grant execute on function public.studexa_get_teacher_gemini_credential(uuid) to service_role;
grant execute on function public.studexa_upsert_teacher_gemini_credential(uuid, text, text) to service_role;
grant execute on function public.studexa_mark_teacher_gemini_invalid(uuid) to service_role;
grant execute on function public.studexa_delete_teacher_gemini_credential(uuid) to service_role;
grant execute on function public.studexa_get_backup_session(uuid, text) to service_role;
grant execute on function public.studexa_reserve_backup_session(uuid, text, text) to service_role;
grant execute on function public.studexa_finish_backup_session(uuid, text, boolean) to service_role;
