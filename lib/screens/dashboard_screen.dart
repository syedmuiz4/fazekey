import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../constants/command_center_options.dart';
import '../models/access_grant.dart';
import '../models/access_log.dart';
import '../models/app_user.dart';
import '../models/area.dart';
import '../providers/alert_provider.dart';
import '../providers/area_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/face_provider.dart';
import '../providers/log_provider.dart';
import '../services/firebase_service.dart';
import '../services/security_report_service.dart';
import '../widgets/app_background.dart';
import '../widgets/corporate_chrome.dart';
import '../widgets/glass_card.dart';
import 'add_area_screen.dart';
import 'face_registration_screen.dart';
import 'user_dashboard_screen.dart';
import 'welcome_screen.dart';

enum _DashboardPage { command, directory, zones, timeline, settings }

enum _DirectoryMode { all, pendingReview, staff, students }

enum _ZoneFilter { activeRooms, capacityUsed, liveLogs }

enum _RoomStatusFilter { all, active, inactive }

enum _RoomDetailView { settings, history }

class _AdminText {
  const _AdminText(this.locale);

  final String locale;

  bool get _ms => locale == 'Malay';

  String get dashboard => _ms ? 'Papan Pemuka' : 'Dashboard';
  String get userDirectory => _ms ? 'Direktori Pengguna' : 'User Directory';
  String get zoneControl => _ms ? 'Kawalan Zon' : 'Zone Control';
  String get roomControl => _ms ? 'Kawalan Bilik' : 'Room Control';
  String get accessLog => _ms ? 'Log Akses' : 'Access Log';
  String get settings => _ms ? 'Tetapan' : 'Settings';
  String get signOut => _ms ? 'Log Keluar' : 'Sign Out';
  String get linkedRooms => _ms ? 'Bilik Terpaut' : 'Linked Rooms';
  String get myAccount => _ms ? 'Akaun Saya' : 'MY ACCOUNT';
  String get display => _ms ? 'Paparan' : 'DISPLAY';
  String get darkMode => _ms ? 'Mod Gelap' : 'Dark Mode';
  String get language => _ms ? 'Bahasa' : 'Language';
  String get changePassword => _ms ? 'Tukar Kata Laluan' : 'Change Password';
  String get editEmail => _ms ? 'Edit Emel' : 'Edit Email';
  String get close => _ms ? 'Tutup' : 'Close';
  String get passwordSent => _ms
      ? 'Emel tetapan semula kata laluan dihantar.'
      : 'Password reset email sent.';
  String get passwordFailed => _ms
      ? 'Tidak dapat menghantar emel tetapan semula kata laluan.'
      : 'Unable to send password reset email.';
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  static const route = '/admin_dashboard';

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final Key _dashboardScaffoldKey = UniqueKey();
  _DashboardPage _page = _DashboardPage.command;
  _DirectoryMode _directoryMode = _DirectoryMode.all;
  int _entryTimelineLimit = 30;
  final int _registrationSignal = 0;
  bool _darkMode = false;
  String _language = 'English';

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
    final auth = context.watch<AuthProvider>();
    if (!auth.loading && auth.user != null && !auth.isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(UserDashboardScreen.route, (_) => false);
      });
      return const SizedBox.shrink();
    }
    final page = _page;
    final text = _AdminText(_language);
    final baseTheme = Theme.of(context);
    final darkScheme =
        ColorScheme.fromSeed(
          seedColor: CorporateColors.teal,
          brightness: Brightness.dark,
        ).copyWith(
          primary: const Color(0xFF2DD4BF),
          secondary: const Color(0xFF38BDF8),
          surface: const Color(0xFF111827),
          surfaceContainerHighest: const Color(0xFF1F2937),
          outline: const Color(0xFF334155),
        );
    final adminTheme = _darkMode
        ? baseTheme.copyWith(
            brightness: Brightness.dark,
            colorScheme: darkScheme,
            scaffoldBackgroundColor: const Color(0xFF0F172A),
            appBarTheme: baseTheme.appBarTheme.copyWith(
              backgroundColor: AppBackground.slateGray,
              foregroundColor: Colors.white,
            ),
            switchTheme: SwitchThemeData(
              thumbColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? const Color(0xFF2DD4BF)
                    : const Color(0xFFE2E8F0),
              ),
              trackColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? const Color(0xFF0F766E)
                    : const Color(0xFF475569),
              ),
            ),
          )
        : baseTheme.copyWith(
            switchTheme: SwitchThemeData(
              thumbColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? CorporateColors.teal
                    : null,
              ),
              trackColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? CorporateColors.teal.withValues(alpha: .45)
                    : null,
              ),
            ),
          );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBackPressed();
      },
      child: Theme(
        data: adminTheme,
        child: ColoredBox(
          color: _darkMode ? const Color(0xFF0F172A) : AppBackground.slateGray,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              return Scaffold(
                key: _dashboardScaffoldKey,
                backgroundColor: _darkMode
                    ? Colors.transparent
                    : AppBackground.slateGray,
                drawer: wide
                    ? null
                    : Drawer(
                        child: _CommandSideMenu(
                          selected: page,
                          onSelect: _selectPage,
                          onSignOut: _signOutAndClear,
                          modal: true,
                          text: text,
                        ),
                      ),
                appBar: AppBar(
                  backgroundColor: _darkMode
                      ? Colors.transparent
                      : AppBackground.slateGray,
                  leading: page == _DashboardPage.timeline
                      ? IconButton(
                          tooltip: 'Back',
                          onPressed: () => _selectPage(_DashboardPage.command),
                          icon: const Icon(Icons.arrow_back_rounded),
                          /*
                        icon: const Text('←') /*
                          '←',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ), */
                        */
                        )
                      : wide
                      ? null
                      : Builder(
                          builder: (context) => IconButton(
                            tooltip: 'Open menu',
                            onPressed: () => Scaffold.of(context).openDrawer(),
                            icon: const Icon(Icons.menu_rounded),
                          ),
                        ),
                  title: Text(
                    _pageTitle(page, text),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: .35,
                    ),
                  ),
                  actions: [
                    _NotificationBell(
                      onTap: () => _showAdminNotification(context),
                    ),
                    if (page == _DashboardPage.timeline ||
                        page == _DashboardPage.settings)
                      IconButton(
                        tooltip: 'Profile',
                        onPressed: () => _selectPage(_DashboardPage.settings),
                        icon: const Icon(Icons.account_circle_rounded),
                      )
                    else
                      IconButton(
                        tooltip: 'Sign out',
                        onPressed: _signOutAndClear,
                        icon: const Icon(Icons.logout_rounded),
                      ),
                  ],
                ),
                body: wide
                    ? Row(
                        children: [
                          _CommandSideMenu(
                            selected: page,
                            onSelect: _selectPage,
                            onSignOut: _signOutAndClear,
                            modal: false,
                            text: text,
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(child: _bodyForPage(page)),
                        ],
                      )
                    : _bodyForPage(page),
                floatingActionButton: _floatingActionButton(page, text),
              );
            },
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
      case _DashboardPage.settings:
        return _SettingsTab(
          onSignOut: _signOutAndClear,
          darkMode: _darkMode,
          language: _language,
          text: _AdminText(_language),
          onDarkModeChanged: (value) => setState(() => _darkMode = value),
          onLanguageChanged: (value) => setState(() => _language = value),
        );
    }
  }

  Widget? _floatingActionButton(_DashboardPage page, _AdminText text) {
    if (page == _DashboardPage.zones) {
      return FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, AddAreaScreen.route),
        icon: const Icon(Icons.playlist_add_rounded),
        label: Text(text.linkedRooms),
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

  String _pageTitle(_DashboardPage page, _AdminText text) {
    switch (page) {
      case _DashboardPage.command:
        return text.dashboard;
      case _DashboardPage.directory:
        return text.userDirectory;
      case _DashboardPage.zones:
        return text.zoneControl;
      case _DashboardPage.timeline:
        return text.accessLog;
      case _DashboardPage.settings:
        return text.settings;
    }
  }

  Future<void> _showAdminNotification(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notifications'),
        content: const SizedBox(
          width: 420,
          child: Text(
            'Temporary screenshot alert: Room access request received.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final localUnread = context.watch<AlertProvider>().unreadCount;
    final firebase = context.read<FirebaseService>();
    return StreamBuilder(
      stream: firebase.watchUnreadAdminNotifications(),
      builder: (context, snapshot) {
        final unread = localUnread + (snapshot.data?.docs.length ?? 0);
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
      },
    );
  }
}

class _CommandSideMenu extends StatelessWidget {
  const _CommandSideMenu({
    required this.selected,
    required this.onSelect,
    required this.onSignOut,
    required this.modal,
    required this.text,
  });

  final _DashboardPage selected;
  final ValueChanged<_DashboardPage> onSelect;
  final Future<void> Function() onSignOut;
  final bool modal;
  final _AdminText text;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return SafeArea(
      child: SizedBox(
        width: 280,
        child: Material(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .88),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                child: Row(
                  children: [
                    const CircleAvatar(child: Icon(Icons.admin_panel_settings)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'FAZEKEY',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              letterSpacing: .3,
                            ),
                          ),
                          Text(
                            user?.name.trim().isNotEmpty == true
                                ? user!.name
                                : 'Command Center',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: NavigationDrawer(
                  selectedIndex: selected.index,
                  onDestinationSelected: (index) {
                    if (modal) Navigator.pop(context);
                    onSelect(_DashboardPage.values[index]);
                  },
                  children: [
                    NavigationDrawerDestination(
                      icon: const Icon(Icons.dashboard_rounded),
                      label: Text(text.dashboard),
                    ),
                    NavigationDrawerDestination(
                      icon: const Icon(Icons.badge_rounded),
                      label: Text(text.userDirectory),
                    ),
                    NavigationDrawerDestination(
                      icon: const Icon(Icons.meeting_room_rounded),
                      label: Text(text.roomControl),
                    ),
                    NavigationDrawerDestination(
                      icon: const Icon(Icons.terminal_rounded),
                      label: Text(text.accessLog),
                    ),
                    NavigationDrawerDestination(
                      icon: const Icon(Icons.tune_rounded),
                      label: Text(text.settings),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: onSignOut,
                    icon: const Icon(Icons.logout_rounded),
                    label: Text(text.signOut),
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
        final now = DateTime.now();
        final activeToday = logs
            .where(
              (log) =>
                  log.granted &&
                  log.timestamp.isAfter(
                    now.subtract(const Duration(hours: 24)),
                  ),
            )
            .length;
        final pendingReview = users.where((user) => user.isPending).length;
        final recentLogs = [...logs]
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

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
                    _FixedDashboardMetricCard(
                      label: 'Active Today',
                      value: activeToday,
                      icon: Icons.verified_user_rounded,
                      onTap: () => onOpenTimeline(limit: 30),
                    ),
                    _FixedDashboardMetricCard(
                      label: 'Total Users',
                      value: users.length,
                      icon: Icons.groups_rounded,
                      onTap: () => onOpenDirectory(_DirectoryMode.all),
                    ),
                    _FixedDashboardMetricCard(
                      label: 'Pending Review',
                      value: pendingReview,
                      icon: Icons.rate_review_rounded,
                      onTap: () =>
                          onOpenDirectory(_DirectoryMode.pendingReview),
                    ),
                    _FixedDashboardMetricCard(
                      label: 'Rooms',
                      value: areas.length,
                      icon: Icons.meeting_room_rounded,
                      onTap: onOpenZones,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 88,
              child: _RoomStatusPanel(areas: areas, onViewAll: onOpenZones),
            ),
            const SizedBox(height: 12),
            _RecentAccessLogsPanel(
              logs: recentLogs.take(3).toList(),
              onHistory: () => onOpenTimeline(limit: 30),
            ),
          ],
        );
      },
    );
  }
}

class _FixedDashboardMetricCard extends StatelessWidget {
  const _FixedDashboardMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final int value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .96),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF99F6E4)),
          boxShadow: [
            BoxShadow(
              color: CorporateColors.lightBlue.withValues(alpha: .22),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: CorporateColors.teal, size: 20),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CorporateColors.mutedText,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: .2,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '$value',
                  style: const TextStyle(
                    color: CorporateColors.text,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
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

class _RoomStatusPanel extends StatelessWidget {
  const _RoomStatusPanel({required this.areas, required this.onViewAll});

  final List<Area> areas;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF99F6E4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sensors_rounded, color: CorporateColors.teal),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Room Status',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: .25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  StreamBuilder<int>(
                    stream: Stream.periodic(
                      const Duration(seconds: 5),
                      (tick) => tick + 1,
                    ),
                    initialData: 0,
                    builder: (context, snapshot) {
                      return Text(
                        _dashboardRoomSummary(
                          areas,
                          offset: snapshot.data ?? 0,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CorporateColors.mutedText,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onViewAll, child: const Text('View All')),
          ],
        ),
      ),
    );
  }
}

