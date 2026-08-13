import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/abuse_report.dart';
import '../services/report_export.dart';
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

/// [save] is a test seam; production writes the file with [saveAbuseReport].
Future<void> showReportDialog(
  BuildContext context,
  SessionController session, {
  required String token,
  required String label,
  AbuseReportSaver? save,
}) async {
  final saved = await showDialog<SavedReport>(
    context: context,
    builder: (context) => _ReportDialog(
      session: session,
      token: token,
      label: label,
      save: save ?? saveAbuseReport,
    ),
  );
  // Shown from here, not from inside the dialog: by then that route is gone and
  // its context with it.
  if (saved == null || !context.mounted) return;
  await _showSavedDialog(context, saved);
}

Future<void> _showSavedDialog(BuildContext context, SavedReport saved) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Informe guardado'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Es un archivo de texto tuyo, en este dispositivo. No se envió '
                'a ningún lado.',
              ),
              const SizedBox(height: 12),
              SelectableText(
                saved.path,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              if (saved.location == ReportLocation.appFolder) ...[
                const SizedBox(height: 12),
                Text(
                  _appFolderHint,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: EncrypchatColors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Listo'),
        ),
      ],
    ),
  );
}

/// Said only where the phone gave us no dialog to choose the folder: the file
/// is somewhere the person did not pick, so the screen has to say how to get
/// back to it.
String get _appFolderHint => Platform.isIOS
    ? 'Acá no hay un diálogo para elegir dónde guardar, así que el archivo '
          'quedó en la carpeta de Encrypchat. Lo encontrás desde la app '
          'Archivos, en «En mi iPhone».'
    : 'Acá no hay un diálogo para elegir dónde guardar, así que el archivo '
          'quedó en la carpeta de Encrypchat. Para sacarlo del teléfono, '
          'conectalo a una computadora.';

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({
    required this.session,
    required this.token,
    required this.label,
    required this.save,
  });

  final SessionController session;
  final String token;
  final String label;
  final AbuseReportSaver save;

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

  /// Applies the block the person ticked and builds the report. Shared by the
  /// two ways out, so neither can quietly skip the block.
  Future<AbuseReport> _prepare() async {
    if (_block && !widget.session.isBlocked(widget.token)) {
      await widget.session.blockContact(widget.token);
    }
    return AbuseReport(
      peerToken: widget.token,
      category: _category,
      createdAt: DateTime.now().toUtc(),
      reporterToken: widget.session.ownToken,
      note: _note.text,
      blocked: widget.session.isBlocked(widget.token),
    );
  }

  Future<void> _save() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final saved = await widget.save(await _prepare());
      if (!mounted) return;
      if (saved == null) {
        // Closed the save dialog without choosing: nothing was written, and the
        // form stays as it was left.
        setState(() => _working = false);
        return;
      }
      Navigator.pop(context, saved);
    } catch (e) {
      _reportFailure(e);
    }
  }

  Future<void> _copyToClipboard() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final report = await _prepare();
      await Clipboard.setData(ClipboardData(text: report.render()));
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Informe copiado. Pegalo donde lo necesites y después copiá '
            'cualquier otra cosa.',
          ),
        ),
      );
    } catch (e) {
      _reportFailure(e);
    }
  }

  void _reportFailure(Object error) {
    if (!mounted) return;
    setState(() => _working = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No se pudo generar el informe: $error')),
    );
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
                'dos dispositivos. El informe se arma acá y lo guardás vos en '
                'un archivo; nadie lo recibe automáticamente.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: EncrypchatColors.muted,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<AbuseCategory>(
                initialValue: _category,
                // Otherwise the field grows to the widest reason, which runs
                // past the dialog on a narrow window or with large text.
                isExpanded: true,
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
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 12),
              // The sentence sits above the button on purpose: copying is the
              // convenient move and its cost is invisible, so it is said before
              // the press rather than in a warning afterwards.
              const Text(
                'El portapapeles es un espacio compartido: otras apps pueden '
                'leer lo que copiás y en algunos sistemas se sincroniza con tu '
                'cuenta. Guardar el informe en un archivo lo deja solo acá.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: EncrypchatColors.muted,
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _working ? null : _copyToClipboard,
                  icon: const Icon(Icons.content_copy_outlined, size: 18),
                  label: const Text('Copiar al portapapeles'),
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
          onPressed: _working ? null : _save,
          child: const Text('Guardar informe…'),
        ),
      ],
    );
  }
}
