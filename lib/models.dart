import 'dart:ui' show Color;

import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// Utilitários
// ---------------------------------------------------------------------------

const Color kCorPadrao = Color(0xFF1B2A4A);

/// Cor de destaque padrão do app (o usuário pode trocar em Aparência).
const Color kCorAppPadrao = Color(0xFF8B6CEF);

/// Cor de quem não tem congregação.
const Color kCorSemCong = Color(0xFF78909C);

Color corDeHex(String hex, {Color padrao = kCorPadrao}) {
  try {
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return padrao;
    return Color(int.parse(h, radix: 16));
  } catch (_) {
    return padrao;
  }
}

String hexDeCor(Color c) =>
    '#${c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

/// Minúsculas, sem acentos e sem espaços duplicados (para buscas/comparações).
String normalizarTexto(String s) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const para = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final r in s.toLowerCase().trim().runes) {
    final c = String.fromCharCode(r);
    final i = de.indexOf(c);
    b.write(i >= 0 ? para[i] : c);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ');
}

/// Chave de comparação para cabeçalhos: "Tipo Sanguíneo" -> "tiposanguineo".
String normalizarChave(String s) =>
    normalizarTexto(s).replaceAll(RegExp(r'[^a-z0-9]'), '');

Map<String, dynamic> _mapa(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

int _int(Object? v) => v is num ? v.toInt() : (int.tryParse(_str(v)) ?? 0);

List<dynamic> _lista(Object? v) => v is List ? v : const [];

String _str(Object? v, [String padrao = '']) =>
    v == null ? padrao : v.toString();

const List<String> kMeses = [
  'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
  'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
];

DateTime? _dataValida(int a, int m, int d) {
  if (a < 1900 || a > 2200 || m < 1 || m > 12 || d < 1 || d > 31) return null;
  final dt = DateTime.utc(a, m, d);
  return dt.month == m ? dt : null;
}

/// Lê "aaaa-mm-dd" ou "dd/mm/aaaa". Devolve a data em UTC (sem hora) ou null.
DateTime? parseNascimento(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(t);
  if (iso != null) {
    return _dataValida(int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!));
  }
  final br = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(t);
  if (br != null) {
    return _dataValida(int.parse(br.group(3)!), int.parse(br.group(2)!), int.parse(br.group(1)!));
  }
  return null;
}

