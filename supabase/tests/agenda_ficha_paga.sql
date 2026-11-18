-- Prova da ficha paga (18/11/2026, migration 20270125100000; o caso OS-00129; plano agenda-pesquisa/via-os129-1711/plano/PLANO.md,
-- F2, decisão do dono "Segura a ficha"), sobre a carteira REAL de 29/10 (o replay da 7a: o Lenine, OS-00074, marcado pela
-- estimativa — o João em ter 03 e qua 04, o Roberto de qui 05 a ter 10/11; o ligar do gestor qui 29/10 16:46, a janela da ficha
-- até qua 18/11).
-- bancada: depende de 20270125100000
--
--   F0 as portas e o que é (sem fixture): as 2 leituras novas invoker, STABLE, authenticated e service_role, nunca anon; as 4
--      recriadas com as portas de antes; a OS que não existe não está paga; sem o ligar, a ficha de quem não tem OS paga sai
--   F1 toda pergunta da ficha leva o número da OS; a não paga é a de antes (padrão e recomendação 1)
--   F2 paga dentro da janela: o aviso, padrão e recomendação 2; a linha do fechamento (inteira e curta: "Para mandar, me diga
--      *mande*."); mostrada e sem resposta, o prazo NÃO solta (o passo vetos não aplica a 2 e não registra erro); às 19:30 a ficha
--      fica (recusada, veto), o porquê ao dono ("… a OS já está paga por inteiro e você não disse *mande*. …", por paga), a
--      pergunta fecha com o motivo dela; a confirmação da manhã também fica
--   F3 o *mande* do dono (1) solta a ficha da OS paga; o *segure* (2) a deixa, sem ação ao dono; a 1 gravada por outro canal que
--      não o do dono (prazo) não solta
--   F4 fora da janela (o ligar de 01/10) e sem o ligar do gestor: só quem tem OS paga ganha a pergunta e a ficha dela fica sem o
--      *mande*; a não paga sai como antes
--   F5 paga depois da pergunta: a aberta de padrão 1 fica resolvida e nasce a nova (padrão 2), uma vez só; o *mande* dado antes de
--      a OS ficar paga vale
--   F6 o que conta como paga: total 0 não; o sinal (parcial) não; o pago por inteiro sim; a cancelada não conta; a OS concluída não
--   F7 sem OS paga, o de antes, byte a byte: a liberada, a ficha das 19:30 e as linhas do fechamento iguais às definições de antes
--      (rodadas como pg_temp); a pergunta igual a menos do número da OS; o João na rotina, para a ficha de ter 03/11 (presa, com a
--      ação ao dono) entrar na comparação
--   F8 (revisão adversarial) o *mande* pelo painel sem autor e pela tela soltam; o dia misto (paga de manhã, não paga à tarde) fica;
--      duas pessoas fora da janela, só a da OS paga ganha a pergunta; a alocação da OS paga cancelada não conta; faturada e cancelada
--      não são pagas; a alocação que não é pela estimativa não conta; a pergunta em teste (sombra) e a fechada sem opção não soltam;
--      o dono sempre tem a ficha; o porquê em 3 casos (sem pergunta, não mostrada, mostrada sem resposta); na linha (m), a ficha paga
--      vem antes da outra ficha do dia; (conferência) a respondida SEM opção não solta (F8f2) e a OS paga de quem não tem telefone diz o
--      porquê de antes, sem_telefone (F8n)
--   F9 (revisão adversarial) o caminho real do dono: a ferramenta agenda_aplicar (agenda_rascunho_aplicar, decisão e opção) e o
--      *grava* (agenda_rascunho_gravar) soltam a ficha paga; com duas decisões esperando, sem dizer qual, recusa; com os números, sai
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_ficha_paga.sql
--   Seguro em produção: F0 só lê; F1 a F7 usam o replay e só rodam na bancada (fora dela saem PULADO). Termina em ROLLBACK.
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
  select py.id from public.payees py where py.name = p_nome and py.active order by py.id limit 1
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- O replay com o gestor ligado (o ligar de qui 29/10 16:46) e o Lenine e o Vanderlei marcados pela estimativa (como a 7a P11).
create function pg_temp.fixtures() returns jsonb language plpgsql as $f$
declare
  v_p jsonb;
begin
  execute current_setting('agenda_teste.replay2910');
  insert into public.os_planejamento (service_order_id, dono_presenca)
  select so.id, 'abre_e_fecha' from public.service_orders so where so.service_order_number in ('OS-00074', 'OS-00069')
  on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';
  update public.payees set phone = '5547900000004' where name = 'João' and phone is null;
  update public.agenda_config
     set modo_marcar_sozinho = 'ligado', modo_encaixe_aprovacao = 'ligado', modo_revisao_diaria = 'ligado', modo_compre_ate = 'ligado',
         modo_vaga_fechamento = 'ligado', gestor_so_propor = false, gestor_so_propor_em = null,
         marcar_sozinho_desde = timestamptz '2026-10-29 16:46-03',
         marcar_regras = '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}'
   where id;
  v_p := public.agenda_propor('os', null, null, array[pg_temp.os('OS-00069'), pg_temp.os('OS-00074')], '{}'::jsonb, true, 'vigia',
                              null, date '2026-10-29', timestamptz '2026-10-29 16:52-03');
  return public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'vigia', null, null, date '2026-10-29',
                               timestamptz '2026-10-29 16:52-03');
end $f$;
-- Uma conta a receber paga (o que falta para a OS ficar paga por inteiro, ou p_valor).
create function pg_temp.pagar(p_os uuid, p_valor numeric default null, p_status text default 'paid') returns void language plpgsql as $f$
declare
  v_falta numeric;
begin
  select so.grand_total - coalesce((select sum(coalesce(r.paid_amount, 0)) from public.receivables r
                                     where r.service_order_id = so.id and r.status is distinct from 'cancelled'), 0)
    into v_falta from public.service_orders so where so.id = p_os;
  insert into public.receivables (id, client_id, service_order_id, description, issue_date, due_date, amount, status, paid_amount,
                                  balance_amount, is_deposit)
  select gen_random_uuid(), so.client_id, so.id, 'Pago (teste da ficha paga)',
         date '2026-10-20', date '2026-10-20', coalesce(p_valor, v_falta), p_status, coalesce(p_valor, v_falta), 0, false
    from public.service_orders so where so.id = p_os;
end $f$;
-- As mensagens à equipe de uma pessoa: "tipo dia estado/motivo [leva]".
create function pg_temp.equipe(p_payee uuid) returns text language sql stable as $f$
  select string_agg(format('%s %s %s%s', m.tipo, m.dia, m.estado || coalesce('/' || m.recusa_motivo, ''),
                           coalesce(' leva ' || m.leva_ficha_de, '')), ' | ' order by m.dia, m.criada_em, m.tipo)
    from public.agenda_equipe_mensagens m where m.payee_id = p_payee and m.modo = 'ligado'
$f$;
-- A função inteira a partir do texto da migration (a definição de antes, para rodar como pg_temp).
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;

-- ── F0. As portas e o que é (sem fixture) ───────────────────────────────────────────────────────────────
with f(assinatura, quem, vol) as (values
  ('public._agenda_os_paga_por_inteiro(uuid)', 'leitura', 's'),
  ('public._agenda_ficha_os_pagas(uuid, date)', 'leitura', 's'),
  ('public._agenda_ficha_liberada(uuid, date, timestamptz)', 'leitura', 's'),
  ('public._agenda_linhas_do_fechamento(date)', 'leitura', 's'),
  ('public._agenda_gestor_fichas(date, timestamptz)', 'ninguem', 'v'),
  ('public._agenda_rotina_ficha(date, timestamptz)', 'ninguem', 'v'))
