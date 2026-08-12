import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/abuse_report.dart';
import '../services/session_controller.dart';
import '../theme/encrypchat_colors.dart';

/// Blocks the token after an explicit confirmation. Returns true when blocked.
Future<bool> confirmBlock(
  BuildContext context,
  SessionController session, {
  required String token,
  required String label,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('¿Bloquear a $label?'),
      content: const Text(
        'Dejarás de recibir sus mensajes, sus fotos y sus llamadas: se '
        'descartan en este dispositivo antes de abrirlos. Tampoco vas a poder '
        'escribirle mientras esté bloqueado.\n\n'
        'Si estás en una llamada con esta persona, se corta ahora mismo.\n\n'
        'No se le avisa. El historial que ya tenés se conserva. Podés '
        'desbloquear cuando quieras.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Bloquear'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  await session.blockContact(token);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label bloqueado en este dispositivo')),
    );
  }
  return true;
}

Future<bool> confirmUnblock(
  BuildContext context,
  SessionController session, {
  required String token,
  required String label,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('¿Desbloquear a $label?'),
      content: const Text(
        'Volverás a recibir sus mensajes, fotos y llamadas, y podrás '
        'escribirle. Lo que te haya enviado mientras estaba bloqueado no se '
        'recupera: se descartó.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Desbloquear'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  await session.unblockContact(token);
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label desbloqueado')));
  }
  return true;
}

Future<void> showReportDialog(
  BuildContext context,
  SessionController session, {
  required String token,
  required String label,
}) async {
  await showDialog<void>(
    context: context,
    builder: (context) =>
        _ReportDialog(session: session, token: token, label: label),
  );
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({
    required this.session,
    required this.token,
    required this.label,
  });

  final SessionController session;
  final String token;
  final String label;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _note = TextEditingController();
  AbuseCategory _category = AbuseCategory.harassment;
  late bool _block = !widget.session.isBlocked(widget.token);
  bool _working = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      if (_block && !widget.session.isBlocked(widget.token)) {
        await widget.session.blockContact(widget.token);
      }
      final report = AbuseReport(
        peerToken: widget.token,
        category: _category,
        createdAt: DateTime.now().toUtc(),
        reporterToken: widget.session.identity.token,
        note: _note.text,
        blocked: widget.session.isBlocked(widget.token),
      );
      await Clipboard.setData(ClipboardData(text: report.render()));
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Informe copiado al portapapeles. Queda en tu dispositivo: '
            'vos decidís si lo compartís.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar el informe: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Reportar a ${widget.label}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Encrypchat no tiene servidor de moderación y no puede leer '
                'esta conversación: va cifrada de extremo a extremo entre los '
                'dos dispositivos. El informe se arma acá y se copia a tu '
                'portapapeles; nadie lo recibe automáticamente.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: EncrypchatColors.muted,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<AbuseCategory>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Motivo'),
                items: [
                  for (final c in AbuseCategory.values)
                    DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Qué pasó (opcional)',
                  hintText: 'Con tus palabras. No se adjuntan los mensajes.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _block,
                onChanged: widget.session.isBlocked(widget.token)
                    ? null
                    : (value) => setState(() => _block = value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  widget.session.isBlocked(widget.token)
                      ? 'Ya está bloqueado en este dispositivo'
                      : 'Bloquear también a este contacto',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _working ? null : _generate,
          child: const Text('Copiar informe'),
        ),
      ],
    );
  }
}
