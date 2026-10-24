-- Agenda de Produção, Fase 1 ("O que eu tenho que fazer"), pacote P5: a escrita pela conversa — rascunho, releitura e
-- o *grava*.
-- Spec: scratchpad agenda-pesquisa/spec-fase1.md (§3 itens 1–3, §5.8, §6 "Releitura" e "Depois do grava", §8.5 R01).
-- Depende de 20261024160000 (tabelas), 160100 (calendário e datas ditas), 160300 (material e sincronização), 160400
-- (resolvedores, duração, prontidão) e 160500 (textos curtos das leituras).
--
-- ═══ DDL — OK NOMEADO ═══ (funções novas; nenhuma tabela, nenhum dado. Grava só quando o dono manda *grava*.)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- POR QUE: o dono conta a agenda conversando, por texto ou áudio ("Lenine dois dias com o Roberto", "o compressor do
-- Flávio chegou dia 14", "eu fico em campo de segunda a sexta"). Nada disso pode virar fato sem ele conferir: o modelo
-- erra nome, inventa número e calcula data. Então as três ferramentas de escrita só gravam RASCUNHO, já resolvido no
-- banco (qual OS, qual pessoa, qual peça, qual fornecedor, qual data), e devolvem a releitura pronta ("Entendi assim,
-- confere? … Responda *grava*"). Quem transforma o rascunho em fato é agenda_rascunho_gravar, chamada só pelo comando
-- sem IA "grava" (P6): o modelo não tem ferramenta para gravar.
--
-- O QUE MUDA (todas security definer, search_path fixo, p_hoje em todas as que lidam com data):
--   1. _autor_da_agenda(p_autor): quem mexe. Pelo painel (JWT) é o login, e tem de ser admin ativo; pelo WhatsApp
--      (service role, sem login) é p_autor, que tem de ser admin ativo. Senão 42501 "Só o administrador mexe na agenda."
--   2. agenda_rascunho_planejar(p_autor, p_canal, p_os, p_dados, p_trecho, p_hoje): dias, quem vai e em que turno,
--      presença do dono, até quando o cliente precisa, quando o barco/motorhome está fora (bem_fora) ou volta
--      (bem_livre_em), "não antes de", escopo em aberto/decidido, espera, prioridade, "não tem peça a comprar" e
--      "aceito a sua estimativa".
--   3. agenda_rascunho_material(p_autor, p_canal, p_os, p_itens, p_situacao, p_quando, p_fornecedor, p_quantidade,
--      p_novo, p_trecho, p_hoje): comprei · a_caminho (previsão do dono = nível C; a 1ª fica em previsao_original) ·
--      na_mao/chegou (chegou_em = a data dita ou hoje; quantidade completa, ou a parcial dita) · vou_comprar (falta +
--      compra combinada + fornecedor) · falta · sem_previsao · pode_comecar_sem (critico = false) · dispensar. p_novo =
--      material fora do orçamento (origem dono; aponta a linha de serviço da peça embutida quando o nome casa com uma).
--   4. agenda_rascunho_disponibilidade(p_autor, p_canal, p_pessoa, p_situacao, p_dias, p_padrao, p_trecho, p_hoje):
--      vem · nao_vem · so_manha · so_tarde, por padrão ("segunda a sexta") ou por data ("terça").
--      As três resolvem tudo no banco; o que é ambíguo ou não existe volta como PERGUNTA ({ok:false, pergunta,
--      opcoes}) e NÃO entra no rascunho. Guarda contra número e data que o dono não disse: os dias, a quantidade e
--      cada data têm de estar no trecho (normalizado: "dois" = 2, "um e meio", "meio dia", "terça-feira" = "terça");
--      senão "Não achei "x" no que você disse; me diga de novo." Uma linha de rascunho por chave (planejar:<os>,
--      material:<origem>:<linha>, disp:<pessoa>:<quando>:<turno>): a correção substitui a linha aberta, e o que não
--      foi dito de novo continua (o "o João ajuda à tarde" depois de "dois dias" não apaga os dois dias).
--   5. agenda_rascunho_ler(p_autor, p_hoje): a releitura do lote aberto, uma linha por OS (e por pessoa), na ordem em
--      que o dono falou; as peças com a mesma situação vão juntas ("Cerbo…, Orion… e KIT Cabos… na mão (desde hoje)").
--   6. agenda_rascunho_gravar(p_autor, p_hoje): numa transação, tudo ou nada. Marca expirado o que passou de
--      expira_em; aplica cada item por _agenda_aplicar_planejar/_material/_disponibilidade (só service_role); o padrão
--      novo de uma pessoa substitui os padrões dela (histórico e dono) UMA vez antes de entrar o lote; sincroniza o
--      material das OS afetadas (antes, para as linhas existirem, e depois); acrescenta ao histórico de cada linha
--      {em, autor, trecho, antes, depois}. Devolve "Gravado. Agora:" com uma linha por OS (o estado da prontidão) e
--      por pessoa. Item que não passa desfaz o lote inteiro e diz qual ("Não gravei nada: …").
--   7. agenda_rascunho_descartar(p_autor): "Descartei. Nada foi gravado."
--   Auxiliares (só service_role): _agenda_trecho_tem, _agenda_trecho_tem_numero, _agenda_data_conferida, _agenda_recusa,
--   _agenda_recusa_da_os, _agenda_os_do_rascunho, _agenda_dias_citados, _agenda_dias_semana_texto, _agenda_quando_texto,
--   _agenda_resolver_fornecedor, _agenda_rotulo_do_item, _agenda_rascunho_frase, _agenda_rascunho_salvar.
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase1_rascunho.sql):
--   · a RPC de material NÃO sincroniza a OS antes de resolver o item (a spec §5.3 mandava): a sincronização cria linhas
--     em os_material, e o contrato do pacote é "nada toca as tabelas de fato antes do grava". O item é resolvido sobre
--     a prontidão (conta bruta + os_material, P3), que já tem todas as linhas, e a chave do rascunho é o VÍNCULO
--     (material:peca:<linha da peça>, material:texto_livre:<linha de serviço>, material:oc:<item da OC>,
--     material:dono:<id>) em vez de material:<os_material.id>. Quem sincroniza é o *grava*.
--   · bem_livre_em, além de bem_fora: "o motorhome só fica livre dia 3" é livre EM 03/11 (fora até 02/11), e "fica
--     fora até dia 3" é fora ATÉ 03/11. Com um campo só, um dos dois sairia um dia errado (R01 espera livre ter 03/11).
--   · a correção substitui a linha do rascunho, mas o que a correção não repete fica (merge por campo): a spec dizia só
--     "substitui", o que faria o 2º pedaço do mesmo áudio apagar o 1º.
--   · o "vou comprar" com fornecedor fica sem artigo ("você compra ter 27/10, fornecedor Premel"): o banco não sabe se
--     é "na Premel" ou "no Mateus" (mesma regra do P4 para nomes de pessoa).
--   · agenda_rascunho_ler/gravar/descartar também abrem para authenticated (conferem o cargo como as três de escrita):
--     o *grava* do painel (P6) e uma tela futura usam a mesma porta.
--
-- O QUE NÃO MUDA: nenhuma tabela, nenhuma função de P1–P4, compras, o Secretário, as telas. Nenhum cron.
--
-- ORDEM DE LIGAR: depois de 20261024160000..160500. Vai para produção JUNTO com o P6 (o comando *grava*): sem ele o
-- rascunho nunca vira fato (a ferramenta continua respondendo a releitura, e o dono não teria como gravar).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase1_rascunho.sql (begin/rollback; com a fixture de 23/10 o áudio
-- R01 inteiro e o estado de scripts/bancada-agenda/fixture-2310-pos-rodada.sql). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261024160600
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; depois de 160000..160500):
--   npx supabase db query --linked -f supabase/migrations/20261024160600_agenda_fase1_rascunho.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261024160600', 'agenda_fase1_rascunho');"
--
-- IDEMPOTENTE: só create or replace function, revoke/grant e comment.

-- ── 0. Quem mexe na agenda ──────────────────────────────────────────────────────────────────────────────

create or replace function public._autor_da_agenda(p_autor uuid)
 returns uuid
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  v_uid   uuid := auth.uid();
  v_papel text;
begin
  -- Pelo painel (JWT) vale o login, e p_autor não conta; pelo WhatsApp (service role, sem login) vale p_autor.
  if v_uid is not null then
    if public.is_admin(v_uid) then
      return v_uid;
    end if;
  else
    -- p_autor só vale para quem chama sem login de usuário (service role, ou o próprio banco). Um JWT de outro papel
    -- sem "sub" não ganha o direito de dizer quem é.
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel in ('', 'service_role') and p_autor is not null and public.is_admin(p_autor) then
      return p_autor;
    end if;
  end if;
  raise exception 'Só o administrador mexe na agenda.' using errcode = '42501';
end;
$function$;

comment on function public._autor_da_agenda(uuid) is
  'Agenda de Produção (Fase 1, P5): quem mexe na agenda. Com login (painel) é o próprio login, que tem de ser admin ativo; sem login (service role, WhatsApp) é p_autor, que tem de ser admin ativo — e só sem login: um JWT de outro papel sem sub não vale. Senão 42501 "Só o administrador mexe na agenda."';

-- ── 1. Guardas: o número e a data têm de estar no que o dono disse ──────────────────────────────────────

-- O texto dito (uma data, os dias da semana) aparece no trecho, os dois normalizados do mesmo jeito (minúsculo, sem
-- acento, número por extenso em dígito, "terça-feira" = "terça"), palavra inteira.
create or replace function public._agenda_trecho_tem(p_trecho text, p_dito text)
 returns boolean
 language sql
 immutable
 set search_path to 'public'
as $function$
  select nullif(public._agenda_preparar_data(p_dito), '') is not null
     and (' ' || public._agenda_preparar_data(p_trecho) || ' ') like ('% ' || public._agenda_preparar_data(p_dito) || ' %');
$function$;

comment on function public._agenda_trecho_tem(text, text) is
  'Agenda de Produção (Fase 1, P5): o que o modelo passou como data ("dia 3", "terça") está nas palavras do dono? Os dois lados normalizados por _agenda_preparar_data (extenso em dígito, sem acento), palavra inteira.';

-- O número (dias, quantidade) aparece no trecho: em dígito ou por extenso ("dois"), e o meio como "um e meio", "um dia e
-- meio", "meio dia" ou com vírgula/ponto. As datas do trecho ("dia 3", "03/11") não valem como número.
create or replace function public._agenda_trecho_tem_numero(p_trecho text, p_n numeric)
 returns boolean
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  s      text := ' ' || regexp_replace(regexp_replace(public._agenda_preparar_data(p_trecho),
                     '\mdia \d{1,2}\M', ' ', 'g'), '\m\d{1,2}/\d{1,2}(/\d{2,4})?\M', ' ', 'g') || ' ';
  v_int  text;
  v_frac text;
