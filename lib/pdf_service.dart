import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'models.dart';

/// Gera os PDFs a partir das opções de [ConfigPdf]: margens opcionais, título
/// em todas/na primeira/nenhuma folha, data e hora (atuais ou escolhidas, em
/// destaque ou não), logo em um canto, capa, assinatura do pastor presidente e
/// vários layouts.
class PdfService {
  static const Map<String, String> layouts = {
    'simples': 'Lista simples',
    'foto': 'Lista com fotos',
    'presenca': 'Lista de presença (assinatura)',
    'assinaturas': 'Lista de assinaturas (só quem requer)',
    'fichas': 'Fichas cadastrais (uma por página)',
    'agrupado': 'Agrupado por congregação',
    'aniversariantes': 'Aniversariantes por mês',
    'classes': 'Por classes da EBD (matrícula)',
    'ata': 'Ata de reunião',
  };

  static const Map<String, String> camposDisponiveis = {
    'congregacao': 'Congregação',
    'classe': 'Classe',
    'nascimento': 'Nascimento',
    'idade': 'Idade',
    'documento': 'CPF / RG',
    'sexo': 'Sexo',
    'sangue': 'Tipo sanguíneo',
    'telefone': 'Telefone',
    'celular': 'Celular',
    'email': 'E-mail',
  };

  static const Map<String, String> _legendas = {
    'simples': 'Relatório de membros',
    'foto': 'Relatório de membros com fotos',
    'presenca': 'Lista de presença',
    'assinaturas': 'Lista de assinaturas',
    'fichas': 'Fichas cadastrais',
    'agrupado': 'Membros por congregação',
    'aniversariantes': 'Aniversariantes',
    'classes': 'Matrícula por classes da EBD',
    'ata': 'Ata de reunião',
  };

  // ------------------------------------------------------------- utilitários

  static pw.MemoryImage? _img(String? b64) {
    if (b64 == null || b64.isEmpty) return null;
    try {
      return pw.MemoryImage(base64Decode(b64));
    } catch (_) {
      return null;
    }
  }

  static PdfColor _pdfCor(String hex) {
    final c = corDeHex(hex);
    return PdfColor(c.red / 255, c.green / 255, c.blue / 255);
  }

  static String _dataStr(ListaEntidades? l, ConfigPdf cfg) {
    if (!cfg.incluirData) return '';
    final fmt = l?.formatoData == 'mm/aaaa' ? 'MM/yyyy' : 'dd/MM/yyyy';
    return DateFormat(fmt).format(cfg.dataReferencia);
  }

  static String _horaStr(ListaEntidades? l, ConfigPdf cfg) {
    if (!cfg.incluirHora) return '';
    final m = cfg.horaReferenciaMin;
    final dt = DateTime(2000, 1, 1, m ~/ 60, m % 60);
    return DateFormat(l?.formatoHora == '12h' ? 'hh:mm a' : 'HH:mm').format(dt);
  }

  static String _valor(Banco banco, String chave, Entidade m) {
    switch (chave) {
      case 'congregacao':
        return banco.congregacaoPorId(m.congregacaoId)?.nome ?? '-';
      case 'classe':
        return banco.classePorId(m.classe)?.nome ?? '-';
      case 'nascimento':
        return m.dataNascimento == null ? '' : dataBr(m.dataNascimento!);
      case 'idade':
        return m.idadeExibida;
      case 'documento':
        return m.documento;
      case 'sexo':
        return m.sexo == 'N/A' ? '' : m.sexo;
      case 'sangue':
        return m.tipoSanguineo == 'N/A' ? '' : m.tipoSanguineo;
      case 'telefone':
        return m.telefone;
      case 'celular':
        return m.celular;
      case 'email':
        return m.email;
      default:
        for (final c in banco.colunas) {
          if (c.id == chave) return c.exibir(m.valoresAtributosDinamicos[chave]);
        }
        return '';
    }
  }

  static String _rotulo(Banco banco, String chave) {
    final fixo = camposDisponiveis[chave];
    if (fixo != null) return fixo;
    for (final c in banco.colunas) {
      if (c.id == chave) return c.nome;
    }
    return chave;
  }

