# "Deixar a IA acompanhar" — dossiê de pesquisa e proposta

**27/07/2026** · pesquisa em 18 frentes (≈150 fontes; as 106 citadas na §14) · ideia do usuário
registrada antes da pesquisa · complementa `marineflow-agenda-autonoma.md` (Fase 9, detecção) e
`marineflow-comunicacao-inteligente.md` (tom por interlocutor).

---

> ## ⚠️ REVISAR ANTES DE IMPLEMENTAR — metade disto já existe (achado em 02/08/2026)
>
> A branch **`session/agenda`** (worktree `marineflow-erp--agenda`, commit `2625d93`, Fases 13-14
> "Contexto Vivo") já entregou **`entity_open_loops`** — os "fios soltos":
>
> - Alimentado por **duas fontes**: fatos do ERP (OS ativa, materiais de OS a receber, orçamento
>   aguardando, título a vencer/vencido, **compra pendente**) e o que foi prometido na conversa.
> - A view **`erp_open_loop_facts`** é a fonte da verdade, recalculada por
>   `refresh_entity_open_loops()` dentro do motor de 15 min — **SQL puro, sem IA**.
> - **O fio FECHA SOZINHO** quando o fato sai da view, quando a tarefa vinculada conclui, quando a
>   OS encerra, ou por inatividade. Já rodou em produção: 24 fios abertos, 1 fechado sozinho.
>
> **Isso é exatamente o Princípio 1 (§3) e a camada 1 de resolução (§7) deste documento — já
> construídos.** Ou seja: a detecção e o fechamento determinístico **não precisam ser feitos de
> novo**. O que falta é só a **metade de saída: cobrar**.
>
> **Consequência para a §5 (arquitetura):** a tabela `ai_followup_missions` proposta ali
> **duplicaria** `entity_open_loops`. O desenho correto é a missão ser um **estado do fio solto**
> ("este fio foi delegado à IA para cobrar"), não um conceito paralelo. O resto do dossiê — os
> parâmetros da §6, as três paradas, a conformidade da §8, as fases — segue válido.
>
> **Pré-requisito:** `session/agenda` está **108 commits atrás da main** com 1 commit não mergeado.
> Precisa entrar na main antes de qualquer coisa ser construída em cima.

---

## 1. A ideia, na sua frase

> *"Um botão na tarefa que faz a IA acompanhar aquele compromisso com o terceiro. Tenho uma tarefa
> do Vanderlei Andrade que vai fornecer os equipamentos, e preciso acompanhar a entrega pra cumprir
> o prazo que eu prometi. Eu queria que a IA falasse com ele: 'Vanderlei, como está a entrega das
> baterias?' — e isso serve também pra compras acompanhar um pedido, e pro orçamento acompanhar se
> o cliente aprovou."*

Traduzindo para o que o sistema precisa fazer: **transformar um item do ERP numa missão de cobrança
com prazo, que a IA persegue junto a um terceiro até resolver — e que se encerra sozinha quando
resolver.**

O nome fica com você. Candidatos que dizem o que fazem: **"IA acompanha"**, **"Deixar a IA cobrar"**,
**"Acompanhar automaticamente"**. Uso "**missão de acompanhamento**" no resto do documento para o
conceito interno.

---

## 2. Diagnóstico: onde exatamente está o buraco

### 2.1 O ciclo hoje para no terceiro passo

```
   detectar  →  sugerir  →  [ COBRAR ]  →  resolver
   ✅ Fase 9    ✅ Fase 9      ❌ NADA        ❌ manual
```

A Fase 9 lê a conversa, extrai o compromisso e propõe a tarefa com a evidência literal. Aceita a
tarefa, **o sistema para**. Cobrar o Vanderlei volta a ser 100% memória humana — que é exatamente o
que o número "0 tarefas criadas manualmente" já provou que não acontece.

### 2.2 O que existe de follow-up, e por que não serve

| Peça | O que faz | Por que não resolve isto |
|---|---|---|
| `ai-whatsapp-followups` (cron */30) | pós-atendimento (2-7d após OS) e reativação (>6 meses) | **Réguas fixas por evento do sistema.** Não existe "acompanhe *este* compromisso" |
| `quote-reminders` (cron diário) | orçamento parado > N dias → lembrete | Idem: regra global, não missão específica com prazo |
| `receivable-reminders` | recebível vencendo | Idem |
| `task-automations` (cron 15min, 12 regras) | cria/resolve tarefa por estado do ERP | Cria trabalho para **você**, não fala com terceiro |
| `whatsapp_scheduled_sends` | agenda um envio | É o **trilho**, não o maquinista: não tem objetivo, prazo, nem critério de parada |
| `ai_operator_pending_actions` + `AIConfirmCard` | gate de aprovação com "Ajustar" | **Reaproveitável inteiro** — é o portão de cada envio na Fase 1 |

