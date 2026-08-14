import 'dart:io';

/// A libp2p-style listen multiaddr this build can dial (`/ip4|ip6/.../tcp/PORT`).
bool isDialHint(String raw) {
  final s = raw.trim();
  if (!(s.startsWith('/ip4/') || s.startsWith('/ip6/'))) return false;
  return RegExp(r'/tcp/\d+$').hasMatch(s);
}

/// Port from `/ip4/127.0.0.1/tcp/41234`. Null if the string is not a TCP addr.
int? listenPortFromMultiaddr(String? multiaddr) {
  if (multiaddr == null) return null;
  final match = RegExp(r'/tcp/(\d+)$').firstMatch(multiaddr.trim());
  if (match == null) return null;
  final port = int.tryParse(match.group(1)!);
  if (port == null || port <= 0 || port > 65535) return null;
  return port;
}

/// Non-loopback IPv4 listen addrs on this device, same port the node bound.
///
/// The core advertises `127.0.0.1` so same-host tests can dial. Another phone
/// cannot use that, so the card and the connect dialog list these instead.
Future<List<String>> lanListenMultiaddrs(int port) async {
  if (port <= 0 || port > 65535) return const [];
  try {
    final ifaces = await NetworkInterface.list(
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );
    final out = <String>[];
    for (final iface in ifaces) {
      for (final addr in iface.addresses) {
        if (addr.isLoopback) continue;
        out.add('/ip4/${addr.address}/tcp/$port');
      }
    }
    return out;
  } catch (_) {
    return const [];
  }
}
