# MarineFlow ERP — Plano de Integração Bancária (Extrato, Boleto, Pix e Cobrança)

> Criado em 23/07/2026. Status: **PROPOSTA — aguardando decisões da Fase 0.**
> Objetivo: analisar extratos e histórico de transações, emitir boletos, emitir Pix,
> enviar cobranças e automatizar a rotina financeira, preferencialmente com C6 ou Nubank.

---

## 1. Veredito da avaliação

| Opção | Emissão (boleto/Pix) | Extrato/transações | Conclusão |
|---|---|---|---|
| **Nubank PJ** | ❌ Não tem API oficial | ✅ Só via agregador Open Finance (Pluggy/Belvo) | Serve apenas para **leitura de extrato**, via terceiro |
| **C6 Bank** | ✅ API oficial (Pix, boleto, cobrança, DDA) | ✅ API oficial (extrato/saldo) | **Melhor opção direta** — exige conta PJ C6 + credenciamento no portal dev + certificado mTLS |
| **Pluggy comercial** | ➖ Iniciação de pagamento (não é foco) | ✅ Multi-banco (Nubank, C6, Inter, big five) | **R$ 2.500/mês (dados) + R$ 500/mês (pagamentos)** — só quando o MarineFlow virar produto p/ clientes externos |
| **Meu Pluggy / Connector 200** | ❌ | ✅ Multi-banco, **GRATUITO p/ dados próprios** | Verificado 26/07/2026: portal meu.pluggy.ai + API grátis dos próprios dados; sem webhooks/categorização → polling diário; uso interno, não p/ revenda |
| **Asaas** | ✅ API aberta (boleto+Pix+cartão), régua de cobrança embutida | ✅ Do saldo Asaas (não do banco) | **Atalho mais rápido para emissão** — sem burocracia, sandbox livre; dinheiro transita pela conta Asaas |
| **Cora (Cora Pro R$ 44,90/mês)** | ✅ Boleto (incl. boleto+Pix e carnê), cobrança parcelada, webhooks | ✅ Saldo/extrato em tempo real (da conta Cora) | Cobre A+B num provedor só; **pagamento via API exige aprovação no app** (governança pronta); exige conta Cora + plano Pro |
| **Banco Inter** | ✅ API oficial gratuita (BolePix, Pix, webhook) | ✅ API oficial | Sólida se abrir conta PJ Inter; sem ICP-Brasil. Ressalvas: integração passa por análise interna, extrato em janelas de 90 dias, API Banking já ficou fechada p/ novas integrações (dez/2025–mar/2026) |

**Recomendação:** não casar o ERP com um banco. Construir uma **camada trocável
`_shared/banking`** espelhando o padrão já aprovado em `_shared/fiscal`
(`types.ts` + `factory.ts` + providers), com três frentes independentes:

- **Frente A — Emissão e cobrança** (boleto, Pix, envio por WhatsApp): provider
  inicial = **C6** (se houver conta PJ C6), **Asaas** (se velocidade importar mais)
  ou **Cora** (se topar conta nova — cobre A+B por R$ 44,90/mês).
- **Frente B — Extrato e conciliação**: **Meu Pluggy gratuito** para multibanco
  (incl. Nubank) com polling diário; API direta do banco (C6/Cora/Inter) para a
  conta principal; OFX manual como bootstrap/fallback (Fase 0.5).
- **Frente C — Programação de pagamentos SEM execução** (rev. 26/07): contas a
  pagar programadas, previsão de caixa, alertas de vencimento, fila de aprovação —
  100% interno ao ERP (usa `payables`), sem tocar API bancária. O ERP monitora e
  sugere; quem paga é o humano no app do banco.

Nubank puro não atende o pedido: sem API oficial, não emite boleto/Pix
programaticamente de jeito nenhum. Se a conta principal for Nubank, a emissão
obrigatoriamente sai por terceiro (Asaas/Cora/Inter/C6) e o Nubank entra só como
fonte de extrato via Meu Pluggy (grátis) ou OFX.

---

## 2. O que o ERP já tem (fundação existente)

Inventário verificado em 23/07/2026 no repo canônico (`Claude Code/marineflow-erp`, branch `main`):

