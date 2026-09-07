import 'package:flutter/material.dart';
import 'package:simple_icons/simple_icons.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/shared/services/whatsapp.dart';

/// "Contacter sur WhatsApp" (cahier §8), as a filled brand-green disc with the
/// real WhatsApp glyph — a generic chat bubble doesn't tell the member which
/// app is about to open. Tapping only hands off to WhatsApp; nothing is ever
/// sent automatically.
class WhatsAppButton extends StatelessWidget {
  const WhatsAppButton({required this.phoneNumber, this.size = 40, super.key});

  final String? phoneNumber;
  final double size;

  @override
  Widget build(BuildContext context) {
    final enabled = phoneNumber != null && phoneNumber!.trim().isNotEmpty;
    final scheme = Theme.of(context).colorScheme;
    final bg = enabled
        ? SbcColors.whatsapp
        : scheme.onSurfaceVariant.withValues(alpha: 0.12);
    final fg = enabled ? Colors.white : scheme.onSurfaceVariant;

    return Tooltip(
      message: enabled ? 'Contacter sur WhatsApp' : 'Numéro non disponible',
      child: Semantics(
        button: true,
        label: 'Contacter sur WhatsApp',
        child: Material(
          color: bg,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? () => openWhatsApp(phoneNumber!) : null,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(SimpleIcons.whatsapp, size: size * 0.55, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}
