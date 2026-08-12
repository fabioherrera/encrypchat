import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypchat/core/media_envelope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EM01 media envelope roundtrip', () {
    final data = Uint8List.fromList(List<int>.generate(64, (i) => i));
    final env = MediaEnvelope(mime: 'image/jpeg', name: 'foto.jpg', data: data);
    final decoded = MediaEnvelope.decode(env.encode());
    expect(decoded.mime, 'image/jpeg');
    expect(decoded.name, 'foto.jpg');
    expect(decoded.data, data);
    expect(MediaEnvelope.looksLike(env.encode()), isTrue);
  });

  test('EM01 keeps non-Latin-1 mime/name intact (UTF-8)', () {
    const name = 'canción-año 😀.jpg';
    final env = MediaEnvelope(
      mime: 'image/jpeg',
      name: name,
      data: Uint8List.fromList([1, 2, 3]),
    );
    final encoded = env.encode();
    final decoded = MediaEnvelope.decode(encoded);
    expect(decoded.name, name);
    expect(decoded.mime, 'image/jpeg');
    // Emoji is non-BMP: 4 UTF-8 bytes, 2 UTF-16 code units.
    expect(utf8.encode(name).length, greaterThan(name.length));
  });

  test('EM01 rejects a name whose UTF-8 form exceeds the byte cap', () {
    final env = MediaEnvelope(
      mime: 'image/jpeg',
      // 200 emoji = 800 UTF-8 bytes (over the cap) but 400 UTF-16 code units.
      name: '😀' * 200,
      data: Uint8List.fromList([1]),
    );
    expect(env.encode, throwsA(isA<StateError>()));
  });

  group('EM01 malformed frames fail as FormatException', () {
    Uint8List frame(List<int> tail, {int padTo = 13}) {
      final out = <int>[...MediaEnvelope.magic, MediaEnvelope.version, ...tail];
      while (out.length < padTo) {
        out.add(0);
      }
      return Uint8List.fromList(out);
    }

    void expectFormatException(Uint8List bytes) {
      expect(MediaEnvelope.looksLike(bytes), isTrue);
      expect(
        () => MediaEnvelope.decode(bytes),
        throwsA(isA<FormatException>()),
      );
    }

    test('mime length over cap', () {
      expectFormatException(frame([0xff, 0xff]));
    });

    test('mime length past end of buffer', () {
      expectFormatException(
        frame([0x00, 0x64]),
      ); // 100 bytes of mime, 6 available
    });

    test('name length over cap', () {
      expectFormatException(frame([0x00, 0x01, 0x61, 0xff, 0xff]));
    });

    test('name length past end of buffer', () {
      expectFormatException(frame([0x00, 0x01, 0x61, 0x00, 0x40]));
    });

    test('no room for the data length prefix', () {
      expectFormatException(
        frame([0x00, 0x01, 0x61, 0x00, 0x01, 0x62], padTo: 13),
      );
    });

    test('data length does not match the buffer', () {
      expectFormatException(
        Uint8List.fromList([
          ...MediaEnvelope.magic,
          MediaEnvelope.version,
          0x00, 0x01, 0x61, // mime "a"
          0x00, 0x01, 0x62, // name "b"
          0x00, 0x00, 0x10, 0x00, // 4096 bytes of data announced
          0x01, 0x02, 0x03,
        ]),
      );
    });
  });
}
