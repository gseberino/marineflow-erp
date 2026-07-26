# Agenda Autônoma — dossiê de pesquisa, diagnóstico e proposta

**26/07/2026** · pesquisa em 21 frentes (>100 fontes: repositórios, papers, docs de produto, fóruns, casos aplicados, dados de analistas) · complementa `marineflow-agenda-tarefas.md` (Fases 0-4) e `marineflow-agenda-benchmark-mercado.md` (Fases 5-8, 33 ferramentas).

---

## 1. O que eu entendi do seu pedido (em uma frase)

> *"Quero abrir a agenda em 1 segundo e encontrar ela já preenchida com o que importa — sem eu ter que lembrar de digitar nada."*

Desdobrando, são **dois problemas diferentes** que costumam ser confundidos:

- **(A) Acesso rápido** — chegar na agenda em 1 toque, de onde você estiver (celular, carro, oficina), inclusive só falando.
- **(B) Alimentação autônoma** — a agenda se preencher sozinha, sem intervenção manual.

E o (B) tem **duas fontes de matéria-prima completamente distintas**:

| Fonte | Exemplo | Status hoje |
|---|---|---|
| **Fatos do sistema** (dados estruturados) | recebível venceu, OS parada, estoque baixo, plano de manutenção vencendo | ✅ **RESOLVIDO** — motor de 12 regras, roda a cada 15 min |
| **Fatos da conversa** (linguagem humana) | cliente pede orçamento no WhatsApp, você promete ligar, fornecedor confirma prazo por áudio, decisão tomada no telefone | ❌ **NÃO RESOLVIDO** — é aqui que a intervenção manual ainda existe |

**Este documento é sobre o segundo.**

---

## 2. Diagnóstico com os SEUS números (medidos hoje, 26/07)

| Métrica | Valor | Leitura |
|---|---|---|
| Mensagens de WhatsApp nos últimos 30 dias | **1.856** | Rio de matéria-prima passando pelo sistema |
| Tarefas criadas pelo motor | **21** | O sistema se alimenta do que ele mesmo sabe ✅ |
| Tarefas criadas **manualmente** | **0** | Ninguém digita tarefa. Nunca. |
| Tarefas criadas **pela IA em conversa** | **0** | O caminho existe, mas ninguém usa |
| Sessões com a IA em 30 dias | 45 | A IA é usada — mas para outras coisas |
| Usuários com canal IA no WhatsApp | **1** (você) | O time inteiro está fora do canal |

**Conclusão dura e importante:** o número "0 tarefas manuais" **não é falha de produto — é a confirmação da sua tese.** Ninguém vai digitar tarefa, nem hoje nem nunca. Qualquer plano que dependa de alguém abrir a agenda e cadastrar está morto na origem. As 1.856 mensagens são o ativo: **o trabalho real da HBR já está escrito em algum lugar — só não vira compromisso.**

E há uma peça de infraestrutura crítica que **você já tem e talvez não saiba**: `whatsapp-transcribe-audio` (Groq) já transcreve áudios recebidos automaticamente. Ou seja, **áudio de cliente já vira texto no seu banco hoje.** Falta só transformar esse texto em tarefa.

---

## 3. Pesquisa — o que o mundo aprendeu (e o que se aplica a você)

### 3.1 O dado mais importante que encontrei: a maioria falha
- Gartner: **mais de 40% dos projetos de IA agêntica serão cancelados até 2027**; 40% das empresas vão rebaixar ou desligar agentes autônomos por falhas de governança descobertas só depois de incidentes em produção. IDC: **88% das provas de conceito nunca chegam a produção ampla.**
- Causa raiz apontada: tratar governança como binário — ou trancado, ou confiança total.
- **Aplicação:** a autonomia tem que ser **graduada e reversível**, exatamente como já fizemos com risco low/medium/high. Nada de "a IA gerencia sua agenda" — e sim "a IA propõe, você aceita com um toque, e o que ela acerta sempre vira automático depois".

