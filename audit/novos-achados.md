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

## [NOVO-024] Deslocamento: 4 técnicos custam o mesmo que 1, e a tarifa por km exibida na OS não é a usada no cálculo

- **Encontrado em:** 11/08/2026, escrevendo a cobertura de teste de `displacement.ts`
- **Categoria:** A — **Severidade sugerida:** P2 · **Status:** registrado, **não corrigido** (regra 3)
- **Arquivo:linha:** `src/lib/displacement.ts:59` e `:79-93`; `src/components/ServiceOrderForm.tsx:344,634,695`

**(a) A tarifa por hora despenca fora da faixa 1–3.** A tabela é `{1: 90, 2: 170, 3: 250}` e a busca é
`rates.hourly[technician_count] || rates.hourly[1]`. Com **4 técnicos**, a hora cai para **R$ 90** — o mesmo
que se fosse **um** técnico, e 36% do que custam 3. Com `0` ou negativo, idem. O número de técnicos é campo livre no
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

## [NOVO-017] Importação de CSV: preço com separador de milhar vira centavos, e "Telefone" vazio apaga o celular

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

## [NOVO-018] Captura rápida da Agenda: quantidade vira horário, e data inexistente vira outro ano

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

## [NOVO-019] Exportação de CSV: coluna "Marina" repete o nome do barco, aspas mal escapadas e injeção de fórmula

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

---

## [NOVO-020] A view do técnico não pode ser ativada como está — dois bloqueios, um deles apaga dado

- **Encontrado em:** 11/08/2026, na revisão pré-merge do `NOVO-006a` (revisores independentes)
- **Categoria:** A — **Severidade sugerida:** **P1 se ativada** · **Status:** registrado, **não corrigido**
- **Arquivo:linha:** `src/hooks/use-service-orders.ts:34`, `src/components/ServiceOrderForm.tsx:610-660,774,805`

Com `VIEW_TECNICO_DISPONIVEL = false` e a migration não aplicada, **nada disso acontece hoje**. Os dois
bloqueios só disparam ao ligar a chave — e os 5 passos de ativação que eu documentei **não cobrem nenhum dos
dois**. Enquanto não forem resolvidos, a chave não pode ser virada.

**(a) O detalhe da OS falha inteiro para o técnico.** `SO_DETAIL_SELECT` pede
`payment_condition_presets(*)`, e eu removi `payment_condition_preset_id` da view — é coluna de condição de
pagamento. Sem a FK, o PostgREST não consegue inferir o relacionamento e responde **400 PGRST200**, o que
derruba a consulta inteira (não só o embed). `ServiceOrderDetail` cai no ramo de erro e mostra "Erro ao
carregar ordem de serviço" em **100% das OSs** — a tela de trabalho do técnico. É a mesma classe de defeito já
registrada em memória: no PostgREST, um embed impossível não volta vazio, volta erro.

**(b) Pior: salvar a OS como técnico apagaria os campos financeiros.** `ServiceOrderForm` semeia o formulário
com `d.<campo> || <default>` (`:610-660`) e o Salvar envia o formulário **inteiro**
(`const { signed_at, ...formForSave } = form` → `:774` e `:805`). Lendo da view, os campos que ela não traz
chegam como `undefined`, viram `0`/`''`/`3.5` no form, e o UPDATE **grava esses zeros na tabela base**:
`discount_amount`, `tax_amount`, `subcontract_cost_total`, `commission_rate`, `commission_amount`,
`commissioned_user_id`, `payment_conditions`, `payment_condition_preset_id`, `financial_notes`,
`discount_services_pct`, `discount_parts_pct`, `travel_cost_per_km`. O técnico anota o serviço que executou,
clica em Salvar, e o desconto negociado com o cliente vira zero. Silenciosamente.

**Por que o compilador não pega:** o cast `.from(fonte as typeof OS_TABELA)` diz ao TypeScript que a resposta
tem todas as colunas da tabela. Ele foi posto para permitir compilar antes de a view existir, e o efeito
colateral é esconder exatamente esta classe de erro.

**Caminho de correção (não feito):** um `SELECT` próprio para o técnico, sem os embeds que dependem de coluna
removida; e o formulário do técnico precisa parar de reenviar campo que não leu — ou enviando apenas os campos
que ele pode editar, ou usando um formulário reduzido. Enquanto isso não existir, **a view fica aplicada e
sem uso** (inócua) ou a tarefa é revertida.

---

## [NOVO-021] Padrão dos PDFs: edição feita durante o "Salvar" é descartada, e a tela diz que salvou

- **Encontrado em:** 11/08/2026, na revisão pré-merge do MF-AUD-014
- **Categoria:** A — **Severidade sugerida:** P3 · **Status:** registrado, **não corrigido**
- **Arquivo:linha:** `src/pages/SettingsPage.tsx:1832` (`setDirty(new Set())`) e `:1870-1874` (checkboxes sem `disabled`)

Em `PdfDefaultsSection.salvar()`, o sucesso da mutation limpa o conjunto `dirty` **inteiro** — inclusive tipos
de documento marcados como alterados **depois** que o upsert já tinha partido. Os checkboxes não ficam
desabilitados durante o `isPending` (só o botão fica), então a janela é clicável: o round-trip da rede, que em
4G no celular é de segundos. Resultado: a tela mostra a opção desmarcada, sem indicador de pendência e com
Salvar desabilitado, enquanto o banco tem o valor antigo. Volta no reload.
**Correção sugerida (uma linha):** remover de `dirty` apenas as chaves efetivamente enviadas, ou passar
`disabled={updateSettings.isPending}` aos checkboxes.

---

## [NOVO-022] Toggles de PDF que não fazem o que o rótulo promete (três casos, dois pré-existentes)

- **Encontrado em:** 11/08/2026, na revisão pré-merge (NOVO-006b e T3.8)
- **Categoria:** A — **Severidade sugerida:** P3 · **Status:** registrado, **não corrigido**

1. **Na via de execução, os outros toggles ficam cinzas mas continuam valendo.** `PDFOptionsDialog.tsx:139`
   desabilita **todos** os demais quando "Via de execução" é marcada — inclusive os que não decidem valor
   nenhum. Mas o gerador continua lendo `showTerms` e `showProductImages` com `semValores = true`: quem quiser
   a folha de campo **sem** os termos não consegue desmarcar, e o bloco imprime assim mesmo.
   **Correção:** desabilitar só os toggles financeiros (o catálogo já sabe quais são).
2. **`showPaymentInstructions` não faz nada** (`pdf-generator.ts:1472`, pré-existente). Marcar e desmarcar não
   muda um byte do PDF; quem apaga o bloco de instruções é `showBankDetails`. O commit da T3.8 deu rótulo em
   inglês e teste de catálogo a um toggle morto.
3. **`showSignature` também não faz nada** (`pdf-generator.ts:1302`, pré-existente): o bloco de assinatura sai
   sempre, mesmo com a opção desligada.

**Consequência comum:** a tela de padrão da empresa (nova) agora **oferece** essas opções ao dono. Configurar
algo que não tem efeito é pior do que não oferecer.

---

## [NOVO-023] O guarda anti-drift do hash de assinatura lê um arquivo só, e vai ficar verde quando o trigger mudar

- **Encontrado em:** 11/08/2026, na revisão pré-merge da cobertura de teste
- **Categoria:** I — **Severidade sugerida:** P3 · **Status:** registrado, **não corrigido**
- **Arquivo:linha:** `src/lib/document-hash.test.ts:145`

O bloco que cobra paridade entre o hash e o trigger procura a migration **pelo nome** (`f41d70d9`, a de
abril). Se alguém acrescentar um campo ao trigger **numa migration nova** — que é como o trigger seria
alterado — o teste continua lendo o arquivo antigo, extrai os mesmos 14 campos, todos passam, e a suíte fica
verde. O cenário que o teste diz impedir passa direto.
**Correção sugerida:** varrer todas as migrations e usar a definição **mais recente** de
`detect_so_change_after_signature`, como já faz o teste de status da OS com o `CHECK`.
## NOVO-010 — Tool `emitir_nfse_da_os` do agente ainda não existe

- **Origem:** [F-NFSE-01] sub-tarefa 5, declarada FORA DE ESCOPO na própria tarefa.
- **Situação:** a NFS-e já pode ser emitida a partir de uma OS pela edge function
  (`document_type: "nfse"` + `service_order_id`), mas o agente de IA não tem tool para isso.
  Hoje ele sabe emitir NF-e (`emitir_nfe_da_os`) e, quando a OS tem mão de obra, avisa que
  "a NFS-e ainda não está disponível" — frase que passa a ser falsa.
- **Por que importa:** o aviso desatualizado é pior que a ausência da tool; ele afirma ao
  dono que uma capacidade não existe quando ela existe.
- **Sugestão:** tool espelhando `emitir_nfe_da_os`, com o mesmo gate de risco (sim + PIN),
  e atualizar a frase do resumo da NF-e.

## NOVO-011 — Serviços sem cadastro fiscal (243 de 243)

- **Origem:** [F-NFSE-01], medido em 10/08/2026.
- **Situação:** os 243 serviços ativos têm `national_tax_code`, `cnae` e `iss_rate` NULOS, e
  `company_fiscal_settings.nfse_total_tax_rate_sn` está vazio. A infraestrutura de emissão
  está pronta e não há um único serviço emitível.
- **Por que importa:** o prazo da NFS-e é 01/09/2026, e nenhum desses valores pode ser
  inferido por software — código de tributação errado declara à prefeitura um serviço que
  não foi prestado, e o percentual do Simples só a contabilidade sabe.
- **Sugestão:** levantar com a contabilidade o código nacional + CNAE + alíquota dos
  serviços mais faturados e o percentual da faixa do Simples, antes de qualquer teste de
  emissão. Não é trabalho de código.

## NOVO-012 — "MÃO DE OBRA" de R$ 12.000 classificada como `logistica`

- **Origem:** [F-NFSE-02], levantamento de 10/08/2026.
- **Situação:** o serviço "MÃO DE OBRA" (R$ 12.000, terceira maior linha de faturamento de serviço nos
  últimos 12 meses) está com `service_verb = 'logistica'` e `service_system = 'nenhum'`.