begin
  if p_n is null or p_n <= 0 then
    return false;
  end if;
  v_int := trunc(p_n)::text;
  v_frac := nullif(regexp_replace(trim_scale(p_n - trunc(p_n))::text, '^0\.', ''), '0');
  if v_frac is null then
    return s ~ ('\m' || v_int || '\M');
  end if;
  -- A normalização transforma a vírgula em espaço e o ponto em barra: "N vírgula F" fica "N F", "N ponto F" fica "N/F".
  return s ~ ('\m' || v_int || '[ /]' || v_frac || '\M')
      or (v_frac = '5' and (s ~ ('\m' || v_int || ' (dias? |diarias? )?e (meio|meia)\M')
                            or (v_int = '0' and s ~ '\m(meio|meia)\M')));
end;
$function$;

comment on function public._agenda_trecho_tem_numero(text, numeric) is
  'Agenda de Produção (Fase 1, P5): o número está nas palavras do dono? Dígito ou extenso ("dois" = 2), "um e meio", "um dia e meio", "meio dia", com vírgula ou ponto. "dia 3" e "03/11" do trecho não contam como número (são datas).';

-- A recusa que volta ao modelo: nada entra no rascunho, e a pergunta vai ao dono como está.
create or replace function public._agenda_recusa(p_pergunta text, p_motivo text, p_opcoes jsonb default '[]'::jsonb)
 returns jsonb
 language sql
 immutable
 set search_path to 'public'
as $function$
  select jsonb_build_object('ok', false, 'motivo', p_motivo, 'pergunta', p_pergunta, 'texto', p_pergunta,
                            'opcoes', coalesce(p_opcoes, '[]'::jsonb));
$function$;

comment on function public._agenda_recusa(text, text, jsonb) is
  'Agenda de Produção (Fase 1, P5): {ok:false, motivo, pergunta, texto, opcoes} — nada entra no rascunho; a pergunta vai ao dono como está.';

-- A data dita, conferida no trecho e entendida por agenda_data_dita. Fora do trecho ou incompreensível = recusa.
create or replace function public._agenda_data_conferida(p_dito text, p_trecho text, p_hoje date, p_sentido text)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v jsonb;
begin
  if not public._agenda_trecho_tem(p_trecho, p_dito) then
    return public._agenda_recusa(format('Não achei "%s" no que você disse; me diga de novo.', btrim(p_dito)), 'fora_do_trecho');
  end if;
  begin
    v := public.agenda_data_dita(p_dito, p_hoje, p_sentido);
  exception when sqlstate '22007' then
    return public._agenda_recusa(sqlerrm, 'data');
  end;
  return v || jsonb_build_object('ok', true);
end;
$function$;

comment on function public._agenda_data_conferida(text, text, date, text) is
  'Agenda de Produção (Fase 1, P5): a data que o modelo passou, conferida nas palavras do dono e convertida por agenda_data_dita ({de, ate, texto, ok:true}); fora do trecho ou incompreensível = recusa com a frase para o dono.';

-- Os dias da semana citados num texto (com repetição; "menos" não tira): a guarda do padrão de disponibilidade.
create or replace function public._agenda_dias_citados(p_texto text)
 returns integer[]
 language sql
 immutable
 set search_path to 'public'
as $function$
  select public._agenda_dias_ditos_parte(
           regexp_replace(regexp_replace(public._agenda_normal(p_texto),
             '\m(segunda|terca|quarta|quinta|sexta) feira\M', '\1', 'g'),
             '\m(segunda|terca|quarta|quinta|sexta|sabado|domingo)s\M', '\1', 'g'));
$function$;

comment on function public._agenda_dias_citados(text) is
  'Agenda de Produção (Fase 1, P5): os dias ISO citados num texto ("segunda a sexta", "terças", "dia de semana"), para conferir que o padrão dito está nas palavras do dono.';

-- ── 2. Textos curtos da releitura ───────────────────────────────────────────────────────────────────────

-- {1,2,3,4,5} → "de seg a sex"; {5} → "toda sexta"; {6} → "todo sábado"; {2,4} → "toda terça e quinta".
create or replace function public._agenda_dias_semana_texto(p_dias smallint[])
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v     int[] := array(select distinct d::int from unnest(coalesce(p_dias, '{}'::smallint[])) d order by 1);
  n     int := cardinality(v);
  curto constant text[] := array['seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];
  nome  constant text[] := array['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado'];
begin
  if n = 0 then
    return null;
  end if;
  if n = 1 then
    return case when v[1] = 6 then 'todo sábado' else 'toda ' || nome[v[1]] end;
  end if;
  if n >= 3 and v[n] - v[1] + 1 = n then
    return format('de %s a %s', curto[v[1]], curto[v[n]]);
  end if;
  return 'toda ' || public._agenda_lista(array(select nome[x] from unnest(v) with ordinality u(x, o) order by o), null);
end;
$function$;

comment on function public._agenda_dias_semana_texto(smallint[]) is
  'Agenda de Produção (Fase 1, P5): os dias de um padrão em texto curto — "de seg a sex", "toda sexta", "todo sábado", "toda terça e quinta".';

-- "ter 27/10" ou "de seg 26/10 a sex 30/10".
create or replace function public._agenda_quando_texto(p_de date, p_ate date)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case when p_ate is null or p_de = p_ate then public._dia_curto(p_de)
              else format('de %s a %s', public._dia_curto(p_de), public._dia_curto(p_ate)) end;
$function$;

comment on function public._agenda_quando_texto(date, date) is
  'Agenda de Produção (Fase 1, P5): um dia ("ter 27/10") ou um período ("de seg 26/10 a sex 30/10").';

-- ── 3. Resolvedores da escrita ──────────────────────────────────────────────────────────────────────────

-- A OS que não deu para resolver: a pergunta (ambíguo), o "não encontrei" ou o status de quem está fora da carteira.
create or replace function public._agenda_recusa_da_os(p_ro jsonb)
 returns jsonb
 language sql
 immutable
 set search_path to 'public'
as $function$
  select public._agenda_recusa(
    case when p_ro ->> 'status' = 'fora_da_carteira'
         then (p_ro ->> 'texto') || ' Só anoto o que é de serviço da carteira (OS aberta ou orçamento aprovado).'
         else p_ro ->> 'texto' end,
    'os_' || coalesce(p_ro ->> 'status', 'nao_achei'),
    coalesce((select jsonb_agg(e ->> 'texto' order by o)
                from jsonb_array_elements(coalesce(p_ro -> 'opcoes', '[]'::jsonb)) with ordinality t(e, o)), '[]'::jsonb));
$function$;

comment on function public._agenda_recusa_da_os(jsonb) is
  'Agenda de Produção (Fase 1, P5): a recusa quando agenda_resolver_os não devolve uma OS da carteira — a pergunta com as opções (ambíguo), o "não encontrei" ou o status de quem está fora da carteira.';

-- O que toda linha de rascunho de uma OS leva: o grupo da releitura e o nome ("Lenine (OS-00074)").
create or replace function public._agenda_os_do_rascunho(p_ro jsonb)
 returns jsonb
 language sql
 immutable
 set search_path to 'public'
as $function$
  select jsonb_build_object(
    'grupo', 'os:' || (p_ro ->> 'id'), 'os', p_ro ->> 'id', 'numero', p_ro ->> 'numero',
    'curto', p_ro ->> 'cliente_curto', 'eh_orc', coalesce((p_ro ->> 'eh_orcamento')::boolean, false),
    'rotulo_grupo', public._agenda_rotulo(jsonb_build_object('curto', p_ro ->> 'cliente_curto', 'numero', p_ro ->> 'numero'), 'num'));
$function$;

comment on function public._agenda_os_do_rascunho(jsonb) is
  'Agenda de Produção (Fase 1, P5): o cabeçalho de toda linha de rascunho de uma OS — grupo da releitura, id, número, nome curto e "Lenine (OS-00074)".';

-- O fornecedor dito: um cadastro ativo (todo pedaço do nome começa uma palavra do nome, da fantasia ou do nome usado),
-- nenhum (fica só o nome dito) ou vários (pergunta, com a cidade/UF de cada um).
create or replace function public._agenda_resolver_fornecedor(p_ref text)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_tok     text[] := array(select t from unnest(string_to_array(public._nome_comparavel(p_ref), ' ')) with ordinality u(t, o)
                             where length(t) >= 2 order by o);
  v_achados jsonb;
  v_n       int;
  v_opcoes  text[];
begin
  if cardinality(v_tok) = 0 then
    return jsonb_build_object('status', 'novo', 'nome', left(btrim(coalesce(p_ref, '')), 80),
                              'texto', left(btrim(coalesce(p_ref, '')), 80));
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id,
           'nome', public._agenda_nome_curto(coalesce(nullif(btrim(s.display_name), ''), nullif(btrim(s.trade_name), ''), s.name)),
           'texto', public._agenda_nome_curto(coalesce(nullif(btrim(s.display_name), ''), nullif(btrim(s.trade_name), ''), s.name))
                    || coalesce(' (' || nullif(concat_ws('/', nullif(btrim(s.city), ''), nullif(btrim(s.state), '')), '') || ')', ''))
           order by s.name collate "C", s.id), '[]'::jsonb), count(*)
    into v_achados, v_n
    from public.suppliers s
   where coalesce(s.active, true)
     and not exists (select 1 from unnest(v_tok) t
                      where not exists (select 1 from unnest(string_to_array(
                                          public._nome_comparavel(concat_ws(' ', s.name, s.trade_name, s.display_name)), ' ')) w
                                         where w like t || '%'));
  if v_n = 0 then
    return jsonb_build_object('status', 'novo', 'nome', left(btrim(p_ref), 80), 'texto', left(btrim(p_ref), 80));
  end if;
  if v_n = 1 then
    return jsonb_build_object('status', 'ok', 'id', v_achados -> 0 ->> 'id', 'nome', v_achados -> 0 ->> 'nome',
                              'texto', v_achados -> 0 ->> 'nome');
  end if;
  v_opcoes := array(select e ->> 'texto' from jsonb_array_elements(v_achados) with ordinality t(e, o) order by o);
  return jsonb_build_object('status', 'ambiguo',
    'opcoes', to_jsonb(v_opcoes),
    'texto', format('Qual %s: %s ou %s?', btrim(p_ref), array_to_string(v_opcoes[1:cardinality(v_opcoes) - 1], ', '),
                    v_opcoes[cardinality(v_opcoes)]));
end;
$function$;

comment on function public._agenda_resolver_fornecedor(text) is
  'Agenda de Produção (Fase 1, P5): o fornecedor que o dono disse — {status ok, id, nome} (um cadastro ativo casa pelo nome, fantasia ou nome usado), {status novo, nome} (nenhum: fica só o nome dito) ou {status ambiguo, texto, opcoes} ("Qual Kamell: Kamell (Vila Velha/ES) ou Kamell (Itajaí/SC)?").';

-- O nome curto do item na releitura, começando na palavra que o dono usou quando ela não está nas 3 primeiras
-- ("CENTRAL DE CONTROLE CERBO GX…" + "cerbo" → "Cerbo gx victron…").
create or replace function public._agenda_rotulo_do_item(p_descricao text, p_tokens text[])
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_pal text[] := regexp_split_to_array(btrim(coalesce(p_descricao, '')), '\s+');
  v_i   int;
