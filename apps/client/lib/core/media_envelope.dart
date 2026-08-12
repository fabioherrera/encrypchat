import 'dart:convert';
import 'dart:typed_data';

/// Binary media payload inside E2EE (`encrypt` plaintext).
///
/// ```text
/// magic: EM01 (4)
/// version: u8 = 1
/// mime: u16 BE + utf8
/// name: u16 BE + utf8
/// data: u32 BE + bytes
/// ```
class MediaEnvelope {
  MediaEnvelope({required this.mime, required this.name, required this.data});

  static const magic = [0x45, 0x4d, 0x30, 0x31]; // EM01
  static const version = 1;
  static const maxDataBytes =
      12 * 1024 * 1024; // under P2P 16MiB ciphertext budget
  /// Caps are UTF-8 byte counts, not code units.
  static const maxMimeLen = 128;
  static const maxNameLen = 512;

  final String mime;
  final String name;
  final Uint8List data;

  Uint8List encode() {
    if (data.length > maxDataBytes) {
      throw StateError('Adjunto demasiado grande (${data.length} bytes)');
    }
    final mimeBytes = Uint8List.fromList(utf8.encode(mime));
    final nameBytes = Uint8List.fromList(utf8.encode(name));
    if (mimeBytes.length > maxMimeLen || nameBytes.length > maxNameLen) {
      throw StateError('EM01 mime/name demasiado largo');
    }
    final out = BytesBuilder(copy: false);
    out.add(magic);
    out.addByte(version);
    out.add(_u16(mimeBytes.length));
    out.add(mimeBytes);
    out.add(_u16(nameBytes.length));
    out.add(nameBytes);
    out.add(_u32(data.length));
    out.add(data);
    return out.toBytes();
  }

  static MediaEnvelope decode(Uint8List bytes) {
    if (bytes.length < 4 + 1 + 2 + 2 + 4) {
      throw const FormatException('EM01 demasiado corto');
    }
    for (var i = 0; i < 4; i++) {
      if (bytes[i] != magic[i]) {
        throw const FormatException('No es EM01');
      }
    }
    if (bytes[4] != version) {
      throw const FormatException('EM01 versión desconocida');
    }
    var o = 5;
    final mimeLen = _ru16(bytes, o);
    o += 2;
    if (mimeLen > maxMimeLen) {
      throw const FormatException('EM01 mime demasiado largo');
    }
    _requireAvailable(bytes, o, mimeLen);
    final mime = utf8.decode(bytes.sublist(o, o + mimeLen));
    o += mimeLen;

    _requireAvailable(bytes, o, 2);
    final nameLen = _ru16(bytes, o);
    o += 2;
    if (nameLen > maxNameLen) {
      throw const FormatException('EM01 name demasiado largo');
    }
    _requireAvailable(bytes, o, nameLen);
    final name = utf8.decode(bytes.sublist(o, o + nameLen));
    o += nameLen;

    _requireAvailable(bytes, o, 4);
    final dataLen = _ru32(bytes, o);
    o += 4;
    if (dataLen > maxDataBytes) {
      throw const FormatException('EM01 data demasiado grande');
    }
    if (o + dataLen != bytes.length) {
      throw const FormatException('EM01 longitud inválida');
    }
    return MediaEnvelope(
      mime: mime,
      name: name,
      data: Uint8List.fromList(bytes.sublist(o, o + dataLen)),
    );
  }

  static bool looksLike(Uint8List bytes) {
    if (bytes.length < 4 + 1 + 2 + 2 + 4) return false;
    for (var i = 0; i < 4; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return bytes[4] == version;
  }

  /// A malformed EM01 must surface as [FormatException], not [RangeError].
  static void _requireAvailable(Uint8List bytes, int offset, int len) {
    if (offset + len > bytes.length) {
      throw const FormatException('EM01 truncado');
    }
  }

  static Uint8List _u16(int v) =>
      Uint8List.fromList([(v >> 8) & 0xff, v & 0xff]);
  static Uint8List _u32(int v) => Uint8List.fromList([
    (v >> 24) & 0xff,
    (v >> 16) & 0xff,
    (v >> 8) & 0xff,
    v & 0xff,
  ]);
  static int _ru16(Uint8List b, int o) => (b[o] << 8) | b[o + 1];
  static int _ru32(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
}
