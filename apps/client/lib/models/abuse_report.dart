import 'package:flutter/foundation.dart';

enum AbuseCategory {
  harassment('Acoso o amenazas'),
  spam('Spam o estafa'),
  sexualContent('Contenido sexual o explotación'),
  impersonation('Suplantación de identidad'),
  other('Otro');

  const AbuseCategory(this.label);

  final String label;
}

/// A local abuse record the user writes for themselves.
///
/// Encrypchat has no moderation backend and no server that could receive this:
/// message bodies are end-to-end encrypted, so nobody but the two devices can
/// read them. The report is rendered as plain text that the person decides what
/// to do with (keep it, hand it to a lawyer, to the police, to a platform where
/// the same person also operates). Nothing here leaves the device on its own,
/// and the conversation itself is never copied in: exporting someone else's
/// messages automatically would leak content this app promises not to move.
@immutable
class AbuseReport {
  const AbuseReport({
    required this.peerToken,
    required this.category,
    required this.createdAt,
    this.reporterToken,
    this.note,
    this.blocked = false,
  });

  final String peerToken;
  final AbuseCategory category;
  final DateTime createdAt;
  final String? reporterToken;
  final String? note;
  final bool blocked;

  String render() {
    final trimmedNote = note?.trim();
    final lines = <String>[
      'Encrypchat — informe de abuso (local)',
      'Generado: ${createdAt.toUtc().toIso8601String()}',
      '',
      'Token reportado: $peerToken',
      if (reporterToken != null && reporterToken!.isNotEmpty)
        'Tu token: $reporterToken',
      'Motivo: ${category.label}',
      'Bloqueado en este dispositivo: ${blocked ? 'sí' : 'no'}',
      if (trimmedNote != null && trimmedNote.isNotEmpty) ...[
        'Descripción:',
        trimmedNote,
      ],
      '',
      'Este informe se generó en tu dispositivo y no se envió a ningún lado. '
          'Encrypchat no tiene servidor de moderación y no puede leer los '
          'mensajes: van cifrados de extremo a extremo entre los dos '
          'dispositivos.',
      'No incluye el contenido de la conversación. Si necesitás aportar '
          'pruebas ante una autoridad o ante otra plataforma, adjuntalas vos.',
      'Bloquear corta la entrega de mensajes, fotos y llamadas de ese token en '
          'este dispositivo. No impide que esa persona genere una identidad '
          'nueva.',
    ];
    return lines.join('\n');
  }
}
