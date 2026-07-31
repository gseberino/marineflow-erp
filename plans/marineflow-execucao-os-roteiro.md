# MarineFlow — Ciclo do Serviço

**Levantar · Executar · Aprender — a ferramenta que gerencia o serviço antes, durante e depois**

Data: 29/07/2026 · Revisão 2 (30/07 — três frentes novas pedidas pelo dono)
Base: inspeção do repositório canônico + pesquisa de 302 fontes (bibliografia no fim)

---

## 0. O que a revisão 2 mudou

A versão 1 tratava da execução: o roteiro que o técnico segue. O dono apontou três coisas que
mudam a natureza da ferramenta:

1. **O mesmo mecanismo serve antes de orçar.** Quando o serviço exige análise técnica ("substituir
   bateria estacionária do motorhome"), a IA gera as perguntas certas para o técnico levantar em campo
   — *tem acesso fácil? precisa isolar os cabos? o suporte é fixo ou removível?* — e desse levantamento
   sai a estimativa de tempo e o rascunho do orçamento.
2. **O levantamento também descobre o que ninguém orça:** terminais, cabos, parafusos, abraçadeiras,
   fita, EPI. É o custo que some da margem porque nunca entrou na conta.
3. **A ferramenta deve aprender** com as correções que o humano faz nas sugestões da IA, e raciocinar
   sobre o histórico do cliente — orçamentos, OS, conversas de WhatsApp.

Isso não é um acréscimo: é a percepção de que **o mesmo objeto atravessa o ciclo inteiro**. O roteiro
tem três tempos, e o que liga um ao outro é que a resposta de hoje calibra a pergunta de amanhã.

| Tempo | O roteiro é… | Quem responde | O que sai |
|---|---|---|---|
| **Levantar** | um questionário curto e ramificado | o técnico em campo (ou o cliente por foto/vídeo) | estimativa em faixa, lista de materiais, rascunho de orçamento |
| **Executar** | um passo a passo com relógio | o técnico durante o serviço | tempo real por etapa, evidências, serviço extra descoberto |
| **Aprender** | um diff entre o que a IA propôs e o que o humano corrigiu | o sistema, sozinho, sob revisão | tempo padrão recalibrado, perguntas melhores, templates melhores |

O apelido que o dono procurava tem nome na indústria — *service lifecycle management*. Neste
documento ele é chamado de **Ciclo do Serviço**, e o artefato que o percorre continua sendo o
**Roteiro**.

---

## 1. O problema, dito com precisão

Hoje a OS do MarineFlow sabe **o que foi vendido** (linhas de serviço e peças), **quem** vai executar
(`service_order_technicians`) e **quanto tempo** foi orçado (`estimated_hours`, `quantity` em horas).
Ela não sabe **o que precisa ser feito, em que ordem, por quem, e quanto cada coisa deveria levar**.

Esse buraco é exatamente onde o dia de trabalho se perde. A literatura de manutenção mede isso há
décadas com um indicador só: *wrench time* — a fração do dia em que o técnico está de fato com a mão
na obra. A média da indústria fica entre **25% e 35%**; a referência de classe mundial é **55%**, e a
diferença quase nunca é falta de esforço: é peça faltando, escopo mal comunicado, retrabalho,
espera e desorganização. Só a caça a peças consome **35 a 60 minutos por evento de reparo**.

Traduzindo para a HBR: cada hora orçada ao cliente que vira 1,6 hora real é margem que evapora sem
deixar rastro no sistema, porque hoje **não existe o registro do que se pretendia fazer** contra o que
foi feito.

**E o erro começa antes.** Uma hora mal executada custa uma hora; uma hora mal orçada custa em toda OS
igual que vier depois. A literatura de estimativa é dura nesse ponto: o viés de otimismo não é falha de
caráter, é padrão cognitivo — pessoas subestimam prazo e custo mesmo sabendo que tarefas parecidas
atrasaram. O antídoto conhecido é a **previsão por classe de referência**: em vez de raciocinar sobre
*este* serviço, olhar a distribuição dos serviços iguais já feitos. Isso exige um histórico consultável
— que é exatamente o que o Ciclo do Serviço constrói.

Do outro lado do mesmo erro está o **superfaturamento defensivo**: sem dado, o jeito de não se queimar é
botar gordura no preço, e aí se perde o serviço para quem orçou melhor. As duas pontas — orçar de menos
e orçar demais — têm a mesma causa e a mesma cura.

---

## 2. O que já existe no MarineFlow (e não precisa ser reinventado)

Inspeção de 29/07/2026, branch `main`, 174 migrations:

| Peça | Onde está | Serve para |
|---|---|---|
| OS com status de ciclo | `service_orders` (`draft→scheduled→open→in_progress→awaiting_parts→awaiting_client→completed→invoiced`) | O ciclo já é modelado; falta granularidade **dentro** de `in_progress` |
| Horas orçadas | `service_orders.estimated_hours`, `hourly_rate`, `labor_cost_total` | Numerador da comparação orçado × real |
| Linhas de mão de obra | `service_order_services` (`billing_unit`, `quantity`) | De onde os passos serão derivados |
| Apontamento de horas | `time_entries` (OS, técnico, início/fim, `duration_minutes`, `billable`) | **Já existe** — está subutilizado (só em `use-reports.ts` e `use-service-orders.ts`) |
| Equipe da OS | `service_order_technicians` (`role_in_order`) | Atribuição por pessoa |
| Evidências | `service_order_photos`, `service_order_signatures` | Prova de execução e aceite |
| Check-in/out de campo | `service_orders.check_in_at/check_out_at`, `technician_notes` | Chegada e saída já registradas |
| Tools de campo por WhatsApp | `_shared/ai/tools/field-ops.ts` (`check_in_service_order`, `check_out_service_order`, `log_service_order_progress`, `attach_photo_to_service_order`) | **O técnico já opera por WhatsApp** — canal pronto |
| Modo foco (1 tarefa por vez) | `src/components/agenda/FocusMode.tsx` | Padrão de UX já validado no produto |
| Motor de automações | `task-automations` (cron 15 min, 12 regras) | Onde os alertas de execução entram |
| Agente com 145 tools + política de autonomia | `_shared/ai/tools/*`, `autonomy-policy.ts` (`NEVER_AUTONOMOUS`, `app_settings.ai_autonomy_<tool>`) | A IA nova herda o mesmo controle |
| PWA instalável | `public/manifest.webmanifest`, `agenda.webmanifest` | Base do app do técnico |
| Planos de manutenção | `maintenance_plans` (por embarcação, `interval_months`) | Origem recorrente de OS |

**O que não existe:**

1. Nenhuma tabela de **passos/etapas de execução** da OS.
2. Nenhum **tempo padrão** por serviço no catálogo (`services` tem preço, não tem duração).
3. Nenhum vínculo entre `time_entries` e **o que** estava sendo feito naquele intervalo.
4. Nenhuma **folha impressa** do serviço para o técnico.
5. A aba "Tarefas" da OS (`EntityTasksPanel`) usa `agenda_tasks` — que é **agenda administrativa**
   ("ligar para o cliente", "cobrar peça"), não etapa técnica. **Não misturar os dois conceitos** é uma
   decisão de projeto: tarefa de agenda tem dono e data; passo de roteiro tem sequência, tempo padrão
   e evidência.

---

## 3. Doutrina do produto — 14 princípios com origem na pesquisa

Estes princípios foram destilados de ~130 fontes e são o que separa esta ferramenta de "mais um
checklist". Cada um vem com a razão de existir.

### P1. O roteiro nasce do catálogo, não da cabeça de quem digita
Salesforce FSM (Work Type → Work Plan Template → Work Step Template) e Dynamics 365 (Incident Type →
Incident Type Service Task) convergem no mesmo desenho: **template por tipo de serviço**, com passos
reutilizáveis entre templates. No Dynamics, a duração estimada do incidente é a **soma das durações
das tarefas** — a estimativa emerge do roteiro, não é chutada por fora.
→ No MarineFlow: `service_step_templates` pendurado em `services`.

### P2. Curto ou ninguém usa
Gawande: 5 a 9 itens por bloco, limite da memória de trabalho; só *killer items* — os passos cujo
esquecimento é catastrófico ou que se perdem sob pressão. Checklist que leva 90 minutos legítimos é
"convite estrutural ao *pencil whipping*".
→ Blocos de no máximo 9 passos. Passo com mais de ~45 min vira bloco próprio.

### P3. Dois modos de checklist, escolhidos de propósito
READ-DO (leia e faça — receita, para quem está aprendendo ou para procedimento raro) versus DO-CONFIRM
(faça de memória e confirme depois — para o técnico experiente).
→ Campo `mode` no template. O mesmo serviço pode ter roteiro READ-DO para o ajudante e DO-CONFIRM para
o mecânico sênior. **Isto é o antídoto nº 1 contra a resistência da equipe.**

### P4. Quem executa participa do desenho, senão é rascunho
Regra de Gawande: "se quem usa não ajudou a desenhar, é um rascunho". A pesquisa de adoção de FSM diz
o mesmo por outro caminho: a resistência não é à tecnologia, é às condições em que ela foi imposta;
15 minutos de treino prático por equipe evita a maior parte da rejeição.
→ **Decisão do dono (29/07):** a IA rascunha os templates e os técnicos corrigem. A co-autoria acontece
na revisão, e ela é obrigatória: template com `origin='ai'` **não pode ser publicado** sem passar por
`approved_by` de um técnico. O que se ganha é velocidade; o que não se abre mão é a assinatura de quem
executa. Na prática, a sessão de revisão é a mesma reunião — só que com o papel já preenchido.

### P5. O passo pode ser "não se aplica" — e isso é dado, não desvio
Salesforce permite marcar Work Step como *Not Applicable*. Sem essa saída, o técnico honesto trava e o
apressado mente.
→ Status `not_applicable` com motivo obrigatório em uma palavra.

### P6. Parada tem código, não desculpa
Design de *reason codes* de chão de fábrica: 8 a 12 opções no primeiro nível, escolha em segundos,
testes de fronteira escritos para evitar deriva entre turnos, revisão trimestral (não semanal), e
vigiar o balde "Outros" — se ele cresce, a análise morre.
→ Lista fechada de motivos de parada: falta de peça, espera do cliente, clima/maré, deslocamento,
equipamento indisponível, retrabalho, apoio técnico, pausa/almoço, outro (com texto).

### P7. Tempo padrão existe, mas o padrão do fabricante mente para o campo
Tabelas *flat rate* Mercury/Yamaha são calculadas para técnico treinado, motor no cavalete, sem
corrosão, com ferramenta especial à mão. Mecânicos experientes relatam a necessidade de **somar ~50%**
para trabalho real. Cronoanálise clássica diz a mesma coisa em linguagem de engenharia: tempo padrão =
tempo observado × ritmo + tolerâncias (fadiga, necessidades pessoais, espera).
→ `standard_minutes` tem `standard_source` (`oem` | `manual` | `historico`) e um **fator de campo**
por marina/condição. Nunca comparar o real contra o número cru do fabricante.

### P8. Estimativa é faixa, não ponto
PERT/três pontos: E = (O + 4M + P)/6, com desvio-padrão dando faixa de confiança. Melhor comunicar
"entre 3h e 5h, provável 3h40" do que fingir precisão de minuto.
→ A partir da Fase 4, cada roteiro carrega P50 e P80 calculados do próprio histórico da HBR.

### P9. Peça separada antes, ou o roteiro é ficção
*Kitting*: separar e conferir todas as peças **antes** de agendar. O ganho medido é o maior de todos os
citados na literatura — wrench time de ~30% para 45-55%, e conformidade de agenda até +40%. A regra de
ouro: o planejador identifica, o almoxarifado separa, e **o agendamento só trava a data quando o kit
está completo**.
→ Portão de agendamento: OS com peça faltando não entra no quadro do dia sem decisão explícita.

### P10. Prova no ato ou não aconteceu
Foto antes/depois com carimbo de hora resolve disputa de cliente antes de virar disputa. Boas
implementações exigem foto **capturada no ato** (não upload da galeria) e bloqueiam o encerramento sem
as evidências obrigatórias.
→ `requires_photo` por passo; encerramento da OS valida os passos com evidência pendente.

### P11. Trabalho descoberto vira proposta na hora, não no dia seguinte
A pesquisa de *change order* é unânime: o técnico precisa descrever o extra, precificar e obter aceite
**no local**; quando a proposta formal chega dias depois, o momento passou. E o texto tem quatro
partes: o que é, por que está fora do orçado, o preço isolado daquilo, e o aceite por escrito.
→ Botão "achei mais serviço" dentro do roteiro → cria linha nova + pedido de aprovação pelo canal que
o cliente já usa (WhatsApp, que a HBR já tem).

### P12. Papel não é atraso — é o ponto de uso
Fóruns de oficina e chão de fábrica são consistentes: o digital ganha em visibilidade de WIP e
rastreabilidade; o papel ganha no ponto de uso, com mão suja, sol na tela e celular sem bateria. A
solução vencedora é híbrida.
→ A folha impressa **não é um relatório do sistema**: é o mesmo roteiro, em A4, com caixas para hora de
início/fim e um QR que abre a OS. Quem trabalha no papel devolve a folha; quem trabalha no app não
imprime. O dado entra igual.

### P13. Micromanagement mata a ferramenta
Duas evidências: o técnico que se sente vigiado por GPS resiste, o que percebe que o app evita cinco
ligações para o escritório adere. E *leaderboards* têm efeito comprovadamente negativo em quem está na
base do ranking, além de premiar velocidade sobre qualidade — o mesmo defeito clássico do pagamento
*flat rate*, onde "torque especificado é pulado".
→ **Sem ranking público de técnicos no piloto.** Variação orçado × real é indicador **do serviço**, não
da pessoa. Métrica por técnico só aparece no privado do gestor, e nunca é a métrica de abertura.

### P14. IA sugere, humano confirma — e a assinatura fica registrada
Padrão *human-in-the-loop* consolidado: aprovação vinculada à ação exata, com expiração e trilha de
auditoria contendo entrada, raciocínio, decisão e resultado da revisão humana. E, especificamente para
procedimento industrial gerado por LLM, o achado mais forte da literatura recente é que **enriquecer o
contexto com dados estruturados** (tipo do componente, faixa normal, limite de falha, dependências)
levou 100% dos casos a resultado melhor — muito acima de truques de prompt.
→ Roteiro gerado por IA nasce como **rascunho**, exige aprovação humana antes de ir para o técnico, e é
alimentado com o histórico real da embarcação e o catálogo da HBR — não com conhecimento genérico.

---

## 3-bis. Oito princípios do levantamento, dos materiais e do aprendizado

### P15. Nem todo serviço precisa de levantamento — e decidir isso é conta, não palpite
O dono foi explícito: o levantamento serve **quando o serviço exige análise técnica antes de orçar**.
Transformar isso em regra evita os dois fracassos possíveis (levantar tudo, e virar burocracia; não
levantar nada, e voltar a chutar). Cinco gatilhos objetivos, qualquer um deles dispara:

1. **Dispersão histórica alta** — o mesmo serviço já variou mais de ±30% entre execuções.
2. **Sem caso parecido** — a busca por serviços similares não achou vizinho próximo o bastante.
3. **Valor acima do limiar** — acima de R$ X (a definir), o erro dói.
4. **Cliente ou embarcação novos** — não há histórico para consultar.
5. **Incerteza declarada no pedido** — o cliente escreveu "não sei se", "acho que", "dá uma olhada".

Contra-regra igualmente importante: serviço com template maduro, histórico consistente e embarcação
conhecida **é orçado direto**, sem perguntar nada. O levantamento custa deslocamento e hora — ele
precisa se pagar.

### P16. A pergunta certa vale mais do que muitas perguntas
O achado mais útil da pesquisa vem da literatura de LLM que entrevista antes de decidir (MediQ,
raciocínio clínico adaptativo): um agente que pergunta sem critério fica **pior** do que um que não
pergunta — 11,3% de queda, por perguntas repetidas e não respondíveis. O que resolve:

- **Módulo de parada**: antes de cada pergunta, o agente declara em escala ordinal se já consegue orçar
  ("não / parcialmente / sim") **com justificativa escrita**, e a decisão é repetida 3 vezes. Essa
  combinação — escala + justificativa + autoconsistência — foi a melhor testada (+22,3%).
- **Filtro antes de mostrar**: descartar pergunta repetida ou fora do alcance de quem responde rendeu
  +5,7 pontos. O técnico nunca vê a pergunta ruim.
- **Ordenar por impacto no preço**: primeiro a pergunta cuja resposta mais muda a estimativa. Se as três
  primeiras já bastam, o roteiro para na terceira.
- **Teto de 9 perguntas**, o mesmo limite do checklist (P2).

### P17. Levantar de longe antes de levantar de perto
Triagem remota por foto e vídeo deflete cerca de 30% das idas ao local em operações de campo. A HBR já
recebe foto e áudio do cliente pelo WhatsApp todo dia. O roteiro de levantamento deve ter duas formas:
**pedir ao cliente** (link com 3-4 perguntas e pedido de foto) e **ir ao local** — nessa ordem, e a
segunda só quando a primeira não bastar.

### P18. Estimativa é faixa, e contingência é proporcional à confiança
Contingência não é gordura escondida: é uma função explícita de duas coisas — clareza do escopo e
qualidade da base de custo. Quanto mais o levantamento amadurece a definição, menor a contingência.
→ O orçamento carrega uma confiança (alta / média / baixa) que sai da própria completude do
levantamento e da distância até os casos parecidos. Confiança baixa acrescenta contingência **visível
internamente** e, para o cliente, vira faixa ou vira condição escrita ("valor válido para acesso pelo
convés; se houver necessidade de remover o painel, revisamos").

### P19. Miudeza se rateia, item relevante se rastreia
É a decisão que faz a diferença entre um sistema útil e um que ninguém preenche. A prática consolidada
em oficinas cobra materiais de consumo como **percentual da mão de obra** — tipicamente 3% a 8%, quase
sempre com teto — enquanto material com nome e quantidade entra como linha, com margem de 15% a 25% e
fator de perda de 10% a 15%. Duas camadas, então:

- **Kit de materiais do serviço**: cada template carrega os consumíveis típicos com quantidade
  (terminal, cabo, abraçadeira, veda-rosca). **Reaproveita o BOM que já existe** no MarineFlow
  (`product_components`, produto tipo `kit`). A IA propõe o kit a partir do que foi consumido nas OS
  anteriores daquele serviço — não do nada.
- **Taxa de materiais de oficina**: percentual sobre a mão de obra, com teto, para lixa, fita, estopa,
  parafuso avulso. Rastrear parafuso a parafuso destrói justamente o tempo produtivo que o projeto quer
  proteger.

Regra de corte: item acima de um valor a definir vira linha; abaixo, entra na taxa. E quando um item da
taxa aparece repetidamente em OS do mesmo serviço, o sistema **propõe promovê-lo a linha do kit**.

### P20. EPI é custo de operação, não linha do orçamento
Luva, óculos, botina e descarte são custo indireto e devem estar embutidos no valor-hora (o *burdened
rate*), não pendurados na OS. A exceção é o EPI específico da tarefa — mergulho, espaço confinado,
trabalho em altura no mastro — que aí sim é custo direto daquele serviço e entra como item. Misturar os
dois infla o orçamento e some com a margem real.

### P21. O sinal de aprendizado é o diff, não o polegar
O feedback que o MarineFlow captura hoje (`ai_message_feedback`, positivo/negativo) é fraco demais para
ensinar. O sinal que serve é o **diff entre o que a IA propôs e o que o humano aprovou**: qual passo foi
apagado, qual tempo foi alterado de 40 para 90 minutos, qual pergunta foi reescrita. Isso é registrado
sem esforço extra do usuário — ele só faz o trabalho dele. Métrica-mãe: **taxa de aceitação sem
edição**, por tipo de sugestão.

### P22. Aprender é arriscado — prefira sempre o reversível
A pesquisa recente de sistemas que se automodificam é consistente em dois pontos: mudar o *andaime*
(prompt, memória, ferramenta) é preferível a mudar o modelo, porque é reversível e auditável; e a
memória é o vetor de falha mais perigoso — uma correção errada vira regra permanente e contamina tudo o
que vem depois. Daí quatro alças, da mais segura à mais arriscada:

| # | Alça | O que muda | Risco | Reversão |
|---|---|---|---|---|
| 1 | **Dado** | tempo padrão recalculado do histórico | baixo — é estatística, sem LLM | recalcular |
| 2 | **Casos** | busca de serviços parecidos para estimar por analogia | baixo — só recupera, não decide | reindexar |
| 3 | **Exemplares** | correções viram exemplos dentro do prompt | médio — exemplo ruim ensina errado | remover exemplo |
| 4 | **Template** | o molde do serviço muda para todos | alto — afeta toda OS futura | versão anterior |

Três salvaguardas obrigatórias, todas com origem na literatura: **nunca aprender de um evento único**
(o padrão `ai_learned_routines` já exige contagem de repetição antes de propor); **destilar em vez de
acumular** — guardar log bruto chegou a ter contribuição negativa em avaliação controlada, enquanto o
mesmo conteúdo destilado em uma frase de insight passou a contribuir positivamente; e **portão de
qualidade**: nenhuma mudança de prompt ou template entra sem passar por um conjunto fixo de 30 a 50
casos reais com resultado conhecido.

**Fora de escopo no piloto:** *fine-tuning*. O ganho não justifica perder a reversibilidade.

---

## 4. Modelo de dados proposto

Três tabelas novas, três alterações. Tudo aditivo, nada destrutivo.

```sql
-- ─────────────────────────────────────────────────────────────
-- 1. CATÁLOGO: passos padrão de um serviço (o "molde")
-- ─────────────────────────────────────────────────────────────
CREATE TABLE public.service_step_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id uuid NOT NULL REFERENCES public.services(id) ON DELETE CASCADE,
  seq integer NOT NULL,
  block text,                          -- agrupador: 'Preparação', 'Execução', 'Fechamento'
  title text NOT NULL,                 -- verbo no imperativo, curto
  detail text,                         -- o "como", opcional
  kind text NOT NULL DEFAULT 'do'
    CHECK (kind IN ('do','check','safety','evidence','handoff')),
  mode text NOT NULL DEFAULT 'do_confirm'
    CHECK (mode IN ('read_do','do_confirm')),          -- P3
  standard_minutes integer,                             -- P7
  is_killer boolean NOT NULL DEFAULT false,             -- P2
  requires_photo boolean NOT NULL DEFAULT false,        -- P10
  requires_measure text,               -- ex.: 'compressao_psi', 'folga_valvula_mm'
  measure_unit text,
  requires_part boolean NOT NULL DEFAULT false,         -- P9 (passo consome peça)
  role_hint text,                      -- 'mecanico' | 'ajudante' | 'eletricista'
  version integer NOT NULL DEFAULT 1,
  active boolean NOT NULL DEFAULT true,
  created_by uuid, created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (service_id, seq, version)
);

-- ─────────────────────────────────────────────────────────────
-- 2. INSTÂNCIA: os passos desta OS específica
-- ─────────────────────────────────────────────────────────────
CREATE TABLE public.service_order_steps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_order_id uuid NOT NULL REFERENCES public.service_orders(id) ON DELETE CASCADE,
  service_order_service_id uuid REFERENCES public.service_order_services(id) ON DELETE SET NULL,
  template_id uuid REFERENCES public.service_step_templates(id) ON DELETE SET NULL,
  seq integer NOT NULL,
  block text,
  title text NOT NULL,
  detail text,
  kind text NOT NULL DEFAULT 'do',
  mode text NOT NULL DEFAULT 'do_confirm',
  standard_minutes integer,
  is_killer boolean NOT NULL DEFAULT false,
  requires_photo boolean NOT NULL DEFAULT false,
  requires_measure text, measure_unit text,
  measure_value numeric,

  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','in_progress','done','not_applicable','blocked')),
  na_reason text,                      -- obrigatório quando not_applicable (P5)
  blocked_reason_code text REFERENCES public.work_stop_reasons(code),  -- P6

  assigned_user_id uuid REFERENCES public.app_users(id),
  started_at timestamptz, completed_at timestamptz,
  actual_minutes integer,              -- derivado de time_entries

  origin text NOT NULL DEFAULT 'template'
    CHECK (origin IN ('template','ai','manual','client_request')),
  ai_confidence numeric(3,2),          -- só quando origin='ai'
  ai_source text,                      -- de onde a IA tirou (manual, histórico, plano)
  approved_by uuid, approved_at timestamptz,   -- P14: rascunho de IA precisa de aprovação

  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX service_order_steps_os_seq ON public.service_order_steps (service_order_id, seq);
CREATE INDEX service_order_steps_assigned ON public.service_order_steps (assigned_user_id, status);

-- ─────────────────────────────────────────────────────────────
-- 3. MOTIVOS DE PARADA (lista fechada, 8-12 no nível 1) — P6
-- ─────────────────────────────────────────────────────────────
CREATE TABLE public.work_stop_reasons (
  code text PRIMARY KEY,
  label text NOT NULL,
  category text NOT NULL,              -- 'espera','logistica','tecnico','pessoal','externo'
  counts_as_billable boolean NOT NULL DEFAULT false,
  sort integer NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true
);

-- ─────────────────────────────────────────────────────────────
-- 4. ALTERAÇÕES ADITIVAS
-- ─────────────────────────────────────────────────────────────
ALTER TABLE public.services
  ADD COLUMN standard_minutes integer,
  ADD COLUMN standard_source text CHECK (standard_source IN ('oem','manual','historico')),
  ADD COLUMN field_factor numeric(4,2) DEFAULT 1.00;   -- P7: fator de campo sobre o padrão OEM

ALTER TABLE public.time_entries
  ADD COLUMN step_id uuid REFERENCES public.service_order_steps(id) ON DELETE SET NULL,
  ADD COLUMN stop_reason_code text REFERENCES public.work_stop_reasons(code);

ALTER TABLE public.service_order_photos
  ADD COLUMN step_id uuid REFERENCES public.service_order_steps(id) ON DELETE SET NULL,
  ADD COLUMN captured_live boolean DEFAULT false;      -- P10: foto tirada no ato
```

### 4-bis. Levantamento, materiais e aprendizado (revisão 2)

Mais quatro tabelas e três alterações. O orçamento no MarineFlow é a própria `service_orders` em status
`draft` (confirmado em `QuoteList.tsx`) — o levantamento se pendura nela, não em uma entidade paralela.

```sql
-- ─────────────────────────────────────────────────────────────
-- 5. LEVANTAMENTO — perguntas padrão de um serviço
-- ─────────────────────────────────────────────────────────────
CREATE TABLE public.service_survey_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id uuid NOT NULL REFERENCES public.services(id) ON DELETE CASCADE,
  seq integer NOT NULL,
  question text NOT NULL,              -- "O suporte da bateria é fixo ou removível?"
  help_text text,                      -- o porquê, para o técnico entender o que está em jogo
  answer_type text NOT NULL DEFAULT 'escolha'
    CHECK (answer_type IN ('sim_nao','escolha','numero','texto','foto','medida')),
  options jsonb,                       -- ['fixo','removível','não identificado']
  price_impact text NOT NULL DEFAULT 'medio'
    CHECK (price_impact IN ('alto','medio','baixo')),   -- ordena o questionário (P16)
  affects text[],                      -- {'tempo','material','acesso','risco'}
  branch_on jsonb,                     -- {"template_id": "...", "equals": "sim"} → só aparece se
  ask_remotely boolean DEFAULT false,  -- pode ser respondida pelo cliente por foto (P17)
  origin text NOT NULL DEFAULT 'manual' CHECK (origin IN ('manual','ai')),
  approved_by uuid, approved_at timestamptz,
  version integer NOT NULL DEFAULT 1,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────
-- 6. LEVANTAMENTO instanciado + respostas
-- ─────────────────────────────────────────────────────────────
CREATE TABLE public.service_surveys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_order_id uuid REFERENCES public.service_orders(id) ON DELETE CASCADE,  -- o orçamento draft
  client_id uuid REFERENCES public.clients(id),
  vessel_id uuid REFERENCES public.vessels(id),
  trigger_reason text NOT NULL,        -- qual dos 5 gatilhos do P15 disparou
  mode text NOT NULL DEFAULT 'local' CHECK (mode IN ('remoto','local')),
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','sent','answered','closed','skipped')),

  -- Módulo de parada (P16)
  confidence text CHECK (confidence IN ('alta','media','baixa')),
  confidence_rationale text,           -- a justificativa escrita, obrigatória
  questions_planned integer, questions_asked integer,

  -- Resultado
  estimated_minutes_p50 integer,
  estimated_minutes_p80 integer,
  contingency_pct numeric(5,2),        -- P18, derivada da confiança
  materials_draft jsonb,               -- lista proposta antes de virar linhas
  answered_by uuid REFERENCES public.app_users(id),
  answered_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.service_survey_answers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  survey_id uuid NOT NULL REFERENCES public.service_surveys(id) ON DELETE CASCADE,
  template_id uuid REFERENCES public.service_survey_templates(id) ON DELETE SET NULL,
  seq integer NOT NULL,
  question_snapshot text NOT NULL,
  answer_value text,
  answer_json jsonb,
  photo_path text,
  skipped_reason text,                 -- "não consegui acessar", "cliente não sabe"
  answered_at timestamptz NOT NULL DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────
-- 7. APRENDIZADO — o diff entre proposto e aprovado (P21)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE public.ai_suggestion_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  suggestion_type text NOT NULL
    CHECK (suggestion_type IN ('survey_question','step','duration','material','quote_line')),
  target_table text NOT NULL, target_id uuid,
  service_id uuid REFERENCES public.services(id),
  suggested jsonb NOT NULL,            -- o que a IA propôs
  approved jsonb,                      -- o que o humano deixou (null = rejeitado)
  verdict text NOT NULL CHECK (verdict IN ('accepted','edited','rejected')),
  change_summary text,                 -- "tempo de 40 para 90 min", em uma linha
  reviewer_id uuid REFERENCES public.app_users(id),
  ai_model text, prompt_version text,  -- para saber o que regrediu quando regredir
  reviewed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ai_suggestion_reviews_type ON public.ai_suggestion_reviews (suggestion_type, verdict, reviewed_at DESC);

-- ─────────────────────────────────────────────────────────────
-- 8. CASOS — a base de analogia (P22, alça 2)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE public.service_cases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_order_id uuid NOT NULL REFERENCES public.service_orders(id) ON DELETE CASCADE,
  service_id uuid REFERENCES public.services(id),
  vessel_id uuid REFERENCES public.vessels(id),
  client_id uuid REFERENCES public.clients(id),
  marina_id uuid REFERENCES public.marinas(id),
  features jsonb NOT NULL,             -- respostas do levantamento + condições (acesso, motor, local)
  actual_minutes integer NOT NULL,
  materials_cost numeric(12,2),
  parts_used jsonb,
  variance_pct numeric(6,2),           -- real × orçado
  outcome text CHECK (outcome IN ('dentro','estourou','sobrou')),
  usable boolean NOT NULL DEFAULT true, -- caso descartado não polui a analogia
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX service_cases_lookup ON public.service_cases (service_id, usable, created_at DESC);

-- ─────────────────────────────────────────────────────────────
-- 9. ALTERAÇÕES ADITIVAS (revisão 2)
-- ─────────────────────────────────────────────────────────────
ALTER TABLE public.services
  ADD COLUMN material_kit_product_id uuid REFERENCES public.products(id),  -- kit tipo 'kit' (BOM existente)
  ADD COLUMN supplies_pct numeric(5,2),      -- taxa de materiais de oficina (P19)
  ADD COLUMN supplies_cap numeric(12,2),     -- teto em R$
  ADD COLUMN requires_survey boolean NOT NULL DEFAULT false;  -- forçar levantamento sempre

ALTER TABLE public.service_orders
  ADD COLUMN survey_id uuid REFERENCES public.service_surveys(id) ON DELETE SET NULL,
  ADD COLUMN estimate_confidence text CHECK (estimate_confidence IN ('alta','media','baixa')),
  ADD COLUMN contingency_pct numeric(5,2);

ALTER TABLE public.service_order_parts
  ADD COLUMN source text DEFAULT 'manual'
    CHECK (source IN ('manual','kit','survey','ai'));   -- de onde a linha veio
```

**Por que `service_cases` existe separada da OS:** a analogia precisa de um registro estável e
consultável mesmo quando a OS é editada, cancelada ou refaturada, e precisa poder ser **desligada**
(`usable = false`) quando o caso foi atípico — motor alagado, cliente que atrapalhou, chuva. Sem esse
botão, um caso ruim contamina toda estimativa futura.

**Regras de RLS**: seguir o padrão em vigor (`authenticated` com `auth.uid() IS NOT NULL`),
`security_invoker=on` em qualquer view nova e `REVOKE` de `anon` na **mesma** migration — o repositório
já tem histórico de vazamento por view criada sem isso.

**View de variação** (a métrica que justifica o projeto):

```sql
CREATE VIEW public.v_service_order_labor_variance
WITH (security_invoker = on) AS
SELECT
  so.id, so.order_number, so.client_id, so.status,
  so.estimated_hours * 60                                   AS orcado_min,
  COALESCE(SUM(te.duration_minutes) FILTER (WHERE te.billable), 0) AS real_min_faturavel,
  COALESCE(SUM(te.duration_minutes), 0)                     AS real_min_total,
  COALESCE(SUM(st.standard_minutes), 0)                     AS padrao_min_roteiro
FROM public.service_orders so
LEFT JOIN public.time_entries te ON te.service_order_id = so.id
LEFT JOIN public.service_order_steps st ON st.service_order_id = so.id
GROUP BY so.id;
REVOKE ALL ON public.v_service_order_labor_variance FROM anon;
```

---

## 5. O fluxo de ponta a ponta

### Antes (planejamento — onde o ganho é maior)
1. OS criada (do orçamento aprovado, do plano de manutenção ou do pedido do cliente no WhatsApp).
2. **Roteiro é montado**: cada `service_order_services` puxa o template do seu serviço; os pedidos
   soltos do cliente ("dá uma olhada no barulho do trim") viram passos `origin='client_request'`.
3. Sistema soma `standard_minutes` → compara com `estimated_hours` do orçamento.
   **Divergência > 20% é avisada agora**, não no fechamento.
4. **Portão de peças (P9)**: lista consolidada do roteiro × estoque. Faltando algo, a OS fica
   `awaiting_parts` e **não entra no quadro do dia** sem decisão explícita.
5. Agendamento: técnico com a competência certa, agrupado por marina (roteirização por proximidade
   reduz deslocamento em 15-25%).

### Durante (execução)
6. Check-in (já existe) → "a caminho" para o cliente (o `OnMyWayButton` já existe na agenda).
7. **Modo Foco do técnico**: um passo por vez, na ordem. Botões grandes: *Feito* · *Não se aplica* ·
   *Travei*. Cronômetro por passo grava `time_entries` com `step_id` — o técnico não "aponta horas",
   ele só toca em Feito.
8. *Travei* exige motivo da lista fechada; a OS muda de estado e o escritório é notificado **na hora**.
9. Foto/medida obrigatória aparece dentro do passo que a exige, não numa aba separada no fim.
10. "Achei mais serviço" → descreve (pode ser por voz: o `agenda-voice-capture` e o
    `whatsapp-transcribe-audio` já existem) → vira proposta com preço → aceite do cliente pelo WhatsApp.

### Depois (fechamento)
11. Encerramento valida: todo passo em estado terminal, evidências obrigatórias presentes, peças
    consumidas baixadas, assinatura do cliente (`service_order_signatures`, já existe).
12. Relatório ao cliente: o que foi feito, fotos, medidas, o que ficou pendente e a recomendação.
13. **Realimentação**: `actual_minutes` de cada passo entra na base de tempos. O padrão do próximo
    serviço igual é recalculado (P50/P80) — é assim que a estimativa deixa de ser chute.

---

## 5-bis. O ciclo completo, no exemplo do dono

**Pedido que chega:** *"Preciso substituir a bateria estacionária do motorhome."*

**1. O sistema decide se precisa levantar.** Busca serviços parecidos: encontrou 2 execuções, com 1h50
e 4h20 — dispersão de 135%. Gatilho 1 disparado. Justificativa registrada: *"as duas trocas anteriores
variaram de 1h50 a 4h20; o que mudou foi o acesso"*. Vai levantar.

**2. Monta a entrevista** a partir do template do serviço, do histórico daquele cliente e do que a
dispersão revelou — as perguntas nascem de onde o tempo realmente variou:

| # | Pergunta | Impacto | Afeta |
|---|---|---|---|
| 1 | O compartimento tem acesso em pé ou exige trabalhar deitado/ajoelhado? | alto | tempo |
| 2 | O suporte é fixo (parafusado à estrutura) ou removível? | alto | tempo, material |
| 3 | É preciso isolar/desconectar cabos de outros circuitos para chegar até ela? | alto | tempo, risco |
| 4 | Os terminais atuais são parafusados ou crimpados? | médio | material |
| 5 | A bateria nova é do mesmo modelo e dimensão? | médio | material, tempo |
| 6 | Há inversor ou carregador ligado ao mesmo barramento? | médio | risco |
| 7 | *(foto)* Compartimento aberto, com a bateria à vista | alto | tudo |

A pergunta 7 é marcada `ask_remotely` — o cliente consegue mandar essa foto pelo WhatsApp hoje. Se a
foto responder as perguntas 1 e 2, o levantamento **fecha sem ninguém sair da oficina** (P17).

**3. Decide quando parar.** Depois da resposta 4, o agente declara: *"confiança para orçar: parcialmente
— sei o acesso e o suporte, mas não sei se há inversor no barramento, o que muda o risco e o tempo de
isolamento"*. Repete a avaliação três vezes; a maioria diz "continuar". Pergunta a 6. Aí declara "sim" —
e para na sexta, não na nona.

**4. Estima por analogia.** Acesso ajoelhado + suporte fixo + isolamento necessário → o caso de 4h20 é
o vizinho mais próximo, não o de 1h50. Devolve: **P50 3h50 · P80 5h00 · confiança média · contingência
12%** — com os dois casos citados na tela, para quem orça poder discordar com base.

**5. Propõe os materiais.** Do kit do serviço: 2 terminais, luva termorretrátil, veda-terminal,
2 abraçadeiras. Da resposta 4 ("crimpados"): terminal de crimpar + verificação do alicate. Do consumo
histórico: fita isolante e parafusos M8, que ficam **abaixo do valor de corte** e entram na taxa de
materiais, não como linha. EPI comum não entra em lugar nenhum — está no valor-hora (P20).

**6. Vira rascunho de orçamento** com as condições escritas: *"valor válido para acesso pelo
compartimento lateral; se for necessário remover o painel interno, revisamos"*. É a contingência dita
em português, no lugar de gordura escondida no preço.

**7. Aprovado, vira roteiro de execução** — as respostas do levantamento já determinam os passos: quem
respondeu "isolamento necessário" ganha o bloco de segurança correspondente, com a etapa de conferir
tensão residual antes de soltar o terminal.

**8. Executado, vira caso.** Real: 4h05. O caso entra em `service_cases` com todas as respostas do
levantamento como características. **A próxima troca de bateria com esse mesmo perfil de acesso já
nasce estimada em 4h**, e a pergunta que mais discriminou o tempo (o acesso) sobe para o topo do
questionário. É o ciclo se fechando.

---

## 6. As telas (e a folha)

### 6.1 Quadro do Dia (gestor)
Colunas por estado — *A começar · Em execução · Travadas · Concluídas hoje*. Cada cartão: cliente,
embarcação, marina, técnico, barra orçado × decorrido, e o motivo se estiver travada. Limite explícito
de OS em execução por técnico (WIP): quando o board fica vermelho, o problema aparece antes de o
cliente ligar. **Sem scroll horizontal em nenhuma largura** — cartões, não tabela larga.

### 6.2 Modo Foco (técnico, no celular)
Reaproveita `FocusMode.tsx`. Um passo na tela inteira: título grande, detalhe abaixo, três botões e o
relógio rodando. Contador "passo 4 de 11". Offline-first: fila em IndexedDB + *background sync*,
resolução por *last-write-wins* com carimbo de hora — na marina o sinal cai, e um app que perde toque
de botão é abandonado na primeira semana.

### 6.3 Painel do Roteiro (na OS, escritório)
Lista dos passos com estado, tempo padrão × real, quem fez, evidências. É onde se monta e se ajusta o
roteiro antes de mandar para o campo.

### 6.4 Levantamento (revisão 2)
Mesma casca do Modo Foco — uma pergunta por vez, botões grandes —, com três diferenças: mostra "3 de 6"
com o número podendo **diminuir** quando o agente decide parar antes; tem o botão *não sei / não
consegui ver*, que é resposta legítima e não buraco; e termina com a estimativa na tela, com os casos
que a sustentam. A versão do cliente é um link com 3-4 perguntas e um pedido de foto — sem jargão.

### 6.5 A folha A4 (P12)
Uma página por OS: cabeçalho (cliente, embarcação, marina, data, técnico), blocos de passos com
quadradinho, linha para hora de início/fim, campo para medidas, e QR que abre a OS no celular.
Preto e branco, fonte grande, sem cor decorativa — o design que a literatura de checklist recomenda.
Quem preenche no papel devolve a folha e o escritório lança; quem usa o app não imprime.

---

## 7. Onde a IA entra (e onde não entra)

Dez usos, agrupados pelos três tempos do ciclo. Todos herdam a política de autonomia já existente
(`app_settings.ai_autonomy_<tool>`, com teto rígido em `NEVER_AUTONOMOUS`).

### Tempo 1 — Executar (versão 1 do plano)

**IA-0 · Rascunhar os templates do catálogo** (Fase 1 — decisão do dono, 29/07)
Entrada: nome e descrição do serviço no catálogo + histórico das OS já executadas daquele serviço
(`technician_notes`, peças consumidas, fotos) + checklist do fabricante quando existir.
Saída: proposta de blocos e passos com tempo sugerido, gravada como template `origin='ai'` **inativo**.
Por que este é o lugar mais seguro para a IA entrar cedo: o rascunho é revisado **uma vez, no
escritório, sem pressa**, e passa a valer para todas as OS daquele serviço. Errar aqui custa uma
correção; errar no rascunho por OS (IA-1) custa um técnico parado na marina.
Guard-rails: template inativo até `approved_by`; passo `kind='safety'` sempre marcado para revisão
explícita; a IA é instruída a **não inventar torque, folga, pressão ou número de fabricante** — onde
o valor for necessário, ela escreve "conferir no manual" e o técnico preenche na revisão.

**IA-1 · Redigir o rascunho do roteiro de uma OS** (Fase 4 — passou a derivar do levantamento)
Entrada: serviços da OS + texto livre do cliente (WhatsApp/áudio já transcrito) + histórico da
embarcação + templates existentes + plano de manutenção.
Saída: lista de passos com tempo sugerido, marcados `origin='ai'` com `ai_confidence` e `ai_source`.
**Nunca vai direto ao técnico**: o gestor aprova (`approved_by`), e a aprovação é a trilha de auditoria.
Guard-rail principal, direto da pesquisa: o ganho vem de **contexto estruturado**, não de prompt
esperto — a IA recebe o catálogo real da HBR, o histórico real da embarcação e os templates aprovados,
e é instruída a **preferir reusar template existente a inventar passo novo**. Passo inventado que não
casa com nenhum template entra sinalizado para revisão.

**IA-2 · Ler o pedido do cliente e propor escopo** (Fase 4)
"O motor está engasgando em rotação alta e o piso do cockpit está soltando" → dois blocos de
diagnóstico, com os passos de verificação que a HBR já usa nesses casos. Isto é o que o dono descreveu
como "solicitações/observações do cliente já listadas" virando trabalho estruturado.

**IA-3 · Calibrar tempos** (Fase 6)
Não é LLM: é estatística sobre `time_entries`. P50/P80 por serviço, por técnico (privado), por marina.
Alimenta `services.standard_minutes` com `standard_source='historico'`. A LLM entra só para **explicar**
a variação em português ("as trocas de óleo em Angra levam 40 min a mais — o deslocamento no flutuante
não estava no padrão").

**IA-4 · Vigiar o dia** (Fase 6)
Dentro do `task-automations` (cron de 15 min, que **não usa IA** e por isso não custa): passo que
estourou 150% do padrão, OS travada há mais de X horas sem alguém saber, roteiro sem peça a 24h do
agendamento. A LLM só é chamada para redigir o aviso, quando o aviso precisa sair.

### Tempo 2 — Levantar (revisão 2)

**IA-5 · Decidir se precisa de levantamento**
Quatro dos cinco gatilhos do P15 são **contas, não IA**: dispersão histórica, distância até o caso mais
parecido, valor e ineditismo do cliente. Só o quinto — ler o pedido do cliente e perceber incerteza —
é LLM, e é barato. A decisão sai com a justificativa em uma linha ("três execuções anteriores variaram
de 2h a 5h30; vale levantar").

**IA-6 · Montar e conduzir a entrevista**
Gera as perguntas a partir do template do serviço + do que já se sabe do cliente e da embarcação, e
**decide quando parar** pelo módulo do P16: declara em escala se já dá para orçar, escreve o porquê, e
repete a decisão três vezes antes de encerrar. Perguntas repetidas ou que o técnico não tem como
responder são filtradas antes de aparecer na tela. Toda pergunta nova (fora do template) é registrada
como `origin='ai'` e entra na fila de curadoria — se ela se mostrar útil, vira pergunta padrão.

**IA-7 · Estimar por analogia, com faixa e contingência**
Recupera os casos mais parecidos em `service_cases` (mesmo serviço, respostas de levantamento
próximas, mesma marina) e devolve P50, P80 e a contingência do P18 — **sempre mostrando de onde veio**:
"3h40 (P50) / 5h10 (P80), com base em 6 trocas parecidas; a de acesso pelo porão levou 5h30". Um número
sem os casos que o sustentam não é entregue.

**IA-8 · Propor os materiais complementares**
Cruza três fontes: o kit do serviço, o que foi de fato consumido nas OS parecidas, e as respostas do
levantamento ("suporte removível" → parafusos e arruelas; "terminal crimpado" → terminal + luva
termorretrátil). Devolve linha a linha com quantidade e origem, marcando o que é palpite. O que não
alcançar o valor de corte entra na taxa de materiais, não na lista.

### Tempo 3 — Aprender (revisão 2)

**IA-9 · Aprender com o diff**
Toda aprovação humana grava `ai_suggestion_reviews`. O que se faz com isso, na ordem de risco do P22:
recalcular tempos (automático), reindexar casos (automático), promover correções recorrentes a
exemplares do prompt (revisão semanal), e propor mudança de template (só com repetição e aprovação,
no molde de `ai_learned_routines`, que já existe no sistema).

**IA-10 · Contexto do cliente no raciocínio**
Antes de qualquer sugestão, o agente lê o que o MarineFlow já guarda sobre aquele cliente e aquela
embarcação: OS anteriores, orçamentos aprovados e recusados, fios soltos em aberto, notas de memória
e o histórico de conversa do WhatsApp. É o que transforma "trocar bateria" em "trocar bateria **neste**
barco, cujo painel já foi remontado em março e cujo dono recusou o último orçamento por preço".

**Onde a IA não entra:** decidir sozinha o que o técnico deve fazer em serviço de segurança
(combustível, elétrica, gás, içamento), alterar preço, ou fechar OS. Passos `kind='safety'` só existem
se vierem de template aprovado por humano — a literatura de alucinação em procedimento industrial é
explícita sobre o custo de errar aqui.

Some-se, na revisão 2: **a IA não envia orçamento ao cliente sozinha** (o envio segue a regra que já
vale hoje), **não aprende de um evento único**, e **não altera template aprovado** sem passar pelo
portão de qualidade.

**Custo estimado:** o motor de 15 min continua sem IA. As chamadas são episódicas — uma por
levantamento, uma por rascunho de roteiro, uma por revisão semanal de aprendizado. Somando o
levantamento (que é o mais conversacional, ~5 a 9 turnos curtos), a estimativa fica na faixa de
R$ 40 a R$ 80/mês no volume atual, contra os ~R$ 15/mês do detector horário já em produção. O maior
risco de custo não é o preço do token: é a entrevista sem módulo de parada, que vira conversa infinita
— por isso o teto de 9 perguntas é também um controle de custo.

---

## 8. Métricas — o que medir, e medir **antes**

| Indicador | Fórmula | Referência da literatura | Onde |
|---|---|---|---|
| Variação de mão de obra | (real − orçado) / orçado | eficiência faturável típica 55-65% | `v_service_order_labor_variance` |
| Aderência à agenda | OS iniciadas na janela / agendadas | meta 90-95% | `service_orders` + agenda |
| Wrench time | min em passos / min entre check-in e check-out | 25-35% típico, 55% referência | `time_entries` |
| Conclusão na 1ª visita | OS fechadas sem 2ª ida | 70-80% típico, 88-90% melhores | `service_orders` |
| Motivos de parada | Pareto de `stop_reason_code` | "Outros" < 10% ou a lista está errada | `time_entries` |
| Qualidade do roteiro | % de passos `not_applicable` | > 25% = template errado | `service_order_steps` |
| Precisão do padrão | \|real − padrão\| / padrão por serviço | alimenta P7/P8 | agregado |

### Indicadores da revisão 2

| Indicador | Fórmula | Por que importa | Onde |
|---|---|---|---|
| Precisão da estimativa | \|real − orçado\| / orçado, mediana | é a razão de existir do levantamento | `service_cases` |
| Viés da estimativa | média de (real − orçado) / orçado | separa **erro** de **tendência**: se o viés é negativo, orçamos de menos sistematicamente | `service_cases` |
| Levantamentos que se pagaram | variação das OS com levantamento × sem | se não houver diferença, o gatilho está errado | comparativo |
| Perguntas por levantamento | mediana de `questions_asked` | acima de 9, o módulo de parada falhou | `service_surveys` |
| Deflexão remota | levantamentos resolvidos sem ir ao local | referência de campo: ~30% | `service_surveys.mode` |
| Materiais não previstos | peças consumidas fora do kit e fora da taxa | é o vazamento de margem que o dono descreveu | `service_order_parts.source` |
| Margem real por OS | (faturado − MO real − material real − taxa) / faturado | o número que fecha o ciclo | view nova |
| Aceitação sem edição | `accepted` / total, por tipo de sugestão | a métrica-mãe do aprendizado (P21) | `ai_suggestion_reviews` |
| Taxa de conversão do orçamento | aprovados / enviados | referência: 25% em concorrência aberta, 30-50% em trabalho negociado | `service_orders` |

Uma leitura combinada vale mais que qualquer indicador isolado: **precisão da estimativa subindo com
taxa de conversão estável** significa que paramos de errar sem ficar caros. Precisão subindo e conversão
caindo significa que passamos a orçar com gordura demais.

**Fase 0 existe só para isto**: apurar o baseline dos últimos 90 dias antes de mudar qualquer coisa.
Sem número de partida, nenhuma fase seguinte pode ser julgada.

---

## 9. Fases

### Fase 0 — Linha de base e verdade sobre os dados · ~3 dias · sem UI
- Relatório dos últimos 90 dias: horas orçadas × `time_entries` existentes × OS sem apontamento algum.
- Levantar os **10 serviços mais frequentes** por volume e por horas.
- **(rev. 2)** Precisão e **viés** da estimativa histórica: erramos para mais ou para menos? Em quais
  serviços a dispersão é maior? — é isso que calibra o gatilho de levantamento do P15.
- **(rev. 2)** Vazamento de material: peças consumidas em OS que não estavam no orçamento, e quanto
  isso representa da margem.
- **Aceite:** um número de partida por indicador da seção 8, a resposta a "quantas OS hoje têm
  apontamento de hora confiável?" e o valor em reais do vazamento de material no trimestre.

### Fase 1 — Roteiro + Modo Foco + folha impressa · ~1,5 semana
**Escopo do piloto (decisão do dono): um tipo de serviço — revisão de 100h.** Repete muito, tem
checklist de fabricante como ponto de partida e permite comparar tempo entre execuções iguais já na
primeira semana.
- Migration com as 3 tabelas + alterações; seed de `work_stop_reasons`.
- **IA-0 rascunha** os templates (revisão de 100h primeiro, depois os 9 seguintes mais frequentes);
  **técnicos revisam e assinam** — sem `approved_by`, o template não sai do rascunho (P4).
- Painel do Roteiro na OS (gerar do catálogo, editar, reordenar).
- Modo Foco no PWA **e** folha A4 imprimível com QR — os dois canais desde o início (decisão do dono).
- **Aceite:** 20 revisões de 100h executadas pelo roteiro; todo passo em estado terminal; ≥ 70% dos
  passos rascunhados pela IA sobrevivem à revisão dos técnicos sem edição (se ficar abaixo, o problema
  é o contexto que a IA recebe, não o conceito — corrigir antes de escalar para outros serviços);
  os técnicos dizem em entrevista o que ajudou e o que atrapalhou.

### Fase 2 — Relógio, paradas e o Quadro do Dia · ~1 semana
- `time_entries` por passo (automático ao tocar Feito), pausa com motivo obrigatório.
- Quadro do Dia com WIP e barra orçado × decorrido.
- Alerta de estouro no `task-automations` (sem IA).
- **Aceite:** ≥ 80% das horas trabalhadas em OS com roteiro estão apontadas por passo; a variação de
  mão de obra passa a ser calculável para toda OS nova.

### Fase 3 — A base de casos · ~3 dias · **pré-requisito de tudo que vem depois**
Barata, invisível e decisiva: toda OS concluída passa a virar um caso em `service_cases`, com as
condições, o tempo real e o material consumido. Inclui o backfill do que já existe (as OS antigas
entram com o que houver, marcadas com confiança menor).
- **Aceite:** a busca "me mostre as 5 execuções mais parecidas com esta" responde em menos de 1s e o
  resultado faz sentido para quem conhece a operação. Sem isso, a Fase 4 não começa.

### Fase 4 — Levantamento antes de orçar · ~2 semanas · **a frente nova nº 1**
- Gatilho do P15 (quatro contas + uma leitura de texto), com a justificativa visível.
- `service_survey_templates` para os serviços que mais variam; a IA rascunha as perguntas, os técnicos
  revisam — mesmo padrão da Fase 1.
- Entrevista com módulo de parada (P16), no celular do técnico **e** em link para o cliente responder
  com foto (P17).
- Estimativa por analogia com faixa P50/P80 e contingência (P18), mostrando os casos que a sustentam.
- Rascunho de orçamento pré-preenchido a partir do levantamento.
- **Aceite:** 15 levantamentos reais; mediana de perguntas ≤ 9; precisão da estimativa nas OS com
  levantamento melhor que o baseline da Fase 0; e pelo menos um caso em que o levantamento **impediu**
  um orçamento errado — documentado, porque é esse o argumento que sustenta a fase.

### Fase 5 — Materiais complementares e margem real · ~1,5 semana · **a frente nova nº 2**
- Kit de materiais por serviço reusando o BOM existente; a IA propõe o kit a partir do consumo real.
- Taxa de materiais de oficina (% da mão de obra, com teto) e o valor de corte entre linha e taxa.
- Perguntas de material dentro do levantamento ("terminal parafusado ou crimpado?").
- EPI específico da tarefa como item; EPI geral no valor-hora (P20).
- View de margem real por OS, fechando o ciclo: faturado − mão de obra real − material real − taxa.
- **Aceite:** o vazamento de material medido na Fase 0 cai pela metade; nenhuma OS fechada no período
  com peça consumida sem origem (`source`) preenchida.

### Fase 6 — Tempos que aprendem + vigilância do dia · ~1 semana
- P50/P80 por serviço; `field_factor` por marina; recálculo de `standard_minutes`.
- Alertas de estouro e de OS travada; explicação em português das variações.
- **Aceite:** erro médio da estimativa nos serviços recorrentes cai contra o baseline da Fase 0.

### Fase 7 — O ciclo que aprende · ~1,5 semana · **a frente nova nº 3**
- `ai_suggestion_reviews` gravando o diff em toda aprovação (isso pode e deve ser ligado **já na Fase
  1** — é só instrumentação; a Fase 7 é quando se passa a *usar* o que foi acumulado).
- Painel de aceitação por tipo de sugestão, com os piores casos em destaque.
- Alça 3 (exemplares): revisão semanal que promove correções recorrentes a exemplos do prompt, com
  orçamento fixo de tamanho — entra um, sai outro.
- Alça 4 (template): proposta de alteração de molde quando o mesmo ajuste se repete, no fluxo
  observado → proposto → aprovado que `ai_learned_routines` já implementa.
- **Portão de qualidade**: conjunto fixo de 30 a 50 casos reais; nenhuma mudança de prompt ou template
  entra sem rodar contra ele e não regredir.
- **Aceite:** a taxa de aceitação sem edição sobe mês a mês em pelo menos dois dos cinco tipos de
  sugestão, **sem** queda no portão de qualidade. Se subir a aceitação e cair o portão, o sistema
  aprendeu a agradar em vez de acertar — e a alça responsável é desligada.

### Fase 8 — Fechamento, evidência e trabalho adicional · ~1 semana
- Bloqueio de encerramento com evidência obrigatória pendente.
- Relatório do serviço ao cliente (aproveitando `pdf-generator.ts` e o portal já existentes).
- "Achei mais serviço" → linha + aprovação do cliente pelo WhatsApp.
- **Aceite:** 100% das OS fechadas no período têm evidência completa; primeiro trabalho adicional
  aprovado no mesmo dia da descoberta.

**Total: ~10 semanas** (eram ~5 na versão 1). O dobro do esforço, e é honesto dizer por quê: as três
frentes novas não são acabamento do roteiro — são dois terços do ciclo. O que **não** muda é a ordem de
entrega de valor: a Fase 1 continua entregando sozinha, e cada fase seguinte é útil mesmo que a próxima
nunca aconteça.

**Caminho curto, se o objetivo for provar valor rápido:** Fases 0 → 1 → 3 → 4. Em cerca de 4 semanas
você tem o roteiro na mão do técnico e o levantamento antes de orçar, que são as duas pontas onde o
dinheiro vaza. Relógio, materiais e aprendizado entram depois, sobre uma base já em uso.

---

## 10. Riscos e antídotos

| Risco | Por que é real | Antídoto no desenho |
|---|---|---|
| *Pencil whipping* (marcar sem fazer) | Documentado em toda indústria com checklist; sinais são tempos idênticos e listas longas fechadas em minutos | Roteiro curto (P2), foto no ato (P10), e **monitorar** passos concluídos rápido demais — sem punir, investigar o template |
| Rejeição da equipe | Resistência vem das condições de introdução, não da tecnologia | Técnicos desenham os primeiros templates (P4); DO-CONFIRM para os experientes (P3); zero ranking (P13); a folha de papel continua válida (P12) |
| Roteiro vira burocracia | Cada campo obrigatório custa segundos × 30 passos × 5 OS/dia | Só *killer items* obrigatórios; voz em vez de digitação (captura por voz leva ~18s contra 2,4 min digitando) |
| IA inventa passo perigoso | Alucinação em procedimento industrial é risco físico | Rascunho + aprovação humana (P14); `kind='safety'` só de template; contexto estruturado em vez de conhecimento genérico |
| Padrão de tempo virar cobrança de produtividade | *Flat rate* faz pular torque e diagnóstico | Métrica é do serviço, não da pessoa; padrão calibrado com dado da HBR, não do fabricante (P7) |
| Confusão entre `agenda_tasks` e passos do roteiro | Duas coisas chamadas "tarefa" na mesma tela | Nomes distintos na UI: **Tarefas** (agenda) × **Roteiro** (execução); a aba atual da OS permanece como está |
| Apontamento confundido com ponto eletrônico | Portaria 671/CLT rege jornada; apontamento por OS é custo, não jornada | Deixar explícito na UI e no treino: `time_entries` **não** substitui registro de ponto. Se a HBR precisar dos dois, são sistemas separados |
| Conflito com outras sessões de IA no repo | Já aconteceu | Trabalhar em `git worktree` próprio, branch `feat/os-roteiro-execucao`, staging arquivo a arquivo |

### Riscos da revisão 2

| Risco | Por que é real | Antídoto no desenho |
|---|---|---|
| Levantamento atrasa o orçamento | O cliente que pede preço hoje não espera visita na semana que vem | Gatilho estreito (P15); modo remoto primeiro (P17); prazo de resposta no próprio levantamento; serviço conhecido continua sendo orçado na hora |
| Perguntas ruins queimam a confiança | Um agente que pergunta sem critério piora o resultado — 11,3% de queda medida | Filtro antes de exibir; teto de 9; botão "essa pergunta não ajuda" que alimenta a curadoria |
| Cliente não aceita pagar a visita | Prática de mercado é dividida | Política de crédito: a visita é abatida se o serviço fechar. Precisa ser dita antes, não na fatura |
| Taxa de materiais parece taxa escondida | Cobrança percentual mal explicada gera atrito | Linha nomeada no orçamento, com o que ela cobre; teto visível; nunca percentual sobre peça |
| Rastrear material demais | Cada item lançado custa segundos do técnico | Valor de corte explícito; abaixo dele, taxa. O sistema **propõe** promover item recorrente, não obriga |
| Analogia com poucos casos | 2 casos parecidos não são uma distribuição | Piso mínimo de casos para usar analogia; abaixo dele, o sistema diz "sem base suficiente" e cai no tempo padrão do template |
| Memória envenenada | Uma correção errada vira regra e contamina tudo depois | Nunca aprender de evento único; proveniência registrada; entrada de memória tem dono e data e pode ser removida |
| Aprender a agradar em vez de acertar | O sistema pode otimizar para a aprovação humana e não para o resultado | O portão de qualidade é **independente** da taxa de aceitação; aceitação subindo com portão caindo desliga a alça responsável |
| Escopo do projeto dobrar de novo | Aconteceu entre a v1 e a v2 desta proposta | O caminho curto (0→1→3→4) está escrito; as demais fases são opcionais e ordenáveis |

---

## 10-bis. Frente transversal: a IA no ponto de uso (pedido do dono, 30/07/2026)

O dono pediu quatro coisas que não são uma fase nova — atravessam todas. Registradas aqui
com o desenho, a pesquisa que as sustenta e onde divergi.

### O que foi pedido
1. O roteiro deve **nascer dos serviços já lançados** na OS ou no orçamento, sugerido pela IA,
   com o usuário ajustando.
2. Um **campo de conversa** junto ao roteiro para acrescentar, corrigir e completar.
3. O mesmo tratamento nas **Tarefas** da OS.
4. Na linha de serviço/produto, um **menu de ações rápidas de IA**: criar tarefa, criar roteiro,
   lançar materiais complementares, cotar com fornecedor, comprar online, separar material.

### P23. A ação certa aparece onde o trabalho está, não numa tela à parte
Salesforce (Agent Quick Actions em record pages) e Dynamics ("de sistema de registro a sistema de
ação") convergiram no mesmo lugar: a ação de IA mora **no registro**, não num assistente separado.
O ganho é de contexto — o botão já sabe de que serviço, de que OS e de que cliente se trata, e o
usuário não redigita o que a tela já mostra.

### P24. Menos botões, e só os que o contexto justifica
Aqui a literatura é um aviso, não um incentivo. *AI fatigue* é fenômeno medido: 95% das empresas
não veem retorno do investimento em IA, e a causa apontada não é o modelo — é proliferação de
funcionalidade sem critério. A NN/g mostra por que a descoberta falha: ícone de *sparkles* sem
significado estabelecido, rótulo proprietário ("Rufus") em vez de linguagem clara, e botão em
lugar não convencional.
→ **Um** ponto de entrada por linha, com no máximo **5 ações**, e cada ação aparece só quando o
contexto a justifica (divulgação progressiva contextual):

| Ação | Só aparece quando |
|---|---|
| Gerar roteiro deste serviço | linha de serviço sem passos ainda |
| Criar tarefa de separação | há peças na OS e ela está agendada |
| Lançar materiais complementares | linha de serviço com kit cadastrado |
| Cotar com fornecedor | linha de produto sem estoque suficiente |
| Comprar online | produto com fornecedor e link cadastrados |

Se todas aparecem sempre, viraram ruído — e o menu terá falhado.

### P25. Instrução de uma linha, não conversa
**Aqui divirjo do pedido.** A pesquisa de padrões de 2026 é direta: *"chat de IA é o padrão mais
over-aplicado; nem toda funcionalidade quer ser um chat — às vezes um botão, uma ação inline ou um
prompt de uma vez só é melhor"*.

Um chat ao lado do roteiro tem três custos concretos: a conversa se perde ao sair da tela, o
contexto cresce a cada turno (e o custo com ele), e — o mais grave para este projeto — **conversa
livre não produz diff estruturado**, que é justamente o combustível da Fase 7.

→ Proposta: um **campo de instrução de uma linha** ("o que ajustar no roteiro?"), que aceita
linguagem natural igual ao chat, mas devolve **alterações propostas passo a passo**, com aceitar
ou descartar em cada uma. O histórico das instruções fica no registro. Isso entrega o que o dono
quer — corrigir e completar falando — e ainda alimenta o aprendizado, porque cada aceite ou recusa
vira uma linha em `ai_suggestion_reviews`.

Se depois de usar ficar claro que falta conversa de verdade, o campo vira chat sem retrabalho: a
mesma tool, com histórico.

### P26. O botão não tem lógica própria — ele chama a tool que já existe
As 154 tools do agente já implementam as regras (autonomia, cargo, preço oculto para técnico). A
ação rápida é **atalho com contexto pré-preenchido**, nunca uma segunda implementação da mesma
regra. Consequências: a tela e o WhatsApp passam pelo mesmo caminho, as ações de risco médio/alto
continuam pedindo confirmação pela política existente, e nada precisa ser reimplementado quando a
regra mudar.

### Onde cada pedido entra nas fases
| Pedido | Fase | Situação |
|---|---|---|
| Roteiro sugerido a partir dos serviços lançados | **IA-1, já prevista** | ficou faltando — é o próximo item |
| Instrução de uma linha no roteiro | Fase 7 (usa `ai_suggestion_reviews`) | desenho acima |
| Mesmo tratamento nas Tarefas | Fase 7 | reusa `agenda_tasks` |
| Menu de ações rápidas por linha | frente própria, depois da Fase 5 | depende do kit de materiais existir |

---

## 10-ter. Roteiro por COMPOSIÇÃO — cobrir o catálogo inteiro sem escrever 4.500 passos

Pedido do dono (31/07): cadastrar no catálogo os serviços que só existem como texto livre,
gerar roteiro para tudo, e fazer a IA sugerir o roteiro **na hora em que a linha é digitada**
no orçamento. A frase que resolveu o desenho foi dele: *"para instalar qualquer equipamento
elétrico tem que desligar a alimentação — o sistema identifica isso e gera o roteiro"*.

### O problema de escala
O catálogo tem **261 serviços ativos** e 37 nomes que só vivem como texto em OS. Escrever 9
passos para cada um são ~2.700 passos — impossível de escrever e pior ainda de manter: mudou o
procedimento de segurança elétrica, mudam 78 roteiros à mão.

### P27. O roteiro se compõe; não se enumera
```
Roteiro = [abertura do SISTEMA] + [corpo do VERBO] + [fechamento do SISTEMA]
```
O bloco de segurança não pertence ao serviço — pertence ao **sistema** que ele toca. Todo
trabalho em 12V DC começa desligando e confirmando ausência de tensão, seja instalação de
geladeira, troca de bomba ou reparo de guincho.

**Dois eixos, extraídos do catálogo real da HBR:**

| Eixo VERBO (o que se faz) | Qtd no catálogo |
|---|---|
| Instalação | 78 |
| Substituição | 40 |
| Diagnóstico | 20 |
| Reparo | 14 |
| Logística / mão de obra | 7 |
| Configuração | 5 |
| Remoção / desmontagem | 4 |
| Manutenção | 3 |
| Adequação | 1 |
| A classificar ("SERVIÇO DE …") | 89 |

| Eixo SISTEMA (o que se toca) | Bloco de abertura |
|---|---|
| Elétrico DC (12/24V) | desligar, confirmar ausência de tensão, fotografar ligação atual |
| Elétrico AC (110/220V) | desligar disjuntor, travar, testar, aterramento |
| Gás GLP | fechar registro, ventilar, teste de estanqueidade ao fim |
| Hidráulico | despressurizar, fechar registro, proteger contra respingo |
| Eletrônico / dados | anotar configuração atual antes de desconectar |
| Refrigeração | verificar carga e nível antes de mexer |
| Mecânico / estrutural | apoiar, travar contra movimento |

**A conta muda de figura:** 7 blocos de abertura + 7 de fechamento + ~9 corpos de verbo = **~23
blocos escritos e revisados uma vez**, cobrindo os 261 serviços. Mudou a regra de segurança de
gás? Um bloco corrigido conserta todos os serviços de gás de uma vez.

### P28. A sugestão nasce na linha do orçamento, não numa tela à parte
Quando alguém digita *"Instalação de chuveiro elétrico 12V"*, o classificador identifica
**verbo = instalação** e **sistema = elétrico DC** e monta o esqueleto na hora. O usuário aprova,
ajusta ou descarta — e o serviço, se ainda não existir no catálogo, é cadastrado junto.

Classificação em duas camadas, e a ordem importa: **palavra-chave primeiro** (barata,
determinística, audível — "bateria/inversor/DC-DC/fusível" → elétrico DC), **IA só no que sobrar**.
A IA não deve ser chamada para reconhecer "instalação de bateria" — isso é um `LIKE`.

### P29. Escopo é o que a HBR faz, e o catálogo já diz qual é
Elétrica e eletrônica embarcada são o núcleo, mas o histórico mostra gás (aquecedor, ramal GLP,
fogão), hidráulica (bomba d'água, mangueira, registro), refrigeração, áudio/vídeo, mecânica leve
(guincho, fechadura, amortecedor) e náutica (transducer, luz de fundeio, isolador galvânico).
Fora do escopo por decisão do dono: **pintura, para-brisa e laminação de fibra** — exigem
conhecimento e equipamento de outra natureza.

Norma aplicável ao que a HBR mais faz: **ABYC E-11** (sistemas AC/DC em barcos, com queda de
tensão máxima de 3% em circuito crítico e 10% no resto) e **ABYC E-13** (instalação de lítio
acima de 600Wh — exatamente os bancos LiFePO4 que a HBR instala).

### Sequência proposta
1. **Classificar o catálogo**: os 261 serviços ganham verbo + sistema. Palavra-chave resolve a
   maioria; a IA fecha o resto; o dono revisa só o que ficou duvidoso. ✅ *keyword feita*
2. **Escrever os ~23 blocos** — a IA rascunha, o dono aprova na tela que já existe. ✅ *feito*
3. **Compositor de roteiro**: gerar passos = abertura do sistema + corpo do verbo + fechamento. ✅
4. **Backfill**: os 37 nomes de texto livre viram serviços de catálogo, já classificados.
5. **Sugestão na linha do orçamento**, com o classificador rodando ao digitar.

### Estado dos blocos (31/07/2026)
Os 23 blocos estão no banco: **116 passos**, todos `origin='ai'` e `active=false`, aguardando
assinatura em `/step-templates` (seção "Blocos componíveis", que mostra quantos serviços cada
bloco alcança). Migration `20260731170000_ciclo_servico_blocos_componiveis`.

| | Escrito | Passos |
|---|---|---|
| Aberturas (por sistema) | 7 | 31 |
| Corpos (por verbo) | 9 | 50 |
| Fechamentos (por sistema) | 7 | 35 |

Cobertura sobre os 261 serviços ativos, com a classificação por palavra-chave que já rodou:
**150 (57,5%) ganham roteiro completo**, 91 (34,9%) só o corpo do verbo, 4 só abertura+fechamento
e 16 nenhum passo — os 107 que a IA ainda precisa classificar são exatamente o que fecha essa conta.

Regra de conteúdo seguida à risca (instrução do dono): **nenhum torque, pressão, temperatura ou
norma foi inventado**. Onde o procedimento depende de um valor, o passo diz "conferir no manual" e
é marcado como medição — o técnico anota o que mediu e a referência vem do fabricante.

Lacuna conhecida: o sistema **`estrutural`** (4 serviços) não tem par de blocos — a tabela do P27
o agrupa com "mecânico", e escrever um 8º par é decisão do dono, não suposição da IA.

---

## 11. Decisões

### Tomadas em 29/07/2026
| # | Decisão | Efeito no plano |
|---|---|---|
| 1 | **Canal do técnico: celular + folha, desde a Fase 1** | O PWA e o A4 entram juntos; o dado entra igual pelos dois caminhos. Custa ~2 dias a mais na Fase 1 e compra a adesão de quem não quer app |
| 2 | **IA rascunha os templates, técnicos corrigem** | A IA sobe da Fase 3 para a Fase 1, mas **no catálogo, não na OS** (IA-0). Revisão humana obrigatória: `approved_by` é condição para ativar o template |
| 3 | **Piloto em um tipo de serviço: revisão de 100h** | A Fase 1 entrega valor medível rápido, porque compara execuções iguais entre si. Expansão para os outros 9 serviços só depois do aceite |
| 4 | **Variação orçado × real visível só para a gestão** | O técnico vê o tempo padrão da etapa; não vê julgamento sobre si. Nenhum ranking, nem privado (P13) |

### Ainda em aberto
5. **Rigor do fechamento**: bloquear a conclusão da OS quando faltar evidência obrigatória já na Fase 1,
   ou só avisar e endurecer na Fase 5? Bloquear cedo gera dado limpo desde o começo e atrito com quem
   está aprendendo a ferramenta; avisar primeiro é mais gentil e custa alguns fechamentos incompletos.
   **Recomendação:** avisar na Fase 1, bloquear na Fase 8 — quando o roteiro já tiver a confiança da equipe.

### Abertas pela revisão 2
6. **Cobrar a visita de levantamento?** A prática mais comum no mercado é cobrar e **abater** o valor se
   o serviço fechar no mesmo atendimento, dito ao cliente antes da visita. Se a HBR não cobrar, o
   gatilho do P15 precisa ser mais estreito — cada levantamento é custo puro.
   **Recomendação:** cobrar com crédito integral, e só nos casos em que o gatilho disparou.
7. **Valor de corte entre linha e taxa, e o percentual da taxa.** A referência de mercado é 3% a 8% da
   mão de obra com teto. Precisa de dois números seus: o percentual e o valor abaixo do qual um item
   não vira linha.
   **Recomendação:** começar em 5% com teto, e valor de corte na casa de R$ 15 — e revisar depois de
   um trimestre com o dado real na mão.
8. **O levantamento pode ir direto ao cliente?** Um link com 3-4 perguntas e pedido de foto deflete
   viagem, mas expõe o cliente a perguntas técnicas que ele pode responder errado.
   **Recomendação:** sim, com perguntas marcadas `ask_remotely` — só as que um leigo consegue responder
   com uma foto ("manda uma foto do compartimento aberto"), nunca as que exigem julgamento técnico.

---

## 12. Bibliografia

Fontes consultadas e filtradas (as que só repetiam conteúdo já coberto foram descartadas).

### Modelos de dados de FSM (padrões da indústria)
1. https://learn.microsoft.com/en-us/dynamics365/field-service/incident-type-overview
2. https://learn.microsoft.com/en-us/dynamics365/field-service/configure-incident-types
3. https://learn.microsoft.com/en-us/dynamics365/field-service/field-service-architecture
4. https://microsoftlearning.github.io/MB-240-Dynamics365forFieldService/Instructions/Labs/LAB%5BMB-240%5D_Lab04_Incident_Types.html
5. https://stoneridgesoftware.com/dynamics-365-ce-field-service-incident-types-and-work-orders/
6. https://stoneridgesoftware.com/options-for-creating-work-orders-d365-field-service/
7. https://erpsoftwareblog.com/2025/08/customizing-work-order-types-in-dynamics-365-field-service/
8. https://nalashaadigital.com/blog/dynamics-365-fieldservice-workorder-management/
9. https://help.salesforce.com/s/articleView?language=en_US&id=service.fs_work_plans_intro.htm&type=5
10. https://help.salesforce.com/s/articleView?id=sf.mfs_work_plans_complete_with_mobile.htm&language=en_US&type=5
11. https://help.salesforce.com/s/articleView?language=en_US&id=sf.fs_appointment_guidelines.htm&type=5
12. https://help.salesforce.com/s/articleView?id=sf.fs_self_appointment_manage.htm&language=en_US&type=5
13. https://help.salesforce.com/s/articleView?id=sf.fs_set_up.htm&language=en_US&type=5
14. https://proquestit.com/insights/salesforce-field-service-work-plans/
15. https://www.salesforceben.com/salesforce-field-service/
16. https://growthheroes.com/salesforce-field-service-core-data-model/
17. https://www.aintiram.com/blog-work-orders-service-appointments
18. https://www.appshark.com/blog/fsl-optimizing-and-maintenance-plans
19. https://trailhead.salesforce.com/content/learn/modules/field_service_maint/field-service-generate-work-orders
20. https://help.zoho.com/portal/en/kb/fsm/faqs/service-appointments/articles/can-i-create-a-service-appointment-for-a-specific-services-in-a-work-order
21. https://en.wikipedia.org/wiki/ServiceMax
22. https://en.wikipedia.org/wiki/Field_force_automation
23. https://en.wikipedia.org/wiki/ClickSoftware

### Checklists e formulários em campo (produtos)
24. https://help.servicetitan.com/docs/forms
25. https://help.servicetitan.com/docs/use-forms
26. https://help.servicetitan.com/docs/trigger-technician-forms
27. https://help.servicetitan.com/v1/docs/add-technician-forms-in-fma
28. https://help.servicetitan.com/roofing/docs/forms-home
29. https://www.servicetitan.com/field-service-management/forms-in-field
30. https://www.servicetitan.com/podcasts/mastering-servicetitan/sena-sadeghi-interview
31. https://www.servicetitan.com/templates/hvac/commercial-maintenance-checklist
32. https://www.servicetitan.com/blog/hvac-technician-checklists
33. https://www.servicetitan.com/blog/hvac-checklist-app
34. https://www.getjobber.com/free-tools/job-sheet-template/
35. https://www.getjobber.com/comparison/jobber-vs-housecall-pro/
36. https://www.fieldpulse.com/resources/blog/housecall-pro-vs-jobber
37. https://contractorplus.app/blog/jobber-vs-housecall-pro
38. https://fieldcamp.ai/compare/jobber-vs-housecall-pro/
39. https://fieldpoint.net/mobile-checklists/
40. https://www.gomocha.com/field-service-maintenance-checklist/
41. https://www.produttivo.com.br/aplicativo-checklist/
42. https://www.produttivo.com.br/blog/field-service-fsm/
43. https://www.auvo.com/checklist
44. https://www.auvo.com/auvo-field-service
45. https://store.omie.com.br/apps/field-control
46. https://help.zoho.com/portal/ja/community/topic/zoho-fsm-ensure-consistent-service-delivery-with-comprehensive-job-sheets

### Gestão de ordem de serviço (processo)
47. https://www.servicepower.com/blog/work-order-management-best-practices-for-field-service
48. https://www.salesforce.com/ap/service/field-service-management/work-order-management/
49. https://www.ptc.com/en/technologies/service-lifecycle-management/field-service-management/work-order-management
50. https://www.bigchange.com/blog/work-orders-what-are-they-and-best-practices
51. https://www.d-tools.com/resource-center/operations-management/work-order-process
52. https://www.fieldservicely.com/field-service-management-best-practices
53. https://coskip.com/blog/proof-required-before-field-service-job-closeout
54. https://coskip.com/blog/field-service-job-closeout-documentation-checklist

### Náutico / marina
55. https://www.dockmaster.com/solutions/service-management
56. https://www.dockmaster.com/marine-service-management
57. https://www.dockmaster.com/dockworks
58. https://www.dockmaster.com/blog/marine-mechanic-software
59. https://www.dockmaster.com/blog/boat-maintenance-software
60. https://commanderne.com/solutions/marine/service
61. https://www.getapp.com/industries-software/marine/f/work-order-management/
62. https://www.scribd.com/document/510417079/4-r (Mercury Warranty Flat Rate Manual 90-889420)
63. https://www.screamandfly.com/archive/index.php/t-112119.html (flat rate real × garantia)
64. https://forums.iboats.com/threads/flat-rate-marine-mechanic-manual.735546/
65. https://www.maurermarine.com/about/rate-sheet/
66. https://partsvu.com/blogs/boating-resources/suzuki-outboard-100-hour-service-checklist
67. https://www.boats.net/blog/outboard-engine-100-hour-service-checklist
68. https://jlmmarine.com/blogs/outboard-101/routine-100-hour-service-checklist-for-outboards
69. https://partsvu.com/blogs/boating-resources/outboard-maintenance-schedule-what-to-do-and-when-for-a-long-running-engine
70. https://www.mercurymarine.com/us/en/lifestyle/dockline/four-stroke-maintenance
71. https://www.pyymarine.com/blog/4-stroke-outboard-engine-maintenance-checklist-from-pyy--103403
72. https://www.copemarine.com/blog/outboard-engine-maintenance-timeline-what-your-motor-needs-at-100-300-500--1000-hours--110155
73. https://mobilemarina.co/blog/outboard-motor-maintenance-the-complete-schedule-for-yamaha-mercury-suzuki
74. https://dot.alaska.gov/stwdmno/ports/assets/pdf/coastalengman/ch19.pdf (haul-out, cap. 19)
75. https://vesselvanguard.com/boat-haul-out/
76. https://www.myyachtmanagement.com/news/2021/vessel-haul-out-guide
77. https://caribbeancompass.com/hauling-out/

### Teoria do checklist e fatores humanos
78. https://www.designreview.byu.edu/collections/good-checklist-design-from-the-checklist-manifesto
79. https://grahammann.net/book-notes/the-checklist-manifesto-atul-gawande
80. https://www.mickmel.com/highlights-from-the-checklist-manifesto-by-atul-gawande/
81. https://jdan.dev/a-book-in-review-checklist-manifesto-by-atul-gawande/
82. https://jsilva.blog/2021/02/19/checklist-manifesto-summary/
83. https://www.systemhub.com/the-checklist-manifesto/
84. https://www.blinkist.com/en/books/the-checklist-manifesto-en
85. https://tractian.com/en/glossary/pencil-whipping
86. https://goaudits.com/blog/pencil-whipping-box-checking/
87. https://www.emaint.com/blog/what-is-pencil-whipping-and-how-to-avoid-it/
88. https://servicechannel.com/blog/pencil-whipping-in-maintenance/
89. https://www.monitorqa.com/blog/pencil-whipping
90. https://pti4you.com/blog/articles/stop-pencil-whipping-digital-dvir-compliance
91. https://pathspot.com/crushing-pencil-whipping-your-ultimate-playbook-for-a-more-efficient-organization/

### Instruções digitais de trabalho e MES
92. https://tulip.co/digital-guidance/digital-work-instructions/
93. https://www.dozuki.com/digital-work-instructions
94. https://www.dozuki.com/resources/sop-work-instructions-guides
95. https://scribe.com/library/work-instructions-software
96. https://humbleops.com/resources/best-digital-work-instructions-software-manufacturers-2026
97. https://pluto-men.com/dozuki-alternatives/
98. https://erpnext.com/manufacturing/job-cards
99. https://erpnext.com/manufacturing/work-orders
100. https://docs.erpnext.com/docs/v12/user/manual/en/manufacturing/job-card
101. https://github.com/frappe/erpnext/blob/develop/erpnext/manufacturing/doctype/job_card/job_card.json
102. https://discuss.frappe.io/t/operations-job-card-work-order/127536
103. https://www.odoo.com/app/field-service-features
104. https://www.odoo.com/documentation/19.0/applications/services/timesheets.html
105. https://www.odoo.com/documentation/19.0/applications/services/helpdesk/advanced/track_and_bill.html
106. https://www.ksolves.com/blog/odoo/odoo-field-service-module-for-end-to-end-efficiency
107. https://docs.oracle.com/en/cloud/saas/supply-chain-and-manufacturing/26a/faumf/how-you-print-work-order-traveler.html
108. https://proshoperp.com/blog/the-dangerous-ubiquitous-paper-job-traveler-packet/
109. https://jobpack.com/paperless-manufacturing-workflow-job-shops/
110. https://jobpack.com/paperless-shop-floor-cnc-machining/
111. https://www.practicalmachinist.com/forum/threads/going-paperless.431334/
112. https://www.practicalmachinist.com/forum/threads/paperless-or-less-paper-job-tracking-routing-job-shop-specific.327437/

### Produtividade, tempos e custo
113. https://reliabilityacademy.com/articles/planning-scheduling/what-is-wrench-time
114. https://www.getmaintainx.com/learning-center/what-is-wrench-time
115. https://www.prometheusgroup.com/resources/posts/5-things-you-need-to-know-about-measuring-wrench-time
116. https://reliabilityweb.com/articles/entry/is-wrench-time-worth-measuring
117. https://tractian.com/en/blog/wrench-time-maintenance-productivity
118. https://reliamag.com/articles/how-to-measure-and-improve-wrench-time/
119. https://www.idcon.com/resource-library/materials-management/kitting-and-staging-parts/
120. https://zoidii.com/blogpost/parts-kitting-work-orders
121. https://f7i.ai/blog/the-maintenance-leaders-guide-to-kitting-reducing-wrench-time-by-30
122. https://reliamag.com/cartoons/maintenance-job-kitting-best-practices-2/
123. https://www.accountingtools.com/articles/labor-efficiency-variance
124. https://en.wikipedia.org/wiki/Direct_labour_cost_variance
125. https://glacierlakepartners.com/insights/fully-burdened-labor-cost-job-service-line
126. https://pushleads.com/job-costing-for-service-contractors/how-to-calculate-your-burdened-labor-rate/
127. https://www.servicetitan.com/blog/budget-vs-actual
128. https://leanscaper.com/blog/tracking-estimated-vs-actual-labor-hours-for-crews
129. https://drawer.ai/blog/ai-field-feedback-compare-estimated-vs-actual-labor-productivity
130. https://www.nomus.com.br/blog-industrial/metodos-de-determinacao-do-tempo-padrao/
131. https://www.kimia.com.br/cronoanalise-estudo-tempos-metodos/
132. https://www.novida.com.br/blog/cronoanalise/
133. https://periodicos.uem.br/ojs/index.php/rev_prod/article/download/52357/pdf/
134. https://terzoni.com.br/leanblog/tempos-metodos/
135. https://pmstudycircle.com/three-point-estimation/
136. https://project-management.info/three-point-estimating-pert/
137. https://projectmanagementacademy.net/resources/blog/a-three-point-estimating-technique-pert/

### Indicadores de serviço
138. https://www.servicetitan.com/blog/field-service-metrics
139. https://comparesoft.com/field-service-management-software/first-time-fix-rate-ftfr/
140. https://llumin.com/blog/what-is-the-first-time-fix-rate-ftfr/
141. https://www.ptc.com/en/blogs/service/what-is-first-time-fix-rate
142. https://www.ibm.com/think/topics/first-time-fix-rate
143. https://fieldnation.com/resources/improve-first-time-fix-rate
144. https://www.getac.com/us/blog/first-time-fix-rate/
145. https://www.gomocha.com/what-is-schedule-adherence-in-field-service/
146. https://en.wikipedia.org/wiki/Delivery_schedule_adherence

### Paradas, motivos e fluxo
147. https://www.machinetracking.com/post/downtime-reason-codes
148. https://www.makula.io/blog/production-downtime-tracking
149. https://llumin.com/blog/what-is-idle-time/
150. https://www.getmaintainx.com/learning-center/what-is-idle-time
151. https://limble.com/learn/causes-of-downtime-manufacturing
152. https://mpulsesoftware.com/blog/cmms/machine-downtime-tracking-best-practices/
153. https://businessmap.io/kanban-resources/getting-started/what-is-wip
154. https://kanbantool.com/kanban-wip-limits
155. https://www.jitbase.com/blog/kanban-vs-continuous-flow-wip-software
156. https://fabriq.tech/en/2025/11/06/kanban-board/

### Agendamento, roteirização e competências
157. https://people.cs.nott.ac.uk/pszrq/files/patat2012.pdf (survey WSRP)
158. https://onlinelibrary.wiley.com/doi/full/10.1002/net.22188
159. https://arxiv.org/pdf/2309.09321 (multi-skill, janelas e sincronização)
160. https://arxiv.org/pdf/2008.02849 (tarefas dependentes)
161. https://arxiv.org/pdf/2604.05153 (column generation, objetivo lexicográfico)
162. https://www.sciencedirect.com/science/article/abs/pii/S0305054823002496
163. https://openproceedings.org/2019/conf/inoc/INOC_2019_paper_25.pdf
164. https://kahunaworkforce.com/field-service-dispatch-skills-management/
165. https://www.fieldproxy.ai/resources/blog/field-service-skills-management
166. https://www.maintainnow.app/learn/definitions/technician-skill-matrix
167. https://www.salesforce.com/service/field-service-management/route-optimization/
168. https://www.getjobber.com/academy/what-is-route-optimization/
169. https://www.joblogic.com/products/dynamic-scheduler

### IA aplicada a serviço
170. https://www.aquant.ai/solutions/field-technicians
171. https://www.aquant.ai/platform
172. https://www.aquant.ai/agent-library
173. https://www.aquant.ai/cios-corner-articles/beyond-rag-why-enterprises-need-retrieval-augmented-conversation-rac
174. https://oxmaint.com/article/ai-work-order-generation-automation
175. https://oxmaint.com/blog/post/agentic-ai-maintenance-copilot-self-schedule-work-orders-2026
176. https://oxmaint.com/article/voice-to-text-work-orders
177. https://fieldcode.com/en/resources/press-releases/ai-llm-workflow-actions
178. https://www.techrev.us/blog/ai-in-field-service-management/
179. https://brocoders.com/blog/ai-in-field-service-management/
180. https://doi.org/10.3390/fire9020065 (LLM gerando OS de manutenção de proteção contra incêndio)
181. https://www.salesforce.com/blog/voice-to-form/

### Confiabilidade de IA em procedimento industrial
182. https://arxiv.org/html/2603.10047 (estabilidade epistêmica; M1-M5)
183. https://arxiv.org/html/2605.24219v2 (alucinação em trajetória multiagente)
184. https://arxiv.org/html/2605.10267v3 (IndustryBench)
185. https://www.sciencedirect.com/science/article/pii/S0925753525002814
186. https://arxiv.org/pdf/2501.17183
187. https://www.agentic-patterns.com/patterns/human-in-loop-approval-framework/
188. https://www.stackai.com/insights/human-in-the-loop-ai-agents-how-to-design-approval-workflows-for-safe-and-scalable-automation
189. https://www.kamiwaza.ai/insights/ai-audit-trail-keeping-humans-in-the-loop
190. https://teamcopilot.ai/blog/human-in-the-loop-ai-agents-approvals-permissions-audit-trails
191. https://community.sap.com/t5/artificial-intelligence-blogs-posts/human-in-the-loop-sap-agents-approval-escalation-and-audit-series-2-part-5/ba-p/14372994

### Pessoas: adoção, remuneração, gamificação
192. https://www.panorama-consulting.com/how-to-address-erp-resistance-in-field-service/
193. https://www.repair-crm.com/2026/05/14/getting-your-team-to-adopt-new-technology-a-field-service-leaders-guide
194. https://www.skyllful.com/poor-tech-adoption-is-killing-your-service-metrics
195. https://www.fieldproxy.ai/articles/field-service-change-management-software-adoption
196. https://chriscollinsinc.com/sdr/hourly-vs-flat-rate-best-automotive-technician-pay-plans/
197. https://www.uti.edu/blog/automotive/hourly-rate-vs-flat-rate-how-auto-mechanics-are-paid
198. https://shopcommander.com/blog/flat-rate-vs-hourly.html
199. https://www.fullbay.com/blog/flat-rate-vs-hourly/
200. https://mechanics.app/blog/technician-flat-rate-explained
201. https://www.mdpi.com/2079-8954/7/1/9 (taxonomia de riscos de gamificação)
202. https://www.mdpi.com/2071-1050/13/12/6608 (leaderboard e estresse)
203. https://arxiv.org/pdf/1906.01577
204. https://medium.com/@kaizo/death-of-the-leaderboard-why-ranking-is-whats-wrong-in-workplace-gamification-7af68c408b60
205. https://www.levelup.plus/blog/leaderboards-good-or-bad/

### Evidência, comunicação e trabalho adicional
206. https://www.smartservice.com/blog/photos-work-orders
207. https://www.repair-crm.com/2026/06/01/photo-capture-for-work-orders-a-practical-guide-for-small-field-service-teams
208. https://www.getskimmer.com/why-skimmer/qna-hub/how-can-pool-companies-provide-proof-of-service-with-photos-reports-and-before-and-after-documentation
209. https://goaudits.com/blog/field-service-report/
210. https://truescreen.io/use-cases/certified-field-activities/
211. https://ryooma.com/siteticket/change-order-wording
212. https://ryooma.com/siteticket/customer-keeps-adding-work
213. https://www.bluesuite.app/blog/change-order-software/
214. https://www.salesforce.com/service/field-service-management/field-service-quoting/
215. https://corp.glympse.com/blog/proactive-communication-to-improve-customer-engagement/
216. https://www.upperinc.com/blog/how-customer-notifications-reduce-calls/
217. https://www.fieldproxy.ai/resources/blog/automated-customer-notifications-reducing-support-calls-by-60-d1-33
218. https://www.migalhas.com.br/depeso/435882/a-validade-juridica-da-assinatura-eletronica-no-cenario-juridico
219. https://www.totvs.com/blog/gestao-para-assinatura-de-documentos/mp-2200/

### Base técnica (offline, QR, código aberto) e trabalhista
220. https://rohitraj.tech/en/notes/pwa-offline-sync
221. https://letsbuildsolutions.com/blog/web-engineering/building-offline-first-web-applications-service-workers-indexeddb-and-sync-strategies-in-production/
222. https://gtcsys.com/comprehensive-faqs-guide-data-synchronization-in-pwas-offline-first-strategies-and-conflict-resolution/
223. https://edana.ch/en/2026/04/05/can-a-web-app-pwa-really-work-offline-like-a-native-app/
224. https://www.getmaintainx.com/blog/using-qr-codes-in-maintenance
225. https://eworkorders.com/asset-management/asset-tagging/
226. https://oxmaint.com/blog/post/blog-post-cmms-qr-code-asset-tagging-guide
227. https://github.com/Grashjs/cmms (Atlas CMMS — AGPLv3, Spring Boot + React + React Native)
228. https://atlas-cmms.com/features/work-orders
229. https://github.com/topics/field-service-management
230. https://supercmms.com/open-source-cmms
231. https://fieldservicesoftware.io/blog/field-service-software-open-source/
232. https://www.mywork.com.br/blog/portaria-671-controle-de-ponto
233. https://factorialhr.com.br/blog/controle-de-ponto-eletronico-portaria-671/
234. https://safetyculture.com/topics/toolbox-topics
235. https://sitemate.com/resources/articles/safety/daily-toolbox-talks/
236. https://blog.spccglobal.com/sop-approval-and-version-control-best-practices/

---

## Bibliografia da revisão 2

### Levantamento antes de orçar, vistoria e triagem remota
237. https://schnackel.com/blogs/10-essential-tips-that-make-a-field-survey-a-success
238. https://systemsurveyor.com/security-system-design-news/downloadable-checklist-10-best-practices-for-a-successful-site-survey
239. https://safetyculture.com/library/property-and-facilities-management/site-survey-initial-visit-zxpibpvg67bnjlbg
240. https://lynxplanning.com/us/a-guide-to-modern-telecom-site-surveys-and-field-assessments/
241. https://enervio.io/blog/solar-site-survey-template-questions
242. https://www.zuper.co/free-tools/solar-site-survey-checklist
243. https://www.fieldengineer.com/field-services/site-survey-readiness
244. https://www.mccormicksys.com/blog/am-i-missing-anything-an-estimating-checklist-for-electrical-plumbing-mechanical-contractors/
245. https://www.servicetitan.com/blog/plumbing-estimating
246. https://www.method.me/pricing-guides/estimate-residential-electrical-work/
247. https://pilars.ai/trades/plumbing/cost-estimating
248. https://errobuilt.com/blog/estimating-and-pricing/plumbing-estimate-template-guide
249. https://www.housecallpro.com/resources/marketing/how-to/how-to-price-plumbing-jobs/
250. https://www.namsglobal.org/
251. https://boatzon.com/blog/how-to-read-marine-survey-report/
252. https://novielliyachts.com/blogs/news/marine-survey-checklist-for-first-time-boat-buyers
253. https://blitzz.co/blog/field-technician-remote-support
254. https://www.ifs.com/en/products/fsm/remote-assistance
255. https://techsee.com/techsee-live-field-services/

### Perguntas geradas por IA e quando parar de perguntar
256. https://arxiv.org/html/2406.00922v1 (MediQ — módulo de abstenção, +22,3%; perguntas ruins custam −11,3%)
257. https://arxiv.org/html/2501.05985 (geração e adaptação de questionários por LLM)
258. https://dl.acm.org/doi/full/10.1145/3719160.3736606
259. https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12097556/ (questionários adaptativos, cold start)
260. https://arxiv.org/pdf/2302.08099 (desenho bayesiano ativo de questionário)
261. https://arxiv.org/pdf/1109.2127 (políticas de diagnóstico com custo por pergunta)
262. https://arxiv.org/pdf/1408.2048 (valor da informação; regra de parada de um passo)
263. https://sites.cs.ucsb.edu/~suri/ccs130a/OptStopping.pdf
264. https://supportcenter.mycase.com/en/articles/9628063-dynamic-intake-forms-with-conditional-logic
265. https://ingmarweber.de/wp-content/uploads/2025/07/Exploring-LLMs-for-Automated-Generation-and-Adaptation-of-Questionnaires.pdf

### Estimativa: viés, analogia e contingência
266. https://www.researchgate.net/publication/233258056_Curbing_Optimism_Bias_and_Strategic_Misrepresentation_in_Planning_Reference_Class_Forecasting_in_Practice
267. https://www.pmi.org/learning/library/nobel-project-management-reference-class-forecasting-8068
268. https://www.tandfonline.com/doi/full/10.1080/09537287.2025.2578708
269. https://arxiv.org/pdf/1302.3642 (Flyvbjerg — getting risks right)
270. https://arxiv.org/pdf/1802.07312
271. https://corporate.jasoncollins.blog/outside-view
272. https://www.sciencedirect.com/science/article/abs/pii/S0925231217311165 (CBR para custo de novo produto)
273. https://www.sciencedirect.com/science/article/abs/pii/S2352710225023575 (CBR + suavização exponencial)
274. https://www.mdpi.com/2071-1050/12/19/7920 (CBR híbrido com algoritmo genético)
275. https://www.sciencedirect.com/science/article/abs/pii/S0926580523000377 (robustez de CBR em fase inicial)
276. https://www.semanticscholar.org/paper/Similarity-measurement-method-of-case-based-for-Ji-Park/af41f089670ab712bdecfc7117b53a7707624cd4
277. https://www.projectcontrolacademy.com/cost-contingency-calculation/

### Materiais, consumíveis, EPI e cobrança da visita
278. https://www.fullbay.com/blog/heavy-duty-shop-supplies/
279. https://www.automotivemanagementnetwork.com/forums/topic/shop-supply-charges/
280. https://woodweb.com/knowledge_base/Calculating_a_Shop_Labor_Rate.html
281. https://www.housecallpro.com/resources/calculate-markup-margin/
282. https://app.aws.org/forum/topic_show.pl?tid=29612 (markup de consumíveis, fórum de soldagem)
283. https://www.workzen.io/en/blog/job-costing-for-small-service-business/
284. https://www.nomitech.com/cost-estimating/estimating-material-cost
285. https://prebuiltml.com/blog/2024/06/17/material-takeoff-basics-the-factor-of-waste/
286. https://amcengineer.com/bill-of-materials/
287. https://eziil.com/glossary/material-takeoff-mto-steel-fabrication/
288. https://professor.pucgoias.edu.br/sitedocente/admin/arquivosUpload/10107/material/Aula%206%20-%20Crit%C3%A9rio%20de%20rateio%20dos%20custos%20indiretos.pdf
289. https://inforos.com.br/calcular-preco-ordem-de-servico-guia-pratico/
290. https://www.servicetitan.com/field-service-management/perfect-diagnostic-fee
291. https://fieldedge.com/blog/diagnostic-fee-service-fee-trip-charge/

### Auto-aprendizado, memória e salvaguardas
292. https://arxiv.org/html/2607.13104v1 (survey de auto-aprimoramento agêntico; preferir andaime a parâmetros)
293. https://arxiv.org/html/2606.25115 (CURATOR — valor líquido por byte; log cru −26,1 → insight +3,3)
294. https://arxiv.org/pdf/2607.07663 (auto-aprimoramento recursivo, limites)
295. https://arxiv.org/pdf/2512.23760 (skill-graph auditado com recompensa verificável)
296. https://nhimg.org/articles/agentic-ai-memory-poisoning-exposes-persistent-governance-gaps/
297. https://mem0.ai/blog/ai-memory-security-best-practices

### Avaliação, portão de qualidade e desempenho de orçamento
298. https://medium.com/@falvarezpinto/evaluation-first-ai-product-engineering-golden-sets-drift-monitoring-and-release-gates-for-llm-2c3bfb3f1e7b
299. https://langfuse.com/resources/engineering/golden-dataset-evaluation
300. https://galtea.ai/blog/automated-llm-evaluation-building-a-ci-cd-quality-gate-that-actually-runs
301. https://k38consulting.com/proven-construction-bid-accuracy/
302. https://downtobid.com/blog/eight-subcontractor-kpis
