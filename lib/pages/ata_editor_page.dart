import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../calendario.dart';
import '../leitor_documentos.dart';
import '../models.dart';
import '../nuvem/sync_service.dart';
import '../publicacao_util.dart';
import '../widgets/dialogos.dart';
import '../widgets/publicar_dialog.dart';
import '../widgets/seletor_data.dart';
import 'opcoes_impressao_page.dart';

/// Editor da ata: dados, movimento de membros (automático), registros e
/// anotações (bloco de notas). Salva sozinho enquanto você escreve.
class AtaEditorPage extends StatefulWidget {
  final Banco banco;
  final Ata ata;
  final VoidCallback onSalvar;

  const AtaEditorPage({
    super.key,
    required this.banco,
    required this.ata,
    required this.onSalvar,
  });

  @override
  State<AtaEditorPage> createState() => _AtaEditorPageState();
}

class _AtaEditorPageState extends State<AtaEditorPage> {
  static const Uuid _uuid = Uuid();

  late final TextEditingController _tituloCtrl;
  late final TextEditingController _textoCtrl;
  Timer? _deb;

  Banco get _banco => widget.banco;
  Ata get _ata => widget.ata;
  bool get _ordinaria => _ata.tipo == 'ordinaria';

  /// Inspetor e membro só leem: campos travados e sem botões de alteração.
  bool get _ro => !Sync.instance.podeEditar;

  @override
  void initState() {
    super.initState();
    _tituloCtrl = TextEditingController(text: _ata.titulo);
    _textoCtrl = TextEditingController(text: _ata.texto);
  }

