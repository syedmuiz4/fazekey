import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/area.dart';
import '../providers/area_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/primary_button.dart';
import 'face_registration_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  static const route = '/register';

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _identityNumber = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  String _role = 'User';
  String _position = 'Student';
  int _level = 1;
  String? _department;

  @override
  void dispose() {
    _name.dispose();
    _identityNumber.dispose();
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final areas = context.watch<AreaProvider>().areas;
    final departmentOptions = _departmentsForLevel(areas, _level);
    final selectedDepartment = _selectedOption(departmentOptions, _department);
    final adminRoleSelected = _role.trim().toLowerCase() == 'admin';
    _syncSelection(department: selectedDepartment);
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Register'),
          backgroundColor: Colors.transparent,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              GlassCard(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'Name'),
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
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                        ),
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          'register-department-$_level-$selectedDepartment',
                        ),
                        initialValue: selectedDepartment,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Department',
                        ),
                        validator: _required,
                        items: departmentOptions
                            .map(
                              (department) => DropdownMenuItem(
                                value: department,
                                child: Text(
                                  department,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _department = value),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Phone'),
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
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
                          if (value != null) {
                            setState(() {
                              _role = value;
                              if (_role.trim().toLowerCase() == 'admin') {
                                _level = 3;
                                _position = 'Admin';
                              } else {
                                _level = 1;
                                _position = _position == 'Admin'
                                    ? 'Student'
                                    : _position;
                              }
                            });
                          }
                        },
                      ),
                      if (!adminRoleSelected) ...[
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: _position == 'Admin'
                              ? 'Student'
                              : _position,
                          decoration: const InputDecoration(
                            labelText: 'Position',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'Student',
                              child: Text('Student'),
                            ),
                            DropdownMenuItem(
                              value: 'Staff',
                              child: Text('Staff'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _position = value);
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        _TextSelector<int>(
                          label: 'Access Level',
                          value: _level,
                          options: const [1, 2, 3],
                          textFor: (level) => 'Level $level',
                          onChanged: (level) => setState(() {
                            _level = level;
                            _department = _firstDepartmentForLevel(
                              areas,
                              level,
                            );
                            _level = level;
                          }),
                        ),
                      ],
                      if (auth.error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          auth.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      PrimaryButton(
                        label: 'Create Account',
                        loading: auth.loading,
                        onPressed: () async {
                          if (!_form.currentState!.validate()) return;
                          final ok = await context
                              .read<AuthProvider>()
                              .register(
                                name: _name.text,
                                email: _email.text,
                                password: _password.text,
                                department: selectedDepartment ?? '',
                                phone: _phone.text,
                                room: '',
                                rooms: const [],
                                role: _role,
                                accessLevel: adminRoleSelected ? 3 : _level,
                                identityNumber: _identityNumber.text,
                                position: adminRoleSelected
                                    ? 'Admin'
                                    : _position,
                              );
                          if (ok && context.mounted) {
                            Navigator.of(context).pushNamedAndRemoveUntil(
                              FaceRegistrationScreen.route,
                              (_) => false,
                            );
                          }
                        },
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

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  List<String> _departmentsForLevel(List<Area> areas, int level) {
    final floor = 'Level $level';
    final departments =
        areas
            .where(
              (area) =>
                  area.active &&
                  area.floor.trim().toLowerCase() == floor.toLowerCase(),
            )
            .expand((area) => area.allowedDepartments)
            .map((department) => department.trim())
            .where((department) => department.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return departments.isEmpty ? _fallbackDepartments : departments;
  }

  String? _firstDepartmentForLevel(List<Area> areas, int level) {
    final options = _departmentsForLevel(areas, level);
    return options.isEmpty ? null : options.first;
  }

  String? _selectedOption(List<String> options, String? selected) {
    if (options.isEmpty) return null;
    return selected != null && options.contains(selected)
        ? selected
        : options.first;
  }

  void _syncSelection({required String? department}) {
    if (_department == department) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _department == department) return;
      setState(() => _department = department);
    });
  }

  static const _fallbackDepartments = [
    'Software Engineering',
    'Information Security',
    'Multimedia',
  ];
}

class _TextSelector<T> extends StatelessWidget {
  const _TextSelector({
    required this.label,
    required this.value,
    required this.options,
    required this.textFor,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> options;
  final String Function(T value) textFor;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              ChoiceChip(
                label: Text(textFor(option)),
                selected: option == value,
                selectedColor: colors.primary.withValues(alpha: .24),
                onSelected: (_) => onChanged(option),
              ),
          ],
        ),
      ],
    );
  }
}
