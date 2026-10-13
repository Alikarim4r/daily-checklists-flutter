import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P2 global asset register', () {
    test('asset keeps organization, physical hierarchy and criticality', () {
      final row = FmAsset.fromJson({
        'id': 'asset-1',
        'organization_id': 'org-a',
        'asset_code': 'CH-02',
        'name_en': 'Cooling Chiller',
        'name_ar': 'المبرد',
        'asset_type': 'hvac',
        'status': 'operational',
        'criticality': 'critical',
        'site_id': 'hq',
        'building_id': 'b1',
        'floor_id': 'gf',
        'area_id': 'plant',
      });
      expect(row.code, 'CH-02');
      expect(row.nameFor('ar'), 'المبرد');
      expect(row.nameFor('en'), 'Cooling Chiller');
      expect(row.siteId, 'hq');
      expect(row.buildingId, 'b1');
      expect(row.floorId, 'gf');
      expect(row.areaId, 'plant');
      expect(row.criticality, 'critical');
    });

    test('plan preserves calendar due dates, cadence and IANA timezone', () {
      final plan = FmPpmPlan.fromJson({
        'id': 'plan-1',
        'organization_id': 'org-a',
        'asset_id': 'asset-1',
        'title_en': 'Monthly PPM',
        'title_ar': 'صيانة شهرية',
        'frequency': 'monthly',
        'interval_count': 1,
        'anchor_date': '2026-01-31',
        'next_due_on': '2026-02-28',
        'timezone_id': 'Asia/Qatar',
        'is_active': true,
      });
      expect(plan.timezone, 'Asia/Qatar');
      expect(plan.anchorDate.day, 31);
      expect(plan.nextDueOn.day, 28);
      expect(plan.titleFor('ar'), 'صيانة شهرية');
      expect(plan.isActive, isTrue);
    });

    test('work order preserves readings and submitted inspection linkage', () {
      final job = FmPpmJob.fromJson({
        'id': 'job-1',
        'organization_id': 'org-a',
        'asset_id': 'asset-1',
        'plan_id': 'plan-1',
        'due_on': '2026-10-05',
        'status': 'completed',
        'inspection_id': 'inspection-1',
        'execution_notes': 'Tested unit',
        'readings': {'chw_c': 6.5},
        'completed_at': '2026-10-06T12:30:00Z',
      });
      expect(job.closed, isTrue);
      expect(job.overdue, isFalse);
      expect(job.readings['chw_c'], 6.5);
      expect(job.inspectionId, 'inspection-1');
      expect(job.completedAt!.isUtc, isTrue);
    });

    test('PPM evidence audit retains actor, timestamp and action', () {
      final event = FmPpmEvent.fromJson({
        'id': 'event-1',
        'job_id': 'job-1',
        'action': 'completed',
        'actor_id': 'user-a',
        'notes': 'Replaced filter',
        'recorded_at': '2026-10-06T13:00:00Z',
      });
      expect(event.action, 'completed');
      expect(event.actorId, 'user-a');
      expect(event.recordedAt.isUtc, isTrue);
    });
  });
}
