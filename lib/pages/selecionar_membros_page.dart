import 'package:flutter/material.dart';

import '../models.dart';
import '../widgets/membro_widgets.dart';

/// Escolhe membros já cadastrados (para adicionar a uma lista ou matricular numa
/// classe). Devolve a lista de ids marcados, na ordem em que foram marcados
/// (ou null se cancelado). Os marcados são mantidos ao mudar busca e filtros,
/// então dá para somar grupos (ex.: todas as mulheres da Sede + todos os
/// jovens da Banqueta).
class SelecionarMembrosPage extends StatefulWidget {
  final Banco banco;
  final String titulo;
  final Set<String> jaIncluidos;
  final String acao;
  final String etiquetaJa;
  final Color corPadrao;

  const SelecionarMembrosPage({
    super.key,
    required this.banco,
    required this.titulo,
    required this.jaIncluidos,
    this.acao = 'Adicionar',
    this.etiquetaJa = 'Já está nesta lista',
    this.corPadrao = kCorSemCong,
  });

  @override
  State<SelecionarMembrosPage> createState() => _SelecionarMembrosPageState();
}

class _SelecionarMembrosPageState extends State<SelecionarMembrosPage> {
  final FiltroMembros _filtro = FiltroMembros();
  final TextEditingController _buscaCtrl = TextEditingController();
  final Set<String> _sel = {};

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banco = widget.banco;
    final jaNaLista = widget.jaIncluidos;
    final visiveis = _filtro.aplicar(banco, banco.membros);
    final disponiveis = visiveis.where((m) => !jaNaLista.contains(m.id)).toList();
    final marcados = disponiveis.where((m) => _sel.contains(m.id)).length;
    final todosMarcados = disponiveis.isNotEmpty && marcados == disponiveis.length;
    final esquema = Theme.of(context).colorScheme;
    final corLista = widget.corPadrao;

    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: banco.membros.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Não há membros cadastrados.\nCadastre na área Membros.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                PainelBuscaFiltros(
                  banco: banco,
                  filtro: _filtro,
                  buscaCtrl: _buscaCtrl,
                  origem: banco.membros,
                  onMudou: () => setState(() {}),
                  corPadrao: kCorSemCong,
                ),
                CheckboxListTile(
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  tristate: true,
                  value: todosMarcados ? true : (marcados > 0 ? null : false),
                  title: Text(
                    todosMarcados
                        ? 'Desmarcar todos os exibidos'
                        : 'Selecionar todos os exibidos (${disponiveis.length})',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Já incluídos: ${visiveis.length - disponiveis.length} dos exibidos',
                    style: TextStyle(fontSize: 12, color: esquema.onSurfaceVariant),
                  ),
                  onChanged: disponiveis.isEmpty
                      ? null
                      : (_) => setState(() {
                            final ids = disponiveis.map((m) => m.id);
                            if (todosMarcados) {
                              _sel.removeAll(ids);
                            } else {
                              _sel.addAll(ids);
                            }
                          }),
                ),
                const Divider(height: 1),
                Expanded(
                  child: visiveis.isEmpty
                      ? const Center(child: Text('Nenhum membro encontrado com esses filtros.'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                          itemCount: visiveis.length,
                          itemBuilder: (_, i) {
                            final m = visiveis[i];
                            final ja = jaNaLista.contains(m.id);
                            void alternar() => setState(() {
                                  _sel.contains(m.id) ? _sel.remove(m.id) : _sel.add(m.id);
                                });
                            return MembroCard(
                              banco: banco,
                              membro: m,
                              corPadrao: corLista,
                              etiqueta: ja ? widget.etiquetaJa : null,
                              leading: Checkbox(
                                value: ja || _sel.contains(m.id),
                                onChanged: ja ? null : (_) => alternar(),
                              ),
                              onTap: ja ? null : alternar,
                            );
                          },
                        ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: esquema.surface,
            border: Border(top: BorderSide(color: esquema.outlineVariant)),
          ),
          child: FilledButton.icon(
            icon: const Icon(Icons.group_add),
            label: Text(_sel.isEmpty
                ? 'Selecione os membros'
                : '${widget.acao} ${_sel.length} membro(s)'),
            onPressed: _sel.isEmpty ? null : () => Navigator.pop(context, _sel.toList()),
          ),
        ),
      ),
    );
  }
}
