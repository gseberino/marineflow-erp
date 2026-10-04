# Avaliação de três recursos de IA — medida em 04/10/2026

Avaliação somente-leitura. Medi de novo no banco de produção (só SELECT) e no código da main
(`marineflow-erp--diario-itens`, commit f3febfa3). Nada foi editado, publicado ou gravado.
As consultas estão nesta pasta (`01-*.sql` a `42-*.sql`), com o resultado em `*.out`.

**Os números do cartão estavam desatualizados:**

| O cartão dizia | Medido hoje |
|---|---|
| Detector: "111 sugestões sem decisão" | **186** sem decisão (176 do WhatsApp + 10 da cobrança de saldo) |
| IA acompanha: "zero missões" | **5 missões** (1 de teste + 4 de 19/09), todas encerradas pelo dono, **0 mensagens enviadas** |
| IA acompanha: "teste de 30 dias termina ~14/10" | O recurso está **desligado desde 15/09 14:37** (horário de Brasília), cerca de 17 h depois de entrar no ar. O teste de 30 dias **não aconteceu**. |
| Ligações: "reavaliar ~26/09" | **Nunca foi construída.** Não há código nem tabela. Existe só o documento de avaliação de 26/07. |

---

## 1. Detector de sugestões da Agenda (`agenda-inbox-detector`)

### Estado hoje
- **Desligado.** O cron `agenda-inbox-detector` (jobid 16, `20 * * * *`) está com `active=false`.
  A última execução foi em **30/09 às 10:20** (horário de Brasília). Não existe a chave
  `agenda_detector_enabled` em `app_settings`, então a pausa depende **só** do cron. Se alguém
  religar o cron, o detector volta a rodar. O cursor não reprocessaria o acúmulo, porque o
  código tem um piso de 24 h.
- O sub-detector `promise` está desligado desde 09/09 (`agenda_detector_promise_enabled=false`).
- Ninguém cadastrou exclusões de contato (`agenda_detector_exclusions` está vazia).

### Uso real (tabela `agenda_suggestions`, 358 linhas desde 26/07)

| Mês | Criadas | Aceitas | Descartadas | Ainda pendentes |
|---|---|---|---|---|
| jul/26 | 77 | 22 | 55 | 0 |
| ago/26 | 162 | 32 | 63 | 67 |
| set/26 | 119 | 0 | 0 | 119 |

- **Todas as 172 decisões foram do dono, em apenas 6 dias:** 27/07, 28/07, 29/07, 03/08, 11/08
  e 15/08. **Não houve nenhuma decisão nas últimas 7 semanas.**
- **A taxa de aceite foi de 31%** (54 de 172). Contando só o WhatsApp, foi de 32% (49 de 153).
  A autonomia exigia 80%, então nunca chegou perto. O detector nunca criou tarefa sozinho
  (0 casos de `auto:autonomia`).
- Das 186 pendentes, **72 têm mais de 30 dias**, 134 têm mais de 14 dias e a mais antiga é de 12/08.
- Quem mais gerou sugestões foi `client_request`: 246 de 358, com aceite de 36%.
- As origens de captura por voz ou texto da própria Agenda (`voice_app`, ditado) foram usadas
  **0 vezes**. As 29 linhas com `manual_text` vêm todas da `balance-reminders` (cobrança de saldo
  vencido), que é outro produtor e continua ativo, com cron diário às 08:30.

### Valor (houve acerto?)
- **Houve.** As 54 sugestões aceitas viraram tarefas. **32 estão concluídas** (28 do WhatsApp).
  Exemplos: "Emitir NF de devolução final (NF 40.480)", "Encaixotar conversor e enviar para
  Tecnomaster", "Cobrar Rodrigo, saldo R$ 1.865,47" e "Entrega baterias, MH Rodrigo".
