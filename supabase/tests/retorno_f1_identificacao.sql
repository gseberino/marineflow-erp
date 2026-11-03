-- Retorno F1 (P1): retorno_identificar, a identificação nova do webhook (F0b-1).
-- Desligada (ou sem a linha de configuração): {"nova": false}, e o webhook segue o ILIKE de hoje.
-- Ligada: o papel de quem_escreve e o client_id SÓ no papel cliente — ambíguo nunca escolhe; equipe,
-- fornecedor, número novo e sem número também dão client_id nulo; cliente inativo e "Cliente Final"
-- (genérico) nunca são devolvidos. Erro de quem_escreve sobe (o webhook cai no ILIKE).
-- Arranjo de retorno_f0b_quem_escreve.sql, com cadastros SINTÉTICOS (nenhum cadastro real é alterado).
-- Run (só pela bancada, de madrugada): npx supabase@2.111.0 db query --linked -f supabase/tests/retorno_f1_identificacao.sql
-- Termina em ROLLBACK: nada fica gravado. Telefones de teste 55479000091xx; o arranjo inteiro é desfeito
-- dentro do arquivo (sub-bloco que termina em 'desfaz'), inclusive a função renomeada do caso 2a.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

do $identificacao$
declare
  v_c_um uuid; v_c_a uuid; v_c_b uuid; v_c_equipe uuid; v_c_inativo uuid; v_c_generico uuid; v_c_misto uuid;
  v_c_ddd uuid; v_forn uuid; v_payee uuid;
  r_desligada jsonb; r_sem_linha jsonb; r_erro text;
  r_um jsonb; r_dois jsonb; r_ddd jsonb; r_equipe jsonb; r_novo jsonb; r_inativo jsonb; r_generico jsonb;
  r_misto jsonb; r_forn jsonb; r_sem_numero jsonb;
  v_chegou boolean := false;
  v_ident_antes boolean;
  v_f record;
  v_rotulo text;
  v_r jsonb;
  v_todas jsonb;
  v_n int := 0;
