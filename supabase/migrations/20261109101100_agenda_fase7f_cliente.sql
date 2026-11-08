
-- Agenda de Produção, Fase 7, etapa 7f ("Falar só o que importa"), pacote P6: o cliente — a semana prevista (M12) e as camadas. A OS marcada pela estimativa,
-- sem dia firme dito, recebe a semana em que o serviço está previsto (o texto que o dono aprovou), sem dia exato; o dia exato vai num toque só, na véspera; dentro
-- da semana dita, a mudança de dia não vira mensagem ao cliente.
-- Spec: scratchpad agenda-pesquisa/spec-fase7f.md (§3.2, §5.6, §6.5, §8.3 agenda_fase7f_cliente.sql e o bloco R8, que vale sobre o corpo: R8.1, R8.3-1 e 2,
-- R8.5-20 a 25, R8.6, R8.7, R8.8, R8.12, R8.13, R8.14); nomes: fase7-registro.md; notas: notas-fase7f.md, seções P1 a P5.
-- Respostas do dono que valem aqui (respostas/<id> da página Respostas do Diário, conferidas em 08/11): ag7-cliente-data (AG7-16) "Concordo: semana prevista até
-- ficar seguro"; ag7-texto-semana (AG7-36) "Aprovo o texto" (o cartão mostrou 3 textos: o da compra feita, o da peça pendente e o "se mudar"; "duas semanas" não foi
-- mostrado e não existe aqui); ag7-texto-pronto-ate (AG7-32) "Não incluir a data de pronto"; ag7-ligar "Ligar direto quando estiver pronto" (publicar em teste pelo
-- OK permanente, cada *ligar* pelo OK nomeado). ag7-aviso-semana (AG7-22, "Mensagem própria às 17:00") é a mensagem da semana ao DONO (P4), não ao cliente: as
-- 17:00 do passo semana vêm de cliente_hora_preparo (R8.5-23).
-- Depende das Fases 1 a 6, do lote de 30/10, das etapas 7a a 7d, de 20261109100000 a 20261109100300, 20261109100600, do dado 20261109100900 e do P5
-- (20261109101000) da 7f (nasce depois deles: R8.2). NÃO depende da 7e.
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (2 novas; 13 recriadas; nenhum dado, nenhuma tabela, nenhuma coluna, nenhuma lista fechada: o tipo semana e o M12 já são do P1)
-- NÃO APLICADA. Existe para revisão e espera o OK. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7f/p6/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA
-- (conferida a cada montagem), e a mudança está só nos blocos "-- FASE 7f: … -- FASE 7f: fim" (em agenda_saude, que já está dentro de um bloco de antes, na marca
-- "-- (7f P6 … -- (7f: fim)"). Tirados os blocos, o corpo é o da origem, byte a byte (o montador e o C8 de supabase/tests/agenda_fase7f_cliente.sql conferem). As origens e o
-- md5 do corpo de antes (prosrc, sem CR; o mesmo de produção em 08/11, sql/wf7f_p6_md5_antes):
--   _agenda_cliente_texto         20261107100500_agenda_fase7d_cliente.sql:369  d13efa766813bc2918f29cbd952bb913
--   _agenda_cliente_registrar     20261031100850_agenda_fase7a_protecoes.sql:298  25f079a242fd0ea09c7c7c05a3e4032d
--   _agenda_cliente_confirmar     20261028100800_agenda_fase5_correcao_rodada.sql:1887  2c22abcfd45d4228f530af9cb49596ba
--   _agenda_cliente_material      20261028100800_agenda_fase5_correcao_rodada.sql:1727  c0c86a16dda8898990576673ae608655
--   agenda_cliente_vigiar         20261107100500_agenda_fase7d_cliente.sql:835  d1d6d168d499d01623dd85ec5fa58408
--   agenda_resposta_do_cliente    20261107100800_agenda_fase7d_correcao.sql:3276  c4d47a8984b547cd70f32ce9ec3a0d46
--   _agenda_cliente_revalidar     20261107100800_agenda_fase7d_correcao.sql:3147  45e68ee3cc90dfad1a937fc5385b262d
--   _agenda_cliente_tipo_texto    20261107100500_agenda_fase7d_cliente.sql:650  8fdaacc55198f5c32eb1d98be16519df
--   _agenda_cliente_o_que         20261107100500_agenda_fase7d_cliente.sql:678  98cdbf545cc7421f54b68e47a2e689eb
--   _agenda_cliente_a_mensagem    20261028100400_agenda_fase5_respostas.sql:110  9772a54e4ae414d92423b7b5aba5c12c
--   _agenda_ver_clientes          20261107100500_agenda_fase7d_cliente.sql:1399  0f131e9ec3dd5bc56376c0df7837b182
--   agenda_cliente_preparar       20261029100950_agenda_fase6_correcao_textos.sql:1325  9243ce1f1455a8b091bffe94182b2fe1
--   agenda_saude                  20261109100600_agenda_fase7f_leituras.sql:571  f2379b63d809d8e056d366776ae00535
--
-- POR QUE: com o gestor marcando pela estimativa, o dia do plano pode mudar até a compra estar feita. A Fase 5 diria ao cliente o dia exato em D−3 (cliente_confirmar_du)
-- e cada mudança viraria mensagem nova. O dono decidiu (AG7-16): o cliente ouve a semana prevista até ficar seguro, e o dia exato só na véspera. Hoje nada disto
-- chega a ninguém: modo_cliente_camadas fica desligado (esta migration não liga nada), e mesmo ligado o freio (gestor_so_propor) o faz teste (R8.6).
--
-- O QUE MUDA (só com modo_cliente_camadas fora de desligado; ele respeita o freio por _agenda_fala_modo('camadas'): com *gestor, só propor* o ligado vale teste e
-- nada novo vai à fila do cliente; em teste só se registra, com a chave ":sombra", como na Fase 5):
--   1. _agenda_cliente_camada (nova): a OS está em camada (a marcada pela estimativa, _agenda_os_por_estimativa, ou todas com cliente_camadas_para = todas)? A
--      semana do 1º dia do plano e a faixa dela pelo calendário (do 1º ao último dia útil da semana, sem sábado com sabado_util falso, sem feriado; o dia que o plano
--      marcou fora disso entra). A OS cujo plano cruza a semana não tem faixa (duas_semanas, R8.3-2).
--   2. _agenda_cliente_semana (nova): o passo semana da rodada do cliente, uma vez por dia, no 1º tique a partir de cliente_hora_preparo (R8.5-23; antes dele nada se
--      lê). Só a OS fora de awaiting_parts, awaiting_client e in_progress, sem dia firme dito (prometido_tipo is distinct from 'firme', R8.5-20), que ainda não
--      começou (o filtro de _agenda_cliente_confirmar, R8.5-21: a OS-00074, já na semana, não recebe), em camada, com o 1º dia a até cliente_semana_du dias úteis,
--      a mensagem saindo antes de a semana começar e antes da véspera. Sem data de pronto (AG7-32). A recusada pelo teto não vira silêncio (R8.5-22): a chave leva
--      o dia, e a semana tenta de novo no dia seguinte; a que o dono segurou ou deixou vencer, e a do cliente que não recebe, ficam.
--   3. _agenda_cliente_texto, _agenda_cliente_tipo_texto, _agenda_cliente_o_que, _agenda_cliente_a_mensagem (recriadas): o tipo semana (M12), o texto aprovado.
--   4. _agenda_cliente_registrar (recriada): a semana só fica ligada com as camadas ligadas pelo freio.
--   5. _agenda_cliente_revalidar (recriada, R8.5-24): a semana com regra própria — o 1º (ou o último) dia do plano saiu da faixa dita = desatualizada.
--   6. agenda_cliente_vigiar (recriada): o passo semana depois do onde_fica e antes do pós-serviço (R8.5-22); com as camadas desligadas ele nem é chamado.
--   7. _agenda_cliente_confirmar (recriada): com as camadas ligadas de verdade, a OS em camada tem o M1 a cliente_dia_exato_du dias de janela antes de D (1 = a
--      véspera: o toque único que a Fase 5 já tem). O material completo continua exigido.
--   8. _agenda_cliente_material (recriada): dentro da semana dita, o M3/M7 com dia não vai ao cliente (o M6 e o M10 já não vão: o risco mede contra o fim da semana
--      dita, e a semana não conta como dia ouvido). Fora dela, o de sempre.
--   9. agenda_resposta_do_cliente (recriada): o SIM à semana é ciência; o resto como as mensagens que não propõem dia (ao dono).
--  10. _agenda_ver_clientes, agenda_cliente_preparar, agenda_saude (recriadas): a semana onde a lista dos tipos é validação ou contagem — "Ainda em teste" (com
--      as camadas fora de desligado), o tipo que existe e é recusado com a saída no preparar, a lista dos liberados na saúde. NUNCA em cliente_tipos_ligados:
--      o ligar é do dono (R8.14).
--
-- O QUE NÃO MUDA: com modo_cliente_camadas desligado (como esta migration deixa) ou em teste, as 11 mensagens ao cliente de hoje saem como antes, byte a byte (a
-- fila, os textos, a hora, a revalidação, a resposta: o C11 e o replay da carteira real conferem); _agenda_cliente_ouviu e a substituição da véspera não contam a
-- semana (NOVO-agenda-77); _agenda_cliente_atraso e _agenda_cliente_mudanca_no_dia não são recriadas; _agenda_chave_telefone, agenda_dia_util, agenda_somar_du,
-- agenda_feriado, _agenda_cliente_dia e _agenda_nome_curto não mudam (pedidos-do-retorno.md, item 13). agenda_promessa_da_os não entra (R8.3-1).
--
-- ORDEM DE LIGAR (spec R8.14): depois de 20261109101000 (o P5). Aplicar sozinha não muda nada para ninguém (modo_cliente_camadas segue desligado). O dado que o põe
-- em teste, o pós-deploy e os md5 são do pacote seguinte.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7f_cliente.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261109101100
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261109101100_agenda_fase7f_cliente.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261109101100', 'agenda_fase7f_cliente');"
--
-- DESFAZER: com modo_cliente_camadas desligado nada disto roda. Para voltar o código: reaplicar as definições das origens acima, e
--   drop function if exists public._agenda_cliente_semana(date, timestamptz), public._agenda_cliente_camada(uuid, date);
--   (a rodada do cliente recriada pela origem não chama mais o passo semana). Mensagem que já saiu ao cliente não volta.
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.

