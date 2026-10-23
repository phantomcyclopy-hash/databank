import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models.dart';
import '../pdf_service.dart';
import '../storage.dart';
import '../widgets/seletor_data.dart';

class ResultadoImpressao {
  final ConfigPdf cfg;
  final String titulo;
  ResultadoImpressao(this.cfg, this.titulo);
}

/// Abre as opções de impressão e, ao confirmar, gera e envia o PDF.
Future<void> imprimirComOpcoes(
  BuildContext context, {
  required Banco banco,
  ListaEntidades? lista,
  required List<Entidade> membros,
  required String tituloInicial,
  String? layout,
  bool ficha = false,
  required void Function(String) aviso,
}) async {
  if (membros.isEmpty) {
    aviso('Não há membros para imprimir.');
    return;
  }
  final res = await Navigator.push<ResultadoImpressao>(
    context,
    MaterialPageRoute(
      builder: (_) => OpcoesImpressaoPage(
        banco: banco,
        lista: lista,
        tituloInicial: tituloInicial,
        layoutInicial: ficha ? 'fichas' : layout,
        mostrarLayout: !ficha,
      ),
    ),
  );
  if (res == null) return;
  if (ficha) res.cfg.layout = 'fichas';
  if (res.cfg.layout == 'assinaturas' && !membros.any((m) => m.requerAssinatura)) {
    aviso('Nenhum membro marcado como "requer assinatura".');
    return;
  }

  try {
    final bytes = await PdfService.gerar(
      banco: banco,
      lista: lista,
      membros: membros,
      titulo: res.titulo,
      cfg: res.cfg,
    );
    final nome = res.titulo.isEmpty ? 'ibmmkar' : res.titulo.replaceAll(RegExp(r'[^\w\-]+'), '_');
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: '$nome.pdf');
  } catch (e) {
    aviso('Erro ao gerar PDF: $e');
  }
}

class OpcoesImpressaoPage extends StatefulWidget {
  final Banco banco;
  final ListaEntidades? lista;
  final String tituloInicial;

  /// true = só edita e salva as opções (sem gerar PDF).
  final bool modoConfig;

  /// false = impressão de ficha individual (layout fixo).
  final bool mostrarLayout;
  final String? layoutInicial;

  const OpcoesImpressaoPage({
    super.key,
    required this.banco,
    this.lista,
    this.tituloInicial = '',
    this.modoConfig = false,
    this.mostrarLayout = true,
    this.layoutInicial,
  });

  @override
  State<OpcoesImpressaoPage> createState() => _OpcoesImpressaoPageState();
}

class _OpcoesImpressaoPageState extends State<OpcoesImpressaoPage> {
  late ConfigPdf cfg;
  late String layoutOriginal;
  late final TextEditingController tituloCtrl;
  late final TextEditingController subtituloCtrl;
  late final TextEditingController sup, inf, esq, dir, pastorCtrl;

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void initState() {
    super.initState();
    cfg = AppStorage.instance.configPdf.copiar();
    layoutOriginal = cfg.layout;
    if (widget.layoutInicial != null) cfg.layout = widget.layoutInicial!;
    if (!PdfService.layouts.containsKey(cfg.layout)) cfg.layout = 'simples';

    // Data e hora valem para cada documento: vêm do evento da lista (se ela tiver)
    // ou são as atuais. Assim a escolha de uma impressão não "vaza" para outra.
    if (!widget.modoConfig) {
      final l = widget.lista;
      if (l != null && parseNascimento(l.dataEvento) != null) {
        cfg.dataModo = 'escolhida';
        cfg.dataEscolhida = l.dataEvento;
      } else {
        cfg.dataModo = 'hoje';
      }
      if (l != null && l.horaEvento >= 0) {
        cfg.horaModo = 'escolhida';
        cfg.horaEscolhida = l.horaEvento;
      } else {
        cfg.horaModo = 'agora';
      }
    }

    tituloCtrl = TextEditingController(text: widget.tituloInicial);
    subtituloCtrl = TextEditingController(text: cfg.capaSubtitulo);
    pastorCtrl = TextEditingController(text: cfg.pastorNome);
    sup = TextEditingController(text: _fmt(cfg.margemSuperior));
    inf = TextEditingController(text: _fmt(cfg.margemInferior));
    esq = TextEditingController(text: _fmt(cfg.margemEsquerda));
    dir = TextEditingController(text: _fmt(cfg.margemDireita));
  }

