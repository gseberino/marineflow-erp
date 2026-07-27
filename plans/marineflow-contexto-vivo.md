# Contexto Vivo — o ecossistema que se conversa

**27/07/2026** · resposta à observação do usuário sobre o caso Vanderlei ("não são só as baterias… ele podia sugerir *acompanhar entrega de materiais do cliente Vanderlei* e vincular à Ordem de Serviço").

---

## 1. O diagnóstico (com os números reais)

A intuição estava certa, e o problema é mais fundo que o detector. Medido hoje em produção:

| Métrica | Valor | O que significa |
|---|---|---|
| Mensagens de WhatsApp (30 dias) | **2.003** | O volume existe |
| Contatos distintos | **107** | Muita gente falando com a HBR |
| Mensagens com **cliente identificado** | **22 (1,1%)** | **O sistema não sabe com quem está falando** |
| Mensagens com fornecedor identificado | **0** | — |
| Mensagens vinculadas a uma OS | **0** | — |
| Sugestões da caixa com cliente vinculado | **0 de 24** | Todas mostram só o telefone |

**A causa raiz não é o detector — é a identidade.** O detector faz um bom trabalho com o que recebe: ele lê uma conversa isolada, sem saber que `5544991777856` é o Vanderlei, que o Vanderlei tem a OS-1042 aberta, e que essa OS tem 6 itens dos quais as baterias são só um. Por isso ele escreve "acompanhar entrega das baterias" — é literalmente tudo que ele podia saber.

**Corolário importante:** melhorar o prompt do detector não resolve. É preciso dar a ele o contexto que hoje não existe.

---

## 2. O que o mercado já aprendeu (pesquisa)

- **Memória de agente virou componente arquitetural separado**, não "prompt maior". O padrão de 2026 é uma camada de memória que extrai fatos, resolve entidades e injeta o relevante antes do modelo responder.
- **O melhor resultado em produção vem de híbrido**: busca vetorial (recall difuso) + **grafo temporal de entidades** (relações tipadas, multi-hop). Para agentes de CRM/suporte, essa combinação é a prática corrente. Em benchmark de memória temporal, o grafo (Zep, 63,8%) supera memória puramente vetorial (Mem0, 49,0%) — e a diferença aparece justamente nas perguntas de "o que é verdade **agora**".
- **Customer 360 em grafo**: clientes, ativos, pedidos, OS e interações viram nós; as relações permitem seguir cadeias — `Cliente → OS → Itens → Fornecedor → Prazo`. As respostas vêm de relações reais, não de proximidade semântica.
- **A dimensão temporal é a que mais importa** em produção: separar "o que vale hoje" de "o que valia há seis meses". Um item entregue ontem não pode continuar sendo cobrado.
- **"Open loops"** (fios soltos): tudo que ficou pendente e ainda pede atenção. É o conceito que descreve exatamente o que a HBR precisa rastrear por cliente.
- **Onde as ferramentas falham:** os frameworks de memória prontos não têm governança nem resolução de entidade de domínio — quem tem o ERP tem vantagem, porque as entidades já são reais e tipadas (cliente, OS, produto), não inferidas.

**Leitura para o nosso caso:** não precisamos de banco de grafo. Nosso "grafo" já existe — é o schema do ERP. O que falta é **ligar a conversa a ele** e manter um resumo vivo por entidade.

---

## 3. Minha opinião

Você identificou o salto certo na hora certa. Fazer o detector adivinhar melhor seria remendo; o que muda o patamar é o agente **saber com quem está falando e o que está em aberto**. Três camadas, nesta ordem — cada uma sozinha já melhora o resultado, e a seguinte só faz sentido com a anterior pronta:

