import 'package:equatable/equatable.dart';

enum OutgoingMessageState { pending, sending, failed, sent }

class Message extends Equatable {
  const Message({
    required this.id,
    required this.chatId,
    required this.sender,
    required this.text,
    required this.timestamp,
    required this.isOutgoing,
    this.reactions = const {},
    this.myReactions = const [],
    this.canEdit = false,
    this.isRead = false,
    this.isPinned = false,
    this.isSystem = false,
    this.systemEventType,
    this.systemPayload = const {},
    this.contentType = 'text',
    this.hasDownloadableFile = false,
    this.replyToId,
    this.replyPreview,
    this.forwardedFrom,
    this.scheduledAt,
    this.voiceDuration,
    this.mentions = const [],
    this.hashtags = const [],
    this.editVersionsCount = 0,
    this.outgoingState = OutgoingMessageState.sent,
    this.clientMessageId,
    this.isImportant = false,
    this.localNote,
    this.isLocalPinned = false,
    this.appliedAutomationRuleIds = const [],
  });

  final String id;
  final String chatId;
  final String sender;
  final String text;
  final DateTime timestamp;
  final bool isOutgoing;
  final Map<String, int> reactions;
  final List<String> myReactions;
  final bool canEdit;
  final bool isRead;
  final bool isPinned;
  final bool isSystem;
  final String? systemEventType;
  final Map<String, dynamic> systemPayload;
  final String contentType;
  final bool hasDownloadableFile;
  final String? replyToId;
  final String? replyPreview;
  final String? forwardedFrom;
  final DateTime? scheduledAt;
  final int? voiceDuration;
  final List<String> mentions;
  final List<String> hashtags;
  final int editVersionsCount;
  final OutgoingMessageState outgoingState;
  final String? clientMessageId;
  final bool isImportant;
  final String? localNote;
  final bool isLocalPinned;
  final List<String> appliedAutomationRuleIds;

  Message copyWith({
    String? id,
    String? text,
    DateTime? timestamp,
    Map<String, int>? reactions,
    List<String>? myReactions,
    bool? canEdit,
    bool? isRead,
    bool? isPinned,
    bool? isSystem,
    String? systemEventType,
    Map<String, dynamic>? systemPayload,
    String? contentType,
    bool? hasDownloadableFile,
    String? replyToId,
    String? replyPreview,
    String? forwardedFrom,
    DateTime? scheduledAt,
    int? voiceDuration,
    List<String>? mentions,
    List<String>? hashtags,
    int? editVersionsCount,
    OutgoingMessageState? outgoingState,
    String? clientMessageId,
    bool? isImportant,
    String? localNote,
    bool? isLocalPinned,
    List<String>? appliedAutomationRuleIds,
  }) {
    return Message(
      id: id ?? this.id,
      chatId: chatId,
      sender: sender,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      isOutgoing: isOutgoing,
      reactions: reactions ?? this.reactions,
      myReactions: myReactions ?? this.myReactions,
      canEdit: canEdit ?? this.canEdit,
      isRead: isRead ?? this.isRead,
      isPinned: isPinned ?? this.isPinned,
      isSystem: isSystem ?? this.isSystem,
      systemEventType: systemEventType ?? this.systemEventType,
      systemPayload: systemPayload ?? this.systemPayload,
      contentType: contentType ?? this.contentType,
      hasDownloadableFile: hasDownloadableFile ?? this.hasDownloadableFile,
      replyToId: replyToId ?? this.replyToId,
      replyPreview: replyPreview ?? this.replyPreview,
      forwardedFrom: forwardedFrom ?? this.forwardedFrom,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      voiceDuration: voiceDuration ?? this.voiceDuration,
      mentions: mentions ?? this.mentions,
      hashtags: hashtags ?? this.hashtags,
      editVersionsCount: editVersionsCount ?? this.editVersionsCount,
      outgoingState: outgoingState ?? this.outgoingState,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      isImportant: isImportant ?? this.isImportant,
      localNote: localNote ?? this.localNote,
      isLocalPinned: isLocalPinned ?? this.isLocalPinned,
      appliedAutomationRuleIds: appliedAutomationRuleIds ?? this.appliedAutomationRuleIds,
    );
  }

  @override
  List<Object?> get props => [
        id,
        chatId,
        sender,
        text,
        timestamp,
        isOutgoing,
        reactions,
        myReactions,
        canEdit,
        isRead,
        isPinned,
        isSystem,
        systemEventType,
        systemPayload,
        contentType,
        hasDownloadableFile,
        replyToId,
        replyPreview,
        forwardedFrom,
        scheduledAt,
        voiceDuration,
        mentions,
        hashtags,
        editVersionsCount,
        outgoingState,
        clientMessageId,
        isImportant,
        localNote,
        isLocalPinned,
        appliedAutomationRuleIds,
      ];
}
