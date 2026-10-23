import 'package:flutter/material.dart';

import 'models.dart';
import 'pages/aniversarios_page.dart';
import 'pages/listas_page.dart';
import 'pages/mural_page.dart';
import 'pages/membros_page.dart';
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
  runApp(const IBMMKARApp());
}

class IBMMKARApp extends StatefulWidget {
  const IBMMKARApp({super.key});

  @override
  State<IBMMKARApp> createState() => _IBMMKARAppState();
}

class _IBMMKARAppState extends State<IBMMKARApp> {
  // 'system' (automático), 'light' ou 'dark'; lembrado entre aberturas.
  String _tema = AppStorage.instance.tema;

  ThemeMode get _modo {
    switch (_tema) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  void _definirTema(String t) {
    setState(() => _tema = t);
    AppStorage.instance.salvarTema(t);
  }

  ThemeData _montarTema(Brightness brilho) {
    final esquema = ColorScheme.fromSeed(seedColor: kCorPadrao, brightness: brilho);
    final formato = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
    return ThemeData(
      useMaterial3: true,
      colorScheme: esquema,
      scaffoldBackgroundColor: brilho == Brightness.light ? const Color(0xFFF4F5F7) : null,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: kCorPadrao,
        foregroundColor: Colors.white,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(shape: formato),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: formato)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: formato)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IBMMKAR',
      debugShowCheckedModeBanner: false,
      themeMode: _modo,
      theme: _montarTema(Brightness.light),
      darkTheme: _montarTema(Brightness.dark),
      home: HomePage(tema: _tema, onTema: _definirTema),
    );
  }
}

class HomePage extends StatefulWidget {
  final String tema;
  final ValueChanged<String> onTema;

  const HomePage({super.key, required this.tema, required this.onTema});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Banco? _banco;
  int _aba = 0;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final b = await AppStorage.instance.carregarBanco();
    if (!mounted) return;
    setState(() => _banco = b);
  }

  /// Atualiza as telas e grava tudo no banco local.
  void _salvar() {
    setState(() {});
    final b = _banco;
    if (b != null) AppStorage.instance.salvarBanco(b);
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
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aparência'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final op in const [
              ['system', 'Automática', 'Segue o modo do aparelho'],
              ['light', 'Clara', ''],
              ['dark', 'Escura', ''],
            ])
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: op[0],
                groupValue: widget.tema,
                title: Text(op[1]),
                subtitle: op[2].isEmpty ? null : Text(op[2]),
                onChanged: (v) {
                  if (v != null) widget.onTema(v);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final banco = _banco;
    if (banco == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final hojeAniversario = aniversariantesDeHoje(banco).length;

    return Scaffold(
      body: IndexedStack(
        index: _aba,
        children: [
          MuralPage(
            banco: banco,
            onSalvar: _salvar,
            onAparencia: _aparencia,
            onAbrirAniversarios: _abrirAniversarios,
          ),
          MembrosPage(
            banco: banco,
            onSalvar: _salvar,
            onAparencia: _aparencia,
            onVerAniversarios: _abrirAniversarios,
          ),
          ListasPage(banco: banco, onSalvar: _salvar, onAparencia: _aparencia),
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
        ],
      ),
    );
  }
}
