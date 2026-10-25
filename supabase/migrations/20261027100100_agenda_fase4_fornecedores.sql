-- Agenda de Produção, Fase 4 ("Material em sincronia com o fornecedor"), pacote P1: o prazo do fornecedor numa fonte só,
-- a prontidão que o usa e o prazo que o dono diz pela conversa (rascunho + *grava*).
-- Spec: scratchpad agenda-pesquisa/spec-fase4.md (§5.1, §5.7, §6.1). Decisões do dono 23/10. Depende de 20261027100000
-- (as colunas de suppliers e de agenda_config) e das Fases 1, 2 e 3 inteiras.
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (13 funções novas; 4 recriadas; nenhuma tabela, nenhum dado)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f4p1/montar-migration.mjs: as partes escritas à mão
-- e os corpos copiados da migration MAIS NOVA de cada função recriada, com cada troca "-- FASE 4:" conferida (uma vez só).
--
-- POR QUE: o prazo de cada fornecedor tem de ter uma fonte só — os prazos por classe de agenda_config (Fase 1), corrigidos
-- pelo que o dono disser do fornecedor (suppliers.modalidade/prazo_*). A regra pela cidade/UF continua como chute, agora
-- tolerante ao caractere quebrado do cadastro (NOVO-agenda-30: 197 fornecedores com "Itaja�"; a Premel caía em
-- "distribuidor SC/PR", 2 dias úteis, em vez de "entrega local", 1). Cadastro repetido vira dúvida (a pergunta sai no P5),
-- sem derrubar o cadastro principal.
--
-- O QUE MUDA:
--   1. Lugar: _agenda_lugar_normal, _agenda_lugar_casa (U+FFFD vale uma letra), _agenda_classe_por_lugar,
--      _agenda_lugar_texto ("Itajaí/SC" com a grafia de municipios_locais).
--   2. Prazo: _agenda_classe_pelo_nome, _agenda_nome_de_grupo, _agenda_classe_texto e _agenda_prazo_do_fornecedor (a fonte
--      única: dono → cadastro repetido → nome → cidade/UF); _agenda_chegada_pela_classe e _agenda_chegada_estimada (a
--      chegada: dias úteis; importado, dias corridos levados ao dia útil). _agenda_classe_do_fornecedor (Fase 1) vira o
--      invólucro da fonte única; _agenda_prazo_da_classe não muda.
--   3. os_prontidao recriada (corpo de 20261025100200): a OC ligada à linha de texto livre cobre o item; o prazo e a classe
--      vêm de _agenda_prazo_do_fornecedor; o importado é nível D com a chegada em dias corridos; "compre até" e "comprando
--      hoje" pelo mesmo prazo; o item ganha prazo_texto, duvida e corridos. Nenhum texto que já existia muda.
--   4. _agenda_rascunho_frase recriada (corpo de 20261025100400): o tipo fornecedor traz a frase pronta.
--   5. _agenda_fornecedor_dito (o fornecedor dito, com o lugar quando vem junto), agenda_rascunho_fornecedor (a RPC da
--      ferramenta fornecedor_prazo; só rascunho, com a releitura) e
--      _agenda_aplicar_fornecedor (o *grava*: suppliers.modalidade/prazo_*/prazo_fonte 'dono', e resolve as perguntas
--      fornecedor_cadastro:<fornecedor> e fornecedores_prazo).
--   6. agenda_rascunho_gravar recriada (corpo de 20261026100200): o tipo fornecedor no grupo dos fatos; a frase entra no
--      "Gravado. Agora:". A recusa "em teste" (modo_proposta) não vale para ele.
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase4_base.sql):
--   · A Kamell de Itajaí JÁ ESTÁ INATIVA em produção (SELECT de 25/10, sql/k01_kamell): para a regra da spec ("outro
--     fornecedor ATIVO com o mesmo nome"), a de Vila Velha nem teria cadastro repetido e a de Itajaí ficaria sem classe,
--     gerando a pergunta "é a mesma?" que o dono já respondeu ao desativar. O cadastro INATIVO com um ativo do mesmo nome
--     vale como o ativo que ficou (o único, ou o principal), com principal_id: o produto da Kamell de Itajaí conta 4 dias
--     úteis, sem pergunta. Com os dois ativos (a fixture de 23/10 tem assim), vale a regra da spec.
--   · O principal do cadastro repetido é escolhido em ORDEM — CNPJ de 14 dígitos primeiro, depois mais produtos + contas a
--     pagar; empate nos dois = nenhum. Lido como filtro ("só quem tem CNPJ"), a bancada (sem CNPJ, como a carteira de 23/10)
--     tiraria a classe da Kamell de Vila Velha e mudaria a prontidão da OS-00112 (E6 da Fase 1).
--   · A classe que se compara no cadastro repetido é a das regras 4–5 (nome, depois lugar), não só a do lugar: duas
--     contas do Mercado Pago em cidades diferentes são o mesmo marketplace, sem dúvida.
--   · "Compre até" do importado: a spec escrevia "p_hoje − corridos − folga"; é o INÍCIO (v_est_sm), como no dia útil:
--     agenda_somar_du(agenda_somar_du(início, −folga) − corridos + 1, −1), o último dia útil em que a compra ainda chega a
--     tempo.
--   · "Comprando hoje, chega por volta de …" (a restrição sem_previsao/compre_ate) também usa a chegada pelo prazo: com o
--     agenda_somar_du(p_hoje, prazo_du) de antes, o importado (prazo_du nulo) daria texto nulo. É o 5º bloco "-- FASE 4:"
--     de os_prontidao (a spec listava quatro).
--   · _agenda_rascunho_frase é recriada já aqui (a spec deixava para o P3): sem o tipo fornecedor ela lança e o rascunho não
--     nasce. O P3 copia desta migration.
--   · O "Gravado. Agora:" do fornecedor vai pela lista das frases dos pedidos (v_f2): a frase sai pronta do
--     _agenda_aplicar_fornecedor; não há OS para o estado da prontidão.
--   · O fornecedor dito passa por _agenda_fornecedor_dito (nova): o resolvedor da Fase 1 só casa o NOME, e a resposta à
--     pergunta "Qual Kamell: Kamell (Vila Velha/ES) ou Kamell (Itajaí/SC)?" ("a de Vila Velha", "Kamell (Vila Velha/ES)")
--     voltava "não achei" ou ambígua de novo. Com o lugar dito, ficam os cadastros que casam o nome E têm a cidade ou a UF
--     dita. _agenda_resolver_fornecedor não muda (material_informar segue com ele).
--   · Na releitura o rótulo é o da conversa de hoje: o nome curto (_agenda_nome_curto: "Mateus", não "Mateus Honório") e a
--     cidade/UF sempre ("Premel (Itajaí/SC)").
--
-- O QUE NÃO MUDA: os textos que já existiam (os testes das Fases 1–3 passam como estão, menos o E9 da Fase 1, que cobrava a
-- classe da Kamell de Itajaí — o cadastro repetido sem principal agora é dúvida, pela spec); nenhum cron, nenhuma tela; a
-- ferramenta fornecedor_prazo (ai-agent, erp-mcp) só deixa rascunho.
--
-- ORDEM DE LIGAR: depois de 20261027100000. Sem as ferramentas novas no ar, nada chama agenda_rascunho_fornecedor; a
-- prontidão muda só onde o fornecedor tem o caractere quebrado na cidade ou cadastro repetido.
--
-- PROVA: supabase/tests/agenda_fase4_base.sql (B5–B8). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261027100100_agenda_fase4_fornecedores.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261027100100', 'agenda_fase4_fornecedores');"
--
-- IDEMPOTENTE: só create or replace function, revoke/grant e comment.

-- ── 1. O lugar do fornecedor, tolerante ao caractere quebrado ───────────────────────────────────────────

-- _agenda_normal (minúsculo, sem acento, pontuação vira espaço) com o caractere quebrado (U+FFFD, "Itaja�") preservado:
-- ele atravessa a normalização como uma marca só de letras e volta no fim.
create or replace function public._agenda_lugar_normal(p text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select replace(public._agenda_normal(replace(coalesce(p, ''), chr(65533), 'qxfffdxq')), 'qxfffdxq', chr(65533));
$function$;

comment on function public._agenda_lugar_normal(text) is
  'Agenda de Produção (Fase 4): o nome de lugar normalizado como _agenda_normal (minúsculo, sem acento, pontuação vira espaço), com o caractere quebrado U+FFFD preservado como marca (NOVO-agenda-30).';

-- O lugar do cadastro casa com a referência? Igual depois de normalizar; ou, com caractere quebrado no cadastro, cada
-- U+FFFD vale uma letra qualquer e o resto tem de ser igual ("Itaja�" casa "Itajaí"; "S�o Paulo" não casa "Itajaí").
create or replace function public._agenda_lugar_casa(p_cadastro text, p_referencia text)
 returns boolean
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  a text := public._agenda_lugar_normal(p_cadastro);
  b text := public._agenda_lugar_normal(p_referencia);
begin
  if a = '' or b = '' then
    return false;
  end if;
  if a = b then
    return true;
  end if;
  if position(chr(65533) in a) = 0 then
    return false;
  end if;
  -- Depois da normalização só sobram [a-z0-9/ ] e a marca: não há o que escapar no regex.
  return b ~ ('^' || replace(a, chr(65533), '.') || '$');
end;
$function$;

comment on function public._agenda_lugar_casa(text, text) is
  'Agenda de Produção (Fase 4): o lugar do cadastro casa com a referência — igual depois de _agenda_lugar_normal, ou (cadastro com U+FFFD) com cada caractere quebrado valendo uma letra: "Itaja�" casa "Itajaí", "Balne�rio Cambori�" casa "Balneário Camboriú", "S�o Paulo" não casa "Itajaí".';

-- A classe pelo lugar: a cidade num município local, a UF SC/PR, outra UF, ou nada.
create or replace function public._agenda_classe_por_lugar(p_cidade text, p_uf text)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c public.agenda_config := public._agenda_cfg();
begin
  if public._agenda_lugar_normal(p_cidade) <> ''
     and exists (select 1 from unnest(c.municipios_locais) m where public._agenda_lugar_casa(p_cidade, m)) then
    return 'entrega_local';
  end if;
  if exists (select 1 from unnest(array['SC', 'PR', 'Santa Catarina', 'Paraná']) u where public._agenda_lugar_casa(p_uf, u)) then
    return 'distribuidor_sc_pr';
  end if;
  if public._agenda_lugar_normal(p_uf) <> '' then
    return 'outro_estado';
  end if;
  return null;
end;
$function$;

comment on function public._agenda_classe_por_lugar(text, text) is
  'Agenda de Produção (Fase 4): a classe de prazo pelo lugar — entrega_local (a cidade casa um de agenda_config.municipios_locais, tolerante ao caractere quebrado), distribuidor_sc_pr (UF SC/PR, por sigla ou por extenso), outro_estado (outra UF), null (sem cidade local e sem UF).';

-- O lugar para o dono ler: a cidade com a grafia de municipios_locais quando casa (o "Itaja�" sai "Itajaí"), a cidade toda
-- em maiúsculas com só a inicial, e a UF em sigla.
create or replace function public._agenda_lugar_texto(p_cidade text, p_uf text)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c     public.agenda_config := public._agenda_cfg();
  v_cid text := nullif(btrim(coalesce(p_cidade, '')), '');
  v_uf  text := nullif(upper(btrim(coalesce(p_uf, ''))), '');
  v_loc text;
begin
  if v_cid is not null then
    select m into v_loc from unnest(c.municipios_locais) with ordinality u(m, o)
     where public._agenda_lugar_casa(v_cid, m) order by o limit 1;
    v_cid := coalesce(v_loc, case when v_cid = upper(v_cid) then initcap(lower(v_cid)) else v_cid end);
  end if;
  if v_uf is not null and v_uf !~ '^[A-Z]{2}$' then
    v_uf := case when public._agenda_lugar_casa(p_uf, 'Santa Catarina') then 'SC'
                 when public._agenda_lugar_casa(p_uf, 'Paraná') then 'PR'
                 else btrim(p_uf) end;
  end if;
  return nullif(concat_ws('/', v_cid, v_uf), '');
end;
$function$;

comment on function public._agenda_lugar_texto(text, text) is
  'Agenda de Produção (Fase 4): o lugar do fornecedor para o dono ler ("Itajaí/SC", "Vila Velha/ES", "Curitiba/PR"): a grafia de municipios_locais quando a cidade casa (conserta o caractere quebrado), a cidade toda em maiúsculas com só a inicial, a UF em sigla. Sem cidade e sem UF = null.';

-- ── 2. O prazo do fornecedor numa fonte só ──────────────────────────────────────────────────────────────

-- A classe pelo nome: marketplace (Mercado Livre/Pago, Amazon, Shopee, Magalu) ou importado (AliExpress, Shein, Temu,
-- eBay, Banggood).
create or replace function public._agenda_classe_pelo_nome(p_nome text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
    when public._agenda_normal(p_nome) ~ '\m(mercado ?livre|mercado ?pago|amazon|shopee|magalu|magazine luiza)\M' then 'marketplace'
    when public._agenda_normal(p_nome) ~ '\m(ali ?express|shein|temu|ebay|banggood)\M' then 'importacao'
  end;
$function$;

comment on function public._agenda_classe_pelo_nome(text) is
  'Agenda de Produção (Fase 4): a classe pelo nome do fornecedor — marketplace (Mercado Livre, Mercado Pago, Amazon, Shopee, Magalu) ou importacao (AliExpress, Shein, Temu, eBay, Banggood); senão null.';

-- O nome que agrupa cadastros repetidos: _nome_comparavel (maiúsculo, sem acento, sem LTDA/ME/EPP/EIRELI/SA/CIA) sem
-- "comércio" ("KAMELL COMERCIO GLOBAL LTDA" e "Kamell Comercio Global" são "KAMELL GLOBAL").
create or replace function public._agenda_nome_de_grupo(p text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select btrim(regexp_replace(regexp_replace(public._nome_comparavel(p), '\mCOMERCIO\M', ' ', 'g'), '\s+', ' ', 'g'));
$function$;

comment on function public._agenda_nome_de_grupo(text) is
  'Agenda de Produção (Fase 4): o nome comparável do fornecedor para achar cadastro repetido — _nome_comparavel sem "comércio".';

-- A frase da classe: "balcão, na mão no mesmo dia" / "entrega local, 1 dia útil" / "outro estado, 4 dias úteis" /
-- "importado, 20 dias corridos".
create or replace function public._agenda_classe_texto(p_classe text, p_du integer, p_corridos integer)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case p_classe
    when 'balcao' then 'balcão, ' || case when coalesce(p_du, 0) = 0 then 'na mão no mesmo dia'
                                          else public._agenda_plural(p_du, 'dia útil', 'dias úteis') end
    when 'entrega_local' then 'entrega local, ' || public._agenda_plural(p_du, 'dia útil', 'dias úteis')
    when 'distribuidor_sc_pr' then 'transportadora de SC/PR, ' || public._agenda_plural(p_du, 'dia útil', 'dias úteis')
    when 'outro_estado' then 'outro estado, ' || public._agenda_plural(p_du, 'dia útil', 'dias úteis')
    when 'marketplace' then 'compra pela internet, ' || public._agenda_plural(p_du, 'dia útil', 'dias úteis')
    when 'importacao' then 'importado, ' || public._agenda_plural(p_corridos, 'dia corrido', 'dias corridos')
  end;
$function$;

comment on function public._agenda_classe_texto(text, integer, integer) is
  'Agenda de Produção (Fase 4): a frase de uma classe de prazo com os dias ("balcão, na mão no mesmo dia", "entrega local, 1 dia útil", "transportadora de SC/PR, 2 dias úteis", "outro estado, 4 dias úteis", "compra pela internet, 3 dias úteis", "importado, 20 dias corridos"). Sem jargão: nunca "du".';

-- O prazo do fornecedor: {classe, du, corridos, fonte, duvida, principal_id, texto}. A 1ª regra que valer:
--   1. sem fornecedor (ou inexistente): tudo nulo;
--   2. o que o dono disse (suppliers.modalidade): a classe dele, os dias dele ou os da classe; fonte 'dono';
--   3. cadastro repetido (outro cadastro ATIVO com o mesmo nome de grupo):
--      · este cadastro é INATIVO (o dono já tirou de uso): vale o prazo do cadastro que ficou (o único ativo, ou o principal
--        dos ativos), com principal_id — o caso da Kamell de Itajaí em produção (25/10);
--      · os dois ativos com classe diferente (pelas regras 4 e 5): o principal é o de CNPJ de 14 dígitos e, depois, o de
--        mais produtos + contas a pagar (empate = nenhum). Quem não é o principal fica sem classe (duvida 'duplicado');
--        o principal segue para as regras 4–5 com duvida 'duplicado' (a pergunta sai, a classe vale);
--   4. pelo nome: marketplace ou importado (os corridos de agenda_config.importacao_dias); fonte 'nome';
--   5. pela cidade/UF (tolerante ao caractere quebrado); fonte 'cidade'. Nada = sem classe (duvida 'sem_lugar').
-- Os dias da classe são os de agenda_config.prazo_classe_du (a fonte única); o importado conta em dias corridos.
create or replace function public._agenda_prazo_do_fornecedor(p_fornecedor uuid)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c          public.agenda_config := public._agenda_cfg();
  s          public.suppliers%rowtype;
  v_vazio    constant jsonb := jsonb_build_object('classe', null, 'du', null, 'corridos', null, 'fonte', null,
                                                  'duvida', null, 'principal_id', null, 'texto', null);
  v_nome_g   text;
  v_grupo    jsonb := '[]'::jsonb;
  v_ativo    boolean;
  v_n        int := 0;
  v_classes  int := 0;
  v_um       uuid;
  v_princ    uuid;
  v_top      record;
  v_empate   int;
  v_duvida   text;
  v_classe   text;
  v_fonte    text;
  v_du       int;
  v_corr     int;
begin
  if p_fornecedor is null then
    return v_vazio;
  end if;
  select * into s from public.suppliers where id = p_fornecedor;
  if not found then
    return v_vazio;
  end if;
  v_ativo := coalesce(s.active, true);

  if s.modalidade is not null then
    v_classe := s.modalidade;
    v_fonte := 'dono';
  else
    v_nome_g := public._agenda_nome_de_grupo(coalesce(nullif(btrim(s.trade_name), ''), s.name));
    if v_nome_g <> '' then
      -- O grupo: este cadastro e os outros ATIVOS com o mesmo nome, com a classe que as regras 4–5 dariam a cada um, se
      -- tem CNPJ de 14 dígitos e o peso (produtos + contas a pagar).
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', o.id, 'ativo', coalesce(o.active, true), 'eu', o.id = s.id,
               'classe', coalesce(public._agenda_classe_pelo_nome(concat_ws(' ', o.name, o.trade_name, o.display_name)),
                                  public._agenda_classe_por_lugar(o.city, o.state)),
               'cnpj14', length(regexp_replace(coalesce(o.cnpj_cpf, ''), '\D', '', 'g')) = 14,
               'peso', (select count(*) from public.products pr where pr.supplier_id = o.id)
                       + (select count(*) from public.payables pa where pa.supplier_id = o.id))
               order by o.id), '[]'::jsonb)
        into v_grupo
        from public.suppliers o
       where (o.id = s.id or coalesce(o.active, true))
         and public._agenda_nome_de_grupo(coalesce(nullif(btrim(o.trade_name), ''), o.name)) = v_nome_g;
      select count(*), min(e ->> 'id')
        into v_n, v_um
        from jsonb_array_elements(v_grupo) e
       where not (e ->> 'eu')::boolean;
    end if;

    if v_n > 0 then
      -- Os candidatos a principal: os ativos do grupo (o próprio só quando também está ativo).
      select (e ->> 'cnpj14')::boolean as cnpj14, (e ->> 'peso')::bigint as peso, (e ->> 'id')::uuid as id into v_top
        from jsonb_array_elements(v_grupo) e
       where (e ->> 'ativo')::boolean
       order by (e ->> 'cnpj14')::boolean desc, (e ->> 'peso')::bigint desc, e ->> 'id'
       limit 1;
      select count(*) into v_empate
        from jsonb_array_elements(v_grupo) e
       where (e ->> 'ativo')::boolean and (e ->> 'cnpj14')::boolean = v_top.cnpj14 and (e ->> 'peso')::bigint = v_top.peso;
      v_princ := case when v_empate = 1 then v_top.id end;

      if not v_ativo then
        -- O cadastro que o dono já tirou de uso vale como o que ficou: o único ativo, ou o principal dos ativos.
        v_um := case when v_n = 1 then v_um else v_princ end;
        if v_um is not null then
          return public._agenda_prazo_do_fornecedor(v_um) || jsonb_build_object('principal_id', v_um);
        end if;
        return v_vazio || jsonb_build_object('duvida', 'duplicado');
      end if;

      select count(distinct coalesce(e ->> 'classe', '-')) into v_classes
        from jsonb_array_elements(v_grupo) e
       where (e ->> 'ativo')::boolean;
      if v_classes > 1 then
        if v_princ is distinct from s.id then
          return v_vazio || jsonb_build_object('duvida', 'duplicado', 'principal_id', v_princ);
        end if;
        v_duvida := 'duplicado';
      else
        v_princ := null;
      end if;
    end if;

    v_classe := public._agenda_classe_pelo_nome(concat_ws(' ', s.name, s.trade_name, s.display_name));
    if v_classe is not null then
      v_fonte := 'nome';
    else
      v_classe := public._agenda_classe_por_lugar(s.city, s.state);
      v_fonte := case when v_classe is not null then 'cidade' end;
    end if;
  end if;

  if v_classe is null then
    return v_vazio || jsonb_build_object('duvida', coalesce(v_duvida, 'sem_lugar'), 'principal_id', v_princ);
  end if;
  if v_classe = 'importacao' then
    v_corr := case when v_fonte = 'dono' then coalesce(s.prazo_dias_corridos, c.importacao_dias) else c.importacao_dias end;
  else
    v_du := case when v_fonte = 'dono' then coalesce(s.prazo_dias_uteis, (c.prazo_classe_du ->> v_classe)::int)
                 else (c.prazo_classe_du ->> v_classe)::int end;
  end if;
  return jsonb_build_object('classe', v_classe, 'du', v_du, 'corridos', v_corr, 'fonte', v_fonte, 'duvida', v_duvida,
    'principal_id', v_princ,
    'texto', public._agenda_classe_texto(v_classe, v_du, v_corr)
             || case v_fonte when 'dono' then ' (você disse)' when 'cidade' then ' (pela cidade, chute meu)'
                             else ' (pelo nome)' end);
end;
$function$;

comment on function public._agenda_prazo_do_fornecedor(uuid) is
  'Agenda de Produção (Fase 4): o prazo do fornecedor numa fonte só, {classe, du, corridos, fonte, duvida, principal_id, texto}. A 1ª regra que valer: o que o dono disse (suppliers.modalidade, fonte dono) → cadastro repetido (outro ativo com o mesmo nome de grupo: o inativo vale como o ativo que ficou; dois ativos de classe diferente = só o principal, CNPJ de 14 dígitos e mais produtos + contas, tem classe, os dois com duvida duplicado) → pelo nome (marketplace, importado; fonte nome) → pela cidade/UF tolerante ao caractere quebrado (fonte cidade) → nada (duvida sem_lugar). Os dias: os do dono, senão os da classe (agenda_config.prazo_classe_du); importado em dias corridos (agenda_config.importacao_dias). texto: "entrega local, 1 dia útil (pela cidade, chute meu)".';

-- A chegada pela classe: dias úteis a partir do dia; importado, os dias corridos levados ao dia útil (o próprio, ou o
-- próximo). Classe nula = null.
create or replace function public._agenda_chegada_pela_classe(p_classe text, p_du integer, p_corridos integer, p_desde date)
 returns date
 language plpgsql
 stable
 set search_path to 'public'
as $function$
begin
  if p_classe is null or p_desde is null then
    return null;
  end if;
  if p_classe = 'importacao' then
    return public.agenda_somar_du(p_desde + coalesce(p_corridos, (public._agenda_cfg()).importacao_dias), 0);
  end if;
  if p_du is null then
    return null;
  end if;
  return public.agenda_somar_du(p_desde, p_du);
end;
$function$;

comment on function public._agenda_chegada_pela_classe(text, integer, integer, date) is
  'Agenda de Produção (Fase 4): a chegada estimada por classe e prazo — agenda_somar_du(desde, du); importado: agenda_somar_du(desde + corridos, 0) (os dias corridos levados ao dia útil); classe nula ou sem dias = null. A da remessa sem fornecedor cadastrado usa esta com a classe do lugar do XML.';

create or replace function public._agenda_chegada_estimada(p_fornecedor uuid, p_desde date)
 returns date
 language sql
 stable
 set search_path to 'public'
as $function$
  select public._agenda_chegada_pela_classe(j ->> 'classe', (j ->> 'du')::int, (j ->> 'corridos')::int, p_desde)
    from (select public._agenda_prazo_do_fornecedor(p_fornecedor) as j) x;
$function$;

comment on function public._agenda_chegada_estimada(uuid, date) is
  'Agenda de Produção (Fase 4): a chegada estimada de uma compra do fornecedor a partir de p_desde, pelo prazo dele (_agenda_prazo_do_fornecedor → _agenda_chegada_pela_classe). Classe desconhecida = null.';

-- A classe do fornecedor (Fase 1, 160400:582) vira um invólucro da fonte única.
create or replace function public._agenda_classe_do_fornecedor(p_fornecedor uuid)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select public._agenda_prazo_do_fornecedor(p_fornecedor) ->> 'classe';
$function$;

comment on function public._agenda_classe_do_fornecedor(uuid) is
  'Agenda de Produção (Fase 1, P3; Fase 4: invólucro de _agenda_prazo_do_fornecedor): a classe de prazo do fornecedor — a que o dono disse (suppliers.modalidade), a do cadastro repetido, marketplace/importado pelo nome, entrega_local (cidade em agenda_config.municipios_locais, tolerante ao caractere quebrado), distribuidor_sc_pr (UF SC/PR), outro_estado (outra UF); sem cidade e sem UF, cadastro repetido que não é o principal, ou sem fornecedor = null (desconhecida).';

-- ── 3. A prontidão com o prazo do fornecedor ────────────────────────────────────────────────────────────
-- Corpo de 20261025100200 copiado; as mudanças estão marcadas "-- FASE 4: … -- FASE 4: fim" (o teste B7 confere que,
-- fora delas, a cópia é linha a linha a da Fase 2).

create or replace function public.os_prontidao(p_so_id uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c            public.agenda_config := public._agenda_cfg();
  so           record;
  p            public.os_planejamento%rowtype;
  v_na_cart    boolean;
  v_aprov      date;
  v_pago       numeric := 0;
  v_pend       numeric := 0;
  v_ag_de      date;
  v_ag_ate     date;
  v_bem_nome   text;
  v_d_bem      date;
  v_bem_tudo   boolean := false;
  v_horizonte  date;
  v_base       date;
  v_est_sm     date;
  v_bruto      jsonb;
  v_itens      jsonb;
  v_crit       jsonb;
  v_embut      jsonb;
  v_n_itens    int;
  v_conferido  boolean;
  v_mat_estado text;
  v_dpm        date;
  v_gargalo    jsonb;
  v_confianca  text;
  v_inicio_mat date;
  v_est        date;
  v_sug        jsonb;
  v_dur        jsonb;
  v_equipe     jsonb;
  v_meios      numeric;
  v_diarias_eq numeric;
  v_dias_re    numeric;
  v_pres       jsonb;
  v_prazo      date;
  v_prazo_fnt  text;
  v_razao      numeric;
  v_r          jsonb := '[]'::jsonb;
  v_estado     text;
  v_estado_txt text;
  v_principal  jsonb;
  v_quase      boolean := false;
  v_parada     boolean := false;
  v_ult_diaria date;
  v_x          jsonb;
  v_compra     jsonb;
  v_n          int;
  v_n_falta    int := 0;
  v_n_sem      int;
  v_txt        text;
  v_cond       text;
  v_dono_padrao boolean;
  v_cc         record;
  -- FASE 2: o que o plano publicado diz da OS (spec-fase2 §6.1)
  v_plano      jsonb;
  v_ult_evid   date;
  v_tem_futuro boolean := false;
  -- FASE 2: fim
begin
  if p_hoje is null then
    raise exception 'os_prontidao: sem o dia de hoje' using errcode = '22004';
  end if;

  select o.*, cl.name as cliente_nome, vs.name as bem, vs.asset_type as bem_tipo,
         mg.service_order_number as juntado_em
    into so
    from public.service_orders o
    left join public.clients cl on cl.id = o.client_id
    left join public.vessels vs on vs.id = o.vessel_id
    left join public.service_orders mg on mg.id = o.merged_into_id
   where o.id = p_so_id;
  if not found then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
  end if;

  select * into p from public.os_planejamento where service_order_id = p_so_id;

  -- Carteira, aprovação, sinal e janela antiga: a MESMA conta de os_carteira (fora dela, a mesma fórmula).
  select true, k.aprovada_em, k.sinal_pago, k.sinal_pendente, k.agendada_de, k.agendada_ate
    into v_na_cart, v_aprov, v_pago, v_pend, v_ag_de, v_ag_ate
    from public.os_carteira(p_hoje) k where k.service_order_id = p_so_id;
  if not found then
    v_na_cart := false;
    v_aprov := (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date;
    select coalesce(sum(coalesce(r.paid_amount, 0)), 0),
           coalesce(sum(case when r.status in ('pending', 'partially_paid', 'overdue')
                             then greatest(r.amount - coalesce(r.paid_amount, 0), 0) else 0 end), 0)
      into v_pago, v_pend
      from public.receivables r
     where r.service_order_id = p_so_id and r.is_deposit and r.status <> 'cancelled';
    v_ag_de := (so.scheduled_start_at at time zone 'America/Sao_Paulo')::date;
    v_ag_ate := (coalesce(so.scheduled_end_at, so.scheduled_start_at) at time zone 'America/Sao_Paulo')::date;
  end if;

  -- O bem (barco, motorhome): 1º dia a partir de amanhã fora de bem_indisponivel; null = fora sem data de volta.
  v_bem_nome := case when public._agenda_normal(coalesce(so.bem_tipo, so.bem)) ~ 'motorhome|motor home|trailer'
                     then 'o motorhome' else 'o barco' end;
  v_horizonte := p_hoje + 7 * c.horizonte_semanas;
  v_d_bem := p_hoje + 1;
  if p.service_order_id is not null and not isempty(p.bem_indisponivel) and p.bem_indisponivel @> v_d_bem then
    select upper(r) into v_d_bem from unnest(p.bem_indisponivel) r where r @> (p_hoje + 1);
  end if;
  v_bem_tudo := v_d_bem is null or v_d_bem > v_horizonte;

  -- O início mais cedo sem olhar o material: o bem livre, o "não antes de" e o congelamento (hoje + o próximo
  -- dia útil ficam como estão).
  v_base := public.agenda_somar_du(p_hoje, c.congelamento_du + 1);
  v_est_sm := greatest(v_d_bem, p.nao_antes_de, v_base);

  -- ── Material efetivo: a conta bruta + o que foi informado em os_material ──
  v_bruto := public.os_necessidade_bruta(p_so_id);

  with
  bruto as (
    select x.ord, x.i ->> 'origin' as origin, (x.i ->> 'sourceId')::uuid as src,
           (x.i ->> 'required')::numeric as req, coalesce((x.i ->> 'available')::numeric, 0) as disp,
           x.i ->> 'status' as st, (x.i ->> 'productId')::uuid as prod, x.i ->> 'description' as descr
      from jsonb_array_elements(coalesce(v_bruto -> 'items', '[]'::jsonb)) with ordinality x(i, ord)
     where coalesce((x.i ->> 'required')::numeric, 0) > 0
       and x.i ->> 'origin' in ('part', 'free_text', 'purchase_order')
  ),
  cand as (
    -- (1) os itens da conta bruta, com a linha do mesmo vínculo
    select 1 as grupo, b.ord::bigint as ord,
           case b.origin when 'part' then 'peca' when 'free_text' then 'texto_livre' else 'oc' end as origem,
           b.src as vinculo, b.req, b.disp, b.st, b.descr, b.prod, null::uuid as po_forn, null::date as recebido_em,
           m as l
      from bruto b
      left join public.os_material m
        on m.service_order_id = p_so_id
       and m.origem = case b.origin when 'part' then 'peca' when 'free_text' then 'texto_livre' else 'oc' end
       and b.src = case m.origem when 'peca' then m.service_order_part_id
                                 when 'texto_livre' then m.service_order_service_id
                                 else m.purchase_order_item_id end
    union all
    -- (2) item de OC de texto livre da OS que já chegou (saiu da conta bruta) — continua, na mão
    select 2, row_number() over (order by po.created_at, poi.id), 'oc', poi.id, poi.quantity, poi.quantity,
           'recebido', poi.description, null, po.supplier_id, po.received_date, m
      from public.purchase_order_items poi
      join public.purchase_orders po on po.id = poi.purchase_order_id
      left join public.os_material m on m.origem = 'oc' and m.purchase_order_item_id = poi.id
     where po.service_order_id = p_so_id and poi.product_id is null and poi.quantity > 0
       and po.status <> 'cancelled'
       and (po.status = 'received' or coalesce(poi.received_qty, 0) >= poi.quantity)
    union all
    -- (3) item de OC cancelada que tinha linha: a sincronização o devolveu a "falta" (ou o dono informou)
    select 3, row_number() over (order by po.created_at, poi.id), 'oc', poi.id, poi.quantity, 0,
           'cancelado', poi.description, null, po.supplier_id, null, m
      from public.os_material m
      join public.purchase_order_items poi on poi.id = m.purchase_order_item_id
      join public.purchase_orders po on po.id = poi.purchase_order_id
     where m.service_order_id = p_so_id and m.origem = 'oc' and po.status = 'cancelled'
    union all
    -- (4) o que o dono citou e não está no orçamento (peça embutida, material novo)
    select 4, row_number() over (order by m.descricao, m.id), 'dono', m.service_order_service_id,
           m.quantidade_necessaria, 0, 'dono', m.descricao, null, null, null, m
      from public.os_material m
     where m.service_order_id = p_so_id and m.origem = 'dono'
  ),
  passo1 as (
    select k.*,
           coalesce((k.l).fonte in ('dono', 'fornecedor', 'nfe', 'pix'), false) as informado,
           coalesce((k.l).critico, true) as critico
      from cand k
     where (k.l).situacao is distinct from 'dispensado'
  ),
  passo2 as (
    select q.*,
           case when q.grupo = 1
                then greatest(q.disp, case when q.informado then least(q.req, (q.l).quantidade_na_mao) else 0 end)
                else 0 end as disp_ef
      from passo1 q
  ),
  passo3 as (
    -- A situação efetiva. Só o fato informado muda o item; "na mão" só com a quantidade completa contra a conta de
    -- hoje; o que o dono disse para menos do que a OS pede hoje volta a faltar.
    select q.*,
           case
             when q.grupo = 2 then case when q.informado and (q.l).situacao <> 'na_mao' then (q.l).situacao else 'na_mao' end
             when q.grupo = 4 then (q.l).situacao
             when q.grupo = 3 then case when q.informado then (q.l).situacao else 'falta' end
             when q.disp_ef >= q.req then 'na_mao'
             when q.informado and (q.l).situacao in ('na_mao', 'comprado', 'a_caminho')
                  and (q.l).quantidade_necessaria < q.req then 'falta'
             when q.informado and (q.l).situacao = 'na_mao' then 'falta'
             when q.informado then (q.l).situacao
             when q.st = 'on_order' then 'a_caminho'
             else 'falta' end as sit
      from passo2 q
  ),
  passo4 as (
    -- A OC que cobre o item que o sistema vê "a caminho" (a da própria OS primeiro): previsão, data e fornecedor.
    select q.*, oc.expected_date as oc_prev, oc.criada as oc_criada, oc.po_number as oc_numero, oc.forn as oc_forn,
           pr.supplier_id as prod_forn
      from passo3 q
      left join public.products pr on pr.id = q.prod
      left join lateral (
        select v.expected_date, (v.po_criada_em at time zone 'America/Sao_Paulo')::date as criada, v.po_number,
               po.supplier_id as forn
          from public.v_oc_itens_a_caminho v
          join public.purchase_orders po on po.id = v.purchase_order_id
         where q.grupo = 1 and q.sit = 'a_caminho' and not q.informado and v.pendente > 0
           and case when q.origem = 'oc' then v.purchase_order_item_id = q.vinculo
                    -- FASE 4: o item de texto livre é coberto pela linha da OC ligada a ele (service_order_service_id, P2).
                    when q.origem = 'texto_livre' then v.service_order_service_id = q.vinculo
                    -- FASE 4: fim
                    else v.product_id = q.prod and v.conta_como_ja_pedido end
         order by (v.service_order_id is distinct from p_so_id), v.po_criada_em, v.purchase_order_item_id
         limit 1) oc on true
  ),
  passo5 as (
    select q.*,
           case
             when q.sit = 'na_mao' and q.grupo = 1 and q.disp >= q.req and not q.informado then 'estoque'
             when q.informado then (q.l).fonte
             when q.grupo = 2 then 'oc'
             when q.sit = 'a_caminho' and q.grupo = 1 then 'oc'
             else (q.l).fonte end as fonte,
           case when q.sit in ('comprado', 'a_caminho') then
                  case when q.informado then (q.l).previsao_ate when q.grupo = 1 then q.oc_prev end end as prev_ate,
           case when q.sit in ('comprado', 'a_caminho') then
                  case when q.informado then (q.l).previsao_fonte
                       when q.grupo = 1 and q.oc_prev is not null then 'oc' end end as prev_fonte,
           -- O informado sem data de compra conta do dia em que o dono contou (conferido_em): a estimativa não anda.
           case when q.sit in ('comprado', 'a_caminho') then
                  case when q.informado
                       then coalesce((q.l).comprado_em, ((q.l).conferido_em at time zone 'America/Sao_Paulo')::date)
                       when q.grupo = 1 then q.oc_criada end end as comprado_em,
           case when q.sit = 'falta' and q.informado then (q.l).compra_prevista_em end as compra_prevista_em,
           case when q.sit = 'na_mao' then
                  case when q.informado or q.grupo = 4 then (q.l).chegou_em
                       when q.grupo = 2 then coalesce((q.l).chegou_em, q.recebido_em)
                       when (q.l).situacao = 'na_mao' then (q.l).chegou_em end end as chegou_em,
           -- O fornecedor: o que o dono disse (cadastrado ou só o nome), senão o da OC, senão o do produto.
           case when q.informado and (q.l).fornecedor_id is null and (q.l).fornecedor_nome is not null then null
                else coalesce(case when q.informado then (q.l).fornecedor_id end, q.oc_forn, q.po_forn,
                              (q.l).fornecedor_id, q.prod_forn) end as forn_id,
           case when q.informado and (q.l).fornecedor_id is null then (q.l).fornecedor_nome end as forn_nome
      from passo4 q
  ),
  passo6 as (
    -- FASE 4: o prazo do fornecedor numa fonte só (_agenda_prazo_do_fornecedor: o que o dono disse, o cadastro repetido,
    -- o nome e a cidade/UF tolerante ao caractere quebrado); a classe, os dias úteis e os corridos saem dele no passo 7.
    select q.*, public._agenda_prazo_do_fornecedor(q.forn_id) as pf
    -- FASE 4: fim
      from passo5 q
  ),
  passo7 as (
    -- FASE 4: a classe e os dias úteis do fornecedor; o importado tem os dias corridos (e prazo nulo).
    select q.*, q.pf ->> 'classe' as classe, (q.pf ->> 'du')::int as prazo, (q.pf ->> 'corridos')::int as corridos
    -- FASE 4: fim
      from passo6 q
  ),
  passo8 as (
    select q.*,
           case
             when q.sit = 'na_mao' then 'A'
             when q.sit in ('comprado', 'a_caminho') and q.prev_ate is not null and q.prev_fonte <> 'dono' then 'B'
             when q.sit in ('comprado', 'a_caminho') and q.prev_ate is not null then 'C'
             when q.sit in ('comprado', 'a_caminho') then 'D'
             -- FASE 4: o importado tem prazo (em dias corridos).
             when q.prazo is not null or q.corridos is not null then 'D'
             -- FASE 4: fim
             else 'E' end as nivel,
           case
             when q.sit = 'na_mao' then q.chegou_em
             when q.sit in ('comprado', 'a_caminho') and q.prev_ate is not null then q.prev_ate
             -- FASE 4: a chegada pelo prazo do fornecedor (_agenda_chegada_pela_classe: dias úteis; o importado, os dias
             -- corridos levados ao dia útil).
             when q.sit in ('comprado', 'a_caminho') and (q.prazo is not null or q.corridos is not null) then
               public._agenda_chegada_pela_classe(q.classe, q.prazo, q.corridos, coalesce(q.comprado_em, p_hoje))
             when q.sit = 'falta' and (q.prazo is not null or q.corridos is not null) then
               -- "Se comprar hoje" (ou no dia combinado): calculado, nunca gravado.
               public._agenda_chegada_pela_classe(q.classe, q.prazo, q.corridos,
                                                  greatest(coalesce(q.compra_prevista_em, p_hoje), p_hoje))
             -- FASE 4: fim
           end as data,
           -- FASE 4: "compre até" pelo mesmo prazo; o importado: o início menos a folga, menos os dias corridos, no último dia
           -- útil até ali (agenda_somar_du(x + 1, -1) é o último dia útil até x).
           case when q.sit = 'falta' and q.prazo is not null and q.compra_prevista_em is null then
             public.agenda_somar_du(v_est_sm, -(c.folga_material_du + q.prazo))
                when q.sit = 'falta' and q.corridos is not null and q.compra_prevista_em is null then
             public.agenda_somar_du(public.agenda_somar_du(v_est_sm, -c.folga_material_du) - q.corridos + 1, -1) end as compre_ate,
           -- FASE 4: fim
           (select f.name from public.suppliers f where f.id = q.forn_id) as forn_cadastro
      from passo7 q
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', (q.l).id, 'linha', q.vinculo, 'origem', q.origem,
           'descricao', coalesce((q.l).descricao, q.descr), 'curto', public._agenda_linha_curta(coalesce((q.l).descricao, q.descr)),
           'nivel', q.nivel, 'situacao', q.sit, 'data', q.data,
           -- Parcial (parte já na mão, informada ou do estoque): quantas estão na mão e quantas faltam, antes do resto.
           'data_texto', case when q.sit <> 'na_mao' and q.disp_ef > 0 and q.disp_ef < q.req
                              then format('%s de %s na mão, %s %s: ', replace(trim_scale(q.disp_ef)::text, '.', ','),
                                          replace(trim_scale(q.req)::text, '.', ','),
                                          case when q.req - q.disp_ef = 1 then 'falta' else 'faltam' end,
                                          replace(trim_scale(q.req - q.disp_ef)::text, '.', ','))
                              else '' end
           || case
              when q.nivel = 'A' then case when q.data is not null then 'na mão desde ' || public._dia_curto(q.data) else 'na mão' end
              when q.nivel = 'B' then 'chega ' || public._dia_curto(q.data) || case q.prev_fonte
                   when 'oc' then ' (pela OC)' when 'fornecedor' then ' (o fornecedor disse)'
                   when 'nfe' then ' (pela nota)' when 'pix' then ' (pelo Pix)' else '' end
              when q.nivel = 'C' then 'chega ' || public._dia_curto(q.data) || ' (você disse)'
              when q.sit in ('comprado', 'a_caminho') then
                   coalesce('pedido em ' || to_char(q.comprado_em, 'DD/MM'), 'comprado')
                   || case when q.data is not null then ', deve chegar por volta de ' || public._dia_curto(q.data)
                           else ', sem previsão' end
              when q.nivel = 'D' then
                   case when q.compra_prevista_em is not null and q.compra_prevista_em >= p_hoje
                        then format('comprando %s, chega por volta de %s', public._dia_curto(q.compra_prevista_em),
                                    public._dia_curto(q.data))
                        else 'se comprar hoje, chega por volta de ' || public._dia_curto(q.data) end
              when q.forn_nome is not null then format('a comprar de %s, sem prazo conhecido', q.forn_nome)
              when q.forn_id is not null then format('a comprar de %s, sem cidade/UF no cadastro', public._agenda_nome_curto(q.forn_cadastro))
              else 'a comprar, sem fornecedor' end,
           'fonte', q.fonte, 'previsao_fonte', q.prev_fonte, 'trecho', (q.l).trecho, 'critico', q.critico,
           'quantidade', trim_scale(q.req), 'na_mao', trim_scale(case when q.sit = 'na_mao' then q.req else q.disp_ef end),
           'fornecedor', coalesce(q.forn_nome, public._agenda_nome_curto(q.forn_cadastro)),
           'classe', q.classe, 'prazo_du', q.prazo,
           -- FASE 4: o texto do prazo do fornecedor ("entrega local, 1 dia útil (pela cidade, chute meu)"), a dúvida do
           -- cadastro (duplicado | sem_lugar) e os dias corridos do importado.
           'prazo_texto', q.pf ->> 'texto', 'duvida', q.pf ->> 'duvida', 'corridos', q.corridos,
           -- FASE 4: fim
           'comprado_em', q.comprado_em, 'compra_prevista_em', q.compra_prevista_em,
           'compre_ate', q.compre_ate,
           'atrasado', q.sit in ('comprado', 'a_caminho') and q.data is not null and q.data < p_hoje,
           'sem_data', q.nivel = 'E' or (q.nivel = 'D' and q.data is null))
           order by q.grupo, q.ord), '[]'::jsonb)
    into v_itens
    from passo8 q;

  v_crit := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_itens) with ordinality t(e, o)
                       where (e ->> 'critico')::boolean), '[]'::jsonb);
  v_n_itens := jsonb_array_length(v_itens);
  v_conferido := p.material_conferido_em is not null
              or exists (select 1 from public.os_material m
                          where m.service_order_id = p_so_id and m.fonte in ('dono', 'fornecedor', 'nfe', 'pix'));

  -- "Tem peça embutida?": linha de texto livre que NÃO entra na compra e (a) vale >= peca_embutida_acima, ou (b) o
  -- classificador lê como material (a unidade não é 'unit'), ou (c) cita peça/material. Some quando o dono responde
  -- por ela (linha do dono ligada à linha) ou quando ele diz "não tem peça a comprar" depois que a linha nasceu.
  select coalesce(jsonb_agg(jsonb_build_object('linha', s.id, 'nome', s.name_snapshot,
                                               'curto', public._agenda_linha_curta(s.name_snapshot),
                                               'valor', s.line_total)
                            order by s.line_total desc nulls last, s.created_at, s.id), '[]'::jsonb)
    into v_embut
    from public.service_order_services s
   where s.service_order_id = p_so_id and s.service_id is null
     and not (s.billing_unit_snapshot = 'unit' and coalesce(s.quantity, 0) > 0 and public.free_text_is_material(s.name_snapshot))
     and (coalesce(s.line_total, 0) >= c.peca_embutida_acima
          or public.free_text_is_material(s.name_snapshot)
          or public._agenda_normal(s.name_snapshot) ~ '\m(peca|pecas|material)\M')
     and not exists (select 1 from public.os_material m
                      where m.service_order_id = p_so_id and m.origem = 'dono' and m.service_order_service_id = s.id)
     and not (p.material_conferido_em is not null and p.material_conferido_em > s.created_at);

  -- O estado do material (do mais forte ao mais fraco).
  v_mat_estado := case
    when exists (select 1 from jsonb_array_elements(v_crit) e where (e ->> 'atrasado')::boolean) then 'atrasado'
    when exists (select 1 from jsonb_array_elements(v_crit) e where (e ->> 'sem_data')::boolean) then 'sem_previsao'
    when jsonb_array_length(v_embut) > 0 or (v_n_itens = 0 and not v_conferido) then 'nao_conferido'
    when exists (select 1 from jsonb_array_elements(v_crit) e where e ->> 'nivel' <> 'A') then 'previsto'
    else 'completo' end;

  -- DPM: a data mais tarde dos críticos fora de A; o início pelo material = chegada + folga_material_du, sem folga
  -- remota (revisão §7: o prazo "outro estado" já cobre o transporte).
  if v_mat_estado not in ('atrasado', 'sem_previsao') then
    select e into v_gargalo from jsonb_array_elements(v_crit) with ordinality t(e, o)
     where e ->> 'nivel' <> 'A' order by (e ->> 'data')::date desc, o limit 1;
    v_dpm := (v_gargalo ->> 'data')::date;
    if v_dpm is not null then
      v_inicio_mat := public.agenda_somar_du(v_dpm, c.folga_material_du);
    end if;
    v_est := greatest(v_est_sm, v_inicio_mat);
  end if;
  v_confianca := (select e ->> 'nivel' from jsonb_array_elements(v_crit) e
                   order by case e ->> 'nivel' when 'E' then 0 when 'D' then 1 when 'C' then 2 when 'B' then 3 else 4 end
                   limit 1);

  -- ── Duração ──
  v_sug := public.os_duracao_sugerida(p_so_id);
  v_dono_padrao := exists (select 1 from public.agenda_disponibilidade d
                            where d.payee_id = public._agenda_dono(null) and d.substituida_em is null
                              and d.dias_semana is not null and d.situacao = 'disponivel');
  if p.dias is not null then
    select coalesce(jsonb_agg(jsonb_build_object('payee_id', e.payee_id, 'nome', public._agenda_nome_curto(py.name),
                                                 'eh_dono', py.kind = 'socio', 'turnos', e.turnos)
                              -- você primeiro; quem vai o dia todo antes de quem vai meio turno
                              order by py.kind = 'socio' desc, e.turnos = 'dia' desc, py.name, e.payee_id), '[]'::jsonb),
           -- Meios-dias por pessoa: o dia todo = 2 por dia; só de manhã ou só à tarde = 1 turno em cada dia que o
           -- serviço ocupa (meio dia com o João à tarde = 1 meio-dia; 1,5 dia à tarde = 2).
           coalesce(sum(case when e.turnos = 'dia' then p.dias * 2 else ceil(p.dias) end), 0)
      into v_equipe, v_meios
      from public.os_planejamento_equipe e
      join public.payees py on py.id = e.payee_id
     where e.service_order_id = p_so_id;
    -- Sem equipe dita, a conta de diárias usa as pessoas da sugestão (é leitura, não vira número gravado). Na conta da
    -- equipe (a que a capacidade cobre), você só entra quando tem padrão.
    v_diarias_eq := case when jsonb_array_length(v_equipe) = 0
                         then p.dias * coalesce((v_sug ->> 'pessoas')::int, 1)
                         else (select coalesce(sum(case when e.turnos = 'dia' then p.dias * 2 else ceil(p.dias) end), 0) / 2
                                 from public.os_planejamento_equipe e join public.payees py on py.id = e.payee_id
                                where e.service_order_id = p_so_id
                                  and (py.kind <> 'socio' or v_dono_padrao)) end;
    v_dur := jsonb_build_object(
      'fonte', p.estimativa_fonte, 'dias', trim_scale(p.dias), 'equipe', v_equipe,
      'meios_dias', trim_scale(v_meios),
      'diarias', trim_scale(case when jsonb_array_length(v_equipe) = 0
                                 then p.dias * coalesce((v_sug ->> 'pessoas')::int, 1)
                                 else v_meios / 2 end),
      'diarias_equipe', trim_scale(v_diarias_eq),
      -- Diárias-pessoa da equipe para o backlog: o que o dono disse é um número só (otimista = realista).
      'dp_otimista', trim_scale(v_diarias_eq), 'dp_realista', trim_scale(v_diarias_eq),
      'equipe_dita', jsonb_array_length(v_equipe) > 0,
      'texto', public._agenda_dias(p.dias)
               || case when jsonb_array_length(v_equipe) > 0 then ': ' || public._agenda_lista(array(
                    select case when (x ->> 'eh_dono')::boolean then 'você' else x ->> 'nome' end
                           || case x ->> 'turnos' when 'dia' then ' (dia todo)' when 'manha' then ' (de manhã)'
                                                  else ' (à tarde)' end
                      from jsonb_array_elements(v_equipe) x), null) else '' end
               || case p.estimativa_fonte when 'aceita' then ' (você aceitou a minha estimativa)' else ' (você disse)' end,
      'sugestao', v_sug);
    v_dias_re := p.dias;
  else
    v_dur := jsonb_build_object(
      'fonte', 'sugerida',
      'dias', v_sug -> 'sugerida', 'dias_otimista', v_sug -> 'dias_otimista', 'dias_realista', v_sug -> 'dias_realista',
      'pessoas', v_sug -> 'pessoas', 'equipe', '[]'::jsonb, 'equipe_dita', false,
      'diarias_otimista', v_sug -> 'diarias_otimista', 'diarias_realista', v_sug -> 'diarias_realista',
      -- Diárias-pessoa da faixa (dias × pessoas) para o backlog: 74 = 3 a 6 (spec §6).
      'dp_otimista', v_sug -> 'diarias_otimista', 'dp_realista', v_sug -> 'diarias_realista',
      'sem_base', coalesce((v_sug ->> 'sem_base')::boolean, false),
      'texto', v_sug ->> 'texto', 'sugestao', v_sug);
    v_dias_re := (v_sug ->> 'dias_realista')::numeric;
  end if;

  v_pres := public.os_presenca_do_dono(p_so_id);

  -- ── Prazo e razão crítica ──
  v_prazo := coalesce(p.precisa_ate, public.agenda_somar_du(v_aprov, c.prazo_padrao_du));
  v_prazo_fnt := case when p.precisa_ate is not null then 'dono' else 'padrão' end;
  if v_dias_re is not null and v_dias_re > 0 then
    v_razao := round(greatest(public.agenda_du_entre(p_hoje, v_prazo), 0) / v_dias_re, 2);
  end if;

  -- ── Execução: parada = em andamento sem diária ligada nos últimos parada_du úteis e sem janela futura ──
  if so.status = 'in_progress' then
    select max(ws.data) into v_ult_diaria
      from public.work_shifts ws
     where ws.data <= p_hoje and ws.tipo in ('normal', 'diaria') and coalesce(ws.fracao, 1) > 0
       and (ws.service_order_id = p_so_id
            or exists (select 1 from public.work_shift_os x where x.shift_id = ws.id and x.service_order_id = p_so_id));
    v_parada := (v_ult_diaria is null or v_ult_diaria < public.agenda_somar_du(p_hoje, -c.parada_du))
                and coalesce(v_ag_ate >= p_hoje, false) is false;
  end if;
  -- FASE 2: (1) a evidência de que a OS andou é a maior entre a última diária ligada, o último meio-dia do plano
  -- cumprido ou parcial e o check-in; (2) com dia no plano de hoje em diante a OS em andamento nunca é parada.
  v_plano := public._agenda_plano_da_os(p_so_id, p_hoje);
  v_tem_futuro := coalesce((v_plano ->> 'proximo_dia')::date >= p_hoje, false);
  v_ult_evid := public._agenda_ultima_evidencia(p_so_id, p_hoje);
  if so.status = 'in_progress' then
    v_parada := (v_ult_evid is null or v_ult_evid < public.agenda_somar_du(p_hoje, -c.parada_du))
                and coalesce(v_ag_ate >= p_hoje, false) is false
                and not v_tem_futuro;
  end if;
  -- FASE 2: fim

  -- ── Restrições: {tipo, quem, texto, bloqueia, desde, compre_ate, pergunta} ──
  if so.status = 'draft' and so.quote_status = 'approved' and so.merged_into_id is null then
    v_r := v_r || jsonb_build_object('tipo', 'orcamento', 'quem', 'dono', 'bloqueia', true, 'desde', v_aprov,
      'compre_ate', null, 'pergunta', 'converter em OS ou arquivar?',
      'texto', format('%s em %s e nunca virou OS: converter ou arquivar?',
                      case when so.signed_at is not null then 'assinado' else 'aprovado' end, to_char(v_aprov, 'DD/MM')));
  end if;
  if (so.quote_status = 'awaiting_deposit' and v_pago = 0) or v_pend > 0 then
    v_r := v_r || jsonb_build_object('tipo', 'sinal', 'quem', 'cliente', 'bloqueia', true, 'desde', v_aprov,
      'compre_ate', null, 'pergunta', null,
      'texto', case when v_pend > 0 then 'esperando o sinal de ' || public._brl(v_pend) else 'esperando o sinal' end);
  end if;
  if so.status = 'awaiting_client' then
    v_r := v_r || jsonb_build_object('tipo', 'cliente', 'quem', 'cliente', 'bloqueia', true, 'desde', null,
      'compre_ate', null, 'pergunta', null, 'texto', 'esperando o cliente');
  end if;
  if p.escopo_em_aberto is not null then
    v_r := v_r || jsonb_build_object('tipo', 'escopo', 'quem', 'dono', 'bloqueia', true, 'desde', null,
      'compre_ate', null, 'pergunta', p.escopo_em_aberto, 'texto', p.escopo_em_aberto);
  end if;
  if p.dias is null then
    v_r := v_r || jsonb_build_object('tipo', 'duracao', 'quem', 'dono', 'bloqueia', false, 'desde', null,
      'compre_ate', null, 'pergunta', 'quantos dias e com quem?',
      'texto', case when coalesce((v_sug ->> 'sem_base')::boolean, false)
                    then 'quantos dias e com quem? (o orçamento não dá base para estimar)'
                    else format('quantos dias e com quem? (chute: %s, %s)',
                                public._agenda_faixa_dias((v_sug ->> 'dias_otimista')::numeric, (v_sug ->> 'dias_realista')::numeric),
                                case when (v_sug ->> 'pessoas')::int = 1 then '1 pessoa'
                                     else (v_sug ->> 'pessoas') || ' pessoas' end) end);
  end if;
  -- Com peça embutida em aberto, a pergunta dela já é o "tem peça a comprar?" (mais precisa): não repete.
  if v_n_itens = 0 and not v_conferido and jsonb_array_length(v_embut) = 0 then
    v_r := v_r || jsonb_build_object('tipo', 'material_nao_conferido', 'quem', 'dono', 'bloqueia', true, 'desde', null,
      'compre_ate', null, 'pergunta', 'tem peça a comprar?', 'texto', 'tem peça a comprar? (o orçamento não tem nenhuma)');
  end if;
  v_n := jsonb_array_length(v_embut);
  if v_n > 0 then
    v_txt := array_to_string(array(select format('"%s"', e ->> 'curto')
                                     from jsonb_array_elements(v_embut) with ordinality t(e, o) where o <= 2 order by o), ' ou ')
             || case when v_n > 2 then format(' (e mais %s)', v_n - 2) else '' end;
    v_r := v_r || jsonb_build_object('tipo', 'peca_embutida', 'quem', 'dono', 'bloqueia', true, 'desde', null,
      'compre_ate', null, 'pergunta', format('tem peça embutida em %s?', v_txt),
      'texto', format('tem peça embutida em %s?', v_txt));
  end if;

  -- O que falta comprar: sem fornecedor/classe (E) pergunta "de quem e quando?"; com classe e sem compra combinada,
  -- "compre até" (programação para trás; se já passou, "comprando hoje, chega por volta de …"). A compra que o dono já
  -- combinou (dia que ainda não passou) sem prazo conhecido NÃO volta a perguntar "de quem e quando": vai à parte.
  select count(*) filter (where e ->> 'situacao' = 'falta'
                          and (((e ->> 'sem_data')::boolean and coalesce((e ->> 'compra_prevista_em')::date < p_hoje, true))
                               or e ->> 'compre_ate' is not null)),
         count(*) filter (where e ->> 'situacao' = 'falta' and (e ->> 'sem_data')::boolean
                          and coalesce((e ->> 'compra_prevista_em')::date < p_hoje, true))
    into v_n_falta, v_n_sem
    from jsonb_array_elements(v_crit) e;
  if v_n_falta > 0 then
    select e into v_compra from jsonb_array_elements(v_crit) with ordinality t(e, o)
     where e ->> 'situacao' = 'falta' and e ->> 'compre_ate' is not null
     order by (e ->> 'compre_ate')::date, o limit 1;
    v_cond := case when v_compra is null then ''
                   when (v_compra ->> 'compre_ate')::date < p_hoje then
                     format('comprando hoje, "%s" chega por volta de %s', v_compra ->> 'curto',
                            -- FASE 4: a chegada "comprando hoje" pelo mesmo prazo do fornecedor (o importado em corridos).
                            public._dia_curto(public._agenda_chegada_pela_classe(v_compra ->> 'classe', (v_compra ->> 'prazo_du')::int,
                                                                                 (v_compra ->> 'corridos')::int, p_hoje)))
                            -- FASE 4: fim
                   else format('"%s": compre até %s', v_compra ->> 'curto',
                               public._dia_curto((v_compra ->> 'compre_ate')::date)) end;
    if v_n_sem > 0 then
      v_txt := case when so.status = 'awaiting_parts' then public._agenda_itens(v_n_falta) || ' sem compra registrada'
                    else public._agenda_itens(v_n_falta) || ' a comprar: de quem e quando?' end;
      v_r := v_r || jsonb_build_object('tipo', 'sem_previsao', 'quem', 'dono', 'bloqueia', true, 'desde', null,
        'compre_ate', v_compra ->> 'compre_ate',
        'pergunta', case when so.status = 'awaiting_parts' then 'o que já está na mão e o que falta? Quando chega?'
                         else format('o material (%s) — compra quando e onde?', public._agenda_itens(v_n_falta)) end,
        'texto', v_txt || case when v_cond <> '' then ' (' || v_cond || ')' else '' end);
    else
      v_r := v_r || jsonb_build_object('tipo', 'compre_ate', 'quem', 'dono', 'bloqueia', true, 'desde', null,
        'compre_ate', v_compra ->> 'compre_ate', 'pergunta', 'compra quando?',
        'texto', public._agenda_itens(v_n_falta) || ' a comprar: ' || v_cond);
    end if;
  end if;

  -- Compra combinada ("compro terça na Casa do Eletricista") sem prazo de entrega conhecido: o que o dono já disse fica
  -- dito; a pergunta é só o que falta — quando chega (com fornecedor) ou de quem (sem).
  select count(*) as n, min((e ->> 'compra_prevista_em')::date) as de, max((e ->> 'compra_prevista_em')::date) as ate,
         bool_and(e ->> 'fornecedor' is not null) as com_forn, count(distinct e ->> 'fornecedor') as n_forn,
         min(e ->> 'fornecedor') as forn, min(e ->> 'curto') as curto
    into v_cc
    from jsonb_array_elements(v_crit) e
   where e ->> 'situacao' = 'falta' and (e ->> 'sem_data')::boolean and (e ->> 'compra_prevista_em')::date >= p_hoje;
  if v_cc.n > 0 then
    v_txt := case when v_cc.de = v_cc.ate then public._dia_curto(v_cc.de)
                  else format('de %s a %s', public._dia_curto(v_cc.de), public._dia_curto(v_cc.ate)) end;
    v_r := v_r || jsonb_build_object('tipo', 'compra_sem_prazo', 'quem', 'dono', 'bloqueia', true, 'desde', null,
      'compre_ate', null,
      'pergunta', case when v_cc.com_forn then format('quando chega a compra de %s?', v_txt)
                       else format('de quem é a compra de %s?', v_txt) end,
      'texto', case when v_cc.n = 1 then format('"%s"', v_cc.curto) else public._agenda_itens(v_cc.n::int) end
               || ': você compra ' || v_txt
               || case when v_cc.com_forn and v_cc.n_forn = 1 then ', fornecedor ' || v_cc.forn else '' end
               || case when v_cc.com_forn then '; sem prazo de entrega conhecido: quando chega?'
                       else '; de quem? (sem o fornecedor não sei quando chega)' end);
  end if;

  -- Comprado sem previsão e sem classe: "chegou?"; previsão vencida: "venceu em dd/mm: chegou?".
  for v_x in select e from jsonb_array_elements(v_crit) with ordinality t(e, o)
              where e ->> 'situacao' in ('comprado', 'a_caminho')
                and ((e ->> 'sem_data')::boolean or (e ->> 'atrasado')::boolean)
              order by o
  loop
    if (v_x ->> 'atrasado')::boolean then
      v_r := v_r || jsonb_build_object('tipo', 'atrasado', 'quem', 'dono', 'bloqueia', true, 'desde', v_x ->> 'data',
        'compre_ate', null, 'pergunta', format('"%s" chegou?', v_x ->> 'curto'),
        'texto', format('a previsão de "%s" venceu em %s: chegou?', v_x ->> 'curto', to_char((v_x ->> 'data')::date, 'DD/MM')));
    else
      v_r := v_r || jsonb_build_object('tipo', 'comprado_sem_previsao', 'quem', 'dono', 'bloqueia', true,
        'desde', v_x ->> 'comprado_em', 'compre_ate', null,
        'pergunta', format('"%s" chegou?', v_x ->> 'curto'),
        'texto', format('"%s" (%s) chegou?', v_x ->> 'curto',
                        coalesce('pedido em ' || to_char((v_x ->> 'comprado_em')::date, 'DD/MM'), 'comprado, sem previsão')));
    end if;
  end loop;

  if v_d_bem is null or v_d_bem > p_hoje + 1 then
    v_r := v_r || jsonb_build_object('tipo', 'bem', 'quem', 'cliente', 'bloqueia', false, 'desde', null,
      'compre_ate', null, 'pergunta', null,
      'texto', case when v_d_bem is null then v_bem_nome || ' está fora, sem data para voltar'
                    else v_bem_nome || ' só fica livre ' || public._dia_curto(v_d_bem) end);
  end if;
  if p.nao_antes_de is not null and p.nao_antes_de > p_hoje then
    v_r := v_r || jsonb_build_object('tipo', 'nao_antes', 'quem', 'terceiro', 'bloqueia', false, 'desde', null,
      'compre_ate', null, 'pergunta', null,
      'texto', format('não antes de %s: %s', public._dia_curto(p.nao_antes_de), p.nao_antes_motivo));
  end if;
  if v_parada then
    v_r := v_r || jsonb_build_object('tipo', 'parada', 'quem', 'dono', 'bloqueia', true, 'desde', v_ult_diaria,
      'compre_ate', null, 'pergunta', 'parou?',
      'texto', case when v_ult_diaria is null then 'em andamento e sem diária lançada: parou?'
                    else format('em andamento sem diária desde %s: parou?', to_char(v_ult_diaria, 'DD/MM')) end);
  end if;

  -- Orçamento aprovado que nunca virou OS, ou sinal pendente: quem destrava é a conversão (o dono) ou o sinal (o
  -- cliente), não a compra — comprar peça de um orçamento que pode ser arquivado não é o próximo passo. As perguntas do
  -- material continuam na lista (a visão da OS e a rodada mostram), sem travar até a conversão e o sinal.
  if exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' in ('orcamento', 'sinal')) then
    select coalesce(jsonb_agg(case when e ->> 'tipo' in ('atrasado', 'sem_previsao', 'compra_sem_prazo', 'comprado_sem_previsao',
                                                         'compre_ate', 'peca_embutida', 'material_nao_conferido')
                                   then jsonb_set(e, '{bloqueia}', 'false'::jsonb) else e end order by o), '[]'::jsonb)
      into v_r
      from jsonb_array_elements(v_r) with ordinality t(e, o);
  end if;

  -- A mais forte primeiro: o que trava antes do que só informa, e na ordem do bloco "travado" (spec §5.4).
  select coalesce(jsonb_agg(e order by (e ->> 'bloqueia')::boolean desc,
           array_position(array['parada', 'atrasado', 'sem_previsao', 'compra_sem_prazo', 'comprado_sem_previsao', 'compre_ate',
                                'peca_embutida', 'material_nao_conferido', 'orcamento', 'escopo', 'sinal', 'cliente',
                                'duracao', 'bem', 'nao_antes'], e ->> 'tipo'), o), '[]'::jsonb)
    into v_r
    from jsonb_array_elements(v_r) with ordinality t(e, o);

  -- ── Estado (o 1º que valer) ──
  v_estado := case
    when p.congelada_ate is not null and p.congelada_ate >= p_hoje then 'congelada'
    when so.status in ('completed', 'invoiced') then 'concluida'
    when so.status = 'cancelled' or so.merged_into_id is not null
         or (so.status = 'draft' and coalesce(so.quote_status, 'draft') not in ('approved', 'awaiting_deposit')) then 'fora_da_carteira'
    when so.status = 'in_progress' then case when v_parada then 'parada' else 'em_execucao' end
    when coalesce(v_ag_ate, v_ag_de) >= p_hoje then 'marcada'
    when exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' = 'sinal') then 'sem_sinal'
    when so.status = 'awaiting_client' or v_bem_tudo or p.nao_antes_de > v_horizonte then 'aguardando_cliente'
    when exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' in ('orcamento', 'escopo')) then 'esperando_voce'
    when v_mat_estado in ('nao_conferido', 'sem_previsao', 'atrasado') then 'aguardando_material'
    else 'pronta' end;
  -- FASE 2: (3) os estados do plano: fixada e programada vêm depois de em execução/parada e antes de marcada; com a
  -- agenda automática ligada a janela antiga é o espelho do plano, e "marcada" não vale (o estado vem das alocações).
  if v_estado not in ('congelada', 'concluida', 'fora_da_carteira', 'em_execucao', 'parada') then
    if coalesce((v_plano ->> 'fixada')::boolean, false) then
      v_estado := 'fixada';
    elsif v_tem_futuro then
      v_estado := 'programada';
    elsif v_estado = 'marcada' and c.modo_proposta = 'ligado' then
      v_estado := case
        when exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' = 'sinal') then 'sem_sinal'
        when so.status = 'awaiting_client' or v_bem_tudo or p.nao_antes_de > v_horizonte then 'aguardando_cliente'
        when exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' in ('orcamento', 'escopo')) then 'esperando_voce'
        when v_mat_estado in ('nao_conferido', 'sem_previsao', 'atrasado') then 'aguardando_material'
        else 'pronta' end;
    end if;
  end if;
  -- FASE 2: fim

  if v_estado in ('concluida', 'fora_da_carteira') and (so.status in ('completed', 'invoiced', 'cancelled')
                                                         or so.merged_into_id is not null) then
    v_r := '[]'::jsonb;
  end if;

  -- A restrição do dono que mais pesa (a 1ª da lista que trava e é dele).
  select e into v_principal from jsonb_array_elements(v_r) with ordinality t(e, o)
   where (e ->> 'bloqueia')::boolean and e ->> 'quem' = 'dono' order by o limit 1;

  v_quase := v_estado = 'aguardando_material'
         and (select count(*) from jsonb_array_elements(v_r) e where (e ->> 'bloqueia')::boolean) = 1
         and v_principal ->> 'tipo' = 'material_nao_conferido';

  -- O texto do estado, para vir depois do nome do cliente ("Lenine: falta você dizer se tem peça a comprar").
  v_estado_txt := case v_estado
    -- "(rever …)" só quando o dia de rever não é o mesmo do fim da espera (é o padrão do rascunho).
    when 'congelada' then 'em espera até ' || public._dia_curto(p.congelada_ate)
                          || case when p.revisar_em is distinct from p.congelada_ate
                                  then coalesce(' (rever ' || public._dia_curto(p.revisar_em) || ')', '') else '' end
    when 'concluida' then case so.status when 'invoiced' then 'faturado' else 'concluído' end
    when 'fora_da_carteira' then public._agenda_rotulo_os(so.status, so.quote_status, so.signed_at is not null, so.juntado_em, false)
    when 'em_execucao' then 'em andamento'
    when 'parada' then case when v_ult_diaria is null then 'em andamento e sem diária lançada'
                            else 'em andamento sem diária desde ' || to_char(v_ult_diaria, 'DD/MM') end
    when 'marcada' then case when v_ag_de is null or v_ag_de = v_ag_ate then 'marcado para ' || public._dia_curto(coalesce(v_ag_ate, v_ag_de))
                             else format('marcado de %s a %s', public._dia_curto(v_ag_de), public._dia_curto(v_ag_ate)) end
    when 'sem_sinal' then (select e ->> 'texto' from jsonb_array_elements(v_r) e where e ->> 'tipo' = 'sinal' limit 1)
    when 'aguardando_cliente' then case
      when so.status = 'awaiting_client' then 'esperando o cliente'
      when v_bem_tudo then case when v_d_bem is null then v_bem_nome || ' está fora, sem data para voltar'
                                else v_bem_nome || ' só fica livre ' || public._dia_curto(v_d_bem) end
      else format('não antes de %s: %s', public._dia_curto(p.nao_antes_de), p.nao_antes_motivo) end
    -- O orçamento parado vem antes do escopo em aberto (a ordem do bloco "travado").
    when 'esperando_voce' then case
      when so.status = 'draft' and so.quote_status = 'approved'
        then format('%s em %s e nunca virou OS', case when so.signed_at is not null then 'assinado' else 'aprovado' end,
                    to_char(v_aprov, 'DD/MM'))
      else 'falta você decidir: ' || p.escopo_em_aberto end
    when 'aguardando_material' then case v_principal ->> 'tipo'
      when 'atrasado' then 'falta você dizer se ' || replace(v_principal ->> 'pergunta', ' chegou?', '') || ' chegou (a previsão venceu)'
      when 'sem_previsao' then case when so.status = 'awaiting_parts'
                                    then format('falta você dizer o que já está na mão e o que falta (%s sem compra registrada)',
                                                public._agenda_itens(v_n_falta))
                                    else 'falta você dizer de quem e quando comprar ' || public._agenda_itens(v_n_falta) end
      when 'comprado_sem_previsao' then 'falta você dizer se ' || replace(v_principal ->> 'texto', ' chegou?', '') || ' chegou'
      when 'compra_sem_prazo' then 'falta você dizer ' || rtrim(v_principal ->> 'pergunta', '?')
      when 'peca_embutida' then 'falta você dizer se tem peça embutida em '
                                || array_to_string(array(select format('"%s"', e ->> 'curto')
                                     from jsonb_array_elements(v_embut) with ordinality t(e, o) where o <= 2 order by o), ' e ')
                                || case when jsonb_array_length(v_embut) > 2
                                        then format(' (e mais %s)', jsonb_array_length(v_embut) - 2) else '' end
      else 'falta você dizer se tem peça a comprar' end
    else -- pronta
      case when v_est is not null and v_est > public.agenda_somar_du(p_hoje, 1) then
             'pronto a partir de ' || public._dia_curto(v_est)
             || case when v_inicio_mat is not null and v_inicio_mat >= v_est_sm then
                  (select case
                        when e ->> 'nivel' in ('B', 'C') then format(', se "%s" chegar %s', e ->> 'curto', public._dia_curto(v_dpm))
                        when e ->> 'situacao' = 'falta' and e ->> 'compra_prevista_em' is not null
                             and (e ->> 'compra_prevista_em')::date >= p_hoje
                          then ', se a compra sair ' || public._dia_curto((e ->> 'compra_prevista_em')::date)
                        when e ->> 'situacao' = 'falta' then ', se comprar hoje'
                        else format(', se "%s" chegar por volta de %s', e ->> 'curto', public._dia_curto(v_dpm)) end
                        from jsonb_array_elements(v_crit) with ordinality t(e, o)
                       where e ->> 'nivel' <> 'A' and (e ->> 'data')::date = v_dpm order by o limit 1)
                else '' end
           else 'pronto para começar' end
  end;
  -- FASE 2: o texto dos estados do plano ("marcado de ter 03/11 a qui 05/11", "(fixado)" quando é fixo).
  if v_estado in ('fixada', 'programada') then
    v_estado_txt := case when (v_plano ->> 'proximo_dia') = (v_plano ->> 'ultimo_dia')
                         then 'marcado para ' || public._dia_curto((v_plano ->> 'proximo_dia')::date)
                         else format('marcado de %s a %s', public._dia_curto((v_plano ->> 'proximo_dia')::date),
                                     public._dia_curto((v_plano ->> 'ultimo_dia')::date)) end
                    || case when v_estado = 'fixada' then ' (fixado)' else '' end;
  end if;
  -- FASE 2: fim

  -- FASE 2: (4) a saída ganha o plano (null sem alocação) e a última evidência; ultima_diaria continua.
  return jsonb_build_object('plano', v_plano, 'ultima_evidencia', v_ult_evid) || jsonb_build_object(
  -- FASE 2: fim
    'ok', true, 'os', so.id, 'numero', so.service_order_number, 'cliente', so.cliente_nome,
    'cliente_curto', public._agenda_nome_curto(so.cliente_nome), 'unidade', so.bem,
    'eh_orcamento', so.status = 'draft', 'status', so.status, 'quote_status', so.quote_status,
    'na_carteira', v_na_cart, 'aprovada_em', v_aprov,
    'estado', v_estado, 'estado_texto', v_estado_txt, 'quase_pronta', v_quase,
    'restricoes', v_r,
    'material', jsonb_build_object(
      'estado', v_mat_estado, 'itens', v_itens, 'dpm', v_dpm,
      'gargalo', (select e ->> 'descricao' from jsonb_array_elements(v_crit) with ordinality t(e, o)
                   where e ->> 'nivel' <> 'A' and v_dpm is not null and (e ->> 'data')::date = v_dpm order by o limit 1),
      'confianca', v_confianca, 'inicio_mat', v_inicio_mat, 'embutidas', v_embut,
      'conferido_em', p.material_conferido_em),
    'duracao', v_dur,
    'presenca_dono', v_pres,
    'est', v_est, 'est_texto', public._dia_curto(v_est), 'est_sem_material', v_est_sm,
    'prazo_efetivo', v_prazo, 'prazo_texto', public._dia_curto(v_prazo), 'prazo_fonte', v_prazo_fnt,
    'razao_critica', v_razao,
    'marcada', case when v_ag_de is not null or v_ag_ate is not null
                    then jsonb_build_object('de', v_ag_de, 'ate', v_ag_ate) end,
    'ultima_diaria', v_ult_diaria);
