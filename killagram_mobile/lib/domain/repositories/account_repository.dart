import '../entities/account_state.dart';

abstract class AccountRepository {
  Future<AccountState> getMe();
  Future<void> appealFreeze(String text);
  Stream<AccountState> watchAccountUpdates();
}
