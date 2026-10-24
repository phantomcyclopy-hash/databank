import 'dart:convert';

import 'package:flutter/material.dart';

import '../models.dart';

const List<String> kSexos = ['Masculino', 'Feminino', 'N/A'];
const List<String> kSangues = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'N/A'];

const Map<String, String> kFaixas = {
  'crianca': 'Crianças (0–12)',
  'adolescente': 'Adolescentes (13–17)',
  'jovem': 'Jovens (18–29)',
  'adulto': 'Adultos (30–59)',
  'idoso': 'Idosos (60+)',
};

const Map<String, String> kOrdens = {
  'manual': 'Ordem da lista (manual)',
  'az': 'Ordem alfabética (A → Z)',
  'za': 'Ordem alfabética (Z → A)',
  'editados': 'Editados recentemente',
  'cadastro': 'Cadastrados recentemente',
  'aniversario': 'Data de aniversário (jan → dez)',
};

// ---------------------------------------------------------------------------
// Filtro (busca + categorias combináveis + ordem)
// ---------------------------------------------------------------------------

class FiltroMembros {
  String busca = '';
  final Set<String> congregacoes = {}; // ids; '' = sem congregação
  final Set<String> sexos = {};
  final Set<String> sangues = {};
  final Set<String> faixas = {};
  final Set<String> classes = {}; // ids de classe; '' = sem classe
  final Set<String> assinatura = {}; // 'sim' = requer assinatura
  final Set<String> fotos = {}; // 'com' | 'sem'
  final Set<String> campos = {}; // ids de campos extras marcados (checkbox)

  /// true = o membro precisa passar em TODAS as categorias marcadas (E);
  /// false = basta passar em UMA (OU).
  bool combinarE = true;

  /// Desligados ficam escondidos, a menos que se peça para mostrá-los.
  bool mostrarDesligados = false;
  String ordem;

  FiltroMembros({this.ordem = 'az'});

  int get categoriasAtivas => (mostrarDesligados ? 1 : 0) + [congregacoes, sexos, sangues, faixas, classes, assinatura, fotos, campos]
      .where((s) => s.isNotEmpty)
      .length;

  bool get ativo => busca.trim().isNotEmpty || categoriasAtivas > 0;

  void limparCategorias() {
    congregacoes.clear();
    sexos.clear();
    sangues.clear();
    faixas.clear();
    classes.clear();
    mostrarDesligados = false;
    assinatura.clear();
    fotos.clear();
    campos.clear();
  }

  static String? faixaDe(String idade) {
    final n = int.tryParse(idade.trim());
    if (n == null || n < 0) return null;
    if (n <= 12) return 'crianca';
    if (n <= 17) return 'adolescente';
    if (n <= 29) return 'jovem';
    if (n <= 59) return 'adulto';
    return 'idoso';
  }

  bool _passaCong(Banco banco, Entidade m) {
    final ef = banco.congregacaoEfetiva(m);
    if (congregacoes.contains(ef)) return true;
    // Multicongregacional "serve para todas": aparece ao filtrar por qualquer
    // congregação real, se a opção estiver ligada.
    if (banco.multiEmTodas &&
        ef == kMultiId &&
        congregacoes.any((id) => id.isNotEmpty && id != kMultiId)) {
      return true;
    }
    return false;
  }

