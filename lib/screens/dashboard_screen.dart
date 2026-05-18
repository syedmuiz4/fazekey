import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/access_grant.dart';
import '../models/access_log.dart';
import '../models/app_user.dart';
import '../models/area.dart';
import '../providers/alert_provider.dart';
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

enum _DashboardPage { command, directory, zones, timeline, archive, settings }

enum _DirectoryMode { all, pendingReview }

enum _ZoneFilter { activeRooms, capacityUsed, liveLogs }

enum _RoomDetailView { settings, history }

enum _ArchiveFilter { all, approvals, facePending, staff, students }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  static const route = '/dashboard';

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final Key _dashboardScaffoldKey = UniqueKey();
  _DashboardPage _page = _DashboardPage.command;
  _DirectoryMode _directoryMode = _DirectoryMode.all;
  int _entryTimelineLimit = 30;
  int _registrationSignal = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AreaProvider>().listen();
      final logs = context.read<LogProvider>();
      logs.listen();
      unawaited(logs.syncPending());
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBackPressed();
      },
      child: AppBackground(
        child: Scaffold(
          key: _dashboardScaffoldKey,
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: Text(_pageTitle(page)),
            actions: [
              _NotificationBell(
                onTap: () =>
                    Navigator.pushNamed(context, NotificationsScreen.route),
              ),
              IconButton(
                tooltip: 'Sign out',
                onPressed: _signOutAndClear,
                icon: const Icon(Icons.logout_rounded),
              ),
            ],
          ),
          body: _bodyForPage(page),
          floatingActionButton: _floatingActionButton(page),
          bottomNavigationBar: NavigationBar(
            selectedIndex: page.index,
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            onDestinationSelected: (index) {
              setState(() => _page = _DashboardPage.values[index]);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_rounded),
                label: 'Command',
              ),
              NavigationDestination(
                icon: Icon(Icons.badge_rounded),
                label: 'Directory',
              ),
              NavigationDestination(
                icon: Icon(Icons.meeting_room_rounded),
                label: 'Zones',
              ),
              NavigationDestination(
                icon: Icon(Icons.terminal_rounded),
                label: 'Timeline',
              ),
              NavigationDestination(
                icon: Icon(Icons.inventory_2_rounded),
                label: 'Archive',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune_rounded),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bodyForPage(_DashboardPage page) {
    switch (page) {
      case _DashboardPage.command:
        return _CommandDashboardTab(
          onOpenDirectory: _openDirectory,
          onOpenZones: () => _selectPage(_DashboardPage.zones),
          onOpenTimeline: _openEntryTimeline,
        );
      case _DashboardPage.directory:
        return _UserDirectoryTab(
          mode: _directoryMode,
          registrationSignal: _registrationSignal,
          onModeChanged: (mode) => setState(() => _directoryMode = mode),
        );
      case _DashboardPage.zones:
        return _ZoneControlTab(onOpenTimeline: _openEntryTimeline);
      case _DashboardPage.timeline:
        return _EntryTimelineTab(initialLimit: _entryTimelineLimit);
      case _DashboardPage.archive:
        return const _UserDataArchiveTab();
      case _DashboardPage.settings:
        return _SettingsTab(onSignOut: _signOutAndClear);
    }
  }

  Widget? _floatingActionButton(_DashboardPage page) {
    if (page == _DashboardPage.directory) {
      return FloatingActionButton.extended(
        onPressed: () {
          setState(() {
            _directoryMode = _DirectoryMode.all;
            _registrationSignal++;
          });
        },
        icon: const Icon(Icons.manage_accounts_rounded),
        label: const Text('Manage Access'),
      );
    }
    if (page == _DashboardPage.zones) {
      return FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, AddAreaScreen.route),
        icon: const Icon(Icons.playlist_add_rounded),
        label: const Text('Linked Rooms'),
      );
    }
    return null;
  }

  void _selectPage(_DashboardPage page) {
    setState(() => _page = page);
  }

  void _openDirectory(_DirectoryMode mode) {
    setState(() {
      _page = _DashboardPage.directory;
      _directoryMode = mode;
    });
  }

  void _openEntryTimeline({int limit = 30}) {
    setState(() {
      _page = _DashboardPage.timeline;
      _entryTimelineLimit = limit;
    });
  }

  Future<void> _handleBackPressed() async {
    if (_page != _DashboardPage.command) {
      setState(() => _page = _DashboardPage.command);
      return;
    }
    await _signOutAndClear();
  }

  Future<void> _signOutAndClear() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.logout();
    if (!mounted || !ok) return;
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushNamedAndRemoveUntil(WelcomeScreen.route, (_) => false);
  }

  String _pageTitle(_DashboardPage page) {
    switch (page) {
      case _DashboardPage.command:
        return 'Command Dashboard';
      case _DashboardPage.directory:
        return 'User Directory';
      case _DashboardPage.zones:
        return 'Zone Control';
      case _DashboardPage.timeline:
        return 'Entry Timeline';
      case _DashboardPage.archive:
        return 'User Data Archive';
      case _DashboardPage.settings:
        return 'System Preferences';
    }
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<AlertProvider>().unreadCount;
    return IconButton(
      tooltip: 'Notifications',
      onPressed: onTap,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_rounded),
          if (unread > 0)
            Positioned(
              right: -4,
              top: -4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFE11D48),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  child: Text(
                    unread > 9 ? '9+' : '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CommandDashboardTab extends StatelessWidget {
  const _CommandDashboardTab({
    required this.onOpenDirectory,
    required this.onOpenZones,
    required this.onOpenTimeline,
  });

  final ValueChanged<_DirectoryMode> onOpenDirectory;
  final VoidCallback onOpenZones;
  final void Function({int limit}) onOpenTimeline;

  @override
  Widget build(BuildContext context) {
    final logs = context.watch<LogProvider>().logs;
    final areas = context.watch<AreaProvider>().areas;
    final firebase = context.read<FirebaseService>();
    return StreamBuilder<List<AppUser>>(
      stream: firebase.watchAllUsers(),
      builder: (context, snapshot) {
        final users = snapshot.data ?? const <AppUser>[];
        final activeToday = logs
            .where(
              (log) => log.granted && _sameDay(log.timestamp, DateTime.now()),
            )
            .length;
        final pendingReview = users.where(_needsAdminReview).length;
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth > 720 ? 4 : 2;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: constraints.maxWidth > 720 ? 1.35 : 1.18,
                  children: [
                    _CommandMetricCard(
                      title: 'Active Today',
                      value: '$activeToday',
                      icon: Icons.verified_user_rounded,
                      onTap: () => onOpenTimeline(limit: 30),
                    ),
                    _CommandMetricCard(
                      title: 'Total Users',
                      value: '${users.length}',
                      icon: Icons.groups_rounded,
                      onTap: () => onOpenDirectory(_DirectoryMode.all),
                    ),
                    _CommandMetricCard(
                      title: 'Pending Review',
                      value: '$pendingReview',
                      icon: Icons.pending_actions_rounded,
                      onTap: () =>
                          onOpenDirectory(_DirectoryMode.pendingReview),
                    ),
                    _CommandMetricCard(
                      title: 'Rooms',
                      value: '${areas.length}',
                      icon: Icons.meeting_room_rounded,
                      onTap: onOpenZones,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            _LiveLogsShortcut(onTap: () => onOpenTimeline(limit: 30)),
            const SizedBox(height: 14),
            _OperationalPulse(logs: logs, areas: areas),
          ],
        );
      },
    );
  }
}

class _CommandMetricCard extends StatelessWidget {
  const _CommandMetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _LiveLogsShortcut extends StatelessWidget {
  const _LiveLogsShortcut({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final logs = context.watch<LogProvider>().logs;
    final denied = logs.where((log) => !log.granted).length;
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const CircleAvatar(child: Icon(Icons.terminal_rounded)),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Live Logs',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
          Chip(
            avatar: const Icon(Icons.rule_rounded, size: 18),
            label: Text('${logs.length} rows'),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          Chip(
            avatar: const Icon(Icons.block_rounded, size: 18),
            label: Text('$denied denied'),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _OperationalPulse extends StatelessWidget {
  const _OperationalPulse({required this.logs, required this.areas});

  final List<AccessLog> logs;
  final List<Area> areas;

  @override
  Widget build(BuildContext context) {
    final capacity = areas.fold<int>(0, (sum, area) => sum + area.capacity);
    final occupied = areas.fold<int>(
      0,
      (sum, area) => sum + area.currentOccupancy,
    );
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Operations',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 210,
            child: BarChart(
              BarChartData(
                maxY: _chartMaxY(logs),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: true, horizontalInterval: 10),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: 10,
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, _) {
                        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
                        return Text(days[value.toInt().clamp(0, 4)]);
                      },
                    ),
                  ),
                ),
                barGroups: List.generate(5, (index) {
                  final day = _workWeekStart().add(Duration(days: index));
                  final count = logs
                      .where((log) => _sameDay(log.timestamp, day))
                      .length;
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: count.toDouble(),
                        borderRadius: BorderRadius.circular(6),
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
          if (capacity > 0) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: (occupied / capacity).clamp(0, 1),
              minHeight: 8,
              borderRadius: BorderRadius.circular(999),
            ),
            const SizedBox(height: 8),
            Text(
              'Capacity used: $occupied / $capacity',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}

class _UserDirectoryTab extends StatefulWidget {
  const _UserDirectoryTab({
    required this.mode,
    required this.registrationSignal,
    required this.onModeChanged,
  });

  final _DirectoryMode mode;
  final int registrationSignal;
  final ValueChanged<_DirectoryMode> onModeChanged;

  @override
  State<_UserDirectoryTab> createState() => _UserDirectoryTabState();
}

class _UserDirectoryTabState extends State<_UserDirectoryTab> {
  final _search = TextEditingController();
  bool _registrationOpen = false;
  late int _lastRegistrationSignal = widget.registrationSignal;

  @override
  void didUpdateWidget(covariant _UserDirectoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.registrationSignal != _lastRegistrationSignal) {
      _lastRegistrationSignal = widget.registrationSignal;
      _registrationOpen = true;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firebase = context.read<FirebaseService>();
    final areas = context.watch<AreaProvider>().areas;
    return StreamBuilder<List<AppUser>>(
      stream: firebase.watchAllUsers(),
      builder: (context, userSnapshot) {
        final users = userSnapshot.data ?? const <AppUser>[];
        return StreamBuilder<List<AccessGrant>>(
          stream: firebase.watchAccessGrants(limit: 300),
          builder: (context, grantSnapshot) {
            final grants = grantSnapshot.data ?? const <AccessGrant>[];
            final grantsByUser = <String, int>{};
            final now = DateTime.now();
            for (final grant in grants) {
              if (grant.isActiveAt(now)) {
                grantsByUser.update(
                  grant.userId,
                  (count) => count + 1,
                  ifAbsent: () => 1,
                );
              }
            }
            final filtered = _filteredUsers(users);
            return ListView(
              padding: const EdgeInsets.all(18),
              children: [
                _NewRegistrationCard(
                  areas: areas,
                  expanded: _registrationOpen,
                  onToggle: () =>
                      setState(() => _registrationOpen = !_registrationOpen),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search_rounded),
                          hintText: 'Search identities',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilterChip(
                      selected: widget.mode == _DirectoryMode.pendingReview,
                      onSelected: (selected) => widget.onModeChanged(
                        selected
                            ? _DirectoryMode.pendingReview
                            : _DirectoryMode.all,
                      ),
                      avatar: const Icon(Icons.pending_actions_rounded),
                      label: const Text('Pending'),
                    ),
                  ],
                ),
                if (userSnapshot.hasError || grantSnapshot.hasError) ...[
                  const SizedBox(height: 12),
                  _InlineError(
                    message:
                        'Directory sync is temporarily unavailable. Existing records remain visible when cached.',
                  ),
                ],
                const SizedBox(height: 12),
                if (filtered.isEmpty)
                  const _EmptyState(
                    icon: Icons.badge_rounded,
                    title: 'No identities found',
                  )
                else
                  for (final user in filtered)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _UserDirectoryCard(
                        user: user,
                        permissionCount: math.max(
                          user.assignedRooms.length,
                          grantsByUser[user.id] ?? 0,
                        ),
                        onEdit: () => _openEditPanel(context, user, areas),
                      ),
                    ),
              ],
            );
          },
        );
      },
    );
  }

  List<AppUser> _filteredUsers(List<AppUser> users) {
    final query = _search.text.trim().toLowerCase();
    return users.where((user) {
      if (widget.mode == _DirectoryMode.pendingReview &&
          !_needsAdminReview(user)) {
        return false;
      }
      if (query.isEmpty) return true;
      return [
        user.name,
        user.email,
        user.identityNumber,
        user.roleLabel,
        user.assignedRoomsLabel,
      ].join(' ').toLowerCase().contains(query);
    }).toList();
  }

  void _openEditPanel(BuildContext context, AppUser user, List<Area> areas) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _UserEditPanel(user: user, areas: areas);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }
}

class _NewRegistrationCard extends StatefulWidget {
  const _NewRegistrationCard({
    required this.areas,
    required this.expanded,
    required this.onToggle,
  });

  final List<Area> areas;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  State<_NewRegistrationCard> createState() => _NewRegistrationCardState();
}

class _NewRegistrationCardState extends State<_NewRegistrationCard> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _identity = TextEditingController();
  final _email = TextEditingController();
  final _department = TextEditingController();
  final _phone = TextEditingController();
  final List<String> _selectedRooms = [];
  String _position = 'Student';
  int _accessLevel = 2;
  DateTime _startAt = DateTime.now();
  DateTime _endAt = DateTime.now().add(const Duration(days: 90));
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _identity.dispose();
    _email.dispose();
    _department.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(child: Icon(Icons.person_add_alt_1_rounded)),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'New Registration',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                ),
              ),
              TextButton.icon(
                onPressed: widget.onToggle,
                icon: Icon(
                  widget.expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                ),
                label: const Text('Manage Access'),
              ),
            ],
          ),
          if (widget.expanded) ...[
            const SizedBox(height: 14),
            Form(
              key: _form,
              child: Column(
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Full Name'),
                    validator: _required,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _identity,
                          decoration: const InputDecoration(
                            labelText: 'Unique ID',
                          ),
                          validator: _required,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _email,
                          decoration: const InputDecoration(labelText: 'Email'),
                          validator: _required,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _department,
                          decoration: const InputDecoration(
                            labelText: 'Department',
                          ),
                          validator: _required,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _phone,
                          decoration: const InputDecoration(labelText: 'Phone'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _PositionToggle(
                    value: _position,
                    onChanged: (value) => setState(() => _position = value),
                  ),
                  const SizedBox(height: 10),
                  _RoomMultiSelectField(
                    title: 'Manage Access',
                    options: widget.areas.map(_roomLabel).toList(),
                    selected: _selectedRooms,
                    onChanged: (rooms) {
                      setState(() {
                        _selectedRooms
                          ..clear()
                          ..addAll(rooms);
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _DateButton(
                          label: 'Start',
                          value: _startAt,
                          onTap: () => _pickDate(start: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DateButton(
                          label: 'End',
                          value: _endAt,
                          onTap: () => _pickDate(start: false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: _accessLevel,
                    decoration: const InputDecoration(
                      labelText: 'Access Level',
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('Level 1')),
                      DropdownMenuItem(value: 2, child: Text('Level 2')),
                      DropdownMenuItem(value: 3, child: Text('Level 3')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _accessLevel = value);
                    },
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.verified_user_rounded),
                      label: Text(_saving ? 'Saving' : 'Save Registration'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_selectedRooms.isEmpty) {
      _showSnack('Select at least one room or add a custom room ID.');
      return;
    }
    if (!_endAt.isAfter(_startAt)) {
      _showSnack('End date must be after the start date.');
      return;
    }
    setState(() => _saving = true);
    final firebase = context.read<FirebaseService>();
    try {
      final created = await firebase.createManagedUser(
        name: _name.text,
        identityNumber: _identity.text,
        email: _email.text,
        department: _department.text,
        phone: _phone.text,
        room: _selectedRooms.first,
        rooms: _selectedRooms,
        role: 'user',
        accessLevel: _accessLevel,
        position: _position,
      );
      final assignedUser = created.copyWith(
        room: _selectedRooms.first,
        rooms: _selectedRooms,
        status: 'approved',
        position: _position,
      );
      for (final area in widget.areas) {
        if (!_selectedRooms.any(
          (room) => _sameAccessTarget(room, _roomLabel(area)),
        )) {
          continue;
        }
        await firebase.grantRoomAccess(
          user: assignedUser,
          area: area,
          startAt: _startAt,
          endAt: _endAt,
        );
      }
      await firebase.approveUserAccess(
        userId: created.id,
        room: _selectedRooms.first,
        rooms: _selectedRooms,
        accessLevel: _accessLevel,
      );
      if (!mounted) return;
      _showSnack(
        'Registration saved with ${_selectedRooms.length} room links.',
      );
      _clear();
    } catch (e) {
      if (mounted) _showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final initial = start ? _startAt : _endAt;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startAt = picked;
        if (!_endAt.isAfter(_startAt)) {
          _endAt = _startAt.add(const Duration(days: 1));
        }
      } else {
        _endAt = picked;
      }
    });
  }

  void _clear() {
    _name.clear();
    _identity.clear();
    _email.clear();
    _department.clear();
    _phone.clear();
    setState(() {
      _selectedRooms.clear();
      _position = 'Student';
      _accessLevel = 2;
      _startAt = DateTime.now();
      _endAt = DateTime.now().add(const Duration(days: 90));
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;
}

class _PositionToggle extends StatelessWidget {
  const _PositionToggle({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(
            value: 'Student',
            icon: Icon(Icons.school_rounded),
            label: Text('Student'),
          ),
          ButtonSegment(
            value: 'Staff',
            icon: Icon(Icons.work_rounded),
            label: Text('Staff'),
          ),
        ],
        selected: {value},
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.event_rounded),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('$label ${DateFormat.yMMMd().format(value)}'),
      ),
    );
  }
}

class _RoomMultiSelectField extends StatefulWidget {
  const _RoomMultiSelectField({
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final List<String> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_RoomMultiSelectField> createState() => _RoomMultiSelectFieldState();
}

class _RoomMultiSelectFieldState extends State<_RoomMultiSelectField> {
  final _search = TextEditingController();
  final _custom = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final options = widget.options
        .where(
          (option) => query.isEmpty || option.toLowerCase().contains(query),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 92),
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final room in widget.selected)
                  InputChip(
                    label: Text(room),
                    avatar: const Icon(Icons.vpn_key_rounded, size: 18),
                    onDeleted: () => _toggle(room, false),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'Search rooms',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 190),
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final option in options)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: widget.selected.any(
                      (room) => _sameAccessTarget(room, option),
                    ),
                    onChanged: (checked) => _toggle(option, checked ?? false),
                    title: Text(option),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                if (options.isEmpty)
                  const ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('No matching rooms'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _custom,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.add_location_alt_rounded),
                  hintText: 'Add custom room ID',
                ),
                onSubmitted: (_) => _addCustom(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Add custom',
              onPressed: _addCustom,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      ],
    );
  }

  void _toggle(String room, bool selected) {
    final next = [...widget.selected];
    next.removeWhere((value) => _sameAccessTarget(value, room));
    if (selected) next.add(room.trim());
    widget.onChanged(_dedupeRooms(next));
  }

  void _addCustom() {
    final room = _custom.text.trim();
    if (room.isEmpty) return;
    _custom.clear();
    widget.onChanged(_dedupeRooms([...widget.selected, room]));
  }
}

class _UserDirectoryCard extends StatelessWidget {
  const _UserDirectoryCard({
    required this.user,
    required this.permissionCount,
    required this.onEdit,
  });

  final AppUser user;
  final int permissionCount;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                child: Text(
                  user.name.trim().isEmpty
                      ? '?'
                      : user.name.trim().characters.first.toUpperCase(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  user.name.trim().isEmpty ? 'Unnamed Profile' : user.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Edit identity',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusChip(
                icon: Icons.fingerprint_rounded,
                label: _uniqueId(user),
              ),
              _RoleBadge(role: user.roleLabel),
              _FaceEnrollmentChip(enrolled: user.hasFace),
              _StatusChip(
                icon: Icons.vpn_key_rounded,
                label: '$permissionCount permissions',
              ),
            ],
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 78),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final room in user.assignedRooms)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.meeting_room_rounded, size: 17),
                      label: Text(room),
                    ),
                  if (user.assignedRooms.isEmpty)
                    const Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('No room links'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 17),
      label: Text(label),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final color = role.toLowerCase().contains('staff')
        ? const Color(0xFF2563EB)
        : const Color(0xFF0D9488);
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(Icons.shield_rounded, size: 17, color: color),
      label: Text(role),
      side: BorderSide(color: color.withValues(alpha: .30)),
      backgroundColor: color.withValues(alpha: .10),
    );
  }
}

