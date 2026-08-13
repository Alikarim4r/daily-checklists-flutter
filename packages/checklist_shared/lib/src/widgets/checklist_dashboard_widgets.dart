import 'package:flutter/material.dart';

import '../theme/checklist_brand.dart';

/// High-level operational pulse shared by Entry and Viewer dashboards.
class ChecklistPulseCard extends StatelessWidget {
  const ChecklistPulseCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.progressLabel,
    required this.color,
    required this.icon,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final double progress;
  final String progressLabel;
  final Color color;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0.0, 1.0);
    final colors = Theme.of(context).colorScheme;
    return ChecklistBrandCard(
      borderColor: color.withValues(alpha: 0.36),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 420;
          final ring = _ProgressRing(
            value: value,
            label: progressLabel,
            color: color,
          );
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ChecklistIconWell(icon: icon),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (trailing case final Widget trailingWidget) trailingWidget,
                ],
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: TextStyle(color: colors.onSurfaceVariant, height: 1.35),
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                copy,
                const SizedBox(height: 14),
                Center(child: ring),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: copy),
              const SizedBox(width: 18),
              ring,
            ],
          );
        },
      ),
    );
  }
}

class ChecklistMetricTile extends StatelessWidget {
  const ChecklistMetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: onTap != null,
      label: '$label: $value',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              color.withValues(alpha: dark ? 0.18 : 0.09),
              dark ? colors.surfaceContainerHighest : colors.surface,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        color: color,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, color: color, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({
    required this.value,
    required this.label,
    required this.color,
  });

  final double value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 88,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.square(
            dimension: 82,
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: 9,
              strokeCap: StrokeCap.round,
              color: color,
              backgroundColor: color.withValues(alpha: 0.12),
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
