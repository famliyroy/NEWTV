import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/server_config.dart';
import '../../core/network/api_exception.dart';
import '../../data/api/auth_api.dart';
import '../../providers.dart';
import '../../shared/widgets/glass_card.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  var _testing = false;
  var _allowSelfSigned = false;
  ServerProbeResult? _probe;
  String? _status;

  @override
  void initState() {
    super.initState();
    final server = ref.read(appDependenciesProvider).session.server;
    if (server != null) _controller.text = server.baseUrl;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    if (ServerConfig.normalize(value ?? '') == null) {
      return '请输入有效的 http:// 或 https:// 服务器地址';
    }
    return null;
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _testing = true;
      _probe = null;
      _status = null;
    });
    final config = ServerConfig(
      baseUrl: ServerConfig.normalize(_controller.text)!,
      allowSelfSigned: _allowSelfSigned,
    );
    try {
      final result = await ref.read(appDependenciesProvider).authApi.probe(config);
      if (!mounted) return;
      setState(() {
        _probe = result;
        _status = '连接成功${config.isSecure ? '' : '（当前是非加密连接）'}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = readableError(error));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _continue() async {
    final probe = _probe;
    if (probe == null) {
      await _testConnection();
      return;
    }
    final dependencies = ref.read(appDependenciesProvider);
    await dependencies.serverStore.save(probe.config);
    await dependencies.serverStore.saveStorageType(probe.storageType);
    dependencies.dioClient.updateServer(probe.config);
    await dependencies.session.configure(probe.config, authenticated: false);
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canContinue = _probe != null && !_testing;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Icon(Icons.live_tv_rounded, size: 72, color: scheme.primary),
              const SizedBox(height: 16),
              Text(
                'NEWTV',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 8),
              Text(
                '连接你的 MoonTVPlus 服务器',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              GlassCard(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _controller,
                        autofocus: true,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: '服务器地址',
                          hintText: 'https://tv.example.com',
                          prefixIcon: Icon(Icons.dns_outlined),
                        ),
                        validator: _validate,
                        onChanged: (_) => setState(() => _probe = null),
                        onFieldSubmitted: (_) => _testConnection(),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('允许自签名证书'),
                        subtitle: const Text('仅在可信局域网环境中开启'),
                        value: _allowSelfSigned,
                        onChanged: (value) => setState(() {
                          _allowSelfSigned = value;
                          _probe = null;
                        }),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _testing ? null : _testConnection,
                              icon: _testing
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.wifi_tethering_outlined),
                              label: Text(_testing ? '连接中…' : '测试连接'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: canContinue ? _continue : null,
                              child: const Text('下一步'),
                            ),
                          ),
                        ],
                      ),
                      if (_status != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _status!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _probe == null ? scheme.error : scheme.primary,
                          ),
                        ),
                      ],
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
