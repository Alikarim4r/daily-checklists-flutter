import 'dart:math' as math;

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';

import 'checkin_tokens.dart';

enum CiTone { neutral, accent, good, warning, danger }

Color ciToneColor(CheckInColors colors, CiTone tone) => switch (tone) {
  CiTone.neutral => colors.inkMuted,
  CiTone.accent => colors.primary,
  CiTone.good => colors.good,
  CiTone.warning => colors.warning,
  CiTone.danger => colors.danger,
};

Color ciToneSoft(CheckInColors colors, CiTone tone) => switch (tone) {
  CiTone.neutral => colors.surfaceRaised,
  CiTone.accent => colors.primarySoft,
  CiTone.good => colors.goodSoft,
  CiTone.warning => colors.warningSoft,
  CiTone.danger => colors.dangerSoft,
};

class CiPageWidth extends StatelessWidget {
  const CiPageWidth({
    super.key,
    required this.child,
    this.maxWidth = CiBreakpoint.wide,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

class CiPanel extends StatelessWidget {
  const CiPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(CiSpace.md),
    this.tone,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final CiTone? tone;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colors = CheckInColors.of(context);
    final outlined = borderColor != null || tone != null;
    return Material(
      color: tone == null ? colors.surface : ciToneSoft(colors, tone!),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: colors.isDark ? .18 : .06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CiRadius.panel),
        side: outlined
            ? BorderSide(
                color: borderColor ?? ciToneColor(colors, tone!),
                width: tone == null ? 1 : 1.2,
              )
            : BorderSide.none,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// CheckIn's primary context block. The start-edge rail is the memorable
/// field-instrument detail and doubles as a progress track.
class CiWorkHeader extends StatelessWidget {
  const CiWorkHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.meta = const [],
    this.progress,
    this.progressLabel,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final List<Widget> meta;
  final double? progress;
  final String? progressLabel;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = CheckInColors.of(context);
    final theme = Theme.of(context);
    final normalized = progress?.clamp(0.0, 1.0);
    return Stack(
      children: [
        CiPanel(
          padding: EdgeInsets.zero,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 5,
                  child: ColoredBox(
                    color: normalized == 1 ? colors.good : colors.primary,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(CiSpace.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Semantics(
                                    header: true,
                                    child: Text(
                                      title,
                                      style: theme.textTheme.headlineSmall,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitle,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colors.inkMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (trailing != null) ...[
                              const SizedBox(width: CiSpace.sm),
                              trailing!,
                            ],
                          ],
                        ),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: CiSpace.sm),
                          Wrap(
                            spacing: CiSpace.md,
                            runSpacing: CiSpace.xs,
                            children: meta,
                          ),
                        ],
                        if (normalized != null) ...[
                          const SizedBox(height: CiSpace.md),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              CiRadius.indicator,
                            ),
                            child: LinearProgressIndicator(
                              minHeight: 7,
                              value: normalized,
                              color: normalized == 1
                                  ? colors.good
                                  : colors.primary,
                              backgroundColor: colors.line,
                              semanticsLabel: progressLabel,
                              semanticsValue: '${(normalized * 100).round()}',
                            ),
                          ),
                          if (progressLabel != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              progressLabel!,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colors.inkMuted,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        PositionedDirectional(
          top: 0,
          start: 5,
          end: 0,
          child: Container(
            height: 2,
            color: colors.primary.withValues(alpha: .72),
          ),
        ),
      ],
    );
  }
}

class CiMeta extends StatelessWidget {
  const CiMeta(this.text, {super.key, this.icon, this.tone = CiTone.neutral});

  final String text;
  final IconData? icon;
  final CiTone tone;

  @override
  Widget build(BuildContext context) {
    final color = ciToneColor(CheckInColors.of(context), tone);
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 5),
        ],
        Flexible(child: Text(text, style: style)),
      ],
    );
  }
}

class CiSectionLabel extends StatelessWidget {
  const CiSectionLabel({
    super.key,
    required this.title,
    this.count,
    this.trailing,
  });

  final String title;
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = CheckInColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, CiSpace.lg, 4, 8),
      child: Row(
        children: [
          Flexible(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            Container(
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              padding: const EdgeInsets.symmetric(horizontal: 7),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.surfaceRaised,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

class CiQueuePanel extends StatelessWidget {
  const CiQueuePanel({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = CheckInColors.of(context);
    return Material(
      color: colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CiRadius.panel),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) Divider(indent: 64, color: colors.line),
            children[index],
          ],
        ],
      ),
    );
  }
}