- **Ambíguo:** as conclusões foram marcadas em lote, em 3 momentos (8 em 29/07 às 11h, 4 em
  03/08 às 18h e 20 em 15/08 às 23h). Não dá para provar que foram feitas *por causa* do lembrete.
  Pode ter sido limpeza.
- **22 tarefas aceitas seguem abertas desde julho/agosto.** Exemplos: "DONNA V, entrega de itens
  faltantes Victron", "Gerar orçamento para Rodrigo (Starlink)" e "Enviar orçamento de baterias
  de lítio para o Nelson".
- O detector também alimentava os "fios soltos" de conversa (`entity_open_loops`,
  `source=conversation`). São 93 no total, mas só **2 fecharam por tarefa concluída**. Outros 25
  expiraram por inatividade e 3 fecharam porque a OS foi encerrada. **63 continuam abertos e
  parados**: a regra de 45 dias vai expirá-los sozinha até cerca de 13/11.

### Custo
- **Hoje: R$ 0 de IA**, porque o detector está pausado.
- **Quando estava ligado:** é uma **estimativa**, porque o detector chama o Haiku pelo OpenRouter e
  **não grava tokens no banco**. A `v_ai_custo_diario` só cobre o assistente. Pelo tráfego do
  WhatsApp, eram no máximo cerca de 540 chamadas em agosto e 350 em setembro, a ~US$ 0,005–0,008
  cada. Isso dá **US$ 2–4 por mês (R$ 10–20)**, compatível com os "~R$ 15/mês" anotados antes.
- **Custo de manutenção que continua mesmo pausado:**
  - **O resumo das 07:30 diz todo dia "📥 186 sugestão(ões) esperando sua decisão"**, inclusive
    depois da pausa (conferido em `whatsapp_send_queue`, enviado de 27/09 a 04/10). É ruído diário
    sem ação possível. O próprio dossiê da Agenda dizia que "notificação dispensada é pior que nenhuma".
  - A aba "Caixa de entrada" da Agenda mostra um contador que trava em 100 (a consulta tem `limit(100)`)
    e é atualizada a cada 2 minutos enquanto a Agenda está aberta.
  - Há cerca de 980 linhas de código entre o detector, a lógica compartilhada e os testes. Também há
    vínculos em fios soltos, nas ferramentas de aprendizado (`learning.ts`), no resumo diário e no
    `SuggestionCard`. Isso pesa pouco parado, mas precisa ser revisado quando o assistente ou o
    modelo mudam.

### Recomendação: **PAUSAR SEM APAGAR** (e tirar o ruído)
O detector acertou coisas reais, mas o hábito de decidir sugestões não pegou: houve 6 sessões de
decisão e depois 7 semanas de silêncio, com aceite de 31%. Religá-lo só faria a pilha crescer.
Apagar também não compensa, porque o código está ligado aos fios soltos e ao resumo diário, e
parado ele custa ~R$ 0. Além disso, o assistente já lê o histórico do WhatsApp sob demanda
(`get_whatsapp_conversation`), o que cobre boa parte da necessidade.

**O que seria feito (não fiz nada):**
1. Manter o cron 16 inativo e o código como está.
2. Tirar do resumo das 07:30 a linha "📥 N sugestões", ou fazê-la contar só as sugestões da
   cobrança de saldo.
3. Arquivar as 176 pendentes do WhatsApp com motivo "arquivada: detector pausado em 30/09",
   mudando o status para `dismissed`. Isso é escrita no banco e pede OK nomeado.
4. **Atenção:** **não** esconder a aba "Caixa de entrada" sem antes decidir o destino da
   `balance-reminders`, que continua gravando cobranças de saldo nela (10 pendentes). Esconder a
   aba esconderia essas cobranças também.
5. Volta a valer a pena se o dono quiser revisar a caixa pelo menos 1 vez por semana, por 4 semanas
   seguidas.

---

## 2. "Deixar a IA acompanhar" (`ai-followup-runner`, `ai_followup_missions` e eventos)

