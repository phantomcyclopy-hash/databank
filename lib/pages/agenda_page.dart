import 'package:flutter/material.dart';

import '../calendario.dart';
import '../models.dart';
import '../nuvem/sync_service.dart';
import '../widgets/compromisso_tile.dart';
import '../widgets/mural_dialogs.dart';

/// Agenda em calendário mensal: compromissos, aniversários e datas comemorativas.
class AgendaPage extends StatefulWidget {
  final Banco banco;
  final VoidCallback onSalvar;

  const AgendaPage({super.key, required this.banco, required this.onSalvar});

  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage> {
  late DateTime _mes; // primeiro dia do mês exibido (UTC)
  late DateTime _sel; // dia selecionado (UTC)

  Banco get _banco => widget.banco;

  @override
  void initState() {
    super.initState();
    final h = soData(DateTime.now());
    _sel = h;
    _mes = DateTime.utc(h.year, h.month, 1);
  }

  void _mudarMes(int delta) => setState(() {
        _mes = DateTime.utc(_mes.year, _mes.month + delta, 1);
      });

  void _irParaHoje() => setState(() {
        final h = soData(DateTime.now());
        _sel = h;
        _mes = DateTime.utc(h.year, h.month, 1);
      });

  void _mudou() {
    setState(() {});
    widget.onSalvar();
  }

  List<Compromisso> _compromissosDo(DateTime d) {
    final veTudo = Sync.instance.veTudo;
    final l = _banco.compromissos
        .where((c) => c.ocorreEm(d) && (c.tipo == 'evento' || veTudo))
        .toList();
    l.sort((a, b) => (a.hora < 0 ? 9999 : a.hora).compareTo(b.hora < 0 ? 9999 : b.hora));
    return l;
  }

  List<Entidade> _aniversariosDo(DateTime d) => _banco.ativos.where((m) {
        final n = m.dataNascimento;
        return n != null && n.month == d.month && n.day == d.day;
      }).toList();

  Future<void> _novo(String tipo) async {
    final novo = await formCompromisso(context, tipo: tipo, dataInicial: _sel);
    if (novo == null) return;
    _banco.compromissos.add(novo);
    _mudou();
  }

  Widget _ponto(Color cor) => Container(
        width: 6,
        height: 6,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
      );

  Widget _celula(DateTime d, ColorScheme e, DateTime hoje) {
    final eHoje = d == hoje;
    final selecionado = d == _sel;
    final temC = _compromissosDo(d).isNotEmpty;
    final temA = Sync.instance.veTudo && _aniversariosDo(d).isNotEmpty;
    final temD = comemorativasNoDia(_banco, d).isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _sel = d),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: selecionado ? e.primary.withOpacity(0.15) : null,
          borderRadius: BorderRadius.circular(8),
          border: eHoje ? Border.all(color: e.primary, width: 1.5) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${d.day}',
                style: TextStyle(
                    fontWeight: eHoje || selecionado ? FontWeight.w700 : FontWeight.w400)),
            const SizedBox(height: 3),
            SizedBox(
              height: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (temC) _ponto(e.primary),
                  if (temA) _ponto(Colors.pink),
                  if (temD) _ponto(Colors.orange),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = Theme.of(context).colorScheme;
    final hoje = soData(DateTime.now());

    final offset = _mes.weekday % 7; // domingo = 0
    final diasNoMes = DateTime.utc(_mes.year, _mes.month + 1, 0).day;
    final celulas = <Widget>[
      for (var i = 0; i < offset; i++) const SizedBox.shrink(),
      for (var dia = 1; dia <= diasNoMes; dia++)
        _celula(DateTime.utc(_mes.year, _mes.month, dia), e, hoje),
    ];

    final compromissos = _compromissosDo(_sel);
    final aniversarios = Sync.instance.veTudo ? _aniversariosDo(_sel) : <Entidade>[];
    final edita = Sync.instance.podeEditar;
    final datas = comemorativasNoDia(_banco, _sel);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda'),
        actions: [
          TextButton(
            onPressed: _irParaHoje,
            child: const Text('Hoje'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'Mês anterior',
                    onPressed: () => _mudarMes(-1)),
                Expanded(
                  child: Text(
                    '${kMeses[_mes.month - 1]} ${_mes.year}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'Próximo mês',
                    onPressed: () => _mudarMes(1)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final s in const ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'])
                  Expanded(
                    child: Center(
                      child: Text(s,
                          style: TextStyle(fontSize: 12, color: e.onSurfaceVariant)),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.15,
              children: celulas,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: Row(
              children: [
                _ponto(e.primary),
                const Text(' compromissos   ', style: TextStyle(fontSize: 11)),
                _ponto(Colors.pink),
                const Text(' aniversários   ', style: TextStyle(fontSize: 11)),
                _ponto(Colors.orange),
                const Text(' datas comemorativas', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 88),
              children: [
                Text(dataPorExtenso(_sel),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                if (compromissos.isEmpty && aniversarios.isEmpty && datas.isEmpty)
                  Text('Nada marcado para este dia.',
                      style: TextStyle(color: e.onSurfaceVariant)),
                ...datas.map((d) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.celebration, color: Colors.orange),
                      title: Text(d.nome),
                      subtitle: d.daIgreja ? const Text('Data da igreja') : null,
                    )),
                ...aniversarios.map((m) {
                  final n = m.dataNascimento!;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.cake, color: Colors.pink),
                    title: Text(m.nome),
                    subtitle: Text('Aniversário · ${_sel.year - n.year} anos'),
                  );
                }),
                ...compromissos.map((c) => CompromissoTile(
                      banco: _banco,
                      compromisso: c,
                      dia: _sel,
                      mostrarData: false,
                      aoMudar: _mudou,
                      somenteLeitura: !edita,
                    )),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: !edita
          ? null
          : PopupMenuButton<String>(
        onSelected: _novo,
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'evento', child: Text('Novo evento neste dia')),
          PopupMenuItem(value: 'lembrete', child: Text('Novo lembrete neste dia')),
        ],
        child: Material(
          color: e.primaryContainer,
          borderRadius: BorderRadius.circular(8),
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, color: e.onPrimaryContainer),
                const SizedBox(width: 8),
                Text('Adicionar', style: TextStyle(color: e.onPrimaryContainer)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
