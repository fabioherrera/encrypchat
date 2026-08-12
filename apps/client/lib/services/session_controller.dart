import 'package:flutter/foundation.dart';

import '../core/core_error.dart';
import '../core/encrypchat_core.dart';
import '../models/contact.dart';
import 'call_service.dart';
import 'identity_service.dart';
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
  }) : _core = core,
       _identity = identity,
       _database = database ?? LocalDatabase(),
       _messagingInjected = messaging,
       _callsInjected = calls;

  EncrypchatCore? _core;
  IdentityService? _identity;
  final LocalDatabase _database;
  final MessagingService? _messagingInjected;
  final CallService? _callsInjected;
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

  MessagingService get messaging {
    final m = _messaging;
    if (m == null) throw StateError('Messaging not initialized');
    return m;
  }

  CallService? get calls => _calls;

  bool get hasMessaging => _messaging != null;

  Future<void> bootstrap() async {
    phase = AppPhase.loading;
    errorMessage = null;
    notifyListeners();
    try {
      _core ??= EncrypchatCore.open();
      _identity ??= IdentityService(core: _core!);
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
        MessagingService(core: core, identity: identity, database: _database);
    _messaging!.setContacts(contacts);
    await _messaging!.loadBlocked();
    _messaging!.addListener(notifyListeners);
    _calls = _callsInjected ?? CallService(messaging: _messaging!);
    _calls!.addListener(notifyListeners);
    try {
      await _messaging!.startNode();
    } catch (e) {
      debugPrint('node start failed: ${e.runtimeType}');
    }
    phase = AppPhase.ready;
    notifyListeners();
  }

  Future<void> refreshContacts() async {
    contacts = await _database.listContacts();
    _messaging?.setContacts(contacts);
    notifyListeners();
  }

  Future<void> importContact(String raw) async {
    final contact = Contact.parseExport(raw);
    if (contact.token == identity.token) {
      throw StateError('Cannot import your own token as a contact');
    }
    await _database.upsertContact(contact);
    await refreshContacts();
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

  Future<void> removeContact(String token) async {
    await _database.deleteContact(token);
    await refreshContacts();
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
    _calls?.dispose();
    _messaging?.removeListener(notifyListeners);
    _messaging?.dispose();
    _database.close();
    super.dispose();
  }
}
