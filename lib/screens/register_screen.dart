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
  static const _departments = [
    'Software Engineering',
    'Information Security and Web Technology',
    'Multimedia',
  ];

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  String _department = _departments.first;
  int _level = 1;
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
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final areas = context.watch<AreaProvider>().areas;
    final areaOptions = _restrictedAreasForLevel(areas, _level);
    final selectedArea = _selectedArea(areaOptions);
    _syncSelectedArea(selectedArea);
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Register'), backgroundColor: Colors.transparent),
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
                      TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Name'), validator: _required),
                      const SizedBox(height: 12),
                      TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email'), validator: _required),
                      const SizedBox(height: 12),
                      TextFormField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Password'), validator: _required),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _department,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Department'),
                              selectedItemBuilder: (context) => _departments
                                  .map(
                                    (d) => Text(
                                      d,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )
                                  .toList(),
                              items: _departments
                                  .map(
                                    (d) => DropdownMenuItem(
                                      value: d,
                                      child: Text(
                                        d,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) setState(() => _department = value);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone'), validator: _required),
                      const SizedBox(height: 16),
                      _TextSelector<int>(
                        label: 'Level',
                        value: _level,
                        options: const [1, 2, 3],
                        textFor: (level) => 'Level $level',
                        onChanged: (level) => setState(() {
                          _level = level;
                          _area = _firstRestrictedAreaForLevel(areas, level);
                        }),
                      ),
                      const SizedBox(height: 16),
                      if (selectedArea == null)
                        Text(
                          'No restricted areas configured for Level $_level.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        )
                      else
                        _TextSelector<String>(
                          label: 'Restricted Area',
                          value: selectedArea,
                          options: areaOptions,
                          textFor: (area) => area,
                          onChanged: (area) => setState(() => _area = area),
                        ),
                      if (auth.error != null) ...[
                        const SizedBox(height: 12),
                        Text(auth.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ],
                      const SizedBox(height: 20),
                      PrimaryButton(
                        label: 'Create Account',
                        loading: auth.loading,
                        onPressed: () async {
                          if (!_form.currentState!.validate()) return;
                          if (selectedArea == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Add a restricted area for Level $_level before registering this account.')),
                            );
                            return;
                          }
                          final ok = await context.read<AuthProvider>().register(
                                name: _name.text,
                                email: _email.text,
                                password: _password.text,
                                department: _department,
                                phone: _phone.text,
                                room: selectedArea,
                              );
                          if (ok && context.mounted) Navigator.pushReplacementNamed(context, FaceRegistrationScreen.route);
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

  String? _required(String? value) => value == null || value.trim().isEmpty ? 'Required' : null;

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

  String? _firstRestrictedAreaForLevel(List<Area> areas, int level) {
    final options = _restrictedAreasForLevel(areas, level);
    return options.isEmpty ? null : options.first;
  }

  String? _selectedArea(List<String> options) {
    if (options.isEmpty) return null;
    return _area != null && options.contains(_area) ? _area : options.first;
  }

  void _syncSelectedArea(String? selectedArea) {
    if (_area == selectedArea) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _area != selectedArea) setState(() => _area = selectedArea);
    });
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
