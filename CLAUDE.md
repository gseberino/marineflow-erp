
## Regras invariantes — valem para TODA sessão neste repositório

Este repositório é editado por **várias sessões de IA ao mesmo tempo** (worktrees paralelos, integrações
de minuto em minuto na `main`). As regras abaixo não são preferência de estilo: cada uma nasceu de um
incidente já ocorrido aqui. Valem independentemente da tarefa em curso.

1. **Nenhuma migration é aplicada em produção sem o arquivo correspondente commitado ANTES em
   `supabase/migrations/`. Sem exceção — inclusive correção de dados.**
   Motivo: em 09/08/2026 a migration `20260809140033_corrige_categorias_que_o_mcc_desmente` foi aplicada
   em produção e não existia em disco (NOVO-003); só foi recuperada porque o Postgres guardava o SQL. Antes
   dela, outras 35 já haviam entrado assim (MF-AUD-058), incluindo **uma correção de segurança de RLS que
   existe apenas no banco** (MF-AUD-021) — o repositório, hoje, não reconstrói a produção.

2. **Commit que atende achado da auditoria referencia o ID na mensagem** (`MF-AUD-0XX`).
   Motivo: é o que permite dizer, meses depois, o que foi feito e o que continua aberto sem reler 27 commits.

3. **Problema encontrado fora do escopo da tarefa atual: registrar em `audit/novos-achados.md` com ID
   `NOVO-XXX` e NÃO corrigir.**
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
