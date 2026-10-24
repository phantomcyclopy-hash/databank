import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import 'dialogos.dart';

/// Gerencia as classes da EBD: renomear, adicionar e remover. A classe especial
/// "Pastor" pode ser renomeada, mas não removida. [onSalvar] roda ao fechar.
Future<void> mostrarClasses(
  BuildContext context,
  Banco banco,
  VoidCallback onSalvar,
) async {
  const uuid = Uuid();
  final novoCtrl = TextEditingController();

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('Classes da EBD'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cada membro pode ter uma classe. A classe "Pastor" é especial: não pode ser removida e seus membros podem assinar como pastor presidente nas impressões.',
                  style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                ...banco.classes.map((c) {
                  final especial = c.id == kClassePastorId;
                  return Row(
                    key: ValueKey(c.id),
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: c.nome,
                          decoration: InputDecoration(
                            isDense: true,
                            helperText: especial
                                ? 'Especial · ${banco.membros.where((m) => m.classe == c.id).length} membro(s)'
                                : '${banco.membros.where((m) => m.classe == c.id).length} membro(s)',
                          ),
                          onChanged: (v) {
                            if (v.trim().isNotEmpty) c.nome = v.trim();
                          },
                        ),
                      ),
                      if (especial)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Tooltip(message: 'Classe especial', child: Icon(Icons.lock_outline)),
                        )
                      else
                        IconButton(
                          tooltip: 'Remover classe',
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () async {
                            final n = banco.membros.where((m) => m.classe == c.id).length;
                            final ok = await confirmar(
                              ctx,
                              titulo: 'Remover classe?',
                              mensagem: n > 0
                                  ? 'A classe "${c.nome}" será removida e $n membro(s) ficarão sem classe. Os membros não são apagados.'
                                  : 'A classe "${c.nome}" será removida.',
                              acao: 'Remover',
                            );
                            if (!ok) return;
                            for (final m in banco.membros) {
                              if (m.classe == c.id) m.classe = '';
                            }
                            setD(() => banco.classes.remove(c));
                          },
                        ),
                    ],
                  );
                }),
                const Divider(height: 28),
                const Text('Nova classe', style: TextStyle(fontWeight: FontWeight.bold)),
                TextField(
                  controller: novoCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nome da classe'),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar classe'),
                    onPressed: () {
                      final nome = novoCtrl.text.trim();
                      if (nome.isEmpty) return;
                      setD(() {
                        banco.classes.add(Classe(id: uuid.v4(), nome: nome));
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
