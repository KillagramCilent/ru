import '../../domain/repositories/auth_repository.dart';
import 'auth_storage.dart';
import 'telegram_gateway.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._gateway, this._storage);

  final TelegramGateway _gateway;
  final AuthStorage _storage;

  @override
  Future<void> requestCode(String phone) {
    return _gateway.requestCode(phone);
  }

  @override
  Future<void> confirmCode({
    required String phone,
    required String code,
    String? password,
  }) {
    return _gateway.confirmCode(phone: phone, code: code, password: password);
  }

  @override
  Future<bool> hasSession() async {
    final token = await _storage.readToken();
    final phone = await _storage.readPhone();
    return token != null && phone != null;
  }

  @override
  Future<String?> currentPhone() => _storage.readPhone();

  @override
  Future<void> logout() => _storage.clear();
}