### 3.2 Orçamento de atenção — o teto duro
- Pesquisa sobre agentes proativos: existe um **teto de 3 a 5 notificações por dia por pessoa**. Notificação dispensada é **pior que nenhuma** — consome orçamento e gera desconfiança.
- Padrões de falha nomeados: **over-notification**, **falsa importância**, **leitura errada de contexto**.
- Fadiga de aprovação: agente que pede confirmação de tudo faz o usuário carimbar sem ler — "sensação de segurança sem a substância".
- **Aplicação:** nada de notificar cada tarefa detectada. **Digest** — o padrão consolidado (batching) que já usamos no briefing das 07:30. Uma mensagem por dia com tudo, e interrupção imediata só para o que é urgente de verdade.

### 3.3 Extração de compromissos de conversa — é tecnologia madura
- Modelo BERT afinado para detectar action items em transcrições: **95,4% de acurácia** (2.750 diálogos).
- Granola (produto de notas de reunião com extração automática): **70% de retenção semanal**, 50% ativos em 10 semanas — prova de que o padrão gruda quando funciona.
- Superhuman faz "auto reminders" detectando follow-ups pendentes **de forma invisível**; Shortwave exige que você peça — e a crítica dos reviews é justamente essa.
- **Aplicação:** o problema técnico está resolvido no mercado. O diferencial é **onde** você aplica: nas suas 1.856 mensagens/mês, com o contexto do ERP junto (cliente, OS, embarcação).

### 3.4 Transcrição de voz em português — barata e boa
- Whisper: português é **Tier 1**, ~4,9% WER médio (12,1% com sotaque forte em áudio ruim). Custo: **US$ 0,006/min** (~R$ 0,03/min); alternativas mais baratas a US$ 0,003/min.
- Sua conta: se o time gravar 10 áudios de 30s por dia → 5 min/dia → **~R$ 4,50/mês**. Irrelevante.
- **Você já tem isso rodando** (Groq, na `whatsapp-transcribe-audio`).

### 3.5 Acesso rápido — o caminho é PWA, não app
- PWA: **atrito de instalação zero** (abrir URL) vs 4-6 toques na loja. Suporta **app shortcuts** no manifest (atalhos de ação direta ao segurar o ícone) e **Share Target API** (seu app aparece no "compartilhar" do Android — dá para mandar um texto de qualquer app direto para a agenda).
- iOS: atalhos da Siri + share sheet permitem "Ei Siri, nova tarefa" chamando uma URL.
- **Você já tem o PWA** (`manifest.webmanifest`, ícones, service worker no ar) — falta explorar shortcuts e share target.

### 3.6 Casos aplicados que deram certo (o que efetivamente funciona)
- **n8n community (10.930 workflows públicos)**: os padrões campeões são exatamente "áudio → transcrição → ação", "mensagem → extração → registro", "briefing antes da reunião". Um template popular: voz em qualquer idioma → transcreve → devolve resumo estruturado.
- **Meta/WhatsApp Business AI no Brasil** (Bordinho Móveis, MG): agente respondeu praticamente todos os clientes nas primeiras interações, ajudando na conversão — validação local de que o WhatsApp é o canal certo no Brasil.
- **Lembretes de compromisso**: redução de no-show de **20-50%** com SMS; **40-60% com WhatsApp** (lê-se mais). Sequência ótima: confirmação D-3, lembrete D-1, check-in no dia. (Seu R9/R13 já implementam isso — desligados.)
- **ROI de automação em PME**: casos medidos de ~18h/semana economizadas em times de 10 pessoas; automações de qualificação de lead com retorno de 12-20x sobre o custo da ferramenta no primeiro mês.
- **OpenClaw** (assistente pessoal open-source que virou o repositório mais rápido a atingir 100k estrelas): a tese central dele é **"seu agente deve viver onde você já está: WhatsApp, Telegram, Signal"** — não num app novo. É exatamente a arquitetura que você já tem.
- **MCP** (Model Context Protocol, padrão da Anthropic adotado por todos): 1.000+ servidores, 97M downloads/mês — o caminho padrão para conectar agente a calendários e ferramentas externas, se um dia quiser integrar Google Calendar de verdade.

