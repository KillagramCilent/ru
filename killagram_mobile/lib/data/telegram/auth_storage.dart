import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthStorage {
  static const _tokenKey = 'killagram_token';
  static const _phoneKey = 'killagram_phone';

  AuthStorage(this._storage);

  final FlutterSecureStorage _storage;

  Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> savePhone(String phone) async {
    await _storage.write(key: _phoneKey, value: phone);
  }

  Future<String?> readToken() async => _storage.read(key: _tokenKey);

  Future<String?> readPhone() async => _storage.read(key: _phoneKey);

  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _phoneKey);
  }
}
