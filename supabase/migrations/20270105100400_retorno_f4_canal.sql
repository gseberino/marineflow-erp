-- Retorno rápido ao cliente, F4 (P5): o canal e as saídas do parceiro.
-- Gerada por script (scripts/gerar_f4.cjs canal): as funções novas vêm de scripts/f4_sql/p5_canal.sql, escritas à mão;
-- _retorno_janela, canal_pode_enviar, retorno_pegar, retorno_saida_autorizada e retorno_registrar_decisao são geradas do
-- corpo vigente, e só os trechos marcados -- F4 são novos.
--
-- 1. parceiro_agendar: a única porta de entrada das saídas do parceiro (emissor 'parceiro'), à parceira (p_numero) ou ao
--    cliente final (p_fone_cliente), nunca os dois. Com o tipo em sombra, a chave ganha ':sombra' e a real fica livre.
-- 2. parceiro_pegar: a fila do parceiro, na ordem da tabela de P5.1 (número e pessoa; o aviso ainda vale; o dono
--    respondeu; pausa; segura pátio; tetos; bloco do pátio no recibo; a regra de ouro de novo, vínculo a vínculo; o eco
--    ouvido pelo cliente; o texto, linha a linha; o modo; segura tudo; o canal; a reserva). Com parceiro_modo
--    'desligado', cancela toda agendada do parceiro (parceiro_desligado) e devolve nulo.
-- 3. parceiro_saida_sem_linhas: tira do painel e do pátio as linhas que o validador reprovou (P5.2).
-- 4. parceiro_saida_autorizada: a última trava, no instante do envio (chamada por retorno_saida_autorizada).
-- 5. _parceiro_aplicar_efeitos: o aviso enviado nos vínculos do par, o painel enviado, a apresentação ao número e a
--    coleta_n do caso (chamada por retorno_registrar_decisao).
-- 6. Gerados: _retorno_janela (aviso e resumo_parceiro), canal_pode_enviar (a regra 2 e o teto das iniciadas),
--    retorno_pegar (não pega o emissor parceiro), retorno_saida_autorizada e retorno_registrar_decisao (o parceiro).
--
-- Com a F4 desligada (parceiro_modo = 'desligado', o padrão), nada muda para o cliente, o número novo e a F1–F3: as duas
-- classes novas continuam classe_nao_suportada no canal e fora da janela, e o retorno_pegar já não via saída do parceiro.
-- Desvio: a spec manda a regra 2 aceitar as duas classes; aqui elas só valem com a origem do parceiro e com a F4 fora de
-- 'desligado', para os testes da F1 (retorno_f1_canal 2a, 2d e 9q) continuarem verdes sem mudar.
--
-- Sem dado. Reverter: reaplicar _retorno_janela, canal_pode_enviar e retorno_saida_autorizada (20261116100500),
-- retorno_pegar (20261201100000) e retorno_registrar_decisao (20261116100700); depois, drop function das funções
-- parceiro_* e _parceiro_* desta migration.

-- ── 1. O modo do parceiro e a porta de entrada das saídas ─────────────────────────────────────────────────────────────

-- O modo efetivo da saída do parceiro: sombra se parceiro_modo não é 'ligado', o tipo está fora de parceiro_tipos_ligados,
-- o eco com eco_modo em sombra, ou a chave da saída é de sombra. Liga só com tudo verde. Não lê retorno_config.modo nem
-- segura_tudo_ate (o segura tudo é reagendamento, no parceiro_pegar).
create or replace function public._parceiro_modo_efetivo(p_saida uuid, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_cfg public.retorno_config := public._retorno_cfg();
  v_s public.retorno_saidas;
begin
  if v_cfg.id is null then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'sem_config');
  end if;
  select * into v_s from public.retorno_saidas s where s.id = p_saida;
  if not found then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'sem_saida');
  end if;
  if v_cfg.parceiro_modo is distinct from 'ligado' then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'parceiro_modo');
  end if;
  if not coalesce(v_s.tipo = any (v_cfg.parceiro_tipos_ligados), false) then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'tipo_desligado');
  end if;
  if v_s.tipo = 'parceiro_eco' and v_cfg.eco_modo is distinct from 'ligado' then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'eco_modo');
  end if;
  if v_s.dedupe_key ~ ':sombra(:|$)' then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'chave_sombra');
  end if;
  return jsonb_build_object('modo', 'ligado', 'motivo', null);
end;
$$;

comment on function public._parceiro_modo_efetivo(uuid, timestamptz) is
  'Retorno F4 (P5.1): {"modo": sombra|ligado, "motivo"} da saída do parceiro: sem_config, sem_saida, parceiro_modo, tipo_desligado, eco_modo ou chave_sombra; ligado só com tudo verde. Não lê retorno_config.modo nem segura_tudo_ate.';

revoke all on function public._parceiro_modo_efetivo(uuid, timestamptz) from public, anon, authenticated;

-- A única porta de entrada das saídas do parceiro: exatamente um entre p_numero (à parceira) e p_fone_cliente (ao cliente
-- final, só aviso e confirmação do NÃO MP). A origem e a classe vêm do tipo (tabela 6.1); a classe passada tem de bater.
-- Sem chave de 8 dígitos (ou número desconhecido), não agenda e devolve nulo. Com o tipo em sombra, a chave ganha
-- ':sombra' (a real fica livre para quando o tipo ligar). Chave repetida não cria outra: devolve a que já existe.
create or replace function public.parceiro_agendar(p_tipo text, p_variante text, p_numero uuid, p_abertura uuid, p_dados jsonb,
                                                   p_enviar_em timestamptz, p_dedupe text, p_classe text,
                                                   p_fone_cliente text default null)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_tipos constant text[] := array['parceiro_ativacao', 'parceiro_recibo', 'parceiro_coleta', 'parceiro_aviso_cliente',
                                   'parceiro_nao_mp_ok', 'parceiro_painel', 'parceiro_patio', 'parceiro_eco', 'parceiro_pausa',
                                   'parceiro_repassar', 'parceiro_recado'];
  v_cfg public.retorno_config := public._retorno_cfg();
  v_dados jsonb := case when jsonb_typeof(p_dados) = 'object' then p_dados else '{}'::jsonb end;
  v_origem text;
  v_classe text;
  v_fone text;
  v_chave text;
  v_client uuid;
  v_num record;
  v_sombra boolean;
  v_dedupe text;
  v_id uuid;
begin
  if (p_numero is null) = (p_fone_cliente is null) then
    raise exception using errcode = '22023', message = 'parceiro_agendar: exatamente um entre o número do parceiro e o telefone do cliente';
  end if;
  if p_tipo is null or not (p_tipo = any (c_tipos)) then
    raise exception using errcode = '22023', message = format('parceiro_agendar: tipo desconhecido %s', coalesce(p_tipo, '(nenhum)'));
  end if;
  if coalesce(btrim(p_dedupe), '') !~ '^parceiro:.' then
    raise exception using errcode = '22023', message = 'parceiro_agendar: a chave tem de começar com parceiro:';
  end if;
  -- A tabela 6.1: tipo → origem → classe.
  v_origem := case when p_tipo in ('parceiro_aviso_cliente', 'parceiro_nao_mp_ok') then 'retorno_aviso' else 'retorno_parceiro' end;
  v_classe := case
    when p_tipo in ('parceiro_recibo', 'parceiro_coleta', 'parceiro_recado', 'parceiro_patio', 'parceiro_pausa', 'parceiro_nao_mp_ok')
      then 'resposta_imediata'
    when p_tipo = 'parceiro_painel' then 'resumo_parceiro'
    else 'aviso'
  end;
  if p_classe is not null and p_classe is distinct from v_classe then
    raise exception using errcode = '22023', message = format('parceiro_agendar: a classe de %s é %s', p_tipo, v_classe);
  end if;
  -- Ao cliente final só o aviso e a confirmação do NÃO MP; à parceira, o resto.
  if (p_fone_cliente is not null) <> (v_origem = 'retorno_aviso') then
    raise exception using errcode = '22023', message = format('parceiro_agendar: %s não vai a esse destino', p_tipo);
  end if;

  if p_numero is not null then
    select n.id, n.phone_normalized, n.pessoa_id, p.parceiro_id into v_num
      from public.parceiro_numeros n
      join public.parceiro_pessoas p on p.id = n.pessoa_id
     where n.id = p_numero;
    if not found then
      return null;
    end if;
    v_fone := v_num.phone_normalized;
    -- os ids do número são do banco: o dado do chamador nunca os troca
    v_dados := v_dados || jsonb_build_object('numero_id', v_num.id, 'pessoa_id', v_num.pessoa_id, 'parceiro_id', v_num.parceiro_id);
    if p_abertura is not null then
      select a.client_id into v_client from public.retorno_aberturas a where a.id = p_abertura;
    end if;
  else
    v_fone := regexp_replace(p_fone_cliente, '\D', '', 'g');
    v_client := nullif(v_dados ->> 'client_id', '')::uuid;
  end if;
  v_chave := public._agenda_chave_telefone(v_fone);
  if v_chave is null then
    return null;
  end if;

  -- Sombra não gasta a chave: o tipo em sombra grava '<chave>:sombra'.
  v_sombra := v_cfg.id is null or v_cfg.parceiro_modo is distinct from 'ligado'
              or not coalesce(p_tipo = any (v_cfg.parceiro_tipos_ligados), false)
              or (p_tipo = 'parceiro_eco' and v_cfg.eco_modo is distinct from 'ligado');
  v_dedupe := case when v_sombra and p_dedupe !~ ':sombra$' then p_dedupe || ':sombra' else p_dedupe end;

  insert into public.retorno_saidas (emissor, abertura_id, tipo, variante, origem, classe, chave, phone_normalized, client_id,
                                     modo, estado, enviar_em, dados, dedupe_key)
  values ('parceiro', p_abertura, p_tipo, left(nullif(btrim(p_variante), ''), 40), v_origem, v_classe, v_chave, v_fone, v_client,
          case when v_sombra then 'sombra' else 'ligado' end, 'agendada', coalesce(p_enviar_em, now()), v_dados, v_dedupe)
  on conflict (dedupe_key) do nothing
  returning id into v_id;
  if v_id is null then
    select s.id into v_id from public.retorno_saidas s where s.dedupe_key = v_dedupe;
  end if;
  return v_id;
end;
$$;

comment on function public.parceiro_agendar(text, text, uuid, uuid, jsonb, timestamptz, text, text, text) is
  'Retorno F4 (P5.1): agenda uma saída do parceiro (emissor parceiro, estado agendada). Exatamente um entre p_numero e p_fone_cliente (senão 22023); origem e classe pela tabela 6.1 (classe diferente = 22023); chave começando com parceiro:. Sem chave de 8 dígitos ou número desconhecido: nulo. Tipo em sombra: dedupe com :sombra. Chave repetida devolve a saída que já existe.';

revoke all on function public.parceiro_agendar(text, text, uuid, uuid, jsonb, timestamptz, text, text, text) from public, anon, authenticated;
grant execute on function public.parceiro_agendar(text, text, uuid, uuid, jsonb, timestamptz, text, text, text) to service_role;

-- ── 2. As linhas do painel e do pátio ──────────────────────────────────────────────────────────────────────────────────────

