import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/access_log.dart';
import '../models/app_user.dart';
import '../providers/alert_provider.dart';
import '../providers/area_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/log_provider.dart';
import '../providers/system_provider.dart';
import '../services/firebase_service.dart';
import '../services/security_report_service.dart';
import '../services/user_data_export_service.dart';
import '../widgets/app_background.dart';
import '../widgets/glass_card.dart';
import 'add_area_screen.dart';
import 'edit_profile_screen.dart';
import 'face_login_screen.dart';
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
    final pages = [
      _HomeTab(),
      const _AreasTab(),
      const _LogsTab(),
      const _SettingsTab(),
    ];
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('FaceKey'),
          actions: [
            Consumer<AlertProvider>(
              builder: (context, alerts, _) {
                final count = alerts.unreadCount;
                return IconButton(
                  onPressed: () =>
                      Navigator.pushNamed(context, NotificationsScreen.route),
                  icon: Badge(
                    isLabelVisible: count > 0,
                    label: Text(count > 99 ? '99+' : '$count'),
                    child: const Icon(Icons.notifications_rounded),
                  ),
                );
              },
            ),
          ],
        ),
        body: pages[_index],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.meeting_room_rounded),
              label: 'Areas',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_rounded),
              label: 'Logs',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
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
    final user = context.watch<AuthProvider>().user;
    final areas = context.watch<AreaProvider>().areas;
    final occupied = areas.fold<int>(
      0,
      (sum, area) => sum + area.currentOccupancy,
    );
    final capacity = areas.fold<int>(0, (sum, area) => sum + area.capacity);

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _ConsoleHeader(
          name: user?.name ?? 'Administrator',
          lockdown: system.settings.globalLockdown,
          syncing: logProvider.syncing,
          pending: logProvider.pendingCount,
          onSync: logProvider.syncPending,
          onLockdownChanged: system.toggleLockdown,
          onEmergencySos: system.activateEmergencyLockdown,
        ),
        const SizedBox(height: 16),
        FutureBuilder<Map<String, int>>(
          future: FirebaseService().dashboardStats(),
          builder: (context, snapshot) {
            final stats = snapshot.data ?? {};
            final items = [
              (
                'Active Today',
                stats['activeToday'] ?? 0,
                Icons.verified_rounded,
              ),
              (
                'Denied Access',
                stats['deniedAccess'] ?? 0,
                Icons.block_rounded,
              ),
              (
                'Users Registered',
                stats['usersRegistered'] ?? 0,
                Icons.group_rounded,
              ),
              ('Occupancy', occupied, Icons.people_alt_rounded),
            ];
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.25,
              ),
              itemBuilder: (_, i) => GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(items[i].$3),
                    const Spacer(),
                    Text(
                      '${items[i].$2}',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
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
                minY: 0,
                maxY: 50,
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: true, horizontalInterval: 10),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: 10,
                      getTitlesWidget: (value, _) =>
                          Text(value.toInt().toString()),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) => Text(
                        ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'][v.toInt().clamp(
                          0,
                          4,
                        )],
                      ),
                    ),
                  ),
                ),
                barGroups: List.generate(5, (i) {
                  final day = _workWeekStart().add(Duration(days: i));
                  final count = logs
                      .where((l) => _sameDay(l.timestamp, day))
                      .length;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: count.clamp(0, 50).toDouble(),
                        color: _barColors[i],
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ),
        if (capacity > 0) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: (occupied / capacity).clamp(0, 1),
            minHeight: 8,
          ),
          const SizedBox(height: 6),
          Text('Real-time occupancy: $occupied / $capacity'),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: () =>
                    Navigator.pushNamed(context, AddAreaScreen.route),
                child: const Text('Add Area'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonal(
                onPressed: () => _exportUserData(context),
                child: const Text('Export User Data'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: () => _writeReport(context, logs),
          child: const Text('Export Security Report'),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: () => Navigator.pushNamed(context, FaceLoginScreen.route),
          child: const Text('Run Access Scan'),
        ),
      ],
    );
  }

  DateTime _workWeekStart() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - DateTime.monday));
  }

  bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  Future<void> _writeReport(BuildContext context, List<AccessLog> logs) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await SecurityReportService().writeCsvReport(logs);
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Security report ready to share.'),
        ),
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'FAZEKEY Security Report',
          text: 'FAZEKEY security report',
        ),
      );
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => _ReportSummary(logs: logs),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to export security report: $e')),
      );
    }
  }

  Future<void> _exportUserData(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final users = await FirebaseService().getAllUsers();
      final file = await UserDataExportService().writeCsv(users);
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('User data export saved and ready to share.'),
        ),
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'FAZEKEY User Data Export',
          text: 'FAZEKEY user data export',
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to export user data: $e')),
      );
    }
  }

  static const _barColors = [
    Color(0xFF5B8DEF),
    Color(0xFF00B894),
    Color(0xFFFDCB6E),
    Color(0xFFE17055),
    Color(0xFFA29BFE),
  ];
}

