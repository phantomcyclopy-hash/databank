import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Pede confirmação antes de uma ação irreversível.
Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  required String mensagem,
  String acao = 'Excluir',
  bool destrutivo = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Text(mensagem),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(
          style: destrutivo ? FilledButton.styleFrom(backgroundColor: Colors.red) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(acao),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Mostra o JSON exportado com botão de copiar (evita renderizar textos enormes).
Future<void> mostrarExportacao(BuildContext context, String titulo, String json) {
  final previa = json.length > 1500 ? '${json.substring(0, 1500)}…' : json;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${(json.length / 1024).toStringAsFixed(0)} KB. Toque em "Copiar" e cole onde quiser guardar (ex.: arquivo .json).',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            Text(previa, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
        FilledButton.icon(
          icon: const Icon(Icons.copy),
          label: const Text('Copiar'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: json));
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('JSON copiado.')));
            }
          },
        ),
      ],
    ),
  );
}
