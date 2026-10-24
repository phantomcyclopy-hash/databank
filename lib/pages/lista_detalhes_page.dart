import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../widgets/classes_dialog.dart';
import '../widgets/dialogos.dart';
import '../widgets/form_membro.dart';
import '../widgets/membro_widgets.dart';
import '../widgets/selecao_acoes.dart';
import '../widgets/seletor_cor.dart';
import 'opcoes_impressao_page.dart';
import 'selecionar_membros_page.dart';

/// Uma lista. Tipos:
///  - padrao: membros escolhidos (podem ser reordenados à mão);
///  - aniversariantes: automática, montada pelos meses de nascimento;
///  - classes: automática, organizada pelas classes da EBD (matrícula).
/// Aqui nunca se apaga um membro; isso só é possível na área Membros.
class ListaDetalhesPage extends StatefulWidget {
  final Banco banco;
  final ListaEntidades lista;
  final VoidCallback onSalvar;

  const ListaDetalhesPage({
    super.key,
    required this.banco,
    required this.lista,
    required this.onSalvar,
  });

  @override
  State<ListaDetalhesPage> createState() => _ListaDetalhesPageState();
}

class _ListaDetalhesPageState extends State<ListaDetalhesPage> {
  late final FiltroMembros _filtro;
  final TextEditingController _buscaCtrl = TextEditingController();

  Banco get _banco => widget.banco;
  ListaEntidades get _lista => widget.lista;
  bool get _padrao => _lista.tipo == 'padrao';

  // ---------------------------------------------------------- multiseleção
  bool _modoSel = false;
  final Set<String> _sel = {};

  void _entrarSelecao([Entidade? m]) => setState(() {
        _modoSel = true;
        if (m != null) _sel.add(m.id);
      });

  void _sairSelecao() => setState(() {
        _modoSel = false;
        _sel.clear();
      });

  void _alternar(Entidade m) => setState(() {
        _sel.contains(m.id) ? _sel.remove(m.id) : _sel.add(m.id);
      });

  /// Marca (ou desmarca) todos os exibidos, isto é, os que passam pela busca e filtros.
  void _selecionarExibidos(List<Entidade> visiveis, {bool? marcar}) => setState(() {
        final todos = visiveis.every((m) => _sel.contains(m.id));
        final adicionar = marcar ?? !todos;
        for (final m in visiveis) {
          adicionar ? _sel.add(m.id) : _sel.remove(m.id);
        }
      });

  Future<void> _removerSelecionados() async {
    if (_bloqueada()) return;
    final n = _sel.length;
    if (n == 0) return;
    final ok = await confirmar(
      context,
      titulo: 'Remover $n membro(s) da lista?',
      mensagem: 'Eles saem desta lista, mas continuam cadastrados na área Membros.',
      acao: 'Remover',
    );
    if (!ok) return;
    setState(() => _lista.membroIds.removeWhere((id) => _sel.contains(id)));
    _sairSelecao();
    widget.onSalvar();
    _snack('$n membro(s) removido(s) da lista.');
  }

  Future<void> _classeSelecionados() async {
    if (_bloqueada()) return;
    final alvo = _banco.membros.where((m) => _sel.contains(m.id)).toList();
    if (alvo.isEmpty) return;
    final id = await escolherClasseDialog(context, _banco, 'Classe de ${alvo.length} membro(s)');
    if (id == null) return;
    final agora = DateTime.now().millisecondsSinceEpoch;
    for (final m in alvo) {
      m.classe = id;
      m.atualizadoEm = agora;
    }
    _sairSelecao();
    widget.onSalvar();
    _snack('Classe alterada para ${alvo.length} membro(s).');
  }

