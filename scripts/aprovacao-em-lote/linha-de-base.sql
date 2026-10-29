-- Linha de base da aprovação em lote (Fase 0 do plano de 28/10/2026). SÓ LEITURA: só SELECT, nada é gravado.
--
-- Para que serve: medir antes e depois (Fase 6) o que o dono vive quando pede várias ações de uma vez — quantos "sim"
-- ele dá, quanto fica para trás, se o assistente fica sabendo do que foi decidido e se as falhas aparecem. O mesmo
-- script, com o mesmo período de tamanho, é rodado antes e depois: o que vale é a comparação.
--
-- Como rodar (só leitura; o SQL longo vai por arquivo):
--   npx -y supabase@2.111.0 --workdir "<repo principal>" db query --linked -f scripts/aprovacao-em-lote/linha-de-base.sql
-- O período fica no CTE `periodo` (padrão: os últimos 90 dias). Nenhum telefone nem texto livre sai: só contagens,
-- nomes de ação e títulos de pendência.
--
-- Conferência de 29/10/2026, com o período do estudo (30/07 22:30 a 28/10 22:30, Brasília) — bate com o estudo:
--   127 pendências (68 executadas, 26 vencidas, 26 rejeitadas, 7 com falha); 53 aprovações pelo WhatsApp e 0
--   registradas na conversa; 22 de 22 no painel; 156 turnos com gravação direta, 20 gravações com erro, 12 turnos com
--   2 ou mais gravações e alguma falha (17 contando os de uma gravação só). Vencidas que eram itens de pedido com
--   várias ações: 24 de 26 pela regra dos 60 s (o estudo listou 23 — 21/08, 31/08 duas vezes e 29/09; a 24ª é um par
--   de lancar_no_caixa de 25/09).
--
-- O que é aproximação (vale para comparar antes × depois, não como número exato do estudo):
--   - "pedido com várias ações" = pendências da mesma sessão nascidas a até 60 s da anterior (a janela da fila de
--     hoje) ou, a partir da Fase 2, com a mesma marca payload->>'_pedido'. Ações que nunca viraram pendência (o Max
--     parava no 1º item) não entram: o estudo as contou lendo os pedidos do dono.
--   - perguntas "você fez?" e pedidos de "continua" são lidos por expressão regular nas mensagens do dono.
with periodo as (
  select now() - interval '90 days' as de, now() as ate
),
admins as (
  select id from public.app_users where role = 'admin'
),
pend as (
  select p.id, p.session_id, p.action_name, p.status, p.created_at, p.executed_at, p.expires_at, p.title,
         p.payload->>'_pedido' as marca, s.channel, s.owner_user_id as dono
    from public.ai_operator_pending_actions p
    left join public.ai_operator_sessions s on s.id = p.session_id
   where p.created_at >= (select de from periodo) and p.created_at < (select ate from periodo)
),
marcado as (
  select pend.*,
         case when lag(created_at) over w is null or created_at - lag(created_at) over w > interval '60 seconds'
              then 1 else 0 end as nova
    from pend
  window w as (partition by session_id order by created_at)
),
rodada as (
  select marcado.*,
         coalesce(marca, session_id::text || ':' ||
                  sum(nova) over (partition by session_id order by created_at rows unbounded preceding)::text) as pedido
    from marcado
),
pedidos as (
  select pedido, min(channel) as channel, min(created_at) as inicio, count(*) as itens,
         count(*) filter (where status = 'executed') as executados,
         count(*) filter (where status = 'executed'
                            and (executed_at at time zone 'America/Sao_Paulo')::date
                              = (created_at at time zone 'America/Sao_Paulo')::date) as executados_no_dia,
         count(*) filter (where status = 'expired') as vencidos
    from rodada
   group by pedido
),
-- Decisões do dono: o "sim"/"não" do WhatsApp (payload.channel = 'whatsapp') e o clique na tela (cartão do chat e
-- sino chamam o mesmo confirm_action, que não grava canal).
decisoes as (
  select a.id, a.created_at, a.actor_user_id, split_part(a.event_type, ':', 1) as tipo,
         coalesce(a.payload->>'channel', 'tela') as canal, p.session_id, p.title
    from public.ai_operator_audit a
    left join public.ai_operator_pending_actions p on p.id = a.pending_action_id
   where a.created_at >= (select de from periodo) and a.created_at < (select ate from periodo)
     and (a.event_type like 'approve_execute:%' or a.event_type like 'reject:%')
),
-- A decisão está na conversa que o modelo lê? Uma fala do assistente com o título da pendência, até 2 min depois,
-- na sessão da pendência ou numa sessão de quem decidiu.
decisoes_na_conversa as (
  select d.*,
         exists (
           select 1
             from public.ai_operator_messages m
             join public.ai_operator_sessions s on s.id = m.session_id
            where (m.session_id = d.session_id or s.owner_user_id = d.actor_user_id)
              and m.role = 'assistant'
              and m.created_at between d.created_at - interval '5 seconds' and d.created_at + interval '2 minutes'
              and coalesce(d.title, '') <> ''
              and position(d.title in coalesce(m.content, '')) > 0
         ) as na_conversa
    from decisoes d
),
-- Vencida com aviso = uma fala do assistente, depois do prazo, dizendo que venceu (Fase 1 em diante). No WhatsApp a
-- linha vai para a conversa que o modelo lê agora (outra sessão do mesmo dono), por isso vale qualquer sessão dele.
vencidas as (
  select r.*, pd.itens,
         exists (
           select 1 from public.ai_operator_messages m
             join public.ai_operator_sessions s2 on s2.id = m.session_id
            where (m.session_id = r.session_id or s2.owner_user_id = r.dono) and m.role = 'assistant'
              and m.created_at >= r.expires_at - interval '5 minutes'
              and m.created_at < r.expires_at + interval '1 day'
              and m.content ~* 'venc(eu|eram)'
              and position(r.title in coalesce(m.content, '')) > 0
         ) as avisada
    from rodada r join pedidos pd on pd.pedido = r.pedido
   where r.status = 'expired'
),
-- Gravações que rodam DIRETO (sem "sim") nas sessões dos administradores, agrupadas pelo turno: as linhas de um turno
-- são gravadas juntas no fim dele (mesmo created_at), então o turno de uma gravação é a primeira fala do usuário
-- gravada a partir dela.
escritas as (
  select a.session_id, s.channel, a.created_at, split_part(a.event_type, ':', 2) as ferramenta,
         (a.payload->>'result_summary') ilike '%"error"%' as erro
    from public.ai_operator_audit a
    join public.ai_operator_sessions s on s.id = a.session_id
   where s.owner_user_id in (select id from admins)
     and a.created_at >= (select de from periodo) and a.created_at < (select ate from periodo)
     and a.event_type like 'tool:%'
     and split_part(a.event_type, ':', 2) ~ '^(create_|add_|remove_|edit_|update_|delete_|set_|apply_|definir_|record_survey|close_service_survey|start_service_survey|log_service_order|acompanhar_conversa|parar_acompanhamento|schedule_self_reminder|cancel_scheduled)'
),
escritas_com_turno as (
  select e.*,
         (select min(m.created_at) from public.ai_operator_messages m
           where m.session_id = e.session_id and m.role = 'user' and m.created_at >= e.created_at - interval '2 seconds') as fim
    from escritas e
),
turnos_com_escrita as (
  select session_id, channel, coalesce(fim, created_at) as fim, count(*) as n, count(*) filter (where erro) as erros
    from escritas_com_turno
   group by 1, 2, 3
),
turnos_com_falha as (
  select t.*,
         (select string_agg(coalesce(m.content, ''), ' ')
            from public.ai_operator_messages m
           where m.session_id = t.session_id and m.role = 'assistant' and m.created_at = t.fim and m.tool_calls is null) as texto_final
    from turnos_com_escrita t
   where t.erros > 0
),
falas_do_dono as (
  select m.content
    from public.ai_operator_messages m
    join public.ai_operator_sessions s on s.id = m.session_id
   where s.owner_user_id in (select id from admins) and m.role = 'user'
     and m.created_at >= (select de from periodo) and m.created_at < (select ate from periodo)
)
select jsonb_build_object(
  'periodo', (select jsonb_build_object('de', to_char(de at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'),
                                         'ate', to_char(ate at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')) from periodo),
  'pendencias', (select jsonb_build_object(
      'total', count(*),
      'executadas', count(*) filter (where status = 'executed'),
      'vencidas', count(*) filter (where status = 'expired'),
      'rejeitadas', count(*) filter (where status = 'rejected'),
      'com_falha', count(*) filter (where status = 'failed'),
      'abertas', count(*) filter (where status in ('pending', 'approved')),
      'por_canal', (select jsonb_object_agg(coalesce(channel, 'sem_sessao'), n)
                      from (select channel, count(*) as n from pend group by channel) c)
    ) from pend),
  'mais_pedidas', (select jsonb_agg(jsonb_build_object('acao', action_name, 'n', n) order by n desc, action_name)
                     from (select action_name, count(*) as n from pend group by action_name order by 2 desc, 1 limit 8) x),
  'pedidos_com_varias_acoes', (select jsonb_build_object(
      'pedidos', count(*),
      'itens', coalesce(sum(itens), 0),
      'executados', coalesce(sum(executados), 0),
      'executados_no_mesmo_dia', coalesce(sum(executados_no_dia), 0),
      'pct_feitos_no_mesmo_dia', case when sum(itens) > 0 then round(100.0 * sum(executados_no_dia) / sum(itens)) end,
      'vencidos', coalesce(sum(vencidos), 0),
      'com_marca_do_pedido', (select count(distinct marca) from pend where marca is not null)
    ) from pedidos where itens >= 2),
  'decisoes', (select jsonb_object_agg(k, n) from (
      select tipo || '/' || canal as k, count(*) as n from decisoes group by 1) x),
  'decisoes_registradas_na_conversa', (select jsonb_object_agg(k, v) from (
      select tipo || '/' || canal as k,
             jsonb_build_object('total', count(*), 'na_conversa', count(*) filter (where na_conversa)) as v
        from decisoes_na_conversa group by 1) x),
  'vencidas', (select jsonb_build_object(
      'total', count(*),
      'itens_de_pedido_com_varias_acoes', count(*) filter (where itens >= 2),
      'com_aviso_na_conversa', count(*) filter (where avisada),
      'sem_aviso', count(*) filter (where not avisada)
    ) from vencidas),
  'gravacoes_diretas', (select jsonb_build_object(
      'turnos', count(*),
      'gravacoes', coalesce(sum(n), 0),
      'gravacoes_com_erro', coalesce(sum(erros), 0),
      'turnos_com_alguma_falha', count(*) filter (where erros > 0),
      'turnos_com_2_ou_mais_e_alguma_falha', count(*) filter (where erros > 0 and n >= 2)
    ) from turnos_com_escrita),
  'falhas_citadas', (select jsonb_build_object(
      'turnos_com_falha', count(*),
      'citadas_pelo_sistema', count(*) filter (where texto_final ilike '%Conferido pelo sistema%'),
      'citadas_pelo_modelo', count(*) filter (where texto_final ~* '(n[aã]o (entrou|entraram|consegui|foi poss[ií]vel|deu certo)|falh|erro)'
                                                and texto_final not ilike '%Conferido pelo sistema%'),
      'sem_citacao', count(*) filter (where coalesce(texto_final, '') !~* '(Conferido pelo sistema|n[aã]o (entrou|entraram|consegui|foi poss[ií]vel|deu certo)|falh|erro)')
    ) from turnos_com_falha),
  'falas_do_dono', (select jsonb_build_object(
      'total', count(*),
      -- No Postgres o limite de palavra é \y (\b é backspace).
      'perguntas_voce_fez', count(*) filter (where content ~* '(voc[eê]|vc)\s+(registrou|cadastrou|lan[cç]ou|fez|terminou|alterou|mudou|enviou|mandou)|conseguiu\??$|\ye\s+(os|as)\s+(outr[oa]s|demais)\y|fez tod[oa]s|cadastrou todos|registrou todos|lan[cç]ou todos|faltou algum|falta algum|todos os servi'),
      'pedidos_de_continuar', count(*) filter (where content ~* '\y(continua|continue|segue com os|segue com as|pode seguir|faz o resto|faz os outros|faz as outras|cadastra os outros|registra os outros|manda o pr[oó]ximo|o pr[oó]ximo)\y')
    ) from falas_do_dono)
) as linha_de_base;
