import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class FirebaseErro implements Exception {
  final String mensagem;
  FirebaseErro(this.mensagem);
  @override
  String toString() => mensagem;
}

/// Sessão de login (tokens do Firebase Authentication).
class Sessao {
  String idToken;
  String refreshToken;
  String uid;
  String email;
  int expiraEm; // ms desde 1970

  Sessao({
    required this.idToken,
    required this.refreshToken,
    required this.uid,
    required this.email,
    required this.expiraEm,
  });

  Map<String, dynamic> toJson() => {
        'idToken': idToken,
        'refreshToken': refreshToken,
        'uid': uid,
        'email': email,
        'expiraEm': expiraEm,
      };

  factory Sessao.fromJson(Map<String, dynamic> j) => Sessao(
        idToken: '${j['idToken'] ?? ''}',
        refreshToken: '${j['refreshToken'] ?? ''}',
        uid: '${j['uid'] ?? ''}',
        email: '${j['email'] ?? ''}',
        expiraEm: (j['expiraEm'] as num?)?.toInt() ?? 0,
      );
}

/// Cliente mínimo do Firebase Auth e do Cloud Firestore pela API REST.
/// Não depende de plugins nativos, então funciona igual no Android e no Windows.
class FirebaseRest {
  final String apiKey;
  final String projectId;

  FirebaseRest({required this.apiKey, required this.projectId});

  static const Duration _limite = Duration(seconds: 45);

  // ----------------------------------------------------------------- erros

  static String _traduzir(String bruto) {
    final b = bruto.toUpperCase();
    if (b.contains('EMAIL_EXISTS')) return 'Este e-mail já tem conta. Use "Entrar".';
    if (b.contains('INVALID_LOGIN_CREDENTIALS') ||
        b.contains('INVALID_PASSWORD') ||
        b.contains('EMAIL_NOT_FOUND')) {
      return 'E-mail ou senha incorretos.';
    }
    if (b.contains('WEAK_PASSWORD')) return 'Senha fraca: use pelo menos 6 caracteres.';
    if (b.contains('INVALID_EMAIL')) return 'E-mail inválido.';
    if (b.contains('USER_DISABLED')) return 'Esta conta foi desativada.';
    if (b.contains('TOO_MANY_ATTEMPTS')) return 'Muitas tentativas. Aguarde um pouco e tente de novo.';
    if (b.contains('OPERATION_NOT_ALLOWED')) {
      return 'Este tipo de login não está ativado no Firebase (Authentication > Método de login).';
    }
    if (b.contains('API KEY NOT VALID') || b.contains('API_KEY_INVALID')) {
      return 'Chave de API (Web API Key) inválida. Confira a chave do projeto.';
    }
    if (b.contains('PERMISSION_DENIED') || b.contains('MISSING OR INSUFFICIENT')) {
      return 'Sem permissão. Confira as regras do Firestore e se você entrou no espaço da igreja.';
    }
    if (b.contains('NOT_FOUND') && b.contains('DATABASE')) {
      return 'Banco Firestore não encontrado. Crie o banco no console do Firebase.';
    }
    if (b.contains('TOKEN_EXPIRED') || b.contains('INVALID_REFRESH_TOKEN') || b.contains('UNAUTHENTICATED')) {
      return 'Sua sessão expirou. Entre novamente.';
    }
    return bruto;
  }

