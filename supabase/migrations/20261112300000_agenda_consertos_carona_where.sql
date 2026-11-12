-- Agenda de Produção: consertos de 12/11/2026 (aprovados pelo dono em 12/11). Só funções: nenhuma tabela, dado, cron, edge ou tela.
--
-- 1. A carona nunca respondia pelo assistente. public.agenda_carona(p_autor, p_os, p_canal, p_hoje, p_agora) não tinha valor padrão, e o
--    ai-agent chama caronaDoTurno/comCarona (_shared/agenda/carona.ts) só com {p_autor, p_os, p_canal} nos 4 caminhos (WhatsApp e painel,
--    pela API e pelo Max): o PostgREST não acha função com esses 3 nomes e devolve 404 (edge_logs de 12/11 00:49 UTC, POST 404
--    /rest/v1/rpc/agenda_carona); o erro é engolido e nunca saiu um "Aproveitando: …".
--    O conserto: p_hoje e p_agora ganham DEFAULT, como nas outras funções da agenda: public._hoje_brt() (o dia de São Paulo,
--    (now() at time zone 'America/Sao_Paulo')::date; nunca current_date, que segue o fuso da sessão) e now(). O corpo é o de
--    20261027100300 byte a byte (md5 sem CR b1186db65b9e98fe8b7326607036d5aa, o de produção em 12/11): as réguas de md5 (prosrc) não
--    mudam e nenhum TS muda (nada a republicar). O create or replace mantém dono, ACL e comment; as portas de antes são reafirmadas.
--    Efeito: o Postgres não deixa um create or replace TIRAR default (42P13). Uma cópia futura da carona tem de levar os defaults (sem
--    eles, falha alto); a bancada, que roda as migrations 2x, derruba a carona antes da 20261026100500 na 2ª rodada
--    (FUNCOES_COM_DEFAULT_DEPOIS em scripts/bancada-agenda/bancada.mjs).
--
-- 2. UPDATE/DELETE sem WHERE: o pg_safeupdate das sessões do PostgREST recusa (HTTP 400 "... requires a WHERE clause"); pelo cron e pelo
--    CLI passa, por isso a bancada não pegava. Procurado em todas as funções da agenda, com os literais em branco e os subselects de fora:
--    · agenda_cliente_decidir_dito (*manda cliente* / *segura cliente*, pela RPC do WhatsApp e do painel): "delete from
--      _agenda_cliente_alvo;" (a tabela temporária) vira "... where true;" (a mesma coisa: apaga tudo). O resto é o corpo de
--      20261028100800 byte a byte (md5 sem CR de antes ee49cf5005d294fde1f125c7550fbe0e); defaults, dono, ACL e comment de antes.
--    · _agenda_aplicar_habilidade: não tem. A consulta de referência corta o comando no 1º ';', e o ';' do texto 'você corrigiu; o resto
--      ficou como eu marquei' cai antes do "where id = v_q" do UPDATE de agenda_perguntas. Não muda.
--    Prova: supabase/tests/agenda_consertos_carona_where.sql.
--
-- DESFAZER (numa transação; o create or replace não tira default): drop function public.agenda_carona(uuid, text[], text, date,
--   timestamptz), a definição e o comment de 20261027100300, revoke all ... from public, anon, authenticated, grant execute ... to
--   service_role; e a definição de agenda_cliente_decidir_dito de 20261028100800 (o create or replace basta: mesmos defaults).

-- ── 1. A carona: p_hoje e p_agora com DEFAULT (o corpo de 20261027100300, sem mudança) ───────────────────────────────────────────

