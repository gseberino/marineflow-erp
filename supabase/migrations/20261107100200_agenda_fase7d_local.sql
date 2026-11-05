-- Agenda de Produção, Fase 7, etapa 7d ("onde, quando e com o bem em que estado"), pacote P3: as leituras do local, da viagem e do bem.
-- Spec: scratchpad agenda-pesquisa/spec-fase7d.md (§3.1 itens 3 a 10, §5.3, §8.3 agenda_fase7d_local.sql, R6.5, R6.7b, R6.8); nomes:
-- fase7-registro.md §1 (7d P3); respostas do dono: fase7-padroes.md (AG7-14, AG7-18, AG7-19, AG7-20 e o conflito 6).
-- Depende de 20261107100000 (agenda_locais, os_autorizados, as colunas de os_planejamento, os parâmetros, _agenda_local_conferido),
-- 20261107100100 (agenda_feriado_municipal), 20261029100100 (_agenda_classe_de_campo), 20261027100100 (_agenda_lugar_casa),
-- 20261028100000 (agenda_cliente_mensagens) e 20261024160100 (_agenda_cfg, _agenda_normal, _agenda_lista, _agenda_nome_curto).
--
-- ═══ DDL — OK NOMEADO ═══ (8 funções novas, leituras invoker; nenhuma tabela, nenhuma função recriada, nenhum dado)
-- NÃO APLICADA. Existe para revisão e espera o OK.
--
-- POR QUE: o motor, o "combinar" e a ficha precisam saber onde é o serviço, se é viagem, como está o bem e o que o local não aceita. Hoje
-- esse saber não existe num lugar só: a ficha lê a marina da OS (ou do bem) e a cidade do cliente; 8 das 11 OS da carteira não têm lugar
-- nenhum (NOVO-agenda-65). Estas leituras são o lugar único. Elas só leem e NINGUÉM as chama neste pacote: quem chama é o motor (P4, com
-- o modo ligado), o "combinar" (P5), o M11 (P6) e as leituras ao dono (P8).
--
-- O QUE MUDA (8 funções novas; nenhuma existia):
--   1. _agenda_local_no(nome): "na Marina Itajaí", "na MP Motorhomes", "no Pátio da HBR". A preposição do R6.5, num lugar só.
--   2. _agenda_viagem_por_municipio(município, UF): a classe da viagem pelo lugar (a regra do município da §3.1, item 4), usada pelo
--      cadastro e pela cidade do cliente.
--   3. _agenda_local_resolvido(os, hoje): a cadeia do local, com os 3 textos (§3.1, item 3).
--   4. _agenda_local_deslocamento(local): o tempo de ida e a classe, do cadastro, das coordenadas ou do município (§3.1, item 4).
--   5. _agenda_viagem_da_os(os, hoje, local): a cadeia da viagem e o que ela custa (§3.1, itens 4 e 5).
--   6. _agenda_estado_do_bem(os, hoje): onde o bem está e o que o serviço exige dele (§3.1, item 10).
--   7. _agenda_local_mascara(os, dia inicial, dia final, hoje, local): os dias e os meios-dias que o local não recebe (§3.1, item 6). Não
--      lê modo nenhum da 7d: quem chama decide (R6.8).
--   8. _agenda_autorizacao_da_os(os, hoje, local): quem está autorizado, só como leitura (§3.1, item 7; AG7-14: nunca filtro de pessoa).
--
-- O QUE NÃO MUDA: _agenda_local_da_os e _agenda_bem_da_os (a ficha de hoje, byte a byte; quem passa _agenda_local_da_os a ler o texto_equipe é
-- o P8); _agenda_nome_curto, _agenda_cliente_dia, _agenda_chave_telefone, agenda_dia_util, agenda_somar_du e agenda_feriado (a sessão do
-- retorno chama; nem assinatura nem sentido). Nenhuma mensagem, nenhuma escrita, nada no caminho da vigia em sombra (R6.8): com a migration
-- aplicada, o motor, a vigia, o secretário e os textos ficam byte a byte.
--
-- DESVIOS DA SPEC (a menor escolha segura; provados em agenda_fase7d_local.sql, e o porquê em notas-fase7d.md):
--   · R6.5, a preposição: "no" só com nome começando por "Pátio"; a spec dizia "pela regra do tipo".
--   · A marina da OS sem local no cadastro, com o barco cadastrado noutra (L1j): a cadeia cai no local do barco, mas isso é suposição e o
--     texto_equipe fica nulo. Sem isto, a ficha do P8 mandaria o técnico à marina do barco, enquanto a OS diz outra.
--   · As palavras do bem só valem para barco (L4a): a linha real "Substituição da hélice do exaustor da claraboia", de um motorhome, casaria
--     a palavra "helice" e pediria o motorhome em seco.
--   · O retirada_em não entra em `dias`: entra em `sai`, porque o P4 só o aplica com modo_patio ligado (§5.4, passo 1). `ent` e `sai` são
--     presos em 1 quando a data vem antes da janela: 0 quer dizer "não há data".
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7d_local.sql. Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261107100200
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261107100200_agenda_fase7d_local.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261107100200', 'agenda_fase7d_local');"
--
-- DESFAZER (só antes do P4, que passa a chamar):
--   drop function if exists public._agenda_autorizacao_da_os(uuid, date, jsonb), public._agenda_local_mascara(uuid, date, date, date, jsonb),
--     public._agenda_estado_do_bem(uuid, date), public._agenda_viagem_da_os(uuid, date, jsonb), public._agenda_local_deslocamento(uuid),
--     public._agenda_local_resolvido(uuid, date), public._agenda_viagem_por_municipio(text, text), public._agenda_local_no(text);
--
-- IDEMPOTENTE: create or replace function, comment e revoke/grant repetidos não mudam nada.

