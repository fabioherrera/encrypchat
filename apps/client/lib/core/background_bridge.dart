import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android background delivery and local notifications. A no-op elsewhere, so
/// callers do not branch per platform.
class BackgroundBridge {
  const BackgroundBridge();

  static const _background = MethodChannel('encrypchat/background');
  static const _activity = MethodChannel('encrypchat/updates');

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<void> _call(
    MethodChannel channel,
    String method, [
    Map<String, Object?>? args,
  ]) async {
    if (!isSupported) return;
    try {
      await channel.invokeMethod<void>(method, args);
    } on PlatformException catch (e) {
      debugPrint('background $method failed: ${e.code}');
    } on MissingPluginException {
      // The engine has no activity attached yet.
      debugPrint('background $method: channel not bound');
    }
  }

  Future<void> start() => _call(_background, 'start');
  Future<void> stop() => _call(_background, 'stop');

  Future<void> setInCall(bool active) =>
      _call(_background, 'setInCall', {'active': active});

  Future<void> notifyMessage(String name) =>
      _call(_background, 'notifyMessage', {'name': name});

  Future<void> notifyCall(String name) =>
      _call(_background, 'notifyCall', {'name': name});

  Future<void> cancelCall() => _call(_background, 'cancelCall');
  Future<void> clearMessages() => _call(_background, 'clearMessages');

  Future<void> requestNotifications() =>
      _call(_activity, 'requestNotifications');

  Future<void> requestBatteryExemption() =>
      _call(_activity, 'requestBatteryExemption');
}
