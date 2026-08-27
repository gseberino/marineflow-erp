# MarineFlow — Controle de Jornada e Pagamento de Equipe e Freelancers

**Data:** 18/08/2026 · **Status:** Fases 1 a 5 no ar em 24/08/2026
**Pedido:** controlar diária e horário de funcionários e freelancers, chegar ao valor a pagar, e permitir o registro pelo agente IA e pelo WhatsApp.

> **STATUS EM 24/08/2026 — o ciclo fecha inteiro: dia trabalhado → valor apurado → conta a pagar → custo do serviço.**
>
> - **Fases 1-3** (18/08): `work_profiles`, `work_shifts`, `payroll_periods`, `payroll_lines` com RLS; motor puro em `_shared/payroll/calculo.ts`; ferramentas do agente em `_shared/ai/tools/jornada.ts`.
> - **Fase 4** (24/08, migration `20260824120000`): **`fechar_folha`** apura todo mundo com perfil vigente e **gera uma conta a pagar por pessoa**, via a RPC `gravar_fechamento_de_folha` — atômica, só de gestor, e com índice único em `(de, ate)` porque fechar o mesmo período duas vezes pagaria a equipe em dobro. `origin='folha'` precisou entrar no `chk_payables_origin`, que é lista fechada. Categoria da despesa vem do `tipo_vinculo`, não de texto livre.
> - **Fase 5** (24/08, migration `20260824130000`): **`v_custo_real_mao_de_obra_por_os`** — o que a mão de obra de cada OS custou de fato, lido do detalhamento das linhas já fechadas. `work_shifts.service_order_id` e o `turno_id` no detalhamento são o rastro; `registrar_jornada` aceita a OS **na mesma frase** ("diária no barco do Rodrigo").
> - **Equipe cadastrada** (23/08): Roberto (diária R$ 160) e Mickael (R$ 130), meia diária até 4h, como `payees` — não como `app_users`, porque não vão usar o sistema ainda e conta ociosa é dívida de segurança, não cadastro.
> - **Custo no agente:** 5 ferramentas, 1.155 tokens.
>
> **O que continua aberto:**
> - **Tela de Folha** não existe. Hoje o fechamento se faz pelo agente. Foi opção: a tela serve para conferir muitas linhas, e são duas pessoas.
> - **Retenção de ISS fica em zero** até a contadora confirmar o que Itajaí exige do prestador. Chutar retenção erra o valor pago a alguém, e o erro só aparece no recibo da pessoa.
> - **Fase 0 (WhatsApp para a equipe)** segue bloqueada por dado — ninguém da equipe tem `phone_normalized`. E Felipe foi desligado em 23/08.
> - **`time_entries` continua com 0 linhas.** A Fase 5 foi construída sobre o turno justamente por isso (ver §5 abaixo). O rateio de um dia entre duas OS espera esse dado.
> - Decisões 4, 5 e 6 da seção 7 seguem sem resposta. Não travam nada hoje: **no regime de diária, hora extra e DSR não se aplicam** — o dia é valor fechado.

---

## 1. O que JÁ existe (e por que quase nada disso funciona hoje)

| Peça | Estado | Observação |
|---|---|---|
| `time_entries` | tabela existe, **0 linhas** | `service_order_id` é **NOT NULL** |
| `log_service_order_hours` | ferramenta existe | **nunca chamada** em toda a auditoria |
| `remove_service_order_hours` | ferramenta existe | nunca chamada |
| `check_in_service_order` / `check_out_service_order` | existem | nunca chamadas |
| `service_order_technicians` | existe | quem trabalhou em qual OS |
| `v_service_order_labor_variance` | view existe | previsto × realizado de mão de obra |
| `commissions` | 1 linha | **já liga em `payables` por `payable_id`** |
| `payees` (favorecidos) | 5 cadastrados | nome, documento, PIX, banco, `kind` |
| `app_users` | 5 pessoas, 3 ativas | já tem `cpf`, `hiring_date`, `salary_base`, `pix_key` |

**Três conclusões que orientam o resto:**

1. **O caminho até o dinheiro já existe.** `commissions → payable_id → payables` é o trilho que transforma trabalho feito em conta a pagar. A ferramenta nova não precisa inventar pagamento — precisa alimentar esse trilho.

2. **`time_entries` não serve para jornada, só para hora de OS.** Com `service_order_id NOT NULL`, não há onde registrar dia de oficina, deslocamento entre serviços, trabalho administrativo ou uma diária. É a lacuna central.

3. **A ferramenta de apontar hora existe e nunca foi usada — isso é um dado, não um detalhe.** Construir mais ferramentas sobre um hábito inexistente repetiria o erro. Ver a seção 5.

