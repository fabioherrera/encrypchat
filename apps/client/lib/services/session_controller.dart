import 'package:flutter/foundation.dart';

import '../core/encrypchat_core.dart';
import '../models/contact.dart';
import 'identity_service.dart';
import 'local_database.dart';
import 'messaging_service.dart';

enum AppPhase { loading, needsOnboarding, ready, error }

/// Owns identity + DB + messaging lifecycle for the shell.
class SessionController extends ChangeNotifier {
  SessionController({
    EncrypchatCore? core,
    IdentityService? identity,
    LocalDatabase? database,
    MessagingService? messaging,
  })  : _core = core,
        _identity = identity,
        _database = database ?? LocalDatabase(),
        _messagingInjected = messaging;

  EncrypchatCore? _core;
  IdentityService? _identity;
  final LocalDatabase _database;
  final MessagingService? _messagingInjected;
  MessagingService? _messaging;

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
    } catch (e, st) {
      debugPrint('bootstrap failed: $e\n$st');
      errorMessage = e.toString();
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
    _messaging = _messagingInjected ??
        MessagingService(
          core: core,
          identity: identity,
          database: _database,
        );
    _messaging!.addListener(notifyListeners);
    try {
      await _messaging!.startNode();
    } catch (e, st) {
      debugPrint('node start failed: $e\n$st');
      // Still allow UI; connect/send will fail loud.
    }
    phase = AppPhase.ready;
    notifyListeners();
  }

  Future<void> refreshContacts() async {
    contacts = await _database.listContacts();
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
    _messaging?.removeListener(notifyListeners);
    _messaging?.dispose();
    _database.close();
    super.dispose();
  }
}
