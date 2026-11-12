-- Agenda de Produção, Fase 7, etapa 7g ("Mostrar como pensou e provar o trabalho"), pacote P6: o placar da semana, o motivo "faltou ferramenta ou carro"
-- e a chave explicar da saúde. O banco conta, toda quinta, o que a agenda fez na semana medida (serviços prontos com data firme, o que marquei e o que o
-- dono corrigiu, as mudanças por zona, o plano cumprido, o real × estimado, as compras no "compre até", as perguntas, as mensagens e os dias perdidos),
-- guarda o placar e, com ele ligado, o leva na mensagem da quinta da 7f, antes das perguntas.
-- Spec: scratchpad agenda-pesquisa/spec-fase7g.md (§5.6, §6.5, §11 e o bloco R9, que vale sobre o corpo: R9.4-3, R9.5-12 a 15, 17 e 27, R9.12, R9.13 —
-- "AG7-27; sem agenda_bloco_do_fechamento; agenda_saude de 20261111100600; a peça placar em aviso-do-gestor.ts e _agenda_lote_texto"); o registro do pacote:
-- notas-fase7g.md (seção P6). Depende das Fases 1 a 6, das etapas 7a a 7d, da 7f inteira, da 7e inteira e da 7g até o P5 (20261112100000: modo_placar,
-- placar_janela, placar_semanas_hist, placar_min_linhas, agenda_placar_semanas, o motivo ferramenta no CHECK; 20261112100100: zona e degrau da ação;
-- 20261112100400: agenda_marcacoes, agenda_tipos_os e a rodada explicar, que chama _agenda_explicar_placar quando ela existe).
--
-- ═══ DDL — OK NOMEADO ═══ (6 funções recriadas; 7 funções novas, 2 delas SECURITY DEFINER com porta)
-- NÃO APLICADA. Existe para revisão e espera o OK.
--
-- POR QUE: o dono combinou um placar na mensagem da quinta (AG7-26): a prova do trabalho com os números do sistema, não com a palavra da IA. E o *dia não*
-- não tinha como dizer "faltou ferramenta ou carro" (AG7-27): o dia caía em "imprevisto" e a medida que decide a 7h não existia.
--
-- O QUE MUDA (com modo_placar desligado, nada na mensagem nem na leitura; em sombra, a rodada guarda o placar e a mensagem é a de antes, byte a byte):
--   1. _agenda_placar_periodo (nova): a semana medida — a semana passada inteira (seg a sáb) ou os últimos 7 dias (placar_janela, AG7-26); com p_semana, a dela.
--   2. _agenda_mensagens_da_agenda (nova): quantas mensagens da agenda entraram na fila no período, por destino, pelo source (R9.5-12: agenda-cliente e
--      agenda-confirmacao = cliente; agenda-equipe; agenda-fornecedor; agenda-dono e agenda (o acorde, chave agenda:<ação>) = dono), as enviadas e por dia
--      útil. Só contagem: nunca o texto.
--   3. _agenda_placar_numeros (nova): as 12 chaves do §5.6 e o freio, cada uma no seu bloco (falhou = {erro: true} e incompleto). A estimativa lê
--      razao_estimativa com motivo_razao nulo (R9.4-3); a cobertura roda _agenda_classe_agora por OS da carteira (1 vez por semana, R9.5-13); reserva nunca
--      conta (as marcações só registram meio-dia sem reserva; a cobertura e os dias perdidos tiram a reserva). Nada arredondado: só no texto.
--   4. _agenda_placar_texto (nova): o texto e a linha do §6.5. Na mensagem, linha sem dado sai; no completo (*agenda placar*), todas ficam, com o "sem
--      dado". Com o freio e nenhuma marcação minha, a 1ª linha diz isso. linhas = as linhas com dado, sem contar mensagens (placar_min_linhas, R9.4-3).
--      O corte, de baixo para cima: tipos, mensagens, perguntas, dias perdidos, compras, estimativa (e depois mudanças e plano cumprido); nunca a
--      cobertura nem as marcações.
--   5. agenda_placar (nova, SECURITY DEFINER, porta admin/financeiro ou service_role): a leitura do placar — a linha guardada quando a semana já fechou,
--      senão a conta de agora; em sombra, "Em teste: " na frente; o histórico das placar_semanas_hist semanas guardadas. Desligado: {modo: desligado}.
--      Quem a chama da conversa é o P7 (o foco).
--   6. _agenda_explicar_placar (nova): o passo placar da rodada explicar (P5), no dia_do_plano, com modo_placar fora de desligado: guarda a semana em
--      agenda_placar_semanas (versão + 1 e histórico só quando muda; 2× = 1×).
--   7. _agenda_saude_explicar (nova, SECURITY DEFINER, a porta da saúde) e agenda_saude (recriada de 20261111100600_agenda_fase7e_rodada.sql:379; md5 do corpo de antes 989537a8ac0baae6ed4b46133be4aa1a): a chave explicar,
--      molde comunicacao/margem (R9.5-17), com os zeros no ok: placar_atrasado, marcacao_aberta_vencida, rebaixar_sem_veto, rodada_atrasada e erros_dia
--      (app_error_logs de explicar:% em 1 dia). A linha entra depois do último "-- (7e: fim)", antes de return v_gr, com a marca "-- (7g".
--   8. _agenda_lote_texto (recriada de 20261109100300_agenda_fase7f_lote.sql:222; md5 do corpo de antes d36af4a7c0177eeaf8f8cb07f1a37960) e _agenda_comunicar_quinta (recriada de 20261109100300_agenda_fase7f_lote.sql:249; md5 do corpo de antes cc24667a155f6ec825485ec686cfb83c): com
--      modo_placar ligado, a quinta leva a peça placar ({texto, linha}) do placar guardado, antes das perguntas, se ele tem ao menos placar_min_linhas
--      linhas com dado; o montador (_shared/agenda/aviso-do-gestor.ts) e _agenda_lote_texto juntam igual (Q4p e o teste do montador). Depois que a fila
--      mandou, o ramo "já saiu" grava enviado_em quando o texto que saiu leva o placar (R9.5-27). Sem mudança e sem pergunta, a quinta continua sem sair:
--      nenhuma mensagem só de placar (R9.F-10). agenda_aviso_enfileirar e agenda-comunicar.ts não mudam de contrato. agenda_bloco_do_fechamento não é
--      recriada (R9.5-14: AG7-22 = propria).
--   9. _agenda_motivo_dito (recriada de 20261025100300_agenda_fase2_conferencia_vigia.sql:84; md5 do corpo de antes c6d11975b998f80ed20e44221dba4c8f), _agenda_motivo_texto (recriada de 20261025100300_agenda_fase2_conferencia_vigia.sql:116; md5 do corpo de antes e83650d34e2c15dd698e4c2656b13209) e
--      agenda_conferir_dia (recriada de 20261025100300_agenda_fase2_conferencia_vigia.sql:551; md5 do corpo de antes 0b47265e5022191567afc729ec956e3f, a 3ª cópia da lista, R9.5-15): o motivo ferramenta (AG7-27) — as palavras
--      ferramenta, ferramentas, carro, sem carro, veículo, faltou ferramenta, faltou carro; o texto "ferramenta ou carro"; e a palavra na pergunta "hoje ou
--      ontem?". O CHECK já tem ferramenta (20261112100000); capacidade_motivos fica sem ele (não é falta do dono). O TS: MOTIVOS_DO_DIA e MOTIVOS_DO_ANDAMENTO.
--
-- O QUE NÃO MUDA: o motor, a vigia, agenda_propor, as propostas, o que se grava fora de agenda_placar_semanas, as mensagens com modo_placar fora de ligado,
-- agenda_bloco_do_fechamento, agenda_aviso_enfileirar. Nenhum texto novo ao cliente. Nada de dinheiro. As palavras de motivo que já valiam dão o mesmo código
-- (as novas não colidem com nenhuma de antes: "faltou" sozinho segue equipe).
--
-- ORDEM DE LIGAR (spec R9.14): depois da 20261112100400. Aplicar sozinha não muda nada na mensagem: modo_placar fica como estiver (desligado até o dado
-- 20261112100990). O motivo ferramenta vale ao aplicar (é palavra nova, sem interruptor: AG7-27).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7g_placar.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261112100500
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; pelo publicar/exec/aplicar.sh, nunca db push: esta versão fica antes das 20261116* que já estão em produção):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261112100500_agenda_fase7g_placar.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261112100500', 'agenda_fase7g_placar');"
--
-- DESFAZER (na ordem): agenda_saude, _agenda_lote_texto, _agenda_comunicar_quinta, _agenda_motivo_dito, _agenda_motivo_texto e agenda_conferir_dia voltam
--   pelo corpo das origens (acima); depois
--   drop function if exists public._agenda_saude_explicar(date, timestamptz), public._agenda_explicar_placar(date, timestamptz),
--     public.agenda_placar(date, date, timestamptz), public._agenda_placar_texto(jsonb, date, date, text, integer),
--     public._agenda_placar_numeros(date, date, date), public._agenda_mensagens_da_agenda(date, date), public._agenda_placar_periodo(date, date);
--   As linhas de agenda_placar_semanas ficam (a tabela é da 20261112100000 e não se apaga).
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.

-- ── 1. A semana medida ──────────────────────────────────────────────────────────────────────────────
-- AG7-26: semana_passada = a semana ISO anterior a p_hoje, de segunda a sábado; ultimos_7_dias = de p_hoje − 7 a p_hoje − 1. A chave (semana) é a segunda do
-- 1º dia: na quinta, as duas janelas dão a mesma segunda. Com p_semana, a semana dela, de segunda a sábado.
create or replace function public._agenda_placar_periodo(p_hoje date, p_semana date default null)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf    public.agenda_config := public._agenda_cfg();
  v_seg date;
  v_de  date;
  v_ate date;
begin
  if p_hoje is null then
    raise exception '_agenda_placar_periodo: sem o dia de hoje' using errcode = '22004';
  end if;
  if p_semana is not null then
    v_seg := p_semana - (extract(isodow from p_semana)::int - 1);
    v_de := v_seg;
    v_ate := v_seg + 5;
  elsif cf.placar_janela = 'ultimos_7_dias' then
    v_de := p_hoje - 7;
    v_ate := p_hoje - 1;
    v_seg := v_de - (extract(isodow from v_de)::int - 1);
  else
    v_seg := p_hoje - (extract(isodow from p_hoje)::int - 1) - 7;
    v_de := v_seg;
    v_ate := v_seg + 5;
  end if;
  return jsonb_build_object('semana', v_seg, 'de', v_de, 'ate', v_ate);
end;
$function$;

comment on function public._agenda_placar_periodo(date, date) is
  'Agenda de Produção (Fase 7g, P6; AG7-26): a semana do placar — {semana (a segunda, a chave de agenda_placar_semanas), de, ate}. Com p_semana: a semana dela, de segunda a sábado. Sem ela, pela placar_janela: semana_passada = a semana ISO anterior a p_hoje, de segunda a sábado; ultimos_7_dias = de p_hoje − 7 a p_hoje − 1 (a chave é a segunda do 1º dia). Sem p_hoje, 22004. STABLE, só service_role.';

