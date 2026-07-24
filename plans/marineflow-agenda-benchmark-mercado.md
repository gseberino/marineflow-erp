# MarineFlow — Benchmark Profundo de Mercado: Agenda & Tarefas

**24/07/2026** · 33 ferramentas analisadas em 5 categorias · fontes: reviews verificados (Capterra, G2, Trustpilot, Product Hunt), análises independentes 2025-2026, threads de usuários (r/productivity), pesquisa acadêmica sobre abandono de apps. Complementa `plans/marineflow-agenda-tarefas.md` (plano executado, Fases 0-4) e **fundamenta o roadmap atualizado (§10)**.

---

## 1. Metodologia

- **Categorias**: (A) tarefas pessoais/GTD, (B) planejamento diário e calendários com IA, (C) gestão de trabalho em equipe, (D) field service — o segmento do MarineFlow, (E) tarefas embutidas em CRM/sistema de negócio — o *padrão arquitetural* do MarineFlow.
- **Por ferramenta**: essência, funções ponto a ponto, o que usuários amam (evidência), o que reclamam (evidência), lição aplicável.
- **Critério de lição**: só entra no roadmap o que tem evidência de uso real — não "feature de brochura".

---

## 2. Categoria A — Tarefas pessoais & GTD

### A1. Todoist (o padrão-ouro de captura)
**Funções**: captura em linguagem natural ("sexta 14h ligar João" cria agendada); projetos/seções/subtarefas; labels + filtros salvos com query própria; prioridades P1-P4; recorrência em linguagem natural ("todo dia útil"); visão Hoje + Em breve; caixa de entrada (inbox) para capturar sem classificar; karma/streaks (gamificação leve); delegação em projetos compartilhados; lembretes por hora/local (pago); comentários e anexos por tarefa; templates de projeto; calendário (fraco); integrações massivas (e-mail, calendário, Zapier, API); assistente de IA (2025) para priorizar e sugerir horários; apps em TODAS as plataformas com sync impecável.
**Amam**: captura em 3 segundos, sync que nunca falha, confiabilidade ("just works"), recorrências poderosas.
**Reclamam**: sem *start dates* (só due); atrás em IA/automação; aumento de preço de ~40% (dez/2025) sem feature nova — revolta documentada; uma tarefa não pode ter 2 responsáveis; calendário fraco.
**Lição MarineFlow**: captura sem atrito é O recurso nº 1 da categoria — nossa captura por linguagem natural via agente IA (chat/WhatsApp) é equivalente e precisa ser *promovida na UI* (hoje está escondida no widget). Inbox de captura rápida sem classificar é gap nosso.

### A2. TickTick (o canivete suíço)
**Funções**: tudo do Todoist +: calendário próprio com drag-and-drop hora a hora; timer Pomodoro embutido; habit tracker; matriz de Eisenhower (urgente×importante, auto-organizada); anotações de voz; widgets; duração estimada em tarefa; "won't do" como status final.
**Amam**: relação preço/recursos, calendário forte, tudo-em-um.
**Reclamam**: excesso de recursos vira procrastinação de configuração ("passei mais tempo ajustando que fazendo"); preocupações de privacidade (domínio chinês); glitches; free limitado.
**Lição**: mais função ≠ mais uso. A matriz de Eisenhower é interessante como VISÃO (nossa prioridade × vencimento já dá os eixos), mas o alerta anti-bloat vale mais que a feature.

### A3. Things 3 (o design que vicia)
**Funções**: Hoje/Esta noite (separação dentro do dia!); Anytime/Someday (compromisso psicológico gradual); headings dentro de projetos; checklist dentro de tarefa; datas de início ≠ prazo; "Logbook" de concluídas por dia; captura global por atalho; zero fricção visual.
**Amam**: a experiência mais polida da categoria; "Logbook" é referência de visão de concluídas.
**Reclamam**: só Apple; compra separada por dispositivo; sem colaboração; sem web.
**Lição**: nosso DoneView (Concluídas por dia) segue o padrão Logbook — certo. "Esta noite" (sub-bucket do dia) é refinamento válido para técnicos (manhã/tarde).

