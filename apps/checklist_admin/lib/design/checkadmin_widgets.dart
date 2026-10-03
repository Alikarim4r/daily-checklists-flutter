import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'checkadmin_tokens.dart';

enum CaTone { neutral, accent, brass, good, warning, danger }

Color caToneColor(CheckAdminColors c, CaTone tone) => switch (tone) {
  CaTone.neutral => c.inkMuted,
  CaTone.accent => c.primary,
  CaTone.brass => c.brass,
  CaTone.good => c.good,
  CaTone.warning => c.warning,
  CaTone.danger => c.danger,
};

Color caToneSoft(CheckAdminColors c, CaTone tone) => switch (tone) {
  CaTone.neutral => c.surfaceRaised,
  CaTone.accent => c.primarySoft,
  CaTone.brass => c.brassSoft,
  CaTone.good => c.goodSoft,
  CaTone.warning => c.warningSoft,
  CaTone.danger => c.dangerSoft,
};

class CaPageWidth extends StatelessWidget {
  const CaPageWidth({super.key, required this.child, this.maxWidth = 1440});
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

class CaRoleBadge extends StatelessWidget {
  const CaRoleBadge({super.key, required this.label, this.tone = CaTone.brass});
  final String label;
  final CaTone tone;

  @override
  Widget build(BuildContext context) {
    final c = CheckAdminColors.of(context);
    final tint = caToneColor(c, tone);
    return Container(
      constraints: const BoxConstraints(minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: caToneSoft(c, tone),
        borderRadius: BorderRadius.circular(CaRadius.mark),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: tint,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class CaPageHeader extends StatelessWidget {
  const CaPageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.meta = const [],
    this.trailing,
  });
  final String eyebrow, title;
  final String? subtitle;
  final List<Widget> meta;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = CheckAdminColors.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.rule)),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              CaSpace.gutter,
              CaSpace.md,
              CaSpace.gutter,
              CaSpace.md + 2,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        rtl ? eyebrow : eyebrow.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: c.inkMuted,
                          letterSpacing: rtl ? 0 : .8,
                        ),
                      ),
                      const SizedBox(height: CaSpace.xs),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: CaSpace.xs),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: CaSpace.sm),
                        Wrap(spacing: 10, runSpacing: 4, children: meta),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
          ),
          PositionedDirectional(
            start: CaSpace.gutter,
            bottom: 0,
            child: Container(width: 52, height: 2, color: c.brass),
          ),
        ],
      ),
    );
  }
}

class CaMeta extends StatelessWidget {
  const CaMeta(this.text, {super.key, this.icon, this.tone = CaTone.neutral});
  final String text;
  final IconData? icon;
  final CaTone tone;
  @override
  Widget build(BuildContext context) {
    final c = CheckAdminColors.of(context);
    final tint = caToneColor(c, tone);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: tint),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tint),
          ),
        ),
      ],
    );
  }
}

class CaSectionLabel extends StatelessWidget {
  const CaSectionLabel({
    super.key,
    required this.title,
    this.count,
    this.trailing,
    this.padding,
  });
  final String title;
  final int? count;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = CheckAdminColors.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding:
            padding ??
            const EdgeInsetsDirectional.fromSTEB(
              CaSpace.gutter,
              CaSpace.xs,
              CaSpace.gutter,
              CaSpace.xs,
            ),
        child: Row(
          children: [
            Flexible(
              child: Text(
                rtl ? title : title.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: c.inkMuted,
                  letterSpacing: rtl ? 0 : .8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: c.surfaceRaised,
                  borderRadius: BorderRadius.circular(CaRadius.mark),
                ),
                child: Text(
                  '$count',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
            const Spacer(),
            if (trailing != null) Flexible(flex: 0, child: trailing!),
          ],
        ),
      ),
    );
  }
}

class CaMetaStrip extends StatelessWidget {
  const CaMetaStrip({super.key, required this.items, this.warningItem});
  final List<String> items;
  final String? warningItem;