### Estado hoje
- **O interruptor está DESLIGADO:** `followup_missions_enabled=false`, com `updated_at` de
  **15/09 17:37 UTC (14:37 de Brasília)**. O recurso entrou no ar em 15/09 00:05 UTC, então ficou
  ligado cerca de 17 h. **Não há registro de quem desligou.** O painel grava a chave direto, sem
  auditoria. O mais provável é que tenha sido o dono, mas **não está provado**.
- **O cron continua rodando à toa:** `ai-followup-runner` (jobid 22, `15 * * * *`) está ativo.
  Foram 179 execuções desde 27/09 (o histórico do cron só guarda cerca de 7 dias), todas
  respondendo `skipped: kill_switch`. São cerca de 720 chamadas de função por mês sem efeito.
- O botão "Deixar a IA acompanhar" continua visível na tarefa e no orçamento, junto com o link
  "IA acompanhando" na Agenda e o painel `/v2/agenda/acompanhamentos`. As 3 ferramentas do
  assistente (`criar_`, `listar_` e `cancelar_missao_acompanhamento`) seguem no perfil.

### Uso real (todas as linhas desde o início)
| Missão | Criada | Rascunhos | Enviadas | Fim |
|---|---|---|---|---|
| Teste do dono (lead) | 15/09 | 1 (o "Toque 1/2") | 0 | rascunho **rejeitado**, missão encerrada pelo dono em 15/09 |
| ORÇ-00092 (Cliente Final) | 19/09 | 0 | 0 | encerrada pelo dono em 23/09 |
| Orçamento EQ-…06aa13 (Celio) | 19/09 | 0 | 0 | encerrada pelo dono em 23/09 |
| Orçamento EQ-…a7cc7c (Acrisio) | 19/09 | 0 | 0 | encerrada pelo dono em 23/09 |
| ORÇ-00083 (Robson) | 19/09 | 0 | 0 | encerrada pelo dono em 23/09 |

- **Nenhuma mensagem saiu para terceiros, nenhuma resposta chegou e nenhuma missão foi resolvida.**
- As 4 missões de 19/09 foram criadas **sem usuário logado** (`criada_por` nulo). Não houve
  conversa do assistente nem mensagem de WhatsApp naquele horário. **A origem é incerta**, e o
  provável é um teste técnico. Como o interruptor já estava desligado, elas nunca redigiram nada.
  O dono encerrou as 4 em 10 segundos, em 22/09 às 22:33.
- **O universo do recurso é pequeno:**
  - Hoje há 4 fios soltos do tipo "depende deles" abertos, e todos estão parados desde julho. Um
    deles é a OC-00001, que é de teste.
  - Há 4 orçamentos aguardando aprovação, dos quais só 2 estão parados há mais de 7 dias.
  - Em todos os fios já registrados, **139 são "nossos" contra 5 "deles"**. O gargalo é cumprir o
    que a HBR prometeu, não cobrar terceiros.

### Custo
- **IA: ~US$ 0,005 no total** (uma chamada de Haiku em 15/09). Hoje é zero.
- **Manutenção:** o cron roda 24 vezes por dia sem efeito. Há cerca de 1.700 linhas entre runner,
  ferramentas, UI, hook, migration e a cadência com testes, mais uma chamada RPC em **toda**
  mensagem recebida no `whatsapp-webhook` (`followup_registrar_resposta`, barata).
- As 3 ferramentas ocupam cerca de 500–700 tokens em cada chamada do assistente.
- **Risco silencioso:** com o interruptor desligado, o botão e a ferramenta do assistente
  **continuam criando missões** e respondem "a IA vai redigir o primeiro toque na próxima janela".
  **Isso é falso**: a missão fica zumbi. Foi exatamente o que aconteceu com as 4 de 19/09.