- **Tabelas financeiras prontas**: `receivables`, `payables`, `payments`
  (com `payment_method` incluindo `pix`), `invoices`, `financial_categories`,
  `collections` e — decisivo — **`bank_transactions`** já criada com
  `bank_ref_id`, `reconciled`, `reconciled_payment_id`, `import_batch_id`
  (migration `20260408154132`). A conciliação foi desenhada desde o início; só falta alimentá-la.
- **Padrão de provider trocável** em `supabase/functions/_shared/fiscal/`
  (`types.ts`, `factory.ts`, `contora-provider.ts`, `payload-builder.ts`) com o trio
  de functions `fiscal-emit` / `fiscal-webhook` / `fiscal-reconcile`. É o molde a copiar.
- **Infra WhatsApp completa** (Evolution API + Cloudflare Tunnel): `whatsapp-send`,
  fila (`whatsapp-queue-worker`), status (`whatsapp-status-worker`) — o "enviar cobrança"
  é só montar a mensagem e enfileirar.
- **Réguas e crons existentes**: `receivable-reminders` (lembrete por vencimento),
  `quote-reminders`, digest matinal 07:30. A régua de cobrança bancária pluga aqui.
- **Agente IA com ~63 tools** (`ai-agent`): as operações bancárias viram novas tools.

**⚠️ Dívida de segurança bloqueante encontrada:** `payments` e `bank_transactions`
têm policy RLS `allow_all ... TO anon, authenticated USING (true)` — ou seja, o
role anônimo lê e escreve dados financeiros. Antes de qualquer dado bancário real
entrar nessas tabelas, essas policies precisam ser restringidas (pré-requisito da Fase 1).

---

## 3. Avaliação detalhada das opções

### 3.1 C6 Bank (preferência declarada — viável)
- Portal: https://developers.c6bank.com.br — APIs de Pix (cobrança imediata e com
  vencimento), pagamentos/cobrança (boleto, DDA), extrato/recebíveis.
- Credenciamento: dentro do **Internet Banking PJ** (Meu Perfil → Integrações API),
  gera-se chave, `client_id`/`client_secret` e baixa-se o **certificado mTLS**.
- Particularidades: o certificado tem validade e, ao expirar, é preciso **trocar o
  certificado E gerar novos client_id/secret** (ponto de falha operacional — monitorar validade).
  O certificado só pode ser baixado no ato da criação.
- Pré-requisito duro: **ter conta PJ no C6**. Sandbox disponível após cadastro no portal.

### 3.2 Nubank PJ (preferência declarada — inviável para emissão)
- **Não existe API pública oficial** para conta PJ (só NuPay for Business, checkout
  de e-commerce — outro caso de uso).
- Caminho legítimo: **Open Finance** — Nubank é participante obrigatório, então um
  agregador regulado (Pluggy, Belvo, Celcoin) lê extrato/saldo com consentimento
  renovável do titular (QR Code no app Nubank a cada ~12 meses).
- Veredito: entra no plano **apenas como fonte de extrato via Frente B**.

### 3.3 Pluggy / agregadores Open Finance
- Uma API única para extrato categorizado, saldo e dados de contraparte
  (CPF/CNPJ) de todos os bancos relevantes, incluindo Nubank e C6.
- Regulado pelo Banco Central; consentimento LGPD explícito do titular da conta.
- Custo: SaaS por conexão/conta — sem preço público, exige contato comercial
  (orçar na Fase 0). Belvo e Celcoin são concorrentes para cotação.

### 3.4 Asaas (atalho de emissão)
- API REST aberta, sandbox sem burocracia, sem mTLS/certificado.
- Boleto sem taxa de emissão (paga só quando pago); Pix R$0,99 (3 primeiros meses)
  → R$1,99 por cobrança recebida, com 100 isenções/mês; cartão como bônus.
- Já tem **régua de cobrança nativa** (e-mail/SMS) — mas a nossa sai pelo WhatsApp próprio.
- Trade-off: o dinheiro liquida na **conta Asaas** e precisa ser transferido ao banco
  (transferência automática configurável). É um intermediário a mais no fluxo de caixa.

