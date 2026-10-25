-- Agenda de Produção, Fase 3 ("A execução: equipe, diária, conclusão e telas"), pacote P4: a rotina da equipe e a diária
-- automática por caminho próprio.
-- Spec: scratchpad agenda-pesquisa/spec-fase3.md (§7, §3.1, §3.2, §3.3 d10–d16, §13.1–13.4). Decisões do dono 23/10 (Rotina
-- com a equipe). Depende da Fase 1 e da Fase 2 inteiras e de 20261026100000 (tabelas), 100100 (a porta completa e os
-- marcos) e 100200 (os caminhos da conclusão).
--
-- ═══ DDL — OK NOMEADO ═══ (funções novas e recriadas; 3 gatilhos novos: 2 em whatsapp_send_queue, só para
-- source = 'agenda-equipe', e 1 em agenda_acoes, só para tipo = 'diaria'; nenhuma tabela, nenhum dado)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- POR QUE: o dono pediu (23/10) que o gestor confirme a equipe na véspera e acompanhe o dia pelo WhatsApp do Roberto
-- (19:30 a ficha; 07:45 a confirmação, só sem o OK; silêncio até as 9h remaneja; 17:00 "como foi hoje?"), no máximo 2
-- mensagens por dia a cada técnico, e que a diária seja lançada quando a resposta do técnico (ou a conferência dele) e o
-- plano batem — por um caminho próprio, que nunca mexe em turno existente, soma os meios-dias, pula o dono e pergunta o
-- que diverge. O Roberto é uma pessoa de verdade: em setembro os técnicos receberam alerta à meia-noite e o dono mandou
-- desligar. Por isso tudo nasce atrás de dois modos separados (modo_equipe e modo_diaria), em sombra pela migration de
-- dado 20261026101000 (P7), e a janela e o teto valem no banco, não só no código.
--
-- O QUE MUDA:
--   1. A ficha e os textos à equipe (agenda_equipe_ficha e ajudantes): só o publicado, sem valor, sem número de OS, sem
--      cliente de outra pessoa, sem acesso; o dono é "o Gustavo".
--   2. O envio (_agenda_equipe_registrar + _agenda_equipe_enfileirar): sombra = só registrada (chave com ":sombra");
--      ligado = a lista da rotina, nunca domingo, a janela 07:30–20:00 de Brasília (com a última tentativa dentro), o
--      teto de 2 que o sistema começa (e 4 respostas) por pessoa e dia, o telefone, o wa_test_mode; depois a fila de
--      sempre (whatsapp_send_queue, source agenda-equipe, dedupe_key da mensagem).
--   3. A trava da fila no banco (_agenda_fila_da_equipe, gatilho em whatsapp_send_queue só para agenda-equipe): recusa a
--      linha fora da janela, no domingo, acima do teto ou sem a mensagem em ligado; a nova tentativa que cairia fora da
--      janela vira falha. E o passo "fila" da rotina (roda sempre, até com tudo desligado): o que não saiu dentro da janela
--      (worker parado) ou ficou na fila quando a equipe saiu de ligado vira falha — desligar vale para o que já estava na fila.
--   4. A resposta do técnico sem IA (_agenda_ler_resposta_da_equipe, gramática fixa) e agenda_resposta_da_equipe (o
--      whatsapp-webhook chama antes da confirmação do cliente e da conferência do recibo): "ok" confirma, "não vou"
--      remaneja, "o que tem pra amanhã" responde o publicado, o "como foi hoje?" vira resultado e diária. O recibo de
--      diárias mais novo fica com o "ok" (NOVO-agenda-17).
--   5. A diária automática (_agenda_confirmacao_do_dia, _agenda_diaria_do_dia, _agenda_lancar_diaria): só INSERT, só sem
--      turno no dia, a fração do plano, ligada às OS, assinada pelo login do dono, status aprovado (a regra de hoje), com
--      desfazer; divergência = a pergunta crítica diaria (_agenda_perguntar_diaria); turno igual sem OS = a pergunta de
--      ligar. O gatilho agenda_acoes_diaria_confirmada recusa a diária da agenda sem a confirmação batendo.
--   6. A palavra *diária <nome> inteira|meia|não [quando]* (agenda_diaria_dita), a decisão (_agenda_decidir_diaria, pela
--      agenda_decidir recriada), o desfazer (_agenda_desfazer_diaria, pela agenda_desfazer recriada) e a linha do "sim"
--      do registrar_diaria (agenda_diaria_da_agenda).
--   7. A rotina (agenda_rotina_rodar, 11 passos, cada um no seu bloco, uma linha em agenda_vigia_rodadas com rotina =
--      'rotina'), com os acordes no formato da vigia.
--   8. Recriadas (corpo da definição mais nova, mudanças marcadas -- FASE 3:): agenda_registrar_dia (via equipe, a diária
--      de cada diarista, a entrega conferida, a intervenção do dono), agenda_decidir (diaria), agenda_desfazer (diaria e a
--      ausência da equipe), _agenda_texto_do_acorde (quem já recebeu a ficha), agenda_saude (os blocos da execução e os
--      zeros obrigatórios) e agenda_rascunho_andamento (o "eu fui" do dono fora do plano).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase3_equipe_diarias.sql):
--   · "no pátio da HBR" pedia os_planejamento.local_tipo, que não existe (nem o dado). O lugar da ficha é a marina (da OS
--     ou do bem) ou a cidade do cliente; sem isso, a ficha não diz lugar.
--   · O replano do "não vou" e do silêncio vai com a origem vigia (a spec dizia 'equipe'): _agenda_propor_e_aplicar só
--     aceita motor/vigia/conferencia/dono, e a mudança é a agenda agindo sozinha (desfazível como a da vigia). A ação
--     'equipe' guarda a causa, a ausência e as ações do replano; desfazer o replano também tira a ausência do dia (senão a
--     vigia refaria o replano no tique seguinte).
--   · O acorde do "não vou" sai pela rotina (no tique seguinte, até 15 min): o webhook não manda nada ao dono.
--   · agenda_registrar_dia não ganhou parâmetro (a assinatura é conferida pelos testes da Fase 2): pela equipe, os turnos
--     confirmados vão em agenda.turnos_equipe, posto na mesma transação por agenda_resposta_da_equipe.
--   · "Não vou" respondido ao "como foi hoje?" ("não vou conseguir terminar") e "terminei" sem o dia não são lidos como
--     falta nem como o dia todo: viram a pergunta crítica da diária (dinheiro não se decide no chute).
--   · O silêncio só conta com a confirmação ENVIADA (a fila diz sent há 30 min ou mais) e sem NENHUMA mensagem dele
--     depois (whatsapp_messages): a resposta que o webhook não leu não vira falta.
--   · A entrega pendente (passo 10) só pergunta das OS concluídas pela porta da agenda: as 21 conclusões de antes da Fase 3
--     não têm a entrega (a coluna é nova) e virariam 21 perguntas de uma vez.
--   · A intervenção do dono grava a que a conversa sabe: sem alocação dele na OS no dia (prevista 'nenhuma', dita
--     'passou'). "Só abriu e ficou o dia" precisa do turno dito, que o rascunho não traz: fica para a Fase 6 (presença
--     aprendida), registrado.
--   · O que a rotina conclui (técnico disse que terminou, último dia) exige UMA OS dele no dia: com duas, ninguém sabe qual.
--
-- REVISÃO DA FASE 3 (C1 — equipe, palavras e fila; as marcas "(C1" no corpo):
--   · item 2: "não vou" com hora, atraso, turno ou "ficar" ("chego às 9", "vou atrasar", "não posso à tarde") é não
--     entendi — vai ao dono com o trecho e nada é remanejado; com terminar/acabar é sobre o serviço.
--   · item 3: o "não vou" ao "como foi hoje?" vale para o dia da ficha que ele levava (senão o próximo dia útil); o "como
--     foi" de hoje continua esperando a resposta de hoje (sem a pergunta da diária de hoje).
--   · item 7: o "ok" com turnos diferentes do plano ("ok, só de manhã") não confirma o dia: vai ao dono (equipe_resposta).
--   · item 8: o turno que já existe é QUALQUER turno do dia (também por hora, folga, atestado, feriado): a pergunta crítica.
--   · R5: o teto contado num lugar só (_agenda_equipe_no_dia, a função e a trava da fila); o 23514 da trava vira a recusa
--     da mensagem, sem desfazer o resto.
--   · NOVO-agenda-28: a resposta direta a uma mensagem do técnico sai na hora entre equipe_resposta_direta_inicio e _fim
--     (06:00–22:00, até 10 min depois, nunca no domingo); fora disso, no início da janela. A janela de uma tentativa é a
--     regra única _agenda_equipe_fora_da_janela (a função, a trava, o passo "fila" da rotina, a saúde; o worker tem a mesma).
--
-- O QUE NÃO MUDA: com modo_equipe e modo_diaria em 'desligado' (como nascem; produção hoje), a rotina devolve
-- {rodou: false}, a resposta da equipe {consumiu: false} e a diária {status: desligado}: nada é gravado e o webhook segue
-- exatamente como hoje. Em 'sombra' nada vai a ninguém e nenhuma diária é lançada: só as mensagens registradas e as ações
-- com executada = false. A conferência do dono (agenda_registrar_dia) só ganha texto quando a diária está fora de
-- desligado. Os gatilhos novos só disparam para source = 'agenda-equipe' (que ninguém usa hoje) e para tipo = 'diaria'.
--
-- ORDEM DE LIGAR: depois de 20261026100200; antes de publicar o task-automations (que chama agenda_rotina_rodar) e o
-- whatsapp-webhook (que chama agenda_resposta_da_equipe). Ligar a diária e a equipe é cada um um OK nomeado (§16).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase3_equipe_diarias.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261026100300
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261026100300_agenda_fase3_equipe_diarias.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261026100300', 'agenda_fase3_equipe_diarias');"
--
-- IDEMPOTENTE: só create or replace function, drop trigger if exists + create trigger, revoke/grant e comment.

-- ── 1. A equipe: quem é pelo telefone e o que a mensagem diz ────────────────────────────────────────────────

