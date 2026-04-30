import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
  String _area = 'Server Room';

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
                      DropdownButtonFormField<String>(
                        initialValue: _department,
                        decoration: const InputDecoration(labelText: 'Department'),
                        items: _departments.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => _department = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone'), validator: _required),
                      const SizedBox(height: 16),
                      _TextSelector<int>(
                        label: 'Level',
                        value: _level,
                        options: const [1, 2, 3],
                        textFor: (level) => 'Level $level',
                        onChanged: (level) => setState(() => _level = level),
                      ),
                      const SizedBox(height: 16),
                      _TextSelector<String>(
                        label: 'Restricted Area',
                        value: _area,
                        options: const ['Server Room'],
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
                        icon: Icons.person_add_alt_1_rounded,
                        onPressed: () async {
                          if (!_form.currentState!.validate()) return;
                          final ok = await context.read<AuthProvider>().register(
                                name: _name.text,
                                email: _email.text,
                                password: _password.text,
                                department: _department,
                                phone: _phone.text,
                                room: 'Level $_level - $_area',
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