**Leitura:** o sistema tem disparadores por *evento*, e o que falta é acompanhamento por *objetivo*.
São coisas diferentes: a régua sabe "orçamento parado há 7 dias"; a missão sabe "o Vanderlei
prometeu as baterias e eu tenho até dia 12".

### 2.3 Números medidos hoje

| Métrica | Valor | Leitura |
|---|---|---|
| Tarefas na agenda | 57 (28 abertas) | Volume pequeno — bom para piloto, ruim para estatística |
| Tarefas com entidade vinculada | 44 de 57 | O vínculo já é hábito |
| Tarefas com **cliente** vinculado | 39 | — |
| Fornecedores com telefone | **396 de 530** | Base pronta para falar com fornecedor |
| `ai-whatsapp-followups` no cron | **ATIVO** | ⚠️ O comentário no código diz "DESATIVADO até validação" — **está errado**, o cron roda. Mesma classe de comentário obsoleto já encontrada no briefing |

### 2.4 🔴 O buraco que trava o caso emblemático

**`agenda_tasks` tem `client_id` e NÃO tem `supplier_id`.** As tools de agenda (`create_task`,
`update_task`, `list_tasks`) não conhecem fornecedor.

O seu exemplo — Vanderlei, que é **fornecedor** — não tem hoje como ser representado como
contraparte de uma tarefa. Isso não é detalhe de implementação: é a Fase 0 do plano. Resolver
"quem é a contraparte" de forma genérica é pré-requisito de tudo.

---

## 3. A tensão que este recurso cria (e que precisa ser resolvida de propósito)

Todo o funcionário digital foi construído sobre um princípio: **copiloto — a IA sugere, você
aprova.** As mensagens que saem hoje ou são determinísticas (lembrete de orçamento) ou passam por
você.

**Esta funcionalidade é diferente em espécie:** é a IA **conversando com um terceiro**, em nome da
HBR, **sem você no meio de cada turno**. Se ela errar, o erro não fica na sua tela — ele chega no
WhatsApp do Vanderlei, com o nome da sua empresa.

Isso não é motivo para não fazer. É motivo para fazer **com a autonomia entrando por último**, e é
o que estrutura as fases da §9.

> ### Princípio 1 — O ERP responde antes da pessoa
> Antes de todo toque, o sistema **relê o estado do ERP**. Se a nota já entrou, se o orçamento já
> foi aprovado, se a OS já foi concluída — a missão fecha sozinha e **ninguém é incomodado**.
> Cobrar algo que já foi entregue é o erro mais caro em relacionamento, e é 100% evitável sem IA.

> ### Princípio 2 — A IA se identifica
> Toda mensagem automática diz que é o assistente da HBR. Não é só conformidade (§8): um fornecedor
> que descobre depois que "conversou com um robô" perde a confiança na empresa inteira.

> ### Princípio 3 — Insistência tem teto, e o teto é baixo
> A missão tem número máximo de toques e prazo absoluto. Chegou ao fim sem resposta, ela **não
> insiste: devolve para você** com o histórico. Agente que não sabe parar é o modo de falha número
> um da literatura (§4.6).

---

## 4. O que a pesquisa mostrou (achados que mandam no desenho)

### 4.1 O padrão de UX já existe e se chama "enrollment" (fontes 1-8)
HubSpot/Salesloft/Outreach: você **inscreve** um contato numa sequência, e o mecanismo central é o
**auto-unenroll on reply** — respondeu, a sequência para sozinha. Vale notar a restrição que eles
adotaram: **um contato só pode estar em uma sequência por vez.**

> **Aplicado:** o botão é um "enroll". E adotamos a mesma trava: **um contato, uma missão ativa.**
> Duas missões simultâneas para o Vanderlei viram duas cobranças na mesma semana — e ele não
> distingue "a das baterias" da "a do pedido 4471"; ele só vê a HBR enchendo o saco.

### 4.2 Quantos toques (fontes 9-17)
Os números clássicos de vendas — *80% dos negócios exigem 5+ toques; 44% desistem no primeiro* —
vêm de **prospecção fria**, onde o outro lado não deve nada. **Não é o nosso caso:** o Vanderlei já
assumiu um compromisso. Para relação morna com obrigação assumida, a literatura de follow-up
converge em **3 a 5 toques, com fechamento explícito depois** — acima disso vira "pestering", e
o dano é de relacionamento, não de conversão.

> **Aplicado:** teto de **3 toques + 1 mensagem de encerramento**. Se a média real ficar colada no
> teto, o problema não é a cadência: é que o alvo não responde e a missão devia ter escalado antes.

### 4.3 Quando tocar (fontes 18-24)
Da automação de cobrança: *"lembrete amigável aos 7 dias é mais eficaz que carta dura aos 60"* —
começar cedo e espaçar. E o achado que mais importa: **cadência estática em B2B produz dois
problemas ao mesmo tempo** — bom pagador super-contatado e caso arriscado sub-contatado. A régua
tem que variar por valor, risco e relação.