  List<Entidade> aplicar(Banco banco, Iterable<Entidade> origem) {
    // Esquece filtros de congregações que foram removidas.
    congregacoes.removeWhere((id) => id.isNotEmpty && banco.congregacaoPorId(id) == null);
    campos.removeWhere((id) => !banco.colunas.any((c) => c.id == id));
    classes.removeWhere((id) => id.isNotEmpty && banco.classePorId(id) == null);

    final q = normalizarTexto(busca);
    final r = origem.where((m) {
      if (q.isNotEmpty && !normalizarTexto(m.nome).contains(q)) return false;
      if (!m.ativo && !mostrarDesligados) return false;

      final criterios = <bool>[];
      if (congregacoes.isNotEmpty) criterios.add(_passaCong(banco, m));
      if (sexos.isNotEmpty) criterios.add(sexos.contains(m.sexo));
      if (sangues.isNotEmpty) criterios.add(sangues.contains(m.tipoSanguineo));
      if (faixas.isNotEmpty) {
        final f = faixaDe(m.idadeExibida);
        criterios.add(f != null && faixas.contains(f));
      }
      if (classes.isNotEmpty) criterios.add(classes.contains(banco.classeEfetiva(m)));
      if (assinatura.isNotEmpty) criterios.add(m.requerAssinatura);
      if (fotos.isNotEmpty) {
        final tem = m.fotoBase64 != null && m.fotoBase64!.isNotEmpty;
        criterios.add(fotos.contains(tem ? 'com' : 'sem'));
      }
      if (campos.isNotEmpty) {
        criterios.add(campos.any((id) => m.valoresAtributosDinamicos[id] == 'true'));
      }
      if (criterios.isEmpty) return true;
      return combinarE ? criterios.every((c) => c) : criterios.any((c) => c);
    }).toList();

    int porNome(Entidade a, Entidade b) =>
        normalizarTexto(a.nome).compareTo(normalizarTexto(b.nome));

    switch (ordem) {
      case 'manual':
        break; // mantém a ordem recebida (ordem da lista)
      case 'za':
        r.sort((a, b) => porNome(b, a));
        break;
      case 'editados':
        r.sort((a, b) {
          final c = b.atualizadoEm.compareTo(a.atualizadoEm);
          return c != 0 ? c : porNome(a, b);
        });
        break;
      case 'cadastro':
        r.sort((a, b) {
          final c = b.criadoEm.compareTo(a.criadoEm);
          return c != 0 ? c : porNome(a, b);
        });
        break;
      case 'aniversario':
        int chave(Entidade e) {
          final n = e.dataNascimento;
          return n == null ? 9999 : n.month * 100 + n.day;
        }
        r.sort((a, b) {
          final c = chave(a).compareTo(chave(b));
          return c != 0 ? c : porNome(a, b);
        });
        break;
      default:
        r.sort(porNome);
    }
    return r;
  }
}

/// "Título" ou "Título (Sede, Bracuí)" quando há filtro de congregação.
String tituloComFiltro(Banco banco, String base, FiltroMembros f) {
  if (f.congregacoes.isEmpty) return base;
  final nomes = f.congregacoes
      .map((id) => id.isEmpty ? 'Sem congregação' : (banco.congregacaoPorId(id)?.nome ?? ''))
      .where((n) => n.isNotEmpty)
      .join(', ');
  return nomes.isEmpty ? base : '$base ($nomes)';
}

// ---------------------------------------------------------------------------
// Peças visuais
// ---------------------------------------------------------------------------

Widget avatarMembro(Entidade m, double raio, {Color? borda}) {
  final temFoto = m.fotoBase64 != null && m.fotoBase64!.isNotEmpty;
  ImageProvider? img;
  if (temFoto) {
    try {
      img = MemoryImage(base64Decode(m.fotoBase64!));
    } catch (_) {
      img = null;
    }
  }
  final avatar = CircleAvatar(
    radius: raio,
    backgroundColor: Colors.blueGrey.shade200,
    backgroundImage: img,
    child: img == null ? Icon(Icons.person, size: raio, color: Colors.blueGrey.shade700) : null,
  );
  if (borda == null) return avatar;
  return Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: borda, width: 2)),
    child: avatar,
  );
}

Widget bolinha(Color cor, [double tamanho = 10]) => Container(
      width: tamanho,
      height: tamanho,
      decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
    );

class MembroCard extends StatelessWidget {
  final Banco banco;
  final Entidade membro;
  final Color corPadrao;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final Widget? leading;
  final String? etiqueta;
  final bool selecionado;

  const MembroCard({
    super.key,
    required this.banco,
    required this.membro,
    required this.corPadrao,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.leading,
    this.etiqueta,
    this.selecionado = false,
  });

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final secundario = TextStyle(fontSize: 12, color: esquema.onSurfaceVariant);
    final cor = banco.corDaCongregacao(membro, corPadrao);
    final cong = banco.congregacaoPorId(membro.congregacaoId);
    final classe = banco.classePorId(membro.classe);
    final idadeTxt = membro.idadeExibida;
    final partes = <String>[
      if (cong != null) cong.nome,
      if (classe != null) 'Classe: ${classe.nome}',
      if (idadeTxt.isNotEmpty) '$idadeTxt anos',
    ];

