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
  final _form = GlobalKey<FormState>();
  final fields = List.generate(6, (_) => TextEditingController());

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    const labels = ['Name', 'Email', 'Password', 'Department', 'Phone', 'Room'];
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
                    children: [
                      for (var i = 0; i < labels.length; i++) ...[
                        TextFormField(
                          controller: fields[i],
                          obscureText: labels[i] == 'Password',
                          decoration: InputDecoration(labelText: labels[i]),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (auth.error != null) Text(auth.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 8),
                      PrimaryButton(
                        label: 'Create Account',
                        loading: auth.loading,
                        icon: Icons.person_add_alt_1_rounded,
                        onPressed: () async {
                          if (!_form.currentState!.validate()) return;
                          final ok = await context.read<AuthProvider>().register(
                                name: fields[0].text,
                                email: fields[1].text,
                                password: fields[2].text,
                                department: fields[3].text,
                                phone: fields[4].text,
                                room: fields[5].text,
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
}