### A4. OmniFocus (o GTD hardcore)
**Funções**: perspectives (visões custom por filtro salvo); defer dates; revisão semanal guiada (o app te obriga a revisar projetos); contextos/tags ilimitadas; sequencial vs paralelo em projetos.
**Amam**: poder absoluto para GTD sério. **Reclamam**: complexidade; curva íngreme; só Apple.
**Lição**: "revisão guiada" é ideia forte adaptável ao nosso briefing semanal (IA propõe: o que está parado, o que descartar). Perspectives = nossos filtros salvos (já temos via FilterPresets).

### A5. Microsoft To Do
**Funções**: My Day (planejamento diário que zera à meia-noite — puxa sugestões de atrasadas); listas compartilhadas; integração profunda Outlook (e-mails viram tarefas); grátis total.
**Amam**: grátis, simples, My Day "zera" o dia sem culpa. **Reclamam**: sem recursos avançados; sem tags reais.
**Lição**: o conceito "My Day zera e re-sugere" é anti-acúmulo de culpa — nosso Hoje já re-deriva do zero diariamente (certo por construção).

### A6. Google Tasks / A7. Apple Reminders
**Funções (Tasks)**: listas simples, integração Gmail/Calendar, estrela. **(Reminders)**: listas inteligentes, lembrete por local/hora, compartilhamento familiar, captura por Siri.
**Amam**: fricção zero, embutidos no ecossistema. **Reclamam**: fracos para qualquer metodologia; sem visões.
**Lição**: distribuição embutida vence app separado — é exatamente a nossa tese (tarefas DENTRO do ERP, não em app à parte). Validação da arquitetura.

### A8. Any.do
**Funções**: "Momento diário" (revisão guiada de 2 min); agenda + tarefas + listas de mercado; UI bonita.
**Amam**: interface. **Reclamam**: recursos rasos, paywall agressivo.
**Lição**: revisão diária guiada de 2 minutos é padrão consolidado (3ª ferramenta com isso) — candidata forte ao roadmap.

### A9. Superlist
**Funções**: subtarefas em níveis ilimitados; notas ricas DENTRO de tarefa (listas, imagens, anexos); tarefas dentro de notas; AI meeting notes; export CSV.
**Amam**: estética + notas ricas. **Reclamam**: jovem, integrações no plano pago.
**Lição**: anexos/notas ricas em tarefa é gap nosso (temos notes texto). Export CSV das tarefas = pedido básico de relatório.

---

## 3. Categoria B — Planejamento diário & calendários IA

### B1. Motion (auto-scheduling máximo — e o alerta)
**Funções**: IA agenda TODAS as tarefas no calendário automaticamente (deadline+prioridade+dependências); replaneja o dia dezenas de vezes; aviso proativo "vai estourar o prazo"; project management; docs/sheets/AI chat (pivô "super app").
**Amam**: quem se adapta, não planeja mais nada manualmente; aviso de risco de prazo.
**Reclamam** (muito): mobile 2,7/5; UI cluttered; preço subindo ($49/mês) + créditos de IA; "agenda opressiva" (encher cada minuto); "virou clone ruim de ClickUp"; onboarding difícil; abandono documentado em 2026.
**Lição CRÍTICA**: auto-scheduling total é rejeitado por sensação de perda de controle; feature bloat mata produto bom. Nossa decisão (IA sugere, humano confirma) está validada pelo fracasso do extremo oposto. O que IMPORTAR: o *aviso de risco de prazo* ("isso não vai caber"), não o agendamento automático.

