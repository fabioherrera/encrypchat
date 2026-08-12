import 'package:flutter/material.dart';

import '../services/identity_wipe.dart';
import '../services/session_controller.dart';
import '../theme/encrypchat_colors.dart';

/// Leaving Encrypchat from inside Encrypchat.
///
/// A screen and not a dialog, and a typed word and not a second tap. The reason
/// is the shape of the product, not ceremony for its own sake: there is no
/// account to sign back into, no server holding a copy, and nobody — including
/// whoever built this — who can give the identity back. A mis-tap here costs
/// every conversation on the device and the token other people have saved.
class DeleteIdentityPage extends StatefulWidget {
  const DeleteIdentityPage({super.key, required this.session});

  final SessionController session;

  @override
  State<DeleteIdentityPage> createState() => _DeleteIdentityPageState();
}

class _DeleteIdentityPageState extends State<DeleteIdentityPage> {
  /// Typed, not tapped. Long enough that it cannot be produced by accident,
  /// short enough that somebody who means it is not fighting the keyboard.
  static const _confirmWord = 'BORRAR';

  static const _danger = Color(0xFF8C1C13);
  static const _dangerBg = Color(0xFFFDECEA);

  final _typed = TextEditingController();
  bool _working = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _typed.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _armed => _typed.text.trim().toUpperCase() == _confirmWord;

  Future<void> _wipe() async {
    if (!_armed || _working) return;
    setState(() {
      _working = true;
      _failure = null;
    });
    IdentityWipeReport report;
    try {
      report = await widget.session.deleteIdentity();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        // The identity is already marked for deletion, so this screen stays
        // where it is with the retry on it. Force-quitting instead is safe:
        // the next launch finishes the wipe before anything else runs.
        _failure =
            'No se pudo completar el borrado (${e.runtimeType}). Volvé a '
            'intentarlo. Tu identidad ya está marcada para borrarse: si cerrás '
            'la app, se termina de borrar al abrirla de nuevo.';
      });
      return;
    }
    if (!mounted) return;
    // The app is already back on onboarding underneath; this route is what is
    // left on top of it.
    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          report.isClean
              ? 'Identidad borrada de este dispositivo.'
              : 'Identidad borrada. ${report.filesLeft} fichero(s) que el '
                    'sistema no dejó eliminar quedaron en el disco, cifrados '
                    'con una clave que ya no existe.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EncrypchatColors.canvas,
      appBar: AppBar(title: const Text('Borrar identidad')),
      body: AbsorbPointer(
        // Nothing is dismissible or editable while the wipe runs: half of it is
        // already done and there is no version of "cancelar" that undoes that.
        absorbing: _working,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            const _Banner(),
            const SizedBox(height: 20),
            const _SectionTitle('Qué se borra'),
            const _Bullets([
              'Tu clave privada y tu token. Nadie te va a poder escribir a ese '
                  'token nunca más, y no hay forma de volver a demostrar que '
                  'sos vos: la clave no existe en ningún otro lado.',
              'Todas tus conversaciones, con los mensajes que hayas recibido y '
                  'enviado.',
              'Todas las fotos y archivos que hayas mandado o recibido.',
              'Tus contactos, tus bloqueos y las solicitudes pendientes.',
              'La dirección del relay que tengas configurada.',
            ]),
            const SizedBox(height: 20),
            const _SectionTitle('Qué no se borra'),
            const _Bullets([
              'Lo que ya le mandaste a otras personas: está en sus '
                  'dispositivos y ellas deciden qué hacer con eso.',
              'Una copia de seguridad del dispositivo hecha antes de este '
                  'borrado, si tenés backups del sistema activados: puede '
                  'contener tanto los ficheros cifrados como la clave.',
            ]),
            const SizedBox(height: 20),
            const _SectionTitle('Qué significa "borrar" en este dispositivo'),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Tus chats y tus adjuntos están cifrados en el disco con una '
                'clave que vive en el llavero del sistema. Esa clave se borra '
                'primero: desde ese momento, lo que quede en el disco es '
                'ciphertext que ya nadie puede abrir.\n\n'
                'Después se borran los ficheros. Borrar un fichero no '
                'sobreescribe sus bytes — ni acá ni en ninguna app —, así que '
                'en almacenamiento flash pueden seguir existiendo un tiempo, '
                'hasta que el sistema reutilice ese espacio. Siguen siendo '
                'ilegibles sin la clave, pero no te prometemos que los bytes '
                'desaparezcan del chip.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: EncrypchatColors.muted,
                ),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Escribí $_confirmWord para confirmar',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: EncrypchatColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _typed,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                filled: true,
                fillColor: EncrypchatColors.paper,
                hintText: _confirmWord,
                border: OutlineInputBorder(),
              ),
            ),
            if (_failure != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                color: _dangerBg,
                child: Text(
                  _failure!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: _danger,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _armed && !_working ? _wipe : null,
              style: FilledButton.styleFrom(
                backgroundColor: _danger,
                foregroundColor: EncrypchatColors.paper,
                minimumSize: const Size.fromHeight(48),
              ),
              child: _working
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: EncrypchatColors.paper,
                      ),
                    )
                  : Text(
                      _failure == null
                          ? 'Borrar mi identidad y todos mis chats'
                          : 'Reintentar el borrado',
                    ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _working ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      color: _DeleteIdentityPageState._dangerBg,
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: _DeleteIdentityPageState._danger,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Esto es irreversible. No hay copia en la nube, no hay servidor '
              'con tus datos y nadie puede devolverte esta identidad: tu clave '
              'existe solo en este dispositivo.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: _DeleteIdentityPageState._danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: EncrypchatColors.muted,
      ),
    );
  }
}

class _Bullets extends StatelessWidget {
  const _Bullets(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '· ',
                  style: TextStyle(color: EncrypchatColors.muted),
                ),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: EncrypchatColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