-- ── 1. A camada da OS ───────────────────────────────────────────────────────────────────────────────
-- §5.6, R8.3-1 (sem agenda_promessa_da_os; a chave do plano é ultimo_dia, explícita no nulo, R8.12-2), R8.5-25 (o fim pelo calendário). A compra feita (os_prontidao,
-- o peso de R8.8) fica no passo, que a lê só para quem vai receber: a camada é barata, e o M1 a lê a cada tique.
create or replace function public._agenda_cliente_camada(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf    public.agenda_config := public._agenda_cfg();
  x     jsonb;
  v_d   date;
  v_fim date;
  v_seg date;
  v_de  date;
  v_ate date;
begin
  if p_os is null or p_hoje is null then
    raise exception '_agenda_cliente_camada: sem a OS ou sem o dia de hoje.' using errcode = '22004';
  end if;
  if public._agenda_fala_modo('camadas') = 'desligado' then
    return jsonb_build_object('camada', 'normal', 'motivo', 'desligado');
  end if;
  x := public._agenda_plano_da_os(p_os, p_hoje);
  v_d := (x ->> 'proximo_dia')::date;
  if v_d is null then
    return jsonb_build_object('camada', 'normal', 'motivo', 'sem_plano');
  end if;
  if not (cf.cliente_camadas_para = 'todas' or public._agenda_os_por_estimativa(p_os, p_hoje)) then
    return jsonb_build_object('camada', 'normal', 'motivo', 'nao_e_estimativa');
  end if;
  v_seg := date_trunc('week', v_d)::date;
  -- o fim é o último dia do plano; sem ele, nada a afirmar (o case explícito: nada de greatest/least engolindo o nulo)
  v_fim := case when (x ->> 'ultimo_dia') is null then null else (x ->> 'ultimo_dia')::date end;
  if v_fim is null then
    return jsonb_build_object('camada', 'semana', 'motivo', 'sem_fim', 'semana', v_seg, 'primeiro_dia', v_d);
  end if;
  if date_trunc('week', v_fim)::date <> v_seg then
    return jsonb_build_object('camada', 'semana', 'motivo', 'duas_semanas', 'semana', v_seg, 'primeiro_dia', v_d, 'ultimo_dia', v_fim);
  end if;
  -- a faixa pelo calendário: do 1º ao último dia útil da semana (segunda a sábado; agenda_dia_util tira o sábado com sabado_util falso e o feriado); o dia que o
  -- plano marcou fora dele (o sábado marcado) entra
  select min(g::date), max(g::date) into v_de, v_ate
    from generate_series(v_seg::timestamp, v_seg::timestamp + interval '5 days', interval '1 day') g
   where public.agenda_dia_util(g::date);
  v_de := case when v_de is null or v_d < v_de then v_d else v_de end;
  v_ate := case when v_ate is null or v_fim > v_ate then v_fim else v_ate end;
  return jsonb_build_object('camada', 'semana', 'motivo', null, 'semana', v_seg, 'faixa_de', v_de, 'faixa_ate', v_ate,
                            'n_dias', (x ->> 'dias')::int, 'primeiro_dia', v_d, 'ultimo_dia', v_fim);
end;
$function$;
comment on function public._agenda_cliente_camada(uuid, date) is
  'Agenda de Produção (Fase 7f, P6; §5.6, AG7-16, R8.3-1, R8.5-25): a OS está em camada? normal (motivo: desligado, sem_plano, nao_e_estimativa) ou semana — a marcada pela estimativa (_agenda_os_por_estimativa), ou todas com cliente_camadas_para = todas, com as camadas fora de desligado (_agenda_fala_modo). {camada, motivo (sem_fim, duas_semanas ou nulo), semana (a segunda), faixa_de e faixa_ate (do 1º ao último dia útil da semana pelo calendário; o dia marcado fora dele entra), n_dias, primeiro_dia, ultimo_dia}. Sem a compra feita (o passo lê os_prontidao). STABLE, invoker, sem grant.';

-- ── 2. O passo semana da rodada do cliente ──────────────────────────────────────────────────────────
-- §5.6, R8.5-20 a 23 e 25, R8.6, R8.8. Molde: _agenda_cliente_onde_fica (o M11 da 7d): o teto conferido antes (quem cede é a semana), a ação em teste nasce contada
-- (fica no foco, não ocupa linha do fechamento), o erro de uma OS vai ao log e o passo segue.
create or replace function public._agenda_cliente_semana(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_fala   text;
  v_modo   text;
  r        record;
  x        jsonb;
  c        jsonb;
  v_d      date;
  v_seg    date;
  v_alvo   timestamptz;
  v_envio  date;
  v_compra boolean;
  v_motivo text;
  v_r      jsonb;
  v_pul    jsonb := '{}'::jsonb;
  n_reg    int := 0;
  n_erro   int := 0;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora do passo semana.' using errcode = '22023';
  end if;
  -- desligado: nada (a rodada nem chama este passo); com o freio, ligado vale teste (R8.6)
  v_fala := public._agenda_fala_modo('camadas');
  if v_fala = 'desligado' then
    return jsonb_build_object('pulado', 'desligado');
  end if;
  -- R8.5-23: uma vez por dia, no 1º tique a partir de cliente_hora_preparo; antes dele nada se lê
  if (p_agora at time zone 'America/Sao_Paulo')::time < cf.cliente_hora_preparo then
    return jsonb_build_object('pulado', 'cedo');
  end if;
  if exists (select 1 from public.agenda_vigia_rodadas q
              where q.rotina = 'cliente' and q.p_hoje = p_hoje and q.contagens -> 'semana' ? 'registradas') then
    return jsonb_build_object('pulado', 'ja_rodou');
  end if;
  -- o modo que o registro dará à linha (a regra de _agenda_cliente_registrar): ligado só com o cliente ligado, a semana na lista e as camadas ligadas pelo freio
  v_modo := case when cf.modo_cliente = 'ligado' and 'semana' = any (cf.cliente_tipos_ligados) and v_fala = 'ligado' then 'ligado' else 'sombra' end;
  v_alvo := public._agenda_cliente_toque(public._agenda_cliente_dia_seguinte(p_hoje));
  -- R8.5-21: o filtro de _agenda_cliente_confirmar (fora de awaiting_parts, awaiting_client e in_progress), e sem o orçamento (draft: a revalidação o recusaria
  -- na hora de sair, depois de perguntar ao dono à toa); R8.5-20: sem dia firme dito, com a OS sem linha em os_planejamento (o caso comum) dentro
  for r in
    select k.service_order_id as os, so.client_id, p.prometido_tipo
      from public.os_carteira(p_hoje) k
      join public.service_orders so on so.id = k.service_order_id
      left join public.os_planejamento p on p.service_order_id = k.service_order_id
     where k.status not in ('awaiting_parts', 'awaiting_client', 'in_progress', 'draft')
       and p.prometido_tipo is distinct from 'firme'
     order by k.numero collate "C", k.service_order_id
  loop
    begin
      v_motivo := null;
      x := public._agenda_plano_da_os(r.os, p_hoje);
      v_d := (x ->> 'proximo_dia')::date;
      v_motivo := case
        -- R8.5-21: o próximo dia depois de hoje, e o serviço ainda não começou
        when v_d is null or v_d <= p_hoje then 'sem_dia'
        when coalesce((x ->> 'inicio')::date, v_d) < v_d then 'comecou'
        -- a faixa já dita (pela semana ou outro caminho): dentro dela nada muda; fora, o caminho de hoje (o M6), não outra semana
        when r.prometido_tipo is not null then 'ja_ouviu'
        when public.agenda_du_entre(p_hoje, v_d) > cf.cliente_semana_du then 'longe'
      end;
      if v_motivo is null then
        c := public._agenda_cliente_camada(r.os, p_hoje);
        -- R8.3-2: a OS cujo plano cruza a semana não recebe a semana (o texto de duas semanas não teve o OK): só a véspera
        v_motivo := case when c ->> 'camada' is distinct from 'semana' then 'fora_da_camada' else c ->> 'motivo' end;
      end if;
      if v_motivo is null then
        v_seg := (c ->> 'semana')::date;
        -- a semana sai antes de ela começar (a OS já na semana não a recebe) e antes da véspera (o toque do dia exato)
        v_envio := (public._agenda_cliente_quando(hashtext(r.os::text), v_alvo, p_agora) at time zone 'America/Sao_Paulo')::date;
        if v_envio >= v_seg or v_envio >= public._agenda_cliente_vespera(v_d) then
          v_motivo := 'em_cima';
        end if;
      end if;
      -- uma semana por OS e semana, neste modo. A recusada pelo teto, pela hora ou pela leitura de agora não conta (R8.5-22: tenta de novo, a chave leva o
      -- dia); a que o dono segurou ou deixou vencer, e a do cliente que não recebe (opt-out, sem telefone, sem conversa) ou da OS fora de hora, contam
      if v_motivo is null
         and exists (select 1 from public.agenda_cliente_mensagens m
                      where m.service_order_id = r.os and m.tipo = 'semana' and m.modo = v_modo
                        and date_trunc('week', m.faixa_de)::date = v_seg
                        and not (m.estado = 'recusada' and m.aprovacao in ('livre', 'aprovada')
                                 and coalesce(m.recusa_motivo, '') not in ('opt_out', 'sem_telefone', 'sem_conversa', 'status'))) then
        v_motivo := 'ja_tem';
      end if;
      -- o teto (molde do M11): o cliente já tem mensagem no dia da semana, a semana ISO cheia, ou a semana de outra OS dele em 24 h: a semana cede e tenta amanhã
      if v_motivo is null
         and ((select count(*) from public.agenda_cliente_mensagens m
                where m.client_id = r.client_id and m.modo = 'ligado'
                  and m.estado in ('registrada', 'aguardando_dono', 'enfileirada', 'enviada', 'respondida', 'sem_resposta')
                  and (m.enviar_em at time zone 'America/Sao_Paulo')::date = v_envio) >= cf.cliente_dia_max
              or public._agenda_cliente_no_periodo(r.client_id, date_trunc('week', v_envio)::date, date_trunc('week', v_envio)::date + 6, null)
                 >= cf.cliente_semana_max
              or exists (select 1 from public.agenda_cliente_mensagens m
                          where m.client_id = r.client_id and m.tipo = 'semana' and m.enviada_em is not null
                            and m.enviada_em > p_agora - make_interval(hours => cf.cliente_mesmo_tipo_horas))) then
        v_motivo := 'cliente_ja_tem_mensagem';
      end if;
      if v_motivo is null then
        -- a compra feita (a prontidão completa da Fase 5): a faixa ("segunda 16/11 a quinta 19/11"); sem ela, a condição ("se as peças chegarem a tempo")
        v_compra := coalesce(public.os_prontidao(r.os, p_hoje) #>> '{material,estado}' = 'completo', false);
        v_r := public._agenda_cliente_registrar('semana', case when v_compra then 'compra_feita' else 'compra_pendente' end, r.os,
                 (c ->> 'faixa_de')::date,
                 jsonb_build_object('dia', c -> 'faixa_de', 'faixa_de', c -> 'faixa_de', 'faixa_ate', c -> 'faixa_ate', 'n', c -> 'n_dias',
                                    'chave', (c ->> 'faixa_de') || ':' || p_hoje::text,
                                    'prometido_tipo', case when v_compra then 'faixa' else 'condicional' end),
                 v_alvo, null, 'rodada', null, p_agora);
        if coalesce((v_r ->> 'criada')::boolean, false) then
          n_reg := n_reg + 1;
          -- (molde do M11, correção R5) em teste a ação nasce contada: fica no foco, e não ocupa linha do fechamento
          if v_r ->> 'modo' = 'sombra' then
            update public.agenda_acoes a set contada_em = p_agora
             where a.id = (select m.acao_id from public.agenda_cliente_mensagens m where m.id = (v_r ->> 'id')::uuid);
          end if;
        else
          v_motivo := coalesce(v_r ->> 'motivo', v_r ->> 'modo', 'nao_criada');
        end if;
      end if;
      if v_motivo is not null then
        v_pul := v_pul || jsonb_build_object(v_motivo, coalesce((v_pul ->> v_motivo)::int, 0) + 1);
      end if;
    exception when others then
      perform public._agenda_cliente_erro_da_os('semana', r.os, sqlstate, sqlerrm, p_hoje);
      n_erro := n_erro + 1;
    end;
  end loop;
  return jsonb_build_object('registradas', n_reg, 'modo', v_modo, 'puladas', v_pul, 'erros_os', n_erro);
end;
$function$;
comment on function public._agenda_cliente_semana(date, timestamptz) is
  'Agenda de Produção (Fase 7f, P6; §5.6, AG7-16, AG7-36, AG7-32, R8.5-20 a 23 e 25): o passo semana da rodada do cliente (depois do onde_fica, antes do pós-serviço). Com as camadas desligadas, {pulado: desligado}; antes de cliente_hora_preparo, {pulado: cedo} sem ler nada; uma vez por dia ({pulado: ja_rodou}). Para a OS fora de awaiting_parts, awaiting_client e in_progress, sem dia firme dito (prometido_tipo is distinct from firme) nem faixa já dita, que não começou, com o 1º dia a até cliente_semana_du dias úteis, em camada (_agenda_cliente_camada; duas_semanas não sai), saindo antes da semana e da véspera, sem a semana desta semana no mesmo modo e sem o teto do cliente: a mensagem semana (compra_feita = faixa, compra_pendente = condicional; a chave leva a faixa e o dia). O modo é o do registro (ligado só com as camadas ligadas pelo freio e a semana na lista); em teste a ação nasce contada. {registradas, modo, puladas {motivo: n}, erros_os}. Volatile, invoker, sem grant.';

-- ── 3. Os textos ────────────────────────────────────────────────────────────────────────────────────
create or replace function public._agenda_cliente_texto(p_tipo text, p_variante text, p_os uuid, p_dados jsonb,
                                                        p_hoje date default public._hoje_brt())
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  x        jsonb := public._agenda_cliente_contexto(p_os, p_hoje);
  d        jsonb := coalesce(p_dados, '{}'::jsonb);
  v_var    text := nullif(btrim(coalesce(p_variante, '')), '');
  v_nome   text := x ->> 'nome';
  v_prim   boolean := coalesce((d ->> 'primeira')::boolean, (x ->> 'primeira')::boolean, false);
  v_envio  date := coalesce((d ->> 'envio')::date, p_hoje);
  v_dia    date := coalesce((d ->> 'dia')::date, (x ->> 'dia')::date);
  v_fim    date := coalesce((d ->> 'fim')::date, (x ->> 'fim')::date);
  v_n      int := coalesce((d ->> 'n')::int, (x ->> 'n_dias')::int);
  v_serv   text := x ->> 'servico';
  v_art    text := x ->> 'servico_artigo';
  v_esta   text;
  v_jan    text;
  v_dito_de  date;
  v_dito_ate date;
  v_assin  text;
  v_abre   text;
  v_resto  text;
  v_falta  text;
begin
  if p_tipo is null or p_tipo not in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar',
                                      -- FASE 7d: (7d P6, §5.6) o M11
                                      'onde_fica',
                                      -- FASE 7d: fim
                                      -- FASE 7f: (7f P6, §5.6, R2: o M12) a semana prevista
                                      'semana',
                                      -- FASE 7f: fim
                                      'nova_data', 'pronto', 'pronto_lembrete', 'pos_servico', 'mudanca_no_dia') then
    raise exception using errcode = '22023', message = format('Tipo de mensagem ao cliente desconhecido: %s.', p_tipo);
  end if;
  if p_tipo = 'confirmar' then
    v_var := coalesce(v_var, case when v_prim then 'primeira' else 'seguinte' end);
  end if;
  -- CORREÇÃO FASE 5: os dados novos da correção C2 — a saudação (item 12: "Bom dia" ou "Boa tarde", da hora do envio) e a
  -- forma "fim" do aviso remarcado (item 6) — só valem onde existem
  if d ? 'saudacao' and coalesce(d ->> 'saudacao', '') not in ('Bom dia', 'Boa tarde') then
    raise exception using errcode = '22023', message = format('Saudação %s não existe na mensagem ao cliente.', d ->> 'saudacao');
  end if;
  if d ? 'forma' and (p_tipo <> 'pode_atrasar' or v_var is distinct from 'remarcado' or coalesce(d ->> 'forma', '') <> 'fim') then
    raise exception using errcode = '22023',
      message = format('A forma %s não existe na mensagem %s.', coalesce(d ->> 'forma', '(nenhuma)'), p_tipo);
  end if;
  -- (item 8) o aviso de atraso com peça crítica ainda sem data de chegada (variante peca_sem_data, d09): nenhuma data — nem
  -- a da peça, nem a nova do serviço —, só o que o cliente ouviu ("que estava para quinta (05/11)")
  if p_tipo = 'pode_atrasar' and v_var = 'peca_sem_data' then
    if v_nome is null then
      raise exception using errcode = '22023', message = 'Falta o nome do cliente para a mensagem pode_atrasar ao cliente.';
    end if;
    if d ? 'dito_de' or d ? 'dito_ate' then
      v_dito_de := (d ->> 'dito_de')::date; v_dito_ate := (d ->> 'dito_ate')::date;
    elsif d ? 'dia_dito' then
      v_dito_de := (d ->> 'dia_dito')::date; v_dito_ate := v_dito_de;
    else
      v_dito_de := (x #>> '{prometido,de}')::date; v_dito_ate := (x #>> '{prometido,ate}')::date;
    end if;
    if coalesce(v_dito_de, v_dito_ate) is null then
      raise exception using errcode = '22023', message = 'Falta o dia dito ao cliente para a mensagem pode_atrasar ao cliente.';
    end if;
    v_resto := format('quero te avisar com antecedência: ainda faltam peças %s sem data de chegada, então %s, que estava %s, vai atrasar. Te digo a nova data assim que elas chegarem. Se isso atrapalhar algum plano seu, me diga.',
                      x ->> 'do_servico', v_serv, public._agenda_cliente_faixa(v_dito_de, v_dito_ate, true));
    -- FASE 6: (P7) sem a repetição (spec-fase6 §6.1): o serviço já vem logo depois ("ainda faltam peças sem data de chegada,
    -- então o serviço no seu veleiro, …"). Texto novo ao cliente: vai à lista do dono para aprovar antes de ligar
    v_resto := format('quero te avisar com antecedência: ainda faltam peças sem data de chegada, então %s, que estava %s, vai atrasar. Te digo a nova data assim que elas chegarem. Se isso atrapalhar algum plano seu, me diga.',
                      v_serv, public._agenda_cliente_faixa(v_dito_de, v_dito_ate, true));
    -- FASE 6: fim
    if v_prim then
      return format('Olá, %s! %s %s', v_nome,
                    case when x ->> 'dono' is not null then format('Aqui é o %s, da %s.', x ->> 'dono', x ->> 'empresa')
                         else format('Aqui é da %s.', x ->> 'empresa') end,
                    upper(left(v_resto, 1)) || substr(v_resto, 2));
    end if;
    return v_nome || ', ' || v_resto;
  end if;
  -- CORREÇÃO FASE 5: fim
  if (p_tipo = 'confirmar' and v_var not in ('primeira', 'seguinte', 'unico'))
     or (p_tipo = 'pode_atrasar' and coalesce(v_var, '') not in ('peca', 'execucao', 'remarcado'))
     or (p_tipo = 'andamento' and coalesce(v_var, '') not in ('primeiro_dia', 'semanal'))
     or (p_tipo = 'mudanca_no_dia' and coalesce(v_var, '') not in ('clima', 'equipe', 'geral'))
     -- FASE 7d: (7d P6, §5.6) as 2 variantes do M11
     or (p_tipo = 'onde_fica' and coalesce(v_var, '') not in ('barco', 'motorhome'))
     -- FASE 7d: fim
     -- FASE 7f: (7f P6, §6.5) as 2 variantes do M12. "Duas semanas" não existe (R8.3-2: o texto não teve o OK do dono) e "mudou" também não: fora da semana dita
     -- vale o caminho de hoje (o pedido do fio, 08/11)
     or (p_tipo = 'semana' and coalesce(v_var, '') not in ('compra_feita', 'compra_pendente'))
     -- FASE 7f: fim
     or (p_tipo in ('vespera', 'acesso', 'material_chegou', 'nova_data', 'pronto', 'pronto_lembrete', 'pos_servico')
         and v_var is not null) then
    raise exception using errcode = '22023', message = format('Variante %s não existe na mensagem %s.', coalesce(v_var, '(nenhuma)'), p_tipo);
  end if;

  v_jan := case d ->> 'janela' when 'manha' then 'pela manhã' when 'tarde' then 'à tarde' when 'dia' then 'o dia todo'
           else public._agenda_cliente_janela(p_os, v_dia) end;
  v_esta := case when v_art in ('os', 'as') then 'estão' else 'está' end;
  if d ? 'dito_de' or d ? 'dito_ate' then
    v_dito_de := (d ->> 'dito_de')::date; v_dito_ate := (d ->> 'dito_ate')::date;
  elsif d ? 'dia_dito' then
    v_dito_de := (d ->> 'dia_dito')::date; v_dito_ate := v_dito_de;
  else
    v_dito_de := (x #>> '{prometido,de}')::date; v_dito_ate := (x #>> '{prometido,ate}')::date;
  end if;

  -- O que cada modelo precisa (o 1º que faltar).
  v_falta := case
    when v_nome is null then 'o nome do cliente'
    when p_tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')
         or (p_tipo = 'pode_atrasar' and v_var = 'remarcado') then
      case when v_dia is null then 'o dia' when v_jan is null then 'a parte do dia (as alocações do dia)'
           when p_tipo = 'confirmar' and v_var <> 'unico' and coalesce(v_n, 0) < 1 then 'os dias de trabalho'
           when p_tipo = 'mudanca_no_dia' and coalesce(d ->> 'quando', '') not in ('hoje', 'amanhã') then 'o quando (hoje ou amanhã)'
           when p_tipo = 'pode_atrasar' and coalesce(v_dito_de, v_dito_ate) is null then 'o dia dito ao cliente' end
    when p_tipo = 'pode_atrasar' and v_var = 'peca' then
      case when coalesce((d ->> 'peca_de')::date, (d ->> 'peca_ate')::date) is null then 'a previsão da peça'
           when coalesce((d ->> 'faixa_de')::date, (d ->> 'faixa_ate')::date) is null then 'a faixa nova'
           when coalesce(v_dito_de, v_dito_ate) is null then 'o dia dito ao cliente' end
    when p_tipo = 'pode_atrasar' and v_var = 'execucao' then
      case when coalesce((d ->> 'faixa_de')::date, (d ->> 'faixa_ate')::date) is null then 'a faixa nova' end
    when p_tipo = 'andamento' then
      case when v_fim is null then 'o fim previsto'
           when v_var = 'semanal' and ((d ->> 'n_feitos') is null or coalesce(v_n, 0) < 1) then 'os dias feitos e o total'
           when v_var = 'primeiro_dia' and coalesce(d ->> 'quando', 'hoje') not in ('hoje', 'ontem') then 'o quando (hoje ou ontem)' end
  end;
  if v_falta is not null then
    raise exception using errcode = '22023', message = format('Falta %s para a mensagem %s ao cliente.', v_falta, p_tipo);
  end if;

  v_assin := case when x ->> 'dono' is not null then format('Aqui é o %s, da %s.', x ->> 'dono', x ->> 'empresa')
                  else format('Aqui é da %s.', x ->> 'empresa') end;

  -- O corpo e como ele abre: 'nome' ("{nome}, …"), 'bom_dia' ("Bom dia, {nome}! …"), 'bom_dia_ponto' ("Bom dia, {nome}.
  -- …"), 'boa_noticia' ("Boa notícia, {nome}: …") ou 'pronto' (o M1 primeira e seguinte, inteiros).
  case p_tipo
    when 'confirmar' then
      if v_var = 'primeira' then
        v_abre := 'pronto';
        v_resto := format('Olá, %s! %s Conseguimos encaixar %s para %s, %s, com previsão de %s de trabalho. Pode ser? Responda SIM para confirmar, ou me diga um dia melhor. A partir de agora te mando por aqui as novidades do serviço.',
                          v_nome, v_assin, v_serv, public._agenda_cliente_dia(v_dia), v_jan,
                          v_n || case when v_n = 1 then ' dia' else ' dias' end);
      elsif v_var = 'seguinte' then
        v_abre := 'pronto';
        v_resto := format('%s, conseguimos encaixar %s para %s, %s, com previsão de %s. Pode ser? Responda SIM ou me diga um dia melhor.',
                          v_nome, v_serv, public._agenda_cliente_dia(v_dia), v_jan,
                          v_n || case when v_n = 1 then ' dia' else ' dias' end);
      else
        v_abre := 'nome';
        v_resto := format('%s fica para %s, %s%s. Pode ser? Responda SIM, ou me diga se algo mudou.',
                          v_serv, public._agenda_cliente_dia(v_dia), v_jan, x ->> 'local');
      end if;
    when 'vespera' then
      v_abre := 'bom_dia';
      v_resto := format('%s chegamos %s para %s%s. Está tudo certo para recebermos? Responda SIM, ou me avise se algo mudou.',
                        public._agenda_cliente_dia_relativo(v_dia, v_envio), v_jan, v_serv, x ->> 'local');
    when 'acesso' then
      v_abre := 'bom_dia';
      v_resto := format('%s chegamos %s para %s. Para não perdermos a viagem: onde %s vai estar, e a chave fica com quem? Pode responder por aqui mesmo, até por áudio.',
                        public._agenda_cliente_dia_relativo(v_dia, v_envio), v_jan, v_serv, x ->> 'o_bem');
    when 'material_chegou' then
      v_abre := 'boa_noticia';
      v_resto := format('o material %s chegou e já foi conferido. Podemos começar %s, %s? Responda SIM, ou me diga um dia melhor.',
                        x ->> 'do_servico', public._agenda_cliente_dia(v_dia), v_jan);
    when 'pode_atrasar' then
      v_abre := 'nome';
      if v_var = 'peca' then
        v_resto := format('quero te avisar com antecedência: a peça %s ainda não chegou e agora está prevista %s. Por isso, %s, que estava %s, deve ficar %s. Te confirmo a data assim que a peça chegar. Se isso atrapalhar algum plano seu, me diga.',
                          x ->> 'do_servico',
                          public._agenda_cliente_faixa((d ->> 'peca_de')::date, (d ->> 'peca_ate')::date, true),
                          v_serv, public._agenda_cliente_faixa(v_dito_de, v_dito_ate, true),
                          public._agenda_cliente_faixa((d ->> 'faixa_de')::date, (d ->> 'faixa_ate')::date, true));
      elsif v_var = 'execucao' then
        v_resto := format('%s %s levando mais tempo do que eu estimei. A nova previsão para terminar é %s. Qualquer dúvida, me chama.',
                          v_serv, v_esta, public._agenda_cliente_faixa((d ->> 'faixa_de')::date, (d ->> 'faixa_ate')::date));
      else
        v_resto := format('%s, que estava %s, precisou passar para %s, %s. Desculpe pela mudança. Pode ser? Responda SIM ou me diga outro dia.',
                          v_serv, public._agenda_cliente_faixa(v_dito_de, v_dito_ate, true), public._agenda_cliente_dia(v_dia), v_jan);
        -- CORREÇÃO FASE 5: (item 6) o remarcado em que o início é o mesmo que o cliente ouviu e só o FIM mudou (a forma fim):
        -- dizer que "precisou passar para" o mesmo dia de início confunde
        if d ->> 'forma' = 'fim' then
          if v_fim is null then
            raise exception using errcode = '22023', message = 'Falta o fim novo para a mensagem pode_atrasar ao cliente.';
          end if;
          v_resto := format('%s vai precisar de mais um dia: agora fica de %s até %s. Desculpe pela mudança. Pode ser? Responda SIM ou me diga outro dia.',
                            v_serv, public._agenda_cliente_dia(v_dia), public._agenda_cliente_dia(v_fim));
          -- FASE 6: (P7) o número certo de dias (spec-fase6 §6.1): n = os dias úteis entre o último dia que o cliente ouviu e o
          -- fim novo (agenda_du_entre); "um dia depois do previsto" com n = 1, "{n} dias depois do previsto" com n ≥ 2. O fim
          -- que não passa do dia dito não vira texto (como todo dado que falta). Texto novo ao cliente: vai à lista do dono
          declare
            v_du int := public.agenda_du_entre(coalesce(v_dito_ate, v_dito_de), v_fim);
          begin
            if coalesce(v_du, 0) < 1 then
              raise exception using errcode = '22023',
                message = 'Falta o fim novo depois do dia dito para a mensagem pode_atrasar ao cliente.';
            end if;
            v_resto := format('%s vai terminar %s depois do previsto: agora fica de %s até %s. Desculpe pela mudança. Pode ser? Responda SIM ou me diga outro dia.',
                              v_serv, case when v_du = 1 then 'um dia' else v_du || ' dias' end,
                              public._agenda_cliente_dia(v_dia), public._agenda_cliente_dia(v_fim));
          end;
          -- FASE 6: fim
        end if;
        -- CORREÇÃO FASE 5: fim
      end if;
    when 'nova_data' then
      v_abre := 'nome';
      v_resto := format('agora com data firme: %s fica para %s, %s. Desculpe pela mudança e obrigado pela paciência. Responda SIM para confirmar, ou me diga se precisa de outro dia.',
                        v_serv, public._agenda_cliente_dia(v_dia), v_jan);
    when 'andamento' then
      v_abre := 'nome';
      if v_var = 'primeiro_dia' then
        v_resto := format('começamos %s %s. Seguimos com a previsão de terminar %s.',
                          coalesce(d ->> 'quando', 'hoje'), v_serv, public._agenda_cliente_dia(v_fim));
      else
        v_resto := format('seguimos com %s: %s de %s dias feitos, previsão de terminar %s.',
                          v_serv, (d ->> 'n_feitos')::int, v_n, public._agenda_cliente_dia(v_fim));
      end if;
    -- FASE 7d: (7d P6, §6.1, AG7-21) o M11, o texto aprovado, literal. O dia não é exigido e nada aqui é promessa de data. {uso} e {prazo} são as partes
    -- opcionais: quem registra tira o que não couber no teto (R6.9-5)
    when 'onde_fica' then
      v_abre := 'nome';
      declare
        v_ele  text := case when coalesce((x ->> 'bem_feminino')::boolean, false) then 'ela' else 'ele' end;
        v_uso  boolean := coalesce((d ->> 'uso')::boolean, false);
      begin
        if v_var = 'barco' then
          v_resto := format('para eu deixar %s encaminhado: %s está em qual marina, e fica na água ou em seco? Quando precisa descer ou subir, quem faz: você, o marinheiro ou a marina?%s%s Pode responder por aqui mesmo, até por áudio.',
                            v_serv, x ->> 'o_bem',
                            case when v_uso then format(' Se for usar %s nas próximas semanas, me diga os dias, que eu marco o serviço fora deles.', x ->> 'o_bem') else '' end,
                            case when coalesce((d ->> 'prazo')::boolean, false) then ' Precisa do serviço pronto até alguma data?' else '' end);
        else
          v_resto := format('para eu deixar %s encaminhado: %s vem para o nosso pátio, ou o serviço é onde %s está? Em que dia %s pode vir?%s Pode responder por aqui mesmo, até por áudio.',
                            v_serv, x ->> 'o_bem', v_ele, v_ele,
                            case when v_uso then format(' Se for viajar com %s nas próximas semanas, me diga quando, que eu marco o serviço fora desses dias.', v_ele) else '' end);
        end if;
      end;
    -- FASE 7d: fim
    -- FASE 7f: (7f P6, §6.5; AG7-36 "Aprovo o texto": o texto mostrado ao dono, literal; AG7-32 "Não incluir a data de pronto"; R8.3-2 sem "duas semanas";
    -- R8.5-25 o fim da faixa pelo calendário, sem sábado com sabado_util falso e sem feriado: quem os calcula é _agenda_cliente_camada, que grava faixa_de e
    -- faixa_ate) a semana prevista (M12). Com a compra feita, a faixa da semana ("(segunda 16/11 a quinta 19/11)"); sem ela, a condição ("se as peças chegarem a
    -- tempo"), como o cartão mostrou. "semana de dd/mm" é a segunda da semana. Com 1 dia de trabalho, "com 1 dia" (o cartão só mostrou "uns 3 dias"). Sem valor,
    -- sem número de OS, sem data de pronto, sem dia exato
    when 'semana' then
      v_abre := 'nome';
      declare
        v_7f_de   date := (d ->> 'faixa_de')::date;
        v_7f_ate  date := (d ->> 'faixa_ate')::date;
        v_7f_nome text[] := array['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];
        v_7f_prev text := case v_art when 'a' then 'prevista' when 'os' then 'previstos' when 'as' then 'previstas' else 'previsto' end;
        v_7f_uns  text;
      begin
        if v_7f_de is null or v_7f_ate is null or v_7f_ate < v_7f_de or date_trunc('week', v_7f_de) <> date_trunc('week', v_7f_ate) then
          raise exception using errcode = '22023', message = 'Falta a semana (o primeiro e o último dia, na mesma semana) para a mensagem semana ao cliente.';
        end if;
        if coalesce(v_n, 0) < 1 then
          raise exception using errcode = '22023', message = 'Falta os dias de trabalho para a mensagem semana ao cliente.';
        end if;
        v_7f_uns := case when v_n = 1 then '1 dia' else 'uns ' || v_n || ' dias' end;
        if v_var = 'compra_feita' then
          v_resto := format('%s %s %s para a semana de %s (%s), com %s de trabalho. O dia certo eu confirmo na véspera. Se algum dia dessa semana não der, me diga.',
                            v_serv, v_esta, v_7f_prev, to_char(date_trunc('week', v_7f_de), 'DD/MM'),
                            v_7f_nome[extract(isodow from v_7f_de)::int] || ' ' || to_char(v_7f_de, 'DD/MM')
                            || case when v_7f_ate > v_7f_de then ' a ' || v_7f_nome[extract(isodow from v_7f_ate)::int] || ' ' || to_char(v_7f_ate, 'DD/MM') else '' end,
                            v_7f_uns);
        else
          v_resto := format('%s %s %s para a semana de %s, se as peças chegarem a tempo, com %s de trabalho. O dia certo eu confirmo na véspera. Se algum dia dessa semana não der, me diga.',
                            v_serv, v_esta, v_7f_prev, to_char(date_trunc('week', v_7f_de), 'DD/MM'), v_7f_uns);
        end if;
      end;
    -- FASE 7f: fim
    when 'pronto' then
      v_abre := 'nome';
      v_resto := format('%s %s %s. Quando fica bom para combinarmos a entrega?', v_serv, v_esta,
                        case v_art when 'a' then 'concluída' when 'os' then 'concluídos' when 'as' then 'concluídas' else 'concluído' end);
    when 'pronto_lembrete' then
      v_abre := 'nome';
      v_resto := format('só para combinarmos a entrega %s: qual dia fica bom pra você?', x ->> 'do_bem');
    when 'pos_servico' then
      v_abre := 'nome';
      v_resto := format('tudo certo com %s? Já deu para usar? Se algo não estiver como esperado, me responde aqui que a gente resolve. Se preferir não receber estas mensagens, é só responder PARAR.',
                        v_serv);
    else -- mudanca_no_dia
      if v_var = 'clima' then
        v_abre := 'bom_dia_ponto';
        v_resto := format('Com a chuva de %s não dá para trabalhar %s com segurança. Podemos passar para %s, %s? Responda SIM ou me diga outro dia.',
                          d ->> 'quando', x ->> 'no_bem', public._agenda_cliente_dia(v_dia), v_jan);
      else
        v_abre := 'nome';
        v_resto := format('tive um imprevisto%s e não vamos conseguir ir %s. Desculpe o transtorno. Podemos ir %s, %s? Responda SIM ou me diga outro dia.',
                          case when v_var = 'equipe' then ' com a equipe' else '' end, d ->> 'quando',
                          public._agenda_cliente_dia(v_dia), v_jan);
      end if;
  end case;

  -- CORREÇÃO FASE 5: (item 12) a saudação pela hora em que a mensagem SAI (o registrar grava p_dados.saudacao: "Bom dia"
  -- antes do meio-dia, "Boa tarde" depois); sem ela, "Bom dia" (como as registradas antes desta correção)
  if v_abre in ('bom_dia', 'bom_dia_ponto') then
    return format('%s, %s%s %s', coalesce(nullif(d ->> 'saudacao', ''), 'Bom dia'), v_nome,
                  case when v_abre = 'bom_dia' then '!' else '.' end,
                  case when v_prim then v_assin || ' ' else '' end || v_resto);
  end if;
  -- CORREÇÃO FASE 5: fim
  return case v_abre
    when 'pronto' then v_resto
    when 'nome' then case when v_prim then format('Olá, %s! %s %s', v_nome, v_assin, upper(left(v_resto, 1)) || substr(v_resto, 2))
                          else v_nome || ', ' || v_resto end
    when 'bom_dia' then format('Bom dia, %s! %s', v_nome, case when v_prim then v_assin || ' ' else '' end || v_resto)
    when 'bom_dia_ponto' then format('Bom dia, %s. %s', v_nome, case when v_prim then v_assin || ' ' else '' end || v_resto)
    else case when v_prim then format('Olá, %s! %s Boa notícia: %s', v_nome, v_assin, v_resto)
              else format('Boa notícia, %s: %s', v_nome, v_resto) end
  end;
end;
$function$;
comment on function public._agenda_cliente_texto(text, text, uuid, jsonb, date) is
  'Agenda de Produção (Fase 5): a mensagem-modelo ao cliente (spec §6.1), pronta, com os dados do banco — tipos confirmar (M1: primeira, seguinte, unico; nula = primeira ou seguinte pelo contexto), vespera (M2), acesso (M4), material_chegou (M3), pode_atrasar (M6: peca, execucao, remarcado), nova_data (M7), andamento (M5: primeiro_dia, semanal), pronto e pronto_lembrete (M8), pos_servico (M9) e mudanca_no_dia (M10: clima, equipe, geral). p_dados = o que o passo calculou (envio, primeira, dia, fim, janela, n, n_feitos, quando, faixa_de/ate, peca_de/ate, dito_de/ate ou dia_dito); o que faltar sai do contexto (_agenda_cliente_contexto). Assinatura só na 1ª mensagem. Lança 22023 com o tipo ou a variante que não existe e quando falta um dado; nunca devolve texto pela metade. CORREÇÃO FASE 5 (C2): (item 12) p_dados.saudacao ("Bom dia" | "Boa tarde"; padrão "Bom dia") abre a véspera, o acesso e o M10 de chuva; (item 6) p_dados.forma = fim no M6 remarcado com o mesmo início ("{nome}, {servico} vai precisar de mais um dia: agora fica de {dia} até {fim}. Desculpe pela mudança. Pode ser? Responda SIM ou me diga outro dia."); (item 8) M6 peca_sem_data, sem data ("{nome}, quero te avisar com antecedência: ainda faltam peças {d}o serviço sem data de chegada, então {servico}, que estava {dito}, vai atrasar. Te digo a nova data assim que elas chegarem. Se isso atrapalhar algum plano seu, me diga."). FASE 6 (P7, spec-fase6 §6.1): a forma fim diz quantos dias o fim andou ("{nome}, {servico} vai terminar um dia depois do previsto: agora fica de {dia} até {fim}. …"; n ≥ 2: "… vai terminar {n} dias depois do previsto: …"; n = agenda_du_entre(dito_ate, fim); n < 1 = 22023); a peça sem data sem a repetição ("{nome}, quero te avisar com antecedência: ainda faltam peças sem data de chegada, então {servico}, que estava {dito}, vai atrasar. …"). Os dois textos novos ao cliente esperam o OK do dono antes de ligar. FASE 7d (P6, §6.1, AG7-21): o M11 onde_fica, variantes barco e motorhome, com p_dados.uso e p_dados.prazo; abre com o nome (com a assinatura na 1ª mensagem); o dia não é exigido. Texto aprovado; qualquer palavra fora da §6.1 volta a pedir o OK do dono. FASE 7f (P6): o tipo semana (M12, a semana prevista; AG7-36): compra_feita ("… está previsto para a semana de 16/11 (segunda 16/11 a quinta 19/11), com uns 3 dias de trabalho. O dia certo eu confirmo na véspera. Se algum dia dessa semana não der, me diga.") e compra_pendente ("… para a semana de 16/11, se as peças chegarem a tempo, com uns 3 dias …"). Exige faixa_de e faixa_ate na mesma semana e n ≥ 1 (22023). Sem data de pronto (AG7-32), sem "duas semanas" (R8.3-2).';

create or replace function public._agenda_cliente_tipo_texto(p_tipo text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case p_tipo
    when 'confirmar' then 'confirmação'
    when 'vespera' then 'véspera'
    when 'acesso' then 'véspera, com a pergunta do acesso'
    when 'material_chegou' then 'o material chegou'
    when 'andamento' then 'andamento'
    when 'pode_atrasar' then 'aviso de atraso'
    when 'nova_data' then 'nova data'
    when 'pronto' then 'ficou pronto'
    when 'pronto_lembrete' then 'lembrete da entrega'
    when 'pos_servico' then 'pós-serviço'
    -- FASE 7d: (7d P6, §6.1) o M11
    when 'onde_fica' then 'onde fica o bem'
    -- FASE 7d: fim
    -- FASE 7f: (7f P6) o M12
    when 'semana' then 'semana prevista'
    -- FASE 7f: fim
    when 'mudanca_no_dia' then 'mudança no dia'
  end;
$function$;
comment on function public._agenda_cliente_tipo_texto(text) is
  'Agenda de Produção (Fase 5, P2): o tipo da mensagem ao cliente como o dono lê ("confirmação", "véspera", "aviso de atraso", "ficou pronto"…). FASE 7d (P6): onde_fica = "onde fica o bem". FASE 7f (P6): semana = "semana prevista".';

create or replace function public._agenda_cliente_o_que(p_tipo text, p_dia date)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case p_tipo
    when 'confirmar' then 'a confirmação' || coalesce(' de ' || public._dia_curto(p_dia), '')
    when 'vespera' then 'o aviso da véspera' || coalesce(' de ' || public._dia_curto(p_dia), '')
    when 'acesso' then 'a véspera com a pergunta do acesso' || coalesce(' (' || public._dia_curto(p_dia) || ')', '')
    when 'material_chegou' then 'que o material chegou' || coalesce(' (começo ' || public._dia_curto(p_dia) || ')', '')
    when 'andamento' then 'o andamento do serviço'
    when 'pode_atrasar' then 'o aviso de que pode atrasar'
    when 'nova_data' then 'a nova data' || coalesce(': ' || public._dia_curto(p_dia), '')
    when 'pronto' then 'que o serviço ficou pronto'
    when 'pronto_lembrete' then 'o lembrete para combinar a entrega'
    when 'pos_servico' then 'a mensagem de pós-serviço'
    -- FASE 7d: (7d P6, §6.1) o M11. Quem chama diz "eu teria mandado para Nelson …", "Mandei para Nelson …" e "… que você aprovou para Nelson não saiu"
    when 'onde_fica' then 'a pergunta de onde fica o bem'
    -- FASE 7d: fim
    -- FASE 7f: (7f P6) o M12: a semana (a segunda dela), nunca o dia. Quem chama diz "eu teria mandado para Nelson …" e "Mandei para Nelson …"
    when 'semana' then 'a semana prevista do serviço' || coalesce(' (semana de ' || to_char(date_trunc('week', p_dia), 'DD/MM') || ')', '')
    -- FASE 7f: fim
    when 'mudanca_no_dia' then 'a mudança do dia' || coalesce(' (novo dia: ' || public._dia_curto(p_dia) || ')', '')
  end;
$function$;
comment on function public._agenda_cliente_o_que(text, date) is
  'Agenda de Produção (Fase 5, P2): o que a mensagem ao cliente diz, como o dono lê na linha do que mudou sozinho ("Mandei ao Nelson a confirmação de qui 05/11."). FASE 7d (P6): onde_fica = "a pergunta de onde fica o bem" (quem chama põe o verbo e o nome: "Em teste: eu teria mandado para Nelson a pergunta de onde fica o bem"). FASE 7f (P6): semana = "a semana prevista do serviço (semana de dd/mm)", a segunda da semana, nunca o dia.';

create or replace function public._agenda_cliente_a_mensagem(p_tipo text, p_variante text, p_dia date)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case p_tipo
    when 'confirmar' then 'à confirmação' || coalesce(' de ' || public._dia_curto(p_dia), '')
    when 'vespera' then 'ao aviso da véspera' || coalesce(' (' || public._dia_curto(p_dia) || ')', '')
    when 'acesso' then 'à pergunta do acesso' || coalesce(' (' || public._dia_curto(p_dia) || ')', '')
    when 'material_chegou' then 'ao aviso de que o material chegou' || coalesce(' (começo ' || public._dia_curto(p_dia) || ')', '')
    when 'nova_data' then 'à nova data' || coalesce(' (' || public._dia_curto(p_dia) || ')', '')
    when 'mudanca_no_dia' then 'à mudança do dia' || coalesce(' (novo dia: ' || public._dia_curto(p_dia) || ')', '')
    when 'pode_atrasar' then case when p_variante = 'remarcado'
                                  then 'à mudança de data' || coalesce(' (' || public._dia_curto(p_dia) || ')', '')
                                  else 'ao aviso de atraso' end
    when 'pronto' then 'ao "ficou pronto"'
    when 'pronto_lembrete' then 'ao lembrete da entrega'
    when 'pos_servico' then 'à mensagem de pós-serviço'
    when 'andamento' then 'ao andamento do serviço'
    -- FASE 7f: (7f P6) o M12: "respondeu … à semana prevista (semana de 16/11)"
    when 'semana' then 'à semana prevista' || coalesce(' (semana de ' || to_char(date_trunc('week', p_dia), 'DD/MM') || ')', '')
    -- FASE 7f: fim
    else 'à mensagem da agenda' end;
$function$;
comment on function public._agenda_cliente_a_mensagem(text, text, date) is
  'Agenda de Produção (Fase 5, P4): a mensagem ao cliente numa frase do dono, depois de "respondeu …" — "à confirmação de ter 03/11", "ao aviso da véspera (ter 03/11)", "ao aviso de atraso", "à mudança de data (qui 12/11)" (o M6 remarcado), "ao \"ficou pronto\"". FASE 7f (P6): semana = "à semana prevista (semana de dd/mm)".';

-- ── 4. O registro e a revalidação ───────────────────────────────────────────────────────────────────
create or replace function public._agenda_cliente_registrar(p_tipo text, p_variante text, p_os uuid, p_dia_alvo date,
                                                            p_dados jsonb, p_alvo timestamptz, p_valida_ate timestamptz,
                                                            p_origem text, p_critica text default null,
                                                            p_agora timestamptz default now(), p_autor uuid default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_tique constant interval := interval '15 minutes';   -- o tique do motor: o que sai até o próximo entra na fila agora
  v_hoje  date := (p_agora at time zone 'America/Sao_Paulo')::date;
  v_dados jsonb := coalesce(p_dados, '{}'::jsonb) - 'primeira' - 'envio' - 'chave' - 'prometido_tipo';
  x       jsonb;
  v_cli   uuid;
  v_modo  text;
  v_chave text;
  v_id    uuid := gen_random_uuid();
  v_ja    uuid;
  v_enviar timestamptz;
  v_valida timestamptz;
  v_prim  boolean;
  v_var   text := nullif(btrim(coalesce(p_variante, '')), '');
  v_txt   text;
  v_proib text;
  v_prom  text;
  v_aprov text;
  v_estado text := 'registrada';
  v_recusa text;
  v_perg  uuid;
  v_base  jsonb;
  v_r     jsonb;
  v_acao  uuid;
  v_aut   uuid;
  -- CORREÇÃO FASE 5: (item 12) a hora do meio-dia da saudação ("Bom dia" antes, "Boa tarde" depois: é o português, não
  -- um parâmetro da agenda nem o fim do turno da manhã)
  c_meio_dia_h constant int := 12;
  -- CORREÇÃO FASE 5: fim
  -- CORREÇÃO FASE 6: (C1) item 4: a folga do aviso em uso (dias úteis)
  v_folga int;
  -- CORREÇÃO FASE 6: fim
  -- FASE 7: (7a P11) a mensagem com dia de uma OS marcada pela estimativa do gestor
  v_f11_est boolean := false;
  -- FASE 7: fim
begin
  if cf.modo_cliente = 'desligado' then
    return jsonb_build_object('criada', false, 'modo', 'desligado');
  end if;
  if p_origem is null or p_origem not in ('rodada', 'dono', 'botao') then
    raise exception 'A mensagem ao cliente vem da rodada, do dono ou do botão (veio %).', coalesce(p_origem, 'nada') using errcode = '22023';
  end if;
  if p_critica is not null and p_critica not in ('segundo_atraso', 'atraso_longo', 'passou', 'teto') then
    raise exception 'Motivo de aviso crítico desconhecido: %.', p_critica using errcode = '22023';
  end if;
  if p_alvo is null then
    raise exception 'A mensagem ao cliente veio sem a hora.' using errcode = '22023';
  end if;
  select so.client_id into v_cli from public.service_orders so where so.id = p_os;
  if v_cli is null then
    raise exception 'A mensagem ao cliente veio sem a OS (ou a OS sem cliente).' using errcode = '22023';
  end if;
  x := public._agenda_cliente_contexto(p_os, v_hoje);

  -- o modo da linha: ligado só com modo_cliente ligado E o tipo na lista das ondas; senão em teste (a chave com :sombra)
  v_modo := case when cf.modo_cliente = 'ligado' and p_tipo = any (cf.cliente_tipos_ligados) then 'ligado' else 'sombra' end;
  -- FASE 7f: (7f P6, §5.6 item 1, R8.6) a semana prevista (M12) só vai de verdade com as camadas ligadas pelo freio (_agenda_fala_modo('camadas')): com *gestor,
  -- só propor*, em teste ou desligadas, ela é teste (a chave com ":sombra", nada vai à fila), mesmo com o tipo na lista. Os outros tipos, o de antes
  if p_tipo = 'semana' and v_modo = 'ligado' and public._agenda_fala_modo('camadas') <> 'ligado' then
    v_modo := 'sombra';
  end if;
  -- FASE 7f: fim
  v_chave := format('agenda-cliente:%s:%s:%s', p_tipo, p_os,
                    coalesce(nullif(btrim(p_dados ->> 'chave'), ''), p_dia_alvo::text,
                             to_char(p_alvo at time zone 'America/Sao_Paulo', 'YYYY-MM-DD')))
             || case when v_modo = 'sombra' then ':sombra' else '' end;
  select m.id into v_ja from public.agenda_cliente_mensagens m where m.dedupe_key = v_chave;
  if v_ja is not null then
    return jsonb_build_object('criada', false, 'modo', v_modo, 'motivo', 'ja_existe', 'id', v_ja);
  end if;

  -- a hora (a janela, o feriado, o intervalo) e o texto contado do dia em que ele SAI (o "Amanhã"), com a assinatura só na
  -- 1ª mensagem; o registro guarda os dois (a revalidação recalcula com eles)
  v_enviar := public._agenda_cliente_quando(hashtext(v_chave), p_alvo, p_agora);
  -- CORREÇÃO FASE 5: (item 12) a saudação dos que abrem com ela (a véspera, o acesso e a mudança no dia por chuva) segue a
  -- hora em que a mensagem SAI (Brasília): "Bom dia" antes do meio-dia, "Boa tarde" depois. Fica em p_dados (e em
  -- base.dados): a revalidação recalcula igual, e a hora que muda depois (a conversa viva) não a deixa desatualizada.
  if p_tipo in ('vespera', 'acesso', 'mudanca_no_dia') then
    v_dados := v_dados || jsonb_build_object('saudacao',
                 case when extract(hour from (v_enviar at time zone 'America/Sao_Paulo')) < c_meio_dia_h then 'Bom dia'
                      else 'Boa tarde' end);
  end if;
  -- CORREÇÃO FASE 5: fim
  v_prim := coalesce((p_dados ->> 'primeira')::boolean, (x ->> 'primeira')::boolean, false);
  if p_tipo = 'confirmar' and v_var is null then
    v_var := case when v_prim then 'primeira' else 'seguinte' end;
  end if;
  v_txt := public._agenda_cliente_texto(p_tipo, v_var, p_os,
             v_dados || jsonb_build_object('primeira', v_prim, 'envio', (v_enviar at time zone 'America/Sao_Paulo')::date), v_hoje);
  v_proib := public._agenda_cliente_texto_proibido(v_txt);
  if v_proib is not null then
    raise exception 'A mensagem ao cliente não pode levar % (o texto: "%").', v_proib, left(v_txt, 120) using errcode = '22023';
  end if;
  -- o que a mensagem DIZ de data (vira o prometido quando sai): firme nos modelos com dia; faixa no atraso da peça e da
  -- execução (condicional, se o passo disser); nada no andamento, no pronto e no pós-serviço
  v_prom := coalesce(nullif(btrim(p_dados ->> 'prometido_tipo'), ''),
                     case when p_tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')
                               or (p_tipo = 'pode_atrasar' and v_var = 'remarcado') then 'firme'
                          when p_tipo = 'pode_atrasar' then 'faixa' end);
  if v_prom is not null and v_prom not in ('condicional', 'faixa', 'firme') then
    raise exception 'O que a mensagem diz de data é condicional, faixa ou firme (veio %).', v_prom using errcode = '22023';
  end if;
  -- CORREÇÃO FASE 5: (item 8) o aviso "ainda faltam peças sem data" não diz data: não vira prometido (ao sair, o gatilho do
  -- envio tira o que o cliente tinha ouvido)
  if p_tipo = 'pode_atrasar' and v_var = 'peca_sem_data' then
    v_prom := null;
  end if;
  -- CORREÇÃO FASE 5: fim
  -- CORREÇÃO FASE 6: (C1) item 4: o aviso de atraso da peça e da execução com a folga do aprendizado em uso (o mesmo
  -- _agenda_aprendido('aviso_folga', 'todas') que _agenda_cliente_risco somou ao fim da faixa) guarda em base.dados o fim da
  -- faixa SEM a folga (faixa_ate_plano): é contra ele que a medição mede o estouro (senão a folga aprenderia contra ela
  -- mesma e iria de 2 a 0 e de volta). O texto e a chave não mudam.
  if p_tipo = 'pode_atrasar' and v_var in ('peca', 'execucao') and (v_dados ->> 'faixa_ate') is not null then
    v_folga := coalesce(round(public._agenda_aprendido('aviso_folga', 'todas'))::int, 0);
    if v_folga > 0 then
      v_dados := v_dados || jsonb_build_object('faixa_ate_plano',
                                               public.agenda_somar_du((v_dados ->> 'faixa_ate')::date, -v_folga));
    end if;
  end if;
  -- CORREÇÃO FASE 6: fim
  -- FASE 7: (7a P11, spec §3.2 "Cliente" e §5.11; AG7-16) a mensagem com dia (confirmar, nova_data, material_chegou) de uma OS
  -- marcada pela estimativa do gestor (_agenda_os_por_estimativa: compromisso de duracao_fonte orcamento de agora em diante, sem
  -- os dias do dono) leva base.dados.por_estimativa — o que a aprovação abaixo e o zero cliente_estimativa_sem_aprovacao da saúde
  -- leem. A véspera e os outros tipos não mudam. Nenhum texto novo ao cliente.
  if p_tipo in ('confirmar', 'nova_data', 'material_chegou')
     and public._agenda_os_por_estimativa(p_os, coalesce(p_dia_alvo, (p_dados ->> 'dia')::date, v_hoje)) then
    v_dados := v_dados || jsonb_build_object('por_estimativa', true);
    v_f11_est := true;
  end if;
  -- FASE 7: fim
  v_valida := coalesce(p_valida_ate, public._agenda_cliente_fim_da_janela((v_enviar at time zone 'America/Sao_Paulo')::date, 0));
  v_base := jsonb_build_object(
    'status', x ->> 'status',
    'dia_alvo', coalesce((p_dados ->> 'dia')::date, (x ->> 'dia')::date, p_dia_alvo),
    'fim', coalesce((p_dados ->> 'fim')::date, (x ->> 'fim')::date),
    'nivel', x ->> 'nivel_material',
    'prometido_ate', x #>> '{prometido,ate}',
    'primeira', v_prim,
    'envio', (v_enviar at time zone 'America/Sao_Paulo')::date,
    'referencia', case when x -> 'plano' is null or jsonb_typeof(x -> 'plano') = 'null' then 'agendada' else 'plano' end,
    'dados', v_dados);

  -- a aprovação (em ligado): a crítica pergunta (cliente_aviso); a do dono e a do tipo ainda não liberado pedem *manda
  -- cliente* (cliente_aprovar); a do botão já foi aprovada pelo clique; o resto sai sozinho. Em teste, sempre livre.
  if v_enviar > v_valida then
    v_aprov := 'livre';
    v_estado := 'recusada';
    v_recusa := 'vencida';
  elsif v_modo = 'sombra' then
    v_aprov := 'livre';
  elsif p_critica is not null then
    v_aprov := 'critica';
    v_estado := 'aguardando_dono';
    v_perg := public._agenda_cliente_perguntar('cliente_aviso',
                format('cliente_aviso:%s:%s', p_os, coalesce(p_dia_alvo, (v_enviar at time zone 'America/Sao_Paulo')::date)),
                p_os, p_dia_alvo, (v_enviar at time zone 'America/Sao_Paulo')::date,
                public._agenda_cliente_texto_do_aviso(p_critica, p_tipo, p_os, p_dados, v_hoje), 'ligado', p_agora, v_valida);
  elsif p_origem = 'botao' then
    v_aprov := 'aprovada';
    v_aut := (select u.id from public.app_users u where u.id = p_autor);
  elsif p_origem = 'dono' or not public._agenda_cliente_tipo_liberado(p_tipo) then
    v_aprov := 'pedida';
    v_estado := 'aguardando_dono';
    v_perg := public._agenda_cliente_perguntar('cliente_aprovar', 'cliente_aprovar:' || v_id, p_os, p_dia_alvo,
                (v_enviar at time zone 'America/Sao_Paulo')::date,
                case when p_origem = 'dono'
                     then format('Pronto para o %s, sai %s: "%s". Para mandar: *manda cliente %s*.', x ->> 'nome',
                                 public._agenda_cliente_quando_texto(v_enviar, p_agora), v_txt, x ->> 'nome')
                     else format('Mensagem para o %s (%s), sai %s: "%s". *manda cliente %s* ou *segura cliente %s*.', x ->> 'nome',
                                 public._agenda_cliente_tipo_texto(p_tipo), public._agenda_cliente_quando_texto(v_enviar, p_agora),
                                 v_txt, x ->> 'nome', x ->> 'nome') end,
                'ligado', p_agora, v_valida);
  -- FASE 7: (7a P11) por estimativa: o sim do dono (*manda cliente*) até somar cliente_aprovacao_dias dias distintos aprovados por
  -- estimativa desse tipo (_agenda_cliente_estimativa_liberada), mesmo com o tipo já liberado (d11). A crítica, o botão e a do
  -- dono seguem acima, como antes.
  elsif v_f11_est and not public._agenda_cliente_estimativa_liberada(p_tipo) then
    v_aprov := 'pedida';
    v_estado := 'aguardando_dono';
    v_perg := public._agenda_cliente_perguntar('cliente_aprovar', 'cliente_aprovar:' || v_id, p_os, p_dia_alvo,
                (v_enviar at time zone 'America/Sao_Paulo')::date,
                format('Mensagem para %s (%s; o dia é pela minha estimativa), sai %s: "%s". *manda cliente %s* ou *segura cliente %s*.',
                       x ->> 'nome', public._agenda_cliente_tipo_texto(p_tipo), public._agenda_cliente_quando_texto(v_enviar, p_agora),
                       v_txt, x ->> 'nome', x ->> 'nome'),
                'ligado', p_agora, v_valida);
  -- FASE 7: fim
  else
    v_aprov := 'livre';
  end if;

  insert into public.agenda_cliente_mensagens (id, client_id, service_order_id, tipo, variante, origem, dia_alvo, faixa_de,
                                               faixa_ate, prometido_tipo, modo, texto, base, enviar_em, valida_ate, aprovacao,
                                               pergunta_id, aprovada_em, aprovada_por, estado, recusa_motivo, dedupe_key,
                                               criada_em)
  values (v_id, v_cli, p_os, p_tipo, v_var, p_origem, p_dia_alvo, (p_dados ->> 'faixa_de')::date,
          (p_dados ->> 'faixa_ate')::date, v_prom, v_modo, v_txt, v_base, v_enviar, v_valida, v_aprov, v_perg,
          case when v_aprov = 'aprovada' then p_agora end, v_aut, v_estado, v_recusa, v_chave, p_agora);

  -- CORREÇÃO FASE 5: (item 15) a linha da sombra sem artigo antes do nome ("Em teste: eu teria mandado para Lucenira …"; a
  -- ação não muda depois de gravada, então ela já nasce assim). O bloco de 20261028100300 logo abaixo não roda mais para a
  -- sombra (v_modo fica 'sombra_feita' só entre os dois blocos).
  if v_modo = 'sombra' then
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
    values (clock_timestamp(), v_hoje, false, 'vigia', 'cliente', p_os, array[p_os], '{}'::jsonb,
            jsonb_build_object('mensagem_id', v_id, 'tipo', p_tipo, 'enviar_em', v_enviar),
            left(format('Em teste: eu teria mandado para %s %s (sairia %s).', x ->> 'nome',
                        public._agenda_cliente_o_que(p_tipo, coalesce((v_base ->> 'dia_alvo')::date, p_dia_alvo)),
                        public._agenda_cliente_quando_texto(v_enviar, p_agora)), 400))
    returning id into v_acao;
    update public.agenda_cliente_mensagens set acao_id = v_acao where id = v_id;
    v_modo := 'sombra_feita';
  end if;
  -- CORREÇÃO FASE 5: fim
  -- em teste: o que a agenda teria mandado (a linha do que mudou sozinho, sem executar)
  if v_modo = 'sombra' then
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
    values (clock_timestamp(), v_hoje, false, 'vigia', 'cliente', p_os, array[p_os], '{}'::jsonb,
            jsonb_build_object('mensagem_id', v_id, 'tipo', p_tipo, 'enviar_em', v_enviar),
            left(format('Em teste: eu teria mandado ao %s %s (sairia %s).', x ->> 'nome',
                        public._agenda_cliente_o_que(p_tipo, coalesce((v_base ->> 'dia_alvo')::date, p_dia_alvo)),
                        public._agenda_cliente_quando_texto(v_enviar, p_agora)), 400))
    returning id into v_acao;
    update public.agenda_cliente_mensagens set acao_id = v_acao where id = v_id;
  end if;

  -- CORREÇÃO FASE 5: (item 15) o modo volta a ser o da linha
  if v_modo = 'sombra_feita' then
    v_modo := 'sombra';
  end if;
  -- CORREÇÃO FASE 5: fim
  -- o que sai até o próximo tique entra na fila agora; o de depois fica registrado e o passo "fila" o enfileira na hora
  if v_modo = 'ligado' and v_estado = 'registrada' and v_aprov in ('livre', 'aprovada') and v_enviar <= p_agora + c_tique then
    v_r := public._agenda_cliente_enfileirar(v_id, p_agora);
  end if;
  return jsonb_build_object('criada', true, 'id', v_id, 'modo', v_modo, 'estado', v_estado, 'motivo', v_recusa,
                            'aprovacao', v_aprov, 'pergunta_id', v_perg, 'enviar_em', v_enviar, 'valida_ate', v_valida,
                            'texto', v_txt)
         || coalesce(v_r, '{}'::jsonb);
end;
$function$;
comment on function public._agenda_cliente_registrar(text, text, uuid, date, jsonb, timestamptz, timestamptz, text, text, timestamptz, uuid) is
  'Agenda de Produção (Fase 5, P2): grava a mensagem-modelo ao cliente e decide o envio — desligado = nada; o texto é o do banco (_agenda_cliente_texto, contado do dia do envio, com a assinatura só na 1ª mensagem; o proibido = 22023); o modo da linha: ligado só com modo_cliente ligado E o tipo em cliente_tipos_ligados, senão sombra (chave com :sombra, a ação "Em teste: eu teria mandado…"); a chave agenda-cliente:<tipo>:<os>:<p_dados.chave | dia_alvo | o dia do alvo> (uma só: a 2ª devolve ja_existe); enviar_em pelo _agenda_cliente_quando; valida_ate = p_valida_ate, senão o fim da janela do dia do envio (passou dela = recusada/vencida); a aprovação em ligado: p_critica (segundo_atraso, atraso_longo, passou, teto) = critica + pergunta cliente_aviso; origem dono ou tipo ainda não liberado = pedida + pergunta cliente_aprovar; botão = aprovada (aprovada_por = p_autor); senão livre. base guarda {status, dia_alvo, fim, nivel, prometido_ate, primeira, envio, referencia, dados} para a revalidação. A livre/aprovada que sai até o próximo tique vai a _agenda_cliente_enfileirar. p_dados: os do modelo (dia, fim, janela, n, faixa_de/ate, peca_de/ate, dito_de/ate, dia_dito, quando, n_feitos), primeira, prometido_tipo, chave (o sufixo da chave no lugar do dia: o lembrete e o andamento semanal), atraso_dias (o aviso crítico). Sem grant. CORREÇÃO FASE 5 (C2): (item 12) a véspera, o acesso e a mudança no dia ganham p_dados.saudacao pela hora do envio (Brasília: "Bom dia" antes das 12:00, "Boa tarde" depois), guardada em base.dados; (item 8) o M6 peca_sem_data não tem prometido_tipo; (item 15) a ação da sombra sem artigo antes do nome. CORREÇÃO FASE 6 (C1, item 4): o aviso de atraso (peca/execucao) com a folga do aprendizado em uso guarda em base.dados.faixa_ate_plano o fim da faixa sem a folga (a medição mede o estouro contra ele). FASE 7 (7a P11, spec §3.2 "Cliente" e §5.11; AG7-16): confirmar, nova_data e material_chegou de uma OS marcada pela estimativa do gestor (_agenda_os_por_estimativa no dia da mensagem) levam base.dados.por_estimativa = true e, fora da crítica, do botão e da do dono, pedem o sim do dono (aprovacao pedida, a pergunta cliente_aprovar "Mensagem para Lenine (confirmação do dia; o dia é pela minha estimativa), sai …") enquanto o tipo não somou cliente_aprovacao_dias dias distintos aprovados por estimativa (_agenda_cliente_estimativa_liberada), mesmo com o tipo já liberado. O texto ao cliente não muda; a véspera e os outros tipos, também não. Sem OS por estimativa, a de antes, byte a byte. FASE 7f (P6): a semana (M12) só fica ligada com as camadas ligadas pelo freio (_agenda_fala_modo); senão é teste. O prometido_tipo dela vem de p_dados (faixa ou condicional).';

create or replace function public._agenda_cliente_revalidar(p_msg uuid, p_agora timestamptz default now())
 returns text
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  m      public.agenda_cliente_mensagens%rowtype;
  so     record;
  v_hoje date := (p_agora at time zone 'America/Sao_Paulo')::date;
  v_plano jsonb;
  v_agora_dia date;
  v_nivel text;
  v_txt  text;
  v_dados jsonb;
begin
  select * into m from public.agenda_cliente_mensagens where id = p_msg;
  if not found then
    return 'desatualizada';
  end if;
  -- 1. o cliente pediu para não receber (ou o cadastro saiu)
  if public._agenda_cliente_sem_mensagem(m.client_id) then
    return 'opt_out';
  end if;
  -- CORREÇÃO FASE 5: (item 13) 1b. o d10 também na revalidação — e por isso no gatilho da fila (as duas travas) e no
  -- agenda_cliente_pode_sair (o worker): a quem não escreveu para a HBR em cliente_conversa_dias a mensagem não sai, por
  -- qualquer caminho. Sem telefone válido, o motivo verdadeiro é o telefone (como no enfileirar).
  if not public._agenda_cliente_conversou(m.client_id, p_agora) then
    return case when public._agenda_cliente_telefone(m.client_id) is null then 'sem_telefone' else 'sem_conversa' end;
  end if;
  -- CORREÇÃO FASE 5: fim
  -- 2. o status da OS
  select o.status, o.delivered_at, o.scheduled_start_at, o.scheduled_end_at into so
    from public.service_orders o where o.id = m.service_order_id;
  -- CORREÇÃO FASE 5: (item 24) a OS faturada (invoiced) logo depois de concluída vale como concluída — o resto da Fase 5
  -- já a trata assim (a resposta, o cliente_avisar): o "ficou pronto" e o pós-serviço dela saem; o aviso de atraso não
  if found and so.status = 'invoiced' then
    so.status := 'completed';
  end if;
  -- CORREÇÃO FASE 5: fim
  if not found or so.status in ('cancelled', 'draft')
     or (m.tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')
         and so.status in ('awaiting_parts', 'awaiting_client', 'completed'))
     or (m.tipo = 'andamento' and so.status <> 'in_progress')
     or (m.tipo in ('pronto', 'pronto_lembrete') and (so.status <> 'completed' or so.delivered_at is not null))
     or (m.tipo = 'pos_servico' and so.status <> 'completed')
     or (m.tipo = 'pode_atrasar' and so.status = 'completed') then
    return 'status';
  end if;
  -- FASE 7d: (7d P6; R6.7a-3, §5.6) o M11, na hora de sair: a OS é relida. O que já foi feito não recebe; o que já foi dito perdeu o sentido
  if m.tipo = 'onde_fica' then
    -- (correção C2) parar o M11 (onde_fica_desde nula) recusa também o que está na fila, como tirar o tipo da lista
    if cf.onde_fica_desde is null then
      return 'tipo_em_teste';
    end if;
    if public._agenda_cliente_ja_atendida(m.service_order_id) is not null then
      return 'status';
    end if;
    if public._agenda_cliente_onde_falta(m.service_order_id, v_hoje) is null then
      return 'desatualizada';
    end if;
  end if;
  -- FASE 7d: fim
  -- FASE 7f: (7f P6, R8.5-24; molde do M11) a semana prevista, na hora de sair: só com as camadas ligadas de verdade (pelo freio: frear ou desligar recusa
  -- também o que está na fila, como tirar o tipo da lista); a OS não pode estar começada, esperando peça ou cliente, nem concluída (R8.5-21); o 1º dia do plano
  -- de agora saiu da faixa dita = desatualizada (e o último dia também: a OS que passou a cruzar a semana não recebe a semana, R8.3-2). O passo semana tenta de
  -- novo, com a semana de agora, no dia seguinte
  if m.tipo = 'semana' then
    if public._agenda_fala_modo('camadas') <> 'ligado' then
      return 'tipo_em_teste';
    end if;
    if so.status in ('awaiting_parts', 'awaiting_client', 'in_progress', 'completed') then
      return 'status';
    end if;
    v_plano := public._agenda_plano_da_os(m.service_order_id, v_hoje);
    if m.faixa_de is null or m.faixa_ate is null or (v_plano ->> 'proximo_dia') is null or (v_plano ->> 'ultimo_dia') is null
       or (v_plano ->> 'proximo_dia')::date not between m.faixa_de and m.faixa_ate
       or (v_plano ->> 'ultimo_dia')::date not between m.faixa_de and m.faixa_ate then
      return 'desatualizada';
    end if;
  end if;
  -- FASE 7f: fim
  -- 3. a data: o dia de que a mensagem fala (o próximo dia do plano; sem plano no registro, o dia agendado da OS) e, nos
  -- tipos de fim (o andamento e o atraso da execução), o último dia
  v_plano := public._agenda_plano_da_os(m.service_order_id, v_hoje);
  if m.base ? 'dia_alvo'
     and (m.tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')
          or (m.tipo = 'pode_atrasar' and m.variante = 'remarcado')) then
    v_agora_dia := case when m.base ->> 'referencia' = 'agendada'
                        then (so.scheduled_start_at at time zone 'America/Sao_Paulo')::date
                        else (v_plano ->> 'proximo_dia')::date end;
    if v_agora_dia is distinct from (m.base ->> 'dia_alvo')::date then
      return 'data_mudou';
    end if;
  end if;
  if m.base ? 'fim' and m.base ->> 'referencia' = 'plano'
     and (m.tipo = 'andamento' or (m.tipo = 'pode_atrasar' and m.variante = 'execucao'))
     and (v_plano ->> 'ultimo_dia')::date is distinct from (m.base ->> 'fim')::date then
    return 'data_mudou';
  end if;
  -- CORREÇÃO FASE 5: (item 6) o remarcado em que só o fim mudou (a forma fim) diz o fim: o último dia de agora tem de ser
  -- o dele. (item 7) a data firme que o DONO mandou dizer (cliente_avisar firme: base.dados.firme_do_dono) não passa pelo
  -- passo 4 — o d09 deixa o dono trocar a faixa pela data firme do plano; os passos 1–3 e 5–7 continuam
  if m.tipo = 'pode_atrasar' and m.variante = 'remarcado' and m.base #>> '{dados,forma}' = 'fim'
     and (v_plano ->> 'ultimo_dia')::date is distinct from (m.base ->> 'fim')::date then
    return 'data_mudou';
  end if;
  if m.origem = 'dono' and coalesce((m.base #>> '{dados,firme_do_dono}')::boolean, false) then
    m.prometido_tipo := null;   -- só nesta cópia local: o passo 4, abaixo, não vale para ela
  end if;
  -- CORREÇÃO FASE 5: fim
  -- 4. a data firme sem todo o material crítico na mão (d09): o pior nível dos críticos fora de A
  if m.prometido_tipo = 'firme' then
    v_nivel := public.os_prontidao(m.service_order_id, v_hoje) #>> '{material,confianca}';
    if v_nivel is not null and v_nivel <> 'A' then
      return 'material';
    end if;
  end if;
  -- 5. o aviso de atraso depois da data que o cliente ouviu (não sai: vira pergunta crítica na rodada)
  if m.tipo = 'pode_atrasar'
     and exists (select 1 from public.os_planejamento p
                  where p.service_order_id = m.service_order_id and p.prometido_ate < v_hoje) then
    return 'passou_da_data';
  end if;
  -- 6. o mesmo tipo a este cliente nas últimas cliente_mesmo_tipo_horas
  if exists (select 1 from public.agenda_cliente_mensagens x
              where x.client_id = m.client_id and x.tipo = m.tipo and x.id <> m.id and x.enviada_em is not null
                and x.enviada_em > p_agora - make_interval(hours => cf.cliente_mesmo_tipo_horas)) then
    return 'mesmo_tipo_24h';
  end if;
  -- 7. o texto de agora (os mesmos dados, a mesma 1ª mensagem, o dia do envio de agora) ≠ o registrado
  v_dados := coalesce(m.base -> 'dados', '{}'::jsonb)
             || jsonb_build_object('primeira', coalesce((m.base ->> 'primeira')::boolean, false),
                                   'envio', (m.enviar_em at time zone 'America/Sao_Paulo')::date);
  begin
    v_txt := public._agenda_cliente_texto(m.tipo, m.variante, m.service_order_id, v_dados, v_hoje);
  exception when others then
    return 'desatualizada';
  end;
  if v_txt is distinct from m.texto then
    return 'desatualizada';
  end if;
  return null;
end;
$function$;
comment on function public._agenda_cliente_revalidar(uuid, timestamptz) is
  'Agenda de Produção (Fase 5, P2): a mensagem ao cliente ainda vale em p_agora? null = sai; senão, na ordem: opt_out (_agenda_cliente_sem_mensagem); status (OS cancelada/rascunho; confirmar, véspera, acesso, material chegou, nova data e mudança no dia com a OS aguardando peça, aguardando o cliente ou concluída; andamento fora de in_progress; pronto e lembrete fora de completed ou já entregue; pós-serviço fora de completed; aviso de atraso com a OS concluída); data_mudou (o próximo dia do plano — sem plano no registro, o dia agendado da OS — ≠ base.dia_alvo; no andamento e no atraso da execução, o último dia ≠ base.fim); material (data firme com algum crítico fora de A, os_prontidao); passou_da_data (aviso de atraso com o prometido_ate antes de hoje); mesmo_tipo_24h (outra do mesmo tipo a ele enviada nas últimas cliente_mesmo_tipo_horas); desatualizada (_agenda_cliente_texto com os dados do registro, a 1ª mensagem de base e o dia do envio de agora ≠ o texto registrado, ou o modelo que não fecha mais). STABLE, definer, sem grant (o pode_sair do worker e as travas a chamam). CORREÇÃO FASE 5 (C1, item 13): depois do opt_out, sem_conversa (o d10: _agenda_cliente_conversou em p_agora; sem telefone válido, sem_telefone) — vale também no gatilho da fila e no pode_sair. CORREÇÃO FASE 5 (C2): (item 24) a OS faturada vale como concluída; (item 6) o M6 remarcado na forma fim também recusa data_mudou quando o último dia ≠ base.fim; (item 7) a data firme do dono (origem dono, base.dados.firme_do_dono) não passa pelo passo 4 (material). FASE 7d (P6; R6.7a-3, §5.6): onde_fica é relida na hora de sair — status com _agenda_cliente_ja_atendida (in_progress, awaiting_client, completed, faturada, entregue, check-in, check-out, resultado, turno, paga) e desatualizada com _agenda_cliente_onde_falta nula (o local e a situação já ditos). FASE 7f (P6): a semana: tipo_em_teste sem as camadas ligadas de verdade; status com a OS começada, esperando peça ou cliente, ou concluída; desatualizada quando o 1º ou o último dia do plano de agora saiu da faixa dita.';

-- ── 5. O dia exato na véspera e o M3/M7 dentro da semana ────────────────────────────────────────────
create or replace function public._agenda_cliente_confirmar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_perto constant interval := interval '2 days';   -- spec §5.3: "não sai se o M1 saiu há menos de 2 dias corridos"
  r       record;
  x       jsonb;
  v_d     date;
  v_m1    timestamptz;
  v_vesp  date;
  v_alvo_v timestamptz;
  v_tipo  text;
  v_r     jsonb;
  n_m1    int := 0;
  n_vesp  int := 0;
  n_unico int := 0;
  n_pula  int := 0;
  -- CORREÇÃO FASE 5: (item 4) as OS puladas por erro
  n_erro int := 0;
  -- CORREÇÃO FASE 5: fim
  -- FASE 7f: (7f P6, §5.6, AG7-16) o dia do toque da OS em camada
  v_7f_d date;
  -- FASE 7f: fim
begin
  for r in
    select k.service_order_id as os
      from public.os_carteira(p_hoje) k
     where k.status not in ('awaiting_parts', 'awaiting_client', 'in_progress')
     order by k.numero collate "C", k.service_order_id
  loop
    -- CORREÇÃO FASE 5: (item 4) cada OS no seu bloco: o erro de uma (o texto que não fecha, o proibido) vai a
    -- app_error_logs (agenda / cliente:confirmar:os) e o passo segue para as outras
    begin
    -- CORREÇÃO FASE 5: fim
    x := public._agenda_plano_da_os(r.os, p_hoje);
    v_d := (x ->> 'proximo_dia')::date;
    continue when v_d is null or v_d <= p_hoje;
    -- ainda não começou: nenhum dia antes do próximo (cumprido, parcial ou sem registro)
    continue when coalesce((x ->> 'inicio')::date, v_d) < v_d;
    continue when public.os_prontidao(r.os, p_hoje) #>> '{material,estado}' is distinct from 'completo';
    x := public._agenda_cliente_contexto(r.os, p_hoje);
    v_vesp := public._agenda_cliente_vespera(v_d);
    continue when v_vesp is null or v_vesp < p_hoje;
    v_alvo_v := public._agenda_cliente_toque(v_vesp);
    v_m1 := public._agenda_cliente_toque(public.agenda_somar_du(v_d, -cf.cliente_confirmar_du));
    if v_m1 < p_agora then
      v_m1 := public._agenda_cliente_proximo_toque(p_agora);
    end if;
    -- FASE 7f: (7f P6, §5.6, AG7-16 "semana prevista até ficar seguro") a OS em camada (_agenda_cliente_camada: a marcada pela estimativa), com as camadas
    -- ligadas de verdade: o dia exato vai cliente_dia_exato_du dias de janela antes de D — com 1, a véspera, e o M1 vira o toque único que o código já tem (a
    -- véspera de uma segunda é o sábado, dia de janela: contar em dias úteis daria a sexta e mais a véspera). A exigência do material completo, acima, fica.
    -- R8.8: com as camadas fora de ligado (o cf já lido), nada novo se lê; o freio (_agenda_fala_modo) só é lido com elas ligadas
    if cf.modo_cliente_camadas = 'ligado' and public._agenda_fala_modo('camadas') = 'ligado'
       and public._agenda_cliente_camada(r.os, p_hoje) ->> 'camada' = 'semana' then
      v_7f_d := v_d;
      for v_7f_i in 1 .. cf.cliente_dia_exato_du loop
        v_7f_d := public._agenda_cliente_vespera(v_7f_d);
      end loop;
      v_m1 := public._agenda_cliente_toque(v_7f_d);
      if v_m1 < p_agora then
        v_m1 := public._agenda_cliente_proximo_toque(p_agora);
      end if;
    end if;
    -- FASE 7f: fim
    -- CORREÇÃO FASE 5: (item 20) o botão antigo já pediu a confirmação deste D (dentro de cliente_resposta_validade, sem
    -- resposta, e o dia que ele confirma é o D), ou o cliente já confirmou o D: o M1 (e o toque único da confirmação) não
    -- sai — seria a 2ª confirmação do mesmo dia. A véspera segue a regra dela.
    if exists (select 1 from public.service_orders so
                where so.id = r.os
                  and ((so.client_confirmation_requested_at > p_agora - cf.cliente_resposta_validade
                        and so.client_confirmation_requested_at <= p_agora and so.client_confirmed_at is null
                        and (public._agenda_cliente_dia_a_confirmar(r.os, p_agora) at time zone 'America/Sao_Paulo')::date = v_d)
                       or (so.client_confirmed_for at time zone 'America/Sao_Paulo')::date = v_d)) then
      v_m1 := null;
    end if;
    -- CORREÇÃO FASE 5: fim
    -- a mensagem que já propôs este D (o material chegou M3, a nova data M7, a mudança no dia M10, o aviso remarcado)
    -- substitui a confirmação; a véspera só sai se ela saiu há c_perto ou mais (abaixo)
    if exists (select 1 from public.agenda_cliente_mensagens m
                where m.service_order_id = r.os
                  and (m.tipo in ('material_chegou', 'nova_data', 'mudanca_no_dia')
                       or (m.tipo = 'pode_atrasar' and m.variante = 'remarcado'))
                  and coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) = v_d and m.estado <> 'recusada') then
      if exists (select 1 from public.agenda_cliente_mensagens m
                  where m.service_order_id = r.os
                    and (m.tipo in ('material_chegou', 'nova_data', 'mudanca_no_dia')
                         or (m.tipo = 'pode_atrasar' and m.variante = 'remarcado'))
                    and coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) = v_d and m.estado <> 'recusada'
                    and (m.enviada_em is null or m.enviada_em > v_alvo_v - c_perto)) then
        n_pula := n_pula + 1;
        continue;
      end if;
      v_m1 := null;
    end if;

    if v_m1 is not null and (v_m1 at time zone 'America/Sao_Paulo')::date >= v_vesp then
      -- um toque só, na véspera (que também não sai se a confirmação saiu há menos de c_perto)
      if public._agenda_cliente_ja_registra(v_vesp, p_hoje, p_agora) then
        if exists (select 1 from public.agenda_cliente_mensagens m
                    where m.service_order_id = r.os and m.tipo in ('confirmar', 'material_chegou', 'nova_data')
                      and m.enviada_em is not null and m.enviada_em > v_alvo_v - c_perto) then
          n_pula := n_pula + 1;
          continue;
        end if;
        v_tipo := case when coalesce((x ->> 'acesso_conhecido')::boolean, false) then 'confirmar' else 'acesso' end;
        v_r := public._agenda_cliente_registrar(v_tipo, case when v_tipo = 'confirmar' then 'unico' end, r.os, v_d,
                 '{}'::jsonb, v_alvo_v, public._agenda_cliente_fim_da_janela(v_vesp, 0), 'rodada', null, p_agora);
        if coalesce((v_r ->> 'criada')::boolean, false) then n_unico := n_unico + 1; end if;
      end if;
      continue;
    end if;
    -- a confirmação (D-3)
    if v_m1 is not null and public._agenda_cliente_ja_registra((v_m1 at time zone 'America/Sao_Paulo')::date, p_hoje, p_agora) then
      v_r := public._agenda_cliente_registrar('confirmar', null, r.os, v_d, '{}'::jsonb, v_m1,
               public._agenda_cliente_fim_da_janela((v_m1 at time zone 'America/Sao_Paulo')::date, 0), 'rodada', null, p_agora);
      if coalesce((v_r ->> 'criada')::boolean, false) then n_m1 := n_m1 + 1; end if;
    end if;
    -- a véspera (D-1)
    if public._agenda_cliente_ja_registra(v_vesp, p_hoje, p_agora) then
      if exists (select 1 from public.agenda_cliente_mensagens m
                  where m.service_order_id = r.os and m.tipo in ('confirmar', 'material_chegou', 'nova_data')
                    and m.enviada_em is not null and m.enviada_em > v_alvo_v - c_perto) then
        n_pula := n_pula + 1;
        continue;
      end if;
      v_tipo := case when coalesce((x ->> 'acesso_conhecido')::boolean, false) then 'vespera' else 'acesso' end;
      v_r := public._agenda_cliente_registrar(v_tipo, null, r.os, v_d, '{}'::jsonb, v_alvo_v,
               public._agenda_cliente_fim_da_janela(v_vesp, 0), 'rodada', null, p_agora);
      if coalesce((v_r ->> 'criada')::boolean, false) then n_vesp := n_vesp + 1; end if;
    end if;
    -- CORREÇÃO FASE 5: (item 4) o erro desta OS: registrado e pulado
    exception when others then
      perform public._agenda_cliente_erro_da_os('confirmar', r.os, sqlstate, sqlerrm, p_hoje);
      n_erro := n_erro + 1;
    end;
    -- CORREÇÃO FASE 5: fim
  end loop;
  -- CORREÇÃO FASE 5: (item 4) as OS puladas por erro nas contagens
  return jsonb_build_object('confirmar', n_m1, 'vespera', n_vesp, 'unico', n_unico, 'vespera_pulada', n_pula,
                            'erros_os', n_erro);
  -- CORREÇÃO FASE 5: fim
  return jsonb_build_object('confirmar', n_m1, 'vespera', n_vesp, 'unico', n_unico, 'vespera_pulada', n_pula);
end;
$function$;
comment on function public._agenda_cliente_confirmar(date, timestamptz) is
  'Agenda de Produção (Fase 5, P3): o passo confirmar da rodada do cliente — a confirmação (M1) em D − cliente_confirmar_du dias úteis, a véspera (M2) ou o acesso (M4) no último dia de janela antes de D, ou um toque só; o M3/M7/M10/M6 remarcado do mesmo D substitui o M1. CORREÇÃO FASE 5 (C1, item 20): o M1 do D não sai quando o botão antigo já pediu a confirmação desse D (client_confirmation_requested_at dentro de cliente_resposta_validade, sem resposta, com _agenda_cliente_dia_a_confirmar no D) ou o cliente já confirmou o D (client_confirmed_for). Interna (sem grant). CORREÇÃO FASE 5 (C2, item 4): o erro de uma OS (o texto que não fecha, o proibido) vai a app_error_logs (agenda / cliente:confirmar:os) e o passo segue para as outras (erros_os). FASE 7f (P6): com as camadas ligadas de verdade, a OS em camada (_agenda_cliente_camada) tem o M1 a cliente_dia_exato_du dias de janela antes de D (1 = a véspera: o toque único). Fora disso, o de antes.';

create or replace function public._agenda_cliente_material(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c_recente_du constant int := 5;     -- spec §5.3: "ficou com todo crítico A há ≤ 5 du"
  r      record;
  v_pront jsonb;
  v_dia  date;
  v_tipo text;
  v_r    jsonb;
  n_reg  int := 0;
  n_ja   int := 0;
  -- CORREÇÃO FASE 5: (item 4) as OS puladas por erro
  n_erro int := 0;
  -- CORREÇÃO FASE 5: fim
  -- FASE 7f: (7f P6) o que ficou dentro da semana dita
  n_7f_dentro int := 0;
  -- FASE 7f: fim
begin
  for r in
    select k.service_order_id as os, k.status, p.prometido_tipo
      from public.os_carteira(p_hoje) k
      left join public.os_planejamento p on p.service_order_id = k.service_order_id
     where k.status not in ('awaiting_parts', 'awaiting_client', 'in_progress')
       and exists (select 1 from public.os_material om
                    where om.service_order_id = k.service_order_id and om.critico and om.situacao = 'na_mao'
                      and om.chegou_em >= public.agenda_somar_du(p_hoje, -c_recente_du))
     order by k.numero collate "C", k.service_order_id
  loop
    -- CORREÇÃO FASE 5: (item 4) cada OS no seu bloco: o erro de uma (o texto que não fecha, o proibido) vai a
    -- app_error_logs (agenda / cliente:material:os) e o passo segue para as outras
    begin
    -- CORREÇÃO FASE 5: fim
    v_pront := public.os_prontidao(r.os, p_hoje);
    continue when v_pront #>> '{material,estado}' is distinct from 'completo';
    v_dia := (public._agenda_plano_da_os(r.os, p_hoje) ->> 'proximo_dia')::date;
    continue when v_dia is null or v_dia <= p_hoje;
    -- estava esperando pelo material? (o prometido nulo não pode deixar a condição nula: aí o continue não pularia)
    continue when not (
      coalesce(r.prometido_tipo in ('condicional', 'faixa'), false)
      or exists (select 1 from public.agenda_cliente_mensagens m
                  where m.service_order_id = r.os and m.tipo = 'pode_atrasar' and m.enviada_em is not null)
      or exists (select 1 from public.agenda_acoes a
                  where a.service_order_id = r.os and a.tipo = 'status' and a.executada and a.desfeita_em is null
                    and a.status_antes = 'awaiting_parts' and a.dia >= public.agenda_somar_du(p_hoje, -c_recente_du)));
    -- o cliente já ouviu esse dia (a confirmação, a véspera): não repete
    if public._agenda_cliente_ouviu(r.os, v_dia, p_agora) then
      n_ja := n_ja + 1;
      continue;
    end if;
    -- FASE 7f: (7f P6, §5.6; o pedido do fio: dentro da semana dita, o M3 e o M7 não vão ao cliente) com as camadas ligadas de verdade, o cliente que ouviu a
    -- semana prevista (o prometido gravado pela mensagem semana enviada) e cujo dia novo cai dentro dela não ganha o "Podemos começar <dia>?": a semana dita
    -- fica, e o dia exato vai na véspera. Fora da semana dita (ou sem ela), o de sempre. O modo só é lido aqui (R8.8: o passo de sempre não lê nada novo)
    if public._agenda_fala_modo('camadas') = 'ligado' and exists (select 1 from public.os_planejamento p
                                  join public.agenda_cliente_mensagens m on m.id = p.prometido_mensagem_id and m.tipo = 'semana'
                                 where p.service_order_id = r.os and p.prometido_tipo in ('faixa', 'condicional')
                                   and v_dia between p.prometido_de and p.prometido_ate) then
      n_7f_dentro := n_7f_dentro + 1;
      continue;
    end if;
    -- FASE 7f: fim
    v_tipo := case when exists (select 1 from public.agenda_cliente_mensagens m
                                 where m.service_order_id = r.os and m.tipo = 'pode_atrasar' and m.enviada_em is not null)
                   then 'nova_data' else 'material_chegou' end;
    v_r := public._agenda_cliente_registrar(v_tipo, null, r.os, v_dia, '{}'::jsonb, p_agora,
             public._agenda_cliente_fim_da_janela((public._agenda_cliente_quando(0, p_agora, p_agora) at time zone 'America/Sao_Paulo')::date, 1),
             'rodada', null, p_agora);
    if coalesce((v_r ->> 'criada')::boolean, false) then n_reg := n_reg + 1; end if;
    -- CORREÇÃO FASE 5: (item 4) o erro desta OS: registrado e pulado
    exception when others then
      perform public._agenda_cliente_erro_da_os('material', r.os, sqlstate, sqlerrm, p_hoje);
      n_erro := n_erro + 1;
    end;
    -- CORREÇÃO FASE 5: fim
  end loop;
  -- FASE 7f: (7f P6) a contagem dentro_da_semana só quando a semana dita segurou algum M3/M7 (sem isso, a chave não existe: o de antes, byte a byte)
  if n_7f_dentro > 0 then
    return jsonb_build_object('registradas', n_reg, 'ja_ouviu', n_ja, 'erros_os', n_erro, 'dentro_da_semana', n_7f_dentro);
  end if;
  -- FASE 7f: fim
  -- CORREÇÃO FASE 5: (item 4) as OS puladas por erro nas contagens
  return jsonb_build_object('registradas', n_reg, 'ja_ouviu', n_ja, 'erros_os', n_erro);
  -- CORREÇÃO FASE 5: fim
  return jsonb_build_object('registradas', n_reg, 'ja_ouviu', n_ja);
end;
$function$;
comment on function public._agenda_cliente_material(date, timestamptz) is
  'Agenda de Produção (Fase 5, P3): o passo material da rodada do cliente — a OS cujo material crítico ficou todo na mão há pouco e que esperava por ele: a nova data (M7) se o aviso de atraso saiu, senão o material chegou (M3); não repete o dia que o cliente já ouviu. CORREÇÃO FASE 5 (C2): (item 1) "ouviu" em ligado é só o que saiu de verdade (_agenda_cliente_ouviu); (item 4) o erro de uma OS vai a app_error_logs (agenda / cliente:material:os) e o passo segue (erros_os). Interna (sem grant). FASE 7f (P6): com as camadas ligadas de verdade, o cliente que ouviu a semana prevista e cujo dia novo cai nela não ganha o M3/M7 com dia (contagem dentro_da_semana); fora dela, o de sempre.';

-- ── 6. A rodada do cliente ──────────────────────────────────────────────────────────────────────────
create or replace function public.agenda_cliente_vigiar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_passos  constant text[] := array['material', 'mudanca_no_dia', 'confirmar', 'atraso', 'andamento', 'pronto',
                                     -- FASE 7d: (7d P6, §5.6) o M11, DEPOIS da confirmação: o teto de 1 por dia recusa de vez quem chega por último, e quem cede é o M11
                                     'onde_fica',
                                     -- FASE 7d: fim
                                     -- FASE 7f: (7f P6, R8.5-22) a semana prevista (M12), DEPOIS do M11 e antes do pós-serviço: o teto de 1 por dia recusa quem chega
                                     -- por último, e a semana cede (ela tenta de novo no dia seguinte)
                                     'semana',
                                     -- FASE 7f: fim
                                     'pos_servico', 'sem_resposta'];
  cf        public.agenda_config;
  v_t0      timestamptz := clock_timestamp();
  v_passo   text;
  v_r       jsonb;
  v_cont    jsonb := '{}'::jsonb;
  v_erros   int := 0;
  v_falhas  jsonb := '[]'::jsonb;
  v_acordes jsonb := '[]'::jsonb;
  v_cota    int;
  v_estado  text;
  v_msg     text;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da rodada do cliente.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  cf := public._agenda_cfg();
  -- A fila do cliente roda SEMPRE, em qualquer modo (até desligado): o que ficou fora da janela, com o modo ou o tipo fora
  -- de ligado, ou que a revalidação recusa, não sai; o que é hora de mandar vai à fila; o que venceu sem o dono vence.
  begin
    v_cont := jsonb_build_object('fila', public._agenda_cliente_fila(p_hoje, p_agora));
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    v_erros := v_erros + 1;
    v_falhas := v_falhas || jsonb_build_object('passo', 'fila', 'sqlstate', v_estado, 'erro', left(v_msg, 300));
    perform public.log_app_error('db', 'mensagem ao cliente, passo fila: ' || v_msg, 'agenda', 'cliente:fila', 'error',
                                 jsonb_build_object('passo', 'fila', 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
  end;
  if cf.modo_cliente = 'desligado' then
    return jsonb_build_object('rodou', false, 'modo', cf.modo_cliente, 'fila', v_cont -> 'fila', 'erros', v_erros,
                              'falhas', v_falhas, 'acordes', '[]'::jsonb);
  end if;

  foreach v_passo in array c_passos loop
    -- FASE 7f: (7f P6, R8.8, R8.12-10) com as camadas desligadas, o passo semana nem é chamado: nada se lê e a chave não aparece (o de antes, byte a byte)
    -- (o cf que a rodada já leu: o freio só leva o ligado a teste, então desligado no cru é desligado no _agenda_fala_modo; nenhuma leitura nova)
    continue when v_passo = 'semana' and cf.modo_cliente_camadas = 'desligado';
    -- FASE 7f: fim
    begin
      execute format('select public.%I($1, $2)', '_agenda_cliente_' || v_passo) into v_r using p_hoje, p_agora;
      v_cont := v_cont || jsonb_build_object(v_passo, coalesce(v_r, '{}'::jsonb));
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_erros := v_erros + 1;
      v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
      perform public.log_app_error('db', format('mensagem ao cliente, passo %s: %s', v_passo, v_msg), 'agenda',
                                   'cliente:' || v_passo, 'error',
                                   jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje,
                                                      'p_agora', p_agora));
    end;
  end loop;

  -- Os acordes: como os da rotina — só com a vigia ligada e a ação executada, na cota acordes_dia_max do dia.
  if cf.modo_vigia = 'ligado' then
    v_cota := greatest(cf.acordes_dia_max - (select count(*)::int from public.agenda_acoes a
                                              where a.dia = p_hoje and a.contada_via = 'acorde'), 0);
    select coalesce(jsonb_agg(q.e order by q.ord), '[]'::jsonb) into v_acordes
      from (select jsonb_build_object('chave', 'agenda:' || a.id, 'assunto', 'cliente:' || a.service_order_id,
                                      'acao_id', a.id, 'os', a.service_order_id, 'perda_em', a.depois ->> 'perda_em',
                                      'texto', a.texto) as e,
                   row_number() over (order by (a.depois ->> 'perda_em')::date nulls last, a.criada_em, a.id) as ord
              from public.agenda_acoes a
             where a.tipo = 'cliente' and a.executada and a.contada_em is null
               and coalesce((a.depois ->> 'acorde')::boolean, false) and a.dia >= p_hoje - 1) q
     where q.ord <= v_cota;
  end if;

  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms,
                                           rotina, modo_equipe, modo_diaria)
  values (clock_timestamp(), p_hoje, p_agora, cf.modo_proposta, cf.modo_vigia,
          v_cont || jsonb_build_object('modo_cliente', cf.modo_cliente, 'tipos_ligados', to_jsonb(cf.cliente_tipos_ligados),
                                       'acordes', jsonb_array_length(v_acordes), 'falhas', v_falhas),
          least(v_erros, 32767), greatest(0, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int),
          'cliente', cf.modo_equipe, cf.modo_diaria);

  return jsonb_build_object('rodou', true, 'modo', cf.modo_cliente, 'tipos_ligados', to_jsonb(cf.cliente_tipos_ligados),
                            'contagens', v_cont, 'erros', v_erros, 'falhas', v_falhas, 'acordes', v_acordes);
end;
$function$;
comment on function public.agenda_cliente_vigiar(date, timestamptz) is
  'Agenda de Produção (Fase 5, P3): a rodada da mensagem ao cliente, a cada 15 min, pelo task-automations (depois da vigia, antes das regras). Antes de tudo, em qualquer modo, o passo fila (_agenda_cliente_fila). modo_cliente desligado = {rodou: false}. Passos, cada um no seu bloco (o que falha vai para app_error_logs, context agenda, action cliente:<passo>, e os outros rodam): material (o material chegou M3 / a nova data M7), mudanca_no_dia (M10, ou o acorde sem decisão), confirmar (a confirmação M1 em D − cliente_confirmar_du dias úteis, a véspera M2 ou o acesso M4 no último dia de janela antes de D, ou um toque só), atraso (o aviso M6 no 1º tique a partir de cliente_hora_preparo, ou na hora com o prometido a até cliente_atraso_na_hora_du dias úteis; nunca depois da data: cliente_aviso passou; 2º atraso e atraso longo = pergunta crítica), andamento (M5), pronto (M8 e o lembrete), pos_servico (M9), sem_resposta (a pergunta cliente_resposta). Tudo pelo _agenda_cliente_registrar (o modo, a aprovação dos primeiros dias, as travas). Uma linha em agenda_vigia_rodadas (rotina = cliente). {rodou, modo, tipos_ligados, contagens, erros, falhas, acordes} — os acordes só com a vigia ligada, na cota acordes_dia_max. Só service_role. FASE 7d (P6, §5.6): o passo onde_fica (M11), depois de pronto e antes de pos_servico: o teto de 1 por dia recusa de vez quem chega por último, e quem cede é o M11. FASE 7f (P6): o passo semana (_agenda_cliente_semana) depois do onde_fica e antes do pós-serviço; com as camadas desligadas ele não é chamado (a chave não aparece).';

-- ── 7. A resposta do cliente ────────────────────────────────────────────────────────────────────────
create or replace function public.agenda_resposta_do_cliente(p_phone text, p_body text, p_message_id uuid, p_tipo_msg text,
                                                             p_intencao text, p_expressao text,
                                                             p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf        public.agenda_config := public._agenda_cfg();
  c_pergunta_dias constant interval := interval '7 days';   -- spec §3.2: a cliente_resposta some em 7 dias
  -- os tipos que esperam resposta (spec §5.4); os que propõem um dia (o pedido de outro dia só vale neles)
  c_esperam constant text[] := array['confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia',
                                     -- FASE 7d: (7d P6, §5.6) o M11 espera resposta
                                     'onde_fica',
                                     -- FASE 7d: fim
                                     -- FASE 7f: (7f P6, §5.6) a semana prevista espera resposta ("Se algum dia dessa semana não der, me diga")
                                     'semana',
                                     -- FASE 7f: fim
                                     'pode_atrasar', 'pronto', 'pronto_lembrete', 'pos_servico'];
  c_do_dia  constant text[] := array['confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia'];
  v_hoje    date;
  v_modo    text;
  v_tipo    text;
  v_trecho  text;
  v_cli     uuid[];
  m         public.agenda_cliente_mensagens%rowtype;
  v_n       int;
  v_r       public.agenda_cliente_respostas%rowtype;
  v_rid     uuid := gen_random_uuid();
  v_int     text;
  v_expr    text;
  v_data    jsonb;
  v_nome    text;
  v_dia     date;
  v_ref     text;
  v_do_dia  boolean;
  v_efeito  text;
  v_o_que   text;
  v_texto   text;
  v_x       jsonb;
  v_acao    uuid;
  v_perg    uuid;
  v_acorde  boolean := false;
  v_de      date;
  v_ate     date;
  v_id      uuid;
  v_k       int := 0;
  v_estado  text;
  v_msg     text;
  -- CORREÇÃO FASE 5: a outra conversa (A1) e o PARAR que vale sempre (item 2)
  c_opt_out_dias constant interval := interval '30 days';   -- decisão da correção C1: o PARAR de quem recebeu da agenda em 30 dias
  v_outra   boolean := false;
  v_opt_cli uuid[];
  v_opt_msg uuid;
  v_opt_os  uuid;
  v_c       uuid;
  -- CORREÇÃO FASE 5: fim
  -- FASE 7d: (correção R3) a confirmação do dia pendente, atrás do M11
  v_7d_m1   public.agenda_cliente_mensagens%rowtype;
  -- FASE 7d: fim
begin
  if p_agora is null then
    return jsonb_build_object('consumiu', false);
  end if;
  -- desligado: nada lê (o webhook segue como sempre)
  if cf.modo_cliente = 'desligado' then
    return jsonb_build_object('consumiu', false, 'modo', 'desligado');
  end if;
  v_tipo := case when p_tipo_msg in ('text', 'audio', 'image', 'document', 'video') then p_tipo_msg else 'outro' end;
  v_trecho := nullif(left(btrim(coalesce(p_body, '')), 500), '');
  if v_tipo = 'text' and v_trecho is null then
    return jsonb_build_object('consumiu', false);
  end if;
  v_hoje := (p_agora at time zone 'America/Sao_Paulo')::date;
  v_modo := case when cf.modo_cliente = 'ligado' then 'ligado' else 'sombra' end;

  -- quem é (o dono, a equipe e quem recebe diária nunca são cliente)
  v_cli := public._agenda_clientes_do_telefone(p_phone, p_agora);
  if cardinality(v_cli) = 0 then
    return jsonb_build_object('consumiu', false);
  end if;
  -- a mesma mensagem dele de novo: nada muda
  if p_message_id is not null then
    select * into v_r from public.agenda_cliente_respostas r where r.whatsapp_message_id = p_message_id;
    if found then
      return jsonb_build_object('consumiu', v_r.modo = 'ligado', 'efeito', v_r.efeito, 'repetida', true, 'resposta_id', v_r.id);
    end if;
  end if;

  -- a que mensagem ele responde: a última da agenda mandada a ele (em teste, a que teria saído), dos tipos que esperam
  -- resposta, dentro de cliente_resposta_validade, ainda sem resposta. Sem ela, a agenda não lê: é conversa.
  select count(distinct x.service_order_id)::int into v_n
    from public.agenda_cliente_mensagens x
   where x.client_id = any (v_cli) and x.tipo = any (c_esperam)
     and ((x.modo = 'ligado' and x.estado in ('enviada', 'sem_resposta')
           and x.enviada_em <= p_agora and x.enviada_em > p_agora - cf.cliente_resposta_validade)
          or (v_modo = 'sombra' and x.modo = 'sombra' and x.estado = 'registrada'
              and x.enviar_em <= p_agora and x.enviar_em > p_agora - cf.cliente_resposta_validade));
  select x.* into m
    from public.agenda_cliente_mensagens x
   where x.client_id = any (v_cli) and x.tipo = any (c_esperam)
     and ((x.modo = 'ligado' and x.estado in ('enviada', 'sem_resposta')
           and x.enviada_em <= p_agora and x.enviada_em > p_agora - cf.cliente_resposta_validade)
          or (v_modo = 'sombra' and x.modo = 'sombra' and x.estado = 'registrada'
              and x.enviar_em <= p_agora and x.enviar_em > p_agora - cf.cliente_resposta_validade))
   order by coalesce(x.enviada_em, x.enviar_em) desc, x.criada_em desc, x.id
   limit 1;
  -- CORREÇÃO FASE 5: (A1 = item 11) a resposta só é da agenda quando a última mensagem que a HBR mandou a esse número é a
  -- dela: o botão antigo (o pedido de 30/09) ou o dono (ou outra rotina) falando com o cliente depois dela = a resposta é
  -- dessa outra conversa — devolve consumiu false (abaixo) e os leitores de antes (o "sim" de 30/09, a revisão) seguem.
  if m.id is not null then
    v_outra := public._agenda_cliente_outra_conversa(v_cli, p_phone, coalesce(m.enviada_em, m.enviar_em), p_agora);
  end if;
  -- (item 2) o PARAR (e os outros opt-outs) vale SEMPRE para quem recebeu mensagem da agenda nos últimos c_opt_out_dias —
  -- fora da validade, depois de outra resposta, com o número de dois clientes ou depois de outra conversa: o pós-serviço
  -- promete "é só responder PARAR". Marca o opt-out de cada cliente do número que recebeu, cancela as vivas dele, grava a
  -- resposta (efeito opt_out) e a ação; nada responde ao cliente.
  if v_modo = 'ligado' and v_tipo = 'text' and p_intencao = 'opt_out' and not public._e_concordancia(p_body)
     and (m.id is null or v_outra or v_n > 1 or cardinality(v_cli) > 1) then
    select coalesce(array_agg(distinct x.client_id), '{}'::uuid[]) into v_opt_cli
      from public.agenda_cliente_mensagens x
     where x.client_id = any (v_cli) and x.modo = 'ligado' and x.enviada_em is not null
       and x.enviada_em <= p_agora and x.enviada_em > p_agora - c_opt_out_dias;
    if cardinality(v_opt_cli) > 0 then
      select x.id, x.service_order_id into v_opt_msg, v_opt_os
        from public.agenda_cliente_mensagens x
       where x.client_id = any (v_opt_cli) and x.modo = 'ligado' and x.enviada_em is not null and x.enviada_em <= p_agora
       order by x.enviada_em desc, x.id limit 1;
      insert into public.agenda_cliente_respostas (id, client_id, service_order_id, mensagem_id, whatsapp_message_id, recebida_em,
                                                   tipo_msg, texto, intencao, expressao, data_dita, efeito, modo)
      values (v_rid, v_opt_cli[1], v_opt_os, v_opt_msg, p_message_id, p_agora, v_tipo, v_trecho, 'opt_out', null, null,
              'opt_out', 'ligado')
      on conflict (whatsapp_message_id) do nothing;
      if not found then
        return jsonb_build_object('consumiu', true, 'repetida', true);
      end if;
      foreach v_c in array v_opt_cli loop
        update public.clients set opt_out_whatsapp = true where id = v_c and not coalesce(opt_out_whatsapp, false);
        for v_id in select x.id from public.agenda_cliente_mensagens x
                     where x.client_id = v_c and x.estado in ('registrada', 'aguardando_dono', 'enfileirada')
                     order by x.enviar_em, x.id loop
          if public._agenda_cliente_cancelar(v_id, 'opt_out', 'O cliente pediu para não receber mensagens.') then
            v_k := v_k + 1;
          end if;
        end loop;
      end loop;
      v_nome := coalesce((select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name))
                            from public.clients cl where cl.id = v_opt_cli[1]), 'cliente');
      v_texto := format('O %s pediu para não receber mais mensagens: não mando mais nada a ele.', v_nome);
      -- FASE 6: (P7) a ação do opt-out sem artigo antes do nome e sem "a ele" (spec-fase6 §6.4)
      v_texto := format('%s pediu para não receber mais mensagens: não mando mais nada.', v_nome);
      -- FASE 6: fim
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto, motivo)
      values (clock_timestamp(), v_hoje, true, 'cliente', 'cliente', v_opt_os, array[v_opt_os], '{}'::jsonb,
              jsonb_build_object('efeito', 'opt_out', 'resposta_id', v_rid, 'mensagem_id', v_opt_msg, 'canceladas', v_k,
                                 'clientes', to_jsonb(v_opt_cli), 'fora_da_mensagem', true),
              v_texto, 'o cliente pediu para parar')
      returning id into v_acao;
      update public.agenda_cliente_respostas set acao_id = v_acao where id = v_rid;
      return jsonb_build_object('consumiu', true, 'modo', 'ligado', 'efeito', 'opt_out', 'intencao', 'opt_out', 'texto', v_texto,
                                'resposta_id', v_rid, 'mensagem_id', v_opt_msg, 'acao_id', v_acao, 'pergunta_id', null);
    end if;
  end if;
  -- CORREÇÃO FASE 5: fim
  if m.id is null then
    return jsonb_build_object('consumiu', false, 'motivo', 'sem_mensagem');
  end if;
  -- CORREÇÃO FASE 5: (A1) a outra conversa depois da mensagem da agenda: não é resposta a ela (em teste também: a sombra
  -- não registra o que a agenda não leria)
  if v_outra then
    return jsonb_build_object('consumiu', false, 'modo', v_modo, 'motivo', 'outra_conversa', 'mensagem_id', m.id);
  end if;
  -- CORREÇÃO FASE 5: fim

  -- a intenção: o áudio e a mídia antes de tudo (nunca confirmam); o SIM curto pela regra única de 30/09; o resto como o
  -- leitor do webhook classificou (sem IA)
  v_int := case when v_tipo = 'audio' then 'audio'
                when v_tipo <> 'text' then 'outro'
                when public._e_concordancia(p_body) then 'confirma'
                when p_intencao in ('remarcar', 'falta', 'data', 'acesso', 'opt_out', 'disputa', 'negociacao', 'pergunta',
                                    'acordo', 'outro') then p_intencao
                else 'outro' end;
  -- FASE 7d: (correção R3) o "sim" atrasado do M1: com o M11 mais novo e a confirmação do dia da mesma OS pendente, o SIM é do dia, não do onde fica. A régua de quem espera é a de cima
  if m.tipo = 'onde_fica' and v_int = 'confirma' then
    select x.* into v_7d_m1
      from public.agenda_cliente_mensagens x
     where x.service_order_id = m.service_order_id and x.id <> m.id
       and (x.tipo in ('confirmar', 'material_chegou', 'nova_data', 'mudanca_no_dia') or (x.tipo = 'pode_atrasar' and x.variante = 'remarcado'))
       and ((x.modo = 'ligado' and x.estado in ('enviada', 'sem_resposta')
             and x.enviada_em <= p_agora and x.enviada_em > p_agora - cf.cliente_resposta_validade)
            or (v_modo = 'sombra' and x.modo = 'sombra' and x.estado = 'registrada'
                and x.enviar_em <= p_agora and x.enviar_em > p_agora - cf.cliente_resposta_validade))
     order by coalesce(x.enviada_em, x.enviar_em) desc, x.criada_em desc, x.id
     limit 1;
    if v_7d_m1.id is not null then
      m := v_7d_m1;
    end if;
  end if;
  -- FASE 7d: fim
  v_expr := case when v_int in ('data', 'remarcar', 'falta') then nullif(left(btrim(coalesce(p_expressao, '')), 60), '') end;
  v_dia := coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo);
  v_data := case when v_expr is not null then public._agenda_cliente_data_da_resposta(v_expr, v_hoje, v_dia) end;
  v_nome := coalesce((select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name))
                        from public.clients cl where cl.id = m.client_id), 'cliente');
  v_ref := public._agenda_cliente_a_mensagem(m.tipo, m.variante, v_dia);
  v_do_dia := m.tipo = any (c_do_dia) or (m.tipo = 'pode_atrasar' and m.variante = 'remarcado');

  -- em teste: só registra o que faria (a intenção); nada muda e os fluxos de hoje seguem iguais
  if v_modo = 'sombra' then
    insert into public.agenda_cliente_respostas (id, client_id, service_order_id, mensagem_id, whatsapp_message_id, recebida_em,
                                                 tipo_msg, texto, intencao, expressao, data_dita, efeito, modo)
    values (v_rid, m.client_id, m.service_order_id, m.id, p_message_id, p_agora, v_tipo, v_trecho, v_int, v_expr,
            (v_data ->> 'de')::date, 'sombra', 'sombra')
    on conflict (whatsapp_message_id) do nothing;
    return jsonb_build_object('consumiu', false, 'modo', 'sombra', 'efeito', 'sombra', 'intencao', v_int, 'resposta_id', v_rid);
  end if;

  -- ligado: a resposta fica registrada primeiro (uma por mensagem do WhatsApp); o efeito vem depois
  insert into public.agenda_cliente_respostas (id, client_id, service_order_id, mensagem_id, whatsapp_message_id, recebida_em,
                                               tipo_msg, texto, intencao, expressao, data_dita, efeito, modo)
  values (v_rid, m.client_id, m.service_order_id, case when v_n > 1 or cardinality(v_cli) > 1 then null else m.id end,
          p_message_id, p_agora, v_tipo, v_trecho, v_int, v_expr, (v_data ->> 'de')::date, 'nada', 'ligado')
  on conflict (whatsapp_message_id) do nothing;
  if not found then
    return jsonb_build_object('consumiu', true, 'repetida', true);
  end if;
  perform set_config('agenda.hoje', v_hoje::text, true);

  begin
    if v_n > 1 or cardinality(v_cli) > 1 then
      -- duas OS (ou dois clientes no número) esperando: não adivinha
      v_efeito := 'ambigua';
      v_texto := format('Chegou "%s" do número do %s, mas %s: não sei a qual mensagem é. Não respondi nada; é com você.',
                        public._agenda_corta(coalesce(v_trecho, 'uma mensagem que não é texto'), 120), v_nome,
                        case when cardinality(v_cli) > 1 then format('o número é de %s clientes', cardinality(v_cli))
                             else format('há %s serviços esperando resposta dele', v_n) end);
      -- FASE 6: (P7) sem artigo antes do nome e sem "dele" (spec-fase6 §6.4), escrito já assim: com dois clientes no número, a
      -- OS da mensagem pode ser do outro, e o ralo (que troca só o 1º nome do cliente da OS) não acharia este
      v_texto := format('Chegou "%s" do número de %s, mas %s: não sei a qual mensagem é. Não respondi nada; é com você.',
                        public._agenda_corta(coalesce(v_trecho, 'uma mensagem que não é texto'), 120), v_nome,
                        case when cardinality(v_cli) > 1 then format('o número é de %s clientes', cardinality(v_cli))
                             else format('há %s serviços esperando resposta do cliente', v_n) end);
      -- FASE 6: fim
    elsif v_int = 'audio' then
      -- o áudio NUNCA confirma: vai ao dono
      v_efeito := 'ao_dono';
      v_texto := format('O %s respondeu por áudio %s; a transcrição está na conversa. Não respondi nada; é com você.', v_nome, v_ref);
    elsif v_tipo <> 'text' then
      v_efeito := 'ao_dono';
      v_texto := format('O %s respondeu com %s %s. Não respondi nada; é com você.', v_nome,
                        case v_tipo when 'image' then 'uma foto' when 'video' then 'um vídeo' when 'document' then 'um documento'
                                    else 'uma mensagem que não é texto' end, v_ref);
    -- FASE 7d: (7d P6; §5.6, R6.3-5) a resposta ao M11: anota, pergunta ao dono e NÃO conta como acesso combinado. O áudio e a mídia já foram ao dono, acima;
    -- o PARAR, a reclamação e a negociação seguem o caminho de sempre, abaixo.
    -- (correção R3, R4) o acordo entra no mesmo leitor do texto inteiro ("Sim, na Marina Itajaí"). Sem sinal de lugar, _agenda_cliente_anotar_onde não anota nada: a resposta vai ao dono como
    -- resposta comum. O acordo e a pergunta sem lugar seguem os textos de sempre, abaixo.
    elsif m.tipo = 'onde_fica' and v_int not in ('opt_out', 'disputa', 'negociacao')
          and (v_int not in ('acordo', 'pergunta')
               or coalesce((public._agenda_local_proposto(m.service_order_id, v_trecho, v_hoje) ->> 'sinal')::boolean, false)) then
      v_x := public._agenda_cliente_anotar_onde(m.id, v_rid, v_trecho, v_hoje, p_agora);
      if coalesce((v_x ->> 'ok')::boolean, false) then
        v_efeito := 'anotou_acesso';
        v_acao := (v_x ->> 'acao_id')::uuid;
        v_perg := (v_x ->> 'pergunta_id')::uuid;
        v_texto := v_x ->> 'texto';
      else
        v_efeito := 'ao_dono';
        v_o_que := v_x ->> 'o_que';
        v_texto := v_x ->> 'texto';
      end if;
    -- FASE 7d: fim
    elsif v_int = 'confirma' then
      if m.tipo in ('confirmar', 'material_chegou', 'nova_data', 'mudanca_no_dia')
         or (m.tipo = 'pode_atrasar' and m.variante = 'remarcado') then
        -- (decisão do P4) o SIM ao aviso remarcado confirma o dia novo, como o M1: o texto dele pede "Responda SIM"
        v_x := public._agenda_cliente_confirmar_dia(m.id, v_rid, v_trecho, v_hoje, p_agora);
        if coalesce((v_x ->> 'ok')::boolean, false) then
          v_efeito := 'confirmou';
          v_acao := (v_x ->> 'acao_id')::uuid;
          v_texto := v_x ->> 'texto';
        else
          v_efeito := 'ao_dono';
          v_o_que := v_x ->> 'o_que';
        end if;
      elsif m.tipo in ('vespera', 'acesso') then
        v_efeito := 'confirmou';   -- só registra (o client_confirmed_* é do SIM ao M1/M3/M7/M10)
      -- FASE 7f: (7f P6, §5.6, NOVO-agenda-77) o SIM à semana prevista é ciência: não confirma dia nenhum (o dia exato vai na véspera). O resto da resposta à
      -- semana segue o caminho de hoje das mensagens que não propõem dia (ao dono)
      elsif m.tipo = 'semana' then
        v_efeito := 'ciencia';
      -- FASE 7f: fim
      elsif m.tipo = 'pode_atrasar' then
        v_efeito := 'ciencia';
      elsif m.tipo in ('pronto', 'pronto_lembrete') then
        v_efeito := 'ao_dono';
        v_o_que := 'combine a entrega com ele';
      else
        v_efeito := 'nada';
      end if;
    elsif v_int = 'opt_out' then
      -- honrado calado (d8): nada mais sai a ele; o dono fica sabendo pela ação
      update public.clients set opt_out_whatsapp = true where id = m.client_id and not coalesce(opt_out_whatsapp, false);
      for v_id in select x.id from public.agenda_cliente_mensagens x
                   where x.client_id = m.client_id and x.estado in ('registrada', 'aguardando_dono', 'enfileirada')
                   order by x.enviar_em, x.id loop
        if public._agenda_cliente_cancelar(v_id, 'opt_out', 'O cliente pediu para não receber mensagens.') then
          v_k := v_k + 1;
        end if;
      end loop;
      v_efeito := 'opt_out';
      v_texto := format('O %s pediu para não receber mais mensagens: não mando mais nada a ele.', v_nome);
      -- FASE 6: (P7) a ação do opt-out sem artigo antes do nome e sem "a ele" (spec-fase6 §6.4)
      v_texto := format('%s pediu para não receber mais mensagens: não mando mais nada.', v_nome);
      -- FASE 6: fim
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto, motivo)
      values (clock_timestamp(), v_hoje, true, 'cliente', 'cliente', m.service_order_id, array[m.service_order_id], '{}'::jsonb,
              jsonb_build_object('efeito', 'opt_out', 'resposta_id', v_rid, 'mensagem_id', m.id, 'canceladas', v_k),
              v_texto, 'o cliente pediu para parar')
      returning id into v_acao;
    elsif v_int in ('disputa', 'negociacao', 'acordo', 'pergunta') then
      v_efeito := 'ao_dono';
      v_acorde := v_int = 'disputa';   -- a reclamação vai na hora
      v_o_que := case v_int when 'disputa' then 'parece reclamação'
                            when 'negociacao' then 'é sobre preço ou pagamento'
                            when 'acordo' then 'parece que concorda, mas não é um SIM claro'
                            else 'é uma pergunta' end;
    elsif v_int in ('data', 'remarcar', 'falta') and not v_do_dia then
      v_efeito := 'ao_dono';
      v_o_que := case when m.tipo in ('pronto', 'pronto_lembrete') then 'falou de dia: combine a entrega com ele'
                      else 'falou de outro dia' end;
    elsif v_int in ('data', 'remarcar', 'falta') and cf.modo_proposta <> 'ligado' then
      v_efeito := 'ao_dono';
      v_o_que := 'pediu outro dia, mas a agenda automática não está ligada: remarque você';
    elsif v_int = 'data' then
      v_de := (v_data ->> 'de')::date;
      v_ate := (v_data ->> 'ate')::date;
      if v_de is null then
        v_efeito := 'ao_dono';
        v_o_que := 'não entendi o dia que ele pediu';
      elsif v_de <= v_hoje then
        v_efeito := 'ao_dono';
        v_o_que := 'o dia que ele pediu já passou ou é hoje';
      elsif v_dia is not null and v_de = v_dia then
        v_efeito := 'ao_dono';
        v_o_que := 'falou do mesmo dia combinado';
      elsif v_dia is not null and v_de < v_dia then
        -- (decisão do P4) mais cedo que o combinado: o "não antes de" não adianta nada; é o dono que vê se dá
        v_efeito := 'ao_dono';
        v_o_que := format('pediu um dia antes do combinado (%s)', public._dia_curto(v_de));
      -- CORREÇÃO FASE 5: (item 9) o dia pedido longe demais do combinado (mais de cliente_pedido_max_du dias úteis) não
      -- remarca sozinho: é o dono que vê
      elsif public.agenda_du_entre(coalesce(v_dia, v_hoje), v_de) > cf.cliente_pedido_max_du then
        v_efeito := 'ao_dono';
        v_o_que := format('pediu %s, mais de %s dias úteis depois do combinado: remarque você', public._dia_curto(v_de),
                          cf.cliente_pedido_max_du);
      -- CORREÇÃO FASE 5: fim
      else
        v_x := public._agenda_cliente_pedido_de_dia(m.id, v_rid,
                 case when v_dia is not null then daterange(v_dia, v_dia, '[]') end, v_de,
                 format('O %s pediu %s', v_nome,
                        case when v_ate > v_de then 'a partir de ' || public._dia_curto(v_de) else public._dia_curto(v_de) end),
                 v_trecho, v_hoje, p_agora);
        v_efeito := 'replanejou';
        v_acao := (v_x ->> 'acao_id')::uuid;
        v_texto := v_x ->> 'texto';
      end if;
    -- CORREÇÃO FASE 5: (item 17) falta/remarcar com um número de dia que o banco não entendeu ("tô viajando, volto dia 20",
    -- "só depois de 20/11"): tirar só o dia combinado remarcaria para quando ele ainda está fora — vai ao dono
    elsif v_int in ('remarcar', 'falta') and v_data is null
          and public._agenda_preparar_data(coalesce(v_trecho, '')) ~ '(\mdia \d{1,2}\M|\m\d{1,2}/\d{1,2})' then
      v_efeito := 'ao_dono';
      v_o_que := 'falou de outro dia, que eu não entendi';
    -- CORREÇÃO FASE 5: fim
    elsif v_int in ('remarcar', 'falta') then
      -- o dia recusado: o que ele disse (convertido pelo banco), senão o dia da mensagem
      v_de := (v_data ->> 'de')::date;
      v_ate := (v_data ->> 'ate')::date;
      if v_de is null or v_ate < v_hoje then
        v_de := v_dia;
        v_ate := v_dia;
      end if;
      v_de := greatest(v_de, v_hoje);
      if v_de is null or v_ate < v_de then
        v_efeito := 'ao_dono';
        v_o_que := 'pediu outro dia';
      elsif not (v_dia between v_de and v_ate)
            and not exists (select 1 from public.agenda_alocacoes a
                             where a.service_order_id = m.service_order_id and a.estado in ('publicada', 'fixada')
                               and a.tipo <> 'reserva' and a.dia between v_de and v_ate) then
        -- (decisão do P4) o dia recusado não é dia do serviço ("não dá amanhã" no sábado, com o serviço na terça): não
        -- adivinho de qual dia ele fala
        v_efeito := 'ao_dono';
        v_o_que := format('disse que não dá %s, mas não é dia do serviço',
                          case when v_ate > v_de then public._dia_curto(v_de) || ' a ' || public._dia_curto(v_ate)
                               else public._dia_curto(v_de) end);
      -- CORREÇÃO FASE 5: (item 9) tirar dias até longe demais do combinado ("vou viajar até 20/12") também não remarca sozinho
      elsif public.agenda_du_entre(coalesce(v_dia, v_hoje), v_ate) > cf.cliente_pedido_max_du then
        v_efeito := 'ao_dono';
        v_o_que := format('disse que não dá até %s, mais de %s dias úteis depois do combinado: remarque você',
                          public._dia_curto(v_ate), cf.cliente_pedido_max_du);
      -- CORREÇÃO FASE 5: fim
      else
        v_x := public._agenda_cliente_pedido_de_dia(m.id, v_rid, daterange(v_de, v_ate, '[]'), null,
                 format('O %s pediu outro dia (%s não dá)', v_nome,
                        case when v_ate > v_de then public._dia_curto(v_de) || ' a ' || public._dia_curto(v_ate)
                             else public._dia_curto(v_de) end),
                 v_trecho, v_hoje, p_agora);
        v_efeito := 'replanejou';
        v_acao := (v_x ->> 'acao_id')::uuid;
        v_texto := v_x ->> 'texto';
      end if;
    -- CORREÇÃO FASE 5: (item 16) o acesso com negação ("não sei onde vai estar a chave", "não tenho a chave", "ainda não
    -- sei") não é acesso dito: não vai para o campo da OS nem desliga a pergunta do acesso — vai ao dono
    elsif v_int = 'acesso' and public._agenda_normal(coalesce(v_trecho, '')) ~ '\m(nao sei|nao tenho|ainda nao)\M' then
      v_efeito := 'ao_dono';
      v_o_que := 'falou do acesso, mas ainda não sabe (ou não tem) a chave';
    -- CORREÇÃO FASE 5: fim
    elsif v_int = 'acesso' and (v_do_dia or m.tipo = 'pode_atrasar') then
      v_x := public._agenda_cliente_anotar_acesso(m.id, v_rid, v_trecho, v_hoje, p_agora);
      v_efeito := 'anotou_acesso';
      v_acao := (v_x ->> 'acao_id')::uuid;
      v_texto := v_x ->> 'texto';
    else
      v_efeito := 'ao_dono';
      v_o_que := case when v_int = 'acesso' then 'falou do acesso' else 'não entendi o que ele quer' end;
    end if;
  exception when others then
    -- o efeito que falha não derruba o webhook: a resposta vai ao dono e o erro fica consultável
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    perform public.log_app_error('db', 'agenda: a resposta do cliente falhou: ' || v_msg, 'agenda', 'cliente:resposta', 'error',
                                 jsonb_build_object('mensagem', m.id, 'resposta', v_rid, 'intencao', v_int, 'sqlstate', v_estado));
    v_efeito := 'ao_dono';
    v_acao := null;
    v_acorde := false;
    v_o_que := 'não consegui ler a resposta sozinho';
    v_texto := null;
  end;

  -- ao dono: a pergunta cliente_resposta (sem opções; some em 7 dias), e o acorde na hora quando é reclamação
  if v_efeito in ('ao_dono', 'ambigua') then
    v_texto := coalesce(v_texto, format('O %s respondeu "%s" %s: %s. Não respondi nada; é com você.', v_nome,
                                        public._agenda_corta(coalesce(v_trecho, ''), 120), v_ref, v_o_que));
    v_perg := public._agenda_cliente_perguntar('cliente_resposta', 'cliente_resposta:' || v_rid, m.service_order_id, v_dia,
                                               case when v_do_dia then v_dia end, v_texto, 'ligado', p_agora,
                                               p_agora + c_pergunta_dias);
    if v_acorde then
      v_acao := public._agenda_cliente_acorde(m.service_order_id, 'cliente_resposta:' || v_rid, v_texto, v_hoje, v_hoje, v_perg);
    end if;
  end if;

  -- a mensagem respondida (antes das 48 h o "não respondeu" não a pega; depois, a pergunta dele se resolve)
  if v_efeito <> 'ambigua' then
    update public.agenda_cliente_mensagens set estado = 'respondida', resposta_id = v_rid
     where id = m.id and estado in ('enviada', 'sem_resposta');
    -- FASE 6: (P7) o motivo sem artigo antes do nome; o update de antes, logo abaixo, não acha mais a pergunta aberta
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = left(format('%s respondeu.', v_nome), 200)
     where chave = 'cliente_resposta:sem_resposta:' || m.id and estado = 'aberta';
    -- FASE 6: fim
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = left(format('O %s respondeu.', v_nome), 200)
     where chave = 'cliente_resposta:sem_resposta:' || m.id and estado = 'aberta';
  end if;
  update public.agenda_cliente_respostas
     set efeito = v_efeito, acao_id = v_acao, pergunta_id = v_perg, data_dita = coalesce((v_data ->> 'de')::date, data_dita)
   where id = v_rid;
  -- CORREÇÃO FASE 5: (item 15) o texto devolvido, quando é o da pergunta ao dono, sem artigo antes do nome ("Flávio
  -- respondeu …"), igual à pergunta; o das ações (confirmou, pediu, opt-out) fica como a ação gravada
  if v_efeito in ('ao_dono', 'ambigua') then
    v_texto := public._agenda_cliente_sem_artigo(v_texto, m.service_order_id);
  end if;
  -- CORREÇÃO FASE 5: fim
  return jsonb_build_object('consumiu', true, 'modo', 'ligado', 'efeito', v_efeito, 'intencao', v_int, 'texto', v_texto,
                            'resposta_id', v_rid, 'mensagem_id', m.id, 'acao_id', v_acao, 'pergunta_id', v_perg);
end;
$function$;
comment on function public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamptz) is
  'Agenda de Produção (Fase 5, P4): a mensagem do cliente que chega pelo WhatsApp (o webhook chama depois da equipe e antes da confirmação de 30/09 e da conferência do recibo: o "ok" tem um dono só). modo_cliente desligado, número de ninguém (ou do dono, da equipe, de quem recebe diária), a mesma mensagem de novo ou sem mensagem da agenda esperando resposta (a última dos tipos que esperam, enviada dentro de cliente_resposta_validade e ainda sem resposta; em teste, a que teria saído) = consumiu false. Em teste: registra a resposta (efeito sombra, com a intenção) e consumiu false. Ligado, a 1ª que vale: duas OS ou dois clientes no número = ambígua (ao dono); áudio e mídia ao dono (o áudio NUNCA confirma); o SIM curto (_e_concordancia) confirma o M1/M3/M7/M10 e o M6 remarcado (_agenda_cliente_confirmar_dia: fixa o dia, com *desfaz*), registra a véspera e o acesso, é ciência no aviso de atraso, vai ao dono no "ficou pronto" e não faz nada no pós-serviço; opt-out = as vivas recusadas (opt_out) e o cadastro marcado, calado; reclamação (na hora, por acorde), negociação, acordo e pergunta ao dono; o dia pedido (data) e o recusado (remarcar, falta) — só nas mensagens que propõem um dia e com modo_proposta ligado — viram o "não antes de" e o bem indisponível com o replano (_agenda_cliente_pedido_de_dia, com *desfaz*; o dia combinado em até 1 dia útil = acorde); o dia passado, de hoje, o mesmo ou mais cedo que o combinado vai ao dono; o acesso dito vai para o campo da OS (_agenda_cliente_anotar_acesso, com *desfaz*); o resto ao dono. Ao dono = a pergunta cliente_resposta:<resposta> (some em 7 dias). A mensagem fica respondida (resposta_id) e a pergunta do "não respondeu" dela se resolve. O efeito que falha vai ao dono e a app_error_logs (cliente:resposta). {consumiu, modo, efeito, intencao, texto, resposta_id, mensagem_id, acao_id, pergunta_id}. Só service_role. CORREÇÃO FASE 5 (C1): (A1) a resposta só é da agenda quando a última mensagem da HBR ao número é a dela — o botão antigo ou outra mensagem outbound depois dela (_agenda_cliente_outra_conversa) = {consumiu:false, motivo:outra_conversa}, em teste também; (item 2) o opt-out vale para quem recebeu mensagem da agenda em 30 dias, mesmo sem mensagem esperando, depois de outra conversa ou com o número ambíguo (efeito opt_out, consumiu true); (item 16) o acesso com negação vai ao dono; (item 17) falta/remarcar com um número de dia não entendido vai ao dono; (item 9) o dia pedido ou o fim do recusado a mais de cliente_pedido_max_du dias úteis do combinado vai ao dono. CORREÇÃO FASE 5 (C2, item 15): o texto devolvido (o da pergunta cliente_resposta ao dono) sem artigo antes do nome. FASE 6 (P7, spec-fase6 §6.4): a ação do opt-out sem artigo e sem "a ele" ("Nelson pediu para não receber mais mensagens: não mando mais nada."), a ambígua escrita já sem artigo ("Chegou "ok" do número de Kalmar, mas há 2 serviços esperando resposta do cliente: …"), o motivo da pergunta do "não respondeu" ("Nelson respondeu."); a pergunta ao dono sai sem "ele" pelo ralo ("não entendi o pedido", "o dia pedido já passou ou é hoje", "combine a entrega com o cliente"); as ações do SIM, do dia pedido e do acesso vêm sem artigo das funções delas. FASE 7d (P6; §5.6, R6.3-5): o M11 onde_fica espera resposta; a resposta de texto que não é PARAR, reclamação, negociação nem acordo vai a _agenda_cliente_anotar_onde (efeito anotou_acesso, a pergunta local ao dono), e NÃO conta como acesso combinado: acesso_ok_em não muda. FASE 7f (P6): a semana espera resposta; o SIM a ela é ciência (não confirma dia nenhum); o resto como as mensagens que não propõem dia (ao dono).';

-- ── 8. As listas dos tipos: o foco, o preparar e a saúde ────────────────────────────────────────────
create or replace function public._agenda_ver_clientes(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  v_uid    uuid := (select auth.uid());
  cf       public.agenda_config;
  v_agora  timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  v_amanha date;
  v_l      text[] := '{}';
  v_c      text[] := '{}';
  v_ef     text[] := '{}';
  v_es     text[] := '{}';
  v_t      text[];
  k        int;
  v_b      text[];
  r        record;
  x        jsonb;
  v_cab    text;
  v_n      jsonb := '{}'::jsonb;
  v_tipos  text[];
  v_prom   text;
  v_conf   timestamptz;
  c_tipos  constant text[] := array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar',
                                    -- FASE 7d: (7d P6, §5.6) o M11
                                    'onde_fica',
                                    -- FASE 7d: fim
                                    'nova_data', 'pronto', 'pronto_lembrete', 'pos_servico', 'mudanca_no_dia'];
begin
  if p_hoje is null then
    raise exception '_agenda_ver_clientes: sem o dia de hoje' using errcode = '22004';
  end if;
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
  end if;
  cf := public._agenda_cfg();
  if cf.modo_cliente = 'desligado' then
    return jsonb_build_object('ok', true, 'texto', 'As mensagens ao cliente estão desligadas: a agenda não fala com cliente.',
                              'dados', jsonb_build_object('modo', cf.modo_cliente));
  end if;
  v_amanha := public._agenda_cliente_dia_seguinte(p_hoje);

  -- o cabeçalho (e, com a OS, o que foi dito e a confirmação)
  if p_os is not null then
    select so.service_order_number as numero, so.client_confirmed_for,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome,
           pl.prometido_tipo, pl.prometido_de, pl.prometido_ate, pl.prometido_fonte, pl.prometido_em
      into r
      from public.service_orders so
      left join public.clients cl on cl.id = so.client_id
      left join public.os_planejamento pl on pl.service_order_id = so.id
     where so.id = p_os;
    v_cab := format('Mensagens ao cliente — %s (%s)%s:', coalesce(r.nome, 'cliente'), r.numero,
                    case when cf.modo_cliente = 'sombra' then ', em teste' else '' end);
    v_prom := case
      when r.prometido_ate is null then 'O que foi dito a ele: nada ainda.'
      else format('O que foi dito a ele: %s (%s, %s%s).',
                  case when coalesce(r.prometido_de, r.prometido_ate) = r.prometido_ate then public._dia_curto(r.prometido_ate)
                       else format('de %s a %s', public._dia_curto(r.prometido_de), public._dia_curto(r.prometido_ate)) end,
                  case r.prometido_tipo when 'firme' then 'data firme' when 'faixa' then 'uma faixa' else 'condicional' end,
                  case r.prometido_fonte when 'mensagem' then 'por mensagem da agenda' when 'dono' then 'por você'
                                         else 'pela confirmação' end,
                  coalesce(' em ' || public._dia_curto((r.prometido_em at time zone 'America/Sao_Paulo')::date), '')) end;
    -- FASE 6: (P7) sem "ele" (spec-fase6 §6.4): "O que foi dito ao cliente: …" (pelo ralo do texto ao dono)
    v_prom := public._agenda_cliente_sem_artigo(v_prom, p_os);
    -- FASE 6: fim
    v_l := array[v_cab, v_prom];
    if r.client_confirmed_for is not null then
      v_l := v_l || format('Ele confirmou %s.', public._dia_curto((r.client_confirmed_for at time zone 'America/Sao_Paulo')::date));
      -- FASE 6: (P7) sem "ele" (spec-fase6 §6.4)
      v_l[cardinality(v_l)] := format('O cliente confirmou %s.',
                                      public._dia_curto((r.client_confirmed_for at time zone 'America/Sao_Paulo')::date));
      -- FASE 6: fim
    end if;
  else
    v_l := array[case when cf.modo_cliente = 'sombra' then 'Mensagens ao cliente (em teste: nada sai ainda):'
                      else 'Mensagens ao cliente:' end];
  end if;

  -- (1) Esperando você: a mensagem que espera *manda cliente* (inteira), o aviso de atraso que é decisão, a data dita que
  -- passou sem aviso e a resposta que foi ao dono
  -- (o "não respondeu" fica no bloco Sem resposta). A mensagem vai inteira; se o texto passar de texto_max, as da 2ª em
  -- diante encurtam (v_es) antes de qualquer linha sair.
  for r in
    select m.tipo, m.texto, m.enviar_em, m.aprovacao, q.texto as pergunta,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome
      from public.agenda_cliente_mensagens m
      join public.clients cl on cl.id = m.client_id
      left join public.agenda_perguntas q on q.id = m.pergunta_id
     where m.modo = 'ligado' and m.estado = 'aguardando_dono' and m.aprovacao in ('pedida', 'critica')
       and (p_os is null or m.service_order_id = p_os)
     order by m.enviar_em, cl.name, m.tipo, m.id
  loop
    if r.aprovacao = 'critica' then
      v_ef := v_ef || format('• Decisão: %s', coalesce(r.pergunta, 'o aviso de atraso do ' || r.nome || ' espera você (1, 2 ou 3).'));
      v_es := v_es || format('• Decisão: %s', coalesce(r.pergunta, 'o aviso de atraso do ' || r.nome || ' espera você (1, 2 ou 3).'));
      -- FASE 6: (P7) sem artigo antes do nome (o texto de quando a pergunta já não existe)
      v_ef[cardinality(v_ef)] := format('• Decisão: %s', coalesce(r.pergunta, 'o aviso de atraso de ' || r.nome || ' espera você (1, 2 ou 3).'));
      v_es[cardinality(v_es)] := v_ef[cardinality(v_ef)];
      -- FASE 6: fim
    else
      v_ef := v_ef || format('• %s (%s), sai %s: "%s" — *manda cliente %s* ou *segura cliente %s*', r.nome,
                             public._agenda_cliente_tipo_texto(r.tipo), public._agenda_cliente_quando_texto(r.enviar_em, v_agora),
                             r.texto, r.nome, r.nome);
      v_es := v_es || format('• %s (%s), sai %s: "%s" — *manda cliente %s*', r.nome,
                             public._agenda_cliente_tipo_texto(r.tipo), public._agenda_cliente_quando_texto(r.enviar_em, v_agora),
                             public._agenda_corta(regexp_replace(r.texto, 'Aqui é [^.]*\.\s*', ''), 70), r.nome);
    end if;
  end loop;
  for r in
    select q.tipo, q.texto from public.agenda_perguntas q
     where q.modo = 'ligado' and q.estado = 'aberta' and (q.expira_em is null or q.expira_em > v_agora)
       and (p_os is null or q.service_order_id = p_os)
       and ((q.tipo = 'cliente_resposta' and q.chave not like 'cliente_resposta:sem_resposta:%')
            or (q.tipo = 'cliente_aviso' and not exists (select 1 from public.agenda_cliente_mensagens m where m.pergunta_id = q.id)))
     order by q.perda_em nulls last, q.criada_em, q.id
  loop
    v_ef := v_ef || case when r.tipo = 'cliente_aviso' then '• Decisão: ' || r.texto else '• ' || r.texto end;
    v_es := v_es || case when r.tipo = 'cliente_aviso' then '• Decisão: ' || r.texto else '• ' || r.texto end;
  end loop;
  v_n := v_n || jsonb_build_object('esperando', cardinality(v_ef));

  -- (2) Vou mandar (hoje e amanhã): as livres e as aprovadas que saem até o próximo dia de janela
  v_b := '{}';
  for r in
    select m.tipo, m.estado, m.enviar_em, coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) as dia,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome
      from public.agenda_cliente_mensagens m join public.clients cl on cl.id = m.client_id
     where m.modo = 'ligado' and m.estado in ('registrada', 'enfileirada', 'aguardando_dono') and m.aprovacao in ('livre', 'aprovada')
       and (m.enviar_em at time zone 'America/Sao_Paulo')::date <= v_amanha
       and (p_os is null or m.service_order_id = p_os)
     order by m.enviar_em, cl.name, m.tipo, m.id
  loop
    v_b := v_b || format('• %s: %s, %s%s', r.nome, public._agenda_cliente_o_que(r.tipo, r.dia),
                         case when r.estado = 'enfileirada' then 'na fila, ' else '' end,
                         public._agenda_cliente_quando_texto(r.enviar_em, v_agora));
  end loop;
  v_n := v_n || jsonb_build_object('vou_mandar', cardinality(v_b));
  if cardinality(v_b) > 0 then
    v_c := v_c || 'Vou mandar (hoje e amanhã):'::text || v_b;
  end if;

  -- (3) Mandei (7 dias)
  v_b := '{}';
  for r in
    select m.tipo, m.enviada_em, coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) as dia,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome
      from public.agenda_cliente_mensagens m join public.clients cl on cl.id = m.client_id
     where m.enviada_em is not null and m.enviada_em > v_agora - interval '7 days'
       and (p_os is null or m.service_order_id = p_os)
     order by m.enviada_em, m.id
  loop
    v_b := v_b || format('• %s: %s (%s às %s)', r.nome, public._agenda_cliente_o_que(r.tipo, r.dia),
                         public._dia_curto((r.enviada_em at time zone 'America/Sao_Paulo')::date),
                         to_char(r.enviada_em at time zone 'America/Sao_Paulo', 'HH24:MI'));
  end loop;
  v_n := v_n || jsonb_build_object('mandei', cardinality(v_b));
  if cardinality(v_b) > 0 then
    v_c := v_c || 'Mandei (7 dias):'::text || v_b;
  end if;

  -- (3b) Em teste: o que a agenda teria mandado (a sombra dos últimos 7 dias e a que sairia)
  v_b := '{}';
  for r in
    select m.tipo, m.enviar_em, m.estado, coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) as dia,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome
      from public.agenda_cliente_mensagens m join public.clients cl on cl.id = m.client_id
     where m.modo = 'sombra' and m.criada_em > v_agora - interval '7 days'
       and (p_os is null or m.service_order_id = p_os)
     order by m.enviar_em, cl.name, m.tipo, m.id
  loop
    v_b := v_b || format('• %s: %s (%s)', r.nome, public._agenda_cliente_o_que(r.tipo, r.dia),
                         case when r.estado = 'recusada' then 'não sairia'
                              when r.enviar_em <= v_agora
                                then format('teria saído %s às %s', public._dia_curto((r.enviar_em at time zone 'America/Sao_Paulo')::date),
                                            to_char(r.enviar_em at time zone 'America/Sao_Paulo', 'HH24:MI'))
                              else 'sairia ' || public._agenda_cliente_quando_texto(r.enviar_em, v_agora) end);
  end loop;
  v_n := v_n || jsonb_build_object('em_teste', cardinality(v_b));
  if cardinality(v_b) > 0 then
    v_c := v_c || case when cf.modo_cliente = 'sombra' then 'Em teste, eu teria mandado:'
                       else 'Em teste, eu teria mandado:' end || v_b;
  elsif cf.modo_cliente = 'sombra' then
    v_c := v_c || 'Em teste: nada que eu teria mandado nos últimos 7 dias.'::text;
  end if;

  -- (4) Responderam (7 dias): com o efeito; em teste, o que eu teria feito
  v_b := '{}';
  for r in
    select a.tipo_msg, a.texto, a.efeito, a.intencao, a.modo, m.tipo, m.variante,
           coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) as dia,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome
      from public.agenda_cliente_respostas a
      join public.clients cl on cl.id = a.client_id
      left join public.agenda_cliente_mensagens m on m.id = a.mensagem_id
     where a.recebida_em > v_agora - interval '7 days' and a.recebida_em <= v_agora
       and (p_os is null or a.service_order_id = p_os)
     order by a.recebida_em, a.id
  loop
    v_b := v_b || format('• %s%s respondeu %s%s: %s', case when r.modo = 'sombra' then 'Em teste: o ' else '' end, r.nome,
                         case when r.tipo_msg = 'audio' then 'por áudio'
                              when r.tipo_msg <> 'text' then 'com ' || case r.tipo_msg when 'image' then 'uma foto'
                                                                                         when 'document' then 'um documento'
                                                                                         when 'video' then 'um vídeo'
                                                                                         else 'uma mensagem' end
                              else '"' || public._agenda_corta(coalesce(r.texto, ''), 60) || '"' end,
                         case when r.tipo is not null then ' ' || public._agenda_cliente_a_mensagem(r.tipo, r.variante, r.dia) else '' end,
                         case when r.efeito = 'sombra' then public._agenda_cliente_teria_feito(r.intencao, r.dia)
                              else public._agenda_cliente_efeito_texto(r.efeito) end);
    -- FASE 6: (P7) sem artigo antes do nome: "• Em teste: Nelson respondeu …"
    v_b[cardinality(v_b)] := replace(v_b[cardinality(v_b)], '• Em teste: o ' || r.nome || ' respondeu ',
                                     '• Em teste: ' || r.nome || ' respondeu ');
    -- FASE 6: fim
    -- FASE 7d: (7d P6, §5.6, R6.3-5) a resposta ao M11 não é o acesso: em teste, o que eu teria feito; em ligado, o efeito anotou_acesso diz o que houve
    if r.tipo = 'onde_fica' and r.efeito in ('sombra', 'anotou_acesso') and r.intencao not in ('audio', 'opt_out', 'disputa', 'negociacao', 'acordo')
       and r.tipo_msg = 'text' then
      v_b[cardinality(v_b)] := replace(v_b[cardinality(v_b)],
        case when r.efeito = 'sombra' then public._agenda_cliente_teria_feito(r.intencao, r.dia)
             else public._agenda_cliente_efeito_texto(r.efeito) end,
        case when r.efeito = 'sombra' then public._agenda_cliente_teria_feito('onde_fica', r.dia) else 'disse onde fica, e eu anotei e perguntei a você' end);
    end if;
    -- FASE 7d: fim
    -- FASE 7f: (7f P6, R8.12-9) a resposta à semana prevista em teste: o SIM seria só ciência (não confirma dia nenhum), e o resto iria a você (a semana não
    -- propõe dia); o PARAR é o de sempre
    if r.tipo = 'semana' and r.efeito = 'sombra' and r.intencao is distinct from 'opt_out' then
      v_b[cardinality(v_b)] := replace(v_b[cardinality(v_b)], public._agenda_cliente_teria_feito(r.intencao, r.dia),
        case when r.intencao = 'confirma' then 'eu teria anotado que ficou ciente' else 'eu teria passado a você' end);
    end if;
    -- FASE 7f: fim
  end loop;
  v_n := v_n || jsonb_build_object('responderam', cardinality(v_b));
  if cardinality(v_b) > 0 then
    v_c := v_c || 'Responderam (7 dias):'::text || v_b;
  end if;

  -- (5) Sem resposta (o M1/M3/M7/M10 que o cliente não respondeu, dos últimos 14 dias)
  v_b := '{}';
  for r in
    select m.tipo, m.enviada_em, coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) as dia,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome
      from public.agenda_cliente_mensagens m join public.clients cl on cl.id = m.client_id
     where m.estado = 'sem_resposta' and m.enviada_em > v_agora - interval '14 days'
       and (p_os is null or m.service_order_id = p_os)
     order by m.enviada_em, m.id
  loop
    v_b := v_b || format('• %s: %s, mandada %s', r.nome, public._agenda_cliente_o_que(r.tipo, r.dia),
                         public._dia_curto((r.enviada_em at time zone 'America/Sao_Paulo')::date));
  end loop;
  v_n := v_n || jsonb_build_object('sem_resposta', cardinality(v_b));
  if cardinality(v_b) > 0 then
    v_c := v_c || 'Sem resposta:'::text || v_b;
  end if;

  -- (6) Não consigo mandar: os clientes da carteira (e das OS concluídas nos últimos 30 dias) sem telefone, com opt-out ou
  -- sem conversa no último ano (d10: por ora só mando a quem já escreveu — suposição, a confirmar com você); e, em ligado, os
  -- tipos ainda em teste
  v_b := '{}';
  for r in
    select c.id,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(c.display_name, '')), ''), c.name)) as nome,
           public._agenda_cliente_telefone(c.id) is null as sem_tel,
           public._agenda_cliente_sem_mensagem(c.id) as opt_out,
           not public._agenda_cliente_conversou(c.id, v_agora) as sem_conversa
      from public.clients c
     where c.id in (select so.client_id from public.service_orders so
                     where so.merged_into_id is null and (p_os is null or so.id = p_os)
                       and (so.status in ('open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client')
                            or (so.status in ('completed', 'invoiced')
                                and coalesce(so.delivered_at, so.check_out_at) > v_agora - interval '30 days')))
     order by 2, c.id
  loop
    if r.sem_tel then
      v_b := v_b || format('%s (sem telefone no cadastro)', r.nome);
    elsif r.opt_out then
      v_b := v_b || format('%s (pediu para não receber mensagens)', r.nome);
    elsif r.sem_conversa then
      v_b := v_b || format('%s (não escreveu para a HBR no último ano; por ora só mando a quem já escreveu)', r.nome);
    end if;
  end loop;
  v_n := v_n || jsonb_build_object('nao_consigo', cardinality(v_b));
  if cardinality(v_b) > 0 then
    v_c := v_c || format('Não consigo mandar: %s.', public._agenda_lista(v_b, null));
  end if;
  if cf.modo_cliente = 'ligado' then
    v_tipos := array(select public._agenda_cliente_tipo_texto(t) from unnest(c_tipos) with ordinality u(t, o)
                      where t <> all (cf.cliente_tipos_ligados) order by o);
    -- FASE 7f: (7f P6) a semana prevista está "em teste" só com as camadas fora de desligado e sem sair de verdade (fora da lista, ou com o freio); desligada,
    -- ela não existe para o cliente, e a lista é a de antes, byte a byte. Na lista dos 11, não: ela vive atrás das camadas
    if public._agenda_fala_modo('camadas') <> 'desligado'
       and not ('semana' = any (cf.cliente_tipos_ligados) and public._agenda_fala_modo('camadas') = 'ligado') then
      v_tipos := v_tipos || public._agenda_cliente_tipo_texto('semana');
    end if;
    -- FASE 7f: fim
    if cardinality(v_tipos) > 0 then
      v_c := v_c || format('Ainda em teste (não saem): %s.', public._agenda_lista(v_tipos, null));
    end if;
  end if;

  -- nada a contar (em ligado): a frase logo depois do cabeçalho, antes do que não consigo mandar
  if (select coalesce(sum(e.value::int), 0) from jsonb_each_text(v_n - 'em_teste' - 'nao_consigo') e) = 0
     and cf.modo_cliente = 'ligado' then
    v_l := v_l || 'Nada esperando você, nada a mandar e nenhuma resposta nos últimos 7 dias.'::text;
  end if;
  -- as que esperam você: a 1ª sempre inteira; as outras encurtam, da última para a 2ª, só se o texto não couber
  k := cardinality(v_ef);
  loop
    v_t := v_l || case when cardinality(v_ef) > 0 then 'Esperando você:'::text || (v_ef[1:k] || v_es[k + 1:]) else '{}'::text[] end
           || v_c;
    exit when k <= 1 or char_length(array_to_string(v_t, E'\n')) <= cf.texto_max;
    k := k - 1;
  end loop;
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_t, cf.texto_max),
                            'dados', v_n || jsonb_build_object('modo', cf.modo_cliente, 'os', p_os));