### B2. Reclaim.ai (o equilíbrio que funciona)
**Funções**: Habits (recorrências flexíveis que acham espaço sozinhas em janelas definidas); Focus Time protegido; buffer entre compromissos; prioridades P1-P4 que decidem o que cede; task sync com Todoist/etc.; analytics de tempo (quanto foi p/ reunião vs foco); defesa automática de horário de almoço.
**Amam**: "smart scheduling que genuinamente funciona"; flexível sem ser ditatorial.
**Reclamam**: só Google Calendar; curva das configurações.
**Lição**: recorrência FLEXÍVEL ("toda semana, em qualquer horário livre de manhã") é mais realista que hora fixa — refinamento futuro da nossa recorrência. Analytics de tempo é a extensão natural do nosso DoneView.

### B3. Sunsama (o ritual)
**Funções**: ritual diário guiado (revê ontem → escolhe 3 prioridades → estima horas → timebox no calendário); alerta anti-sobrecarga (>6h de trabalho profundo = "você está se preparando para falhar"); shutdown ritual no fim do dia; puxa tarefas de Asana/Trello/e-mail; canais por contexto.
**Amam**: a calma; o limite de carga honesto; mobile completo.
**Reclamam**: 15 min/dia de ritual é caro; $192-240/ano; poucas integrações.
**Lição**: *alerta de sobrecarga* (mais horas agendadas que horas úteis do dia) é simples e valioso — cabe no nosso Hoje e no agendamento de OS por técnico. O briefing 07:30 já é nosso "ritual matinal" automatizado — ninguém do mercado tem isso empurrado por WhatsApp.

### B4. Akiflow
**Funções**: captura universal (Slack/e-mail/Asana → inbox única) com atalhos de teclado; command bar; time-boxing por arrastar; rituais configuráveis; slots de disponibilidade compartilháveis.
**Amam**: velocidade de triagem por teclado. **Reclamam**: mobile fraco; sync ocasional.
**Lição**: inbox única de captura + triagem rápida. Nosso equivalente: mensagens de WhatsApp de clientes → sugestão de tarefa (já parcialmente no radar do agente; formalizar como "Caixa de entrada" na Agenda é candidato).

### B5. Morgen / B6. Fantastical / B7. Amie / B8. Structured / B9. Google Calendar (Tasks embutidas)
**Funções-chave**: Morgen — agrega múltiplos calendários + tasks de várias fontes, workflows de planejamento; Fantastical — parsing de linguagem natural impecável de eventos, propostas de horário; Amie — calendário-primeiro com tarefas dentro, estética "joyful"; Structured — timeline visual do dia (linha do tempo vertical), simplicidade extrema; Google Calendar — tasks no próprio calendário, "não concluída rola para amanhã".
**Lições agregadas**: (1) timeline vertical do dia (Structured) é a visão de dia que falta ao nosso mobile de técnico; (2) rolagem automática de tarefa não-feita para o dia seguinte (Google) — nós fazemos via "Atrasadas" (melhor: mantém a verdade); (3) parsing de linguagem natural nos INPUTS da UI (não só no chat) diferencia a experiência.

---

## 4. Categoria C — Gestão de trabalho em equipe

### C1. Asana
**Funções**: projetos multi-visão (lista/board/timeline/calendário); dependências; metas (OKR) ligadas a trabalho; regras de automação (se mover para coluna → atribuir); formulários de entrada; aprovações como tipo de tarefa; portfólios; workload por pessoa (capacidade); campos custom.
**Amam**: estrutura p/ processos; 4,4-4,7/5 no G2. **Reclamam**: caro; ritmo de evolução lento; complexo p/ times pequenos.
**Lição**: *workload por pessoa* (barra de capacidade diária) é exatamente o que a grade semanal do MarineFlow pode ganhar com pouco esforço (soma de horas de OS+compromissos por dia/técnico).

### C2. ClickUp
**Funções**: "tudo app": tarefas, docs, metas, chat, whiteboard; 15+ visões; automações; campos custom; time tracking nativo; dashboards; IA.
**Amam**: preço/recurso. **Reclamam** (G2, consistente): UI esmagadora, lento com volume, bugs — o caso clássico de bloat.
**Lição**: reforço do anti-bloat. Não perseguir paridade de features; perseguir fluxo do dia.

