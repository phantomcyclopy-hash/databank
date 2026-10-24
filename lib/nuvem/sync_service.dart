import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, SocketException;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models.dart';
import '../storage.dart';
import 'firebase_rest.dart';

class _Remoto {
  final String hash;
  final bool apagado;
  _Remoto(this.hash, this.apagado);
}

/// Login e sincronização com o Firebase (Auth + Firestore).
///
/// Modelo: cada item (membro, lista, ata, aviso...) é um documento em
/// `igrejas/{espaço}/{coleção}/{id}` com os campos: json (o item), h (hash),
/// u (momento da gravação) e x (true = apagado, "lápide").
/// Dois "retratos" locais (hash local e hash remoto da última sincronização)
/// dizem o que mudou aqui e o que mudou lá. Se os dois lados mudaram o mesmo
/// item, vale o deste aparelho.
class Sync extends ChangeNotifier {
  Sync._();
  static final Sync instance = Sync._();

  static const List<String> _colecoes = [
    'membros', 'listas', 'atas', 'compromissos', 'avisos', 'datasIgreja', 'movimentos',
  ];

  // --- configuração e sessão (persistidas)
  String apiKey = '';
  String projectId = '';
  String webClientId = '';
  String igrejaId = '';
  String codigo = '';
  bool automatico = true;
  int ultimoSync = 0;
  Sessao? sessao;

  // --- estado
  bool ocupado = false;
  String status = '';
  String? erro;

  Map<String, String> _sl = {}; // hash local na última sincronização
  Map<String, String> _sr = {}; // hash remoto na última sincronização

  Banco? _banco;
  VoidCallback? _aoAplicar;
  Timer? _debEnvio;
  Timer? _periodico;

  bool get configurado => apiKey.trim().isNotEmpty && projectId.trim().isNotEmpty;
  bool get logado => sessao != null;
  bool get pronto => configurado && logado && igrejaId.isNotEmpty;

  FirebaseRest _api() => FirebaseRest(apiKey: apiKey.trim(), projectId: projectId.trim());

  // ------------------------------------------------------------ persistência

  Future<void> carregar() async {
    final m = await AppStorage.instance.lerMapa('nuvem');
    if (m != null) {
      apiKey = '${m['apiKey'] ?? ''}';
      projectId = '${m['projectId'] ?? ''}';
      webClientId = '${m['webClientId'] ?? ''}';
      igrejaId = '${m['igrejaId'] ?? ''}';
      codigo = '${m['codigo'] ?? ''}';
      automatico = m['automatico'] as bool? ?? true;
      ultimoSync = (m['ultimoSync'] as num?)?.toInt() ?? 0;
      final s = m['sessao'];
      if (s is Map) sessao = Sessao.fromJson(Map<String, dynamic>.from(s));
    }
    final snap = await AppStorage.instance.lerMapa('nuvem_snap');
    if (snap != null) {
      _sl = Map<String, String>.from((snap['sl'] as Map? ?? {}).map((k, v) => MapEntry('$k', '$v')));
      _sr = Map<String, String>.from((snap['sr'] as Map? ?? {}).map((k, v) => MapEntry('$k', '$v')));
    }
  }

  Future<void> _salvarEstado() async {
    await AppStorage.instance.gravarMapa('nuvem', {
      'apiKey': apiKey,
      'projectId': projectId,
      'webClientId': webClientId,
      'igrejaId': igrejaId,
      'codigo': codigo,
      'automatico': automatico,
      'ultimoSync': ultimoSync,
      'sessao': sessao?.toJson(),
    });
  }

  Future<void> _salvarSnapshots() async {
    await AppStorage.instance.gravarMapa('nuvem_snap', {'sl': _sl, 'sr': _sr});
  }

  // ---------------------------------------------------------------- ligação

  /// Liga o serviço ao banco em uso. [aoAplicar] é chamado quando chegam dados
  /// novos da nuvem (para redesenhar as telas e gravar localmente).
  void vincular(Banco banco, VoidCallback aoAplicar) {
    _banco = banco;
    _aoAplicar = aoAplicar;
    _periodico?.cancel();
    _periodico = Timer.periodic(const Duration(seconds: 60), (_) {
      if (automatico) sincronizar();
    });
    if (pronto && automatico) sincronizar();
  }

  /// Chamado a cada alteração local: envia depois de uma pausa curta.
  void agendarEnvio() {
    if (!pronto || !automatico) return;
    _debEnvio?.cancel();
    _debEnvio = Timer(const Duration(seconds: 4), sincronizar);
  }

  Future<void> alterarAutomatico(bool v) async {
    automatico = v;
    await _salvarEstado();
    notifyListeners();
    if (v) sincronizar();
  }

