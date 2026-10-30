import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';

import 'models.dart';

/// Persistência local (Sembast).
///
/// Registros:
///  - 'banco'      : membros, congregações, campos extras e listas (formato atual)
///  - 'listas'     : formato ANTIGO (cada lista com seus membros). Nunca é
///                   apagado; serve de cópia de segurança da migração.
///  - 'config_pdf' : opções de impressão (margens, logos, capa...)
///  - 'config_app' : aparência (tema claro/escuro/automático)
class AppStorage {
  AppStorage._();
  static final AppStorage instance = AppStorage._();

  Database? _db;
  final _store = stringMapStoreFactory.store('ibmmkar');

  ConfigPdf configPdf = ConfigPdf();

  /// 'system' (automático), 'light', 'dark' ou 'preto' (preto absoluto).
  String tema = 'system';

  /// Cor de destaque do app (hex).
  String corApp = '#8B6CEF';

  bool get disponivel => _db != null;

  Future<void> abrir() async {
    final dir = await getApplicationDocumentsDirectory();
    await dir.create(recursive: true);
    _db = await databaseFactoryIo.openDatabase(p.join(dir.path, 'ibmmkar.db'));

    final cfg = await _store.record('config_pdf').get(_db!);
    if (cfg != null) configPdf = ConfigPdf.fromJson(Map<String, dynamic>.from(cfg));

    final app = await _store.record('config_app').get(_db!);
    final t = app?['tema'];
    if (t == 'light' || t == 'dark' || t == 'system' || t == 'preto') tema = t as String;
    final c = app?['corApp'];
    if (c is String && c.startsWith('#') && c.length == 7) corApp = c;
  }

  Future<Banco> carregarBanco() async {
    final db = _db;
    if (db == null) return Banco.novo();

    final atual = await _store.record('banco').get(db);
    if (atual != null) return Banco.fromJson(Map<String, dynamic>.from(atual));

    // Primeira abertura nesta versão: migra o formato antigo, se existir.
    final antigo = await _store.record('listas').get(db);
    final itens = antigo?['listas'];
    Banco banco;
    if (itens is List && itens.isNotEmpty) {
      banco = Banco();
      for (final raw in itens) {
        final l = Map<String, dynamic>.from(raw as Map);
        banco.mesclarExterno(
          listaJson: l,
          membrosJson: (l['linhas'] as List?) ?? const [],
          congregacoesJson: l['congregacoes'] as List?,
          colunasJson: l['colunas'] as List?,
          manterIdLista: true,
          atualizarExistentes: true,
        );
      }
    } else {
      banco = Banco.novo();
    }
    await salvarBanco(banco);
    return banco;
  }

  Future<void> salvarBanco(Banco banco) async {
    final db = _db;
    if (db == null) return;
    await _store.record('banco').put(db, banco.toJson());
  }

  Future<void> salvarConfigPdf(ConfigPdf cfg) async {
    configPdf = cfg;
    final db = _db;
    if (db == null) return;
    await _store.record('config_pdf').put(db, cfg.toJson());
  }

  /// Registros genéricos (nuvem, retratos de sincronização...).
  Future<Map<String, dynamic>?> lerMapa(String chave) async {
    final db = _db;
    if (db == null) return null;
    final m = await _store.record(chave).get(db);
    return m == null ? null : Map<String, dynamic>.from(m);
  }

  Future<void> gravarMapa(String chave, Map<String, dynamic> valor) async {
    final db = _db;
    if (db == null) return;
    await _store.record(chave).put(db, valor);
  }

  Future<void> salvarAparencia(String novoTema, String novaCor) async {
    tema = novoTema;
    corApp = novaCor;
    final db = _db;
    if (db == null) return;
    await _store.record('config_app').put(db, {'tema': novoTema, 'corApp': novaCor});
  }
}