-- ── 1. A preposição (R6.5) ──────────────────────────────────────────────────────────────────────────
-- "no" só quando o nome começa pela palavra Pátio: a ficha de hoje diz "na MP Motorhomes" e não pode mudar em teste.
create or replace function public._agenda_local_no(p_nome text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case when public._agenda_normal(normalize(p_nome, nfc)) ~ '^patio\M' then 'no ' else 'na ' end || btrim(p_nome);
$function$;

comment on function public._agenda_local_no(text) is
  'Agenda de Produção (Fase 7d, P3; R6.5): o local com a preposição — "no" só quando o nome começa pela palavra Pátio; senão "na". A ficha de hoje diz "na MP Motorhomes", e esse texto não pode mudar.';

-- ── 2. A classe da viagem pelo lugar ────────────────────────────────────────────────────────────────
-- A regra do município (§3.1, item 4): na região = regional; a UF do bate-volta = ida e volta; outra UF = pernoite. Sem UF e fora da região
-- não há como dizer: null, e quem chama segue a cadeia.
create or replace function public._agenda_viagem_por_municipio(p_municipio text, p_uf text)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c    public.agenda_config := public._agenda_cfg();
  v_uf text := upper(btrim(coalesce(p_uf, '')));
begin
  -- O nfc vem antes: _agenda_lugar_casa, como _agenda_normal, não reconhece o acento decomposto (notas do P2).
  if exists (select 1 from unnest(c.municipios_locais) m where public._agenda_lugar_casa(normalize(p_municipio, nfc), m)) then
    return 'regional';
  end if;
  if v_uf !~ '^[A-Z]{2}$' then
    return null;
  end if;
  return case when v_uf = any (c.viagem_uf_bate_volta) then 'bate_volta' else 'pernoite' end;
end;
$function$;

comment on function public._agenda_viagem_por_municipio(text, text) is
  'Agenda de Produção (Fase 7d, P3; AG7-19): a classe da viagem pelo lugar — regional (o município casa agenda_config.municipios_locais, tolerante ao caractere quebrado), bate_volta (a UF está em viagem_uf_bate_volta), pernoite (outra UF), null (fora da região e sem UF).';

-- ── 3. A cadeia do local (§3.1, item 3) ─────────────────────────────────────────────────────────────
create or replace function public._agenda_local_resolvido(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_so     record;
  l        public.agenda_locais;
  v_fonte  text;
  v_classe text;
  v_cid    text;
  v_mun    text;
  v_uf     text;
  v_sup    boolean;
  v_bem    text;
  v_outra  text;
  v_nota   text;
  v_onde   text;
  v_por    text;
  v_texto  text;
  v_curto  text;
begin
  select so.marina_id, vs.marina_id as marina_do_bem, pl.local_id, pl.local_fonte, cl.city, cl.state
    into v_so
    from public.service_orders so
    left join public.vessels vs on vs.id = so.vessel_id
    left join public.clients cl on cl.id = so.client_id
    left join public.os_planejamento pl on pl.service_order_id = so.id
   where so.id = p_os;
  if not found then
    return null;
  end if;

  -- 1. o que o dono ou o cliente disse
  if v_so.local_id is not null then
    select * into l from public.agenda_locais x where x.id = v_so.local_id and x.ativo;
    if found then v_fonte := v_so.local_fonte; end if;
  end if;
  -- 2. a marina da OS
  if v_fonte is null and v_so.marina_id is not null then
    select * into l from public.agenda_locais x where x.marina_id = v_so.marina_id and x.ativo;
    if found then v_fonte := 'os'; end if;
  end if;
  -- 3. a marina do bem
  if v_fonte is null and v_so.marina_do_bem is not null then
    select * into l from public.agenda_locais x where x.marina_id = v_so.marina_do_bem and x.ativo;
    if found then v_fonte := 'bem'; end if;
  end if;
  -- 4. motorhome, camper, trailer: o pátio, suposição
  if v_fonte is null then
    v_classe := public._agenda_classe_de_campo(p_os) ->> 'bem';
    if v_classe = 'rv' then
      select * into l from public.agenda_locais x where x.tipo = 'patio_hbr' and x.ativo;
      if found then v_fonte := 'patio'; end if;
    end if;
  end if;
  -- 5. a cidade do cliente, suposição, sem local; a cidade com o caractere quebrado não serve
  if v_fonte is null then
    v_cid := nullif(btrim(coalesce(v_so.city, '')), '');
    if v_cid is not null and position(chr(65533) in v_cid) = 0 then
      v_mun := public._agenda_normal(normalize(v_cid, nfc));
      if v_mun <> '' then
        v_fonte := 'cidade';
        v_uf := nullif(upper(btrim(coalesce(v_so.state, ''))), '');
        v_uf := case when v_uf ~ '^[A-Z]{2}$' then v_uf end;
      end if;
    end if;
  end if;
  -- 6. nada
  v_fonte := coalesce(v_fonte, 'nenhum');

  -- A OS diz uma marina que não virou local: a ficha de hoje diz o nome dela, e o texto_equipe não pode dizer outro lugar.
  v_sup := v_fonte in ('patio', 'cidade');
  if v_so.marina_id is not null and v_fonte in ('bem', 'patio', 'cidade', 'nenhum') then
    select nullif(btrim(m.name), '') into v_outra from public.marinas m where m.id = v_so.marina_id;
    v_sup := v_sup or v_fonte = 'bem';
  end if;

  -- O barco cadastrado noutro lugar (NOVO-agenda-63), ou a marina da OS fora do cadastro de locais. A palavra do bem só quando vai ser lida.
  if v_fonte = 'bem' or (v_outra is null and v_so.marina_do_bem is distinct from l.marina_id and v_so.marina_do_bem is not null) then
    v_classe := coalesce(v_classe, public._agenda_classe_de_campo(p_os) ->> 'bem');
    v_bem := case v_classe when 'rv' then 'motorhome' when 'barco' then 'barco' else 'bem' end;
  end if;
  if v_outra is not null then
    v_nota := format('a OS diz %s, que não está no cadastro de locais', v_outra);
  elsif v_so.marina_do_bem is not null and v_so.marina_do_bem is distinct from l.marina_id then
    select format('o %s está cadastrado %s', v_bem, public._agenda_local_no(m.name)) into v_nota
      from public.marinas m where m.id = v_so.marina_do_bem;
  end if;

  if v_fonte = 'cidade' then
    v_curto := 'em ' || v_cid;
    v_texto := v_curto || ' (suposição: pela cidade do cliente)';
  elsif v_fonte = 'nenhum' then
    v_texto := 'não sei onde é o serviço';
  else
    v_curto := public._agenda_local_no(l.nome);
    if v_fonte = 'patio' then
      v_texto := l.nome || ' (suposição: motorhome vem ao pátio)';
    else
      -- "Marina Itajaí (pela OS)": o município só quando o nome não o diz.
      v_onde := l.nome || case when strpos(' ' || public._agenda_normal(normalize(l.nome, nfc)) || ' ',
                                           ' ' || public._agenda_normal(normalize(l.municipio, nfc)) || ' ') > 0
                               then '' else ', em ' || l.municipio end;
      v_por := case v_fonte when 'dono' then 'você disse' when 'cliente' then 'o cliente disse' when 'os' then 'pela OS'
                            else 'pelo cadastro do ' || v_bem end;
      if v_sup then
        v_texto := format('%s (suposição: %s)', v_onde, v_por);
      elsif l.uf is not null and l.uf <> all ((public._agenda_cfg()).viagem_uf_bate_volta) then
        v_texto := format('%s (%s)', v_onde, l.uf);   -- "Iate Clube Caiobá, em Guaratuba (PR)": o estado no lugar da fonte (§6.2)
      else
        v_texto := format('%s (%s)', v_onde, v_por);
      end if;
    end if;
  end if;

  return jsonb_build_object(
    'local_id', l.id, 'nome', l.nome, 'tipo', l.tipo,
    'municipio', coalesce(l.municipio, v_cid), 'uf', coalesce(l.uf, v_uf),
    'fonte', v_fonte, 'suposicao', v_sup,
    'chave', case when l.id is not null then 'l:' || l.id::text when v_fonte = 'cidade' then 'c:' || v_mun end,
    'conferido', public._agenda_local_conferido(l.id, p_hoje),
    'nota_bem', v_nota, 'texto', v_texto, 'texto_curto', v_curto,
    'texto_equipe', case when v_fonte in ('dono', 'cliente', 'os', 'bem') and not v_sup then v_curto end);
end;
$function$;

comment on function public._agenda_local_resolvido(uuid, date) is
  'Agenda de Produção (Fase 7d, P3; §3.1, item 3): onde é o serviço — dono/cliente (os_planejamento.local_id) → a marina da OS → a marina do bem → rv = o pátio da HBR (suposição) → a cidade do cliente (suposição, sem local) → nenhum. Local inativo não entra. {local_id, nome, tipo, municipio, uf, fonte, suposicao, chave, conferido, nota_bem, texto, texto_curto, texto_equipe}. texto_equipe só quando a fonte é dono, cliente, os ou bem e não há suposição: é o que a ficha lê (P8). A OS que não existe: null. STABLE, invoker: agenda_locais sob a RLS; o técnico, sem agenda_config, recebe o P0002 de _agenda_cfg (a leitura lança, não vira "não sei").';

-- ── 4. O deslocamento (§3.1, item 4) ────────────────────────────────────────────────────────────────
create or replace function public._agenda_local_deslocamento(p_local uuid)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  l        public.agenda_locais;
  v_b_lat  text;
  v_b_lng  text;
  v_a      double precision;
  v_ida    int;
  v_fonte  text := 'nenhum';
  v_viagem text;
begin
  select * into l from public.agenda_locais x where x.id = p_local and x.ativo;
  if not found then
    return jsonb_build_object('ida_min', null, 'fonte', 'nenhum', 'viagem', null, 'texto', 'Não sei o deslocamento até lá.');
  end if;

  if l.deslocamento_min is not null then
    v_ida := l.deslocamento_min;
    v_fonte := 'dito';
  elsif l.latitude is not null then
    -- A base do deslocamento é a dos orçamentos: valor fora de número vale "sem base", e o município decide.
    select btrim(max(s.value) filter (where s.key = 'travel_base_lat')), btrim(max(s.value) filter (where s.key = 'travel_base_lng'))
      into v_b_lat, v_b_lng
      from public.app_settings s where s.key in ('travel_base_lat', 'travel_base_lng');
    if v_b_lat ~ '^-?\d+(\.\d+)?$' and v_b_lng ~ '^-?\d+(\.\d+)?$' then
      -- Haversine, raio 6371 km; × fator de estrada ÷ km/h × 60, para cima.
      v_a := sin(radians(l.latitude - v_b_lat::numeric) / 2) ^ 2
             + cos(radians(v_b_lat::numeric)) * cos(radians(l.latitude)) * sin(radians(l.longitude - v_b_lng::numeric) / 2) ^ 2;
      v_ida := ceil(2 * 6371 * asin(sqrt(v_a)) * c.deslocamento_fator_estrada::double precision / c.deslocamento_kmh * 60)::int;
      v_fonte := 'coordenadas';
    end if;
  end if;

  if v_ida is not null then
    v_viagem := case when v_ida <= c.deslocamento_regional_max_min then 'regional'
                     when v_ida <= c.deslocamento_bate_volta_max_min then 'bate_volta'
                     else 'pernoite' end;
  else
    v_viagem := public._agenda_viagem_por_municipio(l.municipio, l.uf);
    if v_viagem is not null then
      v_fonte := 'municipio';
    end if;
  end if;

  -- A viagem dita no cadastro vale sobre o tempo.
  if l.viagem is not null then
    v_viagem := l.viagem;
    v_fonte := 'dito';
  end if;

  return jsonb_build_object('ida_min', v_ida, 'fonte', v_fonte, 'viagem', v_viagem,
    'texto', case when v_fonte = 'nenhum' then 'Não sei o deslocamento até lá.'
                  when v_ida is null then 'Sem o tempo de ida: conto pelo município.'
                  when v_fonte = 'coordenadas' then format('A ida leva cerca de %s min (pelas coordenadas).', v_ida)
                  else format('A ida leva %s min.', v_ida) end);
end;
$function$;

comment on function public._agenda_local_deslocamento(uuid) is
  'Agenda de Produção (Fase 7d, P3; §3.1, item 4; AG7-19): {ida_min, fonte, viagem, texto} do local. Tempo dito no cadastro (deslocamento_min) → pelas coordenadas (haversine da base travel_base_lat/lng × deslocamento_fator_estrada ÷ deslocamento_kmh, para cima) → a classe pelo município, sem tempo. viagem dita no cadastro vale sobre o tempo (fonte dito). Sem nada, ou local que não existe: fonte nenhum e viagem null (não sei não é regional). STABLE, invoker.';

-- ── 5. A viagem da OS (§3.1, itens 4 e 5) ───────────────────────────────────────────────────────────
-- travel_distance_km é o total cobrado, não a distância (812 = 4 × 203, NOVO-agenda-64): só no fim da cadeia, nunca vira ida_min nem texto de
-- distância, e o texto diz que pode somar várias idas.
create or replace function public._agenda_viagem_da_os(p_os uuid, p_hoje date, p_local jsonb default null)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_l      jsonb := coalesce(p_local, public._agenda_local_resolvido(p_os, p_hoje));
  v_id     uuid := (v_l ->> 'local_id')::uuid;
  v_so     record;
  v_d      jsonb;
  v_cad    text;
  v_tipo   text;
  v_fonte  text;
  v_sup    boolean := true;
  v_por    text;
  v_ida    int;
  v_km     numeric;
  v_extra  int;
  v_tec    int;
  v_texto  text;
begin
  select pl.viagem, so.travel_distance_km, so.technician_count_for_travel
    into v_so
    from public.service_orders so
    left join public.os_planejamento pl on pl.service_order_id = so.id
   where so.id = p_os;
  if not found or v_l is null then
    return null;
  end if;
  v_km := coalesce(v_so.travel_distance_km, 0);
  v_tec := v_so.technician_count_for_travel;

  if v_id is not null then
    v_d := public._agenda_local_deslocamento(v_id);
    v_ida := (v_d ->> 'ida_min')::int;
    select x.viagem into v_cad from public.agenda_locais x where x.id = v_id;
  end if;

  if v_so.viagem is not null then
    v_tipo := v_so.viagem;
    v_fonte := 'dono';
    v_sup := false;
  elsif v_cad is not null then
    v_tipo := v_cad;
    v_fonte := 'local';
    v_sup := false;
  elsif v_d ->> 'fonte' = 'dito' then
    v_tipo := v_d ->> 'viagem';
    v_fonte := 'local';
    v_por := format('%s min de estrada', v_ida);
  elsif v_d ->> 'fonte' = 'coordenadas' then
    v_tipo := v_d ->> 'viagem';
    v_fonte := 'coordenadas';
    v_por := format('cerca de %s min de estrada', v_ida);
  else
    -- O município do local ou, sem local, o da cidade do cliente.
    v_tipo := coalesce(v_d ->> 'viagem', public._agenda_viagem_por_municipio(v_l ->> 'municipio', v_l ->> 'uf'));
    if v_tipo is not null then
      v_fonte := 'municipio';
      v_por := case v_tipo when 'pernoite' then 'outro estado' else 'fora da região' end;
    elsif v_km >= c.viagem_km_pernoite then
      v_tipo := 'pernoite';
      v_fonte := 'km';
    elsif v_km >= c.viagem_km_bate_volta then
      v_tipo := 'bate_volta';
      v_fonte := 'km';
    else
      v_tipo := 'regional';
      v_fonte := 'padrao';
    end if;
    if v_fonte = 'km' then
      v_por := 'pelo km cobrado na OS, que pode somar várias idas';
    end if;
  end if;

  v_extra := case v_tipo when 'bate_volta' then c.bate_volta_meios_dia when 'pernoite' then 2 * c.pernoite_ida_meios else 0 end;

  v_texto := case v_tipo
    when 'regional' then 'Sem viagem (aqui na região).'
    when 'bate_volta' then
      'Viagem de ida e volta no mesmo dia' || coalesce(' (suposição: ' || v_por || ')', '') || ': '
      || case when c.bate_volta_meios_dia > 0 then 'cada dia rende meio dia de serviço.' else 'a estrada não tira meio-dia de serviço.' end
    else
      'Viagem com pernoite' || coalesce(' (suposição: ' || v_por || ')', '') || ': a equipe vai e volta junta, em dias seguidos; '
      || case c.pernoite_ida_meios when 0 then 'a ida e a volta não ocupam meio-dia.'
                                   when 1 then 'a ida e a volta ocupam 1 meio-dia cada.'
                                   else format('a ida e a volta ocupam %s meios-dias cada.', c.pernoite_ida_meios) end
    end;
  -- A dupla é do 7b: o técnico cobrado só explica (AG7-04).
  if v_tec > 1 then
    v_texto := v_texto || format(' O orçamento cobra deslocamento de %s técnicos.', v_tec);
  end if;

  return jsonb_build_object(
    'tipo', v_tipo, 'fonte', v_fonte, 'suposicao', v_sup, 'ida_min', v_ida, 'extra_por', v_extra,
    'imax_os', case when v_tipo = 'pernoite' then 0 end,
    'sem_abre_fecha', v_tipo <> 'regional',
    'tecnicos_cobrados', v_tec, 'texto', v_texto);
end;
$function$;

comment on function public._agenda_viagem_da_os(uuid, date, jsonb) is
  'Agenda de Produção (Fase 7d, P3; §3.1, itens 4 e 5; AG7-19): a viagem da OS — os_planejamento.viagem (dono) → agenda_locais.viagem (local) → o tempo dito (local) ou as coordenadas → o município do local ou da cidade do cliente → o km cobrado → regional (padrao). Da 3ª fonte em diante é suposição. {tipo, fonte, suposicao, ida_min, extra_por, imax_os, sem_abre_fecha, tecnicos_cobrados, texto}. travel_distance_km é o total cobrado, às vezes de várias idas: nunca vira ida_min. p_local = a saída de _agenda_local_resolvido (quem já tem não recalcula). A OS que não existe: null. STABLE, invoker.';

-- ── 6. O estado do bem (§3.1, item 10) ──────────────────────────────────────────────────────────────
create or replace function public._agenda_estado_do_bem(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_classe text := public._agenda_classe_de_campo(p_os) ->> 'bem';
  v_pl     record;
  v_l      jsonb;
  v_o_bem  text;
  v_sit    text;
  v_sit_f  text;
  v_exige  text;
  v_ex_f   text := 'padrao';
  v_linhas text;
  v_temp   boolean;
  v_sup    text[] := '{}';
  v_quem   text;
  v_parte  text;
  v_cab    text;
  v_datas  text;
  v_texto  text;
begin
  if v_classe is null then
    return null;
  end if;
  v_o_bem := case v_classe when 'rv' then 'motorhome' when 'barco' then 'barco' else 'bem' end;
  v_temp := extract(month from p_hoje)::smallint = any (c.temporada_meses);

  select pl.bem_situacao, pl.bem_situacao_fonte, pl.bem_exige, pl.descer_quem, pl.entrada_em, pl.retirada_em, pl.entrada_fonte,
         coalesce(not isempty(pl.bem_indisponivel), false) as tem_fora
    into v_pl
    from public.service_orders so
    left join public.os_planejamento pl on pl.service_order_id = so.id
   where so.id = p_os;

  v_l := public._agenda_local_resolvido(p_os, p_hoje);
  v_quem := nullif(btrim(coalesce(v_pl.descer_quem, '')), '');

  -- Onde ele está: o que foi dito → o pátio, pelo tipo do local → não sei.
  if v_pl.bem_situacao is not null then
    v_sit := v_pl.bem_situacao;
    v_sit_f := v_pl.bem_situacao_fonte;
  elsif v_l ->> 'tipo' like 'patio\_%' then
    v_sit := 'patio';
    v_sit_f := 'local';
  end if;
  if v_l ->> 'fonte' = 'patio' then
    v_sup := v_sup || format('supus o %s %s', v_o_bem, v_l ->> 'texto_curto');
  end if;

  -- O que o serviço exige: o que foi dito → a palavra da linha de serviço → tanto faz. As palavras só valem para barco: a linha real
  -- "Substituição da hélice do exaustor da claraboia", de um motorhome, casaria "helice".
  if v_pl.bem_exige is not null then
    v_exige := v_pl.bem_exige;
    v_ex_f := 'dono';
  else
    if v_classe = 'barco' then
      -- As 2 primeiras linhas (a ordem de _agenda_servico_curto) e a de maior valor (a de _agenda_classe_de_campo).
      select string_agg(public._agenda_normal(normalize(x.name_snapshot, nfc)), ' | ') into v_linhas
        from (select s.name_snapshot,
                     row_number() over (order by s.created_at, s.id) as pela_ordem,
                     row_number() over (order by s.line_total desc nulls last, s.created_at nulls last, s.id) as pelo_valor
                from public.service_order_services s
               where s.service_order_id = p_os) x
       where x.pela_ordem <= 2 or x.pelo_valor = 1;
      -- O teste final na água pesa mais: é ele que pede a descida (d9 da §3.3).
      if v_linhas ~ ('\m(' || c.bem_agua_palavras || ')\M') then
        v_exige := 'agua';
      elsif v_linhas ~ ('\m(' || c.bem_seco_palavras || ')\M') then
        v_exige := 'seco';
      end if;
    end if;
    if v_exige = 'agua' then
      v_ex_f := 'palavra';
      v_sup := v_sup || 'supus o teste final na água (pela linha de serviço)'::text;
    elsif v_exige = 'seco' then
      v_ex_f := 'palavra';
      v_sup := v_sup || 'supus o serviço com o barco em seco (pela linha de serviço)'::text;
    end if;
    v_exige := coalesce(v_exige, 'tanto_faz');
  end if;

  -- Na temporada, sem os dias de uso ditos, o barco está suposto livre. "Perguntei" só com o M11 que saiu de verdade.
  if v_classe = 'barco' and v_temp and not coalesce(v_pl.tem_fora, false) and v_sit is distinct from 'com_cliente' then
    v_sup := v_sup || case when exists (select 1 from public.agenda_cliente_mensagens m
                                         where m.service_order_id = p_os and m.tipo = 'onde_fica'
                                           and m.estado in ('enviada', 'respondida', 'sem_resposta'))
                           then 'supus o barco livre nos dias úteis (temporada: perguntei ao cliente os dias de uso)'
                           else 'supus o barco livre nos dias úteis (temporada: ainda não sei os dias de uso)' end;
  end if;

  -- O texto só diz o que foi dito ou o que o serviço pede; o que o local supõe sai no texto do local.
  v_cab := case when v_pl.bem_situacao is not null then
             case v_sit when 'agua' then 'na água' when 'seco' then 'em seco' when 'garagem_seca' then 'em seco (garagem)'
                        when 'patio' then 'no pátio' else 'com o cliente' end end;
  v_parte := case v_exige when 'agua' then 'o teste final é na água'
                          when 'seco' then format('o serviço é com o %s em seco', v_o_bem) end;
  v_datas := case when v_pl.entrada_em is not null and v_pl.retirada_em is not null
                    then format('O %s chega %s e sai %s.', v_o_bem, public._dia_curto(v_pl.entrada_em), public._dia_curto(v_pl.retirada_em))
                  when v_pl.entrada_em is not null then format('O %s chega %s.', v_o_bem, public._dia_curto(v_pl.entrada_em))
                  when v_pl.retirada_em is not null then format('O %s sai %s.', v_o_bem, public._dia_curto(v_pl.retirada_em)) end;
  if v_cab is not null then
    v_texto := format('O %s: %s', v_o_bem, v_cab) || coalesce(', quem desce: ' || v_quem, '') || coalesce('; ' || v_parte, '') || '.';
  elsif v_quem is not null then
    v_texto := 'Quem desce: ' || v_quem || coalesce('; ' || v_parte, '') || '.';
  elsif v_parte is not null then
    v_texto := upper(left(v_parte, 1)) || substr(v_parte, 2) || '.';
  end if;
  if v_datas is not null then
    v_texto := coalesce(v_texto || ' ', '') || v_datas;
  end if;

  return jsonb_build_object(
    'classe', v_classe, 'situacao', v_sit, 'situacao_fonte', v_sit_f, 'exige', v_exige, 'exige_fonte', v_ex_f,
    'descer_quem', v_quem, 'temporada', v_temp, 'entrada_em', v_pl.entrada_em, 'retirada_em', v_pl.retirada_em,
    'entrada_fonte', v_pl.entrada_fonte, 'suposicoes', to_jsonb(v_sup), 'texto', v_texto);
end;
$function$;

comment on function public._agenda_estado_do_bem(uuid, date) is
  'Agenda de Produção (Fase 7d, P3; §3.1, item 10; AG7-14, AG7-20): {classe, situacao, situacao_fonte, exige, exige_fonte, descer_quem, temporada, entrada_em, retirada_em, entrada_fonte, suposicoes[], texto}. situacao: a dita → patio pelo tipo do local (fonte local) → null. exige: o dito → a palavra (bem_agua_palavras, bem_seco_palavras, só em barco, nas 2 primeiras linhas de serviço e na de maior valor, com a água primeiro) → tanto_faz. Em uso pelo cliente é bem_indisponivel, que já existe. A OS que não existe: null. STABLE, invoker.';

-- ── 7. A máscara do local (§3.1, item 6) ────────────────────────────────────────────────────────────
-- Não lê os modos da 7d: quem chama decide (o motor só com o modo ligado; as leituras, sempre). modo_sabado é da 7b e aqui só diz se a HBR
-- trabalha no sábado. O calendário da HBR vale por cima: agenda_feriado não entra, porque o motor já não põe ninguém em 15/06.
create or replace function public._agenda_local_mascara(p_os uuid, p_d_ini date, p_d_fim date, p_hoje date, p_local jsonb default null)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_l      jsonb := coalesce(p_local, public._agenda_local_resolvido(p_os, p_hoje));
  l        public.agenda_locais;
  v_conf   boolean := coalesce((v_l ->> 'conferido')::boolean, false);
  v_mun    text := v_l ->> 'municipio';
  v_sab_7b boolean := c.sabado_manha <> 'nunca'
                      and (c.modo_sabado <> 'desligado' or coalesce(current_setting('agenda.sabado', true), '') = 'on');
  v_tol    interval := make_interval(mins => c.horario_tolerancia_min);
  v_ent_d  date;
  v_sai_d  date;
  v_dias   int[] := '{}';
  v_meios  int[] := '{}';
  v_mot    jsonb := '{}';
  v_notas  text[] := '{}';
  v_regras text[];
  v_fer    text;
  v_d      date;
  v_i      int;
  v_dow    int;
begin
  if v_l is null then
    return null;
  end if;
  if v_l ->> 'local_id' is not null then
    select * into l from public.agenda_locais x where x.id = (v_l ->> 'local_id')::uuid;
  end if;

  for v_i in 1 .. coalesce(p_d_fim - p_d_ini + 1, 0) loop
    v_d := p_d_ini + v_i - 1;
    v_dow := extract(isodow from v_d)::int;
    -- O feriado do município: fato público, vale sem conferir. Só o local conferido pode dizer que abre.
    v_fer := public.agenda_feriado_municipal(v_d, v_mun);
    if v_fer is not null and not (v_conf and l.feriado = 'abre') then
      v_dias := v_dias || v_i;
      v_mot := v_mot || jsonb_build_object(v_i::text,
        format('%s é feriado em %s (%s)', public._dia_curto(v_d), v_mun, regexp_replace(v_fer, '^aniversário de .*$', 'aniversário da cidade')));
      continue;
    end if;
    continue when not v_conf;
    if v_dow = 6 then
      -- O sábado do local só fecha o que a HBR abriu.
      if public.agenda_dia_util(v_d) or (v_sab_7b and public.agenda_feriado(v_d) is null) then
        if l.sabado = 'nao' then
          v_dias := v_dias || v_i;
          v_mot := v_mot || jsonb_build_object(v_i::text, format('%s: %s não abre no sábado', public._dia_curto(v_d), l.nome));
        elsif l.sabado = 'manha' then
          v_meios := v_meios || (2 * (v_i - 1) + 2);
        end if;
      end if;
    elsif v_dow < 6 and l.abre is not null then
      -- O horário de manutenção é de segunda a sexta (agenda_locais.abre).
      if l.abre > c.manha_inicio + v_tol or l.fecha < c.manha_fim - v_tol then
        v_meios := v_meios || (2 * (v_i - 1) + 1);
      end if;
      if l.abre > c.tarde_inicio + v_tol or l.fecha < c.tarde_fim - v_tol then
        v_meios := v_meios || (2 * (v_i - 1) + 2);
      end if;
    end if;
  end loop;

  -- A entrada e a retirada: índice preso em 1 (0 = não há data); depois do fim da janela o índice passa dela de propósito: o EST e os dias
  -- desde a retirada ficam certos. A retirada não entra em dias: o P4 só a aplica com modo_patio ligado.
  select pl.entrada_em, pl.retirada_em into v_ent_d, v_sai_d from public.os_planejamento pl where pl.service_order_id = p_os;

  -- As regras do cadastro que ainda não são regra: nota "a confirmar", no máximo 3.
  if l.id is not null and not v_conf then
    v_regras := array_remove(array[
      case when l.exige_autorizacao then 'pede ' || coalesce(nullif(btrim(l.autorizacao_texto), ''), 'autorização com o nome de quem vai') end,
      case when l.abre is not null then format('abre das %s às %s', to_char(l.abre, 'HH24:MI'), to_char(l.fecha, 'HH24:MI')) end,
      case l.sabado when 'nao' then 'não abre no sábado' when 'manha' then 'no sábado, só de manhã' when 'dia' then 'abre no sábado' end,
      case when l.seguro_exigido then 'pede ' || coalesce(nullif(btrim(l.seguro_texto), ''), 'seguro') end,
      nullif(btrim(coalesce(l.taxa_texto, '')), ''),
      case when l.tomada_max_w is not null then format('tomada até %s W', l.tomada_max_w) end,
      case when l.tem_garagem_seca then 'tem garagem seca' end], null);
    v_notas := array(select format('%s: %s (a confirmar com você).', l.nome, u.r)
                       from unnest(v_regras[1:3]) with ordinality u(r, o) order by u.o);
    if l.tipo = 'estaleiro' and cardinality(v_notas) < 3 then
      v_notas := v_notas || 'No estaleiro, combine com eles quando o barco fica livre para a elétrica.'::text;
    end if;
  end if;

  return jsonb_build_object('dias', to_jsonb(v_dias), 'meios', to_jsonb(v_meios), 'motivos', v_mot, 'notas', to_jsonb(v_notas),
    'ent', case when v_ent_d is null then 0 else greatest(v_ent_d - p_d_ini + 1, 1) end,   -- greatest ignora nulo: sem o case, 1 sem data
    'sai', case when v_sai_d is null then 0 else greatest(v_sai_d - p_d_ini + 1, 1) end);
end;
$function$;

comment on function public._agenda_local_mascara(uuid, date, date, date, jsonb) is
  'Agenda de Produção (Fase 7d, P3; §3.1, item 6): o que o local não recebe entre p_d_ini e p_d_fim. {dias int[] (1 = p_d_ini), meios int[] (2·(d−1)+1 manhã, +1 tarde), motivos {dia: texto}, notas[] (até 3, as regras não conferidas), ent, sai (o índice de entrada_em e de retirada_em, preso em 1; 0 = não há)}. O feriado do município fecha o dia, salvo local conferido com feriado = abre; sábado e horário só com o local conferido, e o sábado só quando a HBR trabalha nele. A retirada não entra em dias: é sai. Não lê os modos da 7d. p_local = a saída de _agenda_local_resolvido. A OS que não existe: null. STABLE, invoker.';

-- ── 8. A autorização, só leitura (§3.1, item 7; AG7-14) ─────────────────────────────────────────────
create or replace function public._agenda_autorizacao_da_os(p_os uuid, p_hoje date, p_local jsonb default null)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_l     jsonb := coalesce(p_local, public._agenda_local_resolvido(p_os, p_hoje));
  v_id    uuid := (v_l ->> 'local_id')::uuid;
  l       public.agenda_locais;
  v_conf  boolean := coalesce((v_l ->> 'conferido')::boolean, false);
  v_ids   uuid[];
  v_nomes text[];
  v_nota  text;
  v_texto text;
begin
  if v_l is null then
    return null;
  end if;
  if v_id is not null then
    select * into l from public.agenda_locais x where x.id = v_id;
  end if;

  -- Revogada, vencida ou de outro local não conta.
  select coalesce(array_agg(a.payee_id order by n.nome, a.payee_id), '{}'), coalesce(array_agg(n.nome order by n.nome, a.payee_id), '{}')
    into v_ids, v_nomes
    from public.os_autorizados a
    join public.payees p on p.id = a.payee_id
    cross join lateral (select public._agenda_nome_curto(p.name) as nome) n
   where a.service_order_id = p_os and a.revogado_em is null
     and (a.valido_ate is null or a.valido_ate >= p_hoje)
     and (a.local_id is null or a.local_id = v_id);

  if l.exige_autorizacao and not v_conf then
    v_nota := format('%s: pede %s (a confirmar com você).', l.nome,
                     coalesce(nullif(btrim(l.autorizacao_texto), ''), 'autorização com o nome de quem vai'));
  end if;

  v_texto := case when cardinality(v_nomes) > 0 then format('Autorizados nesse serviço: %s.', public._agenda_lista(v_nomes))
                  when l.id is null or (l.tipo = 'patio_hbr' and l.exige_autorizacao is null) then null   -- no pátio da HBR não há o que combinar
                  when l.exige_autorizacao then format('%s pede autorização com o nome de quem vai: ninguém anotado ainda.', l.nome)
                  when l.exige_autorizacao is null then format('Não sei se %s pede autorização com o nome de quem vai.', l.nome)
                  else format('%s não pede autorização com o nome de quem vai.', l.nome) end;

  return jsonb_build_object('exige', l.exige_autorizacao, 'conferido', v_conf, 'autorizados', to_jsonb(v_ids), 'nomes', to_jsonb(v_nomes),
                            'nota', v_nota, 'texto', v_texto);
end;
$function$;

comment on function public._agenda_autorizacao_da_os(uuid, date, jsonb) is
  'Agenda de Produção (Fase 7d, P3; §3.1, item 7; AG7-14): só leitura — {exige, conferido, autorizados uuid[], nomes[], nota, texto}. Nunca filtro de pessoa: o acesso é preparo da OS (o item acesso do P5). Conta quem está em os_autorizados sem revogar, dentro de valido_ate e do mesmo local (ou sem local). nota = a regra do local quando não conferida. STABLE, invoker.';

-- ── 9. As portas ────────────────────────────────────────────────────────────────────────────────────
-- Invoker: quem lê passa pela RLS de agenda_locais. Revoke de public E de anon (feedback_supabase_revoke_anon_function).
revoke all on function public._agenda_local_no(text), public._agenda_viagem_por_municipio(text, text),
                       public._agenda_local_resolvido(uuid, date), public._agenda_local_deslocamento(uuid),
                       public._agenda_viagem_da_os(uuid, date, jsonb), public._agenda_estado_do_bem(uuid, date),
                       public._agenda_local_mascara(uuid, date, date, date, jsonb), public._agenda_autorizacao_da_os(uuid, date, jsonb)
  from public, anon;
grant execute on function public._agenda_local_no(text), public._agenda_viagem_por_municipio(text, text),
                          public._agenda_local_resolvido(uuid, date), public._agenda_local_deslocamento(uuid),
                          public._agenda_viagem_da_os(uuid, date, jsonb), public._agenda_estado_do_bem(uuid, date),
                          public._agenda_local_mascara(uuid, date, date, date, jsonb), public._agenda_autorizacao_da_os(uuid, date, jsonb)
  to authenticated, service_role;
