import 'package:flutter/material.dart';

import '../models.dart';

/// Escolhe uma classe ('' = sem classe). Null se cancelado.
Future<String?> escolherClasseDialog(BuildContext context, Banco banco, String titulo) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(titulo),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, ''),
          child: const Text('Sem classe'),
        ),
        ...banco.classes.map((c) => SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, c.id),
              child: Text(c.nome),
            )),
      ],
    ),
  );
}

/// Escolhe uma congregação ('' = sem congregação). Null se cancelado.
Future<String?> escolherCongregacaoDialog(BuildContext context, Banco banco, String titulo) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(titulo),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, ''),
          child: const Text('Sem congregação'),
        ),
        ...banco.todasCongregacoes.map((c) => SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, c.id),
              child: Row(children: [
                CircleAvatar(radius: 6, backgroundColor: corDeHex(c.cor, padrao: Colors.blue)),
                const SizedBox(width: 10),
                Flexible(child: Text(c.nome)),
              ]),
            )),
      ],
    ),
  );
}

/// Escolhe uma lista "padrão" (as automáticas não aceitam membros à mão).
Future<ListaEntidades?> escolherListaDialog(BuildContext context, Banco banco) {
  final opcoes = banco.listas.where((l) => l.tipo == 'padrao' && !l.isLocked).toList();
  return showDialog<ListaEntidades>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Adicionar a qual lista?'),
      children: opcoes.isEmpty
          ? [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Text('Não há listas disponíveis (as bloqueadas e as automáticas não aparecem). Crie uma na área Listas.'),
              ),
            ]
          : opcoes
              .map((l) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, l),
                    child: Row(children: [
                      CircleAvatar(radius: 6, backgroundColor: corDeHex(l.corTema)),
                      const SizedBox(width: 10),
                      Flexible(child: Text(l.titulo)),
                    ]),
                  ))
              .toList(),
    ),
  );
}