class _ConsoleHeader extends StatelessWidget {
  const _ConsoleHeader({
    required this.name,
    required this.lockdown,
    required this.syncing,
    required this.pending,
    required this.onSync,
    required this.onLockdownChanged,
    required this.onEmergencySos,
  });

  final String name;
  final bool lockdown;
  final bool syncing;
  final int pending;
  final VoidCallback onSync;
  final ValueChanged<bool> onLockdownChanged;
  final Future<void> Function() onEmergencySos;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome, $name',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          StreamBuilder<DateTime>(
            stream: Stream.periodic(
              const Duration(seconds: 1),
              (_) => DateTime.now(),
            ),
            initialData: DateTime.now(),
            builder: (context, snapshot) {
              final now = snapshot.data ?? DateTime.now();
              return Text(
                '${DateFormat('EEEE, MMMM d, yyyy').format(now)} - ${DateFormat.jm().format(now)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE11D48),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: onEmergencySos,
              child: const Text(
                'EMERGENCY SOS',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _StatusChip(
                  icon: lockdown
                      ? Icons.lock_rounded
                      : Icons.verified_user_rounded,
                  label: Text(lockdown ? 'Access: Lockdown' : 'Access: Normal'),
                  color: lockdown
                      ? const Color(0xFFFF5B66)
                      : const Color(0xFF32D583),
                  onTap: () => onLockdownChanged(!lockdown),
                ),
                const SizedBox(width: 8),
                _StatusChip(
                  icon: pending > 0
                      ? Icons.cloud_upload_rounded
                      : Icons.cloud_done_rounded,
                  label: _SyncLabel(syncing: syncing, pending: pending),
                  color: pending > 0
                      ? const Color(0xFFFDB022)
                      : const Color(0xFF22D3EE),
                  onTap: syncing ? null : onSync,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final Widget label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, color: color, size: 18),
      label: label,
      onPressed: onTap,
      side: BorderSide(color: color.withValues(alpha: .34)),
      backgroundColor: color.withValues(alpha: .12),
      labelStyle: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

class _SyncLabel extends StatelessWidget {
  const _SyncLabel({required this.syncing, required this.pending});

  final bool syncing;
  final int pending;

  @override
  Widget build(BuildContext context) {
    if (pending > 0) return Text('$pending offline logs');
    if (syncing) return const Text('Syncing');
    final base = Theme.of(context).textTheme.labelLarge ?? const TextStyle();
    return Shimmer.fromColors(
      baseColor: base.color ?? Theme.of(context).colorScheme.onSurfaceVariant,
      highlightColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: .42),
      period: const Duration(milliseconds: 1600),
      child: Text('Synced', style: base),
    );
  }
}

class _ReportSummary extends StatelessWidget {
  const _ReportSummary({required this.logs});

  final List<AccessLog> logs;

  @override
  Widget build(BuildContext context) {
    final denied = logs.where((log) => !log.granted).length;
    final unknown = logs.where((log) => log.isUnknownFace).length;
    final granted = logs.where((log) => log.granted).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Security Report',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('Total ${logs.length}')),
              Chip(label: Text('Granted $granted')),
              Chip(label: Text('Denied $denied')),
              Chip(label: Text('Unknown $unknown')),
            ],
          ),
        ],
      ),
    );
  }
}

