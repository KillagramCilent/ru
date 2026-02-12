import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/state/local_pro_controller.dart';
import '../../core/state/ui_settings_controller.dart';
import '../../core/state/ai_controller.dart';
import '../../core/ai/ai_provider_type.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uiSettings = ServiceLocator.get<UiSettingsController>();
    final localPro = ServiceLocator.get<LocalProController>();
    final isDesktop = MediaQuery.of(context).size.width >= 1024;
    final aiController = ServiceLocator.get<AiController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        children: [
          const _SettingsTile(
            icon: Icons.person,
            title: 'Профиль',
            subtitle: 'Killagram User · @killagram',
          ),
          const _SettingsTile(
            icon: Icons.notifications,
            title: 'Уведомления',
            subtitle: 'Управление звуками и вибрацией',
          ),
          const _SettingsTile(
            icon: Icons.lock,
            title: 'Конфиденциальность и безопасность',
            subtitle: '2FA, блокировка, активные сессии',
          ),
          ValueListenableBuilder<MessageDensityMode>(
            valueListenable: uiSettings.densityMode,
            builder: (context, density, _) => ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                child: Icon(Icons.density_medium, color: Theme.of(context).colorScheme.primary),
              ),
              title: const Text('Плотность сообщений'),
              subtitle: const Text('Compact / Comfortable / Airy'),
              trailing: DropdownButton<MessageDensityMode>(
                value: density,
                onChanged: (value) {
                  if (value == null) return;
                  uiSettings.setDensityMode(value);
                },
                items: const [
                  DropdownMenuItem(value: MessageDensityMode.compact, child: Text('Compact')),
                  DropdownMenuItem(value: MessageDensityMode.comfortable, child: Text('Comfortable')),
                  DropdownMenuItem(value: MessageDensityMode.airy, child: Text('Airy')),
                ],
              ),
            ),
          ),
          if (isDesktop)
            ValueListenableBuilder<bool>(
              valueListenable: localPro.enabled,
              builder: (context, enabled, _) => Column(
                children: [
                  SwitchListTile(
                    title: const Text('Killagram Pro (Local)'),
                    subtitle: const Text('Функции работают только на этом устройстве'),
                    value: enabled,
                    onChanged: localPro.setEnabled,
                    secondary: const Icon(Icons.workspace_premium),
                  ),
                  ValueListenableBuilder<String>(
                    valueListenable: localPro.userLocalEmoji,
                    builder: (context, emoji, __) => ListTile(
                      leading: const Icon(Icons.emoji_emotions_outlined),
                      title: const Text('Local Emoji Near Username'),
                      subtitle: Text(emoji.isEmpty ? 'Не задано' : emoji),
                      trailing: SizedBox(
                        width: 120,
                        child: TextField(
                          controller: TextEditingController(text: emoji),
                          enabled: enabled,
                          onSubmitted: (value) => localPro.setUserLocalEmoji(value.trim()),
                          decoration: const InputDecoration(hintText: '🙂'),
                        ),
                      ),
                    ),
                  ),
                  if (!enabled)
                    const ListTile(
                      leading: Icon(Icons.lock_outline, color: Colors.orange),
                      title: Text('FEATURE_LOCKED'),
                      subtitle: Text('Включите Killagram Pro (Local) для расширенных локальных функций'),
                    ),
                ],
              ),
            ),

          if (isDesktop)
            ValueListenableBuilder<AiProviderType>(
              valueListenable: aiController.provider,
              builder: (context, provider, _) => Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.psychology_outlined),
                    title: const Text('AI Provider (Desktop Pro)'),
                    subtitle: const Text('OpenAI / Grok / Gemini / DeepSeek'),
                    trailing: DropdownButton<AiProviderType>(
                      value: provider,
                      onChanged: (value) {
                        if (value == null) return;
                        aiController.setProvider(value);
                      },
                      items: AiProviderType.values
                          .map((it) => DropdownMenuItem(value: it, child: Text(it.label)))
                          .toList(),
                    ),
                  ),
                  FutureBuilder<String>(
                    future: aiController.getApiKey(provider),
                    builder: (context, snapshot) {
                      final keyController = TextEditingController(text: snapshot.data ?? '');
                      return ListTile(
                        leading: const Icon(Icons.vpn_key_outlined),
                        title: Text('${provider.label} API key'),
                        subtitle: const Text('Stored locally on this device. Not sent to backend.'),
                        trailing: SizedBox(
                          width: 300,
                          child: TextField(
                            controller: keyController,
                            obscureText: true,
                            onSubmitted: (value) => aiController.setApiKey(provider, value),
                            decoration: const InputDecoration(hintText: 'Enter API key and press Enter'),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          const _SettingsTile(
            icon: Icons.extension,
            title: 'Плагины',
            subtitle: 'Управление расширениями Killagram',
          ),
          const _SettingsTile(
            icon: Icons.auto_awesome,
            title: 'AI-ассистент',
            subtitle: 'Резюме, перевод, умные ответы',
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}