- **Por que importa:** o backfill fiscal proposto usa `service_verb` como chave. Se a classificação
  estiver errada, o código de tributação sai errado junto — e são R$ 12 mil declarados à prefeitura
  como outra atividade. Ninguém confere código de tributação depois da nota autorizada.
- **Sugestão:** conferir a classificação deste serviço (e a `classification_confidence` do catálogo)
  ANTES de aplicar qualquer backfill por verbo. Não corrigi: classificação é decisão de quem conhece
  o serviço prestado.

## NOVO-013 — 34 linhas de serviço em OS sem `service_id`

- **Origem:** [F-NFSE-02], últimos 12 meses.
- **Situação:** de 122 linhas de serviço em OS, 34 são digitadas à mão e não apontam para o catálogo.
- **Por que importa:** nenhum backfill de cadastro fiscal as alcança. Na emissão de NFS-e elas vão
  exigir preenchimento manual de código/CNAE/ISS toda vez, ou impedir a emissão.
- **Sugestão:** avaliar se viram serviço de catálogo ou se a tela de emissão precisa de um caminho
  para serviço avulso com código informado na hora.

## NOVO-014 — `services.iss_withheld` não consegue herdar do verbo

- **Origem:** [F-NFSE-03], implementação do resolvedor fiscal, 11/08/2026.
- **Situação:** a coluna é `boolean not null default false`. Como toda linha já tem `false`
  gravado, um `coalesce(s.iss_withheld, f.default_iss_withheld)` nunca alcançaria o verbo — a
  herança existiria no código e não valeria nada.
- **Por que importa:** retenção de ISS na fonte muda quem recolhe o imposto. Herdar errado
  declara retenção que não houve (ou omite a que houve), e é o tomador que responde.
- **O que travou a decisão:** distinguir "explicitamente sem retenção" de "nunca preenchido"
  exige dizer o que significam os `false` que já existem no catálogo. Isso é decisão de
  retenção tributária, não de schema.
- **O que fiz:** deixei `iss_withheld` FORA da herança — vale o valor do serviço, exatamente
  como hoje. Os outros quatro campos herdam normalmente. Está documentado na migration, no
  espelho TS e coberto por teste de paridade nos dois lados.
- **RESPONDIDO pelo gestor em 11/08/2026 — RESOLVIDO.** Nenhum `false` atual foi decisão: o
  cadastro fiscal nunca foi preenchido (em 10/08 os 243 serviços ativos tinham
  `national_tax_code`, `cnae` e `iss_rate` todos nulos), e o `false` veio do DEFAULT da coluna.
  Aplicado na mesma migration, que ainda não tinha ido para produção:
  - `services.iss_withheld` virou **nullable**, sem default;
  - os `false` existentes viraram **NULL** — mas só nas linhas que continuam sem nenhum campo
    fiscal preenchido, para o caso de alguém já ter marcado retenção de propósito;
  - a resolução passou a ser **`COALESCE(serviço, verbo, false)`**, nos dois lados;
  - `service_fiscal_verbs.default_iss_withheld` virou **`not null default false`**: o verbo é o
    piso da herança e precisa sempre responder algo, senão o `false` final seria alcançado sem
    ninguém ter decidido — o mesmo buraco, um nível acima.
  - Quatro testes de paridade travam o comportamento, inclusive a **ordem** das instruções na
    migration (soltar o NOT NULL antes do UPDATE) e a salvaguarda do UPDATE.

---

## [NOVO-025] Colisão de ID: o turno noturno usou NOVO-016 para o deslocamento

- **Encontrado em:** 12/08/2026, integrando `session/noturno-20260811`.
- **Situação:** o turno de 11→12/08 usou **NOVO-016** para o defeito do deslocamento, porque
  era o ID vigente na ordem de serviço que recebeu. Enquanto ele trabalhava, a `main` foi
  renumerada: hoje **NOVO-016 é o teste intermitente do F2-UI** e o deslocamento é
  **NOVO-024**. O commit `070d988` e o livro `audit/relatorio-noturno-20260811.md` ficaram
  com a referência antiga, e ambos já estão na main.
- **Por que importa:** é exatamente o que a regra 2 do CLAUDE.md existe para evitar — daqui
  a meses, procurar "o que foi feito no NOVO-016" devolve duas coisas diferentes.
- **NÃO corrigido de propósito:** reescrever mensagem de commit já publicado exige
  `--force`, que é proibido aqui; e editar o livro do turno apagaria o registro de como as
  coisas de fato aconteceram. **A correção certa é esta anotação**, que liga os dois IDs.
- **Equivalência para quem for procurar:** `NOVO-016` no branch `session/noturno-20260811` e
  no commit `070d988` **=** `NOVO-024` na main.

---

# Tarefas abertas pelas decisões do dono (12/08/2026)

As quatro decisões do livro noturno foram respondidas. **Nenhuma foi implementada hoje** —
cada uma vira tarefa própria, por ordem do dono.

## [TAREFA] NOVO-import-01 — célula não numérica NUNCA vira preço 0
- **Decisão:** importar como `null` e emitir **relatório de conferência com o número da
  linha**; a importação segue nas linhas válidas.
- **Por que:** `0` é um preço que parece válido — entra no campo, salva no produto e sai numa
  proposta. Hoje `"sob consulta"` vira `0` calado (`import-detector.ts`, `transformValue`).
- **Escopo estimado:** ~meio dia. Mexe em `transformValue` (retornar `null`), no contrato de
  `applyMapping` e no passo de conferência do `ImportWizard`, que já existe.
- **Cuidado:** o campo é `not null` no banco? Conferir antes — pode exigir decisão adicional
  sobre gravar `null` ou segurar a linha.

## [TAREFA] Extrair `MULTIPLICADOR_SUSPEITO` com comentário
- **Decisão:** manter **20×**, como **aviso e nunca bloqueio**.
- **Situação:** já está extraído como constante exportada em `price-calculator.ts`, com o
  comentário explicando o porquê. **Esta tarefa está cumprida pelo commit `d16da5b`** — fica
  registrada só para fechar o ciclo da decisão.

## Decisões que confirmaram o comportamento atual (nada a fazer)
- **`"1.500"` = mil e quinhentos.** Formato brasileiro, caso comum. Já é o comportamento
  desde `e0a7c85`, e há teste travando.
- **4º técnico = R$ 330** por extrapolação linear do passo configurado. Já é o comportamento
  desde `070d988`, com teste. Tabela explícita (`travel_hourly_4..6`) só se doer na prática.

---

## [TAREFA AGENDADA] Reconstrução do histórico de migrations via `db pull` — DEPOIS de 01/09

- **Origem:** decisão do dono em 12/08/2026, ao escolher o caminho A para a migration da NFS-e.
- **Por que existe:** `supabase db push` está inutilizável neste projeto (ver MF-AUD-058
  corrigido e a regra 1 do CLAUDE.md). Hoje se contorna aplicando por
  `db query --linked -f` + registro manual da versão. Contorno funciona, mas **o repositório
  não reconstrói a produção** — e entre as 159 versões sem arquivo há uma correção de
  segurança de RLS que existe **apenas no banco** (MF-AUD-021).
- **Escopo:** `supabase db pull` para gerar os arquivos faltantes, conferência do que ele
  produz contra o schema real, e decisão sobre as 114 versões não registradas.
- **NÃO É CAMINHO CRÍTICO, e a ordem importa:** a NFS-e tem prazo regulatório de 01/09 e
  depende de contabilidade e prefeitura, que são latência de terceiros. A limpeza do
  histórico não tem prazo externo e não pode roubar a janela da NFS-e.
- **Exige janela própria e revisão:** mexe em 159 registros de produção, várias horas, e uma
  hipótese errada aqui é pior que a deriva atual — que ao menos é conhecida e documentada.
- **O que NÃO fazer:** `supabase migration repair --status reverted`, que o próprio CLI
  sugere. Marcaria como revertidas 154 migrations que de fato rodaram — escrever no histórico
  que algo não aconteceu, quando aconteceu.

---

## Varredura noturna da frente Levantamento — 15/08 → 16/08

Registrados conforme a regra 3 (não corrigidos) e numerados conforme a regra 8
(`NOVO-lev-NN`). O código desta frente é recente e pouco exercitado em campo;
esta varredura lê o que foi escrito nos últimos dias procurando o que só
apareceria em uso.

### [NOVO-lev-01] A folha imprime as perguntas embaralhadas entre sistemas

- **Onde:** `src/lib/survey-sheet.ts`, `buildSurveySheetHtml`.
- **O quê:** `compose_survey_for_order` passou a devolver o campo `eixo` — de qual
  sistema ou verbo cada pergunta veio — e o comentário da função SQL diz, com todas
  as letras, que "a folha agrupa por isto". **A folha não agrupa.** Ela separa apenas
  por `price_impact` (o que muda o preço × o resto), então numa visita de avaliação
  com seis sistemas as perguntas saem intercaladas: elétrico, gás, instalação,
  logística, elétrico de novo.
- **Por que importa:** em campo se avalia um sistema de cada vez. Quem está no paiol
  olhando o banco de baterias não quer, entre duas perguntas de elétrico, uma sobre o
  cilindro de gás que está do outro lado do veículo. O documentado e o construído
  divergem, e quem confiar no comentário do SQL vai supor um agrupamento que não existe.
- **Consertar seria:** agrupar por `eixo` dentro de cada faixa de impacto, com
  subtítulo por sistema. O dado já chega na folha; falta só usá-lo.
- **Não corrigido:** fora do escopo da tarefa em que foi encontrado.

### [NOVO-lev-02] A folha em branco mente sobre o motivo

- **Onde:** `src/lib/survey-sheet.ts` (`fetchSurveySheetData`) e
  `src/components/service-orders/SurveyPanel.tsx` (`imprimirFolha`).
- **O quê:** nenhuma das cinco chamadas de `fetchSurveySheetData` verifica `.error`.
  Quando uma RPC falha, o Supabase devolve `data: null`, que vira `[]`, e a tela
  responde: *"Este serviço ainda não tem perguntas de levantamento aprovadas."*