-- Os favorecidos da equipe com este telefone (os 8 últimos dígitos, como registrar_conferencia_do_freelancer): ativos e
-- na lista da rotina ou com diária vigente. O dono (sócio sem perfil de diária e fora da lista) nunca casa aqui.
create or replace function public._agenda_payees_do_telefone(p_phone text, p_hoje date default public._hoje_brt())
 returns uuid[]
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(array_agg(p.id order by p.id), '{}'::uuid[])
    from public.payees p
   where p.active
     and length(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g')) >= 8
     and length(regexp_replace(coalesce(p.phone, ''), '\D', '', 'g')) >= 8
     and right(regexp_replace(p.phone, '\D', '', 'g'), 8) = right(regexp_replace(p_phone, '\D', '', 'g'), 8)
     and (exists (select 1 from public.agenda_equipe_contato c where c.payee_id = p.id)
          or exists (select 1 from public.work_profiles w
                      where w.payee_id = p.id and w.modo_pagamento = 'diaria' and w.vigencia_inicio <= p_hoje
                        and (w.vigencia_fim is null or w.vigencia_fim >= p_hoje)));
$function$;

comment on function public._agenda_payees_do_telefone(text, date) is
  'Agenda de Produção (Fase 3, P4): os favorecidos da equipe com este telefone (8 últimos dígitos), ativos e na lista da rotina (agenda_equipe_contato) ou com diária vigente em p_hoje. Mais de um = ambíguo (quem chama registra e não lê).';

create or replace function public._agenda_payee_do_telefone(p_phone text, p_hoje date default public._hoje_brt())
 returns uuid
 language sql
 stable
 set search_path to 'public'
as $function$
  select case when cardinality(x.ids) = 1 then x.ids[1] end
    from (select public._agenda_payees_do_telefone(p_phone, p_hoje) as ids) x;
$function$;

comment on function public._agenda_payee_do_telefone(text, date) is
  'Agenda de Produção (Fase 3, P4): o favorecido da equipe deste telefone; null quando nenhum ou mais de um (ambíguo: a resposta não é lida).';

-- "na Marina de Itajaí" (a marina da OS ou a do bem), senão "em Itajaí" (a cidade do cliente), senão null.
-- CORREÇÃO SOBRE A SPEC: o "no pátio da HBR" pedia os_planejamento.local_tipo, que não existe (nem o dado): fica fora
-- até existir. O texto à equipe só diz o lugar que o banco sabe.
create or replace function public._agenda_local_da_os(p_os uuid)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce('na ' || nullif(btrim(m.name), ''), 'em ' || nullif(btrim(cl.city), ''))
    from public.service_orders so
    left join public.vessels vs on vs.id = so.vessel_id
    left join public.marinas m on m.id = coalesce(so.marina_id, vs.marina_id)
    left join public.clients cl on cl.id = so.client_id
   where so.id = p_os;
$function$;

comment on function public._agenda_local_da_os(uuid) is
  'Agenda de Produção (Fase 3, P4): onde é o serviço, para a ficha da equipe — "na <marina>" (da OS ou do bem), senão "em <cidade do cliente>", senão null. Sem pátio: o dado não existe.';

-- "no barco do Lenine", "no motorhome do Giancarlo"; sem bem, "no serviço do Lenine".
create or replace function public._agenda_bem_da_os(p_os uuid)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case
           when vs.id is null then 'no serviço'
           when public._agenda_normal(coalesce(vs.asset_type, '') || ' ' || coalesce(vs.name, '')) ~ 'motorhome|motor home'
             then 'no motorhome'
           when public._agenda_normal(coalesce(vs.asset_type, '') || ' ' || coalesce(vs.name, '')) ~ '\mtrailer\M' then 'no trailer'
           when public._agenda_normal(coalesce(vs.asset_type, '') || ' ' || coalesce(vs.name, '')) ~ '\mcamper\M' then 'no camper'
           else 'no barco' end
         || coalesce(' do ' || public._agenda_nome_curto(cl.name), '')
    from public.service_orders so
    left join public.vessels vs on vs.id = so.vessel_id
    left join public.clients cl on cl.id = so.client_id
   where so.id = p_os;
$function$;

comment on function public._agenda_bem_da_os(uuid) is
  'Agenda de Produção (Fase 3, P4): o bem da OS na voz da equipe — "no barco do Lenine", "no motorhome do Giancarlo" (trailer, camper); sem bem, "no serviço do <cliente>". Nunca o número da OS.';

-- As 2 primeiras linhas de serviço ("instalação de carregador DC-DC e proteções e revisão…"), até 60 caracteres.
create or replace function public._agenda_servico_curto(p_os uuid)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select nullif(public._agenda_corta(string_agg(x.nome, ' e ' order by x.ord), 60), '')
    from (select case when substr(btrim(s.name_snapshot), 2, 1) ~ '[a-zà-ÿ]'
                      then lower(left(btrim(s.name_snapshot), 1)) || substr(btrim(s.name_snapshot), 2)
                      else btrim(s.name_snapshot) end as nome,
                 row_number() over (order by s.created_at, s.id) as ord
            from public.service_order_services s
           where s.service_order_id = p_os and btrim(coalesce(s.name_snapshot, '')) <> '') x
   where x.ord <= 2;
$function$;

comment on function public._agenda_servico_curto(uuid) is
  'Agenda de Produção (Fase 3, P4): o serviço da ficha — os nomes das 2 primeiras linhas de serviço (a 1ª letra minúscula quando não é sigla), cortados em 60 caracteres; sem linha, null. Sem valor.';

-- O dia na voz da equipe: "hoje (ter 03/11)", "amanhã (qua 04/11)", "terça (03/11)".
create or replace function public._agenda_dia_da_equipe(p_dia date, p_hoje date)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case when p_dia = p_hoje then 'hoje (' || public._dia_curto(p_dia) || ')'
              when p_dia = p_hoje + 1 then 'amanhã (' || public._dia_curto(p_dia) || ')'
              else (array['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'])[extract(isodow from p_dia)::int]
                   || ' (' || to_char(p_dia, 'DD/MM') || ')' end;
$function$;

comment on function public._agenda_dia_da_equipe(date, date) is
  'Agenda de Produção (Fase 3, P4): o dia na mensagem à equipe — "hoje (ter 03/11)", "amanhã (qua 04/11)" ou o nome do dia ("terça (03/11)", a ficha de sexta para depois do feriado).';

-- "8h", "8h30", "13h" (a hora de Brasília).
create or replace function public._agenda_hora_curta(p timestamptz)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select to_char(p at time zone 'America/Sao_Paulo', 'FMHH24') || 'h'
         || case when extract(minute from p at time zone 'America/Sao_Paulo') = 0 then ''
                 else to_char(p at time zone 'America/Sao_Paulo', 'MI') end;
$function$;

comment on function public._agenda_hora_curta(timestamptz) is 'Agenda de Produção (Fase 3, P4): a hora em Brasília na voz da equipe — "8h", "8h30", "13h".';

-- A ficha de uma pessoa num dia: só o publicado (alocações vigentes sem reserva, com modo_proposta ligado), sem valor,
-- sem número de OS, sem cliente de outra pessoa e sem acesso. Os textos saem prontos.
create or replace function public.agenda_equipe_ficha(p_payee uuid, p_dia date, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  cf        public.agenda_config := public._agenda_cfg();
  v_nome    text;
  v_dono    uuid := public._agenda_dono(null);
  v_gustavo text;
  v_dia_txt text;
  v_ref     text;
  r         record;
  v_quem    text[];
  v_parte   text;
  v_partes  text[] := '{}';
  v_resp    text[] := '{}';
  v_conf    text[] := '{}';
  v_os      jsonb := '[]'::jsonb;
  v_m       boolean := false;
  v_t       boolean := false;
  v_serv    text;
  v_n       int := 0;
begin
  if p_payee is null or p_dia is null or p_hoje is null then
    raise exception 'Faltam a pessoa e o dia da ficha.' using errcode = '22023';
  end if;
  select public._agenda_nome_curto(p.name) into v_nome from public.payees p where p.id = p_payee;
  v_gustavo := coalesce('o ' || (select public._agenda_nome_curto(p.name) from public.payees p where p.id = v_dono), 'o responsável');
  v_dia_txt := public._agenda_dia_da_equipe(p_dia, p_hoje);
  v_ref := case when p_dia = p_hoje then 'hoje' when p_dia = p_hoje + 1 then 'amanhã' else v_dia_txt end;

  if cf.modo_proposta = 'ligado' then
    for r in
      select a.service_order_id as os, min(lower(a.periodo)) as ini, bool_or(a.turno = 'manha') as m, bool_or(a.turno = 'tarde') as t,
             array_agg(distinct a.turno) as turnos
        from public.agenda_alocacoes a
       where a.payee_id = p_payee and a.dia = p_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
       group by a.service_order_id
       order by 2, 1
    loop
      v_n := v_n + 1;
      v_m := v_m or r.m;
      v_t := v_t or r.t;
      -- com quem: as outras pessoas da mesma OS nos mesmos turnos (o dono pela abertura ou o fechamento também), "o X"
      v_quem := array(
        select 'o ' || x.nome
          from (select distinct on (b.payee_id) b.payee_id, public._agenda_nome_curto(py.name) as nome,
                       b.payee_id = v_dono or py.kind = 'socio' as dono
                  from public.agenda_alocacoes b join public.payees py on py.id = b.payee_id
                 where b.service_order_id = r.os and b.dia = p_dia and b.estado in ('publicada', 'fixada') and b.tipo <> 'reserva'
                   and b.payee_id <> p_payee and b.turno = any (r.turnos)) x
         order by x.dono desc, x.nome, x.payee_id);
      v_parte := public._agenda_hora_curta(r.ini) || ' ' || public._agenda_bem_da_os(r.os)
                 || coalesce(', ' || public._agenda_local_da_os(r.os), '')
                 || case when cardinality(v_quem) > 0 then ', com ' || public._agenda_lista(v_quem, null) else '' end;
      v_partes := v_partes || v_parte;
      v_resp := v_resp || (v_parte || ', ' || case when r.m and r.t then 'o dia todo' when r.m then 'só de manhã' else 'só à tarde' end);
      v_conf := v_conf || (coalesce(public._agenda_nome_curto((select cl.name from public.service_orders so
                                                                  join public.clients cl on cl.id = so.client_id where so.id = r.os)),
                                    'o serviço') || ' às ' || public._agenda_hora_curta(r.ini));
      v_os := v_os || jsonb_build_object('os', r.os, 'inicio', r.ini, 'manha', r.m, 'tarde', r.t);
    end loop;
  end if;

  if v_n = 0 then
    return jsonb_build_object('tem_plano', false, 'turnos', '[]'::jsonb, 'os', '[]'::jsonb,
      'texto_ficha', null, 'texto_confirmar', null, 'texto_curto', null, 'texto_como_foi', null,
      'texto_resposta', case
        when extract(isodow from p_dia) = 7 then public._agenda_maiuscula(v_ref) || ' é domingo: não tem serviço marcado.'
        when not public.agenda_dia_util(p_dia) then public._agenda_maiuscula(v_dia_txt) || ' não tem serviço marcado.'
        else format('Ainda não tenho o plano de %s. Vou ver com %s e te falo.', v_ref, v_gustavo) end);
  end if;

  v_serv := case when v_n = 1 then public._agenda_servico_curto((v_os -> 0 ->> 'os')::uuid) end;
  return jsonb_build_object(
    'tem_plano', true,
    'turnos', to_jsonb(array_remove(array[case when v_m then 'manha' end, case when v_t then 'tarde' end], null)),
    'os', v_os,
    'texto_ficha', format('%s, %s: %s.', v_nome, v_dia_txt, array_to_string(v_partes, '; '))
                   || coalesce(' Serviço: ' || v_serv || '.', '') || ' Responde OK se tá certo.',
    'texto_resposta', format('%s, %s: %s. Dúvida, fala com %s.', v_nome, v_dia_txt, array_to_string(v_resp, '; '), v_gustavo),
    'texto_confirmar', format('Bom dia, %s. Hoje é %s. Tá confirmado?', v_nome, public._agenda_lista(v_conf, null)),
    'texto_curto', format('%s: %s.', public._agenda_maiuscula(v_dia_txt), array_to_string(v_partes, '; ')),
    'texto_como_foi', 'Como foi hoje? ' || case when v_m and v_t then 'Ficou manhã e tarde?' when v_m then 'Ficou a manhã?'
                                                else 'Ficou a tarde?' end
                      || ' Terminou o previsto? Se foi tudo como o previsto, responde OK.');
end;
$function$;

comment on function public.agenda_equipe_ficha(uuid, date, date) is
  'Agenda de Produção (Fase 3, P4): a ficha de uma pessoa num dia, só do publicado (alocações vigentes sem reserva, com modo_proposta ligado; fora disso tem_plano = false) — {tem_plano, turnos, os[{os, inicio, manha, tarde}], texto_ficha ("Roberto, terça (03/11): 8h no barco do Vanderlei, com o Gustavo. Serviço: … Responde OK se tá certo."), texto_resposta (o "o que tem pra amanhã", com o turno; sem plano "Ainda não tenho o plano de amanhã. Vou ver com o Gustavo e te falo."; domingo "Amanhã é domingo: não tem serviço marcado."), texto_confirmar ("Bom dia, Roberto. Hoje é Vanderlei às 8h. Tá confirmado?"), texto_curto (a ficha que vai junto do "como foi hoje?") e texto_como_foi}. Nunca valor, número de OS, cliente de outra pessoa nem acesso. Só service_role.';

-- ── 2. O envio à equipe: modo, lista, domingo, janela, teto, telefone, modo de teste e a fila ──────────────

-- (Revisão da Fase 3, C1) A janela de UMA tentativa de envio à equipe — a regra única: o _agenda_equipe_enfileirar (a 1ª
-- tentativa e quantas cabem), o gatilho da fila (o INSERT e a nova tentativa), o passo "fila" da rotina e a saúde leem
-- daqui; o worker confere o mesmo na hora de mandar (whatsapp-queue-worker, _shared/agenda/janela-da-fila.ts). null = pode
-- sair; senão o motivo (domingo ou janela). Pode sair: nunca no domingo; no mesmo dia (Brasília) da hora marcada; dentro de
-- [equipe_janela_inicio, equipe_janela_fim) — ou, SÓ para a resposta direta a uma mensagem que o técnico acabou de mandar
-- (tipo resposta, NOVO-agenda-28), dentro de [equipe_resposta_direta_inicio, equipe_resposta_direta_fim), nunca antes da
-- hora marcada (a da mensagem dele) e só até equipe_resposta_direta_prazo depois dela.
create or replace function public._agenda_equipe_fora_da_janela(p_tipo text, p_marcada timestamptz, p_quando timestamptz)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf  public.agenda_config := public._agenda_cfg();
  v_q timestamp := p_quando at time zone 'America/Sao_Paulo';
begin
  if p_quando is null or p_marcada is null then
    return 'janela';
  end if;
  if extract(isodow from v_q) = 7 then
    return 'domingo';
  end if;
  if v_q::date <> (p_marcada at time zone 'America/Sao_Paulo')::date then
    return 'janela';
  end if;
  if v_q::time >= cf.equipe_janela_inicio and v_q::time < cf.equipe_janela_fim then
    return null;
  end if;
  if p_tipo = 'resposta' and v_q::time >= cf.equipe_resposta_direta_inicio and v_q::time < cf.equipe_resposta_direta_fim
     and p_quando >= p_marcada and p_quando <= p_marcada + cf.equipe_resposta_direta_prazo then
    return null;
  end if;
  return 'janela';
end;
$function$;

comment on function public._agenda_equipe_fora_da_janela(text, timestamptz, timestamptz) is
  'Agenda de Produção (Fase 3, revisão C1): a janela de uma tentativa de envio à equipe, a regra única do banco (o worker tem a mesma em _shared/agenda/janela-da-fila.ts) — null = pode sair; ''domingo''; ''janela''. Nunca domingo; o mesmo dia de Brasília da hora marcada; [equipe_janela_inicio, equipe_janela_fim); ou, só para tipo resposta (a resposta direta a uma mensagem do técnico, NOVO-agenda-28), [equipe_resposta_direta_inicio, equipe_resposta_direta_fim) entre a hora marcada e a hora marcada + equipe_resposta_direta_prazo.';

-- (C1, NOVO-agenda-28) Quando sai a resposta a uma mensagem que o técnico acabou de mandar: na hora (a resposta direta), se
-- a mensagem dele chegou entre equipe_resposta_direta_inicio e equipe_resposta_direta_fim de um dia que não é domingo;
-- senão no início da janela da equipe — no mesmo dia, se a janela ainda não começou e não é domingo; senão no do próximo
-- dia que não é domingo. O "não vou" das 06:40 tem o "Tá bom" na hora; o das 05:30, às 07:30; o das 23:00 de sábado, às
-- 07:30 de segunda.
create or replace function public._agenda_equipe_quando_responder(p_recebida timestamptz)
 returns timestamptz
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf  public.agenda_config := public._agenda_cfg();
  v_l timestamp := p_recebida at time zone 'America/Sao_Paulo';
  v_d date := (p_recebida at time zone 'America/Sao_Paulo')::date;
begin
  if extract(isodow from v_l) <> 7 and v_l::time >= cf.equipe_resposta_direta_inicio
     and v_l::time < cf.equipe_resposta_direta_fim then
    return p_recebida;
  end if;
  if extract(isodow from v_l) = 7 or v_l::time >= cf.equipe_janela_inicio then
    v_d := v_d + 1;
  end if;
  if extract(isodow from v_d) = 7 then
    v_d := v_d + 1;
  end if;
  return (v_d + cf.equipe_janela_inicio) at time zone 'America/Sao_Paulo';
end;
$function$;

comment on function public._agenda_equipe_quando_responder(timestamptz) is
  'Agenda de Produção (Fase 3, revisão C1 — NOVO-agenda-28): a hora de envio da resposta a uma mensagem do técnico — a própria hora dela entre equipe_resposta_direta_inicio e equipe_resposta_direta_fim (não domingo); senão o início da janela da equipe (equipe_janela_inicio) do mesmo dia, se ainda não chegou e não é domingo, ou do próximo dia que não é domingo.';

-- (C1, R5) Quantas mensagens à equipe da pessoa ENTRARAM na fila no dia (Brasília, pelo scheduled_for), das que o sistema
-- começa ou das respostas: a contagem única do teto. O _agenda_equipe_enfileirar e o gatilho da fila contam igual — a linha
-- que entrou conta em qualquer estado (saindo ou não), e o que nunca entrou (recusado antes) não conta. p_exceto = a
-- mensagem que está entrando.
create or replace function public._agenda_equipe_no_dia(p_payee uuid, p_dia date, p_resposta boolean, p_exceto uuid)
 returns integer
 language sql
 stable
 set search_path to 'public'
as $function$
  select count(*)::int
    from public.whatsapp_send_queue q join public.agenda_equipe_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-equipe' and q.source_ref_id is distinct from p_exceto and x.payee_id = p_payee
     and (x.tipo = 'resposta') = p_resposta
     and (q.scheduled_for at time zone 'America/Sao_Paulo')::date = p_dia;
$function$;

comment on function public._agenda_equipe_no_dia(uuid, date, boolean, uuid) is
  'Agenda de Produção (Fase 3, revisão C1 — R5): o teto do dia, contado num lugar só — as linhas de whatsapp_send_queue (source agenda-equipe, qualquer estado) das mensagens da pessoa no dia de Brasília do scheduled_for, das respostas (p_resposta) ou das que o sistema começa, sem p_exceto.';

-- Uma mensagem à equipe: decide se vai à fila (e marca enfileirada) ou fica registrada (sombra) ou recusada (o motivo).
-- A ordem é a da spec (§7.2). A janela vale para TODA tentativa: o max_attempts é cortado para a última (+5 min cada)
-- não passar do fim da janela; o gatilho da fila (abaixo) confere tudo de novo no INSERT.
create or replace function public._agenda_equipe_enfileirar(p_msg uuid)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  m       public.agenda_equipe_mensagens%rowtype;
  v_local timestamp;
  v_max   int;
  v_n     int;
  v_fone  text;
  v_teste boolean;
  v_fteste text;
  v_tent  int;
  v_fila  uuid;
  v_motivo text;
  v_det   text;
begin
  select * into m from public.agenda_equipe_mensagens where id = p_msg for update;
  if not found then
    raise exception 'Não encontrei essa mensagem da equipe.' using errcode = 'P0002';
  end if;
  -- já decidida (o tique seguinte não refaz)
  if m.estado <> 'registrada' then
    return jsonb_build_object('estado', m.estado, 'motivo', m.recusa_motivo, 'fila_id', m.fila_id);
  end if;
  -- 1. o modo: sombra (ou a mensagem nasceu em sombra) = só registrada
  if m.modo <> 'ligado' or cf.modo_equipe <> 'ligado' then
    return jsonb_build_object('estado', 'registrada', 'motivo', 'modo');
  end if;

  v_local := m.enviar_em at time zone 'America/Sao_Paulo';
  v_motivo := case
    -- 2. a lista da rotina (só a semente ou o dono põem; "para de mandar" tira)
    when not exists (select 1 from public.agenda_equipe_contato c
                      where c.payee_id = m.payee_id and c.recebe_rotina and c.parou_em is null) then 'parou'
    -- 3. domingo; 4. a janela em Brasília (a regra única; a resposta direta tem a dela — C1, NOVO-agenda-28)
    else public._agenda_equipe_fora_da_janela(m.tipo, m.enviar_em, m.enviar_em)
  end;
  -- 5. o teto do dia (pelo dia do envio): as que o sistema começa e as respostas, cada uma com o seu. (C1, R5) contado
  -- como o gatilho da fila conta (_agenda_equipe_no_dia): as duas contagens são a mesma
  if v_motivo is null then
    v_max := case when m.tipo = 'resposta' then cf.equipe_respostas_dia_max else cf.equipe_proativas_dia_max end;
    v_n := public._agenda_equipe_no_dia(m.payee_id, v_local::date, m.tipo = 'resposta', m.id);
    if v_n >= v_max then
      v_motivo := 'teto';
    end if;
  end if;
  -- 6. o telefone; 7. o modo de teste do WhatsApp vai para o número de teste (o mesmo desvio de
  -- pedir_confirmacao_do_agendamento); ligado sem número de teste = nada sai
  if v_motivo is null then
    select regexp_replace(coalesce(p.phone, ''), '\D', '', 'g') into v_fone from public.payees p where p.id = m.payee_id;
    if length(coalesce(v_fone, '')) in (10, 11) then
      v_fone := '55' || v_fone;
    end if;
    v_teste := coalesce((select s.value::text from public.app_settings s where s.key = 'wa_test_mode'), 'false') in ('true', '"true"');
    if v_teste then
      v_fteste := regexp_replace(coalesce((select s.value::text from public.app_settings s where s.key = 'wa_test_number'), ''),
                                 '\D', '', 'g');
      v_fone := nullif(v_fteste, '');
    end if;
    if length(coalesce(v_fone, '')) < 12 then
      v_motivo := 'sem_telefone';
    end if;
  end if;
  if v_motivo is not null then
    update public.agenda_equipe_mensagens set estado = 'recusada', recusa_motivo = v_motivo where id = m.id;
    return jsonb_build_object('estado', 'recusada', 'motivo', v_motivo);
  end if;

  -- 8. a fila: as tentativas (+5 min cada) que cabem na janela da mensagem (a regra única; a 1ª já cabe)
  v_tent := greatest(1, (select count(*)::int from generate_series(0, 2) k
                          where public._agenda_equipe_fora_da_janela(m.tipo, m.enviar_em,
                                                                      m.enviar_em + make_interval(mins => 5 * k)) is null));
  -- (C1, R5) a trava da fila (o gatilho) recusa com 23514 o que passaria da janela ou do teto: aqui isso vira a recusa da
  -- mensagem com o motivo, sem desfazer o que veio antes na mesma transação (a resposta lida, a ausência, o replano)
  begin
    insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id, priority, scheduled_for,
                                            max_attempts, dedupe_key)
    values (v_fone, m.texto, 'agenda-equipe', m.id, 3, m.enviar_em, v_tent, m.dedupe_key)
    on conflict do nothing
    returning id into v_fila;
  exception when sqlstate '23514' then
    get stacked diagnostics v_det = pg_exception_detail;
    v_motivo := case when v_det in ('teto', 'janela', 'domingo') then v_det else 'teto' end;
    update public.agenda_equipe_mensagens set estado = 'recusada', recusa_motivo = v_motivo where id = m.id;
    return jsonb_build_object('estado', 'recusada', 'motivo', v_motivo, 'pela_fila', true);
  end;
  if v_fila is null then
    -- a mesma chave já estava na fila (o gatilho de idempotência de produção devolve nada): é a mesma mensagem
    select q.id into v_fila from public.whatsapp_send_queue q where q.dedupe_key = m.dedupe_key;
  end if;
  update public.agenda_equipe_mensagens set estado = 'enfileirada', fila_id = v_fila where id = m.id;
  return jsonb_build_object('estado', 'enfileirada', 'fila_id', v_fila, 'teste', v_teste, 'tentativas', v_tent);
end;
$function$;

comment on function public._agenda_equipe_enfileirar(uuid) is
  'Agenda de Produção (Fase 3, P4; revisão C1): a decisão do envio de uma mensagem registrada à equipe, na ordem — modo_equipe fora de ligado (ou a mensagem em sombra) = fica registrada; fora de agenda_equipe_contato.recebe_rotina = recusada/parou; domingo e janela pela _agenda_equipe_fora_da_janela ([equipe_janela_inicio, equipe_janela_fim) de Brasília; a resposta direta, a dela); o teto do dia (equipe_proativas_dia_max para ficha/confirmar/como_foi, equipe_respostas_dia_max para as respostas, contado pela _agenda_equipe_no_dia, como o gatilho) = teto; sem telefone (ou wa_test_mode sem número de teste) = sem_telefone. Senão whatsapp_send_queue (source agenda-equipe, source_ref_id = a mensagem, dedupe_key da mensagem, max_attempts = as tentativas que cabem na janela) e enfileirada; o 23514 da trava da fila vira recusada com o motivo (o detail do gatilho), sem desfazer o que veio antes. Idempotente. Sem grant.';

-- Registra a mensagem no modo de agora (sombra: a chave termina em :sombra) e decide o envio. Desligado = nada.
create or replace function public._agenda_equipe_registrar(p_payee uuid, p_dia date, p_tipo text, p_texto text,
                                                           p_enviar_em timestamptz, p_leva_ficha_de date default null,
                                                           p_responde text default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  v_modo text;
  v_id   uuid;
  v_r    jsonb;
  v_enviar timestamptz;
begin
  if cf.modo_equipe = 'desligado' then
    return jsonb_build_object('criada', false, 'modo', 'desligado');
  end if;
  if p_tipo is null or p_tipo not in ('ficha', 'confirmar', 'como_foi', 'resposta') then
    raise exception 'Tipo de mensagem à equipe desconhecido: "%".', coalesce(p_tipo, '') using errcode = '22023';
  end if;
  if nullif(btrim(coalesce(p_texto, '')), '') is null then
    raise exception 'A mensagem à equipe veio sem texto.' using errcode = '22023';
  end if;
  v_modo := case when cf.modo_equipe = 'ligado' then 'ligado' else 'sombra' end;
  -- (C1, NOVO-agenda-28) a resposta a uma mensagem dele: na hora entre equipe_resposta_direta_inicio e _fim (fora do
  -- domingo); senão no início da janela da equipe (a mensagem registrada nunca muda: a hora entra certa)
  v_enviar := case when p_tipo = 'resposta' then public._agenda_equipe_quando_responder(p_enviar_em) else p_enviar_em end;
  insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, leva_ficha_de, modo, texto, enviar_em, dedupe_key,
                                              responde_wa_id, criada_em)
  values (p_payee, p_dia, p_tipo, p_leva_ficha_de, v_modo, left(p_texto, 600), v_enviar,
          case when p_tipo = 'resposta'
               then format('agenda-equipe:resposta:%s:%s', p_payee, coalesce(p_responde, md5(p_texto || p_enviar_em::text)))
               else format('agenda-equipe:%s:%s:%s', p_tipo, p_payee, p_dia) end
          || case when v_modo = 'sombra' then ':sombra' else '' end,
          case when p_tipo = 'resposta' then p_responde end, p_enviar_em)
  on conflict do nothing
  returning id into v_id;
  if v_id is null then
    return jsonb_build_object('criada', false, 'modo', v_modo, 'motivo', 'ja_existe');
  end if;
  v_r := public._agenda_equipe_enfileirar(v_id);
  return v_r || jsonb_build_object('criada', true, 'modo', v_modo, 'id', v_id);
end;
$function$;

comment on function public._agenda_equipe_registrar(uuid, date, text, text, timestamptz, date, text) is
  'Agenda de Produção (Fase 3, P4; revisão C1): grava a mensagem à equipe no modo de agora (desligado = nada; sombra = estado registrada e a chave agenda-equipe:<tipo>:<pessoa>:<dia> com ":sombra"; ligado = a chave sem sufixo, a mesma da fila) e chama _agenda_equipe_enfileirar. Uma por pessoa, dia, tipo e modo (as respostas pela mensagem dele). A resposta (NOVO-agenda-28) entra com a hora de _agenda_equipe_quando_responder: na hora, entre equipe_resposta_direta_inicio e _fim; senão no início da janela. Sem grant.';

-- A trava da fila no banco (a segunda, depois do _agenda_equipe_enfileirar): nada com source agenda-equipe entra na fila
-- sem a mensagem registrada em ligado, fora da janela (nenhuma tentativa depois do fim), no domingo ou acima do teto do
-- dia. É o que garante que um caminho novo (ou um defeito) não manda à equipe à meia-noite (setembro de 2026).
create or replace function public._agenda_fila_da_equipe()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  m       record;
  v_local timestamp;
  v_fora  text;
  v_max   int;
  v_n     int;
begin
  if tg_op = 'UPDATE' then
    -- a nova tentativa que o worker marca (+5 min) fora da janela da mensagem (ou com a equipe fora de ligado) não sai:
    -- falha. (C1) A janela é a regra única (_agenda_equipe_fora_da_janela): a resposta direta tem a dela e o prazo.
    select x.tipo, x.enviar_em into m from public.agenda_equipe_mensagens x where x.id = new.source_ref_id;
    if not found or cf.modo_equipe <> 'ligado'
       or public._agenda_equipe_fora_da_janela(m.tipo, m.enviar_em, new.scheduled_for) is not null then
      new.status := 'failed';
      new.failed_reason := 'agenda-equipe: a nova tentativa passaria do fim da janela';
    end if;
    return new;
  end if;
  select x.id, x.payee_id, x.tipo, x.modo, x.enviar_em, x.dedupe_key into m
    from public.agenda_equipe_mensagens x where x.id = new.source_ref_id;
  if not found or m.modo <> 'ligado' or cf.modo_equipe <> 'ligado' then
    raise exception 'A fila da equipe só aceita a mensagem registrada pela agenda com modo_equipe ligado.' using errcode = '42501';
  end if;
  v_local := new.scheduled_for at time zone 'America/Sao_Paulo';
  -- (C1) cada tentativa (+5 min) dentro da janela da mensagem, pela regra única; o motivo vai no detail (quem enfileira
  -- recusa a mensagem com ele)
  select t.f into v_fora
    from (select public._agenda_equipe_fora_da_janela(m.tipo, m.enviar_em, new.scheduled_for + make_interval(mins => 5 * k)) as f
            from generate_series(0, greatest(coalesce(new.max_attempts, 3) - 1, 0)) k) t
   where t.f is not null
   limit 1;
  if v_fora is not null then
    raise exception 'Mensagem à equipe fora da janela (% às %, nunca no domingo): %.',
      to_char(cf.equipe_janela_inicio, 'HH24:MI'), to_char(cf.equipe_janela_fim, 'HH24:MI'), to_char(v_local, 'DD/MM HH24:MI')
      using errcode = '23514', detail = v_fora;
  end if;
  v_max := case when m.tipo = 'resposta' then cf.equipe_respostas_dia_max else cf.equipe_proativas_dia_max end;
  -- (C1, R5) a mesma contagem do _agenda_equipe_enfileirar
  v_n := public._agenda_equipe_no_dia(m.payee_id, v_local::date, m.tipo = 'resposta', new.source_ref_id);
  if v_n >= v_max then
    raise exception 'Teto de mensagens à equipe no dia (%): não entra mais nenhuma.', v_max using errcode = '23514', detail = 'teto';
  end if;
  -- (C1, R7) a chave da linha é a da mensagem: o worker reconhece a resposta direta por ela (agenda-equipe:resposta:…)
  if new.dedupe_key is distinct from m.dedupe_key then
    raise exception 'A fila da equipe só aceita a mensagem com a chave dela.' using errcode = '42501';
  end if;
  return new;
end;
$function$;

comment on function public._agenda_fila_da_equipe() is
  'Agenda de Produção (Fase 3, P4; revisão C1): gatilho de whatsapp_send_queue só para source agenda-equipe. INSERT: recusa (23514/42501) a linha sem a mensagem registrada em ligado, com chave diferente da dela, com alguma tentativa fora da janela da mensagem (_agenda_equipe_fora_da_janela: a da equipe; a resposta direta, a dela), no domingo ou acima do teto do dia por pessoa (proativas e respostas, cada uma com o seu, pela _agenda_equipe_no_dia); o 23514 leva o motivo no detail (janela, domingo, teto). UPDATE com status pending: a nova tentativa que cairia fora da janela da mensagem (ou com modo_equipe fora de ligado) vira failed.';

drop trigger if exists trg_agenda_fila_da_equipe on public.whatsapp_send_queue;
create trigger trg_agenda_fila_da_equipe before insert on public.whatsapp_send_queue
  for each row when (new.source = 'agenda-equipe') execute function public._agenda_fila_da_equipe();
drop trigger if exists trg_agenda_fila_da_equipe_tentativa on public.whatsapp_send_queue;
create trigger trg_agenda_fila_da_equipe_tentativa before update of scheduled_for on public.whatsapp_send_queue
  for each row when (new.source = 'agenda-equipe' and new.status = 'pending' and new.scheduled_for is distinct from old.scheduled_for)
  execute function public._agenda_fila_da_equipe();

-- ── 3. A resposta da equipe, lida sem IA ────────────────────────────────────────────────────────────────────

-- A gramática fixa (spec §7.3), na ordem: pergunta → não vou → presença → turnos/terminou → ok → não entendi. Sem
-- acento, minúsculas, sem pontuação, espaços simples. Devolve {tipo, turnos, terminou, dia, ok}:
--   turnos: ["manha","tarde"] | ["manha"] | ["tarde"] | [] (não foi) | ["meio"] (meio dia, sem dizer qual) | null (não disse);
--   terminou: true | false | null; ok: a concordância junto ("ok, terminei").
-- Mais de um turno dito ao mesmo tempo ("só de manhã… o dia todo") = não entendi: a diária não se decide no chute.
create or replace function public._agenda_ler_resposta_da_equipe(p_texto text)
 returns jsonb
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  t       text := btrim(regexp_replace(regexp_replace(
                   translate(lower(coalesce(p_texto, '')), 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc'),
                   '[^a-z0-9 ]', ' ', 'g'), '\s+', ' ', 'g'));
  v_conc  boolean := public._e_concordancia(p_texto);
  v_ok    boolean;
  v_nada  boolean;
  v_dia   boolean;
  v_man   boolean;
  v_tar   boolean;
  v_meio  boolean;
  v_tsim  boolean;
  v_tnao  boolean;
  v_term  boolean;
  v_n     int;
begin
  if t = '' and not v_conc then
    return jsonb_build_object('tipo', 'nao_entendi', 'turnos', null, 'terminou', null, 'dia', null, 'ok', false);
  end if;
  -- 1. pergunta: "o que tem pra amanhã", "oque tem pra fazer amanha", "amanhã tem oq", "onde é amanhã"
  if t ~ '\m(o ?q(ue)?|oq|qual)( (e|tem|vai ser|vai ter|que tem))?( (pra|para))?( fazer)? (amanha|hoje)\M'
     or t ~ '\mamanha (tem|vai ter) (o que|oq|oque|servico)\M'
     or t ~ '\monde (e|vou|vai ser|sera) amanha\M' then
    return jsonb_build_object('tipo', 'pergunta', 'turnos', null, 'terminou', null,
                              'dia', case when t ~ '\mamanha\M' then 'amanha' else 'hoje' end, 'ok', false);
  end if;
  -- 2. não vou (o dia inteiro). (Revisão da Fase 3, C1 — item 2) Com hora, atraso, turno ou "ficar" é outra coisa ("não
  -- consigo chegar às 8, chego às 9", "vou atrasar", "não vou poder ficar a tarde", "não posso amanhã à tarde"): não
  -- entendi — vai ao dono com o trecho e nada é remanejado. Com terminar/acabar é sobre o serviço (segue para o 4).
  if t ~ '\mnao (vou|posso|consigo|vai dar|da)\M' or t ~ '^(hoje|amanha) nao\M'
     or t ~ '\m(to|estou|tou|fiquei) (doente|ruim|mal)\M' or t ~ '\m(hospital|atestado)\M' then
    if t ~ '\m(cheg[a-z]*|atras[a-z]*|cedo|manha|tarde|ficar|fico|almoco|metade|meio (dia|periodo))\M'
       or t ~ '\mas [0-9]' or t ~ '\m[0-9]+ ?(h|hs|hr|hrs|hora|horas)\M' then
      return jsonb_build_object('tipo', 'nao_entendi', 'turnos', null, 'terminou', null, 'dia', null, 'ok', false);
    end if;
    if t !~ '\m(termin|acab|finaliz)[a-z]*\M' then
      return jsonb_build_object('tipo', 'nao_vou', 'turnos', null, 'terminou', null, 'dia', null, 'ok', false);
    end if;
  end if;
  -- 3. presença (conta como confirmação: nunca é silêncio)
  if t ~ '\m(cheguei|ja cheguei|to na|to no|tou na|tou no|ja to|ja tou|ja estou|estou aqui|to aqui|to chegando|chegando|a caminho)\M' then
    return jsonb_build_object('tipo', 'presenca', 'turnos', null, 'terminou', null, 'dia', null, 'ok', false);
  end if;
  -- 4. turnos e se terminou
  v_nada := t ~ '\m(nao fui|faltei|nao trabalhei)\M' or t ~ '^(hoje )?nao deu( pra ir| para ir)?$';
  v_man := t ~ '\mso (de |pela |a )?manha\M' or t ~ '\mate (o )?meio dia\M';
  v_tar := t ~ '\mso (a |de |pela )?tarde\M';
  v_dia := t ~ '\m(dia (todo|inteiro)|manha e tarde|o dia)\M';
  v_meio := not v_man and not v_tar and t ~ '\mmeio (dia|periodo)\M';
  v_tnao := t ~ '\m(nao (terminei|terminou|terminamos|acabei|acabou|acabamos|finalizei|finalizou|deu (pra|para) terminar|ficou pronto|ficou pronta)|falta|faltou|faltam|amanha (termino|terminamos|continua|continuo|continuamos)|ainda nao)\M'
            -- (C1) "não dá pra terminar hoje", "não vou conseguir terminar": o serviço não terminou
            or t ~ '\mnao (da|vai dar|vou|consigo|vou conseguir)( (pra|para))? (terminar|acabar|finalizar)\M';
  v_tsim := t ~ '\m(terminei|terminou|terminamos|terminado|acabei|acabou|acabamos|finalizei|finalizou|finalizamos|ficou pronto|ficou pronta|ta pronto|esta pronto|tudo pronto|concluido|concluimos)\M';
  v_term := case when v_tnao then false when v_tsim then true end;
  v_ok := v_conc
          or (t ~ '^(ok|okay|beleza|blz|certo|tudo certo|tudo ok|tudo tranquilo|tranquilo|show|fechado|combinado|confirmado|confirmo|sim|pode deixar|perfeito|foi tudo (certo|bem|como o previsto)|tudo como (o )?previsto|como (o )?previsto)\M'
              and t !~ '^(ok|okay|beleza|blz|certo|sim) nao\M');
  v_n := v_nada::int + v_dia::int + v_man::int + v_tar::int + v_meio::int;
  if v_n > 1 then
    return jsonb_build_object('tipo', 'nao_entendi', 'turnos', null, 'terminou', v_term, 'dia', null, 'ok', v_ok);
  end if;
  if v_n = 1 or v_term is not null then
    return jsonb_build_object('tipo', 'turnos',
      'turnos', case when v_nada then '[]'::jsonb when v_dia then '["manha","tarde"]'::jsonb when v_man then '["manha"]'::jsonb
                     when v_tar then '["tarde"]'::jsonb when v_meio then '["meio"]'::jsonb end,
      'terminou', v_term, 'dia', null, 'ok', v_ok);
  end if;
  -- 5. ok (a lista de _e_concordancia, e o "ok"/"beleza" no começo)
  if v_ok then
    return jsonb_build_object('tipo', 'ok', 'turnos', null, 'terminou', null, 'dia', null, 'ok', true);
  end if;
  return jsonb_build_object('tipo', 'nao_entendi', 'turnos', null, 'terminou', null, 'dia', null, 'ok', false);
end;
$function$;

comment on function public._agenda_ler_resposta_da_equipe(text) is
  'Agenda de Produção (Fase 3, P4; revisão C1): a resposta do técnico pela gramática fixa (sem IA), na ordem: pergunta ("o que tem pra amanhã" → dia amanha/hoje) · nao_vou ("não vou", "hoje não", "tô doente"; com hora, atraso, turno ou "ficar" — "chego às 9", "vou atrasar", "não posso à tarde" — é nao_entendi, e com terminar/acabar é sobre o serviço) · presenca ("cheguei", "tô na…", "já tô") · turnos (dia todo/manhã e tarde → [manha, tarde]; só de manhã/até o meio dia → [manha]; só à tarde → [tarde]; não fui/faltei → []; meio dia → [meio]) com terminou (terminei/acabou/ficou pronto = true; não terminei/falta/ainda não = false) · ok (_e_concordancia, ou ok/beleza/certo no começo) · nao_entendi. Dois turnos ditos juntos = nao_entendi. {tipo, turnos, terminou, dia, ok}.';

-- Pergunta ao dono que nasce da equipe (não crítica), no modo da equipe.
create or replace function public._agenda_equipe_perguntar(p_tipo text, p_chave text, p_payee uuid, p_os uuid, p_dia date,
                                                           p_texto text, p_modo text, p_agora timestamptz,
                                                           p_opcoes jsonb default '[]'::jsonb, p_recomendacao smallint default null)
 returns boolean
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  v_id uuid;
begin
  if p_modo not in ('sombra', 'ligado') then
    return false;
  end if;
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, payee_id, dia, perda_em, texto, opcoes, recomendacao,
                                       modo, criada_em)
  values (p_tipo, left(p_chave, 200), p_os, case when p_os is null then '{}'::uuid[] else array[p_os] end, p_payee, p_dia, p_dia,
          left(public._agenda_corta(p_texto, 600), 600), coalesce(p_opcoes, '[]'::jsonb), p_recomendacao, p_modo, p_agora)
  on conflict (chave, modo) where estado = 'aberta' do nothing
  returning id into v_id;
  return v_id is not null;
end;
$function$;

comment on function public._agenda_equipe_perguntar(text, text, uuid, uuid, date, text, text, timestamptz, jsonb, smallint) is
  'Agenda de Produção (Fase 3, P4): uma pergunta não crítica ao dono que nasce da equipe (equipe_resposta, concluir, diaria_ligar), com a pessoa. Uma aberta por chave e modo. Sem grant.';

-- A mensagem do técnico que chega pelo WhatsApp (o número dele não é login de administrador).
create or replace function public.agenda_resposta_da_equipe(p_phone text, p_body text, p_message_id text,
                                                            p_recebida_em timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_hoje   date := (p_recebida_em at time zone 'America/Sao_Paulo')::date;
  v_hora   time := (p_recebida_em at time zone 'America/Sao_Paulo')::time;
  v_ids    uuid[];
  v_payee  uuid;
  v_nome   text;
  v_l      jsonb;
  v_tipo   text;
  m        public.agenda_equipe_mensagens%rowtype;
  v_recibo timestamptz;
  v_trecho text := left(btrim(coalesce(p_body, '')), 500);
  v_wa     text := nullif(btrim(coalesce(p_message_id, '')), '');
  v_dia    date;
  v_f      jsonb;
  v_r      jsonb;
  v_os     uuid[];
  v_disp   uuid;
  v_rep    jsonb;
  v_acao   uuid;
  v_plano  text[];
  v_ditos  text[];
  v_conf   text[];
  v_term   boolean;
  v_ent    boolean;
  v_estado text;
  v_msg    text;
  v_resp   text;
  v_div    boolean;
begin
  if v_trecho = '' or p_recebida_em is null then
    return jsonb_build_object('consumiu', false);
  end if;
  -- desligado: nada lê (o webhook segue como sempre)
  if cf.modo_equipe = 'desligado' then
    return jsonb_build_object('consumiu', false, 'modo', 'desligado');
  end if;
  v_ids := public._agenda_payees_do_telefone(p_phone, v_hoje);
  if cardinality(v_ids) > 1 then
    perform public.log_app_error('db', 'agenda: o telefone de uma mensagem é de mais de uma pessoa da equipe; não li a resposta',
                                 'agenda', 'equipe:telefone', 'warn', jsonb_build_object('payees', to_jsonb(v_ids)));
    return jsonb_build_object('consumiu', false, 'motivo', 'ambiguo');
  end if;
  if cardinality(v_ids) = 0 then
    return jsonb_build_object('consumiu', false);
  end if;
  v_payee := v_ids[1];
  v_nome := (select public._agenda_nome_curto(p.name) from public.payees p where p.id = v_payee);
  -- a mesma mensagem dele de novo: nada muda
  if v_wa is not null and exists (select 1 from public.agenda_equipe_mensagens x
                                   where x.payee_id = v_payee and (x.resposta_wa_id = v_wa or x.responde_wa_id = v_wa)) then
    return jsonb_build_object('consumiu', exists (select 1 from public.agenda_equipe_mensagens x
                                                   where x.payee_id = v_payee and x.modo = 'ligado'
                                                     and (x.resposta_wa_id = v_wa or x.responde_wa_id = v_wa)),
                              'repetida', true);
  end if;

  v_l := public._agenda_ler_resposta_da_equipe(p_body);
  v_tipo := v_l ->> 'tipo';
  -- a quem ele responde: a última que o sistema começou (ligado, enfileirada, dentro da validade)
  select * into m from public.agenda_equipe_mensagens x
   where x.payee_id = v_payee and x.tipo <> 'resposta' and x.modo = 'ligado' and x.estado = 'enfileirada'
     and x.enviar_em <= p_recebida_em and x.enviar_em >= p_recebida_em - cf.equipe_resposta_validade
   order by x.enviar_em desc, x.criada_em desc limit 1;
  -- o recibo das diárias mandado depois dela: o "ok" é do recibo (NOVO-agenda-17); a pergunta é sempre da agenda
  select max(a.enviado_ao_freelancer_em) into v_recibo
    from public.acertos_diarias a
   where a.favorecido_id = v_payee and a.status = 'fechado' and a.conferido_em is null
     and a.enviado_ao_freelancer_em > p_recebida_em - interval '7 days' and a.enviado_ao_freelancer_em <= p_recebida_em;
  if v_tipo <> 'pergunta' and v_recibo is not null and (m.id is null or v_recibo > m.enviar_em) then
    return jsonb_build_object('consumiu', false, 'motivo', 'recibo');
  end if;

  -- ── pergunta: a ficha do publicado, sem valores (em sombra só registra) ──────────────────────────────
  if v_tipo = 'pergunta' then
    v_dia := case when v_l ->> 'dia' = 'amanha' then v_hoje + 1 else v_hoje end;
    v_f := public.agenda_equipe_ficha(v_payee, v_dia, v_hoje);
    v_r := public._agenda_equipe_registrar(v_payee, v_dia, 'resposta', v_f ->> 'texto_resposta', p_recebida_em, null,
                                           coalesce(v_wa, md5(v_trecho || p_recebida_em::text)));
    if v_r ? 'id' then
      update public.agenda_equipe_mensagens
         set leitura = v_l || jsonb_build_object('pergunta', v_trecho, 'recebida_em', p_recebida_em)
       where id = (v_r ->> 'id')::uuid;
    end if;
    if not coalesce((v_f ->> 'tem_plano')::boolean, false) and public.agenda_dia_util(v_dia) then
      perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:pergunta', v_payee, v_dia), v_payee,
        null, v_dia, format('O %s perguntou o que tem %s e ainda não tem plano para ele. Diga a ele o que fazer.', v_nome,
                            case when v_dia = v_hoje then 'hoje' else 'amanhã (' || public._dia_curto(v_dia) || ')' end),
        case when cf.modo_equipe = 'ligado' then 'ligado' else 'sombra' end, p_recebida_em);
    end if;
    return jsonb_build_object('consumiu', cf.modo_equipe = 'ligado', 'tipo', v_tipo,
                              'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_f ->> 'texto_resposta' end,
                              'envio', v_r ->> 'estado');
  end if;

  -- ── não vou (à ficha ou à confirmação; sem nada pendente: hoje antes do meio-dia, senão o próximo dia útil) ─
  -- (Revisão C1, item 3) também ao "como foi hoje?": aí o dia é o da ficha que ele levava (senão o próximo dia útil), e o
  -- "como foi" de hoje continua esperando a resposta de hoje (não vira a pergunta da diária de hoje)
  if v_tipo = 'nao_vou' and (m.id is null or m.tipo in ('ficha', 'confirmar', 'como_foi')) then
    -- (antes do fim da manhã, hoje; depois, o próximo dia útil)
    v_dia := case when m.tipo = 'como_foi' then coalesce(m.leva_ficha_de, public.agenda_somar_du(m.dia, 1))
                  else coalesce(m.dia, case when v_hora < cf.manha_fim then v_hoje else public.agenda_somar_du(v_hoje, 1) end) end;
    v_os := array(select distinct a.service_order_id from public.agenda_alocacoes a
                   where a.payee_id = v_payee and a.dia = v_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                   order by 1);
    if cf.modo_equipe <> 'ligado' then
      -- em sombra nada muda: só o que faria
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
      values (clock_timestamp(), v_hoje, false, 'equipe', 'equipe', v_os[1], v_os, v_payee,
              jsonb_build_object('motivo', 'nao_vou', 'dia', v_dia, 'trecho', v_trecho),
              left(format('Em teste: o %s avisou que não vem %s; eu tiraria ele do plano desse dia.', v_nome,
                          public._agenda_dia_ref(v_dia, v_hoje)), 400));
      return jsonb_build_object('consumiu', false, 'tipo', v_tipo, 'modo', 'sombra');
    end if;
    perform set_config('agenda.hoje', v_hoje::text, true);
    if not exists (select 1 from public.agenda_disponibilidade d
                    where d.payee_id = v_payee and d.substituida_em is null and d.situacao = 'indisponivel'
                      and d.turno is null and d.periodo @> v_dia) then
      insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, trecho, criado_em)
      values (v_payee, daterange(v_dia, v_dia, '[]'), 'indisponivel', 'diarista', left('Avisou que não vem: ' || v_trecho, 200),
              left(v_trecho, 300), p_recebida_em)
      returning id into v_disp;
    end if;
    if cf.modo_proposta = 'ligado' and cardinality(v_os) > 0 then
      begin
        v_rep := public.agenda_replanejar(v_os, 'equipe_faltou', 'vigia', v_hoje, p_recebida_em, null);
      exception when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        perform public.log_app_error('db', 'agenda: replanejar depois do "não vou" da equipe falhou: ' || v_msg, 'agenda',
                                     'equipe:replanejar', 'error',
                                     jsonb_build_object('os', to_jsonb(v_os), 'sqlstate', v_estado, 'payee', v_payee));
      end;
    end if;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
    values (clock_timestamp(), v_hoje, true, 'equipe', 'equipe', v_os[1], v_os, v_payee,
            jsonb_build_object('motivo', 'nao_vou', 'dia', v_dia, 'trecho', v_trecho, 'disponibilidade', v_disp,
                               'mensagem', m.id, 'replano_acoes', coalesce(v_rep -> 'acoes', '[]'::jsonb),
                               'acorde', v_dia <= public.agenda_somar_du(v_hoje, cf.congelamento_du)),
            left(format('O %s avisou que não vem %s.', v_nome, public._agenda_dia_da_equipe(v_dia, v_hoje))
                 || coalesce(' ' || nullif(v_rep ->> 'texto', ''), ''), 400))
    returning id into v_acao;
    -- (C1, item 3) o "como foi" de hoje não é respondido pelo "não vou" de amanhã: ele segue esperando a resposta de hoje
    if m.id is not null and m.tipo <> 'como_foi' then
      update public.agenda_equipe_mensagens
         set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa, leitura = v_l,
             acao_id = v_acao
       where id = m.id;
    end if;
    v_resp := format('Tá bom, aviso %s.', coalesce('o ' || (select public._agenda_nome_curto(p.name) from public.payees p
                                                              where p.id = public._agenda_dono(null)), 'o responsável'));
    v_r := public._agenda_equipe_registrar(v_payee, v_dia, 'resposta', v_resp, p_recebida_em, null,
                                           coalesce(v_wa, md5(v_trecho || p_recebida_em::text)));
    return jsonb_build_object('consumiu', true, 'tipo', v_tipo, 'acao_id', v_acao, 'dia', v_dia,
                              'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_resp end, 'envio', v_r ->> 'estado');
  end if;

  -- Daqui em diante só a resposta a uma mensagem que o sistema mandou.
  if m.id is null then
    return jsonb_build_object('consumiu', false, 'tipo', v_tipo);
  end if;

  -- ── à ficha ou à confirmação ────────────────────────────────────────────────────────────────────────
  if m.tipo in ('ficha', 'confirmar') then
    -- (Revisão C1, item 7) o "ok" com os turnos ditos diferentes do plano ("ok, só de manhã" com o dia todo no plano) não
    -- confirma o dia: vai ao dono, como o não entendido (com o plano no texto)
    v_plano := array(select distinct a.turno from public.agenda_alocacoes a
                      where a.payee_id = v_payee and a.dia = m.dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                      order by 1);
    v_ditos := case when jsonb_typeof(v_l -> 'turnos') = 'array'
                    then array(select x from jsonb_array_elements_text(v_l -> 'turnos') x order by 1) end;
    v_div := v_tipo = 'turnos' and v_ditos is not null
             and not (v_ditos = v_plano or (v_ditos = array['meio'] and cardinality(v_plano) = 1));
    if not v_div
       and (v_tipo in ('ok', 'presenca') or (v_tipo = 'turnos' and coalesce((v_l ->> 'ok')::boolean, false))) then
      if not exists (select 1 from public.agenda_disponibilidade d
                      where d.payee_id = v_payee and d.substituida_em is null and d.situacao = 'confirmada'
                        and d.turno is null and d.periodo @> m.dia) then
        insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, trecho, criado_em)
        values (v_payee, daterange(m.dia, m.dia, '[]'), 'confirmada', 'diarista',
                left(case m.tipo when 'ficha' then 'Confirmou a ficha: ' else 'Confirmou de manhã: ' end || v_trecho, 200),
                left(v_trecho, 300), p_recebida_em);
      end if;
    else
      -- não entendi (ou turnos sem ok): vai ao dono com o trecho, e nada muda (nem remaneja: não é silêncio)
      perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:%s', v_payee, m.dia, m.tipo), v_payee,
        null, m.dia, format('O %s respondeu "%s" à %s de %s', v_nome, public._agenda_corta(v_trecho, 120),
                            case m.tipo when 'ficha' then 'ficha' else 'confirmação' end, public._dia_curto(m.dia))
                     || case when v_div
                             then ', e o plano é ' || case when v_plano = array['manha', 'tarde'] then 'o dia todo'
                                                           when v_plano = array['manha'] then 'a manhã'
                                                           when v_plano = array['tarde'] then 'a tarde'
                                                           else 'sem nada para ele' end || '.'
                             else '.' end,
        'ligado', p_recebida_em);
    end if;
    update public.agenda_equipe_mensagens
       set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa, leitura = v_l
     where id = m.id;
    return jsonb_build_object('consumiu', true, 'tipo', v_tipo, 'resposta', null);
  end if;

  -- ── ao "como foi hoje?" ─────────────────────────────────────────────────────────────────────────────
  v_plano := array(select distinct a.turno from public.agenda_alocacoes a
                    where a.payee_id = v_payee and a.dia = m.dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                    order by 1);
  v_ent := true;
  if v_tipo = 'ok' or (v_tipo = 'turnos' and v_l -> 'turnos' = 'null'::jsonb and coalesce((v_l ->> 'ok')::boolean, false)) then
    -- "ok" = tudo como o previsto: os turnos do plano e terminou (salvo "ok, mas não terminei")
    v_ditos := v_plano;
    v_term := coalesce((v_l ->> 'terminou')::boolean, true);
  elsif v_tipo = 'turnos' and jsonb_typeof(v_l -> 'turnos') = 'array' then
    v_ditos := array(select x from jsonb_array_elements_text(v_l -> 'turnos') x order by 1);
    v_term := (v_l ->> 'terminou')::boolean;
  else
    -- não entendi, "terminei" sem o dia, "não vou"/presença fora de hora: a diária vira pergunta (crítica)
    v_ent := false;
    v_ditos := null;
    v_term := (v_l ->> 'terminou')::boolean;
  end if;
  update public.agenda_equipe_mensagens
     set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa,
         leitura = v_l || jsonb_build_object('entendeu', v_ent, 'turnos_lidos', to_jsonb(v_ditos), 'turnos_plano', to_jsonb(v_plano),
                                             'terminou', v_term)
   where id = m.id;
  if v_ent then
    v_conf := array(select x from unnest(v_ditos) x where x = any (v_plano) order by 1);
    perform set_config('agenda.hoje', v_hoje::text, true);
    begin
      if cardinality(v_conf) > 0 then
        -- os turnos que ele confirmou viram resultado (via equipe), e a diária é decidida em seguida
        perform set_config('agenda.turnos_equipe', array_to_string(v_conf, ','), true);
        v_r := public.agenda_registrar_dia(null, m.dia, 'cumprido', null, null, array[v_payee], 'equipe', v_trecho, v_hoje,
                                           p_recebida_em, null);
        perform set_config('agenda.turnos_equipe', '', true);
      elsif v_ditos = '{}'::text[] then
        v_r := public.agenda_registrar_dia(null, m.dia, 'nao_cumprido', 'equipe', null, array[v_payee], 'equipe', v_trecho, v_hoje,
                                           p_recebida_em, null);
      end if;
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      perform set_config('agenda.turnos_equipe', '', true);
      perform public.log_app_error('db', 'agenda: anotar o dia pela resposta da equipe falhou: ' || v_msg, 'agenda',
                                   'equipe:dia', 'error', jsonb_build_object('payee', v_payee, 'dia', m.dia, 'sqlstate', v_estado));
    end;
    -- o "ok" ao "como foi" que levava a ficha de amanhã confirma amanhã também — (C1, item 3) salvo se ele já disse que
    -- não vem amanhã (o "ok" depois do "amanhã não vou" é sobre hoje)
    if v_tipo = 'ok' and m.leva_ficha_de is not null
       and not exists (select 1 from public.agenda_disponibilidade d
                        where d.payee_id = v_payee and d.substituida_em is null and d.situacao in ('confirmada', 'indisponivel')
                          and d.turno is null and d.periodo @> m.leva_ficha_de) then
      insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, trecho, criado_em)
      values (v_payee, daterange(m.leva_ficha_de, m.leva_ficha_de, '[]'), 'confirmada', 'diarista',
              left('Confirmou a ficha junto do "como foi": ' || v_trecho, 200), left(v_trecho, 300), p_recebida_em);
    end if;
  end if;
  -- a diária do dia (idempotente: o agenda_registrar_dia já a chamou quando anotou)
  begin
    v_r := public._agenda_diaria_do_dia(v_payee, m.dia, 'equipe', v_hoje, p_recebida_em);
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    perform public.log_app_error('db', 'agenda: a diária pela resposta da equipe falhou: ' || v_msg, 'agenda', 'equipe:diaria',
                                 'error', jsonb_build_object('payee', v_payee, 'dia', m.dia, 'sqlstate', v_estado));
  end;
  return jsonb_build_object('consumiu', true, 'tipo', v_tipo, 'entendeu', v_ent, 'resposta', null, 'diaria', v_r ->> 'status');
