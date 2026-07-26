# Transcrição de Ligações — avaliação técnica, legal e de custo

**26/07/2026** · resposta ao pedido "quero avaliar" (decisão 4 do dossiê `marineflow-agenda-autonoma.md`).
**Isto é uma AVALIAÇÃO, não uma implementação.** Nada foi construído; o objetivo é você decidir com números.

---

## 1. Resumo executivo (leia só isto se estiver com pressa)

| | |
|---|---|
| **Vale a pena?** | **Sim, mas não agora.** O ganho é real; o custo de mudança operacional é alto e o benefício se sobrepõe ao que a Caixa de Entrada já entrega pelo WhatsApp. |
| **O bloqueio principal** | **Não é técnico, é operacional/legal.** Gravar chamada no Brasil exige aviso claro no início de cada ligação e uma base legal registrada. Não é ilegal — é burocrático e muda como você atende. |
| **O caminho mais barato** | ~R$ 0,05/minuto de transcrição + o custo do telefone. Se a HBR fizer 2h de ligação/dia, dá **~R$ 130/mês**. |
| **O caminho mais simples** | Não gravar tudo: **você ditar um resumo de 20 segundos após a ligação importante** — já funciona hoje, custo ~zero, zero questão legal. |
| **Minha recomendação** | Comece pelo resumo ditado (já pronto). Reavalie a gravação automática daqui a ~60 dias, com dados de uso reais. |

---

## 2. Os três caminhos possíveis

### Caminho A — "Resumo ditado" (custo ~zero, disponível HOJE)
Depois de desligar, você segura o microfone na Agenda (ou manda áudio no WhatsApp) e fala 20 segundos: *"acabei de falar com o Pedro, ele quer trocar as duas baterias, mandar orçamento até quinta"*. Vira tarefa(s) na caixa de entrada.
- **Prós:** já existe (Fase 9), zero custo novo, **zero questão legal** (você narrando, não gravando terceiro), captura o que importa sem o ruído da conversa inteira.
- **Contras:** depende de você lembrar de fazer. Perde o que foi dito literalmente.
- **Custo:** ~R$ 0,03 por recado. Irrelevante.

### Caminho B — Gravação no celular + envio manual (baixo custo, atrito médio)
App de gravação no Android grava a chamada; você compartilha o arquivo para o MarineFlow (via Share Target da Fase 10) e ele transcreve e extrai as tarefas.
- **Prós:** captura literal, sem mudar de operadora/telefone; custo só de transcrição.
- **Contras:** **gravação de chamada no Android tem restrições sérias** — funciona bem em Pixel e alguns fabricantes, é irregular/bloqueada em vários aparelhos e versões; **iPhone não permite** de forma nativa. Exige um passo manual por ligação. E já cai na exigência legal de aviso.
- **Custo:** transcrição ~R$ 0,03/min (Groq/Whisper, mesmo que já usamos). 2h/dia ≈ **R$ 110/mês**.

### Caminho C — Telefonia VoIP com API (o "profissional", maior mudança)
Trocar/complementar o telefone da HBR por um PABX virtual com API (3CX, Zenvia, Twilio). A gravação é do sistema, não do aparelho; o webhook manda o áudio para o MarineFlow automaticamente.
- **Prós:** 100% automático, funciona em qualquer aparelho, grava as ligações da **equipe** também, e o número vira ativo da empresa (não do celular pessoal). O 3CX tem **edição gratuita até 10 usuários**, com app de celular e integração de CRM.
- **Contras:** mudança de infraestrutura de telefonia — portabilidade de número, treinar a equipe, mais um sistema para manter. A transcrição nativa do 3CX é paga em tier alto; sai mais barato mandar o áudio para a nossa própria transcrição.
- **Custo estimado:** PABX R$ 0 a ~R$ 150/mês (dependendo da edição) + minutos VoIP + transcrição ~R$ 110/mês. **Faixa realista: R$ 150–400/mês.**

---

## 3. O que a lei exige (LGPD) — o ponto que decide

Não é proibido gravar. É **condicionado**:

