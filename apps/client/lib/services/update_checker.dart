import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/app_version.dart';
import '../core/legal_links.dart';

enum UpdateStatus { idle, checking, current, available, failed }

enum UpdateChannel {
  androidApk,
  linuxRpm,
  linuxTarball,
  windowsSetup;

  /// Fedora RPM install puts the binary under `/usr/lib64/encrypchat`.
  /// Anything else on Linux is treated as the portable tarball.
  static UpdateChannel? detect() {
    if (kIsWeb) return null;
    if (Platform.isAndroid) return UpdateChannel.androidApk;
    if (Platform.isWindows) return UpdateChannel.windowsSetup;
    if (Platform.isLinux) {
      if (File('/usr/lib64/encrypchat/encrypchat').existsSync()) {
        return UpdateChannel.linuxRpm;
      }
      return UpdateChannel.linuxTarball;
    }
    return null;
  }
}

@immutable
class UpdatePackage {
  const UpdatePackage({
    required this.url,
    required this.sha256,
    required this.fileName,
    required this.channel,
  });

  final Uri url;
  final String sha256;
  final String fileName;
  final UpdateChannel channel;
}

/// Result of comparing this binary to the public catalog on encrypchat.com.
///
/// The catalog is a static JSON file. The request carries no token, no chat
/// data, and no device id. Cloudflare and the origin server still see IP /
/// user-agent / time, as with any visit to the site — see the privacy page,
/// section actualizaciones.
@immutable
class UpdateInfo {
  const UpdateInfo({
    required this.status,
    required this.currentVersion,
    this.latestVersion,
    this.downloadUrl,
    this.notes,
    this.package,
  });

  final UpdateStatus status;
  final String currentVersion;
  final String? latestVersion;
  final String? downloadUrl;
  final String? notes;
  final UpdatePackage? package;

  bool get hasUpdate => status == UpdateStatus.available;

  /// Auto-apply is only offered when the catalog named a file and a hash for
  /// this OS. Missing either means "open the download page" instead.
  bool get canApply => hasUpdate && package != null;
}

class UpdateChecker extends ChangeNotifier {
  UpdateChecker({
    http.Client? client,
    this.currentVersion = encrypchatVersion,
    this.catalogUri,
    UpdateChannel? channel,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       channel = channel ?? UpdateChannel.detect();

  final http.Client _client;
  final bool _ownsClient;
  final String currentVersion;
  final Uri? catalogUri;
  final UpdateChannel? channel;

  UpdateInfo _info = const UpdateInfo(
    status: UpdateStatus.idle,
    currentVersion: encrypchatVersion,
  );
  bool _disposed = false;

  UpdateInfo get info => _info;

  Uri get _uri => catalogUri ?? Uri.parse('${LegalLinks.site}/latest.json');

  /// Widget tests set `FLUTTER_TEST`; a real GET would be slow or flaky.
  static bool get runningInTest =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  Future<void> check({bool force = false}) async {
    if (_disposed) return;
    if (!force && runningInTest && catalogUri == null) return;
    if (!force &&
        (_info.status == UpdateStatus.checking ||
            _info.status == UpdateStatus.available ||
            _info.status == UpdateStatus.current)) {
      return;
    }
    _info = UpdateInfo(
      status: UpdateStatus.checking,
      currentVersion: currentVersion,
    );
    notifyListeners();
    try {
      final res = await _client.get(_uri).timeout(const Duration(seconds: 8));
      if (_disposed) return;
      if (res.statusCode != 200) {
        _fail();
        return;
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is! Map) {
        _fail();
        return;
      }
      final latest = body['version'] as String?;
      if (latest == null || latest.isEmpty) {
        _fail();
        return;
      }
      final download = body['download'] as String?;
      final notes = body['notes'] as String?;
      final newer = compareSemver(latest, currentVersion) > 0;
      _info = UpdateInfo(
        status: newer ? UpdateStatus.available : UpdateStatus.current,
        currentVersion: currentVersion,
        latestVersion: latest,
        downloadUrl: download,
        notes: notes,
        package: newer ? packageFromCatalog(body, channel) : null,
      );
      notifyListeners();
    } catch (_) {
      if (_disposed) return;
      _fail();
    }
  }

  void _fail() {
    _info = UpdateInfo(
      status: UpdateStatus.failed,
      currentVersion: currentVersion,
    );
    notifyListeners();
  }

  /// Picks the catalog entry for this device. Returns null when the OS has
  /// no package (iOS, Windows until a zip exists) or the entry lacks a hash.
  static UpdatePackage? packageFromCatalog(
    Map<dynamic, dynamic> body,
    UpdateChannel? channel,
  ) {
    if (channel == null) return null;
    final packages = body['packages'];
    if (packages is! Map) return null;
    final key = switch (channel) {
      UpdateChannel.androidApk => 'android-apk',
      UpdateChannel.linuxRpm => 'linux-rpm',
      UpdateChannel.linuxTarball => 'linux-tarball',
      UpdateChannel.windowsSetup => 'windows-setup',
    };
    final entry = packages[key];
    if (entry is! Map) return null;
    final urlRaw = entry['url'] as String?;
    final sha = (entry['sha256'] as String?)?.trim().toLowerCase();
    final name = entry['file'] as String?;
    if (urlRaw == null || sha == null || sha.length != 64 || name == null) {
      return null;
    }
    final url = Uri.tryParse(urlRaw);
    if (url == null || !url.isScheme('https')) return null;
    return UpdatePackage(
      url: url,
      sha256: sha,
      fileName: name,
      channel: channel,
    );
  }

  /// `-1` if [a] < [b], `0` if equal, `1` if [a] > [b]. Build metadata (`+n`)
  /// and pre-release suffixes are ignored: `1.0.0+2` equals `1.0.0`.
  static int compareSemver(String a, String b) {
    final pa = _parse(a);
    final pb = _parse(b);
    for (var i = 0; i < 3; i++) {
      if (pa[i] < pb[i]) return -1;
      if (pa[i] > pb[i]) return 1;
    }
    return 0;
  }

  static List<int> _parse(String version) {
    final core = version.split(RegExp(r'[-+]')).first;
    final parts = core.split('.');
    return [
      for (var i = 0; i < 3; i++)
        i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0,
    ];
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsClient) _client.close();
    super.dispose();
  }
}