    final extras = banco.colunas
        .map((c) => MapEntry(c, c.exibir(membro.valoresAtributosDinamicos[c.id])))
        .where((e) => e.value.isNotEmpty && !(e.key.tipo == 'checkbox' && e.value == 'Não'))
        .take(2)
        .map((e) => '${e.key.nome}: ${e.value}')
        .join(' · ');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: selecionado ? esquema.primary.withOpacity(0.12) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selecionado ? esquema.primary : esquema.outlineVariant,
          width: selecionado ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: cor),
              if (leading != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Center(child: leading!),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
                  child: Row(
                    children: [
                      avatarMembro(membro, 22, borda: cor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(membro.nome,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600, fontSize: 15)),
                                ),
                                if (membro.requerAssinatura)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Tooltip(
                                      message: 'Requer assinatura',
                                      child: Icon(Icons.draw, size: 15, color: esquema.primary),
                                    ),
                                  ),
                              ],
                            ),
                            if (partes.isNotEmpty)
                              Row(
                                children: [
                                  if (cong != null) ...[
                                    bolinha(cor, 8),
                                    const SizedBox(width: 5),
                                  ],
                                  Flexible(
                                    child: Text(
                                      partes.join(' · '),
                                      style: secundario,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            if (membro.contato.isNotEmpty)
                              Text(membro.contato, style: secundario),
                            if (extras.isNotEmpty) Text(extras, style: secundario),
                            if (etiqueta != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(etiqueta!,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: esquema.primary)),
                              ),
                          ],
                        ),
                      ),
                      if (trailing != null) trailing!,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Faixa de totais: total + um cartão por congregação (da lista passada).
class DashboardCongregacoes extends StatelessWidget {
  final Banco banco;
  final Iterable<Entidade> origem;
  final Color corPadrao;

  const DashboardCongregacoes({
    super.key,
    required this.banco,
    required this.origem,
    required this.corPadrao,
  });

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final itens = origem.toList();
    final semCong = banco.contar(itens, '');

    Widget cartao(String rotulo, int n, Color cor) => Container(
          width: 116,
          margin: const EdgeInsets.only(right: 8),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: esquema.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: esquema.outlineVariant),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: cor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$n',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                        Text(rotulo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: esquema.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

    return SizedBox(
      height: 68,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
        children: [
          cartao('Total', itens.length, corPadrao),
          ...banco.todasCongregacoes.map((c) => cartao(
                c.nome,
                banco.contar(itens, c.id),
                corDeHex(c.cor, padrao: corPadrao),
              )),
          if (semCong > 0) cartao('Sem congregação', semCong, Colors.grey),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Busca + ordem + filtros
// ---------------------------------------------------------------------------

class PainelBuscaFiltros extends StatelessWidget {
  final Banco banco;
  final FiltroMembros filtro;
  final TextEditingController buscaCtrl;
  final Iterable<Entidade> origem;
  final VoidCallback onMudou;
  final VoidCallback? onEditarCongregacoes;
  final Color corPadrao;
  final bool mostrarOrdem;
  final bool permitirManual;

  const PainelBuscaFiltros({
    super.key,
    required this.banco,
    required this.filtro,
    required this.buscaCtrl,
    required this.origem,
    required this.onMudou,
    required this.corPadrao,
    this.onEditarCongregacoes,
    this.mostrarOrdem = true,
    this.permitirManual = false,
  });

  @override
  Widget build(BuildContext context) {
    final temSem = origem.any((m) => banco.congregacaoEfetiva(m).isEmpty);

    Widget chip(String id, String nome, Color cor) {
      final sel = filtro.congregacoes.contains(id);
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          avatar: bolinha(cor, 12),
          label: Text(nome),
          selected: sel,
          selectedColor: cor.withOpacity(0.25),
          onSelected: (v) {
            v ? filtro.congregacoes.add(id) : filtro.congregacoes.remove(id);
            onMudou();
          },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: buscaCtrl,
                  decoration: InputDecoration(
                    hintText: 'Buscar por nome',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    suffixIcon: filtro.busca.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              buscaCtrl.clear();
                              filtro.busca = '';
                              onMudou();
                            },
                          ),
                  ),
                  onChanged: (v) {
                    filtro.busca = v;
                    onMudou();
                  },
                ),
              ),
              if (mostrarOrdem)
              PopupMenuButton<String>(
                icon: const Icon(Icons.sort),
                tooltip: 'Ordenar: ${kOrdens[filtro.ordem] ?? ''}',
                onSelected: (v) {
                  filtro.ordem = v;
                  onMudou();
                },
                itemBuilder: (_) => kOrdens.entries
                    .where((e) => permitirManual || e.key != 'manual')
                    .map((e) => CheckedPopupMenuItem<String>(
                          value: e.key,
                          checked: filtro.ordem == e.key,
                          child: Text(e.value),
                        ))
                    .toList(),
              ),
              IconButton(
                tooltip: 'Filtros',
                icon: Badge(
                  isLabelVisible: filtro.categoriasAtivas > 0,
                  label: Text('${filtro.categoriasAtivas}'),
                  child: const Icon(Icons.filter_list),
                ),
                onPressed: () => mostrarFiltrosAvancados(context, banco, filtro, onMudou),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ...banco.todasCongregacoes
                    .map((c) => chip(c.id, c.nome, corDeHex(c.cor, padrao: corPadrao))),
                if (temSem) chip('', 'Sem congregação', Colors.grey),
                if (onEditarCongregacoes != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: const Icon(Icons.edit, size: 16),
                      label: const Text('Congregações'),
                      onPressed: onEditarCongregacoes,
                    ),
                  ),
                if (filtro.categoriasAtivas > 0)
                  TextButton(
                    onPressed: () {
                      filtro.limparCategorias();
                      onMudou();
                    },
                    child: const Text('Limpar filtros'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> mostrarFiltrosAvancados(
  BuildContext context,
  Banco banco,
  FiltroMembros f,
  VoidCallback onMudou,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        Widget grupo(String titulo, List<MapEntry<String, String>> opcoes, Set<String> sel) {
          return Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
                Wrap(
                  children: opcoes
                      .map((e) => SizedBox(
                            width: 180,
                            child: CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(e.value, overflow: TextOverflow.ellipsis),
                              value: sel.contains(e.key),
                              onChanged: (v) {
                                setS(() {
                                  v == true ? sel.add(e.key) : sel.remove(e.key);
                                });
                                onMudou();
                              },
                            ),
                          ))
                      .toList(),
                ),
              ],
            ),
          );
        }

