# Novos achados encontrados durante a Fase 2

Itens fora do escopo da tarefa em execução, registrados conforme a regra 5 da fila.
Não foram corrigidos.

---

## BACKLOG (registrado a pedido do dono, sem implementar)

### Tool de notificação operacional para o técnico, com template fixo
- **Origem:** decisão do dono sobre NOVO-005 (10/08/2026), ao negar WhatsApp livre ao técnico.
- **Ideia:** o técnico não dispara nem agenda mensagem pelo assistente — mas há casos operacionais legítimos
  ("estou a caminho", "cheguei", "serviço concluído") que hoje ou passam por outra pessoa ou não acontecem.
  Uma tool futura poderia cobrir isso com **template fixo e sem texto livre**: o técnico escolhe o evento, o
  sistema monta a mensagem, e não há campo onde ele escreva o que quiser.
- **Por que isso muda o risco:** o problema de dar WhatsApp ao técnico não é o envio — é o **texto livre** para
  cliente, sem revisão. Template fixo remove essa superfície e mantém a rastreabilidade.
- **Referências no código:** já existe `OnMyWayButton.tsx` (agenda) fazendo algo próximo pela UI, e
  `whatsapp_templates` como tabela de modelos. O caminho provável é reaproveitar os dois.
- **Status:** não implementado, sem prazo. Só entra em execução com pedido explícito.

---

## [NOVO-001] `deno check`/`deno test` sem `--no-check` falha em qualquer função que importe supabase-js

- **Encontrado em:** T0.1 (MF-AUD-053), ao rodar o gate de teste
- **Categoria:** I (testes/CI) — **Severidade sugerida:** P2
- **Descrição:** `deno test --allow-all supabase/functions/...` aborta antes de executar quando o arquivo sob
  teste importa `https://esm.sh/@supabase/supabase-js@2.45.0`:
  ```
  error: Error: Could not find "@types/node" in a node_modules folder.
  Deno expects the node_modules/ directory to be up to date. Did you forget to run `deno install`?
  ```
  A causa é a presença de `node_modules/` do frontend na raiz: o type-checker do Deno tenta resolver as
  `@types` referenciadas pelo pacote npm e não encontra. Com `--no-check` a suíte roda normalmente
  (**240 testes, 0 falhas**).
- **Por que importa agora:** a tarefa **T2.2** vai colocar `deno test -A supabase/functions` no CI. Do jeito
  que está, ou o comando precisa de `--no-check`, ou o CI quebra em todas as funções que falam com o banco —
  que são quase todas. E usar `--no-check` significa que o CI **não** verifica tipos das Edge Functions, o que
  reabre exatamente o buraco descrito em MF-AUD-046 (o `tsc` do frontend não cobre `supabase/functions`).
- **Sugestão para T2.2:** rodar o teste com `--no-check` **e** acrescentar um passo separado de
  `deno check` com um `deno.json` próprio em `supabase/functions/` (que isole a resolução de tipos do
  `node_modules` do frontend). Assim o CI executa os testes e ainda verifica tipos.
- **Evidência:** saída dos dois comandos, executados em 08/08/2026 no worktree `session/p0-webhook`.

---

## [NOVO-002] Eventos da Evolution ligados sem consumidor no código — e `Webhook Base64` como risco de perda de mensagem

- **Encontrado em:** 09/08/2026, durante a T0.1 (o dono ampliou os eventos no Evolution Manager)
- **Categoria:** G (performance/custo) + A (risco funcional) — **Severidade sugerida:** P2
- **Descrição:** A instância passou a emitir ~18 eventos: `APPLICATION_STARTUP`, `CHATS_SET/UPDATE/UPSERT`,
  `CONNECTION_UPDATE`, `CONTACTS_SET/UPDATE/UPSERT`, `GROUP_UPDATE`, `GROUPS_UPSERT`, `LABELS_ASSOCIATION`,
  `LABELS_EDIT`, `MESSAGES_SET/UPDATE/UPSERT`, `PRESENCE_UPDATE`, `QRCODE_UPDATED`, `SEND_MESSAGE`
  — além de **`Webhook Base64` ligado**.

  O webhook trata explicitamente `messages.update` (status de entrega) e, para o resto, delega a
  `provider.parseIncomingWebhook(payload)`; o que não for mensagem retorna `null` e sai como
  `{ok:true, ignored:"system_or_group"}` (`whatsapp-webhook/index.ts:238-245`). Portanto **todos os eventos
  novos são invocação paga e descartada**.

  Dois riscos, em ordem de gravidade:
  1. **`Webhook Base64`**: faz a Evolution embutir o binário da mídia em base64 no corpo do webhook. O código
     **não lê base64** (`grep -n "base64" whatsapp-webhook/index.ts` → nada); a mídia é obtida por URL em
     `whatsapp-read-media`. Um vídeo de 5 MB vira ~6,7 MB de JSON inútil por requisição, com risco de estourar
     o limite de corpo da Edge Function — e aí **a mensagem com mídia não é gravada**.
  2. **Volume**: `PRESENCE_UPDATE` dispara a cada "digitando"/"online" de qualquer contato; `MESSAGES_SET`,
     `CHATS_SET` e `CONTACTS_SET` mandam sincronização em massa a cada reconexão da instância.