  Future<void> salvarConfig(String chave, String projeto, String webId) async {
    apiKey = chave.trim();
    projectId = projeto.trim();
    webClientId = webId.trim();
    await _salvarEstado();
    notifyListeners();
  }

  // ------------------------------------------------------------------ conta

  void _exigirConfig() {
    if (!configurado) {
      throw FirebaseErro('Preencha a chave de API (Web API Key) e o ID do projeto primeiro.');
    }
  }

  Future<void> _definirSessao(Sessao s) async {
    sessao = s;
    erro = null;
    await _salvarEstado();
    notifyListeners();
  }

  Future<void> entrarEmail(String email, String senha) async {
    _exigirConfig();
    await _definirSessao(await _api().entrar(email.trim(), senha));
  }

  Future<void> cadastrarEmail(String email, String senha) async {
    _exigirConfig();
    await _definirSessao(await _api().cadastrar(email.trim(), senha));
  }

  Future<void> redefinirSenha(String email) async {
    _exigirConfig();
    await _api().redefinirSenha(email.trim());
  }

  Future<void> entrarGoogle() async {
    _exigirConfig();
    if (!Platform.isAndroid) {
      throw FirebaseErro('O login com Google funciona só no Android. Use e-mail e senha.');
    }
    if (webClientId.trim().isEmpty) {
      throw FirebaseErro('Informe o "ID do cliente web" do Firebase para usar o login com Google.');
    }
    final g = GoogleSignIn(scopes: const ['email'], serverClientId: webClientId.trim());
    await g.signOut(); // permite escolher outra conta
    final conta = await g.signIn();
    if (conta == null) throw FirebaseErro('Login cancelado.');
    final auth = await conta.authentication;
    final idt = auth.idToken;
    if (idt == null) throw FirebaseErro('O Google não devolveu o token. Confira o ID do cliente web.');
    final s = await _api().entrarComGoogle(idt);
    if (s.email.isEmpty) s.email = conta.email;
    await _definirSessao(s);
  }

  Future<void> sair() async {
    sessao = null;
    status = '';
    erro = null;
    try {
      if (Platform.isAndroid) await GoogleSignIn().signOut();
    } catch (_) {}
    await _salvarEstado();
    notifyListeners();
  }

  /// Token válido (renova se estiver perto de expirar).
  Future<String> _token() async {
    var s = sessao;
    if (s == null) throw FirebaseErro('Você não está conectado.');
    if (s.expiraEm - DateTime.now().millisecondsSinceEpoch < 120000) {
      s = await _api().renovar(s);
      sessao = s;
      await _salvarEstado();
    }
    return s.idToken;
  }

  // ----------------------------------------------------------------- espaço

  static String _aleatorio(int n, String alfabeto) {
    final r = Random.secure();
    return List.generate(n, (_) => alfabeto[r.nextInt(alfabeto.length)]).join();
  }

