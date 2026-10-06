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
   `src/lib/extrato-diarias.ts` (puro, testado) monta o HTML A4 e as linhas do CSV;
   `use-documentos-diarias.ts` renderiza o PDF no servidor (`/api/pdf`, o mesmo Chromium dos
   orçamentos) e cai na impressão do navegador se o servidor não responder. Não usa o
   `PDFData` de `_shared/pdf/documento.ts`: aquele modelo é de OS/orçamento e é dividido com as
   funções do servidor. O documento é de prestação de serviço por dia — sem horário, sem
   "jornada"/"ponto" no papel. O CSV (`;`, BOM, fórmula neutralizada por `exportToCSV`) junta
   todos os freelancers do período (na grade, o mês da tela).
4. **Assistente:** `registrar_diaria` + `consultar_freelancer` no lugar das 5 de jornada; prompt;
   confirmação com o pedido resolvido. Fecha a paridade tela ↔ assistente (o hook da tela entra em
   `paridade-tela-assistente.test.ts` junto com a tool).
   Feito em `tools/diarias.ts`: jornada `inteiro|meio|faltou|apagar` ("apagar" só para dia lançado
   por engano — a tela exclui, a paridade exige; "faltou" grava a ausência). O resumo da pendência
   (`resumirDiaria`, chamado em `buildPendingSummary`) mostra o dia resolvido e o que já estava
   lançado; depois do "sim" o `aviso` traz a frase do banco e o saldo com a pessoa. Nome acha só
   quem tem perfil de diária e está ativo. Custo: ~480 tokens por chamada contra 1.155 das 5
   antigas. `jornada.ts` apagado; `_shared/payroll/calculo.ts` e as tabelas de folha ficam, sem uso.
5. **Lucro por OS com mão de obra real:** `vw_os_profitability` soma o valor dos dias rateado pelas
   OS; `get_os_profitability` passa a ler a view. Mostrar ao dono a lista de margens antes/depois.
   Migration `20260929173000_lucro_por_os_com_mao_de_obra`: `v_custo_real_mao_de_obra_por_os`
   passa a ler as diárias (work_shift_os, partes iguais) em vez da folha fechada (sempre vazia);
   `vw_os_profitability` desconta `labor_cost_real` do lucro e ganha, no fim, `labor_cost_real`,
   `labor_days`, `labor_sold` e `hours_sold`. A tela soma a mão de obra no custo e mostra a coluna
   "Mão de obra (diárias)". A tool lê a view (corrige também o custo das peças, que usava o preço de
   venda). **Antes/depois medido em 29/09: nenhuma OS muda** — nenhum dos 18 dias estava ligado a
   OS; a margem passa a descontar a mão de obra conforme os dias forem ligados. A do dono continua
   fora. Teste: `supabase/tests/lucro_por_os_mao_de_obra.sql`.
6. **Aposentar o app** (só leitura).

## Melhorias