end;
$function$;

comment on function public.agenda_resposta_da_equipe(text, text, text, timestamptz) is
  'Agenda de Produção (Fase 3, P4): a mensagem do técnico (número que não é login de admin), chamada pelo whatsapp-webhook antes da confirmação do cliente e da conferência do recibo. modo_equipe desligado, telefone de ninguém da equipe (ou de dois) = {consumiu: false}. A mesma mensagem (p_message_id) de novo = nada muda. Lida por _agenda_ler_resposta_da_equipe. Decide a última mensagem que o sistema mandou (ligado, enfileirada, dentro de equipe_resposta_validade); o recibo de diárias mandado depois dela fica com o "ok" (NOVO-agenda-17: consumiu false). pergunta → a ficha do publicado (agenda_equipe_ficha.texto_resposta) como resposta enfileirada (sem plano: a pergunta equipe_resposta ao dono); em sombra só registra (consumiu false). nao_vou → indisponível no dia (agenda_disponibilidade origem diarista), replano (modo_proposta ligado, origem vigia), ação equipe com o acorde para a rotina e "Tá bom, aviso o Gustavo."; em sombra só a ação executada = false. ok/presença à ficha ou à confirmação → confirmada, sem resposta; não entendido → equipe_resposta ao dono, sem remanejo. Ao "como foi hoje?": ok = os turnos do plano e terminou; os turnos ditos viram resultado (agenda_registrar_dia via equipe, só os turnos confirmados) e a diária (_agenda_diaria_do_dia); não entendido = a pergunta crítica da diária. Sem pendente (ok, turnos, presença, não entendi) = consumiu false. {consumiu, tipo, resposta, acao_id}. Só service_role.';

-- ── 4. A diária automática, por caminho próprio (nunca pelo registrar_diaria de hoje, salvo a decisão do dono) ─

-- A confirmação do dia de uma pessoa (a regra única: a diária automática, o gatilho e a saúde leem daqui):
--   (i) a resposta dela ao "como foi hoje?" daquele dia, entendida (fonte equipe, os turnos lidos);
--   (ii) senão, o resultado humano (dia feito, conversa, tela, equipe) de TODAS as alocações dela no dia: algum parcial =
--        divergente; todos não cumpridos = não foi; os cumpridos = os turnos confirmados (fonte conferencia);
--   (iii) senão aguardando (ninguém confirmou: a linha "dia" do fechamento pergunta).
-- {estado: confirmada | divergente | nao_foi | aguardando | sem_plano, fonte, turnos, plano, os, quando, trecho, mensagem}.
create or replace function public._agenda_confirmacao_do_dia(p_payee uuid, p_dia date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_plano text[];
  v_os    uuid[];
  m       record;
  v_n     int;
  v_hum   int;
  v_parc  int;
  v_nao   int;
  v_turn  text[];
begin
  select coalesce(array_agg(distinct a.turno order by a.turno), '{}'), coalesce(array_agg(distinct a.service_order_id order by a.service_order_id), '{}'),
         count(*)
    into v_plano, v_os, v_n
    from public.agenda_alocacoes a
   where a.payee_id = p_payee and a.dia = p_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva';
  if v_n = 0 then
    return jsonb_build_object('estado', 'sem_plano', 'plano', '[]'::jsonb, 'os', '[]'::jsonb);
  end if;
  -- (i) a resposta ao "como foi hoje?"
  select x.id, x.leitura, x.resposta_em, x.resposta_texto into m
    from public.agenda_equipe_mensagens x
   where x.payee_id = p_payee and x.dia = p_dia and x.tipo = 'como_foi' and x.modo = 'ligado' and x.leitura is not null
   order by x.resposta_em desc nulls last, x.criada_em desc limit 1;
  if found then
    if coalesce((m.leitura ->> 'entendeu')::boolean, false) and jsonb_typeof(m.leitura -> 'turnos_lidos') = 'array' then
      v_turn := array(select t from jsonb_array_elements_text(m.leitura -> 'turnos_lidos') t order by 1);
      return jsonb_build_object('estado',
               case when v_turn = v_plano or (v_turn = array['meio'] and cardinality(v_plano) = 1) then 'confirmada'
                    else 'divergente' end,
               'fonte', 'equipe', 'turnos', to_jsonb(v_turn), 'plano', to_jsonb(v_plano), 'os', to_jsonb(v_os),
               'quando', m.resposta_em, 'trecho', m.resposta_texto, 'mensagem', m.id);
    end if;
    return jsonb_build_object('estado', 'divergente', 'fonte', 'equipe', 'turnos', null, 'entendeu', false,
                              'plano', to_jsonb(v_plano), 'os', to_jsonb(v_os), 'quando', m.resposta_em, 'trecho', m.resposta_texto,
                              'mensagem', m.id);
  end if;
  -- (ii) o resultado humano de todas as alocações dela no dia
  select count(*) filter (where a.resultado is not null and a.resultado_via in ('dia_feito', 'conversa', 'tela', 'equipe')),
         count(*) filter (where a.resultado = 'parcial'),
         count(*) filter (where a.resultado = 'nao_cumprido')
    into v_hum, v_parc, v_nao
    from public.agenda_alocacoes a
   where a.payee_id = p_payee and a.dia = p_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva';
  if v_hum = v_n then
    if v_parc > 0 then
      return jsonb_build_object('estado', 'divergente', 'fonte', 'conferencia', 'turnos', null, 'plano', to_jsonb(v_plano),
                                'os', to_jsonb(v_os), 'motivo', 'parcial');
    end if;
    if v_nao = v_n then
      return jsonb_build_object('estado', 'nao_foi', 'fonte', 'conferencia', 'turnos', '[]'::jsonb, 'plano', to_jsonb(v_plano),
                                'os', to_jsonb(v_os));
    end if;
    v_turn := array(select distinct a.turno from public.agenda_alocacoes a
                     where a.payee_id = p_payee and a.dia = p_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                       and a.resultado = 'cumprido' order by 1);
    return jsonb_build_object('estado', case when v_turn = v_plano then 'confirmada' else 'divergente' end, 'fonte', 'conferencia',
                              'turnos', to_jsonb(v_turn), 'plano', to_jsonb(v_plano),
                              'os', to_jsonb(array(select distinct a.service_order_id from public.agenda_alocacoes a
                                                    where a.payee_id = p_payee and a.dia = p_dia and a.estado in ('publicada', 'fixada')
                                                      and a.tipo <> 'reserva' and a.resultado = 'cumprido' order by 1)),
                              'quando', (select max(a.resultado_em) from public.agenda_alocacoes a
                                          where a.payee_id = p_payee and a.dia = p_dia and a.estado in ('publicada', 'fixada')
                                            and a.tipo <> 'reserva'));
  end if;
  return jsonb_build_object('estado', 'aguardando', 'plano', to_jsonb(v_plano), 'os', to_jsonb(v_os));
end;
$function$;

comment on function public._agenda_confirmacao_do_dia(uuid, date) is
  'Agenda de Produção (Fase 3, P4): a confirmação do dia de uma pessoa, regra única da diária automática — (i) a resposta dela ao "como foi hoje?" entendida (fonte equipe; os turnos lidos = o plano → confirmada, senão divergente; não entendida → divergente); (ii) senão o resultado humano (dia_feito, conversa, tela, equipe) de todas as alocações do dia (algum parcial → divergente; todas não cumpridas → nao_foi; os cumpridos = o plano → confirmada); (iii) senão aguardando. Sem alocação → sem_plano. {estado, fonte, turnos, plano, os, quando, trecho, mensagem}.';

-- O gatilho: diária lançada pela agenda sem decisão do dono só existe com a confirmação batendo. A agenda nunca lança
-- dinheiro por inferência; a métrica agenda_saude.diarias.sem_confirmacao confere o mesmo depois do fato.
create or replace function public._agenda_acoes_diaria_confirmada()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  if new.tipo = 'diaria' and new.executada and not new.critica and new.origem <> 'dono'
     and coalesce(public._agenda_confirmacao_do_dia(new.payee_id, (new.depois ->> 'dia')::date) ->> 'estado', '') <> 'confirmada' then
    raise exception 'Diária sem confirmação: a agenda só lança quando o técnico ou você confirmam o dia como estava no plano.'
      using errcode = '23514';
  end if;
  return new;
end;
$function$;

comment on function public._agenda_acoes_diaria_confirmada() is
  'Agenda de Produção (Fase 3, P4): gatilho BEFORE INSERT de agenda_acoes — a ação diaria executada, não crítica e que não é do dono só entra com _agenda_confirmacao_do_dia = confirmada (23514 senão).';

drop trigger if exists agenda_acoes_diaria_confirmada on public.agenda_acoes;
create trigger agenda_acoes_diaria_confirmada before insert on public.agenda_acoes
  for each row when (new.tipo = 'diaria') execute function public._agenda_acoes_diaria_confirmada();

-- A pergunta crítica da diária (a que diverge, a do turno que já existe, a do acerto fechado, a sem o login do dono).
create or replace function public._agenda_perguntar_diaria(p_payee uuid, p_dia date, p_motivo text, p_conf jsonb, p_os uuid[],
                                                           p_hoje date, p_agora timestamptz, p_turno jsonb default null)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_modo  text := case when cf.modo_diaria = 'ligado' then 'ligado' else 'sombra' end;
  v_nome  text := (select public._agenda_nome_curto(p.name) from public.payees p where p.id = p_payee);
  v_valor numeric := (select w.valor_diaria from public.work_profiles w
                       where w.payee_id = p_payee and w.modo_pagamento = 'diaria' and w.vigencia_inicio <= p_dia
                         and (w.vigencia_fim is null or w.vigencia_fim >= p_dia)
                       order by w.vigencia_inicio desc limit 1);
  v_oss   text := public._agenda_lista(array(select public._agenda_rotulo_da_os(x) from unnest(p_os) x order by 1), null);
  v_dito  int := case when jsonb_typeof(p_conf -> 'turnos') = 'array'
                      then case when p_conf -> 'turnos' = '["meio"]'::jsonb then 1 else jsonb_array_length(p_conf -> 'turnos') end end;
  v_plano int := jsonb_array_length(coalesce(p_conf -> 'plano', '[]'::jsonb));
  v_rec   smallint;
  v_opc   jsonb;
  v_txt   text;
  v_rtxt  text;
  v_id    uuid;
  v_trecho text := public._agenda_corta(coalesce(p_conf ->> 'trecho', ''), 120);
  -- (revisão C1, item 8) o turno que existe sem fração (por hora, folga, atestado, feriado): não é diária
  v_semf  boolean := coalesce((p_turno ->> 'sem_fracao')::boolean, false);
begin
  if p_motivo in ('turno_existente') then
    v_opc := jsonb_build_array(
      jsonb_build_object('n', 1, 'texto', format('deixar como está (%s)', (p_turno ->> 'jornada_texto')
                                                   || case when p_turno ->> 'valor' is not null
                                                           then ', ' || public._brl((p_turno ->> 'valor')::numeric) else '' end),
                         'efeito', jsonb_build_object('diaria', 'manter')),
      jsonb_build_object('n', 2, 'texto', format('%s %s no %s, como %s', case when v_semf then 'lançar também' else 'trocar para' end,
                                                 case when v_dito = 1 then 'meia diária' else 'dia inteiro' end,
                                                 v_oss, case p_conf ->> 'fonte' when 'equipe' then 'o ' || v_nome || ' disse' else 'você conferiu' end),
                         'efeito', jsonb_build_object('diaria', jsonb_build_object('jornada', case when v_dito = 1 then 'meio' else 'inteiro' end,
                                                                                   'os', to_jsonb(p_os)))));
    v_rec := 1;
    v_rtxt := case when v_semf then 'Recomendo a 1: o que já está lançado no dia fica como está, até você dizer outra coisa.'
                   else 'Recomendo a 1: a diária já lançada fica como está, até você dizer outra coisa.' end;
    v_txt := case when v_semf
      then format('O %s já tem lançado em %s: %s (%s), e o dia %s foi %s no %s.', v_nome, public._dia_curto(p_dia),
                  p_turno ->> 'jornada_texto', coalesce(nullif(p_turno ->> 'os_texto', ''), 'sem OS'),
                  case p_conf ->> 'fonte' when 'equipe' then 'que ele confirmou' else 'conferido' end,
                  case when v_dito = 1 then 'meio dia' else 'o dia todo' end, v_oss)
      else format('A diária de %s do %s já estava lançada (%s, %s%s) e o dia %s foi %s no %s.', public._dia_curto(p_dia), v_nome,
                  p_turno ->> 'jornada_texto', public._brl((p_turno ->> 'valor')::numeric),
                  coalesce(', ' || nullif(p_turno ->> 'os_texto', ''), ', sem OS'),
                  case p_conf ->> 'fonte' when 'equipe' then 'que ele confirmou' else 'conferido' end,
                  case when v_dito = 1 then 'meio dia' else 'o dia todo' end, v_oss) end;
  elsif p_motivo = 'acerto_fechado' then
    v_opc := jsonb_build_array(
      jsonb_build_object('n', 1, 'texto', 'não lançar (o acerto desse período já foi fechado)', 'efeito', jsonb_build_object('diaria', null)),
      jsonb_build_object('n', 2, 'texto', format('lançar %s no %s depois de reabrir o acerto',
                                                 case when v_dito = 1 then 'meia diária' else 'dia inteiro' end, v_oss),
                         'efeito', jsonb_build_object('diaria', jsonb_build_object('jornada', case when v_dito = 1 then 'meio' else 'inteiro' end,
                                                                                   'os', to_jsonb(p_os)))));
    v_rec := 1;
    v_rtxt := 'Recomendo a 1: o acerto do período já foi fechado; para lançar, reabra o acerto antes.';
    v_txt := format('A diária de %s do %s não entrou: o acerto desse período já foi fechado.', public._dia_curto(p_dia), v_nome);
  else
    -- divergente (o que ele disse × o plano), não entendido, ou sem o login do dono para assinar o lançamento
    v_opc := jsonb_build_array(
      jsonb_build_object('n', 1, 'texto', format('meia diária no %s (%s)%s', v_oss, public._brl(round(coalesce(v_valor, 0) / 2, 2)),
                                                 case when v_dito = 1 then ', como o ' || v_nome || ' disse'
                                                      when v_plano = 1 then ', como estava no plano' else '' end),
                         'efeito', jsonb_build_object('diaria', jsonb_build_object('jornada', 'meio', 'os', to_jsonb(p_os)))),
      jsonb_build_object('n', 2, 'texto', format('dia inteiro no %s (%s)%s', v_oss, public._brl(coalesce(v_valor, 0)),
                                                 case when v_dito = 2 then ', como o ' || v_nome || ' disse'
                                                      when v_plano = 2 then ', como estava no plano' else '' end),
                         'efeito', jsonb_build_object('diaria', jsonb_build_object('jornada', 'inteiro', 'os', to_jsonb(p_os)))),
      jsonb_build_object('n', 3, 'texto', 'não lançar', 'efeito', jsonb_build_object('diaria', null)));
    v_rec := case when v_dito = 0 then 3 when v_dito = 1 then 1 when v_dito = 2 then 2
                  when v_plano = 1 then 1 else 2 end;
    v_rtxt := case when v_dito is not null
                   then format('Recomendo a %s: é o que o %s respondeu%s.', v_rec, v_nome,
                               coalesce(' às ' || to_char((p_conf ->> 'quando')::timestamptz at time zone 'America/Sao_Paulo', 'HH24:MI'), ''))
                   else format('Recomendo a %s: é o que estava no plano.', v_rec) end;
    v_txt := case
      when p_motivo = 'sem_dono' then format('A diária de %s do %s bate com o plano, mas não achei o seu login para lançar.',
                                             public._dia_curto(p_dia), v_nome)
      when p_conf ->> 'fonte' = 'equipe' and v_dito is null
        then format('O %s respondeu "%s" ao "como foi hoje?" de %s e eu não entendi se foi o dia todo.', v_nome, v_trecho,
                    public._dia_curto(p_dia))
      when p_conf ->> 'fonte' = 'equipe'
        then format('O %s respondeu "%s" e o plano de %s era %s no %s.', v_nome, v_trecho, public._dia_curto(p_dia),
                    case when v_plano = 2 then 'o dia todo' else 'meio dia' end, v_oss)
      else format('O dia de %s do %s no %s ficou em parte (conferência): quanto foi de diária?', public._dia_curto(p_dia), v_nome, v_oss) end;
  end if;
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, payee_id, dia, perda_em, texto, opcoes, recomendacao,
                                       recomendacao_texto, modo, criada_em)
  values ('diaria', format('diaria:%s:%s', p_payee, p_dia), p_os[1], p_os, p_payee, p_dia, p_hoje,
          left(public._agenda_corta(v_txt, 600), 600), v_opc, v_rec, left(v_rtxt, 300), v_modo, p_agora)
  on conflict (chave, modo) where estado = 'aberta' do nothing
  returning id into v_id;
  return jsonb_build_object('status', 'pergunta', 'motivo', p_motivo, 'pergunta_id', v_id, 'texto', v_txt);
