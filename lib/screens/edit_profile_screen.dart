import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';
import '../widgets/app_background.dart';
import '../widgets/glass_card.dart';
import 'face_registration_screen.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  static const route = '/edit-profile';

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final FirebaseService _firebase;
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _matricNo = TextEditingController();
  final _course = TextEditingController();
  final _faculty = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _homeAddress = TextEditingController();
  final _emergencyContact = TextEditingController();
  String? _loadedProfileKey;
  AppUser? _initialProfile;
  AppUser? _currentProfile;
  String? _photoPath;
  bool _loadingInitialProfile = true;
  bool _updatingProfile = false;
  bool _pickingPhoto = false;
  String? _profileError;

  @override
  void initState() {
    super.initState();
    _firebase = context.read<FirebaseService>();
    _loadInitialProfile();
  }

  @override
  void dispose() {
    _name.dispose();
    _matricNo.dispose();
    _course.dispose();
    _faculty.dispose();
    _email.dispose();
    _phone.dispose();
    _homeAddress.dispose();
    _emergencyContact.dispose();
    super.dispose();
  }

  Future<void> _loadInitialProfile() async {
    try {
      final activeProfile = context.read<AuthProvider>().user;
      if (activeProfile != null) {
        _loadUser(activeProfile);
        if (!mounted) return;
        setState(() {
          _initialProfile = activeProfile;
          _loadingInitialProfile = false;
        });
        return;
      }
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

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Edit Profile'),
          backgroundColor: Colors.transparent,
        ),
        body: StreamBuilder<AppUser?>(
          stream: auth.watchActiveUserProfile(),
          initialData: auth.user ?? _initialProfile,
          builder: (context, snapshot) {
            final user =
                snapshot.data ??
                auth.user ??
                _currentProfile ??
                _initialProfile;
            if (snapshot.connectionState == ConnectionState.waiting &&
                user == null &&
                _loadingInitialProfile) {
              return const Center(child: CircularProgressIndicator());
            }
            if (user == null) {
              return const Center(child: Text('Sign in to edit your profile.'));
            }
            _loadUser(user);
            final photoBlockReason = _profilePhotoBlockReason(user);
            return _ProfileForm(
              form: _form,
              user: user,
              name: _name,
              matricNo: _matricNo,
              course: _course,
              faculty: _faculty,
              email: _email,
              phone: _phone,
              homeAddress: _homeAddress,
              emergencyContact: _emergencyContact,
              photoPath: _photoPath,
              onPickPhoto: photoBlockReason == null
                  ? _showImageSourceSheet
                  : null,
              onUpdateProfile: _updateProfile,
              updatingProfile: _updatingProfile,
              pickingPhoto: _pickingPhoto,
              profileError: _profileError,
              photoApprovalNote: photoBlockReason,
            );
          },
        ),
      ),
    );
  }

  void _loadUser(AppUser user) {
    final profileKey =
        '${user.id}|${user.name}|${user.email}|${user.identityNumber}|'
        '${user.course}|${user.faculty}|${user.phone}|${user.homeAddress}|'
        '${user.emergencyContact}|${user.photoUrl}|${user.pendingPhotoUrl}|'
        '${user.photoChangeRequestedAt}|${user.photoUpdatedAt}';
    if (_loadedProfileKey == profileKey) return;
    _loadedProfileKey = profileKey;
    _currentProfile = user;
    _name.text = user.name;
    _matricNo.text = user.identityNumber.trim().isEmpty
        ? user.id
        : user.identityNumber.trim();
    _course.text = user.course.trim().isEmpty ? user.department : user.course;
    _faculty.text = user.faculty.trim().isEmpty ? 'FSKTM' : user.faculty;
    final accountEmail = _firebase.currentUserEmail;
    _email.text = accountEmail?.trim().isNotEmpty == true
        ? accountEmail!.trim()
        : user.email;
    _phone.text = user.phone;
    _homeAddress.text = user.homeAddress;
    _emergencyContact.text = user.emergencyContact;
    _photoPath = user.photoUrl;
  }

  Future<void> _showImageSourceSheet() async {
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
    if (source == null) return;
    await _pickProfileImage(source);
  }

  Future<void> _pickProfileImage(ImageSource source) async {
    final current = _currentProfile;
    if (current == null) return;
    setState(() {
      _pickingPhoto = true;
      _profileError = null;
    });
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 86,
        maxWidth: 1200,
      );
      if (picked == null) return;
      final saved = await _persistProfileImage(picked, current);
      await _firebase.requestProfilePhotoUpdate(
        userId: current.id,
        photoUrl: saved.path,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile picture sent for admin approval.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _profileError = 'Unable to update profile picture: $e');
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  Future<File> _persistProfileImage(XFile picked, AppUser user) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'profile_pictures'));
    await dir.create(recursive: true);
    final extension = p.extension(picked.path).trim().isEmpty
        ? '.jpg'
        : p.extension(picked.path);
    final fileName =
        '${user.id}-${DateTime.now().millisecondsSinceEpoch}$extension';
    return File(picked.path).copy(p.join(dir.path, fileName));
  }

  Future<void> _updateProfile() async {
    if (!_form.currentState!.validate()) return;
    final current = _currentProfile;
    if (current == null || _name.text.trim().isEmpty) {
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
          phone: _phone.text,
          homeAddress: _homeAddress.text,
          emergencyContact: _emergencyContact.text,
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
      SnackBar(content: Text(ok ? 'Profile updated.' : _profileError!)),
    );
  }

  String? _profilePhotoBlockReason(AppUser user) {
    if (user.hasPendingPhotoApproval) {
      return 'Profile picture request is pending admin approval.';
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
}

class _ProfileForm extends StatelessWidget {
  const _ProfileForm({
    required this.form,
    required this.user,
    required this.name,
    required this.matricNo,
    required this.course,
    required this.faculty,
    required this.email,
    required this.phone,
    required this.homeAddress,
    required this.emergencyContact,
    required this.photoPath,
    required this.onPickPhoto,
    required this.onUpdateProfile,
    required this.updatingProfile,
    required this.pickingPhoto,
    required this.profileError,
    required this.photoApprovalNote,
  });

  final GlobalKey<FormState> form;
  final AppUser user;
  final TextEditingController name;
  final TextEditingController matricNo;
  final TextEditingController course;
  final TextEditingController faculty;
  final TextEditingController email;
  final TextEditingController phone;
  final TextEditingController homeAddress;
  final TextEditingController emergencyContact;
  final String? photoPath;
  final VoidCallback? onPickPhoto;
  final VoidCallback? onUpdateProfile;
  final bool updatingProfile;
  final bool pickingPhoto;
  final String? profileError;
  final String? photoApprovalNote;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          GlassCard(
            child: Row(
              children: [
                _EditableFaceAvatar(
                  photoPath: photoPath,
                  pickingPhoto: pickingPhoto,
                  onPickPhoto: onPickPhoto,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.email.isEmpty
                            ? 'Official email pending'
                            : user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (photoApprovalNote != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          photoApprovalNote!,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
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
                  TextFormField(
                    controller: matricNo,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Matric No.',
                      prefixIcon: Icon(Icons.badge_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: email,
                    readOnly: true,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Official Email',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: course,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Course',
                      prefixIcon: Icon(Icons.school_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: faculty,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Faculty',
                      prefixIcon: Icon(Icons.account_balance_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      prefixIcon: Icon(Icons.phone_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: homeAddress,
                    minLines: 2,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      labelText: 'Home Address',
                      prefixIcon: Icon(Icons.home_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: emergencyContact,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Emergency Contact',
                      prefixIcon: Icon(Icons.contact_emergency_rounded),
                    ),
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
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
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
                      user.hasFace
                          ? 'Re-enroll Face Identity'
                          : 'Register Face Identity',
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

class _EditableFaceAvatar extends StatelessWidget {
  const _EditableFaceAvatar({
    required this.photoPath,
    required this.pickingPhoto,
    required this.onPickPhoto,
  });

  final String? photoPath;
  final bool pickingPhoto;
  final VoidCallback? onPickPhoto;

  @override
  Widget build(BuildContext context) {
    final file = photoPath == null ? null : File(photoPath!);
    final image = file != null && file.existsSync() ? FileImage(file) : null;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 38,
          backgroundImage: image,
          child: image == null
              ? const Icon(Icons.person_rounded, size: 36)
              : null,
        ),
        Positioned(
          right: -4,
          bottom: -4,
          child: IconButton.filledTonal(
            tooltip: 'Update profile picture',
            onPressed: pickingPhoto ? null : onPickPhoto,
            icon: pickingPhoto
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_camera_rounded),
          ),
        ),
      ],
    );
  }
}
