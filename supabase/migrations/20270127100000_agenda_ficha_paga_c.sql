-- Agenda: ficha paga, parte C (18/11/2026) — sobre a 20270126100000 (F2b v3)
-- Plano: D:/IA-HBR/agenda-pesquisa/via-os129-1711/plano/F2c/RESUMO.md. Resposta do dono (18/11 ~18:10, cartão da revisão da F2b v2, item 2b):
--   "Não mandar o 'como foi'": o dia em que a ficha do técnico ficou segurada NÃO recebe o "Como foi hoje?" das 17:00 (ex.: o Alex não
--   recebe a ficha de qui; então qui às 17:00 ele também não recebe o "como foi").
--
-- O que muda (o mínimo possível, só uma função):
--   _agenda_rotina_como_foi: com a mensagem à equipe ligada, a pessoa cujo plano do dia NÃO chegou por veto — a ficha do dia (a da
--   véspera, 19:30) registrada como recusada por veto (_agenda_ficha_liberada falso) e nenhuma confirmação da manhã do dia que tenha
--   saído (enfileirada, enviada) — não entra no "como foi". Sem o "como foi", o "ok" dela não vira prova de trabalho (o "começou" da
--   F2b), e o dia seguinte continua segurado até o *mande* do dono. O dono, quem teve a ficha liberada, quem recebeu a confirmação e
--   quem teve a ficha recusada por outro motivo (teto, janela, telefone) seguem iguais. Desligado ou em teste: o de antes.
--   Nenhuma mensagem nova: o dia sem resposta segue o caminho de sempre (a vigia o marca sem_registro depois, sem mensagem).
-- Toda mudança é ACRÉSCIMO, em blocos "-- FICHA PAGA C: (…) … -- FICHA PAGA C: fim": tirados os blocos C, a função é a de produção,
-- byte a byte (20261109101000; conferir-acrescimo-c.mjs). Os testes de cópia tiram os blocos "-- FICHA PAGA:", "-- FICHA PAGA B:" e
-- "-- FICHA PAGA C:".
--
-- ORDEM: a F2c só depois da F2b (a guarda do aplicar exige a 20270126100000 registrada); desfazer a F2c ANTES da F2b (a guarda 5 do
-- desfazer da F2b recusa com a F2c registrada).
-- DESFAZER: D:/IA-HBR/agenda-pesquisa/via-os129-1711/plano/F2c/desfazer.sql (a definição de produção).

-- ── 1. O "como foi" do dia segurado ──────────────────────────────────────────────────────────────────────
-- _agenda_rotina_como_foi (de 20261109101000 (produção em 18/11); md5 do corpo de antes d3e8b6f77ecef723fd4a529979ea338f sem CR)
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
  -- FASE 7f: (7f P5) o previsto e a mudança junto da ficha que vai no "como foi"
  v_7f_s    jsonb;
  v_7f_prev boolean;
  v_7f_mud  boolean;
  v_7f_txt  text;
  v_7f_dias date[];
  -- FASE 7f: fim
