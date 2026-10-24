import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'models.dart';

/// Um membro lido de um arquivo, ainda sem vínculo com uma lista.
class MembroImportado {
  final String nome;
  final String congregacao; // nome em texto
  final Map<String, String> campos; // chaves via normalizarChave()

  MembroImportado({
    required this.nome,
    this.congregacao = '',
    this.campos = const {},
  });
}

/// Backup de lista (formato antigo ou atual), para mesclar no banco.
class BackupExterno {
  final Map<String, dynamic> listaJson;
  final List<dynamic> membrosJson;
  final List<dynamic>? congregacoesJson;
  final List<dynamic>? colunasJson;
  final List<dynamic>? classesJson;

  BackupExterno({
    required this.listaJson,
    required this.membrosJson,
    this.congregacoesJson,
    this.colunasJson,
    this.classesJson,
  });
}

class ResultadoImportacao {
  /// Preenchido quando o JSON é um backup de lista completa.
  final BackupExterno? backup;

  /// Backup COMPLETO do app (tudo): Map do Banco, pronto para Banco.fromJson.
  final Map<String, dynamic>? bancoCompleto;
  final List<MembroImportado> membros;
  final int linhasIgnoradas;

  ResultadoImportacao({
    this.backup,
    this.bancoCompleto,
    this.membros = const [],
    this.linhasIgnoradas = 0,
  });
}

class ResumoImportacao {
  final int novos; // membros criados no cadastro
  final int vinculados; // já cadastrados, agora adicionados à lista
  final int jaExistiam; // já cadastrados (e já na lista, quando há lista)
  final int ignorados;
  final int congregacoesNovas;

  ResumoImportacao({
    required this.novos,
    required this.vinculados,
    required this.jaExistiam,
    required this.ignorados,
    required this.congregacoesNovas,
  });

  String get mensagem {
    final partes = <String>['$novos membro(s) novo(s)'];
    if (vinculados > 0) partes.add('$vinculados já cadastrado(s) adicionado(s) à lista');
    if (jaExistiam > 0) partes.add('$jaExistiam já existia(m)');
    if (ignorados > 0) partes.add('$ignorados linha(s) sem nome ignorada(s)');
    if (congregacoesNovas > 0) {
      partes.add('$congregacoesNovas congregação(ões) nova(s)');
    }
    return partes.join(' · ');
  }
}

class Importador {
  static const List<String> extensoes = ['json', 'csv', 'txt'];

  static const _chavesNome = ['nome', 'name', 'nomecompleto', 'membro'];
  static const _chavesCongregacao = ['congregacao', 'igreja', 'congregation'];
  static const _cabecalhosConhecidos = {
    'nome', 'name', 'nomecompleto', 'membro', 'telefone', 'celular', 'email',
    'cpf', 'rg', 'idade', 'sexo', 'tiposanguineo', 'congregacao', 'igreja',
    'nascimento', 'datanascimento', 'datadenascimento', 'dtnascimento',
    'aniversario', 'classe',
  };

  static const _chavesNascimento = [
    'nascimento', 'datanascimento', 'datadenascimento', 'dtnascimento', 'aniversario',
  ];

  // ------------------------------------------------------------------ leitura

