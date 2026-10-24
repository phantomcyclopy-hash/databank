import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../calendario.dart';
import '../models.dart';
import '../pdf_service.dart';
import '../storage.dart';
import '../widgets/compromisso_tile.dart';
import '../widgets/dialogos.dart';
import '../widgets/membro_widgets.dart';
import '../widgets/mural_dialogs.dart';
import '../nuvem/sync_service.dart';
import 'agenda_page.dart';
import 'nuvem_page.dart';

class _Ocorrencia {
  final DateTime dia;
  final Compromisso c;
  _Ocorrencia(this.dia, this.c);
}

/// Tela inicial: dia atual, avisos, agenda dos próximos dias, datas
/// comemorativas e aniversariantes do mês.
class MuralPage extends StatelessWidget {
  final Banco banco;
  final VoidCallback onSalvar;
  final VoidCallback onAparencia;
  final VoidCallback onAbrirAniversarios;

  const MuralPage({
    super.key,
    required this.banco,
    required this.onSalvar,
    required this.onAparencia,
    required this.onAbrirAniversarios,
  });

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ------------------------------------------------------------------ avisos

  Future<void> _novoAviso(BuildContext context) async {
    final a = await formAviso(context);
    if (a == null) return;
    banco.avisos.add(a);
    onSalvar();
  }

  Future<void> _editarAviso(BuildContext context, Aviso a) async {
    final novo = await formAviso(context, existente: a);
    if (novo == null) return;
    final i = banco.avisos.indexWhere((x) => x.id == novo.id);
    if (i >= 0) banco.avisos[i] = novo;
    onSalvar();
  }

  Future<void> _excluirAviso(BuildContext context, Aviso a) async {
    final ok = await confirmar(context,
        titulo: 'Excluir aviso?', mensagem: '"${a.titulo}" será apagado.');
    if (!ok) return;
    banco.avisos.removeWhere((x) => x.id == a.id);
    onSalvar();
  }

  Future<void> _limparExpirados(BuildContext context, int n) async {
    final ok = await confirmar(context,
        titulo: 'Apagar avisos expirados?',
        mensagem: '$n aviso(s) expirado(s) serão apagados.',
        acao: 'Apagar');
    if (!ok) return;
    final hoje = DateTime.now();
    banco.avisos.removeWhere((a) => a.expirado(hoje));
    onSalvar();
  }

  Future<void> _copiarAviso(BuildContext context, Aviso a) async {
    final texto = a.texto.isEmpty ? a.titulo : '${a.titulo}\n\n${a.texto}';
    await Clipboard.setData(ClipboardData(text: texto));
    if (context.mounted) _snack(context, 'Aviso copiado. Cole onde quiser enviar.');
  }

