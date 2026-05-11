import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/access_log.dart';
import '../models/app_user.dart';
import '../models/area.dart';
import '../models/incident_report.dart';
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
import 'face_registration_screen.dart';
import 'notifications_screen.dart';
import 'welcome_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  static const route = '/dashboard';

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

void _pushNamedAfterFrame(
  BuildContext context,
  String route, {
  Object? arguments,
  bool rootNavigator = false,
}) {
  SchedulerBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    Navigator.of(
      context,
      rootNavigator: rootNavigator,
    ).pushNamed(route, arguments: arguments);
  });
}

void _pushAndClearAfterFrame(BuildContext context, String route) {
  SchedulerBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, route, (_) => false);
  });
}

const _campusFaculties = ['FSKTM', 'FKEE', 'FKAAB', 'FPTV'];
const _fsktmHonoursPrograms = [
  'Information Security',
  'Multimedia Computing',
  'Software Engineering',
  'Web Technology',
  'Information Technology',
];
const _adminPageCount = 10;

class _DashboardScreenState extends State<DashboardScreen> {
  int _index = 0;
  String? _resolvedUserId;
  bool? _resolvedIsAdmin;
  bool _roleResolutionQueued = false;

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
    final auth = context.watch<AuthProvider>();
    if (auth.loading && auth.user == null) {
      return const AppBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return StreamBuilder<AppUser?>(
      stream: auth.watchActiveUserProfile(),
      initialData: auth.user,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting &&
            user == null) {
          return const AppBackground(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        _syncAuthSnapshot(auth, user);
        if (user == null) {
          _queueRoleResolution(null);
          return const AppBackground(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Center(child: Text('Sign in to continue.')),
            ),
          );
        }
        if (_resolvedUserId != user.id || _resolvedIsAdmin != user.isAdmin) {
          _queueRoleResolution(user);
          return const AppBackground(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final maxIndex = user.isAdmin ? _adminPageCount - 1 : 3;
        final selectedIndex = _index.clamp(0, maxIndex).toInt();
        return user.isAdmin
            ? _AdminShell(
                user: user,
                index: selectedIndex,
                onIndexChanged: (i) => setState(() => _index = i),
              )
            : _UserShell(
                user: user,
                index: selectedIndex,
                onIndexChanged: (i) => setState(() => _index = i),
              );
      },
    );
  }

  void _syncAuthSnapshot(AuthProvider auth, AppUser? user) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      auth.syncProfileSnapshot(user);
    });
  }

  void _queueRoleResolution(AppUser? user) {
    if (_roleResolutionQueued) return;
    _roleResolutionQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _resolvedUserId = user?.id;
        _resolvedIsAdmin = user?.isAdmin;
        _roleResolutionQueued = false;
      });
    });
  }
}

class _AdminShell extends StatelessWidget {
  const _AdminShell({
    required this.user,
    required this.index,
    required this.onIndexChanged,
  });

  final AppUser user;
  final int index;
  final ValueChanged<int> onIndexChanged;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const _EmergencyResponseCenterTab(),
      const _SecurityOverridesTab(),
      const _UserRegistrationTab(),
      const _StudentDataArchiveTab(),
      const _AccessControlZonesTab(),
      const _ScannerDeviceManagerTab(),
      const _LogsTab(),
      _HomeTab(user: user),
      const _AcademicSessionSetupTab(),
      const _SettingsTab(),
    ];
    final labels = const [
      'Emergency Response Center',
      'Security Overrides',
      'Identity Management',
      'Student Data Archive',
      'Access Control Zones',
      'Scanner Device Manager',
      'Audit Trails',
      'Reports & Exports',
      'Academic Session Setup',
      'Timing Windows',
    ];
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(labels[index]),
          actions: [
            Consumer<AlertProvider>(
              builder: (context, alerts, _) {
                final count = alerts.unreadCount;
                return IconButton(
                  onPressed: () =>
                      _pushNamedAfterFrame(context, NotificationsScreen.route),
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
        drawer: _AdminNavigationDrawer(
          user: user,
          selectedIndex: index,
          onDestinationSelected: (i) {
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              Navigator.pop(context);
              onIndexChanged(i);
            });
          },
        ),
        body: pages[index],
      ),
    );
  }
}

