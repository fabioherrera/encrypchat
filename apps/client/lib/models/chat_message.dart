import 'dart:typed_data';

import 'package:flutter/foundation.dart';

enum MessageDirection { outbound, inbound }

enum MessageStatus { sending, sent, delivered, viaRelay, error }

enum MessageKind { text, media }

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.peerToken,
    required this.direction,
    required this.bodySealed,
    required this.status,
    required this.createdAt,
    this.kind = MessageKind.text,
    this.mime,
    this.mediaRelPath,
    this.plaintext,
    this.error,
  });

  final String id;
  final String peerToken;
  final MessageDirection direction;
  final Uint8List bodySealed;
  final MessageStatus status;
  final DateTime createdAt;
  final MessageKind kind;
  final String? mime;
  final String? mediaRelPath;

  /// Decrypted caption / text for UI (memory).
  ///
  /// Media bytes are deliberately absent: they stay sealed on disk and are read
  /// on demand ([MessagingService.mediaBytesFor]) so the cache cannot retain them.
  final String? plaintext;
  final String? error;

  bool get isMedia => kind == MessageKind.media;

  ChatMessage copyWith({
    MessageStatus? status,
    String? plaintext,
    String? error,
    Uint8List? bodySealed,
    String? mediaRelPath,
    MessageKind? kind,
    String? mime,
  }) {
    return ChatMessage(
      id: id,
      peerToken: peerToken,
      direction: direction,
      bodySealed: bodySealed ?? this.bodySealed,
      status: status ?? this.status,
      createdAt: createdAt,
      kind: kind ?? this.kind,
      mime: mime ?? this.mime,
      mediaRelPath: mediaRelPath ?? this.mediaRelPath,
      plaintext: plaintext ?? this.plaintext,
      error: error,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'peer_token': peerToken,
    'direction': direction.name,
    'body_sealed': bodySealed,
    'status': status.name,
    'created_at': createdAt.toUtc().toIso8601String(),
    'kind': kind.name,
    'mime': mime,
    'media_relpath': mediaRelPath,
  };

  factory ChatMessage.fromMap(Map<String, Object?> map, {String? plaintext}) {
    final sealed = map['body_sealed'];
    final Uint8List body;
    if (sealed is Uint8List) {
      body = sealed;
    } else if (sealed is List<int>) {
      body = Uint8List.fromList(sealed);
    } else {
      throw FormatException('body_sealed missing');
    }
    final kindName = map['kind'] as String? ?? 'text';
    return ChatMessage(
      id: map['id']! as String,
      peerToken: map['peer_token']! as String,
      direction: MessageDirection.values.byName(map['direction']! as String),
      bodySealed: body,
      status: MessageStatus.values.byName(map['status']! as String),
      createdAt: DateTime.parse(map['created_at']! as String),
      kind: MessageKind.values.byName(kindName),
      mime: map['mime'] as String?,
      mediaRelPath: map['media_relpath'] as String?,
      plaintext: plaintext,
    );
  }
}