insert into _resultado
select 'F0a as portas: as 2 leituras novas e a liberada invoker, STABLE, para authenticated e service_role; as linhas do fechamento como eram; o passo fichas e a ficha das 19:30 sem grant a ninguém; nunca anon; search_path fixo',
       bool_and(not has_function_privilege('anon', f.assinatura, 'execute')
                and has_function_privilege('authenticated', f.assinatura, 'execute') = (f.quem = 'leitura')
                and has_function_privilege('service_role', f.assinatura, 'execute') = (f.quem = 'leitura')
                and not p.prosecdef and p.provolatile::text = f.vol
                and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'),
       string_agg(f.assinatura, ', ') filter (where has_function_privilege('anon', f.assinatura, 'execute')
                                              or has_function_privilege('authenticated', f.assinatura, 'execute') <> (f.quem = 'leitura')
                                              or p.prosecdef or p.provolatile::text <> f.vol)
  from f join pg_proc p on p.oid = f.assinatura::regprocedure;

do $f0$
declare
  v_res jsonb := '[]'::jsonb;
begin
  v_res := pg_temp.ok(v_res, 'F0b a OS que não existe (ou nula) não está paga; a pessoa sem alocação não tem OS paga',
    not public._agenda_os_paga_por_inteiro(gen_random_uuid()) and not public._agenda_os_paga_por_inteiro(null)
    and public._agenda_ficha_os_pagas(gen_random_uuid(), date '2026-11-05') = '{}'::uuid[], null);
  begin
    update public.agenda_config set marcar_sozinho_desde = null where id;
    v_res := pg_temp.ok(v_res, 'F0c sem o ligar do gestor, a ficha de quem não tem OS paga sempre pode sair (o de antes)',
      public._agenda_ficha_liberada(gen_random_uuid(), date '2026-11-05', now()), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$f0$;

-- ── F1 a F6: com o replay ────────────────────────────────────────────────────────────────────────────
do $fx$
declare
  v_res   jsonb := '[]'::jsonb;
  c_qua   constant date := date '2026-11-04';
  c_q05   constant date := date '2026-11-05';
  c_s06   constant date := date '2026-11-06';
  c_nao   constant text := 'Hoje às 19:30 a ficha de amanhã vai para Roberto: OS-00074 Lenine, qui 05/11 o dia todo — dia 3 de 6, pela minha estimativa. 1) Mande (recomendo); 2) Segure a ficha: eu não mando e você fala com ele.';
  c_paga  constant text := 'Hoje às 19:30 a ficha de amanhã vai para Roberto: OS-00074 Lenine, qui 05/11 o dia todo — dia 3 de 6, pela minha estimativa. A OS-00074 já está PAGA por inteiro: o serviço ainda vai ser feito? Sem resposta até 19:30, eu seguro a ficha. 1) Mande; 2) Segure a ficha: eu não mando e você fala com ele (recomendo).';
  c_curta constant text := 'Agenda: Hoje às 19:30 a ficha de amanhã vai para Roberto: OS-00074 Lenine, qui 05/11 o dia todo — dia 3 de 6, pela minha estimativa. A OS-00074 já está PAGA por inteiro: o serviço ainda vai ser feito? Sem resposta até 19:30, eu seguro a ficha. Para mandar, me diga *mande*.';
  c_acao  constant text := 'Não mandei a ficha de qui 05/11 a Roberto (OS-00074 Lenine): a OS já está paga por inteiro e você não disse *mande*. Fale com Roberto.';
  v_len   uuid;
  v_rob   uuid;
  v_adm   uuid;
  v_q     uuid;
  v_q2    uuid;
  r       jsonb;
  r2      jsonb;
  v_t     text;
  v_t2    text;
  v_n     int;
  v_err   int;
  v_ok    boolean;
  v_lin   jsonb;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('F1 a F6 (o replay de 29/10)', true, 'PULADO: sem agenda_teste.replay2910 (rode pela bancada)');
    return;
  end if;
  begin
    r := pg_temp.fixtures();
    v_len := pg_temp.os('OS-00074');
    v_rob := pg_temp.pessoa('Roberto');
    select u.id into v_adm from public.app_users u where u.role = 'admin' order by u.id limit 1;

    -- ── F1. O número da OS em toda pergunta; a não paga é a de antes ──
    begin
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      select format('%s|%s|%s', q.opcao_padrao, q.recomendacao, q.texto) into v_t from public.agenda_perguntas q where q.id = v_q;
      v_res := pg_temp.ok(v_res, 'F1a a pergunta da ficha leva o número da OS ("Roberto: OS-00074 Lenine, qui 05/11 o dia todo — dia 3 de 6, …"); sem OS paga, padrão e recomendação 1, o resto como antes',
        not public._agenda_os_paga_por_inteiro(v_len) and v_t = '1|1|' || c_nao and (r ->> 'novas')::int = 1, coalesce(v_t, '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── F2. Paga dentro da janela: o aviso, o padrão 2, a linha do fechamento, o prazo que não solta, a ficha que fica ──
    begin
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      select format('%s|%s|%s|%s', q.opcao_padrao, q.recomendacao, q.veto_ate = pg_temp.em(c_qua, '19:30'), q.texto) into v_t
        from public.agenda_perguntas q where q.id = v_q;
      v_res := pg_temp.ok(v_res, 'F2a paga por inteiro (dentro da janela): "… A OS-00074 já está PAGA por inteiro: o serviço ainda vai ser feito? Sem resposta até 19:30, eu seguro a ficha. 1) Mande; 2) Segure … (recomendo)." — padrão e recomendação 2, prazo 19:30',
        public._agenda_os_paga_por_inteiro(v_len) and public._agenda_ficha_os_pagas(v_rob, c_q05) = array[v_len]
        and v_t = '2|2|t|' || c_paga, coalesce(v_t, '-'));
      v_lin := public._agenda_linhas_do_fechamento(c_qua);
      v_res := pg_temp.ok(v_res, 'F2b a linha (m) do fechamento: a inteira com o aviso; a curta termina com "Para mandar, me diga *mande*." (não "Para segurar")',
        exists (select 1 from jsonb_array_elements(v_lin) x where x ->> 'pergunta_id' = v_q::text and x ->> 'texto' = 'Agenda: ' || c_paga
                 and x ->> 'texto_curto' = c_curta),
        (select string_agg(coalesce(x ->> 'texto_curto', '-'), ' || ') from jsonb_array_elements(v_lin) x where x ->> 'pergunta_id' = v_q::text));
      -- mostrada no fechamento das 17:30, sem resposta
      perform public.agenda_fechamento_registrar(c_qua,
        (select jsonb_agg(x) from jsonb_array_elements(v_lin) x where x ->> 'pergunta_id' = v_q::text), 'fechamento', pg_temp.em(c_qua, '17:30'));
      v_ok := public._agenda_ficha_liberada(v_rob, c_q05, pg_temp.em(c_qua, '19:29'));
      v_err := (select count(*) from public.app_error_logs);
      r := public._agenda_gestor_vetos(c_qua, pg_temp.em(c_qua, '19:31'));
      v_t := (select q.estado || ':' || coalesce(q.opcao_escolhida::text, '-') from public.agenda_perguntas q where q.id = v_q);
      v_res := pg_temp.ok(v_res, 'F2c mostrada e sem resposta, nada solta: a liberada é falsa; o passo vetos não aplica a 2 sem resposta (sem_condicao), não registra erro, e a pergunta continua aberta',
        not v_ok and v_t = 'aberta:-' and (r ->> 'sem_condicao')::int >= 1 and (select count(*) from public.app_error_logs) = v_err,
        v_t || ' | ' || r::text);
      v_n := (select count(*) from public.whatsapp_send_queue);
      r := public._agenda_rotina_ficha(c_qua, pg_temp.em(c_qua, '19:32'));
      v_res := pg_temp.ok(v_res, 'F2d às 19:30 a ficha de qui 05/11 fica (recusada, veto), nada vai à fila; o porquê ao dono: "Não mandei a ficha de qui 05/11 a Roberto (OS-00074 Lenine): a OS já está paga por inteiro e você não disse *mande*. Fale com Roberto." (por paga); a pergunta fecha com o motivo dela',
        pg_temp.equipe(v_rob) = 'ficha 2026-11-05 recusada/veto' and (select count(*) from public.whatsapp_send_queue) = v_n
        and (select a.texto || '|' || (a.depois ->> 'por') from public.agenda_acoes a where a.tipo = 'equipe' and a.origem = 'vigia'
              and a.payee_id = v_rob and a.depois ->> 'motivo' = 'ficha_segurada') = c_acao || '|paga'
        and (select q.estado || ':' || q.resolvida_motivo from public.agenda_perguntas q where q.id = v_q)
            = 'resolvida:a OS estava paga por inteiro e você não disse mande: a ficha não saiu',
        pg_temp.equipe(v_rob) || ' | ' || coalesce((select string_agg(a.texto || ' [' || (a.depois ->> 'por') || ']', ' | ') from public.agenda_acoes a where a.tipo = 'equipe'), '-'));
      r := public._agenda_rotina_confirmar(c_q05, pg_temp.em(c_q05, '07:45'));
      v_res := pg_temp.ok(v_res, 'F2e a confirmação da manhã de qui 05/11 também fica (recusada, veto)',
        pg_temp.equipe(v_rob) = 'ficha 2026-11-05 recusada/veto | confirmar 2026-11-05 recusada/veto', pg_temp.equipe(v_rob));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── F3. O *mande* solta; o *segure* segura; a 1 pelo prazo não solta ──
    begin
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      r2 := public.agenda_decidir(v_q, 1::smallint, v_adm, 'whatsapp', 'mande', c_qua, pg_temp.em(c_qua, '17:40'));
      v_ok := public._agenda_ficha_liberada(v_rob, c_q05, pg_temp.em(c_qua, '19:30'))
              and not public._agenda_ficha_liberada(v_rob, c_q05, pg_temp.em(c_qua, '17:39'));
      perform public._agenda_rotina_ficha(c_qua, pg_temp.em(c_qua, '19:30'));
      v_res := pg_temp.ok(v_res, 'F3a o *mande* do dono (1, pela conversa) solta a ficha da OS paga: "Combinado: mando a ficha de qui 05/11 para Roberto." e ela sai às 19:30 (antes da resposta, não soltava)',
        v_ok and r2 ->> 'texto' = 'Combinado: mando a ficha de qui 05/11 para Roberto.'
        and pg_temp.equipe(v_rob) = 'ficha 2026-11-05 enfileirada', r2::text || ' | ' || pg_temp.equipe(v_rob));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      r2 := public.agenda_decidir(v_q, 2::smallint, v_adm, 'whatsapp', 'segure', c_qua, pg_temp.em(c_qua, '17:40'));
      perform public._agenda_rotina_ficha(c_qua, pg_temp.em(c_qua, '19:30'));
      v_res := pg_temp.ok(v_res, 'F3b o *segure* (2) na OS paga: a ficha fica (recusada, veto), sem ação ao dono (ele sabe)',
        pg_temp.equipe(v_rob) = 'ficha 2026-11-05 recusada/veto'
        and not exists (select 1 from public.agenda_acoes a where a.tipo = 'equipe' and a.origem = 'vigia'), pg_temp.equipe(v_rob));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      -- a 1 gravada pelo canal do prazo (não é o dono): não solta
      update public.agenda_perguntas set estado = 'respondida', opcao_escolhida = 1, respondida_via = 'prazo',
             respondida_em = pg_temp.em(c_qua, '19:31'), mostrada_vezes = 1, mostrada_em = pg_temp.em(c_qua, '17:30'), mostrada_via = 'fechamento'
       where id = v_q;
      v_res := pg_temp.ok(v_res, 'F3c a 1 gravada pelo canal do prazo (não pelo dono) não solta a ficha da OS paga',
        not public._agenda_ficha_liberada(v_rob, c_q05, pg_temp.em(c_qua, '19:32')), null);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── F4. Fora da janela e sem o ligar do gestor ──
    begin
      update public.agenda_config set marcar_sozinho_desde = timestamptz '2026-10-01 16:46-03' where id;
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      v_t := r::text;
      begin
        perform public._agenda_rotina_ficha(c_qua, pg_temp.em(c_qua, '19:30'));
        v_t2 := pg_temp.equipe(v_rob);
        raise exception 'desfaz' using errcode = 'P0097';
      exception when sqlstate 'P0097' then null;
      end;
      v_res := pg_temp.ok(v_res, 'F4a fora da janela (o ligar de 01/10) e sem OS paga: o passo fichas pula ("fora da janela da ficha") e a ficha sai às 19:30 como antes',
        (r ->> 'pulado')::boolean and r ->> 'motivo' = 'fora da janela da ficha' and v_t2 = 'ficha 2026-11-05 enfileirada', v_t || ' | ' || v_t2);
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      v_t := (select q.texto from public.agenda_perguntas q where q.id = v_q);
      begin
        perform public._agenda_rotina_ficha(c_qua, pg_temp.em(c_qua, '19:30'));
        v_t2 := pg_temp.equipe(v_rob);
        raise exception 'desfaz' using errcode = 'P0097';
      exception when sqlstate 'P0097' then null;
      end;
      r2 := public.agenda_decidir(v_q, 1::smallint, v_adm, 'whatsapp', 'mande', c_qua, pg_temp.em(c_qua, '17:40'));
      perform public._agenda_rotina_ficha(c_qua, pg_temp.em(c_qua, '19:30'));
      v_res := pg_temp.ok(v_res, 'F4b fora da janela com a OS paga: a pergunta nasce (só para o Roberto, com o aviso); sem resposta a ficha fica; com o *mande*, sai',
        (r ->> 'perguntas')::int = 1 and r -> 'pessoas' -> 0 ->> 'pessoa' = v_rob::text and v_t = c_paga
        and v_t2 = 'ficha 2026-11-05 recusada/veto' and pg_temp.equipe(v_rob) = 'ficha 2026-11-05 enfileirada',
        r::text || ' | ' || coalesce(v_t2, '-') || ' | ' || pg_temp.equipe(v_rob));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      update public.agenda_config set marcar_sozinho_desde = null where id;
      r2 := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      perform public._agenda_rotina_ficha(c_qua, pg_temp.em(c_qua, '19:30'));
      v_res := pg_temp.ok(v_res, 'F4c sem o ligar do gestor: sem OS paga, o passo pula como antes ("o gestor ainda não marca sozinho"); com a OS paga, a pergunta nasce e a ficha sem resposta fica',
        (r2 ->> 'pulado')::boolean and r2 ->> 'motivo' like 'o gestor ainda não marca sozinho%'
        and (r ->> 'perguntas')::int = 1 and pg_temp.equipe(v_rob) = 'ficha 2026-11-05 recusada/veto',
        r2::text || ' | ' || r::text || ' | ' || pg_temp.equipe(v_rob));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── F5. Paga depois da pergunta ──
    begin
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '17:07'));
      v_q2 := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      r2 := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '17:23'));
      v_res := pg_temp.ok(v_res, 'F5a a OS ficou paga depois da pergunta: a aberta de padrão 1 fica resolvida ("a OS ficou paga por inteiro depois desta pergunta: perguntei de novo, avisando") e nasce a nova (padrão 2, com o aviso); o passo chamado de novo não repete (em produção roda 1x/dia)',
        v_q2 is distinct from v_q and (r ->> 'novas')::int = 1 and (r2 ->> 'novas')::int = 0 and r2 -> 'pessoas' -> 0 ->> 'pergunta_id' = v_q2::text
        and (select q.estado || ':' || q.resolvida_motivo from public.agenda_perguntas q where q.id = v_q)
            = 'resolvida:a OS ficou paga por inteiro depois desta pergunta: perguntei de novo, avisando'
        and (select q.estado || ':' || q.opcao_padrao || ':' || q.recomendacao || ':' || q.texto from public.agenda_perguntas q where q.id = v_q2)
            = 'aberta:2:2:' || c_paga
        and (select count(*) from public.agenda_perguntas q where q.tipo = 'ficha_estimativa') = 2,
        r::text || ' | ' || r2::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      r2 := public.agenda_decidir(v_q, 1::smallint, v_adm, 'whatsapp', 'mande', c_qua, pg_temp.em(c_qua, '17:10'));
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '17:23'));
      perform public._agenda_rotina_ficha(c_qua, pg_temp.em(c_qua, '19:30'));
      v_res := pg_temp.ok(v_res, 'F5b o *mande* dado antes de a OS ficar paga vale (a decisão do dono não volta a ser perguntada): a ficha sai',
        (select count(*) from public.agenda_perguntas q where q.tipo = 'ficha_estimativa') = 1
        and pg_temp.equipe(v_rob) = 'ficha 2026-11-05 enfileirada', r::text || ' | ' || pg_temp.equipe(v_rob));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── F6. O que conta como paga ──
    begin
      v_t := '';
      perform pg_temp.pagar(v_len, 100);
      v_t := v_t || public._agenda_os_paga_por_inteiro(v_len) || ',';
      perform pg_temp.pagar(v_len, null, 'cancelled');
      v_t := v_t || public._agenda_os_paga_por_inteiro(v_len) || ',';
      perform pg_temp.pagar(v_len);
      v_t := v_t || public._agenda_os_paga_por_inteiro(v_len) || ',';
      -- total 0: o gatilho de totais pode recalcular grand_total; o que vale é o que ficou gravado
      update public.service_orders set grand_total = 0 where id = v_len;
      v_t := v_t || case when (select so.grand_total from public.service_orders so where so.id = v_len) = 0
                         then public._agenda_os_paga_por_inteiro(v_len)::text else 'total-recalculado' end || ',';
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
              when others then v_t := v_t || 'ERRO(' || sqlerrm || '),';
    end;
    begin
      perform pg_temp.pagar(v_len);
      -- a OS concluída (o status gravado direto, só para a leitura: a porta faria mais coisas)
      alter table public.service_orders disable trigger user;
      update public.service_orders set status = 'completed' where id = v_len;
      alter table public.service_orders enable trigger user;
      v_t := v_t || public._agenda_os_paga_por_inteiro(v_len);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
              when others then v_t := v_t || 'ERRO(' || sqlerrm || ')';
    end;
    v_res := pg_temp.ok(v_res, 'F6 o que conta como paga: o sinal (parcial) não; a conta cancelada não soma; o que falta pago, sim; total 0 não; a OS concluída não',
      v_t = 'false,false,true,false,false', v_t);
    -- o replay sai daqui: o F7 o monta de novo
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then
    v_res := pg_temp.ok(v_res, 'F1-F6 sem erro', false, sqlstate || ': ' || sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$fx$;

-- ── F7. Sem OS paga, o de antes, byte a byte ────────────────────────────────────────────────────────────
do $f7$
declare
  v_res   jsonb := '[]'::jsonb;
  c_qua   constant date := date '2026-11-04';
  c_q05   constant date := date '2026-11-05';
  v_rob   uuid;
  v_joao  uuid;
  v_dono  uuid;
  d       date;
  p       uuid;
  h       text;
  v_n     int := 0;
  v_tot   int := 0;
  v_a     text;
  v_b     text;
  v_x     jsonb;
  v_y     jsonb;
  r       jsonb;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('F7 (o replay de 29/10)', true, 'PULADO: sem agenda_teste.replay2910 (rode pela bancada)');
    return;
  end if;
  execute replace(pg_temp.inteira(current_setting('agenda_teste.mig_protecoes_fase7a'), '_agenda_ficha_liberada'),
                  'create or replace function public._agenda_ficha_liberada(', 'create function pg_temp.liberada_antes(');
  execute replace(pg_temp.inteira(current_setting('agenda_teste.mig_correcao2_fase7a'), '_agenda_gestor_fichas'),
                  'create or replace function public._agenda_gestor_fichas(', 'create function pg_temp.fichas_antes(');
  execute replace(pg_temp.inteira(current_setting('agenda_teste.mig_equipe_fase7f'), '_agenda_rotina_ficha'),
                  'create or replace function public._agenda_rotina_ficha(', 'create function pg_temp.ficha_antes(');
  execute replace(pg_temp.inteira(current_setting('agenda_teste.mig_combinar_fase7d'), '_agenda_linhas_do_fechamento'),
                  'create or replace function public._agenda_linhas_do_fechamento(', 'create function pg_temp.linhas_antes(');
  begin
    perform pg_temp.fixtures();
    v_rob := pg_temp.pessoa('Roberto');
    v_joao := pg_temp.pessoa('João');
    v_dono := public._agenda_dono(null);
    -- (revisão adversarial) o João na rotina: no replay ele não está, e sem isto a ficha de ter 03/11 nem existia (o F7c de 30/10
    -- comparava o vazio)
    insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em)
    values (v_joao, true, 'dono', pg_temp.em(date '2026-10-20', '10:00'))
    on conflict (payee_id) do update set recebe_rotina = true, parou_em = null, parou_motivo = null;
    -- as perguntas de qua 04 (Roberto qui 05) e de sex 30/10 (João ter 03), a de qua 04 mostrada
    r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
    perform public.agenda_fechamento_registrar(c_qua,
      (select jsonb_agg(x) from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_qua)) x
        where x ->> 'pergunta_id' = r -> 'pessoas' -> 0 ->> 'pergunta_id'), 'fechamento', pg_temp.em(c_qua, '17:30'));
    perform public._agenda_gestor_fichas(date '2026-10-30', pg_temp.em(date '2026-10-30', '16:52'));
    -- F7a a liberada: as 3 pessoas, de qui 29/10 a qui 12/11, em 4 horas
    foreach p in array array[v_rob, v_joao, v_dono] loop
      for d in select g::date from generate_series(date '2026-10-29', date '2026-11-12', interval '1 day') g loop
        foreach h in array array['09:00', '17:31', '19:29', '19:31'] loop
          v_tot := v_tot + 1;
          if public._agenda_ficha_liberada(p, d, pg_temp.em(c_qua, h)) is distinct from pg_temp.liberada_antes(p, d, pg_temp.em(c_qua, h)) then
            v_n := v_n + 1;
          end if;
        end loop;
      end loop;
    end loop;
    v_res := pg_temp.ok(v_res, 'F7a sem OS paga, a liberada é a de antes em todo par (Roberto, João, o dono; qui 29/10 a qui 12/11; 4 horas), com perguntas mostradas e não',
      v_n = 0 and v_tot = 180, format('%s diferentes de %s', v_n, v_tot));
    -- F7b as linhas do fechamento (com a pergunta da ficha não paga): as de antes
    v_a := '';
    v_b := '';
    foreach d in array array[date '2026-10-29', date '2026-10-30', c_qua, c_q05] loop
      v_a := v_a || public._agenda_linhas_do_fechamento(d)::text;
      v_b := v_b || pg_temp.linhas_antes(d)::text;
    end loop;
    v_res := pg_temp.ok(v_res, 'F7b sem OS paga, as linhas do fechamento são as de antes, byte a byte (com a pergunta da ficha; qui 29/10, sex 30/10, qua 04 e qui 05/11)',
      v_a = v_b and length(v_a) > 200, md5(v_a) || ' / ' || md5(v_b));
    -- F7c a ficha das 19:30 (o João, ter 03, pergunta não mostrada: segura; o Roberto, qui 05, mostrada: sai): a de antes
    foreach d in array array[date '2026-10-30', c_qua] loop
      begin
        perform public._agenda_rotina_ficha(d, pg_temp.em(d, '19:30'));
        v_x := coalesce((select jsonb_agg(jsonb_build_array(m.payee_id, m.dia, m.tipo, m.estado, m.recusa_motivo, m.texto) order by m.payee_id, m.dia, m.tipo)
                           from public.agenda_equipe_mensagens m), '[]'::jsonb)
               || coalesce((select jsonb_agg(jsonb_build_array(a.tipo, a.payee_id, a.texto, a.depois - 'mensagem') order by a.payee_id, a.texto)
                              from public.agenda_acoes a where a.tipo = 'equipe'), '[]'::jsonb)
               || coalesce((select jsonb_agg(jsonb_build_array(q.chave, q.estado, q.resolvida_motivo) order by q.chave)
                              from public.agenda_perguntas q where q.tipo = 'ficha_estimativa'), '[]'::jsonb);
        raise exception 'desfaz' using errcode = 'P0097';
      exception when sqlstate 'P0097' then null;
      end;
      begin
        perform pg_temp.ficha_antes(d, pg_temp.em(d, '19:30'));
        v_y := coalesce((select jsonb_agg(jsonb_build_array(m.payee_id, m.dia, m.tipo, m.estado, m.recusa_motivo, m.texto) order by m.payee_id, m.dia, m.tipo)
                           from public.agenda_equipe_mensagens m), '[]'::jsonb)
               || coalesce((select jsonb_agg(jsonb_build_array(a.tipo, a.payee_id, a.texto, a.depois - 'mensagem') order by a.payee_id, a.texto)
                              from public.agenda_acoes a where a.tipo = 'equipe'), '[]'::jsonb)
               || coalesce((select jsonb_agg(jsonb_build_array(q.chave, q.estado, q.resolvida_motivo) order by q.chave)
                              from public.agenda_perguntas q where q.tipo = 'ficha_estimativa'), '[]'::jsonb);
        raise exception 'desfaz' using errcode = 'P0097';
      exception when sqlstate 'P0097' then null;
      end;
      v_res := pg_temp.ok(v_res, format('F7c sem OS paga, a ficha das 19:30 de %s é a de antes (as mensagens, a ação ao dono e a pergunta)', to_char(d, 'DD/MM')),
        v_x = v_y and jsonb_array_length(v_x) > 0
        and (d <> date '2026-10-30' or (v_x::text like '%ficha_segurada%' and v_x::text like '%Não mandei a ficha de ter 03/11 a João%')),
        left(v_x::text, 300) || ' / ' || left(v_y::text, 300));
    end loop;
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  -- F7d a pergunta: a de antes a menos do número da OS (o resultado e as perguntas gravadas), dentro e fora da janela e sem o ligar
  v_a := '';
  v_b := '';
  foreach h in array array['dentro', 'fora', 'sem_ligar'] loop
    foreach d in array array[date '2026-10-29', date '2026-10-30', c_qua, c_q05, date '2026-11-06'] loop
      begin
        perform pg_temp.fixtures();
        if h = 'fora' then update public.agenda_config set marcar_sozinho_desde = timestamptz '2026-10-01 16:46-03' where id; end if;
        if h = 'sem_ligar' then update public.agenda_config set marcar_sozinho_desde = null where id; end if;
        r := public._agenda_gestor_fichas(d, pg_temp.em(d, '16:52'));
        v_a := v_a || regexp_replace(((r - 'pessoas') || jsonb_build_object('n', jsonb_array_length(coalesce(r -> 'pessoas', '[]'::jsonb))))::text, 'OS-\d+ ', '', 'g')
               || coalesce((select string_agg(regexp_replace(format('%s|%s|%s|%s|%s|%s|%s', q.chave, q.texto, q.recomendacao, q.opcao_padrao, q.veto_ate, q.expira_em, q.perda_em), 'OS-\d+ ', '', 'g'), ';' order by q.chave)
                              from public.agenda_perguntas q where q.tipo = 'ficha_estimativa'), '-') || E'\n';
        raise exception 'desfaz' using errcode = 'P0097';
      exception when sqlstate 'P0097' then null;
      end;
      begin
        perform pg_temp.fixtures();
        if h = 'fora' then update public.agenda_config set marcar_sozinho_desde = timestamptz '2026-10-01 16:46-03' where id; end if;
        if h = 'sem_ligar' then update public.agenda_config set marcar_sozinho_desde = null where id; end if;
        r := pg_temp.fichas_antes(d, pg_temp.em(d, '16:52'));
        v_b := v_b || ((r - 'pessoas') || jsonb_build_object('n', jsonb_array_length(coalesce(r -> 'pessoas', '[]'::jsonb))))::text
               || coalesce((select string_agg(format('%s|%s|%s|%s|%s|%s|%s', q.chave, q.texto, q.recomendacao, q.opcao_padrao, q.veto_ate, q.expira_em, q.perda_em), ';' order by q.chave)
                              from public.agenda_perguntas q where q.tipo = 'ficha_estimativa'), '-') || E'\n';
        raise exception 'desfaz' using errcode = 'P0097';
      exception when sqlstate 'P0097' then null;
      end;
    end loop;
  end loop;
  v_res := pg_temp.ok(v_res, 'F7d sem OS paga, o passo fichas é o de antes a menos do número da OS no texto (qui 29/10 a sex 06/11; dentro e fora da janela e sem o ligar do gestor)',
    v_a = v_b and v_a like '%ficha_estimativa:%', md5(v_a) || ' / ' || md5(v_b) || ' | ' || left(v_a, 400) || ' || ' || left(v_b, 400));
  perform pg_temp.gravar(v_res);
