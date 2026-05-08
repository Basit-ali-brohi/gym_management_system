import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _tenantCtrl = TextEditingController(text: 'demo');
  final _emailCtrl = TextEditingController(text: 'admin@demo.com');
  final _passCtrl = TextEditingController(text: 'admin123');
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _tenantCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final theme = Theme.of(context);

    final errorText = switch (auth.error) {
      null => null,
      'invalid_credentials' => 'Tenant / Email / Password galat hai',
      'unauthorized' => 'Login unauthorized',
      'login_failed' => 'Server connect nahi ho raha ($apiBaseUrl). API URL/port check karo, backend run karo.',
      _ => auth.error,
    };

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Gym Management', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 6),
                      Text('SaaS Login', style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _tenantCtrl,
                        decoration: const InputDecoration(labelText: 'Tenant / Gym Code'),
                        validator: (v) => (v == null || v.trim().length < 2) ? 'Tenant required' : null,
                        enabled: !auth.isLoading,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _emailCtrl,
                        decoration: const InputDecoration(labelText: 'Email'),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) => (v == null || !v.contains('@')) ? 'Valid email required' : null,
                        enabled: !auth.isLoading,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _passCtrl,
                        decoration: const InputDecoration(labelText: 'Password'),
                        obscureText: true,
                        validator: (v) => (v == null || v.isEmpty) ? 'Password required' : null,
                        enabled: !auth.isLoading,
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          errorText,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: auth.isLoading
                            ? null
                            : () async {
                                if (!_formKey.currentState!.validate()) return;
                                await ref.read(authControllerProvider.notifier).login(
                                      tenantSlug: _tenantCtrl.text,
                                      email: _emailCtrl.text,
                                      password: _passCtrl.text,
                                    );
                              },
                        child: auth.isLoading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Login'),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Dev default: demo / admin@demo.com / admin123',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
