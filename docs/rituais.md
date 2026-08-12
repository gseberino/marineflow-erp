# Rituais operacionais — o porquê

Os comandos em `.claude/commands/` são curtos e imperativos de propósito: quem os invoca precisa de ordens,
não de argumentação. **Este arquivo guarda a argumentação.** Quando um comando parecer arbitrário, a resposta
está aqui — e quando alguém quiser afrouxar uma regra, é aqui que estão os incidentes que a criaram.

| Ritual | Quando | Onde |
|---|---|---|
| `/modo-noturno` | turno autônomo, sem revisor acordado | `.claude/commands/modo-noturno.md` |
| `/checkpoint` | retrato do estado de uma frente, a qualquer hora | `.claude/commands/checkpoint.md` |
| `/integracao` | levar um branch à `main` | `.claude/commands/integracao.md` |
| `/regras-noturnas` | colar em qualquer sessão que fique rodando sozinha | `.claude/commands/regras-noturnas.md` |

---

## A imagem que organiza o turno noturno

O guarda noturno faz a ronda, varre o pátio, limpa a guarita — tarefas de baixa consequência e alta
reversibilidade. Quando encontra algo grande (um portão com defeito, um vazamento), **anota no livro de
ocorrências e o dono decide de manhã**. O que o guarda nunca faz: reformar a fachada, mexer na fiação ou
redecorar o escritório do dono às 3h, por melhor que pareça a ideia.

A imagem não é decorativa: ela decide os casos que o texto não previu. Diante de qualquer dúvida — "posso
fazer isto?" — a pergunta é se um guarda faria, e a resposta quase sempre aparece sozinha.

**O motivo por trás de tudo é um só: não há revisor durante a noite.** Os dois piores episódios desta semana
— a migration que existia só no banco, e a entrega que apagaria dado financeiro em silêncio — aconteceram
**com** revisor por perto, e foram pegos por isso. Sem revisor, um erro na primeira hora compõe por mais sete.

Daí a meta do turno não ser "o máximo de mudanças", e sim **o máximo de diffs prontos e confiáveis para
revisar ao acordar, mais um livro honesto**.

---

## De onde veio cada regra

**Produção congelada.** Não é desconfiança da noite: é que produção mudada sem revisor não tem quem perceba
o efeito. Escrever a migration é trabalho; aplicá-la é decisão. As duas coisas não precisam acontecer na
mesma hora, e separá-las custa nada.

**Um commit por tarefa, quatro gates antes de cada um.** O turno pode acabar a qualquer momento — limite de
uso, contexto, queda. Com um commit por tarefa e gates verdes, o pior resultado possível é o dono acordar com
menos tarefas prontas; nunca com o repositório quebrado. Gate vermelho que não cede em tentativa razoável é
sinal de que a tarefa é maior do que parecia: reverter e registrar custa dez minutos, insistir custa a noite.

**Território.** Várias sessões editam este repositório ao mesmo tempo. Tocar arquivo de outra frente não
"adianta o trabalho dela" — cria conflito que alguém vai resolver às cegas, sem saber qual lado estava certo.

**Achado se registra, não se corrige de passagem.** Corrigir de passagem mistura diffs, quebra a
rastreabilidade e transforma uma tarefa pequena em sessão longa. Registrar custa um minuto e não perde o
achado. Correção é tarefa deliberada, com commit próprio — e é assim que se sabe, meses depois, o que foi
feito e o que continua aberto.

**IDs de achado com slug da frente (`NOVO-<slug>-NN`).** Em 11/08/2026 quatro IDs tinham dois significados
cada, porque três sessões numeravam em sequência global ao mesmo tempo. Renumerar depois é barato uma vez e
caro sempre. O slug da frente elimina a corrida: cada frente numera dentro do próprio espaço.

**Você não decide produto.** Presumir a resposta é decidir pelo dono — e a decisão presumida chega ao código
sem ninguém para contestá-la. Registrar as opções com uma recomendação entrega ao dono o trabalho já feito,
faltando só a escolha.