- **Por que importa:** a mensagem é FALSA em todos os casos de erro — permissão
  negada, rede caída, função derrubada por uma migration. Manda quem está de saída
  para a tela de aprovação de perguntas, onde não há nada errado, enquanto o defeito
  real fica invisível. É a mesma classe que derrubou o PDF do sistema inteiro em
  05/08 e custou dois dias: erro engolido que vira mensagem errada.
- **Consertar seria:** propagar o erro de cada RPC e distinguir na tela "não há
  perguntas" de "não deu para buscar as perguntas: <causa>".
- **Não corrigido:** regra 3.

### [NOVO-lev-03] Uma consulta ficou fora do `Promise.all`

- **Onde:** `src/lib/survey-sheet.ts`, `fetchSurveySheetData`.
- **O quê:** a busca do nome do serviço (`service_order_services`) roda depois do
  `Promise.all`, serializada, quando poderia ir junto das outras cinco.
- **Por que importa:** pouco — é uma viagem a mais numa ação que já leva algumas
  centenas de milissegundos. Registrado por completude, não por urgência.
- **Não corrigido:** regra 3, e não vale a mexida sozinho.

### [NOVO-lev-04] Resposta pulada continua alimentando o dimensionamento

- **Onde:** `survey_cable_sizing` (migration `20260815110000`), nas seis leituras
  por papel (`corrente`, `comprimento`, `tensao`, `criticidade`, `casa_maquinas`,
  `feixe`).
- **O quê:** o filtro é `(a.numeric_value is not null or a.answer_value is not null)`.
  **Não há `and a.skipped_reason is null`.** Uma resposta marcada como "não consegui
  verificar" entra no cálculo se tiver qualquer valor gravado.
- **Como acontece na prática:** o técnico responde a corrente ("250"), depois volta
  e marca "não consegui ver" — porque descobriu que leu o valor errado. O upsert
  grava `skipped_reason`, mas **não apaga `numeric_value`**, porque o campo não vai
  no payload e o `ON CONFLICT DO UPDATE` só toca no que foi enviado. O 250 fica lá,
  e o dimensionamento continua calculando com um número que quem mediu retirou.
- **Por que importa:** este é o cálculo que decide bitola de cabo. Uma leitura
  retirada de propósito voltando pela porta dos fundos é pior que leitura nenhuma —
  a função inclusive responde `pronto: true`, dizendo que sabe o que não sabe.
- **A assimetria denuncia:** `survey_suggested_materials` FILTRA `skipped_reason is
  null` (linha 38 da migration `20260808120000`). As duas funções leem a mesma
  tabela com regras diferentes; a do material está certa.
- **Consertar seria:** somar `and a.skipped_reason is null` às seis leituras, e
  limpar `numeric_value`/`answer_unit` quando a resposta vira pulada.
- **Não corrigido:** regra 3. **É o mais grave desta varredura.**

### [NOVO-lev-05] Corrigir uma resposta pode sobrescrever OUTRA pergunta

- **Onde:** `src/components/service-orders/SurveyPanel.tsx` (`gravar`), com
  `onConflict: 'survey_id,seq'` em `use-service-survey.ts:276`.
- **O quê:** a resposta é gravada com `seq: idx + 1` — a POSIÇÃO na lista — e o
  upsert casa por `(survey_id, seq)`. A posição não é identidade: ela depende de
  quais perguntas estavam ativas no momento em que a lista foi montada.
- **Como acontece na prática:** um levantamento é aberto e respondido até a 9ª
  pergunta. Uma pergunta nova de impacto ALTO é aprovada — e ela entra em terceiro
  lugar, porque a ordem é por impacto no preço. O levantamento é reaberto para
  completar; agora a 3ª posição é outra pergunta, e responder ali **sobrescreve a
  resposta que estava no seq 3**. A original some sem aviso.
- **Por que isso é plausível aqui, e não teórico:** há 18 perguntas aguardando
  aprovação neste momento, e várias são de impacto alto — exatamente as que entram
  no começo da lista. Aprovar perguntas enquanto há levantamento aberto é o curso
  normal desta frente.
- **Consertar seria:** casar por `(survey_id, template_id)` — que é a identidade
  real — mantendo `seq` apenas como ordem de exibição. Exige índice único novo e
  cuidado com as respostas de `template_id` nulo (as lançadas pela folha antiga).
- **Não corrigido:** regra 3, e a correção mexe em chave de tabela com dados.

### [NOVO-lev-06] Material lançado pelo levantamento não mexe no total da OS

- **Onde:** `apply_survey_materials` (migration `20260806100000`), chamada por
  `src/hooks/use-survey-material-rules.ts` (`useApplySurveyMaterials`) e
  `src/components/service-orders/SuggestedMaterialsPanel.tsx`. Mesmo defeito em
  `src/components/service-orders/RelatedMaterialsPanel.tsx` (`useAddRelated`).
- **O quê:** as duas rotas inserem em `service_order_parts` e **ninguém recalcula
  o total da ordem**. Conferido no banco: os únicos gatilhos da tabela são
  `parts_reservation` (reserva de estoque), `trg_warranty_parts` (validade de
  garantia) e `update_service_order_parts_updated_at`. Nenhum chama
  `recalc_so_totals`. E nenhuma das duas rotas chama `recalcTotals` do frontend.
- **Qual é o caminho certo, para comparar:** `use-service-order-parts.ts:93` —
  toda edição de peça chama `recalcTotals(service_order_id)` logo depois de
  gravar, dentro de um `try/catch` que **desfaz a alteração** se o recálculo
  falhar. `ServiceOrderForm` faz o mesmo. Quem entrou por este caminho novo
  não herdou nada disso.
- **Por que importa:** a peça aparece na lista e o orçamento continua com o valor
  de antes. Não há erro, não há aviso. O número volta ao lugar sozinho na próxima
  vez que alguém editar qualquer linha ou salvar o formulário — de modo que o
  total "muda sozinho" depois, sem ninguém ter mexido em preço. É a mesma classe
  de defeito de `MF-AUD-009` (o agente alterava a OS por uma rota sem cascata) e
  reaparece aqui por uma rota nova.
- **Consertar seria:** chamar `recalcTotals` no `mutationFn` das duas rotas, com o
  mesmo padrão de reversão do `use-service-order-parts`. Ou — melhor, porque fecha
  a classe inteira — um gatilho `after insert or update or delete` em
  `service_order_parts` chamando `recalc_so_totals`; mas isso é decisão de
  arquitetura, porque a aritmética de hoje vive no frontend
  (`receivable-redistribution.ts`) e é ela que checa o piso do que o cliente já
  pagou.
- **Não corrigido:** regra 3, e a correção certa é a decisão acima.

### [NOVO-lev-07] A tela não atualiza porque a invalidação usa chaves que não existem

- **Onde:** `src/hooks/use-survey-material-rules.ts:85-87` e
  `src/components/service-orders/RelatedMaterialsPanel.tsx:68-70`.
- **O quê:** as duas invalidam `['service-order-parts', id]` e `['service-order', id]`.
  As chaves reais do repositório são **`['so-parts', id]`** (`use-service-orders.ts:307`)
  e **`['service-orders', id]`** (`use-service-orders.ts:52`) — plural em uma,
  nome diferente na outra. `invalidateQueries` com chave inexistente não é erro:
  não casa com nada e devolve sucesso.
- **Por que importa:** somado ao `NOVO-lev-06`, o clique em "Lançar" produz um
  toast de sucesso e **nada visível muda** — nem a lista de peças, nem o total.
  Quem confere lê aquilo como "não funcionou" e clica de novo; aí a trava de
  duplicata responde *"Nada novo a lançar — esses materiais já estavam no
  orçamento"*, que contradiz a tela que ele está vendo. Os itens só aparecem
  depois de recarregar a página.
- **Consertar seria:** trocar pelas duas chaves reais. É uma linha em cada arquivo.
- **Não corrigido:** regra 3 — mas é o achado de menor custo de correção desta
  varredura, e o de sintoma mais visível.

### [NOVO-lev-08] "Já estavam no orçamento" também é dito quando nada foi lançado por falta de número

- **Onde:** `apply_survey_materials` (migration `20260806100000`), o `case` da
  mensagem de retorno.
- **O quê:** o `insert ... select` descarta a linha por três motivos diferentes —
  `quantity is null`, `quantity <= 0` e produto já lançado neste orçamento — e
  todos caem no mesmo `v_criadas = 0`, que responde *"Nada novo a lançar — esses
  materiais já estavam no orçamento."*
- **Como acontece na prática:** a sugestão vem marcada com o alerta *"a resposta
  não tem número — confira a quantidade"* (a própria função já avisa disso), quem
  confere marca a linha assim mesmo e manda lançar. A quantidade é nula, a linha é
  descartada, e a resposta afirma que o material já estava lá — quando não está e
  não vai estar.
- **Por que importa:** a mensagem manda parar de procurar. Quem a lê não volta
  para corrigir a resposta do levantamento, que é exatamente o que precisaria
  fazer. O `SuggestedMaterialsPanel` já desmarca sozinho a linha com alerta, o que
  reduz a frequência — não elimina, porque marcar de volta é um clique.
- **Consertar seria:** contar os descartados por motivo (`count(*) filter (where
  m.quantity is null)`, etc.) e dizer qual foi. A função já tem a lista em mãos.
- **Não corrigido:** regra 3.

### [NOVO-lev-09] A trava de duplicata não enxerga o que a própria instrução está inserindo

- **Onde:** `apply_survey_materials`, o `not exists (...) x.source = 'survey'`.
- **O quê:** a subconsulta anti-duplicata lê `service_order_parts` no instantâneo
  do início da instrução. Duas regras selecionadas na mesma chamada apontando para
  o **mesmo produto** passam as duas, porque nenhuma vê a linha que a outra está
  criando. Aplicadas em dois cliques, a segunda é barrada.
- **Por que é plausível aqui:** o cabo é o caso central desta frente, e o desenho
  natural é uma regra por trecho (banco→inversor, inversor→quadro), ambas
  apontando para o mesmo produto de cabo. Nesse desenho, o resultado depende de o
  usuário ter marcado as duas juntas ou uma de cada vez.