- **Recomendação imediata (config, sem código):** desligar `Webhook Base64` e manter ligados apenas
  `MESSAGES_UPSERT`, `MESSAGES_UPDATE`, `SEND_MESSAGE` e `CONNECTION_UPDATE`.
- **Oportunidade real (vira tarefa quando houver código):**
  - `CONTACTS_UPSERT`/`CONTACTS_UPDATE` → o payload traz `pushName`/nome do contato: alimenta direto a
    identidade de contatos (frente que levou a identificação de 1,1% → 72,6%), sem custo de IA.
  - `CONNECTION_UPDATE` → detectar queda da instância e avisar o dono; hoje a queda só é percebida pelo
    silêncio. Casa com o `health_status` que o healthcheck já calcula.
  - `MESSAGES_DELETE` (hoje desligado) → registrar que o cliente apagou uma mensagem.
- **Evidência:** prints do Evolution Manager (09/08/2026); `whatsapp-webhook/index.ts:238-245`; ausência de
  qualquer referência a base64 na função; logs de Edge Function mostrando `POST | 200` seguidos com
  `?token=` logo após o Save.

---

## [NOVO-004] Nenhum teste cobre os termos e condições do PDF

- **Encontrado em:** 09/08/2026, durante a S3 (diagnóstico do sintoma dos termos)
- **Categoria:** I (testes) — **Severidade sugerida:** P3
- **Descrição:** Existem **sete** arquivos de teste de PDF (`pdf-generator`, `pdf-generator.payment-history`,
  `pdf-canvas-scale`, `pdf-css-isolation`, `pdf-survey`, `pdf-html-isolation`, `pdf-pagination`) e **nenhum**
  menciona `showTerms` ou `terms` — busca em `src/lib/*.test.ts` e `src/test/*.test.ts` retorna vazio.
  Os termos são conteúdo contratual que vai ao cliente, e a parte determinística é trivial de cobrir: dado
  `showTerms: true` e `terms` preenchido, o HTML gerado contém "Condições Gerais e Garantia" e o texto; com
  `showTerms: false`, não contém. Isso não testa a rasterização do `html2canvas` (que exige navegador), mas
  trava a metade do problema que é lógica pura — justamente a metade que o diagnóstico da S3 precisou
  verificar à mão.
- **Ação recomendada:** dois casos em `pdf-generator.test.ts`. Não foi feito por estar fora do escopo da S3
  (somente leitura).
- **Evidência:** `audit/diagnostico-terms.md` §6; `grep -rn "showTerms\|terms" src/lib/*.test.ts src/test/*.test.ts` → vazio.

---

## [NOVO-005] 14 tools com service role seguem sem barreira de cargo — fora do escopo da decisão #3

