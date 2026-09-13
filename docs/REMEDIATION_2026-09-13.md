# تقرير الإصلاحات والتحقق — 13 سبتمبر 2026

المشروع: daily-checklists-flutter

الإصدار البرمجي المرشح: **1.3.5+12**

خط الأساس: `69450a4028ff5018d879e61923a24a134e14d7e6`

هذا التقرير يصف إصلاحات المصدر والتحقق المحلي، وليس إعلانًا بأن الموقع أو التطبيقات المثبتة أو قاعدة بيانات الإنتاج قد حُدّثت. تم الحفاظ على تعديلات المستخدم الموجودة في بدء العمل والمتعلقة بتهيئة صندوق المزامنة على الويب.

## 1. السبب الجذري لمشكلة المزامنة

كان الحفظ التلقائي يحتفظ بنسخة محلية عند إصدار خادمي معيّن، ثم تنجح مسارات حفظ أخرى في رفع الإصدار دون تسوية النسخة المحلية القديمة. إعادة تشغيل هذه النسخة كانت تسبب تعارضًا قد يبدو للمستخدم كفشل اتصال. الحذف غير المشروط بعد الحفظ لم يكن آمنًا، لأنه قد يحذف تعديلات أحدث.

وُجد أيضًا توليد معرّف باستخدام `nextInt(1 << 32)`؛ نتيجة الإزاحة في JavaScript تجعل الحد صفرًا، وهو سبب خطأ RangeError الظاهر في الويب. استُبدل بمعرّف عشوائي من 16 بايت وحدود آمنة للمتصفح.

## 2. الإصلاح وضمانات سلامة البيانات

- توحيد الحفظ الكامل في Entry عبر `_saveItemsAuthoritatively` مع `saveAndReconcile`.
- انتظار الحفظ التلقائي الجاري، ورفع المرفقات المعلقة، ثم حفظ اللقطة المحلية قبل طلب الحفظ الخادمي متى كان الصندوق متاحًا.
- حذف جيل اللقطة الذي غطاه الحفظ الناجح فقط. إذا ظهر جيل أحدث، لا يُحذف. وإذا تغيّرت مراجعة التحرير أثناء الحفظ، تُحفظ التعديلات الحالية بالإصدار الخادمي المعاد.
- عند فشل النقل تظل اللقطة قابلة للاستعادة. فشل الحفظ الخادمي لا يؤدي إلى تنظيف الصندوق.
- تطبيق المسار المشترك على الحفظ والإرسال وترحيل المشاكل وإرفاق الأدلة وإزالة الأدلة المعلقة.
- حفظ بقية الإجابات والملاحظات والتوقيع قبل RPC الإزالة الجزئية لصورة إصلاح محفوظة. عدم استعادة مرجع الصورة محليًا بعد التأكد من نجاح فصلها في الخادم.
- منع تداخل الحفظ/الإرسال/اختيار الصور/إزالة صورة الإصلاح مع التحرير والتنقل؛ والتحقق من حفظ آخر تعديل قبل مغادرة القائمة أو تغيير التاريخ.
- استعادة المسودات المحلية ومسودات الخادم الموجودة في الصندوق للموقع والتاريخ المناسبين، مع مراعاة صاحب اللقطة عندما يكون مسجلًا.
- إبقاء طلب الإرسال في الصندوق حتى نجاح الحفظ والإرسال معًا؛ وعدم تحويله إلى حفظ عادي بواسطة حفظ تلقائي لم يتضمن أي تعديل.
- الحفاظ على التوقيع المرسوم أثناء تصدير PNG، وإعادة أخذ لقطة عند وصول ضربات قلم أحدث.

لم تُغيَّر آلية القفل التفاؤلي في SQL: يبقى `p_expected_version` مطلوبًا، وتبقى التعارضات الحقيقية مرفوضة، ويُستخدم الإصدار الجديد الذي يعيده الخادم. لم يُعدَّل محلّل التعارضات المشترك؛ اختُبرت حالات التعارض والسجل النهائي واستئناف checkpoint كما هي.