begin
  if cardinality(coalesce(p_tokens, '{}'::text[])) > 0 then
    select u.o into v_i
      from unnest(v_pal) with ordinality u(w, o)
     where exists (select 1 from unnest(p_tokens) t
                    where exists (select 1 from unnest(string_to_array(public._agenda_normal(u.w), ' ')) x where x like t || '%'))
     order by u.o
     limit 1;
    if v_i > 3 then
      return public._agenda_linha_curta(array_to_string(v_pal[v_i:], ' '));
    end if;
  end if;
  return public._agenda_linha_curta(p_descricao);
end;
$function$;

comment on function public._agenda_rotulo_do_item(text, text[]) is
  'Agenda de Produção (Fase 1, P5): o nome curto do item para a releitura (_agenda_linha_curta), começando na palavra que o dono usou quando ela não está entre as 3 primeiras.';

-- ── 4. A frase de cada linha do rascunho (sai dos dados já resolvidos) ──────────────────────────────────

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
    end if;
    if nullif(p_d ->> 'escopo_em_aberto', '') is not null then
      v_partes := v_partes || ('falta decidir: ' || (p_d ->> 'escopo_em_aberto'));
    end if;
    if p_d ->> 'congelada_ate' is not null then
      v_partes := v_partes || ('em espera até ' || public._dia_curto((p_d ->> 'congelada_ate')::date)
                               || case when p_d ->> 'revisar_em' is distinct from p_d ->> 'congelada_ate'
                                       then ' (rever ' || public._dia_curto((p_d ->> 'revisar_em')::date) || ')' else '' end);
    end if;
    if p_d ->> 'prioridade' is not null then
      v_partes := v_partes || case when (p_d ->> 'prioridade')::int = 1 then 'passa na frente (prioridade 1)'
                                   else 'prioridade ' || (p_d ->> 'prioridade') end;
    end if;
    if p_d ->> 'sem_material' is not null then
      v_partes := v_partes || case when (p_d ->> 'sem_material')::boolean then 'não tem peça a comprar'
                                   else 'tem peça a conferir' end;
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
      else v_quando || ' de manhã, não' end;
  end if;

  raise exception '_agenda_rascunho_frase: tipo "%" não existe', p_tipo using errcode = '22023';
end;
$function$;

comment on function public._agenda_rascunho_frase(text, jsonb) is
  'Agenda de Produção (Fase 1, P5): a frase de uma linha do rascunho, montada dos dados já resolvidos — planejar ("2 dias com Roberto e João (à tarde); você abre e fecha"), material ("chega ter 03/11 (você disse)", "você compra ter 27/10, fornecedor Premel") e disponibilidade ("em campo de seg a sex", "toda sexta à tarde, não").';

-- ── 5. O rascunho: guardar (com a correção) e ler ───────────────────────────────────────────────────────

-- Guarda uma linha do rascunho. Se já há linha ABERTA com a mesma chave, ela vira 'substituido' e a nova herda o que
-- não foi dito de novo (merge por campo) e a posição na releitura. Devolve a linha da releitura.
create or replace function public._agenda_rascunho_salvar(p_autor uuid, p_canal text, p_tipo text, p_chave text, p_os uuid,
                                                          p_dados jsonb, p_trecho text, p_hoje date)
 returns text
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_velha  public.agenda_rascunho%rowtype;
  v_dados  jsonb := p_dados || jsonb_build_object('hoje', p_hoje);
  v_trecho text := btrim(coalesce(p_trecho, ''));
  v_ordem  int;
  v_frase  text;
  v_texto  text;
begin
  perform pg_advisory_xact_lock(hashtext('agenda_rascunho:' || p_autor::text));

  select r.* into v_velha
    from public.agenda_rascunho r
   where r.autor = p_autor and r.chave = p_chave and r.estado = 'aberto'
   for update;
  if found then
    if v_velha.expira_em <= now() then
      update public.agenda_rascunho set estado = 'expirado' where id = v_velha.id;
    else
      v_dados := (v_velha.dados - 'frase') || v_dados;
      v_ordem := (v_velha.dados ->> 'ordem')::int;
      if v_velha.trecho is not null and v_velha.trecho <> v_trecho
         and char_length(v_velha.trecho || ' / ' || v_trecho) <= 500 then
        v_trecho := v_velha.trecho || ' / ' || v_trecho;
      end if;
      update public.agenda_rascunho set estado = 'substituido' where id = v_velha.id;
    end if;
  end if;

  if v_ordem is null then
    select coalesce(max((r.dados ->> 'ordem')::int), 0) + 1 into v_ordem
      from public.agenda_rascunho r
     where r.autor = p_autor and r.estado = 'aberto';
  end if;

  v_frase := public._agenda_rascunho_frase(p_tipo, v_dados);
  v_dados := v_dados || jsonb_build_object('frase', v_frase, 'ordem', v_ordem);
  v_texto := public._agenda_corta(
    (v_dados ->> 'rotulo_grupo') || ': ' || coalesce((v_dados ->> 'rotulo') || ' ', '') || v_frase, 300);

  insert into public.agenda_rascunho (autor, canal, tipo, chave, service_order_id, dados, texto, trecho, expira_em)
  values (p_autor, p_canal, p_tipo, p_chave, p_os, v_dados, v_texto, public._agenda_corta(v_trecho, 500),
          now() + c.rascunho_validade);
  return v_texto;
end;
$function$;

comment on function public._agenda_rascunho_salvar(uuid, text, text, text, uuid, jsonb, text, date) is
  'Agenda de Produção (Fase 1, P5): guarda uma linha do rascunho (uma aberta por autor e chave). A aberta anterior da mesma chave vira substituido e a nova herda o que não foi dito de novo e a posição na releitura; expirada não é herdada. Devolve a linha da releitura.';