### 3.5 Banco Inter (plano B sólido)
- API oficial **gratuita** para PJ: Cobrança "BolePix" (boleto com QR Pix no mesmo
  documento), Pix, saldo/extrato, pagamento, **webhooks nativos** de liquidação.
- Certificado próprio gerado no IB (validade 12 meses), sem ICP-Brasil.
- Exige abrir conta PJ Inter. Se a empresa toparia abrir conta nova, é possivelmente
  o melhor custo-benefício técnico do mercado.

---

## 4. Arquitetura proposta

```
                       ┌──────────────────────────────────────────────┐
                       │  supabase/functions/_shared/banking/         │
                       │  types.ts      (BankingProvider interface)   │
                       │  factory.ts    (escolhe provider por env)    │
                       │  c6-provider.ts / asaas-provider.ts / ...    │
                       │  pluggy-provider.ts (só Frente B)            │
                       └──────────────┬───────────────────────────────┘
                                      │
   ┌───────────────┬──────────────────┼──────────────────┬─────────────────┐
   │ banking-charge│  banking-webhook │   banking-sync   │ (reuso)         │
   │ emite boleto/ │  liquidação →    │  extrato → bank_ │ whatsapp-send   │
   │ Pix p/ receiv.│  baixa receivable│  transactions +  │ receivable-     │
   │               │  + insere payment│  conciliação     │ reminders       │
   └───────────────┴──────────────────┴──────────────────┴─────────────────┘
```

### Interface mínima (`types.ts`)
```ts
interface BankingProvider {
  createCharge(input: ChargeInput): Promise<ChargeResult>;   // boleto e/ou Pix cob
  cancelCharge(chargeId: string): Promise<void>;
  getCharge(chargeId: string): Promise<ChargeStatus>;
  createPixQr(input: PixInput): Promise<PixResult>;          // Pix avulso (estático/dinâmico)
  parseWebhook(req: Request): Promise<SettlementEvent[]>;    // valida assinatura!
  fetchStatement(range: DateRange): Promise<BankTransaction[]>; // Frente B
}
```

### Mudanças de schema (novas migrations — nomeadas, por gate)
1. `bank_accounts` — contas conectadas (banco, provider, apelido, status do consentimento OF, validade do certificado).
2. `bank_charges` — cobranças emitidas: `receivable_id` FK, provider, `provider_charge_id`,
   tipo (`boleto` | `pix` | `bolepix`), linha digitável, `pix_copia_cola`, `qr_code_base64`,
   URL do PDF, status (`pending`→`paid`/`overdue`/`cancelled`), `paid_at`, valor pago.
3. `bank_transactions` — **acrescentar** `bank_account_id` FK e `raw jsonb` (payload original);
   já tem o resto.
4. **Correção das RLS** de `payments`/`bank_transactions` (+ RLS das novas tabelas): nada de `anon`.

### Segredos (Supabase secrets, nunca no repo)
`C6_CLIENT_ID`, `C6_CLIENT_SECRET`, `C6_MTLS_CERT`/`KEY` (base64), `ASAAS_API_KEY`,
`PLUGGY_CLIENT_ID/SECRET`, `BANKING_WEBHOOK_SECRET` (validação HMAC dos webhooks).

---

## 5. Fases de execução

### Fase 0 — Decisões e credenciamento (usuário + Claude, ~sem código)
**Decisões que só o usuário pode tomar:**
1. Em qual banco está (ou estará) a conta PJ principal? Existe conta C6 PJ hoje?
2. Aceita o dinheiro transitar pela conta Asaas (caminho rápido) ou exige liquidação
   direta no banco (caminho C6/Inter, mais burocracia)?
3. Extrato: só o banco principal (API direta) ou multi-banco incl. Nubank (contratar Pluggy)?
4. Ordem de prioridade: emissão de cobrança primeiro ou conciliação de extrato primeiro?
   (Recomendo emissão — é receita/rotina diária; conciliação vem na sequência.)

**Ações do usuário:** criar credenciais no portal escolhido (C6: IB PJ → Integrações API,
guardar o certificado num local seguro; Asaas: conta + API key sandbox; Pluggy: contato comercial).
**Gate de saída:** provider escolhido por frente + credenciais sandbox em mãos.

