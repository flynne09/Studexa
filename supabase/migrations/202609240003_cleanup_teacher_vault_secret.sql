-- Remove the encrypted Vault value whenever its private Teacher mapping is
-- deleted, including deletion caused by an auth.users cascade.

create or replace function private.cleanup_teacher_gemini_vault_secret()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from vault.secrets where id = old.secret_id;
  return old;
end;
$$;

drop trigger if exists teacher_gemini_credentials_delete_secret
  on private.teacher_gemini_credentials;
create trigger teacher_gemini_credentials_delete_secret
after delete on private.teacher_gemini_credentials
for each row execute function private.cleanup_teacher_gemini_vault_secret();

revoke all on function private.cleanup_teacher_gemini_vault_secret()
  from public, anon, authenticated;