### 3.7 Confiabilidade — como não deixar a IA inventar tarefa
- Padrão consolidado: **structured output com schema forçado** + **limiar de confiança** + **verificação pós-resposta**. Abaixo do limiar → não age, escala para humano.
- Arquitetura de 3 camadas: governança de entrada → geração ancorada em evidência → verificação da saída.
- **Aplicação:** toda tarefa sugerida carrega a **frase original que a gerou** (evidência). Se a IA não consegue citar a frase, não sugere. Isso mata alucinação e ainda te dá contexto para decidir em 1 segundo.

---

## 4. Minha visão (o que eu faria, e por quê)

### 4.1 O princípio que organiza tudo: **Sugerir ≫ Criar**
O mercado erra nos dois extremos. Motion criou tudo sozinho e virou "agenda opressiva" — êxodo documentado em 2026. Todoist não cria nada e depende da sua disciplina — e o seu número (0 tarefas manuais) prova onde isso dá.

**O ponto ótimo é o meio: a IA lê tudo, propõe pouco, e você aceita com um toque.** Aceitar é 1 clique; ignorar não custa nada; e o que você aceita repetidamente vira regra automática depois. Isso respeita as três leis que a pesquisa martelou: **teto de atenção**, **autonomia graduada**, **reversibilidade**.

### 4.2 A "Caixa de Entrada da Agenda" — o coração da proposta
Um lugar único onde chegam **sugestões**, não tarefas. Cada card mostra:
- o que a IA entendeu ("Ligar para o Carlos sobre o orçamento da lancha"),
- **a frase original que gerou aquilo** (evidência — mata alucinação),
- a entidade do ERP já vinculada (cliente/OS/orçamento),
- 3 botões: **✓ Aceitar** · **✎ Ajustar** · **✗ Descartar**.

Alimentada por 4 detectores, todos em cima de dados que **já existem no seu banco**:
1. **Promessa sua** ("vou te mandar amanhã", "te ligo na segunda") → tarefa para você.
2. **Pedido do cliente** ("consegue ver meu motor essa semana?") → tarefa de atendimento vinculada ao cliente.
3. **Prazo dito por terceiro** ("a peça chega dia 12") → tarefa de acompanhamento.
4. **Conversa sem resposta** com pedido implícito → follow-up.

Cada descarte ensina o sistema (log de rejeição → ajusta o limiar por tipo). **Meta honesta: ≥50% de aceitação.** Abaixo disso, o detector é ruim e deve ser desligado, não tolerado.

### 4.3 Captura de voz: o "áudio para si mesmo"
Você já manda áudio no WhatsApp o dia todo. A proposta: **um número/contato interno** (ou o próprio canal já habilitado) onde você manda um áudio de 10 segundos — *"lembra de cobrar a marina sexta e agendar a revisão do barco do Pedro"* — e a IA transcreve, separa em N tarefas, e devolve **uma** mensagem: *"Criei 2 tarefas: [1] Cobrar marina (sexta) [2] Agendar revisão barco do Pedro (sem data). Responda 1 ou 2 para ajustar."*

Toda a infraestrutura já existe: Evolution + webhook + transcrição Groq + agente com tools de agenda. **É integração, não construção.**

### 4.4 Acesso rápido: 3 caminhos, custo baixo
1. **PWA shortcuts** — segurar o ícone do MarineFlow no celular → "Nova tarefa", "Minha agenda hoje". (manifest, ~1h de trabalho)
2. **Share Target** — selecionar texto em qualquer app → Compartilhar → MarineFlow → vira tarefa. (Android; ~2h)
3. **Comando de voz** — "Ei Siri/Google, abrir agenda MarineFlow" via atalho para URL. (configuração, 0 código)

### 4.5 O que eu **NÃO** faria (e por quê)
- ❌ **Auto-scheduling total** (Motion): rejeitado pelos usuários, sensação de perda de controle.
- ❌ **Criar tarefa sem passar pela caixa de entrada**: um item errado que aparece sozinho na agenda destrói a confiança — e confiança é o ativo mais caro aqui.
- ❌ **Notificar cada detecção**: viola o teto de atenção; o digest do briefing já é o canal certo.
- ❌ **Escutar chamadas telefônicas** (transcrição de ligação): tecnicamente possível, mas exige consentimento, muda a relação com o cliente e é o maior salto de complexidade/risco do conjunto. Só se você pedir explicitamente.
- ❌ **App nativo**: PWA cobre; app novo é atrito de instalação e manutenção dobrada.

