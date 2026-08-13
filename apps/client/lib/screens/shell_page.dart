import 'dart:async';

import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../services/session_controller.dart';
import '../services/update_applier.dart';
import '../services/update_checker.dart';
import '../theme/encrypchat_colors.dart';
import '../widgets/update_banner.dart';
import 'call_overlay_host.dart';
import 'chats_page.dart';
import 'contacts_page.dart';
import 'chat_page.dart';
import 'my_token_page.dart';
import 'settings_page.dart';

/// Width at which the shell becomes a desktop split (list | conversation).
const desktopSplitBreakpoint = 840.0;

class ShellPage extends StatefulWidget {
  const ShellPage({
    super.key,
    required this.session,
    this.updates,
    this.applier,
  });

  final SessionController session;

  /// Injectable so tests do not hit the network.
  final UpdateChecker? updates;
  final UpdateApplier? applier;

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int _index = 0;
  Contact? _openPeer;
  late final UpdateChecker _updates;
  late final UpdateApplier _applier;
  late final bool _ownsUpdates;
  late final bool _ownsApplier;
  bool _offerShown = false;

  @override
  void initState() {
    super.initState();
    _ownsUpdates = widget.updates == null;
    _ownsApplier = widget.applier == null;
    _updates = widget.updates ?? UpdateChecker();
    _applier = widget.applier ?? UpdateApplier();
    _updates.addListener(_onUpdates);
    _applier.addListener(_onUpdates);
    widget.session.addListener(_onSession);
    unawaited(_updates.check());
  }

  void _onUpdates() {
    if (!mounted) return;
    setState(() {});
    if (_updates.info.hasUpdate && !_offerShown) {
      _offerShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_openOffer());
      });
    }
  }

  Future<void> _openOffer() {
    return showUpdateOffer(
      context: context,
      info: _updates.info,
      applier: _applier,
    );
  }

  void _onSession() {
    if (!mounted) return;
    final open = _openPeer;
    if (open == null) {
      setState(() {});
      return;
    }
    final stillThere = widget.session.contacts.any((c) => c.token == open.token);
    setState(() {
      if (!stillThere) _openPeer = null;
    });
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    _updates.removeListener(_onUpdates);
    _applier.removeListener(_onUpdates);
    if (_ownsUpdates) _updates.dispose();
    if (_ownsApplier) _applier.dispose();
    super.dispose();
  }

  void _openChat(Contact peer) {
    setState(() {
      _openPeer = peer;
      _index = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CallOverlayHost(
      session: widget.session,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= desktopSplitBreakpoint;
          if (desktop) return _desktop(context);
          return _mobile();
        },
      ),
    );
  }

  Widget _mobile() {
    return Scaffold(
      body: Column(
        children: [
          UpdateBanner(
            info: _updates.info,
            onReview: () {
              unawaited(_openOffer());
            },
          ),
          Expanded(child: _tabBody(embeddedChat: false)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _destinations(),
      ),
    );
  }

  Widget _desktop(BuildContext context) {
    final peer = _openPeer;
    return Scaffold(
      backgroundColor: EncrypchatColors.canvas,
      body: Column(
        children: [
          UpdateBanner(
            info: _updates.info,
            onReview: () {
              unawaited(_openOffer());
            },
          ),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 340,
                  child: Column(
                    children: [
                      Expanded(child: _tabBody(embeddedChat: true)),
                      _DesktopTabBar(
                        index: _index,
                        hasUpdate: _updates.info.hasUpdate,
                        onSelect: (i) => setState(() => _index = i),
                      ),
                    ],
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  color: EncrypchatColors.navy.withValues(alpha: 0.12),
                ),
                Expanded(
                  child: peer == null
                      ? const _EmptyConversation()
                      : ChatPage(
                          key: ValueKey(peer.token),
                          session: widget.session,
                          peer: peer,
                          embedded: true,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBody({required bool embeddedChat}) {
    return switch (_index) {
      0 => ChatsPage(
        session: widget.session,
        selectedToken: embeddedChat ? _openPeer?.token : null,
        onOpenChat: embeddedChat
            ? _openChat
            : (peer) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ChatPage(session: widget.session, peer: peer),
                  ),
                );
              },
      ),
      1 => ContactsPage(
        session: widget.session,
        onOpenContact: embeddedChat ? _openChat : null,
      ),
      2 => MyTokenPage(session: widget.session),
      _ => SettingsPage(
        session: widget.session,
        updates: _updates,
        applier: _applier,
      ),
    };
  }

  List<NavigationDestination> _destinations() {
    return [
      const NavigationDestination(
        icon: Icon(Icons.chat_bubble_outline, color: EncrypchatColors.navy),
        selectedIcon: Icon(Icons.chat_bubble, color: EncrypchatColors.navy),
        label: 'Chats',
      ),
      const NavigationDestination(
        icon: Icon(Icons.people_outline, color: EncrypchatColors.iconContacts),
        selectedIcon: Icon(Icons.people, color: EncrypchatColors.iconContacts),
        label: 'Contactos',
      ),
      const NavigationDestination(
        icon: Icon(Icons.qr_code_2_outlined, color: EncrypchatColors.navyMid),
        selectedIcon: Icon(Icons.qr_code_2, color: EncrypchatColors.navyMid),
        label: 'Mi token',
      ),
      NavigationDestination(
        icon: Badge(
          isLabelVisible: _updates.info.hasUpdate,
          child: const Icon(
            Icons.settings_outlined,
            color: EncrypchatColors.muted,
          ),
        ),
        selectedIcon: Badge(
          isLabelVisible: _updates.info.hasUpdate,
          child: const Icon(Icons.settings, color: EncrypchatColors.muted),
        ),
        label: 'Ajustes',
      ),
    ];
  }
}

class _DesktopTabBar extends StatelessWidget {
  const _DesktopTabBar({
    required this.index,
    required this.onSelect,
    required this.hasUpdate,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final bool hasUpdate;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EncrypchatColors.paper,
      elevation: 8,
      shadowColor: EncrypchatColors.ink.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _tab(
              0,
              Icons.chat_bubble,
              Icons.chat_bubble_outline,
              'Chats',
              EncrypchatColors.navy,
            ),
            _tab(
              1,
              Icons.people,
              Icons.people_outline,
              'Contactos',
              EncrypchatColors.iconContacts,
            ),
            _tab(
              2,
              Icons.qr_code_2,
              Icons.qr_code_2_outlined,
              'Mi token',
              EncrypchatColors.navyMid,
            ),
            _tab(
              3,
              Icons.settings,
              Icons.settings_outlined,
              'Ajustes',
              EncrypchatColors.muted,
              badge: hasUpdate,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab(
    int i,
    IconData selected,
    IconData idle,
    String label,
    Color color, {
    bool badge = false,
  }) {
    final on = index == i;
    return InkWell(
      onTap: () => onSelect(i),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Badge(
              isLabelVisible: badge,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: EncrypchatColors.paper,
                  boxShadow: EncrypchatColors.raisedShadow,
                ),
                child: Icon(on ? selected : idle, size: 18, color: color),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                color: on ? EncrypchatColors.navy : EncrypchatColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: EncrypchatColors.canvas,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 48,
                color: EncrypchatColors.offline,
              ),
              SizedBox(height: 16),
              Text(
                'Elegí un chat',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: EncrypchatColors.ink,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Los mensajes se quedan en este dispositivo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: EncrypchatColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