class CiQueueRow extends StatelessWidget {
  const CiQueueRow({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.icon = Icons.assignment_outlined,
    this.meta = const [],
    this.tone = CiTone.accent,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget> meta;
  final CiTone tone;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = CheckInColors.of(context);
    final tint = ciToneColor(colors, tone);
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 68),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 10, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: ciToneSoft(colors, tone),
                    borderRadius: BorderRadius.circular(CiRadius.control),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: tint, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Wrap(spacing: 12, runSpacing: 4, children: meta),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: colors.inkMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CiCrumb {
  const CiCrumb(this.label, {this.onTap});

  final String label;
  final VoidCallback? onTap;
}

class CiBreadcrumbs extends StatelessWidget {
  const CiBreadcrumbs({super.key, required this.items});

  final List<CiCrumb> items;

  @override
  Widget build(BuildContext context) {
    final colors = CheckInColors.of(context);
    final children = <Widget>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      if (index > 0) {
        children.add(
          Icon(Icons.chevron_right_rounded, size: 16, color: colors.inkMuted),
        );
      }
      final label = Text(
        item.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: item.onTap == null ? colors.ink : colors.primary,
        ),
      );
      children.add(
        item.onTap == null
            ? ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: label,
              )
            : InkWell(
                onTap: item.onTap,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    child: label,
                  ),
                ),
              ),
      );
    }
    return Wrap(
      spacing: 2,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

class CiStatusPill extends StatelessWidget {
  const CiStatusPill({
    super.key,
    required this.label,
    this.tone = CiTone.neutral,
    this.icon,
  });

  final String label;
  final CiTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = CheckInColors.of(context);
    final tint = ciToneColor(colors, tone);
    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: ciToneSoft(colors, tone),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: tint),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: tint,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CiInlineNotice extends StatelessWidget {
  const CiInlineNotice({
    super.key,
    required this.message,
    this.tone = CiTone.neutral,
    this.title,
    this.action,
    this.icon,
  });

  final String? title;
  final String message;
  final CiTone tone;
  final Widget? action;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = CheckInColors.of(context);
    final tint = ciToneColor(colors, tone);
    return Semantics(
      liveRegion: tone == CiTone.danger,
      child: CiPanel(
        tone: tone,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon ??
                  switch (tone) {
                    CiTone.good => Icons.check_circle_outline_rounded,
                    CiTone.warning => Icons.warning_amber_rounded,
                    CiTone.danger => Icons.error_outline_rounded,
                    CiTone.accent => Icons.info_outline_rounded,
                    CiTone.neutral => Icons.info_outline_rounded,
                  },
              color: tint,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(
                      title!,
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(color: tint),
                    ),
                    const SizedBox(height: 3),
                  ],
                  Text(message, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            if (action != null) ...[const SizedBox(width: 8), action!],
          ],
        ),
      ),
    );
  }
}

