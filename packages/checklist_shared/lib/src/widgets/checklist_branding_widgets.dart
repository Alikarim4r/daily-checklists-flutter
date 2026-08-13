import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../reports/report_branding.dart';
import '../reports/report_branding_resolver.dart';

class ResolvedOrgHeader extends StatefulWidget {
  const ResolvedOrgHeader({
    super.key,
    required this.siteId,
    required this.language,
    required this.siteNameAr,
    required this.siteNameEn,
    required this.buildingCode,
  });

  final String siteId;
  final String language;
  final String siteNameAr;
  final String siteNameEn;
  final String buildingCode;

  @override
  State<ResolvedOrgHeader> createState() => _ResolvedOrgHeaderState();
}

class _ResolvedOrgHeaderState extends State<ResolvedOrgHeader> {
  late Future<ReportBrandingBytes> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  @override
  void didUpdateWidget(covariant ResolvedOrgHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteId != widget.siteId ||
        oldWidget.language != widget.language) {
      _future = _resolve();
    }
  }

  Future<ReportBrandingBytes> _resolve() => ReportBrandingResolver(
    Supabase.instance.client,
  ).resolveForSite(siteId: widget.siteId, language: widget.language);

  bool get _ar => widget.language == 'ar';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ReportBrandingBytes>(
      future: _future,
      builder: (context, snap) {
        final brand = snap.data;
        final orgName =
            brand?.orgNameFor(widget.language) ??
            (_ar ? 'الجهة' : 'Organization');
        final bytes = brand?.orgHeaderLogo;
        final siteLabel = _ar
            ? (widget.siteNameAr.isNotEmpty
                  ? widget.siteNameAr
                  : widget.buildingCode)
            : (widget.siteNameEn.isNotEmpty
                  ? widget.siteNameEn
                  : widget.buildingCode);

        final titles = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: _ar
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Text(
                _ar
                    ? 'خدمة الإدارة المتكاملة للمرافق لصالح $orgName'
                    : 'Integrated Facilities Management Service for $orgName',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                  height: 1.25,
                ),
                textAlign: _ar ? TextAlign.right : TextAlign.left,
              ),
              const SizedBox(height: 4),
              Text(
                _ar
                    ? 'قائمة الفحص اليومي للمرافق - $siteLabel'
                    : 'Facilities Daily Inspection Checklist - $siteLabel',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                  height: 1.25,
                ),
                textAlign: _ar ? TextAlign.right : TextAlign.left,
              ),
            ],
          ),
        );

        final logo = bytes == null
            ? SizedBox(
                height: 58,
                width: 170,
                child: Center(
                  child: Text(
                    orgName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              )
            : Image.memory(
                Uint8List.fromList(bytes),
                width: 170,
                height: 58,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => SizedBox(
                  height: 58,
                  width: 170,
                  child: Center(
                    child: Text(
                      orgName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              );

        return Directionality(
          textDirection: ui.TextDirection.ltr,
          child: Container(
            padding: const EdgeInsets.only(bottom: 8),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFF000000), width: 1),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _ar
                  ? [
                      logo,
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: titles,
                        ),
                      ),
                    ]
                  : [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: titles,
                        ),
                      ),
                      logo,
                    ],
            ),
          ),
        );
      },
    );
  }
}

class ResolvedFooterLogos extends StatefulWidget {
  const ResolvedFooterLogos({
    super.key,
    required this.siteId,
    required this.language,
  });

  final String siteId;
  final String language;

  @override
  State<ResolvedFooterLogos> createState() => _ResolvedFooterLogosState();
}

class _ResolvedFooterLogosState extends State<ResolvedFooterLogos> {
  late Future<ReportBrandingBytes> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  @override
  void didUpdateWidget(covariant ResolvedFooterLogos oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteId != widget.siteId ||
        oldWidget.language != widget.language) {
      _future = _resolve();
    }
  }

  Future<ReportBrandingBytes> _resolve() => ReportBrandingResolver(
    Supabase.instance.client,
  ).resolveForSite(siteId: widget.siteId, language: widget.language);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ReportBrandingBytes>(
      future: _future,
      builder: (context, snap) {
        final brand = snap.data;
        final ar = widget.language == 'ar';
        final leftBytes = ar ? brand?.zoneFooterLogo : brand?.siteFooterLogo;
        final rightBytes = ar ? brand?.siteFooterLogo : brand?.zoneFooterLogo;
        final credit = brand == null
            ? '© Facilities'
            : '© ${brand.orgNameFor(widget.language)}';

        Widget side(List<int>? bytes, double height) {
          if (bytes == null) return SizedBox(width: 90, height: height);
          return Image.memory(
            Uint8List.fromList(bytes),
            height: height,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => SizedBox(height: height),
          );
        }

        return Directionality(
          textDirection: ui.TextDirection.ltr,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              side(leftBytes, 28),
              Text(
                credit,
                style: const TextStyle(fontSize: 9, color: Colors.black54),
              ),
              side(rightBytes, 32),
            ],
          ),
        );
      },
    );
  }
}
