-- Secretário, Passo 4 ("uma voz só"), P4.0 (15/10/2026): o portão. Tudo que o sistema diz ao dono por
-- conta própria passa a REGISTRAR um aviso aqui, e o portão decide uma de quatro coisas:
--   acordar  → a fonte pode mandar agora (no máximo 2 por dia, das 08:00 às 19:59 de Brasília, um por
--              assunto; das 08:00 às 09:29 sem cartão de sim/não — é a janela da manhã);
--   guardar  → vai na próxima mensagem fixa (manhã das 07:30 ou fechamento das 17:30). Nada é
--              descartado: o guardado só sai quando a mensagem que o contém for entregue;
--   deixar   → fica como está (pedido do próprio dono, resposta a uma ação dele, mensagem fixa própria);
--   acabar   → uma mensagem fixa já leva isso (ex.: "vence hoje" já está na manhã).
-- Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-uma-voz.md (§3.4, §3.5, §3.6, §6)
--
-- Nesta publicação nada muda para o dono: a chave voz_unica nasce 'desligado' e, até o P4.5, as fontes
-- só REGISTRAM (modo 'sombra'), para comparar o que o portão faria com o que de fato saiu.
--   * avisos_do_dono: um aviso por (telefone, modo, chave), com a decisão, a situação e a mensagem fixa
--     que o leva;
--   * aviso_registrar: a única entrada (trava por telefone e dia; repetido = a mesma chave);
--   * aviso_reabrir: o envio de um acorde falhou → volta a guardado e libera a vaga do dia;
--   * avisos_para_a_mensagem: o que a manhã/o fechamento deve levar (confere antes o que já foi
--     incluído: entregue de verdade só com a fila 'sent'; falhou → volta a guardado);
--   * avisos_incluir_na_mensagem: a mensagem fixa diz quais levou (e o id da fila);
--   * aviso_resolver: o guardado que deixou de ser verdade antes da mensagem fixa (D8: some).
--
-- GRAVA DADO — OK NOMEADO: três chaves em app_settings (bloco 7):
--   voz_unica = 'desligado' (desligado | sombra | ligado; até o P4.5 'ligado' ainda age como sombra);
--   voz_unica_regras = as respostas-padrão das decisões abertas do dono (D1–D10, JSON);
--   acompanhar_freio = 'ligado' (P4.3: no máximo 2 avisos de acompanhamento por mensagem do contato).
-- Recria o gatilho _app_settings_chaves_do_dono com as três chaves (só o admin muda). DEPENDE DO PASSO 3:
-- em produção (15/10/2026) o corpo é o de 20261015200000 (md5 do prosrc normalizado — A-Z em minúscula, sem
-- espaços — 42dded24d25e3fcf4cb6a05c0f18c16e); o Passo 3 (20261015210000_resumo_tarde, commit e52ee042,
-- publicado ANTES desta) o recria com fechamento_formato (md5 4e65302e7fcfa0998c412ff6b20366ce). Este corpo é
-- o do Passo 3 + as três chaves daqui, e a guarda só aceita o do Passo 3 ou o próprio: fora disso, para sem
-- apagar nada. Idempotente.

-- ---------------------------------------------------------------------------------------------
-- 0. A guarda do gatilho das chaves, ANTES de qualquer criação (para parar sem deixar nada pela metade).
-- ---------------------------------------------------------------------------------------------
-- O gatilho tem de ser o do Passo 3 (20261015210000, commit e52ee042: o de 20261015200000 + fechamento_formato,
-- md5 4e65302e7fcfa0998c412ff6b20366ce) ou já este (2ª aplicação). Qualquer outro — inclusive o de antes do
-- Passo 3 (42dded24d25e3fcf4cb6a05c0f18c16e, o de produção em 15/10/2026) — PARA a migration sem apagar nada:
-- aplicado antes do Passo 3, este corpo levaria fechamento_formato junto, e a guarda do Passo 3 recusaria o
-- corpo daqui (a ordem é Passo 3 → esta).
do $$
declare
  v_md5 text;