  @override
  Widget build(BuildContext context) {
    final c = CheckAdminColors.of(context);
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: c.inkMuted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Container(
      color: c.surface,
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(
        CaSpace.gutter,
        5,
        CaSpace.gutter,
        7,
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 2,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            Text(items[i], style: style),
            if (i < items.length - 1 || warningItem != null)
              Text('·', style: style),
          ],
          if (warningItem != null)
            Text(
              warningItem!,
              style: style?.copyWith(
                color: c.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class CaCreateButton extends StatelessWidget {
  const CaCreateButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.compactLabel,
  });
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final String? compactLabel;

  @override
  Widget build(BuildContext context) {
    final c = CheckAdminColors.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final iconOnly = width < 340 || textScale > 1.3;
    final shown = width < 390 && compactLabel != null ? compactLabel! : label;
    final style = FilledButton.styleFrom(
      backgroundColor: c.primarySoft,
      foregroundColor: c.primaryStrong,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 11),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CaRadius.control),
      ),
      elevation: 0,
    );
    if (iconOnly) {
      return Tooltip(
        message: label,
        child: Semantics(
          button: true,
          label: label,
          child: SizedBox(
            width: 44,
            height: 44,
            child: FilledButton(
              style: style.copyWith(
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              ),
              onPressed: onPressed,
              child: Icon(icon, size: 20),
            ),
          ),
        ),
      );
    }
    return FilledButton.icon(
      style: style,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(shown),
    );
  }
}

class CaCodeBadge extends StatelessWidget {
  const CaCodeBadge({
    super.key,
    required this.code,
    this.width,
    this.tone = CaTone.neutral,
  });
  final String code;
  final double? width;
  final CaTone tone;

  @override
  Widget build(BuildContext context) {
    final c = CheckAdminColors.of(context);
    final child = Container(
      constraints: const BoxConstraints(minHeight: 24),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: caToneSoft(c, tone),
        borderRadius: BorderRadius.circular(CaRadius.mark),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            code,
            maxLines: 1,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: caToneColor(c, tone),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
    return width == null ? child : SizedBox(width: width, child: child);
  }
}

class CaSelectorRow extends StatelessWidget {
  const CaSelectorRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.leading,
    this.status,
  });
  final String title, subtitle;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? status;

  @override
  Widget build(BuildContext context) {
    final c = CheckAdminColors.of(context);
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: subtitle.trim().isEmpty ? title : '$title, $subtitle',
      child: Material(
        color: c.surface,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 9, 10, 9),
              child: Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 10)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 2,
                          children: [
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                subtitle,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            ?status,
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: c.inkMuted,
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

class CaPanel extends StatelessWidget {
  const CaPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(CaSpace.md),
    this.tone = CaTone.neutral,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final CaTone tone;
  @override
  Widget build(BuildContext context) {
    final c = CheckAdminColors.of(context);
    return Material(
      color: c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CaRadius.panel),
        side: tone == CaTone.neutral
            ? BorderSide.none
            : BorderSide(color: caToneColor(c, tone).withValues(alpha: .55)),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class CaMetric {
  const CaMetric({
    required this.label,
    required this.value,
    this.icon,
    this.tone = CaTone.neutral,
  });
  final String label, value;
  final IconData? icon;
  final CaTone tone;
}

class CaMetricStrip extends StatelessWidget {
  const CaMetricStrip({super.key, required this.metrics});
  final List<CaMetric> metrics;
  @override
  Widget build(BuildContext context) {
    final c = CheckAdminColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = math.max(
          1,
          math.min(metrics.length, (constraints.maxWidth / 150).floor()),
        );
        return Material(
          color: c.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CaRadius.panel),
          ),
          child: Wrap(
            children: [
              for (var i = 0; i < metrics.length; i++)
                SizedBox(
                  width: constraints.maxWidth / columns - .5,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 92),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: BorderDirectional(
                        end: BorderSide(
                          color: (i + 1) % columns == 0
                              ? Colors.transparent
                              : c.rule,
                        ),
                        bottom: BorderSide(
                          color: i < metrics.length - columns
                              ? c.rule
                              : Colors.transparent,
                        ),
                      ),
                    ),
                    child: _MetricCell(metric: metrics[i]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.metric});
  final CaMetric metric;
  @override
  Widget build(BuildContext context) {
    final c = CheckAdminColors.of(context);
    final tint = caToneColor(c, metric.tone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            if (metric.icon != null) ...[
              Icon(metric.icon, size: 16, color: tint),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                metric.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: c.inkMuted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          metric.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: metric.tone == CaTone.neutral ? c.ink : tint,
          ),
        ),
      ],
    );
  }
}

class CaCommandRow extends StatelessWidget {
  const CaCommandRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.meta = const [],
    this.trailing,
    this.selected = false,
    this.onTap,
    this.minHeight = 56,
    this.showChevron = true,
  });
  final String title;
  final String? subtitle;
  final Widget? leading, trailing;
  final List<Widget> meta;
  final bool selected;
  final VoidCallback? onTap;
  final double minHeight;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final c = CheckAdminColors.of(context);
    final body = AnimatedContainer(
      duration: CaMotion.of(context, CaMotion.quick),
      color: selected
          ? c.primarySoft.withValues(alpha: .65)
          : Colors.transparent,
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 9, 10, 9),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
                  const SizedBox(height: 4),
                  Wrap(spacing: 10, runSpacing: 2, children: meta),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (onTap != null && showChevron)
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: c.inkMuted,
              textDirection: Directionality.of(context),
            ),
        ],
      ),
    );
    return onTap == null
        ? body
        : Semantics(
            button: true,
            selected: selected,
            label: subtitle == null || subtitle!.trim().isEmpty
                ? title
                : '$title, $subtitle',
            child: InkWell(
              onTap: onTap,
              overlayColor: WidgetStatePropertyAll(
                c.primary.withValues(alpha: .06),
              ),
              child: body,
            ),
          );
  }
}