## 3. إصلاحات مؤكدة أخرى

### الحسابات والصلاحيات

- نقل إنشاء المستخدم إلى Edge Function تستخدم واجهة Supabase Auth Admin الرسمية بدل إدخال مستخدم Auth عبر SQL.
- التحقق من JWT، والمالك بواسطة UUID ثابت، أو مدير مؤسسة نشط ومعتمد؛ وعدم الوثوق بدور/مؤسسة يرسلها العميل.
- إنشاء الحساب الجديد كمستخدم viewer معلق وغير نشط، وحصر مؤسسة الحساب بسلطة المنشئ؛ وإرجاع أخطاء JSON مع CORS.
- Migration 035 تضبط صلاحيات Data API الافتراضية والصريحة، وتحظر RPC إنشاء الحساب القديم عن العملاء، وتضيف فهارس للمفاتيح الأجنبية.
- اختبارات PostgreSQL فعلية تحت أدوار authenticated وanon تغطي العزل بين المؤسسات، وتعديل الاسم الآمن، ورفض تصعيد الدور، ورفض RPC القديم، وتشغيل RPC المسودة المسموح.

### التقارير العربية والمرفقات

- تضمين خطوط Noto العربية واللاتينية وترخيصها في التطبيق؛ التقارير لا تعتمد على تنزيل خط وقت الطباعة.
- إزالة الارتفاعات/حدود الأسطر التي تقص النصوص الطويلة، وتكرار عنوان الجدول في الصفحات التالية.
- تصحيح اتجاه القيم العربية في بيانات رأس التقرير، ومنها اسم المفتش.
- جعل الصور المضمنة هي الخيار الافتراضي في PDF. يبقى خيار الروابط متاحًا مع تنبيه صريح بأن الرابط صالح لسبعة أيام.
- فحص بصري لتقرير عربي تجريبي من 22 بندًا طويلًا على صفحتين؛ ظهرت البنود كاملة والعناوين مكررة دون قص في الملف التجريبي.

### اكتمال البيانات والأداء

- جلب السجلات على صفحات ثابتة الترتيب بدل التوقف عند حد الاستجابة الافتراضي.
- تجميع جلب البنود والسمات في دفعات بدل استعلام مستقل لكل سجل.
- اختبار يتجاوز 1000 سجل، وآخر يتحقق من 1320 بندًا موزعة على 60 فحصًا.

### بوابة التنزيل والإصدار

- توحيد إصدار التطبيقات الثلاثة وبيانات البوابة وكسر التخزين المؤقت على 1.3.5+12.
- إضافة فحص يمنع عدم تطابق بيانات الإصدار والروابط المخبأة.
- إعداد نشر Pages بعد نجاح Quality Gate، مع اشتراط حزم Android وmacOS الست المطابقة والموقّعة والتحقق منها قبل استبدال الموقع.
- النشر يفشل ويحافظ على الموقع السابق إذا كانت حزم التنزيل ناقصة أو قديمة أو غير مستوفية للتحقق.
- إزالة ثمانية ملفات تشغيل مؤقتة من `supabase/.temp` من التتبع وإضافتها للتجاهل. يمكن استعادتها من Git؛ لا تحتوي هذه الإزالة على بيانات فحص أو سجلات مستخدمين.

## 4. الاختبارات والأوامر

الأوامر من جذر المشروع ما لم يُذكر غير ذلك. النتائج التالية هي نتائج التشغيل النهائي الناجح؛ التشغيلات المرحلية كشفت امتلاء القرص وأخطاء في تهيئة بعض الاختبارات، وتم إصلاحها وإعادة التشغيل بنجاح. لم تبق نتيجة اختبار فاشلة في التحقق النهائي.