begin
  if v_local::time < cf.equipe_hora_como_foi then
    return jsonb_build_object('como_foi', 0);
  end if;
  for v_p in select x from public._agenda_contatos_com_plano(p_hoje) x loop
    continue when exists (select 1 from public.agenda_equipe_mensagens m
                           where m.payee_id = v_p and m.modo = v_modo and m.tipo = 'como_foi' and m.dia = p_hoje);
    -- FICHA PAGA C: (18/11/2026, 20270127100000; decisão do dono "Não mandar o 'como foi'") com a mensagem à equipe ligada, quem não
    -- recebeu o plano do dia por veto — a ficha do dia (a da véspera) recusada por veto (_agenda_ficha_liberada falso) e nenhuma
    -- confirmação da manhã do dia que tenha saído — não recebe o "como foi hoje?": o "ok" dele viraria prova de trabalho (o "começou" da
    -- F2b) e soltaria o dia seguinte sem o *mande*. A ficha recusada por outro motivo (teto, janela, telefone): o de antes.
    continue when v_modo = 'ligado'
                  and exists (select 1 from public.agenda_equipe_mensagens m
                               where m.payee_id = v_p and m.modo = 'ligado' and m.tipo = 'ficha' and m.dia = p_hoje
                                 and m.estado = 'recusada' and m.recusa_motivo = 'veto')
                  and not exists (select 1 from public.agenda_equipe_mensagens m
                                   where m.payee_id = v_p and m.modo = 'ligado' and m.tipo = 'confirmar' and m.dia = p_hoje
                                     and m.estado <> 'recusada');
    -- FICHA PAGA C: fim
    v_f := public.agenda_equipe_ficha(v_p, p_hoje, p_hoje);
    continue when not coalesce((v_f ->> 'tem_plano')::boolean, false);
    v_leva := exists (select 1 from public.agenda_equipe_mensagens m
                       where m.payee_id = v_p and m.modo = v_modo and m.tipo = 'confirmar' and m.dia = p_hoje
                         and m.estado <> 'recusada')
              and not exists (select 1 from public.agenda_equipe_mensagens m
                               where m.payee_id = v_p and m.modo = v_modo and m.tipo = 'ficha' and m.dia = v_d);
    v_fd := case when v_leva then public.agenda_equipe_ficha(v_p, v_d, p_hoje) end;
    v_leva := v_leva and coalesce((v_fd ->> 'tem_plano')::boolean, false);
    -- FASE 7: (7a P11, spec §3.2 "Equipe" e §5.11; AG7-15) a ficha de amanhã que iria junto do "como foi hoje?" obedece a mesma
    -- proteção da ficha das 19:30 (_agenda_ficha_liberada) e mais: o "como foi" sai antes da hora da ficha, quando o dono ainda
    -- pode segurá-la; então a ficha de um dia pela estimativa na janela de veto só vai junto com o "mande" dele (opção 1). Senão o
    -- "como foi" vai sem ela, e a rotina da hora da ficha decide.
    if v_leva and v_modo = 'ligado'
       and (not public._agenda_ficha_liberada(v_p, v_d, p_agora)
            or exists (select 1 from public.agenda_perguntas q
                        where q.chave = format('ficha_estimativa:%s:%s', v_p, v_d) and q.modo = 'ligado'
                          and q.opcao_escolhida is distinct from 1)) then
      v_leva := false;
    end if;
    -- FASE 7: fim
    -- FASE 7f: (7f P5, §5.5 (2) e (3), R8.5-17) a ficha de amanhã que vai no "como foi" (às 17:00, quando a confirmação de hoje saiu) leva o mesmo que a das
    -- 19:30 levaria: a mudança da semana e, na quinta, o previsto (uma mensagem só; a ficha das 19:30 não sai para quem já a recebeu aqui). Só com o previsto
    -- ligado de verdade e a equipe ligada; sem nada a dizer ou passando de 600 letras, o de antes, byte a byte.
    v_7f_txt := null;
    v_7f_dias := null;
    if v_leva and v_modo = 'ligado' and public._agenda_fala_modo('previsto') = 'ligado' then
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
        if char_length(coalesce(v_f ->> 'texto_como_foi', '')) + 1 + char_length(coalesce(v_fd ->> 'texto_curto', '')) + char_length(v_7f_txt) > 600 then
          v_7f_txt := null;
          v_7f_dias := null;
        end if;
      end if;
    end if;
    if v_7f_txt is not null then
      v_r := public._agenda_equipe_registrar(v_p, p_hoje, 'como_foi', (v_f ->> 'texto_como_foi') || ' ' || (v_fd ->> 'texto_curto') || v_7f_txt,
                                             p_agora, v_d, null, v_7f_dias);
    else
    -- FASE 7f: fim
    v_r := public._agenda_equipe_registrar(v_p, p_hoje, 'como_foi',
             (v_f ->> 'texto_como_foi') || case when v_leva then ' ' || (v_fd ->> 'texto_curto') else '' end,
             p_agora, case when v_leva then v_d end);
    -- FASE 7f: (7f P5) o fim do if de cima
    end if;
    -- FASE 7f: fim
    v_cont := v_cont || jsonb_build_object(coalesce(v_r ->> 'estado', 'nada'),
                                           coalesce((v_cont ->> coalesce(v_r ->> 'estado', 'nada'))::int, 0) + 1);
  end loop;
  return jsonb_build_object('por_estado', v_cont);
end;
$function$;

comment on function public._agenda_rotina_como_foi(date, timestamptz) is
  'Agenda de Produção (Fase 3, P4): o "como foi hoje?" (equipe_hora_como_foi) a quem teve plano hoje; no dia em que a confirmação da manhã saiu, ele leva a ficha de amanhã (e a hora da ficha não manda nada). FASE 7 (7a P11; AG7-15): a ficha de amanhã de um dia pela estimativa na janela de veto só vai junto com o "mande" do dono (a opção 1 da pergunta ficha_estimativa) — o "como foi" sai antes do fechamento e da hora da ficha; sem isso (ou com _agenda_ficha_liberada falso), ele vai sem a ficha e a rotina da hora da ficha decide. Fora disso, a de antes, byte a byte. FASE 7f (P5): a ficha de amanhã que vai junto do "como foi" leva, com o previsto ligado de verdade e a equipe ligada, a mudança da semana e, na quinta, o previsto (uma mensagem só), e grava em dias o que a pessoa passa a ter ouvido. Fora disso, o de antes, byte a byte. FICHA PAGA C (18/11/2026, 20270127100000; decisão do dono "Não mandar o ''como foi''"): com a mensagem à equipe ligada, quem não recebeu o plano do dia por veto — a ficha do dia recusada por veto (_agenda_ficha_liberada falso) e nenhuma confirmação da manhã do dia que tenha saído — não recebe o "como foi hoje?" (o "ok" dele viraria prova de trabalho e soltaria o dia seguinte sem o *mande*). O dono, quem teve a ficha liberada, quem recebeu a confirmação e a ficha recusada por outro motivo: o de antes. Nenhuma mensagem nova.';

-- A porta não muda (create or replace a mantém: só o dono do banco).
