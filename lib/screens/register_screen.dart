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
  int _level = 1;
  String? _department;
  String? _area;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AreaProvider>().listen();
    });
  }

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
    final areaOptions = _restrictedAreasForLevel(areas, _level);
    final selectedArea = _selectedOption(areaOptions, _area);
    _syncSelection(department: selectedDepartment, area: selectedArea);
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
                      const SizedBox(height: 16),
                      _TextSelector<int>(
                        label: 'Level',
                        value: _level,
                        options: const [1, 2, 3],
                        textFor: (level) => 'Level $level',
                        onChanged: (level) => setState(() {
                          _level = level;
                          _department = _firstDepartmentForLevel(areas, level);
                          _area = _firstRestrictedAreaForLevel(areas, level);
                        }),
                      ),
                      const SizedBox(height: 16),
                      if (selectedArea == null)
                        Text(
                          'No restricted areas configured for Level $_level.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        )
                      else
                        DropdownButtonFormField<String>(
                          key: ValueKey('register-area-$_level-$selectedArea'),
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
                          onChanged: (area) => setState(() => _area = area),
                        ),
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
                          if (selectedArea == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Add a restricted area for Level $_level before registering this account.',
                                ),
                              ),
                            );
                            return;
                          }
                          final ok = await context
                              .read<AuthProvider>()
                              .register(
                                name: _name.text,
                                email: _email.text,
                                password: _password.text,
                                department: selectedDepartment ?? '',
                                phone: _phone.text,
                                room: selectedArea,
                                identityNumber: _identityNumber.text,
                              );
                          if (ok && context.mounted) {
                            Navigator.pushReplacementNamed(
                              context,
                              FaceRegistrationScreen.route,
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
