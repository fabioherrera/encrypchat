import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Local contact (public material only — never stores secrets).
@immutable
class Contact {
  const Contact({
    required this.token,
    required this.publicKey,
    this.displayName,
    this.createdAt,
  });

  final String token;
  final Uint8List publicKey;
  final String? displayName;
  final DateTime? createdAt;

  String get publicKeyHex =>
      publicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  String get label {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    if (token.length > 14) return '${token.substring(0, 10)}…${token.substring(token.length - 4)}';
    return token;
  }

  Map<String, Object?> toMap() => {
        'token': token,
        'public_key': publicKey,
        'display_name': displayName,
        'created_at': (createdAt ?? DateTime.now().toUtc()).toIso8601String(),
      };

  factory Contact.fromMap(Map<String, Object?> map) {
    final key = map['public_key'];
    final Uint8List pub;
    if (key is Uint8List) {
      pub = key;
    } else if (key is List<int>) {
      pub = Uint8List.fromList(key);
    } else {
      throw FormatException('contact public_key missing');
    }
    return Contact(
      token: map['token']! as String,
      publicKey: pub,
      displayName: map['display_name'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at']! as String)
          : null,
    );
  }

  /// `encrypchat:contact:v1:<token>:<pubkey_hex>:<display_name>`
  String exportLine() {
    final name = Uri.encodeComponent(displayName ?? '');
    return 'encrypchat:contact:v1:$token:$publicKeyHex:$name';
  }

  static Contact parseExport(String raw) {
    final trimmed = raw.trim();
    final parts = trimmed.split(':');
    if (parts.length < 5 ||
        parts[0] != 'encrypchat' ||
        parts[1] != 'contact' ||
        parts[2] != 'v1') {
      throw const FormatException('Invalid contact export');
    }
    final token = parts[3];
    final hex = parts[4];
    final namePart = parts.length > 5 ? parts.sublist(5).join(':') : '';
    final pub = _hexToBytes(hex);
    if (!_tokenMatchesPublicKey(token, pub)) {
      throw const FormatException('Token does not match public key');
    }
    final name = namePart.isEmpty ? null : Uri.decodeComponent(namePart);
    return Contact(
      token: token.toLowerCase(),
      publicKey: pub,
      displayName: (name == null || name.isEmpty) ? null : name,
      createdAt: DateTime.now().toUtc(),
    );
  }
}

bool isValidToken(String token) {
  final t = token.trim().toLowerCase();
  if (!t.startsWith('ec_') || t.length != 67) return false;
  final hex = t.substring(3);
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(hex);
}

bool _tokenMatchesPublicKey(String token, Uint8List publicKey) {
  if (publicKey.length != 32) return false;
  final digest = sha256.convert(publicKey);
  final expected = 'ec_${digest.toString()}';
  return expected == token.trim().toLowerCase();
}

Uint8List _hexToBytes(String hex) {
  final cleaned = hex.trim().toLowerCase();
  if (cleaned.length != 64 || !RegExp(r'^[0-9a-f]+$').hasMatch(cleaned)) {
    throw const FormatException('Invalid public key hex');
  }
  final out = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    out[i] = int.parse(cleaned.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Optional JSON helper for tests / debug (no secrets).
String contactsToJson(List<Contact> contacts) {
  return jsonEncode([
    for (final c in contacts)
      {
        'token': c.token,
        'public_key_hex': c.publicKeyHex,
        'display_name': c.displayName,
      },
  ]);
}