- **Efeito colateral do mesmo `not exists`, na direção oposta:** ele olha a ordem
  INTEIRA, sem considerar `service_order_service_id`. Dois serviços na mesma ordem
  que precisem do mesmo produto — dois bancos de bateria, dois inversores — só
  recebem material no primeiro, e o segundo fica silenciosamente sem.
- **Consertar seria:** trocar por `on conflict` sobre um índice único real, ou
  agregar por produto antes de inserir (`sum(quantity) group by product_id`), o
  que também resolveria o caso dos dois trechos de cabo virando uma linha só.
  Decidir se a unidade de duplicata é a ordem ou a linha de serviço é escolha de
  negócio.
- **Não corrigido:** regra 3.

### [NOVO-lev-10] O planejador de quebra ignora as margens — e o card ainda parte ao meio

- **Onde:** `src/lib/pdf-generator.ts:399-404` (a medição) e `src/lib/pdf-pagination.ts`
  (`planPageBreaks`).
- **O quê:** cada bloco é medido por `el.getBoundingClientRect().height`, que
  **não inclui margens**. O CSS do documento dá margem a quase todo bloco de topo:
  `.card { margin-bottom: 20px }` (`pdf-generator.ts:750`), `table { margin-bottom:
  16px }` (:766) e `.grid { margin-bottom: 20px }` (:792). A conta de "quanto já
  usei desta folha" fica menor que a realidade, e cresce a cada bloco.
- **Provado com os números reais do arquivo:** cinco cards de 200 px com os 20 px
  de margem do CSS. O planejador soma 1000 px, vê que cabe em 1032 e **não planeja
  quebra nenhuma**. As posições reais são `[0,200] [220,420] [440,640] [660,860]
  [880,1080]` — o quinto card termina em **1080**, 48 px além da folha, e o
  html2pdf o corta. É exatamente o defeito que este módulo existe para impedir
  (o card "Informações para Pagamento" partido ao meio), ainda alcançável.
- **Por que não aparece sempre:** o erro só morde quando a soma sem margens fica
  logo abaixo do limite e a soma com margens passa. Quanto mais blocos na folha,
  maior a chance — documento longo é justamente o que tem muitos.
- **Consertar seria:** medir a ocupação real. O jeito robusto não é somar
  `height + marginTop + marginBottom` (que erra no colapso de margens), e sim
  derivar a altura de cada bloco da diferença entre os topos dos irmãos
  consecutivos — que já inclui a margem efetiva —, usando o fim do container para
  o último.
- **Não corrigido:** regra 3.

### [NOVO-lev-11] Bloco mais alto que a folha zera a conta pelo lugar errado

- **Onde:** `src/lib/pdf-pagination.ts:101-104`.
- **O quê:** `if (altura > alturaUtil) { usado = altura % alturaUtil; continue; }`.
  A sobra é calculada como se o bloco alto começasse no topo de uma folha. Ele
  quase nunca começa: vem depois do cabeçalho, dos dados do cliente, do resumo.
  O certo é `(usado + altura) % alturaUtil`.
- **Provado:** blocos de 200, 3000, 250 e 300 px, folha de 1032. Sobra real depois
  do bloco de 3000 px = `(200+3000) % 1032` = **104 px**; o planejador calcula
  `3000 % 1032` = **936 px**. Com 936 "usados", o bloco de 250 px não caberia e o
  planejador **manda quebrar a página** — quando na realidade sobravam 928 px
  livres. Resultado: uma folha quase inteira em branco no meio do documento.
- **A direção contrária também existe:** com outros números o planejador acha que
  cabe quando não cabe, e aí o bloco é fatiado — o mesmo estrago do `NOVO-lev-10`.
- **O bloco alto é o caso comum, não o excepcional:** a tabela de itens de uma OS
  com muitas linhas passa de 1032 px sozinha, e nunca é o primeiro filho.
- **O teste existente passa porque evita o caso quebrado:**
  `pdf-pagination.test.ts:41` põe o bloco alto **como primeiro bloco** — onde
  `usado` é 0 e as duas fórmulas coincidem. Dá confiança falsa.
- **Consertar seria:** uma linha (`usado = (usado + altura) % alturaUtil`) mais um
  caso de teste com o bloco alto em segundo lugar.
- **Não corrigido:** regra 3.

### [NOVO-lev-12] `indivisivel` é medido, documentado — e nunca usado

- **Onde:** `src/lib/pdf-pagination.ts:72-80` (o tipo) e `:96` (o destructuring);
  `src/lib/pdf-generator.ts:403` (quem calcula).
- **O quê:** o chamador varre cada bloco com `el.classList.contains('card') ||
  !!el.querySelector('table')` para marcar o que não pode partir, e
  `planPageBreaks` desestrutura `indivisivel` e **não o lê em lugar nenhum**.
  Bloco indivisível e bloco comum seguem exatamente o mesmo caminho.
- **Por que importa:** não produz saída errada hoje — o comentário do código
  (`:111-113`) já explica que os dois descem inteiros de propósito. O problema é o
  contrário: o campo promete um comportamento no tipo e nos testes
  (`pdf-pagination.test.ts:28` passa `indivisivel: true` como se importasse), e
  quem for mexer vai supor que a distinção existe. Também custa um
  `querySelector('table')` por bloco em toda geração.
- **Consertar seria:** ou remover o campo, ou usá-lo — por exemplo, permitindo que
  um bloco DIVISÍVEL longo (texto corrido de termos) parta em vez de descer
  inteiro e deixar meia folha vazia.
- **Não corrigido:** regra 3.

### [NOVO-lev-13] `scopeCss` divide seletores por vírgula sem olhar parênteses

- **Onde:** `src/lib/css-scope.ts:34` (`seletores.split(',')`).
- **O quê:** a vírgula é tratada sempre como separador de seletores. Dentro de
  `:is()`, `:not()`, `:where()` ou de um `[attr="a,b"]` ela não é.
  `:is(h1, h2) { … }` sai como **`.pdf :is(h1, .pdf h2)`** — verificado rodando a
  função. O escopo entra dentro dos argumentos e o seletor passa a significar
  outra coisa.
- **Estado hoje:** **latente.** O CSS de `pageWrapper` não usa nenhum desses —
  conferi os 29 blocos de regra. Nada quebrado em produção agora.
- **Por que registrar mesmo assim:** este CSS é editado à mão sempre que o
  documento muda, e `:not()` é a primeira coisa que alguém escreve ao ajustar
  espaçamento de tabela ("todas as linhas menos a última"). O erro é silencioso:
  não lança, não avisa, só deixa de aplicar.
- **Conferido e SEM defeito, para não voltar a investigar:** o `@import` do Google
  Fonts, que tem `;` dentro da URL (`wght@400;500;600…`), atravessa a função
  intacto — o laço fatia em pedaços contíguos e reconcatena sem perda. E
  comentário com chave fora da posição 0 produz texto embaralhado que o
  navegador reinterpreta corretamente, porque o `.pdf` inserido cai sempre antes
  do `/*` ou dentro do comentário. Os dois foram testados.
- **Consertar seria:** dividir contando profundidade de parênteses e colchetes.
- **Não corrigido:** regra 3.

### [NOVO-lev-14] O portal público monta o PDF por conta própria — e é o documento que o CLIENTE baixa

- **Onde:** `src/pages/PublicServiceOrderView.tsx:211` (`buildPdfData`), contra
  `src/hooks/use-pdf.ts:58` (`carregarPDFData`).
- **O quê:** a unificação de 05/08 juntou `usePDFData` e `fetchPDFData` numa
  montagem só. Ficou de fora uma **terceira cópia**, escrita à mão, no portal
  público — que não chama nenhuma das duas e busca tudo de novo com o cliente do
  token (`sb`, `:89-118`).
- **O teste que deveria pegar isso nomeia justamente o portal:**
  `use-pdf-unico.test.ts:8` diz *"usePDFData (tela) e fetchPDFData (lote, anexo de
  WhatsApp, **portal público**)"* — e o teste só faz grep dentro de `use-pdf.ts`.
  Mesmo padrão de confiança falsa do `NOVO-lev-11`.
- **O que diverge, conferido campo a campo:**
  - `documentType` é **`'service_order'` fixo** (`:214`). **Hoje há 31 orçamentos
    em `draft` com link público** — conferido no banco. Todos os 31 são baixados
    pelo cliente com o cabeçalho **"Ordem de Serviço"** em vez de "Orçamento"
    (`pdf-generator.ts:1052`), com a seção chamada "Relato do Problema" em vez de
    "Objetivo do Projeto / Diagnóstico" (`:1185`) e o bloco de assinatura dizendo
    "Aceite do Serviço Realizado" em vez de "Aprovação do Orçamento" (`:1322`).
  - **A validade some.** `getValidityText()` só sai quando `isQuote`
    (`pdf-generator.ts:1276`), e `buildPdfData` nem passa `quote_validity_days`.
    Os **31 de 31** têm validade preenchida no banco. O cliente recebe um
    orçamento sem prazo de validade.
  - `logo_url` não é passado: o PDF do cliente sai **sem a logo**, o do ERP com.
  - Não passa `marina`, `expenses`, `survey`, `deposit_paid`, `receivables`,
    `payments`, `travel_hours`, `ferry_cost`, `travel_type`, `commission_*`,
    `financial_notes`, `payment_method_preferred`, `discount_services_pct`,
    `discount_parts_pct`. O levantamento e o sinal já pago **nunca chegam** ao
    documento que o cliente baixa.
  - Na direção contrária, passa `card_fee_amount` e `card_installments`, que
    `carregarPDFData` **não** monta. A taxa de cartão aparece no PDF do portal e
    não aparece no do ERP — o mesmo documento, dois valores.
  - `technical_notes` é passado e só é suprimido quando `isQuote`
    (`pdf-generator.ts:1256`). Com `isQuote` sempre falso, **nota técnica interna
    entra no orçamento do cliente**. Hoje nenhum dos 31 tem o campo preenchido —
    latente, mas o caminho está aberto.
