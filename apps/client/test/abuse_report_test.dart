import 'package:encrypchat/models/abuse_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final report = AbuseReport(
    peerToken: 'ec_${'a' * 64}',
    category: AbuseCategory.harassment,
    createdAt: DateTime.utc(2026, 8, 12, 18, 30),
    reporterToken: 'ec_${'b' * 64}',
    note: 'Me mandó amenazas.',
    blocked: true,
  );

  test('the report carries what the user chose to write, nothing else', () {
    final text = report.render();
    expect(text, contains('ec_${'a' * 64}'));
    expect(text, contains('Acoso o amenazas'));
    expect(text, contains('Me mandó amenazas.'));
    expect(text, contains('2026-08-12T18:30:00.000Z'));
    expect(text, contains('Bloqueado en este dispositivo: sí'));
  });

  test('the report does not promise a review that nobody can do', () {
    final text = report.render().toLowerCase();
    for (final claim in [
      'revisaremos',
      'nuestro equipo',
      'moderador',
      'enviado a',
    ]) {
      expect(text, isNot(contains(claim)));
    }
    expect(text, contains('no se envió a ningún lado'));
    expect(text, contains('no incluye el contenido'));
  });
}
