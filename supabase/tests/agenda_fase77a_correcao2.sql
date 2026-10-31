-- Prova da correção 2 da Fase 7a (migration 20261031100985): o que a 2ª revisão da etapa achou e o cético confirmou, sobre a carteira
-- REAL de qui 29/10 (o replay; a presença do dono do Lenine e do Vanderlei como em produção: abre e fecha), com e sem a equipe de 30/10
-- (Roberto, João e Mickael fora; o Alex declarado pelo dono e na rotina, sem telefone — como em produção). Cada bloco diz o achado.
-- bancada: depende de 20261031100985
--
--   Y0  as portas das 4 funções novas
--   Y1  (o corte de 1.000 e o desempate) a linha das perguntas do gestor com prazo vai com perda 76; a sem prazo diz o porquê
--   Y2  (a dupla sem a 2ª pessoa) com o Alex sozinho: a palavra diz quem está e o que fazer, a OS espera o dono (classe 4 dupla, "falta a
--       2ª pessoa" no aviso), o foco avisa antes; com a 2ª pessoa na grade, o de antes
--   Y3  (a ficha prometida a quem não tem telefone) o gestor só pergunta a ficha de quem a recebe; a ficha segurada diz o porquê
--   Y4  (idem) a pergunta da ficha liberada fecha com o que houve no registro ("… mas ela não saiu (sem telefone no cadastro)")
--   Y5  (o dono "sempre" não é o técnico) a marina nova leva o técnico e o dono junto; o diagnóstico continua com o dono; com a linha
--       do dono, a Kalmar OS-00033 é marcada com o Alex
--   Y6  (o *desfaz* até a OS mudar) a reserva automática depois do *desfaz* não solta a trava; a ação do dono solta; o foco diz
--       "você desfez"
--   Y7  (acima de 8 diárias) a 3ª opção "Já terminou"; a pergunta sem prazo que venceu volta; o foco com o número da OS que se repete
--   Y8  (o "compre até" da OS que a vigia tirou do plano) o empurrão conta uma vez por saída, a cobrança continua e as compras do
--       fechamento a mantêm (perda 80)
--   Y9  (o aviso) o prazo das perguntas do gestor que ele conta como vistas; a frase do gestor com ponto e sem repetir a pergunta
--   Y10 (a OS em duas linhas) o estimar e a marcação da mesma OS no mesmo aviso: um *desfaz* só
--   Y11 (a parada) o planejamento que o dono mexeu conta como mexida
--   Y12 (as três correções da 1ª revisão sem teste vermelho) o aviso conta as perguntas do gestor como vistas (achado 15), a suposição
--       sem pergunta não vira linha vazia no aprontar (achado 24), o encaixe não marca de novo o que o dono desfez (achado 17)
--   Y13 (as do lote de 30/10 mudadas no lugar pela 100980) _agenda_aviso_mudancas e _agenda_aviso_fora_texto com o gestor desligado:
--       a saída da definição de 20261030100300, byte a byte
--   Y14 as recriadas de antes da 7a: sem os blocos da Fase 7, o corpo de antes da 7a, byte a byte
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono: Y0 e Y14 leem; o resto usa o replay e só roda na bancada
--   (fora dela sai PULADO). Termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$
  select p.id from public.payees p where p.name = p_nome order by p.id limit 1
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
create function pg_temp.replay(p_modo text) returns void language plpgsql as $f$
begin
  if coalesce(current_setting('agenda_teste.ja_replay', true), '') <> 'on' then
    execute current_setting('agenda_teste.replay2910');
    insert into public.os_planejamento (service_order_id, dono_presenca)
    select so.id, 'abre_e_fecha' from public.service_orders so where so.service_order_number in ('OS-00074', 'OS-00069')
    on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';
    perform set_config('agenda_teste.ja_replay', 'on', true);
  end if;
  update public.agenda_config
     set modo_marcar_sozinho = p_modo, modo_encaixe_aprovacao = p_modo, modo_revisao_diaria = p_modo, modo_compre_ate = p_modo,
         modo_vaga_fechamento = p_modo, gestor_so_propor = false, gestor_so_propor_em = null,
         marcar_sozinho_desde = case when p_modo = 'ligado' then timestamptz '2026-10-29 16:46-03' end,
         marcar_regras = '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}'
   where id;
end $f$;
-- a equipe de 30/10 como está em produção: Roberto, João e Mickael saem; o Alex, declarado pelo dono, todo dia útil, na rotina da
-- equipe (agenda_equipe_contato, incluido_por dono) e sem telefone
create function pg_temp.equipe_3010() returns void language plpgsql as $f$
begin
  update public.agenda_disponibilidade set substituida_em = timestamptz '2026-10-29 21:30-03' where substituida_em is null
     and payee_id in (select id from public.payees where name in ('Roberto', 'João', 'Mickael'));
  update public.agenda_equipe_contato set recebe_rotina = false, parou_em = timestamptz '2026-10-29 21:30-03',
         parou_motivo = 'saiu da equipe (o dono, 29/10)'
   where payee_id in (select id from public.payees where name in ('Roberto', 'João', 'Mickael')) and parou_em is null;
  insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, trecho)
  select p.id, '{1,2,3,4,5}'::smallint[], null, 'disponivel', 'dono', 'você disse em 29/10', 'Alex todo dia útil'
    from public.payees p where p.name = 'Alex';
  insert into public.agenda_equipe_contato (payee_id, incluido_por, recebe_rotina)
  select p.id, 'dono', true from public.payees p where p.name = 'Alex'
  on conflict (payee_id) do update set recebe_rotina = true, parou_em = null, parou_motivo = null;
