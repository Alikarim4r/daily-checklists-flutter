# Daily Checklists ↔ Supabase (مستقل عن منصة العدادات)

## فصل المشاريع
- **هذا المستودع فقط:** `daily-checklists-flutter`
- **قاعدة البيانات:** مشروع Supabase **مستقل** باسم `daily-checklists`
- **Project ref:** `xhdpyiklhouqwrtdwztn`
- **Dashboard:** https://supabase.com/dashboard/project/xhdpyiklhouqwrtdwztn
- Migrations هنا: `supabase/migrations/001` … `005`
- لا تستخدم URL/مفاتيح مشروع `smart-meters-platform`

## إعداد (تم على هذا الجهاز)
1. المشروع مربوط عبر `npx supabase link --project-ref xhdpyiklhouqwrtdwztn`
2. الهجرات مدفوعة: `npx supabase db push`
3. الأسرار في `.env.local` (غير مُتتبَّع في git)

## مستخدم إداري
أنشئ مستخدمًا من Authentication ثم حدّثه:

```sql
update profiles
set role = 'super_admin', is_active = true, approval_status = 'approved'
where email = 'you@example.com';

insert into user_site_access (user_id, site_id, role, can_read, can_write, can_manage)
select p.id, s.id, 'super_admin', true, true, true
from profiles p cross join sites s
where p.email = 'you@example.com'
on conflict do nothing;
```

## تشغيل التطبيقات
```bash
./scripts/run_staging_app.sh entry
./scripts/run_staging_app.sh viewer
./scripts/run_staging_app.sh admin
```

macOS (تثبيت في `~/Applications`):
```bash
./scripts/build_macos_signed.sh checklist_entry InspectionEntry com.moehe.checklists.entry
./scripts/build_macos_signed.sh checklist_viewer InspectionViewer com.moehe.checklists.viewer
./scripts/build_macos_signed.sh checklist_admin InspectionAdmin com.moehe.checklists.admin
```
