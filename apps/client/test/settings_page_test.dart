import 'package:encrypchat/core/update_copy.dart';
import 'package:encrypchat/screens/settings_page.dart';
import 'package:encrypchat/services/session_controller.dart';
import 'package:encrypchat/services/update_applier.dart';
import 'package:encrypchat/services/update_checker.dart';
import 'package:encrypchat/widgets/update_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('Ajustes offers an explicit in-app update', (tester) async {
    final client = MockClient((request) async {
      return http.Response('{"version":"9.9.9"}', 200);
    });
    final updates = UpdateChecker(
      client: client,
      currentVersion: '1.0.0',
      catalogUri: Uri.parse('https://encrypchat.com/latest.json'),
      channel: UpdateChannel.linuxRpm,
    );
    await updates.check();
    final applier = UpdateApplier();

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          session: SessionController(),
          updates: updates,
          applier: applier,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Ajustes'), findsOneWidget);
    expect(find.textContaining('Actualiza solo la app'), findsWidgets);
    expect(find.text('Ver'), findsOneWidget);
    updates.dispose();
    applier.dispose();
  });

  testWidgets('the offer says data stays on the device and nothing is hidden', (
    tester,
  ) async {
    const info = UpdateInfo(
      status: UpdateStatus.available,
      currentVersion: '1.0.0',
      latestVersion: '1.0.1',
    );
    final applier = UpdateApplier();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showUpdateOffer(
              context: context,
              info: info,
              applier: applier,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text(UpdateCopy.title), findsOneWidget);
    expect(find.textContaining('solo la aplicación'), findsOneWidget);
    expect(find.textContaining('No hay nada oculto'), findsOneWidget);
    expect(
      find.textContaining('siguen en este dispositivo'),
      findsOneWidget,
    );
    expect(find.text(UpdateCopy.apply), findsNothing);
    expect(find.text(UpdateCopy.openSite), findsOneWidget);
    expect(find.text(UpdateCopy.later), findsOneWidget);
    applier.dispose();
  });
}
