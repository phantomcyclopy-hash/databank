import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../calendario.dart';
import '../models.dart';
import '../nuvem/sync_service.dart';
import '../pdf_service.dart';
import '../storage.dart';
import '../widgets/compromisso_tile.dart';
import '../widgets/dialogos.dart';
import '../widgets/membro_widgets.dart';
import '../widgets/mural_dialogs.dart';
import 'agenda_page.dart';
import 'cultos_page.dart';
import 'perfil_page.dart';

class _Ocorrencia {
  final DateTime dia;
  final Compromisso c;
  _Ocorrencia(this.dia, this.c);
}

class _ItemDia {
  final int hora; // minutos ou -1
  final String titulo;
  final String sub;
  final IconData icone;
  final String detalhe;
  _ItemDia(this.hora, this.titulo, this.sub, this.icone, [this.detalhe = '']);
}

const List<String> _abrev = ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SÁB', 'DOM'];

/// Tela inicial. No topo: o dia de hoje, o que está marcado e os próximos dias
/// (com os cultos da semana). Depois: versículo, avisos, publicações, agenda,
/// datas comemorativas e aniversariantes. Quem não pode editar só consulta.
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

  bool get _edita => Sync.instance.podeEditar;
  bool get _veTudo => Sync.instance.veTudo;

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ------------------------------------------------------------ itens do dia

  IconData _iconeCategoria(Compromisso c) {
    if (c.tipo == 'lembrete') return Icons.check_circle_outline;
    switch (c.categoria) {
      case 'ensaio':
        return Icons.music_note;
      case 'reuniao':
        return Icons.groups;
      default:
        return Icons.event;
    }
  }

  List<_ItemDia> _itensDoDia(DateTime d) {
    final out = <_ItemDia>[];
    for (final c in banco.cultos) {
      if (c.diaSemana == d.weekday) {
        out.add(_ItemDia(c.hora, c.titulo, c.horaTexto, Icons.church_outlined, c.cronograma));
      }
    }
    for (final c in banco.compromissos) {
      if (!c.ocorreEm(d)) continue;
      if (c.tipo == 'lembrete' && (!_veTudo || (c.feito && c.repete == 'nao'))) continue;
      if (c.categoria == 'versiculo') continue;
      final sub = [
        if (c.horaTexto.isNotEmpty) c.horaTexto,
        if (c.local.isNotEmpty) c.local,
        if (c.tipo == 'lembrete') 'lembrete',
      ].join(' · ');
      out.add(_ItemDia(c.hora, c.titulo, sub, _iconeCategoria(c), c.descricao));
    }
    out.sort((a, b) => (a.hora < 0 ? 9999 : a.hora).compareTo(b.hora < 0 ? 9999 : b.hora));
    return out;
  }

  Compromisso? _versiculoDe(DateTime d) {
    for (final c in banco.compromissos) {
      if (c.categoria == 'versiculo' && c.ocorreEm(d)) return c;
    }
    return null;
  }

  // ------------------------------------------------------------------ topo

  Widget _topo(BuildContext context, DateTime agora) {
    final e = Theme.of(context).colorScheme;
    final h = soData(agora);
    final itens = _itensDoDia(h);
    final niver = _veTudo ? aniversariantesDeHoje(banco) : <Entidade>[];
    final datas = comemorativasNoDia(banco, h);

    Widget linha(IconData i, String texto, {String? hora}) => Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(i, size: 15, color: e.primary),
              const SizedBox(width: 6),
              if (hora != null && hora.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(hora, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              Expanded(child: Text(texto, style: const TextStyle(fontSize: 13))),
            ],
          ),
        );

    final extras = niver.length + datas.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 118,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: e.primary, borderRadius: BorderRadius.circular(8)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_abrev[agora.weekday - 1],
                        style: TextStyle(
                            color: e.onPrimary.withOpacity(0.8),
                            fontSize: 12,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w600)),
                    Text('${agora.day}',
                        style: TextStyle(
                            color: e.onPrimary, fontSize: 44, fontWeight: FontWeight.w800, height: 1.05)),
                    Text('${kMeses[agora.month - 1]}\n${agora.year}',
                        style: TextStyle(color: e.onPrimary, fontSize: 12, height: 1.25)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _diaDetalhe(context, h),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: e.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Hoje', style: TextStyle(fontWeight: FontWeight.w700)),
                        if (itens.isEmpty && extras == 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('Nada marcado para hoje.',
                                style: TextStyle(fontSize: 13, color: e.onSurfaceVariant)),
                          ),
                        ...itens.take(4).map((i) => linha(i.icone, i.titulo,
                            hora: i.hora >= 0
                                ? '${(i.hora ~/ 60).toString().padLeft(2, '0')}:${(i.hora % 60).toString().padLeft(2, '0')}'
                                : null)),
                        if (itens.length > 4)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('+ ${itens.length - 4} item(ns)',
                                style: TextStyle(fontSize: 12, color: e.onSurfaceVariant)),
                          ),
                        ...datas.map((d) => linha(Icons.celebration, d.nome)),
                        if (niver.isNotEmpty)
                          linha(Icons.cake, 'Aniversário: ${niver.map((m) => m.nome.split(' ').first).join(', ')}'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Expanded(
              child: Text('Próximos dias', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (_edita)
              TextButton.icon(
                icon: const Icon(Icons.edit_calendar, size: 16),
                label: const Text('Cultos da semana'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => CultosPage(banco: banco, onSalvar: onSalvar)),
                ),
              ),
          ],
        ),
        SizedBox(
          height: 84,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [for (var i = 1; i <= 7; i++) _quadradinho(context, h.add(Duration(days: i)))],
          ),
        ),
      ],
    );
  }

  Widget _quadradinho(BuildContext context, DateTime d) {
    final e = Theme.of(context).colorScheme;
    final itens = _itensDoDia(d);
    final temCulto = banco.cultos.any((c) => c.diaSemana == d.weekday);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _diaDetalhe(context, d),
        child: Container(
          width: 76,
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: itens.isEmpty ? e.outlineVariant : e.primary.withOpacity(0.6)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_abrev[d.weekday - 1],
                  style: TextStyle(fontSize: 10, letterSpacing: 1, color: e.onSurfaceVariant)),
              Text('${d.day}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              if (itens.isEmpty)
                Text('-', style: TextStyle(fontSize: 10, color: e.onSurfaceVariant))
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (temCulto) Icon(Icons.church_outlined, size: 11, color: e.primary),
                    Flexible(
                      child: Text(
                        ' ${itens.first.titulo}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _diaDetalhe(BuildContext context, DateTime d) {
    final itens = _itensDoDia(d);
    final datas = comemorativasNoDia(banco, d);
    final verso = _versiculoDe(d);
    final niver = _veTudo
        ? banco.ativos.where((m) {
            final n = m.dataNascimento;
            return n != null && n.month == d.month && n.day == d.day;
          }).toList()
        : <Entidade>[];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final e = Theme.of(ctx).colorScheme;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dataPorExtenso(d),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  if (itens.isEmpty && datas.isEmpty && niver.isEmpty && verso == null)
                    Text('Nada marcado para este dia.', style: TextStyle(color: e.onSurfaceVariant)),
                  if (verso != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.menu_book),
                      title: Text(verso.titulo),
                      subtitle: Text(verso.descricao),
                    ),
                  ...itens.map((i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(i.icone, size: 18, color: e.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(i.titulo,
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
                            if (i.sub.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 26),
                                child: Text(i.sub,
                                    style: TextStyle(fontSize: 12, color: e.onSurfaceVariant)),
                              ),
                            if (i.detalhe.isNotEmpty)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(left: 26, top: 6),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: e.outlineVariant),
                                ),
                                child: Text(i.detalhe, style: const TextStyle(fontSize: 13, height: 1.5)),
                              ),
                          ],
                        ),
                      )),
                  ...datas.map((c) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.celebration, color: Colors.orange),
                        title: Text(c.nome),
                      )),
                  ...niver.map((m) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.cake, color: Colors.pink),
                        title: Text(m.nome),
                        subtitle: Text('Aniversário · ${d.year - m.dataNascimento!.year} anos'),
                      )),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- versículo

  Widget _cartaoVersiculo(BuildContext context, Compromisso v) {
    final e = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: e.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: e.primary.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.format_quote, color: e.primary),
              const SizedBox(width: 6),
              Text('Versículo do dia',
                  style: TextStyle(color: e.primary, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.8)),
            ],
          ),
          if (v.descricao.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(v.descricao,
                  style: const TextStyle(fontSize: 15, fontStyle: FontStyle.italic, height: 1.4)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(v.titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------- avisos

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
    final data = a.criadoEm > 0 ? dataBr(DateTime.fromMillisecondsSinceEpoch(a.criadoEm)) : '';
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
                child: SelectableText(a.texto, style: const TextStyle(fontSize: 13)),
              ),
            Wrap(
              children: [
                acao(Icons.copy, 'Copiar texto', () => _copiarAviso(context, a)),
                if (_edita) ...[
                  acao(a.fixado ? Icons.push_pin : Icons.push_pin_outlined,
                      a.fixado ? 'Desafixar' : 'Fixar no topo', () {
                    a.fixado = !a.fixado;
                    onSalvar();
                  }),
                  acao(Icons.print_outlined, 'Imprimir aviso (PDF)', () => _imprimirAviso(context, a)),
                  acao(Icons.edit_outlined, 'Editar', () => _editarAviso(context, a)),
                  acao(Icons.delete_outline, 'Excluir', () => _excluirAviso(context, a)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- publicações

  Widget _cartaoPublicacao(BuildContext context, Publicacao p) {
    final e = Theme.of(context).colorScheme;
    final ate = parseNascimento(p.expiraEm);
    final quando = p.publicadoEm > 0
        ? 'Publicado em ${dataBr(DateTime.fromMillisecondsSinceEpoch(p.publicadoEm))}'
        : 'Publicado';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: e.outlineVariant),
      ),
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PublicacaoPage(
              publicacao: p,
              podeApagar: _edita,
              aoApagar: () {
                banco.publicacoes.removeWhere((x) => x.id == p.id);
                onSalvar();
              },
            ),
          ),
        ),
        leading: Icon(p.tipo == 'ata' ? Icons.event_note : Icons.description, color: e.primary),
        title: Text(p.titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '$quando${ate == null ? '' : ' · até ${dataBr(ate)}'}\n${p.texto.split('\n').first}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
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
                    'Além das datas nacionais, cadastre as da sua igreja (aniversário da igreja, campanhas...).',
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
                                    titulo: 'Excluir data?', mensagem: '"${d.titulo}" será apagada.');
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
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
              item(Icons.event, 'Novo evento', 'Ensaio, reunião, versículo do dia...',
                  () => _novoCompromisso(context, 'evento')),
              item(Icons.check_circle_outline, 'Novo lembrete', 'Tarefa da secretaria (só a equipe vê)',
                  () => _novoCompromisso(context, 'lembrete')),
              item(Icons.church_outlined, 'Cultos da semana', 'Dias, títulos e cronogramas fixos',
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => CultosPage(banco: banco, onSalvar: onSalvar)))),
              item(Icons.celebration_outlined, 'Datas da igreja', 'Datas comemorativas próprias',
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

  // -------------------------------------------------------------- fale conosco

  Widget _secaoContato(BuildContext context) {
    final e = Theme.of(context).colorScheme;
    final c = banco.contato;
    final ehDono = Sync.instance.ehDono;

    Widget linha(IconData icone, String rotulo, String valor) => ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(icone, color: e.primary),
          title: SelectableText(valor, style: const TextStyle(fontSize: 14)),
          subtitle: Text(rotulo, style: const TextStyle(fontSize: 11)),
          trailing: IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Copiar',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: valor));
              if (context.mounted) _snack(context, 'Copiado.');
            },
          ),
        );

    return _secao(
      context,
      'Fale conosco',
      acao: ehDono
          ? TextButton.icon(
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Editar'),
              onPressed: () async {
                final novo = await formContato(context, c);
                if (novo == null) return;
                banco.contato = novo;
                onSalvar();
              },
            )
          : null,
      filhos: [
        if (c.vazio)
          _vazio(
            context,
            ehDono
                ? 'Toque em "Editar" para definir o telefone, e-mail ou endereço da igreja.'
                : 'As informações de contato da igreja serão divulgadas aqui.',
          ),
        if (c.telefone.trim().isNotEmpty) linha(Icons.phone, 'Telefone / WhatsApp', c.telefone),
        if (c.email.trim().isNotEmpty) linha(Icons.mail_outline, 'E-mail', c.email),
        if (c.endereco.trim().isNotEmpty) linha(Icons.place_outlined, 'Endereço', c.endereco),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = Theme.of(context).colorScheme;
    final agora = DateTime.now();
    final h = soData(agora);
    final sync = Sync.instance;

    // Avisos ativos (fixados primeiro, depois os mais novos)
    final ativos = banco.avisos.where((a) => !a.expirado(agora)).toList()
      ..sort((a, b) {
        if (a.fixado != b.fixado) return a.fixado ? -1 : 1;
        return b.criadoEm.compareTo(a.criadoEm);
      });
    final expirados = banco.avisos.length - ativos.length;

    final publicacoes = banco.publicacoes.where((p) => !p.expirada(agora)).toList()
      ..sort((a, b) => b.publicadoEm.compareTo(a.publicadoEm));

    // Agenda: atrasados + próximos 14 dias
    final limite = h.add(const Duration(days: 14));
    final itens = <_Ocorrencia>[];
    for (final c in banco.compromissos) {
      final base = c.dataBase;
      if (base == null || c.categoria == 'versiculo') continue;
      final lembrete = c.tipo == 'lembrete';
      if (lembrete && !_veTudo) continue;
      if (c.repete == 'nao') {
        if (base.isBefore(h)) {
          if (lembrete && !c.feito) itens.add(_Ocorrencia(base, c));
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

    final proximasDatas = proximasComemorativas(banco, h, 45).take(6).toList();
    final niverMes = _veTudo
        ? (banco.ativos.where((m) => m.dataNascimento?.month == h.month).toList()
          ..sort((a, b) {
            final c = a.dataNascimento!.day.compareTo(b.dataNascimento!.day);
            return c != 0 ? c : normalizarTexto(a.nome).compareTo(normalizarTexto(b.nome));
          }))
        : <Entidade>[];
    final versiculo = _versiculoDe(h);
    final pendente = sync.pedido == 'secretaria' && !sync.podeEditar;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mural'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Agenda',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AgendaPage(banco: banco, onSalvar: onSalvar)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            tooltip: 'Aparência e cores',
            onPressed: onAparencia,
          ),
          ListenableBuilder(
            listenable: sync,
            builder: (context, _) {
              final IconData icone;
              final String dica;
              if (sync.ocupado) {
                icone = Icons.cloud_sync_outlined;
                dica = 'Sincronizando...';
              } else if (sync.erro != null) {
                icone = Icons.cloud_off;
                dica = 'Nuvem: ${sync.erro}';
              } else {
                icone = Icons.account_circle_outlined;
                dica = 'Minha conta';
              }
              return IconButton(
                icon: Icon(icone),
                tooltip: dica,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PerfilPage()),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => sync.sincronizar(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              children: [
                if (pendente)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: e.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Seu pedido de acesso como secretaria aguarda a aprovação da conta principal. Até lá você vê o Mural e a Agenda.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                _topo(context, agora),
                if (versiculo != null) _cartaoVersiculo(context, versiculo),

                // ---- Avisos
                _secao(
                  context,
                  'Avisos',
                  acao: _edita
                      ? TextButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Novo'),
                          onPressed: () => _novoAviso(context),
                        )
                      : null,
                  filhos: [
                    if (ativos.isEmpty) _vazio(context, 'Nenhum aviso no momento.'),
                    ...ativos.map((a) => _cartaoAviso(context, a)),
                    if (_edita && expirados > 0)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => _limparExpirados(context, expirados),
                          child: Text('Apagar $expirados aviso(s) expirado(s)'),
                        ),
                      ),
                  ],
                ),

                // ---- Publicações (listas e atas)
                if (publicacoes.isNotEmpty)
                  _secao(
                    context,
                    'Publicações',
                    filhos: publicacoes.map((p) => _cartaoPublicacao(context, p)).toList(),
                  ),

                // ---- Agenda
                _secao(
                  context,
                  _veTudo ? 'Lembretes e agenda (14 dias)' : 'Agenda (14 dias)',
                  acao: TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => AgendaPage(banco: banco, onSalvar: onSalvar)),
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
                          somenteLeitura: !_edita,
                        )),
                  ],
                ),

                // ---- Datas comemorativas
                _secao(
                  context,
                  'Datas comemorativas',
                  acao: _edita
                      ? TextButton(
                          onPressed: () => _gerenciarDatas(context),
                          child: const Text('Datas da igreja'),
                        )
                      : null,
                  filhos: [
                    if (proximasDatas.isEmpty) _vazio(context, 'Nenhuma data nos próximos 45 dias.'),
                    ...proximasDatas.map((d) {
                      final dias = d.data.difference(h).inDays;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.celebration, color: d.daIgreja ? e.primary : Colors.orange),
                        title: Text(d.nome),
                        subtitle: Text(
                            '${dataBr(d.data)} · ${dias == 0 ? 'hoje' : dias == 1 ? 'amanhã' : 'em $dias dias'}'
                            '${d.daIgreja ? ' · da igreja' : ''}'),
                      );
                    }),
                  ],
                ),

                // ---- Aniversariantes do mês (só quem vê o cadastro)
                if (_veTudo)
                  _secao(
                    context,
                    'Aniversariantes de ${kMeses[h.month - 1]}',
                    acao: TextButton(onPressed: onAbrirAniversarios, child: const Text('Ver todos')),
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

                // ---- Fale conosco (último elemento do Mural)
                _secaoContato(context),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: _edita
          ? FloatingActionButton.extended(
              onPressed: () => _menuAdicionar(context),
              icon: const Icon(Icons.add),
              label: const Text('Adicionar'),
            )
          : null,
    );
  }
}