### C3. Monday.com
**Funções**: boards visuais modulares; automações "quando X então Y" em linguagem visual; dashboards; formulários.
**Amam**: onboarding rápido, visual (4,7/5 G2 — o maior da categoria). **Reclamam**: preço explode com o time (40-60% mais caro que ClickUp em 50+ seats); times migram ao crescer.
**Lição**: automação apresentada em "quando X → então Y" legível é como nossos toggles de regras deveriam evoluir (mostrar a frase da regra, não só on/off) — barato e didático.

### C4. Trello
**Funções**: kanban puro; Butler (automação sem código: regras, botões, agendados); power-ups.
**Amam**: simplicidade + free generoso; 76% sentimento positivo. **Reclamam**: estagnado (Atlassian prioriza Jira); paywall de power-ups.
**Lição**: kanban por STATUS não nos serve (nosso status é binário), mas kanban por PESSOA na semana já temos (grade). Butler valida automação declarativa acessível.

### C5. Notion
**Funções**: databases flexíveis com visões; automações por gatilho; tarefas dentro de docs; templates.
**Amam**: flexibilidade/preço. **Reclamam**: vira "construir o sistema" em vez de usar; estrutura degrada com o time; permissões confusas.
**Lição**: flexibilidade infinita transfere o trabalho de design para o usuário — nossa opinião forte (visões fixas bem escolhidas) é a escolha certa para uma equipe operacional.

### C6. Linear
**Funções**: issues com ciclos (sprints); triage inbox; atalhos de teclado em tudo; velocidade obsessiva; auto-archive; "projetos" com health.
**Amam**: a ferramenta mais rápida da categoria; foco. **Reclamam**: nicho dev; pouco flexível.
**Lição**: performance é feature. Cada visão nossa deve abrir < 1s; triage inbox reaparece (3ª vez) como padrão.

---

## 5. Categoria D — Field service (o nosso segmento)

### D1. Jobber (4,6/5 Capterra — o benchmark SMB)
**Funções**: agenda drag-and-drop (dia/semana/mês/mapa); request → quote → job → invoice num fluxo; lembretes por SMS/e-mail ao cliente (reduz no-show comprovadamente); "on my way" text; GPS leve; app do técnico com fotos/notas/assinatura; portal do cliente; follow-up automático de orçamento; pagamentos.
**Amam**: facilidade; agenda + orçamento + fatura num app só; time savers do fluxo completo.
**Reclamam**: recorrências de agendamento limitadas (sem quinzenal/mensal!); bugs intermitentes; suporte lento; sente-se limitado quando o time cresce.
**Lição**: o fluxo conectado (orçamento→OS→fatura) o MarineFlow JÁ TEM mais profundo (fiscal incluso). Onde Jobber ganha de nós: lembrete "estou a caminho" ao cliente e visão-mapa. Onde já ganhamos: nosso R6/R9 cobrem follow-up e lembrete; recorrência nossa já faz mensal (deles não!).

### D2. Housecall Pro (4,7/5 Capterra)
**Funções**: agendamento online pelo cliente; comunicação automatizada (confirmação, a caminho, pós-serviço); price book; pipeline visual de jobs; avaliação pós-serviço automática.
**Amam**: setup fácil; comunicação automática com cliente. **Reclamam**: navegação confusa com muitos recursos.
**Lição**: *pesquisa pós-serviço automática* (mensagem 1 dia após concluir OS pedindo avaliação) é regra R-nova de alto valor comercial e custo mínimo (nossa fila WhatsApp já existe).