end;
$function$;

comment on function public.os_prontidao(uuid, date) is
  'Agenda de Produção (Fase 1, P3; Fase 2, P2; Fase 4, P1: o prazo de cada item é o do fornecedor — _agenda_prazo_do_fornecedor, com o que o dono disse, o cadastro repetido, o nome e a cidade tolerante ao caractere quebrado; o importado conta em dias corridos; o item ganha prazo_texto, duvida e corridos; o texto livre é coberto pela linha da OC ligada a ele): a prontidão de uma OS em p_hoje. Estado (o 1º que valer): congelada → concluida → fora_da_carteira → em_execucao/parada → fixada/programada (Fase 2: tem meio-dia vigente de hoje em diante, fixado ou publicado) → marcada (a janela antiga; só fora de modo_proposta ligado) → sem_sinal → aguardando_cliente → esperando_voce → aguardando_material → pronta. Parada (Fase 2) = em andamento, sem evidência (diária ligada, meio-dia cumprido/parcial ou check-in) há parada_du dias úteis e sem dia no plano. Restrições {tipo, quem (dono|cliente|terceiro), texto, bloqueia, desde, compre_ate, pergunta}, a mais forte primeiro. Material efetivo = conta bruta + fato informado em os_material, níveis A (na mão, quantidade completa) / B (previsão do fornecedor, nota, OC, Pix) / C (previsão do dono) / D (sem previsão: comprado em + prazo da classe, ou "se comprar hoje") / E (sem fornecedor nem classe); "material não conferido" com zero itens ou peça embutida em aberto; dpm, início pelo material (chegada + folga_material_du, sem folga remota), est, compre até para trás, prazo efetivo (precisa_ate ou aprovação + prazo_padrao_du) e razão crítica. Saída também com plano (_agenda_plano_da_os; null sem alocação), ultima_evidencia e ultima_diaria. Também aceita OS fora da carteira.';

