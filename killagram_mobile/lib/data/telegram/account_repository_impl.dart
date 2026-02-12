import '../../domain/entities/account_state.dart';
import '../../domain/repositories/account_repository.dart';
import 'telegram_gateway.dart';

class AccountRepositoryImpl implements AccountRepository {
  AccountRepositoryImpl(this._gateway);

  final TelegramGateway _gateway;

  @override
  Future<AccountState> getMe() {
    return _gateway.fetchMe();
  }

  @override
  Future<void> appealFreeze(String text) {
    return _gateway.appealFreeze(text);
  }

  @override
  Stream<AccountState> watchAccountUpdates() async* {
    await for (final event in _gateway.subscribeEvents()) {
      if (event['event_type'] != 'account_status_updated') {
        continue;
      }
      final payload = event['payload'] as Map<String, dynamic>? ?? {};
      final current = await getMe();
      yield AccountState(
        id: current.id,
        phone: current.phone,
        status: payload['status']?.toString() ?? current.status,
        freezeReason: payload['freeze_reason'] as String? ?? current.freezeReason,
        premium: current.premium,
        starsBalance: current.starsBalance,
      );
    }
  }
}