end;
$function$;

comment on function public._agenda_perguntar_diaria(uuid, date, text, jsonb, uuid[], date, timestamptz, jsonb) is
  'Agenda de Produção (Fase 3, P4; revisão C1): a pergunta CRÍTICA da diária (tipo diaria, chave diaria:<pessoa>:<dia>, no modo da diária) — divergente/não entendida/sem login do dono: 1) meia diária, 2) dia inteiro, 3) não lançar, recomendando o que a pessoa disse (sem o dito, o plano); turno que já existe: 1) deixar como está, 2) trocar (o turno sem fração — por hora, folga, atestado, feriado —: 2) lançar também); acerto fechado: 1) não lançar, 2) lançar depois de reabrir. Sem grant.';

-- O lançamento (sem turno no dia; nunca sobrescreve): o turno, os vínculos às OS, a alocação e a ação desfazível.
create or replace function public._agenda_lancar_diaria(p_payee uuid, p_dia date, p_fracao numeric, p_os uuid[], p_origem text,
                                                        p_confirmacao text, p_pergunta uuid, p_hoje date, p_agora timestamptz,
                                                        p_conf jsonb default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_nome  text := (select public._agenda_nome_curto(p.name) from public.payees p where p.id = p_payee);
  v_perfil public.work_profiles%rowtype;
  v_dono  uuid := (select p.app_user_id from public.payees p where p.id = public._agenda_dono(null));
  v_ws    uuid;
  v_valor numeric;
  v_txt   text;
  v_acao  uuid;
  v_msg   text;
  v_os    uuid[] := array(select distinct x from unnest(p_os) x order by 1);
begin
  if p_fracao not in (0.5, 1) then
    raise exception 'Fração de diária desconhecida: %.', p_fracao using errcode = '22023';
  end if;
  select * into v_perfil from public.work_profiles w
   where w.payee_id = p_payee and w.modo_pagamento = 'diaria' and w.vigencia_inicio <= p_dia
     and (w.vigencia_fim is null or w.vigencia_fim >= p_dia)
   order by w.vigencia_inicio desc limit 1;
  if not found then
    return jsonb_build_object('status', 'sem_perfil');
  end if;
  v_valor := round(v_perfil.valor_diaria * p_fracao, 2);
  v_txt := format('%s, %s: %s no %s, %s — %s.', v_nome, public._dia_curto(p_dia),
                  case when p_fracao = 1 then 'dia inteiro' else 'meia diária' end,
                  public._agenda_lista(array(select public._agenda_rotulo_da_os(x) from unnest(v_os) x order by 1), null),
                  public._brl(v_valor), coalesce(p_confirmacao, 'confirmado'));
  -- sombra: só o que lançaria (a decisão do dono numa pergunta em ligado sempre lança)
  if p_pergunta is null and cf.modo_diaria <> 'ligado' then
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, antes, depois, texto)
    values (clock_timestamp(), p_hoje, false, p_origem, 'diaria', v_os[1], v_os, p_payee, jsonb_build_object('turno', null),
            jsonb_build_object('dia', p_dia, 'fracao', p_fracao, 'os', to_jsonb(v_os), 'valor', v_valor, 'confirmacao', p_confirmacao),
            left('Em teste: lançaria ' || v_txt, 400))
    returning id into v_acao;
    return jsonb_build_object('status', 'sombra', 'acao_id', v_acao, 'texto', 'Em teste: lançaria ' || v_txt, 'valor', v_valor,
                              'fracao', p_fracao, 'nome', v_nome);
  end if;
  if v_dono is null then
    return public._agenda_perguntar_diaria(p_payee, p_dia, 'sem_dono', coalesce(p_conf, '{}'::jsonb), v_os, p_hoje, p_agora);
  end if;
  -- (revisão C1, item 8) sozinha, a agenda nunca lança num dia em que a pessoa já tem QUALQUER turno — também o sem fração
  -- (por hora, folga, atestado, feriado), que o índice de um dia por perfil não pega. A regra do turno que já existe
  -- (_agenda_diaria_do_dia) decide: a pergunta crítica. A decisão do dono (p_pergunta) lança mesmo assim.
  if p_pergunta is null and exists (select 1 from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
                                     where wp.payee_id = p_payee and ws.data = p_dia) then
    return jsonb_build_object('status', 'corrida');
  end if;
  begin
    insert into public.work_shifts (work_profile_id, data, tipo, origem, status, observacao, registrado_por, aprovado_por,
                                    aprovado_em, fracao, valor_diaria, extras, descontos)
    values (v_perfil.id, p_dia, 'diaria', 'agente', 'aprovado', left('Pela agenda: ' || coalesce(p_confirmacao, 'confirmado'), 500),
            v_dono, v_dono, p_agora, p_fracao, v_perfil.valor_diaria, 0, 0)
    on conflict (work_profile_id, data) where fracao is not null do nothing
    returning id into v_ws;
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like '%acerto nº%' then
      return public._agenda_perguntar_diaria(p_payee, p_dia, 'acerto_fechado', coalesce(p_conf, '{}'::jsonb), v_os, p_hoje, p_agora);
    end if;
    raise;
  end;
  if v_ws is null then
    -- corrida: alguém lançou o dia agora; a regra do turno que já existe decide (nunca sobrescreve)
    return jsonb_build_object('status', 'corrida');
  end if;
  insert into public.work_shift_os (shift_id, service_order_id) select v_ws, x from unnest(v_os) x on conflict do nothing;
  update public.agenda_alocacoes a set work_shift_id = v_ws
   where a.payee_id = p_payee and a.dia = p_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
     and a.service_order_id = any (v_os);
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, work_shift_id,
                                   pergunta_id, critica, antes, depois, texto, desfazivel_ate)
  values (clock_timestamp(), p_hoje, true, p_origem, 'diaria', v_os[1], v_os, p_payee, v_ws, p_pergunta, p_pergunta is not null,
          jsonb_build_object('turno', null),
          jsonb_build_object('dia', p_dia, 'fracao', p_fracao, 'os', to_jsonb(v_os), 'valor', v_valor, 'confirmacao', p_confirmacao),
          left(v_txt, 400), p_agora + cf.desfazer_validade)
  returning id into v_acao;
  return jsonb_build_object('status', 'lancada', 'work_shift_id', v_ws, 'acao_id', v_acao, 'texto', v_txt, 'valor', v_valor,
                            'fracao', p_fracao, 'nome', v_nome);
end;
$function$;

comment on function public._agenda_lancar_diaria(uuid, date, numeric, uuid[], text, text, uuid, date, timestamptz, jsonb) is
  'Agenda de Produção (Fase 3, P4; revisão C1): lança a diária pela agenda — só INSERT (sozinha, nunca com QUALQUER turno da pessoa no dia, também sem fração; on conflict do índice de um dia por perfil: nunca sobrescreve; corrida = status corrida), tipo diaria, origem agente, status aprovado (a regra de hoje), assinado pelo login do dono (sem ele: a pergunta crítica), valor do perfil vigente; work_shift_os das OS do plano (meio dia em duas OS = uma diária ligada às duas); agenda_alocacoes.work_shift_id; ação diaria desfazível ("Roberto, ter 03/11: dia inteiro no Vanderlei (OS-00069), R$ 180,00 — ele confirmou às 17:12."). Em sombra só a ação executada = false. Acerto fechado (trg_dia_em_acerto_fechado) = a pergunta crítica. Sem grant.';