-- ── 4. A frase do rascunho: o tipo fornecedor ───────────────────────────────────────────────────────────
-- Corpo de 20261025100400 copiado; a mudança está marcada "-- FASE 4:".

create or replace function public._agenda_rascunho_frase(p_tipo text, p_d jsonb)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_partes text[] := '{}';
  v_t      text;
  v_forn   text := nullif(p_d ->> 'fornecedor_txt', '');
  v_hoje   date := (p_d ->> 'hoje')::date;
  v_quando text;
begin
  if p_tipo = 'planejar' then
    if nullif(p_d ->> 'escopo_decidido', '') is not null then
      v_partes := v_partes || (p_d ->> 'escopo_decidido');
    end if;
    v_t := null;
    if p_d ->> 'dias' is not null then
      v_t := public._agenda_dias((p_d ->> 'dias')::numeric)
             || case when p_d ->> 'estimativa_fonte' = 'aceita' then ' (a minha estimativa, que você aceitou)' else '' end;
    end if;
    if jsonb_array_length(coalesce(p_d -> 'equipe', '[]'::jsonb)) > 0 then
      v_t := concat_ws(' ', v_t, 'com ' || public._agenda_lista(array(
               select case when (e ->> 'eh_dono')::boolean then 'você' else e ->> 'nome' end
                      || case e ->> 'turnos' when 'manha' then ' (de manhã)' when 'tarde' then ' (à tarde)' else '' end
                 from jsonb_array_elements(p_d -> 'equipe') with ordinality t(e, o) order by o), null));
    elsif p_d ? 'equipe' and p_d ->> 'dias' is null then
      v_t := 'sem ninguém marcado para ir';
    end if;
    if v_t is not null then
      v_partes := v_partes || v_t;
    end if;
    if p_d ->> 'dono' is not null then
      v_partes := v_partes || case p_d ->> 'dono' when 'abre_e_fecha' then 'você abre e fecha'
                                                 when 'sempre' then 'você fica o tempo todo' else 'você não vai' end;
    end if;
    if p_d ->> 'precisa_ate' is not null then
      v_partes := v_partes || ('o cliente precisa até ' || public._dia_curto((p_d ->> 'precisa_ate')::date));
    elsif p_d ? 'precisa_ate' then
      v_partes := v_partes || 'o cliente não tem mais prazo'::text;
    end if;
    if p_d ? 'bem' then
      v_partes := v_partes || case p_d #>> '{bem,modo}'
        when 'livre' then coalesce(p_d ->> 'bem_nome', 'o barco') || ' já está livre'
        when 'fora' then coalesce(p_d ->> 'bem_nome', 'o barco') || ' fica fora '
                         || public._agenda_quando_texto((p_d #>> '{bem,de}')::date, (p_d #>> '{bem,ate}')::date)
        else coalesce(p_d ->> 'bem_nome', 'o barco') || ' fica livre ' || public._dia_curto((p_d #>> '{bem,livre_em}')::date) end;
    end if;
    if p_d ->> 'nao_antes_de' is not null then
      v_partes := v_partes || ('não antes de ' || public._dia_curto((p_d ->> 'nao_antes_de')::date)
                               || case when coalesce(p_d ->> 'nao_antes_motivo', 'você disse') = 'você disse' then ''
                                       else ' (' || (p_d ->> 'nao_antes_motivo') || ')' end);
    elsif p_d ? 'nao_antes_de' then
      v_partes := v_partes || 'pode começar sem esperar data'::text;
    end if;
    if nullif(p_d ->> 'escopo_em_aberto', '') is not null then
      v_partes := v_partes || ('falta decidir: ' || (p_d ->> 'escopo_em_aberto'));
    elsif p_d ? 'escopo_em_aberto' and nullif(p_d ->> 'escopo_decidido', '') is null then
      v_partes := v_partes || 'nada mais a decidir no escopo'::text;
    end if;
    if p_d ->> 'congelada_ate' is not null then
      v_partes := v_partes || ('em espera até ' || public._dia_curto((p_d ->> 'congelada_ate')::date)
                               || case when p_d ->> 'revisar_em' is distinct from p_d ->> 'congelada_ate'
                                       then ' (rever ' || public._dia_curto((p_d ->> 'revisar_em')::date) || ')' else '' end);
    elsif p_d ? 'congelada_ate' then
      v_partes := v_partes || 'sai da espera'::text;
    end if;
    if p_d ->> 'prioridade' is not null then
      v_partes := v_partes || case when (p_d ->> 'prioridade')::int = 1 then 'passa na frente (prioridade 1)'
                                   else 'prioridade ' || (p_d ->> 'prioridade') end;
    end if;
    if p_d ->> 'sem_material' is not null then
      v_partes := v_partes || case when (p_d ->> 'sem_material')::boolean then 'não tem peça a comprar'
                                   else 'tem peça a conferir' end;
    end if;
    -- FASE 2: quanto dá para adiantar no pátio sem o bem (bancada: barramento, chicote).
    if p_d ? 'adiantavel_patio' then
      v_partes := v_partes || case when p_d ->> 'adiantavel_patio' is null then 'nada a adiantar no pátio'
                                   else 'dá para adiantar ' || public._agenda_dias((p_d ->> 'adiantavel_patio')::numeric) || ' no pátio' end;
    end if;
    return array_to_string(v_partes, '; ');
  end if;

  if p_tipo = 'material' then
    v_t := case p_d ->> 'acao'
      when 'na_mao' then
        case when p_d ->> 'quantidade_na_mao' is not null
             then format('%s de %s na mão', public._os_material_qtd((p_d ->> 'quantidade_na_mao')::numeric),
                         public._os_material_qtd((p_d ->> 'quantidade_necessaria')::numeric))
             when (p_d ->> 'chegou_em')::date = v_hoje then 'na mão (desde hoje)'
             else 'na mão desde ' || public._dia_curto((p_d ->> 'chegou_em')::date) end
      when 'comprado' then
        'comprado' || case when (p_d ->> 'comprado_em')::date = v_hoje then ' hoje'
                           else ' em ' || public._dia_curto((p_d ->> 'comprado_em')::date) end
        || case when p_d ->> 'previsao_ate' is not null
                then ', chega ' || public._dia_curto((p_d ->> 'previsao_ate')::date) || ' (você disse)' else '' end
      when 'a_caminho' then
        case when p_d ->> 'previsao_ate' is null then 'a caminho, sem previsão'
             when p_d ->> 'previsao_de' is not null then
               format('chega entre %s e %s (você disse)', public._dia_curto((p_d ->> 'previsao_de')::date),
                      public._dia_curto((p_d ->> 'previsao_ate')::date))
             else 'chega ' || public._dia_curto((p_d ->> 'previsao_ate')::date) || ' (você disse)' end
      when 'falta' then
        case when coalesce((p_d ->> 'vou_comprar')::boolean, false) then
               case when p_d ->> 'compra_prevista_em' is null then 'você vai comprar'
                    else 'você compra ' || public._dia_curto((p_d ->> 'compra_prevista_em')::date) end
             else 'falta comprar' end
      when 'sem_previsao' then 'comprado, sem previsão de chegada'
      when 'dispensado' then 'não precisa mais (sai da lista)'
      else null end;
    if v_t is not null and v_forn is not null and p_d ->> 'acao' <> 'dispensado' then
      v_t := v_t || ', fornecedor ' || v_forn;
    end if;
    if p_d ->> 'critico' is not null and not (p_d ->> 'critico')::boolean then
      v_t := coalesce(v_t || ' (dá para começar sem)', 'dá para começar sem');
    end if;
    return v_t;
  end if;

  if p_tipo = 'disponibilidade' then
    v_quando := case when (p_d ->> 'padrao')::boolean
                     then public._agenda_dias_semana_texto(array(select jsonb_array_elements_text(p_d -> 'dias_semana')::smallint))
                     else public._agenda_quando_texto((p_d ->> 'de')::date, (p_d ->> 'ate')::date) end;
    return case p_d ->> 'dito'
      when 'vem' then case when (p_d ->> 'eh_dono')::boolean then 'em campo ' else 'vem ' end || v_quando
      when 'nao_vem' then case when (p_d ->> 'eh_dono')::boolean then 'fora de campo ' else 'não vem ' end || v_quando
      when 'so_manha' then v_quando || ' à tarde, não'
      else v_quando || ' de manhã, não' end
      || case when coalesce((p_d ->> 'sabado_por_data')::boolean, false) then ' (sábado eu só conto por data)' else '' end;
  end if;

  -- FASE 2: os pedidos da conversa (marcar, aplicar/decidir, desfazer, andamento) chegam com a frase pronta do banco.
  if p_tipo in ('marcar', 'aplicar', 'desfazer', 'andamento') then
    return p_d ->> 'frase_pronta';
  end if;

  -- FASE 4: o prazo do fornecedor chega com a frase pronta do banco (agenda_rascunho_fornecedor).
  if p_tipo = 'fornecedor' then
    return p_d ->> 'frase_pronta';
  end if;
  -- FASE 4: fim
  raise exception '_agenda_rascunho_frase: tipo "%" não existe', p_tipo using errcode = '22023';
end;
$function$;

comment on function public._agenda_rascunho_frase(text, jsonb) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): a frase de uma linha do rascunho, montada dos dados já resolvidos — planejar ("2 dias com Roberto e João (à tarde); você abre e fecha; dá para adiantar 1 dia no pátio"), material ("chega ter 03/11 (você disse)", "você compra ter 27/10, fornecedor Premel") e disponibilidade ("em campo de seg a sex", "toda sexta à tarde, não"); os pedidos da Fase 2 (marcar, aplicar, desfazer, andamento) e o prazo do fornecedor (Fase 4) trazem a frase pronta (dados.frase_pronta).';

-- ── 5. O que o dono diz do fornecedor vira RASCUNHO ─────────────────────────────────────────────────────

-- O fornecedor dito, com o lugar quando ele vem junto: "Kamell (Vila Velha/ES)" (a opção da pergunta de ambiguidade),
-- "a Kamell de Vila Velha", "a Kamell de SC". _agenda_resolver_fornecedor (Fase 1) só casa o nome — o lugar dito vira
-- palavra que não está no nome e o fornecedor sai "novo", e o nome sozinho continua ambíguo. Aqui: o nome primeiro, como
-- sempre; se não resolveu e há lugar, os cadastros ativos que casam o nome (a mesma regra do resolvedor) E têm a cidade ou a
-- UF dita (tolerante ao caractere quebrado). Um só = ele; vários = a pergunta do nome; nenhum = não achei.
create or replace function public._agenda_fornecedor_dito(p_ref text)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_ref   text := btrim(coalesce(p_ref, ''));
  v_r     jsonb := public._agenda_resolver_fornecedor(p_ref);
  v_lugar text;
  v_nome  text;
  v_tok   text[];
  v_ids   uuid[];
  s       public.suppliers%rowtype;
begin
  if v_r ->> 'status' = 'ok' then
    return v_r;
  end if;
  -- O lugar: o que está entre parênteses, senão o que vem depois do ÚLTIMO "de/do/da/em" ("Casa do Eletricista de Itajaí").
  v_lugar := coalesce((regexp_match(v_ref, '\(([^)]*)\)'))[1], (regexp_match(v_ref, '^.*\s(?:de|do|da|em)\s+(.+)$', 'i'))[1]);
  v_nome := btrim(case when v_ref ~ '\(' then regexp_replace(v_ref, '\([^)]*\)', ' ', 'g')
                       else regexp_replace(v_ref, '^(.*)\s(?:de|do|da|em)\s+.+$', '\1', 'i') end);
  if nullif(btrim(coalesce(v_lugar, '')), '') is null or v_nome = '' then
    return v_r;
  end if;
  v_tok := array(select t from unnest(string_to_array(public._nome_comparavel(v_nome), ' ')) with ordinality u(t, o)
                  where length(t) >= 2 order by o);
  if cardinality(v_tok) = 0 then
    return v_r;
  end if;
  v_ids := array(
    select f.id
      from public.suppliers f
     where coalesce(f.active, true)
       and not exists (select 1 from unnest(v_tok) t
                        where not exists (select 1 from unnest(string_to_array(
                                            public._nome_comparavel(concat_ws(' ', f.name, f.trade_name, f.display_name)), ' ')) w
                                           where w like t || '%'))
       and exists (select 1 from unnest(regexp_split_to_array(v_lugar, '\s*[/,]\s*')) p
                    where nullif(btrim(p), '') is not null
                      and (public._agenda_lugar_casa(f.city, p) or public._agenda_lugar_casa(f.state, p)))
     order by f.name collate "C", f.id);
  if cardinality(v_ids) = 1 then
    select * into s from public.suppliers where id = v_ids[1];
    return jsonb_build_object('status', 'ok', 'id', s.id,
      'nome', public._agenda_nome_curto(coalesce(nullif(btrim(s.display_name), ''), nullif(btrim(s.trade_name), ''), s.name)),
      'texto', public._agenda_nome_curto(coalesce(nullif(btrim(s.display_name), ''), nullif(btrim(s.trade_name), ''), s.name)));
  end if;
  v_r := public._agenda_resolver_fornecedor(v_nome);
  if v_r ->> 'status' = 'ambiguo' then
    return v_r;
  end if;
  return jsonb_build_object('status', 'novo', 'nome', left(v_ref, 80), 'texto', left(v_ref, 80));
end;
$function$;

comment on function public._agenda_fornecedor_dito(text) is
  'Agenda de Produção (Fase 4, P1): o fornecedor que o dono disse, com o lugar quando vem junto ("Kamell (Vila Velha/ES)", "a Kamell de Vila Velha", "a Kamell de SC") — o nome por _agenda_resolver_fornecedor; se não resolveu e há lugar, os ativos que casam o nome e têm a cidade ou a UF dita. Um = {status ok, id, nome}; vários = a pergunta do nome; nenhum = {status novo}.';

-- "A Premel eu pego no balcão", "a Kamell chega em 4 dias úteis depois que sai", "a Toli chega em 5 dias", "a Kamell de
-- SC é a mesma do ES": nada muda no cadastro; a releitura sai pronta e só o *grava* do dono grava
-- (_agenda_aplicar_fornecedor). O fornecedor tem de estar cadastrado (o novo é recusado: o cadastro é pela tela).
create or replace function public.agenda_rascunho_fornecedor(p_autor uuid, p_canal text, p_fornecedor text,
                                                             p_modalidade text default null, p_prazo numeric default null,
                                                             p_unidade text default null, p_mesmo_que text default null,
                                                             p_trecho text default null,
                                                             p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor  uuid := public._autor_da_agenda(p_autor);
  c        public.agenda_config := public._agenda_cfg();
  v_r      jsonb;
  v_id     uuid;
  s        public.suppliers%rowtype;
  v_nome   text;
  v_lugar  text;
  v_rot    text;
  v_y      uuid;
  y        public.suppliers%rowtype;
  v_ynome  text;
  v_yd     jsonb;
  v_aberto jsonb;
  v_mod    text := nullif(lower(btrim(coalesce(p_modalidade, ''))), '');
  v_uni    text := nullif(lower(btrim(coalesce(p_unidade, ''))), '');
  v_n      int;
  v_du     int;
  v_corr   int;
  v_du_ef  int;
  v_co_ef  int;
  v_conv   boolean := false;
  v_dito   boolean := false;
  v_frase  text;
  v_grav   text;
  v_item   text;
  c_modais constant text[] := array['balcao', 'entrega_local', 'distribuidor_sc_pr', 'outro_estado', 'marketplace', 'importacao'];
  c_viajam constant text[] := array['distribuidor_sc_pr', 'outro_estado', 'marketplace', 'importacao'];
begin
  if p_canal is null or p_canal not in ('whatsapp', 'painel') then
    raise exception 'agenda_rascunho_fornecedor: canal "%" inválido (whatsapp ou painel)', p_canal using errcode = '22023';
  end if;
  if v_mod is not null and not (v_mod = any (c_modais)) then
    raise exception 'agenda_rascunho_fornecedor: modalidade "%" não existe (balcao, entrega_local, distribuidor_sc_pr, outro_estado, marketplace ou importacao)',
      p_modalidade using errcode = '22023';
  end if;
  if v_uni is not null and v_uni not in ('uteis', 'corridos') then
    raise exception 'agenda_rascunho_fornecedor: unidade "%" não existe (uteis ou corridos)', p_unidade using errcode = '22023';
  end if;
  if c.modo_leitura = 'desligado' then
    return public._agenda_recusa('A agenda de produção está desligada agora: não anotei nada.', 'desligada');
  end if;
  if nullif(btrim(p_trecho), '') is null then
    return public._agenda_recusa('Me diga com as suas palavras como você compra desse fornecedor.', 'sem_trecho');
  end if;
  if nullif(btrim(p_fornecedor), '') is null then
    return public._agenda_recusa('De qual fornecedor?', 'sem_fornecedor');
  end if;

  -- O fornecedor dito (com o lugar, se veio): um cadastro ativo; ambíguo = a pergunta com a cidade de cada um; novo = recusa.
  v_r := public._agenda_fornecedor_dito(p_fornecedor);
  if v_r ->> 'status' = 'ambiguo' then
    return public._agenda_recusa(v_r ->> 'texto', 'fornecedor_ambiguo', v_r -> 'opcoes');
  end if;
  if v_r ->> 'status' <> 'ok' then
    return public._agenda_recusa(format('Não achei a %s nos fornecedores. Cadastre na tela de fornecedores e me diga de novo.',
                                        btrim(p_fornecedor)), 'fornecedor_novo');
  end if;
  v_id := (v_r ->> 'id')::uuid;
  select * into s from public.suppliers where id = v_id;
  v_nome := v_r ->> 'nome';
  v_lugar := public._agenda_lugar_texto(s.city, s.state);
  v_rot := v_nome || coalesce(' (' || v_lugar || ')', '');

  if nullif(btrim(p_mesmo_que), '') is not null then
    -- "É a mesma de …": copia como o outro cadastro entrega (o que o dono disse dele agora, no mesmo lote, ou o que já
    -- está gravado).
    if v_mod is not null or p_prazo is not null then
      return public._agenda_recusa(
        format('Diga só que a %s é a mesma de %s (eu copio como ela entrega) ou como a %s entrega: uma coisa de cada vez.',
               v_nome, btrim(p_mesmo_que), v_nome), 'mesmo_que_e_prazo');
    end if;
    v_r := public._agenda_fornecedor_dito(p_mesmo_que);
    if v_r ->> 'status' = 'ambiguo' then
      return public._agenda_recusa(v_r ->> 'texto', 'fornecedor_ambiguo', v_r -> 'opcoes');
    end if;
    if v_r ->> 'status' <> 'ok' then
      return public._agenda_recusa(format('Não achei a %s nos fornecedores. Cadastre na tela de fornecedores e me diga de novo.',
                                          btrim(p_mesmo_que)), 'fornecedor_novo');
    end if;
    v_y := (v_r ->> 'id')::uuid;
    if v_y = v_id then
      return public._agenda_recusa(format('É o mesmo cadastro da %s: me diga qual é o outro.', v_nome), 'mesmo_cadastro');
    end if;
    select * into y from public.suppliers where id = v_y;
    v_ynome := v_r ->> 'nome';
    select r.dados into v_yd
      from public.agenda_rascunho r
     where r.autor = v_autor and r.chave = 'fornecedor:' || v_y and r.estado = 'aberto' and r.expira_em > now()
     limit 1;
    if (v_yd ->> 'modalidade') is null and y.modalidade is not null then
      v_yd := jsonb_build_object('modalidade', y.modalidade, 'prazo_dias_uteis', y.prazo_dias_uteis,
                                 'prazo_dias_corridos', y.prazo_dias_corridos);
    end if;
    if (v_yd ->> 'modalidade') is null then
      return public._agenda_recusa(format('Me diga também como a %s entrega.', v_ynome), 'mesmo_que_sem_prazo');
    end if;
    v_mod := v_yd ->> 'modalidade';
    v_du := (v_yd ->> 'prazo_dias_uteis')::int;
    v_corr := (v_yd ->> 'prazo_dias_corridos')::int;
  else
    select r.dados into v_aberto
      from public.agenda_rascunho r
     where r.autor = v_autor and r.chave = 'fornecedor:' || v_id and r.estado = 'aberto' and r.expira_em > now()
       and (r.dados ->> 'mesmo_que_id') is null
     limit 1;
    if v_mod is null and p_prazo is null then
      return public._agenda_recusa(format('Me diga como você compra da %s e em quantos dias chega.', v_nome), 'nada_dito');
    end if;
    -- A modalidade: a dita; senão a da correção aberta; senão a que vale hoje (a que o dono já disse, ou o chute).
    v_mod := coalesce(v_mod, v_aberto ->> 'modalidade', public._agenda_prazo_do_fornecedor(v_id) ->> 'classe');
    if v_mod is null then
      return public._agenda_recusa(
        format('Como você compra da %s: no balcão, entrega local, por transportadora, de outro estado, pela internet ou importado?',
               v_nome), 'sem_modalidade');
    end if;
    if v_mod = 'importacao' and v_uni = 'uteis' then
      return public._agenda_recusa('Importado eu conto em dias corridos: em quantos dias chega?', 'importado_em_uteis');
    end if;
    if p_prazo is not null then
      if p_prazo < 0 or p_prazo <> trunc(p_prazo) then
        return public._agenda_recusa('Me diga o prazo em dias inteiros.', 'prazo_invalido');
      end if;
      v_n := p_prazo::int;
      if v_n = 0 and v_mod <> 'balcao' then
        return public._agenda_recusa(format('Em quantos dias chega da %s?', v_nome), 'prazo_zero');
      end if;
      if v_n > 0 then
        -- Guarda do número não dito: o prazo tem de estar nas palavras do dono ("na hora", "no balcão" = sem número).
        if not public._agenda_trecho_tem_numero(p_trecho, p_prazo) then
          return public._agenda_recusa(format('Não achei "%s" no que você disse; me diga de novo.', v_n), 'fora_do_trecho');
        end if;
        v_dito := true;
        if v_mod = 'importacao' then
          if v_n > 120 then
            return public._agenda_recusa('Importado eu conto até 120 dias corridos: confere o prazo?', 'prazo_longo');
          end if;
          v_corr := v_n;
        else
          if v_uni = 'corridos' then
            -- "Chega em 5 dias" (corridos) de quem não é importado: o banco conta os dias úteis desse intervalo.
            v_du := public.agenda_du_entre(p_hoje, p_hoje + v_n);
            v_conv := true;
          else
            v_du := v_n;
          end if;
          if v_du > 60 then
            return public._agenda_recusa('Eu conto até 60 dias úteis: confere o prazo?', 'prazo_longo');
          end if;
        end if;
      end if;
    elsif v_aberto is not null and (v_aberto ->> 'modalidade') is not distinct from v_mod then
      -- A correção que só troca outra coisa herda o prazo dito antes.
      v_du := (v_aberto ->> 'prazo_dias_uteis')::int;
      v_corr := (v_aberto ->> 'prazo_dias_corridos')::int;
      v_n := (v_aberto ->> 'dito')::int;
      v_conv := coalesce((v_aberto ->> 'convertido')::boolean, false);
      v_dito := v_du is not null or v_corr is not null;
    end if;
  end if;

  -- Os dias que vão valer (os ditos, senão os da classe) e as frases da releitura e do *grava*.
  v_du_ef := case when v_mod <> 'importacao' then coalesce(v_du, (c.prazo_classe_du ->> v_mod)::int) end;
  v_co_ef := case when v_mod = 'importacao' then coalesce(v_corr, c.importacao_dias) end;
  if v_y is not null then
    v_frase := format('é a mesma %s%s — conto %s para as duas. Para tirar o cadastro repetido, desative a%s na tela de fornecedores',
                      v_ynome, coalesce(' de ' || public._agenda_lugar_texto(y.city, null), ''),
                      case when v_mod = 'importacao' then public._agenda_plural(v_co_ef, 'dia corrido', 'dias corridos')
                           when v_du_ef = 0 then 'o mesmo dia'
                           else public._agenda_plural(v_du_ef, 'dia útil', 'dias úteis') end,
                      coalesce(' de ' || public._agenda_lugar_texto(s.city, null), ' que sobra'));
    v_grav := format('%s: a mesma%s, %s (você disse).', v_nome,
                     coalesce(' de ' || public._agenda_lugar_texto(y.city, null), ''),
                     public._agenda_classe_texto(v_mod, v_du_ef, v_co_ef));
  else
    v_frase := case when v_conv
                    then format('%s dias (conto %s)', v_n, public._agenda_plural(v_du, 'dia útil', 'dias úteis'))
                    else public._agenda_classe_texto(v_mod, v_du_ef, v_co_ef)
                         || case when v_dito and v_mod = any (c_viajam) then ' depois do despacho' else '' end end
               || ' (você disse)';
    v_grav := v_nome || ': ' || v_frase || '.';
    if v_lugar is null then
      v_frase := v_frase || '. A cidade continua em branco no cadastro';
    end if;
  end if;

  v_item := public._agenda_rascunho_salvar(v_autor, p_canal, 'fornecedor', 'fornecedor:' || v_id, null,
    jsonb_build_object('grupo', 'fornecedor:' || v_id, 'rotulo_grupo', v_rot, 'fornecedor_id', v_id, 'nome', v_nome,
                       'modalidade', v_mod,
                       'prazo_dias_uteis', case when v_mod <> 'importacao' then v_du end,
                       'prazo_dias_corridos', case when v_mod = 'importacao' then v_corr end,
                       'dito', v_n, 'convertido', v_conv, 'mesmo_que_id', v_y,
                       'frase_pronta', v_frase, 'frase_gravada', v_grav),
    p_trecho, p_hoje);

  return jsonb_build_object('ok', true, 'item', v_item, 'itens', jsonb_build_array(v_item),
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
end;
$function$;

comment on function public.agenda_rascunho_fornecedor(uuid, text, text, text, numeric, text, text, text, date) is
  'Agenda de Produção (Fase 4, P1): como o dono compra de um fornecedor e em quantos dias chega vira RASCUNHO (nada em suppliers). Fornecedor pelo nome (ambíguo = a pergunta com a cidade de cada um; não cadastrado = recusa, o cadastro é pela tela). modalidade (balcao, entrega_local, distribuidor_sc_pr, outro_estado, marketplace, importacao; sem ela, a da correção aberta ou a que vale hoje), prazo (inteiro, tem de estar no trecho; "no balcão" sem número = o da classe), unidade (uteis | corridos; importado sempre em corridos; os corridos de quem não é importado viram dias úteis por agenda_du_entre), mesmo_que (o outro cadastro do mesmo fornecedor: copia como ele entrega, dito no mesmo lote ou já gravado). Chave fornecedor:<id> (a correção substitui). Devolve {ok, item, itens, releitura}.';

-- O *grava* do prazo do fornecedor: o cadastro passa a dizer como o dono compra dele (prazo_fonte 'dono'), e as perguntas
-- de cadastro desse fornecedor e a pergunta única dos principais se resolvem.
create or replace function public._agenda_aplicar_fornecedor(p_autor uuid, p_dados jsonb, p_trecho text, p_hoje date)
 returns text
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_id   uuid := (p_dados ->> 'fornecedor_id')::uuid;
  v_y    uuid := (p_dados ->> 'mesmo_que_id')::uuid;
  v_mod  text := p_dados ->> 'modalidade';
  v_du   int := (p_dados ->> 'prazo_dias_uteis')::int;
  v_corr int := (p_dados ->> 'prazo_dias_corridos')::int;
  v_yd   jsonb;
  v_nome text := coalesce(p_dados ->> 'nome', 'fornecedor');
begin
  if v_id is null or not exists (select 1 from public.suppliers where id = v_id) then
    raise exception 'O fornecedor desta linha não está mais no cadastro.';
  end if;
  if v_y is not null then
    -- O outro cadastro vale como está AGORA: a linha dele neste mesmo lote (ainda aberta, ou gravada nesta transação), senão
    -- o que o cadastro dele diz.
    select r.dados into v_yd
      from public.agenda_rascunho r
     where r.autor = p_autor and r.chave = 'fornecedor:' || v_y
       and (r.estado = 'aberto' or (r.estado = 'gravado' and r.gravado_em = now()))
     order by r.criado_em desc
     limit 1;
    if (v_yd ->> 'modalidade') is null then
      select jsonb_build_object('modalidade', f.modalidade, 'prazo_dias_uteis', f.prazo_dias_uteis,
                                'prazo_dias_corridos', f.prazo_dias_corridos)
        into v_yd
        from public.suppliers f where f.id = v_y and f.modalidade is not null;
    end if;
    if (v_yd ->> 'modalidade') is not null then
      v_mod := v_yd ->> 'modalidade';
      v_du := (v_yd ->> 'prazo_dias_uteis')::int;
      v_corr := (v_yd ->> 'prazo_dias_corridos')::int;
    end if;
  end if;
  if v_mod is null then
    raise exception 'Falta dizer como você compra da %.', v_nome;
  end if;

  update public.suppliers
     set modalidade = v_mod,
         prazo_dias_uteis = case when v_mod <> 'importacao' then v_du end,
         prazo_dias_corridos = case when v_mod = 'importacao' then v_corr end,
         prazo_fonte = 'dono', prazo_informado_em = now(),
         prazo_trecho = left(nullif(btrim(coalesce(p_trecho, '')), ''), 300)
   where id = v_id;

  update public.agenda_perguntas
     set estado = 'resolvida', resolvida_motivo = left(format('você disse como compra da %s', v_nome), 200)
   where estado = 'aberta' and (chave = 'fornecedor_cadastro:' || v_id or tipo = 'fornecedores_prazo');

  return coalesce(p_dados ->> 'frase_gravada', v_nome || ': ' || public._agenda_classe_texto(v_mod, v_du, v_corr) || '.');
end;
$function$;

comment on function public._agenda_aplicar_fornecedor(uuid, jsonb, text, date) is
  'Agenda de Produção (Fase 4, P1): grava uma linha de rascunho fornecedor — suppliers.modalidade, prazo_dias_uteis (não importado), prazo_dias_corridos (importado), prazo_fonte dono, prazo_informado_em e prazo_trecho; com mesmo_que, como o outro cadastro está agora (a linha dele no mesmo lote, senão o cadastro dele). Resolve as perguntas fornecedor_cadastro:<fornecedor> e fornecedores_prazo ("você disse como compra da X"). Devolve a frase do "Gravado. Agora:". Só pelo agenda_rascunho_gravar; só service_role.';

-- ── 6. O *grava*: o tipo fornecedor ─────────────────────────────────────────────────────────────────────
-- Corpo de 20261026100200 copiado; a mudança está marcada "-- FASE 4:".

create or replace function public.agenda_rascunho_gravar(p_autor uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor   uuid := public._autor_da_agenda(p_autor);
  v_exp     int;
  v_exp_dia date;
  v_ids     uuid[];
  v_oss_mat uuid[];
  v_r       public.agenda_rascunho%rowtype;
  v_x       uuid;
  v_n       int := 0;
  v_item    text;
  v_estado  text;
  v_msg     text;
  v_linhas  text[] := '{}';
  v_g       record;
  v_p       jsonb;
  v_nome    int;
  -- FASE 2: a hora do *grava* (now(); a bancada fixa com set_config('agenda.agora', …, true), como agenda.hoje), a
  -- config, as frases do que a agenda fez com os pedidos e o tipo de cada linha.
  v_agora   timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  cf        public.agenda_config := public._agenda_cfg();
  v_f2      text[] := '{}';
  v_f2_item text;
begin
  perform pg_advisory_xact_lock(hashtext('agenda_rascunho:' || v_autor::text));

  -- O que passou da validade não grava (e fica marcado, mesmo se o resto falhar).
  with e as (
    update public.agenda_rascunho set estado = 'expirado'
     where autor = v_autor and estado = 'aberto' and expira_em <= now()
    returning criado_em)
  select count(*), max((e.criado_em at time zone 'America/Sao_Paulo')::date) into v_exp, v_exp_dia from e;

  -- FASE 2: primeiro os fatos (Fase 1), depois o andamento, marcar, publicar/decidir e desfazer — cada grupo na ordem em
  -- que o dono falou.
  select coalesce(array_agg(r.id order by case r.tipo when 'andamento' then 1 when 'marcar' then 2 when 'aplicar' then 3
                                                      when 'desfazer' then 4 else 0 end,
                                          (r.dados ->> 'ordem')::int, r.criado_em, r.id), '{}'),
         coalesce(array_agg(distinct r.service_order_id) filter (where r.tipo = 'material'), '{}')
    into v_ids, v_oss_mat
    from public.agenda_rascunho r
   where r.autor = v_autor and r.estado = 'aberto';

  if cardinality(v_ids) = 0 then
    return jsonb_build_object('ok', true, 'gravados', 0, 'expirados', v_exp,
      'texto', case when v_exp > 0 then format('A releitura de %s expirou; me diga de novo o que mudou.', public._dia_curto(v_exp_dia))
                    else 'Não tenho nada esperando para gravar.' end);
  end if;

  -- FASE 2: com a agenda automática fora de 'ligado', o pedido à agenda não grava — e o lote é tudo ou nada.
  -- FASE 3: menos concluir e entregar, que valem em todos os modos (a conclusão pela porta é a correção do D7).
  if cf.modo_proposta <> 'ligado'
     and exists (select 1 from public.agenda_rascunho r where r.id = any (v_ids) and r.tipo in ('marcar', 'aplicar', 'desfazer', 'andamento')
                    and not (r.tipo = 'andamento' and r.dados ->> 'evento' in ('concluiu', 'entregou'))) then
    return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'motivo', 'em_teste',
      'texto', 'Não gravei nada: a agenda automática ainda está em teste e o que você pediu mexe na agenda. Mande *descarta* e me diga de novo o resto.');
  end if;

  -- Tudo ou nada: um item que não passa desfaz o lote inteiro (as linhas continuam abertas para corrigir).
  begin
    foreach v_x in array v_oss_mat loop
      perform public.os_material_sincronizar(v_x, p_hoje);   -- as linhas espelho existem antes do fato
    end loop;

    -- O padrão novo de uma pessoa troca, UMA vez antes de entrar o lote, só o que ele realmente troca:
    --   · "vem" (seg a qui): as linhas de padrão dela (do histórico e do dono) que caem em algum desses dias; os
    --     outros dias da semana continuam como estavam;
    --   · "só de manhã", "só à tarde", "não vem" (terça): o "vem" fica; a linha indisponível do turno entra por cima
    --     (a capacidade põe o "não vem neste turno" acima do padrão "vem"). Só sai a restrição que o dono já tinha
    --     dito para os mesmos dias ("só à tarde às terças" e depois "só de manhã às terças").
    update public.agenda_disponibilidade a
       set substituida_em = now()
      from (select (r.dados ->> 'payee_id')::uuid as payee, r.dados ->> 'situacao' as situacao,
                   array(select jsonb_array_elements_text(r.dados -> 'dias_semana')::smallint) as dias
              from public.agenda_rascunho r
             where r.id = any (v_ids) and r.tipo = 'disponibilidade' and (r.dados ->> 'padrao')::boolean) n
     where a.substituida_em is null and a.dias_semana is not null and a.payee_id = n.payee
       and ((n.situacao = 'disponivel' and a.origem in ('historico', 'dono') and a.dias_semana && n.dias)
            or (n.situacao = 'indisponivel' and a.origem = 'dono' and a.situacao = 'indisponivel'
                and a.dias_semana <@ n.dias));

    foreach v_x in array v_ids loop
      select * into v_r from public.agenda_rascunho where id = v_x for update;
      v_item := v_r.texto;
      case v_r.tipo
        when 'planejar' then
          perform public._agenda_aplicar_planejar(v_autor, v_r.service_order_id, v_r.dados, v_r.trecho, p_hoje);
        when 'material' then
          perform public._agenda_aplicar_material(v_autor, v_r.service_order_id, v_r.dados, v_r.trecho, p_hoje);
        when 'disponibilidade' then
          perform public._agenda_aplicar_disponibilidade(v_autor, v_r.dados, v_r.trecho, p_hoje);
        -- FASE 4: o prazo do fornecedor vai ao cadastro dele; a frase entra no "Gravado. Agora:" junto dos pedidos.
        when 'fornecedor' then
          v_f2 := v_f2 || public._agenda_aplicar_fornecedor(v_autor, v_r.dados, v_r.trecho, p_hoje);
        -- FASE 4: fim
        else
          -- FASE 2: o pedido à agenda (marcar, aplicar/decidir, desfazer, andamento) pelas funções do motor.
          v_f2_item := public._agenda_aplicar_pedido(v_autor, v_r.tipo, v_r.service_order_id, v_r.dados, v_r.trecho, v_r.canal,
                                                     p_hoje, v_agora);
          if nullif(btrim(coalesce(v_f2_item, '')), '') is not null then
            v_f2 := v_f2 || v_f2_item;
          end if;
      end case;
      update public.agenda_rascunho set estado = 'gravado', gravado_em = now() where id = v_x;
      v_n := v_n + 1;
    end loop;

    foreach v_x in array v_oss_mat loop
      perform public.os_material_sincronizar(v_x, p_hoje);
    end loop;
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    -- FASE 3: a porta recusou concluir ou entregar (o período fechado no financeiro): a frase dela.
    if v_estado = 'P0096' then
      return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'erro', v_msg, 'sqlstate', v_estado,
        'texto', 'Não gravei nada. ' || btrim(v_msg));
    end if;
    -- FASE 2: a agenda recusou um pedido (a proposta ficou velha, a decisão mudou, não coube, já começou…).
    if v_estado = 'P0097' then
      return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'erro', v_msg, 'sqlstate', v_estado,
        'texto', format('Não gravei nada. A agenda mudou desde a releitura: %s. Me peça de novo.', rtrim(btrim(v_msg), '.')));
    end if;
    return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'erro', v_msg, 'sqlstate', v_estado,
      'texto', format('Não gravei nada: %s (%s). Corrija o que estiver errado, ou mande *descarta*, e depois *grava* de novo.',
                      case when v_estado = 'P0001' then v_msg else 'o banco recusou um item' end,
                      coalesce(v_item, 'o lote')));
  end;

  -- "Gravado. Agora:" — uma linha por OS (o estado da prontidão) e por pessoa, na ordem em que o dono falou.
  for v_g in
    select r.dados ->> 'grupo' as grupo, min((r.dados ->> 'ordem')::int) as ordem,
           (array_agg(r.service_order_id order by (r.dados ->> 'ordem')::int))[1] as os,
           (array_agg(r.dados order by (r.dados ->> 'ordem')::int))[1] as d,
           string_agg(r.dados ->> 'frase', '; ' order by (r.dados ->> 'ordem')::int) as frases
      from public.agenda_rascunho r
     where r.id = any (v_ids) and r.tipo in ('planejar', 'material', 'disponibilidade')   -- FASE 2: os pedidos vêm em v_f2
     group by r.dados ->> 'grupo'
     order by 2
  loop
    if v_g.os is not null then
      v_p := public.os_prontidao(v_g.os, p_hoje);
      select count(*) into v_nome from public.os_carteira(p_hoje) k where k.cliente_curto = v_p ->> 'cliente_curto';
      v_linhas := v_linhas || ('• ' || public._agenda_rotulo(jsonb_build_object(
                                 'curto', v_p ->> 'cliente_curto', 'numero', v_p ->> 'numero',
                                 'eh_orc', (v_p ->> 'eh_orcamento')::boolean, 'n_nome', v_nome))
                               || ': ' || (v_p ->> 'estado_texto') || '.');
    else
      v_linhas := v_linhas || ('• ' || (v_g.d ->> 'rotulo_grupo') || ': ' || v_g.frases || '.');
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'gravados', v_n, 'expirados', v_exp,
    'texto', 'Gravado. Agora:' || E'\n' || array_to_string(v_linhas || array(select '• ' || x from unnest(v_f2) x), E'\n')
             || case when v_exp > 0 then E'\n' || format('(A releitura de %s tinha expirado e não foi gravada.)', public._dia_curto(v_exp_dia))
                     else '' end);
end;
$function$;

comment on function public.agenda_rascunho_gravar(uuid, date) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): o *grava* do dono — numa transação, tudo ou nada: marca expirado o que passou da validade; sincroniza o material das OS do lote; troca UMA vez, das pessoas com padrão novo, só os padrões que o "vem" cobre; aplica primeiro os fatos (_agenda_aplicar_planejar/_material/_disponibilidade; Fase 4: _agenda_aplicar_fornecedor, o prazo dito de um fornecedor, que não depende do modo da agenda), depois os pedidos à agenda da Fase 2 na ordem andamento, marcar, aplicar/decidir e desfazer (_agenda_aplicar_pedido: agenda_registrar_dia, a porta, agenda_marcar_os, agenda_aplicar, agenda_decidir, agenda_desfazer, com p_agora = a hora do *grava*); sincroniza de novo. Com modo_proposta fora de ligado, o lote com pedido à agenda não grava (Fase 3: menos concluir e entregar, que gravam em todos os modos; a recusa da porta = "Não gravei nada. Não concluí: …" e o lote volta). Devolve {ok, gravados, expirados, texto "Gravado. Agora:" + uma linha por OS (estado da prontidão), por pessoa e por pedido (a frase da agenda)}; item que não passa: {ok:false, texto "Não gravei nada: …" ou "Não gravei nada. A agenda mudou desde a releitura: …. Me peça de novo.", erro} e nada muda. Chamada só pelo comando sem IA "grava", nunca por ferramenta do modelo.';