### Camada 1 — Identidade (destrava tudo)
Resolver `telefone → cliente / fornecedor / lead` em **toda** mensagem, no momento em que ela chega, e gravar o vínculo. Hoje isso acontece em 1% dos casos.
- Casamento por telefone normalizado contra clientes, fornecedores e leads (com as variações brasileiras: 9º dígito, DDD, +55).
- O que não casar entra numa fila de "quem é este contato?" — e o próprio agente pode perguntar a você uma vez: *"O 5544-9177-7856 é o Vanderlei da Marina X?"*. Respondeu uma vez, vale para sempre.
- **Efeito imediato:** as sugestões passam a dizer "Vanderlei" em vez de um número, e a tarefa nasce vinculada ao cliente.

### Camada 2 — Contexto vivo por entidade (os fios soltos)
Um resumo curto e **sempre atualizado** por cliente/fornecedor: o que está em aberto agora.
- Alimentado por duas fontes: **fatos do ERP** (OS abertas, orçamentos pendentes, títulos vencidos, OCs a receber) e **fatos da conversa** (o que foi prometido, pedido ou combinado).
- Cada fio solto tem estado (`aberto → resolvido`) e é **fechado automaticamente** quando o ERP prova que acabou — exatamente a mecânica de auto-resolução que já funciona no motor de tarefas.
- É o "o que é verdade agora" que a pesquisa aponta como o ponto crítico.

### Camada 3 — Detector com visão de conjunto
Com 1 e 2 prontas, o detector recebe, junto da conversa: quem é o contato, o que está aberto com ele, e quais OS/orçamentos existem.
- Aí ele consegue escrever **"Acompanhar entrega dos materiais da OS-1042 — Vanderlei (baterias, cabos, disjuntores)"** e já vincular à OS.
- Também consegue **fundir** sugestões: se já existe um fio solto "entrega de materiais", a nova menção **atualiza** aquele fio em vez de criar uma segunda tarefa quase igual.
- E o inverso: quando você conclui a tarefa, o fio solto fecha e some do contexto.

**O ganho composto:** cada conversa deixa o sistema mais informado, e cada informação melhora a próxima sugestão. É o "ecossistema que se conversa e se autoajusta" que você descreveu.

---

## 4. O que eu faria diferente do mercado (e por quê)

1. **Sem banco de grafo, sem embeddings no começo.** O ERP já é o grafo (chaves estrangeiras reais). Postgres + um resumo materializado por entidade resolve 90% com uma fração da complexidade. Se um dia a busca difusa fizer falta, `pgvector` entra depois — o Supabase já suporta.
2. **Fatos com origem e validade, nunca "achismo".** Todo item de contexto guarda de onde veio (mensagem, OS, título) e quando expira. Isso mantém a mesma disciplina anti-alucinação da caixa de entrada.
3. **Fio solto do ERP tem precedência sobre fio solto de conversa.** Se o banco diz que a OS foi concluída, não importa o que a conversa sugeria.
4. **Nada disso vira notificação nova.** O contexto serve para o agente responder e sugerir melhor — não para gerar mais mensagens. O teto de atenção continua valendo.

---

## 5. Proposta de fases

### Fase 12 — Identidade dos contatos (1 sessão)
Resolvedor de telefone→entidade em toda mensagem (inclusive retroativo nas 2.003 já existentes); tela/comando "quem é este contato?"; sugestões e tarefas passando a nascer com cliente vinculado.
**Aceite:** ≥70% das mensagens dos últimos 30 dias com contato identificado; sugestões novas exibindo nome em vez de telefone.

### Fase 13 — Fios soltos por entidade ✅ CONCLUÍDA (27/07/2026)
Tabela de itens em aberto por cliente/fornecedor, alimentada pelo ERP e pela conversa, com fechamento automático; painel "o que está em aberto" na tela do cliente; tool `get_open_loops` para o agente.
**Aceite:** abrir um cliente mostra o que está pendente com ele sem eu perguntar; item fecha sozinho quando o ERP resolve.

### Fase 14 — Detector com visão de conjunto ✅ CONCLUÍDA (27/07/2026)
Detector recebe identidade + fios soltos + OS/orçamentos abertos; passa a agrupar (materiais em vez de baterias), vincular à OS certa e **atualizar** fio existente em vez de duplicar.
**Aceite:** o caso Vanderlei produz "Acompanhar entrega dos materiais da OS-XXXX — Vanderlei", vinculada à OS; menção repetida não gera segunda sugestão.

