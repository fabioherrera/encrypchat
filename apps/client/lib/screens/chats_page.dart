import 'package:flutter/material.dart';

import '../theme/encrypchat_colors.dart';

class ChatsPage extends StatelessWidget {
  const ChatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EncrypchatColors.canvas,
      appBar: AppBar(title: const Text('Chats')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 56,
                color: EncrypchatColors.navy.withValues(alpha: 0.45),
              ),
              const SizedBox(height: 16),
              const Text(
                'Sin chats aún',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: EncrypchatColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'La mensajería P2P llega en la Fase 4. '
                'Creá tu identidad e importá contactos mientras tanto.',
                textAlign: TextAlign.center,
                style: TextStyle(color: EncrypchatColors.muted, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