/// Leitura de uma publicação (lista ou ata) do Mural.
class PublicacaoPage extends StatelessWidget {
  final Publicacao publicacao;
  final bool podeApagar;
  final VoidCallback aoApagar;

  const PublicacaoPage({
    super.key,
    required this.publicacao,
    required this.podeApagar,
    required this.aoApagar,
  });

  @override
  Widget build(BuildContext context) {
    final e = Theme.of(context).colorScheme;
    final ate = parseNascimento(publicacao.expiraEm);
    return Scaffold(
      appBar: AppBar(
        title: Text(publicacao.titulo, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copiar texto',
            onPressed: () async {
              await Clipboard.setData(
                  ClipboardData(text: '${publicacao.titulo}\n\n${publicacao.texto}'));
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Texto copiado.')));
              }
            },
          ),
          if (podeApagar)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remover do Mural',
              onPressed: () async {
                final ok = await confirmar(context,
                    titulo: 'Remover do Mural?',
                    mensagem: 'A publicação "${publicacao.titulo}" sai do Mural. O original continua guardado.',
                    acao: 'Remover');
                if (!ok) return;
                aoApagar();
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (ate != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('Fica no Mural até ${dataBr(ate)}',
                  style: TextStyle(fontSize: 12, color: e.onSurfaceVariant)),
            ),
          SelectableText(publicacao.texto, style: const TextStyle(fontSize: 15, height: 1.5)),
        ],
      ),
    );
  }
}