### D3. ServiceTitan (enterprise)
**Funções**: dispatch board com skills/localização/receita por job; capacity planning; roteirização por tráfego; telefonia integrada; memberships/contratos recorrentes; relatórios profundos.
**Amam**: potência enterprise. **Reclamam** (muito): onboarding complexo, caro, suporte ruim.
**Lição**: contratos de manutenção recorrente (membership) geram OS automaticamente — o MarineFlow tem o embrião disso na sugestão de revisão 12+ meses do briefing; formalizar "plano de manutenção por embarcação" é diferencial de receita recorrente para a HBR.

### D4. ServiceM8 (3,8/5 G2) / D5. Workiz (4,5/5) / D6. FieldPulse (4,7/5)
**Funções-chave**: ServiceM8 — checklists de job obrigatórios, badges de status em tempo real; Workiz — franquias de nicho, telefone+SMS embutido, free tier; FieldPulse — mobile-first, timesheets, formulários custom por tipo de job.
**Reclamam**: lags (M8), mobile limitado (Workiz), glitches em integrações (FieldPulse).
**Lição**: checklist obrigatório por TIPO de serviço (template de checklist ao criar OS/tarefa de um tipo) aparece como padrão do segmento — nosso checklist existe mas não tem templates.

---

## 6. Categoria E — Tarefas dentro de CRM/sistema (o nosso padrão arquitetural)

### E1. Pipedrive (activity-based selling)
**Funções**: TODA negociação deve ter uma próxima atividade agendada — o app marca visualmente deal "sem próxima ação" como podre; atividade concluída pede imediatamente a próxima; lembretes; automação leve (deal parado → tarefa).
**Amam**: a disciplina "sempre existe um próximo passo" aumenta conversão comprovadamente.
**Lição TOP**: **"toda entidade ativa tem próxima ação"** é a versão CRM da nossa tese. Aplicar como indicador: OS/orçamento/cobrança ativos SEM tarefa viva vinculada = flag "sem próximo passo" no painel e no overview do agente. É a inversão elegante do nosso motor (que já cria as ações) — o indicador pega o que as regras não cobrem.

### E2. HubSpot
**Funções**: filas de tarefas (task queues — trabalhar em lote: 20 follow-ups em sequência com um clique "próxima"); sequences (e-mail+tarefa alternados); workflows visuais.
**Lição**: *fila de execução em lote* ("modo foco: me dê a próxima tarefa") é ótima para o financeiro fazer cobranças em série — e conversa direto com nosso agente ("me passa uma por uma").

### E3. Salesforce
**Funções**: tasks/events nativos em qualquer objeto; Einstein sugere próximas ações; process builder.
**Lição**: confirmação da arquitetura polimórfica (tarefa em qualquer entidade) — já implementada por nós.

---

## 7. Por que usuários ABANDONAM (síntese da evidência)

1. **Abandono é mais agudo no início** (pesquisa: curva de abandono cai forte nas primeiras semanas) → as primeiras 2 semanas do time no MarineFlow decidem tudo; o motor criando tarefas sozinho é nossa vacina (o app nunca está vazio).
2. **Fricção de captura mata** (tema nº 1 em Todoist-vs-resto) → captura por WhatsApp/chat precisa ser ensinada ao time.
3. **Feature bloat mata** (Motion, ClickUp, TickTick) → cada feature nova deve remover um passo do dia, não adicionar uma tela.
4. **Perda de controle mata** (auto-scheduling do Motion) → IA sugere, humano decide. Mantido.
5. **Quebra de confiança mata** (preço, perda de dados, tarefa que "volta do nada") → o bug que você achou ontem era EXATAMENTE isso; corrigido com a dispensa manual. Zero tolerância a comportamento "mágico" não explicado.
6. **Lista longa sem hierarquia paralisa** (pesquisa) → Hoje com 3 seções + prioridade visual; nunca "one big list".
7. **O que não mostra progresso é abandonado** → visão Concluídas + métricas (agora existentes) são retenção, não vaidade.

---

## 8. Matriz consolidada — função × mercado × MarineFlow