- **Vários dias de uma vez — FEITO em 29/09/2026** (teste do dono: "o Mickael faltou desde o dia
  19/09" gravava só o dia 19). Assistente: `registrar_diaria` aceita `data_ate` e `fim_de_semana`;
  `data` entende o dia da semana ("segunda" = a mais recente até hoje); só dias úteis por padrão;
  até 31 dias; nunca no futuro; `apagar` é um dia de cada vez. Tela: "Registrar dia" › "Vários
  dias" (De/Até, sábado e domingo marcáveis). Nos dois, **dia já lançado no intervalo fica como
  está** — o intervalo só preenche o que falta (um "faltou desde…" não pode apagar um dia inteiro
  lançado no meio); corrigir é registrar aquele dia sozinho. Sem mudança no banco: é
  `registrar_diaria` por data. Obs.: 19/09/2026 foi sábado — em dias úteis o intervalo começa no 21.
- **Freelancer novo pelo assistente — FEITO em 01/10/2026** (o dono pediu "cadastre o João Marcelo,
  entrou no lugar do Mickael" e o assistente respondeu que só dava pela tela, que não existe). Função
  `cadastrar_freelancer` (migration `20261001183918`): favorecido (ou o que já existe com o MESMO
  nome/CPF — nome parecido não conta) + diária + conta corrente desde o primeiro dia + categoria +
  regra por CPF quando há CPF; `p_simular` devolve o que faria, e é o texto da confirmação. Tool
  `cadastrar_freelancer` no perfil; `cadastrar_favorecido` passa a mandar diarista para ela. Junto:
  `registrar_diaria` aceita `valor_diaria` só quando a pessoa diz outro valor para o dia ("na
  quarta foram 130") — a tela já permitia. João Marcelo cadastrado pela função (R$ 150 desde
  29/09, Pix e-mail, sem CPF) com 29/09 R$ 150, 30/09 R$ 130 e 01/10 R$ 150. Mickael mantido.
  Teste: `supabase/tests/cadastrar_freelancer.sql`.
- **"Novo freelancer" na tela — FEITO em 03/10/2026** (o dono: "o botão na tela, eu quero sim").
  Financeiro › Diárias, na barra e na tela vazia: `NovoFreelancerDialog.tsx` em duas etapas — o
  formulário e a CONFERÊNCIA (a mesma `cadastrar_freelancer` com `p_simular`, nada gravado; a recusa
  aparece ali), e só então "Cadastrar". Hooks `simularCadastro`/`useCadastrarFreelancer` em
  `use-diarias.ts`. A tela não repete regra nenhuma: tipo da chave, cadastro existente e regra por
  CPF são do banco.

## Rodada de 06/10/2026 — Pix lançado à mão, períodos, WhatsApp e acerto

Pedido do dono: "lancei pelo Lançar o Pix que já fiz e não apareceu no extrato de diárias (o de
dinheiro/bolso apareceu)"; filtrar por período livre ("o período não pago", "duas semanas"); extrato
em PDF, consulta e lançamento também pelo WhatsApp; revisar o módulo e pesquisar o mercado.

**Causa do "não apareceu":** o "Lançar" com Pix grava uma ANOTAÇÃO (anotacoes_do_extrato) que
espera a linha do banco; o pagamento só nascia quando o motor do extrato (06:10 e 15:10) casava as
duas e o lançamento era aprovado. Caso real: Pix de R$ 100 ao Roberto às 17:36/17:39 (a 2ª anotação
substituiu a 1ª — era o mesmo Pix); a linha chegou às 18:06 e só entraria no dia seguinte.

Decisões do dono (caixa de perguntas): o Pix anotado **aparece e já desconta**; períodos "em
aberto", "últimos 15 dias", "desde o último pagamento", "semana atual" + datas livres; PDF pelo
WhatsApp **do mesmo jeito que o do orçamento**; da pesquisa, as quatro: vale separado, fechar ao
pagar, recibo numerado, extrato ao freelancer com "conferido".

- **Fase 1** (migration `20261006200000`): a conta corrente inclui a anotação sem lançamento como
  "Anotado — aguardando o banco" (sai quando o lançamento existe; recusada na fila não conta);
  `_periodo_do_atalho` por pessoa; `conta_corrente_freelancer`/`resumo_freelancers` com `p_atalho`.
  `banking-sync` dispara o motor do extrato quando chega transação nova. Tela: períodos + "Escolher
  datas…", linha "Anotado", cartão com o período de cada um; aviso longo quando uma anotação
  substitui outra igual. O extrato (PDF/CSV) passou a `_shared/diarias/extrato.ts`.
- **Fase 2** (migration `20261006210000`): token de uso único (3 min) para o `/api/pdf` renderizar
  documento sem ordem (`x-pdf-token`; só service_role emite). Assistente: `consultar_freelancer` com
  os períodos e datas; `registrar_pagamento_freelancer` (Pix → anotação; dinheiro → Caixa; bolso do
  sócio → reembolso); `enviar_extrato_freelancer` (extrato ou recibo, ao WhatsApp de quem pediu).
  Tela: "Registrar pagamento".
- **Fase 3** (migration `20261006220000`): `acertos_diarias` — fechar o período ao pagar (foto:
  dias, vales já pagos, a pagar), recibo nº sequencial, dias TRAVADOS até a data (trigger), reabrir
  só o último e com motivo. **Vale** = pagamento feito dentro do período aberto (o acerto o desconta;
  não se marca pagamento por pagamento). Recibo em A4 com valor por extenso, competência e
  assinatura (art. 320 CC). `enviar_acerto_ao_freelancer` manda o recibo ao WhatsApp dele pedindo
  OK; o webhook chama `registrar_conferencia_do_freelancer` (mesma `_e_concordancia` da confirmação
  do agendamento) e avisa o dono. Tela: bloco "Acertos" no Extrato (fechar com conferência, recibo,
  reabrir), dias travados sem Corrigir/Excluir. As 3 tools do acerto ficam fora do perfil enxuto do
  admin (teto de 100), alcançáveis pela rede.
- Testes SQL: `diarias_pix_anotado_e_periodos.sql` (11), `token_de_pdf.sql` (7),
  `diarias_acerto_e_recibo.sql` (14); os antigos das Diárias passam com as migrations novas.
- Pesquisa (apps BR/estrangeiros, repositórios): ver o relatório da conversa de 06/10/2026 —
  o que ficou de fora: mensagem automática ao freelancer quando o dia é lançado, lembrete de
  "N dias sem pagar", foto/GPS (baixa prioridade para 3 pessoas).

## Armadilhas já medidas

- Lançar a diária como despesa da OS (`so_expense_add`) **sobe o preço do cliente** (faturável por
  padrão) ou some da margem (não faturável). O custo entra pela view de lucro, não pela OS.
- O fechamento de folha criaria conta a pagar do mesmo trabalho que o Pix já lançou — a trava
  `trg_folha_sem_diarista` recusa diarista com conta corrente.
- "Diárias de freelancers" ainda não está em `CATEGORIAS_COM_FAVORECIDO` (`use-payees.ts`): a fila
  não mostra o seletor "quem recebeu" para ela (o servidor grava o favorecido sugerido mesmo assim).
- Deploy de `finance-review`/`ai-agent` só a partir da main atual — a sessão do financeiro publicou
  v42/v196 a partir de a8afecbb.
