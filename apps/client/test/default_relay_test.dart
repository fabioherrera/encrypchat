import 'package:encrypchat/core/default_relay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first run uses the compiled Encrypchat relay', () {
    expect(
      resolveRelayUrl(stored: null, defaultUrl: encrypchatDefaultRelayUrl),
      encrypchatDefaultRelayUrl,
    );
    expect(
      resolveRelayUrl(stored: '  ', defaultUrl: encrypchatDefaultRelayUrl),
      encrypchatDefaultRelayUrl,
    );
  });

  test('an explicit off stays off after a restart', () {
    expect(
      resolveRelayUrl(
        stored: encrypchatRelayOff,
        defaultUrl: encrypchatDefaultRelayUrl,
      ),
      isNull,
    );
  });

  test('a custom URL wins over the default', () {
    expect(
      resolveRelayUrl(
        stored: 'https://relay.example/ ',
        defaultUrl: encrypchatDefaultRelayUrl,
      ),
      'https://relay.example/',
    );
  });

  test('tests without a compiled default stay disconnected', () {
    expect(resolveRelayUrl(stored: null, defaultUrl: null), isNull);
  });

  test('☁ copy names P2P first and what the mailbox sees', () {
    final ours = relayCloudDialogBody(configured: true, usesDefault: true);
    expect(ours, contains('P2P se intenta primero'));
    expect(ours, contains('token de destino'));
    expect(ours, contains('IP'));
    expect(ours, isNot(contains('sin intermediarios')));

    final own = relayCloudDialogBody(configured: true, usesDefault: false);
    expect(own, contains('Encrypchat no recibe'));
    expect(own, contains('misma URL'));
    expect(own, contains('P2P se intenta primero'));

    final off = relayCloudDialogBody(configured: false, usesDefault: false);
    expect(off, contains('apagado'));
    expect(off, contains('No hay entrega entre redes distintas'));
  });
}
