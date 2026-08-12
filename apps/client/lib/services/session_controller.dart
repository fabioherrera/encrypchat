import 'package:flutter/foundation.dart';

import '../core/encrypchat_core.dart';
import '../models/contact.dart';
import 'identity_service.dart';
import 'local_database.dart';

enum AppPhase { loading, needsOnboarding, ready, error }

/// Owns identity + DB lifecycle for the shell.
class SessionController extends ChangeNotifier {
  SessionController({
    EncrypchatCore? core,
    IdentityService? identity,
    LocalDatabase? database,
  })  : _core = core,
        _identity = identity,
        _database = database ?? LocalDatabase();

  EncrypchatCore? _core;
  IdentityService? _identity;
  final LocalDatabase _database;

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
      await _database.upsertProfile(
        token: _identity!.token!,
        publicKey: _identity!.publicKey!,
      );
      contacts = await _database.listContacts();
      phase = AppPhase.ready;
      notifyListeners();
    } catch (e, st) {
      debugPrint('bootstrap failed: $e\n$st');
      errorMessage = e.toString();
      phase = AppPhase.error;
      notifyListeners();
    }
  }

  Future<void> createIdentity() async {
    await identity.create();
    await _database.upsertProfile(
      token: identity.token!,
      publicKey: identity.publicKey!,
    );
    contacts = await _database.listContacts();
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

  @override
  void dispose() {
    _database.close();
    super.dispose();
  }
}
