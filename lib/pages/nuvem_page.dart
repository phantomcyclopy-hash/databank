import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../nuvem/firebase_rest.dart';
import '../nuvem/sync_service.dart';
import '../widgets/dialogos.dart';

/// Login, espaço da igreja e sincronização com o Firebase.
class NuvemPage extends StatefulWidget {
  const NuvemPage({super.key});

  @override
  State<NuvemPage> createState() => _NuvemPageState();
}

class _NuvemPageState extends State<NuvemPage> {
  final Sync _sync = Sync.instance;

  late final TextEditingController _apiKey;
  late final TextEditingController _projeto;
  late final TextEditingController _webId;
  final TextEditingController _email = TextEditingController();
  final TextEditingController _senha = TextEditingController();
  final TextEditingController _espacoId = TextEditingController();
  final TextEditingController _espacoCodigo = TextEditingController();

  bool _trabalhando = false;
  bool _verSenha = false;

  @override
  void initState() {
    super.initState();
    _apiKey = TextEditingController(text: _sync.apiKey);
    _projeto = TextEditingController(text: _sync.projectId);
    _webId = TextEditingController(text: _sync.webClientId);
  }

  @override
  void dispose() {
    for (final c in [_apiKey, _projeto, _webId, _email, _senha, _espacoId, _espacoCodigo]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _executar(Future<void> Function() f, {String? sucesso}) async {
    setState(() => _trabalhando = true);
    try {
      await f();
      if (sucesso != null) _snack(sucesso);
    } on FirebaseErro catch (e) {
      _snack(e.mensagem);
    } on PlatformException catch (e) {
      _snack('Falha no login com Google (${e.code}). Confira o SHA-1 e o ID do cliente web no guia.');
    } catch (e) {
      _snack('Erro: $e');
    } finally {
      if (mounted) setState(() => _trabalhando = false);
    }
  }

  Future<void> _salvarConfig() => _sync.salvarConfig(_apiKey.text, _projeto.text, _webId.text);

  Widget _secao(String titulo, List<Widget> filhos, {String? ajuda}) {
    final e = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: e.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            if (ajuda != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(ajuda, style: TextStyle(fontSize: 12, color: e.onSurfaceVariant)),
              ),
            const SizedBox(height: 8),
            ...filhos,
          ],
        ),
      ),
    );
  }

  Widget _copiavel(String rotulo, String valor) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(rotulo, style: const TextStyle(fontSize: 12)),
      subtitle: SelectableText(valor,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      trailing: IconButton(
        icon: const Icon(Icons.copy),
        tooltip: 'Copiar',
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: valor));
          _snack('Copiado.');
        },
      ),
    );
  }

  String _quando(int ms) {
    if (ms <= 0) return 'nunca';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(d.day)}/${dois(d.month)}/${d.year} ${dois(d.hour)}:${dois(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final e = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Nuvem (Firebase)')),
      body: ListenableBuilder(
        listenable: _sync,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.only(top: 6, bottom: 32),
            children: [
              // ---------------------------------------------------- projeto
              _secao(
                '1. Projeto Firebase',
                [
                  TextField(
                    controller: _apiKey,
                    decoration: const InputDecoration(
                      labelText: 'Chave de API da Web (Web API Key)',
                      isDense: true,
                    ),
                  ),
                  TextField(
                    controller: _projeto,
                    decoration: const InputDecoration(labelText: 'ID do projeto (Project ID)', isDense: true),
                  ),
                  TextField(
                    controller: _webId,
                    decoration: const InputDecoration(
                      labelText: 'ID do cliente web (só para entrar com Google)',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      onPressed: _trabalhando ? null : () => _executar(_salvarConfig, sucesso: 'Dados do projeto salvos.'),
                      child: const Text('Salvar dados do projeto'),
                    ),
                  ),
                ],
                ajuda: 'Veja o passo a passo no arquivo firebase/LEIA-ME.md do projeto.',
              ),

              // ------------------------------------------------------ conta
              if (_sync.logado)
                _secao('2. Conta', [
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.account_circle),
                    title: Text(_sync.sessao!.email.isEmpty ? 'Conectado' : _sync.sessao!.email),
                    subtitle: const Text('Conectado ao Firebase'),
                    trailing: TextButton(
                      onPressed: _trabalhando ? null : () => _executar(_sync.sair),
                      child: const Text('Sair'),
                    ),
                  ),
                ])
              else
                _secao('2. Conta', [
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'E-mail', isDense: true),
                  ),
                  TextField(
                    controller: _senha,
                    obscureText: !_verSenha,
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: Icon(_verSenha ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _verSenha = !_verSenha),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _trabalhando
                            ? null
                            : () => _executar(() async {
                                  await _salvarConfig();
                                  await _sync.entrarEmail(_email.text, _senha.text);
                                }),
                        child: const Text('Entrar'),
                      ),
                      OutlinedButton(
                        onPressed: _trabalhando
                            ? null
                            : () => _executar(() async {
                                  await _salvarConfig();
                                  await _sync.cadastrarEmail(_email.text, _senha.text);
                                }, sucesso: 'Conta criada e conectada.'),
                        child: const Text('Criar conta'),
                      ),
                      if (Platform.isAndroid)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.login),
                          label: const Text('Entrar com Google'),
                          onPressed: _trabalhando
                              ? null
                              : () => _executar(() async {
                                    await _salvarConfig();
                                    await _sync.entrarGoogle();
                                  }),
                        ),
                    ],
                  ),
                  TextButton(
                    onPressed: _trabalhando
                        ? null
                        : () => _executar(() async {
                              await _salvarConfig();
                              await _sync.redefinirSenha(_email.text);
                            }, sucesso: 'Se o e-mail existir, enviamos o link para redefinir a senha.'),
                    child: const Text('Esqueci a senha'),
                  ),
                ]),

              // ------------------------------------------------------ espaço
              if (_sync.logado)
                _secao(
                  '3. Espaço da igreja',
                  _sync.igrejaId.isEmpty
                      ? [
                          const Text(
                            'O espaço é onde ficam os dados compartilhados. Crie um (no primeiro aparelho) ou entre em um existente (nos outros).',
                            style: TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            icon: const Icon(Icons.add_home_work_outlined),
                            label: const Text('Criar espaço da igreja'),
                            onPressed: _trabalhando
                                ? null
                                : () => _executar(_sync.criarEspaco,
                                    sucesso: 'Espaço criado. Anote o ID e o código abaixo.'),
                          ),
                          const Divider(height: 28),
                          const Text('Já existe um espaço?',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          TextField(
                            controller: _espacoId,
                            decoration: const InputDecoration(labelText: 'ID do espaço', isDense: true),
                          ),
                          TextField(
                            controller: _espacoCodigo,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(labelText: 'Código de acesso', isDense: true),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.tonal(
                              onPressed: _trabalhando
                                  ? null
                                  : () => _executar(
                                      () => _sync.entrarEspaco(_espacoId.text, _espacoCodigo.text),
                                      sucesso: 'Você entrou no espaço.'),
                              child: const Text('Entrar no espaço'),
                            ),
                          ),
                        ]
                      : [
                          _copiavel('ID do espaço', _sync.igrejaId),
                          _copiavel('Código de acesso', _sync.codigo),
                          Text(
                            'Em outro aparelho: configure o projeto, entre com uma conta e use "Já existe um espaço?" com estes dois dados. Guarde o código: quem o tiver entra no espaço.',
                            style: TextStyle(fontSize: 12, color: e.onSurfaceVariant),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _trabalhando
                                  ? null
                                  : () async {
                                      final ok = await confirmar(
                                        context,
                                        titulo: 'Sair do espaço?',
                                        mensagem:
                                            'Este aparelho para de sincronizar. Os dados continuam aqui e na nuvem.',
                                        acao: 'Sair',
                                      );
                                      if (ok) _executar(_sync.sairEspaco);
                                    },
                              child: const Text('Sair do espaço'),
                            ),
                          ),
                        ],
                ),

              // ------------------------------------------------ sincronização
              if (_sync.pronto)
                _secao('4. Sincronização', [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sincronizar automaticamente'),
                    subtitle: const Text('Envia depois de cada alteração e confere a nuvem a cada minuto'),
                    value: _sync.automatico,
                    onChanged: (v) => _sync.alterarAutomatico(v),
                  ),
                  const SizedBox(height: 4),
                  Text('Última sincronização: ${_quando(_sync.ultimoSync)}',
                      style: const TextStyle(fontSize: 13)),
                  if (_sync.status.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(_sync.status, style: TextStyle(fontSize: 12, color: e.onSurfaceVariant)),
                    ),
                  if (_sync.erro != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_sync.erro!, style: const TextStyle(fontSize: 12, color: Colors.red)),
                    ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    icon: _sync.ocupado
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync),
                    label: Text(_sync.ocupado ? 'Sincronizando...' : 'Sincronizar agora'),
                    onPressed: _sync.ocupado ? null : () => _sync.sincronizar(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Se o mesmo item for alterado em dois aparelhos ao mesmo tempo, vale a versão do aparelho que sincronizar por último. Itens apagados somem em todos os aparelhos.',
                    style: TextStyle(fontSize: 12, color: e.onSurfaceVariant),
                  ),
                ]),
            ],
          );
        },
      ),
    );
  }
}