- **Encontrado em:** 10/08/2026, durante a T1.5
- **Categoria:** F — **Severidade sugerida:** P2
- **Descrição:** A T1.5 aplicou a decisão #3 (técnico não vê financeiro) e fechou **todas** as tools que
  tocam as cinco tabelas financeiras. Aproveitando a passagem, também barrei as de gestão que usavam service
  role sem cargo (`get_task_metrics`, `agent_health_report`, `list_pending_pos`, `list_low_stock`,
  `get_os_profitability`, `get_technician_commissions`) e endureci `adjust_inventory`.

  **Sobram 14 tools que usam service role e não têm barreira de cargo alguma**, e eu deliberadamente não
  mexi nelas porque decidir ali seria decidir pelo dono:
  ```
  comms-tools.ts    interpret_customer_reply
  memory.ts         list_memory_notes · forget_note
  service-orders.ts create_service_order · update_service_order_status
  whatsapp.ts       send_collection_reminder(high) · send_service_order_link(high) ·
                    schedule_whatsapp_message(high) · list_scheduled_whatsapp ·
                    cancel_scheduled_whatsapp · schedule_self_reminder ·
                    list_unanswered_messages · mute_contact · unmute_contact
  ```
  Três grupos, com respostas provavelmente diferentes:
  1. **OS de campo** (`create_service_order`, `update_service_order_status`) — parecem legítimas para o
     técnico; é o trabalho dele. Manteria como está.
  2. **Lembrete pessoal** (`schedule_self_reminder`, `list_memory_notes`) — idem.
  3. **Comunicação com cliente** (as 8 de WhatsApp, `interpret_customer_reply`) — **aqui é decisão de
     negócio**: o técnico pode disparar mensagem ao cliente pelo agente? As três de `risk: "high"` já param
     no gate de aprovação; as `low` executam direto.
- **Pergunta para o Gustavo:** o cargo técnico pode enviar/agendar WhatsApp para cliente pelo assistente?
  Se não, aplico `NON_TECHNICIAN_ROLES` nas oito de WhatsApp — é o mesmo diff das outras.
- **Evidência:** varredura em `audit/`-scratch reproduzida no teste de guarda
  `supabase/functions/_shared/ai/tools/cargo-financeiro_test.ts`, que hoje cobre só a fatia financeira.

---

## [NOVO-006] Valores da OS continuam visíveis ao técnico — column-level grant não serve aqui

