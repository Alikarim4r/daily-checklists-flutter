# Daily Checklists ↔ Supabase

## المشروع المخصص

- المستودع: `daily-checklists-flutter`
- Supabase project ref: `xhdpyiklhouqwrtdwztn`
- الهجرات المحلية: `supabase/migrations/001` … `026`
- الأسرار المحلية: `.env.local` فقط، وهي مستثناة من Git

لا يعني وجود `supabase/.temp/project-ref` أن جلسة CLI موثقة أو أن الهجرات دُفعت. نفّذ دائماً:

```bash
npx supabase login
npx supabase link --project-ref xhdpyiklhouqwrtdwztn
npx supabase migration list --linked
npx supabase db push --linked --dry-run
```

راجع القائمة والنسخة الاحتياطية، ثم طبق:

```bash
npx supabase db push --linked
npx supabase migration list --linked
npx supabase db lint --linked --fail-on error
```

لا تنفذ `supabase db reset --linked` على الإنتاج؛ فهو إجراء هدّام.

## ترتيب النشر الإلزامي

1. خذ نسخة احتياطية قابلة للاستعادة وتأكد من المشروع المرتبط.
2. طبّق الهجرات بالترتيب حتى `026`.
3. تحقق من إدراج UUID المالك في `platform_owners`.
4. نفّذ اختبار قبول بحساب فني ومدير وعارض في مؤسسة تجريبية.
5. انشر تطبيقات Flutter الجديدة بعد نجاح التحقق، لأن `020` يسحب صلاحيات DML المباشرة ويعتمد RPCs.

## تهيئة مالك المنصة مرة واحدة

أنشئ مستخدم Authentication موثوقاً ثم نفّذ من SQL Editor أو قناة `service_role` موثوقة، مع استبدال البريد. البريد هنا جسر تهيئة فقط؛ التحقق التشغيلي اللاحق يتم بالـUUID.

```sql
begin;

insert into public.platform_owners (user_id)
select id
from auth.users
where lower(email) = lower('owner@example.com')
on conflict (user_id) do nothing;

update public.profiles profile
set
  role = 'super_admin',
  is_active = true,
  approval_status = 'approved',
  home_organization_id = null,
  updated_at = now()
from public.platform_owners owner_row
where owner_row.user_id = profile.id;

commit;
```

لا تمنح `anon` أو `authenticated` صلاحية مباشرة على `platform_owners`. إدارة العضوية تتم فقط عبر قناة إدارية موثوقة.

## اختبارات القبول بعد الهجرة

- المستخدم يستطيع تحديث `full_name` فقط من ملفه؛ تغيير `role` أو `approval_status` أو `email` مرفوض.
- مدير مؤسسة لا يرى أو يعدّل مواقع مؤسسة أخرى.
- العارض يرى الفحوص المعتمدة فقط؛ الفني يرى نطاق الكتابة المعين له.
- إرسال مسودة ناقصة أو بلا توقيع صالح يفشل من الخادم.
- تبديل `default_answer` من payload لا يغير بيانات الكتالوج الثابتة.
- تعديل متزامن بإصدار قديم يعيد تعارضاً ولا يكتب فوق عمل مستخدم آخر.
- مزامنة المسودة المحلية مرتين لا تنشئ فحصين.
- الاعتماد والحذف والتصحيح يعمل كل منها داخل نطاق الموقع فقط.

## متغيرات التشغيل

```dotenv
SUPABASE_URL=https://PROJECT_REF.supabase.co
SUPABASE_ANON_KEY=PUBLIC_ANON_KEY
APP_ENV=staging
DEMO_LOGIN=false
```

لا تضع `service_role` أو كلمة مرور قاعدة البيانات داخل Flutter أو ملفات الويب.
