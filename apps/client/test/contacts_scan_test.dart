import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:encrypchat/core/qr_from_image.dart';
import 'package:encrypchat/models/contact.dart';
import 'package:encrypchat/screens/contacts_page.dart';
import 'package:encrypchat/services/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a bare token is not a card', () {
    expect(Contact.looksLikeCard('ec_${'a' * 64}'), isFalse);
    expect(
      Contact.looksLikeCard(
        'encrypchat:contact:v1:ec_${'a' * 64}:${'b' * 64}:',
      ),
      isTrue,
    );
  });

  test('the QR drawn on Mi token decodes back to the same card', () async {
    final pub = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    final card = Contact(
      token: 'ec_${sha256.convert(pub)}',
      publicKey: pub,
      displayName: 'Ada',
    ).exportLine();

    expect(decodeQrFromImageBytes(await _qrPng(card)), card);
  });

  test('a wifi QR is not treated as a contact', () async {
    final png = await _qrPng('WIFI:S:red;T:WPA;P:secreto;;');
    final text = decodeQrFromImageBytes(png);
    expect(text, isNotNull);
    expect(Contact.looksLikeCard(text!), isFalse);
  });

  testWidgets('empty contacts offers the camera first', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ContactsPage(session: SessionController())),
    );

    expect(find.text('Escanear QR'), findsWidgets);
    expect(find.text('Pegar export'), findsWidgets);
  });
}

Future<Uint8List> _qrPng(String data) async {
  const size = 400.0;
  final painter = QrPainter(
    data: data,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.M,
    gapless: true,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: Color(0xFF000000),
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Color(0xFF000000),
    ),
  );
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, size, size),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  painter.paint(canvas, const Size(size, size));
  final image = await recorder.endRecording().toImage(
    size.toInt(),
    size.toInt(),
  );
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}
