-- Agenda de Produção — OPÇÃO A (19/11/2026): o pedido de aprovação da mensagem ao cliente entra no resumo da manhã, com o prazo.
--
-- Decisão do dono (19/11): "O pedido de aprovação entra no resumo da manhã, com prazo." Formato combinado: "Aviso ao Rodrigo sobre o dia 25. Mando? (vence 14h)".
-- O dono responde por texto (WhatsApp sem botão) com as palavras que JÁ existem: *manda cliente <nome>* / *segura cliente <nome>* (agenda_cliente_decidir_dito;
-- sem nome = todas). Nada do que acontece depois do "manda" muda: _agenda_cliente_decidir → _agenda_cliente_enfileirar, com as travas de sempre.
--
-- Por quê (medido em 19/11, só leitura): de 28/10 a 18/11 nenhuma mensagem ao cliente saiu; 16 cliente_aprovar terminaram (15 vencidas pelo prazo, 1 pelo status),
-- 14 delas NUNCA mostradas ao dono. 13 das 16 tinham pelo menos um resumo da manhã ENVIADO entre nascer e vencer (de 5,5 h a 59,5 h antes de vencer), mas a manhã
-- não mostrava a agenda; o fechamento das 17:30 mostra uma só por vez (a 1ª por enviar_em, "E mais N") e saiu 3 vezes desde 14/11. As outras 3 nasceram depois da
-- manhã e venciam no mesmo dia (acesso/onde fica: falam do dia seguinte).
--
-- O que muda:
--   1. agenda_aprovacoes_da_manha(p_hoje, p_agora) — NOVA, stable, definer, só service_role: as mensagens em ligado esperando o *manda cliente* (aguardando_dono,
--      pedida, cliente_aprovar aberta, ainda válidas), da que vence primeiro para a última, até 5 linhas, e o bloco pronto para a manhã. O prazo é o do banco
--      (valida_ate, que é o expira_em da pergunta), escrito como "vence 19h" / "vence amanhã 19h" / "vence sáb 21/11 13h". Com modo_cliente fora de ligado, vazio.
--   2. A exibição é medida pelo contador que já existe (agenda_perguntas.mostrada_vezes/mostrada_em/mostrada_via), pelo MESMO caminho do fechamento: a manhã guarda
--      as perguntas que mostrou com o id da linha da fila do dono (agenda_fechamento_guardar, via 'manha') e elas só contam quando a fila disser 'sent'
--      (_agenda_fechamento_conferir, que o motor de 15 min já chama). Para isso:
--        · agenda_perguntas.mostrada_via e agenda_fechamento_fila.via aceitam 'manha';
--        · agenda_fechamento_guardar aceita p_via 'manha' (só linhas de pergunta: sem ação nem prazo);
--        · agenda_fechamento_registrar aceita p_via 'manha'. O resto dos dois corpos, byte a byte o de produção: tirados os blocos "-- OPÇÃO A: … -- OPÇÃO A: fim"
--          e devolvidas as linhas "--antes:" de dentro deles (a convenção da FICHA PAGA), o md5 sem CR volta a ser o de hoje (guardar c12f67c9…, registrar 9a035e2b…).
--      Mostrar cliente_aprovar não decide nada: ela não vence por prazo do gestor (c_nunca), e a linha do cliente do fechamento não olha o contador.
--   3. A regra de vencimento NÃO muda (ver o relatório): com o pedido na manhã, toda mensagem viva às 07:30 tem ao menos 5,5 h depois do resumo (valida_ate é o fim
--      da janela do dia de envio: 19:00 em dia útil, 13:00 no sábado). Empurrar a validade mudaria o que o cliente recebe (o texto fala do dia de envio).
--
-- Nenhum modo novo, nenhuma mensagem nova ao cliente, nenhum cron. A manhã só mostra; quem manda é o *manda cliente* do dono.
-- DESFAZER: recriar agenda_fechamento_guardar e agenda_fechamento_registrar de 20261113200000 / 20261109100200, voltar os dois CHECKs e
-- drop function public.agenda_aprovacoes_da_manha(date, timestamptz). A manhã (ai-daily-briefing) sem a função sai como antes (a leitura falha = sem o bloco).

-- ── 1. Os CHECKs aceitam 'manha' ─────────────────────────────────────────────────────────────────────────────────────────────────────
alter table public.agenda_perguntas drop constraint if exists agenda_perguntas_mostrada_via_check;
alter table public.agenda_perguntas add constraint agenda_perguntas_mostrada_via_check
  check (mostrada_via = any (array['fechamento'::text, 'acorde'::text, 'conversa'::text, 'aviso'::text, 'manha'::text]));