-- As linhas, uma a uma, numeradas de 1 em diante só entre as que deram texto. A linha que dá 22023 (sem nome, estado ou
-- data) sai com fora_por = 'texto', e as outras seguem. Devolve {linhas: [objeto + k], textos: [texto], fora: [objeto]}.
create or replace function public._parceiro_linhas_texto(p_tipo text, p_linhas jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ok jsonb := '[]'::jsonb;
  v_textos jsonb := '[]'::jsonb;
  v_fora jsonb := '[]'::jsonb;
  v_k integer := 0;
  v_l jsonb;
  v_txt text;
  v_vessel uuid;
  v_client uuid;
begin
  for v_l in select e from jsonb_array_elements(case when jsonb_typeof(p_linhas) = 'array' then p_linhas else '[]'::jsonb end) e loop
    begin
      if jsonb_typeof(v_l) is distinct from 'object' then
        raise exception using errcode = '22023', message = 'parceiro_linhas_texto: linha que não é objeto';
      end if;
      v_vessel := null;
      v_client := null;
      select so.vessel_id, oi.client_id into v_vessel, v_client
        from public.os_interessados oi
        join public.service_orders so on so.id = oi.service_order_id
       where oi.id = nullif(v_l ->> 'interessado_id', '')::uuid;
      -- a etapa (R1, respostas de 09/11) só vai quando a linha a traz; o catálogo só a usa com parceiro_etapa_ligada
      v_txt := public._parceiro_texto(p_tipo, 'linha', jsonb_build_object(
                 'n', v_k + 1, 'bem', public._parceiro_bem(v_vessel), 'cliente', public._parceiro_nome_curto(v_client),
                 'estado', v_l ->> 'estado', 'desde', v_l -> 'desde')
                 || (case when jsonb_typeof(v_l -> 'etapa') = 'string' then jsonb_build_object('etapa', v_l -> 'etapa')
                          else '{}'::jsonb end));
      v_k := v_k + 1;
      v_ok := v_ok || jsonb_build_array((v_l - 'k') || jsonb_build_object('k', v_k));
      v_textos := v_textos || to_jsonb(v_txt);
    exception when sqlstate '22023' or sqlstate '22P02' then
      v_fora := v_fora || jsonb_build_array((case when jsonb_typeof(v_l) = 'object' then v_l - 'k' else '{}'::jsonb end)
                                            || jsonb_build_object('fora_por', 'texto'));
    end;
  end loop;
  return jsonb_build_object('linhas', v_ok, 'textos', v_textos, 'fora', v_fora);
end;
$$;

comment on function public._parceiro_linhas_texto(text, jsonb) is
  'Retorno F4 (P5.1, linha 7): monta as linhas do painel ou do pátio por _parceiro_texto(…, ''linha''), numeradas de 1 a k só entre as que deram texto. A que dá 22023 sai com fora_por = texto. Devolve {linhas, textos, fora}; nunca guarda o texto nas linhas.';

revoke all on function public._parceiro_linhas_texto(text, jsonb) from public, anon, authenticated;

-- O painel (P06) ou o pátio direto (P10) inteiro: as linhas, o corte (no máximo 14 linhas de OS e 1.500 caracteres, com
-- "E mais N veículos."), o cabeçalho e o rodapé. O corte nunca vira 'tamanho' nem derruba o painel. p_mais_antes soma as
-- linhas que já tinham sido cortadas antes. Sem nenhuma linha com texto: 22023.
create or replace function public._parceiro_painel_texto(p_tipo text, p_variante text, p_linhas jsonb, p_mais_antes integer,
                                                         p_dia date, p_rodape boolean)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_max constant integer := 14;
  c_limite constant integer := 1500;
  v_r jsonb;
  v_n integer;
  v_m integer;
  v_mais integer;
  v_texto text;
begin
  v_r := public._parceiro_linhas_texto(p_tipo, p_linhas);
  v_n := jsonb_array_length(v_r -> 'textos');
  if v_n = 0 then
    raise exception using errcode = '22023', message = 'parceiro_painel_texto: nenhuma linha com texto';
  end if;
  v_m := least(v_n, c_max);
  loop
    v_mais := (v_n - v_m) + greatest(coalesce(p_mais_antes, 0), 0);
    v_texto := public._parceiro_texto(p_tipo, p_variante, jsonb_build_object(
      'dia', p_dia,
      'linhas', (select jsonb_agg(t.x order by t.o) from jsonb_array_elements(v_r -> 'textos') with ordinality t(x, o) where t.o <= v_m),
      'mais', v_mais,
      'rodape', coalesce(p_rodape, false)));
    exit when char_length(v_texto) <= c_limite or v_m <= 1;
    v_m := v_m - 1;
  end loop;
  if char_length(v_texto) > c_limite then
    raise exception using errcode = '22023', message = 'parceiro_painel_texto: nem uma linha cabe';
  end if;
  return jsonb_build_object(
    'texto', v_texto,
    'linhas', (select coalesce(jsonb_agg(t.x order by t.o), '[]'::jsonb)
                 from jsonb_array_elements(v_r -> 'linhas') with ordinality t(x, o) where t.o <= v_m),
    'cortadas', (select coalesce(jsonb_agg(t.x - 'k' order by t.o), '[]'::jsonb)
                   from jsonb_array_elements(v_r -> 'linhas') with ordinality t(x, o) where t.o > v_m),
    'fora', v_r -> 'fora',
    'mais', v_mais,
    'item_linhas', (select coalesce(jsonb_agg(jsonb_build_object('n', t.o, 'texto', t.x #>> '{}') order by t.o), '[]'::jsonb)
                      from jsonb_array_elements(v_r -> 'textos') with ordinality t(x, o) where t.o <= v_m));
end;
$$;

comment on function public._parceiro_painel_texto(text, text, jsonb, integer, date, boolean) is
  'Retorno F4 (P4.1 e P5.1): o painel (P06) ou o pátio direto (P10): no máximo 14 linhas de OS e 1.500 caracteres; o que não cabe sai do fim e vira "E mais N veículos.". Devolve {texto, linhas (as que ficaram, com k), cortadas, fora, mais, item_linhas [{n, texto}]}. Sem linha com texto: 22023.';

revoke all on function public._parceiro_painel_texto(text, text, jsonb, integer, date, boolean) from public, anon, authenticated;

-- Tira das listas da saída (os_ids e interessado_ids, na mesma posição; linhas e bloco, pelo interessado) os vínculos dados,
-- e guarda os objetos tirados em linhas_fora com o motivo. Nunca guarda texto.
create or replace function public._parceiro_tirar_vinculos(p_dados jsonb, p_ids uuid[], p_fora_por text)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  v_d jsonb := case when jsonb_typeof(p_dados) = 'object' then p_dados else '{}'::jsonb end;
  v_ids text[] := array(select x::text from unnest(coalesce(p_ids, '{}'::uuid[])) as x);
  v_int jsonb := case when jsonb_typeof(v_d -> 'interessado_ids') = 'array' then v_d -> 'interessado_ids' else '[]'::jsonb end;
  v_os jsonb := case when jsonb_typeof(v_d -> 'os_ids') = 'array' then v_d -> 'os_ids' else '[]'::jsonb end;
  v_fora jsonb := case when jsonb_typeof(v_d -> 'linhas_fora') = 'array' then v_d -> 'linhas_fora' else '[]'::jsonb end;
  v_chave text;
begin
  v_d := v_d || jsonb_build_object(
    'interessado_ids', (select coalesce(jsonb_agg(x.v order by x.o), '[]'::jsonb)
                          from jsonb_array_elements(v_int) with ordinality x(v, o)
                         where not ((x.v #>> '{}') = any (v_ids))),
    'os_ids', (select coalesce(jsonb_agg(y.v order by y.o), '[]'::jsonb)
                 from jsonb_array_elements(v_os) with ordinality y(v, o)
                where not (coalesce(v_int ->> (y.o::integer - 1), '') = any (v_ids))));
  foreach v_chave in array array['linhas', 'bloco'] loop
    if jsonb_typeof(v_d -> v_chave) = 'array' then
      v_fora := v_fora || (select coalesce(jsonb_agg((l.v - 'k') || jsonb_build_object('fora_por', p_fora_por) order by l.o), '[]'::jsonb)
                             from jsonb_array_elements(v_d -> v_chave) with ordinality l(v, o)
                            where coalesce(l.v ->> 'interessado_id', '') = any (v_ids));
      v_d := v_d || jsonb_build_object(v_chave,
               (select coalesce(jsonb_agg(l.v order by l.o), '[]'::jsonb)
                  from jsonb_array_elements(v_d -> v_chave) with ordinality l(v, o)
                 where not (coalesce(l.v ->> 'interessado_id', '') = any (v_ids))));
    end if;
  end loop;
  return v_d || jsonb_build_object('linhas_fora', v_fora);
end;
$$;

comment on function public._parceiro_tirar_vinculos(jsonb, uuid[], text) is
  'Retorno F4 (P5.1): tira das listas da saída (os_ids e interessado_ids na mesma posição, linhas e bloco pelo interessado_id) os vínculos dados e guarda os objetos tirados em linhas_fora com fora_por. Nunca guarda texto.';

revoke all on function public._parceiro_tirar_vinculos(jsonb, uuid[], text) from public, anon, authenticated;

-- Marca em parceiro_paineis.linhas, pelo interessado, as linhas que saíram no envio (fora_por), sem renumerar: o n é o
-- que o dono viu.
create or replace function public._parceiro_painel_marcar(p_painel uuid, p_fora jsonb)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  if p_painel is null or jsonb_typeof(p_fora) is distinct from 'array' or jsonb_array_length(p_fora) = 0 then
    return;
  end if;
  update public.parceiro_paineis pp
     set linhas = (select coalesce(jsonb_agg(
                           case when l.v ->> 'fora_por' is null
                                     and exists (select 1 from jsonb_array_elements(p_fora) f
                                                  where f ->> 'interessado_id' = l.v ->> 'interessado_id')
                                then l.v || jsonb_build_object('fora_por',
                                       (select f ->> 'fora_por' from jsonb_array_elements(p_fora) f
                                         where f ->> 'interessado_id' = l.v ->> 'interessado_id' limit 1))
                                else l.v end
                           order by l.o), '[]'::jsonb)
                     from jsonb_array_elements(pp.linhas) with ordinality l(v, o))
   where pp.id = p_painel;
end;
$$;

comment on function public._parceiro_painel_marcar(uuid, jsonb) is
  'Retorno F4 (P5.1 e P5.2): grava fora_por (regra, texto ou validador) nas linhas de parceiro_paineis que saíram no envio, pelo interessado_id, sem renumerar.';

revoke all on function public._parceiro_painel_marcar(uuid, jsonb) from public, anon, authenticated;

-- As linhas que saem hoje ao parceiro (parceiro_linhas, da P7), na ordem de P7.2: só as com n e sem fora_por. Sem a
-- função (a bancada das ondas 4 e 5 antes da P7), nenhuma: o recibo sai sem o bloco.
create or replace function public._parceiro_linhas_que_saem(p_parceiro uuid, p_agora timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_r jsonb;
begin
  if to_regprocedure('public.parceiro_linhas(uuid, timestamptz)') is null then
    return '[]'::jsonb;
  end if;
  v_r := public.parceiro_linhas(p_parceiro, p_agora);
  if jsonb_typeof(v_r) = 'object' then
    v_r := v_r -> 'linhas';
  end if;
  if jsonb_typeof(v_r) is distinct from 'array' then
    return '[]'::jsonb;
  end if;
  -- a etapa (R1, respostas de 09/11) segue com a linha quando parceiro_linhas a pôs
  return (select coalesce(jsonb_agg(jsonb_build_object('n', (x ->> 'n')::integer, 'interessado_id', x -> 'interessado_id',
                                                       'service_order_id', x -> 'service_order_id', 'estado', x -> 'estado',
                                                       'desde', x -> 'desde')
                                    || (case when jsonb_typeof(x -> 'etapa') = 'string' then jsonb_build_object('etapa', x -> 'etapa')
                                             else '{}'::jsonb end)
                                    order by (x ->> 'n')::integer), '[]'::jsonb)
            from jsonb_array_elements(v_r) x
           where jsonb_typeof(x) = 'object'
             and x ->> 'fora_por' is null
             and coalesce(x ->> 'n', '') ~ '^[0-9]{1,3}$');
end;
$$;

comment on function public._parceiro_linhas_que_saem(uuid, timestamptz) is
  'Retorno F4 (P5.1, bloco P11): as linhas de parceiro_linhas (P7) que saem hoje, na ordem de n, só ids, estado e desde (e a etapa, quando parceiro_linhas a pôs: R1 de 09/11). Sem a função, lista vazia.';

revoke all on function public._parceiro_linhas_que_saem(uuid, timestamptz) from public, anon, authenticated;

-- O contexto do validador do painel e do pátio, com os trechos do modelo também quebrados por linha: a rodada valida cada
-- linha sozinha (P5.2), e o trecho que atravessa a quebra de linha não está dentro de uma linha só. Os pedaços são texto
-- fixo do modelo: a permissão não cresce além do que o banco escreveu.
create or replace function public._parceiro_trechos_por_linha(p_ctx jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select case
    when jsonb_typeof(p_ctx -> 'trechos_do_modelo') = 'array' then
      jsonb_set(p_ctx, '{trechos_do_modelo}', coalesce((
        select jsonb_agg(y.t order by y.primeira)
          from (select x.t, min(x.o) as primeira
                  from (select e.t, e.o::bigint * 1000 as o
                          from jsonb_array_elements_text(p_ctx -> 'trechos_do_modelo') with ordinality e(t, o)
                        union all
                        select pd.t, e.o::bigint * 1000 + pd.o
                          from jsonb_array_elements_text(p_ctx -> 'trechos_do_modelo') with ordinality e(t, o),
                               regexp_split_to_table(e.t, E'\n') with ordinality pd(t, o)
                         where btrim(pd.t) <> '') x
                 group by x.t) y), '[]'::jsonb))
    else p_ctx
  end;
$$;

comment on function public._parceiro_trechos_por_linha(jsonb) is
  'Retorno F4 (P5.2): devolve o contexto com os trechos_do_modelo acrescidos dos mesmos trechos quebrados por linha, para a validação linha a linha do painel e do pátio na edge.';

revoke all on function public._parceiro_trechos_por_linha(jsonb) from public, anon, authenticated;

-- ── 3. A trava do aviso e os efeitos ───────────────────────────────────────────────────────────────────────────────────────

-- O aviso ao cliente ainda vale? Nulo = vale; senão o motivo: veto (do par), opt_out (cadastro ou canal), numero_compartilhado
-- (quem_escreve do telefone deixou de ser só aquele cliente) ou parceiro_regra (nenhum vínculo citado continua confirmado,
-- sem retenção e sem aviso_saida_id, ou o parceiro inativo). A régua é aviso_saida_id, não aviso_em: o vínculo registrado
-- "pessoalmente" ou "pela revenda" que ganhou telefone também recebe o aviso.
create or replace function public._parceiro_aviso_ainda_vale(p_saida uuid, p_agora timestamptz)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_s public.retorno_saidas;
  v_client uuid;
  v_parceiro uuid;
  v_ids uuid[];
  v_cl public.clients;
  v_q jsonb;
begin
  select * into v_s from public.retorno_saidas s where s.id = p_saida;
  if not found then
    return 'parceiro_regra';
  end if;
  v_client := nullif(v_s.dados ->> 'client_id', '')::uuid;
  v_parceiro := nullif(v_s.dados ->> 'parceiro_id', '')::uuid;
  v_ids := array(select x::uuid
                   from jsonb_array_elements_text(case when jsonb_typeof(v_s.dados -> 'interessado_ids') = 'array'
                                                       then v_s.dados -> 'interessado_ids' else '[]'::jsonb end) x);
  if v_client is null or v_parceiro is null then
    return 'parceiro_regra';
  end if;
  if public._parceiro_veto_de(v_client, v_parceiro, v_agora) is not null then
    return 'veto';
  end if;
  select * into v_cl from public.clients c where c.id = v_client;
  if not found or coalesce(v_cl.opt_out_whatsapp, false) or public.canal_bloqueado(v_s.phone_normalized) is not null then
    return 'opt_out';
  end if;
  v_q := public.quem_escreve(v_s.phone_normalized);
  if v_q ->> 'papel' is distinct from 'cliente' or nullif(v_q ->> 'cliente_id', '')::uuid is distinct from v_client then
    return 'numero_compartilhado';
  end if;
  if not exists (select 1 from public.parceiros pa where pa.id = v_parceiro and pa.ativo)
     or not exists (select 1 from public.os_interessados oi
                     where oi.id = any (v_ids)
                       and oi.client_id = v_client
                       and oi.parceiro_id = v_parceiro
                       and oi.situacao = 'confirmado'
                       and oi.papel is distinct from 'anfitria'
                       and oi.retido_em is null
                       and oi.aviso_saida_id is null) then
    return 'parceiro_regra';
  end if;
  return null;
end;
$$;

comment on function public._parceiro_aviso_ainda_vale(uuid, timestamptz) is
  'Retorno F4 (P5.1): nulo se o aviso ao cliente ainda vale; senão veto, opt_out, numero_compartilhado ou parceiro_regra (nenhum vínculo de interessado_ids confirmado, sem retido_em e sem aviso_saida_id, ou parceiro inativo).';

revoke all on function public._parceiro_aviso_ainda_vale(uuid, timestamptz) from public, anon, authenticated;

-- Os efeitos de uma decisão de saída do parceiro (chamada por retorno_registrar_decisao em toda decisão). Enviada: o aviso
-- grava todos os vínculos confirmados do par sem aviso_saida_id (os nao_avisado ganham 'mensagem' e aviso_em; os
-- registrados pessoalmente ou pela revenda, só aviso_saida_id, sem nova carência); o painel vira 'enviado'; a 1ª mensagem
-- com a apresentação grava apresentada_em. A incerta não conta como aviso. A coleta decidida em sombra, enviada ou incerta
-- soma coleta_n no caso (até 2).
create or replace function public._parceiro_aplicar_efeitos(p_saida uuid, p_agora timestamptz)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_s public.retorno_saidas;
  v_em timestamptz;
  v_numero uuid;
begin
  select * into v_s from public.retorno_saidas s where s.id = p_saida;
  if not found or v_s.emissor is distinct from 'parceiro' then
    return;
  end if;
  v_em := coalesce(v_s.enviada_em, v_s.decidida_em, p_agora, now());

  if v_s.estado = 'enviada' then
    if v_s.tipo = 'parceiro_aviso_cliente' then
      update public.os_interessados oi
         set aviso_saida_id = v_s.id,
             aviso_ao_cliente = case when oi.aviso_ao_cliente = 'nao_avisado' then 'mensagem' else oi.aviso_ao_cliente end,
             aviso_em = case when oi.aviso_ao_cliente = 'nao_avisado' then v_em else oi.aviso_em end
       where oi.client_id = nullif(v_s.dados ->> 'client_id', '')::uuid
         and oi.parceiro_id = nullif(v_s.dados ->> 'parceiro_id', '')::uuid
         and oi.situacao = 'confirmado'
         and oi.papel is distinct from 'anfitria'
         and oi.aviso_saida_id is null
         and oi.aviso_ao_cliente in ('nao_avisado', 'pessoalmente', 'pela_revenda');
    end if;
    if v_s.tipo = 'parceiro_painel' and coalesce(v_s.dados ->> 'painel_id', '') ~ '^[0-9a-f-]{36}$' then
      update public.parceiro_paineis pp set estado = 'enviado' where pp.id = (v_s.dados ->> 'painel_id')::uuid;
    end if;
    v_numero := case when coalesce(v_s.dados ->> 'numero_id', '') ~ '^[0-9a-f-]{36}$' then (v_s.dados ->> 'numero_id')::uuid end;
    if v_numero is not null and coalesce(v_s.texto, '') like '%assistente virtual da HBR%' then
      update public.parceiro_numeros n set apresentada_em = v_em where n.id = v_numero;
    end if;
  end if;

  if v_s.tipo = 'parceiro_coleta' and v_s.estado in ('sombra', 'enviada', 'incerta') and v_s.abertura_id is not null then
    update public.retorno_aberturas a
       set coleta_n = least(a.coleta_n + 1, 2), atualizada_em = now()
     where a.id = v_s.abertura_id;
  end if;
end;
$$;

comment on function public._parceiro_aplicar_efeitos(uuid, timestamptz) is
  'Retorno F4 (P5.1): os efeitos da decisão de uma saída do parceiro. Enviada: aviso → todos os vínculos confirmados do par sem aviso_saida_id (nao_avisado vira mensagem com aviso_em; os registrados só ganham aviso_saida_id); painel → enviado; apresentação → apresentada_em. A incerta não conta como aviso. Coleta em sombra, enviada ou incerta → coleta_n + 1 (até 2).';

revoke all on function public._parceiro_aplicar_efeitos(uuid, timestamptz) from public, anon, authenticated;

-- ── 4. A fila do parceiro ──────────────────────────────────────────────────────────────────────────────────────────────────

-- Fecha a saída sem texto novo (recusada ou cancelada), com o motivo da lista fechada.
create or replace function public._parceiro_pegar_fechar(p_saida uuid, p_estado text, p_motivo text, p_dados jsonb, p_agora timestamptz)
returns void
language sql
volatile
security definer
set search_path = public
as $$
  update public.retorno_saidas s
     set estado = p_estado, motivo = p_motivo, decidida_em = p_agora, processando_ate = null,
         dados = coalesce(p_dados, s.dados), atualizada_em = now()
   where s.id = p_saida;
$$;

comment on function public._parceiro_pegar_fechar(uuid, text, text, jsonb, timestamptz) is
  'Retorno F4 (P5.1): fecha a saída do parceiro (recusada ou cancelada) com o motivo, a hora da decisão e os dados.';

revoke all on function public._parceiro_pegar_fechar(uuid, text, text, jsonb, timestamptz) from public, anon, authenticated;

-- A fila do parceiro (C-PEGAR-P): até 10 voltas, cada uma com 1 saída devida do emissor 'parceiro', FOR UPDATE SKIP LOCKED;
-- cada volta num begin … exception próprio (o item que dá exceção vira recusada/erro, vai ao log e o próximo segue). A
-- ordem é a da tabela de P5.1, e a primeira que falha decide; fora os reagendamentos (8a e 9), recusada leva o motivo.
-- Devolve o formato do retorno_pegar, com o contexto do validador do parceiro (ou do cliente, no aviso e no NÃO MP) e,
-- no painel e no pátio, linhas [{n, texto}] para a validação linha a linha da edge.
create or replace function public.parceiro_pegar(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_contam constant text[] := array['sombra', 'preparada', 'enviando', 'enviada', 'incerta'];
  c_ao_cliente constant text[] := array['parceiro_aviso_cliente', 'parceiro_nao_mp_ok'];
  c_conversa constant text[] := array['parceiro_recibo', 'parceiro_coleta', 'parceiro_recado'];
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date;
  v_desde_hoje timestamptz;
  v_cfg public.retorno_config;
  v_volta integer;
  v_s public.retorno_saidas;
  v_ab public.retorno_aberturas;
  v_dados jsonb;
  v_num record;
  v_parceiro uuid;
  v_pessoa uuid;
  v_numero uuid;
  v_client uuid;
  v_motivo text;
  v_rh jsonb;
  v_n integer;
  v_citacao boolean;
  v_ids uuid[];
  v_os uuid[];
  v_vis jsonb;
  v_visib jsonb;
  v_caiu uuid[];
  v_cand jsonb;
  v_lin jsonb;
  v_painel jsonb;
  v_texto text;
  v_var text;
  v_campos jsonb;
  v_guardar jsonb;
  v_nomes jsonb;
  v_pz jsonb;
  v_ped public.parceiro_pedidos;
  v_so record;
  v_sigla text;
  v_dia date;
  v_rodape boolean;
  v_item_linhas jsonb;
  v_modo jsonb;
  v_ligado boolean;
  v_canal jsonb;
  v_ctx jsonb;
  v_k integer;
  v_forma text;
  v_primeiro text;
  i integer;
begin
  v_cfg := public._retorno_cfg();
  if v_cfg.id is null or v_cfg.modo = 'desligado' then
    return null;
  end if;
  -- A F4 desligada: toda agendada do parceiro cai, e nada sai.
  if v_cfg.parceiro_modo = 'desligado' then
    update public.retorno_saidas s
       set estado = 'cancelada', motivo = 'parceiro_desligado', decidida_em = v_agora, processando_ate = null, atualizada_em = now()
     where s.id in (select x.id from public.retorno_saidas x
                     where x.emissor = 'parceiro' and x.estado = 'agendada'
                     for update skip locked);
    return null;
  end if;
  v_desde_hoje := v_hoje::timestamp at time zone c_fuso;

  for v_volta in 1 .. 10 loop
    select * into v_s
      from public.retorno_saidas s
     where s.emissor = 'parceiro'
       and s.estado = 'agendada'
       and s.enviar_em <= v_agora
       and (s.processando_ate is null or s.processando_ate < v_agora)
     order by s.enviar_em, s.id
     limit 1
     for update skip locked;
    if not found then
      return null;
    end if;

    begin
      v_dados := v_s.dados;
      v_var := coalesce(v_s.variante, 'padrao');
      v_motivo := null;
      v_parceiro := null;
      v_pessoa := null;
      v_numero := null;
      v_item_linhas := null;
      v_ab := null;
      -- o registro do número sempre atribuído (nulo na saída ao cliente), para nenhuma volta ler o da anterior
      select null::uuid as id, false as recebe_painel, null::uuid as pessoa_id, null::timestamptz as pausado_em,
             null::uuid as parceiro_id, null::text as sigla
        into v_num;
      v_campos := '{}'::jsonb;
      v_guardar := '{}'::jsonb;

      -- 1. Saída à parceira: o número ainda confirmado, a pessoa e o parceiro ativos.
      if not (v_s.tipo = any (c_ao_cliente)) then
        v_numero := case when coalesce(v_dados ->> 'numero_id', '') ~ '^[0-9a-f-]{36}$' then (v_dados ->> 'numero_id')::uuid end;
        select n.id, n.recebe_painel, p.id as pessoa_id, p.pausado_em, p.parceiro_id, pa.sigla into v_num
          from public.parceiro_numeros n
          join public.parceiro_pessoas p on p.id = n.pessoa_id and p.ativo
          join public.parceiros pa on pa.id = p.parceiro_id and pa.ativo
         where n.id = v_numero and n.situacao = 'confirmado';
        if not found then
          v_motivo := 'parceiro_regra';
        else
          v_parceiro := v_num.parceiro_id;
          v_pessoa := v_num.pessoa_id;
        end if;
      -- 1a. O aviso ao cliente ainda vale (também o reagendado para a manhã seguinte).
      elsif v_s.tipo = 'parceiro_aviso_cliente' then
        v_motivo := public._parceiro_aviso_ainda_vale(v_s.id, v_agora);
      end if;
      if v_motivo is not null then
        perform public._parceiro_pegar_fechar(v_s.id, 'recusada', v_motivo, v_dados, v_agora);
        continue;
      end if;

      -- 1b. O caso: fechado, ou o dono já respondeu à chave depois da abertura (até um "ok, já vejo").
      if v_s.abertura_id is not null then
        select * into v_ab from public.retorno_aberturas a where a.id = v_s.abertura_id;
        if not found or v_ab.estado = 'fechada' then
          perform public._parceiro_pegar_fechar(v_s.id, 'cancelada', 'caso_fechado', v_dados, v_agora);
          continue;
        end if;
        v_rh := public._retorno_resposta_humana(v_ab.id, v_agora);
        if v_rh ->> 'respondida_em' is not null then
          perform public._parceiro_pegar_fechar(v_s.id, 'cancelada', 'respondida_pelo_dono', v_dados, v_agora);
          update public.retorno_aberturas a
             set respondida_em = coalesce(a.respondida_em, (v_rh ->> 'respondida_em')::timestamptz), atualizada_em = now()
           where a.id = v_ab.id;
          continue;
        end if;
      end if;

      -- 2. A pessoa pausada: painel, eco e repassar; o painel e o eco só ao número que recebe o resumo.
      if v_s.tipo in ('parceiro_painel', 'parceiro_eco', 'parceiro_repassar')
         and ((v_num.pausado_em is not null and v_num.pausado_em <= v_agora)
              or (v_s.tipo in ('parceiro_painel', 'parceiro_eco') and not coalesce(v_num.recebe_painel, false))) then
        perform public._parceiro_pegar_fechar(v_s.id, 'recusada', 'pausado', v_dados, v_agora);
        continue;
      end if;

      -- 3. "Segura pátio": o painel, o pátio e o eco caem (o recibo sai sem o bloco, abaixo).
      if v_s.tipo in ('parceiro_painel', 'parceiro_patio', 'parceiro_eco') and v_cfg.segura_patio then
        perform public._parceiro_pegar_fechar(v_s.id, 'recusada', 'segura_patio', v_dados, v_agora);
        continue;
      end if;

      -- 4. Os tetos (contam sombra, preparada, enviando, enviada e incerta decididas até agora).
      v_motivo := null;
      if v_s.tipo = 'parceiro_painel' then
        select count(*) into v_n from public.retorno_saidas o
         where o.emissor = 'parceiro' and o.tipo = 'parceiro_painel' and o.id <> v_s.id
           and o.dados ->> 'parceiro_id' = v_parceiro::text
           and o.estado = any (c_contam) and o.decidida_em >= v_desde_hoje and o.decidida_em <= v_agora;
        if v_n >= v_cfg.painel_dia_max then
          v_motivo := 'teto_painel';
        end if;
      elsif v_s.tipo = 'parceiro_eco' then
        select count(*) into v_n from public.retorno_saidas o
         where o.emissor = 'parceiro' and o.tipo = 'parceiro_eco' and o.id <> v_s.id
           and o.dados ->> 'parceiro_id' = v_parceiro::text
           and o.estado = any (c_contam) and o.decidida_em >= v_desde_hoje and o.decidida_em <= v_agora;
        if v_n >= v_cfg.eco_dia_max then
          v_motivo := 'teto_eco';
        end if;
      elsif v_s.tipo = 'parceiro_patio' then
        select count(*) into v_n from public.retorno_saidas o
         where o.emissor = 'parceiro' and o.tipo = 'parceiro_patio' and o.id <> v_s.id and o.chave = v_s.chave
           and o.estado = any (c_contam) and o.decidida_em >= v_desde_hoje and o.decidida_em <= v_agora;
        if v_n >= v_cfg.patio_dia_max then
          v_motivo := 'teto_patio';
        end if;
      elsif v_s.tipo = any (c_conversa) then
        -- recibo, coleta ou recado de OUTRO caso na mesma chave, em recibo_intervalo: só caso diferente conta
        if exists (select 1 from public.retorno_saidas o
                    where o.emissor = 'parceiro' and o.chave = v_s.chave and o.id <> v_s.id
                      and o.tipo = any (c_conversa)
                      and o.abertura_id is distinct from v_s.abertura_id
                      and o.estado = any (c_contam)
                      and o.decidida_em <= v_agora
                      and o.decidida_em > v_agora - v_cfg.recibo_intervalo) then
          v_motivo := 'teto_numero';
        elsif v_s.tipo = 'parceiro_coleta'
              and (select count(*) from public.retorno_saidas o
                    where o.emissor = 'parceiro' and o.abertura_id = v_s.abertura_id and o.id <> v_s.id
                      and o.tipo = 'parceiro_coleta' and o.estado = any (c_contam) and o.decidida_em <= v_agora) >= v_cfg.coleta_max then
          v_motivo := 'teto_coleta';
        end if;
      end if;
      if v_motivo is not null then
        perform public._parceiro_pegar_fechar(v_s.id, 'recusada', v_motivo, v_dados, v_agora);
        continue;
      end if;

      -- O bloco do pátio no recibo (P11), decidido antes da linha 5: patio_nivel 'direto', sem segura pátio, ao menos 1
      -- linha e nenhum recibo com bloco à mesma chave em patio_recibo_intervalo. Sem as condições, o recibo não é citação.
      if v_s.tipo = 'parceiro_recibo' and v_var = 'padrao' then
        v_dados := v_dados || jsonb_build_object('bloco_patio', false, 'bloco', '[]'::jsonb, 'os_ids', '[]'::jsonb,
                                                 'interessado_ids', '[]'::jsonb);
        if v_cfg.patio_nivel = 'direto' and not v_cfg.segura_patio
           and not exists (select 1 from public.retorno_saidas o
                            where o.emissor = 'parceiro' and o.chave = v_s.chave and o.tipo = 'parceiro_recibo' and o.id <> v_s.id
                              and coalesce((o.dados ->> 'bloco_patio')::boolean, false)
                              and o.estado = any (c_contam)
                              and o.decidida_em <= v_agora
                              and o.decidida_em > v_agora - v_cfg.patio_recibo_intervalo) then
          v_cand := public._parceiro_linhas_que_saem(v_parceiro, v_agora);
          if jsonb_array_length(v_cand) > 0 then
            v_dados := v_dados || jsonb_build_object(
              'bloco_patio', true,
              'bloco', v_cand,
              'os_ids', (select coalesce(jsonb_agg(t.x -> 'service_order_id' order by t.o), '[]'::jsonb)
                           from jsonb_array_elements(v_cand) with ordinality t(x, o)),
              'interessado_ids', (select coalesce(jsonb_agg(t.x -> 'interessado_id' order by t.o), '[]'::jsonb)
                                    from jsonb_array_elements(v_cand) with ordinality t(x, o)));
          end if;
        end if;
      end if;

      -- 5. A regra de ouro de novo, vínculo a vínculo, nos tipos de citação (6.1). A OS que caiu sai da linha.
      v_citacao := v_s.tipo in ('parceiro_painel', 'parceiro_eco', 'parceiro_repassar')
                   or (v_s.tipo = 'parceiro_patio' and v_var is distinct from 'vazio')
                   or (v_s.tipo = 'parceiro_recibo' and coalesce((v_dados ->> 'bloco_patio')::boolean, false));
      if v_citacao then
        v_ids := array(select x::uuid from jsonb_array_elements_text(case when jsonb_typeof(v_dados -> 'interessado_ids') = 'array'
                                                                           then v_dados -> 'interessado_ids' else '[]'::jsonb end) x);
        v_os := array(select x::uuid from jsonb_array_elements_text(case when jsonb_typeof(v_dados -> 'os_ids') = 'array'
                                                                          then v_dados -> 'os_ids' else '[]'::jsonb end) x);
        if cardinality(v_ids) = 0 or cardinality(v_ids) is distinct from cardinality(v_os) then
          perform public._parceiro_pegar_fechar(v_s.id, 'recusada', 'parceiro_regra', v_dados, v_agora);
          continue;
        end if;
        v_visib := '[]'::jsonb;
        v_caiu := '{}'::uuid[];
        for i in 1 .. cardinality(v_ids) loop
          if exists (select 1 from public.os_interessados oi
                      where oi.id = v_ids[i] and oi.parceiro_id = v_parceiro and oi.service_order_id = v_os[i]) then
            v_vis := public.parceiro_os_visivel(v_ids[i], v_agora);
          else
            v_vis := jsonb_build_object('visivel', false, 'motivo', 'outro_parceiro');
          end if;
          v_visib := v_visib || jsonb_build_array(jsonb_build_object(
            'interessado_id', v_ids[i], 'visivel', coalesce((v_vis ->> 'visivel')::boolean, false), 'motivo', v_vis ->> 'motivo',
            'em', v_agora));
          if (v_vis ->> 'visivel')::boolean is not true then
            v_caiu := v_caiu || v_ids[i];
          end if;
        end loop;
        v_dados := v_dados || jsonb_build_object('visibilidade', v_visib);
        if cardinality(v_caiu) > 0 then
          v_dados := public._parceiro_tirar_vinculos(v_dados, v_caiu, 'regra');
          if v_s.tipo = 'parceiro_painel' and coalesce(v_dados ->> 'painel_id', '') ~ '^[0-9a-f-]{36}$' then
            perform public._parceiro_painel_marcar((v_dados ->> 'painel_id')::uuid,
              (select coalesce(jsonb_agg(f), '[]'::jsonb) from jsonb_array_elements(v_dados -> 'linhas_fora') f
                where f ->> 'fora_por' = 'regra'));
          end if;
        end if;
        if jsonb_array_length(v_dados -> 'interessado_ids') = 0 then
          if v_s.tipo = 'parceiro_patio' then
            -- o pátio pedido responde sempre: sem linha sobrando, vira o "vazio", que não cita ninguém
            v_var := 'vazio';
            v_dados := v_dados || jsonb_build_object('sem_linhas', true, 'linhas', '[]'::jsonb);
          elsif v_s.tipo = 'parceiro_recibo' then
            v_dados := v_dados || jsonb_build_object('bloco_patio', false, 'bloco', '[]'::jsonb);
          else
            perform public._parceiro_pegar_fechar(v_s.id, 'recusada', 'parceiro_regra', v_dados, v_agora);
            continue;
          end if;
        end if;
      end if;

      -- 6. O eco: o cliente ouviu o marco (P7). Nunca o parceiro sabe antes do cliente. Aninhado de propósito: o plpgsql
      -- prepara a condição inteira na 1ª passada, e _parceiro_cliente_ouviu (P7, onda 5) não existe na onda 4.
      if v_s.tipo = 'parceiro_eco' then
        if public._parceiro_cliente_ouviu((v_dados -> 'os_ids' ->> 0)::uuid, v_var, v_agora) is null then
          perform public._parceiro_pegar_fechar(v_s.id, 'recusada', 'cliente_nao_ouviu', v_dados, v_agora);
          continue;
        end if;
      end if;

      -- O eco e o repassar falam de uma OS só: nome que colide com outro cliente do parceiro derruba a saída (P4.2, item 5).
      if v_s.tipo in ('parceiro_eco', 'parceiro_repassar') then
        select oi.client_id into v_client from public.os_interessados oi where oi.id = (v_dados -> 'interessado_ids' ->> 0)::uuid;
        v_forma := public._parceiro_nome_curto(v_client);
        v_primeiro := public._agenda_nome_curto(v_forma);
        v_nomes := public._parceiro_nomes_do_contexto(v_parceiro, array[v_client], v_pessoa);
        if v_forma is null
           or exists (select 1 from jsonb_array_elements_text(v_nomes -> 'nomes_de_outros') o
                       where public._texto_simples(btrim(o)) in (public._texto_simples(v_forma), public._texto_simples(v_primeiro))) then
          perform public._parceiro_pegar_fechar(v_s.id, 'recusada', 'parceiro_regra',
                                                v_dados || jsonb_build_object('nome_ambiguo', true), v_agora);
          continue;
        end if;
      end if;

      -- 7. O texto (P4). O painel e o pátio linha a linha: a linha que dá 22023 sai com fora_por = 'texto', e o resto segue.
      --    22023 no cabeçalho, em todas as linhas ou em outro tipo: recusada/texto.
      begin
        if v_s.tipo = any (c_ao_cliente) then
          v_client := nullif(v_dados ->> 'client_id', '')::uuid;
          if v_s.tipo = 'parceiro_aviso_cliente' then
            select pa.sigla into v_sigla from public.parceiros pa where pa.id = nullif(v_dados ->> 'parceiro_id', '')::uuid;
            v_var := (case when v_dados ->> 'papel' in ('contratante', 'pagador') then 'contrata_' else '' end)
                     || (case when public._cliente_ja_apresentada(v_client, v_s.chave, v_hoje) then 'seguinte' else 'com_apresentacao' end);
            v_campos := jsonb_build_object('nome', public._retorno_nome(v_client), 'sigla', v_sigla,
                                           'bem', public._parceiro_bem_do_par(v_client, nullif(v_dados ->> 'parceiro_id', '')::uuid),
                                           'papel', v_dados ->> 'papel');
          else
            v_campos := case when v_var = 'com_nome' then jsonb_build_object('nome', public._retorno_nome(v_client)) else '{}'::jsonb end;
          end if;
          v_guardar := jsonb_build_object('nome', v_campos ->> 'nome');
          v_texto := public._parceiro_texto(v_s.tipo, v_var, v_campos);

        elsif v_s.tipo in ('parceiro_painel', 'parceiro_patio') and v_var is distinct from 'vazio' then
          if v_s.tipo = 'parceiro_painel' then
            v_var := 'padrao';
            v_dia := coalesce(case when coalesce(v_dados ->> 'dia', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then (v_dados ->> 'dia')::date end,
                              (select pp.dia from public.parceiro_paineis pp
                                where coalesce(v_dados ->> 'painel_id', '') ~ '^[0-9a-f-]{36}$' and pp.id = (v_dados ->> 'painel_id')::uuid),
                              v_hoje);
            -- o rodapé, uma vez por semana a cada número
            v_rodape := not exists (select 1 from public.retorno_saidas o
                                     where o.emissor = 'parceiro' and o.tipo = 'parceiro_painel' and o.chave = v_s.chave and o.id <> v_s.id
                                       and coalesce((o.dados ->> 'rodape')::boolean, false)
                                       and o.estado = any (c_contam)
                                       and o.decidida_em <= v_agora
                                       and o.decidida_em > v_agora - v_cfg.parceiro_rodape_intervalo);
          else
            v_var := 'direto';
            v_dia := v_hoje;
            v_rodape := false;
          end if;
          v_painel := public._parceiro_painel_texto(v_s.tipo, v_var, v_dados -> 'linhas', 0, v_dia, v_rodape);
          v_texto := v_painel ->> 'texto';
          v_item_linhas := v_painel -> 'item_linhas';
          v_dados := v_dados || jsonb_build_object(
            'linhas', v_painel -> 'linhas',
            'linhas_cortadas', v_painel -> 'cortadas',
            'mais', v_painel -> 'mais',
            'dia', v_dia,
            'rodape', v_rodape,
            'linhas_fora', coalesce(v_dados -> 'linhas_fora', '[]'::jsonb) || (v_painel -> 'fora'),
            -- as listas gravadas são sempre as linhas que ficaram no texto
            'os_ids', (select coalesce(jsonb_agg(x -> 'service_order_id' order by (x ->> 'k')::integer), '[]'::jsonb)
                         from jsonb_array_elements(v_painel -> 'linhas') x),
            'interessado_ids', (select coalesce(jsonb_agg(x -> 'interessado_id' order by (x ->> 'k')::integer), '[]'::jsonb)
                                  from jsonb_array_elements(v_painel -> 'linhas') x));
          if v_s.tipo = 'parceiro_painel' and coalesce(v_dados ->> 'painel_id', '') ~ '^[0-9a-f-]{36}$' then
            perform public._parceiro_painel_marcar((v_dados ->> 'painel_id')::uuid, v_painel -> 'fora');
          end if;

        elsif v_s.tipo = 'parceiro_patio' then
          v_texto := public._parceiro_texto('parceiro_patio', 'vazio', '{}'::jsonb);

        elsif v_s.tipo = 'parceiro_pausa' then
          v_texto := public._parceiro_texto('parceiro_pausa', v_var, '{}'::jsonb);

        elsif v_s.tipo = 'parceiro_eco' then
          select so.vessel_id, oi.client_id into v_so
            from public.os_interessados oi join public.service_orders so on so.id = oi.service_order_id
           where oi.id = (v_dados -> 'interessado_ids' ->> 0)::uuid;
          v_texto := public._parceiro_texto('parceiro_eco', v_var, jsonb_build_object(
                       'bem', public._parceiro_bem(v_so.vessel_id), 'cliente', public._parceiro_nome_curto(v_so.client_id)));

        else
          -- Os textos com o prefixo {comigo}{pessoa}: a apresentação na 1ª mensagem ao número, depois o "Oi, Carla!".
          v_nomes := public._parceiro_nomes_do_contexto(
                       v_parceiro,
                       array(select oi.client_id
                               from jsonb_array_elements_text(case when jsonb_typeof(v_dados -> 'interessado_ids') = 'array'
                                                                    then v_dados -> 'interessado_ids' else '[]'::jsonb end) with ordinality u(id, o)
                               join public.os_interessados oi on oi.id = u.id::uuid
                              order by u.o),
                       v_pessoa);
          v_campos := jsonb_build_object('abertura', public._parceiro_abertura(v_numero, v_nomes -> 'nomes_de_outros', v_agora),
                                         'nomes_de_outros', v_nomes -> 'nomes_de_outros', 'parceiro_id', v_parceiro);
          if v_s.tipo in ('parceiro_recibo', 'parceiro_coleta') and v_var in ('padrao', 'veiculo_nome', 'orcamento') then
            -- o prazo falado, sem hora exata, visto de hoje
            v_pz := public._retorno_prazo(greatest(coalesce(v_ab.aberta_em, v_agora), v_agora), v_s.chave);
            v_campos := v_campos || jsonb_build_object('quando', public._retorno_quando((v_pz ->> 'dia')::date, v_hoje),
                                                       'hora', v_pz ->> 'hora');
            v_guardar := v_guardar || jsonb_build_object('quando', v_campos ->> 'quando', 'hora', v_campos ->> 'hora');
          end if;
          if (v_s.tipo = 'parceiro_coleta' and v_var = 'whatsapp') or (v_s.tipo = 'parceiro_recibo' and v_var = 'orcamento') then
            select * into v_ped from public.parceiro_pedidos pp
             where coalesce(v_dados ->> 'pedido_id', '') ~ '^[0-9a-f-]{36}$' and pp.id = (v_dados ->> 'pedido_id')::uuid;
            if v_ped.id is null then
              select * into v_ped from public.parceiro_pedidos pp where pp.abertura_id = v_s.abertura_id;
            end if;
            v_campos := v_campos || jsonb_strip_nulls(jsonb_build_object('primeiro_nome', nullif(btrim(v_ped.primeiro_nome), '')));
            if v_s.tipo = 'parceiro_recibo' then
              -- o bem do que a própria parceira disse: motorhome, trailer ou camper; senão veículo
              v_campos := v_campos || jsonb_build_object('bem',
                case when public._texto_simples(btrim(coalesce(v_ped.veiculo, ''))) in ('motorhome', 'trailer', 'camper')
                     then public._texto_simples(btrim(v_ped.veiculo)) else 'veículo' end);
            end if;
            v_guardar := v_guardar || jsonb_strip_nulls(jsonb_build_object('primeiro_nome', v_campos ->> 'primeiro_nome',
                                                                           'pedido_id', v_ped.id));
          elsif v_s.tipo = 'parceiro_recado' then
            v_campos := v_campos || jsonb_build_object('nome',
              case when coalesce((v_nomes ->> 'pessoa_ok')::boolean, false) then v_nomes ->> 'nome_permitido' end);
          elsif v_s.tipo = 'parceiro_repassar' then
            select so.vessel_id, oi.client_id into v_so
              from public.os_interessados oi join public.service_orders so on so.id = oi.service_order_id
             where oi.id = (v_dados -> 'interessado_ids' ->> 0)::uuid;
            v_campos := v_campos || jsonb_build_object(
              'primeiro_nome', coalesce(nullif(btrim(v_dados ->> 'primeiro_nome'), ''),
                                        public._agenda_nome_curto(public._parceiro_nome_curto(v_so.client_id))),
              'bem', public._parceiro_bem(v_so.vessel_id));
            v_guardar := v_guardar || jsonb_build_object('primeiro_nome', v_campos ->> 'primeiro_nome');
          end if;

          -- O bloco do pátio no recibo: até 5 linhas, a que dá 22023 sai, e o mesmo "E mais".
          if v_s.tipo = 'parceiro_recibo' and coalesce((v_dados ->> 'bloco_patio')::boolean, false) then
            v_lin := public._parceiro_linhas_texto('parceiro_patio', v_dados -> 'bloco');
            v_k := jsonb_array_length(v_lin -> 'textos');
            v_dados := v_dados || jsonb_build_object('linhas_fora', coalesce(v_dados -> 'linhas_fora', '[]'::jsonb) || (v_lin -> 'fora'));
            if v_k = 0 then
              v_dados := v_dados || jsonb_build_object('bloco_patio', false, 'bloco', '[]'::jsonb, 'os_ids', '[]'::jsonb,
                                                       'interessado_ids', '[]'::jsonb);
            else
              v_campos := v_campos || jsonb_build_object(
                'bloco_linhas', (select jsonb_agg(t.x order by t.o) from jsonb_array_elements(v_lin -> 'textos') with ordinality t(x, o) where t.o <= 5),
                'bloco_mais', greatest(v_k - 5, 0));
              v_dados := v_dados || jsonb_build_object(
                'bloco', (select jsonb_agg(t.x order by t.o) from jsonb_array_elements(v_lin -> 'linhas') with ordinality t(x, o) where t.o <= 5),
                'bloco_cortadas', (select coalesce(jsonb_agg(t.x - 'k' order by t.o), '[]'::jsonb)
                                     from jsonb_array_elements(v_lin -> 'linhas') with ordinality t(x, o) where t.o > 5),
                'os_ids', (select jsonb_agg(t.x -> 'service_order_id' order by t.o) from jsonb_array_elements(v_lin -> 'linhas') with ordinality t(x, o) where t.o <= 5),
                'interessado_ids', (select jsonb_agg(t.x -> 'interessado_id' order by t.o) from jsonb_array_elements(v_lin -> 'linhas') with ordinality t(x, o) where t.o <= 5));
            end if;
          end if;

          v_texto := public._parceiro_texto(v_s.tipo, v_var, v_campos);
        end if;
      exception when sqlstate '22023' then
        perform public._parceiro_pegar_fechar(v_s.id, 'recusada', 'texto',
                                              v_dados || jsonb_build_object('texto_erro', left(sqlerrm, 200)), v_agora);
        perform public._retorno_log('pegar', 'parceiro_pegar: ' || sqlerrm, 'error',
                                    jsonb_build_object('saida', v_s.id, 'sqlstate', '22023'));
        continue;
      end;
      v_dados := v_dados || jsonb_strip_nulls(v_guardar);

      -- 8. O modo efetivo do parceiro. A saída com chave real que cai em sombra troca a chave (a real fica livre).
      v_modo := public._parceiro_modo_efetivo(v_s.id, v_agora);
      v_ligado := v_modo ->> 'modo' = 'ligado';
      if v_ligado then
        v_dados := v_dados - 'sombra_motivo';
      else
        v_dados := v_dados || jsonb_build_object('sombra_motivo', coalesce(v_modo ->> 'motivo', 'parceiro_modo'));
        if v_s.dedupe_key !~ ':sombra(:|$)' then
          update public.retorno_saidas s
             set dedupe_key = s.dedupe_key || ':sombra:' || s.id, atualizada_em = now()
           where s.id = v_s.id
           returning * into v_s;
        end if;
      end if;

      -- 8a. "Segura tudo" não queima a saída: espera a hora do segura. O painel só dentro do próprio dia.
      if v_cfg.segura_tudo_ate is not null and v_cfg.segura_tudo_ate > v_agora then
        if v_s.classe = 'resumo_parceiro'
           and ((v_cfg.segura_tudo_ate at time zone c_fuso)::date <> v_hoje
                or (v_cfg.segura_tudo_ate at time zone c_fuso)::time >= v_cfg.painel_janela_fim) then
          perform public._parceiro_pegar_fechar(v_s.id, 'recusada', 'segura_tudo', v_dados, v_agora);
        else
          update public.retorno_saidas s
             set enviar_em = v_cfg.segura_tudo_ate, dados = s.dados || jsonb_build_object('segurada', true), atualizada_em = now()
           where s.id = v_s.id;
        end if;
        continue;
      end if;

      -- 9. O canal, simulando na sombra. Ligada, trava antes a linha de configuração (R1-11).
      if v_ligado then
        perform 1 from public.retorno_config c where c.id for update;
      end if;
      v_canal := public.canal_pode_enviar(v_s.phone_normalized, v_s.classe, v_s.origem, v_agora, not v_ligado, v_s.tipo);
      if not coalesce((v_canal ->> 'pode')::boolean, false) then
        -- fora da janela, espaçamento e teto das iniciadas com hora futura só reagendam; o painel, só dentro do dia
        if v_canal ->> 'motivo' in ('fora_da_janela', 'espacamento', 'teto_iniciadas')
           and (v_canal ->> 'enviar_em')::timestamptz > v_agora
           and (v_s.classe is distinct from 'resumo_parceiro'
                or (((v_canal ->> 'enviar_em')::timestamptz at time zone c_fuso)::date = v_hoje)) then
          update public.retorno_saidas s
             set enviar_em = (v_canal ->> 'enviar_em')::timestamptz, atualizada_em = now()
           where s.id = v_s.id;
          continue;
        end if;
        update public.retorno_saidas s
           set estado = 'recusada', motivo = coalesce(v_canal ->> 'motivo', 'canal'), variante = left(v_var, 40),
               texto = v_texto, dados = v_dados, decidida_em = v_agora, processando_ate = null, atualizada_em = now()
         where s.id = v_s.id;
        continue;
      end if;

      -- 10. A reserva: preparada (sombra) ou enviando (ligada), por 2 min.
      update public.retorno_saidas s
         set estado = case when v_ligado then 'enviando' else 'preparada' end,
             texto = v_texto, dados = v_dados, variante = left(v_var, 40), decidida_em = v_agora,
             processando_ate = v_agora + interval '2 minutes',
             modo = case when v_ligado then 'ligado' else 'sombra' end,
             atualizada_em = now()
       where s.id = v_s.id
       returning * into v_s;
      if v_ligado then
        -- o espaçamento global entre saídas automáticas, sorteado como no retorno_pegar (R1-11)
        update public.retorno_config c
           set proximo_envio_em = v_agora + make_interval(secs => (c.espaco_min_s
                                    + floor(random() * (c.espaco_max_s - c.espaco_min_s + 1)))::double precision)
         where c.id;
      end if;

      -- O item, com o contexto do validador montado pelo banco.
      v_ctx := public._parceiro_contexto_do_validador(v_s.id, v_texto, v_dados, v_agora);
      if v_item_linhas is not null then
        v_ctx := public._parceiro_trechos_por_linha(v_ctx);
      end if;
      return jsonb_build_object(
        'saida_id', v_s.id,
        'tentativa', v_s.tentativa,
        'dedupe_key', v_s.dedupe_key,
        'tipo', v_s.tipo,
        'variante', v_s.variante,
        'origem', v_s.origem,
        'classe', v_s.classe,
        'modo', v_s.modo,
        'phone', v_s.phone_normalized,
        'texto', v_s.texto,
        'validador', v_ctx)
        || case when v_item_linhas is not null then jsonb_build_object('linhas', v_item_linhas) else '{}'::jsonb end;
    exception when others then
      -- Erro num item nunca trava a fila: a volta é desfeita, a saída vira recusada/erro e a próxima segue.
      update public.retorno_saidas s
         set estado = 'recusada', motivo = 'erro', decidida_em = v_agora, processando_ate = null,
             dados = s.dados || jsonb_build_object('erro', jsonb_build_object('sqlstate', sqlstate, 'mensagem', left(sqlerrm, 200))),
             atualizada_em = now()
       where s.id = v_s.id;
      perform public._retorno_log('pegar', 'parceiro_pegar: ' || sqlerrm, 'error',
                                  jsonb_build_object('saida', v_s.id, 'sqlstate', sqlstate));
    end;
  end loop;
  return null;
end;
$$;

comment on function public.parceiro_pegar(timestamptz) is
  'Retorno F4 (C-PEGAR-P): a fila do parceiro, na ordem de P5.1: 1 número/pessoa/parceiro (parceiro_regra), 1a aviso ainda vale, 1b caso fechado ou respondido pelo dono (cancelada), 2 pausado, 3 segura_patio, 4 tetos (painel, eco, pátio, número e coleta), bloco P11 do recibo, 5 regra de ouro vínculo a vínculo (dados.visibilidade; a OS que caiu sai da linha; pátio sem linha vira vazio), 6 eco ouvido pelo cliente, 7 texto linha a linha (texto), 8 modo (sombra troca a chave), 8a segura tudo reagenda, 9 canal (fora da janela, espaçamento e teto das iniciadas reagendam), 10 reserva. parceiro_modo desligado: cancela tudo (parceiro_desligado). Formato do retorno_pegar, com linhas no painel e no pátio.';

revoke all on function public.parceiro_pegar(timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_pegar(timestamptz) to service_role;

-- ── 5. A linha reprovada pelo validador (P5.2) ─────────────────────────────────────────────────────────────────────────────

-- O validador da edge corta a linha, não o painel: tira as linhas reprovadas (p_ns: o número de cada uma no texto), grava
-- fora_por = 'validador' em dados.linhas_fora e em parceiro_paineis.linhas, tira os ids das listas, refaz o texto (o corte
-- anterior continua: "E mais" soma as já cortadas) e devolve {texto, linhas, validador}. Sem linha sobrando, ou saída que
-- não é painel nem pátio reservado: {caiu: true}.
create or replace function public.parceiro_saida_sem_linhas(p_saida uuid, p_ns integer[], p_regras jsonb,
                                                            p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_s public.retorno_saidas;
  v_dados jsonb;
  v_tiradas jsonb;
  v_restam jsonb;
  v_painel jsonb;
  v_ctx jsonb;
  v_dia date;
begin
  select * into v_s from public.retorno_saidas s where s.id = p_saida for update;
  if not found or v_s.emissor is distinct from 'parceiro' or v_s.estado not in ('preparada', 'enviando')
     or not (v_s.tipo = 'parceiro_painel' or (v_s.tipo = 'parceiro_patio' and v_s.variante = 'direto'))
     or jsonb_typeof(v_s.dados -> 'linhas') is distinct from 'array' then
    return jsonb_build_object('caiu', true, 'motivo', 'saida');
  end if;
  v_dados := v_s.dados;
  v_tiradas := (select coalesce(jsonb_agg((x - 'k') || jsonb_build_object(
                         'fora_por', 'validador',
                         'regras', (select r -> 'regras' from jsonb_array_elements(case when jsonb_typeof(p_regras) = 'array'
                                                                                          then p_regras else '[]'::jsonb end) r
                                     where (r ->> 'n') = (x ->> 'k') limit 1))
                       order by (x ->> 'k')::integer), '[]'::jsonb)
                  from jsonb_array_elements(v_dados -> 'linhas') x
                 where (x ->> 'k')::integer = any (coalesce(p_ns, '{}'::integer[])));
  v_restam := (select coalesce(jsonb_agg(x - 'k' order by (x ->> 'k')::integer), '[]'::jsonb)
                 from jsonb_array_elements(v_dados -> 'linhas') x
                where not ((x ->> 'k')::integer = any (coalesce(p_ns, '{}'::integer[]))));
  v_dados := v_dados || jsonb_build_object('linhas_fora', coalesce(v_dados -> 'linhas_fora', '[]'::jsonb) || v_tiradas);
  if coalesce(v_dados ->> 'painel_id', '') ~ '^[0-9a-f-]{36}$' then
    perform public._parceiro_painel_marcar((v_dados ->> 'painel_id')::uuid, v_tiradas);
  end if;

  if jsonb_array_length(v_restam) = 0 then
    update public.retorno_saidas s
       set dados = v_dados || jsonb_build_object('linhas', '[]'::jsonb, 'os_ids', '[]'::jsonb, 'interessado_ids', '[]'::jsonb),
           atualizada_em = now()
     where s.id = v_s.id;
    return jsonb_build_object('caiu', true, 'motivo', 'sem_linhas');
  end if;

  v_dia := coalesce(case when coalesce(v_dados ->> 'dia', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then (v_dados ->> 'dia')::date end,
                    (v_agora at time zone 'America/Sao_Paulo')::date);
  begin
    v_painel := public._parceiro_painel_texto(v_s.tipo, v_s.variante, v_restam,
                                              case when jsonb_typeof(v_dados -> 'linhas_cortadas') = 'array'
                                                   then jsonb_array_length(v_dados -> 'linhas_cortadas') else 0 end,
                                              v_dia, coalesce((v_dados ->> 'rodape')::boolean, false));
  exception when sqlstate '22023' then
    return jsonb_build_object('caiu', true, 'motivo', 'texto');
  end;
  v_dados := v_dados || jsonb_build_object(
    'linhas', v_painel -> 'linhas',
    'linhas_fora', coalesce(v_dados -> 'linhas_fora', '[]'::jsonb) || (v_painel -> 'fora'),
    'os_ids', (select coalesce(jsonb_agg(x -> 'service_order_id' order by (x ->> 'k')::integer), '[]'::jsonb)
                 from jsonb_array_elements(v_painel -> 'linhas') x),
    'interessado_ids', (select coalesce(jsonb_agg(x -> 'interessado_id' order by (x ->> 'k')::integer), '[]'::jsonb)
                          from jsonb_array_elements(v_painel -> 'linhas') x));
  update public.retorno_saidas s
     set texto = v_painel ->> 'texto', dados = v_dados, atualizada_em = now()
   where s.id = v_s.id;

  v_ctx := public._parceiro_trechos_por_linha(
             public._parceiro_contexto_do_validador(v_s.id, v_painel ->> 'texto', v_dados, v_agora));
  return jsonb_build_object('texto', v_painel ->> 'texto', 'linhas', v_painel -> 'item_linhas', 'validador', v_ctx);
end;
$$;

comment on function public.parceiro_saida_sem_linhas(uuid, integer[], jsonb, timestamptz) is
  'Retorno F4 (C-LINHAS, P5.2): tira do painel ou do pátio reservado as linhas que o validador reprovou (p_ns = o número da linha no texto), com fora_por validador em dados.linhas_fora e em parceiro_paineis.linhas, tira os ids das listas e refaz o texto. Devolve {texto, linhas, validador} ou {caiu: true}.';

revoke all on function public.parceiro_saida_sem_linhas(uuid, integer[], jsonb, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_saida_sem_linhas(uuid, integer[], jsonb, timestamptz) to service_role;

-- ── 6. A última trava, no instante do envio ────────────────────────────────────────────────────────────────────────────────

-- Chamada por retorno_saida_autorizada (o whatsapp-send confere toda origem retorno_*). Só pode com a saída do parceiro
-- enviando, ligada e dentro da reserva; o telefone dela; o modo do parceiro ligado agora; à parceira, o número confirmado,
-- de pessoa e parceiro ativos; o aviso ao cliente ainda valendo; no tipo de citação, cada vínculo do parceiro dono do
-- número (par OS × parceiro) passando na regra de ouro de novo; sem bloqueio do canal; dentro da janela da classe.
-- Qualquer exceção: {"pode": false, "motivo": "erro"}.
create or replace function public.parceiro_saida_autorizada(p_saida uuid, p_fone text, p_agora timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_s public.retorno_saidas;
  v_modo jsonb;
  v_parceiro uuid;
  v_ids uuid[];
  v_os uuid[];
  v_citacao boolean;
  v_bloqueio text;
  v_janela jsonb;
  i integer;
begin
  begin
    select * into v_s from public.retorno_saidas s where s.id = p_saida;
    if not found then
      return jsonb_build_object('pode', false, 'motivo', 'sem_saida');
    end if;
    if v_s.emissor is distinct from 'parceiro' then
      return jsonb_build_object('pode', false, 'motivo', 'emissor');
    end if;
    if v_s.estado is distinct from 'enviando' then
      return jsonb_build_object('pode', false, 'motivo', 'estado');
    end if;
    if v_s.modo is distinct from 'ligado' then
      return jsonb_build_object('pode', false, 'motivo', 'saida_em_sombra');
    end if;
    if v_s.processando_ate is null or v_s.processando_ate <= v_agora then
      return jsonb_build_object('pode', false, 'motivo', 'reserva_vencida');
    end if;
    if not coalesce(public._mesmo_telefone(p_fone, v_s.phone_normalized), false) then
      return jsonb_build_object('pode', false, 'motivo', 'telefone');
    end if;
    v_modo := public._parceiro_modo_efetivo(v_s.id, v_agora);
    if v_modo ->> 'modo' is distinct from 'ligado' then
      return jsonb_build_object('pode', false, 'motivo', coalesce(v_modo ->> 'motivo', 'parceiro_modo'));
    end if;

    if v_s.tipo in ('parceiro_aviso_cliente', 'parceiro_nao_mp_ok') then
      if v_s.tipo = 'parceiro_aviso_cliente' and public._parceiro_aviso_ainda_vale(v_s.id, v_agora) is not null then
        return jsonb_build_object('pode', false, 'motivo', 'parceiro_regra');
      end if;
    else
      select p.parceiro_id into v_parceiro
        from public.parceiro_numeros n
        join public.parceiro_pessoas p on p.id = n.pessoa_id and p.ativo
        join public.parceiros pa on pa.id = p.parceiro_id and pa.ativo
       where coalesce(v_s.dados ->> 'numero_id', '') ~ '^[0-9a-f-]{36}$'
         and n.id = (v_s.dados ->> 'numero_id')::uuid
         and n.situacao = 'confirmado';
      if v_parceiro is null then
        return jsonb_build_object('pode', false, 'motivo', 'parceiro_regra');
      end if;
      -- O recibo só é citação com o bloco do pátio.
      v_citacao := v_s.tipo in ('parceiro_painel', 'parceiro_eco', 'parceiro_repassar')
                   or (v_s.tipo = 'parceiro_patio' and v_s.variante is distinct from 'vazio')
                   or (v_s.tipo = 'parceiro_recibo' and coalesce((v_s.dados ->> 'bloco_patio')::boolean, false));
      if v_citacao then
        v_ids := array(select x::uuid from jsonb_array_elements_text(case when jsonb_typeof(v_s.dados -> 'interessado_ids') = 'array'
                                                                           then v_s.dados -> 'interessado_ids' else '[]'::jsonb end) x);
        v_os := array(select x::uuid from jsonb_array_elements_text(case when jsonb_typeof(v_s.dados -> 'os_ids') = 'array'
                                                                          then v_s.dados -> 'os_ids' else '[]'::jsonb end) x);
        if cardinality(v_ids) = 0 or cardinality(v_ids) is distinct from cardinality(v_os) then
          return jsonb_build_object('pode', false, 'motivo', 'parceiro_regra');
        end if;
        for i in 1 .. cardinality(v_ids) loop
          if not exists (select 1 from public.os_interessados oi
                          where oi.id = v_ids[i] and oi.parceiro_id = v_parceiro and oi.service_order_id = v_os[i])
             or (public.parceiro_os_visivel(v_ids[i], v_agora) ->> 'visivel')::boolean is not true then
            return jsonb_build_object('pode', false, 'motivo', 'parceiro_regra');
          end if;
        end loop;
      end if;
    end if;

    v_bloqueio := public.canal_bloqueado(p_fone);
    if v_bloqueio is not null then
      return jsonb_build_object('pode', false, 'motivo', v_bloqueio);
    end if;
    v_janela := public._retorno_janela(v_s.classe, v_agora, v_s.chave);
    if not coalesce((v_janela ->> 'dentro')::boolean, false) then
      return jsonb_build_object('pode', false, 'motivo', 'fora_da_janela');
    end if;
    return jsonb_build_object('pode', true, 'motivo', null);
  exception when others then
    return jsonb_build_object('pode', false, 'motivo', 'erro');
  end;
end;
$$;

comment on function public.parceiro_saida_autorizada(uuid, text, timestamptz) is
  'Retorno F4 (C-AUT-P): {"pode", "motivo"} da saída do parceiro no instante do envio: enviando, ligada, na reserva, o telefone dela, o modo do parceiro ligado, o número confirmado (à parceira), o aviso ainda valendo (parceiro_regra), cada vínculo citado do parceiro do número passando na regra de ouro (parceiro_regra), sem bloqueio e dentro da janela. Exceção = erro.';

revoke all on function public.parceiro_saida_autorizada(uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_saida_autorizada(uuid, text, timestamptz) to service_role;

-- ── 6. Gerado do corpo vigente, com os trechos -- F4 ───────────────────────────────────────────────────────────────────

create or replace function public._retorno_janela(p_classe text, p_agora timestamptz, p_chave text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_cfg public.retorno_config := public._retorno_cfg();
  v_local timestamp;
  v_t time;
  v_d date;
  v_dia date;
  v_fim time;
begin
  -- Sem a linha de configuração, sem hora ou classe que a janela não conhece: fora, sem próxima abertura.
  if v_cfg.id is null or p_agora is null
     or p_classe is null or p_classe not in ('resposta_imediata', 'resposta_atrasada', 'aviso', 'resumo_parceiro')
     -- F4 (P5): as duas classes do parceiro só existem com a F4 fora de 'desligado'; desligada, a janela é a de antes.
     or (p_classe in ('aviso', 'resumo_parceiro') and v_cfg.parceiro_modo = 'desligado') then
    return jsonb_build_object('dentro', false, 'enviar_em', null);
  end if;

  v_local := p_agora at time zone c_fuso;
  v_t := v_local::time;
  v_d := v_local::date;

  if p_classe = 'resposta_imediata' then
    -- K3: todo dia, inclusive domingo e feriado; o fim é exclusivo (22:00 já está fora).
    if v_t >= v_cfg.cliente_resposta_direta_inicio and v_t < v_cfg.cliente_resposta_direta_fim then
      return jsonb_build_object('dentro', true, 'enviar_em', null);
    end if;
    return jsonb_build_object('dentro', false, 'enviar_em', public._retorno_proxima_manha(p_agora, p_chave));
  end if;

  -- F4 (P5): resumo_parceiro (o painel): seg–sex em dia útil, de painel_hora a painel_janela_fim (o fim é exclusivo).
  -- Fora: painel_hora de hoje, se ainda não passou; senão nulo, e o painel do dia cai (nunca vale amanhã).
  if p_classe = 'resumo_parceiro' then
    if extract(isodow from v_d) between 1 and 5 and public.agenda_dia_util(v_d) then
      if v_t >= v_cfg.painel_hora and v_t < v_cfg.painel_janela_fim then
        return jsonb_build_object('dentro', true, 'enviar_em', null);
      end if;
      if v_t < v_cfg.painel_hora then
        return jsonb_build_object('dentro', false, 'enviar_em', (v_d + v_cfg.painel_hora) at time zone c_fuso);
      end if;
    end if;
    return jsonb_build_object('dentro', false, 'enviar_em', null);
  end if;

  -- F4 (P5): aviso (o aviso ao cliente, o eco, a ativação e o repassar) tem a janela da resposta_atrasada, abaixo.
  -- resposta_atrasada: o fim da janela do dia (nulo no domingo e no feriado).
  v_fim := case
    when extract(isodow from v_d) = 7 or public.agenda_feriado(v_d) is not null then null
    when extract(isodow from v_d) = 6 then v_cfg.atrasada_sabado_fim
    else v_cfg.atrasada_fim
  end;
  if v_fim is not null and v_t >= v_cfg.atrasada_inicio and v_t < v_fim then
    return jsonb_build_object('dentro', true, 'enviar_em', null);
  end if;

  -- A próxima abertura: hoje, se ainda não deu atrasada_inicio e hoje é permitido; senão o próximo dia
  -- que não é domingo nem feriado (até 7 dias à frente).
  for i in 0 .. 7 loop
    v_dia := v_d + i;
    if extract(isodow from v_dia) <> 7 and public.agenda_feriado(v_dia) is null
       and (i > 0 or v_t < v_cfg.atrasada_inicio) then
      return jsonb_build_object('dentro', false, 'enviar_em', (v_dia + v_cfg.atrasada_inicio) at time zone c_fuso);
    end if;
  end loop;
  return jsonb_build_object('dentro', false, 'enviar_em', null);
end;
$$;

create or replace function public.canal_pode_enviar(p_fone text, p_classe text, p_origem text,
                                                    p_agora timestamptz default now(),
                                                    p_simular boolean default false,
                                                    p_tipo text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_cfg public.retorno_config := public._retorno_cfg();
  v_agora timestamptz := coalesce(p_agora, now());
  v_simular boolean := coalesce(p_simular, false);
  v_chave text := public._agenda_chave_telefone(p_fone);
  v_bloqueio text;
  v_janela jsonb;
  v_desde timestamptz;
  v_n bigint;
begin
  -- 1. Sem a linha de configuração, ou o retorno desligado: nada sai.
  if v_cfg.id is null or v_cfg.modo = 'desligado' then
    return jsonb_build_object('pode', false, 'motivo', 'sem_config', 'enviar_em', null);
  end if;

  -- 2. Só as duas classes de resposta (as do pedido 7 nunca passam aqui).
  --    F4 (P5): aviso e resumo_parceiro passam só com a origem do parceiro (retorno_parceiro, retorno_aviso) e com a F4
  --    fora de 'desligado'; sem isso continuam classe_nao_suportada, como na F1.
  if p_classe is null or p_classe not in ('resposta_imediata', 'resposta_atrasada', 'aviso', 'resumo_parceiro')
     or (p_classe in ('aviso', 'resumo_parceiro')
         and (v_cfg.parceiro_modo = 'desligado' or p_origem is null or p_origem not in ('retorno_parceiro', 'retorno_aviso'))) then
    return jsonb_build_object('pode', false, 'motivo', 'classe_nao_suportada', 'enviar_em', null);
  end if;

  -- 3. Sem os 8 dígitos não há a quem mandar.
  if v_chave is null then
    return jsonb_build_object('pode', false, 'motivo', 'sem_numero', 'enviar_em', null);
  end if;

  -- 4. A equipe, pelo mesmo telefone (8 dígitos e o mesmo DDD, como em quem_escreve).
  if exists (select 1 from public.app_users u
              where u.active and (public._mesmo_telefone(p_fone, u.phone_normalized) or public._mesmo_telefone(p_fone, u.phone)))
     or exists (select 1 from public.payees p where p.active and public._mesmo_telefone(p_fone, p.phone)) then
    return jsonb_build_object('pode', false, 'motivo', 'equipe', 'enviar_em', null);
  end if;

  -- 5. Bloqueio da F0a. O parar só sai confirmando o opt-out recém-gravado (e nunca sem ele).
  v_bloqueio := public.canal_bloqueado(p_fone);
  if p_tipo = 'parar' then
    if not coalesce(public._retorno_parar_permitido(v_chave, v_agora), false) then
      return jsonb_build_object('pode', false, 'motivo', coalesce(v_bloqueio, 'canal'), 'enviar_em', null);
    end if;
  elsif v_bloqueio is not null then
    return jsonb_build_object('pode', false, 'motivo', v_bloqueio, 'enviar_em', null);
  end if;

  -- 6. O número que o dono marcou como pessoal.
  if exists (select 1 from public.whatsapp_leads l
              where l.lead_tipo = 'pessoal' and public._agenda_chave_telefone(l.phone_normalized) = v_chave) then
    return jsonb_build_object('pode', false, 'motivo', 'pessoal', 'enviar_em', null);
  end if;

  -- 7. "Segura tudo".
  if v_cfg.segura_tudo_ate is not null and v_cfg.segura_tudo_ate > v_agora then
    return jsonb_build_object('pode', false, 'motivo', 'segura_tudo', 'enviar_em', null);
  end if;

  -- 8. Disjuntor: só sai a resposta imediata a quem escreveu.
  if v_cfg.so_reativo and p_classe <> 'resposta_imediata' then
    return jsonb_build_object('pode', false, 'motivo', 'so_reativo', 'enviar_em', null);
  end if;

  -- 9. A janela da classe.
  v_janela := public._retorno_janela(p_classe, v_agora, v_chave);
  if not coalesce((v_janela ->> 'dentro')::boolean, false) then
    return jsonb_build_object('pode', false, 'motivo', 'fora_da_janela', 'enviar_em', v_janela -> 'enviar_em');
  end if;

  -- 10. O teto da HBR: as respostas decididas desde 00:00 de Brasília até agora.
  v_desde := ((v_agora at time zone c_fuso)::date)::timestamp at time zone c_fuso;
  -- F4 (P5): teto das iniciadas pela HBR (12 por dia): aviso e painel desta tabela, mais o que a agenda já mandou hoje.
  if p_classe in ('aviso', 'resumo_parceiro') then
    select (select count(*) from public.retorno_saidas s
             where s.classe in ('aviso', 'resumo_parceiro') and s.decidida_em >= v_desde and s.decidida_em <= v_agora
               and (s.estado in ('enviada', 'incerta', 'enviando') or (v_simular and s.estado in ('sombra', 'preparada'))))
         + (select count(*) from public.agenda_cliente_mensagens m where m.enviada_em >= v_desde and m.enviada_em <= v_agora)
      into v_n;
    if v_n >= v_cfg.iniciadas_dia_max then
      -- O aviso espera o dia seguinte; o painel do dia não vale amanhã.
      return jsonb_build_object('pode', false, 'motivo', 'teto_iniciadas', 'enviar_em',
        (case when p_classe = 'aviso'
              then public._retorno_janela('aviso', (((v_agora at time zone c_fuso)::date + 1)::timestamp at time zone c_fuso), v_chave) -> 'enviar_em'
         end));
    end if;
  end if;
  -- F4 (P5): o teto das respostas vale só para resposta_imediata e resposta_atrasada: aviso e painel obedecem só ao das
  -- iniciadas, e nunca caem em teto_dia. A resposta ao parceiro (resposta_imediata) conta aqui, como qualquer resposta.
  if p_classe in ('resposta_imediata', 'resposta_atrasada') then
    select count(*) into v_n
      from public.retorno_saidas s
     where s.classe in ('resposta_imediata', 'resposta_atrasada')
       and s.decidida_em >= v_desde
       and s.decidida_em <= v_agora
       and (s.estado in ('enviada', 'incerta', 'enviando')
            or (v_simular and s.estado in ('sombra', 'preparada')));
    if v_n >= v_cfg.respostas_dia_max then
      return jsonb_build_object('pode', false, 'motivo', 'teto_dia', 'enviar_em', null);
    end if;
  end if;

  -- 11. O espaçamento global entre saídas automáticas (a simulação não reserva, então não espera).
  if not v_simular and v_cfg.proximo_envio_em is not null and v_cfg.proximo_envio_em > v_agora then
    return jsonb_build_object('pode', false, 'motivo', 'espacamento', 'enviar_em', v_cfg.proximo_envio_em);
  end if;

  -- 12.
  return jsonb_build_object('pode', true, 'motivo', null, 'enviar_em', null);
end;
$$;

create or replace function public.retorno_pegar(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_recibos constant text[] := array['recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo'];
  c_contam constant text[] := array['sombra', 'preparada', 'enviando', 'enviada', 'incerta'];
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date;
  v_cfg public.retorno_config;
  v_volta integer;
  v_s public.retorno_saidas;
  v_ab public.retorno_aberturas;
  v_ch jsonb;
  v_pz jsonb;
  v_pd jsonb;
  v_desde timestamptz;
  v_dados jsonb;
  v_campos jsonb;
  v_nome text;
  v_var text;
  v_texto text;
  v_modo jsonb;
  v_ligado boolean;
  v_canal jsonb;
  v_pretendido boolean;
  v_ouviu boolean;
  v_volta_atraso boolean;
  v_topo date;
  v_do_bem text;
  v_apos_saudacao boolean;
  v_ctx jsonb;
  v_m jsonb;           -- F2
  v_f2 boolean;        -- F2
  v_alt text;          -- F2
  v_acorde boolean;    -- F2 (P14)
begin
  v_cfg := public._retorno_cfg();
  if v_cfg.id is null or v_cfg.modo = 'desligado' then
    return null;
  end if;

  for v_volta in 1 .. 10 loop
    -- 1. Uma saída devida, fora de reserva, que só a edge decide. Duas execuções nunca pegam a mesma.
    select * into v_s
      from public.retorno_saidas s
     where s.estado = 'agendada'
       and s.enviar_em <= v_agora
       and (s.processando_ate is null or s.processando_ate < v_agora)
       and s.tipo not in ('acorde', 'cadastro_provisorio', 'fila')
       and s.emissor <> 'parceiro'   -- F4 (P5): a saída do parceiro é do parceiro_pegar
     order by s.enviar_em, s.id
     limit 1
     for update skip locked;
    if not found then
      return null;
    end if;

    begin
      -- 2. Conferir de novo, agora.
      v_ch := public._retorno_checar_antes(v_s.id, v_agora);
      if v_ch ->> 'acao' = 'cancelar' then
        update public.retorno_saidas s
           set estado = 'cancelada', motivo = v_ch ->> 'motivo', decidida_em = v_agora, processando_ate = null,
               atualizada_em = now()
         where s.id = v_s.id and s.estado = 'agendada';
        if v_ch ->> 'motivo' = 'respondida_pelo_dono' then
          update public.retorno_aberturas a
             set respondida_em = coalesce(a.respondida_em, (v_ch -> 'resposta' ->> 'respondida_em')::timestamptz),
                 atualizada_em = now()
           where a.id = v_s.abertura_id;
        end if;
        continue;
      elsif v_ch ->> 'acao' = 'adiar' then
        update public.retorno_saidas s
           set enviar_em = (v_ch ->> 'enviar_em')::timestamptz,
               dados = s.dados || jsonb_build_object('adiada', jsonb_build_object('motivo', v_ch ->> 'motivo', 'em', v_agora)),
               atualizada_em = now()
         where s.id = v_s.id;
        continue;
      end if;

      -- A triagem pode ter mexido na saída (o risco que apareceu) e no caso: lê de novo.
      select * into v_s from public.retorno_saidas s where s.id = v_s.id;
      select * into v_ab from public.retorno_aberturas a where a.id = v_s.abertura_id;

      -- 3. Compor.
      v_dados := v_s.dados;
      v_nome := case when v_ab.papel = 'cliente' then public._retorno_nome(v_ab.client_id) end;
      v_pretendido := v_cfg.modo = 'ligado' and v_s.tipo = any (v_cfg.tipos_ligados);
      v_pz := null;
      v_campos := '{}'::jsonb;
      v_topo := null;
      v_m := null;       -- F2
      v_f2 := false;     -- F2
      v_acorde := false; -- F2 (P14)

      if v_s.tipo = any (c_recibos) or v_s.tipo = 'saudacao_numero_novo' then
        -- O prazo é do banco, gravado na 1ª composição (a mensagem da noite guarda a promessa da faixa noite).
        -- O guardado que já venceu é calculado de novo: nunca promete hora passada.
        if jsonb_typeof(v_dados -> 'prazo') = 'object' then
          v_pz := v_dados -> 'prazo';
          if (v_pz ->> 'prometido_ate')::timestamptz <= v_agora then
            v_pz := null;
          end if;
        end if;
        if v_pz is null then
          -- F2 (P14): a pressa, com vaga de acorde, sai junto com o recibo e promete o fechamento de hoje. Sem vaga, a faixa normal.
          if coalesce((v_ab.sinais ->> 'pressa')::boolean, false)
             and v_s.tipo <> 'saudacao_numero_novo'
             and v_cfg.modo = 'ligado' and 'acorde' = any (v_cfg.tipos_ligados)
             and (v_agora at time zone c_fuso)::time >= time '08:00' and (v_agora at time zone c_fuso)::time < time '20:00' then
            v_acorde := public._retorno_acordar_agora(v_ab.id, 'pressa', v_agora);
          end if;
          v_pz := public._retorno_prazo(greatest(v_ab.aberta_em, v_agora), v_ab.chave,
                                        coalesce((v_ab.sinais ->> 'pressa')::boolean, false), v_acorde);
        end if;
        v_dados := v_dados || jsonb_build_object('prazo', v_pz);
        -- Fora da janela K3: o recibo espera a manhã (com o prazo guardado).
        if (v_pz ->> 'recibo_em')::timestamptz > v_agora then
          update public.retorno_saidas s
             set enviar_em = (v_pz ->> 'recibo_em')::timestamptz, dados = v_dados, atualizada_em = now()
           where s.id = v_s.id;
          continue;
        end if;
        -- O recibo sai agora: "hoje", "amanhã" e o outro dia são vistos de HOJE, não do dia em que o prazo foi
        -- guardado (o composto às 21:59, "amanhã até as 10h", que o canal levou à manhã seguinte diz "hoje até
        -- as 10h"). A promessa (dia, hora, prometido_ate) não muda. No prazo recém-calculado nada muda: ref já
        -- é hoje.
        v_pz := v_pz || jsonb_build_object('ref', v_hoje,
                                           'quando', public._retorno_quando((v_pz ->> 'dia')::date, v_hoje),
                                           'outro_dia', (v_pz ->> 'dia')::date > v_hoje);
        v_dados := v_dados || jsonb_build_object('prazo', v_pz);
        v_volta_atraso := v_ab.atraso_gravacao >= v_cfg.volta_min and v_ab.atraso_gravacao <= v_cfg.volta_max;
        if v_s.tipo = 'saudacao_numero_novo' then
          -- a saudação (T19) não promete hora: só o cumprimento entra nos dados (e no contexto do validador)
          v_campos := jsonb_build_object('cumprimento', public._retorno_cumprimento(v_agora), 'volta', v_volta_atraso);
        else
          v_campos := jsonb_build_object('cumprimento', public._retorno_cumprimento(v_agora),
                                         'quando', v_pz ->> 'quando', 'hora', v_pz ->> 'hora',
                                         'volta', v_volta_atraso,
                                         'risco', coalesce((v_dados ->> 'risco')::boolean, false));
        end if;
      end if;

      if v_s.tipo = 'recibo_cliente' then
        if v_pz ->> 'fonte' = 'fora_ate' then
          v_var := 'fora_ate';
        elsif v_pz ->> 'faixa' = 'noite' then
          v_var := case when v_pz ->> 'quando' = 'hoje' then 'manha' else 'manha_outro_dia' end;
          -- {de_quando}: a 1ª mensagem entre 00:00 e 06:59 do mesmo dia do recibo é "desta madrugada"
          v_campos := v_campos || jsonb_build_object('de_quando',
            case when (v_ab.aberta_em at time zone c_fuso)::date = v_hoje
                      and (v_ab.aberta_em at time zone c_fuso)::time < time '07:00'
                 then 'desta madrugada' else 'de ontem à noite' end);
        elsif v_volta_atraso then
          -- a queda avisada pelo vigia da conexão entre 30 min antes da mensagem e a gravação dela (R1-03)
          v_var := case when exists (select 1 from public.app_notifications n
                                      where n.type = 'whatsapp_caiu'
                                        and n.created_at >= v_ab.aberta_em - interval '30 minutes'
                                        and n.created_at <= v_ab.gravada_em
                                        and n.created_at <= v_agora)
                        then 'volta_queda' else 'volta' end;
          v_campos := v_campos || jsonb_build_object(
            'dia_msg', public._agenda_cliente_dia((v_ab.aberta_em at time zone c_fuso)::date),
            'hora_msg', to_char(v_ab.aberta_em at time zone c_fuso, 'HH24:MI'));
        elsif coalesce((v_pz ->> 'outro_dia')::boolean, false) then
          v_var := 'outro_dia';
        else
          v_var := 'padrao';
        end if;
        if v_nome is null then
          v_var := case v_var when 'outro_dia' then 'outro_dia_sem_nome'
                              when 'manha' then 'manha_sem_nome'
                              when 'manha_outro_dia' then 'manha_sem_nome'
                              when 'fora_ate' then 'fora_ate_sem_nome'
                              else 'sem_nome' end;
        elsif v_var in ('padrao', 'outro_dia', 'manha', 'manha_outro_dia', 'fora_ate', 'volta', 'volta_queda') then
          -- VOZ-1 e VOZ-6: a Claudia se apresenta só se ninguém (retorno ou agenda) falou com este cliente.
          -- Em sombra, a sombra do retorno também conta, para a simulação sair como sairia ligada.
          v_ouviu := public._cliente_ja_apresentada(v_ab.client_id, v_s.chave, v_hoje)
                     or (not v_pretendido
                         and exists (select 1 from public.retorno_saidas o
                                      where o.chave = v_s.chave
                                        and o.id <> v_s.id
                                        and o.emissor = 'retorno'
                                        and o.tipo not in ('acorde', 'cadastro_provisorio', 'fila')
                                        and o.decidida_em > v_agora - v_cfg.apresentacao_intervalo
                                        and o.decidida_em <= v_agora
                                        and o.estado = 'sombra'));
          if not v_ouviu then
            v_var := v_var || '_apresentacao';
          end if;
        end if;

      elsif v_s.tipo = 'recibo_ambiguo' then
        v_var := 'padrao';

      elsif v_s.tipo = 'recibo_numero_novo' then
        v_apos_saudacao := coalesce((v_dados ->> 'apos_saudacao')::boolean, false)
                           or exists (select 1 from public.retorno_saidas o
                                       where o.abertura_id = v_s.abertura_id
                                         and o.tipo = 'saudacao_numero_novo'
                                         and o.estado in ('sombra', 'enviada', 'incerta')
                                         and o.decidida_em <= v_agora);
        if v_apos_saudacao then
          v_var := 'sem_pergunta';     -- no máximo 2 mensagens automáticas no 1º contato (R1-23)
        else
          -- O pedido das 24 h do número (a mesma janela da triagem): a necessidade dita e o bem.
          select min(public._retorno_hora_real(w)) into v_desde
            from public.whatsapp_messages w
           where public._agenda_chave_telefone(w.phone_normalized) = v_s.chave
             and w.direction = 'inbound'
             and w.occurred_at <= v_agora
             and w.occurred_at >= v_agora - interval '24 hours'
             and public._retorno_hora_real(w) >= v_agora - interval '24 hours';
          v_pd := case when v_desde is not null
                       then public._retorno_pedido_de_servico(v_s.chave, v_desde, v_agora, null) end;
          v_do_bem := public._retorno_do_bem(coalesce(v_pd ->> 'bem_palavra', v_ab.sinais ->> 'bem_palavra'));
          if coalesce((v_pd ->> 'servico_generico')::boolean, false) then
            v_var := 'pergunta_necessidade';
          elsif coalesce(v_pd ->> 'ano', v_ab.sinais ->> 'ano') is null and v_do_bem is not null then
            v_var := 'pergunta_modelo';
            v_campos := v_campos || jsonb_build_object('do_bem', v_do_bem);
          else
            v_var := 'sem_pergunta';   -- sem a palavra do bem não há como perguntar o modelo
          end if;
        end if;

      elsif v_s.tipo = 'saudacao_numero_novo' then
        v_var := 'padrao';

      elsif v_s.tipo = 'coleta_numero_novo' then
        v_var := 'nome';

      elsif v_s.tipo = 'adiamento' then
        v_var := case when v_nome is null then 'sem_nome' else 'com_nome' end;
        v_campos := jsonb_build_object('hora', v_dados ->> 'hora');

      elsif v_s.tipo in ('fim_do_dia', 'urgente') then
        -- A marca de topo vem antes do texto: é o que torna verdadeiro "o primeiro da lista dele … cedo".
        v_topo := public.agenda_somar_du(v_hoje + 1, 0);
        update public.retorno_aberturas a
           set topo_dia = case when a.topo_dia is null or a.topo_dia < v_hoje then v_topo
                               else least(a.topo_dia, v_topo) end,
               atualizada_em = now()
         where a.id = v_s.abertura_id
         returning * into v_ab;
        v_campos := jsonb_build_object('quando_lista', public._retorno_quando(v_topo, v_hoje));
        if v_s.tipo = 'fim_do_dia' then
          v_var := case when v_nome is null then 'sem_nome' else 'com_nome' end;
        else
          v_var := case when v_nome is null then 'sem_acorde_sem_nome' else 'sem_acorde' end;
          -- F2 (P14): o banco sabe qual das duas é verdade. "Avisei" só com o aviso de fato registrado.
          if v_cfg.modo = 'ligado' and 'acorde' = any (v_cfg.tipos_ligados)
             and public._retorno_acordar_agora(v_ab.id, 'urgente', v_agora) then
            v_var := case when v_nome is null then 'acorde_sem_nome' else 'acorde' end;
          end if;
        end if;

      elsif v_s.tipo = 'parar' then
        v_var := case when v_nome is null then 'sem_nome' else 'com_nome' end;

      -- F2: modelo com fato. O aprovado sai como o dono viu, sem recompor (a trava por hash). O sozinho confere o fato de novo.
      elsif v_s.tipo like 'modelo\_%' escape '\' then
        if v_dados ? 'texto_aprovado' then
          v_var := 'aprovado';
        else
          v_m := public._retorno_modelo_do_caso(v_ab.id, v_agora);
          if v_m ->> 'modelo' is distinct from v_s.tipo then
            update public.retorno_saidas s
               set estado = 'recusada', motivo = 'fato_mudou', decidida_em = v_agora, processando_ate = null, atualizada_em = now()
             where s.id = v_s.id;
            continue;
          end if;
          if exists (select 1 from public.retorno_saidas o
                      where o.abertura_id = v_s.abertura_id
                        and o.tipo in ('recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo', 'saudacao_numero_novo')
                        and o.estado in ('enviada', 'incerta')
                        and o.decidida_em <= v_agora) then
            v_var := case when v_nome is null then 'apos_recibo_sem_nome' else 'apos_recibo' end;
          elsif v_nome is null then
            v_var := 'sem_nome';
          else
            -- VOZ-1 e VOZ-6: a Claudia se apresenta só se ninguém falou com este cliente
            v_ouviu := public._cliente_ja_apresentada(v_ab.client_id, v_s.chave, v_hoje);
            v_var := case when v_ouviu then 'padrao' else 'padrao_apresentacao' end;
          end if;
        end if;

      else
        v_var := null;   -- tipo desconhecido: o _retorno_texto recusa (22023)
      end if;

      -- F2: as variantes novas só com a chave ligada: com ela desligada, o texto ao cliente é o da F1.
      if v_cfg.variantes_ligadas then
        if v_s.tipo = 'recibo_cliente' and v_var = 'padrao' and not coalesce((v_pz ->> 'outro_dia')::boolean, false) then
          v_alt := public._retorno_variante_f2(v_ab.id, v_agora);
          if v_alt is not null then
            v_var := v_alt;
            v_f2 := true;
          end if;
        elsif v_s.tipo = 'adiamento' and public._retorno_tem_orcamento(v_ab.id, v_agora) then
          v_var := case when v_nome is null then 'orcamento_sem_nome' else 'orcamento' end;
          v_f2 := true;
        elsif v_s.tipo = 'coleta_numero_novo' and public._retorno_tem_orcamento(v_ab.id, v_agora) then
          v_var := 'nome_orcamento';
          v_f2 := true;
        end if;
      end if;

      if v_nome is not null then
        v_campos := v_campos || jsonb_build_object('nome', v_nome);
      end if;
      v_dados := v_dados || jsonb_strip_nulls(v_campos);

      begin
        -- F2: o modelo tem o texto dele; o resto, o da F1 ou a variante nova.
        if v_s.tipo like 'modelo\_%' escape '\' then
          v_texto := coalesce(v_dados ->> 'texto_aprovado', public._retorno_texto_do_modelo(v_ab.id, v_m, v_var, v_agora));
        elsif v_f2 then
          v_texto := public._retorno_texto_f2(v_s.tipo, v_var, v_dados);
        else
          v_texto := public._retorno_texto(v_s.tipo, v_var, v_dados);
        end if;
      exception when sqlstate '22023' then
        update public.retorno_saidas s
           set estado = 'recusada', motivo = 'texto', variante = left(v_var, 40), decidida_em = v_agora,
               processando_ate = null, dados = v_dados || jsonb_build_object('texto_erro', left(sqlerrm, 200)),
               atualizada_em = now()
         where s.id = v_s.id;
        perform public._retorno_log('pegar', 'retorno_pegar: ' || sqlerrm, 'error',
                                    jsonb_build_object('saida', v_s.id, 'sqlstate', '22023'));
        continue;
      end;

      -- F2: o dia da peça entra no contexto do validador.
      if v_s.tipo = 'modelo_peca_chegou' then
        v_dados := v_dados || jsonb_strip_nulls(jsonb_build_object('dia_peca', (regexp_match(v_texto, '[0-9]{2}/[0-9]{2}'))[1]));
      end if;

      -- 4. O modo efetivo (P4): o grupo do caso, o URGENTE, a passagem sem acorde e o caso em sombra.
      v_modo := public._retorno_modo_efetivo(v_s.id, v_var, v_dados -> 'prazo', v_agora);
      v_ligado := v_modo ->> 'modo' = 'ligado';
      -- F2: *segura tudo* não queima a saída: ela espera a hora do segura, e *solta tudo* a traz de volta.
      if v_modo ->> 'motivo' = 'segura_tudo' then
        update public.retorno_saidas s
           set enviar_em = v_cfg.segura_tudo_ate, dados = s.dados || jsonb_build_object('segurada', true), atualizada_em = now()
         where s.id = v_s.id;
        continue;
      end if;
      if v_ligado then
        v_dados := v_dados - 'sombra_motivo';
      else
        v_dados := v_dados || jsonb_build_object('sombra_motivo', coalesce(v_modo ->> 'motivo', 'modo'));
      end if;

      -- 5. O canal (P4), simulando quando a saída vai em sombra. Ligada, trava antes a linha de configuração
      --    (até o fim da transação): a 2ª execução simultânea espera aqui e o canal dela já vê o
      --    proximo_envio_em e o teto do dia da 1ª (R1-11).
      if v_ligado then
        perform 1 from public.retorno_config c where c.id for update;
      end if;
      v_canal := public.canal_pode_enviar(v_s.phone_normalized, v_s.classe, v_s.origem, v_agora, not v_ligado, v_s.tipo);
      -- F2: o envio aprovado pelo dono conta, mas pode passar do teto do dia. Bloqueio, opt-out, pessoal e cliente final nunca passam.
      if not coalesce((v_canal ->> 'pode')::boolean, false)
         and not (v_canal ->> 'motivo' = 'teto_dia' and coalesce((v_dados ->> 'aprovada')::boolean, false)) then
        if v_canal ->> 'motivo' in ('fora_da_janela', 'espacamento')
           and (v_canal ->> 'enviar_em')::timestamptz > v_agora then
          update public.retorno_saidas s
             set enviar_em = (v_canal ->> 'enviar_em')::timestamptz,
                 dados = s.dados || jsonb_strip_nulls(jsonb_build_object('prazo', v_dados -> 'prazo')),
                 atualizada_em = now()
           where s.id = v_s.id;
          continue;
        end if;
        update public.retorno_saidas s
           set estado = 'recusada', motivo = coalesce(v_canal ->> 'motivo', 'canal'), variante = left(v_var, 40),
               texto = v_texto, dados = v_dados, decidida_em = v_agora, processando_ate = null, atualizada_em = now()
         where s.id = v_s.id;
        continue;
      end if;

      -- 6. Os tetos por número (contam sombra, preparada, enviando, enviada e incerta decididas até agora).
      if v_s.tipo = any (c_recibos) or v_s.tipo = 'saudacao_numero_novo' then
        -- recibo ou saudação de OUTRO caso nas últimas 12 h (a saudação e o recibo do mesmo caso são o par do
        -- 1º contato, J.10)
        if exists (select 1 from public.retorno_saidas o
                    where o.chave = v_s.chave
                      and o.id <> v_s.id
                      and o.emissor = 'retorno'
                      and (o.tipo = any (c_recibos) or o.tipo = 'saudacao_numero_novo')
                      and o.abertura_id is distinct from v_s.abertura_id
                      and o.estado = any (c_contam)
                      and o.decidida_em <= v_agora
                      and o.decidida_em > v_agora - v_cfg.recibo_intervalo) then
          update public.retorno_saidas s
             set estado = 'recusada', motivo = 'teto_numero', variante = left(v_var, 40), texto = v_texto,
                 dados = v_dados, decidida_em = v_agora, processando_ate = null, atualizada_em = now()
           where s.id = v_s.id;
          continue;
        end if;
      end if;
      if v_s.tipo = 'saudacao_numero_novo'
         and exists (select 1 from public.retorno_saidas o
                      where o.chave = v_s.chave
                        and o.id <> v_s.id
                        and o.tipo = 'saudacao_numero_novo'
                        and o.estado = any (c_contam)
                        and o.decidida_em <= v_agora
                        and o.decidida_em > v_agora - v_cfg.saudacao_intervalo) then
        update public.retorno_saidas s
           set estado = 'recusada', motivo = 'teto_saudacao', variante = left(v_var, 40), texto = v_texto,
               dados = v_dados, decidida_em = v_agora, processando_ate = null, atualizada_em = now()
         where s.id = v_s.id;
        continue;
      end if;
      if v_s.tipo = 'coleta_numero_novo'
         and (select count(*) from public.retorno_saidas o
               where o.abertura_id = v_s.abertura_id
                 and o.id <> v_s.id
                 and o.tipo in ('saudacao_numero_novo', 'recibo_numero_novo', 'coleta_numero_novo')
                 and o.estado = any (c_contam)
                 and o.decidida_em <= v_agora) >= v_cfg.coleta_max then
        update public.retorno_saidas s
           set estado = 'recusada', motivo = 'teto_coleta', variante = left(v_var, 40), texto = v_texto,
               dados = v_dados, decidida_em = v_agora, processando_ate = null, atualizada_em = now()
         where s.id = v_s.id;
        continue;
      end if;

      -- 7. A reserva.
      update public.retorno_saidas s
         set estado = case when v_ligado then 'enviando' else 'preparada' end,
             texto = v_texto, dados = v_dados, variante = left(v_var, 40), decidida_em = v_agora,
             processando_ate = v_agora + interval '2 minutes',
             modo = case when v_ligado then 'ligado' else 'sombra' end,
             atualizada_em = now()
       where s.id = v_s.id
       returning * into v_s;
      if v_ligado then
        -- o espaçamento global entre saídas automáticas, sorteado (R1-11)
        update public.retorno_config c
           set proximo_envio_em = v_agora + make_interval(secs => (c.espaco_min_s
                                    + floor(random() * (c.espaco_max_s - c.espaco_min_s + 1)))::double precision)
         where c.id;
      end if;

      -- 8. O item, com o contexto do validador montado pelo banco.
      v_ctx := public._retorno_contexto_do_validador(v_s.id, v_texto, v_dados, v_agora);
      return jsonb_build_object(
        'saida_id', v_s.id,
        'tentativa', v_s.tentativa,
        'dedupe_key', v_s.dedupe_key,
        'tipo', v_s.tipo,
        'variante', v_s.variante,
        'origem', v_s.origem,
        'classe', v_s.classe,
        'modo', v_s.modo,
        'phone', v_s.phone_normalized,
        'texto', v_s.texto,
        'validador', v_ctx);
    exception when others then
      -- Erro num item nunca trava a fila: a volta é desfeita, a saída vira recusada/erro e a próxima segue.
      update public.retorno_saidas s
         set estado = 'recusada', motivo = 'erro', decidida_em = v_agora, processando_ate = null,
             dados = s.dados || jsonb_build_object('erro', jsonb_build_object('sqlstate', sqlstate,
                                                                               'mensagem', left(sqlerrm, 200))),
             atualizada_em = now()
       where s.id = v_s.id;
      perform public._retorno_log('pegar', 'retorno_pegar: ' || sqlerrm, 'error',
                                  jsonb_build_object('saida', v_s.id, 'sqlstate', sqlstate));
    end;
  end loop;
  return null;
end;
$$;

create or replace function public.retorno_saida_autorizada(p_saida uuid, p_fone text, p_agora timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_s public.retorno_saidas;
  v_modo jsonb;
  v_bloqueio text;
  v_janela jsonb;
begin
  begin
    select * into v_s from public.retorno_saidas s where s.id = p_saida;
    if not found then
      return jsonb_build_object('pode', false, 'motivo', 'sem_saida');
    end if;
    -- F4 (P5): a saída do parceiro tem a última trava dela (veto, 24 h, o vínculo e o número conferidos de novo).
    if v_s.emissor = 'parceiro' then
      return public.parceiro_saida_autorizada(p_saida, p_fone, v_agora);
    end if;
    -- A saída reservada pelo retorno_pegar: do retorno, enviando, ligada e dentro da reserva.
    if v_s.emissor is distinct from 'retorno' then
      return jsonb_build_object('pode', false, 'motivo', 'emissor');
    end if;
    if v_s.estado is distinct from 'enviando' then
      return jsonb_build_object('pode', false, 'motivo', 'estado');
    end if;
    if v_s.modo is distinct from 'ligado' then
      return jsonb_build_object('pode', false, 'motivo', 'saida_em_sombra');
    end if;
    if v_s.processando_ate is null or v_s.processando_ate <= v_agora then
      return jsonb_build_object('pode', false, 'motivo', 'reserva_vencida');
    end if;
    -- O destino é o telefone da saída (8 dígitos e o mesmo DDD).
    if not coalesce(public._mesmo_telefone(p_fone, v_s.phone_normalized), false) then
      return jsonb_build_object('pode', false, 'motivo', 'telefone');
    end if;
    -- As mesmas regras do retorno_pegar, de novo agora.
    v_modo := public._retorno_modo_efetivo(v_s.id, v_s.variante, v_s.dados -> 'prazo', v_agora);
    if v_modo ->> 'modo' is distinct from 'ligado' then
      return jsonb_build_object('pode', false, 'motivo', coalesce(v_modo ->> 'motivo', 'modo'));
    end if;
    -- O bloqueio; a única exceção é a confirmação do PARAR (a própria saída, enviando, não conta).
    v_bloqueio := public.canal_bloqueado(p_fone);
    if v_s.tipo = 'parar' then
      if not coalesce(public._retorno_parar_permitido(v_s.chave, v_agora, v_s.id), false) then
        return jsonb_build_object('pode', false, 'motivo', coalesce(v_bloqueio, 'canal'));
      end if;
    elsif v_bloqueio is not null then
      return jsonb_build_object('pode', false, 'motivo', v_bloqueio);
    end if;
    -- A janela da classe.
    v_janela := public._retorno_janela(v_s.classe, v_agora, v_s.chave);
    if not coalesce((v_janela ->> 'dentro')::boolean, false) then
      return jsonb_build_object('pode', false, 'motivo',
        case when v_s.classe in ('resposta_imediata', 'resposta_atrasada') then 'fora_da_janela' else 'classe_nao_suportada' end);
    end if;
    return jsonb_build_object('pode', true, 'motivo', null);
  exception when others then
    -- Na dúvida, não manda.
    return jsonb_build_object('pode', false, 'motivo', 'erro');
  end;
end;
$$;

create or replace function public.retorno_registrar_decisao(p_saida uuid, p_estado text, p_detalhe jsonb default '{}',
                                                            p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_motivos constant text[] := array['validador', 'canal', 'provedor', 'equipe', 'texto'];
  v_agora timestamptz := coalesce(p_agora, now());
  d jsonb := case when jsonb_typeof(p_detalhe) = 'object' then p_detalhe else '{}'::jsonb end;
  v_s public.retorno_saidas;
  v_cfg public.retorno_config;
  v_final text;
  v_motivo text;
  v_erro boolean := false;
  v_envio jsonb;
begin
  begin
    select * into v_s from public.retorno_saidas s where s.id = p_saida for update;
    if not found then
      return jsonb_build_object('ok', false, 'erro', 'sem_saida');
    end if;
    if v_s.emissor is null or v_s.emissor not in ('retorno', 'parceiro')   -- F4 (P5): também a saída do parceiro
       or p_estado is null
       or (p_estado = 'sombra' and v_s.estado <> 'preparada')
       or (p_estado in ('enviada', 'incerta', 'reagendar') and v_s.estado <> 'enviando')
       or (p_estado = 'recusada' and v_s.estado not in ('preparada', 'enviando')) then
      return jsonb_build_object('ok', false, 'erro', 'estado');
    end if;
    -- o que a edge viu do envio, só códigos (nunca texto do cliente)
    v_envio := jsonb_strip_nulls(jsonb_build_object('http_status', d -> 'http_status', 'codigo', left(d ->> 'codigo', 64),
                                                    'em', v_agora));

    if p_estado = 'sombra' then
      v_final := 'sombra';
      update public.retorno_saidas s
         set estado = 'sombra', validador = nullif(d -> 'validador', 'null'::jsonb), processando_ate = null,
             atualizada_em = now()
       where s.id = v_s.id;

    elsif p_estado = 'enviada' then
      v_final := 'enviada';
      update public.retorno_saidas s
         set estado = 'enviada', enviada_em = v_agora, provider_message_id = left(d ->> 'provider_message_id', 200),
             validador = nullif(d -> 'validador', 'null'::jsonb), processando_ate = null,
             dados = s.dados || jsonb_build_object('envio', v_envio), atualizada_em = now()
       where s.id = v_s.id;
      -- uma enviada zera os erros e desliga o disjuntor por erros (o da conexão é do vigia)
      update public.retorno_config c
         set erros_seguidos = 0,
             so_reativo = case when c.so_reativo_motivo = 'erros' then false else c.so_reativo end,
             so_reativo_desde = case when c.so_reativo_motivo = 'erros' then null else c.so_reativo_desde end,
             so_reativo_motivo = case when c.so_reativo_motivo = 'erros' then null else c.so_reativo_motivo end
       where c.id;

    elsif p_estado = 'incerta' then
      -- FINAL: pode ter saído, e nunca há 2ª tentativa (o vigia só confere a conversa por 30 min).
      v_final := 'incerta';
      v_erro := true;
      update public.retorno_saidas s
         set estado = 'incerta', validador = nullif(d -> 'validador', 'null'::jsonb), processando_ate = null,
             dados = s.dados || jsonb_build_object('envio', v_envio), atualizada_em = now()
       where s.id = v_s.id;

    elsif p_estado = 'recusada' then
      v_final := 'recusada';
      v_motivo := case when d ->> 'motivo' = any (c_motivos) then d ->> 'motivo' else 'erro' end;
      v_erro := v_motivo = 'provedor';
      update public.retorno_saidas s
         set estado = 'recusada', motivo = v_motivo, processando_ate = null,
             validador = case when v_motivo = 'validador'
                              then jsonb_strip_nulls(jsonb_build_object(
                                     'ok', false,
                                     'regras', case when jsonb_typeof(d -> 'regras') = 'array' then d -> 'regras'
                                                    else '[]'::jsonb end,
                                     'codigo', left(d ->> 'codigo', 64)))
                              else nullif(d -> 'validador', 'null'::jsonb) end,
             dados = s.dados || jsonb_build_object('envio', v_envio)
                     || case when v_motivo = 'erro' and d ? 'motivo'
                             then jsonb_build_object('motivo_recebido', left(d ->> 'motivo', 64)) else '{}'::jsonb end,
             atualizada_em = now()
       where s.id = v_s.id;

    elsif p_estado = 'reagendar' then
      -- Só o 503 (a reserva do whatsapp-send não aconteceu): volta com a MESMA chave; acima de 3, recusa.
      if v_s.tentativa >= 3 then
        v_final := 'recusada';
        update public.retorno_saidas s
           set estado = 'recusada', motivo = 'reserva', processando_ate = null,
               dados = s.dados || jsonb_build_object('envio', v_envio), atualizada_em = now()
         where s.id = v_s.id;
      else
        v_final := 'agendada';
        update public.retorno_saidas s
           set estado = 'agendada', enviar_em = v_agora + interval '2 minutes', tentativa = s.tentativa + 1,
               processando_ate = null, decidida_em = null,
               dados = s.dados || jsonb_build_object('envio', v_envio), atualizada_em = now()
         where s.id = v_s.id;
      end if;

    else
      return jsonb_build_object('ok', false, 'erro', 'estado');
    end if;

    -- O disjuntor por erros (B.6): três erros seguidos do envio (incerta ou provedor) → só resposta imediata.
    if v_erro then
      update public.retorno_config c
         set erros_seguidos = least(c.erros_seguidos + 1, 32767)
       where c.id
       returning * into v_cfg;
      if v_cfg.erros_seguidos >= 3 and not v_cfg.so_reativo then
        update public.retorno_config c
           set so_reativo = true, so_reativo_motivo = 'erros', so_reativo_desde = v_agora
         where c.id;
        perform public._retorno_log('disjuntor', 'retorno: so_reativo ligado por erros seguidos do envio', 'warn',
                                    jsonb_build_object('erros_seguidos', v_cfg.erros_seguidos, 'saida', v_s.id));
      end if;
    end if;

    -- Os efeitos no caso (a sombra simula o relógio inteiro; a incerta pode ter saído), num sub-bloco próprio:
    -- o efeito que falha vai ao log e não desfaz a decisão (a saída nunca fica presa voltando à fila).
    if v_final in ('sombra', 'enviada', 'incerta') then
      begin
        perform public._retorno_aplicar_efeitos(v_s.id, v_agora);
      exception when others then
        perform public._retorno_log('decisao', 'retorno_registrar_decisao: efeitos no caso: ' || sqlerrm, 'error',
                                    jsonb_build_object('saida', v_s.id, 'estado', v_final, 'sqlstate', sqlstate));
      end;
    end if;

    -- F4 (P5): os efeitos do parceiro (aviso, painel, apresentação, coleta_n), em toda decisão de saída do parceiro, num
    -- sub-bloco próprio: o efeito que falha vai ao log e não desfaz a decisão.
    if v_s.emissor = 'parceiro' then
      begin
        perform public._parceiro_aplicar_efeitos(v_s.id, v_agora);
      exception when others then
        perform public._retorno_log('decisao', 'retorno_registrar_decisao: efeitos do parceiro: ' || sqlerrm, 'error',
                                    jsonb_build_object('saida', v_s.id, 'estado', v_final, 'sqlstate', sqlstate));
      end;
    end if;

    return jsonb_build_object('ok', true, 'estado', v_final);
  exception when others then
    perform public._retorno_log('decisao', 'retorno_registrar_decisao: ' || sqlerrm, 'error',
                                jsonb_build_object('saida', p_saida, 'estado', p_estado, 'sqlstate', sqlstate));
    return jsonb_build_object('ok', false, 'erro', sqlstate);
  end;
end;
$$;
