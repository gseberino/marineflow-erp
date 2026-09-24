# Fila noturna — serviço designado da Parte 1

Lida pelo `/modo-noturno` no início do turno. **Editar este arquivo é como a fila evolui** — o comando não
muda. Item concluído: mover para "Concluídos" com o commit; item que não reproduz mais: mover para "Não
reproduzem" com a data da verificação.

Regra que vale para todos: **re-verificar que o defeito ainda reproduz antes de corrigir.** Com várias
frentes ativas, achado envelhece — o MF-AUD-030 já chegou morto na fila uma vez.

Cada item vira **um commit**, com testes cobrindo o caso e as bordas, e os quatro gates verdes.

---

> ## ✅ A fila está VAZIA desde 24/09/2026
>
> Os sete itens que estavam aqui como "em aberto" já estavam corrigidos na `main` — a lista é que não tinha
> sido atualizada. Conferidos um a um em 24/09/2026, lendo o código de produção (não o histórico de commits,
> que não prova qual versão está no ar). Detalhes em "Não reproduzem mais", abaixo.
>
> **Antes de escrever um item novo aqui, leia isto:** foi exatamente esta lista desatualizada que quase fez
> uma sessão refazer sete correções prontas. Um achado que envelhece nesta fila custa mais caro que um achado
> não registrado, porque parece trabalho pendente. Se você registrar algo, registre **como verificar que ainda
> reproduz** — não só onde dói.

## Em aberto, nesta ordem

_(vazia)_

---

## Como reabastecer a fila

Duas fontes valem mais que auditoria nova, porque falam do que o dono usa de verdade:

1. **`app_error_logs`** — o que a produção registrou, com data e quantas vezes. Foi de lá que saíram os dois
   defeitos corrigidos em 24/09 (`ac0b8ee`): o PDF que falhava com a aba aberta durante uma publicação, e as
   seis ações de auditoria que o CHECK recusava em silêncio.
   ```sql
   select to_char(last_seen_at,'DD/MM HH24:MI') as visto, occurrences, source, context, action, message
   from app_error_logs where resolved_at is null and last_seen_at > now() - interval '21 days'
   order by last_seen_at desc;
   ```
2. **`audit/novos-achados.md`** — os achados das varreduras, com o estado de cada um anotado no próprio item.
   Vários já estão marcados como resolvidos ali; **confira no código antes de trazer para cá.**

---

## Concluídos

### 6. NOVO-018 — captura rápida perde o "3" · `feat/agenda-retomada` (28/08/2026)
Hora passou a exigir marcador (`h`, `:`, "às"/"as"), então número solto continua sendo quantidade e fica no
título; data inexistente (30/02, 31/11, e 29/02 em ano não bissexto) é recusada em vez de virar outro dia.
Também deixou de aceitar minuto acima de 59, que produzia `14:75` e estourava como *Invalid Date* na
`AgendaPage`. O bloco `[NOVO-018]` do teste foi invertido — era caracterização do defeito, agora fixa o
comportamento certo — mais 3 bordas novas. 19 testes verdes; os 15 casos legítimos passaram sem alteração.
`src/lib/quick-task-parser.ts`

## Não reproduzem mais

Todos verificados em **24/09/2026**, lendo o código que está na `main`. Cada linha diz **onde** a correção
está hoje — é o que permite conferir de novo sem repetir a investigação inteira.

| Item | Como foi verificado | Onde está a correção |
|---|---|---|
| **1 · NOVO-017** — CSV corrompe dinheiro; "Telefone" vazio apaga o celular | `parseNumeroPlanilha` documenta a regra de separador decimal e tem teste para "1.234,56", "1,234.56" e "1.500"; o caso Celular/Telefone tem teste nos dois sentidos de ordem das colunas | `src/lib/import-detector.ts` · `src/lib/import-detector.test.ts:150-280` |
| **2 · NOVO-024** — 4 técnicos custam o mesmo que 1 | `hourlyRateFor` deriva o passo das faixas configuradas e o teto vem das chaves da tabela, não de um `3` fixo | `src/lib/displacement.ts:63-85` |
| **3 · NOVO-009** — preço explode quando margem+imposto+comissão = 100% | teste `[NOVO-009]` cobre 99%, 100% e 101%, e exige erro claro em vez de número absurdo | `src/lib/price-calculator.test.ts:85-128` |
| **4 · NOVO-022** — toggles que mentem na via de execução | o diálogo desabilita só o que `isFinancialOption(key)` diz ser financeiro | `src/components/PDFOptionsDialog.tsx:142` · `src/lib/pdf-visibility.test.ts:105` |
| **5 · NOVO-019** — CSV: "Marina" repete o barco, aspas, injeção de fórmula | a coluna Marina lê `marinas.name`; célula iniciada por `=`, `@`, `+`/`-` não numérico recebe apóstrofo; aspas ganham envelope | `src/lib/export-utils.ts:19-31,90` |
| **7 · NOVO-023** — guarda do hash lê a migration pelo nome | varre todas as migrations que definem o trigger e usa a **mais recente** | `src/lib/document-hash.test.ts:145-160` |
| **8 · NOVO-021** — edição durante o "Salvar" em voo se perde | o `ref` enxerga o rascunho atual e só as chaves enviadas saem de `dirty` | `src/pages/settings/PdfDefaultsSection.tsx:37,67` |
