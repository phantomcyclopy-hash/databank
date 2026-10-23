import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../importador.dart';
import '../models.dart';
import '../widgets/campos_extras_dialog.dart';
import '../widgets/classes_dialog.dart';
import '../widgets/congregacoes_dialog.dart';
import '../widgets/dialogos.dart';
import '../widgets/form_membro.dart';
import '../widgets/membro_widgets.dart';
import '../widgets/selecao_acoes.dart';
import 'opcoes_impressao_page.dart';

/// Cadastro geral de membros. É o ÚNICO lugar onde um membro pode ser excluído.
class MembrosPage extends StatefulWidget {
  final Banco banco;
  final VoidCallback onSalvar;
  final VoidCallback onAparencia;
  final VoidCallback onVerAniversarios;

  const MembrosPage({
    super.key,
    required this.banco,
    required this.onSalvar,
    required this.onAparencia,
    required this.onVerAniversarios,
  });

  @override
  State<MembrosPage> createState() => _MembrosPageState();
}

class _MembrosPageState extends State<MembrosPage> {
  late final FiltroMembros _filtro;
  final TextEditingController _buscaCtrl = TextEditingController();

  Banco get _banco => widget.banco;

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

  /// Marca (ou desmarca) todos os membros exibidos, ou seja, os que passam
  /// pela busca e pelos filtros atuais.
  void _selecionarExibidos(List<Entidade> visiveis, {bool? marcar}) => setState(() {
        final todos = visiveis.every((m) => _sel.contains(m.id));
        final adicionar = marcar ?? !todos;
        for (final m in visiveis) {
          adicionar ? _sel.add(m.id) : _sel.remove(m.id);
        }
      });

  List<Entidade> _selecionados() => _banco.membros.where((m) => _sel.contains(m.id)).toList();

  Future<void> _excluirSelecionados() async {
    final alvo = _selecionados();
    if (alvo.isEmpty) return;
    final ok = await confirmar(
      context,
      titulo: 'Excluir ${alvo.length} membro(s)?',
      mensagem:
          'Os ${alvo.length} membros selecionados serão removidos do cadastro e de todas as listas. Esta ação não pode ser desfeita.',
    );
    if (!ok) return;
    for (final m in alvo) {
      _banco.excluirMembro(m);
    }
    _sairSelecao();
    widget.onSalvar();
    _snack('${alvo.length} membro(s) excluído(s).');
  }

  Future<void> _adicionarSelecionadosALista() async {
    final alvo = _selecionados();
    if (alvo.isEmpty) return;
    final lista = await escolherListaDialog(context, _banco);
    if (lista == null) return;
    var n = 0;
    for (final m in alvo) {
      if (!lista.membroIds.contains(m.id)) {
        lista.membroIds.add(m.id);
        n++;
      }
    }
    _sairSelecao();
    widget.onSalvar();
    _snack('$n membro(s) adicionado(s) a "${lista.titulo}".');
  }

  Future<void> _alterarClasseSelecionados() async {
    final alvo = _selecionados();
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

  Future<void> _alterarCongregacaoSelecionados() async {
    final alvo = _selecionados();
    if (alvo.isEmpty) return;
    final id =
        await escolherCongregacaoDialog(context, _banco, 'Congregação de ${alvo.length} membro(s)');
    if (id == null) return;
    final agora = DateTime.now().millisecondsSinceEpoch;
    for (final m in alvo) {
      m.congregacaoId = id;
      m.atualizadoEm = agora;
    }
    _sairSelecao();
    widget.onSalvar();
    _snack('Congregação alterada para ${alvo.length} membro(s).');
  }

  AppBar _appBarSelecao(List<Entidade> visiveis) {
    return AppBar(
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
              case 'lista':
                _adicionarSelecionadosALista();
                break;
              case 'classe':
                _alterarClasseSelecionados();
                break;
              case 'cong':
                _alterarCongregacaoSelecionados();
                break;
              case 'imprimir':
                imprimirComOpcoes(
                  context,
                  banco: _banco,
                  membros: visiveis.where((m) => _sel.contains(m.id)).toList(),
                  tituloInicial: 'Membros selecionados',
                  aviso: _snack,
                );
                break;
              case 'excluir':
                _excluirSelecionados();
                break;
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'lista', child: Text('Adicionar a uma lista')),
            PopupMenuItem(value: 'classe', child: Text('Alterar classe')),
            PopupMenuItem(value: 'cong', child: Text('Alterar congregação')),
            PopupMenuItem(value: 'imprimir', child: Text('Imprimir / relatório')),
            PopupMenuItem(value: 'excluir', child: Text('Excluir membros')),
          ],
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _filtro = FiltroMembros(ordem: _banco.ordemMembros);
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
    if (_banco.ordemMembros != _filtro.ordem) {
      _banco.ordemMembros = _filtro.ordem;
      widget.onSalvar();
    }
  }

  // ------------------------------------------------------------------ ações