begin
  select md5(regexp_replace(translate(p.prosrc, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), '\s+', '', 'g'))
    into v_md5
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = '_app_settings_chaves_do_dono';
  if v_md5 is null or v_md5 not in ('4e65302e7fcfa0998c412ff6b20366ce', 'e59e8bdee68ab39b9f77422ae0b378e7') then
    raise exception 'o gatilho _app_settings_chaves_do_dono não é o do Passo 3 (md5 %): aplique antes 20261015210000_resumo_tarde ou confira o corpo em produção antes de recriar', coalesce(v_md5, 'ausente');
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. avisos_do_dono
-- ---------------------------------------------------------------------------------------------
create table if not exists public.avisos_do_dono (
  id                   uuid primary key default gen_random_uuid(),
  -- o dia de Brasília do registro: é o dia do limite de acordes
  dia                  date not null,
  phone_normalized     text not null,
  modo                 text not null,
  -- quem pediu para falar (vigia_negocio, email, acompanhar, promessa, lead_site, conexao, saldos…)
  fonte                text not null,
  -- a identidade do aviso: a mesma chave de novo = repetido (golpe:<remetente>, nfe_rejeitada:<dia>…)
  chave                text not null,
  -- "um aviso por assunto": dois avisos do mesmo assunto no mesmo dia acordam uma vez só
  assunto              text not null,
  -- de quem é (acomp:<id>:<última recebida> — a contagem do freio)
  referencia           text,
  -- o que a fonte pediu
  destino              text not null,
  -- o que o portão decidiu na hora (não muda)
  decisao              text not null,
  -- onde o aviso está agora
  situacao             text not null,
  motivo               text,
  -- o acorde pode levar cartão de sim/não? (só depois das 09:30)
  cartao               boolean not null default false,
  -- a mensagem fixa que leva o guardado, e a partir de quando ela pode levá-lo
  mensagem             text,
  entregar_a_partir_de timestamptz,
  texto                text,
  dados                jsonb not null default '{}'::jsonb,
  fila_id              uuid,
  pendencia_id         uuid,
  incluido_em          timestamptz,
  entregue_em          timestamptz,
  -- quantas vezes voltou a guardado (envio que falhou)
  reaberto             smallint not null default 0,
  -- o relógio da decisão (now(), ou o "agora" do ensaio)
  registrado_em        timestamptz not null,
  criado_em            timestamptz not null default now(),
  atualizado_em        timestamptz not null default now(),
  constraint avisos_do_dono_chave_unica unique (phone_normalized, modo, chave),
  constraint avisos_do_dono_phone_chk check (phone_normalized ~ '^[0-9]{10,15}$'),
  constraint avisos_do_dono_modo_chk check (modo in ('sombra', 'ligado')),
  -- lista aberta de propósito (fonte nova não pode subir sem efeito por um CHECK esquecido)
  constraint avisos_do_dono_fonte_chk check (fonte ~ '^[a-z][a-z_]{2,39}$'),
  constraint avisos_do_dono_chave_chk check (char_length(chave) between 3 and 200),
  constraint avisos_do_dono_assunto_chk check (char_length(assunto) between 3 and 200),
  constraint avisos_do_dono_referencia_chk check (referencia is null or char_length(referencia) between 3 and 200),
  constraint avisos_do_dono_destino_chk check (destino in ('acorde', 'proxima_fixa', 'hoje', 'escritorio', 'deixar', 'acaba')),
  constraint avisos_do_dono_decisao_chk check (decisao in ('acordar', 'guardar', 'deixar', 'acabar')),
  constraint avisos_do_dono_situacao_chk check (situacao in ('acordou', 'guardado', 'incluido', 'entregue', 'resolvido', 'deixado', 'acabou')),
  constraint avisos_do_dono_motivo_chk check (motivo is null or motivo ~ '^[a-z][a-z_]{1,59}$'),
  constraint avisos_do_dono_mensagem_chk check (mensagem is null or mensagem in ('manha', 'fechamento')),
  -- quem espera mensagem fixa sabe qual e desde quando
  constraint avisos_do_dono_guardado_chk check (
    situacao not in ('guardado', 'incluido', 'entregue') or (mensagem is not null and entregar_a_partir_de is not null)),
  -- incluído/entregue numa mensagem que existe na fila (a sombra não enfileira)
  constraint avisos_do_dono_fila_chk check (situacao not in ('incluido', 'entregue') or fila_id is not null or modo = 'sombra'),
  constraint avisos_do_dono_cartao_chk check (not cartao or decisao = 'acordar'),
  constraint avisos_do_dono_texto_chk check (texto is null or char_length(texto) <= 4000),
  constraint avisos_do_dono_dados_chk check (jsonb_typeof(dados) = 'object' and octet_length(dados::text) <= 8192),
  constraint avisos_do_dono_reaberto_chk check (reaberto between 0 and 50)
);

comment on table public.avisos_do_dono is
  'Secretário (Passo 4, 15/10/2026): o portão "uma voz só". Cada aviso que uma fonte quer dar ao dono, com a decisão (acordar, guardar, deixar, acabar) e onde ele está (acordou, guardado, incluido, entregue, resolvido, deixado, acabou). Modo sombra = só registro, para comparar. Só o admin lê; escrita só pelas RPCs aviso_*/avisos_* (service_role).';
comment on column public.avisos_do_dono.chave is 'Identidade do aviso: a mesma chave de novo (mesmo telefone e modo) = repetido, nada novo.';
comment on column public.avisos_do_dono.assunto is 'Um acorde por assunto por dia: o 2º aviso do mesmo assunto no mesmo dia vai guardado (salvo novo_fato).';
comment on column public.avisos_do_dono.entregar_a_partir_de is 'A mensagem fixa que pode levar o guardado: a primeira (manhã ou fechamento) que sair depois desta hora.';

create index if not exists avisos_do_dono_do_dia
  on public.avisos_do_dono (phone_normalized, modo, dia, situacao);
create index if not exists avisos_do_dono_esperando
  on public.avisos_do_dono (phone_normalized, modo, entregar_a_partir_de)
  where situacao in ('guardado', 'incluido');
create index if not exists avisos_do_dono_referencia
  on public.avisos_do_dono (referencia) where referencia is not null;

-- ---------------------------------------------------------------------------------------------
-- 2. RLS e privilégios (revogar de anon/authenticated POR NOME)
-- ---------------------------------------------------------------------------------------------
alter table public.avisos_do_dono enable row level security;

