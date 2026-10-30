import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../calendario.dart';
import '../models.dart';
import 'seletor_data.dart';

const Map<String, String> kRepeticoes = {
  'nao': 'Não repete',
  'diario': 'Todo dia',
  'semanal': 'Toda semana',
  'mensal': 'Todo mês',
  'anual': 'Todo ano',
};

/// Cria ou edita um aviso. Devolve o aviso pronto (ou null se cancelado).
Future<Aviso?> formAviso(BuildContext context, {Aviso? existente}) {
  const uuid = Uuid();
  final tituloCtrl = TextEditingController(text: existente?.titulo ?? '');
  final textoCtrl = TextEditingController(text: existente?.texto ?? '');
  var fixado = existente?.fixado ?? false;
  DateTime? expiraData = parseNascimento(existente?.expiraEm ?? '');
  var expira = expiraData != null;
  var erro = false;

  return showDialog<Aviso>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setF) => AlertDialog(
        title: Text(existente == null ? 'Novo aviso' : 'Editar aviso'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: tituloCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Título *',
                    errorText: erro ? 'Informe o título' : null,
                  ),
                ),
                TextField(
                  controller: textoCtrl,
                  minLines: 3,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Texto do aviso'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fixar no topo do Mural'),
                  value: fixado,
                  onChanged: (v) => setF(() => fixado = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Expira em uma data'),
                  subtitle: const Text('Depois dela o aviso some do Mural'),
                  value: expira,
                  onChanged: (v) => setF(() {
                    expira = v;
                    if (v && expiraData == null) expiraData = soData(DateTime.now());
                  }),
                ),
                if (expira)
                  SeletorData(
                    rotulo: 'Expira em',
                    inicial: expiraData,
                    onChanged: (d) => expiraData = d,
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
                setF(() => erro = true);
                return;
              }
              Navigator.pop(
                ctx,
                Aviso(
                  id: existente?.id ?? uuid.v4(),
                  titulo: tituloCtrl.text.trim(),
                  texto: textoCtrl.text.trim(),
                  criadoEm: existente?.criadoEm ?? DateTime.now().millisecondsSinceEpoch,
                  fixado: fixado,
                  expiraEm: expira && expiraData != null ? isoData(expiraData!) : '',
                ),
              );
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );
}

/// Cria ou edita um lembrete ('lembrete') ou evento ('evento') da agenda.
Future<Compromisso?> formCompromisso(
  BuildContext context, {
  required String tipo,
  Compromisso? existente,
  DateTime? dataInicial,
}) {
  const uuid = Uuid();
  final ehEvento = (existente?.tipo ?? tipo) == 'evento';
  final tituloCtrl = TextEditingController(text: existente?.titulo ?? '');
  final descCtrl = TextEditingController(text: existente?.descricao ?? '');
  final localCtrl = TextEditingController(text: existente?.local ?? '');
  DateTime? data = existente?.dataBase ?? soData(dataInicial ?? DateTime.now());
  var temHora = (existente?.hora ?? -1) >= 0;
  var hora = (existente?.hora ?? -1) >= 0 ? existente!.hora : 19 * 60;
  var repete = existente?.repete ?? 'nao';
  var categoria = existente?.categoria ?? 'outro';
  var erroTitulo = false;
  var erroData = false;

  return showDialog<Compromisso>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setF) => AlertDialog(
        title: Text(existente == null
            ? (ehEvento ? 'Novo evento' : 'Novo lembrete')
            : (ehEvento ? 'Editar evento' : 'Editar lembrete')),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: tituloCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Título *',
                    errorText: erroTitulo ? 'Informe o título' : null,
                  ),
                ),
                if (ehEvento)
                  DropdownButtonFormField<String>(
                    value: categoria,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Tipo de evento'),
                    items: kCategoriasEvento.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setF(() => categoria = v ?? 'outro'),
                  ),
                if (ehEvento && categoria == 'versiculo')
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Título = a referência (ex.: Salmos 23:1). Detalhes = o texto do versículo. Aparece no Mural no dia escolhido.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                if (ehEvento && categoria != 'versiculo')
                  TextField(
                    controller: localCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Local'),
                  ),
                TextField(
                  controller: descCtrl,
                  minLines: 2,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Detalhes'),
                ),
                SeletorData(
                  rotulo: 'Data *',
                  inicial: data,
                  onChanged: (d) => data = d,
                ),
                if (erroData)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Informe uma data válida',
                        style: TextStyle(fontSize: 12, color: Colors.red)),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Definir hora'),
                  value: temHora,
                  onChanged: (v) => setF(() => temHora = v),
                ),
                if (temHora)
                  SeletorHora(rotulo: 'Hora', minutos: hora, onChanged: (m) => hora = m),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: repete,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Repetição'),
                  items: kRepeticoes.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setF(() => repete = v ?? 'nao'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final semTitulo = tituloCtrl.text.trim().isEmpty;
              final semData = data == null;
              if (semTitulo || semData) {
                setF(() {
                  erroTitulo = semTitulo;
                  erroData = semData;
                });
                return;
              }
              Navigator.pop(
                ctx,
                Compromisso(
                  id: existente?.id ?? uuid.v4(),
                  tipo: ehEvento ? 'evento' : 'lembrete',
                  titulo: tituloCtrl.text.trim(),
                  descricao: descCtrl.text.trim(),
                  local: ehEvento ? localCtrl.text.trim() : '',
                  data: isoData(data!),
                  hora: temHora ? hora : -1,
                  feito: existente?.feito ?? false,
                  repete: repete,
                  categoria: ehEvento ? categoria : 'outro',
                ),
              );
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );
}

