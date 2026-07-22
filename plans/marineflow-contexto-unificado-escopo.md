# Escopo — Contexto unificado por entidade (Ciclo 2 · Fase 3)

> Ideia do dono: "uma memória que armazena o contexto de cada cliente, contato de WhatsApp e
> fornecedor, ligando OS, orçamentos, cotações — tudo unificado".
> Levantamento feito no banco canônico `okurngvcodmljjicopdp` em 22/07/2026.

## Princípio inegociável

**O banco continua dono do dado. A memória guarda só o que o banco não sabe.**
A "unificação" é **montagem em tempo de leitura** — nunca cópia. Criar um armazém que duplica
OS/orçamentos/cotações produziria uma segunda fonte de verdade que desincroniza (a mesma classe
de erro que quebrou o estoque nesta sessão).

## Mapa real de ligações (levantado)

| Entidade | Onde já se liga |
|---|---|
| **Cliente** (`client_id`) | vessels, service_orders, receivables, collections, invoices, issued_fiscal_documents, whatsapp_messages, external_quotes, agenda_tasks, ai_operator_memory_notes, client_whatsapp_settings |
| **Fornecedor** (`supplier_id`) | purchase_orders, payables, product_suppliers, products, quote_responses, service_order_expenses |
| **Ativo** (`vessel_id`) | service_orders, vessel_contacts, external_quotes, ai_operator_memory_notes |

**Descoberta-chave:** `ai_operator_memory_notes` **já tem** `client_id`, `vessel_id`, `topic`,
`confidence`, `source`, `source_reference` e fluxo de verificação (`verification_status`,
`verified_by/at`, `rejected_by/at`). A infraestrutura de memória por entidade **existe e está
ociosa** — hoje o agente só lê `scope='global'` e não há nenhuma nota gravada.

**Lacuna confirmada:** `supplier_id` **não existe** em `whatsapp_messages` nem em
`ai_operator_memory_notes`. Por isso a leitura de cotação hoje casa fornecedor por *últimos 8
dígitos do telefone* — heurística, não vínculo.

---

## ETAPA 1 — Ficha 360 (sem schema novo)

**Objetivo:** uma pergunta ("me resume o João") devolve tudo que se sabe, montado na leitura.

- **1.1** `get_client_360(client_id)`: dados do cliente · ativos com equipamentos · OS/orçamentos
  (abertos + últimos concluídos) · financeiro (a receber, vencido, total histórico) · últimas
  mensagens · notas fiscais · memória da entidade (quando a Etapa 3 existir).
- **1.2** `get_supplier_360(supplier_id)`: dados · produtos que fornece · últimas OCs · cotações
  (abertas/respondidas/ganhas) · contas a pagar · últimas mensagens.
- **1.3** Performance: teto por seção (top N), sem N+1; nunca varrer tabela inteira.
- **1.4** Cargo: técnico não vê financeiro — seções de dinheiro omitidas para `technician`.
- **1.5** Prompt: quando usar, e responder com a síntese antes do detalhe.
- **1.6** Validar contra dados reais (cliente e fornecedor que existam de fato).

**Pronto quando:** perguntando por um cliente real, o agente devolve um retrato coerente em
uma chamada, sem inventar seção vazia e sem estourar contexto.

---

## ETAPA 2 — Resolução de contato (WhatsApp → entidade)

**Objetivo:** saber de quem é um número, de forma durável, e parar de depender de heurística.

- **2.1** Investigar `client_whatsapp_settings` e como `whatsapp_messages.client_id` é preenchido
  hoje; medir quantas mensagens ficam sem dono.
- **2.2** Migration **aditiva**: `whatsapp_messages.supplier_id` (+ índice). Nenhuma coluna
  existente alterada.
- **2.3** Helper único de normalização/casamento de telefone (últimos 8 dígitos como chave —
  imune ao 9º dígito brasileiro), usado por todo mundo em vez de cópias espalhadas.
- **2.4** `identify_contact(phone | message_id)` → diz se é cliente, fornecedor, equipe ou
  desconhecido, com o motivo do casamento.
- **2.5** `link_contact_to_entity(message_id | phone, entity)` → ensina o vínculo e **persiste**
  nas mensagens daquele número (inclusive retroativo).
- **2.6** `read_supplier_messages` passa a usar a resolução oficial, mantendo o casamento por
  telefone como fallback.

**Pronto quando:** "de quem é esse número?" tem resposta; e ao ensinar uma vez, o vínculo
vale para as mensagens seguintes **e** para as anteriores daquele número.

---

## ETAPA 3 — Memória por entidade (ativar o que já existe)

**Objetivo:** o agente lembrar o que o banco não sabe — preferências, acordos, padrões.

- **3.1** Migration **aditiva**: `ai_operator_memory_notes.supplier_id` (+ índice). Reusar
  `scope`, `topic`, `confidence`, `source` e o fluxo de verificação já existentes.
- **3.2** `remember_about_entity(entity, título, nota, topic?)` → nasce como **sugerida**
  (`verification_status` pendente), nunca como verdade.
- **3.3** `list_entity_notes(entity)` e `review_entity_note(id, aprovar|rejeitar)`.
- **3.4** Carregamento contextual: no painel, `PromptRuntimeCtx` já traz `entityType`/`entityId`
  — injetar as notas **verificadas** daquela entidade (teto de N). No WhatsApp, as notas vêm
  pela ficha 360 quando a entidade entra em jogo.
- **3.5** Guardrails: só nota **verificada** é injetada; memória **nunca** contradiz o banco
  (dado é do banco, nota é conhecimento); teto de tokens; o agente não pode "promover" a
  própria nota — aprovar é do dono.
- **3.6** Testes da política de injeção (o que entra, o que nunca entra).

**Pronto quando:** eu digo "o João sempre pede 10% de desconto", aprovo, e na próxima conversa
sobre o João isso aparece sozinho — sem eu repetir.

---

## Ordem e por quê
1. **Ficha 360** — barata, valida a hipótese da "visão unificada" no mesmo dia.
2. **Resolução de contato** — destrava o WhatsApp e remove a heurística frágil.
3. **Memória por entidade** — exige critério (o que lembrar, quem aprova); vem por último.
