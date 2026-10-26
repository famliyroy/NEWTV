import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../providers.dart';
import '../../shared/widgets/glass_card.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  var _needsUsername = false;
  var _remember = true;
  var _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStorageType();
  }

  Future<void> _loadStorageType() async {
    final type = await ref.read(appDependenciesProvider).serverStore.loadStorageType();
    if (!mounted) return;
    setState(() => _needsUsername = type.isNotEmpty && type.toLowerCase() != 'localstorage');
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final password = _passwordController.text;
    final username = _usernameController.text;
    if (password.isEmpty || (_needsUsername && username.trim().isEmpty)) {
      setState(() => _error = _needsUsername ? '请输入用户名和密码' : '请输入密码');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dependencies = ref.read(appDependenciesProvider);
      await dependencies.authApi.login(
        username: _needsUsername ? username : null,
        password: password,
      );
      if (!_remember) {
        await dependencies.preferences.setBool('sessionOnly', true);
      } else {
        await dependencies.preferences.setBool('sessionOnly', false);
      }
      dependencies.session.markAuthenticated();
      if (mounted) context.go('/home');
    } catch (error) {
      if (mounted) setState(() => _error = readableError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Icon(Icons.lock_open_rounded, size: 64, color: scheme.primary),
              const SizedBox(height: 20),
              Text('登录', textAlign: TextAlign.center, style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 24),
              GlassCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_needsUsername) ...[
                      TextField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: '用户名',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: '密码',
                        prefixIcon: Icon(Icons.password_outlined),
                      ),
                      obscureText: true,
                      onSubmitted: (_) => _login(),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('保持登录'),
                      value: _remember,
                      onChanged: (value) => setState(() => _remember = value ?? true),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(_error!, style: TextStyle(color: scheme.error), textAlign: TextAlign.center),
                      ),
                    FilledButton(
                      onPressed: _loading ? null : _login,
                      child: _loading
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('登录'),
                    ),
                    TextButton(
                      onPressed: _loading ? null : () => context.go('/onboarding'),
                      child: const Text('更换服务器'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
