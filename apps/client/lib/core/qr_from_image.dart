import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';
import 'package:zxing2/zxing2.dart';

/// Reads a QR from a still image. Returns the payload, or null when there is
/// no QR in the picture.
///
/// Used where the live camera is not available (Linux, Windows) and as a
/// fallback on a phone that already has a photo of the other device's token
/// screen. Decoding is local: the bytes never leave the device.
String? decodeQrFromImageBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final image = decoded.convert(numChannels: 4);

  final pixels = Int32List(image.width * image.height);
  var i = 0;
  for (final pixel in image) {
    pixels[i++] =
        (pixel.a.toInt() << 24) |
        (pixel.r.toInt() << 16) |
        (pixel.g.toInt() << 8) |
        pixel.b.toInt();
  }

  try {
    final source = RGBLuminanceSource(image.width, image.height, pixels);
    final result = QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source)));
    final text = result.text;
    return text.isEmpty ? null : text;
  } on ReaderException {
    return null;
  }
}
