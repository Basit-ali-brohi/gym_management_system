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
  bool _obscure = true;

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
      'invalid_credentials' => 'Invalid tenant, email, or password',
      'unauthorized' => 'Login unauthorized',
      'login_failed' => 'Cannot connect to server ($apiBaseUrl). Check the API URL/port and ensure the backend is running.',
      _ => auth.error,
    };

    Widget formCard() {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        height: 42,
                        width: 42,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: theme.colorScheme.primaryContainer,
                          border: Border.all(color: theme.colorScheme.outlineVariant),
                        ),
                        child: Icon(Icons.fitness_center, color: theme.colorScheme.onPrimaryContainer),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Gym Management', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text('Sign in to continue', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _tenantCtrl,
                    decoration: const InputDecoration(labelText: 'Tenant / Gym Code', prefixIcon: Icon(Icons.apartment_outlined)),
                    validator: (v) => (v == null || v.trim().length < 2) ? 'Tenant required' : null,
                    enabled: !auth.isLoading,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.alternate_email)),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => (v == null || !v.contains('@')) ? 'Valid email required' : null,
                    enabled: !auth.isLoading,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _passCtrl,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                        onPressed: auth.isLoading ? null : () => setState(() => _obscure = !_obscure),
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      ),
                    ),
                    obscureText: _obscure,
                    validator: (v) => (v == null || v.isEmpty) ? 'Password required' : null,
                    enabled: !auth.isLoading,
                    onFieldSubmitted: (_) async {
                      if (auth.isLoading) return;
                      if (!(_formKey.currentState?.validate() ?? false)) return;
                      await ref.read(authControllerProvider.notifier).login(
                            tenantSlug: _tenantCtrl.text,
                            email: _emailCtrl.text,
                            password: _passCtrl.text,
                          );
                    },
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withAlpha(18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: theme.colorScheme.error),
                          const SizedBox(width: 10),
                          Expanded(child: Text(errorText, style: theme.textTheme.bodyMedium)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: auth.isLoading
                        ? null
                        : () async {
                            if (!(_formKey.currentState?.validate() ?? false)) return;
                            await ref.read(authControllerProvider.notifier).login(
                                  tenantSlug: _tenantCtrl.text,
                                  email: _emailCtrl.text,
                                  password: _passCtrl.text,
                                );
                          },
                    child: auth.isLoading
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 980;
          final bg = theme.colorScheme.surface;
          final fg = theme.colorScheme.onSurface;
          final grad = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary.withAlpha(28),
              theme.colorScheme.tertiary.withAlpha(20),
              theme.colorScheme.surface,
            ],
          );

          if (!wide) {
            return Container(
              decoration: BoxDecoration(gradient: grad),
              child: Center(child: Padding(padding: const EdgeInsets.all(20), child: formCard())),
            );
          }

          return Container(
            color: bg,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(gradient: grad),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(40, 40, 40, 40),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Run your gym like a business', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: fg)),
                              const SizedBox(height: 10),
                              Text(
                                'Members, leads, billing, attendance, inventory, reports — sab kuch aik hi dashboard me.',
                                style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 18),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: const [
                                  _LoginPill(icon: Icons.people_alt_outlined, text: 'Members'),
                                  _LoginPill(icon: Icons.person_search_outlined, text: 'Leads'),
                                  _LoginPill(icon: Icons.receipt_long_outlined, text: 'Invoices'),
                                  _LoginPill(icon: Icons.how_to_reg_outlined, text: 'Attendance'),
                                  _LoginPill(icon: Icons.inventory_2_outlined, text: 'Inventory'),
                                  _LoginPill(icon: Icons.bar_chart_outlined, text: 'Reports'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(28),
                  child: Center(child: formCard()),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LoginPill extends StatelessWidget {
  const _LoginPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withAlpha(200),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(text, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
