import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';

/// Pergunta por quanto tempo publicar e adiciona ao Mural. A publicação some
/// sozinha no prazo escolhido (no máximo 30 dias).
Future<void> publicarNoMural(
  BuildContext context,
  Banco banco, {
  required String tipo,
  required String titulo,
  required String texto,
  required VoidCallback onSalvar,
}) async {
  var dias = 30;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('Publicar no Mural'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"$titulo" ficará visível para todos os que acessam o app.',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            const Text('Some do Mural em:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('7 dias')),
                ButtonSegment(value: 15, label: Text('15 dias')),
                ButtonSegment(value: 30, label: Text('30 dias')),
              ],
              selected: {dias},
              onSelectionChanged: (s) => setD(() => dias = s.first),
            ),
            const SizedBox(height: 8),
            const Text(
              'É uma cópia do conteúdo de agora; mudanças feitas depois não alteram o que foi publicado.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Publicar')),
        ],
      ),
    ),
  );
  if (ok != true) return;

  final agora = DateTime.now();
  banco.publicacoes.add(Publicacao(
    id: const Uuid().v4(),
    tipo: tipo,
    titulo: titulo,
    texto: texto,
    publicadoEm: agora.millisecondsSinceEpoch,
    expiraEm: isoData(agora.add(Duration(days: dias))),
  ));
  onSalvar();
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Publicado no Mural por $dias dias.')));
  }
}