end $f$;
create function pg_temp.marcar(p_os uuid[], p_hoje date, p_agora timestamptz) returns jsonb language plpgsql as $f$
declare
  v_p jsonb;
begin
  v_p := public.agenda_propor('os', null, null, p_os, '{}'::jsonb, true, 'vigia', null, p_hoje, p_agora);
  return public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'vigia', null, null, p_hoje, p_agora);
end $f$;
create function pg_temp.dias(p_os uuid, p_de date) returns text language sql stable as $f$
  select coalesce(string_agg(distinct to_char(a.dia, 'DD/MM'), ',' order by to_char(a.dia, 'DD/MM')), '-')
    from public.agenda_alocacoes a
   where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_de
$f$;
-- O corpo de uma função numa migration (o texto entre "as $function$" e "$function$") e sem os blocos da Fase 7.
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;'));
end $f$;
create function pg_temp.sem_fase7(p_corpo text) returns text language plpgsql as $f$
declare
  v_b text[] := '{}'; v_bloco boolean := false; l text;
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    if not v_bloco and l ~ '^\s*-- FASE 7:' and l !~ '^\s*-- FASE 7: fim' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- FASE 7: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return array_to_string(v_b, E'\n');
end $f$;

-- ── Y0. As portas das 4 funções novas ─────────────────────────────────────────────────────────────────────
with f(sig, porta) as (values
  ('public._agenda_equipe_tem_telefone(uuid)', 'ninguem'),
  ('public._agenda_gestor_compra_saiu(date)', 'ninguem'),
  ('public._agenda_tecnicos_da_grade(date)', 'leitura'),
  ('public._agenda_tecnicos_frase(text[])', 'leitura'))
insert into _resultado
select 'Y0 as portas: o telefone e as OS que saíram pelo material para ninguém (nem o service_role); os técnicos da grade e a frase para authenticated e service_role; nunca anon; invoker, search_path fixo',
       count(p.oid) = 4
       and bool_and(p.oid is not null and not has_function_privilege('anon', p.oid, 'execute') and not p.prosecdef
                    and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%'
                    and case f.porta
                          when 'leitura' then has_function_privilege('authenticated', p.oid, 'execute')
                                              and has_function_privilege('service_role', p.oid, 'execute')
                          else not has_function_privilege('authenticated', p.oid, 'execute')
                               and not has_function_privilege('service_role', p.oid, 'execute') end),
       coalesce(string_agg(f.sig, ', ') filter (where p.oid is null or p.prosecdef or has_function_privilege('anon', p.oid, 'execute')), 'todas')
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);

-- ── Y14. As recriadas de antes da 7a: sem os blocos da Fase 7, o corpo de antes da 7a ─────────────────────────
do $copias$
declare
  v_me   text := coalesce(current_setting('agenda_teste.mig_correcao2_fase7a', true), '');
  v_novo text;
  v_dif  text;
  r      record;