-- ── 7. Portas ───────────────────────────────────────────────────────────────────────────────────────────
-- Leituras: security invoker (a RLS de quem lê vale), STABLE/IMMUTABLE, sem anon; authenticated (o painel, com o login
-- do admin) e service_role (o WhatsApp, o motor e o fechamento). As recriadas mantêm a ACL (create or replace), e o
-- revoke/grant de novo não custa.
revoke all on function
  public._agenda_lugar_normal(text), public._agenda_lugar_casa(text, text), public._agenda_classe_por_lugar(text, text),
  public._agenda_lugar_texto(text, text), public._agenda_classe_pelo_nome(text), public._agenda_nome_de_grupo(text),
  public._agenda_classe_texto(text, integer, integer), public._agenda_prazo_do_fornecedor(uuid),
  public._agenda_chegada_pela_classe(text, integer, integer, date), public._agenda_chegada_estimada(uuid, date),
  public._agenda_classe_do_fornecedor(uuid), public.os_prontidao(uuid, date)
  from public, anon;
grant execute on function
  public._agenda_lugar_normal(text), public._agenda_lugar_casa(text, text), public._agenda_classe_por_lugar(text, text),
  public._agenda_lugar_texto(text, text), public._agenda_classe_pelo_nome(text), public._agenda_nome_de_grupo(text),
  public._agenda_classe_texto(text, integer, integer), public._agenda_prazo_do_fornecedor(uuid),
  public._agenda_chegada_pela_classe(text, integer, integer, date), public._agenda_chegada_estimada(uuid, date),
  public._agenda_classe_do_fornecedor(uuid), public.os_prontidao(uuid, date)
  to authenticated, service_role;

-- A RPC da ferramenta (confere o cargo por _autor_da_agenda): o painel e o WhatsApp. O *grava* também.
revoke all on function
  public.agenda_rascunho_fornecedor(uuid, text, text, text, numeric, text, text, text, date),
  public.agenda_rascunho_gravar(uuid, date)
  from public, anon;
grant execute on function
  public.agenda_rascunho_fornecedor(uuid, text, text, text, numeric, text, text, text, date),
  public.agenda_rascunho_gravar(uuid, date)
  to authenticated, service_role;

-- As internas (a frase e o *grava* da linha): só service_role. As RPCs acima as chamam como dono das funções.
revoke all on function
  public._agenda_rascunho_frase(text, jsonb), public._agenda_aplicar_fornecedor(uuid, jsonb, text, date),
  public._agenda_fornecedor_dito(text)
  from public, anon, authenticated;
grant execute on function
  public._agenda_rascunho_frase(text, jsonb), public._agenda_aplicar_fornecedor(uuid, jsonb, text, date),
  public._agenda_fornecedor_dito(text)
  to service_role;
