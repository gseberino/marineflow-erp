# MarineFlow — Diárias de freelancers (Roberto, Mickael)

**Data:** 28/09/2026 · **Status:** Passos 0 e 1 no ar (29/09, main a15931d3); Passo 2 no branch `session/diarias`

Traz para dentro do ERP o controle que vivia fora dele: a planilha `Controle_Freelancers_HBR.xlsx` e o
app em artifact "Diárias e pagamentos | HBR" (https://claude.ai/artifact/UyLYGqmLXsX5Z7JYKK4Jnh).

## O ponto de partida (medido em 28/09/2026)

- O módulo de jornada de 18–24/08 (`plans/marineflow-jornada-e-pagamento-de-equipe.md`) já tinha o
  esqueleto — `payees` + `work_profiles` (Roberto R$ 160, Mickael R$ 130), `work_shifts`, 5 tools —
  e **nunca foi usado**: 0 dias, 0 folhas, 0 chamadas das tools.
- O uso real estava no app: 16 dias (07–25/09, lançados em lote em 23 e 24/09) e 10 pagamentos.
- Os pagamentos **já vinham do extrato** como `payables` com favorecido — mas espalhados em 4
  categorias, e 16 Pix para o CPF do Roberto estavam no fornecedor CORREA MATERIAIS (e 6 na VIA
  S.A.) porque o motor antigo casava por "nome parecido". App × ERP tinham 1 pagamento em comum.
- Nenhum cálculo de lucro por OS desconta mão de obra (`vw_os_profitability`, `get_os_profitability`).

**Conclusão:** estender o que existe, não criar tabelas paralelas. Freelancer = favorecido com perfil
de diária; dia = `work_shifts`; pagamento = o lançamento que já vem do extrato. Saldo calculado.

## Decisões do dono (28/09/2026)

| # | Decisão |
|---|---|
| D1 | Os Pix do Nubank **pessoal** do Gustavo ao Roberto entram como "pago do bolso do sócio", com reembolso a ele; o Roberto fica gravado como quem recebeu (`payables.beneficiario_id`). |
| D2 | Corrigir os 16 Pix de outras pessoas presos na VIA S.A. |
| D3 | Conta corrente começa em **25/08/2026, saldo zero** (reproduz o app). |
| D4 | Categoria nova **"Diárias de freelancers"** (custo direto); regra por CPF lança sozinha. |
| D5 | Dia em duas OS: o valor se divide **em partes iguais** (`work_shift_os`). |
| D6 | Tela em **Financeiro › Diárias** (admin e financeiro). |
| D7 | As 5 tools de jornada viram 2: `registrar_diaria` e `consultar_freelancer`. |
| D8 | Pelo assistente, toda diária pede **"sim"** antes de gravar. |
| D9 | Retenção de INSS/ISS, NFS-e e risco de vínculo: fora por enquanto (decisão do dono). |
| D10 | Valor do módulo só para admin/financeiro — sai a exceção "o titular lê o próprio valor". |
| D11 | Importar os 16 dias do app e congelá-lo quando a tela do ERP estiver no ar. |
| D12 | Extra = só o que o freelancer pagou do próprio bolso. Todo Pix a ele conta como pago; o de material mantém a categoria de material. |

## Passos

0. **Dados (no ar, 28/09):** VIA S.A. (16) e CORREA (16 Pix do Roberto) corrigidas; categoria, CPF do
   Roberto, regras por documento; 11 pagamentos desde 25/08 em Diárias.
1. **Banco + tela mínima:** migration `20260928190000_diarias_conta_corrente` (dia com valor gravado,
   rateio, conta corrente, `registrar_diaria`/`apagar_diaria`/`conta_corrente_freelancer`/
   `resumo_freelancers`, beneficiário no bolso do sócio, trava da folha, D10) + importação +
   Financeiro › Diárias (Resumo e Extrato). Teste: `supabase/tests/diarias_conta_corrente.sql`.
2. **Grade do mês + ficha do dia** (dia inteiro / meio / não trabalhou, lista do dia, Desfazer).
   Só frontend (`GradeDiarias.tsx`, `FichaDoDia.tsx`). **Não reaproveita o `WeekView` da Agenda:**
   ele é pessoa × 7 dias, interno a uma página de 1.549 linhas, e ~80% dele desenha cartões de OS e
   tarefa; a semelhança é só "matriz com clique na célula". Extrair um componente comum obrigaria a
   mexer numa tela que funciona sem um segundo uso que precise do mesmo. Na ficha, "Não trabalhou"
   grava a falta (valor zero) — apagar é o "Excluir" da lista, com Desfazer. Dia antes do início da
   conta corrente e dia no futuro ficam fechados na grade e no formulário.
3. **Extrato em PDF** com assinatura e **CSV mensal** para o contador.
4. **Assistente:** `registrar_diaria` + `consultar_freelancer` no lugar das 5 de jornada; prompt;
   confirmação com o pedido resolvido. Fecha a paridade tela ↔ assistente (o hook da tela entra em
   `paridade-tela-assistente.test.ts` junto com a tool).
5. **Lucro por OS com mão de obra real:** `vw_os_profitability` soma o valor dos dias rateado pelas
   OS; `get_os_profitability` passa a ler a view. Mostrar ao dono a lista de margens antes/depois.
6. **Aposentar o app** (só leitura).

## Armadilhas já medidas

- Lançar a diária como despesa da OS (`so_expense_add`) **sobe o preço do cliente** (faturável por
  padrão) ou some da margem (não faturável). O custo entra pela view de lucro, não pela OS.
- O fechamento de folha criaria conta a pagar do mesmo trabalho que o Pix já lançou — a trava
  `trg_folha_sem_diarista` recusa diarista com conta corrente.
- "Diárias de freelancers" ainda não está em `CATEGORIAS_COM_FAVORECIDO` (`use-payees.ts`): a fila
  não mostra o seletor "quem recebeu" para ela (o servidor grava o favorecido sugerido mesmo assim).
- Deploy de `finance-review`/`ai-agent` só a partir da main atual — a sessão do financeiro publicou
  v42/v196 a partir de a8afecbb.
