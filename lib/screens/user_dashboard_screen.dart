import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/access_grant.dart';
import '../models/app_user.dart';
import '../models/area.dart';
import '../models/room_access_record.dart';
import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';
import '../widgets/app_background.dart';
import 'edit_profile_screen.dart';
import 'welcome_screen.dart';

class UserDashboardScreen extends StatefulWidget {
  const UserDashboardScreen({super.key});
  static const route = '/student_dashboard';

  @override
  State<UserDashboardScreen> createState() => _UserDashboardScreenState();
}

class _UserDashboardScreenState extends State<UserDashboardScreen> {
  int _index = 0;
  DateTime _clock = DateTime.now();
  Timer? _timer;
  bool _nightMode = false;
  String _language = 'English';
  bool _passwordDialogShowing = false;
  String? _passwordDialogUserId;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _clock = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final firebase = context.read<FirebaseService>();
    final text = _UserText(_language);
    return StreamBuilder<AppUser?>(
      stream: auth.watchActiveUserProfile(),
      initialData: auth.user,
      builder: (context, snapshot) {
        final user = snapshot.data ?? auth.user;
        if (user != null && user.requiresPasswordChange && !user.isAdmin) {
          _scheduleTemporaryPasswordChange(user);
        }
        return AppBackground(
          child: Scaffold(
            backgroundColor: _nightMode
                ? const Color(0xFF0F172A)
                : AppBackground.slateGray,
            body: IndexedStack(
              index: _index,
              children: [
                _HomeTab(
                  user: user,
                  firebase: firebase,
                  clock: _clock,
                  text: text,
                ),
                _HistoryTab(user: user, firebase: firebase, text: text),
                _ProfileTab(user: user, firebase: firebase, text: text),
                _SettingsTab(
                  user: user,
                  firebase: firebase,
                  text: text,
                  language: _language,
                  nightMode: _nightMode,
                  onLanguageChanged: (value) =>
                      setState(() => _language = value),
                  onNightModeChanged: (value) =>
                      setState(() => _nightMode = value),
                ),
              ],
            ),
            bottomNavigationBar: _UserBottomBar(
              selectedIndex: _index,
              onChanged: (value) => setState(() => _index = value),
              text: text,
            ),
          ),
        );
      },
    );
  }

  void _scheduleTemporaryPasswordChange(AppUser user) {
    if (_passwordDialogShowing && _passwordDialogUserId == user.id) return;
    _passwordDialogShowing = true;
    _passwordDialogUserId = user.id;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _TemporaryPasswordChangeDialog(user: user),
      );
      if (!mounted) return;
      _passwordDialogShowing = false;
      final current = context.read<AuthProvider>().user;
      if (current?.requiresPasswordChange == true && current?.isAdmin != true) {
        _scheduleTemporaryPasswordChange(current!);
      } else {
        _passwordDialogUserId = null;
      }
    });
  }
}

class _TemporaryPasswordChangeDialog extends StatefulWidget {
  const _TemporaryPasswordChangeDialog({required this.user});

  final AppUser user;

  @override
  State<_TemporaryPasswordChangeDialog> createState() =>
      _TemporaryPasswordChangeDialogState();
}