  Future<void> _novo() async {
    final novo = await abrirFormularioMembro(
      context,
      _banco,
      congregacaoInicial: _filtro.congregacoes.length == 1 ? _filtro.congregacoes.first : '',
    );
    if (novo == null) return;
    _banco.salvarMembro(novo);
    widget.onSalvar();
  }

  Future<void> _editar(Entidade m) async {
    final novo = await abrirFormularioMembro(context, _banco, existente: m);
    if (novo == null) return;
    _banco.salvarMembro(novo);
    widget.onSalvar();
  }

  Future<void> _excluir(Entidade m) async {
    final n = _banco.listasDoMembro(m);
    final ok = await confirmar(
      context,
      titulo: 'Excluir membro?',
      mensagem: n > 0
          ? '"${m.nome}" será removido do cadastro e de $n lista(s). Esta ação não pode ser desfeita.'
          : '"${m.nome}" será removido do cadastro. Esta ação não pode ser desfeita.',
    );
    if (!ok) return;
    _banco.excluirMembro(m);
    widget.onSalvar();
  }

  void _imprimirFicha(Entidade m) {
    imprimirComOpcoes(
      context,
      banco: _banco,
      membros: [m],
      tituloInicial: 'Ficha cadastral',
      ficha: true,
      aviso: _snack,
    );
  }

