import '../data/buildings.dart';
import '../data/checklist_lists.dart';

class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.defaultAnswer,
    required this.texts,
    this.isCustom = false,
    this.customIndex,
  });

  final int id;
  final String defaultAnswer;
  final Map<String, String> texts;
  final bool isCustom;
  final int? customIndex;

  String textFor(String language) {
    return texts[language] ?? texts['en'] ?? texts['ar'] ?? '#$id';
  }

  static String listKeyForBuilding(String buildingId) {
    final type = kBuildingsConfig[buildingId]?['type'] ?? 'DEFAULT';
    if (kChecklistLists.containsKey(type)) return type;
    return 'DEFAULT';
  }

  static List<ChecklistItem> forBuilding(
    String buildingId, {
    String? checklistType,
    List<Map<String, dynamic>> customItems = const [],
    Map<String, String> customItemTexts = const {},
  }) {
    final key = (checklistType != null &&
            kChecklistLists.containsKey(checklistType))
        ? checklistType
        : listKeyForBuilding(buildingId);
    final base = (kChecklistLists[key] ?? kChecklistLists['DEFAULT']!)
        .map((raw) {
          final texts = <String, String>{};
          for (final lang in const [
            'en',
            'ar',
            'bn',
            'hi',
            'ml',
            'ta',
            'tl',
          ]) {
            final v = raw[lang];
            if (v is String && v.isNotEmpty) texts[lang] = v;
          }
          return ChecklistItem(
            id: (raw['id'] as num?)?.toInt() ?? 0,
            defaultAnswer: '${raw['default'] ?? 'Y'}',
            texts: texts,
          );
        })
        .toList();

    final customs = [...customItems]
      ..sort((a, b) => ((a['index'] as num?) ?? 0)
          .compareTo((b['index'] as num?) ?? 0));

    for (final c in customs) {
      final index = (c['index'] as num?)?.toInt() ?? 0;
      final id = (c['id'] as num?)?.toInt() ?? (1000 + index);
      final text = customItemTexts['$id'] ??
          customItemTexts[id.toString()] ??
          c['text']?.toString() ??
          c['en']?.toString() ??
          'Custom item';
      base.add(
        ChecklistItem(
          id: id,
          defaultAnswer: '${c['default'] ?? 'Y'}',
          texts: {
            'en': text,
            'ar': text,
          },
          isCustom: true,
          customIndex: index,
        ),
      );
    }
    return base;
  }
}

bool isProblemResponse({
  required ChecklistItem item,
  required String? response,
}) {
  if (response == null || response == 'NA') return false;
  if (item.defaultAnswer == 'NA') return false;
  if (item.defaultAnswer == 'Y') return response == 'N';
  if (item.defaultAnswer == 'N') return response == 'Y';
  return false;
}

bool isIdealResponse({
  required ChecklistItem item,
  required String? response,
}) {
  if (response == null || response == 'NA') return false;
  if (item.defaultAnswer == 'NA') return false;
  return response == item.defaultAnswer;
}
