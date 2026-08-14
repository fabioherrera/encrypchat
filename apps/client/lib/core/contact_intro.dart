import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// First hello after adding someone. Carries the sender's public key so a
/// P2P-only request can be accepted — an `EC04` frame otherwise only has the
/// token, and Accept would stay disabled.
///
/// JSON UTF-8: `{"v":1,"kind":"intro","token":"ec_…","pub":"<64 hex>"}`.
class ContactIntro {
  const ContactIntro({required this.token, required this.publicKey});

  static const schemaVersion = 1;
  static const kind = 'intro';
  static const preview = 'Quiere agregarte como contacto';

  final String token;
  final Uint8List publicKey;

  String get publicKeyHex =>
      publicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  bool get keyMatchesToken {
    if (publicKey.length != 32) return false;
    return 'ec_${sha256.convert(publicKey)}' == token.trim().toLowerCase();
  }

  /// True when this intro is the same identity the frame already authenticated.
  bool matchesSender(String senderToken) =>
      token.trim().toLowerCase() == senderToken.trim().toLowerCase() &&
      keyMatchesToken;

  Uint8List encode() {
    if (!keyMatchesToken) {
      throw StateError('intro token does not match public key');
    }
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'v': schemaVersion,
          'kind': kind,
          'token': token.trim().toLowerCase(),
          'pub': publicKeyHex,
        }),
      ),
    );
  }

  static bool looksLike(Uint8List bytes) {
    if (bytes.isEmpty || bytes[0] != 0x7b) return false;
    try {
      final map = jsonDecode(utf8.decode(bytes));
      return map is Map && map['kind'] == kind && map['v'] == schemaVersion;
    } catch (_) {
      return false;
    }
  }

  static ContactIntro? tryDecode(Uint8List bytes) {
    if (!looksLike(bytes)) return null;
    try {
      final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final token = (map['token'] as String?)?.trim().toLowerCase() ?? '';
      final hex = (map['pub'] as String?)?.trim().toLowerCase() ?? '';
      if (token.isEmpty || hex.length != 64) return null;
      if (!RegExp(r'^[0-9a-f]+$').hasMatch(hex)) return null;
      final pub = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        pub[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      }
      final intro = ContactIntro(token: token, publicKey: pub);
      if (!intro.keyMatchesToken) return null;
      return intro;
    } catch (_) {
      return null;
    }
  }
}