- **Consertar seria:** o portal chamar `carregarPDFData` (o cliente do token serve
  para as mesmas tabelas) e derivar `documentType` de `documentTypeFor(status)`,
  que já existe em `src/lib/document-type.ts` e é exatamente para isto. E o teste
  de unificação passar a olhar `PublicServiceOrderView.tsx`.
- **Não corrigido:** regra 3. **É o achado de maior alcance desta varredura** —
  atinge o documento que sai da empresa.

### [NOVO-lev-15] O botão "Baixar PDF" do portal abre a janela de impressão

- **Onde:** `src/pages/PublicServiceOrderView.tsx:286` e `:425-426`.
- **O quê:** o botão tem ícone de download e o rótulo **"Baixar PDF"**, e chama
  `printPDF(...)` — que abre a janela de impressão do navegador. Nenhum arquivo é
  baixado.
- **Por que importa:** este link chega ao cliente por WhatsApp, e ele o abre no
  celular. Pedir "baixar" e receber a caixa de impressão do iOS é onde a pessoa
  desiste — ou imprime em papel um documento que queria guardar. Todos os outros
  botões de baixar do sistema usam `downloadPDF`.
- **Consertar seria:** trocar por `downloadPDF`, ou renomear o botão para
  "Imprimir" e acrescentar um de baixar de verdade.
- **Não corrigido:** regra 3.

### [NOVO-lev-16] Três consultas do PDF não checam erro, e cada fallback mente diferente

- **Onde:** `src/hooks/use-pdf.ts` — `settingsRes` (`:76`), `receivablesRes`
  (`:81`) e a de `payments` (`:96`). Só `soRes.error` é verificado (`:88`).
- **O quê:** cada uma tem um `|| []` ou `|| ''` que transforma falha em ausência.
- **O que sai do outro lado, por consulta:**
  - `app_settings` falha → `get()` devolve vazio em tudo. O documento sai com o
    nome **"MarineFlow"** (`:113`, o fallback literal), sem CNPJ, sem endereço,
    sem telefone, sem dados bancários e **sem termos** — e vai assim para o
    cliente, sem nenhum aviso na tela.
  - `receivables` falha → `depositPaid = 0`, `receivables: []`. O cliente que já
    pagou o sinal recebe um documento **sem registro nenhum do que pagou**.
  - `payments` falha → o histórico de pagamentos some, e a seção que existe para
    "mostrar o real" mostra vazio.
- **Por que não é teórico:** é a mesma classe que derrubou o PDF inteiro em 05/08
  e o `NOVO-lev-02` da folha de levantamento. Aqui o erro nem chega a derrubar:
  produz um documento plausível e errado, que é pior.
- **Consertar seria:** checar `.error` nas três e falhar com a causa, do mesmo
  jeito que `soRes` já faz.
- **Não corrigido:** regra 3.

### [NOVO-lev-17] A galeria de fotos do PDF lê uma coluna que nada escreve

- **Onde:** `src/hooks/use-pdf.ts:230` contra
  `src/components/ServiceOrderPhotos.tsx:75`.
- **O quê:** o PDF monta a "Galeria Técnica / Evidências do Serviço"
  (`pdf-generator.ts:1113`) a partir de `service_orders.photos` — uma coluna
  `jsonb`. **Nada no repositório escreve nessa coluna**: procurei em `src/`, nas
  edge functions e nas migrations. Quem sobe foto pela tela grava na **tabela**
  `service_order_photos`, que o PDF nunca lê.
- **Conferido no banco:** as 79 ordens têm `photos = []`, e
  `service_order_photos` tem 0 linhas. Ninguém subiu foto ainda — então isto não
  está errado hoje; está errado **a partir da primeira foto**, e do jeito mais
  difícil de perceber: a opção existe, a seção existe, e a galeria sai vazia.
- **E os dois leitores da coluna discordam da forma:** `use-pdf.ts:230` faz
  `photos.map(p => p.url)` (objetos), enquanto `PublicServiceOrderView.tsx:604`
  faz `photos.map((url: string) => …)` (strings) e o próprio
  `pdf-generator.ts:1117` espera string. Se a coluna algum dia for preenchida com
  strings, o PDF renderiza `<img src="undefined">`.
- **Consertar seria:** o PDF ler `service_order_photos` (a fonte real), e decidir
  o destino da coluna `photos` — usar ou remover, não as duas coisas pela metade.
- **Não corrigido:** regra 3.

### [NOVO-lev-18] Com mais de um levantamento fechado, o PDF escolhe um qualquer

- **Onde:** `src/hooks/use-pdf.ts:25` — `lista.find((s) => s?.status === 'closed')`.
- **O quê:** pega o **primeiro** fechado na ordem em que o PostgREST devolveu o
  embed, e o embed não pede ordenação nenhuma. Sem `order by`, a ordem não é
  garantida entre execuções.
- **Por que passou a ser plausível:** até 15/08 o levantamento era de um serviço;
  desde `compose_survey_for_order` ele é **da ordem**, e uma visita de avaliação
  que gera um segundo levantamento na mesma ordem é o fluxo desenhado. Dois
  fechados na mesma ordem deixa de ser exceção.
- **Estado hoje:** latente — há uma única ordem com levantamento no banco, e ele
  não está fechado.
- **Consertar seria:** ordenar por `answered_at desc` no embed e pegar o mais
  recente, ou respeitar `service_orders.survey_id`, que existe justamente para
  apontar o levantamento principal.
- **Não corrigido:** regra 3.

### [NOVO-lev-19] A folha impressa e a tela de lançamento montam perguntas diferentes

- **Onde:** `src/lib/survey-sheet.ts:436-440` contra
  `src/hooks/use-service-survey.ts:97` (`useSurveyQuestions`), usada por
  `SurveySheetEntryDialog.tsx:39`.
- **O quê:** são **duas composições distintas** para o mesmo levantamento.
  - A folha, quando há ordem, chama `compose_survey_for_order` com
    **`p_limit: 14`** — rodízio entre TODOS os sistemas e verbos das linhas da
    ordem (elétrico, gás, refrigeração).
  - A tela que lança a folha de volta chama `compose_survey_for_service`, que
    tem **`limit 9` fixo no SQL** e só olha UM serviço.
- **O que acontece com o papel preenchido:** o técnico volta com até 14 respostas
  e encontra na tela uma lista mais curta e **de outro conjunto**. As perguntas
  que ele respondeu no papel e não estão na tela **não têm onde ser lançadas** —
  a medida foi tomada e se perde. E as que estão na tela e não estavam no papel
  ficam em branco, e o código as grava com
  `skipped_reason: 'em branco na folha de campo'`
  (`SurveySheetEntryDialog.tsx:85`) — ou seja, registra como "não deu para
  verificar" uma pergunta que **nunca foi feita ao técnico**.
- **Por que isso é o pior tipo de erro aqui:** o levantamento inteiro existe para
  que o orçamento não seja chutado. Uma resposta perdida vira preço faltando; uma
  "não verificada" falsa vira contingência cobrada por algo que estava resolvido.
  Os dois estragos são silenciosos.
- **O `SurveySheetEntryDialog` já recebe `serviceOrderId`** (`:29`) e o usa para
  criar o levantamento — só não o usa para montar as perguntas.
- **Consertar seria:** a tela de lançamento usar a mesma composição da folha,
  com o mesmo limite. Melhor ainda: a folha gravar quais `template_id` imprimiu,
  e a tela lançar exatamente aqueles — o papel e a tela deixam de poder divergir.
- **Não corrigido:** regra 3, e a escolha entre "mesma RPC" e "folha carimba o
  conjunto" é decisão de desenho.

### [NOVO-lev-20] A frase pronta afirma a bitola mesmo quando o cálculo não fechou

- **Onde:** `supabase/functions/_shared/ai/tools/survey-ops.ts:400-402`
  (`como_dizer`) e `dc_cable_sizing` (migration `20260808100000`), no
  `mm2_minimo`.
- **O quê:** `mm2_minimo` é `greatest(coalesce(v_drop,0), coalesce(v_amp,0))`. Com
  a ampacidade indisponível, `v_amp` é nulo, o `coalesce` o transforma em **0**, e
  o máximo passa a ser só a queda de tensão — **a metade que sobrou vira o
  resultado**. Em seguida, `como_dizer` é montado com `r?.mm2_minimo ? …`, **sem
  olhar `pronto`**, e entrega ao modelo uma frase fechada.
- **Provado rodando a função em produção** (200 A, 1 m de trecho, 12 V, 10% de
  queda, isolação 105 °C, em casa de máquinas, feixe de 4 condutores):
  - `pronto: false`, `mm2_por_ampacidade: null` — nenhuma bitola cadastrada
    atende com o derating.
  - `mm2_minimo: **5.96**`.
  - `como_dizer` sai como: *"Para 200 A neste trecho, mantendo 10% de queda, o
    cabo precisa de no mínimo 5.96 mm²."*
- **Por que importa:** é ~6 mm² para 200 A. A `instrucao` logo abaixo manda
  "NUNCA apresente a bitola como fechada se 'pronto' for false" — mas a frase
  pronta já foi entregue, e frase pronta ganha de instrução. O módulo inteiro foi
  escrito com o princípio "meia conta nunca é apresentada como inteira"
  (comentário da própria migration), e este é o ponto em que ele é violado.
- **Consertar seria:** `mm2_minimo` só existir quando os dois critérios existirem
  (ou vir acompanhado de `mm2_minimo_parcial`, com outro nome), e `como_dizer`
  ser gerado apenas com `pronto === true` — nos outros casos, dizer o que falta.
- **Não corrigido:** regra 3. **É o achado mais grave da noite: erra para menos
  em dimensionamento de cabo, que é risco físico.**

### [NOVO-lev-21] Quatro das seis perguntas do dimensionamento estão inativas — e os padrões saem como se tivessem sido lidos

- **Onde:** `survey_cable_sizing` (migration `20260815110000`), no
  `jsonb_build_object('lido_do_levantamento', …)`.
- **Conferido no banco, hoje:** dos seis papéis que a função lê, só dois têm
  pergunta ativa —
  `corrente` ("Qual a corrente máxima do circuito, em ampères?") e
  `comprimento` ("Qual a distância do banco de baterias até o inversor?").
  **`tensao`, `criticidade`, `casa_maquinas` e `feixe` têm zero perguntas ativas**
  (uma cadastrada cada, todas aguardando aprovação).