create or replace function public.agenda_rascunho_ler(p_autor uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor  uuid := public._autor_da_agenda(p_autor);
  v_linhas text;
  v_n      int;
begin
  with r as (
    select x.id, x.tipo, x.dados, x.dados ->> 'grupo' as grupo, (x.dados ->> 'ordem')::int as ordem
      from public.agenda_rascunho x
     where x.autor = v_autor and x.estado = 'aberto' and x.expira_em > now()
  ),
  seg as (
    -- As peças da mesma OS com a mesma frase vão juntas; o resto é uma frase por linha de rascunho.
    select r.grupo,
           case when r.tipo = 'material' then 'm:' || coalesce(r.dados ->> 'frase', '') else 'x:' || r.id::text end as chave,
           min(r.ordem) as ordem, count(*) as n, max((r.dados ->> 'total_itens')::int) as total,
           array_agg(r.dados ->> 'rotulo' order by r.ordem) as rotulos,
           min(r.dados ->> 'frase') as frase, bool_or(r.tipo = 'material') as eh_material
      from r
     group by 1, 2
  ),
  seg_txt as (
    select s.grupo, s.ordem,
           case when not s.eh_material then s.frase
                when s.n >= 2 and s.n = s.total then format('os %s itens %s', s.n, s.frase)
                else public._agenda_lista(s.rotulos, 3) || ' ' || s.frase end as txt
      from seg s
  ),
  grp as (
    select g.grupo, min(g.ordem) as ordem, string_agg(g.txt, '; ' order by g.ordem) as corpo,
           (select r.dados ->> 'rotulo_grupo' from r where r.grupo = g.grupo order by r.ordem limit 1) as rotulo
      from seg_txt g
     group by g.grupo
  )
  select string_agg('• ' || grp.rotulo || ': ' || grp.corpo
                    || case when right(grp.corpo, 1) in ('.', '?', '!') then '' else '.' end, E'\n' order by grp.ordem),
         count(*)
    into v_linhas, v_n
    from grp;

  if coalesce(v_n, 0) = 0 then
    return jsonb_build_object('ok', true, 'vazio', true, 'itens', 0, 'texto', 'Não tenho nada esperando para gravar.');
  end if;
  return jsonb_build_object('ok', true, 'vazio', false,
    'itens', (select count(*) from public.agenda_rascunho x
               where x.autor = v_autor and x.estado = 'aberto' and x.expira_em > now()),
    'texto', 'Entendi assim, confere?' || E'\n' || v_linhas || E'\n' || 'Responda *grava* ou corrija o que estiver errado.');
end;
$function$;

comment on function public.agenda_rascunho_ler(uuid, date) is
  'Agenda de Produção (Fase 1, P5): a releitura do lote aberto (não expirado) do autor — "Entendi assim, confere?", uma linha por OS e por pessoa na ordem em que o dono falou (peças com a mesma situação juntas) e "Responda *grava* ou corrija o que estiver errado." Sem nada: "Não tenho nada esperando para gravar."';

-- ── 6. As três escritas de rascunho ─────────────────────────────────────────────────────────────────────

create or replace function public.agenda_rascunho_planejar(p_autor uuid, p_canal text, p_os text, p_dados jsonb,
                                                           p_trecho text, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor  uuid := public._autor_da_agenda(p_autor);
  d        jsonb := coalesce(p_dados, '{}'::jsonb);
  c_campos constant text[] := array['dias', 'com_quem', 'dono', 'precisa_ate', 'bem_fora', 'bem_livre_em', 'nao_antes_de',
                                    'nao_antes_motivo', 'escopo_em_aberto', 'escopo_decidido', 'congelar_ate', 'revisar_em',
                                    'prioridade', 'sem_material', 'aceitar_sugestao'];
  v_k      text;
  v_ro     jsonb;
  v_os     uuid;
  v_out    jsonb := '{}'::jsonb;
  v_n      numeric;
  v_sug    jsonb;
  v_x      jsonb;
  v_rp     jsonb;
  v_turnos text;
  v_equipe jsonb := '[]'::jsonb;
  v_dt     jsonb;
  v_dt2    jsonb;
  v_bem    text;
  v_txt    text;
begin
  if p_canal is null or p_canal not in ('whatsapp', 'painel') then
    raise exception 'agenda_rascunho_planejar: canal "%" inválido (whatsapp ou painel)', p_canal using errcode = '22023';
  end if;
  if jsonb_typeof(d) <> 'object' then
    raise exception 'agenda_rascunho_planejar: p_dados tem de ser um objeto' using errcode = '22023';
  end if;
  select k into v_k from jsonb_object_keys(d) k where k <> all (c_campos) order by k limit 1;
  if v_k is not null then
    raise exception 'agenda_rascunho_planejar: o campo "%" não existe', v_k using errcode = '22023';
  end if;
  d := jsonb_strip_nulls(d);
  if nullif(btrim(p_trecho), '') is null then
    return public._agenda_recusa('Me diga com as suas palavras o que mudou nesse serviço.', 'sem_trecho');
  end if;

  v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
  if v_ro ->> 'status' <> 'ok' then
    return public._agenda_recusa_da_os(v_ro);
  end if;
  v_os := (v_ro ->> 'id')::uuid;

  -- Dias: o número dito (no trecho) ou "aceito a sua estimativa" (a sugestão, com fonte 'aceita').
  if d ? 'dias' then
    begin
      v_n := (d ->> 'dias')::numeric;
    exception when others then
      v_n := null;
    end;
    if v_n is null or v_n <= 0 or v_n > 60 or v_n * 2 <> trunc(v_n * 2) then
      return public._agenda_recusa('Quantos dias? Diga em dias ou meio dia (por exemplo, "2 dias" ou "um dia e meio").', 'dias_invalido');
    end if;
    if not public._agenda_trecho_tem_numero(p_trecho, v_n) then
      return public._agenda_recusa(format('Não achei "%s" no que você disse; me diga de novo quantos dias.', public._agenda_dias(v_n)),
                                   'fora_do_trecho');
    end if;
    v_out := v_out || jsonb_build_object('dias', trim_scale(v_n), 'estimativa_fonte', 'dono');
  elsif coalesce((d ->> 'aceitar_sugestao')::boolean, false) then
    v_sug := public.os_duracao_sugerida(v_os);
    if coalesce((v_sug ->> 'sem_base')::boolean, false) or v_sug ->> 'sugerida' is null then
      return public._agenda_recusa('O orçamento não dá base para eu estimar: quantos dias?', 'sem_base');
    end if;
    v_out := v_out || jsonb_build_object('dias', (v_sug ->> 'sugerida')::numeric, 'estimativa_fonte', 'aceita');
  end if;

  -- Quem vai, por turno ("dia" quando não disse).
  if d ? 'com_quem' then
    if jsonb_typeof(d -> 'com_quem') <> 'array' then
      raise exception 'agenda_rascunho_planejar: com_quem tem de ser uma lista' using errcode = '22023';
    end if;
    for v_x in select e from jsonb_array_elements(d -> 'com_quem') with ordinality t(e, o) order by o loop
      if jsonb_typeof(v_x) = 'string' then
        v_x := jsonb_build_object('pessoa', v_x #>> '{}');
      end if;
      v_turnos := coalesce(nullif(btrim(v_x ->> 'turnos'), ''), 'dia');
      if v_turnos not in ('dia', 'manha', 'tarde') then
        raise exception 'agenda_rascunho_planejar: turnos "%" inválido (dia, manha ou tarde)', v_turnos using errcode = '22023';
      end if;
      v_rp := public.agenda_resolver_pessoa(v_x ->> 'pessoa', v_autor, p_hoje);
      if v_rp ->> 'status' <> 'ok' then
        return public._agenda_recusa(v_rp ->> 'texto', 'pessoa_' || (v_rp ->> 'status'),
          coalesce((select jsonb_agg(e ->> 'nome' order by o)
                      from jsonb_array_elements(coalesce(v_rp -> 'opcoes', '[]'::jsonb)) with ordinality t(e, o)), '[]'::jsonb));
      end if;
      v_equipe := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_equipe) with ordinality t(e, o)
                             where e ->> 'payee_id' <> v_rp ->> 'payee_id'), '[]'::jsonb)
                  || jsonb_build_array(jsonb_build_object('payee_id', v_rp ->> 'payee_id', 'nome', v_rp ->> 'nome_curto',
                                                          'eh_dono', coalesce((v_rp ->> 'eh_dono')::boolean, false),
                                                          'turnos', v_turnos));
    end loop;
    v_out := v_out || jsonb_build_object('equipe', v_equipe);
  end if;

  if d ? 'dono' then
    if d ->> 'dono' not in ('abre_e_fecha', 'sempre', 'nunca') then
      raise exception 'agenda_rascunho_planejar: dono "%" inválido (abre_e_fecha, sempre ou nunca)', d ->> 'dono' using errcode = '22023';
    end if;
    v_out := v_out || jsonb_build_object('dono', d ->> 'dono');
  end if;

  if d ? 'precisa_ate' then
    v_dt := public._agenda_data_conferida(d ->> 'precisa_ate', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if (v_dt ->> 'ate')::date < p_hoje then
      return public._agenda_recusa(format('"%s" já passou. Até quando o cliente precisa?', btrim(d ->> 'precisa_ate')), 'data_passada');
    end if;
    v_out := v_out || jsonb_build_object('precisa_ate', v_dt ->> 'ate');
  end if;

  -- O bem fora: "fora de 26 a 30/10", "fora até dia 3" (inclusive) ou "só fica livre dia 3" (livre nesse dia).
  if d ? 'bem_fora' then
    v_dt := public._agenda_data_conferida(d ->> 'bem_fora', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if (v_dt ->> 'ate')::date < p_hoje then
      return public._agenda_recusa(format('"%s" já passou. Até quando o bem fica fora?', btrim(d ->> 'bem_fora')), 'data_passada');
    end if;
    v_out := v_out || jsonb_build_object('bem', jsonb_build_object(
      'modo', 'fora', 'de', greatest((v_dt ->> 'de')::date, p_hoje), 'ate', (v_dt ->> 'ate')::date,
      'livre_em', (v_dt ->> 'ate')::date + 1));
  end if;
  if d ? 'bem_livre_em' then
    v_dt := public._agenda_data_conferida(d ->> 'bem_livre_em', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    v_out := v_out || jsonb_build_object('bem', case
      when (v_dt ->> 'de')::date <= p_hoje then jsonb_build_object('modo', 'livre')
      else jsonb_build_object('modo', 'livre_em', 'de', p_hoje, 'ate', (v_dt ->> 'de')::date - 1, 'livre_em', (v_dt ->> 'de')::date) end);
  end if;

  if d ? 'nao_antes_de' then
    v_dt := public._agenda_data_conferida(d ->> 'nao_antes_de', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    v_out := v_out || jsonb_build_object('nao_antes_de', v_dt ->> 'de',
      'nao_antes_motivo', coalesce(left(nullif(btrim(d ->> 'nao_antes_motivo'), ''), 120), 'você disse'));
  elsif d ? 'nao_antes_motivo' then
    return public._agenda_recusa('Não antes de que dia?', 'sem_data');
  end if;

  if d ? 'escopo_em_aberto' then
    v_out := v_out || jsonb_build_object('escopo_em_aberto', nullif(left(btrim(d ->> 'escopo_em_aberto'), 160), ''));
  end if;
  if d ? 'escopo_decidido' then
    v_out := v_out || jsonb_build_object('escopo_decidido', nullif(left(btrim(d ->> 'escopo_decidido'), 160), ''));
    if not d ? 'escopo_em_aberto' then
      -- O que o dono decidiu fecha a pergunta em aberto.
      v_out := v_out || jsonb_build_object('escopo_em_aberto', null);
    end if;
  end if;

  if d ? 'congelar_ate' then
    v_dt := public._agenda_data_conferida(d ->> 'congelar_ate', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if d ? 'revisar_em' then
      v_dt2 := public._agenda_data_conferida(d ->> 'revisar_em', p_trecho, p_hoje, 'futuro');
      if not (v_dt2 ->> 'ok')::boolean then return v_dt2; end if;
    else
      v_dt2 := v_dt;   -- sem data para rever: revê no dia em que a espera acaba
    end if;
    v_out := v_out || jsonb_build_object('congelada_ate', v_dt ->> 'ate', 'revisar_em', v_dt2 ->> 'de');
  elsif d ? 'revisar_em' then
    return public._agenda_recusa('Em espera até quando?', 'sem_data');
  end if;

  if d ? 'prioridade' then
    begin
      v_n := (d ->> 'prioridade')::numeric;
    exception when others then
      v_n := null;
    end;
    if v_n is null or v_n not in (1, 2, 3) then
      raise exception 'agenda_rascunho_planejar: prioridade "%" inválida (1, 2 ou 3)', d ->> 'prioridade' using errcode = '22023';
    end if;
    v_out := v_out || jsonb_build_object('prioridade', v_n::int);
  end if;

  if d ? 'sem_material' then
    v_out := v_out || jsonb_build_object('sem_material', (d ->> 'sem_material')::boolean);
  end if;

  if v_out = '{}'::jsonb then
    return public._agenda_recusa('O que mudou nesse serviço? (quantos dias, quem vai, até quando o cliente precisa…)', 'nada');
  end if;

  select case when public._agenda_normal(coalesce(vs.asset_type, vs.name)) ~ 'motorhome|motor home|trailer'
              then 'o motorhome' else 'o barco' end
    into v_bem
    from public.service_orders so left join public.vessels vs on vs.id = so.vessel_id
   where so.id = v_os;

  v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'planejar', 'planejar:' || v_os::text, v_os,
                                          public._agenda_os_do_rascunho(v_ro) || jsonb_build_object('bem_nome', v_bem) || v_out,
                                          p_trecho, p_hoje);
  return jsonb_build_object('ok', true, 'item', v_txt,
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
end;
$function$;

comment on function public.agenda_rascunho_planejar(uuid, text, text, jsonb, text, date) is
  'Agenda de Produção (Fase 1, P5): o que o dono disse do serviço vira RASCUNHO (nada em os_planejamento). p_dados: dias, com_quem [{pessoa, turnos dia|manha|tarde}], dono (abre_e_fecha|sempre|nunca), precisa_ate, bem_fora, bem_livre_em, nao_antes_de + nao_antes_motivo, escopo_em_aberto, escopo_decidido, congelar_ate + revisar_em, prioridade 1–3, sem_material, aceitar_sugestao. OS e pessoas resolvidas no banco (ambíguo/não achado = pergunta, nada no rascunho); dias e datas têm de estar no trecho; datas por agenda_data_dita. Devolve {ok, item, releitura} ou {ok:false, pergunta, opcoes}.';

create or replace function public.agenda_rascunho_material(p_autor uuid, p_canal text, p_os text, p_itens text[],
                                                           p_situacao text, p_quando text default null,
                                                           p_fornecedor text default null, p_quantidade numeric default null,
                                                           p_novo boolean default false, p_trecho text default null,
                                                           p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor    uuid := public._autor_da_agenda(p_autor);
  v_acao     text;
  v_ro       jsonb;
  v_os       uuid;
  v_cab      jsonb;
  v_itens    jsonb;
  v_crit     jsonb;
  v_total    int;
  v_dt       jsonb;
  v_forn     jsonb;
  v_sit      jsonb;
  v_sel      jsonb := '[]'::jsonb;
  v_item     text;
  v_tok      text[];
  v_esp      text[];
  v_cands    jsonb;
  v_n        int;
  v_x        jsonb;
  v_opc      text[];
  v_lserv    uuid;
  v_textos   text[] := '{}';
  v_dados    jsonb;
  c_vazias   constant text[] := array['o', 'a', 'os', 'as', 'do', 'da', 'de', 'dos', 'das', 'e', 'um', 'uma', 'uns', 'umas',
                                      'no', 'na', 'nos', 'nas', 'pro', 'pra', 'para', 'que', 'esse', 'essa', 'esses', 'essas',
                                      'aquele', 'aquela', 'meu', 'minha', 'ja', 'chegou', 'chegaram', 'comprei', 'ta', 'tao',
                                      'aqui'];
  c_generico constant text[] := array['peca', 'pecas', 'material', 'materiais', 'item', 'itens', 'coisa', 'coisas',
                                      'produto', 'produtos'];
  c_tudo     constant text[] := array['tudo', 'todos', 'todas', 'todo', 'toda'];
begin
  if p_canal is null or p_canal not in ('whatsapp', 'painel') then
    raise exception 'agenda_rascunho_material: canal "%" inválido (whatsapp ou painel)', p_canal using errcode = '22023';
  end if;
  v_acao := case lower(btrim(coalesce(p_situacao, '')))
    when 'comprei' then 'comprado' when 'comprado' then 'comprado'
    when 'a_caminho' then 'a_caminho'
    when 'na_mao' then 'na_mao' when 'chegou' then 'na_mao'
    when 'vou_comprar' then 'vou_comprar' when 'falta' then 'falta' when 'sem_previsao' then 'sem_previsao'
    when 'pode_comecar_sem' then 'pode_comecar_sem' when 'dispensar' then 'dispensar' end;
  if v_acao is null then
    raise exception 'agenda_rascunho_material: situação "%" não existe (comprei, a_caminho, na_mao, vou_comprar, falta, sem_previsao, pode_comecar_sem ou dispensar)',
      p_situacao using errcode = '22023';
  end if;
  if nullif(btrim(p_trecho), '') is null then
    return public._agenda_recusa('Me diga com as suas palavras o que aconteceu com o material.', 'sem_trecho');
  end if;
  if not exists (select 1 from unnest(coalesce(p_itens, '{}'::text[])) i where nullif(btrim(i), '') is not null) then
    return public._agenda_recusa('Qual material? Diga o nome da peça (ou "tudo").', 'sem_item');
  end if;

  v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
  if v_ro ->> 'status' <> 'ok' then
    return public._agenda_recusa_da_os(v_ro);
  end if;
  v_os := (v_ro ->> 'id')::uuid;
  v_cab := public._agenda_os_do_rascunho(v_ro);

  -- A data, conferida no que o dono disse: chegou/comprei olham para trás; chega/vou comprar, para a frente.
  if nullif(btrim(p_quando), '') is not null and v_acao in ('comprado', 'a_caminho', 'na_mao', 'vou_comprar') then
    v_dt := public._agenda_data_conferida(p_quando, p_trecho, p_hoje,
                                          case when v_acao in ('comprado', 'na_mao') then 'passado' else 'futuro' end);
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if v_acao in ('comprado', 'na_mao') and (v_dt ->> 'ate')::date > p_hoje then
      return public._agenda_recusa(format('"%s" ainda não chegou. Quando %s?', btrim(p_quando),
                                          case v_acao when 'na_mao' then 'chegou' else 'comprou' end), 'data_futura');
    end if;
    if v_acao in ('a_caminho', 'vou_comprar') and (v_dt ->> 'ate')::date < p_hoje then
      return public._agenda_recusa(format('"%s" já passou. %s', btrim(p_quando),
                                          case v_acao when 'a_caminho' then 'Chegou?' else 'Quando vai comprar?' end), 'data_passada');
    end if;
  end if;

  if p_quantidade is not null then
    if p_quantidade <= 0 then
      return public._agenda_recusa('Quantas peças?', 'quantidade_invalida');
    end if;
    if not public._agenda_trecho_tem_numero(p_trecho, p_quantidade) then
      return public._agenda_recusa(format('Não achei "%s" no que você disse; me diga de novo quantas.', public._os_material_qtd(p_quantidade)),
                                   'fora_do_trecho');
    end if;
  end if;

  if nullif(btrim(p_fornecedor), '') is not null then
    v_forn := public._agenda_resolver_fornecedor(p_fornecedor);
    if v_forn ->> 'status' = 'ambiguo' then
      return public._agenda_recusa(v_forn ->> 'texto', 'fornecedor_ambiguo', v_forn -> 'opcoes');
    end if;
  end if;

  -- As chaves da situação: cada situação escreve todas as suas (nula quando não vale), para a correção apagar o que a
  -- situação anterior tinha; "pode começar sem" só mexe em critico; o fornecedor só quando foi dito.
  v_sit := case v_acao
    when 'comprado' then jsonb_build_object('acao', 'comprado', 'comprado_em', coalesce((v_dt ->> 'ate')::date, p_hoje),
                                            'chegou_em', null, 'compra_prevista_em', null, 'quantidade_na_mao', null,
                                            'vou_comprar', false)
    when 'a_caminho' then jsonb_build_object('acao', 'a_caminho', 'chegou_em', null, 'compra_prevista_em', null,
                                             'quantidade_na_mao', null, 'vou_comprar', false)
                          || case when v_dt is not null then jsonb_build_object(
                               'previsao_de', case when v_dt ->> 'de' <> v_dt ->> 'ate' then v_dt ->> 'de' end,
                               'previsao_ate', v_dt ->> 'ate') else '{}'::jsonb end
    when 'na_mao' then jsonb_build_object('acao', 'na_mao', 'chegou_em', coalesce((v_dt ->> 'ate')::date, p_hoje),
                                          'compra_prevista_em', null, 'quantidade_na_mao', null, 'vou_comprar', false)
    when 'vou_comprar' then jsonb_build_object('acao', 'falta', 'vou_comprar', true, 'compra_prevista_em', v_dt ->> 'de',
                                               'comprado_em', null, 'previsao_de', null, 'previsao_ate', null,
                                               'chegou_em', null, 'quantidade_na_mao', null)
    when 'falta' then jsonb_build_object('acao', 'falta', 'vou_comprar', false, 'compra_prevista_em', null,
                                         'comprado_em', null, 'previsao_de', null, 'previsao_ate', null, 'chegou_em', null,
                                         'quantidade_na_mao', null)
    when 'sem_previsao' then jsonb_build_object('acao', 'sem_previsao', 'previsao_de', null, 'previsao_ate', null,
                                                'chegou_em', null, 'compra_prevista_em', null, 'quantidade_na_mao', null,
                                                'vou_comprar', false)
    when 'pode_comecar_sem' then jsonb_build_object('critico', false)
    else jsonb_build_object('acao', 'dispensado', 'compra_prevista_em', null, 'vou_comprar', false) end;
  if v_forn is not null then
    v_sit := v_sit || jsonb_build_object('fornecedor_id', case when v_forn ->> 'status' = 'ok' then v_forn ->> 'id' end,
                                         'fornecedor_nome', case when v_forn ->> 'status' = 'novo' then v_forn ->> 'nome' end,
                                         'fornecedor_txt', v_forn ->> 'nome');
  end if;

  -- Os itens da OS como a prontidão vê (conta bruta + os_material), sem sincronizar nada.
  v_itens := coalesce(public.os_prontidao(v_os, p_hoje) #> '{material,itens}', '[]'::jsonb);
  v_crit := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_itens) with ordinality t(e, o)
                       where (e ->> 'critico')::boolean), '[]'::jsonb);
  v_total := jsonb_array_length(v_crit);

  if coalesce(p_novo, false) then
    -- Material fora do orçamento: linha nova do dono, ligada à linha de serviço em que estava embutida quando o nome
    -- casa com uma só linha de texto livre da OS.
    foreach v_item in array p_itens loop
      continue when nullif(btrim(v_item), '') is null;
      v_tok := array(select t from unnest(string_to_array(public._agenda_normal(v_item), ' ')) with ordinality u(t, o)
                      where t <> all (c_vazias) and t <> all (c_generico) order by o);
      v_lserv := null;
      if cardinality(v_tok) > 0 then
        select min(s.id::text)::uuid into v_lserv
          from public.service_order_services s
         where s.service_order_id = v_os and s.service_id is null
           and not exists (select 1 from unnest(v_tok) t
                            where not exists (select 1 from unnest(string_to_array(public._agenda_normal(s.name_snapshot), ' ')) w
                                               where w like t || '%'))
        having count(*) = 1;
      end if;
      v_sel := v_sel || jsonb_build_array(jsonb_build_object(
        'chave', 'material:novo:' || v_os::text || ':' || md5(public._agenda_normal(v_item)),
        'origem', 'dono', 'novo', true, 'vinculo', null, 'linha_id', null,
        'descricao', left(public._agenda_maiuscula(btrim(v_item)), 200), 'quantidade_necessaria', coalesce(p_quantidade, 1),
        'servico_linha', v_lserv,
        'rotulo', public._agenda_linha_curta(public._agenda_maiuscula(btrim(v_item))) || ' (fora do orçamento)'));
    end loop;
  else
    foreach v_item in array p_itens loop
      continue when nullif(btrim(v_item), '') is null;
      v_tok := array(select t from unnest(string_to_array(public._agenda_normal(v_item), ' ')) with ordinality u(t, o)
                      where t <> all (c_vazias) order by o);
      v_esp := array(select t from unnest(v_tok) with ordinality u(t, o) where t <> all (c_generico) and t <> all (c_tudo) order by o);
      if v_tok && c_tudo and cardinality(v_esp) = 0 then
        -- "tudo", "todos os itens": todos os críticos.
        v_cands := v_crit;
        if jsonb_array_length(v_cands) = 0 then
          return public._agenda_recusa(format('O serviço de %s não tem material no orçamento. Se tem peça, me diga qual (é peça nova).',
                                              v_cab ->> 'rotulo_grupo'), 'sem_material');
        end if;
      elsif cardinality(v_esp) = 0 then
        -- "a peça", "o material": a única crítica que ainda não está na mão.
        v_cands := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_crit) with ordinality t(e, o)
                              where e ->> 'nivel' <> 'A'), '[]'::jsonb);
        v_n := jsonb_array_length(v_cands);
        if v_n = 0 then
          return public._agenda_recusa(format('Não tem peça faltando no serviço de %s.', v_cab ->> 'rotulo_grupo'), 'item_nao_achei');
        end if;
        if v_n > 1 then
          v_opc := array(select public._agenda_rotulo_do_item(e ->> 'descricao', null)
                           from jsonb_array_elements(v_cands) with ordinality t(e, o) order by o);
          return public._agenda_recusa(format('Qual peça do %s: %s ou %s?', v_cab ->> 'curto',
                                              array_to_string(v_opc[1:cardinality(v_opc) - 1], ', '), v_opc[cardinality(v_opc)]),
                                       'item_ambiguo', to_jsonb(v_opc));
        end if;
      else
        -- Pelo nome: todo pedaço do que o dono disse começa uma palavra da descrição.
        v_cands := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_itens) with ordinality t(e, o)
                              where not exists (select 1 from unnest(v_esp) tk
                                                 where not exists (select 1 from unnest(string_to_array(
                                                                     public._agenda_normal(e ->> 'descricao'), ' ')) w
                                                                    where w like tk || '%'))), '[]'::jsonb);
        v_n := jsonb_array_length(v_cands);
        if v_n = 0 then
          v_opc := array(select public._agenda_rotulo_do_item(e ->> 'descricao', null)
                           from jsonb_array_elements(v_itens) with ordinality t(e, o) order by o);
          return public._agenda_recusa(format('Não achei "%s" no material de %s. %s Se é peça que não está no orçamento, me diga que é nova.',
                                              btrim(v_item), v_cab ->> 'rotulo_grupo',
                                              case when cardinality(v_opc) = 0 then 'O orçamento não tem peça.'
                                                   else 'Tem: ' || public._agenda_lista(v_opc, 6)
                                                        || case when right(public._agenda_lista(v_opc, 6), 1) = '…' then '' else '.' end end),
                                       'item_nao_achei', to_jsonb(v_opc));
        end if;
        if v_n > 1 then
          v_opc := array(select public._agenda_rotulo_do_item(e ->> 'descricao', v_esp)
                           from jsonb_array_elements(v_cands) with ordinality t(e, o) order by o);
          return public._agenda_recusa(format('Qual "%s" do %s: %s ou %s?', btrim(v_item), v_cab ->> 'curto',
                                              array_to_string(v_opc[1:cardinality(v_opc) - 1], ', '), v_opc[cardinality(v_opc)]),
                                       'item_ambiguo', to_jsonb(v_opc));
        end if;
      end if;
      for v_x in select e from jsonb_array_elements(v_cands) with ordinality t(e, o) order by o loop
        v_dados := jsonb_build_object(
          'chave', case when v_x ->> 'origem' = 'dono' then 'material:dono:' || (v_x ->> 'id')
                        else 'material:' || (v_x ->> 'origem') || ':' || (v_x ->> 'linha') end,
          'origem', v_x ->> 'origem', 'novo', false, 'vinculo', v_x ->> 'linha', 'linha_id', v_x ->> 'id',
          'descricao', v_x ->> 'descricao', 'quantidade_necessaria', (v_x ->> 'quantidade')::numeric,
          'rotulo', public._agenda_rotulo_do_item(v_x ->> 'descricao', v_esp));
        continue when exists (select 1 from jsonb_array_elements(v_sel) s where s ->> 'chave' = v_dados ->> 'chave');
        v_sel := v_sel || jsonb_build_array(v_dados);
      end loop;
    end loop;
  end if;

  if v_acao = 'na_mao' and p_quantidade is not null and jsonb_array_length(v_sel) > 1 then
    return public._agenda_recusa('Me diga a quantidade de uma peça por vez.', 'quantidade_varios');
  end if;

  for v_x in select e from jsonb_array_elements(v_sel) with ordinality t(e, o) order by o loop
    v_dados := v_cab || (v_x - 'chave') || v_sit || jsonb_build_object('total_itens', v_total);
    if v_acao = 'na_mao' and p_quantidade is not null and not coalesce((v_x ->> 'novo')::boolean, false)
       and p_quantidade < (v_x ->> 'quantidade_necessaria')::numeric then
      v_dados := v_dados || jsonb_build_object('quantidade_na_mao', p_quantidade);   -- parcial: o resto continua faltando
    end if;
    v_textos := v_textos || public._agenda_rascunho_salvar(v_autor, p_canal, 'material', v_x ->> 'chave', v_os, v_dados,
                                                          p_trecho, p_hoje);
  end loop;

  return jsonb_build_object('ok', true, 'item', array_to_string(v_textos, E'\n'), 'itens', to_jsonb(v_textos),
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
end;
$function$;

comment on function public.agenda_rascunho_material(uuid, text, text, text[], text, text, text, numeric, boolean, text, date) is
  'Agenda de Produção (Fase 1, P5): o que o dono disse do material vira RASCUNHO (nada em os_material; nem a sincronização roda). Itens pelo nome contra a descrição ("compressor", "Cerbo"), "tudo" = os críticos, "a peça" = a única crítica fora da mão; ambíguo/não achado = pergunta com as opções. Situações: comprei, a_caminho (+ quando = previsão do dono, nível C), na_mao/chegou (chegou_em = a data dita ou hoje; quantidade parcial dita), vou_comprar (+ quando = compra combinada, + fornecedor), falta, sem_previsao, pode_comecar_sem (critico false), dispensar. p_novo = material fora do orçamento (origem dono). Datas e quantidade têm de estar no trecho; fornecedor resolvido (ambíguo = pergunta). Devolve {ok, item, itens, releitura}.';

create or replace function public.agenda_rascunho_disponibilidade(p_autor uuid, p_canal text, p_pessoa text, p_situacao text,
                                                                  p_dias text, p_padrao boolean default false,
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
  v_rp     jsonb;
  v_turno  text;
  v_sit    text;
  v_dias   smallint[];
  v_dt     jsonb;
  v_chave  text;
  v_dados  jsonb;
  v_txt    text;
begin
  if p_canal is null or p_canal not in ('whatsapp', 'painel') then
    raise exception 'agenda_rascunho_disponibilidade: canal "%" inválido (whatsapp ou painel)', p_canal using errcode = '22023';
  end if;
  select x.turno, x.sit into v_turno, v_sit
    from (values ('vem', null, 'disponivel'), ('nao_vem', null, 'indisponivel'),
                 ('so_manha', 'tarde', 'indisponivel'), ('so_tarde', 'manha', 'indisponivel')) x(dito, turno, sit)
   where x.dito = lower(btrim(coalesce(p_situacao, '')));
  if not found then
    raise exception 'agenda_rascunho_disponibilidade: situação "%" não existe (vem, nao_vem, so_manha ou so_tarde)', p_situacao
      using errcode = '22023';
  end if;
  if nullif(btrim(p_trecho), '') is null then
    return public._agenda_recusa('Me diga com as suas palavras quem vem e quando.', 'sem_trecho');
  end if;
  if nullif(btrim(p_dias), '') is null then
    return public._agenda_recusa('Quais dias?', 'sem_dias');
  end if;

  v_rp := public.agenda_resolver_pessoa(p_pessoa, v_autor, p_hoje);
  if v_rp ->> 'status' <> 'ok' then
    return public._agenda_recusa(v_rp ->> 'texto', 'pessoa_' || (v_rp ->> 'status'),
      coalesce((select jsonb_agg(e ->> 'nome' order by o)
                  from jsonb_array_elements(coalesce(v_rp -> 'opcoes', '[]'::jsonb)) with ordinality t(e, o)), '[]'::jsonb));
  end if;

  v_dados := jsonb_build_object(
    'grupo', 'pessoa:' || (v_rp ->> 'payee_id'), 'payee_id', v_rp ->> 'payee_id', 'nome', v_rp ->> 'nome_curto',
    'eh_dono', coalesce((v_rp ->> 'eh_dono')::boolean, false),
    'rotulo_grupo', case when coalesce((v_rp ->> 'eh_dono')::boolean, false) then 'Você' else v_rp ->> 'nome_curto' end,
    'padrao', coalesce(p_padrao, false), 'turno', v_turno, 'situacao', v_sit, 'dito', lower(btrim(p_situacao)));

  if coalesce(p_padrao, false) then
    begin
      v_dias := public.agenda_dias_da_semana_ditos(p_dias);
    exception when sqlstate '22007' then
      return public._agenda_recusa(sqlerrm, 'dias');
    end;
    if not (v_dias::int[] <@ public._agenda_dias_citados(p_trecho)) then
      return public._agenda_recusa(format('Não achei "%s" no que você disse; me diga de novo quais dias.', btrim(p_dias)), 'fora_do_trecho');
    end if;
    v_chave := format('disp:%s:p%s:%s', v_rp ->> 'payee_id', array_to_string(v_dias, ''), coalesce(v_turno, 'dia'));
    v_dados := v_dados || jsonb_build_object('dias_semana', to_jsonb(v_dias));
  else
    v_dt := public._agenda_data_conferida(p_dias, p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if (v_dt ->> 'ate')::date < p_hoje then
      return public._agenda_recusa(format('"%s" já passou. Para quando é?', btrim(p_dias)), 'data_passada');
    end if;
    v_chave := format('disp:%s:d%s_%s:%s', v_rp ->> 'payee_id', greatest((v_dt ->> 'de')::date, p_hoje), v_dt ->> 'ate',
                      coalesce(v_turno, 'dia'));
    v_dados := v_dados || jsonb_build_object('de', greatest((v_dt ->> 'de')::date, p_hoje), 'ate', (v_dt ->> 'ate')::date);
  end if;

  v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'disponibilidade', v_chave, null, v_dados, p_trecho, p_hoje);
  return jsonb_build_object('ok', true, 'item', v_txt,
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
end;
$function$;

comment on function public.agenda_rascunho_disponibilidade(uuid, text, text, text, text, boolean, text, date) is
  'Agenda de Produção (Fase 1, P5): quem vem quando vira RASCUNHO (nada em agenda_disponibilidade). p_situacao vem (disponível), nao_vem (indisponível), so_manha (a tarde indisponível), so_tarde (a manhã indisponível); p_padrao = toda semana (agenda_dias_da_semana_ditos: "segunda a sexta"), senão a data dita (agenda_data_dita, futuro). Pessoa resolvida no banco ("eu" = o sócio do login); os dias têm de estar no trecho. Devolve {ok, item, releitura} ou {ok:false, pergunta}.';

-- ── 7. Aplicar (só pelo *grava*) ────────────────────────────────────────────────────────────────────────

create or replace function public._agenda_aplicar_planejar(p_autor uuid, p_os uuid, p_dados jsonb, p_trecho text, p_hoje date)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  d           jsonb := coalesce(p_dados, '{}'::jsonb);
  v_old       public.os_planejamento%rowtype;
  v_new       public.os_planejamento%rowtype;
  v_eq_antes  jsonb;
  v_eq_depois jsonb;
  v_antes     jsonb := '{}'::jsonb;
  v_depois    jsonb := '{}'::jsonb;
  v_k         text;
begin
  if not exists (select 1 from public.service_orders where id = p_os) then
    raise exception 'o serviço % não existe mais', coalesce(d ->> 'numero', p_os::text) using errcode = 'P0001';
  end if;
  insert into public.os_planejamento (service_order_id) values (p_os) on conflict (service_order_id) do nothing;
  select * into v_old from public.os_planejamento where service_order_id = p_os for update;
  v_new := v_old;

  if d ? 'dias' then
    v_new.dias := (d ->> 'dias')::numeric;
    v_new.estimativa_fonte := d ->> 'estimativa_fonte';
    v_new.estimativa_em := now();
  end if;
  if d ? 'dono' then v_new.dono_presenca := d ->> 'dono'; end if;
  if d ? 'precisa_ate' then v_new.precisa_ate := (d ->> 'precisa_ate')::date; end if;
  if d ? 'bem' then
    v_new.bem_indisponivel := case when d #>> '{bem,modo}' = 'livre' then '{}'::datemultirange
                                   else datemultirange(daterange((d #>> '{bem,de}')::date, (d #>> '{bem,livre_em}')::date, '[)')) end;
  end if;
  if d ? 'nao_antes_de' then
    v_new.nao_antes_de := (d ->> 'nao_antes_de')::date;
    v_new.nao_antes_motivo := d ->> 'nao_antes_motivo';
  end if;
  if d ? 'escopo_em_aberto' then v_new.escopo_em_aberto := d ->> 'escopo_em_aberto'; end if;
  if d ? 'escopo_decidido' then v_new.escopo_decidido := d ->> 'escopo_decidido'; end if;
  if d ? 'congelada_ate' then
    v_new.congelada_ate := (d ->> 'congelada_ate')::date;
    v_new.revisar_em := (d ->> 'revisar_em')::date;
  end if;
  if d ? 'prioridade' then v_new.prioridade_manual := (d ->> 'prioridade')::smallint; end if;
  if d ? 'sem_material' then
    v_new.material_conferido_em := case when (d ->> 'sem_material')::boolean then now() end;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('payee_id', e.payee_id, 'turnos', e.turnos) order by e.payee_id), '[]'::jsonb)
    into v_eq_antes
    from public.os_planejamento_equipe e where e.service_order_id = p_os;
  if d ? 'equipe' then
    delete from public.os_planejamento_equipe where service_order_id = p_os;
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos)
    select p_os, (e ->> 'payee_id')::uuid, e ->> 'turnos' from jsonb_array_elements(d -> 'equipe') e;
    select coalesce(jsonb_agg(jsonb_build_object('payee_id', e.payee_id, 'turnos', e.turnos) order by e.payee_id), '[]'::jsonb)
      into v_eq_depois
      from public.os_planejamento_equipe e where e.service_order_id = p_os;
  else
    v_eq_depois := v_eq_antes;
  end if;

  -- O histórico guarda só o que mudou: {campo: antes} e {campo: depois}.
  for v_k in select key from jsonb_each(to_jsonb(v_new) - array['historico', 'atualizado_em', 'atualizado_por', 'trecho', 'estimativa_em'])
  loop
    if to_jsonb(v_old) -> v_k is distinct from to_jsonb(v_new) -> v_k then
      v_antes := v_antes || jsonb_build_object(v_k, to_jsonb(v_old) -> v_k);
      v_depois := v_depois || jsonb_build_object(v_k, to_jsonb(v_new) -> v_k);
    end if;
  end loop;
  if v_eq_antes is distinct from v_eq_depois then
    v_antes := v_antes || jsonb_build_object('equipe', v_eq_antes);
    v_depois := v_depois || jsonb_build_object('equipe', v_eq_depois);
  end if;

  update public.os_planejamento
     set dias = v_new.dias, estimativa_fonte = v_new.estimativa_fonte, estimativa_em = v_new.estimativa_em,
         dono_presenca = v_new.dono_presenca, precisa_ate = v_new.precisa_ate, bem_indisponivel = v_new.bem_indisponivel,
         nao_antes_de = v_new.nao_antes_de, nao_antes_motivo = v_new.nao_antes_motivo,
         escopo_em_aberto = v_new.escopo_em_aberto, escopo_decidido = v_new.escopo_decidido,
         congelada_ate = v_new.congelada_ate, revisar_em = v_new.revisar_em, prioridade_manual = v_new.prioridade_manual,
         material_conferido_em = v_new.material_conferido_em,
         trecho = public._agenda_corta(p_trecho, 500),
         historico = public._os_material_historico(v_old.historico, jsonb_build_object(
           'em', p_hoje, 'autor', p_autor, 'trecho', public._agenda_corta(p_trecho, 500), 'antes', v_antes, 'depois', v_depois)),
         atualizado_em = now(), atualizado_por = p_autor
   where service_order_id = p_os;
  return jsonb_build_object('antes', v_antes, 'depois', v_depois);
end;
$function$;

comment on function public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date) is
  'Agenda de Produção (Fase 1, P5): grava em os_planejamento (e os_planejamento_equipe) uma linha de rascunho planejar — só os campos ditos; a equipe dita substitui a anterior. Histórico {em, autor, trecho, antes, depois} com só o que mudou (os 20 mais novos). Só pelo agenda_rascunho_gravar; só service_role.';

create or replace function public._agenda_aplicar_material(p_autor uuid, p_os uuid, p_dados jsonb, p_trecho text, p_hoje date)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  d      jsonb := coalesce(p_dados, '{}'::jsonb);
  v_old  public.os_material%rowtype;
  v_new  public.os_material%rowtype;
  v_req  numeric;
  v_vinc uuid := (d ->> 'vinculo')::uuid;
begin
  if coalesce((d ->> 'novo')::boolean, false) then
    insert into public.os_material (service_order_id, service_order_service_id, origem, descricao, quantidade_necessaria,
                                    situacao, historico)
    values (p_os, (d ->> 'servico_linha')::uuid, 'dono', left(d ->> 'descricao', 200),
            coalesce((d ->> 'quantidade_necessaria')::numeric, 1), 'falta', '[]'::jsonb)
    returning * into v_old;
  elsif d ->> 'origem' = 'dono' then
    select * into v_old from public.os_material where id = (d ->> 'linha_id')::uuid and service_order_id = p_os for update;
    if not found then
      raise exception '"%" saiu do serviço', d ->> 'rotulo' using errcode = 'P0001';
    end if;
  else
    select m.* into v_old
      from public.os_material m
     where m.service_order_id = p_os and m.origem = d ->> 'origem'
       and v_vinc = case m.origem when 'peca' then m.service_order_part_id
                                  when 'texto_livre' then m.service_order_service_id
                                  else m.purchase_order_item_id end
     for update;
    if not found then
      -- Linha que a sincronização não cria (item de OC que já chegou): nasce aqui, pelo vínculo, se ainda for da OS.
      if not (case d ->> 'origem'
                when 'peca' then exists (select 1 from public.service_order_parts x where x.id = v_vinc and x.service_order_id = p_os)
                when 'texto_livre' then exists (select 1 from public.service_order_services x where x.id = v_vinc and x.service_order_id = p_os)
                when 'oc' then exists (select 1 from public.purchase_order_items x join public.purchase_orders po on po.id = x.purchase_order_id
                                        where x.id = v_vinc and po.service_order_id = p_os)
                else false end) then
        raise exception '"%" saiu do serviço', d ->> 'rotulo' using errcode = 'P0001';
      end if;
      insert into public.os_material (service_order_id, service_order_part_id, service_order_service_id, purchase_order_item_id,
                                      origem, descricao, quantidade_necessaria, situacao, historico)
      values (p_os,
              case when d ->> 'origem' = 'peca' then v_vinc end,
              case when d ->> 'origem' = 'texto_livre' then v_vinc end,
              case when d ->> 'origem' = 'oc' then v_vinc end,
              d ->> 'origem', left(coalesce(d ->> 'descricao', 'Material'), 200),
              coalesce((d ->> 'quantidade_necessaria')::numeric, 1), 'falta', '[]'::jsonb)
      returning * into v_old;
    end if;
  end if;

  v_new := v_old;
  v_req := v_old.quantidade_necessaria;
  if d ? 'acao' then
    v_new.fonte := 'dono';
    case d ->> 'acao'
      when 'na_mao' then
        if d ->> 'quantidade_na_mao' is not null and (d ->> 'quantidade_na_mao')::numeric < v_req then
          -- Parcial: o que chegou fica guardado e a situação continua a de antes (o resto ainda falta).
          v_new.quantidade_na_mao := (d ->> 'quantidade_na_mao')::numeric;
          if v_new.situacao in ('na_mao', 'dispensado') then
            v_new.situacao := 'falta';
            v_new.chegou_em := null;
          end if;
        else
          v_new.situacao := 'na_mao';
          v_new.quantidade_na_mao := v_req;
          v_new.chegou_em := (d ->> 'chegou_em')::date;
          v_new.compra_prevista_em := null;
        end if;
      when 'comprado' then
        v_new.situacao := 'comprado';
        v_new.comprado_em := (d ->> 'comprado_em')::date;
        v_new.chegou_em := null;
        v_new.compra_prevista_em := null;
        if d ->> 'previsao_ate' is not null then
          v_new.previsao_de := (d ->> 'previsao_de')::date;
          v_new.previsao_ate := (d ->> 'previsao_ate')::date;
          v_new.previsao_fonte := 'dono';
          v_new.previsao_original := coalesce(v_old.previsao_original, v_new.previsao_ate);
        end if;
      when 'a_caminho' then
        v_new.situacao := 'a_caminho';
        v_new.chegou_em := null;
        v_new.compra_prevista_em := null;
        if d ->> 'comprado_em' is not null then v_new.comprado_em := (d ->> 'comprado_em')::date; end if;
        if d ->> 'previsao_ate' is not null then
          v_new.previsao_de := (d ->> 'previsao_de')::date;
          v_new.previsao_ate := (d ->> 'previsao_ate')::date;
          v_new.previsao_fonte := 'dono';
          v_new.previsao_original := coalesce(v_old.previsao_original, v_new.previsao_ate);
        end if;
      when 'sem_previsao' then
        v_new.situacao := 'comprado';
        v_new.previsao_de := null;
        v_new.previsao_ate := null;
        v_new.previsao_fonte := null;
        v_new.chegou_em := null;
        v_new.compra_prevista_em := null;
      when 'falta' then
        v_new.situacao := 'falta';
        v_new.compra_prevista_em := (d ->> 'compra_prevista_em')::date;
        v_new.comprado_em := null;
        v_new.previsao_de := null;
        v_new.previsao_ate := null;
        v_new.previsao_fonte := null;
        v_new.chegou_em := null;
      when 'dispensado' then
        v_new.situacao := 'dispensado';
        v_new.compra_prevista_em := null;
      else
        raise exception 'situação "%" desconhecida no rascunho', d ->> 'acao' using errcode = 'P0001';
    end case;
    -- Fora de "na mão" e de "dispensado", a quantidade na mão é só a parcial (a completa voltou a faltar).
    if v_new.situacao not in ('na_mao', 'dispensado') and v_new.quantidade_na_mao >= v_req then
      v_new.quantidade_na_mao := 0;
    end if;
  end if;
  if d ? 'critico' then
    v_new.critico := (d ->> 'critico')::boolean;
  end if;
  if d ? 'fornecedor_id' or d ? 'fornecedor_nome' then
    v_new.fornecedor_id := (d ->> 'fornecedor_id')::uuid;
    v_new.fornecedor_nome := left(d ->> 'fornecedor_nome', 80);
  end if;

  update public.os_material
     set situacao = v_new.situacao, fonte = v_new.fonte, quantidade_na_mao = v_new.quantidade_na_mao,
         critico = v_new.critico, fornecedor_id = v_new.fornecedor_id, fornecedor_nome = v_new.fornecedor_nome,
         compra_prevista_em = v_new.compra_prevista_em, comprado_em = v_new.comprado_em,
         previsao_de = v_new.previsao_de, previsao_ate = v_new.previsao_ate, previsao_original = v_new.previsao_original,
         previsao_fonte = v_new.previsao_fonte, chegou_em = v_new.chegou_em,
         trecho = public._agenda_corta(p_trecho, 300), conferido_em = now(),
         historico = public._os_material_historico(v_old.historico, jsonb_build_object(
           'em', p_hoje, 'de', case when coalesce((d ->> 'novo')::boolean, false) then null else v_old.situacao end,
           'para', v_new.situacao, 'por', 'dono', 'autor', p_autor, 'trecho', public._agenda_corta(p_trecho, 300),
           'nota', d ->> 'frase')),
         atualizado_em = now(), atualizado_por = p_autor
   where id = v_old.id;
  return jsonb_build_object('linha', v_old.id, 'de', v_old.situacao, 'para', v_new.situacao);
end;
$function$;

comment on function public._agenda_aplicar_material(uuid, uuid, jsonb, text, date) is
  'Agenda de Produção (Fase 1, P5): grava em os_material uma linha de rascunho material — acha a linha pelo vínculo (ou cria: material novo do dono, item de OC que a sincronização não cria), aplica a situação dita (fonte dono; previsão do dono com previsao_original na 1ª; na mão com a quantidade completa ou a parcial), critico e fornecedor; histórico {em, de, para, por dono, autor, trecho, nota}. Só pelo agenda_rascunho_gravar; só service_role.';

create or replace function public._agenda_aplicar_disponibilidade(p_autor uuid, p_dados jsonb, p_trecho text, p_hoje date)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  d       jsonb := coalesce(p_dados, '{}'::jsonb);
  v_payee uuid := (d ->> 'payee_id')::uuid;
  v_per   daterange;
  v_id    uuid;
begin
  if not exists (select 1 from public.payees where id = v_payee) then
    raise exception '% não está mais no cadastro', coalesce(d ->> 'nome', 'a pessoa') using errcode = 'P0001';
  end if;
  if coalesce((d ->> 'padrao')::boolean, false) then
    insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, trecho, criado_por)
    values (v_payee, array(select jsonb_array_elements_text(d -> 'dias_semana')::smallint), d ->> 'turno', d ->> 'situacao',
            'dono', format('você disse em %s', to_char(p_hoje, 'DD/MM')), public._agenda_corta(p_trecho, 300), p_autor)
    returning id into v_id;
  else
    v_per := daterange((d ->> 'de')::date, (d ->> 'ate')::date, '[]');
    -- A mesma data e o mesmo turno ditos de novo trocam o que o dono tinha dito antes (fica o rastro).
    update public.agenda_disponibilidade
       set substituida_em = now()
     where payee_id = v_payee and substituida_em is null and origem = 'dono' and periodo = v_per
       and turno is not distinct from d ->> 'turno';
    insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, trecho, criado_por)
    values (v_payee, v_per, d ->> 'turno', d ->> 'situacao', 'dono', format('você disse em %s', to_char(p_hoje, 'DD/MM')),
            public._agenda_corta(p_trecho, 300), p_autor)
    returning id into v_id;
  end if;
  return jsonb_build_object('linha', v_id);