  AppBar _appBarSelecao(List<Entidade> visiveis, Color corLista, Color fg) {
    return AppBar(
      backgroundColor: corLista,
      foregroundColor: fg,
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Sair da seleção',
        onPressed: _sairSelecao,
      ),
      title: Text('${_sel.length} selecionado(s)'),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all),
          tooltip: 'Selecionar / desmarcar todos os exibidos',
          onPressed: () => _selecionarExibidos(visiveis),
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'remover':
                _removerSelecionados();
                break;
              case 'classe':
                _classeSelecionados();
                break;
              case 'imprimir':
                _imprimir(visiveis.where((m) => _sel.contains(m.id)).toList());
                break;
            }
          },
          itemBuilder: (_) => [
            if (_padrao) const PopupMenuItem(value: 'remover', child: Text('Remover da lista')),
            const PopupMenuItem(value: 'classe', child: Text('Alterar classe')),
            const PopupMenuItem(value: 'imprimir', child: Text('Imprimir seleção')),
          ],
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _filtro = FiltroMembros(ordem: _lista.ordem);
    if (!_padrao && _filtro.ordem == 'manual') _filtro.ordem = 'az';
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _aoMudar() {
    setState(() {});
    if (_lista.ordem != _filtro.ordem) {
      _lista.ordem = _filtro.ordem;
      widget.onSalvar();
    }
  }

  bool _bloqueada() {
    if (_lista.isLocked) {
      _snack('Esta lista está bloqueada. Desbloqueie na tela de Listas para alterar.');
      return true;
    }
    return false;
  }

  String _dataHoraAtual() {
    final agora = DateTime.now();
    final partes = <String>[];
    if (_lista.mostrarData) {
      final d = parseNascimento(_lista.dataEvento) ?? agora;
      partes.add(DateFormat(_lista.formatoData == 'mm/aaaa' ? 'MM/yyyy' : 'dd/MM/yyyy').format(d));
    }
    if (_lista.mostrarHora) {
      final min = _lista.horaEvento >= 0 ? _lista.horaEvento : agora.hour * 60 + agora.minute;
      final h = DateTime(2000, 1, 1, min ~/ 60, min % 60);
      partes.add(DateFormat(_lista.formatoHora == '12h' ? 'hh:mm a' : 'HH:mm').format(h));
    }
    return partes.join(' ');
  }

  String get _layoutPrincipal {
    switch (_lista.tipo) {
      case 'aniversariantes':
        return 'aniversariantes';
      case 'classes':
        return 'classes';
      default:
        return 'presenca';
    }
  }

  String _etiquetaAniversario(Entidade m) {
    final n = m.dataNascimento;
    if (n == null) return '';
    final h = DateTime.now();
    final hoje = m.diasParaAniversario(h) == 0;
    final dd = n.day.toString().padLeft(2, '0');
    final mm = n.month.toString().padLeft(2, '0');
    return '${hoje ? 'Hoje! ' : ''}Aniversário $dd/$mm · ${h.year - n.year} anos em ${h.year}';
  }

  // ------------------------------------------------------------------ ações

  Future<void> _adicionarExistentes() async {
    if (_bloqueada()) return;
    final ids = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => SelecionarMembrosPage(
          banco: _banco,
          titulo: 'Adicionar à lista: ${_lista.titulo}',
          jaIncluidos: _lista.membroIds.toSet(),
          corPadrao: corDeHex(_lista.corTema),
        ),
      ),
    );
    if (ids == null || ids.isEmpty) return;
    setState(() {
      for (final id in ids) {
        if (!_lista.membroIds.contains(id)) _lista.membroIds.add(id);
      }
    });
    widget.onSalvar();
    _snack('${ids.length} membro(s) adicionado(s) à lista.');
  }

  Future<void> _novoMembro() async {
    if (_bloqueada()) return;
    final novo = await abrirFormularioMembro(
      context,
      _banco,
      congregacaoInicial: _filtro.congregacoes.length == 1 ? _filtro.congregacoes.first : '',
    );
    if (novo == null) return;
    setState(() {
      _banco.salvarMembro(novo);
      if (!_lista.membroIds.contains(novo.id)) _lista.membroIds.add(novo.id);
    });
    widget.onSalvar();
  }

  Future<void> _editar(Entidade m) async {
    if (_bloqueada()) return;
    final novo = await abrirFormularioMembro(context, _banco, existente: m);
    if (novo == null) return;
    setState(() => _banco.salvarMembro(novo));
    widget.onSalvar();
  }

  Future<void> _removerDaLista(Entidade m) async {
    if (_bloqueada()) return;
    final ok = await confirmar(
      context,
      titulo: 'Remover da lista?',
      mensagem: '"${m.nome}" sai desta lista, mas continua cadastrado na área Membros.',
      acao: 'Remover',
    );
    if (!ok) return;
    setState(() => _lista.membroIds.remove(m.id));
    widget.onSalvar();
  }

  Future<String?> _escolherClasse(String titulo) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(titulo),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text('Sem classe'),
          ),
          ..._banco.classes.map((c) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, c.id),
                child: Text(c.nome),
              )),
        ],
      ),
    );
  }

  Future<void> _alterarClasse(Entidade m) async {
    if (_bloqueada()) return;
    final id = await _escolherClasse('Classe de ${m.nome}');
    if (id == null) return;
    setState(() {
      m.classe = id;
      m.atualizadoEm = DateTime.now().millisecondsSinceEpoch;
    });
    widget.onSalvar();
  }

  /// Matricula vários membros de uma vez numa classe.
  Future<void> _matricular() async {
    if (_bloqueada()) return;
    final classeId = await _escolherClasse('Matricular em qual classe?');
    if (classeId == null) return;
    final nome = classeId.isEmpty ? 'Sem classe' : (_banco.classePorId(classeId)?.nome ?? '');
    if (!mounted) return;
    final ids = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => SelecionarMembrosPage(
          banco: _banco,
          titulo: 'Matricular: $nome',
          jaIncluidos: {
            for (final m in _banco.membros)
              if (_banco.classeEfetiva(m) == classeId) m.id
          },
          acao: 'Matricular',
          etiquetaJa: 'Já está nesta classe',
        ),
      ),
    );
    if (ids == null || ids.isEmpty) return;
    final agora = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      for (final m in _banco.membros) {
        if (ids.contains(m.id)) {
          m.classe = classeId;
          m.atualizadoEm = agora;
        }
      }
    });
    widget.onSalvar();
    _snack('${ids.length} membro(s) matriculado(s) em $nome.');
  }

  void _imprimirFicha(Entidade m) {
    imprimirComOpcoes(
      context,
      banco: _banco,
      lista: _lista,
      membros: [m],
      tituloInicial: _lista.titulo,
      ficha: true,
      aviso: _snack,
    );
  }

  void _imprimir(List<Entidade> visiveis, {String? layout}) {
    imprimirComOpcoes(
      context,
      banco: _banco,
      lista: _lista,
      membros: visiveis,
      tituloInicial: tituloComFiltro(_banco, _lista.titulo, _filtro),
      layout: layout,
      aviso: _snack,
    );
  }

  void _exportar() {
    final membros = _banco.membrosDaLista(_lista);
    final json = jsonEncode({
      'tipo': 'ata_ibmmkar',
      'lista': _lista.toJson(),
      'membros': membros.map((m) => m.toJson()).toList(),
      'congregacoes': _banco.congregacoes.map((c) => c.toJson()).toList(),
      'colunas': _banco.colunas.map((c) => c.toJson()).toList(),
      'classes': _banco.classes.map((c) => c.toJson()).toList(),
    });
    mostrarExportacao(context, 'Exportar lista (JSON)', json);
  }

  // ------------------------------------------------------------ reordenação

  void _aplicarOrdem(List<Entidade> visiveis, int de, int para) {
    if (para > de) para -= 1;
    final ids = visiveis.map((m) => m.id).toList();
    final id = ids.removeAt(de);
    ids.insert(para, id);
    setState(() => _lista.membroIds = ids);
    widget.onSalvar();
  }

  void _mover(List<Entidade> visiveis, int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= visiveis.length) return;
    final ids = visiveis.map((m) => m.id).toList();
    final t = ids[i];
    ids[i] = ids[j];
    ids[j] = t;
    setState(() => _lista.membroIds = ids);
    widget.onSalvar();
  }

  // ----------------------------------------------------------------- menus

  void _menuAdicionar() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.group_add),
              title: const Text('Membros já cadastrados'),
              subtitle: const Text('Escolha na lista, com filtros e "selecionar todos"'),
              onTap: () {
                Navigator.pop(ctx);
                _adicionarExistentes();
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_add),
              title: const Text('Novo membro'),
              subtitle: const Text('Cadastra e já adiciona a esta lista'),
              onTap: () {
                Navigator.pop(ctx);
                _novoMembro();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuMembro(Entidade m) {
    return PopupMenuButton<String>(
      tooltip: 'Ações',
      onSelected: (v) {
        if (v == 'editar') _editar(m);
        if (v == 'classe') _alterarClasse(m);
        if (v == 'ficha') _imprimirFicha(m);
        if (v == 'remover') _removerDaLista(m);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'editar', child: Text('Editar ficha')),
        if (_lista.tipo == 'classes')
          const PopupMenuItem(value: 'classe', child: Text('Alterar classe (matricular)')),
        const PopupMenuItem(value: 'ficha', child: Text('Imprimir ficha')),
        if (_padrao) const PopupMenuItem(value: 'remover', child: Text('Remover da lista')),
      ],
    );
  }

  Widget _cartao(Entidade m, Color corLista, {Widget? trailing}) {
    return MembroCard(
      banco: _banco,
      membro: m,
      corPadrao: corLista,
      selecionado: _modoSel && _sel.contains(m.id),
      leading: _modoSel ? Checkbox(value: _sel.contains(m.id), onChanged: (_) => _alternar(m)) : null,
      onTap: _modoSel ? () => _alternar(m) : () => _editar(m),
      onLongPress: _modoSel ? null : () => _entrarSelecao(m),
      etiqueta: _lista.tipo == 'aniversariantes' ? _etiquetaAniversario(m) : null,
      trailing: _modoSel ? null : (trailing ?? _menuMembro(m)),
    );
  }

  // --------------------------------------------------------------- conteúdo

  Widget _listaReordenavel(List<Entidade> visiveis, Color corLista) {
    Widget seta(IconData icone, String dica, VoidCallback? acao) => SizedBox(
          width: 30,
          height: 28,
          child: IconButton(
            padding: EdgeInsets.zero,
            iconSize: 22,
            tooltip: dica,
            icon: Icon(icone),
            onPressed: acao,
          ),
        );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
          buildDefaultDragHandles: false,
          itemCount: visiveis.length,
          onReorder: (a, b) => _aplicarOrdem(visiveis, a, b),
          itemBuilder: (ctx, i) {
            final m = visiveis[i];
            return Container(
              key: ValueKey(m.id),
              child: _cartao(
                m,
                corLista,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        seta(Icons.keyboard_arrow_up, 'Mover para cima',
                            i > 0 ? () => _mover(visiveis, i, -1) : null),
                        seta(Icons.keyboard_arrow_down, 'Mover para baixo',
                            i < visiveis.length - 1 ? () => _mover(visiveis, i, 1) : null),
                      ],
                    ),
                    ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: Tooltip(message: 'Arraste para reordenar', child: Icon(Icons.drag_handle)),
                      ),
                    ),
                    _menuMembro(m),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _listaPorClasses(List<Entidade> visiveis, Color corLista) {
    final esquema = Theme.of(context).colorScheme;
    final grupos = <MapEntry<String, List<Entidade>>>[];
    for (final c in _banco.classes) {
      final l = visiveis.where((m) => _banco.classeEfetiva(m) == c.id).toList();
      if (l.isNotEmpty) grupos.add(MapEntry(c.nome, l));
    }
    final sem = visiveis.where((m) => _banco.classeEfetiva(m).isEmpty).toList();
    if (sem.isNotEmpty) grupos.add(MapEntry('Sem classe', sem));

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
          children: [
            for (final g in grupos) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
                child: Row(
                  children: [
                    Text(g.key,
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700, color: esquema.primary)),
                    const SizedBox(width: 8),
                    Text('${g.value.length} membro(s)',
                        style: TextStyle(fontSize: 12, color: esquema.onSurfaceVariant)),
                    const SizedBox(width: 8),
                    Expanded(child: Divider(color: esquema.outlineVariant)),
                  ],
                ),
              ),
              ...g.value.map((m) => _cartao(m, corLista)),
            ],
          ],
        ),
      ),
    );
  }

  String? get _avisoAutomatica {
    if (_lista.tipo == 'aniversariantes') {
      final meses = (_lista.meses.toList()..sort()).map((m) => kMeses[m - 1]).join(', ');
      return 'Lista automática: aniversariantes ${_lista.meses.isEmpty ? 'de todos os meses' : 'de $meses'}. '
          'Atualiza sozinha conforme as datas de nascimento cadastradas.';
    }
    if (_lista.tipo == 'classes') {
      return 'Lista automática organizada pelas classes da EBD. Use "Matricular" para colocar vários '
          'membros numa classe, ou o menu de cada membro para trocar a classe.';
    }
    return null;
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final corLista = corDeHex(_lista.corTema);
    final fg = corTextoSobre(corLista);
    final esquema = Theme.of(context).colorScheme;
    final membrosLista = _banco.membrosDaLista(_lista);
    final visiveis = _filtro.aplicar(_banco, membrosLista);
    final dataHora = _dataHoraAtual();
    final aviso = _avisoAutomatica;
    final corGrade = (_filtro.congregacoes.length == 1)
        ? (_banco.congregacaoPorId(_filtro.congregacoes.first) != null
            ? corDeHex(_banco.congregacaoPorId(_filtro.congregacoes.first)!.cor, padrao: corLista)
            : Colors.grey)
        : corLista;

    final manual = _padrao && _filtro.ordem == 'manual';
    final podeReordenar = manual && !_filtro.ativo && !_lista.isLocked && !_modoSel;

    IconData iconeAtalho;
    String dicaAtalho;
    switch (_lista.tipo) {
      case 'aniversariantes':
        iconeAtalho = Icons.cake_outlined;
        dicaAtalho = 'Imprimir aniversariantes';
        break;
      case 'classes':
        iconeAtalho = Icons.school_outlined;
        dicaAtalho = 'Imprimir matrícula por classes';
        break;
      default:
        iconeAtalho = Icons.assignment_turned_in_outlined;
        dicaAtalho = 'Lista de presença (PDF)';
    }

    return Scaffold(
      appBar: _modoSel
          ? _appBarSelecao(visiveis, corLista, fg)
          : AppBar(
        backgroundColor: corLista,
        foregroundColor: fg,
        title: Row(
          children: [
            Flexible(child: Text(_lista.titulo, overflow: TextOverflow.ellipsis)),
            if (dataHora.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text('($dataHora)', style: TextStyle(fontSize: 12, color: fg.withOpacity(0.75))),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.checklist),
            tooltip: 'Selecionar vários',
            onPressed: () => _entrarSelecao(),
          ),
          IconButton(
            icon: Icon(iconeAtalho),
            tooltip: dicaAtalho,
            onPressed: () => _imprimir(visiveis, layout: _layoutPrincipal),
          ),
          IconButton(
            icon: const Icon(Icons.description_outlined),
            tooltip: 'Gerador de relatórios',
            onPressed: () => _imprimir(visiveis),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'existentes':
                  _adicionarExistentes();
                  break;
                case 'novo':
                  _novoMembro();
                  break;
                case 'matricular':
                  _matricular();
                  break;
                case 'classes':
                  mostrarClasses(context, _banco, () {
                    setState(() {});
                    widget.onSalvar();
                  });
                  break;
                case 'json':
                  _exportar();
                  break;
                case 'pdf':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OpcoesImpressaoPage(
                          banco: _banco, lista: _lista, modoConfig: true),
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (_) => [
              if (_padrao) ...const [
                PopupMenuItem(value: 'existentes', child: Text('Adicionar membros cadastrados')),
                PopupMenuItem(value: 'novo', child: Text('Novo membro')),
              ],
              if (_lista.tipo == 'classes') ...const [
                PopupMenuItem(value: 'matricular', child: Text('Matricular membros')),
                PopupMenuItem(value: 'classes', child: Text('Gerenciar classes')),
              ],
              const PopupMenuItem(value: 'json', child: Text('Exportar lista (JSON)')),
              const PopupMenuItem(value: 'pdf', child: Text('Opções de impressão')),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (ctx, c) {
          final largo = c.maxWidth >= 820;

          Widget conteudo;
          if (membrosLista.isEmpty) {
            conteudo = Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _padrao
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Esta lista ainda não tem membros.', textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            icon: const Icon(Icons.group_add),
                            label: const Text('Adicionar membros'),
                            onPressed: _menuAdicionar,
                          ),
                        ],
                      )
                    : Text(
                        _lista.tipo == 'aniversariantes'
                            ? 'Nenhum membro com data de nascimento nos meses escolhidos.\nCadastre as datas na área Membros.'
                            : 'Nenhum membro cadastrado.',
                        textAlign: TextAlign.center,
                      ),
              ),
            );
          } else if (visiveis.isEmpty) {
            conteudo = const Center(child: Text('Nenhum membro encontrado com esses filtros.'));
          } else if (_lista.tipo == 'classes') {
            conteudo = _listaPorClasses(visiveis, corLista);
          } else if (podeReordenar) {
            conteudo = _listaReordenavel(visiveis, corLista);
          } else if (largo) {
            conteudo = gradeMembros(
              banco: _banco,
              membros: visiveis,
              corGrade: corGrade,
              corPadrao: corLista,
              onTap: _editar,
              acoes: _modoSel ? (m) => const SizedBox.shrink() : _menuMembro,
              selecionados: _modoSel ? _sel : null,
              onSelecionar: (m, v) => setState(() {
                v ? _sel.add(m.id) : _sel.remove(m.id);
              }),
              onSelecionarTodos: (v) => _selecionarExibidos(visiveis, marcar: v),
            );
          } else {
            conteudo = ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
              itemCount: visiveis.length,
              itemBuilder: (_, i) => _cartao(visiveis[i], corLista),
            );
          }

          return Column(
            children: [
              DashboardCongregacoes(banco: _banco, origem: membrosLista, corPadrao: corLista),
              PainelBuscaFiltros(
                banco: _banco,
                filtro: _filtro,
                buscaCtrl: _buscaCtrl,
                origem: membrosLista,
                onMudou: _aoMudar,
                corPadrao: corLista,
                permitirManual: _padrao,
              ),
              if (aviso != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: esquema.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: esquema.outlineVariant),
                    ),
                    child: Text(aviso, style: const TextStyle(fontSize: 12)),
                  ),
                ),
              if (membrosLista.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      manual && _filtro.ativo
                          ? 'Limpe a busca e os filtros para reordenar à mão.'
                          : manual
                              ? 'Use as setas ou arraste pelo ícone ≡ para reordenar (${membrosLista.length} membro(s)).'
                              : (visiveis.length == membrosLista.length
                                  ? '${membrosLista.length} membro(s)'
                                  : '${visiveis.length} de ${membrosLista.length} membro(s)'),
                      style: TextStyle(fontSize: 12, color: esquema.onSurfaceVariant),
                    ),
                  ),
                ),
              if (_modoSel)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    'Para selecionar por filtro: aplique a busca e os filtros e toque no ícone de selecionar todos.',
                    style: TextStyle(fontSize: 12, color: esquema.primary),
                  ),
                ),
              Expanded(child: conteudo),
            ],
          );
        },
      ),
      floatingActionButton: _modoSel
          ? null
          : _padrao
          ? FloatingActionButton.extended(
              onPressed: _lista.isLocked ? null : _menuAdicionar,
              backgroundColor: _lista.isLocked ? Colors.grey : corLista,
              foregroundColor: fg,
              icon: const Icon(Icons.group_add),
              label: const Text('Adicionar'),
            )
          : (_lista.tipo == 'classes'
              ? FloatingActionButton.extended(
                  onPressed: _lista.isLocked ? null : _matricular,
                  backgroundColor: _lista.isLocked ? Colors.grey : corLista,
                  foregroundColor: fg,
                  icon: const Icon(Icons.school),
                  label: const Text('Matricular'),
                )
              : null),
    );
  }
}
