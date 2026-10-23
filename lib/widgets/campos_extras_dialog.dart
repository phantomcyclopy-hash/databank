import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';

/// Gerencia os campos extras (valem para todos os membros): adicionar,
/// renomear e excluir. [onSalvar] roda ao fechar.
Future<void> mostrarCamposExtras(
  BuildContext context,
  Banco banco,
  VoidCallback onSalvar,
) async {
  const uuid = Uuid();
  final novoCtrl = TextEditingController();
  var novoTipo = 'texto';

  const nomesTipo = {'texto': 'Texto', 'numero': 'Número', 'checkbox': 'Caixa de marcar'};

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('Campos extras'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Informações adicionais que aparecem na ficha de todos os membros.',
                  style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                if (banco.colunas.isEmpty) const Text('Nenhum campo extra criado.'),
                ...banco.colunas.map((c) => Row(
                      key: ValueKey(c.id),
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: c.nome,
                            decoration: InputDecoration(
                              isDense: true,
                              helperText: nomesTipo[c.tipo] ?? c.tipo,
                            ),
                            onChanged: (v) {
                              if (v.trim().isNotEmpty) c.nome = v.trim();
                            },
                          ),
                        ),
                        IconButton(
                          tooltip: 'Excluir campo',
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: ctx,
                              builder: (c2) => AlertDialog(
                                title: const Text('Excluir campo?'),
                                content: Text(
                                    'O campo "${c.nome}" e os valores preenchidos nele serão apagados de todos os membros.'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(c2, false),
                                      child: const Text('Cancelar')),
                                  FilledButton(
                                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                    onPressed: () => Navigator.pop(c2, true),
                                    child: const Text('Excluir'),
                                  ),
                                ],
                              ),
                            );
                            if (ok != true) return;
                            for (final m in banco.membros) {
                              m.valoresAtributosDinamicos.remove(c.id);
                            }
                            setD(() => banco.colunas.removeWhere((e) => e.id == c.id));
                          },
                        ),
                      ],
                    )),
                const Divider(height: 28),
                const Text('Novo campo', style: TextStyle(fontWeight: FontWeight.bold)),
                TextField(
                  controller: novoCtrl,
                  decoration: const InputDecoration(labelText: 'Nome do campo'),
                ),
                const SizedBox(height: 8),
                DropdownButton<String>(
                  value: novoTipo,
                  isExpanded: true,
                  items: nomesTipo.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setD(() => novoTipo = v ?? 'texto'),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar campo'),
                    onPressed: () {
                      final nome = novoCtrl.text.trim();
                      if (nome.isEmpty) return;
                      setD(() {
                        banco.colunas
                            .add(ColunaEspecificacao(id: uuid.v4(), nome: nome, tipo: novoTipo));
                        novoCtrl.clear();
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Concluir')),
        ],
      ),
    ),
  );

  onSalvar();
}