- **Encontrado em:** 10/08/2026, na T1.7 (decisão #3, item 2: "avaliar column-level grants")
- **Categoria:** F — **Severidade sugerida:** P2 · **Status:** avaliado, **não aplicado**, por decisão técnica
- **Descrição:** A decisão #3 pediu para avaliar `REVOKE SELECT (coluna)` nos campos de valor de
  `service_orders` (`grand_total`, `labor_cost_total`, `parts_cost_total`, `travel_cost_total`,
  `operational_cost_total`, `card_fee_amount`, `discount_amount`, `tax_amount`…), com a instrução de manter a
  ocultação atual se quebrasse o frontend. **Quebra.** Motivo:

  1. Column-level grant no Postgres **não omite a coluna** — ele **recusa a consulta inteira** com
     `42501: permission denied for column`. Não existe "devolver NULL no lugar".
  2. O PostgREST expande `select=*` para a lista de colunas. O frontend pede `*` em praticamente todo lugar —
     `SO_SELECT` e `SO_DETAIL_SELECT` (`src/hooks/use-service-orders.ts:15-33`) começam com `*`, e o mesmo
     vale para `usePDFData`/`fetchPDFData`.
  3. Resultado: o técnico deixaria de conseguir **abrir a OS**, que é a tela do trabalho dele. Trocaria um
     problema de confidencialidade por um de operação.

  **O que funcionaria, se um dia virar prioridade:** uma view `service_orders_tecnico` sem as colunas de
  valor + RLS que direcione o técnico a ela, ou uma coluna calculada que zere valores por cargo. As duas são
  mudanças de superfície de API, com impacto no frontend — tarefa própria, não um `REVOKE`.

  **Situação atual, dita sem eufemismo:** o técnico **vê os valores da OS** (total, mão de obra, peças) na
  tela de OS e no PDF. O que a T1.7 fechou foi o acesso às cinco tabelas financeiras — títulos, pagamentos,
  contas a pagar, notas e extrato bancário. É menos do que "não enxerga nada financeiro" ao pé da letra, e o
  Gustavo precisa saber disso para decidir se quer a tarefa da view.
- **Evidência:** `src/hooks/use-service-orders.ts:15-33` (selects com `*`); comportamento documentado do
  PostgREST/Postgres para grants de coluna.

---

## [NOVO-007] PDF baixado trunca o fim: altura da captura é congelada antes de o html2pdf inserir os espaçadores

- **Encontrado em:** 10/08/2026, no diagnóstico do P1 do PDF truncado (`audit/diagnostico-pdf-truncado.md`)
- **Categoria:** A — **Severidade sugerida:** P1 · **Status:** diagnosticado, **não corrigido**
- **Descrição:** `generatePDFBlob` mede `captureHeight = container.scrollHeight`
  (`src/lib/pdf-generator.ts:380`) **depois** de inserir as marcas `.html2pdf__page-break` — que são divs
  vazias e não somam altura — e congela esse valor em `html2canvas.height`/`windowHeight`. Em seguida, o
  plugin de pagebreak do html2pdf (`node_modules/html2pdf.js/dist/html2pdf.js:420-428`) implementa cada quebra
  **inserindo uma div de padding de até 1031 px no DOM**, e `toCanvas` (`:771-775`) repassa as opções como
  estão. O documento cresce, a captura não: o excedente — sempre o **fim** — fica de fora da imagem.
- **Previsão que confirma:** documento de 1 página (sem quebra, sem espaçador) **não** trunca; o defeito só
  aparece com 2+ páginas e piora com o comprimento.
- **Provável causa do sintoma antigo dos termos:** os termos são o penúltimo bloco do documento. O
  `diagnostico-terms.md` descartou dado e preferência e ficou sem causa — **esta é a causa mais provável**, e
  as duas investigações se fecham numa só.
- **Caminho sugerido (não implementado):** inserir os espaçadores nós mesmos **antes** de medir
  `captureHeight` e tirar `legacy` do `pagebreak.mode`, para que o html2pdf não mexa mais no DOM depois da
  medição. Alternativa mais simples: não congelar `height`/`windowHeight` — porém essas opções foram postas de
  propósito contra clipping lateral, então exigem teste nos dois eixos.
- **Bônus latente:** o loop do plugin (`html2pdf.js:369`) usa `getBoundingClientRect()` enquanto insere
  espaçadores no mesmo loop, invalidando as coordenadas dos elementos seguintes.

---

## [NOVO-016] Teste intermitente na suíte do F2-UI — 1 falha em 5 execuções, nome não capturado

- **Encontrado em:** 11/08/2026, na verificação do turno da noite (operador de volta).
- **Categoria:** I (testes/CI) — **Severidade sugerida:** P3
- **Onde:** branch `feat/f2-ui-financeiro` @ `ddd13ff`, suíte completa (`vitest run`).
- **O que aconteceu:** a **primeira** execução da suíte, logo após `git checkout` do branch, terminou
  com `1 failed | 918 passed (919)`. As **quatro** execuções seguintes, no mesmo commit e no mesmo
  worktree, deram `919 passed` — inclusive uma com `node_modules/.vite` e `.vitest` apagados.

- **O nome do teste NÃO foi capturado, e isso é falha minha de instrumentação.** O comando daquela
  primeira rodada filtrava só as linhas de total (`grep "Test Files|Tests"`), então o bloco
  "Failed Tests" não entrou na saída. Quando fui buscar o nome, já não reproduzia. Registro sem o
  nome em vez de chutar qual foi.

- **Por que importa mesmo sendo intermitente:** teste que falha 1 em 5 no CI reprova merge por
  sorteio. Pior, ensina a reagir a vermelho com "roda de novo", que é como uma quebra real passa.

- **Hipótese, não conclusão:** as execuções mostram `environment` entre 90 s e 274 s — muito alto
  para 78 arquivos. Isso indica contenção de recurso na máquina (várias sessões de IA rodando
  suíte ao mesmo tempo neste repo), e o candidato mais provável é um `findBy*` estourando timeout
  sob carga, não um defeito de lógica. **Não verifiquei**, então fica como hipótese.

- **Como pegar da próxima vez:** rodar com saída completa em arquivo
  (`vitest run > saida.txt 2>&1`) em vez de filtrar no pipe, e considerar
  `vitest --retry=1` no CI **apenas** se vier acompanhado de relatório de flakes — sem o relatório,
  o retry esconde o problema em vez de medi-lo.

- **Não corrigido** (regra 3): a suíte do F2-UI não é o escopo da verificação da manhã, e mexer em
  teste alheio durante revisão de merge misturaria diffs.
## [NOVO-008] Os itens da OS continuam com preço unitário no mesmo embed que a tela do técnico usa

- **Encontrado em:** 11/08/2026, escrevendo a view do NOVO-006a
- **Categoria:** F — **Severidade sugerida:** P2 · **Status:** registrado, **não corrigido**
- **Descrição:** a view `service_orders_tecnico` tira as colunas de valor **da OS**, mas o detalhe da OS é
  lido com embed dos itens — `service_order_parts(*, products(*))` e `service_order_services(*, services(name))`
  (`src/hooks/use-service-orders.ts:25-35`). As duas tabelas de item têm `unit_price`/`total_price`, e
  `products(*)` traz o preço e o **custo** do produto. Ou seja: fechar a OS pelo lado da tabela-mãe deixa o
  preço de cada peça e de cada serviço passando pelo mesmo `select`, e o total é aritmética de somar.
- **Por que não corrigi junto:** a tarefa era a view de `service_orders`, e ampliar para três views mais os
  embeds correspondentes muda o desenho da consulta do detalhe — que é a tela mais usada do sistema — sem
  possibilidade de validar em banco na mesma janela.
- **Caminho sugerido:** views irmãs `service_order_parts_tecnico` e `service_order_services_tecnico` (mesmas
  colunas menos preço), e o `SO_DETAIL_SELECT` do técnico apontando para elas. Alternativa mais barata e
  menos completa: manter os embeds, mas pedir colunas nomeadas em vez de `*` no caminho do técnico.
- **Consequência prática enquanto não for feito:** a frase "o técnico não vê valores" continua sendo verdade
  só do total para cima. Quem quiser somar, soma.

---

## [NOVO-009] Preço de venda vira 3,6 × 10¹⁸ quando margem + imposto + comissão dão exatamente 100%

- **Encontrado em:** 11/08/2026, escrevendo a cobertura de teste de `price-calculator.ts`
- **Categoria:** A — **Severidade sugerida:** P2 · **Status:** registrado, **não corrigido** (regra 3)
- **Arquivo:linha:** `src/lib/price-calculator.ts:30-39` (o guard), `src/components/PriceCalculator.tsx:53-60`
  (o que faz o número escapar para o formulário)
- **Descrição:** a fórmula é `custo / (1 - margem - imposto - comissão)` e existe um guard para o caso
  impossível: `if (divisor <= 0) return zeros`. O problema é que, em ponto flutuante binário,
  `1 - 0.6 - 0.3 - 0.1` **não dá zero** — dá `2,7755575615628914e-17`, positivo. O guard não pega, a divisão
  acontece, e o preço de venda sai **3,6 × 10¹⁸**.
- **Depende da combinação, e é isso que torna difícil reproduzir pelo relato:**

  | margem + imposto + comissão | divisor calculado | resultado |
  |---|---|---|
  | 60 + 30 + 10 | `+2,78e-17` | **preço 3,6e18** |
  | 70 + 20 + 10 | `+2,78e-17` | **preço 3,6e18** |
  | 33,33 + 33,33 + 33,34 | `+5,55e-17` | **preço 1,8e18** |
  | 50 + 30 + 20 | `0` | zeros (correto) |
  | 40 + 40 + 20 | `-5,55e-17` | zeros (correto) |
  | 80 + 15 + 5 | `-4,16e-17` | zeros (correto) |

- **Por que não é só cosmético:** `PriceCalculator.tsx:53-60` sincroniza o preço calculado para o formulário
  do produto sempre que `breakdown.sale_price > 0`. O aviso de "preço impossível" aparece na tela **e o número
  astronômico já foi gravado no campo**. Quem salvar sem reparar leva o valor para o cadastro.
- **Correção sugerida (uma linha):** comparar com uma tolerância em vez de zero exato —
  `if (divisor <= 1e-9)` — ou calcular o divisor a partir da soma em pontos percentuais inteiros
  (`(100 - margem - imposto - comissão) / 100`), que erra menos por construção.
- **Cobertura:** `src/lib/price-calculator.test.ts` tem o caso marcado com `it.fails` e o comportamento atual
  documentado. Quando a correção entrar, o `it.fails` passa a acusar e obriga a virar `it()`.

---

## [NOVO-010] Deslocamento: 4 técnicos custam menos que 3, e a tarifa por km exibida na OS não é a usada no cálculo

- **Encontrado em:** 11/08/2026, escrevendo a cobertura de teste de `displacement.ts`
- **Categoria:** A — **Severidade sugerida:** P2 · **Status:** registrado, **não corrigido** (regra 3)
- **Arquivo:linha:** `src/lib/displacement.ts:59` e `:79-93`; `src/components/ServiceOrderForm.tsx:344,634,695`

**(a) A tarifa por hora despenca fora da faixa 1–3.** A tabela é `{1: 90, 2: 170, 3: 250}` e a busca é
`rates.hourly[technician_count] || rates.hourly[1]`. Com **4 técnicos**, a hora cai para **R$ 90** — menos do
que com 1... e menos da metade do que com 3. Com `0` ou negativo, idem. O número de técnicos é campo livre no
formulário da OS, então basta digitar 4. O `||` também engole um eventual `0` legítimo na tabela.
**Sugestão:** usar a maior faixa disponível quando o número passar do teto (`hourly[min(n, 3)]`), ou uma
tarifa por técnico adicional — é decisão comercial, não técnica.

**(b) `calculateDisplacement` ignora as tarifas da empresa.** Ela chama `calculateTravelCost` **sem passar
`rates`**, então usa `DEFAULT_TRAVEL_RATES` — mesmo quando `app_settings` tem valores diferentes. E devolve
`cost_per_km: 1.10` **fixo em código**, que o formulário grava na OS (`ServiceOrderForm.tsx:695`). Hoje o
padrão e a configuração coincidem em 1,10, então ninguém percebe; **no dia em que o dono mudar
`travel_km_rate` na tela de configurações, o botão de calcular deslocamento continuará cobrando 1,10.** O
mesmo formulário já monta `travelRatesFromSettings(appSettings)` para o cálculo manual (`:128-130`) — é passar
o mesmo objeto adiante.

**(c) Duas chaves para a mesma ideia, com valores diferentes, em produção.** `app_settings` tem
`travel_km_rate = 1.10` **e** `travel_cost_per_km = 3.50`. O código só lê a primeira; a segunda não é lida por
ninguém (`grep` em `src/` e `supabase/functions/`) — mas existe também uma **coluna** `travel_cost_per_km` em
`service_orders`, cujo default no formulário é **3,5** (`:344,634`). Ou seja, o campo "custo por km" gravado na
OS pode dizer 3,50 enquanto o total foi calculado a 1,10. **Sugestão:** decidir qual é a chave verdadeira,
apagar a outra e fazer o formulário gravar a mesma tarifa que usou na conta.

---

## [NOVO-011] Importação de CSV: preço com separador de milhar vira centavos, e "Telefone" vazio apaga o celular

- **Encontrado em:** 11/08/2026, escrevendo a cobertura de teste de `import-detector.ts`
- **Categoria:** A — **Severidade sugerida:** P1 (a) / P2 (b) · **Status:** registrado, **não corrigido** (regra 3)
- **Arquivo:linha:** `src/lib/import-detector.ts:170-178` (a) e `:142-143` + `:194-201` (b);
  entrada pela tela `src/components/ImportWizard.tsx:86-116`

**(a) `1.234,56` é importado como `1.23`.** A conversão é
`parseFloat(str.replace(',', '.'))` — `replace` com string troca **só a primeira ocorrência** e nada remove o
ponto de milhar. `"1.234,56"` vira `"1.234.56"`, e `parseFloat` para no segundo ponto: **1.234**. Vale para
`sale_price`, `cost_price` e `default_price`. O mesmo em `stock_quantity`/`minimum_stock` com `parseInt`:
`"1.500"` unidades entram como **1**.
  - **Por que é P1:** é uma carga em lote. O erro entra em centenas de linhas de uma vez, já gravadas,
    misturadas às certas — e um preço de R$ 1,23 no catálogo não parece "erro de importação", parece cadastro
    errado. Só aparece quando alguém vender por esse valor.
  - **Correção sugerida:** normalizar antes de converter — remover separador de milhar e trocar a vírgula
    decimal (`str.replace(/\./g, '').replace(',', '.')` quando o padrão for pt-BR), decidindo o formato pelo
    último separador encontrado. Precisa cuidar do caso inverso (`1,234.56` em arquivo en-US).

**(b) Duas colunas mapeadas para `phone`, e a segunda sobrescreve a primeira mesmo vazia.** O mapeamento de
clientes tem `'Celular': 'phone'` **e** `'Telefone': 'phone'`. `applyMapping` percorre o mapeamento em ordem e
atribui sempre: se o cadastro tem celular e não tem telefone fixo, o `Telefone` vazio vira `null` e **apaga o
celular já lido**. É justamente o número que serve para WhatsApp.
  - **Correção sugerida:** só sobrescrever quando o novo valor não for nulo/vazio (`mapped[t] ??= valor`), ou
    mapear celular e fixo para campos distintos.

**Cobertura:** `src/lib/import-detector.test.ts` documenta os dois comportamentos com o ID no nome do caso —
como registro do que acontece hoje, não como aprovação. Quando a correção entrar, esses casos falham e obrigam
a atualizar a expectativa junto.

---

## [NOVO-012] Captura rápida da Agenda: quantidade vira horário, e data inexistente vira outro ano

- **Encontrado em:** 11/08/2026, escrevendo a cobertura de teste de `quick-task-parser.ts`
- **Categoria:** A — **Severidade sugerida:** P2 (a) / P3 (b) · **Status:** registrado, **não corrigido**
- **Arquivo:linha:** `src/lib/quick-task-parser.ts:61-69` (a) e `:47-56` (b)

**(a) "comprar 3 cabos" vira uma tarefa das 03:00 chamada "comprar cabos".** O reconhecimento de hora aceita
qualquer número solto de 0 a 23 (`/\s(?:[àa]s\s+)?(\d{1,2})(?:[:h](\d{2}))?h?\s/`), sem exigir o `h`, os dois
pontos ou o "às". Numa captura rápida, número solto quase sempre é **quantidade**, não horário. O estrago é
duplo: aparece um horário que ninguém pediu **e** some do título o dado que importava. "comprar 10
disjuntores" → 10:00, "comprar disjuntores".
  - **Correção sugerida:** exigir marcador de hora — `h`, `:` ou o prefixo "às"/"as". Número puro só seria
    hora se estivesse no começo do texto (`"14 ligar pro João"` é raro; `"comprar 3 cabos"` não).

**(b) `30/02` vira 02/03 do ano seguinte, sem aviso.** `new Date(2026, 1, 30)` não é inválida — o JavaScript
normaliza para 2 de março. A checagem `Number.isNaN(cand.getTime())` nunca dispara. Como a data normalizada já
passou, a regra do "se passou, é do ano que vem" empurra para **2027**: a tarefa nasce a mais de um ano de
distância. Mesmo caminho para `31/11`.
  - **Correção sugerida:** conferir depois de construir se `getDate()`/`getMonth()` batem com o que foi
    digitado; se não, tratar como "sem data" e deixar o texto no título.

**Cobertura:** `src/lib/quick-task-parser.test.ts` documenta os dois com o ID no nome do bloco, junto de 20
casos do comportamento correto (hoje/amanhã, dia da semana indo para a próxima ocorrência, dd/mm com e sem
ano, hora nas quatro formas, prioridade, limpeza do título).

---

## [NOVO-013] Exportação de CSV: coluna "Marina" repete o nome do barco, aspas mal escapadas e injeção de fórmula

- **Encontrado em:** 11/08/2026, escrevendo a cobertura de teste de `export-utils.ts`
- **Categoria:** A (a, b) / G-segurança (c) — **Severidade sugerida:** P2 (a) / P3 (b) / P2 (c)
- **Status:** registrado, **não corrigido** (regra 3)
- **Arquivo:linha:** `src/lib/export-utils.ts:80` (a), `:20-21` (b), `:16-23` (c)

**(a) No export de embarcações, a coluna "Marina" lê a chave `name`** — que é o nome da **embarcação**. A
planilha sai com o nome do barco repetido em duas colunas e **nenhuma informação de marina**. Provável
copiar-e-colar: as duas entradas são `key: 'name'`. A correção depende de como a consulta traz a marina
(`marinas.name` embedado precisaria de uma chave própria ou de um `transform`).

**(b) Aspas são escapadas mas o campo não é envolvido.** `str.replace(/"/g, '""')` roda sempre, e o envelope
`"…"` só é aplicado quando há `;` ou quebra de linha. Um produto chamado `cabo "flex" 6mm` chega ao Excel como
`cabo ""flex"" 6mm`. **Correção:** envolver sempre que a string contiver aspas, além de `;` e `\n`.

**(c) Injeção de fórmula (CSV injection).** Nenhum campo é neutralizado, então um valor de cadastro que
comece com `=`, `+`, `-` ou `@` é interpretado como **fórmula** ao abrir a planilha. O conteúdo vem do
usuário (nome, notas, endereço) e o arquivo **sai da empresa** — vai para o contador, para o cliente, para
outro sistema. **Correção usual:** prefixar com apóstrofo (`'`) ou envolver em aspas com um caractere neutro
antes do sinal, quando o valor começar com um desses quatro.

**Cobertura:** `src/lib/export-utils.test.ts` — 14 casos, sendo os três acima marcados com o ID.
