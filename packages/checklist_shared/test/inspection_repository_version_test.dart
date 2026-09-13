import 'dart:convert';

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('saveItems sends and adopts the authoritative server version', () async {
    late Map<String, dynamic> requestBody;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/rest/v1/rpc/save_checklist_inspection');
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          '9',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    final inspection = Inspection(
      id: '10000000-0000-4000-8000-000000000001',
      siteId: '20000000-0000-4000-8000-000000000001',
      buildingCode: 'B1',
      inspectionDate: DateTime(2026, 9, 12),
      version: 8,
      items: [InspectionItem(itemIndex: 1, description: 'Test item')],
    );

    await InspectionRepository(client).saveItems(inspection);

    expect(requestBody['p_expected_version'], 8);
    expect(inspection.version, 9);
    await client.dispose();
  });
}