revoke all on table public.avisos_do_dono from public, anon, authenticated;
grant select on table public.avisos_do_dono to authenticated;
grant all on table public.avisos_do_dono to service_role;
drop policy if exists avisos_do_dono_admin_le on public.avisos_do_dono;
create policy avisos_do_dono_admin_le on public.avisos_do_dono
  for select to authenticated using (public.is_admin((select auth.uid())));

-- ---------------------------------------------------------------------------------------------
-- 3. _aviso_proxima_mensagem: a próxima mensagem fixa que pode levar um aviso guardado
--    Espelho de proximaMensagemFixa (_shared/uma-voz/janela.ts); o ensaio da bancada compara os dois.
--    'hoje'       → só a manhã (07:30 de hoje se ainda não passou; senão a de amanhã);
--    'escritorio' → só o fechamento (17:30 do próximo seg–sex);
--    o resto      → a primeira: manhã de hoje (antes das 07:30), fechamento de hoje (seg–sex antes das
--                   17:30), manhã de amanhã; sábado → manhã de domingo (D7; 'segunda' → de segunda).
--    Feriado não entra aqui: o guardado espera a PRIMEIRA mensagem que sair depois de entregar_a_partir_de,
--    então num feriado sem fechamento a manhã seguinte o leva.
-- ---------------------------------------------------------------------------------------------
create or replace function public._aviso_proxima_mensagem(p_agora timestamptz, p_destino text, p_sabado text default 'domingo')
returns table (mensagem text, a_partir timestamptz)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_local timestamp := p_agora at time zone 'America/Sao_Paulo';
  v_dia   date := (p_agora at time zone 'America/Sao_Paulo')::date;
  v_hora  time := (p_agora at time zone 'America/Sao_Paulo')::time;
  v_dow   integer := extract(dow from (p_agora at time zone 'America/Sao_Paulo'))::integer;
  v_d     date;
begin
  if p_destino = 'hoje' then
    mensagem := 'manha';
    a_partir := ((case when v_hora < time '07:30' then v_dia else v_dia + 1 end) + time '07:30') at time zone 'America/Sao_Paulo';
    return next;
    return;
  end if;
  if p_destino = 'escritorio' then
    v_d := case when v_dow between 1 and 5 and v_hora < time '17:30' then v_dia else v_dia + 1 end;
    while extract(dow from v_d) in (0, 6) loop
      v_d := v_d + 1;
    end loop;
    mensagem := 'fechamento';
    a_partir := (v_d + time '17:30') at time zone 'America/Sao_Paulo';
    return next;
    return;
  end if;
  if v_hora < time '07:30' then
    mensagem := 'manha';
    a_partir := (v_dia + time '07:30') at time zone 'America/Sao_Paulo';
  elsif v_dow between 1 and 5 and v_hora < time '17:30' then
    mensagem := 'fechamento';
    a_partir := (v_dia + time '17:30') at time zone 'America/Sao_Paulo';
  elsif v_dow = 6 and p_sabado = 'segunda' then
    mensagem := 'manha';
    a_partir := ((v_dia + 2) + time '07:30') at time zone 'America/Sao_Paulo';
  else
    mensagem := 'manha';
    a_partir := ((v_dia + 1) + time '07:30') at time zone 'America/Sao_Paulo';
  end if;
  return next;
end $$;

comment on function public._aviso_proxima_mensagem(timestamptz, text, text) is
  'Secretário: a próxima mensagem fixa (manha 07:30 | fechamento 17:30 seg–sex) que pode levar um aviso guardado, a partir de um instante. Interna; espelho de proximaMensagemFixa (TS).';

