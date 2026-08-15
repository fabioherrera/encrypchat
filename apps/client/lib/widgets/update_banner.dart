import 'package:flutter/material.dart';

import '../core/legal_links.dart';
import '../core/update_copy.dart';
import '../screens/about_page.dart';
import '../services/update_applier.dart';
import '../services/update_checker.dart';
import '../theme/encrypchat_colors.dart';

/// In-app notice that a newer package exists.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.info, required this.onReview});

  final UpdateInfo info;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    if (!info.hasUpdate) return const SizedBox.shrink();
    final latest = info.latestVersion ?? '';
    return Material(
      color: const Color(0xFFFFF4E5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            const Icon(
              Icons.system_update_alt,
              size: 18,
              color: Color(0xFF8A5A00),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Hay una versión nueva ($latest). Actualiza solo la app: '
                'seguridad, estabilidad y funciones. Tus datos se quedan '
                'en este dispositivo.',
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: Color(0xFF8A5A00),
                ),
              ),
            ),
            TextButton(onPressed: onReview, child: const Text('Ver')),
          ],
        ),
      ),
    );
  }
}

Future<void> showUpdateOffer({
  required BuildContext context,
  required UpdateInfo info,
  required UpdateApplier applier,
}) {
  if (applier.phase == UpdateApplyPhase.done ||
      applier.phase == UpdateApplyPhase.failed) {
    applier.reset();
  }
  return showDialog<void>(
    context: context,
    barrierDismissible: applier.phase == UpdateApplyPhase.idle,
    builder: (context) => UpdateOfferDialog(info: info, applier: applier),
  );
}

class UpdateOfferDialog extends StatelessWidget {
  const UpdateOfferDialog({
    super.key,
    required this.info,
    required this.applier,
  });

  final UpdateInfo info;
  final UpdateApplier applier;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: applier,
      builder: (context, _) {
        final phase = applier.phase;
        final busy =
            phase == UpdateApplyPhase.downloading ||
            phase == UpdateApplyPhase.verifying ||
            phase == UpdateApplyPhase.installing;
        return AlertDialog(
          title: const Text(UpdateCopy.title),
          content: SizedBox(width: 420, child: _body(phase, busy)),
          actions: [
            if (!busy && phase != UpdateApplyPhase.done)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(UpdateCopy.later),
              ),
            if (phase == UpdateApplyPhase.idle ||
                phase == UpdateApplyPhase.failed)
              FilledButton(
                onPressed: () => _apply(context),
                child: Text(
                  info.canApply ? UpdateCopy.apply : UpdateCopy.openSite,
                ),
              ),
            if (phase == UpdateApplyPhase.done)
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Entendido'),
              ),
          ],
        );
      },
    );
  }

  Widget _body(UpdateApplyPhase phase, bool busy) {
    final latest = info.latestVersion ?? '';
    final current = info.currentVersion;
    if (phase == UpdateApplyPhase.idle) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            UpdateCopy.headline(latest, current),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: EncrypchatColors.ink,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            UpdateCopy.body,
            style: TextStyle(height: 1.45, color: EncrypchatColors.ink),
          ),
        ],
      );
    }
    if (phase == UpdateApplyPhase.failed) {
      return Text(
        applier.error ?? 'No se pudo actualizar.',
        style: const TextStyle(height: 1.45, color: EncrypchatColors.ink),
      );
    }
    if (phase == UpdateApplyPhase.done) {
      return const Text(
        UpdateCopy.done,
        style: TextStyle(height: 1.45, color: EncrypchatColors.ink),
      );
    }
    final label = switch (phase) {
      UpdateApplyPhase.downloading => UpdateCopy.downloading,
      UpdateApplyPhase.verifying => UpdateCopy.verifying,
      UpdateApplyPhase.installing => UpdateCopy.installing,
      _ => UpdateCopy.downloading,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: phase == UpdateApplyPhase.downloading && applier.progress > 0
              ? applier.progress
              : null,
          color: EncrypchatColors.navy,
        ),
      ],
    );
  }

  Future<void> _apply(BuildContext context) async {
    if (!info.canApply) {
      final url =
          info.downloadUrl ?? LegalLinks.download(LegalLinks.deviceLocale);
      if (context.mounted) Navigator.of(context).pop();
      if (context.mounted) await openExternalUrl(context, url);
      return;
    }
    await applier.apply(info.package!);
  }
}
