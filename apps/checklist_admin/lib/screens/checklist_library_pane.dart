import 'dart:async';

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../design/checkadmin_errors.dart';
import '../design/checkadmin_tokens.dart';
import '../design/checkadmin_widgets.dart';

class ChecklistLibraryPane extends ConsumerStatefulWidget {
  const ChecklistLibraryPane({
    super.key,
    required this.profile,
    required this.language,
    required this.onInstalled,
  });

  final Profile profile;
  final String language;
  final ValueChanged<String> onInstalled;

  @override
  ConsumerState<ChecklistLibraryPane> createState() =>
      _ChecklistLibraryPaneState();
}

class _ChecklistLibraryPaneState extends ConsumerState<ChecklistLibraryPane> {
  final _search = TextEditingController();
  List<Organization> organizations = const [];
  List<ChecklistLibraryTemplate> templates = const [];
  Map<String, ProductDetails> products = const {};
  String? organizationId;
  String category = 'all';
  String industry = 'all';
  String domain = 'all';
  String documentKind = 'all';
  Map<String, List<GlobalLibraryFacet>> globalFacets = const {};
  bool globalLibraryReady = false;
  bool hasMoreLibrary = false;
  bool loadingMoreLibrary = false;
  int _libraryRequest = 0;
  Timer? _searchDebounce;
  String accessFilter = 'all';
  bool installedOnly = false;
  bool filtersExpanded = false;
  bool loading = true;
  bool purchasing = false;
  String? message;
  LibraryPurchaseService? _billing;
  StreamSubscription<String>? _verifiedSub;

  bool get ar => widget.language == 'ar';
  String _t(String en, String arText) => ar ? arText : en;

  @override
  void initState() {
    super.initState();
    _loadOrganizations();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    _verifiedSub?.cancel();
    _billing?.dispose();
    super.dispose();
  }

