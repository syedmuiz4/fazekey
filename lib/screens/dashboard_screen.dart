import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../models/access_log.dart';
import '../models/area.dart';
import '../models/app_user.dart';
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

const _levels = [1, 2, 3];
const _fallbackDepartments = [
  'Software Engineering',
  'Information Security',
  'Multimedia',
];

List<String> _departmentsForLevel(List<Area> areas, int level) {
  final floor = 'Level $level';
  final departments = areas
      .where((area) => area.active && area.floor.trim().toLowerCase() == floor.toLowerCase())
      .expand((area) => area.allowedDepartments)
      .map((department) => department.trim())
      .where((department) => department.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return departments.isEmpty ? _fallbackDepartments : departments;
}

List<String> _restrictedAreasForLevel(List<Area> areas, int level) {
  final floor = 'Level $level';
  final names = areas
      .where((area) => area.active && area.floor.trim().toLowerCase() == floor.toLowerCase())
      .map((area) => area.name.trim().isEmpty ? '$floor - Room ${area.roomNumber}' : area.name.trim())
      .toSet()
      .toList()
    ..sort();
  return names;
}

String? _firstDepartmentForLevel(List<Area> areas, int level) {
  final options = _departmentsForLevel(areas, level);
  return options.isEmpty ? null : options.first;
}

String? _firstRestrictedAreaForLevel(List<Area> areas, int level) {
  final options = _restrictedAreasForLevel(areas, level);
  return options.isEmpty ? null : options.first;
}

String? _selectedOption(List<String> options, String? selected) {
  if (options.isEmpty) return null;
  return selected != null && options.contains(selected) ? selected : options.first;
}

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
        const SizedBox(height: 4),
        Center(
          child: Image.asset(
            'assets/images/logo1.png',
            width: 220.0,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
        const SizedBox(height: 18),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF22D3EE), Color(0xFFA855F7)],
          ).createShader(bounds),
          child: Text(
            'FaceKey',
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              textStyle: Theme.of(context).textTheme.displaySmall,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Human-centric campus security with intelligent face access and real-time awareness.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .7),
                ),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 18),
        _StatusStrip(
          lockdown: system.settings.globalLockdown,
          syncing: logProvider.syncing,
          pending: logProvider.pendingCount,
          onSync: logProvider.syncPending,
          onLockdownChanged: system.toggleLockdown,
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
                minY: 0,
                maxY: 50,
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: true, horizontalInterval: 10),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: 10,
                      getTitlesWidget: (value, _) => Text(value.toInt().toString()),
                    ),
                  ),
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
          LinearProgressIndicator(value: (occupied / capacity).clamp(0, 1), minHeight: 8),
          const SizedBox(height: 6),
          Text('Real-time occupancy: $occupied / $capacity'),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: FilledButton(onPressed: () => Navigator.pushNamed(context, AddAreaScreen.route), child: const Text('Add Area'))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton.tonal(onPressed: () => _writeReport(context, logs), child: const Text('Report'))),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(onPressed: () => Navigator.pushNamed(context, FaceLoginScreen.route), child: const Text('Run Access Scan')),
      ],
    );
  }

  DateTime _workWeekStart() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - DateTime.monday));
  }

  bool _sameDay(DateTime left, DateTime right) => left.year == right.year && left.month == right.month && left.day == right.day;

  Future<void> _writeReport(BuildContext context, List<AccessLog> logs) async {
    final messenger = ScaffoldMessenger.of(context);
    final file = await SecurityReportService().writePdfReport(logs);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _ReportSummary(logs: logs, filePath: file.path),
    );
    messenger.showSnackBar(SnackBar(content: Text('PDF report saved: ${file.path}')));
  }

  static const _barColors = [
    Color(0xFF5B8DEF),
    Color(0xFF00B894),
    Color(0xFFFDCB6E),
    Color(0xFFE17055),
    Color(0xFFA29BFE),
  ];
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.lockdown,
    required this.syncing,
    required this.pending,
    required this.onSync,
    required this.onLockdownChanged,
  });

  final bool lockdown;
  final bool syncing;
  final int pending;
  final VoidCallback onSync;
  final ValueChanged<bool> onLockdownChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterChip(
          selected: lockdown,
          label: Text(lockdown ? 'Access: Lockdown' : 'Access: Normal'),
          selectedColor: Colors.red.withValues(alpha: .22),
          onSelected: onLockdownChanged,
        ),
        ActionChip(
          label: _SyncLabel(syncing: syncing, pending: pending),
          onPressed: syncing ? null : onSync,
        ),
      ],
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
      highlightColor: Theme.of(context).colorScheme.primary.withValues(alpha: .42),
      period: const Duration(milliseconds: 1600),
      child: Text('Synced', style: base),
    );
  }
}

