import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../calendario.dart';
import '../models.dart';
import '../widgets/dialogos.dart';
import '../widgets/seletor_data.dart';

/// Cultos fixos da semana (repetem toda semana). Título, horário e cronograma
/// são editáveis e aparecem no topo do Mural.
class CultosPage extends StatefulWidget {
  final Banco banco;
  final VoidCallback onSalvar;

  const CultosPage({super.key, required this.banco, required this.onSalvar});

  @override
  State<CultosPage> createState() => _CultosPageState();
}

class _CultosPageState extends State<CultosPage> {
  static const Uuid _uuid = Uuid();

  Banco get _banco => widget.banco;

  Future<void> _form({Culto? existente}) async {
    var dia = existente?.diaSemana ?? DateTime.sunday;
    final tituloCtrl = TextEditingController(text: existente?.titulo ?? '');
    final cronoCtrl = TextEditingController(text: existente?.cronograma ?? '');
    var temHora = (existente?.hora ?? -1) >= 0;
    var hora = (existente?.hora ?? -1) >= 0 ? existente!.hora : 19 * 60;
    var erro = false;

    final r = await showDialog<Culto>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(existente == null ? 'Novo culto' : 'Editar culto'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: dia,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Dia da semana (todas as semanas)'),
                    items: [
                      for (var i = 1; i <= 7; i++)
                        DropdownMenuItem(value: i, child: Text(kDiasSemana[i - 1])),
                    ],
                    onChanged: (v) => setD(() => dia = v ?? dia),
                  ),
                  TextField(
                    controller: tituloCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Título *',
                      hintText: 'Ex: Culto de Doutrina',
                      errorText: erro ? 'Informe o título' : null,
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Definir horário'),
                    value: temHora,
                    onChanged: (v) => setD(() => temHora = v),
                  ),
                  if (temHora)
                    SeletorHora(rotulo: 'Horário', minutos: hora, onChanged: (m) => hora = m),
                  const SizedBox(height: 8),
                  TextField(
                    controller: cronoCtrl,
                    minLines: 4,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      labelText: 'Cronograma',
                      hintText: '19:00 Abertura\n19:10 Louvor\n19:40 Palavra',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (tituloCtrl.text.trim().isEmpty) {
                  setD(() => erro = true);
                  return;
                }
                Navigator.pop(
                  ctx,
                  Culto(
                    id: existente?.id ?? _uuid.v4(),
                    diaSemana: dia,
                    titulo: tituloCtrl.text.trim(),
                    hora: temHora ? hora : -1,
                    cronograma: cronoCtrl.text.trim(),
                  ),
                );
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (r == null) return;
    setState(() {
      final i = _banco.cultos.indexWhere((c) => c.id == r.id);
      if (i >= 0) {
        _banco.cultos[i] = r;
      } else {
        _banco.cultos.add(r);
      }
    });
    widget.onSalvar();
  }

  Future<void> _excluir(Culto c) async {
    final ok = await confirmar(
      context,
      titulo: 'Excluir culto?',
      mensagem: '"${c.titulo}" deixará de aparecer em todas as semanas.',
    );
    if (!ok) return;
    setState(() => _banco.cultos.removeWhere((x) => x.id == c.id));
    widget.onSalvar();
  }

  @override
  Widget build(BuildContext context) {
    final e = Theme.of(context).colorScheme;
    final cultos = [..._banco.cultos]..sort((a, b) {
        final d = a.diaSemana.compareTo(b.diaSemana);
        return d != 0 ? d : (a.hora < 0 ? 9999 : a.hora).compareTo(b.hora < 0 ? 9999 : b.hora);
      });

    return Scaffold(
      appBar: AppBar(title: const Text('Cultos da semana')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              'Os cultos se repetem toda semana e aparecem no topo do Mural. Edite o título e o cronograma quando precisar.',
              style: TextStyle(fontSize: 12, color: e.onSurfaceVariant),
            ),
          ),
          if (cultos.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Nenhum culto cadastrado.\nToque em "Novo culto".', textAlign: TextAlign.center)),
            ),
          ...cultos.map((c) => Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: e.outlineVariant),
                ),
                child: ListTile(
                  onTap: () => _form(existente: c),
                  leading: Icon(Icons.church_outlined, color: e.primary),
                  title: Text(c.titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${kDiasSemana[c.diaSemana - 1]}${c.horaTexto.isEmpty ? '' : ' · ${c.horaTexto}'}'
                    '${c.cronograma.isEmpty ? '' : '\n${c.cronograma}'}',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  isThreeLine: c.cronograma.isNotEmpty,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'Excluir',
                    onPressed: () => _excluir(c),
                  ),
                ),
              )),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _form(),
        icon: const Icon(Icons.add),
        label: const Text('Novo culto'),
      ),
    );
  }
}