> **Aplicado:** a cadência é **contada para trás a partir do prazo**, não fixa. Prazo em 10 dias →
> toques em D-7, D-3, D-1. Prazo em 3 dias → um toque só, hoje. Sem prazo → 2d/4d/7d.

### 4.4 Horário — e aqui a lei é explícita (fontes 25-31)
O CDC e as leis estaduais de cobrança fixam: **segunda a sexta 10h-21h, sábado 10h-13h, domingo e
feriado proibido.** Formalmente isso rege cobrança a consumidor, não conversa com fornecedor — mas
adotar a janela mais estrita é grátis, remove uma classe inteira de risco, e evita o pior sintoma
de robô: mensagem às 22h de domingo.

> **Aplicado:** janela ainda mais estreita — **seg-sex, 9h-18h**. Sábado não, porque fornecedor não
> responde sábado, e a mensagem só envelhece até segunda.

### 4.5 A IA precisa dizer que é IA (fontes 32-40)
O **Artigo 50 do AI Act europeu entra em vigor em 2 de agosto de 2026** — daqui a dias — exigindo
que sistemas que interagem com pessoas **avisem, na primeira interação**, que são IA. O Brasil
caminha na mesma direção com o **PL 2338/2023** (aprovado no Senado em dez/2024, em tramitação na
Câmara, modelo de risco espelhado no europeu, sanções de até R$ 50 milhões).

A HBR não está sob o AI Act. Mas a norma está convergindo, o custo de cumprir é uma frase, e o
custo de não cumprir é o Vanderlei descobrindo sozinho.

> **Aplicado:** toda mensagem de missão começa se identificando. Uma vez por missão, não em toda
> mensagem — repetir vira ruído.

### 4.6 Agente que não sabe parar (fontes 41-49)
Literatura consistente sobre loops infinitos em agentes: as condições de parada precisam ser
**verificáveis, não subjetivas**. *"Pare quando tiver 3 fontes"* funciona; *"pare quando terminar"*
não. As defesas recomendadas são camadas: teto de iterações, orçamento, timeout absoluto, detecção
de progresso, e critério de conclusão explícito. Há até trabalho sobre **envenenamento da condição
de término** — o terceiro conseguir manter o agente preso no loop.

> **Aplicado:** três paradas independentes — **teto de toques**, **prazo absoluto** e **resolução
> verificada**. Qualquer uma encerra. Nenhuma delas depende do julgamento do modelo.

### 4.7 Detectar que resolveu (fontes 50-57)
Classificação de resposta é problema conhecido: taxonomias de 3-5 classes, com automação tratando
apenas as inequívocas e humano ficando com o resto.

> **Aplicado:** três camadas, nessa ordem — (1) **o ERP mudou** (determinístico, sem IA, é a
> preferida); (2) **a resposta prova**, classificada pelo modelo em quarentena com evidência
> literal obrigatória (mesma trava do detector da agenda e da triagem de e-mail); (3) **prazo
> estourou** → escala. Nunca fechar por "achei que resolveu".

### 4.8 Quando devolver para o humano (fontes 58-64)
Suporte com IA em produção: **taxa mediana de escalonamento de 22%**; gatilhos principais são baixa
confiança (39%), pedido explícito do usuário (28%) e queda de sentimento (17%). E o achado
operacional: *"o handoff é onde a maioria das implantações perde valor"* — quem recebe precisa do
**histórico completo**, senão o cliente repete tudo.

> **Aplicado:** escala com o fio inteiro e uma linha de recomendação. Gatilhos: resposta ambígua,
> resposta negativa, sentimento ruim, pedido de parar, ou "quem é você?".

### 4.9 Autonomia se conquista por tipo, e se perde sozinha (fontes 65-73)
O padrão de autonomia graduada mais maduro: autonomia é **propriedade por habilidade**, não nível
global; promoção exige **evidência empírica + autorização humana registrada**; e **a demoção é
assimétrica — automática, sem esperar decisão humana.**

> **Aplicado:** cada *tipo* de missão (entrega de fornecedor, aprovação de orçamento, pedido de
> compra) sobe de nível sozinho ao acumular aprovações sem edição — e **cai sozinho** ao primeiro
> sinal ruim. Ver Fase 3.

### 4.10 Arquitetura: máquina de estado, não processo vivo (fontes 74-82)
Agentes de longa duração em produção são **duráveis**: estado persistido, checkpoint após cada
passo, retomada após queda. O padrão certo é job de fundo com estado em banco — não um loop
segurando contexto por dias.

> **Aplicado:** a missão é **uma linha no Postgres** e um cron que acorda. Encaixa exatamente na
> arquitetura que o MarineFlow já tem (14 crons). Zero infraestrutura nova.