---

## 2. O que a lei exige (e o que ela NÃO exige, no tamanho da HBR)

### 2.1 Registro de ponto: não é obrigatório aqui

A Portaria MTP 671/2021 organiza o registro de jornada em REP-C, REP-A e REP-P (programa). **A obrigatoriedade começa acima de 20 empregados.** A HBR tem 5 cadastros, 3 ativos.

**Consequência prática, e é grande:** não é preciso construir um REP-P — com AFD, certificação, numeração sequencial inviolável, exportação fiscal. Isso economiza a maior parte do esforço.

**Ressalva registrada:** se a empresa optar por um sistema eletrônico de *ponto*, ele deve seguir a portaria. O desenho abaixo evita isso ao se posicionar como **controle gerencial de horas e custo**, não registro de ponto legal — não emite espelho de ponto nem comprovante com fé de registro. Passando de 20 empregados, é outro projeto.

### 2.2 Freelancer: o RPA saiu de cena em janeiro de 2026

**Desde 01/01/2026 a NFS-e é obrigatória para profissionais autônomos**, emitida por eles próprios no portal nacional. O RPA não desapareceu juridicamente, mas foi substituído na prática.

**Para o MarineFlow:** a HBR **recebe** a nota do freelancer — não emite RPA. O sistema deve registrar a nota recebida e conciliá-la com o apurado. Campos de retenção federal e ISS saem zerados para autônomo e MEI, salvo exigência municipal.

> ⚠️ Conclusão de pesquisa, não de contadora. Itajaí pode ter regra própria de retenção de ISS, e a HBR está no Simples. **Confirmar antes da Fase 3.**

### 2.3 Regras de cálculo (CLT)

| Item | Regra |
|---|---|
| Hora normal | salário mensal ÷ **220** |
| Hora extra diurna | **+50%** (art. 59) |
| Adicional noturno (22h–5h) | **+20%** (art. 73) |
| Domingo/feriado | **+100%** |
| Hora extra noturna | cumulativa: hora × 1,20 × 1,50 = **× 1,80** |
| DSR sobre extras | total HE ÷ dias úteis × domingos e feriados do mês |

Convenção coletiva pode elevar esses percentuais — o sistema precisa permitir sobrescrever.

---

## 3. O que o mercado faz (e o que vale copiar)

De ClockShark, Jobber, Hubstaff, Procore, SmartBarrel, FOUNDATION e Miter:

**Vale copiar:**
- **Job costing** — hora lançada contra a OS, custo real contra o orçado. *A HBR já tem metade disso em `v_service_order_labor_variance`.*
- **Aprovação antes de virar dinheiro** — registro entra como rascunho; só aprovado vira conta a pagar. Sem isso, erro de digitação vira pagamento.
- **Lançamento diário, não semanal** — consenso em todas as fontes: esperar o fim da semana produz timesheet inventado de memória.
- **Múltiplas formas de pagamento por pessoa** — a mesma pessoa pode ter hora, diária e empreitada em períodos diferentes. FOUNDATION e ADP tratam como requisito básico.
- **Alerta de estouro** — avisar quando a mão de obra da OS passa do previsto, *antes* de fechar.

**Não vale copiar agora:**
- **Geofence/GPS.** É a feature mais vendida do segmento e resolve um problema que a HBR não tem: fraude de ponto em equipe grande. Com 3 ativos e o dono sendo o técnico principal, o custo (privacidade, bateria, app dedicado, suporte) supera o ganho. **Opção futura, não construir.**
- **Certified payroll / prevailing wage** — exigência de obra pública americana.
- **Folha completa** — a HBR tem contadora. O sistema produz o *insumo* da folha.

---

## 4. Desenho proposto

### 4.1 Princípio: separar jornada de hora cobrável

- **Jornada** = o que a pessoa trabalhou → base do que ela **recebe**
- **Hora de OS** = o gasto num serviço → base do que o cliente **paga** e da margem

Uma jornada de 8h pode conter 5h em duas OS, 1h de deslocamento e 2h de oficina. Hoje só as 5h teriam onde ser registradas — e é por isso que o custo real de mão de obra nunca fecha.

### 4.2 Modelo de dados

**`work_profiles`** — como cada pessoa é paga, com vigência (regime muda).