class CaLedger extends StatelessWidget {
  const CaLedger({super.key, required this.children, this.inset = false});
  final List<Widget> children;
  final bool inset;

  @override
  Widget build(BuildContext context) {
    final c = CheckAdminColors.of(context);
    final useInset =
        inset || MediaQuery.sizeOf(context).width >= CaBreakpoint.inset;
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Divider(
              color: c.rule,
              indent: CaSpace.gutter,
              endIndent: 0,
              height: 1,
            ),
          children[i],
        ],
      ],
    );
    if (useInset) {
      return Material(
        color: c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CaRadius.panel),
        ),
        child: column,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(
          top: BorderSide(color: c.rule),
          bottom: BorderSide(color: c.rule),
        ),
      ),
      child: Material(color: Colors.transparent, child: column),
    );
  }
}

class CaInlineNotice extends StatelessWidget {
  const CaInlineNotice({
    super.key,
    required this.message,
    this.title,
    this.tone = CaTone.accent,
    this.onDismiss,
  });
  final String message;
  final String? title;
  final CaTone tone;
  final VoidCallback? onDismiss;
  @override
  Widget build(BuildContext context) {
    final c = CheckAdminColors.of(context);
    final tint = caToneColor(c, tone);
    final icon = switch (tone) {
      CaTone.good => Icons.check_circle_outline,
      CaTone.warning => Icons.warning_amber_rounded,
      CaTone.danger => Icons.error_outline,
      _ => Icons.info_outline,
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          border: BorderDirectional(start: BorderSide(color: tint, width: 3)),
          borderRadius: BorderRadius.circular(CaRadius.control),
        ),
        padding: const EdgeInsetsDirectional.fromSTEB(12, 11, 6, 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19, color: tint),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(title!, style: Theme.of(context).textTheme.titleSmall),
                  Text(
                    message,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            if (onDismiss != null)
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: onDismiss,
                icon: const Icon(Icons.close, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}

class CaEmptyState extends StatelessWidget {
  const CaEmptyState({
    super.key,
    required this.title,
    required this.icon,
    this.message,
    this.action,
  });
  final String title;
  final IconData icon;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = CheckAdminColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(CaSpace.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.surfaceRaised,
                  borderRadius: BorderRadius.circular(CaRadius.control),
                ),
                child: Icon(icon, size: 24, color: c.inkMuted),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (message != null) ...[
                const SizedBox(height: 4),
                Text(
                  message!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (action != null) ...[const SizedBox(height: 12), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class CaSkeletonList extends StatelessWidget {
  const CaSkeletonList({super.key, this.rows = 5});
  final int rows;
  @override
  Widget build(BuildContext context) {
    final c = CheckAdminColors.of(context);
    return CaLedger(
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  widthFactor: i.isEven ? .42 : .58,
                  child: Container(height: 12, color: c.surfaceRaised),
                ),
                const SizedBox(height: 8),
                FractionallySizedBox(
                  widthFactor: i.isEven ? .68 : .35,
                  child: Container(height: 9, color: c.surfaceRaised),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
