import 'dart:math' as math;

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';

import 'checkview_tokens.dart';

// ---------------------------------------------------------------------------
// Status semantics
// ---------------------------------------------------------------------------

enum CvTone { approved, pending, returned, rejected, neutral, accent }

Color cvToneColor(CheckViewColors c, CvTone tone) => switch (tone) {
  CvTone.approved => c.approved,
  CvTone.pending => c.pending,
  CvTone.returned => c.returned,
  CvTone.rejected => c.rejected,
  CvTone.neutral => c.neutral,
  CvTone.accent => c.accent,
};

CvTone cvReviewTone(ReviewStatus status) => switch (status) {
  ReviewStatus.approved => CvTone.approved,
  ReviewStatus.submitted => CvTone.pending,
  ReviewStatus.returned => CvTone.returned,
  ReviewStatus.rejected => CvTone.rejected,
  ReviewStatus.draft || ReviewStatus.canceled => CvTone.neutral,
};

CvTone cvActionStatusTone(CorrectiveActionStatus status) => switch (status) {
  CorrectiveActionStatus.open => CvTone.returned,
  CorrectiveActionStatus.inProgress => CvTone.accent,
  CorrectiveActionStatus.pendingVerification => CvTone.pending,
  CorrectiveActionStatus.closed => CvTone.approved,
  CorrectiveActionStatus.canceled => CvTone.neutral,
};

CvTone cvPriorityTone(CorrectiveActionPriority priority) => switch (priority) {
  CorrectiveActionPriority.critical => CvTone.rejected,
  CorrectiveActionPriority.high => CvTone.returned,
  CorrectiveActionPriority.medium ||
  CorrectiveActionPriority.low => CvTone.neutral,
};

/// A square swatch plus a label; color is never the only signal.
class CvStatusMark extends StatelessWidget {
  const CvStatusMark({super.key, required this.label, required this.tone});

  final String label;
  final CvTone tone;

  @override
  Widget build(BuildContext context) {
    final color = cvToneColor(CheckViewColors.of(context), tone);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Title block — the CheckView signature
// ---------------------------------------------------------------------------

class CvTitleField {
  const CvTitleField({
    required this.label,
    this.value,
    this.child,
    this.onTap,
    this.flex = 1,
    this.maxLines = 1,
    this.scaleDown = false,
  }) : assert(value != null || child != null);

  final String label;
  final String? value;

  /// Custom value presentation (for example a [CvStatusMark]).
  final Widget? child;
  final VoidCallback? onTap;
  final int flex;
  final int maxLines;

  /// Shrinks a short fixed-format value (a date) instead of truncating it on
  /// narrow phones or large text scales.
  final bool scaleDown;
}

/// Ruled context strip modelled on an architectural drawing title block.
///
/// The brass datum line underneath turns into the progress indicator while
/// [loading] is true, so loading never shifts the layout.
class CvTitleBlock extends StatelessWidget {
  const CvTitleBlock({super.key, required this.fields, this.loading = false});

  final List<CvTitleField> fields;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = CheckViewColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackFirst = constraints.maxWidth < 560 && fields.length > 2;
        final rows = stackFirst
            ? [
                [fields.first],
                fields.sublist(1),
              ]
            : [fields];
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 1, color: c.hairline),
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) Container(height: 1, color: c.hairline),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < rows[r].length; i++) ...[
                      if (i > 0) Container(width: 1, color: c.hairline),
                      Expanded(
                        flex: rows[r][i].flex,
                        child: _TitleCell(field: rows[r][i]),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            CvDatumLine(loading: loading),
          ],
        );
      },
    );
  }
}

class _TitleCell extends StatelessWidget {
  const _TitleCell({required this.field});

  final CvTitleField field;

  @override
  Widget build(BuildContext context) {
    final c = CheckViewColors.of(context);
    final theme = Theme.of(context);
    final valueStyle = theme.textTheme.titleSmall?.copyWith(
      fontSize: 14.5,
      fontFeatures: cvTabular,
    );
    final value =
        field.child ??
        (field.scaleDown
            ? FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(field.value!, maxLines: 1, style: valueStyle),
              )
            : Text(
                field.value!,
                maxLines: field.maxLines,
                overflow: TextOverflow.ellipsis,
                style: valueStyle,
              ));
    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          CvSpace.gutter,
          10,
          CvSpace.sm,
          10,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    field.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(height: 3),
                  value,
                ],
              ),
            ),
            if (field.onTap != null)
              Icon(Icons.expand_more, size: 20, color: c.inkMuted),
          ],
        ),
      ),
    );
    if (field.onTap == null) {
      return MergeSemantics(child: body);
    }
    return Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: field.onTap, child: body),
    );
  }
}

