-- Agenda: a ficha mostra a OS e segura a ficha de OS PAGA por inteiro (18/11/2026)
-- Plano: D:/IA-HBR/agenda-pesquisa/via-os129-1711/plano/PLANO.md (F2). Decisão do dono (18/11 ~00:35): "Segura a ficha".
--
-- O caso (OS-00129, 17-18/11): orçamento de 28/10 já FEITO (pelo Alex, em outubro) e PAGO por inteiro (R$ 750, Pix de 31/10,
-- lançado 16/11 23:51) foi convertido sem sinal em 16/11 e a agenda o marcou para qua 18/11. A pergunta da ficha das 19:30
-- ("Hoje às 19:30 a ficha de amanhã vai para Alex: <cliente>, qua 18/11 o dia todo — dia 1 de 1, …") não dizia o número da OS
-- nem que ela estava paga; com o "Mande", o Alex recebeu ficha e via de um dia inteiro para um serviço feito. E a pergunta só
-- existe na janela de veto (marcar_sozinho_desde + ficha_veto_dias = até 23/11): depois, ficha, confirmação e via saem sozinhas.
--
-- O que muda:
--   1. _agenda_os_paga_por_inteiro(os) e _agenda_ficha_os_pagas(pessoa, dia), novas: paga por inteiro = soma de
--      receivables.paid_amount (fora as canceladas) >= grand_total - 0,01, com grand_total > 0 e a OS fora de completed, invoiced
--      e cancelled; as OS pagas da pessoa no dia são as da alocação vigente pela estimativa (publicada/fixada, sem reserva,
--      duracao_fonte orcamento) — a mesma que a proteção da ficha já olha.
--   2. _agenda_ficha_liberada: a pessoa (não o dono) com OS paga no dia só tem a ficha (e a confirmação da manhã, e a ficha que iria
--      no "como foi") com o *mande* do DONO de verdade — a pergunta respondida com a 1 por um canal do dono (nunca o prazo). O
--      silêncio nunca solta. Vale dentro e fora da janela de veto e sem marcar_sozinho_desde. Sem OS paga, o de antes.
--   3. _agenda_gestor_fichas: TODA pergunta da ficha leva o número da OS ("OS-00129 Fulano, qua 18/11 o dia todo — dia 1 de 1").
--      Com OS paga: "A OS-00129 já está PAGA por inteiro: o serviço ainda vai ser feito? Sem resposta até 19:30, eu seguro a ficha."
--      e a recomendação e o padrão viram a 2 (Segure). Fora da janela (ou sem o ligar do gestor) ela só pergunta a quem tem OS paga.
--      A pergunta aberta que nasceu antes de a OS ficar paga (padrão 1, sem resposta) não muda o que pergunta (o gatilho
--      _agenda_perguntas_antes recusa): ela fica resolvida ("a OS ficou paga…") e nasce a nova, com o mesmo insert do gravador.
--   4. _agenda_rotina_ficha: a ficha presa por OS paga diz o porquê ao dono ("Não mandei a ficha de qua 18/11 a Alex (OS-00129
--      Fulano): a OS já está paga por inteiro e <porquê>. Fale com Alex."): sem pergunta, "e não consegui te perguntar antes das 19:30"
--      (por = paga_sem_pergunta); não mostrada, "e você não viu a pergunta" (paga_nao_vista); mostrada e sem resposta, "e você não
--      disse *mande*" (paga). A pergunta fecha com o motivo verdadeiro. Fora disso, byte a byte.
--   5. _agenda_linhas_do_fechamento: na linha (m), a ficha de OS paga (padrão 2) vem antes das outras fichas do dia (a 2ª sairia só
--      como "Também …", sem o aviso); e a forma curta dela termina com "Para mandar, me diga *mande*." no lugar de "Para segurar, me
--      diga." (que contradiria o "eu seguro") — um bloco depois do laço da (m), que troca só essa frase no texto_curto. Fora disso,
--      byte a byte.
-- Toda mudança é ACRÉSCIMO, em blocos "-- FICHA PAGA: (…) … -- FICHA PAGA: fim" (o "if" novo com o código de antes no meio, como a 7f
-- fez com o prazo). A única linha trocada (a ordem da (m)) vai dentro do bloco junto da de antes, numa linha "--antes:" na coluna 0:
-- tirados os blocos e devolvidas as "--antes:", cada função recriada é a de origem, byte a byte (conferir-acrescimo.mjs). Os testes
-- que conferem a cópia na função viva fazem o mesmo com pg_temp.sem_ficha_paga.
-- A via do técnico (task-automations/via-da-agenda.ts) só lê a ficha que foi para a fila (fila_id): ficha recusada = via não sai.
--
-- Fora daqui (bordas conhecidas, no RESUMO da F2): o puxar da 7e (ficha_presa só olha a janela); o "mande" dado antes de a OS
-- ficar paga vale; a OS que deixa de estar paga com a pergunta aberta (o texto dizia "eu seguro", vale a regra de antes).
--
-- DESFAZER: D:/IA-HBR/agenda-pesquisa/via-os129-1711/plano/F2/desfazer.sql (as 4 definições de antes, sem as 2 funções novas).

-- ── 1. A OS paga por inteiro e as OS pagas da pessoa no dia ─────────────────────────────────────────────
create or replace function public._agenda_os_paga_por_inteiro(p_os uuid)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce((
    select so.grand_total > 0
           and so.status not in ('completed', 'invoiced', 'cancelled')
           and coalesce((select sum(coalesce(r.paid_amount, 0)) from public.receivables r
                          where r.service_order_id = so.id and r.status is distinct from 'cancelled'), 0) >= so.grand_total - 0.01
      from public.service_orders so
     where so.id = p_os), false);
$function$;

comment on function public._agenda_os_paga_por_inteiro(uuid) is
  'Agenda de Produção (ficha paga, 18/11/2026, 20270125100000; o caso OS-00129): a OS está paga por inteiro? soma de receivables.paid_amount (fora as canceladas) >= grand_total - 0,01, com grand_total > 0 e a OS fora de completed, invoiced e cancelled. Sem a OS = false. STABLE, invoker (lê com a RLS de quem pergunta, como _agenda_ficha_liberada); authenticated e service_role.';

create or replace function public._agenda_ficha_os_pagas(p_payee uuid, p_dia date)
 returns uuid[]
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(array_agg(x.os order by x.ini, x.os), '{}'::uuid[])
    from (select a.service_order_id as os, min(lower(a.periodo)) as ini
            from public.agenda_alocacoes a
           where a.payee_id = p_payee and a.dia = p_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
             and a.duracao_fonte = 'orcamento'
           group by a.service_order_id) x
   where public._agenda_os_paga_por_inteiro(x.os);
$function$;

comment on function public._agenda_ficha_os_pagas(uuid, date) is
  'Agenda de Produção (ficha paga, 18/11/2026, 20270125100000): as OS pagas por inteiro (_agenda_os_paga_por_inteiro) entre as da alocação vigente da pessoa no dia pela estimativa (publicada ou fixada, sem reserva, duracao_fonte orcamento — a da proteção da ficha), na ordem do dia. Nenhuma = {}. STABLE, invoker; authenticated e service_role.';

-- ── 2. A ficha liberada ─────────────────────────────────────────────────────────────────────────────────
-- _agenda_ficha_liberada (de 20261031100850_agenda_fase7a_protecoes.sql; md5 do corpo de antes ec5ad2b9c7015dd67adf286846dbf285 sem CR)
create or replace function public._agenda_ficha_liberada(p_payee uuid, p_dia date, p_agora timestamptz)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select case
    when p_payee is null or p_dia is null or p_agora is null then true
    -- FICHA PAGA: (18/11/2026) a pessoa (não o dono) com OS paga por inteiro no dia, pela estimativa, só tem a ficha com o *mande* do
    -- DONO de verdade: a pergunta respondida com a 1 por um canal dele (nunca o prazo). O silêncio nunca solta. Dentro e fora da
    -- janela de veto, com ou sem o ligar do gestor.
    when p_payee is distinct from public._agenda_dono(null)
         and cardinality(public._agenda_ficha_os_pagas(p_payee, p_dia)) > 0 then
      exists (select 1 from public.agenda_perguntas q
               where q.chave = format('ficha_estimativa:%s:%s', p_payee, p_dia) and q.modo = 'ligado'
                 and q.estado = 'respondida' and q.opcao_escolhida = 1 and q.respondida_via is distinct from 'prazo'
                 and q.respondida_em <= p_agora)
    -- FICHA PAGA: fim
    when cf.marcar_sozinho_desde is null then true
    when p_dia < (cf.marcar_sozinho_desde at time zone 'America/Sao_Paulo')::date
      or p_dia >= (cf.marcar_sozinho_desde at time zone 'America/Sao_Paulo')::date + cf.ficha_veto_dias then true
    when p_payee is not distinct from public._agenda_dono(null) then true
    when not exists (select 1 from public.agenda_alocacoes a
                      where a.payee_id = p_payee and a.dia = p_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                        and a.duracao_fonte = 'orcamento') then true
    else exists (select 1 from public.agenda_perguntas q
                  where q.chave = format('ficha_estimativa:%s:%s', p_payee, p_dia) and q.modo = 'ligado'
                    and q.mostrada_vezes > 0 and q.mostrada_em <= p_agora and q.opcao_escolhida is distinct from 2)
  end
    from public.agenda_config cf
   where cf.id;
$function$;

comment on function public._agenda_ficha_liberada(uuid, date, timestamptz) is
  'Agenda de Produção (Fase 7a, P11; AG7-15): a ficha (e a confirmação da manhã) da pessoa no dia pode sair? true fora da janela de veto (marcar_sozinho_desde nulo, ou p_dia fora de [o dia do ligar, + ficha_veto_dias)), para o dono e para o dia sem alocação vigente da pessoa com duracao_fonte orcamento; senão só com a pergunta ficha_estimativa:<pessoa>:<dia> de verdade (modo ligado) mostrada ao dono até p_agora e não segurada (opcao_escolhida distinta de 2). Lida por _agenda_rotina_ficha, _agenda_rotina_como_foi e _agenda_rotina_confirmar (recriadas pelo P11). STABLE, invoker; authenticated e service_role. FICHA PAGA (18/11/2026, 20270125100000; o caso OS-00129): a pessoa (não o dono) com OS paga por inteiro no dia pela estimativa (_agenda_ficha_os_pagas) só tem a ficha, a confirmação da manhã e a ficha do "como foi" com o *mande* do dono de verdade — a pergunta ficha_estimativa:<pessoa>:<dia> de verdade respondida com a 1 por um canal do dono (respondida_via distinta de prazo) até p_agora; o silêncio nunca solta; vale dentro e fora da janela e sem o ligar do gestor. Sem OS paga, o de antes.';

-- ── 3. A pergunta da ficha ─────────────────────────────────────────────────────────────────────────────
-- _agenda_gestor_fichas (de 20261031100985_agenda_fase77a_correcao2.sql; md5 do corpo de antes b652c8f60de5d8795391e89e3b814031 sem CR)
create or replace function public._agenda_gestor_fichas(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config;
  v_modo  text;
  v_desde date;
  v_d     date;
  v_ate   timestamptz;
  v_hora  text;
  v_quando text;
  v_dono  uuid := public._agenda_dono(null);
  p       record;
  v_os    uuid;
  v_partes text[];
  v_txt   text;
  v_id    uuid;
  v_novas int := 0;
  v_lista jsonb := '[]'::jsonb;
  v_ops   jsonb;
  -- FICHA PAGA: (18/11/2026) a OS paga por inteiro
  v_janela boolean;
  v_pagas  boolean;
  v_fp_os  uuid[];
  v_fp_rot text;
  v_fp_q   public.agenda_perguntas%rowtype;
  -- FICHA PAGA: fim
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_fichas: sem o dia ou a hora' using errcode = '22004';
  end if;
  cf := public._agenda_cfg();
  v_modo := coalesce(public._agenda_modo_da_pergunta('ficha_estimativa', null), 'desligado');
  if v_modo = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'as mensagens à equipe estão desligadas');
  end if;
  -- FICHA PAGA: (18/11/2026) a ficha de OS paga por inteiro pergunta dentro e fora da janela e sem o ligar do gestor: alguém (não o
  -- dono) com OS paga no próximo dia útil, pela estimativa. Sem ninguém assim, os pulos de antes.
  v_d := public.agenda_somar_du(p_hoje, 1);
  v_pagas := exists (select 1 from public.agenda_alocacoes a
                      where a.dia = v_d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.duracao_fonte = 'orcamento'
                        and a.payee_id is distinct from v_dono and public._agenda_os_paga_por_inteiro(a.service_order_id));
  if not v_pagas then
  -- FICHA PAGA: fim
  if cf.marcar_sozinho_desde is null then
    return jsonb_build_object('pulado', true, 'motivo', 'o gestor ainda não marca sozinho: sem janela da ficha');
  end if;
  -- FICHA PAGA: (fecha o "se ninguém tem OS paga")
  end if;
  -- FICHA PAGA: fim
  if not public.agenda_dia_util(p_hoje) then
    return jsonb_build_object('pulado', true, 'motivo', 'não é dia útil');
  end if;
  v_desde := (cf.marcar_sozinho_desde at time zone 'America/Sao_Paulo')::date;
  v_d := public.agenda_somar_du(p_hoje, 1);
  -- FICHA PAGA: (18/11/2026) a janela; fora dela (e sem o ligar do gestor), só a OS paga
  v_janela := v_desde is not null and v_d >= v_desde and v_d < v_desde + cf.ficha_veto_dias;
  if not v_pagas then
  -- FICHA PAGA: fim
  if v_d < v_desde or v_d >= v_desde + cf.ficha_veto_dias then
    return jsonb_build_object('pulado', true, 'motivo', 'fora da janela da ficha', 'dia', v_d);
  end if;
  -- FICHA PAGA: (fecha o "se ninguém tem OS paga")
  end if;
  -- FICHA PAGA: fim
  v_ate := (p_hoje + cf.equipe_hora_ficha) at time zone 'America/Sao_Paulo';
  if p_agora >= v_ate then
    return jsonb_build_object('pulado', true, 'motivo', 'já passou a hora da ficha', 'dia', v_d);
  end if;
  v_hora := to_char(cf.equipe_hora_ficha, 'HH24:MI');
  v_quando := case when v_d = p_hoje + 1 then 'amanhã'
                   else (array['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'])[extract(isodow from v_d)::int] end;
  v_ops := jsonb_build_array(
    jsonb_build_object('n', 1, 'texto', 'Mande', 'efeito', jsonb_build_object('mandar', true)),
    jsonb_build_object('n', 2, 'texto', 'Segure a ficha: eu não mando e você fala com ele', 'efeito', jsonb_build_object('segurar', true)));

  for p in
    select c.payee_id, public._agenda_nome_curto(py.name) as nome
      from public._agenda_contatos_com_plano(v_d) c(payee_id)
      join public.payees py on py.id = c.payee_id
     where c.payee_id is distinct from v_dono
       and exists (select 1 from public.agenda_alocacoes a
                    where a.payee_id = c.payee_id and a.dia = v_d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                      and a.duracao_fonte = 'orcamento')
       -- FASE 7: (7a correção 2, a ficha prometida a quem não tem telefone) só quem tem para onde a ficha ir: sem telefone ela não sai
       -- de jeito nenhum, e a pergunta prometia "Hoje às 19:30 a ficha de amanhã vai para Alex" (e às 19:30 a fechava "ela foi como
       -- eu disse"). A ficha de quem não tem telefone fica segurada e diz o porquê (_agenda_rotina_ficha): o dono avisa de boca.
       and public._agenda_equipe_tem_telefone(c.payee_id)
       -- FASE 7: fim
       -- FICHA PAGA: (18/11/2026) fora da janela, só quem tem OS paga no dia
       and (v_janela or cardinality(public._agenda_ficha_os_pagas(c.payee_id, v_d)) > 0)
       -- FICHA PAGA: fim
       -- a ficha desse dia já foi decidida (registrada, ou de carona no "como foi hoje?"): não há o que perguntar
       and not exists (select 1 from public.agenda_equipe_mensagens m
                        where m.payee_id = c.payee_id and m.modo = 'ligado'
                          and ((m.tipo = 'ficha' and m.dia = v_d) or (m.tipo = 'como_foi' and m.leva_ficha_de = v_d)))
     order by 2, 1
  loop
    -- o que a ficha diz desse dia pela estimativa: cada OS dele no dia, o turno e que dia é do plano dela
    select array_agg(format('%s, %s %s — dia %s de %s', o.cliente, public._dia_curto(v_d),
                            case when o.m and o.t then 'o dia todo' when o.m then 'de manhã' else 'à tarde' end, o.k, o.n)
                     order by o.ini, o.os),
           (array_agg(o.os order by o.ini, o.os))[1]
      into v_partes, v_os
      from (select a.service_order_id as os, min(lower(a.periodo)) as ini,
                   bool_or(a.turno = 'manha') as m, bool_or(a.turno = 'tarde') as t,
                   coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) as cliente,
                   (select count(distinct b.dia) from public.agenda_alocacoes b
                     where b.service_order_id = a.service_order_id and b.estado in ('publicada', 'fixada') and b.tipo <> 'reserva'
                       and b.presenca = 'turno' and b.dia <= v_d) as k,
                   (select count(distinct b.dia) from public.agenda_alocacoes b
                     where b.service_order_id = a.service_order_id and b.estado in ('publicada', 'fixada') and b.tipo <> 'reserva'
                       and b.presenca = 'turno') as n
              from public.agenda_alocacoes a
              join public.service_orders so on so.id = a.service_order_id
              left join public.clients cl on cl.id = so.client_id
             where a.payee_id = p.payee_id and a.dia = v_d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
               and a.duracao_fonte = 'orcamento'
             group by a.service_order_id, cl.name, so.service_order_number) o;
    -- FICHA PAGA: (18/11/2026) o número da OS na frente do nome ("OS-00129 Fulano, qua 18/11 o dia todo — dia 1 de 1"): as mesmas
    -- partes, de novo, com o número
    select array_agg(format('%s, %s %s — dia %s de %s', concat_ws(' ', o.numero, o.cliente), public._dia_curto(v_d),
                            case when o.m and o.t then 'o dia todo' when o.m then 'de manhã' else 'à tarde' end, o.k, o.n)
                     order by o.ini, o.os)
      into v_partes
      from (select a.service_order_id as os, min(lower(a.periodo)) as ini,
                   bool_or(a.turno = 'manha') as m, bool_or(a.turno = 'tarde') as t,
                   so.service_order_number as numero, public._agenda_nome_curto(cl.name) as cliente,
                   (select count(distinct b.dia) from public.agenda_alocacoes b
                     where b.service_order_id = a.service_order_id and b.estado in ('publicada', 'fixada') and b.tipo <> 'reserva'
                       and b.presenca = 'turno' and b.dia <= v_d) as k,
                   (select count(distinct b.dia) from public.agenda_alocacoes b
                     where b.service_order_id = a.service_order_id and b.estado in ('publicada', 'fixada') and b.tipo <> 'reserva'
                       and b.presenca = 'turno') as n
              from public.agenda_alocacoes a
              join public.service_orders so on so.id = a.service_order_id
              left join public.clients cl on cl.id = so.client_id
             where a.payee_id = p.payee_id and a.dia = v_d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
               and a.duracao_fonte = 'orcamento'
             group by a.service_order_id, cl.name, so.service_order_number) o;
    -- FICHA PAGA: fim
    -- FICHA PAGA: (18/11/2026) com OS paga por inteiro, o aviso e a recomendação e o padrão na 2 (Segure): sem resposta, eu seguro.
    -- A aberta que nasceu antes de a OS ficar paga (padrão 1, sem resposta) não muda o que pergunta (o gatilho recusa): fica
    -- resolvida e nasce a nova, com o mesmo insert do gravador (_agenda_gestor_perguntar não devolve a mesma chave fechada).
    v_fp_os := public._agenda_ficha_os_pagas(p.payee_id, v_d);
    v_id := null;
    if cardinality(v_fp_os) > 0 then
      v_fp_rot := public._agenda_lista(array(select so.service_order_number from unnest(v_fp_os) with ordinality u(os, o)
                                              join public.service_orders so on so.id = u.os order by u.o), null);
      v_txt := format('Hoje às %s a ficha de %s vai para %s: %s, pela minha estimativa.', v_hora, v_quando, p.nome,
                      array_to_string(v_partes, '; '))
               || case when cardinality(v_fp_os) = 1
                       then format(' A %s já está PAGA por inteiro: o serviço ainda vai ser feito?', v_fp_rot)
                       else format(' As %s já estão PAGAS por inteiro: os serviços ainda vão ser feitos?', v_fp_rot) end
               || format(' Sem resposta até %s, eu seguro a ficha.', v_hora)
               || ' 1) Mande; 2) Segure a ficha: eu não mando e você fala com ele (recomendo).';
      select q.* into v_fp_q from public.agenda_perguntas q
       where q.chave = format('ficha_estimativa:%s:%s', p.payee_id, v_d) and q.modo = v_modo and q.estado = 'aberta';
      if v_fp_q.id is not null and v_fp_q.opcao_padrao is distinct from 2 and v_fp_q.opcao_escolhida is null then
        update public.agenda_perguntas
           set estado = 'resolvida', resolvida_motivo = 'a OS ficou paga por inteiro depois desta pergunta: perguntei de novo, avisando'
         where id = v_fp_q.id;
        insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, perda_em, texto, opcoes, recomendacao, modo,
                                             criada_em, expira_em, veto_ate, opcao_padrao)
        values ('ficha_estimativa', v_fp_q.chave, v_os, case when v_os is null then '{}'::uuid[] else array[v_os] end,
                (v_ate at time zone 'America/Sao_Paulo')::date, left(public._agenda_corta(v_txt, 600), 600), v_ops, 2::smallint,
                v_modo, p_agora, v_ate + cf.desfazer_validade, v_ate, 2::smallint)
        returning id into v_id;
      end if;
      if v_id is null then
        v_id := public._agenda_gestor_perguntar('ficha_estimativa', format('ficha_estimativa:%s:%s', p.payee_id, v_d), v_os, v_txt,
                                                v_ops, 2::smallint, v_ate, 2::smallint, v_modo, p_agora);
      end if;
    else
    -- FICHA PAGA: fim
    v_txt := format('Hoje às %s a ficha de %s vai para %s: %s, pela minha estimativa.', v_hora, v_quando, p.nome,
                    array_to_string(v_partes, '; '))
             || ' 1) Mande (recomendo); 2) Segure a ficha: eu não mando e você fala com ele.';
    v_id := public._agenda_gestor_perguntar('ficha_estimativa', format('ficha_estimativa:%s:%s', p.payee_id, v_d), v_os, v_txt,
                                            v_ops, 1::smallint, v_ate, 1::smallint, v_modo, p_agora);
    -- FICHA PAGA: (fecha o "se tem OS paga")
    end if;
    -- FICHA PAGA: fim
    if v_id is not null and exists (select 1 from public.agenda_perguntas q where q.id = v_id and q.criada_em = p_agora) then
      v_novas := v_novas + 1;
    end if;
    v_lista := v_lista || jsonb_build_object('pessoa', p.payee_id, 'nome', p.nome, 'pergunta_id', v_id, 'texto', v_txt);
  end loop;
  return jsonb_build_object('dia', v_d, 'prazo', v_ate, 'modo', v_modo, 'perguntas', jsonb_array_length(v_lista),
                            'novas', v_novas, 'pessoas', v_lista);