alter table public.agenda_fechamento_fila drop constraint if exists agenda_fechamento_fila_via_check;
alter table public.agenda_fechamento_fila add constraint agenda_fechamento_fila_via_check
  check (via = any (array['fechamento'::text, 'manha'::text]));

-- ── 2. A guarda aceita a manhã ───────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.agenda_fechamento_guardar(p_hoje date, p_linhas jsonb, p_fila uuid, p_via text default 'fechamento',
                                                            p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  q    record;
  v_id uuid;
  v_r  jsonb;
begin
  if p_hoje is null or p_fila is null or p_agora is null then
    raise exception 'agenda_fechamento_guardar: sem o dia, a linha da fila ou a hora.' using errcode = '22004';
  end if;
  -- OPÇÃO A: (19/11/2026) a manhã também espera a fila (só perguntas). As linhas de antes, em "--antes:".
--antes:  if p_via is null or p_via <> 'fechamento' then
--antes:    raise exception 'Por onde foi mostrado: "%" (só o fechamento espera a fila).', coalesce(p_via, '') using errcode = '22023';
  if p_via is null or p_via not in ('fechamento', 'manha') then
    raise exception 'Por onde foi mostrado: "%" (só o fechamento e a manhã esperam a fila).', coalesce(p_via, '') using errcode = '22023';
  -- OPÇÃO A: fim
  end if;
  if jsonb_typeof(coalesce(p_linhas, '[]'::jsonb)) <> 'array' then
    raise exception 'As linhas mostradas vêm numa lista.' using errcode = '22023';
  end if;
  -- OPÇÃO A: (19/11/2026) a manhã só mostra perguntas — nada de ação contada nem de prazo escrito (o pedido ao cliente não tem veto)
  if p_via = 'manha' and exists (select 1 from jsonb_array_elements(coalesce(p_linhas, '[]'::jsonb)) x
                                  where jsonb_typeof(x) <> 'object' or x ? 'veto_ate' or x ? 'veto_diria'
                                     or coalesce(jsonb_array_length(case when jsonb_typeof(x -> 'acao_ids') = 'array' then x -> 'acao_ids' end), 0) > 0) then
    raise exception 'A manhã só mostra perguntas (sem ação nem prazo).' using errcode = '22023';
  end if;
  -- OPÇÃO A: fim
  select f.id, f.status into q from public.whatsapp_send_queue f where f.id = p_fila;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'sem_fila', 'perguntas', 0, 'acoes', 0);
  end if;
  insert into public.agenda_fechamento_fila (dia, fila_id, via, linhas, criada_em)
  values (p_hoje, p_fila, p_via, coalesce(p_linhas, '[]'::jsonb), p_agora)
  on conflict (fila_id) do nothing
  returning id into v_id;
  if v_id is null then
    return jsonb_build_object('ok', true, 'estado', 'ja_existe', 'perguntas', 0, 'acoes', 0);
  end if;
  if q.status = 'sent' then
    v_r := public._agenda_fechamento_conferir(p_agora, v_id);
    return jsonb_build_object('ok', true, 'estado', 'registrada', 'id', v_id,
                              'perguntas', coalesce((v_r ->> 'perguntas')::int, 0), 'acoes', coalesce((v_r ->> 'acoes')::int, 0));
  end if;
  return jsonb_build_object('ok', true, 'estado', 'esperando', 'id', v_id, 'perguntas', 0, 'acoes', 0);
end;
$function$;

comment on function public.agenda_fechamento_guardar(date, jsonb, uuid, text, timestamptz) is
  'Agenda de Produção (consertos de 13/11, (b)): as linhas da agenda que o fechamento levou ({pergunta_id, acao_ids, pergunta_ids?, veto_ate?, veto_diria?}, as de agenda_fechamento_registrar), guardadas com o id da linha da fila da tarde (agenda_fechamento_fila). Só contam como mostradas quando a fila diz sent (_agenda_fechamento_conferir; o motor de 15 min confere em agenda_aviso_conferir); se a fila já mandou, contam agora, na hora em que saiu. A mesma linha da fila 2x = ja_existe (nada conta de novo). Sem a linha da fila = {ok:false, motivo:sem_fila} (nada guardado). {ok, estado: esperando|registrada|ja_existe, id, perguntas, acoes}. Só o fechamento (p_via). Definer, só o service_role. OPÇÃO A (19/11/2026, 20270128100000): p_via ''manha'' também — o resumo da manhã guarda as perguntas cliente_aprovar que mostrou (agenda_aprovacoes_da_manha) com o id da linha da fila do dono; na manhã cada linha é só de pergunta ({pergunta_id, pergunta_ids?}, acao_ids vazia, sem veto_ate nem veto_diria): o resto = 22023.';

