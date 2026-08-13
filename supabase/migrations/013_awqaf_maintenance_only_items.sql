-- =============================================================================
-- Awqaf templates: maintenance / faults only (no cleaning items)
-- Migration: 013_awqaf_maintenance_only_items.sql
-- =============================================================================

-- Remove previous mixed items (cleaning + maintenance)
delete from public.checklist_template_items
where template_id in (
  select id from public.checklist_templates
  where code in ('AWQAF_MEN_PRAYER', 'AWQAF_WUDU', 'AWQAF_IMAM_HOUSE')
);

-- Men prayer hall — maintenance / faults
insert into public.checklist_template_items
  (template_id, item_index, default_answer, description_en, description_ar, sort_order, is_active, overdue_after_days)
select t.id, v.item_index, v.default_answer, v.description_en, v.description_ar, v.sort_order, true, v.overdue_days
from public.checklist_templates t
cross join (values
  (1, 'Y', 'Are all lights functioning normally with no flickering or busted lamps?', 'هل جميع الأضواء تعمل بشكل طبيعي دون وميض أو تلف؟', 1, 2),
  (2, 'Y', 'Are AC / ventilation units operating normally without faults?', 'هل وحدات التكييف والتهوية تعمل بشكل طبيعي دون أعطال؟', 2, 2),
  (3, 'Y', 'Are ceiling / wall fans operating normally?', 'هل مراوح السقف/الجدران تعمل بشكل طبيعي؟', 3, 3),
  (4, 'Y', 'Is the prayer clock / display operating correctly?', 'هل ساعة المصلى/العرض تعمل بشكل صحيح؟', 4, 3),
  (5, 'Y', 'Are speakers and audio system working without noise or cutouts?', 'هل مكبرات الصوت تعمل دون ضجيج أو انقطاع؟', 5, 2),
  (6, 'N', 'Are there any water leaks or damp spots on walls/ceiling?', 'هل يوجد تسرب مياه أو رطوبة على الجدران/السقف؟', 6, 1),
  (7, 'Y', 'Are doors and locks closing properly without damage?', 'هل الأبواب والأقفال تغلق بشكل سليم ودون تلفيات؟', 7, 3),
  (8, 'Y', 'Is emergency lighting working?', 'هل إضاءة الطوارئ تعمل؟', 8, 2),
  (9, 'Y', 'Are exit signs / emergency indicators visible and working?', 'هل لوحات المخارج ومؤشرات الطوارئ واضحة وتعمل؟', 9, 2),
  (10, 'N', 'Is there any abnormal sound from equipment (AC, fans, speakers)?', 'هل يوجد أي صوت غير طبيعي من المعدات (تكييف، مراوح، سماعات)؟', 10, 2),
  (11, 'Y', 'Are electrical sockets and switches free from faults or burn marks?', 'هل المقابس والمفاتيح الكهربائية خالية من الأعطال أو علامات الاحتراق؟', 11, 2),
  (12, 'Y', 'Are Quran stands / shelves structurally undamaged and usable?', 'هل مساند ورفوف المصاحف سليمة هيكلياً وقابلة للاستخدام؟', 12, 5)
) as v(item_index, default_answer, description_en, description_ar, sort_order, overdue_days)
where t.code = 'AWQAF_MEN_PRAYER';

-- Washrooms & ablution — maintenance / plumbing / electrical
insert into public.checklist_template_items
  (template_id, item_index, default_answer, description_en, description_ar, sort_order, is_active, overdue_after_days)
