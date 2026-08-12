import 'dart:convert';
import 'dart:typed_data';

/// Call signaling over Encrypchat E2EE (not persisted as chat bubbles).
///
/// JSON UTF-8: `{"v":1,"kind":"call",...}`
enum CallSignalType { invite, accept, reject, hangup, sdpOffer, sdpAnswer, ice }

enum CallMediaMode { audio, av }

class CallSignal {
  CallSignal({
    required this.type,
    required this.callId,
    required this.media,
    this.sdp,
    this.candidate,
    this.sentAtUnix,
  });

  static const schemaVersion = 1;
  static const kind = 'call';
  static const maxSdpChars = 64 * 1024;
  static const maxCandidateChars = 8 * 1024;

  final CallSignalType type;
  final String callId;
  final CallMediaMode media;
  final String? sdp;
  final Map<String, dynamic>? candidate;

  /// When the sender says it wrote this, in Unix seconds (`ts`).
  ///
  /// Inside the E2EE payload, so it cannot be edited in transit, but it is the
  /// sender's clock: a claim, not a trusted time. `null` means the peer runs a
  /// build from before the field existed — see `CallService` for what that costs.
  final int? sentAtUnix;

  /// Same signal, stamped with this device's clock. Called on the way out so the
  /// stamp comes from one place instead of every construction site.
  CallSignal stamped(int sentAtUnix) => CallSignal(
    type: type,
    callId: callId,
    media: media,
    sdp: sdp,
    candidate: candidate,
    sentAtUnix: sentAtUnix,
  );

  static bool looksLike(Uint8List bytes) {
    if (bytes.isEmpty || bytes[0] != 0x7b) return false; // '{'
    try {
      final map = jsonDecode(utf8.decode(bytes));
      return map is Map && map['kind'] == kind && map['v'] == schemaVersion;
    } catch (_) {
      return false;
    }
  }

  static CallSignal decode(Uint8List bytes) {
    final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (map['kind'] != kind || map['v'] != schemaVersion) {
      throw const FormatException('Not a call signal');
    }
    final typeName = map['type'] as String? ?? '';
    final type = switch (typeName) {
      'invite' => CallSignalType.invite,
      'accept' => CallSignalType.accept,
      'reject' => CallSignalType.reject,
      'hangup' => CallSignalType.hangup,
      'sdp-offer' => CallSignalType.sdpOffer,
      'sdp-answer' => CallSignalType.sdpAnswer,
      'ice' => CallSignalType.ice,
      _ => throw FormatException('Unknown call type: $typeName'),
    };
    final mediaName = map['media'] as String? ?? 'audio';
    final media = mediaName == 'av' ? CallMediaMode.av : CallMediaMode.audio;
    final callId = map['callId'] as String? ?? '';
    if (callId.isEmpty || callId.length > 128) {
      throw const FormatException('Invalid callId');
    }
    final sdp = map['sdp'] as String?;
    if (sdp != null && sdp.length > maxSdpChars) {
      throw const FormatException('SDP demasiado grande');
    }
    Map<String, dynamic>? cand;
    final rawCand = map['candidate'];
    if (rawCand is Map) {
      cand = Map<String, dynamic>.from(rawCand);
      final cStr = cand['candidate'] as String? ?? '';
      if (cStr.length > maxCandidateChars) {
        throw const FormatException('ICE candidate demasiado grande');
      }
    }
    final ts = map['ts'];
    return CallSignal(
      type: type,
      callId: callId,
      media: media,
      sdp: sdp,
      candidate: cand,
      // Absent or not a number reads as unstamped, never as zero: `0` would look
      // like 1970 and be judged stale by the freshness check.
      sentAtUnix: ts is int && ts > 0 ? ts : null,
    );
  }

  Uint8List encode() {
    final map = <String, dynamic>{
      'v': schemaVersion,
      'kind': kind,
      'type': switch (type) {
        CallSignalType.invite => 'invite',
        CallSignalType.accept => 'accept',
        CallSignalType.reject => 'reject',
        CallSignalType.hangup => 'hangup',
        CallSignalType.sdpOffer => 'sdp-offer',
        CallSignalType.sdpAnswer => 'sdp-answer',
        CallSignalType.ice => 'ice',
      },
      'callId': callId,
      'media': media == CallMediaMode.av ? 'av' : 'audio',
    };
    if (sentAtUnix != null) map['ts'] = sentAtUnix;
    if (sdp != null) map['sdp'] = sdp;
    if (candidate != null) map['candidate'] = candidate;
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }
}
