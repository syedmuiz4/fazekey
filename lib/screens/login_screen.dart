import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../widgets/app_background.dart';
import '../widgets/corporate_chrome.dart';
import '../widgets/glass_card.dart';
import '../widgets/primary_button.dart';
import 'dashboard_screen.dart';
import 'face_login_screen.dart';
import 'register_screen.dart';
import 'user_dashboard_screen.dart';

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
  bool _showPasswordLogin = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final logoHeight = (MediaQuery.sizeOf(context).height * .30)
        .clamp(220.0, 320.0)
        .toDouble();
    return AppBackground(
      child: Scaffold(
        backgroundColor: AppBackground.slateGray,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: Column(
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'FAZEKEY',
                    style:
                        GoogleFonts.orbitron(
                          fontSize: 120,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -5,
                          height: .85,
                        ).copyWith(
                          color: const Color(0xFF00E5FF),
                          shadows: [
                            Shadow(
                              color: const Color(
                                0xFF00E5FF,
                              ).withValues(alpha: .72),
                              blurRadius: 25,
                            ),
                          ],
                        ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Hero(
                              tag: 'facekey-logo',
                              child: Image.asset(
                                'assets/images/logo3_.png',
                                height: logoHeight,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                            const SizedBox(height: 28),
                            Text(
                              'System Authentication',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 34),
                            SizedBox(
                              height: 56,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: CorporateColors.teal,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                ),
                                onPressed: () => Navigator.of(
                                  context,
                                ).pushNamed(FaceLoginScreen.route),
                                child: const Text(
                                  'Login with Face',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Divider(
                              color: Theme.of(
                                context,
                              ).dividerColor.withValues(alpha: .55),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: TextButton(
                                    onPressed: () => setState(
                                      () => _showPasswordLogin =
                                          !_showPasswordLogin,
                                    ),
                                    child: Text(
                                      _showPasswordLogin
                                          ? 'Hide email login'
                                          : 'Login with password',
                                    ),
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Text('|'),
                                ),
                                Flexible(
                                  child: TextButton(
                                    onPressed: () => Navigator.pushNamed(
                                      context,
                                      RegisterScreen.route,
                                    ),
                                    child: const Text('Register Admin'),
                                  ),
                                ),
                              ],
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: _showPasswordLogin
                                  ? Padding(
                                      key: const ValueKey('password-login'),
                                      padding: const EdgeInsets.only(top: 8),
                                      child: GlassCard(
                                        child: Form(
                                          key: _form,
                                          child: Column(
                                            children: [
                                              TextFormField(
                                                controller: _email,
                                                decoration:
                                                    const InputDecoration(
                                                      labelText: 'Email',
                                                    ),
                                                validator: _required,
                                              ),
                                              const SizedBox(height: 14),
                                              TextFormField(
                                                controller: _password,
                                                obscureText: true,
                                                decoration:
                                                    const InputDecoration(
                                                      labelText: 'Password',
                                                    ),
                                                validator: _required,
                                              ),
                                              if (auth.error != null) ...[
                                                const SizedBox(height: 12),
                                                Text(
                                                  auth.error!,
                                                  style: TextStyle(
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.error,
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(height: 20),
                                              PrimaryButton(
                                                label: 'Login',
                                                loading: auth.loading,
                                                onPressed: () async {
                                                  if (!_form.currentState!
                                                      .validate()) {
                                                    return;
                                                  }
                                                  final authProvider = context
                                                      .read<AuthProvider>();
                                                  final ok = await authProvider
                                                      .login(
                                                        _email.text,
                                                        _password.text,
                                                      );
                                                  if (ok && context.mounted) {
                                                    final route =
                                                        authProvider.isAdmin
                                                        ? DashboardScreen.route
                                                        : UserDashboardScreen
                                                              .route;
                                                    Navigator.of(
                                                      context,
                                                    ).pushNamedAndRemoveUntil(
                                                      route,
                                                      (_) => false,
                                                    );
                                                  }
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink(
                                      key: ValueKey('face-only'),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;
}