### 4.11 🔴 O risco que pode custar o número (fontes 83-90)
A política do WhatsApp exige **opt-in para mensagem iniciada pela empresa**, respeito imediato a
opt-out, e trata **denúncia de spam como gatilho primário de suspensão**. E é explícita sobre APIs
não-oficiais: uso de ferramentas fora do canal oficial viola os termos e **aciona a detecção
automática de spam**.

**A HBR usa Evolution/Baileys — não-oficial.** Não é motivo para abandonar (a decisão de ficar no
Evolution já foi tomada e é consciente), mas **é motivo para esta funcionalidade ser a mais
comedida do sistema**: ela é a única que aumenta mensagens iniciadas pela empresa.

> **Aplicado:** teto global diário de mensagens de missão; só para contatos **com conversa
> existente** (nunca primeiro contato); opt-out honrado para sempre; e desligamento automático do
> tipo ao primeiro bloqueio.

### 4.12 O mercado já vai por aqui (fontes 91-106)
- **Jobber** tem follow-up automático de orçamento — mas **teto de 2 lembretes, texto fixo, só
  orçamento**. ServiceTitan idem via add-on de marketing. Nenhum dos dois faz missão sobre item
  arbitrário nem redige por contexto.
- Em compras existe categoria inteira chamada **"expediting"** — e já há plataformas com agentes
  de IA que perseguem pedido e validam compromisso de fornecedor.
- **Superhuman / Boomerang / Nudge** consolidaram o mecanismo: detectar ausência de resposta,
  redigir o follow-up com IA, e **parar sozinho quando a pessoa responde**.

> **Onde a HBR fica diferente:** nenhum deles amarra a cobrança ao **estado do ERP** (nota entrou,
> OS concluída, estoque baixou) para fechar a missão sem incomodar ninguém. Esse é o Princípio 1, e
> é vantagem real de quem tem o ERP e o WhatsApp no mesmo lugar.

---

## 5. Arquitetura proposta

### 5.1 O conceito: missão

```
   [ Botão em tarefa / compra / orçamento ]
                  │
                  ▼
        ai_followup_missions  ← uma linha, com OBJETIVO, CONTRAPARTE e PRAZO
                  │
     ┌────────────┴────────────┐
     ▼                         ▼
  cron acorda            webhook do WhatsApp
  (a cada hora)          (chegou resposta)
     │                         │
     │ 1. o ERP já resolveu?   │ classifica em quarentena
     │    → fecha, não fala    │ (evidência literal obrigatória)
     │ 2. está na janela?      │
     │ 3. tem toque devido?    ▼
     │    → redige         resolveu? → fecha
     ▼                     adiou?   → reagenda p/ nova data
  Fase 1: propõe p/ você   recusou? → escala p/ você
  Fase 3: envia direto     confuso? → escala p/ você
```

### 5.2 Tabelas (2)

```sql
ai_followup_missions (
  id, objetivo text,             -- "confirmar entrega das baterias"
  -- CONTRAPARTE genérica: resolve o buraco de supplier_id (§2.4)
  contraparte_tipo text,         -- 'client' | 'supplier' | 'lead'
  contraparte_id uuid,
  contraparte_phone text,        -- normalizado, congelado na criação
  contraparte_label text,        -- "Vanderlei Andrade"
  -- ORIGEM: de onde o botão foi apertado
  origem_tipo text,              -- 'agenda_task' | 'purchase_order' | 'quote'
  origem_id uuid,
  -- OBJETIVO VERIFICÁVEL: como o ERP prova que resolveu (Princípio 1)
  criterio_erp text,             -- 'po_received' | 'quote_approved' | 'manual'
  prazo_final timestamptz,
  -- CADÊNCIA
  max_toques int default 3,
  toques_feitos int default 0,
  proximo_toque_em timestamptz,
  autonomia text default 'draft',-- 'draft' (você aprova) | 'auto'
  status text default 'active',  -- active|resolved|escalated|cancelled|expired
  resolucao text, resolucao_evidencia text, resolvida_em timestamptz,
  criada_por uuid, created_at,
  -- a trava da §4.1
  constraint uma_missao_por_contato unique (contraparte_phone) where status='active'
)

ai_followup_events (
  id, mission_id fk, tipo,       -- 'touch_sent'|'reply'|'erp_resolved'|'escalated'|'skipped'
  conteudo text, classificacao text, evidencia text,
  created_at
)
```

### 5.3 O que é reaproveitado (quase tudo)