- **O quê:** sem resposta, a função usa os padrões — 12 V, 3% de queda, fora de
  casa de máquinas, 1 condutor no feixe — e os devolve **dentro de uma chave
  chamada `lido_do_levantamento`**. Nada disso foi lido de levantamento nenhum.
- **A direção do erro não é a mesma nos quatro:**
  - `tensao = 12` e `queda = 3%` erram para MAIS (cabo mais grosso que o
    necessário num sistema de 24/48 V). Custa dinheiro, não segurança.
  - **`casa_maquinas = false` e `feixe = 1` erram para MENOS**: o derating de 0,7
    da casa de máquinas e o de feixe simplesmente não são aplicados, porque a
    pergunta que os acionaria não existe para ser respondida.
- **O tamanho do erro, medido:** 200 A, 1 m, 12 V, 10%. Como o sistema responde
  hoje: `mm2_por_ampacidade = 35`, `pronto = true`. Com casa de máquinas e feixe
  de 4: `mm2_por_ampacidade = null` — **nenhuma das cinco bitolas cadastradas
  atende**. O sistema devolve 35 mm² com `pronto: true` para um circuito cuja
  resposta honesta é "não sei".
- **Consertar seria:** aprovar as quatro perguntas (elas já existem, estão entre
  as 18 pendentes) e, enquanto não houver resposta, a função declarar o padrão
  como PADRÃO — chave `presumido`, não `lido_do_levantamento` — e derrubar
  `pronto` quando o que falta é derating.
- **Não corrigido:** regra 3. Ligado ao `NOVO-lev-20`: um produz o número errado,
  o outro o apresenta como certo.

### [NOVO-lev-22] A transcrição do papel não passa pela conferência de grandeza

- **Onde:** `src/components/service-orders/SurveySheetEntryDialog.tsx` — não
  importa `checkMeasure`; `SurveyPanel.tsx:112` importa e usa.
- **O quê:** a tela viva confere cada resposta de grandeza contra a unidade e a
  faixa esperadas e avisa "confira a vírgula e a unidade". A tela que transcreve
  a folha **não faz nenhuma conferência** — é um `<Input>` de texto puro.
- **Por que é justamente ali que faz falta:** na tela viva quem digita é quem
  acabou de medir e sabe o valor. Na transcrição, quem digita está **lendo a
  letra de outra pessoa** dias depois, e é aí que 2,5 vira 25 sem ninguém notar.
  A rede existe, está testada com 14 casos, e não cobre o caminho de maior risco.
- **Também não grava `numeric_value` nem `answer_unit`** — o número volta a ser
  garimpado do texto. Isso está previsto no comentário da migration
  `20260815110000` e é aceitável; o que não é aceitável é a ausência do aviso.
- **Consertar seria:** chamar `checkMeasure` por campo com `expectedUnit`/
  `minExpected`/`maxExpected` da pergunta, mostrar o aviso abaixo do campo (sem
  bloquear) e gravar `numeric_value` quando houver um número só.
- **Não corrigido:** regra 3.

### [NOVO-lev-23] Falha ao gravar as respostas deixa um levantamento órfão, e o botão cria outro

- **Onde:** `src/components/service-orders/SurveySheetEntryDialog.tsx:64-90`.
- **O quê:** `start.mutateAsync` cria o levantamento **antes** do insert das
  respostas. Se o insert falhar (rede, RLS, um `template_id` que saiu do ar entre
  abrir e lançar), o `catch` mostra o erro e **o levantamento fica no banco,
  aberto e vazio**. O diálogo continua aberto com tudo preenchido, e clicar
  "Lançar folha" de novo cria **mais um**.
- **Por que importa:** o levantamento vazio aparece na aba como se alguém tivesse
  começado um; e o `NOVO-lev-18` mostra que a escolha de qual levantamento vai
  para o PDF é por ordem não determinada — quanto mais registros soltos na mesma
  ordem, mais fácil o documento pegar o errado.
- **Consertar seria:** guardar o `surveyId` já criado num `ref` e reaproveitá-lo
  na nova tentativa, ou mover os três passos para uma RPC única (o insert, o
  fechamento e a criação numa transação só).
- **Não corrigido:** regra 3.

### [NOVO-lev-24] Corrigir a medida não corrige o número que o cálculo lê

- **Onde:** `src/components/service-orders/SurveyPanel.tsx:483-490` (o botão
  "corrigir") e `src/hooks/use-service-survey.ts:263-277` (`useAnswerSurvey`).
- **O quê:** a correção manda só `answer: correcao.trim()`. Não manda
  `numericValue` nem `answerUnit`. E o upsert monta o payload com spread
  condicional — `...(input.numericValue !== undefined && !== null ? { numeric_value } : {})` —,
  de modo que a coluna **não entra no `ON CONFLICT DO UPDATE`** e o valor antigo
  permanece.
- **O que acontece:** a resposta era `25` (vírgula errada, deveria ser `2,5`).
  Gravada pela tela viva, ficou `answer_value = '25'` e `numeric_value = 25`.
  Alguém percebe e corrige para `2,5`. Agora `answer_value = '2,5'` e
  **`numeric_value` continua 25**. O `survey_cable_sizing` lê
  `coalesce(numeric_value, parse_answer_number(answer_value))` — pega o 25. A
  tela mostra a resposta certa e o dimensionamento usa a errada.
- **Por que dói exatamente aqui:** o comentário que justifica esta UI
  (`SurveyPanel.tsx:464-468`) diz que ela existe para não *"deixar o número
  errado sustentando o preço"*. É a única função do botão, e é a única coisa que
  ele não faz.
- **E a correção também não passa por `checkMeasure`:** o aviso de "confira a
  vírgula", que aparece na resposta original, não aparece na correção.
- **Consertar seria:** na correção, rodar `checkMeasure` e mandar
  `numericValue`/`answerUnit` junto — e, no hook, escrever `numeric_value: null`
  explicitamente quando não houver número, em vez de omitir a chave. A omissão é
  a mesma raiz do `NOVO-lev-04`.
- **Não corrigido:** regra 3. **Aparentado ao `NOVO-lev-04` e ao `NOVO-lev-20`:
  os três terminam em bitola calculada sobre número que ninguém confirmou.**

### [NOVO-lev-25] Reabrir (ou só recarregar a página) volta para a pergunta 1 e sobrescreve o que já foi respondido

- **Onde:** `src/components/service-orders/SurveyPanel.tsx:85` (`useState(0)` para
  `idx`), `:104` (`ativo`) e `:158` (`seq: idx + 1`).
- **O quê:** `idx` é estado local que nasce em 0 e **nunca é sincronizado com as
  respostas que já existem**. Não há `useEffect` que o posicione em
  `respostas.length`.
- **Dois caminhos, o mesmo estrago:**
  1. **Reabrir.** `useReopenSurvey` põe `status: 'draft'`, e `ativo` volta a
     apontar para o levantamento. A tela reabre **na pergunta 1**, com o campo
     vazio. Responder grava `seq: 1`, que pelo `onConflict: 'survey_id,seq'`
     **sobrescreve a resposta 1 que estava lá**. Para chegar na pergunta que
     faltava, é preciso passar por todas — apagando cada uma no caminho.
  2. **Recarregar a página no meio.** O default de `status` em `service_surveys`
     é `'draft'` (conferido no banco), então após um F5 `ativo` continua
     apontando para o levantamento em curso e `idx` volta a 0. Mesma
     sobrescrita, sem ninguém ter pedido para reabrir nada.
- **A tela promete o contrário, com todas as letras:** o comentário em `:543-545`
  diz *"reabrir devolve a fila de perguntas **de onde parou**, sem apagar nada do
  que já foi respondido"*, e o toast de sucesso diz *"Levantamento reaberto — as
  respostas foram mantidas."* Elas foram mantidas até a próxima resposta.
- **A lista "O que foi levantado" continua mostrando tudo**, então a perda não é
  visível como perda: a linha simplesmente muda de valor.
- **Consertar seria:** posicionar `idx` na primeira pergunta ainda sem resposta
  (a partir de `respostas`), e marcar as já respondidas na fila. A correção
  completa depende do `NOVO-lev-05` — enquanto a identidade for `seq` e não
  `template_id`, "primeira sem resposta" também é uma conta sobre posição.
- **Não corrigido:** regra 3.

### [NOVO-lev-26] Reabrir não limpa a estimativa, ao contrário do que o código afirma

- **Onde:** `src/hooks/use-service-survey.ts:334-347`.
- **O quê:** o comentário diz *"A confiança e a estimativa são limpas de
  propósito — foram um julgamento sobre um conjunto de respostas que agora vai
  mudar"*. O `update` limpa `confidence`, `confidence_rationale` e `answered_at`.
  **Não limpa `estimated_minutes_p50`, `estimated_minutes_p80`,
  `contingency_pct` nem `cases_used`** — exatamente os quatro campos que formam a
  estimativa.
- **Por que importa:** entre reabrir e fechar de novo, o levantamento carrega uma
  contingência carimbada por um julgamento que foi explicitamente retirado.
  `useCloseSurvey` reescreve os quatro ao fechar, então a janela é limitada — mas
  é justamente a janela em que alguém volta ao local e olha o orçamento.
- **Consertar seria:** ou limpar os quatro, ou corrigir o comentário. O perigo do
  jeito atual é que a próxima pessoa vai confiar no comentário.
- **Não corrigido:** regra 3.

### [NOVO-lev-27] As fotos do levantamento vão para um bucket público

- **Onde:** `src/hooks/use-service-survey.ts:234-249` (`uploadSurveyPhoto` /
  `surveyPhotoUrl`).
- **O quê:** o upload vai para o bucket `service-order-photos` e a URL é obtida
  por `getPublicUrl`. **Conferido no banco: `storage.buckets.public = true`** para
  esse bucket. Quem tiver a URL vê a imagem sem autenticação nenhuma.
