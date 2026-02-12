abstract class AuthRepository {
  Future<void> requestCode(String phone);
  Future<void> confirmCode({
    required String phone,
    required String code,
    String? password,
  });
  Future<bool> hasSession();
  Future<String?> currentPhone();
  Future<void> logout();
}