Legenda: ✅ temos · 🟡 parcial · ❌ não temos · [padrão] = presente na maioria da categoria

| Função | Onde é padrão | MarineFlow |
|---|---|---|
| Captura linguagem natural | A (todos os líderes) | ✅ via agente (chat/WhatsApp) — 🟡 não há atalho na UI da Agenda |
| Inbox de captura sem classificar | A/B (Todoist, Akiflow, Linear) | ❌ |
| Visão Hoje (atrasadas/hoje) | A (todos) | ✅ |
| "Logbook" de concluídas | Things, todos C | ✅ (DoneView, novo) |
| Recorrência | todos | ✅ subset RRULE (Jobber nem tem mensal!) |
| Recorrência flexível ("qualquer horário na janela") | Reclaim | ❌ (refinamento) |
| Lembretes multi-canal | A/B/D | ✅ app + WhatsApp interno |
| Anti-conflito de horário | B/D | ✅ no BANCO (ninguém da amostra tem garantia nesse nível) |
| Auto-criação por evento do negócio | D (parcial), E (parcial) | ✅ 12 regras + auto-resolução (nosso diferencial nº 1) |
| Tarefa vinculada a entidade | E (todos) | ✅ polimórfico |
| Botão de ação que resolve a tarefa | E (Pipedrive/HubSpot) | ❌ (chip só navega) |
| "Sem próxima ação" flag | Pipedrive | ❌ **alto valor** |
| Fila de execução em lote | HubSpot | ❌ |
| Checklist em tarefa | A/C/D | ✅ — 🟡 sem templates por tipo |
| Workload/capacidade por pessoa | Asana, ServiceTitan | ❌ (grade mostra itens, não carga) |
| Alerta de sobrecarga do dia | Sunsama | ❌ |
| Aviso "prazo em risco" | Motion | 🟡 (briefing lista atrasadas; não prevê risco) |
| Timeline vertical do dia (mobile) | Structured, B | ❌ |
| Drag-and-drop agenda | todos B/C/D | ✅ (semana desktop) |
| Lembrete ao cliente (no-show) | D (todos) | ✅ R9 (off) + R10 interno |
| "Estou a caminho" ao cliente | Jobber/Housecall | ❌ |
| Pesquisa pós-serviço | Housecall | ❌ regra nova barata |
| Contrato/manutenção recorrente → OS | ServiceTitan | 🟡 (só sugestão no briefing) |
| Agendamento online pelo cliente | Housecall | ❌ (fora de escopo declarado) |
| Métricas de execução | C (dashboards) | ✅ DoneView + get_task_metrics |
| Export CSV | Superlist etc. | ❌ (barato) |
| Ritual diário guiado | Sunsama/Any.do/MS To Do | ✅ automatizado (briefing 07:30 push) — melhor que o mercado: chega sozinho |
| Revisão semanal guiada | OmniFocus | ❌ (briefing semanal do agente) |
| Filtros salvos | A/C | ✅ (FilterPresets) |
| Notas ricas/anexos em tarefa | A9/C | 🟡 (texto simples) |

**Leitura honesta**: em *motor de automação + integração com o negócio + entrega proativa (briefing por WhatsApp)*, o MarineFlow já está à frente de tudo que foi analisado — nenhuma das 33 tem funcionário IA operando a agenda dentro do ERP. Os gaps reais estão na **camada de execução** (ação direta, fila em lote, "sem próxima ação") e na **camada de percepção de carga** (workload, sobrecarga, risco de prazo).

---

## 9. Gap analysis priorizado (por evidência × esforço)

