import 'dart:typed_data';

import 'package:flutter/foundation.dart';

enum MessageDirection { outbound, inbound }

enum MessageStatus { sending, sent, delivered, error }

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.peerToken,
    required this.direction,
    required this.bodySealed,
    required this.status,
    required this.createdAt,
    this.plaintext,
    this.error,
  });

  final String id;
  final String peerToken;
  final MessageDirection direction;

  /// At-rest AEAD blob (`local_seal` with db_key). Never plaintext on disk.
  final Uint8List bodySealed;
  final MessageStatus status;
  final DateTime createdAt;

  /// Decrypted for UI only (memory).
  final String? plaintext;
  final String? error;

  ChatMessage copyWith({
    MessageStatus? status,
    String? plaintext,
    String? error,
    Uint8List? bodySealed,
  }) {
    return ChatMessage(
      id: id,
      peerToken: peerToken,
      direction: direction,
      bodySealed: bodySealed ?? this.bodySealed,
      status: status ?? this.status,
      createdAt: createdAt,
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
    return ChatMessage(
      id: map['id']! as String,
      peerToken: map['peer_token']! as String,
      direction: MessageDirection.values.byName(map['direction']! as String),
      bodySealed: body,
      status: MessageStatus.values.byName(map['status']! as String),
      createdAt: DateTime.parse(map['created_at']! as String),
      plaintext: plaintext,
    );
  }
}
