import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';

import '../design/checkview_tokens.dart';
import 'checkview_settings_drawer.dart';
import 'corrective_actions_screen.dart';
import 'ops_dashboard_screen.dart';
import 'viewer_home.dart';

/// Top-level CheckView navigation: inspections, operations, corrective
/// actions. A bottom bar on phones, a rail on wider screens.
class CheckViewShell extends StatefulWidget {
  const CheckViewShell({
    super.key,
    required this.profile,
    required this.language,
    required this.onLanguageChanged,
  });

  final Profile profile;
  final String language;
  final ValueChanged<String> onLanguageChanged;

  @override
  State<CheckViewShell> createState() => _CheckViewShellState();
}

class _CheckViewShellState extends State<CheckViewShell> {
  static const _inspections = 0;
  static const _operations = 1;
  static const _actions = 2;

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _homeKey = GlobalKey<ViewerHomeState>();
  int _index = _inspections;

  /// Destinations are built on first visit so Operations does not load its
  /// metrics at sign-in.
  final Set<int> _visited = {_inspections};

  bool get ar => widget.language == 'ar';

  void _select(int index) {
    if (index == _index) return;
    final returningHome = index == _inspections;
    setState(() {
      _index = index;
      _visited.add(index);
    });
    // Reviews and actions elsewhere may have changed today's records.
    if (returningHome) _homeKey.currentState?.reload();
  }

  void _openSettings() => _scaffoldKey.currentState?.openEndDrawer();

  Future<void> _openInspectionFromOperations(String id) async {
    _select(_inspections);
    await _homeKey.currentState?.openInspectionById(id);
  }

  List<(IconData, IconData, String)> get _destinations => [
    (
      Icons.fact_check_outlined,
      Icons.fact_check,
      ar ? 'الفحوصات' : 'Inspections',
    ),
    (Icons.insights_outlined, Icons.insights, ar ? 'العمليات' : 'Operations'),
    (Icons.handyman_outlined, Icons.handyman, ar ? 'الإجراءات' : 'Actions'),
  ];

  Widget _brandMark() => Padding(
    padding: const EdgeInsets.only(top: CvSpace.sm, bottom: CvSpace.xl),
    child: ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          'assets/branding/app_icon_simple.png',
          width: 36,
          height: 36,
          errorBuilder: (_, _, _) => const SizedBox.square(dimension: 36),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = CheckViewColors.of(context);
    final useRail = MediaQuery.sizeOf(context).width >= CvBreakpoint.rail;
    final pages = IndexedStack(
      index: _index,
      children: [
        ViewerHome(
          key: _homeKey,
          profile: widget.profile,
          language: widget.language,
          active: _index == _inspections,
          onOpenSettings: _openSettings,
        ),
        if (_visited.contains(_operations))
          OpsDashboardScreen(
            profile: widget.profile,
            language: widget.language,
            onOpenInspection: _openInspectionFromOperations,
            onOpenSettings: _openSettings,
          )
        else
          const SizedBox.shrink(),
        if (_visited.contains(_actions))
          CorrectiveActionsScreen(
            profile: widget.profile,
            language: widget.language,
            onOpenSettings: _openSettings,
          )
        else
          const SizedBox.shrink(),
      ],
    );

    return PopScope(
      canPop: _index == _inspections,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _index != _inspections) _select(_inspections);
      },
      child: Scaffold(
        key: _scaffoldKey,
        endDrawer: CheckViewSettingsDrawer(
          profile: widget.profile,
          language: widget.language,
          onLanguageChanged: widget.onLanguageChanged,
        ),
        body: useRail
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SafeArea(
                    child: NavigationRail(
                      selectedIndex: _index,
                      onDestinationSelected: _select,
                      groupAlignment: -1,
                      leading: _brandMark(),
                      destinations: [
                        for (final (icon, selectedIcon, label) in _destinations)
                          NavigationRailDestination(
                            icon: Icon(icon),
                            selectedIcon: Icon(selectedIcon),
                            label: Text(label),
                          ),
                      ],
                    ),
                  ),
                  VerticalDivider(width: 1, color: c.hairline),
                  Expanded(child: pages),
                ],
              )
            : pages,
        bottomNavigationBar: useRail
            ? null
            : DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.hairline)),
                ),
                child: SafeArea(
                  top: false,
                  child: NavigationBar(
                    selectedIndex: _index,
                    onDestinationSelected: _select,
                    destinations: [
                      for (final (icon, selectedIcon, label) in _destinations)
                        NavigationDestination(
                          icon: Icon(icon),
                          selectedIcon: Icon(selectedIcon),
                          label: label,
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