-- ---------------------------------------------------------------------------------------------
-- 4. aviso_registrar: a única entrada do portão
--    p = {phone, modo ('sombra'|'ligado'), fonte, chave, assunto?, destino, referencia?, texto?, dados?,
--         novo_fato? (fato novo do mesmo assunto que pode acordar de novo — D2), agora? (o ensaio)}
--    Devolve {ok, decisao (acordar|guardar|deixar|acabar|repetido), situacao, motivo, cartao, id,
--             mensagem, entregar_a_partir_de, acordes_hoje}. Quem recebe 'acordar' envia; se o envio
--    falhar, chama aviso_reabrir.
-- ---------------------------------------------------------------------------------------------
create or replace function public.aviso_registrar(p jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_agora     timestamptz;
  v_dia       date;
  v_hora      time;
  v_phone     text := p->>'phone';
  v_modo      text := coalesce(nullif(p->>'modo', ''), 'sombra');
  v_fonte     text := p->>'fonte';
  v_chave     text := p->>'chave';
  v_assunto   text := coalesce(nullif(p->>'assunto', ''), p->>'chave');
  v_destino   text := p->>'destino';
  v_novo_fato boolean;
  v_regras    jsonb;
  v_limite    integer := 2;
  v_sabado    text := 'domingo';
  v_existe    record;
  v_acordes   integer;
  v_decisao   text;
  v_situacao  text;
  v_motivo    text;
  v_cartao    boolean := false;
  v_mensagem  text;
  v_a_partir  timestamptz;
  v_id        uuid;
begin
  begin
    v_agora := coalesce(nullif(p->>'agora', '')::timestamptz, now());
    v_novo_fato := coalesce((p->>'novo_fato')::boolean, false);
  exception when others then
    return jsonb_build_object('ok', false, 'erro', 'agora ou novo_fato inválido');
  end;
  if v_phone is null or v_phone !~ '^[0-9]{10,15}$' or v_fonte is null or v_chave is null or v_destino is null then
    return jsonb_build_object('ok', false, 'erro', 'faltam phone, fonte, chave ou destino');
  end if;
  if v_modo not in ('sombra', 'ligado')
     or v_destino not in ('acorde', 'proxima_fixa', 'hoje', 'escritorio', 'deixar', 'acaba') then
    return jsonb_build_object('ok', false, 'erro', 'modo ou destino desconhecido');
  end if;
  v_dia := (v_agora at time zone 'America/Sao_Paulo')::date;
  v_hora := (v_agora at time zone 'America/Sao_Paulo')::time;

  -- As regras do dono (app_settings.voz_unica_regras): quantos acordes por dia (0–5, padrão 2) e para
  -- onde vai o excesso de sábado (D7). Chave ausente ou JSON ruim = o padrão.
  begin
    select s.value::jsonb into v_regras from public.app_settings s where s.key = 'voz_unica_regras';
    v_limite := least(greatest(coalesce((v_regras->>'acordes_por_dia')::integer, 2), 0), 5);
    if v_regras->>'sabado' in ('domingo', 'segunda') then
      v_sabado := v_regras->>'sabado';
    end if;
  exception when others then
    v_limite := 2;
    v_sabado := 'domingo';
  end;

  -- 1. A trava: duas fontes ao mesmo tempo, no mesmo telefone e dia, não passam as duas.
  perform pg_advisory_xact_lock(hashtext('avisos_do_dono:' || v_phone || ':' || v_modo || ':' || v_dia::text));

  -- 2. A mesma chave já passou: repetido (nada novo).
  select a.id, a.decisao, a.situacao into v_existe
    from public.avisos_do_dono a
   where a.phone_normalized = v_phone and a.modo = v_modo and a.chave = v_chave;
  if found then
    return jsonb_build_object('ok', true, 'decisao', 'repetido', 'id', v_existe.id,
                              'antes', v_existe.decisao, 'situacao', v_existe.situacao);
  end if;

  -- 3. A decisão.
  if v_destino = 'deixar' then
    v_decisao := 'deixar';
    v_situacao := 'deixado';
  elsif v_destino = 'acaba' then
    v_decisao := 'acabar';
    v_situacao := 'acabou';
  elsif v_destino <> 'acorde' then
    v_decisao := 'guardar';
    v_situacao := 'guardado';
    v_motivo := 'destino';
  elsif v_hora < time '08:00' or v_hora >= time '20:00' then
    v_decisao := 'guardar';
    v_situacao := 'guardado';
    v_motivo := 'fora_da_janela';
  elsif not v_novo_fato and exists (
          select 1 from public.avisos_do_dono a
           where a.phone_normalized = v_phone and a.modo = v_modo and a.dia = v_dia
             and a.assunto = v_assunto and a.situacao = 'acordou') then
    v_decisao := 'guardar';
    v_situacao := 'guardado';
    v_motivo := 'assunto_ja_acordou_hoje';
  else
    select count(*) into v_acordes
      from public.avisos_do_dono a
     where a.phone_normalized = v_phone and a.modo = v_modo and a.dia = v_dia and a.situacao = 'acordou';
    if v_acordes >= v_limite then
      v_decisao := 'guardar';
      v_situacao := 'guardado';
      v_motivo := 'limite_do_dia';
    else
      v_decisao := 'acordar';
      v_situacao := 'acordou';
      -- das 08:00 às 09:29 é a janela da manhã: acorda só com a informação, sem sim/não
      v_cartao := v_hora >= time '09:30';
      v_motivo := case when v_cartao then null else 'janela_da_manha' end;
    end if;
  end if;

  if v_situacao = 'guardado' then
    select x.mensagem, x.a_partir into v_mensagem, v_a_partir
      from public._aviso_proxima_mensagem(
             v_agora, case when v_destino in ('hoje', 'escritorio') then v_destino else 'proxima_fixa' end, v_sabado) x;
  end if;

  insert into public.avisos_do_dono (dia, phone_normalized, modo, fonte, chave, assunto, referencia, destino, decisao,
                                     situacao, motivo, cartao, mensagem, entregar_a_partir_de, texto, dados, registrado_em)
  values (v_dia, v_phone, v_modo, v_fonte, v_chave, v_assunto, nullif(p->>'referencia', ''), v_destino, v_decisao,
          v_situacao, v_motivo, v_cartao, v_mensagem, v_a_partir, left(p->>'texto', 4000),
          case when jsonb_typeof(p->'dados') = 'object' then p->'dados' else '{}'::jsonb end, v_agora)
  on conflict (phone_normalized, modo, chave) do nothing
  returning id into v_id;
  if v_id is null then
    -- a mesma chave entrou por outro dia ao mesmo tempo (a trava é por dia): vale a primeira
    select a.id, a.decisao, a.situacao into v_existe
      from public.avisos_do_dono a
     where a.phone_normalized = v_phone and a.modo = v_modo and a.chave = v_chave;
    return jsonb_build_object('ok', true, 'decisao', 'repetido', 'id', v_existe.id,
                              'antes', v_existe.decisao, 'situacao', v_existe.situacao);
  end if;

  select count(*) into v_acordes
    from public.avisos_do_dono a
   where a.phone_normalized = v_phone and a.modo = v_modo and a.dia = v_dia and a.situacao = 'acordou';
  return jsonb_build_object('ok', true, 'decisao', v_decisao, 'situacao', v_situacao, 'motivo', v_motivo,
                            'cartao', v_cartao, 'id', v_id, 'mensagem', v_mensagem,
                            'entregar_a_partir_de', v_a_partir, 'acordes_hoje', v_acordes, 'limite', v_limite);
end $$;

comment on function public.aviso_registrar(jsonb) is
  'Secretário (uma voz só): registra um aviso ao dono e decide acordar (até 2/dia, 08–20h, um por assunto; cartão só depois das 09:30), guardar (próxima mensagem fixa), deixar ou acabar. A mesma chave = repetido. Só service_role.';

-- ---------------------------------------------------------------------------------------------
-- 5. aviso_reabrir: o acorde não saiu (envio falhou) → guardado para a próxima mensagem fixa, e a vaga
--    do dia fica livre. p = {id, agora?}
-- ---------------------------------------------------------------------------------------------
create or replace function public.aviso_reabrir(p jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id       uuid;
  v_agora    timestamptz;
  v_aviso    record;
  v_sabado   text := 'domingo';
  v_mensagem text;
  v_a_partir timestamptz;
begin
  begin
    v_id := (p->>'id')::uuid;
    v_agora := coalesce(nullif(p->>'agora', '')::timestamptz, now());
  exception when others then
    return jsonb_build_object('ok', false, 'erro', 'id ou agora inválido');
  end;
  select a.id, a.situacao, a.phone_normalized, a.modo, a.dia into v_aviso
    from public.avisos_do_dono a where a.id = v_id for update;
  if not found then
    return jsonb_build_object('ok', true, 'resultado', 'nao_achei');
  end if;
  if v_aviso.situacao <> 'acordou' then
    return jsonb_build_object('ok', true, 'resultado', 'nao_estava_acordado', 'situacao', v_aviso.situacao);
  end if;
  begin
    select case when s.value::jsonb->>'sabado' in ('domingo', 'segunda') then s.value::jsonb->>'sabado' else 'domingo' end
      into v_sabado from public.app_settings s where s.key = 'voz_unica_regras';
  exception when others then
    v_sabado := 'domingo';
  end;
  select x.mensagem, x.a_partir into v_mensagem, v_a_partir
    from public._aviso_proxima_mensagem(v_agora, 'proxima_fixa', coalesce(v_sabado, 'domingo')) x;
  update public.avisos_do_dono a
     set situacao = 'guardado', motivo = 'envio_falhou', cartao = false, mensagem = v_mensagem,
         entregar_a_partir_de = v_a_partir, reaberto = least(a.reaberto + 1, 50), atualizado_em = now()
   where a.id = v_id;
  return jsonb_build_object('ok', true, 'resultado', 'reaberto', 'mensagem', v_mensagem, 'entregar_a_partir_de', v_a_partir);
end $$;

comment on function public.aviso_reabrir(jsonb) is
  'Secretário (uma voz só): o acorde não saiu → volta a guardado (próxima mensagem fixa) e libera a vaga do dia. Só service_role.';

-- ---------------------------------------------------------------------------------------------
-- 6. avisos_para_a_mensagem / avisos_incluir_na_mensagem / aviso_resolver
--    A mensagem fixa (manhã ou fechamento) pergunta o que levar, diz o que levou e marca o que deixou de
--    ser verdade. "Nunca descartado": o incluído só vira entregue quando a fila diz 'sent'; se a fila
--    falhou (ou a linha sumiu), volta a guardado e a próxima mensagem fixa o leva.
-- ---------------------------------------------------------------------------------------------
-- p = {phone, modo, mensagem ('manha'|'fechamento'), agora?}
create or replace function public.avisos_para_a_mensagem(p jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_phone    text := p->>'phone';
  v_modo     text := coalesce(nullif(p->>'modo', ''), 'sombra');
  v_mensagem text := p->>'mensagem';
  v_agora    timestamptz;
  v_entregues integer := 0;
  v_voltaram integer := 0;
  v_avisos   jsonb;
begin
  begin
    v_agora := coalesce(nullif(p->>'agora', '')::timestamptz, now());
  exception when others then
    return jsonb_build_object('ok', false, 'erro', 'agora inválido');
  end;
  if v_phone is null or v_mensagem is null or v_mensagem not in ('manha', 'fechamento') or v_modo not in ('sombra', 'ligado') then
    return jsonb_build_object('ok', false, 'erro', 'faltam phone ou mensagem (manha|fechamento)');
  end if;

  -- o que foi incluído numa mensagem que JÁ saiu: entregue
  update public.avisos_do_dono a
     set situacao = 'entregue', entregue_em = coalesce(f.sent_at, now()), atualizado_em = now()
    from public.whatsapp_send_queue f
   where a.phone_normalized = v_phone and a.modo = v_modo and a.situacao = 'incluido'
     and f.id = a.fila_id and f.status = 'sent';
  get diagnostics v_entregues = row_count;
  -- o que foi incluído numa mensagem que NÃO saiu (falhou, cancelada, sumiu da fila): volta a guardado
  update public.avisos_do_dono a
     set situacao = 'guardado', fila_id = null, incluido_em = null, reaberto = least(a.reaberto + 1, 50),
         motivo = 'mensagem_nao_saiu', atualizado_em = now()
   where a.phone_normalized = v_phone and a.modo = v_modo and a.situacao = 'incluido' and a.fila_id is not null
     and not exists (select 1 from public.whatsapp_send_queue f
                      where f.id = a.fila_id and f.status in ('pending', 'sending', 'sent'));
  get diagnostics v_voltaram = row_count;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', a.id, 'fonte', a.fonte, 'assunto', a.assunto, 'destino', a.destino, 'motivo', a.motivo,
           'texto', a.texto, 'dados', a.dados, 'registrado_em', a.registrado_em, 'dia', a.dia,
           'mensagem', a.mensagem, 'reaberto', a.reaberto) order by a.registrado_em, a.id), '[]'::jsonb)
    into v_avisos
    from (select * from public.avisos_do_dono a
           where a.phone_normalized = v_phone and a.modo = v_modo and a.situacao = 'guardado'
             and a.entregar_a_partir_de <= v_agora
             and (a.destino in ('acorde', 'proxima_fixa')
                  or (a.destino = 'hoje' and v_mensagem = 'manha')
                  or (a.destino = 'escritorio' and v_mensagem = 'fechamento'))
           order by a.registrado_em, a.id
           limit 50) a;

  return jsonb_build_object('ok', true, 'avisos', v_avisos, 'entregues', v_entregues, 'voltaram', v_voltaram);
