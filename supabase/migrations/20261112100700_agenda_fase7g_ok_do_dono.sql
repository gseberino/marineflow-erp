-- Agenda de Produção, Fase 7, etapa 7g ("Mostrar como pensou e provar o trabalho"), pacote P5b: o "espera o seu ok". O tipo de OS em que o dono corrige muito o
-- que o gestor marca passa a reservar e perguntar "Pode marcar assim?" antes de valer; sem resposta no prazo, fica marcado; volta a marcar sozinho depois de 3
-- marcações seguidas sem correção; *desfaz espera* volta na hora.
-- Spec: scratchpad agenda-pesquisa/spec-fase7g.md (§3.1 item 8, §5.5, §6.4, K4 a K10 da §8.3 e o bloco R9, que vale sobre o corpo: R9.4-4 e os 7 pontos, R9.5-23
-- a 25, R9.6, R9.12, R9.13 — "R9.4-4; R9.5-23 a 25; agenda_desfazer_dito de 20261111100600"); o registro do pacote: notas-fase7g.md (seção P5b). Depende das
-- Fases 1 a 6, das etapas 7a a 7d, da 7f inteira (veto_tipos, o prazo, _agenda_fala_modo, _agenda_padrao_da_pergunta), da 7e inteira e da 7g até o P7
-- (20261112100000: modo_rebaixar, os parâmetros do rebaixar e agenda_tipos_os; 20261112100400: a rodada explicar; 20261112100500: a saúde; 20261112100600: a tela).
--
-- A VERSÃO: o mapa (R9.2) dava 20261112100450 "desde que nada recrie depois dele o que ele recria". Este pacote recria _agenda_saude_explicar (a 100500, do P6) e
-- agenda_tela_semana (a 100600, do P7), e a 7g é aplicada arquivo por arquivo, na ordem do nome: com 100450, a do P6 e a do P7 apagariam os blocos daqui. Vale
-- 20261112100700, a 1ª da faixa de correções (100700..100980), antes do dado 20261112100990, com o corpo MAIS NOVO de cada uma (o do P5, P6, P7, da 7f e da 7e).
-- Nenhuma migration de nome maior (as 20261113*, 20261116* e 20261123*) recria as 11.
--
-- ═══ DDL — OK NOMEADO ═══ (3 listas ampliadas; a coluna gerada critica; 3 colunas e 1 CHECK em os_planejamento; 4 funções novas; 11 recriadas)
-- NÃO APLICADA. Existe para revisão e espera o OK.
--
-- POR QUE (AG7-25, a regra aprovada pelo dono): "Se você corrigir metade das minhas marcações num tipo de serviço (pelo menos 3 em 8 semanas), passo a esperar o
-- seu ok nele; volto a marcar sozinho depois de 3 seguidas sem correção". O P5 mede e diz em teste o que faria (agenda_tipos_os.teria); faltava o ok de verdade.
--
-- O QUE MUDA (só com modo_rebaixar LIGADO e, para a classe passar a esperar, também o gestor marcando sozinho e o veto ligados; desligado ou em sombra, nada que
-- o dono veja: o motor, as leituras e o que se grava são os de antes, byte a byte, no replay da carteira real, f7g/p5b/real.mjs. Fora de ligado, de propósito:
-- a chave explicar da saúde ganha 2 zeros (ok_sem_pergunta, nivel_sem_aviso: 0 sem reserva ok_do_dono e sem nível); a rodada explicar faz 1 consulta a mais por
-- tique (há pergunta ok_marcacao aberta?); e a OS que seria classe 2 pelo orçamento faz 1 leitura por chave (_agenda_espera_ok) — o R9.8 pedia 0 SQL novo na
-- vigia fora de ligado, o que não dá sem ler o modo; a mitigação é a dele, só depois de nada mais segurar a OS e com a fonte orcamento):
--   1. As listas: agenda_perguntas.tipo + ok_marcacao (e a coluna gerada critica, por SET EXPRESSION, copiando a expressão da 7d); agenda_alocacoes.condicao_tipo
--      + ok_do_dono; agenda_acoes.tipo + nivel. os_planejamento + espera_ok_desde, ok_do_dono_em, ok_do_dono_via (dono | prazo) e o CHECK os_planejamento_ok_coerente.
--   2. _agenda_espera_ok(os) (nova): a OS espera o ok? modo_rebaixar, modo_veto e modo_marcar_sozinho ligados, CRUS (R9.6: com *gestor, só propor* a reserva fica),
--      e a linha de os_planejamento com espera_ok_desde e sem ok_do_dono_em; OS sem linha = não (R9.4-4 ponto 2). Uma leitura por chave.
--   3. _agenda_classe_da_os (recriada de 20261101100300_agenda_fase7b_motor.sql:800; md5 do corpo de antes 06aa24fb0049f269d39787434c3aceeb): a OS que seria classe 2 com os dias pelo orçamento e que espera o ok é classe 3,
--      motivo espera, condição ok_do_dono (R9.4-4 pontos 1, 3, 4 e 5); depois do "Não marca", classe 4 duracao.
--   4. _agenda_condicao_da_reserva (recriada de 20261025100200_agenda_fase2_motor.sql:3682; md5 do corpo de antes 63b22e85a316102edad939f2e57ae53c): "se você der o ok até <dia>", nunca antes do prazo da pergunta (ponto 6).
--   5. _agenda_explicar_ok (nova): a cada tique, a reserva ok_do_dono sem pergunta ganha a pergunta ok_marcacao (crítica, 1) Pode marcar assim, 2) Não marca: eu
--      digo os dias; recomendação 1; o padrão e o prazo da 7f), e a pergunta que ficou sem a reserva fecha (resolvida).
--   6. _agenda_padrao_da_pergunta (recriada de 20261109100000_agenda_fase7f_base.sql:377; md5 do corpo de antes 4c2024d1cb4ed7f252e09adaa7351615) e _agenda_modo_da_pergunta (recriada de
--      20261107100000_agenda_fase7d_tabelas.sql:601; md5 do corpo de antes 40a78627108f025a6caaa035df768927): ok_marcacao na tabela da 7f (recomendação, opção; cliente com prometido) e no modo_rebaixar cru (R9.5-23).
--   7. agenda_decidir (recriada de 20261109100100_agenda_fase7f_perguntas.sql:791; md5 do corpo de antes 108125fc0e603c9f9077d019f6767809) → _agenda_ok_decidir (nova): 1 grava ok_do_dono_em (via dono, ou prazo) e a reserva vira
--      compromisso pelo caminho da vigia (_agenda_propor_e_aplicar); 2 solta a reserva (soltar_reserva, origem dono, crítica) e pergunta os dias (duracao).
--   8. _agenda_explicar_tipos (recriada de 20261112100400_agenda_fase7g_correcoes.sql:303; md5 do corpo de antes c43c683a81b2419c4470f7f511d2a731): o nível de verdade (a ação nivel, desfazível pelo *desfaz espera*; a volta com
--      voltar_n aceitas seguidas), as respostas "Não marca" na amostra e o espera_ok_desde das OS da carteira da classe ainda sem dia marcado.
--   9. agenda_desfazer (recriada de 20261109100100_agenda_fase7f_perguntas.sql:1036; md5 do corpo de antes 7a138b9382d5fc4289de0b770a70fa55) → _agenda_desfazer_nivel (nova), e agenda_desfazer_dito (recriada de
--      20261111100600_agenda_fase7e_rodada.sql:2600; md5 do corpo de antes f90e5d978ac75a1e05c56f2bb128042d, a da 7e P7): *desfaz espera* volta o tipo de OS a sozinho, sem o prazo de 24 h, e trava por rebaixar_trava_dias (ponto 7).
--  10. agenda_explicar_rodar (recriada de 20261112100400_agenda_fase7g_correcoes.sql:376; md5 do corpo de antes 49c8737529162699e8c26e9b7aa1e769): o passo ok a cada tique; _agenda_saude_explicar (recriada de
--      20261112100500_agenda_fase7g_placar.sql:848; md5 do corpo de antes 1be352347492cf36427707bd3ca87606): os zeros ok_sem_pergunta e nivel_sem_aviso; agenda_tela_semana (recriada de 20261112100600_agenda_fase7g_tela.sql:493; md5 do corpo de antes 1491d1fc43940ccf0d0a6dd8cbdf3a9a):
--      "Reserva, esperando o seu ok".
--
-- O QUE NÃO MUDA: nenhum texto novo ao cliente nem à equipe (a reserva não avisa ninguém, AG7-09); nada de dinheiro; o aviso do gestor e as peças do aviso (lista
-- fechada, R9.5-25: a ação nivel chega pelo "o que mudou", pelo fechamento e por *agenda pendências*; a pergunta, pelo lote da 7f). Não recria
-- _agenda_vigia_reservas, _agenda_vigia_duracao_material, _agenda_mudancas, _agenda_gestor_motivo_texto, agenda_aplicar nem _agenda_aplicar_planejar (R9.1).
-- Não toca agenda_cliente_mensagens, agenda_cliente_respostas, a leitura da resposta do cliente nem cliente_resposta_validade. Não muda veto_tipos: quem põe
-- ok_marcacao lá é o dado 20261112100990.
--
-- ORDEM DE LIGAR (spec R9.14): depois da 20261112100600 e antes do dado 20261112100990. Aplicar sozinha não muda nada: modo_rebaixar fica como estiver. O "espera
-- o seu ok" liga com "OK ligar o espera o seu ok" (modo_rebaixar ligado), só com o freio solto, o plano limpo e o prazo nas perguntas da 7f dado. O roteiro em
-- linguagem do dono: fila-do-dono/fase7g-oks.md.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7g_ok_do_dono.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261112100700
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; pelo publicar/exec/aplicar.sh, nunca db push: esta versão fica antes das 20261116* que já estão em produção):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261112100700_agenda_fase7g_ok_do_dono.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261112100700', 'agenda_fase7g_ok_do_dono');"
--
-- DESFAZER: as 11 recriadas voltam pelo corpo das origens (acima); as 4 novas: drop function; as listas e as colunas ficam (nada as usa com modo_rebaixar fora
-- de ligado).
--
-- IDEMPOTENTE: add column if not exists, o CHECK e a expressão só se faltam, o ampliador só soma o que falta, create or replace function e comment.

-- ── 1. As listas, a coluna gerada e o lugar do ok na OS ─────────────────────────────────────────────

select public._agenda_ampliar_lista('public.agenda_perguntas', 'agenda_perguntas_tipo_check', 'tipo', array['ok_marcacao']);
select public._agenda_ampliar_lista('public.agenda_alocacoes', 'agenda_alocacoes_condicao_tipo_check', 'condicao_tipo', array['ok_do_dono']);
select public._agenda_ampliar_lista('public.agenda_acoes', 'agenda_acoes_tipo_check', 'tipo', array['nivel']);

-- ok_marcacao passa a ser crítica (a decisão "Pode marcar assim?", com 2 opções e a recomendação: critica_tem_opcoes passa a valer para ela). SET EXPRESSION
-- (Postgres 17+, o molde da 7d, 20261107100000): a expressão de hoje (a da 7d: os 13 tipos) + ok_marcacao, só se ainda não a tem.
do $$
begin
  if exists (select 1
               from pg_attribute a
               join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
              where a.attrelid = 'public.agenda_perguntas'::regclass and a.attname = 'critica' and a.attgenerated = 's'
                and pg_get_expr(d.adbin, d.adrelid) not like '%''ok_marcacao''%') then
    if current_setting('server_version_num')::int < 170000 then
      raise exception 'agenda_perguntas.critica: esta migration precisa do Postgres 17 ou mais novo (ALTER COLUMN … SET EXPRESSION); este é o %.',
        current_setting('server_version');
    end if;
    alter table public.agenda_perguntas alter column critica set expression as
      (tipo in ('nao_cabe','segundo_atraso','atraso_longo','remarcar_confirmado','fixada_pelo_dono','diaria','cliente_aviso',
                'aprendizado','onda','dia_avisado','dia_prometido','sabado','acesso','ok_marcacao'));
  end if;
end
$$;

-- O ok por OS (§4.2). Só a rodada explicar (espera_ok_desde) e a decisão do dono (ok_do_dono_*) escrevem; nenhum *grava* as toca. Nulas: só 4 de 131 OS têm a linha,
-- e quem lê usa coalesce por fora (R9.4-4 ponto 2).
alter table public.os_planejamento
  add column if not exists espera_ok_desde timestamptz,
  add column if not exists ok_do_dono_em   timestamptz,
  add column if not exists ok_do_dono_via  text check (ok_do_dono_via in ('dono', 'prazo'));

do $$
begin
  if not exists (select 1 from pg_constraint where conrelid = 'public.os_planejamento'::regclass and conname = 'os_planejamento_ok_coerente') then
    alter table public.os_planejamento add constraint os_planejamento_ok_coerente check ((ok_do_dono_em is null) = (ok_do_dono_via is null));
  end if;
end
$$;

comment on column public.os_planejamento.espera_ok_desde is
  'Agenda de Produção (Fase 7g, P5b; AG7-25): desde quando a OS espera o ok do dono antes de valer (o tipo de OS dela está em espera_ok). A rodada explicar grava e limpa; o *desfaz espera* limpa.';
comment on column public.os_planejamento.ok_do_dono_em is
  'Agenda de Produção (Fase 7g, P5b): quando o dono deu o ok à marcação da OS (a opção 1 da pergunta ok_marcacao, ou o prazo dela).';
comment on column public.os_planejamento.ok_do_dono_via is
  'Agenda de Produção (Fase 7g, P5b): dono (respondeu 1) ou prazo (ficou com a recomendação sem resposta).';

-- ── 2. As 4 funções novas ───────────────────────────────────────────────────────────────────────────

-- A OS espera o ok do dono? O modo CRU (R9.6: se lesse o freio, *gestor, só propor* faria a OS voltar à classe 2 e a vigia promoveria todas as reservas à espera,
-- o contrário do que ele pediu) e a linha. Sem a linha, não (coalesce por fora: R9.4-4 ponto 2, R9.12-3).
create or replace function public._agenda_espera_ok(p_os uuid)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce((select c.modo_rebaixar = 'ligado' and c.modo_veto = 'ligado' and c.modo_marcar_sozinho = 'ligado'
                          and pl.espera_ok_desde is not null and pl.ok_do_dono_em is null
                     from public.agenda_config c
                     join public.os_planejamento pl on pl.service_order_id = p_os
                    where c.id), false);
$function$;

comment on function public._agenda_espera_ok(uuid) is
  'Agenda de Produção (Fase 7g, P5b; §5.5, R9.4-4, R9.6): a OS espera o ok do dono antes de valer? modo_rebaixar, modo_veto e modo_marcar_sozinho ligados, CRUS (com *gestor, só propor* a reserva fica), e os_planejamento.espera_ok_desde gravado sem ok_do_dono_em. OS sem linha = false. Uma leitura por chave. Quem chama: _agenda_classe_da_os (só depois de nada mais segurar a OS e com a fonte orcamento). STABLE, invoker; execute para authenticated e service_role (a cadeia das leituras do painel passa por _agenda_classe_da_os).';

-- O passo ok da rodada explicar (a cada tique): a pergunta de cada reserva ok_do_dono e o fecho da pergunta que ficou sem reserva.
create or replace function public._agenda_explicar_ok(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf    public.agenda_config := public._agenda_cfg();
  r     record;
  v_cri int := 0;
  v_fec int := 0;
  v_n   int;
  v_txt text;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_explicar_ok: sem o dia ou a hora' using errcode = '22004';
  end if;
  -- 1. a pergunta aberta sem a reserva ok_do_dono vigente da OS (a vigia soltou, a reserva virou marcação, o tipo de OS voltou a marcar sozinho, o modo saiu de
  --    ligado): fecha, resolvida (§5.5). Em qualquer modo: a pergunta não fica aberta à toa em *agenda pendências*.
  update public.agenda_perguntas q
     set estado = 'resolvida', resolvida_motivo = 'a reserva saiu da agenda'
   where q.tipo = 'ok_marcacao' and q.estado = 'aberta'
     and not exists (select 1 from public.agenda_alocacoes a
                      where a.service_order_id = q.service_order_id and a.tipo = 'reserva' and a.condicao_tipo = 'ok_do_dono'
                        and a.estado in ('publicada', 'fixada') and a.resultado is null and a.dia >= p_hoje);
  get diagnostics v_fec = row_count;
  -- 2. a reserva ok_do_dono vigente sem pergunta aberta nem uma nascida depois dela: a pergunta nasce (só com modo_rebaixar ligado), crítica e ligada, uma por OS e
  --    dia da reserva (a chave), on conflict do nothing (R9.5-24; _agenda_gestor_perguntar não serve). O padrão e o prazo são da 7f: o gatilho agenda_perguntas_padrao
  --    preenche, e o prazo nasce quando ela for mostrada (o bloco, a mensagem da quinta).
  if cf.modo_rebaixar = 'ligado' then
    for r in select a.service_order_id as os, min(a.dia) as de, min(a.condicao_ate) as ate, min(a.criado_em) as pub,
                    array_agg(distinct a.dia) as dias,
                    count(distinct (a.dia, a.turno)) filter (where a.presenca = 'turno') as meios,
                    array_agg(distinct a.payee_id) filter (where a.presenca = 'turno') as pessoas
               from public.agenda_alocacoes a
              where a.tipo = 'reserva' and a.condicao_tipo = 'ok_do_dono' and a.estado in ('publicada', 'fixada') and a.resultado is null and a.dia >= p_hoje
              group by a.service_order_id order by 1 loop
      continue when exists (select 1 from public.agenda_perguntas q
                             where q.tipo = 'ok_marcacao' and q.service_order_id = r.os and (q.estado = 'aberta' or q.criada_em >= r.pub));
      v_txt := format('Reservei %s de %s com %s (%s pelo orçamento, estimativa minha). Nas OS de %s eu espero o seu ok. 1) Pode marcar assim (recomendo); 2) Não marca: eu digo os dias.',
                      public._agenda_rotulo_da_os(r.os), public._agenda_dias_texto(r.dias),
                      coalesce(nullif(public._agenda_lista(array(select public._agenda_nome_curto(py.name) from public.payees py
                                                                  where py.id = any (coalesce(r.pessoas, '{}'::uuid[])) order by 1)), ''), 'a equipe'),
                      public._agenda_meios_texto(r.meios::int),
                      coalesce(public._agenda_classe_de_campo(r.os) ->> 'texto', 'deste tipo'));
      insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, dia, perda_em, texto, opcoes, recomendacao, modo, criada_em)
      values ('ok_marcacao', format('ok_marcacao:%s:%s', r.os, (r.pub at time zone 'America/Sao_Paulo')::date), r.os, array[r.os], r.de, r.ate,
              left(v_txt, 600),
              jsonb_build_array(jsonb_build_object('n', 1, 'texto', 'Pode marcar assim'), jsonb_build_object('n', 2, 'texto', 'Não marca: eu digo os dias')),
              1, 'ligado', p_agora)
      on conflict (chave, modo) where estado = 'aberta' do nothing;
      get diagnostics v_n = row_count;
      v_cri := v_cri + v_n;
    end loop;
  end if;
  return jsonb_build_object('criadas', v_cri, 'fechadas', v_fec);
end;
$function$;

comment on function public._agenda_explicar_ok(date, timestamptz) is
  'Agenda de Produção (Fase 7g, P5b; §5.5, §6.4, R9.5-24): o passo ok da rodada explicar, a cada tique. (1) Em qualquer modo, a pergunta ok_marcacao aberta cuja OS não tem mais reserva ok_do_dono vigente fecha (resolvida, "a reserva saiu da agenda"). (2) Com modo_rebaixar ligado, cada OS com reserva ok_do_dono vigente sem pergunta ok_marcacao aberta nem nascida depois da reserva ganha a pergunta (crítica, ligada, chave ok_marcacao:<os>:<dia da reserva>, dia = o 1º dia, perda_em = condicao_ate, opções 1 "Pode marcar assim" e 2 "Não marca: eu digo os dias", recomendação 1; texto "Reservei <OS> de <dias> com <pessoas> (<n dias> pelo orçamento, estimativa minha). Nas OS de <classe> eu espero o seu ok. 1) …; 2) …."), on conflict do nothing; o padrão e o prazo, da 7f. {criadas, fechadas}. 22004 sem o dia ou a hora. Invoker, só service_role (quem chama é agenda_explicar_rodar).';

