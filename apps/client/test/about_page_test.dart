import 'package:encrypchat/screens/about_page.dart';
import 'package:encrypchat/services/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the legal pages are reachable and shown as full URLs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AboutPage(session: SessionController())),
    );
    await tester.pump();

    expect(find.text('Política de privacidad'), findsOneWidget);
    expect(find.text('Términos de uso'), findsOneWidget);
    // The URL is on screen, so the page stays reachable even where the app
    // cannot hand the link to a browser.
    expect(
      find.textContaining('https://encrypchat.com/'),
      findsNWidgets(2),
    );
    expect(find.text('Contactos bloqueados'), findsOneWidget);
  });
}
