import 'package:flutter/material.dart';

import 'theme/encrypchat_colors.dart';
import 'theme/encrypchat_theme.dart';

/// Encrypchat shell — UI tokens from docs/design/design-system.md
void main() {
  runApp(const EncrypchatApp());
}

class EncrypchatApp extends StatelessWidget {
  const EncrypchatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Encrypchat',
      debugShowCheckedModeBanner: false,
      theme: buildEncrypchatLightTheme(),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Encrypchat'),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Encrypchat',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: EncrypchatColors.navy,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'DECENTRALIZED P2P CHAT | ZERO-CLOUD',
                textAlign: TextAlign.center,
                style: TextStyle(
                  letterSpacing: 0.5,
                  color: EncrypchatColors.muted,
                ),
              ),
              SizedBox(height: 24),
              Text(
                'Light theme approved — chat UI lands in later phases.',
                textAlign: TextAlign.center,
                style: TextStyle(color: EncrypchatColors.ink),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.send),
      ),
    );
  }
}
