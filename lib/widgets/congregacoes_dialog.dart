import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import 'seletor_cor.dart';

/// Gerencia as congregações: adicionar, renomear, trocar a cor e remover, além
/// da opção multicongregacional. [onSalvar] roda ao fechar.
Future<void> mostrarGerenciarCongregacoes(
  BuildContext context,
  Banco banco,
  VoidCallback onSalvar,
) async {
  const uuid = Uuid();

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        Widget linha({
          required Key chave,
          required String nome,
          required String corHex,
          required ValueChanged<String> aoMudarNome,
          required ValueChanged<String> aoMudarCor,
          Widget? acao,
        }) {
          return Padding(
            key: chave,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () async {
                    final nova = await escolherCor(ctx, corDeHex(corHex, padrao: Colors.blue),
                        titulo: 'Cor de $nome');
                    if (nova != null) setD(() => aoMudarCor(hexDeCor(nova)));
                  },
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: corDeHex(corHex, padrao: Colors.blue),
                    child: const Icon(Icons.palette, size: 14, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: nome,
                    decoration: const InputDecoration(isDense: true),
                    onChanged: aoMudarNome,
                  ),
                ),
                if (acao != null) acao,
              ],
            ),
          );
        }

        Future<void> remover(Congregacao c) async {
          final n = banco.contar(banco.membros, c.id);
          final ok = await showDialog<bool>(
            context: ctx,
            builder: (c2) => AlertDialog(
              title: const Text('Remover congregação?'),
              content: Text(n > 0
                  ? '"${c.nome}" será removida e $n membro(s) ficarão sem congregação. Os membros não são apagados.'
                  : '"${c.nome}" será removida.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('Cancelar')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(c2, true),
                  child: const Text('Remover'),
                ),
              ],
            ),
          );
          if (ok != true) return;
          for (final m in banco.membros) {
            if (m.congregacaoId == c.id) m.congregacaoId = '';
          }
          setD(() => banco.congregacoes.remove(c));
        }

        return AlertDialog(
          title: const Text('Congregações e cores'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Toque no círculo para escolher a cor; edite o nome direto no campo.',
                      style: TextStyle(
                          fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  if (banco.congregacoes.isEmpty) const Text('Nenhuma congregação.'),
                  ...banco.congregacoes.map((c) => linha(
                        chave: ValueKey(c.id),
                        nome: c.nome,
                        corHex: c.cor,
                        aoMudarNome: (v) => c.nome = v.trim(),
                        aoMudarCor: (v) => c.cor = v,
                        acao: IconButton(
                          tooltip: 'Remover',
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => remover(c),
                        ),
                      )),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar congregação'),
                      onPressed: () => setD(() {
                        banco.congregacoes.add(Congregacao(
                          id: uuid.v4(),
                          nome: 'Nova congregação',
                          cor: kPaletaCongregacoes[
                              banco.congregacoes.length % kPaletaCongregacoes.length],
                        ));
                      }),
                    ),
                  ),
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Opção multicongregacional'),
                    subtitle: const Text('Para quem serve a todas as congregações'),
                    value: banco.multiAtiva,
                    onChanged: (v) => setD(() => banco.multiAtiva = v),
                  ),
                  if (banco.multiAtiva) ...[
                    linha(
                      chave: const ValueKey('multi'),
                      nome: banco.multiNome,
                      corHex: banco.multiCor,
                      aoMudarNome: (v) =>
                          banco.multiNome = v.trim().isEmpty ? 'Multicongregacional' : v.trim(),
                      aoMudarCor: (v) => banco.multiCor = v,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Incluir ao filtrar por uma congregação'),
                      subtitle: const Text('Esses membros aparecem junto de cada congregação'),
                      value: banco.multiEmTodas,
                      onChanged: (v) => setD(() => banco.multiEmTodas = v),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Concluir')),
          ],
        );
      },
    ),
  );

  onSalvar();
}