class _AdminNavigationDrawer extends StatelessWidget {
  const _AdminNavigationDrawer({
    required this.user,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final AppUser user;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: _AdminProfileCard(user: user),
            ),
            Expanded(
              child: NavigationDrawer(
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected,
                children: [
                  const _DrawerGroupLabel('Critical Response'),
                  const NavigationDrawerDestination(
                    icon: Icon(Icons.emergency_share_rounded),
                    label: Text('Emergency Response Center'),
                  ),
                  const NavigationDrawerDestination(
                    icon: Icon(Icons.admin_panel_settings_rounded),
                    label: Text('Security Overrides'),
                  ),
                  const SizedBox(height: 12),
                  const _DrawerGroupLabel('Identity & Enrollment'),
                  const NavigationDrawerDestination(
                    icon: Icon(Icons.manage_accounts_rounded),
                    label: Text('Identity Management'),
                  ),
                  const NavigationDrawerDestination(
                    icon: Icon(Icons.inventory_2_rounded),
                    label: Text('Student Data Archive'),
                  ),
                  const SizedBox(height: 12),
                  const _DrawerGroupLabel('Security & Zones'),
                  const NavigationDrawerDestination(
                    icon: Icon(Icons.rule_folder_rounded),
                    label: Text('Access Control Zones'),
                  ),
                  const NavigationDrawerDestination(
                    icon: Icon(Icons.sensors_rounded),
                    label: Text('Scanner Device Manager'),
                  ),
                  const NavigationDrawerDestination(
                    icon: Icon(Icons.history_rounded),
                    label: Text('Audit Trails'),
                  ),
                  const SizedBox(height: 12),
                  const _DrawerGroupLabel('Advanced Utilities'),
                  const NavigationDrawerDestination(
                    icon: Icon(Icons.ios_share_rounded),
                    label: Text('Reports & Exports'),
                  ),
                  const NavigationDrawerDestination(
                    icon: Icon(Icons.event_available_rounded),
                    label: Text('Academic Session Setup'),
                  ),
                  const NavigationDrawerDestination(
                    icon: Icon(Icons.schedule_rounded),
                    label: Text('Timing Windows'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                Icons.logout_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Logout',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () async {
                final auth = context.read<AuthProvider>();
                final ok = await auth.logout();
                if (!ok || !context.mounted) return;
                _pushAndClearAfterFrame(context, WelcomeScreen.route);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminProfileCard extends StatelessWidget {
  const _AdminProfileCard({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _FaceAvatar(user: user),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFF32D583),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name.isEmpty ? 'Administrator' : user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'System Version 2.0',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.circle, size: 8, color: Color(0xFF32D583)),
                    const SizedBox(width: 6),
                    Text(
                      'Online',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerGroupLabel extends StatelessWidget {
  const _DrawerGroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _EmergencyResponseCenterTab extends StatelessWidget {
  const _EmergencyResponseCenterTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<IncidentReport>>(
      stream: FirebaseService().watchIncidentReports(),
      builder: (context, snapshot) {
        final reports = (snapshot.data ?? const <IncidentReport>[]).where((
          report,
        ) {
          final title = report.title.toLowerCase();
          return title.contains('sos') ||
              report.severity.toLowerCase() == 'critical';
        }).toList();
        if (snapshot.connectionState == ConnectionState.waiting &&
            reports.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const _UserSectionHeader(
              title: 'Emergency Response Center',
              subtitle: 'Real-time campus SOS reports from user devices',
            ),
            const SizedBox(height: 12),
            if (reports.isEmpty)
              const GlassCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.health_and_safety_rounded),
                  title: Text('No active SOS alerts'),
                  subtitle: Text('Critical user alerts will appear here.'),
                ),
              )
            else
              for (final report in reports)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SosReportCard(report: report),
                ),
          ],
        );
      },
    );
  }
}

class _SosReportCard extends StatelessWidget {
  const _SosReportCard({required this.report});

  final IncidentReport report;

  @override
  Widget build(BuildContext context) {
    final matric = report.reporterIdentityNumber.trim().isEmpty
        ? report.reporterId
        : report.reporterIdentityNumber.trim();
    final location = report.lastScannedLocation.trim().isEmpty
        ? 'Location unavailable'
        : report.lastScannedLocation.trim();
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0x26E11D48),
                child: Icon(Icons.sos_rounded, color: Color(0xFFE11D48)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.reporterName.isEmpty
                          ? 'Student SOS'
                          : report.reporterName,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      DateFormat.yMMMd().add_jm().format(report.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(report.status.toUpperCase()),
                side: const BorderSide(color: Color(0x66E11D48)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PassportProfileField(label: 'Matric No.', value: matric),
          const SizedBox(height: 8),
          _PassportProfileField(label: 'Last Location', value: location),
          const SizedBox(height: 8),
          Text(report.details),
        ],
      ),
    );
  }
}

class _SecurityOverridesTab extends StatelessWidget {
  const _SecurityOverridesTab();

  @override
  Widget build(BuildContext context) {
    final system = context.watch<SystemProvider>();
    final settings = system.settings;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const _UserSectionHeader(
          title: 'Security Overrides',
          subtitle: 'Campus-wide controls for critical access conditions',
        ),
        const SizedBox(height: 12),
        GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.lock_rounded),
                value: settings.globalLockdown,
                onChanged: system.loading ? null : system.toggleLockdown,
                title: const Text('Global Lockdown'),
                subtitle: const Text('Suspend all non-admin entry scans'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.build_circle_rounded),
                value: settings.maintenanceMode,
                onChanged: system.loading ? null : system.toggleMaintenanceMode,
                title: const Text('Maintenance Mode'),
                subtitle: const Text(
                  'Flag scanners and user hub as maintenance',
                ),
              ),
            ],
          ),
        ),
        if (system.error != null) ...[
          const SizedBox(height: 12),
          Text(
            system.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class _StudentDataArchiveTab extends StatelessWidget {
  const _StudentDataArchiveTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppUser>>(
      stream: FirebaseService().watchAllUsers(),
      builder: (context, snapshot) {
        final users = snapshot.data ?? const <AppUser>[];
        final students = users.where((user) => !user.isAdmin).toList();
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const _UserSectionHeader(
              title: 'Student Data Archive',
              subtitle: 'Bulk identity data management and exports',
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.7,
              children: [
                _ArchiveMetric(label: 'Profiles', value: '${users.length}'),
                _ArchiveMetric(label: 'Students', value: '${students.length}'),
                _ArchiveMetric(
                  label: 'Face Enrolled',
                  value: '${users.where((user) => user.hasFace).length}',
                ),
                _ArchiveMetric(
                  label: 'Pending Face',
                  value: '${users.where((user) => !user.hasFace).length}',
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: users.isEmpty
                  ? null
                  : () => _exportArchive(context, users),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Export Student Archive'),
            ),
            const SizedBox(height: 12),
            for (final user in users)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassCard(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      user.hasFace
                          ? Icons.verified_user_rounded
                          : Icons.person_search_rounded,
                    ),
                    title: Text(
                      user.name.isEmpty ? 'Unnamed profile' : user.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${user.identityNumber.isEmpty ? user.id : user.identityNumber}\n'
                      '${user.faculty.isEmpty ? 'Faculty pending' : user.faculty} - '
                      '${user.course.isEmpty ? user.department : user.course}',
                    ),
                    isThreeLine: true,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _exportArchive(BuildContext context, List<AppUser> users) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await UserDataExportService().writeCsv(users);
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Student archive ready to share.')),
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'FAZEKEY Student Data Archive',
          text: 'FAZEKEY student data archive',
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to export archive: $e')),
      );
    }
  }
}

class _ArchiveMetric extends StatelessWidget {
  const _ArchiveMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const Spacer(),
          Text(label),
        ],
      ),
    );
  }
}

