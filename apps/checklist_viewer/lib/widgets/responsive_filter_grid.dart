import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/viewer_filter_distribution.dart';

/// Equal-width fields. No off-screen horizontal scroll: on a narrow viewport
/// remaining fields wrap into new rows; each row uses every available pixel.
/// Completion is passed as the final field and remains adjacent to other fields.
class ResponsiveFilterGrid extends StatelessWidget {
  const ResponsiveFilterGrid({super.key, required this.fields});
  final List<Widget> fields;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const margin = 8.0;
      const gap = 8.0;
      const verticalGap = 6.0;
      final columns = ViewerFilterDistribution.columnsFor(
        constraints.maxWidth,
        fields.length,
        margin: margin,
        gap: gap,
      );
      final rows = <Widget>[];
      if (columns > 0) {
        for (var start = 0; start < fields.length; start += columns) {
          final end = math.min(fields.length, start + columns);
          final countInRow = end - start;
          final fieldWidth = ViewerFilterDistribution.fieldWidth(
            constraints.maxWidth,
            countInRow,
            margin: margin,
            gap: gap,
          );
          rows.add(
            Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                for (var i = start; i < end; i++) ...[
                  if (i != start) const SizedBox(width: gap),
                  SizedBox(width: fieldWidth, child: fields[i]),
                ],
              ],
            ),
          );
        }
      }
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: margin, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i != 0) const SizedBox(height: verticalGap),
                rows[i],
              ],
            ],
          ),
        ),
      );
    },
  );
}