class _FaceEnrollmentChip extends StatelessWidget {
  const _FaceEnrollmentChip({required this.enrolled});

  final bool enrolled;

  @override
  Widget build(BuildContext context) {
    final color = enrolled ? const Color(0xFF16A34A) : const Color(0xFFF59E0B);
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(Icons.circle, size: 12, color: color),
      label: Text(enrolled ? 'Face enrolled' : 'Face pending'),
    );
  }
}

class _UserEditPanel extends StatefulWidget {
  const _UserEditPanel({required this.user, required this.areas});

  final AppUser user;
  final List<Area> areas;

  @override
  State<_UserEditPanel> createState() => _UserEditPanelState();
}

class _UserEditPanelState extends State<_UserEditPanel> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _identity;
  late final TextEditingController _email;
  late final TextEditingController _department;
  late final TextEditingController _phone;
  late String _position;
  late String _status;
  late List<String> _rooms;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _name = TextEditingController(text: user.name);
    _identity = TextEditingController(text: user.identityNumber);
    _email = TextEditingController(text: user.email);
    _department = TextEditingController(text: user.department);
    _phone = TextEditingController(text: user.phone);
    _position = user.roleLabel.toLowerCase().contains('staff')
        ? 'Staff'
        : 'Student';
    _status = user.status.trim().isEmpty ? 'approved' : user.status;
    _rooms = [...user.assignedRooms];
  }

  @override
  void dispose() {
    _name.dispose();
    _identity.dispose();
    _email.dispose();
    _department.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 12,
        child: SizedBox(
          width: math.min(width * .94, 460),
          height: double.infinity,
          child: SafeArea(
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Edit Identity',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Full Name'),
                    validator: _required,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _identity,
                    decoration: const InputDecoration(labelText: 'Unique ID'),
                    validator: _required,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: _required,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _department,
                    decoration: const InputDecoration(labelText: 'Department'),
                    validator: _required,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                  const SizedBox(height: 10),
                  _PositionToggle(
                    value: _position,
                    onChanged: (value) => setState(() => _position = value),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(
                        value: 'approved',
                        child: Text('Approved'),
                      ),
                      DropdownMenuItem(
                        value: 'pending',
                        child: Text('Pending'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _status = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  _RoomMultiSelectField(
                    title: 'Manage Access',
                    options: widget.areas.map(_roomLabel).toList(),
                    selected: _rooms,
                    onChanged: (rooms) => setState(() => _rooms = rooms),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(_saving ? 'Saving' : 'Save Changes'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final updated = widget.user.copyWith(
      name: _name.text.trim(),
      identityNumber: _identity.text.trim(),
      email: _email.text.trim(),
      department: _department.text.trim(),
      phone: _phone.text.trim(),
      room: _rooms.isEmpty ? '' : _rooms.first,
      rooms: _rooms,
      role: 'User',
      position: _position,
      status: _status,
    );
    try {
      await context.read<FirebaseService>().updateUserProfile(updated);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Identity updated.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;
}

class _ZoneControlTab extends StatefulWidget {
  const _ZoneControlTab({required this.onOpenTimeline});

  final void Function({int limit}) onOpenTimeline;

  @override
  State<_ZoneControlTab> createState() => _ZoneControlTabState();
}

class _ZoneControlTabState extends State<_ZoneControlTab> {
  _ZoneFilter _filter = _ZoneFilter.activeRooms;
  String? _expandedAreaId;
  _RoomDetailView _detailView = _RoomDetailView.settings;

  @override
  Widget build(BuildContext context) {
    final areaProvider = context.watch<AreaProvider>();
    final logs = context.watch<LogProvider>().logs;
    final firebase = context.read<FirebaseService>();
    return StreamBuilder<List<AppUser>>(
      stream: firebase.watchAllUsers(),
      builder: (context, snapshot) {
        final users = snapshot.data ?? const <AppUser>[];
        final rooms = _sortedRooms(areaProvider.areas, logs);
        final activeRooms = areaProvider.areas
            .where((area) => area.active)
            .length;
        final capacity = areaProvider.areas.fold<int>(
          0,
          (sum, area) => sum + area.capacity,
        );
        final used = areaProvider.areas.fold<int>(
          0,
          (sum, area) => sum + area.currentOccupancy,
        );
        return RefreshIndicator(
          onRefresh: areaProvider.refresh,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth > 760;
                  return GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: wide ? 3 : 1,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: wide ? 2.8 : 4.4,
                    children: [
                      _ZoneMetricToggle(
                        selected: _filter == _ZoneFilter.activeRooms,
                        icon: Icons.meeting_room_rounded,
                        label: 'Active Rooms',
                        value: '$activeRooms',
                        onTap: () =>
                            setState(() => _filter = _ZoneFilter.activeRooms),
                      ),
                      _ZoneMetricToggle(
                        selected: _filter == _ZoneFilter.capacityUsed,
                        icon: Icons.speed_rounded,
                        label: 'Capacity Used',
                        value: capacity == 0
                            ? '0%'
                            : '${((used / capacity) * 100).round()}%',
                        onTap: () =>
                            setState(() => _filter = _ZoneFilter.capacityUsed),
                      ),
                      _ZoneMetricToggle(
                        selected: _filter == _ZoneFilter.liveLogs,
                        icon: Icons.terminal_rounded,
                        label: 'Live Logs',
                        value: '${logs.length}',
                        onTap: () {
                          setState(() => _filter = _ZoneFilter.liveLogs);
                          widget.onOpenTimeline(limit: 30);
                        },
                      ),
                    ],
                  );
                },
              ),
              if (areaProvider.error != null) ...[
                const SizedBox(height: 12),
                _InlineError(message: areaProvider.error!),
              ],
              const SizedBox(height: 12),
              if (rooms.isEmpty)
                const _EmptyState(
                  icon: Icons.meeting_room_rounded,
                  title: 'No linked rooms available',
                )
              else
                for (final room in rooms)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _RoomAssetCard(
                      area: room,
                      logs: logs,
                      users: users,
                      expanded: _expandedAreaId == room.id,
                      detailView: _detailView,
                      onToggle: () {
                        setState(() {
                          _expandedAreaId = _expandedAreaId == room.id
                              ? null
                              : room.id;
                          _detailView = _RoomDetailView.settings;
                        });
                      },
                      onDetailViewChanged: (view) =>
                          setState(() => _detailView = view),
                      onExport: () => _exportRoom(context, room, logs),
                      onEdit: () => _openRoomEditor(context, room),
                      onDelete: () => _deleteRoom(context, room),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  List<Area> _sortedRooms(List<Area> areas, List<AccessLog> logs) {
    final rooms = [...areas];
    switch (_filter) {
      case _ZoneFilter.activeRooms:
        rooms.sort((a, b) {
          final active = b.active.toString().compareTo(a.active.toString());
          return active == 0 ? a.name.compareTo(b.name) : active;
        });
      case _ZoneFilter.capacityUsed:
        rooms.sort((a, b) {
          final left = a.capacity <= 0 ? 0 : a.currentOccupancy / a.capacity;
          final right = b.capacity <= 0 ? 0 : b.currentOccupancy / b.capacity;
          return right.compareTo(left);
        });
      case _ZoneFilter.liveLogs:
        rooms.sort((a, b) {
          final left = _latestRoomLogTime(a, logs);
          final right = _latestRoomLogTime(b, logs);
          return right.compareTo(left);
        });
    }
    return rooms;
  }

  Future<void> _exportRoom(
    BuildContext context,
    Area area,
    List<AccessLog> logs,
  ) async {
    final roomLogs = logs.where((log) => _logBelongsToArea(log, area)).toList();
    final file = await SecurityReportService().writeCsvReport(roomLogs);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Room export saved: ${file.path}')));
  }

  Future<void> _deleteRoom(BuildContext context, Area area) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete room'),
        content: Text('Delete ${_roomLabel(area)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<AreaProvider>().deleteArea(area.id);
  }

  void _openRoomEditor(BuildContext context, Area area) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _RoomEditSheet(area: area),
    );
  }
}

class _ZoneMetricToggle extends StatelessWidget {
  const _ZoneMetricToggle({
    required this.selected,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomAssetCard extends StatelessWidget {
  const _RoomAssetCard({
    required this.area,
    required this.logs,
    required this.users,
    required this.expanded,
    required this.detailView,
    required this.onToggle,
    required this.onDetailViewChanged,
    required this.onExport,
    required this.onEdit,
    required this.onDelete,
  });

  final Area area;
  final List<AccessLog> logs;
  final List<AppUser> users;
  final bool expanded;
  final _RoomDetailView detailView;
  final VoidCallback onToggle;
  final ValueChanged<_RoomDetailView> onDetailViewChanged;
  final VoidCallback onExport;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final occupants = _occupantLogs(area, logs);
    return GlassCard(
      onTap: onToggle,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: area.active
                    ? const Color(0xFF0D9488).withValues(alpha: .14)
                    : const Color(0xFFE11D48).withValues(alpha: .12),
                child: Icon(
                  area.active ? Icons.sensor_door_rounded : Icons.lock_rounded,
                  color: area.active
                      ? const Color(0xFF0D9488)
                      : const Color(0xFFE11D48),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _roomLabel(area),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '${area.location} | ${area.floor}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Export',
                onPressed: onExport,
                icon: const Icon(Icons.file_download_rounded),
              ),
              IconButton(
                tooltip: 'Edit',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
              ),
            ],
          ),
          if (expanded) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<_RoomDetailView>(
                segments: const [
                  ButtonSegment(
                    value: _RoomDetailView.settings,
                    icon: Icon(Icons.tune_rounded),
                    label: Text('Settings'),
                  ),
                  ButtonSegment(
                    value: _RoomDetailView.history,
                    icon: Icon(Icons.history_rounded),
                    label: Text('History'),
                  ),
                ],
                selected: {detailView},
                onSelectionChanged: (selection) =>
                    onDetailViewChanged(selection.first),
              ),
            ),
            const SizedBox(height: 14),
            if (detailView == _RoomDetailView.settings)
              _RoomSettingsView(area: area, logs: logs, users: users)
            else
              _RoomHistoryView(area: area, logs: logs, occupants: occupants),
          ],
        ],
      ),
    );
  }
}

class _RoomSettingsView extends StatelessWidget {
  const _RoomSettingsView({
    required this.area,
    required this.logs,
    required this.users,
  });

  final Area area;
  final List<AccessLog> logs;
  final List<AppUser> users;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 680;
        final chart = _RoomPieChart(
          area: area,
          occupants: _occupantLogs(area, logs),
          users: users,
        );
        final controls = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CapacitySlider(area: area),
            const SizedBox(height: 12),
            _RolePolicyToggles(area: area),
          ],
        );
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 260, height: 210, child: chart),
              const SizedBox(width: 18),
              Expanded(child: controls),
            ],
          );
        }
        return Column(
          children: [
            SizedBox(height: 220, child: chart),
            const SizedBox(height: 12),
            controls,
          ],
        );
      },
    );
  }
}

