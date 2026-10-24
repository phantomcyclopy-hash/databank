import 'dart:convert';
import 'dart:io' show ZLibCodec;

import 'package:archive/archive.dart';

import 'importador.dart';

class LeituraException implements Exception {
  final String mensagem;
  LeituraException(this.mensagem);
  @override
  String toString() => mensagem;
}

/// Extrai o TEXTO de um arquivo .txt, .docx ou .pdf (sem formatação).
/// Lança [LeituraException] com uma mensagem clara quando não der.
String extrairTexto(String nomeArquivo, List<int> bytes) {
  final ext = nomeArquivo.contains('.') ? nomeArquivo.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'txt':
      return Importador.decodificar(bytes).trim();
    case 'docx':
      return _docx(bytes);
    case 'pdf':
      return _pdf(bytes);
    case 'doc':
      throw LeituraException(
          'Arquivos .doc (Word antigo) não são suportados. Abra no Word e salve como .docx.');
    default:
      throw LeituraException('Formato não suportado: .$ext (use .docx, .pdf ou .txt).');
  }
}

String _desescapar(String s) {
  return s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)))
      .replaceAll('&amp;', '&');
}

String _compactar(String s) =>
    s.replaceAll('\r', '').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

// ---------------------------------------------------------------------- Word

String _docx(List<int> bytes) {
  Archive arq;
  try {
    arq = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw LeituraException('Não foi possível abrir o .docx (arquivo danificado?).');
  }
  ArchiveFile? doc;
  for (final f in arq.files) {
    if (f.name == 'word/document.xml') doc = f;
  }
  if (doc == null) throw LeituraException('Arquivo .docx inválido (sem conteúdo de texto).');

  final xml = utf8.decode(doc.content as List<int>, allowMalformed: true);
  final b = StringBuffer();
  for (final p in xml.split('</w:p>')) {
    final t = p
        .replaceAll(RegExp(r'<w:tab\s*/>'), '\t')
        .replaceAll(RegExp(r'<w:br\s*/>'), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    b.writeln(_desescapar(t));
  }
  final r = _compactar(b.toString());
  if (r.isEmpty) throw LeituraException('O .docx não tem texto (só imagens?).');
  return r;
}

// ----------------------------------------------------------------------- PDF
// Extração "melhor esforço" em Dart puro: lê os fluxos de conteúdo (Flate) e
// junta os textos. Funciona para a maioria dos PDFs gerados por editores de
// texto; PDFs digitalizados (imagem) ou com fontes especiais não têm texto
// recuperável.

String _pdf(List<int> bytes) {
  final raw = latin1.decode(bytes); // 1 caractere = 1 byte, índices coincidem
  final saida = StringBuffer();
  var pos = 0;
  while (true) {
    final i = raw.indexOf('stream', pos);
    if (i < 0) break;
    var ini = i + 6;
    if (raw.startsWith('\r\n', ini)) {
      ini += 2;
    } else if (raw.startsWith('\n', ini) || raw.startsWith('\r', ini)) {
      ini += 1;
    }
    final fim = raw.indexOf('endstream', ini);
    if (fim < 0) break;
    pos = fim + 9;

    List<int> conteudo;
    try {
      conteudo = ZLibCodec().decode(bytes.sublist(ini, fim));
    } catch (_) {
      conteudo = bytes.sublist(ini, fim);
    }
    final s = latin1.decode(conteudo, allowInvalid: true);
    if (!s.contains('BT')) continue;
    saida.write(_textoDeConteudo(s));
  }

  final r = _compactar(saida.toString());
  final letras = RegExp(r'[A-Za-zÀ-ÿ]').allMatches(r).length;
  if (letras < 20) {
    throw LeituraException(
        'Não foi possível extrair texto deste PDF (pode ser digitalizado ou usar fontes especiais). '
        'Se puder, exporte o documento como .docx ou .txt e importe de novo.');
  }
  return r;
}

String _literalPdf(String lit) {
  // lit vem sem os parênteses externos
  final b = StringBuffer();
  for (var i = 0; i < lit.length; i++) {
    final c = lit[i];
    if (c != '\\' || i + 1 >= lit.length) {
      b.write(c);
      continue;
    }
    final n = lit[++i];
    switch (n) {
      case 'n':
        b.write('\n');
        break;
      case 'r':
        break;
      case 't':
        b.write(' ');
        break;
      case '(':
      case ')':
      case '\\':
        b.write(n);
        break;
      default:
        if (RegExp(r'[0-7]').hasMatch(n)) {
          var oct = n;
          while (oct.length < 3 && i + 1 < lit.length && RegExp(r'[0-7]').hasMatch(lit[i + 1])) {
            oct += lit[++i];
          }
          b.writeCharCode(int.parse(oct, radix: 8));
        } else {
          b.write(n);
        }
    }
  }
  return b.toString();
}

String _textoDeConteudo(String s) {
  final out = StringBuffer();
  final token = RegExp(r'\((?:\\.|[^\\)])*\)|\[|\]|-?\d+\.?\d*|[A-Za-z*\x27"]+');
  for (final bloco in RegExp(r'BT(.*?)ET', dotAll: true).allMatches(s)) {
    var dentroArray = false;
    for (final t in token.allMatches(bloco.group(1)!)) {
      final x = t.group(0)!;
      if (x.startsWith('(')) {
        out.write(_literalPdf(x.substring(1, x.length - 1)));
      } else if (x == '[') {
        dentroArray = true;
      } else if (x == ']') {
        dentroArray = false;
      } else if (dentroArray && RegExp(r'^-?\d').hasMatch(x)) {
        if ((double.tryParse(x) ?? 0) < -250) out.write(' ');
      } else if (x == 'Td' || x == 'TD' || x == 'T*' || x == "'" || x == '"') {
        out.write('\n');
      }
    }
    out.write('\n');
  }
  return out.toString();
}