| # | Gap | Evidência | Esforço |
|---|---|---|---|
| 1 | Botão de ação que resolve (registrar pagamento, receber OC, agendar OS pré-preenchidos) | Pipedrive/HubSpot; nossa tarefa hoje é aviso navegável, não alavanca | M |
| 2 | Flag "sem próxima ação" em OS/orçamento/cobrança ativos | Pipedrive (comprovadamente aumenta conversão) | S |
| 3 | Quick-add com linguagem natural NA UI da Agenda (input que chama o agente) | Todoist/Fantastical: captura é o recurso nº 1 | S |
| 4 | Fila de execução em lote ("próxima tarefa →") | HubSpot task queues | M |
| 5 | Workload na semana (h agendadas/dia/pessoa + alerta de sobrecarga) | Asana workload + Sunsama alerta | M |
| 6 | Pesquisa pós-serviço automática (R13) + "estou a caminho" | Housecall/Jobber | S (fila já existe) |
| 7 | Templates de checklist por tipo de serviço | ServiceM8/FieldPulse | S |
| 8 | Planos de manutenção por embarcação → OS recorrente | ServiceTitan memberships; receita recorrente p/ HBR | L |
| 9 | Revisão semanal guiada pelo agente (segunda 08h: parados, descartar, semana) | OmniFocus review + nosso briefing | S |
| 10 | Inbox de captura (mensagens/ideias → triagem) | Akiflow/Linear triage | M |
| 11 | Export CSV de tarefas/concluídas | padrão básico | S |
| 12 | Recorrência flexível + timeline do dia mobile + notas ricas | Reclaim/Structured/Superlist | M/L |

---

## 10. ROADMAP ATUALIZADO — Fases 5-8

> Fases 0-4 concluídas (23-24/07/2026, ver plano principal). Gates iguais: worktree, testes, migration nomeada, mensagem nova a cliente sempre nasce OFF.

### Fase 5 — Execução sem sair do lugar (o clique que resolve) — 1-2 sessões
1. **Ações diretas na tarefa**: cobrança → "Registrar pagamento" (PaymentDialog pré-carregado); R1 → QuickSchedule com OS selecionada; R7 → "Receber OC"; R8 → "Criar OC".
2. **Quick-add na Agenda**: input "adicionar tarefa…" com parsing pelo agente (mesma tool create_task) — captura de 3 segundos na UI.
3. **Flag "sem próxima ação"**: badge em OS/orçamento/cobrança ativos sem tarefa viva; seção no `get_situation_overview`.
4. Export CSV (Hoje + Concluídas).
**Aceite**: concluir uma cobrança REGISTRANDO o pagamento a partir da tarefa em ≤ 2 cliques; criar tarefa por texto na Agenda em ≤ 3 s.

### Fase 6 — Carga e risco (a agenda que protege o time) — 1-2 sessões
1. **Workload na semana**: soma de horas (OS+compromissos) por pessoa/dia na grade; barra de capacidade (jornada configurável); célula fica âmbar/vermelha em sobrecarga.
2. **Alerta de sobrecarga** ao agendar (UI e tool): "João já tem 7h nesse dia".
3. **Risco de prazo no briefing**: tarefas/OS com due amanhã + dia lotado = "em risco".
4. **Fila de execução** ("modo foco"): botão na visão Hoje → uma tarefa por vez, concluir/adiar/pular; e comando "me passa uma por uma" no agente.
**Aceite**: agendar 8h num dia de 6h úteis dispara alerta; fila percorre as tarefas do financeiro em sequência.

### Fase 7 — O ciclo do cliente (receita e reputação) — 1-2 sessões
1. **R13 pesquisa pós-serviço** (D+1 após concluir OS, WhatsApp, nasce OFF).
2. **"Estou a caminho"**: botão do técnico na OS do dia → mensagem ao cliente (gate de confirmação).
3. **Templates de checklist por tipo de serviço** (cadastro em Settings; aplicados na criação).
4. **Revisão semanal guiada** (segunda 08h via agente: parados 7+ dias, sugestões de descarte, prévia da semana).
**Aceite**: OS concluída gera pesquisa em D+1 (em modo teste); checklist padrão aparece ao criar tarefa de um tipo mapeado.