String isoData(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String dataBr(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year.toString().padLeft(4, '0')}';

bool _bissexto(int a) => (a % 4 == 0 && a % 100 != 0) || a % 400 == 0;

DateTime _aniversarioEm(int ano, int mes, int dia) {
  if (mes == 2 && dia == 29 && !_bissexto(ano)) dia = 28;
  return DateTime.utc(ano, mes, dia);
}

/// Id especial da opção "multicongregacional" (serve para todas).
const String kMultiId = '*multi*';

const List<String> kPaletaCongregacoes = [
  '#1E88E5', '#43A047', '#FB8C00', '#8E24AA', '#E53935',
  '#00ACC1', '#6D4C41', '#D81B60', '#7CB342', '#5E35B1',
];

// ---------------------------------------------------------------------------
// Congregação
// ---------------------------------------------------------------------------

class Congregacao {
  String id;
  String nome;
  String cor; // Hex

  Congregacao({required this.id, required this.nome, required this.cor});

  /// Instalação nova começa só com a Sede (a opção multicongregacional é à parte).
  static List<Congregacao> padroes() => [
        Congregacao(id: 'sede', nome: 'Sede', cor: '#1E88E5'),
      ];

  Map<String, dynamic> toJson() => {'id': id, 'nome': nome, 'cor': cor};

  factory Congregacao.fromJson(Map<String, dynamic> json) => Congregacao(
        id: _str(json['id']),
        nome: _str(json['nome']),
        cor: _str(json['cor'], '#1E88E5'),
      );
}

// ---------------------------------------------------------------------------
// Classe da EBD
// ---------------------------------------------------------------------------

/// Classe especial: não pode ser removida. Os membros dela podem ser escolhidos
/// como "pastor presidente" na assinatura das impressões.
const String kClassePastorId = 'pastor';

class Classe {
  String id;
  String nome;

  Classe({required this.id, required this.nome});

  static List<Classe> padroes() => [
        Classe(id: 'adultos', nome: 'Adultos'),
        Classe(id: 'adojovem', nome: 'Adojovem'),
        Classe(id: 'juniores', nome: 'Juniores'),
        Classe(id: 'catecumenos', nome: 'Catecúmenos'),
        Classe(id: kClassePastorId, nome: 'Pastor'),
      ];

  Map<String, dynamic> toJson() => {'id': id, 'nome': nome};

  factory Classe.fromJson(Map<String, dynamic> json) =>
      Classe(id: _str(json['id']), nome: _str(json['nome']));
}

// ---------------------------------------------------------------------------
// Coluna personalizada
// ---------------------------------------------------------------------------

class ColunaEspecificacao {
  String id;
  String nome;
  String tipo; // 'texto', 'numero', 'checkbox'

  ColunaEspecificacao({
    required this.id,
    required this.nome,
    this.tipo = 'texto',
  });

  /// Texto para exibir um valor desta coluna (tabela, PDF).
  String exibir(String? valor) {
    final v = valor ?? '';
    if (tipo == 'checkbox') return v == 'true' ? 'Sim' : 'Não';
    return v;
  }

  Map<String, dynamic> toMap() => toJson();

  factory ColunaEspecificacao.fromMap(Map<String, dynamic> json) =>
      ColunaEspecificacao.fromJson(json);

  Map<String, dynamic> toJson() => {'id': id, 'nome': nome, 'tipo': tipo};

  factory ColunaEspecificacao.fromJson(Map<String, dynamic> json) {
    return ColunaEspecificacao(
      id: _str(json['id']),
      nome: _str(json['nome']),
      tipo: _str(json['tipo'], 'texto'),
    );
  }
}

// ---------------------------------------------------------------------------
// Membro
// ---------------------------------------------------------------------------

class Entidade {
  String id;
  String nome;
  String? fotoBase64;
  String congregacaoId; // '' = sem congregação
  String cpf;
  String rg;
  String idade; // usada só quando não há data de nascimento
  String nascimento; // 'aaaa-mm-dd' ou ''
  String classe; // id da classe da EBD ('' = sem classe)
  bool requerAssinatura; // quando marcado, exige CPF/RG e aparece nas listas de assinatura
  String assinaturaNome; // nome como deve aparecer abaixo da assinatura ('' = o nome)
  String assinaturaCargo; // cargo / função ao assinar
  bool ativo; // false = desligado: continua no cadastro, mas some das listas e contagens
  String dataSaida; // 'aaaa-mm-dd'
  String motivoSaida;
  String sexo;
  String tipoSanguineo;
  String telefone;
  String celular;
  String email;
  Map<String, String> valoresAtributosDinamicos;
  int criadoEm; // ms desde 1970 (0 = desconhecido)
  int atualizadoEm;

  Entidade({
    required this.id,
    required this.nome,
    this.fotoBase64,
    this.congregacaoId = '',
    this.cpf = '',
    this.rg = '',
    this.idade = '',
    this.nascimento = '',
    this.classe = '',
    this.requerAssinatura = false,
    this.assinaturaNome = '',
    this.assinaturaCargo = '',
    this.ativo = true,
    this.dataSaida = '',
    this.motivoSaida = '',
    this.sexo = 'N/A',
    this.tipoSanguineo = 'N/A',
    this.telefone = '',
    this.celular = '',
    this.email = '',
    this.criadoEm = 0,
    this.atualizadoEm = 0,
    required this.valoresAtributosDinamicos,
  });

  /// Melhor contato para mostrar numa linha só.
  String get contato {
    if (celular.isNotEmpty) return celular;
    if (telefone.isNotEmpty) return telefone;
    return email;
  }

  String get documento => cpf.isNotEmpty ? cpf : rg;

  DateTime? get dataNascimento => parseNascimento(nascimento);

  /// Idade em anos na data [ref] (pelo nascimento; senão pelo campo idade).
  int? idadeEm(DateTime ref) {
    final n = dataNascimento;
    if (n != null) {
      var a = ref.year - n.year;
      if (ref.month < n.month || (ref.month == n.month && ref.day < n.day)) a--;
      return a < 0 ? null : a;
    }
    return int.tryParse(idade.trim());
  }

  int? get idadeAnos => idadeEm(DateTime.now());

  String get idadeExibida => idadeAnos?.toString() ?? idade;

  /// Próximo aniversário a partir de [hoje] (UTC, sem hora). Null sem nascimento.
  DateTime? proximoAniversario(DateTime hoje) {
    final n = dataNascimento;
    if (n == null) return null;
    final h = DateTime.utc(hoje.year, hoje.month, hoje.day);
    var d = _aniversarioEm(h.year, n.month, n.day);
    if (d.isBefore(h)) d = _aniversarioEm(h.year + 1, n.month, n.day);
    return d;
  }

  int? diasParaAniversario(DateTime hoje) {
    final p = proximoAniversario(hoje);
    if (p == null) return null;
    return p.difference(DateTime.utc(hoje.year, hoje.month, hoje.day)).inDays;
  }

  /// Idade que a pessoa completa no próximo aniversário.
  int? idadeNoProximoAniversario(DateTime hoje) {
    final p = proximoAniversario(hoje);
    final n = dataNascimento;
    if (p == null || n == null) return null;
    return p.year - n.year;
  }

  Entidade copiar() {
    return Entidade(
      id: id,
      nome: nome,
      fotoBase64: fotoBase64,
      congregacaoId: congregacaoId,
      cpf: cpf,
      rg: rg,
      idade: idade,
      nascimento: nascimento,
      classe: classe,
      requerAssinatura: requerAssinatura,
      assinaturaNome: assinaturaNome,
      assinaturaCargo: assinaturaCargo,
      ativo: ativo,
      dataSaida: dataSaida,
      motivoSaida: motivoSaida,
      sexo: sexo,
      tipoSanguineo: tipoSanguineo,
      telefone: telefone,
      celular: celular,
      email: email,
      criadoEm: criadoEm,
      atualizadoEm: atualizadoEm,
      valoresAtributosDinamicos:
          Map<String, String>.from(valoresAtributosDinamicos),
    );
  }

  Map<String, dynamic> toMap() => toJson();

  factory Entidade.fromMap(Map<String, dynamic> json) =>
      Entidade.fromJson(json);

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'fotoBase64': fotoBase64,
        'congregacaoId': congregacaoId,
        'cpf': cpf,
        'rg': rg,
        'idade': idade,
        'nascimento': nascimento,
        'classe': classe,
        'requerAssinatura': requerAssinatura,
        'assinaturaNome': assinaturaNome,
        'assinaturaCargo': assinaturaCargo,
        'ativo': ativo,
        'dataSaida': dataSaida,
        'motivoSaida': motivoSaida,
        'sexo': sexo,
        'tipoSanguineo': tipoSanguineo,
        'telefone': telefone,
        'celular': celular,
        'email': email,
        'criadoEm': criadoEm,
        'atualizadoEm': atualizadoEm,
        'valoresAtributosDinamicos': valoresAtributosDinamicos,
      };

  factory Entidade.fromJson(Map<String, dynamic> json) {
    final bruto = _mapa(json['valoresAtributosDinamicos'] ?? json['valores']);
    return Entidade(
      id: _str(json['id']),
      nome: _str(json['nome']),
      fotoBase64: json['fotoBase64'] as String?,
      congregacaoId: _str(json['congregacaoId']),
      cpf: _str(json['cpf']),
      rg: _str(json['rg']),
      idade: _str(json['idade']),
      nascimento: _str(json['nascimento']),
      classe: _str(json['classe']),
      requerAssinatura: json['requerAssinatura'] as bool? ?? false,
      assinaturaNome: _str(json['assinaturaNome']),
      assinaturaCargo: _str(json['assinaturaCargo']),
      ativo: json['ativo'] as bool? ?? true,
      dataSaida: _str(json['dataSaida']),
      motivoSaida: _str(json['motivoSaida']),
      sexo: _str(json['sexo'], 'N/A'),
      tipoSanguineo: _str(json['tipoSanguineo'], 'N/A'),
      telefone: _str(json['telefone']),
      celular: _str(json['celular']),
      email: _str(json['email']),
      criadoEm: _int(json['criadoEm']),
      atualizadoEm: _int(json['atualizadoEm']),
      valoresAtributosDinamicos:
          bruto.map((k, v) => MapEntry(k, _str(v))),
    );
  }
}

// ---------------------------------------------------------------------------
// Lista (lista): guarda apenas REFERÊNCIAS aos membros do cadastro geral
// ---------------------------------------------------------------------------

