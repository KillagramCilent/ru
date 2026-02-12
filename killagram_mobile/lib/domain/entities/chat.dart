import 'package:equatable/equatable.dart';

class Chat extends Equatable {
  const Chat({
    required this.id,
    required this.title,
    required this.lastMessage,
    required this.unreadCount,
    required this.avatarUrl,
    required this.isMuted,
    this.isSavedMessages = false,
    this.verificationStatus = 'unverified',
    this.verificationProvider = 'none',
    this.verificationProviderName,
    this.verificationBadgeIconUrl,
  });

  final String id;
  final String title;
  final String lastMessage;
  final int unreadCount;
  final String avatarUrl;
  final bool isMuted;
  final bool isSavedMessages;
  final String verificationStatus;
  final String verificationProvider;
  final String? verificationProviderName;
  final String? verificationBadgeIconUrl;

  bool get isVerified => verificationStatus == 'verified';

  @override
  List<Object?> get props => [
        id,
        title,
        lastMessage,
        unreadCount,
        avatarUrl,
        isMuted,
        isSavedMessages,
        verificationStatus,
        verificationProvider,
        verificationProviderName,
        verificationBadgeIconUrl,
      ];
}
