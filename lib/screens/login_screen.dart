import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../widgets/app_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/primary_button.dart';
import 'face_login_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  static const route = '/login';

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Security Portal',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in to manage secure campus access.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 28),
              Center(
                child: Image.asset(
                  'assets/images/logo2.png',
                  width: 132,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
              const SizedBox(height: 18),
              GlassCard(
                child: Form(
                  key: _form,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _email,
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: _required,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _password,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                        ),
                        validator: _required,
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
                        label: 'Login',
                        loading: auth.loading,
                        onPressed: () async {
                          if (!_form.currentState!.validate()) return;
                          final ok = await context.read<AuthProvider>().login(
                            _email.text,
                            _password.text,
                          );
                          if (ok && context.mounted) {
                            Navigator.of(context).pushNamedAndRemoveUntil(
                              '/admin_dashboard',
                              (_) => false,
                            );
                          }
                        },
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(
                          context,
                        ).pushNamed(FaceLoginScreen.route),
                        child: const Text('Login with Face'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () =>
                    Navigator.pushNamed(context, RegisterScreen.route),
                child: const Text('Create administrator account'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;
}
