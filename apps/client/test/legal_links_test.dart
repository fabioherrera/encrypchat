import 'dart:ui';

import 'package:encrypchat/core/legal_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legal links follow the device language when the site has it', () {
    expect(
      LegalLinks.privacy(const Locale('en', 'US')),
      'https://encrypchat.com/en/privacy',
    );
    expect(
      LegalLinks.terms(const Locale('es', 'AR')),
      'https://encrypchat.com/es/terms',
    );
    expect(
      LegalLinks.download(const Locale('en')),
      'https://encrypchat.com/en/download',
    );
  });

  test('unsupported languages fall back to Spanish, not to a 404', () {
    expect(
      LegalLinks.privacy(const Locale('de')),
      'https://encrypchat.com/es/privacy',
    );
  });
}