  /// Cria o espaço da igreja e entra nele.
  Future<void> criarEspaco() async {
    final api = _api();
    final token = await _token();
    final s = sessao!;
    final id = _aleatorio(10, 'abcdefghijkmnpqrstuvwxyz23456789');
    final cod = _aleatorio(8, 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789');
    final agora = DateTime.now().millisecondsSinceEpoch;
    await api.gravar(token, [
      {
        'update': {
          'name': api.nomeDoc('igrejas/$id'),
          'fields': {'codigo': FirebaseRest.texto(cod), 'criadoEm': FirebaseRest.inteiro(agora)},
        },
        'currentDocument': {'exists': false},
      },
      {
        'update': {
          'name': api.nomeDoc('igrejas/$id/usuarios/${s.uid}'),
          'fields': {
            'codigo': FirebaseRest.texto(cod),
            'email': FirebaseRest.texto(s.email),
            'criadoEm': FirebaseRest.inteiro(agora),
          },
        },
        'currentDocument': {'exists': false},
      },
    ]);
    await _entrouNoEspaco(id, cod);
  }

  /// Entra em um espaço existente com o ID e o código.
  Future<void> entrarEspaco(String id, String cod) async {
    final api = _api();
    final token = await _token();
    final s = sessao!;
    final espacoId = id.trim().toLowerCase();
    final espacoCod = cod.trim().toUpperCase();
    try {
      await api.gravar(token, [
        {
          'update': {
            'name': api.nomeDoc('igrejas/$espacoId/usuarios/${s.uid}'),
            'fields': {
              'codigo': FirebaseRest.texto(espacoCod),
              'email': FirebaseRest.texto(s.email),
              'criadoEm': FirebaseRest.inteiro(DateTime.now().millisecondsSinceEpoch),
            },
          },
        },
      ]);
    } on FirebaseErro {
      // Já era membro? Então consegue ler o espaço.
      try {
        await api.listar(token, 'igrejas/$espacoId/config');
      } on FirebaseErro {
        throw FirebaseErro('ID ou código do espaço inválido (ou o espaço não existe).');
      }
    }
    await _entrouNoEspaco(espacoId, espacoCod);
  }

  Future<void> _entrouNoEspaco(String id, String cod) async {
    igrejaId = id;
    codigo = cod;
    _sl = {};
    _sr = {};
    await _salvarEstado();
    await _salvarSnapshots();
    notifyListeners();
    sincronizar();
  }

  Future<void> sairEspaco() async {
    igrejaId = '';
    codigo = '';
    _sl = {};
    _sr = {};
    status = '';
    await _salvarEstado();
    await _salvarSnapshots();
    notifyListeners();
  }

  // ----------------------------------------------------------- sincronização

  static String _hash(String s) => sha1.convert(utf8.encode(s)).toString();

  Map<String, String> _itensLocais(Banco b) {
    final j = b.toJson();
    final out = <String, String>{};
    for (final col in _colecoes) {
      for (final item in (j[col] as List? ?? const [])) {
        final m = item as Map;
        final id = '${m['id'] ?? ''}';
        if (id.isEmpty) continue;
        out['$col/$id'] = jsonEncode(m);
      }
    }
    final cfg = <String, dynamic>{};
    for (final e in j.entries) {
      if (!_colecoes.contains(e.key)) cfg[e.key] = e.value;
    }
    out['config/config'] = jsonEncode(cfg);
    return out;
  }

  static String _str(Object? campo) =>
      campo is Map ? '${campo['stringValue'] ?? ''}' : '';
  static bool _bool(Object? campo) => campo is Map && campo['booleanValue'] == true;

  static String _chaveDoNome(String nome) {
    final p = nome.split('/');
    return '${p[p.length - 2]}/${p.last}';
  }

  /// Aplica um item vindo da nuvem (ou o apaga, se [jsonStr] for null).
  void _aplicar(Banco b, String k, String? jsonStr) {
    final i = k.indexOf('/');
    final col = k.substring(0, i);
    final id = k.substring(i + 1);
    Map<String, dynamic>? m;
    if (jsonStr != null && jsonStr.isNotEmpty) {
      m = Map<String, dynamic>.from(jsonDecode(jsonStr) as Map);
    }

    void trocar<T>(List<T> lista, String Function(T) idDe, T? novo) {
      final ix = lista.indexWhere((x) => idDe(x) == id);
      if (novo == null) {
        if (ix >= 0) lista.removeAt(ix);
      } else if (ix >= 0) {
        lista[ix] = novo;
      } else {
        lista.add(novo);
      }
    }

    switch (col) {
      case 'membros':
        trocar<Entidade>(b.membros, (x) => x.id, m == null ? null : Entidade.fromJson(m));
        break;
      case 'listas':
        trocar<ListaEntidades>(b.listas, (x) => x.id, m == null ? null : ListaEntidades.fromJson(m));
        break;
      case 'atas':
        trocar<Ata>(b.atas, (x) => x.id, m == null ? null : Ata.fromJson(m));
        break;
      case 'compromissos':
        trocar<Compromisso>(b.compromissos, (x) => x.id, m == null ? null : Compromisso.fromJson(m));
        break;
      case 'avisos':
        trocar<Aviso>(b.avisos, (x) => x.id, m == null ? null : Aviso.fromJson(m));
        break;
      case 'datasIgreja':
        trocar<DataIgreja>(b.datasIgreja, (x) => x.id, m == null ? null : DataIgreja.fromJson(m));
        break;
      case 'movimentos':
        trocar<Movimento>(b.movimentos, (x) => x.id, m == null ? null : Movimento.fromJson(m));
        break;
      case 'config':
        if (m != null) {
          final t = Banco.fromJson(m);
          b.congregacoes = t.congregacoes;
          b.colunas = t.colunas;
          b.classes = t.classes;
          b.multiAtiva = t.multiAtiva;
          b.multiNome = t.multiNome;
          b.multiCor = t.multiCor;
          b.multiEmTodas = t.multiEmTodas;
          b.ordemMembros = t.ordemMembros;
        }
        break;
    }
  }

  Future<void> sincronizar() async {
    final banco = _banco;
    if (!pronto || banco == null || ocupado) return;

    ocupado = true;
    erro = null;
    status = 'Sincronizando...';
    notifyListeners();

    try {
      final api = _api();
      final token = await _token();

      // 1) retrato local
      final locais = _itensLocais(banco);
      final hashL = {for (final e in locais.entries) e.key: _hash(e.value)};

      // 2) retrato remoto (só hash, data e marca de apagado)
      final remoto = <String, _Remoto>{};
      for (final col in [..._colecoes, 'config']) {
        final docs = await api.listar(token, 'igrejas/$igrejaId/$col');
        for (final d in docs) {
          final f = (d['fields'] as Map?) ?? const {};
          remoto[_chaveDoNome('${d['name']}')] = _Remoto(_str(f['h']), _bool(f['x']));
        }
      }

      // 3) o que fazer com cada item
      final chaves = {...hashL.keys, ...remoto.keys, ..._sl.keys, ..._sr.keys};
      final enviar = <String>[];
      final baixar = <String>[];
      final novoSl = <String, String>{};
      final novoSr = <String, String>{};

      for (final k in chaves) {
        final l = hashL[k] ?? '-';
        final r = remoto[k];
        final rh = (r == null || r.apagado || r.hash.isEmpty) ? '-' : r.hash;
        final sl = _sl[k] ?? '-';
        final sr = _sr[k] ?? '-';
        final lMudou = l != sl;
        final rMudou = rh != sr;

        if (!lMudou && !rMudou) {
          novoSl[k] = l;
          novoSr[k] = rh;
        } else if (lMudou && !rMudou) {
          enviar.add(k);
        } else if (!lMudou && rMudou) {
          baixar.add(k);
        } else if (l == rh) {
          novoSl[k] = l;
          novoSr[k] = rh;
        } else {
          enviar.add(k); // conflito: vale o deste aparelho
        }
      }

      // 4) enviar
      final agora = DateTime.now().millisecondsSinceEpoch;
      var enviados = 0;
      var grandes = 0;
      final lote = <Map<String, dynamic>>[];
      var tamanho = 0;

      Future<void> descarregar() async {
        if (lote.isEmpty) return;
        await api.gravar(token, List.of(lote));
        lote.clear();
        tamanho = 0;
      }

      for (final k in enviar) {
        final json = locais[k];
        final apagar = json == null;
        if (!apagar && json.length > 900000) {
          grandes++; // passaria do limite de 1 MiB do Firestore
          continue;
        }
        final h = apagar ? '-' : hashL[k]!;
        final i = k.indexOf('/');
        final col = k.substring(0, i);
        final id = k.substring(i + 1);
        final custo = apagar ? 300 : json.length + 300;
        if (lote.length >= 100 || tamanho + custo > 2500000) await descarregar();
        lote.add({
          'update': {
            'name': api.nomeDoc('igrejas/$igrejaId/$col/$id'),
            'fields': {
              'json': FirebaseRest.texto(apagar ? '' : json),
              'h': FirebaseRest.texto(h),
              'u': FirebaseRest.inteiro(agora),
              'x': FirebaseRest.booleano(apagar),
            },
          },
        });
        tamanho += custo;
        novoSl[k] = h;
        novoSr[k] = h;
        enviados++;
      }
      await descarregar();

      // 5) baixar
      var baixados = 0;
      final aBaixar = <String>[];
      for (final k in baixar) {
        final r = remoto[k];
        if (r == null || r.apagado || r.hash.isEmpty) {
          _aplicar(banco, k, null);
          novoSl[k] = '-';
          novoSr[k] = '-';
          baixados++;
        } else {
          aBaixar.add(k);
        }
      }
      for (var i = 0; i < aBaixar.length; i += 15) {
        final fim = min(i + 15, aBaixar.length);
        final docs = await api.buscarVarios(
            token, aBaixar.sublist(i, fim).map((k) => 'igrejas/$igrejaId/$k').toList());
        for (final d in docs) {
          final k = _chaveDoNome('${d['name']}');
          final f = (d['fields'] as Map?) ?? const {};
          _aplicar(banco, k, _str(f['json']));
          novoSr[k] = remoto[k]?.hash ?? _str(f['h']);
          baixados++;
        }
      }
      if (baixados > 0) {
        // retrato local depois de aplicar, para não "rebaixar" na próxima vez
        final depois = _itensLocais(banco);
        for (final k in baixar) {
          final j = depois[k];
          novoSl[k] = j == null ? '-' : _hash(j);
        }
      }

      _sl = novoSl;
      _sr = novoSr;
      await _salvarSnapshots();
      ultimoSync = DateTime.now().millisecondsSinceEpoch;
      await _salvarEstado();

      status = 'Sincronizado: $enviados enviado(s), $baixados recebido(s)'
          '${grandes > 0 ? ' · $grandes item(ns) grande(s) demais ficaram só neste aparelho' : ''}';
      if (baixados > 0) _aoAplicar?.call();
    } on FirebaseErro catch (e) {
      erro = e.mensagem;
      status = 'Falha na sincronização';
    } on SocketException {
      erro = 'Sem conexão com a internet. Tentaremos de novo.';
      status = 'Offline';
    } on TimeoutException {
      erro = 'O servidor demorou para responder. Tentaremos de novo.';
      status = 'Sem resposta';
    } catch (e) {
      erro = 'Erro: $e';
      status = 'Falha na sincronização';
    } finally {
      ocupado = false;
      notifyListeners();
    }
  }
}