begin
  if v_me = '' then
    insert into _resultado values ('Y14 as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
    return;
  end if;
  for r in select * from (values
      ('agenda_meios_da_os', 'public.agenda_meios_da_os(uuid, date)', 'agenda_teste.mig_motor_fase2'),
      ('_agenda_classe_da_os', 'public._agenda_classe_da_os(jsonb, jsonb, date, boolean, boolean)', 'agenda_teste.mig_motor_fase2'),
      ('_agenda_rotina_ficha', 'public._agenda_rotina_ficha(date, timestamptz)', 'agenda_teste.mig_equipe_fase3'),
      ('agenda_aviso_pecas', 'public.agenda_aviso_pecas(date, timestamptz)', 'agenda_teste.mig_correcao_revisao'),
      ('_agenda_linhas_do_fechamento', 'public._agenda_linhas_do_fechamento(date)', 'agenda_teste.mig_correcao_revisao'),
      ('_agenda_aprontar_de', 'public._agenda_aprontar_de(jsonb, integer)', 'agenda_teste.mig_leituras_fase1')
    ) t(nome, assinatura, guc)
  loop
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = r.assinatura::regprocedure;
    if coalesce(current_setting(r.guc, true), '') = '' or pg_temp.corpo(current_setting(r.guc, true), r.nome) = ''
       or pg_temp.sem_fase7(v_novo) <> pg_temp.corpo(current_setting(r.guc, true), r.nome)
       or position(format('create or replace function public.%s(', r.nome) in v_me) = 0
       or position('(7a correção 2' in pg_temp.inteira(v_me, r.nome)) = 0 then
      v_dif := concat_ws(', ', v_dif, r.nome);
    end if;
  end loop;
  insert into _resultado values ('Y14 as 6 recriadas de antes da 7a (os meios-dias, a classe, a rotina da ficha, o aviso, as linhas do fechamento e o aprontar): recriadas pela correção 2 com a mudança marcada, e sem os blocos da Fase 7 o corpo de antes da 7a, byte a byte',
    v_dif is null, coalesce(v_dif, 'todas'));
end
$copias$;

-- ── Y1 a Y13. Com o replay ───────────────────────────────────────────────────────────────────────────────
do $y$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2026-10-29';
  c_sex  constant date := date '2026-10-30';
  c_ter  constant date := date '2026-11-03';
  c_qua  constant date := date '2026-11-04';
  v_adm  uuid;
  v_len  uuid;
  v_van  uuid;
  v_nel  uuid;
  v_gia  uuid;
  v_k32  uuid;
  v_k33  uuid;
  v_r96  uuid;
  v_alex uuid;
  v_dono uuid;
  v_a    uuid;
  v_q    uuid;
  v_q2   uuid;
  v_t    text;
  v_t2   text;
  v_t3   text;
  v_t4   text;
  v_n    int;
  v_n2   int;
  r      jsonb;
  r2     jsonb;
  r3     jsonb;
  x      jsonb;
  v_lin  jsonb;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('Y1–Y13 (o replay de 29/10)', true, 'PULADO: sem agenda_teste.replay2910 (rode pela bancada)');
    return;
  end if;
  perform pg_temp.replay('ligado');
  select u.id into v_adm from public.app_users u where u.role = 'admin' order by u.id limit 1;
  -- o dono recebe o aviso (o _agenda_aviso_dono de produção: o admin com o WhatsApp do assistente)
  update public.app_users set ai_whatsapp_enabled = true, phone_normalized = '5547900000210' where id = v_adm;
  v_len := pg_temp.os('OS-00074');
  v_van := pg_temp.os('OS-00069');
  v_nel := pg_temp.os('OS-00112');
  v_gia := pg_temp.os('OS-00130');
  v_k32 := pg_temp.os('OS-00032');
  v_k33 := pg_temp.os('OS-00033');
  v_r96 := pg_temp.os('OS-00096');
  v_alex := pg_temp.pessoa('Alex');
  v_dono := public._agenda_dono(null);

  -- ── Y1. A linha das perguntas do gestor ganha o desempate (o corte de 1.000 e as vagas; os achados 15/18 de novo) ──
  begin
    perform public.agenda_gestor_rodar(c_sex, pg_temp.em(c_sex, '16:53'));
    v_lin := public._agenda_linhas_do_fechamento(c_sex);
    x := (select l from jsonb_array_elements(v_lin) l where l ->> 'tipo' = 'pergunta' and l ? 'pergunta_ids' limit 1);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Y1a a linha das perguntas do gestor com prazo vai com perda 76 (entre as que perdem hoje, ganha o desempate: antes 75 com a mensagem ao cliente, e saía primeiro no corte de 1.000 pelo tipo); a sem prazo diz o porquê ("Espero você (não marco sozinho): Giancarlo (OS-00130).")',
    (x ->> 'perda')::int = 76 and x ->> 'texto' like '%Espero você (não marco sozinho): Giancarlo (OS-00130).%'
    and x ->> 'texto' not like '%Espero você: %',
    coalesce(x::text, '-'));
  v_res := pg_temp.ok(v_res, 'Y1b a mesma linha leva a forma curta (texto_curto), com as mesmas perguntas, para o Secretário cheio: "Agenda: Sem resposta até ter 03/11 18:00, conto: Nelson (OS-00112) 4 dias; … Espero você (não marco sozinho): Giancarlo (OS-00130)." — a inteira (~400) não cabia com os 3 que ficaram de hoje',
    x ->> 'texto_curto' like 'Agenda: Sem resposta até ter 03/11 18:00, conto: %'
    and x ->> 'texto_curto' like '%Nelson (OS-00112) 4 dias%'
    and x ->> 'texto_curto' like '%Espero você (não marco sozinho): Giancarlo (OS-00130).'
    and char_length(x ->> 'texto_curto') < char_length(x ->> 'texto') and char_length(x ->> 'texto_curto') <= 300
    -- (e a forma curta vai dentro da linha: nenhum item da lista sem tipo)
    and not exists (select 1 from jsonb_array_elements(v_lin) l where not l ? 'tipo'),
    coalesce(x ->> 'texto_curto', '-') || ' | ' || coalesce(char_length(x ->> 'texto_curto')::text, '-'));

  -- ── Y2. A dupla sem a 2ª pessoa (AG7-04, fase7-padroes) ──
  begin
    perform pg_temp.equipe_3010();
    perform pg_temp.marcar(array[v_len], c_sex, pg_temp.em(c_sex, '08:00'));
    v_t3 := public._agenda_ver_gestor(c_sex) ->> 'texto';
    r := public.agenda_dupla_dita(v_adm, 'Lenine', true, c_sex, pg_temp.em(c_sex, '10:00'));
    x := public._agenda_classe_agora(v_len, c_sex) - 'pront';
    r2 := public.agenda_propor('os', null, null, array[v_len], '{}'::jsonb, false, 'vigia', null, c_sex, pg_temp.em(c_sex, '10:05'));
    v_t2 := public._agenda_aviso_fora_texto(r2 -> 'fora', '{}'::uuid[]);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Y2a com o Alex sozinho na equipe, *Lenine com dupla* não promete "vão 2 pessoas": diz quem está e o que fazer, que não marca de novo e que o já marcado fica',
    r ->> 'texto' = 'Lenine com dupla: anotei, vão 2 pessoas em cada meio-dia. Hoje só Alex está na equipe: para ir dupla, chame um ajudante e me diga os dias dele. Até lá eu não marco Lenine de novo; o que já está marcado fica como está. *desfaz Lenine* volta.',
    coalesce(r ->> 'texto', '-'));
  v_res := pg_temp.ok(v_res, 'Y2b a OS que pede 2 pessoas com 1 técnico na grade espera o dono: classe 4, motivo dupla; o motor a deixa de fora pelo mesmo motivo e o aviso diz "falta a 2ª pessoa" (antes: tirada do plano calada, "sem lugar", e nunca voltava)',
    x ->> 'classe' = '4' and x ->> 'motivo' = 'dupla'
    and x ->> 'texto' = 'precisa de 2 pessoas e só Alex está na equipe: chame um ajudante e me diga os dias dele'
    and v_t2 = 'Ficou de fora: Lenine (falta a 2ª pessoa).',
    coalesce(x::text, '-') || ' | ' || coalesce(v_t2, '-'));
  v_res := pg_temp.ok(v_res, 'Y2c o foco *agenda gestor* avisa antes de o dono dizer a palavra: "Pode precisar de dupla (banco de baterias): hoje só Alex está na equipe: para ir dupla, chame um ajudante e diga *Lenine com dupla*."',
    v_t3 like '%Pode precisar de dupla (banco de baterias): hoje só Alex está na equipe: para ir dupla, chame um ajudante e diga *Lenine com dupla*.%',
    coalesce(v_t3, '-'));
  begin
    r := public.agenda_dupla_dita(v_adm, 'Lenine', true, c_sex, pg_temp.em(c_sex, '10:00'));
    x := public._agenda_classe_agora(v_len, c_sex) - 'pront';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Y2d com a 2ª pessoa na grade (o replay de 29/10: João e Roberto), a palavra e a classe são as de antes',
    r ->> 'texto' = 'Lenine com dupla: nas próximas vezes que eu marcar, vão 2 pessoas em cada meio-dia. *desfaz Lenine* volta.'
    and x ->> 'motivo' is distinct from 'dupla',
    coalesce(r ->> 'texto', '-') || ' | ' || coalesce(x::text, '-'));

  -- ── Y3. A ficha prometida a quem não tem telefone ──
  begin
    perform pg_temp.equipe_3010();
    perform pg_temp.marcar(array[v_len], c_sex, pg_temp.em(c_sex, '08:00'));
    r := public._agenda_gestor_fichas(c_ter, pg_temp.em(c_ter, '16:53'));
    r3 := public._agenda_rotina_ficha(c_ter, pg_temp.em(c_ter, '19:30'));
    select a.texto, a.depois ->> 'por' into v_t, v_t2 from public.agenda_acoes a
     where a.tipo = 'equipe' and a.depois ->> 'motivo' = 'ficha_segurada' and a.payee_id = v_alex
     order by a.criada_em desc limit 1;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.equipe_3010();
    perform pg_temp.marcar(array[v_len], c_sex, pg_temp.em(c_sex, '08:00'));
    update public.payees set phone = '5547900000005' where id = v_alex;
    r2 := public._agenda_gestor_fichas(c_ter, pg_temp.em(c_ter, '16:53'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Y3a o gestor só pergunta a ficha de quem tem telefone: o Alex sem telefone, nenhuma pergunta ("Hoje às 19:30 a ficha de amanhã vai para Alex" era falso); com telefone, a pergunta de sempre',
    (r ->> 'perguntas')::int = 0 and (r2 ->> 'perguntas')::int = 1
    and r2 -> 'pessoas' -> 0 ->> 'texto' like 'Hoje às 19:30 a ficha de amanhã vai para Alex: Lenine, qua 04/11 o dia todo — dia 1 de 6, pela minha estimativa.%',
    coalesce(r::text, '-') || ' | ' || coalesce(r2 ->> 'perguntas', '-'));
  v_res := pg_temp.ok(v_res, 'Y3b às 19:30 a ficha de quem não tem telefone fica segurada e o dono fica sabendo o porquê: "… Alex não tem telefone no cadastro. Fale com Alex." (por sem_telefone)',
    v_t = 'Não mandei a ficha de qua 04/11 a Alex (Lenine): o dia é pela minha estimativa e Alex não tem telefone no cadastro. Fale com Alex.'
    and v_t2 = 'sem_telefone',
    coalesce(v_t, '-') || ' | ' || coalesce(v_t2, '-') || ' | ' || coalesce(r3::text, '-'));

  -- ── Y4. A pergunta da ficha fecha com o que houve no registro ──
  begin
    perform pg_temp.equipe_3010();
    update public.payees set phone = '5547900000005' where id = v_alex;
    perform pg_temp.marcar(array[v_len], c_sex, pg_temp.em(c_sex, '08:00'));
    r := public._agenda_gestor_fichas(c_ter, pg_temp.em(c_ter, '16:53'));
    v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
    update public.agenda_perguntas set mostrada_vezes = 1, mostrada_em = pg_temp.em(c_ter, '17:31'), mostrada_via = 'fechamento'
     where id = v_q;
    -- o telefone some entre a pergunta e a ficha: o registro recusa
    update public.payees set phone = null where id = v_alex;
    r2 := public._agenda_rotina_ficha(c_ter, pg_temp.em(c_ter, '19:30'));
    select q.estado || ' | ' || coalesce(q.resolvida_motivo, '-') into v_t from public.agenda_perguntas q where q.id = v_q;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Y4 a pergunta da ficha liberada (vista, não segurada) e a ficha recusada no registro: a pergunta fecha "… mas ela não saiu (sem telefone no cadastro)" — antes fechava "ela foi como eu disse" e o registro recusava em seguida',
    v_t = 'resolvida | na hora da ficha você não a segurou, mas ela não saiu (sem telefone no cadastro)'
    and r2 #>> '{por_estado,recusada}' = '1',
    coalesce(v_t, '-') || ' | ' || coalesce(r2::text, '-'));

  -- ── Y5. O dono "sempre" não é o técnico (AG7-02, AG7-04) ──
  begin
    r := public.agenda_meios_da_os(v_k33, c_sex);
    r2 := public.agenda_meios_da_os(v_r96, c_sex);
    update public.agenda_config set marcar_regras = array_remove(marcar_regras, 'uma_pessoa') where id;
    r3 := public.agenda_meios_da_os(v_k33, c_sex);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Y5a com a regra uma_pessoa, a marina nova (presença sempre) leva 1 técnico por turno e o dono junto (antes 0: só o dono); o diagnóstico (Rodrigo OS-00096) continua só com o dono; sem a regra, o de antes (2 pessoas, o dono é uma)',
    r ->> 'presenca' = 'sempre' and r ->> 'regra_motivo' = 'marina nova'
    and (r #>> '{por_turno,manha,desejado}')::int = 1 and (r #>> '{por_turno,tarde,desejado}')::int = 1
    and r2 ->> 'regra_motivo' = 'diagnóstico' and (r2 #>> '{por_turno,manha,desejado}')::int = 0
    and (r3 #>> '{por_turno,manha,desejado}')::int = greatest((r3 ->> 'pessoas_sugeridas')::int - 1, 0),
    coalesce((r -> 'por_turno')::text, '-') || ' | ' || coalesce((r2 -> 'por_turno')::text, '-') || ' | ' || coalesce((r3 -> 'por_turno')::text, '-'));
  begin
    perform pg_temp.equipe_3010();
    -- a Kalmar OS-00033 volta do cliente e o dono diz "faltam 3 dias"; a linha do dono em campo (publicar/exec/dono-campo-3010.sql)
    update public.service_orders set status = 'open' where id = v_k33;
    insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em)
    values (v_k33, 3, 'dono', pg_temp.em(c_sex, '09:00'))
    on conflict (service_order_id) do update set dias = 3, estimativa_fonte = 'dono', estimativa_em = pg_temp.em(c_sex, '09:00');
    insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, trecho)
    values (v_dono, '{1,2,3,4,5}'::smallint[], null, 'disponivel', 'dono', 'você disse em 30/10', 'fico em campo de segunda a sexta');
    perform pg_temp.marcar(array[v_k33], c_sex, pg_temp.em(c_sex, '10:00'));
    select count(*) filter (where a.payee_id = v_alex and a.presenca = 'turno'), count(*) filter (where a.payee_id = v_dono)
      into v_n, v_n2
      from public.agenda_alocacoes a
     where a.service_order_id = v_k33 and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Y5b com a linha do dono, a Kalmar OS-00033 (marina nova, 3 dias ditos) é marcada com o Alex em todo meio-dia e o dono junto (antes: só o dono, o turno inteiro, e o Alex parado)',
    v_n = 6 and v_n2 > 0, format('Alex %s meios-dias; você %s', v_n, v_n2));

  -- ── Y6. O *desfaz* vale até a OS mudar (o achado 17 de novo) ──
  begin
    perform pg_temp.marcar(array[v_len], c_hoje, pg_temp.em(c_hoje, '16:53'));
    select a.id into v_a from public.agenda_acoes a
     where a.service_order_id = v_len and a.executada and a.origem = 'vigia' and a.tipo in ('criar', 'promover_reserva', 'mover')
     order by a.criada_em desc, a.id desc limit 1;
    r := public.agenda_desfazer(v_a, v_adm, 'dono', c_sex, pg_temp.em(c_sex, '09:40'));
    -- a proposta de quinta da vigia reserva o Lenine de novo (a ação de plano automática, depois do *desfaz*)
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, texto, depois)
    values (clock_timestamp() + interval '1 hour', c_sex, true, 'vigia', 'publicar', v_len, array[v_len],
            'Reserva (acima da carga) Lenine (OS-00074): seg 09 a seg 16/11', '{}');
    v_t := public._agenda_gestor_desfeito(v_len, clock_timestamp() + interval '2 hours')::text;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, texto, depois)
    values (clock_timestamp() + interval '3 hours', c_sex, true, 'dono', 'fixar', v_len, array[v_len], 'Lenine: você fixou seg 09/11', '{}');
    v_t2 := public._agenda_gestor_desfeito(v_len, clock_timestamp() + interval '4 hours')::text;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Y6a a reserva automática da vigia depois do *desfaz* não solta a trava (antes soltava, e a revisão de sexta remarcava firme); a ação do dono solta',
    (r ->> 'ok')::boolean and v_t = 'true' and v_t2 = 'false',
    coalesce(r ->> 'texto', '-') || ' | depois da reserva ' || coalesce(v_t, '-') || ' | depois do dono ' || coalesce(v_t2, '-'));
  v_res := pg_temp.ok(v_res, 'Y6b o foco agrupa o porquê certo: desfeito "você desfez (me diga os dias para eu marcar de novo)" e dupla "falta a 2ª pessoa", antes de "sem lugar na agenda"',
    public._agenda_gestor_motivo_texto('desfeito') = 'você desfez (me diga os dias para eu marcar de novo)'
    and public._agenda_gestor_motivo_texto('dupla') = 'falta a 2ª pessoa'
    and public._agenda_gestor_motivo_ordem('você desfez (me diga os dias para eu marcar de novo)') < public._agenda_gestor_motivo_ordem('sem lugar na agenda')
    and public._agenda_gestor_motivo_ordem('falta a 2ª pessoa') < public._agenda_gestor_motivo_ordem('sem lugar na agenda'),
    public._agenda_gestor_motivo_texto('desfeito') || ' | ' || public._agenda_gestor_motivo_texto('dupla'));

  -- ── Y7. Acima de 8 diárias (o achado 20 de novo) ──
  begin
    r := public._agenda_gestor_perguntas_da_os(v_gia, c_hoje, pg_temp.em(c_hoje, '16:53'), false);
    v_q := (r ->> 'pergunta_id')::uuid;
    select jsonb_array_length(q.opcoes), q.opcoes -> 2 ->> 'texto', q.opcoes -> 2 -> 'efeito' ->> 'terminou'
      into v_n, v_t, v_t2 from public.agenda_perguntas q where q.id = v_q;
    -- mostrada 2 vezes, sem resposta, vence (expira_em: 7 dias): a rodada seguinte pergunta de novo
    update public.agenda_perguntas set mostrada_vezes = 2, mostrada_em = pg_temp.em(c_ter, '17:31'), mostrada_via = 'fechamento'
     where id = v_q;
    update public.agenda_perguntas set estado = 'vencida' where id = v_q;
    r2 := public._agenda_gestor_perguntas_da_os(v_gia, date '2026-11-10', pg_temp.em(date '2026-11-10', '16:53'), false);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Y7a o serviço grande (Giancarlo, entregue — AG7-11) ganha a 3ª opção "Já terminou (ou já entreguei)" (efeito terminou)',
    v_n = 3 and v_t = 'Já terminou (ou já entreguei)' and v_t2 = 'true', format('%s opções; %s; %s', v_n, v_t, v_t2));
  v_res := pg_temp.ok(v_res, 'Y7b a pergunta sem prazo que venceu sem resposta (mostrada 2 vezes) volta: o gestor pergunta de novo (antes: "ja_perguntei" e a OS sem data e sem pergunta para sempre)',
    (r2 ->> 'perguntou')::boolean and (r2 ->> 'pergunta_id')::uuid is distinct from v_q and r2 -> 'veto_ate' = 'null'::jsonb,
    coalesce(r2::text, '-'));
  begin
    perform public._agenda_gestor_perguntar('situacao', 'situacao:' || v_k32 || ':rastro', v_k32,
      'Kalmar (OS-00032) já começou em 22/06: quanto falta? Pelo orçamento o serviço inteiro dá 18,3 diárias, mais de 8: não marco sozinho, espero você dizer quanto falta.',
      '[]'::jsonb, 2::smallint, null, null, 'ligado', pg_temp.em(c_sex, '16:53'));
    perform public._agenda_gestor_perguntar('situacao', 'situacao:' || v_k33 || ':rastro', v_k33,
      'Kalmar (OS-00033) já começou: quanto falta? … não marco sozinho, espero você dizer quanto falta.',
      '[]'::jsonb, 2::smallint, null, null, 'ligado', pg_temp.em(c_sex, '16:53'));
    v_t := public._agenda_ver_gestor(c_sex) ->> 'texto';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Y7c em "Perguntei antes de marcar", o nome que se repete leva o número da OS ("• Kalmar (OS-00032): …" e "• Kalmar (OS-00033): …", não duas linhas iguais)',
    v_t like '%• Kalmar (OS-00032): %' and v_t like '%• Kalmar (OS-00033): %',
    coalesce(substr(v_t, position('Perguntei antes de marcar' in v_t), 400), v_t));

  -- ── Y8. O "compre até" da OS que a vigia tirou do plano pelo material (D7-2, spec §3.2 e §5.10) ──
  begin
    perform pg_temp.marcar(array[v_van], c_sex, pg_temp.em(c_sex, '08:00'));
    perform public._agenda_gestor_compre_ate(c_sex, pg_temp.em(c_sex, '16:53'));
    -- qua 04/11 00:00 a vigia tira o Vanderlei pelo material (o "compre até" de sex 30/10 venceu e a peça não chega a tempo)
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'material', cancelada_em = pg_temp.em(c_qua, '00:00')
     where service_order_id = v_van and tipo <> 'reserva' and estado in ('publicada', 'fixada');
    r := public._agenda_gestor_compre_ate(c_qua, pg_temp.em(c_qua, '16:53'));
    select string_agg(m.empurrada_vezes::text, ',' order by m.descricao) into v_t
      from public.os_material m where m.service_order_id = v_van and m.compre_ate is not null;
    r2 := public._agenda_gestor_compre_ate(c_qua, pg_temp.em(c_qua, '17:07'));
    v_lin := public._agenda_linhas_do_fechamento(c_qua);
    v_t2 := (select l ->> 'perda' || ' ' || (l ->> 'texto') from jsonb_array_elements(v_lin) l where l ->> 'tipo' = 'compras');
    r3 := public._agenda_gestor_compre_ate(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
    select string_agg(q.estado || ' ' || split_part(q.chave, ':', 3), ',' order by q.criada_em) into v_t3
      from public.agenda_perguntas q where q.tipo = 'compre_ate' and q.service_order_id = v_van;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Y8a a OS que saiu da agenda pelo material sem a compra: o empurrão conta (cada item, empurrada_vezes 1), uma vez só por saída (o tique seguinte não soma)',
    (r ->> 'empurrados')::int = 3 and v_t = '1,1,1' and (r2 ->> 'empurrados')::int = 0,
    format('1º %s; itens %s; 2º %s', r ->> 'empurrados', v_t, r2 ->> 'empurrados'));
  v_res := pg_temp.ok(v_res, 'Y8b a cobrança continua: "Vanderlei (OS-00069) saiu da agenda: … Comprando hoje, chega para começar seg 16/11. Quando comprar, me diga o dia que chega e eu marco de novo." — e não é resolvida "não precisa mais" no dia seguinte',
    r -> 'perguntas' -> 0 ->> 'variante' = 'saiu'
    and r -> 'perguntas' -> 0 ->> 'texto' = 'Vanderlei (OS-00069) saiu da agenda: o ''compre até'' de 3 itens venceu sex 30/10 e a peça não chegaria a tempo. Comprando hoje, chega para começar seg 16/11. Quando comprar, me diga o dia que chega e eu marco de novo.'
    and v_t3 like '%aberta saiu%',
    coalesce(r -> 'perguntas' ->> 0, '-') || ' | ' || coalesce(v_t3, '-'));
  v_res := pg_temp.ok(v_res, 'Y8c as compras do fechamento a mantêm, como decisão (perda 80): "… 3 itens de Vanderlei — saiu da agenda: comprando hoje, chega para começar seg 16/11."',
    v_t2 = '80 Compras: Sem fornecedor (contei 7 dias úteis): 3 itens de Vanderlei — saiu da agenda: comprando hoje, chega para começar seg 16/11.',
    coalesce(v_t2, '-'));

  -- ── Y9 e Y12a. O aviso das 17:00 com as perguntas do gestor ──
  begin
    perform public.agenda_gestor_rodar(c_sex, pg_temp.em(c_sex, '08:07'));
    perform public.agenda_gestor_rodar(c_sex, pg_temp.em(c_sex, '16:53'));
    r := public.agenda_aviso_pecas(c_sex, pg_temp.em(c_sex, '17:00'));
    select q.id into v_q from public.agenda_perguntas q
     where q.tipo = 'situacao' and q.service_order_id = v_nel and q.modo = 'ligado' and q.estado = 'aberta';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_t := r -> 'perguntas' ->> 'texto';
  v_res := pg_temp.ok(v_res, 'Y9a o aviso diz até quando valem as perguntas do gestor que ele conta como vistas: "Sem resposta até ter 03/11 às 18:00, faço o que eu disse." (antes o dono só lia o prazo no fechamento do próprio dia)',
    v_t like '%Sem resposta até ter 03/11 às 18:00, faço o que eu disse.', coalesce(v_t, r::text));
  v_res := pg_temp.ok(v_res, 'Y9b a frase do gestor termina com ponto e a pergunta da situação não se repete: "• Nelson (OS-00112): compra quando? Perguntei se já começou; sem resposta, conto 4 dias." (antes "… conto 4 dias O serviço já começou?")',
    v_t like '%• Nelson (OS-00112): compra quando? Perguntei se já começou; sem resposta, conto 4 dias.' || E'\n' || '%'
    and v_t not like '%O serviço já começou?%' and v_t not like '%dias O %' and v_t not like '%os dias Tem %',
    coalesce(v_t, '-'));
  v_res := pg_temp.ok(v_res, 'Y12a (achado 15 da 1ª revisão, sem teste vermelho) o aviso conta como vistas as perguntas do gestor das OS que ele cobre (a situação do Nelson em pergunta_ids)',
    v_q is not null and (r -> 'perguntas' -> 'pergunta_ids') ? v_q::text, coalesce((r -> 'perguntas' -> 'pergunta_ids')::text, '-'));

  -- ── Y10. O estimar do gestor e a marcação da mesma OS no mesmo aviso ──
  begin
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, texto, depois)
    values (pg_temp.em(c_sex, '18:07'), c_sex, true, 'vigia', 'estimar', v_van, array[v_van],
            'Sem resposta sobre Vanderlei até sex 30/10 às 18:00: contei o serviço inteiro, 7,5 dias (estimativa minha). *desfaz Vanderlei* volta.', '{}');
    perform pg_temp.marcar(array[v_van], c_sex, pg_temp.em(c_sex, '18:08'));
    r := public.agenda_aviso_pecas(c_sex, pg_temp.em(c_sex, '18:15'));
    select count(*) into v_n from jsonb_array_elements(r -> 'mudancas') m where m ->> 'texto' like '%*desfaz Vanderlei*%';
    v_t := (select m ->> 'texto' from jsonb_array_elements(r -> 'mudancas') m where m ->> 'texto' like 'Sem resposta sobre Vanderlei%');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Y10 o estimar (os dias que o prazo gravou) e a marcação do Vanderlei no mesmo aviso: um *desfaz Vanderlei* só (na marcação); a linha do estimar fica sem ele',
    v_n = 1 and v_t = 'Sem resposta sobre Vanderlei até sex 30/10 às 18:00: contei o serviço inteiro, 7,5 dias (estimativa minha).',
    format('%s *desfaz*; %s', v_n, coalesce(v_t, '-')));

  -- ── Y11. A parada conta o planejamento que o dono mexeu ──
  begin
    r := public._agenda_os_situacao(v_van, c_ter);
    insert into public.os_planejamento (service_order_id, atualizado_em, atualizado_por) values (v_van, pg_temp.em(c_ter, '09:00'), v_adm)
    on conflict (service_order_id) do update set atualizado_em = pg_temp.em(c_ter, '09:00'), atualizado_por = v_adm;
    r2 := public._agenda_os_situacao(v_van, c_ter);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Y11 o Vanderlei parado desde 03/10 (ter 03/11): pende "parada"; com o dono mexendo no planejamento hoje (a dupla, os dias), não pende mais — como o comentário da correção 1 dizia',
    r ->> 'tipo' = 'parada' and (r ->> 'pendente')::boolean and not (r2 ->> 'pendente')::boolean,
    coalesce(r::text, '-') || ' | ' || coalesce(r2::text, '-'));

  -- ── Y12b e Y12c. As outras duas correções da 1ª revisão sem teste vermelho ──
  v_t := array_to_string(array(select jsonb_array_elements_text(public._agenda_aprontar_de(jsonb_build_object(
           'dono_padrao', true,
           'oss', jsonb_build_array(
             jsonb_build_object('executavel', true, 'dono_trava', false, 'ordem', 1, 'numero', 'OS-00074', 'curto', 'Lenine',
               'restr_dono', jsonb_build_array(jsonb_build_object('tipo', 'sem_peca_suposta', 'quem', 'dono', 'bloqueia', false,
                 'texto', 'marquei sem peça a comprar; se precisar, me diga', 'pergunta', null))),
             jsonb_build_object('executavel', true, 'dono_trava', true, 'ordem', 2, 'numero', 'OS-00112', 'curto', 'Nelson',
               'restr_dono', jsonb_build_array(jsonb_build_object('tipo', 'compre_ate', 'quem', 'dono', 'bloqueia', true,
                 'texto', 'compre até hoje', 'pergunta', 'compra quando?'))))), 20) -> 'linhas')), E'\n');
  v_res := pg_temp.ok(v_res, 'Y12b (achado 24 da 1ª revisão, sem teste vermelho) a suposição sem pergunta (sem_peca_suposta) não vira a linha vazia "• Lenine (OS-00074): " no aprontar, com o Lenine entre os que cabem; o Nelson pergunta',
    v_t not like '%Lenine%' and v_t like '%• Nelson (OS-00112): compra quando?%', v_t);
  begin
    perform pg_temp.marcar(array[v_len], c_hoje, pg_temp.em(c_hoje, '16:53'));
    select a.id into v_a from public.agenda_acoes a
     where a.service_order_id = v_len and a.executada and a.origem = 'vigia' and a.tipo in ('criar', 'promover_reserva', 'mover')
     order by a.criada_em desc, a.id desc limit 1;
    r := public.agenda_desfazer(v_a, v_adm, 'dono', c_sex, pg_temp.em(c_sex, '09:40'));
    -- o tique seguinte do encaixe (o *desfaz* voltou o planejamento na mesma hora: o sinal de "mudou" dele não conta)
    r2 := public._agenda_gestor_encaixe(c_hoje, clock_timestamp() + interval '10 minutes');
    v_t := pg_temp.dias(v_len, c_hoje);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Y12c (achado 17 da 1ª revisão, sem teste vermelho) o encaixe do tique seguinte não marca de novo o Lenine que o dono desfez (o planejamento que o próprio *desfaz* voltou não é "mudou")',
    (r ->> 'ok')::boolean and v_t = '-'
    and not exists (select 1 from jsonb_array_elements(coalesce(r2 -> 'por_os', '[]'::jsonb)) p where (p ->> 'os')::uuid = v_len),
    coalesce(v_t, '-') || ' | ' || coalesce(left((r2 -> 'por_os')::text, 300), '-'));

  -- ── Y13. As do lote de 30/10 mudadas no lugar pela 100980, com o gestor desligado ──
  if coalesce(current_setting('agenda_teste.mig_correcao_aviso', true), '') = '' then
    v_res := pg_temp.ok(v_res, 'Y13 o aviso do lote de 30/10', true, 'PULADO: sem agenda_teste.mig_correcao_aviso (rode pela bancada)');
  else
    execute replace(pg_temp.inteira(current_setting('agenda_teste.mig_correcao_aviso'), '_agenda_aviso_mudancas'),
                    'create or replace function public._agenda_aviso_mudancas(', 'create function pg_temp.aviso_mudancas_antes(');
    execute replace(pg_temp.inteira(current_setting('agenda_teste.mig_correcao_aviso'), '_agenda_aviso_fora_texto'),
                    'create or replace function public._agenda_aviso_fora_texto(', 'create function pg_temp.aviso_fora_antes(');
    begin
      perform pg_temp.replay('desligado');
      -- as ações das Fases 1–6 que o aviso conta (a vigia e o motor publicam, criam, movem, cancelam; o dono não conta)
      perform pg_temp.marcar(array[v_len, v_van], c_hoje, pg_temp.em(c_hoje, '16:53'));
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, texto, depois)
      values (pg_temp.em(c_hoje, '17:10'), c_hoje, true, 'vigia', 'mover', v_nel, array[v_nel], 'Nelson (OS-00112): de ter 10 para qua 11/11 — o material não chega a tempo.', '{}'),
             (pg_temp.em(c_hoje, '17:11'), c_hoje, true, 'dono', 'cancelar', v_gia, array[v_gia], 'Giancarlo (OS-00130): você tirou da agenda.', '{}');
      select count(*), count(*) filter (where public._agenda_aviso_mudancas(d)::text = pg_temp.aviso_mudancas_antes(d)::text),
             sum(jsonb_array_length(public._agenda_aviso_mudancas(d)))
        into v_n, v_n2, x
        from generate_series(c_hoje - 2, c_hoje + 6, interval '1 day') g(t), lateral (select g.t::date as d) dd;
      select string_agg(m, ',') into v_t
        from unnest(array['material', 'atrasado', 'sem_previsao', 'comprado_sem_previsao', 'compra_sem_prazo', 'compre_ate',
                          'material_nao_conferido', 'peca_embutida', 'cliente', 'bem', 'sinal', 'orcamento', 'escopo', 'duracao',
                          'so_com_voce', 'padrao_do_dono', 'sem_encaixe', 'sem_reserva', 'fixar_nao_cabe', 'nao_cabe', 'depois',
                          'nao_antes', 'espera', 'parada', 'congelada', 'outro']) m
       where public._agenda_aviso_fora_texto(jsonb_build_array(jsonb_build_object('os', gen_random_uuid(), 'numero', 'OS-1',
                                                                                 'cliente_curto', 'Fulano', 'motivo', m)), '{}'::uuid[])
             is distinct from
             pg_temp.aviso_fora_antes(jsonb_build_array(jsonb_build_object('os', gen_random_uuid(), 'numero', 'OS-1',
                                                                           'cliente_curto', 'Fulano', 'motivo', m)), '{}'::uuid[]);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    v_res := pg_temp.ok(v_res, 'Y13 _agenda_aviso_mudancas e _agenda_aviso_fora_texto (do lote de 30/10, em produção; mudadas no lugar pela 100980, fora de bloco) com o gestor desligado: a saída da definição de 20261030100300, byte a byte (9 dias com as mudanças da vigia e do dono; os 26 motivos de antes da 7a)',
      v_n = 9 and v_n2 = 9 and coalesce(x::text, '0')::int > 0 and v_t is null,
      format('dias iguais %s de %s (%s grupos); motivos diferentes: %s', v_n2, v_n, coalesce(x::text, '0'), coalesce(v_t, 'nenhum')));
  end if;

  perform pg_temp.gravar(v_res);
end
$y$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