class _TemporaryPasswordChangeDialogState
    extends State<_TemporaryPasswordChangeDialog> {
  final _form = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _submitted = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        title: const Text('Change temporary password'),
        content: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'For account accountability, replace the temporary password before continuing as ${widget.user.name.trim().isEmpty ? widget.user.email : widget.user.name}.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Use at least 12 characters.\nCombine uppercase/lowercase letters, numbers, and symbols.',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _currentPassword,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Temporary Password',
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _newPassword,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New Password',
                    ),
                    validator: _newPasswordValidator,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _confirmPassword,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm New Password',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Required';
                      }
                      if (value.trim() != _newPassword.text.trim()) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                  if (_submitted && _error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_reset_rounded),
            label: Text(_saving ? 'Updating' : 'Update Password'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _error = null;
    });
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.completeTemporaryPasswordChange(
      currentPassword: _currentPassword.text,
      newPassword: _newPassword.text,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _saving = false;
        _error = auth.error ?? 'Unable to update password.';
      });
      return;
    }
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  String? _newPasswordValidator(String? value) {
    final password = value?.trim() ?? '';
    if (password.isEmpty) return 'Required';
    if (password.length < 12) return 'Use at least 12 characters';
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Add an uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'Add a lowercase letter';
    }
    if (!RegExp(r'\d').hasMatch(password)) return 'Add a number';
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      return 'Add a symbol';
    }
    if (password == _currentPassword.text.trim()) {
      return 'Use a different password';
    }
    return null;
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.user,
    required this.firebase,
    required this.clock,
    required this.text,
  });

  final AppUser? user;
  final FirebaseService firebase;
  final DateTime clock;
  final _UserText text;

  @override
  Widget build(BuildContext context) {
    final displayName = user?.name.trim().isNotEmpty == true
        ? user!.name.trim()
        : 'User';
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
        children: [
          _Panel(
            child: Row(
              children: [
                _SmallProfileAvatar(
                  photoPath: user?.photoUrl,
                  fallback: displayName.characters.first.toUpperCase(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        text.welcomeUser(displayName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: .2,
                              color: const Color(0xFF0F172A),
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        text.homeSubtitleFor(user),
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (text.homeAcademicTitleFor(user) != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          text.homeAcademicTitleFor(user)!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF0D9488),
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormat('d MMM yyyy').format(clock),
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          DateFormat('h:mm:ss a').format(clock),
                          style: const TextStyle(
                            color: Color(0xFF0D9488),
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    if (user != null) ...[
                      const SizedBox(width: 4),
                      _UserNotificationBell(user: user!, firebase: firebase),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _CampusNewsCarousel(firebase: firebase),
          const SizedBox(height: 14),
          _CurrentRoomCard(user: user, firebase: firebase, text: text),
          const SizedBox(height: 14),
          _HomeRoomActionButton(user: user, firebase: firebase, text: text),
          const SizedBox(height: 16),
          Center(
            child: Opacity(
              opacity: .5,
              child: Image.asset(
                'assets/images/logo3_.png',
                width: 118,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CampusNewsCarousel extends StatefulWidget {
  const _CampusNewsCarousel({required this.firebase});
  final FirebaseService firebase;

  @override
  State<_CampusNewsCarousel> createState() => _CampusNewsCarouselState();
}

class _CampusNewsCarouselState extends State<_CampusNewsCarousel> {
  final _controller = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_index + 1) % _campusNewsCount;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.firebase.firestore
          .collection('campusNews')
          .where('active', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        final news =
            snapshot.data?.docs.map(_CampusNews.fromDoc).toList() ??
            const <_CampusNews>[];
        final visibleItems = _campusNewsWithDefaults(news);
        return _Panel(
          child: SizedBox(
            height: 184,
            child: Stack(
              children: [
                PageView.builder(
                  controller: _controller,
                  itemCount: visibleItems.length,
                  onPageChanged: (value) => setState(() => _index = value),
                  itemBuilder: (context, page) {
                    final item = visibleItems[page];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 34),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FDFF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE0F2FE)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF0D9488,
                              ).withValues(alpha: .08),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              item.dateLabel,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF0D9488),
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              item.title,
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => _openNewsLink(context, item),
                              child: const Text(
                                'Read more',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => _goTo((_index - 1) % visibleItems.length),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: () => _goTo((_index + 1) % visibleItems.length),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < visibleItems.length; i++)
                        Container(
                          width: _index == i ? 18 : 6,
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: _index == i
                                ? const Color(0xFF0D9488)
                                : const Color(0xFFBAE6FD),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _goTo(int page) {
    if (!_controller.hasClients) return;
    final normalized = page < 0 ? _campusNewsCount - 1 : page;
    _controller.animateToPage(
      normalized,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openNewsLink(BuildContext context, _CampusNews item) async {
    final link = item.link.trim();
    if (link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Full article link is not available yet.'),
        ),
      );
      return;
    }
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _CurrentRoomCard extends StatelessWidget {
  const _CurrentRoomCard({
    required this.user,
    required this.firebase,
    required this.text,
  });
  final AppUser? user;
  final FirebaseService firebase;
  final _UserText text;

  @override
  Widget build(BuildContext context) {
    final currentUser = user;
    if (currentUser == null) return const SizedBox.shrink();
    return StreamBuilder<List<AccessGrant>>(
      stream: firebase.watchAccessGrants(userId: currentUser.id, limit: 80),
      builder: (context, grantSnapshot) {
        final grants = grantSnapshot.data ?? const <AccessGrant>[];
        return StreamBuilder<List<Area>>(
          stream: firebase.watchAreas(),
          builder: (context, areaSnapshot) {
            final areas = areaSnapshot.data ?? const <Area>[];
            return StreamBuilder<RoomAccessRecord?>(
              stream: firebase.watchActiveRoomSession(currentUser.id),
              builder: (context, snapshot) {
                final record = snapshot.data;
                final accessRoom = record?.areaName;
                return _Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text.currentRoom,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .25,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (accessRoom == null)
                        Text(
                          text.noActiveRoom,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      else ...[
                        Row(
                          children: [
                            Icon(
                              record == null
                                  ? Icons.meeting_room_rounded
                                  : Icons.check_circle_rounded,
                              color: const Color(0xFF16A34A),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                accessRoom,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          record == null
                              ? text.accessReady
                              : '${text.checkedIn}: ${DateFormat.yMMMd().add_jm().format(record.timestamp)}',
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _RoomCapacityList(
                        rooms: _visibleRooms(currentUser, grants),
                        areas: areas,
                      ),
                      if (record != null) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () async {
                              await firebase.closeActiveRoomSessionForUser(
                                currentUser,
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(text.signedOutRoom)),
                              );
                            },
                            icon: const Icon(Icons.logout_rounded),
                            label: Text(text.signOutRoom),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _HomeRoomActionButton extends StatelessWidget {
  const _HomeRoomActionButton({
    required this.user,
    required this.firebase,
    required this.text,
  });

  final AppUser? user;
  final FirebaseService firebase;
  final _UserText text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: user == null ? null : () => _showRoomActionDialog(context),
        icon: const Icon(Icons.logout_rounded),
        label: Text(text.exitRoom),
      ),
    );
  }

  Future<void> _showRoomActionDialog(BuildContext context) async {
    final currentUser = user;
    if (currentUser == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text.roomActionTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.exit_to_app_rounded),
                  title: Text(
                    text.exitRoom,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(text.exitRoomNote),
                  onTap: () async {
                    final auth = context.read<AuthProvider>();
                    Navigator.pop(sheetContext);
                    await firebase.closeActiveRoomSessionForUser(currentUser);
                    final ok = await auth.logout();
                    if (!context.mounted || !ok) return;
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      WelcomeScreen.route,
                      (_) => false,
                    );
                  },
                ),
                const Divider(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.meeting_room_rounded),
                  title: Text(
                    text.enterNewRoom,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(text.enterNewRoomNote),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    showDialog<void>(
                      context: context,
                      builder: (_) => _NewRoomRequestDialog(
                        user: currentUser,
                        firebase: firebase,
                        text: text,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NewRoomRequestDialog extends StatefulWidget {
  const _NewRoomRequestDialog({
    required this.user,
    required this.firebase,
    required this.text,
  });

  final AppUser user;
  final FirebaseService firebase;
  final _UserText text;

  @override
  State<_NewRoomRequestDialog> createState() => _NewRoomRequestDialogState();
}

class _NewRoomRequestDialogState extends State<_NewRoomRequestDialog> {
  String? _selectedAreaId;
  List<Area> _activeAreas = const [];
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.text.enterNewRoom),
      content: StreamBuilder<List<Area>>(
        stream: widget.firebase.watchAreas(),
        builder: (context, snapshot) {
          final areas = _uniqueActiveAreas(snapshot.data ?? const <Area>[]);
          if (areas.isEmpty) return Text(widget.text.noRoomsAvailable);
          _activeAreas = areas;
          final selectedId = areas.any((area) => area.id == _selectedAreaId)
              ? _selectedAreaId
              : areas.first.id;
          _selectedAreaId = selectedId;
          return DropdownButtonFormField<String>(
            initialValue: selectedId,
            isExpanded: true,
            decoration: InputDecoration(labelText: widget.text.currentRoom),
            items: [
              for (final area in areas)
                DropdownMenuItem(
                  value: area.id,
                  child: Text(
                    _areaDisplay(area),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _sending
                ? null
                : (value) => setState(() => _selectedAreaId = value),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: Text(widget.text.close),
        ),
        FilledButton.icon(
          onPressed: _sending || _selectedAreaId == null ? null : _sendRequest,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_rounded),
          label: Text(widget.text.send),
        ),
      ],
    );
  }

  Future<void> _sendRequest() async {
    final area = _selectedArea();
    if (area == null) return;
    setState(() => _sending = true);
    try {
      await widget.firebase.createRoomAccessRequest(
        user: widget.user,
        area: area,
        areaName: _areaDisplay(area),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(widget.text.roomRequestSent)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Area? _selectedArea() {
    final selectedId = _selectedAreaId;
    if (selectedId == null) return null;
    for (final area in _activeAreas) {
      if (area.id == selectedId) return area;
    }
    return null;
  }
}

class _InlineInfo extends StatelessWidget {
  const _InlineInfo({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Text(
              '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomCapacityList extends StatelessWidget {
  const _RoomCapacityList({required this.rooms, required this.areas});

  final List<String> rooms;
  final List<Area> areas;

  @override
  Widget build(BuildContext context) {
    if (rooms.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final room in rooms.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RoomCapacityRow(room: room, area: _matchingArea(room)),
          ),
      ],
    );
  }

  Area? _matchingArea(String room) {
    final key = _accessKey(room);
    for (final area in areas) {
      if (_areaRoomKeys(area).contains(key)) {
        return area;
      }
    }
    return null;
  }
}

class _RoomCapacityRow extends StatelessWidget {
  const _RoomCapacityRow({required this.room, required this.area});

  final String room;
  final Area? area;

  @override
  Widget build(BuildContext context) {
    final currentArea = area;
    final capacity = currentArea?.capacity ?? 0;
    final occupied = currentArea?.currentOccupancy ?? 0;
    final label = capacity <= 0
        ? 'Capacity available'
        : '$occupied / $capacity occupied';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FDFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0F2FE)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.meeting_room_rounded, color: Color(0xFF0D9488)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                room,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

DateTime? _latestGrantExpiry(List<AccessGrant> grants) {
  final active = grants.where((grant) => grant.active).toList()
    ..sort((a, b) => b.endAt.compareTo(a.endAt));
  return active.isEmpty ? null : active.first.endAt;
}

List<String> _visibleRooms(AppUser user, List<AccessGrant> grants) {
  final values = <String>[
    ...grants.map((grant) => grant.areaName),
    ...user.assignedRooms,
  ];
  final rooms = <String>[];
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) continue;
    if (rooms.any((room) => _accessKey(room) == _accessKey(trimmed))) continue;
    rooms.add(trimmed);
  }
  return rooms;
}

String _accessKey(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({
    required this.user,
    required this.firebase,
    required this.text,
  });
  final AppUser? user;
  final FirebaseService firebase;
  final _UserText text;

  @override
  Widget build(BuildContext context) {
    final currentUser = user;
    if (currentUser == null) return const SizedBox.shrink();
    return SafeArea(
      bottom: false,
      child: StreamBuilder<List<RoomAccessRecord>>(
        stream: firebase.watchUserRoomAccessRecords(currentUser.id, limit: 200),
        builder: (context, snapshot) {
          final records = snapshot.data ?? const <RoomAccessRecord>[];
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const Text(
                'History',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .3,
                ),
              ),
              const SizedBox(height: 12),
              _HistorySummary(records: records),
              const SizedBox(height: 12),
              if (records.isEmpty)
                const _Panel(child: Text('No access history yet.'))
              else
                for (final record in records)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _Panel(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          record.areaName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          DateFormat.yMMMd().add_jm().format(record.timestamp),
                        ),
                        trailing: Text(
                          record.event.toUpperCase(),
                          style: TextStyle(
                            color: record.isEntry
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFE11D48),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({
    required this.user,
    required this.firebase,
    required this.text,
  });
  final AppUser? user;
  final FirebaseService firebase;
  final _UserText text;

  @override
  Widget build(BuildContext context) {
    final pass = _AccessPass.fromUser(user);
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _ProfilePassCard(pass: pass, user: user, firebase: firebase),
          if (user != null) ...[
            const SizedBox(height: 14),
            StreamBuilder<List<AccessGrant>>(
              stream: firebase.watchAccessGrants(userId: user!.id, limit: 80),
              builder: (context, snapshot) {
                final validUntil =
                    user!.accessValidUntil ??
                    _latestGrantExpiry(snapshot.data ?? const <AccessGrant>[]);
                return _Panel(
                  child: _InlineInfo(
                    label: text.validUntil,
                    value: validUntil == null
                        ? text.noExpiryAvailable
                        : DateFormat.yMMMd().add_jm().format(validUntil),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 14),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Room Access',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .25,
                  ),
                ),
                const SizedBox(height: 10),
                StreamBuilder<List<Area>>(
                  stream: firebase.watchAreas(),
                  builder: (context, snapshot) => _RoomPermissionGrid(
                    rooms: pass.rooms,
                    areas: snapshot.data ?? const <Area>[],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistorySummary extends StatelessWidget {
  const _HistorySummary({required this.records});

  final List<RoomAccessRecord> records;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final record in records.where((record) => record.isEntry)) {
      counts.update(record.areaName, (value) => value + 1, ifAbsent: () => 1);
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Room Summary',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: .25,
            ),
          ),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            const Text('No room visits recorded yet.')
          else
            for (final entry in entries.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      '${entry.value} times',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    required this.user,
    required this.firebase,
    required this.text,
    required this.language,
    required this.nightMode,
    required this.onLanguageChanged,
    required this.onNightModeChanged,
  });

  final AppUser? user;
  final FirebaseService firebase;
  final _UserText text;
  final String language;
  final bool nightMode;
  final ValueChanged<String> onLanguageChanged;
  final ValueChanged<bool> onNightModeChanged;

  @override
  Widget build(BuildContext context) {
    final selectedLanguage = _validLanguage(language);
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Settings',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: .3,
            ),
          ),
          const SizedBox(height: 12),
          if (user != null) ...[
            _SettingsProfileCard(user: user!, firebase: firebase),
            const SizedBox(height: 10),
          ],
          _Panel(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_rounded),
              title: Text(
                text.editProfile,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(text.editProfileNote),
              onTap: () =>
                  Navigator.pushNamed(context, EditProfileScreen.route),
            ),
          ),
          const SizedBox(height: 10),
          _Panel(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.support_agent_rounded),
              title: Text(
                text.helpSupport,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(text.helpSupportNote),
              onTap: user == null
                  ? null
                  : () => showDialog<void>(
                      context: context,
                      builder: (_) => _SupportRequestDialog(
                        user: user!,
                        firebase: firebase,
                        text: text,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          _Panel(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_reset_rounded),
              title: Text(
                text.changePassword,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(text.forgotPasswordNote),
              onTap: () async {
                final auth = context.read<AuthProvider>();
                final ok = await auth.sendPasswordReset();
                if (!context.mounted) return;
                if (ok) {
                  await showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(text.forgotPassword),
                      content: Text(text.checkEmail),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(text.close),
                        ),
                      ],
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(auth.error ?? text.actionFailed)),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 10),
          _Panel(
            child: Column(
              children: [
                SwitchListTile(
                  value: nightMode,
                  onChanged: onNightModeChanged,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    text.nightMode,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
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
          const SizedBox(height: 10),
          _Panel(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout_rounded),
              title: const Text(
                'Sign Out',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              onTap: () async {
                final ok = await context.read<AuthProvider>().logout();
                if (!context.mounted || !ok) return;
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil(WelcomeScreen.route, (_) => false);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UserNotificationBell extends StatelessWidget {
  const _UserNotificationBell({required this.user, required this.firebase});

  final AppUser user;
  final FirebaseService firebase;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firebase.watchUserNotifications(user.id, limit: 30),
      builder: (context, snapshot) {
        final docs = [...?snapshot.data?.docs]
          ..sort((a, b) {
            final aTime = (a.data()['createdAt'] as Timestamp?)?.toDate();
            final bTime = (b.data()['createdAt'] as Timestamp?)?.toDate();
            return (bTime ?? DateTime(0)).compareTo(aTime ?? DateTime(0));
          });
        final unread = docs.where((doc) => doc.data()['read'] != true).length;
        return IconButton(
          tooltip: 'Notifications',
          onPressed: () => _showNotifications(context, docs),
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

  Future<void> _showNotifications(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final visibleDocs = docs.take(12).toList();
    unawaited(firebase.markUserNotificationsRead(user.id).catchError((_) {}));
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notifications'),
        content: SizedBox(
          width: 420,
          child: docs.isEmpty
              ? const Text('No notifications yet.')
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final doc in visibleDocs) ...[
                        _UserNotificationTile(data: doc.data()),
                        if (doc != visibleDocs.last) const Divider(height: 16),
                      ],
                    ],
                  ),
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

class _SettingsProfileCard extends StatelessWidget {
  const _SettingsProfileCard({required this.user, required this.firebase});

  final AppUser user;
  final FirebaseService firebase;

  @override
  Widget build(BuildContext context) {
    return _ProfilePassCard(
      pass: _AccessPass.fromUser(user),
      user: user,
      firebase: firebase,
    );
  }
}

class _UserNotificationTile extends StatelessWidget {
  const _UserNotificationTile({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? 'Notification').toString();
    final message = (data['message'] ?? '').toString();
    final createdAt =
        (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.notifications_active_rounded, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(message),
              const SizedBox(height: 2),
              Text(
                DateFormat.yMMMd().add_jm().format(createdAt),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SupportRequestDialog extends StatefulWidget {
  const _SupportRequestDialog({
    required this.user,
    required this.firebase,
    required this.text,
  });

  final AppUser user;
  final FirebaseService firebase;
  final _UserText text;

  @override
  State<_SupportRequestDialog> createState() => _SupportRequestDialogState();
}

class _SupportRequestDialogState extends State<_SupportRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  final _contact = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _contact.text = widget.user.email;
  }

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    _contact.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.text.supportTitle),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _subject,
                decoration: InputDecoration(
                  labelText: widget.text.supportSubject,
                ),
                validator: _required,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _message,
                minLines: 4,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: widget.text.supportMessage,
                ),
                validator: _required,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _contact,
                decoration: InputDecoration(
                  labelText: widget.text.supportContact,
                ),
                validator: _required,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: Text(widget.text.close),
        ),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_rounded),
          label: Text(widget.text.send),
        ),
      ],
    );
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Required' : null;
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      await widget.firebase.createSupportRequest(
        user: widget.user,
        subject: _subject.text,
        message: _message.text,
        contact: _contact.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(widget.text.supportSent)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF5EEAD4)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F766E).withValues(alpha: .16),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _ProfilePassCard extends StatelessWidget {
  const _ProfilePassCard({required this.pass, this.user, this.firebase});
  final _AccessPass pass;
  final AppUser? user;
  final FirebaseService? firebase;

  @override
  Widget build(BuildContext context) {
    final profileUser = user;
    final profileFirebase = firebase;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ProfileAvatar(
                photoPath: pass.photoPath,
                action: profileUser == null || profileFirebase == null
                    ? null
                    : _ProfilePhotoRequestButton(
                        user: profileUser,
                        firebase: profileFirebase,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pass.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pass.category,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _PassLine(label: 'ID', value: pass.identity),
          const SizedBox(height: 8),
          _PassLine(label: 'Access Status', value: pass.accessStatus),
          const SizedBox(height: 8),
          _PassLine(label: 'Semester', value: pass.semester),
          const SizedBox(height: 8),
          _PassLine(label: 'Session', value: pass.session),
          const SizedBox(height: 8),
          _PassLine(label: pass.academicLabel, value: pass.programme),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.photoPath, this.action});
  final String? photoPath;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final provider = _photoProvider();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 38,
          backgroundColor: const Color(0xFFCCFBF1),
          backgroundImage: provider,
          child: provider == null
              ? const Icon(
                  Icons.face_retouching_natural_rounded,
                  color: Color(0xFF0F766E),
                  size: 34,
                )
              : null,
        ),
        if (action != null) Positioned(right: -6, bottom: -6, child: action!),
      ],
    );
  }

  ImageProvider<Object>? _photoProvider() {
    return _profilePhotoProvider(photoPath);
  }
}

class _ProfilePhotoRequestButton extends StatefulWidget {
  const _ProfilePhotoRequestButton({
    required this.user,
    required this.firebase,
  });

  final AppUser user;
  final FirebaseService firebase;

  @override
  State<_ProfilePhotoRequestButton> createState() =>
      _ProfilePhotoRequestButtonState();
}

class _ProfilePhotoRequestButtonState
    extends State<_ProfilePhotoRequestButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: 'Request profile picture change',
      constraints: const BoxConstraints.tightFor(width: 42, height: 42),
      onPressed: _busy ? null : _requestPhoto,
      icon: _busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.photo_camera_rounded, size: 20),
    );
  }

  Future<void> _requestPhoto() async {
    final messenger = ScaffoldMessenger.of(context);
    final blockReason = _profilePhotoBlockReason(widget.user);
    if (blockReason != null) {
      messenger.showSnackBar(SnackBar(content: Text(blockReason)));
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 86,
        maxWidth: 1200,
      );
      if (picked == null) return;
      final saved = await _persistProfileImage(picked);
      await widget.firebase.requestProfilePhotoUpdate(
        userId: widget.user.id,
        photoUrl: saved.path,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Profile picture sent for admin approval.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to update profile picture: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<File> _persistProfileImage(XFile picked) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'profile_pictures'));
    await dir.create(recursive: true);
    final extension = p.extension(picked.path).trim().isEmpty
        ? '.jpg'
        : p.extension(picked.path);
    final fileName =
        '${widget.user.id}-${DateTime.now().millisecondsSinceEpoch}$extension';
    return File(picked.path).copy(p.join(dir.path, fileName));
  }
}

ImageProvider<Object>? _profilePhotoProvider(String? photoPath) {
  final path = photoPath?.trim();
  if (path == null || path.isEmpty) return null;
  final file = File(path);
  return file.existsSync() ? FileImage(file) : null;
}

String? _profilePhotoBlockReason(AppUser user) {
  if (user.hasPendingPhotoApproval) {
    return 'Profile picture request is waiting for admin review.';
  }
  final now = DateTime.now();
  final lastChange = user.photoUpdatedAt ?? user.photoChangeRequestedAt;
  if (lastChange != null &&
      lastChange.year == now.year &&
      lastChange.month == now.month) {
    return 'Profile picture can be changed again next month.';
  }
  return null;
}

class _SmallProfileAvatar extends StatelessWidget {
  const _SmallProfileAvatar({required this.photoPath, required this.fallback});

  final String? photoPath;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final provider = _profilePhotoProvider(photoPath);
    return CircleAvatar(
      radius: 24,
      backgroundColor: const Color(0xFFCCFBF1),
      backgroundImage: provider,
      child: provider == null
          ? Text(
              fallback,
              style: const TextStyle(
                color: Color(0xFF0F766E),
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            )
          : null,
    );
  }
}

class _PassLine extends StatelessWidget {
  const _PassLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDFA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(
                '$label:',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            Expanded(
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomPermissionGrid extends StatelessWidget {
  const _RoomPermissionGrid({required this.rooms, this.areas = const []});
  final List<String> rooms;
  final List<Area> areas;

  @override
  Widget build(BuildContext context) {
    if (rooms.isEmpty) return const Text('No room access assigned.');
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 520 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rooms.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.35,
          ),
          itemBuilder: (context, index) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .88),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF5EEAD4)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.meeting_room_rounded,
                      color: Color(0xFF0F766E),
                    ),
                    const Spacer(),
                    Text(
                      rooms[index],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _capacityLabel(_matchingArea(rooms[index])),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Area? _matchingArea(String room) {
    final key = _accessKey(room);
    for (final area in areas) {
      if (_areaRoomKeys(area).contains(key)) {
        return area;
      }
    }
    return null;
  }
}

String _capacityLabel(Area? area) {
  if (area == null || area.capacity <= 0) return 'Capacity available';
  return '${area.currentOccupancy} / ${area.capacity} occupied';
}

class _UserBottomBar extends StatelessWidget {
  const _UserBottomBar({
    required this.selectedIndex,
    required this.onChanged,
    required this.text,
  });
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final _UserText text;

  static const _items = [
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.list_alt_rounded, label: 'History'),
    (icon: Icons.person_rounded, label: 'Profile'),
    (icon: Icons.settings_rounded, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 66,
        width: double.infinity,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFBAE6FD))),
          ),
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onChanged(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _items[i].icon,
                          color: selectedIndex == i
                              ? const Color(0xFF0D9488)
                              : const Color(0xFF64748B),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          text.navLabel(i),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selectedIndex == i
                                ? const Color(0xFF0D9488)
                                : const Color(0xFF64748B),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: selectedIndex == i
                                ? const Color(0xFF3B82F6)
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
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

class _AccessPass {
  const _AccessPass({
    required this.name,
    required this.category,
    required this.identity,
    required this.accessStatus,
    required this.semester,
    required this.session,
    required this.academicLabel,
    required this.programme,
    required this.rooms,
    this.photoPath,
  });

  final String name;
  final String category;
  final String identity;
  final String accessStatus;
  final String semester;
  final String session;
  final String academicLabel;
  final String programme;
  final List<String> rooms;
  final String? photoPath;

  factory _AccessPass.fromUser(AppUser? user) {
    final rooms = user?.assignedRooms
        .where((room) => room.trim().isNotEmpty)
        .toList();
    final position = user?.position.trim().toLowerCase();
    final isStaff = position == 'staff';
    return _AccessPass(
      name: user?.name.trim().isNotEmpty == true
          ? user!.name.trim()
          : 'Fazekey User',
      category: isStaff ? 'Staff' : 'Student',
      identity: user?.identityNumber.trim().isNotEmpty == true
          ? user!.identityNumber.trim()
          : 'Unavailable',
      accessStatus: user?.isApproved == false ? 'Setup Required' : 'Active',
      semester: user?.currentSemester.trim().isNotEmpty == true
          ? user!.currentSemester.trim()
          : 'Semester 1',
      session: _currentAcademicSession(),
      academicLabel: isStaff ? 'Department' : 'Programme',
      programme: isStaff
          ? (user?.department.trim().isNotEmpty == true
                ? user!.department.trim()
                : 'Department unavailable')
          : _programmeName(user),
      rooms: rooms == null || rooms.isEmpty ? const [] : rooms,
      photoPath: user?.photoUrl,
    );
  }
}

class _CampusNews {
  const _CampusNews({
    required this.title,
    required this.dateLabel,
    this.link = '',
    this.order = 0,
  });

  final String title;
  final String dateLabel;
  final String link;
  final int order;

  static _CampusNews fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final timestamp = data['date'] as Timestamp?;
    final dateLabel = (data['dateLabel'] ?? data['publishedAtLabel'])
        ?.toString()
        .trim();
    return _CampusNews(
      title: (data['title'] ?? 'Campus Update').toString(),
      dateLabel: dateLabel?.isNotEmpty == true
          ? dateLabel!
          : timestamp == null
          ? ''
          : DateFormat('MMM d, yyyy').format(timestamp.toDate()),
      link: (data['link'] ?? data['url'] ?? '').toString(),
      order: data['order'] is int ? data['order'] as int : 0,
    );
  }
}

const _campusNewsCount = 3;

const _defaultCampusNews = [
  _CampusNews(
    order: 1,
    title: 'Final exam desk numbers for Semester I 2025/2026 now available',
    dateLabel: '18 May 2026',
  ),
  _CampusNews(
    order: 2,
    title:
        'Update your phone number and personal email to receive important notices',
    dateLabel: '30 April 2026',
    link: 'http://itinfo.uthm.edu.my/phone-smap/',
  ),
  _CampusNews(
    order: 3,
    title:
        'Course withdrawal applications open for Bachelor\'s and Diploma students for Semester II 2025/2026',
    dateLabel: '10 May 2026',
  ),
];

int _sortNews(_CampusNews a, _CampusNews b) {
  if (a.order != b.order) return a.order.compareTo(b.order);
  return a.title.compareTo(b.title);
}

List<_CampusNews> _campusNewsWithDefaults(List<_CampusNews> realtimeNews) {
  final sorted = realtimeNews.where((item) => item.order > 0).toList()
    ..sort(_sortNews);
  return [
    for (final fallback in _defaultCampusNews)
      _matchingNews(sorted, fallback.order) ?? fallback,
  ].take(_campusNewsCount).toList(growable: false);
}

_CampusNews? _matchingNews(List<_CampusNews> news, int order) {
  for (final item in news) {
    if (item.order == order) return item;
  }
  return null;
}

String _areaDisplay(Area area) {
  final name = area.name.trim();
  final room = area.roomNumber.trim();
  if (name.isNotEmpty) return name;
  if (room.isNotEmpty) return 'Room $room';
  return area.id.trim().isEmpty ? 'Room Asset' : area.id.trim();
}

Set<String> _areaRoomKeys(Area area) {
  final floor = area.floor.trim();
  final roomNumber = area.roomNumber.trim();
  final location = area.location.trim();
  final floorRoom = floor.isNotEmpty && roomNumber.isNotEmpty
      ? '$floor - Room $roomNumber'
      : '';
  final locationFloorRoom = location.isNotEmpty && floorRoom.isNotEmpty
      ? '$location - $floorRoom'
      : '';
  return {
    area.id,
    area.name,
    area.roomNumber,
    if (floor.isNotEmpty && area.name.trim().isNotEmpty)
      '$floor - ${area.name}',
    if (location.isNotEmpty && area.name.trim().isNotEmpty)
      '$location - ${area.name}',
    if (location.isNotEmpty && floor.isNotEmpty && area.name.trim().isNotEmpty)
      '$location - $floor - ${area.name}',
    if (roomNumber.isNotEmpty) 'Room $roomNumber',
    floorRoom,
    locationFloorRoom,
    _areaDisplay(area),
  }.map(_accessKey).where((value) => value.isNotEmpty).toSet();
}

List<Area> _uniqueActiveAreas(List<Area> source) {
  final areas = <Area>[];
  final keys = <String>{};
  for (final area in source.where((area) => area.active)) {
    final key = area.id.trim().isNotEmpty
        ? area.id.trim()
        : _accessKey(_areaDisplay(area));
    if (key.isEmpty || !keys.add(key)) continue;
    areas.add(area);
  }
  areas.sort((a, b) => _areaDisplay(a).compareTo(_areaDisplay(b)));
  return areas;
}

String _validLanguage(String value) {
  return value == 'Malay' ? 'Malay' : 'English';
}

String _userDisplayId(AppUser user) {
  final identity = user.identityNumber.trim();
  if (identity.isNotEmpty) return identity;
  return user.id.length <= 8 ? user.id : user.id.substring(0, 8);
}

String _programmeName(AppUser? user) {
  final source = [
    user?.course,
    user?.department,
    user?.faculty,
  ].whereType<String>().join(' ').toLowerCase();
  if (source.contains('doctor of philosophy') || source.contains('phd')) {
    return 'Doctor of Philosophy (PhD) in Information Technology';
  }
  if (source.contains('master') && source.contains('software')) {
    return 'Master of Computer Science (Software Engineering)';
  }
  if (source.contains('master') && source.contains('information security')) {
    return 'Master of Computer Science (Information Security)';
  }
  if (source.contains('master')) {
    return 'Master of Information Technology';
  }
  if (source.contains('multimedia') || source.contains('bim')) {
    return 'Bachelor of Computer Science (Multimedia Computing) with Honours - BIM';
  }
  if (source.contains('software') || source.contains('bis')) {
    return 'Bachelor of Computer Science (Software Engineering) with Honours - BIS';
  }
  if (source.contains('web') || source.contains('biw')) {
    return 'Bachelor of Computer Science (Web Technology) with Honours - BIW';
  }
  if (source.contains('information technology') || source.contains('bit')) {
    return 'Bachelor of Information Technology with Honours - BIT';
  }
  return 'Bachelor of Computer Science (Information Security) with Honours - BIS';
}

String _currentAcademicSession() {
  final now = DateTime.now();
  final start = now.month >= 9 ? now.year : now.year - 1;
  return '$start/${start + 1}';
}

class _UserText {
  const _UserText(this.locale);

  final String locale;

  bool get _ms => locale == 'Malay';

  String get welcomeBack => _ms ? 'Selamat kembali' : 'Welcome back';
  String welcomeUser(String name) =>
      _ms ? 'Selamat datang, $name' : 'Welcome, $name';
  String get homeSubtitle => _ms ? 'Akses kampus aktif' : 'Campus access';
  String homeSubtitleFor(AppUser? user) {
    final role = user?.role.trim().toLowerCase() ?? '';
    if (role == 'admin') return _ms ? 'Akses admin' : 'Admin access';
    final id = user == null ? '' : _userDisplayId(user);
    if (id.isEmpty) return _ms ? 'ID tidak tersedia' : 'ID unavailable';
    return _ms ? 'ID: $id' : 'ID: $id';
  }

  String? homeAcademicTitleFor(AppUser? user) {
    final position = user?.position.trim().toLowerCase() ?? '';
    final role = user?.role.trim().toLowerCase() ?? '';
    if (role == 'admin' || position == 'staff' || role == 'staff') {
      return null;
    }
    final source = [
      user?.course,
      user?.department,
      user?.faculty,
    ].whereType<String>().join(' ').toLowerCase();
    if (source.contains('master') ||
        source.contains('phd') ||
        source.contains('doctor of philosophy')) {
      return _ms ? 'Pascasiswazah' : 'Postgraduate';
    }
    if (source.contains('bachelor') || source.contains('diploma')) {
      return _ms ? 'Prasiswazah' : 'Undergraduate';
    }
    return null;
  }

  String get realTime =>
      _ms ? 'Tarikh dan masa semasa' : 'Current date and time';
  String get currentRoom => _ms ? 'Bilik Semasa' : 'Current Room';
  String get noActiveRoom =>
      _ms ? 'Tiada akses bilik aktif' : 'No active room access';
  String get accessReady =>
      _ms ? 'Akses bilik sedia digunakan' : 'Room access ready';
  String get checkedIn => _ms ? 'Daftar masuk' : 'Checked in';
  String get validUntil =>
      _ms ? 'Akses fakulti sah sehingga' : 'Faculty access valid until';
  String get noExpiryAvailable =>
      _ms ? 'Tiada tempoh akses fakulti' : 'No faculty access expiry date';
  String get signOutRoom => _ms ? 'Daftar Keluar Bilik' : 'Sign Out of Room';
  String get signedOutRoom =>
      _ms ? 'Telah daftar keluar bilik.' : 'Signed out of room.';
  String get signOut => _ms ? 'Log Keluar' : 'Sign Out';
  String get exitRoom => _ms ? 'Keluar Bilik' : 'Exit Room';
  String get roomActionTitle =>
      _ms ? 'Pilih tindakan bilik' : 'Choose room action';
  String get exitRoomNote => _ms
      ? 'Tamatkan sesi bilik aktif dan log keluar daripada aplikasi.'
      : 'End the active room session and sign out of the app.';
  String get enterNewRoom => _ms ? 'Masuk Bilik Baharu' : 'Enter New Room';
  String get enterNewRoomNote => _ms
      ? 'Hantar permintaan bilik baharu untuk kelulusan admin.'
      : 'Send a new room request for admin approval.';
  String get roomRequestSent => _ms
      ? 'Permintaan bilik dihantar. Sila tunggu kelulusan admin.'
      : 'Room request sent. Please wait for admin approval.';
  String get noRoomsAvailable =>
      _ms ? 'Tiada bilik aktif tersedia.' : 'No active rooms available.';
  String get editProfile => _ms ? 'Edit Profil' : 'Edit Profile';
  String get editProfileNote => _ms
      ? 'Perubahan memerlukan kelulusan admin dan hanya boleh dibuat sekali sebulan.'
      : 'Changes require admin approval and are limited to once per month.';
  String get changePassword => forgotPassword;
  String get forgotPassword => _ms ? 'Lupa Kata Laluan' : 'Forgot Password';
  String get forgotPasswordNote => _ms
      ? 'Hantar pautan tetapan semula kata laluan ke emel anda.'
      : 'Send a password reset link to your email.';
  String get passwordEmailSent => _ms
      ? 'Berjaya. Emel tetapan semula kata laluan telah disediakan.'
      : 'Success. Password reset email prepared.';
  String get checkEmail =>
      _ms ? 'Sila semak emel anda.' : 'Please check your email.';
  String get actionFailed =>
      _ms ? 'Tindakan gagal.' : 'Unable to complete action.';
  String get helpSupport => _ms ? 'Bantuan & Sokongan' : 'Help & Support';
  String get helpSupportNote => _ms
      ? 'Hantar isu kepada admin untuk tindakan lanjut.'
      : 'Send an issue to admin for follow-up.';
  String get supportTitle => _ms ? 'Minta Bantuan' : 'Request Support';
  String get supportSubject => _ms ? 'Subjek' : 'Subject';
  String get supportMessage => _ms ? 'Mesej' : 'Message';
  String get supportContact => _ms ? 'Telefon / emel' : 'Phone or email';
  String get supportSent => _ms
      ? 'Berjaya. Permintaan sokongan dihantar.'
      : 'Success. Support request sent.';
  String get send => _ms ? 'Hantar' : 'Send';
  String get close => _ms ? 'Tutup' : 'Close';
  String get nightMode => _ms ? 'Mod Malam' : 'Night Mode';
  String get language => _ms ? 'Bahasa' : 'Language';

  String navLabel(int index) {
    final english = ['Home', 'History', 'Profile', 'Settings'];
    final malay = ['Utama', 'Sejarah', 'Profil', 'Tetapan'];
    final source = _ms ? malay : english;
    return source[index.clamp(0, source.length - 1)];
  }
}