---

## 5. Proposta faseada (Fases 9-11)

### Fase 9 — Caixa de Entrada + captura por voz (o essencial)
- Tabela `agenda_suggestions` (sugestão + evidência + confiança + origem + status).
- Detector rodando no cron sobre mensagens novas (últimas 24h), com structured output e limiar; **não cria tarefa, cria sugestão**.
- Aba "Caixa de entrada" na Agenda com badge de contagem + Aceitar/Ajustar/Descartar em 1 toque.
- Áudio/texto para o canal interno → N tarefas + resposta única de confirmação.
- Bloco no briefing 07:30: "*3 sugestões esperando sua olhada*".
- **Aceite:** ≥50% de aceitação na 1ª semana; nenhuma tarefa criada sem passar pela caixa.

### Fase 10 — Acesso instantâneo
- PWA shortcuts + Share Target + atalho de voz do celular.
- Widget "próxima ação" (o que fazer agora, 1 item só).
- **Aceite:** criar tarefa a partir de um texto qualquer do celular em ≤ 3 toques, sem abrir o app.

### Fase 11 — Autonomia graduada (só depois de dados reais)
- Tipos de sugestão com ≥80% de aceitação em 30 dias **passam a virar tarefa direto** (com aviso no digest e desfazer de 1 toque).
- Limiar por tipo calibrado com o histórico de aceite/descarte.
- **Aceite:** ≥50% das tarefas nascendo sem intervenção, com <5% de desfazer.

---

## 6. O que eu preciso de você (as decisões que não posso tomar sozinho)

Estas mudam o desenho, então prefiro perguntar a chutar:

1. **Quais conversas a IA pode ler para sugerir?** Só as suas conversas de trabalho? Todas as do número da HBR (incluindo clientes)? Existe conversa que ela **nunca** deve tocar?
2. **Quem mais entra no canal?** Hoje só você tem o canal IA. O Felipe (técnico) entra? A pessoa do financeiro? Isso define se a caixa de entrada é sua ou do time.
3. **Áudio: canal separado ou o mesmo?** Prefere um contato/número só seu para "mandar recado para a agenda", ou usar o canal atual da HBR?
4. **Ligação telefônica entra no escopo?** (transcrição de chamadas — maior ganho, maior complexidade e questão de consentimento)
5. **E-mail é fonte relevante** para a HBR, ou o trabalho real acontece 95% no WhatsApp?
6. **Qual seu limite de paciência diário?** Uma mensagem por dia (digest) é o certo, ou você toparia até 2-3 interrupções para coisas urgentes?

Se você não quiser decidir tudo agora, **o mínimo que eu preciso é a resposta da 1 e da 3** — com elas eu construo a Fase 9 inteira.

---

## 6.1 DECISÕES TOMADAS (26/07/2026)

| # | Decisão | Consequência no desenho |
|---|---|---|
| 1 | **Detector lê TODAS as conversas do número da HBR** (clientes, fornecedores, equipe, incluindo grupos) | Cobertura máxima das 1.856 msgs/mês. Contrapartida obrigatória: sugestão SEMPRE cita a frase-evidência; nada é enviado a ninguém; conversas ficam onde estão (só leitura). Vou incluir uma lista de exclusão por contato (silenciar detector para X) desde a v1. |
| 2 | **Captura por voz nos DOIS caminhos**: áudio pelo canal WhatsApp atual + botão de gravar no app | Backend único: ambos caem no mesmo endpoint de transcrição → mesma caixa de entrada. No app, `MediaRecorder` → upload → transcrição (Groq, já em uso). |
| 3 | **Piloto só com você** no canal IA | A caixa de entrada da Fase 9 é pessoal (dono). Estrutura já preparada para multiusuário (Felipe/financeiro entram na Fase 11, quando os limiares estiverem calibrados). |
| 4 | **Transcrição de ligações: AVALIAR** | Vira um documento próprio (pesquisa dedicada: caminho técnico, consentimento/LGPD, custo, provedores) — **não** entra na Fase 9. Entrego a avaliação separada. |