class _CapacitySlider extends StatefulWidget {
  const _CapacitySlider({required this.area});

  final Area area;

  @override
  State<_CapacitySlider> createState() => _CapacitySliderState();
}

class _CapacitySliderState extends State<_CapacitySlider> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.area.capacity.clamp(0, 250).toDouble();
  }

  @override
  void didUpdateWidget(covariant _CapacitySlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.area.capacity != widget.area.capacity) {
      _value = widget.area.capacity.clamp(0, 250).toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Capacity ${_value.round()}',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        Slider(
          min: 0,
          max: 250,
          divisions: 250,
          value: _value,
          label: '${_value.round()}',
          onChanged: (value) => setState(() => _value = value),
          onChangeEnd: (value) {
            context.read<AreaProvider>().updateArea(
              widget.area.copyWith(capacity: value.round()),
            );
          },
        ),
      ],
    );
  }
}

class _RolePolicyToggles extends StatelessWidget {
  const _RolePolicyToggles({required this.area});

  final Area area;

  @override
  Widget build(BuildContext context) {
    final selected = area.allowedRoles
        .map((role) => role.trim().toLowerCase())
        .where((role) => role.isNotEmpty)
        .toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Role Policy',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              selected: selected.contains('student'),
              avatar: const Icon(Icons.school_rounded),
              label: const Text('Students'),
              onSelected: (value) => _toggle(context, 'Student', value),
            ),
            FilterChip(
              selected: selected.contains('staff'),
              avatar: const Icon(Icons.work_rounded),
              label: const Text('Staff'),
              onSelected: (value) => _toggle(context, 'Staff', value),
            ),
          ],
        ),
      ],
    );
  }

  void _toggle(BuildContext context, String role, bool value) {
    final roles = area.allowedRoles
        .where((item) => item.trim().toLowerCase() != role.toLowerCase())
        .toList();
    if (value) roles.add(role);
    context.read<AreaProvider>().updateArea(area.copyWith(allowedRoles: roles));
  }
}