| Campo | Para quê |
|---|---|
| `app_user_id` / `payee_id` | funcionário tem login; freelancer é favorecido (já existe) |
| `tipo_vinculo` | clt · diarista · freelancer · pj · socio |
| `modo_pagamento` | hora · diaria · mensal · empreitada |
| `valor_hora`, `valor_diaria`, `valor_mensal` | conforme o modo |
| `meia_diaria_ate_horas` | abaixo disso paga meia diária |
| `jornada_diaria_horas`, `divisor_mensal` | 8h e 220 por padrão |
| `pct_hora_extra`, `pct_noturno`, `pct_domingo` | 50/20/100, sobrescrevíveis |
| `paga_dsr` | só CLT |
| `vigencia_inicio`, `vigencia_fim` | histórico; recalcular o passado não muda o que já foi pago |

**`work_shifts`** — a jornada. **Sem** `service_order_id` obrigatório:
`worker_id` · `data` · `inicio` · `fim` · `intervalo_minutos` · `tipo` (normal/diaria/folga/falta/atestado) · `origem` (whatsapp/painel/agente/importado) · `status` (rascunho/aprovado/pago) · `observacao` · `registrado_por`

**`time_entries` continua e ganha `shift_id` opcional.** Nada quebra; o que muda é poder perguntar "das 8h do dia, quantas foram cobráveis?".

**`payroll_periods`** — `de` · `ate` · `status` (aberto/fechado/pago) · `fechado_por`

**`payroll_lines`** — resultado por pessoa, com memória de cálculo aberta: horas normais, extras diurnas, extras noturnas, domingos, diárias inteiras e meias, comissões do período, descontos, **bruto**, retenções, **líquido**, `payable_id`.

### 4.3 Cálculo

```
Por hora:    horas_normais   × valor_hora
           + horas_extras    × valor_hora × (1 + pct_he)
           + horas_noturnas  × valor_hora × 1,20 × (1,5 se extra)
           + domingos        × valor_hora × 2,00
           + DSR (se CLT)    = total_extras ÷ dias_uteis × domingos_e_feriados

Por diária:  dias_completos × valor_diaria
           + dias_parciais  × valor_diaria × 0,5

Empreitada:  valor fechado por OS, independente de horas

Em todos:    + comissões do período (já existem)
             − adiantamentos e descontos
```

**Regra de ouro:** gravar a memória de cálculo item a item. Um valor sem a conta ao lado gera discussão que ninguém consegue resolver depois.

### 4.4 Do trabalho ao pagamento

```
registro (WhatsApp/painel/agente)
   → work_shift [rascunho]
   → aprovação do dono          ← nada vira dinheiro sem passar aqui
   → fechamento do período
   → payroll_line (com memória de cálculo)
   → payable  [trilho que JÁ existe]
   → pagamento + baixa
```

Para freelancer, um passo a mais: **anexar a NFS-e que ele emitiu** e conferir contra o apurado. Divergência é alerta, não bloqueio.

---

## 5. Registro pelo agente IA e pelo WhatsApp

**A lição de `log_service_order_hours` — existe, é ensinada no prompt, nunca foi usada — precisa ser respeitada, não repetida.**

### 5.1 Por que a ferramenta atual morreu (hipóteses)

1. **O único técnico cadastrado está com `ai_whatsapp_enabled = false`.** Quem mais precisaria registrar hora não consegue falar com o agente. *Hipótese mais provável e mais barata de testar.*
2. Apontar hora não resolve um problema que arde na hora — lembra-se do serviço, não das horas.
3. O prompt instrui, mas nada **pergunta**. Registro que depende de iniciativa não acontece.

### 5.2 O desenho que decorre disso

**Perguntar, não esperar.** O motor de automações (cron de 15 min, já existe) manda no fim do dia: *"Fechou o dia? Responda as horas ou diária."* Uma pergunta responde por si; uma instrução no prompt não. Mesmo princípio que fez a regra do item físico funcionar quando saiu do prompt e virou verificação no código.

| O que a pessoa diz | O que acontece |
|---|---|
| "cheguei" / "comecei" | abre turno com hora de agora |
| "terminei" / "saí" | fecha o turno, calcula duração, mostra o total do dia |
| "trabalhei 8h hoje" | turno fechado direto |
| "hoje foi diária" | turno tipo diária |
| "o Felipe fez diária hoje" | dono registra por terceiro (exige papel de gestor) |
| "das 8 às 17, uma hora de almoço" | turno com intervalo |
| "quanto vou receber esse mês?" | prévia do período aberto |
| "quanto devo pro Felipe?" | idem, visão do dono |

**Cinco ferramentas novas, não quinze:**
`registrar_jornada` · `fechar_jornada` · `minhas_horas` · `apurar_pagamento` · `fechar_periodo`