-- ── 3. O registro aceita a manhã ─────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.agenda_fechamento_registrar(p_hoje date, p_linhas jsonb, p_via text default 'fechamento',
                                                              p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  e      jsonb;
  v_perg int := 0;
  v_acao int := 0;
  v_n    int;
begin
  -- OPÇÃO A: (19/11/2026) a manhã também mostra (pela guarda, depois que a fila mandou). As linhas de antes, em "--antes:".
--antes:  if p_via is null or p_via not in ('fechamento', 'acorde', 'conversa') then
--antes:    raise exception 'Por onde foi mostrado: "%" (fechamento, acorde ou conversa).', coalesce(p_via, '') using errcode = '22023';
  if p_via is null or p_via not in ('fechamento', 'acorde', 'conversa', 'manha') then
    raise exception 'Por onde foi mostrado: "%" (fechamento, acorde, conversa ou manhã).', coalesce(p_via, '') using errcode = '22023';
  -- OPÇÃO A: fim
  end if;
  if jsonb_typeof(coalesce(p_linhas, '[]'::jsonb)) <> 'array' then
    raise exception 'As linhas mostradas vêm numa lista.' using errcode = '22023';
  end if;
  for e in select x from jsonb_array_elements(coalesce(p_linhas, '[]'::jsonb)) x loop
    if e ->> 'pergunta_id' is not null then
      update public.agenda_perguntas q
         set mostrada_vezes = least(q.mostrada_vezes + 1, 50), mostrada_em = p_agora, mostrada_via = p_via
             -- FASE 7f: (7f P3, §3.1 item 7, §5.3, R8.5-1) no MESMO update que a mostra: o prazo escrito no texto que o dono viu. Sem veto_ate na linha, nada muda: ele é nulo em sombra e com o
             -- freio (_agenda_pergunta_linha), e o relógio nunca começa de um prazo que ele não leu. A que espera ele não ganha prazo. De um valor a outro, só a que nunca foi mostrada antes do
             -- prazo velho (a regra de _agenda_perguntas_antes): o que ele já viu com prazo não muda. veto_diria é o prazo que seria, em sombra: só veto_teria_em, para medir, uma vez.
             , veto_ate = case when q.veto_espera is not null then q.veto_ate
                               when q.veto_ate is null then (e ->> 'veto_ate')::timestamptz
                               when q.veto_ate < p_agora and (e ->> 'veto_ate')::timestamptz > q.veto_ate
                                    and not coalesce(q.mostrada_vezes > 0 and q.mostrada_em < q.veto_ate, false) then (e ->> 'veto_ate')::timestamptz
                               else q.veto_ate end
             , veto_teria_em = coalesce(q.veto_teria_em, (e ->> 'veto_diria')::timestamptz)
             -- FASE 7f: fim
       where q.id = (e ->> 'pergunta_id')::uuid and q.estado = 'aberta';
      get diagnostics v_n = row_count;
      v_perg := v_perg + v_n;
    end if;
    -- FASE 7: (7a correção, achado 15) a linha das perguntas do gestor mostra várias: cada uma de pergunta_ids (fora a pergunta_id,
    -- já contada) ganha a mostrada
    if jsonb_typeof(e -> 'pergunta_ids') = 'array' then
      update public.agenda_perguntas q
         set mostrada_vezes = least(q.mostrada_vezes + 1, 50), mostrada_em = p_agora, mostrada_via = p_via
       where q.id in (select y::uuid from jsonb_array_elements_text(e -> 'pergunta_ids') y)
         and q.id is distinct from nullif(e ->> 'pergunta_id', '')::uuid and q.estado = 'aberta';
      get diagnostics v_n = row_count;
      v_perg := v_perg + v_n;
    end if;
    -- FASE 7: fim
    if jsonb_typeof(e -> 'acao_ids') = 'array' then
      update public.agenda_acoes a set contada_em = p_agora, contada_via = p_via
       where a.id in (select y::uuid from jsonb_array_elements_text(e -> 'acao_ids') y) and a.contada_em is null;
      get diagnostics v_n = row_count;
      v_acao := v_acao + v_n;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'perguntas', v_perg, 'acoes', v_acao);
end;
$function$;