---

## 7. O que ficou de pé (27/07/2026)

**Fase 13 — como funciona na prática.** Tabela `entity_open_loops` com duas origens.
A view `erp_open_loop_facts` é a fonte da verdade dos fatos do ERP (OS ativa; materiais de
OS a receber, **agregados por OS**; orçamento aguardando; título a vencer/vencido; compra
pendente). `refresh_entity_open_loops()` roda dentro do motor de 15 min — SQL puro, **zero
IA** — e faz o ciclo completo: abre o que passou a existir e **fecha** o que saiu da view.
Fio de conversa fecha ainda por tarefa concluída, OS encerrada ou 45 dias de silêncio.

Primeira carga: **24 fios abertos**. Na execução seguinte, um título com saldo zerado saiu
da view e o fio **fechou sozinho** — o mecanismo de auto-resolução validado em produção,
não no papel.

Decisões de recorte que valem registrar:
- Título só vira fio dentro de **15 dias** do vencimento. Boleto para daqui a três meses é
  agenda, não fio solto; entraria só para poluir o painel.
- Título com saldo zerado e status `pending` é **sujeira de cadastro**, não pendência.
- Painel é **somente leitura**. Quem fecha fio é o ERP. Um botão "resolver" na tela criaria
  divergência silenciosa com o banco.

**Fase 14 — como o agrupamento acontece.** O detector recebe os fios já abertos rotulados
`[L1]`, `[L2]`… e devolve `updates_open_loop` quando a conversa é sobre um deles. Nesse
caso a menção **reforça** o fio (`mentions+1`, evidência mais recente) e não vira sugestão.
`loopKeyFromTitle` é a rede de segurança para quando o modelo não aponta o código: normaliza
acento, caixa, pontuação e palavra vazia, então títulos equivalentes colidem na mesma chave.

**Bug encontrado de passagem:** o contexto do detector filtrava OS por status que **não
existem** no banco (`waiting_parts`, `waiting_approval`, `reopened`) e omitia `open` e
`awaiting_parts` — ou seja, ele enxergava só parte das OS ativas desde a Fase 12. Corrigido.

**Pegadinhas de Postgres que custaram tempo:**
- Não existe `min(uuid)`. Para escolher uma linha de referência num agregado, use
  `(array_agg(id ORDER BY ...))[1]`.
- `to_char(v,'FM999G999G990D00')` usa o separador do servidor (`1,710.00`). Para pt-BR,
  `translate(..., ',.', '.,')`.
- `(minha_funcao(...)).*` chama a função **uma vez por coluna do retorno**. Uma função de
  2 colunas invocada assim executa 2×; num teste de contador isso vira número inflado.

---

## 6. Fontes
[Frameworks de memória de agente 2026](https://atlan.com/know/best-ai-agent-memory-frameworks-2026/) · [vetor vs grafo para memória](https://atlan.com/know/vector-database-vs-knowledge-graph-agent-memory/) · [estado da memória de agentes (mem0)](https://mem0.ai/blog/state-of-ai-agent-memory-2026) · [soluções de memória em grafo comparadas](https://mem0.ai/blog/graph-memory-solutions-ai-agents) · [8 sistemas de memória em produção](https://fountaincity.tech/resources/blog/agent-memory-knowledge-systems-compared/) · [Customer 360 em grafo](https://www.puppygraph.com/blog/customer-360-graph-database) · [grafos de conhecimento em IA agêntica](https://zbrain.ai/knowledge-graphs-for-agentic-ai/) · [memória persistente com Cognee](https://www.cognee.ai/blog/tutorials/beyond-recall-building-persistent-memory-in-ai-agents-with-cognee) · [Salesforce Data 360](https://architect.salesforce.com/docs/architect/fundamentals/guide/data-360-architecture) · [open loops e atenção](https://katehannontherapy.com/blogs/closing-the-loop-how-open-loops-fuel-anxiety)
