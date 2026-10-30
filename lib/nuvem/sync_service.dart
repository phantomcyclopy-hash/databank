import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models.dart';
import '../storage.dart';
import 'config_igreja.dart';
import 'firebase_rest.dart';

class _Remoto {
  final String hash;
  final bool apagado;
  _Remoto(this.hash, this.apagado);
}

/// Conta listada na tela "Contas e permissões".
class ContaInfo {
  final String uid;
  final String email;
  final String nome;
  final String papel;
  final String pedido;
  ContaInfo(this.uid, this.email, this.nome, this.papel, this.pedido);
}

/// Login (e-mail e senha), papéis e sincronização com o Firebase.
///
/// Cada item (membro, lista, ata, aviso...) é um documento em
/// `igrejas/{kEspacoId}/{coleção}/{id}` com: json (o item), h (hash), u (momento
/// da gravação) e x (true = apagado). Dois "retratos" locais (hash local e hash
/// remoto da última sincronização) dizem o que mudou aqui e o que mudou lá.
/// Se os dois lados mudaram o mesmo item, vale o deste aparelho.
///
/// O que cada papel sincroniza: dono e secretaria enviam e recebem tudo;
/// inspetor recebe tudo e não envia nada; membro só recebe o que é público
/// (avisos, agenda, cultos, datas e publicações).
class Sync extends ChangeNotifier {
  Sync._();
  static final Sync instance = Sync._();

  static const List<String> _todas = [
    'membros', 'listas', 'atas', 'compromissos', 'agenda', 'avisos',
    'datasIgreja', 'movimentos', 'cultos', 'publicacoes', 'contato',
  ];
  static const List<String> _publicas = [
    'agenda', 'avisos', 'datasIgreja', 'cultos', 'publicacoes', 'contato',
  ];

  /// Só a conta dona grava o "Fale conosco".
  bool _podeEnviar(String chave) =>
      podeEditar && (!chave.startsWith('contato/') || ehDono);

  // --- sessão e perfil (persistidos)
  Sessao? sessao;
  String papel = 'membro';
  String nome = '';
  String foto = ''; // base64 pequeno
  String pedido = ''; // 'secretaria' = pediu aprovação
  bool automatico = true;
  int ultimoSync = 0;

  // --- estado
  bool ocupado = false;
  String status = '';
  String? erro;

  Map<String, String> _sl = {};
  Map<String, String> _sr = {};

  Banco? _banco;
  VoidCallback? _aoAplicar;
  Timer? _debEnvio;
  Timer? _periodico;

  // ----------------------------------------------------------------- papéis

  bool get logado => sessao != null;
  String get email => sessao?.email ?? '';
  String get papelEfetivo => email.toLowerCase() == kDonoEmail ? 'dono' : papel;
  bool get ehDono => papelEfetivo == 'dono';
  bool get podeEditar => papelEfetivo == 'dono' || papelEfetivo == 'secretaria';
  bool get veTudo => podeEditar || papelEfetivo == 'inspetor';
  bool get bloqueado => papelEfetivo == 'bloqueado';
  bool get pronto => logado && !bloqueado;
  String get papelRotulo => kPapeis[papelEfetivo] ?? papelEfetivo;
  String get nomeExibido => nome.isNotEmpty ? nome : (email.contains('@') ? email.split('@').first : email);

  List<String> get _colecoesAtivas => veTudo ? _todas : _publicas;

  FirebaseRest _api() => FirebaseRest(apiKey: kFirebaseApiKey, projectId: kFirebaseProjeto);

  // ------------------------------------------------------------ persistência