end;
$function$;

comment on function public._agenda_aplicar_disponibilidade(uuid, jsonb, text, date) is
  'Agenda de Produção (Fase 1, P5): grava em agenda_disponibilidade uma linha de rascunho disponibilidade (origem dono): padrão por dia da semana (a troca dos padrões vigentes é feita uma vez pelo agenda_rascunho_gravar) ou exceção por data (a mesma data e turno ditos antes ganham substituida_em). Só pelo agenda_rascunho_gravar; só service_role.';

-- ── 8. O *grava* e o *descarta* ─────────────────────────────────────────────────────────────────────────

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
begin
  perform pg_advisory_xact_lock(hashtext('agenda_rascunho:' || v_autor::text));

  -- O que passou da validade não grava (e fica marcado, mesmo se o resto falhar).
  with e as (
    update public.agenda_rascunho set estado = 'expirado'
     where autor = v_autor and estado = 'aberto' and expira_em <= now()
    returning criado_em)
  select count(*), max((e.criado_em at time zone 'America/Sao_Paulo')::date) into v_exp, v_exp_dia from e;

  select coalesce(array_agg(r.id order by (r.dados ->> 'ordem')::int, r.criado_em, r.id), '{}'),
         coalesce(array_agg(distinct r.service_order_id) filter (where r.tipo = 'material'), '{}')
    into v_ids, v_oss_mat
    from public.agenda_rascunho r
   where r.autor = v_autor and r.estado = 'aberto';

  if cardinality(v_ids) = 0 then
    return jsonb_build_object('ok', true, 'gravados', 0, 'expirados', v_exp,
      'texto', case when v_exp > 0 then format('A releitura de %s expirou; me diga de novo o que mudou.', public._dia_curto(v_exp_dia))
                    else 'Não tenho nada esperando para gravar.' end);
  end if;

  -- Tudo ou nada: um item que não passa desfaz o lote inteiro (as linhas continuam abertas para corrigir).
  begin
    foreach v_x in array v_oss_mat loop
      perform public.os_material_sincronizar(v_x, p_hoje);   -- as linhas espelho existem antes do fato
    end loop;

    -- O padrão novo de uma pessoa troca os padrões dela (do histórico e do dono) UMA vez, antes de entrar o lote.
    update public.agenda_disponibilidade a
       set substituida_em = now()
     where a.substituida_em is null and a.dias_semana is not null and a.origem in ('historico', 'dono')
       and a.payee_id in (select (r.dados ->> 'payee_id')::uuid from public.agenda_rascunho r
                           where r.id = any (v_ids) and r.tipo = 'disponibilidade' and (r.dados ->> 'padrao')::boolean);

    foreach v_x in array v_ids loop
      select * into v_r from public.agenda_rascunho where id = v_x for update;
      v_item := v_r.texto;
      case v_r.tipo
        when 'planejar' then
          perform public._agenda_aplicar_planejar(v_autor, v_r.service_order_id, v_r.dados, v_r.trecho, p_hoje);
        when 'material' then
          perform public._agenda_aplicar_material(v_autor, v_r.service_order_id, v_r.dados, v_r.trecho, p_hoje);
        else
          perform public._agenda_aplicar_disponibilidade(v_autor, v_r.dados, v_r.trecho, p_hoje);
      end case;
      update public.agenda_rascunho set estado = 'gravado', gravado_em = now() where id = v_x;
      v_n := v_n + 1;
    end loop;

    foreach v_x in array v_oss_mat loop
      perform public.os_material_sincronizar(v_x, p_hoje);
    end loop;
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
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
     where r.id = any (v_ids)
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
    'texto', 'Gravado. Agora:' || E'\n' || array_to_string(v_linhas, E'\n')
             || case when v_exp > 0 then E'\n' || format('(A releitura de %s tinha expirado e não foi gravada.)', public._dia_curto(v_exp_dia))
                     else '' end);
