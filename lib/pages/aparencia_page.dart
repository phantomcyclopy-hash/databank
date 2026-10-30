import 'package:flutter/material.dart';

import '../models.dart';
import '../widgets/seletor_cor.dart';

/// Modo (automático, claro, escuro, preto absoluto) e cor de destaque do app.
/// As mudanças valem na hora e ficam salvas.
class AparenciaPage extends StatefulWidget {
  final String tema;
  final Color cor;
  final void Function(String tema, Color cor) aoMudar;

  const AparenciaPage({
    super.key,
    required this.tema,
    required this.cor,
    required this.aoMudar,
  });

  @override
  State<AparenciaPage> createState() => _AparenciaPageState();
}

class _AparenciaPageState extends State<AparenciaPage> {
  late String _tema = widget.tema;
  late Color _cor = widget.cor;

  static const _modos = [
    ['system', 'Automático', 'Segue o modo do aparelho'],
    ['light', 'Claro', 'Fundo branco'],
    ['dark', 'Escuro', 'Cinza escuro'],
    ['preto', 'Preto absoluto', 'Fundo totalmente preto (economiza bateria em telas OLED)'],
  ];

  void _aplicar({String? tema, Color? cor}) {
    setState(() {
      if (tema != null) _tema = tema;
      if (cor != null) _cor = cor;
    });
    widget.aoMudar(_tema, _cor);
  }

  Future<void> _escolher() async {
    final nova = await escolherCor(context, _cor, titulo: 'Cor do app');
    if (nova != null) _aplicar(cor: nova);
  }

  @override
  Widget build(BuildContext context) {
    final e = Theme.of(context).colorScheme;

    Widget cartao(String titulo, List<Widget> filhos) => Card(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: e.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                ...filhos,
              ],
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Aparência')),
      body: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 32),
        children: [
          cartao('Modo', [
            for (final m in _modos)
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: m[0],
                groupValue: _tema,
                title: Text(m[1]),
                subtitle: Text(m[2], style: const TextStyle(fontSize: 12)),
                onChanged: (v) {
                  if (v != null) _aplicar(tema: v);
                },
              ),
          ]),
          cartao('Cor do app', [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(backgroundColor: _cor, radius: 18),
              title: const Text('Cor de destaque'),
              subtitle: Text('${hexDeCor(_cor)} · botões, seleções e realces'),
              trailing: const Icon(Icons.palette_outlined),
              onTap: _escolher,
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.restore),
                label: const Text('Restaurar cor padrão'),
                onPressed: () => _aplicar(cor: kCorAppPadrao),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
