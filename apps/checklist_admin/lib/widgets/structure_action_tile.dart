import 'package:flutter/material.dart';

import '../design/checkadmin_tokens.dart';

/// Smart-meters-style action row used in Structure detail pane.
class StructureActionTile extends StatelessWidget {
  const StructureActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.destructive = false,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool enabled;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = CheckAdminColors.of(context);
    final accent = destructive ? c.danger : c.primary;
    final titleColor = destructive
        ? c.danger
        : (enabled ? c.ink : c.inkMuted.withValues(alpha: 0.55));

    return Semantics(
      button: true,
      enabled: enabled,
      label: subtitle == null || subtitle!.trim().isEmpty
          ? label
          : '$label, $subtitle',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: c.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: destructive ? c.danger.withValues(alpha: 0.35) : c.rule,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: titleColor,
                              ),
                        ),
                        if (subtitle != null &&
                            subtitle!.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(color: c.inkMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    destructive
                        ? Icons.delete_forever_outlined
                        : Icons.chevron_left,
                    size: destructive ? 22 : 20,
                    color: enabled
                        ? (destructive ? c.danger : c.inkMuted)
                        : c.inkMuted.withValues(alpha: 0.35),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