- **O que são essas fotos:** quadro elétrico, banco de baterias, interior de
  lancha e de motorhome de cliente — tiradas dentro da propriedade dele. O
  caminho (`surveys/<uuid>/<seq>-<timestamp>.jpg`) não é adivinhável, mas a
  proteção é só a obscuridade do UUID: a URL vaza em qualquer link colado,
  histórico de navegador ou print de tela.
- **Estado:** a decisão de bucket público é anterior a esta frente (já valia para
  as fotos de OS). O que muda é o volume e a natureza — o levantamento é o que
  passa a produzir foto de dentro da casa/embarcação do cliente de forma
  sistemática, e o comentário do próprio código diz que "é a foto que sustenta o
  preço".
- **Consertar seria:** bucket privado com URL assinada de validade curta
  (`createSignedUrl`), como já se faz nos anexos fiscais. Muda o `surveyPhotoUrl`
  e os dois pontos que o consomem.
- **Não corrigido:** regra 3, e a troca de bucket precisa de decisão sobre as
  fotos já existentes.

### [NOVO-lev-28] "Costuma entrar junto" aprende com orçamento que nunca virou serviço

- **Onde:** `related_materials` (migration `20260807100000`), na CTE `ordens_com` —
  o único filtro é `sop.service_order_id <> p_service_order_id`. **Não há filtro
  de status.**
- **O quê:** a estatística conta qualquer ordem que tenha a peça, inclusive
  rascunho e cancelada.
- **Medido no banco, hoje:**

  | situação | ordens | linhas de peça |
  |---|---:|---:|
  | rascunho (`draft`) | 31 | 118 |
  | cancelada | 24 | 41 |
  | executada (`completed` + `invoiced`) | 13 | 40 |
  | em andamento (demais) | 8 | 18 |

  **159 das ~217 linhas — 73% — vêm de ordens que nunca foram executadas**, e as
  canceladas entram com o mesmo peso das concluídas.
- **E a tela afirma o contrário:** `RelatedMaterialsPanel.tsx:95` escreve
  *"**{juntos} de {de_total}** vez(es) que você **usou** {produto}"*. Um rascunho
  não é um uso; uma cancelada é o oposto de um uso. O comentário da própria
  função diz "nas outras vezes que você usou isto".
- **Por que importa:** um orçamento que o cliente recusou por causa de um item
  caro passa a recomendar esse item nos próximos. A sugestão fica mais forte
  justamente quando a proposta foi rejeitada muitas vezes.
- **Consertar seria:** restringir a `status in ('completed','invoiced')` — o
  mesmo recorte que `create_service_cases_on_complete` usa para dizer o que
  virou caso. Com 13 ordens executadas o `p_min_juntos = 3` fica apertado, então
  vale rever o piso junto.
- **Não corrigido:** regra 3, e o recorte é decisão de negócio (contar `open` ou
  não, por exemplo).

### [NOVO-lev-29] A lista de material relacionado sai em ordem de UUID

- **Onde:** `related_materials`, a cláusula final
  `order by c.sugerido, pct desc, c.juntos desc`.
- **O quê:** `distinct on (c.sugerido)` obriga o `order by` a **começar** pela
  chave do distinct. Dentro de cada produto a ordenação por `pct desc` funciona e
  guarda o vínculo mais forte — que é o que o comentário promete. Mas o conjunto
  final sai ordenado por `c.sugerido`, que é um **uuid**: a ordem de exibição é
  aleatória.
- **Por que importa:** a tela mostra a lista inteira sem recorte
  (`RelatedMaterialsPanel.tsx:90`), então a sugestão de 90% de recorrência pode
  aparecer depois da de 30%. Numa lista curta ninguém nota; é quando ela cresce
  que a ordenação passa a ser a única coisa que a torna útil. **Também não há
  `limit`** — tudo o que passar do piso entra na tela.
- **Consertar seria:** embrulhar o `distinct on` numa subconsulta e ordenar por
  fora (`select * from (…) t order by pct desc, juntos desc limit 8`).
- **Não corrigido:** regra 3.

### [NOVO-lev-30] O `limit 5` do histórico não limita nada

- **Onde:** `estimate_from_cases` (migration `20260730020000`), no `select` que
  monta `baseado_em`.
- **O quê:** `jsonb_agg` é agregado sem `group by` — a consulta devolve **uma
  linha só**, e o `limit 5` é aplicado depois da agregação, sobre essa linha
  única. Ele nunca corta nada.
- **Provado rodando em produção:**
  `select jsonb_array_length((select coalesce(jsonb_agg(g order by g desc),'[]') from generate_series(1,40) g limit 5))`
  devolve **40**.
- **O que sai do outro lado:** `baseado_em` traz **todas** as execuções do
  serviço. Os dois consumidores juntam tudo numa linha:
  - `SurveyPanel.tsx:439` — `.join(' · ')` no rodapé da estimativa;
  - `survey-sheet.ts:194` — a mesma junção dentro do bloco de histórico da
    **folha impressa**, que tem altura fixa.
  Com 40 execuções, a folha do técnico ganha um parágrafo de 40 pares
  "OS-xxxxx 3h20" onde cabiam cinco.
  E `useCloseSurvey` grava esse mesmo array em `service_surveys.cases_used`,
  então a lista inteira fica guardada em cada levantamento.
- **Estado hoje:** latente, e vale registrar por quê — **`service_cases` tem 6
  linhas e nenhuma utilizável**: todas com `actual_minutes` nulo e
  `unusable_reason` = "Concluída sem hora apontada". Não é defeito, é o gatilho
  funcionando e dizendo a verdade; mas significa que a estimativa por analogia
  nunca teve dado, e que este `limit` nunca foi exercitado.
- **Consertar seria:** mover o corte para dentro (`from (select … order by
  created_at desc limit 5) c`).
- **Não corrigido:** regra 3.

### [NOVO-lev-31] `parse_answer_number` continua aberta para `anon`

- **Onde:** migration `20260806100000`, seção 2 — a função é criada e recebe
  `comment on`, mas **não recebe `revoke`/`grant`**, ao contrário das outras
  quatro funções do mesmo arquivo.
- **Conferido no banco:** `has_function_privilege('anon', …, 'EXECUTE')` = **true**.
  É a única função desta frente nessa situação; as outras treze estão fechadas.
- **Exposição real: nenhuma.** É um parser de texto para número, `immutable`, sem
  acesso a tabela — quem a chamasse como anônimo só conseguiria converter o
  próprio texto.
- **Por que registrar mesmo assim:** a regra está escrita na migration vizinha,
  duas semanas depois, sobre uma função igualmente inofensiva —
  *"aritmética pura, não expõe dado nenhum — mas função nova nasce com EXECUTE
  para public, e deixar uma aberta ensina a deixar a próxima"*
  (`20260808100000`, linhas 65-67). Esta é a que ficou.
- **Consertar seria:** duas linhas de `revoke`/`grant`, no padrão das demais.
- **Não corrigido:** regra 3.

### [NOVO-lev-32] O limiar de valor do levantamento é "configurável" sem ter como ser configurado — e o cast pode derrubar a função

- **Onde:** `should_survey_service` (migration `20260730020000`, linha 194):
  `coalesce((select value::numeric from public.app_settings where key = 'survey_valor_limiar'), 3000)`.
- **Duas coisas, uma leitura:**
  1. **A chave não existe e nada a escreve.** Conferido: `app_settings` não tem a
     linha, e `survey_valor_limiar` aparece **uma única vez em todo o
     repositório** — nesta migration. Não há tela, seed ou rotina que a crie. O
     limiar é, na prática, o literal 3000; o `coalesce` é o único caminho que
     roda.
  2. **O cast não é protegido.** `coalesce` só cobre a ausência de linha. Se a
     chave passar a existir com um texto que não seja numérico puro — `"3.000"`,
     `"R$ 3000"`, ou vazio —, `value::numeric` **lança** `invalid input syntax`,
     e como `should_survey_service` é a primeira coisa que o `SurveyPanel`
     chama, o bloco do gatilho some para **todos os serviços**, não só para um.
     E `app_settings` aceita insert de qualquer chave por qualquer autenticado
     (política `app_settings_auth_insert`, sem restrição).
- **Por que importa:** é um botão que não existe protegendo um cast que não
  perdoa. Quem for ligar a configuração — o caminho natural é inserir a chave
  pela tela genérica de settings — tem boa chance de digitar no formato de moeda
  brasileiro e derrubar o painel inteiro.
- **Consertar seria:** validar com `nullif(regexp_replace(value,'[^0-9.]','','g'),'')::numeric`
  ou `pg_input_is_valid(value,'numeric')` (PG16+), e — se o limiar é para ser
  configurável — criar a linha e o campo na tela de configurações.
- **Não corrigido:** regra 3.

### [NOVO-lev-33] O registro do ativo entra no documento sem escapar

- **Onde:** `src/lib/pdf-generator.ts:1178` —
  `${data.vessel?.registration ? `Registro: ${data.vessel.registration}<br/>` : ''}`.
- **O quê:** é a **única interpolação de texto vindo do cadastro que não passa
  por `esc()`** em todo o arquivo. Varri as 1.570 linhas: todas as outras — nome
  do cliente, do ativo, do fabricante, descrição, notas técnicas, URL de foto,
  SKU — usam `esc()`. Esta ficou de fora, cercada de vizinhas escapadas
  (`esc(data.vessel.name)` na linha 1175, `esc(data.vessel.manufacturer)` na
  1177).
- **De onde vem o valor:** `vessels.hull_id_or_registration`, texto livre digitado
  na tela de ativos por qualquer usuário interno.
- **Por que não é só cosmético:** `generatePDFBlob` faz `container.innerHTML =
  html` e anexa o resultado ao `document.body` do ERP; `printPDF` escreve o mesmo
  HTML numa janela nova. Marcação injetada no campo executa nos dois caminhos, no
  contexto da aplicação. Um `<` sozinho já quebra o bloco do ativo.
- **Secundário, no mesmo arquivo:** `pageWrapper(`${docTypeLabel} ${docNumber}`)`
  (linha 1343) põe o número no `<title>` sem escapar — no corpo ele é escapado
  (`esc(docNumber)`, linha 1348). O número da ordem é gerado pelo sistema
  (`ORÇ-00074`), então o risco é nulo; anotado para o conserto sair completo.
