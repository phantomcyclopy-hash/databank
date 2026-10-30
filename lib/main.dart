import 'package:flutter/material.dart';

import 'models.dart';
import 'nuvem/sync_service.dart';
import 'pages/aniversarios_page.dart';
import 'pages/aparencia_page.dart';
import 'pages/atas_page.dart';
import 'pages/listas_page.dart';
import 'pages/login_page.dart';
import 'pages/membros_page.dart';
import 'pages/mural_page.dart';
import 'storage.dart';
import 'widgets/membro_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await AppStorage.instance.abrir();
  } catch (e) {
    // Sem banco o app abre, mas nada será salvo.
    debugPrint('Falha ao abrir o banco local: $e');
  }
  try {
    await Sync.instance.carregar();
  } catch (e) {
    debugPrint('Falha ao carregar a sessão da nuvem: $e');
  }
  runApp(const IBMMKARApp());
}

class IBMMKARApp extends StatefulWidget {
  const IBMMKARApp({super.key});

  @override
  State<IBMMKARApp> createState() => _IBMMKARAppState();
}

class _IBMMKARAppState extends State<IBMMKARApp> {
  // 'system', 'light', 'dark' ou 'preto'; lembrados entre aberturas.
  String _tema = AppStorage.instance.tema;
  Color _cor = corDeHex(AppStorage.instance.corApp, padrao: kCorAppPadrao);

  ThemeMode get _modo {
    switch (_tema) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
      case 'preto':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  void _definirAparencia(String tema, Color cor) {
    setState(() {
      _tema = tema;
      _cor = cor;
    });
    AppStorage.instance.salvarAparencia(tema, hexDeCor(cor));
  }

  /// Visual no estilo Obsidian: superfícies planas, bordas finas e um único
  /// destaque (a cor escolhida). No modo "preto absoluto" o fundo é #000000.
  ThemeData _montarTema(Brightness brilho, {bool preto = false}) {
    final escuro = brilho == Brightness.dark;
    final acento = _cor;

    final fundo = !escuro
        ? const Color(0xFFFFFFFF)
        : (preto ? const Color(0xFF000000) : const Color(0xFF1E1E1E));
    final superficie = !escuro
        ? const Color(0xFFF5F5F7)
        : (preto ? const Color(0xFF0B0B0B) : const Color(0xFF262626));
    final borda = !escuro
        ? const Color(0xFFE2E2E6)
        : (preto ? const Color(0xFF262626) : const Color(0xFF383838));
    final texto = !escuro ? const Color(0xFF1C1C1E) : const Color(0xFFDCDDDE);
    final textoSuave = !escuro ? const Color(0xFF6E6E76) : const Color(0xFF9A9A9F);
    final sobreAcento =
        ThemeData.estimateBrightnessForColor(acento) == Brightness.dark ? Colors.white : Colors.black;

    final esquema = ColorScheme.fromSeed(seedColor: acento, brightness: brilho).copyWith(
      primary: acento,
      onPrimary: sobreAcento,
      secondary: acento,
      onSecondary: sobreAcento,
      primaryContainer: Color.alphaBlend(acento.withOpacity(escuro ? 0.28 : 0.16), fundo),
      onPrimaryContainer: texto,
      secondaryContainer: Color.alphaBlend(acento.withOpacity(escuro ? 0.30 : 0.18), fundo),
      onSecondaryContainer: texto,
      surface: superficie,
      onSurface: texto,
      onSurfaceVariant: textoSuave,
      outline: textoSuave,
      outlineVariant: borda,
      surfaceTint: Colors.transparent,
    );

    final formato = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
    return ThemeData(
      useMaterial3: true,
      colorScheme: esquema,
      scaffoldBackgroundColor: fundo,
      canvasColor: fundo,
      dividerColor: borda,
      dialogBackgroundColor: superficie,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      dividerTheme: DividerThemeData(color: borda, space: 1, thickness: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: fundo,
        foregroundColor: texto,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: fundo,
        surfaceTintColor: Colors.transparent,
        indicatorColor: esquema.secondaryContainer,
        elevation: 0,
        height: 64,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: acento,
        foregroundColor: sobreAcento,
        elevation: 1,
        shape: formato,
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: formato)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: formato)),
      popupMenuTheme: PopupMenuThemeData(color: superficie, surfaceTintColor: Colors.transparent),
      bottomSheetTheme:
          BottomSheetThemeData(backgroundColor: superficie, surfaceTintColor: Colors.transparent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Secretaria IBMMK',
      debugShowCheckedModeBanner: false,
      themeMode: _modo,
      theme: _montarTema(Brightness.light),
      darkTheme: _montarTema(Brightness.dark, preto: _tema == 'preto'),
      home: HomePage(tema: _tema, cor: _cor, onAparencia: _definirAparencia),
    );
  }
}

