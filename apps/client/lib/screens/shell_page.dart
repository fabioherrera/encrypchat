import 'package:flutter/material.dart';

import '../services/session_controller.dart';
import '../theme/encrypchat_colors.dart';
import 'chats_page.dart';
import 'contacts_page.dart';
import 'my_token_page.dart';

class ShellPage extends StatefulWidget {
  const ShellPage({super.key, required this.session});

  final SessionController session;

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (_index) {
      0 => ChatsPage(session: widget.session),
      1 => ContactsPage(session: widget.session),
      _ => MyTokenPage(session: widget.session),
    };

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: EncrypchatColors.paper,
        indicatorColor: EncrypchatColors.bubbleOut,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Contactos',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_2_outlined),
            selectedIcon: Icon(Icons.qr_code_2),
            label: 'Mi token',
          ),
        ],
      ),
    );
  }
}
