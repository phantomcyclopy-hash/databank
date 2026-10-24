import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';

/// Campo de data em dia / mês / ano (sem calendário: mais rápido para datas
/// antigas, como nascimento, e não depende de localização do sistema).
/// Chama [onChanged] com a data (UTC, sem hora) ou null se vazia/inválida.
class SeletorData extends StatefulWidget {
  final String rotulo;
  final DateTime? inicial;
  final ValueChanged<DateTime?> onChanged;

  const SeletorData({
    super.key,
    required this.rotulo,
    required this.inicial,
    required this.onChanged,
  });

  @override
  State<SeletorData> createState() => _SeletorDataState();
}

class _SeletorDataState extends State<SeletorData> {
  late final TextEditingController _dia;
  late final TextEditingController _ano;
  int? _mes;
  bool _invalida = false;

  @override
  void initState() {
    super.initState();
    final d = widget.inicial;
    _dia = TextEditingController(text: d == null ? '' : '${d.day}');
    _ano = TextEditingController(text: d == null ? '' : '${d.year}');
    _mes = d?.month;
  }

  @override
  void dispose() {
    _dia.dispose();
    _ano.dispose();
    super.dispose();
  }

  void _mudou() {
    final dia = int.tryParse(_dia.text.trim());
    final ano = int.tryParse(_ano.text.trim());
    final vazio = _dia.text.trim().isEmpty && _ano.text.trim().isEmpty && _mes == null;

    DateTime? data;
    if (dia != null && ano != null && _mes != null && _ano.text.trim().length == 4) {
      data = parseNascimento('$ano-$_mes-$dia');
    }
    setState(() => _invalida = !vazio && data == null);
    widget.onChanged(data);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(widget.rotulo,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 62,
              child: TextField(
                controller: _dia,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                decoration: const InputDecoration(labelText: 'Dia', isDense: true),
                onChanged: (_) => _mudou(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _mes,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Mês', isDense: true),
                items: [
                  for (var i = 0; i < 12; i++)
                    DropdownMenuItem(value: i + 1, child: Text(kMeses[i])),
                ],
                onChanged: (v) {
                  _mes = v;
                  _mudou();
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 76,
              child: TextField(
                controller: _ano,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: const InputDecoration(labelText: 'Ano', isDense: true),
                onChanged: (_) => _mudou(),
              ),
            ),
            IconButton(
              tooltip: 'Limpar data',
              icon: const Icon(Icons.clear, size: 20),
              onPressed: () {
                _dia.clear();
                _ano.clear();
                _mes = null;
                _mudou();
              },
            ),
          ],
        ),
        if (_invalida)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text('Data inválida', style: TextStyle(fontSize: 12, color: Colors.red)),
          ),
      ],
    );
  }
}

/// Campo de hora em HH : MM. [onChanged] recebe os minutos desde 00:00.
class SeletorHora extends StatefulWidget {
  final String rotulo;
  final int minutos;
  final ValueChanged<int> onChanged;

  const SeletorHora({
    super.key,
    required this.rotulo,
    required this.minutos,
    required this.onChanged,
  });

  @override
  State<SeletorHora> createState() => _SeletorHoraState();
}

class _SeletorHoraState extends State<SeletorHora> {
  late final TextEditingController _h;
  late final TextEditingController _m;
  bool _invalida = false;

  @override
  void initState() {
    super.initState();
    _h = TextEditingController(text: (widget.minutos ~/ 60).toString().padLeft(2, '0'));
    _m = TextEditingController(text: (widget.minutos % 60).toString().padLeft(2, '0'));
  }

  @override
  void dispose() {
    _h.dispose();
    _m.dispose();
    super.dispose();
  }

  void _mudou() {
    final h = int.tryParse(_h.text.trim());
    final m = int.tryParse(_m.text.trim());
    final ok = h != null && m != null && h >= 0 && h <= 23 && m >= 0 && m <= 59;
    setState(() => _invalida = !ok);
    if (ok) widget.onChanged(h * 60 + m);
  }

  Widget _campo(TextEditingController c, String rotulo) => SizedBox(
        width: 64,
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
          ],
          decoration: InputDecoration(labelText: rotulo, isDense: true),
          onChanged: (_) => _mudou(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(widget.rotulo,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        Row(
          children: [
            _campo(_h, 'Hora'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(':', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            _campo(_m, 'Min'),
          ],
        ),
        if (_invalida)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text('Hora inválida (00:00 a 23:59)',
                style: TextStyle(fontSize: 12, color: Colors.red)),
          ),
      ],
    );
  }
}

/// "35 anos" calculado a partir de [nasc].
String idadeTexto(DateTime nasc) {
  final hoje = DateTime.now();
  var a = hoje.year - nasc.year;
  if (hoje.month < nasc.month || (hoje.month == nasc.month && hoje.day < nasc.day)) a--;
  return a < 0 ? '-' : '$a anos';
}
