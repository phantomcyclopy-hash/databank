# Banco Dinâmico — Plano de Ação

## Decisões de arquitetura

| Tema | Escolha | Por quê |
|---|---|---|
| Banco local | **Sembast** (NoSQL, Dart puro) | Roda em Android, iOS, Windows, macOS e Linux sem código nativo nem geração de código; armazena Maps/JSON, o que encaixa perfeitamente em atributos dinâmicos. |
| Alternativas | Drift (SQLite) | Melhor se surgirem consultas relacionais pesadas ou centenas de milhares de registros. Troca isolada na interface `EntidadeRepository`. Isar original está sem manutenção ativa (existe fork comunitário); Hive idem menos recomendado para projeto novo. |
| Atributos dinâmicos | Lista de `AtributoDinamico` com `id` próprio | Adicionar/remover/renomear sem migração; leitura tolerante a campos ausentes e ao formato legado (Map). |
| Presenças | Coleção separada, 1 registro por marcação | Histórico grande não infla o documento da entidade; cada registro sincroniza individualmente. |
| Visibilidade | Campo `isVisible` | Ocultar nunca apaga; a UI filtra. |
| Datas | `timestamp` em ms UTC; dia/mês/hora/minuto derivados | Uma única fonte da verdade, sem inconsistência. |
| Sync-ready | UUID v4, `atualizadoEm`, `excluidoEm` (tombstone), `schemaVersion` | Base para merge "last-write-wins" por registro. |

## Fases

### Fase 1 — Estrutura de dados
1. `flutter create . --platforms=android,ios,windows,macos,linux`
2. Copiar `pubspec.yaml` e `lib/`; rodar `flutter pub get`.
3. Escrever testes unitários de `models.dart`: round-trip `toMap/fromMap` e `toJson/fromJson`; leitura de Map legado; tipo desconhecido vira `texto`/`outro`.

### Fase 2 — Banco local
1. `SembastEntidadeRepository.abrir()` no `main`.
2. Testar o repositório com `newDatabaseFactoryMemory()` do Sembast (sem disco).
3. Cobrir: adicionar entidade, upsert/remover atributo, registrar presença, alternar visibilidade (registro continua existindo), exclusão lógica.
4. Medir com 10 mil+ presenças; se a leitura por entidade ficar lenta, migrar o repositório para Drift com índice em `entidade_id`.

### Fase 3 — Interface
1. Lista de entidades e detalhe (já no `main.dart`).
2. Próximos passos: busca/filtro por atributo, edição do nome, layout adaptativo (painel lateral em desktop), atalhos de teclado, exportação CSV/JSON.
3. Gerenciamento de estado: se o app crescer, trocar `StreamBuilder` por Riverpod ou BLoC; a interface do repositório já suporta isso.

### Fase 4 — Nuvem
1. Criar `NuvemDataSource` (interface) com duas implementações possíveis: Firestore ou Supabase.
2. Fila local de alterações pendentes (usar `atualizadoEm > ultimaSync`).
3. Estratégia: enviar pendentes, baixar remotas, resolver conflito por `atualizadoEm` (last-write-wins); `excluidoEm` propaga deleções.
4. Atributos: em conflito simultâneo na mesma entidade, mesclar por `id` de atributo em vez de sobrescrever a lista toda.
5. Autenticação e regras de segurança (Firestore Rules ou RLS no Supabase) por usuário.
6. Supabase: tabelas `entidades` (coluna `atributos jsonb`) e `presencas`. Firestore: coleção `entidades` e subcoleção `presencas`.

## Como rodar
```
flutter create . --platforms=android,ios,windows,macos,linux
flutter pub get
flutter run -d <dispositivo>
```
