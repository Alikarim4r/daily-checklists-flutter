import 'dart:convert';
import 'dart:math' as math;

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('inspection listing reads beyond the Data API row cap', () async {
    final offsets = <int>[];
    final rows = List.generate(
      1103,
      (i) => {
        'id': 'inspection-$i',
        'site_id': 'site-1',
        'building_code': 'B7-M',
        'inspection_date': '2026-09-12',
        'version': 1,
      },
    );
    final client = SupabaseClient(
      'https://example.test',
      'test-key',
      httpClient: MockClient((request) async {
        Object response;
        if (request.url.path.endsWith('/checklist_inspections')) {
          final offset = int.parse(
            request.url.queryParameters['offset'] ?? '0',
          );
          final limit = int.parse(
            request.url.queryParameters['limit'] ?? '1000',
          );
          offsets.add(offset);
          response = rows.sublist(
            offset,
            math.min(offset + limit, rows.length),
          );
        } else if (request.url.path.endsWith(
          '/resolve_checklist_form_themes',
        )) {
          response = [
            {'site_id': 'site-1', 'theme_key': 'classic_gold'},
          ];
        } else {
          fail('Unexpected query ${request.url.path}');
        }
        return http.Response(
          jsonEncode(response),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);

    final inspections = await InspectionRepository(client).listInspections();
    expect(inspections.length, 1103);
    expect(inspections.map((item) => item.id).toSet().length, 1103);
    expect(offsets, [0, 500, 1000]);
  });

  test(
    'batched items include all 22 rows for every inspection beyond 1000 items',
    () async {
      final rows = [
        for (var inspection = 0; inspection < 60; inspection++)
          for (var index = 1; index <= 22; index++)
            {
              'id': '$inspection-$index',
              'inspection_id': 'i-$inspection',
              'item_index': index,
              'description': 'Item $index',
            },
      ];
      var requests = 0;
      final client = SupabaseClient(
        'https://example.test',
        'test-key',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/checklist_inspection_items');
          requests++;
          final offset = int.parse(
            request.url.queryParameters['offset'] ?? '0',
          );
          final limit = int.parse(
            request.url.queryParameters['limit'] ?? '1000',
          );
          return http.Response(
            jsonEncode(
              rows.sublist(offset, math.min(offset + limit, rows.length)),
            ),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);

      final grouped = await InspectionRepository(client)
          .listItemsForInspections(
            inspectionIds: List.generate(60, (i) => 'i-$i'),
          );
      expect(grouped.length, 60);
      expect(grouped.values.every((items) => items.length == 22), isTrue);
      expect(requests, 3);
    },
  );
}
