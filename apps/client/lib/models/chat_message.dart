import 'dart:typed_data';

import 'package:flutter/foundation.dart';

enum MessageDirection { outbound, inbound }

/// How far an outbound message got — and, for the two that are not a
/// confirmation, how far it is honest to say it got.
///
/// [delivered] is the only delivery there is: `node_send` waits for the peer's
/// own ACK, so the message reached their device.
///
/// [viaRelay] is **not** one. It says the relay accepted the blob and nothing
/// beyond that: a relay whose mailbox for that token is over quota now answers
/// an enqueue exactly like it answers an acceptance — same status, same body,
/// an id that names no row — because the difference was a presence oracle,
/// letting anyone holding a token fill the mailbox and then probe to learn
/// whether that person had come online to empty it. This device cannot tell the
/// two apart and never will: the honest sender and the attacker send the same
/// request. Everything on screen has to fit inside "handed to the relay".
///
/// [sent] is only in rows migrated from the pre-F5 schema, where there was no
/// distinction to make.
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