  void _relatorio(List<Entidade> visiveis) {
    imprimirComOpcoes(
      context,
      banco: _banco,
      membros: visiveis,
      tituloInicial: tituloComFiltro(_banco, 'Membros', _filtro),
      aviso: _snack,
    );
  }

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
        final novo = Banco.fromJson(lido.bancoCompleto!);
        if (!mounted) return;
        final ok = await confirmar(
          context,
          titulo: 'Restaurar backup completo?',
          mensagem:
              'Isto SUBSTITUI tudo o que está no app agora (${_banco.membros.length} membros, ${_banco.listas.length} listas) '
              'pelo conteúdo do backup (${novo.membros.length} membros, ${novo.listas.length} listas). Esta ação não pode ser desfeita.',
          acao: 'Restaurar',
        );
        if (!ok) return;
        _banco.substituirPor(novo);
        widget.onSalvar();
        _snack('Backup restaurado: ${novo.membros.length} membro(s), ${novo.listas.length} lista(s).');
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
        _banco.listas.remove(lista); // aqui só interessam os membros
        widget.onSalvar();
        _snack('Backup importado: ${lista.membroIds.length} membro(s).');
        return;
      }

      final resumo = Importador.aplicar(_banco, lido);
      widget.onSalvar();
      _snack(resumo.mensagem);
    } catch (e) {
      _snack('Erro ao importar: $e');
    }
  }

  void _exportar() {
    final json = jsonEncode({
      'tipo': 'membros_ibmmkar',
      'membros': _banco.membros.map((m) => m.toJson()).toList(),
      'congregacoes': _banco.congregacoes.map((c) => c.toJson()).toList(),
      'colunas': _banco.colunas.map((c) => c.toJson()).toList(),
      'classes': _banco.classes.map((c) => c.toJson()).toList(),
    });
    mostrarExportacao(context, 'Exportar membros (JSON)', json);
  }

  /// Backup completo: gera um arquivo .json e abre o compartilhamento do sistema
  /// (Drive, WhatsApp, e-mail...). Para restaurar: Importar e escolher o arquivo.
  Future<void> _backupCompleto() async {
    final json = jsonEncode({'tipo': 'banco_ibmmkar', 'banco': _banco.toJson()});
    try {
      final dir = await getTemporaryDirectory();
      final h = DateTime.now();
      final nome =
          'ibmmkar_backup_${h.year}${h.month.toString().padLeft(2, '0')}${h.day.toString().padLeft(2, '0')}.json';
      final arquivo = File('${dir.path}/$nome');
      await arquivo.writeAsString(json);
      await Share.shareXFiles([XFile(arquivo.path)], text: 'Backup IBMMKAR');
    } catch (e) {
      // Sem compartilhamento disponível: mostra o texto para copiar.
      if (mounted) mostrarExportacao(context, 'Backup completo (JSON)', json);
    }
  }

  void _congregacoes() {
    mostrarGerenciarCongregacoes(context, _banco, () {
      setState(() {});
      widget.onSalvar();
    });
  }

  void _classes() {
    mostrarClasses(context, _banco, () {
      setState(() {});
      widget.onSalvar();
    });
  }

  /// Lembrete: aniversariantes de hoje e dos próximos 7 dias.
  Widget _bannerAniversarios() {
    final hoje = aniversariantesDeHoje(_banco);
    final prox = aniversariantesProximos(_banco, dias: 7);
    if (hoje.isEmpty && prox == 0) return const SizedBox.shrink();

    final esquema = Theme.of(context).colorScheme;
    final agora = DateTime.now();
    final nomes = hoje.map((m) {
      final i = m.idadeNoProximoAniversario(agora);
      return i == null ? m.nome : '${m.nome} ($i)';
    }).join(', ');
    final texto = hoje.isNotEmpty
        ? 'Aniversariantes de hoje: $nomes${prox > 0 ? ' · mais $prox nos próximos 7 dias' : ''}'
        : '$prox aniversariante(s) nos próximos 7 dias';

    return InkWell(
      onTap: widget.onVerAniversarios,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: esquema.primary.withOpacity(0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: esquema.primary.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.cake, color: esquema.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(texto,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  void _camposExtras() {
    mostrarCamposExtras(context, _banco, () {
      setState(() {});
      widget.onSalvar();
    });
  }

  Widget _menuMembro(Entidade m) {
    return PopupMenuButton<String>(
      tooltip: 'Ações',
      onSelected: (v) {
        if (v == 'editar') _editar(m);
        if (v == 'ficha') _imprimirFicha(m);
        if (v == 'excluir') _excluir(m);
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'editar', child: Text('Editar')),
        PopupMenuItem(value: 'ficha', child: Text('Imprimir ficha')),
        PopupMenuItem(value: 'excluir', child: Text('Excluir membro')),
      ],
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final todos = _banco.membros;
    final visiveis = _filtro.aplicar(_banco, todos);
    final esquema = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: _modoSel
          ? _appBarSelecao(visiveis)
          : AppBar(
        title: const Text('Membros'),
        actions: [
          IconButton(
            icon: const Icon(Icons.checklist),
            tooltip: 'Selecionar vários',
            onPressed: () => _entrarSelecao(),
          ),
          IconButton(
            icon: const Icon(Icons.description_outlined),
            tooltip: 'Gerador de relatórios',
            onPressed: () => _relatorio(visiveis),
          ),
          IconButton(
            icon: const Icon(Icons.brightness_6_outlined),
            tooltip: 'Aparência (claro / escuro)',
            onPressed: widget.onAparencia,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'importar':
                  _importar();
                  break;
                case 'congs':
                  _congregacoes();
                  break;
                case 'classes':
                  _classes();
                  break;
                case 'campos':
                  _camposExtras();
                  break;
                case 'backup':
                  _backupCompleto();
                  break;
                case 'json':
                  _exportar();
                  break;
                case 'pdf':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OpcoesImpressaoPage(banco: _banco, modoConfig: true),
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'importar', child: Text('Importar / restaurar backup (JSON, CSV, TXT)')),
              PopupMenuItem(value: 'congs', child: Text('Congregações e cores')),
              PopupMenuItem(value: 'classes', child: Text('Classes da EBD')),
              PopupMenuItem(value: 'campos', child: Text('Campos extras')),
              PopupMenuItem(value: 'backup', child: Text('Backup completo (compartilhar arquivo)')),
              PopupMenuItem(value: 'json', child: Text('Exportar membros (JSON)')),
              PopupMenuItem(value: 'pdf', child: Text('Opções de impressão')),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (ctx, c) {
          final largo = c.maxWidth >= 820;

          Widget conteudo;
          if (todos.isEmpty) {
            conteudo = const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nenhum membro cadastrado.\nToque em "Novo membro" ou importe um arquivo (JSON, CSV ou TXT).',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          } else if (visiveis.isEmpty) {
            conteudo = const Center(child: Text('Nenhum membro encontrado com esses filtros.'));
          } else if (largo) {
            conteudo = gradeMembros(
              banco: _banco,
              membros: visiveis,
              corGrade: kCorPadrao,
              corPadrao: kCorSemCong,
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
              itemBuilder: (_, i) {
                final m = visiveis[i];
                return MembroCard(
                  banco: _banco,
                  membro: m,
                  corPadrao: kCorSemCong,
                  selecionado: _modoSel && _sel.contains(m.id),
                  leading: _modoSel
                      ? Checkbox(value: _sel.contains(m.id), onChanged: (_) => _alternar(m))
                      : null,
                  onTap: _modoSel ? () => _alternar(m) : () => _editar(m),
                  onLongPress: _modoSel ? null : () => _entrarSelecao(m),
                  trailing: _modoSel ? null : _menuMembro(m),
                );
              },
            );
          }

          return Column(
            children: [
              _bannerAniversarios(),
              DashboardCongregacoes(banco: _banco, origem: todos, corPadrao: kCorSemCong),
              PainelBuscaFiltros(
                banco: _banco,
                filtro: _filtro,
                buscaCtrl: _buscaCtrl,
                origem: todos,
                onMudou: _aoMudar,
                onEditarCongregacoes: _congregacoes,
                corPadrao: kCorSemCong,
              ),
              if (todos.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      visiveis.length == todos.length
                          ? '${todos.length} membro(s)'
                          : '${visiveis.length} de ${todos.length} membro(s)',
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
          : FloatingActionButton.extended(
        onPressed: _novo,
        icon: const Icon(Icons.person_add),
        label: const Text('Novo membro'),
      ),
    );
  }
}
