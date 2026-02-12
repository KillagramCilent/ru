import 'package:flutter/material.dart';
import '../../core/di/service_locator.dart';
import '../../data/telegram/api_exception.dart';
import '../../domain/repositories/auth_repository.dart';
import '../chats/chats_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final AuthRepository _authRepository = ServiceLocator.get<AuthRepository>();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _codeRequested = false;
  bool _loading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showError('Введите номер телефона');
      return;
    }
    setState(() => _loading = true);
    try {
      await _authRepository.requestCode(phone);
      if (!mounted) return;
      setState(() => _codeRequested = true);
    } on ApiException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _confirmCode() async {
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      _showError('Введите код');
      return;
    }
    setState(() => _loading = true);
    try {
      await _authRepository.confirmCode(
        phone: phone,
        code: code,
        password: _passwordController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ChatsScreen()),
      );
    } on ApiException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход в Killagram')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Номер телефона',
                hintText: '+79991234567',
              ),
            ),
            const SizedBox(height: 16),
            if (_codeRequested)
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Код из SMS'),
              ),
            if (_codeRequested) const SizedBox(height: 16),
            if (_codeRequested)
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Пароль 2FA (если включен)',
                ),
              ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading
                  ? null
                  : _codeRequested
                      ? _confirmCode
                      : _requestCode,
              child: Text(_codeRequested ? 'Подтвердить' : 'Получить код'),
            ),
          ],
        ),
      ),
    );
  }
}