  static String decodificar(List<int> bytes) {
    var b = bytes;
    if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
      b = b.sublist(3); // remove BOM
    }
    try {
      return utf8.decode(b);
    } on FormatException {
      return latin1.decode(b); // CSV/TXT salvos pelo Excel/Bloco de Notas antigo
    }
  }

  static ResultadoImportacao ler(String nomeArquivo, List<int> bytes) {
    final texto = decodificar(bytes);
    final ext =
        nomeArquivo.contains('.') ? nomeArquivo.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'json':
        return _lerJson(texto);
      case 'csv':
        return _lerCsv(texto);
      case 'txt':
        return _lerTxt(texto);
      default:
        throw FormatException('Formato não suportado: .$ext');
    }
  }

  // --------------------------------------------------------------------- JSON

  static ResultadoImportacao _lerJson(String texto) {
    final dados = jsonDecode(texto);

    if (dados is Map) {
      final m = Map<String, dynamic>.from(dados);

      // Backup completo do app: {"tipo": "banco_ibmmkar", "banco": {...}}
      if (m['tipo'] == 'banco_ibmmkar' && m['banco'] is Map) {
        return ResultadoImportacao(
            bancoCompleto: Map<String, dynamic>.from(m['banco'] as Map));
      }
      // Backup de lista (formato atual): {"tipo": "ata_ibmmkar", "lista": {...}, "membros": [...]}
      if (m['tipo'] == 'ata_ibmmkar' && m['lista'] is Map) {
        return ResultadoImportacao(
          backup: BackupExterno(
            listaJson: Map<String, dynamic>.from(m['lista'] as Map),
            membrosJson: (m['membros'] as List?) ?? const [],
            congregacoesJson: m['congregacoes'] as List?,
            colunasJson: m['colunas'] as List?,
            classesJson: m['classes'] as List?,
          ),
        );
      }
      // Backup do cadastro de membros: {"tipo": "membros_ibmmkar", "membros": [...]}
      if (m['tipo'] == 'membros_ibmmkar' && m['membros'] is List) {
        return ResultadoImportacao(
          backup: BackupExterno(
            listaJson: {'id': '', 'titulo': 'Membros importados'},
            membrosJson: m['membros'] as List,
            congregacoesJson: m['congregacoes'] as List?,
            colunasJson: m['colunas'] as List?,
            classesJson: m['classes'] as List?,
          ),
        );
      }
      // Formato antigo: {"tipo": "banco_dinamico_lista", "lista": {...}}
      if (m['tipo'] == 'banco_dinamico_lista' && m['lista'] is Map) {
        return ResultadoImportacao(
            backup: _backupLegado(Map<String, dynamic>.from(m['lista'] as Map)));
      }
      // Formato antigo: lista completa com membros em "linhas"
      if (m.containsKey('titulo') && m['linhas'] is List) {
        return ResultadoImportacao(backup: _backupLegado(m));
      }
      for (final chave in ['membros', 'linhas', 'entidades', 'pessoas']) {
        if (m[chave] is List) return _membrosDeLista(m[chave] as List);
      }
      throw const FormatException(
          'JSON não reconhecido: esperava uma lista de nomes, uma lista de objetos ou um backup de lista.');
    }
    if (dados is List) return _membrosDeLista(dados);
    throw const FormatException('JSON não reconhecido.');
  }

  static BackupExterno _backupLegado(Map<String, dynamic> l) => BackupExterno(
        listaJson: l,
        membrosJson: (l['linhas'] as List?) ?? const [],
        congregacoesJson: l['congregacoes'] as List?,
        colunasJson: l['colunas'] as List?,
      );

  static ResultadoImportacao _membrosDeLista(List itens) {
    final membros = <MembroImportado>[];
    var ignoradas = 0;

    for (final item in itens) {
      if (item is String) {
        final nome = item.trim();
        if (nome.isEmpty) {
          ignoradas++;
        } else {
          membros.add(MembroImportado(nome: nome));
        }
      } else if (item is Map) {
        final campos = <String, String>{};
        item.forEach((k, v) {
          if (v == null || v is Map || v is List) return;
          final valor = v.toString().trim();
          if (valor.isNotEmpty) campos[normalizarChave(k.toString())] = valor;
        });
        final nome = _primeiro(campos, _chavesNome);
        if (nome.isEmpty) {
          ignoradas++;
          continue;
        }
        final cong = _primeiro(campos, _chavesCongregacao);
        for (final k in [..._chavesNome, ..._chavesCongregacao]) {
          campos.remove(k);
        }
        membros.add(MembroImportado(nome: nome, congregacao: cong, campos: campos));
      } else {
        ignoradas++;
      }
    }
    return ResultadoImportacao(membros: membros, linhasIgnoradas: ignoradas);
  }

  static String _primeiro(Map<String, String> campos, List<String> chaves) {
    for (final k in chaves) {
      final v = campos[k];
      if (v != null && v.isNotEmpty) return v;
    }
    return '';
  }

  // ---------------------------------------------------------------------- TXT

  static ResultadoImportacao _lerTxt(String texto) {
    final membros = <MembroImportado>[];
    for (final linha in const LineSplitter().convert(texto)) {
      final nome = linha.trim();
      if (nome.isNotEmpty) membros.add(MembroImportado(nome: nome));
    }
    return ResultadoImportacao(membros: membros);
  }

  // ---------------------------------------------------------------------- CSV

  static ResultadoImportacao _lerCsv(String texto) {
    final sep = _detectarSeparador(texto);
    final linhas = _parseCsv(texto, sep);
    if (linhas.isEmpty) return ResultadoImportacao();

    final normalizadas = linhas.first.map(normalizarChave).toList();
    final temCabecalho = normalizadas.any(_cabecalhosConhecidos.contains);

    final membros = <MembroImportado>[];
    var ignoradas = 0;

    if (!temCabecalho) {
      // Sem cabeçalho: nome = primeira coluna.
      for (final l in linhas) {
        final nome = l.first.trim();
        if (nome.isEmpty) {
          ignoradas++;
        } else {
          membros.add(MembroImportado(nome: nome));
        }
      }
      return ResultadoImportacao(membros: membros, linhasIgnoradas: ignoradas);
    }

    var idxNome = normalizadas.indexWhere(_chavesNome.contains);
    if (idxNome < 0) idxNome = 0;
    final idxCong = normalizadas.indexWhere(_chavesCongregacao.contains);

    for (final l in linhas.skip(1)) {
      final nome = idxNome < l.length ? l[idxNome].trim() : '';
      if (nome.isEmpty) {
        ignoradas++;
        continue;
      }
      final campos = <String, String>{};
      for (var i = 0; i < l.length && i < normalizadas.length; i++) {
        if (i == idxNome || i == idxCong) continue;
        final v = l[i].trim();
        if (v.isNotEmpty && normalizadas[i].isNotEmpty) campos[normalizadas[i]] = v;
      }
      final cong = (idxCong >= 0 && idxCong < l.length) ? l[idxCong].trim() : '';
      membros.add(MembroImportado(nome: nome, congregacao: cong, campos: campos));
    }
    return ResultadoImportacao(membros: membros, linhasIgnoradas: ignoradas);
  }

  static String _detectarSeparador(String texto) {
    final primeira = const LineSplitter()
        .convert(texto)
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    var melhor = ',';
    var max = 0;
    for (final s in [',', ';', '\t']) {
      final n = s.allMatches(primeira).length;
      if (n > max) {
        max = n;
        melhor = s;
      }
    }
    return melhor;
  }

  static List<List<String>> _parseCsv(String texto, String sep) {
    final linhas = <List<String>>[];
    var campo = StringBuffer();
    var linha = <String>[];
    var aspas = false;

    for (var i = 0; i < texto.length; i++) {
      final c = texto[i];
      if (aspas) {
        if (c == '"') {
          if (i + 1 < texto.length && texto[i + 1] == '"') {
            campo.write('"');
            i++;
          } else {
            aspas = false;
          }
        } else {
          campo.write(c);
        }
      } else if (c == '"') {
        aspas = true;
      } else if (c == sep) {
        linha.add(campo.toString());
        campo = StringBuffer();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < texto.length && texto[i + 1] == '\n') i++;
        linha.add(campo.toString());
        campo = StringBuffer();
        linhas.add(linha);
        linha = <String>[];
      } else {
        campo.write(c);
      }
    }
    if (campo.isNotEmpty || linha.isNotEmpty) {
      linha.add(campo.toString());
      linhas.add(linha);
    }
    return linhas.where((l) => l.any((c) => c.trim().isNotEmpty)).toList();
  }

  // ------------------------------------------------------------------ aplicar

  /// Aplica os membros lidos ao banco. Quem já existe (mesmo nome e mesma
  /// congregação; ou só o nome, se o arquivo não traz congregação) é
  /// reaproveitado em vez de duplicado. Com [lista], todos entram na lista.
  static ResumoImportacao aplicar(Banco banco, ResultadoImportacao r,
      {ListaEntidades? lista}) {
    const uuid = Uuid();
    final agora = DateTime.now().millisecondsSinceEpoch;

    var novos = 0;
    var vinculados = 0;
    var jaExistiam = 0;
    var novasCongs = 0;

    for (final mi in r.membros) {
      var cong = banco.congregacaoPorNome(mi.congregacao);
      final nomeNorm = normalizarTexto(mi.nome);
      final semCong = mi.congregacao.trim().isEmpty;

      Entidade? existente;
      for (final m in banco.membros) {
        if (normalizarTexto(m.nome) != nomeNorm) continue;
        if (semCong || (cong != null && banco.congregacaoEfetiva(m) == cong.id)) {
          existente = m;
          break;
        }
      }

      if (existente != null) {
        if (lista != null && !lista.membroIds.contains(existente.id)) {
          lista.membroIds.add(existente.id);
          vinculados++;
        } else {
          jaExistiam++;
        }
        continue;
      }

      if (cong == null && !semCong) {
        cong = Congregacao(
          id: uuid.v4(),
          nome: mi.congregacao.trim(),
          cor: kPaletaCongregacoes[
              banco.congregacoes.length % kPaletaCongregacoes.length],
        );
        banco.congregacoes.add(cong);
        novasCongs++;
      }

      final dinamicos = <String, String>{};
      for (final col in banco.colunas) {
        final v = mi.campos[normalizarChave(col.nome)];
        if (v != null) dinamicos[col.id] = v;
      }

      final novo = Entidade(
        id: uuid.v4(),
        nome: mi.nome,
        congregacaoId: cong?.id ?? '',
        cpf: mi.campos['cpf'] ?? '',
        rg: mi.campos['rg'] ?? '',
        idade: mi.campos['idade'] ?? '',
        nascimento: _nascimento(mi.campos),
        classe: banco.classePorNome(mi.campos['classe'] ?? '')?.id ?? '',
        sexo: _sexo(mi.campos['sexo']),
        tipoSanguineo: _sangue(mi.campos['tiposanguineo']),
        telefone: mi.campos['telefone'] ?? '',
        celular: mi.campos['celular'] ?? '',
        email: mi.campos['email'] ?? '',
        criadoEm: agora,
        atualizadoEm: agora,
        valoresAtributosDinamicos: dinamicos,
      );
      banco.membros.add(novo);
      lista?.membroIds.add(novo.id);
      novos++;
    }

    return ResumoImportacao(
      novos: novos,
      vinculados: vinculados,
      jaExistiam: jaExistiam,
      ignorados: r.linhasIgnoradas,
      congregacoesNovas: novasCongs,
    );
  }

  static String _nascimento(Map<String, String> campos) {
    for (final k in _chavesNascimento) {
      final d = parseNascimento(campos[k] ?? '');
      if (d != null) return isoData(d);
    }
    return '';
  }

  static String _sexo(String? v) {
    final n = normalizarTexto(v ?? '');
    if (n == 'm' || n.startsWith('masc')) return 'Masculino';
    if (n == 'f' || n.startsWith('fem')) return 'Feminino';
    return 'N/A';
  }

  static const _tiposSangue = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  static String _sangue(String? v) {
    final n = (v ?? '').trim().toUpperCase();
    return _tiposSangue.contains(n) ? n : 'N/A';
  }
}
