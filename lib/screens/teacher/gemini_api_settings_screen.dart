import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/teacher_gemini_key_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_feedback.dart';
import '../../widgets/studexa_background.dart';

class GeminiApiSettingsScreen extends StatefulWidget {
  const GeminiApiSettingsScreen({super.key, this.service});

  final TeacherGeminiKeyService? service;

  @override
  State<GeminiApiSettingsScreen> createState() =>
      _GeminiApiSettingsScreenState();
}

class _GeminiApiSettingsScreenState extends State<GeminiApiSettingsScreen> {
  static const _apiKeysUrl = 'https://aistudio.google.com/api-keys';
  late final TeacherGeminiKeyService _service =
      widget.service ?? TeacherGeminiKeyService();
  final _controller = TextEditingController();
  TeacherGeminiKeyStatus? _status;
  bool _loading = true;
  bool _saving = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final status = await _service.getStatus();
      if (mounted) {
        setState(() {
          _status = status;
          _loading = false;
        });
      }
    } on TeacherGeminiKeyException catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppFeedback.error(context, error.message, title: 'Settings unavailable');
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(const ClipboardData(text: _apiKeysUrl));
    if (mounted) {
      AppFeedback.success(
        context,
        'Google AI Studio API Keys link copied to your clipboard.',
        title: 'Link copied',
      );
    }
  }

  Future<void> _save() async {
    final key = _controller.text.trim();
    if (key.isEmpty) {
      AppFeedback.warning(context, 'Paste your Gemini API key first.');
      return;
    }
    setState(() => _saving = true);
    try {
      final status = await _service.saveAndVerify(key);
      _controller.clear();
      if (!mounted) return;
      setState(() {
        _status = status;
        _saving = false;
      });
      AppFeedback.success(
        context,
        'Google verified the key. Studexa will use it for your quiz generation.',
        title: 'API key saved',
      );
    } on TeacherGeminiKeyException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppFeedback.error(context, error.message, title: 'Key not saved');
    }
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Gemini API key?'),
        content: const Text(
          'Your temporary generation allowance will not reset. You can add another personal key later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove key'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final status = await _service.remove();
      if (!mounted) return;
      setState(() {
        _status = status;
        _saving = false;
      });
      AppFeedback.success(context, 'Your personal Gemini API key was removed.');
    } on TeacherGeminiKeyException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppFeedback.error(context, error.message, title: 'Key not removed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gemini API Settings')),
      body: StudexaBackground(
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: ListView(
                      padding: const EdgeInsets.all(AppTheme.spacingXl),
                      children: [
                        _StatusCard(status: _status),
                        const SizedBox(height: AppTheme.spacingLg),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(AppTheme.spacingLg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _status?.configured == true
                                      ? 'Replace your key'
                                      : 'Add your personal key',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'The complete key is sent securely for verification and is never shown again in Studexa.',
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  key: const Key('gemini_api_key_input'),
                                  controller: _controller,
                                  obscureText: _obscure,
                                  enableSuggestions: false,
                                  autocorrect: false,
                                  decoration: InputDecoration(
                                    labelText: 'Gemini API key',
                                    hintText: 'Paste your key here',
                                    prefixIcon: const Icon(Icons.key_rounded),
                                    suffixIcon: IconButton(
                                      tooltip: _obscure
                                          ? 'Show key'
                                          : 'Hide key',
                                      onPressed: () =>
                                          setState(() => _obscure = !_obscure),
                                      icon: Icon(
                                        _obscure
                                            ? Icons.visibility_rounded
                                            : Icons.visibility_off_rounded,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    key: const Key('save_verify_gemini_key'),
                                    onPressed: _saving ? null : _save,
                                    icon: _saving
                                        ? const SizedBox.square(
                                            dimension: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.verified_rounded),
                                    label: const Text('Save and Verify'),
                                  ),
                                ),
                                if (_status?.configured == true) ...[
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    child: TextButton.icon(
                                      key: const Key('remove_gemini_key'),
                                      onPressed: _saving ? null : _remove,
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                      ),
                                      label: const Text('Remove saved key'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppTheme.spacingLg),
                        _GuideCard(onCopyLink: _copyLink),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});
  final TeacherGeminiKeyStatus? status;

  @override
  Widget build(BuildContext context) {
    final ready = status?.isReady == true;
    final configured = status?.configured == true;
    return Card(
      color: ready ? AppTheme.successContainer : AppTheme.warningContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              ready ? Icons.verified_user_rounded : Icons.key_off_rounded,
              color: ready ? AppTheme.success : AppTheme.warning,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ready
                        ? 'Configured ${status?.maskedKey ?? ''}'
                        : configured
                        ? 'Saved key needs replacement'
                        : 'No personal key configured',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ready
                        ? 'Personal key active • ${status!.fallbackRemainingToday} Studexa fallback sessions remain today.'
                        : '${status?.graceRemaining ?? 0} of 3 lifetime temporary generations remain.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.onCopyLink});
  final VoidCallback onCopyLink;

  static const steps = [
    'Open the official Google AI Studio API Keys page.',
    'Sign in with your own Google account and accept the terms if requested.',
    'Open Dashboard → Projects.',
    'Use the default project Google creates for you, or create/import a Google Cloud project that you own. Do not use another teacher’s project.',
    'Open API Keys and select Create API key. Google AI Studio creates the recommended authorization-key type by default.',
    'Select your own project and create the key.',
    'Copy the generated key.',
    'Return to Studexa, paste it above, and select Save and Verify.',
    'Check usage later through Google AI Studio → Dashboard → Usage or Rate limits.',
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How to get your API key',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const SelectableText(
              'https://aistudio.google.com/api-keys',
              style: TextStyle(color: AppTheme.info),
            ),
            TextButton.icon(
              key: const Key('copy_ai_studio_link'),
              onPressed: onCopyLink,
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy Link'),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${i + 1}.',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Expanded(child: Text(steps[i])),
                  ],
                ),
              ),
            const Divider(height: 28),
            const Text(
              'Safety and billing',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              '• The free tier can be used without paid billing, subject to Google’s current quotas.\n'
              '• You are responsible for charges if you voluntarily enable a paid Gemini tier.\n'
              '• Never share your key with students, other teachers, chat messages, or public files.\n'
              '• If a key leaks, revoke it in Google AI Studio and replace it in Studexa.\n'
              '• If Create API key is unavailable, use a project you own, try an eligible personal Google account, or contact your Google Workspace administrator.',
            ),
          ],
        ),
      ),
    );
  }
}