-- A decisão da pergunta ok_marcacao (§5.5, §6.4), chamada por agenda_decidir (definer) depois das portas dela: o canal, a trava do plano, a pergunta travada e,
-- pelo prazo, a porta da 7f (o veto efetivo ligado e o que não pode vencer).
create or replace function public._agenda_ok_decidir(p_pergunta uuid, p_opcao smallint, p_autor uuid, p_via text, p_trecho text,
                                                     p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_q     public.agenda_perguntas%rowtype;
  v_opc   jsonb;
  v_os    uuid;
  v_rot   text;
  v_nome  text;
  v_r     jsonb;
  v_dias  date[];
  v_pes   text;
  v_prazo text;
  v_ids   uuid[];
  v_alocs jsonb;
  v_cond  text;
  v_cate  date;
  v_fix   boolean;
  v_va    bigint;
  v_acao  uuid;
  v_tem   boolean;
  v_estado text;
  v_msg   text;
begin
  select * into v_q from public.agenda_perguntas where id = p_pergunta;
  if not found or v_q.tipo is distinct from 'ok_marcacao' then
    raise exception 'Não encontrei essa pergunta.' using errcode = 'P0002';
  end if;
  if v_q.estado <> 'aberta' then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta já foi respondida ou resolvida.');
  end if;
  if v_q.modo <> 'ligado' or coalesce(public._agenda_modo_da_pergunta(v_q.tipo, v_q.chave), 'desligado') <> 'ligado' then
    return jsonb_build_object('ok', false, 'texto', 'O "espero o seu ok" ainda está em teste: mostro como ficaria, mas não mudo nada.');
  end if;
  select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
  if v_opc is null then
    return jsonb_build_object('ok', false,
      'texto', 'Essa opção não existe. As opções são: '
               || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int) from jsonb_array_elements(v_q.opcoes) o) || '.');
  end if;
  v_os := v_q.service_order_id;
  v_rot := public._agenda_rotulo_da_os(v_os);
  v_nome := coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so join public.clients cl on cl.id = so.client_id where so.id = v_os),
                     'esse serviço');
  update public.agenda_perguntas
     set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
         respondida_por = p_autor, respondida_via = p_via
   where id = p_pergunta;
  -- a linha de os_planejamento pode não existir (R9.4-4 ponto 2)
  insert into public.os_planejamento (service_order_id) values (v_os) on conflict (service_order_id) do nothing;

  if p_opcao = 1 then
    update public.os_planejamento
       set ok_do_dono_em = p_agora, ok_do_dono_via = case when p_via = 'prazo' then 'prazo' else 'dono' end
     where service_order_id = v_os;
    -- a reserva vira compromisso pelo caminho de sempre (o da vigia com a classe 2: _agenda_propor_e_aplicar, origem vigia); o que não couber agora, ou se a
    -- proposta falhar, fica para a vigia do próximo tique (a OS já não espera o ok). A falha vai a app_error_logs (explicar:ok) e o ok fica gravado.
    begin
      v_r := public._agenda_propor_e_aplicar('os', array[v_os], 'vigia', null, p_hoje, p_agora);
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      perform public.log_app_error('db', format('explicar, ok dado e a marcação não saiu: %s', v_msg), 'agenda', 'explicar:ok', 'error',
                                   jsonb_build_object('passo', 'ok_decidir', 'sqlstate', v_estado, 'os', v_os, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
    v_dias := array(select distinct a.dia from public.agenda_alocacoes a
                     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje order by 1);
    v_pes := nullif(public._agenda_lista(array(select distinct public._agenda_nome_curto(py.name)
                                                 from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
                                                where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                                                  and a.dia >= p_hoje and a.presenca = 'turno' order by 1)), '');
    v_prazo := case when p_via <> 'prazo' then null
                    when v_q.veto_ate is null then 'Sem resposta'
                    else format('Sem resposta até %s às %s', public._dia_curto((v_q.veto_ate at time zone 'America/Sao_Paulo')::date),
                                to_char(v_q.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI')) end;
    -- só diz que ficou marcado o que ficou (R9.12-9); o *desfaz <nome>* não entra: a reserva voltaria e a vigia a promoveria de novo (R9.12-6)
    return jsonb_build_object('ok', true, 'promovida', cardinality(v_dias) > 0, 'acoes', v_r -> 'acoes',
      'texto', case when cardinality(v_dias) > 0 and v_prazo is null
                    then format('Combinado: %s fica marcado de %s com %s.', v_rot, public._agenda_dias_texto(v_dias), coalesce(v_pes, 'a equipe'))
                    when cardinality(v_dias) > 0
                    then format('%s: %s ficou marcado de %s com %s. Se não for assim, me diga os dias.', v_prazo, v_rot,
                                public._agenda_dias_texto(v_dias), coalesce(v_pes, 'a equipe'))
                    when v_prazo is null
                    then format('Combinado: anotei o seu ok para %s; marco assim que couber na agenda.', v_rot)
                    else format('%s: anotei o ok para %s; marco assim que couber na agenda.', v_prazo, v_rot) end);
  end if;

  -- 2: solta a reserva (o caminho do soltar_reserva da vigia, com o motivo dono, a ação crítica com a pergunta) e pergunta os dias (o caminho da vigia:
  -- _agenda_vigia_perguntar duracao). espera_ok_desde fica: até o dono dizer os dias, a OS espera (classe 4 duracao em _agenda_classe_da_os), sem reservar de novo.
  select array_agg(a.id order by a.dia, a.turno = 'tarde', a.payee_id, a.id),
         jsonb_agg(jsonb_build_object('alocacao_id', a.id, 'payee_id', a.payee_id, 'dia', a.dia, 'turno', a.turno, 'presenca', a.presenca,
                                      'estado', a.estado, 'fixado_por', a.fixado_por) order by a.dia, a.turno = 'tarde', a.payee_id, a.id),
         (array_agg(a.condicao order by a.dia, a.turno = 'tarde', a.id))[1], min(a.condicao_ate), bool_or(a.estado = 'fixada')
    into v_ids, v_alocs, v_cond, v_cate, v_fix
    from public.agenda_alocacoes a
   where a.service_order_id = v_os and a.tipo = 'reserva' and a.condicao_tipo = 'ok_do_dono' and a.estado in ('publicada', 'fixada')
     and a.resultado is null and a.dia >= p_hoje;
  if coalesce(cardinality(v_ids), 0) > 0 then
    v_va := (public._agenda_cfg()).versao_plano;
    if v_fix then perform set_config('agenda.mexe_fixado', 'on', true); end if;
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'dono'
     where id = any (v_ids) and estado in ('publicada', 'fixada');
    perform set_config('agenda.mexe_fixado', 'off', true);
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, pergunta_id, critica, versao_antes, versao_depois,
                                     alocacoes_canceladas, antes, depois, texto, motivo, autor)
    values (clock_timestamp(), p_hoje, true, 'dono', 'soltar_reserva', v_os, array[v_os], p_pergunta, true, v_va, (public._agenda_cfg()).versao_plano,
            v_ids, jsonb_build_object('alocacoes', v_alocs, 'condicao', v_cond, 'condicao_ate', v_cate), '{}'::jsonb,
            left(format('%s: tirei a reserva de %s, como você disse.', v_rot,
                        public._agenda_dias_texto(array(select (x ->> 'dia')::date from jsonb_array_elements(v_alocs) x))), 400),
            'dono', p_autor)
    returning id into v_acao;
  end if;
  perform public._agenda_vigia_perguntar('duracao', 'duracao:' || v_os, v_os, null, null, null,
    format('Quantos dias leva %s, e com quem? Você disse para eu não marcar pelo orçamento.', v_rot), cf.modo_vigia, p_agora, false);
  v_tem := exists (select 1 from public.agenda_perguntas q where q.chave = 'duracao:' || v_os and q.estado = 'aberta' and q.modo = 'ligado');
  return jsonb_build_object('ok', true, 'acao_id', v_acao,
    'texto', case when v_acao is null then format('Certo: não marco %s.', v_nome) else format('Certo: tirei a reserva de %s.', v_nome) end
             || case when v_tem then ' Me diga quantos dias e com quem (está em *agenda pendências*).' else ' Me diga quantos dias e com quem.' end);
end;
$function$;

comment on function public._agenda_ok_decidir(uuid, smallint, uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 7g, P5b; §5.5, §6.4, R9.4-4): a decisão da pergunta ok_marcacao, chamada por agenda_decidir. Aberta e com o modo dela (modo_rebaixar) ligado, senão a recusa com a saída. 1: os_planejamento.ok_do_dono_em = agora e ok_do_dono_via (prazo pelo prazo da 7f, senão dono; a linha nasce se falta) e a reserva vira compromisso por _agenda_propor_e_aplicar(os, origem vigia); o texto só diz "fica marcado de … com …" com o meio-dia vigente de verdade, senão "marco assim que couber". 2: solta a reserva ok_do_dono vigente (cancelada, motivo dono; a ação soltar_reserva de origem dono, crítica, com a pergunta, sem desfazer), espera_ok_desde fica, e pergunta os dias (_agenda_vigia_perguntar duracao, no modo da vigia): "Certo: tirei a reserva de <nome>. Me diga quantos dias e com quem (está em *agenda pendências*)." Invoker, só service_role.';

-- O *desfaz* da ação nivel (§6.4, R9.4-4 ponto 7), chamado por agenda_desfazer (definer) depois das portas dela (executada, não desfeita, não é um desfazer).
create or replace function public._agenda_desfazer_nivel(p_acao uuid, p_autor uuid, p_via text, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf     public.agenda_config := public._agenda_cfg();
  v_a    public.agenda_acoes%rowtype;
  v_t    public.agenda_tipos_os%rowtype;
  v_cls  text;
  v_ctxt text;
  v_txt  text;
  v_acao uuid;
  v_n    int;
begin
  select * into v_a from public.agenda_acoes where id = p_acao;
  if not found or v_a.tipo is distinct from 'nivel' then
    raise exception 'Não encontrei essa mudança.' using errcode = 'P0002';
  end if;
  v_cls := v_a.antes ->> 'classe';
  select * into v_t from public.agenda_tipos_os where classe = v_cls for update;
  v_ctxt := coalesce((select public._agenda_classe_de_campo(m.service_order_id) ->> 'texto' from public.agenda_marcacoes m
                       where m.classe = v_cls order by m.marcada_em desc, m.acao_id desc limit 1), v_cls);
  -- a volta a sozinho não se desfaz: ela veio das marcações aceitas, e voltar a esperar é com uma correção nova (a saída)
  if v_a.depois ->> 'nivel' is distinct from 'espera_ok' then
    return jsonb_build_object('ok', false,
      'texto', format('Isso não se desfaz: voltei a marcar sozinho nas OS de %s porque as minhas últimas marcações nelas ficaram como fiz. Se eu errar de novo e você corrigir, volto a esperar o seu ok.', v_ctxt));
  end if;
  -- nada mudou desde a ação: o nível de hoje é o que ela pôs
  if v_t.classe is null or v_t.acao_id is distinct from v_a.id or v_t.nivel is distinct from 'espera_ok' then
    return jsonb_build_object('ok', false,
      'texto', format('Não desfaço: depois disso o nível das OS de %s já mudou. Hoje eu %s nelas.', v_ctxt,
                      case when v_t.nivel = 'espera_ok' then 'espero o seu ok' else 'marco sozinho' end));
  end if;
  update public.agenda_tipos_os t
     set nivel = 'sozinho', desde = null, travado_ate = p_hoje + cf.rebaixar_trava_dias, texto = null,
         historico = public._os_material_historico(t.historico, jsonb_build_object('em', p_agora, 'antes', jsonb_build_object('nivel', 'espera_ok'),
                       'depois', jsonb_build_object('nivel', 'sozinho', 'travado_ate', p_hoje + cf.rebaixar_trava_dias), 'acao', v_a.id, 'por', 'dono'))
   where t.classe = v_cls;
  -- as OS da classe que esperavam o ok voltam (a reserva ok_do_dono delas: classe 2, e a vigia a promove no próximo tique)
  update public.os_planejamento pl set espera_ok_desde = null
   where pl.espera_ok_desde is not null and pl.ok_do_dono_em is null
     and public._agenda_classe_de_campo(pl.service_order_id) ->> 'chave' = v_cls;
  get diagnostics v_n = row_count;
  v_txt := format('Desfeito: volto a marcar sozinho nas OS de %s. Não passo a esperar o seu ok nelas de novo por %s dias.', v_ctxt, cf.rebaixar_trava_dias);
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, os_ids, critica, antes, depois, texto, autor, desfaz_a)
  values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer', '{}', false,
          jsonb_build_object('acao', v_a.id), v_a.antes || jsonb_build_object('travado_ate', p_hoje + cf.rebaixar_trava_dias), left(v_txt, 400), p_autor, v_a.id)
  returning id into v_acao;
  update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_a.id;
  return jsonb_build_object('ok', true, 'texto', v_txt, 'acao_id', v_acao, 'os_soltas', v_n, 'recriadas', '[]'::jsonb, 'canceladas', '[]'::jsonb);
end;
$function$;

comment on function public._agenda_desfazer_nivel(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 7g, P5b; §6.4, R9.4-4 ponto 7): o desfazer da ação nivel, chamado por agenda_desfazer, sem o prazo de 24 h (desfazivel_ate) nem OS. A ida a espera_ok: com o nível ainda o dela (agenda_tipos_os.acao_id = a ação), a classe volta a sozinho, travada até hoje + rebaixar_trava_dias (o teria não volta a espera_ok antes), as OS da classe perdem espera_ok_desde (as sem o ok), a ação desfazer e a ação marcada desfeita: "Desfeito: volto a marcar sozinho nas OS de <classe>. Não passo a esperar o seu ok nelas de novo por 28 dias." Mudou depois = "Não desfaço…". A volta a sozinho não se desfaz (a recusa diz o caminho). Invoker, só service_role.';

-- ── 3. As recriadas ─────────────────────────────────────────────────────────────────────────────────

-- _agenda_classe_da_os (de 20261101100300_agenda_fase7b_motor.sql:800; md5 do corpo de antes 06aa24fb0049f269d39787434c3aceeb)
create or replace function public._agenda_classe_da_os(p_pront jsonb, p_meios jsonb, p_hoje date,
                                                       p_tem_fixada boolean default false,
                                                       p_fora_do_horizonte boolean default false)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_est   text := p_pront ->> 'estado';
  v_r     jsonb := coalesce(p_pront -> 'restricoes', '[]'::jsonb);
  v_mat   text := p_pront #>> '{material,estado}';
  v_crit  jsonb;
  v_trava jsonb;
  v_cond  text[] := '{}';
  v_txt   text;
  v_mat_trava boolean;
  -- FASE 7: (7a correção 2, a dupla sem a 2ª pessoa) quantas pessoas o meio-dia pede e quem a grade tem
  v_f72_n    int;
  v_f72_tec  text[];
  -- FASE 7: fim
  -- FASE 7b: (7b P4, R4.3(b)) quantas pessoas a dupla dita pede num passo
  v_7b_n    int;
  -- FASE 7b: fim
begin
  if not coalesce((p_pront ->> 'ok')::boolean, false) then
    return jsonb_build_object('classe', 4, 'motivo', 'nao_achei', 'texto', 'não encontrei esse serviço');
  end if;
  if v_est in ('concluida', 'fora_da_carteira') then
    return jsonb_build_object('classe', 4, 'motivo', 'fora_da_carteira', 'texto', p_pront ->> 'estado_texto');
  end if;
  if v_est = 'congelada' then
    return jsonb_build_object('classe', 4, 'motivo', 'congelada', 'texto', p_pront ->> 'estado_texto');
  end if;

  select coalesce(jsonb_agg(e order by o), '[]'::jsonb) into v_crit
    from jsonb_array_elements(coalesce(p_pront #> '{material,itens}', '[]'::jsonb)) with ordinality t(e, o)
   where coalesce((e ->> 'critico')::boolean, true) and e ->> 'nivel' is distinct from 'A';

  -- Material que trava de vez (nem reserva): previsão vencida, ou falta sem previsão que não é compra já combinada.
  v_mat_trava := v_mat = 'atrasado'
     or (v_mat = 'sem_previsao' and exists (
           select 1 from jsonb_array_elements(v_crit) e
            where coalesce((e ->> 'sem_data')::boolean, false)
              and not (e ->> 'situacao' = 'falta' and coalesce((e ->> 'compra_prevista_em')::date >= p_hoje, false))));

  -- Em execução (ou com meio-dia fixado): compromisso primeiro, se o material deixa.
  if v_est in ('em_execucao', 'parada') or p_tem_fixada then
    if v_mat_trava then
      select e into v_trava from jsonb_array_elements(v_r) with ordinality t(e, o)
       where e ->> 'tipo' in ('atrasado', 'sem_previsao', 'comprado_sem_previsao') order by o limit 1;
      return jsonb_build_object('classe', 4, 'motivo', 'material',
                                'texto', coalesce(v_trava ->> 'texto', p_pront ->> 'estado_texto'));
    end if;
    -- FASE 7: (7a P3, regra situacao; AG7-11, §3.3 d6) a OS em andamento sem os dias ditos e sem plano (situacao_pendente de
    -- agenda_meios_da_os, só com a regra estimativa) também espera o "quanto falta?" antes de entrar no plano: sem isso, o motor
    -- a marcaria com a estimativa inteira (só a sugerida existe)
    if p_meios ->> 'situacao_pendente' = 'true' then
      return jsonb_build_object('classe', 4, 'motivo', 'situacao',
                                'texto', coalesce((select e ->> 'texto' from jsonb_array_elements(v_r) with ordinality t(e, o)
                                                    where e ->> 'tipo' = 'situacao' order by o limit 1), p_pront ->> 'estado_texto'));
    end if;
    -- FASE 7: fim
    return jsonb_build_object('classe', 1, 'motivo', case when p_tem_fixada then 'fixada' else 'em_execucao' end,
                              'texto', p_pront ->> 'estado_texto');
  end if;

  -- O que trava antes do material (quem destrava primeiro): orçamento, sinal, cliente, escopo; o bem ou o "não antes de"
  -- além do horizonte; depois o material que trava de vez.
  select e into v_trava from jsonb_array_elements(v_r) with ordinality t(e, o)
   where e ->> 'tipo' in ('orcamento', 'sinal', 'cliente', 'escopo') order by o limit 1;
  -- FASE 7: (7a P12, regra sinal_cobrar; AG7-09 "marco e cobro o sinal", spec §R1 e §5.12) o sinal combinado e não pago não
  -- trava: a OS segue para a classe que teria sem ele (o compromisso, se o resto estiver pronto) — nada de reserva por sinal,
  -- e condicao_tipo não ganha 'sinal' — e o gestor lembra o dono de cobrar quando ela ganha dia (_agenda_gestor_sinal). O que
  -- trava depois do sinal na mesma lista (o orçamento, o cliente, o escopo) continua travando. Sem a regra, a de antes.
  if v_trava ->> 'tipo' = 'sinal' and public._agenda_gestor_regra('sinal_cobrar') then
    select e into v_trava from jsonb_array_elements(v_r) with ordinality t(e, o)
     where e ->> 'tipo' in ('orcamento', 'cliente', 'escopo') order by o limit 1;
  end if;
  -- FASE 7: fim
  if v_trava is not null then
    return jsonb_build_object('classe', 4, 'motivo', v_trava ->> 'tipo', 'texto', v_trava ->> 'texto');
  end if;
  -- FASE 7b: (7b P4, R4.3(b)) a dupla DITA pelo dono (fonte dono: o tempo todo, no início ou no fim — a dita no início ou no fim
  -- a correção 2 não via, o desejado dela é 1) com modo_dupla fora de desligado (o dk só existe assim): pede o maior dk dos passos que
  -- restam (o dono que conta como uma das pessoas sai da conta); com menos técnicos na grade (_agenda_tecnicos_da_grade: com quem
  -- vem sob demanda, R4.3(c)) espera o dono, classe 4 dupla — também em teste: sem isso a dita no início sairia do plano calada. A
  -- dupla inferida pela tarefa (fonte regra) nunca segura a OS: vai com 1 pessoa (o encaixe).
  if p_meios ? 'dk' and p_meios #>> '{dupla,fonte}' = 'dono' and not coalesce((p_meios ->> 'equipe_dita')::boolean, false) then
    v_7b_n := coalesce((select max(x::int) from jsonb_array_elements_text(p_meios -> 'dk') x), 0)
              - case when coalesce((p_meios ->> 'dk_dono_conta')::boolean, true)
                          and (coalesce((p_meios #>> '{dono_turno,manha}')::boolean, false)
                               or coalesce((p_meios #>> '{dono_turno,tarde}')::boolean, false)) then 1 else 0 end;
    if v_7b_n >= 2 then
      v_f72_tec := public._agenda_tecnicos_da_grade(p_hoje);
      if cardinality(v_f72_tec) < v_7b_n then
        return jsonb_build_object('classe', 4, 'motivo', 'dupla',
          'texto', format('precisa de %s pessoas e %s: chame um ajudante e me diga os dias dele', v_7b_n,
                          public._agenda_tecnicos_frase(v_f72_tec)));
      end if;
    end if;
  end if;
  -- FASE 7b: fim
  -- FASE 7: (7a correção 2, a dupla sem a 2ª pessoa; AG7-04 e fase7-padroes: "o gestor SUGERE quando chamar (ex.: dupla
  -- necessária)") com a regra uma_pessoa, a OS que o dono disse que vai com dupla (um meio-dia que pede 2 pessoas em
  -- agenda_meios_da_os, sem a equipe dita) e a grade com menos técnicos do que isso espera o dono: classe 4, motivo dupla. Antes,
  -- com o Alex sozinho, o motor a tirava do plano calado ("sem lugar") e ela nunca voltava. A grade só é lida quando a OS pede 2.
  if public._agenda_gestor_regra('uma_pessoa') and not coalesce((p_meios ->> 'equipe_dita')::boolean, false) then
    v_f72_n := greatest(coalesce((p_meios #>> '{por_turno,manha,desejado}')::int, 0),
                        coalesce((p_meios #>> '{por_turno,tarde,desejado}')::int, 0));
    if v_f72_n >= 2 then
      v_f72_tec := public._agenda_tecnicos_da_grade(p_hoje);
      if cardinality(v_f72_tec) < v_f72_n then
        return jsonb_build_object('classe', 4, 'motivo', 'dupla',
          'texto', format('precisa de %s pessoas e %s: chame um ajudante e me diga os dias dele', v_f72_n,
                          public._agenda_tecnicos_frase(v_f72_tec)));
      end if;
    end if;
  end if;
  -- FASE 7: fim
  if p_fora_do_horizonte then
    select e into v_trava from jsonb_array_elements(v_r) with ordinality t(e, o)
     where e ->> 'tipo' in ('bem', 'nao_antes') order by o limit 1;
    return jsonb_build_object('classe', 4, 'motivo', 'bem', 'texto', coalesce(v_trava ->> 'texto', p_pront ->> 'estado_texto'));
  end if;
  if v_mat_trava then
    select e into v_trava from jsonb_array_elements(v_r) with ordinality t(e, o)
     where e ->> 'tipo' in ('atrasado', 'sem_previsao', 'comprado_sem_previsao') order by o limit 1;
    return jsonb_build_object('classe', 4, 'motivo', 'material',
                              'texto', coalesce(v_trava ->> 'texto', p_pront ->> 'estado_texto'));
  end if;
  -- FASE 7: (7a P3) o que o gestor não marca sem perguntar antes (as chaves de agenda_meios_da_os, que só existem com a regra
  -- estimativa): a OS começada ou parada (situacao_pendente, AG7-11) e a estimativa que ele não usa sozinho — acima de
  -- estimativa_max_diarias, com peça embutida ou sem mão de obra separada (estimativa_motivo, com a fonte ainda 'sugerida').
  -- Antes de "sem base para estimar" (que, sem a regra, continua 'duracao'); o P4 pergunta por estes dois motivos.
  if p_meios ->> 'situacao_pendente' = 'true' then
    return jsonb_build_object('classe', 4, 'motivo', 'situacao',
                              'texto', coalesce((select e ->> 'texto' from jsonb_array_elements(v_r) with ordinality t(e, o)
                                                  where e ->> 'tipo' = 'situacao' order by o limit 1), p_pront ->> 'estado_texto'));
  end if;
  if p_meios ->> 'estimativa_motivo' in ('grande', 'embutida', 'sem_base') and p_meios ->> 'fonte' = 'sugerida' then
    return jsonb_build_object('classe', 4, 'motivo', 'estimativa',
                              'texto', coalesce((select e ->> 'texto' from jsonb_array_elements(v_r) with ordinality t(e, o)
                                                  where e ->> 'tipo' = 'duracao' order by o limit 1),
                                                'quantos dias e com quem? (o orçamento não dá base para estimar)'));
  end if;
  -- FASE 7: fim
  if coalesce((p_meios ->> 'sem_base')::boolean, false) or (p_meios ->> 'total') is null then
    return jsonb_build_object('classe', 4, 'motivo', 'duracao',
                              'texto', 'quantos dias e com quem? (o orçamento não dá base para estimar)');
  end if;

  -- O que só deixa reservar (classe 3), do que mais trava ao que menos.
  if exists (select 1 from jsonb_array_elements(v_crit) e where e ->> 'nivel' = 'D' and e ->> 'situacao' = 'falta') then
    v_cond := v_cond || 'compra'::text;
  end if;
  -- FASE 7: (7a P3, regra compra_firme; D7-2, AG7-07) a peça a comprar com "compre até" (vivo ou gravado) abaixo do teto de
  -- empurrões não segura a OS na reserva: ela fica no compromisso e a compra é cobrada (o item vem marcado compra_firme pela
  -- os_prontidao). Só sai a condição quando TODA falta de nível D é firme.
  if 'compra' = any (v_cond) and public._agenda_gestor_regra('compra_firme')
     and not exists (select 1 from jsonb_array_elements(v_crit) e
                      where e ->> 'nivel' = 'D' and e ->> 'situacao' = 'falta'
                        and not coalesce((e ->> 'compra_firme')::boolean, false)) then
    v_cond := array_remove(v_cond, 'compra'::text);
  end if;
  -- FASE 7: fim
  if v_mat = 'sem_previsao'
     or exists (select 1 from jsonb_array_elements(v_crit) e
                 where e ->> 'nivel' = 'D' and e ->> 'situacao' in ('comprado', 'a_caminho')) then
    v_cond := v_cond || 'material'::text;
  end if;
  if v_mat = 'nao_conferido' then
    v_cond := v_cond || 'conferir_material'::text;
  end if;
  if p_meios ->> 'fonte' = 'sugerida' then
    v_cond := v_cond || 'duracao'::text;
  end if;
  if cardinality(v_cond) = 0 then
    -- FASE 7g: (7g P5b; §5.5, R9.4-4 pontos 1, 3, 4 e 5) o tipo de OS que espera o ok do dono (agenda_tipos_os.nivel espera_ok, gravado na OS em
    -- os_planejamento.espera_ok_desde pela rodada explicar): a OS pronta com os dias pelo orçamento (fonte orcamento) só reserva, condição ok_do_dono, até o dono
    -- dizer 1 na pergunta ok_marcacao ou o prazo dela vencer (agenda_decidir). Só aqui, depois de nada mais segurar a OS (v_cond vazio) e com fonte orcamento:
    -- antes disso, nenhuma consulta nova (R9.8). _agenda_espera_ok lê o modo cru e a linha (R9.6): com *gestor, só propor* a reserva fica. A OS vem de
    -- p_pront (os_prontidao tem a chave os). Motivo espera, que o "de fora" já diz ("esperando a sua decisão"). Com a opção 2 ("Não marca: eu digo os dias")
    -- dada desde que a OS passou a esperar, ela espera os dias do dono (classe 4 duracao), sem reservar e perguntar de novo a cada replano.
    if p_meios ->> 'fonte' = 'orcamento' and public._agenda_espera_ok((p_pront ->> 'os')::uuid) then
      if exists (select 1 from public.agenda_perguntas q
                  join public.os_planejamento pl on pl.service_order_id = q.service_order_id
                 where q.service_order_id = (p_pront ->> 'os')::uuid and q.tipo = 'ok_marcacao' and q.estado = 'respondida'
                   and q.opcao_escolhida = 2 and q.respondida_em >= pl.espera_ok_desde) then
        return jsonb_build_object('classe', 4, 'motivo', 'duracao',
                                  'texto', 'quantos dias e com quem? (você disse para eu não marcar pelo orçamento)');
      end if;
      return jsonb_build_object('classe', 3, 'motivo', 'espera', 'condicao_tipo', 'ok_do_dono', 'condicoes', jsonb_build_array('ok_do_dono'),
                                'texto', 'espero o seu ok');
    end if;
    -- FASE 7g: fim
    return jsonb_build_object('classe', 2, 'motivo', 'pronta', 'texto', p_pront ->> 'estado_texto');
  end if;

  select e ->> 'texto' into v_txt from jsonb_array_elements(v_r) with ordinality t(e, o)
   where e ->> 'tipo' = any (case v_cond[1]
           when 'compra' then array['compre_ate', 'sem_previsao']
           when 'material' then array['compra_sem_prazo', 'comprado_sem_previsao', 'sem_previsao']
           when 'conferir_material' then array['peca_embutida', 'material_nao_conferido']
           else array['duracao'] end)
   order by o limit 1;
  return jsonb_build_object('classe', 3, 'motivo', v_cond[1], 'condicao_tipo', v_cond[1], 'condicoes', to_jsonb(v_cond),
                            'texto', coalesce(v_txt, p_pront ->> 'estado_texto'));
end;
$function$;

comment on function public._agenda_classe_da_os(jsonb, jsonb, date, boolean, boolean) is
  'Agenda de Produção (Fase 2, P2): a classe da OS para o motor, pelas restrições de os_prontidao e o molde de agenda_meios_da_os — 1 = em execução/parada ou com meio-dia fixado (compromisso, primeiro); 2 = pronta: dias ditos ou aceitos, sem orçamento/sinal/cliente/escopo travando e todo crítico em A, B ou C (compromisso); 3 = o que falta é só compra (D falta, o "compre até"), material comprado sem previsão ou compra combinada sem prazo, conferir o material (zero linhas ou peça embutida) ou dias só sugeridos (só reserva condicionada; condicao_tipo na ordem compra > material > conferir_material > duracao); 4 = nunca: fora da carteira, em espera, material atrasado ou sem previsão, orçamento, sinal, cliente, escopo, o bem ou o "não antes de" além do horizonte, sem base para os dias. {classe, motivo, texto (quem trava), condicao_tipo}. FASE 7 (7a P3), com as chaves de agenda_meios_da_os que só existem com a regra estimativa: a OS começada ou parada (situacao_pendente; também a em andamento sem plano nem dias) = classe 4 situacao; a estimativa que o gestor não usa sozinho (estimativa_motivo grande, embutida ou sem_base, com a fonte sugerida) = classe 4 estimativa, antes do "sem base" (que sem a regra continua duracao); com a regra compra_firme, a falta de nível D com compra_firme (os_prontidao) não entra na condição compra (a OS fica no compromisso). Sem o portão, a de antes. FASE 7 (7a P12; AG7-09 "marco e cobro o sinal"): com a regra sinal_cobrar, o sinal combinado e não pago sai da trava de antes do material e não entra em condição nenhuma (condicao_tipo não ganha sinal): a OS fica na classe que teria sem ele (o compromisso, se o resto estiver pronto); o orçamento, o cliente e o escopo continuam travando. O gestor lembra o dono de cobrar (_agenda_gestor_sinal). Sem a regra, a de antes. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; a dupla sem a 2ª pessoa, AG7-04): com a regra uma_pessoa, a OS que pede 2 pessoas num meio-dia (a dupla dita, sem a equipe dita) e a grade (_agenda_tecnicos_da_grade) com menos técnicos do que isso é classe 4, motivo dupla ("precisa de 2 pessoas e só Alex está na equipe: chame um ajudante e me diga os dias dele"): espera o dono em vez de sair do plano calada. Sem a regra, a de antes, byte a byte. FASE 7b (P4, R4.3(b)): com modo_dupla fora de desligado (sombra e ligado), a dupla DITA pelo dono (fonte dono em agenda_meios_da_os: o tempo todo, no início ou no fim) pede o maior dk dos passos que restam (menos o dono quando ele conta como uma das pessoas); com menos técnicos na grade (_agenda_tecnicos_da_grade, que fora de desligado conta quem vem sob demanda com meio-dia livre no horizonte), classe 4, motivo dupla ("precisa de 2 pessoas e só Alex está na equipe: chame um ajudante e me diga os dias dele"). A dupla inferida (fonte regra) nunca segura a OS. Desligado, a de antes, byte a byte. FASE 7g (P5b): a OS que seria classe 2 (nada a segurar), com os dias pelo orçamento (fonte orcamento) e _agenda_espera_ok (o tipo de OS espera o ok do dono, com o modo cru) é classe 3, motivo espera, condicao_tipo ok_do_dono ("espero o seu ok"): só reserva, até o ok; com a opção 2 da pergunta ok_marcacao dada desde que ela passou a esperar, classe 4 duracao. Fora disso, a de antes, sem consulta nova.';

-- _agenda_condicao_da_reserva (de 20261025100200_agenda_fase2_motor.sql:3682; md5 do corpo de antes 63b22e85a316102edad939f2e57ae53c)
create or replace function public._agenda_condicao_da_reserva(p_os uuid, p_tipo text, p_dia date, p_pront jsonb, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  v_item jsonb;
  v_ate  date;
  v_txt  text;
  v_forn text;
begin
  if p_tipo = 'compra' then
    select e into v_item from jsonb_array_elements(coalesce(p_pront #> '{material,itens}', '[]'::jsonb)) with ordinality t(e, o)
     where coalesce((e ->> 'critico')::boolean, true) and e ->> 'nivel' = 'D' and e ->> 'situacao' = 'falta'
     order by coalesce((e ->> 'prazo_du')::int, 0) desc, o limit 1;
    v_ate := greatest(coalesce((v_item ->> 'compra_prevista_em')::date,
                               public.agenda_somar_du(p_dia, -(cf.folga_material_du + coalesce((v_item ->> 'prazo_du')::int, 0)))),
                      p_hoje);
    v_forn := coalesce(', fornecedor ' || nullif(v_item ->> 'fornecedor', ''), '');
    v_txt := case when v_ate <= p_hoje then format('se "%s" estiver na mão (comprando hoje%s)', v_item ->> 'curto', v_forn)
                  else format('se "%s" estiver na mão (compre até %s%s)', v_item ->> 'curto', public._dia_curto(v_ate), v_forn) end;
  elsif p_tipo = 'material' then
    select e into v_item from jsonb_array_elements(coalesce(p_pront #> '{material,itens}', '[]'::jsonb)) with ordinality t(e, o)
     where coalesce((e ->> 'critico')::boolean, true) and e ->> 'nivel' is distinct from 'A'
     order by (e ->> 'situacao') = 'falta', o limit 1;
    v_ate := greatest(public.agenda_somar_du(p_dia, -cf.congelamento_du), p_hoje);
    v_txt := format('se "%s" chegar até %s', coalesce(v_item ->> 'curto', 'o material'), public._dia_curto(v_ate));
  elsif p_tipo = 'conferir_material' then
    v_ate := greatest(public.agenda_somar_du(p_dia, -cf.congelamento_du), p_hoje);
    v_txt := format('se você disser até %s se tem peça a comprar', public._dia_curto(v_ate));
  -- FASE 7g: (7g P5b; §5.5, R9.4-4 ponto 6) ok_do_dono: até a véspera útil do 1º dia, e nunca antes do prazo que a pergunta ok_marcacao teria se fosse mostrada
  -- no próximo dia útil (veto_du dias úteis depois dele, a régua de _agenda_veto_ate): sem isso a vigia (_agenda_vigia_reservas, condição vencida) soltaria a
  -- reserva antes de o dono ver a pergunta e de o prazo dela vencer. Pode passar do 1º dia: a reserva não chama ninguém, e quem decide é a pergunta (1 ou o
  -- prazo promovem; 2 solta).
  elsif p_tipo = 'ok_do_dono' then
    v_ate := greatest(public.agenda_somar_du(p_dia, -1), public.agenda_somar_du(p_hoje, cf.veto_du + 1));
    v_txt := format('se você der o ok até %s', public._dia_curto(v_ate));
  -- FASE 7g: fim
  else
    v_ate := greatest(public.agenda_somar_du(p_dia, -cf.congelamento_du), p_hoje);
    v_txt := format('se você confirmar os dias até %s', public._dia_curto(v_ate));
  end if;
  return jsonb_build_object('condicao', left(v_txt, 160), 'condicao_ate', v_ate);
end;
$function$;

comment on function public._agenda_condicao_da_reserva(uuid, text, date, jsonb, date) is
  'Agenda de Produção (Fase 2, P2): a condição da reserva em palavras e a data-limite, do 1º dia dela — compra: o "compre até" daquele início, agenda_somar_du(dia, −(folga_material_du + prazo da classe do fornecedor)) ou a compra combinada ("comprando hoje" quando já é hoje); material, conferir o material e os dias: o dia útil antes do congelamento. Nunca antes de hoje. FASE 7g (P5b): ok_do_dono: "se você der o ok até <dia>", condicao_ate = o maior entre a véspera útil do 1º dia e hoje + veto_du + 1 dias úteis (o prazo da pergunta mostrada no próximo dia útil): a vigia não solta a reserva antes do prazo.';

-- _agenda_padrao_da_pergunta (de 20261109100000_agenda_fase7f_base.sql:377; md5 do corpo de antes 4c2024d1cb4ed7f252e09adaa7351615)
create or replace function public._agenda_padrao_da_pergunta(p_tipo text, p_critica boolean, p_os uuid, p_opcoes jsonb,
                                                             p_recomendacao smallint, p_os_ids uuid[] default '{}')
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_chave  text;
  v_efeito text;
  v_espera text;
begin
  case
    when p_tipo = 'duracao' then
      v_chave := 'estimativa'; v_efeito := 'nada';
    when p_tipo = 'material_conferir' then
      v_chave := 'sem_peca'; v_efeito := 'nada';
    when p_tipo = 'padrao_do_dono' then
      v_chave := 'abre_e_fecha'; v_efeito := 'nada';
    when p_tipo = 'dias_semana' then
      v_chave := 'abre_e_fecha'; v_efeito := 'nada'; v_espera := 'tipo';
    when p_tipo in ('previsao_fornecedor', 'fornecedor_cadastro', 'fornecedores_prazo') then
      v_chave := 'prazo_padrao'; v_efeito := 'nada';
    when p_tipo in ('parada', 'estouro', 'equipe_resposta') then
      v_chave := 'como_esta'; v_efeito := 'nada';
    when p_tipo = 'chegou' then
      v_chave := 'nao_chegou'; v_efeito := 'nada';
    -- FASE 7g: (7g P5b; §5.5, R9.4-4 ponto 1, R8.5-2; AG7-15) ok_marcacao ("Pode marcar assim?"): sem resposta vale a recomendada (1, fica marcado) pelo prazo da
    -- 7f, com o tipo em veto_tipos (o dado 20261112100990 o põe); com dia dito ao cliente numa das OS, espera o dono, como nao_cabe.
    when p_tipo = 'ok_marcacao' then
      v_chave := 'recomendacao'; v_efeito := 'opcao';
      if exists (select 1 from public.os_planejamento pl
                  where pl.service_order_id = any (coalesce(p_os_ids, '{}') || p_os) and pl.prometido_tipo is not null) then
        v_espera := 'cliente';
      end if;
    -- FASE 7g: fim
    when p_tipo in ('nao_cabe', 'atraso_longo', 'segundo_atraso', 'fixada_pelo_dono') then
      v_chave := 'recomendacao'; v_efeito := 'opcao';
      if exists (select 1 from public.os_planejamento pl
                  where pl.service_order_id = any (coalesce(p_os_ids, '{}') || p_os) and pl.prometido_tipo is not null) then
        v_espera := 'cliente';
      end if;
    when p_tipo in ('remarcar_confirmado', 'dia_prometido', 'acesso') then
      v_chave := 'recomendacao'; v_efeito := 'opcao'; v_espera := 'cliente';
    when p_tipo in ('diaria', 'diaria_ligar', 'nfe_vincular', 'pix_material', 'concluir', 'entrega', 'compre_ate', 'sinal') then
      v_espera := 'dinheiro';
    when p_tipo in ('cliente_aprovar', 'cliente_aviso', 'cliente_resposta', 'aprendizado', 'conferencia', 'tarefa') then
      v_espera := 'tipo';
    when p_tipo in ('situacao', 'estimativa', 'reestimar', 'ficha_estimativa') then
      v_chave := 'estimativa'; v_efeito := 'opcao';
    when p_tipo in ('bem_livre', 'equipe_cadastro') then
      v_chave := 'como_esta'; v_efeito := 'nada'; v_espera := 'tipo';
    when p_tipo in ('onda', 'dia_avisado', 'sabado') then
      v_chave := 'recomendacao'; v_efeito := 'opcao'; v_espera := 'tipo';
    when p_tipo = 'habilidade' then
      v_chave := 'recomendacao'; v_efeito := 'nada'; v_espera := 'tipo';
    when p_tipo = 'local' then
      v_espera := 'cliente';
    else
      -- reavaliar, equipe_sem_dias, combinar e o tipo que esta função não conhece
      v_espera := 'sem_padrao';
  end case;

  if v_efeito = 'opcao'
     and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(p_opcoes) = 'array' then p_opcoes else '[]'::jsonb end) e
                      where e ->> 'n' = p_recomendacao::text) then
    return jsonb_build_object('chave', null, 'efeito', null, 'espera', 'sem_padrao');
  end if;

  if v_espera is null and not p_tipo = any ((public._agenda_cfg()).veto_tipos) then
    v_espera := 'tipo';
  end if;
  return jsonb_build_object('chave', v_chave, 'efeito', v_efeito, 'espera', v_espera);
end;
$function$;

comment on function public._agenda_padrao_da_pergunta(text, boolean, uuid, jsonb, smallint, uuid[]) is
  'Agenda de Produção (Fase 7f, P1; §5.1, R8.5-2; AG7-15): {chave, efeito, espera} do tipo de pergunta. p_recomendacao é a opção que seria aplicada, coalesce(opcao_padrao, recomendacao); efeito opcao sem essa opção entre as opções = sem_padrao. Prometido em p_os ou em p_os_ids = espera cliente. Tipo fora de veto_tipos = espera tipo, mantendo a chave. Tipo desconhecido = sem_padrao. É a foto do nascimento: quem vence confere o prometido de novo. STABLE, sem grant: quem chama é o gatilho, que é definer, e o backfill. FASE 7g (P5b): ok_marcacao = {recomendacao, opcao}, espera cliente com prometido_tipo numa das OS (como nao_cabe); fora de veto_tipos, espera tipo.';

-- _agenda_modo_da_pergunta (de 20261107100000_agenda_fase7d_tabelas.sql:601; md5 do corpo de antes 40a78627108f025a6caaa035df768927)
create or replace function public._agenda_modo_da_pergunta(p_tipo text, p_chave text)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case
    when p_tipo in ('nao_cabe', 'segundo_atraso', 'atraso_longo', 'remarcar_confirmado', 'fixada_pelo_dono') then c.modo_proposta
    when p_tipo = 'chegou' and coalesce(p_chave, '') like 'chegou:fornecedor:%' then c.modo_material
    -- CORREÇÃO 29/10 (revisão): a equipe sem dias é da vigia.
    when p_tipo = 'equipe_sem_dias' then c.modo_vigia
    -- CORREÇÃO 29/10 (revisão): fim
    when p_tipo in ('conferencia', 'chegou', 'parada', 'estouro', 'duracao', 'material_conferir', 'padrao_do_dono', 'entrega')
      then c.modo_vigia
    when p_tipo in ('nfe_vincular', 'pix_material', 'previsao_fornecedor', 'fornecedor_cadastro', 'fornecedores_prazo')
      then c.modo_material
    when p_tipo in ('diaria', 'diaria_ligar') then c.modo_diaria
    when p_tipo in ('equipe_resposta', 'concluir') then c.modo_equipe
    when p_tipo in ('cliente_aprovar', 'cliente_aviso', 'cliente_resposta') then c.modo_cliente
    when p_tipo = 'aprendizado' then c.modo_aprendizado
    -- FASE 7: (7a P11) a pergunta da ficha da equipe de um dia pela estimativa (ficha_estimativa) é das mensagens à equipe
    -- (modo_equipe), não do gestor que marca: a proteção vale enquanto houver dia marcado pela estimativa na janela, também com
    -- *gestor, só propor* (sem isso a pergunta nasceria em teste e a ficha ficaria segurada sem o dono poder soltá-la). Vem antes
    -- da linha do 7a P1, que ainda a cita.
    when p_tipo = 'ficha_estimativa' then c.modo_equipe
    -- FASE 7: fim
    -- FASE 7b: (7b P1) a pergunta dos dias da semana ao dono (dias_semana) é do modo_dias; a chamada da equipe (equipe_cadastro)
    -- passa a ser do modo_cadastro quando ele sai de desligado (o 7b P3 faz o passo equipe do gestor ceder: uma pergunta só);
    -- desligado, continua a do gestor que marca (a linha do 7a P1, abaixo, que ainda a cita). Vem antes dela.
    when p_tipo = 'dias_semana' then c.modo_dias
    when p_tipo = 'equipe_cadastro' and c.modo_cadastro <> 'desligado' then c.modo_cadastro
    -- FASE 7b: fim
    -- FASE 7c: (7c P1) a pergunta de quem faz o quê (habilidade): a da equipe (habilidade:equipe:…, a proposta pelo histórico) é do
    -- modo_habilidade_propor; a de uma OS (habilidade:os:<os>, "ninguém com isso fica livre") é do modo_habilidade.
    when p_tipo = 'habilidade' and coalesce(p_chave, '') like 'habilidade:os:%' then c.modo_habilidade
    when p_tipo = 'habilidade' then c.modo_habilidade_propor
    -- FASE 7c: fim
    -- FASE 7c: (7c P8, R5.4) as perguntas das etapas (tarefa: tarefa:prazo:<os>, "o que falta não cabe até o prazo", e tarefa:quem:<os>,
    -- "a etapa de risco sem quem faça") são do modo_tarefas.
    when p_tipo = 'tarefa' then c.modo_tarefas
    -- FASE 7c: fim
    -- FASE 7d: (7d P1, R6.3-1) as perguntas do local: o modo CRU, sem o freio de *gestor, só propor* (R6.7b): a pergunta já aberta
    -- continua respondível, e quem abre pergunta nova lê _agenda_local_modo. local é da mensagem ao cliente (nasce da resposta ao M11);
    -- combinar é do interruptor do que se combina, pela chave combinar:<tipo>:<os>:<para>; o resto, combinar:acesso:… incluído, é do
    -- preparo do acesso, como a crítica acesso.
    when p_tipo = 'local' then c.modo_cliente
    when p_tipo = 'combinar' and coalesce(p_chave, '') like 'combinar:reserva_marina:%' then c.modo_bem
    when p_tipo = 'combinar' and coalesce(p_chave, '') like 'combinar:descida:%' then c.modo_bem
    when p_tipo = 'combinar' and coalesce(p_chave, '') like 'combinar:entrada:%' then c.modo_patio
    when p_tipo in ('combinar', 'acesso') then c.modo_local_autorizacao
    -- FASE 7d: fim
    -- FASE 7g: (7g P5b; R9.5-23, R9.6) ok_marcacao ("Pode marcar assim?") é do modo_rebaixar, CRU: a pergunta aberta continua respondível com o freio, e quem a
    -- abre (_agenda_explicar_ok) só abre com modo_rebaixar ligado.
    when p_tipo = 'ok_marcacao' then c.modo_rebaixar
    -- FASE 7g: fim
    -- FASE 7: os tipos do gestor da agenda (7a P1). O dia avisado e o prometido são críticas do plano, como o remarcar
    -- confirmado; a revisão diária faz reavaliar e reestimar; a cobrança do "compre até", a dela; o resto é do gestor que marca.
    when p_tipo in ('dia_avisado', 'dia_prometido') then c.modo_proposta
    when p_tipo in ('reavaliar', 'reestimar') then public._agenda_gestor_modo('revisao')
    when p_tipo = 'compre_ate' then public._agenda_gestor_modo('compre_ate')
    when p_tipo in ('situacao', 'estimativa', 'equipe_cadastro', 'ficha_estimativa', 'bem_livre', 'sinal', 'onda', 'sabado')
      then public._agenda_gestor_modo('marcar')
    -- FASE 7: fim
  end
    from public.agenda_config c
   where c.id;
$function$;

comment on function public._agenda_modo_da_pergunta(text, text) is
  'Agenda de Produção (correção de 29/10, P3): o modo de agenda_config de quem grava cada tipo de pergunta — críticas do plano: modo_proposta; conferencia, chegou, parada, estouro, duracao, material_conferir, padrao_do_dono, entrega: modo_vigia; chegou:fornecedor:…, nfe_vincular, pix_material, previsao_fornecedor, fornecedor_cadastro, fornecedores_prazo: modo_material; diaria, diaria_ligar: modo_diaria; equipe_resposta, concluir: modo_equipe; cliente_*: modo_cliente; aprendizado: modo_aprendizado; outro tipo: null. A limpeza da vigia fecha a pergunta aberta em sombra quando este modo está ligado. STABLE, invoker, só o service_role. CORREÇÃO 29/10 (revisão): o tipo novo equipe_sem_dias é da vigia (modo_vigia). Fase 7a (P1): dia_avisado e dia_prometido = modo_proposta (críticas do plano); reavaliar e reestimar = o modo da revisão do gestor; compre_ate = o da cobrança; situacao, estimativa, equipe_cadastro, ficha_estimativa, bem_livre, sinal, onda e sabado = o do gestor que marca (_agenda_gestor_modo). Fase 7a (P11): ficha_estimativa = modo_equipe (a pergunta é das mensagens à equipe: a proteção da ficha vale com *gestor, só propor*); o bloco vem antes da linha do P1, que ainda a cita. Fase 7b (P1): dias_semana = modo_dias (a pergunta dos dias da semana ao dono); equipe_cadastro = modo_cadastro fora de desligado (a chamada da equipe passa a ser da 7b), senão o do gestor que marca, como antes. Fase 7c (P1): habilidade = modo_habilidade_propor (a pergunta de quem faz o quê da equipe, habilidade:equipe:…) ou modo_habilidade (a de uma OS, habilidade:os:<os>). FASE 7c (P8, R5.4): o tipo tarefa (tarefa:prazo:<os> e tarefa:quem:<os>, as exceções das etapas) é do modo_tarefas. Fase 7d (P1; R6.3-1): local = modo_cliente; acesso = modo_local_autorizacao; combinar pela chave (combinar:reserva_marina:… e combinar:descida:… = modo_bem; combinar:entrada:… = modo_patio; o resto, combinar:acesso:… incluído, = modo_local_autorizacao). O modo CRU, sem o freio de *gestor, só propor* (R6.7b): quem abre pergunta nova lê _agenda_local_modo. FASE 7g (P5b): ok_marcacao = modo_rebaixar (cru).';

-- agenda_decidir (de 20261109100100_agenda_fase7f_perguntas.sql:791; md5 do corpo de antes 108125fc0e603c9f9077d019f6767809)
create or replace function public.agenda_decidir(p_pergunta uuid, p_opcao smallint, p_autor uuid default null,
                                                 p_via text default 'whatsapp', p_trecho text default null,
                                                 p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config;
  v_q    public.agenda_perguntas%rowtype;
  v_opc  jsonb;
  v_rest jsonb;
  v_sim  jsonb;
  v_mud  text;
  v_r    jsonb;
  v_ap   jsonb;
  -- FASE 7b: (7b P3) a chamada da equipe, o contato e a pergunta dos dias do dono
  v_7b_g    jsonb;
  v_7b_txt  text;
  v_7b_nome text;
  v_7b_dias smallint[];
  v_7b_acao uuid;
  -- FASE 7b: fim
begin
  -- FASE 7f: (7f P2, §5.2) o canal prazo passa; o resto segue pela conferência de sempre, logo abaixo. Com prazo, respondida_por fica nulo e a resposta é o texto do passo.
  if p_via is distinct from 'prazo' then
  -- FASE 7f: fim
  if p_via is null or p_via not in ('whatsapp', 'painel', 'tela') then
    raise exception 'Canal desconhecido para a decisão: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  -- FASE 7f: (fecha o "se não é prazo")
  end if;
  -- FASE 7f: fim
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  cf := public._agenda_cfg();
  -- CORREÇÃO FASE 6: (C1) regressão B2: a pergunta do aprendizado toma a trava da rodada do aprendizado ANTES de travar a
  -- pergunta (é aqui, e não em _agenda_aprendizado_decidir, que a linha da pergunta é travada primeiro); as outras não
  if exists (select 1 from public.agenda_perguntas q where q.id = p_pergunta and q.tipo = 'aprendizado') then
    perform pg_advisory_xact_lock(hashtext('agenda_aprender'));
  end if;
  -- CORREÇÃO FASE 6: fim
  select * into v_q from public.agenda_perguntas where id = p_pergunta for update;
  if not found then
    raise exception 'Não encontrei essa pergunta.' using errcode = 'P0002';
  end if;
  -- FASE 7f: (7f P2, R8.6) pelo prazo não há autor; com o freio ou em sombra nada decide, e o que não pode vencer não vence: é a última porta, sob a trava e com a pergunta relida. Quem chama já filtrou, e a
  -- recusa vira veto_espera = sem_padrao.
  if p_via = 'prazo' and (p_autor is not null or public._agenda_fala_modo('veto') <> 'ligado' or public._agenda_pergunta_espera(v_q, p_hoje) is not null) then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta espera você: nada mudou.');
  end if;
  -- FASE 7f: fim
  -- FASE 3: a diária (a pergunta crítica que diverge e a de ligar a OS) tem o efeito dela e o modo dela (modo_diaria):
  -- _agenda_decidir_diaria (20261026100300).
  if v_q.tipo in ('diaria', 'diaria_ligar') then
    return public._agenda_decidir_diaria(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_hoje, p_agora);
  end if;
  -- FASE 3: fim
  -- FASE 5: a mensagem ao cliente (cliente_aprovar, a aprovação dos primeiros dias, e cliente_aviso, a crítica do aviso de
  -- atraso) tem o efeito dela e o modo dela (modo_cliente): _agenda_cliente_decidir (20261028100300).
  if v_q.tipo in ('cliente_aprovar', 'cliente_aviso') then
    return public._agenda_cliente_decidir(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_agora);
  end if;
  -- FASE 5: fim
  -- FASE 6: (P6) a pergunta do aprendizado (a troca grande de um valor medido, a carga de cada pessoa pelo plano cumprido e
  -- o planejador mais forte) tem o efeito dela e o modo dela (modo_aprendizado e aprendizado_ligados):
  -- _agenda_aprendizado_decidir (20261029100600). A opção 1 da carga é a única escrita de parâmetro (carga_max), com *desfaz*.
  if v_q.tipo = 'aprendizado' then
    return public._agenda_aprendizado_decidir(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_hoje, p_agora);
  end if;
  -- FASE 6: fim
  -- FASE 7: (7a P4) as perguntas do gestor da agenda (situacao e estimativa decidem aqui; os outros 8 tipos, nos pacotes que os
  -- criam, que recriam _agenda_gestor_decidir) têm o efeito delas e o modo delas (o do gestor): _agenda_gestor_decidir
  -- (20261031100300). dia_avisado e dia_prometido não: são críticas do plano e seguem a decisão de sempre, abaixo; a
  -- equipe_cadastro desta etapa não tem opções ("não é de decisão").
  if v_q.tipo in ('situacao', 'estimativa', 'reavaliar', 'reestimar', 'ficha_estimativa', 'onda', 'sabado', 'bem_livre',
                  'compre_ate', 'sinal') then
    return public._agenda_gestor_decidir(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_hoje, p_agora);
  end if;
  -- FASE 7: fim
  -- FASE 7d: (7d P5, §5.5, R1) as perguntas do que combinar têm o efeito delas e a regra delas (a pergunta e o modo cru, não o freio: R6.7b):
  -- _agenda_local_decidir. Vem antes do "não é de decisão": a combinar não é crítica. O tipo local é do P6.
  if v_q.tipo in ('combinar', 'local', 'acesso') then
    return public._agenda_local_decidir(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_hoje, p_agora);
  end if;
  -- FASE 7d: fim
  -- FASE 7g: (7g P5b; §5.5, §6.4, R9.4-4) a pergunta ok_marcacao ("Pode marcar assim?") tem o efeito dela: _agenda_ok_decidir (1 grava o ok e a reserva vira
  -- compromisso pelo caminho da vigia; 2 solta a reserva e pergunta os dias). Antes do "não é de decisão" e da decisão crítica de sempre, que replanejaria pelas
  -- opções. Pelo prazo, a porta da 7f (acima) já passou: a 1, com ok_do_dono_via = prazo.
  if v_q.tipo = 'ok_marcacao' then
    return public._agenda_ok_decidir(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_hoje, p_agora);
  end if;
  -- FASE 7g: fim
  -- FASE 7b: (7b P3; R4.1-3, R4.1-6, R4.2(b)) as perguntas da equipe com opções — a chamada (1 está certo; 2 mudou: "Me diga quem
  -- saiu ou quem entrou e em que dias vem …", sem diária), o contato (1 põe na rotina, com *desfaz*; 2 grava a recusa: a linha parada,
  -- e nem a regra d14 nem a pergunta voltam) e a pergunta dos dias do dono (a opção com dias grava a semana pelo
  -- _agenda_equipe_dias_gravar, origem dono — a 2, "Fico em campo de seg a sex", cria o padrão dele —; a 1 só fica respondida). Só
  -- com a pergunta e o modo dela (_agenda_modo_da_pergunta) ligados. A chamada da 7a (sem opções) segue o caminho de antes.
  if v_q.tipo = 'dias_semana' or (v_q.tipo = 'equipe_cadastro' and jsonb_array_length(v_q.opcoes) > 0) then
    if v_q.estado <> 'aberta' then
      return jsonb_build_object('ok', false, 'texto', 'Essa pergunta já foi respondida ou resolvida.');
    end if;
    if v_q.modo <> 'ligado' or coalesce(public._agenda_modo_da_pergunta(v_q.tipo, v_q.chave), 'desligado') <> 'ligado' then
      return jsonb_build_object('ok', false, 'texto', 'Essa pergunta da equipe ainda está em teste: mostro como ficaria, mas não mudo nada.');
    end if;
    select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
    if v_opc is null then
      return jsonb_build_object('ok', false,
        'texto', 'Essa opção não existe. As opções são: '
                 || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                       from jsonb_array_elements(v_q.opcoes) o) || '.');
    end if;
    update public.agenda_perguntas
       set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
           respondida_por = p_autor, respondida_via = p_via
     where id = p_pergunta;
    v_7b_nome := coalesce((select public._agenda_nome_curto(py.name) from public.payees py where py.id = v_q.payee_id), 'a pessoa');
    if v_q.tipo = 'dias_semana' then
      if v_opc -> 'efeito' ? 'dias' then
        v_7b_dias := array(select y::smallint from jsonb_array_elements_text(v_opc #> '{efeito,dias}') y);
        -- (correção da revisão da 7b, achados 3 e 10) a opção com dias da pergunta dos dias do dono ("Fico em campo de seg a
        -- sex") diz os dias dele de toda semana: só ela troca o padrão (o gravador prende só a semana em qualquer outra fala do dono)
        if cardinality(v_7b_dias) > 0 and v_q.payee_id is not distinct from public._agenda_dono(null) then
          perform set_config('agenda.dias_padrao_do_dono', 'sim', true);
        end if;
        -- (correção da revisão da 7b: fim)
        v_7b_g := public._agenda_equipe_dias_gravar(v_q.payee_id, v_q.dia, v_7b_dias,
                                                    coalesce((v_opc #>> '{efeito,sabado}')::boolean, false), 'dono',
                                                    'opção ' || p_opcao, p_agora, null, v_q.id, p_autor);
        -- (correção da revisão da 7b, achados 3 e 10) a variável volta a vazio logo depois
        perform set_config('agenda.dias_padrao_do_dono', '', true);
        -- (correção da revisão da 7b: fim)
        v_7b_txt := v_7b_g ->> 'texto';
        insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, payee_id, pergunta_id, depois, texto, autor)
        values (clock_timestamp(), p_hoje, true, 'dono', 'equipe', v_q.payee_id, v_q.id,
                jsonb_build_object('motivo', 'dias_semana', 'semana', v_q.dia, 'dias', to_jsonb(v_7b_dias),
                                   'mudou', v_7b_g -> 'mudou', 'padrao_mudou', v_7b_g -> 'padrao_mudou'),
                left(v_7b_txt, 400), p_autor)
        returning id into v_7b_acao;
      else
        v_7b_txt := format('Anotei: na semana de %s fica assim.', to_char(v_q.dia, 'DD/MM'));
      end if;
      return jsonb_build_object('ok', true, 'texto', v_7b_txt, 'acao_id', v_7b_acao);
    end if;
    if v_opc #>> '{efeito,contato}' = 'por' then
      insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em)
      values (v_q.payee_id, true, 'dono', p_agora)
      on conflict (payee_id) do update set recebe_rotina = true, parou_em = null, parou_motivo = null;
      v_7b_txt := format('Pus %s na rotina da equipe, como você pediu. *desfaz* tira.', v_7b_nome);
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, payee_id, pergunta_id, depois, texto, autor,
                                       desfazivel_ate)
      values (clock_timestamp(), p_hoje, true, 'dono', 'equipe', v_q.payee_id, v_q.id,
              jsonb_build_object('motivo', 'contato', 'payee', v_q.payee_id), left(v_7b_txt, 400), p_autor,
              p_agora + cf.desfazer_validade)
      returning id into v_7b_acao;
      return jsonb_build_object('ok', true, 'texto', v_7b_txt, 'acao_id', v_7b_acao);
    end if;
    if v_opc #>> '{efeito,contato}' = 'nao' then
      insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em, parou_em, parou_motivo)
      values (v_q.payee_id, false, 'dono', p_agora, p_agora, 'você disse que não')
      on conflict (payee_id) do nothing;
      return jsonb_build_object('ok', true, 'texto', format('Anotei: %s fica fora da rotina da equipe.', v_7b_nome));
    end if;
    if v_opc #>> '{efeito,chamada}' = 'mudou' then
      return jsonb_build_object('ok', true,
        'texto', 'Me diga quem saiu ou quem entrou e em que dias vem (ex.: Alex saiu; Mateus vem qua e qui; Mateus vem toda terça).');
    end if;
    return jsonb_build_object('ok', true, 'texto', 'Anotei: sigo com a equipe que tenho.');
  end if;
  -- FASE 7b: fim
  if not v_q.critica then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta não é de decisão.');
  end if;
  if v_q.estado <> 'aberta' then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta já foi respondida ou resolvida.');
  end if;
  if v_q.modo <> 'ligado' or cf.modo_proposta <> 'ligado' then
    return jsonb_build_object('ok', false, 'texto', 'A agenda automática ainda está em teste: mostro como ficaria, mas não marco nada.');
  end if;
  select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
  if v_opc is null then
    return jsonb_build_object('ok', false,
      'texto', 'Essa opção não existe. As opções são: '
               || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                     from jsonb_array_elements(v_q.opcoes) o) || '.');
  end if;
  v_rest := coalesce(v_opc #> '{efeito,restricoes}', '{}'::jsonb);

  -- A agenda mudou desde a pergunta: o efeito da opção é refeito agora; se não termina como a opção dizia, a pergunta
  -- volta com os dias de agora (nada é executado).
  if v_q.versao_base is distinct from cf.versao_plano and jsonb_typeof(v_opc -> 'espera') = 'object'
     and v_opc -> 'espera' <> '{}'::jsonb then
    v_sim := public.agenda_propor('replano', null, null, v_q.os_ids, v_rest, false, 'dono', p_autor, p_hoje, p_agora);
    select string_agg(format('%s termina %s (antes eu disse %s)', public._agenda_rotulo_da_os(e.key::uuid),
                             coalesce(public._dia_curto(x.fim), 'sem encaixe'), public._dia_curto((e.value #>> '{}')::date)), '; ')
      into v_mud
      from jsonb_each(v_opc -> 'espera') e
      left join lateral (select max((i ->> 'fim_depois')::date) as fim from jsonb_array_elements(v_sim -> 'itens') i
                          where i ->> 'op' = 'criar' and i ->> 'os' = e.key and i ->> 'tipo' <> 'reserva') x on true
     where x.fim is distinct from (e.value #>> '{}')::date;
    if v_mud is not null then
      return jsonb_build_object('ok', false, 'mudou', true,
        'texto', 'A agenda mudou desde a pergunta: ' || v_mud || '. Me responda de novo com os dias de agora.');
    end if;
  end if;

  begin
    update public.agenda_perguntas
       set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
           respondida_por = p_autor, respondida_via = p_via
     where id = p_pergunta;
    -- FASE 7f: (7f P2, §5.2) pelo prazo ninguém decidiu: como nas rodadas automáticas, origem vigia e sem autor. Assim a ação sai no *o que mudou* e no aviso, que só contam motor e vigia, com o *desfaz*
    -- dela; não fixa o dia pelo dono nem marca a duração como aceita, o que p_via = dono faria; e nem a proposta nem a ação dizem que foi ele.
    if p_via = 'prazo' then
      v_r := public.agenda_propor('replano', null, null, v_q.os_ids, v_rest || jsonb_build_object('decisao', p_pergunta), true, 'vigia', null, p_hoje, p_agora);
    else
    -- FASE 7f: fim
    v_r := public.agenda_propor('replano', null, null, v_q.os_ids, v_rest || jsonb_build_object('decisao', p_pergunta),
                                true, 'dono', p_autor, p_hoje, p_agora);
    -- FASE 7f: (fecha o "se é prazo")
    end if;
    -- FASE 7f: fim
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      raise exception using errcode = 'P0098', message = coalesce(v_r ->> 'texto', 'não deu');
    end if;
    -- FASE 7f: (7f P2, §5.2) o mesmo caminho do propor: a ação sai crítica, com a pergunta, e sem autor
    if p_via = 'prazo' then
      v_ap := public.agenda_aplicar((v_r ->> 'proposta_id')::uuid, null, 'vigia', null, p_pergunta, p_hoje, p_agora);
    else
    -- FASE 7f: fim
    v_ap := public.agenda_aplicar((v_r ->> 'proposta_id')::uuid, null, 'dono', p_autor, p_pergunta, p_hoje, p_agora);
    -- FASE 7f: (fecha o "se é prazo")
    end if;
    -- FASE 7f: fim
    if not coalesce((v_ap ->> 'ok')::boolean, false) then
      raise exception using errcode = 'P0098', message = coalesce(v_ap ->> 'texto', 'não deu');
    end if;
  exception when sqlstate 'P0098' then
    -- nada fica: a pergunta continua aberta
    return jsonb_build_object('ok', false, 'texto', 'Não consegui fazer o que você escolheu: ' || sqlerrm || ' Nada mudou.');
  end;
  return jsonb_build_object('ok', true, 'texto', 'Feito: ' || (v_ap ->> 'texto'), 'acoes', v_ap -> 'acoes',
                            'proposta_id', v_r ->> 'proposta_id');
end;
$function$;

comment on function public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): a resposta do dono a uma pergunta crítica aberta (só em ligado). Opção que não existe = recusa, nada marcado. Se a agenda mudou desde a pergunta, o efeito da opção é refeito agora e, se não termina como a opção dizia (espera), devolve a pergunta com os dias de agora sem executar. Senão: a pergunta fica respondida (opcao_escolhida, resposta = as palavras do dono, respondida_*) e o efeito é executado — agenda_propor(replano, as OS da pergunta, as restrições da opção + decisao) e agenda_aplicar com p_pergunta (toda ação sai critica = true com pergunta_id). Falhou = nada fica, a pergunta continua aberta. Canais: whatsapp, painel, tela. Fase 3: diaria e diaria_ligar vão a _agenda_decidir_diaria (o lançamento, a correção pelo registrar_diaria ou a ligação às OS, com modo_diaria ligado). Fase 5 (P3): cliente_aprovar e cliente_aviso vão a _agenda_cliente_decidir (manda ou segura a mensagem ao cliente; com modo_cliente ligado). Fase 6 (P6): aprendizado vai a _agenda_aprendizado_decidir (1 o medido passa a valer — na carga, agenda_config.carga_max muda —, 2 trava, 3 volta ao padrão e trava; a 1 e a 3 com a ação crítica desfazível; com modo_aprendizado ligado e o item na lista). CORREÇÃO FASE 6 (C1, regressão B2): a pergunta do aprendizado toma pg_advisory_xact_lock(hashtext(''agenda_aprender'')) antes do for update da pergunta. FASE 7 (7a P4): as perguntas do gestor da agenda (situacao, estimativa, reavaliar, reestimar, ficha_estimativa, onda, sabado, bem_livre, compre_ate, sinal) vão a _agenda_gestor_decidir (o efeito e o modo delas: o do gestor); dia_avisado e dia_prometido seguem a decisão crítica de sempre; equipe_cadastro, a de antes. FASE 7b (P3; R4.1-3, R4.1-6, R4.2(b)): as perguntas da equipe com opções têm o efeito delas, com a pergunta e o modo dela (_agenda_modo_da_pergunta) ligados (senão "ainda está em teste") — equipe_cadastro chamada: 1 "Anotei: sigo com a equipe que tenho."; 2 "Me diga quem saiu ou quem entrou e em que dias vem (ex.: Alex saiu; Mateus vem qua e qui; Mateus vem toda terça)." (sem diária); equipe_cadastro contato: 1 põe na lista da rotina (agenda_equipe_contato recebe_rotina, incluido_por dono) com a ação equipe desfazível ("Pus Mateus na rotina da equipe, como você pediu. *desfaz* tira.", depois.motivo contato); 2 grava a recusa — a linha parada (recebe_rotina false, parou_em agora, "você disse que não"): nem a regra d14 nem a pergunta voltam; dias_semana: a opção com dias grava a semana pelo _agenda_equipe_dias_gravar (origem dono; a 2, "Fico em campo de seg a sex", cria o padrão do dono {1..5} sem frequência; a 3, "Nenhum dia", prende só a semana), com a ação equipe do dono; a 1 ("Fica assim") só fica respondida. A chamada da 7a (sem opções) e o telefone (sem opções) seguem o de antes. CORREÇÃO DA REVISÃO DA 7b (achados 3 e 10): na pergunta dias_semana do dono, a opção com dias grava com agenda.dias_padrao_do_dono = sim (só nessa chamada): ela é a única fala do dono que troca o padrão dele ("Fico em campo de seg a sex" = toda semana); a resposta diz "toda semana a partir de agora". FASE 7d (P5, §5.5, R1): os tipos combinar, local e acesso vão a _agenda_local_decidir (o efeito e a regra delas: a pergunta e o modo cru, não o freio), antes do "não é de decisão". FASE 7f (P2; §5.2): o canal prazo passa, com respondida_por nulo e a resposta = o texto do passo; recusa com autor, com modo_veto efetivo fora de ligado (*gestor, só propor*) e no que _agenda_pergunta_espera segura: {ok: false}, nada mudou. A decisão crítica pelo prazo propõe e aplica com origem vigia, sem autor: a ação sai crítica, com pergunta_id, desfazível, e não diz que foi o dono. FASE 7g (P5b): ok_marcacao vai a _agenda_ok_decidir (1: ok_do_dono_em e a reserva vira compromisso pelo caminho da vigia; 2: solta a reserva, origem dono, e pergunta os dias), antes do "não é de decisão"; pelo prazo, a 1 com ok_do_dono_via = prazo.';

-- agenda_desfazer (de 20261109100100_agenda_fase7f_perguntas.sql:1036; md5 do corpo de antes 7a138b9382d5fc4289de0b770a70fa55)
create or replace function public.agenda_desfazer(p_acao uuid, p_autor uuid default null, p_via text default 'dono',
                                                  p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config;
  v_a     public.agenda_acoes%rowtype;
  v_nome  text;
  v_x     record;
  v_novas uuid[] := '{}';
  v_canc  uuid[] := '{}';
  v_id    uuid;
  v_os    uuid;
  v_acao  uuid;
  v_txt   text;
  v_q     public.agenda_perguntas%rowtype;
  v_dias  date[];
  -- FASE 7: (7a P7) os ramos das ações do gestor (estimar, dupla, gestor) e quem saiu da equipe
  v_f7_pl    public.os_planejamento%rowtype;
  v_f7_txt   text;
  v_f7_acao  uuid;
  v_f7_sai   uuid[] := '{}';
  v_f7_fora  uuid[] := '{}';
  v_f7_ficam int := 0;
  v_f7_nomes text;
  -- FASE 7: fim
  -- FASE 7b: (7b P3) quem entrou na rotina da equipe sai
  v_7b_acao uuid;
  v_7b_txt  text;
  v_7b_nome text;
  -- FASE 7b: fim
  -- FASE 7b: (correção da revisão da 7b, achado 18) desfazer a 2ª pessoa da dupla
  v_7bc_ajud text;
  -- FASE 7b: fim
  -- FASE 7d: (correção G5) a entrega que o cancelar da vigia seguiu
  v_7d_marco uuid;
  v_7d_rm    jsonb;
  -- FASE 7d: fim
  -- FASE 7f: (7f P2) a pergunta que volta
  v_7f_q    public.agenda_perguntas;
  v_7f_nova uuid;
  v_7f_txt  text;
  v_7f_acao uuid;
  -- FASE 7f: fim
begin
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  cf := public._agenda_cfg();
  select * into v_a from public.agenda_acoes where id = p_acao for update;
  if not found then
    raise exception 'Não encontrei essa mudança.' using errcode = 'P0002';
  end if;
  v_os := v_a.service_order_id;
  v_nome := coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                        join public.clients cl on cl.id = so.client_id where so.id = v_os), 'serviço');
  if not v_a.executada then
    return jsonb_build_object('ok', false, 'texto', 'Isso foi só o teste da agenda automática: nada mudou para desfazer.');
  end if;
  if v_a.desfeita_em is not null then
    return jsonb_build_object('ok', false, 'texto', 'Isso já foi desfeito.');
  end if;
  if v_a.tipo = 'desfazer' then
    return jsonb_build_object('ok', false, 'texto', 'Não desfaço um desfazer: me diga o dia que você quer.');
  end if;
  -- FASE 3: a conclusão e a entrega têm o desfazer delas (o status e a saída pela porta, as cobranças da conclusão, a
  -- comissão de vendedor, os vencimentos "na entrega" e a entrega): _agenda_desfazer_marco (20261026100100).
  if v_a.tipo in ('concluir', 'entregar') then
    return public._agenda_desfazer_marco(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 3 (P4): a diária que a agenda lançou: apaga o turno que ela criou, se o acerto está aberto (_agenda_desfazer_diaria).
  if v_a.tipo = 'diaria' then
    return public._agenda_desfazer_diaria(v_a.id, p_autor, p_hoje, p_agora);
  end if;
  -- FASE 3: fim
  -- FASE 4: a mudança do material que o gestor fez sozinho (a previsão pela mensagem do fornecedor, a chegada pela nota
  -- importada): as linhas voltam como estavam, se ninguém mexeu nelas depois (_agenda_desfazer_material, 20261027100400).
  if v_a.tipo = 'material' then
    return public._agenda_desfazer_material(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 4: fim
  -- FASE 5: o que a resposta do cliente mudou (a confirmação, o pedido de dia, o acesso: a ação com depois.resposta_id) tem
  -- o desfazer dela (_agenda_desfazer_cliente, 20261028100400); a mensagem enviada não se desmanda; o acorde e a decisão do
  -- aviso crítico não mudaram nada na agenda.
  if v_a.origem = 'cliente' and v_a.tipo in ('fixar', 'cliente') and v_a.depois ? 'resposta_id' then
    return public._agenda_desfazer_cliente(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  if v_a.tipo = 'cliente' then
    return jsonb_build_object('ok', false,
      'texto', case when v_a.depois ? 'mensagem_id' then 'Mensagem enviada não se desmanda.'
                    else 'Isso foi um aviso para você: nada mudou na agenda para desfazer.' end);
  end if;
  -- FASE 5: fim
  -- FASE 6: (P6) o que o aprendizado mudou (a troca que entrou sozinha e a decisão 1 ou 3 do dono) tem o desfazer dele: o
  -- valor de antes volta e a chave fica travada; a carga volta carga_max (_agenda_desfazer_aprendizado, 20261029100600).
  if v_a.tipo = 'aprendizado' then
    return public._agenda_desfazer_aprendizado(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 6: fim
  -- FASE 7d: (7d P5, §5.5) a ação local tem o desfazer dela: as colunas de os_planejamento voltam ao antes, as linhas de os_autorizados que ela criou
  -- ganham revogado_em e o replano do "Segure o dia" volta (_agenda_desfazer_local)
  if v_a.tipo = 'local' then
    return public._agenda_desfazer_local(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 7d: fim
  -- FASE 7g: (7g P5b; §5.5, §6.4, R9.4-4 ponto 7) a ação nivel (o tipo de OS que passou a esperar o seu ok, ou que voltou a marcar sozinho) tem o desfazer dela,
  -- sem o prazo de 24 h (desfazivel_ate) e sem OS: _agenda_desfazer_nivel. *desfaz espera* chega aqui por agenda_desfazer_dito.
  if v_a.tipo = 'nivel' then
    return public._agenda_desfazer_nivel(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 7g: fim
  -- FASE 7: (7a P7, spec R3 e §5.7) as ações do gestor que não são de alocação têm o ramo delas: estimar (os dias que o gestor
  -- gravou pelo prazo ou pela opção 1: os_planejamento.dias, estimativa_fonte e estimativa_em voltam ao antes da ação), dupla
  -- (dupla_dita, dupla_meios, dupla_motivo e dupla_em voltam) e gestor (*gestor, só propor* / *pode marcar*: gestor_so_propor e
  -- gestor_so_propor_em voltam). Só se nada mudou depois da ação (o que está gravado é o depois dela); senão a recusa diz o que
  -- mudou. reparar e reestimar são de alocação e seguem o caminho de sempre.
  if v_a.tipo in ('estimar', 'dupla', 'gestor') then
    if v_a.desfazivel_ate is null or p_agora > v_a.desfazivel_ate then
      return jsonb_build_object('ok', false,
        'texto', case when v_a.tipo = 'gestor' then 'Não dá mais para desfazer: passou o prazo. Diga *gestor, só propor* ou *gestor, pode marcar*.'
                      else format('Não dá mais para desfazer o %s: passou o prazo. Se quiser mudar, me diga.', v_nome) end);
    end if;
    if v_a.tipo = 'gestor' then
      if (select c.gestor_so_propor from public.agenda_config c where c.id)
         is distinct from (v_a.depois ->> 'gestor_so_propor')::boolean then
        return jsonb_build_object('ok', false,
          'texto', 'Não desfaço: depois disso você já mudou o gestor de novo. Diga *gestor, só propor* ou *gestor, pode marcar*.');
      end if;
      update public.agenda_config
         set gestor_so_propor = coalesce((v_a.antes ->> 'gestor_so_propor')::boolean, false),
             gestor_so_propor_em = (v_a.antes ->> 'gestor_so_propor_em')::timestamptz,
             atualizado_em = p_agora, atualizado_por = p_autor
       where id;
      v_f7_txt := case when coalesce((v_a.antes ->> 'gestor_so_propor')::boolean, false)
                       then 'Desfeito: voltei a só sugerir. *gestor, pode marcar* volta a marcar.'
                       else 'Desfeito: voltei a marcar sozinho; o que eu marcar vem no seu fechamento, com *desfaz*.' end;
    else
      select * into v_f7_pl from public.os_planejamento where service_order_id = v_os for update;
      if not found then
        return jsonb_build_object('ok', false, 'texto', format('Não achei o planejamento do %s: nada mudou.', v_nome));
      end if;
      if v_a.tipo = 'estimar' then
        if v_f7_pl.dias is distinct from (v_a.depois ->> 'dias')::numeric or v_f7_pl.estimativa_fonte is distinct from 'orcamento' then
          return jsonb_build_object('ok', false,
            'texto', format('Não desfaço: depois disso os dias do %s mudaram (%s). Para mudar de novo, me diga os dias.', v_nome,
                            coalesce(public._agenda_dias(v_f7_pl.dias), 'sem dias')));
        end if;
        update public.os_planejamento
           set dias = (v_a.antes ->> 'dias')::numeric, estimativa_fonte = v_a.antes ->> 'estimativa_fonte',
               estimativa_em = (v_a.antes ->> 'estimativa_em')::timestamptz,
               historico = public._os_material_historico(v_f7_pl.historico, jsonb_build_object(
                 'em', p_hoje, 'quando', p_agora, 'autor', p_autor, 'por', 'dono', 'motivo', 'desfeito', 'acao', v_a.id,
                 'antes', v_a.depois, 'depois', v_a.antes)),
               atualizado_em = p_agora, atualizado_por = p_autor
         where service_order_id = v_os;
        v_f7_txt := case when v_a.antes ->> 'dias' is null
                         then format('Desfeito: o %s volta sem os dias que eu contei (%s). Me diga quantos dias são.',
                                     public._agenda_rotulo_da_os(v_os), public._agenda_dias((v_a.depois ->> 'dias')::numeric))
                         else format('Desfeito: o %s volta a %s, como estava.', public._agenda_rotulo_da_os(v_os),
                                     public._agenda_dias((v_a.antes ->> 'dias')::numeric)) end;
      else
        if v_f7_pl.dupla_dita is distinct from v_a.depois ->> 'dupla_dita'
           or v_f7_pl.dupla_meios is distinct from (v_a.depois ->> 'dupla_meios')::smallint then
          return jsonb_build_object('ok', false,
            'texto', format('Não desfaço: depois disso a dupla do %s mudou. Diga *%s com dupla* ou *%s sem dupla*.', v_nome, v_nome, v_nome));
        end if;
        update public.os_planejamento
           set dupla_dita = v_a.antes ->> 'dupla_dita', dupla_meios = (v_a.antes ->> 'dupla_meios')::smallint,
               dupla_motivo = v_a.antes ->> 'dupla_motivo', dupla_em = (v_a.antes ->> 'dupla_em')::timestamptz,
               historico = public._os_material_historico(v_f7_pl.historico, jsonb_build_object(
                 'em', p_agora, 'autor', p_autor, 'por', 'dono', 'trecho', 'desfeito', 'acao', v_a.id,
                 'antes', v_a.depois, 'depois', v_a.antes)),
               atualizado_em = p_agora, atualizado_por = p_autor
         where service_order_id = v_os;
        v_f7_txt := format('Desfeito: o %s volta %s.', public._agenda_rotulo_da_os(v_os),
                           case v_a.antes ->> 'dupla_dita'
                             when 'todos' then 'com dupla'
                             when 'nao' then 'sem dupla'
                             when 'inicio' then 'com dupla no início'
                             when 'fim' then 'com dupla no fim'
                             else 'ao normal: 1 pessoa, e dupla só quando você marcar' end);
      end if;
    end if;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, critica, antes, depois, texto,
                                     autor, desfaz_a)
    values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer', v_os,
            v_a.os_ids, false, jsonb_build_object('acao', v_a.id), v_a.antes, left(v_f7_txt, 400), p_autor, v_a.id)
    returning id into v_f7_acao;
    update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_f7_acao where id = v_a.id;
    return jsonb_build_object('ok', true, 'texto', v_f7_txt, 'acao_id', v_f7_acao, 'recriadas', '[]'::jsonb, 'canceladas', '[]'::jsonb);
  end if;
  -- FASE 7: fim
  -- FASE 7b: (7b P3, §5.2) a entrada na rotina da equipe — a ação equipe da regra d14 (vigia) ou do "1) Ponho" do dono (depois.motivo
  -- regra_d14 ou contato) — sai: recebe_rotina false e a linha parada ("desfeito pelo dono"); a regra não a põe de novo (a linha existe).
  if v_a.tipo = 'equipe' and v_a.depois ->> 'motivo' in ('regra_d14', 'contato') then
    v_7b_nome := coalesce((select public._agenda_nome_curto(py.name) from public.payees py where py.id = v_a.payee_id), 'a pessoa');
    if v_a.desfazivel_ate is null or p_agora > v_a.desfazivel_ate then
      return jsonb_build_object('ok', false,
        'texto', format('Não dá mais para desfazer: passou o prazo. Se quiser tirar %s da rotina da equipe, me diga.', v_7b_nome));
    end if;
    update public.agenda_equipe_contato
       set recebe_rotina = false, parou_em = p_agora, parou_motivo = 'desfeito pelo dono'
     where payee_id = v_a.payee_id and parou_em is null;
    if not found then
      return jsonb_build_object('ok', false, 'texto', format('%s já não está na rotina da equipe: nada mudou.', v_7b_nome));
    end if;
    v_7b_txt := format('Desfeito: %s sai da rotina da equipe e não recebe mais a ficha nem a pergunta dos dias.', v_7b_nome);
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, payee_id, os_ids, critica, antes, depois, texto, autor,
                                     desfaz_a)
    values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer',
            v_a.payee_id, '{}'::uuid[], false, jsonb_build_object('acao', v_a.id), jsonb_build_object('recebe_rotina', false),
            left(v_7b_txt, 400), p_autor, v_a.id)
    returning id into v_7b_acao;
    update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_7b_acao where id = v_a.id;
    return jsonb_build_object('ok', true, 'texto', v_7b_txt, 'acao_id', v_7b_acao, 'recriadas', '[]'::jsonb,
                              'canceladas', '[]'::jsonb);
  end if;
  -- FASE 7b: fim
  -- FASE 7f: (7f P2, §5.2, R8.5-10, R8.5-11) a pergunta que ficou com o padrão volta a esperar o dono, sem prazo: uma pergunta NOVA, igual à de antes, que nasce pelo gatilho com o padrão. A fechada fica como
  -- foi. A mesma chave: se a vigia já a abriu de novo, nada duplica, e o texto continua verdade. A validade que já passou não volta vencida. Passou a janela: a recusa diz por onde sai.
  if v_a.tipo = 'assumir' then
    if v_a.desfazivel_ate is null or p_agora > v_a.desfazivel_ate then
      return jsonb_build_object('ok', false, 'texto', 'Não dá mais para reabrir a pergunta: passou o prazo. Se quiser mudar, me diga com as suas palavras.');
    end if;
    select * into v_7f_q from public.agenda_perguntas where id = v_a.pergunta_id;
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, os_material_id, payee_id, dia, perda_em, texto, opcoes, recomendacao,
                                         recomendacao_texto, versao_base, modo, criada_em, expira_em)
    values (v_7f_q.tipo, v_7f_q.chave, v_7f_q.service_order_id, v_7f_q.os_ids, v_7f_q.os_material_id, v_7f_q.payee_id, v_7f_q.dia, v_7f_q.perda_em, v_7f_q.texto,
            v_7f_q.opcoes, v_7f_q.recomendacao, v_7f_q.recomendacao_texto, cf.versao_plano, v_7f_q.modo, p_agora,
            case when v_7f_q.expira_em is null or v_7f_q.expira_em > p_agora then v_7f_q.expira_em else p_agora + cf.desfazer_validade end)
    on conflict (chave, modo) where estado = 'aberta' do nothing
    returning id into v_7f_nova;
    v_7f_txt := case when v_a.antes ->> 'rotulo' is not null then format('Desfeito: a pergunta sobre %s volta a esperar você.', v_a.antes ->> 'rotulo')
                     else 'Desfeito: a pergunta volta a esperar você.' end;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, critica, antes, depois, texto, autor, desfaz_a)
    values (p_agora, p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer', v_os, v_a.os_ids, false,
            jsonb_build_object('acao', v_a.id), jsonb_build_object('pergunta_id', v_7f_nova), left(v_7f_txt, 400), p_autor, v_a.id)
    returning id into v_7f_acao;
    update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_7f_acao where id = v_a.id;
    return jsonb_build_object('ok', true, 'texto', v_7f_txt, 'acao_id', v_7f_acao, 'pergunta_id', v_7f_nova, 'recriadas', '[]'::jsonb, 'canceladas', '[]'::jsonb);
  end if;
  -- FASE 7f: fim
  if v_a.desfazivel_ate is null then
    return jsonb_build_object('ok', false, 'texto', 'Essa mudança foi pedida por você: para mudar de novo, me diga o dia.');
  end if;
  if p_agora > v_a.desfazivel_ate then
    return jsonb_build_object('ok', false,
      'texto', case when exists (select 1 from public.agenda_alocacoes a where a.id = any (v_a.alocacoes_criadas)
                                                                       and lower(a.periodo) <= p_agora)
                    then format('Não dá para desfazer: já começou o 1º dia do %s na nova data. Se quiser mudar, me diga o dia.', v_nome)
                    else format('Não dá mais para desfazer o %s: passou o prazo. Se quiser mudar, me diga o dia.', v_nome) end);
  end if;
  if exists (select 1 from public.agenda_alocacoes a
              where a.id = any (v_a.alocacoes_criadas) and a.estado in ('publicada', 'fixada')
                and (lower(a.periodo) <= p_agora or a.resultado is not null)) then
    return jsonb_build_object('ok', false,
      'texto', format('Não dá para desfazer: já começou o 1º dia do %s na nova data. Se quiser mudar, me diga o dia.', v_nome));
  end if;
  -- recriar o que saiu não pode bater em quem já está no lugar
  select a.dia, a.turno, py.name as pessoa, cl.name as cliente into v_x
    from public.agenda_alocacoes c
    join public.agenda_alocacoes a on a.payee_id = c.payee_id and a.periodo && c.periodo and a.estado in ('publicada', 'fixada')
                                  and not (a.id = any (v_a.alocacoes_criadas))
    join public.payees py on py.id = a.payee_id
    join public.service_orders so on so.id = a.service_order_id
    left join public.clients cl on cl.id = so.client_id
   where c.id = any (v_a.alocacoes_canceladas) and c.estado = 'cancelada' and lower(c.periodo) > p_agora
   order by a.dia, a.turno = 'tarde'
   limit 1;
  if found then
    -- FASE 7b: (correção da revisão da 7b, achado 18) no serviço em que o gestor completou a dupla, a revisão encurtou o fim e outra OS
    -- ocupou o meio-dia que sobrou: a recusa (a regra de sempre: o *desfaz* nunca sobrepõe) diz como voltar — desfazer antes o que
    -- ocupou o lugar
    if v_os is not null and exists (select 1 from public.agenda_alocacoes a
                                     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.motivos ? 'dupla_completa') then
      v_7bc_ajud := public._agenda_lista(array(
                      select distinct public._agenda_nome_curto(py.name) from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
                       where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.motivos ? 'dupla_completa' order by 1));
      return jsonb_build_object('ok', false,
        'texto', format('Não dá para desfazer: o %s já está no %s %s. Com %s junto, o %s acaba antes; se quiser o dia de volta mesmo assim, diga *desfaz %s* e depois *desfaz %s*.',
                        public._agenda_nome_curto(v_x.pessoa), coalesce(public._agenda_nome_curto(v_x.cliente), 'outro serviço'),
                        public._agenda_meio_texto(v_x.dia, v_x.turno), v_7bc_ajud, v_nome,
                        coalesce(public._agenda_nome_curto(v_x.cliente), 'outro serviço'), v_nome));
    end if;
    -- FASE 7b: fim
    return jsonb_build_object('ok', false,
      'texto', format('Não dá para desfazer: o %s já está no %s %s.', public._agenda_nome_curto(v_x.pessoa),
                      coalesce(public._agenda_nome_curto(v_x.cliente), 'outro serviço'), public._agenda_meio_texto(v_x.dia, v_x.turno)));
  end if;

  -- FASE 7: (7a P7; fase7-padroes "medição de 30/10", item 4) o que a ação tirou e era de quem não está mais na equipe (a
  -- grade, agenda_capacidade, naquele dia) não volta: o *desfaz* restaura só o que cabe e diz o resto. Se tudo o que voltaria é
  -- de quem saiu e a ação não criou nada que ainda esteja de pé, nada muda (a recusa diz por quê): voltar o Lenine com João e
  -- Roberto, que saíram, faria a vigia remanejar de novo e mandar outro aviso com outro *desfaz*.
  select coalesce(array_agg(c.id) filter (where not g.na_grade), '{}'), coalesce(array_agg(distinct c.payee_id) filter (where not g.na_grade), '{}'),
         count(*) filter (where g.na_grade)
    into v_f7_sai, v_f7_fora, v_f7_ficam
    from public.agenda_alocacoes c
    cross join lateral (select exists (select 1 from public.agenda_capacidade(c.dia, c.dia, p_hoje) k
                                        where k.payee_id = c.payee_id) as na_grade) g
   where c.id = any (v_a.alocacoes_canceladas) and c.estado = 'cancelada' and lower(c.periodo) > p_agora;
  if cardinality(v_f7_fora) > 0 then
    v_f7_nomes := public._agenda_lista(array(select public._agenda_nome_curto(py.name) from public.payees py
                                              where py.id = any (v_f7_fora) order by py.name, py.id), null);
  end if;
  if cardinality(v_f7_fora) > 0 and v_f7_ficam = 0
     and not exists (select 1 from public.agenda_alocacoes a
                      where a.id = any (v_a.alocacoes_criadas) and a.estado in ('publicada', 'fixada')) then
    return jsonb_build_object('ok', false, 'status', 'saiu_da_equipe',
      'texto', format('Não dá para desfazer como estava: %s não %s mais na equipe, e era com %s que o %s estava. Nada mudou; ele volta à agenda com a equipe de agora.',
                      v_f7_nomes, case when cardinality(v_f7_fora) = 1 then 'está' else 'estão' end,
                      case when cardinality(v_f7_fora) = 1 then 'ele' else 'eles' end, v_nome));
  end if;
  -- FASE 7: fim
  -- FASE 7d: (correção G5) o cancelar da vigia em OS concluída por *entreguei* é só o efeito: o *desfaz* volta a entrega junto, pelo caminho dela, senão a OS segue concluída, com o plano de volta, e o
  -- tique seguinte cancela de novo. Se ela não volta, nada volta: a recusa dela.
  if v_a.tipo = 'cancelar' and v_a.origem = 'vigia' and (select so.status from public.service_orders so where so.id = v_os) = 'completed' then
    select x.id into v_7d_marco from public.agenda_acoes x
     where x.service_order_id = v_os and x.tipo in ('entregar', 'concluir') and x.executada and x.desfeita_em is null
       and x.criada_em <= v_a.criada_em and x.desfazivel_ate >= p_agora
     order by x.tipo = 'entregar' desc, x.criada_em desc, x.id desc limit 1;
    if v_7d_marco is not null then
      v_7d_rm := public._agenda_desfazer_marco(v_7d_marco, p_autor, p_via, p_hoje, p_agora);
      if not coalesce((v_7d_rm ->> 'ok')::boolean, false) then
        return v_7d_rm;
      end if;
    end if;
    -- (correção M9) a regra única: se a OS segue concluída depois do marco, o plano NÃO volta (a vigia tiraria de novo a cada tique), e o *desfaz* diz por quê. O cancelar segue desfazível: é o 2º *desfaz* que acha a conclusão
    if (select so.status from public.service_orders so where so.id = v_os) = 'completed' then
      if v_7d_rm is null then
        return jsonb_build_object('ok', false, 'texto', format('Não dá para voltar os dias do %s: ele segue concluído. Reabra a OS primeiro.', v_nome));
      end if;
      return jsonb_build_object('ok', true, 'acao_id', v_7d_rm -> 'acao_id', 'recriadas', '[]'::jsonb, 'canceladas', '[]'::jsonb,
        'texto', (v_7d_rm ->> 'texto') || ' ' ||
                 case when exists (select 1 from public.agenda_acoes x
                                    where x.service_order_id = v_os and x.tipo = 'concluir' and x.executada and x.desfeita_em is null
                                      and x.criada_em <= v_a.criada_em and x.desfazivel_ate >= p_agora)
                      then format('O %s segue concluído: mande *desfaz %s* de novo para voltar a conclusão.', v_nome,
                                  (select so.service_order_number from public.service_orders so where so.id = v_os))
                      else format('O %s segue concluído: os dias só voltam reabrindo a OS.', v_nome) end);
    end if;
  end if;
  -- FASE 7d: fim
  -- 1. O que a ação criou sai.
  for v_id in select a.id from public.agenda_alocacoes a
               where a.id = any (v_a.alocacoes_criadas) and a.estado in ('publicada', 'fixada') order by a.dia, a.turno, a.id loop
    if (select estado from public.agenda_alocacoes where id = v_id) = 'fixada' then
      perform set_config('agenda.mexe_fixado', 'on', true);
    end if;
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'desfeito' where id = v_id;
    perform set_config('agenda.mexe_fixado', 'off', true);
    v_canc := v_canc || v_id;
  end loop;
  -- 2. O que ela tirou volta, igual (mesma pessoa, dia, turno e presença), do que ainda não começou.
  for v_x in select c.* from public.agenda_alocacoes c
              where c.id = any (v_a.alocacoes_canceladas) and c.estado = 'cancelada' and lower(c.periodo) > p_agora
              order by c.dia, c.turno = 'tarde', c.payee_id, c.id loop
    -- FASE 7: (7a P7) o meio-dia de quem saiu da equipe não volta
    continue when v_x.id = any (v_f7_sai);
    -- FASE 7: fim
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, substitui_id,
                                         fixado_por, reserva_de, condicao, condicao_tipo, condicao_ate, motivos)
    values (v_x.service_order_id, v_x.payee_id, v_x.dia, v_x.turno, v_x.presenca, v_x.tipo,
            case when v_x.fixado_por is not null then 'fixada' else 'publicada' end, v_x.origem, v_x.id,
            v_x.fixado_por, v_x.reserva_de, v_x.condicao, v_x.condicao_tipo, v_x.condicao_ate, v_x.motivos)
    returning id into v_id;
    v_novas := v_novas || v_id;
  end loop;
  -- 3. O status volta pela porta (a regra de não regredir o que começou continua valendo) e o espelho acompanha.
  if v_a.tipo = 'status' and v_a.status_antes is not null and v_os is not null then
    perform public.os_transicionar_status(v_os, v_a.status_antes, 'desfazer', null, p_autor, null, p_hoje, p_agora);
  elsif v_os is not null then
    if public._agenda_os_tem_dia(v_os, p_hoje) then
      if (select status from public.service_orders where id = v_os) in ('open', 'approved', 'awaiting_parts') then
        perform public.os_transicionar_status(v_os, 'scheduled', 'desfazer', null, p_autor, null, p_hoje, p_agora);
      end if;
    elsif (select status from public.service_orders where id = v_os) = 'scheduled' then
      perform public.os_transicionar_status(v_os, case when v_a.status_antes in ('open', 'approved', 'awaiting_parts')
                                                       then v_a.status_antes else 'approved' end,
                                            'desfazer', null, p_autor, null, p_hoje, p_agora);
    end if;
    perform public._agenda_espelhar_datas(v_os, p_hoje);
  end if;

  v_dias := array(select a.dia from public.agenda_alocacoes a where a.id = any (v_novas) and a.tipo <> 'reserva');
  v_txt := case when cardinality(v_dias) > 0
                then format('Desfeito: o %s volta para %s, como estava.', public._agenda_rotulo_da_os(v_os), public._agenda_dias_texto(v_dias))
                when cardinality(v_novas) > 0 then format('Desfeito: a reserva do %s volta como estava.', public._agenda_rotulo_da_os(v_os))
                else format('Desfeito: o %s sai da agenda, como estava.', coalesce(public._agenda_rotulo_da_os(v_os), 'serviço')) end;
  -- FASE 7b: (correção da revisão da 7b, achado 18) desfazer a 2ª pessoa que o gestor pôs na dupla (as alocações com o motivo
  -- dupla_completa) tira só ela: o serviço continua marcado — o texto de antes dizia que ele saía da agenda
  if cardinality(v_novas) = 0 and cardinality(v_canc) > 0 and v_os is not null and public._agenda_os_tem_dia(v_os, p_hoje)
     and not exists (select 1 from public.agenda_alocacoes a where a.id = any (v_canc) and not coalesce(a.motivos ? 'dupla_completa', false)) then
    v_txt := format('Desfeito: tirei %s do %s %s; o resto do serviço fica como estava.',
                    public._agenda_lista(array(select distinct public._agenda_nome_curto(py.name)
                                                 from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
                                                where a.id = any (v_canc) order by 1)),
                    public._agenda_rotulo_da_os(v_os),
                    public._agenda_meios_frase((select jsonb_agg(jsonb_build_object('dia', a.dia, 'turno', a.turno) order by a.dia, a.turno)
                                                  from public.agenda_alocacoes a where a.id = any (v_canc))));
  end if;
  -- FASE 7b: fim
  -- FASE 7: (7a P7) e diz o que não voltou
  if cardinality(v_f7_fora) > 0 then
    v_txt := v_txt || format(' %s não %s mais na equipe: os dias %s não voltam.', v_f7_nomes,
                             case when cardinality(v_f7_fora) = 1 then 'está' else 'estão' end,
                             case when cardinality(v_f7_fora) = 1 then 'dele' else 'deles' end);
  end if;
  -- FASE 7: fim
  -- FASE 7d: (correção G5) os 2 "Desfeito", na ordem em que aconteceram
  v_txt := coalesce((v_7d_rm ->> 'texto') || ' ', '') || v_txt;
  -- FASE 7d: fim
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, proposta_id, critica,
                                   versao_depois, alocacoes_criadas, alocacoes_canceladas, antes, depois, texto, autor, desfaz_a)
  values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer', v_os,
          v_a.os_ids, v_a.proposta_id, false, (public._agenda_cfg()).versao_plano, v_novas, v_canc,
          jsonb_build_object('acao', v_a.id), jsonb_build_object('alocacoes', to_jsonb(v_novas)), left(v_txt, 400), p_autor, v_a.id)
  returning id into v_acao;
  update public.agenda_alocacoes set acao_id = v_acao where id = any (v_novas);
  update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_a.id;

  -- Desfazer uma decisão crítica não a reabre: a decisão volta ao dono como pergunta nova, do mesmo tipo.
  if v_a.critica and v_a.pergunta_id is not null then
    select * into v_q from public.agenda_perguntas where id = v_a.pergunta_id;
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, perda_em, texto, opcoes, recomendacao,
                                         recomendacao_texto, versao_base, modo, criada_em)
    values (v_q.tipo, left(v_q.chave || ':refeita:' || left(v_acao::text, 8), 200), v_q.service_order_id, v_q.os_ids, v_q.perda_em,
            v_q.texto, v_q.opcoes, v_q.recomendacao, v_q.recomendacao_texto, (public._agenda_cfg()).versao_plano, v_q.modo, p_agora)
    on conflict (chave, modo) where estado = 'aberta' do nothing;
    v_txt := format('Desfeito. A decisão sobre o %s volta a ficar com você.', v_nome);
  end if;
  -- FASE 3: o replano que a ausência da equipe causou ("não vou" ou o silêncio até as 9h): desfazer também tira a ausência
  -- daquele dia (senão a vigia replanejaria de novo no tique seguinte). "Se ele estiver lá, *desfaz Vanderlei*."
  update public.agenda_disponibilidade d set substituida_em = p_agora
   where d.substituida_em is null
     and d.id in (select (e.depois ->> 'disponibilidade')::uuid from public.agenda_acoes e
                   where e.tipo = 'equipe' and e.depois ->> 'disponibilidade' is not null
                     and coalesce(e.depois -> 'replano_acoes', '[]'::jsonb) ? v_a.id::text);
  -- FASE 3: fim
  -- FASE 5: o replano que o pedido de dia do cliente causou, desfeito direto (sem a ação do cliente): o pedido sai junto (o
  -- bem indisponível e o "não antes de" voltam; senão a vigia replanejaria de novo no tique seguinte) e a ação do cliente
  -- fica desfeita. Quem desfaz pela ação do cliente (_agenda_desfazer_cliente) liga agenda.desfazer_cliente e faz isso ela.
  if coalesce(current_setting('agenda.desfazer_cliente', true), '') <> 'on' then
    for v_x in select e.id from public.agenda_acoes e
                where e.tipo = 'cliente' and e.origem = 'cliente' and e.executada and e.desfeita_em is null
                  and e.depois ->> 'efeito' = 'replanejou'
                  and coalesce(e.depois -> 'replano_acoes', '[]'::jsonb) ? v_a.id::text loop
      perform public._agenda_cliente_restaurar_pedido(v_x.id, p_agora);
      update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_x.id;
    end loop;
  end if;
  -- FASE 5: fim
  -- FASE 7d: (7d P5, R6.7c-1) o replano do "Segure o dia", desfeito direto (sem a ação local): o "não antes de" volta junto, senão a vigia tiraria o
  -- dia de novo no tique seguinte; e a ação local fica desfeita. Quem desfaz pela ação local liga agenda.desfazer_local e faz isso ela.
  if coalesce(current_setting('agenda.desfazer_local', true), '') <> 'on' then
    for v_x in select e.id from public.agenda_acoes e
                where e.tipo = 'local' and e.executada and e.desfeita_em is null
                  and coalesce(e.depois -> 'replano_acoes', '[]'::jsonb) ? v_a.id::text loop
      perform public._agenda_local_restaurar(v_x.id, p_autor, p_agora);
      update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_x.id;
    end loop;
  end if;
  -- FASE 7d: fim
  return jsonb_build_object('ok', true, 'texto', v_txt, 'acao_id', v_acao, 'recriadas', to_jsonb(v_novas), 'canceladas', to_jsonb(v_canc));
end;
$function$;

comment on function public.agenda_desfazer(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): desfaz uma ação executada — recusa (nada muda) se foi sombra, já foi desfeita, não é desfazível (pedido do dono pela tela ou aprovação), passou o desfazivel_ate, algum meio-dia criado já começou ou tem resultado, ou recriar o que saiu bateria em quem já está no lugar ("Não dá para desfazer: o Roberto já está no Giancarlo…"). Faz: o que ela criou → cancelada (desfeito); o que ela tirou volta igual (substitui_id, mesmo estado/fixado); o status pela porta (via desfazer; o que começou não regride); o espelho; nova ação tipo desfazer (desfaz_a) e a original ganha desfeita_*. Desfazer uma decisão crítica cria a pergunta de novo ("A decisão sobre o Nelson volta a ficar com você."). Fase 3: concluir e entregar vão a _agenda_desfazer_marco (as cobranças da conclusão, a saída, a comissão de vendedor e a entrega); a diária da agenda a _agenda_desfazer_diaria (apaga o turno que ela criou, com o acerto aberto); desfazer o replano da ausência da equipe tira a ausência do dia (agenda_disponibilidade substituída). Fase 4 (P4): a ação material (a previsão pela mensagem do fornecedor, a chegada pela nota) vai a _agenda_desfazer_material (as linhas voltam se ninguém mexeu nelas depois). Fase 5 (P4): o que a resposta do cliente mudou (a ação fixar/cliente de origem cliente com depois.resposta_id: a confirmação, o pedido de dia, o acesso) vai a _agenda_desfazer_cliente; a outra ação cliente (a mensagem enviada, o acorde, a decisão do aviso) não se desfaz ("Mensagem enviada não se desmanda."); desfazer direto o replano que o pedido de dia causou também tira o pedido (_agenda_cliente_restaurar_pedido) e deixa a ação do cliente desfeita. Fase 6 (P6): a ação aprendizado vai a _agenda_desfazer_aprendizado (o em_uso de antes volta, nulo = o padrão, e a chave fica travada por aprender_trava_dias; a da carga volta carga_max). FASE 7 (7a P7, spec R3): as ações do gestor que não são de alocação têm o ramo delas — estimar (os_planejamento.dias, estimativa_fonte e estimativa_em voltam ao antes da ação: "Desfeito: o Nelson (OS-00112) volta sem os dias que eu contei (4 dias). Me diga quantos dias são."), dupla (dupla_dita, dupla_meios, dupla_motivo e dupla_em voltam) e gestor (gestor_so_propor e gestor_so_propor_em voltam), cada uma só se nada mudou depois dela (senão a recusa diz o que mudou), dentro do desfazivel_ate; reparar e reestimar seguem o caminho de alocação de sempre. E (a medição de 30/10, item 4) o que a ação tirou e era de quem não está mais na equipe naquele dia (agenda_capacidade) não volta: o desfazer restaura só o que cabe e diz o resto ("… João e Roberto não estão mais na equipe: os dias deles não voltam."); se tudo o que voltaria é de quem saiu e a ação não criou nada de pé, nada muda ({ok: false, status saiu_da_equipe}). FASE 7b (P3, §5.2): a ação equipe que pôs alguém na rotina da equipe — pela regra d14 (vigia, depois.motivo regra_d14) ou pelo "1) Ponho" do dono (depois.motivo contato) — se desfaz dentro do desfazivel_ate: a linha em agenda_equipe_contato fica parada (recebe_rotina false, parou_em, "desfeito pelo dono"; a regra não a põe de novo) e "Desfeito: Rafael sai da rotina da equipe e não recebe mais a ficha nem a pergunta dos dias."; já fora da rotina = nada muda. CORREÇÃO DA REVISÃO DA 7b (achado 18): desfazer a ação que só pôs a 2ª pessoa na dupla (alocações com o motivo dupla_completa) diz "Desfeito: tirei Mateus do Lenine (OS-00074) em ter 10/11 (manhã e tarde); o resto do serviço fica como estava." (não "sai da agenda"); a recusa por sobreposição no serviço com a dupla completada acrescenta "Com Mateus junto, o Lenine acaba antes; se quiser o dia de volta mesmo assim, diga *desfaz Tânia* e depois *desfaz Lenine*.". FASE 7d (P5, §5.5, R6.7c-1): a ação local vai a _agenda_desfazer_local; o replano do "Segure o dia" desfeito direto também volta o "não antes de" (_agenda_local_restaurar) e deixa a ação local desfeita. FASE 7f (P2; §5.2, R8.5-10, R8.5-11): a ação assumir volta antes do caminho genérico: uma pergunta nova, igual à de antes, com a mesma chave, que nasce pelo gatilho com o padrão e sem prazo; a ação fica desfeita. Passou desfazivel_ate (2 dias úteis às veto_hora): a recusa manda dizer com as palavras dele. FASE 7g (P5b): a ação nivel vai a _agenda_desfazer_nivel, sem o prazo de 24 h (o *desfaz espera*: a classe volta a sozinho, travada por rebaixar_trava_dias).';

-- agenda_desfazer_dito (de 20261111100600_agenda_fase7e_rodada.sql:2600; md5 do corpo de antes f90e5d978ac75a1e05c56f2bb128042d)
create or replace function public.agenda_desfazer_dito(p_autor uuid, p_alvo text default null, p_canal text default 'whatsapp',
                                                       p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor uuid := public._autor_da_agenda(p_autor);
  v_ref   jsonb;
  v_id    uuid;
  v_r     jsonb;
  v_txts  text[] := '{}';
  v_falha text;
  -- FASE 6: (P6) o alvo "aprendizado"
  v_aprend boolean := false;
  -- FASE 6: fim
begin
  -- FASE 7g: (7g P5b; §5.5, §6.4, R9.4-4 ponto 7) *desfaz espera*: o tipo de OS que espera o seu ok (agenda_tipos_os.nivel espera_ok; o mais recente) volta a
  -- marcar sozinho pela ação nivel que o pôs lá, por agenda_desfazer (sem o prazo de 24 h nem agenda_acao_desfazivel, que só acha por OS). Sem nenhum em
  -- espera: com modo_rebaixar ligado, "não tenho"; fora dele, o alvo segue o caminho de antes, byte a byte.
  if public._agenda_normal(p_alvo) in ('espera', 'a espera') then
    declare
      v_7g_acao uuid;
    begin
      select t.acao_id into v_7g_acao from public.agenda_tipos_os t
       where t.nivel = 'espera_ok' and t.acao_id is not null order by t.desde desc, t.classe limit 1;
      if v_7g_acao is not null then
        v_r := public.agenda_desfazer(v_7g_acao, v_autor, 'dono', p_hoje, p_agora);
        return jsonb_build_object('ok', coalesce((v_r ->> 'ok')::boolean, false), 'mudou', coalesce((v_r ->> 'ok')::boolean, false),
                                  'acoes', case when coalesce((v_r ->> 'ok')::boolean, false) then jsonb_build_array(v_7g_acao) end, 'texto', v_r ->> 'texto');
      elsif (select c.modo_rebaixar from public.agenda_config c where c.id) = 'ligado' then
        return jsonb_build_object('ok', false, 'mudou', false, 'status', 'nenhuma',
                                  'texto', 'Não tenho tipo de serviço esperando o seu ok agora: eu marco sozinho em todos.');
      end if;
    end;
  end if;
  -- FASE 7g: fim
  -- CORREÇÃO FASE 6: (C2) item 6: *desfaz aprendizado <coisa>* desfaz só o que é daquela coisa — fator, presença, valor (ou
  -- diária), folga, capacidade (ou carga), fornecedor (o atraso e o prazo de todos) ou o nome de um fornecedor (os dois
  -- dele) —: das ações aprendizado ainda desfazíveis que são dela, as do instante mais novo (o mesmo lote), tudo ou nada.
  -- Cada uma trava só a sua chave (_agenda_desfazer_aprendizado); as outras do lote continuam em uso. *desfaz aprendizado*
  -- sozinho continua desfazendo o lote inteiro (abaixo). A coisa que não é item nem fornecedor = nao_achei.
  if public._agenda_normal(p_alvo) ~ '^(o )?aprendizado [a-z0-9]' then
    declare
      v_coisa text := regexp_replace(public._agenda_normal(p_alvo), '^(o )?aprendizado ', '');
      v_itens text[];
      v_ids   uuid[];
      v_de    text;
    begin
      v_itens := case v_coisa
                   when 'fator' then array['fator']
                   when 'presenca' then array['presenca']
                   when 'valor' then array['mo']
                   when 'diaria' then array['mo']
                   when 'folga' then array['aviso_folga']
                   when 'capacidade' then array['capacidade_dono', 'carga']
                   when 'carga' then array['capacidade_dono', 'carga']
                   when 'fornecedor' then array['fornecedor_atraso', 'fornecedor_prazo'] end;
      v_de := case v_coisa
                when 'fator' then 'do fator'
                when 'presenca' then 'da sua presença'
                when 'valor' then 'do valor por diária'
                when 'diaria' then 'do valor por diária'
                when 'folga' then 'da folga do aviso de atraso'
                when 'capacidade' then 'da carga da semana'
                when 'carga' then 'da carga da semana'
                when 'fornecedor' then 'dos fornecedores' end;
      -- (7e P7, R7.5-18; marca sem FASE porque está dentro do bloco da correção C2 da Fase 6) as palavras da margem: *desfaz aprendizado dias* (o tempo das OS: o viés, o geral, as
      -- classes e o dos seus dias), *semana* (a folga da semana) e *compra* (o seu tempo de compra). "folga" continua sendo a do aviso de atraso (aviso_folga), como antes.
      if v_itens is null then
        v_itens := case v_coisa when 'dias' then array['vies'] when 'semana' then array['folga_semana'] when 'compra' then array['tempo_compra'] end;
        v_de := case v_coisa when 'dias' then 'dos dias das OS' when 'semana' then 'da folga da semana' when 'compra' then 'do seu tempo de compra' end;
      end if;
      -- (7e: fim)
      if v_itens is null then
        -- o nome do fornecedor: o curto ("Kamell"), o de exibição, o fantasia ou a razão social, como o dono escreve
        select 'de ' || public._agenda_fornecedor_curto(s.id) into v_de
          from public.suppliers s
         where v_coisa in (public._agenda_normal(public._agenda_fornecedor_curto(s.id)), public._agenda_normal(s.display_name),
                           public._agenda_normal(s.trade_name), public._agenda_normal(s.name))
         order by s.active desc nulls last, s.id
         limit 1;
        if v_de is null then
          return jsonb_build_object('ok', false, 'mudou', false, 'status', 'nao_achei',
            'texto', 'Não achei isso no que eu aprendi. Diga *desfaz aprendizado* e fator, presença, valor, folga, capacidade ou o nome do fornecedor (ou só *desfaz aprendizado*, que volta tudo).');
        end if;
      end if;
      with m as (
        select a.id, a.criada_em, a.antes
          from public.agenda_acoes a
          left join public.suppliers s on a.antes ->> 'item' in ('fornecedor_atraso', 'fornecedor_prazo')
                                      and s.id::text = a.antes ->> 'chave'
         where a.tipo = 'aprendizado' and a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora
           and case when v_itens is not null then a.antes ->> 'item' = any (v_itens)
                    else s.id is not null
                         and v_coisa in (public._agenda_normal(public._agenda_fornecedor_curto(s.id)),
                                         public._agenda_normal(s.display_name), public._agenda_normal(s.trade_name),
                                         public._agenda_normal(s.name)) end)
      select array_agg(m.id order by m.antes ->> 'item', m.antes ->> 'chave', m.id) into v_ids
        from m
       where m.criada_em = (select max(x.criada_em) from m x);
      -- (7e P7; a conferência do P7) no viés, o geral antes das classes do mesmo lote: o *desfaz* de cada classe diz o que ela passa a usar (o geral, _agenda_desfazer_aprendizado), e
      -- o geral do lote já tem de estar desfeito. Nos outros itens, a mesma ordem de antes.
      v_ids := array(select a.id from public.agenda_acoes a where a.id = any (v_ids)
                      order by a.antes ->> 'item', (a.antes ->> 'item' = 'vies' and a.antes ->> 'nivel' = 'todas') desc, a.antes ->> 'chave', a.id);
      -- (7e: fim)
      if coalesce(cardinality(v_ids), 0) = 0 then
        return jsonb_build_object('ok', false, 'mudou', false, 'status', 'nenhuma',
          'texto', format('Não tenho mudança do aprendizado %s para desfazer agora.', v_de));
      end if;
      begin
        foreach v_id in array v_ids loop
          v_r := public.agenda_desfazer(v_id, v_autor, 'dono', p_hoje, p_agora);
          if not coalesce((v_r ->> 'ok')::boolean, false) then
            v_falha := v_r ->> 'texto';
            raise exception using errcode = 'P0098', message = 'desfazer recusado';
          end if;
          v_txts := v_txts || (v_r ->> 'texto');
        end loop;
      exception when sqlstate 'P0098' then
        return jsonb_build_object('ok', false, 'mudou', false, 'texto', v_falha);
      end;
      return jsonb_build_object('ok', true, 'mudou', true, 'acoes', to_jsonb(v_ids), 'texto', array_to_string(v_txts, ' '));
    end;
  end if;
  -- CORREÇÃO FASE 6: fim
  -- FASE 6: (P6) *desfaz aprendizado* (spec-fase6 §5.6): o último lote de ações aprendizado desfazíveis — as do mesmo
  -- instante (o que a mesma rodada ou a mesma decisão mudou: o fator muda as 4 chaves de uma vez) —, tudo ou nada. Sem
  -- nenhuma, "não tenho". Os outros alvos seguem por agenda_acao_desfazivel, como antes
  if public._agenda_normal(p_alvo) in ('aprendizado', 'o aprendizado') then
    v_aprend := true;
    select jsonb_build_object('status', 'ok',
                              'acao_id', (array_agg(a.id order by a.antes ->> 'item', a.antes ->> 'chave', a.id))[1],
                              'acao_ids', jsonb_agg(a.id order by a.antes ->> 'item', a.antes ->> 'chave', a.id))
      into v_ref
      from public.agenda_acoes a
     where a.tipo = 'aprendizado' and a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora
       and a.criada_em = (select max(b.criada_em) from public.agenda_acoes b
                           where b.tipo = 'aprendizado' and b.executada and b.desfeita_em is null and b.desfazivel_ate >= p_agora)
    having count(*) > 0;
    v_ref := coalesce(v_ref, jsonb_build_object('status', 'nenhuma',
                                                'texto', 'Não tenho mudança do aprendizado para desfazer agora.'));
    -- (7e P7; a conferência do P7) no viés, o geral antes das classes do lote (como no *desfaz aprendizado <coisa>*, acima); nos outros itens, a mesma ordem de antes
    if v_ref ? 'acao_ids' then
      v_ref := v_ref || jsonb_build_object('acao_ids', (select jsonb_agg(a.id order by a.antes ->> 'item', (a.antes ->> 'item' = 'vies' and a.antes ->> 'nivel' = 'todas') desc,
                                                                         a.antes ->> 'chave', a.id)
                                                          from public.agenda_acoes a where a.id in (select (jsonb_array_elements_text(v_ref -> 'acao_ids'))::uuid)));
    end if;
    -- (7e: fim)
  else
  -- FASE 6: fim
  v_ref := public.agenda_acao_desfazivel(p_alvo, p_hoje, p_agora);
  -- FASE 6: (P6) o fim do "se é o aprendizado"
  end if;
  -- FASE 6: fim
  if v_ref ->> 'status' is distinct from 'ok' then
    return jsonb_build_object('ok', false, 'mudou', false, 'status', v_ref ->> 'status', 'texto', v_ref ->> 'texto',
                              'opcoes', v_ref -> 'opcoes');
  end if;
  -- "desfaz semana" são várias ações: tudo ou nada
  begin
    for v_id in select x::uuid from jsonb_array_elements_text(coalesce(v_ref -> 'acao_ids', jsonb_build_array(v_ref ->> 'acao_id'))) x loop
      v_r := public.agenda_desfazer(v_id, v_autor, 'dono', p_hoje, p_agora);
      if not coalesce((v_r ->> 'ok')::boolean, false) then
        v_falha := v_r ->> 'texto';
        raise exception using errcode = 'P0098', message = 'desfazer recusado';
      end if;
      v_txts := v_txts || (v_r ->> 'texto');
    end loop;
  exception when sqlstate 'P0098' then
    return jsonb_build_object('ok', false, 'mudou', false, 'texto', v_falha);
  end;
  -- FASE 6: (P6) o lote do aprendizado: os "Desfeito: …" um depois do outro (não é a publicação da semana)
  if v_aprend then
    return jsonb_build_object('ok', true, 'mudou', true, 'acoes', v_ref -> 'acao_ids', 'texto', array_to_string(v_txts, ' '));
  end if;
  -- FASE 6: fim
  return jsonb_build_object('ok', true, 'mudou', true, 'acoes', v_ref -> 'acao_ids',
    'texto', case when cardinality(v_txts) = 1 then v_txts[1]
                  else format('Desfiz a publicação da semana (%s): %s', public._agenda_plural(cardinality(v_txts), 'mudança', 'mudanças'),
                              array_to_string(v_txts, ' ')) end);
end;
$function$;

comment on function public.agenda_desfazer_dito(uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): a palavra *desfaz* (+ o nome, o número ou "semana") — agenda_acao_desfazivel (ambíguo ou nada: a frase pronta, nada muda) + agenda_desfazer(via dono) de cada ação; "semana" é tudo ou nada. Executa direto: é a ordem exata do dono. Admin pelo _autor_da_agenda. Fase 6 (P6): o alvo "aprendizado" = o último lote de ações aprendizado desfazíveis (as do mesmo instante), tudo ou nada; o texto é o "Desfeito: …" de cada uma. CORREÇÃO FASE 6 (C2, item 6): *desfaz aprendizado <coisa>* (fator, presença, valor/diária, folga, capacidade/carga, fornecedor ou o nome de um fornecedor) desfaz só as ações daquela coisa do instante mais novo, tudo ou nada; cada uma trava só a sua chave; *desfaz aprendizado* sozinho continua o lote. A coisa desconhecida = nao_achei; sem mudança = nenhuma. FASE 7e (P7, R7.5-18): *desfaz aprendizado dias* (o viés), *semana* (a folga da semana) e *compra* (o tempo de compra). A recusa da coisa que não existe é a de antes (a saída é a mesma: *desfaz aprendizado* sozinho volta tudo). No lote, o geral do viés antes das classes (o texto de cada classe diz o que ela passa a usar). FASE 7g (P5b): *desfaz espera* desfaz a ação nivel do tipo de OS mais recente em espera_ok (por agenda_tipos_os, não por agenda_acao_desfazivel); sem nenhum, com modo_rebaixar ligado, "não tenho"; fora dele, o caminho de antes.';

-- _agenda_explicar_tipos (de 20261112100400_agenda_fase7g_correcoes.sql:303; md5 do corpo de antes c43c683a81b2419c4470f7f511d2a731)
create or replace function public._agenda_explicar_tipos(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf        public.agenda_config := public._agenda_cfg();
  r         record;
  v_old     public.agenda_tipos_os;
  v_amostra jsonb;
  v_n       int;
  v_corr    int;
  v_seg     int;
  v_teria   text;
  v_txt     text;
  v_cls     int := 0;
  v_esp     int := 0;
  -- FASE 7g: (7g P5b) o nível de verdade
  v_7g_lig   boolean;
  v_7g_ctxt  text;
  v_7g_acao  uuid;
  v_7g_os    uuid;
  v_7g_txt   text;
  v_7g_teste text;
  v_7g_esp   int := 0;
  v_7g_volt  int := 0;
  -- FASE 7g: fim
begin
  if cf.modo_rebaixar = 'desligado' then
    return jsonb_build_object('modo', 'desligado');
  end if;
  for r in select x.classe, (array_agg(x.service_order_id order by x.marcada_em desc, x.acao_id desc))[1] as os
             from public.agenda_marcacoes x where x.quem = 'gestor' group by x.classe order by x.classe loop
    select coalesce(jsonb_agg(jsonb_build_object('os', s.service_order_id, 'acao', s.acao_id, 'desfecho', s.desfecho, 'em', s.desfecho_em)
                              order by s.desfecho_em desc, s.acao_id desc), '[]'::jsonb),
           count(*), count(*) filter (where s.desfecho in ('ajustada', 'desfeita'))
      into v_amostra, v_n, v_corr
      from (select x.service_order_id, x.acao_id, x.desfecho, x.desfecho_em
              from public.agenda_marcacoes x
             where x.quem = 'gestor' and x.classe = r.classe and x.desfecho in ('aceita', 'ajustada', 'desfeita')
               and x.desfecho_em <= p_agora and x.desfecho_em >= p_agora - make_interval(weeks => cf.rebaixar_janela_semanas)
             order by x.desfecho_em desc, x.acao_id desc
             limit cf.rebaixar_amostra) s;
    -- FASE 7g: (7g P5b; §3.1 item 8) as perguntas ok_marcacao respondidas "Não marca" (a opção 2) das OS da classe contam como desfeita na amostra, na mesma
    -- janela e no mesmo teto. Sem nenhuma (o caso de sempre fora de ligado), a amostra de cima, byte a byte.
    if exists (select 1 from public.agenda_perguntas q where q.tipo = 'ok_marcacao' and q.estado = 'respondida' and q.opcao_escolhida = 2) then
      select coalesce(jsonb_agg(jsonb_build_object('os', s.os, 'acao', s.acao, 'desfecho', s.desfecho, 'em', s.em)
                                || case when s.pergunta then jsonb_build_object('pergunta', true) else '{}'::jsonb end
                                order by s.em desc, s.acao desc), '[]'::jsonb),
             count(*), count(*) filter (where s.desfecho in ('ajustada', 'desfeita'))
        into v_amostra, v_n, v_corr
        from (select u.* from (
                select x.service_order_id as os, x.acao_id as acao, x.desfecho, x.desfecho_em as em, false as pergunta
                  from public.agenda_marcacoes x
                 where x.quem = 'gestor' and x.classe = r.classe and x.desfecho in ('aceita', 'ajustada', 'desfeita')
                   and x.desfecho_em <= p_agora and x.desfecho_em >= p_agora - make_interval(weeks => cf.rebaixar_janela_semanas)
                union all
                select q.service_order_id, q.id, 'desfeita', q.respondida_em, true
                  from public.agenda_perguntas q
                 where q.tipo = 'ok_marcacao' and q.estado = 'respondida' and q.opcao_escolhida = 2
                   and q.respondida_em <= p_agora and q.respondida_em >= p_agora - make_interval(weeks => cf.rebaixar_janela_semanas)
                   and public._agenda_classe_de_campo(q.service_order_id) ->> 'chave' = r.classe) u
               order by u.em desc, u.acao desc
               limit cf.rebaixar_amostra) s;
    end if;
    -- FASE 7g: fim
    -- as aceitas seguidas, da mais nova para trás
    v_seg := coalesce((select min(t.o) - 1 from jsonb_array_elements(v_amostra) with ordinality t(e, o) where t.e ->> 'desfecho' <> 'aceita'),
                      jsonb_array_length(v_amostra));
    select * into v_old from public.agenda_tipos_os t where t.classe = r.classe;
    v_teria := case when v_old.travado_ate is not null and v_old.travado_ate >= p_hoje then 'sozinho'
                    when v_n > 0 and v_n >= cf.rebaixar_n_min and v_corr::numeric / v_n >= cf.rebaixar_taxa then 'espera_ok'
                    else 'sozinho' end;
    v_txt := case when v_teria = 'espera_ok'
                  then left(format('Em teste: nas OS de %s eu passaria a esperar o seu ok (você corrigiu %s de %s).',
                                   coalesce(public._agenda_classe_de_campo(r.os) ->> 'texto', r.classe), v_corr, v_n), 300) end;
    -- FASE 7g: (7g P5b; §6.5) a classe que espera o ok (o nível, de verdade) guarda o texto do nível, que o placar lê, no lugar do "Em teste" do teria; o de
    -- teste fica para a volta a sozinho.
    v_7g_teste := v_txt;
    if v_old.nivel = 'espera_ok' then
      v_txt := left(format('Nas OS de %s eu espero o seu ok antes de marcar, desde %s.',
                           coalesce(public._agenda_classe_de_campo(r.os) ->> 'texto', r.classe),
                           public._dia_curto((v_old.desde at time zone 'America/Sao_Paulo')::date)), 300);
    end if;
    -- FASE 7g: fim
    insert into public.agenda_tipos_os as t (classe, teria, n, corrigidas, aceitas_seguidas, amostra, calculado_em, texto, historico)
    values (r.classe, v_teria, v_n, v_corr, v_seg, v_amostra, p_agora, v_txt,
            jsonb_build_array(jsonb_build_object('em', p_agora, 'antes', null, 'depois', jsonb_build_object('teria', v_teria, 'n', v_n, 'corrigidas', v_corr))))
    on conflict (classe) do update
       set teria = excluded.teria, n = excluded.n, corrigidas = excluded.corrigidas, aceitas_seguidas = excluded.aceitas_seguidas,
           amostra = excluded.amostra, calculado_em = excluded.calculado_em, texto = excluded.texto,
           historico = case when t.teria is distinct from excluded.teria
                            then public._os_material_historico(t.historico, jsonb_build_object(
                                   'em', p_agora, 'antes', jsonb_build_object('teria', t.teria, 'n', t.n, 'corrigidas', t.corrigidas),
                                   'depois', jsonb_build_object('teria', excluded.teria, 'n', excluded.n, 'corrigidas', excluded.corrigidas)))
                            else t.historico end
     where (t.teria, t.n, t.corrigidas, t.aceitas_seguidas, t.amostra, t.texto)
           is distinct from (excluded.teria, excluded.n, excluded.corrigidas, excluded.aceitas_seguidas, excluded.amostra, excluded.texto);
    -- FASE 7g: (7g P5b; §5.5, §3.1 item 8, §6.4, R9.4-4, R9.6; AG7-25) o nível de verdade, só com o rebaixar ligado e o gestor marcando sozinho: modo_rebaixar
    -- ligado, _agenda_gestor_modo('marcar') e _agenda_fala_modo('veto') ligados (com *gestor, só propor* ou sem o veto ligado, age como sombra: só o teria de
    -- cima). sozinho com teria espera_ok (a trava já está no teria) → espera_ok: a ação nivel (vigia, executada; o *desfaz espera* não depende do prazo dela)
    -- e o nível na linha. espera_ok com voltar_n aceitas seguidas → sozinho: a ação nivel de volta (não se desfaz) e o espera_ok_desde das OS da classe
    -- limpo. Em espera_ok, a OS da carteira da classe ainda sem dia marcado e sem o ok ganha espera_ok_desde (insert … on conflict: só 4 de 131 OS têm a
    -- linha, R9.4-4 ponto 2); a já marcada fica como está.
    if v_7g_lig is null then
      v_7g_lig := cf.modo_rebaixar = 'ligado' and public._agenda_gestor_modo('marcar') = 'ligado' and public._agenda_fala_modo('veto') = 'ligado';
    end if;
    if v_7g_lig and coalesce(v_old.nivel, 'sozinho') = 'sozinho' and v_teria = 'espera_ok' then
      v_7g_ctxt := coalesce(public._agenda_classe_de_campo(r.os) ->> 'texto', r.classe);
      v_7g_txt := format('Nas OS de %s você corrigiu %s das minhas últimas %s marcações. A partir de agora, nelas eu reservo e espero o seu ok antes de valer '
                         || '(a equipe e o cliente só sabem depois). *desfaz espera* volta.', v_7g_ctxt, v_corr, v_n);
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, antes, depois, texto, desfazivel_ate)
      values (clock_timestamp(), p_hoje, true, 'vigia', 'nivel', jsonb_build_object('classe', r.classe, 'nivel', 'sozinho'),
              jsonb_build_object('classe', r.classe, 'nivel', 'espera_ok', 'n', v_n, 'corrigidas', v_corr), left(v_7g_txt, 400),
              p_agora + cf.desfazer_validade)
      returning id into v_7g_acao;
      update public.agenda_tipos_os t
         set nivel = 'espera_ok', desde = p_agora, acao_id = v_7g_acao,
             texto = left(format('Nas OS de %s eu espero o seu ok antes de marcar, desde %s.', v_7g_ctxt,
                                 public._dia_curto((p_agora at time zone 'America/Sao_Paulo')::date)), 300),
             historico = public._os_material_historico(t.historico, jsonb_build_object('em', p_agora, 'antes', jsonb_build_object('nivel', 'sozinho'),
                           'depois', jsonb_build_object('nivel', 'espera_ok', 'n', v_n, 'corrigidas', v_corr), 'acao', v_7g_acao))
       where t.classe = r.classe;
      v_7g_esp := v_7g_esp + 1;
    elsif v_7g_lig and v_old.nivel = 'espera_ok' and v_seg >= cf.voltar_n then
      v_7g_ctxt := coalesce(public._agenda_classe_de_campo(r.os) ->> 'texto', r.classe);
      v_7g_txt := format('Nas OS de %s as minhas últimas %s marcações ficaram como fiz: volto a marcar sozinho nelas. Você continua podendo corrigir.',
                         v_7g_ctxt, v_seg);
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, antes, depois, texto)
      values (clock_timestamp(), p_hoje, true, 'vigia', 'nivel', jsonb_build_object('classe', r.classe, 'nivel', 'espera_ok', 'desde', v_old.desde),
              jsonb_build_object('classe', r.classe, 'nivel', 'sozinho', 'aceitas', v_seg), left(v_7g_txt, 400))
      returning id into v_7g_acao;
      update public.agenda_tipos_os t
         set nivel = 'sozinho', desde = null, acao_id = v_7g_acao, texto = v_7g_teste,
             historico = public._os_material_historico(t.historico, jsonb_build_object('em', p_agora, 'antes', jsonb_build_object('nivel', 'espera_ok'),
                           'depois', jsonb_build_object('nivel', 'sozinho', 'aceitas', v_seg), 'acao', v_7g_acao))
       where t.classe = r.classe;
      update public.os_planejamento pl set espera_ok_desde = null
       where pl.espera_ok_desde is not null and pl.ok_do_dono_em is null
         and public._agenda_classe_de_campo(pl.service_order_id) ->> 'chave' = r.classe;
      v_7g_volt := v_7g_volt + 1;
    end if;
    if v_7g_lig and (select t.nivel from public.agenda_tipos_os t where t.classe = r.classe) = 'espera_ok' then
      for v_7g_os in select k.service_order_id from public.os_carteira(p_hoje) k order by 1 loop
        continue when public._agenda_classe_de_campo(v_7g_os) ->> 'chave' is distinct from r.classe;
        continue when public._agenda_os_tem_dia(v_7g_os, p_hoje);
        insert into public.os_planejamento as pl (service_order_id, espera_ok_desde) values (v_7g_os, p_agora)
        on conflict (service_order_id) do update set espera_ok_desde = excluded.espera_ok_desde
         where pl.espera_ok_desde is null and pl.ok_do_dono_em is null;
      end loop;
    end if;
    -- FASE 7g: fim
    v_cls := v_cls + 1;
    if v_teria = 'espera_ok' then
      v_esp := v_esp + 1;
    end if;
  end loop;
  -- FASE 7g: (7g P5b) quantas passaram a esperar o ok e quantas voltaram a marcar sozinhas (sem nenhuma, o retorno de antes)
  if v_7g_esp + v_7g_volt > 0 then
    return jsonb_build_object('classes', v_cls, 'teria', v_esp, 'espera_ok', v_7g_esp, 'voltaram', v_7g_volt);
  end if;
  -- FASE 7g: fim
  return jsonb_build_object('classes', v_cls, 'teria', v_esp, 'espera_ok', 0, 'voltaram', 0);
end;
$function$;

comment on function public._agenda_explicar_tipos(date, timestamptz) is
  'Agenda de Produção (Fase 7g, P5; §3.1 item 8, R9.4-4, AG7-25): o passo tipos da rodada explicar. modo_rebaixar desligado = {modo: desligado}, nada gravado. Para cada classe com marcação do gestor: a amostra (as rebaixar_amostra mais novas decididas aceita, ajustada ou desfeita, com desfecho_em nas rebaixar_janela_semanas até p_agora), n, corrigidas (ajustada + desfeita), as aceitas seguidas da mais nova para trás, teria = espera_ok com n > 0, n ≥ rebaixar_n_min e corrigidas ÷ n ≥ rebaixar_taxa, fora da trava (travado_ate ≥ hoje), senão sozinho; texto só com espera_ok ("Em teste: nas OS de <classe> eu passaria a esperar o seu ok (você corrigiu N de M)."). Upsert em agenda_tipos_os só quando algo mudou (2× = 1×); o histórico ganha uma entrada quando teria muda. O nível NÃO muda (é do P5b): em sombra e em ligado, só teria e texto. {classes, teria (quantas teriam espera_ok), espera_ok: 0, voltaram: 0}. Invoker, só service_role. FASE 7g (P5b): as perguntas ok_marcacao respondidas 2 contam como desfeita na amostra; com modo_rebaixar ligado e _agenda_gestor_modo(marcar) e _agenda_fala_modo(veto) ligados, o nível muda: sozinho com teria espera_ok → espera_ok (a ação nivel, origem vigia, desfazível pelo *desfaz espera*), espera_ok com voltar_n aceitas seguidas → sozinho (a ação nivel de volta; espera_ok_desde das OS da classe limpo); em espera_ok, as OS da carteira da classe sem dia marcado e sem o ok ganham espera_ok_desde; o texto da linha em espera_ok é o do nível. {classes, teria, espera_ok, voltaram} com os números de verdade.';

-- agenda_explicar_rodar (de 20261112100400_agenda_fase7g_correcoes.sql:376; md5 do corpo de antes 49c8737529162699e8c26e9b7aa1e769)
create or replace function public.agenda_explicar_rodar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf       public.agenda_config;
  v_uid    uuid := auth.uid();
  v_t0     timestamptz := clock_timestamp();
  v_passos text[];
  v_passo  text;
  v_r      jsonb;
  v_cont   jsonb := '{}'::jsonb;
  v_erros  int := 0;
  v_falhas jsonb := '[]'::jsonb;
  v_parou  text;
  v_estado text;
  v_msg    text;
  -- FASE 7g: (7g P5b) o passo ok
  v_7g_ok  jsonb;
  -- FASE 7g: fim
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da rodada explicar.' using errcode = '22023';
  end if;
  -- Quem roda: sem login, o service_role (o task-automations); com login, só administrador e financeiro.
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
  end if;
  cf := public._agenda_cfg();
  -- FASE 7g: (7g P5b; §5.5 "em todo tique: ok", R9.4-4) o passo ok roda a cada tique, antes do resto e em qualquer dia e hora: a pergunta ok_marcacao nasce no
  -- tique da reserva ok_do_dono (o zero ok_sem_pergunta da saúde cobra), e a que ficou sem a reserva fecha. Só com modo_rebaixar ligado ou com pergunta
  -- ok_marcacao aberta: sem isso, a rodada de antes, byte a byte (com a consulta das abertas a mais). Erro (também o tempo) → app_error_logs (explicar:ok) e o
  -- resto segue. Não grava linha: o resultado vai em contagens.ok da linha do dia, quando ela roda e o passo fez algo.
  if cf.modo_rebaixar = 'ligado' or exists (select 1 from public.agenda_perguntas q where q.tipo = 'ok_marcacao' and q.estado = 'aberta') then
    begin
      v_7g_ok := public._agenda_explicar_ok(p_hoje, p_agora);
    exception when query_canceled or others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_7g_ok := jsonb_build_object('erro', left(v_msg, 300));
      perform public.log_app_error('db', format('explicar, passo ok: %s', v_msg), 'agenda', 'explicar:ok', 'error',
                                   jsonb_build_object('passo', 'ok', 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end if;
  -- FASE 7g: fim
  if cf.modo_porque = 'desligado' and cf.modo_rebaixar = 'desligado' and cf.modo_placar = 'desligado' then
    return jsonb_build_object('rodou', false, 'desligado', true);
  end if;
  if extract(isodow from p_hoje)::int = 7 then
    return jsonb_build_object('rodou', false, 'domingo', true);
  end if;
  if (p_agora at time zone 'America/Sao_Paulo')::time < cf.explicar_hora then
    return jsonb_build_object('rodou', false, 'cedo', true, 'hora', cf.explicar_hora);
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_explicar_rodar'));
  if exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'explicar' and x.p_hoje = p_hoje) then
    return jsonb_build_object('rodou', false, 'ja_rodou', true);
  end if;
  -- os passos de hoje: o placar é do P6 (sem a função, não entra)
  v_passos := case when cf.modo_porque <> 'desligado' then array['marcacoes'] else '{}'::text[] end
           || case when cf.modo_rebaixar <> 'desligado' then array['tipos'] else '{}'::text[] end
           || case when cf.modo_placar <> 'desligado' and extract(isodow from p_hoje)::int = cf.dia_do_plano
                        and to_regprocedure('public._agenda_explicar_placar(date, timestamp with time zone)') is not null
                   then array['placar'] else '{}'::text[] end;
  if cardinality(v_passos) = 0 then
    return jsonb_build_object('rodou', false, 'nada', true);
  end if;
  foreach v_passo in array v_passos loop
    if clock_timestamp() - v_t0 > cf.explicar_tempo_max then
      v_parou := v_passo;
      exit;
    end if;
    begin
      execute format('select public.%I($1, $2)', '_agenda_explicar_' || v_passo) into v_r using p_hoje, p_agora;
      v_cont := v_cont || jsonb_build_object(v_passo, coalesce(v_r, '{}'::jsonb));
    exception
      -- when others não pega query_canceled (o corte de 30 s do service_role): registra, grava a rodada com parou_no e encerra; o tique seguinte não repete
      when query_canceled then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        v_erros := v_erros + 1;
        v_parou := v_passo;
        v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
        perform public.log_app_error('db', format('explicar, passo %s: o tempo da rodada acabou (%s)', v_passo, v_msg), 'agenda',
                                     'explicar:' || v_passo, 'error',
                                     jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora,
                                                        'tempo_max', cf.explicar_tempo_max::text));
        exit;
      when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        v_erros := v_erros + 1;
        v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
        perform public.log_app_error('db', format('explicar, passo %s: %s', v_passo, v_msg), 'agenda',
                                     'explicar:' || v_passo, 'error',
                                     jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end loop;
  v_cont := v_cont || jsonb_build_object('modos', jsonb_build_object('porque', cf.modo_porque, 'rebaixar', cf.modo_rebaixar, 'placar', cf.modo_placar),
                                         'falhas', v_falhas)
            || case when v_parou is not null then jsonb_build_object('parou_no', v_parou) else '{}'::jsonb end;
  -- FASE 7g: (7g P5b) o passo ok deste tique na linha do dia, quando fez algo (criou, fechou ou falhou)
  if v_7g_ok ? 'erro' or coalesce((v_7g_ok ->> 'criadas')::int, 0) + coalesce((v_7g_ok ->> 'fechadas')::int, 0) > 0 then
    v_cont := v_cont || jsonb_build_object('ok', v_7g_ok);
  end if;
  -- FASE 7g: fim
  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms, rotina, modo_equipe, modo_diaria)
  values (clock_timestamp(), p_hoje, p_agora, cf.modo_proposta, cf.modo_vigia, v_cont, least(v_erros, 32767),
          greatest(0, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int), 'explicar', cf.modo_equipe, cf.modo_diaria);
  return jsonb_build_object('rodou', true, 'diaria', true, 'contagens', v_cont - 'falhas' - 'modos' - 'parou_no', 'modos', v_cont -> 'modos',
                            'erros', v_erros, 'falhas', v_falhas)
         || case when v_parou is not null then jsonb_build_object('parou_no', v_parou) else '{}'::jsonb end;
end;
$function$;

comment on function public.agenda_explicar_rodar(date, timestamptz) is
  'Agenda de Produção (Fase 7g, P5; §5.5, R9.5-8, R9.5-9, R9.5-21): a rodada explicar, pelo task-automations a cada tique (agenda-explicar.ts, antes da rodada comunicar). modo_porque, modo_rebaixar e modo_placar desligados = {rodou: false, desligado}; domingo = {rodou: false, domingo}; antes de explicar_hora = {rodou: false, cedo, hora}; a rodada de hoje já gravada = {rodou: false, ja_rodou}; nenhum passo a rodar = {rodou: false, nada}: nenhuma dessas grava linha. Passos, cada um no seu bloco: marcacoes (modo_porque fora de desligado; _agenda_explicar_marcacoes), tipos (modo_rebaixar fora de desligado; _agenda_explicar_tipos) e, no dia_do_plano, placar (modo_placar fora de desligado e _agenda_explicar_placar existindo, do P6). O relógio explicar_tempo_max antes de cada passo: passou, a rodada grava parou_no e o resto fica para amanhã. Erro de um passo → app_error_logs (agenda, explicar:<passo>) e segue; query_canceled → app_error_logs, parou_no e encerra (a linha do dia fica: o tique seguinte não repete). Uma linha em agenda_vigia_rodadas (rotina explicar; contagens: os passos, modos, falhas e parou_no). {rodou: true, diaria, contagens, modos, erros, falhas, parou_no}. Nenhuma mensagem. SECURITY DEFINER; sem login, o service_role; com login, só admin/financeiro (42501). Só service_role tem execute. FASE 7g (P5b): a cada tique, antes do resto e em qualquer dia, com modo_rebaixar ligado ou pergunta ok_marcacao aberta: o passo ok (_agenda_explicar_ok; erro → app_error_logs explicar:ok, e segue); o resultado vai em contagens.ok da linha do dia quando o passo fez algo.';

-- _agenda_saude_explicar (de 20261112100500_agenda_fase7g_placar.sql:848; md5 do corpo de antes 1be352347492cf36427707bd3ca87606)
create or replace function public._agenda_saude_explicar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  -- estrutural: os números "em 7 dias" (o porquê e a zona que ficaram sem gravar)
  c_janela constant int := 7;
  -- estrutural: as ações que mexem no plano (R9.5-16; a lista do gatilho da zona, 20261112100100)
  c_mexem  constant text[] := array['publicar', 'criar', 'mover', 'cancelar', 'fixar', 'promover_reserva', 'soltar_reserva', 'reparar', 'reestimar'];
  -- FASE 7g: (7g P5b) estrutural: a pergunta ok_marcacao nasce no tique da reserva; um tique do motor e mais um de folga (§11, aceite 6)
  c_7g_tique constant interval := '30 minutes';
  -- FASE 7g: fim
  cf       public.agenda_config;
  v_uid    uuid := auth.uid();
  v_papel  text;
  v_hora   time;
  v_desde  timestamptz;
  v_z      jsonb;
  v_n      jsonb;
begin
  -- Quem vê: com login, só admin/financeiro; sem login, só o service_role (a porta de _agenda_saude_margem).
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'A saúde da agenda é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'A saúde da agenda é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_saude_explicar: sem o dia de hoje ou a hora' using errcode = '22004';
  end if;
  cf := public._agenda_cfg();
  v_hora := (p_agora at time zone 'America/Sao_Paulo')::time;
  -- a janela dos números: desde marcacoes_desde, até 7 dias; sem marcacoes_desde, nada (R9.12-2: o nulo explícito)
  v_desde := case when cf.marcacoes_desde is null then p_agora
                  else greatest(cf.marcacoes_desde, p_agora - make_interval(days => c_janela)) end;
  -- Os zeros obrigatórios (entram no ok).
  v_z := jsonb_build_object(
    -- o placar da semana não guardado até explicar_hora + 1 hora do dia_do_plano, com modo_placar fora de desligado (§11, aceite 8)
    'placar_atrasado', case
       when cf.modo_placar = 'desligado' then 0
       when extract(isodow from p_hoje)::int <> cf.dia_do_plano then 0
       when v_hora < cf.explicar_hora + interval '1 hour' then 0
       when exists (select 1 from public.agenda_placar_semanas s where s.semana = (public._agenda_placar_periodo(p_hoje) ->> 'semana')::date) then 0
       else 1 end,
    -- a marcação ainda aberta depois da janela de correção (o dia da marcação + correcao_janela_du dias úteis já passou): a rodada que decide não rodou. Só com
    -- modo_porque fora de desligado (desligado, a rodada não decide nada)
    'marcacao_aberta_vencida', case when cf.modo_porque = 'desligado' then 0 else (
       select count(*) from public.agenda_marcacoes m
        where m.desfecho = 'aberta'
          and public.agenda_somar_du((m.marcada_em at time zone 'America/Sao_Paulo')::date, cf.correcao_janela_du) < p_hoje) end,
    -- o rebaixar ligado sem o veto ligado (o rebaixar agiria como sombra: R9.6, §11)
    'rebaixar_sem_veto', case when cf.modo_rebaixar = 'ligado' and public._agenda_fala_modo('veto') <> 'ligado' then 1 else 0 end,
    -- dia que não é domingo, depois de explicar_hora + 1 hora, com o porquê ou o rebaixar fora de desligado (os passos diários da rodada), e nenhuma rodada
    -- explicar de hoje (o molde de rodada_puxar_atrasada da margem: o domingo não roda, e o "em 26 h" acenderia toda segunda)
    'rodada_atrasada', case
       when cf.modo_porque = 'desligado' and cf.modo_rebaixar = 'desligado' then 0
       when extract(isodow from p_hoje)::int = 7 then 0
       when v_hora < cf.explicar_hora + interval '1 hour' then 0
       when exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'explicar' and x.p_hoje = p_hoje) then 0
       else 1 end,
    -- os erros da 7g em 1 dia (a rodada explicar, o porquê do motor e a zona da ação: explicar:%; §11, aceite 11)
    'erros_dia', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.action like 'explicar:%' and e.last_seen_at > p_agora - interval '1 day' and e.last_seen_at <= p_agora));
  -- FASE 7g: (7g P5b; §11 aceites 6 e 7) os zeros do ok do dono, em todo modo (0 sem reserva ok_do_dono e sem nível): ok_sem_pergunta = a OS com reserva
  -- ok_do_dono vigente nascida há mais de c_7g_tique sem a pergunta ok_marcacao aberta, nem uma nascida depois dela; nivel_sem_aviso = o tipo de OS cujo nível
  -- não é o que a ação nivel dele diz (em espera_ok sem a ação nivel que o pôs lá, valendo; em sozinho com essa ação ainda valendo).
  v_z := v_z || jsonb_build_object(
    'ok_sem_pergunta', (select count(*) from (
        select a.service_order_id as os, min(a.criado_em) as pub
          from public.agenda_alocacoes a
         where a.tipo = 'reserva' and a.condicao_tipo = 'ok_do_dono' and a.estado in ('publicada', 'fixada') and a.resultado is null and a.dia >= p_hoje
         group by a.service_order_id) r
       where r.pub <= p_agora - c_7g_tique
         and not exists (select 1 from public.agenda_perguntas q
                          where q.tipo = 'ok_marcacao' and q.service_order_id = r.os and (q.estado = 'aberta' or q.criada_em >= r.pub))),
    'nivel_sem_aviso', (select count(*) from public.agenda_tipos_os t
                          left join public.agenda_acoes x on x.id = t.acao_id
                         where case when t.nivel = 'espera_ok'
                                    then x.id is null or x.tipo is distinct from 'nivel' or x.desfeita_em is not null
                                         or x.depois ->> 'nivel' is distinct from 'espera_ok'
                                    else x.id is not null and x.tipo = 'nivel' and x.desfeita_em is null and x.depois ->> 'nivel' = 'espera_ok' end));
  -- FASE 7g: fim
  -- Os números (nenhum reprova): a última rodada, as marcações por desfecho, os tipos em teste, o último placar guardado e, em 7 dias desde marcacoes_desde,
  -- as alocações vigentes sem o porquê e as ações que mexeram no plano sem a zona (com o porquê fora de desligado)
  v_n := jsonb_build_object(
    'ultima_rodada', (select jsonb_build_object('p_hoje', x.p_hoje, 'erros', x.erros, 'parou_no', x.contagens ->> 'parou_no')
                        from public.agenda_vigia_rodadas x where x.rotina = 'explicar'
                       order by x.p_agora desc, x.rodou_em desc, x.id desc limit 1),
    'marcacoes', coalesce((select jsonb_object_agg(t.k, t.n)
                             from (select coalesce(m.desfecho, 'do_dono') as k, count(*) as n from public.agenda_marcacoes m group by 1) t), '{}'::jsonb),
    'tipos_teria', (select count(*) from public.agenda_tipos_os t where t.teria = 'espera_ok'),
    'placar', (select jsonb_build_object('semana', s.semana, 'versao', s.versao, 'modo', s.modo, 'enviado', s.enviado_em is not null)
                 from public.agenda_placar_semanas s order by s.semana desc limit 1),
    'alocacoes_sem_porque', case when cf.modo_porque = 'desligado' or cf.marcacoes_desde is null then 0 else (
       select count(*) from public.agenda_alocacoes a
        where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.suposicoes is null and a.criado_em >= v_desde and a.criado_em <= p_agora) end,
    'acoes_sem_zona', case when cf.modo_porque = 'desligado' or cf.marcacoes_desde is null then 0 else (
       select count(*) from public.agenda_acoes a
        where a.executada and a.zona is null and a.tipo = any (c_mexem) and a.criada_em >= v_desde and a.criada_em <= p_agora
          and cardinality(coalesce(a.alocacoes_criadas, '{}'::uuid[])) + cardinality(coalesce(a.alocacoes_canceladas, '{}'::uuid[])) > 0) end);
  return jsonb_build_object('zeros_ok', not exists (select 1 from jsonb_each(v_z) z where (z.value)::text <> '0'), 'numeros', v_n) || v_z;
end;
$function$;

comment on function public._agenda_saude_explicar(date, timestamptz) is
  'Agenda de Produção (Fase 7g, P6; §11, R9.5-17): a chave explicar de agenda_saude — os zeros obrigatórios (entram no ok; zeros_ok): placar_atrasado (dia_do_plano, depois de explicar_hora + 1 hora, modo_placar fora de desligado e a semana sem linha em agenda_placar_semanas), marcacao_aberta_vencida (aberta depois do dia da marcação + correcao_janela_du dias úteis, com modo_porque fora de desligado), rebaixar_sem_veto (modo_rebaixar ligado e o veto fora de ligado), rodada_atrasada (porquê ou rebaixar fora de desligado, não é domingo, depois de explicar_hora + 1 hora e nenhuma rodada explicar de hoje) e erros_dia (app_error_logs da agenda com action explicar:% no dia até p_agora); e os números (ultima_rodada, marcacoes por desfecho, tipos_teria, o último placar guardado, alocacoes_sem_porque e acoes_sem_zona em 7 dias desde marcacoes_desde). ok_sem_pergunta e nivel_sem_aviso são do P5b; explicar_divergencias não é contado (nada guarda o de antes). Sem os modos dentro: a chave existe em todos os modos. Definer, a porta de _agenda_saude_margem (admin/financeiro ou service_role; 42501); sem o dia ou a hora, 22004. FASE 7g (P5b): mais 2 zeros no ok: ok_sem_pergunta (reserva ok_do_dono vigente há mais de 30 minutos sem a pergunta ok_marcacao) e nivel_sem_aviso (o nível do tipo de OS diferente do que a ação nivel dele diz).';

-- agenda_tela_semana (de 20261112100600_agenda_fase7g_tela.sql:493; md5 do corpo de antes 1491d1fc43940ccf0d0a6dd8cbdf3a9a)
create or replace function public.agenda_tela_semana(p_de date default null, p_hoje date default public._hoje_brt(),
                                                     p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_uid    uuid := auth.uid();
  v_seg    date;
  v_prop   uuid;
  v_teste  boolean := cf.modo_proposta = 'sombra';
  v_dias   jsonb;
  v_comp   int;
  v_livre  numeric;
  v_ppc    numeric;
  v_sem    jsonb;
  v_den    int;
  v_lv     jsonb;
  v_titulo text;
  v_dec    jsonb;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_tela_semana: sem o dia ou a hora de agora' using errcode = '22004';
  end if;
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
  end if;
  v_seg := coalesce(p_de, p_hoje) - (extract(isodow from coalesce(p_de, p_hoje))::int - 1);

  if cf.modo_proposta = 'desligado' then
    return jsonb_build_object('modo', cf.modo_proposta, 'em_teste', false, 'de', v_seg, 'ate', v_seg + 5,
      'titulo', 'A agenda automática está desligada: não há plano publicado.',
      'resumo', null, 'comprometido_pct', null, 'livre_diarias', null, 'ppc_anterior', null, 'livre_de_verdade', null,
      'dias', '[]'::jsonb, 'mudancas', '[]'::jsonb, 'decisoes', '[]'::jsonb, 'como_responder', null);
  end if;
  -- Em sombra nada é publicado: os blocos são os da última semana que a sombra montou para estes dias.
  if v_teste then
    select pr.id into v_prop from public.agenda_propostas pr
     where pr.modo = 'sombra' and pr.escopo = 'semana' and pr.periodo && daterange(v_seg, v_seg + 6, '[]')
     order by pr.criada_em desc, pr.id desc limit 1;
  end if;

  with
  a0 as (
    select x.* from public.agenda_alocacoes x
     where (not v_teste and x.estado in ('publicada', 'fixada'))
        or (v_prop is not null and x.estado = 'proposta' and x.proposta_id = v_prop)
  ),
  na_semana as (select distinct x.service_order_id from a0 x where x.dia between v_seg and v_seg + 6),
  -- o "dia n de N" pela OS inteira (o dia em que nada foi cumprido não conta, como em v_agenda_dia)
  dias_os as (
    select d.service_order_id, d.dia,
           (row_number() over (partition by d.service_order_id order by d.dia))::int as dia_n,
           (count(*) over (partition by d.service_order_id))::int as dias_total
      from (select x.service_order_id, x.dia from a0 x join na_semana s using (service_order_id)
             where x.tipo <> 'reserva' group by x.service_order_id, x.dia
            having bool_or(x.resultado is distinct from 'nao_cumprido')) d
  ),
  a as (select x.* from a0 x where x.dia between v_seg and v_seg + 6),
  pp as (
    select a.dia, a.service_order_id, a.payee_id,
           array_agg(distinct a.turno order by a.turno) as turnos,
           case when bool_or(a.presenca = 'turno') then 'turno'
                when bool_or(a.presenca = 'abertura') and bool_or(a.presenca = 'fechamento') then 'abre_e_fecha'
                when bool_or(a.presenca = 'abertura') then 'abertura'
                else 'fechamento' end as presenca,
           min(lower(a.periodo)) as ini
      from a group by a.dia, a.service_order_id, a.payee_id
  ),
  pe as (
    select pp.dia, pp.service_order_id,
           jsonb_agg(jsonb_build_object('payee_id', pp.payee_id, 'nome', x.j ->> 'nome',
                                        'eh_dono', coalesce((x.j ->> 'eh_dono')::boolean, false),
                                        'turnos', to_jsonb(pp.turnos), 'presenca', pp.presenca)
                     order by coalesce((x.j ->> 'eh_dono')::boolean, false) desc, pp.ini, x.j ->> 'nome', pp.payee_id) as pessoas
      from pp cross join lateral (select public._agenda_pessoa(pp.payee_id) as j) x
     group by pp.dia, pp.service_order_id
  ),
  g as (
    select a.dia, a.service_order_id,
           bool_and(a.tipo = 'reserva') as reserva,
           case when bool_and(a.tipo = 'reserva') then 'reserva' else min(a.tipo) filter (where a.tipo <> 'reserva') end as tipo,
           min(a.reserva_de) filter (where a.tipo = 'reserva') as reserva_de,
           min(a.condicao) filter (where a.tipo = 'reserva') as condicao,
           -- FASE 7g: (7g P5b; §5.7) a reserva que espera o ok do dono (condição ok_do_dono)
           coalesce(bool_or(a.condicao_tipo = 'ok_do_dono') filter (where a.tipo = 'reserva'), false) as ok_do_dono,
           -- FASE 7g: fim
           min(lower(a.periodo)) as ini,
           bool_or(a.estado = 'fixada') as fixada,
           case when coalesce(bool_and(a.resultado is null) filter (where a.tipo <> 'reserva'), true) then null
                when bool_or(a.resultado = 'cumprido') then 'cumprido'
                when bool_or(a.resultado = 'parcial') then 'parcial'
                when bool_or(a.resultado = 'sem_registro') then 'sem_registro'
                else 'nao_cumprido' end as resultado
      from a group by a.dia, a.service_order_id
  ),
  blocos as (
    select g.dia, jsonb_agg(jsonb_build_object(
             'os', g.service_order_id, 'numero', so.service_order_number, 'cliente', public._agenda_nome_curto(cl.name),
             'bem', v.name, 'local', coalesce(m.name, nullif(btrim(cl.city), '')),
             'hora', to_char(g.ini at time zone 'America/Sao_Paulo', 'HH24:MI'),
             'pessoas_texto', nullif(public._agenda_pessoas_do_dia(pe.pessoas), ''),
             'dia_n', d.dia_n, 'dias_total', d.dias_total,
             'dia_texto', case when coalesce(d.dias_total, 1) > 1 and d.dia_n is not null
                               then format('dia %s de %s', d.dia_n, d.dias_total) end,
             'confirmado_cliente', coalesce((so.client_confirmed_for at time zone 'America/Sao_Paulo')::date = g.dia, false),
             'reserva', g.reserva,
             'reserva_texto', case when g.reserva then case when g.reserva_de = 'patio' then 'Reserva no pátio, a confirmar'
                                                            else 'Reserva, a confirmar' end end,
             'condicao', g.condicao, 'tipo', g.tipo, 'fixada', g.fixada, 'resultado', g.resultado,
             -- FASE 7g: (7g P5b; §5.7) a reserva que espera o seu ok diz isso no lugar de "a confirmar" (a chave repetida: no jsonb vale a de baixo, a daqui; sem
             -- a condição ok_do_dono, o mesmo valor de cima)
             'reserva_texto', case when g.reserva and g.ok_do_dono then 'Reserva, esperando o seu ok'
                                   when g.reserva then case when g.reserva_de = 'patio' then 'Reserva no pátio, a confirmar' else 'Reserva, a confirmar' end end,
             -- FASE 7g: fim
             'resultado_texto', case g.resultado when 'cumprido' then 'feito' when 'parcial' then 'feito em parte'
                                                 when 'sem_registro' then 'sem registro' when 'nao_cumprido' then 'não aconteceu' end)
             order by g.ini, so.service_order_number, g.service_order_id) as blocos
      from g
      join public.service_orders so on so.id = g.service_order_id
      left join public.clients cl on cl.id = so.client_id
      left join public.vessels v on v.id = so.vessel_id
      left join public.marinas m on m.id = so.marina_id
      left join pe on pe.dia = g.dia and pe.service_order_id = g.service_order_id
      left join dias_os d on d.service_order_id = g.service_order_id and d.dia = g.dia
     group by g.dia
  ),
  cap as (select k.* from public.agenda_capacidade(v_seg, v_seg + 6, p_hoje) k),
  usado as (select a.payee_id, a.dia, a.turno from a group by a.payee_id, a.dia, a.turno),
  -- por pessoa e dia: os meios-dias esperados (a soma das frequências, ao meio-dia inteiro), os usados (qualquer presença,
  -- como a grade do motor) e os livres (esperados e sem nada no plano)
  pes as (
    select k.dia, k.payee_id, k.pessoa, k.eh_dono,
           round(sum(k.meios_esperados))::int as esp,
           count(u.turno)::int as usados,
           array_remove(array_agg(case when k.situacao = 'livre' and k.meios_esperados > 0 and u.turno is null then k.turno end
                                  order by k.turno = 'tarde'), null) as livres,
           coalesce(sum(k.meios_esperados) filter (where k.situacao = 'livre' and u.turno is null), 0) as livre_esp
      from cap k
      left join usado u on u.payee_id = k.payee_id and u.dia = k.dia and u.turno = k.turno
     group by k.dia, k.payee_id, k.pessoa, k.eh_dono
  ),
  dia as (
    select d::date as dia, b.blocos from generate_series(v_seg, v_seg + 5, interval '1 day') d
      left join blocos b on b.dia = d::date
     where extract(isodow from d) between 1 and 5 or b.blocos is not null or cf.sabado_util
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'dia', dia.dia, 'rotulo', upper(public._dia_curto(dia.dia)), 'hoje', dia.dia = p_hoje,
           'feriado', public.agenda_feriado(dia.dia),
           'pessoas', coalesce((select jsonb_agg(jsonb_build_object(
                         'payee_id', x.payee_id, 'nome', x.pessoa, 'eh_dono', x.eh_dono,
                         'meios_usados', x.usados, 'meios_esperados', x.esp,
                         'pct', case when x.esp > 0 then round(100 * x.usados::numeric / x.esp)::int end,
                         'cor', case when x.esp = 0 then 'vermelho'
                                     when x.usados::numeric / x.esp <= cf.carga_max then 'verde'
                                     when x.usados <= x.esp then 'ambar'
                                     else 'vermelho' end,
                         'texto', format('%s %s/%s', x.pessoa, x.usados, x.esp))
                       order by x.eh_dono desc, x.pessoa, x.payee_id)
                  from pes x where x.dia = dia.dia and (x.esp > 0 or x.usados > 0)), '[]'::jsonb),
           'blocos', coalesce(dia.blocos, '[]'::jsonb),
           'livre_texto', (select 'livre: ' || string_agg(case when x.eh_dono then 'você' else x.pessoa end || ' '
                                    || case when cardinality(x.livres) = 2 then 'dia todo'
                                            when x.livres[1] = 'manha' then 'manhã' else 'tarde' end,
                                    ', ' order by x.eh_dono desc, x.pessoa, x.payee_id)
                             from pes x where x.dia = dia.dia and dia.dia >= p_hoje and cardinality(x.livres) > 0))
           order by dia.dia), '[]'::jsonb),
         (select round(100 * sum(x.usados)::numeric / nullif(sum(x.esp), 0))::int from pes x
           where public.agenda_dia_util(x.dia)),
         (select trim_scale(round(sum(x.livre_esp)) / 2) from pes x where x.dia >= p_hoje and public.agenda_dia_util(x.dia))
    into v_dias, v_comp, v_livre
    from dia;

  -- FASE 7g: (7g P7; §5.7, R9.5-19, R9.12-9 e 10) com modo_porque ligado e o plano publicado (não a sombra do motor, que não tem alocação vigente), cada bloco
  -- ganha quem (gestor | dono: da 1ª alocação vigente do bloco no dia — o compromisso antes da reserva, de turno, a manhã, o técnico antes de você — e da ação
  -- que a criou, _agenda_quem_marcou), quem_texto ("marcado pelo gestor" / "marcado por você"; na reserva, "reservado pelo gestor" / "reservado por você": a
  -- reserva não é marcação) e porque_texto (_agenda_porque_linha dessa alocação: a fonte da duração e as suposições, até c_linha letras). Bloco sem alocação
  -- vigente: as 3 nulas. Fora de ligado, as chaves ficam ausentes: a tela de antes, byte a byte. Uma falha aqui não derruba a tela (os blocos de antes).
  if cf.modo_porque = 'ligado' and not v_teste then
    declare
      c_linha   constant int := 120;   -- estrutural: o teto da linha do porquê no bloco (§5.7)
      v_7g_dono uuid := public._agenda_dono(null);
    begin
      select coalesce(jsonb_agg(d.v || jsonb_build_object('blocos', coalesce((
               select jsonb_agg(b.v || jsonb_build_object(
                        'quem', q.quem,
                        'quem_texto', case when q.quem is null then null
                                           when coalesce((b.v ->> 'reserva')::boolean, false)
                                             then case when q.quem = 'dono' then 'reservado por você' else 'reservado pelo gestor' end
                                           when q.quem = 'dono' then 'marcado por você' else 'marcado pelo gestor' end,
                        'porque_texto', case when q.id is not null
                                             then public._agenda_corta(public._agenda_porque_linha((b.v ->> 'os')::uuid, jsonb_build_array(q.id::text), p_hoje),
                                                                       c_linha) end)
                      order by b.o)
                 from jsonb_array_elements(d.v -> 'blocos') with ordinality b(v, o)
                 left join lateral (
                   select x.id, public._agenda_quem_marcou(ac.origem, x.origem) as quem
                     from public.agenda_alocacoes x
                     left join public.agenda_acoes ac on ac.id = x.acao_id
                    where x.service_order_id = (b.v ->> 'os')::uuid and x.dia = (d.v ->> 'dia')::date and x.estado in ('publicada', 'fixada')
                    order by x.tipo = 'reserva', x.presenca <> 'turno', x.turno = 'tarde', x.payee_id is not distinct from v_7g_dono, x.id
                    limit 1) q on true), '[]'::jsonb))
             order by d.o), '[]'::jsonb)
        into v_dias
        from jsonb_array_elements(v_dias) with ordinality d(v, o);
    exception when others then
      null;   -- a tela de antes: os blocos sem as 3 chaves
    end;
  end if;
  -- FASE 7g: fim
  v_sem := public.agenda_ppc(v_seg - 7, p_hoje);
  v_ppc := (v_sem ->> 'ppc')::numeric;
  v_den := (v_sem ->> 'cumpridos')::int + jsonb_array_length(coalesce(v_sem -> 'nao_cumpridos', '[]'::jsonb));
  if cf.modo_proposta = 'ligado' then
    v_lv := public.agenda_livre_de_verdade(p_hoje, p_agora);
  end if;
  v_titulo := case
    when v_teste and v_prop is null then 'Em teste: ainda não montei esta semana.'
    when v_teste then 'Em teste: eu montaria assim — ' || public._agenda_titulo_da_semana(v_seg) || '.'
    else public._agenda_titulo_da_semana(v_seg) end;

  select coalesce(jsonb_agg(jsonb_build_object(
           'pergunta_id', e ->> 'id', 'n', (e ->> 'n')::int, 'tipo', e ->> 'tipo',
           'texto', format('Decisão %s: %s', e ->> 'n',
                           case when e ->> 'tipo' = 'diaria' then public._agenda_texto_da_diaria((e ->> 'id')::uuid)
                                else e ->> 'texto' end))
           order by (e ->> 'n')::int), '[]'::jsonb)
    into v_dec
    from jsonb_array_elements(public.agenda_decisoes_abertas(p_agora)) e;

  return jsonb_build_object(
    'modo', cf.modo_proposta, 'em_teste', v_teste, 'de', v_seg, 'ate', v_seg + 5, 'titulo', v_titulo,
    'comprometido_pct', v_comp, 'livre_diarias', v_livre,
    'ppc_anterior', case when v_ppc is not null then round(100 * v_ppc)::int end,
    'resumo', concat_ws(' · ',
                case when v_comp is not null then format('comprometido %s%%', v_comp) end,
                case when v_livre is not null then 'livre ' || replace(trim_scale(v_livre)::text, '.', ',')
                                                   || case when v_livre = 1 then ' diária' else ' diárias' end end,
                -- revisão da Fase 3: sem o jargão "PPC" — "semana passada: 5 de 6 dias cumpridos" (sem dia conferido, nada)
                case when v_den > 0
                     then format('semana passada: %s de %s %s', (v_sem ->> 'cumpridos')::int,
                                 public._agenda_plural(v_den, 'dia', 'dias'),
                                 case when (v_sem ->> 'cumpridos')::int = 1 then 'cumprido' else 'cumpridos' end) end),
    'livre_de_verdade', case when v_lv ->> 'fonte' = 'simulacao' then v_lv ->> 'texto' end,
    'dias', v_dias,
    'mudancas', public._agenda_tela_mudancas(p_hoje, p_agora),
    'decisoes', v_dec,
    'como_responder', case when jsonb_array_length(v_dec) > 0
                           then 'Responda no WhatsApp: diga a decisão e a opção (por exemplo, "na decisão 1, a opção 2").' end);
end;
$function$;

comment on function public.agenda_tela_semana(date, date, timestamptz) is
  'Agenda de Produção (Fase 3, P7a): a tela Agenda › Semana da semana ISO de p_de (sem ele, a de p_hoje), seg a sex (o sábado só com plano ou sabado_util) — {modo, em_teste, de, ate, titulo ("Semana de 03 a 06/11 (seg 02 é Finados)"; em sombra "Em teste: eu montaria assim — …", com os blocos da última semana montada pela sombra), comprometido_pct, livre_diarias, ppc_anterior, resumo ("comprometido 54% · livre 5,5 diárias · semana passada: 5 de 6 dias cumpridos"; sem dia conferido na semana passada, sem essa parte), livre_de_verdade (a simulação, só em ligado), dias:[{dia, rotulo "TER 03/11", hoje, feriado, pessoas:[{payee_id, nome, eh_dono, meios_usados, meios_esperados, pct, cor (verde ≤ carga_max, ambar ≤ 100%, vermelho acima; esperado zero com uso = vermelho), texto "Roberto 2/2"}], blocos:[{os, numero, cliente, bem, local, hora, pessoas_texto, dia_n, dias_total, dia_texto "dia 1 de 3", confirmado_cliente, reserva, reserva_texto "Reserva, a confirmar", condicao, tipo, fixada, resultado, resultado_texto}], livre_texto "livre: Roberto tarde"}], mudancas (_agenda_tela_mudancas), decisoes:[{pergunta_id, n, tipo, texto}], como_responder}. Desligado: só o título. Administrador e financeiro (com login) ou service_role; senão 42501. FASE 7g (P7): com modo_porque ligado e o plano publicado, cada bloco ganha quem (gestor | dono, da 1ª alocação vigente do bloco no dia e da ação que a criou), quem_texto ("marcado pelo gestor", "marcado por você"; na reserva, "reservado pelo gestor", "reservado por você") e porque_texto (_agenda_porque_linha, até 120 letras); bloco sem alocação vigente, as 3 nulas. Fora de ligado (e na sombra do motor), as chaves ficam ausentes. FASE 7g (P5b): a reserva com a condição ok_do_dono diz reserva_texto "Reserva, esperando o seu ok".';

-- ── 4. As portas ────────────────────────────────────────────────────────────────────────────────────
-- As 11 recriadas: create or replace mantém a porta de antes. _agenda_espera_ok é chamada por _agenda_classe_da_os, que authenticated executa (as leituras do
-- painel, invoker): execute para authenticated e service_role, nunca anon nem public. As outras 3 só são chamadas por definer (agenda_explicar_rodar,
-- agenda_decidir, agenda_desfazer): só service_role.
revoke all on function public._agenda_espera_ok(uuid) from public, anon;
grant execute on function public._agenda_espera_ok(uuid) to authenticated, service_role;
revoke all on function public._agenda_explicar_ok(date, timestamptz), public._agenda_ok_decidir(uuid, smallint, uuid, text, text, date, timestamptz),
  public._agenda_desfazer_nivel(uuid, uuid, text, date, timestamptz) from public, anon, authenticated;
grant execute on function public._agenda_explicar_ok(date, timestamptz), public._agenda_ok_decidir(uuid, smallint, uuid, text, text, date, timestamptz),
  public._agenda_desfazer_nivel(uuid, uuid, text, date, timestamptz) to service_role;