/// The brass datum line on its own; doubles as a progress indicator.
class CvDatumLine extends StatelessWidget {
  const CvDatumLine({super.key, this.loading = false});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = CheckViewColors.of(context);
    return SizedBox(
      height: 2,
      child: loading
          ? LinearProgressIndicator(
              minHeight: 2,
              color: c.accent,
              backgroundColor: c.datum.withValues(alpha: 0.35),
            )
          : ColoredBox(color: c.datum),
    );
  }
}

// ---------------------------------------------------------------------------
// Ledgers — hairline-divided surfaces instead of one card per row
// ---------------------------------------------------------------------------

class CvSectionHeader extends StatelessWidget {
  const CvSectionHeader({
    super.key,
    required this.title,
    this.count,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(4, CvSpace.xl, 4, CvSpace.sm),
  });

  final String title;
  final int? count;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Flexible(
            child: Semantics(
              header: true,
              child: Text(title, style: theme.textTheme.titleMedium),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: CvSpace.sm),
            Text(
              '$count',
              style: theme.textTheme.labelMedium?.copyWith(
                color: CheckViewColors.of(context).inkMuted,
                fontFeatures: cvTabular,
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

/// A finite ledger panel. For long lists use [CvLedgerTile] in a builder.
class CvLedger extends StatelessWidget {
  const CvLedger({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CheckViewColors.of(context).surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CvRadius.ledger),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(indent: CvSpace.gutter),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One segment of a ledger rendered by a lazy list builder.
class CvLedgerTile extends StatelessWidget {
  const CvLedgerTile({
    super.key,
    required this.child,
    required this.isFirst,
    required this.isLast,
  });

  final Widget child;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    const radius = Radius.circular(CvRadius.ledger);
    return Material(
      color: CheckViewColors.of(context).surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: isFirst ? radius : Radius.zero,
          bottom: isLast ? radius : Radius.zero,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child,
          if (!isLast) const Divider(indent: CvSpace.gutter),
        ],
      ),
    );
  }
}

class CvLedgerRow extends StatelessWidget {
  const CvLedgerRow({
    super.key,
    required this.title,
    this.subtitle,
    this.meta = const [],
    this.leading,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.busy = false,
    this.titleMaxLines = 2,
  });

  final String title;
  final String? subtitle;

  /// Separate meta facts; rendered as spaced items, never dot-joined.
  final List<Widget> meta;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final bool busy;
  final int titleMaxLines;

  @override
  Widget build(BuildContext context) {
    final c = CheckViewColors.of(context);
    final theme = Theme.of(context);
    final row = AnimatedContainer(
      duration: CvMotion.of(context, CvMotion.quick),
      curve: CvMotion.curve,
      color: selected ? c.accentSoft : Colors.transparent,
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsetsDirectional.fromSTEB(
        CvSpace.gutter,
        CvSpace.md,
        CvSpace.md,
        CvSpace.md,
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: CvSpace.md)],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: titleMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: CvSpace.md, runSpacing: 4, children: meta),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: CvSpace.sm),
            trailing!,
          ],
          if (busy)
            const Padding(
              padding: EdgeInsetsDirectional.only(start: CvSpace.sm),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (onTap != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: CvSpace.xs),
              child: Icon(Icons.chevron_right, size: 20, color: c.inkMuted),
            ),
        ],
      ),
    );
    return Semantics(
      selected: selected,
      child: onTap == null
          ? MergeSemantics(child: row)
          : InkWell(onTap: busy ? null : onTap, child: row),
    );
  }
}

/// Small muted fact used in ledger meta rows.
class CvMeta extends StatelessWidget {
  const CvMeta(this.text, {super.key, this.icon, this.color});