-- ── 2. As mensagens da agenda no período (só contagem) ──────────────────────────────────────────────
-- R9.5-12: pelo source (agenda-confirmacao vai ao CLIENTE). O acorde da vigia (source agenda, chave agenda:<ação>) é do dono. O lembrete R10 da OS ao técnico
-- (agenda-r10) não é da agenda de produção e fica fora. Nunca lê o texto da mensagem.
create or replace function public._agenda_mensagens_da_agenda(p_de date, p_ate date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_n  jsonb;
  v_du int;
begin
  if p_de is null or p_ate is null then
    raise exception '_agenda_mensagens_da_agenda: sem o período' using errcode = '22004';
  end if;
  select jsonb_build_object(
           'dono', count(*) filter (where x.quem = 'dono'), 'equipe', count(*) filter (where x.quem = 'equipe'),
           'cliente', count(*) filter (where x.quem = 'cliente'), 'fornecedor', count(*) filter (where x.quem = 'fornecedor'),
           'enviadas', jsonb_build_object(
              'dono', count(*) filter (where x.quem = 'dono' and x.enviada), 'equipe', count(*) filter (where x.quem = 'equipe' and x.enviada),
              'cliente', count(*) filter (where x.quem = 'cliente' and x.enviada),
              'fornecedor', count(*) filter (where x.quem = 'fornecedor' and x.enviada)))
    into v_n
    from (select case when f.source in ('agenda-cliente', 'agenda-confirmacao') then 'cliente'
                      when f.source = 'agenda-equipe' then 'equipe'
                      when f.source = 'agenda-fornecedor' then 'fornecedor'
                      else 'dono' end as quem,
                 f.sent_at is not null as enviada
            from public.whatsapp_send_queue f
           where f.source in ('agenda-cliente', 'agenda-confirmacao', 'agenda-equipe', 'agenda-fornecedor', 'agenda-dono', 'agenda')
             and f.created_at >= (p_de::timestamp at time zone 'America/Sao_Paulo')
             and f.created_at < ((p_ate + 1)::timestamp at time zone 'America/Sao_Paulo')) x;
  v_du := (select count(*) from generate_series(p_de, p_ate, interval '1 day') g where public.agenda_dia_util(g::date));
  return v_n || jsonb_build_object(
    'dias_uteis', v_du,
    'por_dia', case when v_du > 0 then jsonb_build_object('dono', trim_scale((v_n ->> 'dono')::numeric / v_du), 'equipe', trim_scale((v_n ->> 'equipe')::numeric / v_du),
                                                           'cliente', trim_scale((v_n ->> 'cliente')::numeric / v_du)) end);
end;
$function$;

comment on function public._agenda_mensagens_da_agenda(date, date) is
  'Agenda de Produção (Fase 7g, P6; §5.6, R9.5-12): as mensagens da agenda que entraram em whatsapp_send_queue de p_de a p_ate (dias de Brasília), por destino pelo source — agenda-cliente e agenda-confirmacao = cliente; agenda-equipe = equipe; agenda-fornecedor = fornecedor; agenda-dono e agenda (o acorde, chave agenda:<ação>) = dono — {dono, equipe, cliente, fornecedor, enviadas{…} (sent_at), dias_uteis (agenda_dia_util), por_dia{dono, equipe, cliente} (nulo sem dia útil)}. Só contagem, nunca o texto. STABLE, só service_role.';

-- ── 3. Os números do placar ─────────────────────────────────────────────────────────────────────────
-- §5.6 com o R9: cada chave no seu bloco (a falha de uma não derruba as outras: a chave vira {erro: true} e incompleto = true; query_canceled não cai aqui, e
-- está certo). Datas de p_de, p_ate e p_hoje; nenhum relógio. Nada arredondado (só o texto arredonda).
create or replace function public._agenda_placar_numeros(p_de date, p_ate date, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  -- estrutural: as semanas da comparação do real × estimado (§5.6, "nas 8 semanas até p_ate")
  c_semanas constant int := 8;
  -- estrutural: os motivos de _agenda_classe_da_os que esperam o cliente ou não são serviço da carteira (§5.6)
  c_espera  constant text[] := array['cliente', 'orcamento', 'sinal', 'escopo', 'fora_da_carteira', 'nao_achei'];
  -- estrutural: as ações que mexem no plano, sem publicar (§5.6; a lista do gatilho da zona, R9.5-16)
  c_mexem   constant text[] := array['criar', 'mover', 'cancelar', 'fixar', 'promover_reserva', 'soltar_reserva', 'reparar', 'reestimar'];
  cf     public.agenda_config := public._agenda_cfg();
  v_ini  timestamptz;
  v_fim  timestamptz;
  v_r    jsonb;
  v      jsonb;
  v_a    jsonb;
  v_b    jsonb;
  v_inc  boolean := false;
begin
  if p_de is null or p_ate is null or p_hoje is null then
    raise exception '_agenda_placar_numeros: sem o período ou o dia de hoje' using errcode = '22004';
  end if;
  v_ini := p_de::timestamp at time zone 'America/Sao_Paulo';
  v_fim := (p_ate + 1)::timestamp at time zone 'America/Sao_Paulo';
  -- o freio (R9.4-3: a 1ª linha do texto)
  v_r := jsonb_build_object('freio', cf.gestor_so_propor);

  -- cobertura: as OS da carteira com mão de obra (com base para os dias) e sem esperar o cliente (a classe de agora); com data firme = meio-dia vigente sem
  -- reserva de p_ate em diante, ou em andamento. Reserva nunca conta. pct nulo sem pronta (R9.12-2).
  begin
    select jsonb_build_object('prontas', count(*) filter (where x.pronta), 'com_data', count(*) filter (where x.pronta and x.com_data))
      into v
      from (select case when coalesce((public.os_duracao_sugerida(c.service_order_id) ->> 'sem_base')::boolean, true) then false
                        else not coalesce((public._agenda_classe_agora(c.service_order_id, p_hoje) ->> 'motivo') = any (c_espera), false) end as pronta,
                   c.status = 'in_progress'
                   or exists (select 1 from public.agenda_alocacoes a
                               where a.service_order_id = c.service_order_id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                                 and a.dia >= p_ate) as com_data
              from public.os_carteira(p_hoje) c) x;
    v := v || jsonb_build_object('pct', case when (v ->> 'prontas')::int > 0 then trim_scale(100 * (v ->> 'com_data')::numeric / (v ->> 'prontas')::int) end);
  exception when others then
    v := jsonb_build_object('erro', true);
    v_inc := true;
  end;
  v_r := v_r || jsonb_build_object('cobertura', v);

  -- aprovacao: a 1ª marcação de cada OS com aprovada_em no período — os dias úteis da aprovação ao 1º dia; os minutos da aprovação à marcação, só as minhas
  begin
    select jsonb_build_object(
             'n', count(*),
             'du_mediana', (percentile_cont(0.5) within group (order by public.agenda_du_entre((m.aprovada_em at time zone 'America/Sao_Paulo')::date, m.de)::float8))::numeric,
             'gestor_n', count(*) filter (where m.quem = 'gestor'),
             'minutos_mediana', (percentile_cont(0.5) within group (order by extract(epoch from m.marcada_em - m.aprovada_em)::float8 / 60)
                                  filter (where m.quem = 'gestor'))::numeric)
      into v
      from public.agenda_marcacoes m
     where m.aprovada_em >= v_ini and m.aprovada_em < v_fim
       and not exists (select 1 from public.agenda_marcacoes m2
                        where m2.service_order_id = m.service_order_id and (m2.marcada_em, m2.acao_id) < (m.marcada_em, m.acao_id));
  exception when others then
    v := jsonb_build_object('erro', true);
    v_inc := true;
  end;
  v_r := v_r || jsonb_build_object('aprovacao', v);

  -- marcacoes: as do período, por quem marcou
  begin
    select jsonb_build_object('gestor', count(*) filter (where m.quem = 'gestor'), 'dono', count(*) filter (where m.quem = 'dono'))
      into v
      from public.agenda_marcacoes m
     where m.marcada_em >= v_ini and m.marcada_em < v_fim;
  exception when others then
    v := jsonb_build_object('erro', true);
    v_inc := true;
  end;
  v_r := v_r || jsonb_build_object('marcacoes', v);

  -- correcoes: as minhas decididas no período (remarcada e saiu não contam); conferidas = as aceitas com meio-dia conferido (R9.4-2: o silêncio não é aceite)
  begin
    select jsonb_build_object(
             'aceita', count(*) filter (where m.desfecho = 'aceita'), 'ajustada', count(*) filter (where m.desfecho = 'ajustada'),
             'desfeita', count(*) filter (where m.desfecho = 'desfeita'), 'conferidas', count(*) filter (where m.desfecho = 'aceita' and m.conferida),
             'ajustes', jsonb_build_object(
                'duracao', count(*) filter (where m.desfecho = 'ajustada' and 'duracao' = any (m.ajustes)),
                'pessoa', count(*) filter (where m.desfecho = 'ajustada' and 'pessoa' = any (m.ajustes)),
                'dia', count(*) filter (where m.desfecho = 'ajustada' and 'dia' = any (m.ajustes)),
                'tirou', count(*) filter (where m.desfecho = 'ajustada' and 'tirou' = any (m.ajustes)),
                'material', count(*) filter (where m.desfecho = 'ajustada' and 'material' = any (m.ajustes))),
             'por_classe', coalesce((select jsonb_object_agg(t.classe, jsonb_build_object('n', t.n, 'corrigidas', t.c))
                                       from (select m2.classe, count(*) as n, count(*) filter (where m2.desfecho in ('ajustada', 'desfeita')) as c
                                               from public.agenda_marcacoes m2
                                              where m2.quem = 'gestor' and m2.desfecho in ('aceita', 'ajustada', 'desfeita')
                                                and m2.desfecho_em >= v_ini and m2.desfecho_em < v_fim
                                              group by m2.classe) t), '{}'::jsonb))
      into v
      from public.agenda_marcacoes m
     where m.quem = 'gestor' and m.desfecho in ('aceita', 'ajustada', 'desfeita') and m.desfecho_em >= v_ini and m.desfecho_em < v_fim;
  exception when others then
    v := jsonb_build_object('erro', true);
    v_inc := true;
  end;
  v_r := v_r || jsonb_build_object('correcoes', v);

  -- zonas: as ações executadas minhas (nem do dono nem do cliente) que mexeram no plano no período e não foram desfeitas, pela zona e pelo degrau gravados
  -- (20261112100100; a ação sem zona não entra). firme_du: até onde vai a zona firme (cliente_semana_du, 7f), para o texto.
  begin
    select jsonb_build_object(
             'travada', count(*) filter (where a.zona = 'travada'), 'firme', count(*) filter (where a.zona = 'firme'),
             'livre', count(*) filter (where a.zona = 'livre'), 'firme_du', cf.cliente_semana_du,
             'degraus', jsonb_build_object(
                'pessoa', count(*) filter (where a.degrau = 'pessoa'), 'turno', count(*) filter (where a.degrau = 'turno'),
                'dia', count(*) filter (where a.degrau = 'dia'), 'data', count(*) filter (where a.degrau = 'data'),
                'tirou', count(*) filter (where a.degrau = 'tirou')))
      into v
      from public.agenda_acoes a
     where a.executada and a.desfeita_em is null and a.zona is not null and a.tipo = any (c_mexem)
       and a.criada_em >= v_ini and a.criada_em < v_fim
       and a.origem is distinct from 'cliente' and public._agenda_quem_marcou(a.origem) = 'gestor';
  exception when others then
    v := jsonb_build_object('erro', true);
    v_inc := true;
  end;
  v_r := v_r || jsonb_build_object('zonas', v);

  -- ppc: agenda_ppc da semana de p_de; com os últimos 7 dias, a semana de p_ate também, somadas pela mesma regra
  begin
    v_a := public.agenda_ppc(p_de, p_hoje);
    v_b := case when (p_ate - (extract(isodow from p_ate)::int - 1)) <> (p_de - (extract(isodow from p_de)::int - 1))
                then public.agenda_ppc(p_ate, p_hoje) end;
    v := jsonb_build_object(
      'compromissos', (v_a ->> 'compromissos')::int + coalesce((v_b ->> 'compromissos')::int, 0),
      'cumpridos', (v_a ->> 'cumpridos')::int + coalesce((v_b ->> 'cumpridos')::int, 0),
      'conferidos', (v_a ->> 'cumpridos')::int + jsonb_array_length(v_a -> 'nao_cumpridos')
                    + coalesce((v_b ->> 'cumpridos')::int + jsonb_array_length(v_b -> 'nao_cumpridos'), 0));
    v := v || jsonb_build_object('ppc', case when (v ->> 'conferidos')::int > 0 then trim_scale((v ->> 'cumpridos')::numeric / (v ->> 'conferidos')::int) end);
  exception when others then
    v := jsonb_build_object('erro', true);
    v_inc := true;
  end;
  v_r := v_r || jsonb_build_object('ppc', v);

  -- estimativa: o real ÷ o estimado da 7e (razao_estimativa com motivo_razao nulo, R9.4-3) das OS concluídas no período e nas 8 semanas até p_ate
  begin
    select jsonb_build_object(
             'n', count(*) filter (where m.concluida_em >= p_de),
             'mediana', (percentile_cont(0.5) within group (order by m.razao_estimativa::float8) filter (where m.concluida_em >= p_de))::numeric,
             'ate_8_semanas', jsonb_build_object('n', count(*), 'mediana', (percentile_cont(0.5) within group (order by m.razao_estimativa::float8))::numeric))
      into v
      from public.agenda_medidas_os m
     where m.razao_estimativa is not null and m.motivo_razao is null
       and m.concluida_em > p_ate - 7 * c_semanas and m.concluida_em <= p_ate;
  exception when others then
    v := jsonb_build_object('erro', true);
    v_inc := true;
  end;
  v_r := v_r || jsonb_build_object('estimativa', v);

  -- compras: os itens críticos com o "compre até" (7a) no período; no prazo = comprado até o "compre até"
  begin
    select jsonb_build_object('com_prazo', count(*), 'no_prazo', count(*) filter (where m.comprado_em is not null and m.comprado_em <= m.compre_ate),
                              'vencidas', count(*) filter (where m.comprado_em is null or m.comprado_em > m.compre_ate))
      into v
      from public.os_material m
     where m.critico and m.compre_ate between p_de and p_ate;
  exception when others then
    v := jsonb_build_object('erro', true);
    v_inc := true;
  end;
  v_r := v_r || jsonb_build_object('compras', v);

  -- perguntas: as abertas agora (em ligado, sem a conferência), a idade em dias úteis; as assumidas pelo prazo ou pelo teto (7f) e as respondidas no período
  begin
    select jsonb_build_object('abertas', count(*), 'idade_max_du', max(x.du), 'idade_media_du', trim_scale(avg(x.du)))
      into v
      from (select public.agenda_du_entre((q.criada_em at time zone 'America/Sao_Paulo')::date, p_hoje) as du
              from public.agenda_perguntas q
             where q.estado = 'aberta' and q.modo = 'ligado' and q.tipo <> 'conferencia') x;
    v := v || jsonb_build_object(
      'assumidas', (select count(*) from public.agenda_perguntas q where q.assumida_em >= v_ini and q.assumida_em < v_fim),
      'respondidas', (select count(*) from public.agenda_perguntas q where q.modo = 'ligado' and q.respondida_em >= v_ini and q.respondida_em < v_fim));
  exception when others then
    v := jsonb_build_object('erro', true);
    v_inc := true;
  end;
  v_r := v_r || jsonb_build_object('perguntas', v);

  -- mensagens
  begin
    v := public._agenda_mensagens_da_agenda(p_de, p_ate);
  exception when others then
    v := jsonb_build_object('erro', true);
    v_inc := true;
  end;
  v_r := v_r || jsonb_build_object('mensagens', v);

  -- perdidos: os meios-dias (dia e turno) vigentes sem reserva do período que não foram cumpridos (1) ou foram em parte (0,5) por chuva ou por ferramenta
  begin
    select jsonb_build_object('clima_meios', coalesce(sum(x.peso) filter (where x.motivo = 'clima'), 0),
                              'ferramenta_meios', coalesce(sum(x.peso) filter (where x.motivo = 'ferramenta'), 0))
      into v
      from (select a.dia, a.turno, a.motivo, max(case when a.resultado = 'nao_cumprido' then 1 else 0.5 end) as peso
              from public.agenda_alocacoes a
             where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia between p_de and p_ate
               and a.resultado in ('nao_cumprido', 'parcial') and a.motivo in ('clima', 'ferramenta')
             group by a.dia, a.turno, a.motivo) x;
  exception when others then
    v := jsonb_build_object('erro', true);
    v_inc := true;
  end;
  v_r := v_r || jsonb_build_object('perdidos', v);

  -- tipos: as classes em que espero o ok do dono (o nível, P5b) e as que em teste eu passaria a esperar (teria, P5), com o texto delas
  begin
    select jsonb_build_object(
             'espera_ok', coalesce(jsonb_agg(jsonb_build_object('classe', t.classe, 'texto', t.texto) order by t.classe)
                                     filter (where t.nivel = 'espera_ok'), '[]'::jsonb),
             'teria', coalesce(jsonb_agg(jsonb_build_object('classe', t.classe, 'texto', t.texto) order by t.classe)
                                 filter (where t.nivel <> 'espera_ok' and t.teria = 'espera_ok' and t.texto is not null), '[]'::jsonb))
      into v
      from public.agenda_tipos_os t;
  exception when others then
    v := jsonb_build_object('erro', true);
    v_inc := true;
  end;
  v_r := v_r || jsonb_build_object('tipos', v);

  return v_r || jsonb_build_object('incompleto', v_inc);
end;
$function$;

comment on function public._agenda_placar_numeros(date, date, date) is
  'Agenda de Produção (Fase 7g, P6; §5.6, R9.4-3, R9.5-12, R9.5-13): os números do placar de p_de a p_ate (dias de Brasília), com p_hoje — {freio (gestor_so_propor), cobertura{prontas, com_data, pct} (as OS de os_carteira com base para os dias, os_duracao_sugerida sem sem_base, e a classe de agora, _agenda_classe_agora, fora de cliente, orcamento, sinal, escopo, fora_da_carteira e nao_achei; com data = meio-dia vigente sem reserva de p_ate em diante ou em andamento; pct nulo sem pronta), aprovacao{n, du_mediana, gestor_n, minutos_mediana} (a 1ª marcação da OS com aprovada_em no período), marcacoes{gestor, dono}, correcoes{aceita, ajustada, desfeita, conferidas (aceitas com meio-dia conferido), ajustes{duracao, pessoa, dia, tirou, material}, por_classe{classe: {n, corrigidas}}} (as do gestor com desfecho_em no período), zonas{travada, firme, livre, firme_du, degraus{…}} (ações executadas do gestor que mexeram no plano, sem publicar, não desfeitas), ppc{compromissos, cumpridos, conferidos, ppc} (agenda_ppc; as 2 semanas somadas quando o período as toca), estimativa{n, mediana, ate_8_semanas{n, mediana}} (razao_estimativa com motivo_razao nulo, por concluida_em), compras{com_prazo, no_prazo, vencidas} (itens críticos com compre_ate no período), perguntas{abertas, idade_max_du, idade_media_du, assumidas, respondidas}, mensagens (_agenda_mensagens_da_agenda), perdidos{clima_meios, ferramenta_meios} (meios-dias vigentes sem reserva não cumpridos = 1, parciais = 0,5), tipos{espera_ok, teria} ([{classe, texto}] de agenda_tipos_os), incompleto}. Cada chave no seu bloco: falhou = {erro: true} e incompleto. Reserva nunca conta. Nada arredondado. STABLE, só service_role.';

-- ── 4. O texto e a linha ─────────────────────────────────────────────────────────────────────────────
-- §6.5 com o R9.4-3. p_modo: mensagem (a quinta: só as linhas com dado, e "Detalhe em *agenda placar*." no fim) ou completo (*agenda placar*: todas, com o
-- "sem dado"). O número com erro vira "não consegui contar agora". Arredonda só aqui: 1 casa no fator, nos dias úteis e nas mensagens; inteiro no resto.
create or replace function public._agenda_placar_texto(p_numeros jsonb, p_de date, p_ate date, p_modo text, p_max integer)
 returns jsonb
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  -- estrutural: a ordem do corte, de baixo para cima (§6.5; depois da estimativa, as mudanças e o plano cumprido); nunca a cobertura nem as marcações
  c_corte constant text[] := array['tipos', 'mensagens', 'perguntas', 'perdidos', 'compras', 'estimativa', 'zonas', 'ppc'];
  c_onde  constant text := 'Detalhe em *agenda placar*.';
  c_erro  constant text := 'não consegui contar agora.';
  -- estrutural: a linha cabe no CHECK de agenda_placar_semanas.linha
  c_linha constant int := 300;
  n       jsonb := coalesce(p_numeros, '{}'::jsonb);
  v_msg   boolean;
  v_per   text;
  v_k     text[] := '{}';
  v_l     text[] := '{}';
  v_d     boolean[] := '{}';
  v_dados int := 0;
  v       jsonb;
  v_x     jsonb;
  v_p     text;
  v_lin   text[] := '{}';
  v_txt   text;
  v_corte text;
  i       int;
  g       int;
  d       int;
  ac      int;
  aj      int;
  de      int;
  x1      numeric;
  x2      numeric;
  e       jsonb;
begin
  if p_modo is null or p_modo not in ('mensagem', 'completo') then
    raise exception '_agenda_placar_texto: o modo é mensagem ou completo, não "%"', coalesce(p_modo, '') using errcode = '22023';
  end if;
  if p_de is null or p_ate is null then
    raise exception '_agenda_placar_texto: sem o período' using errcode = '22004';
  end if;
  v_msg := p_modo = 'mensagem';
  v_per := lpad(extract(day from p_de)::int::text, 2, '0')
           || case when extract(month from p_de) = extract(month from p_ate) then ''
                   else '/' || lpad(extract(month from p_de)::int::text, 2, '0') end
           || ' a ' || lpad(extract(day from p_ate)::int::text, 2, '0') || '/' || lpad(extract(month from p_ate)::int::text, 2, '0');

  -- o freio: com gestor_so_propor e nenhuma marcação minha na semana, a 1ª linha diz isso (R9.4-3, R9.12-9); não conta como linha com dado
  if coalesce((n ->> 'freio')::boolean, false) and not coalesce(n -> 'marcacoes' ? 'erro', true)
     and coalesce((n #>> '{marcacoes,gestor}')::int, 0) = 0 then
    v_k := v_k || 'freio'::text;
    v_l := v_l || 'Com *gestor, só propor*, não marquei nada sozinho nesta semana.'::text;
    v_d := v_d || true;
  end if;

  -- a cobertura e, na mesma linha, da aprovação à data
  v := n -> 'cobertura';
  v_k := v_k || 'cobertura'::text;
  if v is null or v ? 'erro' then
    v_l := v_l || ('Serviços prontos com data firme: ' || c_erro);
    v_d := v_d || false;
  elsif coalesce((v ->> 'prontas')::int, 0) = 0 then
    v_l := v_l || 'Serviços prontos com data firme: nenhum serviço pronto.'::text;
    v_d := v_d || false;
  else
    v_p := format('Serviços prontos com data firme: %s de %s (%s%%).', v ->> 'com_data', v ->> 'prontas', public._agenda_num((v ->> 'pct')::numeric, 0));
    v_x := n -> 'aprovacao';
    if v_x is not null and not (v_x ? 'erro') and coalesce((v_x ->> 'n')::int, 0) > 0 and v_x ->> 'du_mediana' is not null then
      x1 := round((v_x ->> 'du_mediana')::numeric, 1);
      v_p := v_p || format(' Da aprovação à data: %s %s (%s OS)', public._agenda_num(x1, 1), case when x1 = 1 then 'dia útil' else 'dias úteis' end, v_x ->> 'n');
      if coalesce((v_x ->> 'gestor_n')::int, 0) > 0 and v_x ->> 'minutos_mediana' is not null then
        x2 := round((v_x ->> 'minutos_mediana')::numeric);
        v_p := v_p || '; marquei em '
               || case when x2 < 60 then public._agenda_plural(x2::int, 'minuto', 'minutos')
                       else public._agenda_plural(round(x2 / 60)::int, 'hora', 'horas') end
               || ' depois de aprovar';
      end if;
      v_p := v_p || '.';
    end if;
    v_l := v_l || v_p;
    v_d := v_d || true;
  end if;

  -- as marcações e o que o dono corrigiu
  v := n -> 'marcacoes';
  v_x := n -> 'correcoes';
  v_k := v_k || 'marcacoes'::text;
  if v is null or v_x is null or v ? 'erro' or v_x ? 'erro' then
    v_l := v_l || ('Marcações: ' || c_erro);
    v_d := v_d || false;
  else
    g := coalesce((v ->> 'gestor')::int, 0);
    d := coalesce((v ->> 'dono')::int, 0);
    ac := coalesce((v_x ->> 'aceita')::int, 0);
    aj := coalesce((v_x ->> 'ajustada')::int, 0);
    de := coalesce((v_x ->> 'desfeita')::int, 0);
    if g + d + ac + aj + de = 0 then
      v_l := v_l || 'Marcações: nenhuma na semana.'::text;
      v_d := v_d || false;
    else
      v_p := case when g > 0 and d > 0 then format('Marquei %s, você marcou %s.', g, d)
                  when g > 0 then format('Marquei %s.', g)
                  when d > 0 then format('Você marcou %s.', d)
                  else '' end;
      if ac + aj + de > 0 then
        v_p := v_p || case when v_p = '' then '' else ' ' end || 'Das minhas: ' || array_to_string(array_remove(array[
                 case when ac > 0 then format('%s %s como fiz (%s)', ac, case when ac = 1 then 'ficou' else 'ficaram' end,
                                              case coalesce((v_x ->> 'conferidas')::int, 0) when 0 then 'nenhuma conferida' when 1 then '1 conferida'
                                                   else (v_x ->> 'conferidas') || ' conferidas' end) end,
                 case when aj > 0 then format('%s você ajustou (%s)', aj, array_to_string(array_remove(array[
                        case when coalesce((v_x #>> '{ajustes,duracao}')::int, 0) > 0 then 'a duração' end,
                        case when coalesce((v_x #>> '{ajustes,pessoa}')::int, 0) > 0 then 'a pessoa' end,
                        case when coalesce((v_x #>> '{ajustes,dia}')::int, 0) > 0 then 'o dia' end,
                        case when coalesce((v_x #>> '{ajustes,tirou}')::int, 0) > 0 then 'tirou da agenda' end,
                        case when coalesce((v_x #>> '{ajustes,material}')::int, 0) > 0 then 'o material' end], null), ', ')) end,
                 case when de > 0 then format('%s você desfez', de) end], null), ', ') || '.';
      end if;
      v_l := v_l || v_p;
      v_d := v_d || true;
    end if;
  end if;

  -- as mudanças por zona
  v := n -> 'zonas';
  v_k := v_k || 'zonas'::text;
  if v is null or v ? 'erro' then
    v_l := v_l || ('Mudanças: ' || c_erro);
    v_d := v_d || false;
  elsif coalesce((v ->> 'travada')::int, 0) + coalesce((v ->> 'firme')::int, 0) + coalesce((v ->> 'livre')::int, 0) = 0 then
    v_l := v_l || 'Mudanças: nenhuma na semana.'::text;
    v_d := v_d || false;
  else
    v_l := v_l || format('Mudanças: %s em dia já avisado, %s nos próximos %s, %s mais à frente.',
                         case when coalesce((v ->> 'travada')::int, 0) = 0 then 'nenhuma' else v ->> 'travada' end,
                         case when coalesce((v ->> 'firme')::int, 0) = 0 then 'nenhuma' else v ->> 'firme' end,
                         public._agenda_plural(coalesce((v ->> 'firme_du')::int, 0), 'dia útil', 'dias úteis'),
                         case when coalesce((v ->> 'livre')::int, 0) = 0 then 'nenhuma' else v ->> 'livre' end);
    v_d := v_d || true;
  end if;

  -- o plano cumprido
  v := n -> 'ppc';
  v_k := v_k || 'ppc'::text;
  if v is null or v ? 'erro' then
    v_l := v_l || ('Plano cumprido: ' || c_erro);
    v_d := v_d || false;
  elsif coalesce((v ->> 'compromissos')::int, 0) = 0 then
    v_l := v_l || 'Plano cumprido: sem dia marcado firme na semana.'::text;
    v_d := v_d || false;
  elsif coalesce((v ->> 'conferidos')::int, 0) = 0 then
    v_l := v_l || format('Plano cumprido: %s, nenhum conferido.', public._agenda_plural((v ->> 'compromissos')::int, 'dia de serviço', 'dias de serviço'));
    v_d := v_d || true;
  else
    v_l := v_l || format('Plano cumprido: %s de %s (%s%%).', v ->> 'cumpridos',
                         public._agenda_plural((v ->> 'conferidos')::int, 'dia de serviço', 'dias de serviço'),
                         public._agenda_num(100 * (v ->> 'ppc')::numeric, 0));
    v_d := v_d || true;
  end if;

  -- o real × o estimado
  v := n -> 'estimativa';
  v_k := v_k || 'estimativa'::text;
  if v is null or v ? 'erro' then
    v_l := v_l || ('O real × estimado: ' || c_erro);
    v_d := v_d || false;
  elsif coalesce((v ->> 'n')::int, 0) = 0 or v ->> 'mediana' is null then
    v_l := v_l || 'O real × estimado: nenhuma OS concluída medida.'::text;
    v_d := v_d || false;
  else
    v_l := v_l || format('O real ficou em %s× o que estimei (%s).', public._agenda_num((v ->> 'mediana')::numeric, 1),
                         case when (v ->> 'n')::int = 1 then '1 OS concluída' else (v ->> 'n') || ' OS concluídas' end);
    v_d := v_d || true;
  end if;

  -- as compras
  v := n -> 'compras';
  v_k := v_k || 'compras'::text;
  if v is null or v ? 'erro' then
    v_l := v_l || ('Compras: ' || c_erro);
    v_d := v_d || false;
  elsif coalesce((v ->> 'com_prazo')::int, 0) = 0 then
    v_l := v_l || 'Compras: nenhum "compre até" na semana.'::text;
    v_d := v_d || false;
  else
    v_l := v_l || format('Compras: %s de %s feitas até o "compre até".', v ->> 'no_prazo', v ->> 'com_prazo');
    v_d := v_d || true;
  end if;

  -- as perguntas
  v := n -> 'perguntas';
  v_k := v_k || 'perguntas'::text;
  if v is null or v ? 'erro' then
    v_l := v_l || ('Perguntas abertas: ' || c_erro);
    v_d := v_d || false;
  elsif coalesce((v ->> 'abertas')::int, 0) = 0 then
    v_l := v_l || 'Perguntas abertas: nenhuma.'::text;
    v_d := v_d || false;
  else
    v_l := v_l || format('Perguntas abertas: %s (a mais antiga %s).', v ->> 'abertas',
                         case when coalesce((v ->> 'idade_max_du')::int, 0) = 0 then 'é de hoje'
                              else 'com ' || public._agenda_plural((v ->> 'idade_max_du')::int, 'dia útil', 'dias úteis') end);
    v_d := v_d || true;
  end if;

  -- as mensagens por dia útil (não contam para o mínimo, R9.4-3)
  v := n -> 'mensagens';
  v_k := v_k || 'mensagens'::text;
  if v is null or v ? 'erro' then
    v_l := v_l || ('Mensagens: ' || c_erro);
    v_d := v_d || false;
  elsif v -> 'por_dia' is null or jsonb_typeof(v -> 'por_dia') <> 'object'
        or coalesce((v ->> 'dono')::int, 0) + coalesce((v ->> 'equipe')::int, 0) + coalesce((v ->> 'cliente')::int, 0) = 0 then
    v_l := v_l || 'Mensagens: nenhuma da agenda na semana.'::text;
    v_d := v_d || false;
  else
    v_l := v_l || format('Mensagens por dia: %s a você, %s à equipe, %s a clientes.', public._agenda_num((v #>> '{por_dia,dono}')::numeric, 1),
                         public._agenda_num((v #>> '{por_dia,equipe}')::numeric, 1), public._agenda_num((v #>> '{por_dia,cliente}')::numeric, 1));
    v_d := v_d || true;
  end if;

  -- os dias perdidos por chuva e por ferramenta ou carro (meios-dias: o parcial vale meio)
  v := n -> 'perdidos';
  v_k := v_k || 'perdidos'::text;
  if v is null or v ? 'erro' then
    v_l := v_l || ('Dias perdidos: ' || c_erro);
    v_d := v_d || false;
  else
    x1 := coalesce((v ->> 'clima_meios')::numeric, 0);
    x2 := coalesce((v ->> 'ferramenta_meios')::numeric, 0);
    if x1 + x2 = 0 then
      v_l := v_l || 'Dias perdidos: nenhum por chuva nem por ferramenta ou carro.'::text;
      v_d := v_d || false;
    else
      v_l := v_l || ('Dias perdidos: ' || array_to_string(array_remove(array[
               case when x1 > 0 then 'chuva ' || case when x1 = trunc(x1) then public._agenda_meios_texto(x1::int)
                                                      else public._agenda_num(x1 / 2, 2) || ' dia' end end,
               case when x2 > 0 then 'ferramenta ou carro ' || case when x2 = trunc(x2) then public._agenda_meios_texto(x2::int)
                                                                    else public._agenda_num(x2 / 2, 2) || ' dia' end end], null), ', ') || '.');
      v_d := v_d || true;
    end if;
  end if;

  -- os tipos de OS: as classes em espera do ok e as que eu passaria a esperar (só com elas: §6.5)
  v := n -> 'tipos';
  if v is not null and not (v ? 'erro') then
    for e in select t.y from jsonb_array_elements(coalesce(v -> 'espera_ok', '[]'::jsonb) || coalesce(v -> 'teria', '[]'::jsonb)) with ordinality t(y, o) order by t.o loop
      continue when nullif(btrim(e ->> 'texto'), '') is null;
      v_k := v_k || 'tipos'::text;
      v_l := v_l || btrim(e ->> 'texto');
      v_d := v_d || true;
    end loop;
  end if;

  -- as linhas com dado, sem contar o freio e as mensagens (o mínimo da quinta, R9.4-3)
  v_dados := (select count(*) from generate_subscripts(v_k, 1) s where v_d[s] and v_k[s] not in ('freio', 'mensagens'));

  -- o texto: na mensagem, só as linhas com dado (e o freio); o corte de baixo para cima, chave por chave
  for i in 1 .. cardinality(v_k) loop
    if v_msg and not v_d[i] then
      v_k[i] := null;
    end if;
  end loop;
  foreach v_corte in array array[null::text] || c_corte loop
    if v_corte is not null then
      for i in 1 .. cardinality(v_k) loop
        if v_k[i] = v_corte then
          v_k[i] := null;
        end if;
      end loop;
    end if;
    v_lin := array['Placar da semana de ' || v_per || ' (números do sistema):']
             || array(select '• ' || v_l[s] from generate_subscripts(v_k, 1) s where v_k[s] is not null order by s)
             || case when v_msg then array[c_onde] else '{}'::text[] end;
    v_txt := array_to_string(v_lin, E'\n');
    exit when p_max is null or char_length(v_txt) <= p_max;
  end loop;
  if p_max is not null and char_length(v_txt) > p_max then
    v_txt := left(v_txt, greatest(p_max - 1, 0)) || '…';
  end if;

  -- a linha (≤ 300): só as partes com dado
  v_lin := '{}';
  v := n -> 'cobertura';
  if v is not null and not (v ? 'erro') and coalesce((v ->> 'prontas')::int, 0) > 0 then
    v_lin := v_lin || format('%s de %s prontos com data', v ->> 'com_data', v ->> 'prontas');
  end if;
  v := n -> 'marcacoes';
  v_x := n -> 'correcoes';
  if v is not null and v_x is not null and not (v ? 'erro') and not (v_x ? 'erro')
     and coalesce((v ->> 'gestor')::int, 0) + coalesce((v_x ->> 'ajustada')::int, 0) + coalesce((v_x ->> 'desfeita')::int, 0) > 0 then
    v_lin := v_lin || format('marquei %s, você corrigiu %s', coalesce((v ->> 'gestor')::int, 0),
                             coalesce((v_x ->> 'ajustada')::int, 0) + coalesce((v_x ->> 'desfeita')::int, 0));
  end if;
  v := n -> 'ppc';
  if v is not null and not (v ? 'erro') and coalesce((v ->> 'conferidos')::int, 0) > 0 then
    v_lin := v_lin || format('plano cumprido %s%%', public._agenda_num(100 * (v ->> 'ppc')::numeric, 0));
  end if;
  v := n -> 'compras';
  if v is not null and not (v ? 'erro') and coalesce((v ->> 'com_prazo')::int, 0) > 0 then
    v_lin := v_lin || format('compras %s de %s no prazo', v ->> 'no_prazo', v ->> 'com_prazo');
  end if;
  v_p := 'Placar ' || v_per || ': ' || coalesce(nullif(array_to_string(v_lin, '; '), ''), 'sem números na semana') || '. ' || c_onde;
  if char_length(v_p) > c_linha then
    v_p := left(v_p, c_linha - 1) || '…';
  end if;
  return jsonb_build_object('texto', v_txt, 'linha', v_p, 'linhas', v_dados);
end;
$function$;

comment on function public._agenda_placar_texto(jsonb, date, date, text, integer) is
  'Agenda de Produção (Fase 7g, P6; §6.5, R9.4-3): o texto e a linha do placar a partir dos números (_agenda_placar_numeros) — {texto, linha (≤ 300), linhas (as com dado, sem contar o freio e as mensagens: o mínimo da quinta)}. O título "Placar da semana de DD a DD/MM (números do sistema):" e, uma por linha com "• ": o freio (com gestor_so_propor e nenhuma marcação minha: "Com *gestor, só propor*, não marquei nada sozinho nesta semana."), os serviços prontos com data firme (com a aprovação à data), as marcações e o que o dono corrigiu (com as conferidas), as mudanças por zona, o plano cumprido, o real × estimado, as compras no "compre até", as perguntas abertas, as mensagens por dia útil, os dias perdidos e as classes em espera do ok ou em teste. p_modo mensagem: só as linhas com dado e "Detalhe em *agenda placar*." no fim; completo: todas, com o "sem dado". Erro numa chave: "<o quê>: não consegui contar agora.". O corte em p_max, de baixo para cima: tipos, mensagens, perguntas, dias perdidos, compras, estimativa, mudanças, plano cumprido; nunca a cobertura nem as marcações; no fim, na letra, com "…". p_modo fora de mensagem e completo = 22023. IMMUTABLE, só service_role.';

-- ── 5. A leitura e o guardado ───────────────────────────────────────────────────────────────────────
-- A leitura do placar (*agenda placar*, pelo foco do P7). Molde da porta: _agenda_saude_margem (7e).
create or replace function public.agenda_placar(p_semana date default null, p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_teste constant text := 'Em teste: ';
  cf      public.agenda_config;
  v_uid   uuid := auth.uid();
  v_papel text;
  v_per   jsonb;
  v_de    date;
  v_ate   date;
  v_s     public.agenda_placar_semanas;
  v_num   jsonb;
  v_t     jsonb;
  v_guard boolean := false;
  v_hist  jsonb;
begin
  -- Quem vê: com login, só admin/financeiro; sem login, só o service_role.
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'O placar da agenda é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'O placar da agenda é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora do placar.' using errcode = '22023';
  end if;
  cf := public._agenda_cfg();
  if cf.modo_placar = 'desligado' then
    return jsonb_build_object('modo', 'desligado');
  end if;
  v_per := public._agenda_placar_periodo(p_hoje, p_semana);
  v_de := (v_per ->> 'de')::date;
  v_ate := (v_per ->> 'ate')::date;
  -- a semana que já fechou e foi guardada: os números guardados (os da mensagem); senão, a conta de agora
  select * into v_s from public.agenda_placar_semanas s where s.semana = (v_per ->> 'semana')::date;
  if found and v_s.de = v_de and v_s.ate = v_ate and v_ate < p_hoje then
    v_num := v_s.numeros;
    v_guard := true;
  else
    v_num := public._agenda_placar_numeros(v_de, v_ate, p_hoje);
  end if;
  v_t := public._agenda_placar_texto(v_num, v_de, v_ate, 'completo',
                                     cf.texto_max - case when cf.modo_placar = 'sombra' then char_length(c_teste) else 0 end);
  v_hist := (select coalesce(jsonb_agg(jsonb_build_object('semana', h.semana, 'de', h.de, 'ate', h.ate, 'cobertura', h.numeros -> 'cobertura',
                                                          'correcoes', h.numeros -> 'correcoes', 'ppc', h.numeros -> 'ppc') order by h.semana desc), '[]'::jsonb)
               from (select s.semana, s.de, s.ate, s.numeros from public.agenda_placar_semanas s
                      where s.semana < (v_per ->> 'semana')::date order by s.semana desc limit cf.placar_semanas_hist) h);
  return jsonb_build_object(
    'modo', cf.modo_placar, 'semana', v_per -> 'semana', 'de', v_de, 'ate', v_ate, 'numeros', v_num,
    'texto', case when cf.modo_placar = 'sombra' then c_teste || (v_t ->> 'texto') else v_t ->> 'texto' end,
    'linha', v_t ->> 'linha', 'linhas', (v_t ->> 'linhas')::int, 'guardado', v_guard, 'historico', v_hist);
end;
$function$;

comment on function public.agenda_placar(date, date, timestamptz) is
  'Agenda de Produção (Fase 7g, P6; §5.6, R9.4-3): a leitura do placar (*agenda placar*). modo_placar desligado = {modo: desligado}. A semana de p_semana (segunda a sábado), senão a da placar_janela (_agenda_placar_periodo); a linha guardada de agenda_placar_semanas quando a semana já fechou (ate < p_hoje) e é o mesmo período, senão a conta de agora (_agenda_placar_numeros). {modo, semana, de, ate, numeros, texto (o completo, até texto_max; em sombra com "Em teste: " na frente), linha, linhas, guardado, historico (as placar_semanas_hist semanas guardadas antes dela: cobertura, correcoes e ppc)}. Faltam o dia ou a hora = 22023. SECURITY DEFINER, STABLE; com login, só admin/financeiro (42501); sem login, só o service_role.';

-- O passo placar da rodada explicar (P5): no dia_do_plano, com modo_placar fora de desligado (a rodada já confere os dois), guarda a semana. Muda inteiro (versão + 1
-- e uma entrada no histórico) só quando o número, o texto, a linha ou o modo mudam: 2× = 1×.
create or replace function public._agenda_explicar_placar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  -- estrutural: o CHECK de agenda_placar_semanas.texto (20261112100000); texto_max pode passar dele
  c_texto_tabela constant int := 1000;
  -- estrutural: o CHECK do histórico da linha (até 10 entradas)
  c_hist         constant int := 10;
  cf    public.agenda_config := public._agenda_cfg();
  v_per jsonb;
  v_sem date;
  v_de  date;
  v_ate date;
  v_num jsonb;
  v_t   jsonb;
  v_s   public.agenda_placar_semanas;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_explicar_placar: sem o dia ou a hora' using errcode = '22004';
  end if;
  if cf.modo_placar = 'desligado' then
    return jsonb_build_object('guardado', false, 'modo', 'desligado');
  end if;
  v_per := public._agenda_placar_periodo(p_hoje);
  v_sem := (v_per ->> 'semana')::date;
  v_de := (v_per ->> 'de')::date;
  v_ate := (v_per ->> 'ate')::date;
  v_num := public._agenda_placar_numeros(v_de, v_ate, p_hoje);
  v_t := public._agenda_placar_texto(v_num, v_de, v_ate, 'completo', least(cf.texto_max, c_texto_tabela));
  select * into v_s from public.agenda_placar_semanas s where s.semana = v_sem for update;
  if not found then
    insert into public.agenda_placar_semanas (semana, de, ate, modo, numeros, texto, linha, calculado_em)
    values (v_sem, v_de, v_ate, cf.modo_placar, v_num, v_t ->> 'texto', v_t ->> 'linha', p_agora);
    return jsonb_build_object('guardado', true, 'semana', v_sem, 'versao', 1, 'incompleto', coalesce((v_num ->> 'incompleto')::boolean, false));
  end if;
  -- a janela mudou no meio (a mesma segunda, outro período): a linha guardada fica
  if v_s.de <> v_de or v_s.ate <> v_ate then
    return jsonb_build_object('guardado', false, 'semana', v_sem, 'outro_periodo', true);
  end if;
  if v_s.numeros = v_num and v_s.texto = (v_t ->> 'texto') and v_s.linha = (v_t ->> 'linha') and v_s.modo = cf.modo_placar then
    return jsonb_build_object('guardado', false, 'semana', v_sem, 'igual', true, 'versao', v_s.versao);
  end if;
  update public.agenda_placar_semanas s
     set numeros = v_num, texto = v_t ->> 'texto', linha = v_t ->> 'linha', modo = cf.modo_placar, calculado_em = p_agora, versao = s.versao + 1,
         historico = coalesce((select jsonb_agg(h.e order by h.o) from jsonb_array_elements(s.historico) with ordinality h(e, o)
                                where h.o > jsonb_array_length(s.historico) - (c_hist - 1)), '[]'::jsonb)
                     || jsonb_build_array(jsonb_build_object('versao', s.versao, 'calculado_em', s.calculado_em, 'modo', s.modo, 'linha', s.linha))
   where s.semana = v_sem;
  return jsonb_build_object('guardado', true, 'semana', v_sem, 'versao', v_s.versao + 1, 'incompleto', coalesce((v_num ->> 'incompleto')::boolean, false));
end;
$function$;

comment on function public._agenda_explicar_placar(date, timestamptz) is
  'Agenda de Produção (Fase 7g, P6; §5.6): o passo placar da rodada explicar (agenda_explicar_rodar o chama no dia_do_plano com modo_placar fora de desligado). Desligado = {guardado: false, modo: desligado}, nada gravado. Guarda a semana da placar_janela em agenda_placar_semanas com o modo de agora: a 1ª vez insere (versão 1); depois, só quando números, texto, linha ou modo mudam, versão + 1 e uma entrada no histórico (até 10); igual = {guardado: false, igual}; o mesmo dia de segunda com outro período (a janela mudou) = {guardado: false, outro_periodo}. O texto guardado é o completo, até texto_max e até o CHECK da tabela. {guardado, semana, versao, incompleto}. Nenhuma mensagem. Invoker, só service_role.';

-- ── 6. A saúde ──────────────────────────────────────────────────────────────────────────────────────
-- Molde: _agenda_saude_margem (7e) e _agenda_saude_comunicacao (7f): a porta, os zeros que entram no ok e os números; sem os modos dentro (a chave não muda de um
-- modo para o outro; os zeros que vigiam um modo olham o dele). Os do ok do dono (ok_sem_pergunta, nivel_sem_aviso) são do P5b.
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
  'Agenda de Produção (Fase 7g, P6; §11, R9.5-17): a chave explicar de agenda_saude — os zeros obrigatórios (entram no ok; zeros_ok): placar_atrasado (dia_do_plano, depois de explicar_hora + 1 hora, modo_placar fora de desligado e a semana sem linha em agenda_placar_semanas), marcacao_aberta_vencida (aberta depois do dia da marcação + correcao_janela_du dias úteis, com modo_porque fora de desligado), rebaixar_sem_veto (modo_rebaixar ligado e o veto fora de ligado), rodada_atrasada (porquê ou rebaixar fora de desligado, não é domingo, depois de explicar_hora + 1 hora e nenhuma rodada explicar de hoje) e erros_dia (app_error_logs da agenda com action explicar:% no dia até p_agora); e os números (ultima_rodada, marcacoes por desfecho, tipos_teria, o último placar guardado, alocacoes_sem_porque e acoes_sem_zona em 7 dias desde marcacoes_desde). ok_sem_pergunta e nivel_sem_aviso são do P5b; explicar_divergencias não é contado (nada guarda o de antes). Sem os modos dentro: a chave existe em todos os modos. Definer, a porta de _agenda_saude_margem (admin/financeiro ou service_role; 42501); sem o dia ou a hora, 22004.';

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
  -- (7e P7; §5.6, R7.5-17, a correção do P4; marca sem FASE porque está dentro do bloco da correção C2 da Fase 6) os itens da margem têm os zeros e os números deles na chave margem
  -- (_agenda_saude_margem, no fim): aqui eles saem dos zeros e das métricas do aprendizado da Fase 6, que não os conhecem. Sem isso, com a margem ligada, o "em uso fora de ligado" contava
  -- todo item da margem recalculado na última rodada (_agenda_aprendizado_da_lista é nula para eles: nunca estão em aprendizado_ligados), a "troca grande sem pergunta" contava toda ação
  -- da margem (o case não os conhece) e o "em uso com amostra pequena" contava a folga da semana que volta ao padrão por passo sem medida (R7.4): o ok da saúde cairia a cada passo.
  -- Cada conta tira exatamente o que a de cima contou dos itens da margem (as mesmas condições). Sem linha nem ação da margem, tira 0 e as métricas são as de antes, byte a byte.
  v_apeq := v_apeq - (select count(*) from public.agenda_aprendizado a
                       where a.item = 'folga_semana' and a.calculado is null
                         and a.estado in ('em_uso', 'pergunta', 'travado') and a.em_uso is not null and a.n < a.n_min);
  v_afora := v_afora - (select count(*) from public.agenda_aprendizado a
                         where a.item in ('vies', 'folga_semana', 'promessa', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor')
                           and v_arod.p_agora is not null and a.estado = 'em_uso' and a.em_uso is not null and a.calculado_em >= v_arod.p_agora
                           and (coalesce(v_arod.contagens ->> 'modo_aprendizado', '') <> 'ligado'
                                or not coalesce(v_arod.contagens -> 'ligados' ? public._agenda_aprendizado_da_lista(a.item), false)));
  v_agrande := v_agrande - (select count(*) from public.agenda_acoes a
                             where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada
                               and a.criada_em > p_agora - make_interval(days => cf.aprender_saude_dias)
                               and a.antes ->> 'item' in ('vies', 'folga_semana', 'promessa', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor'));
  v_apr := v_apr || jsonb_build_object('em_uso_com_amostra_pequena', v_apeq, 'em_uso_fora_de_ligado', v_afora);
  v_amet := v_amet || jsonb_build_object(
    'itens', coalesce((select jsonb_object_agg(t.item, jsonb_build_object('chaves', t.chaves, 'n_max', t.n_max, 'n_min', t.n_min,
                                                                         'estados', t.estados))
                         from (select a.item, count(*) as chaves, max(a.n) as n_max, max(a.n_min) as n_min,
                                      (select jsonb_object_agg(s.estado, s.n)
                                         from (select b.estado, count(*) as n from public.agenda_aprendizado b
                                                where b.item = a.item group by b.estado) s) as estados
                                 from public.agenda_aprendizado a where a.item not in ('vies', 'folga_semana', 'promessa', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor') group by a.item) t), '{}'::jsonb));
  -- (7e: fim)
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
  -- (7e P7; §5.6, R7.5-17; dentro do bloco do gestor: por isso a marca, não o bloco) a chave margem (_agenda_saude_margem), com os zeros obrigatórios no ok. Sem nada da margem (nenhuma
  -- linha nem ação dela, o puxar sem rodar fora de hora), os zeros são 0 e o ok é o de antes. A chave existe em todos os modos e não traz os modos (não muda de um para o outro).
  v_gr := v_gr || jsonb_build_object('margem', public._agenda_saude_margem(p_hoje, p_agora));
  v_gr := jsonb_set(v_gr, '{ok}', to_jsonb(coalesce((v_gr ->> 'ok')::boolean, false)
                                            and coalesce((v_gr #>> '{margem,zeros_ok}')::boolean, true)));
  -- (7e: fim)
  -- (7g P6; §11, R9.5-17; dentro do bloco do gestor: por isso a marca, não o bloco) a chave explicar (_agenda_saude_explicar), com os zeros obrigatórios no
  -- ok. Sem os modos da 7g e sem nada do que eles fazem, os zeros são 0 e o ok é o de antes. A chave existe em todos os modos e não traz os modos.
  v_gr := v_gr || jsonb_build_object('explicar', public._agenda_saude_explicar(p_hoje, p_agora));
  v_gr := jsonb_set(v_gr, '{ok}', to_jsonb(coalesce((v_gr ->> 'ok')::boolean, false)
                                            and coalesce((v_gr #>> '{explicar,zeros_ok}')::boolean, true)));
  -- (7g: fim)
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
  'Agenda de Produção (Fase 2, P3): a conferência depois de cada deploy e o painel da sombra — {ok, modos, vigia (última rodada, rodou nas últimas 2 h, erros em 24 h no app_error_logs context agenda, rodadas em 24 h), hoje (publicar, criar, mover, cancelar, promover, soltar, status, resultado, desfeitas, sombra), criticas (abertas, respondidas em 7 dias, sem_decisao e pela_regra_sem_decisao — têm de ser 0), perguntas (abertas por tipo, mostradas hoje), propostas, plano (vigentes futuras, OS programadas, reservas, sem registro em 7 dias), invariantes (vigente de OS fora da carteira, espelho divergente em ligado, choques = 0), fechamento (leu o plano hoje: resumo_tarde.detalhe.agenda; linhas mostradas)}. Leitura (invoker): authenticated (a RLS do admin vale) e service_role. Fase 3: a vigia lê só as rodadas dela (rotina = vigia); blocos rotina (última rodada, rodou nas últimas 2 h, erros 24 h), equipe (mensagens e recusas de hoje; acima_do_teto e fora_da_janela — também o que saiu fora dela — têm de ser 0), diarias (lançadas e em teste em 7 dias, perguntas abertas; sem_confirmacao e sobrescreveu_turno têm de ser 0), conclusao (pela agenda e desfeitas em 7 dias; sem_recebivel_quando_devia = 0, só para quem lê a releitura), marcos (N4), comissao (pagamento desligado; payables de comissão de técnico em 7 dias = 0) e modos_fase3; o ok inclui esses zeros. Fase 4 (P5): o bloco material — modos (material, detector, fornecedor), a rodada do material (rotina = material: última, rodou nas últimas 2 h, erros 24 h em material:%), remessas (a caminho, sem resposta, ligadas/sem serviço/chegaram em 7 dias), perguntas (as abertas da Fase 4 por tipo; pix_na_semana), detector (agenda_detector_precisao dos últimos 14 dias — só para administrador/financeiro ou sem login —, aplicados e desfeitos em 7 dias), fornecedor (registradas, enfileiradas, em teste e recusadas por motivo em 7 dias), cobertura (itens críticos das OS que começam nas próximas material_inicio_dias e quantos têm data, nível A–D), espera (mediana da aprovação à 1ª compra, OS aprovadas em 90 dias); os zeros obrigatórios entram no ok: vinculo_sem_resposta_do_dono, previsao_sem_original e, do fornecedor, na_fila_em_sombra, fora_da_janela, acima_do_teto e com_valor_ou_cliente. Fase 5 (P3): o bloco cliente — modo, tipos_ligados, tipos_liberados (somaram cliente_aprovacao_dias dias aprovados), a rodada do cliente (rotina = cliente: última, rodou nas últimas 2 h, erros 24 h em cliente:%), mensagens_7d por tipo (registradas, aguardando, enviadas, recusadas por motivo), aprovacao (pedidas abertas, vencidas, aprovadas e seguradas em 7 dias) e as métricas (M6 antes da data, aprovadas sem segurar, resposta em 1 dia, SIM automático, opt-outs, falhas de entrega, idas perdidas por acesso com e sem véspera); os zeros obrigatórios entram no ok: fora_da_janela, em_feriado_ou_domingo, acima_do_teto, intervalo_curto, com_texto_proibido, na_fila_em_sombra, sem_aprovacao_no_periodo, critica_sem_decisao, vespera_com_os_aguardando_peca, aviso_depois_da_data e audio_que_confirmou. Fase 6 (P6): a chave aprendizado — o modo, a lista, a última rodada, os erros de aprender:% em 24 h, os 6 zeros (em_uso_com_amostra_pequena, em_uso_fora_de_ligado, troca_grande_sem_pergunta, rodada_atrasada, medida_sem_classe, fator_fora_dos_limites; entram no ok) e as métricas (itens, medidas, trocas em 30 dias, o erro do fator, a pontualidade antes e depois da folga, o item desfeito 2 vezes em 4 semanas). CORREÇÃO FASE 6 (C2, item 12): as janelas do aprendizado vêm de agenda_config — a troca grande em aprender_saude_dias, a rodada atrasada em aprender_atraso_h, as métricas das trocas em aprender_parar_dias e o desfeito 2 vezes em aprender_trava_dias. FASE 7 (7a P7, spec §11): a chave gestor — os modos efetivos (marcar, encaixe, revisao, compre_ate, vaga, so_propor, desde), as regras, a última rodada (rotina gestor), as rodadas em 24 h, se os passos diários rodaram hoje, os erros de gestor:% em 24 h, os zeros obrigatórios (entram no ok: zona_travada_mexida e dia_avisado_sem_pergunta pela regra de _agenda_criticidade_da_acao, estimativa_sem_pergunta, prazo_em_critica, prazo_em_dia_prometido, aprovada_sem_data, rodada_gestor_atrasada, cliente_estimativa_sem_aprovacao, ficha_estimativa_sem_veto, onda_aplicada_sem_pergunta, alocacao_sem_fonte, regra_em_sombra_aplicada; os do que o gestor muda sozinho contam a partir de marcar_sozinho_desde) e prazo_vencido_sem_mostrar (só se conta: fica fora do ok), e os números (OS por estimativa, perguntas com prazo abertas/vencidas/respondidas/aplicadas pelo prazo, compre até gravados/cobrados/empurrados, fichas seguradas). E o erro do fator (métricas do aprendizado) só com as medidas que têm fator (a medida por estimativa é válida e não tem fator). FASE 7b (P5, §5.4, R4.3(g)): a chave equipe_dias (_agenda_saude_equipe7b): modos (dias, dupla, sabado, cadastro, chamar), a última rodada da semana da equipe e os erros de equipe_semana:% em 24 h, os zeros obrigatórios (entram no ok: dias_fora_da_janela, dias_duas_na_semana, dia_acima_do_teto, ficha_recusada_por_teto_com_dias, dupla_com_uma_pessoa — só a dita —, dupla_incompleta_com_gente_livre, novato_sozinho, sabado_sem_prazo, sabado_tarde, dono_em_vaga_sem_ok, resposta_sem_gravar) e os números (perguntadas × respondidas na última semana fechada e o %, adiadas pelo teto em 7 dias, a dupla inferida esperando o ajudante, duplas inferidas × ditas, sábados usados e em teste, a semana passada por pessoa: declarada × usada × cumprida). Sem os modos da 7b, os zeros são 0 e o ok é o de antes. FASE 7d (P8; §11, R6.3-11): a chave local (_agenda_saude_local), com os zeros obrigatórios no ok (acesso_sem_preparo, feriado_local_marcado, patio_acima_das_vagas, viagem_quebrada, rodada_local_atrasada); onde_fica em tipos_liberados. Sem os modos da 7d, os zeros são 0 e o ok é o de antes. FASE 7f (P7; §11, R2, R8.13): a chave comunicacao (_agenda_saude_comunicacao: os modos crus, a rodada comunicar, os zeros obrigatórios no ok e os números da comunicação); e o zero prazo_em_critica do gestor passa a ser a crítica com prazo fora de veto_tipos ou com veto_espera (a crítica pode vencer, AG7-15). FASE 7f (P6): a semana entra em cliente.tipos_liberados quando somar os dias aprovados (como o M11). FASE 7e (P7, §5.6, R7.5-17): a chave margem (_agenda_saude_margem), com zeros_ok no ok; os itens da margem saem dos zeros e das métricas do aprendizado da Fase 6 (em uso com amostra pequena: a folga da semana que volta ao padrão; em uso fora de ligado; troca grande sem pergunta; metricas.itens): eles estão na margem. FASE 7g (P6): a chave explicar (_agenda_saude_explicar: placar_atrasado, marcacao_aberta_vencida, rebaixar_sem_veto, rodada_atrasada e erros_dia, e os números), com zeros_ok no ok. Sem os modos da 7g, os zeros são 0 e o ok é o de antes.';

-- ── 7. A quinta ─────────────────────────────────────────────────────────────────────────────────────

create or replace function public._agenda_lote_texto(p_pecas jsonb)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select concat_ws(E'\n', nullif(btrim(p_pecas ->> 'cabecalho'), ''),
                   (select string_agg('• ' || btrim(m ->> 'texto'), E'\n' order by o)
                      from jsonb_array_elements(case when jsonb_typeof(p_pecas -> 'mudancas') = 'array' then p_pecas -> 'mudancas' else '[]'::jsonb end) with ordinality t(m, o)
                     where nullif(btrim(m ->> 'texto'), '') is not null),
                   nullif(btrim(p_pecas ->> 'fora'), ''), nullif(btrim(p_pecas ->> 'rodape'), ''))
         -- FASE 7g: (7g P6, R9.5-27) o placar, depois do rodapé e antes das perguntas, com uma linha em branco (o montador junta igual: o Q4p)
         || coalesce(E'\n\n' || nullif(btrim(p_pecas #>> '{placar,texto}'), ''), '')
         -- FASE 7g: fim
         || coalesce(E'\n\n' || nullif(btrim(p_pecas #>> '{perguntas,texto}'), ''), '');
$function$;

comment on function public._agenda_lote_texto(jsonb) is
  'Agenda de Produção (Fase 7f, P4; §5.4): o texto inteiro das peças do aviso (cabeçalho, "• " + cada mudança, o de fora, o rodapé, a linha em branco e as perguntas), o mesmo que _shared/agenda/aviso-do-gestor.ts junta quando cabe no teto. A sombra da quinta guarda este texto. IMMUTABLE, sem grant. FASE 7g (P6): com a peça placar (a quinta com modo_placar ligado), o texto dela depois do rodapé e antes das perguntas, com uma linha em branco dos dois lados; o montador junta igual. Sem a peça, o texto de antes.';

create or replace function public._agenda_comunicar_quinta(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_cab_mudou constant text := 'Agenda — o que eu mudei sozinho:';
  c_cab_nada  constant text := 'Agenda — a semana que vem:';
  c_rodape    constant text := '*agenda plano* mostra tudo.';
  c_preciso   constant text := 'Para a semana que vem preciso de:';
  c_audio     constant text := 'Pode ser um áudio só, citando o nome do cliente.';
  cf      public.agenda_config := public._agenda_cfg();
  v       public.agenda_dono_avisos;
  v_lig   boolean;
  v_m     jsonb;
  v_nm    int;
  v_lin   text[] := '{}';
  v_ids   uuid[] := '{}';
  v_tot   int := 0;
  v_perg  jsonb;
  v_pecas jsonb;
  v_txt   text;
  v_l     jsonb;
  v_pr    int := 0;
  r       record;
  -- FASE 7g: (7g P6, R9.5-27) o placar guardado da semana e o texto dele na mensagem
  v_7g_s  public.agenda_placar_semanas;
  v_7g_t  jsonb;
  -- FASE 7g: fim
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da mensagem da semana.' using errcode = '22023';
  end if;
  if extract(isodow from p_hoje)::int <> cf.dia_do_plano then
    return jsonb_build_object('pulado', true, 'motivo', 'dia');
  end if;
  -- d12: com 'fechamento', a semana vai no bloco da quinta (a parte semana do P3), nada aqui
  if cf.dono_semana_aviso <> 'propria' then
    return jsonb_build_object('pulado', true, 'motivo', 'fechamento');
  end if;
  if public._agenda_fala_modo('lote') = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'desligado');
  end if;
  if (p_agora at time zone 'America/Sao_Paulo')::time < cf.dono_semana_hora then
    return jsonb_build_object('pulado', true, 'motivo', 'cedo');
  end if;

  -- uma vez: a chave do dia. Saiu (a fila mandou e agenda_aviso_conferir contou as perguntas): o prazo que estava no texto.
  select * into v from public.agenda_dono_avisos x where x.dedupe_key = 'agenda-dono:semana:' || p_hoje::text;
  if found then
    if v.estado = 'enviada' then
      for r in select q.id from public.agenda_perguntas q
                where q.id = any (v.pergunta_ids) and q.estado = 'aberta' and q.veto_espera is null
                  and q.veto_ate is null and q.veto_teria_em is null and q.mostrada_em = v.enviada_em
                order by q.id loop
        v_l := public._agenda_pergunta_linha(r.id, p_hoje, v.enviar_em);
        continue when position(('· ' || (v_l ->> 'texto')) in v.texto) = 0;
        update public.agenda_perguntas q
           set veto_ate = (v_l ->> 'veto_ate')::timestamptz, veto_teria_em = (v_l ->> 'veto_diria')::timestamptz
         where q.id = r.id and q.veto_ate is null and q.veto_teria_em is null
           and (v_l ->> 'veto_ate' is not null or v_l ->> 'veto_diria' is not null);
        if found then
          v_pr := v_pr + 1;
        end if;
      end loop;
      -- FASE 7g: (7g P6, R9.5-27) o placar que foi no texto que saiu: enviado_em, de nulo à hora do envio, uma vez. Só com modo_placar ligado (fora dele a
      -- quinta não leva placar) e só se o texto que saiu tem o texto ou a linha do placar guardado ("onde ver", sozinho, não é o placar).
      if cf.modo_placar = 'ligado' then
        select s.* into v_7g_s from public.agenda_placar_semanas s
         where s.semana = (public._agenda_placar_periodo(p_hoje) ->> 'semana')::date and s.enviado_em is null;
        if found then
          v_7g_t := public._agenda_placar_texto(v_7g_s.numeros, v_7g_s.de, v_7g_s.ate, 'mensagem', cf.texto_max);
          if position((v_7g_t ->> 'texto') in v.texto) > 0 or position((v_7g_t ->> 'linha') in v.texto) > 0 then
            update public.agenda_placar_semanas s set enviado_em = coalesce(v.enviada_em, p_agora)
             where s.semana = v_7g_s.semana and s.enviado_em is null;
          end if;
        end if;
      end if;
      -- FASE 7g: fim
    end if;
    return jsonb_build_object('ja_saiu', true, 'estado', v.estado)
           || case when v_pr > 0 then jsonb_build_object('prazos', v_pr) else '{}'::jsonb end;
  end if;

  v_lig := public._agenda_lote_ligado();
  if not v_lig and exists (select 1 from public.agenda_vigia_rodadas x
                            where x.rotina = 'comunicar' and x.p_hoje = p_hoje and x.contagens #> '{quinta,quinta_diria}' is not null) then
    return jsonb_build_object('ja_diria', true);
  end if;

  -- o que mudou e não foi contado, e as perguntas na ordem, menos as que o dono já escolheu
  v_m := public._agenda_lote_mudancas(p_hoje);
  v_nm := jsonb_array_length(v_m);
  for r in select e, (e ->> 'id')::uuid as id
             from jsonb_array_elements(public.agenda_perguntas_em_ordem(p_hoje, p_agora)) e
             join public.agenda_perguntas q on q.id = (e ->> 'id')::uuid
            where q.opcao_escolhida is null and nullif(btrim(e ->> 'linha'), '') is not null
            order by (e ->> 'ordem')::int loop
    v_tot := v_tot + 1;
    if v_tot <= cf.perguntas_abertas_max then
      v_lin := v_lin || ('· ' || (r.e ->> 'linha'));
      v_ids := v_ids || r.id;
    end if;
  end loop;
  if v_nm = 0 and v_tot = 0 then
    return case when v_lig then jsonb_build_object('motivo', 'nada')
                else jsonb_build_object('quinta_diria', jsonb_build_object('texto', null, 'motivo', 'nada')) end;
  end if;
  if v_tot > 0 then
    v_perg := jsonb_build_object('texto', c_preciso || E'\n' || array_to_string(v_lin, E'\n')
                                          || case when v_tot > cardinality(v_lin) then E'\n' || format('(e mais %s em *agenda pendências*)', v_tot - cardinality(v_lin)) else '' end
                                          || E'\n' || c_audio,
                                 'pergunta_ids', to_jsonb(v_ids));
  end if;
  v_pecas := jsonb_build_object(
    'avisar', true, 'semana', true, 'rodada', p_agora, 'dia', p_hoje, 'limite', cf.gestor_aviso_texto_max,
    'cabecalho', case when v_nm > 0 then c_cab_mudou else c_cab_nada end,
    'mudancas', (select coalesce(jsonb_agg(jsonb_build_object('texto', g ->> 'texto', 'acao_ids', g -> 'acao_ids') order by o), '[]'::jsonb)
                   from jsonb_array_elements(v_m) with ordinality t(g, o)),
    'fora', case when v_nm > 0 then public._agenda_lote_fora(v_m) end,
    'rodape', c_rodape, 'perguntas', v_perg, 'perguntas_erro', null);
  -- FASE 7g: (7g P6, R9.5-27, R9.4-3) com modo_placar ligado, a peça placar ({texto, linha}) do placar guardado da semana, antes das perguntas (o montador
  -- e _agenda_lote_texto a juntam depois do rodapé), só com as linhas que têm dado e só com ao menos placar_min_linhas delas (sem contar mensagens). Sem o
  -- placar guardado, abaixo do mínimo ou fora de ligado, a chave não existe: as peças de antes. A quinta sem mudança e sem pergunta já voltou com nada.
  if cf.modo_placar = 'ligado' then
    select s.* into v_7g_s from public.agenda_placar_semanas s where s.semana = (public._agenda_placar_periodo(p_hoje) ->> 'semana')::date;
    if found then
      v_7g_t := public._agenda_placar_texto(v_7g_s.numeros, v_7g_s.de, v_7g_s.ate, 'mensagem', cf.texto_max);
      if (v_7g_t ->> 'linhas')::int >= cf.placar_min_linhas then
        v_pecas := v_pecas || jsonb_build_object('placar', jsonb_build_object('texto', v_7g_t ->> 'texto', 'linha', v_7g_t ->> 'linha'));
      end if;
    end if;
  end if;
  -- FASE 7g: fim
  if not v_lig then
    v_txt := public._agenda_lote_texto(v_pecas);
    return jsonb_build_object('quinta_diria', jsonb_build_object(
      'texto', v_txt, 'caracteres', char_length(v_txt), 'cabe', char_length(v_txt) <= cf.gestor_aviso_texto_max, 'mudancas', v_nm,
      'acao_ids', to_jsonb(array(select x::uuid from jsonb_array_elements(v_m) g, jsonb_array_elements_text(g -> 'acao_ids') x)),
      'perguntas', cardinality(v_ids), 'pergunta_ids', to_jsonb(v_ids), 'perguntas_abertas', v_tot));
  end if;
  return jsonb_build_object('avisos', jsonb_build_array(v_pecas), 'mudancas', v_nm, 'perguntas', cardinality(v_ids));
end;
$function$;

comment on function public._agenda_comunicar_quinta(date, timestamptz) is
  'Agenda de Produção (Fase 7f, P4; §5.4, §6.3, R8.5-12 a 14, AG7-22): o passo quinta da rodada comunicar. Só no dia_do_plano ({pulado, motivo dia}), com dono_semana_aviso = propria ({pulado, motivo fechamento}: a semana vai no bloco), com o lote fora de desligado ({pulado, motivo desligado}) e a partir de dono_semana_hora ({pulado, motivo cedo}). Uma vez por dia, pela chave agenda-dono:semana:<dia>: a 2ª vez = {ja_saiu, estado}, e, depois que a fila mandou, grava o prazo (veto_ate) e o que seria (veto_teria_em) de cada pergunta cuja linha está no texto que saiu ({prazos}). Com o lote ligado de verdade (_agenda_lote_ligado): {avisos: [as peças, como as de agenda_aviso_pecas, com semana = true]} — o cabeçalho, o que mudou e não foi contado (_agenda_lote_mudancas), o de fora, o rodapé e "Para a semana que vem preciso de:" com até perguntas_abertas_max linhas de agenda_perguntas_em_ordem, "(e mais N em *agenda pendências*)" e "Pode ser um áudio só, citando o nome do cliente.". Sai mesmo sem mudança, com pergunta; sem nada = {motivo nada}. Em sombra: {quinta_diria: {texto, caracteres, cabe, mudancas, acao_ids, perguntas, pergunta_ids}}, uma vez por dia ({ja_diria}). Volatile, sem grant. FASE 7g (P6): com modo_placar ligado, as peças ganham placar = {texto, linha} do placar guardado da semana (agenda_placar_semanas, pela placar_janela), só com as linhas com dado e com ao menos placar_min_linhas delas (sem contar mensagens); em sombra (o lote em sombra) o quinta_diria o leva junto. Depois que a fila mandou (o ramo já saiu, estado enviada), grava enviado_em no placar quando o texto que saiu tem o texto ou a linha dele. Fora de ligado, as peças e o ramo já saiu de antes, byte a byte. Sem mudança e sem pergunta, continua sem sair: nenhuma mensagem só de placar.';

-- ── 8. O motivo ferramenta (AG7-27) ─────────────────────────────────────────────────────────────────

create or replace function public._agenda_motivo_dito(p_motivo text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  with w as (select public._agenda_normal(p_motivo) as v)
  select case
    when w.v = '' then null
    when replace(w.v, ' ', '_') in ('material', 'cliente_ou_bem', 'equipe_faltou', 'trabalho_anterior', 'informacao', 'clima',
                                    'estimativa', 'imprevisto_tecnico', 'urgencia_outra_os', 'esqueci', 'concluida_antes')
      then replace(w.v, ' ', '_')
    when w.v in ('peca', 'pecas', 'falta peca', 'falta de peca', 'faltou peca', 'faltou material', 'falta material') then 'material'
    when w.v in ('cliente', 'bem', 'barco', 'lancha', 'motorhome', 'cliente nao liberou', 'cliente desmarcou', 'cliente cancelou')
      then 'cliente_ou_bem'
    when w.v in ('equipe', 'faltou', 'faltou gente', 'nao veio', 'ninguem veio', 'falta de gente') then 'equipe_faltou'
    when w.v in ('anterior', 'servico anterior', 'outro servico atrasou') then 'trabalho_anterior'
    when w.v in ('info', 'falta informacao', 'faltou informacao') then 'informacao'
    when w.v in ('chuva', 'choveu', 'tempo', 'vento', 'mau tempo') then 'clima'
    when w.v in ('demorou', 'demorou mais') then 'estimativa'
    when w.v in ('imprevisto', 'problema', 'defeito') then 'imprevisto_tecnico'
    when w.v in ('urgencia', 'urgente', 'outra os', 'emergencia') then 'urgencia_outra_os'
    when w.v in ('esquecimento') then 'esqueci'
    when w.v in ('terminou antes', 'acabou antes', 'concluiu antes') then 'concluida_antes'
    -- FASE 7g: (7g P6, AG7-27, §3.1 item 12) faltou ferramenta ou carro: as palavras e o código (nenhuma colide com as de cima; "faltou" sozinho segue equipe)
    when w.v in ('ferramenta', 'ferramentas', 'carro', 'sem carro', 'veiculo', 'faltou ferramenta', 'faltou carro') then 'ferramenta'
    -- FASE 7g: fim
  end
  from w;
$function$;

comment on function public._agenda_motivo_dito(text) is
  'Agenda de Produção (Fase 2, P3): o motivo de um dia que não foi como no plano, pelas palavras do dono ("cliente", "chuva", "equipe", "imprevisto"…) ou pelo código, → o código LCI (material, cliente_ou_bem, equipe_faltou, trabalho_anterior, informacao, clima, estimativa, imprevisto_tecnico, urgencia_outra_os, esqueci, concluida_antes). null = não entendi. FASE 7g (P6): o código ferramenta (AG7-27): ferramenta, ferramentas, carro, sem carro, veiculo, faltou ferramenta e faltou carro.';

create or replace function public._agenda_motivo_texto(p_codigo text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case p_codigo
    when 'material' then 'material'
    when 'cliente_ou_bem' then 'cliente'
    when 'equipe_faltou' then 'equipe'
    when 'trabalho_anterior' then 'trabalho anterior'
    when 'informacao' then 'informação'
    when 'clima' then 'chuva'
    when 'estimativa' then 'estimativa'
    when 'imprevisto_tecnico' then 'imprevisto'
    when 'urgencia_outra_os' then 'urgência em outra OS'
    when 'esqueci' then 'esqueci'
    when 'concluida_antes' then 'terminou antes'
    -- FASE 7g: (7g P6, AG7-27) o motivo ferramenta em palavras
    when 'ferramenta' then 'ferramenta ou carro'
    -- FASE 7g: fim
    else p_codigo end;
$function$;

comment on function public._agenda_motivo_texto(text) is
  'Agenda de Produção (Fase 2, P3): o motivo LCI em uma palavra ("cliente", "chuva", "imprevisto"). FASE 7g (P6): ferramenta = "ferramenta ou carro" (AG7-27).';

create or replace function public.agenda_conferir_dia(p_autor uuid, p_resultado text, p_motivo text default null,
                                                      p_quando text default null, p_canal text default 'whatsapp',
                                                      p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config;
  v_autor uuid := public._autor_da_agenda(p_autor);
  v_d     jsonb;
  v_dia   date;
  v_pal   text;
  v_qdo   text;
begin
  if p_resultado is null or p_resultado not in ('cumprido', 'parcial', 'nao_cumprido') then
    raise exception 'Resultado desconhecido: "%" (cumprido, parcial ou nao_cumprido).', coalesce(p_resultado, '') using errcode = '22023';
  end if;
  cf := public._agenda_cfg();
  if cf.modo_proposta <> 'ligado' then
    return jsonb_build_object('ok', false, 'mudou', false, 'texto', 'Ainda não tenho plano publicado: a agenda automática está em teste.');
  end if;
  if p_resultado in ('parcial', 'nao_cumprido') and public._agenda_motivo_dito(p_motivo) is null then
    return jsonb_build_object('ok', false, 'mudou', false, 'pede', 'motivo', 'texto', public._agenda_ajuda_do_motivo(p_resultado));
  end if;
  if nullif(btrim(coalesce(p_quando, '')), '') is not null then
    begin
      v_d := public.agenda_data_dita(p_quando, p_hoje, 'passado');
    exception when sqlstate '22007' then
      return jsonb_build_object('ok', false, 'mudou', false, 'texto', sqlerrm);
    end;
    if (v_d ->> 'de') is distinct from (v_d ->> 'ate') then
      return jsonb_build_object('ok', false, 'mudou', false, 'texto', 'Diga um dia só (por exemplo "ontem" ou "segunda").');
    end if;
    v_dia := (v_d ->> 'de')::date;
  else
    -- sem dia dito: a conferência aberta mais recente; sem ela, hoje se algum meio-dia já começou (d19)
    select q.dia into v_dia from public.agenda_perguntas q
     where q.tipo = 'conferencia' and q.estado = 'aberta' and q.dia <= p_hoje
     order by q.dia desc, q.criada_em desc, q.id desc limit 1;
    -- A conferência de um dia anterior ficou sem resposta e hoje também tem plano: *choveu* às 08:30 é de hoje ou de
    -- ontem? O banco não escolhe (a mudança executa direto e replaneja): pergunta, sem mudar nada. Para cumprido e
    -- parcial, só quando algum meio-dia de hoje já começou (às 07:00 o "dia feito" ainda é o de ontem, d19).
    if v_dia is not null and v_dia < p_hoje
       and exists (select 1 from public.agenda_alocacoes a
                    where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = p_hoje
                      and (p_resultado = 'nao_cumprido' or lower(a.periodo) <= p_agora)) then
      v_pal := case
        when p_resultado = 'cumprido' then 'dia feito'
        when p_resultado = 'nao_cumprido' and public._agenda_motivo_dito(p_motivo) = 'clima' then 'choveu'
        else (case p_resultado when 'parcial' then 'dia parcial ' else 'dia não ' end)
             || case public._agenda_motivo_dito(p_motivo)
                  when 'material' then 'material' when 'cliente_ou_bem' then 'cliente' when 'equipe_faltou' then 'equipe'
                  when 'trabalho_anterior' then 'anterior' when 'informacao' then 'informação' when 'clima' then 'clima'
                  when 'estimativa' then 'estimativa' when 'imprevisto_tecnico' then 'imprevisto'
                  -- FASE 7g: (7g P6, AG7-27; R9.5-15: a 3ª cópia da lista) a palavra do motivo ferramenta na pergunta "hoje ou ontem?" (sem ela, "imprevisto")
                  when 'ferramenta' then 'ferramenta'
                  -- FASE 7g: fim
                  when 'urgencia_outra_os' then 'urgência' when 'esqueci' then 'esqueci' else 'imprevisto' end end;
      v_qdo := case when v_dia = p_hoje - 1 then 'ontem' when v_dia = p_hoje - 2 then 'anteontem' else to_char(v_dia, 'DD/MM') end;
      return jsonb_build_object('ok', false, 'mudou', false, 'pede', 'dia', 'dias', jsonb_build_array(p_hoje, v_dia),
        'texto', format('Hoje (%s) ou %s? Diga *%s hoje* ou *%s %s*.', public._dia_curto(p_hoje),
                        case when v_dia = p_hoje - 1 then 'ontem (' || public._dia_curto(v_dia) || ')' else public._dia_curto(v_dia) end,
                        v_pal, v_pal, v_qdo));
    end if;
    if v_dia is null then
      if exists (select 1 from public.agenda_alocacoes a
                  where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = p_hoje and lower(a.periodo) <= p_agora) then
        v_dia := p_hoje;
      else
        return jsonb_build_object('ok', false, 'mudou', false, 'texto', 'Hoje ainda não começou nada do plano.');
      end if;
    end if;
  end if;
  return public.agenda_registrar_dia(v_autor, v_dia, p_resultado, p_motivo, null, null, 'dia_feito', null, p_hoje, p_agora, p_canal);
end;
$function$;

comment on function public.agenda_conferir_dia(uuid, text, text, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): a entrada das palavras *dia feito*, *dia parcial <motivo>*, *dia não <motivo>* — o dia é o dito (p_quando, agenda_data_dita passado: "ontem", "segunda", "dd/mm"), senão a conferência aberta mais recente (d19) — mas se ela é de um dia anterior e hoje também tem plano (para não cumprido, qualquer meio-dia; para cumprido e parcial, um que já começou), nada muda e a pergunta volta: "Hoje (qua 04/11) ou ontem (ter 03/11)? Diga *choveu hoje* ou *choveu ontem*." —, senão hoje se algum meio-dia já começou ("Hoje ainda não começou nada do plano."). Fora de modo_proposta ligado: "Ainda não tenho plano publicado: a agenda automática está em teste." (nada muda). Chama agenda_registrar_dia com todas as alocações do dia. Admin pelo _autor_da_agenda. FASE 7g (P6): a pergunta "hoje ou ontem?" diz *dia não ferramenta* para o motivo ferramenta (AG7-27; antes cairia em imprevisto).';

-- ── 9. As portas ────────────────────────────────────────────────────────────────────────────────────
-- As 5 internas, só o service_role (§3.1 item 13): quem as chama é a rodada (service_role), a quinta (da rodada comunicar, definer) e as 2 definer abaixo, que
-- rodam como o dono. A leitura e a saúde, definer com porta dentro, com execute a authenticated (o painel: agenda_saude é invoker e agenda_ver também) e ao
-- service_role, nunca anon. As recriadas mantêm as portas delas (create or replace não muda a ACL).
revoke all on function public._agenda_placar_periodo(date, date), public._agenda_mensagens_da_agenda(date, date),
  public._agenda_placar_numeros(date, date, date), public._agenda_placar_texto(jsonb, date, date, text, integer),
  public._agenda_explicar_placar(date, timestamptz) from public, anon, authenticated;
grant execute on function public._agenda_placar_periodo(date, date), public._agenda_mensagens_da_agenda(date, date),
  public._agenda_placar_numeros(date, date, date), public._agenda_placar_texto(jsonb, date, date, text, integer),
  public._agenda_explicar_placar(date, timestamptz) to service_role;
revoke all on function public.agenda_placar(date, date, timestamptz), public._agenda_saude_explicar(date, timestamptz) from public, anon;
grant execute on function public.agenda_placar(date, date, timestamptz), public._agenda_saude_explicar(date, timestamptz) to authenticated, service_role;