**Impacto no escopo da Fase 9 (revisado):** detector sobre todas as conversas + lista de exclusão por contato; captura por voz WhatsApp **e** app; caixa de entrada pessoal; briefing avisando o que está esperando.

---

## 7. Fontes (principais, por frente)

**Agentes e frameworks:** [Awesome AI Agents](https://github.com/Jenqyang/Awesome-AI-Agents) · [awesome-ai-agents-2026](https://github.com/caramaschiHG/awesome-ai-agents-2026) · [melhores frameworks open source](https://www.firecrawl.dev/blog/best-open-source-agent-frameworks) · [OpenClaw](https://en.wikipedia.org/wiki/OpenClaw) · [personal AI agents self-hosted](https://www.oneclaw.net/blog/personal-ai-agent-github) · [8 assistentes open-source](https://www.vellum.ai/blog/best-open-source-personal-ai-assistants)
**Extração de action items:** [Granola — extração de compromissos](https://www.granola.ai/blog/meeting-action-items-ai-extraction) · [paper: action-item-driven summarization](https://arxiv.org/pdf/2312.17581) · [Instructor: extração estruturada](https://python.useinstructor.com/examples/action_items/) · [caso de automação de tarefas](https://www.mymobilelyfe.com/artificial-intelligence/turn-meetings-into-action-automating-action-item-extraction-and-task-assignment-with-ai/) · [use case OpenClaw](https://github.com/hesamsheikh/awesome-openclaw-usecases/blob/main/usecases/meeting-notes-action-items.md)
**Proatividade, atenção e confiança:** [notification budget](https://tianpan.co/blog/2026-05-13-background-agents-notification-budget-attention-economy) · [approval fatigue](https://getmrmr.com/blog/approval-fatigue) · [agent notification intelligence](https://zylos.ai/zh/research/2026-04-23-agent-notification-intelligence-smart-alerting-triage/) · [proactive AI guide](https://www.emilingemarkarlsson.com/blog/proactive-ai-agents-guide-2025/) · [anticipation gap](https://www.mindstudio.ai/blog/anticipation-gap-proactive-ai-agents) · [digest/batching](https://docs.notificationapi.com/features/digest) · [Knock: batched notifications](https://knock.app/blog/building-a-batched-notification-engine) · [SuprSend best practices](https://docs.suprsend.com/docs/best-practices-for-batching-digest)
**Human-in-the-loop e autonomia:** [Galileo: HITL oversight](https://galileo.ai/blog/human-in-the-loop-agent-oversight) · [Permit.io: padrões HITL](https://www.permit.io/blog/human-in-the-loop-for-ai-agents-best-practices-frameworks-use-cases-and-demo) · [Redis: production oversight](https://redis.io/blog/ai-human-in-the-loop/) · [paper: autonomia e confiança](https://arxiv.org/pdf/2510.04465) · [paper: externalização em agentes](https://arxiv.org/pdf/2604.08224)
**Realidade de mercado:** [Gartner: 40% cancelados](https://searchengineland.com/gartner-40-of-agentic-ai-projects-will-fail-making-humans-indispensable-474695) · [Gartner: governança uniforme falha](https://www.gartner.com/en/newsroom/press-releases/2026-05-26-gartner-says-applying-uniform-governance-across-ai-agents-will-lead-to-enterprise-ai-agent-failure) · [89% dos pilotos não escalam](https://www.beri.net/article/ai-agent-adoption-enterprise-2026-gartner-idc) · [estatísticas de adoção](https://joget.com/ai-agent-adoption-in-2026-what-the-analysts-data-shows/)
**Voz e transcrição:** [Whisper WER por idioma](https://novascribe.ai/how-accurate-is-whisper) · [preços 2026](https://diyai.io/ai-tools/speech-to-text/openai-whisper-api-pricing-2026/) · [melhor STT open source](https://northflank.com/blog/best-open-source-speech-to-text-stt-model-in-2026-benchmarks) · [PROPOR: ASR em português](https://aclanthology.org/2026.propor-1.30.pdf)
**WhatsApp/automação aplicada:** [n8n WhatsApp + voz + agendamento](https://n8n.io/workflows/8454-automate-whatsapp-customer-support-with-voice-transcription-faq-and-appointment-scheduling/) · [chatbot multimodal com memória](https://n8n.io/workflows/3586-ai-powered-whatsapp-chatbot-for-text-voice-images-and-pdfs-with-memory/) · [10.930 workflows da comunidade](https://n8n.io/workflows/) · [280+ templates](https://github.com/enescingoz/awesome-n8n-templates) · [Meta Business AI no Brasil](https://forbes.com.br/forbes-tech/2026/02/whatsapp-business-lanca-ia-agentica-para-pmes/) · [caso Bordinho Móveis](https://canaltech.com.br/apps/whatsapp-business-ganha-agente-de-ia-para-responder-mensagens-de-clientes/) · [Evolution API](https://github.com/EvolutionAPI/evolution-api)
**Lembretes e no-show:** [dados de redução por SMS](https://www.yougot.ai/blog/reminders/appointment-reminders/do-appointment-reminder-texts-reduce-no-shows) · [WhatsApp -50%](https://achiya-automation.com/en/blog/whatsapp-appointment-scheduling/) · [sequência de 3 toques](https://www.textrequest.com/insights/sms-appointment-reminders-ultimate-guide)
**Acesso rápido / PWA:** [app shortcuts](https://progressier.com/pwa-capabilities/app-shortcuts) · [Share Target API](https://github.com/usememos/memos/issues/5837) · [what PWA can do today](https://whatpwacando.today/shortcuts/) · [Siri Shortcuts + automação](https://zapier.com/blog/zapier-siri-shortcuts/) · [share sheet iOS](https://support.apple.com/guide/shortcuts/share-actions-apdaf74d75a5/ios)
**Confiabilidade de LLM:** [controle de alucinação em aplicação](https://www.parasoft.com/blog/controlling-llm-hallucinations-application-level-best-practices/) · [framework multicamada (MDPI)](https://www.mdpi.com/2073-431X/14/8/332) · [CABS: geração estruturada](https://arxiv.org/pdf/2406.00069) · [detecção em produção](https://layerlens.ai/blog/llm-hallucination-detection-in-production)
**Infra e padrões:** [MCP guia 2026](https://www.sitepoint.com/model-context-protocol-mcp/) · [roadmap MCP](https://a2a-mcp.org/blog/mcp-2026-roadmap) · [Supabase: assistente com Postgres](https://supabase.com/blog/natural-db) · [Telegram bot em Edge Functions](https://supabase.com/docs/guides/functions/examples/telegram-bot) · [transcrição em Edge Function](https://supabase.com/docs/guides/functions/examples/elevenlabs-transcribe-speech) · [event sourcing (Azure)](https://learn.microsoft.com/en-us/azure/architecture/patterns/event-sourcing) · [EDA (SAP)](https://www.sap.com/resources/what-is-event-driven-architecture)
**ROI e produtividade PME:** [Zapier: 10 automações de maior ROI](https://techconcepts.org/blog/zapier-small-business) · [ROI de automação com números reais](https://www.creworklabs.com/blog/ai-automation-roi-for-small-business) · [carga administrativa em PMEs](https://smallbusinesscharter.org/help-to-grow-management/news-and-case-studies/sme-leaders-overwhelmed-by-business-admin) · [Zapier field service](https://zapier.com/automations/business-owners/field-service-operations/field-service-reporting)
**E-mail/assistentes:** [Superhuman auto reminders](https://blog.superhuman.com/shortwave-email/) · [melhores assistentes de e-mail 2026](https://missiveapp.com/blog/ai-email-assistant) · [inbox zero tools](https://get-alfred.ai/blog/best-ai-assistant-for-inbox-zero)
**Rituais de equipe:** [standup bots comparados](https://www.standupalice.com/post/best-daily-standup-bots-for-slack-in-2025-comparison) · [DailyBot check-ins](https://www.dailybot.com/academy/product/check-ins/daily-standups/)
**Náutico/manutenção:** [agentes de IA na manutenção](https://www.fracttal.com/pt-br/blog/agente-ia-na-manutencao) · [manutenção autônoma de embarcações](https://blog.mdftechnology.com.br/manutencao-autonoma-de-embarcacoes/)
