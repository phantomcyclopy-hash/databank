import 'package:flutter/material.dart';

import '../calendario.dart';
import '../models.dart';
import 'seletor_data.dart';

class SaidaInfo {
  final DateTime data;
  final String motivo;
  SaidaInfo(this.data, this.motivo);
}

const List<String> kMotivosSaida = [
  'Transferência',
  'Mudança de cidade',
  'Falecimento',
  'Desligamento a pedido',
  'Disciplina',
  'Outro',
];

/// Pergunta data e motivo do desligamento de [membro]. Null se cancelado.
Future<SaidaInfo?> pedirDesligamento(BuildContext context, Entidade membro) {
  DateTime? data = soData(DateTime.now());
  var motivo = kMotivosSaida.first;
  final detalheCtrl = TextEditingController();
  var erroData = false;

  return showDialog<SaidaInfo>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text('Desligar ${membro.nome}?'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'O membro continua no cadastro (pode ser reativado), mas sai das listas e das contagens. A saída entra automaticamente na ata do mês.',
                  style: TextStyle(fontSize: 12),
                ),
                SeletorData(rotulo: 'Data da saída', inicial: data, onChanged: (d) => data = d),
                if (erroData)
                  const Text('Informe uma data válida',
                      style: TextStyle(fontSize: 12, color: Colors.red)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: motivo,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Motivo'),
                  items: kMotivosSaida
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) => setD(() => motivo = v ?? motivo),
                ),
                TextField(
                  controller: detalheCtrl,
                  decoration: const InputDecoration(labelText: 'Detalhes (opcional)'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (data == null) {
                setD(() => erroData = true);
                return;
              }
              final det = detalheCtrl.text.trim();
              Navigator.pop(ctx, SaidaInfo(data!, det.isEmpty ? motivo : '$motivo: $det'));
            },
            child: const Text('Desligar'),
          ),
        ],
      ),
    ),
  );
}