class CiEmptyState extends StatelessWidget {
  const CiEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.assignment_turned_in_outlined,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = CheckInColors.of(context);
    return CiPanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CiSpace.lg),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.primarySoft,
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: colors.primary, size: 28),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class CiLoadingList extends StatelessWidget {
  const CiLoadingList({super.key, this.rows = 4});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final colors = CheckInColors.of(context);
    return Semantics(
      label: MaterialLocalizations.of(context).alertDialogLabel,
      child: CiQueuePanel(
        children: [
          for (var index = 0; index < rows; index++)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.surfaceRaised,
                      borderRadius: BorderRadius.circular(CiRadius.control),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FractionallySizedBox(
                          widthFactor: index.isEven ? .62 : .78,
                          child: Container(height: 12, color: colors.line),
                        ),
                        const SizedBox(height: 9),
                        FractionallySizedBox(
                          widthFactor: .42,
                          child: Container(height: 8, color: colors.line),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class CiMetric {
  const CiMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.tone = CiTone.neutral,
  });

  final String label;
  final String value;
  final IconData icon;
  final CiTone tone;
}

class CiMetricGrid extends StatelessWidget {
  const CiMetricGrid({super.key, required this.metrics});

  final List<CiMetric> metrics;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 760
          ? math.min(4, metrics.length)
          : 2;
      final rows = <List<CiMetric>>[];
      for (var i = 0; i < metrics.length; i += columns) {
        rows.add(metrics.sublist(i, math.min(i + columns, metrics.length)));
      }
      final colors = CheckInColors.of(context);
      return Material(
        color: colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CiRadius.panel),
          side: BorderSide(color: colors.line),
        ),
        child: Column(
          children: [
            for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
              if (rowIndex > 0) Divider(color: colors.line),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var column = 0; column < columns; column++) ...[
                      if (column > 0)
                        VerticalDivider(width: 1, color: colors.line),
                      Expanded(
                        child: column < rows[rowIndex].length
                            ? _CiMetricCell(metric: rows[rowIndex][column])
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _CiMetricCell extends StatelessWidget {
  const _CiMetricCell({required this.metric});

  final CiMetric metric;

  @override
  Widget build(BuildContext context) {
    final colors = CheckInColors.of(context);
    final tint = ciToneColor(colors, metric.tone);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.all(CiSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(metric.icon, size: 20, color: tint),
            const SizedBox(height: 9),
            Text(
              metric.value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 2),
            Text(
              metric.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class CiBottomActions extends StatelessWidget {
  const CiBottomActions({
    super.key,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    this.busy = false,
    this.primaryIcon = Icons.send_rounded,
    this.secondaryIcon = Icons.save_outlined,
  });

  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String secondaryLabel;
  final VoidCallback? onSecondary;
  final bool busy;
  final IconData primaryIcon;
  final IconData secondaryIcon;

  @override
  Widget build(BuildContext context) {
    final colors = CheckInColors.of(context);
    return Material(
      color: colors.surface,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: .16),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                onPressed: busy ? null : onSecondary,
                icon: Icon(secondaryIcon, size: 20),
                label: Text(
                  secondaryLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: FilledButton.icon(
                onPressed: busy ? null : onPrimary,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(primaryIcon, size: 20),
                label: Text(
                  primaryLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CiResponseSelector extends StatelessWidget {
  const CiResponseSelector({
    super.key,
    required this.value,
    required this.labels,
    required this.onChanged,
    this.enabled = true,
  });

  final ChecklistResponse? value;
  final AppLabels labels;
  final ValueChanged<ChecklistResponse?> onChanged;
  final bool enabled;

  String _label(ChecklistResponse response) => switch (response) {
    ChecklistResponse.yes => labels.yes,
    ChecklistResponse.no => labels.no,
    ChecklistResponse.na => labels.na,
  };

  @override
  Widget build(BuildContext context) {
    final colors = CheckInColors.of(context);
    return Row(
      children: [
        for (
          var index = 0;
          index < ChecklistResponse.values.length;
          index++
        ) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: _ResponseCell(
              response: ChecklistResponse.values[index],
              label: _label(ChecklistResponse.values[index]),
              selected: value == ChecklistResponse.values[index],
              enabled: enabled,
              colors: colors,
              onTap: () => onChanged(
                value == ChecklistResponse.values[index]
                    ? null
                    : ChecklistResponse.values[index],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ResponseCell extends StatelessWidget {
  const _ResponseCell({
    required this.response,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.colors,
    required this.onTap,
  });

  final ChecklistResponse response;
  final String label;
  final bool selected;
  final bool enabled;
  final CheckInColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = switch (response) {
      ChecklistResponse.yes => CiTone.good,
      ChecklistResponse.no => CiTone.danger,
      ChecklistResponse.na => CiTone.neutral,
    };
    final tint = ciToneColor(colors, tone);
    final cell = AnimatedContainer(
      duration: CiMotion.of(context, CiMotion.quick),
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: selected ? ciToneSoft(colors, tone) : colors.surface,
        border: Border.all(
          color: selected ? tint : colors.lineStrong,
          width: selected ? 1.6 : 1,
        ),
        borderRadius: BorderRadius.circular(CiRadius.control),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (selected) ...[
            Icon(Icons.check_rounded, size: 17, color: tint),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected ? tint : colors.ink,
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(CiRadius.control),
          child: cell,
        ),
      ),
    );
  }
}

class CiInspectionItemFrame extends StatelessWidget {
  const CiInspectionItemFrame({
    super.key,
    required this.index,
    required this.title,
    required this.child,
    this.statusLabel,
    this.tone = CiTone.neutral,
  });

  final int index;
  final String title;
  final Widget child;
  final String? statusLabel;
  final CiTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = CheckInColors.of(context);
    final tint = ciToneColor(colors, tone);
    return Material(
      color: colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CiRadius.panel),
        side: BorderSide(
          color: tone == CiTone.neutral ? colors.line : tint,
          width: tone == CiTone.neutral ? 1 : 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tone == CiTone.neutral
                        ? colors.surfaceRaised
                        : ciToneSoft(colors, tone),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$index',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: tone == CiTone.neutral ? colors.ink : tint,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (statusLabel != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: CiStatusPill(label: statusLabel!, tone: tone),
                  ),
                ],
              ],
            ),
          ),
          Divider(color: colors.line),
          Padding(padding: const EdgeInsets.all(14), child: child),
        ],
      ),
    );
  }
}