E **reaproveitar** `check_in_service_order` / `check_out_service_order`: passam a abrir e fechar turno além de marcar a OS.

> ⚠️ Cada ferramenta custa ~256 tokens em toda chamada do agente (ver `plans/marineflow-otimizacao-prompt-e-tokens.md`). Cinco ≈ 1.280 tokens. O preço deve ser cobrado do canal certo: **estas entram no WhatsApp** (é onde o técnico está) e `fechar_periodo` fica só no painel.

**Confiança:** registrar a própria jornada é risco baixo. Registrar a de outra pessoa, ou fechar período, mexe em dinheiro de terceiro — vai para o fluxo de confirmação que já existe.

---

## 6. Fases

| Fase | Entrega | Por que nesta ordem |
|---|---|---|
| **0** | Habilitar WhatsApp do técnico e testar `log_service_order_hours` como está | Custa quase nada e testa a hipótese central antes de construir. Se passar a ser usada, o problema era acesso — e o resto fica mais simples. |
| **1** | `work_profiles` + `work_shifts` + tela de cadastro | A lacuna estrutural. Sem lugar para o dia sem OS, nada fecha. |
| **2** | Registro pelo WhatsApp + a pergunta do fim do dia | Onde o hábito nasce ou não nasce |
| **3** | Motor de cálculo + `payroll_periods` + `payroll_lines` | Só depois de haver dado real |
| **4** | Fechamento → `payable`, anexo da NFS-e do freelancer | Fecha o ciclo no trilho existente |
| **5** | Custo real de mão de obra por OS contra o orçado | O ganho gerencial: qual serviço dá prejuízo |

**Fase 0 antes de tudo** — a diferença entre construir sobre hipótese e sobre fato.

---

## 7. Decisões que dependem do dono

1. **Quem são as pessoas?** Hoje 1 técnico e 5 favorecidos. Quantos freelancers de fato, com que frequência?
2. **Qual o regime de cada um?** CLT, diarista, freelancer com nota, PJ? Define quanto do motor de cálculo precisa existir na Fase 3.
3. **Meia diária existe?** Se sim, abaixo de quantas horas?
4. **Hora extra se paga ou se compensa?** Banco de horas muda o modelo.
5. **O dono aponta as próprias horas?** Se o custo dele não entra, a margem por OS continua mentindo — decisão de gestão, não técnica.
6. **Deslocamento conta como jornada paga?** Hoje é cobrado do cliente (`travel_hourly_*`); se também é pago ao técnico, é outra conta.

---

## 8. O que este plano deliberadamente NÃO faz

- **Não vira REP-P.** Não é ponto legal, não emite espelho, não gera AFD.
- **Não emite RPA.** Desde 01/2026 quem emite é o autônomo, via NFS-e. O sistema recebe e concilia.
- **Não substitui a contadora.** Produz o insumo da folha, com memória de cálculo aberta.
- **Não faz geofence.** Resolve fraude que uma equipe de 3 pessoas não tem.
- **Não recalcula o passado.** Perfil tem vigência; mudar o valor-hora hoje não mexe no já pago.

---

## 9. Fontes

- [Portaria 671/2021 — Perguntas e Respostas (gov.br)](https://www.gov.br/trabalho-e-emprego/pt-br/assuntos/inspecao-do-trabalho/fiscalizacao-do-trabalho/Perguntas%20e%20Respostas%20REP)
- [Portaria 671 — o que mudou (Pontotel)](https://www.pontotel.com.br/portaria-671/)
- [Mudança na emissão de RPA a partir de janeiro de 2026 (Sindireceita)](https://sindireceita.org.br/noticias/2025/12/30/mudanca-importante-na-emissao-de-rpa-a-partir-de-janeiro-de-2026)
- [Cálculo RPA 2026 (Contabilizei)](https://www.contabilizei.com.br/contabilidade-online/calculo-rpa-recibo-pagamento-autonomo/)
- [Horas extras, adicional noturno e DSR 2026 (LegalSuite)](https://legalsuite.com.br/blog/trab-horas-extras-calculo-completo-2026)
- [Geofence time tracking (ClockShark)](https://www.clockshark.com/tour/geofence-time-tracking)
- [Job Costing (Jobber)](https://help.getjobber.com/hc/en-us/articles/14343244961175-Job-Costing)
- [Construction Labor Cost Tracking 2026 (SmartBarrel)](https://smartbarrel.io/blog/construction-labor-cost-tracking-complete-guide/)
- [Múltiplas taxas de pagamento (ADP)](https://www.adp.com/resources/articles-and-insights/articles/p/paying-employees-with-multiple-pay-rates.aspx)
