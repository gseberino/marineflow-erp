# MarineFlow AI Operator — Ciclo 2 / Fase 1 (versão conformada)

> Consolida e **corrige** os dois documentos de planejamento do Ciclo 2, casando cada
> item com as **tools reais** do `_shared/ai/tools/*.ts` (63 tools, conferidas em 2026-07-21).
> Decisões do dono: **quick-wins primeiro** · **fiscal exposto como tool que emite**.

---

## 0. Correções aplicadas ao planejamento original

Referências do passado **descartadas** (não valem mais):

- **Modelo = Claude via OpenRouter** (confirmado no código). Não é Gemini nem Lovable.
  → Cai o "Risco #1 (confirmar modelo)" e a "dependência de modelo" do Bloco B/Seção 0.3.
- **Áudio = transcrição** (Groq Whisper, já em produção), **não nativo**. O caminho de
  entrada por voz já existe ponta a ponta; não há decisão de modelo pendente aqui.

Itens que os docs marcavam como "gap/novo" mas **já são tools reais** (não construir de novo):

| Descrição no doc | Tool real existente |
|---|---|
| Desconto / trava de margem | `apply_service_order_discount` |
| Registrar sinal/depósito ("cobra 50%") | `register_deposit_and_convert` (risk high) |
| Enviar cobrança | `send_collection_reminder` (risk high) |
| OC a partir de OS | `create_purchase_order_from_so` |
| Cadastrar fornecedor | `create_supplier` |
| Baixa / ajuste de estoque | `adjust_inventory` + `register_stock_entry` |
| Cadastrar produto | `create_product` |

**Fiscal NF-e/NFS-e NÃO é módulo ausente.** A camada já existe (`_shared/fiscal`: Contora,
payload-builder, nfe-sanitize; NF-e em produção). O que falta é **expor como tool do
agente**. Rebaixa a Seção F de "projeto complexo (SEFAZ/certificado)" para "1 tool que
chama a camada pronta".

---

## 1. Gaps REAIS (confirmados nome a nome)

1. **Remover / editar item de orçamento** — só existem `add_service_order_item`,
   `add_service_to_order`, `add_material_to_order`. **Não há remover nem editar.** ← gap real.
2. **Consolidar cotações** — não existe. ← gap real.
3. **Reserva de estoque** ao aprovar — não existe. ← gap real.
4. **Camada de orquestração** (comando-único / `aprovar_orcamento`) — é workflow, não tool.
5. **Emissão fiscal como tool** — `emitir_nfse_da_os` (nova), plugando em `_shared/fiscal`.

O "menu de 112 funcionalidades" fica como **backlog bruto de referência**, não como plano.
Detalha-se um bloco só quando entra na fila de build (método da Seção 0.1 do doc original).

---

## 2. Princípio de arquitetura

- **Fluxos nomeados + confirmar-plano-antes-de-executar.** Encaixa na régua de risco atual
  (low faz / medium+high pedem confirmação; high financeiro pede PIN).
- **Sub-agentes por domínio: adiar.** Com 63 tools ainda é gerenciável. Gatilho honesto para
  introduzir roteador/sub-agentes: passar de ~80 tools **E** haver erro medido de escolha de
  tool. Não antecipar.
- **Sem saga de rollback automático** (ver Bloco C). Idempotência + relatório de estado
  parcial + tarefa "resolver manual". Nunca desfazer cobrança/OS automaticamente.

---

## 3. Definição de Pronto (template universal — 9 pontos)

Todo item só é "definitivo, sem erros" quando responde: (1) Contrato da tool — casado a nome
real; (2) Banco + RLS por `company_id`; (3) Nível de risco + idempotência (trava atômica);
(4) UX painel; (5) UX WhatsApp; (6) Casos de borda; (7) Auditoria; (8) Testes Vitest;
(9) Critério de aceite verificável. **Gate entre blocos:** não avança sem os testes e o
aceite do bloco atual passando.

---

## 4. Ordem de execução (decisão: quick-wins primeiro)

### Bloco A — Orçamento editável  *(começar aqui: barato, isolado, uso diário)*
- **A.1 `remover_item_orcamento(service_order_id, item_id | descrição)`** — risk **baixo**;
  soft-delete p/ auditoria; recalcula total/margem; descrição ambígua → lista numerada.
- **A.2 `editar_item_orcamento(service_order_id, item_id, {quantidade?, preço?, desconto?})`**
  — risk **baixo** com **trava de margem** (reaproveita a lógica de `apply_service_order_discount`);
  rejeita qtd/preço ≤ 0 e desconto > 100%; grava de→para.
- Aceite: removo/edito item por linguagem natural, total e margem recalculam, com trilha.

### Bloco A′ — Ações de 1-clique no resumo matinal  *(quick-win de alto valor diário)*
- Botões "cobrar" / "follow-up" dentro do digest que **já existe** (`ai-daily-briefing`),
  disparando as tools prontas (`send_collection_reminder`, `schedule_self_reminder`).
- Sem digitar. Cada ação mantém a régua de risco (envio a cliente = confirma).
- Aceite: do resumo matinal eu disparo cobrança/follow-up em 1 toque, com confirmação.

