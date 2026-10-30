import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../importador.dart';
import '../models.dart';
import '../nuvem/sync_service.dart';
import '../publicacao_util.dart';
import '../widgets/dialogos.dart';
import '../widgets/publicar_dialog.dart';
import '../widgets/seletor_cor.dart';
import '../widgets/seletor_data.dart';
import 'lista_detalhes_page.dart';

/// Listas (listas de presença, ceias, eventos...). Cada lista só REFERENCIA membros
/// do cadastro geral; apagar uma lista nunca apaga membros.
class ListasPage extends StatefulWidget {
  final Banco banco;
  final VoidCallback onSalvar;
  final VoidCallback onAparencia;

  const ListasPage({
    super.key,
    required this.banco,
    required this.onSalvar,
    required this.onAparencia,
  });

  @override
  State<ListasPage> createState() => _ListasPageState();
}

class _ListasPageState extends State<ListasPage> {
  final Uuid _uuid = const Uuid();

  Banco get _banco => widget.banco;

  // ---------------------------------------------------- filtro e multiseleção
  String _busca = '';
  final Set<String> _tipos = {}; // padrao | aniversariantes | classes
  bool _modoSel = false;
  final Set<String> _sel = {};

  List<ListaEntidades> _filtradas() {
    final q = normalizarTexto(_busca);
    return _banco.listas.where((l) {
      if (_tipos.isNotEmpty && !_tipos.contains(l.tipo)) return false;
      if (q.isNotEmpty && !normalizarTexto(l.titulo).contains(q)) return false;
      return true;
    }).toList();
  }

  void _entrarSelecao([ListaEntidades? l]) => setState(() {
        _modoSel = true;
        if (l != null) _sel.add(l.id);
      });

  void _sairSelecao() => setState(() {
        _modoSel = false;
        _sel.clear();
      });

  void _alternar(ListaEntidades l) => setState(() {
        _sel.contains(l.id) ? _sel.remove(l.id) : _sel.add(l.id);
      });

  void _selecionarExibidas(List<ListaEntidades> exibidas) => setState(() {
        final todas = exibidas.every((l) => _sel.contains(l.id));
        for (final l in exibidas) {
          todas ? _sel.remove(l.id) : _sel.add(l.id);
        }
      });

  List<ListaEntidades> _selecionadas() =>
      _banco.listas.where((l) => _sel.contains(l.id)).toList();

  Future<void> _excluirSelecionadas() async {
    final alvo = _selecionadas();
    if (alvo.isEmpty) return;
    final ok = await confirmar(
      context,
      titulo: 'Excluir ${alvo.length} lista(s)?',
      mensagem:
          'As listas selecionadas serão apagadas. Nenhum membro é excluído: todos continuam cadastrados na área Membros. Esta ação não pode ser desfeita.',
    );
    if (!ok) return;
    _banco.listas.removeWhere((l) => _sel.contains(l.id));
    _sairSelecao();
    widget.onSalvar();
    _snack('${alvo.length} lista(s) excluída(s).');
  }

  void _bloquearSelecionadas(bool bloquear) {
    final alvo = _selecionadas();
    for (final l in alvo) {
      l.isLocked = bloquear;
    }
    _sairSelecao();
    widget.onSalvar();
    _snack('${alvo.length} lista(s) ${bloquear ? 'bloqueada(s)' : 'desbloqueada(s)'}.');
  }

  void _exportarSelecionada() {
    final alvo = _selecionadas();
    if (alvo.length != 1) {
      _snack('Selecione apenas uma lista para exportar.');
      return;
    }
    final l = alvo.first;
    final json = jsonEncode({
      'tipo': 'ata_ibmmkar', // marcador antigo, mantido para compatibilidade de backups
      'lista': l.toJson(),
      'membros': _banco.membrosDaLista(l).map((m) => m.toJson()).toList(),
      'congregacoes': _banco.congregacoes.map((c) => c.toJson()).toList(),
      'colunas': _banco.colunas.map((c) => c.toJson()).toList(),
      'classes': _banco.classes.map((c) => c.toJson()).toList(),
    });
    mostrarExportacao(context, 'Exportar lista (JSON)', json);
  }

