import 'models.dart';

const List<String> kDiasSemana = [
  'Segunda-feira', 'Terça-feira', 'Quarta-feira', 'Quinta-feira',
  'Sexta-feira', 'Sábado', 'Domingo',
];

/// "Sexta-feira, 23 de outubro de 2026"
String dataPorExtenso(DateTime d) =>
    '${kDiasSemana[d.weekday - 1]}, ${d.day} de ${kMeses[d.month - 1].toLowerCase()} de ${d.year}';

DateTime soData(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Domingo de Páscoa (algoritmo de Meeus/Jones/Butcher).
DateTime pascoa(int ano) {
  final a = ano % 19;
  final b = ano ~/ 100;
  final c = ano % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final mes = (h + l - 7 * m + 114) ~/ 31;
  final dia = ((h + l - 7 * m + 114) % 31) + 1;
  return DateTime.utc(ano, mes, dia);
}

DateTime _enesimoDomingo(int ano, int mes, int n) {
  var d = DateTime.utc(ano, mes, 1);
  while (d.weekday != DateTime.sunday) {
    d = d.add(const Duration(days: 1));
  }
  return d.add(Duration(days: 7 * (n - 1)));
}

class DataComemorativa {
  final DateTime data; // UTC, sem hora
  final String nome;
  final bool daIgreja;
  const DataComemorativa(this.data, this.nome, {this.daIgreja = false});
}

/// Datas comemorativas nacionais (as móveis são calculadas pela Páscoa).
List<DataComemorativa> datasNacionais(int ano) {
  final p = pascoa(ano);
  DateTime d(int m, int dia) => DateTime.utc(ano, m, dia);
  return [
    DataComemorativa(d(1, 1), 'Ano Novo'),
    DataComemorativa(p.subtract(const Duration(days: 2)), 'Sexta-feira Santa'),
    DataComemorativa(p, 'Páscoa'),
    DataComemorativa(d(4, 21), 'Tiradentes'),
    DataComemorativa(d(5, 1), 'Dia do Trabalho'),
    DataComemorativa(_enesimoDomingo(ano, 5, 2), 'Dia das Mães'),
    DataComemorativa(_enesimoDomingo(ano, 8, 2), 'Dia dos Pais'),
    DataComemorativa(d(9, 7), 'Independência do Brasil'),
    DataComemorativa(d(10, 12), 'Dia das Crianças'),
    DataComemorativa(d(10, 12), 'Nossa Senhora Aparecida'),
    DataComemorativa(d(10, 31), 'Dia da Reforma Protestante'),
    DataComemorativa(d(11, 2), 'Finados'),
    DataComemorativa(d(11, 15), 'Proclamação da República'),
    DataComemorativa(_enesimoDomingo(ano, 12, 2), 'Dia da Bíblia'),
    DataComemorativa(d(12, 25), 'Natal'),
  ];
}

/// Nacionais + as cadastradas pela igreja, para o ano pedido.
List<DataComemorativa> datasDoAno(Banco banco, int ano) {
  return [
    ...datasNacionais(ano),
    for (final c in banco.datasIgreja)
      if (c.ano == 0 || c.ano == ano)
        if (c.dia >= 1 && c.dia <= 31 && c.mes >= 1 && c.mes <= 12)
          DataComemorativa(DateTime.utc(ano, c.mes, c.dia), c.titulo, daIgreja: true),
  ];
}

List<DataComemorativa> comemorativasNoDia(Banco banco, DateTime dia) {
  final d = soData(dia);
  return datasDoAno(banco, d.year).where((c) => c.data == d).toList();
}

/// Próximas datas (a partir de hoje) dentro de [dias] dias, em ordem.
List<DataComemorativa> proximasComemorativas(Banco banco, DateTime hoje, int dias) {
  final h = soData(hoje);
  final limite = h.add(Duration(days: dias));
  final todas = [...datasDoAno(banco, h.year), ...datasDoAno(banco, h.year + 1)];
  final r = todas.where((c) => !c.data.isBefore(h) && !c.data.isAfter(limite)).toList();
  r.sort((a, b) => a.data.compareTo(b.data));
  return r;
}
