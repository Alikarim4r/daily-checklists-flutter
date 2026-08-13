import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UsersTab extends ConsumerStatefulWidget {
  const UsersTab({super.key, required this.profile});
  final Profile profile;

  @override
  ConsumerState<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<UsersTab> {
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
      setState(() {
        users = list;
        sites = siteList;
        organizations = orgList;
      });
    } catch (e) {
      setState(() => message = e.toString());
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم اعتماد المستخدم')));
      }
    } catch (e) {
      setState(() => message = e.toString());
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
      setState(() => message = e.toString());
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
        title: const Text('إضافة مستخدم'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: 'الاسم',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'البريد',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور (8 أحرف على الأقل)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'يُنشأ الحساب بانتظار الاعتماد — ثم عيّن الدور والمواقع.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إنشاء'),
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
        const SnackBar(content: Text('تم إنشاء المستخدم — اعتمده الآن')),
      );
      if (created != null) await _approve(created);
    } catch (e) {
      setState(() => message = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final list = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('بانتظار الاعتماد')),
                    ButtonSegment(value: 1, label: Text('المعتمدون')),
                  ],
                  selected: {segment},
                  onSelectionChanged: (s) => setState(() => segment = s.first),
                ),
              ),
              if (_canCreate) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _createUser,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('إضافة'),
                ),
              ],
            ],
          ),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(message!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('لا يوجد مستخدمون في هذه القائمة'))
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final u = list[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: ListTile(
                        title: Text(u.fullName.isEmpty ? u.email : u.fullName),
                        subtitle: Text(
                          '${u.email}\n'
                          '${u.role.labelAr} • ${u.approvalStatus.labelAr}'
                          '${u.isPlatformOwner ? ' • مالك' : ''}',
                        ),
                        isThreeLine: true,
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            if (u.approvalStatus != ApprovalStatus.approved &&
                                _canActOn(u))
                              FilledButton(
                                onPressed: () => _approve(u),
                                child: const Text('اعتماد'),
                              ),
                            if (u.approvalStatus == ApprovalStatus.approved &&
                                _canActOn(u)) ...[
                              TextButton(
                                onPressed: () => _editSiteFlags(u),
                                child: const Text('صلاحيات'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    _setStatus(u, ApprovalStatus.suspended),
                                child: const Text('إيقاف'),
                              ),
                            ],
                            if (u.approvalStatus == ApprovalStatus.pending &&
                                _canActOn(u))
                              TextButton(
                                onPressed: () =>
                                    _setStatus(u, ApprovalStatus.rejected),
                                child: const Text('رفض'),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
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
  });

  final Profile user;
  final List<ChecklistSite> sites;
  final List<Organization> organizations;
  final Profile actor;

  @override
  State<_ApproveUserDialog> createState() => _ApproveUserDialogState();
}

class _ApproveUserDialogState extends State<_ApproveUserDialog> {
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
      title: Text('اعتماد — ${widget.user.email}'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<UserRole>(
                initialValue: role,
                decoration: const InputDecoration(
                  labelText: 'الدور',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final r in _roleChoices)
                    DropdownMenuItem(value: r, child: Text(r.labelAr)),
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
                  decoration: const InputDecoration(
                    labelText: 'الجهة (مطلوب للسوبر أدمن)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final o in widget.organizations)
                      DropdownMenuItem(
                        value: o.id,
                        child: Text(o.nameAr.isNotEmpty ? o.nameAr : o.nameEn),
                      ),
                  ],
                  onChanged: (v) => setState(() => organizationId = v),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (needsSites) ...[
                const SizedBox(height: 12),
                const Text(
                  'المواقع وقوائم الفحص (مطلوب واحد على الأقل)',
                  style: TextStyle(fontWeight: FontWeight.w600),
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
                                ? s.nameAr
                                : '${s.buildingCode} — ${s.nameAr}',
                          ),
                          subtitle: Text(
                            s.isCampus
                                ? 'موقع · منح الوصول يوسّع للقوائم داخله عند الكتابة'
                                : 'قائمة فحص',
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
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () {
            if (needsOrg &&
                (organizationId == null || organizationId!.isEmpty)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('اختر جهة للسوبر أدمن')),
              );
              return;
            }
            if (needsSites && selected.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('اختر موقعاً واحداً على الأقل')),
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
          child: const Text('اعتماد'),
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
    required this.onSaved,
  });

  final Profile user;
  final List<ChecklistSite> allSites;
  final List<UserSiteAccess> initialAccess;
  final Future<void> Function() onSaved;

  @override
  ConsumerState<_SiteFlagsDialog> createState() => _SiteFlagsDialogState();
}

class _SiteFlagsDialogState extends ConsumerState<_SiteFlagsDialog> {
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('صلاحيات المواقع — ${widget.user.email}'),
      content: SizedBox(
        width: 480,
        height: 420,
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
                                ? s.nameAr
                                : '${s.buildingCode} — ${s.nameAr}',
                          ),
                          subtitle: Text(
                            s.isCampus ? 'موقع (حرم)' : 'قائمة فحص',
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
                              children: [
                                FilterChip(
                                  label: const Text('قراءة'),
                                  selected: row.canRead,
                                  onSelected: (v) =>
                                      setState(() => row.canRead = v),
                                ),
                                FilterChip(
                                  label: const Text('كتابة/تعديل'),
                                  selected: row.canWrite,
                                  onSelected: (v) =>
                                      setState(() => row.canWrite = v),
                                ),
                                FilterChip(
                                  label: const Text('إدارة'),
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
                                        ? 'يبدأ الآن'
                                        : 'من ${_dateLabel(row.validFrom!)}',
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
                                        ? 'بلا انتهاء'
                                        : 'حتى ${_dateLabel(row.validUntil!)}',
                                  ),
                                ),
                                if (row.validFrom != null ||
                                    row.validUntil != null)
                                  IconButton(
                                    tooltip: 'إزالة المدة',
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
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: saving ? null : _save,
          child: Text(saving ? 'جاري الحفظ…' : 'حفظ'),
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