### ⚠️ Auditoria 27/07/2026 — a Fase 0.5 JÁ EXISTIA (e estava com bugs)

Antes de escrever qualquer código novo, auditoria do repo revelou que **importação de
extrato e conciliação já existem** e estão roteadas em duas telas (`FinancialPage` e
`FinancialV2` → aba Conciliação):
- `src/lib/bank-parser.ts` — parser de OFX e CSV, detecção de fatura de cartão.
- `src/components/BankReconciliation.tsx` — upload drag-and-drop, preview, sugestões
  automáticas (valor ±5% e data ±7 dias), conciliar com receivable/payable existente,
  vincular a OS, criar lançamento novo, ignorar/restaurar.
- Hooks completos em `use-financial.ts`.

**Mas `bank_transactions` tinha 0 linhas** — a funcionalidade nunca rodou com dados
reais (mesmo padrão da Entrada de Mercadoria por XML). E a auditoria achou 4 defeitos
que teriam corrompido o financeiro no primeiro uso de verdade:

1. **Sem deduplicação (crítico).** O FITID era gravado em `bank_ref_id` mas nunca
   usado; não havia índice único. Reimportar período sobreposto — o uso normal —
   duplicaria todo o histórico. *Corrigido:* dedupe por consulta prévia no hook
   (funciona sem migration) + índice único na migration + dedupe dentro do arquivo.
2. **Valor com milhar brasileiro lido errado (crítico).** `1.450,00` virava **1,45**,
   silenciosamente, porque o parser trocava vírgula por ponto sem olhar a posição.
   *Corrigido:* `parseAmount` decide o separador decimal pelo último a aparecer.
3. **CSV quebrado por vírgula dentro de aspas.** `"PAGAMENTO, PARCELA 2"` deslocava
   todas as colunas seguintes, corrompendo data e valor. *Corrigido:* `splitCSVLine`
   respeita aspas (incl. escapadas).
4. **Acentos corrompidos.** Arquivo era lido como UTF-8 fixo; OFX Latin-1 (comum em
   bancos BR) corrompia toda descrição. *Corrigido:* `decodeStatementFile` tenta
   UTF-8 estrito e cai para Windows-1252.

Também adicionado: extração de **EndToEndId do Pix** e de CNPJ/CPF da contraparte
(casamento forte para a conciliação automática), respeito ao `TRNTYPE`, e feedback
na importação ("N importadas · M já existiam"). 19 testes unitários novos
(`src/test/bank-parser.test.ts`); suíte completa 245/245.

**Conclusão prática:** a porta 3 (upload no ERP) da Fase 0.5 está pronta e corrigida.
Faltam as portas WhatsApp e Dropbox, que continuam válidas como descrito abaixo.

### Fase 0.5 — MVP de extrato manual via OFX (proposta do usuário, 23/07/2026)
Antecipa a Frente B sem contratar nada: o usuário exporta o extrato em **OFX**
(Nubank PJ: app "Gerar Extrato" → e-mail, ou app.nubank.com.br → download direto;
C6: Web Banking/app → OFX/CSV até 180 dias) e entrega ao agente. **Uma esteira,
duas portas de entrada:**

1. **Porta WhatsApp (fazer primeiro — infra 100% pronta):** usuário manda o arquivo
   .ofx no chat do agente; `whatsapp-webhook` detecta documento do número do dono
   → roteia para `banking-import` → parse OFX → upsert em `bank_transactions`
   (dedupe por **FITID** → `bank_ref_id`) → agente responde resumo (N transações,
   novas, sugestões de conciliação). Agente cobra o extrato se não receber há X dias.
2. **Porta Dropbox (segunda porta, fluxo desktop):** pasta reservada no Dropbox do
   usuário; app OAuth do Dropbox (refresh token em Supabase secrets); cron diário
   (~07:00) lista a pasta, baixa arquivos novos (cursor/lista de processados),
   importa pela MESMA `banking-import` e reporta no digest 07:30.
   (Porta 3 opcional: tela "Importar extrato" no próprio ERP, drag-and-drop.)

- **OFX obrigatório, CSV só fallback:** OFX tem FITID (ID único por transação →
  dedupe perfeito, períodos sobrepostos não duplicam); CSV varia por banco e não tem ID.
