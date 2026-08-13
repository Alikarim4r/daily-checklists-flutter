import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/report_logo_paper_diagram.dart';
import '../widgets/report_logo_slot_editor.dart';

/// Full-screen (or pushed) logo editors with paper position diagrams.
class ReportLogosScreen extends ConsumerStatefulWidget {
  const ReportLogosScreen.org({
    super.key,
    required this.organization,
    required this.language,
    required this.canEdit,
  }) : zone = null,
       site = null,
       isCampus = true,
       _kind = _LogoScreenKind.org;

  const ReportLogosScreen.zone({
    super.key,
    required this.zone,
    required this.language,
    required this.canEdit,
  }) : organization = null,
       site = null,
       isCampus = true,
       _kind = _LogoScreenKind.zone;

  const ReportLogosScreen.site({
    super.key,
    required this.site,
    required this.language,
    required this.canEdit,
    this.isCampus = true,
  }) : organization = null,
       zone = null,
       _kind = _LogoScreenKind.site;

  final Organization? organization;
  final Zone? zone;
  final ChecklistSite? site;
  final String language;
  final bool canEdit;
  final bool isCampus;
  final _LogoScreenKind _kind;

  @override
  ConsumerState<ReportLogosScreen> createState() => ReportLogosScreenState();
}

enum _LogoScreenKind { org, zone, site }

class ReportLogosScreenState extends ConsumerState<ReportLogosScreen> {
  late Organization? _org = widget.organization;
  late Zone? _zone = widget.zone;
  late ChecklistSite? _site = widget.site;

  bool get _ar => widget.language == 'ar';
  String _t(String en, String ar) => _ar ? ar : en;

  @override
  Widget build(BuildContext context) {
    final title = switch (widget._kind) {
      _LogoScreenKind.org => _t('Organization logos', 'شعارات الجهة'),
      _LogoScreenKind.zone => _t('Zone logo', 'شعار المنطقة'),
      _LogoScreenKind.site =>
        widget.isCampus
            ? _t('Site logo', 'شعار الموقع')
            : _t('Checklist logo', 'شعار القائمة'),
    };

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget._kind == _LogoScreenKind.org && _org != null) ...[
            ReportLogoPaperDiagram(
              kind: ReportLogoSlotKind.orgHeader,
              language: widget.language,
            ),
            const SizedBox(height: 20),
            ReportLogoSlotEditor(
              organizationId: _org!.id,
              storageKey: 'logo_ar.png',
              title: _t('Arabic logo (header)', 'الشعار العربي (أعلى)'),
              subtitle: _t(
                'Used when the checklist language is Arabic — top of sheet.',
                'يُستخدم عند اللغة العربية — أعلى ورقة الفحص.',
              ),
              storagePath: _org!.logoArPath,
              canEdit: widget.canEdit,
              language: widget.language,
              onPathChanged: (path) async {
                final updated = await ref
                    .read(organizationRepositoryProvider)
                    .updateOrgLogos(
                      id: _org!.id,
                      logoEnPath: _org!.logoEnPath,
                      logoArPath: path,
                    );
                setState(() => _org = updated);
              },
            ),
            const SizedBox(height: 24),
            ReportLogoSlotEditor(
              organizationId: _org!.id,
              storageKey: 'logo_en.png',
              title: _t('English logo (header)', 'الشعار الإنجليزي (أعلى)'),
              subtitle: _t(
                'Used when the checklist language is English — top of sheet.',
                'يُستخدم عند اللغة الإنجليزية — أعلى ورقة الفحص.',
              ),
              storagePath: _org!.logoEnPath,
              canEdit: widget.canEdit,
              language: widget.language,
              onPathChanged: (path) async {
                final updated = await ref
                    .read(organizationRepositoryProvider)
                    .updateOrgLogos(
                      id: _org!.id,
                      logoEnPath: path,
                      logoArPath: _org!.logoArPath,
                    );
                setState(() => _org = updated);
              },
            ),
          ],
          if (widget._kind == _LogoScreenKind.zone && _zone != null) ...[
            ReportLogoPaperDiagram(
              kind: ReportLogoSlotKind.zoneFooter,
              language: widget.language,
            ),
            const SizedBox(height: 20),
            ReportLogoSlotEditor(
              organizationId: _zone!.organizationId,
              storageKey: 'zones/${_zone!.id}.png',
              title: _t('Zone logo (footer)', 'شعار المنطقة (أسفل)'),
              subtitle: _t(
                'Bottom-right in English · bottom-left in Arabic',
                'أسفل يمين بالإنجليزية · أسفل يسار بالعربية',
              ),
              storagePath: _zone!.reportLogoPath,
              canEdit: widget.canEdit,
              language: widget.language,
              slotWidth: kFooterLogoSlotW,
              slotHeight: kFooterLogoSlotH,
              onPathChanged: (path) async {
                final updated = await ref
                    .read(organizationRepositoryProvider)
                    .updateZoneLogo(id: _zone!.id, reportLogoPath: path);
                setState(() => _zone = updated);
              },
            ),
          ],
          if (widget._kind == _LogoScreenKind.site && _site != null) ...[
            ReportLogoPaperDiagram(
              kind: ReportLogoSlotKind.siteFooter,
              language: widget.language,
            ),
            const SizedBox(height: 20),
            ReportLogoSlotEditor(
              organizationId: _site!.organizationId,
              storageKey: 'sites/${_site!.id}.png',
              title: widget.isCampus
                  ? _t('Site logo (footer)', 'شعار الموقع (أسفل)')
                  : _t(
                      'Checklist logo (overrides campus)',
                      'شعار القائمة (يتجاوز شعار الموقع)',
                    ),
              subtitle: _t(
                'Bottom-left in English · bottom-right in Arabic',
                'أسفل يسار بالإنجليزية · أسفل يمين بالعربية',
              ),
              storagePath: _site!.reportLogoPath,
              canEdit: widget.canEdit,
              language: widget.language,
              slotWidth: kFooterLogoSlotW,
              slotHeight: kFooterLogoSlotH,
              onPathChanged: (path) async {
                final updated = await ref
                    .read(siteRepositoryProvider)
                    .updateReportLogo(id: _site!.id, reportLogoPath: path);
                setState(() => _site = updated);
              },
            ),
          ],
        ],
      ),
    );
  }
}