        final checkboxes = banco.colunas.where((c) => c.tipo == 'checkbox').toList();

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Filtros', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    'Marque as caixas para filtrar. Dentro de um grupo, vale qualquer uma marcada.',
                    style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Combinar (E)')),
                      ButtonSegment(value: false, label: Text('Qualquer (OU)')),
                    ],
                    selected: {f.combinarE},
                    onSelectionChanged: (s) {
                      setS(() => f.combinarE = s.first);
                      onMudou();
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      f.combinarE
                          ? 'Mostra só quem atende a todos os grupos marcados.'
                          : 'Mostra quem atende a pelo menos um dos grupos marcados.',
                      style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ),
                  grupo(
                    'Congregação',
                    [
                      ...banco.todasCongregacoes.map((c) => MapEntry(c.id, c.nome)),
                      const MapEntry('', 'Sem congregação'),
                    ],
                    f.congregacoes,
                  ),
                  grupo('Sexo', kSexos.map((s) => MapEntry(s, s)).toList(), f.sexos),
                  grupo('Tipo sanguíneo', kSangues.map((s) => MapEntry(s, s)).toList(), f.sangues),
                  grupo('Faixa etária', kFaixas.entries.toList(), f.faixas),
                  grupo(
                    'Classe (EBD)',
                    [
                      ...banco.classes.map((c) => MapEntry(c.id, c.nome)),
                      const MapEntry('', 'Sem classe'),
                    ],
                    f.classes,
                  ),
                  grupo('Assinatura', const [MapEntry('sim', 'Requer assinatura')], f.assinatura),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Mostrar membros desligados'),
                    value: f.mostrarDesligados,
                    onChanged: (v) {
                      setS(() => f.mostrarDesligados = v ?? false);
                      onMudou();
                    },
                  ),
                  grupo('Foto', const [MapEntry('com', 'Com foto'), MapEntry('sem', 'Sem foto')], f.fotos),
                  if (checkboxes.isNotEmpty)
                    grupo('Campos extras marcados',
                        checkboxes.map((c) => MapEntry(c.id, c.nome)).toList(), f.campos),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          setS(f.limparCategorias);
                          onMudou();
                        },
                        child: const Text('Limpar filtros'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Concluir'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// Grade (computador)
// ---------------------------------------------------------------------------

Widget gradeMembros({
  required Banco banco,
  required List<Entidade> membros,
  required Color corGrade,
  required Color corPadrao,
  required void Function(Entidade) onTap,
  required Widget Function(Entidade) acoes,
  Set<String>? selecionados, // != null liga o modo de seleção (caixas na tabela)
  void Function(Entidade, bool)? onSelecionar,
  void Function(bool)? onSelecionarTodos,
}) {
  TextStyle negrito() => const TextStyle(fontWeight: FontWeight.bold);

  return SingleChildScrollView(
    padding: const EdgeInsets.only(bottom: 88),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DataTable(
          showCheckboxColumn: selecionados != null,
          onSelectAll: selecionados == null ? null : (v) => onSelecionarTodos?.call(v ?? false),
          headingRowColor: MaterialStateProperty.all(corGrade.withOpacity(0.18)),
          border: TableBorder.all(color: corGrade.withOpacity(0.5), width: 1),
          columns: [
            DataColumn(label: Text('', style: negrito())),
            DataColumn(label: Text('Foto', style: negrito())),
            DataColumn(label: Text('Nome', style: negrito())),
            DataColumn(label: Text('Congregação', style: negrito())),
            DataColumn(label: Text('Idade', style: negrito())),
            DataColumn(label: Text('Nascimento', style: negrito())),
            DataColumn(label: Text('Classe', style: negrito())),
            DataColumn(label: Text('CPF / RG', style: negrito())),
            DataColumn(label: Text('Contato', style: negrito())),
            ...banco.colunas.map((c) => DataColumn(label: Text(c.nome, style: negrito()))),
            DataColumn(label: Text('Ações', style: negrito())),
          ],
          rows: membros.map((m) {
            final cor = banco.corDaCongregacao(m, corPadrao);
            final cong = banco.congregacaoPorId(m.congregacaoId);
            return DataRow(
              selected: selecionados?.contains(m.id) ?? false,
              onSelectChanged:
                  selecionados == null ? null : (v) => onSelecionar?.call(m, v ?? false),
              color: MaterialStateProperty.all(cor.withOpacity(0.07)),
              cells: [
                DataCell(bolinha(cor, 14)),
                DataCell(avatarMembro(m, 16)),
                DataCell(
                  Text(m.nome, style: const TextStyle(fontWeight: FontWeight.w500)),
                  onTap: selecionados == null ? () => onTap(m) : null,
                ),
                DataCell(Text(cong?.nome ?? '-')),
                DataCell(Text(m.idadeExibida.isEmpty ? '-' : m.idadeExibida)),
                DataCell(Text(m.dataNascimento == null ? '-' : dataBr(m.dataNascimento!))),
                DataCell(Text(banco.classePorId(m.classe)?.nome ?? '-')),
                DataCell(Text(m.documento)),
                DataCell(Text(m.contato)),
                ...banco.colunas.map((c) {
                  final v = c.exibir(m.valoresAtributosDinamicos[c.id]);
                  return DataCell(Text(v.isEmpty ? '-' : v));
                }),
                DataCell(acoes(m)),
              ],
            );
          }).toList(),
        ),
      ),
    ),
  );
}


