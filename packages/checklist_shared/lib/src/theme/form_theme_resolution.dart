/// A theme candidate at one level of the organization hierarchy.
class FormThemeScopeValue {
  const FormThemeScopeValue({
    required this.theme,
    required this.source,
    this.accent,
  });

  final String? theme;
  final String? accent;
  final String source;

  bool get isConcrete {
    final value = theme?.trim();
    return value != null && value.isNotEmpty && value != 'inherit';
  }
}

class ResolvedFormThemeValue {
  const ResolvedFormThemeValue({
    required this.theme,
    required this.source,
    this.accent,
  });

  final String theme;
  final String? accent;
  final String source;
}

/// Mirrors the database resolver and provides a deterministic offline/fallback
/// path: unit → campus → zone → list type → organization → classic default.
ResolvedFormThemeValue resolveFormThemeHierarchy({
  FormThemeScopeValue? site,
  FormThemeScopeValue? campus,
  FormThemeScopeValue? zone,
  FormThemeScopeValue? template,
  FormThemeScopeValue? organization,
}) {
  for (final candidate in [site, campus, zone, template, organization]) {
    if (candidate != null && candidate.isConcrete) {
      return ResolvedFormThemeValue(
        theme: candidate.theme!.trim(),
        accent: candidate.accent,
        source: candidate.source,
      );
    }
  }
  return const ResolvedFormThemeValue(theme: 'classic_gold', source: 'default');
}