**Autoavaliação ao fim de cada tarefa.** Na madrugada de 10-11/08 um relatório afirmou "pronta para aplicar,
verificação pendente" sobre uma entrega que, se ativada, quebraria a tela do técnico e apagaria doze campos
financeiros a cada Salvar. O SQL estava certo; o caminho de leitura e escrita, não. **Dizer "pronto" sobre o
que não foi verificado ponta a ponta é o erro mais caro cometido aqui** — mais caro que o defeito em si, porque
transfere confiança que não existe. Daí o **NÃO ATIVAR** obrigatório.

**Cast para calar o compilador é proibido.** No mesmo episódio, um `as typeof OS_TABELA` — posto só para
compilar antes de a view existir — escondeu do `tsc` exatamente os dois defeitos que a revisão humana levou
horas para achar. É a **regra 7** do `CLAUDE.md`. Se o tipo grita ao trocar a fonte de dados, ele está
fazendo o trabalho dele: o grito É o defeito.

---

## O livro de ocorrências

`audit/relatorio-noturno-<AAAAMMDD>.md` é **o estado do turno**, não o resumo dele. Atualizado após cada
tarefa — não no fim — ele transforma uma sessão interrompida em uma sessão pausada. Sessão que morre sem livro
em dia perdeu a noite; com livro em dia, não perdeu nada.

O livro registra três coisas que o `git log` não registra: **o que a revisão matinal deve olhar** (o autor
sabe onde é frágil), **o que foi pulado e por quê**, e **as decisões que não eram suas**.

---

## Por que a ordem Parte 1 → 2 → 3

O combustível é finito e queima primeiro no que vale mais.

1. **Serviço designado** — defeitos já conhecidos, quase todos de dinheiro. Maior valor por hora.
2. **Varredura** — descoberta. Testes de caracterização são o instrumento: escrever o que a tela faz hoje
   revelou seis defeitos reais em uma noite, incluindo o do CSV que corrompe preço.
3. **Ronda** — vigília. Vale quando não há nada melhor a fazer, e o item (a) já pegou uma migration órfã.

**Ronda sem ocorrência é resultado válido.** Guarda entediado que "acha" problema para se ocupar é pior que
guarda parado: gera ruído que consome a revisão da manhã.

---

## Pesquisa externa

Permitida só na ronda, em dependências (b) e enriquecimento de achados (f). Docs oficiais das bibliotecas que
o projeto **usa** têm prioridade sobre artigos. Toda referência é anexada ao achado.

**Nenhuma "boa prática" de publicação é aplicada ao código durante a noite** — aplicar moda de blog às 3h em
código que funciona é exatamente a fiação que o guarda não mexe. E cada pesquisa consome o mesmo tanque de uso
que o trabalho: lanterna acesa o tempo todo encurta o turno.

---

## O que a manhã garante

O turno noturno só pode ser conservador porque a manhã existe: revisão diff a diff, revisão adversarial,
aprovação do dono, ff-only, push. É o `/integracao`. **A noite produz material para a manhã decidir** — e é
essa divisão que permite trabalhar sozinho sem risco.

Duas a quatro correções boas, verificadas e testadas, mais um livro fiel, é uma noite excelente. Três commits
e dois "pulei por dúvida" bem documentados significam que o sistema funcionou.

---

## Melhorias futuras destes rituais (baixa prioridade)

**Migrar de `.claude/commands/` para `.claude/skills/`.** A documentação atual do Claude Code informa que as
duas formas criam o mesmo `/comando` e que `commands/` continua funcionando, mas recomenda skills — que
ganham um diretório próprio para arquivos de apoio (o livro-modelo do turno poderia morar junto do
`/modo-noturno`) e podem ser carregadas automaticamente quando relevantes. **Decisão do Gustavo em
12/08/2026: fica em `commands/` por ora.** Migrar é mover cada arquivo para
`.claude/skills/<nome>/SKILL.md` — o frontmatter é o mesmo.
