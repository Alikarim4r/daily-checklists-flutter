/// Draft examples only: NOT OEM-certified maintenance instructions.
class FmPpmStarterRecipe {
  const FmPpmStarterRecipe({
    required this.code,
    required this.titleEn,
    required this.titleAr,
    required this.frequency,
    required this.instructions,
  });
  final String code, titleEn, titleAr, frequency, instructions;
}

const fmPpmStarterRecipes = <FmPpmStarterRecipe>[
  FmPpmStarterRecipe(
    code: 'chiller_monthly',
    titleEn: 'Chiller operational PPM',
    titleAr: 'الصيانة الوقائية التشغيلية للمبرد',
    frequency: 'monthly',
    instructions:
        'Review OEM maintenance and site work permit before work. '
        'Record chilled water supply/return temperatures and operating pressures; '
        'check alarms, accessible visual leaks, abnormal vibration and logs. '
        'Escalate unsafe conditions. This draft is not an OEM service procedure.',
  ),
  FmPpmStarterRecipe(
    code: 'cooling_tower_monthly',
    titleEn: 'Cooling Tower condition check',
    titleAr: 'فحص حالة برج التبريد',
    frequency: 'monthly',
    instructions:
        'Review site water safety plan and required access permits. '
        'Record available temperatures and water quality log references. '
        'Inspect accessible exterior fan/motor conditions, leaks, basin and distribution. '
        'Escalate microbiological risk; do not perform confined-space or energized work '
        'without specialist method statements and authorization.',
  ),
  FmPpmStarterRecipe(
    code: 'pump_monthly',
    titleEn: 'Pump condition monitoring',
    titleAr: 'متابعة حالة المضخات',
    frequency: 'monthly',
    instructions:
        'Check manufacturer guidance and isolation requirements. '
        'Record suction/discharge pressures, running status, visible leaks, '
        'motor current if safely available, vibration and unusual noises. '
        'Flag deviations for competent maintenance personnel.',
  ),
  FmPpmStarterRecipe(
    code: 'electrical_monthly',
    titleEn: 'Electrical panel external observation',
    titleAr: 'فحص ظاهري للوحة الكهربائية',
    frequency: 'monthly',
    instructions:
        'External visual check only, without opening energized enclosures. '
        'Check signage, physical access, environmental conditions, warning indicators '
        'and maintenance records. Any internal testing requires qualified personnel '
        'and approved isolation procedures.',
  ),
  FmPpmStarterRecipe(
    code: 'irrigation_weekly',
    titleEn: 'Irrigation network review',
    titleAr: 'مراجعة شبكة الري',
    frequency: 'weekly',
    instructions:
        'Inspect controller schedule, accessible valve boxes, '
        'sprinkler/nozzle operation, visible leaks and soil moisture distribution. '
        'Record faults and water consumption deviations.',
  ),
  FmPpmStarterRecipe(
    code: 'washrooms_daily',
    titleEn: 'Washroom hygiene & condition',
    titleAr: 'النظافة والحالة العامة لدورات المياه',
    frequency: 'daily',
    instructions:
        'Review soap and consumable supplies, accessible fixtures, '
        'visible leakage, drainage, damaged surfaces and slip hazards. '
        'Document issues requiring plumbing, civil or electrical corrective action.',
  ),
  FmPpmStarterRecipe(
    code: 'fire_safety_weekly',
    titleEn: 'Fire escape visual inspection',
    titleAr: 'الفحص الظاهري لمسارات الإخلاء',
    frequency: 'weekly',
    instructions:
        'Check that designated routes, exits and signs are unobstructed. '
        'Log damaged or missing equipment for competent personnel. '
        'Do not substitute this inspection for legally required specialized testing.',
  ),
];
