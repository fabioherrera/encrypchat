import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// A contact card that cannot be imported, and never will be.
///
/// Separate from a transient failure on purpose: nothing about retrying a
/// malformed card helps, so the UI must say what is wrong with *the card* and
/// point at getting a new one, instead of offering another attempt.
class ContactCardException implements Exception {
  const ContactCardException(this.message);

  /// Shown as-is: describes the card, never key material.
  final String message;

  /// The shape is wrong: not an export line at all, or truncated.
  static const unreadable = ContactCardException(
    'Esa tarjeta de contacto no se pudo leer. Tiene que empezar con '
    '"encrypchat:contact:v1:" y llegar completa: pedile que la exporte de '
    'nuevo, o volvé a escanear el QR entero.',
  );

  /// A bare `ec_…` token. Identity is the token, but encryption needs the
  /// public key that only travels in the export line / QR.
  static const tokenOnly = ContactCardException(
    'Eso es solo el token. Sin la clave pública no se puede cifrar: pedile '
    'que toque Exportar contacto en Mi token y te pase esa línea completa '
    '(empieza con encrypchat:contact:v1:).',
  );

  /// Token and public key do not agree, so one of the two was altered in
  /// transit or copied by halves.
  static const tokenMismatch = ContactCardException(
    'El token de esa tarjeta no corresponde a su clave pública. Está alterada '
    'o quedó mal copiada: pedile la tarjeta otra vez y no la edites a mano.',
  );

  /// The core refused the key: `InvalidPublicKey` (2). Either degenerate, or a
  /// non-canonical encoding of a real key — which is an identity that would get
  /// its own token and, with it, a way around a block (F-10). Not something to
  /// "fix" here; see invariant 14 in `docs/ffi-contract.md`.
  static const malformedKey = ContactCardException(
    'La clave pública de esa tarjeta está mal codificada, así que no se puede '
    'usar como identidad. No es un problema de red: la tarjeta está mal. '
    'Pedile que la genere de nuevo con una versión al día de Encrypchat.',
  );

  @override
  String toString() => 'ContactCardException: $message';
}

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
    if (token.length > 14)
      return '${token.substring(0, 10)}…${token.substring(token.length - 4)}';
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

  /// True for a complete export line or for the QR that carries the same
  /// string. A bare `ec_…` token is not a card: it has no public key, so it
  /// cannot be imported.
  static bool looksLikeCard(String raw) =>
      raw.trim().startsWith('encrypchat:contact:v1:');

  /// Parses an export line or a scanned QR (they carry the same string).
  ///
  /// The 32 bytes come out exactly as they were written: this never masks,
  /// reduces or otherwise "repairs" an encoding. Whether the core accepts the
  /// key is the core's call — see `EncrypchatCore.assertUsablePublicKey`.
  static Contact parseExport(String raw) {
    final trimmed = raw.trim();
    if (isValidToken(trimmed)) {
      throw ContactCardException.tokenOnly;
    }
    final parts = trimmed.split(':');
    if (parts.length < 5 ||
        parts[0] != 'encrypchat' ||
        parts[1] != 'contact' ||
        parts[2] != 'v1') {
      throw ContactCardException.unreadable;
    }
    final token = parts[3];
    final hex = parts[4];
    final namePart = parts.length > 5 ? parts.sublist(5).join(':') : '';
    final pub = _hexToBytes(hex);
    if (!_tokenMatchesPublicKey(token, pub)) {
      throw ContactCardException.tokenMismatch;
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
    throw ContactCardException.unreadable;
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