  @override
  void dispose() {
    for (final c in [tituloCtrl, subtituloCtrl, sup, inf, esq, dir, pastorCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  double _mm(TextEditingController c, double padrao) {
    final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
    if (v == null) return padrao;
    return v.clamp(0.0, 60.0).toDouble();
  }

  Future<String?> _escolherImagem() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
      withData: true,
    );
    final bytes = r?.files.single.bytes;
    return bytes == null ? null : base64Encode(bytes);
  }

  Future<void> _confirmar() async {
    cfg.margemSuperior = _mm(sup, 15);
    cfg.margemInferior = _mm(inf, 15);
    cfg.margemEsquerda = _mm(esq, 15);
    cfg.margemDireita = _mm(dir, 15);
    cfg.capaSubtitulo = subtituloCtrl.text.trim();
    cfg.pastorNome = pastorCtrl.text.trim();

    final paraSalvar = cfg.copiar();
    // Ficha individual não deve mudar o layout lembrado dos relatórios.
    if (!widget.mostrarLayout && !widget.modoConfig) paraSalvar.layout = layoutOriginal;
    await AppStorage.instance.salvarConfigPdf(paraSalvar);

    if (!mounted) return;
    Navigator.pop(context, ResultadoImpressao(cfg, tituloCtrl.text.trim()));
  }

  // ------------------------------------------------------------------ peças

  Widget _secao(String titulo, List<Widget> filhos, {String? ajuda}) {
    final esquema = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: esquema.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            if (ajuda != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(ajuda,
                    style: TextStyle(fontSize: 12, color: esquema.onSurfaceVariant)),
              ),
            const SizedBox(height: 8),
            ...filhos,
          ],
        ),
      ),
    );
  }

  Widget _seletorLogo({
    required String? b64,
    required VoidCallback onEscolher,
    required VoidCallback onRemover,
    List<Widget> extras = const [],
  }) {
    Widget? previa;
    if (b64 != null && b64.isNotEmpty) {
      try {
        previa = Image.memory(base64Decode(b64), height: 64);
      } catch (_) {
        previa = null;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (previa != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(6),
              ),
              child: previa,
            ),
          ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.image),
              label: Text(previa == null ? 'Escolher imagem (PNG)' : 'Trocar imagem'),
              onPressed: onEscolher,
            ),
            if (previa != null)
              TextButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remover'),
                onPressed: onRemover,
              ),
            ...extras,
          ],
        ),
      ],
    );
  }

  Widget _campoMm(String rotulo, TextEditingController c) => Expanded(
        child: TextField(
          controller: c,
          enabled: cfg.usarMargens,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: rotulo, suffixText: 'mm'),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final lista = widget.lista;
    final mostrarCampos = !widget.modoConfig &&
        (cfg.layout == 'simples' || cfg.layout == 'foto' || cfg.layout == 'agrupado');

    final camposTodos = <String, String>{
      ...PdfService.camposDisponiveis,
      for (final c in widget.banco.colunas) c.id: c.nome,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.modoConfig ? 'Opções de impressão' : 'Imprimir'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 24),
        children: [
          // ---------------------------------------------------- Relatório
          if (!widget.modoConfig)
            _secao('Relatório', [
              if (widget.mostrarLayout)
                DropdownButtonFormField<String>(
                  value: cfg.layout,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Tipo de relatório'),
                  items: PdfService.layouts.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => cfg.layout = v ?? 'simples'),
                ),
              TextField(
                controller: tituloCtrl,
                decoration: const InputDecoration(labelText: 'Título do documento'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Retrato'), icon: Icon(Icons.stay_current_portrait)),
                  ButtonSegment(value: true, label: Text('Paisagem'), icon: Icon(Icons.stay_current_landscape)),
                ],
                selected: {cfg.paisagem},
                onSelectionChanged: (s) => setState(() => cfg.paisagem = s.first),
              ),
              if (mostrarCampos) ...[
                const SizedBox(height: 14),
                const Text('Informações que aparecem na tabela',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: camposTodos.entries
                      .map((e) => FilterChip(
                            label: Text(e.value),
                            selected: cfg.campos.contains(e.key),
                            onSelected: (v) => setState(() {
                              if (v) {
                                if (!cfg.campos.contains(e.key)) cfg.campos.add(e.key);
                              } else {
                                cfg.campos.remove(e.key);
                              }
                            }),
                          ))
                      .toList(),
                ),
              ],
            ]),

          // ------------------------------------------- Título, data e hora
          _secao(
            'Título, data e hora',
            [
              const Text('Título nas folhas', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'todas', label: Text('Todas as folhas')),
                  ButtonSegment(value: 'primeira', label: Text('Só a 1ª')),
                  ButtonSegment(value: 'nenhum', label: Text('Nenhuma')),
                ],
                selected: {cfg.tituloModo},
                onSelectionChanged: (s) => setState(() => cfg.tituloModo = s.first),
              ),
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mostrar data'),
                value: cfg.incluirData,
                onChanged: (v) => setState(() => cfg.incluirData = v),
              ),
              if (cfg.incluirData) ...[
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'hoje', label: Text('Data de hoje')),
                    ButtonSegment(value: 'escolhida', label: Text('Escolher data')),
                  ],
                  selected: {cfg.dataModo},
                  onSelectionChanged: (s) => setState(() {
                    cfg.dataModo = s.first;
                    if (cfg.dataModo == 'escolhida' && cfg.dataEscolhida.isEmpty) {
                      final h = DateTime.now();
                      cfg.dataEscolhida = isoData(DateTime.utc(h.year, h.month, h.day));
                    }
                  }),
                ),
                if (cfg.dataModo == 'escolhida')
                  SeletorData(
                    rotulo: 'Data do documento',
                    inicial: parseNascimento(cfg.dataEscolhida),
                    onChanged: (d) {
                      if (d != null) cfg.dataEscolhida = isoData(d);
                    },
                  ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mostrar hora'),
                value: cfg.incluirHora,
                onChanged: (v) => setState(() => cfg.incluirHora = v),
              ),
              if (cfg.incluirHora) ...[
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'agora', label: Text('Hora de agora')),
                    ButtonSegment(value: 'escolhida', label: Text('Escolher hora')),
                  ],
                  selected: {cfg.horaModo},
                  onSelectionChanged: (s) => setState(() {
                    cfg.horaModo = s.first;
                    if (cfg.horaModo == 'escolhida' && cfg.horaEscolhida == 0) {
                      final h = DateTime.now();
                      cfg.horaEscolhida = h.hour * 60 + h.minute;
                    }
                  }),
                ),
                if (cfg.horaModo == 'escolhida')
                  SeletorHora(
                    rotulo: 'Hora do documento',
                    minutos: cfg.horaEscolhida,
                    onChanged: (m) => cfg.horaEscolhida = m,
                  ),
              ],
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Data e hora em destaque'),
                subtitle: const Text('Grandes, no tamanho do título, ao lado dele'),
                value: cfg.dataHoraGrande,
                onChanged: (v) => setState(() => cfg.dataHoraGrande = v),
              ),
              if (cfg.dataHoraGrande)
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'e', label: Text('Esquerda do título')),
                    ButtonSegment(value: 'd', label: Text('Direita do título')),
                  ],
                  selected: {cfg.dataHoraLado},
                  onSelectionChanged: (s) => setState(() => cfg.dataHoraLado = s.first),
                ),
              if (lista != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('O formato (dd/mm/aaaa, 12h ou 24h) é o escolhido nesta lista.',
                      style: TextStyle(fontSize: 12, color: esquema.onSurfaceVariant)),
                ),
            ],
          ),

          // ------------------------------------------------------ Margens
          _secao(
            'Margens',
            [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Usar margens'),
                subtitle: Text(cfg.usarMargens
                    ? 'Distância entre o conteúdo e a borda da folha'
                    : 'Sem margens: algumas impressoras cortam as bordas'),
                value: cfg.usarMargens,
                onChanged: (v) => setState(() => cfg.usarMargens = v),
              ),
              Row(children: [
                _campoMm('Superior', sup),
                const SizedBox(width: 8),
                _campoMm('Inferior', inf),
              ]),
              Row(children: [
                _campoMm('Esquerda', esq),
                const SizedBox(width: 8),
                _campoMm('Direita', dir),
              ]),
            ],
          ),

          // -------------------------------------------------- Logo no canto
          _secao(
            'Logo no canto das folhas',
            [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Carimbar logo em todas as folhas'),
                value: cfg.usarCarimbo,
                onChanged: (v) => setState(() => cfg.usarCarimbo = v),
              ),
              _seletorLogo(
                b64: cfg.carimboBase64,
                onEscolher: () async {
                  final b = await _escolherImagem();
                  if (b != null) setState(() => cfg.carimboBase64 = b);
                },
                onRemover: () => setState(() => cfg.carimboBase64 = null),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: cfg.carimboPosicao,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Canto'),
                items: const [
                  DropdownMenuItem(value: 'bd', child: Text('Inferior direito')),
                  DropdownMenuItem(value: 'be', child: Text('Inferior esquerdo')),
                  DropdownMenuItem(value: 'td', child: Text('Superior direito')),
                  DropdownMenuItem(value: 'te', child: Text('Superior esquerdo')),
                ],
                onChanged: (v) => setState(() => cfg.carimboPosicao = v ?? 'bd'),
              ),
              const SizedBox(height: 6),
              Text('Altura da logo: ${cfg.tamanhoCarimbo.round()} mm'),
              Slider(
                min: 10,
                max: 50,
                divisions: 40,
                value: cfg.tamanhoCarimbo.clamp(10.0, 50.0).toDouble(),
                onChanged: (v) => setState(() => cfg.tamanhoCarimbo = v),
              ),
            ],
          ),

          // --------------------------------------------------- Assinaturas
          _secao(
            'Assinaturas',
            [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Espaço para assinatura do pastor presidente'),
                value: cfg.assinaturaPastor,
                onChanged: (v) => setState(() => cfg.assinaturaPastor = v),
              ),
              if (cfg.assinaturaPastor) ...[
                DropdownButtonFormField<String>(
                  value: cfg.assinaturaPastorOnde,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Em quais folhas'),
                  items: const [
                    DropdownMenuItem(value: 'todas', child: Text('Em todas as folhas')),
                    DropdownMenuItem(value: 'primeira', child: Text('Só na primeira folha')),
                    DropdownMenuItem(value: 'ultima', child: Text('Só na última folha')),
                  ],
                  onChanged: (v) => setState(() => cfg.assinaturaPastorOnde = v ?? 'ultima'),
                ),
                TextField(
                  controller: pastorCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nome do pastor presidente (opcional)',
                    hintText: 'Aparece abaixo da linha de assinatura',
                  ),
                ),
                if (widget.banco.pastores.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text('Pastores cadastrados (classe Pastor):',
                        style: TextStyle(fontSize: 12, color: esquema.onSurfaceVariant)),
                  ),
                  Wrap(
                    spacing: 8,
                    children: widget.banco.pastores
                        .map((p) => ActionChip(
                              avatar: const Icon(Icons.person, size: 16),
                              label: Text(p.nome),
                              onPressed: () => setState(() => pastorCtrl.text = p.nome),
                            ))
                        .toList(),
                  ),
                ],
              ],
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Coluna de assinatura nas listas'),
                subtitle: const Text(
                    'Só quem está marcado como "requer assinatura" ganha espaço para assinar'),
                value: cfg.colunaAssinatura,
                onChanged: (v) => setState(() => cfg.colunaAssinatura = v),
              ),
            ],
          ),

          // --------------------------------------------------------- Capa
          _secao(
            'Capa',
            [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Gerar capa na primeira folha'),
                subtitle: const Text('Com logo, título, subtítulo e data'),
                value: cfg.usarCapa,
                onChanged: (v) => setState(() => cfg.usarCapa = v),
              ),
              _seletorLogo(
                b64: cfg.capaLogoBase64,
                onEscolher: () async {
                  final b = await _escolherImagem();
                  if (b != null) setState(() => cfg.capaLogoBase64 = b);
                },
                onRemover: () => setState(() => cfg.capaLogoBase64 = null),
                extras: [
                  if (cfg.carimboBase64 != null)
                    TextButton.icon(
                      icon: const Icon(Icons.copy),
                      label: const Text('Usar a logo do canto'),
                      onPressed: () => setState(() => cfg.capaLogoBase64 = cfg.carimboBase64),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: subtituloCtrl,
                decoration: const InputDecoration(
                  labelText: 'Subtítulo da capa (opcional)',
                  hintText: 'Ex: Assembleia Geral, Ceia do Senhor',
                ),
              ),
              const SizedBox(height: 6),
              Text('Altura da logo na capa: ${cfg.tamanhoLogoCapa.round()} mm'),
              Slider(
                min: 20,
                max: 120,
                divisions: 50,
                value: cfg.tamanhoLogoCapa.clamp(20.0, 120.0).toDouble(),
                onChanged: (v) => setState(() => cfg.tamanhoLogoCapa = v),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: esquema.surface,
            border: Border(top: BorderSide(color: esquema.outlineVariant)),
          ),
          child: FilledButton.icon(
            icon: Icon(widget.modoConfig ? Icons.save : Icons.picture_as_pdf),
            label: Text(widget.modoConfig ? 'Salvar opções' : 'Gerar PDF'),
            onPressed: _confirmar,
          ),
        ),
      ),
    );
  }
}