- Parser OFX em Deno: SGML/XML simples, ~150 linhas, sem dependência externa.
- **Limites honestos:** não emite nada (Frente A intacta); conciliação vira D+1 e
  depende da disciplina do export manual — se cansar, é o sinal para ativar C6 API/Pluggy.
  O importador NÃO é descartado depois: vira fallback permanente da `banking-sync`.
- **Pré-requisito mantido:** corrigir RLS de `bank_transactions`/`payments` ANTES do primeiro import real.
- **Gate:** primeiro OFX real importado + resumo correto devolvido pelo agente.

### Fase 1 — Fundação + emissão em sandbox (1º sprint de código)
- Migrations: `bank_accounts`, `bank_charges`, ajustes em `bank_transactions`, **correção RLS**.
- `_shared/banking/` (types, factory, provider escolhido) + edge function `banking-charge`.
- UI mínima: botão "Gerar cobrança (Boleto/Pix)" na tela de receivables → mostra
  QR/linha digitável/PDF, grava em `bank_charges`.
- **Validação:** emitir e cancelar cobrança no sandbox; nenhum acesso a produção bancária.
- **Gate:** demo em sandbox aprovada pelo usuário.

### Fase 2 — Webhook de liquidação e baixa automática
- `banking-webhook`: recebe evento de pagamento (assinatura validada), marca
  `bank_charges.paid`, dá baixa no `receivable` e insere `payments` (espelha o fluxo
  `fiscal-webhook`). Idempotente (`provider_charge_id` único).
- Fallback de polling (cron) para provider sem webhook confiável.
- **Gate:** pagamento sandbox → baixa automática visível no ERP, sem intervenção.

### Fase 3 — Envio de cobrança e régua via WhatsApp
- Template de mensagem (Pix copia-e-cola + link do boleto) → `whatsapp-send`/fila existente.
- Estender `receivable-reminders`: se receivable tem `bank_charge` ativa, o lembrete
  já vai com o meio de pagamento; reenvio automático em D-3, D0, D+3 (configurável).
- Respeitar regra existente de silenciar contato; log em `collections`.
- **Gate:** autorização explícita do usuário para envio real de WhatsApp (regra CLAUDE.md).

### Fase 4 — Extrato e conciliação (Frente B)
- `banking-sync` (cron diário ou sob demanda): busca extrato (C6 direto e/ou Pluggy)
  → upsert em `bank_transactions` (dedupe por `bank_ref_id`).
- Motor de conciliação sugerida: match por valor+data+txid/E2E-ID do Pix contra
  `payments`/`bank_charges`; sugestões com score, confirmação humana na UI
  (report-only primeiro, como no padrão do workflow do Ciclo 2).
- Tela de conciliação: lista transações não conciliadas, aceita/rejeita sugestão.
- **Gate:** 1 mês de extrato conciliado com < X pendências manuais.

### Fase 5 — Automação e IA (funcionário digital)
- Novas tools no `ai-agent`: `criar_cobranca`, `consultar_cobranca`, `extrato_periodo`,
  `resumo_financeiro`, `enviar_cobranca_whatsapp` (esta atrás do gate de aprovação).
- Digest 07:30: bloco "recebidos ontem / a vencer hoje / inadimplentes".
- Rotinas: cobrança automática ao faturar orçamento (integra com o fluxo fiscal
  existente — NF-e + boleto + WhatsApp num ato só).
- **Gate:** cada automação nasce report-only e só executa após aprovação (padrão Ciclo 2).

---

## 6. Riscos e mitigação

| Risco | Mitigação |
|---|---|
| RLS `allow_all`/`anon` em tabelas financeiras | Corrigir na Fase 1, antes de dado real |
| Certificado C6 expira → derruba emissão e exige novo client_id/secret | Registrar validade em `bank_accounts` + alerta no digest 30/7 dias antes |
| Webhook forjado dando baixa falsa | Validar assinatura/HMAC + conferir valor contra `bank_charges` + idempotência |
| Consentimento Open Finance expira (~12 meses) | Status em `bank_accounts` + alerta de renovação |
| Dinheiro parado na conta Asaas | Transferência automática diária configurada na plataforma |
| LGPD (dados de contraparte no extrato) | Minimizar retenção de `raw`, acesso só a roles internos |
| Multi-sessão no repo | Trabalhar em worktree/branch dedicada (`feat/banking-integration`), staging por arquivo |
| Vendor lock-in | É exatamente o que a interface `BankingProvider` elimina — trocar provider = 1 arquivo |

