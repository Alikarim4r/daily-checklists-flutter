# Daily Checklists Flutter

منظومة فحص مرافق يومية ثنائية اللغة لوزارة التربية والتعليم والتعليم العالي، مبنية من ثلاثة تطبيقات Flutter وحزمة مشتركة وقاعدة Supabase مستقلة.

> هذا المستودع مستقل تماماً عن `smart-meters-platform`. لا تشارك معه عنوان Supabase أو المفاتيح أو الهجرات.

## التطبيقات

| التطبيق | المسار | الاستخدام |
|---|---|---|
| Entry | `apps/checklist_entry` | إدخال الفني، الصور المائية، التوقيع، والعمل دون اتصال |
| Viewer | `apps/checklist_viewer` | العرض والمراجعة والاعتماد والتقارير ولوحة التشغيل |
| Admin | `apps/checklist_admin` | المؤسسات والمواقع والمستخدمون والصلاحيات والكتالوج والسياسات |

الحزمة المشتركة في `packages/checklist_shared`، والهجرات المتسلسلة `001` إلى `033` في `supabase/migrations`.

## ضمانات الإصدار

- مالك المنصة محدد بعضوية UUID محمية، وليس ببريد قابل للتعديل.
- صلاحيات المستخدم والمؤسسة والموقع مفروضة في PostgreSQL/RLS وRPCs، لا في الواجهة فقط.
- دورة الفحص ذرّية مع تحقق خادمي، قفل تفاؤلي `version`، وسجل تصحيحات.
- قائمة العمل دون اتصال مشفرة، والمسودات المحلية متزامنة دون تكرار عبر `client_reference`.
- جلسة Supabase هي مصدر المصادقة؛ لا تُخزن كلمات مرور الحساب محلياً.
- إصدارات Android لا تستخدم مفتاح debug، وإصدارات macOS قابلة للتوقيع والتوثيق، ووضع Demo معطل افتراضياً.
- بوابة CI تفحص التنسيق والتحليل والاختبارات وبناء الويب وصحة SQL والثوابت الأمنية.

## الإعداد والتشغيل

```bash
cp .env.example .env.local
# ضع SUPABASE_URL وSUPABASE_ANON_KEY للمشروع المخصص فقط

./scripts/run_staging_app.sh entry
./scripts/run_staging_app.sh viewer
./scripts/run_staging_app.sh admin
```

## بوابة الجودة

يتطلب فحص SQL حزمة Python `pglast==8.4`.

```bash
python3 -m pip install -r requirements-dev.txt
./scripts/check_quality.sh
```

عند توفر PostgreSQL محليًا، يطبّق الفحص جميع الهجرات في قاعدة مؤقتة ويشغّل
دورة إنشاء/حفظ/إرسال/اعتماد كاملة. في CI يكون هذا الاختبار إلزاميًا.

## نشر قاعدة البيانات

لا تفترض أن الهجرات المحلية مطبقة على المشروع البعيد. افحص التاريخ واعرض التغييرات أولاً، ثم ادفعها من جلسة Supabase CLI موثقة:

```bash
npx supabase login
npx supabase link --project-ref xhdpyiklhouqwrtdwztn
npx supabase migration list --linked
npx supabase db push --linked --dry-run
npx supabase db push --linked
```

انشر جميع الهجرات حتى `033` قبل استخدام الإصدار 1.3.1؛ تضيف `022` ثيمات القوائم الهرمية، و`023` قوائم المساجد الاحترافية وترجماتها السبع، وتصحح `025`–`026` قائمة `B7-M` إلى 22 بنداً وربطها، ثم تضيف `027`–`031` التدقيق والإشعارات والإجراءات التصحيحية والوصول المؤقت، وتحمي `032`–`033` الصور والتوقيع التاريخي من الاستبدال أو الحذف وتوفر تنظيفاً آمناً لمسودات كاملة. لا تستخدم `db reset --linked` مع بيانات حقيقية.

## بناء الإصدار

```bash
# Android: يتطلب android/key.properties أو ANDROID_KEYSTORE_*
./scripts/build_android_release.sh checklist_entry

# iOS: يتطلب توقيع Apple، ويمكن تمرير IOS_EXPORT_OPTIONS_PLIST
./scripts/build_ios_release.sh checklist_entry

# macOS: يتطلب Developer ID؛ APPLE_NOTARY_PROFILE يفعّل notarization
./scripts/build_macos_signed.sh \
  checklist_entry InspectionEntry com.moehe.checklists.checklistEntry

# بوابة الويب والتطبيقات الثلاثة
./scripts/build_web_portal.sh
```

كرر أوامر المنصات مع `checklist_viewer` و`checklist_admin`. تحفظ المخرجات الموقعة في `dist/` ولا تدخل Git.

تفاصيل قاعدة البيانات في `docs/SUPABASE_SETUP.md` وخطوات الإطلاق في `docs/RELEASE_CHECKLIST.md`.