end $$;

comment on function public.avisos_para_a_mensagem(jsonb) is
  'Secretário (uma voz só): os avisos guardados que a mensagem fixa (manha|fechamento) deve levar agora. Antes, confere os já incluídos: fila sent = entregue; fila que não saiu = volta a guardado. Só service_role.';

-- p = {phone, modo, ids: [uuid…], fila_id (obrigatório no modo ligado), agora?}
create or replace function public.avisos_incluir_na_mensagem(p jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_phone text := p->>'phone';
  v_modo  text := coalesce(nullif(p->>'modo', ''), 'sombra');
  v_ids   uuid[];
  v_fila  uuid;
  v_agora timestamptz;
  v_n     integer := 0;
begin
  begin
    v_ids := array(select jsonb_array_elements_text(coalesce(p->'ids', '[]'::jsonb))::uuid);
    v_fila := nullif(p->>'fila_id', '')::uuid;
    v_agora := coalesce(nullif(p->>'agora', '')::timestamptz, now());
  exception when others then
    return jsonb_build_object('ok', false, 'erro', 'ids, fila_id ou agora inválido');
  end;
  if v_phone is null or v_modo not in ('sombra', 'ligado') then
    return jsonb_build_object('ok', false, 'erro', 'faltam phone ou modo');
  end if;
  if v_modo = 'ligado' and v_fila is null then
    return jsonb_build_object('ok', false, 'erro', 'no modo ligado a mensagem precisa do id da fila');
  end if;
  if v_fila is null then
    -- sombra: a mensagem-sombra não sai; o que ela levaria conta como entregue nela
    update public.avisos_do_dono a
       set situacao = 'entregue', incluido_em = v_agora, entregue_em = v_agora, atualizado_em = now()
     where a.phone_normalized = v_phone and a.modo = v_modo and a.situacao = 'guardado' and a.id = any (v_ids);
  else
    update public.avisos_do_dono a
       set situacao = 'incluido', fila_id = v_fila, incluido_em = v_agora, atualizado_em = now()
     where a.phone_normalized = v_phone and a.modo = v_modo and a.situacao = 'guardado' and a.id = any (v_ids);
  end if;
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'incluidos', v_n);
end $$;