  dynamic _decodificar(http.Response r) {
    dynamic corpo;
    try {
      corpo = r.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      corpo = null;
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return corpo;

    var msg = 'Erro ${r.statusCode} do servidor.';
    if (corpo is Map && corpo['error'] is Map) {
      final e = corpo['error'] as Map;
      msg = _traduzir('${e['message'] ?? ''} ${e['status'] ?? ''}'.trim());
    } else if (corpo is List && corpo.isNotEmpty && corpo.first is Map && (corpo.first as Map)['error'] is Map) {
      final e = (corpo.first as Map)['error'] as Map;
      msg = _traduzir('${e['message'] ?? ''} ${e['status'] ?? ''}'.trim());
    }
    throw FirebaseErro(msg);
  }

  Future<Map<String, dynamic>> _postJson(String url, Map<String, dynamic> corpo) async {
    final r = await http
        .post(Uri.parse(url),
            headers: {'Content-Type': 'application/json'}, body: jsonEncode(corpo))
        .timeout(_limite);
    final j = _decodificar(r);
    return j is Map ? Map<String, dynamic>.from(j) : <String, dynamic>{};
  }

  // ------------------------------------------------------------ autenticação

  Sessao _sessaoDe(Map<String, dynamic> j, String emailPadrao) => Sessao(
        idToken: '${j['idToken'] ?? j['id_token'] ?? ''}',
        refreshToken: '${j['refreshToken'] ?? j['refresh_token'] ?? ''}',
        uid: '${j['localId'] ?? j['user_id'] ?? ''}',
        email: '${j['email'] ?? emailPadrao}',
        expiraEm: DateTime.now().millisecondsSinceEpoch +
            (int.tryParse('${j['expiresIn'] ?? j['expires_in'] ?? 3600}') ?? 3600) * 1000,
      );

  Future<Sessao> cadastrar(String email, String senha) async {
    final j = await _postJson(
        'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey',
        {'email': email, 'password': senha, 'returnSecureToken': true});
    return _sessaoDe(j, email);
  }

  Future<Sessao> entrar(String email, String senha) async {
    final j = await _postJson(
        'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey',
        {'email': email, 'password': senha, 'returnSecureToken': true});
    return _sessaoDe(j, email);
  }

  /// Troca o token do Google (obtido no aparelho) por uma sessão do Firebase.
  Future<Sessao> entrarComGoogle(String googleIdToken) async {
    final j = await _postJson(
        'https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=$apiKey', {
      'postBody': 'id_token=$googleIdToken&providerId=google.com',
      'requestUri': 'http://localhost',
      'returnIdpCredential': true,
      'returnSecureToken': true,
    });
    return _sessaoDe(j, '');
  }

  Future<void> redefinirSenha(String email) async {
    await _postJson(
        'https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=$apiKey',
        {'requestType': 'PASSWORD_RESET', 'email': email});
  }

  Future<Sessao> renovar(Sessao s) async {
    final r = await http.post(
      Uri.parse('https://securetoken.googleapis.com/v1/token?key=$apiKey'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'grant_type': 'refresh_token', 'refresh_token': s.refreshToken},
    ).timeout(_limite);
    final j = _decodificar(r);
    final nova = _sessaoDe(Map<String, dynamic>.from(j as Map), s.email);
    if (nova.email.isEmpty) nova.email = s.email;
    return nova;
  }

  // ---------------------------------------------------------------- Firestore

  String get _raiz =>
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

  String nomeDoc(String caminho) =>
      'projects/$projectId/databases/(default)/documents/$caminho';

  Map<String, String> _auth(String token) =>
      {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};

  /// Lista os documentos de uma coleção, trazendo só os [campos] pedidos
  /// (padrão: h = hash, u = data, x = apagado) para não baixar fotos à toa.
  Future<List<Map<String, dynamic>>> listar(String token, String caminho,
      {List<String> campos = const ['h', 'u', 'x']}) async {
    final out = <Map<String, dynamic>>[];
    String? pagina;
    do {
      final q = StringBuffer('pageSize=300');
      for (final c in campos) {
        q.write('&mask.fieldPaths=$c');
      }
      if (pagina != null) q.write('&pageToken=${Uri.encodeQueryComponent(pagina)}');
      final r = await http.get(Uri.parse('$_raiz/$caminho?$q'), headers: _auth(token)).timeout(_limite);
      final j = _decodificar(r);
      pagina = null;
      if (j is Map) {
        for (final d in (j['documents'] as List? ?? const [])) {
          out.add(Map<String, dynamic>.from(d as Map));
        }
        final prox = j['nextPageToken'];
        if (prox is String && prox.isNotEmpty) pagina = prox;
      }
    } while (pagina != null);
    return out;
  }

  /// Baixa documentos completos (com o campo json).
  Future<List<Map<String, dynamic>>> buscarVarios(String token, List<String> caminhos) async {
    final r = await http
        .post(Uri.parse('$_raiz:batchGet'),
            headers: _auth(token),
            body: jsonEncode({'documents': caminhos.map(nomeDoc).toList()}))
        .timeout(_limite);
    final j = _decodificar(r);
    final out = <Map<String, dynamic>>[];
    if (j is List) {
      for (final item in j) {
        if (item is Map && item['found'] is Map) {
          out.add(Map<String, dynamic>.from(item['found'] as Map));
        }
      }
    }
    return out;
  }

  /// Grava vários documentos de uma vez (cria ou substitui).
  Future<void> gravar(String token, List<Map<String, dynamic>> escritas) async {
    if (escritas.isEmpty) return;
    final r = await http
        .post(Uri.parse('$_raiz:commit'),
            headers: _auth(token), body: jsonEncode({'writes': escritas}))
        .timeout(_limite);
    _decodificar(r);
  }

  /// Atualiza só os [campos] indicados (cria o documento se não existir).
  Future<void> atualizarCampos(
      String token, String caminho, Map<String, Map<String, dynamic>> campos) async {
    final mascara = campos.keys.map((k) => 'updateMask.fieldPaths=$k').join('&');
    final r = await http
        .patch(Uri.parse('$_raiz/$caminho?$mascara'),
            headers: _auth(token), body: jsonEncode({'fields': campos}))
        .timeout(_limite);
    _decodificar(r);
  }

  // Campos tipados do Firestore
  static Map<String, dynamic> texto(String v) => {'stringValue': v};
  static Map<String, dynamic> inteiro(int v) => {'integerValue': '$v'};
  static Map<String, dynamic> booleano(bool v) => {'booleanValue': v};
}