end;
$function$;

comment on function public.agenda_rascunho_gravar(uuid, date) is
  'Agenda de Produção (Fase 1, P5): o *grava* do dono — numa transação, tudo ou nada: marca expirado o que passou da validade; sincroniza o material das OS do lote; troca UMA vez os padrões de disponibilidade das pessoas com padrão novo; aplica cada linha aberta (_agenda_aplicar_planejar/_material/_disponibilidade) e marca gravado; sincroniza de novo. Devolve {ok, gravados, expirados, texto "Gravado. Agora:" + uma linha por OS (estado da prontidão) e por pessoa}; item que não passa: {ok:false, texto "Não gravei nada: …", erro} e nada muda. Chamada só pelo comando sem IA "grava" (P6), nunca por ferramenta do modelo.';

create or replace function public.agenda_rascunho_descartar(p_autor uuid)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor uuid := public._autor_da_agenda(p_autor);
  v_n     int;
begin
  with e as (
    update public.agenda_rascunho set estado = 'descartado'
     where autor = v_autor and estado = 'aberto'
    returning id)
  select count(*) into v_n from e;
  return jsonb_build_object('ok', true, 'descartados', v_n,
    'texto', case when v_n > 0 then 'Descartei. Nada foi gravado.' else 'Não tinha nada esperando para gravar.' end);