| Precisa | Já existe |
|---|---|
| Enfileirar/enviar WhatsApp | `whatsapp-send`, `whatsapp_send_queue` |
| Agendar envio futuro | `whatsapp_scheduled_sends` |
| Gate de aprovação com "Ajustar" | `ai_operator_pending_actions` + `AIConfirmCard` |
| Guarda de conformidade e tom | `_shared/ai/comms/send-guard.ts`, `voice-profiles.ts` |
| Classificação com evidência literal | padrão de `inbox-detector.ts` e `_shared/email/triage.ts` |
| Cron | pg_cron (14 jobs) |
| Silenciar contato | `mute_contact` / `whatsapp_leads.muted_at` |

**Código novo real:** uma edge `ai-followup-runner`, um classificador de resposta, o gancho no
webhook, a tabela, e o botão. O resto é ligação.

---

## 6. Parâmetros calibrados (o "embasamento" pedido)

| Parâmetro | Valor | De onde vem |
|---|---|---|
| Máximo de toques | **3 + 1 encerramento** | §4.2 — relação morna com obrigação assumida, não prospecção fria |
| Cadência | **contada para trás do prazo** (D-7, D-3, D-1); sem prazo: 2d/4d/7d | §4.3 — cadência estática falha nos dois extremos |
| Janela de envio | **seg-sex, 9h-18h** | §4.4 — mais estrita que o CDC (10-21h / sáb 10-13h) |
| Dois toques no mesmo dia | **proibido** | §4.2 |
| Missões simultâneas por contato | **1** | §4.1 — a trava do HubSpot |
| Identificação como IA | **1× por missão, no primeiro toque** | §4.5 — AI Act art. 50, PL 2338 |
| Teto global de mensagens de missão/dia | **10** (configurável) | §4.11 — proteção do número |
| Contato sem conversa prévia | **nunca** | §4.11 — opt-in |
| Escalonamento esperado | **~20-25%** das missões | §4.8 — mediana de mercado é 22% |
| Promoção para autonomia | **≥80% aprovado sem edição em ≥20 amostras do tipo** | §4.9 |
| Demoção | **automática, 1 sinal ruim basta** | §4.9 — assimetria deliberada |

---

## 7. As três camadas de "resolveu"

1. **ERP mudou (determinístico, preferida).** `criterio_erp` diz o que observar: pedido recebido,
   orçamento aprovado, OS concluída, nota lançada. Roda antes de todo toque. Fecha **sem falar com
   ninguém** — e é a única camada com 100% de certeza.
2. **Resposta prova.** Classificador em quarentena, sem tools, saída em enum
   (`resolvido` | `nova_data` | `nao_resolve` | `pare` | `pessoa_errada`), **evidência literal
   obrigatória** conferida contra o texto real. Sem evidência → escala, não fecha.
3. **Prazo estourou.** Escala para você com o fio inteiro. Nunca insiste além do teto.

**`nova_data` é o caso mais valioso e o mais fácil de errar:** "chega dia 12" deve reagendar a
missão e — se a tarefa de origem tiver prazo — avisar você que o prazo prometido ao cliente final
está em risco. É o elo que fecha o loop do seu exemplo.

---

## 8. Conformidade e segurança

| Frente | Regra adotada |
|---|---|
| **Identificação como IA** | Primeiro toque diz que é o assistente da HBR (§4.5) |
| **Horário** | Janela 9-18h seg-sex, mais estrita que o CDC (§4.4) |
| **Opt-out** | "não quero receber" → `muted_at` **permanente** + missão cancelada + você avisado |
| **WhatsApp** | Só contato com conversa existente; teto diário; bloqueio → desliga o tipo (§4.11) |
| **LGPD** | Dado já tratado (é cliente/fornecedor da HBR); base = execução de contrato/legítimo interesse; toda mensagem auditável em `ai_followup_events` |
| **Prompt injection** | Resposta do terceiro é **dado, nunca comando**. O classificador não tem tools e não pode encerrar missão, alterar prazo ou disparar ação — só rotular (§4.6, envenenamento de condição de término) |
| **Auditoria** | Todo toque, resposta e decisão gravados; `ai_operator_audit` para a trilha |

---

## 9. Fases

### **Fase 0 — Contraparte genérica** · ~1 dia · sem IA, sem envio
Resolver o §2.4: a missão carrega a própria contraparte (tipo/id/telefone/rótulo), sem depender de
`agenda_tasks` ganhar `supplier_id`. Tabelas criadas. O botão aparece e **cria a missão em modo
rascunho — nada é enviado.**
- **Portão:** criar a missão do Vanderlei de verdade e ver a linha correta no banco.

### **Fase 1 — Copiloto** · ~2-3 dias · a IA redige, você aprova
Cron acorda, checa o ERP, respeita a janela, redige o toque no seu tom e manda para **você** aprovar
pelo `AIConfirmCard` (com "Ajustar"). Você aprova → sai. **Zero envio autônomo.**
- **Portão:** 15 toques aprovados com **≥80% sem edição**. Abaixo disso, o problema é o texto — e
  autonomia em cima de texto ruim é escalar o erro.