end;
$function$;

comment on function public._agenda_gestor_fichas(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P11; AG7-15, spec §5.11 e §6.3): o passo diário fichas da rodada do gestor — com o ligar do gestor (marcar_sozinho_desde) e o próximo dia útil dentro das ficha_veto_dias a partir dele, para cada pessoa da rotina (_agenda_contatos_com_plano, sem o dono) com alocação vigente nesse dia de duracao_fonte orcamento e sem a ficha do dia já decidida, a pergunta ficha_estimativa (chave ficha_estimativa:<pessoa>:<dia>; veto_ate = hoje às equipe_hora_ficha; opções 1 Mande / 2 Segure; recomendação e padrão 1): "Hoje às 19:30 a ficha de amanhã vai para Roberto: Lenine, ter 03/11 o dia todo — dia 1 de 6, pela minha estimativa. 1) Mande (recomendo); 2) Segure a ficha: eu não mando e você fala com ele." (o dia que não é amanhã pelo nome: "a ficha de terça"). O modo é o de _agenda_modo_da_pergunta(''ficha_estimativa'') — o das mensagens à equipe; desligado, fora da janela, depois da hora da ficha ou fora de dia útil = {pulado}. {dia, prazo, modo, perguntas, novas, pessoas [{pessoa, nome, pergunta_id, texto}]}. Invoker, sem grant. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; a ficha prometida a quem não tem telefone): só pergunta a ficha de quem tem para onde ela ir (_agenda_equipe_tem_telefone, a régua de _agenda_equipe_registrar): sem telefone, nenhuma pergunta — a ficha fica segurada às 19:30 e o aviso diz "não tem telefone no cadastro. Fale com Alex.". FICHA PAGA (18/11/2026, 20270125100000; o caso OS-00129): toda pergunta leva o número da OS ("Alex: OS-00129 Fulano, qua 18/11 o dia todo — dia 1 de 1"). Com OS paga por inteiro (_agenda_ficha_os_pagas): "… pela minha estimativa. A OS-00129 já está PAGA por inteiro: o serviço ainda vai ser feito? Sem resposta até 19:30, eu seguro a ficha. 1) Mande; 2) Segure a ficha: eu não mando e você fala com ele (recomendo).", recomendação e padrão 2; fora da janela e sem o ligar do gestor, só pergunta a quem tem OS paga (sem nenhuma, os pulos de antes). A aberta que nasceu antes de a OS ficar paga (padrão 1, sem resposta) fica resolvida ("a OS ficou paga por inteiro depois desta pergunta: perguntei de novo, avisando") e nasce a nova, com o insert do gravador.';

-- ── 4. A ficha das 19:30 ───────────────────────────────────────────────────────────────────────────────
-- _agenda_rotina_ficha (de 20261109101000_agenda_fase7f_equipe.sql; md5 do corpo de antes 592d7ce112fa55352963cce9262406b5 sem CR)
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
  -- FASE 7: (7a P11) a ficha de um dia pela estimativa, na janela de veto
  v_f11_q   public.agenda_perguntas%rowtype;
  v_f11_m   uuid;
  v_f11_a   uuid;
  v_f11_os  uuid[];
  v_f11_cli text;
  v_f11_nom text;
  v_f72_fecha boolean := false;  -- (7a correção 2) a pergunta da ficha fecha depois do registro, com o que houve
  -- FICHA PAGA: (18/11/2026) as OS pagas por inteiro da pessoa no dia (_agenda_ficha_os_pagas)
  v_fp_os   uuid[];
  -- FICHA PAGA: fim
  -- FASE 7: fim
  -- FASE 7f: (7f P5) o previsto e a mudança junto da ficha
  v_7f_s    jsonb;
  v_7f_prev boolean;
  v_7f_mud  boolean;
  v_7f_txt  text;
  v_7f_dias date[];
  -- FASE 7f: fim