### Recomendação: **PAUSAR SEM APAGAR** (esconder e parar o cron)
O recurso nunca foi testado de verdade: ficou 17 h ligado, com 1 rascunho rejeitado e 0 envios.
Por isso não há dado para dizer que funciona, nem que não funciona. O caso de uso medido é raro:
são 2 orçamentos parados e nenhum fornecedor real "devendo" entrega. O assistente pelo WhatsApp
já consegue redigir uma cobrança quando o dono pede. Apagar seria jogar fora um trabalho pronto
e cuidadoso, com copiloto, teto, opt-out e janela de horário, que custa ~R$ 0 parado.

**O que seria feito (não fiz nada):**
1. Desativar o cron 22 (`cron.alter_job(22, active := false)`) e manter `followup_missions_enabled=false`.
2. Esconder o botão "Deixar a IA acompanhar" (tarefa e orçamento) e o link "IA acompanhando" da
   Agenda enquanto o interruptor estiver desligado.
3. Tirar as 3 ferramentas do perfil do assistente.
4. Alternativa mínima a 2 e 3: fazer a RPC `create_followup_mission` recusar a criação quando o
   interruptor estiver desligado. Isso elimina a missão zumbi.
5. Manter tabelas, código e painel.
6. **Esquecer a data de 14/10**, porque não há teste em curso. Volta a valer a pena se surgir um
   fornecedor real com entrega atrasada que o dono queira cobrar.

---

## 3. Transcrição de ligações telefônicas (D28)

### O que existe
- **Nada construído.** Não há tabela de chamadas, gravações ou transcrições, nem função, tela ou
  commit de implementação.
- Existe só o documento `plans/marineflow-transcricao-ligacoes-avaliacao.md` (26/07), que
  recomendava "não fazer agora" por três motivos: a LGPD exige aviso em toda ligação, gravar em
  celular é restrito e o custo seria de R$ 150–400/mês no caminho VoIP.
- O "Caminho A" que o documento recomendava no lugar (ditar um resumo de 20 s depois da ligação,
  pelo microfone da Agenda ou por `agenda-voice-capture`) **está pronto e foi usado 0 vezes**:
  nenhuma sugestão tem origem `voice_app`.
- **Não confundir** com `whatsapp-transcribe-audio`, que transcreve áudios do WhatsApp, está no ar
  e é usada pelo assistente. Ela não tem relação com ligações.
- O gatilho para reabrir era "perder 2 ou mais compromissos por semana combinados por telefone".
  **Ninguém mediu isso**, e não há nenhum registro de compromisso perdido por telefone.

### Custo
- **Zero** de IA, de cron e de código. O único custo é o cartão ocupar a atenção do dono.

### Recomendação: **APOSENTAR (arquivar a ideia)**
Não há nada ligado nem nada a manter. A alternativa gratuita que cobriria o mesmo problema nunca
foi usada, o que indica que capturar ligações não é uma dor sentida hoje.

**O que seria feito:** marcar a D28 como encerrada ("arquivada em 04/10; reabrir só se o dono
relatar compromisso perdido por telefone") e manter o documento em `plans/` como referência.
Não há nada para desligar.

---

## Pontos ambíguos (cautela)
1. O custo do detector é **estimado**, porque ele não registra tokens. A faixa é de R$ 10–20/mês
   quando ligado.
2. As 32 tarefas "concluídas" vindas de sugestões foram marcadas em lote. Não dá para provar que o
   lembrete gerou o trabalho.
3. Não há registro de **quem** desligou o "IA acompanha" em 15/09, nem de quem criou as 4 missões
   de 19/09.
4. `cron.job_run_details` só guarda cerca de 7 dias (desde 27/09). As datas anteriores vêm de
   `agenda_suggestions`, `ai_operator_audit` e `app_settings.updated_at`.
5. Uma consulta falhou uma vez por erro de login temporário da CLI, e repeti com sucesso.
   Nenhum dado ficou faltando.