class _RoomPieChart extends StatelessWidget {
  const _RoomPieChart({
    required this.area,
    required this.occupants,
    required this.users,
  });

  final Area area;
  final List<AccessLog> occupants;
  final List<AppUser> users;

  @override
  Widget build(BuildContext context) {
    final userById = {for (final user in users) user.id: user};
    var staff = 0;
    var students = 0;
    for (final log in occupants) {
      final user = userById[log.userId];
      if ((user?.roleLabel ?? '').toLowerCase().contains('staff')) {
        staff++;
      } else {
        students++;
      }
    }
    final available = math.max(area.capacity - occupants.length, 0);
    final sections = <PieChartSectionData>[
      if (staff > 0)
        PieChartSectionData(
          value: staff.toDouble(),
          title: 'Staff $staff',
          color: const Color(0xFF2563EB),
          radius: 54,
          titleStyle: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      if (students > 0)
        PieChartSectionData(
          value: students.toDouble(),
          title: 'Students $students',
          color: const Color(0xFF0D9488),
          radius: 54,
          titleStyle: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      PieChartSectionData(
        value: available <= 0 && staff == 0 && students == 0
            ? 1
            : available.toDouble(),
        title: 'Open $available',
        color: const Color(0xFF94A3B8),
        radius: 54,
        titleStyle: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    ];
    return PieChart(
      PieChartData(sections: sections, centerSpaceRadius: 30, sectionsSpace: 2),
    );
  }
}

class _RoomHistoryView extends StatelessWidget {
  const _RoomHistoryView({
    required this.area,
    required this.logs,
    required this.occupants,
  });

  final Area area;
  final List<AccessLog> logs;
  final List<AccessLog> occupants;

  @override
  Widget build(BuildContext context) {
    final roomLogs = logs.where((log) => _logBelongsToArea(log, area)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Live Occupancy',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        if (occupants.isEmpty)
          const Text('No live occupants recorded.')
        else
          for (final log in occupants.take(6))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_pin_circle_rounded),
              title: Text(log.userName),
              subtitle: Text(_preciseDate(log.timestamp)),
            ),
        const Divider(height: 24),
        const Text(
          'Server Feed',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        for (final log in roomLogs.take(6)) _CompactLogLine(log: log),
      ],
    );
  }
}

class _RoomEditSheet extends StatefulWidget {
  const _RoomEditSheet({required this.area});