end;
$function$;
comment on function public._agenda_ver_clientes(uuid, date) is
  'Agenda de Produção (Fase 5, P5): agenda_ver foco clientes (*agenda clientes*) — as mensagens ao cliente em blocos: "Esperando você" (a mensagem que espera *manda cliente*/*segura cliente*, INTEIRA; o aviso de atraso que é decisão; a data dita que passou sem aviso; a resposta que foi ao dono), "Vou mandar (hoje e amanhã)", "Mandei (7 dias)", "Em teste, eu teria mandado" (a sombra), "Responderam (7 dias)" com o efeito (em teste: o que eu teria feito), "Sem resposta" e "Não consigo mandar" (sem telefone, opt-out, sem conversa no último ano, tipos ainda em teste). Com p_os, só dela, mais o que foi dito (prometido_*) e a confirmação. modo_cliente desligado = "As mensagens ao cliente estão desligadas". Até texto_max, cortado por linha. A hora de agora: agenda.agora (a bancada), senão now(). Definer (lê a fila e as respostas): com login, só administrador e financeiro (42501). {ok, texto, dados:{esperando, vou_mandar, mandei, em_teste, responderam, sem_resposta, nao_consigo, modo, os}}. FASE 6 (P7, spec-fase6 §6.4): sem artigo antes do nome e sem "ele" ("O que foi dito ao cliente: …", "O cliente confirmou …", "• Em teste: Nelson respondeu …", "o aviso de atraso de Nelson espera você …"). FASE 7d (P6, §5.6): onde_fica na lista dos tipos ("Ainda em teste (não saem): onde fica o bem."), e a resposta ao M11 diz o que houve, não "o acesso". FASE 7f (P6): a semana na lista "Ainda em teste" só com as camadas fora de desligado e sem sair de verdade; a resposta a ela em teste diz o que seria (ciência; o resto a você).';

