import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/checkadmin_errors.dart';
import '../design/checkadmin_tokens.dart';
import '../design/checkadmin_widgets.dart';

class UsersTab extends ConsumerStatefulWidget {
  const UsersTab({super.key, required this.profile, required this.language});
  final Profile profile;
  final String language;

  @override
  ConsumerState<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<UsersTab> {
  bool get ar => widget.language == 'ar';
  String _t(String en, String arText) => ar ? arText : en;
  List<Profile> users = [];
  List<ChecklistSite> sites = [];
  List<Organization> organizations = [];
  bool loading = true;
  String? message;
  int segment = 0; // 0 pending, 1 active

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      message = null;
    });
    try {
      final list = await ref.read(authRepositoryProvider).listProfiles();
      // RLS scopes sites/orgs to what the actor may see.
      final siteList = await ref
          .read(siteRepositoryProvider)
          .listAllSites(activeOnly: true);
      final orgList = await ref
          .read(organizationRepositoryProvider)
          .listOrganizations(activeOnly: true);
      final hasAttention = list.any(
        (u) => u.approvalStatus != ApprovalStatus.approved,
      );
      setState(() {
        users = list;
        sites = siteList;
        organizations = orgList;
        if (!hasAttention) segment = 1;
      });
    } catch (e) {
      setState(() => message = checkAdminUserMessage(e, widget.language));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<Profile> get _filtered {
    if (segment == 0) {
      return users
          .where(
            (u) =>
                u.approvalStatus == ApprovalStatus.pending ||
                u.approvalStatus == ApprovalStatus.rejected ||
                u.approvalStatus == ApprovalStatus.suspended,
          )
          .toList();
    }
    return users
        .where((u) => u.approvalStatus == ApprovalStatus.approved)
        .toList();
  }

  Future<void> _approve(Profile user) async {
    final result = await showDialog<_ApproveResult>(
      context: context,
      builder: (context) => _ApproveUserDialog(
        user: user,
        sites: sites,
        organizations: organizations,
        actor: widget.profile,
        language: widget.language,
      ),
    );
    if (result == null) return;
    try {
      await ref
          .read(authRepositoryProvider)
          .approveUser(
            userId: user.id,
            role: result.role,
            siteIds: result.siteIds,
            note: result.note,
            organizationId: result.organizationId,
          );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('User approved', 'تم اعتماد المستخدم'))),
        );
      }
    } catch (e) {
      setState(() => message = checkAdminUserMessage(e, widget.language));
    }
  }

  Future<void> _editSiteFlags(Profile user) async {
    final siteRepo = ref.read(siteRepositoryProvider);
    final access = await siteRepo.listUserSiteAccess(user.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _SiteFlagsDialog(
        user: user,
        allSites: sites,
        initialAccess: access,
        language: widget.language,
        onSaved: _load,
      ),
    );
  }

  Future<void> _setStatus(Profile user, ApprovalStatus status) async {
    try {
      await ref
          .read(authRepositoryProvider)
          .setUserStatus(userId: user.id, status: status);
      await _load();
    } catch (e) {
      setState(() => message = checkAdminUserMessage(e, widget.language));
    }
  }

  bool get _canCreate =>
      widget.profile.canManageSuperAdmins || widget.profile.canManageSiteAdmins;

  bool _canActOn(Profile user) {
    if (user.isPlatformOwner) return false;
    if (user.role == UserRole.superAdmin &&
        !widget.profile.canManageSuperAdmins) {
      return false;
    }
    if (user.role == UserRole.siteAdmin &&
        !widget.profile.canManageSiteAdmins) {
      return false;
    }
    return true;
  }

  Future<void> _createUser() async {
    if (!_canCreate) return;
    final name = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(_t('Add user', 'إضافة مستخدم')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(
                  labelText: _t('Full name', 'الاسم'),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: _t('Email', 'البريد'),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: _t(
                    'Password (at least 8 characters)',
                    'كلمة المرور (8 أحرف على الأقل)',
                  ),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _t(
                  'The account is created pending approval. Assign the role and sites next.',
                  'يُنشأ الحساب بانتظار الاعتماد — ثم عيّن الدور والمواقع.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('Cancel', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('Create', 'إنشاء')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final userId = await ref
          .read(authRepositoryProvider)
          .createUser(
            email: email.text.trim(),
            password: password.text,
            fullName: name.text.trim().isEmpty ? null : name.text.trim(),
          );
      await _load();
      if (!mounted) return;
      Profile? created;
      for (final u in users) {
        if (u.id == userId) {
          created = u;
          break;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'User created. Approve the account now.',
              'تم إنشاء المستخدم — اعتمده الآن',
            ),
          ),
        ),
      );
      if (created != null) await _approve(created);
    } catch (e) {
      setState(() => message = checkAdminUserMessage(e, widget.language));
    }
  }

  CaTone _userTone(Profile u) => switch (u.approvalStatus) {
    ApprovalStatus.approved => CaTone.good,
    ApprovalStatus.pending => CaTone.warning,
    ApprovalStatus.suspended || ApprovalStatus.rejected => CaTone.danger,
  };

  String _statusLabel(Profile u) => ar
      ? u.approvalStatus.labelAr
      : u.approvalStatus.dbValue.replaceAll('_', ' ');

  String _roleLabel(Profile u) =>
      ar ? u.role.labelAr : u.role.dbValue.replaceAll('_', ' ');

  bool _isElevated(Profile u) =>
      u.isPlatformOwner ||
      u.role == UserRole.superAdmin ||
      u.role == UserRole.siteAdmin;

  String _initials(Profile u) {
    final source = u.fullName.trim().isEmpty
        ? u.email.trim()
        : u.fullName.trim();
    final parts = source
        .split(RegExp(r'\\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final value = parts.first;
      return value.substring(0, value.length.clamp(0, 2)).toUpperCase();
    }
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }

  Widget _avatar(Profile u) {
    final c = CheckAdminColors.of(context);
    final elevated = _isElevated(u);
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(CaRadius.control),
        border: elevated ? Border.all(color: c.brass, width: 1.5) : null,
      ),
      child: Text(
        _initials(u),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: elevated ? c.brass : c.inkMuted,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<void> _handleUserMenu(Profile u, String action) async {
    switch (action) {
      case 'access':
        await _editSiteFlags(u);
      case 'suspend':
        await _setStatus(u, ApprovalStatus.suspended);
      case 'reject':
        await _setStatus(u, ApprovalStatus.rejected);
      case 'approve':
        await _approve(u);
    }
  }

  Widget _userTrailing(Profile u) {
    final canAct = _canActOn(u);
    final pending = u.approvalStatus != ApprovalStatus.approved;
    final elevated = _isElevated(u);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CaRoleBadge(
          label: _roleLabel(u),
          tone: elevated ? CaTone.brass : CaTone.neutral,
        ),
        if (pending && canAct) ...[
          const SizedBox(width: 6),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            onPressed: () => _approve(u),
            child: Text(_t('Approve', 'اعتماد')),
          ),
        ],
        if (canAct)
          PopupMenuButton<String>(
            tooltip: _t('More actions', 'إجراءات إضافية'),
            onSelected: (value) => _handleUserMenu(u, value),
            itemBuilder: (context) => [
              if (u.approvalStatus == ApprovalStatus.approved)
                PopupMenuItem(
                  value: 'access',
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.admin_panel_settings_outlined),
                    title: Text(_t('Access', 'الصلاحيات')),
                  ),
                ),
              if (u.approvalStatus == ApprovalStatus.approved)
                PopupMenuItem(
                  value: 'suspend',
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.pause_circle_outline),
                    title: Text(_t('Suspend', 'إيقاف')),
                  ),
                ),
              if (u.approvalStatus == ApprovalStatus.pending)
                PopupMenuItem(
                  value: 'reject',
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.block_outlined),
                    title: Text(_t('Reject', 'رفض')),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _userRow(Profile u) {
    final pending = u.approvalStatus != ApprovalStatus.approved;
    return CaCommandRow(
      minHeight: 64,
      leading: _avatar(u),
      title: u.fullName.trim().isEmpty ? u.email : u.fullName,
      subtitle: u.fullName.trim().isEmpty ? _roleLabel(u) : u.email,
      meta: pending ? [CaMeta(_statusLabel(u), tone: _userTone(u))] : const [],
      trailing: _userTrailing(u),
      showChevron: false,
      onTap: _canActOn(u)
          ? () => pending ? _approve(u) : _editSiteFlags(u)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = users
        .where((u) => u.approvalStatus != ApprovalStatus.approved)
        .length;
    final activeCount = users
        .where((u) => u.approvalStatus == ApprovalStatus.approved)
        .length;
    final list = _filtered;
    final c = CheckAdminColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pendingCount > 0)
          Container(
            constraints: const BoxConstraints(minHeight: 48),
            decoration: BoxDecoration(
              color: c.surface,
              border: BorderDirectional(
                start: BorderSide(color: c.warning, width: 2),
                bottom: BorderSide(color: c.rule),
              ),
            ),
            padding: const EdgeInsetsDirectional.fromSTEB(
              CaSpace.gutter,
              CaSpace.sm,
              CaSpace.sm,
              CaSpace.sm,
            ),
            child: Row(
              children: [
                Icon(Icons.schedule_outlined, size: 18, color: c.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _t(
                      '$pendingCount accounts need attention',
                      '$pendingCount حسابات تحتاج إجراء',
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: c.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => segment = 0),
                  child: Text(_t('Review', 'مراجعة')),
                ),
              ],
            ),
          ),
        if (pendingCount > 0)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              CaSpace.gutter,
              CaSpace.sm,
              CaSpace.gutter,
              0,
            ),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: 0,
                    label: Text(
                      _t(
                        'Needs action $pendingCount',
                        'يحتاج إجراء $pendingCount',
                      ),
                    ),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text(
                      _t('Active $activeCount', 'المعتمدون $activeCount'),
                    ),
                  ),
                ],
                selected: {segment},
                onSelectionChanged: loading
                    ? null
                    : (v) => setState(() => segment = v.first),
              ),
            ),
          ),
        if (message != null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              CaSpace.gutter,
              CaSpace.sm,
              CaSpace.gutter,
              0,
            ),
            child: CaInlineNotice(
              message: message!,
              tone: CaTone.danger,
              onDismiss: () => setState(() => message = null),
            ),
          ),
        CaSectionLabel(
          title: segment == 0 && pendingCount > 0
              ? _t('Needs action', 'يحتاج إجراء')
              : _t('Access', 'الوصول'),
          count: list.length,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: _t('Refresh', 'تحديث'),
                onPressed: loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
              if (_canCreate)
                CaCreateButton(
                  onPressed: loading ? null : _createUser,
                  icon: Icons.person_add_alt_1,
                  label: _t('New user', 'مستخدم جديد'),
                  compactLabel: _t('User', 'مستخدم'),
                ),
            ],
          ),
        ),
        Expanded(
          child: loading && users.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(CaSpace.gutter),
                  child: CaSkeletonList(rows: 6),
                )
              : list.isEmpty
              ? CaEmptyState(
                  icon: segment == 0
                      ? Icons.verified_user_outlined
                      : Icons.people_outline,
                  title: segment == 0
                      ? _t(
                          'Nothing needs attention',
                          'لا توجد حسابات تحتاج إجراء',
                        )
                      : _t('No approved users', 'لا يوجد مستخدمون معتمدون'),
                  message: segment == 0
                      ? _t(
                          'New registration requests will appear here.',
                          'ستظهر طلبات التسجيل الجديدة هنا.',
                        )
                      : null,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.viewPaddingOf(context).bottom + 16,
                    ),
                    children: [
                      CaLedger(children: [for (final u in list) _userRow(u)]),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _ApproveResult {
  const _ApproveResult({
    required this.role,
    required this.siteIds,
    this.note,
    this.organizationId,
  });
  final UserRole role;
  final List<String> siteIds;
  final String? note;
  final String? organizationId;
}

class _ApproveUserDialog extends StatefulWidget {
  const _ApproveUserDialog({
    required this.user,
    required this.sites,
    required this.organizations,
    required this.actor,
    required this.language,
  });

  final Profile user;
  final List<ChecklistSite> sites;
  final List<Organization> organizations;
  final Profile actor;
  final String language;

  @override
  State<_ApproveUserDialog> createState() => _ApproveUserDialogState();
}

class _ApproveUserDialogState extends State<_ApproveUserDialog> {
  bool get ar => widget.language == 'ar';
  String _t(String en, String arText) => ar ? arText : en;
  late UserRole role;
  final selected = <String>{};
  final noteCtrl = TextEditingController();
  String? organizationId;

  @override
  void initState() {
    super.initState();
    role = UserRole.technician;
    organizationId =
        widget.actor.homeOrganizationId ??
        (widget.organizations.isNotEmpty
            ? widget.organizations.first.id
            : null);
  }

  @override
  void dispose() {
    noteCtrl.dispose();
    super.dispose();
  }

  List<UserRole> get _roleChoices {
    if (widget.actor.canManageSuperAdmins) {
      return const [
        UserRole.superAdmin,
        UserRole.siteAdmin,
        UserRole.technician,
        UserRole.viewer,
      ];
    }
    if (widget.actor.canManageSiteAdmins) {
      return const [UserRole.siteAdmin, UserRole.technician, UserRole.viewer];
    }
    // Site admin: technicians / viewers only
    return const [UserRole.technician, UserRole.viewer];
  }

  @override
  Widget build(BuildContext context) {
    final needsSites = role != UserRole.superAdmin;
    final needsOrg = role == UserRole.superAdmin;
    return AlertDialog(
      title: Text(
        _t('Approve ${widget.user.email}', 'اعتماد — ${widget.user.email}'),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<UserRole>(
                initialValue: role,
                decoration: InputDecoration(
                  labelText: _t('Role', 'الدور'),
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final r in _roleChoices)
                    DropdownMenuItem(
                      value: r,
                      child: Text(
                        ar ? r.labelAr : r.dbValue.replaceAll('_', ' '),
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => role = v);
                },
              ),
              if (needsOrg) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: organizationId,
                  decoration: InputDecoration(
                    labelText: _t(
                      'Organization (required for super admin)',
                      'الجهة (مطلوب للسوبر أدمن)',
                    ),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final o in widget.organizations)
                      DropdownMenuItem(
                        value: o.id,
                        child: Text(
                          o.nameFor(widget.language).isNotEmpty
                              ? o.nameFor(widget.language)
                              : (o.nameAr.isNotEmpty ? o.nameAr : o.nameEn),
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => organizationId = v),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: InputDecoration(
                  labelText: _t('Note (optional)', 'ملاحظة (اختياري)'),
                  border: OutlineInputBorder(),
                ),
              ),
              if (needsSites) ...[
                const SizedBox(height: 12),
                Text(
                  _t(
                    'Sites and checklists (at least one required)',
                    'المواقع وقوائم الفحص (مطلوب واحد على الأقل)',
                  ),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 220,
                  child: ListView(
                    children: [
                      for (final s in widget.sites)
                        CheckboxListTile(
                          dense: true,
                          value: selected.contains(s.id),
                          title: Text(
                            s.isCampus
                                ? s.nameFor(widget.language)
                                : '${s.buildingCode} — ${s.nameFor(widget.language)}',
                          ),
                          subtitle: Text(
                            s.isCampus
                                ? _t(
                                    'Campus · access extends to its checklists on write',
                                    'موقع · منح الوصول يوسّع للقوائم داخله عند الكتابة',
                                  )
                                : _t('Checklist', 'قائمة فحص'),
                          ),
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              selected.add(s.id);
                            } else {
                              selected.remove(s.id);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_t('Cancel', 'إلغاء')),
        ),
        FilledButton(
          onPressed: () {
            if (needsOrg &&
                (organizationId == null || organizationId!.isEmpty)) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _t(
                      'Choose an organization for the super admin',
                      'اختر جهة للسوبر أدمن',
                    ),
                  ),
                ),
              );
              return;
            }
            if (needsSites && selected.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _t(
                      'Choose at least one site',
                      'اختر موقعاً واحداً على الأقل',
                    ),
                  ),
                ),
              );
              return;
            }
            Navigator.pop(
              context,
              _ApproveResult(
                role: role,
                siteIds: selected.toList(),
                note: noteCtrl.text.trim().isEmpty
                    ? null
                    : noteCtrl.text.trim(),
                organizationId: needsOrg ? organizationId : null,
              ),
            );
          },
          child: Text(_t('Approve', 'اعتماد')),
        ),
      ],
    );
  }
}