begin
  -- 0. A função: STABLE, SECURITY DEFINER com search_path, e só o service_role chama.
  select p.provolatile, p.prosecdef, coalesce(p.proconfig, '{}') as config into v_f
    from pg_proc p where p.oid = to_regprocedure('public.retorno_identificar(text)');
  if not found then
    raise exception '0: retorno_identificar não existe';
  end if;
  if v_f.provolatile <> 's' or not v_f.prosecdef or not ('search_path=public' = any (v_f.config)) then
    raise exception '0b: retorno_identificar não é STABLE + SECURITY DEFINER com search_path = public';
  end if;
  if has_function_privilege('anon', 'public.retorno_identificar(text)', 'execute')
     or has_function_privilege('authenticated', 'public.retorno_identificar(text)', 'execute')
     or not has_function_privilege('service_role', 'public.retorno_identificar(text)', 'execute') then
    raise exception '0c: retorno_identificar não é só do service_role';
  end if;
  -- O valor de hoje (depois de 11/11 a identificação nova pode estar ligada): o arranjo devolve a ele.
  select identificacao_nova into v_ident_antes from public.retorno_config where id;
  if not found then
    raise exception '0d: retorno_config sem a linha de configuração';
  end if;

  begin
    -- Cadastros sintéticos: cada número de teste tem só os cadastros abaixo.
    insert into public.clients (type, name, whatsapp)
      values ('individual', 'Teste F1 identificação um', '(47) 90000-9101') returning id into v_c_um;
    insert into public.clients (type, name, phone)
      values ('individual', 'Teste F1 identificação A', '47 90000-9102') returning id into v_c_a;
    insert into public.clients (type, name, whatsapp)
      values ('company', 'Teste F1 identificação B', '(47) 90000-9102') returning id into v_c_b;
    insert into public.payees (name, phone)
      values ('Teste F1 identificação equipe', '(47) 90000-9103') returning id into v_payee;
    insert into public.clients (type, name, whatsapp)
      values ('individual', 'Teste F1 identificação da equipe', '(47) 90000-9103') returning id into v_c_equipe;
    insert into public.clients (type, name, whatsapp, phone, active)
      values ('individual', 'Teste F1 identificação inativo', '(47) 90000-9105', '(47) 90000-9107', false)
      returning id into v_c_inativo;
    insert into public.clients (type, name, whatsapp, phone, generico)
      values ('individual', 'Teste F1 identificação Cliente Final', '(47) 90000-9106', '(47) 90000-9107', true)
      returning id into v_c_generico;
    insert into public.clients (type, name, whatsapp)
      values ('individual', 'Teste F1 identificação misto', '(47) 90000-9107') returning id into v_c_misto;
    insert into public.suppliers (name, phone, active)
      values ('Teste F1 identificação fornecedor', '(47) 90000-9108', true) returning id into v_forn;
    insert into public.clients (type, name, whatsapp)
      values ('individual', 'Teste F1 identificação outro DDD', '(11) 90000-9109') returning id into v_c_ddd;

    -- 1. Desligada: {"nova": false}, mesmo para um cliente conhecido.
    update public.retorno_config set identificacao_nova = false where id;
    r_desligada := public.retorno_identificar('5547900009101');

    -- 1b. Sem a linha de configuração: também {"nova": false} (falha fecha).
    begin
      delete from public.retorno_config;
      r_sem_linha := public.retorno_identificar('5547900009101');
      raise exception 'desfaz' using errcode = 'P0001';
    exception when sqlstate 'P0001' then
      if sqlerrm <> 'desfaz' then raise; end if;
    end;

    -- 2. Ligada.
    update public.retorno_config set identificacao_nova = true where id;

    -- 2a. Erro de quem_escreve sobe, nunca vira "não identificado" calado. Fica antes da 1ª chamada ligada:
    --     com a função renomeada, a chamada a quem_escreve não acha a função (42883).
    begin
      alter function public.quem_escreve(text) rename to quem_escreve_f1_fora;
      perform public.retorno_identificar('5547900009101');
      r_erro := 'não subiu';
      raise exception 'desfaz' using errcode = 'P0001';
    exception
      when sqlstate 'P0001' then
        if sqlerrm <> 'desfaz' then r_erro := 'P0001: ' || sqlerrm; end if;
      when others then
        r_erro := sqlstate;
    end;

    r_um := public.retorno_identificar('5547900009101');
    r_dois := public.retorno_identificar('5547900009102');
    r_equipe := public.retorno_identificar('5547900009103');
    r_novo := public.retorno_identificar('5547900009104');
    r_inativo := public.retorno_identificar('5547900009105');
    r_generico := public.retorno_identificar('5547900009106');
    r_misto := public.retorno_identificar('5547900009107');
    r_forn := public.retorno_identificar('5547900009108');
    r_ddd := public.retorno_identificar('5547900009109');
    r_sem_numero := public.retorno_identificar(null);

    v_chegou := true;
    raise exception 'desfaz' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'desfaz' then raise; end if;
  end;
  if not v_chegou then
    raise exception '0e: o arranjo não chegou ao fim';
  end if;
  if exists (select 1 from public.clients where id in (v_c_um, v_c_a, v_c_b, v_c_misto))
     or (select identificacao_nova from public.retorno_config where id) is distinct from v_ident_antes
     or to_regprocedure('public.quem_escreve(text)') is null then
    raise exception '0f: o arranjo não foi desfeito';
  end if;

  -- 1. Desligada ou sem a linha.
  if r_desligada is distinct from '{"nova": false}'::jsonb then
    raise exception '1: desligada não devolveu só {"nova": false}: %', r_desligada;
  end if;
  if r_sem_linha is distinct from '{"nova": false}'::jsonb then
    raise exception '1b: sem a linha de configuração não devolveu {"nova": false}: %', r_sem_linha;
  end if;

  -- 2a. O erro subiu.
  if r_erro is distinct from '42883' then
    raise exception '2a: erro de quem_escreve não subiu como exceção (%)', r_erro;
  end if;

  -- 2. O contrato C-IDENT em toda resposta ligada: só nova, papel, client_id e clientes (nunca nome);
  --    client_id só no papel cliente.
  v_todas := jsonb_build_object('um', r_um, 'dois', r_dois, 'equipe', r_equipe, 'novo', r_novo,
                                'inativo', r_inativo, 'generico', r_generico, 'misto', r_misto,
                                'fornecedor', r_forn, 'ddd', r_ddd, 'sem_numero', r_sem_numero);
  for v_rotulo, v_r in select e.key, e.value from jsonb_each(v_todas) e loop
    v_n := v_n + 1;
    if jsonb_typeof(v_r) is distinct from 'object'
       or (select array_agg(k order by k collate "C") from jsonb_object_keys(v_r) k)
          is distinct from array['client_id', 'clientes', 'nova', 'papel']
       or v_r -> 'nova' is distinct from 'true'::jsonb
       or jsonb_typeof(v_r -> 'papel') is distinct from 'string'
       or jsonb_typeof(v_r -> 'clientes') is distinct from 'array' then
      raise exception '2 (%): fora do contrato C-IDENT: %', v_rotulo, v_r;
    end if;
    if (v_r ->> 'papel' = 'cliente') is distinct from (jsonb_typeof(v_r -> 'client_id') = 'string') then
      raise exception '2 (%): client_id fora do papel cliente: %', v_rotulo, v_r;
    end if;
  end loop;
  if v_n <> 10 then
    raise exception '2: conferidas % respostas, esperadas 10', v_n;
  end if;

  -- 2b. Um cliente ativo: identifica, com o id dele.
  if r_um ->> 'papel' is distinct from 'cliente' or r_um ->> 'client_id' is distinct from v_c_um::text
     or r_um -> 'clientes' is distinct from jsonb_build_array(v_c_um) then
    raise exception '2b: um cliente não deu o client_id dele: %', r_um;
  end if;
  -- 2c. Dois clientes no mesmo número: ambíguo, com os dois, client_id nulo.
  if r_dois ->> 'papel' is distinct from 'cliente_ambiguo' or jsonb_typeof(r_dois -> 'client_id') is distinct from 'null'
     or jsonb_array_length(r_dois -> 'clientes') is distinct from 2
     or not coalesce(r_dois -> 'clientes' @> jsonb_build_array(v_c_a, v_c_b), false) then
    raise exception '2c: número de dois clientes escolheu um deles: %', r_dois;
  end if;
  -- 2d. Um cadastro só, mas de DDD diferente: ambíguo também (os 8 dígitos batem, a pessoa pode ser outra).
  if r_ddd ->> 'papel' is distinct from 'cliente_ambiguo' or jsonb_typeof(r_ddd -> 'client_id') is distinct from 'null'
     or r_ddd -> 'clientes' is distinct from jsonb_build_array(v_c_ddd) then
    raise exception '2d: DDD diferente identificou: %', r_ddd;
  end if;
  -- 2e. Equipe (mesmo com o número num cadastro de cliente): client_id nulo, sem lista de clientes.
  if r_equipe ->> 'papel' is distinct from 'equipe' or jsonb_typeof(r_equipe -> 'client_id') is distinct from 'null'
     or r_equipe -> 'clientes' is distinct from '[]'::jsonb then
    raise exception '2e: número da equipe virou cliente: %', r_equipe;
  end if;
  -- 2f. Sem cadastro: novo, client_id nulo.
  if r_novo ->> 'papel' is distinct from 'novo' or jsonb_typeof(r_novo -> 'client_id') is distinct from 'null'
     or r_novo -> 'clientes' is distinct from '[]'::jsonb then
    raise exception '2f: número sem cadastro não deu novo: %', r_novo;
  end if;
  -- 2g. Só cliente inativo, ou só o "Cliente Final": nunca devolvidos (é número novo).
  if r_inativo ->> 'papel' is distinct from 'novo' or r_inativo -> 'clientes' is distinct from '[]'::jsonb
     or r_generico ->> 'papel' is distinct from 'novo' or r_generico -> 'clientes' is distinct from '[]'::jsonb then
    raise exception '2g: cliente inativo ou Cliente Final identificou: % %', r_inativo, r_generico;
  end if;
  -- 2h. O mesmo número num ativo, num inativo e no "Cliente Final": só o ativo.
  if r_misto ->> 'papel' is distinct from 'cliente' or r_misto ->> 'client_id' is distinct from v_c_misto::text
     or r_misto -> 'clientes' is distinct from jsonb_build_array(v_c_misto) then
    raise exception '2h: o inativo ou o Cliente Final entrou na lista: %', r_misto;
  end if;
  -- 2i. Fornecedor ativo: client_id nulo, sem lista de clientes.
  if r_forn ->> 'papel' is distinct from 'fornecedor' or jsonb_typeof(r_forn -> 'client_id') is distinct from 'null'
     or r_forn -> 'clientes' is distinct from '[]'::jsonb then
    raise exception '2i: fornecedor não deu fornecedor sem client_id: %', r_forn;
  end if;
  -- 2j. Sem número: sem_numero, client_id nulo.
  if r_sem_numero ->> 'papel' is distinct from 'sem_numero' or jsonb_typeof(r_sem_numero -> 'client_id') is distinct from 'null'
     or r_sem_numero -> 'clientes' is distinct from '[]'::jsonb then
    raise exception '2j: sem número: %', r_sem_numero;
  end if;
  -- 2k. Em nenhuma resposta aparece o inativo, o "Cliente Final" ou o cadastro do número da equipe.
  if position(v_c_inativo::text in v_todas::text) > 0 or position(v_c_generico::text in v_todas::text) > 0
     or position(v_c_equipe::text in v_todas::text) > 0 then
    raise exception '2k: um cadastro que nunca identifica apareceu numa resposta';
  end if;

  insert into _bancada (arquivo, ok, numeros)
  values ('retorno_f1_identificacao', true, jsonb_build_object('respostas_ligadas', v_n, 'erro_sobe', r_erro));
end
$identificacao$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
