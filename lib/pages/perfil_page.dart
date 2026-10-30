import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../nuvem/firebase_rest.dart';
import '../nuvem/sync_service.dart';
import '../widgets/dialogos.dart';
import 'contas_page.dart';

/// Conta do usuário: foto, nome, papel, sincronização e saída.
class PerfilPage extends StatefulWidget {
  const PerfilPage({super.key});

  @override
  State<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends State<PerfilPage> {
  final Sync _sync = Sync.instance;
  late final TextEditingController _nome = TextEditingController(text: _sync.nome);
  bool _ocupado = false;

  @override
  void dispose() {
    _nome.dispose();
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
      _snack('Erro: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _trocarFoto() async {
    final img = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 256,
      maxHeight: 256,
    );
    if (img == null) return;
    final bytes = await img.readAsBytes();
    await _executar(() => _sync.salvarPerfil(_nome.text, base64Encode(bytes)),
        sucesso: 'Foto atualizada.');
  }

  Future<void> _sair() async {
    final ok = await confirmar(
      context,
      titulo: 'Sair da conta?',
      mensagem:
          'Os dados salvos neste aparelho serão apagados (eles continuam na nuvem). Entre de novo para recuperá-los.',
      acao: 'Sair',
    );
    if (!ok) return;
    await _executar(_sync.sair);
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  String _quando(int ms) {
    if (ms <= 0) return 'nunca';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(d.day)}/${dois(d.month)}/${d.year} ${dois(d.hour)}:${dois(d.minute)}';
  }

  Widget _secao(String titulo, List<Widget> filhos) {
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
            const SizedBox(height: 8),
            ...filhos,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Minha conta')),
      body: ListenableBuilder(
        listenable: _sync,
        builder: (context, _) {
          ImageProvider? img;
          if (_sync.foto.isNotEmpty) {
            try {
              img = MemoryImage(base64Decode(_sync.foto));
            } catch (_) {
              img = null;
            }
          }
          final pendente = _sync.pedido == 'secretaria' && !_sync.podeEditar;

          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 32),
            children: [
              Center(
                child: GestureDetector(
                  onTap: _ocupado ? null : _trocarFoto,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 52,
                        backgroundColor: e.secondaryContainer,
                        backgroundImage: img,
                        child: img == null
                            ? Text(
                                _sync.nomeExibido.isEmpty ? '?' : _sync.nomeExibido[0].toUpperCase(),
                                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700),
                              )
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: e.primary,
                          child: Icon(Icons.camera_alt, size: 16, color: e.onPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Chip(
                  label: Text(_sync.papelRotulo),
                  avatar: const Icon(Icons.verified_user, size: 16),
                ),
              ),
              if (pendente)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                  child: Text(
                    'Seu pedido de acesso como secretaria aguarda a aprovação da conta principal. Até lá você entra como membro.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: e.primary),
                  ),
                ),
              _secao('Dados', [
                TextField(
                  controller: _nome,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nome'),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('E-mail', style: TextStyle(fontSize: 12)),
                  subtitle: Text(_sync.email, style: const TextStyle(fontSize: 15)),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: _ocupado
                        ? null
                        : () => _executar(() => _sync.salvarPerfil(_nome.text, _sync.foto),
                            sucesso: 'Dados salvos.'),
                    child: const Text('Salvar nome'),
                  ),
                ),
              ]),
              _secao('Sincronização', [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sincronizar automaticamente'),
                  subtitle: const Text('Confere a nuvem a cada minuto e ao abrir o app'),
                  value: _sync.automatico,
                  onChanged: (v) => _sync.alterarAutomatico(v),
                ),
                Text('Última sincronização: ${_quando(_sync.ultimoSync)}',
                    style: const TextStyle(fontSize: 13)),
                if (_sync.status.isNotEmpty)
                  Text(_sync.status, style: TextStyle(fontSize: 12, color: e.onSurfaceVariant)),
                if (_sync.erro != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_sync.erro!, style: const TextStyle(fontSize: 12, color: Colors.red)),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  icon: _sync.ocupado
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync),
                  label: Text(_sync.ocupado ? 'Sincronizando...' : 'Sincronizar agora'),
                  onPressed: _sync.ocupado ? null : () => _sync.sincronizar(),
                ),
              ]),
              _secao('Conta', [
                if (_sync.ehDono)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.manage_accounts),
                    title: const Text('Contas e permissões'),
                    subtitle: const Text('Aprovar secretarias e definir quem edita'),
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const ContasPage())),
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.lock_reset),
                  title: const Text('Redefinir senha'),
                  subtitle: const Text('Enviamos um link para o seu e-mail'),
                  onTap: _ocupado
                      ? null
                      : () => _executar(() => _sync.redefinirSenha(_sync.email),
                          sucesso: 'Link enviado para ${_sync.email}.'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('Sair'),
                  onTap: _ocupado ? null : _sair,
                ),
              ]),
            ],
          );
        },
      ),
    );
  }
}