  final Area area;

  @override
  State<_RoomEditSheet> createState() => _RoomEditSheetState();
}

class _RoomEditSheetState extends State<_RoomEditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _location;
  late final TextEditingController _floor;
  late final TextEditingController _room;
  late double _capacity;
  late Set<String> _roles;
  bool _active = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final area = widget.area;
    _name = TextEditingController(text: area.name);
    _location = TextEditingController(text: area.location);
    _floor = TextEditingController(text: area.floor);
    _room = TextEditingController(text: area.roomNumber);
    _capacity = area.capacity.clamp(0, 250).toDouble();
    _roles = area.allowedRoles
        .map((role) => role.trim())
        .where((role) => role.isNotEmpty)
        .toSet();
    _active = area.active;
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _floor.dispose();
    _room.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 18,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 18,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Edit Room',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Room Name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _location,
                decoration: const InputDecoration(labelText: 'Location'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _floor,
                      decoration: const InputDecoration(labelText: 'Floor'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _room,
                      decoration: const InputDecoration(labelText: 'Room'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: (value) => setState(() => _active = value),
                title: const Text('Active'),
              ),
              Text(
                'Capacity ${_capacity.round()}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Slider(
                min: 0,
                max: 250,
                divisions: 250,
                value: _capacity,
                label: '${_capacity.round()}',
                onChanged: (value) => setState(() => _capacity = value),
              ),
              const Text(
                'Role Policy',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    selected: _roles.any(
                      (role) => role.toLowerCase() == 'student',
                    ),
                    avatar: const Icon(Icons.school_rounded),
                    label: const Text('Students'),
                    onSelected: (selected) => _toggleRole('Student', selected),
                  ),
                  FilterChip(
                    selected: _roles.any(
                      (role) => role.toLowerCase() == 'staff',
                    ),
                    avatar: const Icon(Icons.work_rounded),
                    label: const Text('Staff'),
                    onSelected: (selected) => _toggleRole('Staff', selected),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(_saving ? 'Saving' : 'Save Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleRole(String role, bool selected) {
    setState(() {
      _roles.removeWhere((item) => item.toLowerCase() == role.toLowerCase());
      if (selected) _roles.add(role);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final next = widget.area.copyWith(
      name: _name.text.trim(),
      location: _location.text.trim(),
      floor: _floor.text.trim(),
      roomNumber: _room.text.trim(),
      active: _active,
      capacity: _capacity.round(),
      allowedRoles: _roles.toList(),
    );
    await context.read<AreaProvider>().updateArea(next);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);
  }
}

class _EntryTimelineTab extends StatefulWidget {
  const _EntryTimelineTab({required this.initialLimit});

  final int initialLimit;

  @override
  State<_EntryTimelineTab> createState() => _EntryTimelineTabState();
}

class _EntryTimelineTabState extends State<_EntryTimelineTab> {
  final _search = TextEditingController();
  String _status = 'all';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LogProvider>();
    final logs = _filtered(provider.logs).take(widget.initialLimit).toList();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Search timeline',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            DropdownButton<String>(
              value: _status,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'granted', child: Text('Granted')),
                DropdownMenuItem(value: 'denied', child: Text('Denied')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _status = value);
              },
            ),
          ],
        ),
        if (provider.error != null) ...[
          const SizedBox(height: 12),
          _InlineError(
            message:
                'Entry Timeline sync is delayed. Firestore will retry automatically.',
          ),
        ],
        const SizedBox(height: 12),
        if (logs.isEmpty)
          const _EmptyState(
            icon: Icons.terminal_rounded,
            title: 'No timeline entries',
          )
        else
          for (final log in logs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TimelineRow(
                log: log,
                onTap: () => _showSecurityDetail(context, log),
              ),
            ),
        TextButton.icon(
          onPressed: provider.loadMore,
          icon: const Icon(Icons.expand_more_rounded),
          label: const Text('Load more'),
        ),
      ],
    );
  }

  List<AccessLog> _filtered(List<AccessLog> logs) {
    final query = _search.text.trim().toLowerCase();
    return logs.where((log) {
      if (_status != 'all' && log.status != _status) return false;
      if (query.isEmpty) return true;
      return [
        log.userName,
        log.areaName,
        log.status,
        log.reason,
      ].join(' ').toLowerCase().contains(query);
    }).toList();
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.log, required this.onTap});

  final AccessLog log;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = log.granted
        ? const Color(0xFF16A34A)
        : const Color(0xFFE11D48);
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(
            log.granted ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${log.userName} | ${log.areaName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  _preciseDate(log.timestamp),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            log.status.toUpperCase(),
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

void _showSecurityDetail(BuildContext context, AccessLog log) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final file = log.snapshotPath == null ? null : File(log.snapshotPath!);
      final hasPhoto = file != null && file.existsSync();
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      log.granted ? 'Access Detail' : 'Security Detail',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (!log.granted)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 220,
                    width: double.infinity,
                    child: hasPhoto
                        ? Image.file(file, fit: BoxFit.cover)
                        : DecoratedBox(
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.no_photography_rounded,
                                size: 42,
                              ),
                            ),
                          ),
                  ),
                ),
              const SizedBox(height: 12),
              _DetailLine(label: 'Status', value: log.status.toUpperCase()),
              _DetailLine(label: 'User', value: log.userName),
              _DetailLine(label: 'Room', value: log.areaName),
              _DetailLine(
                label: 'Timestamp',
                value: _preciseDate(log.timestamp),
              ),
              _DetailLine(label: 'Reason', value: log.reason),
            ],
          ),
        ),
      );
    },
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(child: Text(value.isEmpty ? 'Unavailable' : value)),
        ],
      ),
    );
  }
}