  static List<String> _chavesCampos(Banco banco, ConfigPdf cfg) {
    final todos = [...camposDisponiveis.keys, ...banco.colunas.map((c) => c.id)];
    return todos.where(cfg.campos.contains).toList();
  }

  static pw.Widget _txt(String s, {bool negrito = false, bool cinza = false}) => pw.Text(
        s,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: negrito ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: cinza ? PdfColors.grey600 : PdfColors.black,
        ),
      );

  static pw.Widget _tabela(
    PdfColor corCab,
    List<String> cabecalho,
    List<List<pw.Widget>> linhas,
    Map<int, pw.TableColumnWidth> larguras,
  ) {
    pw.Widget cel(pw.Widget w) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: w,
        );

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
      columnWidths: larguras,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.TableRow(
          repeat: true,
          decoration: pw.BoxDecoration(color: corCab),
          children: cabecalho
              .map((h) => cel(pw.Text(h,
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white))))
              .toList(),
        ),
        ...linhas.map((l) => pw.TableRow(children: l.map(cel).toList())),
      ],
    );
  }

  static pw.Widget _foto(Entidade m) {
    final img = _img(m.fotoBase64);
    if (img == null) return pw.SizedBox(width: 36, height: 42);
    return pw.Container(width: 36, height: 42, child: pw.Image(img, fit: pw.BoxFit.cover));
  }

  static pw.Widget _titulo(String texto, PdfColor cor) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6, bottom: 6),
        child: pw.Row(children: [
          pw.Container(
            width: 10,
            height: 10,
            decoration: pw.BoxDecoration(color: cor, shape: pw.BoxShape.circle),
          ),
          pw.SizedBox(width: 6),
          pw.Text(texto, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ]),
      );

  // ------------------------------------------------------------------ layouts

  static pw.Widget _tabelaLista({
    required Banco banco,
    required List<Entidade> membros,
    required ConfigPdf cfg,
    required PdfColor corCab,
    required bool comFoto,
  }) {
    final chaves = _chavesCampos(banco, cfg);
    final comAssin = cfg.colunaAssinatura;
    final cab = [
      'Nº',
      if (comFoto) 'Foto',
      'Nome',
      ...chaves.map((k) => _rotulo(banco, k)),
      if (comAssin) 'Assinatura',
    ];

    final larg = <int, pw.TableColumnWidth>{};
    var i = 0;
    larg[i++] = const pw.FixedColumnWidth(26);
    if (comFoto) larg[i++] = const pw.FixedColumnWidth(46);
    larg[i++] = const pw.FlexColumnWidth(3);
    for (var k = 0; k < chaves.length; k++) {
      larg[i++] = const pw.FlexColumnWidth(1.5);
    }
    if (comAssin) larg[i++] = const pw.FlexColumnWidth(2.2);

    final linhas = <List<pw.Widget>>[];
    for (var n = 0; n < membros.length; n++) {
      final m = membros[n];
      linhas.add([
        _txt('${n + 1}'),
        if (comFoto) _foto(m),
        _txt(m.nome, negrito: true),
        ...chaves.map((k) => _txt(_valor(banco, k, m))),
        // Só quem requer assinatura ganha espaço para assinar.
        if (comAssin) (m.requerAssinatura ? pw.SizedBox(height: 18) : _txt('-', cinza: true)),
      ]);
    }
    return _tabela(corCab, cab, linhas, larg);
  }

  static pw.Widget _tabelaPresenca(Banco banco, List<Entidade> membros, PdfColor corCab) {
    final linhas = <List<pw.Widget>>[];
    for (var n = 0; n < membros.length; n++) {
      final m = membros[n];
      linhas.add([
        _txt('${n + 1}'),
        _txt(m.nome, negrito: true),
        _txt(_valor(banco, 'congregacao', m)),
        _txt(m.documento),
        pw.SizedBox(height: 16),
      ]);
    }
    return _tabela(
      corCab,
      ['Nº', 'Nome do membro', 'Congregação', 'CPF / RG', 'Assinatura'],
      linhas,
      {
        0: const pw.FixedColumnWidth(26),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FlexColumnWidth(1.6),
        3: const pw.FlexColumnWidth(1.6),
        4: const pw.FlexColumnWidth(3),
      },
    );
  }

  static List<pw.Widget> _assinaturas(Banco banco, List<Entidade> membros, PdfColor corCab) {
    if (membros.isEmpty) {
      return [pw.Text('Nenhum membro marcado como "requer assinatura".')];
    }
    final linhas = <List<pw.Widget>>[];
    for (var n = 0; n < membros.length; n++) {
      final m = membros[n];
      linhas.add([
        _txt('${n + 1}'),
        _txt(m.assinaturaNome.isEmpty ? m.nome : m.assinaturaNome, negrito: true),
        _txt(m.assinaturaCargo),
        _txt(m.documento),
        pw.SizedBox(height: 24),
      ]);
    }
    return [
      _tabela(
        corCab,
        ['Nº', 'Nome', 'Cargo / função', 'CPF / RG', 'Assinatura'],
        linhas,
        {
          0: const pw.FixedColumnWidth(26),
          1: const pw.FlexColumnWidth(3),
          2: const pw.FlexColumnWidth(2),
          3: const pw.FlexColumnWidth(1.6),
          4: const pw.FlexColumnWidth(3),
        },
      ),
    ];
  }

  static List<pw.Widget> _agrupado(Banco banco, List<Entidade> membros, ConfigPdf cfg) {
    final grupos = <MapEntry<Congregacao?, List<Entidade>>>[];
    for (final c in banco.todasCongregacoes) {
      final l = membros.where((m) => banco.congregacaoEfetiva(m) == c.id).toList();
      if (l.isNotEmpty) grupos.add(MapEntry(c, l));
    }
    final sem = membros.where((m) => banco.congregacaoEfetiva(m).isEmpty).toList();
    if (sem.isNotEmpty) grupos.add(MapEntry(null, sem));

    final out = <pw.Widget>[];
    for (final g in grupos) {
      final cor = g.key == null ? PdfColors.grey600 : _pdfCor(g.key!.cor);
      out.add(_titulo('${g.key?.nome ?? 'Sem congregação'} (${g.value.length})', cor));
      out.add(_tabelaLista(
          banco: banco, membros: g.value, cfg: cfg, corCab: cor, comFoto: false));
      out.add(pw.SizedBox(height: 12));
    }
    out.add(pw.Text('Total: ${membros.length} membro(s)',
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)));
    return out;
  }

  static List<pw.Widget> _aniversariantes(
      Banco banco, List<Entidade> membros, DateTime ref, PdfColor cor) {
    final porMes = <int, List<Entidade>>{};
    var semData = 0;
    for (final m in membros) {
      final n = m.dataNascimento;
      if (n == null) {
        semData++;
        continue;
      }
      porMes.putIfAbsent(n.month, () => []).add(m);
    }

    final out = <pw.Widget>[];
    for (var mes = 1; mes <= 12; mes++) {
      final l = porMes[mes];
      if (l == null) continue;
      l.sort((a, b) {
        final c = a.dataNascimento!.day.compareTo(b.dataNascimento!.day);
        return c != 0 ? c : normalizarTexto(a.nome).compareTo(normalizarTexto(b.nome));
      });
      out.add(_titulo('${kMeses[mes - 1]} (${l.length})', cor));
      out.add(_tabela(
        cor,
        ['Dia', 'Nome', 'Congregação', 'Completa', 'Contato'],
        l
            .map((m) => [
                  _txt(m.dataNascimento!.day.toString().padLeft(2, '0')),
                  _txt(m.nome, negrito: true),
                  _txt(_valor(banco, 'congregacao', m)),
                  _txt('${ref.year - m.dataNascimento!.year} anos'),
                  _txt(m.contato),
                ])
            .toList(),
        {
          0: const pw.FixedColumnWidth(30),
          1: const pw.FlexColumnWidth(3),
          2: const pw.FlexColumnWidth(1.6),
          3: const pw.FlexColumnWidth(1.2),
          4: const pw.FlexColumnWidth(1.8),
        },
      ));
      out.add(pw.SizedBox(height: 12));
    }
    if (out.isEmpty) {
      out.add(pw.Text('Nenhum aniversariante com data de nascimento cadastrada.'));
    }
    if (semData > 0) {
      out.add(pw.Text('$semData membro(s) sem data de nascimento não aparecem nesta lista.',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)));
    }
    return out;
  }

  static List<pw.Widget> _classes(Banco banco, List<Entidade> membros, PdfColor cor) {
    final grupos = <MapEntry<String, List<Entidade>>>[];
    for (final c in banco.classes) {
      final l = membros.where((m) => banco.classeEfetiva(m) == c.id).toList();
      if (l.isNotEmpty) grupos.add(MapEntry(c.nome, l));
    }
    final sem = membros.where((m) => banco.classeEfetiva(m).isEmpty).toList();
    if (sem.isNotEmpty) grupos.add(MapEntry('Sem classe', sem));

    final out = <pw.Widget>[];
    for (final g in grupos) {
      out.add(_titulo('${g.key} (${g.value.length})', cor));
      final linhas = <List<pw.Widget>>[];
      for (var n = 0; n < g.value.length; n++) {
        final m = g.value[n];
        linhas.add([
          _txt('${n + 1}'),
          _txt(m.nome, negrito: true),
          _txt(m.idadeExibida),
          _txt(_valor(banco, 'congregacao', m)),
          _txt(m.contato),
          pw.SizedBox(height: 16),
        ]);
      }
      out.add(_tabela(
        cor,
        ['Nº', 'Nome', 'Idade', 'Congregação', 'Contato', 'Assinatura'],
        linhas,
        {
          0: const pw.FixedColumnWidth(26),
          1: const pw.FlexColumnWidth(3),
          2: const pw.FixedColumnWidth(36),
          3: const pw.FlexColumnWidth(1.6),
          4: const pw.FlexColumnWidth(1.6),
          5: const pw.FlexColumnWidth(2.4),
        },
      ));
      out.add(pw.SizedBox(height: 12));
    }
    out.add(pw.Text('Total: ${membros.length} membro(s)',
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)));
    return out;
  }

  static List<pw.Widget> _ficha(Banco banco, Entidade m) {
    final foto = _img(m.fotoBase64);
    final cong = banco.congregacaoPorId(m.congregacaoId);
    final classe = banco.classePorId(m.classe);
    final nasc = m.dataNascimento;
    return [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (foto != null)
            pw.Container(
              width: 90,
              height: 110,
              margin: const pw.EdgeInsets.only(right: 16),
              child: pw.Image(foto, fit: pw.BoxFit.cover),
            ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Nome: ${m.nome}',
                    style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text('Congregação: ${cong?.nome ?? '-'}'),
                pw.Text('Classe (EBD): ${classe?.nome ?? '-'}'),
                pw.Text(
                    'Nascimento: ${nasc == null ? '-' : dataBr(nasc)} | Idade: ${m.idadeExibida}'),
                pw.Text('CPF: ${m.cpf} | RG: ${m.rg}'),
                pw.Text('Sexo: ${m.sexo} | Tipo sanguíneo: ${m.tipoSanguineo}'),
                pw.Text('Telefone: ${m.telefone} | Celular: ${m.celular}'),
                pw.Text('E-mail: ${m.email}'),
              ],
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 18),
      pw.Divider(),
      if (banco.colunas.isNotEmpty)
        pw.Text('Informações adicionais',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
      pw.SizedBox(height: 6),
      ...banco.colunas.map((c) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Text('${c.nome}: ${c.exibir(m.valoresAtributosDinamicos[c.id])}'),
          )),
      if (m.requerAssinatura) ...[
        pw.SizedBox(height: 44),
        pw.Center(
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Container(width: 220, height: 0.6, color: PdfColors.grey800),
              pw.SizedBox(height: 3),
              pw.Text(m.assinaturaNome.isEmpty ? m.nome : m.assinaturaNome,
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              if (m.assinaturaCargo.isNotEmpty)
                pw.Text(m.assinaturaCargo, style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
      ],
    ];
  }

  // ---------------------------------------------------------------------- ata

  /// Troca aspas/travessões "bonitos" (comuns em textos do Word) por equivalentes
  /// que a fonte padrão do PDF consegue desenhar.
  static String limpar(String s) {
    return s
        .replaceAll('\u201C', '"')
        .replaceAll('\u201D', '"')
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'")
        .replaceAll('\u2013', '-')
        .replaceAll('\u2014', '-')
        .replaceAll('\u2026', '...')
        .replaceAll('\u2022', '-')
        .replaceAll('\u00A0', ' ')
        .replaceAll('\t', '    ');
  }

  static String _rotuloMes(String mes) {
    final p = mes.split('-');
    if (p.length != 2) return '';
    final m = int.tryParse(p[1]);
    if (m == null || m < 1 || m > 12) return '';
    return ' · ${kMeses[m - 1]}/${p[0]}';
  }

  static pw.Widget _secaoTitulo(String texto, PdfColor cor) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 12, bottom: 6),
        padding: const pw.EdgeInsets.only(bottom: 3),
        decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: cor, width: 1))),
        child: pw.Text(texto, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      );

  static pw.Widget _subtitulo(String texto) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6, bottom: 4),
        child: pw.Text(texto, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      );

  /// Marcação simples das anotações: "# Título", "## Subtítulo", "- item",
  /// **negrito** e linhas em branco.
  static List<pw.Widget> _renderTexto(String texto) {
    pw.Widget paragrafo(String linha, {double tamanho = 11, bool negritoTodo = false}) {
      final partes = linha.split('**');
      final spans = <pw.InlineSpan>[];
      for (var i = 0; i < partes.length; i++) {
        if (partes[i].isEmpty) continue;
        final negrito = negritoTodo || i.isOdd;
        spans.add(pw.TextSpan(
          text: partes[i],
          style: pw.TextStyle(
              fontSize: tamanho, fontWeight: negrito ? pw.FontWeight.bold : pw.FontWeight.normal),
        ));
      }
      return pw.RichText(text: pw.TextSpan(children: spans));
    }

    final out = <pw.Widget>[];
    for (final bruta in limpar(texto).split('\n')) {
      final l = bruta.trimRight();
      if (l.trim().isEmpty) {
        out.add(pw.SizedBox(height: 6));
      } else if (l.startsWith('## ')) {
        out.add(pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4, bottom: 2),
            child: paragrafo(l.substring(3), tamanho: 12, negritoTodo: true)));
      } else if (l.startsWith('# ')) {
        out.add(pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6, bottom: 3),
            child: paragrafo(l.substring(2), tamanho: 14, negritoTodo: true)));
      } else if (l.startsWith('- ')) {
        out.add(pw.Padding(
          padding: const pw.EdgeInsets.only(left: 12, bottom: 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('-  ', style: const pw.TextStyle(fontSize: 11)),
              pw.Expanded(child: paragrafo(l.substring(2))),
            ],
          ),
        ));
      } else {
        out.add(pw.Padding(padding: const pw.EdgeInsets.only(bottom: 3), child: paragrafo(l)));
      }
    }
    return out;
  }

  static String _ddmm(String iso) {
    final d = parseNascimento(iso);
    if (d == null) return '-';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  static List<pw.Widget> _corpoAta(Banco banco, Ata a, PdfColor cor) {
    final out = <pw.Widget>[];

    // Movimento de membros (automático)
    if (a.incluirMovimentos) {
      final mv = banco.movimentosDaAta(a);
      final entradas = mv.where((m) => m.tipo == 'entrada').toList();
      final saidas = mv.where((m) => m.tipo == 'saida').toList();
      out.add(_secaoTitulo('Movimento de membros', cor));
      if (mv.isEmpty) {
        out.add(pw.Text('Nenhuma entrada ou saída no período.',
            style: const pw.TextStyle(fontSize: 11)));
      }
      if (entradas.isNotEmpty) {
        out.add(_subtitulo('Entradas (${entradas.length})'));
        out.add(_tabela(
          cor,
          ['Data', 'Nome', 'Observação'],
          entradas
              .map((m) => [_txt(_ddmm(m.data)), _txt(limpar(m.nome), negrito: true), _txt(limpar(m.motivo))])
              .toList(),
          {
            0: const pw.FixedColumnWidth(44),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FlexColumnWidth(2),
          },
        ));
      }
      if (saidas.isNotEmpty) {
        out.add(_subtitulo('Saídas (${saidas.length})'));
        out.add(_tabela(
          cor,
          ['Data', 'Nome', 'Motivo'],
          saidas
              .map((m) => [_txt(_ddmm(m.data)), _txt(limpar(m.nome), negrito: true), _txt(limpar(m.motivo))])
              .toList(),
          {
            0: const pw.FixedColumnWidth(44),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FlexColumnWidth(2),
          },
        ));
      }
    }

    // Registros por categoria
    if (a.registros.isNotEmpty) {
      out.add(_secaoTitulo('Registros', cor));
      for (final cat in kCategoriasRegistro.keys) {
        final l = a.registros.where((r) => r.categoria == cat).toList()
          ..sort((x, y) => x.data.compareTo(y.data));
        if (l.isEmpty) continue;
        out.add(_subtitulo('${kCategoriasRegistro[cat]} (${l.length})'));
        for (final r in l) {
          out.add(pw.Padding(
            padding: const pw.EdgeInsets.only(left: 8, bottom: 3),
            child: pw.Text('${_ddmm(r.data)} - ${limpar(r.texto)}',
                style: const pw.TextStyle(fontSize: 11)),
          ));
        }
      }
    }

    // Anotações livres
    if (a.texto.trim().isNotEmpty) {
      out.add(_secaoTitulo('Anotações', cor));
      out.addAll(_renderTexto(a.texto));
    }

    // Assinaturas dos membros que requerem
    if (a.assinaturasMembros) {
      final quem = banco.ativos.where((m) => m.requerAssinatura).toList();
      out.add(_secaoTitulo('Assinaturas', cor));
      out.addAll(_assinaturas(banco, quem, cor));
    }

    if (out.isEmpty) out.add(pw.Text('Ata sem conteúdo.'));
    return out;
  }

  static pw.Page _capa({
    required PdfPageFormat formato,
    required pw.EdgeInsets margem,
    required pw.MemoryImage? logo,
    required double alturaLogo,
    required String titulo,
    required String subtitulo,
    required String dataStr,
    required String horaStr,
    required bool grande,
    required String legenda,
    required int total,
  }) {
    final dh = [dataStr, horaStr].where((e) => e.isNotEmpty).join(' ');
    return pw.Page(
      pageFormat: formato,
      margin: margem,
      build: (pw.Context ctx) => pw.Center(
        child: pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 24),
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              if (logo != null) pw.Image(logo, height: alturaLogo, fit: pw.BoxFit.contain),
              if (logo != null) pw.SizedBox(height: 28),
              pw.Text(titulo,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold)),
              if (subtitulo.isNotEmpty) ...[
                pw.SizedBox(height: 10),
                pw.Text(subtitulo,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 15, color: PdfColors.grey700)),
              ],
              pw.SizedBox(height: 22),
              pw.Text(legenda,
                  style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
              if (dh.isNotEmpty)
                pw.Text(dh,
                    style: grande
                        ? pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)
                        : const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
              if (total >= 0)
                pw.Text('$total membro(s)',
                    style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------- gerar

  static Future<Uint8List> gerar({
    required Banco banco,
    ListaEntidades? lista,
    required List<Entidade> membros,
    required String titulo,
    required ConfigPdf cfg,
    Ata? ata,
  }) async {
    final pdf = pw.Document();
    final mm = PdfPageFormat.mm;
    final formato = cfg.paisagem ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
    final margem = cfg.usarMargens
        ? pw.EdgeInsets.fromLTRB(cfg.margemEsquerda * mm, cfg.margemSuperior * mm,
            cfg.margemDireita * mm, cfg.margemInferior * mm)
        : pw.EdgeInsets.zero;

    final itens = cfg.layout == 'assinaturas'
        ? membros.where((m) => m.requerAssinatura).toList()
        : membros;

    final corLista = _pdfCor(lista?.corTema ?? '#1B2A4A');
    final dataStr = _dataStr(lista, cfg);
    final horaStr = _horaStr(lista, cfg);
    final dh = [dataStr, horaStr].where((e) => e.isNotEmpty).join(' ');
    final grande = cfg.dataHoraGrande && dh.isNotEmpty;
    var legenda = _legendas[cfg.layout] ?? 'Relatório';
    if (cfg.layout == 'ata' && ata != null) {
      legenda = ata.tipo == 'ordinaria'
          ? 'Ata ordinária${_rotuloMes(ata.mes)}'
          : 'Ata extraordinária';
    }
    final carimbo = cfg.usarCarimbo ? _img(cfg.carimboBase64) : null;
    final altCarimbo = cfg.tamanhoCarimbo * mm;

    // ---- capa
    if (cfg.usarCapa) {
      pdf.addPage(_capa(
        formato: formato,
        margem: margem,
        logo: _img(cfg.capaLogoBase64),
        alturaLogo: cfg.tamanhoLogoCapa * mm,
        titulo: titulo,
        subtitulo: cfg.capaSubtitulo,
        dataStr: dataStr,
        horaStr: horaStr,
        grande: grande,
        legenda: legenda,
        total: cfg.layout == 'ata' ? -1 : itens.length,
      ));
    }

    // ---- cabeçalho / rodapé
    final mostrarTitulo = cfg.tituloModo != 'nenhum';
    final carimboTopo = carimbo != null && cfg.carimboPosicao.startsWith('t');
    final carimboBaixo = carimbo != null && cfg.carimboPosicao.startsWith('b');
    final carimboEsq = cfg.carimboPosicao.endsWith('e');

    pw.Widget stamp() => pw.Image(carimbo!, height: altCarimbo, fit: pw.BoxFit.contain);

    pw.Widget tituloBloco() {
      final bloco = pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (titulo.isNotEmpty)
            pw.Text(titulo, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(
            [legenda, if (!grande && dh.isNotEmpty) dh].join(' | '),
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      );
      if (!grande) return bloco;

      // Data e hora em destaque, no tamanho do título, ao lado dele.
      final esq = cfg.dataHoraLado == 'e';
      final destaque = pw.Column(
        crossAxisAlignment: esq ? pw.CrossAxisAlignment.start : pw.CrossAxisAlignment.end,
        children: [
          if (dataStr.isNotEmpty)
            pw.Text(dataStr, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          if (horaStr.isNotEmpty)
            pw.Text(horaStr, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        ],
      );
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: esq
            ? [destaque, pw.SizedBox(width: 16), pw.Expanded(child: bloco)]
            : [pw.Expanded(child: bloco), pw.SizedBox(width: 16), destaque],
      );
    }

    // Assinatura do pastor presidente.
    pw.Widget assinaturaPastor() => pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.SizedBox(height: 26),
            pw.Container(width: 190, height: 0.6, color: PdfColors.grey800),
            pw.SizedBox(height: 3),
            pw.Text('Pastor Presidente',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            if (cfg.pastorNome.trim().isNotEmpty)
              pw.Text(cfg.pastorNome.trim(), style: const pw.TextStyle(fontSize: 9)),
          ],
        );

    final titulosEmTodas = mostrarTitulo && cfg.tituloModo == 'todas';
    final temHeader = titulosEmTodas || carimboTopo;
    final primeiraPagina = cfg.usarCapa ? 2 : 1; // a capa conta como página 1

    // ---- corpo
    final corpo = <pw.Widget>[];
    if (mostrarTitulo && cfg.tituloModo == 'primeira') {
      corpo.add(tituloBloco());
      corpo.add(pw.SizedBox(height: 10));
    }
    switch (cfg.layout) {
      case 'presenca':
        corpo.add(_tabelaPresenca(banco, itens, corLista));
        break;
      case 'assinaturas':
        corpo.addAll(_assinaturas(banco, itens, corLista));
        break;
      case 'fichas':
        for (var i = 0; i < itens.length; i++) {
          corpo.addAll(_ficha(banco, itens[i]));
          if (i < itens.length - 1) corpo.add(pw.NewPage());
        }
        break;
      case 'agrupado':
        corpo.addAll(_agrupado(banco, itens, cfg));
        break;
      case 'aniversariantes':
        corpo.addAll(_aniversariantes(banco, itens, cfg.dataReferencia, corLista));
        break;
      case 'classes':
        corpo.addAll(_classes(banco, itens, corLista));
        break;
      case 'ata':
        if (ata != null) corpo.addAll(_corpoAta(banco, ata, corLista));
        break;
      default:
        corpo.add(_tabelaLista(
          banco: banco,
          membros: itens,
          cfg: cfg,
          corCab: corLista,
          comFoto: cfg.layout == 'foto',
        ));
    }
    // Assinatura só na última folha: entra no fim do conteúdo.
    if (cfg.assinaturaPastor && cfg.assinaturaPastorOnde == 'ultima') {
      corpo.add(pw.SizedBox(height: 30));
      corpo.add(pw.Center(child: assinaturaPastor()));
    }

    pdf.addPage(pw.MultiPage(
      pageFormat: formato,
      margin: margem,
      header: temHeader
          ? (pw.Context ctx) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (carimboTopo && carimboEsq) stamp(),
                    if (carimboTopo && carimboEsq) pw.SizedBox(width: 12),
                    pw.Expanded(child: titulosEmTodas ? tituloBloco() : pw.SizedBox()),
                    if (carimboTopo && !carimboEsq) pw.SizedBox(width: 12),
                    if (carimboTopo && !carimboEsq) stamp(),
                  ],
                ),
              )
          : null,
      footer: (pw.Context ctx) {
        // Em "todas" ou "primeira" a assinatura fica no rodapé (o espaço é
        // reservado só nas páginas em que ela aparece).
        final comAssinatura = cfg.assinaturaPastor &&
            (cfg.assinaturaPastorOnde == 'todas' ||
                (cfg.assinaturaPastorOnde == 'primeira' && ctx.pageNumber == primeiraPagina));
        return pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            if (comAssinatura) pw.Center(child: assinaturaPastor()),
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Expanded(
                    child: pw.Align(
                      alignment: pw.Alignment.centerLeft,
                      child: (carimboBaixo && carimboEsq) ? stamp() : pw.SizedBox(),
                    ),
                  ),
                  pw.Text('Pág. ${ctx.pageNumber}/${ctx.pagesCount}',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                  pw.Expanded(
                    child: pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: (carimboBaixo && !carimboEsq) ? stamp() : pw.SizedBox(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
      build: (pw.Context ctx) => corpo,
    ));

    return pdf.save();
  }

  // --------------------------------------------------------------------- aviso

  /// Comunicado (aviso do Mural) em uma folha: logo, título, data, texto e,
  /// se ligada nas opções de impressão, assinatura do pastor presidente.
  static Future<Uint8List> aviso({required Aviso aviso, required ConfigPdf cfg}) async {
    final pdf = pw.Document();
    final mm = PdfPageFormat.mm;
    final margem = cfg.usarMargens
        ? pw.EdgeInsets.fromLTRB(cfg.margemEsquerda * mm, cfg.margemSuperior * mm,
            cfg.margemDireita * mm, cfg.margemInferior * mm)
        : pw.EdgeInsets.zero;
    final logo = cfg.usarCarimbo ? _img(cfg.carimboBase64) : null;
    final data = DateFormat('dd/MM/yyyy').format(
        aviso.criadoEm > 0 ? DateTime.fromMillisecondsSinceEpoch(aviso.criadoEm) : DateTime.now());
    final paragrafos = aviso.texto.split('\n');

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: margem,
      build: (pw.Context ctx) => [
        if (logo != null)
          pw.Center(child: pw.Image(logo, height: cfg.tamanhoCarimbo * mm * 1.6, fit: pw.BoxFit.contain)),
        if (logo != null) pw.SizedBox(height: 18),
        pw.Center(
          child: pw.Text('AVISO',
              style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700, letterSpacing: 3)),
        ),
        pw.SizedBox(height: 6),
        pw.Center(
          child: pw.Text(aviso.titulo,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(data, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
        ),
        pw.SizedBox(height: 16),
        pw.Divider(),
        pw.SizedBox(height: 12),
        for (final p in paragrafos)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Text(p.isEmpty ? ' ' : p,
                style: const pw.TextStyle(fontSize: 13, lineSpacing: 3)),
          ),
        if (cfg.assinaturaPastor) ...[
          pw.SizedBox(height: 50),
          pw.Center(
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Container(width: 190, height: 0.6, color: PdfColors.grey800),
                pw.SizedBox(height: 3),
                pw.Text('Pastor Presidente',
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                if (cfg.pastorNome.trim().isNotEmpty)
                  pw.Text(cfg.pastorNome.trim(), style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ),
        ],
      ],
    ));

    return pdf.save();
  }
}