class ListaEntidades {
  String id;
  String titulo;
  bool mostrarData;
  String formatoData; // 'dd/mm/aaaa' ou 'mm/aaaa'
  bool mostrarHora;
  String formatoHora; // '12h' ou '24h'
  String corTema; // Código Hex
  bool isLocked;
  List<String> membroIds;
  String ordem; // 'az', 'za', 'editados', 'cadastro', 'aniversario'

  /// Data e hora do evento da lista (passado ou futuro). Vazio/-1 = usar a atual.
  String dataEvento; // 'aaaa-mm-dd' ou ''
  int horaEvento; // minutos desde 00:00, ou -1

  /// 'padrao' (membros escolhidos), 'aniversariantes' (automática, por mês)
  /// ou 'classes' (automática, organizada por classe da EBD).
  String tipo;
  List<int> meses; // só para 'aniversariantes' (vazio = o ano todo)

  ListaEntidades({
    required this.id,
    required this.titulo,
    this.mostrarData = true,
    this.formatoData = 'dd/mm/aaaa',
    this.mostrarHora = true,
    this.formatoHora = '24h',
    this.corTema = '#2196F3',
    this.isLocked = false,
    List<String>? membroIds,
    this.ordem = 'az',
    this.tipo = 'padrao',
    List<int>? meses,
    this.dataEvento = '',
    this.horaEvento = -1,
  })  : membroIds = membroIds ?? [],
        meses = meses ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'titulo': titulo,
        'mostrarData': mostrarData,
        'formatoData': formatoData,
        'mostrarHora': mostrarHora,
        'formatoHora': formatoHora,
        'corTema': corTema,
        'isLocked': isLocked,
        'membroIds': membroIds,
        'ordem': ordem,
        'tipo': tipo,
        'meses': meses,
        'dataEvento': dataEvento,
        'horaEvento': horaEvento,
      };

  factory ListaEntidades.fromJson(Map<String, dynamic> json) {
    return ListaEntidades(
      id: _str(json['id']),
      titulo: _str(json['titulo']),
      mostrarData: json['mostrarData'] as bool? ?? true,
      formatoData: _str(json['formatoData'], 'dd/mm/aaaa'),
      mostrarHora: json['mostrarHora'] as bool? ?? true,
      formatoHora: _str(json['formatoHora'], '24h'),
      corTema: _str(json['corTema'], '#2196F3'),
      isLocked: json['isLocked'] as bool? ?? false,
      membroIds: _lista(json['membroIds']).map((e) => e.toString()).toList(),
      ordem: _str(json['ordem'], 'az'),
      tipo: _str(json['tipo'], 'padrao'),
      dataEvento: _str(json['dataEvento']),
      horaEvento: json['horaEvento'] == null ? -1 : _int(json['horaEvento']),
      meses: _lista(json['meses']).map((e) => _int(e)).where((m) => m >= 1 && m <= 12).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Mural: compromissos (lembretes e eventos), avisos e datas da igreja
// ---------------------------------------------------------------------------

class Compromisso {
  String id;
  String tipo; // 'lembrete' | 'evento'
  String titulo;
  String descricao;
  String local;
  String data; // 'aaaa-mm-dd'
  int hora; // minutos desde 00:00, ou -1 (sem hora)
  bool feito;
  String repete; // nao | diario | semanal | mensal | anual
  String categoria; // eventos: outro | ensaio | reuniao | versiculo

  Compromisso({
    required this.id,
    this.tipo = 'lembrete',
    required this.titulo,
    this.descricao = '',
    this.local = '',
    this.data = '',
    this.hora = -1,
    this.feito = false,
    this.repete = 'nao',
    this.categoria = 'outro',
  });

  DateTime? get dataBase => parseNascimento(data);

  String get horaTexto => hora < 0
      ? ''
      : '${(hora ~/ 60).toString().padLeft(2, '0')}:${(hora % 60).toString().padLeft(2, '0')}';

  /// O compromisso cai no [dia]? (considera a repetição)
  bool ocorreEm(DateTime dia) {
    final b = dataBase;
    if (b == null) return false;
    final d = DateTime.utc(dia.year, dia.month, dia.day);
    if (d.isBefore(b)) return false;
    switch (repete) {
      case 'diario':
        return true;
      case 'semanal':
        return d.difference(b).inDays % 7 == 0;
      case 'mensal':
        return d.day == b.day;
      case 'anual':
        return d.month == b.month && d.day == b.day;
      default:
        return d == b;
    }
  }

  /// Próxima ocorrência a partir de [hoje] (inclusive). Null se já passou.
  DateTime? proxima(DateTime hoje) {
    final b = dataBase;
    if (b == null) return null;
    final h = DateTime.utc(hoje.year, hoje.month, hoje.day);
    if (repete == 'nao') return b.isBefore(h) ? null : b;
    for (var i = 0; i <= 400; i++) {
      final d = h.add(Duration(days: i));
      if (ocorreEm(d)) return d;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tipo': tipo,
        'titulo': titulo,
        'descricao': descricao,
        'local': local,
        'data': data,
        'hora': hora,
        'feito': feito,
        'repete': repete,
        'categoria': categoria,
      };

  factory Compromisso.fromJson(Map<String, dynamic> json) => Compromisso(
        id: _str(json['id']),
        tipo: _str(json['tipo'], 'lembrete'),
        titulo: _str(json['titulo']),
        descricao: _str(json['descricao']),
        local: _str(json['local']),
        data: _str(json['data']),
        hora: json['hora'] == null ? -1 : _int(json['hora']),
        feito: json['feito'] as bool? ?? false,
        repete: _str(json['repete'], 'nao'),
        categoria: _str(json['categoria'], 'outro'),
      );
}

class Aviso {
  String id;
  String titulo;
  String texto;
  int criadoEm; // ms desde 1970
  bool fixado;
  String expiraEm; // 'aaaa-mm-dd' ou '' (não expira)

  Aviso({
    required this.id,
    required this.titulo,
    this.texto = '',
    this.criadoEm = 0,
    this.fixado = false,
    this.expiraEm = '',
  });

  bool expirado(DateTime hoje) {
    final e = parseNascimento(expiraEm);
    if (e == null) return false;
    return e.isBefore(DateTime.utc(hoje.year, hoje.month, hoje.day));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'titulo': titulo,
        'texto': texto,
        'criadoEm': criadoEm,
        'fixado': fixado,
        'expiraEm': expiraEm,
      };

  factory Aviso.fromJson(Map<String, dynamic> json) => Aviso(
        id: _str(json['id']),
        titulo: _str(json['titulo']),
        texto: _str(json['texto']),
        criadoEm: _int(json['criadoEm']),
        fixado: json['fixado'] as bool? ?? false,
        expiraEm: _str(json['expiraEm']),
      );
}

/// Data comemorativa cadastrada pela igreja. ano = 0 repete todo ano.
class DataIgreja {
  String id;
  String titulo;
  int dia;
  int mes;
  int ano;

  DataIgreja({
    required this.id,
    required this.titulo,
    required this.dia,
    required this.mes,
    this.ano = 0,
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'titulo': titulo, 'dia': dia, 'mes': mes, 'ano': ano};

  factory DataIgreja.fromJson(Map<String, dynamic> json) => DataIgreja(
        id: _str(json['id']),
        titulo: _str(json['titulo']),
        dia: _int(json['dia']),
        mes: _int(json['mes']),
        ano: _int(json['ano']),
      );
}

// ---------------------------------------------------------------------------
// Cultos da semana (fixos, repetem toda semana) e publicações no Mural
// ---------------------------------------------------------------------------

const Map<String, String> kCategoriasEvento = {
  'outro': 'Evento',
  'ensaio': 'Ensaio',
  'reuniao': 'Reunião',
  'versiculo': 'Versículo do dia',
};

/// Culto fixo da semana. [diaSemana] segue DateTime.weekday (1 = segunda ... 7 = domingo).
class Culto {
  String id;
  int diaSemana;
  String titulo;
  int hora; // minutos desde 00:00, ou -1
  String cronograma; // um item por linha (ex.: "19:00 Abertura")

  Culto({
    required this.id,
    required this.diaSemana,
    required this.titulo,
    this.hora = -1,
    this.cronograma = '',
  });

  String get horaTexto => hora < 0
      ? ''
      : '${(hora ~/ 60).toString().padLeft(2, '0')}:${(hora % 60).toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'diaSemana': diaSemana,
        'titulo': titulo,
        'hora': hora,
        'cronograma': cronograma,
      };

  factory Culto.fromJson(Map<String, dynamic> json) => Culto(
        id: _str(json['id']),
        diaSemana: _int(json['diaSemana']).clamp(1, 7),
        titulo: _str(json['titulo']),
        hora: json['hora'] == null ? -1 : _int(json['hora']),
        cronograma: _str(json['cronograma']),
      );
}

/// Lista ou ata (ou texto) publicada no Mural até [expiraEm].
class Publicacao {
  String id;
  String tipo; // 'lista' | 'ata' | 'texto'
  String titulo;
  String texto;
  int publicadoEm; // ms
  String expiraEm; // 'aaaa-mm-dd'

  Publicacao({
    required this.id,
    this.tipo = 'texto',
    required this.titulo,
    this.texto = '',
    this.publicadoEm = 0,
    this.expiraEm = '',
  });

  bool expirada(DateTime hoje) {
    final e = parseNascimento(expiraEm);
    if (e == null) return false;
    return e.isBefore(DateTime.utc(hoje.year, hoje.month, hoje.day));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tipo': tipo,
        'titulo': titulo,
        'texto': texto,
        'publicadoEm': publicadoEm,
        'expiraEm': expiraEm,
      };

  factory Publicacao.fromJson(Map<String, dynamic> json) => Publicacao(
        id: _str(json['id']),
        tipo: _str(json['tipo'], 'texto'),
        titulo: _str(json['titulo']),
        texto: _str(json['texto']),
        publicadoEm: _int(json['publicadoEm']),
        expiraEm: _str(json['expiraEm']),
      );
}

/// Informações do "Fale conosco" (só a conta dona edita).
class Contato {
  String telefone;
  String email;
  String endereco;

  Contato({this.telefone = '', this.email = '', this.endereco = ''});

  bool get vazio => telefone.trim().isEmpty && email.trim().isEmpty && endereco.trim().isEmpty;

  Map<String, dynamic> toJson() => {'telefone': telefone, 'email': email, 'endereco': endereco};

  factory Contato.fromJson(Map<String, dynamic> json) => Contato(
        telefone: _str(json['telefone']),
        email: _str(json['email']),
        endereco: _str(json['endereco']),
      );
}

// ---------------------------------------------------------------------------
// Atas (relatórios de reunião) e movimento de membros
// ---------------------------------------------------------------------------

const Map<String, String> kCategoriasRegistro = {
  'acontecimento': 'Acontecimento',
  'evento': 'Evento',
  'posicionamento': 'Posicionamento',
  'feito': 'Feito / realizado',
  'outro': 'Outro',
};

/// Entrada ou saída de um membro (alimenta as atas automaticamente).
class Movimento {
  String id;
  String membroId;
  String nome; // cópia do nome na hora do movimento
  String tipo; // 'entrada' | 'saida'
  String data; // 'aaaa-mm-dd'
  String motivo;

  Movimento({
    required this.id,
    required this.membroId,
    required this.nome,
    required this.tipo,
    required this.data,
    this.motivo = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'membroId': membroId,
        'nome': nome,
        'tipo': tipo,
        'data': data,
        'motivo': motivo,
      };

  factory Movimento.fromJson(Map<String, dynamic> json) => Movimento(
        id: _str(json['id']),
        membroId: _str(json['membroId']),
        nome: _str(json['nome']),
        tipo: _str(json['tipo'], 'entrada'),
        data: _str(json['data']),
        motivo: _str(json['motivo']),
      );
}

/// Um registro dentro da ata (acontecimento, evento, posicionamento, feito...).
class RegistroAta {
  String id;
  String data; // 'aaaa-mm-dd'
  String categoria; // chave de kCategoriasRegistro
  String texto;

  RegistroAta({
    required this.id,
    this.data = '',
    this.categoria = 'acontecimento',
    this.texto = '',
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'data': data, 'categoria': categoria, 'texto': texto};

  factory RegistroAta.fromJson(Map<String, dynamic> json) => RegistroAta(
        id: _str(json['id']),
        data: _str(json['data']),
        categoria: _str(json['categoria'], 'acontecimento'),
        texto: _str(json['texto']),
      );
}

/// Ata de reunião. 'ordinaria' = relatório do mês (acumula registros e o
/// movimento de membros do mês); 'extraordinaria' = folha avulsa, não acumulativa.
class Ata {
  String id;
  String tipo; // 'ordinaria' | 'extraordinaria'
  String titulo;
  String mes; // 'aaaa-mm' (ordinária)
  String data; // data da reunião 'aaaa-mm-dd' ('' = não informada)
  int hora; // minutos desde 00:00, ou -1
  String texto; // anotações livres (bloco de notas, com marcação simples)
  List<RegistroAta> registros;
  bool incluirMovimentos; // entradas e saídas de membros no documento
  String periodoIni; // extraordinária: período do movimento de membros
  String periodoFim;
  bool assinaturasMembros; // incluir assinaturas de quem "requer assinatura"
  int criadoEm;
  int atualizadoEm;

  Ata({
    required this.id,
    this.tipo = 'ordinaria',
    required this.titulo,
    this.mes = '',
    this.data = '',
    this.hora = -1,
    this.texto = '',
    List<RegistroAta>? registros,
    this.incluirMovimentos = true,
    this.periodoIni = '',
    this.periodoFim = '',
    this.assinaturasMembros = false,
    this.criadoEm = 0,
    this.atualizadoEm = 0,
  }) : registros = registros ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'tipo': tipo,
        'titulo': titulo,
        'mes': mes,
        'data': data,
        'hora': hora,
        'texto': texto,
        'registros': registros.map((r) => r.toJson()).toList(),
        'incluirMovimentos': incluirMovimentos,
        'periodoIni': periodoIni,
        'periodoFim': periodoFim,
        'assinaturasMembros': assinaturasMembros,
        'criadoEm': criadoEm,
        'atualizadoEm': atualizadoEm,
      };

  factory Ata.fromJson(Map<String, dynamic> json) => Ata(
        id: _str(json['id']),
        tipo: _str(json['tipo'], 'ordinaria'),
        titulo: _str(json['titulo']),
        mes: _str(json['mes']),
        data: _str(json['data']),
        hora: json['hora'] == null ? -1 : _int(json['hora']),
        texto: _str(json['texto']),
        registros: _lista(json['registros']).map((r) => RegistroAta.fromJson(_mapa(r))).toList(),
        incluirMovimentos: json['incluirMovimentos'] as bool? ?? true,
        periodoIni: _str(json['periodoIni']),
        periodoFim: _str(json['periodoFim']),
        assinaturasMembros: json['assinaturasMembros'] as bool? ?? false,
        criadoEm: _int(json['criadoEm']),
        atualizadoEm: _int(json['atualizadoEm']),
      );
}

// ---------------------------------------------------------------------------
// Banco: cadastro geral de membros + congregações + campos extras + listas
// ---------------------------------------------------------------------------

class Banco {
  List<Entidade> membros;
  List<Congregacao> congregacoes;
  List<ColunaEspecificacao> colunas; // campos extras (valem para todos)
  List<Classe> classes; // classes da EBD
  List<ListaEntidades> listas; // listas
  List<Compromisso> compromissos; // Mural: lembretes e eventos
  List<Aviso> avisos; // Mural: avisos
  List<DataIgreja> datasIgreja; // Mural: datas comemorativas da igreja
  List<Ata> atas; // relatórios de reunião
  List<Movimento> movimentos; // entradas e saídas de membros
  List<Culto> cultos; // cultos fixos da semana
  List<Publicacao> publicacoes; // listas/atas publicadas no Mural
  Contato contato; // "Fale conosco"

  // Opção multicongregacional (serve para todas as congregações)
  bool multiAtiva;
  String multiNome;
  String multiCor;
  bool multiEmTodas; // também aparece ao filtrar por uma congregação

  String ordemMembros; // ordem na área Membros

  Banco({
    List<Entidade>? membros,
    List<Congregacao>? congregacoes,
    List<ColunaEspecificacao>? colunas,
    List<Classe>? classes,
    List<ListaEntidades>? listas,
    List<Compromisso>? compromissos,
    List<Aviso>? avisos,
    List<DataIgreja>? datasIgreja,
    List<Ata>? atas,
    List<Movimento>? movimentos,
    List<Culto>? cultos,
    List<Publicacao>? publicacoes,
    Contato? contato,
    this.multiAtiva = true,
    this.multiNome = 'Multicongregacional',
    this.multiCor = '#8E24AA',
    this.multiEmTodas = true,
    this.ordemMembros = 'az',
  })  : membros = membros ?? [],
        congregacoes = congregacoes ?? Congregacao.padroes(),
        colunas = colunas ?? [],
        classes = classes ?? Classe.padroes(),
        listas = listas ?? [],
        compromissos = compromissos ?? [],
        avisos = avisos ?? [],
        datasIgreja = datasIgreja ?? [],
        atas = atas ?? [],
        movimentos = movimentos ?? [],
        cultos = cultos ?? [],
        publicacoes = publicacoes ?? [],
        contato = contato ?? Contato();

  /// Banco vazio de primeira execução (com dois campos extras de exemplo).
  factory Banco.novo() {
    const uuid = Uuid();
    return Banco(colunas: [
      ColunaEspecificacao(id: uuid.v4(), nome: 'Cargo / Função'),
      ColunaEspecificacao(id: uuid.v4(), nome: 'Observação'),
    ]);
  }

  Congregacao get multi =>
      Congregacao(id: kMultiId, nome: multiNome, cor: multiCor);

  /// Congregações normais + multicongregacional (se ativa).
  List<Congregacao> get todasCongregacoes =>
      [...congregacoes, if (multiAtiva) multi];

  Congregacao? congregacaoPorId(String id) {
    if (id.isEmpty) return null;
    if (id == kMultiId) return multiAtiva ? multi : null;
    for (final c in congregacoes) {
      if (c.id == id) return c;
    }
    return null;
  }

  Congregacao? congregacaoPorNome(String nome) {
    final alvo = normalizarTexto(nome);
    if (alvo.isEmpty) return null;
    for (final c in todasCongregacoes) {
      if (normalizarTexto(c.nome) == alvo) return c;
    }
    return null;
  }

  Classe? classePorId(String id) {
    if (id.isEmpty) return null;
    for (final c in classes) {
      if (c.id == id) return c;
    }
    return null;
  }

  Classe? classePorNome(String nome) {
    final alvo = normalizarTexto(nome);
    if (alvo.isEmpty) return null;
    for (final c in classes) {
      if (normalizarTexto(c.nome) == alvo) return c;
    }
    return null;
  }

  /// Id válido da classe do membro ('' se não tem ou se foi removida).
  String classeEfetiva(Entidade m) => classePorId(m.classe) == null ? '' : m.classe;

  /// Id válido da congregação do membro ('' se não tem ou se foi removida).
  String congregacaoEfetiva(Entidade m) =>
      congregacaoPorId(m.congregacaoId) == null ? '' : m.congregacaoId;

  int contar(Iterable<Entidade> origem, String congregacaoId) =>
      origem.where((m) => congregacaoEfetiva(m) == congregacaoId).length;

  Color corDaCongregacao(Entidade m, Color padrao) {
    final c = congregacaoPorId(m.congregacaoId);
    return c == null ? padrao : corDeHex(c.cor, padrao: padrao);
  }

  /// Membros de uma lista, na ordem em que foram adicionados.
  List<Entidade> membrosDaLista(ListaEntidades l) {
    // Listas automáticas: a lista é calculada a partir do cadastro.
    if (l.tipo == 'aniversariantes') {
      return membros.where((m) {
        final n = m.dataNascimento;
        if (!m.ativo || n == null) return false;
        return l.meses.isEmpty || l.meses.contains(n.month);
      }).toList();
    }
    if (l.tipo == 'classes') return membros.where((m) => m.ativo).toList();

    final porId = {for (final m in membros) m.id: m};
    return [
      for (final id in l.membroIds)
        if (porId[id] != null && porId[id]!.ativo) porId[id]!
    ];
  }

  /// Troca TODO o conteúdo por [o] (restauração de backup completo).
  void substituirPor(Banco o) {
    membros = o.membros;
    congregacoes = o.congregacoes;
    colunas = o.colunas;
    classes = o.classes;
    listas = o.listas;
    compromissos = o.compromissos;
    avisos = o.avisos;
    datasIgreja = o.datasIgreja;
    atas = o.atas;
    movimentos = o.movimentos;
    cultos = o.cultos;
    publicacoes = o.publicacoes;
    contato = o.contato;
    multiAtiva = o.multiAtiva;
    multiNome = o.multiNome;
    multiCor = o.multiCor;
    multiEmTodas = o.multiEmTodas;
    ordemMembros = o.ordemMembros;
  }

  /// Remove publicações vencidas (rodado por quem edita).
  bool limparPublicacoesExpiradas() {
    final hoje = DateTime.now();
    final antes = publicacoes.length;
    publicacoes.removeWhere((p) => p.expirada(hoje));
    return publicacoes.length != antes;
  }

  /// Membros em atividade (não desligados).
  List<Entidade> get ativos => membros.where((m) => m.ativo).toList();

  String _hoje() => isoData(DateTime.now());

  void _registrar(Entidade m, String tipo, String data, String motivo) {
    movimentos.add(Movimento(
      id: const Uuid().v4(),
      membroId: m.id,
      nome: m.nome,
      tipo: tipo,
      data: data,
      motivo: motivo,
    ));
  }

  /// Insere um membro novo (registrando a ENTRADA) ou substitui o que tem o mesmo id.
  void salvarMembro(Entidade novo) {
    final i = membros.indexWhere((m) => m.id == novo.id);
    if (i >= 0) {
      membros[i] = novo;
    } else {
      membros.add(novo);
      _registrar(novo, 'entrada', _hoje(), '');
    }
  }

  /// Desliga o membro (ele continua no cadastro) e registra a SAÍDA.
  void desligar(Entidade m, DateTime data, String motivo) {
    m.ativo = false;
    m.dataSaida = isoData(data);
    m.motivoSaida = motivo;
    m.atualizadoEm = DateTime.now().millisecondsSinceEpoch;
    _registrar(m, 'saida', isoData(data), motivo);
  }

  /// Reativa um membro desligado e registra uma ENTRADA (reintegração).
  void reativar(Entidade m, DateTime data) {
    m.ativo = true;
    m.dataSaida = '';
    m.motivoSaida = '';
    m.atualizadoEm = DateTime.now().millisecondsSinceEpoch;
    _registrar(m, 'entrada', isoData(data), 'Reintegração');
  }

  /// Movimentos de membros que caem no período da ata.
  List<Movimento> movimentosDaAta(Ata a) {
    DateTime? ini;
    DateTime? fim;
    if (a.tipo == 'ordinaria') {
      final p = a.mes.split('-');
      if (p.length == 2) {
        final y = int.tryParse(p[0]);
        final m = int.tryParse(p[1]);
        if (y != null && m != null) {
          ini = DateTime.utc(y, m, 1);
          fim = DateTime.utc(y, m + 1, 0);
        }
      }
    } else {
      ini = parseNascimento(a.periodoIni);
      fim = parseNascimento(a.periodoFim) ?? ini;
    }
    if (ini == null || fim == null) return [];
    final r = movimentos.where((mv) {
      final d = parseNascimento(mv.data);
      return d != null && !d.isBefore(ini!) && !d.isAfter(fim!);
    }).toList();
    r.sort((x, y) => x.data.compareTo(y.data));
    return r;
  }

  /// Apaga o membro do cadastro e de todas as listas.
  void excluirMembro(Entidade m) {
    membros.removeWhere((e) => e.id == m.id);
    for (final l in listas) {
      l.membroIds.remove(m.id);
    }
  }

  /// Em quantas listas "de escolha" o membro foi adicionado.
  int listasDoMembro(Entidade m) =>
      listas.where((l) => l.tipo == 'padrao' && l.membroIds.contains(m.id)).length;

  Map<String, dynamic> toJson() => {
        'membros': membros.map((m) => m.toJson()).toList(),
        'congregacoes': congregacoes.map((c) => c.toJson()).toList(),
        'colunas': colunas.map((c) => c.toJson()).toList(),
        'classes': classes.map((c) => c.toJson()).toList(),
        'listas': listas.map((l) => l.toJson()).toList(),
        'compromissos': compromissos.map((c) => c.toJson()).toList(),
        'avisos': avisos.map((a) => a.toJson()).toList(),
        'datasIgreja': datasIgreja.map((d) => d.toJson()).toList(),
        'atas': atas.map((a) => a.toJson()).toList(),
        'movimentos': movimentos.map((m) => m.toJson()).toList(),
        'cultos': cultos.map((c) => c.toJson()).toList(),
        'publicacoes': publicacoes.map((p) => p.toJson()).toList(),
        'contato': contato.toJson(),
        'multiAtiva': multiAtiva,
        'multiNome': multiNome,
        'multiCor': multiCor,
        'multiEmTodas': multiEmTodas,
        'ordemMembros': ordemMembros,
      };

  factory Banco.fromJson(Map<String, dynamic> json) {
    final congs = _lista(json['congregacoes'])
        .map((c) => Congregacao.fromJson(_mapa(c)))
        .toList();
    return Banco(
      membros: _lista(json['membros']).map((m) => Entidade.fromJson(_mapa(m))).toList(),
      congregacoes: json.containsKey('congregacoes') ? congs : null,
      colunas: _lista(json['colunas'])
          .map((c) => ColunaEspecificacao.fromJson(_mapa(c)))
          .toList(),
      classes: json.containsKey('classes') ? _classesComPastor(json['classes']) : null,
      listas: _lista(json['listas'])
          .map((l) => ListaEntidades.fromJson(_mapa(l)))
          .toList(),
      compromissos: _lista(json['compromissos'])
          .map((c) => Compromisso.fromJson(_mapa(c)))
          .toList(),
      avisos: _lista(json['avisos']).map((a) => Aviso.fromJson(_mapa(a))).toList(),
      datasIgreja:
          _lista(json['datasIgreja']).map((d) => DataIgreja.fromJson(_mapa(d))).toList(),
      atas: _lista(json['atas']).map((a) => Ata.fromJson(_mapa(a))).toList(),
      movimentos:
          _lista(json['movimentos']).map((m) => Movimento.fromJson(_mapa(m))).toList(),
      cultos: _lista(json['cultos']).map((c) => Culto.fromJson(_mapa(c))).toList(),
      publicacoes:
          _lista(json['publicacoes']).map((p) => Publicacao.fromJson(_mapa(p))).toList(),
      contato: json['contato'] is Map ? Contato.fromJson(_mapa(json['contato'])) : null,
      multiAtiva: json['multiAtiva'] as bool? ?? true,
      multiNome: _str(json['multiNome'], 'Multicongregacional'),
      multiCor: _str(json['multiCor'], '#8E24AA'),
      multiEmTodas: json['multiEmTodas'] as bool? ?? true,
      ordemMembros: _str(json['ordemMembros'], 'az'),
    );
  }

  static List<Classe> _classesComPastor(Object? bruto) {
    final l = _lista(bruto).map((c) => Classe.fromJson(_mapa(c))).toList();
    if (!l.any((c) => c.id == kClassePastorId)) {
      l.add(Classe(id: kClassePastorId, nome: 'Pastor'));
    }
    return l;
  }

  /// Membros da classe especial "Pastor".
  List<Entidade> get pastores =>
      membros.where((m) => m.classe == kClassePastorId).toList();

  /// Mescla uma lista vinda de fora (backup ou formato antigo, em que cada lista
  /// carregava seus próprios membros) neste banco. Membros com o mesmo id são
  /// reaproveitados; congregações e campos são casados por id e depois por nome.
  /// Devolve a lista criada.
  ListaEntidades mesclarExterno({
    required Map<String, dynamic> listaJson,
    required List<dynamic> membrosJson,
    List<dynamic>? congregacoesJson,
    List<dynamic>? colunasJson,
    List<dynamic>? classesJson,
    bool manterIdLista = false,
    bool atualizarExistentes = false,
  }) {
    // Congregações
    final congMap = <String, String>{};
    for (final raw in congregacoesJson ?? const []) {
      final c = Congregacao.fromJson(_mapa(raw));
      Congregacao? ex;
      for (final e in congregacoes) {
        if (e.id == c.id) ex = e;
      }
      ex ??= congregacaoPorNome(c.nome);
      if (ex == null) {
        congregacoes.add(c);
        congMap[c.id] = c.id;
      } else {
        if (atualizarExistentes && ex.id != kMultiId) {
          ex.nome = c.nome;
          ex.cor = c.cor;
        }
        congMap[c.id] = ex.id;
      }
    }

    // Campos extras
    final colMap = <String, String>{};
    for (final raw in colunasJson ?? const []) {
      final c = ColunaEspecificacao.fromJson(_mapa(raw));
      ColunaEspecificacao? ex;
      for (final e in colunas) {
        if (e.id == c.id) ex = e;
      }
      if (ex == null) {
        for (final e in colunas) {
          if (normalizarChave(e.nome) == normalizarChave(c.nome)) ex = e;
        }
      }
      if (ex == null) {
        colunas.add(c);
        colMap[c.id] = c.id;
      } else {
        colMap[c.id] = ex.id;
      }
    }

    // Classes da EBD
    final classMap = <String, String>{};
    for (final raw in classesJson ?? const []) {
      final c = Classe.fromJson(_mapa(raw));
      Classe? ex;
      for (final e in classes) {
        if (e.id == c.id) ex = e;
      }
      ex ??= classePorNome(c.nome);
      if (ex == null) {
        classes.add(c);
        classMap[c.id] = c.id;
      } else {
        classMap[c.id] = ex.id;
      }
    }

    // Membros
    final ids = <String>[];
    final existentes = {for (final m in membros) m.id};
    for (final raw in membrosJson) {
      final m = Entidade.fromJson(_mapa(raw));
      if (m.id.isEmpty) continue;
      if (!existentes.contains(m.id)) {
        if (m.congregacaoId.isNotEmpty && m.congregacaoId != kMultiId) {
          m.congregacaoId = congMap[m.congregacaoId] ??
              (congregacaoPorId(m.congregacaoId)?.id ?? '');
        }
        if (m.classe.isNotEmpty) {
          m.classe = classMap[m.classe] ?? (classePorId(m.classe)?.id ?? '');
        }
        m.valoresAtributosDinamicos = {
          for (final e in m.valoresAtributosDinamicos.entries)
            if (colMap.containsKey(e.key)) colMap[e.key]!: e.value
        };
        membros.add(m);
        existentes.add(m.id);
      }
      if (!ids.contains(m.id)) ids.add(m.id);
    }

    final lista = ListaEntidades.fromJson(listaJson);
    if (!manterIdLista || lista.id.isEmpty) lista.id = const Uuid().v4();
    lista.membroIds = ids;
    listas.add(lista);
    return lista;
  }
}

// ---------------------------------------------------------------------------
// Opções de impressão (globais do app; lembradas entre impressões)
// ---------------------------------------------------------------------------

class ConfigPdf {
  // Relatório
  String layout; // simples | foto | presenca | fichas | agrupado | aniversariantes | classes
  bool paisagem;
  List<String> campos; // colunas do relatório (ver PdfService.camposDisponiveis)

  // Cabeçalho
  String tituloModo; // todas | primeira | nenhum

  // Data e hora (cada uma pode ser a atual ou uma escolhida)
  bool incluirData;
  String dataModo; // hoje | escolhida
  String dataEscolhida; // 'aaaa-mm-dd'
  bool incluirHora;
  String horaModo; // agora | escolhida
  int horaEscolhida; // minutos desde 00:00
  bool dataHoraGrande; // em destaque, ao lado do título
  String dataHoraLado; // d = direita do título | e = esquerda

  // Assinatura do pastor presidente
  bool assinaturaPastor;
  String assinaturaPastorOnde; // todas | primeira | ultima
  String pastorNome;

  // Coluna "Assinatura" nas listas (preenchida só para quem requer assinatura)
  bool colunaAssinatura;

  // Margens (mm)
  bool usarMargens;
  double margemSuperior;
  double margemInferior;
  double margemEsquerda;
  double margemDireita;

  // Logo no canto (carimbo)
  bool usarCarimbo;
  String? carimboBase64;
  String carimboPosicao; // bd | be | td | te  (baixo/topo + direita/esquerda)
  double tamanhoCarimbo; // altura em mm

  // Capa
  bool usarCapa;
  String? capaLogoBase64;
  String capaSubtitulo;
  double tamanhoLogoCapa; // altura em mm

  ConfigPdf({
    this.layout = 'simples',
    this.paisagem = false,
    List<String>? campos,
    this.tituloModo = 'todas',
    this.incluirData = true,
    this.dataModo = 'hoje',
    this.dataEscolhida = '',
    this.incluirHora = true,
    this.horaModo = 'agora',
    this.horaEscolhida = 0,
    this.dataHoraGrande = false,
    this.dataHoraLado = 'd',
    this.assinaturaPastor = false,
    this.assinaturaPastorOnde = 'ultima',
    this.pastorNome = '',
    this.colunaAssinatura = false,
    this.usarMargens = true,
    this.margemSuperior = 15,
    this.margemInferior = 15,
    this.margemEsquerda = 15,
    this.margemDireita = 15,
    this.usarCarimbo = false,
    this.carimboBase64,
    this.carimboPosicao = 'bd',
    this.tamanhoCarimbo = 25,
    this.usarCapa = false,
    this.capaLogoBase64,
    this.capaSubtitulo = '',
    this.tamanhoLogoCapa = 60,
  }) : campos = campos ?? ['congregacao', 'celular'];

  /// Data usada no documento (a escolhida ou a de hoje).
  DateTime get dataReferencia {
    if (dataModo == 'escolhida') {
      final d = parseNascimento(dataEscolhida);
      if (d != null) return d;
    }
    return DateTime.now();
  }

  /// Hora usada no documento, em minutos desde 00:00.
  int get horaReferenciaMin {
    if (horaModo == 'escolhida') return horaEscolhida.clamp(0, 1439);
    final n = DateTime.now();
    return n.hour * 60 + n.minute;
  }

  ConfigPdf copiar() => ConfigPdf.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'layout': layout,
        'paisagem': paisagem,
        'campos': campos,
        'tituloModo': tituloModo,
        'incluirData': incluirData,
        'dataModo': dataModo,
        'dataEscolhida': dataEscolhida,
        'incluirHora': incluirHora,
        'horaModo': horaModo,
        'horaEscolhida': horaEscolhida,
        'dataHoraGrande': dataHoraGrande,
        'dataHoraLado': dataHoraLado,
        'assinaturaPastor': assinaturaPastor,
        'assinaturaPastorOnde': assinaturaPastorOnde,
        'pastorNome': pastorNome,
        'colunaAssinatura': colunaAssinatura,
        'usarMargens': usarMargens,
        'margemSuperior': margemSuperior,
        'margemInferior': margemInferior,
        'margemEsquerda': margemEsquerda,
        'margemDireita': margemDireita,
        'usarCarimbo': usarCarimbo,
        'carimboBase64': carimboBase64,
        'carimboPosicao': carimboPosicao,
        'tamanhoCarimbo': tamanhoCarimbo,
        'usarCapa': usarCapa,
        'capaLogoBase64': capaLogoBase64,
        'capaSubtitulo': capaSubtitulo,
        'tamanhoLogoCapa': tamanhoLogoCapa,
      };

  factory ConfigPdf.fromJson(Map<String, dynamic> json) {
    double n(Object? v, double p) =>
        v is num ? v.toDouble() : (double.tryParse(_str(v)) ?? p);
    final carimbo = json['carimboBase64'] as String?;
    final campos = json['campos'];
    // Versões anteriores tinham um único interruptor "incluirDataHora".
    final antigo = json['incluirDataHora'] as bool? ?? true;
    return ConfigPdf(
      layout: _str(json['layout'], 'simples'),
      paisagem: json['paisagem'] as bool? ?? false,
      campos: campos is List ? campos.map((e) => e.toString()).toList() : null,
      tituloModo: _str(json['tituloModo'], 'todas'),
      incluirData: json['incluirData'] as bool? ?? antigo,
      dataModo: _str(json['dataModo'], 'hoje'),
      dataEscolhida: _str(json['dataEscolhida']),
      incluirHora: json['incluirHora'] as bool? ?? antigo,
      horaModo: _str(json['horaModo'], 'agora'),
      horaEscolhida: _int(json['horaEscolhida']),
      dataHoraGrande: json['dataHoraGrande'] as bool? ?? false,
      dataHoraLado: _str(json['dataHoraLado'], 'd'),
      assinaturaPastor: json['assinaturaPastor'] as bool? ?? false,
      assinaturaPastorOnde: _str(json['assinaturaPastorOnde'], 'ultima'),
      pastorNome: _str(json['pastorNome']),
      colunaAssinatura: json['colunaAssinatura'] as bool? ?? false,
      usarMargens: json['usarMargens'] as bool? ?? true,
      margemSuperior: n(json['margemSuperior'], 15),
      margemInferior: n(json['margemInferior'], 15),
      margemEsquerda: n(json['margemEsquerda'], 15),
      margemDireita: n(json['margemDireita'], 15),
      carimboBase64: carimbo,
      // Compatível com a versão anterior (carimboNoTopo).
      usarCarimbo: json['usarCarimbo'] as bool? ?? (carimbo != null),
      carimboPosicao: json['carimboPosicao'] is String
          ? json['carimboPosicao'] as String
          : ((json['carimboNoTopo'] as bool? ?? false) ? 'td' : 'bd'),
      tamanhoCarimbo: n(json['tamanhoCarimbo'], 25),
      usarCapa: json['usarCapa'] as bool? ?? false,
      capaLogoBase64: json['capaLogoBase64'] as String?,
      capaSubtitulo: _str(json['capaSubtitulo']),
      tamanhoLogoCapa: n(json['tamanhoLogoCapa'], 60),
    );
  }
}