  @override
  void dispose() {
    _deb?.cancel();
    _aplicarCampos();
    _tituloCtrl.dispose();
    _textoCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _aplicarCampos() {
    if (_ro) return;
    final t = _tituloCtrl.text.trim();
    if (t.isNotEmpty) _ata.titulo = t;
    _ata.texto = _textoCtrl.text;
    _ata.atualizadoEm = DateTime.now().millisecondsSinceEpoch;
  }

  /// Salva depois de uma pequena pausa na digitação.
  void _agendar() {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 700), () {
      _aplicarCampos();
      widget.onSalvar();
    });
  }

  void _salvarAgora() {
    _deb?.cancel();
    _aplicarCampos();
    widget.onSalvar();
  }

  // ------------------------------------------------------------- formatação

  void _prefixo(String p) {
    final t = _textoCtrl.text;
    final sel = _textoCtrl.selection;
    final pos = sel.isValid ? sel.start : t.length;
    final ini = pos <= 0 ? 0 : t.lastIndexOf('\n', pos - 1) + 1;
    _textoCtrl.value = TextEditingValue(
      text: t.substring(0, ini) + p + t.substring(ini),
      selection: TextSelection.collapsed(offset: pos + p.length),
    );
    _agendar();
  }

  void _negrito() {
    final t = _textoCtrl.text;
    final sel = _textoCtrl.selection;
    if (!sel.isValid) return;
    final a = sel.start;
    final b = sel.end;
    if (a == b) {
      _textoCtrl.value = TextEditingValue(
        text: '${t.substring(0, a)}****${t.substring(a)}',
        selection: TextSelection.collapsed(offset: a + 2),
      );
    } else {
      _textoCtrl.value = TextEditingValue(
        text: '${t.substring(0, a)}**${t.substring(a, b)}**${t.substring(b)}',
        selection: TextSelection(baseOffset: a + 2, extentOffset: b + 2),
      );
    }
    _agendar();
  }

  // ---------------------------------------------------------------- registros

  Future<void> _registro({RegistroAta? existente}) async {
    DateTime? data = parseNascimento(existente?.data ?? '') ?? soData(DateTime.now());
    var cat = existente?.categoria ?? 'acontecimento';
    final textoCtrl = TextEditingController(text: existente?.texto ?? '');
    var erro = false;

    final r = await showDialog<RegistroAta>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(existente == null ? 'Novo registro' : 'Editar registro'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: cat,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Categoria'),
                    items: kCategoriasRegistro.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setD(() => cat = v ?? cat),
                  ),
                  SeletorData(rotulo: 'Data', inicial: data, onChanged: (d) => data = d),
                  const SizedBox(height: 6),
                  TextField(
                    controller: textoCtrl,
                    minLines: 3,
                    maxLines: 8,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'O que aconteceu *',
                      errorText: erro ? 'Escreva o registro' : null,
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
                if (textoCtrl.text.trim().isEmpty) {
                  setD(() => erro = true);
                  return;
                }
                Navigator.pop(
                  ctx,
                  RegistroAta(
                    id: existente?.id ?? _uuid.v4(),
                    data: data == null ? '' : isoData(data!),
                    categoria: cat,
                    texto: textoCtrl.text.trim(),
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
      final i = _ata.registros.indexWhere((x) => x.id == r.id);
      if (i >= 0) {
        _ata.registros[i] = r;
      } else {
        _ata.registros.add(r);
      }
    });
    _salvarAgora();
  }

  Future<void> _excluirRegistro(RegistroAta r) async {
    final ok = await confirmar(context,
        titulo: 'Excluir registro?', mensagem: 'O registro será apagado desta ata.');
    if (!ok) return;
    setState(() => _ata.registros.removeWhere((x) => x.id == r.id));
    _salvarAgora();
  }

  // -------------------------------------------------------------------- ações

  Future<void> _importar() async {
    try {
      final r = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['docx', 'pdf', 'txt'],
        withData: true,
      );
      if (r == null) return;
      final arq = r.files.single;
      if (arq.bytes == null) {
        _snack('Não foi possível ler o arquivo.');
        return;
      }
      final texto = extrairTexto(arq.name, arq.bytes!);
      setState(() {
        _textoCtrl.text = _textoCtrl.text.trim().isEmpty ? texto : '${_textoCtrl.text}\n\n$texto';
      });
      _salvarAgora();
      _snack('Texto importado (${texto.length} caracteres) e adicionado às anotações.');
    } on LeituraException catch (e) {
      _snack(e.mensagem);
    } catch (e) {
      _snack('Erro ao importar: $e');
    }
  }

  void _gerarPdf() {
    _salvarAgora();
    imprimirComOpcoes(
      context,
      banco: _banco,
      membros: const [],
      tituloInicial: _ata.titulo,
      ata: _ata,
      aviso: _snack,
    );
  }

  Future<void> _excluirAta() async {
    final ok = await confirmar(
      context,
      titulo: 'Excluir ata?',
      mensagem: 'A ata "${_ata.titulo}" e todos os seus registros serão apagados. Esta ação não pode ser desfeita.',
    );
    if (!ok) return;
    _deb?.cancel();
    _banco.atas.removeWhere((x) => x.id == _ata.id);
    widget.onSalvar();
    if (mounted) Navigator.pop(context);
  }

  // ------------------------------------------------------------------ build

  Widget _secao(String titulo, List<Widget> filhos, {Widget? acao, String? ajuda}) {
    final e = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: e.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(titulo,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                if (acao != null && !_ro) acao,
              ],
            ),
            if (ajuda != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(ajuda, style: TextStyle(fontSize: 12, color: e.onSurfaceVariant)),
              ),
            const SizedBox(height: 8),
            IgnorePointer(
              ignoring: _ro,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: filhos),
            ),
          ],
        ),
      ),
    );
  }

  Widget _botaoFormato(IconData icone, String dica, VoidCallback f) => IconButton(
        tooltip: dica,
        icon: Icon(icone),
        onPressed: f,
      );

  @override
  Widget build(BuildContext context) {
    final e = Theme.of(context).colorScheme;
    final mv = _banco.movimentosDaAta(_ata);
    final entradas = mv.where((m) => m.tipo == 'entrada').toList();
    final saidas = mv.where((m) => m.tipo == 'saida').toList();
    final registros = [..._ata.registros]..sort((a, b) => a.data.compareTo(b.data));
    final quemAssina = _banco.ativos.where((m) => m.requerAssinatura).length;

    String ddmm(String iso) {
      final d = parseNascimento(iso);
      return d == null ? '-' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_ordinaria ? 'Ata ordinária' : 'Ata extraordinária'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Gerar PDF',
            onPressed: _gerarPdf,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'importar') _importar();
              if (v == 'pdf') _gerarPdf();
              if (v == 'publicar') {
                _salvarAgora();
                publicarNoMural(
                  context,
                  _banco,
                  tipo: 'ata',
                  titulo: _ata.titulo,
                  texto: textoDaAta(_banco, _ata),
                  onSalvar: widget.onSalvar,
                );
              }
              if (v == 'excluir') _excluirAta();
            },
            itemBuilder: (_) => [
              if (!_ro)
                const PopupMenuItem(
                    value: 'importar', child: Text('Importar arquivo (Word, PDF, TXT)')),
              const PopupMenuItem(value: 'pdf', child: Text('Gerar PDF / opções de impressão')),
              if (!_ro) const PopupMenuItem(value: 'publicar', child: Text('Publicar no Mural')),
              if (!_ro) const PopupMenuItem(value: 'excluir', child: Text('Excluir ata')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 32),
        children: [
          // ---------------------------------------------------------- dados
          _secao('Dados da ata', [
            TextField(
              controller: _tituloCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Título'),
              onChanged: (_) => _agendar(),
            ),
            SeletorData(
              rotulo: _ordinaria ? 'Data da reunião (opcional)' : 'Data da reunião',
              inicial: parseNascimento(_ata.data),
              onChanged: (d) {
                _ata.data = d == null ? '' : isoData(d);
                _agendar();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Definir hora da reunião'),
              value: _ata.hora >= 0,
              onChanged: (v) => setState(() {
                _ata.hora = v ? (DateTime.now().hour * 60 + DateTime.now().minute) : -1;
                _agendar();
              }),
            ),
            if (_ata.hora >= 0)
              SeletorHora(
                rotulo: 'Hora',
                minutos: _ata.hora,
                onChanged: (m) {
                  _ata.hora = m;
                  _agendar();
                },
              ),
          ]),

          // ----------------------------------------------- movimento de membros
          _secao(
            'Movimento de membros',
            [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Incluir entradas e saídas no documento'),
                subtitle: Text(_ordinaria
                    ? 'Automático: tudo o que acontecer no mês entra aqui'
                    : 'Escolha o período abaixo'),
                value: _ata.incluirMovimentos,
                onChanged: (v) => setState(() {
                  _ata.incluirMovimentos = v;
                  _agendar();
                }),
              ),
              if (_ata.incluirMovimentos && !_ordinaria) ...[
                SeletorData(
                  rotulo: 'Período: de',
                  inicial: parseNascimento(_ata.periodoIni),
                  onChanged: (d) {
                    _ata.periodoIni = d == null ? '' : isoData(d);
                    setState(() {});
                    _agendar();
                  },
                ),
                SeletorData(
                  rotulo: 'até',
                  inicial: parseNascimento(_ata.periodoFim),
                  onChanged: (d) {
                    _ata.periodoFim = d == null ? '' : isoData(d);
                    setState(() {});
                    _agendar();
                  },
                ),
              ],
              if (_ata.incluirMovimentos) ...[
                const SizedBox(height: 8),
                if (mv.isEmpty)
                  Text('Nenhuma entrada ou saída no período.',
                      style: TextStyle(color: e.onSurfaceVariant)),
                if (entradas.isNotEmpty) ...[
                  Text('Entradas (${entradas.length})',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  ...entradas.map((m) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.login, color: Colors.green),
                        title: Text(m.nome),
                        subtitle: Text('${ddmm(m.data)}${m.motivo.isEmpty ? '' : ' · ${m.motivo}'}'),
                      )),
                ],
                if (saidas.isNotEmpty) ...[
                  Text('Saídas (${saidas.length})',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  ...saidas.map((m) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.logout, color: Colors.red),
                        title: Text(m.nome),
                        subtitle: Text('${ddmm(m.data)}${m.motivo.isEmpty ? '' : ' · ${m.motivo}'}'),
                      )),
                ],
              ],
            ],
            ajuda:
                'Entradas vêm de novos cadastros; saídas, de "Desligar membro" na área Membros.',
          ),

          // -------------------------------------------------------- registros
          _secao(
            _ordinaria ? 'Registros do mês' : 'Registros',
            [
              if (registros.isEmpty)
                Text('Nenhum registro ainda.', style: TextStyle(color: e.onSurfaceVariant)),
              ...registros.map((r) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onTap: () => _registro(existente: r),
                    title: Text(r.texto, maxLines: 3, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${ddmm(r.data)} · ${kCategoriasRegistro[r.categoria] ?? r.categoria}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: 'Excluir registro',
                      onPressed: () => _excluirRegistro(r),
                    ),
                  )),
            ],
            acao: TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Adicionar'),
              onPressed: () => _registro(),
            ),
            ajuda: _ordinaria
                ? 'Vá acrescentando durante o mês: acontecimentos, eventos, posicionamentos, feitos.'
                : null,
          ),

          // ------------------------------------------------------- anotações
          _secao('Anotações', [
            Wrap(
              children: [
                _botaoFormato(Icons.title, 'Título', () => _prefixo('# ')),
                _botaoFormato(Icons.text_fields, 'Subtítulo', () => _prefixo('## ')),
                _botaoFormato(Icons.format_list_bulleted, 'Item de lista', () => _prefixo('- ')),
                _botaoFormato(Icons.format_bold, 'Negrito', _negrito),
                _botaoFormato(Icons.upload_file, 'Importar arquivo', _importar),
              ],
            ),
            TextField(
              controller: _textoCtrl,
              minLines: 10,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Escreva aqui. Use os botões para título, lista e negrito.',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _agendar(),
            ),
          ]),

          // ------------------------------------------------------ assinaturas
          _secao('Assinaturas', [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Incluir assinaturas dos membros'),
              subtitle: Text('$quemAssina membro(s) marcado(s) como "requer assinatura"'),
              value: _ata.assinaturasMembros,
              onChanged: (v) => setState(() {
                _ata.assinaturasMembros = v;
                _agendar();
              }),
            ),
            Text(
              'A assinatura do pastor presidente, o título em todas as folhas, a logo, as margens e a capa são ligados em "Gerar PDF".',
              style: TextStyle(fontSize: 12, color: e.onSurfaceVariant),
            ),
          ]),
        ],
      ),
    );
  }
}
