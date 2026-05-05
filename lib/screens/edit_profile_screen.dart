import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/area.dart';
import '../models/app_user.dart';
import '../providers/area_provider.dart';
import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';
import '../widgets/app_background.dart';
import '../widgets/glass_card.dart';
import 'face_registration_screen.dart';

const _levels = [1, 2, 3];

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  static const route = '/edit-profile';

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _firebase = FirebaseService();
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _department = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  int _level = 1;
  String? _area;
  String? _loadedProfileKey;
  Stream<AppUser?>? _profileStream;
  AppUser? _initialProfile;
  AppUser? _currentProfile;
  bool _loadingInitialProfile = true;
  bool _updatingProfile = false;
  String? _profileError;

  @override
  void initState() {
    super.initState();
    _loadInitialProfile();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AreaProvider>().listen();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _department.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _loadInitialProfile() async {
    try {
      final profile = await _firebase.currentUserProfile();
      if (!mounted) return;
      if (profile != null) {
        _loadUser(profile);
      } else {
        _email.text = _firebase.currentUserEmail ?? '';
      }
      setState(() {
        _initialProfile = profile;
        _loadingInitialProfile = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _profileError = e.toString();
        _loadingInitialProfile = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final areas = context.watch<AreaProvider>().areas;
    final profileStream =
        _profileStream ??= _firebase.watchCurrentUserProfile();

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Edit Profile'),
          backgroundColor: Colors.transparent,
        ),
        body: StreamBuilder<AppUser?>(
          stream: profileStream,
          initialData: auth.user ?? _initialProfile,
          builder: (context, snapshot) {
            final user = snapshot.data;
            if (snapshot.connectionState == ConnectionState.waiting &&
                user == null &&
                _loadingInitialProfile) {
              return const Center(child: CircularProgressIndicator());
            }
            if (user == null) {
              return const Center(child: Text('Sign in to edit your profile.'));
            }
            _loadUser(user);
            final areaOptions = _restrictedAreasForLevel(areas, _level);
            final selectedArea = _selectedOption(areaOptions, _area);
            _syncAreaSelection(selectedArea);
            return _ProfileForm(
              form: _form,
              user: user,
              name: _name,
              department: _department,
              email: _email,
              phone: _phone,
              level: _level,
              areaOptions: areaOptions,
              selectedArea: selectedArea,
              onLevelChanged: (level) => setState(() {
                _level = level;
                _area = _firstRestrictedAreaForLevel(areas, level);
              }),
              onAreaChanged: (value) => setState(() {
                _area = value;
              }),
              onUpdateProfile: _updateProfile,
              updatingProfile: _updatingProfile,
              profileError: _profileError,
            );
          },
        ),
      ),
    );
  }

  void _loadUser(AppUser user) {
    final profileKey =
        '${user.id}|${user.name}|${user.phone}|${user.department}|${user.room}';
    if (_loadedProfileKey == profileKey) return;
    _loadedProfileKey = profileKey;
    _currentProfile = user;
    _name.text = user.name;
    _department.text = user.department;
    _email.text = _firebase.currentUserEmail ?? user.email;
    _phone.text = user.phone;
    _area = user.room;
    _level = _levelFromRoom(user.room) ?? 1;
  }

  int? _levelFromRoom(String room) {
    final match = RegExp(
      r'Level\s+(\d+)',
      caseSensitive: false,
    ).firstMatch(room);
    return int.tryParse(match?.group(1) ?? '');
  }

  void _syncAreaSelection(String? area) {
    if (_area == area) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _area == area) return;
      setState(() => _area = area);
    });
  }

  Future<void> _updateProfile() async {
    if (!_form.currentState!.validate()) return;
    final current = _currentProfile;
    final selectedDepartment = _department.text.trim();
    final selectedArea = _area?.trim().isNotEmpty == true
        ? _area!.trim()
        : current?.room.trim() ?? '';
    if (current == null ||
        _name.text.trim().isEmpty ||
        selectedDepartment.isEmpty) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _updatingProfile = true;
      _profileError = null;
    });
    var ok = false;
    Object? failure;
    try {
      await _firebase.updateUserProfile(
        current.copyWith(
          name: _name.text,
          department: selectedDepartment,
          phone: _phone.text,
          room: selectedArea,
        ),
      );
      ok = true;
    } catch (e) {
      failure = e;
    }
    if (!mounted) return;
    setState(() {
      _updatingProfile = false;
      _profileError = ok
          ? null
          : failure?.toString() ?? 'Unable to update profile.';
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? 'Profile updated.' : _profileError!),
      ),
    );
  }
}

