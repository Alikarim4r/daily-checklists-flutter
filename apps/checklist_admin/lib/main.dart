import 'dart:ui' as ui;

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await bootstrapSupabase();
  runApp(const ProviderScope(child: AdminRoot()));
}

class AdminRoot extends StatelessWidget {
  const AdminRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'فحص يومي — إدارة',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: ViewerPalette.orange),
        useMaterial3: true,
        scaffoldBackgroundColor: ViewerPalette.bg,
      ),
      builder: (context, child) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: ChecklistAuthGate(
        appTitle: 'إدارة الهيكل والصلاحيات',
        subtitle: 'نظام الفحص اليومي — مستخدمون وصلاحيات المواقع',
        allowedForProfile: (p) => p.canUseAdminApp,
        homeBuilder: (context, profile) => AdminShell(profile: profile),
      ),
    );
  }
}

class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key, required this.profile});
  final Profile profile;

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final showDelete = widget.profile.canDeleteInspections;
    final tabs = <Widget>[
      UsersTab(profile: widget.profile),
      if (showDelete) DeleteTab(profile: widget.profile),
      SitesTab(profile: widget.profile),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الفحص اليومي'),
        backgroundColor: ViewerPalette.slate900,
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                widget.profile.isPlatformOwner
                    ? 'مالك المنصة'
                    : widget.profile.role.labelAr,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
          IconButton(
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: tabs[tab.clamp(0, tabs.length - 1)],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab.clamp(0, tabs.length - 1),
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.people_outline),
            label: 'مستخدمون',
          ),
          if (showDelete)
            const NavigationDestination(
              icon: Icon(Icons.delete_outline),
              label: 'حذف',
            ),
          const NavigationDestination(
            icon: Icon(Icons.apartment),
            label: 'مواقع',
          ),
        ],
      ),
    );
  }
}

class UsersTab extends ConsumerStatefulWidget {
  const UsersTab({super.key, required this.profile});
  final Profile profile;

  @override
  ConsumerState<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<UsersTab> {
  List<Profile> users = [];
  List<ChecklistSite> sites = [];
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
      final siteList =
          await ref.read(siteRepositoryProvider).listChecklistSites();
      setState(() {
        users = list;
        sites = siteList;
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
        actor: widget.profile,
      ),
    );
    if (result == null) return;
    try {
      await ref.read(authRepositoryProvider).approveUser(
            userId: user.id,
            role: result.role,
            siteIds: result.siteIds,
            note: result.note,
          );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم اعتماد المستخدم')),
        );
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
      await ref.read(authRepositoryProvider).setUserStatus(
            userId: user.id,
            status: status,
          );
      await _load();
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
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('بانتظار الاعتماد')),
              ButtonSegment(value: 1, label: Text('المعتمدون')),
            ],
            selected: {segment},
            onSelectionChanged: (s) => setState(() => segment = s.first),
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
                        title: Text(
                          u.fullName.isEmpty ? u.email : u.fullName,
                        ),
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
                                !u.isPlatformOwner)
                              FilledButton(
                                onPressed: () => _approve(u),
                                child: const Text('اعتماد'),
                              ),
                            if (u.approvalStatus == ApprovalStatus.approved &&
                                !u.isPlatformOwner) ...[
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
                                !u.isPlatformOwner)
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
  });
  final UserRole role;
  final List<String> siteIds;
  final String? note;
}

class _ApproveUserDialog extends StatefulWidget {
  const _ApproveUserDialog({
    required this.user,
    required this.sites,
    required this.actor,
  });

  final Profile user;
  final List<ChecklistSite> sites;
  final Profile actor;

  @override
  State<_ApproveUserDialog> createState() => _ApproveUserDialogState();
}

class _ApproveUserDialogState extends State<_ApproveUserDialog> {
  late UserRole role;
  final selected = <String>{};
  final noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    role = UserRole.technician;
  }

  @override
  void dispose() {
    noteCtrl.dispose();
    super.dispose();
  }

  List<UserRole> get _roleChoices {
    final list = <UserRole>[
      UserRole.siteAdmin,
      UserRole.technician,
      UserRole.viewer,
    ];
    if (widget.actor.isPlatformOwner) {
      list.insert(0, UserRole.superAdmin);
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final needsSites = role != UserRole.superAdmin;
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
                value: role,
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
                  'المواقع (مطلوب واحد على الأقل)',
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
                          title: Text('${s.buildingCode} — ${s.nameAr}'),
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
          );
        } else if (!want && had) {
          await repo.revokeSiteAccess(
            userId: widget.user.id,
            siteId: site.id,
          );
        } else if (want && had) {
          await repo.updateSiteAccessFlags(
            userId: widget.user.id,
            siteId: site.id,
            canRead: row!.canRead,
            canWrite: row.canWrite,
            canManage: row.canManage,
          );
        }
      }
      await widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
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
                    ),
                  );
                  return Card(
                    child: Column(
                      children: [
                        CheckboxListTile(
                          value: row.selected,
                          title: Text('${s.buildingCode} — ${s.nameAr}'),
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
}

class _FlagRow {
  _FlagRow({
    required this.selected,
    required this.canRead,
    required this.canWrite,
    required this.canManage,
  });
  bool selected;
  bool canRead;
  bool canWrite;
  bool canManage;
}

class DeleteTab extends ConsumerStatefulWidget {
  const DeleteTab({super.key, required this.profile});
  final Profile profile;

  @override
  ConsumerState<DeleteTab> createState() => _DeleteTabState();
}

class _DeleteTabState extends ConsumerState<DeleteTab> {
  List<Inspection> records = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final list = await ref.read(inspectionRepositoryProvider).listInspections();
    setState(() {
      records = list;
      loading = false;
    });
  }

  Future<void> _delete(Inspection row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف السجل'),
        content: Text('حذف ${row.buildingCode} بتاريخ ${row.dateIso}؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(inspectionRepositoryProvider).deleteInspection(row.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return ListView.builder(
      itemCount: records.length,
      itemBuilder: (context, i) {
        final r = records[i];
        return ListTile(
          title: Text('${r.buildingCode} — ${r.dateIso}'),
          subtitle: Text(r.inspectorName),
          trailing: IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => _delete(r),
          ),
        );
      },
    );
  }
}

class SitesTab extends ConsumerStatefulWidget {
  const SitesTab({super.key, required this.profile});
  final Profile profile;

  @override
  ConsumerState<SitesTab> createState() => _SitesTabState();
}

class _SitesTabState extends ConsumerState<SitesTab> {
  List<ChecklistSite> sites = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ref
        .read(siteRepositoryProvider)
        .listChecklistSites(activeOnly: false);
    setState(() {
      sites = list;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return ListView.builder(
      itemCount: sites.length,
      itemBuilder: (context, i) {
        final s = sites[i];
        return ListTile(
          title: Text('${s.buildingCode} — ${s.nameAr}'),
          subtitle: Text('${s.pin} • ${s.checklistType}'),
          trailing: Text(s.isActive ? 'نشط' : 'موقوف'),
        );
      },
    );
  }
}
