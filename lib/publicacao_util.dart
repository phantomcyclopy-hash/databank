import 'calendario.dart';
import 'models.dart';

String _horaTxt(int min) =>
    '${(min ~/ 60).toString().padLeft(2, '0')}:${(min % 60).toString().padLeft(2, '0')}';

/// Texto simples de uma lista, para publicar no Mural.
String textoDaLista(Banco b, ListaEntidades l) {
  final membros = b.membrosDaLista(l);
  final s = StringBuffer();
  final d = parseNascimento(l.dataEvento);
  if (d != null || l.horaEvento >= 0) {
    s.writeln('${d == null ? '' : dataPorExtenso(d)}${l.horaEvento >= 0 ? ' às ${_horaTxt(l.horaEvento)}' : ''}');
  }
  s.writeln('${membros.length} membro(s)');
  s.writeln();
  for (var i = 0; i < membros.length; i++) {
    final cong = b.congregacaoPorId(membros[i].congregacaoId);
    s.writeln('${i + 1}. ${membros[i].nome}${cong == null ? '' : ' (${cong.nome})'}');
  }
  return s.toString().trim();
}

/// Texto simples de uma ata, para publicar no Mural.
String textoDaAta(Banco b, Ata a) {
  final s = StringBuffer();
  final d = parseNascimento(a.data);
  if (d != null || a.hora >= 0) {
    s.writeln('${d == null ? '' : dataPorExtenso(d)}${a.hora >= 0 ? ' às ${_horaTxt(a.hora)}' : ''}');
    s.writeln();
  }

  if (a.incluirMovimentos) {
    final mv = b.movimentosDaAta(a);
    final entradas = mv.where((m) => m.tipo == 'entrada').toList();
    final saidas = mv.where((m) => m.tipo == 'saida').toList();
    if (mv.isNotEmpty) {
      s.writeln('MOVIMENTO DE MEMBROS');
      if (entradas.isNotEmpty) {
        s.writeln('Entradas (${entradas.length}):');
        for (final m in entradas) {
          s.writeln('- ${m.nome}${m.motivo.isEmpty ? '' : ' (${m.motivo})'}');
        }
      }
      if (saidas.isNotEmpty) {
        s.writeln('Saídas (${saidas.length}):');
        for (final m in saidas) {
          s.writeln('- ${m.nome}${m.motivo.isEmpty ? '' : ' (${m.motivo})'}');
        }
      }
      s.writeln();
    }
  }

  if (a.registros.isNotEmpty) {
    for (final cat in kCategoriasRegistro.keys) {
      final l = a.registros.where((r) => r.categoria == cat).toList()
        ..sort((x, y) => x.data.compareTo(y.data));
      if (l.isEmpty) continue;
      s.writeln(kCategoriasRegistro[cat]!.toUpperCase());
      for (final r in l) {
        final dt = parseNascimento(r.data);
        s.writeln('- ${dt == null ? '' : '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}: '}${r.texto}');
      }
      s.writeln();
    }
  }

  if (a.texto.trim().isNotEmpty) {
    for (final linha in a.texto.split('\n')) {
      var t = linha.replaceAll('**', '');
      if (t.startsWith('## ')) t = t.substring(3);
      if (t.startsWith('# ')) t = t.substring(2);
      s.writeln(t);
    }
  }
  final r = s.toString().trim();
  return r.isEmpty ? 'Ata sem conteúdo.' : r;
}