### **Fase 2 — Fechamento sozinho** · ~2 dias
As três camadas da §7. A missão fecha quando o ERP muda ou a resposta prova, e escala quando não.
- **Portão:** **zero falso-fechamento** em 20 missões (fechar dizendo que resolveu quando não
  resolveu é pior que não fechar).

### **Fase 3 — Autonomia graduada por tipo** · ~2 dias
Tipos com ≥80% de aprovação sem edição em ≥20 amostras passam a **enviar direto**, com desfazer e
aviso no resumo matinal. Demoção automática ao primeiro sinal ruim.
- **Portão:** 30 dias de Fase 2 sem bloqueio nem reclamação.

### **Fase 4 — Os outros botões** · ~2 dias
O mesmo motor em **compras** (acompanhar pedido) e **orçamento** (acompanhar aprovação), que são os
dois casos que você citou. Aqui o `criterio_erp` fica forte: pedido recebido e orçamento aprovado
são estados que o sistema **já** conhece — boa parte das missões vai fechar sem nenhuma mensagem.

**Total: ~9-10 dias.** Valor real a partir da Fase 1.

---

## 10. Métricas e desligamento

| Métrica | Alvo | Se falhar |
|---|---|---|
| Aprovação sem edição | ≥80% | Não promove para autonomia; revisa o texto |
| Falso-fechamento | **0** | Bloqueia a Fase 3 |
| Média de toques por missão | <2,5 | Se colar em 3, a cadência ou o alvo estão errados |
| Missões resolvidas sem mensagem (camada ERP) | quanto maior, melhor | É a métrica de elegância do recurso |
| Escalonamento | ~20-25% | Muito abaixo = está fechando o que devia escalar |
| **Bloqueio ou pedido de parar** | **0** | **Desliga o tipo imediatamente** |

**Kill switch:** `app_settings.followup_missions_enabled = 'false'` para tudo sem deploy.

---

## 11. Fora de escopo

Ligação telefônica por IA · primeiro contato com quem nunca conversou com a HBR · negociação
(preço, prazo, condição) · missão sobre pessoa física sem relação comercial · mais de uma missão
por contato · missão sem prazo nem critério de fechamento · e-mail como canal (entra depois que o
piloto de e-mail estiver de pé).

---

## 12. Riscos

| Risco | Prob. | Impacto | Mitigação |
|---|---|---|---|
| **Cobrar algo já entregue** | Média | **Alto** — vergonha comercial | Princípio 1: relê o ERP antes de cada toque |
| **Ban do WhatsApp** (Evolution não-oficial) | Baixa-média | **Muito alto** — para o canal inteiro | Teto diário, só contato existente, opt-out permanente, desliga no 1º bloqueio |
| Falar com a pessoa errada | Média | Médio | Telefone congelado na criação; `pessoa_errada` escala |
| Terceiro tenta comandar o agente | Baixa | Médio | Classificador sem tools; resposta é dado, não comando |
| Você aprovar no automático (fadiga) | **Alta** | Médio | Volume baixo por desenho; se aprovação sobe e qualidade cai, reduz volume |
| Missão órfã (item cancelado) | Média | Baixo | Cancelamento do item cancela a missão |
| Prazo prometido ao cliente final furar | Média | Alto | `nova_data` avisa você quando a nova data estoura o seu prazo |

---

## 13. Decisões que preciso de você

1. **Nome do botão** — você disse que o nome já diz o que faz. Qual?
2. **Fase 1 fica quanto tempo?** Sugiro **30 dias** antes de liberar qualquer autonomia — é a IA
   falando com terceiros em nome da HBR.
3. **Fornecedor e cliente têm o mesmo teto?** Sugiro tratar **cliente com régua mais curta** (2
   toques): fornecedor atrasado é rotina, cliente cobrado demais é venda perdida.
4. **Começar por qual?** Sugiro **entrega de fornecedor** — é o seu caso real (Vanderlei), o dano de
   um erro é menor que com cliente, e o `criterio_erp` é limpo (nota entrou ou não entrou).

---

## 14. Fontes (106 de ≈150 consultadas)

**Enrollment e sequências (1-8)**
1. https://knowledge.hubspot.com/sequences/enroll-contacts-in-a-sequence
2. https://knowledge.hubspot.com/sequences/unenroll-from-sequence
3. https://consultevo.com/hubspot-unenroll-from-sequences/
4. https://www.4crms.com/blog/how-to-automate-hubspot-sequence-enrollment-and-unenrollment-for-contacts-via-workflows
5. https://blog.gorevx.com/guide-101-sequence-set-up-in-hubspot
6. https://community.hubspot.com/t5/HubSpot-Ideas/Remove-the-quot-Unenroll-contacts-from-sequence-if-they-reply-to/idi-p/508849
7. https://help.superhuman.com/hc/en-us/articles/45270478397203-Reminders-on-Autopilot
8. https://help.superhuman.com/hc/en-us/articles/40144492186515-Auto-Reminders-Auto-Drafts

