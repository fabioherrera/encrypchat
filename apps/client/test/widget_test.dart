import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:encrypchat/main.dart';

void main() {
  testWidgets('Encrypchat shell shows brand', (WidgetTester tester) async {
    await tester.pumpWidget(const EncrypchatApp());

    expect(find.text('Encrypchat'), findsWidgets);
    expect(
      find.text('DECENTRALIZED P2P CHAT | ZERO-CLOUD'),
      findsOneWidget,
    );
  });
}