comment on function public.agenda_fechamento_registrar(date, jsonb, text, timestamptz) is
  'Agenda de Produção (Fase 2, P3): o que o fechamento (ou a conversa) mostrou da agenda — para cada linha {pergunta_id?, acao_ids?}: a pergunta aberta ganha mostrada_vezes + 1, mostrada_em e mostrada_via; as ações ainda não contadas ganham contada_em/contada_via. Chamada pelo secretário quando o fechamento saiu com as linhas da agenda em ligado. Só service_role. CORREÇÃO DA 7a (revisão da etapa; achado 15): a linha pode trazer também pergunta_ids (a linha das perguntas do gestor, que mostra várias numa só): cada pergunta aberta da lista que não é a pergunta_id ganha a mostrada. FASE 7f (P3; §3.1 item 7, §5.3): a linha pode trazer veto_ate, o prazo escrito no texto, gravado no mesmo update que mostra, só na pergunta que não espera o dono, sem prazo, ou que nunca foi mostrada antes do prazo velho. veto_diria vai para veto_teria_em. Sem as 2 chaves, nada muda. OPÇÃO A (19/11/2026, 20270128100000): p_via ''manha'' também (o resumo da manhã, pela guarda: só depois que a fila mandou).';

-- ── 4. As aprovações da manhã ────────────────────────────────────────────────────────────────────────────────────────────────────────
-- Uma linha por mensagem esperando o *manda cliente*, a que vence primeiro em cima: "Rodrigo: a véspera com a pergunta do acesso (qua 25/11). Mando? (vence 19h)".
-- O nome é o curto (o que *manda cliente <nome>* acha); dois clientes diferentes com o mesmo nome curto na lista saem pelo nome inteiro (o *manda* acharia os dois e
-- pediria o sobrenome). O "o quê" é _agenda_cliente_o_que (o mesmo do "Amanhã … vou mandar" do fechamento). Até 5 linhas; o resto, "e mais N" (*agenda clientes*).
-- Só as linhas escritas vão em linhas[] (as que contam como mostradas quando a manhã sair).
create or replace function public.agenda_aprovacoes_da_manha(p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  c_max    constant int := 5;
  r        record;
  v_linhas jsonb := '[]'::jsonb;
  v_txt    text[] := '{}';
  v_total  int := 0;
  v_nomes  text[] := '{}';
  v_nome   text;
  v_dia    date;
  v_hora   text;
  v_vence  text;
  v_oque   text;
  v_linha  text;
  v_bloco  text;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_aprovacoes_da_manha: sem o dia ou a hora.' using errcode = '22004';
  end if;
  if cf.modo_cliente is distinct from 'ligado' then
    return jsonb_build_object('total', 0, 'linhas', '[]'::jsonb, 'texto', null);
  end if;
  for r in
    with base as (
      select m.id as msg, q.id as pergunta_id, m.client_id, m.tipo, m.enviar_em,
             coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) as dia,
             least(m.valida_ate, coalesce(q.expira_em, m.valida_ate)) as vence,
             public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as curto,
             coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name) as completo,
             cl.name as ordem_nome, so.service_order_number as os_num
        from public.agenda_cliente_mensagens m
        join public.agenda_perguntas q on q.id = m.pergunta_id
        join public.clients cl on cl.id = m.client_id
        left join public.service_orders so on so.id = m.service_order_id
       where m.modo = 'ligado' and m.estado = 'aguardando_dono' and m.aprovacao = 'pedida'
         and q.tipo = 'cliente_aprovar' and q.estado = 'aberta' and q.modo = 'ligado'
         and m.valida_ate > p_agora and (q.expira_em is null or q.expira_em > p_agora)
    ), mesmo_nome as (
      select public._agenda_normal(b.curto) as chave from base b group by 1 having count(distinct b.client_id) > 1
    )
    select b.*, (public._agenda_normal(b.curto) in (select x.chave from mesmo_nome x)) as ambiguo, count(*) over () as n,
           count(*) over (partition by b.client_id) as do_cliente
      from base b
     order by b.vence, b.enviar_em, b.ordem_nome, b.msg
  loop
    v_total := r.n;
    exit when cardinality(v_txt) >= c_max;
    v_nome := case when r.ambiguo then r.completo else r.curto end;
    v_dia := (r.vence at time zone 'America/Sao_Paulo')::date;
    v_hora := to_char(r.vence at time zone 'America/Sao_Paulo', 'FMHH24') || 'h'
              || case when extract(minute from r.vence at time zone 'America/Sao_Paulo') <> 0
                      then to_char(r.vence at time zone 'America/Sao_Paulo', 'MI') else '' end;
    v_vence := 'vence ' || case when v_dia = p_hoje then v_hora
                                when v_dia = p_hoje + 1 then 'amanhã ' || v_hora
                                else public._dia_curto(v_dia) || ' ' || v_hora end;
    v_oque := coalesce(public._agenda_cliente_o_que(r.tipo, r.dia),
                       'a mensagem' || coalesce(' (' || public._agenda_cliente_tipo_texto(r.tipo) || ')', ''));
    -- o mesmo cliente com mais de uma mensagem: a OS diz qual é qual (o *manda cliente <nome>* manda as dele)
    v_linha := format('%s%s: %s. Mando? (%s)', v_nome, case when r.do_cliente > 1 and r.os_num is not null then ' (' || r.os_num || ')' else '' end,
                      v_oque, v_vence);
    v_txt := v_txt || v_linha;
    if not v_nome = any (v_nomes) then
      v_nomes := v_nomes || v_nome;
    end if;
    v_linhas := v_linhas || jsonb_build_object('pergunta_id', r.pergunta_id, 'mensagem_id', r.msg, 'nome', v_nome,
                                               'texto', v_linha, 'vence_em', r.vence);
  end loop;
  if v_total = 0 then
    return jsonb_build_object('total', 0, 'linhas', '[]'::jsonb, 'texto', null);
  end if;
  v_bloco := case when v_total = 1 then '📨 Mensagem ao cliente esperando o seu sim:' else '📨 Mensagens ao cliente esperando o seu sim:' end
             || E'\n' || array_to_string(array(select '• ' || t from unnest(v_txt) t), E'\n')
             || case when v_total > cardinality(v_txt)
                     then format(E'\n• e mais %s (*agenda clientes* mostra)', v_total - cardinality(v_txt)) else '' end
             || E'\n'
             || case when cardinality(v_nomes) = 1 and v_total = cardinality(v_txt)
                     then format('Para mandar: *manda cliente %s*. Para não mandar: *segura cliente %s*.', v_nomes[1], v_nomes[1])
                     else format('Para mandar: *manda cliente %s* (ou *manda cliente*: as %s). Para não mandar: *segura cliente %s*.',
                                 v_nomes[1], v_total, v_nomes[1]) end
             || ' O texto: *agenda clientes*.';
  return jsonb_build_object('total', v_total, 'linhas', v_linhas, 'texto', v_bloco);
