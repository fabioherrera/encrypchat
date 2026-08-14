import 'package:encrypchat/core/lan_listen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isDialHint accepts only ip+tcp multiaddrs', () {
    expect(isDialHint('/ip4/192.168.1.10/tcp/41234'), isTrue);
    expect(isDialHint('/ip6/::1/tcp/9'), isTrue);
    expect(isDialHint('/ip4/127.0.0.1/tcp/1'), isTrue);
    expect(isDialHint('/ip4/192.168.1.10/udp/41234'), isFalse);
    expect(isDialHint('192.168.1.10:41234'), isFalse);
    expect(isDialHint('not-an-addr'), isFalse);
  });

  test('listenPortFromMultiaddr reads the tcp port', () {
    expect(listenPortFromMultiaddr('/ip4/127.0.0.1/tcp/41234'), 41234);
    expect(listenPortFromMultiaddr('/ip4/10.0.0.2/tcp/1'), 1);
    expect(listenPortFromMultiaddr('/ip4/10.0.0.2/udp/9'), isNull);
    expect(listenPortFromMultiaddr(null), isNull);
  });
}
