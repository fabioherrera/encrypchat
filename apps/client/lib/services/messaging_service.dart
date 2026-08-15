import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/core_error.dart';
import '../core/core_worker.dart';
import '../core/default_relay.dart';
import '../core/encrypchat_core.dart';
import '../core/call_signal.dart';
import '../core/contact_intro.dart';
import '../core/lan_listen.dart';
import '../core/media_envelope.dart';
import '../core/wire_frame.dart';
import '../models/chat_message.dart';
import '../models/contact.dart';
import '../models/message_request.dart';
import 'identity_service.dart';
import 'local_database.dart';
import 'media_store.dart';
import 'relay_client.dart';

/// Why something that arrived never became a message, on either route.
///
/// The core's error codes are not interchangeable and neither are these: an old
/// client is a compatibility problem the peer can fix, a forged sender is an
/// attack, and an expired blob is genuine but stale. Blurring them into
/// "inbound error" would hide the only one that means somebody tried something.
enum InboundDropReason {
  /// `InvalidFrame` (10): not an `ECS1` blob, so a pre-0.8.0 client sent it.
  legacyFormat,

  /// `CiphertextTooShort` (4).
  truncated,

  /// `DecryptionFailed` (3): not addressed to this identity.
  notForUs,

  /// `AuthFailed` (11): addressed to us, but the sender binding does not hold.
  forged,

  /// `InvalidPublicKey` (2): the sender key is a non-canonical encoding — the
  /// same key under a second token, which is how a blocked peer came back (F-10).
  malformedSenderKey,

  /// `Expired` (13): authenticated, then rejected by the freshness window.
  expired,

  /// The same authentic blob arrived twice.
  replay,

  /// Call signaling by relay, which is not enabled.
  callSignal,

  /// Opened and authenticated, but the payload inside did not parse.
  unreadable,

  /// A non-contact tried to send an attachment. Requests are text-only.
  strangerMedia,

  /// A non-contact tried to call. Strangers never ring.
  strangerCall,

  /// Too many pending requests already: this stranger did not get a slot.
  requestsFull,

  /// A pending stranger used up the messages it gets before being accepted.
  senderFull,

  /// A non-contact sent something bigger than a request is allowed to be —
  /// either measured after opening it, or refused on the wire without opening
  /// it at all.
  strangerTooLong,

  /// An attachment from a contact would break a media ceiling.
  mediaQuota,
}

/// What happened when this device tried to tell a new contact it was added.
enum ContactAnnounce { delivered, viaRelay, noRoute }

extension InboundDropCopy on InboundDropReason {
  /// One line for a list of incidents.
  String get title => switch (this) {
    InboundDropReason.legacyFormat => 'Formato viejo',
    InboundDropReason.truncated => 'Mensaje truncado',
    InboundDropReason.notForUs => 'No era para esta identidad',
    InboundDropReason.forged => 'Remitente no verificado',
    InboundDropReason.malformedSenderKey =>
      'Clave del remitente mal codificada',
    InboundDropReason.expired => 'Fuera de la ventana de frescura',
    InboundDropReason.replay => 'Mensaje repetido',
    InboundDropReason.callSignal => 'Señal de llamada por relay',
    InboundDropReason.unreadable => 'Contenido ilegible',
    InboundDropReason.strangerMedia => 'Adjunto de un desconocido',
    InboundDropReason.strangerCall => 'Llamada de un desconocido',
    InboundDropReason.requestsFull => 'Bandeja de solicitudes llena',
    InboundDropReason.senderFull => 'Solicitud con demasiados mensajes',
    InboundDropReason.strangerTooLong => 'Solicitud demasiado grande',
    InboundDropReason.mediaQuota => 'Sin espacio para adjuntos',
  };

  /// What happened and what the user can do about it.
  String get detail => switch (this) {
    InboundDropReason.legacyFormat =>
      'Alguien te escribió con una versión anterior de Encrypchat. Ese '
          'formato no autenticaba al remitente, así que no se acepta: pídele '
          'que actualice.',
    InboundDropReason.truncated =>
      'El mensaje llegó incompleto desde el relay. Pídele que lo reenvíe.',
    InboundDropReason.notForUs =>
      'El relay entregó un mensaje que no está dirigido a esta identidad, o '
          'con la cabecera corrupta. No se puede leer ni saber quién lo mandó.',
    InboundDropReason.forged =>
      'Un mensaje iba dirigido a ti, pero el remitente no se pudo verificar: '
          'o alguien intentó hacerse pasar por un contacto, o el mensaje fue '
          'manipulado. Se descartó sin mostrarlo ni atribuirlo a nadie.',
    InboundDropReason.malformedSenderKey =>
      'Un mensaje iba dirigido a ti, pero la clave de quien lo firmó está mal '
          'codificada: es la misma clave de siempre escrita de otra forma, lo '
          'que le daría un token distinto y, con él, una vuelta a un bloqueo. '
          'Se descartó sin atribuirlo a nadie.',
    InboundDropReason.expired =>
      'El mensaje es auténtico pero quedó fuera de la ventana de frescura '
          '(más de 7 días en el buzón, o el reloj de algún dispositivo está '
          'desfasado).',
    InboundDropReason.replay =>
      'Llegó una copia repetida de un mensaje que ya tenías. Alguien reenvió '
          'un mensaje capturado, o el relay lo entregó dos veces.',
    InboundDropReason.callSignal =>
      'Una llamada intentó entrar por el relay. Las llamadas van solo P2P, '
          'así que no suena.',
    InboundDropReason.unreadable =>
      'Un mensaje se descifró bien pero su contenido no se pudo interpretar.',
    InboundDropReason.strangerMedia =>
      'Alguien que no tienes en contactos intentó mandarte un adjunto. Las '
          'solicitudes son solo de texto: acéptalo como contacto y podrá '
          'mandarte fotos y archivos.',
    InboundDropReason.strangerCall =>
      'Alguien que no tienes en contactos intentó llamarte. No suena: agrégalo '
          'como contacto si quieres recibir sus llamadas.',
    InboundDropReason.requestsFull =>
      'Hay demasiadas solicitudes esperando, así que llegó una que no entró. '
          'Resuelve las que tienes en Solicitudes para volver a recibir.',
    InboundDropReason.senderFull =>
      'Alguien que no tienes en contactos siguió escribiendo después de agotar '
          'los mensajes que se le permiten. Está en Solicitudes: acéptalo, '
          'descártalo o bloquéalo.',
    InboundDropReason.strangerTooLong =>
      'Alguien que no tienes en contactos mandó algo más grande de lo que '
          'puede ser una solicitud, así que se descartó. Si te quiere mandar '
          'un archivo, agrégalo como contacto primero.',
    InboundDropReason.mediaQuota =>
      'Un adjunto no se guardó porque se llenó el cupo de adjuntos. Borra una '
          'conversación con fotos para liberar espacio y pídele que lo reenvíe.',
  };

  /// The cases that describe an attempt against the user rather than an
  /// incident; the UI gives them a different weight. A stranger writing is not
  /// an attack — it is the reason the requests inbox exists.
  bool get isHostile =>
      this == InboundDropReason.forged ||
      this == InboundDropReason.malformedSenderKey;

  /// Reasons the user resolves in Solicitudes rather than by reading a notice.
  bool get pointsAtRequests =>
      this == InboundDropReason.requestsFull ||
      this == InboundDropReason.senderFull ||
      this == InboundDropReason.strangerMedia ||
      this == InboundDropReason.strangerCall;
}

/// Whether the relay's second delivery of a blob still has work to do.
///
/// The relay stopped deleting a blob on delivery: it leases it for 60 s and
/// hands it over once more if the client comes back, which is what covers a
/// client killed between the `200` and its own write. That only works if the
/// two dispositions are told apart.
///
/// [settled] — filed, or refused by a verdict a second copy cannot change (a
/// stranger's attachment, an unparseable payload). The `msg_id` is remembered
/// and the redelivery is discarded as the duplicate it is.
///
/// [retry] — refused for something this device can undo: a full request inbox,
/// a full media store. The id is **not** remembered, so the redelivery gets a
/// real second chance a minute later.
///
/// A payload that throws on the way in falls under neither: nothing is
/// remembered, which is the whole of B-1.
enum _InboundDisposition { settled, retry }

/// What a conversation currently holds in memory: a **contiguous** run of
/// messages that always ends at the newest one, plus whether the database still
/// has something older than its first message.
///
/// Both properties are what the chat screen leans on. It renders the window
/// bottom-up, so extending it backwards adds items on the far side of the
/// viewport and cannot move the reading position, and a message arriving is
/// always an append. A window with a hole in it, or one that stopped short of
/// the newest message, would break both at once.
class _ConversationWindow {
  _ConversationWindow({required this.messages, required this.hasOlder});

  final List<ChatMessage> messages;
  bool hasOlder;
}