comment on function public.avisos_incluir_na_mensagem(jsonb) is
  'Secretário (uma voz só): a mensagem fixa levou estes guardados (com o id da fila; sem fila só na sombra, que conta como entregue). Só service_role.';

-- p = {phone, modo, ids: [uuid…], motivo?}: D8 — o guardado que deixou de ser verdade some
create or replace function public.aviso_resolver(p jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_phone  text := p->>'phone';
  v_modo   text := coalesce(nullif(p->>'modo', ''), 'sombra');
  v_ids    uuid[];
  v_motivo text := coalesce(nullif(p->>'motivo', ''), 'ja_resolvido');
  v_n      integer := 0;
begin
  begin
    v_ids := array(select jsonb_array_elements_text(coalesce(p->'ids', '[]'::jsonb))::uuid);
  exception when others then
    return jsonb_build_object('ok', false, 'erro', 'ids inválido');
  end;
  if v_motivo !~ '^[a-z][a-z_]{1,59}$' then
    v_motivo := 'ja_resolvido';
  end if;
  update public.avisos_do_dono a
     set situacao = 'resolvido', motivo = v_motivo, atualizado_em = now()
   where a.phone_normalized = v_phone and a.modo = v_modo and a.situacao = 'guardado' and a.id = any (v_ids);
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'resolvidos', v_n);
end $$;

