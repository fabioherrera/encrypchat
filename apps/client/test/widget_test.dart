import 'package:flutter_test/flutter_test.dart';

import 'package:encrypchat/main.dart';
import 'package:encrypchat/services/session_controller.dart';

void main() {
  testWidgets('Onboarding shows brand when identity missing', (tester) async {
    final session = SessionController();
    session.phase = AppPhase.needsOnboarding;

    await tester.pumpWidget(EncrypchatApp(session: session));
    await tester.pump();

    expect(find.text('Encrypchat'), findsWidgets);
    expect(find.text('DECENTRALIZED P2P CHAT | ZERO-CLOUD'), findsOneWidget);
    expect(find.text('Crear identidad'), findsOneWidget);
  });

  testWidgets('Empty chats shell when ready', (tester) async {
    final session = _ReadySession();
    await tester.pumpWidget(EncrypchatApp(session: session));
    await tester.pump();

    expect(find.text('Chats'), findsWidgets);
    expect(find.text('Sin chats aún'), findsOneWidget);
  });
}

/// Minimal ready session that does not touch FFI / secure storage.
class _ReadySession extends SessionController {
  _ReadySession() {
    phase = AppPhase.ready;
  }
}