  final String text;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? CheckViewColors.of(context).inkMuted;
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: tint, fontFeatures: cvTabular);
    if (icon == null) return Text(text, style: style);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: tint),
        const SizedBox(width: 4),
        Flexible(child: Text(text, style: style)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tally — the current operational state as counts
// ---------------------------------------------------------------------------

class CvTallyItem {
  const CvTallyItem({required this.label, required this.count, this.tone});

  final String label;
  final int count;
  final CvTone? tone;
}

class CvTally extends StatelessWidget {
  const CvTally({super.key, required this.items});

  final List<CvTallyItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final c = CheckViewColors.of(context);
    return Material(
      color: c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CvRadius.ledger),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fit = math.max(1, (constraints.maxWidth / 112).floor());
          // Balance rows (4 items on a phone: 2 + 2, not 3 + 1).
          final rowCount = (items.length / fit).ceil();
          final columns = (items.length / rowCount).ceil();
          final rows = <List<CvTallyItem>>[
            for (var i = 0; i < items.length; i += columns)
              items.sublist(i, (i + columns).clamp(0, items.length)),
          ];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var r = 0; r < rows.length; r++) ...[
                if (r > 0) const Divider(),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < columns; i++) ...[
                        if (i > 0) Container(width: 1, color: c.hairline),
                        Expanded(
                          child: i < rows[r].length
                              ? _TallyCell(item: rows[r][i])
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TallyCell extends StatelessWidget {
  const _TallyCell({required this.item});

  final CvTallyItem item;

  @override
  Widget build(BuildContext context) {
    final c = CheckViewColors.of(context);
    final theme = Theme.of(context);
    final zero = item.count == 0;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CvSpace.gutter,
          vertical: CvSpace.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item.count}',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w400,
                color: zero ? c.inkMuted : c.ink,
                fontFeatures: cvTabular,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.tone != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: zero ? c.rule : cvToneColor(c, item.tone!),
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    item.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: c.inkMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty, error, loading
// ---------------------------------------------------------------------------

class CvEmptyState extends StatelessWidget {
  const CvEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = CheckViewColors.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CvSpace.xl,
        vertical: CvSpace.xxl,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    border: Border.all(color: c.rule),
                    borderRadius: BorderRadius.circular(CvRadius.ledger),
                  ),
                  child: Icon(icon, size: 26, color: c.inkMuted),
                ),
              ),
              const SizedBox(height: CvSpace.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              if (message != null) ...[
                const SizedBox(height: 6),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: c.inkMuted,
                  ),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: CvSpace.xl),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class CvErrorState extends StatelessWidget {
  const CvErrorState({
    super.key,
    required this.title,
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String title;
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return CvEmptyState(
      icon: Icons.cloud_off_outlined,
      title: title,
      message: message,
      action: OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh, size: 20),
        label: Text(retryLabel),
      ),
    );
  }
}

/// Static placeholder rows with the final layout's rhythm. No shimmer.
class CvSkeletonLedger extends StatelessWidget {
  const CvSkeletonLedger({super.key, this.rows = 5});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final c = CheckViewColors.of(context);
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: c.raised,
          borderRadius: BorderRadius.circular(CvRadius.mark),
        ),
      ),
    );
    return ExcludeSemantics(
      child: CvLedger(
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.all(CvSpace.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(i.isEven ? 0.42 : 0.56, 13),
                  const SizedBox(height: 10),
                  bar(i.isEven ? 0.68 : 0.34, 10),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Banners and action bars
// ---------------------------------------------------------------------------

enum CvBannerTone { info, success, warning, error }

/// Inline message with a leading rule in the tone color.
class CvBanner extends StatelessWidget {
  const CvBanner({
    super.key,
    required this.message,
    this.tone = CvBannerTone.info,
    this.title,
    this.onDismiss,
    this.margin = const EdgeInsets.fromLTRB(
      CvSpace.gutter,
      CvSpace.md,
      CvSpace.gutter,
      0,
    ),
  });

  final String message;
  final String? title;
  final CvBannerTone tone;
  final VoidCallback? onDismiss;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final c = CheckViewColors.of(context);
    final theme = Theme.of(context);
    final (color, icon) = switch (tone) {
      CvBannerTone.info => (c.accent, Icons.info_outline),
      CvBannerTone.success => (c.approved, Icons.check_circle_outline),
      CvBannerTone.warning => (c.pending, Icons.error_outline),
      CvBannerTone.error => (c.rejected, Icons.report_gmailerrorred_outlined),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Padding(
        padding: margin,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            border: BorderDirectional(
              start: BorderSide(color: color, width: 3),
            ),
          ),
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              CvSpace.md,
              CvSpace.md,
              onDismiss == null ? CvSpace.md : CvSpace.xs,
              CvSpace.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: CvSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null)
                        Text(title!, style: theme.textTheme.titleSmall),
                      Text(
                        message,
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    onPressed: onDismiss,
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    icon: Icon(Icons.close, size: 18, color: c.inkMuted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CvAction {
  const CvAction({
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Filled; otherwise outlined.
  final bool primary;
}

/// Sticky decision bar. Buttons share the width when every label fits on
/// one line; otherwise they stack full-width so no decision is truncated.
class CvActionBar extends StatelessWidget {
  const CvActionBar({super.key, required this.actions});

  final List<CvAction> actions;

  static const _gap = CvSpace.sm;
  static const _buttonPadding = 20.0 * 2 + 8;

  bool _fitsInRow(BuildContext context, double maxWidth) {
    final style = Theme.of(context).textTheme.labelLarge;
    final share = (maxWidth - _gap * (actions.length - 1)) / actions.length;
    for (final action in actions) {
      final painter = TextPainter(
        text: TextSpan(text: action.label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final needed = painter.width + _buttonPadding;
      painter.dispose();
      if (needed > share) return false;
    }
    return true;
  }

  Widget _button(CvAction action) {
    final label = Text(action.label, textAlign: TextAlign.center);
    return action.primary
        ? FilledButton(onPressed: action.onPressed, child: label)
        : OutlinedButton(onPressed: action.onPressed, child: label);
  }

  @override
  Widget build(BuildContext context) {
    final c = CheckViewColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            CvSpace.gutter,
            10,
            CvSpace.gutter,
            10,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (_fitsInRow(context, constraints.maxWidth)) {
                return Row(
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: _gap),
                      Expanded(child: _button(actions[i])),
                    ],
                  ],
                );
              }
              // Stacked: the primary decision sits last, nearest the thumb.
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(height: _gap),
                    _button(actions[i]),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Choices: strips (inline) and sheets (modal)
// ---------------------------------------------------------------------------

class CvChoice<T> {
  const CvChoice({
    required this.value,
    required this.label,
    this.description,
    this.icon,
  });

  final T value;
  final String label;
  final String? description;
  final IconData? icon;
}

/// Inline mutually exclusive choice. Plain ink wells (not SegmentedButton) so
/// theme changes triggered here never rebuild a live M3 state machine.
class CvChoiceStrip<T> extends StatelessWidget {
  const CvChoiceStrip({
    super.key,
    required this.choices,
    required this.selected,
    required this.onSelected,
  });

  final List<CvChoice<T>> choices;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = CheckViewColors.of(context);
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: c.rule),
        borderRadius: BorderRadius.circular(CvRadius.control),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(CvRadius.control - 1),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < choices.length; i++) ...[
                if (i > 0) Container(width: 1, color: c.rule),
                Expanded(
                  child: _ChoiceStripCell(
                    choice: choices[i],
                    selected: choices[i].value == selected,
                    onTap: () => onSelected(choices[i].value),
                    theme: theme,
                    colors: c,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceStripCell<T> extends StatelessWidget {
  const _ChoiceStripCell({
    required this.choice,
    required this.selected,
    required this.onTap,
    required this.theme,
    required this.colors,
  });

  final CvChoice<T> choice;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;
  final CheckViewColors colors;

  @override
  Widget build(BuildContext context) {
    final tint = selected ? colors.ink : colors.inkMuted;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      child: Material(
        color: selected ? colors.accentSoft : colors.surface,
        child: InkWell(
          onTap: selected ? null : onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.all(CvSpace.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (choice.icon != null) ...[
                    Icon(choice.icon, size: 18, color: tint),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      choice.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: tint,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
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

/// Modal list of options with a title. Returns the chosen value.
Future<T?> showCvChoiceSheet<T>({
  required BuildContext context,
  required String title,
  required List<CvChoice<T>> choices,
  T? selected,
  String? message,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: CvSpace.sm),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CvSheetHeader(title: title, message: message),
            const Divider(),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: CvSpace.lg),
                itemCount: choices.length,
                separatorBuilder: (_, _) =>
                    const Divider(indent: CvSpace.xl, endIndent: CvSpace.xl),
                itemBuilder: (context, index) => CvChoiceRow(
                  choice: choices[index],
                  selected: choices[index].value == selected,
                  onTap: () =>
                      Navigator.pop(sheetContext, choices[index].value),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class CvChoiceRow<T> extends StatelessWidget {
  const CvChoiceRow({
    super.key,
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final CvChoice<T> choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = CheckViewColors.of(context);
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CvSpace.xl,
              vertical: CvSpace.md,
            ),
            child: Row(
              children: [
                if (choice.icon != null) ...[
                  Icon(choice.icon, size: 22, color: c.inkMuted),
                  const SizedBox(width: CvSpace.lg),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        choice.label,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      if (choice.description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          choice.description!,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: CvSpace.md),
                  Icon(Icons.check, size: 20, color: c.accent),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CvSheetHeader extends StatelessWidget {
  const CvSheetHeader({super.key, required this.title, this.message});

  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(CvSpace.xl, 0, CvSpace.xl, CvSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleLarge),
          ),
          if (message != null) ...[
            const SizedBox(height: 4),
            Text(message!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