class _AreasTab extends StatelessWidget {
  const _AreasTab();

  static const _normalStatusColor = Color(0xFF5B8DEF);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AreaProvider>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, AddAreaScreen.route),
        label: const Text('Add Area'),
      ),
      body: RefreshIndicator(
        onRefresh: provider.refresh,
        child: ListView.separated(
          padding: const EdgeInsets.all(18),
          itemCount: provider.areas.length,
          separatorBuilder: (_, index) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final area = provider.areas[i];
            final capacity = area.capacity <= 0 ? 1 : area.capacity;
            final occupancyValue = (area.currentOccupancy / capacity).clamp(
              0.0,
              1.0,
            );
            return Opacity(
              opacity: area.active ? 1 : .5,
              child: GlassCard(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        area.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${area.location} - ${area.floor} - Room ${area.roomNumber}\n'
                        'Occupancy ${area.currentOccupancy}${area.capacity > 0 ? ' / ${area.capacity}' : ''}\n'
                        'Roles: ${area.allowedRoles.isEmpty ? 'All' : area.allowedRoles.join(', ')}',
                      ),
                      isThreeLine: true,
                      trailing: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Switch(
                            value: area.active,
                            onChanged: (value) => provider.updateArea(
                              area.copyWith(active: value),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: occupancyValue,
                        minHeight: 4,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: .58),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          _normalStatusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LogsTab extends StatefulWidget {
  const _LogsTab();

  @override
  State<_LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<_LogsTab> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LogProvider>();
    final logs = _filteredLogs(provider.logs);
    final grouped = _groupLogs(logs);
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'Search logs',
          ),
          onChanged: provider.search,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final label in const ['All', 'Granted', 'Denied'])
              ChoiceChip(
                label: Text(label),
                selected: _filter == label,
                showCheckmark: false,
                onSelected: (_) => setState(() => _filter = label),
              ),
          ],
        ),
        const SizedBox(height: 16),
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
            child: Text(
              entry.key,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          for (final log in entry.value)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _LogCard(
                log: log,
                onSnapshot: () => _showSnapshot(context, log.snapshotPath!),
              ),
            ),
        ],
        TextButton(
          onPressed: provider.loadMore,
          child: const Text('Load more'),
        ),
      ],
    );
  }

  List<AccessLog> _filteredLogs(List<AccessLog> logs) {
    if (_filter == 'Granted') return logs.where((log) => log.granted).toList();
    if (_filter == 'Denied') return logs.where((log) => !log.granted).toList();
    return logs;
  }

  Map<String, List<AccessLog>> _groupLogs(List<AccessLog> logs) {
    final grouped = <String, List<AccessLog>>{};
    for (final log in logs) {
      grouped.putIfAbsent(_dateGroup(log.timestamp), () => []).add(log);
    }
    return grouped;
  }

  String _dateGroup(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final logDate = DateTime(timestamp.year, timestamp.month, timestamp.day);
    final difference = today.difference(logDate).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    return DateFormat.yMMMd().format(timestamp);
  }

  void _showSnapshot(BuildContext context, String path) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .78),
      builder: (_) => Dialog.fullscreen(
        backgroundColor: const Color(0xFF070A0F),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Unknown Face Snapshot',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: File(path).existsSync()
                      ? InteractiveViewer(
                          child: Image.file(File(path), fit: BoxFit.contain),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Snapshot is no longer available on this device.\n$path',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.log, required this.onSnapshot});

  final AccessLog log;
  final VoidCallback onSnapshot;

  @override
  Widget build(BuildContext context) {
    final statusColor = log.granted
        ? const Color(0xFF32D583)
        : const Color(0xFFFF5B66);
    return GlassCard(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(width: 4, color: statusColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            log.userName,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${log.areaName} - ${DateFormat.jm().format(log.timestamp)}\n${log.reason}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (!log.granted && log.snapshotPath != null)
                      TextButton(
                        onPressed: onSnapshot,
                        child: const Text('View Snapshot'),
                      )
                    else
                      Text(
                        log.status.toUpperCase(),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
          child: Row(
            children: [
              _FaceAvatar(user: user),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.name ?? 'Administrator',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.email ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SwitchListTile(
                value: settings.afterHoursAlerts,
                onChanged: system.toggleAfterHoursAlerts,
                title: const Text('After Hours'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: settings.intrusionAlerts,
                onChanged: system.toggleIntrusionAlerts,
                title: const Text('Intrusion Alerts'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: settings.monitoringWindowLogging,
                onChanged: system.toggleMonitoringWindowLogging,
                title: const Text('Monitoring Window'),
              ),
              const Divider(height: 1),
              ListTile(
                title: Text(
                  'Access Window ${_time(settings.afterHoursStart)}-${_time(settings.afterHoursEnd)}',
                ),
                onTap: () => _showAccessWindow(context, system),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SettingTile(
          title: 'Edit Profile',
          onTap: () => Navigator.of(
            context,
            rootNavigator: true,
          ).pushNamed(EditProfileScreen.route),
        ),
        _SettingTile(
          title: 'Change Password',
          onTap: () => _sendPasswordReset(context, auth),
        ),
        _SettingTile(
          title: 'Help & Support',
          onTap: () => _openHelpSupport(context, settings.administratorEmail),
        ),
        SwitchListTile(
          value: auth.darkMode,
          onChanged: auth.toggleDarkMode,
          title: const Text('Dark Mode'),
        ),
        FilledButton.tonal(
          onPressed: auth.loading
              ? null
              : () async {
                  final ok = await auth.logout();
                  if (!ok) return;
                  if (!context.mounted) return;
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    WelcomeScreen.route,
                    (_) => false,
                  );
                },
          child: const Text('Logout'),
        ),
      ],
    );
  }

  String _time(int hour) => '${hour.toString().padLeft(2, '0')}:00';

  Future<void> _sendPasswordReset(
    BuildContext context,
    AuthProvider auth,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final resetEmail = auth.passwordResetEmail;
    final ok = await auth.sendPasswordReset();
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Password reset email sent to $resetEmail.'
              : auth.error ?? 'Unable to send password reset email.',
        ),
      ),
    );
  }

  Future<void> _showAccessWindow(
    BuildContext context,
    SystemProvider system,
  ) async {
    var start = system.settings.afterHoursStart;
    var end = system.settings.afterHoursEnd;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Access Window',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: start,
                        decoration: const InputDecoration(labelText: 'Start'),
                        items: List.generate(
                          24,
                          (hour) => DropdownMenuItem(
                            value: hour,
                            child: Text(_time(hour)),
                          ),
                        ),
                        onChanged: (value) async {
                          if (value != null) setSheetState(() => start = value);
                          await system.updateAfterHours(start: start, end: end);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: end,
                        decoration: const InputDecoration(labelText: 'End'),
                        items: List.generate(
                          24,
                          (hour) => DropdownMenuItem(
                            value: hour,
                            child: Text(_time(hour)),
                          ),
                        ),
                        onChanged: (value) async {
                          if (value != null) setSheetState(() => end = value);
                          await system.updateAfterHours(start: start, end: end);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openHelpSupport(
    BuildContext context,
    String administratorEmail,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri(
      scheme: 'mailto',
      path: administratorEmail.trim().isEmpty
          ? 'administrator@fazekey.app'
          : administratorEmail.trim(),
      queryParameters: const {
        'subject': 'FAZEKEY Support Request',
        'body':
            'Hello Administrator,\r\n\r\nI need assistance with FAZEKEY.\r\n\r\nRegards,',
      },
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Unable to open an email application.')),
      );
    }
  }
}

class _FaceAvatar extends StatelessWidget {
  const _FaceAvatar({required this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final photo = user?.photoUrl;
    final file = photo == null ? null : File(photo);
    final image = file != null && file.existsSync() ? FileImage(file) : null;
    return CircleAvatar(
      radius: 34,
      backgroundImage: image,
      child: image == null ? const Icon(Icons.person_rounded, size: 34) : null,
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({required this.title, this.onTap});
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) =>
      ListTile(title: Text(title), onTap: onTap);
}