**Cadência e número de toques (9-17)**
9. https://www.cirrusinsight.com/blog/sales-follow-up-statistics
10. https://pipeline.zoominfo.com/sales/sales-follow-up-statistics
11. https://ircsalessolutions.com/insights/sales-follow-up-statistics/
12. https://www.highspot.com/blog/sales-cadence/
13. https://coldemailmanifesto.com/sales-cadence
14. https://instantly.ai/blog/how-many-times-should-you-really-follow-up-with-a-prospect/
15. https://ditlead.com/blog/how-often-should-you-reach-out-to-your-prospects
16. https://skipcall.io/en/blog/b2b-sales-cadence
17. https://marketbetter.ai/blog/2026/02/22/sales-cadence-examples/

**Persistência sem estragar relação (18-24)**
18. https://www.scale-labs.com/en/blog/the-art-of-follow-up-how-to-stay-persistent-without-being-annoying
19. https://www.ringcentral.com/us/en/blog/customer-follow-up/
20. https://www.cartboss.io/blog/how-to-follow-up-with-customers/
21. https://lagrowthmachine.com/friendly-reminder-email-templates/
22. https://aircall.io/blog/support/customer-call-follow-up-strategies/
23. https://axiomworkspace.com/articles/crm-reminders-small-team-follow-ups/
24. https://www.sayanchor.com/post/sending-follow-up-email-sample

**Cobrança/dunning: cadência dinâmica (25-31)**
25. https://www.chaserhq.com/blog/what-is-dunning-in-accounts-receivables-and-how-to-optimize-it
26. https://www.quadient.com/en/blog/what-are-best-practices-accounts-receivable-automation-2026
27. https://blog.alguna.com/ar-automation-best-practices/
28. https://www.resolutai.com/blog/b-2-b-collections-best-practices
29. https://www.transformance.ai/blog-posts/accounts-receivable-automation-complete-2026-guide
30. https://www.brokenrubik.com/blog/netsuite-dunning-guide
31. https://www.cobmais.com.br/blog/horario-de-ligacao-de-cobranca/

**Horário legal de contato no Brasil (32-36)**
32. https://blog.monest.com.br/qual-horario-permitido-para-fazer-cobranca/
33. https://www.jusbrasil.com.br/artigos/e-permitido-fazer-cobranca-aos-sabados/742765408
34. https://portalcontraponto.com.br/capa/horarios-permitidos-ligacoes-cobranca-telemarketing-por-estado-e-ddd/
35. https://cdlcl.org.br/quais-os-horarios-corretos-para-proceder-com-cobranca-ao-consumidor-2/
36. https://www.jusbrasil.com.br/artigos/ligacoes-abusivas-de-cobranca-e-telemarketing-o-que-ninguem-te-contou-sobre-seus-direitos/4328158254

**IA precisa se identificar (37-46)**
37. https://artificialintelligenceact.eu/transparency-rules-article-50/
38. https://digital-strategy.ec.europa.eu/en/faqs/transparency-obligations-under-article-50-ai-act
39. https://bratby.law/ai-act-transparency-obligations-2026/
40. https://hard2bit.com/en/blog/ai-act-article-50-ai-transparency-chatbots-deepfakes/
41. https://techjacksolutions.com/ai-brief/eu-ai-act-article-50-compliance-requirements-august-2026/
42. https://labs.cloudsecurityalliance.org/research/csa-research-note-eu-ai-act-article-50-transparency-20260729/
43. https://www25.senado.leg.br/web/atividade/materias/-/materia/157233
44. https://exame.com/inteligencia-artificial/marco-legal-da-inteligencia-artificial-pl-2338-o-que-muda-para-empresas-com-a-nova-lei/
45. https://ialocus.com.br/blog/post-pl-2338-marco-legal-ia-brasil-2026.html
46. https://lbca.com.br/pl-2338-23-3-pontos-de-atencao-sobre-o-marco-regulatorio-da-ia/

**Condições de parada de agente (47-55)**
47. https://arxiv.org/pdf/2607.01641
48. https://arxiv.org/pdf/2605.05846
49. https://www.mindstudio.ai/blog/agent-loops-verifiable-stop-conditions
50. https://docs.bswen.com/blog/2026-03-11-prevent-ai-agent-infinite-loops/
51. https://inkog.io/glossary/infinite-loop-ai-agent
52. https://dev.to/alanwest/how-to-stop-your-llm-agent-from-looping-itself-into-oblivion-27eh
53. https://dev.to/mukundakatta/your-agent-loop-needs-a-real-exit-llm-stop-conditions-15bf
54. https://arxiv.org/pdf/2603.19896
55. https://www.cio.com/article/4064998/taming-ai-agents-the-autonomous-workforce-of-2026.html

