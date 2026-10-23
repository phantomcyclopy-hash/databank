import 'package:flutter/material.dart';

import '../models.dart';
import '../widgets/form_membro.dart';
import '../widgets/membro_widgets.dart';
import 'opcoes_impressao_page.dart';

/// Lembrete de aniversariantes: hoje, próximos dias ou por mês.
class AniversariosPage extends StatefulWidget {
  final Banco banco;
  final VoidCallback onSalvar;
  final VoidCallback onAparencia;

  const AniversariosPage({
    super.key,
    required this.banco,
    required this.onSalvar,
    required this.onAparencia,
  });

  @override
  State<AniversariosPage> createState() => _AniversariosPageState();
}

class _AniversariosPageState extends State<AniversariosPage> {
  final FiltroMembros _filtro = FiltroMembros();
  final TextEditingController _buscaCtrl = TextEditingController();

  String _modo = 'proximos'; // proximos | mes
  int _dias = 30;
  int _mes = DateTime.now().month;

  Banco get _banco => widget.banco;

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _editar(Entidade m) async {
    final novo = await abrirFormularioMembro(context, _banco, existente: m);
    if (novo == null) return;
    _banco.salvarMembro(novo);
    widget.onSalvar();
  }

  void _imprimir(List<Entidade> itens) {
    imprimirComOpcoes(
      context,
      banco: _banco,
      membros: itens,
      tituloInicial: _modo == 'mes'
          ? 'Aniversariantes de ${kMeses[_mes - 1]}'
          : 'Aniversariantes (próximos $_dias dias)',
      layout: 'aniversariantes',
      aviso: _snack,
    );
  }

  String _etiqueta(Entidade m, DateTime hoje) {
    if (_modo == 'proximos') return descricaoAniversario(m, hoje);
    final n = m.dataNascimento!;
    final dd = n.day.toString().padLeft(2, '0');
    final mm = n.month.toString().padLeft(2, '0');
    final eHoje = m.diasParaAniversario(hoje) == 0;
    return '${eHoje ? 'Hoje! ' : ''}Dia $dd/$mm · ${hoje.year - n.year} anos em ${hoje.year}';
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final hoje = DateTime.now();

    final comData = _banco.membros.where((m) => m.dataNascimento != null).toList();
    final semData = _banco.membros.where((m) => m.dataNascimento == null).toList();
    final base = _filtro.aplicar(_banco, comData);

    int porNome(Entidade a, Entidade b) =>
        normalizarTexto(a.nome).compareTo(normalizarTexto(b.nome));

    List<Entidade> itens;
    if (_modo == 'proximos') {
      itens = base.where((m) {
        final d = m.diasParaAniversario(hoje);
        return d != null && d <= _dias;
      }).toList()
        ..sort((a, b) {
          final c = a.diasParaAniversario(hoje)!.compareTo(b.diasParaAniversario(hoje)!);
          return c != 0 ? c : porNome(a, b);
        });
    } else {
      itens = base.where((m) => m.dataNascimento!.month == _mes).toList()
        ..sort((a, b) {
          final c = a.dataNascimento!.day.compareTo(b.dataNascimento!.day);
          return c != 0 ? c : porNome(a, b);
        });
    }

    final aniversarioHoje = comData.where((m) => m.diasParaAniversario(hoje) == 0).toList();
    final textoHoje = aniversarioHoje.map((m) {
      final i = m.idadeNoProximoAniversario(hoje);
      return i == null ? m.nome : '${m.nome} ($i)';
    }).join(', ');

    final lista = <Widget>[
      if (itens.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            comData.isEmpty
                ? 'Nenhum membro tem data de nascimento cadastrada.\nEdite a ficha do membro para informar.'
                : 'Nenhum aniversariante neste período.',
            textAlign: TextAlign.center,
          ),
        ),
      ...itens.map((m) => MembroCard(
            banco: _banco,
            membro: m,
            corPadrao: kCorSemCong,
            etiqueta: _etiqueta(m, hoje),
            onTap: () => _editar(m),
          )),
      if (semData.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: esquema.outlineVariant),
            ),
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text('Sem data de nascimento (${semData.length})'),
              subtitle: const Text('Toque para completar o cadastro',
                  style: TextStyle(fontSize: 12)),
              children: semData
                  .map((m) => ListTile(
                        dense: true,
                        title: Text(m.nome),
                        subtitle: Text(_banco.congregacaoPorId(m.congregacaoId)?.nome ?? ''),
                        trailing: const Icon(Icons.edit, size: 18),
                        onTap: () => _editar(m),
                      ))
                  .toList(),
            ),
          ),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aniversários'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Imprimir lista exibida',
            onPressed: () => _imprimir(itens),
          ),
          IconButton(
            icon: const Icon(Icons.brightness_6_outlined),
            tooltip: 'Aparência (claro / escuro)',
            onPressed: widget.onAparencia,
          ),
        ],
      ),
      body: Column(
        children: [
          if (aniversarioHoje.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: esquema.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: esquema.primary.withOpacity(0.5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.cake, color: esquema.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Hoje: $textoHoje',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'proximos', label: Text('Próximos dias'), icon: Icon(Icons.upcoming)),
                  ButtonSegment(value: 'mes', label: Text('Por mês'), icon: Icon(Icons.calendar_month)),
                ],
                selected: {_modo},
                onSelectionChanged: (s) => setState(() => _modo = s.first),
              ),
            ),
          ),
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: _modo == 'proximos'
                  ? [
                      for (final d in const [7, 30, 60, 90])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('$d dias'),
                            selected: _dias == d,
                            onSelected: (_) => setState(() => _dias = d),
                          ),
                        ),
                    ]
                  : [
                      for (var i = 0; i < 12; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(kMeses[i].substring(0, 3)),
                            selected: _mes == i + 1,
                            onSelected: (_) => setState(() => _mes = i + 1),
                          ),
                        ),
                    ],
            ),
          ),
          PainelBuscaFiltros(
            banco: _banco,
            filtro: _filtro,
            buscaCtrl: _buscaCtrl,
            origem: comData,
            onMudou: () => setState(() {}),
            corPadrao: kCorSemCong,
            mostrarOrdem: false,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _modo == 'mes'
                    ? '${itens.length} aniversariante(s) em ${kMeses[_mes - 1]}'
                    : '${itens.length} aniversariante(s) nos próximos $_dias dias',
                style: TextStyle(fontSize: 12, color: esquema.onSurfaceVariant),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              children: lista,
            ),
          ),
        ],
      ),
    );
  }
}
