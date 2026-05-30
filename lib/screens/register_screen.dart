import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../constants/command_center_options.dart';
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
  final _customDepartment = TextEditingController();
  String _role = 'User';
  String _position = 'Student';
  int _level = 1;
  String _department = commandCenterDepartments.first;

  @override
  void dispose() {
    _name.dispose();
    _identityNumber.dispose();
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _customDepartment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    const departmentOptions = commandCenterDepartments;
    final selectedDepartment = _selectedDepartment;
    final adminRoleSelected = _role.trim().toLowerCase() == 'admin';
    return AppBackground(
      child: Scaffold(
        backgroundColor: AppBackground.slateGray,
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
                          'register-department-$_level-$_department',
                        ),
                        initialValue: _department,
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
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _department = value);
                          }
                        },
                      ),
                      if (_department == 'Other...') ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _customDepartment,
                          decoration: const InputDecoration(
                            labelText: 'Custom Department',
                          ),
                          validator: _required,
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
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
                            _department = commandCenterDepartments.first;
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
                                department: selectedDepartment,
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

  String get _selectedDepartment {
    if (_department == 'Other...') return _customDepartment.text.trim();
    return _department;
  }
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