comment on function public.aviso_resolver(jsonb) is
  'Secretário (uma voz só): o aviso guardado deixou de ser verdade antes da mensagem fixa (cliente respondido, nota reemitida) → resolvido; não aparece. Só service_role.';

revoke all on function public._aviso_proxima_mensagem(timestamptz, text, text) from public, anon, authenticated;
revoke all on function public.aviso_registrar(jsonb) from public, anon, authenticated;
revoke all on function public.aviso_reabrir(jsonb) from public, anon, authenticated;
revoke all on function public.avisos_para_a_mensagem(jsonb) from public, anon, authenticated;
revoke all on function public.avisos_incluir_na_mensagem(jsonb) from public, anon, authenticated;
revoke all on function public.aviso_resolver(jsonb) from public, anon, authenticated;
grant execute on function public._aviso_proxima_mensagem(timestamptz, text, text) to service_role;
grant execute on function public.aviso_registrar(jsonb) to service_role;
grant execute on function public.aviso_reabrir(jsonb) to service_role;
grant execute on function public.avisos_para_a_mensagem(jsonb) to service_role;
grant execute on function public.avisos_incluir_na_mensagem(jsonb) to service_role;
grant execute on function public.aviso_resolver(jsonb) to service_role;

-- ---------------------------------------------------------------------------------------------
-- 7. GRAVA DADO — OK NOMEADO: as três chaves. voz_unica nasce 'desligado'; o freio nasce 'ligado'.
--    Três fontes do mesmo padrão: estas linhas, _shared/uma-voz/portao.ts (voz_unica ausente ou inválida =
--    desligado; regras ausentes ou ruins = REGRAS_PADRAO; freio ausente = desligado, para o código publicado
--    antes desta migration não mudar nada) e a ausência das chaves.
-- ---------------------------------------------------------------------------------------------
insert into public.app_settings (key, value, description) values
  ('voz_unica', 'desligado',
   'Uma voz só (secretário, Passo 4): desligado = as fontes avisam o dono como sempre; sombra = avisam como sempre E registram em avisos_do_dono o que o portão faria (acordar, guardar, deixar), para comparar; ligado = o portão decide (até o P4.5 ainda age como sombra). Voltar atrás = desligado.'),
  ('voz_unica_regras',
   '{"acordes_por_dia":2,"email_sem_golpe":"proxima_fixa","desistencia_acorda_com_orcamento_de":5000,"acompanhar_conta_no_limite":true,"promessa":"proxima_fixa","lead_site":"proxima_fixa","sabado":"domingo","guardado_resolvido":"some","telefone_no_aviso":true,"verificacao_min":15,"freio_avisos":2}',
   'Respostas-padrão das decisões abertas do dono para a voz única (D1–D10 da spec): acordes por dia, e-mail urgente sem golpe, desistência com orçamento de pelo menos R$ X, acompanhamento conta no limite, promessa, lead do site, excesso de sábado, guardado resolvido, telefone no aviso, minutos da verificação, avisos do freio. Trocar um valor muda a regra sem publicar código.'),
  ('acompanhar_freio', 'ligado',
   'Freio do acompanhamento (Passo 4, P4.3): ligado = no máximo 2 avisos sobre a mesma mensagem do contato; o aviso volta quando ele escreve de novo. desligado = como antes (a cada intervalo, até 3 por dia).')
on conflict (key) do nothing;

-- Igual ao do Passo 3 (20261015210000, commit e52ee042), com as três chaves novas no fim.
create or replace function public._app_settings_chaves_do_dono()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is not null and not public.is_admin(v_uid) then
    if (tg_op <> 'INSERT' and old.key in ('salario_minimo', 'pro_labore_pelo_salario_minimo'))
       or (tg_op <> 'DELETE' and new.key in ('salario_minimo', 'pro_labore_pelo_salario_minimo')) then
      raise exception 'Só o administrador muda o salário mínimo e a regra do pró-labore.' using errcode = '42501';
    end if;
    if (tg_op <> 'INSERT' and old.key = 'comprovante_fluxo')
       or (tg_op <> 'DELETE' and new.key = 'comprovante_fluxo') then
      raise exception 'Só o administrador liga ou desliga o fluxo de comprovantes.' using errcode = '42501';
    end if;
    if (tg_op <> 'INSERT' and old.key = 'comprovante_conversa')
       or (tg_op <> 'DELETE' and new.key = 'comprovante_conversa') then
      raise exception 'Só o administrador liga ou desliga a conversa dos comprovantes.' using errcode = '42501';
    end if;
    if (tg_op <> 'INSERT' and old.key = 'resumo_formato')
       or (tg_op <> 'DELETE' and new.key = 'resumo_formato') then
      raise exception 'Só o administrador muda o formato do resumo da manhã.' using errcode = '42501';
    end if;
    if (tg_op <> 'INSERT' and old.key = 'fechamento_formato')
       or (tg_op <> 'DELETE' and new.key = 'fechamento_formato') then
      raise exception 'Só o administrador liga ou desliga o fechamento da tarde.' using errcode = '42501';
    end if;
    if (tg_op <> 'INSERT' and old.key in ('voz_unica', 'voz_unica_regras'))
       or (tg_op <> 'DELETE' and new.key in ('voz_unica', 'voz_unica_regras')) then
      raise exception 'Só o administrador liga a voz única do secretário ou muda as regras dela.' using errcode = '42501';
    end if;
    if (tg_op <> 'INSERT' and old.key = 'acompanhar_freio')
       or (tg_op <> 'DELETE' and new.key = 'acompanhar_freio') then
      raise exception 'Só o administrador liga ou desliga o freio do acompanhamento.' using errcode = '42501';
    end if;
  end if;
  return coalesce(new, old);
