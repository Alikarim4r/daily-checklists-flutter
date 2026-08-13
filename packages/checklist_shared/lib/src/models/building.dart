import '../data/buildings.dart';

class BuildingConfig {
  const BuildingConfig({
    required this.id,
    required this.num,
    required this.ar,
    required this.en,
    required this.pin,
    required this.type,
  });

  final String id;
  final String num;
  final String ar;
  final String en;
  final String pin;
  final String type;

  String nameFor(String language) {
    if (language == 'ar') return ar;
    return en;
  }

  static BuildingConfig? byId(String id) {
    final raw = kBuildingsConfig[id];
    if (raw == null) return null;
    return BuildingConfig(
      id: id,
      num: raw['num'] ?? '',
      ar: raw['ar'] ?? id,
      en: raw['en'] ?? id,
      pin: raw['pin'] ?? '',
      type: raw['type'] ?? 'DEFAULT',
    );
  }

  static List<BuildingConfig> get all =>
      kBuildingsConfig.keys.map((id) => byId(id)!).toList(growable: false);
}