  Future<void> _imprimirAviso(BuildContext context, Aviso a) async {
    try {
      final bytes = await PdfService.aviso(aviso: a, cfg: AppStorage.instance.configPdf);
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'aviso.pdf');
    } catch (e) {
      if (context.mounted) _snack(context, 'Erro ao gerar PDF: $e');
    }
  }

  Widget _cartaoAviso(BuildContext context, Aviso a) {
    final e = Theme.of(context).colorScheme;
    final data = a.criadoEm > 0
        ? dataBr(DateTime.fromMillisecondsSinceEpoch(a.criadoEm))
        : '';
    Widget acao(IconData icone, String dica, VoidCallback f) => IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          tooltip: dica,
          icon: Icon(icone),
          onPressed: f,
        );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: a.fixado ? e.primary : e.outlineVariant, width: a.fixado ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (a.fixado)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.push_pin, size: 16, color: e.primary),
                  ),
                Expanded(
                  child: Text(a.titulo,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                if (data.isNotEmpty)
                  Text(data, style: TextStyle(fontSize: 11, color: e.onSurfaceVariant)),
              ],
            ),
            if (a.texto.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(a.texto, style: const TextStyle(fontSize: 13)),
              ),
            Wrap(
              children: [
                acao(a.fixado ? Icons.push_pin : Icons.push_pin_outlined,
                    a.fixado ? 'Desafixar' : 'Fixar no topo', () {
                  a.fixado = !a.fixado;
                  onSalvar();
                }),
                acao(Icons.copy, 'Copiar texto', () => _copiarAviso(context, a)),
                acao(Icons.print_outlined, 'Imprimir aviso (PDF)', () => _imprimirAviso(context, a)),
                acao(Icons.edit_outlined, 'Editar', () => _editarAviso(context, a)),
                acao(Icons.delete_outline, 'Excluir', () => _excluirAviso(context, a)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------- datas da igreja

  void _gerenciarDatas(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Datas da igreja'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Além das datas nacionais, cadastre as da sua igreja (aniversário da igreja, aniversário de casamento do pastor, campanhas...).',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  if (banco.datasIgreja.isEmpty) const Text('Nenhuma data cadastrada.'),
                  ...banco.datasIgreja.map((d) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(d.titulo),
                        subtitle: Text(
                            '${d.dia.toString().padLeft(2, '0')}/${d.mes.toString().padLeft(2, '0')}'
                            '${d.ano == 0 ? ' · todo ano' : '/${d.ano}'}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () async {
                                final novo = await formDataIgreja(ctx, existente: d);
                                if (novo == null) return;
                                final i = banco.datasIgreja.indexWhere((x) => x.id == novo.id);
                                if (i >= 0) banco.datasIgreja[i] = novo;
                                setD(() {});
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () async {
                                final ok = await confirmar(ctx,
                                    titulo: 'Excluir data?',
                                    mensagem: '"${d.titulo}" será apagada.');
                                if (!ok) return;
                                setD(() => banco.datasIgreja.removeWhere((x) => x.id == d.id));
                              },
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Adicionar data'),
              onPressed: () async {
                final nova = await formDataIgreja(ctx);
                if (nova == null) return;
                setD(() => banco.datasIgreja.add(nova));
              },
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Concluir')),
          ],
        ),
      ),
    ).then((_) => onSalvar());
  }

  // ------------------------------------------------------------------- partes

  Widget _secao(BuildContext context, String titulo,
      {Widget? acao, required List<Widget> filhos}) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(titulo,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              if (acao != null) acao,
            ],
          ),
          const SizedBox(height: 4),
          ...filhos,
        ],
      ),
    );
  }

  Widget _vazio(BuildContext context, String texto) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(texto,
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _cartaoHoje(BuildContext context, DateTime hoje, List<Entidade> niver,
      List<DataComemorativa> datas, int compHoje, int atrasados) {
    const branco70 = TextStyle(color: Colors.white70, fontSize: 13);
    final nomesNiver = niver.map((m) {
      final i = m.idadeNoProximoAniversario(hoje);
      return i == null ? m.nome : '${m.nome} ($i)';
    }).join(', ');
    final linhas = <String>[
      if (niver.isNotEmpty) 'Aniversariante(s) de hoje: $nomesNiver',
      if (datas.isNotEmpty) 'Hoje: ${datas.map((d) => d.nome).join(', ')}',
      if (compHoje > 0) '$compHoje compromisso(s) para hoje',
      if (atrasados > 0) '$atrasados lembrete(s) atrasado(s)',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: kCorPadrao, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kDiasSemana[hoje.weekday - 1].toUpperCase(),
              style: const TextStyle(
                  color: Colors.white70, fontSize: 12, letterSpacing: 1.5)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${hoje.day}',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 48, fontWeight: FontWeight.w700, height: 1.1)),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('de ${kMeses[hoje.month - 1].toLowerCase()} de ${hoje.year}',
                      style: const TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ),
            ],
          ),
          if (linhas.isEmpty)
            const Text('Nada de especial para hoje.', style: branco70)
          else
            ...linhas.map((l) => Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(l, style: const TextStyle(color: Colors.white, fontSize: 13)),
                )),
        ],
      ),
    );
  }

  void _menuAdicionar(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        Widget item(IconData i, String t, String s, VoidCallback f) => ListTile(
              leading: Icon(i),
              title: Text(t),
              subtitle: Text(s),
              onTap: () {
                Navigator.pop(ctx);
                f();
              },
            );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              item(Icons.campaign_outlined, 'Novo aviso', 'Comunicado fixo no Mural',
                  () => _novoAviso(context)),
              item(Icons.check_circle_outline, 'Novo lembrete', 'Tarefa com data (e repetição)',
                  () => _novoCompromisso(context, 'lembrete')),
              item(Icons.event, 'Novo evento', 'Agenda com data, hora e local',
                  () => _novoCompromisso(context, 'evento')),
              item(Icons.celebration_outlined, 'Nova data comemorativa', 'Datas da sua igreja',
                  () => _gerenciarDatas(context)),
            ],
          ),
        );
      },
    );
  }

  Future<void> _novoCompromisso(BuildContext context, String tipo) async {
    final novo = await formCompromisso(context, tipo: tipo);
    if (novo == null) return;
    banco.compromissos.add(novo);
    onSalvar();
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final e = Theme.of(context).colorScheme;
    final agora = DateTime.now();
    final h = soData(agora);

    // Avisos ativos (fixados primeiro, depois os mais novos)
    final ativos = banco.avisos.where((a) => !a.expirado(agora)).toList()
      ..sort((a, b) {
        if (a.fixado != b.fixado) return a.fixado ? -1 : 1;
        return b.criadoEm.compareTo(a.criadoEm);
      });
    final expirados = banco.avisos.length - ativos.length;

    // Compromissos: atrasados + próximos 14 dias
    final limite = h.add(const Duration(days: 14));
    final itens = <_Ocorrencia>[];
    var atrasados = 0;
    for (final c in banco.compromissos) {
      final base = c.dataBase;
      if (base == null) continue;
      final lembrete = c.tipo == 'lembrete';
      if (c.repete == 'nao') {
        if (base.isBefore(h)) {
          if (lembrete && !c.feito) {
            itens.add(_Ocorrencia(base, c));
            atrasados++;
          }
        } else if (!base.isAfter(limite) && !(lembrete && c.feito)) {
          itens.add(_Ocorrencia(base, c));
        }
      } else {
        var d = c.proxima(h);
        var n = 0;
        while (d != null && !d.isAfter(limite) && n < 3) {
          itens.add(_Ocorrencia(d, c));
          n++;
          d = c.proxima(d.add(const Duration(days: 1)));
        }
      }
    }
    itens.sort((a, b) {
      final x = a.dia.compareTo(b.dia);
      if (x != 0) return x;
      return (a.c.hora < 0 ? 9999 : a.c.hora).compareTo(b.c.hora < 0 ? 9999 : b.c.hora);
    });
    final compHoje = itens.where((o) => o.dia == h).length;

    final niverHoje = aniversariantesDeHoje(banco);
    final datasHoje = comemorativasNoDia(banco, h);
    final proximasDatas = proximasComemorativas(banco, h, 45).take(6).toList();

    final niverMes = banco.ativos.where((m) => m.dataNascimento?.month == h.month).toList()
      ..sort((a, b) {
        final c = a.dataNascimento!.day.compareTo(b.dataNascimento!.day);
        return c != 0
            ? c
            : normalizarTexto(a.nome).compareTo(normalizarTexto(b.nome));
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mural'),
        actions: [
          ListenableBuilder(
            listenable: Sync.instance,
            builder: (context, _) {
              final s = Sync.instance;
              final IconData icone;
              final String dica;
              if (!s.pronto) {
                icone = Icons.cloud_off_outlined;
                dica = 'Nuvem: não conectada';
              } else if (s.ocupado) {
                icone = Icons.cloud_sync_outlined;
                dica = 'Sincronizando...';
              } else if (s.erro != null) {
                icone = Icons.cloud_off;
                dica = 'Nuvem: ${s.erro}';
              } else {
                icone = Icons.cloud_done_outlined;
                dica = 'Nuvem: sincronizado';
              }
              return IconButton(
                icon: Icon(icone),
                tooltip: dica,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NuvemPage()),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Agenda (calendário)',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => AgendaPage(banco: banco, onSalvar: onSalvar)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.brightness_6_outlined),
            tooltip: 'Aparência (claro / escuro)',
            onPressed: onAparencia,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              _cartaoHoje(context, agora, niverHoje, datasHoje, compHoje, atrasados),

              // ---- Avisos
              _secao(
                context,
                'Avisos',
                acao: TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Novo'),
                  onPressed: () => _novoAviso(context),
                ),
                filhos: [
                  if (ativos.isEmpty) _vazio(context, 'Nenhum aviso no momento.'),
                  ...ativos.map((a) => _cartaoAviso(context, a)),
                  if (expirados > 0)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => _limparExpirados(context, expirados),
                        child: Text('Apagar $expirados aviso(s) expirado(s)'),
                      ),
                    ),
                ],
              ),

              // ---- Agenda
              _secao(
                context,
                'Lembretes e agenda (14 dias)',
                acao: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => AgendaPage(banco: banco, onSalvar: onSalvar)),
                  ),
                  child: const Text('Agenda completa'),
                ),
                filhos: [
                  if (itens.isEmpty) _vazio(context, 'Nada marcado para os próximos dias.'),
                  ...itens.take(12).map((o) => CompromissoTile(
                        key: ValueKey('${o.c.id}-${o.dia.toIso8601String()}'),
                        banco: banco,
                        compromisso: o.c,
                        dia: o.dia,
                        aoMudar: onSalvar,
                      )),
                ],
              ),

              // ---- Datas comemorativas
              _secao(
                context,
                'Datas comemorativas',
                acao: TextButton(
                  onPressed: () => _gerenciarDatas(context),
                  child: const Text('Datas da igreja'),
                ),
                filhos: [
                  if (proximasDatas.isEmpty)
                    _vazio(context, 'Nenhuma data nos próximos 45 dias.'),
                  ...proximasDatas.map((d) {
                    final dias = d.data.difference(h).inDays;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.celebration,
                          color: d.daIgreja ? e.primary : Colors.orange),
                      title: Text(d.nome),
                      subtitle: Text(
                          '${dataBr(d.data)} · ${dias == 0 ? 'hoje' : dias == 1 ? 'amanhã' : 'em $dias dias'}'
                          '${d.daIgreja ? ' · da igreja' : ''}'),
                    );
                  }),
                ],
              ),

              // ---- Aniversariantes do mês
              _secao(
                context,
                'Aniversariantes de ${kMeses[h.month - 1]}',
                acao: TextButton(
                  onPressed: onAbrirAniversarios,
                  child: const Text('Ver todos'),
                ),
                filhos: [
                  if (niverMes.isEmpty)
                    _vazio(context, 'Nenhum aniversariante neste mês (ou sem data de nascimento cadastrada).'),
                  ...niverMes.take(8).map((m) {
                    final n = m.dataNascimento!;
                    final eHoje = n.day == h.day;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: avatarMembro(m, 16),
                      title: Text(m.nome),
                      subtitle: Text(
                          '${eHoje ? 'Hoje! ' : ''}Dia ${n.day.toString().padLeft(2, '0')} · completa ${h.year - n.year} anos'),
                    );
                  }),
                  if (niverMes.length > 8)
                    _vazio(context, '+ ${niverMes.length - 8} aniversariante(s). Toque em "Ver todos".'),
                ],
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _menuAdicionar(context),
        icon: const Icon(Icons.add),
        label: const Text('Adicionar'),
      ),
    );
  }
}