end $$;

drop trigger if exists app_settings_chaves_do_dono on public.app_settings;
create trigger app_settings_chaves_do_dono
  before insert or update or delete on public.app_settings
  for each row execute function public._app_settings_chaves_do_dono();

revoke all on function public._app_settings_chaves_do_dono() from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- Prova: a migration falha se alguma porta ficou aberta.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_t text := 'public.avisos_do_dono';
  v_f text;
  v_rpcs text[] := array['public.aviso_registrar(jsonb)', 'public.aviso_reabrir(jsonb)', 'public.avisos_para_a_mensagem(jsonb)',
                         'public.avisos_incluir_na_mensagem(jsonb)', 'public.aviso_resolver(jsonb)',
                         'public._aviso_proxima_mensagem(timestamp with time zone, text, text)'];
  v_def text;
begin
  if not (select relrowsecurity from pg_class where oid = v_t::regclass) then
    raise exception 'RLS desligada em %', v_t;
  end if;
  if has_table_privilege('anon', v_t, 'select') or has_table_privilege('anon', v_t, 'insert')
     or has_table_privilege('anon', v_t, 'update') or has_table_privilege('anon', v_t, 'delete') then
    raise exception 'anon ainda alcança %', v_t;
  end if;
  if has_table_privilege('authenticated', v_t, 'insert') or has_table_privilege('authenticated', v_t, 'update')
     or has_table_privilege('authenticated', v_t, 'delete') then
    raise exception 'authenticated escreve direto em %', v_t;
  end if;
  if not has_table_privilege('service_role', v_t, 'select') or not has_table_privilege('service_role', v_t, 'insert')
     or not has_table_privilege('service_role', v_t, 'update') then
    raise exception 'service_role não alcança %', v_t;
  end if;
  -- policies: só a prevista, só TO authenticated, só SELECT, só admin
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'avisos_do_dono') <> 1
     or exists (select 1 from pg_policies
                 where schemaname = 'public' and tablename = 'avisos_do_dono'
                   and (roles <> array['authenticated']::name[] or cmd <> 'SELECT'
                        or policyname <> 'avisos_do_dono_admin_le' or position('is_admin' in qual) = 0)) then
    raise exception 'policies de avisos_do_dono diferentes das previstas (ou alcançando anon/public)';
  end if;
  foreach v_f in array v_rpcs loop
    if has_function_privilege('anon', v_f, 'execute') then
      raise exception 'função do portão exposta para anon: %', v_f;
    end if;
    if has_function_privilege('authenticated', v_f, 'execute') then
      raise exception 'função do portão exposta para authenticated: %', v_f;
    end if;
    if not has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'a edge (service_role) não alcança %', v_f;
    end if;
  end loop;
  if not exists (select 1 from pg_constraint where conname = 'avisos_do_dono_chave_unica'
                    and conrelid = 'public.avisos_do_dono'::regclass and contype = 'u') then
    raise exception 'a chave única (telefone, modo, chave) do portão está ausente';
  end if;
  if (select count(*) from public.app_settings where key in ('voz_unica', 'voz_unica_regras', 'acompanhar_freio')) <> 3 then
    raise exception 'as chaves voz_unica, voz_unica_regras e acompanhar_freio não foram criadas';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'app_settings_chaves_do_dono'
                    and tgrelid = 'public.app_settings'::regclass and tgenabled <> 'D') then
    raise exception 'gatilho app_settings_chaves_do_dono ausente: o financeiro ligaria a voz única';
  end if;
  v_def := pg_get_functiondef('public._app_settings_chaves_do_dono()'::regprocedure);
  if position('voz_unica_regras' in v_def) = 0 or position('acompanhar_freio' in v_def) = 0
     or position('fechamento_formato' in v_def) = 0 or position('resumo_formato' in v_def) = 0
     or position('comprovante_conversa' in v_def) = 0 or position('comprovante_fluxo' in v_def) = 0
     or position('pro_labore_pelo_salario_minimo' in v_def) = 0 then
    raise exception 'o gatilho das chaves do dono não protege todas as chaves (voz única, freio, fechamento, resumo, comprovantes, pró-labore)';
  end if;
  if has_function_privilege('anon', 'public._app_settings_chaves_do_dono()', 'execute')
     or has_function_privilege('authenticated', 'public._app_settings_chaves_do_dono()', 'execute') then
    raise exception 'gatilho das chaves do dono exposto';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261016101000', 'avisos_do_dono')
on conflict do nothing;
