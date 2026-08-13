import 'dart:typed_data';

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'report_logo_crop_dialog.dart';

/// Single logo slot with pick → crop → upload to [kReportLogosBucket].
class ReportLogoSlotEditor extends ConsumerStatefulWidget {
  const ReportLogoSlotEditor({
    super.key,
    required this.organizationId,
    required this.storageKey,
    required this.title,
    required this.subtitle,
    required this.storagePath,
    required this.canEdit,
    required this.onPathChanged,
    this.slotWidth = kOrgLogoSlotW,
    this.slotHeight = kOrgLogoSlotH,
    this.language = 'en',
  });

  final String organizationId;

  /// Key relative to org folder, e.g. `logo_en.png`, `zones/{id}.png`.
  final String storageKey;
  final String title;
  final String subtitle;
  final String? storagePath;
  final bool canEdit;
  final ValueChanged<String?> onPathChanged;
  final double slotWidth;
  final double slotHeight;
  final String language;

  @override
  ConsumerState<ReportLogoSlotEditor> createState() =>
      _ReportLogoSlotEditorState();
}

class _ReportLogoSlotEditorState extends ConsumerState<ReportLogoSlotEditor> {
  bool _busy = false;

  bool get _ar => widget.language == 'ar';
  String _t(String en, String ar) => _ar ? ar : en;

  Future<void> _pickAndUpload() async {
    if (!widget.canEdit || _busy) return;
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
      maxWidth: 2400,
    );
    if (file == null) return;

    final raw = await file.readAsBytes();
    final validation = ImageUploadValidation.validate(
      raw,
      minWidth: 200,
      minHeight: 60,
    );
    if (!validation.ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validation.messageFor(widget.language))),
      );
      return;
    }
    if (!mounted) return;
    final cropped = await showReportLogoCropDialog(
      context: context,
      imageBytes: Uint8List.fromList(raw),
      slotWidth: widget.slotWidth,
      slotHeight: widget.slotHeight,
      title: widget.title,
    );
    if (cropped == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final path = '${widget.organizationId}/${widget.storageKey}';
      final client = ref.read(supabaseClientProvider);
      await client.storage
          .from(kReportLogosBucket)
          .uploadBinary(
            path,
            cropped,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: true,
            ),
          );
      ReportBrandingResolver.clearCache();
      widget.onPathChanged(path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t('Logo upload failed: $error', 'فشل رفع الشعار: $error'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    if (!widget.canEdit || _busy) return;
    final path = widget.storagePath;
    setState(() => _busy = true);
    try {
      if (path != null && path.isNotEmpty) {
        try {
          await ref
              .read(supabaseClientProvider)
              .storage
              .from(kReportLogosBucket)
              .remove([path]);
        } catch (_) {}
      }
      ReportBrandingResolver.clearCache();
      widget.onPathChanged(null);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.storagePath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(widget.subtitle, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Container(
          width: widget.slotWidth,
          height: widget.slotHeight,
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
            ),
            borderRadius: BorderRadius.circular(6),
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          ),
          clipBehavior: Clip.antiAlias,
          child: path == null || path.isEmpty
              ? const Center(child: Text('—'))
              : FutureBuilder<String>(
                  future: ref
                      .read(supabaseClientProvider)
                      .storage
                      .from(kReportLogosBucket)
                      .createSignedUrl(path, 3600),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    return Image.network(
                      snap.data!,
                      fit: BoxFit.contain,
                      width: widget.slotWidth,
                      height: widget.slotHeight,
                      errorBuilder: (_, _, _) =>
                          const Center(child: Icon(Icons.broken_image)),
                    );
                  },
                ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            TextButton(
              onPressed: widget.canEdit && !_busy ? _pickAndUpload : null,
              child: Text(
                widget.canEdit ? _t('Import', 'استيراد') : _t('Locked', 'مقفل'),
              ),
            ),
            TextButton(
              onPressed:
                  widget.canEdit && !_busy && path != null && path.isNotEmpty
                  ? _clear
                  : null,
              child: Text(_t('Clear', 'مسح')),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