/// Encrypt → P2P send (prefer); on PeerOffline → blind relay; poll inbound + relay pull.
class MessagingService extends ChangeNotifier {
  MessagingService({
    required EncrypchatCore core,
    required IdentityService identity,
    required LocalDatabase database,
    RelayClient? relay,
    MediaStore? mediaStore,
    FlutterSecureStorage? storage,
    String? defaultRelayUrl,
  }) : _core = core,
       _identity = identity,
       _database = database,
       _relay = relay ?? RelayClient(),
       _media = mediaStore ?? MediaStore(core: core, database: database),
       _storage =
           storage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(encryptedSharedPreferences: true),
           ),
       _defaultRelayUrl = defaultRelayUrl;

  /// Where the relay address lives in the OS secure store. Public so deleting
  /// the identity can remove it with the rest — see `IdentityWipe`.
  static const relayUrlStorageKey = 'relay_base_url_v1';

  /// Must stay under relay `MAX_BLOB_BYTES` (256 KiB). Applies to the **sealed**
  /// blob, which is the payload plus [EncrypchatCore.sealedOverheadBytes].
  static const relayMaxBlobBytes = 256 * 1024;

  /// How much of a conversation is read at a time, opening a chat and on every
  /// step backwards through its history.
  ///
  /// Fifty is about three screenfuls on a phone and one on a desktop window, so
  /// the first page always overflows the viewport (a page that fits leaves
  /// nothing to scroll and no way to ask for the next one) and a scroll back
  /// buys enough that the next fetch is not immediate. The cost of a page is
  /// what sets it: every message in it is an AEAD open on the UI isolate, and
  /// the old behaviour — two hundred at once, every time a chat opened — is the
  /// freeze this replaces.
  static const messagesPageSize = 50;

  /// How far a window may grow before its oldest page is dropped again.
  ///
  /// Ten pages: enough that scrolling back never hits it by hand, and the
  /// ceiling only bites when a conversation is *receiving* while it is open.
  /// At roughly 600 B of plaintext and metadata per text message this is under
  /// a megabyte per conversation, times [maxCachedPeers]. Media never counts —
  /// bytes are read from disk on demand and belong to the widget showing them.
  static const maxWindowMessages = 500;

  static const maxCachedPeers = 3;

  /// The core's freshness window for sealed blobs: 7 days into the past (the
  /// relay's max TTL), 300 s into the future. Outside it `sealedOpen` fails with
  /// `Expired`, and that is exactly what bounds how long a seen `msg_id` has to
  /// be remembered — a blob older than this cannot be replayed anyway.
  static const sealedFreshnessPast = Duration(days: 7);
  static const sealedFreshnessSkew = Duration(seconds: 300);

  /// Where the seen-id table stops being a normal size. Crossing it is logged
  /// and nothing is evicted: everything above it is still inside the freshness
  /// window, and forgetting an id there is exactly what an attacker wants — see
  /// [LocalDatabase.pruneSeenSealedIds].
  static const seenSealedWatermark = 20000;

  /// Last resort so the table cannot grow without bound. At ~50 B per row this
  /// is single-digit megabytes, it takes ten times the watermark's work to
  /// reach, and past it bounded disk wins over a perfect replay window.
  static const seenSealedHardCap = 200000;

  /// What an identity that is **not** a contact is allowed to leave here (F-6).
  ///
  /// A token is meant to be shareable — publish it, hand it over by QR — so a
  /// stranger who has yours can reach you. But only on a measured leash: text
  /// only, a handful of messages, and a bounded number of them pending at once.
  /// Worst case on disk is `20 × 5 × 4 KiB ≈ 400 KiB`, against the 12 MiB per
  /// frame with no ceiling at all that this replaces.
  static const maxPendingRequests = 20;
  static const maxRequestMessagesPerPeer = 5;
  static const maxRequestTextBytes = 4096;

  /// The largest **ciphertext** an identity that is not a contact can have
  /// opened on this isolate, checked before `decrypt` runs (B-5).
  ///
  /// It is [maxRequestTextBytes] plus what `encrypt` adds, so it refuses
  /// exactly nothing that the policy below would have accepted: a stranger's
  /// attachment and a stranger's call are dropped anyway, and their text is
  /// capped at the same 4 KiB one step later. What it does stop is the
  /// asymmetry — a frame may carry up to 16 MiB (`MAX_FRAME_LEN`), and a peer
  /// with a throwaway identity could make the interface open one after another
  /// before the policy got a chance to throw them away.
  static const maxStrangerCiphertextBytes =
      maxRequestTextBytes + EncrypchatCore.encryptOverheadBytes;

  final EncrypchatCore _core;
  final IdentityService _identity;
  final LocalDatabase _database;
  final RelayClient _relay;
  final MediaStore _media;
  final FlutterSecureStorage _storage;
  final String? _defaultRelayUrl;

  Timer? _poll;
  Timer? _relayPoll;

  /// Where the blocking node calls run. `null` when the isolate could not be
  /// spawned, in which case they run here and the interface pays for it.
  CoreWorker? _worker;
  bool _draining = false;
  bool _pulling = false;
  String? listenAddr;
  String? lastError;

  /// Non-loopback listen addrs for this node, same port as [listenAddr].
  List<String> lanListenAddrs = const [];

  /// Dial hints from imported cards, keyed by peer token. Not written to the
  /// contacts table: they go stale when the other device changes network.
  final Map<String, List<String>> _dialHints = {};

  /// Tokens we have a live P2P session with, as far as this process can tell.
  /// Set after a delivered send or an inbound P2P frame; cleared on PeerOffline.
  final Set<String> _livePeers = {};

  final Map<String, Future<bool>> _dialInFlight = {};
  final Map<String, _ConversationWindow> _cache = {};

  /// Cached peers, least recently used first.
  final List<String> _cacheLru = [];
  final Map<String, Contact> _contacts = {};

  /// Mirror of the `requests` table, so the chat list can show a badge without
  /// a query on every rebuild.
  List<MessageRequest> _requests = const [];

  /// Requests displaced from the inbox this session to make room for a newer
  /// stranger. Surfaced so a bandeja that keeps rolling over is visible.
  int _displacedRequests = 0;

  /// Sealed ids being processed right now.
  ///
  /// Since the id is only written once the payload has been dealt with, the
  /// database can no longer be the mutual exclusion between two deliveries of
  /// the same blob — there is an `await` in between. This set is: it lives for
  /// as long as the process does, which is exactly as long as the gap it
  /// covers. Across processes the message table is the authority instead, and
  /// `insertMessageIfNew` is idempotent.
  final Set<String> _sealedIdsInFlight = {};

  /// Mirror of the `blocked` table, kept in memory so the inbound hot path can
  /// decide before decrypting. Loaded by [loadBlocked] on every session start.
  final Set<String> _blocked = {};

  /// Inbound payloads discarded since this session started, by reason. Covers
  /// both routes: a relay blob that failed to open and a stranger's attachment
  /// are both things that arrived and were not filed.
  final Map<InboundDropReason, int> _drops = {};
  InboundDropReason? _lastDrop;

  /// Whether the blocking node calls are running off this isolate (F-11). False
  /// means the spawn failed and sends are freezing frames again.
  @visibleForTesting
  bool get sendsOffIsolate => _worker != null;

  /// Wall clock used for the sealed freshness window and for pruning seen ids.
  /// Injectable because a blob's `sent_at` is bound inside its ciphertext and
  /// cannot be backdated from the outside: moving the clock is the only way to
  /// reach the expiry path.
  @visibleForTesting
  DateTime Function() clock = () => DateTime.now().toUtc();

  /// Demux for call signaling (not persisted as chat).
  void Function(String fromToken, CallSignal signal)? onCallSignal;

  /// Installed by `CallService`. Runs when the user blocks a token, **before**
  /// the block is applied, so a live call with that identity is torn down while
  /// this class is still allowed to send it a `hangup`.
  ///
  /// The media path is direct UDP and does not go through the node, so blocking
  /// alone would leave mic and camera flowing; and once the block is in place
  /// the peer's own `hangup` is dropped too, leaving the call up forever.
  Future<void> Function(String token)? onBlockPeer;

  bool get nodeRunning => _core.isNodeRunning;
  bool get relayConfigured => _relay.isConfigured;
  String? get relayBaseUrl => _relay.baseUrl;

  /// True when the compiled Encrypchat relay is the one in use.
  bool get usesDefaultRelay =>
      relayConfigured && _relay.baseUrl == _defaultRelayUrl;

  /// True when this process has an open P2P session with [token].
  ///
  /// That is not "the other person opened the app". It is only "we can talk
  /// on a socket right now". Showing anything else would be a presence oracle.
  bool isLivePeer(String token) =>
      _livePeers.contains(LocalDatabase.normalizeToken(token));

  /// One line for a chat header or a list row: route, not availability.
  String routeLabel(String token, {required bool blocked}) {
    if (blocked) return 'Bloqueado';
    if (!nodeRunning) return 'Tu nodo está detenido';
    if (isLivePeer(token)) return 'Sesión P2P';
    if (relayConfigured) return 'Sin sesión P2P · relay listo';
    return 'Sin ruta · conecta o usa un relay';
  }

  void rememberDialHints(String token, List<String> hints) {
    final key = LocalDatabase.normalizeToken(token);
    final clean = [
      for (final h in hints)
        if (isDialHint(h)) h,
    ];
    if (clean.isEmpty) {
      _dialHints.remove(key);
    } else {
      _dialHints[key] = clean;
    }
  }

  void forgetPeerRoute(String token) {
    final key = LocalDatabase.normalizeToken(token);
    _dialHints.remove(key);
    _livePeers.remove(key);
  }

  void _markLive(String token) {
    if (_livePeers.add(LocalDatabase.normalizeToken(token))) {
      notifyListeners();
    }
  }

  void _markOffline(String token) {
    if (_livePeers.remove(LocalDatabase.normalizeToken(token))) {
      notifyListeners();
    }
  }

  /// Tries the listen addrs that arrived with the card. Returns true if any
  /// dial completed; that is not yet proof the session is with [token].
  ///
  /// A send that lands while import is still dialing waits for that attempt
  /// instead of giving up and marking the message failed.
  Future<bool> tryDial(String token) async {
    final key = LocalDatabase.normalizeToken(token);
    final hints = _dialHints[key];
    if (hints == null || hints.isEmpty || !_core.isNodeRunning) return false;
    final existing = _dialInFlight[key];
    if (existing != null) return existing;
    final future = _dialHintsInOrder(hints);
    _dialInFlight[key] = future;
    try {
      return await future;
    } finally {
      _dialInFlight.remove(key);
    }
  }

  Future<bool> _dialHintsInOrder(List<String> hints) async {
    for (final addr in hints.take(3)) {
      try {
        await connectMultiaddr(addr);
        return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  Future<void> refreshLanListenAddrs() async {
    final port = listenPortFromMultiaddr(listenAddr);
    if (port == null) {
      if (lanListenAddrs.isNotEmpty) {
        lanListenAddrs = const [];
        notifyListeners();
      }
      return;
    }
    final next = await lanListenMultiaddrs(port);
    if (!_sameAddrs(lanListenAddrs, next)) {
      lanListenAddrs = next;
      notifyListeners();
    }
  }

  static bool _sameAddrs(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Relay configured over plain HTTP: blobs stay E2EE but token/pubkey/proof
  /// travel in the clear. Surfaced in the UI, not blocked (LAN demos need it).
  bool get relayIsInsecure => _relay.isInsecure;

  /// Why the mailbox is not being drained, when the reason is not going to pass
  /// on its own: a protocol mismatch, a relay that speaks the pre-F-8 challenge,
  /// or a proof the relay keeps refusing.
  ///
  /// Being offline is *not* one of those and stays out of here — a banner that
  /// blinks every 8 s while the train goes through a tunnel teaches people to
  /// ignore banners. This exists because the F-8 drift produced a pull failing
  /// forever with nothing on screen, which is the failure mode worth naming.
  String? get relayPullFault => _relayPullFault;
  String? _relayPullFault;

  /// How long to leave the mailbox alone after a 429. The relay's default budget
  /// is 30 pulls per minute **per IP**, and this loop spends 7.5 of them, so a
  /// few devices on one network share the ceiling: this is long enough to fall
  /// well under it and short enough that a message does not sit there.
  static const relayBackoff = Duration(seconds: 45);

  DateTime? _relayBackoffUntil;

  void _noteRelayFault(String message) {
    if (_relayPullFault == message) return;
    _relayPullFault = message;
    notifyListeners();
  }

  void _clearRelayFault() {
    if (_relayPullFault == null) return;
    _relayPullFault = null;
    notifyListeners();
  }

  void setContacts(List<Contact> contacts) {
    _contacts
      ..clear()
      ..addEntries(
        contacts.map((c) => MapEntry(LocalDatabase.normalizeToken(c.token), c)),
      );
  }

  Contact? contactForToken(String token) =>
      _contacts[LocalDatabase.normalizeToken(token)];

  /// Whether this identity is agended. The gate for everything a stranger is
  /// not allowed to do: attachments, ringing, unbounded storage.
  bool isContact(String token) =>
      _contacts.containsKey(LocalDatabase.normalizeToken(token));

  /// Pending message requests, newest activity first. Small by construction
  /// ([maxPendingRequests]), so the list is held in memory for the UI.
  List<MessageRequest> get requests => List.unmodifiable(_requests);

  Future<void> loadRequests() async {
    _requests = await _database.listRequests();
    notifyListeners();
  }

  /// How many pending requests were pushed out by newer ones since this session
  /// started. Zero is the normal case; anything else means the inbox is being
  /// churned, which is what a flood of throwaway identities looks like.
  int get displacedRequests => _displacedRequests;

  /// Tokens blocked on this device, newest first.
  List<String> get blockedTokens => List.unmodifiable(_blocked);

  /// Inbound payloads dropped in this session, by reason. Which one leads is up
  /// to the UI: the map is the raw tally.
  Map<InboundDropReason, int> get inboundDrops => Map.unmodifiable(_drops);

  InboundDropReason? get lastDrop => _lastDrop;

  int get dropCount => _drops.values.fold(0, (sum, count) => sum + count);

  /// At least one blob was addressed to this identity and failed the sender
  /// binding: the one drop reason that is an attempt, not an incident.
  bool get sawForgedSender => (_drops[InboundDropReason.forged] ?? 0) > 0;

  /// Dismisses the tally once the user has read it.
  void clearDrops() {
    if (_drops.isEmpty) return;
    _drops.clear();
    _lastDrop = null;
    notifyListeners();
  }

  void _noteDrop(InboundDropReason reason) {
    _drops.update(reason, (count) => count + 1, ifAbsent: () => 1);
    _lastDrop = reason;
    // The reason name is a classification, never content or an identity.
    debugPrint('inbound dropped: ${reason.name}');
    notifyListeners();
  }

  bool isBlocked(String token) =>
      _blocked.contains(LocalDatabase.normalizeToken(token));

  Future<void> loadBlocked() async {
    final tokens = await _database.listBlockedTokens();
    _blocked
      ..clear()
      ..addAll(tokens.map(LocalDatabase.normalizeToken));
    _syncBlockedToCore();
    notifyListeners();
  }

  /// Mirrors the list into the core, which refuses a blocked token at the
  /// handshake and on send (defence in depth).
  ///
  /// Best effort **on purpose**: the enforcing layer is this class — see the
  /// cut in [handleInboundFrame] — and a core that refuses the update must not
  /// stop the user from blocking someone, so a failure is logged and swallowed.
  void _syncBlockedToCore() {
    if (!_core.isNodeRunning) return;
    // One malformed entry makes the core reject the whole list and keep the
    // previous (stale) one, so a junk row cannot be allowed to disable the
    // mirror for every other token. Dart-side blocking still covers it.
    final tokens = _blocked.where(isValidToken).toList(growable: false);
    if (tokens.length != _blocked.length) {
      debugPrint(
        'core blocklist: ${_blocked.length - tokens.length} token(s) skipped',
      );
    }
    try {
      _core.nodeSetBlockedTokens(tokens);
    } catch (e) {
      debugPrint('core blocklist sync failed: ${e.runtimeType}');
    }
  }

  /// Blocking is local and unilateral: the peer is never told. It drops
  /// everything that identity sends — text, media and call signaling — and
  /// stops this device from sending to it.
  Future<void> block(String token) async {
    final normalized = LocalDatabase.normalizeToken(token);
    try {
      await onBlockPeer?.call(normalized);
    } catch (e) {
      // A teardown that fails must never stop the block: cutting this identity
      // off is the control the user asked for, and the call is the side effect.
      debugPrint('block: call teardown failed (${e.runtimeType})');
    }
    await _database.blockToken(normalized);
    _blocked.add(normalized);
    _syncBlockedToCore();
    notifyListeners();
  }

  Future<void> unblock(String token) async {
    final normalized = LocalDatabase.normalizeToken(token);
    await _database.unblockToken(normalized);
    _blocked.remove(normalized);
    _syncBlockedToCore();
    notifyListeners();
  }

  Future<void> loadRelayUrl() async {
    final stored = await _storage.read(key: relayUrlStorageKey);
    _relay.baseUrl = resolveRelayUrl(
      stored: stored,
      defaultUrl: _defaultRelayUrl,
    );
    notifyListeners();
  }

  Future<void> setRelayBaseUrl(String? url) async {
    final trimmed = url?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == encrypchatRelayOff) {
      await _storage.write(key: relayUrlStorageKey, value: encrypchatRelayOff);
      _relay.baseUrl = null;
    } else {
      await _storage.write(key: relayUrlStorageKey, value: trimmed);
      _relay.baseUrl = trimmed;
    }
    // Pointing at a different relay is the usual answer to the fault, so the old
    // verdict must not outlive the address it was about.
    _relayPullFault = null;
    notifyListeners();
  }

  /// Forget a custom URL or an explicit off and go back to the compiled default.
  Future<void> useDefaultRelay() async {
    await _storage.delete(key: relayUrlStorageKey);
    _relay.baseUrl = _defaultRelayUrl;
    _relayPullFault = null;
    notifyListeners();
  }

  Future<void> startNode({int listenPort = 0}) async {
    await loadRelayUrl();
    if (_core.isNodeRunning) return;
    _core.nodeStart(secret: _identity.requireSecret(), listenPort: listenPort);
    // The core-side list is empty after every start, so this is the one sync
    // that cannot be skipped: without it a restart silently drops the mirror.
    _syncBlockedToCore();
    listenAddr = _core.nodeListenAddr();
    await refreshLanListenAddrs();
    _worker = await CoreWorker.spawn();
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 400), (_) {
      unawaited(_drainInbound());
    });
    _relayPoll?.cancel();
    _relayPoll = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(pullFromRelay());
    });
    unawaited(pullFromRelay());
    notifyListeners();
  }

  Future<void> stopNode() async {
    await _teardownNode();
    notifyListeners();
  }

  /// Everything [stopNode] does except telling the UI, so [dispose] can reuse
  /// it: notifying a disposed `ChangeNotifier` throws, and the teardown is
  /// asynchronous now that a stop is queued behind the worker's pending sends.
  Future<void> _teardownNode() async {
    _poll?.cancel();
    _poll = null;
    _relayPoll?.cancel();
    _relayPoll = null;
    listenAddr = null;
    lanListenAddrs = const [];
    _livePeers.clear();
    _dialInFlight.clear();
    final worker = _worker;
    _worker = null;
    if (worker != null) {
      // Detach first: from here on nothing in this isolate touches the handle,
      // and the worker runs the stop behind whatever it still had queued, so a
      // send in flight can never find the node freed underneath it.
      await worker.stopNodeAndClose(_core.detachNode());
    } else {
      _core.nodeStop();
    }
  }

  Future<void> connectHostPort(String host, int port) =>
      connectMultiaddr('/ip4/${host.trim()}/tcp/$port');

  /// Dialing blocks up to 10 s in the core (TCP plus the EH02 handshake), so it
  /// runs on the worker isolate too: the user taps "Conectar" and the dialog
  /// stays alive while it happens.
  Future<void> connectMultiaddr(String multiaddr) async {
    lastError = null;
    try {
      final worker = _worker;
      final address = _core.nodeHandleAddress;
      if (worker != null && address != null) {
        await worker.connect(
          handleAddress: address,
          multiaddr: multiaddr.trim(),
        );
      } else {
        _core.nodeConnect(multiaddr.trim());
      }
      notifyListeners();
    } catch (e) {
      lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Dial the card's listen addrs once, then send. A first send after import
  /// otherwise fails with PeerOffline even when both devices are on the LAN:
  /// adding a contact does not open a socket.
  Future<void> _sendWithDialRetry({
    required String peerToken,
    required Uint8List frame,
  }) async {
    try {
      await _sendFrame(peerToken: peerToken, frame: frame);
    } on CoreException catch (e) {
      if (e.code != CoreException.peerOffline) rethrow;
      if (!await tryDial(peerToken)) rethrow;
      await _sendFrame(peerToken: peerToken, frame: frame);
    }
  }

  /// One send, off the UI isolate when there is a worker to run it (F-11).
  ///
  /// The fallback is the old behaviour on purpose: if the isolate could not be
  /// spawned, sending on this isolate still works and freezes a frame, which is
  /// better than a client that cannot send at all. It is logged at spawn time.
  Future<void> _sendFrame({
    required String peerToken,
    required Uint8List frame,
  }) async {
    final worker = _worker;
    final address = _core.nodeHandleAddress;
    if (worker == null || address == null) {
      _core.nodeSend(peerToken: peerToken, frame: frame);
      return;
    }
    await worker.send(
      handleAddress: address,
      peerToken: peerToken,
      frame: frame,
    );
  }

  /// The conversation as it is held in memory: oldest-first, ending at the
  /// newest message. A cold conversation loads its newest page here — not its
  /// whole history — and [loadOlderMessages] extends it backwards from there.
  Future<List<ChatMessage>> messagesFor(String peerToken) async {
    final cached = _cache[peerToken];
    if (cached != null) {
      _touchCache(peerToken);
      return List.unmodifiable(cached.messages);
    }
    final window = await _readPage(peerToken, before: null);
    _cache[peerToken] = window;
    _touchCache(peerToken);
    return List.unmodifiable(window.messages);
  }

  /// Extends a cached conversation one page further back and reports how many
  /// messages that added. Zero means there was nothing older to read.
  ///
  /// Deliberately does not notify: this is one screen asking for its own
  /// scrollback, and waking every other listener to rebuild is not part of it.
  /// The caller reads the window it just extended.
  Future<int> loadOlderMessages(String peerToken) async {
    final window = _cache[peerToken];
    if (window == null || !window.hasOlder || window.messages.isEmpty) return 0;
    final older = await _readPage(peerToken, before: window.messages.first);
    // The window can be replaced while this awaits — the conversation deleted,
    // the peer dropped by the LRU — and prepending to the old object would
    // either resurrect it or splice a page into a thread that no longer starts
    // where it did.
    if (!identical(_cache[peerToken], window)) return 0;
    window.messages.insertAll(0, older.messages);
    window.hasOlder = older.hasOlder;
    return older.messages.length;
  }

  /// Whether this conversation has messages older than the ones in memory.
  bool hasOlderMessages(String peerToken) =>
      _cache[peerToken]?.hasOlder ?? false;

  /// Collapses a conversation back to its newest page.
  ///
  /// Called when its screen closes. While a chat is open the window is as long
  /// as the user scrolled back, and that is decrypted text this process has no
  /// reason to keep holding once nobody is reading it. Nothing is lost: the
  /// messages are on disk and scrolling back reads them again.
  void releaseWindow(String peerToken) {
    final window = _cache[peerToken];
    if (window == null) return;
    if (window.messages.length <= messagesPageSize) return;
    window.messages.removeRange(0, window.messages.length - messagesPageSize);
    window.hasOlder = true;
  }

  /// Reads one page and opens it.
  ///
  /// One row more than the page is asked for and thrown away before anything is
  /// decrypted: that extra row is the whole answer to "is there anything older",
  /// and it is what keeps the screen from offering a scrollback that ends in an
  /// empty fetch — or hiding one that does not.
  Future<_ConversationWindow> _readPage(
    String peerToken, {
    required ChatMessage? before,
  }) async {
    final rows = await _database.listMessages(
      peerToken,
      limit: messagesPageSize + 1,
      before: before,
    );
    final hasOlder = rows.length > messagesPageSize;
    final page = hasOlder ? rows.sublist(rows.length - messagesPageSize) : rows;
    return _ConversationWindow(
      messages: [for (final m in page) _openForDisplay(m)],
      hasOlder: hasOlder,
    );
  }

  /// A stored message with its body opened for the UI. A body that will not
  /// open becomes a visible error rather than a blank bubble: the row is real,
  /// and pretending it is not would hide a `db_key` that no longer matches.
  ChatMessage _openForDisplay(ChatMessage m) {
    try {
      if (!m.isMedia) {
        final text = _core.openUtf8(
          dbKey: _database.dbKey,
          sealed: m.bodySealed,
        );
        return m.copyWith(plaintext: text);
      }
      String? caption;
      try {
        caption = _openCaption(m);
      } catch (e) {
        // Distinct from "no caption": the sealed body exists but did not open.
        debugPrint('open caption failed: ${e.runtimeType}');
        return m.copyWith(
          plaintext: '«adjunto: nombre ilegible»',
          status: MessageStatus.error,
        );
      }
      return m.copyWith(plaintext: caption ?? m.mime);
    } catch (e) {
      debugPrint('open message failed: ${e.runtimeType}');
      return m.copyWith(
        plaintext: '«no se pudo abrir»',
        status: MessageStatus.error,
      );
    }
  }

  /// Sealed media read on demand for the UI. Bytes are never cached here.
  Future<Uint8List> mediaBytesFor(ChatMessage message) {
    final rel = message.mediaRelPath;
    if (!message.isMedia || rel == null) {
      throw StateError('El mensaje no tiene adjunto');
    }
    return _media.readSealed(rel);
  }

  Future<void> refreshPeer(String peerToken) async {
    _cache.remove(peerToken);
    _cacheLru.remove(peerToken);
    await messagesFor(peerToken);
    notifyListeners();
  }

  /// Caption is optional: `null` means "no caption", a throw means the sealed
  /// body could not be opened (rotated `db_key`, corrupt row) and must surface.
  String? _openCaption(ChatMessage message) {
    final caption = _core.openUtf8(
      dbKey: _database.dbKey,
      sealed: message.bodySealed,
    );
    return caption.isEmpty ? null : caption;
  }

  void _touchCache(String peerToken) {
    _cacheLru
      ..remove(peerToken)
      ..add(peerToken);
    while (_cacheLru.length > maxCachedPeers) {
      _cache.remove(_cacheLru.removeAt(0));
    }
  }

  Future<ChatMessage> sendText({
    required Contact peer,
    required String text,
  }) async {
    _assertNotBlocked(peer.token);
    _assertUsablePeerKey(peer);
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw CoreException(CoreException.emptyPlaintext);
    }
    if (!_core.isNodeRunning) {
      throw StateError('Nodo P2P no iniciado');
    }

    final id = _newId();
    final sealed = _core.localSeal(
      dbKey: _database.dbKey,
      plaintext: Uint8List.fromList(utf8.encode(trimmed)),
    );
    var message = ChatMessage(
      id: id,
      peerToken: peer.token,
      direction: MessageDirection.outbound,
      bodySealed: sealed,
      status: MessageStatus.sending,
      createdAt: DateTime.now().toUtc(),
      plaintext: trimmed,
    );
    await _database.upsertMessage(message);
    _pushCache(message);
    notifyListeners();

    final ciphertext = _core.encryptUtf8(
      recipientPublicKey: peer.publicKey,
      plaintext: trimmed,
    );
    final frame = WireFrame.create(
      senderToken: _identity.token!,
      ciphertext: ciphertext,
      msgId: _idToBytes(id),
    );
    final encoded = frame.encode();

    try {
      await _sendWithDialRetry(peerToken: peer.token, frame: encoded);
      _markLive(peer.token);
      message = message.copyWith(status: MessageStatus.delivered);
      await _database.updateMessageStatus(id, MessageStatus.delivered);
      _pushCache(message);
      notifyListeners();
      return message;
    } on CoreException catch (e) {
      if (e.code == CoreException.peerOffline) {
        _markOffline(peer.token);
      }
      if (e.code == CoreException.peerOffline && _relay.isConfigured) {
        try {
          await _enqueueSealed(
            peer: peer,
            plaintext: Uint8List.fromList(utf8.encode(trimmed)),
          );
          message = message.copyWith(status: MessageStatus.viaRelay);
          await _database.updateMessageStatus(id, MessageStatus.viaRelay);
          _pushCache(message);
          notifyListeners();
          return message;
        } catch (re) {
          message = message.copyWith(
            status: MessageStatus.error,
            error: 'P2P offline y relay falló: $re',
          );
          await _database.updateMessageStatus(id, MessageStatus.error);
          _pushCache(message);
          notifyListeners();
          throw StateError(message.error!);
        }
      }
      message = message.copyWith(
        status: MessageStatus.error,
        error: switch (e.code) {
          CoreException.peerOffline =>
            'Sin ruta P2P. Misma Wi‑Fi: Chats → enlace, o configura un relay '
                '(☁). Agregar un contacto no abre un socket.',
          CoreException.peerBlocked => blockedMessage,
          _ => e.toString(),
        },
      );
      await _database.updateMessageStatus(id, MessageStatus.error);
      _pushCache(message);
      notifyListeners();
      if (e.code == CoreException.peerBlocked) {
        // The core caught what this class should have caught first: report it
        // as the block it is, not as a raw error code.
        throw StateError(blockedMessage);
      }
      rethrow;
    }
  }

  /// Tells [peer] that this device added them. The payload carries our public
  /// key so their Solicitudes can offer Accept even if the hello only went P2P.
  Future<ContactAnnounce> sendContactIntro(Contact peer) async {
    _assertNotBlocked(peer.token);
    _assertUsablePeerKey(peer);
    if (!_core.isNodeRunning) return ContactAnnounce.noRoute;

    final intro = ContactIntro(
      token: _identity.token!,
      publicKey: _identity.publicKey!,
    );
    final plain = intro.encode();
    final id = _newId();
    final sealed = _core.localSeal(
      dbKey: _database.dbKey,
      plaintext: Uint8List.fromList(utf8.encode(ContactIntro.preview)),
    );
    var message = ChatMessage(
      id: id,
      peerToken: peer.token,
      direction: MessageDirection.outbound,
      bodySealed: sealed,
      status: MessageStatus.sending,
      createdAt: DateTime.now().toUtc(),
      plaintext: ContactIntro.preview,
    );
    await _database.upsertMessage(message);
    _pushCache(message);
    notifyListeners();

    final ciphertext = _core.encrypt(
      recipientPublicKey: peer.publicKey,
      plaintext: plain,
    );
    final frame = WireFrame.create(
      senderToken: _identity.token!,
      ciphertext: ciphertext,
      msgId: _idToBytes(id),
    );

    try {
      await _sendWithDialRetry(peerToken: peer.token, frame: frame.encode());
      _markLive(peer.token);
      message = message.copyWith(status: MessageStatus.delivered);
      await _database.updateMessageStatus(id, MessageStatus.delivered);
      _pushCache(message);
      notifyListeners();
      return ContactAnnounce.delivered;
    } on CoreException catch (e) {
      if (e.code == CoreException.peerOffline) {
        _markOffline(peer.token);
      }
      if (e.code == CoreException.peerOffline && _relay.isConfigured) {
        try {
          await _enqueueSealed(peer: peer, plaintext: plain);
          message = message.copyWith(status: MessageStatus.viaRelay);
          await _database.updateMessageStatus(id, MessageStatus.viaRelay);
          _pushCache(message);
          notifyListeners();
          return ContactAnnounce.viaRelay;
        } catch (_) {
          message = message.copyWith(status: MessageStatus.error);
          await _database.updateMessageStatus(id, MessageStatus.error);
          _pushCache(message);
          notifyListeners();
          return ContactAnnounce.noRoute;
        }
      }
      message = message.copyWith(status: MessageStatus.error);
      await _database.updateMessageStatus(id, MessageStatus.error);
      _pushCache(message);
      notifyListeners();
      return ContactAnnounce.noRoute;
    } catch (_) {
      message = message.copyWith(status: MessageStatus.error);
      await _database.updateMessageStatus(id, MessageStatus.error);
      _pushCache(message);
      notifyListeners();
      return ContactAnnounce.noRoute;
    }
  }

  /// Send an image/file (E2EE). Prefers P2P; relay only if ciphertext ≤ 256 KiB.
  Future<ChatMessage> sendMedia({
    required Contact peer,
    required Uint8List bytes,
    required String mime,
    required String name,
  }) async {
    _assertNotBlocked(peer.token);
    _assertUsablePeerKey(peer);
    if (!_core.isNodeRunning) {
      throw StateError('Nodo P2P no iniciado');
    }
    if (bytes.isEmpty) {
      throw CoreException(CoreException.emptyPlaintext);
    }
    final envelope = MediaEnvelope(mime: mime, name: name, data: bytes);
    final plain = envelope.encode();

    final id = _newId();
    final rel = await _media.writeSealed(id: id, plaintextBytes: bytes);
    final captionSealed = _core.localSeal(
      dbKey: _database.dbKey,
      plaintext: Uint8List.fromList(utf8.encode(name)),
    );
    var message = ChatMessage(
      id: id,
      peerToken: peer.token,
      direction: MessageDirection.outbound,
      bodySealed: captionSealed,
      status: MessageStatus.sending,
      createdAt: DateTime.now().toUtc(),
      kind: MessageKind.media,
      mime: mime,
      mediaRelPath: rel,
      plaintext: name,
    );
    await _database.upsertMessage(message);
    _pushCache(message);
    notifyListeners();

    final ciphertext = _core.encrypt(
      recipientPublicKey: peer.publicKey,
      plaintext: plain,
    );
    final frame = WireFrame.create(
      senderToken: _identity.token!,
      ciphertext: ciphertext,
      msgId: _idToBytes(id),
    );

    try {
      await _sendWithDialRetry(peerToken: peer.token, frame: frame.encode());
      _markLive(peer.token);
      message = message.copyWith(status: MessageStatus.delivered);
      await _database.updateMessageStatus(id, MessageStatus.delivered);
      _pushCache(message);
      notifyListeners();
      return message;
    } on CoreException catch (e) {
      if (e.code == CoreException.peerOffline) {
        _markOffline(peer.token);
      }
      if (e.code == CoreException.peerOffline && _relay.isConfigured) {
        // A sealed blob is exactly its payload plus a fixed overhead, so the
        // relay limit can be checked before spending the seal.
        final sealedSize = EncrypchatCore.sealedOverheadBytes + plain.length;
        if (sealedSize > relayMaxBlobBytes) {
          message = message.copyWith(
            status: MessageStatus.error,
            error:
                'Adjunto ($sealedSize B sellado) supera el límite del relay '
                '($relayMaxBlobBytes B). Conecta P2P o comprime la imagen.',
          );
          await _database.updateMessageStatus(id, MessageStatus.error);
          _pushCache(message);
          notifyListeners();
          throw StateError(message.error!);
        }
        try {
          await _enqueueSealed(peer: peer, plaintext: plain);
          message = message.copyWith(status: MessageStatus.viaRelay);
          await _database.updateMessageStatus(id, MessageStatus.viaRelay);
          _pushCache(message);
          notifyListeners();
          return message;
        } catch (re) {
          message = message.copyWith(
            status: MessageStatus.error,
            error: 'Relay falló: $re',
          );
          await _database.updateMessageStatus(id, MessageStatus.error);
          _pushCache(message);
          notifyListeners();
          rethrow;
        }
      }
      message = message.copyWith(
        status: MessageStatus.error,
        error: switch (e.code) {
          CoreException.peerOffline =>
            'Peer offline — adjuntos grandes requieren P2P o relay ≤256KiB',
          CoreException.peerBlocked => blockedMessage,
          _ => e.toString(),
        },
      );
      await _database.updateMessageStatus(id, MessageStatus.error);
      _pushCache(message);
      notifyListeners();
      if (e.code == CoreException.peerBlocked) {
        throw StateError(blockedMessage);
      }
      rethrow;
    }
  }

  /// Seals a payload for the relay and enqueues it.
  ///
  /// Returning normally means the relay **took** the blob, and that is the most
  /// this can ever mean. A mailbox over quota is refused with the same reply as
  /// an acceptance, on purpose: the two used to be distinguishable, and that
  /// difference let anyone who knew a token fill the mailbox and then probe it
  /// to find out when its owner came online to empty it. Nothing here can undo
  /// that, and nothing should try — the honest sender and the attacker send the
  /// same request, so any signal to one is a signal to the other. What the
  /// client owes instead is copy that does not promise what it did not learn;
  /// see [MessageStatus.viaRelay].
  ///
  /// The plaintext is the same shape the P2P path carries — bare UTF-8 text, an
  /// `EM01` media envelope — and carries **no** sender field: the recipient
  /// reads the authenticated sender out of the ciphertext when it opens the
  /// blob. Sealing with `encrypchat_encrypt` instead would put the sender back
  /// in the payload, where anyone holding the recipient's public key can write
  /// whatever token they like.
  Future<void> _enqueueSealed({
    required Contact peer,
    required Uint8List plaintext,
  }) async {
    final sealed = _core.sealedSeal(
      senderSecret: _identity.requireSecret(),
      recipientPublicKey: peer.publicKey,
      plaintext: plaintext,
    );
    if (sealed.blob.length > relayMaxBlobBytes) {
      throw StateError(
        'El mensaje sellado (${sealed.blob.length} B) supera el límite del '
        'relay ($relayMaxBlobBytes B). Conecta P2P o envía algo más corto.',
      );
    }
    await _relay.enqueue(destToken: peer.token, blob: sealed.blob);
  }

  /// E2EE call signaling (not stored in chat DB).
  ///
  /// **P2P-only, both directions.** Sender authentication is no longer what
  /// blocks this — sealed sender covers the relay path now — but a stored ring
  /// is a separate product decision: an `invite` pulled hours later would ring
  /// for a call nobody is on, and an accepted one would hand over mic and
  /// camera to a peer that is not even connected. [_acceptPayload] drops
  /// inbound call signals that arrive by relay for the same reason.
  Future<void> sendCallSignal({
    required Contact peer,
    required CallSignal signal,
  }) async {
    _assertNotBlocked(peer.token);
    _assertUsablePeerKey(peer);
    if (!_core.isNodeRunning) {
      throw StateError('Nodo P2P no iniciado');
    }
    // Stamped here so every outbound signal carries one, from the same clock the
    // freshness checks use: the receiver refuses to ring for an `invite` that
    // took too long to arrive.
    final plain = signal.stamped(_nowUnix()).encode();
    final ciphertext = _core.encrypt(
      recipientPublicKey: peer.publicKey,
      plaintext: plain,
    );
    final frame = WireFrame.create(
      senderToken: _identity.token!,
      ciphertext: ciphertext,
      msgId: _idToBytes(_newId()),
    );
    try {
      await _sendWithDialRetry(peerToken: peer.token, frame: frame.encode());
      _markLive(peer.token);
    } on CoreException catch (e) {
      if (e.code == CoreException.peerBlocked) throw StateError(blockedMessage);
      if (e.code != CoreException.peerOffline) rethrow;
      _markOffline(peer.token);
      throw StateError(
        'Llamadas requieren una sesión P2P. Misma Wi‑Fi: Chats → enlace.',
      );
    }
  }

  Future<void> pullFromRelay() async {
    if (!_relay.isConfigured || _pulling) return;
    final now = clock();
    if (_relayBackoffUntil != null && now.isBefore(_relayBackoffUntil!)) return;
    _pulling = true;
    try {
      List<Uint8List> blobs;
      try {
        blobs = await _pullOnce();
      } on RelayAuthException {
        // A challenge lives 120 s and the relay trims the oldest under load, so
        // the id can go stale between the two calls. One fresh attempt now
        // instead of a silent 8 s gap; a second failure is a real mismatch
        // (wrong key for the token) and is reported, not looped on.
        debugPrint('relay pull: challenge rejected, asking for a new one');
        blobs = await _pullOnce();
      }
      _clearRelayFault();
      for (final blob in blobs) {
        try {
          await handleRelayBlob(blob);
        } catch (e) {
          // Blobs are already deleted relay-side: one bad blob must not drop the rest.
          debugPrint('relay blob dropped: ${e.runtimeType}');
        }
      }
      await _pruneSeenSealedIds();
      _relayBackoffUntil = null;
    } on RelayBusyException {
      // The pull budget is per client IP, so every device on this network shares
      // it: at one cycle every 8 s a handful of phones behind the same NAT reach
      // it with nobody misbehaving. Backing off is the fix, and it is deliberately
      // not shown — the mailbox keeps waiting and the next cycle drains it.
      _relayBackoffUntil = now.add(relayBackoff);
      debugPrint(
        'relay rate-limited this address, next pull in '
        '${relayBackoff.inSeconds}s',
      );
    } on RelayAuthException catch (e) {
      // Twice in a row is no longer a challenge that went stale mid-flight: this
      // key does not prove this token to this relay, and no amount of waiting
      // fixes it.
      _noteRelayFault(e.message);
    } on StateError catch (e) {
      // Where the protocol mismatches land (422, a challenge with no id).
      _noteRelayFault(e.message);
    } catch (e) {
      // Network noise. Never interpolate the exception: FormatException embeds a
      // fragment of the decrypted source, and debugPrint survives release builds.
      debugPrint('relay pull failed: ${e.runtimeType}');
    } finally {
      _pulling = false;
    }
  }

  /// One challenge → proof → pull round trip.
  ///
  /// The `challenge_id` is what ties the two requests together since F-8: the
  /// relay no longer knows which mailbox a challenge belongs to, so it can only
  /// find the ephemeral secret again by that id. The proof itself is unchanged —
  /// the destination is already inside its transcript.
  Future<List<Uint8List>> _pullOnce() async {
    final token = _identity.token!;
    final ch = await _relay.challenge();
    final proof = _core.popProof(
      secret: _identity.requireSecret(),
      ephPubkey: ch.ephPubkey,
      nonce: ch.nonce,
      destToken: token,
    );
    return _relay.pull(
      challengeId: ch.id,
      destToken: token,
      publicKey: _identity.publicKey!,
      proof: proof,
    );
  }

  /// Opens a sealed relay blob, checks it is not a replay, and files it.
  ///
  /// Order matters twice over. The sender is authenticated first, so the
  /// blocklist acts on an identity the sender cannot choose; and the `msg_id`
  /// is written **last**, after the payload has been dealt with.
  ///
  /// That second order is the one the relay's lease depends on. Recording the
  /// id first — a durable commit — and inserting the message after left a gap:
  /// a process killed in between, or an insert that failed for anything other
  /// than a `FormatException`, ended with the id remembered and the message
  /// gone, and the redelivery the lease exists for was then discarded as a
  /// replay. Doing it the other way round costs nothing, because
  /// `insertMessageIfNew` is idempotent: a redelivery after a *successful*
  /// write is refused by the message table itself, so `seen_sealed` only has to
  /// remember what was **discarded** — plus, cheaply, what was stored.
  @visibleForTesting
  Future<void> handleRelayBlob(Uint8List blob) async {
    final SealedInbound opened;
    try {
      opened = _core.sealedOpen(
        recipientSecret: _identity.requireSecret(),
        blob: blob,
        nowUnixSecs: _nowUnix(),
      );
    } on CoreException catch (e) {
      // Nothing is written on error, and there is no declared sender to fall
      // back to — that field is gone from the payload on purpose.
      _noteDrop(_reasonForOpenFailure(e.code));
      return;
    }
    if (isBlocked(opened.senderToken)) {
      // The token comes out of the ciphertext, so this is the first time the
      // blocklist decides on an identity the sender could not choose.
      debugPrint('relay blob dropped: blocked sender');
      return;
    }
    final msgId = _bytesToId(opened.msgId);
    if (await _database.seenSealedId(msgId) || !_sealedIdsInFlight.add(msgId)) {
      // `ECS1` makes a captured blob re-openable, not re-usable: it authenticates
      // the same sender and the same `msg_id`, and that id is what stops here.
      _noteDrop(InboundDropReason.replay);
      return;
    }
    try {
      final disposition = await _acceptPayload(
        senderToken: opened.senderToken,
        plain: opened.plaintext,
        msgId: msgId,
        viaRelay: true,
        // Authenticated, and the only route that hands it over: it is what
        // makes a request from a stranger answerable at all.
        senderPublicKey: opened.senderPublicKey,
      );
      if (disposition == _InboundDisposition.settled) {
        await _rememberSealedId(msgId, opened);
      }
    } on FormatException {
      // A deliberate discard, so the id *is* recorded: a payload that failed to
      // parse will fail the same way on the second delivery, and discarding
      // that copy as a duplicate is cheaper than decoding it to reach the same
      // verdict. What must never look like this is a write that broke.
      _noteDrop(InboundDropReason.unreadable);
      await _rememberSealedId(msgId, opened);
    } finally {
      _sealedIdsInFlight.remove(msgId);
    }
  }

  Future<void> _rememberSealedId(String msgId, SealedInbound opened) {
    return _database.recordSeenSealedId(
      msgId,
      sentAtUnix: opened.sentAtUnix,
      // Local clock: the sender's `sent_at` is authenticated but chosen by the
      // sender, and letting it decide retention is how an id inside the window
      // could be evicted on demand.
      receivedAtUnix: _nowUnix(),
    );
  }

  static InboundDropReason _reasonForOpenFailure(int code) => switch (code) {
    CoreException.invalidFrame => InboundDropReason.legacyFormat,
    CoreException.ciphertextTooShort => InboundDropReason.truncated,
    CoreException.decryptionFailed => InboundDropReason.notForUs,
    CoreException.invalidPublicKey => InboundDropReason.malformedSenderKey,
    CoreException.authFailed => InboundDropReason.forged,
    CoreException.expired => InboundDropReason.expired,
    _ => InboundDropReason.unreadable,
  };

  /// Drops seen ids the freshness window can no longer let back in. Best effort:
  /// a failed prune leaves a bigger table, never a hole in the replay check.
  ///
  /// The horizon is on `received_at`, and it is read from the same clock that is
  /// handed to `sealedOpen`. That is what makes a clock jump harmless rather than
  /// a hole: if the clock moves forward, every id this forgets belongs to a blob
  /// the core now refuses as `Expired` under that same clock. What it does not
  /// cover is a device clock moved forward and then back, which needs a
  /// persisted monotonic time feeding the freshness check too.
  Future<void> _pruneSeenSealedIds() async {
    final horizon =
        _nowUnix() -
        sealedFreshnessPast.inSeconds -
        sealedFreshnessSkew.inSeconds;
    try {
      final result = await _database.pruneSeenSealedIds(
        receivedBeforeUnix: horizon,
        hardCap: seenSealedHardCap,
      );
      if (result.held > seenSealedWatermark) {
        // A count, never an id: this says "somebody is flooding the mailbox",
        // which is the one thing worth knowing here.
        debugPrint('seen-id table above watermark: ${result.held} ids held');
      }
    } catch (e) {
      debugPrint('seen-id prune failed: ${e.runtimeType}');
    }
  }

  /// Seconds since the epoch, clamped to 1: the core reads `0` as "no freshness
  /// window", and a device whose clock never got set must not silently lose the
  /// expiry check. Rejecting everything as `Expired` is the honest failure.
  int _nowUnix() {
    final secs = clock().toUtc().millisecondsSinceEpoch ~/ 1000;
    return secs < 1 ? 1 : secs;
  }

  Future<void> _drainInbound() async {
    if (!_core.isNodeRunning || _draining) return;
    _draining = true;
    try {
      while (true) {
        Uint8List? raw;
        try {
          raw = _core.nodeTryRecv();
        } catch (e) {
          debugPrint('inbound poll failed: ${e.runtimeType}');
          return;
        }
        if (raw == null) break;
        try {
          await handleInboundFrame(raw);
        } catch (e) {
          // One malformed frame must not stop the queue from draining.
          debugPrint('inbound frame dropped: ${e.runtimeType}');
        }
      }
    } finally {
      _draining = false;
    }
  }

  @visibleForTesting
  Future<void> handleInboundFrame(Uint8List raw) async {
    final frame = WireFrame.decode(raw);
    if (isBlocked(frame.senderToken)) {
      // Single cut for every payload type: text, media (EM01) and call
      // signaling all arrive as one frame, and the sender is known before the
      // ciphertext is opened. Nothing is decrypted, stored or rung.
      debugPrint('inbound frame dropped: blocked sender');
      return;
    }
    if (!isContact(frame.senderToken) &&
        frame.ciphertext.length > maxStrangerCiphertextBytes) {
      // Before `decrypt`, and that is the whole point (B-5). Sending is off the
      // UI isolate since F-11, receiving is not: `decrypt` is a DH plus an AEAD
      // open over the whole ciphertext, right here, and until this check the
      // 4 KiB a stranger is allowed was only applied afterwards — so a peer
      // with a throwaway identity could hand the interface 16 MiB at a time and
      // have it open every one of them before throwing them away. A contact is
      // deliberately exempt: their attachments are large by design, and they
      // are an identity the user chose to keep.
      _noteDrop(InboundDropReason.strangerTooLong);
      return;
    }
    final plain = _core.decrypt(
      secret: _identity.requireSecret(),
      ciphertext: frame.ciphertext,
    );
    await _acceptPayload(
      senderToken: frame.senderToken,
      plain: plain,
      msgId: _bytesToId(frame.msgId),
      viaRelay: false,
    );
    _markLive(frame.senderToken);
  }

  /// Files an inbound payload from either route. Both carry the same bytes now
  /// that the relay no longer wraps them in a JSON envelope with a `from`: the
  /// sender is an argument here because each route authenticates it its own way
  /// — the session token for P2P, the sealed sender for the relay.
  ///
  /// This is also the **single** place the non-contact policy is applied. It has
  /// to be one place: the same rule spread over the two routes is how F-6
  /// happened, and the check only makes sense here, after both routes have
  /// authenticated the sender they hand over.
  Future<_InboundDisposition> _acceptPayload({
    required String senderToken,
    required Uint8List plain,
    required String msgId,
    required bool viaRelay,
    Uint8List? senderPublicKey,
  }) async {
    var payload = plain;
    var key = senderPublicKey;
    if (ContactIntro.looksLike(plain)) {
      final intro = ContactIntro.tryDecode(plain);
      if (intro == null || !intro.matchesSender(senderToken)) {
        _noteDrop(InboundDropReason.unreadable);
        return _InboundDisposition.settled;
      }
      // P2P frames do not carry a key. The intro does, bound to the token
      // the session already authenticated, so Accept can work without relay.
      key = intro.publicKey;
      payload = Uint8List.fromList(utf8.encode(ContactIntro.preview));
    }
    final isMedia = MediaEnvelope.looksLike(payload);
    final isCall = CallSignal.looksLike(payload);
    if (isCall && viaRelay) {
      // See [sendCallSignal]: signaling stays P2P-only, so a stored ring is
      // dropped instead of woken up hours later.
      _noteDrop(InboundDropReason.callSignal);
      return _InboundDisposition.settled;
    }
    if (!isContact(senderToken)) {
      final refusal = await _admitFromUnknown(
        senderToken: senderToken,
        senderPublicKey: key,
        isMedia: isMedia,
        isCall: isCall,
        textBytes: payload.length,
        viaRelay: viaRelay,
      );
      if (refusal != null) {
        _noteDrop(refusal);
        return _dispositionFor(refusal);
      }
    }
    if (isMedia) {
      final env = MediaEnvelope.decode(payload);
      return _persistInboundMedia(
        peerToken: senderToken,
        mime: env.mime,
        name: env.name,
        bytes: env.data,
        viaRelay: viaRelay,
        msgId: msgId,
      );
    }
    if (isCall) {
      onCallSignal?.call(senderToken, CallSignal.decode(payload));
      return _InboundDisposition.settled;
    }
    final text = utf8.decode(payload);
    final sealed = _core.localSeal(
      dbKey: _database.dbKey,
      plaintext: Uint8List.fromList(utf8.encode(text)),
    );
    final message = ChatMessage(
      id: msgId,
      peerToken: senderToken,
      direction: MessageDirection.inbound,
      bodySealed: sealed,
      status: viaRelay ? MessageStatus.viaRelay : MessageStatus.delivered,
      createdAt: DateTime.now().toUtc(),
      plaintext: text,
    );
    if (!await _database.insertMessageIfNew(message)) {
      // The id is already stored, so this is a repeat — of a relay blob whose
      // seen-id was pruned, or of a `msg_id` a connected peer reused. Either way
      // the stored row is left exactly as it was.
      _noteDrop(InboundDropReason.replay);
      return _InboundDisposition.settled;
    }
    _pushCache(message);
    notifyListeners();
    return _InboundDisposition.settled;
  }

  /// Whether a refusal is one this device can undo, and therefore one the
  /// relay's second delivery should be allowed to try again against.
  ///
  /// The three that are: an inbox full of strangers, one stranger out of
  /// messages, and a media store with no room. All three are cleared by the
  /// user — resolving a request, accepting a sender, deleting a conversation —
  /// and the lease is 60 s, which is time enough to do it. Everything else is a
  /// verdict on the payload itself and does not change by arriving twice.
  static _InboundDisposition _dispositionFor(InboundDropReason reason) =>
      switch (reason) {
        InboundDropReason.requestsFull ||
        InboundDropReason.senderFull ||
        InboundDropReason.mediaQuota => _InboundDisposition.retry,
        _ => _InboundDisposition.settled,
      };

  /// The policy for an identity that is not a contact: it may ask, in text, a
  /// few times, and that is all. Returns the reason it was refused, or `null`
  /// when the message may go on to be stored.
  ///
  /// Discarding outright was the other option and it was rejected: a token is
  /// made to be handed out, so the person who gets yours by QR or from a bio
  /// would have no way to reach you, and — worse — no way to find out, because
  /// the relay accepts the blob either way. Accepting into a bounded inbox keeps
  /// that flow and still bounds what a stranger costs: no attachment, no ring,
  /// no notification, a handful of short messages.
  Future<InboundDropReason?> _admitFromUnknown({
    required String senderToken,
    required Uint8List? senderPublicKey,
    required bool isMedia,
    required bool isCall,
    required int textBytes,
    required bool viaRelay,
  }) async {
    if (isCall) {
      // The harassment case: ringing is the loudest thing an identity can do
      // here, and a stranger does not get it. Nothing is stored either.
      return InboundDropReason.strangerCall;
    }
    if (isMedia) {
      // The disk-filling case. A file from someone unknown is refused before it
      // is written, which is the difference from F-6: sealing it first and
      // hiding it afterwards is what let 12 MiB loops go unnoticed.
      return InboundDropReason.strangerMedia;
    }
    if (textBytes > maxRequestTextBytes) {
      return InboundDropReason.strangerTooLong;
    }
    var admission = await _database.admitRequestMessage(
      senderToken,
      publicKey: senderPublicKey,
      viaRelay: viaRelay,
      maxPeers: maxPendingRequests,
      maxPerPeer: maxRequestMessagesPerPeer,
    );
    if (admission == RequestAdmission.inboxFull &&
        await _displaceOldestRequest()) {
      admission = await _database.admitRequestMessage(
        senderToken,
        publicKey: senderPublicKey,
        viaRelay: viaRelay,
        maxPeers: maxPendingRequests,
        maxPerPeer: maxRequestMessagesPerPeer,
      );
    }
    switch (admission) {
      case RequestAdmission.admitted:
        await loadRequests();
        return null;
      case RequestAdmission.inboxFull:
        // Only reachable when another delivery took the slot that was just
        // freed, so it is a moment rather than a state. The id is not
        // remembered either, and the relay hands the blob over again.
        return InboundDropReason.requestsFull;
      case RequestAdmission.senderFull:
        return InboundDropReason.senderFull;
    }
  }

  /// Frees a slot by dropping the request whose sender has been quiet the
  /// longest, and everything it left on the device. Reports whether it found
  /// one to drop.
  ///
  /// The twenty slots used to be first come, first served, with no expiry and
  /// no eviction: twenty throwaway identities — which the threat model itself
  /// says cost nothing — owned them permanently, and from then on no genuine
  /// stranger could reach the user at all. Nobody was told, on either end: the
  /// relay accepts the blob and the sender sees a delivery.
  ///
  /// So the inbox is a rolling window of the twenty most recent strangers
  /// instead. It is lossy on purpose and the screen says so. Both the loss and
  /// the alternative are real, but they are not the same size: displacing an
  /// unread request needs twenty new ones and fills the screen with them, while
  /// refusing kept the channel shut with nothing visible anywhere. Ageing
  /// requests out on a timer was the other candidate and it does not hold —
  /// whatever the window, refreshing it costs the attacker one identity every
  /// window/20, and the channel is shut again.
  ///
  /// The order is deliberate: the conversation goes first and the slot after,
  /// so a process killed in between leaves an empty request the user can
  /// discard, never messages under a token with no request and no contact —
  /// which is the invisible conversation of F-6.
  Future<bool> _displaceOldestRequest() async {
    final displaced = await _database.oldestRequestToken();
    if (displaced == null) return false;
    await deleteConversation(displaced);
    await _database.deleteRequest(displaced);
    _displacedRequests++;
    // A count, never the token: this says the inbox is rolling over, which is
    // the part worth knowing.
    debugPrint('requests inbox full: displaced $_displacedRequests so far');
    await loadRequests();
    return true;
  }

  /// Turns a request into a contact, which is what lets it send attachments and
  /// ring. The public key is the whole reason this can fail: it comes out of the
  /// ciphertext on the relay route, and an `EC04` frame only carries the token,
  /// so a request that only ever arrived by P2P cannot be answered yet.
  Future<Contact> acceptRequest(
    MessageRequest request, {
    String? displayName,
  }) async {
    final pub = request.publicKey;
    if (pub == null) {
      throw StateError(
        'Falta su clave pública: pídele su tarjeta de contacto (token + QR) '
        'para poder responderle.',
      );
    }
    // The key came out of `sealed_open`, which on a current core has already
    // refused a non-canonical encoding. Asked again anyway: this is where a key
    // becomes a stored identity, and on an older core nothing else checks.
    try {
      _core.assertUsablePublicKey(
        senderSecret: _identity.requireSecret(),
        publicKey: pub,
      );
    } on CoreException catch (e) {
      if (e.code == CoreException.invalidPublicKey) {
        throw StateError(
          'La clave que trae esa solicitud está mal codificada, así que no se '
          'puede guardar como identidad. Pídele su tarjeta (token + QR).',
        );
      }
      rethrow;
    }
    final contact = Contact(
      token: request.peerToken,
      publicKey: pub,
      displayName: displayName,
      createdAt: DateTime.now().toUtc(),
    );
    await _database.upsertContact(contact);
    await _database.deleteRequest(request.peerToken);
    _contacts[LocalDatabase.normalizeToken(contact.token)] = contact;
    await loadRequests();
    return contact;
  }

  /// Drops a request and everything it left on this device. With [alsoBlock] the
  /// block goes first, so nothing new lands while the history is being removed.
  Future<void> discardRequest(
    String peerToken, {
    bool alsoBlock = false,
  }) async {
    if (alsoBlock) await block(peerToken);
    await deleteConversation(peerToken);
    await _database.deleteRequest(peerToken);
    await loadRequests();
  }

  /// Removes a conversation's messages and their sealed media files. Media
  /// first: a row without its file is a broken attachment, a file without its
  /// row is a byte nobody can ever find or free.
  Future<void> deleteConversation(String peerToken) async {
    final token = LocalDatabase.normalizeToken(peerToken);
    final paths = await _database.listMediaRelPaths(peerToken: token);
    await _media.deleteSealed(paths);
    await _database.deleteMessagesFor(token);
    _cache.remove(token);
    _cacheLru.remove(token);
    notifyListeners();
  }

  Future<_InboundDisposition> _persistInboundMedia({
    required String peerToken,
    required String mime,
    required String name,
    required Uint8List bytes,
    required bool viaRelay,
    String? msgId,
  }) async {
    if (msgId != null && await _database.messageExists(msgId)) {
      // Checked before the file is written, not after: an attachment already
      // stored under this id must not be sealed to disk a second time, and the
      // stored copy is the one that stays. This is also what makes the seen-id
      // write safe to leave until last — a delivery that lands twice because
      // the first one was interrupted stops here, not in the file system.
      _noteDrop(InboundDropReason.replay);
      return _InboundDisposition.settled;
    }
    try {
      await _media.ensureRoomFor(bytes: bytes.length, peerToken: peerToken);
    } on MediaQuotaException catch (e) {
      // Refused before writing, and counted so the UI can say why attachments
      // stopped arriving. Silence here would be the same failure as F-6.
      debugPrint('inbound media refused: ${e.global ? 'store' : 'peer'} quota');
      _noteDrop(InboundDropReason.mediaQuota);
      return _dispositionFor(InboundDropReason.mediaQuota);
    }
    final id = msgId ?? _newId();
    final rel = await _media.writeSealed(id: id, plaintextBytes: bytes);
    final captionSealed = _core.localSeal(
      dbKey: _database.dbKey,
      plaintext: Uint8List.fromList(utf8.encode(name)),
    );
    final message = ChatMessage(
      id: id,
      peerToken: peerToken,
      direction: MessageDirection.inbound,
      bodySealed: captionSealed,
      status: viaRelay ? MessageStatus.viaRelay : MessageStatus.delivered,
      createdAt: DateTime.now().toUtc(),
      kind: MessageKind.media,
      mime: mime,
      mediaRelPath: rel,
      plaintext: name,
    );
    if (!await _database.insertMessageIfNew(message)) {
      // The check above already covers the ordinary repeat; this closes the gap
      // where a second copy landed by the other route while the file was being
      // written. The stored row keeps its file, so the new one is a byte nobody
      // could ever reach.
      await _media.deleteSealed([rel]);
      _noteDrop(InboundDropReason.replay);
      return _InboundDisposition.settled;
    }
    _pushCache(message);
    notifyListeners();
    return _InboundDisposition.settled;
  }

  /// Updates an already-cached conversation. A cold conversation is left alone:
  /// seeding it with a single message would make a partial list look complete.
  ///
  /// A new message is always an append, which is the one edit that keeps the
  /// window contiguous and still ending at the newest message. The trim at the
  /// far end is the same bargain the window already makes with the database —
  /// what it drops is a page it knows how to read back, and `hasOlder` says so —
  /// so this stays a single notion of what is loaded instead of a second one.
  void _pushCache(ChatMessage message) {
    final window = _cache[message.peerToken];
    if (window == null) return;
    final list = window.messages;
    final idx = list.indexWhere((m) => m.id == message.id);
    if (idx >= 0) {
      list[idx] = message;
    } else {
      list.add(message);
    }
    if (list.length > maxWindowMessages) {
      list.removeRange(0, list.length - maxWindowMessages);
      window.hasOlder = true;
    }
    _touchCache(message.peerToken);
  }

  /// Shown wherever a send is refused for a blocked peer, no matter which of
  /// the two layers cut it: this class up front, or the core with `PeerBlocked`.
  static const blockedMessage =
      'Contacto bloqueado: desbloquéalo para volver a escribirle o llamarlo.';

  /// A stored card whose public key the core refuses (`InvalidPublicKey`). The
  /// realistic way to get one is an import from before the core started
  /// rejecting non-canonical encodings, so the fix is a new card, not a retry.
  static const malformedCardMessage =
      'La clave pública guardada de este contacto está mal codificada, así que '
      'no se le puede escribir. Pídele su tarjeta (token + QR) otra vez.';

  void _assertNotBlocked(String token) {
    if (isBlocked(token)) {
      throw StateError(blockedMessage);
    }
  }

  /// Asked before anything is written, so a card that cannot be used never
  /// leaves a message stuck in "enviando". The check is the core's verdict, not
  /// a rule reimplemented here — see `EncrypchatCore.assertUsablePublicKey`.
  void _assertUsablePeerKey(Contact peer) {
    try {
      _core.assertUsablePublicKey(
        senderSecret: _identity.requireSecret(),
        publicKey: peer.publicKey,
      );
    } on CoreException catch (e) {
      if (e.code == CoreException.invalidPublicKey) {
        throw StateError(malformedCardMessage);
      }
      rethrow;
    }
  }

  static String _newId() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static Uint8List _idToBytes(String id) {
    try {
      final decoded = base64Url.decode(base64Url.normalize(id));
      if (decoded.length >= 16) {
        return Uint8List.fromList(decoded.sublist(0, 16));
      }
    } catch (_) {}
    final out = Uint8List(16);
    final src = utf8.encode(id);
    for (var i = 0; i < 16; i++) {
      out[i] = i < src.length ? src[i] : 0;
    }
    return out;
  }

  static String _bytesToId(Uint8List bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  @override
  void dispose() {
    _poll?.cancel();
    _relayPoll?.cancel();
    _relay.close();
    if (_core.isNodeRunning) {
      // Not awaited, because `dispose` is synchronous — but the timers are
      // already cancelled and the handle is detached inside, so nothing here
      // touches the node again while the worker finishes what it had queued.
      unawaited(_teardownNode());
    }
    super.dispose();
  }
}