class HomePage extends StatefulWidget {
  final String tema;
  final Color cor;
  final void Function(String tema, Color cor) onAparencia;

  const HomePage({
    super.key,
    required this.tema,
    required this.cor,
    required this.onAparencia,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  Banco? _banco;
  int _aba = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _carregar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Ao voltar para o app, confere a nuvem.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && Sync.instance.automatico) {
      Sync.instance.sincronizar();
    }
  }

  Future<void> _carregar() async {
    final b = await AppStorage.instance.carregarBanco();
    if (!mounted) return;
    setState(() => _banco = b);
    // Dados vindos da nuvem: redesenha e grava só localmente (sem reenviar).
    Sync.instance.vincular(b, () {
      if (!mounted) return;
      setState(() {});
      AppStorage.instance.salvarBanco(b);
    });
    if (Sync.instance.podeEditar && b.limparPublicacoesExpiradas()) {
      AppStorage.instance.salvarBanco(b);
    }
  }

  /// Atualiza as telas e grava tudo no banco local (e agenda o envio à nuvem).
  void _salvar() {
    setState(() {});
    final b = _banco;
    if (b != null) AppStorage.instance.salvarBanco(b);
    Sync.instance.agendarEnvio();
  }

  /// Tela completa de aniversariantes (aberta a partir do Mural e dos Membros).
  void _abrirAniversarios() {
    final b = _banco;
    if (b == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AniversariosPage(banco: b, onSalvar: _salvar, onAparencia: _aparencia),
      ),
    );
  }

  void _aparencia() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AparenciaPage(
          tema: widget.tema,
          cor: widget.cor,
          aoMudar: widget.onAparencia,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Sync.instance,
      builder: (context, _) {
        final s = Sync.instance;
        if (!s.logado) return const LoginPage();

        final banco = _banco;
        if (banco == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (s.bloqueado) return const BloqueadoPage();

        final mural = MuralPage(
          banco: banco,
          onSalvar: _salvar,
          onAparencia: _aparencia,
          onAbrirAniversarios: _abrirAniversarios,
        );

        // Membro: só o Mural (com agenda e perfil), sem barra inferior.
        if (!s.veTudo) return mural;

        final hojeAniversario = aniversariantesDeHoje(banco).length;

        return Scaffold(
          body: IndexedStack(
            index: _aba,
            children: [
              mural,
              MembrosPage(
                banco: banco,
                onSalvar: _salvar,
                onAparencia: _aparencia,
                onVerAniversarios: _abrirAniversarios,
              ),
              ListasPage(banco: banco, onSalvar: _salvar, onAparencia: _aparencia),
              AtasPage(banco: banco, onSalvar: _salvar, onAparencia: _aparencia),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _aba,
            onDestinationSelected: (i) => setState(() => _aba = i),
            destinations: [
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: hojeAniversario > 0,
                  label: Text('$hojeAniversario'),
                  child: const Icon(Icons.dashboard_outlined),
                ),
                selectedIcon: const Icon(Icons.dashboard),
                label: 'Mural',
              ),
              const NavigationDestination(
                icon: Icon(Icons.groups_outlined),
                selectedIcon: Icon(Icons.groups),
                label: 'Membros',
              ),
              const NavigationDestination(
                icon: Icon(Icons.description_outlined),
                selectedIcon: Icon(Icons.description),
                label: 'Listas',
              ),
              const NavigationDestination(
                icon: Icon(Icons.event_note_outlined),
                selectedIcon: Icon(Icons.event_note),
                label: 'Atas',
              ),
            ],
          ),
        );
      },
    );
  }
}