- **Consertar seria:** `esc(data.vessel.registration)`, e um teste que varra o
  arquivo procurando interpolação de campo de cadastro sem `esc` — a mesma
  ideia das varreduras de `.select()` e de hooks.
- **Não corrigido:** regra 3.

### [NOVO-lev-34] Todo documento diz "Página 01 / 01"

- **Onde:** `src/lib/pdf-generator.ts:694` (cabeçalho) e `:1338` (rodapé). Nos
  dois, a string é literal.
- **O quê:** o documento afirma ter uma página só, sempre — inclusive nos que
  têm cinco. O módulo inteiro de paginação (`pdf-pagination.ts`, os espaçadores,
  o `NOVO-lev-10` e o `NOVO-lev-11`) existe justamente porque estes documentos
  passam de uma folha.
- **Por que importa neste sistema em particular:** o documento é assinado pelo
  cliente no portal e circula por WhatsApp e e-mail. Numeração de página é o que
  permite dizer que a proposta está inteira — sem ela, ninguém percebe uma folha
  faltando, nem na conferência interna nem do lado do cliente.
- **Consertar seria:** no caminho de imprimir, dá para fazer com CSS
  (`@page { @bottom-right { content: counter(page) " / " counter(pages) } }`,
  suporte irregular) ou com contadores em elementos de rodapé repetidos. No
  caminho de baixar, quem sabe o número de folhas é o html2pdf **depois** de
  fatiar — o jeito honesto é escrever a numeração pelo `jsPDF` sobre o PDF
  pronto, que a API `.toPdf().get('pdf')` já permite. Enquanto isso não existir,
  **tirar a frase é melhor que mantê-la**: informação errada é pior que
  informação ausente.
- **Não corrigido:** regra 3.

### [NOVO-lev-35] `itemColumnCount` nunca foi ligado, e as colunas somam 85%

- **Onde:** `src/lib/pdf-visibility.ts:54` (a função) contra
  `src/lib/pdf-generator.ts` (que não a importa).
- **O quê, em duas partes:**
  1. `itemColumnCount` existe, tem quatro asserções em
     `pdf-visibility.test.ts:64-67`, e o comentário dela diz que serve para o
     `colspan` do rodapé não desalinhar a tabela — *"o tipo de defeito que só
     aparece no papel"*. **`pdf-generator.ts` não tem nenhum `colspan`** e nunca
     importa a função. É helper morto, com teste dando cobertura a nada — o mesmo
     padrão do `indivisivel` (`NOVO-lev-12`).
  2. As larguras das colunas são literais (`:1229-1233` e `:1245-1249`):
     55% + 15% para descrição e quantidade, mais 15% por coluna de preço. Com as
     duas colunas de preço dá 100%; **com só uma marcada no diálogo, dá 85%** —
     a tabela sai estreita ou o navegador redistribui a sobra a seu critério, e o
     resultado difere entre imprimir (layout do navegador) e baixar (rasterizado).
- **Por que registrar junto:** é a mesma peça de contabilidade da tabela. Quem
  for ligar a função vai querer que a largura saia dela também.
- **Consertar seria:** derivar largura e `colspan` de `itemColumnCount`, ou
  remover a função e o teste.
- **Não corrigido:** regra 3.

---

## Fechamento da varredura noturna — 15/08 23:33 a 16/08 07:00

Nove rodadas, uma área por rodada, lendo o código e — quando a resposta estava no
banco e não no arquivo — **rodando a função contra produção**. Trinta e cinco
achados (`NOVO-lev-01` a `NOVO-lev-35`). **Nada foi corrigido** (regra 3):
nenhum dos achados quebra produção neste momento, e vários exigem decisão de
desenho ou de negócio. Ao fim de cada rodada, `tsc -b` em zero e a suíte
completa passando — 102 arquivos, 1.280 testes, em todas as nove.

### O que foi coberto

`survey-sheet.ts` · `survey-measure.ts` · `SurveyPanel.tsx` ·
`SurveySheetEntryDialog.tsx` · `pdf-generator.ts` · `pdf-pagination.ts` ·
`css-scope.ts` · `use-pdf.ts` · `use-service-survey.ts` ·
`use-survey-material-rules.ts` · `RelatedMaterialsPanel.tsx` ·
`PublicServiceOrderView.tsx` · as funções SQL do levantamento
(`compose_survey_for_*`, `should_survey_service`, `estimate_from_cases`,
`previous_survey_answers`, `related_materials`, `survey_suggested_materials`,
`apply_survey_materials`, `survey_cable_sizing`, `dc_cable_sizing`,
`parse_answer_number`) · a RLS de `service_surveys`, `service_survey_answers`,
`survey_material_rules` e `dc_ampacity_ratings` · e a consistência entre a folha
impressa e a tela de lançamento.

### O que ficou de fora

Não foram lidos: `buildInvoiceHTML` e o PDF de recibo (`v2/lib/receipt.ts`),
`pdf-print.ts`, `download.ts`, `autosave-guard.ts`, `document-type.ts`, o
download em lote e o anexo de WhatsApp, a tela de aprovação de perguntas e de
regras de material, e `survey_question_catalog`.

### Os achados por gravidade

**1. Erram um número que decide material — inclusive bitola de cabo, que é risco
físico.**
`NOVO-lev-20` (a frase pronta afirma 5,96 mm² para 200 A com `pronto: false`) ·
`NOVO-lev-21` (quatro das seis perguntas do dimensionamento inativas; os padrões
saem sob a chave `lido_do_levantamento`, e os dois que erram para menos são
justamente casa de máquinas e feixe) · `NOVO-lev-24` (corrigir a medida não
corrige o `numeric_value`, que é o que o cálculo lê) · `NOVO-lev-04` (resposta
marcada como "não consegui ver" continua alimentando o cálculo) ·
`NOVO-lev-06` (material lançado pelo levantamento não mexe no total da ordem).

**2. Saem da empresa errados.**
`NOVO-lev-14` (31 orçamentos com link público baixados como "Ordem de Serviço" e
sem validade; o portal tem uma terceira montagem do PDF) · `NOVO-lev-16` (três
consultas sem checar erro: documento com o nome "MarineFlow", sem CNPJ, sem
banco, sem termos, e sem o sinal já pago) · `NOVO-lev-34` ("Página 01 / 01" em
documento de várias folhas) · `NOVO-lev-15` ("Baixar PDF" do portal abre a
janela de impressão) · `NOVO-lev-10` e `NOVO-lev-11` (a paginação ainda deixa
bloco ser cortado, e cria página quase em branco depois de tabela longa).

**3. Perdem o que foi levantado.**
`NOVO-lev-19` (a folha imprime até 14 perguntas da ordem e a tela lança 9 de um
serviço — o que não casa se perde, e o que sobra é gravado como "não verificado"
sem ter sido perguntado) · `NOVO-lev-25` (reabrir, ou só recarregar a página,
volta para a pergunta 1 e sobrescreve as respostas) · `NOVO-lev-05` (o upsert
casa por posição, não por pergunta) · `NOVO-lev-23` (falha no lançamento deixa
levantamento órfão e o botão cria outro).

**4. Sugerem mal.**
`NOVO-lev-28` (73% da evidência de "costuma entrar junto" vem de orçamento
rascunho ou cancelado, e a tela chama isso de "vezes que você usou") ·
`NOVO-lev-30` (o `limit 5` do histórico não limita — a folha impressa recebe
todas as execuções numa linha) · `NOVO-lev-29` (lista em ordem de uuid) ·
`NOVO-lev-08` e `NOVO-lev-09` (mensagem falsa e trava de duplicata furada no
lançamento de material) · `NOVO-lev-18` (com dois levantamentos fechados, o PDF
pega um qualquer).

**5. Erro engolido que vira mensagem errada.**
`NOVO-lev-02` (folha vazia diz que faltam perguntas aprovadas, seja qual for a
causa) · `NOVO-lev-07` (invalidação com chaves de cache inexistentes: o clique
parece não ter feito nada) · `NOVO-lev-17` (a galeria de fotos lê uma coluna que
nada escreve).

**6. Higiene de segurança.**
`NOVO-lev-27` (fotos do levantamento em bucket público) · `NOVO-lev-33` (registro
do ativo sem `esc()`) · `NOVO-lev-32` (`value::numeric` sem validação derruba o
painel inteiro) · `NOVO-lev-31` (`parse_answer_number` aberta para `anon`) ·
`NOVO-lev-13` (`scopeCss` divide seletor por vírgula sem contar parênteses —
latente).

**7. Código que promete e não entrega.**
`NOVO-lev-12` (`indivisivel`) · `NOVO-lev-35` (`itemColumnCount`) ·
`NOVO-lev-26` (reabrir não limpa a estimativa, ao contrário do comentário) ·
`NOVO-lev-01` (a folha diz que agrupa por sistema e não agrupa) ·
`NOVO-lev-03` (consulta fora do `Promise.all`).

### Três coisas que a varredura verificou e NÃO são defeito

Anotadas para não voltarem à fila: o `@import` do Google Fonts atravessa o
`scopeCss` intacto apesar dos `;` na URL; comentário com chave fora da posição 0
embaralha o texto mas o navegador reinterpreta certo; e as 6 linhas de
`service_cases` estarem todas inutilizáveis é o gatilho **funcionando** e
dizendo a verdade ("Concluída sem hora apontada") — não há defeito ali, mas
significa que a estimativa por analogia nunca teve dado.

### O padrão que se repetiu

Sete dos trinta e cinco achados são **teste ou comentário que dá confiança
falsa**: o teste da paginação põe o bloco alto em primeiro lugar, justamente
onde a fórmula errada acerta (`NOVO-lev-11`); o teste de unificação do PDF
nomeia o portal público e só faz grep em `use-pdf.ts` (`NOVO-lev-14`); o
comentário do reabrir diz que limpa a estimativa e não limpa (`NOVO-lev-26`); o
toast diz que as respostas foram mantidas um instante antes de sobrescrevê-las
(`NOVO-lev-25`). Vale mais como método do que como lista: **onde havia um
comentário afirmando o comportamento, valeu a pena conferir se o código o
cumpria** — foi o que rendeu os achados mais graves da noite.