select t.id, v.item_index, v.default_answer, v.description_en, v.description_ar, v.sort_order, true, v.overdue_days
from public.checklist_templates t
cross join (values
  (1, 'Y', 'Are ablution (wudu) taps working with adequate water flow?', 'هل حنفيات الوضوء تعمل بتدفق ماء مناسب؟', 1, 1),
  (2, 'Y', 'Are toilet flush systems operating normally?', 'هل أنظمة شطف دورات المياه تعمل بشكل طبيعي؟', 2, 1),
  (3, 'N', 'Is there any water leakage from taps, pipes, or tanks?', 'هل يوجد أي تسرب من الحنفيات أو المواسير أو الخزانات؟', 3, 1),
  (4, 'Y', 'Are drains free from blockage (not overflowing)?', 'هل المصارف خالية من الانسداد (لا يوجد فيضان)؟', 4, 1),
  (5, 'Y', 'Are washroom lights functioning normally?', 'هل أضواء دورات المياه تعمل بشكل طبيعي؟', 5, 2),
  (6, 'Y', 'Are exhaust fans operating normally?', 'هل مراوح الشفط تعمل بشكل طبيعي؟', 6, 2),
  (7, 'Y', 'Are hand dryers (if installed) functioning normally?', 'هل مجففات اليد (إن وُجدت) تعمل بشكل طبيعي؟', 7, 2),
  (8, 'Y', 'Is hot water available where required?', 'هل الماء الساخن متوفر حيث يُطلب؟', 8, 2),
  (9, 'Y', 'Are doors, partitions, and hardware undamaged and operable?', 'هل الأبواب والقواطع والتجهيزات غير تالفة وقابلة للتشغيل؟', 9, 3),
  (10, 'Y', 'Are disabled-access fixtures operable (grab bars, accessible taps/toilet)?', 'هل تجهيزات ذوي الإعاقة قابلة للتشغيل (مقابض، حنفيات/مرحاض مهيأ)؟', 10, 2),
  (11, 'N', 'Is there any abnormal noise from pumps or pipework?', 'هل يوجد ضجيج غير طبيعي من المضخات أو تمديدات المياه؟', 11, 2),
  (12, 'Y', 'Are water heaters / mixers (if installed) free from faults?', 'هل سخانات المياه/الخلاطات (إن وُجدت) خالية من الأعطال؟', 12, 2)
) as v(item_index, default_answer, description_en, description_ar, sort_order, overdue_days)
where t.code = 'AWQAF_WUDU';

-- Imam house — maintenance / faults
insert into public.checklist_template_items
  (template_id, item_index, default_answer, description_en, description_ar, sort_order, is_active, overdue_after_days)
select t.id, v.item_index, v.default_answer, v.description_en, v.description_ar, v.sort_order, true, v.overdue_days
from public.checklist_templates t
cross join (values
  (1, 'Y', 'Are AC units operating normally without faults?', 'هل وحدات التكييف تعمل بشكل طبيعي دون أعطال؟', 1, 2),
  (2, 'Y', 'Are electrical outlets and switches functioning normally?', 'هل المقابس والمفاتيح الكهربائية تعمل بشكل طبيعي؟', 2, 2),
  (3, 'Y', 'Are all lights functioning normally with no busted lamps?', 'هل جميع الأضواء تعمل بشكل طبيعي دون تلف؟', 3, 2),
  (4, 'Y', 'Is water supply operating normally (pressure / availability)?', 'هل إمداد المياه يعمل بشكل طبيعي (الضغط/التوفر)؟', 4, 2),
  (5, 'N', 'Is there any water leakage in kitchen or bathrooms?', 'هل يوجد أي تسرب مياه في المطبخ أو الحمامات؟', 5, 1),
  (6, 'Y', 'Are doors, locks, and windows secure and undamaged?', 'هل الأبواب والأقفال والنوافذ آمنة وغير تالفة؟', 6, 3),
  (7, 'Y', 'Are bathroom taps and flush systems operating normally?', 'هل حنفيات وشطف الحمامات تعمل بشكل طبيعي؟', 7, 2),
  (8, 'Y', 'Are smoke detectors / safety devices (if installed) functioning?', 'هل أجهزة كشف الدخان/السلامة (إن وُجدت) تعمل؟', 8, 3),
  (9, 'N', 'Is there any abnormal sound from equipment (AC, fridge, pumps)?', 'هل يوجد أي صوت غير طبيعي من المعدات (تكييف، ثلاجة، مضخات)؟', 9, 2),
  (10, 'N', 'Are there roof / ceiling leaks or visible structural moisture damage?', 'هل يوجد تسرب من السقف أو رطوبة هيكلية ظاهرة؟', 10, 2)
) as v(item_index, default_answer, description_en, description_ar, sort_order, overdue_days)
where t.code = 'AWQAF_IMAM_HOUSE';
