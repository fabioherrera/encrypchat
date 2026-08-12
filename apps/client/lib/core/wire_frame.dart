import 'dart:math';
import 'dart:typed_data';

import 'package:encrypchat/models/contact.dart';

/// EC04 wire frame (matches `crates/core/src/frame.rs`).
class WireFrame {
  WireFrame({
    required this.msgId,
    required String senderToken,
    required this.ciphertext,
  }) : senderToken = senderToken.trim().toLowerCase();

  static const magic = [0x45, 0x43, 0x30, 0x34]; // EC04
  static const version = 1;
  static const msgIdLen = 16;

  final Uint8List msgId;
  final String senderToken;
  final Uint8List ciphertext;

  factory WireFrame.create({
    required String senderToken,
    required Uint8List ciphertext,
    Uint8List? msgId,
  }) {
    if (!isValidToken(senderToken)) {
      throw const FormatException('Invalid sender token');
    }
    if (ciphertext.isEmpty) {
      throw const FormatException('Empty ciphertext');
    }
    final id = msgId ?? _randomMsgId();
    if (id.length != msgIdLen) {
      throw const FormatException('msg_id must be 16 bytes');
    }
    return WireFrame(
      msgId: id,
      senderToken: senderToken,
      ciphertext: ciphertext,
    );
  }

  Uint8List encode() {
    final tokenBytes = Uint8List.fromList(senderToken.codeUnits);
    final builder = BytesBuilder(copy: false);
    builder.add(magic);
    builder.addByte(version);
    builder.add(msgId);
    builder.add(_u16be(tokenBytes.length));
    builder.add(tokenBytes);
    builder.add(_u32be(ciphertext.length));
    builder.add(ciphertext);
    return builder.toBytes();
  }

  static WireFrame decode(Uint8List bytes) {
    if (bytes.length < 4 + 1 + msgIdLen + 2 + 4) {
      throw const FormatException('Frame too short');
    }
    for (var i = 0; i < 4; i++) {
      if (bytes[i] != magic[i]) {
        throw const FormatException('Bad magic');
      }
    }
    if (bytes[4] != version) {
      throw const FormatException('Bad version');
    }
    var offset = 5;
    final msgId = Uint8List.fromList(bytes.sublist(offset, offset + msgIdLen));
    offset += msgIdLen;
    final tokenLen = _readU16be(bytes, offset);
    offset += 2;
    if (tokenLen == 0 || offset + tokenLen > bytes.length) {
      throw const FormatException('Bad token length');
    }
    final token = String.fromCharCodes(
      bytes.sublist(offset, offset + tokenLen),
    );
    offset += tokenLen;
    if (offset + 4 > bytes.length) {
      throw const FormatException('Missing ciphertext length');
    }
    final ctLen = _readU32be(bytes, offset);
    offset += 4;
    if (ctLen == 0 || offset + ctLen != bytes.length) {
      throw const FormatException('Bad ciphertext length');
    }
    final ct = Uint8List.fromList(bytes.sublist(offset, offset + ctLen));
    if (!isValidToken(token)) {
      throw const FormatException('Invalid token in frame');
    }
    // Matches `decode_frame` in core: one frame, one encoding. Accepting a
    // non-canonical token here would let the same frame arrive as two byte
    // strings, which breaks anything that caches or dedups on those bytes.
    if (token != token.trim().toLowerCase()) {
      throw const FormatException('Non-canonical token in frame');
    }
    return WireFrame(msgId: msgId, senderToken: token, ciphertext: ct);
  }

  static Uint8List _randomMsgId() {
    final rnd = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(msgIdLen, (_) => rnd.nextInt(256)),
    );
  }

  static Uint8List _u16be(int v) =>
      Uint8List.fromList([(v >> 8) & 0xff, v & 0xff]);

  static Uint8List _u32be(int v) => Uint8List.fromList([
    (v >> 24) & 0xff,
    (v >> 16) & 0xff,
    (v >> 8) & 0xff,
    v & 0xff,
  ]);

  static int _readU16be(Uint8List b, int o) => (b[o] << 8) | b[o + 1];

  static int _readU32be(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
}