  void _publicar(ListaEntidades l) {
    publicarNoMural(
      context,
      _banco,
      tipo: 'lista',
      titulo: l.titulo,
      texto: textoDaLista(_banco, l),
      onSalvar: widget.onSalvar,
    );
  }

  Widget _cabecalho(ColorScheme esquema, bool vazio) {
    const nomesTipo = {
      'padrao': 'Escolhidas',
      'aniversariantes': 'Aniversários',
      'classes': 'Classes',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Listas de presença, ceias e eventos. Os membros ficam na área Membros; aqui você escolhe quem entra em cada lista.',
            style: TextStyle(fontSize: 12, color: esquema.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          TextField(
            decoration: InputDecoration(
              hintText: 'Buscar lista pelo título',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (v) => setState(() => _busca = v),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: nomesTipo.entries
                .map((e) => FilterChip(
                      label: Text(e.value),
                      selected: _tipos.contains(e.key),
                      onSelected: (v) => setState(() {
                        v ? _tipos.add(e.key) : _tipos.remove(e.key);
                      }),
                    ))
                .toList(),
          ),
          if (_modoSel)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Para selecionar por filtro: busque ou marque um tipo e toque no ícone de selecionar todas.',
                style: TextStyle(fontSize: 12, color: esquema.primary),
              ),
            ),
          if (vazio)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(child: Text('Nenhuma lista encontrada com esses filtros.')),
            ),
        ],
      ),
    );
  }

  AppBar _appBarSelecao(List<ListaEntidades> exibidas) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Sair da seleção',
        onPressed: _sairSelecao,
      ),
      title: Text('${_sel.length} selecionada(s)'),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all),
          tooltip: 'Selecionar / desmarcar todas as exibidas',
          onPressed: () => _selecionarExibidas(exibidas),
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'bloquear':
                _bloquearSelecionadas(true);
                break;
              case 'desbloquear':
                _bloquearSelecionadas(false);
                break;
              case 'exportar':
                _exportarSelecionada();
                break;
              case 'publicar':
                final alvo = _selecionadas();
                if (alvo.length != 1) {
                  _snack('Selecione apenas uma lista para publicar.');
                } else {
                  _publicar(alvo.first);
                }
                break;
              case 'excluir':
                _excluirSelecionadas();
                break;
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'bloquear', child: Text('Bloquear')),
            PopupMenuItem(value: 'desbloquear', child: Text('Desbloquear')),
            PopupMenuItem(value: 'publicar', child: Text('Publicar no Mural (uma lista)')),
            PopupMenuItem(value: 'exportar', child: Text('Exportar (uma lista)')),
            PopupMenuItem(value: 'excluir', child: Text('Excluir listas')),
          ],
        ),
      ],
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ------------------------------------------------------ criar / configurar

  Future<void> _dialogoLista({ListaEntidades? existente}) async {
    final tituloCtrl = TextEditingController(text: existente?.titulo ?? '');
    var cor = existente != null
        ? corDeHex(existente.corTema)
        : Theme.of(context).colorScheme.primary;
    var mostrarData = existente?.mostrarData ?? true;
    var formatoData = existente?.formatoData ?? 'dd/mm/aaaa';
    var mostrarHora = existente?.mostrarHora ?? true;
    var formatoHora = existente?.formatoHora ?? '24h';
    // Data e hora do evento (passado ou futuro); "atual" = usa o momento da abertura/impressão.
    var dataModo = (existente?.dataEvento ?? '').isNotEmpty ? 'personalizada' : 'atual';
    DateTime? dataEv = parseNascimento(existente?.dataEvento ?? '');
    var horaModo = (existente?.horaEvento ?? -1) >= 0 ? 'personalizada' : 'atual';
    var horaEv = (existente?.horaEvento ?? -1) >= 0
        ? existente!.horaEvento
        : DateTime.now().hour * 60 + DateTime.now().minute;
    var tipo = existente?.tipo ?? 'padrao';
    final meses = <int>{...(existente?.meses ?? <int>[])};
    const descricaoTipo = {
      'padrao': 'Você escolhe os membros e pode reordená-los à mão.',
      'aniversariantes': 'Automática: reúne quem faz aniversário nos meses escolhidos.',
      'classes': 'Automática: organiza os membros pelas classes da EBD (matrícula).',
    };

    final criada = await showDialog<ListaEntidades>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(existente == null ? 'Nova lista' : 'Configurar lista'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (existente == null) ...[
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'padrao', label: Text('Escolhida')),
                      ButtonSegment(value: 'aniversariantes', label: Text('Aniversários')),
                      ButtonSegment(value: 'classes', label: Text('Classes')),
                    ],
                    selected: {tipo},
                    onSelectionChanged: (s) => setD(() => tipo = s.first),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 8),
                    child: Text(descricaoTipo[tipo] ?? '', style: const TextStyle(fontSize: 12)),
                  ),
                ],
                TextField(
                  controller: tituloCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Título da lista',
                    hintText: 'Ex: Ceia do Senhor, EBD, Batismo',
                  ),
                ),
                if (tipo == 'aniversariantes') ...[
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Meses', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (var i = 0; i < 12; i++)
                        FilterChip(
                          label: Text(kMeses[i].substring(0, 3)),
                          selected: meses.contains(i + 1),
                          onSelected: (v) => setD(() {
                            v ? meses.add(i + 1) : meses.remove(i + 1);
                          }),
                        ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('Nenhum mês marcado = o ano todo', style: TextStyle(fontSize: 12)),
                  ),
                ],
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cor da lista'),
                  trailing: CircleAvatar(backgroundColor: cor, radius: 16),
                  onTap: () async {
                    final nova = await escolherCor(ctx, cor, titulo: 'Cor da lista');
                    if (nova != null) setD(() => cor = nova);
                  },
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mostrar data'),
                  value: mostrarData,
                  onChanged: (v) => setD(() => mostrarData = v),
                ),
                if (mostrarData) ...[
                  DropdownButtonFormField<String>(
                    value: formatoData,
                    decoration: const InputDecoration(labelText: 'Formato da data'),
                    items: const [
                      DropdownMenuItem(value: 'dd/mm/aaaa', child: Text('dd/mm/aaaa')),
                      DropdownMenuItem(value: 'mm/aaaa', child: Text('mm/aaaa')),
                    ],
                    onChanged: (v) => setD(() => formatoData = v!),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'atual', label: Text('Data atual')),
                      ButtonSegment(value: 'personalizada', label: Text('Data do evento')),
                    ],
                    selected: {dataModo},
                    onSelectionChanged: (s) => setD(() {
                      dataModo = s.first;
                      if (dataModo == 'personalizada' && dataEv == null) {
                        final h = DateTime.now();
                        dataEv = DateTime.utc(h.year, h.month, h.day);
                      }
                    }),
                  ),
                  if (dataModo == 'personalizada')
                    SeletorData(
                      rotulo: 'Data do evento (passado ou futuro)',
                      inicial: dataEv,
                      onChanged: (d) => dataEv = d,
                    ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mostrar hora'),
                  value: mostrarHora,
                  onChanged: (v) => setD(() => mostrarHora = v),
                ),
                if (mostrarHora) ...[
                  DropdownButtonFormField<String>(
                    value: formatoHora,
                    decoration: const InputDecoration(labelText: 'Formato da hora'),
                    items: const [
                      DropdownMenuItem(value: '24h', child: Text('24 horas (14:30)')),
                      DropdownMenuItem(value: '12h', child: Text('12 horas (02:30 PM)')),
                    ],
                    onChanged: (v) => setD(() => formatoHora = v!),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'atual', label: Text('Hora atual')),
                      ButtonSegment(value: 'personalizada', label: Text('Hora do evento')),
                    ],
                    selected: {horaModo},
                    onSelectionChanged: (s) => setD(() => horaModo = s.first),
                  ),
                  if (horaModo == 'personalizada')
                    SeletorHora(
                      rotulo: 'Hora do evento',
                      minutos: horaEv,
                      onChanged: (m) => horaEv = m,
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final titulo = tituloCtrl.text.trim();
                if (titulo.isEmpty) return;

                if (existente == null) {
                  Navigator.pop(
                    ctx,
                    ListaEntidades(
                      id: _uuid.v4(),
                      titulo: titulo,
                      mostrarData: mostrarData,
                      formatoData: formatoData,
                      mostrarHora: mostrarHora,
                      formatoHora: formatoHora,
                      dataEvento: dataModo == 'personalizada' && dataEv != null ? isoData(dataEv!) : '',
                      horaEvento: horaModo == 'personalizada' ? horaEv : -1,
                      corTema: hexDeCor(cor),
                      tipo: tipo,
                      meses: meses.toList()..sort(),
                      ordem: tipo == 'padrao'
                          ? 'manual'
                          : (tipo == 'aniversariantes' ? 'aniversario' : 'az'),
                    ),
                  );
                } else {
                  existente
                    ..titulo = titulo
                    ..corTema = hexDeCor(cor)
                    ..mostrarData = mostrarData
                    ..formatoData = formatoData
                    ..mostrarHora = mostrarHora
                    ..formatoHora = formatoHora
                    ..dataEvento =
                        dataModo == 'personalizada' && dataEv != null ? isoData(dataEv!) : ''
                    ..horaEvento = horaModo == 'personalizada' ? horaEv : -1;
                  if (existente.tipo == 'aniversariantes') {
                    existente.meses = meses.toList()..sort();
                  }
                  widget.onSalvar();
                  Navigator.pop(ctx);
                }
              },
              child: Text(existente == null ? 'Criar' : 'Salvar'),
            ),
          ],
        ),
      ),
    );

    if (criada != null) {
      _banco.listas.add(criada);
      widget.onSalvar();
      _abrirLista(criada); // já abre para adicionar membros
    }
  }

  String _subtitulo(ListaEntidades a) {
    final n = _banco.membrosDaLista(a).length;
    String base;
    switch (a.tipo) {
      case 'aniversariantes':
        final meses = a.meses.isEmpty
            ? 'todos os meses'
            : (a.meses.toList()..sort()).map((m) => kMeses[m - 1].substring(0, 3)).join(', ');
        base = 'Aniversariantes · $meses · $n';
        break;
      case 'classes':
        base = 'Por classes da EBD · $n membro(s)';
        break;
      default:
        base = '$n membro(s)';
    }
    final ev = _textoEvento(a);
    final extra = [if (ev.isNotEmpty) ev, if (a.isLocked) 'bloqueada'];
    return extra.isEmpty ? base : '$base · ${extra.join(' · ')}';
  }

  String _textoEvento(ListaEntidades a) {
    final d = parseNascimento(a.dataEvento);
    final partes = <String>[];
    if (d != null) partes.add(dataBr(d));
    if (a.horaEvento >= 0) {
      final h = (a.horaEvento ~/ 60).toString().padLeft(2, '0');
      final m = (a.horaEvento % 60).toString().padLeft(2, '0');
      partes.add('$h:$m');
    }
    return partes.isEmpty ? '' : 'Evento: ${partes.join(' ')}';
  }

  // ----------------------------------------------------------------- importar

  Future<void> _importar() async {
    try {
      final r = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: Importador.extensoes,
        withData: true,
      );
      if (r == null) return;
      final arq = r.files.single;
      if (arq.bytes == null) {
        _snack('Não foi possível ler o arquivo.');
        return;
      }

      final lido = Importador.ler(arq.name, arq.bytes!);

      if (lido.bancoCompleto != null) {
        _snack('Este é um backup completo. Para restaurar, use Membros > menu > Importar.');
        return;
      }

      if (lido.backup != null) {
        final b = lido.backup!;
        final lista = _banco.mesclarExterno(
          listaJson: b.listaJson,
          membrosJson: b.membrosJson,
          congregacoesJson: b.congregacoesJson,
          colunasJson: b.colunasJson,
          classesJson: b.classesJson,
        );
        widget.onSalvar();
        _snack('Lista "${lista.titulo}" importada com ${lista.membroIds.length} membro(s).');
        return;
      }

      // Lista de nomes: cria uma lista com o nome do arquivo. Quem já está no
      // cadastro é reaproveitado; os demais viram membros novos.
      final nome = arq.name.contains('.')
          ? arq.name.substring(0, arq.name.lastIndexOf('.'))
          : arq.name;
      final nova = ListaEntidades(
        id: _uuid.v4(),
        titulo: nome.isEmpty ? 'Lista importada' : nome,
        corTema: '#1B2A4A',
      );
      final resumo = Importador.aplicar(_banco, lido, lista: nova);
      _banco.listas.add(nova);
      widget.onSalvar();
      _snack('"${nova.titulo}": ${resumo.mensagem}');
    } catch (e) {
      _snack('Erro ao importar arquivo: $e');
    }
  }

  // ------------------------------------------------------------------ outros

  Future<void> _excluir(ListaEntidades lista) async {
    final ok = await confirmar(
      context,
      titulo: 'Excluir lista?',
      mensagem:
          'A lista "${lista.titulo}" será apagada. Nenhum membro é excluído: todos continuam cadastrados na área Membros. Esta ação não pode ser desfeita.',
    );
    if (!ok) return;
    _banco.listas.remove(lista);
    widget.onSalvar();
  }

  void _abrirLista(ListaEntidades lista) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ListaDetalhesPage(banco: _banco, lista: lista, onSalvar: widget.onSalvar),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final listas = _filtradas();

    Widget corpo;
    if (_banco.listas.isEmpty) {
      corpo = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nenhuma lista criada.\nToque em "Nova lista" ou importe um arquivo (JSON, CSV ou TXT).',
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      corpo = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
            itemCount: listas.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) return _cabecalho(esquema, listas.isEmpty);
              final lista = listas[i - 1];
              final cor = corDeHex(lista.corTema);
              final marcada = _modoSel && _sel.contains(lista.id);
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                elevation: 0,
                clipBehavior: Clip.antiAlias,
                color: marcada ? esquema.primary.withOpacity(0.12) : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: marcada ? esquema.primary : esquema.outlineVariant,
                    width: marcada ? 1.6 : 1,
                  ),
                ),
                child: InkWell(
                  onTap: _modoSel ? () => _alternar(lista) : () => _abrirLista(lista),
                  onLongPress: _modoSel ? null : () => _entrarSelecao(lista),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(width: 6, color: cor),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                            child: Row(
                              children: [
                                if (_modoSel)
                                  Checkbox(
                                    value: _sel.contains(lista.id),
                                    onChanged: (_) => _alternar(lista),
                                  ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          if (lista.tipo != 'padrao')
                                            Padding(
                                              padding: const EdgeInsets.only(right: 6),
                                              child: Icon(
                                                lista.tipo == 'classes' ? Icons.school : Icons.cake,
                                                size: 16,
                                                color: esquema.primary,
                                              ),
                                            ),
                                          Flexible(
                                            child: Text(lista.titulo,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w600, fontSize: 16)),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _subtitulo(lista),
                                        style: TextStyle(
                                            fontSize: 12, color: esquema.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!_modoSel && Sync.instance.podeEditar)
                                IconButton(
                                  icon: Icon(
                                    lista.isLocked ? Icons.lock : Icons.lock_open,
                                    color: lista.isLocked ? Colors.red : esquema.outline,
                                  ),
                                  tooltip: lista.isLocked ? 'Desbloquear' : 'Bloquear alterações',
                                  onPressed: () {
                                    lista.isLocked = !lista.isLocked;
                                    widget.onSalvar();
                                  },
                                ),
                                if (!_modoSel && Sync.instance.podeEditar)
                                PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'editar') _dialogoLista(existente: lista);
                                    if (v == 'publicar') _publicar(lista);
                                    if (v == 'excluir') _excluir(lista);
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'editar', child: Text('Configurar lista')),
                                    PopupMenuItem(value: 'publicar', child: Text('Publicar no Mural')),
                                    PopupMenuItem(value: 'excluir', child: Text('Excluir lista')),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    return Scaffold(
      appBar: _modoSel
          ? _appBarSelecao(listas)
          : AppBar(
        title: const Text('Listas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.checklist),
            tooltip: 'Selecionar várias',
            onPressed: () => _entrarSelecao(),
          ),
          if (Sync.instance.podeEditar)
            IconButton(
              icon: const Icon(Icons.file_upload_outlined),
              tooltip: 'Importar (JSON, CSV, TXT)',
              onPressed: _importar,
            ),
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            tooltip: 'Aparência e cores',
            onPressed: widget.onAparencia,
          ),
        ],
      ),
      body: corpo,
      floatingActionButton: (_modoSel || !Sync.instance.podeEditar)
          ? null
          : FloatingActionButton.extended(
        onPressed: () => _dialogoLista(),
        icon: const Icon(Icons.add),
        label: const Text('Nova lista'),
      ),
    );
  }
}
