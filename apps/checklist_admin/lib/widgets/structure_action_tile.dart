import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = destructive ? Colors.red.shade700 : scheme.primary;
    final titleColor = destructive
        ? Colors.red.shade700
        : (enabled ? null : scheme.onSurface.withValues(alpha: 0.38));

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: (isDark ? scheme.surfaceContainerHighest : Colors.white)
            .withValues(alpha: ChecklistChrome.listSurfaceOpacity),
        elevation: enabled ? 1 : 0,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(14),
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
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: titleColor,
                        ),
                      ),
                      if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.6),
                              ),
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
                      ? (destructive
                            ? Colors.red.shade700
                            : scheme.onSurface.withValues(alpha: 0.45))
                      : scheme.onSurface.withValues(alpha: 0.2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
