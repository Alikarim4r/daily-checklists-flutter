import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('transport failures are eligible for offline queue fallback', () {
    expect(
      ChecklistConnectivity.isTransportFailure(
        Exception('ClientException: Failed host lookup: api.example.com'),
      ),
      isTrue,
    );
    expect(
      ChecklistConnectivity.isTransportFailure(
        Exception('TimeoutException after 0:00:05.000000'),
      ),
      isTrue,
    );
  });

  test('server validation errors are not mislabeled as offline', () {
    expect(
      ChecklistConnectivity.isTransportFailure(
        Exception('PostgrestException: inspection version conflict (409)'),
      ),
      isFalse,
    );
    expect(
      ChecklistConnectivity.isTransportFailure(
        Exception('PostgrestException: not allowed to submit (403)'),
      ),
      isFalse,
    );
  });

  test('backend reachability uses the authoritative probe', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
    );
    expect(
      await ChecklistConnectivity.canReachBackend(client, probe: () async {}),
      isTrue,
    );
    expect(
      await ChecklistConnectivity.canReachBackend(
        client,
        probe: () async => throw Exception('Failed host lookup'),
      ),
      isFalse,
    );
    expect(
      await ChecklistConnectivity.canReachBackend(
        client,
        probe: () async => throw Exception('permission denied (403)'),
      ),
      isTrue,
    );
  });

  test('correctable submit validation stays as a server draft', () {
    expect(
      ChecklistSubmissionValidation.requiresDraftCorrection(
        Exception('all checklist items must be answered; missing: 3, 6'),
      ),
      isTrue,
    );
    expect(
      ChecklistSubmissionValidation.requiresDraftCorrection(
        Exception('not allowed to submit this inspection'),
      ),
      isFalse,
    );
    expect(
      ChecklistSubmissionValidation.messageFor(
        Exception('all checklist items must be answered; missing: 3, 6'),
        'en',
      ),
      'Answer every item before submitting; missing items: 3, 6.',
    );
  });
}