| الأمر | النتيجة |
| --- | --- |
| `CHECKLIST_SQL_PYTHON=/tmp/daily-checklists-quality-venv/bin/python CHECKLIST_REQUIRE_POSTGRES=1 scripts/check_quality.sh` | نجاح، exit 0 |
| تنسيق Dart داخل السكربت | 117 ملفًا؛ دون تغييرات تنسيق |
| `flutter analyze --no-pub` للمشاريع الأربعة | لا مشاكل |
| `flutter test --no-pub` للحزمة المشتركة | 68 اختبارًا ناجحًا |
| `flutter test --no-pub` لتطبيق Entry | 3 اختبارات ناجحة |
| `flutter test --no-pub` لتطبيق Viewer | اختبار واحد ناجح |
| `flutter test --no-pub` لتطبيق Admin | اختباران ناجحان |
| محلل migrations ضمن السكربت | 35 migration ناجحة |
| PostgreSQL ضمن السكربت | تطبيق 001–035 واختبارات workflow وRLS بنجاح |
| `python3 scripts/check_web_portal.py` | الصفحات الخمس والإصدار 1.3.5+12 متطابقة |
| `node --check web_portal/portal.js` | نجاح |
| `node --test scripts/test_admin_create_user.mjs` | 8 اختبارات ناجحة |
| `ruby -e 'require "yaml"; ARGV.each { |path| YAML.parse_file(path) }' .github/workflows/quality.yml .github/workflows/deploy-pages.yml` | الملفان صالحان نحويًا |
| `git diff --check` | دون أخطاء مسافات |

تشغيل مركّز مستقل من `packages/checklist_shared`:

```sh
flutter test --no-pub \
  test/offline_queue_generation_test.dart \
  test/offline_sync_checkpoint_test.dart \
  test/inspection_repository_version_test.dart \
  test/report_font_loader_test.dart --reporter expanded
```

النتيجة: **14 اختبارًا ناجحًا**. تشمل A–H المطلوبة: حذف اللقطة القديمة بعد نجاح الحفظ/تغيير الأدلة، حماية الجيل الأحدث، بقاء التعارض الحقيقي، حماية السجل النهائي، استئناف checkpoint، الاحتفاظ بالعمل عند فشل النقل، واعتماد الإصدار المعاد من الخادم.

تشغيل المتصفح من الحزمة المشتركة مع Chrome for Testing المحلي في `CHROME_EXECUTABLE`:

```sh
flutter test --no-pub --platform chrome \
  test/photo_pair_test.dart test/offline_queue_web_test.dart \
  --reporter expanded
```

النتيجة: **7 اختبارات ناجحة**، بما فيها إنشاء جيلين في الصندوق المشفر على المتصفح دون RangeError.

التحقق البصري:

```sh
CHECKLIST_PDF_TEST_OUTPUT=/tmp/checklist-arabic-regression.pdf \
  flutter test --no-pub test/report_font_loader_test.dart --reporter expanded
pdftoppm -scale-to 1400 -png -f 1 -l 2 \
  /tmp/checklist-arabic-regression.pdf /tmp/checklist-arabic-review
```

النتيجة: اختباران ناجحان، وفحص الصورتين الناتجتين يدويًا. الملف تجريبي وليس إعادة إصدار لتقرير المستخدم الأصلي.

بعد آخر تعديل لمنع تداخل إزالة صورة الإصلاح مع التنقل، أُعيد تنسيق ملف Entry وتحليله وتشغيل اختباراته الثلاثة بنجاح.

## 5. المراجعة الذاتية وحدود التسليم

تمت مراجعة فقد التعديلات المحلية، وإعادة تشغيل اللقطات القديمة، وسباقات الحفظ التلقائي، ودورة الصور، والقفل التفاؤلي، وأمان الإرسال والسجلات النهائية. أُجريت أيضًا مراجعة مستقلة مركزة لمسار نشر البوابة ولم تُكتشف عوائق فيه.

التحقق الآلي لا يغني عن smoke test في staging بحسابات فعلية وأجهزة حقيقية. لم يُنفَّذ في هذا التسليم:

