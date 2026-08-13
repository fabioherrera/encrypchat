import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/qr_from_image.dart';
import '../models/contact.dart';
import '../theme/encrypchat_colors.dart';

/// Live camera scan exists on Android and iOS. Linux and Windows have no
/// scanner plugin, so those platforms read a still image of the QR instead.
bool get liveCameraScanAvailable =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

const _imageTypes = XTypeGroup(
  label: 'Imagen',
  extensions: ['png', 'jpg', 'jpeg', 'webp'],
  mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
);

/// Opens the camera on a phone, or an image picker on a desktop, and returns
/// the payload of an Encrypchat contact QR. Null is a cancel, not a failure.
///
/// [pickImageBytes] is a test seam; production uses the system file dialog.
Future<String?> scanContactCard(
  BuildContext context, {
  Future<Uint8List?> Function()? pickImageBytes,
}) async {
  if (liveCameraScanAvailable) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const ScanContactPage()),
    );
  }
  return scanContactCardFromImage(context, pickImageBytes: pickImageBytes);
}

/// Reads a contact QR from a still image. Used on desktop, and from the
/// camera screen when the other device is not in front of the lens.
Future<String?> scanContactCardFromImage(
  BuildContext context, {
  Future<Uint8List?> Function()? pickImageBytes,
}) async {
  final bytes = await (pickImageBytes ?? _pickImageBytes)();
  if (bytes == null) return null;
  final text = decodeQrFromImageBytes(bytes);
  if (text == null) {
    if (context.mounted) {
      await _explain(
        context,
        'Esa imagen no tiene un QR legible. Pedile que abra Mi token y '
        'volvé a sacarle foto al recuadro, o pegá el export.',
      );
    }
    return null;
  }
  if (!Contact.looksLikeCard(text)) {
    if (context.mounted) {
      await _explain(
        context,
        'Ese QR no es una tarjeta de Encrypchat. Pedile que abra Mi token '
        'y te muestre el QR de ahí.',
      );
    }
    return null;
  }
  return text;
}

Future<Uint8List?> _pickImageBytes() async {
  final file = await openFile(acceptedTypeGroups: const [_imageTypes]);
  if (file == null) return null;
  return file.readAsBytes();
}

Future<void> _explain(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('No se pudo leer el QR'),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Entendido'),
        ),
      ],
    ),
  );
}

/// Full-screen camera aimed at another Encrypchat's "Mi token" QR.
class ScanContactPage extends StatefulWidget {
  const ScanContactPage({super.key});

  @override
  State<ScanContactPage> createState() => _ScanContactPageState();
}

class _ScanContactPageState extends State<ScanContactPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
  );
  var _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final text = barcode.rawValue;
      if (text == null || !Contact.looksLikeCard(text)) continue;
      _done = true;
      Navigator.of(context).pop(text);
      return;
    }
  }

  Future<void> _fromImage() async {
    if (_done) return;
    final text = await scanContactCardFromImage(context);
    if (text == null || !mounted || _done) return;
    _done = true;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EncrypchatColors.ink,
      appBar: AppBar(
        title: const Text('Escanear contacto'),
        backgroundColor: EncrypchatColors.navy,
        foregroundColor: EncrypchatColors.paper,
        actions: [
          IconButton(
            tooltip: 'Leer QR de una imagen',
            onPressed: _fromImage,
            icon: const Icon(Icons.image_outlined),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraError(error: error),
          ),
          const IgnorePointer(child: _Viewfinder()),
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Text(
                'Apuntá al QR de Mi token en el otro dispositivo.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: EncrypchatColors.paper,
                  height: 1.4,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Viewfinder extends StatelessWidget {
  const _Viewfinder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 240,
        height: 240,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: EncrypchatColors.paper, width: 2),
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: EncrypchatColors.ink,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.videocam_off_outlined,
              size: 48,
              color: EncrypchatColors.paper,
            ),
            const SizedBox(height: 16),
            Text(
              denied
                  ? 'Sin permiso de cámara no se puede escanear. Podés '
                        'concederlo en Ajustes, o volver y pegar el export.'
                  : 'Esta cámara no se pudo abrir. Pegá el export desde '
                        'Contactos, o leé el QR desde una imagen.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: EncrypchatColors.paper,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