### Fase 8 — Manutenção recorrente (o ServiceTitan da marina) — 2-3 sessões
1. **Planos de manutenção por embarcação** (periodicidade, escopo padrão, valor).
2. Motor: plano vence → tarefa "Propor revisão" + orçamento-rascunho pela IA.
3. Visão "Planos" (ativos, vencendo, taxa de conversão).
**Aceite**: plano cadastrado gera proposta automática na janela; conversão medida no BI.

### Deliberadamente ADIADO (com motivo)
Auto-scheduling total (Motion provou o rechaço) · agendamento online pelo cliente (canal é o WhatsApp) · GPS/rotas (1 equipe local) · gamificação/karma · notas ricas com anexos (esperar demanda real) · timeline vertical mobile (reavaliar após Fase 6).

---

## 11. Fontes principais

Todoist: [Efficient App](https://efficient.app/apps/todoist) · [The Business Dive](https://thebusinessdive.com/todoist-review) · [Capterra](https://www.capterra.com/p/149339/Todoist-for-Business/reviews/) | TickTick: [comparativo](https://techwiseinsider.com/todoist-vs-ticktick-ive-tried-them-both-and-heres-the-winner/) | Motion: [Saner.ai reviews](https://blog.saner.ai/motion-reviews/) · [alternativas 2026](https://temporal.day/blog/best-motion-alternatives-2026) · [Efficient App](https://efficient.app/apps/motion) | Reclaim: [ClickUp review](https://clickup.com/learn/topic/productivity/tools/reclaim/) · [Lifestack](https://lifestack.ai/blog/reclaim-ai-review) | Sunsama/Akiflow: [Morgen](https://www.morgen.so/blog-posts/sunsama-vs-akiflow) · [Ellie](https://ellieplanner.com/comparisons/sunsama-vs-akiflow) · [Productive with Chris](https://productivewithchris.com/comparisons/sunsama-vs-akiflow/) | Asana/ClickUp/Monday: [Tech-Insider](https://tech-insider.org/asana-vs-monday-2026/) · [SaaSprobe](https://saasprobe.com/compare/clickup-vs-monday-vs-asana/) · [Trackr](https://www.trytrackr.com/blog/clickup-vs-monday-vs-asana-2026) | GTD apps: [The Sweet Setup](https://thesweetsetup.com/articles/comparison-best-gtd-apps-things-todoist-omnifocus/) · [SmartRemoteGigs](https://smartremotegigs.com/best-gtd-apps-comparison/) | Notion/Trello: [Cloudwards](https://www.cloudwards.net/notion-vs-trello/) · [Unstar (abandono de power users)](https://unstar.app/blog/productivity-app-reviews-what-power-users-complain-about-2026) | Jobber/Housecall: [Capterra Jobber](https://www.capterra.com/p/127994/Jobber/reviews/) · [SelectHub](https://www.selecthub.com/field-service-software/jobber-vs-housecall-pro/) · [FieldPulse comparativo](https://www.fieldpulse.com/resources/blog/housecall-pro-vs-jobber) | ServiceTitan et al.: [Jobber Academy](https://www.getjobber.com/academy/servicetitan-competitors/) · [Field Service Guide](https://fieldserviceguide.com/best-field-service-management-software/) | CRM: [Sybill](https://www.sybill.ai/blogs/salesforce-vs-hubspot-vs-pipedrive) · [Pipedrive](https://www.pipedrive.com/en/blog/hubspot-vs-salesforce-vs-pipedrive) | Abandono: [Zapier](https://zapier.com/blog/why-you-hate-every-to-do-list-app/) · [Scoping review (PMC)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11694054/) | Superlist/Amie: [Efficient App Superlist](https://efficient.app/apps/superlist) · [Ellie sobre Amie](https://ellieplanner.com/comparisons/amie-calendar-review) | Daily planners: [The Digital PM](https://thedigitalprojectmanager.com/tools/best-daily-planner-apps/)
