import 'package:flutter/material.dart';

import '../nuvem/config_igreja.dart';
import '../nuvem/firebase_rest.dart';
import '../nuvem/sync_service.dart';
import '../widgets/dialogos.dart';

/// Só a conta principal vê esta tela: aprova pedidos e define o papel de cada conta.
class ContasPage extends StatefulWidget {
  const ContasPage({super.key});

  @override
  State<ContasPage> createState() => _ContasPageState();
}

class _ContasPageState extends State<ContasPage> {
  List<ContaInfo>? _contas;
  String? _erro;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _carregar() async {
    setState(() {
      _erro = null;
      _ocupado = true;
    });
    try {
      final c = await Sync.instance.listarContas();
      if (mounted) setState(() => _contas = c);
    } on FirebaseErro catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } catch (e) {
      if (mounted) setState(() => _erro = 'Erro: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _mudar(ContaInfo c, String novo) async {
    if (novo == c.papel && c.pedido.isEmpty) return;
    final rotulo = kPapeis[novo] ?? novo;
    final ok = await confirmar(
      context,
      titulo: 'Mudar para $rotulo?',
      mensagem: '${c.nome.isEmpty ? c.email : c.nome} passará a ser "$rotulo".',
      acao: 'Confirmar',
      destrutivo: novo == 'bloqueado',
    );
    if (!ok) return;
    try {
      await Sync.instance.definirPapel(c.uid, novo);
      _snack('Permissão atualizada.');
      _carregar();
    } on FirebaseErro catch (e) {
      _snack(e.mensagem);
    } catch (e) {
      _snack('Erro: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contas e permissões'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _ocupado ? null : _carregar,
          ),
        ],
      ),
      body: _contas == null
          ? Center(
              child: _erro != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_erro!, textAlign: TextAlign.center),
                    )
                  : const CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    'Secretaria: edita tudo. Inspetor: vê tudo, sem editar. Membro: só mural e agenda. '
                    'Pedidos de secretaria aparecem primeiro.',
                    style: TextStyle(fontSize: 12, color: e.onSurfaceVariant),
                  ),
                ),
                if (_contas!.isEmpty) const Text('Nenhuma conta ainda.'),
                ..._contas!.map((c) {
                  final ehDono = c.email.toLowerCase() == kDonoEmail;
                  final pendente = c.pedido == 'secretaria';
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: pendente ? e.primary : e.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(c.nome.isEmpty ? c.email : c.nome,
                                        style: const TextStyle(fontWeight: FontWeight.w600)),
                                    Text(c.email,
                                        style: TextStyle(fontSize: 12, color: e.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                              if (ehDono)
                                const Chip(label: Text('Dono'))
                              else
                                DropdownButton<String>(
                                  value: ['secretaria', 'inspetor', 'membro', 'bloqueado'].contains(c.papel)
                                      ? c.papel
                                      : 'membro',
                                  underline: const SizedBox.shrink(),
                                  items: ['secretaria', 'inspetor', 'membro', 'bloqueado']
                                      .map((p) => DropdownMenuItem(value: p, child: Text(kPapeis[p]!)))
                                      .toList(),
                                  onChanged: (v) {
                                    if (v != null) _mudar(c, v);
                                  },
                                ),
                            ],
                          ),
                          if (pendente && !ehDono)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Wrap(
                                spacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text('Pediu acesso como secretaria',
                                      style: TextStyle(fontSize: 12, color: e.primary)),
                                  FilledButton.tonal(
                                    onPressed: () => _mudar(c, 'secretaria'),
                                    child: const Text('Aprovar'),
                                  ),
                                  TextButton(
                                    onPressed: () => _mudar(c, 'membro'),
                                    child: const Text('Recusar'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
