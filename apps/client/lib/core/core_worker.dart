import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'core_error.dart';
import 'encrypchat_core.dart';

/// Runs the node's **blocking** FFI calls off the UI isolate.
///
/// `docs/ffi-contract.md` gives each one a budget: `node_send` waits up to 15 s
/// for the peer's ACK, `node_connect` up to 10 s for the dial and handshake. On
/// the main isolate that is a frozen interface with no dialog and no way out —
/// and on Android, an ANR (F-11).
///
/// Design notes, because two of them are load-bearing:
///
/// - **One worker, not a pool.** Commands are processed in the order they were
///   sent, which is the ordering a conversation needs. A pool would let a second
///   message overtake a first one that is waiting on a slow ACK.
/// - **The node handle travels as an integer.** A `Pointer` cannot cross an
///   isolate boundary but its address can, and the contract allows concurrent
///   `encrypchat_node_*` calls from any thread — which is exactly what this is:
///   `try_recv` keeps polling on the main isolate (it never blocks) while a send
///   waits here.
/// - **`node_stop` goes through the queue too.** That is what makes the shared
///   handle safe: stopping is enqueued behind every send already in flight, so
///   the node is never freed while another call is inside it.
class CoreWorker {
  CoreWorker._(this._isolate, this._commands, this._responses, this._sub);

  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _responses;
  final StreamSubscription<dynamic> _sub;

  final Map<int, Completer<void>> _pending = {};
  int _nextId = 1;
  bool _closed = false;

  /// How long the isolate gets to come up and report its command port.
  static const _handshakeTimeout = Duration(seconds: 5);

  /// Spawns the worker, or returns `null` when the platform will not give us
  /// one. The caller then keeps calling on its own isolate: a frozen frame is
  /// bad, refusing to send at all is worse.
  static Future<CoreWorker?> spawn() async {
    final responses = ReceivePort();
    final ready = Completer<SendPort>();
    CoreWorker? worker;
    // One port both ways: the first message is the worker's command port, every
    // later one is a `[id, code, detail]` reply.
    final sub = responses.listen((message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      worker?._onResponse(message);
    });
    try {
      final isolate = await Isolate.spawn(
        _workerMain,
        responses.sendPort,
        debugName: 'encrypchat-core',
      );
      final commands = await ready.future.timeout(_handshakeTimeout);
      worker = CoreWorker._(isolate, commands, responses, sub);
      return worker;
    } catch (e) {
      await sub.cancel();
      responses.close();
      debugPrint('core worker unavailable: ${e.runtimeType}');
      return null;
    }
  }

  Future<void> _call(String op, List<Object?> args) {
    if (_closed) {
      throw StateError('Core worker closed');
    }
    final id = _nextId++;
    final completer = Completer<void>();
    _pending[id] = completer;
    _commands.send([id, op, ...args]);
    return completer.future;
  }

  void _onResponse(dynamic message) {
    final reply = message as List<Object?>;
    final completer = _pending.remove(reply[0] as int);
    if (completer == null) return;
    final code = reply[1] as int;
    if (code == 0) {
      completer.complete();
      return;
    }
    completer.completeError(
      code < 0
          ? StateError(reply[2] as String? ?? 'core worker failed')
          : CoreException(code, reply[2] as String?),
    );
  }

  /// `encrypchat_node_send`: up to 15 s waiting for the peer's ACK.
  Future<void> send({
    required int handleAddress,
    required String peerToken,
    required Uint8List frame,
  }) => _call('send', [handleAddress, peerToken, frame]);

  /// `encrypchat_node_connect`: up to 10 s to dial and finish EH02.
  Future<void> connect({
    required int handleAddress,
    required String multiaddr,
  }) => _call('connect', [handleAddress, multiaddr]);

  /// Stops the node **after** every command already queued, then lets the
  /// isolate exit. Never throws: teardown is not a place to fail.
  Future<void> stopNodeAndClose(int? handleAddress) async {
    if (_closed) return;
    try {
      await _call('stop', [handleAddress ?? 0]);
    } catch (e) {
      debugPrint('core worker stop failed: ${e.runtimeType}');
    }
    close();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Core worker closed'));
      }
    }
    _pending.clear();
    unawaited(_sub.cancel());
    _responses.close();
    // `beforeNextEvent`, never `immediate`: an isolate sitting inside a native
    // call cannot be killed anyway, and the node handle it is holding must not
    // be freed under it.
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }
}

/// Worker entry point. Opens its own view of the library — `dlopen` on a library
/// already loaded in the process returns the same one, so this is a second set
/// of function pointers, not a second copy of the core.
void _workerMain(SendPort responses) {
  final commands = ReceivePort();
  responses.send(commands.sendPort);
  EncrypchatCore? core;

  commands.listen((message) {
    final request = message as List<Object?>;
    final id = request[0] as int;
    final op = request[1] as String;
    try {
      core ??= EncrypchatCore.open();
      switch (op) {
        case 'send':
          core!.nodeSend(
            handleAddress: request[2] as int,
            peerToken: request[3] as String,
            frame: request[4] as Uint8List,
          );
        case 'connect':
          core!.nodeConnect(
            request[3] as String,
            handleAddress: request[2] as int,
          );
        case 'stop':
          core!.nodeStopAt(request[2] as int);
        default:
          throw StateError('unknown op $op');
      }
      responses.send([id, 0, null]);
    } on CoreException catch (e) {
      responses.send([id, e.code, e.message]);
    } catch (e) {
      // Negative codes cannot collide with a `CoreError`, so the caller can
      // tell "the core said no" from "the bridge broke".
      responses.send([id, -1, e.toString()]);
    }
    if (op == 'stop') commands.close();
  });
}