/// Edita o "Fale conosco" (telefone, e-mail e endereço). Null se cancelado.
Future<Contato?> formContato(BuildContext context, Contato atual) {
  final tel = TextEditingController(text: atual.telefone);
  final mail = TextEditingController(text: atual.email);
  final end = TextEditingController(text: atual.endereco);

  return showDialog<Contato>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Fale conosco'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Preencha só o que quiser mostrar. Aparece no fim do Mural para todos.',
                style: TextStyle(fontSize: 12),
              ),
              TextField(
                controller: tel,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Telefone / WhatsApp'),
              ),
              TextField(
                controller: mail,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail'),
              ),
              TextField(
                controller: end,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Endereço'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(
            ctx,
            Contato(telefone: tel.text.trim(), email: mail.text.trim(), endereco: end.text.trim()),
          ),
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
}

/// Cria ou edita uma data comemorativa da igreja.
Future<DataIgreja?> formDataIgreja(BuildContext context, {DataIgreja? existente}) {
  const uuid = Uuid();
  final tituloCtrl = TextEditingController(text: existente?.titulo ?? '');
  final hoje = DateTime.now();
  DateTime? data = existente == null
      ? soData(hoje)
      : parseNascimento(
          '${existente.ano == 0 ? hoje.year : existente.ano}-${existente.mes}-${existente.dia}');
  var todoAno = existente == null ? true : existente.ano == 0;
  var erroTitulo = false;
  var erroData = false;

  return showDialog<DataIgreja>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setF) => AlertDialog(
        title: Text(existente == null ? 'Nova data comemorativa' : 'Editar data'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: tituloCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Nome da data *',
                    hintText: 'Ex: Aniversário da igreja',
                    errorText: erroTitulo ? 'Informe o nome' : null,
                  ),
                ),
                SeletorData(rotulo: 'Data *', inicial: data, onChanged: (d) => data = d),
                if (erroData)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Informe uma data válida',
                        style: TextStyle(fontSize: 12, color: Colors.red)),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Repetir todo ano'),
                  subtitle: const Text('Desligado = vale só para o ano da data'),
                  value: todoAno,
                  onChanged: (v) => setF(() => todoAno = v),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final semTitulo = tituloCtrl.text.trim().isEmpty;
              final semData = data == null;
              if (semTitulo || semData) {
                setF(() {
                  erroTitulo = semTitulo;
                  erroData = semData;
                });
                return;
              }
              Navigator.pop(
                ctx,
                DataIgreja(
                  id: existente?.id ?? uuid.v4(),
                  titulo: tituloCtrl.text.trim(),
                  dia: data!.day,
                  mes: data!.month,
                  ano: todoAno ? 0 : data!.year,
                ),
              );
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );
}
