import 'package:flutter/material.dart';

import '../calendario.dart';
import '../models.dart';
import 'dialogos.dart';
import 'mural_dialogs.dart';

/// Linha de um lembrete ou evento. [dia] é a data desta ocorrência (importa
/// para itens que se repetem). [aoMudar] deve salvar e redesenhar a tela.
class CompromissoTile extends StatelessWidget {
  final Banco banco;
  final Compromisso compromisso;
  final DateTime dia;
  final bool mostrarData;
  final VoidCallback aoMudar;

  /// Quem não pode editar só consulta (sem marcar, editar ou excluir).
  final bool somenteLeitura;

  const CompromissoTile({
    super.key,
    required this.banco,
    required this.compromisso,
    required this.dia,
    required this.aoMudar,
    this.mostrarData = true,
    this.somenteLeitura = false,
  });

  bool get _lembrete => compromisso.tipo == 'lembrete';

  static IconData _icone(String categoria) {
    switch (categoria) {
      case 'ensaio':
        return Icons.music_note;
      case 'reuniao':
        return Icons.groups;
      case 'versiculo':
        return Icons.menu_book;
      default:
        return Icons.event;
    }
  }

  void _concluir() {
    final c = compromisso;
    if (c.repete != 'nao') {
      // Lembrete que se repete: concluir adianta para a próxima ocorrência.
      final prox = c.proxima(soData(dia).add(const Duration(days: 1)));
      if (prox != null) c.data = isoData(prox);
    } else {
      c.feito = !c.feito;
    }
    aoMudar();
  }

  void _detalhes(BuildContext context) {
    final c = compromisso;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(c.titulo),
        content: SingleChildScrollView(
          child: SelectableText([
            dataBr(soData(dia)) + (c.horaTexto.isEmpty ? '' : ' · ${c.horaTexto}'),
            if (c.local.isNotEmpty) 'Local: ${c.local}',
            if (c.categoria != 'outro') kCategoriasEvento[c.categoria] ?? '',
            if (c.descricao.isNotEmpty) '\n${c.descricao}',
          ].join('\n')),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
        ],
      ),
    );
  }

  Future<void> _editar(BuildContext context) async {
    final novo = await formCompromisso(context, tipo: compromisso.tipo, existente: compromisso);
    if (novo == null) return;
    final i = banco.compromissos.indexWhere((c) => c.id == novo.id);
    if (i >= 0) banco.compromissos[i] = novo;
    aoMudar();
  }

  Future<void> _excluir(BuildContext context) async {
    final ok = await confirmar(
      context,
      titulo: _lembrete ? 'Excluir lembrete?' : 'Excluir evento?',
      mensagem: compromisso.repete == 'nao'
          ? '"${compromisso.titulo}" será apagado.'
          : '"${compromisso.titulo}" será apagado, inclusive todas as repetições.',
    );
    if (!ok) return;
    banco.compromissos.removeWhere((c) => c.id == compromisso.id);
    aoMudar();
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final c = compromisso;
    final base = c.dataBase;
    final atrasado = _lembrete &&
        !c.feito &&
        c.repete == 'nao' &&
        base != null &&
        base.isBefore(soData(DateTime.now()));

    final partes = <String>[
      if (mostrarData) dataBr(soData(dia)),
      if (c.horaTexto.isNotEmpty) c.horaTexto,
      if (c.local.isNotEmpty) c.local,
      if (c.repete != 'nao') kRepeticoes[c.repete] ?? '',
    ];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: atrasado ? Colors.red : esquema.outlineVariant),
      ),
      child: ListTile(
        dense: true,
        onTap: () => somenteLeitura ? _detalhes(context) : _editar(context),
        leading: _lembrete
            ? Checkbox(value: c.feito, onChanged: somenteLeitura ? null : (_) => _concluir())
            : Icon(_icone(c.categoria), color: esquema.primary),
        title: Text(
          c.titulo,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            decoration: c.feito ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: (partes.isEmpty && !atrasado && c.descricao.isEmpty)
            ? null
            : Text(
                [
                  if (partes.isNotEmpty) partes.join(' · '),
                  if (atrasado) 'ATRASADO',
                  if (c.descricao.isNotEmpty) c.descricao,
                ].join('\n'),
                style: TextStyle(fontSize: 12, color: atrasado ? Colors.red : null),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: somenteLeitura
            ? null
            : PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'editar') _editar(context);
                  if (v == 'excluir') _excluir(context);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'editar', child: Text('Editar')),
                  PopupMenuItem(value: 'excluir', child: Text('Excluir')),
                ],
              ),
      ),
    );
  }
}