class _RecentAccessLogsPanel extends StatelessWidget {
  const _RecentAccessLogsPanel({required this.logs, required this.onHistory});

  final List<AccessLog> logs;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF99F6E4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Expanded(
                  child: Text(
                    'Recent Access Logs',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: .25,
                    ),
                  ),
                ),
                TextButton(onPressed: onHistory, child: const Text('History')),
              ],
            ),
            const Divider(height: 14),
            if (logs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Center(
                  child: Text(
                    'No recent security events',
                    style: TextStyle(
                      color: CorporateColors.mutedText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            else
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final log in logs)
                    _RecentLogRow(
                      log: log,
                      onDetails: () => _showSecurityDetail(context, log),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _RecentLogRow extends StatelessWidget {
  const _RecentLogRow({required this.log, required this.onDetails});

  final AccessLog log;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final color = log.granted
        ? const Color(0xFF16A34A)
        : const Color(0xFFE11D48);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_logUserName(log)} | ${log.areaName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  '${DateFormat.jm().format(log.timestamp)} | ${log.status.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CorporateColors.mutedText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onDetails, child: const Text('Details')),
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
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _DirectoryFilterChip(
                      label: 'All',
                      selected: widget.mode == _DirectoryMode.all,
                      onTap: () => widget.onModeChanged(_DirectoryMode.all),
                    ),
                    _DirectoryFilterChip(
                      label: 'Pending',
                      selected: widget.mode == _DirectoryMode.pendingReview,
                      onTap: () =>
                          widget.onModeChanged(_DirectoryMode.pendingReview),
                    ),
                    _DirectoryFilterChip(
                      label: 'Staff',
                      selected: widget.mode == _DirectoryMode.staff,
                      onTap: () => widget.onModeChanged(_DirectoryMode.staff),
                    ),
                    _DirectoryFilterChip(
                      label: 'Students',
                      selected: widget.mode == _DirectoryMode.students,
                      onTap: () =>
                          widget.onModeChanged(_DirectoryMode.students),
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
                        onView: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _UserDeepDetailPage(user: user),
                          ),
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
      switch (widget.mode) {
        case _DirectoryMode.all:
          break;
        case _DirectoryMode.pendingReview:
          if (!_needsAdminReview(user)) return false;
        case _DirectoryMode.staff:
          if (!user.roleLabel.toLowerCase().contains('staff')) return false;
        case _DirectoryMode.students:
          if (!user.roleLabel.toLowerCase().contains('student')) return false;
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
    final firebase = context.read<FirebaseService>();
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _UserActionSheet(
        user: user,
        onScanFace: () {
          Navigator.pop(sheetContext);
          Navigator.pushNamed(
            context,
            FaceRegistrationScreen.route,
            arguments: FaceRegistrationArgs(user: user),
          );
        },
        onUpdateAccount: () {
          Navigator.pop(sheetContext);
          _openUserEditorDialog(context, user, areas);
        },
        onSendTemporaryPassword: () {
          Navigator.pop(sheetContext);
          unawaited(_sendTemporaryPassword(firebase, messenger, user));
        },
        onDeleteUser: () {
          Navigator.pop(sheetContext);
          unawaited(_deleteUser(context, user));
        },
        onRevokeAccess: () {
          Navigator.pop(sheetContext);
          unawaited(_revokeUserAccess(context, user));
        },
      ),
    );
  }

  void _openUserEditorDialog(
    BuildContext context,
    AppUser user,
    List<Area> areas,
  ) {
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

  Future<void> _sendTemporaryPassword(
    FirebaseService firebase,
    ScaffoldMessengerState messenger,
    AppUser user,
  ) async {
    final email = user.email.trim();
    if (email.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No registered email is available.')),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text('Sending temporary password email to $email...')),
    );
    try {
      await firebase.sendTemporaryPasswordSetupEmail(user);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Temporary password email sent to $email.')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _deleteUser(BuildContext context, AppUser user) async {
    final id = user.id.trim();
    if (id.isEmpty) return;
    final firebase = context.read<FirebaseService>();
    final face = context.read<FaceProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await firebase.deleteManagedUser(id);
      await face.deleteLocalFace(id);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${user.name} profile deleted. Remove the Firebase Auth account too before reusing ${user.email}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Future<void> _revokeUserAccess(BuildContext context, AppUser user) async {
    final id = user.id.trim();
    if (id.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<FirebaseService>().revokeUserAccess(id);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Access revoked for ${user.name}.')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
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

class _DirectoryFilterChip extends StatelessWidget {
  const _DirectoryFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => onTap(),
    );
  }
}

class _NewRegistrationCardState extends State<_NewRegistrationCard> {
  static const _departmentOptions = <String>[
    'Information Technology',
    'ICT Division',
    'Software Engineering',
    'Multimedia',
    'Information Security',
    'Other...',
  ];
  static const _programmeOptions = <String>[
    'Bachelor of Computer Science (Information Security) with Honours - BIS',
    'Bachelor of Computer Science (Multimedia Computing) with Honours - BIM',
    'Bachelor of Computer Science (Software Engineering) with Honours - BIS',
    'Bachelor of Computer Science (Web Technology) with Honours - BIW',
    'Bachelor of Information Technology with Honours - BIT',
    'Master of Information Technology',
    'Master of Computer Science (Information Security)',
    'Master of Computer Science (Software Engineering)',
    'Doctor of Philosophy (PhD) in Information Technology',
  ];

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _identity = TextEditingController();
  final _email = TextEditingController();
  final _department = TextEditingController();
  final _phone = TextEditingController();
  final List<String> _selectedRooms = [];
  String _departmentChoice = _departmentOptions.first;
  String _programmeChoice = _programmeOptions.first;
  String _position = 'Student';
  int _accessLevel = 2;
  DateTime _startAt = DateTime.now();
  DateTime _endAt = DateTime.now().add(const Duration(days: 90));
  bool _saving = false;
  AppUser? _credentialUser;
  String? _temporaryPassword;

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
    final roomOptions = _roomsForAccessLevel(
      widget.areas,
      _accessLevel,
    ).map(_roomLabel).toList();
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
                label: Text(widget.expanded ? 'Close' : 'Open'),
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
                  _ResponsiveFields(
                    children: [
                      TextFormField(
                        controller: _identity,
                        decoration: const InputDecoration(
                          labelText: 'Unique ID',
                        ),
                        validator: _required,
                      ),
                      TextFormField(
                        controller: _email,
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: _required,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _ResponsiveFields(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _departmentChoice,
                            decoration: const InputDecoration(
                              labelText: 'Department',
                            ),
                            items: [
                              for (final option in _departmentOptions)
                                DropdownMenuItem(
                                  value: option,
                                  child: Text(option),
                                ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _departmentChoice = value);
                            },
                          ),
                          if (_departmentChoice == 'Other...') ...[
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _department,
                              decoration: const InputDecoration(
                                labelText: 'Custom Department',
                              ),
                              validator: _required,
                            ),
                          ],
                        ],
                      ),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(labelText: 'Phone'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _PositionToggle(
                    value: _position,
                    onChanged: (value) => setState(() => _position = value),
                  ),
                  if (_position == 'Student') ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _programmeChoice,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Programme'),
                      selectedItemBuilder: (context) => [
                        for (final option in _programmeOptions)
                          Text(
                            option,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                      items: [
                        for (final option in _programmeOptions)
                          DropdownMenuItem(
                            value: option,
                            child: Text(
                              option,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _programmeChoice = value);
                        }
                      },
                    ),
                  ],
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: _accessLevel,
                    decoration: const InputDecoration(
                      labelText: 'Floor Access',
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Level G')),
                      DropdownMenuItem(value: 1, child: Text('Level 1')),
                      DropdownMenuItem(value: 2, child: Text('Level 2')),
                      DropdownMenuItem(value: 3, child: Text('Level 3')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _accessLevel = value;
                        final nextOptions = _roomsForAccessLevel(
                          widget.areas,
                          value,
                        ).map(_roomLabel).toSet();
                        _selectedRooms.removeWhere(
                          (room) => !nextOptions.contains(room),
                        );
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  _RoomMultiSelectField(
                    title: 'Room Schedule',
                    options: roomOptions,
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
                  _ResponsiveFields(
                    children: [
                      _DateButton(
                        label: 'Start',
                        value: _startAt,
                        onTap: () => _pickDate(start: true),
                      ),
                      _DateButton(
                        label: 'End',
                        value: _endAt,
                        onTap: () => _pickDate(start: false),
                      ),
                    ],
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
                  if (_credentialUser != null &&
                      _temporaryPassword != null) ...[
                    const SizedBox(height: 16),
                    _CredentialConfirmationPanel(
                      user: _credentialUser!,
                      temporaryPassword: _temporaryPassword!,
                    ),
                  ],
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
    final department = _selectedDepartment;
    final temporaryPassword = _generateTemporaryPassword();
    try {
      final created = await firebase.createManagedUser(
        name: _name.text,
        identityNumber: _identity.text,
        email: _email.text,
        temporaryPassword: temporaryPassword,
        department: department,
        phone: _phone.text,
        room: _selectedRooms.first,
        rooms: _selectedRooms,
        role: 'user',
        accessLevel: _accessLevel,
        position: _position,
        course: _position == 'Student' ? _programmeChoice : department,
      );
      final assignedUser = created.copyWith(
        room: _selectedRooms.first,
        rooms: _selectedRooms,
        status: 'approved',
        position: _position,
        course: _position == 'Student' ? _programmeChoice : department,
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
      setState(() {
        _credentialUser = assignedUser.copyWith(department: department);
        _temporaryPassword = temporaryPassword;
      });
      _showSnack(
        'Registration saved. Send the temporary password or register face scan below.',
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
      _departmentChoice = _departmentOptions.first;
      _programmeChoice = _programmeOptions.first;
      _position = 'Student';
      _accessLevel = 2;
      _startAt = DateTime.now();
      _endAt = DateTime.now().add(const Duration(days: 90));
    });
  }

  String get _selectedDepartment {
    if (_departmentChoice == 'Other...') return _department.text.trim();
    return _departmentChoice;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  String _generateTemporaryPassword() {
    const alphabet =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789@#%';
    final random = math.Random.secure();
    return 'fx_${List.generate(10, (_) => alphabet[random.nextInt(alphabet.length)]).join()}';
  }
}

class _CredentialConfirmationPanel extends StatelessWidget {
  const _CredentialConfirmationPanel({
    required this.user,
    required this.temporaryPassword,
  });

  final AppUser user;
  final String temporaryPassword;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CorporateColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CorporateColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: _ResponsiveFields(
          children: [
            FilledButton.icon(
              onPressed: () async {
                try {
                  await context.read<FirebaseService>().sendSetupEmail(
                    user.email,
                    user: user,
                    temporaryPassword: temporaryPassword,
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Temporary password email is ready.'),
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(e.toString())));
                }
              },
              icon: const Icon(Icons.mail_outline_rounded),
              label: const Text('Send Temporary Password'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  FaceRegistrationScreen.route,
                  arguments: FaceRegistrationArgs(user: user),
                );
              },
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text('Face Registration'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                children[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: crossAxisAlignment,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
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
    required this.onView,
    required this.onEdit,
  });

  final AppUser user;
  final int permissionCount;
  final VoidCallback onView;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final id = _uniqueId(user).toLowerCase();
    final name = user.name.trim().isEmpty ? 'syed' : user.name.trim();
    final role = user.roleLabel.trim().isEmpty ? 'Staff' : user.roleLabel;
    final faceStatus = user.hasFace ? 'Verified' : 'Not enrolled';
    final rooms = user.assignedRooms
        .where((room) => room.trim().isNotEmpty)
        .toList(growable: false);
    final photo = _profileImage(user.photoUrl);
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFFE0F2FE),
                backgroundImage: photo,
                child: photo == null
                    ? const Icon(
                        Icons.person_rounded,
                        color: CorporateColors.teal,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$role (${_levelSummary(rooms)})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$name | ID: $id',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: CorporateColors.mutedText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: 'View full profile',
                child: IconButton(
                  onPressed: onView,
                  icon: const Icon(Icons.visibility_rounded),
                ),
              ),
              Tooltip(
                message: 'Edit identity',
                child: IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _DirectoryInfo(label: 'Face', value: faceStatus),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DirectoryInfo(
                  label: 'Rooms',
                  value: '$permissionCount assigned',
                ),
              ),
            ],
          ),
          if (rooms.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final room in rooms.take(4))
                  _RoomBadge(label: '$room\nFloor: ${_roomLevel(room)}'),
                if (rooms.length > 4) _RoomBadge(label: '+${rooms.length - 4}'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  ImageProvider<Object>? _profileImage(String? path) {
    final value = path?.trim();
    if (value == null || value.isEmpty) return null;
    final file = File(value);
    return file.existsSync() ? FileImage(file) : null;
  }

  String _levelSummary(List<String> rooms) {
    final levels = rooms
        .map(_roomLevel)
        .toSet()
        .where((level) => level != 'Room');
    if (levels.isEmpty) return 'No room assigned';
    return levels.join(', ');
  }

  String _roomLevel(String room) {
    final key = _accessKey(room);
    if (key.contains('serverroom1')) {
      return 'Level 1';
    }
    if (key.contains('ictoffice') || key.contains('serverroom2')) {
      return 'Level 2';
    }
    if (key.contains('accesslab') ||
        key.contains('fileroom') ||
        key.contains('itdevelopmentsuite') ||
        key.contains('serverroom3') ||
        key.contains('networkcoreoperations')) {
      return 'Level 3';
    }
    if (key.contains('generaloffice') || key.contains('serverroom')) {
      return 'Level G';
    }
    return 'Room';
  }
}

class _DirectoryInfo extends StatelessWidget {
  const _DirectoryInfo({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CorporateColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CorporateColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: CorporateColors.mutedText,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomBadge extends StatelessWidget {
  const _RoomBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

class _UserActionSheet extends StatelessWidget {
  const _UserActionSheet({
    required this.user,
    required this.onScanFace,
    required this.onUpdateAccount,
    required this.onSendTemporaryPassword,
    required this.onDeleteUser,
    required this.onRevokeAccess,
  });

  final AppUser user;
  final VoidCallback onScanFace;
  final VoidCallback onUpdateAccount;
  final VoidCallback onSendTemporaryPassword;
  final VoidCallback onDeleteUser;
  final VoidCallback onRevokeAccess;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              user.name.trim().isEmpty ? 'Operational Controls' : user.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: onScanFace,
              child: const Align(
                alignment: Alignment.centerLeft,
                child: Text('Scan Face'),
              ),
            ),
            TextButton(
              onPressed: onUpdateAccount,
              child: const Align(
                alignment: Alignment.centerLeft,
                child: Text('Update Account'),
              ),
            ),
            TextButton(
              onPressed: onSendTemporaryPassword,
              child: const Align(
                alignment: Alignment.centerLeft,
                child: Text('Send Temporary Password'),
              ),
            ),
            TextButton(
              onPressed: onRevokeAccess,
              child: const Align(
                alignment: Alignment.centerLeft,
                child: Text('Revoke Access'),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFF6B81),
              ),
              onPressed: onDeleteUser,
              child: const Align(
                alignment: Alignment.centerLeft,
                child: Text('Delete User'),
              ),
            ),
          ],
        ),
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
      label: Text(enrolled ? 'Face enrolled' : 'Face setup needed'),
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
  late List<String> _rooms;
  late String _departmentChoice;
  DateTime _grantStart = DateTime.now();
  DateTime _grantEnd = DateTime.now().add(const Duration(days: 90));
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
    _departmentChoice = commandCenterDepartments.contains(user.department)
        ? user.department
        : 'Other...';
    _position = user.roleLabel.toLowerCase().contains('staff')
        ? 'Staff'
        : 'Student';
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
                  DropdownButtonFormField<String>(
                    initialValue: _departmentChoice,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Department'),
                    items: commandCenterDepartments
                        .map(
                          (department) => DropdownMenuItem(
                            value: department,
                            child: Text(department),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _departmentChoice = value);
                      if (value != 'Other...') _department.text = value;
                    },
                  ),
                  if (_departmentChoice == 'Other...') ...[
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _department,
                      decoration: const InputDecoration(
                        labelText: 'Custom Department',
                      ),
                      validator: _required,
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                  const SizedBox(height: 10),
                  _PositionToggle(
                    value: _position,
                    onChanged: (value) => setState(() => _position = value),
                  ),
                  const SizedBox(height: 10),
                  _ResponsiveFields(
                    children: [
                      _DateButton(
                        label: 'Access Starts',
                        value: _grantStart,
                        onTap: () => _pickGrantDate(start: true),
                      ),
                      _DateButton(
                        label: 'Access Ends',
                        value: _grantEnd,
                        onTap: () => _pickGrantDate(start: false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _RoomMultiSelectField(
                    title: 'Room Schedule',
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
    if (!_grantEnd.isAfter(_grantStart)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Access end must be after start.')),
      );
      return;
    }
    setState(() => _saving = true);
    final department = _departmentChoice == 'Other...'
        ? _department.text.trim()
        : _departmentChoice;
    final updated = widget.user.copyWith(
      name: _name.text.trim(),
      identityNumber: _identity.text.trim(),
      email: _email.text.trim(),
      department: department,
      phone: _phone.text.trim(),
      room: _rooms.isEmpty ? '' : _rooms.first,
      rooms: _rooms,
      role: 'User',
      position: _position,
      status: 'approved',
    );
    try {
      final firebase = context.read<FirebaseService>();
      await firebase.updateUserProfile(updated);
      for (final room in _rooms) {
        final area = _areaForRoom(room);
        if (area == null) continue;
        await firebase.grantRoomAccess(
          user: updated,
          area: area,
          startAt: _grantStart,
          endAt: _grantEnd,
          approveUser: false,
        );
      }
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

  Area? _areaForRoom(String room) {
    for (final area in widget.areas) {
      if (_sameAccessTarget(room, _roomLabel(area))) return area;
    }
    return null;
  }

  Future<void> _pickGrantDate({required bool start}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _grantStart : _grantEnd,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _grantStart = picked;
        if (!_grantEnd.isAfter(_grantStart)) {
          _grantEnd = _grantStart.add(const Duration(days: 1));
        }
      } else {
        _grantEnd = picked;
      }
    });
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
  static const _allAccessOrders = 'All levels';
  static const _allRoles = 'All roles';
  static const _studentRole = 'Students';
  static const _staffRole = 'Staff';

  final _roomSearch = TextEditingController();
  _ZoneFilter _filter = _ZoneFilter.activeRooms;
  _RoomStatusFilter _statusFilter = _RoomStatusFilter.all;
  String _floorFilter = _allAccessOrders;
  String _roleFilter = _allRoles;
  String? _expandedAreaId;
  _RoomDetailView _detailView = _RoomDetailView.settings;

  @override
  void dispose() {
    _roomSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final areaProvider = context.watch<AreaProvider>();
    final logs = context.watch<LogProvider>().logs;
    final firebase = context.read<FirebaseService>();
    return StreamBuilder<List<AppUser>>(
      stream: firebase.watchAllUsers(),
      builder: (context, snapshot) {
        final users = snapshot.data ?? const <AppUser>[];
        final floorOptions = _zoneFloorOptions(
          areaProvider.areas,
          allLabel: _allAccessOrders,
        );
        final selectedFloor = floorOptions.contains(_floorFilter)
            ? _floorFilter
            : _allAccessOrders;
        final rooms = _filteredRooms(
          _sortedRooms(areaProvider.areas, logs),
          selectedFloor,
        );
        final roomGroups = _roomGroupsByAccessOrder(rooms);
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
              const SizedBox(height: 12),
              _ZoneRoomFilterBar(
                searchController: _roomSearch,
                floorOptions: floorOptions,
                selectedFloor: selectedFloor,
                statusFilter: _statusFilter,
                roleFilter: _roleFilter,
                onSearchChanged: (_) => setState(() {}),
                onFloorChanged: (value) => setState(() {
                  _floorFilter = value ?? _allAccessOrders;
                }),
                onStatusChanged: (value) => setState(() {
                  _statusFilter = value ?? _RoomStatusFilter.all;
                }),
                onRoleChanged: (value) => setState(() {
                  _roleFilter = value ?? _allRoles;
                }),
              ),
              if (areaProvider.error != null) ...[
                const SizedBox(height: 12),
                _InlineError(message: areaProvider.error!),
              ],
              const SizedBox(height: 12),
              if (roomGroups.isEmpty)
                const _EmptyState(
                  icon: Icons.meeting_room_rounded,
                  title: 'No linked rooms available',
                )
              else
                for (final group in roomGroups) ...[
                  _AccessOrderHeader(group: group),
                  for (final room in group.rooms)
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

  List<Area> _filteredRooms(List<Area> rooms, String selectedFloor) {
    final query = _roomSearch.text.trim().toLowerCase();
    return rooms.where((area) {
      if (selectedFloor != _allAccessOrders &&
          area.floor.trim() != selectedFloor) {
        return false;
      }
      switch (_statusFilter) {
        case _RoomStatusFilter.all:
          break;
        case _RoomStatusFilter.active:
          if (!area.active) return false;
        case _RoomStatusFilter.inactive:
          if (area.active) return false;
      }
      if (_roleFilter == _studentRole && !_areaAllowsRole(area, 'student')) {
        return false;
      }
      if (_roleFilter == _staffRole && !_areaAllowsRole(area, 'staff')) {
        return false;
      }
      if (query.isEmpty) return true;
      return [
        area.id,
        area.name,
        area.floor,
        area.roomNumber,
        area.location,
        _roomSubtitle(area),
      ].join(' ').toLowerCase().contains(query);
    }).toList();
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

class _ZoneRoomFilterBar extends StatelessWidget {
  const _ZoneRoomFilterBar({
    required this.searchController,
    required this.floorOptions,
    required this.selectedFloor,
    required this.statusFilter,
    required this.roleFilter,
    required this.onSearchChanged,
    required this.onFloorChanged,
    required this.onStatusChanged,
    required this.onRoleChanged,
  });

  final TextEditingController searchController;
  final List<String> floorOptions;
  final String selectedFloor;
  final _RoomStatusFilter statusFilter;
  final String roleFilter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onFloorChanged;
  final ValueChanged<_RoomStatusFilter?> onStatusChanged;
  final ValueChanged<String?> onRoleChanged;

  @override
  Widget build(BuildContext context) {
    final roleOptions = const ['All roles', 'Students', 'Staff'];
    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 250,
            child: TextField(
              controller: searchController,
              decoration: const InputDecoration(
                labelText: 'Filter rooms',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: onSearchChanged,
            ),
          ),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              key: ValueKey('floor-$selectedFloor-${floorOptions.length}'),
              initialValue: selectedFloor,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Level'),
              items: [
                for (final floor in floorOptions)
                  DropdownMenuItem(
                    value: floor,
                    child: Text(
                      floor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: onFloorChanged,
            ),
          ),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<_RoomStatusFilter>(
              key: ValueKey('status-$statusFilter'),
              initialValue: statusFilter,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(
                  value: _RoomStatusFilter.all,
                  child: Text('All'),
                ),
                DropdownMenuItem(
                  value: _RoomStatusFilter.active,
                  child: Text('Active'),
                ),
                DropdownMenuItem(
                  value: _RoomStatusFilter.inactive,
                  child: Text('Inactive'),
                ),
              ],
              onChanged: onStatusChanged,
            ),
          ),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<String>(
              key: ValueKey('role-$roleFilter'),
              initialValue: roleFilter,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Role'),
              items: [
                for (final role in roleOptions)
                  DropdownMenuItem(value: role, child: Text(role)),
              ],
              onChanged: onRoleChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccessOrderHeader extends StatelessWidget {
  const _AccessOrderHeader({required this.group});

  final _RoomAccessOrderGroup group;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              group.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: CorporateColors.text,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: CorporateColors.teal.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: CorporateColors.teal.withValues(alpha: .35),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              child: Text(
                '${group.rooms.length}',
                style: const TextStyle(
                  color: CorporateColors.teal,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomAccessOrderGroup {
  const _RoomAccessOrderGroup({required this.label, required this.rooms});

  final String label;
  final List<Area> rooms;
}

bool _areaAllowsRole(Area area, String role) {
  final target = role.trim().toLowerCase();
  final roles = area.allowedRoles
      .map((item) => item.trim().toLowerCase())
      .where((item) => item.isNotEmpty)
      .toSet();
  if (roles.isEmpty) return true;
  if (target == 'student') {
    return roles.contains('student') || roles.contains('user');
  }
  if (target == 'staff') {
    return roles.contains('staff') || roles.contains('user');
  }
  return roles.contains(target);
}

List<String> _zoneFloorOptions(List<Area> areas, {required String allLabel}) {
  final floors =
      areas
          .map((area) => area.floor.trim())
          .where((floor) => floor.isNotEmpty)
          .toSet()
          .toList()
        ..sort(_compareAccessOrder);
  return [allLabel, ...floors];
}

List<_RoomAccessOrderGroup> _roomGroupsByAccessOrder(List<Area> rooms) {
  final grouped = <String, List<Area>>{};
  for (final room in rooms) {
    final floor = room.floor.trim().isEmpty
        ? 'Unassigned floor'
        : room.floor.trim();
    grouped.putIfAbsent(floor, () => <Area>[]).add(room);
  }
  final floors = grouped.keys.toList()..sort(_compareAccessOrder);
  return [
    for (final floor in floors)
      _RoomAccessOrderGroup(
        label: _accessOrderGroupLabel(floor),
        rooms: grouped[floor]!,
      ),
  ];
}

String _accessOrderGroupLabel(String floor) {
  return floor.trim().isEmpty ? 'Unassigned level' : floor.trim();
}

int _compareAccessOrder(String left, String right) {
  final order = _floorAccessOrder(left).compareTo(_floorAccessOrder(right));
  if (order != 0) return order;
  return left.compareTo(right);
}

int _floorAccessOrder(String floor) {
  final normalized = _accessKey(floor);
  if (normalized == 'levelg' ||
      normalized == 'g' ||
      normalized.contains('ground')) {
    return 0;
  }
  final levelMatch = RegExp(r'level(\d+)').firstMatch(normalized);
  if (levelMatch != null) {
    return int.tryParse(levelMatch.group(1) ?? '') ?? 99;
  }
  final numberMatch = RegExp(r'\d+').firstMatch(normalized);
  return int.tryParse(numberMatch?.group(0) ?? '') ?? 99;
}

String _floorAccessLabel(int level) => level <= 0 ? 'Level G' : 'Level $level';

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
                      _roomSubtitle(area),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
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
            const SizedBox(height: 12),
            _RoomUserRoster(area: area, users: users),
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

class _RoomUserRoster extends StatelessWidget {
  const _RoomUserRoster({required this.area, required this.users});

  final Area area;
  final List<AppUser> users;

  @override
  Widget build(BuildContext context) {
    final assigned =
        users.where((user) => _userAssignedToArea(user, area)).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final staff = assigned
        .where((user) => user.roleLabel.toLowerCase().contains('staff'))
        .length;
    final students = assigned.length - staff;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Assigned Users: $students student${students == 1 ? '' : 's'} / $staff staff',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        if (assigned.isEmpty)
          const Text('No assigned users for this room.')
        else
          for (final user in assigned.take(8))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    user.roleLabel.toLowerCase().contains('staff')
                        ? Icons.work_rounded
                        : Icons.school_rounded,
                    size: 18,
                    color: CorporateColors.teal,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      user.name.trim().isEmpty ? user.id : user.name.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    user.roleLabel,
                    style: const TextStyle(
                      color: CorporateColors.mutedText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
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

class _RoomHistoryView extends StatefulWidget {
  const _RoomHistoryView({
    required this.area,
    required this.logs,
    required this.occupants,
  });

  final Area area;
  final List<AccessLog> logs;
  final List<AccessLog> occupants;

  @override
  State<_RoomHistoryView> createState() => _RoomHistoryViewState();
}

class _RoomHistoryViewState extends State<_RoomHistoryView> {
  String _filter = 'month';

  @override
  Widget build(BuildContext context) {
    final roomLogs =
        widget.logs
            .where((log) => _logBelongsToArea(log, widget.area))
            .where(_matchesFilter)
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _RoomLogFilterChip(
              label: 'Today',
              selected: _filter == 'today',
              onTap: () => setState(() => _filter = 'today'),
            ),
            _RoomLogFilterChip(
              label: '7 days',
              selected: _filter == 'week',
              onTap: () => setState(() => _filter = 'week'),
            ),
            _RoomLogFilterChip(
              label: 'This month',
              selected: _filter == 'month',
              onTap: () => setState(() => _filter = 'month'),
            ),
            _RoomLogFilterChip(
              label: 'All',
              selected: _filter == 'all',
              onTap: () => setState(() => _filter = 'all'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Live Occupancy',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        if (widget.occupants.isEmpty)
          const Text('No live occupants recorded.')
        else
          for (final log in widget.occupants.take(6))
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
        if (roomLogs.isEmpty)
          const Text('No room logs for this filter.')
        else
          for (final log in roomLogs.take(12)) _CompactLogLine(log: log),
      ],
    );
  }

  bool _matchesFilter(AccessLog log) {
    final now = DateTime.now();
    switch (_filter) {
      case 'today':
        return _sameDay(log.timestamp, now);
      case 'week':
        return log.timestamp.isAfter(now.subtract(const Duration(days: 7)));
      case 'month':
        return log.timestamp.year == now.year &&
            log.timestamp.month == now.month;
      default:
        return true;
    }
  }
}

class _RoomLogFilterChip extends StatelessWidget {
  const _RoomLogFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
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
  late String _floorChoice;
  late double _capacity;
  late Set<String> _roles;
  bool _active = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final area = widget.area;
    _name = TextEditingController(text: area.name);
    _location = TextEditingController(text: 'FSKTM');
    _floor = TextEditingController(text: area.floor);
    _floorChoice = commandCenterFloorOptions.contains(area.floor)
        ? area.floor
        : 'Other...';
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
                readOnly: true,
                decoration: const InputDecoration(labelText: 'Location'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _floorChoice,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Floor'),
                      items: commandCenterFloorOptions
                          .map(
                            (floor) => DropdownMenuItem(
                              value: floor,
                              child: Text(floor),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _floorChoice = value);
                      },
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
              if (_floorChoice == 'Other...') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _floor,
                  decoration: const InputDecoration(labelText: 'Custom Floor'),
                ),
              ],
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
      location: 'FSKTM',
      floor: _floorChoice == 'Other...' ? _floor.text.trim() : _floorChoice,
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
  String _room = 'all';
  String _period = 'all';
  DateTime? _selectedDate;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LogProvider>();
    final sourceLogs = provider.logs.isEmpty
        ? _sampleAccessLogs()
        : provider.logs;
    final roomOptions = _roomOptions(sourceLogs);
    final filteredLogs = _filtered(sourceLogs);
    final visibleLogs = filteredLogs.take(widget.initialLimit).toList();
    final grantedCount = filteredLogs.where((log) => log.granted).length;
    final deniedCount = filteredLogs.length - grantedCount;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _AccessLogPanel(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    labelText: 'Search',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'granted', child: Text('Granted')),
                    DropdownMenuItem(value: 'denied', child: Text('Denied')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _status = value);
                  },
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  initialValue: roomOptions.contains(_room) ? _room : 'all',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Room'),
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All')),
                    for (final room in roomOptions)
                      if (room != 'all')
                        DropdownMenuItem(
                          value: room,
                          child: Text(
                            room,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _room = value);
                  },
                ),
              ),
              SizedBox(
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: _pickLogDate,
                  icon: const Icon(Icons.event_rounded),
                  label: Text(
                    _selectedDate == null
                        ? 'Date'
                        : DateFormat.yMMMd().format(_selectedDate!),
                  ),
                ),
              ),
              if (_selectedDate != null)
                SizedBox(
                  height: 56,
                  child: TextButton(
                    onPressed: () => setState(() => _selectedDate = null),
                    child: const Text('Clear'),
                  ),
                ),
              _PeriodChip(
                label: 'Today',
                selected: _period == 'today',
                onTap: () => setState(() {
                  _period = 'today';
                  _selectedDate = null;
                }),
              ),
              _PeriodChip(
                label: '7 days',
                selected: _period == 'week',
                onTap: () => setState(() {
                  _period = 'week';
                  _selectedDate = null;
                }),
              ),
              _PeriodChip(
                label: 'This month',
                selected: _period == 'month',
                onTap: () => setState(() {
                  _period = 'month';
                  _selectedDate = null;
                }),
              ),
              _PeriodChip(
                label: 'All',
                selected: _period == 'all',
                onTap: () => setState(() => _period = 'all'),
              ),
            ],
          ),
        ),
        if (provider.error != null) ...[
          const SizedBox(height: 12),
          _InlineError(
            message:
                'Access Log sync is delayed. Firestore will retry automatically.',
          ),
        ],
        const SizedBox(height: 12),
        _AccessLogPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              if (visibleLogs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(22),
                  child: _EmptyState(
                    icon: Icons.terminal_rounded,
                    title: 'No access log entries',
                  ),
                )
              else
                for (final log in visibleLogs)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: _TimelineRow(
                      log: log,
                      onTap: () => _showSecurityDetail(context, log),
                    ),
                  ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Total: ${filteredLogs.length}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Granted: $grantedCount',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Denied: $deniedCount',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (provider.logs.length > widget.initialLimit)
                      TextButton.icon(
                        onPressed: provider.loadMore,
                        icon: const Icon(Icons.expand_more_rounded),
                        label: const Text('Load more'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<AccessLog> _filtered(List<AccessLog> logs) {
    final query = _search.text.trim().toLowerCase();
    return logs.where((log) {
      if (_status == 'granted' && !log.granted) return false;
      if (_status == 'denied' && log.granted) return false;
      if (_room != 'all' && _accessKey(log.areaName) != _accessKey(_room)) {
        return false;
      }
      if (_selectedDate != null && !_sameDay(log.timestamp, _selectedDate!)) {
        return false;
      }
      if (_selectedDate == null && !_matchesPeriod(log.timestamp)) return false;
      if (query.isEmpty) return true;
      return [
        _logUserName(log),
        log.areaName,
        log.status,
        log.reason,
      ].join(' ').toLowerCase().contains(query);
    }).toList();
  }

  bool _matchesPeriod(DateTime timestamp) {
    final now = DateTime.now();
    switch (_period) {
      case 'today':
        return _sameDay(timestamp, now);
      case 'week':
        return timestamp.isAfter(now.subtract(const Duration(days: 7)));
      case 'month':
        return timestamp.year == now.year && timestamp.month == now.month;
      default:
        return true;
    }
  }

  List<String> _roomOptions(List<AccessLog> logs) {
    final rooms = {
      ...commandCenterRoomNames,
      ...logs
          .map((log) => log.areaName.trim())
          .where((room) => room.isNotEmpty),
    }.toList()..sort();
    return ['all', ...rooms];
  }

  Future<void> _pickLogDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _selectedDate = picked;
      _period = 'all';
    });
  }

  List<AccessLog> _sampleAccessLogs() {
    final now = DateTime.now();
    return [
      AccessLog(
        id: 'sample_granted',
        userId: 'sample_daniel',
        userName: 'daniel',
        areaId: 'server_room',
        areaName: 'Server Room',
        status: 'granted',
        reason: 'Sample verified entry',
        timestamp: now.subtract(const Duration(minutes: 12)),
        synced: true,
      ),
      AccessLog(
        id: 'sample_denied',
        userId: '',
        userName: 'Unknown face',
        areaId: 'server_room',
        areaName: 'Server Room',
        status: 'denied',
        reason: 'Sample denied entry',
        timestamp: now.subtract(const Duration(minutes: 4)),
        synced: true,
      ),
    ];
  }
}

class _AccessLogPanel extends StatelessWidget {
  const _AccessLogPanel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CorporateColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CorporateColors.border),
        boxShadow: [
          BoxShadow(
            color: CorporateColors.lightBlue.withValues(alpha: .2),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _AccessStatusBadge extends StatelessWidget {
  const _AccessStatusBadge({required this.log});

  final AccessLog log;

  @override
  Widget build(BuildContext context) {
    final color = log.granted
        ? const Color(0xFF16A34A)
        : const Color(0xFFE11D48);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          log.granted ? 'Granted' : 'Denied',
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

String _logUserName(AccessLog log) {
  final name = log.userName.trim();
  if (name.isEmpty || log.isUnknownFace) return 'Unknown face';
  return name;
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _AccessStatusBadge(log: log),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _showSecurityDetail(BuildContext context, AccessLog log) {
  final firebase = context.read<FirebaseService>();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final file = log.snapshotPath == null ? null : File(log.snapshotPath!);
      final hasPhoto = file != null && file.existsSync();
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            18,
            18,
            MediaQuery.viewInsetsOf(context).bottom + 18,
          ),
          child: ListView(
            shrinkWrap: true,
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
              _DetailLine(label: 'Result', value: log.status.toUpperCase()),
              _DetailLine(label: 'User', value: log.userName),
              _DetailLine(label: 'Room', value: log.areaName),
              _DetailLine(
                label: 'Timestamp',
                value: _preciseDate(log.timestamp),
              ),
              _DetailLine(label: 'Reason', value: log.reason),
              const Divider(height: 22),
              Text(
                'User Details',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              FutureBuilder<AppUser?>(
                future: log.userId.trim().isEmpty
                    ? Future<AppUser?>.value(null)
                    : firebase.getUser(log.userId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(),
                    );
                  }
                  final user = snapshot.data;
                  if (user == null) {
                    return const Text(
                      'No registered user profile is linked to this access log.',
                    );
                  }
                  return _AccessLogUserDetails(user: user);
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _AccessLogUserDetails extends StatelessWidget {
  const _AccessLogUserDetails({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final academicLabel = user.roleLabel.toLowerCase().contains('staff')
        ? 'Department'
        : 'Programme';
    final rooms = user.assignedRoomsLabel.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailLine(label: 'Name', value: user.name),
        _DetailLine(label: 'ID', value: _uniqueId(user)),
        _DetailLine(label: 'Email', value: user.email),
        _DetailLine(label: 'Phone', value: user.phone),
        _DetailLine(label: 'Category', value: user.roleLabel),
        _DetailLine(
          label: academicLabel,
          value: academicLabel == 'Department' ? user.department : user.course,
        ),
        _DetailLine(label: 'Faculty', value: user.faculty),
        _DetailLine(label: 'Semester', value: user.currentSemester),
        _DetailLine(
          label: 'Access',
          value: _floorAccessLabel(user.accessLevel),
        ),
        _DetailLine(label: 'Rooms', value: rooms),
        _DetailLine(label: 'Status', value: user.status),
        _DetailLine(
          label: 'Face',
          value: user.hasFace ? 'Registered' : 'Not registered',
        ),
      ],
    );
  }
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

class _UserDeepDetailPage extends StatelessWidget {
  const _UserDeepDetailPage({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final firebase = context.read<FirebaseService>();
    return AppBackground(
      child: Scaffold(
        backgroundColor: AppBackground.slateGray,
        appBar: AppBar(
          backgroundColor: AppBackground.slateGray,
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
                      const SizedBox(height: 14),
                      _DetailLine(label: 'Email', value: user.email),
                      _DetailLine(label: 'Phone', value: user.phone),
                      _DetailLine(label: 'Role', value: user.roleLabel),
                      _DetailLine(
                        label: user.position.trim().toLowerCase() == 'staff'
                            ? 'Department'
                            : 'Programme',
                        value: user.department,
                      ),
                      _DetailLine(
                        label: 'Created',
                        value: _preciseDate(user.createdAt),
                      ),
                      _DetailLine(
                        label: 'Rooms',
                        value: user.assignedRoomsLabel,
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
  const _SettingsTab({
    required this.onSignOut,
    required this.darkMode,
    required this.language,
    required this.text,
    required this.onDarkModeChanged,
    required this.onLanguageChanged,
  });

  final Future<void> Function() onSignOut;
  final bool darkMode;
  final String language;
  final _AdminText text;
  final ValueChanged<bool> onDarkModeChanged;
  final ValueChanged<String> onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final adminName = user?.name.trim().isNotEmpty == true
        ? user!.name.trim()
        : 'admin';
    final adminEmail = user?.email.trim().isNotEmpty == true
        ? user!.email.trim()
        : 'syedmuizzuddin03@gmail.com';
    final selectedLanguage = _validLanguage(language);
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _SettingsPanel(
          title: text.myAccount,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                adminName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                adminEmail,
                style: const TextStyle(
                  color: CorporateColors.mutedText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton(
                    onPressed: auth.loading
                        ? null
                        : () => _showAdminPasswordDialog(context),
                    child: Text(text.changePassword),
                  ),
                  OutlinedButton(
                    onPressed: auth.loading
                        ? null
                        : () => _showAdminEmailDialog(context, adminEmail),
                    child: Text(text.editEmail),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SettingsPanel(
          title: text.display,
          child: Column(
            children: [
              SwitchListTile(
                value: darkMode,
                onChanged: onDarkModeChanged,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  text.darkMode,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: selectedLanguage,
                decoration: InputDecoration(labelText: text.language),
                items: const [
                  DropdownMenuItem(value: 'English', child: Text('English')),
                  DropdownMenuItem(value: 'Malay', child: Text('Malay')),
                ],
                onChanged: (value) {
                  if (value != null) onLanguageChanged(value);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: auth.loading ? null : onSignOut,
          icon: const Icon(Icons.logout_rounded),
          label: Text(text.signOut),
        ),
      ],
    );
  }

  Future<void> _showAdminPasswordDialog(BuildContext context) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => const _AdminPasswordDialog(),
    );
    if (!context.mounted || updated != true) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Admin password updated.')));
  }

  Future<void> _showAdminEmailDialog(
    BuildContext context,
    String currentEmail,
  ) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => _AdminEmailDialog(currentEmail: currentEmail),
    );
    if (!context.mounted || updated != true) return;
    final pendingVerification = context
        .read<AuthProvider>()
        .adminEmailUpdatePendingVerification;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          pendingVerification
              ? 'Verification email sent. Open the link to finish changing the admin login email.'
              : 'Admin email updated.',
        ),
      ),
    );
  }
}

class _AdminPasswordDialog extends StatefulWidget {
  const _AdminPasswordDialog();

  @override
  State<_AdminPasswordDialog> createState() => _AdminPasswordDialogState();
}

class _AdminPasswordDialogState extends State<_AdminPasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Password'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current Password'),
              validator: _required,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New Password'),
              validator: (value) {
                if (value == null || value.trim().length < 6) {
                  return 'Use at least 6 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm Password'),
              validator: (value) =>
                  value == _next.text ? null : 'Passwords do not match',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving' : 'Save'),
        ),
      ],
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.updateAdminPassword(
      currentPassword: _current.text,
      newPassword: _next.text,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error ?? 'Unable to update password.')),
      );
    }
  }
}

class _AdminEmailDialog extends StatefulWidget {
  const _AdminEmailDialog({required this.currentEmail});

  final String currentEmail;

  @override
  State<_AdminEmailDialog> createState() => _AdminEmailDialogState();
}

class _AdminEmailDialogState extends State<_AdminEmailDialog> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _email.text = widget.currentEmail;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Email'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'New Email'),
              validator: (value) {
                final email = value?.trim() ?? '';
                return email.contains('@') ? null : 'Enter a valid email';
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current Password'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Required' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving' : 'Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.updateAdminEmail(
      currentPassword: _password.text,
      newEmail: _email.text,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error ?? 'Unable to update email.')),
      );
    }
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CorporateColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CorporateColors.border),
        boxShadow: [
          BoxShadow(
            color: CorporateColors.lightBlue.withValues(alpha: .22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: CorporateColors.mutedText,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
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
                '${DateFormat.jm().format(log.timestamp)}  ${log.userName}  ${log.status}',
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

String _roomLabel(Area area) {
  final name = area.name.trim();
  final room = area.roomNumber.trim();
  if (name.isNotEmpty) return name;
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

List<Area> _roomsForAccessLevel(List<Area> areas, int accessLevel) {
  final target = accessLevel == 0 ? 'levelg' : 'level$accessLevel';
  final rooms = areas.where((area) => _accessKey(area.floor) == target).toList()
    ..sort((a, b) => _roomLabel(a).compareTo(_roomLabel(b)));
  return rooms;
}

String _roomSubtitle(Area area) {
  final details = <String>[
    if (area.roomNumber.trim().isNotEmpty) 'Room ${area.roomNumber.trim()}',
    if (area.location.trim().isNotEmpty) area.location.trim(),
  ];
  return details.isEmpty ? 'Room details unavailable' : details.join(' | ');
}

String _accessKey(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

String _validLanguage(String value) {
  return value == 'Malay' ? 'Malay' : 'English';
}

bool _logBelongsToArea(AccessLog log, Area area) {
  if (log.areaId.trim().isNotEmpty && log.areaId == area.id) return true;
  return _roomAccessKeys(area).contains(_accessKey(log.areaName));
}

bool _userAssignedToArea(AppUser user, Area area) {
  final roomKeys = _roomAccessKeys(area);
  return user.assignedRooms.any((room) => roomKeys.contains(_accessKey(room)));
}

Set<String> _roomAccessKeys(Area area) {
  return {
    area.id,
    area.name,
    area.roomNumber,
    '${area.floor} - ${area.name}',
    '${area.location} - ${area.name}',
    '${area.location} - ${area.floor} - ${area.name}',
    _roomLabel(area),
    '${area.location} ${area.floor} ${area.roomNumber}',
  }.map(_accessKey).where((key) => key.isNotEmpty).toSet();
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

String _dashboardRoomSummary(List<Area> areas, {int offset = 0}) {
  if (areas.isEmpty) return 'No rooms linked';
  final sorted = [...areas]
    ..sort((a, b) {
      final floor = _compareAccessOrder(a.floor, b.floor);
      return floor == 0 ? _roomLabel(a).compareTo(_roomLabel(b)) : floor;
    });
  final count = sorted.length < 2 ? sorted.length : 2;
  final start = sorted.isEmpty ? 0 : offset % sorted.length;
  final source = [
    for (var index = 0; index < count; index++)
      sorted[(start + index) % sorted.length],
  ];
  return source
      .map((area) => '${_roomLabel(area)} : ${area.currentOccupancy}')
      .join(' | ');
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
