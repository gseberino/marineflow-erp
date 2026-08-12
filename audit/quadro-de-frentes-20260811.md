# Quadro de frentes — 11/08/2026, após a integração do turno noturno

Estado de cada frente de trabalho paralela neste repositório, medido hoje de manhã. A `main` de referência é
`ac5ce13` (já com o noturno integrado). Gates rodados em worktree temporário próprio — **nenhum worktree de
outra sessão foi tocado**.

---

## ✅ Já integradas na `main`

| Frente | Commit de merge | O que trouxe |
|---|---|---|
| `fix/mf-aud-009-cascata-recebiveis` | `d34bc07` | O agente que altera OS passa a cascatear recebíveis. A aritmética saiu de dentro de `updateReceivableFromSO` e virou módulo puro (`receivable-redistribution.ts`), usado pelos dois caminhos — tela e agente. Antes, mexer na OS pelo agente deixava o título com o valor antigo, e dava para derrubar o total abaixo do que o cliente já pagou |
| `test/mf-aud-020-rls` | `365a2ce` | Os testes de RLS que faltavam: um SQL que roda em transação com `ROLLBACK` (seguro até em produção) e uma guarda estática que roda no CI sem banco. A migration já estava aplicada desde 10/08 |
| `feat/reorganizacao-financeiro` | (anterior) | F3 — Cartões vira tela própria. Worktree `marineflow-erp--financeiro-ia` está **limpo**, sem trabalho pendente |
| `session/noturno` | `ac5ce13` (ff-only) | Este turno: 15 commits — lint fora do CI, padrão de PDF em Settings, via de execução, paridade i18n, 8 módulos cobertos por teste |

---

## ⏳ Pendentes de integração

### `feat/nfse-nacional` — 9 commits · **a mais volumosa e a que mais exige atenção**

**Conteúdo:** a frente de NFS-e inteira. Pré-voo obrigatório antes de emitir, builder com as quatro rejeições
mapeadas em português, emissão a partir dos **serviços** da OS, seção de NFS-e na tela fiscal, cadastro fiscal
por **verbo** (com herança) e `iss_withheld` herdando do verbo.

**Gates (medidos hoje):** `typecheck` **0 erros** · `vitest` **954 passam**.
⚠️ Na **primeira** execução deram 3 falhas — `hooks-antes-do-return` e `postgrest-select-columns` (2 casos).
Na segunda, mesmos arquivos, **954/954**. Ver a nota sobre o `NOVO-016` no fim: os nomes que faltavam àquele
achado são estes.

**Colisão com a `main` nova:**
- `audit/novos-achados.md` → **conflito real** (os dois lados acrescentaram achados no fim). A resolução é
  manter os dois blocos; os IDs **não** colidem mais — os meus foram renumerados para 017-024.
- `src/pages/SettingsPage.tsx` → auto-merge limpo, mas **os dois lados mexeram no arquivo**: eles
  acrescentaram cadastro fiscal, eu acrescentei a seção "Padrão dos PDFs". Vale abrir a tela depois do merge —
  auto-merge sem conflito não é garantia de que as duas seções convivem bem no layout.

**⚠️ O banco está À FRENTE deste branch:** a migration `nfse_cadastro_fiscal_de_servicos` **já foi aplicada em
produção** (versão `20260811014317`), mas o código que a usa **não está na `main`**. A segunda migration do
branch (`20260811003000_nfse_verbos_fiscais_com_heranca`) **não** foi aplicada. Ou seja: hoje existe em
produção uma tabela que o repositório na `main` não conhece.

**Espera:** os códigos de serviço da contabilidade (as dez linhas de verbo nascem vazias de propósito) e a
decisão sobre emitir NFS-e pelo Emissor Nacional. O `NOVO-014` (retenção de ISS) foi respondido no último
commit da frente.

---

### `feat/f2-ui-financeiro` — 1 commit

**Conteúdo:** Extrato e Conciliação deixam de ser abas da mesma tela e viram **rotas separadas**
(`/v2/financial/extrato` e `/v2/financial/conciliacao`), com as duas filas antigas fundidas numa só e o
fechamento de período movido para dentro da conciliação.

**Gates (medidos hoje):** `typecheck` **0 erros** · `vitest` **919 passam**, já na primeira execução.

**Colisão com a `main` nova:** só `audit/novos-achados.md` (mesmo caso de append). Nenhum arquivo de código em
comum com o noturno.

**Espera:** revisão de uso — é mudança de navegação, o tipo de coisa que só o dono valida. Traz o `NOVO-015`
(aba "Sugeridas" da Conciliação sem motor por trás) como achado próprio.

---

### `docs/turno-noite-20260810` — 1 commit

**Conteúdo:** o diário do outro turno da noite. Só `.md`. Registra que duas das seis tarefas daquela fila já
estavam feitas, que o `gh` não está autenticado nesta máquina (nenhum PR foi aberto por isso) e três achados
sobre dinheiro/imposto.

**Gates:** não se aplica — nenhum arquivo de código.

**Colisão com a `main` nova:** **merge limpo**, sem conflito.

**Espera:** nada. Pode entrar quando quiser.

---

## Sessão da posição 3 (CashForecast / financeiro)

O worktree `marineflow-erp--financeiro-ia` está no branch `feat/reorganizacao-financeiro`, que **já está
integrado** na `main`, e a árvore está **limpa** (nada modificado além de `tsbuildinfo`). O
`CashForecastPanel` não foi tocado por este turno — a instrução foi respeitada — e não há trabalho daquela
sessão esperando merge.

O que aquela frente deixou no ar é o `feat/f2-ui-financeiro` (acima), que é dela.

---

## Ordem de integração sugerida

1. **`docs/turno-noite-20260810`** — merge limpo, custo zero.
2. **`feat/f2-ui-financeiro`** — um conflito só, em `.md`, e a frente está verde.
3. **`feat/nfse-nacional`** — por último: é a maior, tem conflito em dois arquivos e **precisa da conversa
   sobre o banco estar à frente do código**.

---

## Nota para o `NOVO-016` (achado da outra sessão)

Aquele achado registra um teste intermitente na suíte, com o nome não capturado — e diz, com honestidade, que
foi falha de instrumentação. **Capturei hoje:** são `src/test/hooks-antes-do-return.test.ts` (1 caso) e
`src/test/postgrest-select-columns.test.ts` (2 casos). Falharam juntos na primeira execução da suíte completa
em um worktree recém-criado, passaram na segunda, e passam sempre quando rodados isoladamente.

Os três varrem o sistema de arquivos do projeto (leem componentes e os `.select()` do código-fonte), o que
sustenta a hipótese de contenção de I/O sob carga — várias suítes rodando ao mesmo tempo nesta máquina — e não
de defeito de lógica. **Não investiguei além disso**, e a frente não é minha: fica como contribuição ao achado
alheio, não como diagnóstico fechado.