  Future<void> _loadOrganizations() async {
    try {
      final list = await ref
          .read(organizationRepositoryProvider)
          .listOrganizations(activeOnly: true);
      final home = widget.profile.homeOrganizationId;
      final target = widget.profile.isPlatformOwner
          ? list.firstOrNull?.id
          : home;
      if (!mounted) return;
      setState(() {
        organizations = list;
        organizationId = target;
      });
      if (target != null) await _loadLibrary();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        loading = false;
        message = checkAdminUserMessage(error, widget.language);
      });
    }
  }

  Future<void> _loadLibrary() async {
    final orgId = organizationId;
    if (orgId == null) return;
    final request = ++_libraryRequest;
    setState(() {
      loading = true;
      message = null;
    });
    try {
      final repo = ref.read(checklistLibraryRepositoryProvider);
      late final List<ChecklistLibraryTemplate> rows;
      Map<String, List<GlobalLibraryFacet>> facets = const {};
      var v2 = false;
      try {
        rows = await repo.listGlobalTemplatesV2(
          organizationId: orgId,
          industry: industry == 'all' ? null : industry,
          domain: domain == 'all' ? null : domain,
          documentKind: documentKind == 'all' ? null : documentKind,
          category: category == 'all' ? null : category,
          search: _search.text,
        );
        facets = await repo.listGlobalFacetsV2(organizationId: orgId);
        v2 = true;
      } catch (error) {
        // Never fall back on 401/403/RLS errors.
        if (!ChecklistLibraryRepository.isGlobalApiNotInstalled(error)) {
          rethrow;
        }
        rows = await repo.listTemplates(organizationId: orgId);
      }
      if (!mounted || request != _libraryRequest) return;
      setState(() {
        templates = rows;
        globalLibraryReady = v2;
        globalFacets = facets;
        hasMoreLibrary = v2 && rows.length == 100;
        loadingMoreLibrary = false;
      });
      await _configureBilling(rows);
    } catch (error) {
      if (!mounted || request != _libraryRequest) return;
      setState(() => message = checkAdminUserMessage(error, widget.language));
    } finally {
      if (mounted && request == _libraryRequest) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _loadMoreLibrary() async {
    if (!globalLibraryReady ||
        !hasMoreLibrary ||
        loadingMoreLibrary ||
        organizationId == null) {
      return;
    }
    final request = _libraryRequest;
    final offset = templates.length;
    setState(() => loadingMoreLibrary = true);
    try {
      final next = await ref
          .read(checklistLibraryRepositoryProvider)
          .listGlobalTemplatesV2(
            organizationId: organizationId!,
            industry: industry == 'all' ? null : industry,
            domain: domain == 'all' ? null : domain,
            documentKind: documentKind == 'all' ? null : documentKind,
            category: category == 'all' ? null : category,
            search: _search.text,
            offset: offset,
          );
      if (!mounted || request != _libraryRequest) return;
      final seen = templates.map((e) => e.id).toSet();
      setState(() {
        templates = [
          ...templates,
          for (final item in next)
            if (seen.add(item.id)) item,
        ];
        hasMoreLibrary = next.length == 100;
      });
      await _configureBilling(templates);
    } catch (error) {
      if (mounted && request == _libraryRequest) {
        setState(() => message = checkAdminUserMessage(error, widget.language));
      }
    } finally {
      if (mounted && request == _libraryRequest) {
        setState(() => loadingMoreLibrary = false);
      }
    }
  }

  Future<void> _configureBilling(List<ChecklistLibraryTemplate> rows) async {
    await _verifiedSub?.cancel();
    await _billing?.dispose();
    final ids = {
      for (final row in rows)
        if (row.googlePlayProductId?.isNotEmpty == true)
          row.googlePlayProductId!,
    };
    if (ids.isEmpty || organizationId == null) {
      if (mounted) setState(() => products = const {});
      return;
    }
    final service = LibraryPurchaseService(
      organizationId: organizationId!,
      productIds: ids,
      applicationUserName: widget.profile.id,
      packageName: 'com.alielhassan.checkadmin',
      repository: ref.read(checklistLibraryRepositoryProvider),
    );
    _billing = service;
    _verifiedSub = service.verifiedProductIds.listen((_) async {
      if (!mounted) return;
      await _loadLibrary();
    });
    if (!await service.initialize()) return;
    final response = await service.loadProducts();
    if (!mounted) return;
    setState(() {
      products = {for (final item in response.productDetails) item.id: item};
    });
  }

  Future<void> _install(ChecklistLibraryTemplate template) async {
    final orgId = organizationId;
    if (orgId == null) return;
    try {
      final installedId = await ref
          .read(checklistLibraryRepositoryProvider)
          .installTemplate(
            libraryTemplateId: template.id,
            organizationId: orgId,
          );
      if (!mounted) return;
      widget.onInstalled(installedId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'Installed as an editable draft.',
              'تم التنزيل كمسودة قابلة للتعديل.',
            ),
          ),
        ),
      );
      await _loadLibrary();
    } catch (error) {
      if (!mounted) return;
      setState(() => message = checkAdminUserMessage(error, widget.language));
    }
  }

  Future<void> _purchase(ChecklistLibraryTemplate template) async {
    final productId = template.googlePlayProductId;
    final product = productId == null ? null : products[productId];
    if (product == null || _billing == null) return;
    setState(() => purchasing = true);
    try {
      await _billing!.buy(product);
    } catch (error) {
      if (mounted) {
        setState(() => message = checkAdminUserMessage(error, widget.language));
      }
    } finally {
      if (mounted) setState(() => purchasing = false);
    }
  }

  Future<void> _editTaxonomy(ChecklistLibraryTemplate template) async {
    if (!widget.profile.isPlatformOwner || !globalLibraryReady) return;
    try {
      final repo = ref.read(checklistLibraryRepositoryProvider);
      final terms = await repo.listGlobalTaxonomyTerms();
      if (!mounted) return;
      final selectedIndustries = template.industries.map((e) => e.slug).toSet();
      final selectedDomains = template.domains.map((e) => e.slug).toSet();
      final industries = terms['industry'] ?? const <GlobalLibraryFacet>[];
      final domains = [...?terms['domain'], ...?terms['subdomain']];
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, refresh) => AlertDialog(
            title: Text(_t('Classify template', 'تصنيف القالب')),
            content: SizedBox(
              width: 520,
              height: MediaQuery.sizeOf(dialogContext).height * .56,
              child: ListView(
                children: [
                  Text(
                    template.nameFor(widget.language),
                    style: Theme.of(dialogContext).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _t('Sectors', 'القطاعات'),
                    style: Theme.of(dialogContext).textTheme.titleMedium,
                  ),
                  for (final term in industries)
                    CheckboxListTile(
                      dense: true,
                      title: Text(term.nameFor(widget.language)),
                      value: selectedIndustries.contains(term.slug),
                      onChanged: (checked) => refresh(() {
                        if (checked == true) {
                          selectedIndustries.add(term.slug);
                        } else {
                          selectedIndustries.remove(term.slug);
                        }
                      }),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    _t('Disciplines', 'التخصصات'),
                    style: Theme.of(dialogContext).textTheme.titleMedium,
                  ),
                  for (final term in domains)
                    CheckboxListTile(
                      dense: true,
                      title: Text(term.nameFor(widget.language)),
                      value: selectedDomains.contains(term.slug),
                      onChanged: (checked) => refresh(() {
                        if (checked == true) {
                          selectedDomains.add(term.slug);
                        } else {
                          selectedDomains.remove(term.slug);
                        }
                      }),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(_t('Cancel', 'إلغاء')),
              ),
              FilledButton(
                onPressed: selectedIndustries.isEmpty || selectedDomains.isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: Text(_t('Save classification', 'حفظ التصنيف')),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
      await repo.assignGlobalTaxonomyV2(
        templateId: template.id,
        industries: selectedIndustries.toList(),
        domains: selectedDomains.toList(),
      );
      if (!mounted) return;
      await _loadLibrary();
    } catch (error) {
      if (mounted) {
        setState(() => message = checkAdminUserMessage(error, widget.language));
      }
    }
  }

  List<ChecklistLibraryTemplate> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return templates.where((template) {
      if (installedOnly && !template.isInstalled) return false;
      if (globalLibraryReady &&
          industry != 'all' &&
          !template.industries.any((term) => term.slug == industry)) {
        return false;
      }
      if (globalLibraryReady &&
          domain != 'all' &&
          !template.domains.any((term) => term.slug == domain)) {
        return false;
      }
      if (globalLibraryReady &&
          documentKind != 'all' &&
          template.documentKind != documentKind) {
        return false;
      }
      if (category != 'all' && template.categorySlug != category) return false;
      if (accessFilter == 'included' && template.isPremium) return false;
      if (accessFilter == 'premium' && !template.isPremium) return false;
      if (query.isEmpty) return true;
      final haystack = [
        template.nameEn,
        template.nameAr,
        template.descriptionEn ?? '',
        template.descriptionAr ?? '',
        template.categoryNameEn,
        template.categoryNameAr,
        ...template.facilityTags,
        for (final term in [...template.industries, ...template.domains]) ...[
          term.nameEn,
          term.nameAr,
        ],
        template.documentKindNameEn,
        template.documentKindNameAr,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  List<String> get _categories => [
    'all',
    if (globalLibraryReady)
      for (final value
          in globalFacets['category'] ?? const <GlobalLibraryFacet>[])
        value.slug
    else ...{for (final item in templates) item.categorySlug},
  ];

  String _categoryLabel(String value) {
    if (value == 'all') return _t('All categories', 'كل التصنيفات');
    if (globalLibraryReady) {
      final facet = (globalFacets['category'] ?? const <GlobalLibraryFacet>[])
          .where((valueRow) => valueRow.slug == value)
          .firstOrNull;
      if (facet != null) return facet.nameFor(widget.language);
    }
    final row = templates.where((e) => e.categorySlug == value).firstOrNull;
    return row?.categoryNameFor(widget.language) ?? value;
  }

  int _categoryCount(String value) {
    if (globalLibraryReady) {
      final categories =
          globalFacets['category'] ?? const <GlobalLibraryFacet>[];
      if (value == 'all') {
        return categories.fold(0, (total, facet) => total + facet.count);
      }
      return categories
          .where((facet) => facet.slug == value)
          .fold(0, (total, facet) => total + facet.count);
    }
    return value == 'all'
        ? templates.length
        : templates.where((e) => e.categorySlug == value).length;
  }

  String _accessLabel(String value) => switch (value) {
    'included' => _t('Included', 'المضمنة'),
    'premium' => _t('Premium', 'المدفوعة'),
    _ => _t('All access', 'كل الأنواع'),
  };

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final colors = CheckAdminColors.of(context);
    final compact = MediaQuery.sizeOf(context).width < 700;
    final hasActiveFilters =
        category != 'all' ||
        industry != 'all' ||
        domain != 'all' ||
        documentKind != 'all' ||
        accessFilter != 'all' ||
        installedOnly;

    Widget searchField() => TextField(
      controller: _search,
      onChanged: (_) {
        setState(() {});
        _searchDebounce?.cancel();
        if (globalLibraryReady) {
          _searchDebounce = Timer(
            const Duration(milliseconds: 400),
            _loadLibrary,
          );
        }
      },
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded),
        hintText: _t('Search library', 'ابحث في المكتبة'),
        isDense: true,
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                tooltip: _t('Clear', 'مسح'),
                onPressed: () {
                  _search.clear();
                  setState(() {});
                  _searchDebounce?.cancel();
                  if (globalLibraryReady) _loadLibrary();
                },
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );

    Widget organizationFilter() => DropdownButtonFormField<String>(
      initialValue: organizationId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: _t('Organization', 'الجهة'),
        prefixIcon: const Icon(Icons.business_outlined),
        isDense: true,
      ),
      items: [
        for (final org in organizations)
          DropdownMenuItem(
            value: org.id,
            child: Text(
              org.nameFor(widget.language),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) async {
        if (value == null || value == organizationId) return;
        setState(() {
          organizationId = value;
          category = 'all';
          industry = 'all';
          domain = 'all';
          documentKind = 'all';
        });
        await _loadLibrary();
      },
    );

    Widget categoryFilter() => DropdownButtonFormField<String>(
      key: ValueKey(
        'library-category-$category-$organizationId-$globalLibraryReady',
      ),
      initialValue: category,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: _t('Category', 'التصنيف'),
        prefixIcon: const Icon(Icons.category_outlined),
        isDense: true,
      ),
      items: [
        for (final value in _categories)
          DropdownMenuItem(
            value: value,
            child: Text(
              '${_categoryLabel(value)} (${_categoryCount(value)})',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) {
        if (value == null || value == category) return;
        setState(() => category = value);
        if (globalLibraryReady) _loadLibrary();
      },
    );

    Widget taxonomyFilter({
      required String title,
      required String selected,
      required IconData icon,
      required List<GlobalLibraryFacet> options,
      required ValueChanged<String> onChoose,
    }) => DropdownButtonFormField<String>(
      key: ValueKey('global-$title-$selected'),
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: title,
        prefixIcon: Icon(icon),
        isDense: true,
      ),
      items: [
        DropdownMenuItem(value: 'all', child: Text(_t('All', 'الكل'))),
        for (final option in options)
          DropdownMenuItem(
            value: option.slug,
            child: Text(
              '${option.nameFor(widget.language)} (${option.count})',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) {
        if (value != null && value != selected) {
          setState(() {
            category = 'all';
            onChoose(value);
          });
          _loadLibrary();
        }
      },
    );

    Widget industryFilter() => taxonomyFilter(
      title: _t('Industry / sector', 'القطاع'),
      selected: industry,
      icon: Icons.public_rounded,
      options: globalFacets['industry'] ?? const [],
      onChoose: (value) => industry = value,
    );
    Widget domainFilter() => taxonomyFilter(
      title: _t('Discipline', 'التخصص'),
      selected: domain,
      icon: Icons.category_outlined,
      options: [...?globalFacets['domain'], ...?globalFacets['subdomain']],
      onChoose: (value) => domain = value,
    );
    Widget kindFilter() {
      final kinds = <String, String>{
        'checklist': _t('Checklist', 'قائمة فحص'),
        for (final row in templates)
          row.documentKind: row.documentKindNameFor(widget.language),
      };
      return DropdownButtonFormField<String>(
        key: ValueKey('document-kind-$documentKind'),
        initialValue: documentKind,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: _t('Document type', 'نوع المستند'),
          prefixIcon: const Icon(Icons.description_outlined),
          isDense: true,
        ),
        items: [
          DropdownMenuItem(
            value: 'all',
            child: Text(_t('All types', 'كل الأنواع')),
          ),
          for (final entry in kinds.entries)
            DropdownMenuItem(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (value) {
          if (value == null || value == documentKind) return;
          setState(() => documentKind = value);
          _loadLibrary();
        },
      );
    }

    Widget accessFilterField() => DropdownButtonFormField<String>(
      initialValue: accessFilter,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: _t('Access', 'النوع'),
        prefixIcon: const Icon(Icons.tune_rounded),
        isDense: true,
      ),
      items: [
        for (final value in const ['all', 'included', 'premium'])
          DropdownMenuItem(
            value: value,
            child: Text(_accessLabel(value), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) {
        if (value != null) setState(() => accessFilter = value);
      },
    );

    Widget installedFilter() => FilterChip(
      avatar: const Icon(Icons.download_done_rounded, size: 17),
      label: Text(_t('Installed only', 'المثبتة فقط')),
      selected: installedOnly,
      visualDensity: VisualDensity.compact,
      onSelected: (value) => setState(() => installedOnly = value),
    );

    Widget compactFilters() => Padding(
      padding: const EdgeInsets.fromLTRB(CaSpace.gutter, 6, CaSpace.gutter, 2),
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CaRadius.panel),
          side: BorderSide(color: colors.rule),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.profile.isPlatformOwner &&
                  organizations.isNotEmpty) ...[
                organizationFilter(),
                const SizedBox(height: 8),
              ],
              if (globalLibraryReady) ...[
                industryFilter(),
                const SizedBox(height: 8),
                domainFilter(),
                const SizedBox(height: 8),
                kindFilter(),
                const SizedBox(height: 8),
              ],
              categoryFilter(),
              const SizedBox(height: 8),
              accessFilterField(),
              const SizedBox(height: 6),
              Row(
                children: [
                  installedFilter(),
                  const Spacer(),
                  Text(
                    _t('${rows.length} lists', '${rows.length} قائمة'),
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: colors.inkMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    Widget desktopFilters() => Padding(
      padding: const EdgeInsets.fromLTRB(CaSpace.gutter, 8, CaSpace.gutter, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fields = <Widget>[
            if (widget.profile.isPlatformOwner && organizations.isNotEmpty)
              organizationFilter(),
            if (globalLibraryReady) ...[
              industryFilter(),
              domainFilter(),
              kindFilter(),
            ],
            categoryFilter(),
            accessFilterField(),
          ];
          const gap = 10.0;
          final columns = constraints.maxWidth >= 1080
              ? 4
              : constraints.maxWidth >= 730
              ? 3
              : 2;
          final fieldWidth =
              (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: 8,
            children: [
              for (final field in fields)
                SizedBox(width: fieldWidth, child: field),
            ],
          );
        },
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            CaSpace.gutter,
            compact ? 4 : CaSpace.sm,
            CaSpace.gutter,
            0,
          ),
          child: compact
              ? Row(
                  children: [
                    Expanded(child: searchField()),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: _t('Filters', 'الفلاتر'),
                      isSelected: filtersExpanded || hasActiveFilters,
                      onPressed: () =>
                          setState(() => filtersExpanded = !filtersExpanded),
                      icon: Icon(
                        hasActiveFilters
                            ? Icons.filter_alt_rounded
                            : Icons.filter_alt_outlined,
                      ),
                      selectedIcon: const Icon(Icons.filter_alt_rounded),
                    ),
                  ],
                )
              : searchField(),
        ),
        if (compact)
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: filtersExpanded
                ? ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .43,
                    ),
                    child: SingleChildScrollView(child: compactFilters()),
                  )
                : const SizedBox.shrink(),
          )
        else ...[
          desktopFilters(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CaSpace.gutter,
              6,
              CaSpace.gutter,
              0,
            ),
            child: Row(
              children: [
                installedFilter(),
                const Spacer(),
                Text(
                  _t('${rows.length} lists', '${rows.length} قائمة'),
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: colors.inkMuted),
                ),
              ],
            ),
          ),
        ],
        if (message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CaSpace.gutter,
              2,
              CaSpace.gutter,
              CaSpace.sm,
            ),
            child: CaInlineNotice(
              message: message!,
              tone: CaTone.danger,
              onDismiss: () => setState(() => message = null),
            ),
          ),
        if (loading)
          const LinearProgressIndicator(minHeight: 2)
        else
          Expanded(
            child: rows.isEmpty
                ? CaEmptyState(
                    icon: Icons.auto_stories_outlined,
                    title: _t('No library lists found', 'لا توجد قوائم مطابقة'),
                    message: _t(
                      'Try another category or search term.',
                      'جرّب تصنيفاً أو عبارة بحث أخرى.',
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadLibrary,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final twoColumns = constraints.maxWidth >= 900;
                        return GridView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                            CaSpace.gutter,
                            compact ? 6 : CaSpace.sm,
                            CaSpace.gutter,
                            MediaQuery.viewPaddingOf(context).bottom +
                                CaSpace.lg,
                          ),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: twoColumns ? 2 : 1,
                                crossAxisSpacing: CaSpace.sm,
                                mainAxisSpacing: compact ? 8 : CaSpace.sm,
                                mainAxisExtent: twoColumns ? 236 : 224,
                              ),
                          itemCount: rows.length + (hasMoreLibrary ? 1 : 0),
                          itemBuilder: (_, index) => index < rows.length
                              ? _libraryCard(rows[index])
                              : Center(
                                  child: TextButton.icon(
                                    onPressed: loadingMoreLibrary
                                        ? null
                                        : _loadMoreLibrary,
                                    icon: loadingMoreLibrary
                                        ? const SizedBox(
                                            width: 15,
                                            height: 15,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.expand_more_rounded),
                                    label: Text(
                                      _t(
                                        'Load more templates',
                                        'تحميل قوالب إضافية',
                                      ),
                                    ),
                                  ),
                                ),
                        );
                      },
                    ),
                  ),
          ),
      ],
    );
  }

  Widget _libraryCard(ChecklistLibraryTemplate template) {
    final c = CheckAdminColors.of(context);
    final productId = template.googlePlayProductId;
    final product = productId == null ? null : products[productId];
    final price = product?.price ?? _fallbackPrice(template);

    return Material(
      color: c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CaRadius.panel),
        side: BorderSide(color: c.rule),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    template.industries.isEmpty
                        ? template.categoryNameFor(widget.language)
                        : '${template.categoryNameFor(widget.language)} · '
                              '${template.industries.first.nameFor(widget.language)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: c.inkMuted),
                  ),
                ),
                if (widget.profile.isPlatformOwner && globalLibraryReady)
                  IconButton(
                    tooltip: _t(
                      'Edit industry and discipline',
                      'تعديل القطاع والتخصص',
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _editTaxonomy(template),
                    icon: const Icon(Icons.edit_note_rounded, size: 20),
                  ),
                const SizedBox(width: 8),
                CaRoleBadge(
                  label: template.isPremium
                      ? _t('Premium', 'مدفوع')
                      : _t('Included', 'مضمنة'),
                  tone: template.isPremium ? CaTone.brass : CaTone.good,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              template.nameFor(widget.language),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (template.descriptionFor(widget.language)?.isNotEmpty ==
                true) ...[
              const SizedBox(height: 4),
              Text(
                template.descriptionFor(widget.language)!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: c.inkMuted),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                CaMeta(
                  _t(
                    '${template.itemCount} items',
                    '${template.itemCount} بند',
                  ),
                  icon: Icons.checklist_rounded,
                ),
                CaMeta(
                  '${template.languages.length} ${_t('languages', 'لغات')}',
                  icon: Icons.translate_rounded,
                ),
                if (template.isPremium && price != null)
                  CaMeta(price, icon: Icons.sell_outlined, tone: CaTone.brass),
              ],
            ),
            const Spacer(),
            Divider(height: 16, color: c.rule),
            Row(
              children: [
                if (template.isInstalled) ...[
                  Icon(Icons.check_circle_rounded, size: 17, color: c.good),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      template.hasUpdate
                          ? _t('Update available', 'يتوفر تحديث')
                          : _t('Installed', 'مثبتة'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.labelMedium?.copyWith(color: c.good),
                    ),
                  ),
                ] else
                  const Spacer(),
                _libraryAction(template, product),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _libraryAction(
    ChecklistLibraryTemplate template,
    ProductDetails? product,
  ) {
    if (template.canAccess) {
      return FilledButton.icon(
        onPressed: purchasing ? null : () => _install(template),
        icon: Icon(
          template.isInstalled
              ? Icons.system_update_alt_rounded
              : Icons.download_rounded,
        ),
        label: Text(
          template.isInstalled
              ? (template.hasUpdate
                    ? _t('Install update', 'تثبيت التحديث')
                    : _t('Open copy', 'فتح النسخة'))
              : _t('Install', 'تنزيل'),
        ),
      );
    }
    if (!template.isPremium) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.lock_outline_rounded),
        label: Text(_t('Upgrade plan', 'ترقية الاشتراك')),
      );
    }
    if (product == null) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.storefront_outlined),
        label: Text(
          _t('Not on Google Play yet', 'غير متاح في Google Play بعد'),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: purchasing ? null : () => _purchase(template),
      icon: const Icon(Icons.shopping_bag_outlined),
      label: Text(_t('Buy ${product.price}', 'شراء ${product.price}')),
    );
  }

  String? _fallbackPrice(ChecklistLibraryTemplate template) {
    final minor = template.listPriceMinor;
    if (minor == null) return null;
    return '${(minor / 100).toStringAsFixed(2)} ${template.listPriceCurrency}';
  }
}
