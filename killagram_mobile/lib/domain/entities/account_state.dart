import 'package:equatable/equatable.dart';

class AccountState extends Equatable {
  const AccountState({
    required this.id,
    required this.phone,
    required this.status,
    required this.freezeReason,
    required this.premium,
    required this.starsBalance,
  });

  final String id;
  final String phone;
  final String status;
  final String? freezeReason;
  final bool premium;
  final int starsBalance;

  bool get isFrozen => status == 'frozen';
  bool get isPremium => premium;

  @override
  List<Object?> get props => [id, phone, status, freezeReason, premium, starsBalance];
}
