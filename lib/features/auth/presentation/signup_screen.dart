import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/design_system.dart';
import '../../../data/data_providers.dart';
import '../application/auth_validators.dart';
import 'widgets/auth_scaffold.dart';

/// Account creation. When the project requires email confirmation, sign-up
/// returns without a session and a "check your email" view is shown;
/// otherwise the router redirects into the app.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _confirmationSentTo;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    final auth = ref.read(authRepositoryProvider);
    final email = _email.text.trim();
    try {
      await auth.signUp(
        email: email,
        password: _password.text,
        displayName: _name.text.trim(),
      );
      TextInput.finishAutofillContext();
      // No session -> email confirmation required.
      if (auth.currentUser == null && mounted) {
        setState(() => _confirmationSentTo = email);
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyAuthMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sentTo = _confirmationSentTo;
    if (sentTo != null) {
      return AuthScaffold(
        title: 'Check your email',
        subtitle: 'One more step',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormMessage(
              isError: false,
              message:
                  'We sent a confirmation link to $sentTo. Open it to '
                  'activate your account, then sign in.',
            ),
            Gaps.h24,
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
              onPressed: () => context.go(AppRoutes.login),
              child: const Text('Back to sign in'),
            ),
          ],
        ),
      );
    }

    return AuthScaffold(
      title: 'Create account',
      subtitle: 'Organize notes and quizzes by subject',
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const Key('signup-name'),
                controller: _name,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                validator: AuthValidators.displayName,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  helperText: 'Shown to people you share with',
                ),
              ),
              Gaps.h16,
              TextFormField(
                key: const Key('signup-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                validator: AuthValidators.email,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              Gaps.h16,
              PasswordField(
                key: const Key('signup-password'),
                controller: _password,
                autofillHints: const [AutofillHints.newPassword],
                validator: AuthValidators.newPassword,
                helperText:
                    'At least ${AuthValidators.minPasswordLength} characters, '
                    'letters and numbers',
              ),
              Gaps.h16,
              PasswordField(
                key: const Key('signup-confirm'),
                controller: _confirm,
                label: 'Confirm password',
                autofillHints: const [AutofillHints.newPassword],
                validator: AuthValidators.confirmPassword(() => _password.text),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
              Gaps.h24,
              if (_error != null) ...[FormMessage(message: _error!), Gaps.h16],
              LoadingButton(
                key: const Key('signup-submit'),
                label: 'Create account',
                loading: _loading,
                onPressed: _submit,
              ),
              Gaps.h16,
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Already have an account?'),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => context.go(AppRoutes.login),
                    child: const Text('Sign in'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