-- A diária de uma pessoa num dia: pula, confere, compara com o plano e com o turno que existe, e lança ou pergunta.
create or replace function public._agenda_diaria_do_dia(p_payee uuid, p_dia date, p_origem text, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_kind  text;
  v_conf  jsonb;
  v_os    uuid[];
  v_frac  numeric;
  v_ws    record;
  v_wsos  uuid[];
  v_fonte text;
  v_txt   text;
  v_r     jsonb;
  v_jtxt  text;
begin
  if p_origem is null or p_origem not in ('equipe', 'conferencia', 'rotina') then
    raise exception 'Quem pede a diária: "%" (equipe, conferencia ou rotina).', coalesce(p_origem, '') using errcode = '22023';
  end if;
  if cf.modo_diaria = 'desligado' then
    return jsonb_build_object('status', 'desligado');
  end if;
  if p_dia > p_hoje or p_dia < p_hoje - cf.diaria_janela_dias then
    return jsonb_build_object('status', 'fora_da_janela');
  end if;
  -- o dono (sócio) não tem diária; nem quem não tem perfil de diária vigente no dia
  select p.kind into v_kind from public.payees p where p.id = p_payee;
  if v_kind is null or v_kind = 'socio' then
    return jsonb_build_object('status', 'dono');
  end if;
  if not exists (select 1 from public.work_profiles w
                  where w.payee_id = p_payee and w.modo_pagamento = 'diaria' and w.vigencia_inicio <= p_dia
                    and (w.vigencia_fim is null or w.vigencia_fim >= p_dia)) then
    return jsonb_build_object('status', 'sem_perfil');
  end if;
  -- já tratada (chave diaria:<pessoa>:<dia>): a ação do modo de agora (lançada, desfeita ou corrigida) ou a pergunta aberta
  if exists (select 1 from public.agenda_acoes a
              where a.tipo = 'diaria' and a.payee_id = p_payee and a.depois ->> 'dia' = p_dia::text
                and a.executada = (cf.modo_diaria = 'ligado')) then
    return jsonb_build_object('status', 'ja_tratada');
  end if;
  -- a pergunta da diária (crítica ou de ligar) aberta, ou já respondida pelo dono ("não lançar" não volta a perguntar)
  if exists (select 1 from public.agenda_perguntas q
              where q.chave in (format('diaria:%s:%s', p_payee, p_dia), format('diaria_ligar:%s:%s', p_payee, p_dia))
                and q.estado in ('aberta', 'respondida')
                and q.modo = case when cf.modo_diaria = 'ligado' then 'ligado' else 'sombra' end) then
    return jsonb_build_object('status', 'pergunta');
  end if;

  v_conf := public._agenda_confirmacao_do_dia(p_payee, p_dia);
  if v_conf ->> 'estado' = 'sem_plano' then
    -- a diária fora do plano é do dono (registrar_diaria)
    return jsonb_build_object('status', 'sem_plano');
  end if;
  if v_conf ->> 'estado' = 'aguardando' then
    return jsonb_build_object('status', 'aguardando');
  end if;
  if v_conf ->> 'estado' = 'nao_foi' then
    return jsonb_build_object('status', 'nao_foi', 'texto', format('%s não foi %s.',
      (select public._agenda_nome_curto(p.name) from public.payees p where p.id = p_payee), public._agenda_dia_ref(p_dia, p_hoje)));
  end if;
  v_os := array(select (x #>> '{}')::uuid from jsonb_array_elements(v_conf -> 'os') x order by 1);
  if v_conf ->> 'estado' = 'divergente' then
    return public._agenda_perguntar_diaria(p_payee, p_dia, 'divergente', v_conf, v_os, p_hoje, p_agora);
  end if;

  -- confirmada: a fração é a do plano (meio dia = 1 turno)
  v_frac := jsonb_array_length(v_conf -> 'plano')::numeric / 2;
  v_fonte := v_conf ->> 'fonte';
  v_txt := case when v_fonte = 'equipe'
                then 'ele confirmou' || coalesce(' às ' || to_char((v_conf ->> 'quando')::timestamptz at time zone 'America/Sao_Paulo', 'HH24:MI'), '')
                else 'você conferiu o dia' end;
  -- o turno que já existe: a agenda nunca muda fração, valor ou OS dele. (Revisão C1, item 8) QUALQUER turno da pessoa no
  -- dia conta — também o sem fração (por hora, folga, atestado, feriado): esse vai sempre para a pergunta crítica
  select ws.id, ws.fracao, ws.valor_dia, ws.tipo into v_ws
    from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
   where wp.payee_id = p_payee and ws.data = p_dia
   order by ws.fracao is null, ws.created_at, ws.id
   limit 1;
  if v_ws.id is not null then
    v_wsos := array(select wo.service_order_id from public.work_shift_os wo where wo.shift_id = v_ws.id order by 1);
    if v_ws.fracao = v_frac and v_wsos = v_os then
      update public.agenda_alocacoes a set work_shift_id = v_ws.id
       where a.payee_id = p_payee and a.dia = p_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
         and a.service_order_id = any (v_os) and a.work_shift_id is distinct from v_ws.id;
      return jsonb_build_object('status', 'igual', 'work_shift_id', v_ws.id);
    end if;
    if v_ws.fracao = v_frac and cardinality(v_wsos) = 0 then
      -- a pergunta de ligar (não crítica): 1) ligar às OS do plano, 2) deixar sem OS
      perform public._agenda_equipe_perguntar('diaria_ligar', format('diaria_ligar:%s:%s', p_payee, p_dia), p_payee, v_os[1], p_dia,
        format('A diária de %s do %s já estava lançada, sem OS. Ligo ao %s? Me responda aqui.', public._dia_curto(p_dia),
               (select public._agenda_nome_curto(p.name) from public.payees p where p.id = p_payee),
               public._agenda_lista(array(select public._agenda_rotulo_da_os(x) from unnest(v_os) x order by 1), null)),
        case when cf.modo_diaria = 'ligado' then 'ligado' else 'sombra' end, p_agora,
        jsonb_build_array(
          jsonb_build_object('n', 1, 'texto', 'ligar a diária às OS do plano',
                             'efeito', jsonb_build_object('diaria', 'ligar', 'os', to_jsonb(v_os), 'work_shift_id', v_ws.id)),
          jsonb_build_object('n', 2, 'texto', 'deixar sem OS', 'efeito', jsonb_build_object('diaria', 'manter'))), 1::smallint);
      return jsonb_build_object('status', 'pergunta_ligar');
    end if;
    v_jtxt := case when v_ws.fracao is not null then public._rotulo_jornada(v_ws.fracao)
                   else case v_ws.tipo when 'normal' then 'turno por hora' when 'folga' then 'folga' when 'atestado' then 'atestado'
                                       when 'feriado' then 'feriado' when 'falta' then 'falta' else 'turno sem diária' end end;
    return public._agenda_perguntar_diaria(p_payee, p_dia, 'turno_existente', v_conf, v_os, p_hoje, p_agora,
      jsonb_build_object('jornada_texto', v_jtxt, 'valor', case when v_ws.fracao is not null then v_ws.valor_dia end,
                         'sem_fracao', v_ws.fracao is null,
                         'os_texto', public._agenda_lista(array(select so.service_order_number from unnest(v_wsos) x
                                                                 join public.service_orders so on so.id = x order by 1), null)));
  end if;

  v_r := public._agenda_lancar_diaria(p_payee, p_dia, v_frac, v_os, v_fonte, v_txt, null, p_hoje, p_agora, v_conf);
  if v_r ->> 'status' = 'corrida' then
    return public._agenda_diaria_do_dia(p_payee, p_dia, p_origem, p_hoje, p_agora);
  end if;
  return v_r;
end;
$function$;

comment on function public._agenda_diaria_do_dia(uuid, date, text, date, timestamptz) is
  'Agenda de Produção (Fase 3, P4): a diária automática de uma pessoa num dia (chamada pela resposta da equipe, pelo agenda_registrar_dia e pela rotina; idempotente pela chave diaria:<pessoa>:<dia>). Nada com modo_diaria desligado, dia futuro ou além de diaria_janela_dias. Pula o dono (sócio) e quem não tem perfil de diária vigente. Sem plano = nada (a diária fora do plano é do dono). _agenda_confirmacao_do_dia: aguardando = nada; não foi = nada; divergente = a pergunta crítica. Confirmada: com turno no dia igual (fração e OS) só liga a alocação; igual sem OS = a pergunta de ligar (não crítica); diferente — ou QUALQUER turno sem fração (por hora, folga, atestado, feriado; revisão C1) — = a pergunta crítica (o turno nunca muda); sem turno = _agenda_lancar_diaria (fração do plano, somando os meios-dias). {status, …}. Sem grant.';

-- A resposta do dono à pergunta da diária (crítica ou de ligar), pelo modo da diária.
create or replace function public._agenda_decidir_diaria(p_pergunta uuid, p_opcao smallint, p_autor uuid, p_via text, p_trecho text,
                                                         p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_q     public.agenda_perguntas%rowtype;
  v_opc   jsonb;
  v_ef    jsonb;
  v_autor uuid;
  v_nome  text;
  v_ws    record;
  v_os    uuid[];
  v_r     jsonb;
  v_txt   text;
  v_acao  uuid;
  v_antes jsonb;
begin
  select * into v_q from public.agenda_perguntas where id = p_pergunta for update;
  if not found or v_q.tipo not in ('diaria', 'diaria_ligar') then
    raise exception 'Não encontrei essa pergunta da diária.' using errcode = 'P0002';
  end if;
  if v_q.estado <> 'aberta' then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta já foi respondida ou resolvida.');
  end if;
  if v_q.modo <> 'ligado' or cf.modo_diaria <> 'ligado' then
    return jsonb_build_object('ok', false, 'texto', 'A diária automática ainda está em teste: mostro como ficaria, mas não lanço nada.');
  end if;
  select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
  if v_opc is null then
    return jsonb_build_object('ok', false,
      'texto', 'Essa opção não existe. As opções são: '
               || coalesce((select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                              from jsonb_array_elements(v_q.opcoes) o), 'nenhuma') || '.');
  end if;
  v_autor := public._autor_da_agenda(p_autor);
  v_nome := (select public._agenda_nome_curto(p.name) from public.payees p where p.id = v_q.payee_id);
  v_ef := v_opc -> 'efeito' -> 'diaria';
  begin
    update public.agenda_perguntas
       set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
           respondida_por = v_autor, respondida_via = p_via
     where id = p_pergunta;
    if v_ef is null or jsonb_typeof(v_ef) = 'null' then
      v_txt := format('Não lancei a diária de %s do %s.', public._dia_curto(v_q.dia), v_nome);
    elsif v_ef = '"manter"'::jsonb then
      v_txt := format('Deixei a diária de %s do %s como estava.', public._dia_curto(v_q.dia), v_nome);
    elsif v_ef = '"ligar"'::jsonb then
      v_os := array(select (x #>> '{}')::uuid from jsonb_array_elements(v_opc -> 'efeito' -> 'os') x order by 1);
      insert into public.work_shift_os (shift_id, service_order_id)
      select (v_opc -> 'efeito' ->> 'work_shift_id')::uuid, x from unnest(v_os) x on conflict do nothing;
      update public.agenda_alocacoes a set work_shift_id = (v_opc -> 'efeito' ->> 'work_shift_id')::uuid
       where a.payee_id = v_q.payee_id and a.dia = v_q.dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
         and a.service_order_id = any (v_os);
      v_txt := format('Liguei a diária de %s do %s ao %s.', public._dia_curto(v_q.dia), v_nome,
                      public._agenda_lista(array(select public._agenda_rotulo_da_os(x) from unnest(v_os) x order by 1), null));
    else
      v_os := array(select (x #>> '{}')::uuid from jsonb_array_elements(v_ef -> 'os') x order by 1);
      select ws.id, ws.fracao, ws.valor_dia, ws.origem into v_ws
        from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
       where wp.payee_id = v_q.payee_id and ws.data = v_q.dia and ws.fracao is not null limit 1;
      if v_ws.id is null then
        v_r := public._agenda_lancar_diaria(v_q.payee_id, v_q.dia, case when v_ef ->> 'jornada' = 'meio' then 0.5 else 1 end, v_os,
                                            'dono', 'você decidiu', p_pergunta, p_hoje, p_agora);
        if v_r ->> 'status' <> 'lancada' then
          raise exception using errcode = 'P0098', message = coalesce(v_r ->> 'texto', 'não deu para lançar a diária.');
        end if;
        v_txt := 'Diária lançada: ' || (v_r ->> 'texto');
      else
        -- o turno que existe: sobrescrever é o pedido do dono (registrar_diaria, a regra de hoje)
        v_antes := jsonb_build_object('turno', jsonb_build_object('id', v_ws.id, 'fracao', v_ws.fracao, 'valor_dia', v_ws.valor_dia,
                                                                  'origem', v_ws.origem));
        v_r := public.registrar_diaria(v_q.payee_id, v_q.dia, v_ef ->> 'jornada', v_os, null, null, null, null, 'whatsapp', v_autor);
        insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, work_shift_id,
                                         pergunta_id, critica, antes, depois, texto, autor)
        values (clock_timestamp(), p_hoje, true, 'dono', 'diaria', v_os[1], v_os, v_q.payee_id, v_ws.id, p_pergunta, true, v_antes,
                jsonb_build_object('dia', v_q.dia, 'fracao', case when v_ef ->> 'jornada' = 'meio' then 0.5 else 1 end,
                                   'os', to_jsonb(v_os), 'confirmacao', 'você decidiu', 'registrar_diaria', v_r ->> 'acao'),
                left('Diária corrigida pela sua decisão: ' || coalesce(v_r ->> 'message', ''), 400), v_autor)
        returning id into v_acao;
        v_txt := 'Feito: ' || coalesce(v_r ->> 'message', 'diária corrigida.');
      end if;
    end if;
  exception
    when sqlstate 'P0098' then
      return jsonb_build_object('ok', false, 'texto', 'Não consegui fazer o que você escolheu: ' || sqlerrm || ' Nada mudou.');
    when others then
      -- o resto (o acerto fechado, a coerência do turno…): nada fica, a pergunta continua aberta, e o erro é consultável
      perform public.log_app_error('db', 'agenda: a decisão da diária não aplicou: ' || sqlerrm, 'agenda', 'diaria:decidir', 'warn',
                                   jsonb_build_object('pergunta', p_pergunta, 'opcao', p_opcao));
      return jsonb_build_object('ok', false, 'texto', 'Não consegui fazer o que você escolheu: ' || sqlerrm || ' Nada mudou.');
  end;
  return jsonb_build_object('ok', true, 'texto', v_txt, 'acao_id', coalesce(v_acao, (v_r ->> 'acao_id')::uuid));
end;
$function$;

comment on function public._agenda_decidir_diaria(uuid, smallint, uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 3, P4): a decisão do dono numa pergunta diaria (crítica) ou diaria_ligar — só com a pergunta e modo_diaria em ligado. "não lançar" e "deixar como está" só respondem; "ligar" põe work_shift_os e a alocação; meia/inteira sem turno = _agenda_lancar_diaria (ação crítica com a pergunta); com turno = registrar_diaria (o pedido do dono sobrescreve) e a ação crítica com o antes. Falhou (acerto fechado…) = nada fica, a pergunta continua aberta. Sem grant.';

-- Apaga a diária que a AGENDA lançou (desfazer em 24 h, ou a palavra *diária <nome> não* sem prazo), se o acerto está aberto.
create or replace function public._agenda_desfazer_diaria(p_acao uuid, p_autor uuid, p_hoje date, p_agora timestamptz,
                                                          p_sem_prazo boolean default false)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_a    public.agenda_acoes%rowtype;
  v_ws   record;
  v_nome text;
  v_dia  date;
  v_txt  text;
  v_acao uuid;
begin
  select * into v_a from public.agenda_acoes where id = p_acao for update;
  if not found or v_a.tipo <> 'diaria' then
    raise exception 'Não encontrei essa diária da agenda.' using errcode = 'P0002';
  end if;
  v_nome := (select public._agenda_nome_curto(p.name) from public.payees p where p.id = v_a.payee_id);
  v_dia := (v_a.depois ->> 'dia')::date;
  if not v_a.executada then
    return jsonb_build_object('ok', false, 'texto', 'Isso foi só o teste da diária automática: nada foi lançado.');
  end if;
  if v_a.desfeita_em is not null then
    return jsonb_build_object('ok', false, 'texto', 'Essa diária já foi apagada.');
  end if;
  if not p_sem_prazo and (v_a.desfazivel_ate is null or p_agora > v_a.desfazivel_ate) then
    return jsonb_build_object('ok', false, 'texto',
      format('Não dá mais para desfazer a diária de %s do %s: passou o prazo. Corrija com *diária %s meia*, *inteira* ou *não*.',
             public._dia_curto(v_dia), v_nome, v_nome));
  end if;
  select ws.id, ws.origem into v_ws from public.work_shifts ws where ws.id = v_a.work_shift_id;
  if v_ws.id is null then
    return jsonb_build_object('ok', false, 'texto', format('A diária de %s do %s já não existe.', public._dia_curto(v_dia), v_nome));
  end if;
  -- só o que a agenda criou (o turno que já existia nunca é apagado por ela)
  if v_ws.origem <> 'agente' or coalesce(jsonb_typeof(v_a.antes -> 'turno'), 'null') <> 'null' then
    return jsonb_build_object('ok', false, 'texto',
      format('Essa diária de %s do %s não foi lançada por mim: para apagar, use Financeiro › Diárias.', public._dia_curto(v_dia), v_nome));
  end if;
  begin
    delete from public.work_shifts where id = v_ws.id;
  exception when others then
    if sqlerrm like '%acerto nº%' then
      return jsonb_build_object('ok', false, 'texto', format('Não dá para apagar: o acerto do %s desse período já foi fechado.', v_nome));
    end if;
    raise;
  end;
  v_txt := format('Apaguei a diária de %s do %s que eu tinha lançado.', public._dia_curto(v_dia), v_nome);
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, antes, depois, texto,
                                   autor, desfaz_a)
  values (clock_timestamp(), p_hoje, true, 'dono', 'desfazer', v_a.service_order_id, v_a.os_ids, v_a.payee_id,
          jsonb_build_object('acao', v_a.id, 'tipo', 'diaria'), jsonb_build_object('dia', v_dia, 'turno_apagado', v_ws.id),
          left(v_txt, 400), p_autor, v_a.id)
  returning id into v_acao;
  update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_a.id;
  return jsonb_build_object('ok', true, 'texto', v_txt, 'acao_id', v_acao);
end;
$function$;

comment on function public._agenda_desfazer_diaria(uuid, uuid, date, timestamptz, boolean) is
  'Agenda de Produção (Fase 3, P4): apaga o work_shifts que a agenda lançou (cascade work_shift_os; a alocação fica com work_shift_id nulo) — dentro de desfazivel_ate (o *desfaz*) ou sem prazo (a palavra *diária <nome> não*); só turno de origem agente criado pela ação; acerto fechado = "Não dá para apagar: o acerto do Roberto desse período já foi fechado." Ação desfazer e a original desfeita. Sem grant.';

-- A palavra do dono: *diária <nome> inteira|meia|não [quando]*.
create or replace function public.agenda_diaria_dita(p_autor uuid, p_nome text, p_jornada text, p_quando text default null,
                                                     p_canal text default 'whatsapp', p_hoje date default public._hoje_brt(),
                                                     p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_autor uuid := public._autor_da_agenda(p_autor);
  v_jor   text := case public._agenda_normal(p_jornada)
                    when 'inteira' then 'inteiro' when 'inteiro' then 'inteiro' when 'dia inteiro' then 'inteiro'
                    when 'meia' then 'meio' when 'meio' then 'meio' when 'nao' then 'nao' end;
  v_rp    jsonb;
  v_payee uuid;
  v_nome  text;
  v_d     jsonb;
  v_dia   date;
  v_q     public.agenda_perguntas%rowtype;
  v_n     smallint;
  v_a     public.agenda_acoes%rowtype;
  v_ws    record;
  v_os    uuid[];
  v_r     jsonb;
  v_via   text := case when p_canal in ('whatsapp', 'painel', 'tela') then p_canal else 'whatsapp' end;
  v_trecho text;
begin
  if v_jor is null then
    raise exception 'Jornada da diária: "%" (inteira, meia ou não).', coalesce(p_jornada, '') using errcode = '22023';
  end if;
  if cf.modo_diaria = 'desligado' then
    return jsonb_build_object('ok', false, 'status', 'nao_achei', 'texto', 'A diária automática está desligada.');
  end if;
  v_rp := public.agenda_resolver_pessoa(p_nome, v_autor, p_hoje);
  if v_rp ->> 'status' = 'ambiguo' then
    return jsonb_build_object('ok', false, 'status', 'ambiguo', 'texto', v_rp ->> 'texto');
  end if;
  if v_rp ->> 'status' <> 'ok' or coalesce((v_rp ->> 'eh_dono')::boolean, false) then
    return jsonb_build_object('ok', false, 'status', 'nao_achei', 'texto', coalesce(v_rp ->> 'texto', 'Não achei essa pessoa.'));
  end if;
  v_payee := (v_rp ->> 'payee_id')::uuid;
  v_nome := v_rp ->> 'nome_curto';
  v_trecho := format('diária %s %s%s', v_nome, p_jornada, coalesce(' ' || nullif(btrim(p_quando), ''), ''));
  if nullif(btrim(coalesce(p_quando, '')), '') is not null then
    begin
      v_d := public.agenda_data_dita(p_quando, p_hoje, 'passado');
    exception when sqlstate '22007' then
      return jsonb_build_object('ok', false, 'status', 'data', 'texto', sqlerrm);
    end;
    if (v_d ->> 'de') is distinct from (v_d ->> 'ate') then
      return jsonb_build_object('ok', false, 'status', 'data', 'texto', 'Diga um dia só (por exemplo "ontem" ou "terça").');
    end if;
    v_dia := (v_d ->> 'de')::date;
  else
    select q.dia into v_dia from public.agenda_perguntas q
     where q.tipo = 'diaria' and q.payee_id = v_payee and q.estado = 'aberta'
     order by q.dia desc, q.criada_em desc limit 1;
    if v_dia is null then
      select (a.depois ->> 'dia')::date into v_dia from public.agenda_acoes a
       where a.tipo = 'diaria' and a.payee_id = v_payee and a.executada and a.desfeita_em is null
       order by a.criada_em desc limit 1;
    end if;
    v_dia := coalesce(v_dia, p_hoje);
  end if;

  -- (a) a pergunta aberta da diária: a opção cuja jornada casa ("não" = não lançar)
  select * into v_q from public.agenda_perguntas q
   where q.tipo = 'diaria' and q.payee_id = v_payee and q.dia = v_dia and q.estado = 'aberta'
   order by q.modo = 'ligado' desc, q.criada_em desc limit 1;
  if v_q.id is not null then
    select (o ->> 'n')::smallint into v_n from jsonb_array_elements(v_q.opcoes) o
     where case when v_jor = 'nao' then jsonb_typeof(o -> 'efeito' -> 'diaria') is distinct from 'object'
                                        and (o -> 'efeito' -> 'diaria') is distinct from '"manter"'::jsonb
                                        and (o -> 'efeito' -> 'diaria') is distinct from '"ligar"'::jsonb
                else o -> 'efeito' -> 'diaria' ->> 'jornada' = v_jor end
     order by (o ->> 'n')::int limit 1;
    if v_n is null then
      return jsonb_build_object('ok', false, 'status', 'opcao',
        'texto', 'Essa não é uma das opções da pergunta: ' || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                                                                 from jsonb_array_elements(v_q.opcoes) o) || '.');
    end if;
    return public.agenda_decidir(v_q.id, v_n, v_autor, v_via, v_trecho, p_hoje, p_agora);
  end if;

  -- (b) a diária que a agenda lançou (a ação que CRIOU o turno, não desfeita; as correções do dono depois dela não
  -- contam): corrige pelo registrar_diaria ou apaga
  select * into v_a from public.agenda_acoes a
   where a.tipo = 'diaria' and a.payee_id = v_payee and a.depois ->> 'dia' = v_dia::text and a.executada and a.desfeita_em is null
     and a.work_shift_id is not null and coalesce(jsonb_typeof(a.antes -> 'turno'), 'null') = 'null'
   order by a.criada_em desc limit 1;
  if v_a.id is not null then
    if v_jor = 'nao' then
      return public._agenda_desfazer_diaria(v_a.id, v_autor, p_hoje, p_agora, true);
    end if;
    select ws.id, ws.fracao, ws.valor_dia, ws.origem into v_ws from public.work_shifts ws where ws.id = v_a.work_shift_id;
    if v_ws.fracao = (case when v_jor = 'meio' then 0.5 else 1 end) then
      return jsonb_build_object('ok', true, 'mudou', false,
        'texto', format('Já estava assim: %s, %s, %s.', v_nome, public._dia_curto(v_dia), public._rotulo_jornada(v_ws.fracao)));
    end if;
    v_os := array(select wo.service_order_id from public.work_shift_os wo where wo.shift_id = v_ws.id order by 1);
    begin
      v_r := public.registrar_diaria(v_payee, v_dia, v_jor, case when cardinality(v_os) > 0 then v_os end, null, null, null, null,
                                     'whatsapp', v_autor);
    exception when others then
      if sqlerrm like '%acerto nº%' then
        return jsonb_build_object('ok', false, 'texto', format('Não dá para corrigir: o acerto do %s desse período já foi fechado.', v_nome));
      end if;
      raise;
    end;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, work_shift_id,
                                     antes, depois, texto, autor)
    values (clock_timestamp(), p_hoje, true, 'dono', 'diaria', v_os[1], v_os, v_payee, v_ws.id,
            jsonb_build_object('turno', jsonb_build_object('id', v_ws.id, 'fracao', v_ws.fracao, 'valor_dia', v_ws.valor_dia,
                                                           'origem', v_ws.origem)),
            jsonb_build_object('dia', v_dia, 'fracao', case when v_jor = 'meio' then 0.5 else 1 end, 'os', to_jsonb(v_os),
                               'confirmacao', 'você corrigiu', 'corrige', v_a.id),
            left(format('Corrigido: %s, %s, %s (era %s).', v_nome, public._dia_curto(v_dia),
                        case when v_jor = 'meio' then 'meia diária' else 'dia inteiro' end,
                        case when v_ws.fracao = 1 then 'dia inteiro' else 'meia diária' end), 400), v_autor);
    return jsonb_build_object('ok', true, 'mudou', true,
      'texto', format('Corrigido: %s, %s, %s (era %s).', v_nome, public._dia_curto(v_dia),
                      case when v_jor = 'meio' then 'meia diária' else 'dia inteiro' end,
                      case when v_ws.fracao = 1 then 'dia inteiro' else 'meia diária' end));
  end if;
  -- (c) nada da agenda: o turno segue ao modelo (o registrar_diaria normal)
  return jsonb_build_object('ok', false, 'status', 'nao_achei', 'texto', format('Não tenho diária da agenda do %s para %s.', v_nome,
                                                                                 public._dia_curto(v_dia)));
end;
$function$;

comment on function public.agenda_diaria_dita(uuid, text, text, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 3, P4): a palavra *diária <nome> inteira|meia|não [quando]* — a pessoa por agenda_resolver_pessoa (ambíguo = a pergunta; o dono ou ninguém = nao_achei); o dia dito (passado), senão o da pergunta diaria aberta mais recente dela, senão o da última diária da agenda, senão hoje. (a) Há pergunta diaria aberta → agenda_decidir com a opção da jornada ("não" = não lançar); (b) há diária lançada pela agenda → corrige pelo registrar_diaria ("Corrigido: Roberto, ter 03/11, meia diária (era dia inteiro).") ou, com "não", apaga ("Apaguei a diária de ter 03/11 do Roberto que eu tinha lançado."; acerto fechado = "Não dá para apagar…"); (c) nada → status nao_achei (o turno segue ao modelo e ao registrar_diaria). modo_diaria desligado = nao_achei. Admin pelo _autor_da_agenda.';

-- A linha do "sim" do registrar_diaria: a agenda já lançou essa diária? (texto pronto)
create or replace function public.agenda_diaria_da_agenda(p_payee uuid, p_dia date)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce((
    select jsonb_build_object('lancada', true, 'acao_id', a.id, 'fracao', (a.depois ->> 'fracao')::numeric,
             'texto', format('A agenda já lançou essa diária às %s (corrige com *diária %s %s*).',
                             to_char(a.criada_em at time zone 'America/Sao_Paulo', 'HH24:MI'), public._agenda_nome_curto(p.name),
                             case when (a.depois ->> 'fracao')::numeric = 1 then 'meia' else 'inteira' end))
      from public.agenda_acoes a join public.payees p on p.id = a.payee_id
     where a.tipo = 'diaria' and a.payee_id = p_payee and a.depois ->> 'dia' = p_dia::text and a.executada and a.desfeita_em is null
     order by a.criada_em desc limit 1), jsonb_build_object('lancada', false));
$function$;

comment on function public.agenda_diaria_da_agenda(uuid, date) is
  'Agenda de Produção (Fase 3, P4): para o resumo do "sim" do registrar_diaria — a diária da pessoa no dia que a agenda lançou (ação diaria executada, não desfeita): {lancada, acao_id, fracao, texto "A agenda já lançou essa diária às 17:12 (corrige com *diária Roberto meia*)."}; senão {lancada: false}.';

-- ── 5. A rotina da equipe (o mesmo tique de 15 min da vigia, antes dela) ────────────────────────────────────
-- Cada passo é uma função _agenda_rotina_<passo>(p_hoje, p_agora) que devolve as contagens (e os acordes); a rotina os
-- chama um a um, cada um no seu bloco. Sem grant: só agenda_rotina_rodar (security definer) os chama.

-- O modo em que a rotina grava as mensagens: ligado ou sombra (desligado não chega aqui).
create or replace function public._agenda_modo_da_equipe()
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case when (public._agenda_cfg()).modo_equipe = 'ligado' then 'ligado' else 'sombra' end;
$function$;

comment on function public._agenda_modo_da_equipe() is 'Agenda de Produção (Fase 3, P4): ligado ou sombra (o modo em que a mensagem à equipe é gravada).';

-- Os contatos da rotina com plano (vigente, sem reserva) num dia.
create or replace function public._agenda_contatos_com_plano(p_dia date)
 returns setof uuid
 language sql
 stable
 set search_path to 'public'
as $function$
  select c.payee_id
    from public.agenda_equipe_contato c join public.payees p on p.id = c.payee_id
   where c.recebe_rotina and c.parou_em is null and p.active
     and exists (select 1 from public.agenda_alocacoes a
                  where a.payee_id = c.payee_id and a.dia = p_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva')
   order by c.payee_id;
$function$;

comment on function public._agenda_contatos_com_plano(date) is 'Agenda de Produção (Fase 3, P4): quem está na lista da rotina (recebe e não parou, ativo) e tem plano publicado no dia.';

-- 0. A fila velha: o que não saiu dentro da janela (o worker parado, a internet caída) não sai depois — vira falha e a
-- mensagem fica recusada por janela. A mensagem das 19:30 nunca chega às 22:00.
create or replace function public._agenda_rotina_fila(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_local timestamp := p_agora at time zone 'America/Sao_Paulo';
  v_ids   uuid[];
  v_modo  uuid[];
begin
  -- o modo saiu de ligado (o dono desligou ou voltou à sombra): o que ainda não saiu não sai mais
  if cf.modo_equipe <> 'ligado' then
    with x as (
      update public.whatsapp_send_queue q
         set status = 'failed', failed_reason = 'agenda-equipe: modo_equipe saiu de ligado'
       where q.source = 'agenda-equipe' and q.status = 'pending'
      returning q.id)
    select coalesce(array_agg(x.id), '{}') into v_modo from x;
    update public.agenda_equipe_mensagens m set estado = 'recusada', recusa_motivo = 'modo'
     where m.fila_id = any (v_modo) and m.estado = 'enfileirada';
  end if;
  -- (C1) o que já devia ter saído e agora não sai mais (a regra única da janela, com a da resposta direta); o que está
  -- marcado para depois (a resposta que vai no início da janela de amanhã) fica
  with x as (
    update public.whatsapp_send_queue q
       set status = 'failed', failed_reason = 'agenda-equipe: não saiu dentro da janela'
     where q.source = 'agenda-equipe' and q.status = 'pending' and q.scheduled_for <= p_agora
       and (not exists (select 1 from public.agenda_equipe_mensagens x0 where x0.id = q.source_ref_id)
            or exists (select 1 from public.agenda_equipe_mensagens x0
                        where x0.id = q.source_ref_id
                          and public._agenda_equipe_fora_da_janela(x0.tipo, x0.enviar_em, p_agora) is not null))
    returning q.id)
  select coalesce(array_agg(x.id), '{}') into v_ids from x;
  update public.agenda_equipe_mensagens m set estado = 'recusada', recusa_motivo = 'janela'
   where m.fila_id = any (v_ids) and m.estado = 'enfileirada';
  return jsonb_build_object('canceladas', cardinality(v_ids) + cardinality(coalesce(v_modo, '{}'::uuid[])),
                            'pelo_modo', cardinality(coalesce(v_modo, '{}'::uuid[])));
end;
$function$;

-- 1. A ficha da véspera (equipe_hora_ficha num dia útil): o próximo dia útil (de sexta, a segunda ou a terça depois do
-- feriado). Não vai a quem já recebeu a ficha desse dia nem a quem recebeu o "como foi hoje?" levando a ficha.
create or replace function public._agenda_rotina_ficha(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_local timestamp := p_agora at time zone 'America/Sao_Paulo';
  v_modo  text := public._agenda_modo_da_equipe();
  v_d     date;
  v_p     uuid;
  v_f     jsonb;
  v_r     jsonb;
  v_cont  jsonb := '{}'::jsonb;
begin
  if v_local::time < cf.equipe_hora_ficha or not public.agenda_dia_util(p_hoje) then
    return jsonb_build_object('fichas', 0);
  end if;
  v_d := public.agenda_somar_du(p_hoje, 1);
  for v_p in select x from public._agenda_contatos_com_plano(v_d) x loop
    continue when exists (select 1 from public.agenda_equipe_mensagens m
                           where m.payee_id = v_p and m.modo = v_modo
                             and ((m.tipo = 'ficha' and m.dia = v_d) or (m.tipo = 'como_foi' and m.leva_ficha_de = v_d)));
    v_f := public.agenda_equipe_ficha(v_p, v_d, p_hoje);
    continue when not coalesce((v_f ->> 'tem_plano')::boolean, false);
    v_r := public._agenda_equipe_registrar(v_p, v_d, 'ficha', v_f ->> 'texto_ficha', p_agora);
    v_cont := v_cont || jsonb_build_object(coalesce(v_r ->> 'estado', 'nada'),
                                           coalesce((v_cont ->> coalesce(v_r ->> 'estado', 'nada'))::int, 0) + 1);
  end loop;
  return jsonb_build_object('dia', v_d, 'por_estado', v_cont);
end;
$function$;

-- 2. A confirmação da manhã (equipe_hora_confirmar, antes de equipe_silencio_ate): só a quem não confirmou o dia.
create or replace function public._agenda_rotina_confirmar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_local timestamp := p_agora at time zone 'America/Sao_Paulo';
  v_modo  text := public._agenda_modo_da_equipe();
  v_p     uuid;
  v_f     jsonb;
  v_r     jsonb;
  v_cont  jsonb := '{}'::jsonb;
begin
  if v_local::time < cf.equipe_hora_confirmar or v_local::time >= cf.equipe_silencio_ate then
    return jsonb_build_object('confirmar', 0);
  end if;
  for v_p in select x from public._agenda_contatos_com_plano(p_hoje) x loop
    continue when exists (select 1 from public.agenda_disponibilidade d
                           where d.payee_id = v_p and d.substituida_em is null and d.situacao = 'confirmada'
                             and d.turno is null and d.periodo @> p_hoje);
    continue when exists (select 1 from public.agenda_equipe_mensagens m
                           where m.payee_id = v_p and m.modo = v_modo and m.tipo = 'confirmar' and m.dia = p_hoje);
    v_f := public.agenda_equipe_ficha(v_p, p_hoje, p_hoje);
    continue when not coalesce((v_f ->> 'tem_plano')::boolean, false);
    v_r := public._agenda_equipe_registrar(v_p, p_hoje, 'confirmar', v_f ->> 'texto_confirmar', p_agora);
    v_cont := v_cont || jsonb_build_object(coalesce(v_r ->> 'estado', 'nada'),
                                           coalesce((v_cont ->> coalesce(v_r ->> 'estado', 'nada'))::int, 0) + 1);
  end loop;
  return jsonb_build_object('por_estado', v_cont);
end;
$function$;

-- 3. O silêncio até equipe_silencio_ate: a confirmação que SAIU (a fila diz enviada há 30 min ou mais) e ficou sem
-- resposta, e nenhuma mensagem dele desde então (presença, "cheguei", ou o que for: mensagem não entendida não é silêncio)
-- → indisponível hoje, replano (modo_proposta ligado) e o acorde ao dono. Só em ligado (em sombra nada saiu).
create or replace function public._agenda_rotina_silencio(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_local timestamp := p_agora at time zone 'America/Sao_Paulo';
  m       record;
  v_os    uuid[];
  v_disp  uuid;
  v_rep   jsonb;
  v_nome  text;
  v_hora  text := to_char(cf.equipe_silencio_ate, 'FMHH24') || 'h'
                  || case when extract(minute from cf.equipe_silencio_ate) = 0 then '' else to_char(cf.equipe_silencio_ate, 'MI') end;
  v_n     int := 0;
  v_estado text;
  v_msg   text;
begin
  -- (a falta pelo silêncio só vale na manhã: depois do fim dela, o dia já é do "como foi hoje?")
  if cf.modo_equipe <> 'ligado' or v_local::time < cf.equipe_silencio_ate or v_local::time >= cf.manha_fim then
    return jsonb_build_object('silencio', 0);
  end if;
  for m in
    select x.*, p.phone from public.agenda_equipe_mensagens x
      join public.whatsapp_send_queue q on q.id = x.fila_id
      join public.payees p on p.id = x.payee_id
     where x.tipo = 'confirmar' and x.dia = p_hoje and x.modo = 'ligado' and x.estado = 'enfileirada' and x.resposta_em is null
       and q.status = 'sent' and q.sent_at <= p_agora - interval '30 minutes'
     order by x.enviar_em, x.id
  loop
    -- qualquer mensagem dele depois do envio: não é silêncio (o dono vê o trecho, se não foi entendido)
    continue when exists (select 1 from public.whatsapp_messages w
                           where w.direction = 'inbound' and w.created_at > m.enviar_em and w.created_at <= p_agora
                             and length(regexp_replace(coalesce(m.phone, ''), '\D', '', 'g')) >= 8
                             and right(regexp_replace(coalesce(w.phone_normalized, ''), '\D', '', 'g'), 8)
                                 = right(regexp_replace(m.phone, '\D', '', 'g'), 8));
    v_nome := (select public._agenda_nome_curto(p.name) from public.payees p where p.id = m.payee_id);
    v_os := array(select distinct a.service_order_id from public.agenda_alocacoes a
                   where a.payee_id = m.payee_id and a.dia = p_hoje and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                   order by 1);
    v_disp := null;
    v_rep := null;
    if not exists (select 1 from public.agenda_disponibilidade d
                    where d.payee_id = m.payee_id and d.substituida_em is null and d.situacao = 'indisponivel'
                      and d.turno is null and d.periodo @> p_hoje) then
      insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_em)
      values (m.payee_id, daterange(p_hoje, p_hoje, '[]'), 'indisponivel', 'agente',
              'Sem resposta à confirmação até ' || to_char(cf.equipe_silencio_ate, 'HH24:MI'), p_agora)
      returning id into v_disp;
    end if;
    if cf.modo_proposta = 'ligado' and cardinality(v_os) > 0 then
      begin
        v_rep := public.agenda_replanejar(v_os, 'equipe_faltou', 'vigia', p_hoje, p_agora, null);
      exception when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        perform public.log_app_error('db', 'agenda: replanejar pelo silêncio da equipe falhou: ' || v_msg, 'agenda',
                                     'rotina:silencio', 'error', jsonb_build_object('os', to_jsonb(v_os), 'sqlstate', v_estado));
      end;
    end if;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
    values (clock_timestamp(), p_hoje, true, 'equipe', 'equipe', v_os[1], v_os, m.payee_id,
            jsonb_build_object('motivo', 'silencio', 'dia', p_hoje, 'disponibilidade', v_disp, 'mensagem', m.id,
                               'replano_acoes', coalesce(v_rep -> 'acoes', '[]'::jsonb), 'acorde', true),
            left(format('O %s não respondeu à confirmação de hoje até as %s.', v_nome, v_hora)
                 || coalesce(' ' || nullif(v_rep ->> 'texto', ''), ''), 400));
    update public.agenda_equipe_mensagens set estado = 'sem_resposta' where id = m.id;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('silencio', v_n);
end;
$function$;

-- 4. O "como foi hoje?" (equipe_hora_como_foi): a quem teve plano hoje. No dia em que a confirmação da manhã saiu, ele
-- leva a ficha de amanhã (e as 19:30 não mandam nada): são 3 horários e o teto é 2 (d10).
create or replace function public._agenda_rotina_como_foi(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_local timestamp := p_agora at time zone 'America/Sao_Paulo';
  v_modo  text := public._agenda_modo_da_equipe();
  v_d     date := public.agenda_somar_du(p_hoje, 1);
  v_p     uuid;
  v_f     jsonb;
  v_fd    jsonb;
  v_leva  boolean;
  v_r     jsonb;
  v_cont  jsonb := '{}'::jsonb;
begin
  if v_local::time < cf.equipe_hora_como_foi then
    return jsonb_build_object('como_foi', 0);
  end if;
  for v_p in select x from public._agenda_contatos_com_plano(p_hoje) x loop
    continue when exists (select 1 from public.agenda_equipe_mensagens m
                           where m.payee_id = v_p and m.modo = v_modo and m.tipo = 'como_foi' and m.dia = p_hoje);
    v_f := public.agenda_equipe_ficha(v_p, p_hoje, p_hoje);
    continue when not coalesce((v_f ->> 'tem_plano')::boolean, false);
    v_leva := exists (select 1 from public.agenda_equipe_mensagens m
                       where m.payee_id = v_p and m.modo = v_modo and m.tipo = 'confirmar' and m.dia = p_hoje
                         and m.estado <> 'recusada')
              and not exists (select 1 from public.agenda_equipe_mensagens m
                               where m.payee_id = v_p and m.modo = v_modo and m.tipo = 'ficha' and m.dia = v_d);
    v_fd := case when v_leva then public.agenda_equipe_ficha(v_p, v_d, p_hoje) end;
    v_leva := v_leva and coalesce((v_fd ->> 'tem_plano')::boolean, false);
    v_r := public._agenda_equipe_registrar(v_p, p_hoje, 'como_foi',
             (v_f ->> 'texto_como_foi') || case when v_leva then ' ' || (v_fd ->> 'texto_curto') else '' end,
             p_agora, case when v_leva then v_d end);
    v_cont := v_cont || jsonb_build_object(coalesce(v_r ->> 'estado', 'nada'),
                                           coalesce((v_cont ->> coalesce(v_r ->> 'estado', 'nada'))::int, 0) + 1);
  end loop;
  return jsonb_build_object('por_estado', v_cont);
end;
$function$;

-- 5. Sem resposta: o que passou de equipe_resposta_validade sem resposta.
create or replace function public._agenda_rotina_sem_resposta(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf  public.agenda_config := public._agenda_cfg();
  v_n int;
begin
  update public.agenda_equipe_mensagens m set estado = 'sem_resposta'
   where m.tipo <> 'resposta' and m.estado = 'enfileirada' and m.resposta_em is null
     and m.enviar_em + cf.equipe_resposta_validade < p_agora;
  get diagnostics v_n = row_count;
  return jsonb_build_object('sem_resposta', v_n);
end;
$function$;

-- 6. O acorde da equipe: o "não vou" (que chegou pelo webhook) e o silêncio que mudaram hoje ou amanhã. A mudança já foi
-- feita (o replano); aqui só o aviso ao dono, no mesmo envio da vigia (cota acordes_dia_max).
create or replace function public._agenda_rotina_acordes_da_equipe(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  r        record;
  v_rep    uuid;
  v_nome   text;
  v_txt    text;
  v_acordes jsonb := '[]'::jsonb;
begin
  for r in
    select e.* from public.agenda_acoes e
     where e.tipo = 'equipe' and e.executada and e.contada_em is null and coalesce((e.depois ->> 'acorde')::boolean, false)
       and e.dia >= p_hoje - 1
       and (e.depois ->> 'dia')::date between p_hoje and public.agenda_somar_du(p_hoje, cf.congelamento_du)
     order by e.criada_em, e.id
  loop
    -- a mudança que o replano fez (a 1ª executada); o acorde sai uma vez (a mudança ou o aviso contados)
    select a.id into v_rep from public.agenda_acoes a
     where a.id in (select (x #>> '{}')::uuid from jsonb_array_elements(coalesce(r.depois -> 'replano_acoes', '[]'::jsonb)) x)
       and a.executada
     order by a.criada_em, a.id limit 1;
    continue when exists (select 1 from public.agenda_acoes a
                           where a.contada_via = 'acorde'
                             and (a.id = v_rep or a.id in (select (x #>> '{}')::uuid
                                                              from jsonb_array_elements(coalesce(r.depois -> 'replano_acoes', '[]'::jsonb)) x)));
    v_nome := (select public._agenda_nome_curto(p.name) from public.payees p where p.id = r.payee_id);
    v_txt := case r.depois ->> 'motivo'
               when 'silencio' then split_part(r.texto, '.', 1) || '.'
               else format('O %s avisou que não vem %s.', v_nome, public._agenda_dia_da_equipe((r.depois ->> 'dia')::date, p_hoje)) end
             || case when v_rep is not null then ' ' || public._agenda_texto_do_acorde(v_rep, (r.depois ->> 'dia')::date, p_hoje)
                     else ' A agenda automática não está ligada: reveja o dia dele.' end;
    v_acordes := v_acordes || jsonb_build_object('chave', 'agenda:' || coalesce(v_rep, r.id), 'assunto', 'equipe:' || r.payee_id,
                   'acao_id', coalesce(v_rep, r.id), 'os', r.service_order_id, 'perda_em', r.depois ->> 'dia', 'texto', v_txt);
  end loop;
  return jsonb_build_object('acordes_da_equipe', jsonb_array_length(v_acordes), 'acordes', v_acordes);
end;
$function$;

-- 7. As diárias (modo_diaria): (pessoa, dia) dos últimos diaria_janela_dias com plano e sem a diária tratada.
create or replace function public._agenda_rotina_diarias(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  r      record;
  v_r    jsonb;
  v_cont jsonb := '{}'::jsonb;
begin
  for r in
    select distinct a.payee_id, a.dia
      from public.agenda_alocacoes a join public.payees p on p.id = a.payee_id
     where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and p.kind <> 'socio'
       and a.dia between p_hoje - cf.diaria_janela_dias and p_hoje
       and exists (select 1 from public.work_profiles w
                    where w.payee_id = a.payee_id and w.modo_pagamento = 'diaria' and w.vigencia_inicio <= a.dia
                      and (w.vigencia_fim is null or w.vigencia_fim >= a.dia))
     order by a.dia, a.payee_id
  loop
    v_r := public._agenda_diaria_do_dia(r.payee_id, r.dia, 'rotina', p_hoje, p_agora);
    v_cont := v_cont || jsonb_build_object(v_r ->> 'status', coalesce((v_cont ->> (v_r ->> 'status'))::int, 0) + 1);
  end loop;
  return jsonb_build_object('por_status', v_cont);
end;
$function$;

-- 8. O resultado pela diária (repescagem; modo_proposta ligado): a diária lançada depois (pelo dono) preenche o
-- resultado do meio-dia que ficou sem resultado ou "sem registro": dia inteiro → os turnos dela cumpridos; meia com 1
-- turno no plano → cumprido; falta → não cumprido (equipe); meia com 2 turnos → nada (qual turno?).
create or replace function public._agenda_rotina_resultado_pela_diaria(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  r      record;
  v_res  text;
  v_ids  uuid[];
  v_os   uuid;
  v_n    int := 0;
begin
  perform set_config('agenda.hoje', p_hoje::text, true);
  for r in
    select a.payee_id, a.dia, ws.id as ws_id, ws.fracao, ws.data,
           array_agg(a.id order by a.turno = 'tarde', a.id) as alocs,
           (select count(*) from public.agenda_alocacoes b
             where b.payee_id = a.payee_id and b.dia = a.dia and b.estado in ('publicada', 'fixada') and b.tipo <> 'reserva') as n_plano
      from public.agenda_alocacoes a
      join public.work_profiles wp on wp.payee_id = a.payee_id and wp.modo_pagamento = 'diaria'
      join public.work_shifts ws on ws.work_profile_id = wp.id and ws.data = a.dia and ws.fracao is not null
     where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia <= p_hoje and lower(a.periodo) <= p_agora
       and (a.resultado is null or a.resultado = 'sem_registro')
       and (ws.fracao = 0 or exists (select 1 from public.work_shift_os wo
                                      where wo.shift_id = ws.id and wo.service_order_id = a.service_order_id))
     group by a.payee_id, a.dia, ws.id, ws.fracao, ws.data
  loop
    v_res := case when r.fracao = 1 then 'cumprido' when r.fracao = 0.5 and r.n_plano = 1 then 'cumprido'
                  when r.fracao = 0 then 'nao_cumprido' end;
    continue when v_res is null;
    with x as (
      update public.agenda_alocacoes a
         set resultado = v_res, motivo = case when v_res = 'nao_cumprido' then 'equipe_faltou' end, resultado_em = p_agora,
             resultado_via = 'sistema', resultado_trecho = 'diária lançada em ' || public._dia_curto(r.data),
             work_shift_id = case when r.fracao > 0 then r.ws_id else a.work_shift_id end
       where a.id = any (r.alocs)
      returning a.id, a.service_order_id)
    select coalesce(array_agg(x.id), '{}') into v_ids from x;
    for v_os in select distinct a.service_order_id from public.agenda_alocacoes a where a.id = any (v_ids) loop
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, work_shift_id,
                                       depois, texto)
      values (clock_timestamp(), p_hoje, true, 'sistema', 'resultado', v_os, array[v_os], r.payee_id, r.ws_id,
              jsonb_build_object('resultado', v_res, 'via', 'sistema', 'dia', r.dia,
                                 'alocacoes', to_jsonb(array(select a.id from public.agenda_alocacoes a
                                                              where a.id = any (v_ids) and a.service_order_id = v_os order by a.id))),
              left(format('%s, %s: %s pela diária lançada.', public._agenda_rotulo_da_os(v_os), public._dia_curto(r.dia),
                          case when v_res = 'cumprido' then 'feito' else 'não andou (equipe)' end), 400));
    end loop;
    v_n := v_n + cardinality(v_ids);
  end loop;
  return jsonb_build_object('alocacoes', v_n);
end;
$function$;

-- 9. A conclusão pelo técnico (equipe ligada; modo_proposta ligado conclui, sombra só registra): ele disse que terminou
-- hoje E o plano não tem mais dia para a OS (sem meio-dia vigente depois de hoje e nada restando) → a porta (via equipe,
-- desfazível). Um sinal só = a pergunta "concluir" (não crítica). Nunca por silêncio, hora ou inferência.
create or replace function public._agenda_rotina_conclusao(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  m       record;
  v_os    uuid[];
  v_x     uuid;
  v_st    text;
  v_fut   date[];
  v_rest  numeric;
  v_r     jsonb;
  v_acao  uuid;
  v_nome  text;
  v_cli   text;
  v_conc  int := 0;
  v_perg  int := 0;
begin
  for m in
    select x.* from public.agenda_equipe_mensagens x
     where x.tipo = 'como_foi' and x.modo = 'ligado' and x.dia = p_hoje and x.acao_id is null
       and coalesce((x.leitura ->> 'terminou')::boolean, false)
     order by x.resposta_em, x.id
  loop
    v_os := array(select distinct a.service_order_id from public.agenda_alocacoes a
                   where a.payee_id = m.payee_id and a.dia = p_hoje and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva');
    continue when cardinality(v_os) <> 1;
    v_x := v_os[1];
    select so.status into v_st from public.service_orders so where so.id = v_x;
    continue when v_st not in ('open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client');
    v_nome := (select public._agenda_nome_curto(p.name) from public.payees p where p.id = m.payee_id);
    v_cli := (select public._agenda_nome_curto(cl.name) from public.service_orders so join public.clients cl on cl.id = so.client_id
               where so.id = v_x);
    v_fut := array(select distinct a.dia from public.agenda_alocacoes a
                    where a.service_order_id = v_x and a.dia > p_hoje and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                    order by 1);
    v_rest := (public.agenda_meios_da_os(v_x, p_hoje + 1) ->> 'restantes')::numeric;
    if cardinality(v_fut) = 0 and v_rest = 0 then
      if cf.modo_proposta = 'ligado' then
        v_r := public.os_registrar_marco(v_x, 'conclusao', 'equipe', null, null,
                                         left(format('O %s disse que terminou: "%s"', v_nome, m.resposta_texto), 200), p_hoje, p_agora);
        if coalesce((v_r ->> 'ok')::boolean, false) and v_r ->> 'acao_id' is not null then
          update public.agenda_equipe_mensagens set acao_id = (v_r ->> 'acao_id')::uuid where id = m.id;
          v_conc := v_conc + 1;
        else
          -- a porta recusou (o período fechado, o levantamento…): a pergunta, com a frase dela
          perform public._agenda_equipe_perguntar('concluir', format('concluir:%s:%s', v_x, p_hoje), m.payee_id, v_x, p_hoje,
            format('O %s disse que terminou o %s, mas não concluí: %s', v_nome, public._agenda_rotulo_da_os(v_x),
                   coalesce(v_r ->> 'texto', 'a porta recusou.')), 'ligado', p_agora);
          v_perg := v_perg + 1;
        end if;
      else
        insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
        values (clock_timestamp(), p_hoje, false, 'equipe', 'concluir', v_x, array[v_x], m.payee_id,
                jsonb_build_object('mensagem', m.id),
                left(format('Em teste: concluiria o %s (o %s disse que terminou e era o último dia do plano).',
                            public._agenda_rotulo_da_os(v_x), v_nome), 400))
        returning id into v_acao;
        update public.agenda_equipe_mensagens set acao_id = v_acao where id = m.id;
        v_conc := v_conc + 1;
      end if;
    else
      if public._agenda_equipe_perguntar('concluir', format('concluir:%s:%s', v_x, p_hoje), m.payee_id, v_x, p_hoje,
           format('O %s disse que terminou o %s, mas o plano tinha mais %s. *concluiu %s* fecha a OS.', v_nome,
                  public._agenda_rotulo_da_os(v_x),
                  case when cardinality(v_fut) > 0
                       then public._agenda_plural(cardinality(v_fut), 'dia', 'dias') || ' (' || public._agenda_dias_texto(v_fut) || ')'
                       else 'serviço do que você disse' end,
                  coalesce(v_cli, (select so.service_order_number from public.service_orders so where so.id = v_x))),
           'ligado', p_agora) then
        v_perg := v_perg + 1;
      end if;
    end if;
  end loop;
  return jsonb_build_object('concluidas', v_conc, 'perguntas', v_perg);
end;
$function$;

-- 10. A entrega pendente (modo_vigia): a OS concluída pela porta da agenda (Fase 3) há entrega_aviso_du dias úteis sem
-- entrega → uma pergunta por OS. As 21 conclusões de antes da Fase 3 não entram (nenhuma tem a entrega: a coluna é nova).
create or replace function public._agenda_rotina_entrega(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf  public.agenda_config := public._agenda_cfg();
  r   record;
  v_n int := 0;
begin
  for r in
    select so.id, so.service_order_number as numero, so.check_out_at, public._agenda_nome_curto(cl.name) as cliente
      from public.service_orders so left join public.clients cl on cl.id = so.client_id
     where so.status = 'completed' and so.delivered_at is null and so.check_out_at is not null
       and exists (select 1 from public.agenda_acoes a
                    where a.service_order_id = so.id and a.tipo = 'concluir' and a.executada and a.desfeita_em is null)
       and public.agenda_du_entre((so.check_out_at at time zone 'America/Sao_Paulo')::date, p_hoje) >= cf.entrega_aviso_du
     order by so.check_out_at, so.id
  loop
    if public._agenda_vigia_perguntar('entrega', 'entrega:' || r.id, r.id, null, null, p_hoje,
         format('A %s%s está concluída desde %s e não tem entrega. Já entregou? *entreguei %s*.', r.numero,
                coalesce(' (' || r.cliente || ')', ''), public._dia_curto((r.check_out_at at time zone 'America/Sao_Paulo')::date),
                coalesce(r.cliente, r.numero)),
         case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end, p_agora, true) then
      v_n := v_n + 1;
    end if;
  end loop;
  return jsonb_build_object('perguntas', v_n);
end;
$function$;

-- A rotina: um tique (o task-automations a chama logo antes da vigia).
create or replace function public.agenda_rotina_rodar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_passos      constant text[] := array['ficha', 'confirmar', 'silencio', 'como_foi', 'sem_resposta',
                                         'acordes_da_equipe', 'diarias', 'resultado_pela_diaria', 'conclusao', 'entrega'];
  c_da_equipe   constant text[] := array['ficha', 'confirmar', 'silencio', 'como_foi', 'sem_resposta', 'acordes_da_equipe'];
  c_do_dia_util constant text[] := array['ficha', 'confirmar', 'silencio', 'como_foi'];
  cf        public.agenda_config;
  v_t0      timestamptz := clock_timestamp();
  v_passo   text;
  v_r       jsonb;
  v_cont    jsonb := '{}'::jsonb;
  v_erros   int := 0;
  v_falhas  jsonb := '[]'::jsonb;
  v_acordes jsonb := '[]'::jsonb;
  v_cota    int;
  v_estado  text;
  v_msg     text;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da rotina.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  cf := public._agenda_cfg();
  -- A fila velha roda SEMPRE, em qualquer modo (até desligado): o que não saiu na janela, ou ficou na fila quando o dono
  -- desligou a equipe, não sai mais. Só mexe em linha source agenda-equipe; não grava a rodada.
  begin
    v_cont := jsonb_build_object('fila', public._agenda_rotina_fila(p_hoje, p_agora));
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    v_erros := v_erros + 1;
    v_falhas := v_falhas || jsonb_build_object('passo', 'fila', 'sqlstate', v_estado, 'erro', left(v_msg, 300));
    perform public.log_app_error('db', 'rotina da agenda, passo fila: ' || v_msg, 'agenda', 'rotina:fila', 'error',
                                 jsonb_build_object('passo', 'fila', 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
  end;
  if cf.modo_equipe = 'desligado' and cf.modo_diaria = 'desligado' then
    return jsonb_build_object('rodou', false, 'modos', jsonb_build_object('equipe', cf.modo_equipe, 'diaria', cf.modo_diaria),
                              'acordes', '[]'::jsonb, 'fila', v_cont -> 'fila');
  end if;

  foreach v_passo in array c_passos loop
    continue when v_passo = any (c_da_equipe) and cf.modo_equipe = 'desligado';
    -- domingo: nada à equipe
    continue when v_passo = any (c_do_dia_util) and extract(isodow from p_hoje) = 7;
    continue when v_passo = 'diarias' and cf.modo_diaria = 'desligado';
    continue when v_passo = 'resultado_pela_diaria' and cf.modo_proposta <> 'ligado';
    continue when v_passo = 'conclusao' and (cf.modo_equipe <> 'ligado' or cf.modo_proposta = 'desligado');
    continue when v_passo = 'entrega' and cf.modo_vigia = 'desligado';
    begin
      execute format('select public.%I($1, $2)', '_agenda_rotina_' || v_passo) into v_r using p_hoje, p_agora;
      v_acordes := v_acordes || coalesce(v_r -> 'acordes', '[]'::jsonb);
      v_cont := v_cont || jsonb_build_object(v_passo, coalesce(v_r, '{}'::jsonb) - 'acordes');
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_erros := v_erros + 1;
      v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
      perform public.log_app_error('db', format('rotina da agenda, passo %s: %s', v_passo, v_msg), 'agenda', 'rotina:' || v_passo,
                                   'error', jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje,
                                                               'p_agora', p_agora));
    end;
  end loop;

  -- Os acordes: como os da vigia — só com a vigia ligada e a ação executada, na cota acordes_dia_max do dia.
  if cf.modo_vigia = 'ligado' and jsonb_array_length(v_acordes) > 0 then
    v_cota := greatest(cf.acordes_dia_max - (select count(*)::int from public.agenda_acoes a
                                              where a.dia = p_hoje and a.contada_via = 'acorde'), 0);
    select coalesce(jsonb_agg(q.e order by q.ord), '[]'::jsonb) into v_acordes
      from (select e, row_number() over (order by (e ->> 'perda_em')::date nulls last, e ->> 'chave') as ord
              from jsonb_array_elements(v_acordes) e
             where exists (select 1 from public.agenda_acoes a where a.id = (e ->> 'acao_id')::uuid and a.executada)) q
     where q.ord <= v_cota;
  else
    v_acordes := '[]'::jsonb;
  end if;

  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms,
                                           rotina, modo_equipe, modo_diaria)
  values (clock_timestamp(), p_hoje, p_agora, cf.modo_proposta, cf.modo_vigia,
          v_cont || jsonb_build_object('acordes', jsonb_array_length(v_acordes), 'falhas', v_falhas),
          least(v_erros, 32767), greatest(0, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int),
          'rotina', cf.modo_equipe, cf.modo_diaria);

  return jsonb_build_object('rodou', true,
                            'modos', jsonb_build_object('proposta', cf.modo_proposta, 'vigia', cf.modo_vigia,
                                                        'equipe', cf.modo_equipe, 'diaria', cf.modo_diaria),
                            'contagens', v_cont, 'erros', v_erros, 'falhas', v_falhas, 'acordes', v_acordes);
end;
$function$;

comment on function public.agenda_rotina_rodar(date, timestamptz) is
  'Agenda de Produção (Fase 3, P4): a rotina da equipe e da diária, a cada 15 min, logo antes da vigia (task-automations). modo_equipe e modo_diaria desligados = {rodou: false}. Antes de tudo, em qualquer modo, a fila velha (o que não saiu na janela, ou ficou na fila com a equipe fora de ligado, vira falha). Passos, cada um no seu bloco (o que falha vai para app_error_logs, context agenda, action rotina:<passo>, e os outros rodam): ficha (equipe_hora_ficha, num dia útil, do próximo dia útil); confirmar (equipe_hora_confirmar, só a quem não confirmou); silencio (equipe_silencio_ate: a confirmação enviada sem resposta nem mensagem dele → indisponível, replano e acorde; só em ligado); como_foi (equipe_hora_como_foi; leva a ficha de amanhã no dia em que a confirmação saiu); sem_resposta; acordes_da_equipe (o "não vou" e o silêncio de hoje/amanhã); diarias (modo_diaria); resultado_pela_diaria (modo_proposta ligado: a diária lançada depois preenche o resultado); conclusao (o técnico disse que terminou e era o último dia → a porta via equipe; um sinal só = a pergunta); entrega (modo_vigia: concluída pela agenda há entrega_aviso_du sem entrega). Domingo: nada à equipe. Uma linha em agenda_vigia_rodadas (rotina = rotina). {rodou, modos, contagens, erros, falhas, acordes} — os acordes só com a vigia ligada, na cota acordes_dia_max. Só service_role.';

-- ── 6. As funções das Fases 2 e 3 recriadas (o corpo da definição mais nova; as mudanças marcadas -- FASE 3:) ──

-- agenda_registrar_dia: corpo de 20261025100300 (a única que a define).
create or replace function public.agenda_registrar_dia(p_autor uuid, p_dia date, p_resultado text, p_motivo text default null,
                                                       p_os uuid default null, p_pessoas uuid[] default null,
                                                       p_via text default 'dia_feito', p_trecho text default null,
                                                       p_hoje date default public._hoje_brt(), p_agora timestamptz default now(),
                                                       p_canal text default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor   uuid;
  v_motivo  text;
  v_alvo    uuid[];
  v_mudou   uuid[];
  v_oss     uuid[];
  v_antes   jsonb;
  v_os      uuid;
  v_mov     uuid[] := '{}';
  v_and     text[] := '{}';
  v_partes  text[] := '{}';
  v_acoes   uuid[] := '{}';
  v_acao    uuid;
  v_check   timestamptz;
  v_porta   jsonb;
  v_rep     jsonb;
  v_txt     text;
  v_ref     text;
  v_resp    text;
  v_estado  text;
  v_msg     text;
  -- FASE 3: a diária do dia, a entrega conferida e a intervenção do dono
  v_dono    uuid;
  v_interv  boolean := false;
  v_itxt    text;
  v_lanc    text[] := '{}';
  v_somb    text[] := '{}';
  v_ult     jsonb;
  v_dr      jsonb;
  v_p       uuid;
  v_ent     record;
begin
  -- FASE 3: o técnico (p_via equipe, pela resposta dele ao "como foi hoje?") não é administrador: só sem login (service
  -- role), só nas alocações dele (uma pessoa) e sem autor. Os outros caminhos continuam com o administrador.
  if p_via = 'equipe' then
    if auth.uid() is not null or coalesce(cardinality(p_pessoas), 0) <> 1 then
      raise exception 'Só a resposta do técnico anota o dia pela equipe.' using errcode = '42501';
    end if;
    v_autor := null;
  else
    v_autor := public._autor_da_agenda(p_autor);
  end if;
  if p_resultado is null or p_resultado not in ('cumprido', 'parcial', 'nao_cumprido') then
    raise exception 'Resultado desconhecido: "%" (cumprido, parcial ou nao_cumprido).', coalesce(p_resultado, '') using errcode = '22023';
  end if;
  -- FASE 3: equipe (a resposta do técnico).
  if p_via is null or p_via not in ('dia_feito', 'conversa', 'tela', 'equipe') then
    raise exception 'Caminho desconhecido para anotar o dia: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  if p_dia is null or p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia, a data de hoje ou a hora.' using errcode = '22023';
  end if;
  v_motivo := public._agenda_motivo_dito(p_motivo);
  if p_resultado in ('parcial', 'nao_cumprido') and v_motivo is null then
    return jsonb_build_object('ok', false, 'mudou', false, 'pede', 'motivo', 'texto', public._agenda_ajuda_do_motivo(p_resultado));
  end if;
  if p_dia > p_hoje then
    return jsonb_build_object('ok', false, 'mudou', false,
      'texto', public._agenda_maiuscula(public._dia_curto(p_dia)) || ' ainda não chegou: não dá para dizer como foi.');
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  v_ref := public._agenda_dia_ref(p_dia, p_hoje);
  v_resp := case when p_via = 'tela' then 'tela' when p_canal in ('whatsapp', 'painel', 'tela') then p_canal else 'whatsapp' end;

  -- O alvo: os meio-dias vigentes (sem reserva) do dia; cumprido e parcial só o que já começou.
  v_alvo := array(select a.id from public.agenda_alocacoes a
                   where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = p_dia
                     and (p_os is null or a.service_order_id = p_os)
                     and (p_pessoas is null or a.payee_id = any (p_pessoas))
                     and (p_resultado = 'nao_cumprido' or lower(a.periodo) <= p_agora)
                     -- FASE 3: pela equipe, só os turnos que o técnico confirmou (agenda.turnos_equipe, posto na mesma
                     -- transação por agenda_resposta_da_equipe)
                     and (p_via <> 'equipe' or coalesce(current_setting('agenda.turnos_equipe', true), '') = ''
                          or a.turno = any (string_to_array(current_setting('agenda.turnos_equipe', true), ',')))
                   order by a.service_order_id, a.turno = 'tarde', a.payee_id, a.id);
  -- FASE 3: o dono foi a uma OS sem estar no plano dela no dia ("eu fui no Lenine"): a intervenção dele fica registrada
  -- (agenda_intervencoes_do_dono, o insumo da presença aprendida das OS parecidas). Nada muda no plano nem na diária.
  if p_os is not null and p_resultado in ('cumprido', 'parcial') and p_via in ('dia_feito', 'conversa', 'tela') then
    v_dono := public._agenda_dono(v_autor);
    if v_dono is not null and v_dono = any (coalesce(p_pessoas, '{}'::uuid[]))
       and not exists (select 1 from public.agenda_alocacoes a
                        where a.service_order_id = p_os and a.dia = p_dia and a.estado in ('publicada', 'fixada')
                          and a.tipo <> 'reserva' and a.payee_id = v_dono) then
      insert into public.agenda_intervencoes_do_dono (service_order_id, dia, prevista, dita, classe, origem, trecho, autor, criado_em)
      values (p_os, p_dia, 'nenhuma', 'passou',
              case public.os_presenca_do_dono(p_os) ->> 'motivo' when 'diagnóstico' then 'diagnostico'
                   when 'comissionamento' then 'comissionamento' when 'marina nova' then 'marina_nova' else 'execucao' end,
              case p_via when 'dia_feito' then 'conferencia' when 'tela' then 'tela' else 'conversa' end,
              left(nullif(btrim(coalesce(p_trecho, '')), ''), 300), v_autor, p_agora)
      on conflict (service_order_id, dia, origem) do nothing;
      v_interv := true;
      v_itxt := format('Anotei que você foi ao %s sem estar no plano: isso ajusta a sua presença nas OS parecidas.',
                       coalesce(public._agenda_nome_curto((select cl.name from public.service_orders so
                                                             join public.clients cl on cl.id = so.client_id where so.id = p_os)),
                                public._agenda_rotulo_da_os(p_os)));
    end if;
  end if;
  if cardinality(v_alvo) = 0 and v_interv then
    return jsonb_build_object('ok', true, 'mudou', true, 'dia', p_dia, 'texto', v_itxt, 'alocacoes', 0, 'acoes', '[]'::jsonb,
                              'intervencao', true);
  end if;
  -- FASE 3: fim
  if cardinality(v_alvo) = 0 then
    return jsonb_build_object('ok', false, 'mudou', false, 'dia', p_dia,
      'texto', case
        when exists (select 1 from public.agenda_alocacoes a
                      where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = p_dia
                        and (p_os is null or a.service_order_id = p_os) and (p_pessoas is null or a.payee_id = any (p_pessoas)))
          then format('Ainda não começou nada do plano %s.', v_ref)
        when p_os is not null then format('%s não estava no plano %s.', public._agenda_rotulo_da_os(p_os), v_ref)
        else format('Não tinha nada do plano %s.', v_ref) end);
  end if;

  -- Como estava (para a ação) e o que muda (o mesmo resultado de novo não muda nada).
  select coalesce(jsonb_object_agg(q.os, q.alocs), '{}'::jsonb) into v_antes
    from (select a.service_order_id::text as os,
                 jsonb_agg(jsonb_build_object('alocacao_id', a.id, 'payee_id', a.payee_id, 'dia', a.dia, 'turno', a.turno,
                                              'presenca', a.presenca, 'resultado', a.resultado, 'motivo', a.motivo)
                           order by a.turno = 'tarde', a.payee_id, a.id) as alocs
            from public.agenda_alocacoes a where a.id = any (v_alvo) group by a.service_order_id) q;
  with mud as (
    update public.agenda_alocacoes a
       set resultado = p_resultado, motivo = v_motivo, resultado_em = p_agora, resultado_via = p_via,
           resultado_por = v_autor, resultado_trecho = left(nullif(btrim(coalesce(p_trecho, '')), ''), 300)
     where a.id = any (v_alvo) and (a.resultado is distinct from p_resultado or a.motivo is distinct from v_motivo)
     returning a.id, a.service_order_id)
  select coalesce(array_agg(m.id order by m.id), '{}'::uuid[]),
         coalesce(array_agg(distinct m.service_order_id), '{}'::uuid[])
    into v_mudou, v_oss
    from mud m;

  if cardinality(v_mudou) = 0 then
    return jsonb_build_object('ok', true, 'mudou', false, 'dia', p_dia,
      'texto', format('Já estava anotado %s: %s %s.', v_ref,
                      public._agenda_lista(array(select public._agenda_rotulo_da_os(x)
                                                   from unnest((select array_agg(distinct a.service_order_id)
                                                                  from public.agenda_alocacoes a where a.id = any (v_alvo))) x
                                                  order by 1), null),
                      case p_resultado when 'cumprido' then 'feito'
                                       when 'parcial' then 'em parte (' || public._agenda_motivo_texto(v_motivo) || ')'
                                       else 'não andou (' || public._agenda_motivo_texto(v_motivo) || ')' end));
  end if;

  -- Por OS: a ação (resultado), o início pela porta e o espelho.
  for v_os in select x from unnest(v_oss) x
               order by (select so.service_order_number from public.service_orders so where so.id = x) collate "C", x loop
    v_txt := format('%s, %s: %s.', public._agenda_rotulo_da_os(v_os), public._dia_curto(p_dia),
                    case p_resultado when 'cumprido' then 'feito'
                                     when 'parcial' then 'andou em parte (' || public._agenda_motivo_texto(v_motivo) || ')'
                                     else 'não andou (' || public._agenda_motivo_texto(v_motivo) || ')' end);
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto,
                                     motivo, autor)
    -- FASE 3: a resposta do técnico tem a origem dela (equipe).
    values (clock_timestamp(), p_hoje, true, case when p_via = 'equipe' then 'equipe' else 'conferencia' end, 'resultado', v_os, array[v_os],
            jsonb_build_object('alocacoes', coalesce(v_antes -> v_os::text, '[]'::jsonb)),
            jsonb_build_object('resultado', p_resultado, 'motivo', v_motivo, 'via', p_via, 'dia', p_dia,
                               'alocacoes', to_jsonb(array(select a.id from public.agenda_alocacoes a
                                                            where a.id = any (v_mudou) and a.service_order_id = v_os order by a.id))),
            left(v_txt, 400), v_motivo, v_autor)
    returning id into v_acao;
    v_acoes := v_acoes || v_acao;

    if p_resultado in ('cumprido', 'parcial')
       and (select so.status from public.service_orders so where so.id = v_os)
           in ('open', 'approved', 'scheduled', 'awaiting_parts', 'awaiting_client') then
      -- o início é a hora do 1º meio-dia dela no dia (o banco deriva; ninguém grava hora dita)
      select min(lower(a.periodo)) into v_check
        from public.agenda_alocacoes a
       where a.service_order_id = v_os and a.dia = p_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva';
      -- FASE 3: pela equipe a porta é a da equipe (sem autor, como motor e vigia).
      v_porta := public.os_transicionar_status(v_os, 'in_progress', case when p_via = 'equipe' then 'equipe' else 'conferencia' end,
                                               null, v_autor, v_check, p_hoje, p_agora);
      if coalesce((v_porta ->> 'mudou')::boolean, false) then
        v_and := v_and || public._agenda_nome_curto((select cl.name from public.service_orders so
                                                      join public.clients cl on cl.id = so.client_id where so.id = v_os));
      end if;
    end if;
    perform public._agenda_espelhar_datas(v_os, p_hoje);
    if p_resultado in ('parcial', 'nao_cumprido') then
      v_mov := v_mov || v_os;
    end if;
    v_partes := v_partes || case
      when p_resultado = 'cumprido' then format('%s feito, com %s', public._agenda_rotulo_da_os(v_os), public._agenda_quem(v_os, p_dia, v_alvo))
      when p_resultado = 'parcial' then format('%s andou em parte (%s)', public._agenda_rotulo_da_os(v_os), public._agenda_motivo_texto(v_motivo))
      when v_motivo = 'clima' then coalesce(public._agenda_nome_curto((select cl.name from public.service_orders so
                                                                         join public.clients cl on cl.id = so.client_id where so.id = v_os)),
                                            public._agenda_rotulo_da_os(v_os))
      else public._agenda_rotulo_da_os(v_os) end;
  end loop;

  -- A conferência do dia fica respondida quando nada do que começou ficou sem resultado.
  update public.agenda_perguntas q
     set estado = 'respondida', respondida_em = p_agora, respondida_por = v_autor, respondida_via = v_resp,
         resposta = left(nullif(btrim(coalesce(p_trecho, '')), ''), 500)
   where q.tipo = 'conferencia' and q.dia = p_dia and q.estado = 'aberta'
     and not exists (select 1 from public.agenda_alocacoes a
                      where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = p_dia
                        and a.resultado is null and lower(a.periodo) <= p_agora);

  -- Parcial e não cumprido: replaneja na mesma transação. Se o motor falhar, o resultado fica e a vigia tenta de novo.
  if cardinality(v_mov) > 0 then
    begin
      -- FASE 3: o "não fui" do técnico replaneja como a vigia (a agenda age sozinha, sem autor).
      v_rep := public.agenda_replanejar(v_mov, v_motivo, case when p_via = 'equipe' then 'vigia' else 'conferencia' end,
                                        p_hoje, p_agora, v_autor);
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      perform public.log_app_error('db', 'agenda: replanejar depois da conferência falhou: ' || v_msg, 'agenda',
                                   'conferencia:replanejar', 'error',
                                   jsonb_build_object('os', to_jsonb(v_mov), 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
      v_rep := jsonb_build_object('ok', false, 'texto', 'Não consegui replanejar agora; eu tento de novo daqui a pouco.');
    end;
  end if;

  -- FASE 3: a entrega conferida (alocação tipo entrega cumprida) é o marco da entrega; e a diária de cada diarista do dia
  -- (_agenda_diaria_do_dia: só lança quando a confirmação e o plano batem; o resto vira pergunta; o dono pula).
  if p_resultado = 'cumprido' then
    for v_ent in select a.service_order_id as os, min(lower(a.periodo)) as quando from public.agenda_alocacoes a
                  where a.id = any (v_mudou) and a.tipo = 'entrega' group by a.service_order_id order by 1 loop
      begin
        perform public.os_registrar_marco(v_ent.os, 'entrega', case when p_via = 'equipe' then 'equipe' else 'conferencia' end,
                                          v_ent.quando, v_autor, p_trecho, p_hoje, p_agora);
      exception when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        perform public.log_app_error('db', 'agenda: a entrega conferida não registrou: ' || v_msg, 'agenda', 'conferencia:entrega',
                                     'error', jsonb_build_object('os', v_ent.os, 'sqlstate', v_estado, 'p_hoje', p_hoje));
      end;
    end loop;
  end if;
  if p_dia <= p_hoje then
    for v_p in select distinct a.payee_id from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
                where a.id = any (v_mudou) and py.kind <> 'socio' order by 1 loop
      begin
        v_dr := public._agenda_diaria_do_dia(v_p, p_dia, case when p_via = 'equipe' then 'equipe' else 'conferencia' end,
                                             p_hoje, p_agora);
      exception when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        perform public.log_app_error('db', 'agenda: a diária da conferência falhou: ' || v_msg, 'agenda', 'conferencia:diaria',
                                     'error', jsonb_build_object('payee', v_p, 'dia', p_dia, 'sqlstate', v_estado));
        v_dr := null;
      end;
      if v_dr ->> 'status' = 'lancada' then
        v_lanc := v_lanc || format('%s (%s, %s)', v_dr ->> 'nome',
                                   case when (v_dr ->> 'fracao')::numeric = 1 then 'dia' else 'meia' end,
                                   public._brl((v_dr ->> 'valor')::numeric));
        v_ult := v_dr;
      elsif v_dr ->> 'status' = 'sombra' then
        v_somb := v_somb || format('%s (%s, %s)', v_dr ->> 'nome',
                                   case when (v_dr ->> 'fracao')::numeric = 1 then 'dia' else 'meia' end,
                                   public._brl((v_dr ->> 'valor')::numeric));
      end if;
    end loop;
  end if;
  -- FASE 3: fim
  v_txt := case
    when p_resultado = 'nao_cumprido' and v_motivo = 'clima'
      then format('Anotado, %s: não deu por causa da chuva (%s).', v_ref, public._agenda_lista(v_partes, null))
    when p_resultado = 'nao_cumprido'
      then format('Anotado, %s: %s não andou (%s).', v_ref, public._agenda_lista(v_partes, null), public._agenda_motivo_texto(v_motivo))
    else format('Anotado, %s: %s.', v_ref, array_to_string(v_partes, '; ')) end
    || case when cardinality(v_and) = 1 then ' ' || v_and[1] || ' agora está em andamento.'
            when cardinality(v_and) > 1 then ' ' || public._agenda_lista(v_and, null) || ' agora estão em andamento.'
            else '' end
    || case when v_rep is null then ''
            when coalesce((v_rep ->> 'ok')::boolean, false) and v_rep ->> 'texto' like 'Nada a mudar na agenda.%'
              then ' O resto do plano fica como está.' || coalesce(nullif(substr(v_rep ->> 'texto', length('Nada a mudar na agenda.') + 1), ''), '')
            when coalesce((v_rep ->> 'ok')::boolean, false)
              then ' Replanejei: ' || regexp_replace(coalesce(v_rep ->> 'texto', ''), '^Mudei: ', '')
            else ' ' || coalesce(v_rep ->> 'texto', '') end;
  -- FASE 3: as diárias lançadas (ou o que lançaria, em teste) e a intervenção do dono, no fim do texto.
  v_txt := v_txt
    || case when cardinality(v_lanc) > 0
            then format(' Lancei %s: %s. *diária %s %s* corrige.',
                        case when cardinality(v_lanc) = 1 then 'a diária' else 'as diárias' end, public._agenda_lista(v_lanc, null),
                        v_ult ->> 'nome', case when (v_ult ->> 'fracao')::numeric = 1 then 'meia' else 'inteira' end)
            else '' end
    || case when cardinality(v_somb) > 0 then format(' Em teste: lançaria %s.', public._agenda_lista(v_somb, null)) else '' end
    || case when v_interv then ' ' || v_itxt else '' end;
  return jsonb_build_object('ok', true, 'mudou', true, 'dia', p_dia, 'texto', v_txt, 'alocacoes', cardinality(v_mudou),
                            'acoes', to_jsonb(v_acoes), 'replano', v_rep);
end;
$function$;

comment on function public.agenda_registrar_dia(uuid, date, text, text, uuid, uuid[], text, text, date, timestamptz, text) is
  'Agenda de Produção (Fase 2, P3): o que aconteceu num dia do plano — resultado (cumprido, parcial, nao_cumprido) e o motivo LCI (obrigatório para parcial e não; sem ele, a frase que pede, nada muda) nas alocações vigentes sem reserva do dia (p_os/p_pessoas recortam; cumprido e parcial só o que já começou). Idempotente: o mesmo resultado de novo não muda nada; outro corrige (vai ao histórico). Uma ação resultado por OS (origem conferencia, sem desfazer). cumprido/parcial numa OS que não começou → porta em andamento com o check-in na hora do 1º meio-dia dela no dia; parcial/não → agenda_replanejar na mesma transação (se o motor falhar, o resultado fica, o erro vai para app_error_logs e a vigia tenta de novo); a pergunta conferencia do dia fica respondida. Admin pelo _autor_da_agenda. Fase 3: p_via equipe (a resposta do técnico; sem login, uma pessoa, só os turnos confirmados em agenda.turnos_equipe; a porta e o replano como a agenda sozinha); depois do resultado, a entrega conferida (alocação entrega cumprida → os_registrar_marco) e a diária de cada diarista tocado (_agenda_diaria_do_dia: "Lancei as diárias: Roberto (dia, R$ 180,00) e João (meia, R$ 75,00). *diária João inteira* corrige." ou "Em teste: lançaria …"); o dono (p_pessoas) numa OS em que não estava no plano = agenda_intervencoes_do_dono ("Anotei que você foi ao Lenine sem estar no plano…").';

-- agenda_decidir: corpo de 20261025100200 (a única que a define).
create or replace function public.agenda_decidir(p_pergunta uuid, p_opcao smallint, p_autor uuid default null,
                                                 p_via text default 'whatsapp', p_trecho text default null,
                                                 p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config;
  v_q    public.agenda_perguntas%rowtype;
  v_opc  jsonb;
  v_rest jsonb;
  v_sim  jsonb;
  v_mud  text;
  v_r    jsonb;
  v_ap   jsonb;
begin
  if p_via is null or p_via not in ('whatsapp', 'painel', 'tela') then
    raise exception 'Canal desconhecido para a decisão: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  cf := public._agenda_cfg();
  select * into v_q from public.agenda_perguntas where id = p_pergunta for update;
  if not found then
    raise exception 'Não encontrei essa pergunta.' using errcode = 'P0002';
  end if;
  -- FASE 3: a diária (a pergunta crítica que diverge e a de ligar a OS) tem o efeito dela e o modo dela (modo_diaria):
  -- _agenda_decidir_diaria (20261026100300).
  if v_q.tipo in ('diaria', 'diaria_ligar') then
    return public._agenda_decidir_diaria(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_hoje, p_agora);
  end if;
  -- FASE 3: fim
  if not v_q.critica then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta não é de decisão.');
  end if;
  if v_q.estado <> 'aberta' then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta já foi respondida ou resolvida.');
  end if;
  if v_q.modo <> 'ligado' or cf.modo_proposta <> 'ligado' then
    return jsonb_build_object('ok', false, 'texto', 'A agenda automática ainda está em teste: mostro como ficaria, mas não marco nada.');
  end if;
  select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
  if v_opc is null then
    return jsonb_build_object('ok', false,
      'texto', 'Essa opção não existe. As opções são: '
               || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                     from jsonb_array_elements(v_q.opcoes) o) || '.');
  end if;
  v_rest := coalesce(v_opc #> '{efeito,restricoes}', '{}'::jsonb);

  -- A agenda mudou desde a pergunta: o efeito da opção é refeito agora; se não termina como a opção dizia, a pergunta
  -- volta com os dias de agora (nada é executado).
  if v_q.versao_base is distinct from cf.versao_plano and jsonb_typeof(v_opc -> 'espera') = 'object'
     and v_opc -> 'espera' <> '{}'::jsonb then
    v_sim := public.agenda_propor('replano', null, null, v_q.os_ids, v_rest, false, 'dono', p_autor, p_hoje, p_agora);
    select string_agg(format('%s termina %s (antes eu disse %s)', public._agenda_rotulo_da_os(e.key::uuid),
                             coalesce(public._dia_curto(x.fim), 'sem encaixe'), public._dia_curto((e.value #>> '{}')::date)), '; ')
      into v_mud
      from jsonb_each(v_opc -> 'espera') e
      left join lateral (select max((i ->> 'fim_depois')::date) as fim from jsonb_array_elements(v_sim -> 'itens') i
                          where i ->> 'op' = 'criar' and i ->> 'os' = e.key and i ->> 'tipo' <> 'reserva') x on true
     where x.fim is distinct from (e.value #>> '{}')::date;
    if v_mud is not null then
      return jsonb_build_object('ok', false, 'mudou', true,
        'texto', 'A agenda mudou desde a pergunta: ' || v_mud || '. Me responda de novo com os dias de agora.');
    end if;
  end if;

  begin
    update public.agenda_perguntas
       set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
           respondida_por = p_autor, respondida_via = p_via
     where id = p_pergunta;
    v_r := public.agenda_propor('replano', null, null, v_q.os_ids, v_rest || jsonb_build_object('decisao', p_pergunta),
                                true, 'dono', p_autor, p_hoje, p_agora);
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      raise exception using errcode = 'P0098', message = coalesce(v_r ->> 'texto', 'não deu');
    end if;
    v_ap := public.agenda_aplicar((v_r ->> 'proposta_id')::uuid, null, 'dono', p_autor, p_pergunta, p_hoje, p_agora);
    if not coalesce((v_ap ->> 'ok')::boolean, false) then
      raise exception using errcode = 'P0098', message = coalesce(v_ap ->> 'texto', 'não deu');
    end if;
  exception when sqlstate 'P0098' then
    -- nada fica: a pergunta continua aberta
    return jsonb_build_object('ok', false, 'texto', 'Não consegui fazer o que você escolheu: ' || sqlerrm || ' Nada mudou.');
  end;
  return jsonb_build_object('ok', true, 'texto', 'Feito: ' || (v_ap ->> 'texto'), 'acoes', v_ap -> 'acoes',
                            'proposta_id', v_r ->> 'proposta_id');
end;
$function$;

comment on function public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): a resposta do dono a uma pergunta crítica aberta (só em ligado). Opção que não existe = recusa, nada marcado. Se a agenda mudou desde a pergunta, o efeito da opção é refeito agora e, se não termina como a opção dizia (espera), devolve a pergunta com os dias de agora sem executar. Senão: a pergunta fica respondida (opcao_escolhida, resposta = as palavras do dono, respondida_*) e o efeito é executado — agenda_propor(replano, as OS da pergunta, as restrições da opção + decisao) e agenda_aplicar com p_pergunta (toda ação sai critica = true com pergunta_id). Falhou = nada fica, a pergunta continua aberta. Canais: whatsapp, painel, tela. Fase 3: diaria e diaria_ligar vão a _agenda_decidir_diaria (o lançamento, a correção pelo registrar_diaria ou a ligação às OS, com modo_diaria ligado).';

-- agenda_desfazer: corpo de 20261026100100 (a mais nova; o bloco -- FASE 3: do P2 fica).
create or replace function public.agenda_desfazer(p_acao uuid, p_autor uuid default null, p_via text default 'dono',
                                                  p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config;
  v_a     public.agenda_acoes%rowtype;
  v_nome  text;
  v_x     record;
  v_novas uuid[] := '{}';
  v_canc  uuid[] := '{}';
  v_id    uuid;
  v_os    uuid;
  v_acao  uuid;
  v_txt   text;
  v_q     public.agenda_perguntas%rowtype;
  v_dias  date[];
begin
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  cf := public._agenda_cfg();
  select * into v_a from public.agenda_acoes where id = p_acao for update;
  if not found then
    raise exception 'Não encontrei essa mudança.' using errcode = 'P0002';
  end if;
  v_os := v_a.service_order_id;
  v_nome := coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                        join public.clients cl on cl.id = so.client_id where so.id = v_os), 'serviço');
  if not v_a.executada then
    return jsonb_build_object('ok', false, 'texto', 'Isso foi só o teste da agenda automática: nada mudou para desfazer.');
  end if;
  if v_a.desfeita_em is not null then
    return jsonb_build_object('ok', false, 'texto', 'Isso já foi desfeito.');
  end if;
  if v_a.tipo = 'desfazer' then
    return jsonb_build_object('ok', false, 'texto', 'Não desfaço um desfazer: me diga o dia que você quer.');
  end if;
  -- FASE 3: a conclusão e a entrega têm o desfazer delas (o status e a saída pela porta, as cobranças da conclusão, a
  -- comissão de vendedor, os vencimentos "na entrega" e a entrega): _agenda_desfazer_marco (20261026100100).
  if v_a.tipo in ('concluir', 'entregar') then
    return public._agenda_desfazer_marco(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 3 (P4): a diária que a agenda lançou: apaga o turno que ela criou, se o acerto está aberto (_agenda_desfazer_diaria).
  if v_a.tipo = 'diaria' then
    return public._agenda_desfazer_diaria(v_a.id, p_autor, p_hoje, p_agora);
  end if;
  -- FASE 3: fim
  if v_a.desfazivel_ate is null then
    return jsonb_build_object('ok', false, 'texto', 'Essa mudança foi pedida por você: para mudar de novo, me diga o dia.');
  end if;
  if p_agora > v_a.desfazivel_ate then
    return jsonb_build_object('ok', false,
      'texto', case when exists (select 1 from public.agenda_alocacoes a where a.id = any (v_a.alocacoes_criadas)
                                                                       and lower(a.periodo) <= p_agora)
                    then format('Não dá para desfazer: já começou o 1º dia do %s na nova data. Se quiser mudar, me diga o dia.', v_nome)
                    else format('Não dá mais para desfazer o %s: passou o prazo. Se quiser mudar, me diga o dia.', v_nome) end);
  end if;
  if exists (select 1 from public.agenda_alocacoes a
              where a.id = any (v_a.alocacoes_criadas) and a.estado in ('publicada', 'fixada')
                and (lower(a.periodo) <= p_agora or a.resultado is not null)) then
    return jsonb_build_object('ok', false,
      'texto', format('Não dá para desfazer: já começou o 1º dia do %s na nova data. Se quiser mudar, me diga o dia.', v_nome));
  end if;
  -- recriar o que saiu não pode bater em quem já está no lugar
  select a.dia, a.turno, py.name as pessoa, cl.name as cliente into v_x
    from public.agenda_alocacoes c
    join public.agenda_alocacoes a on a.payee_id = c.payee_id and a.periodo && c.periodo and a.estado in ('publicada', 'fixada')
                                  and not (a.id = any (v_a.alocacoes_criadas))
    join public.payees py on py.id = a.payee_id
    join public.service_orders so on so.id = a.service_order_id
    left join public.clients cl on cl.id = so.client_id
   where c.id = any (v_a.alocacoes_canceladas) and c.estado = 'cancelada' and lower(c.periodo) > p_agora
   order by a.dia, a.turno = 'tarde'
   limit 1;
  if found then
    return jsonb_build_object('ok', false,
      'texto', format('Não dá para desfazer: o %s já está no %s %s.', public._agenda_nome_curto(v_x.pessoa),
                      coalesce(public._agenda_nome_curto(v_x.cliente), 'outro serviço'), public._agenda_meio_texto(v_x.dia, v_x.turno)));
  end if;

  -- 1. O que a ação criou sai.
  for v_id in select a.id from public.agenda_alocacoes a
               where a.id = any (v_a.alocacoes_criadas) and a.estado in ('publicada', 'fixada') order by a.dia, a.turno, a.id loop
    if (select estado from public.agenda_alocacoes where id = v_id) = 'fixada' then
      perform set_config('agenda.mexe_fixado', 'on', true);
    end if;
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'desfeito' where id = v_id;
    perform set_config('agenda.mexe_fixado', 'off', true);
    v_canc := v_canc || v_id;
  end loop;
  -- 2. O que ela tirou volta, igual (mesma pessoa, dia, turno e presença), do que ainda não começou.
  for v_x in select c.* from public.agenda_alocacoes c
              where c.id = any (v_a.alocacoes_canceladas) and c.estado = 'cancelada' and lower(c.periodo) > p_agora
              order by c.dia, c.turno = 'tarde', c.payee_id, c.id loop
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, substitui_id,
                                         fixado_por, reserva_de, condicao, condicao_tipo, condicao_ate, motivos)
    values (v_x.service_order_id, v_x.payee_id, v_x.dia, v_x.turno, v_x.presenca, v_x.tipo,
            case when v_x.fixado_por is not null then 'fixada' else 'publicada' end, v_x.origem, v_x.id,
            v_x.fixado_por, v_x.reserva_de, v_x.condicao, v_x.condicao_tipo, v_x.condicao_ate, v_x.motivos)
    returning id into v_id;
    v_novas := v_novas || v_id;
  end loop;
  -- 3. O status volta pela porta (a regra de não regredir o que começou continua valendo) e o espelho acompanha.
  if v_a.tipo = 'status' and v_a.status_antes is not null and v_os is not null then
    perform public.os_transicionar_status(v_os, v_a.status_antes, 'desfazer', null, p_autor, null, p_hoje, p_agora);
  elsif v_os is not null then
    if public._agenda_os_tem_dia(v_os, p_hoje) then
      if (select status from public.service_orders where id = v_os) in ('open', 'approved', 'awaiting_parts') then
        perform public.os_transicionar_status(v_os, 'scheduled', 'desfazer', null, p_autor, null, p_hoje, p_agora);
      end if;
    elsif (select status from public.service_orders where id = v_os) = 'scheduled' then
      perform public.os_transicionar_status(v_os, case when v_a.status_antes in ('open', 'approved', 'awaiting_parts')
                                                       then v_a.status_antes else 'approved' end,
                                            'desfazer', null, p_autor, null, p_hoje, p_agora);
    end if;
    perform public._agenda_espelhar_datas(v_os, p_hoje);
  end if;

  v_dias := array(select a.dia from public.agenda_alocacoes a where a.id = any (v_novas) and a.tipo <> 'reserva');
  v_txt := case when cardinality(v_dias) > 0
                then format('Desfeito: o %s volta para %s, como estava.', public._agenda_rotulo_da_os(v_os), public._agenda_dias_texto(v_dias))
                when cardinality(v_novas) > 0 then format('Desfeito: a reserva do %s volta como estava.', public._agenda_rotulo_da_os(v_os))
                else format('Desfeito: o %s sai da agenda, como estava.', coalesce(public._agenda_rotulo_da_os(v_os), 'serviço')) end;
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, proposta_id, critica,
                                   versao_depois, alocacoes_criadas, alocacoes_canceladas, antes, depois, texto, autor, desfaz_a)
  values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer', v_os,
          v_a.os_ids, v_a.proposta_id, false, (public._agenda_cfg()).versao_plano, v_novas, v_canc,
          jsonb_build_object('acao', v_a.id), jsonb_build_object('alocacoes', to_jsonb(v_novas)), left(v_txt, 400), p_autor, v_a.id)
  returning id into v_acao;
  update public.agenda_alocacoes set acao_id = v_acao where id = any (v_novas);
  update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_a.id;

  -- Desfazer uma decisão crítica não a reabre: a decisão volta ao dono como pergunta nova, do mesmo tipo.
  if v_a.critica and v_a.pergunta_id is not null then
    select * into v_q from public.agenda_perguntas where id = v_a.pergunta_id;
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, perda_em, texto, opcoes, recomendacao,
                                         recomendacao_texto, versao_base, modo, criada_em)
    values (v_q.tipo, left(v_q.chave || ':refeita:' || left(v_acao::text, 8), 200), v_q.service_order_id, v_q.os_ids, v_q.perda_em,
            v_q.texto, v_q.opcoes, v_q.recomendacao, v_q.recomendacao_texto, (public._agenda_cfg()).versao_plano, v_q.modo, p_agora)
    on conflict (chave, modo) where estado = 'aberta' do nothing;
    v_txt := format('Desfeito. A decisão sobre o %s volta a ficar com você.', v_nome);
  end if;
  -- FASE 3: o replano que a ausência da equipe causou ("não vou" ou o silêncio até as 9h): desfazer também tira a ausência
  -- daquele dia (senão a vigia replanejaria de novo no tique seguinte). "Se ele estiver lá, *desfaz Vanderlei*."
  update public.agenda_disponibilidade d set substituida_em = p_agora
   where d.substituida_em is null
     and d.id in (select (e.depois ->> 'disponibilidade')::uuid from public.agenda_acoes e
                   where e.tipo = 'equipe' and e.depois ->> 'disponibilidade' is not null
                     and coalesce(e.depois -> 'replano_acoes', '[]'::jsonb) ? v_a.id::text);
  -- FASE 3: fim
  return jsonb_build_object('ok', true, 'texto', v_txt, 'acao_id', v_acao, 'recriadas', to_jsonb(v_novas), 'canceladas', to_jsonb(v_canc));
end;
$function$;

comment on function public.agenda_desfazer(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): desfaz uma ação executada — recusa (nada muda) se foi sombra, já foi desfeita, não é desfazível (pedido do dono pela tela ou aprovação), passou o desfazivel_ate, algum meio-dia criado já começou ou tem resultado, ou recriar o que saiu bateria em quem já está no lugar ("Não dá para desfazer: o Roberto já está no Giancarlo…"). Faz: o que ela criou → cancelada (desfeito); o que ela tirou volta igual (substitui_id, mesmo estado/fixado); o status pela porta (via desfazer; o que começou não regride); o espelho; nova ação tipo desfazer (desfaz_a) e a original ganha desfeita_*. Desfazer uma decisão crítica cria a pergunta de novo ("A decisão sobre o Nelson volta a ficar com você."). Fase 3: concluir e entregar vão a _agenda_desfazer_marco (as cobranças da conclusão, a saída, a comissão de vendedor e a entrega); a diária da agenda a _agenda_desfazer_diaria (apaga o turno que ela criou, com o acerto aberto); desfazer o replano da ausência da equipe tira a ausência do dia (agenda_disponibilidade substituída).';

-- _agenda_texto_do_acorde: corpo de 20261025100300 (a única que a define).
create or replace function public._agenda_texto_do_acorde(p_acao uuid, p_perda date, p_hoje date)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select format('Mudei a agenda de %s: %s', case when p_perda = p_hoje then 'hoje' when p_perda = p_hoje + 1 then 'amanhã'
                                                 else public._dia_curto(p_perda) end, a.texto)
         || case when a.desfazivel_ate is not null
                 then format(' *desfaz %s* volta como estava.',
                             coalesce(public._agenda_nome_curto(cl.name), so.service_order_number, 'isso'))
                 else '' end
         -- FASE 3: quem já recebeu a ficha (ou a confirmação) do dia que mudou: o dono avisa (a mensagem de mudança à
         -- equipe é da Fase 5). Quem faltou (indisponível no dia) não entra.
         || coalesce((select format(' O %s já recebeu a ficha de %s com o %s: avise ele da mudança.', public._agenda_nome_curto(py.name),
                                    case when m.dia = p_hoje then 'hoje' when m.dia = p_hoje + 1 then 'amanhã' else public._dia_curto(m.dia) end,
                                    coalesce(public._agenda_nome_curto(cl.name), 'serviço'))
                        from public.agenda_equipe_mensagens m join public.payees py on py.id = m.payee_id
                       where m.modo = 'ligado' and m.tipo in ('ficha', 'confirmar') and m.dia = p_perda
                         and m.estado in ('enfileirada', 'respondida', 'sem_resposta')
                         and m.payee_id in (select b.payee_id from public.agenda_alocacoes b
                                             where b.id = any (a.alocacoes_canceladas || a.alocacoes_criadas))
                         and not exists (select 1 from public.agenda_disponibilidade d
                                          where d.payee_id = m.payee_id and d.substituida_em is null and d.situacao = 'indisponivel'
                                            and d.periodo @> m.dia)
                       order by m.enviar_em desc, m.id limit 1), '')
    from public.agenda_acoes a
    left join public.service_orders so on so.id = a.service_order_id
    left join public.clients cl on cl.id = so.client_id
   where a.id = p_acao;
$function$;

comment on function public._agenda_texto_do_acorde(uuid, date, date) is 'Agenda de Produção (Fase 2, P3): o acorde de uma mudança feita sozinha — "Mudei a agenda de amanhã: <a frase da ação> *desfaz Vanderlei* volta como estava." Fase 3: quando a mudança atinge quem já recebeu a ficha do dia (e não faltou), "O Roberto já recebeu a ficha de amanhã com o Lenine: avise ele da mudança."';

-- agenda_saude: corpo de 20261025100300 (a única que a define).
create or replace function public.agenda_saude(p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf        public.agenda_config := public._agenda_cfg();
  v_cart    uuid[];
  v_ult     record;
  v_vig     jsonb;
  v_hoje    jsonb;
  v_crit    jsonb;
  v_perg    jsonb;
  v_prop    jsonb;
  v_plano   jsonb;
  v_inv     jsonb;
  v_fech    jsonb;
  v_sem     int;
  v_regra   jsonb;
  v_leu     boolean;
  v_choques int;
  -- FASE 3
  v_rot     jsonb;
  v_eq      jsonb;
  v_dia     jsonb;
  v_conc    jsonb;
  v_marcos  jsonb;
  v_com     jsonb;
  v_teto    int;
  v_janela  int;
  v_semconf int;
  v_sobre   int;
  v_semrec  int;
  v_pay     int;
begin
  v_cart := array(select k.service_order_id from public.os_carteira(p_hoje) k);

  select max(x.p_agora) as ultima, max(x.rodou_em) as rodou_em,
         count(*) filter (where x.p_agora > p_agora - interval '1 day' and x.p_agora <= p_agora) as n24,
         (array_agg(x.erros order by x.p_agora desc, x.rodou_em desc))[1] as erros_ult
    into v_ult from public.agenda_vigia_rodadas x
   -- FASE 3: a rotina da equipe grava na mesma tabela (rotina = 'rotina'); a vigia é só a dela.
   where x.rotina = 'vigia';
  v_vig := jsonb_build_object(
    'ultima_rodada', v_ult.ultima, 'rodou_em', v_ult.rodou_em,
    'rodou_nas_ultimas_2h', coalesce(v_ult.ultima > p_agora - interval '2 hours', false),
    'rodadas_24h', coalesce(v_ult.n24, 0), 'erros_ultima_rodada', coalesce(v_ult.erros_ult, 0),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.last_seen_at >= least(p_agora, now()) - interval '1 day'));

  select jsonb_build_object(
           'publicar', count(*) filter (where a.executada and a.tipo = 'publicar'),
           'criar', count(*) filter (where a.executada and a.tipo = 'criar'),
           'mover', count(*) filter (where a.executada and a.tipo = 'mover'),
           'cancelar', count(*) filter (where a.executada and a.tipo = 'cancelar'),
           'promover', count(*) filter (where a.executada and a.tipo = 'promover_reserva'),
           'soltar', count(*) filter (where a.executada and a.tipo = 'soltar_reserva'),
           'status', count(*) filter (where a.executada and a.tipo = 'status'),
           'resultado', count(*) filter (where a.executada and a.tipo = 'resultado'),
           'desfeitas', count(*) filter (where a.executada and a.tipo = 'desfazer'),
           'sombra', count(*) filter (where not a.executada))
    into v_hoje from public.agenda_acoes a where a.dia = p_hoje;

  -- A prova: nenhuma ação crítica executada sem a decisão registrada (o gatilho impede; isto confere).
  select count(*) into v_sem
    from public.agenda_acoes a left join public.agenda_perguntas q on q.id = a.pergunta_id
   where a.executada and a.critica and (q.id is null or q.estado <> 'respondida' or q.opcao_escolhida is null);
  -- E o erro de classificação: ação autônoma executada como não crítica que a regra diz crítica.
  select jsonb_build_object('n', count(*), 'acoes', coalesce(jsonb_agg(a.id order by a.criada_em, a.id), '[]'::jsonb)) into v_regra
    from public.agenda_acoes a
   where a.executada and not a.critica and a.origem in ('motor', 'vigia', 'conferencia')
     and a.tipo in ('publicar', 'criar', 'mover', 'cancelar', 'promover_reserva', 'soltar_reserva')
     and public._agenda_criticidade_da_acao(a.id) is not null;
  v_crit := jsonb_build_object(
    'abertas', (select count(*) from public.agenda_perguntas q where q.critica and q.estado = 'aberta'),
    'respondidas_7d', (select count(*) from public.agenda_perguntas q
                        where q.critica and q.estado = 'respondida' and q.respondida_em > p_agora - interval '7 days'),
    'sem_decisao', v_sem, 'pela_regra_sem_decisao', (v_regra ->> 'n')::int, 'pela_regra_acoes', v_regra -> 'acoes');

  v_perg := jsonb_build_object(
    'abertas_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select q.tipo, count(*) as n from public.agenda_perguntas q where q.estado = 'aberta' group by q.tipo) t), '{}'::jsonb),
    'abertas_sombra', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.modo = 'sombra'),
    'mostradas_hoje', (select count(*) from public.agenda_perguntas q
                        where (q.mostrada_em at time zone 'America/Sao_Paulo')::date = p_hoje));

  select jsonb_build_object(
           'abertas', count(*) filter (where p.estado = 'aberta'),
           'obsoletas_7d', count(*) filter (where p.estado = 'obsoleta' and p.criada_em > p_agora - interval '7 days'),
           'aplicadas_7d', count(*) filter (where p.estado = 'aplicada' and p.criada_em > p_agora - interval '7 days'),
           'sombra_7d', count(*) filter (where p.modo = 'sombra' and p.criada_em > p_agora - interval '7 days'))
    into v_prop from public.agenda_propostas p;

  select jsonb_build_object(
           'alocacoes_vigentes_futuras', count(*) filter (where a.dia >= p_hoje and a.resultado is null),
           'os_programadas', count(distinct a.service_order_id) filter (where a.dia >= p_hoje and a.resultado is null and a.tipo <> 'reserva'),
           'reservas', count(*) filter (where a.dia >= p_hoje and a.tipo = 'reserva'),
           'sem_registro_7d', count(*) filter (where a.resultado = 'sem_registro' and a.dia > p_hoje - 7))
    into v_plano from public.agenda_alocacoes a where a.estado in ('publicada', 'fixada');

  select count(*) into v_choques
    from public.agenda_alocacoes a join public.agenda_alocacoes b
      on b.payee_id = a.payee_id and b.id > a.id and b.periodo && a.periodo
   where a.estado in ('publicada', 'fixada') and b.estado in ('publicada', 'fixada');
  v_inv := jsonb_build_object(
    'vigente_de_os_fora_da_carteira', (select count(distinct a.service_order_id) from public.agenda_alocacoes a
                                        where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
                                          and not (a.service_order_id = any (v_cart))),
    'espelho_divergente', case when cf.modo_proposta <> 'ligado' then 0 else (
       select count(*) from public.service_orders so
        cross join lateral (select min(lower(a.periodo)) as ini, max(upper(a.periodo)) as fim from public.agenda_alocacoes a
                             where a.service_order_id = so.id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                               and a.resultado is distinct from 'nao_cumprido') m
        where so.id = any (v_cart)
          and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = so.id)
          and (so.scheduled_start_at is distinct from m.ini or so.scheduled_end_at is distinct from m.fim)) end,
    'choques', v_choques);

  if to_regclass('public.resumo_tarde') is not null then
    execute $q$select exists (select 1 from public.resumo_tarde t
                               where t.dia = $1 and jsonb_typeof(t.detalhe -> 'agenda') = 'object'
                                 and (t.detalhe -> 'agenda' ? 'linhas_diria' or t.detalhe -> 'agenda' ? 'linhas'))$q$
      into v_leu using p_hoje;
  end if;
  v_fech := jsonb_build_object(
    'leu_o_plano_hoje', v_leu,
    'linhas_mostradas', (select count(*) from public.agenda_acoes a
                          where a.contada_via = 'fechamento' and (a.contada_em at time zone 'America/Sao_Paulo')::date = p_hoje)
                        + (select count(*) from public.agenda_perguntas q
                            where q.mostrada_via = 'fechamento' and (q.mostrada_em at time zone 'America/Sao_Paulo')::date = p_hoje));

  -- FASE 3: a rotina, a equipe, as diárias, a conclusão, os marcos e a comissão. Os "0 obrigatórios": acima do teto, fora
  -- da janela, diária sem confirmação, turno sobrescrito pela agenda, conclusão sem cobrança quando devia, pagamento de
  -- comissão de técnico.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'rotina:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_rot from public.agenda_vigia_rodadas x where x.rotina = 'rotina';
  select count(*) into v_teto
    from (select m.payee_id, (m.enviar_em at time zone 'America/Sao_Paulo')::date as dia, m.tipo = 'resposta' as resp, count(*) as n
            from public.agenda_equipe_mensagens m
           where m.modo = 'ligado' and m.estado in ('enfileirada', 'respondida', 'sem_resposta')
           group by 1, 2, 3) t
   where t.n > case when t.resp then cf.equipe_respostas_dia_max else cf.equipe_proativas_dia_max end;
  -- (revisão C1) pela regra única da janela (_agenda_equipe_fora_da_janela): a resposta direta tem a dela
  select count(*) into v_janela
    from public.whatsapp_send_queue q
    left join public.agenda_equipe_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-equipe'
     and (x.id is null
          or public._agenda_equipe_fora_da_janela(x.tipo, x.enviar_em, q.scheduled_for) is not null
          -- o que SAIU fora da janela (o worker atrasado): também conta
          or (q.sent_at is not null and public._agenda_equipe_fora_da_janela(x.tipo, x.enviar_em, q.sent_at) is not null));
  v_eq := jsonb_build_object(
    'mensagens_hoje_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select m.tipo, count(*) as n from public.agenda_equipe_mensagens m
         where (m.enviar_em at time zone 'America/Sao_Paulo')::date = p_hoje group by m.tipo) t), '{}'::jsonb),
    'recusadas_hoje_por_motivo', coalesce((select jsonb_object_agg(t.recusa_motivo, t.n) from (
        select m.recusa_motivo, count(*) as n from public.agenda_equipe_mensagens m
         where m.estado = 'recusada' and (m.enviar_em at time zone 'America/Sao_Paulo')::date = p_hoje group by m.recusa_motivo) t), '{}'::jsonb),
    'acima_do_teto', v_teto, 'fora_da_janela', v_janela);
  select count(*) into v_semconf
    from public.agenda_acoes a
   where a.tipo = 'diaria' and a.executada and not a.critica and a.origem <> 'dono' and a.desfeita_em is null
     and coalesce(public._agenda_confirmacao_do_dia(a.payee_id, (a.depois ->> 'dia')::date) ->> 'estado', '') <> 'confirmada';
  select count(*) into v_sobre
    from public.agenda_acoes a left join public.work_shifts ws on ws.id = a.work_shift_id
   where a.tipo = 'diaria' and a.executada and not a.critica and a.origem <> 'dono'
     and (coalesce(jsonb_typeof(a.antes -> 'turno'), 'null') <> 'null' or (ws.id is not null and ws.origem <> 'agente'));
  v_dia := jsonb_build_object(
    -- (o dia de quem agiu: a.dia é o p_hoje dele; criada_em é o relógio do banco)
    'lancadas_7d', (select count(*) from public.agenda_acoes a
                     where a.tipo = 'diaria' and a.executada and a.origem <> 'dono' and a.dia > p_hoje - 7),
    'sombra_7d', (select count(*) from public.agenda_acoes a
                   where a.tipo = 'diaria' and not a.executada and a.dia > p_hoje - 7),
    'perguntas_abertas', (select count(*) from public.agenda_perguntas q where q.tipo in ('diaria', 'diaria_ligar') and q.estado = 'aberta'),
    'sem_confirmacao', v_semconf, 'sobrescreveu_turno', v_sobre);
  -- a conclusão pela porta sem cobrança viva quando a regra da condição dá parcelas ou título (a releitura é só service_role)
  if has_function_privilege('public._os_recebiveis_da_conclusao(uuid, date)', 'execute') then
    select count(*) into v_semrec
      from (select distinct so.id, so.check_out_at
              from public.agenda_acoes a join public.service_orders so on so.id = a.service_order_id
             where a.tipo = 'concluir' and a.executada and a.desfeita_em is null and so.status in ('completed', 'invoiced')
               and so.check_out_at is not null
               and not exists (select 1 from public.receivables r where r.service_order_id = so.id and r.status <> 'cancelled')) t
     where public._os_recebiveis_da_conclusao(t.id, (t.check_out_at at time zone 'America/Sao_Paulo')::date) ->> 'motivo'
           in ('parcelas', 'titulo_unico');
  end if;
  v_conc := jsonb_build_object(
    'pela_agenda_7d', (select count(*) from public.agenda_acoes a
                        where a.tipo = 'concluir' and a.executada and a.origem in ('equipe', 'dono')
                          and a.dia > p_hoje - 7),
    'desfeitas_7d', (select count(*) from public.agenda_acoes a
                      where a.tipo = 'concluir' and a.desfeita_em > p_agora - interval '7 days'),
    'sem_recebivel_quando_devia', v_semrec);
  select jsonb_build_object(
           'concluidas_30d', count(*),
           'entregues_em_ate_5du', count(*) filter (where so.delivered_at is not null
             and public.agenda_du_entre((so.check_out_at at time zone 'America/Sao_Paulo')::date,
                                        (so.delivered_at at time zone 'America/Sao_Paulo')::date) <= cf.entrega_aviso_du),
           'sem_entrega_ha_mais_de_5du', count(*) filter (where so.delivered_at is null and so.status = 'completed'
             and public.agenda_du_entre((so.check_out_at at time zone 'America/Sao_Paulo')::date, p_hoje) > cf.entrega_aviso_du))
    into v_marcos
    from public.service_orders so
   where so.check_out_at > p_agora - interval '30 days'
     and exists (select 1 from public.agenda_acoes a
                  where a.service_order_id = so.id and a.tipo = 'concluir' and a.executada and a.desfeita_em is null);
  select count(*) into v_pay
    from public.payables pa
   where pa.origin = 'commission' and pa.created_at > p_agora - interval '7 days'
     and pa.payee_id in (select w.payee_id from public.work_profiles w where w.modo_pagamento = 'diaria' and w.payee_id is not null);
  v_com := jsonb_build_object('pagamento', (select c.pagamento from public.comissao_config c where c.id),
                              'payables_de_comissao_tecnico_7d', v_pay);
  -- FASE 3: fim
  return jsonb_build_object(
    -- FASE 3: os zeros obrigatórios da execução entram no ok.
    'ok', v_sem = 0 and (v_regra ->> 'n')::int = 0 and v_choques = 0
          and v_teto = 0 and v_janela = 0 and v_semconf = 0 and v_sobre = 0 and coalesce(v_semrec, 0) = 0 and v_pay = 0,
    'modos', jsonb_build_object('leitura', cf.modo_leitura, 'proposta', cf.modo_proposta, 'vigia', cf.modo_vigia),
    'vigia', v_vig, 'hoje', v_hoje, 'criticas', v_crit, 'perguntas', v_perg, 'propostas', v_prop, 'plano', v_plano,
    'invariantes', v_inv, 'fechamento', v_fech,
    -- FASE 3
    'rotina', v_rot, 'equipe', v_eq, 'diarias', v_dia, 'conclusao', v_conc, 'marcos', v_marcos, 'comissao', v_com,
    'modos_fase3', jsonb_build_object('equipe', cf.modo_equipe, 'diaria', cf.modo_diaria));
end;
$function$;

comment on function public.agenda_saude(date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): a conferência depois de cada deploy e o painel da sombra — {ok, modos, vigia (última rodada, rodou nas últimas 2 h, erros em 24 h no app_error_logs context agenda, rodadas em 24 h), hoje (publicar, criar, mover, cancelar, promover, soltar, status, resultado, desfeitas, sombra), criticas (abertas, respondidas em 7 dias, sem_decisao e pela_regra_sem_decisao — têm de ser 0), perguntas (abertas por tipo, mostradas hoje), propostas, plano (vigentes futuras, OS programadas, reservas, sem registro em 7 dias), invariantes (vigente de OS fora da carteira, espelho divergente em ligado, choques = 0), fechamento (leu o plano hoje: resumo_tarde.detalhe.agenda; linhas mostradas)}. Leitura (invoker): authenticated (a RLS do admin vale) e service_role. Fase 3: a vigia lê só as rodadas dela (rotina = vigia); blocos rotina (última rodada, rodou nas últimas 2 h, erros 24 h), equipe (mensagens e recusas de hoje; acima_do_teto e fora_da_janela — também o que saiu fora dela — têm de ser 0), diarias (lançadas e em teste em 7 dias, perguntas abertas; sem_confirmacao e sobrescreveu_turno têm de ser 0), conclusao (pela agenda e desfeitas em 7 dias; sem_recebivel_quando_devia = 0, só para quem lê a releitura), marcos (N4), comissao (pagamento desligado; payables de comissão de técnico em 7 dias = 0) e modos_fase3; o ok inclui esses zeros.';

-- agenda_rascunho_andamento: corpo de 20261026100200 (a mais nova).
create or replace function public.agenda_rascunho_andamento(p_autor uuid, p_canal text, p_os text, p_evento text,
                                                            p_dia text default null, p_quem text[] default null,
                                                            p_motivo text default null, p_trecho text default null,
                                                            p_hoje date default public._hoje_brt(),
                                                            p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor   uuid := public._autor_da_agenda(p_autor);
  v_ev      text := public._agenda_normal(p_evento);
  v_rec     jsonb;
  v_ro      jsonb;
  v_os      uuid;
  v_status  text;
  v_dia     date := p_hoje;
  v_dt      jsonb;
  v_rp      jsonb;
  v_x       text;
  v_pes     uuid[];
  v_nomes   text[] := '{}';
  v_quem    text;
  v_motivo  text;
  v_res     text;
  v_m       boolean;
  v_t       boolean;
  v_turnos  text;
  v_fora    text[];
  v_check   timestamptz;
  v_para    text;
  v_futuros date[];
  v_frase   text;
  v_chave   text;
  v_plural  boolean;
  v_txt     text;
  -- FASE 3 (P4): o dono que foi sem estar no plano
  v_interv  boolean := false;
begin
  -- FASE 3: concluir e entregar viram RASCUNHO com a releitura da saída e das cobranças da condição (o *grava* passa pela
  -- porta: os_registrar_marco, via dono), em todos os modos. "terminou", "acabou", "finalizou" e "pronto" são concluir;
  -- "entregue" é entregar.
  if v_ev in ('concluiu', 'concluida', 'concluido', 'terminou', 'acabou', 'finalizou', 'entregou', 'entregue', 'pronto', 'pronta') then
    return public._agenda_rascunho_marco(v_autor, p_canal, p_os,
                                         case when v_ev in ('entregou', 'entregue') then 'entregou' else 'concluiu' end,
                                         p_dia, p_trecho, p_hoje);
  end if;
  if v_ev not in ('trabalhou', 'parcial', 'nao foi', 'nao_foi', 'comecou', 'parou') then
    -- FASE 3: a lista do erro ganha concluiu e entregou.
    raise exception 'agenda_rascunho_andamento: evento "%" não existe (trabalhou, parcial, nao_foi, comecou, parou, concluiu ou entregou)', p_evento
      using errcode = '22023';
  end if;
  v_ev := replace(v_ev, ' ', '_');
  v_rec := public._agenda_pedido_recusa(p_canal, p_trecho, 'agenda_rascunho_andamento');
  if v_rec is not null then
    return v_rec;
  end if;

  v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
  if v_ro ->> 'status' <> 'ok' then
    return public._agenda_recusa_da_os(v_ro);
  end if;
  v_os := (v_ro ->> 'id')::uuid;
  select so.status into v_status from public.service_orders so where so.id = v_os;

  if nullif(btrim(coalesce(p_dia, '')), '') is not null then
    v_dt := public._agenda_data_conferida(p_dia, p_trecho, p_hoje, 'passado');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if (v_dt ->> 'de') is distinct from (v_dt ->> 'ate') then
      return public._agenda_recusa('Diga um dia só (por exemplo "hoje", "ontem" ou "segunda").', 'um_dia');
    end if;
    v_dia := (v_dt ->> 'de')::date;
  end if;
  if v_dia > p_hoje then
    return public._agenda_recusa(public._agenda_maiuscula(public._dia_curto(v_dia)) || ' ainda não chegou: não dá para dizer como foi.',
                                 'dia_futuro');
  end if;

  if p_quem is not null and cardinality(p_quem) > 0 then
    v_pes := '{}';
    foreach v_x in array p_quem loop
      v_rp := public.agenda_resolver_pessoa(v_x, v_autor, p_hoje);
      if v_rp ->> 'status' <> 'ok' then
        return public._agenda_recusa(v_rp ->> 'texto', 'pessoa_' || (v_rp ->> 'status'),
          coalesce((select jsonb_agg(e ->> 'nome' order by o)
                      from jsonb_array_elements(coalesce(v_rp -> 'opcoes', '[]'::jsonb)) with ordinality t(e, o)), '[]'::jsonb));
      end if;
      continue when (v_rp ->> 'payee_id')::uuid = any (v_pes);
      v_pes := v_pes || (v_rp ->> 'payee_id')::uuid;
      v_nomes := v_nomes || case when coalesce((v_rp ->> 'eh_dono')::boolean, false) then 'você' else v_rp ->> 'nome_curto' end;
    end loop;
    v_quem := public._agenda_lista(v_nomes, null);
    v_plural := cardinality(v_pes) > 1;
  end if;

  v_motivo := public._agenda_motivo_dito(p_motivo);
  if v_ev in ('parcial', 'nao_foi') and v_motivo is null then
    return public._agenda_recusa('Me diga o motivo: material, cliente, equipe, clima, imprevisto, anterior, informação, estimativa, urgência ou esqueci.',
                                 'sem_motivo');
  end if;

  if v_ev in ('trabalhou', 'parcial', 'nao_foi') then
    v_res := case v_ev when 'trabalhou' then 'cumprido' when 'parcial' then 'parcial' else 'nao_cumprido' end;
    -- FASE 3 (P4): "eu fui no Lenine" sem estar no plano dele no dia não é recusa: é a intervenção do dono (o *grava* anota
    -- em agenda_intervencoes_do_dono, para a presença das OS parecidas; o plano e a diária não mudam).
    v_interv := v_ev = 'trabalhou' and coalesce(cardinality(v_pes), 0) = 1 and v_pes[1] = public._agenda_dono(v_autor)
                and not exists (select 1 from public.agenda_alocacoes a
                                 where a.service_order_id = v_os and a.dia = v_dia and a.estado in ('publicada', 'fixada')
                                   and a.tipo <> 'reserva' and a.payee_id = v_pes[1]);
    -- o plano do dia: quem estava, e (para feito e em parte) o que já começou
    if not v_interv and not exists (select 1 from public.agenda_alocacoes a
                    where a.service_order_id = v_os and a.dia = v_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva') then
      return public._agenda_recusa(format('%s não estava no plano %s. Para a diária de quem trabalhou, me diga quem e quanto.',
                                          public._agenda_rotulo_da_os(v_os), public._agenda_dia_ref(v_dia, p_hoje)), 'fora_do_plano');
    end if;
    if v_pes is not null and not v_interv then
      v_fora := array(select n from unnest(v_pes, v_nomes) u(p, n)
                       where not exists (select 1 from public.agenda_alocacoes a
                                          where a.service_order_id = v_os and a.dia = v_dia and a.estado in ('publicada', 'fixada')
                                            and a.tipo <> 'reserva' and a.payee_id = u.p));
      if cardinality(v_fora) > 0 then
        return public._agenda_recusa(format('Pelo plano, %s não %s no %s %s.', public._agenda_lista(v_fora, null),
                                            case when cardinality(v_fora) > 1 then 'estavam' else 'estava' end,
                                            v_ro ->> 'cliente_curto', public._agenda_dia_ref(v_dia, p_hoje)), 'pessoa_fora_do_plano');
      end if;
    end if;
    if not v_interv and v_res <> 'nao_cumprido'
       and not exists (select 1 from public.agenda_alocacoes a
                        where a.service_order_id = v_os and a.dia = v_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                          and (v_pes is null or a.payee_id = any (v_pes)) and lower(a.periodo) <= p_agora) then
      return public._agenda_recusa(format('Ainda não começou nada do plano do %s %s.', v_ro ->> 'cliente_curto',
                                          public._agenda_dia_ref(v_dia, p_hoje)), 'nao_comecou');
    end if;
    select bool_or(a.turno = 'manha'), bool_or(a.turno = 'tarde') into v_m, v_t
      from public.agenda_alocacoes a
     where a.service_order_id = v_os and a.dia = v_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
       and (v_pes is null or a.payee_id = any (v_pes));
    v_turnos := case when v_m and v_t then ' o dia todo' when v_m then ' de manhã' when v_t then ' à tarde' else '' end;
    v_frase := case
      when v_interv then 'você foi sem estar no plano: anoto a sua presença (o plano e as diárias não mudam)'
      when v_ev = 'trabalhou' and v_quem is null then 'feito, com ' || public._agenda_quem(v_os, v_dia)
      when v_ev = 'trabalhou' then v_quem || case when v_plural then ' trabalharam' else ' trabalhou' end || v_turnos
      when v_ev = 'parcial' and v_quem is null then format('andou em parte (%s)', public._agenda_motivo_texto(v_motivo))
      when v_ev = 'parcial' then format('%s %s em parte (%s)', v_quem, case when v_plural then 'trabalharam' else 'trabalhou' end,
                                        public._agenda_motivo_texto(v_motivo))
      when v_quem is null then format('não andou (%s)', public._agenda_motivo_texto(v_motivo))
      else format('%s %s (%s)', v_quem, case when v_plural then 'não foram' else 'não foi' end, public._agenda_motivo_texto(v_motivo)) end;
    v_chave := format('andamento:%s:%s:%s', v_os, v_dia,
                      coalesce('p' || left(md5((select string_agg(x::text, ',' order by x) from unnest(v_pes) x)), 20), 'todos'));

  elsif v_ev = 'comecou' then
    if v_status = 'in_progress' then
      return public._agenda_recusa(format('%s já está em andamento.', public._agenda_rotulo_da_os(v_os)), 'ja_em_andamento');
    end if;
    if v_status not in ('open', 'approved', 'scheduled', 'awaiting_parts', 'awaiting_client') then
      return public._agenda_recusa(format('%s está %s: a agenda não muda o status dela.', public._agenda_rotulo_da_os(v_os),
                                          public._agenda_status_texto(v_status)), 'status');
    end if;
    -- o início é a manhã do dia dito (o banco deriva a hora; ninguém grava hora dita)
    v_check := lower(public.agenda_periodo(v_dia, 'manha'));
    v_frase := format('começou (início às %s)', to_char(v_check at time zone 'America/Sao_Paulo', 'HH24:MI'));
    v_chave := format('andamento:%s:%s:status', v_os, v_dia);

  else  -- parou
    if v_motivo is null or v_motivo not in ('material', 'cliente_ou_bem') then
      return public._agenda_recusa('Parou por quê? Se falta peça, diga material; se o cliente ou o barco não liberou, diga cliente.',
                                   'parou_motivo');
    end if;
    v_para := case when v_motivo = 'material' then 'awaiting_parts' else 'awaiting_client' end;
    if v_status = v_para then
      return public._agenda_recusa(format('%s já está %s.', public._agenda_rotulo_da_os(v_os), public._agenda_status_texto(v_para)),
                                   'ja_esta');
    end if;
    if v_status not in ('open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client') then
      return public._agenda_recusa(format('%s está %s: a agenda não muda o status dela.', public._agenda_rotulo_da_os(v_os),
                                          public._agenda_status_texto(v_status)), 'status');
    end if;
    v_futuros := array(select distinct a.dia from public.agenda_alocacoes a
                        where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.resultado is null
                          and lower(a.periodo) > p_agora order by 1);
    v_frase := format('parou (%s): passa a %s%s', public._agenda_motivo_texto(v_motivo), public._agenda_status_texto(v_para),
                      case when cardinality(v_futuros) > 0
                           then ' e sai da agenda ' || public._agenda_dias_texto(v_futuros) else '' end);
    v_chave := format('andamento:%s:%s:status', v_os, v_dia);
  end if;

  v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'andamento', v_chave, v_os,
             jsonb_build_object('grupo', format('andamento:%s:%s', v_os, v_dia),
                                'rotulo_grupo', public._agenda_maiuscula(public._agenda_dia_ref(v_dia, p_hoje)) || ', '
                                                || public._agenda_rotulo_da_os(v_os),
                                'os', v_os, 'dia', v_dia, 'evento', v_ev, 'resultado', v_res, 'pessoas', to_jsonb(v_pes),
                                'nomes', to_jsonb(v_nomes), 'motivo', v_motivo, 'status_para', v_para, 'check_in', v_check,
                                'frase_pronta', v_frase),
             p_trecho, p_hoje);
  return jsonb_build_object('ok', true, 'item', v_txt,
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
end;
$function$;

comment on function public.agenda_rascunho_andamento(uuid, text, text, text, text, text[], text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P4): o que aconteceu na OS vira RASCUNHO (nada muda) — trabalhou · parcial · nao_foi (o resultado do meio-dia no plano: as pessoas ditas têm de estar no plano do dia; feito e em parte só no que já começou; parcial e não foi pedem o motivo LCI) · comecou (em andamento, com o início na manhã do dia dito) · parou (material → aguardando peças; cliente → aguardando o cliente; sai da agenda o que ainda não começou). Fase 3: concluiu (terminou, acabou, finalizou, pronto) e entregou (entregue) viram rascunho pela _agenda_rascunho_marco, em todos os modos ("Concluo o Lenine (OS-00074) hoje (qui 29/10): fica registrada a saída, e saem as cobranças da condição: …"; o *grava* conclui e entrega pela porta, via dono). O dia por agenda_data_dita (passado, dito no trecho; sem dia = hoje). Chave andamento:<os>:<dia>:<quem> (começou/parou: :status); a releitura junta os fatos da OS no dia ("Hoje (ter 03/11), Vanderlei (OS-00069): Roberto trabalhou o dia todo; João não foi (equipe)."). O *grava* chama agenda_registrar_dia (via conversa) ou a porta (via dono). Fase 3 (P4): "eu fui" do dono numa OS em que ele não estava no plano do dia vira a intervenção dele ("você foi sem estar no plano: anoto a sua presença…"; o *grava* grava agenda_intervencoes_do_dono).';

-- ── Portas ───────────────────────────────────────────────────────────────────────────────────────────────
-- As leituras e os textos (invoker; a RLS de quem lê vale): authenticated e service_role, nunca anon.
revoke all on function
  public._agenda_payees_do_telefone(text, date), public._agenda_payee_do_telefone(text, date),
  public._agenda_local_da_os(uuid), public._agenda_bem_da_os(uuid), public._agenda_servico_curto(uuid),
  public._agenda_dia_da_equipe(date, date), public._agenda_hora_curta(timestamptz),
  public._agenda_ler_resposta_da_equipe(text), public._agenda_confirmacao_do_dia(uuid, date),
  public._agenda_modo_da_equipe(), public._agenda_contatos_com_plano(date),
  public.agenda_diaria_da_agenda(uuid, date), public._agenda_equipe_fora_da_janela(text, timestamptz, timestamptz)
  from public, anon;
grant execute on function
  public._agenda_payees_do_telefone(text, date), public._agenda_payee_do_telefone(text, date),
  public._agenda_local_da_os(uuid), public._agenda_bem_da_os(uuid), public._agenda_servico_curto(uuid),
  public._agenda_dia_da_equipe(date, date), public._agenda_hora_curta(timestamptz),
  public._agenda_ler_resposta_da_equipe(text), public._agenda_confirmacao_do_dia(uuid, date),
  public._agenda_modo_da_equipe(), public._agenda_contatos_com_plano(date),
  public.agenda_diaria_da_agenda(uuid, date), public._agenda_equipe_fora_da_janela(text, timestamptz, timestamptz)
  to authenticated, service_role;

-- A palavra do dono: o painel (authenticated, com o administrador conferido dentro) e o WhatsApp (service_role).
revoke all on function public.agenda_diaria_dita(uuid, text, text, text, text, date, timestamptz) from public, anon;
grant execute on function public.agenda_diaria_dita(uuid, text, text, text, text, date, timestamptz) to authenticated, service_role;

-- O que fala com a equipe ou age sozinho: só service_role (o webhook e o task-automations).
revoke all on function
  public.agenda_equipe_ficha(uuid, date, date), public.agenda_resposta_da_equipe(text, text, text, timestamptz),
  public.agenda_rotina_rodar(date, timestamptz)
  from public, anon, authenticated;
grant execute on function
  public.agenda_equipe_ficha(uuid, date, date), public.agenda_resposta_da_equipe(text, text, text, timestamptz),
  public.agenda_rotina_rodar(date, timestamptz)
  to service_role;

-- As peças de dentro: ninguém de fora (só as funções security definer acima as chamam; os gatilhos rodam sozinhos).
revoke all on function
  public._agenda_equipe_enfileirar(uuid), public._agenda_equipe_registrar(uuid, date, text, text, timestamptz, date, text),
  public._agenda_fila_da_equipe(), public._agenda_equipe_perguntar(text, text, uuid, uuid, date, text, text, timestamptz, jsonb, smallint),
  public._agenda_acoes_diaria_confirmada(),
  public._agenda_perguntar_diaria(uuid, date, text, jsonb, uuid[], date, timestamptz, jsonb),
  public._agenda_lancar_diaria(uuid, date, numeric, uuid[], text, text, uuid, date, timestamptz, jsonb),
  public._agenda_diaria_do_dia(uuid, date, text, date, timestamptz),
  public._agenda_decidir_diaria(uuid, smallint, uuid, text, text, date, timestamptz),
  public._agenda_desfazer_diaria(uuid, uuid, date, timestamptz, boolean),
  public._agenda_rotina_fila(date, timestamptz), public._agenda_rotina_ficha(date, timestamptz),
  public._agenda_rotina_confirmar(date, timestamptz), public._agenda_rotina_silencio(date, timestamptz),
  public._agenda_rotina_como_foi(date, timestamptz), public._agenda_rotina_sem_resposta(date, timestamptz),
  public._agenda_rotina_acordes_da_equipe(date, timestamptz), public._agenda_rotina_diarias(date, timestamptz),
  public._agenda_rotina_resultado_pela_diaria(date, timestamptz), public._agenda_rotina_conclusao(date, timestamptz),
  public._agenda_rotina_entrega(date, timestamptz),
  public._agenda_equipe_quando_responder(timestamptz), public._agenda_equipe_no_dia(uuid, date, boolean, uuid)
  from public, anon, authenticated, service_role;

-- As recriadas mantêm as portas delas (create or replace não muda a ACL; repetidas aqui para a migration se bastar):
revoke all on function public.agenda_registrar_dia(uuid, date, text, text, uuid, uuid[], text, text, date, timestamptz, text) from public, anon;
grant execute on function public.agenda_registrar_dia(uuid, date, text, text, uuid, uuid[], text, text, date, timestamptz, text)
  to authenticated, service_role;
revoke all on function public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz),
                       public.agenda_desfazer(uuid, uuid, text, date, timestamptz)
  from public, anon, authenticated;
grant execute on function public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz),
                          public.agenda_desfazer(uuid, uuid, text, date, timestamptz)
  to service_role;
revoke all on function public._agenda_texto_do_acorde(uuid, date, date), public.agenda_saude(date, timestamptz) from public, anon;
grant execute on function public._agenda_texto_do_acorde(uuid, date, date), public.agenda_saude(date, timestamptz)
  to authenticated, service_role;