- نشر Edge Function أو migration 035 على قاعدة بيانات الإنتاج.
- بناء وتوقيع وتوثيق حزم الإصدار الجديد أو تثبيتها على الأجهزة.
- تأكيد نشر Pages أو اكتمال Quality Gate البعيد؛ نتيجة الرفع وCI تُذكر في رسالة التسليم.

يجب تنسيق نشر الخلفية وتحديث Admin لأن migration 035 تمنع مسار إنشاء الحساب القديم. اتبع `SUPABASE_SETUP.md` و`WEB_DEPLOYMENT.md` و`RELEASE_CHECKLIST.md`. وجود رقم إصدار جديد في المصدر لا يعني أن تنزيلات الموقع أصبحت بهذا الإصدار.

## 6. جميع الملفات المتغيرة في هذا التسليم

المسارات نسبية إلى جذر المستودع؛ تشمل الإضافات والحذف وملف التقرير هذا:

- `.github/workflows/deploy-pages.yml`
- `.github/workflows/quality.yml`
- `.gitignore`
- `apps/checklist_admin/pubspec.yaml`
- `apps/checklist_entry/lib/main.dart`
- `apps/checklist_entry/pubspec.yaml`
- `apps/checklist_viewer/lib/main.dart`
- `apps/checklist_viewer/pubspec.yaml`
- `docs/RELEASE_CHECKLIST.md`
- `docs/REMEDIATION_2026-09-13.md`
- `docs/SUPABASE_SETUP.md`
- `docs/WEB_DEPLOYMENT.md`
- `packages/checklist_shared/assets/fonts/NotoNaskhArabic-Bold.ttf`
- `packages/checklist_shared/assets/fonts/NotoNaskhArabic-Regular.ttf`
- `packages/checklist_shared/assets/fonts/NotoSans-Bold.ttf`
- `packages/checklist_shared/assets/fonts/NotoSans-Regular.ttf`
- `packages/checklist_shared/assets/fonts/OFL.txt`
- `packages/checklist_shared/lib/checklist_shared.dart`
- `packages/checklist_shared/lib/src/offline/offline_inspection_queue.dart`
- `packages/checklist_shared/lib/src/reports/inspection_report_exporter.dart`
- `packages/checklist_shared/lib/src/reports/ops_report_exporter.dart`
- `packages/checklist_shared/lib/src/reports/report_font_loader.dart`
- `packages/checklist_shared/lib/src/repositories/auth_repository.dart`
- `packages/checklist_shared/lib/src/repositories/inspection_repository.dart`
- `packages/checklist_shared/pubspec.yaml`
- `packages/checklist_shared/test/inspection_pagination_test.dart`
- `packages/checklist_shared/test/inspection_repository_version_test.dart`
- `packages/checklist_shared/test/offline_queue_generation_test.dart`
- `packages/checklist_shared/test/offline_queue_web_test.dart`
- `packages/checklist_shared/test/report_font_loader_test.dart`
- `scripts/check_quality.sh`
- `scripts/check_web_portal.py`
- `scripts/test_admin_create_user.mjs`
- `scripts/test_migrations_postgres.sh`
- `supabase/.temp/gotrue-version`
- `supabase/.temp/linked-project.json`
- `supabase/.temp/pooler-url`
- `supabase/.temp/postgres-version`
- `supabase/.temp/project-ref`
- `supabase/.temp/rest-version`
- `supabase/.temp/storage-migration`
- `supabase/.temp/storage-version`
- `supabase/config.toml`
- `supabase/functions/admin-create-user/index.ts`
- `supabase/migrations/035_explicit_data_api_grants_and_indexes.sql`
- `supabase/tests/bootstrap.sql`
- `supabase/tests/rls_access_smoke.sql`
- `web_portal/apps.html`
- `web_portal/downloads.html`
- `web_portal/index.html`
- `web_portal/portal.js`
- `web_portal/privacy.html`
- `web_portal/support.html`

معرّف commit ونتيجة push متاحان في رسالة التسليم وسجل Git الذي يحتوي هذا التقرير.
