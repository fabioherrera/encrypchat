import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/background_bridge.dart';
import '../core/core_error.dart';
import '../core/default_relay.dart';
import '../core/encrypchat_core.dart';
import '../models/contact.dart';
import '../models/message_request.dart';
import 'call_service.dart';
import 'identity_service.dart';
import 'identity_wipe.dart';
import 'local_database.dart';
import 'messaging_service.dart';

enum AppPhase { loading, needsOnboarding, ready, error }

/// Owns identity + DB + messaging + calls lifecycle for the shell.
class SessionController extends ChangeNotifier {
  SessionController({
    EncrypchatCore? core,
    IdentityService? identity,
    LocalDatabase? database,
    MessagingService? messaging,
    CallService? calls,
    FlutterSecureStorage? storage,
    BackgroundBridge background = const BackgroundBridge(),
  }) : _background = background,
       _core = core,
       _identity = identity,
       _database = database ?? LocalDatabase(),
       _messagingInjected = messaging,
       _callsInjected = calls,
       _storage =
           storage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(encryptedSharedPreferences: true),
           );

  static const _backgroundKey = 'background_delivery_v1';
  static const _autoUpdateKey = 'auto_update_v1';

  final BackgroundBridge _background;
  EncrypchatCore? _core;
  IdentityService? _identity;
  final LocalDatabase _database;
  final MessagingService? _messagingInjected;
  final CallService? _callsInjected;
  final FlutterSecureStorage _storage;
  MessagingService? _messaging;
  CallService? _calls;

  AppPhase phase = AppPhase.loading;
  String? errorMessage;
  List<Contact> contacts = const [];

  EncrypchatCore get core {
    final c = _core;
    if (c == null) throw StateError('Core not initialized');
    return c;
  }

  IdentityService get identity {
    final i = _identity;
    if (i == null) throw StateError('Identity not initialized');
    return i;
  }

  LocalDatabase get database => _database;

  /// Token of the identity in use, or null while there is none. Screens that
  /// only need to name the local identity ask here instead of reaching for the
  /// service that holds the secret.
  String? get ownToken => _identity?.token;

  MessagingService get messaging {
    final m = _messaging;
    if (m == null) throw StateError('Messaging not initialized');
    return m;
  }

  CallService? get calls => _calls;

  bool get hasMessaging => _messaging != null;

  bool get supportsBackgroundDelivery => _background.isSupported;

  /// Android only: stay connected with the app closed.
  bool backgroundDelivery = true;

  /// Install signed updates without asking.
  bool autoUpdate = true;

  bool _visible = true;
  bool _ringing = false;
  bool _callHeld = false;

  /// True during a call, when an update must not close the app.
  bool get inCall {
    final phase = _calls?.phase;
    return phase != null && phase != CallPhase.idle && phase != CallPhase.ended;
  }

  bool get isVisible => _visible;

  Future<void> bootstrap() async {
    phase = AppPhase.loading;
    errorMessage = null;
    notifyListeners();
    try {
      _core ??= EncrypchatCore.open();
      _identity ??= IdentityService(core: _core!);
      // Before the database: a wipe that was interrupted still has files whose
      // key is already gone, and opening first would mint a new `db_key`, fail
      // to read them with it, and report a corrupt database instead of finishing
      // what the user asked for.
      await IdentityWipe.resumeIfPending(_storage);
      await _database.open();
      final loaded = await _identity!.load();
      if (!loaded) {
        phase = AppPhase.needsOnboarding;
        notifyListeners();
        return;
      }
      await _enterReady();
    } on CoreVersionException catch (e) {
      // Safe to print: it describes the library on disk, not anything of the user's.
      debugPrint('core too old: ${e.found}');
      errorMessage = e.message;
      phase = AppPhase.error;
      notifyListeners();
    } on LocalDatabaseKeyException catch (e) {
      // Retrying cannot help, but the message has to say why, since the only
      // way out costs the local history.
      errorMessage = e.message;
      phase = AppPhase.error;
      notifyListeners();
    } on LocalDatabaseMigrationException catch (e) {
      debugPrint('local db migration failed: ${e.reason}');
      errorMessage = e.message;
      phase = AppPhase.error;
      notifyListeners();
    } catch (e) {
      // A decode failure on the stored secret would echo key material otherwise,
      // so neither the log nor the screen gets the exception text.
      debugPrint('bootstrap failed: ${e.runtimeType}');
      errorMessage =
          'No se pudo abrir el almacenamiento local (${e.runtimeType}).';
      phase = AppPhase.error;
      notifyListeners();
    }
  }

  Future<void> createIdentity() async {
    await identity.create();
    await _enterReady();
  }

  Future<void> _enterReady() async {
    await _database.upsertProfile(
      token: identity.token!,
      publicKey: identity.publicKey!,
    );
    contacts = await _database.listContacts();
    _messaging =
        _messagingInjected ??
        MessagingService(
          core: core,
          identity: identity,
          database: _database,
          defaultRelayUrl: encrypchatDefaultRelayUrl,
        );
    _messaging!.setContacts(contacts);
    await _messaging!.loadBlocked();
    await _messaging!.loadRequests();
    _messaging!.addListener(notifyListeners);
    _messaging!.onInboundMessage = _onInboundMessage;
    _calls = _callsInjected ?? CallService(messaging: _messaging!);
    _calls!.addListener(notifyListeners);
    _calls!.addListener(_onCallChanged);
    try {
      await _messaging!.startNode();
    } catch (e) {
      debugPrint('node start failed: ${e.runtimeType}');
    }
    await _loadPreferences();
    phase = AppPhase.ready;
    notifyListeners();
  }

  Future<void> _loadPreferences() async {
    try {
      backgroundDelivery = await _storage.read(key: _backgroundKey) != 'off';
      autoUpdate = await _storage.read(key: _autoUpdateKey) != 'off';
    } catch (e) {
      debugPrint('preferences unreadable: ${e.runtimeType}');
    }
    if (_background.isSupported && backgroundDelivery) {
      await _background.start();
    }
  }

  Future<void> setBackgroundDelivery(bool on) async {
    backgroundDelivery = on;
    await _storage.write(key: _backgroundKey, value: on ? 'on' : 'off');
    if (on) {
      await _background.requestNotifications();
      await _background.requestBatteryExemption();
      await _background.start();
    } else {
      await _background.stop();
    }
    notifyListeners();
  }

  Future<void> setAutoUpdate(bool on) async {
    autoUpdate = on;
    await _storage.write(key: _autoUpdateKey, value: on ? 'on' : 'off');
    notifyListeners();
  }

  /// First time the shell is on screen: Android only shows these prompts with an
  /// activity attached, which a boot in the background does not have.
  Future<void> requestBackgroundPermissions() async {
    if (!_background.isSupported || !backgroundDelivery) return;
    await _background.requestNotifications();
    await _background.requestBatteryExemption();
    await _background.start();
  }

  /// Fed from the app lifecycle.
  void setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    _messaging?.setBackgrounded(!visible);
    if (visible) {
      _messaging?.onAppResumed();
      unawaited(_background.clearMessages());
    }
  }

  void _onInboundMessage(String fromToken) {
    if (_visible) return;
    unawaited(
      _background.notifyMessage(contactByToken(fromToken)?.label ?? ''),
    );
  }

  void _onCallChanged() {
    final calls = _calls;
    if (calls == null) return;
    final ringing = calls.phase == CallPhase.incoming;
    if (ringing != _ringing) {
      _ringing = ringing;
      if (ringing) {
        if (!_visible) {
          unawaited(_background.notifyCall(calls.peer?.label ?? ''));
        }
      } else {
        unawaited(_background.cancelCall());
      }
    }
    final held =
        calls.phase == CallPhase.outgoing ||
        calls.phase == CallPhase.connecting ||
        calls.phase == CallPhase.active;
    if (held != _callHeld) {
      _callHeld = held;
      unawaited(_background.setInCall(held));
    }
  }

  /// Erases this identity and everything it left on the device, then drops the
  /// app back to onboarding.
  ///
  /// The mark goes first, so from here on the wipe is the only state the app can
  /// come back to — a crash mid-way is finished by [bootstrap], not left as an
  /// identity that half exists. The live session is torn down before anything is
  /// deleted: the node holds a copy of the secret, a call would keep the mic and
  /// camera open, and the database has to be closed before its file goes.
  ///
  /// Rebooting through [bootstrap] afterwards is deliberate — it is the same
  /// path a fresh install takes, so there is no second definition of what an
  /// empty device looks like.
  Future<IdentityWipeReport> deleteIdentity() async {
    await IdentityWipe.markPending(_storage);
    await _shutdownSession();
    final report = await IdentityWipe.run(_storage);
    await bootstrap();
    return report;
  }

  /// Stops everything that is running and forgets the secret held in memory.
  /// Ordered so that nothing is still using what the next step deletes.
  Future<void> _shutdownSession() async {
    final calls = _calls;
    _calls = null;
    if (calls != null) {
      calls.removeListener(notifyListeners);
      calls.removeListener(_onCallChanged);
      // Sent while the node is still up: the peer on the other side gets a
      // hangup instead of a call that goes quiet.
      try {
        await calls.hangup();
      } catch (e) {
        debugPrint('wipe: call teardown failed (${e.runtimeType})');
      }
      calls.dispose();
    }
    final messaging = _messaging;
    _messaging = null;
    if (messaging != null) {
      messaging.removeListener(notifyListeners);
      await messaging.stopNode();
      messaging.dispose();
    }
    await _background.stop();
    _identity?.forget();
    contacts = const [];
    await _database.close();
  }

  Future<void> refreshContacts() async {
    contacts = await _database.listContacts();
    _messaging?.setContacts(contacts);
    notifyListeners();
  }

  /// Imports a card, whether it was pasted or scanned from a QR — both carry the
  /// same export line, so this is the single place the check has to hold.
  ///
  /// The key is put to the core before anything is stored, and
  /// `InvalidPublicKey` (2) is reported as a malformed card rather than as a
  /// failure worth retrying. Storing it and finding out on the first send would
  /// leave a contact that looks fine and cannot be written to; worse, a
  /// non-canonical key is an alias with a token of its own, which is how a
  /// blocked peer came back under a name nobody had blocked (F-10). Nothing here
  /// ever re-encodes a key to make it fit.
  Future<Contact> importContact(String raw) async {
    final contact = Contact.parseExport(raw);
    try {
      core.assertUsablePublicKey(
        senderSecret: identity.requireSecret(),
        publicKey: contact.publicKey,
      );
    } on CoreException catch (e) {
      if (e.code == CoreException.invalidPublicKey) {
        throw ContactCardException.malformedKey;
      }
      rethrow;
    }
    if (contact.token == identity.token) {
      throw const ContactCardException(
        'Esa tarjeta es la tuya: no puedes agregarte como contacto.',
      );
    }
    await _database.upsertContact(contact);
    final messaging = _messaging;
    if (messaging != null && contact.dialHints.isNotEmpty) {
      messaging.rememberDialHints(contact.token, contact.dialHints);
    }
    await refreshContacts();
    return contact;
  }

  /// After a successful import: try to tell the other device so they see
  /// Solicitudes. No route means they will not see anything until a later
  /// connect or relay.
  Future<ContactAnnounce> announceNewContact(Contact contact) async {
    if (!hasMessaging) return ContactAnnounce.noRoute;
    return messaging.sendContactIntro(contact);
  }

  Future<void> addContact({
    required String token,
    required String publicKeyHex,
    String? displayName,
  }) async {
    final line =
        'encrypchat:contact:v1:$token:$publicKeyHex:${Uri.encodeComponent(displayName ?? '')}';
    await importContact(line);
  }

  /// Deleting a contact takes their conversation with it.
  ///
  /// The chat list walks contacts, so a thread whose contact is gone would be
  /// unreachable: impossible to read, to delete, or to see growing. That is the
  /// same invisibility as F-6, reached from the other end, so the history is
  /// removed instead of orphaned — and the dialog says so before doing it.
  Future<void> removeContact(String token) async {
    await _messaging?.deleteConversation(token);
    _messaging?.forgetPeerRoute(token);
    await _database.deleteContact(token);
    await refreshContacts();
  }

  /// Message requests from identities that are not contacts.
  List<MessageRequest> get requests => _messaging?.requests ?? const [];

  Future<void> acceptRequest(
    MessageRequest request, {
    String? displayName,
  }) async {
    await messaging.acceptRequest(request, displayName: displayName);
    await refreshContacts();
  }

  Future<void> discardRequest(String token, {bool alsoBlock = false}) async {
    await messaging.discardRequest(token, alsoBlock: alsoBlock);
    notifyListeners();
  }

  /// Blocked tokens, whether or not they are still saved as contacts.
  List<String> get blockedTokens => _messaging?.blockedTokens ?? const [];

  bool isBlocked(String token) => _messaging?.isBlocked(token) ?? false;

  Future<void> blockContact(String token) async {
    await messaging.block(token);
    notifyListeners();
  }

  Future<void> unblockContact(String token) async {
    await messaging.unblock(token);
    notifyListeners();
  }

  String exportOwnContact({String? displayName}) {
    return Contact(
      token: identity.token!,
      publicKey: identity.publicKey!,
      displayName: displayName,
      dialHints: hasMessaging ? messaging.lanListenAddrs : const [],
    ).exportLine();
  }

  Contact? contactByToken(String token) {
    for (final c in contacts) {
      if (c.token == token) return c;
    }
    return null;
  }

  @override
  void dispose() {
    _calls?.removeListener(notifyListeners);
    _calls?.removeListener(_onCallChanged);
    _calls?.dispose();
    _messaging?.removeListener(notifyListeners);
    _messaging?.dispose();
    _database.close();
    super.dispose();
  }
}