### Bloco B — Comando por voz → plano → confirmação  *(FEITO via prompt — 2026-07-21)*
Decisão de design (conferida no loop): **NÃO** foram criadas tools `interpretar_comando`/
`confirmar_plano` — seria overengineering (o modelo chamaria uma tool p/ gerar um plano que ele
mesmo produz + máquina de replay). A arquitetura já tem o que basta:
- **B.3 clarificação** já existia: `AUTO_DISAMBIG` (clientes/embarcações/produtos/OS) + `present_options`.
- **Interceptação por risco** já faz short-circuit → card de confirmação por ação sensível.
- **B.1+B.2 entregue via PROMPT** (seção "PLANO ANTES DE EXECUTAR"): comando com 2+ ações de
  efeito (ou áudio 🎤) → o agente mostra o plano numerado e espera "sim" SEM chamar tool de
  escrita (turno só-texto encerra e aguarda); passos condicionais não rodam; ao confirmar,
  executa em ordem e as etapas sensíveis ainda batem no card. 1 ação só = executa direto.
- Se a robustez do "não executar antes do sim" se provar insuficiente na prática (low effort no
  WhatsApp), ENTÃO considerar mecanismo dedicado — medir antes.

### Bloco C — Workflow `aprovar_orcamento`  *(o coração — só depois de A e B estáveis)*
Sequência ao registrar aprovação: aprovar → faturar em OS → cobrança de sinal (%
configurável, `register_deposit_and_convert`) → lembrete de follow-up (`schedule_self_reminder`)
→ OC dos itens sem estoque (`create_purchase_order_from_so`) → agendar OS
(`schedule_service_order`).

> **Mapear no build:** "faturar orçamento em OS" = `update_quote_status` vs.
> `convert_external_quote_to_so` — confirmar qual reflete o fluxo de aprovação interno.

**Regra de ouro (minha recomendação forte): report-only, sem rollback automático.**
- Cada passo é tool idempotente que já existe.
- O workflow apresenta o plano, executa em sequência, reporta **✔/✖ por passo**.
- Falha parcial → **não desfaz nada** → cria tarefa "resolver manual" + avisa com o estado exato.
- Idempotente: aprovar 2× não duplica OS/cobrança.
- Aceite: aprovação dispara os passos, reporta ✔/✖ item a item, nunca duplica, e falha
  parcial deixa estado claro e recuperável (sem reversão automática).

### Bloco D — Compras & cotação  *(depende do canal estável — ver §5)*
- `sugerir_fornecedores` (histórico + `create_supplier`/categoria) — risk baixo.
- `enviar_cotacao(fornecedores[], itens[])` por WhatsApp — risk **sensível**, prévia + confirma.
- `consolidar_cotacoes` → comparativo preço/prazo (gancho p/ recomendar melhor — Fase 2).
- `cadastrar_produto_guiado` — reaproveita `create_product`, evita duplicata.

### Bloco E — Estoque
- Baixa automática ao concluir OS (idempotente; estorno na reabertura via `reopen_service_order`).
- **Reserva** de estoque ao aprovar (Bloco C); cancelamento libera; sem saldo → vira demanda de OC.

### Bloco F — Fiscal  *(realidade conferida no código — 2026-07-21)*
Correção importante ao plano: a camada `fiscal-emit` **só emite NF-e (produto)** —
`documentType="nfe"` fixo, com "NFS-e fica para a Fase 3". Como o MarineFlow é majoritariamente
serviço (OS), a **NFS-e que faria sentido a partir da OS não existe ainda**. Emitir também é
admin-only + SEFAZ real + exige montar payload rico (destinatário/endereço/itens/natureza) —
**não é quick-win**, é projeto próprio (confirma o Risco #3 original).

- **FEITO (só leitura, risco baixo):** `list_fiscal_documents` e `get_fiscal_document` — o
  agente consulta status/lista de notas emitidas ("a nota do fulano saiu?", "quais falharam?"),
  mas NUNCA emite/cancela/corrige. Deployado.
- **Emissão de NF-e a partir da OS** (bridge OS→payload, admin-only, confirma+PIN, só produto):
  backlog como projeto próprio, quando priorizado. NFS-e depende de novo provedor/módulo.

---

## 5. Dependência crítica (fora dos docs originais)

Bloco D e a camada proativa dependem do **WhatsApp entregar com confiabilidade**. Existe plano
aberto tratando do **"Aguardando mensagem"** (upgrade Evolution v2.3.0 → v2.3.7) + fix do
auto-lembrete (constraints do banco). **Estabilizar o canal antes de empilhar features que
disparam WhatsApp** — senão "bugs de feature" serão, na verdade, bugs de infra.

---

## 6. Pendências para fechar antes de codar cada bloco

- [x] Lista real das tools do agente — **feita** (63 tools mapeadas neste doc).
- [x] Modelo — **Claude via OpenRouter** (resolvido).
- [ ] Política de estado parcial do Bloco C — **decidida como report-only** (confirmar por escrito).
- [ ] Mapear "faturar orçamento" (`update_quote_status` vs `convert_external_quote_to_so`).
- [ ] Confirmar se o canal WhatsApp já foi estabilizado (plano v2.3.7) antes do Bloco D.