class _ProfileForm extends StatelessWidget {
  const _ProfileForm({
    required this.form,
    required this.user,
    required this.name,
    required this.department,
    required this.email,
    required this.phone,
    required this.level,
    required this.areaOptions,
    required this.selectedArea,
    required this.onLevelChanged,
    required this.onAreaChanged,
    required this.onUpdateProfile,
    required this.updatingProfile,
    required this.profileError,
  });

  final GlobalKey<FormState> form;
  final AppUser user;
  final TextEditingController name;
  final TextEditingController department;
  final TextEditingController email;
  final TextEditingController phone;
  final int level;
  final List<String> areaOptions;
  final String? selectedArea;
  final ValueChanged<int> onLevelChanged;
  final ValueChanged<String?> onAreaChanged;
  final VoidCallback? onUpdateProfile;
  final bool updatingProfile;
  final String? profileError;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
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
                        user.name,
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.email,
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
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  _LevelDropdown(value: level, onChanged: onLevelChanged),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: department,
                    decoration: const InputDecoration(labelText: 'Department'),
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: email,
                    readOnly: true,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Account Email'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                  const SizedBox(height: 12),
                  if (selectedArea == null)
                    Text(
                      'Area assignment unavailable.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      key: ValueKey('edit-area-$level-$selectedArea'),
                      initialValue: selectedArea,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Restricted Area',
                      ),
                      validator: _required,
                      items: areaOptions
                          .map(
                            (area) => DropdownMenuItem(
                              value: area,
                              child: Text(
                                area,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: onAreaChanged,
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: updatingProfile ? null : onUpdateProfile,
                    child: Text(
                      updatingProfile ? 'Updating Profile' : 'Update Profile',
                    ),
                  ),
                  if (profileError != null) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        profileError!,
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.pushNamed(
                      context,
                      FaceRegistrationScreen.route,
                    ),
                    child: Text(
                      user.hasFace ? 'Re-enroll Face Data' : 'Register Face Data',
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Change Password'),
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final auth = context.read<AuthProvider>();
                      final resetEmail =
                          auth.passwordResetEmail ?? email.text.trim();
                      final ok = await auth.sendPasswordReset();
                      if (!context.mounted) return;
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'Password reset email sent to $resetEmail.'
                                : auth.error ??
                                      'Unable to send password reset email.',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;
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
      items: _levels
          .map(
            (level) =>
                DropdownMenuItem(value: level, child: Text('Level $level')),
          )
          .toList(),
      onChanged: (level) {
        if (level != null) onChanged(level);
      },
    );
  }
}

class _FaceAvatar extends StatelessWidget {
  const _FaceAvatar({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final photo = user.photoUrl;
    final file = photo == null ? null : File(photo);
    final image = file != null && file.existsSync() ? FileImage(file) : null;
    return CircleAvatar(
      radius: 34,
      backgroundImage: image,
      child: image == null ? const Icon(Icons.person_rounded, size: 34) : null,
    );
  }
}

List<String> _restrictedAreasForLevel(List<Area> areas, int level) {
  final floor = 'Level $level';
  final names =
      areas
          .where(
            (area) =>
                area.active &&
                area.floor.trim().toLowerCase() == floor.toLowerCase(),
          )
          .map(
            (area) => area.name.trim().isEmpty
                ? '$floor - Room ${area.roomNumber}'
                : area.name.trim(),
          )
          .toSet()
          .toList()
        ..sort();
  return names;
}

String? _firstRestrictedAreaForLevel(List<Area> areas, int level) {
  final options = _restrictedAreasForLevel(areas, level);
  return options.isEmpty ? null : options.first;
}

String? _selectedOption(List<String> options, String? selected) {
  if (options.isEmpty) return null;
  return selected != null && options.contains(selected)
      ? selected
      : options.first;
}
