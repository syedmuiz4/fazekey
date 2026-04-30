import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/access_log.dart';
import '../providers/area_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/log_provider.dart';
import '../providers/system_provider.dart';
import '../services/firebase_service.dart';
import '../services/security_report_service.dart';
import '../widgets/app_background.dart';
import '../widgets/glass_card.dart';
import 'add_area_screen.dart';
import 'face_login_screen.dart';
import 'face_registration_screen.dart';
import 'notifications_screen.dart';
import 'welcome_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  static const route = '/dashboard';

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AreaProvider>().listen();
      final logs = context.read<LogProvider>();
      logs.listen();
      logs.syncPending();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_HomeTab(), const _AreasTab(), const _LogsTab(), const _SettingsTab()];
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('FaceKey'),
          actions: [
            IconButton(onPressed: () => Navigator.pushNamed(context, NotificationsScreen.route), icon: const Icon(Icons.notifications_rounded)),
          ],
        ),
        body: pages[_index],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.meeting_room_rounded), label: 'Areas'),
            NavigationDestination(icon: Icon(Icons.history_rounded), label: 'Logs'),
            NavigationDestination(icon: Icon(Icons.settings_rounded), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final logs = context.watch<LogProvider>().logs;
    final logProvider = context.watch<LogProvider>();
    final system = context.watch<SystemProvider>();
    final areas = context.watch<AreaProvider>().areas;
    final occupied = areas.fold<int>(0, (sum, area) => sum + area.currentOccupancy);
    final capacity = areas.fold<int>(0, (sum, area) => sum + area.capacity);

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _StatusStrip(
          lockdown: system.settings.globalLockdown,
          syncing: logProvider.syncing,
          pending: logProvider.pendingCount,
          onSync: logProvider.syncPending,
        ),
        const SizedBox(height: 12),
        FutureBuilder<Map<String, int>>(
          future: FirebaseService().dashboardStats(),
          builder: (context, snapshot) {
            final stats = snapshot.data ?? {};
            final items = [
              ('Active Today', stats['activeToday'] ?? 0, Icons.verified_rounded),
              ('Denied Access', stats['deniedAccess'] ?? 0, Icons.block_rounded),
              ('Users Registered', stats['usersRegistered'] ?? 0, Icons.group_rounded),
              ('Occupancy', occupied, Icons.people_alt_rounded),
            ];
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.25),
              itemBuilder: (_, i) => GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(items[i].$3),
                    const Spacer(),
                    Text('${items[i].$2}', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
                    Text(items[i].$1),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        GlassCard(
          child: SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                maxY: _chartMaxY(logs),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: true, horizontalInterval: 10),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, interval: 10)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) => Text(['Mon', 'Tue', 'Wed', 'Thu', 'Fri'][v.toInt().clamp(0, 4)]),
                    ),
                  ),
                ),
                barGroups: List.generate(5, (i) {
                  final day = _workWeekStart().add(Duration(days: i));
                  final count = logs.where((l) => _sameDay(l.timestamp, day)).length;
                  return BarChartGroupData(x: i, barRods: [BarChartRodData(toY: count.toDouble(), borderRadius: BorderRadius.circular(8))]);
                }),
              ),
            ),
          ),
        ),
        if (capacity > 0) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: (occupied / capacity).clamp(0, 1), minHeight: 8),
          const SizedBox(height: 6),
          Text('Real-time occupancy: $occupied / $capacity'),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: FilledButton.icon(onPressed: () => Navigator.pushNamed(context, AddAreaScreen.route), icon: const Icon(Icons.add_business_rounded), label: const Text('Add Area'))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton.tonalIcon(onPressed: () => _writeReport(context, logs), icon: const Icon(Icons.file_download_rounded), label: const Text('Report'))),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(onPressed: () => Navigator.pushNamed(context, FaceLoginScreen.route), icon: const Icon(Icons.face_rounded), label: const Text('Run Access Scan')),
      ],
    );
  }

  DateTime _workWeekStart() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - DateTime.monday));
  }

  bool _sameDay(DateTime left, DateTime right) => left.year == right.year && left.month == right.month && left.day == right.day;

  double _chartMaxY(List<AccessLog> logs) {
    var maxCount = 10;
    final start = _workWeekStart();
    for (var i = 0; i < 5; i++) {
      final day = start.add(Duration(days: i));
      final count = logs.where((l) => _sameDay(l.timestamp, day)).length;
      if (count > maxCount) maxCount = count;
    }
    return (((maxCount + 9) ~/ 10) * 10).toDouble();
  }

  Future<void> _writeReport(BuildContext context, List<AccessLog> logs) async {
    final messenger = ScaffoldMessenger.of(context);
    final file = await SecurityReportService().writePdfReport(logs);
    messenger.showSnackBar(SnackBar(content: Text('PDF report saved: ${file.path}')));
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.lockdown, required this.syncing, required this.pending, required this.onSync});

  final bool lockdown;
  final bool syncing;
  final int pending;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Chip(
          avatar: Icon(lockdown ? Icons.lock_rounded : Icons.lock_open_rounded, size: 18),
          label: Text(lockdown ? 'Global lockdown active' : 'Access normal'),
          backgroundColor: lockdown ? Colors.red.withValues(alpha: .22) : null,
        ),
        ActionChip(
          avatar: syncing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sync_rounded, size: 18),
          label: Text(pending == 0 ? 'Synced' : '$pending offline logs'),
          onPressed: syncing ? null : onSync,
        ),
      ],
    );
  }
}