class _ReportSummary extends StatelessWidget {
  const _ReportSummary({required this.logs, required this.filePath});

  final List<AccessLog> logs;
  final String filePath;

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
          Text('Security Report', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
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
          const SizedBox(height: 12),
          Text(filePath, style: Theme.of(context).textTheme.bodySmall),
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
            final occupancyValue = (area.currentOccupancy / capacity).clamp(0.0, 1.0);
            return Opacity(
              opacity: area.active ? 1 : .5,
              child: GlassCard(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(area.name, style: const TextStyle(fontWeight: FontWeight.w800)),
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
                            onChanged: (value) => provider.updateArea(area.copyWith(active: value)),
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
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .58),
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
        TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search logs'), onChanged: provider.search),
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
              child: _LogCard(log: log, onSnapshot: () => _showSnapshot(context, log.snapshotPath!)),
            ),
        ],
        TextButton(onPressed: provider.loadMore, child: const Text('Load more')),
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
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: File(path).existsSync()
                      ? InteractiveViewer(child: Image.file(File(path), fit: BoxFit.contain))
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
    final statusColor = log.granted ? const Color(0xFF32D583) : const Color(0xFFFF5B66);
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
                          Text(log.userName, style: const TextStyle(fontWeight: FontWeight.w800)),
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
                      TextButton(onPressed: onSnapshot, child: const Text('View Snapshot'))
                    else
                      Text(
                        log.status.toUpperCase(),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: statusColor, fontWeight: FontWeight.w900),
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
    final logs = context.watch<LogProvider>();
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
                    Text(user?.name ?? 'Administrator', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(user?.email ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Text('${user?.department ?? 'Security'} - ${user?.room ?? 'Control'}', style: Theme.of(context).textTheme.bodySmall),
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
                title: const Text('After-hours Monitoring'),
                subtitle: Text(settings.afterHoursAlerts ? 'Active: ${_time(settings.afterHoursStart)} - ${_time(settings.afterHoursEnd)}' : 'Paused'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: settings.intrusionAlerts,
                onChanged: system.toggleIntrusionAlerts,
                title: const Text('Intrusion Alerts'),
                subtitle: Text(settings.intrusionAlerts ? 'Unknown and denied attempts are flagged' : 'Intrusion notifications are paused'),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Monitoring Window'),
                subtitle: Text('${_time(settings.afterHoursStart)} - ${_time(settings.afterHoursEnd)}'),
                onTap: () => _showMonitoringWindow(context, system),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SettingTile(
          title: 'Edit Profile',
          subtitle: 'Update your name, department, phone, and area',
          onTap: user == null ? null : () => _showEditProfile(context, auth, user),
        ),
        _SettingTile(title: 'Re-enroll Face Data', subtitle: user?.hasFace == true ? 'Refresh recognition profile' : 'Register face profile', onTap: () => Navigator.pushNamed(context, FaceRegistrationScreen.route)),
        _SettingTile(
          title: 'Change Password',
          subtitle: user?.email == null ? 'No account email available' : 'Send reset link to ${user!.email}',
          onTap: auth.loading
              ? null
              : () async {
                  final ok = await auth.sendPasswordReset();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ok ? 'Password reset email sent.' : auth.error ?? 'Unable to send password reset email.')),
                  );
                },
        ),
        _SettingTile(
          title: 'Help & Support',
          subtitle: 'View support details and troubleshooting steps',
          onTap: () => _showHelpSupport(context, logs),
        ),
        SwitchListTile(value: auth.darkMode, onChanged: auth.toggleDarkMode, title: const Text('Dark mode')),
        FilledButton.tonal(
          onPressed: auth.loading
              ? null
              : () async {
                  final ok = await auth.logout();
                  if (!ok) return;
                  if (!context.mounted) return;
                  Navigator.pushNamedAndRemoveUntil(context, WelcomeScreen.route, (_) => false);
                },
          child: const Text('Logout'),
        ),
      ],
    );
  }

  String _time(int hour) => '${hour.toString().padLeft(2, '0')}:00';

  Future<void> _showMonitoringWindow(BuildContext context, SystemProvider system) async {
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
                Text('After-hours Window', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: start,
                        decoration: const InputDecoration(labelText: 'Start'),
                        items: List.generate(24, (h) => DropdownMenuItem(value: h, child: Text(_time(h)))),
                        onChanged: (value) {
                          if (value != null) setSheetState(() => start = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: end,
                        decoration: const InputDecoration(labelText: 'End'),
                        items: List.generate(24, (h) => DropdownMenuItem(value: h, child: Text(_time(h)))),
                        onChanged: (value) {
                          if (value != null) setSheetState(() => end = value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      await system.updateAfterHours(start: start, end: end);
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('Save Window'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEditProfile(BuildContext context, AuthProvider auth, AppUser user) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _EditProfileSheet(auth: auth, user: user),
    );
  }

  Future<void> _showHelpSupport(BuildContext context, LogProvider logs) {
    final syncText = logs.pendingCount > 0 ? '${logs.pendingCount} local records are waiting to sync.' : 'Local activity is synced.';
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Help & Support', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            Text('For access issues, re-enroll face data and confirm your assigned restricted area.'),
            const SizedBox(height: 8),
            Text(syncText),
            if (logs.error != null) ...[
              const SizedBox(height: 8),
              Text(logs.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: logs.syncing ? null : logs.syncPending,
                child: Text(logs.syncing ? 'Syncing' : 'Sync Activity'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({required this.auth, required this.user});

  final AuthProvider auth;
  final AppUser user;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late int _level;
  String? _department;
  String? _area;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.user.name);
    _phone = TextEditingController(text: widget.user.phone);
    _department = widget.user.department;
    _area = widget.user.room;
    _level = _levelFromRoom(widget.user.room) ?? 1;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final areas = context.watch<AreaProvider>().areas;
    final departmentOptions = _departmentsForLevel(areas, _level);
    final selectedDepartment = _selectedOption(departmentOptions, _department);
    final areaOptions = _restrictedAreasForLevel(areas, _level);
    final selectedArea = _selectedOption(areaOptions, _area);
    _syncSelection(department: selectedDepartment, area: selectedArea);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit Profile', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Name'), validator: _required),
            const SizedBox(height: 12),
            _LevelDropdown(
              value: _level,
              onChanged: (level) => setState(() {
                _level = level;
                _department = _firstDepartmentForLevel(areas, level);
                _area = _firstRestrictedAreaForLevel(areas, level);
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('edit-department-$_level-$selectedDepartment'),
              initialValue: selectedDepartment,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Department'),
              validator: _required,
              items: departmentOptions
                  .map(
                    (department) => DropdownMenuItem(
                      value: department,
                      child: Text(department, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _department = value),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone'), validator: _required),
            const SizedBox(height: 12),
            if (selectedArea == null)
              Text(
                'No restricted areas configured for Level $_level.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              )
            else
              DropdownButtonFormField<String>(
                key: ValueKey('edit-area-$_level-$selectedArea'),
                initialValue: selectedArea,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Restricted Area'),
                validator: _required,
                items: areaOptions
                    .map(
                      (area) => DropdownMenuItem(
                        value: area,
                        child: Text(area, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _area = value),
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: selectedArea == null
                    ? null
                    : () async {
                        if (!_form.currentState!.validate()) return;
                        final ok = await widget.auth.updateProfile(
                          name: _name.text,
                          department: selectedDepartment ?? '',
                          phone: _phone.text,
                          room: selectedArea,
                        );
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(ok ? 'Profile updated.' : widget.auth.error ?? 'Unable to update profile.')),
                        );
                      },
                child: const Text('Save Profile'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _required(String? value) => value == null || value.trim().isEmpty ? 'Required' : null;

  int? _levelFromRoom(String room) {
    final match = RegExp(r'Level\s+(\d+)', caseSensitive: false).firstMatch(room);
    return int.tryParse(match?.group(1) ?? '');
  }

  void _syncSelection({required String? department, required String? area}) {
    if (_department == department && _area == area) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || (_department == department && _area == area)) return;
      setState(() {
        _department = department;
        _area = area;
      });
    });
  }
}

class _LevelDropdown extends StatelessWidget {
  const _LevelDropdown({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Level'),
      items: _levels.map((level) => DropdownMenuItem(value: level, child: Text('Level $level'))).toList(),
      onChanged: (level) {
        if (level != null) onChanged(level);
      },
    );
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
  const _SettingTile({required this.title, required this.subtitle, this.onTap});
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(title: Text(title), subtitle: Text(subtitle), onTap: onTap);
}
