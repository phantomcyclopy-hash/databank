import 'dart:math';

import 'package:flutter/material.dart';

import '../models.dart';

const List<Color> _coresRapidas = [
  Color(0xFF8B6CEF),
  Color(0xFF1E88E5),
  Color(0xFF00ACC1),
  Color(0xFF43A047),
  Color(0xFFFDD835),
  Color(0xFFFB8C00),
  Color(0xFFE53935),
  Color(0xFFD81B60),
  Color(0xFF6D4C41),
  Color(0xFF546E7A),
  Color(0xFF1B2A4A),
];

/// Roda de cores: o matiz gira em volta (vermelho no topo, no sentido horário)
/// e a saturação aumenta do centro (branco) para a borda.
class RodaDeCores extends StatelessWidget {
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  final double tamanho;

  const RodaDeCores({
    super.key,
    required this.hsv,
    required this.onChanged,
    this.tamanho = 260,
  });

  void _toque(Offset local) {
    final centro = Offset(tamanho / 2, tamanho / 2);
    final d = local - centro;
    final raio = tamanho / 2;
    final sat = (d.distance / raio).clamp(0.0, 1.0).toDouble();
    var graus = atan2(d.dx, -d.dy) * 180 / pi; // 0 = topo, horário
    if (graus < 0) graus += 360;
    onChanged(hsv.withHue(graus).withSaturation(sat));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: tamanho,
      height: tamanho,
      child: GestureDetector(
        onPanDown: (d) => _toque(d.localPosition),
        onPanUpdate: (d) => _toque(d.localPosition),
        child: CustomPaint(painter: _RodaPainter(hsv)),
      ),
    );
  }
}

class _RodaPainter extends CustomPainter {
  final HSVColor hsv;
  _RodaPainter(this.hsv);

  @override
  void paint(Canvas canvas, Size size) {
    final centro = size.center(Offset.zero);
    final raio = size.width / 2;
    final rect = Rect.fromCircle(center: centro, radius: raio);

    // matiz (começa no topo)
    final matizes = [
      for (final h in [0.0, 60.0, 120.0, 180.0, 240.0, 300.0, 360.0])
        HSVColor.fromAHSV(1, h, 1, 1).toColor()
    ];
    canvas.drawCircle(
      centro,
      raio,
      Paint()
        ..shader = SweepGradient(colors: matizes, transform: const GradientRotation(-pi / 2))
            .createShader(rect),
    );
    // saturação: branco no centro
    canvas.drawCircle(
      centro,
      raio,
      Paint()
        ..shader = RadialGradient(colors: [Colors.white, Colors.white.withOpacity(0)])
            .createShader(rect),
    );
    // brilho
    if (hsv.value < 1) {
      canvas.drawCircle(centro, raio, Paint()..color = Colors.black.withOpacity(1 - hsv.value));
    }

    // marcador
    final ang = hsv.hue * pi / 180;
    final r = hsv.saturation * raio;
    final p = centro + Offset(sin(ang) * r, -cos(ang) * r);
    canvas.drawCircle(p, 12, Paint()..color = Colors.black.withOpacity(0.35));
    canvas.drawCircle(p, 11, Paint()..color = hsv.toColor());
    canvas.drawCircle(
      p,
      11,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _RodaPainter old) => old.hsv != hsv;
}

/// Abre o seletor de cor com a roda de cores (matiz e saturação), o controle de
/// brilho, o código hexadecimal e cores rápidas. Null se cancelado.
Future<Color?> escolherCor(BuildContext context, Color atual,
    {String titulo = 'Escolher cor'}) {
  var hsv = HSVColor.fromColor(atual);
  final hexCtrl = TextEditingController(text: hexDeCor(atual));
  final lado = min(260.0, MediaQuery.of(context).size.width - 120).clamp(180.0, 260.0).toDouble();

  return showDialog<Color>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        void definir(HSVColor n) => setS(() {
              hsv = n;
              hexCtrl.text = hexDeCor(n.toColor());
            });

        return AlertDialog(
          title: Text(titulo),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: RodaDeCores(hsv: hsv, tamanho: lado, onChanged: definir)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.brightness_low, size: 18),
                    Expanded(
                      child: Slider(
                        value: hsv.value,
                        onChanged: (v) => definir(hsv.withValue(v)),
                      ),
                    ),
                    const Icon(Icons.brightness_high, size: 18),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: hsv.toColor(),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade500),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: hexCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Código hexadecimal',
                          hintText: '#8B6CEF',
                          isDense: true,
                        ),
                        onChanged: (v) {
                          if (v.replaceAll('#', '').length == 6) {
                            final c = corDeHex(v, padrao: hsv.toColor());
                            setS(() => hsv = HSVColor.fromColor(c));
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _coresRapidas
                      .map((c) => GestureDetector(
                            onTap: () => definir(HSVColor.fromColor(c)),
                            child: CircleAvatar(backgroundColor: c, radius: 15),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, hsv.toColor()),
              child: const Text('Selecionar'),
            ),
          ],
        );
      },
    ),
  );
}

/// Cor de texto legível sobre [fundo].
Color corTextoSobre(Color fundo) =>
    ThemeData.estimateBrightnessForColor(fundo) == Brightness.dark
        ? Colors.white
        : Colors.black87;