class _AreasTab extends StatelessWidget {
  const _AreasTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AreaProvider>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(onPressed: () => Navigator.pushNamed(context, AddAreaScreen.route), child: const Icon(Icons.add_rounded)),
      body: RefreshIndicator(
        onRefresh: provider.refresh,
        child: ListView.separated(
          padding: const EdgeInsets.all(18),
          itemCount: provider.areas.length,
          separatorBuilder: (_, index) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final area = provider.areas[i];
            return GlassCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sensor_door_rounded),
                title: Text(area.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${area.location} - Floor ${area.floor} - Room ${area.roomNumber}\nOccupancy ${area.currentOccupancy}${area.capacity > 0 ? ' / ${area.capacity}' : ''}\nRoles: ${area.allowedRoles.isEmpty ? 'All' : area.allowedRoles.join(', ')}'),
                isThreeLine: true,
                trailing: Wrap(children: [
                  IconButton(
                    tooltip: area.active ? 'Deactivate' : 'Activate',
                    onPressed: () => provider.updateArea(area.copyWith(active: !area.active)),
                    icon: Icon(area.active ? Icons.toggle_on_rounded : Icons.toggle_off_rounded),
                  ),
                  IconButton(
                    tooltip: 'Restrict to IT and security',
                    onPressed: () => provider.updateArea(area.copyWith(allowedDepartments: const ['IT', 'Security'], allowedRoles: const ['admin', 'security'])),
                    icon: const Icon(Icons.admin_panel_settings_rounded),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LogsTab extends StatelessWidget {
  const _LogsTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LogProvider>();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search logs'), onChanged: provider.search),
        const SizedBox(height: 14),
        for (final log in provider.logs)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(log.granted ? Icons.check_circle_rounded : Icons.cancel_rounded, color: log.granted ? Colors.greenAccent : Colors.redAccent),
                title: Text(log.userName, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${log.areaName} - ${DateFormat.yMMMd().add_jm().format(log.timestamp)}\n${log.reason}'),
                isThreeLine: true,
                trailing: log.isUnknownFace && log.snapshotPath != null
                    ? TextButton(onPressed: () => _showSnapshot(context, log.snapshotPath!), child: const Text('View Snapshot'))
                    : Text(log.status.toUpperCase()),
              ),
            ),
          ),
        TextButton(onPressed: provider.loadMore, child: const Text('Load more')),
      ],
    );
  }

  void _showSnapshot(BuildContext context, String path) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unknown face snapshot'),
        content: File(path).existsSync()
            ? Image.file(File(path), fit: BoxFit.contain)
            : Text('Snapshot is no longer available on this device.\n$path'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final system = context.watch<SystemProvider>();
    final user = auth.user;
    final settings = system.settings;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        GlassCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
            title: Text(user?.name ?? 'Administrator', style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text('${user?.email ?? ''}\nRole: ${user?.role ?? 'admin'}'),
            isThreeLine: true,
            trailing: user?.hasFace == true ? const Icon(Icons.verified_rounded) : const Icon(Icons.warning_rounded),
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          value: settings.globalLockdown,
          onChanged: system.toggleLockdown,
          title: const Text('Global lockdown'),
          subtitle: const Text('Immediately denies all face scans'),
          secondary: const Icon(Icons.emergency_rounded),
        ),
        SwitchListTile(
          value: settings.afterHoursAlerts,
          onChanged: system.toggleAfterHoursAlerts,
          title: const Text('After-hours alerts'),
          subtitle: Text('${settings.afterHoursStart}:00 to ${settings.afterHoursEnd}:00'),
          secondary: const Icon(Icons.notifications_active_rounded),
        ),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                value: settings.afterHoursStart,
                decoration: const InputDecoration(labelText: 'Alert start'),
                items: List.generate(24, (h) => DropdownMenuItem(value: h, child: Text('$h:00'))),
                onChanged: (v) {
                  if (v != null) system.updateAfterHours(start: v, end: settings.afterHoursEnd);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: settings.afterHoursEnd,
                decoration: const InputDecoration(labelText: 'Alert end'),
                items: List.generate(24, (h) => DropdownMenuItem(value: h, child: Text('$h:00'))),
                onChanged: (v) {
                  if (v != null) system.updateAfterHours(start: settings.afterHoursStart, end: v);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SettingTile(icon: Icons.account_circle_rounded, title: 'Account', subtitle: user?.department ?? ''),
        _SettingTile(icon: Icons.face_retouching_natural_rounded, title: 'Re-enroll Face Data', subtitle: user?.hasFace == true ? 'Refresh recognition profile' : 'Register face profile', onTap: () => Navigator.pushNamed(context, FaceRegistrationScreen.route)),
        _SettingTile(icon: Icons.notifications_active_rounded, title: 'Notifications', subtitle: 'Realtime Firestore alerts', onTap: () => Navigator.pushNamed(context, NotificationsScreen.route)),
        const _SettingTile(icon: Icons.backup_rounded, title: 'Backup', subtitle: 'Offline logs sync automatically'),
        const _SettingTile(icon: Icons.memory_rounded, title: 'System', subtitle: 'ML Kit + MobileFaceNet 192D'),
        SwitchListTile(value: auth.darkMode, onChanged: auth.toggleDarkMode, title: const Text('Dark mode'), secondary: const Icon(Icons.dark_mode_rounded)),
        FilledButton.tonalIcon(
          onPressed: auth.loading
              ? null
              : () async {
                  final ok = await auth.logout();
                  if (!ok) return;
                  if (!context.mounted) return;
                  Navigator.pushNamedAndRemoveUntil(context, WelcomeScreen.route, (_) => false);
                },
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Logout'),
        ),
      ],
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({required this.icon, required this.title, required this.subtitle, this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(leading: Icon(icon), title: Text(title), subtitle: Text(subtitle), onTap: onTap);
}
