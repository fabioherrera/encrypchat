import 'package:flutter/foundation.dart';

/// Someone who is not a contact wrote to this device.
///
/// Their messages are stored like any other conversation, but the identity is
/// not in `contacts`, so it needs a row of its own: without one, the chat list
/// (which walks contacts) would never show it, and the user could not read,
/// delete or block what arrived — that was F-6.
@immutable
class MessageRequest {
  const MessageRequest({
    required this.peerToken,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.messageCount,
    this.publicKey,
    this.viaRelay = false,
  });

  final String peerToken;

  /// The sender's X25519 public key, when the route that carried the message
  /// authenticated it: `sealed_open` hands it over, an `EC04` frame only
  /// carries the token. Without it the request can be read and blocked but not
  /// accepted, because replying needs the key.
  final Uint8List? publicKey;

  final DateTime firstSeenAt;
  final DateTime lastSeenAt;

  /// Messages admitted from this identity while it is still a request. Bounded:
  /// see `MessagingService.maxRequestMessagesPerPeer`.
  final int messageCount;

  final bool viaRelay;

  /// Accepting means creating a contact, which needs the public key.
  bool get canAccept => publicKey != null;

  String get shortToken => peerToken.length > 14
      ? '${peerToken.substring(0, 10)}…${peerToken.substring(peerToken.length - 4)}'
      : peerToken;

  factory MessageRequest.fromMap(Map<String, Object?> map) {
    final key = map['public_key'];
    return MessageRequest(
      peerToken: map['peer_token']! as String,
      publicKey: key is Uint8List
          ? key
          : (key is List<int> ? Uint8List.fromList(key) : null),
      firstSeenAt:
          DateTime.tryParse(map['first_seen_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      lastSeenAt:
          DateTime.tryParse(map['last_seen_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      messageCount: (map['message_count'] as num?)?.toInt() ?? 0,
      viaRelay: ((map['via_relay'] as num?)?.toInt() ?? 0) != 0,
    );
  }
}

/// Why a message from a non-contact was or was not stored.
enum RequestAdmission {
  /// Stored, and the request is visible in the inbox.
  admitted,

  /// Too many distinct strangers are already pending: nothing is stored, and
  /// the UI says so instead of dropping in silence.
  inboxFull,

  /// This stranger already used every slot it gets before being accepted.
  senderFull,
}
