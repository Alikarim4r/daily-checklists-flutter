import 'package:flutter/material.dart';

import '../l10n/app_labels.dart';
import '../theme/checklist_brand.dart';

/// Compact language selector.
class LanguageToggle extends StatelessWidget {
  const LanguageToggle({
    super.key,
    required this.language,
    required this.onChanged,
    this.languages = const ['en', 'ar'],
  });

  final String language;
  final ValueChanged<String> onChanged;
  final List<String> languages;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Language',
      initialValue: language,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final code in languages)
          PopupMenuItem(
            value: code,
            child: Text(languageDisplayNames[code] ?? code),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.language, color: ChecklistChrome.onAccent, size: 20),
            const SizedBox(width: 4),
            Text(
              (languageDisplayNames[language] ?? language).toUpperCase(),
              style: TextStyle(
                color: ChecklistChrome.onAccent,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