## 7. Estimativa de custo recorrente (ordem de grandeza)
- **C6 API:** sem custo de API divulgado; tarifas normais de liquidação de boleto/Pix da conta PJ.
- **Asaas:** R$1,99/cobrança Pix recebida (100 isentas/mês), boleto pago ~R$1,99 — sem mensalidade.
- **Cora:** R$ 44,90/mês (plano Cora Pro, requisito da Integração Direta) + tarifas por transação quando usadas.
- **Meu Pluggy / Connector 200:** R$ 0 (dados próprios, uso interno).
- **Pluggy comercial:** R$ 2.500/mês (dados) + R$ 500/mês (pagamentos) — publicado em pluggy.ai/precos, verificado 26/07/2026.
- **Inter:** API gratuita; só tarifas de liquidação.

---

## 8. Revisão 26/07/2026 — cruzamento com pesquisa externa (ChatGPT)

O usuário trouxe uma pesquisa feita no ChatGPT sobre o mesmo tema. Cruzamento:

**Confirmado por verificação independente (3/3 alegações-chave):**
1. **Cora**: Integração Direta exige plano **Cora Pro (R$ 44,90/mês)**; entrega saldo/extrato
   em tempo real, emissão de boleto (incl. boleto+Pix e carnês), cobrança parcelada, webhooks,
   ambiente stage, OAuth2+certificado; **pagamentos iniciados por API só executam após
   aprovação humana no app** — modelo de governança alinhado ao princípio Sugerir≫Executar.
2. **Meu Pluggy / Connector 200**: acesso **gratuito e permanente** via API aos PRÓPRIOS
   dados bancários conectados no portal meu.pluggy.ai (Open Finance regulado, inclui Nubank).
   Limites: sem webhooks, sem categorização/KYC, uso pessoal/interno — polling diário resolve.
   **Substitui a Pluggy paga na Frente B enquanto o uso for interno da HBR.**
3. **Pluggy comercial**: preços publicados R$ 2.500/mês (dados) + R$ 500/mês (pagamentos) —
   inviável agora; fica para quando o MarineFlow oferecer isso a clientes externos.

**Convergências que validam o plano existente** (chegamos igual, por caminhos independentes):
camada de adaptadores (`BankProvider` ≈ nosso `BankingProvider`); OFX como contingência e
não como integração principal (≈ nossa Fase 0.5); chave única provider+conta+id p/ dedupe
(≈ FITID→`bank_ref_id`); conciliação previsto×realizado com confirmação humana nos casos
de baixa confiança (≈ report-only); escopos read-only primeiro; segredos só no backend;
webhooks idempotentes; agregador só na fase comercial.

**Lacunas da pesquisa ChatGPT** (não invalidam, mas o escopo dele era só monitoramento):
não avaliou C6 (preferência do usuário) nem Nubank nem Asaas; a Frente A (emissão de
cobrança) ficou subatendida — coberta aqui por C6/Asaas/Cora/Inter.

**Incorporado ao plano a partir da pesquisa dele:**
- **Frente C** (programação de pagamentos interna, sem execução) — ver seção 1.
- Enriquecimento de schema para as próximas migrations: `bank_sync_runs` (log de cada
  sincronização + indicador "última sync" na UI — nunca mostrar saldo velho como atual),
  `bank_webhook_events` (recepção bruta idempotente), campos `counterparty_name`/
  `counterparty_document`/`pix_end_to_end_id`/`balance_after` em `bank_transactions`,
  e trilha de auditoria imutável das ações financeiras.
- Ressalvas do Inter: aprovação por análise interna, extrato em janelas de 90 dias
  (sync incremental obrigatório), histórico de indisponibilidade p/ novas integrações
  (dez/2025–mar/2026) — reforça a camada trocável.
- Cora entra como candidata oficial da Frente A (e B da própria conta) na decisão da Fase 0.
