import 'package:flutter/material.dart';

import '../models.dart';

const List<Color> _coresRapidas = [
  Color(0xFF1B2A4A),
  Color(0xFF1E88E5),
  Color(0xFF43A047),
  Color(0xFFFB8C00),
  Color(0xFFFDD835),
  Color(0xFFE53935),
  Color(0xFFD81B60),
  Color(0xFF8E24AA),
  Color(0xFF00ACC1),
  Color(0xFF6D4C41),
  Color(0xFF546E7A),
];

/// Abre um seletor de cor (paleta rápida + código hexadecimal).
/// Retorna a cor escolhida ou null se cancelado.
Future<Color?> escolherCor(BuildContext context, Color atual,
    {String titulo = 'Escolher cor'}) {
  Color temp = atual;
  final hexCtrl = TextEditingController(text: hexDeCor(atual));

  return showDialog<Color>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setPicker) => AlertDialog(
        title: Text(titulo),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  color: temp,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade400),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: hexCtrl,
                decoration: const InputDecoration(
                  labelText: 'Código hexadecimal',
                  hintText: '#FF0000',
                  prefixIcon: Icon(Icons.color_lens),
                ),
                onChanged: (v) {
                  if (v.length == 7 || v.length == 9) {
                    setPicker(() => temp = corDeHex(v, padrao: temp));
                  }
                },
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _coresRapidas.map((c) {
                  return GestureDetector(
                    onTap: () => setPicker(() {
                      temp = c;
                      hexCtrl.text = hexDeCor(c);
                    }),
                    child: CircleAvatar(
                      backgroundColor: c,
                      radius: 18,
                      child: temp.value == c.value
                          ? const Icon(Icons.check, color: Colors.white, size: 18)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, temp),
              child: const Text('Selecionar')),
        ],
      ),
    ),
  );
}

/// Cor de texto legível sobre [fundo].
Color corTextoSobre(Color fundo) =>
    ThemeData.estimateBrightnessForColor(fundo) == Brightness.dark
        ? Colors.white
        : Colors.black87;
