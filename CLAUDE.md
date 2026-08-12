
## Regras invariantes — valem para TODA sessão neste repositório

Este repositório é editado por **várias sessões de IA ao mesmo tempo** (worktrees paralelos, integrações
de minuto em minuto na `main`). As regras abaixo não são preferência de estilo: cada uma nasceu de um
incidente já ocorrido aqui. Valem independentemente da tarefa em curso.

1. **`supabase db push` NÃO É UTILIZÁVEL neste projeto. Migration se aplica por
   `supabase db query --linked -f <arquivo>` — e a versão se registra à mão, no mesmo ato.**

   Medido em 12/08/2026, e é maior do que se supunha: **297 versões registradas no banco ×
   252 arquivos em disco**, com a deriva correndo nos **dois sentidos**:

   - **159 versões registradas sem arquivo local** (154 delas anteriores a qualquer trabalho
     recente, cobrindo abril→agosto). É o que faz o `db push` abortar com
     `LegacyDbPushMissingLocalError` antes de aplicar seja o que for.
   - **114 arquivos em disco cuja versão nunca foi registrada** — consequência direta de
     `db query -f`, que **executa o SQL mas não escreve em `schema_migrations`**.

   **Na prática, aplicar uma migration são dois passos:**

   ```bash
   npx supabase db query --linked -f supabase/migrations/<arquivo>.sql
   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations \
     (version, name) values ('<AAAAMMDDHHMMSS>', '<nome_sem_a_data>') on conflict (version) do nothing;"
   ```

   Pular o segundo passo faz o arquivo virar o 115º sem registro. **`migration repair
   --status reverted`, que o CLI sugere, NÃO se usa aqui**: marcaria como revertidas 154
   migrations que de fato rodaram em produção — escrever no histórico que algo não aconteceu,
   quando aconteceu.

   **Continua valendo, e por cima disto:** nenhuma migration é aplicada sem o arquivo
   commitado ANTES em `supabase/migrations/`. Sem exceção — inclusive correção de dados.
   Motivo original: em 09/08/2026 a `20260809140033_corrige_categorias_que_o_mcc_desmente` foi
   aplicada e não existia em disco (NOVO-003); só foi recuperada porque o Postgres guardava o
   SQL. Entre as 159 há **uma correção de segurança de RLS que existe apenas no banco**
   (MF-AUD-021) — o repositório, hoje, não reconstrói a produção.

   A reconstrução do histórico via `db pull` está agendada como tarefa própria **para depois
   de 01/09** (ver MF-AUD-058). Não é caminho crítico, e não se faz às pressas.

2. **Commit que atende achado da auditoria referencia o ID na mensagem** (`MF-AUD-0XX`).
   Motivo: é o que permite dizer, meses depois, o que foi feito e o que continua aberto sem reler 27 commits.

3. **Problema encontrado fora do escopo da tarefa atual: registrar em `audit/novos-achados.md` com ID no
   formato da regra 8 e NÃO corrigir.**
   Motivo: corrigir de passagem mistura diffs, quebra a rastreabilidade e transforma uma tarefa pequena em
   sessão longa. Registrar custa um minuto e não perde o achado.

4. **Itens marcados `[DECISÃO]` em `audit/99-sumario-executivo.md` não se implementam sem resposta
   explícita do Gustavo registrada em arquivo.**
   Motivo: são doze itens em que a escolha é de negócio, não técnica (matriz de acesso do financeiro, corte
   das telas legadas, validade de orçamento, i18n como requisito). Presumir a resposta é decidir pelo dono.

5. **Gates de CI e scripts de teste não se alteram fora de tarefa dedicada.**
   Motivo: afrouxar o gate para fazer a própria tarefa passar é como perder a rede de proteção sem ninguém
   perceber. Se o gate atrapalha, isso é um achado — ver regra 3.

6. **Segredos e tokens nunca em código, em log ou em mensagem de commit — sempre via secrets.**
   Motivo: as Edge Functions expostas dependem de segredo compartilhado como única autenticação
   (MF-AUD-053/054). Um valor vazado em log de função anula a proteção inteira. Para conferir se dois
   segredos coincidem, compare **hashes**, nunca os valores.

7. **Trocar a fonte de dados de um formulário exige que o tipo FALHE até leitura e escrita estarem
   completas. Cast para compilar (`as typeof`, `as any`, `as unknown as`) é proibido nesse contexto.**
   Motivo: em 11/08/2026 uma view sem as colunas de valor (`service_orders_tecnico`) foi ligada aos hooks de
   leitura com `.from(fonte as typeof OS_TABELA)` — o cast existia só para o código compilar antes de a view
   existir no schema gerado. Ele escondeu do compilador duas coisas que a revisão pré-merge encontrou por
   leitura (NOVO-020): um embed impossível, que faria o PostgREST responder 400 e derrubar a tela do técnico
   em 100% das OSs; e, pior, que `ServiceOrderForm` semeia com `d.<campo> || 0` e salva o formulário
   **inteiro** — de modo que cada Salvar do técnico gravaria zero em doze campos financeiros da OS. Sem o
   cast, o `tsc` teria apontado os campos ausentes na primeira compilação.
   **Na prática:** fonte nova (view, RPC, endpoint) entra com o tipo real dela. Se o formulário não compila,
   é porque a escrita ainda depende de campo que a leitura não traz — e isso é o defeito, não o obstáculo.

8. **Achado novo usa ID com slug da frente: `NOVO-<slug>-NN`.**
   Motivo: em 11/08/2026 quatro IDs tinham dois significados cada, porque três sessões numeravam em sequência
   global ao mesmo tempo — e a colisão só apareceu na integração. O slug elimina a corrida: cada frente
   numera no próprio espaço.
   **Vale para achados novos.** Os `NOVO-001` a `NOVO-024` já registrados ficam como estão: renumerar
   quebraria as referências nas mensagens de commit, que são imutáveis.

> Antes de editar: se houver (ou puder haver) outra sessão ativa, isole-se em um worktree próprio —
> `bash .claude/skills/multi-session-guard/guard.sh worktree <nome>`. Nunca `git add -A`.

---

## Deploy de edge function neste repo

`supabase functions deploy` usa Docker para empacotar. Quando o Docker Desktop não está
rodando, o CLI imprime "WARNING: Docker is not running" e **fica pendurado sem erro** —
parece lentidão, mas nunca termina.

Use sempre `--use-api`, que empacota no servidor e dispensa o Docker:

    npx supabase functions deploy <nome> --project-ref okurngvcodmljjicopdp --use-api

Sintoma de que o deploy não passou: `list_edge_functions` mostra a versão antiga. Vale
conferir depois de deployar — o CLI travado não devolve código de erro.
