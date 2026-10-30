import 'package:flutter/material.dart';

import '../models.dart';
import 'membro_widgets.dart';

/// Ficha do membro somente para leitura (usada por quem não pode editar).
Future<void> mostrarFichaMembro(BuildContext context, Banco banco, Entidade m) {
  final cong = banco.congregacaoPorId(m.congregacaoId);
  final classe = banco.classePorId(m.classe);
  final nasc = m.dataNascimento;

  final linhas = <MapEntry<String, String>>[
    MapEntry('Congregação', cong?.nome ?? '-'),
    MapEntry('Classe (EBD)', classe?.nome ?? '-'),
    MapEntry('Nascimento', nasc == null ? '-' : dataBr(nasc)),
    MapEntry('Idade', m.idadeExibida.isEmpty ? '-' : '${m.idadeExibida} anos'),
    MapEntry('Sexo', m.sexo),
    MapEntry('Tipo sanguíneo', m.tipoSanguineo),
    MapEntry('CPF', m.cpf.isEmpty ? '-' : m.cpf),
    MapEntry('RG', m.rg.isEmpty ? '-' : m.rg),
    MapEntry('Telefone', m.telefone.isEmpty ? '-' : m.telefone),
    MapEntry('Celular', m.celular.isEmpty ? '-' : m.celular),
    MapEntry('E-mail', m.email.isEmpty ? '-' : m.email),
    for (final c in banco.colunas)
      MapEntry(c.nome, c.exibir(m.valoresAtributosDinamicos[c.id]).isEmpty
          ? '-'
          : c.exibir(m.valoresAtributosDinamicos[c.id])),
    if (m.requerAssinatura)
      MapEntry('Assinatura',
          '${m.assinaturaNome.isEmpty ? m.nome : m.assinaturaNome}${m.assinaturaCargo.isEmpty ? '' : ' · ${m.assinaturaCargo}'}'),
    if (!m.ativo)
      MapEntry('Situação',
          'Desligado${m.dataSaida.isEmpty ? '' : ' em ${m.dataSaida}'}${m.motivoSaida.isEmpty ? '' : ' · ${m.motivoSaida}'}'),
  ];

  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final e = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Row(
          children: [
            avatarMembro(m, 24, borda: banco.corDaCongregacao(m, e.primary)),
            const SizedBox(width: 12),
            Expanded(child: Text(m.nome, style: const TextStyle(fontSize: 18))),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final l in linhas)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(l.key,
                              style: TextStyle(fontSize: 12, color: e.onSurfaceVariant)),
                        ),
                        Expanded(child: SelectableText(l.value, style: const TextStyle(fontSize: 14))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
        ],
      );
    },
  );
}