**Classificação de resposta e detecção de resolução (56-63)**
56. https://www.unifygtm.com/explore/automate-reply-classification-follow-up
57. https://instantly.ai/blog/ai-reply-agent-for-sales-teams/
58. https://www.sequenzy.com/blog/ai-agent-email-reply-handling
59. https://www.annotera.ai/blog/intent-classification-for-ai-chatbots/
60. https://www.digitalgenius.com/blog/intent-detection-the-building-block-of-conversational-ai
61. https://chatboq.com/blogs/automated-responses-guide
62. https://blog.peppercloud.com/7-ways-ai-agents-are-killing-the-sorry-for-late-reply-culture/
63. https://sikdartechnologies.in/ai-customer-service-chatbots-fail/

**Escalonamento para humano (64-71)**
64. https://myaskai.com/blog/ai-confidence-thresholds-handoff
65. https://bluetweak.com/blog/ai-to-human-handoff
66. https://www.buildmvpfast.com/blog/agent-handoff-patterns-ai-human-escalation-confidence-threshold-2026
67. https://www.eesel.ai/blog/ai-chat-escalation
68. https://www.usefini.com/guides/best-ai-support-platforms-human-agent-escalation-2026
69. https://www.digitalapplied.com/blog/customer-service-ai-agent-statistics-2026-data
70. https://www.zoom.com/en/blog/ai-customer-service-agents/
71. https://leanonmarketing.com/blog/ai-agents-customer-support-deep-dive-2026

**Autonomia graduada (72-80)**
72. https://arxiv.org/pdf/2606.22484
73. https://arxiv.org/pdf/2604.23049
74. https://arxiv.org/pdf/2605.12105
75. https://arxiv.org/pdf/2606.04321
76. https://seanfalconer.medium.com/the-practical-guide-to-the-levels-of-ai-agent-autonomy-ac5115d3af26
77. https://www.emergentmind.com/topics/levels-of-autonomy-in-ai-agents
78. https://cordum.io/blog/human-in-the-loop-ai-patterns
79. https://www.swarmia.com/blog/five-levels-ai-agent-autonomy/
80. https://www.bantechsolutions.com/faq/how-do-you-maintain-human-oversight-of-autonomous-ai-systems/

**Agentes duráveis / longa duração (81-89)**
81. https://developers.googleblog.com/build-long-running-ai-agents-that-pause-resume-and-never-lose-context-with-adk/
82. https://zylos.ai/research/2026-04-24-durable-execution-agent-runtimes/
83. https://zylos.ai/research/2026-03-04-ai-agent-workflow-checkpointing-resumability/
84. https://pub.towardsai.net/durable-ai-agents-how-to-build-long-running-workflows-that-survive-crashes-restarts-and-real-c79b32c24cde
85. https://tianpan.co/blog/2026-03-07-async-agent-workflows-long-running-task-design
86. https://www.indium.tech/blog/7-state-persistence-strategies-ai-agents-2026/
87. https://www.augmentcode.com/guides/async-ai-agent-workflows
88. https://fast.io/resources/ai-agent-workflow-state-persistence/
89. https://inference.sh/blog/agent-runtime/durable-execution

**Política do WhatsApp e risco de banimento (90-96)**
90. https://whatsappbusiness.com/policy/
91. https://www.whatsable.app/blog/whatsapp-spam-policy-explained-for-businesses-in-2026
92. https://wetarseel.ai/whatsapp-business-api-opt-in-rules/
93. https://helo.ai/resources/blog/whatsapp-opt-in-complete-guide
94. https://zaple.ai/blog/whatsapp-bulk-messages-avoid-ban/
95. https://chakrahq.com/article/whatsapp-api-account-restricted-or-blocked-find-out-why-and-how-to-resolve/
96. https://www.chatappquestions.com/whatsapp/whatsapp-business/policy/

**Mercado: field service, compras e agentes de acompanhamento (97-106)**
97. https://help.getjobber.com/hc/en-us/articles/115012715008-Quote-Approvals
98. https://help.getjobber.com/hc/en-us/articles/24244124296471-Automations
99. https://www.getjobber.com/features/customer-communication-management/
100. https://ustechautomations.com/resources/blog/home-service-estimate-follow-up-automation-platform-comparison-2026
101. https://ustechautomations.com/resources/blog/automate-estimate-and-quote-followup-for-hvac-companies-2026
102. https://www.ivalua.com/blog/procurement-automation-software/
103. https://www.gartner.com/reviews/market/procurement-orchestration-platforms
104. https://valitract.com/best-purchase-order-automation-software/
105. https://www.boomeranggmail.com/l/email-follow-up-gmail.html
106. https://blog.superhuman.com/follow-up-on-emails/

---

*Nenhuma linha de código foi escrita para esta funcionalidade. Este é o embasamento pedido — a
execução depende das decisões da §13.*