  Future<void> carregar() async {
    final m = await AppStorage.instance.lerMapa('nuvem');
    if (m != null) {
      automatico = m['automatico'] as bool? ?? true;
      ultimoSync = (m['ultimoSync'] as num?)?.toInt() ?? 0;
      papel = '${m['papel'] ?? 'membro'}';
      nome = '${m['nome'] ?? ''}';
      foto = '${m['foto'] ?? ''}';
      pedido = '${m['pedido'] ?? ''}';
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
      'automatico': automatico,
      'ultimoSync': ultimoSync,
      'papel': papel,
      'nome': nome,
      'foto': foto,
      'pedido': pedido,
      'sessao': sessao?.toJson(),
    });
  }

  Future<void> _salvarSnapshots() async {
    await AppStorage.instance.gravarMapa('nuvem_snap', {'sl': _sl, 'sr': _sr});
  }

  // ---------------------------------------------------------------- ligação

  /// Liga o serviço ao banco em uso. [aoAplicar] roda quando chegam dados novos.
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
    if (!pronto || !podeEditar || !automatico) return;
    _debEnvio?.cancel();
    _debEnvio = Timer(const Duration(seconds: 4), sincronizar);
  }

  Future<void> alterarAutomatico(bool v) async {
    automatico = v;
    await _salvarEstado();
    notifyListeners();
    if (v) sincronizar();
  }

  // ------------------------------------------------------------------ conta

  Future<void> _definirSessao(Sessao s) async {
    sessao = s;
    erro = null;
    await _salvarEstado();
    notifyListeners();
  }

  String get _caminhoPerfil => 'igrejas/$kEspacoId/usuarios/${sessao!.uid}';

  Future<void> entrar(String email, String senha) async {
    final s = await _api().entrar(email.trim(), senha);
    await _definirSessao(s);
    try {
      await _carregarPerfil(criarSeFaltar: true);
    } catch (_) {}
    notifyListeners();
    sincronizar();
  }

  /// Cria a conta. Todo mundo entra como "membro"; quem pede "secretaria"
  /// fica com o pedido pendente até a conta dona aprovar.
  Future<void> criarConta({
    required String nomeCompleto,
    required String email,
    required String senha,
    required bool pedirSecretaria,
  }) async {
    final api = _api();
    final s = await api.cadastrar(email.trim(), senha);
    await _definirSessao(s);
    await api.atualizarCampos(s.idToken, _caminhoPerfil, {
      'email': FirebaseRest.texto(s.email),
      'nome': FirebaseRest.texto(nomeCompleto.trim()),
      'papel': FirebaseRest.texto('membro'),
      'pedido': FirebaseRest.texto(pedirSecretaria ? 'secretaria' : ''),
      'criadoEm': FirebaseRest.inteiro(DateTime.now().millisecondsSinceEpoch),
    });
    papel = 'membro';
    nome = nomeCompleto.trim();
    foto = '';
    pedido = pedirSecretaria ? 'secretaria' : '';
    await _salvarEstado();
    notifyListeners();
    sincronizar();
  }

  Future<void> redefinirSenha(String email) => _api().redefinirSenha(email.trim());

  Future<void> _carregarPerfil({bool criarSeFaltar = false}) async {
    final s = sessao;
    if (s == null) return;
    final api = _api();
    final token = await _token();
    final docs = await api.buscarVarios(token, [_caminhoPerfil]);
    if (docs.isEmpty) {
      if (!criarSeFaltar) return;
      final padrao = s.email.contains('@') ? s.email.split('@').first : s.email;
      await api.atualizarCampos(token, _caminhoPerfil, {
        'email': FirebaseRest.texto(s.email),
        'nome': FirebaseRest.texto(padrao),
        'papel': FirebaseRest.texto('membro'),
        'pedido': FirebaseRest.texto(''),
        'criadoEm': FirebaseRest.inteiro(DateTime.now().millisecondsSinceEpoch),
      });
      papel = 'membro';
      nome = padrao;
      foto = '';
      pedido = '';
    } else {
      final f = (docs.first['fields'] as Map?) ?? const {};
      final p = _str(f['papel']);
      papel = p.isEmpty ? 'membro' : p;
      nome = _str(f['nome']);
      foto = _str(f['foto']);
      pedido = _str(f['pedido']);
    }
    await _salvarEstado();
  }

  /// Salva nome e foto do próprio perfil.
  Future<void> salvarPerfil(String novoNome, String novaFoto) async {
    final token = await _token();
    await _api().atualizarCampos(token, _caminhoPerfil, {
      'nome': FirebaseRest.texto(novoNome.trim()),
      'foto': FirebaseRest.texto(novaFoto),
    });
    nome = novoNome.trim();
    foto = novaFoto;
    await _salvarEstado();
    notifyListeners();
  }

  /// Sai da conta. Apaga os dados deste aparelho (eles continuam na nuvem),
  /// para que outra pessoa que entre aqui não veja o que não deve.
  Future<void> sair() async {
    if (pronto && podeEditar) {
      var espera = 0;
      while (ocupado && espera < 40) {
        await Future.delayed(const Duration(milliseconds: 500));
        espera++;
      }
      try {
        await sincronizar(); // envia o que estiver pendente
      } catch (_) {}
    }
    sessao = null;
    papel = 'membro';
    nome = '';
    foto = '';
    pedido = '';
    status = '';
    erro = null;
    _sl = {};
    _sr = {};
    await _salvarEstado();
    await _salvarSnapshots();
    final b = _banco;
    if (b != null) {
      b.substituirPor(Banco.novo());
      await AppStorage.instance.salvarBanco(b);
      _aoAplicar?.call();
    }
    notifyListeners();
  }

  // ----------------------------------------------- contas (só a conta dona)

  Future<List<ContaInfo>> listarContas() async {
    final token = await _token();
    final docs = await _api().listar(token, 'igrejas/$kEspacoId/usuarios',
        campos: const ['email', 'nome', 'papel', 'pedido']);
    final out = <ContaInfo>[];
    for (final d in docs) {
      final f = (d['fields'] as Map?) ?? const {};
      final uid = '${d['name']}'.split('/').last;
      final p = _str(f['papel']);
      out.add(ContaInfo(uid, _str(f['email']), _str(f['nome']), p.isEmpty ? 'membro' : p, _str(f['pedido'])));
    }
    out.sort((a, b) {
      // pendentes primeiro, depois por nome
      final pa = a.pedido.isNotEmpty ? 0 : 1;
      final pb = b.pedido.isNotEmpty ? 0 : 1;
      if (pa != pb) return pa.compareTo(pb);
      return (a.nome.isEmpty ? a.email : a.nome)
          .toLowerCase()
          .compareTo((b.nome.isEmpty ? b.email : b.nome).toLowerCase());
    });
    return out;
  }

  Future<void> definirPapel(String uid, String novoPapel) async {
    final token = await _token();
    await _api().atualizarCampos(token, 'igrejas/$kEspacoId/usuarios/$uid', {
      'papel': FirebaseRest.texto(novoPapel),
      'pedido': FirebaseRest.texto(''),
    });
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

  // ----------------------------------------------------------- sincronização

  static String _hash(String s) => sha1.convert(utf8.encode(s)).toString();

  Map<String, String> _itensLocais(Banco b) {
    final j = b.toJson();
    final ativas = _colecoesAtivas;
    final compromissos = (j['compromissos'] as List? ?? const []).cast<Map>();
    final porColecao = <String, List<Map>>{
      'membros': (j['membros'] as List? ?? const []).cast<Map>(),
      'listas': (j['listas'] as List? ?? const []).cast<Map>(),
      'atas': (j['atas'] as List? ?? const []).cast<Map>(),
      'avisos': (j['avisos'] as List? ?? const []).cast<Map>(),
      'datasIgreja': (j['datasIgreja'] as List? ?? const []).cast<Map>(),
      'movimentos': (j['movimentos'] as List? ?? const []).cast<Map>(),
      'cultos': (j['cultos'] as List? ?? const []).cast<Map>(),
      'publicacoes': (j['publicacoes'] as List? ?? const []).cast<Map>(),
      'contato': (!b.contato.vazio && j['contato'] is Map)
          ? <Map>[{...(j['contato'] as Map), 'id': 'principal'}]
          : <Map>[],
      // eventos são públicos (agenda); lembretes ficam restritos
      'agenda': [for (final c in compromissos) if (c['tipo'] == 'evento') c],
      'compromissos': [for (final c in compromissos) if (c['tipo'] != 'evento') c],
    };

    final out = <String, String>{};
    for (final col in ativas) {
      for (final m in porColecao[col] ?? const <Map>[]) {
        final id = '${m['id'] ?? ''}';
        if (id.isEmpty) continue;
        out['$col/$id'] = jsonEncode(m);
      }
    }
    const fora = {
      'membros', 'listas', 'atas', 'compromissos', 'avisos', 'datasIgreja',
      'movimentos', 'cultos', 'publicacoes', 'contato',
    };
    final cfg = <String, dynamic>{};
    for (final e in j.entries) {
      if (!fora.contains(e.key)) cfg[e.key] = e.value;
    }
    out['config/config'] = jsonEncode(cfg);
    return out;
  }

  static String _str(Object? campo) => campo is Map ? '${campo['stringValue'] ?? ''}' : '';
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
      case 'agenda':
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
      case 'cultos':
        trocar<Culto>(b.cultos, (x) => x.id, m == null ? null : Culto.fromJson(m));
        break;
      case 'publicacoes':
        trocar<Publicacao>(b.publicacoes, (x) => x.id, m == null ? null : Publicacao.fromJson(m));
        break;
      case 'contato':
        b.contato = m == null ? Contato() : Contato.fromJson(m);
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

      // papel atual (pode ter mudado)
      final papelAntes = papelEfetivo;
      await _carregarPerfil(criarSeFaltar: true);
      if (bloqueado) {
        status = 'Acesso bloqueado';
        return;
      }
      if (papelEfetivo != papelAntes) notifyListeners();

      final ativas = _colecoesAtivas;
      final aceitaPrefixo = {...ativas, 'config'};

      // 1) retrato local
      final locais = _itensLocais(banco);
      final hashL = {for (final e in locais.entries) e.key: _hash(e.value)};

      // 2) retrato remoto (só hash, data e marca de apagado)
      final remoto = <String, _Remoto>{};
      for (final col in [...ativas, 'config']) {
        final docs = await api.listar(token, 'igrejas/$kEspacoId/$col');
        for (final d in docs) {
          final f = (d['fields'] as Map?) ?? const {};
          remoto[_chaveDoNome('${d['name']}')] = _Remoto(_str(f['h']), _bool(f['x']));
        }
      }

      // 3) o que fazer com cada item
      final chaves = {...hashL.keys, ...remoto.keys, ..._sl.keys, ..._sr.keys}
          .where((k) => aceitaPrefixo.contains(k.split('/').first));
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
          if (_podeEnviar(k)) {
            enviar.add(k);
          } else {
            // sem permissão para enviar: o que a nuvem tem prevalece
            baixar.add(k);
          }
        } else if (!lMudou && rMudou) {
          baixar.add(k);
        } else if (l == rh) {
          novoSl[k] = l;
          novoSr[k] = rh;
        } else {
          if (_podeEnviar(k)) {
            enviar.add(k); // conflito: vale o deste aparelho
          } else {
            baixar.add(k);
          }
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
            'name': api.nomeDoc('igrejas/$kEspacoId/$col/$id'),
            'fields': {
              'json': FirebaseRest.texto(apagar ? '' : json),
              'h': FirebaseRest.texto(h),
              'u': FirebaseRest.inteiro(agora),
              'x': FirebaseRest.booleano(apagar),
            },
          },
        });
        tamanho += custo;
        novoSl[k] = apagar ? '-' : h;
        novoSr[k] = apagar ? '-' : h;
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
            token, aBaixar.sublist(i, fim).map((k) => 'igrejas/$kEspacoId/$k').toList());
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
