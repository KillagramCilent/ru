import 'package:flutter/material.dart';
import 'core/config/layout_breakpoints.dart';
import 'core/di/service_locator.dart';
import 'core/theme/killagram_theme.dart';
import 'domain/repositories/auth_repository.dart';
import 'features/auth/auth_screen.dart';
import 'features/chats/chats_screen.dart';
import 'features/desktop/desktop_home_screen.dart';

class KillagramApp extends StatelessWidget {
  const KillagramApp({super.key});

  @override
  Widget build(BuildContext context) {
    final authRepository = ServiceLocator.get<AuthRepository>();
    return MaterialApp(
      title: 'Killagram',
      theme: KillagramTheme.light,
      darkTheme: KillagramTheme.dark,
      home: FutureBuilder<bool>(
        future: authRepository.hasSession(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final hasSession = snapshot.data ?? false;
          if (!hasSession) {
            return const AuthScreen();
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop =
                  constraints.maxWidth >= LayoutBreakpoints.desktop;
              return isDesktop
                  ? const DesktopHomeScreen()
                  : const ChatsScreen();
            },
          );
        },
      ),
    );
  }
}