class _UserDataArchiveTab extends StatefulWidget {
  const _UserDataArchiveTab();

  @override
  State<_UserDataArchiveTab> createState() => _UserDataArchiveTabState();
}

class _UserDataArchiveTabState extends State<_UserDataArchiveTab> {
  final _search = TextEditingController();
  _ArchiveFilter _filter = _ArchiveFilter.all;
  DateTime? _start;
  DateTime? _end;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firebase = context.read<FirebaseService>();
    return StreamBuilder<List<AppUser>>(
      stream: firebase.watchAllUsers(),
      builder: (context, snapshot) {
        final users = snapshot.data ?? const <AppUser>[];
        final filtered = _filtered(users);
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ArchiveFilterToggle(
                  label: 'All',
                  count: users.length,
                  selected: _filter == _ArchiveFilter.all,
                  onTap: () => setState(() => _filter = _ArchiveFilter.all),
                ),
                _ArchiveFilterToggle(
                  label: 'Approvals',
                  count: users.where((user) => user.isPending).length,
                  selected: _filter == _ArchiveFilter.approvals,
                  onTap: () =>
                      setState(() => _filter = _ArchiveFilter.approvals),
                ),
                _ArchiveFilterToggle(
                  label: 'Face Pending',
                  count: users.where((user) => !user.hasFace).length,
                  selected: _filter == _ArchiveFilter.facePending,
                  onTap: () =>
                      setState(() => _filter = _ArchiveFilter.facePending),
                ),
                _ArchiveFilterToggle(
                  label: 'Staff',
                  count: users
                      .where(
                        (user) =>
                            user.roleLabel.toLowerCase().contains('staff'),
                      )
                      .length,
                  selected: _filter == _ArchiveFilter.staff,
                  onTap: () => setState(() => _filter = _ArchiveFilter.staff),
                ),
                _ArchiveFilterToggle(
                  label: 'Students',
                  count: users
                      .where(
                        (user) =>
                            user.roleLabel.toLowerCase().contains('student'),
                      )
                      .length,
                  selected: _filter == _ArchiveFilter.students,
                  onTap: () =>
                      setState(() => _filter = _ArchiveFilter.students),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search archived profiles',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DateFilterChip(
                  label: 'Start',
                  value: _start,
                  onTap: () => _pickDate(start: true),
                  onClear: () => setState(() => _start = null),
                ),
                _DateFilterChip(
                  label: 'End',
                  value: _end,
                  onTap: () => _pickDate(start: false),
                  onClear: () => setState(() => _end = null),
                ),
              ],
            ),
            if (snapshot.hasError) ...[
              const SizedBox(height: 12),
              _InlineError(
                message:
                    'Archive sync is temporarily unavailable. Try again after Firestore finishes indexing.',
              ),
            ],
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              const _EmptyState(
                icon: Icons.inventory_2_rounded,
                title: 'No archive records found',
              )
            else
              for (final user in filtered)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        child: Icon(
                          user.hasFace
                              ? Icons.face_retouching_natural_rounded
                              : Icons.face_retouching_off_rounded,
                        ),
                      ),
                      title: Text(
                        user.name,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        '${_uniqueId(user)} | ${user.roleLabel} | ${user.status}',
                      ),
                      trailing: TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => _UserDeepDetailPage(user: user),
                          ),
                        ),
                        child: const Text('View Full Profile'),
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }

  List<AppUser> _filtered(List<AppUser> users) {
    final query = _search.text.trim().toLowerCase();
    return users.where((user) {
      if (_start != null && user.createdAt.isBefore(_start!)) return false;
      if (_end != null &&
          !user.createdAt.isBefore(_end!.add(const Duration(days: 1)))) {
        return false;
      }
      switch (_filter) {
        case _ArchiveFilter.all:
          break;
        case _ArchiveFilter.approvals:
          if (!user.isPending) return false;
        case _ArchiveFilter.facePending:
          if (user.hasFace) return false;
        case _ArchiveFilter.staff:
          if (!user.roleLabel.toLowerCase().contains('staff')) return false;
        case _ArchiveFilter.students:
          if (!user.roleLabel.toLowerCase().contains('student')) return false;
      }
      if (query.isEmpty) return true;
      return [
        user.name,
        user.email,
        user.identityNumber,
        user.roleLabel,
        user.status,
      ].join(' ').toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _pickDate({required bool start}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start
          ? (_start ?? DateTime.now())
          : (_end ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }
}

class _ArchiveFilterToggle extends StatelessWidget {
  const _ArchiveFilterToggle({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      onSelected: (_) => onTap(),
      label: Text('$label $count'),
    );
  }
}

class _DateFilterChip extends StatelessWidget {
  const _DateFilterChip({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: const Icon(Icons.event_rounded, size: 18),
      label: Text(
        value == null ? label : '$label ${DateFormat.yMMMd().format(value!)}',
      ),
      onPressed: onTap,
      onDeleted: value == null ? null : onClear,
    );
  }
}

class _UserDeepDetailPage extends StatelessWidget {
  const _UserDeepDetailPage({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final firebase = context.read<FirebaseService>();
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('View Full Profile'),
        ),
        body: StreamBuilder<List<AccessLog>>(
          stream: firebase.watchUserLogs(user.id, limit: 120),
          builder: (context, snapshot) {
            final logs = snapshot.data ?? const <AccessLog>[];
            return ListView(
              padding: const EdgeInsets.all(18),
              children: [
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _StatusChip(
                            icon: Icons.fingerprint_rounded,
                            label: _uniqueId(user),
                          ),
                          _RoleBadge(role: user.roleLabel),
                          _FaceEnrollmentChip(enrolled: user.hasFace),
                          _StatusChip(
                            icon: Icons.vpn_key_rounded,
                            label: '${user.assignedRooms.length} permissions',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (snapshot.hasError) ...[
                  const SizedBox(height: 12),
                  _InlineError(message: 'History timeline sync is delayed.'),
                ],
                const SizedBox(height: 12),
                const Text(
                  'History Timeline',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                if (logs.isEmpty)
                  const _EmptyState(
                    icon: Icons.history_rounded,
                    title: 'No scan history',
                  )
                else
                  for (final log in logs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TimelineRow(
                        log: log,
                        onTap: () => _showSecurityDetail(context, log),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.onSignOut});

  final Future<void> Function() onSignOut;

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
            title: Text(
              user?.name ?? 'Administrator',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              '${user?.email ?? ''}\nRole: ${user?.roleLabel ?? 'Admin'}',
            ),
            trailing: user?.hasFace == true
                ? const Icon(Icons.verified_rounded)
                : const Icon(Icons.warning_rounded),
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          value: settings.globalLockdown,
          onChanged: system.toggleLockdown,
          title: const Text('Global Lockdown'),
          secondary: const Icon(Icons.emergency_rounded),
        ),
        SwitchListTile(
          value: settings.afterHoursAlerts,
          onChanged: system.toggleAfterHoursAlerts,
          title: const Text('After-hours Alerts'),
          secondary: const Icon(Icons.notifications_active_rounded),
        ),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: settings.afterHoursStart,
                decoration: const InputDecoration(labelText: 'Alert Start'),
                items: List.generate(
                  24,
                  (hour) =>
                      DropdownMenuItem(value: hour, child: Text('$hour:00')),
                ),
                onChanged: (value) {
                  if (value != null) {
                    system.updateAfterHours(
                      start: value,
                      end: settings.afterHoursEnd,
                    );
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: settings.afterHoursEnd,
                decoration: const InputDecoration(labelText: 'Alert End'),
                items: List.generate(
                  24,
                  (hour) =>
                      DropdownMenuItem(value: hour, child: Text('$hour:00')),
                ),
                onChanged: (value) {
                  if (value != null) {
                    system.updateAfterHours(
                      start: settings.afterHoursStart,
                      end: value,
                    );
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SettingTile(
          icon: Icons.face_retouching_natural_rounded,
          title: 'Identity Enrollment',
          onTap: () =>
              Navigator.pushNamed(context, FaceRegistrationScreen.route),
        ),
        _SettingTile(
          icon: Icons.notifications_active_rounded,
          title: 'Notifications',
          onTap: () => Navigator.pushNamed(context, NotificationsScreen.route),
        ),
        _SettingTile(
          icon: Icons.center_focus_strong_rounded,
          title: 'Run Scanner',
          onTap: () => Navigator.pushNamed(context, FaceLoginScreen.route),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: auth.loading ? null : onSignOut,
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sign Out'),
        ),
      ],
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({required this.icon, required this.title, this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(leading: Icon(icon), title: Text(title), onTap: onTap);
  }
}

class _CompactLogLine extends StatelessWidget {
  const _CompactLogLine({required this.log});

  final AccessLog log;

  @override
  Widget build(BuildContext context) {
    final color = log.granted
        ? const Color(0xFF16A34A)
        : const Color(0xFFE11D48);
    return InkWell(
      onTap: () => _showSecurityDetail(context, log),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(Icons.circle, size: 10, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${DateFormat.Hms().format(log.timestamp)}  ${log.userName}  ${log.status}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.sync_problem_rounded,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              Icon(icon, size: 42),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ),
    );
  }
}

bool _needsAdminReview(AppUser user) =>
    user.isPending || !user.hasFace || user.hasPendingPhotoApproval;

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

DateTime _workWeekStart() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return today.subtract(Duration(days: today.weekday - DateTime.monday));
}

double _chartMaxY(List<AccessLog> logs) {
  var maxCount = 10;
  final start = _workWeekStart();
  for (var i = 0; i < 5; i++) {
    final day = start.add(Duration(days: i));
    final count = logs.where((log) => _sameDay(log.timestamp, day)).length;
    if (count > maxCount) maxCount = count;
  }
  return (((maxCount + 9) ~/ 10) * 10).toDouble();
}

String _roomLabel(Area area) {
  final name = area.name.trim();
  if (name.isNotEmpty) return name;
  final floor = area.floor.trim();
  final room = area.roomNumber.trim();
  if (floor.isNotEmpty && room.isNotEmpty) return '$floor - Room $room';
  if (room.isNotEmpty) return 'Room $room';
  return area.location.trim().isEmpty ? 'Room Asset' : area.location.trim();
}

String _uniqueId(AppUser user) {
  final identity = user.identityNumber.trim();
  if (identity.isNotEmpty) return identity;
  return user.id.length <= 8 ? user.id : user.id.substring(0, 8);
}

List<String> _dedupeRooms(Iterable<String> values) {
  final rooms = <String>[];
  for (final value in values) {
    final room = value.trim();
    if (room.isEmpty) continue;
    if (rooms.any((existing) => _sameAccessTarget(existing, room))) continue;
    rooms.add(room);
  }
  return rooms;
}

bool _sameAccessTarget(String left, String right) =>
    _accessKey(left) == _accessKey(right);

String _accessKey(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

bool _logBelongsToArea(AccessLog log, Area area) {
  if (log.areaId.trim().isNotEmpty && log.areaId == area.id) return true;
  final roomKeys = {
    area.name,
    area.roomNumber,
    _roomLabel(area),
    '${area.location} ${area.floor} ${area.roomNumber}',
  }.map(_accessKey).toSet();
  return roomKeys.contains(_accessKey(log.areaName));
}

List<AccessLog> _occupantLogs(Area area, List<AccessLog> logs) {
  final latest = <String, AccessLog>{};
  final today = DateTime.now();
  final roomLogs =
      logs
          .where((log) => log.granted && _sameDay(log.timestamp, today))
          .where((log) => _logBelongsToArea(log, area))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  for (final log in roomLogs) {
    final key = log.userId.trim().isEmpty ? log.userName : log.userId;
    latest.putIfAbsent(key, () => log);
  }
  return latest.values.toList();
}

DateTime _latestRoomLogTime(Area area, List<AccessLog> logs) {
  final roomLogs = logs.where((log) => _logBelongsToArea(log, area));
  if (roomLogs.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
  return roomLogs
      .map((log) => log.timestamp)
      .reduce((left, right) => left.isAfter(right) ? left : right);
}

String _preciseDate(DateTime date) =>
    DateFormat('EEEE, MMMM d, yyyy h:mm:ss a').format(date);
