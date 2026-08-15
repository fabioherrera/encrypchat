import 'dart:io';

import 'package:encrypchat/models/abuse_report.dart';
import 'package:encrypchat/screens/safety_actions.dart';
import 'package:encrypchat/services/report_export.dart';
import 'package:encrypchat/services/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// F-14: the report relates the identity of whoever is being harassed with the
/// identity of whoever is harassing them, and it used to leave the app through
/// the system clipboard — a channel other apps read and some systems sync. What
/// these tests hold is the shape of the fix: the path the button offers writes a
/// file and touches nothing shared, and the clipboard is only reached by asking
/// for it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late _ClipboardSpy clipboard;

  final peer = 'ec_${'a' * 64}';

  AbuseReport reportAt(DateTime when) => AbuseReport(
    peerToken: peer,
    category: AbuseCategory.harassment,
    createdAt: when,
    reporterToken: 'ec_${'b' * 64}',
    note: 'Me mandó amenazas.',
    blocked: true,
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('encrypchat_report_export');
    _mockPathProvider(temp);
    clipboard = _ClipboardSpy()..install();
  });

  tearDown(() async {
    clipboard.remove();
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  group('saving the report', () {
    test(
      'the report goes to the file the person chose, and nowhere else',
      () async {
        final target = p.join(temp.path, 'informe.txt');
        final report = reportAt(DateTime.utc(2026, 8, 13, 18, 30, 45));

        final saved = await saveAbuseReport(
          report,
          platformPicksPath: true,
          pickPath: (suggested) async => target,
        );

        expect(saved!.location, ReportLocation.chosen);
        expect(saved.path, target);
        expect(File(target).readAsStringSync(), report.render());
        expect(clipboard.copies, isEmpty);
      },
    );

    test('closing the save dialog leaves nothing behind', () async {
      final saved = await saveAbuseReport(
        reportAt(DateTime.utc(2026, 8, 13, 18, 30, 45)),
        platformPicksPath: true,
        pickPath: (suggested) async => null,
      );

      expect(saved, isNull);
      expect(temp.listSync(), isEmpty);
      expect(clipboard.copies, isEmpty);
    });

    test(
      'where the phone has no save dialog the report is still a file',
      () async {
        // Android and iOS do not implement `getSaveLocation`, so there is nobody
        // to ask: the file goes to Encrypchat's folder and the screen says where.
        final report = reportAt(DateTime.utc(2026, 8, 13, 18, 30, 45));

        final saved = await saveAbuseReport(report, platformPicksPath: false);

        expect(saved!.location, ReportLocation.appFolder);
        expect(File(saved.path).readAsStringSync(), report.render());
        expect(p.basename(p.dirname(saved.path)), 'Informes');
        expect(clipboard.copies, isEmpty);
      },
    );

    test('the suggested name carries the moment, not who was reported', () {
      final name = reportFileName(DateTime.utc(2026, 8, 13, 18, 30, 45));

      expect(name, 'informe-encrypchat-2026-08-13-183045.txt');
      // Two reports written in the same minute are two files, not one
      // overwriting the other.
      expect(
        reportFileName(DateTime.utc(2026, 8, 13, 18, 30, 46)),
        isNot(name),
      );
      expect(name, isNot(contains(peer)));
    });
  });

  group('the report dialog', () {
    late _TestSession session;
    final saves = <AbuseReport>[];

    /// Opens the dialog with the save seam replaced: [cancelled] stands for the
    /// person closing the system dialog without choosing a file.
    Future<void> open(WidgetTester tester, {bool cancelled = false}) async {
      session = _TestSession();
      saves.clear();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showReportDialog(
                    context,
                    session,
                    token: peer,
                    label: 'Bruno',
                    save: (report) async {
                      saves.add(report);
                      if (cancelled) return null;
                      return SavedReport(
                        path: p.join(temp.path, 'informe.txt'),
                        location: ReportLocation.chosen,
                      );
                    },
                  ),
                  child: const Text('reportar'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('reportar'));
      await tester.pumpAndSettle();
    }

    testWidgets('the button on offer writes a file and never copies', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(find.text('Guardar informe…'));
      await tester.pumpAndSettle();

      expect(saves, hasLength(1));
      expect(saves.single.peerToken, peer);
      // The whole finding in one line.
      expect(clipboard.copies, isEmpty);
      // And the person is told where it went, since they picked the place.
      expect(find.text('Informe guardado'), findsOneWidget);
      expect(find.text(p.join(temp.path, 'informe.txt')), findsOneWidget);
    });

    testWidgets('a save the person backed out of keeps the form open', (
      tester,
    ) async {
      await open(tester, cancelled: true);

      await tester.tap(find.text('Guardar informe…'));
      await tester.pumpAndSettle();

      // Closing the system dialog is a change of mind, not a failure: nothing
      // is announced as saved and what was typed is still there to retry.
      expect(find.text('Informe guardado'), findsNothing);
      expect(find.text('Guardar informe…'), findsOneWidget);
      expect(clipboard.copies, isEmpty);
    });

    testWidgets('the clipboard costs a second decision, and says why first', (
      tester,
    ) async {
      await open(tester);

      // Readable before the button is pressed, not in a warning afterwards.
      expect(
        find.textContaining('otras apps pueden leer lo que copias'),
        findsOneWidget,
      );
      expect(find.text('Copiar al portapapeles'), findsOneWidget);

      // It sits under the sentence, so on a short window it has to be scrolled
      // to — which is the point: it is not the button that falls under a thumb.
      await tester.ensureVisible(find.text('Copiar al portapapeles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copiar al portapapeles'));
      await tester.pumpAndSettle();

      expect(saves, isEmpty, reason: 'copying is not the file path');
      expect(clipboard.copies.single, contains(peer));
    });

    testWidgets('either way out applies the block that was ticked', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(find.text('Guardar informe…'));
      await tester.pumpAndSettle();

      expect(session.blocked, {peer});
    });
  });
}

/// Counts what reaches the system clipboard. Reading the channel rather than a
/// wrapper is deliberate: the point is that nothing at all arrives at the OS.
class _ClipboardSpy {
  final copies = <String>[];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = (call.arguments as Map?)?.cast<String, dynamic>();
            copies.add(args?['text'] as String? ?? '');
          }
          return null;
        });
  }

  void remove() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  }
}

/// Only what the report dialog reads. A real session would open the database
/// and start a node, neither of which has anything to say about where the
/// report goes.
class _TestSession extends SessionController {
  _TestSession() {
    phase = AppPhase.ready;
  }

  final blocked = <String>{};

  @override
  String? get ownToken => 'ec_${'b' * 64}';

  @override
  bool isBlocked(String token) => blocked.contains(token);

  @override
  Future<void> blockContact(String token) async => blocked.add(token);
}

void _mockPathProvider(Directory dir) {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async => dir.path);
}
