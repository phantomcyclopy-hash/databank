import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../calendario.dart';
import '../leitor_documentos.dart';
import '../models.dart';
import '../widgets/dialogos.dart';
import '../widgets/seletor_data.dart';
import 'ata_editor_page.dart';
import 'opcoes_impressao_page.dart';

/// Relatórios de reunião. Ordinária = relatório do mês (acumulativo);
/// extraordinária = folha avulsa, gerada na hora.
class AtasPage extends StatefulWidget {
  final Banco banco;
  final VoidCallback onSalvar;
  final VoidCallback onAparencia;

  const AtasPage({
    super.key,
    required this.banco,
    required this.onSalvar,
    required this.onAparencia,
  });

  @override
  State<AtasPage> createState() => _AtasPageState();
}

class _AtasPageState extends State<AtasPage> {
  static const Uuid _uuid = Uuid();

  Banco get _banco => widget.banco;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _abrir(Ata a) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AtaEditorPage(banco: _banco, ata: a, onSalvar: widget.onSalvar),
      ),
    ).then((_) => widget.onSalvar());
  }

  // ----------------------------------------------------------------- criar

  Future<void> _novaOrdinaria() async {
    final hoje = DateTime.now();
    var mes = hoje.month;
    var ano = hoje.year;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Ata ordinária'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Relatório do mês: acumula registros (acontecimentos, eventos, posicionamentos, feitos) e o movimento de membros do mês.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: mes,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Mês'),
                      items: [
                        for (var i = 0; i < 12; i++)
                          DropdownMenuItem(value: i + 1, child: Text(kMeses[i])),
                      ],
                      onChanged: (v) => setD(() => mes = v ?? mes),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 100,
                    child: DropdownButtonFormField<int>(
                      value: ano,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Ano'),
                      items: [
                        for (var y = hoje.year - 4; y <= hoje.year + 1; y++)
                          DropdownMenuItem(value: y, child: Text('$y')),
                      ],
                      onChanged: (v) => setD(() => ano = v ?? ano),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Abrir')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final chave = '$ano-${mes.toString().padLeft(2, '0')}';
    final existentes = _banco.atas.where((a) => a.tipo == 'ordinaria' && a.mes == chave);
    if (existentes.isNotEmpty) {
      _snack('Já existe a ata de ${kMeses[mes - 1]}/$ano. Abrindo.');
      _abrir(existentes.first);
      return;
    }
    final agora = DateTime.now().millisecondsSinceEpoch;
    final a = Ata(
      id: _uuid.v4(),
      tipo: 'ordinaria',
      titulo: 'Ata ordinária - ${kMeses[mes - 1]}/$ano',
      mes: chave,
      criadoEm: agora,
      atualizadoEm: agora,
    );
    _banco.atas.add(a);
    widget.onSalvar();
    _abrir(a);
  }

  Future<void> _novaExtraordinaria() async {
    final tituloCtrl = TextEditingController(text: 'Ata extraordinária');
    DateTime? data = soData(DateTime.now());
    var temHora = false;
    var hora = DateTime.now().hour * 60 + DateTime.now().minute;
    var erro = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Ata extraordinária'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Folha avulsa, não acumulativa. Ela é salva assim que criada e você pode gerar o PDF na hora.',
                    style: TextStyle(fontSize: 12),
                  ),
                  TextField(
                    controller: tituloCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Título'),
                  ),
                  SeletorData(
                      rotulo: 'Data da reunião *', inicial: data, onChanged: (d) => data = d),
                  if (erro)
                    const Text('Informe uma data válida',
                        style: TextStyle(fontSize: 12, color: Colors.red)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Definir hora'),
                    value: temHora,
                    onChanged: (v) => setD(() => temHora = v),
                  ),
                  if (temHora)
                    SeletorHora(rotulo: 'Hora', minutos: hora, onChanged: (m) => hora = m),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (data == null) {
                  setD(() => erro = true);
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Criar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || data == null) return;

    final iso = isoData(data!);
    final agora = DateTime.now().millisecondsSinceEpoch;
    final a = Ata(
      id: _uuid.v4(),
      tipo: 'extraordinaria',
      titulo: tituloCtrl.text.trim().isEmpty ? 'Ata extraordinária' : tituloCtrl.text.trim(),
      data: iso,
      hora: temHora ? hora : -1,
      periodoIni: iso,
      periodoFim: iso,
      criadoEm: agora,
      atualizadoEm: agora,
    );
    _banco.atas.add(a);
    widget.onSalvar();
    _abrir(a);
  }

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
      final nome = arq.name.contains('.')
          ? arq.name.substring(0, arq.name.lastIndexOf('.'))
          : arq.name;
      final hoje = isoData(DateTime.now());
      final agora = DateTime.now().millisecondsSinceEpoch;
      final a = Ata(
        id: _uuid.v4(),
        tipo: 'extraordinaria',
        titulo: nome.isEmpty ? 'Ata importada' : nome,
        data: hoje,
        periodoIni: hoje,
        periodoFim: hoje,
        incluirMovimentos: false,
        texto: texto,
        criadoEm: agora,
        atualizadoEm: agora,
      );
      _banco.atas.add(a);
      widget.onSalvar();
      _snack('Texto importado (${texto.length} caracteres). Revise e ajuste no editor.');
      _abrir(a);
    } on LeituraException catch (e) {
      _snack(e.mensagem);
    } catch (e) {
      _snack('Erro ao importar: $e');
    }
  }

  Future<void> _excluir(Ata a) async {
    final ok = await confirmar(
      context,
      titulo: 'Excluir ata?',
      mensagem: 'A ata "${a.titulo}" e todos os seus registros serão apagados. Esta ação não pode ser desfeita.',
    );
    if (!ok) return;
    _banco.atas.removeWhere((x) => x.id == a.id);
    widget.onSalvar();
  }

  void _gerarPdf(Ata a) {
    imprimirComOpcoes(
      context,
      banco: _banco,
      membros: const [],
      tituloInicial: a.titulo,
      ata: a,
      aviso: _snack,
    );
  }

  void _menuNova() {
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
              item(Icons.event_note, 'Ata ordinária', 'Relatório do mês, acumulativo',
                  _novaOrdinaria),
              item(Icons.bolt, 'Ata extraordinária', 'Folha avulsa, gerada na hora',
                  _novaExtraordinaria),
              item(Icons.upload_file, 'Importar arquivo', 'Word (.docx), PDF ou TXT vira uma ata',
                  _importar),
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------- build

  String _subtitulo(Ata a) {
    final regs = '${a.registros.length} registro(s)';
    if (a.tipo == 'ordinaria') {
      final mv = _banco.movimentosDaAta(a);
      final p = a.mes.split('-');
      final m = p.length == 2 ? int.tryParse(p[1]) : null;
      final rotulo = (m != null && m >= 1 && m <= 12) ? '${kMeses[m - 1]}/${p[0]}' : a.mes;
      return '$rotulo · $regs · ${mv.where((x) => x.tipo == 'entrada').length} entrada(s) · '
          '${mv.where((x) => x.tipo == 'saida').length} saída(s)';
    }
    final d = parseNascimento(a.data);
    return 'Extraordinária${d == null ? '' : ' · ${dataBr(d)}'} · $regs';
  }

  Widget _cartao(Ata a) {
    final e = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: e.outlineVariant),
      ),
      child: ListTile(
        onTap: () => _abrir(a),
        leading: Icon(a.tipo == 'ordinaria' ? Icons.event_note : Icons.bolt, color: e.primary),
        title: Text(a.titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(_subtitulo(a), style: const TextStyle(fontSize: 12)),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'abrir') _abrir(a);
            if (v == 'pdf') _gerarPdf(a);
            if (v == 'excluir') _excluir(a);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'abrir', child: Text('Abrir / editar')),
            PopupMenuItem(value: 'pdf', child: Text('Gerar PDF')),
            PopupMenuItem(value: 'excluir', child: Text('Excluir ata')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = Theme.of(context).colorScheme;
    final ordinarias = _banco.atas.where((a) => a.tipo == 'ordinaria').toList()
      ..sort((a, b) => b.mes.compareTo(a.mes));
    final extras = _banco.atas.where((a) => a.tipo != 'ordinaria').toList()
      ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));

    Widget titulo(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
          child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Atas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Importar arquivo (Word, PDF, TXT)',
            onPressed: _importar,
          ),
          IconButton(
            icon: const Icon(Icons.brightness_6_outlined),
            tooltip: 'Aparência (claro / escuro)',
            onPressed: widget.onAparencia,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text(
                  'Relatórios de reunião. A ata ordinária acumula o mês (movimento de membros, acontecimentos, posicionamentos e feitos); a extraordinária é uma folha avulsa, gerada na hora.',
                  style: TextStyle(fontSize: 12, color: e.onSurfaceVariant),
                ),
              ),
              if (_banco.atas.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text('Nenhuma ata criada.\nToque em "Nova ata" para começar.',
                        textAlign: TextAlign.center),
                  ),
                ),
              if (ordinarias.isNotEmpty) titulo('Ordinárias (por mês)'),
              ...ordinarias.map(_cartao),
              if (extras.isNotEmpty) titulo('Extraordinárias'),
              ...extras.map(_cartao),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _menuNova,
        icon: const Icon(Icons.add),
        label: const Text('Nova ata'),
      ),
    );
  }
}