begin
  if v_local::time < cf.equipe_hora_ficha or not public.agenda_dia_util(p_hoje) then
    return jsonb_build_object('fichas', 0);
  end if;
  v_d := public.agenda_somar_du(p_hoje, 1);
  for v_p in select x from public._agenda_contatos_com_plano(v_d) x loop
    continue when exists (select 1 from public.agenda_equipe_mensagens m
                           where m.payee_id = v_p and m.modo = v_modo
                             and ((m.tipo = 'ficha' and m.dia = v_d) or (m.tipo = 'como_foi' and m.leva_ficha_de = v_d)));
    -- FASE 7f: (7f P5, §5.5 (1), AG7-23 "Sim, só vira dia dele com o sim") quem tem o convite de amanhã enviado e ainda sem o SIM não recebe a ficha:
    -- o dia ainda não é dele. Só com o convite ligado de verdade (com o freio, o de antes: a ficha sai).
    continue when public._agenda_fala_modo('convite') = 'ligado'
                  and exists (select 1 from public.agenda_equipe_mensagens m
                               where m.payee_id = v_p and m.tipo = 'convite' and m.dia = v_d and m.modo = 'ligado'
                                 and m.estado in ('enfileirada', 'sem_resposta', 'respondida')
                                 and m.leitura ->> 'convite' is distinct from 'sim');
    -- FASE 7f: fim
    v_f := public.agenda_equipe_ficha(v_p, v_d, p_hoje);
    continue when not coalesce((v_f ->> 'tem_plano')::boolean, false);
    -- FASE 7: (7a P11, spec §3.2 "Equipe" e §5.11; AG7-15) nas primeiras ficha_veto_dias a partir do ligar do gestor, a ficha de
    -- um dia marcado pela estimativa (a alocação da pessoa no dia com duracao_fonte orcamento) só sai com a pergunta
    -- ficha_estimativa daquele dia mostrada ao dono e não segurada (_agenda_ficha_liberada). Senão ela fica registrada como
    -- recusada (veto): nada vai à fila nem conta no teto da pessoa. Se o dono não soube (não viu a pergunta a tempo, ou ela nem
    -- nasceu), o que mudou conta para ele (a ação equipe da vigia: o fechamento e o *o que mudou* do dia seguinte). A pergunta do
    -- dia fecha aqui: a hora da ficha chegou. Só com a mensagem de verdade (em teste nada sai de todo jeito).
    if v_modo = 'ligado' then
      v_f11_q := null;
      select q.* into v_f11_q from public.agenda_perguntas q
       where q.chave = format('ficha_estimativa:%s:%s', v_p, v_d) and q.modo = 'ligado'
       order by q.criada_em desc, q.id desc limit 1;
      if not public._agenda_ficha_liberada(v_p, v_d, p_agora) then
        insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, recusa_motivo, dedupe_key,
                                                    criada_em)
        values (v_p, v_d, 'ficha', 'ligado', left(v_f ->> 'texto_ficha', 600), p_agora, 'recusada', 'veto',
                format('agenda-equipe:ficha:%s:%s', v_p, v_d), p_agora)
        returning id into v_f11_m;
        -- FICHA PAGA: (18/11/2026) a ficha presa por OS paga por inteiro diz o porquê ao dono (por = paga)
        v_fp_os := public._agenda_ficha_os_pagas(v_p, v_d);
        -- FICHA PAGA: fim
        if v_f11_q.id is null or v_f11_q.opcao_escolhida is distinct from 2 then
          v_f11_os := array(select a.service_order_id from public.agenda_alocacoes a
                             where a.payee_id = v_p and a.dia = v_d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                               and a.duracao_fonte = 'orcamento'
                             group by a.service_order_id order by min(lower(a.periodo)), a.service_order_id);
          v_f11_cli := public._agenda_lista(array(
                         select coalesce(public._agenda_nome_curto(cl.name), so.service_order_number)
                           from unnest(v_f11_os) with ordinality u(os, o)
                           join public.service_orders so on so.id = u.os left join public.clients cl on cl.id = so.client_id
                          order by u.o), null);
          v_f11_nom := (select public._agenda_nome_curto(py.name) from public.payees py where py.id = v_p);
          -- FICHA PAGA: (18/11/2026) a ficha presa por OS paga por inteiro: o porquê é esse ("Não mandei a ficha de qua 18/11 a Alex
          -- (OS-00129 Fulano): a OS já está paga por inteiro e <porquê>. Fale com Alex."), dito pelo que houve com a pergunta: sem pergunta,
          -- "e não consegui te perguntar antes das 19:30" (por paga_sem_pergunta); não mostrada, "e você não viu a pergunta" (paga_nao_vista);
          -- mostrada e sem resposta, "e você não disse *mande*" (paga). O texto é o do insert: a ação não muda depois de gravada (o gatilho
          -- _agenda_acoes_so_desfaz). Sem telefone, o de antes (ela não sairia de todo jeito).
          if cardinality(v_fp_os) > 0 and not (v_f11_q.id is null and not public._agenda_equipe_tem_telefone(v_p)) then
            insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
            values (clock_timestamp(), p_hoje, true, 'vigia', 'equipe', v_f11_os[1], v_f11_os, v_p,
                    jsonb_build_object('motivo', 'ficha_segurada', 'dia', v_d, 'mensagem', v_f11_m, 'pergunta', v_f11_q.id,
                                       'por', case when v_f11_q.id is null then 'paga_sem_pergunta'
                                                   when coalesce(v_f11_q.mostrada_vezes, 0) = 0 then 'paga_nao_vista'
                                                   else 'paga' end),
                    left(format('Não mandei a ficha de %s a %s (%s): %s %s. Fale com %s.',
                                public._dia_curto(v_d), v_f11_nom,
                                public._agenda_lista(array(
                                  select concat_ws(' ', so.service_order_number, public._agenda_nome_curto(cl.name))
                                    from unnest(v_fp_os) with ordinality u(os, o)
                                    join public.service_orders so on so.id = u.os left join public.clients cl on cl.id = so.client_id
                                   order by u.o), null),
                                case when cardinality(v_fp_os) = 1 then 'a OS já está paga por inteiro'
                                     else 'as OS já estão pagas por inteiro' end,
                                case when v_f11_q.id is null
                                       then 'e não consegui te perguntar antes das ' || to_char(cf.equipe_hora_ficha, 'HH24:MI')
                                     when coalesce(v_f11_q.mostrada_vezes, 0) = 0 then 'e você não viu a pergunta'
                                     else 'e você não disse *mande*' end,
                                v_f11_nom), 400))
            returning id into v_f11_a;
          else
          -- FICHA PAGA: fim
          insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
          values (clock_timestamp(), p_hoje, true, 'vigia', 'equipe', v_f11_os[1], v_f11_os, v_p,
                  jsonb_build_object('motivo', 'ficha_segurada', 'dia', v_d, 'mensagem', v_f11_m, 'pergunta', v_f11_q.id,
                                     -- (7a correção 2) quem não tem telefone não ganha a pergunta: o porquê é esse
                                     'por', case when v_f11_q.id is null and not public._agenda_equipe_tem_telefone(v_p) then 'sem_telefone'
                                                 when v_f11_q.id is null then 'sem_pergunta' else 'nao_vista' end),
                  left(format('Não mandei a ficha de %s a %s (%s): o dia é pela minha estimativa e %s. Fale com %s.',
                              public._dia_curto(v_d), v_f11_nom, v_f11_cli,
                              -- (7a correção 2) sem telefone no cadastro: o gestor não pergunta a ficha (ela não sairia), e o
                              -- dono fica sabendo que tem de avisar de boca
                              case when v_f11_q.id is null and not public._agenda_equipe_tem_telefone(v_p)
                                     then format('%s não tem telefone no cadastro', v_f11_nom)
                                   when v_f11_q.id is null then 'não consegui te perguntar antes'
                                   else 'você não viu a pergunta antes das ' || to_char(cf.equipe_hora_ficha, 'HH24:MI') end,
                              v_f11_nom), 400))
          returning id into v_f11_a;
          -- FICHA PAGA: (fecha o "se a OS está paga")
          end if;
          -- FICHA PAGA: fim
          update public.agenda_equipe_mensagens set acao_id = v_f11_a where id = v_f11_m;
        end if;
        -- FICHA PAGA: (18/11/2026) a pergunta da OS paga fecha com o motivo dela (o update de baixo não acha mais a aberta)
        if cardinality(v_fp_os) > 0 then
          update public.agenda_perguntas
             set estado = 'resolvida',
                 resolvida_motivo = case when coalesce(v_f11_q.mostrada_vezes, 0) = 0
                                         then 'a OS estava paga por inteiro e você não viu a pergunta: a ficha não saiu'
                                         else 'a OS estava paga por inteiro e você não disse mande: a ficha não saiu' end
           where chave = format('ficha_estimativa:%s:%s', v_p, v_d) and modo = 'ligado' and estado = 'aberta';
        end if;
        -- FICHA PAGA: fim
        update public.agenda_perguntas
           set estado = 'resolvida', resolvida_motivo = 'na hora da ficha você não tinha visto a pergunta: a ficha não saiu'
         where chave = format('ficha_estimativa:%s:%s', v_p, v_d) and modo = 'ligado' and estado = 'aberta';
        v_cont := v_cont || jsonb_build_object('recusada', coalesce((v_cont ->> 'recusada')::int, 0) + 1);
        continue;
      end if;
      -- (7a correção 2) a pergunta fecha logo abaixo, depois do registro: antes ela fechava aqui "ela foi como eu disse" e o
      -- registro recusava em seguida (sem telefone, teto, janela) — o dono lia que a ficha tinha ido
      v_f72_fecha := true;
    end if;
    -- FASE 7: fim
    -- FASE 7f: (7f P5, §5.5 (2) e (3), §6.4, R8.5-17) com o previsto ligado de verdade (o freio = teste) e a equipe ligada, a ficha leva o que a
    -- semana da pessoa tem a dizer, numa mensagem só: a mudança dos dias que ela já ouviu ("Na semana: sai …; entra …") e, na quinta, o previsto da
    -- semana que vem. A ficha grava em dias o que a pessoa passa a ter ouvido. Sem nada a dizer, ou passando de 600 letras, a ficha de antes (e os
    -- passos previsto e mudancas_equipe da rodada comunicar mandam o que ficou de fora, sozinho). Fora disso, byte a byte a de antes.
    v_7f_txt := null;
    v_7f_dias := null;
    if v_modo = 'ligado' and public._agenda_fala_modo('previsto') = 'ligado' then
      v_7f_s := public._agenda_equipe_semana_da_pessoa(v_p, p_hoje, p_agora);
      v_7f_prev := jsonb_array_length(coalesce(v_7f_s -> 'previsto', '[]'::jsonb)) > 0
                   and not exists (select 1 from public.agenda_equipe_mensagens m
                                    where m.payee_id = v_p and m.tipo = 'previsto' and m.dia = (v_7f_s ->> 'seg')::date and m.modo = 'ligado');
      v_7f_mud := jsonb_typeof(v_7f_s -> 'mudanca') = 'object'
                  and not exists (select 1 from public.agenda_equipe_mensagens m
                                   where m.dedupe_key = format('agenda-equipe:mudanca:%s:%s:19h', v_p, p_hoje));
      if v_7f_prev or v_7f_mud then
        v_7f_txt := case when v_7f_mud then v_7f_s ->> 'texto_mudanca_junto' else '' end
                    || case when v_7f_prev then v_7f_s ->> 'texto_previsto_junto' else '' end;
        v_7f_dias := array(select x::date from jsonb_array_elements_text(v_7f_s -> case when v_7f_prev and v_7f_mud then 'estado_ambos'
                                                                                   when v_7f_prev then 'estado_previsto'
                                                                                   else 'estado_mudanca' end) x order by 1);
        if char_length(coalesce(v_f ->> 'texto_ficha', '')) + char_length(v_7f_txt) > 600 then
          v_7f_txt := null;
          v_7f_dias := null;
        end if;
      end if;
    end if;
    if v_7f_txt is not null then
      v_r := public._agenda_equipe_registrar(v_p, v_d, 'ficha', (v_f ->> 'texto_ficha') || v_7f_txt, p_agora, null, null, v_7f_dias);
    else
    -- FASE 7f: fim
    v_r := public._agenda_equipe_registrar(v_p, v_d, 'ficha', v_f ->> 'texto_ficha', p_agora);
    -- FASE 7f: (7f P5) o fim do if de cima
    end if;
    -- FASE 7f: fim
    -- FASE 7: (7a correção 2, a ficha prometida a quem não tem telefone) a pergunta da ficha liberada fecha com o que aconteceu
    -- no registro: enfileirada = "ela foi como eu disse"; recusada (o teto, a janela, o telefone que sumiu) = o porquê
    if v_f72_fecha then
      update public.agenda_perguntas
         set estado = 'resolvida',
             resolvida_motivo = case when v_r ->> 'estado' = 'recusada'
                                     then format('na hora da ficha você não a segurou, mas ela não saiu (%s)',
                                                 case v_r ->> 'motivo' when 'sem_telefone' then 'sem telefone no cadastro'
                                                                       when 'teto' then 'o limite de mensagens do dia'
                                                                       when 'janela' then 'fora do horário de mandar'
                                                                       when 'parou' then 'a pessoa não recebe mais a rotina'
                                                                       else coalesce(v_r ->> 'motivo', 'recusada') end)
                                     else 'na hora da ficha você não a segurou: ela foi como eu disse' end
       where chave = format('ficha_estimativa:%s:%s', v_p, v_d) and modo = 'ligado' and estado = 'aberta';
      v_f72_fecha := false;
    end if;
    -- FASE 7: fim
    v_cont := v_cont || jsonb_build_object(coalesce(v_r ->> 'estado', 'nada'),
                                           coalesce((v_cont ->> coalesce(v_r ->> 'estado', 'nada'))::int, 0) + 1);
  end loop;
  return jsonb_build_object('dia', v_d, 'por_estado', v_cont);
end;
$function$;

comment on function public._agenda_rotina_ficha(date, timestamptz) is
  'Agenda de Produção (Fase 3, P4): a ficha da véspera (equipe_hora_ficha num dia útil) para o próximo dia útil — não vai a quem já recebeu a ficha desse dia nem a quem recebeu o "como foi hoje?" levando a ficha; o texto de agenda_equipe_ficha, pelo _agenda_equipe_registrar. FASE 7 (7a P11, spec §3.2 "Equipe" e §5.11; AG7-15): com a mensagem de verdade, a ficha que _agenda_ficha_liberada não solta (na janela de veto do ligar, um dia da pessoa marcado pela estimativa sem a pergunta ficha_estimativa mostrada, ou segurada com a 2) fica registrada como recusada (veto) — nada vai à fila nem conta no teto — e, se o dono não soube, a ação equipe da vigia conta no que mudou ("Não mandei a ficha de ter 03/11 a Roberto (Lenine): o dia é pela minha estimativa e você não viu a pergunta antes das 19:30. Fale com Roberto."); a pergunta do dia fecha (resolvida). Fora disso, a de antes, byte a byte. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; a ficha prometida a quem não tem telefone): a ficha segurada de quem não tem telefone diz o porquê ("Não mandei a ficha de qui 05/11 a Alex (Lenine): o dia é pela minha estimativa e Alex não tem telefone no cadastro. Fale com Alex.", por = sem_telefone); e a pergunta da ficha que fechou "ela foi como eu disse" com a ficha recusada no registro ganha o motivo verdadeiro ("… mas ela não saiu (sem telefone no cadastro)"). FASE 7f (P5): com o convite ligado de verdade, quem tem o convite de amanhã sem o SIM não recebe a ficha (AG7-23); com o previsto ligado de verdade e a equipe ligada, a ficha leva a mudança da semana ("Na semana: sai …; entra …") e, na quinta, o previsto da semana que vem, numa mensagem só, e grava em dias o que a pessoa passa a ter ouvido. Fora disso, a de antes, byte a byte. FICHA PAGA (18/11/2026, 20270125100000): a ficha presa por OS paga por inteiro (_agenda_ficha_liberada) diz o porquê ao dono — "Não mandei a ficha de qua 18/11 a Alex (OS-00129 Fulano): a OS já está paga por inteiro e <porquê>. Fale com Alex.": sem pergunta, "e não consegui te perguntar antes das 19:30" (por = paga_sem_pergunta); pergunta não mostrada, "e você não viu a pergunta" (paga_nao_vista); mostrada sem resposta, "e você não disse *mande*" (paga). Sem telefone, o de antes. A pergunta aberta fecha com o motivo dela ("a OS estava paga por inteiro e você não viu a pergunta | não disse mande: a ficha não saiu"). Fora disso, byte a byte.';

-- ── 5. A forma curta da linha (m) no fechamento ─────────────────────────────────────────────────────────
-- _agenda_linhas_do_fechamento (de 20261107100400_agenda_fase7d_combinar.sql; md5 do corpo de antes c286fe8dc33eb9bb6dc1470f90f3649d sem CR)
create or replace function public._agenda_linhas_do_fechamento(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_max   constant int := 480;   -- estrutural: uma linha da agenda no fechamento
  -- FASE 3: o fim do texto da conferência da vigia (é o que a linha dia troca quando tem o que contar da equipe)
  c_cauda constant text := ' Foi isso? Responda *dia feito* ou conte o que mudou.';
  v_ini   date;
  v_am1   date;
  v_am2   date;
  v_out   jsonb := '[]'::jsonb;
  q       record;
  g       jsonb;
  v_m     jsonb;
  v_ms    jsonb;
  v_conf  record;
  v_txts  text[];
  v_ids   jsonb;
  v_txt   text;
  v_mod   text;
  v_n     int;
  k       int;
  m       text;
  -- FASE 3
  v_eq    jsonb;
  v_base  text;
  v_dia   text;
  v_som   text;
  v_extra text;
  v_cauda text;
  v_pend  jsonb;
  v_tec   text;
  v_cob   text;
  v_ppc   jsonb;
  v_com   jsonb;
  -- FASE 7: (7a P7) a linha do gestor em teste e a das compras da semana
  v_f7_txt   text;
  v_f7_cmp   jsonb;
  v_f7_min   date;
  v_f7_urg   boolean;
  v_f7_perda int;
  -- FASE 7: fim
  -- FASE 7: (7a correção, achados 15 e 18) a linha das perguntas do gestor
  c_max_perg  constant int := 600;   -- estrutural: até 640 na coleta, como a do cliente
  v_f77_ids   jsonb;
  v_f77_txt   text;
  v_f77_prazo boolean;
  v_f77_segs  text[];
  v_f77_grupo text;
  v_f77_itens text[];
  v_f77_rest  int;
  v_f77_nl    text;
  v_f77_item  text;
  v_f77_ns    text[];
  v_f77_ni    text[];
  v_f77_l     text;
  v_f77_q     record;
  -- FASE 7: fim
  -- FASE 7b: (7b P3, R4.2(d)) a linha (n) da equipe
  v_7b_on     boolean;
  v_7b_ids    jsonb;
  v_7b_txt    text;
  v_7b_itens  text[];
  v_7b_curtos text[];
  v_7b_rest   int;
  v_7b_perde  boolean;
  v_7b_lig    boolean;
  v_7b_item   text;
  v_7b_curto  text;
  v_7b_l      text;
  v_7b_q      record;
  -- (correção 3) o prazo de quem vence, na forma curta
  v_c3_ate    timestamptz;
  -- (correção 3: fim)
  -- FASE 7b: fim
  -- FASE 7c: (7c P5, R5.4 item 4) a linha (n) com as perguntas de quem faz o quê
  v_7c_on    boolean;
  v_7c_7b    boolean;
  v_7c_q     record;
  v_7c_eq    boolean;
  v_7c_marc  text;
  v_7c_exig  text;
  v_7c_ate   timestamptz;
  -- FASE 7c: fim
  -- FASE 7c: (7c P8, R5.4 item 4, R5.2-2(b)) as perguntas das etapas na linha (n) e a linha (o) das etapas
  v_p8_on     boolean;
  v_p8_q      record;
  v_p8_quem   boolean;
  v_p8_pess   record;
  v_p8_h      jsonb;
  v_p8_a      jsonb;
  v_p8_hi     jsonb;
  v_p8_ai     jsonb;
  v_p8_nomes  text[] := '{}';
  v_p8_nfone  int;
  v_p8_nrot   int;
  v_p8_hoje   jsonb := '[]'::jsonb;
  v_p8_amanha jsonb := '[]'::jsonb;
  v_p8_txt    text;
  v_p8_curto  text;
  v_p8_alta   boolean;
  v_p8_k      int;
  v_p8_g      record;
  v_p8_parte  text[];
  v_p8_dia    text;
  -- FASE 7c: fim
  -- FASE 7c: (7c correção, achados 14, 8 e 2) a 7b que espera a vez dela, a forma curta do cliente e a (n) que ficou de fora
  c_c2_dias   constant int := 2;    -- estrutural: os dias úteis que a pergunta de quem faz o quê espera sem ser vista antes de subir
  c_c2_perda  constant int := 77;   -- estrutural: acima das perguntas do gestor (76), abaixo da compra e da decisão (80)
  v_c14_pula  boolean;
  v_c8_agora  timestamptz;
  v_c8_tipo   text;
  v_c8_env    timestamptz;
  v_c8_qid    uuid;
  v_c8_nome   text;
  v_c8_n      int;
  v_c8_curto  text;
  -- FASE 7c: fim
  -- FASE 7c: (7c correção 2, achados 1, 11, 13 e 15) a cobrança do último dia antes de um dia de revisão, as linhas de 75 que sobem
  -- juntas e a "Também" de quem faz o quê que conta
  v_c13_av     jsonb := '[]'::jsonb;
  v_c13_d      date;
  v_c13_prox   date;
  v_c13_k      int;
  v_c13_p      record;
  v_c13_u      jsonb;
  v_c13_rev    boolean;
  v_c13_q      text;
  v_c13_parte  text[];
  v_c13_ult    boolean := false;
  v_c11_tambem boolean := false;
  -- FASE 7c: fim
begin
  if p_hoje is null then
    raise exception 'agenda: sem o dia de hoje' using errcode = '22004';
  end if;
  if cf.modo_proposta = 'desligado' and cf.modo_vigia = 'desligado' then
    return '[]'::jsonb;
  end if;
  v_ini := p_hoje - 6;
  v_am1 := public.agenda_somar_du(p_hoje, 1);
  v_am2 := public.agenda_somar_du(p_hoje, 2);

  -- (a) as decisões críticas abertas
  -- FASE 3: menos a da diária, que tem a linha dela (b2)
  for q in select x.* from public.agenda_perguntas x where x.critica and x.estado = 'aberta' and x.tipo <> 'diaria'
            -- FASE 7d: (7d P5, §5.5) a crítica acesso em que o dono já disse "vou combinar hoje" fica aberta até o dia, mas não volta ao fechamento
            and not (x.tipo = 'acesso' and x.opcao_escolhida is not null)
            -- FASE 7d: fim
            order by x.perda_em nulls last, x.criada_em, x.id loop
    v_out := v_out || jsonb_build_object('tipo', 'decisao',
      'texto', 'Agenda, preciso de você. ' || q.texto || ' Me responda aqui.',
      'perda', case when q.perda_em is not null and q.perda_em <= v_am1 then 100
                    when q.perda_em is not null and q.perda_em <= v_am2 then 80 else 50 end,
      'pergunta_id', q.id, 'acao_ids', '[]'::jsonb,
      'modo', case when q.modo = 'ligado' and cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- FASE 3 (a2): a diária que diverge do plano (crítica): as opções, a recomendação e as palavras que respondem.
  -- A perda: o banco não sabe quando o acerto fecha (o dono fecha quando quer); com 2 dias úteis sem resposta, 80.
  for q in select x.* from public.agenda_perguntas x where x.tipo = 'diaria' and x.estado = 'aberta'
            order by x.perda_em nulls last, x.criada_em, x.id loop
    v_out := v_out || jsonb_build_object('tipo', 'diaria',
      'texto', 'Diária, preciso de você: ' || public._agenda_texto_da_diaria(q.id),
      'perda', case when public.agenda_du_entre(coalesce(q.dia, q.perda_em, p_hoje), p_hoje) >= 2 then 80 else 50 end,
      'pergunta_id', q.id, 'acao_ids', '[]'::jsonb,
      'modo', case when q.modo = 'ligado' and cf.modo_diaria = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- (b) o que mudou sozinho (de verdade e na sombra), ainda não contado
  v_m := public._agenda_mudancas(v_ini, p_hoje, true, true, null);
  v_ms := public._agenda_mudancas(v_ini, p_hoje, false, true, null);

  -- (c) a semana publicada
  for g in select x from jsonb_array_elements(v_m) x where x ->> 'tipo' = 'publicacao' loop
    v_out := v_out || jsonb_build_object('tipo', 'semana',
      'texto', public._agenda_linha_da_semana((g ->> 'proposta_id')::uuid, g -> 'acao_ids', (g ->> 'desfazivel')::boolean, p_hoje),
      'perda', 60, 'pergunta_id', null, 'acao_ids', g -> 'acao_ids',
      'modo', case when cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end);
  end loop;
  for g in select x from jsonb_array_elements(v_ms) x where x ->> 'tipo' = 'publicacao' loop
    v_out := v_out || jsonb_build_object('tipo', 'semana',
      'texto', public._agenda_linha_da_semana((g ->> 'proposta_id')::uuid, g -> 'acao_ids', false, p_hoje),
      'perda', 60, 'pergunta_id', null, 'acao_ids', g -> 'acao_ids', 'modo', 'sombra');
  end loop;

  -- (d) a conferência de hoje, com o que mudou sozinho; sem ela, o que mudou numa linha só
  select x.* into v_conf from public.agenda_perguntas x
   where x.tipo = 'conferencia' and x.estado = 'aberta' and x.dia = p_hoje
   order by (x.modo = 'ligado') desc, x.criada_em desc, x.id desc limit 1;
  -- FASE 3: o que a equipe confirmou, a diária que a agenda lançou, quem falta confirmar e o último dia da OS
  v_eq := public._agenda_dia_da_equipe(p_hoje);
  v_pend := v_eq -> 'pendentes';
  v_extra := nullif(array_to_string(array(select x from jsonb_array_elements_text(v_eq -> 'lig') x
                                          union all select x from jsonb_array_elements_text(v_eq -> 'ultimo') x), ' '), '');
  for m in select unnest(array['ligado', 'sombra']) loop
    v_txts := array(select public._agenda_mudanca_texto(x, false)
                      from jsonb_array_elements(case when m = 'ligado' then v_m else v_ms end) with ordinality t(x, o)
                     where x ->> 'tipo' = 'acao' order by o);
    v_ids := coalesce((select jsonb_agg(y order by o, o2)
                         from jsonb_array_elements(case when m = 'ligado' then v_m else v_ms end) with ordinality t(x, o),
                              jsonb_array_elements(x -> 'acao_ids') with ordinality u(y, o2)
                        where x ->> 'tipo' = 'acao'), '[]'::jsonb);
    v_mod := case when m = 'ligado' and cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end;
    if v_conf.id is not null and v_conf.modo = m then
      -- FASE 3: o texto do dia com a equipe. Sem nada a contar, é o da conferência, byte a byte.
      v_dia := v_conf.texto;
      if v_extra is not null or jsonb_array_length(v_pend) > 0 then
        v_base := case when right(v_conf.texto, char_length(c_cauda)) = c_cauda
                       then left(v_conf.texto, char_length(v_conf.texto) - char_length(c_cauda)) else v_conf.texto end;
        v_cauda := case
          when jsonb_array_length(v_pend) = 1
            then format(' Foi isso para o %s? *dia feito* lança a %s dele, ou conte o que mudou.', v_pend -> 0 ->> 'nome',
                        case when (v_pend -> 0 ->> 'meios')::int = 1 then 'meia diária' else 'diária' end)
          when jsonb_array_length(v_pend) > 1
            then format(' Foi isso para %s? *dia feito* lança as diárias deles, ou conte o que mudou.',
                        public._agenda_lista(array(select 'o ' || (e ->> 'nome') from jsonb_array_elements(v_pend) with ordinality t(e, o)
                                                    order by o), null))
          when (v_eq ->> 'aguardando')::int > 0 and cf.modo_diaria = 'ligado' then ' Foi isso? *dia feito* lança agora.'
          else c_cauda end;
        v_dia := v_base || coalesce(' ' || v_extra, '') || v_cauda;
      end if;
      v_ids := v_ids || (v_eq -> 'ids');
      for k in reverse cardinality(v_txts) .. 0 loop
        v_txt := v_dia
                 || case when k > 0 then ' Mudei sozinho: ' || array_to_string(v_txts[1:k], ' ')
                                         || case when k < cardinality(v_txts) then format(' (e mais %s em *o que mudou*)', cardinality(v_txts) - k) else '' end
                         when cardinality(v_txts) > 0 then format(' Mudei sozinho %s: *o que mudou* mostra.',
                                                                   public._agenda_plural(cardinality(v_txts), 'coisa', 'coisas'))
                         else '' end;
        exit when char_length(v_txt) <= c_max;
      end loop;
      v_out := v_out || jsonb_build_object('tipo', 'dia', 'texto', v_txt, 'perda', 70, 'pergunta_id', v_conf.id, 'acao_ids', v_ids,
        'modo', case when v_conf.modo = 'ligado' and cf.modo_vigia = 'ligado' and v_mod = 'ligado' then 'ligado' else 'sombra' end);
      -- FASE 3: o que a sombra da equipe e da diária diria, só no detalhe
      if jsonb_array_length(v_eq -> 'som') > 0 then
        v_som := v_dia || ' ' || array_to_string(array(select x from jsonb_array_elements_text(v_eq -> 'som') x), ' ');
        v_out := v_out || jsonb_build_object('tipo', 'dia', 'texto', public._agenda_corta(v_som, c_max), 'perda', 70,
                                             'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', 'sombra');
      end if;
    elsif cardinality(v_txts) > 0 then
      for k in reverse cardinality(v_txts) .. 1 loop
        v_txt := 'Agenda, mudei sozinho. ' || array_to_string(v_txts[1:k], ' ')
                 || case when k < cardinality(v_txts) then format(' (e mais %s em *o que mudou*)', cardinality(v_txts) - k) else '' end;
        exit when char_length(v_txt) <= c_max;
      end loop;
      v_out := v_out || jsonb_build_object('tipo', 'mudancas', 'texto', v_txt, 'perda', 40, 'pergunta_id', null, 'acao_ids', v_ids,
                                           'modo', v_mod);
    end if;
  end loop;
  -- a conferência na sombra sem nada a contar junto, ou de um modo sem mudança (o laço acima já cobriu quem teve)
  -- (nada a fazer: o laço passa pelos dois modos)

  -- FASE 3 (d1): sem a conferência aberta (todos confirmaram), o dia com o que a equipe e a diária contam numa linha
  -- própria: a diária que a agenda lançou ("*diária Roberto meia* corrige") e o último dia da OS.
  if v_conf.id is null and (v_extra is not null or jsonb_array_length(v_eq -> 'som') > 0) then
    v_base := public._agenda_texto_do_dia(p_hoje);
    if v_base is not null then
      v_cauda := case when jsonb_array_length(v_eq -> 'lancadas') > 0
                      then format(' *diária %s %s* corrige.', v_eq -> 'lancadas' -> 0 ->> 'nome',
                                  case when (v_eq -> 'lancadas' -> 0 ->> 'fracao')::numeric = 1 then 'meia' else 'inteira' end)
                      else '' end;
      if v_extra is not null then
        v_out := v_out || jsonb_build_object('tipo', 'dia', 'texto', public._agenda_corta(v_base || ' ' || v_extra || v_cauda, c_max),
          'perda', 70, 'pergunta_id', null, 'acao_ids', v_eq -> 'ids',
          'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
      end if;
      if jsonb_array_length(v_eq -> 'som') > 0 then
        v_out := v_out || jsonb_build_object('tipo', 'dia',
          'texto', public._agenda_corta(v_base || coalesce(' ' || v_extra, '') || ' '
                                        || array_to_string(array(select x from jsonb_array_elements_text(v_eq -> 'som') x), ' '), c_max),
          'perda', 70, 'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', 'sombra');
      end if;
    end if;
  end if;

  -- FASE 3 (d2): o que o gestor concluiu pela palavra do técnico (o técnico disse que terminou e era o último dia do
  -- plano), ainda não contado: a cobrança que a conclusão disse e o *desfaz* pelo número (a OS saiu da carteira).
  for q in select x.* from public.agenda_acoes x
            where x.tipo = 'concluir' and x.origem = 'equipe' and x.contada_em is null and x.desfeita_em is null
              and x.dia between v_ini and p_hoje
            order by x.criada_em, x.id loop
    v_tec := (select public._agenda_nome_curto(py.name) from public.agenda_equipe_mensagens em
                join public.payees py on py.id = em.payee_id where em.acao_id = q.id
               order by em.resposta_em desc nulls last limit 1);
    if q.executada then
      -- revisão da Fase 3 (item 5): o "vence hoje" de outro dia pelo ajudante único
      v_cob := public._agenda_vence_no_dia(regexp_replace(q.texto, '^[^—]* — saída [^.]*\.\s*', ''), q.dia, p_hoje);
      v_txt := format('Concluí o %s%s: o %s disse que terminou e era o último dia do plano.%s *desfaz %s* reabre.',
                      public._agenda_rotulo_da_os(q.service_order_id),
                      case when q.dia <> p_hoje then ' ' || public._dia_curto(q.dia) else '' end,
                      coalesce(v_tec, 'técnico'), coalesce(' ' || nullif(v_cob, q.texto), ''),
                      (select so.service_order_number from public.service_orders so where so.id = q.service_order_id));
    else
      v_txt := q.texto;
    end if;
    v_out := v_out || jsonb_build_object('tipo', 'conclusao', 'texto', public._agenda_corta(v_txt, c_max), 'perda', 45,
      'pergunta_id', null, 'acao_ids', jsonb_build_array(q.id),
      'modo', case when q.executada and cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- FASE 7: (7a correção, achados 15 e 18; no lugar da linha (l) do 7a P11) (m) as perguntas do gestor que esperam o dono numa
  -- linha só: a ficha_estimativa de hoje (a ficha das 19:30 de um dia pela estimativa, que perde hoje), a situacao, a estimativa e
  -- o reestimar. Antes, cada uma disputava sozinha a vaga da pergunta de fato (e), de perda 30, e nenhuma chegava ao dono: o prazo
  -- só vale com a pergunta vista, e o gestor não marcava (Nelson, Flávio, Giancarlo e MP fora a semana inteira); a da ficha perdia
  -- para a mensagem ao cliente da véspera, e a ficha do 1º dia ficava segurada. A 1ª (a ficha; depois a de prazo mais perto) vai
  -- com o texto inteiro; as outras curtas, agrupadas pelo prazo ("Também, sem resposta até ter 03/11 18:00: Nelson (OS-00112) 4
  -- dias; Flávio (OS-00104) 3,5 dias."; sem prazo: "Espero você: Giancarlo (OS-00130)."), até c_max_perg; o resto fica para
  -- *agenda gestor*. O fechamento que sai conta como mostradas todas as que a linha leva (pergunta_ids). Perda 75 com alguma de
  -- prazo (ela perde no prazo), 30 sem; modo = o da vigia.
  for m in select unnest(array['ligado', 'sombra']) loop
    v_f77_ids := '[]'::jsonb;
    v_f77_txt := null;
    v_f77_prazo := false;
    v_f77_segs := '{}';
    v_f77_grupo := null;
    v_f77_itens := '{}';
    v_f77_rest := 0;
    for v_f77_q in
      select x.id, x.texto, x.veto_ate, x.service_order_id, x.tipo,
             case when x.veto_ate is null then null
                  else public._dia_curto((x.veto_ate at time zone 'America/Sao_Paulo')::date) || ' '
                       || to_char(x.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI') end as ate,
             (select (o -> 'efeito' ->> 'dias')::numeric from jsonb_array_elements(coalesce(x.opcoes, '[]'::jsonb)) o
               where (o ->> 'n')::int = x.opcao_padrao limit 1) as dias_padrao
        from public.agenda_perguntas x
       where x.estado = 'aberta' and x.modo = m and not x.critica and x.opcao_escolhida is null
         and ((x.tipo = 'ficha_estimativa' and x.veto_ate is not null
               and (x.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
              or (x.tipo in ('situacao', 'estimativa', 'reestimar')
                  and (x.veto_ate is null or (x.veto_ate at time zone 'America/Sao_Paulo')::date >= p_hoje)))
         and x.mostrada_vezes < cf.perguntas_vezes_max
         and not exists (select 1 from public.agenda_dono_avisos v
                          where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
       -- FICHA PAGA: (18/11/2026) a ficha de OS paga (padrão 2) antes das outras fichas do dia: a 2ª ficha sai só como "Também …",
       -- sem o aviso do PAGA nem o "eu seguro". A linha de antes, que a cópia sem os blocos devolve:
--antes:       order by x.tipo = 'ficha_estimativa' desc, x.veto_ate nulls last, x.criada_em, x.id
       order by x.tipo = 'ficha_estimativa' desc, (x.tipo = 'ficha_estimativa' and x.opcao_padrao = 2) desc, x.veto_ate nulls last,
                x.criada_em, x.id
       -- FICHA PAGA: fim
    loop
      if v_f77_txt is null then
        v_f77_txt := 'Agenda: ' || v_f77_q.texto;
        v_f77_ids := jsonb_build_array(v_f77_q.id);
        v_f77_prazo := v_f77_q.veto_ate is not null;
        continue;
      end if;
      if v_f77_rest > 0 then
        v_f77_rest := v_f77_rest + 1;
        continue;
      end if;
      -- (7a correção 2) sem prazo, o porquê junto: acima do teto de diárias o gestor não marca sozinho
      v_f77_nl := case when v_f77_q.ate is null then 'Espero você (não marco sozinho): ' else format('Também, sem resposta até %s: ', v_f77_q.ate) end;
      v_f77_item := public._agenda_rotulo_da_os(v_f77_q.service_order_id)
                    || case when v_f77_q.dias_padrao is not null then ' ' || public._agenda_dias(v_f77_q.dias_padrao) else '' end;
      if v_f77_nl is distinct from v_f77_grupo then
        v_f77_ns := v_f77_segs || case when v_f77_grupo is not null then array[v_f77_grupo || array_to_string(v_f77_itens, '; ') || '.']
                                       else '{}'::text[] end;
        v_f77_ni := array[v_f77_item];
      else
        v_f77_ns := v_f77_segs;
        v_f77_ni := v_f77_itens || v_f77_item;
      end if;
      v_f77_l := v_f77_txt || ' ' || array_to_string(v_f77_ns || (v_f77_nl || array_to_string(v_f77_ni, '; ') || '.'), ' ');
      -- cabe com o "(e mais N em *agenda gestor*)" que pode vir depois
      if char_length(v_f77_l) > c_max_perg - 32 then
        v_f77_rest := 1;
        continue;
      end if;
      v_f77_segs := v_f77_ns;
      v_f77_grupo := v_f77_nl;
      v_f77_itens := v_f77_ni;
      v_f77_ids := v_f77_ids || to_jsonb(v_f77_q.id);
      v_f77_prazo := v_f77_prazo or v_f77_q.veto_ate is not null;
    end loop;
    continue when v_f77_txt is null;
    v_f77_l := v_f77_txt
               || case when v_f77_grupo is not null
                       then ' ' || array_to_string(v_f77_segs || (v_f77_grupo || array_to_string(v_f77_itens, '; ') || '.'), ' ')
                       else '' end
               || case when v_f77_rest > 0 then format(' (e mais %s em *agenda gestor*)', v_f77_rest) else '' end;
    -- (7a correção 2, os achados 15/18 de novo) perda 76 com alguma de prazo: entre as linhas que perdem hoje ela ganha o desempate
    -- (antes, 75 com a mensagem ao cliente, ela perdia pelo tipo — "cliente" < "pergunta" — e saía primeiro no corte de 1.000)
    -- (7a correção 2) o objeto da linha entre parênteses: a forma curta (abaixo) entra nele, não como outro item da lista
    v_out := v_out || (jsonb_build_object('tipo', 'pergunta', 'texto', v_f77_l, 'perda', case when v_f77_prazo then 76 else 30 end,
      'pergunta_id', v_f77_ids ->> 0, 'pergunta_ids', v_f77_ids, 'acao_ids', '[]'::jsonb,
      'modo', case when m = 'ligado' and cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end)
      -- (7a correção 2, o corte de 1.000 do fechamento) a mesma linha na forma curta (texto_curto), com as MESMAS perguntas: a
      -- ficha sem as opções ("… pela minha estimativa. Para segurar, me diga.") e cada uma pelo prazo e pelo que o gestor faz sem
      -- resposta ("Sem resposta até ter 03/11 18:00, conto: Nelson (OS-00112) 4 dias; …"). O Secretário cheio (3 que ficaram, ~900
      -- caracteres) usa esta antes de tirar a linha — a inteira (~400) não cabia e as perguntas nunca eram vistas.
      || coalesce((select jsonb_build_object('texto_curto', k.t) from (select
           'Agenda: ' || concat_ws(' ',
             (select split_part(pc.texto, ' 1) Mande', 1) || ' Para segurar, me diga.' from public.agenda_perguntas pc
               where pc.id = (v_f77_ids ->> 0)::uuid and pc.tipo = 'ficha_estimativa'),
             (select string_agg(g.grupo || g.itens || '.', ' ' order by g.ord)
                from (select case when y.ate is null then 'Espero você (não marco sozinho): '
                                  else format('Sem resposta até %s, conto: ', y.ate) end as grupo,
                             string_agg(y.item, '; ' order by y.o) as itens, min(y.o) as ord
                        from (select t.o,
                                     case when pc.veto_ate is null then null
                                          else public._dia_curto((pc.veto_ate at time zone 'America/Sao_Paulo')::date) || ' '
                                               || to_char(pc.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI') end as ate,
                                     public._agenda_rotulo_da_os(pc.service_order_id)
                                     || coalesce(' ' || public._agenda_dias((select (op -> 'efeito' ->> 'dias')::numeric
                                                                               from jsonb_array_elements(coalesce(pc.opcoes, '[]'::jsonb)) op
                                                                              where (op ->> 'n')::int = pc.opcao_padrao limit 1)), '') as item
                                from jsonb_array_elements_text(v_f77_ids) with ordinality t(id, o)
                                join public.agenda_perguntas pc on pc.id = t.id::uuid
                               where pc.tipo <> 'ficha_estimativa') y
                       group by y.ate) g)) as t) k
         where char_length(k.t) < char_length(v_f77_l)), '{}'::jsonb));
  end loop;
  -- FASE 7: fim
  -- FICHA PAGA: (18/11/2026) na forma curta da linha (m), a ficha de OS paga (padrão 2: "Sem resposta …, eu seguro a ficha."):
  -- "Para mandar, me diga *mande*." no lugar de "Para segurar, me diga." (que contradiria o "eu seguro")
  v_out := coalesce((select jsonb_agg(case when x ->> 'tipo' = 'pergunta'
                                                and coalesce(x ->> 'texto_curto', '') like '%eu seguro a ficha. Para segurar, me diga.%'
                                           then jsonb_set(x, '{texto_curto}', to_jsonb(replace(x ->> 'texto_curto',
                                                  'eu seguro a ficha. Para segurar, me diga.', 'eu seguro a ficha. Para mandar, me diga *mande*.')))
                                           else x end order by e.o)
                       from jsonb_array_elements(v_out) with ordinality e(x, o)), '[]'::jsonb);
  -- FICHA PAGA: fim
  -- FASE 7b: (7b P3, R4.2(d)) (n) a equipe: as perguntas abertas da equipe — a chamada (equipe_cadastro:chamada), a dos dias do
  -- dono (dias_semana), o telefone e o contato — numa linha só, nesta ordem e depois a mais antiga. Pela pergunta de fato (e), de perda
  -- 30, elas nunca entravam nas vagas (as de fornecedor estão abertas e nunca vistas desde 28/10): a chamada nunca seria vista nem
  -- venceria, e a pergunta da semana ficaria esperando por ela. A 1ª vai com o texto inteiro; as outras, curtas, até c_max_perg; o
  -- resto "(e mais N em *agenda equipe*)". pergunta_ids = todas as que a linha mostra (o fechamento que sai as conta como mostradas;
  -- a chamada vista ganha o prazo na rodada da semana). Perda 75 enquanto alguma nunca foi mostrada (o prazo só começa depois de vista)
  -- ou perde hoje (o veto_ate ou o perda_em de hoje): vaga própria entre as que perdem hoje; senão 30. Modo ligado só com a pergunta
  -- em ligado e o modo dela (o de _agenda_modo_da_pergunta: modo_dias; modo_cadastro fora de desligado, senão o do gestor) ligado.
  -- texto_curto = as mesmas perguntas só pelo nome. Só com modo_dias ou modo_cadastro fora de desligado (senão, o de antes); a (e)
  -- não as repete.
  v_7b_on := cf.modo_dias <> 'desligado' or cf.modo_cadastro <> 'desligado';
  -- (7c P5, R5.4 item 4, R5.10-8) o portão da linha separado por etapa: o bloco roda com a 7b (modo_dias ou modo_cadastro) OU com
  -- a 7c (modo_habilidade_propor ou modo_habilidade) fora de desligado; dentro dele, as perguntas da 7b só entram com o portão da 7b
  -- (v_7c_7b) e as de quem faz o quê só com o da 7c (v_7c_on). v_7b_on volta a ser só o da 7b logo depois do bloco: a pergunta de fato
  -- (e) exclui só os tipos que a (n) levou (sem isso, com a 7b desligada e a 7c em teste, a chamada da 7a sairia da (e), perda 30,
  -- para a (n), perda 75, e o texto do dono mudaria).
  v_7c_on := cf.modo_habilidade_propor <> 'desligado' or cf.modo_habilidade <> 'desligado';
  v_7c_7b := v_7b_on;
  v_7b_on := v_7b_on or v_7c_on;
  -- (7c: fim)
  -- (7c P8, R5.4 item 4) e com as etapas (modo_tarefas) fora de desligado: as perguntas das etapas (tarefa) só com o portão delas
  v_p8_on := cf.modo_tarefas <> 'desligado';
  v_7b_on := v_7b_on or v_p8_on;
  -- (7c: fim)
  if v_7b_on then
    for m in select unnest(array['ligado', 'sombra']) loop
      v_7b_ids := '[]'::jsonb;
      v_7b_txt := null;
      v_7b_itens := '{}';
      v_7b_curtos := '{}';
      v_7b_rest := 0;
      v_7b_perde := false;
      v_7b_lig := true;
      -- (7c correção, achado 14) a 7b não gasta a vez dela por causa da 7c: sem nenhuma pergunta da 7b que perca hoje (nunca vista, o
      -- veto ou o prazo de hoje) e com uma de quem faz o quê ou das etapas que perde hoje, as da 7b ficam fora da linha neste dia — a da
      -- 7c vai primeiro e inteira (conta como vista) e a chamada não é contada como mostrada num dia que não é o dela. Antes, com a de
      -- quem faz o quê só como "Também" (não conta), a perda 75 dela fazia a chamada sair e gastar as 2 vezes antes do dia em que vence,
      -- e quem faz o quê só era vista quando a chamada saía da linha. Com a 7b perdendo hoje, a de antes (a 7b primeiro). Sem a 7c, a de antes.
      v_c14_pula := v_7c_7b and (v_7c_on or v_p8_on)
        and not exists (select 1 from public.agenda_perguntas x
                         where x.estado = 'aberta' and x.modo = m and not x.critica and x.tipo in ('equipe_cadastro', 'dias_semana')
                           and x.mostrada_vezes < cf.perguntas_vezes_max
                           and not exists (select 1 from public.agenda_dono_avisos v
                                            where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
                           and (x.mostrada_vezes = 0
                                or (x.veto_ate is not null and (x.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                                or x.perda_em is not distinct from p_hoje))
        and exists (select 1 from public.agenda_perguntas x
                     where x.estado = 'aberta' and x.modo = m and not x.critica
                       and ((v_7c_on and x.tipo = 'habilidade') or (v_p8_on and x.tipo = 'tarefa'))
                       and x.mostrada_vezes < cf.perguntas_vezes_max
                       and not exists (select 1 from public.agenda_dono_avisos v
                                        where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
                       and (x.mostrada_vezes = 0
                            or (x.tipo = 'habilidade'
                                and ((x.veto_ate is not null and (x.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                                     or x.perda_em is not distinct from p_hoje))
                            or (x.tipo = 'tarefa' and x.chave not like 'tarefa:quem:%' and x.perda_em is not null and x.perda_em <= v_am1)));
      -- (7c: fim)
      for v_7b_q in
        select x.id, x.tipo, x.chave, x.texto, x.dia, x.mostrada_vezes, x.veto_ate, x.perda_em,
               coalesce((select public._agenda_nome_curto(py.name) from public.payees py where py.id = x.payee_id), '') as nome,
               case when x.tipo = 'dias_semana' then cf.modo_dias
                    when cf.modo_cadastro <> 'desligado' then cf.modo_cadastro
                    else public._agenda_gestor_modo('marcar') end as modo_agora
          from public.agenda_perguntas x
         where x.estado = 'aberta' and x.modo = m and not x.critica and x.tipo in ('equipe_cadastro', 'dias_semana')
           and x.mostrada_vezes < cf.perguntas_vezes_max
           and not exists (select 1 from public.agenda_dono_avisos v
                            where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
         order by case when x.chave like 'equipe_cadastro:chamada:%' then 1 when x.tipo = 'dias_semana' then 2
                       when x.chave like 'equipe_cadastro:telefone:%' then 3 else 4 end, x.criada_em, x.id
      loop
        -- (7c P5) as perguntas da equipe da 7b só com o portão da 7b (o bloco pode estar rodando só pela 7c)
        continue when not v_7c_7b;
        -- (7c: fim)
        -- (7c correção, achado 14) neste dia as da 7b esperam o dia delas (acima)
        continue when v_c14_pula;
        -- (7c: fim)
        v_7b_curto := case
          when v_7b_q.chave like 'equipe_cadastro:chamada:%' then 'a equipe da agenda está certa?'
          when v_7b_q.tipo = 'dias_semana' then format('os dias da semana de %s', to_char(v_7b_q.dia, 'DD/MM'))
          when v_7b_q.chave like 'equipe_cadastro:telefone:%' then format('o telefone do %s', v_7b_q.nome)
          else format('%s na rotina da equipe?', v_7b_q.nome) end;
        if v_7b_txt is null then
          v_7b_txt := 'Agenda: ' || v_7b_q.texto;
        else
          if v_7b_rest > 0 then
            v_7b_rest := v_7b_rest + 1;
            continue;
          end if;
          v_7b_item := case
            when v_7b_q.chave like 'equipe_cadastro:telefone:%'
              then format('Também: o telefone do %s (sem ele não mando a ficha).', v_7b_q.nome)
            when v_7b_q.chave like 'equipe_cadastro:contato:%'
              then format('Também: %s tem telefone; ponho na rotina? Responda 1 ou 2 em *agenda pendências*.', v_7b_q.nome)
            when v_7b_q.tipo = 'dias_semana'
              then format('Também: os dias da semana de %s (responda em *agenda pendências*).', to_char(v_7b_q.dia, 'DD/MM'))
            else 'Também: a chamada da equipe (responda em *agenda pendências*).' end;
          if char_length(array_to_string(array[v_7b_txt] || v_7b_itens || v_7b_item, ' ')) > c_max_perg - 32 then
            v_7b_rest := 1;
            continue;
          end if;
          v_7b_itens := v_7b_itens || v_7b_item;
        end if;
        v_7b_ids := v_7b_ids || to_jsonb(v_7b_q.id);
        -- (correção da revisão da 7b, achado 17) a chamada e a pergunta dos dias que vão só como "Também: … (responda em *agenda
        -- pendências*)" não contam como mostradas: o dono não leu a pergunta (a dos dias, com a sugestão de quem chamar, contava como vista
        -- e vencia na quinta seguinte sem ele a ter lido). Elas ficam com mostrada_vezes 0 (a linha segue com perda 75) e saem inteiras no
        -- fechamento em que vierem primeiro. O telefone e o contato vão com a pergunta toda na forma curta e contam.
        if jsonb_array_length(v_7b_ids) > 1 and (v_7b_q.tipo = 'dias_semana' or v_7b_q.chave like 'equipe_cadastro:chamada:%') then
          v_7b_ids := v_7b_ids - (jsonb_array_length(v_7b_ids) - 1);
        end if;
        -- (correção da revisão da 7b: fim)
        -- (correção 3) a forma curta (texto_curto, a que o Secretário cheio usa) leva o prazo de cada pergunta que vence e o
        -- "sigo assim": o registro não sabe qual das formas saiu e conta como vistas todas as pergunta_ids (agenda_fechamento_registrar),
        -- então a chamada vista só como "a equipe da agenda está certa?" ganhava o prazo de equipe_chamada_prazo_du dias úteis sem o dono
        -- ter lido o "sigo assim". A data é a que o vencimento grava: a chamada contada aqui (a 1ª da linha; a do "Também" não conta, achado
        -- 17), com o cadastro fora de desligado, vence em _agenda_veto_ate(o dia do registro, equipe_chamada_prazo_du) (a rodada da semana
        -- grava o veto_ate no tique seguinte; já gravado, o dele); a dos dias da semana, com modo_dias fora de desligado, vence no prazo da
        -- semana dela (o dia do plano em perda_em, hora_do_plano − equipe_dias_fechar_antes: o passo fechar de agenda_equipe_semana), vista
        -- ou não. O telefone e o contato não vencem: como antes. A forma longa não muda.
        v_c3_ate := case
          when v_7b_q.chave like 'equipe_cadastro:chamada:%' and cf.modo_cadastro <> 'desligado' and v_7b_ids ? v_7b_q.id::text
            then coalesce(v_7b_q.veto_ate,
                          public._agenda_veto_ate(p_hoje::timestamp at time zone 'America/Sao_Paulo', cf.equipe_chamada_prazo_du))
          when v_7b_q.tipo = 'dias_semana' and cf.modo_dias <> 'desligado' and v_7b_q.perda_em is not null
            then ((v_7b_q.perda_em + cf.hora_do_plano) - cf.equipe_dias_fechar_antes) at time zone 'America/Sao_Paulo' end;
        if v_c3_ate is not null then
          v_7b_curto := v_7b_curto || format(' — sem resposta até %s às %s, sigo assim',
                                             public._dia_curto((v_c3_ate at time zone 'America/Sao_Paulo')::date),
                                             to_char(v_c3_ate at time zone 'America/Sao_Paulo', 'HH24:MI'));
        end if;
        -- (correção 3: fim)
        v_7b_curtos := v_7b_curtos || v_7b_curto;
        -- (correção da revisão da 7b, achado 7) a chamada da 7a (sem opções) é do gestor que marca, também com o cadastro da 7b
        -- em teste: a de antes, já aberta e ligada, não vira teste (o dono deixava de vê-la)
        if v_7b_q.chave like 'equipe_cadastro:chamada:%' and cf.modo_cadastro <> 'ligado'
           and not exists (select 1 from public.agenda_perguntas p where p.id = v_7b_q.id and jsonb_array_length(p.opcoes) > 0) then
          v_7b_q.modo_agora := public._agenda_gestor_modo('marcar');
        end if;
        -- (correção da revisão da 7b: fim)
        v_7b_lig := v_7b_lig and v_7b_q.modo_agora = 'ligado';
        v_7b_perde := v_7b_perde or v_7b_q.mostrada_vezes = 0
                      or (v_7b_q.veto_ate is not null and (v_7b_q.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                      or v_7b_q.perda_em is not distinct from p_hoje;
      end loop;
      -- (7c P5, R5.4 item 4, R5.1-6, R5.10-7) as perguntas de quem faz o quê (habilidade), depois das da 7b: primeiro a da equipe
      -- (habilidade:equipe:…), depois as de OS (habilidade:os:…), e a mais antiga; só com o portão da 7c. A 1ª da linha vai inteira; as
      -- outras curtas, até c_max_perg ("Também: quem faz o quê (marquei: Alex instala sozinho; responda em *agenda pendências*)."; a de
      -- OS: "Também: Caio (OS-97173): falta quem comissiona Victron em todos os dias; quem pode? (responda em *agenda pendências*).").
      -- A da equipe que vai só como "Também" não conta como mostrada (sai de pergunta_ids: o achado 17 da 7b estendido) e sai inteira no
      -- fechamento em que vier primeiro; a de OS conta (vai com a pergunta toda, como o telefone e o contato). Na forma curta
      -- (texto_curto, a que o Secretário cheio usa — o registro não sabe qual forma saiu), a da equipe leva o que foi marcado e, quando é
      -- contada e vence (modo ligado), o prazo: "quem faz o quê — marquei: Alex instala sozinho; sem resposta até qua 04/11 às 18:00,
      -- fica assim" (a data que _agenda_habilidade_vetos grava depois do registro: o veto_ate, ou _agenda_veto_ate do dia de hoje). O
      -- modo de cada uma é o de _agenda_modo_da_pergunta (a da equipe: modo_habilidade_propor; a de OS: modo_habilidade), que a linha não
      -- pode chamar (é só do service_role; a linha é lida pelo painel). A perda é a da (n): 75 enquanto alguma nunca foi vista inteira ou
      -- perde hoje.
      if v_7c_on then
        for v_7c_q in
          select x.id, x.tipo, x.chave, x.texto, x.modo, x.mostrada_vezes, x.veto_ate, x.perda_em,
                 coalesce(public._agenda_rotulo_da_os(x.service_order_id), '') as nome,
                 case when x.chave like 'habilidade:os:%' then cf.modo_habilidade else cf.modo_habilidade_propor end as modo_agora
            from public.agenda_perguntas x
           where x.estado = 'aberta' and x.modo = m and not x.critica and x.tipo = 'habilidade'
             and x.mostrada_vezes < cf.perguntas_vezes_max
             and not exists (select 1 from public.agenda_dono_avisos v
                              where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
           order by case when x.chave like 'habilidade:equipe:%' then 1 else 2 end, x.criada_em, x.id
        loop
          v_7c_eq := v_7c_q.chave like 'habilidade:equipe:%';
          -- o que foi marcado (as propostas vivas da pergunta, lidas sob a RLS de agenda_etiquetas) e o que a OS pede
          v_7c_marc := case when v_7c_eq then nullif(public._agenda_lista(array(
                         select public._agenda_nome_curto(py.name) || ' ' || split_part(public._agenda_etiqueta_texto(e.etiqueta, e.nivel), ':', 1)
                           from public.agenda_etiquetas e join public.payees py on py.id = e.payee_id
                          where e.pergunta_id = v_7c_q.id and e.estado = 'proposta'
                          order by case e.etiqueta when 'instala' then 0 when 'ajudante' then 1 else 2 end, e.nivel desc,
                                   public._agenda_nome_curto(py.name), e.id), null), '') end;
          v_7c_exig := case when not v_7c_eq then substring(v_7c_q.texto from ': o serviço pede (.*), e nas próximas ') end;
          v_7b_curto := case when v_7c_eq then 'quem faz o quê' || coalesce(' — marquei: ' || v_7c_marc, '')
                             else format('%s: falta %s', v_7c_q.nome, coalesce(v_7c_exig, 'quem o serviço pede')) end;
          if v_7b_txt is null then
            v_7b_txt := 'Agenda: ' || v_7c_q.texto;
          else
            if v_7b_rest > 0 then
              v_7b_rest := v_7b_rest + 1;
              continue;
            end if;
            v_7b_item := case
              when v_7c_eq then format('Também: quem faz o quê (%sresponda em *agenda pendências*).',
                                       coalesce('marquei: ' || v_7c_marc || '; ', ''))
              else format('Também: %s: falta %s; quem pode? (responda em *agenda pendências*).', v_7c_q.nome,
                          coalesce(v_7c_exig, 'quem o serviço pede')) end;
            -- (7c correção 2, achado 11) a de quem faz o quê da equipe, ligada (a pergunta e o modo dela), que vai como "Também" atrás de
            -- uma pergunta da 7b que perde hoje leva o que foi marcado E o prazo — o mesmo que a forma curta dela, que já contava como
            -- vista — e conta (abaixo). Antes, só como "Também: quem faz o quê (marquei: …; responda em *agenda pendências*)." ela nunca
            -- contava: na semana real a chamada (no dia do prazo) e depois o telefone do Alex iam primeiro, e o prazo nunca começava. Em
            -- teste, a de antes.
            v_c11_tambem := v_7c_eq and m = 'ligado' and v_7c_q.modo = 'ligado' and v_7c_q.modo_agora = 'ligado';
            if v_c11_tambem then
              v_7c_ate := coalesce(v_7c_q.veto_ate, public._agenda_veto_ate(p_hoje::timestamp at time zone 'America/Sao_Paulo'));
              v_7b_item := format('Também: quem faz o quê (%ssem resposta até %s às %s, fica assim; responda em *agenda pendências*).',
                                  coalesce('marquei: ' || v_7c_marc || '; ', ''),
                                  public._dia_curto((v_7c_ate at time zone 'America/Sao_Paulo')::date),
                                  to_char(v_7c_ate at time zone 'America/Sao_Paulo', 'HH24:MI'));
            end if;
            -- (7c: fim)
            if char_length(array_to_string(array[v_7b_txt] || v_7b_itens || v_7b_item, ' ')) > c_max_perg - 32 then
              v_7b_rest := 1;
              continue;
            end if;
            v_7b_itens := v_7b_itens || v_7b_item;
          end if;
          v_7b_ids := v_7b_ids || to_jsonb(v_7c_q.id);
          if jsonb_array_length(v_7b_ids) > 1 and v_7c_eq then
            v_7b_ids := v_7b_ids - (jsonb_array_length(v_7b_ids) - 1);
          end if;
          -- (7c correção 2, achado 11) e a "Também" com o prazo conta: volta a pergunta_ids (o achado 17 da 7b a tirava)
          if v_c11_tambem and not v_7b_ids ? v_7c_q.id::text then
            v_7b_ids := v_7b_ids || to_jsonb(v_7c_q.id);
          end if;
          v_c11_tambem := false;
          -- (7c: fim)
          if v_7c_eq and v_7c_q.modo = 'ligado' and v_7b_ids ? v_7c_q.id::text then
            v_7c_ate := coalesce(v_7c_q.veto_ate, public._agenda_veto_ate(p_hoje::timestamp at time zone 'America/Sao_Paulo'));
            v_7b_curto := v_7b_curto || format('; sem resposta até %s às %s, fica assim',
                                               public._dia_curto((v_7c_ate at time zone 'America/Sao_Paulo')::date),
                                               to_char(v_7c_ate at time zone 'America/Sao_Paulo', 'HH24:MI'));
          end if;
          v_7b_curtos := v_7b_curtos || v_7b_curto;
          v_7b_lig := v_7b_lig and v_7c_q.modo_agora = 'ligado';
          v_7b_perde := v_7b_perde or v_7c_q.mostrada_vezes = 0
                        or (v_7c_q.veto_ate is not null and (v_7c_q.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                        or v_7c_q.perda_em is not distinct from p_hoje;
        end loop;
      end if;
      -- (7c: fim)
      -- (7c P8, R5.4 item 4, R5.2-2(c)) as perguntas das etapas (tarefa), depois das de quem faz o quê: primeiro a de quem faça a etapa de
      -- risco (tarefa:quem:<os>), depois a de prazo (tarefa:prazo:<os>), e a mais antiga; só com o portão das etapas. A 1ª da linha vai
      -- inteira; as outras curtas, até c_max_perg ("Também: Lenine: quem vai junto em "…"? (responda em *agenda pendências*)."). As duas
      -- contam como mostradas (vão com a pergunta toda, como a de OS de quem faz o quê). O modo é o de _agenda_modo_da_pergunta
      -- (modo_tarefas), que a linha não pode chamar. A de prazo cujo prazo (perda_em) é hoje ou o próximo dia útil perde hoje.
      if v_p8_on then
        for v_p8_q in
          select x.id, x.chave, x.texto, x.mostrada_vezes, x.perda_em,
                 coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                             join public.clients cl on cl.id = so.client_id where so.id = x.service_order_id),
                          public._agenda_rotulo_da_os(x.service_order_id), '') as cli
            from public.agenda_perguntas x
           where x.estado = 'aberta' and x.modo = m and not x.critica and x.tipo = 'tarefa'
             and x.mostrada_vezes < cf.perguntas_vezes_max
             and not exists (select 1 from public.agenda_dono_avisos v
                              where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
           order by case when x.chave like 'tarefa:quem:%' then 1 else 2 end, x.criada_em, x.id
        loop
          v_p8_quem := v_p8_q.chave like 'tarefa:quem:%';
          v_7b_curto := case when v_p8_quem then format('%s: quem vai junto%s?', v_p8_q.cli,
                                                         coalesce(' em ' || substring(v_p8_q.texto from '"[^"]+"'), ''))
                             else format('%s: as etapas não cabem até %s', v_p8_q.cli, public._dia_curto(v_p8_q.perda_em)) end;
          if v_7b_txt is null then
            v_7b_txt := 'Agenda: ' || v_p8_q.texto;
          else
            if v_7b_rest > 0 then
              v_7b_rest := v_7b_rest + 1;
              continue;
            end if;
            v_7b_item := format('Também: %s (responda em *agenda pendências*).', v_7b_curto);
            if char_length(array_to_string(array[v_7b_txt] || v_7b_itens || v_7b_item, ' ')) > c_max_perg - 32 then
              v_7b_rest := 1;
              continue;
            end if;
            v_7b_itens := v_7b_itens || v_7b_item;
          end if;
          v_7b_ids := v_7b_ids || to_jsonb(v_p8_q.id);
          v_7b_curtos := v_7b_curtos || v_7b_curto;
          v_7b_lig := v_7b_lig and cf.modo_tarefas = 'ligado';
          v_7b_perde := v_7b_perde or v_p8_q.mostrada_vezes = 0
                        or (not v_p8_quem and v_p8_q.perda_em is not null and v_p8_q.perda_em <= v_am1);
        end loop;
      end if;
      -- (7c: fim)
      continue when v_7b_txt is null;
      v_7b_l := array_to_string(array[v_7b_txt] || v_7b_itens, ' ')
                || case when v_7b_rest > 0 then format(' (e mais %s em *agenda equipe*)', v_7b_rest) else '' end;
      v_7b_curto := 'Agenda, equipe: ' || array_to_string(v_7b_curtos, '; ')
                    || case when right(v_7b_curtos[cardinality(v_7b_curtos)], 1) = '?' then '' else '.' end
                    || ' *agenda pendências* mostra.';
      v_out := v_out || (jsonb_build_object('tipo', 'pergunta', 'texto', v_7b_l, 'perda', case when v_7b_perde then 75 else 30 end,
        'pergunta_id', v_7b_ids ->> 0, 'pergunta_ids', v_7b_ids, 'acao_ids', '[]'::jsonb,
        'modo', case when m = 'ligado' and v_7b_lig then 'ligado' else 'sombra' end)
        || case when char_length(v_7b_curto) < char_length(v_7b_l) then jsonb_build_object('texto_curto', v_7b_curto)
                else '{}'::jsonb end);
    end loop;
  end if;
  -- FASE 7b: fim
  -- FASE 7c: (7c P5, R5.10-8) o portão da 7b volta a ser só o dela: a (e) exclui as perguntas da 7b só com ele (e as de quem faz o quê
  -- só com o da 7c, abaixo)
  v_7b_on := v_7c_7b;
  -- FASE 7c: fim
  -- (e) uma pergunta de fato, a que perde primeiro (cada pergunta aparece em até perguntas_vezes_max fechamentos)
  -- FASE 3: entram também concluir, entrega, equipe_resposta e diaria_ligar (não críticas)
  for m in select unnest(array['ligado', 'sombra']) loop
    select count(*) into v_n from public.agenda_perguntas x
     where not x.critica and x.estado = 'aberta' and x.modo = m and x.tipo <> 'conferencia'
       -- FASE 7: (7a P7) nem a pergunta do gestor (situacao/estimativa) em que o dono já escolheu "eu digo os dias": o prazo
       -- dela não vale mais, e o texto o prometia (notas do P4, desvio 4)
       and not (x.tipo in ('situacao', 'estimativa') and x.opcao_escolhida is not null)
       -- FASE 7: fim
       -- FASE 7: (7a P11) nem a ficha_estimativa: ela tem a linha própria (l), acima
       and x.tipo <> 'ficha_estimativa'
       -- FASE 7: fim
       -- FASE 7: (7a correção, achado 15) nem as perguntas do gestor que esperam o dono: elas vão na linha (m), acima
       and x.tipo not in ('situacao', 'estimativa', 'reestimar')
       -- FASE 7: fim
       -- FASE 7b: (7b P3, R4.2(d)) nem as perguntas da equipe: elas vão na linha (n), acima
       and not (v_7b_on and x.tipo in ('equipe_cadastro', 'dias_semana'))
       -- FASE 7b: fim
       -- FASE 7c: (7c P5, R5.4 item 4) nem as perguntas de quem faz o quê com a 7c fora de desligado: elas vão na linha (n), acima
       and not (v_7c_on and x.tipo = 'habilidade')
       -- FASE 7c: fim
       -- FASE 7c: (7c P8, R5.4 item 4) nem as perguntas das etapas com o modo_tarefas fora de desligado: elas vão na linha (n), acima
       and not (v_p8_on and x.tipo = 'tarefa')
       -- FASE 7c: fim
       -- CORREÇÃO 29/10 (revisão): nem a pergunta que um aviso do gestor de hoje já levou ou está levando (na fila).
       and not exists (select 1 from public.agenda_dono_avisos v
                        where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
       -- CORREÇÃO 29/10 (revisão): fim
       and x.mostrada_vezes < cf.perguntas_vezes_max;
    continue when v_n = 0;
    select x.* into q from public.agenda_perguntas x
     where not x.critica and x.estado = 'aberta' and x.modo = m and x.tipo <> 'conferencia'
       -- FASE 7: (7a P7) nem a pergunta do gestor (situacao/estimativa) em que o dono já escolheu "eu digo os dias": o prazo
       -- dela não vale mais, e o texto o prometia (notas do P4, desvio 4)
       and not (x.tipo in ('situacao', 'estimativa') and x.opcao_escolhida is not null)
       -- FASE 7: fim
       -- FASE 7: (7a P11) nem a ficha_estimativa: ela tem a linha própria (l), acima
       and x.tipo <> 'ficha_estimativa'
       -- FASE 7: fim
       -- FASE 7: (7a correção, achado 15) nem as perguntas do gestor que esperam o dono: elas vão na linha (m), acima
       and x.tipo not in ('situacao', 'estimativa', 'reestimar')
       -- FASE 7: fim
       -- FASE 7b: (7b P3, R4.2(d)) nem as perguntas da equipe: elas vão na linha (n), acima
       and not (v_7b_on and x.tipo in ('equipe_cadastro', 'dias_semana'))
       -- FASE 7b: fim
       -- FASE 7c: (7c P5, R5.4 item 4) nem as perguntas de quem faz o quê com a 7c fora de desligado: elas vão na linha (n), acima
       and not (v_7c_on and x.tipo = 'habilidade')
       -- FASE 7c: fim
       -- FASE 7c: (7c P8, R5.4 item 4) nem as perguntas das etapas com o modo_tarefas fora de desligado: elas vão na linha (n), acima
       and not (v_p8_on and x.tipo = 'tarefa')
       -- FASE 7c: fim
       -- CORREÇÃO 29/10 (revisão): nem a pergunta que um aviso do gestor de hoje já levou ou está levando (na fila).
       and not exists (select 1 from public.agenda_dono_avisos v
                        where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
       -- CORREÇÃO 29/10 (revisão): fim
       and x.mostrada_vezes < cf.perguntas_vezes_max
     order by x.perda_em nulls last, x.criada_em, x.id limit 1;
    v_out := v_out || jsonb_build_object('tipo', 'pergunta',
      'texto', 'Agenda: ' || q.texto || case when v_n > 1 then format(' (e mais %s em *agenda pendências*)', v_n - 1) else '' end,
      'perda', 30, 'pergunta_id', q.id, 'acao_ids', '[]'::jsonb,
      'modo', case when m = 'ligado' and cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
    -- FASE 7d: (7d P5, R6.7c-3) a combinar que perde em até 2 dias úteis sobe a 75: sem isso ela cai atrás de tudo no corte por perda do Secretário
    -- (vagas = maxManha − as que ficaram + as garantidas), e reserva_marina, descida e entrada não têm rede em D-1. Uma linha só, e os 75 dão a vaga
    -- garantida (agenda_textos_do_fechamento). A local fica em 30: nada espera por ela.
    if q.tipo = 'combinar' and q.perda_em <= v_am2 then
      v_out := jsonb_set(v_out, array[(jsonb_array_length(v_out) - 1)::text, 'perda'], to_jsonb(75));
    end if;
    -- FASE 7d: fim
  end loop;

  -- FASE 7c: (7c P8, R5.2-2(b), R5.10-6, -10, -13) (o) as etapas de quem não recebe pelo WhatsApp (sem telefone pela régua da 7a,
  -- _agenda_equipe_tem_telefone — a mesma do registro —, ou fora da lista da rotina) com etapa no plano de hoje ou do próximo dia útil: o
  -- que hoje devia ficar pronto (o dono passa e confere) e o que fazer amanhã, sem números (as listas do dia e a da OS numeram
  -- diferente), até c_max, cortando por etapa inteira ("e mais N"); o texto_curto para o Secretário cheio. Perda 75 só quando amanhã é
  -- o último dia de uma OS (a cobrança da véspera) ou volta primeiro uma pendente dita; senão 70 (a etapa de risco sozinha não sobe a
  -- perda). Tipo dia, sem pergunta: nada vence por ela. Em teste, modo sombra e "Em teste: " (vai ao detalhe, nunca ao texto do dono).
  -- Só com a porta das etapas aberta (o administrador ou o financeiro logado, ou sem login).
  if cf.modo_tarefas <> 'desligado' and (auth.uid() is null or public.is_admin_or_financial(auth.uid())) then
    for v_p8_pess in
      select x.payee_id, x.nome, public._agenda_equipe_tem_telefone(x.payee_id) as fone,
             exists (select 1 from public.agenda_equipe_contato c
                      where c.payee_id = x.payee_id and c.recebe_rotina and c.parou_em is null) as rotina
        from (select distinct a.payee_id, public._agenda_nome_curto(py.name) as nome
                from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
               where a.dia in (p_hoje, v_am1) and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno'
                 and a.payee_id is distinct from public._agenda_dono(null)) x
       order by x.nome, x.payee_id
    loop
      continue when v_p8_pess.fone and v_p8_pess.rotina;
      v_p8_h := public._agenda_tarefas_da_pessoa(v_p8_pess.payee_id, p_hoje, p_hoje);
      v_p8_a := public._agenda_tarefas_da_pessoa(v_p8_pess.payee_id, v_am1, p_hoje);
      -- hoje: o que terminava e ainda não tem resultado (uma vez por etapa)
      v_p8_hi := coalesce((select jsonb_agg(i order by (i ->> 'n')::int) from jsonb_array_elements(v_p8_h -> 'itens') i
                            where (i ->> 'termina')::boolean and i -> 'resultado' = 'null'::jsonb
                              and not exists (select 1 from jsonb_array_elements(v_p8_hoje) j where j ->> 'tarefa' = i ->> 'tarefa')),
                           '[]'::jsonb);
      -- amanhã: o que a pessoa faz, por OS, com o último dia e a pendente dita que volta primeiro
      v_p8_ai := coalesce((select jsonb_agg(i || jsonb_build_object('nome', v_p8_pess.nome, 'payee', v_p8_pess.payee_id,
                                  'com', case when (i ->> 'com_dono')::boolean then 'você' end,
                                  'ultimo', (v_p8_a -> 'ultimo_dia') @> jsonb_build_array(jsonb_build_object('os', i ->> 'os')),
                                  'pdita', exists (select 1 from public.os_tarefas t where t.id = (i ->> 'tarefa')::uuid
                                                      and t.estado = 'viva' and t.pendente_vezes > 0))
                                order by (i ->> 'n')::int)
                           from jsonb_array_elements(v_p8_a -> 'itens') i), '[]'::jsonb);
      -- só quem tem o que conferir hoje ou o que fazer amanhã entra no "Etapas (… não tem telefone …)"
      continue when jsonb_array_length(v_p8_hi) = 0 and jsonb_array_length(v_p8_ai) = 0;
      v_p8_nomes := v_p8_nomes || v_p8_pess.nome;
      v_p8_nfone := coalesce(v_p8_nfone, 0) + case when v_p8_pess.fone then 0 else 1 end;
      v_p8_nrot := coalesce(v_p8_nrot, 0) + case when v_p8_pess.rotina then 0 else 1 end;
      v_p8_hoje := v_p8_hoje || v_p8_hi;
      v_p8_amanha := v_p8_amanha || v_p8_ai;
    end loop;
    -- (7c correção 2, achado 13) o dia útil de amanhã é dia de revisão (o 1º dia útil da semana ou do mês: a tarde do Secretário é a
    -- revisão, sem as linhas da agenda) — a véspera do último dia que cai no dia útil seguinte a ele nunca chegava ao dono (a OS que
    -- termina na terça; o dia útil depois de um feriado na segunda). A linha de hoje já cobra esse último dia, de quem trabalha amanhã;
    -- até 2 dias de revisão seguidos (a do mês e a da semana).
    v_c13_d := v_am1;
    for v_c13_k in 1 .. 2 loop
      -- (7d P5, R6.12) o remendo do achado 13 sai: com 62d1fd95 as linhas saem nos dias de revisão, e a (o) já cobra a véspera do último dia no próprio dia.
      -- Com o exit, v_c13_av fica [] e tudo o que dependia dele vira o caminho sem remendo. A parte do achado 15 fica (usa v_am1). A remoção física é da 7f.
      exit;
      -- (7d: fim)
        select exists (
          with s as (
            select w.x, (select min(make_date(extract(year from w.x)::int, extract(month from w.x)::int, 1) + c13n)
                           from generate_series(0, 9) c13n
                          where extract(isodow from make_date(extract(year from w.x)::int, extract(month from w.x)::int, 1) + c13n) between 1 and 5
                            and public.agenda_feriado(make_date(extract(year from w.x)::int, extract(month from w.x)::int, 1) + c13n) is null) as rm
              from (select v_c13_d - (extract(isodow from v_c13_d)::int - 1) + c13n as x from generate_series(0, 4) c13n) w
          )
          select 1 where extract(isodow from v_c13_d) between 1 and 5 and public.agenda_feriado(v_c13_d) is null
            and (v_c13_d = (select s.rm from s where s.x = v_c13_d)
                 or v_c13_d = (select min(s.x) from s where extract(isodow from s.x) between 1 and 5 and public.agenda_feriado(s.x) is null
                                                  and s.x <> s.rm))) into v_c13_rev;
      exit when not v_c13_rev;
      v_c13_prox := public.agenda_somar_du(v_c13_d, 1);
      for v_c13_p in select distinct i ->> 'payee' as payee, i ->> 'nome' as nome from jsonb_array_elements(v_p8_amanha) i order by 2, 1 loop
        v_c13_u := public._agenda_tarefas_da_pessoa((v_c13_p.payee)::uuid, v_c13_prox, p_hoje) -> 'ultimo_dia';
        v_c13_av := v_c13_av || coalesce((select jsonb_agg(jsonb_build_object('dia', v_c13_prox, 'rev', v_c13_d, 'nome', v_c13_p.nome,
                                                                              'cliente', u ->> 'cliente', 'os', u ->> 'os') order by o)
                                            from jsonb_array_elements(coalesce(v_c13_u, '[]'::jsonb)) with ordinality t(u, o)), '[]'::jsonb);
      end loop;
      v_c13_d := v_c13_prox;
    end loop;
    -- (7c: fim)
    if jsonb_array_length(v_p8_hoje) > 0 or jsonb_array_length(v_p8_amanha) > 0 then
      v_p8_dia := case when v_am1 = p_hoje + 1 then 'Amanhã (' || public._dia_curto(v_am1) || ')'
                       else public._agenda_maiuscula(public._dia_curto(v_am1)) end;
      -- monta com até v_p8_k etapas por lista; corta por etapa inteira até caber em c_max
      v_p8_k := 5;
      loop
        v_p8_txt := format('Etapas (%s %s: quem passa e confere é você).', public._agenda_lista(v_p8_nomes, null),
                           case when v_p8_nfone = cardinality(v_p8_nomes)
                                  then case when cardinality(v_p8_nomes) = 1 then 'não tem telefone' else 'não têm telefone' end
                                when v_p8_nrot = cardinality(v_p8_nomes)
                                  then case when cardinality(v_p8_nomes) = 1 then 'não está na rotina da equipe' else 'não estão na rotina da equipe' end
                                else 'não recebem pelo WhatsApp' end);
        for v_p8_g in select i ->> 'cliente' as cli, min((i ->> 'n')::int) as o,
                             jsonb_agg(i order by (i ->> 'n')::int) as its
                        from jsonb_array_elements(v_p8_hoje) i group by i ->> 'cliente' order by 2 loop
          v_p8_txt := v_p8_txt || format(' Hoje no %s devia ficar pronto: %s.', v_p8_g.cli,
                                         public._agenda_tarefas_lista_texto(v_p8_g.its, v_p8_k, null, false, false));
        end loop;
        if jsonb_array_length(v_p8_hoje) > 0 then
          v_p8_txt := v_p8_txt || format(' Se faltou alguma, me diga qual (ex.: no %s falta "%s").', v_p8_hoje -> 0 ->> 'cliente',
                                         lower(left(v_p8_hoje -> 0 ->> 'texto', 1)) || substr(v_p8_hoje -> 0 ->> 'texto', 2));
        end if;
        for v_p8_g in select i ->> 'nome' as nome, i ->> 'cliente' as cli, min((i ->> 'n')::int) as o,
                             bool_or((i ->> 'ultimo')::boolean) as ult, jsonb_agg(i order by (i ->> 'n')::int) as its
                        from jsonb_array_elements(v_p8_amanha) i group by i ->> 'nome', i ->> 'payee', i ->> 'cliente'
                       order by i ->> 'nome', 3 loop
          v_p8_txt := v_p8_txt || format(' %s, %s no %s: %s.', v_p8_dia, v_p8_g.nome, v_p8_g.cli,
                                         public._agenda_tarefas_lista_texto(v_p8_g.its, v_p8_k, null, true, false))
                      || case when v_p8_g.ult then ' É o último dia: tem que ficar tudo pronto.' else '' end;
        end loop;
        -- (7c correção 2, achado 13) a cobrança do último dia depois do dia de revisão, sempre inteira: com o porquê, quando cabe; sem
        -- ele, quando não ("Qui 05/11 é o último dia do Lenine (Alex): tem que ficar tudo pronto."); o que não cabe sai das listas (o k)
        for v_c13_p in select a ->> 'dia' as dia, a ->> 'rev' as rev, a ->> 'nome' as nome, a ->> 'cliente' as cli
                         from jsonb_array_elements(v_c13_av) with ordinality t(a, o) order by o loop
          v_c13_q := format(' %s é o último dia do %s (%s): tem que ficar tudo pronto — aviso hoje porque %s é dia de revisão.',
                            public._agenda_maiuscula(public._dia_curto(v_c13_p.dia::date)), v_c13_p.cli, v_c13_p.nome,
                            public._dia_curto(v_c13_p.rev::date));
          if char_length(v_p8_txt || v_c13_q) + (case when cf.modo_tarefas = 'ligado' then 0 else 10 end) > c_max then
            v_c13_q := format(' %s é o último dia do %s (%s): tem que ficar tudo pronto.',
                              public._agenda_maiuscula(public._dia_curto(v_c13_p.dia::date)), v_c13_p.cli, v_c13_p.nome);
          end if;
          v_p8_txt := v_p8_txt || v_c13_q;
        end loop;
        -- (7c: fim)
        v_p8_txt := case when cf.modo_tarefas = 'ligado' then '' else 'Em teste: ' end || v_p8_txt;
        exit when char_length(v_p8_txt) <= c_max or v_p8_k = 1;
        v_p8_k := v_p8_k - 1;
      end loop;
      v_p8_txt := public._agenda_corta(v_p8_txt, c_max);
      -- a forma curta (o Secretário cheio)
      v_p8_parte := array(select case when bool_or((i ->> 'ultimo')::boolean)
                                      then format('amanhã é o último dia do %s (%s, %s)', i ->> 'cliente', i ->> 'nome',
                                                  public._agenda_plural(count(*)::int, 'etapa', 'etapas'))
                                      else format('amanhã, %s no %s (%s)', i ->> 'nome', i ->> 'cliente',
                                                  public._agenda_plural(count(*)::int, 'etapa', 'etapas')) end
                            from jsonb_array_elements(v_p8_amanha) i group by i ->> 'nome', i ->> 'payee', i ->> 'cliente'
                           order by i ->> 'nome', min((i ->> 'n')::int))
                  || case when jsonb_array_length(v_p8_hoje) > 0
                          then array[format('hoje, %s para conferir', jsonb_array_length(v_p8_hoje))] else '{}'::text[] end;
      v_p8_curto := case when cf.modo_tarefas = 'ligado' then '' else 'Em teste: ' end
                    || 'Etapas: ' || array_to_string(v_p8_parte, '; ') || '.'
                    || case when jsonb_array_length(v_p8_amanha) > 0
                            then format(' Pergunte o que o %s faz amanhã.', v_p8_amanha -> 0 ->> 'nome') else '' end;
      v_p8_alta := exists (select 1 from jsonb_array_elements(v_p8_amanha) i where (i ->> 'ultimo')::boolean or (i ->> 'pdita')::boolean);
      -- (7c correção 2, achados 15 e 13) a forma curta com o dia quando o próximo dia útil não é amanhã (a sexta, a véspera de feriado:
      -- "seg 09/11 é o último dia do Lenine (Alex, 2 etapas). Pergunte o que o Alex faz na seg 09/11." — antes, "amanhã", e o "o que o
      -- Alex faz amanhã?" respondia pelo sábado) e com o último dia depois do dia de revisão; o último dia (o de amanhã ou o depois da
      -- revisão) marca a linha para subir com as outras de 75 (no fim). Sem nada disso, a de antes.
      if v_am1 <> p_hoje + 1 or jsonb_array_length(v_c13_av) > 0 then
        v_c13_q := case when v_am1 = p_hoje + 1 then 'amanhã' else public._dia_curto(v_am1) end;
        v_c13_parte := array(select case when bool_or((i ->> 'ultimo')::boolean)
                                         then format('%s é o último dia do %s (%s, %s)', v_c13_q, i ->> 'cliente', i ->> 'nome',
                                                     public._agenda_plural(count(*)::int, 'etapa', 'etapas'))
                                         else format('%s, %s no %s (%s)', v_c13_q, i ->> 'nome', i ->> 'cliente',
                                                     public._agenda_plural(count(*)::int, 'etapa', 'etapas')) end
                               from jsonb_array_elements(v_p8_amanha) i group by i ->> 'nome', i ->> 'payee', i ->> 'cliente'
                              order by i ->> 'nome', min((i ->> 'n')::int))
                       || array(select format('%s é o último dia do %s (%s)', public._dia_curto((a ->> 'dia')::date), a ->> 'cliente',
                                              a ->> 'nome')
                                  from jsonb_array_elements(v_c13_av) with ordinality t(a, o) order by o)
                       || case when jsonb_array_length(v_p8_hoje) > 0
                               then array[format('hoje, %s para conferir', jsonb_array_length(v_p8_hoje))] else '{}'::text[] end;
        v_p8_curto := case when cf.modo_tarefas = 'ligado' then '' else 'Em teste: ' end
                      || 'Etapas: ' || array_to_string(v_c13_parte, '; ') || '.'
                      || case when jsonb_array_length(v_p8_amanha) > 0
                              then format(' Pergunte o que o %s faz %s.', v_p8_amanha -> 0 ->> 'nome',
                                          case when v_am1 = p_hoje + 1 then 'amanhã' else 'na ' || public._dia_curto(v_am1) end)
                              else '' end;
      end if;
      v_p8_alta := v_p8_alta or jsonb_array_length(v_c13_av) > 0;
      v_c13_ult := cf.modo_tarefas = 'ligado'
                   and (jsonb_array_length(v_c13_av) > 0
                        or exists (select 1 from jsonb_array_elements(v_p8_amanha) i where (i ->> 'ultimo')::boolean));
      -- (7c: fim)
      v_out := v_out || (jsonb_build_object('tipo', 'dia', 'texto', v_p8_txt, 'perda', case when v_p8_alta then 75 else 70 end,
        'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', case when cf.modo_tarefas = 'ligado' then 'ligado' else 'sombra' end)
        || case when char_length(v_p8_curto) < char_length(v_p8_txt) then jsonb_build_object('texto_curto', v_p8_curto)
                else '{}'::jsonb end);
    end if;
  end if;
  -- FASE 7c: fim
  -- FASE 3 (f): o PPC no último dia útil da semana (sexta; com feriado, o dia útil antes), se a semana teve compromisso
  v_ppc := public.agenda_ppc(p_hoje, p_hoje);
  if (v_ppc ->> 'ultimo_dia_util')::boolean and (v_ppc ->> 'compromissos')::int > 0 and v_ppc ->> 'linha' is not null then
    v_out := v_out || jsonb_build_object('tipo', 'ppc', 'texto', public._agenda_corta(v_ppc ->> 'linha', c_max), 'perda', 55,
      'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
  end if;

  -- FASE 3 (g): a comissão do mês que fechou, no 1º dia útil do mês (só a conta: nada é pago). Quem não pode ver a
  -- comissão (42501) não ganha a linha.
  if p_hoje = public.agenda_somar_du(make_date(extract(year from p_hoje)::int, extract(month from p_hoje)::int, 1), 0) then
    begin
      v_com := public.comissao_resumo_do_mes(null, p_hoje);
    exception when sqlstate '42501' then
      v_com := null;
    end;
    if coalesce((v_com ->> 'primeiro_dia_util')::boolean, false) and nullif(v_com ->> 'linha', '') is not null then
      v_out := v_out || jsonb_build_object('tipo', 'comissao', 'texto', v_com ->> 'linha', 'perda', 20,
        'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
    end if;
  end if;

  -- FASE 7: (7a P7) (i) o "eu marcaria assim" do gestor em teste (spec §6.1): com o modo marcar em sombra, o texto_sombra do
  -- diário de hoje (a rodada do gestor das 16:52 o grava), perda 65, com o modo da vigia (o dono lê de verdade o que o gestor
  -- faria). (j) As compras da semana (agenda_gestor_dia.compras de hoje, que o P10 grava, [{texto, compre_ate, urgente}]): perda
  -- 80 com alguma compra urgente (AG7-07: o serviço começa a menos de compra_urgente_du dias úteis — vai como decisão), 65 com
  -- "compre até" hoje ou amanhã, 45 até compras_aviso_du dias úteis; sem nada disso, nenhuma linha. O modo é o do compre_ate.
  if public._agenda_gestor_modo('marcar') = 'sombra' then
    select g.texto_sombra into v_f7_txt from public.agenda_gestor_dia g where g.dia = p_hoje;
    if nullif(btrim(v_f7_txt), '') is not null then
      -- (7a correção, achado 14) em teste, perda 25: abaixo de toda linha de verdade (só a comissão é menor) — a linha de teste
      -- não tira o lugar da semana publicada, da diária, da conclusão nem da pergunta que o dono precisa ver
      v_out := v_out || jsonb_build_object('tipo', 'gestor', 'texto', v_f7_txt, 'perda', 25, 'pergunta_id', null,
        'acao_ids', '[]'::jsonb, 'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
    end if;
  end if;
  select g.compras into v_f7_cmp from public.agenda_gestor_dia g where g.dia = p_hoje;
  if jsonb_array_length(coalesce(v_f7_cmp, '[]'::jsonb)) > 0 then
    select min((e ->> 'compre_ate')::date), coalesce(bool_or((e ->> 'urgente')::boolean), false)
      into v_f7_min, v_f7_urg from jsonb_array_elements(v_f7_cmp) e;
    -- (7a correção, achado 19) o "compre até" de hoje (ou vencido, que comprando hoje ainda chega) é decisão de hoje: perda 80
    v_f7_perda := case when v_f7_urg or (v_f7_min is not null and v_f7_min <= p_hoje) then 80
                       when v_f7_min is not null and v_f7_min <= v_am1 then 65
                       when v_f7_min is not null and v_f7_min <= public.agenda_somar_du(p_hoje, cf.compras_aviso_du) then 45 end;
    v_f7_txt := array_to_string(array(select btrim(e ->> 'texto') from jsonb_array_elements(v_f7_cmp) with ordinality t(e, o)
                                       where nullif(btrim(e ->> 'texto'), '') is not null order by o), ' ');
    if v_f7_perda is not null and nullif(v_f7_txt, '') is not null then
      v_out := v_out || jsonb_build_object('tipo', 'compras', 'texto', public._agenda_corta('Compras: ' || v_f7_txt, c_max),
        'perda', v_f7_perda, 'pergunta_id', null, 'acao_ids', '[]'::jsonb,
        'modo', case when public._agenda_gestor_modo('compre_ate') = 'ligado' then 'ligado' else 'sombra' end);
    end if;
  end if;
  -- FASE 7: fim
  -- FASE 5: (h) a mensagem ao cliente, só com modo_cliente ligado: a que espera *manda cliente* e sai até o próximo dia de
  -- janela (perda 75; até 600 caracteres, c_max_cliente de _agenda_cliente_fechamento) e o que sai sozinho amanhã (perda 40,
  -- com *segura cliente*). As críticas (cliente_aviso) já entram pela linha decisao; o que saiu, pela linha mudancas.
  if cf.modo_cliente = 'ligado' then
    v_out := v_out || public._agenda_cliente_fechamento(p_hoje);
  end if;
  -- FASE 5: fim
  -- FASE 7c: (7c correção, achados 8 e 2) o fechamento cheio com uma linha da 7c ligada que perde hoje (a (o) "Etapas" ou a (n) com
  -- uma pergunta de quem faz o quê ou das etapas). O Secretário (textoDaTarde) encolhe só as linhas que têm forma curta antes de tirar
  -- uma, e a do cliente (75, a mensagem que espera *manda cliente*, até 600 letras) não tinha: com ela, a (o) e a (n) caíam (a semana
  -- real da revisão, 5 fechamentos com uma linha de cliente). Sem a 7c ligada (desligada ou em teste), a de antes, byte a byte.
  if exists (select 1 from jsonb_array_elements(v_out) x
              where x ->> 'modo' = 'ligado' and (x ->> 'perda')::int >= 75
                and ((x ->> 'tipo' = 'dia' and x ->> 'texto' like 'Etapas%')
                     or exists (select 1 from jsonb_array_elements_text(coalesce(x -> 'pergunta_ids', '[]'::jsonb)) u(id)
                                  join public.agenda_perguntas qq on qq.id = u.id::uuid
                                 where qq.tipo in ('habilidade', 'tarefa')))) then
    -- (8) a mensagem ao cliente ganha a forma curta (a coleta só a usa no fechamento enxuto, com linha garantida prestes a sair): quem,
    -- o tipo, quando sai e a palavra — "Mensagem para Vera (véspera, com a pergunta do acesso) espera *manda cliente Vera* (sai ter
    -- 10/11 às 09:00); *agenda clientes* mostra." — com a mesma 1ª mensagem de _agenda_cliente_fechamento
    if cf.modo_cliente = 'ligado' then
      v_c8_agora := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
      select m2.tipo, m2.enviar_em, q2.id,
             public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)), count(*) over ()
        into v_c8_tipo, v_c8_env, v_c8_qid, v_c8_nome, v_c8_n
        from public.agenda_cliente_mensagens m2
        join public.agenda_perguntas q2 on q2.id = m2.pergunta_id
        join public.clients cl on cl.id = m2.client_id
       where m2.modo = 'ligado' and m2.estado = 'aguardando_dono' and m2.aprovacao = 'pedida'
         and q2.tipo = 'cliente_aprovar' and q2.estado = 'aberta'
         and (m2.enviar_em at time zone 'America/Sao_Paulo')::date <= public._agenda_cliente_dia_seguinte(p_hoje)
       order by m2.enviar_em, cl.name, m2.tipo, m2.id
       limit 1;
      if v_c8_qid is not null then
        v_c8_curto := case when v_c8_n > 1
          then format('Mensagem para %s (%s) e mais %s esperam *manda cliente* (a 1ª sai %s); *agenda clientes* mostra.', v_c8_nome,
                      public._agenda_cliente_tipo_texto(v_c8_tipo), v_c8_n - 1, public._agenda_cliente_quando_texto(v_c8_env, v_c8_agora))
          else format('Mensagem para %s (%s) espera *manda cliente %s* (sai %s); *agenda clientes* mostra.', v_c8_nome,
                      public._agenda_cliente_tipo_texto(v_c8_tipo), v_c8_nome, public._agenda_cliente_quando_texto(v_c8_env, v_c8_agora)) end;
        v_out := (select coalesce(jsonb_agg(case when x ->> 'tipo' = 'cliente' and (x ->> 'perda')::int = 75
                                                  and x ->> 'pergunta_id' = v_c8_qid::text and not x ? 'texto_curto'
                                                  and char_length(v_c8_curto) < char_length(x ->> 'texto')
                                             then x || jsonb_build_object('texto_curto', v_c8_curto) else x end order by o), '[]'::jsonb)
                    from jsonb_array_elements(v_out) with ordinality t(x, o));
      end if;
    end if;
    -- (2) a (n) com uma pergunta de quem faz o quê ou das etapas, ligada, contada na linha e nunca vista há c_c2_dias dias úteis (ela
    -- perdeu c_c2_dias fechamentos: com a compra (80) e as perguntas do gestor (76), as três não cabem nem na forma curta, e a de menor
    -- perda saía todo dia — o prazo nunca corria e a proposta nunca valia) sobe a c_c2_perda: neste dia sai a de menor perda das outras
    -- (a das perguntas do gestor, ou uma de 75), uma vez, e no dia seguinte, vista, ela volta à de sempre. Não sobe se a linha que ela
    -- tiraria (perda 76 a 79) perde algo hoje: a ficha de amanhã (ficha_estimativa) ou um prazo (veto ou perda) de hoje.
    if not exists (select 1 from jsonb_array_elements(v_out) x
                    where x ->> 'modo' = 'ligado' and (x ->> 'perda')::int between 76 and 79
                      and exists (select 1 from jsonb_array_elements_text(coalesce(x -> 'pergunta_ids', '[]'::jsonb)) u(id)
                                    join public.agenda_perguntas qq on qq.id = u.id::uuid
                                   where qq.tipo = 'ficha_estimativa'
                                      or (qq.veto_ate is not null and (qq.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                                      or qq.perda_em is not distinct from p_hoje)) then
      v_out := (select coalesce(jsonb_agg(case when x ->> 'modo' = 'ligado' and x ->> 'tipo' = 'pergunta' and (x ->> 'perda')::int = 75
                                                and exists (select 1 from jsonb_array_elements_text(coalesce(x -> 'pergunta_ids', '[]'::jsonb)) u(id)
                                                              join public.agenda_perguntas qq on qq.id = u.id::uuid
                                                             where qq.tipo in ('habilidade', 'tarefa') and qq.modo = 'ligado'
                                                               and qq.estado = 'aberta' and qq.mostrada_vezes = 0
                                                               and public.agenda_du_entre((qq.criada_em at time zone 'America/Sao_Paulo')::date,
                                                                                          p_hoje) >= c_c2_dias)
                                           then jsonb_set(x, '{perda}', to_jsonb(c_c2_perda)) else x end order by o), '[]'::jsonb)
                  from jsonb_array_elements(v_out) with ordinality t(x, o));
    end if;
  end if;
  -- FASE 7c: fim
  -- FASE 7c: (7c correção 2, achados 1 e 13) quando uma linha da 7c ligada espera demais — a (n) com quem faz o quê nunca vista há
  -- c_c2_dias dias úteis (a 100580 a subiu a c_c2_perda, acima) ou a (o) "Etapas" da véspera do último dia (o de amanhã ou o depois
  -- de um dia de revisão) —, sobem a c_c2_perda TODAS as linhas ligadas de 75 (as que perdem hoje: a mensagem ao cliente que espera
  -- *manda cliente*, a (o), a (n)), na ordem de sempre entre elas. Quem sai no corte de 1.000 é a pergunta do gestor (76) que não perde
  -- hoje — ela espera um dia —, nunca a mensagem ao cliente (antes, só a (n) subia: com 4 linhas de 75 ou mais, saía o cliente, a de
  -- menor perda). Não sobe se uma linha de 76 a 79 perde algo hoje (a ficha de amanhã, um veto ou um prazo de hoje: a mesma guarda
  -- da 100580). Só com a pergunta do gestor de 76 para ceder; sem ela, nada passa à frente, e a (n) que a 100580 subiu volta a 75 (ela
  -- só tiraria o lugar de outra de 75). A vaga garantida não muda (75 e 77 contam igual). Sem a 7c ligada, nada disto acontece.
  if (exists (select 1 from jsonb_array_elements(v_out) x
               where x ->> 'modo' = 'ligado' and x ->> 'tipo' = 'pergunta' and (x ->> 'perda')::int = c_c2_perda)
      or (v_c13_ult
         and exists (select 1 from jsonb_array_elements(v_out) x
                      where x ->> 'modo' = 'ligado' and x ->> 'tipo' = 'dia' and x ->> 'texto' like 'Etapas%' and (x ->> 'perda')::int = 75)
         and not exists (select 1 from jsonb_array_elements(v_out) x
                          where x ->> 'modo' = 'ligado' and (x ->> 'perda')::int between 76 and 79
                          and exists (select 1 from jsonb_array_elements_text(coalesce(x -> 'pergunta_ids', '[]'::jsonb)) u(id)
                                        join public.agenda_perguntas qq on qq.id = u.id::uuid
                                       where qq.tipo = 'ficha_estimativa'
                                          or (qq.veto_ate is not null and (qq.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                                          or qq.perda_em is not distinct from p_hoje)
                         ))) then
    if exists (select 1 from jsonb_array_elements(v_out) x where x ->> 'modo' = 'ligado' and x ->> 'tipo' = 'pergunta' and (x ->> 'perda')::int = 76) then
      v_out := (select coalesce(jsonb_agg(case when x ->> 'modo' = 'ligado' and (x ->> 'perda')::int = 75
                                               then jsonb_set(x, '{perda}', to_jsonb(c_c2_perda)) else x end order by o), '[]'::jsonb)
                  from jsonb_array_elements(v_out) with ordinality t(x, o));
    else
      -- sem a de 76, a (n) que a 100580 subiu só passaria à frente das outras de 75 (a mensagem ao cliente): volta a 75
      v_out := (select coalesce(jsonb_agg(case when x ->> 'modo' = 'ligado' and x ->> 'tipo' = 'pergunta' and (x ->> 'perda')::int = c_c2_perda
                                               then jsonb_set(x, '{perda}', to_jsonb(75)) else x end order by o), '[]'::jsonb)
                  from jsonb_array_elements(v_out) with ordinality t(x, o));
    end if;
  end if;
  -- FASE 7c: fim
  return coalesce((select jsonb_agg(x order by (x ->> 'perda')::int desc, x ->> 'tipo', x ->> 'texto')
                     from jsonb_array_elements(v_out) x), '[]'::jsonb);
end;
$function$;

comment on function public._agenda_linhas_do_fechamento(date) is
  'Agenda de Produção (Fase 2, P5; Fase 3, P6): as linhas da agenda no fechamento das 17:30 — [{tipo (decisao|diaria|dia|ppc|semana|conclusao|mudancas|pergunta|comissao), texto, perda, pergunta_id, acao_ids, modo}] da maior perda para a menor (decisão 100/80/50 pela perda_em; dia 70; semana 60; ppc 55; diaria 50 ou 80 com 2 dias úteis sem resposta; conclusao 45; mudanças 40; pergunta 30; comissao 20). FASE 3: a linha dia conta o que a equipe confirmou, a diária que a agenda lançou ("*diária Roberto meia* corrige"), quem falta confirmar ("Foi isso para o João? *dia feito* lança a meia diária dele") e o último dia da OS (*concluiu <nome>*); sem nada disso, sai byte a byte a da Fase 2. diaria = a pergunta crítica da diária com as opções e as palavras (modo_diaria); conclusao = o que o gestor concluiu pela palavra do técnico, com o *desfaz* pelo número (modo_proposta); ppc = agenda_ppc().linha no último dia útil da semana com compromisso (modo_vigia); comissao = comissao_resumo_do_mes().linha no 1º dia útil do mês (modo_vigia). modo ligado só com o registro em ligado e o modo que o governa ligado agora; o resto sombra (o que diria; vai ao detalhe). O secretário mostra as ligadas que cabem nas vagas (REGRAS.maxManha − as que ficaram) e registra o que saiu (agenda_fechamento_registrar). FASE 5 (P5): cliente (só com modo_cliente ligado; _agenda_cliente_fechamento) — perda 75 com a mensagem que espera *manda cliente* e sai até o próximo dia de janela (a 1ª inteira, até 600 caracteres; acima disso o texto da mensagem é cortado em 300 e *agenda clientes* mostra inteira), perda 40 com o que sai sozinho amanhã e *segura cliente <nome>*. CORREÇÃO 29/10 (revisão): a pergunta de fato (e) não repete a que um aviso do gestor de hoje já levou ou está levando (agenda_dono_avisos enfileirada ou enviada): a pergunta sai uma vez por dia. FASE 7 (7a P7, spec §5.7 e §6.1): (i) com o gestor que marca em teste (_agenda_gestor_modo(''marcar'') = ''sombra''), a linha gestor — o "eu marcaria assim" do diário de hoje (agenda_gestor_dia.texto_sombra, ≤ 640: "Agenda em teste (nada mudou): eu marcaria assim — …"), perda 65, modo = o da vigia; (j) a linha compras — as compras da semana do diário de hoje (agenda_gestor_dia.compras [{texto, compre_ate, urgente}], que o P10 grava): perda 80 com compra urgente (AG7-07: vai como decisão), 65 com "compre até" hoje ou amanhã, 45 até compras_aviso_du dias úteis, modo = o do compre_ate; (k) a pergunta situacao/estimativa em que o dono já escolheu "eu digo os dias" (opcao_escolhida) não volta como linha pergunta (o prazo dela não vale mais). Sem o gestor em teste e sem compras, a saída de antes, byte a byte. FASE 7 (7a P11, spec §3.2 "Equipe" e §5.11): (l) a pergunta ficha_estimativa aberta de hoje (veto_ate hoje: a ficha das 19:30 de um dia pela estimativa, na janela de veto do ligar) numa linha própria, tipo pergunta, perda 75, com o pergunta_id (o fechamento que sai a conta como mostrada), uma por pessoa, modo = o da vigia; a linha (e) não a repete. Sem essa pergunta, a saída de antes, byte a byte. CORREÇÃO DA 7a (revisão da etapa): (achados 15 e 18) (m), no lugar da (l): as perguntas do gestor que esperam o dono — a ficha_estimativa de hoje, situacao, estimativa e reestimar — numa linha só, tipo pergunta: a 1ª (a ficha primeiro, depois a de prazo mais perto) com o texto inteiro, as outras curtas e agrupadas pelo prazo ("Também, sem resposta até ter 03/11 18:00: Nelson (OS-00112) 4 dias; …"; sem prazo: "Espero você: …"), até 600 caracteres, com pergunta_id (a 1ª) e pergunta_ids (todas as que a linha mostra: o fechamento que sai as conta como mostradas); perda 75 com alguma de prazo (ela perde no prazo), 30 sem; a linha (e) não as repete; (achado 14) a linha gestor de teste ("eu marcaria assim") vai com perda 25, abaixo de toda linha de verdade (só a comissão é menor); (achado 19) as compras com "compre até" hoje ou já vencido (comprando hoje ainda chega) vão como decisão, perda 80. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; os achados 15/18 de novo): a linha (m) das perguntas do gestor com prazo vai com perda 76 (ganha o desempate das que perdem hoje: antes perdia para a mensagem ao cliente pelo tipo e saía primeiro no corte de 1.000 do fechamento); as sem prazo dizem o porquê ("Espero você (não marco sozinho): Giancarlo (OS-00130)."); (o corte de 1.000) a linha (m) leva também texto_curto, com as MESMAS perguntas: a ficha sem as opções e cada uma pelo prazo e pelo que o gestor faz sem resposta ("Agenda: Sem resposta até ter 03/11 18:00, conto: Nelson (OS-00112) 4 dias; Flávio (OS-00104) 3,5 dias. Espero você (não marco sozinho): Giancarlo (OS-00130).") — o Secretário cheio a usa antes de tirar a linha. FASE 7b (P3, R4.2(d)): com modo_dias ou modo_cadastro fora de desligado, (n) a equipe — as perguntas abertas da equipe (a chamada equipe_cadastro:chamada, a dias_semana do dono, o telefone e o contato; não críticas, mostradas menos de perguntas_vezes_max vezes, fora as que um aviso de hoje levou) numa linha só, tipo pergunta, nesta ordem e depois a mais antiga: a 1ª com o texto inteiro, as outras curtas ("Também: o telefone do Alex (sem ele não mando a ficha)."; "Também: Mateus tem telefone; ponho na rotina? Responda 1 ou 2 em *agenda pendências*."; "Também: os dias da semana de 16/11 (responda em *agenda pendências*).") até 600 caracteres e o resto "(e mais N em *agenda equipe*)"; pergunta_id = a 1ª e pergunta_ids = todas as que a linha mostra (o fechamento que sai as conta como mostradas); perda 75 enquanto alguma nunca foi mostrada ou perde hoje (veto_ate ou perda_em de hoje), senão 30; modo ligado só com a pergunta em ligado e o modo dela ligado; texto_curto com as mesmas perguntas, só pelo nome ("Agenda, equipe: a equipe da agenda está certa?; o telefone do Alex. *agenda pendências* mostra."). A pergunta de fato (e) não as repete. Com os dois modos desligados, a saída de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achados 7 e 17): na linha (n) da equipe, a chamada e a pergunta dos dias que vão só como "Também: … (responda em *agenda pendências*)" ficam fora de pergunta_ids (não contam como mostradas; saem inteiras no fechamento em que vierem primeiro); a chamada da 7a (sem opções) usa o modo do gestor que marca, também com o cadastro da 7b em teste. CORREÇÃO 3 DA 7b (o R5.9 da spec da 7c; o R5.10-7): na linha (n) da equipe, a forma curta (texto_curto, a que o Secretário cheio usa, e o registro conta as pergunta_ids da linha sem saber qual forma saiu) leva, em cada pergunta que vence, o prazo e o "sigo assim" — "Agenda, equipe: a equipe da agenda está certa? — sem resposta até ter 10/11 às 18:00, sigo assim. *agenda pendências* mostra." —, com a data que o vencimento grava: a chamada contada na linha, com o cadastro fora de desligado, em _agenda_veto_ate(o dia do registro, equipe_chamada_prazo_du) (ou o veto_ate já gravado); a dos dias da semana, com modo_dias fora de desligado, no prazo da semana dela (perda_em, hora_do_plano − equipe_dias_fechar_antes). O telefone e o contato não vencem: como antes. A forma longa e o resto, byte a byte. FASE 7c (P5, R5.4 item 4, R5.1-6, R5.10-7/-8): o portão da linha (n) passa a "a 7b (modo_dias ou modo_cadastro) OU a 7c (modo_habilidade_propor ou modo_habilidade) fora de desligado"; dentro dela, as perguntas da 7b só com o portão da 7b e, depois delas, as de quem faz o quê (habilidade: primeiro a habilidade:equipe, depois as habilidade:os) só com o da 7c, com o modo de _agenda_modo_da_pergunta (a da equipe: modo_habilidade_propor; a de OS: modo_habilidade). A da equipe que vai só como "Também: quem faz o quê (marquei: Alex instala sozinho; responda em *agenda pendências*)." fica fora de pergunta_ids (não conta como vista); a de OS ("Também: Caio (OS-97173): falta quem comissiona Victron em todos os dias; quem pode? (responda em *agenda pendências*).") conta. A forma curta leva o que foi marcado e, na da equipe contada e ligada, o prazo: "quem faz o quê — marquei: Alex instala sozinho; sem resposta até qua 04/11 às 18:00, fica assim" (o veto_ate, ou _agenda_veto_ate do dia de hoje: a data que _agenda_habilidade_vetos grava depois do registro). A pergunta de fato (e) exclui as da 7b só com o portão da 7b e as de quem faz o quê só com o da 7c. Com os modos da 7c desligados, a saída de antes, byte a byte (com a 7b desligada e em teste). FASE 7c (P8, R5.4 item 4, R5.2-2(b) e (c)): com modo_tarefas fora de desligado, a linha (n) leva também as perguntas das etapas (tarefa:quem:<os>, depois tarefa:prazo:<os>; a de prazo que vence hoje ou no próximo dia útil perde hoje), só com o portão delas, e a (e) não as repete; e a linha (o) das etapas (tipo dia; até 480, sem números): a quem não recebe pelo WhatsApp (sem telefone pela régua da 7a ou fora da rotina) com etapa hoje ou no próximo dia útil — "Etapas (Alex não tem telefone: quem passa e confere é você). Hoje no Lenine devia ficar pronto: …. Se faltou alguma, me diga qual (…). Amanhã (qui 05/11), Alex no Lenine: Terminar: …; … — com você. É o último dia: tem que ficar tudo pronto." —, texto_curto "Etapas: amanhã é o último dia do Lenine (Alex, 2 etapas); hoje, 2 para conferir. Pergunte o que o Alex faz amanhã.", perda 75 só com o último dia de uma OS amanhã ou com uma pendente dita que volta primeiro (senão 70), sem pergunta; em teste, modo sombra e "Em teste: ". Com modo_tarefas desligado, a de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7c (20261102100580): (achado 14) na linha (n), sem nenhuma pergunta da 7b que perca hoje e com uma de quem faz o quê ou das etapas que perde hoje, as da 7b ficam fora da linha neste dia (a da 7c vai primeiro, inteira, e conta como vista; a chamada não gasta a vez dela num dia que não é o seu); (achado 8) com uma linha da 7c ligada de perda >= 75 (a (o) "Etapas" ou a (n) com pergunta de quem faz o quê ou das etapas), a linha do cliente de perda 75 ganha a forma curta ("Mensagem para Vera (véspera, com a pergunta do acesso) espera *manda cliente Vera* (sai ter 10/11 às 09:00); *agenda clientes* mostra."; com mais de uma, "… e mais N esperam *manda cliente* (a 1ª sai …) …"), para o Secretário cheio encolher a do cliente antes de tirar a da 7c; (achado 2) a (n) com uma pergunta de quem faz o quê ou das etapas ligada, contada, aberta e nunca vista há 2 dias úteis ou mais sobe de 75 a 77 (acima das perguntas do gestor, abaixo da compra e da decisão), salvo se uma linha de perda 76 a 79 perde algo hoje (a ficha de amanhã, um veto ou um prazo de hoje). Sem a 7c ligada, a de antes, byte a byte. CORREÇÃO 2 DA REVISÃO DA 7c (20261102100590): (achados 1 e 13) com a (n) de quem faz o quê nunca vista há 2 dias úteis (a que a 100580 sobe a 77) ou com a (o) "Etapas" ligada da véspera do último dia, todas as linhas ligadas de 75 sobem a 77 juntas quando há a pergunta do gestor de 76 para ceder (sai no corte a de 76, que não perde hoje, nunca a mensagem ao cliente) — sem ela, a (n) que a 100580 sobe volta a 75 —, salvo com uma linha de 76 a 79 que perde algo hoje; (achado 13) quando o próximo dia útil é dia de revisão da tarde (o 1º dia útil da semana ou do mês: turnoDaTarde), a (o) de hoje já cobra o último dia que cai no dia útil seguinte ("Ter 10/11 é o último dia do Lenine (Alex): tem que ficar tudo pronto — aviso hoje porque seg 09/11 é dia de revisão."), também na forma curta, com perda 75; (achado 15) a forma curta da (o) diz o dia ("seg 09/11", "Pergunte o que o Alex faz na seg 09/11.") quando o próximo dia útil não é amanhã; (achado 11) a de quem faz o quê da equipe, ligada, que vai como "Também" leva o que foi marcado e o prazo e conta como vista. Sem a 7c ligada, a de antes. FASE 7d (P5, R6.7c-3, R6.12): (a) a crítica acesso com a opção 2 já dita não volta ao fechamento; (e) a combinar com perda_em até o 2º dia útil sobe a 75 (a vaga garantida de agenda_textos_do_fechamento), a local fica em 30; (achado 13) o remendo "aviso hoje porque … é dia de revisão" sai: com as linhas nos dias de revisão (62d1fd95), a (o) cobra a véspera do último dia no próprio dia, e o v_c13_av fica vazio. A parte do achado 15 fica. Só pode ir ao ar com o ai-daily-briefing com 62d1fd95 no ar antes ou junto. FICHA PAGA (18/11/2026, 20270125100000): na linha (m), a ficha de OS paga (padrão 2) vem antes das outras fichas do dia (a 2ª sairia só como "Também …", sem o aviso); na forma curta, ela termina com "Para mandar, me diga *mande*." no lugar de "Para segurar, me diga.". Fora disso, byte a byte.';

-- ── 6. Portas ──────────────────────────────────────────────────────────────────────────────────────────
-- As 2 leituras novas como a _agenda_ficha_liberada que as lê: authenticated e service_role, nunca anon. As 4 recriadas mantêm as
-- portas de antes (create or replace não as muda).
revoke all on function public._agenda_os_paga_por_inteiro(uuid), public._agenda_ficha_os_pagas(uuid, date) from public, anon;
grant execute on function public._agenda_os_paga_por_inteiro(uuid), public._agenda_ficha_os_pagas(uuid, date) to authenticated, service_role;