end;
$function$;

comment on function public.agenda_rascunho_descartar(uuid) is
  'Agenda de Produção (Fase 1, P5): o *descarta* do dono — marca descartado o lote aberto. "Descartei. Nada foi gravado."';

-- ── Portas ──────────────────────────────────────────────────────────────────────────────────────────────
-- As RPCs do rascunho: security definer, conferem o cargo (_autor_da_agenda); authenticated (painel) e service_role
-- (WhatsApp). Nunca anon.
revoke all on function
  public.agenda_rascunho_planejar(uuid, text, text, jsonb, text, date),
  public.agenda_rascunho_material(uuid, text, text, text[], text, text, text, numeric, boolean, text, date),
  public.agenda_rascunho_disponibilidade(uuid, text, text, text, text, boolean, text, date),
  public.agenda_rascunho_ler(uuid, date), public.agenda_rascunho_gravar(uuid, date), public.agenda_rascunho_descartar(uuid)
  from public, anon;
grant execute on function
  public.agenda_rascunho_planejar(uuid, text, text, jsonb, text, date),
  public.agenda_rascunho_material(uuid, text, text, text[], text, text, text, numeric, boolean, text, date),
  public.agenda_rascunho_disponibilidade(uuid, text, text, text, text, boolean, text, date),
  public.agenda_rascunho_ler(uuid, date), public.agenda_rascunho_gravar(uuid, date), public.agenda_rascunho_descartar(uuid)
  to authenticated, service_role;