class _ScannerDeviceManagerTab extends StatelessWidget {
  const _ScannerDeviceManagerTab();

  @override
  Widget build(BuildContext context) {
    final areas = context.watch<AreaProvider>().areas;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const _UserSectionHeader(
          title: 'Scanner Device Manager',
          subtitle: 'Entry-point scanner connectivity and zone heartbeat',
        ),
        const SizedBox(height: 12),
        if (areas.isEmpty)
          const GlassCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.sensors_off_rounded),
              title: Text('No scanner-linked zones'),
              subtitle: Text('Add zones to register monitored entry points.'),
            ),
          )
        else
          for (final area in areas)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ScannerDeviceTile(area: area),
            ),
      ],
    );
  }
}

class _ScannerDeviceTile extends StatelessWidget {
  const _ScannerDeviceTile({required this.area});

  final Area area;

  @override
  Widget build(BuildContext context) {
    final online = area.active;
    final healthyCapacity =
        area.capacity <= 0 || area.currentOccupancy <= area.capacity;
    final status = online
        ? healthyCapacity
              ? 'Online'
              : 'Capacity Alert'
        : 'Offline';
    final color = !online
        ? Theme.of(context).colorScheme.error
        : healthyCapacity
        ? const Color(0xFF32D583)
        : const Color(0xFFFDB022);
    return GlassCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.sensors_rounded, color: color),
        title: Text(
          area.name.isEmpty ? 'Entry Point ${area.roomNumber}' : area.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${area.location} - ${area.floor} - Room ${area.roomNumber}\n'
          'Last heartbeat: ${online ? 'live' : 'not reporting'}',
        ),
        trailing: Chip(
          visualDensity: VisualDensity.compact,
          label: Text(status),
          side: BorderSide(color: color.withValues(alpha: .4)),
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _AcademicSessionSetupTab extends StatelessWidget {
  const _AcademicSessionSetupTab();

  @override
  Widget build(BuildContext context) {
    final system = context.watch<SystemProvider>();
    final settings = system.settings;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const _UserSectionHeader(
          title: 'Academic Session Setup',
          subtitle: 'Sync semester dates with the Digital Identity hub',
        ),
        const SizedBox(height: 12),
        GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.event_rounded),
                title: const Text('Semester Start'),
                subtitle: Text(
                  DateFormat.yMMMd().format(settings.semesterStart),
                ),
                onTap: () => _pickDate(
                  context,
                  initial: settings.semesterStart,
                  onPicked: (date) => system.updateAcademicSession(
                    start: date,
                    end: settings.semesterEnd,
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.event_available_rounded),
                title: const Text('Semester End'),
                subtitle: Text(DateFormat.yMMMd().format(settings.semesterEnd)),
                onTap: () => _pickDate(
                  context,
                  initial: settings.semesterEnd,
                  onPicked: (date) => system.updateAcademicSession(
                    start: settings.semesterStart,
                    end: date,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate(
    BuildContext context, {
    required DateTime initial,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2025),
      lastDate: DateTime(2030),
    );
    if (picked != null) onPicked(picked);
  }
}

class _UserShell extends StatelessWidget {
  const _UserShell({
    required this.user,
    required this.index,
    required this.onIndexChanged,
  });

  final AppUser user;
  final int index;
  final ValueChanged<int> onIndexChanged;

  @override
  Widget build(BuildContext context) {
    final pages = [
      _PersonalHubTab(
        user: user,
        onOpenActivity: () => onIndexChanged(1),
        onOpenAccess: () => onIndexChanged(2),
      ),
      _MyActivityTab(user: user),
      _AccessPermissionsTab(user: user),
      _SettingsTab(user: user),
    ];
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Digital Identity'),
        ),
        body: pages[index],
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: onIndexChanged,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.badge_rounded),
              label: 'Identity',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_rounded),
              label: 'Activity',
            ),
            NavigationDestination(
              icon: Icon(Icons.verified_user_rounded),
              label: 'Access',
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

class _UserRegistrationTab extends StatefulWidget {
  const _UserRegistrationTab();

  @override
  State<_UserRegistrationTab> createState() => _UserRegistrationTabState();
}

class _UserRegistrationTabState extends State<_UserRegistrationTab> {
  final _firebase = FirebaseService();
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _identityNumber = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  String _faculty = _campusFaculties.first;
  String _program = _fsktmHonoursPrograms.first;
  String _role = 'User';
  int _accessLevel = 1;
  String? _room;
  AppUser? _editing;
  bool _saving = false;
  bool _sendingSetupEmail = false;

  @override
  void dispose() {
    _name.dispose();
    _identityNumber.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final areas = context.watch<AreaProvider>().areas;
    final roomOptions =
        areas
            .map(
              (area) => area.name.trim().isEmpty
                  ? '${area.floor} - Room ${area.roomNumber}'
                  : area.name.trim(),
            )
            .toSet()
            .toList()
          ..sort();
    final selectedRoom = _room != null && roomOptions.contains(_room)
        ? _room
        : (roomOptions.isEmpty ? null : roomOptions.first);
    if (_room != selectedRoom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _room = selectedRoom);
      });
    }

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        GlassCard(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _editing == null ? 'Register User' : 'Update User',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Full Name'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _identityNumber,
                  decoration: const InputDecoration(
                    labelText: 'Matric or Staff ID',
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('faculty-$_faculty'),
                        initialValue: _faculty,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Faculty'),
                        items: _campusFaculties
                            .map(
                              (faculty) => DropdownMenuItem(
                                value: faculty,
                                child: Text(faculty),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => _faculty = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('program-$_program'),
                        initialValue: _program,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'FSKTM Honours Program',
                        ),
                        items: _fsktmHonoursPrograms
                            .map(
                              (program) => DropdownMenuItem(
                                value: program,
                                child: Text(
                                  program,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => _program = value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _role,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: const [
                          DropdownMenuItem(value: 'User', child: Text('User')),
                          DropdownMenuItem(
                            value: 'Admin',
                            child: Text('Admin'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _role = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
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
                          if (value != null) {
                            setState(() => _accessLevel = value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (selectedRoom == null)
                  const Text('Add a room before assigning access.')
                else
                  DropdownButtonFormField<String>(
                    key: ValueKey('managed-room-$selectedRoom'),
                    initialValue: selectedRoom,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Primary Room',
                    ),
                    items: roomOptions
                        .map(
                          (room) => DropdownMenuItem(
                            value: room,
                            child: Text(
                              room,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _room = value),
                  ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: Icon(
                    _editing == null
                        ? Icons.person_add_rounded
                        : Icons.save_rounded,
                  ),
                  label: Text(
                    _saving
                        ? 'Saving'
                        : (_editing == null
                              ? 'Create Profile'
                              : 'Save Changes'),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _sendingSetupEmail
                      ? null
                      : () => _sendSetupEmail(_email.text),
                  icon: const Icon(Icons.mark_email_read_rounded),
                  label: Text(
                    _sendingSetupEmail
                        ? 'Sending Setup Email'
                        : 'Send Setup Email',
                  ),
                ),
                if (_editing != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _saving ? null : _clearForm,
                    child: const Text('Cancel Editing'),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        StreamBuilder<List<AppUser>>(
          stream: _firebase.watchAllUsers(),
          builder: (context, snapshot) {
            final users = snapshot.data ?? const <AppUser>[];
            if (snapshot.connectionState == ConnectionState.waiting &&
                users.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            return Column(
              children: [
                for (final user in users)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          child: Icon(
                            user.hasFace
                                ? Icons.face_rounded
                                : Icons.person_rounded,
                          ),
                        ),
                        title: Text(
                          user.name.isEmpty ? 'Unnamed profile' : user.name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${user.identityNumber.isEmpty ? user.id : user.identityNumber} - ${user.role} - Level ${user.accessLevel}\n${user.room}',
                        ),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) => _handleUserAction(value, user),
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                              value: 'face',
                              child: Text('Capture Face'),
                            ),
                            PopupMenuItem(
                              value: 'setup',
                              child: Text('Send Setup Email'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final room = _room?.trim() ?? '';
      final editing = _editing;
      if (editing == null) {
        await _firebase.createManagedUser(
          name: _name.text,
          identityNumber: _identityNumber.text,
          email: _email.text,
          department: _program,
          phone: _phone.text,
          room: room,
          role: _role,
          accessLevel: _accessLevel,
          course: _program,
          faculty: _faculty,
        );
      } else {
        await _firebase.updateUserProfile(
          editing.copyWith(
            name: _name.text,
            identityNumber: _identityNumber.text,
            email: _email.text,
            department: _program,
            course: _program,
            faculty: _faculty,
            phone: _phone.text,
            room: room,
            role: _role,
            accessLevel: _accessLevel,
          ),
        );
      }
      if (!mounted) return;
      _clearForm();
      messenger.showSnackBar(const SnackBar(content: Text('User saved.')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to save user: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _handleUserAction(String value, AppUser user) {
    if (value == 'edit') {
      setState(() {
        _editing = user;
        _name.text = user.name;
        _identityNumber.text = user.identityNumber;
        _email.text = user.email;
        _faculty = _selectedFaculty(user.faculty);
        _program = _selectedProgram(
          user.course.trim().isEmpty ? user.department : user.course,
        );
        _phone.text = user.phone;
        _role = user.isAdmin ? 'Admin' : 'User';
        _accessLevel = user.accessLevel.clamp(1, 3);
        _room = user.room;
      });
      return;
    }
    if (value == 'face') {
      _pushNamedAfterFrame(
        context,
        FaceRegistrationScreen.route,
        arguments: FaceRegistrationArgs(user: user),
      );
      return;
    }
    if (value == 'setup') {
      _sendSetupEmail(user.email);
      return;
    }
    _confirmDelete(user);
  }

  Future<void> _sendSetupEmail(String email) async {
    final target = email.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (target.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enter an email before sending setup.')),
      );
      return;
    }
    setState(() => _sendingSetupEmail = true);
    try {
      await _firebase.sendSetupEmail(target);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Setup email sent to $target.')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to send setup email: $e')),
      );
    } finally {
      if (mounted) setState(() => _sendingSetupEmail = false);
    }
  }

  Future<void> _confirmDelete(AppUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: Text('Remove ${user.name.isEmpty ? 'this user' : user.name}?'),
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
    if (confirmed != true) return;
    await _firebase.deleteManagedUser(user.id);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('User removed.')));
  }

  void _clearForm() {
    _form.currentState?.reset();
    setState(() {
      _editing = null;
      _name.clear();
      _identityNumber.clear();
      _email.clear();
      _phone.clear();
      _faculty = _campusFaculties.first;
      _program = _fsktmHonoursPrograms.first;
      _role = 'User';
      _accessLevel = 1;
    });
  }

  static String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  String _selectedFaculty(String value) {
    return _campusFaculties.contains(value) ? value : _campusFaculties.first;
  }

  String _selectedProgram(String value) {
    return _fsktmHonoursPrograms.contains(value)
        ? value
        : _fsktmHonoursPrograms.first;
  }
}

class _PersonalHubTab extends StatelessWidget {
  const _PersonalHubTab({
    required this.user,
    required this.onOpenActivity,
    required this.onOpenAccess,
  });

  final AppUser user;
  final VoidCallback onOpenActivity;
  final VoidCallback onOpenAccess;

  @override
  Widget build(BuildContext context) {
    final assignedZone = user.room.trim().isEmpty ? 'Not assigned' : user.room;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _StudentPassportHeader(user: user),
        const SizedBox(height: 14),
        GlassCard(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _FaceAvatar(user: user),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          'Digital Identity',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Matric No.',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              SelectableText(
                user.identityNumber.isEmpty ? user.id : user.identityNumber,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              _PassportProfileField(
                label: 'Course',
                value: user.course.trim().isEmpty
                    ? user.department
                    : user.course,
              ),
              const SizedBox(height: 10),
              _PassportProfileField(
                label: 'Faculty',
                value: user.faculty.trim().isEmpty ? 'FSKTM' : user.faculty,
              ),
              const SizedBox(height: 10),
              _PassportProfileField(
                label: 'Current Semester',
                value: user.currentSemester.trim().isEmpty
                    ? 'Semester ${user.accessLevel}'
                    : user.currentSemester,
              ),
              const SizedBox(height: 10),
              _PassportProfileField(label: 'Official Email', value: user.email),
              const SizedBox(height: 10),
              _PassportProfileField(label: 'Phone Number', value: user.phone),
              const SizedBox(height: 10),
              _PassportProfileField(
                label: 'Home Address',
                value: user.homeAddress,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _StatusBadge(
                    icon: Icons.shield_rounded,
                    label: user.hasFace
                        ? 'Biometrics: Verified'
                        : 'Biometrics: Pending',
                    color: user.hasFace
                        ? const Color(0xFF32D583)
                        : Theme.of(context).colorScheme.error,
                  ),
                  _StatusBadge(
                    icon: Icons.location_on_rounded,
                    label: 'Assigned Zone: $assignedZone',
                    color: const Color(0xFF5B8DEF),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _AcademicCalendarStrip(),
        const SizedBox(height: 16),
        const _CampusNewsFeed(),
        const SizedBox(height: 16),
        Text(
          'Campus Utilities',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.7,
          children: [
            _QuickActionTile(
              icon: Icons.history_rounded,
              label: 'Access History',
              onTap: onOpenActivity,
            ),
            _QuickActionTile(
              icon: Icons.verified_user_rounded,
              label: 'My Zones',
              onTap: onOpenAccess,
            ),
            _QuickActionTile(
              icon: Icons.face_retouching_natural_rounded,
              label: 'Re-enroll Face',
              onTap: () =>
                  _pushNamedAfterFrame(context, FaceRegistrationScreen.route),
            ),
            _QuickActionTile(
              icon: Icons.edit_rounded,
              label: 'Edit Profile',
              onTap: () =>
                  _pushNamedAfterFrame(context, EditProfileScreen.route),
            ),
          ],
        ),
      ],
    );
  }
}

class _StudentPassportHeader extends StatelessWidget {
  const _StudentPassportHeader({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: StreamBuilder<DateTime>(
        stream: Stream.periodic(
          const Duration(seconds: 1),
          (_) => DateTime.now(),
        ),
        initialData: DateTime.now(),
        builder: (context, snapshot) {
          final now = snapshot.data ?? DateTime.now();
          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hello, ${user.name.isEmpty ? 'Student' : user.name}!',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Welcome to your UTHM campus identity portal.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    DateFormat.Hm().format(now),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    DateFormat('EEEE, d MMMM yyyy').format(now),
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AcademicCalendarStrip extends StatelessWidget {
  const _AcademicCalendarStrip();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SystemProvider>().settings;
    final start = settings.semesterStart;
    final end = settings.semesterEnd;
    final items = [
      (DateFormat('d MMM').format(start), 'Semester Begins', 'Academic Office'),
      (
        DateFormat('d MMM').format(start.add(const Duration(days: 14))),
        'Add/Drop Deadline',
        'Programme Units',
      ),
      (
        DateFormat(
          'd MMM',
        ).format(start.add(Duration(days: end.difference(start).inDays ~/ 2))),
        'Mid-Semester Review',
        'Faculty Office',
      ),
      (DateFormat('d MMM').format(end), 'Semester Ends', 'Academic Office'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Academic Calendar',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 118,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              return SizedBox(
                width: 210,
                child: GlassCard(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.$1,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.$2,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      Text(
                        item.$3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
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

class _CampusNewsFeed extends StatelessWidget {
  const _CampusNewsFeed();

  static const _items = [
    (
      Icons.campaign_rounded,
      'Campus News',
      'Authorized identity checks are active at all FSKTM restricted zones.',
    ),
    (
      Icons.verified_user_rounded,
      'Security Advisory',
      'Keep your digital identity profile current before lab access scans.',
    ),
    (
      Icons.school_rounded,
      'Academic Notice',
      'Honours programme consultation slots open this week at the faculty office.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Campus News',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        for (final item in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(item.$1),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.$2,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(item.$3),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PassportProfileField extends StatelessWidget {
  const _PassportProfileField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        Expanded(
          child: Text(
            value.trim().isEmpty ? 'Not provided' : value,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, color: color, size: 18),
      label: Text(label),
      side: BorderSide(color: color.withValues(alpha: .45)),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label, textAlign: TextAlign.center),
    );
  }
}

class _MyActivityTab extends StatelessWidget {
  const _MyActivityTab({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AccessLog>>(
      stream: FirebaseService().watchUserLogs(user.id),
      builder: (context, snapshot) {
        final logs = snapshot.data ?? const <AccessLog>[];
        if (snapshot.connectionState == ConnectionState.waiting &&
            logs.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (logs.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(18),
            children: const [
              _UserSectionHeader(
                title: 'Personal Access History',
                subtitle: 'Your private campus entry record',
              ),
              SizedBox(height: 120),
              Center(child: Text('No activity yet.')),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const _UserSectionHeader(
              title: 'Personal Access History',
              subtitle: 'Your private campus entry record',
            ),
            const SizedBox(height: 12),
            for (final log in logs)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _LogCard(
                  log: log,
                  onSnapshot: () {},
                  showSnapshotAction: false,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _UserSectionHeader extends StatelessWidget {
  const _UserSectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AccessPermissionsTab extends StatelessWidget {
  const _AccessPermissionsTab({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final areas = context.watch<AreaProvider>().areas;
    final allowed = areas.where(user.canAccessArea).toList();
    final denied = areas.where((area) => !user.canAccessArea(area)).toList();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current Access',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text('Role: ${user.role}'),
              Text('Access level: ${user.accessLevel}'),
              Text(
                'Primary room: ${user.room.isEmpty ? 'Not assigned' : user.room}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Allowed Rooms',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        if (allowed.isEmpty)
          const Text('No room access is currently assigned.')
        else
          for (final area in allowed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AreaPermissionTile(area: area, allowed: true),
            ),
        const SizedBox(height: 8),
        Text(
          'View Only',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        for (final area in denied)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _AreaPermissionTile(area: area, allowed: false),
          ),
      ],
    );
  }
}

class _AreaPermissionTile extends StatelessWidget {
  const _AreaPermissionTile({required this.area, required this.allowed});

  final Area area;
  final bool allowed;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          allowed ? Icons.check_circle_rounded : Icons.lock_rounded,
          color: allowed ? const Color(0xFF32D583) : null,
        ),
        title: Text(
          area.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${area.location} - ${area.floor} - Room ${area.roomNumber}',
        ),
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final logs = context.watch<LogProvider>().logs;
    final logProvider = context.watch<LogProvider>();
    final system = context.watch<SystemProvider>();
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
          name: user.name.isEmpty ? 'Administrator' : user.name,
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
                    _pushNamedAfterFrame(context, AddAreaScreen.route),
                child: const Text('Add Area'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonal(
                onPressed: () => _exportUserData(context),
                child: const Text('Export Clean CSV'),
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
          onPressed: () => _pushNamedAfterFrame(context, FaceLoginScreen.route),
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
        const SnackBar(content: Text('Security report ready to share.')),
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Campus Access Security Report',
          text: 'Campus access security report',
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
        const SnackBar(content: Text('Clean user export is ready to share.')),
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Campus Access User Data Export',
          text: 'Campus access user data export',
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

const _zoneStatusColor = Color(0xFF5B8DEF);

class _AccessControlZonesTab extends StatelessWidget {
  const _AccessControlZonesTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AreaProvider>();
    return StreamBuilder<List<AppUser>>(
      stream: FirebaseService().watchAllUsers(),
      builder: (context, snapshot) {
        final users = snapshot.data ?? const <AppUser>[];
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _pushNamedAfterFrame(context, AddAreaScreen.route),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Zone'),
          ),
          body: RefreshIndicator(
            onRefresh: provider.refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(18),
              itemCount: provider.areas.length,
              separatorBuilder: (_, index) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final area = provider.areas[i];
                return _ZoneAclCard(
                  area: area,
                  users: users,
                  loadingUsers:
                      snapshot.connectionState == ConnectionState.waiting,
                  provider: provider,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _ZoneAclCard extends StatelessWidget {
  const _ZoneAclCard({
    required this.area,
    required this.users,
    required this.loadingUsers,
    required this.provider,
  });

  final Area area;
  final List<AppUser> users;
  final bool loadingUsers;
  final AreaProvider provider;

  @override
  Widget build(BuildContext context) {
    final capacity = area.capacity <= 0 ? 1 : area.capacity;
    final occupancyValue = (area.currentOccupancy / capacity).clamp(0.0, 1.0);
    final highSecurity = _isHighSecurity(area);
    return Opacity(
      opacity: area.active ? 1 : .5,
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      area.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (highSecurity)
                    const Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('High security'),
                    ),
                ],
              ),
              subtitle: Text(
                '${area.location} - ${area.floor} - Room ${area.roomNumber}\n'
                'Occupancy ${area.currentOccupancy}${area.capacity > 0 ? ' / ${area.capacity}' : ''}\n'
                'Roles: ${area.allowedRoles.isEmpty ? 'All' : area.allowedRoles.join(', ')}',
              ),
              isThreeLine: true,
              trailing: Switch(
                value: area.active,
                onChanged: (value) =>
                    provider.updateArea(area.copyWith(active: value)),
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: occupancyValue,
                minHeight: 4,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: .58),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  _zoneStatusColor,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 4, bottom: 8),
              leading: const Icon(Icons.groups_rounded),
              title: const Text('Zone Capacity Control'),
              subtitle: Text(
                '${area.currentOccupancy} occupied of ${area.capacity <= 0 ? 'unlimited' : area.capacity}',
              ),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _CapacityStepper(
                        label: 'Occupancy',
                        value: area.currentOccupancy,
                        onDecrease: area.currentOccupancy <= 0
                            ? null
                            : () => _setOccupancy(area.currentOccupancy - 1),
                        onIncrease: () =>
                            _setOccupancy(area.currentOccupancy + 1),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _CapacityStepper(
                        label: 'Capacity',
                        value: area.capacity,
                        onDecrease: area.capacity <= 0
                            ? null
                            : () => _setCapacity(area.capacity - 1),
                        onIncrease: () => _setCapacity(area.capacity + 1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: area.currentOccupancy == 0
                        ? null
                        : () => _setOccupancy(0),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Reset Occupancy'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 4),
              leading: const Icon(Icons.assignment_ind_rounded),
              title: const Text('Access Control List'),
              subtitle: Text(
                '${area.allowedUserIds.length} granted, ${area.revokedUserIds.length} revoked',
              ),
              children: [
                if (loadingUsers)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  )
                else if (users.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(0, 8, 0, 16),
                    child: Text('No users are available for ACL assignment.'),
                  )
                else
                  for (final user in users)
                    _AclUserTile(
                      area: area,
                      user: user,
                      onGrant: () => _grant(user),
                      onRevoke: () => _revoke(user),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _isHighSecurity(Area area) {
    final name = '${area.name} ${area.roomNumber}'.toLowerCase();
    return name.contains('it') ||
        name.contains('server') ||
        name.contains('security') ||
        name.contains('restricted');
  }

  Future<void> _grant(AppUser user) {
    final allowed = {...area.allowedUserIds, user.id}.toList()..sort();
    final revoked = area.revokedUserIds.where((id) => id != user.id).toList();
    return provider.updateArea(
      area.copyWith(allowedUserIds: allowed, revokedUserIds: revoked),
    );
  }

  Future<void> _revoke(AppUser user) {
    final allowed = area.allowedUserIds.where((id) => id != user.id).toList();
    final revoked = {...area.revokedUserIds, user.id}.toList()..sort();
    return provider.updateArea(
      area.copyWith(allowedUserIds: allowed, revokedUserIds: revoked),
    );
  }

  Future<void> _setOccupancy(int value) {
    return provider.updateArea(
      area.copyWith(currentOccupancy: value.clamp(0, 9999).toInt()),
    );
  }

  Future<void> _setCapacity(int value) {
    return provider.updateArea(
      area.copyWith(capacity: value.clamp(0, 9999).toInt()),
    );
  }
}

class _CapacityStepper extends StatelessWidget {
  const _CapacityStepper({
    required this.label,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String label;
  final int value;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: .28),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Decrease $label',
                  onPressed: onDecrease,
                  icon: const Icon(Icons.remove_rounded),
                ),
                SizedBox(
                  width: 42,
                  child: Text(
                    '$value',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  tooltip: 'Increase $label',
                  onPressed: onIncrease,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AclUserTile extends StatelessWidget {
  const _AclUserTile({
    required this.area,
    required this.user,
    required this.onGrant,
    required this.onRevoke,
  });

  final Area area;
  final AppUser user;
  final VoidCallback onGrant;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final explicitlyGranted = area.allowedUserIds.contains(user.id);
    final explicitlyRevoked = area.revokedUserIds.contains(user.id);
    final effectiveAccess = user.canAccessArea(area);
    final statusColor = explicitlyRevoked
        ? Theme.of(context).colorScheme.error
        : effectiveAccess
        ? const Color(0xFF32D583)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final id = user.identityNumber.isEmpty ? user.id : user.identityNumber;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.person_pin_rounded, color: statusColor),
      title: Text(user.name.isEmpty ? 'Unnamed profile' : user.name),
      subtitle: Text(
        '$id - ${_aclStatus(explicitlyGranted, explicitlyRevoked, effectiveAccess)}',
      ),
      trailing: Wrap(
        spacing: 6,
        children: [
          TextButton(
            onPressed: explicitlyGranted ? null : onGrant,
            child: const Text('Grant'),
          ),
          TextButton(
            onPressed: explicitlyRevoked ? null : onRevoke,
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
  }

  String _aclStatus(bool granted, bool revoked, bool effectiveAccess) {
    if (granted) return 'Explicitly granted';
    if (revoked) return 'Revoked';
    return effectiveAccess ? 'Allowed by policy' : 'No access';
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
  const _LogCard({
    required this.log,
    required this.onSnapshot,
    this.showSnapshotAction = true,
  });

  final AccessLog log;
  final VoidCallback onSnapshot;
  final bool showSnapshotAction;

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
                    if (showSnapshotAction &&
                        !log.granted &&
                        log.snapshotPath != null)
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

class _SettingsTab extends StatefulWidget {
  const _SettingsTab({this.user});

  final AppUser? user;

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  bool _accessAlerts = true;
  bool _biometricAlerts = true;
  bool _sosBusy = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final system = context.watch<SystemProvider>();
    final activeUser = widget.user ?? auth.user;
    final settings = system.settings;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        GlassCard(
          child: Row(
            children: [
              _FaceAvatar(user: activeUser),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activeUser?.name ?? 'Administrator',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      activeUser?.email ?? '',
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
        if (!auth.isAdmin) ...[
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.face_retouching_natural_rounded),
                  title: const Text('Re-enroll Face Data'),
                  subtitle: const Text('Update your biometric access profile'),
                  onTap: () => _pushNamedAfterFrame(
                    context,
                    FaceRegistrationScreen.route,
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_rounded),
                  value: _accessAlerts,
                  onChanged: (value) => setState(() => _accessAlerts = value),
                  title: const Text('Real-time Access Alerts'),
                  subtitle: const Text(
                    'Notify me when access events are logged',
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.security_rounded),
                  value: _biometricAlerts,
                  onChanged: (value) =>
                      setState(() => _biometricAlerts = value),
                  title: const Text('Biometric Status Alerts'),
                  subtitle: const Text('Notify me about enrollment changes'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE11D48),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: _sosBusy || activeUser == null
                ? null
                : () => _raiseCampusSos(context, activeUser),
            icon: const Icon(Icons.sos_rounded),
            label: Text(_sosBusy ? 'Sending SOS' : 'Campus Emergency SOS'),
          ),
          const SizedBox(height: 12),
        ],
        if (auth.isAdmin) ...[
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
        ],
        _SettingTile(
          title: 'Edit Profile',
          onTap: () => _pushNamedAfterFrame(
            context,
            EditProfileScreen.route,
            rootNavigator: true,
          ),
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
        if (!auth.isAdmin)
          FilledButton.tonal(
            onPressed: auth.loading
                ? null
                : () async {
                    final ok = await auth.logout();
                    if (!ok) return;
                    if (!context.mounted) return;
                    _pushAndClearAfterFrame(context, WelcomeScreen.route);
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

  Future<void> _raiseCampusSos(BuildContext context, AppUser user) async {
    final messenger = ScaffoldMessenger.of(context);
    final userLogs =
        context
            .read<LogProvider>()
            .logs
            .where((log) => log.userId == user.id)
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final lastScannedLocation = userLogs.isEmpty
        ? (user.room.isEmpty ? 'Digital Identity' : user.room)
        : userLogs.first.areaName;
    setState(() => _sosBusy = true);
    try {
      await FirebaseService().addIncidentReport(
        reporterId: user.id,
        reporterName: user.name.isEmpty ? 'Student' : user.name,
        title: 'Campus Emergency SOS',
        severity: 'Critical',
        areaName: user.room.isEmpty ? 'Digital Identity' : user.room,
        reporterIdentityNumber: user.identityNumber.isEmpty
            ? user.id
            : user.identityNumber,
        lastScannedLocation: lastScannedLocation,
        details:
            'Emergency SOS triggered from the Digital Identity settings panel.',
      );
      if (!context.mounted) return;
      await context.read<AlertProvider>().raiseIntrusionAlert(
        title: 'Campus Emergency SOS',
        body:
            '${user.name.isEmpty ? 'A student' : user.name} requested immediate assistance.',
        severity: 'Critical',
      );
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Campus emergency alert sent.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to send emergency alert: $e')),
      );
    } finally {
      if (mounted) setState(() => _sosBusy = false);
    }
  }

  Future<void> _openHelpSupport(
    BuildContext context,
    String administratorEmail,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri(
      scheme: 'mailto',
      path: administratorEmail.trim().isEmpty
          ? 'administrator@campus-access.local'
          : administratorEmail.trim(),
      queryParameters: const {
        'subject': 'Campus Access Support Request',
        'body':
            'Hello Administrator,\r\n\r\nI need assistance with campus access.\r\n\r\nRegards,',
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