// ---------------------------------------------------------------------------
// Aniversários
// ---------------------------------------------------------------------------

List<Entidade> aniversariantesDeHoje(Banco banco) {
  final h = DateTime.now();
  return banco.ativos.where((m) => m.diasParaAniversario(h) == 0).toList();
}

int aniversariantesProximos(Banco banco, {int dias = 7}) {
  final h = DateTime.now();
  return banco.ativos.where((m) {
    final d = m.diasParaAniversario(h);
    return d != null && d >= 1 && d <= dias;
  }).length;
}

String _ddmm(Entidade m) {
  final n = m.dataNascimento;
  if (n == null) return '';
  return '${n.day.toString().padLeft(2, '0')}/${n.month.toString().padLeft(2, '0')}';
}

/// "Hoje! Completa 35 anos", "Amanhã · 35 anos", "Em 3 dias (12/05) · 35 anos".
String descricaoAniversario(Entidade m, DateTime hoje) {
  final dias = m.diasParaAniversario(hoje);
  final idade = m.idadeNoProximoAniversario(hoje);
  if (dias == null) return '';
  final anos = idade == null ? '' : ' · completa $idade anos';
  if (dias == 0) return 'Hoje!$anos';
  if (dias == 1) return 'Amanhã (${_ddmm(m)})$anos';
  return 'Em $dias dias (${_ddmm(m)})$anos';
}