-- As internas (o cargo, as guardas, os textos, o salvar e os três aplicar): só service_role. As RPCs acima as chamam
-- como dono das funções.
revoke all on function
  public._autor_da_agenda(uuid), public._agenda_trecho_tem(text, text), public._agenda_trecho_tem_numero(text, numeric),
  public._agenda_recusa(text, text, jsonb), public._agenda_data_conferida(text, text, date, text),
  public._agenda_dias_citados(text), public._agenda_dias_semana_texto(smallint[]), public._agenda_quando_texto(date, date),
  public._agenda_recusa_da_os(jsonb), public._agenda_os_do_rascunho(jsonb), public._agenda_resolver_fornecedor(text),
  public._agenda_rotulo_do_item(text, text[]), public._agenda_rascunho_frase(text, jsonb),
  public._agenda_rascunho_salvar(uuid, text, text, text, uuid, jsonb, text, date),
  public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date), public._agenda_aplicar_material(uuid, uuid, jsonb, text, date),
  public._agenda_aplicar_disponibilidade(uuid, jsonb, text, date)
  from public, anon, authenticated;
grant execute on function
  public._autor_da_agenda(uuid), public._agenda_trecho_tem(text, text), public._agenda_trecho_tem_numero(text, numeric),
  public._agenda_recusa(text, text, jsonb), public._agenda_data_conferida(text, text, date, text),
  public._agenda_dias_citados(text), public._agenda_dias_semana_texto(smallint[]), public._agenda_quando_texto(date, date),
  public._agenda_recusa_da_os(jsonb), public._agenda_os_do_rascunho(jsonb), public._agenda_resolver_fornecedor(text),
  public._agenda_rotulo_do_item(text, text[]), public._agenda_rascunho_frase(text, jsonb),
  public._agenda_rascunho_salvar(uuid, text, text, text, uuid, jsonb, text, date),
  public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date), public._agenda_aplicar_material(uuid, uuid, jsonb, text, date),
  public._agenda_aplicar_disponibilidade(uuid, jsonb, text, date)
  to service_role;