create or replace function public.agenda_cliente_preparar(p_autor uuid, p_os text, p_tipo text, p_firme boolean default false,
                                                          p_trecho text default null, p_hoje date default public._hoje_brt(),
                                                          p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_autor uuid := public._autor_da_agenda(p_autor);
  v_tipo  text := lower(btrim(coalesce(p_tipo, '')));
  v_ro    jsonb;
  v_os    uuid;
  x       jsonb;
  v_rk    jsonb;
  v_nome  text;
  v_st    text;
  v_dia   date;
  v_var   text;
  v_dados jsonb := '{}'::jsonb;
  v_alvo  timestamptz := p_agora;
  v_valida timestamptz;
  v_chave text;
  v_r     jsonb;
  m       public.agenda_cliente_mensagens%rowtype;
  v_conc  date;
  v_ini   date;
  v_pl    jsonb;
  v_txt   text;
begin
  if v_tipo not in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar', 'nova_data', 'pronto',
                    -- FASE 7f: (7f P6) a semana prevista é um tipo que existe (a recusa abaixo diz por onde sair)
                    'semana',
                    -- FASE 7f: fim
                    'pronto_lembrete', 'pos_servico', 'mudanca_no_dia') then
    raise exception 'O tipo da mensagem ao cliente não existe: "%".', coalesce(p_tipo, '') using errcode = '22023';
  end if;
  if cf.modo_cliente = 'desligado' then
    return public._agenda_recusa('As mensagens ao cliente estão desligadas: não preparei nada.', 'desligada');
  end if;
  if nullif(btrim(coalesce(p_trecho, '')), '') is null then
    return public._agenda_recusa('Me diga com as suas palavras o que avisar ao cliente.', 'sem_trecho');
  end if;
  if v_tipo = 'mudanca_no_dia' then
    return public._agenda_recusa('O aviso de mudança no dia eu mando sozinho quando o plano muda (chuva, falta da equipe). Para outra data, me diga o novo dia do serviço.',
                                 'mudanca_no_dia');
  end if;
  -- FASE 7f: (7f P6, §5.6; R8.12-1, a recusa diz a saída) a semana prevista é da rodada (às cliente_hora_preparo, ao serviço marcado pela minha estimativa, sem dia certo);
  -- quem quer dizer o dia ao cliente pede a confirmação
  if v_tipo = 'semana' then
    return public._agenda_recusa(format('A semana prevista eu mando sozinho, às %s, ao serviço que ainda não tem o dia certo; o dia certo vai na véspera. Para dizer o dia ao cliente agora, peça a confirmação.',
                                        to_char(cf.cliente_hora_preparo, 'HH24:MI')), 'semana');
  end if;
  -- FASE 7f: fim
  v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
  if v_ro ->> 'status' = 'fora_da_carteira' and v_tipo in ('pronto', 'pronto_lembrete', 'pos_servico') then
    v_os := (v_ro ->> 'id')::uuid;
  elsif v_ro ->> 'status' <> 'ok' then
    return public._agenda_recusa_da_os(v_ro);
  else
    v_os := (v_ro ->> 'id')::uuid;
  end if;
  x := public._agenda_cliente_contexto(v_os, p_hoje);
  v_nome := coalesce(x ->> 'nome', 'cliente');
  v_st := x ->> 'status';
  if not coalesce((x ->> 'telefone_ok')::boolean, false) then
    -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
    return public._agenda_recusa(format('%s não tem telefone no cadastro: não tenho como mandar.', v_nome), 'sem_telefone');
    -- FASE 6: fim
    return public._agenda_recusa(format('O %s não tem telefone no cadastro: não tenho como mandar.', v_nome), 'sem_telefone');
  end if;
  if coalesce((x ->> 'opt_out')::boolean, false) then
    -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
    return public._agenda_recusa(format('%s pediu para não receber mensagens: não mando.', v_nome), 'opt_out');
    -- FASE 6: fim
    return public._agenda_recusa(format('O %s pediu para não receber mensagens: não mando.', v_nome), 'opt_out');
  end if;

  if v_tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data') then
    v_dia := (x ->> 'dia')::date;
    -- d09: material sem previsão ou não conferido nunca vira data firme (antes da data: é o que o dono precisa saber)
    if coalesce(x ->> 'material_estado', '') <> 'completo' then
      -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
      return public._agenda_recusa(format('O material de %s ainda não está todo na mão (%s): não digo data firme ao cliente. Quando chegar, me avise e eu preparo.',
                                          v_nome, case x ->> 'material_estado' when 'previsto' then 'tem peça a caminho'
                                                                             when 'sem_previsao' then 'tem peça sem previsão de chegada'
                                                                             when 'atrasado' then 'tem peça atrasada'
                                                                             else 'o material ainda não foi conferido' end),
                                   'material');
      -- FASE 6: fim
      return public._agenda_recusa(format('O material do %s ainda não está todo na mão (%s): não digo data firme ao cliente. Quando chegar, me avise e eu preparo.',
                                          v_nome, case x ->> 'material_estado' when 'previsto' then 'tem peça a caminho'
                                                                             when 'sem_previsao' then 'tem peça sem previsão de chegada'
                                                                             when 'atrasado' then 'tem peça atrasada'
                                                                             else 'o material ainda não foi conferido' end),
                                   'material');
    end if;
    if v_dia is null then
      -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
      return public._agenda_recusa(format('%s não tem data no plano: não tenho o que %s.', v_nome,
                                          case v_tipo when 'confirmar' then 'confirmar' when 'nova_data' then 'dizer de data nova'
                                                      else 'avisar' end), 'sem_data');
      -- FASE 6: fim
      return public._agenda_recusa(format('O %s não tem data no plano: não tenho o que %s.', v_nome,
                                          case v_tipo when 'confirmar' then 'confirmar' when 'nova_data' then 'dizer de data nova'
                                                      else 'avisar' end), 'sem_data');
    end if;
    if v_tipo in ('vespera', 'acesso') then
      if v_dia <= p_hoje then
        -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
        return public._agenda_recusa(format('O serviço de %s é hoje: a véspera já passou.', v_nome), 'passou');
        -- FASE 6: fim
        return public._agenda_recusa(format('O serviço do %s é hoje: a véspera já passou.', v_nome), 'passou');
      end if;
      v_alvo := greatest(p_agora, public._agenda_cliente_toque(public._agenda_cliente_vespera(v_dia)));
    end if;
  elsif v_tipo = 'pode_atrasar' then
    v_rk := public._agenda_cliente_risco(v_os, p_hoje);
    if (x #>> '{prometido,ate}') is null or v_rk is null then
      -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
      return public._agenda_recusa(format('Não há data dita para %s: sem data dita, não há atraso a avisar. Se você disse uma data, me conte ("falei pro %s que é dia 3").',
                                          v_nome, v_nome), 'sem_prometido');
      -- FASE 6: fim
      return public._agenda_recusa(format('Não há data dita ao %s: sem data dita, não há atraso a avisar. Se você disse uma data a ele, me conte ("falei pro %s que é dia 3").',
                                          v_nome, v_nome), 'sem_prometido');
    end if;
    if coalesce((v_rk ->> 'passou')::boolean, false) then
      -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
      return public._agenda_recusa(format('A data que %s ouviu (%s) já passou: um aviso escrito agora chega depois dela. Recomendo você ligar.',
                                          v_nome, public._dia_curto((v_rk ->> 'dito_ate')::date)), 'passou');
      -- FASE 6: fim
      return public._agenda_recusa(format('A data que o %s ouviu (%s) já passou: um aviso escrito agora chega depois dela. Recomendo você ligar.',
                                          v_nome, public._dia_curto((v_rk ->> 'dito_ate')::date)), 'passou');
    end if;
    if coalesce(p_firme, false) then
      -- a data firme do plano no lugar da faixa (d09: só o dono decide, e só com o plano publicado)
      if (x ->> 'dia') is null or (x ->> 'fim') is null then
        -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
        return public._agenda_recusa(format('%s não tem o plano publicado: não tenho data firme para dizer; vai a faixa.', v_nome),
                                     'sem_plano');
        -- FASE 6: fim
        return public._agenda_recusa(format('O %s não tem o plano publicado: não tenho data firme para dizer; vai a faixa.', v_nome),
                                     'sem_plano');
      end if;
      v_var := 'remarcado';
      v_dia := (x ->> 'dia')::date;
      v_dados := jsonb_build_object('dia', x -> 'dia', 'fim', x -> 'fim', 'prometido_tipo', 'firme',
                                    'dito_de', v_rk -> 'dito_de', 'dito_ate', v_rk -> 'dito_ate');
      -- CORREÇÃO FASE 5: (item 7) a data firme que o DONO manda dizer passa pela revalidação sem o passo do material (d09:
      -- só o dono troca a faixa pela data firme do plano); (item 6) com o início igual ao que o cliente ouviu, a forma fim
      v_dados := v_dados || jsonb_build_object('firme_do_dono', true)
                 || case when v_dia = coalesce((v_rk ->> 'dito_de')::date, (v_rk ->> 'dito_ate')::date)
                         then jsonb_build_object('forma', 'fim') else '{}'::jsonb end;
      -- CORREÇÃO FASE 5: fim
    else
      if coalesce((v_rk ->> 'sem_data')::boolean, false) then
        -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
        return public._agenda_recusa(format('A peça de %s ainda não tem previsão: não tenho data nova para dizer. Com a previsão eu preparo (ou peça com a data firme do plano).',
                                            v_nome), 'sem_data');
        -- FASE 6: fim
        return public._agenda_recusa(format('A peça do %s ainda não tem previsão: não tenho data nova para dizer. Com a previsão eu preparo (ou peça com a data firme do plano).',
                                            v_nome), 'sem_data');
      end if;
      if not coalesce((v_rk ->> 'risco')::boolean, false) then
        -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
        return public._agenda_recusa(format('O plano de %s ainda cabe na data dita (%s): não há atraso a avisar.', v_nome,
                                            public._dia_curto((v_rk ->> 'dito_ate')::date)), 'sem_risco');
        -- FASE 6: fim
        return public._agenda_recusa(format('O plano do %s ainda cabe na data que ele ouviu (%s): não há atraso a avisar.', v_nome,
                                            public._dia_curto((v_rk ->> 'dito_ate')::date)), 'sem_risco');
      end if;
      v_var := v_rk ->> 'variante';
      v_dia := (v_rk ->> 'faixa_de')::date;
      v_dados := jsonb_build_object('faixa_de', v_rk -> 'faixa_de', 'faixa_ate', v_rk -> 'faixa_ate', 'prometido_tipo', v_rk -> 'tipo',
                                    'dito_de', v_rk -> 'dito_de', 'dito_ate', v_rk -> 'dito_ate')
                 || case when v_var = 'peca' then jsonb_build_object('peca_de', v_rk -> 'peca', 'peca_ate', v_rk -> 'peca')
                         else '{}'::jsonb end;
      -- CORREÇÃO FASE 5: (item 6) o remarcado da rodada com o mesmo início: a forma fim (como o passo atraso)
      if v_rk ->> 'forma' = 'fim' then
        v_dados := v_dados || jsonb_build_object('forma', 'fim', 'dia', v_rk -> 'faixa_de', 'fim', v_rk -> 'faixa_ate');
      end if;
      -- CORREÇÃO FASE 5: fim
    end if;
    v_valida := public._agenda_cliente_ultimo_fim((v_rk ->> 'dito_ate')::date);
  elsif v_tipo = 'andamento' then
    v_pl := public._agenda_plano_da_os(v_os, p_hoje);
    select min(a.dia) into v_ini from public.agenda_alocacoes a
     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
       and a.resultado in ('cumprido', 'parcial');
    if v_st <> 'in_progress' or v_ini is null or (v_pl ->> 'ultimo_dia') is null then
      -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
      return public._agenda_recusa(format('O serviço de %s ainda não começou (ou não tem o fim no plano): não há andamento a contar.', v_nome),
                                   'sem_andamento');
      -- FASE 6: fim
      return public._agenda_recusa(format('O serviço do %s ainda não começou (ou não tem o fim no plano): não há andamento a contar.', v_nome),
                                   'sem_andamento');
    end if;
    v_var := 'semanal';
    v_dia := (v_pl ->> 'ultimo_dia')::date;
    v_dados := jsonb_build_object('n_feitos', floor(coalesce((v_pl ->> 'meios_cumpridos')::numeric, 0))::int,
                                  'chave', to_char(p_hoje, 'IYYY-"S"IW'));
  else
    -- pronto, lembrete e pós-serviço: a OS concluída
    select (so.check_out_at at time zone 'America/Sao_Paulo')::date into v_conc
      from public.service_orders so where so.id = v_os and so.status in ('completed', 'invoiced');
    if v_conc is null then
      -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
      return public._agenda_recusa(format('O serviço de %s ainda não está concluído.', v_nome), 'nao_concluida');
      -- FASE 6: fim
      return public._agenda_recusa(format('O serviço do %s ainda não está concluído.', v_nome), 'nao_concluida');
    end if;
    if v_tipo in ('pronto', 'pronto_lembrete')
       and exists (select 1 from public.service_orders so where so.id = v_os and so.delivered_at is not null) then
      -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
      return public._agenda_recusa(format('O serviço de %s já foi entregue.', v_nome), 'entregue');
      -- FASE 6: fim
      return public._agenda_recusa(format('O serviço do %s já foi entregue.', v_nome), 'entregue');
    end if;
    if v_tipo = 'pronto' then
      v_dia := v_conc;
    elsif v_tipo = 'pronto_lembrete' then
      v_dados := jsonb_build_object('chave', '2');
    else
      v_dados := jsonb_build_object('chave', 'pos');
    end if;
  end if;

  begin
    v_r := public._agenda_cliente_registrar(v_tipo, v_var, v_os, v_dia, v_dados, v_alvo, v_valida, 'dono', null, p_agora, v_autor);
    if v_r ->> 'motivo' = 'ja_existe' then
      select * into m from public.agenda_cliente_mensagens where id = (v_r ->> 'id')::uuid;
      if m.estado = 'recusada' then
        -- a do mesmo dia já foi recusada (segurada, vencida…): o pedido explícito do dono vale uma vez mais
        v_chave := coalesce(nullif(btrim(v_dados ->> 'chave'), ''), v_dia::text, to_char(p_agora at time zone 'America/Sao_Paulo', 'YYYY-MM-DD'))
                   || ':dono';
        v_r := public._agenda_cliente_registrar(v_tipo, v_var, v_os, v_dia, v_dados || jsonb_build_object('chave', v_chave), v_alvo,
                                                v_valida, 'dono', null, p_agora, v_autor);
        if v_r ->> 'motivo' = 'ja_existe' then
          select * into m from public.agenda_cliente_mensagens where id = (v_r ->> 'id')::uuid;
        end if;
      end if;
    end if;
  exception when sqlstate '22023' then
    -- CORREÇÃO FASE 6: (C2) texto 6: a forma fim cujo fim novo não passa do dia que o cliente ouviu (n < 1, a recusa do P7 em
    -- _agenda_cliente_texto) diz isso ao dono em palavras, e não o texto técnico do erro
    if sqlerrm = 'Falta o fim novo depois do dia dito para a mensagem pode_atrasar ao cliente.' then
      return public._agenda_recusa('Não preparei: o fim novo não passa do dia que o cliente ouviu, então não há atraso para avisar.', 'texto');
    end if;
    -- CORREÇÃO FASE 6: fim
    return public._agenda_recusa(format('Não preparei: %s', sqlerrm), 'texto');
  end;

  if v_r ->> 'motivo' = 'ja_existe' then
    v_txt := case
      when m.estado = 'aguardando_dono' and m.aprovacao = 'pedida'
        then format('Já está pronta, esperando você (sai %s): "%s". Para mandar: *manda cliente %s*.',
                    public._agenda_cliente_quando_texto(m.enviar_em, p_agora), m.texto, v_nome)
      when m.estado = 'aguardando_dono' then format('Essa mensagem ao %s é uma decisão que espera você: responda pela conversa (1, 2 ou 3).', v_nome)
      when m.estado in ('registrada', 'enfileirada') and m.modo = 'ligado'
        then format('Essa mensagem já vai sair sozinha %s: "%s". Para não mandar: *segura cliente %s*.',
                    public._agenda_cliente_quando_texto(m.enviar_em, p_agora), m.texto, v_nome)
      when m.estado in ('registrada', 'enfileirada')
        then format('Em teste: essa mensagem já está registrada (sairia %s): "%s".',
                    public._agenda_cliente_quando_texto(m.enviar_em, p_agora), m.texto)
      when m.enviada_em is not null
        then format('Já mandei ao %s %s às %s: "%s".', v_nome,
                    public._dia_curto((m.enviada_em at time zone 'America/Sao_Paulo')::date),
                    to_char(m.enviada_em at time zone 'America/Sao_Paulo', 'HH24:MI'), m.texto)
      else format('Essa mensagem ao %s já foi registrada e não sai (%s).', v_nome, coalesce(m.recusa_motivo, m.estado)) end;
    -- CORREÇÃO FASE 5: (item 15) sem artigo antes do nome ("Já mandei para Nelson …")
    v_txt := public._agenda_cliente_sem_artigo(v_txt, v_os);
    -- CORREÇÃO FASE 5: fim
    return jsonb_build_object('ok', true, 'status', 'ja_existe', 'texto', v_txt, 'mensagem_id', m.id, 'estado', m.estado,
                              'modo', m.modo);
  end if;
  if v_r ->> 'estado' = 'recusada' then
    -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
    return public._agenda_recusa(format('Não preparei: a mensagem para %s passaria da hora de servir (sairia %s).', v_nome,
                                        public._agenda_cliente_quando_texto((v_r ->> 'enviar_em')::timestamptz, p_agora)),
                                 coalesce(v_r ->> 'motivo', 'vencida'));
    -- FASE 6: fim
    return public._agenda_recusa(format('Não preparei: a mensagem ao %s passaria da hora de servir (sairia %s).', v_nome,
                                        public._agenda_cliente_quando_texto((v_r ->> 'enviar_em')::timestamptz, p_agora)),
                                 coalesce(v_r ->> 'motivo', 'vencida'));
  end if;
  v_txt := case
    when v_r ->> 'modo' = 'ligado'
      then format('Pronto para o %s, sai %s: "%s". Para mandar: *manda cliente %s*.', v_nome,
                  public._agenda_cliente_quando_texto((v_r ->> 'enviar_em')::timestamptz, p_agora), v_r ->> 'texto', v_nome)
    when cf.modo_cliente = 'ligado'
      then format('Esse tipo de mensagem (%s) ainda está em teste: não sai. Eu teria preparado para o %s, para sair %s: "%s".',
                  public._agenda_cliente_tipo_texto(v_tipo), v_nome,
                  public._agenda_cliente_quando_texto((v_r ->> 'enviar_em')::timestamptz, p_agora), v_r ->> 'texto')
    else format('Em teste (as mensagens ao cliente ainda não saem): eu teria preparado para o %s, para sair %s: "%s".', v_nome,
                public._agenda_cliente_quando_texto((v_r ->> 'enviar_em')::timestamptz, p_agora), v_r ->> 'texto') end;
  -- CORREÇÃO FASE 5: (item 15) "Pronto para Vanderlei, sai agora: …" (sem artigo antes do nome)
  v_txt := public._agenda_cliente_sem_artigo(v_txt, v_os);
  -- CORREÇÃO FASE 5: fim
  return jsonb_build_object('ok', true, 'status', 'preparada', 'texto', v_txt, 'mensagem_id', v_r -> 'id',
                            'estado', v_r ->> 'estado', 'modo', v_r ->> 'modo', 'enviar_em', v_r -> 'enviar_em');
end;
$function$;
comment on function public.agenda_cliente_preparar(uuid, text, text, boolean, text, date, timestamptz) is
  'Agenda de Produção (Fase 5, P5): a ferramenta cliente_avisar — prepara a mensagem-modelo que o dono pede e NUNCA envia. Resolve a OS (agenda_resolver_os; o pronto, o lembrete e o pós-serviço aceitam a OS concluída fora da carteira), confere o telefone e o opt-out, o tipo e os dados (sem dado, diz o que falta: "O Nelson não tem data no plano: não tenho o que confirmar.", "Não há data dita ao Giancarlo: …", d09 — material fora de "completo" não vira data firme), e registra pelo _agenda_cliente_registrar com origem dono (em ligado, sempre pedida: "Pronto para o Nelson, sai amanhã às 09:00: "…". Para mandar: *manda cliente Nelson*."; em teste, a sombra). A chave é a da rodada (a mesma mensagem não sai duas vezes: a que já existe é dita como está; a recusada antes ganha uma 2ª chance com :dono). p_firme (só pode_atrasar): a data firme do plano (variante remarcado) no lugar da faixa, só com o plano publicado. mudanca_no_dia não é pela ferramenta (sai sozinha). modo_cliente desligado = recusa. Admin pelo _autor_da_agenda. {ok, status, texto, mensagem_id, estado, modo, enviar_em} ou a recusa {ok:false, motivo, pergunta, texto}. CORREÇÃO FASE 5 (C2): (item 7) p_firme grava firme_do_dono em p_dados (a revalidação não aplica o passo do material a ela); (item 6) a forma fim com o mesmo início que o cliente ouviu; (item 15) o texto da preparada e o da que já existe sem artigo antes do nome. FASE 6 (P7, spec-fase6 §6.4): as recusas sem artigo antes do nome e sem "ele" ("Nelson não tem telefone no cadastro: …", "Não há data dita para Giancarlo: … Se você disse uma data, me conte …", "O plano de Nelson ainda cabe na data dita (qui 05/11): …"); a preparada e a que já existe passam pelo ralo (_agenda_cliente_sem_artigo, que agora tira também o "ele"). CORREÇÃO FASE 6 (C2, texto 6): a forma fim cujo fim novo não passa do dia que o cliente ouviu diz "Não preparei: o fim novo não passa do dia que o cliente ouviu, então não há atraso para avisar.", e não o texto técnico do erro. FASE 7f (P6): o tipo semana existe e é recusado com a saída: é da rodada, às 17:00; para o dia, a confirmação.';

create or replace function public.agenda_saude(p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf        public.agenda_config := public._agenda_cfg();
  v_cart    uuid[];
  v_ult     record;
  v_vig     jsonb;
  v_hoje    jsonb;
  v_crit    jsonb;
  v_perg    jsonb;
  v_prop    jsonb;
  v_plano   jsonb;
  v_inv     jsonb;
  v_fech    jsonb;
  v_sem     int;
  v_regra   jsonb;
  v_leu     boolean;
  v_choques int;
  -- FASE 3
  v_rot     jsonb;
  v_eq      jsonb;
  v_dia     jsonb;
  v_conc    jsonb;
  v_marcos  jsonb;
  v_com     jsonb;
  v_teto    int;
  v_janela  int;
  v_semconf int;
  v_sobre   int;
  v_semrec  int;
  v_pay     int;
  -- FASE 4: o material e a mensagem ao fornecedor
  v_mrod    jsonb;
  v_rem     jsonb;
  v_mperg   jsonb;
  v_semdono int;
  v_semorig int;
  v_prec    jsonb;
  v_det     jsonb;
  v_fsombra int;
  v_ffora   int;
  v_fteto   int;
  v_fproib  int;
  v_forn    jsonb;
  v_cob     jsonb;
  v_med     numeric;
  v_zeros4  boolean;
  v_mat     jsonb;
  -- FASE 4: fim
  -- FASE 5: a mensagem ao cliente
  v_crod    jsonb;
  v_cmsg    jsonb;
  v_caprov  jsonb;
  v_cjan    int;
  v_cdom    int;
  v_cteto   int;
  v_cint    int;
  v_cproib  int;
  v_csombra int;
  v_csemap  int;
  v_ccrit   int;
  v_cvesp   int;
  v_cdepois int;
  v_caudio  int;
  v_cmet    jsonb;
  v_zeros5  boolean;
  v_cli     jsonb;
  -- FASE 5: fim
  -- FASE 6: o aprendizado
  v_arod    record;
  v_apeq    int;
  v_afora   int;
  v_agrande int;
  v_aatras  int;
  v_asemcl  int;
  v_afat    int;
  v_amet    jsonb;
  v_zeros6  boolean;
  v_apr     jsonb;
  -- FASE 6: fim
  -- CORREÇÃO FASE 6: (C2) item 12: os zeros de antes do aprendizado (para o ok sair com as janelas de agenda_config)
  v_z4_antes boolean;
  -- FASE 7: (7a P7) o gestor da agenda
  v_ges     jsonb;
  v_gz      jsonb;
  v_gzeros  boolean;
  v_gdesde  timestamptz;
  v_gmodos  jsonb;
  v_gult    record;
  v_gr      jsonb;
  -- FASE 7: fim
  -- CORREÇÃO FASE 6: fim
begin
  v_cart := array(select k.service_order_id from public.os_carteira(p_hoje) k);

  select max(x.p_agora) as ultima, max(x.rodou_em) as rodou_em,
         count(*) filter (where x.p_agora > p_agora - interval '1 day' and x.p_agora <= p_agora) as n24,
         (array_agg(x.erros order by x.p_agora desc, x.rodou_em desc))[1] as erros_ult
    into v_ult from public.agenda_vigia_rodadas x
   -- FASE 3: a rotina da equipe grava na mesma tabela (rotina = 'rotina'); a vigia é só a dela.
   where x.rotina = 'vigia';
  v_vig := jsonb_build_object(
    'ultima_rodada', v_ult.ultima, 'rodou_em', v_ult.rodou_em,
    'rodou_nas_ultimas_2h', coalesce(v_ult.ultima > p_agora - interval '2 hours', false),
    'rodadas_24h', coalesce(v_ult.n24, 0), 'erros_ultima_rodada', coalesce(v_ult.erros_ult, 0),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.last_seen_at >= least(p_agora, now()) - interval '1 day'));

  select jsonb_build_object(
           'publicar', count(*) filter (where a.executada and a.tipo = 'publicar'),
           'criar', count(*) filter (where a.executada and a.tipo = 'criar'),
           'mover', count(*) filter (where a.executada and a.tipo = 'mover'),
           'cancelar', count(*) filter (where a.executada and a.tipo = 'cancelar'),
           'promover', count(*) filter (where a.executada and a.tipo = 'promover_reserva'),
           'soltar', count(*) filter (where a.executada and a.tipo = 'soltar_reserva'),
           'status', count(*) filter (where a.executada and a.tipo = 'status'),
           'resultado', count(*) filter (where a.executada and a.tipo = 'resultado'),
           'desfeitas', count(*) filter (where a.executada and a.tipo = 'desfazer'),
           'sombra', count(*) filter (where not a.executada))
    into v_hoje from public.agenda_acoes a where a.dia = p_hoje;

  -- A prova: nenhuma ação crítica executada sem a decisão registrada (o gatilho impede; isto confere).
  select count(*) into v_sem
    from public.agenda_acoes a left join public.agenda_perguntas q on q.id = a.pergunta_id
   where a.executada and a.critica and (q.id is null or q.estado <> 'respondida' or q.opcao_escolhida is null);
  -- E o erro de classificação: ação autônoma executada como não crítica que a regra diz crítica.
  select jsonb_build_object('n', count(*), 'acoes', coalesce(jsonb_agg(a.id order by a.criada_em, a.id), '[]'::jsonb)) into v_regra
    from public.agenda_acoes a
   where a.executada and not a.critica and a.origem in ('motor', 'vigia', 'conferencia')
     and a.tipo in ('publicar', 'criar', 'mover', 'cancelar', 'promover_reserva', 'soltar_reserva')
     and public._agenda_criticidade_da_acao(a.id) is not null;
  v_crit := jsonb_build_object(
    'abertas', (select count(*) from public.agenda_perguntas q where q.critica and q.estado = 'aberta'),
    'respondidas_7d', (select count(*) from public.agenda_perguntas q
                        where q.critica and q.estado = 'respondida' and q.respondida_em > p_agora - interval '7 days'),
    'sem_decisao', v_sem, 'pela_regra_sem_decisao', (v_regra ->> 'n')::int, 'pela_regra_acoes', v_regra -> 'acoes');

  v_perg := jsonb_build_object(
    'abertas_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select q.tipo, count(*) as n from public.agenda_perguntas q where q.estado = 'aberta' group by q.tipo) t), '{}'::jsonb),
    'abertas_sombra', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.modo = 'sombra'),
    'mostradas_hoje', (select count(*) from public.agenda_perguntas q
                        where (q.mostrada_em at time zone 'America/Sao_Paulo')::date = p_hoje));

  select jsonb_build_object(
           'abertas', count(*) filter (where p.estado = 'aberta'),
           'obsoletas_7d', count(*) filter (where p.estado = 'obsoleta' and p.criada_em > p_agora - interval '7 days'),
           'aplicadas_7d', count(*) filter (where p.estado = 'aplicada' and p.criada_em > p_agora - interval '7 days'),
           'sombra_7d', count(*) filter (where p.modo = 'sombra' and p.criada_em > p_agora - interval '7 days'))
    into v_prop from public.agenda_propostas p;

  select jsonb_build_object(
           'alocacoes_vigentes_futuras', count(*) filter (where a.dia >= p_hoje and a.resultado is null),
           'os_programadas', count(distinct a.service_order_id) filter (where a.dia >= p_hoje and a.resultado is null and a.tipo <> 'reserva'),
           'reservas', count(*) filter (where a.dia >= p_hoje and a.tipo = 'reserva'),
           'sem_registro_7d', count(*) filter (where a.resultado = 'sem_registro' and a.dia > p_hoje - 7))
    into v_plano from public.agenda_alocacoes a where a.estado in ('publicada', 'fixada');

  select count(*) into v_choques
    from public.agenda_alocacoes a join public.agenda_alocacoes b
      on b.payee_id = a.payee_id and b.id > a.id and b.periodo && a.periodo
   where a.estado in ('publicada', 'fixada') and b.estado in ('publicada', 'fixada');
  v_inv := jsonb_build_object(
    'vigente_de_os_fora_da_carteira', (select count(distinct a.service_order_id) from public.agenda_alocacoes a
                                        where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
                                          and not (a.service_order_id = any (v_cart))),
    'espelho_divergente', case when cf.modo_proposta <> 'ligado' then 0 else (
       select count(*) from public.service_orders so
        cross join lateral (select min(lower(a.periodo)) as ini, max(upper(a.periodo)) as fim from public.agenda_alocacoes a
                             where a.service_order_id = so.id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                               and a.resultado is distinct from 'nao_cumprido') m
        where so.id = any (v_cart)
          and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = so.id)
          and (so.scheduled_start_at is distinct from m.ini or so.scheduled_end_at is distinct from m.fim)) end,
    'choques', v_choques);

  if to_regclass('public.resumo_tarde') is not null then
    execute $q$select exists (select 1 from public.resumo_tarde t
                               where t.dia = $1 and jsonb_typeof(t.detalhe -> 'agenda') = 'object'
                                 and (t.detalhe -> 'agenda' ? 'linhas_diria' or t.detalhe -> 'agenda' ? 'linhas'))$q$
      into v_leu using p_hoje;
  end if;
  v_fech := jsonb_build_object(
    'leu_o_plano_hoje', v_leu,
    'linhas_mostradas', (select count(*) from public.agenda_acoes a
                          where a.contada_via = 'fechamento' and (a.contada_em at time zone 'America/Sao_Paulo')::date = p_hoje)
                        + (select count(*) from public.agenda_perguntas q
                            where q.mostrada_via = 'fechamento' and (q.mostrada_em at time zone 'America/Sao_Paulo')::date = p_hoje));

  -- FASE 3: a rotina, a equipe, as diárias, a conclusão, os marcos e a comissão. Os "0 obrigatórios": acima do teto, fora
  -- da janela, diária sem confirmação, turno sobrescrito pela agenda, conclusão sem cobrança quando devia, pagamento de
  -- comissão de técnico.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'rotina:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_rot from public.agenda_vigia_rodadas x where x.rotina = 'rotina';
  select count(*) into v_teto
    from (select m.payee_id, (m.enviar_em at time zone 'America/Sao_Paulo')::date as dia, m.tipo = 'resposta' as resp, count(*) as n
            from public.agenda_equipe_mensagens m
           where m.modo = 'ligado' and m.estado in ('enfileirada', 'respondida', 'sem_resposta')
           group by 1, 2, 3) t
   where t.n > case when t.resp then cf.equipe_respostas_dia_max else cf.equipe_proativas_dia_max end;
  -- (revisão C1) pela regra única da janela (_agenda_equipe_fora_da_janela): a resposta direta tem a dela
  select count(*) into v_janela
    from public.whatsapp_send_queue q
    left join public.agenda_equipe_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-equipe'
     and (x.id is null
          or public._agenda_equipe_fora_da_janela(x.tipo, x.enviar_em, q.scheduled_for) is not null
          -- o que SAIU fora da janela (o worker atrasado): também conta
          or (q.sent_at is not null and public._agenda_equipe_fora_da_janela(x.tipo, x.enviar_em, q.sent_at) is not null));
  v_eq := jsonb_build_object(
    'mensagens_hoje_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select m.tipo, count(*) as n from public.agenda_equipe_mensagens m
         where (m.enviar_em at time zone 'America/Sao_Paulo')::date = p_hoje group by m.tipo) t), '{}'::jsonb),
    'recusadas_hoje_por_motivo', coalesce((select jsonb_object_agg(t.recusa_motivo, t.n) from (
        select m.recusa_motivo, count(*) as n from public.agenda_equipe_mensagens m
         where m.estado = 'recusada' and (m.enviar_em at time zone 'America/Sao_Paulo')::date = p_hoje group by m.recusa_motivo) t), '{}'::jsonb),
    'acima_do_teto', v_teto, 'fora_da_janela', v_janela);
  select count(*) into v_semconf
    from public.agenda_acoes a
   where a.tipo = 'diaria' and a.executada and not a.critica and a.origem <> 'dono' and a.desfeita_em is null
     and coalesce(public._agenda_confirmacao_do_dia(a.payee_id, (a.depois ->> 'dia')::date) ->> 'estado', '') <> 'confirmada';
  select count(*) into v_sobre
    from public.agenda_acoes a left join public.work_shifts ws on ws.id = a.work_shift_id
   where a.tipo = 'diaria' and a.executada and not a.critica and a.origem <> 'dono'
     and (coalesce(jsonb_typeof(a.antes -> 'turno'), 'null') <> 'null' or (ws.id is not null and ws.origem <> 'agente'));
  v_dia := jsonb_build_object(
    -- (o dia de quem agiu: a.dia é o p_hoje dele; criada_em é o relógio do banco)
    'lancadas_7d', (select count(*) from public.agenda_acoes a
                     where a.tipo = 'diaria' and a.executada and a.origem <> 'dono' and a.dia > p_hoje - 7),
    'sombra_7d', (select count(*) from public.agenda_acoes a
                   where a.tipo = 'diaria' and not a.executada and a.dia > p_hoje - 7),
    'perguntas_abertas', (select count(*) from public.agenda_perguntas q where q.tipo in ('diaria', 'diaria_ligar') and q.estado = 'aberta'),
    'sem_confirmacao', v_semconf, 'sobrescreveu_turno', v_sobre);
  -- a conclusão pela porta sem cobrança viva quando a regra da condição dá parcelas ou título (a releitura é só service_role)
  if has_function_privilege('public._os_recebiveis_da_conclusao(uuid, date)', 'execute') then
    select count(*) into v_semrec
      from (select distinct so.id, so.check_out_at
              from public.agenda_acoes a join public.service_orders so on so.id = a.service_order_id
             where a.tipo = 'concluir' and a.executada and a.desfeita_em is null and so.status in ('completed', 'invoiced')
               and so.check_out_at is not null
               and not exists (select 1 from public.receivables r where r.service_order_id = so.id and r.status <> 'cancelled')) t
     where public._os_recebiveis_da_conclusao(t.id, (t.check_out_at at time zone 'America/Sao_Paulo')::date) ->> 'motivo'
           in ('parcelas', 'titulo_unico');
  end if;
  v_conc := jsonb_build_object(
    'pela_agenda_7d', (select count(*) from public.agenda_acoes a
                        where a.tipo = 'concluir' and a.executada and a.origem in ('equipe', 'dono')
                          and a.dia > p_hoje - 7),
    'desfeitas_7d', (select count(*) from public.agenda_acoes a
                      where a.tipo = 'concluir' and a.desfeita_em > p_agora - interval '7 days'),
    'sem_recebivel_quando_devia', v_semrec);
  select jsonb_build_object(
           'concluidas_30d', count(*),
           'entregues_em_ate_5du', count(*) filter (where so.delivered_at is not null
             and public.agenda_du_entre((so.check_out_at at time zone 'America/Sao_Paulo')::date,
                                        (so.delivered_at at time zone 'America/Sao_Paulo')::date) <= cf.entrega_aviso_du),
           'sem_entrega_ha_mais_de_5du', count(*) filter (where so.delivered_at is null and so.status = 'completed'
             and public.agenda_du_entre((so.check_out_at at time zone 'America/Sao_Paulo')::date, p_hoje) > cf.entrega_aviso_du))
    into v_marcos
    from public.service_orders so
   where so.check_out_at > p_agora - interval '30 days'
     and exists (select 1 from public.agenda_acoes a
                  where a.service_order_id = so.id and a.tipo = 'concluir' and a.executada and a.desfeita_em is null);
  select count(*) into v_pay
    from public.payables pa
   where pa.origin = 'commission' and pa.created_at > p_agora - interval '7 days'
     and pa.payee_id in (select w.payee_id from public.work_profiles w where w.modo_pagamento = 'diaria' and w.payee_id is not null);
  v_com := jsonb_build_object('pagamento', (select c.pagamento from public.comissao_config c where c.id),
                              'payables_de_comissao_tecnico_7d', v_pay);
  -- FASE 3: fim
  -- FASE 4: o material (a nota, o Pix, o detector, o cadastro) e a mensagem ao fornecedor. Os "0 obrigatórios": linha
  -- ligada a nota ou Pix sem a palavra do dono (vinculo_sem_resposta_do_dono), previsão sem o original guardado, e na
  -- mensagem ao fornecedor: nada na fila em sombra (ou sem a mensagem registrada), nada saindo ou que saiu fora da janela,
  -- nada acima do teto, nada com valor, pagamento, OS, link ou o nome do cliente.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'material:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_mrod from public.agenda_vigia_rodadas x where x.rotina = 'material';
  select jsonb_build_object(
           'a_caminho', count(*) filter (where r.estado = 'a_caminho'),
           'sem_resposta', count(*) filter (where r.vinculo = 'sem_resposta' and r.estado <> 'descartada'),
           'ligadas_7d', count(*) filter (where r.vinculo = 'ligada' and r.respondida_em > p_agora - interval '7 days'),
           'sem_servico_7d', count(*) filter (where r.vinculo = 'sem_servico' and r.respondida_em > p_agora - interval '7 days'),
           'chegaram_7d', count(*) filter (where r.estado = 'chegou' and r.chegou_em > p_hoje - 7))
    into v_rem from public.material_remessas r;
  v_mperg := jsonb_build_object(
    'abertas_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select q.tipo, count(*) as n from public.agenda_perguntas q
         where q.estado = 'aberta'
           and q.tipo in ('nfe_vincular', 'pix_material', 'previsao_fornecedor', 'fornecedor_cadastro', 'fornecedores_prazo')
         group by q.tipo) t), '{}'::jsonb),
    -- o teto do Pix (pix_perguntas_semana_max por semana ISO, no total), no modo de agora
    'pix_na_semana', (select count(*) from public.agenda_perguntas q
                       where q.tipo = 'pix_material'
                         and q.modo = case when cf.modo_material = 'ligado' then 'ligado' else 'sombra' end
                         and (q.criada_em at time zone 'America/Sao_Paulo')::date
                             between date_trunc('week', p_hoje)::date and date_trunc('week', p_hoje)::date + 6));
  -- a linha que a agenda ligou a uma nota ou a um Pix tem de ter a palavra do dono (ou a compra que ele já ligou)
  select count(*) into v_semdono
    from public.os_material m
   where (m.remessa_id is not null or m.fonte in ('nfe', 'pix'))
     and coalesce(m.evidencia ->> 'vinculo_por', '') not in ('dono', 'compra_ligada');
  select count(*) into v_semorig from public.os_material m where m.previsao_ate is not null and m.previsao_original is null;
  -- a precisão do detector é do administrador e do financeiro (para outro login ela lançaria 42501)
  if (select auth.uid()) is null or public.is_admin_or_financial((select auth.uid())) then
    v_prec := public.agenda_detector_precisao(p_hoje - 13, p_hoje);
  end if;
  v_det := jsonb_build_object(
    'sinais_14d', v_prec -> 'sinais', 'julgados_14d', v_prec -> 'julgados', 'certos_14d', v_prec -> 'certos',
    'precisao_14d', v_prec -> 'precisao', 'pronto_para_ligar', coalesce((v_prec ->> 'pronto_para_ligar')::boolean, false),
    'aplicados_7d', (select count(*) from public.material_sinais s where s.estado = 'aplicado' and s.dia > p_hoje - 7),
    'desfeitos_7d', (select count(*) from public.material_sinais s join public.agenda_acoes a on a.id = s.acao_id
                      where a.desfeita_em > p_agora - interval '7 days'));
  -- a mensagem ao fornecedor: o que entrou na fila sem a mensagem registrada em ligado (nada sai em sombra)
  select count(*) into v_fsombra
    from public.whatsapp_send_queue q
    left join public.agenda_fornecedor_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-fornecedor' and (x.id is null or x.modo <> 'ligado');
  v_fsombra := v_fsombra + (select count(*) from public.agenda_fornecedor_mensagens x
                             where x.modo <> 'ligado' and (x.fila_id is not null or x.estado = 'enfileirada'));
  -- o que está na fila, saindo ou saiu fora da janela da mensagem (pela regra única); o que falhou não saiu
  select count(*) into v_ffora
    from public.whatsapp_send_queue q
    join public.agenda_fornecedor_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-fornecedor'
     and ((q.status in ('pending', 'sending', 'sent')
           and public._agenda_fornecedor_fora_da_janela(x.enviar_em, q.scheduled_for) is not null)
          or (q.sent_at is not null and public._agenda_fornecedor_fora_da_janela(x.enviar_em, q.sent_at) is not null));
  -- acima do teto: o que entrou na fila (ligado), por fornecedor no dia e na semana ISO, e no dia a todos
  with ent as (
    select x.fornecedor_id as f, (x.enviar_em at time zone 'America/Sao_Paulo')::date as dia
      from public.agenda_fornecedor_mensagens x
     where x.modo = 'ligado'
       and (x.fila_id is not null
            or exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-fornecedor' and q.source_ref_id = x.id))
  )
  select (select count(*) from (select e.f, e.dia from ent e group by 1, 2 having count(*) > cf.fornecedor_dia_max) a)
       + (select count(*) from (select e.f, date_trunc('week', e.dia) from ent e group by 1, 2
                                 having count(*) > cf.fornecedor_semana_max) b)
       + (select count(*) from (select e.dia from ent e group by 1 having count(*) > cf.fornecedor_total_dia_max) t)
    into v_fteto;
  select count(*) into v_fproib
    from public.agenda_fornecedor_mensagens x
   where public._agenda_fornecedor_texto_proibido(x.texto, x.service_order_id) is not null;
  select jsonb_build_object(
           'registradas_7d', count(*),
           'enfileiradas_7d', count(*) filter (where x.estado = 'enfileirada'),
           'em_teste_7d', count(*) filter (where x.modo = 'sombra'),
           'recusadas_7d_por_motivo', coalesce((
             select jsonb_object_agg(t.recusa_motivo, t.n) from (
               select y.recusa_motivo, count(*) as n from public.agenda_fornecedor_mensagens y
                where y.estado = 'recusada' and (y.enviar_em at time zone 'America/Sao_Paulo')::date > p_hoje - 7
                group by y.recusa_motivo) t), '{}'::jsonb))
    into v_forn
    from public.agenda_fornecedor_mensagens x
   where (x.enviar_em at time zone 'America/Sao_Paulo')::date > p_hoje - 7;
  -- a cobertura: os itens críticos das OS que começam nas próximas material_inicio_dias, e quantos têm data (nível A a D)
  select jsonb_build_object(
           'itens_criticos_proximos', count(*),
           'com_previsao', count(*) filter (where e ->> 'nivel' <> 'E'),
           'pct', case when count(*) > 0 then round(100 * (count(*) filter (where e ->> 'nivel' <> 'E'))::numeric / count(*)) end)
    into v_cob
    from (select k.id from unnest(v_cart) k(id)
           where public._agenda_inicio_previsto(k.id, p_hoje) between p_hoje and p_hoje + cf.material_inicio_dias) o
    cross join lateral jsonb_array_elements(coalesce(public.os_prontidao(o.id, p_hoje) #> '{material,itens}', '[]'::jsonb)) e
   where coalesce((e ->> 'critico')::boolean, false);
  -- a espera: a mediana dos dias corridos da aprovação (a régua de os_carteira) até a 1ª compra (o dia dito ou o da OC),
  -- das OS aprovadas nos últimos 90 dias que já compraram
  select percentile_cont(0.5) within group (order by t.d) into v_med
    from (select min(coalesce(m.comprado_em, (po.created_at at time zone 'America/Sao_Paulo')::date))
                 - (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date as d
            from public.service_orders so
            join public.os_material m on m.service_order_id = so.id
            left join public.purchase_order_items poi on poi.id = m.purchase_order_item_id
            left join public.purchase_orders po on po.id = poi.purchase_order_id and po.status <> 'cancelled'
           where so.merged_into_id is null and so.status <> 'cancelled'
             and (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date
                 between p_hoje - 90 and p_hoje
           group by so.id
          having min(coalesce(m.comprado_em, (po.created_at at time zone 'America/Sao_Paulo')::date)) is not null) t;
  v_zeros4 := v_semdono = 0 and v_semorig = 0 and v_fsombra = 0 and v_ffora = 0 and v_fteto = 0 and v_fproib = 0;
  v_mat := jsonb_build_object(
    'modos', jsonb_build_object('material', cf.modo_material, 'detector', cf.modo_detector, 'fornecedor', cf.modo_fornecedor),
    'ultima_rodada', v_mrod -> 'ultima_rodada', 'rodou_nas_ultimas_2h', v_mrod -> 'rodou_nas_ultimas_2h',
    'erros_24h', v_mrod -> 'erros_24h',
    'remessas', v_rem, 'perguntas', v_mperg,
    'vinculo_sem_resposta_do_dono', v_semdono, 'previsao_sem_original', v_semorig,
    'detector', v_det,
    'fornecedor', v_forn || jsonb_build_object('na_fila_em_sombra', v_fsombra, 'fora_da_janela', v_ffora,
                                               'acima_do_teto', v_fteto, 'com_valor_ou_cliente', v_fproib),
    'cobertura', v_cob,
    'espera', jsonb_build_object('mediana_ate_comprar_90d', v_med));
  -- FASE 4: fim
  -- FASE 5: a mensagem ao cliente — o modo, as ondas e os tipos liberados, a rodada, as mensagens e a aprovação em 7 dias.
  -- Os "0 obrigatórios" (entram no ok pelo v_zeros4, para o ok ficar igual linha a linha): nada fora da janela (nem o que
  -- saiu fora dela), nada em feriado ou domingo, nada acima do teto, nada a menos do intervalo de outra, nada com texto
  -- proibido, nada na fila em teste, nada enviado sem a aprovação dos primeiros dias, nada crítico enviado sem a opção 2,
  -- nenhuma véspera com a OS aguardando peça, nenhum aviso de atraso depois da data dita, nenhum áudio que confirmou. As
  -- métricas não reprovam.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'cliente:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_crod from public.agenda_vigia_rodadas x where x.rotina = 'cliente';
  select coalesce(jsonb_object_agg(t.tipo, jsonb_build_object('registradas', t.reg, 'aguardando', t.agu, 'enviadas', t.env,
                                                              'recusadas_por_motivo', t.rec)), '{}'::jsonb)
    into v_cmsg
    from (select m.tipo, count(*) as reg, count(*) filter (where m.estado = 'aguardando_dono') as agu,
                 count(*) filter (where m.enviada_em is not null) as env,
                 coalesce((select jsonb_object_agg(y.recusa_motivo, y.n)
                             from (select z.recusa_motivo, count(*) as n from public.agenda_cliente_mensagens z
                                    where z.tipo = m.tipo and z.estado = 'recusada' and z.criada_em > p_agora - interval '7 days'
                                    group by z.recusa_motivo) y), '{}'::jsonb) as rec
            from public.agenda_cliente_mensagens m
           where m.criada_em > p_agora - interval '7 days'
           group by m.tipo) t;
  select jsonb_build_object(
           'pedidas_abertas', count(*) filter (where m.estado = 'aguardando_dono' and m.aprovacao in ('pedida', 'critica')),
           'vencidas_7d', count(*) filter (where m.aprovacao = 'vencida' and m.criada_em > p_agora - interval '7 days'),
           'aprovadas_7d', count(*) filter (where m.aprovacao = 'aprovada' and m.aprovada_em > p_agora - interval '7 days'),
           'seguradas_7d', count(*) filter (where m.aprovacao = 'segurada' and m.aprovada_em > p_agora - interval '7 days'))
    into v_caprov from public.agenda_cliente_mensagens m where m.modo = 'ligado';
  -- a janela (a regra única): o que está na fila, saindo ou saiu fora da janela da mensagem; o feriado e o domingo à parte
  select count(*) filter (where t.f is not null), count(*) filter (where t.f in ('feriado', 'domingo'))
    into v_cjan, v_cdom
    from (select coalesce(case when q.status in ('pending', 'sending', 'sent')
                               then public._agenda_cliente_fora_da_janela(x.enviar_em, q.scheduled_for) end,
                          case when q.sent_at is not null then public._agenda_cliente_fora_da_janela(x.enviar_em, q.sent_at) end) as f
            from public.whatsapp_send_queue q
            join public.agenda_cliente_mensagens x on x.id = q.source_ref_id
           where q.source = 'agenda-cliente') t;
  -- o teto: o que entrou na fila (ligado), por cliente no dia e na semana ISO, e no dia a todos
  with ent as (
    select m.client_id as c, (m.enviar_em at time zone 'America/Sao_Paulo')::date as dia
      from public.agenda_cliente_mensagens m
     where m.modo = 'ligado' and m.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta')
  )
  select (select count(*) from (select e.c, e.dia from ent e group by 1, 2 having count(*) > cf.cliente_dia_max) a)
       + (select count(*) from (select e.c, date_trunc('week', e.dia) from ent e group by 1, 2
                                 having count(*) > cf.cliente_semana_max) b)
       + (select count(*) from (select e.dia from ent e group by 1 having count(*) > cf.cliente_total_dia_max) t)
    into v_cteto;
  -- o intervalo: duas linhas agenda-cliente (na fila, saindo ou saídas) a menos de cliente_intervalo_min_s uma da outra
  select count(*) into v_cint
    from public.whatsapp_send_queue a
    join public.whatsapp_send_queue b
      on b.source = 'agenda-cliente' and b.id > a.id and b.status in ('pending', 'sending', 'sent')
     and abs(extract(epoch from coalesce(b.sent_at, b.scheduled_for) - coalesce(a.sent_at, a.scheduled_for)))
         < cf.cliente_intervalo_min_s
   where a.source = 'agenda-cliente' and a.status in ('pending', 'sending', 'sent');
  select count(*) into v_cproib
    from public.agenda_cliente_mensagens m where public._agenda_cliente_texto_proibido(m.texto) is not null;
  -- em teste nada entra na fila (nem linha da fila sem a mensagem registrada em ligado)
  select (select count(*) from public.whatsapp_send_queue q
            left join public.agenda_cliente_mensagens x on x.id = q.source_ref_id
           where q.source = 'agenda-cliente' and (x.id is null or x.modo <> 'ligado'))
       + (select count(*) from public.agenda_cliente_mensagens x
           where x.modo <> 'ligado' and (x.fila_id is not null or x.enviada_em is not null
                                         or x.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta')))
    into v_csombra;
  -- enviada sem a aprovação do dono quando o tipo ainda não somava os dias aprovados (ou a preparada pelo dono)
  select count(*) into v_csemap
    from public.agenda_cliente_mensagens m
   where m.modo = 'ligado' and m.enviada_em is not null and m.aprovacao <> 'aprovada'
     and (m.origem <> 'rodada'
          or (cf.cliente_aprovacao_dias > 0
              and (select count(distinct (y.aprovada_em at time zone 'America/Sao_Paulo')::date)
                     from public.agenda_cliente_mensagens y
                    where y.tipo = m.tipo and y.aprovacao = 'aprovada' and y.origem = 'rodada' and y.modo = 'ligado'
                      and y.aprovada_em < m.criada_em) < cf.cliente_aprovacao_dias));
  -- a crítica enviada sem a decisão "2) eu mando o aviso escrito"
  select count(*) into v_ccrit
    from public.agenda_cliente_mensagens m
    left join public.agenda_perguntas q on q.id = m.pergunta_id
   where m.enviada_em is not null
     and (m.aprovacao = 'critica'
          or (q.tipo = 'cliente_aviso' and not (q.estado = 'respondida' and q.opcao_escolhida = 2)));
  -- a véspera (M2/M4) enviada com a OS aguardando peça (no registro, ou pela última mudança de status antes do envio)
  select count(*) into v_cvesp
    from public.agenda_cliente_mensagens m
   where m.tipo in ('vespera', 'acesso') and m.enviada_em is not null
     and (m.base ->> 'status' = 'awaiting_parts'
          or (select a.status_depois from public.agenda_acoes a
               where a.service_order_id = m.service_order_id and a.tipo = 'status' and a.executada
                 and a.criada_em <= m.enviada_em
               order by a.criada_em desc, a.id desc limit 1) = 'awaiting_parts');
  -- o aviso de atraso enviado depois da data que o cliente ouviu
  select count(*) into v_cdepois
    from public.agenda_cliente_mensagens m
   where m.tipo = 'pode_atrasar' and m.enviada_em is not null and m.base ? 'prometido_ate'
     and (m.enviada_em at time zone 'America/Sao_Paulo')::date > (m.base ->> 'prometido_ate')::date;
  select count(*) into v_caudio
    from public.agenda_cliente_respostas r where r.tipo_msg = 'audio' and r.efeito = 'confirmou';
  -- as métricas (para depois; nenhuma reprova)
  select jsonb_build_object(
    'm6_antes_da_data_pct_90d', (
      select case when count(*) > 0 then round(100 * (count(*) filter (
               where (m.enviada_em at time zone 'America/Sao_Paulo')::date <= (m.base ->> 'prometido_ate')::date))::numeric
               / count(*)) end
        from public.agenda_cliente_mensagens m
       where m.tipo = 'pode_atrasar' and m.enviada_em > p_agora - interval '90 days' and m.base ? 'prometido_ate'),
    'aprovadas_sem_segurar_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where m.aprovacao = 'aprovada'))::numeric / count(*)) end
        from public.agenda_cliente_mensagens m
       where m.modo = 'ligado' and m.aprovacao in ('aprovada', 'segurada') and m.aprovada_em > p_agora - interval '30 days'),
    'resposta_24h_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where r.recebida_em <= m.enviada_em + interval '1 day'))::numeric
               / count(*)) end
        from public.agenda_cliente_mensagens m
        left join public.agenda_cliente_respostas r on r.id = m.resposta_id
       where m.modo = 'ligado' and m.enviada_em > p_agora - interval '30 days'
         and m.tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')),
    'sim_automatico_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where r.efeito = 'confirmou'))::numeric / count(*)) end
        from public.agenda_cliente_respostas r
       where r.modo = 'ligado' and r.recebida_em > p_agora - interval '30 days' and r.intencao = 'confirma'),
    'opt_outs_30d', (select count(*) from public.agenda_cliente_respostas r
                      where r.intencao = 'opt_out' and r.recebida_em > p_agora - interval '30 days'),
    'falhas_de_entrega_30d', (select count(*) from public.whatsapp_send_queue q
                               where q.source = 'agenda-cliente' and q.status = 'failed'
                                 and q.created_at > p_agora - interval '30 days'),
    'idas_perdidas_por_acesso_90d', (
      select jsonb_build_object('com_aviso', count(*) filter (where t.avisado), 'sem_aviso', count(*) filter (where not t.avisado))
        from (select distinct a.service_order_id, a.dia,
                     exists (select 1 from public.agenda_cliente_mensagens m
                              where m.service_order_id = a.service_order_id and m.tipo in ('vespera', 'acesso')
                                and m.enviada_em is not null and coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) = a.dia) as avisado
                from public.agenda_alocacoes a
               where a.resultado = 'nao_cumprido' and a.motivo = 'cliente_ou_bem' and a.dia > p_hoje - 90 and a.dia <= p_hoje) t))
    into v_cmet;
  v_zeros5 := v_cjan = 0 and v_cdom = 0 and v_cteto = 0 and v_cint = 0 and v_cproib = 0 and v_csombra = 0 and v_csemap = 0
              and v_ccrit = 0 and v_cvesp = 0 and v_cdepois = 0 and v_caudio = 0;
  v_zeros4 := v_zeros4 and v_zeros5;
  v_cli := jsonb_build_object(
    'modo', cf.modo_cliente, 'tipos_ligados', to_jsonb(cf.cliente_tipos_ligados),
    'tipos_liberados', to_jsonb(array(select t from unnest(array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento',
                                                                  'pode_atrasar', 'nova_data', 'pronto', 'pronto_lembrete',
                                                                  'pos_servico', 'mudanca_no_dia']) t
                                       where public._agenda_cliente_tipo_liberado(t))),
    'ultima_rodada', v_crod -> 'ultima_rodada', 'rodou_nas_ultimas_2h', v_crod -> 'rodou_nas_ultimas_2h',
    'erros_24h', v_crod -> 'erros_24h',
    'mensagens_7d', jsonb_build_object('por_tipo', v_cmsg),
    'aprovacao', v_caprov,
    'fora_da_janela', v_cjan, 'em_feriado_ou_domingo', v_cdom, 'acima_do_teto', v_cteto, 'intervalo_curto', v_cint,
    'com_texto_proibido', v_cproib, 'na_fila_em_sombra', v_csombra, 'sem_aprovacao_no_periodo', v_csemap,
    'critica_sem_decisao', v_ccrit, 'vespera_com_os_aguardando_peca', v_cvesp, 'aviso_depois_da_data', v_cdepois,
    'audio_que_confirmou', v_caudio,
    'metricas', v_cmet);
  -- FASE 5: fim
  -- CORREÇÃO FASE 6: (C2) item 12: os zeros obrigatórios de antes do aprendizado (o bloco do aprendizado os junta aos dele; o
  -- bloco da C2 depois dele refaz essa junta com as janelas de agenda_config)
  v_z4_antes := v_zeros4;
  -- CORREÇÃO FASE 6: fim
  -- FASE 6: (P6) o aprendizado (spec-fase6 §11) — o modo, a lista, a rodada, os itens e as métricas. Os "0 obrigatórios"
  -- (entram no ok pelo v_zeros4, como os das Fases 4 e 5): nada em uso com menos medidas que o mínimo; nada que a ÚLTIMA
  -- rodada gravou em uso com o modo dela fora de ligado ou o item fora da lista dela (logo depois de o dono desligar, o leitor
  -- já devolve o padrão; a linha muda na rodada seguinte); nenhuma troca grande que entrou sozinha (as ações da vigia em 7 dias
  -- contra os limites de hoje: a regra de _agenda_aprendizado_troca_cabe, que não tem porta para quem lê a saúde); nenhuma
  -- rodada atrasada (depois da 1ª, nenhuma em 26 h); nenhuma medida sem classe; nenhum fator fora de [fator_min, fator_max].
  -- Os erros de aprender:% em 24 h e as métricas não reprovam.
  select x.p_agora, x.p_hoje, x.contagens into v_arod
    from public.agenda_vigia_rodadas x where x.rotina = 'aprender'
   order by x.p_agora desc, x.rodou_em desc, x.id desc limit 1;
  select count(*) into v_apeq
    from public.agenda_aprendizado a
   where a.estado in ('em_uso', 'pergunta', 'travado') and a.em_uso is not null and a.n < a.n_min;
  select count(*) into v_afora
    from public.agenda_aprendizado a
   where v_arod.p_agora is not null and a.estado = 'em_uso' and a.em_uso is not null and a.calculado_em >= v_arod.p_agora
     and (coalesce(v_arod.contagens ->> 'modo_aprendizado', '') <> 'ligado'
          or not coalesce(v_arod.contagens -> 'ligados' ? public._agenda_aprendizado_da_lista(a.item), false));
  select count(*) into v_agrande
    from public.agenda_acoes a
   where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada and a.criada_em > p_agora - interval '7 days'
     and not coalesce(case a.antes ->> 'item'
           when 'fator' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.fator_troca_max
           when 'mo' then (a.antes ->> 'valor')::numeric > 0
                          and abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                              / (a.antes ->> 'valor')::numeric <= cf.mo_troca_max
           when 'fornecedor_atraso' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                         <= cf.fornecedor_troca_max_du
           when 'fornecedor_prazo' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                        <= cf.fornecedor_troca_max_du
           when 'capacidade_dono' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                       <= cf.capacidade_troca_max
           when 'aviso_folga' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.aviso_troca_max_du
           when 'presenca' then a.antes ->> 'nivel' in ('fina', 'sistema')
         end, false);
  v_aatras := case when v_arod.p_agora is not null and v_arod.p_agora < p_agora - interval '26 hours' then 1 else 0 end;
  select count(*) into v_asemcl from public.agenda_medidas_os m where m.classe_bem is null or m.classe_sistema is null;
  select count(*) into v_afat
    from public.agenda_aprendizado a
   where a.item = 'fator'
     and ((a.calculado is not null and a.calculado not between cf.fator_min and cf.fator_max)
          or (a.em_uso is not null and a.em_uso not between cf.fator_min and cf.fator_max));
  -- as métricas (para depois; nenhuma reprova)
  select jsonb_build_object(
    'itens', coalesce((select jsonb_object_agg(t.item, jsonb_build_object('chaves', t.chaves, 'n_max', t.n_max, 'n_min', t.n_min,
                                                                         'estados', t.estados))
                         from (select a.item, count(*) as chaves, max(a.n) as n_max, max(a.n_min) as n_min,
                                      (select jsonb_object_agg(s.estado, s.n)
                                         from (select b.estado, count(*) as n from public.agenda_aprendizado b
                                                where b.item = a.item group by b.estado) s) as estados
                                 from public.agenda_aprendizado a group by a.item) t), '{}'::jsonb),
    'medidas', (select jsonb_build_object('total', count(*), 'validas', count(*) filter (where m.valida),
                                          'invalidas', coalesce((select jsonb_object_agg(y.motivo, y.n)
                                                                   from (select z.motivo, count(*) as n from public.agenda_medidas_os z
                                                                          where not z.valida
                                                                            and z.concluida_em > p_hoje - cf.aprender_janela_dias
                                                                          group by z.motivo) y), '{}'::jsonb))
                  from public.agenda_medidas_os m where m.concluida_em > p_hoje - cf.aprender_janela_dias),
    'trocas_30d', jsonb_build_object(
      'sozinhas', (select count(*) from public.agenda_acoes a
                    where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada and a.criada_em > p_agora - interval '30 days'),
      'perguntas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.criada_em > p_agora - interval '30 days'),
      'decididas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.estado = 'respondida' and q.respondida_em > p_agora - interval '30 days'),
      'desfeitas', (select count(*) from public.agenda_acoes a
                     where a.tipo = 'aprendizado' and a.desfeita_em > p_agora - interval '30 days')),
    -- o erro do fator: das OS válidas concluídas depois que o fator da classe delas passou a valer, quantas ficaram dentro dele
    'erro_do_fator', (select case when count(*) > 0 then jsonb_build_object('dentro', count(*) filter (where t.fator <= t.uso),
                                                                           'medidas', count(*),
                                                                           'pct', round(100 * (count(*) filter (where t.fator <= t.uso))::numeric / count(*))) end
                        from (select m.fator, u.em_uso as uso
                                from public.agenda_medidas_os m
                                cross join lateral (
                                  select a.em_uso, a.em_uso_desde from public.agenda_aprendizado a
                                   where a.item = 'fator' and a.estado = 'em_uso'
                                     and a.chave in (m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                     'bem:' || m.classe_bem, 'todas')
                                   order by array_position(array[m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                                 'bem:' || m.classe_bem, 'todas'], a.chave)
                                   limit 1) u
                               where m.valida and m.concluida_em >= (u.em_uso_desde at time zone 'America/Sao_Paulo')::date) t),
    -- a pontualidade com o cliente antes e depois de a folga do aviso valer
    'pontualidade_folga', (select case when f.desde is not null then jsonb_build_object(
                                     'desde', f.desde,
                                     'antes_pct', (select round(100 * avg((m.atraso_cliente_du <= 0)::int)) from public.agenda_medidas_os m
                                                    where m.atraso_cliente_du is not null and m.concluida_em < f.desde),
                                     'depois_pct', (select round(100 * avg((m.atraso_cliente_du <= 0)::int)) from public.agenda_medidas_os m
                                                     where m.atraso_cliente_du is not null and m.concluida_em >= f.desde)) end
                             from (select (min(a.em_uso_desde) at time zone 'America/Sao_Paulo')::date as desde
                                     from public.agenda_aprendizado a where a.item = 'aviso_folga' and a.em_uso is not null) f),
    -- parar (§11): o item que o dono desfez 2 vezes em 4 semanas (recomendar tirá-lo da lista; a decisão é dele)
    'desfeito_2x_em_4_semanas', coalesce((select jsonb_agg(t.item order by t.item)
                                            from (select a.antes ->> 'item' as item from public.agenda_acoes a
                                                   where a.tipo = 'aprendizado' and a.desfeita_em > p_agora - interval '28 days'
                                                   group by 1 having count(distinct a.desfeita_em) >= 2) t), '[]'::jsonb))
    into v_amet;
  v_zeros6 := v_apeq = 0 and v_afora = 0 and v_agrande = 0 and v_aatras = 0 and v_asemcl = 0 and v_afat = 0;
  v_zeros4 := v_zeros4 and v_zeros6;
  v_apr := jsonb_build_object(
    'modo', cf.modo_aprendizado, 'ligados', to_jsonb(cf.aprendizado_ligados),
    'ultima_rodada', v_arod.p_agora,
    'rodou_hoje', exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'aprender' and x.p_hoje = p_hoje),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.action like 'aprender:%'
                     and e.last_seen_at >= least(p_agora, now()) - interval '1 day'),
    'em_uso_com_amostra_pequena', v_apeq, 'em_uso_fora_de_ligado', v_afora, 'troca_grande_sem_pergunta', v_agrande,
    'rodada_atrasada', v_aatras, 'medida_sem_classe', v_asemcl, 'fator_fora_dos_limites', v_afat,
    'metricas', v_amet);
  -- FASE 6: fim
  -- CORREÇÃO FASE 6: (C2) item 12: as janelas do aprendizado na saúde vêm de agenda_config (eram números escritos aqui): a
  -- troca grande que entrou sozinha, nas ações dos últimos aprender_saude_dias (era 7 dias); a rodada atrasada, sem rodada há
  -- mais de aprender_atraso_h (era 26 h); as trocas das métricas, nos últimos aprender_parar_dias (era 30 dias; a chave
  -- trocas_30d fica com o nome); o item desfeito 2 vezes dentro de aprender_trava_dias (era 28 dias, as "4 semanas" da §11).
  -- As contas de cima não valem mais: refeitas aqui com o parâmetro (com os DEFAULTs, o mesmo resultado), e com elas os
  -- zeros, o ok e o bloco aprendizado.
  select count(*) into v_agrande
    from public.agenda_acoes a
   where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada
     and a.criada_em > p_agora - make_interval(days => cf.aprender_saude_dias)
     and not coalesce(case a.antes ->> 'item'
           when 'fator' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.fator_troca_max
           when 'mo' then (a.antes ->> 'valor')::numeric > 0
                          and abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                              / (a.antes ->> 'valor')::numeric <= cf.mo_troca_max
           when 'fornecedor_atraso' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                         <= cf.fornecedor_troca_max_du
           when 'fornecedor_prazo' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                        <= cf.fornecedor_troca_max_du
           when 'capacidade_dono' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                       <= cf.capacidade_troca_max
           when 'aviso_folga' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.aviso_troca_max_du
           when 'presenca' then a.antes ->> 'nivel' in ('fina', 'sistema')
         end, false);
  v_aatras := case when v_arod.p_agora is not null
                        and v_arod.p_agora < p_agora - make_interval(hours => cf.aprender_atraso_h) then 1 else 0 end;
  v_amet := v_amet || jsonb_build_object(
    'trocas_30d', jsonb_build_object(
      'sozinhas', (select count(*) from public.agenda_acoes a
                    where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada
                      and a.criada_em > p_agora - make_interval(days => cf.aprender_parar_dias)),
      'perguntas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.criada_em > p_agora - make_interval(days => cf.aprender_parar_dias)),
      'decididas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.estado = 'respondida'
                       and q.respondida_em > p_agora - make_interval(days => cf.aprender_parar_dias)),
      'desfeitas', (select count(*) from public.agenda_acoes a
                     where a.tipo = 'aprendizado' and a.desfeita_em > p_agora - make_interval(days => cf.aprender_parar_dias))),
    'desfeito_2x_em_4_semanas', coalesce((select jsonb_agg(t.item order by t.item)
                                            from (select a.antes ->> 'item' as item from public.agenda_acoes a
                                                   where a.tipo = 'aprendizado'
                                                     and a.desfeita_em > p_agora - make_interval(days => cf.aprender_trava_dias)
                                                   group by 1 having count(distinct a.desfeita_em) >= 2) t), '[]'::jsonb));
  v_zeros6 := v_apeq = 0 and v_afora = 0 and v_agrande = 0 and v_aatras = 0 and v_asemcl = 0 and v_afat = 0;
  v_zeros4 := v_z4_antes and v_zeros6;
  v_apr := v_apr || jsonb_build_object('troca_grande_sem_pergunta', v_agrande, 'rodada_atrasada', v_aatras, 'metricas', v_amet);
  -- CORREÇÃO FASE 6: fim
  -- FASE 7: (7a P7, spec §11) o bloco gestor: os modos efetivos, a última rodada (rotina gestor), os erros de gestor:% em 24 h, os
  -- zeros obrigatórios (entram no ok, salvo prazo_vencido_sem_mostrar, que só se conta: a pergunta fica aberta) e os números. Os
  -- zeros do que o gestor muda sozinho contam a partir do OK de ligar (marcar_sozinho_desde): antes dele não há o que contar.
  -- E (aviso do P6) o erro do fator só com as medidas que têm fator: a medida por estimativa é válida e não tem fator.
  v_gdesde := cf.marcar_sozinho_desde;
  v_gmodos := jsonb_build_object('marcar', public._agenda_gestor_modo('marcar'), 'encaixe', public._agenda_gestor_modo('encaixe'),
                                 'revisao', public._agenda_gestor_modo('revisao'), 'compre_ate', public._agenda_gestor_modo('compre_ate'),
                                 'vaga', public._agenda_gestor_modo('vaga'), 'so_propor', cf.gestor_so_propor, 'desde', v_gdesde);
  select max(x.p_agora) as ultima,
         count(*) filter (where x.p_agora > p_agora - interval '1 day' and x.p_agora <= p_agora) as n24,
         coalesce(bool_or(x.p_hoje = p_hoje and x.contagens ? 'diaria'), false) as diaria_hoje,
         (array_agg(x.erros order by x.p_agora desc, x.rodou_em desc))[1] as erros_ult
    into v_gult from public.agenda_vigia_rodadas x where x.rotina = 'gestor';
  v_gz := jsonb_build_object(
    -- o dia que o cliente ouviu e o dia que a equipe já sabia, mudados sem a pergunta crítica (a regra de _agenda_criticidade_da_acao)
    'zona_travada_mexida', (select count(*) from public.agenda_acoes a
                             where v_gdesde is not null and a.criada_em >= v_gdesde and a.executada and not a.critica
                               and a.origem in ('motor', 'vigia', 'conferencia')
                               and a.tipo in ('publicar', 'criar', 'mover', 'cancelar', 'promover_reserva', 'soltar_reserva')
                               and public._agenda_criticidade_da_acao(a.id) = 'dia_prometido'),
    'dia_avisado_sem_pergunta', (select count(*) from public.agenda_acoes a
                                  where v_gdesde is not null and a.criada_em >= v_gdesde and a.executada and not a.critica
                                    and a.origem in ('motor', 'vigia', 'conferencia')
                                    and a.tipo in ('publicar', 'criar', 'mover', 'cancelar', 'promover_reserva', 'soltar_reserva')
                                    and public._agenda_criticidade_da_acao(a.id) = 'dia_avisado'),
    -- marcada pela estimativa sem a pergunta que ela pedia (grande, começada/parada, sem mão de obra, peça embutida)
    'estimativa_sem_pergunta', case when not public._agenda_gestor_regra('estimativa') then 0 else (
       select count(*) from (select distinct a.service_order_id as os from public.agenda_alocacoes a
                               left join public.os_planejamento pl on pl.service_order_id = a.service_order_id
                              where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
                                and a.resultado is null and a.duracao_fonte = 'orcamento' and pl.dias is null) o
        where coalesce(public._agenda_gestor_estimativa(o.os, p_hoje) ->> 'motivo', '') in ('grande', 'situacao', 'sem_base', 'embutida')) end,
    'prazo_em_critica', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.critica and q.veto_ate is not null),
    'prazo_em_dia_prometido', (select count(*) from public.agenda_perguntas q
                                where q.estado = 'aberta' and q.veto_ate is not null and q.tipo = 'dia_prometido'),
    -- aprovada há mais de aprovada_sem_data_min sem dia, sem reserva, sem pergunta aberta e sem o motor ter dito por que fica de
    -- fora depois da aprovação (com o encaixe na aprovação ligado: antes dele, quem encaixa é a vigia e a publicação)
    'aprovada_sem_data', case when public._agenda_gestor_modo('encaixe') <> 'ligado' then 0 else (
       select count(*) from public.os_carteira(p_hoje) k join public.service_orders so on so.id = k.service_order_id
        where coalesce(so.converted_to_os_at, so.signed_at) is not null
          and coalesce(so.converted_to_os_at, so.signed_at) < p_agora - make_interval(mins => cf.aprovada_sem_data_min)
          and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = k.service_order_id
                           and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null)
          and not exists (select 1 from public.agenda_perguntas q where q.estado = 'aberta' and q.service_order_id = k.service_order_id)
          and not exists (select 1 from public.agenda_propostas pr cross join lateral jsonb_array_elements(coalesce(pr.fora, '[]'::jsonb)) f
                           where pr.criada_em >= coalesce(so.converted_to_os_at, so.signed_at)
                             and (f ->> 'os')::uuid = k.service_order_id)) end,
    -- sem rodada do gestor em 40 min, de 07:30 a 21:00 de dia útil, com algum modo do gestor fora de desligado
    'rodada_gestor_atrasada', case when (v_gmodos ->> 'marcar' <> 'desligado' or v_gmodos ->> 'encaixe' <> 'desligado'
                                         or v_gmodos ->> 'revisao' <> 'desligado' or v_gmodos ->> 'compre_ate' <> 'desligado')
                                        and public.agenda_dia_util(p_hoje)
                                        and (p_agora at time zone 'America/Sao_Paulo')::time between time '07:30' and time '21:00'
                                        and coalesce(v_gult.ultima < p_agora - interval '40 minutes', true) then 1 else 0 end,
    -- a mensagem ao cliente por estimativa que saiu sem o sim do dono antes de somar cliente_aprovacao_dias dias aprovados
    'cliente_estimativa_sem_aprovacao', (
       select count(*) from public.agenda_cliente_mensagens m
        where v_gdesde is not null and m.criada_em >= v_gdesde and m.base -> 'dados' ->> 'por_estimativa' = 'true'
          and m.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta') and m.aprovacao <> 'aprovada'
          and (select count(distinct (n.aprovada_em at time zone 'America/Sao_Paulo')::date) from public.agenda_cliente_mensagens n
                where n.tipo = m.tipo and n.base -> 'dados' ->> 'por_estimativa' = 'true' and n.aprovacao = 'aprovada'
                  and n.aprovada_em < m.criada_em) < cf.cliente_aprovacao_dias),
    -- a ficha de um dia por estimativa que saiu na janela de veto sem a pergunta ficha_estimativa mostrada (ou segurada com 2)
    'ficha_estimativa_sem_veto', (
       select count(*) from public.agenda_equipe_mensagens em
        where v_gdesde is not null and em.tipo = 'ficha' and em.modo = 'ligado'
          and em.estado in ('enfileirada', 'respondida', 'sem_resposta')
          and em.dia >= (v_gdesde at time zone 'America/Sao_Paulo')::date
          and em.dia < (v_gdesde at time zone 'America/Sao_Paulo')::date + cf.ficha_veto_dias
          and exists (select 1 from public.agenda_alocacoes a where a.payee_id = em.payee_id and a.dia = em.dia
                       and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.duracao_fonte = 'orcamento')
          and not exists (select 1 from public.agenda_perguntas q
                           where q.chave = 'ficha_estimativa:' || em.payee_id || ':' || em.dia and q.mostrada_vezes > 0
                             and q.opcao_escolhida is distinct from 2)),
    -- a rodada que mudou o dia de mais de gestor_k_os OS de uma vez sem a pergunta onda
    'onda_aplicada_sem_pergunta', (
       select count(*) from (select a.proposta_id from public.agenda_acoes a
                               where v_gdesde is not null and a.criada_em >= v_gdesde and a.executada and not a.critica
                                 and a.origem in ('motor', 'vigia') and a.tipo = 'mover' and a.proposta_id is not null
                               group by a.proposta_id having count(distinct a.service_order_id) > cf.gestor_k_os) p
        where not exists (select 1 from public.agenda_perguntas q where q.tipo = 'onda' and q.proposta_id = p.proposta_id)),
    -- o compromisso novo sem de onde veio a duração (o gatilho _agenda_alocacao_fonte grava em toda alocação nova)
    'alocacao_sem_fonte', (select count(*) from public.agenda_alocacoes a
                            where v_gdesde is not null and a.criado_em >= v_gdesde and a.tipo <> 'reserva' and a.duracao_fonte is null),
    -- a ação do gestor feita numa rodada em que o modo dela não estava ligado (estimar: marcar; reestimar e reparar: revisao)
    'regra_em_sombra_aplicada', (
       select count(*) from public.agenda_acoes a
        where a.executada and a.origem = 'vigia' and a.tipo in ('estimar', 'reestimar', 'reparar')
          and a.criada_em > p_agora - interval '7 days'
          and coalesce((select r.contagens -> 'modos' ->> case when a.tipo = 'estimar' then 'marcar' else 'revisao' end
                          from public.agenda_vigia_rodadas r
                         where r.rotina = 'gestor' and r.p_agora <= a.criada_em
                         order by r.p_agora desc, r.rodou_em desc limit 1), 'desligado') <> 'ligado'),
    -- a pergunta com prazo vencido que o dono nunca viu antes do prazo: fica aberta (aqui só se conta; não entra no ok)
    'prazo_vencido_sem_mostrar', (select count(*) from public.agenda_perguntas q
                                   where q.estado = 'aberta' and q.veto_ate is not null and q.veto_ate < p_agora
                                     and not coalesce(q.mostrada_vezes > 0 and q.mostrada_em < q.veto_ate, false)));
  -- (7f P7; R2, P2b, AG7-15; dentro do bloco do gestor da 7a: por isso a marca, não o bloco) prazo_em_critica: desde a 7f a crítica pode ter prazo e vencer (AG7-15, "sem resposta
  -- fica como ele propôs"). O zero passa a ser o prazo em crítica que nunca venceria: fora de veto_tipos ou com veto_espera. Hoje, 0 críticas na história: 0 nos dois jeitos.
  v_gz := v_gz || jsonb_build_object('prazo_em_critica', (select count(*) from public.agenda_perguntas q
                                                         where q.estado = 'aberta' and q.critica and q.veto_ate is not null
                                                           and (not q.tipo = any (cf.veto_tipos) or q.veto_espera is not null)));
  -- (7f: fim)
  v_gzeros := not exists (select 1 from jsonb_each(v_gz) z where z.key <> 'prazo_vencido_sem_mostrar' and (z.value)::text <> '0');
  v_ges := jsonb_build_object(
    'modos', v_gmodos, 'regras', to_jsonb(cf.marcar_regras),
    'ultima_rodada', v_gult.ultima, 'rodadas_24h', coalesce(v_gult.n24, 0), 'diaria_hoje', coalesce(v_gult.diaria_hoje, false),
    'erros_ultima_rodada', coalesce(v_gult.erros_ult, 0),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.action like 'gestor:%' and e.last_seen_at >= least(p_agora, now()) - interval '1 day'),
    'zeros_ok', v_gzeros,
    'numeros', jsonb_build_object(
      'os_por_estimativa', (select count(distinct a.service_order_id) from public.agenda_alocacoes a
                             where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
                               and a.resultado is null and a.duracao_fonte = 'orcamento'),
      'perguntas_com_prazo', jsonb_build_object(
        'abertas', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.veto_ate is not null),
        'vencidas', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.veto_ate is not null and q.veto_ate < p_agora),
        'respondidas_7d', (select count(*) from public.agenda_perguntas q where q.estado = 'respondida' and q.veto_ate is not null
                             and q.respondida_em > p_agora - interval '7 days'),
        'pelo_prazo_7d', (select count(*) from public.agenda_acoes a where a.tipo = 'estimar' and a.origem = 'vigia' and a.executada
                            and a.criada_em > p_agora - interval '7 days')),
      'compre_ate', jsonb_build_object(
        'gravados', (select count(*) from public.os_material m where m.compre_ate is not null),
        'cobrados', (select count(*) from public.os_material m where m.cobrado_vezes > 0),
        'empurrados', (select count(*) from public.os_material m where m.empurrada_vezes > 0)),
      'fichas_seguradas_7d', (select count(*) from public.agenda_equipe_mensagens em
                               where em.recusa_motivo = 'veto' and em.criada_em > p_agora - interval '7 days'))) || v_gz;
  v_amet := v_amet || jsonb_build_object(
    'erro_do_fator', (select case when count(*) > 0 then jsonb_build_object('dentro', count(*) filter (where t.fator <= t.uso),
                                                                           'medidas', count(*),
                                                                           'pct', round(100 * (count(*) filter (where t.fator <= t.uso))::numeric / count(*))) end
                        from (select m.fator, u.em_uso as uso
                                from public.agenda_medidas_os m
                                cross join lateral (
                                  select a.em_uso, a.em_uso_desde from public.agenda_aprendizado a
                                   where a.item = 'fator' and a.estado = 'em_uso'
                                     and a.chave in (m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                     'bem:' || m.classe_bem, 'todas')
                                   order by array_position(array[m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                                 'bem:' || m.classe_bem, 'todas'], a.chave)
                                   limit 1) u
                               where m.valida and m.fator is not null
                                 and m.concluida_em >= (u.em_uso_desde at time zone 'America/Sao_Paulo')::date) t));
  v_apr := v_apr || jsonb_build_object('metricas', v_amet);
  v_gr := jsonb_build_object(
    -- os zeros obrigatórios da execução (a Fase 3), do material e da mensagem ao fornecedor (a Fase 4) e os do gestor entram no ok
    'ok', v_sem = 0 and (v_regra ->> 'n')::int = 0 and v_choques = 0
          and v_teto = 0 and v_janela = 0 and v_semconf = 0 and v_sobre = 0 and coalesce(v_semrec, 0) = 0 and v_pay = 0
          and v_zeros4
          and v_gzeros,
    'modos', jsonb_build_object('leitura', cf.modo_leitura, 'proposta', cf.modo_proposta, 'vigia', cf.modo_vigia),
    'vigia', v_vig, 'hoje', v_hoje, 'criticas', v_crit, 'perguntas', v_perg, 'propostas', v_prop, 'plano', v_plano,
    'invariantes', v_inv, 'fechamento', v_fech,
    'rotina', v_rot, 'equipe', v_eq, 'diarias', v_dia, 'conclusao', v_conc, 'marcos', v_marcos, 'comissao', v_com,
    'modos_fase3', jsonb_build_object('equipe', cf.modo_equipe, 'diaria', cf.modo_diaria),
    'cliente', v_cli,
    'aprendizado', v_apr,
    'material', v_mat,
    'gestor', v_ges);
  -- FASE 7b (P5, §5.4, R4.3(g); dentro do bloco do gestor da 7a, que monta a saída e volta aqui — por isso sem os dois-pontos depois
  -- de "7b": os tiradores de antes tiram o bloco do gestor inteiro e não o leem como bloco próprio): a chave equipe_dias
  -- (_agenda_saude_equipe7b: as mensagens dias à equipe, a dupla no plano, quem nunca fica sozinho, o sábado, o dono numa vaga e a
  -- resposta gravada), com os zeros obrigatórios no ok. Sem os modos da 7b, os zeros são 0 e o ok é o de antes.
  v_gr := v_gr || jsonb_build_object('equipe_dias', public._agenda_saude_equipe7b(p_hoje, p_agora));
  v_gr := jsonb_set(v_gr, '{ok}', to_jsonb(coalesce((v_gr ->> 'ok')::boolean, false)
                                            and coalesce((v_gr #>> '{equipe_dias,zeros_ok}')::boolean, true)));
  -- FASE 7b (P5): fim
  -- (7d P8; §11, R6.3-11; dentro do bloco do gestor: por isso a marca, não o bloco) a chave local (_agenda_saude_local), com os zeros obrigatórios no ok. Sem os modos da 7d, os
  -- zeros são 0 e o ok é o de antes.
  v_gr := v_gr || jsonb_build_object('local', public._agenda_saude_local(p_hoje, p_agora));
  v_gr := jsonb_set(v_gr, '{ok}', to_jsonb(coalesce((v_gr ->> 'ok')::boolean, false)
                                            and coalesce((v_gr #>> '{local,zeros_ok}')::boolean, true)));
  -- O M11 na lista dos liberados (o recado do P6): aqui, e não na lista dos 11 lá em cima, que fica dentro do bloco da Fase 5
  if public._agenda_cliente_tipo_liberado('onde_fica') then
    v_gr := jsonb_set(v_gr, '{cliente,tipos_liberados}', (v_gr #> '{cliente,tipos_liberados}') || '["onde_fica"]'::jsonb);
  end if;
  -- (7d: fim)
  -- (7f P7; §11, R8.13; dentro do bloco do gestor: por isso a marca, não o bloco) a chave comunicacao (_agenda_saude_comunicacao), com os zeros obrigatórios no ok. Sem os modos
  -- da 7f e sem nada do que eles fazem, os zeros são 0 e o ok é o de antes.
  v_gr := v_gr || jsonb_build_object('comunicacao', public._agenda_saude_comunicacao(p_hoje, p_agora));
  v_gr := jsonb_set(v_gr, '{ok}', to_jsonb(coalesce((v_gr ->> 'ok')::boolean, false)
                                            and coalesce((v_gr #>> '{comunicacao,zeros_ok}')::boolean, true)));
  -- (7f: fim)
  -- (7f P6; dentro do bloco do gestor: por isso a marca, não o bloco) o M12 na lista dos liberados, como o M11 da 7d: aqui, e não na lista dos 11 lá em cima,
  -- que fica dentro do bloco da Fase 5. Só a contagem: a semana nunca entra em cliente_tipos_ligados por aqui (o ligar é do dono)
  if public._agenda_cliente_tipo_liberado('semana') then
    v_gr := jsonb_set(v_gr, '{cliente,tipos_liberados}', (v_gr #> '{cliente,tipos_liberados}') || '["semana"]'::jsonb);
  end if;
  -- (7f: fim)
  return v_gr;
  -- FASE 7: fim
  return jsonb_build_object(
    -- FASE 3: os zeros obrigatórios da execução entram no ok.
    'ok', v_sem = 0 and (v_regra ->> 'n')::int = 0 and v_choques = 0
          and v_teto = 0 and v_janela = 0 and v_semconf = 0 and v_sobre = 0 and coalesce(v_semrec, 0) = 0 and v_pay = 0
          -- FASE 4: os zeros obrigatórios do material e da mensagem ao fornecedor entram no ok.
          and v_zeros4,
          -- FASE 4: fim
    'modos', jsonb_build_object('leitura', cf.modo_leitura, 'proposta', cf.modo_proposta, 'vigia', cf.modo_vigia),
    'vigia', v_vig, 'hoje', v_hoje, 'criticas', v_crit, 'perguntas', v_perg, 'propostas', v_prop, 'plano', v_plano,
    'invariantes', v_inv, 'fechamento', v_fech,
    -- FASE 3
    'rotina', v_rot, 'equipe', v_eq, 'diarias', v_dia, 'conclusao', v_conc, 'marcos', v_marcos, 'comissao', v_com,
    'modos_fase3', jsonb_build_object('equipe', cf.modo_equipe, 'diaria', cf.modo_diaria),
    -- FASE 5: a mensagem ao cliente
    'cliente', v_cli,
    -- FASE 5: fim
    -- FASE 6: o aprendizado
    'aprendizado', v_apr,
    -- FASE 6: fim
    -- FASE 4: o material
    'material', v_mat);
    -- FASE 4: fim
end;
$function$;
comment on function public.agenda_saude(date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): a conferência depois de cada deploy e o painel da sombra — {ok, modos, vigia (última rodada, rodou nas últimas 2 h, erros em 24 h no app_error_logs context agenda, rodadas em 24 h), hoje (publicar, criar, mover, cancelar, promover, soltar, status, resultado, desfeitas, sombra), criticas (abertas, respondidas em 7 dias, sem_decisao e pela_regra_sem_decisao — têm de ser 0), perguntas (abertas por tipo, mostradas hoje), propostas, plano (vigentes futuras, OS programadas, reservas, sem registro em 7 dias), invariantes (vigente de OS fora da carteira, espelho divergente em ligado, choques = 0), fechamento (leu o plano hoje: resumo_tarde.detalhe.agenda; linhas mostradas)}. Leitura (invoker): authenticated (a RLS do admin vale) e service_role. Fase 3: a vigia lê só as rodadas dela (rotina = vigia); blocos rotina (última rodada, rodou nas últimas 2 h, erros 24 h), equipe (mensagens e recusas de hoje; acima_do_teto e fora_da_janela — também o que saiu fora dela — têm de ser 0), diarias (lançadas e em teste em 7 dias, perguntas abertas; sem_confirmacao e sobrescreveu_turno têm de ser 0), conclusao (pela agenda e desfeitas em 7 dias; sem_recebivel_quando_devia = 0, só para quem lê a releitura), marcos (N4), comissao (pagamento desligado; payables de comissão de técnico em 7 dias = 0) e modos_fase3; o ok inclui esses zeros. Fase 4 (P5): o bloco material — modos (material, detector, fornecedor), a rodada do material (rotina = material: última, rodou nas últimas 2 h, erros 24 h em material:%), remessas (a caminho, sem resposta, ligadas/sem serviço/chegaram em 7 dias), perguntas (as abertas da Fase 4 por tipo; pix_na_semana), detector (agenda_detector_precisao dos últimos 14 dias — só para administrador/financeiro ou sem login —, aplicados e desfeitos em 7 dias), fornecedor (registradas, enfileiradas, em teste e recusadas por motivo em 7 dias), cobertura (itens críticos das OS que começam nas próximas material_inicio_dias e quantos têm data, nível A–D), espera (mediana da aprovação à 1ª compra, OS aprovadas em 90 dias); os zeros obrigatórios entram no ok: vinculo_sem_resposta_do_dono, previsao_sem_original e, do fornecedor, na_fila_em_sombra, fora_da_janela, acima_do_teto e com_valor_ou_cliente. Fase 5 (P3): o bloco cliente — modo, tipos_ligados, tipos_liberados (somaram cliente_aprovacao_dias dias aprovados), a rodada do cliente (rotina = cliente: última, rodou nas últimas 2 h, erros 24 h em cliente:%), mensagens_7d por tipo (registradas, aguardando, enviadas, recusadas por motivo), aprovacao (pedidas abertas, vencidas, aprovadas e seguradas em 7 dias) e as métricas (M6 antes da data, aprovadas sem segurar, resposta em 1 dia, SIM automático, opt-outs, falhas de entrega, idas perdidas por acesso com e sem véspera); os zeros obrigatórios entram no ok: fora_da_janela, em_feriado_ou_domingo, acima_do_teto, intervalo_curto, com_texto_proibido, na_fila_em_sombra, sem_aprovacao_no_periodo, critica_sem_decisao, vespera_com_os_aguardando_peca, aviso_depois_da_data e audio_que_confirmou. Fase 6 (P6): a chave aprendizado — o modo, a lista, a última rodada, os erros de aprender:% em 24 h, os 6 zeros (em_uso_com_amostra_pequena, em_uso_fora_de_ligado, troca_grande_sem_pergunta, rodada_atrasada, medida_sem_classe, fator_fora_dos_limites; entram no ok) e as métricas (itens, medidas, trocas em 30 dias, o erro do fator, a pontualidade antes e depois da folga, o item desfeito 2 vezes em 4 semanas). CORREÇÃO FASE 6 (C2, item 12): as janelas do aprendizado vêm de agenda_config — a troca grande em aprender_saude_dias, a rodada atrasada em aprender_atraso_h, as métricas das trocas em aprender_parar_dias e o desfeito 2 vezes em aprender_trava_dias. FASE 7 (7a P7, spec §11): a chave gestor — os modos efetivos (marcar, encaixe, revisao, compre_ate, vaga, so_propor, desde), as regras, a última rodada (rotina gestor), as rodadas em 24 h, se os passos diários rodaram hoje, os erros de gestor:% em 24 h, os zeros obrigatórios (entram no ok: zona_travada_mexida e dia_avisado_sem_pergunta pela regra de _agenda_criticidade_da_acao, estimativa_sem_pergunta, prazo_em_critica, prazo_em_dia_prometido, aprovada_sem_data, rodada_gestor_atrasada, cliente_estimativa_sem_aprovacao, ficha_estimativa_sem_veto, onda_aplicada_sem_pergunta, alocacao_sem_fonte, regra_em_sombra_aplicada; os do que o gestor muda sozinho contam a partir de marcar_sozinho_desde) e prazo_vencido_sem_mostrar (só se conta: fica fora do ok), e os números (OS por estimativa, perguntas com prazo abertas/vencidas/respondidas/aplicadas pelo prazo, compre até gravados/cobrados/empurrados, fichas seguradas). E o erro do fator (métricas do aprendizado) só com as medidas que têm fator (a medida por estimativa é válida e não tem fator). FASE 7b (P5, §5.4, R4.3(g)): a chave equipe_dias (_agenda_saude_equipe7b): modos (dias, dupla, sabado, cadastro, chamar), a última rodada da semana da equipe e os erros de equipe_semana:% em 24 h, os zeros obrigatórios (entram no ok: dias_fora_da_janela, dias_duas_na_semana, dia_acima_do_teto, ficha_recusada_por_teto_com_dias, dupla_com_uma_pessoa — só a dita —, dupla_incompleta_com_gente_livre, novato_sozinho, sabado_sem_prazo, sabado_tarde, dono_em_vaga_sem_ok, resposta_sem_gravar) e os números (perguntadas × respondidas na última semana fechada e o %, adiadas pelo teto em 7 dias, a dupla inferida esperando o ajudante, duplas inferidas × ditas, sábados usados e em teste, a semana passada por pessoa: declarada × usada × cumprida). Sem os modos da 7b, os zeros são 0 e o ok é o de antes. FASE 7d (P8; §11, R6.3-11): a chave local (_agenda_saude_local), com os zeros obrigatórios no ok (acesso_sem_preparo, feriado_local_marcado, patio_acima_das_vagas, viagem_quebrada, rodada_local_atrasada); onde_fica em tipos_liberados. Sem os modos da 7d, os zeros são 0 e o ok é o de antes. FASE 7f (P7; §11, R2, R8.13): a chave comunicacao (_agenda_saude_comunicacao: os modos crus, a rodada comunicar, os zeros obrigatórios no ok e os números da comunicação); e o zero prazo_em_critica do gestor passa a ser a crítica com prazo fora de veto_tipos ou com veto_espera (a crítica pode vencer, AG7-15). FASE 7f (P6): a semana entra em cliente.tipos_liberados quando somar os dias aprovados (como o M11).';

-- ── 9. Portas ───────────────────────────────────────────────────────────────────────────────────────
-- As 2 novas: sem grant (quem as chama é a rodada do cliente, definer). As recriadas: as portas de antes, as de produção em 08/11 (sql/wf7f_p6_portas_prod),
-- repetidas para a migration valer sozinha.
revoke all on function public._agenda_cliente_camada(uuid, date),
                       public._agenda_cliente_semana(date, timestamptz),
                       public._agenda_cliente_registrar(text, text, uuid, date, jsonb, timestamptz, timestamptz, text, text, timestamptz, uuid),
                       public._agenda_cliente_revalidar(uuid, timestamptz),
                       public._agenda_cliente_confirmar(date, timestamptz),
                       public._agenda_cliente_material(date, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public.agenda_cliente_vigiar(date, timestamptz),
                       public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.agenda_cliente_vigiar(date, timestamptz),
                          public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamptz)
  to service_role;
revoke all on function public._agenda_cliente_texto(text, text, uuid, jsonb, date),
                       public._agenda_cliente_tipo_texto(text),
                       public._agenda_cliente_o_que(text, date),
                       public._agenda_cliente_a_mensagem(text, text, date),
                       public._agenda_ver_clientes(uuid, date),
                       public.agenda_cliente_preparar(uuid, text, text, boolean, text, date, timestamptz),
                       public.agenda_saude(date, timestamptz)
  from public, anon;
grant execute on function public._agenda_cliente_texto(text, text, uuid, jsonb, date),
                          public._agenda_cliente_tipo_texto(text),
                          public._agenda_cliente_o_que(text, date),
                          public._agenda_cliente_a_mensagem(text, text, date),
                          public._agenda_ver_clientes(uuid, date),
                          public.agenda_cliente_preparar(uuid, text, text, boolean, text, date, timestamptz),
                          public.agenda_saude(date, timestamptz)
  to authenticated, service_role;
