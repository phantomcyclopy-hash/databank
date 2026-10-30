import 'package:flutter/material.dart';

import '../nuvem/firebase_rest.dart';
import '../nuvem/sync_service.dart';

/// Entrada do app: só e-mail e senha. Quem cria conta entra como membro; quem
/// pede "secretaria" fica aguardando a aprovação da conta principal.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _nome = TextEditingController();
  final _email = TextEditingController();
  final _senha = TextEditingController();

  bool _criando = false;
  bool _pedirSecretaria = false;
  bool _verSenha = false;
  bool _ocupado = false;

  @override
  void dispose() {
    _nome.dispose();
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _executar(Future<void> Function() f, {String? sucesso}) async {
    setState(() => _ocupado = true);
    try {
      await f();
      if (sucesso != null) _snack(sucesso);
    } on FirebaseErro catch (e) {
      _snack(e.mensagem);
    } catch (e) {
      _snack('Sem conexão ou erro inesperado: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _enviar() {
    final email = _email.text.trim();
    final senha = _senha.text;
    if (!email.contains('@')) {
      _snack('Informe um e-mail válido.');
      return;
    }
    if (senha.length < 6) {
      _snack('A senha precisa ter pelo menos 6 caracteres.');
      return;
    }
    if (_criando) {
      if (_nome.text.trim().isEmpty) {
        _snack('Informe seu nome.');
        return;
      }
      _executar(() => Sync.instance.criarConta(
            nomeCompleto: _nome.text,
            email: email,
            senha: senha,
            pedirSecretaria: _pedirSecretaria,
          ));
    } else {
      _executar(() => Sync.instance.entrar(email, senha));
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset('assets/icon/app_icon.png', height: 96, width: 96),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Secretaria IBMMK',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                Text('Cadastro de membros, listas e atas',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: e.onSurfaceVariant)),
                const SizedBox(height: 28),
                if (_criando)
                  TextField(
                    controller: _nome,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Seu nome'),
                  ),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'E-mail'),
                ),
                TextField(
                  controller: _senha,
                  obscureText: !_verSenha,
                  onSubmitted: (_) => _ocupado ? null : _enviar(),
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    suffixIcon: IconButton(
                      icon: Icon(_verSenha ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _verSenha = !_verSenha),
                    ),
                  ),
                ),
                if (_criando) ...[
                  const SizedBox(height: 16),
                  const Text('Tipo de conta', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Membro'), icon: Icon(Icons.person)),
                      ButtonSegment(
                          value: true, label: Text('Secretaria'), icon: Icon(Icons.admin_panel_settings)),
                    ],
                    selected: {_pedirSecretaria},
                    onSelectionChanged: (s) => setState(() => _pedirSecretaria = s.first),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _pedirSecretaria
                          ? 'Seu pedido será analisado pela conta principal. Até lá, você entra como membro.'
                          : 'Você verá o mural e a agenda da igreja.',
                      style: TextStyle(fontSize: 12, color: e.onSurfaceVariant),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _ocupado ? null : _enviar,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _ocupado
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_criando ? 'Criar conta' : 'Entrar'),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _ocupado ? null : () => setState(() => _criando = !_criando),
                  child: Text(_criando ? 'Já tenho conta. Entrar' : 'Criar conta'),
                ),
                if (!_criando)
                  TextButton(
                    onPressed: _ocupado
                        ? null
                        : () {
                            if (!_email.text.contains('@')) {
                              _snack('Digite seu e-mail acima primeiro.');
                              return;
                            }
                            _executar(() => Sync.instance.redefinirSenha(_email.text),
                                sucesso: 'Se o e-mail existir, enviamos o link para redefinir a senha.');
                          },
                    child: const Text('Esqueci a senha'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mostrada quando a conta foi bloqueada pela conta principal.
class BloqueadoPage extends StatelessWidget {
  const BloqueadoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.block, size: 56),
                const SizedBox(height: 14),
                const Text('Acesso bloqueado',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text(
                  'Esta conta não tem acesso ao espaço da igreja. Fale com a secretaria.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: () => Sync.instance.sair(),
                  child: const Text('Sair'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