end;
$function$;

comment on function public.agenda_aprovacoes_da_manha(date, timestamptz) is
  'Agenda de Produção, OPÇÃO A (19/11/2026, decisão do dono): o pedido de aprovação da mensagem ao cliente no resumo da manhã, com o prazo. As mensagens em ligado esperando o *manda cliente* (aguardando_dono, pedida, a pergunta cliente_aprovar aberta em ligado, valida_ate e expira_em depois de p_agora), da que vence primeiro: até 5 linhas "<nome>: <o que> (de _agenda_cliente_o_que). Mando? (vence 19h | vence amanhã 19h | vence sáb 21/11 13h)" — o prazo é least(valida_ate, expira_em), do banco —, "e mais N (*agenda clientes* mostra)" e as palavras que já existem (*manda cliente <nome>*, *manda cliente* = todas, *segura cliente <nome>*). Nome curto; o inteiro quando dois clientes da lista têm o mesmo curto; com a OS ("Rodrigo (OS-00129): …") quando o mesmo cliente tem mais de uma. modo_cliente fora de ligado = vazio. {total, linhas: [{pergunta_id, mensagem_id, nome, texto, vence_em}] (só as escritas), texto (o bloco, ou null)}. Só lê. Definer, só o service_role (o ai-daily-briefing).';

-- ── 5. Portas ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
-- As recriadas mantêm as de antes (create or replace não mexe na ACL); repetidas aqui para a migration ficar inteira.
revoke all on function public.agenda_fechamento_guardar(date, jsonb, uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_fechamento_guardar(date, jsonb, uuid, text, timestamptz) to service_role;
revoke all on function public.agenda_fechamento_registrar(date, jsonb, text, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_fechamento_registrar(date, jsonb, text, timestamptz) to service_role;
revoke all on function public.agenda_aprovacoes_da_manha(date, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_aprovacoes_da_manha(date, timestamptz) to service_role;

insert into supabase_migrations.schema_migrations (version, name) values ('20270128100000','agenda_aprovacao_na_manha');