end
$f7$;

-- ── F8 e F9. A revisão adversarial (os extras X1, X1b, X4, X5b, X6 da revisão; os mutantes M04, M08, M12, M13, M15, M16; o porquê; a
--    ordem da (m); o caminho real do *mande*) ──────────────────────────────────────────────────────────────────────────────────────
do $f8$
declare
  v_res   jsonb := '[]'::jsonb;
  c_qua   constant date := date '2026-11-04';
  c_q05   constant date := date '2026-11-05';
  v_len   uuid;
  v_van   uuid;
  v_rob   uuid;
  v_joao  uuid;
  v_adm   uuid;
  v_dono  uuid;
  v_q     uuid;
  v_q2    uuid;
  r       jsonb;
  r2      jsonb;
  r3      jsonb;
  v_t     text;
  v_ok    boolean;
  v_lin   jsonb;
  v_n     int;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('F8 e F9 (o replay de 29/10)', true, 'PULADO: sem agenda_teste.replay2910 (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.fixtures();
    v_len := pg_temp.os('OS-00074');
    v_van := pg_temp.os('OS-00069');
    v_rob := pg_temp.pessoa('Roberto');
    v_joao := pg_temp.pessoa('João');
    v_dono := public._agenda_dono(null);
    select u.id into v_adm from public.app_users u where u.role = 'admin' order by u.id limit 1;

    -- F8a (X1) o *mande* pelo painel sem respondida_por (o registro real de 17/11): solta
    begin
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      r2 := public.agenda_decidir(v_q, 1::smallint, null, 'painel', 'mande', c_qua, pg_temp.em(c_qua, '17:40'));
      perform public._agenda_rotina_ficha(c_qua, pg_temp.em(c_qua, '19:30'));
      v_t := (select q.estado || ':' || q.opcao_escolhida || ':' || q.respondida_via || ':' || coalesce(q.respondida_por::text, 'nulo')
                from public.agenda_perguntas q where q.id = v_q);
      v_res := pg_temp.ok(v_res, 'F8a (X1) o *mande* pelo painel, sem autor (como o de 17/11), solta a ficha da OS paga',
        pg_temp.equipe(v_rob) = 'ficha 2026-11-05 enfileirada' and v_t = 'respondida:1:painel:nulo', v_t || ' | ' || coalesce(pg_temp.equipe(v_rob), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- F8b (X1b) pela tela, com autor: solta
    begin
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      r2 := public.agenda_decidir(v_q, 1::smallint, v_adm, 'tela', 'mande', c_qua, pg_temp.em(c_qua, '17:40'));
      perform public._agenda_rotina_ficha(c_qua, pg_temp.em(c_qua, '19:30'));
      v_res := pg_temp.ok(v_res, 'F8b (X1b) o *mande* pela tela, com autor, solta',
        pg_temp.equipe(v_rob) = 'ficha 2026-11-05 enfileirada', coalesce(r2 ->> 'texto', '-') || ' | ' || coalesce(pg_temp.equipe(v_rob), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- F8c (X4) dia misto: o Roberto em qui 05 com a OS-00074 (PAGA) de manhã e a OS-00069 (não paga) à tarde; mostrada e sem resposta, fica
    begin
      alter table public.agenda_alocacoes disable trigger user;
      update public.agenda_alocacoes set service_order_id = v_van
       where payee_id = v_rob and dia = c_q05 and turno = 'tarde' and estado in ('publicada', 'fixada');
      alter table public.agenda_alocacoes enable trigger user;
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      perform public.agenda_fechamento_registrar(c_qua,
        (select jsonb_agg(x) from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_qua)) x where x ->> 'pergunta_id' = v_q::text),
        'fechamento', pg_temp.em(c_qua, '17:30'));
      perform public._agenda_rotina_ficha(c_qua, pg_temp.em(c_qua, '19:30'));
      v_res := pg_temp.ok(v_res, 'F8c (X4) dia misto (a OS paga de manhã, a não paga à tarde): mostrada e sem resposta, a ficha fica (a da outra OS junto)',
        pg_temp.equipe(v_rob) = 'ficha 2026-11-05 recusada/veto' and public._agenda_ficha_os_pagas(v_rob, c_q05) = array[v_len],
        coalesce(pg_temp.equipe(v_rob), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- F8d (X5b) duas pessoas fora da janela (o João na rotina, em qui 05 na OS-00069, não paga; o Roberto na OS-00074, paga): só o Roberto
    -- ganha a pergunta; a ficha do João sai, a do Roberto fica
    begin
      insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em)
      values (v_joao, true, 'dono', pg_temp.em(date '2026-10-20', '10:00'))
      on conflict (payee_id) do update set recebe_rotina = true, parou_em = null, parou_motivo = null;
      alter table public.agenda_alocacoes disable trigger user;
      update public.agenda_alocacoes set dia = c_q05, periodo = tstzrange(lower(periodo) - interval '7 days', upper(periodo) - interval '7 days', '[)')
       where payee_id = v_joao and dia = date '2026-11-12' and estado in ('publicada', 'fixada');
      alter table public.agenda_alocacoes enable trigger user;
      update public.agenda_config set marcar_sozinho_desde = timestamptz '2026-10-01 16:46-03' where id;
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      perform public._agenda_rotina_ficha(c_qua, pg_temp.em(c_qua, '19:30'));
      v_res := pg_temp.ok(v_res, 'F8d (X5b) duas pessoas fora da janela, só a do Roberto paga: 1 pergunta, só para o Roberto; a ficha do João sai, a do Roberto fica',
        (r ->> 'perguntas')::int = 1 and r -> 'pessoas' -> 0 ->> 'pessoa' = v_rob::text
        and pg_temp.equipe(v_joao) = 'ficha 2026-11-05 enfileirada' and pg_temp.equipe(v_rob) = 'ficha 2026-11-05 recusada/veto',
        'perguntas=' || coalesce(r ->> 'perguntas', '-') || ' | joao: ' || coalesce(pg_temp.equipe(v_joao), '-') || ' | rob: ' || coalesce(pg_temp.equipe(v_rob), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- F8e (X6) a alocação da OS paga foi cancelada (o dia da pessoa agora é de outra OS, não paga): a OS paga não conta mais
    begin
      alter table public.agenda_alocacoes disable trigger user;
      update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = pg_temp.em(c_qua, '10:00'), cancelada_motivo = 'replanejado'
       where payee_id = v_rob and dia = c_q05 and turno = 'manha' and estado in ('publicada', 'fixada');
      update public.agenda_alocacoes set service_order_id = v_van
       where payee_id = v_rob and dia = c_q05 and turno = 'tarde' and estado in ('publicada', 'fixada');
      alter table public.agenda_alocacoes enable trigger user;
      perform pg_temp.pagar(v_len);
      v_res := pg_temp.ok(v_res, 'F8e (X6) a alocação da OS paga cancelada não conta: _agenda_ficha_os_pagas vazia',
        public._agenda_ficha_os_pagas(v_rob, c_q05) = '{}'::uuid[], public._agenda_ficha_os_pagas(v_rob, c_q05)::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- F8f (M16) a pergunta da OS paga fechada sem opção (resolvida) não solta. A constraint respondida_coerente ((estado = 'respondida')
    -- = (respondida_em is not null), da Fase 2) faz toda resolvida ter respondida_em nulo — o teste confere que ela segue lá. O M16
    -- ("respondida ou resolvida, e não segurada, solta") NÃO é equivalente: uma respondida com a opção nula é possível (a ficha_estimativa
    -- não é crítica, e critica_decidida só vale para crítica) — o F8f2 abaixo o mata (conferência independente de 18/11, achado 4).
    begin
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      update public.agenda_perguntas set mostrada_vezes = 1, mostrada_em = pg_temp.em(c_qua, '17:30'), mostrada_via = 'fechamento' where id = v_q;
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste: fechada sem opção' where id = v_q;
      v_res := pg_temp.ok(v_res, 'F8f (M16) a pergunta da OS paga fechada sem opção (resolvida) não solta; e a constraint respondida_coerente (resolvida nunca tem hora de resposta) segue no banco',
        not public._agenda_ficha_liberada(v_rob, c_q05, pg_temp.em(c_qua, '19:30'))
        and exists (select 1 from pg_constraint c where c.conrelid = 'public.agenda_perguntas'::regclass and c.conname = 'respondida_coerente'
                     and pg_get_constraintdef(c.oid) like '%(estado = ''respondida''::text) = (respondida_em IS NOT NULL)%'),
        (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'public.agenda_perguntas'::regclass and c.conname = 'respondida_coerente'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- F8f2 (M16; o CONF-1 da conferência) respondida SEM opção (opção nula, pelo painel, com hora de resposta): não solta — só a 1 solta
    begin
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      update public.agenda_perguntas set estado = 'respondida', opcao_escolhida = null, respondida_via = 'painel',
             respondida_em = pg_temp.em(c_qua, '17:40'), mostrada_vezes = 1, mostrada_em = pg_temp.em(c_qua, '17:30'), mostrada_via = 'fechamento'
       where id = v_q;
      v_res := pg_temp.ok(v_res, 'F8f2 (M16) respondida sem opção (opção nula, pelo painel, com hora de resposta) não solta a ficha da OS paga',
        not public._agenda_ficha_liberada(v_rob, c_q05, pg_temp.em(c_qua, '19:30')),
        (select q.estado || ':' || coalesce(q.opcao_escolhida::text, 'nula') || ':' || q.critica from public.agenda_perguntas q where q.id = v_q));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- F8g (M13) a pergunta em teste (modo sombra), mesmo com a 1, não solta
    begin
      perform pg_temp.pagar(v_len);
      update public.agenda_config set modo_equipe = 'sombra' where id;
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      update public.agenda_perguntas set estado = 'respondida', opcao_escolhida = 1, respondida_via = 'whatsapp', respondida_por = v_adm,
             respondida_em = pg_temp.em(c_qua, '17:40'), resposta = 'mande', mostrada_vezes = 1, mostrada_em = pg_temp.em(c_qua, '17:30'),
             mostrada_via = 'fechamento'
       where id = v_q;
      update public.agenda_config set modo_equipe = 'ligado' where id;
      v_res := pg_temp.ok(v_res, 'F8g (M13) a pergunta em teste (sombra) respondida com a 1 não solta a ficha de verdade',
        (select q.modo from public.agenda_perguntas q where q.id = v_q) = 'sombra'
        and not public._agenda_ficha_liberada(v_rob, c_q05, pg_temp.em(c_qua, '19:30')),
        (select q.modo || ':' || q.estado from public.agenda_perguntas q where q.id = v_q));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- F8h (M04) o dono, com a OS paga no dia (ter 10/11 no Lenine), sempre tem a ficha
    begin
      perform pg_temp.pagar(v_len);
      v_res := pg_temp.ok(v_res, 'F8h (M04) o dono com OS paga no dia (ter 10/11) sempre tem a ficha',
        cardinality(public._agenda_ficha_os_pagas(v_dono, date '2026-11-10')) > 0
        and public._agenda_ficha_liberada(v_dono, date '2026-11-10', pg_temp.em(date '2026-11-09', '19:30')),
        public._agenda_ficha_os_pagas(v_dono, date '2026-11-10')::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- F8i (M08) faturada e cancelada não são "pagas a fazer"; em andamento, sim
    begin
      perform pg_temp.pagar(v_len);
      alter table public.service_orders disable trigger user;
      update public.service_orders set status = 'invoiced' where id = v_len;
      v_t := public._agenda_os_paga_por_inteiro(v_len)::text;
      update public.service_orders set status = 'cancelled' where id = v_len;
      v_t := v_t || ',' || public._agenda_os_paga_por_inteiro(v_len)::text;
      update public.service_orders set status = 'in_progress' where id = v_len;
      v_t := v_t || ',' || public._agenda_os_paga_por_inteiro(v_len)::text;
      alter table public.service_orders enable trigger user;
      v_res := pg_temp.ok(v_res, 'F8i (M08) faturada e cancelada não contam como paga a fazer; em andamento, sim', v_t = 'false,false,true', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- F8j (M12) a alocação que não é pela estimativa (os dias ditos pelo dono) não conta
    begin
      perform pg_temp.pagar(v_len);
      alter table public.agenda_alocacoes disable trigger user;
      update public.agenda_alocacoes set duracao_fonte = 'dono' where payee_id = v_rob and dia = c_q05 and estado in ('publicada', 'fixada');
      alter table public.agenda_alocacoes enable trigger user;
      v_res := pg_temp.ok(v_res, 'F8j (M12) a alocação com os dias ditos pelo dono (não pela estimativa) não conta como OS paga da ficha',
        public._agenda_ficha_os_pagas(v_rob, c_q05) = '{}'::uuid[], public._agenda_ficha_os_pagas(v_rob, c_q05)::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- F8k o porquê, sem pergunta (o pagamento depois do passo do dia): "e não consegui te perguntar antes das 19:30", por paga_sem_pergunta
    begin
      perform pg_temp.pagar(v_len);
      perform public._agenda_rotina_ficha(c_qua, pg_temp.em(c_qua, '19:30'));
      v_t := (select a.texto || ' [' || (a.depois ->> 'por') || ']' from public.agenda_acoes a
               where a.tipo = 'equipe' and a.payee_id = v_rob and a.depois ->> 'motivo' = 'ficha_segurada');
      v_res := pg_temp.ok(v_res, 'F8k o porquê sem pergunta: "… a OS já está paga por inteiro e não consegui te perguntar antes das 19:30. Fale com Roberto." (paga_sem_pergunta)',
        pg_temp.equipe(v_rob) = 'ficha 2026-11-05 recusada/veto'
        and v_t = 'Não mandei a ficha de qui 05/11 a Roberto (OS-00074 Lenine): a OS já está paga por inteiro e não consegui te perguntar antes das 19:30. Fale com Roberto. [paga_sem_pergunta]',
        coalesce(v_t, '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- F8l o porquê, pergunta não mostrada: "e você não viu a pergunta", por paga_nao_vista; a pergunta fecha com o motivo dela
    begin
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      perform public._agenda_rotina_ficha(c_qua, pg_temp.em(c_qua, '19:30'));
      v_t := (select a.texto || ' [' || (a.depois ->> 'por') || ']' from public.agenda_acoes a
               where a.tipo = 'equipe' and a.payee_id = v_rob and a.depois ->> 'motivo' = 'ficha_segurada');
      v_res := pg_temp.ok(v_res, 'F8l o porquê com a pergunta não mostrada: "… e você não viu a pergunta. Fale com Roberto." (paga_nao_vista); a pergunta fecha "… e você não viu a pergunta: a ficha não saiu"',
        v_t = 'Não mandei a ficha de qui 05/11 a Roberto (OS-00074 Lenine): a OS já está paga por inteiro e você não viu a pergunta. Fale com Roberto. [paga_nao_vista]'
        and (select q.estado || ':' || q.resolvida_motivo from public.agenda_perguntas q where q.id = v_q)
            = 'resolvida:a OS estava paga por inteiro e você não viu a pergunta: a ficha não saiu',
        coalesce(v_t, '-') || ' | ' || coalesce((select q.estado || ':' || q.resolvida_motivo from public.agenda_perguntas q where q.id = v_q), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- F8m na linha (m), a ficha paga vem antes da outra ficha do dia: o João (OS-00069, não paga) perguntado às 16:00, o Roberto (OS-00074)
    -- refeito às 16:52, depois de pago — pela ordem de antes (a mais velha primeiro), o João sairia inteiro e o Roberto só como "Também …"
    begin
      insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em)
      values (v_joao, true, 'dono', pg_temp.em(date '2026-10-20', '10:00'))
      on conflict (payee_id) do update set recebe_rotina = true, parou_em = null, parou_motivo = null;
      alter table public.agenda_alocacoes disable trigger user;
      update public.agenda_alocacoes set dia = c_q05, periodo = tstzrange(lower(periodo) - interval '7 days', upper(periodo) - interval '7 days', '[)')
       where payee_id = v_joao and dia = date '2026-11-12' and estado in ('publicada', 'fixada');
      alter table public.agenda_alocacoes enable trigger user;
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:00'));
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      v_q := (select q.id from public.agenda_perguntas q where q.chave = format('ficha_estimativa:%s:%s', v_rob, c_q05) and q.estado = 'aberta');
      v_n := (select count(*) from public.agenda_perguntas q where q.tipo = 'ficha_estimativa' and q.estado = 'aberta');
      v_lin := public._agenda_linhas_do_fechamento(c_qua);
      v_t := (select x ->> 'texto' from jsonb_array_elements(v_lin) x where x ->> 'tipo' = 'pergunta' and (x ->> 'perda')::int = 76 limit 1);
      v_res := pg_temp.ok(v_res, 'F8m na linha (m), a ficha da OS paga vem antes da outra ficha do dia (inteira, com o aviso), e a curta é a dela',
        v_n = 2 and v_t like 'Agenda: Hoje às 19:30 a ficha de amanhã vai para Roberto: OS-00074 Lenine, qui 05/11%já está PAGA por inteiro%'
        and exists (select 1 from jsonb_array_elements(v_lin) x where x ->> 'pergunta_id' = v_q::text
                     and x ->> 'texto_curto' like '%eu seguro a ficha. Para mandar, me diga *mande*.%'),
        'abertas=' || v_n || ' | ' || coalesce(left(v_t, 260), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- F8n (M19; o CONF-2 da conferência) OS paga e a pessoa sem telefone: a ficha fica e o porquê é o de antes ("Roberto não tem telefone
    -- no cadastro", por sem_telefone) — sem telefone o gestor nem pergunta, e a ficha não sairia de todo jeito
    begin
      perform pg_temp.pagar(v_len);
      update public.payees set phone = null where id = v_rob;
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      perform public._agenda_rotina_ficha(c_qua, pg_temp.em(c_qua, '19:30'));
      v_t := (select a.texto || ' [' || (a.depois ->> 'por') || ']' from public.agenda_acoes a
               where a.tipo = 'equipe' and a.payee_id = v_rob and a.depois ->> 'motivo' = 'ficha_segurada');
      v_res := pg_temp.ok(v_res, 'F8n (M19) OS paga e a pessoa sem telefone: a ficha fica e o porquê é o de antes ("Roberto não tem telefone no cadastro", sem_telefone)',
        pg_temp.equipe(v_rob) = 'ficha 2026-11-05 recusada/veto' and v_t like '%Roberto não tem telefone no cadastro%[sem_telefone]',
        coalesce(pg_temp.equipe(v_rob), '-') || ' | ' || coalesce(v_t, '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- F9a o caminho real do dono, sozinha na lista: a ferramenta agenda_aplicar (agenda_rascunho_aplicar, opção 1) deixa o rascunho; o
    -- *grava* (agenda_rascunho_gravar) responde a pergunta pelo canal whatsapp; às 19:30 a ficha da OS paga sai
    begin
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste: só a ficha na lista' where estado = 'aberta' and id <> v_q;
      r := public.agenda_rascunho_aplicar(v_adm, 'whatsapp', null, null, null, '1', 'mande', c_qua, pg_temp.em(c_qua, '17:41'));
      perform set_config('agenda.agora', pg_temp.em(c_qua, '17:42')::text, true);
      r2 := public.agenda_rascunho_gravar(v_adm, c_qua);
      perform public._agenda_rotina_ficha(c_qua, pg_temp.em(c_qua, '19:30'));
      v_t := (select q.estado || ':' || q.opcao_escolhida || ':' || q.respondida_via from public.agenda_perguntas q where q.id = v_q);
      v_res := pg_temp.ok(v_res, 'F9a o caminho real, sozinha na lista: agenda_aplicar (opção 1, "mande") deixa o rascunho; o *grava* responde ("Combinado: mando a ficha de qui 05/11 para Roberto."); às 19:30 a ficha da OS paga sai',
        coalesce((r ->> 'ok')::boolean, false) and r2 ->> 'texto' like '%Combinado: mando a ficha de qui 05/11 para Roberto.%'
        and v_t = 'respondida:1:whatsapp' and pg_temp.equipe(v_rob) = 'ficha 2026-11-05 enfileirada',
        left(r::text, 200) || ' | ' || left(coalesce(r2::text, '-'), 300) || ' | ' || coalesce(v_t, '-') || ' | ' || coalesce(pg_temp.equipe(v_rob), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- F9b com duas decisões esperando (a ficha do João e a do Roberto): só a opção, sem dizer qual decisão, recusa; com os dois números nas
    -- palavras do dono, a do Roberto é respondida e a ficha dele sai
    begin
      insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em)
      values (v_joao, true, 'dono', pg_temp.em(date '2026-10-20', '10:00'))
      on conflict (payee_id) do update set recebe_rotina = true, parou_em = null, parou_motivo = null;
      alter table public.agenda_alocacoes disable trigger user;
      update public.agenda_alocacoes set dia = c_q05, periodo = tstzrange(lower(periodo) - interval '7 days', upper(periodo) - interval '7 days', '[)')
       where payee_id = v_joao and dia = date '2026-11-12' and estado in ('publicada', 'fixada');
      alter table public.agenda_alocacoes enable trigger user;
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      v_q := (select q.id from public.agenda_perguntas q where q.chave = format('ficha_estimativa:%s:%s', v_rob, c_q05) and q.estado = 'aberta');
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste: só as 2 fichas na lista'
       where estado = 'aberta' and tipo <> 'ficha_estimativa';
      v_n := (select (d ->> 'n')::int from jsonb_array_elements(public.agenda_decisoes_abertas(pg_temp.em(c_qua, '17:41'))) d where d ->> 'id' = v_q::text);
      r := public.agenda_rascunho_aplicar(v_adm, 'whatsapp', null, null, null, '1', 'mande', c_qua, pg_temp.em(c_qua, '17:41'));
      r3 := public.agenda_rascunho_aplicar(v_adm, 'whatsapp', null, null, v_n::text, '1', format('na %s, a 1', v_n), c_qua, pg_temp.em(c_qua, '17:41'));
      perform set_config('agenda.agora', pg_temp.em(c_qua, '17:42')::text, true);
      r2 := public.agenda_rascunho_gravar(v_adm, c_qua);
      perform public._agenda_rotina_ficha(c_qua, pg_temp.em(c_qua, '19:30'));
      v_res := pg_temp.ok(v_res, 'F9b com 2 decisões esperando: só "mande" (sem dizer qual) recusa; "na N, a 1" responde a do Roberto e a ficha dele sai',
        v_n is not null and not coalesce((r ->> 'ok')::boolean, false) and coalesce((r3 ->> 'ok')::boolean, false)
        and r2 ->> 'texto' like '%Combinado: mando a ficha de qui 05/11 para Roberto.%' and pg_temp.equipe(v_rob) = 'ficha 2026-11-05 enfileirada',
        'n=' || coalesce(v_n::text, '-') || ' | só mande: ' || left(r::text, 200) || ' | com números: ' || left(r3::text, 160) || ' | grava: '
        || left(coalesce(r2::text, '-'), 200) || ' | ' || coalesce(pg_temp.equipe(v_rob), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- F9c com 2 esperando, as palavras dizem a pessoa e o mande, sem número ("mande a ficha do Roberto"), e o modelo achou a decisão
    -- pela lista: vale (_agenda_disse_em_palavras) — a releitura nomeia a pergunta do Roberto e pede o *grava*
    begin
      insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em)
      values (v_joao, true, 'dono', pg_temp.em(date '2026-10-20', '10:00'))
      on conflict (payee_id) do update set recebe_rotina = true, parou_em = null, parou_motivo = null;
      alter table public.agenda_alocacoes disable trigger user;
      update public.agenda_alocacoes set dia = c_q05, periodo = tstzrange(lower(periodo) - interval '7 days', upper(periodo) - interval '7 days', '[)')
       where payee_id = v_joao and dia = date '2026-11-12' and estado in ('publicada', 'fixada');
      alter table public.agenda_alocacoes enable trigger user;
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      v_q := (select q.id from public.agenda_perguntas q where q.chave = format('ficha_estimativa:%s:%s', v_rob, c_q05) and q.estado = 'aberta');
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste: só as 2 fichas na lista'
       where estado = 'aberta' and tipo <> 'ficha_estimativa';
      v_n := (select (d ->> 'n')::int from jsonb_array_elements(public.agenda_decisoes_abertas(pg_temp.em(c_qua, '17:41'))) d where d ->> 'id' = v_q::text);
      r := public.agenda_rascunho_aplicar(v_adm, 'whatsapp', null, null, v_n::text, '1', 'mande a ficha do Roberto', c_qua, pg_temp.em(c_qua, '17:41'));
      v_res := pg_temp.ok(v_res, 'F9c com 2 esperando, "mande a ficha do Roberto" (o modelo achou a decisão pela lista): vale — a releitura nomeia a pergunta do Roberto, "Mande", e pede o *grava*',
        coalesce((r ->> 'ok')::boolean, false) and r ->> 'item' like '%vai para Roberto: OS-00074 Lenine%: Mande'
        and r ->> 'releitura' like '%Responda *grava*%', left(r::text, 400));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then
    v_res := pg_temp.ok(v_res, 'F8-F9 sem erro', false, sqlstate || ': ' || sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$f8$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