1. **Aviso claro e inequívoco no início da ligação**, informando que a chamada é gravada **e para quê**. Na prática: uma frase padrão ("Esta ligação pode ser gravada para registro do atendimento") ou uma URA.
2. **Base legal registrada** — consentimento é uma das opções, mas para atendimento contratual normalmente se usa "execução de contrato" ou "legítimo interesse", **documentado**. Consentimento sozinho não basta.
3. **Controle de acesso** aos áudios (quem ouve, log de auditoria).
4. **Prazo de retenção definido** e exclusão segura ao fim dele.
5. **Atender pedidos do titular** (o cliente pode pedir a gravação ou a exclusão).

Sanção máxima: 2% do faturamento, teto de R$ 50 milhões — na prática, o risco para uma empresa do porte da HBR é baixo se o aviso existir e a retenção for curta, mas **o item 1 muda o tom de toda ligação**, e isso é uma decisão de negócio, não técnica.

**Nota importante:** o Caminho A (você ditando um resumo depois) **não tem nenhuma dessas exigências** — você está registrando sua própria narrativa, não a voz do cliente.

---

## 4. O que seria preciso construir (se você escolher B ou C)

1. **Endpoint de upload de áudio longo** — o `agenda-voice-capture` de hoje aceita base64 pequeno; ligação de 15 min exigiria upload para o Storage e transcrição assíncrona. (~1 sessão)
2. **Diarização** ("quem falou o quê") — o Whisper puro não separa falantes bem; para conversa de 2 pessoas dá para conviver sem, mas a qualidade da extração cai. Provedores com diarização nativa (Deepgram/AssemblyAI) custam mais.
3. **Extração adaptada** — o detector atual foi calibrado para mensagens curtas; transcrição de 15 minutos precisa de sumarização antes da extração (2 etapas, mais tokens).
4. **Vínculo com o cliente** — casar o número da ligação com o cadastro (já temos a normalização de telefone).
5. **Tela de gravações + retenção automática** — exigência da LGPD (item 3 e 4 acima). (~1 sessão)
6. **Consentimento** — frase de abertura e registro da base legal.

**Total estimado: 3 a 4 sessões**, sendo ~1 delas só de conformidade.

---

## 5. Minha recomendação, com o porquê

**Não faça agora. Faça o Caminho A e reavalie em 60 dias.**

Três razões:
1. **O ganho marginal é menor do que parece.** A Caixa de Entrada já captura o WhatsApp, que é onde está o grosso do seu volume (1.856 mensagens/mês). A ligação é o canal secundário.
2. **O custo real não é dinheiro, é atrito.** Avisar em toda ligação que ela é gravada muda a relação com o cliente — e isso é irreversível na percepção dele.
3. **Você ainda não tem dados de uso.** Se a caixa de entrada tiver aceitação alta, o padrão está validado e aí sim vale ampliar a fonte. Se tiver baixa, ampliar a fonte só multiplicaria o ruído.

**Gatilho objetivo para reabrir esta decisão:** se em 60 dias você constatar que **perde compromissos combinados por telefone com frequência** (ex.: 2+ por semana), a conta muda e o Caminho C passa a valer.

---

## 6. Fontes
[LGPD e gravação de chamadas — conformidade](https://delgrande.com.br/blog/sua-gravacao-de-chamadas-esta-100-em-conformidade-com-a-lgpd/) · [gravação e riscos legais (Khomp)](https://communications.khomp.com/blog-eventos/gravacao-chamadas-lgpd/) · [LGPD 2026: foco em segurança de infraestrutura](https://delgrande.com.br/blog/lgpd-e-gravacao-de-chamadas-em-2026-evite-multas-com-criptografia-ponta-a-ponta/) · [gravação de voz do cliente](https://www.ddcomsystems.com.br/lgpd-e-a-gravacao-de-voz-do-cliente) · [gravação automática no Android](https://www.mundoconectado.com.br/tutoriais/android-como-gravar-ligacoes-automaticamente/) · [restrições por aparelho/país (Google)](https://support.google.com/phoneapp/answer/9803950?hl=pt-BR) · [3CX PABX virtual — edição gratuita](https://infob.com.br/melhor-pabx-virtual/) · [3CX transcrição em nuvem](https://www.3cx.com.br/blog/cloud-transcription-enterprise-plus/) · [TotalVoice/Zenvia API de voz](https://totalvoice.github.io/totalvoice-docs/) · [Twilio Voice — preços Brasil](https://www.twilio.com/en-us/voice/pricing/br) · [preços de transcrição 2026](https://diyai.io/ai-tools/speech-to-text/openai-whisper-api-pricing-2026/)