class _SiteFlagsDialog extends ConsumerStatefulWidget {
  const _SiteFlagsDialog({
    required this.user,
    required this.allSites,
    required this.initialAccess,
    required this.language,
    required this.onSaved,
  });

  final Profile user;
  final List<ChecklistSite> allSites;
  final List<UserSiteAccess> initialAccess;
  final String language;
  final Future<void> Function() onSaved;

  @override
  ConsumerState<_SiteFlagsDialog> createState() => _SiteFlagsDialogState();
}

class _SiteFlagsDialogState extends ConsumerState<_SiteFlagsDialog> {
  bool get ar => widget.language == 'ar';
  String _t(String en, String arText) => ar ? arText : en;

  late Map<String, _FlagRow> rows;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    rows = {
      for (final a in widget.initialAccess)
        a.siteId: _FlagRow(
          selected: true,
          canRead: a.canRead,
          canWrite: a.canWrite,
          canManage: a.canManage,
          validFrom: a.validFrom?.toLocal(),
          validUntil: a.validUntil?.toLocal(),
        ),
    };
  }

  Future<void> _save() async {
    setState(() => saving = true);
    final repo = ref.read(siteRepositoryProvider);
    final existing = {for (final a in widget.initialAccess) a.siteId};
    try {
      for (final site in widget.allSites) {
        final row = rows[site.id];
        final want = row?.selected == true;
        final had = existing.contains(site.id);
        if (want && !had) {
          await repo.grantSiteAccess(
            userId: widget.user.id,
            siteId: site.id,
            canRead: row!.canRead,
            canWrite: row.canWrite,
            canManage: row.canManage,
            role: widget.user.role.dbValue,
            validFrom: row.validFrom,
            validUntil: row.validUntil,
          );
        } else if (!want && had) {
          await repo.revokeSiteAccess(userId: widget.user.id, siteId: site.id);
        } else if (want && had) {
          await repo.updateSiteAccessFlags(
            userId: widget.user.id,
            siteId: site.id,
            canRead: row!.canRead,
            canWrite: row.canWrite,
            canManage: row.canManage,
            validFrom: row.validFrom,
            validUntil: row.validUntil,
          );
        }
      }
      await widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(checkAdminUserMessage(e, widget.language))),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _t(
          'Site access — ${widget.user.email}',
          'صلاحيات المواقع — ${widget.user.email}',
        ),
      ),
      content: SizedBox(
        width: 480,
        height: (MediaQuery.sizeOf(context).height * .55).clamp(240.0, 420.0),
        child: ListView(
          children: [
            for (final s in widget.allSites)
              Builder(
                builder: (context) {
                  final row = rows.putIfAbsent(
                    s.id,
                    () => _FlagRow(
                      selected: false,
                      canRead: true,
                      canWrite: widget.user.role.defaultCanWrite,
                      canManage: widget.user.role.defaultCanManage,
                      validFrom: null,
                      validUntil: null,
                    ),
                  );
                  return Card(
                    child: Column(
                      children: [
                        CheckboxListTile(
                          value: row.selected,
                          title: Text(
                            s.isCampus
                                ? s.nameFor(widget.language)
                                : '${s.buildingCode} — ${s.nameFor(widget.language)}',
                          ),
                          subtitle: Text(
                            s.isCampus
                                ? _t('Campus', 'موقع (حرم)')
                                : _t('Checklist', 'قائمة فحص'),
                          ),
                          onChanged: (v) => setState(() {
                            row.selected = v == true;
                          }),
                        ),
                        if (row.selected)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                FilterChip(
                                  label: Text(_t('Read', 'قراءة')),
                                  selected: row.canRead,
                                  onSelected: (v) =>
                                      setState(() => row.canRead = v),
                                ),
                                FilterChip(
                                  label: Text(
                                    _t('Write / edit', 'كتابة/تعديل'),
                                  ),
                                  selected: row.canWrite,
                                  onSelected: (v) =>
                                      setState(() => row.canWrite = v),
                                ),
                                FilterChip(
                                  label: Text(_t('Manage', 'إدارة')),
                                  selected: row.canManage,
                                  onSelected: (v) =>
                                      setState(() => row.canManage = v),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate:
                                          row.validFrom ?? DateTime.now(),
                                      firstDate: DateTime.now().subtract(
                                        const Duration(days: 1),
                                      ),
                                      lastDate: DateTime.now().add(
                                        const Duration(days: 3650),
                                      ),
                                    );
                                    if (picked != null) {
                                      setState(() => row.validFrom = picked);
                                    }
                                  },
                                  icon: const Icon(Icons.play_circle_outline),
                                  label: Text(
                                    row.validFrom == null
                                        ? _t('Starts now', 'يبدأ الآن')
                                        : _t(
                                            'From ${_dateLabel(row.validFrom!)}',
                                            'من ${_dateLabel(row.validFrom!)}',
                                          ),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate:
                                          row.validUntil ??
                                          DateTime.now().add(
                                            const Duration(days: 30),
                                          ),
                                      firstDate:
                                          row.validFrom ?? DateTime.now(),
                                      lastDate: DateTime.now().add(
                                        const Duration(days: 3650),
                                      ),
                                    );
                                    if (picked != null) {
                                      setState(
                                        () => row.validUntil = DateTime(
                                          picked.year,
                                          picked.month,
                                          picked.day,
                                          23,
                                          59,
                                          59,
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.event_busy_outlined),
                                  label: Text(
                                    row.validUntil == null
                                        ? _t('No end date', 'بلا انتهاء')
                                        : _t(
                                            'Until ${_dateLabel(row.validUntil!)}',
                                            'حتى ${_dateLabel(row.validUntil!)}',
                                          ),
                                  ),
                                ),
                                if (row.validFrom != null ||
                                    row.validUntil != null)
                                  IconButton(
                                    tooltip: _t('Clear dates', 'إزالة المدة'),
                                    onPressed: () => setState(() {
                                      row.validFrom = null;
                                      row.validUntil = null;
                                    }),
                                    icon: const Icon(Icons.clear),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: Text(_t('Cancel', 'إلغاء')),
        ),
        FilledButton(
          onPressed: saving ? null : _save,
          child: Text(
            saving ? _t('Saving…', 'جاري الحفظ…') : _t('Save', 'حفظ'),
          ),
        ),
      ],
    );
  }

  String _dateLabel(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class _FlagRow {
  _FlagRow({
    required this.selected,
    required this.canRead,
    required this.canWrite,
    required this.canManage,
    required this.validFrom,
    required this.validUntil,
  });
  bool selected;
  bool canRead;
  bool canWrite;
  bool canManage;
  DateTime? validFrom;
  DateTime? validUntil;
}
