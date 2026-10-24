import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import 'membro_widgets.dart';
import 'seletor_data.dart';

/// Formulário de cadastro/edição de membro. Devolve o membro pronto (ou null se
/// cancelado); quem chama grava no banco com [Banco.salvarMembro].
Future<Entidade?> abrirFormularioMembro(
  BuildContext context,
  Banco banco, {
  Entidade? existente,
  String congregacaoInicial = '',
}) async {
  const uuid = Uuid();
  final picker = ImagePicker();

  final nomeCtrl = TextEditingController(text: existente?.nome ?? '');
  final cpfCtrl = TextEditingController(text: existente?.cpf ?? '');
  final rgCtrl = TextEditingController(text: existente?.rg ?? '');
  final idadeCtrl = TextEditingController(text: existente?.idade ?? '');
  final telCtrl = TextEditingController(text: existente?.telefone ?? '');
  final celCtrl = TextEditingController(text: existente?.celular ?? '');
  final emailCtrl = TextEditingController(text: existente?.email ?? '');
  final assinNomeCtrl = TextEditingController(text: existente?.assinaturaNome ?? '');
  final assinCargoCtrl = TextEditingController(text: existente?.assinaturaCargo ?? '');

  var sexoSel = kSexos.contains(existente?.sexo) ? existente!.sexo : 'N/A';
  var sangueSel = kSangues.contains(existente?.tipoSanguineo) ? existente!.tipoSanguineo : 'N/A';
  var congSel = existente?.congregacaoId ?? congregacaoInicial;
  if (banco.congregacaoPorId(congSel) == null) congSel = '';
  String? foto = existente?.fotoBase64;
  var erroNome = false;
  var erroDoc = false;
  DateTime? nasc = existente?.dataNascimento;
  var classeSel = banco.classePorId(existente?.classe ?? '') != null ? existente!.classe : '';
  var requerAssin = existente?.requerAssinatura ?? false;

  final extras = Map<String, String>.from(existente?.valoresAtributosDinamicos ?? {});
  for (final col in banco.colunas) {
    extras.putIfAbsent(col.id, () => col.tipo == 'checkbox' ? 'false' : '');
  }

  final resultado = await showDialog<Entidade>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setF) => AlertDialog(
        title: Text(existente == null ? 'Cadastrar membro' : 'Ficha do membro'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    final img = await picker.pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 70,
                      maxWidth: 600,
                      maxHeight: 600,
                    );
                    if (img != null) {
                      final bytes = await img.readAsBytes();
                      setF(() => foto = base64Encode(bytes));
                    }
                  },
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.blueGrey.shade200,
                    backgroundImage: foto != null ? MemoryImage(base64Decode(foto!)) : null,
                    child: foto == null
                        ? Icon(Icons.add_a_photo, size: 30, color: Colors.blueGrey.shade700)
                        : null,
                  ),
                ),
                if (foto != null)
                  TextButton(
                    onPressed: () => setF(() => foto = null),
                    child: const Text('Remover foto'),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('Toque no círculo para escolher a foto',
                        style: TextStyle(fontSize: 12)),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: nomeCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Nome completo *',
                    errorText: erroNome ? 'Informe o nome' : null,
                  ),
                ),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: cpfCtrl,
                          decoration: InputDecoration(
                              labelText: 'CPF',
                              errorText: erroDoc ? 'Obrigatório (ou RG)' : null))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextField(
                          controller: rgCtrl,
                          decoration: const InputDecoration(labelText: 'RG'))),
                ]),
                SeletorData(
                  rotulo: 'Data de nascimento',
                  inicial: nasc,
                  onChanged: (d) => setF(() => nasc = d),
                ),
                Row(children: [
                  Expanded(
                    child: nasc == null
                        ? TextField(
                            controller: idadeCtrl,
                            decoration: const InputDecoration(labelText: 'Idade'),
                            keyboardType: TextInputType.number,
                          )
                        : InputDecorator(
                            decoration: const InputDecoration(labelText: 'Idade'),
                            child: Text(idadeTexto(nasc!)),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: sexoSel,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Sexo'),
                      items: kSexos.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      onChanged: (v) => setF(() => sexoSel = v!),
                    ),
                  ),
                ]),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: sangueSel,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Tipo sanguíneo'),
                      items: kSangues.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      onChanged: (v) => setF(() => sangueSel = v!),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: congSel,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Congregação'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Sem congregação')),
                        ...banco.todasCongregacoes.map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Row(children: [
                                bolinha(corDeHex(c.cor, padrao: Colors.blue), 12),
                                const SizedBox(width: 8),
                                Flexible(child: Text(c.nome, overflow: TextOverflow.ellipsis)),
                              ]),
                            )),
                      ],
                      onChanged: (v) => setF(() => congSel = v ?? ''),
                    ),
                  ),
                ]),
                DropdownButtonFormField<String>(
                  value: classeSel,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Classe (EBD)'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Sem classe')),
                    ...banco.classes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.nome))),
                  ],
                  onChanged: (v) => setF(() => classeSel = v ?? ''),
                ),
                Row(children: [
                  Expanded(
                      child: TextField(
                    controller: telCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Telefone'),
                  )),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextField(
                    controller: celCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Celular'),
                  )),
                ]),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-mail'),
                ),
                const Divider(height: 24),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Requer assinatura'),
                  subtitle: const Text('Exige CPF ou RG e entra nas listas de assinatura'),
                  value: requerAssin,
                  onChanged: (v) => setF(() {
                    requerAssin = v ?? false;
                    if (!requerAssin) erroDoc = false;
                  }),
                ),
                if (requerAssin) ...[
                  TextField(
                    controller: assinNomeCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nome para assinatura',
                      hintText: 'Se vazio, usa o nome completo',
                    ),
                  ),
                  TextField(
                    controller: assinCargoCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Cargo / função ao assinar',
                      hintText: 'Ex: Secretário, Diácono, Tesoureiro',
                    ),
                  ),
                ],
                if (banco.colunas.isNotEmpty) ...[
                  const Divider(height: 24),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Campos extras', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
                ...banco.colunas.map((col) {
                  if (col.tipo == 'checkbox') {
                    return CheckboxListTile(
                      key: ValueKey(col.id),
                      contentPadding: EdgeInsets.zero,
                      title: Text(col.nome),
                      value: extras[col.id] == 'true',
                      onChanged: (v) => setF(() => extras[col.id] = (v ?? false).toString()),
                    );
                  }
                  return TextFormField(
                    key: ValueKey(col.id),
                    initialValue: extras[col.id] ?? '',
                    keyboardType: col.tipo == 'numero' ? TextInputType.number : TextInputType.text,
                    decoration: InputDecoration(labelText: col.nome),
                    onChanged: (v) => extras[col.id] = v,
                  );
                }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final nome = nomeCtrl.text.trim();
              if (nome.isEmpty) {
                setF(() => erroNome = true);
                return;
              }
              if (requerAssin && cpfCtrl.text.trim().isEmpty && rgCtrl.text.trim().isEmpty) {
                setF(() => erroDoc = true);
                return;
              }
              final agora = DateTime.now().millisecondsSinceEpoch;
              Navigator.pop(
                ctx,
                Entidade(
                  id: existente?.id ?? uuid.v4(),
                  nome: nome,
                  fotoBase64: foto,
                  congregacaoId: congSel,
                  cpf: cpfCtrl.text.trim(),
                  rg: rgCtrl.text.trim(),
                  idade: nasc == null ? idadeCtrl.text.trim() : '',
                  nascimento: nasc == null ? '' : isoData(nasc!),
                  classe: classeSel,
                  requerAssinatura: requerAssin,
                  assinaturaNome: requerAssin ? assinNomeCtrl.text.trim() : '',
                  assinaturaCargo: requerAssin ? assinCargoCtrl.text.trim() : '',
                  sexo: sexoSel,
                  tipoSanguineo: sangueSel,
                  telefone: telCtrl.text.trim(),
                  celular: celCtrl.text.trim(),
                  email: emailCtrl.text.trim(),
                  criadoEm: (existente != null && existente.criadoEm > 0) ? existente.criadoEm : agora,
                  atualizadoEm: agora,
                  valoresAtributosDinamicos: extras,
                ),
              );
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );

  return resultado;
}