create or replace function public.agenda_carona(p_autor uuid, p_os text[], p_canal text,
                                                p_hoje date default public._hoje_brt(),
                                                p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf    public.agenda_config := public._agenda_cfg();
  v_ids uuid[] := '{}';
  v_ro  jsonb;
  v_ref text;
  v_os  uuid;
  q     record;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_carona: sem o dia ou a hora de agora' using errcode = '22004';
  end if;
  if p_canal is null or p_canal not in ('whatsapp', 'painel') then
    raise exception 'Por onde: "%" (whatsapp ou painel).', coalesce(p_canal, '') using errcode = '22023';
  end if;
  -- só com a vigia ligada (a pergunta de fato é dela) e só para o dono
  if cf.modo_vigia <> 'ligado' then
    return null;
  end if;
  if p_autor is null or not exists (select 1 from public.app_users u where u.id = p_autor and u.active and u.role = 'admin') then
    return null;
  end if;
  -- as OS como o turno citou (número, nome ou id), resolvidas aqui; ref ambígua = nada (pode ser outra OS)
  foreach v_ref in array coalesce(p_os, '{}'::text[]) loop
    continue when nullif(btrim(v_ref), '') is null;
    v_ro := public.agenda_resolver_os(left(btrim(v_ref), 80), p_hoje, false);
    if v_ro ->> 'status' = 'ambiguo' then
      return null;
    end if;
    if v_ro ->> 'status' in ('ok', 'fora_da_carteira') and not ((v_ro ->> 'id')::uuid = any (v_ids)) then
      v_ids := v_ids || (v_ro ->> 'id')::uuid;
    end if;
  end loop;
  if cardinality(v_ids) <> 1 then
    return null;
  end if;
  v_os := v_ids[1];
  -- uma carona por OS a cada carona_por_os_dias
  if exists (select 1 from public.agenda_perguntas x
              where (x.service_order_id = v_os or v_os = any (x.os_ids))
                and x.carona_em is not null and x.carona_em >= p_agora - make_interval(days => cf.carona_por_os_dias)) then
    return null;
  end if;
  select x.* into q from public.agenda_perguntas x
   where x.estado = 'aberta' and x.modo = 'ligado' and (x.service_order_id = v_os or v_os = any (x.os_ids))
     and (x.expira_em is null or x.expira_em > p_agora)
     and (x.critica or x.tipo in ('chegou', 'parada', 'estouro', 'duracao', 'material_conferir', 'concluir', 'entrega', 'diaria_ligar'))
   order by x.critica desc, x.perda_em nulls last, x.id
   limit 1;
  -- FASE 4: (P3) sem pergunta das Fases 2–3 da OS, a do material dela (a nota, o Pix, a mensagem do fornecedor), a que
  -- perde primeiro. A da nota pode citar mais de uma OS (os_ids): vai de carona em qualquer uma.
  if q.id is null then
    select x.* into q from public.agenda_perguntas x
     where x.estado = 'aberta' and x.modo = 'ligado' and (x.service_order_id = v_os or v_os = any (x.os_ids))
       and (x.expira_em is null or x.expira_em > p_agora)
       and x.tipo in ('nfe_vincular', 'pix_material', 'previsao_fornecedor')
     order by x.perda_em nulls last, x.criada_em, x.id
     limit 1;
  end if;
  -- FASE 4: fim
  if q.id is null then
    return null;
  end if;
  -- a que já saiu hoje no fechamento não vai de novo
  if q.mostrada_via = 'fechamento' and (q.mostrada_em at time zone 'America/Sao_Paulo')::date = p_hoje then
    return null;
  end if;
  update public.agenda_perguntas
     set carona_em = p_agora, mostrada_vezes = least(mostrada_vezes + 1, 50), mostrada_em = p_agora, mostrada_via = 'conversa'
   where id = q.id;
  return jsonb_build_object('pergunta_id', q.id, 'os', v_os, 'tipo', q.tipo, 'texto', 'Aproveitando: ' || q.texto);
end;
$function$;

-- As portas, como estavam (create or replace mantém; reafirmadas para a migration valer sozinha): só service_role.
revoke all on function public.agenda_carona(uuid, text[], text, date, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_carona(uuid, text[], text, date, timestamptz) to service_role;

-- ── 2. *manda/segura cliente*: o DELETE da tabela temporária com WHERE (o corpo de 20261028100800 + a linha marcada) ─────────────

create or replace function public.agenda_cliente_decidir_dito(p_autor uuid, p_acao text, p_alvo text default null,
                                                              p_canal text default 'whatsapp',
                                                              p_hoje date default public._hoje_brt(),
                                                              p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_autor  uuid := public._autor_da_agenda(p_autor);
  v_acao   text := lower(btrim(coalesce(p_acao, '')));
  v_via    text := case when p_canal in ('whatsapp', 'painel', 'tela') then p_canal else 'whatsapp' end;
  v_alvo   text := nullif(btrim(coalesce(p_alvo, '')), '');
  v_norm   text := public._agenda_normal(p_alvo);
  v_trecho text;
  r        record;
  v_r      jsonb;
  v_msgs   uuid[] := '{}';
  v_txts   text[] := '{}';
  v_nomes  text[] := '{}';
  v_quando text[] := '{}';
  v_todos_ok boolean := true;
  v_crit   int;
  v_cli    int;
  v_lista  text;
  v_q      text;
  v_txt    text;
begin
  if v_acao not in ('manda', 'segura') then
    raise exception 'A palavra da mensagem ao cliente é *manda cliente* ou *segura cliente* (veio "%").', coalesce(p_acao, '')
      using errcode = '22023';
  end if;
  v_trecho := format('%s cliente%s', v_acao, coalesce(' ' || v_alvo, ''));
  if cf.modo_cliente = 'desligado' then
    return jsonb_build_object('ok', false, 'status', 'nao_achei',
                              'texto', 'As mensagens ao cliente estão desligadas: não há nada para mandar nem segurar.');
  end if;
  if cf.modo_cliente <> 'ligado' then
    return jsonb_build_object('ok', false, 'status', 'em_teste', 'texto', 'As mensagens ao cliente estão em teste: nada sai ainda.');
  end if;
  if v_alvo is not null and (char_length(v_alvo) > 40 or v_norm = '') then
    return jsonb_build_object('ok', false, 'status', 'nao_achei',
                              'texto', format('Não achei mensagem esperando para "%s".', left(v_alvo, 40)));
  end if;

  -- as mensagens vivas em ligado do alvo: as que esperam o dono (pedida; a crítica só para dizer que é decisão) e, no
  -- *segura*, as que iam sair sozinhas
  create temp table if not exists _agenda_cliente_alvo (id uuid, pergunta_id uuid, estado text, aprovacao text,
                                                        enviar_em timestamptz, client_id uuid, nome text, completo text)
    on commit drop;
  -- CONSERTO 12/11 (pg_safeupdate): pelo PostgREST, DELETE sem WHERE é recusado (HTTP 400); "where true" apaga tudo, como antes.
  delete from _agenda_cliente_alvo where true;
  insert into _agenda_cliente_alvo
  select m.id, m.pergunta_id, m.estado, m.aprovacao, m.enviar_em, m.client_id,
         public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)),
         coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)
    from public.agenda_cliente_mensagens m
    join public.clients cl on cl.id = m.client_id
   where m.modo = 'ligado'
     and ((m.estado = 'aguardando_dono' and m.aprovacao in ('pedida', 'critica'))
          or (v_acao = 'segura' and m.estado in ('registrada', 'enfileirada', 'aguardando_dono')
              and m.aprovacao in ('livre', 'aprovada')))
     and (v_alvo is null
          or public._agenda_normal(public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name))) = v_norm
          or public._agenda_normal(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) = v_norm
          or public._agenda_normal(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) like v_norm || ' %'
          or public._agenda_normal(cl.name) = v_norm or public._agenda_normal(cl.name) like v_norm || ' %');

  select count(*) filter (where a.aprovacao = 'critica'), count(distinct a.client_id) filter (where a.aprovacao <> 'critica')
    into v_crit, v_cli from _agenda_cliente_alvo a;
  if v_cli = 0 then
    if v_crit > 0 then
      return jsonb_build_object('ok', false, 'status', 'decisao',
                                'texto', 'Essa é uma decisão: responda pela conversa (opção 1, 2 ou 3).');
    end if;
    return jsonb_build_object('ok', false, 'status', case when v_alvo is null then 'nenhuma' else 'nao_achei' end,
      'texto', case when v_alvo is null then 'Não tenho mensagem ao cliente esperando você.'
                    else format('Não achei mensagem esperando para "%s".', v_alvo) end);
  end if;
  if v_alvo is not null and v_cli > 1 then
    select public._agenda_lista(array_agg(distinct a.completo order by a.completo), null) into v_lista
      from _agenda_cliente_alvo a where a.aprovacao <> 'critica';
    return jsonb_build_object('ok', false, 'status', 'ambiguo',
      'texto', format('Tem %s clientes "%s" esperando (%s): diga o sobrenome.', v_cli, v_alvo, v_lista));
  end if;

  for r in select a.* from _agenda_cliente_alvo a where a.aprovacao <> 'critica' order by a.enviar_em, a.id loop
    if v_acao = 'manda' then
      continue when r.estado <> 'aguardando_dono' or r.aprovacao <> 'pedida';
      v_r := public._agenda_cliente_decidir(r.pergunta_id, 1::smallint, v_autor, v_via, v_trecho, p_agora);
      v_q := case when v_r ->> 'estado' = 'enfileirada' then 'agora'
                  else public._agenda_cliente_quando_texto((select m.enviar_em from public.agenda_cliente_mensagens m
                                                             where m.id = r.id), p_agora) end;
      v_todos_ok := v_todos_ok and coalesce((v_r ->> 'ok')::boolean, false)
                    and coalesce(v_r ->> 'estado', '') in ('aguardando_dono', 'registrada', 'enfileirada');
    elsif r.estado = 'aguardando_dono' and r.aprovacao = 'pedida' and r.pergunta_id is not null then
      v_r := public._agenda_cliente_decidir(r.pergunta_id, 2::smallint, v_autor, v_via, v_trecho, p_agora);
      v_todos_ok := v_todos_ok and coalesce((v_r ->> 'ok')::boolean, false);
    elsif public._agenda_cliente_cancelar(r.id, 'segurada', 'o dono segurou a mensagem') then
      update public.agenda_cliente_mensagens
         set aprovacao = 'segurada', aprovada_em = p_agora,
             aprovada_por = (select u.id from public.app_users u where u.id = v_autor)
       where id = r.id;
      v_r := jsonb_build_object('ok', true, 'texto', format('Segurei a mensagem do %s: ela não sai.', r.nome));
    else
      v_r := jsonb_build_object('ok', false, 'texto', format('A mensagem do %s já está saindo: não deu para segurar.', r.nome));
      v_todos_ok := false;
    end if;
    -- CORREÇÃO FASE 5: (item 15) o texto de cada uma sem artigo antes do nome ("Segurei a mensagem de Nelson: ela não sai."),
    -- como o da decisão (_agenda_cliente_decidir)
    v_r := jsonb_set(v_r, '{texto}', to_jsonb(coalesce(public._agenda_cliente_sem_artigo(v_r ->> 'texto',
             (select m.service_order_id from public.agenda_cliente_mensagens m where m.id = r.id)), '')));
    -- CORREÇÃO FASE 5: fim
    v_msgs := v_msgs || r.id;
    v_txts := v_txts || coalesce(v_r ->> 'texto', '');
    v_quando := v_quando || coalesce(v_q, '');
    if not r.nome = any (v_nomes) then
      v_nomes := v_nomes || r.nome;
    end if;
  end loop;

  if cardinality(v_msgs) = 0 then
    -- *manda* sem nenhuma esperando o dono (só as que já iam sair sozinhas)
    return jsonb_build_object('ok', false, 'status', 'nenhuma',
      'texto', case when v_alvo is null then 'Não tenho mensagem ao cliente esperando você.'
                    else format('Não achei mensagem esperando para "%s".', v_alvo) end);
  end if;
  v_txt := case
    when cardinality(v_msgs) = 1 then v_txts[1]
    when v_acao = 'manda' and v_todos_ok and (select count(distinct q) from unnest(v_quando) q) = 1
      then format('Mandei %s: %s (saem %s).', cardinality(v_msgs), public._agenda_lista(v_nomes, null), v_quando[1])
    when v_acao = 'segura' and v_todos_ok
      then format('Segurei %s: as mensagens do %s não saem.', cardinality(v_msgs), public._agenda_lista(v_nomes, null))
    else array_to_string(v_txts, ' ') end;
  -- CORREÇÃO FASE 5: (item 15) "Segurei 2: as mensagens de Nelson e Flávio não saem."
  v_txt := replace(v_txt, ': as mensagens do ', ': as mensagens de ');
  -- CORREÇÃO FASE 5: fim
  return jsonb_build_object('ok', true, 'status', 'ok', 'texto', v_txt, 'decididas', cardinality(v_msgs),
                            'mensagens', to_jsonb(v_msgs));
end;
$function$;

-- As portas, como estavam: authenticated (o painel) e service_role (o WhatsApp); nunca anon.
revoke all on function public.agenda_cliente_decidir_dito(uuid, text, text, text, date, timestamptz) from public, anon;
grant execute on function public.agenda_cliente_decidir_dito(uuid, text, text, text, date, timestamptz) to authenticated, service_role;

-- O PostgREST relê as funções (a chamada da carona só com p_autor, p_os e p_canal passa a existir para ele).
notify pgrst, 'reload schema';
