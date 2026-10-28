-- Agenda de Produção, Fase 5 ("Mensagens ao cliente"), pacote P6: a tela — o bloco "Cliente" do cartão "Plano" da OS (o
-- que foi dito ao cliente, a confirmação, as mensagens desta OS e o que espera o dono), pela chave cliente de
-- os_plano_da_os.
-- Spec: scratchpad agenda-pesquisa/spec-fase5.md (§5.6, §5.7, §9 P6). Decisões do dono 23/10 (o gestor manda sozinho as
-- mensagens-modelo; os 3 primeiros dias de cada tipo passam pelo dono; o crítico sempre pergunta). Depende de 20261028100000
-- (as tabelas), 100100 (o telefone), 100200 (os textos do envio: o tipo, o quando, a conversa, o opt-out), 100300 (o risco)
-- e 100500 (o foco clientes e o texto do efeito).
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (1 função nova, 1 recriada; nenhuma tabela, nenhum gatilho, nenhum dado)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f5p6/montar-migration.mjs: a parte escrita à mão e o
-- corpo de os_plano_da_os copiado da migration mais nova que a define (20261026100600, conferido com grep em 27/10: nenhuma
-- migration posterior a recriou), com o bloco "-- FASE 5:" conferido (fora dele nenhuma linha muda).
--
-- POR QUE: o dono lê as mensagens ao cliente pela conversa (*agenda clientes*), mas, na tela da OS, o cartão "Plano" não
-- dizia o que o cliente ouviu nem o que a agenda mandou ou vai mandar a ele. Sem isso, quem abre a OS para ligar ao cliente
-- não sabe que data ele tem na cabeça.
--
-- O QUE MUDA:
--   1. _agenda_cliente_da_os (nova; invoker, sem grant: só os_plano_da_os a chama): a chave cliente — o contato (telefone,
--      conversa no último ano, opt-out), o que foi dito (os_planejamento.prometido_*) e se ainda vale
--      (_agenda_cliente_risco), a confirmação (client_confirmed_for), como o serviço é dito ao cliente, as 5 mensagens mais
--      recentes desta OS com o estado como o dono lê (o efeito da resposta por _agenda_cliente_efeito_texto) e o que espera
--      o dono (a conta do foco clientes, _agenda_ver_clientes). Em teste, "Em teste: nada sai ainda".
--   2. os_plano_da_os (recriada; corpo de 20261026100600): a chave cliente, num bloco "-- FASE 5:" logo no começo do
--      jsonb_build_object. As outras chaves não mudam.
--
-- O QUE NÃO MUDA: nenhuma mensagem sai e nada é gravado (as duas são STABLE). A tela não ganha botão de mandar: a aprovação
-- continua pela palavra (*manda cliente <nome>* / *segura cliente <nome>*) ou pela conversa, e o texto da tela só a cita. A
-- porta do cartão continua a mesma (administrador e financeiro com login, ou service_role; senão 42501).
--
-- DINHEIRO: nada. O cartão continua sem valor (a diária só "lançada" ou "a confirmar"); a mensagem ao cliente nunca leva
-- valor (_agenda_cliente_texto_proibido, P1/P2).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase5_telas.sql e anotadas em notas-fase5.md):
--   · A chave cliente traz, além do que a §5.6 lista, o modo, o nome, o contato_texto, o serviço dito ao cliente, o
--     risco_texto do prometido e mensagens_mais (o que passa das 5): a tela não calcula nada.
--   · opt_out = o cliente não recebe (opt-out, cadastro inativo ou número bloqueado: _agenda_cliente_sem_mensagem), como o
--     envio decide.
--   · A chave sai mesmo com modo_cliente desligado (o prometido gravado pelo botão antigo ou pelo *grava* vale sempre); a tela
--     esconde o bloco quando está desligado e não há nem prometido nem mensagem.
--
-- ORDEM DE LIGAR: depois de 20261028100000..100500; antes do front (o cartão novo lê a chave cliente; o cartão de antes
-- ignora a chave). Aplicar sozinha não muda nada para ninguém.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase5_telas.sql (T1 a chave cliente com a fixture; T2 a cópia só muda
-- no bloco) e supabase/tests/agenda_fase5_pos_deploy.sql. Na bancada: node scripts/bancada-agenda/rodar.mjs
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261028100600_agenda_fase5_telas.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261028100600', 'agenda_fase5_telas');"
--
-- DESFAZER: reaplicar os_plano_da_os de 20261026100600 (o cartão volta sem a chave cliente) e
--   drop function if exists public._agenda_cliente_da_os(uuid, date);
--
-- IDEMPOTENTE: create or replace; as portas repetidas.

-- ── 1. O bloco "Cliente" do cartão "Plano" da OS ────────────────────────────────────────────────────────

-- A chave cliente de os_plano_da_os (spec §5.6): o contato do cliente (telefone, conversa, opt-out), o que foi dito a ele
-- (os_planejamento.prometido_*) e se ainda vale (_agenda_cliente_risco), a confirmação, como o serviço é dito a ele, as
-- mensagens desta OS (as 5 mais recentes, com o estado como o dono lê) e o que espera o dono (a mesma conta do foco
-- clientes: _agenda_ver_clientes). Invoker e sem grant: só os_plano_da_os (definer, confere o administrador e o
-- financeiro) a chama. A tela não tem botão de mandar: a aprovação é pela palavra (*manda cliente <nome>* / *segura
-- cliente <nome>*), que o texto cita. null sem a OS ou sem o cliente.
create or replace function public._agenda_cliente_da_os(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf        public.agenda_config := public._agenda_cfg();
  v_agora   timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  so        record;
  pl        public.os_planejamento%rowtype;
  v_tel     boolean;
  v_sem     boolean;
  v_conv    boolean;
  v_contato text;
  v_prom    jsonb;
  v_risco   jsonb;
  v_risco_t text;
  v_msgs    jsonb;
  v_total   int;
  v_esp     int;
  v_ped     int;
  v_esp_t   text;
  -- estrutura, não parâmetro: a lista curta do cartão (spec §5.6, "até 5"); o resto, *agenda clientes* mostra
  c_lista   constant int := 5;
begin
  select s.id, s.client_id, s.client_confirmed_for,
         public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(c.display_name, '')), ''), c.name)) as nome
    into so
    from public.service_orders s left join public.clients c on c.id = s.client_id
   where s.id = p_os;
  if so.id is null or so.client_id is null then
    return null;
  end if;
  select * into pl from public.os_planejamento x where x.service_order_id = p_os;

  -- o contato (as mesmas regras do envio e do foco: o número que é de alguém da HBR conta como sem telefone)
  v_tel := public._agenda_cliente_telefone(so.client_id) is not null;
  v_sem := public._agenda_cliente_sem_mensagem(so.client_id);
  v_conv := public._agenda_cliente_conversou(so.client_id, v_agora);
  v_contato := case when not v_tel then 'sem telefone no cadastro'
                    when v_sem then 'pediu para não receber mensagens'
                    when not v_conv then 'não escreveu para a HBR no último ano; por ora só mando a quem já escreveu' end;

  -- o que foi dito ao cliente (≠ o plano) e se ainda vale
  if pl.prometido_ate is not null then
    v_risco := public._agenda_cliente_risco(p_os, p_hoje);
    if coalesce((v_risco ->> 'risco')::boolean, false) then
      v_risco_t := case
        when coalesce((v_risco ->> 'sem_data')::boolean, false)
          then 'Pode atrasar: o material ainda não tem previsão, então ainda não sei a data nova.'
        when v_risco ->> 'faixa_de' = v_risco ->> 'faixa_ate'
          then format('Pode atrasar: agora a previsão é %s.', public._dia_curto((v_risco ->> 'faixa_de')::date))
        else format('Pode atrasar: agora a previsão é de %s a %s.', public._dia_curto((v_risco ->> 'faixa_de')::date),
                    public._dia_curto((v_risco ->> 'faixa_ate')::date)) end
        || case when coalesce((v_risco ->> 'passou')::boolean, false) then ' A data que ele ouviu já passou.' else '' end;
    end if;
    v_prom := jsonb_build_object(
      'tipo', pl.prometido_tipo, 'de', coalesce(pl.prometido_de, pl.prometido_ate), 'ate', pl.prometido_ate,
      'original_ate', pl.prometido_original_ate, 'fonte', pl.prometido_fonte,
      'texto', case when coalesce(pl.prometido_de, pl.prometido_ate) = pl.prometido_ate then public._dia_curto(pl.prometido_ate)
                    else format('de %s a %s', public._dia_curto(pl.prometido_de), public._dia_curto(pl.prometido_ate)) end
               || format(' (%s, %s%s)',
                         case pl.prometido_tipo when 'firme' then 'data firme' when 'faixa' then 'uma faixa'
                                                else 'depende da peça' end,
                         case pl.prometido_fonte when 'mensagem' then 'por mensagem da agenda' when 'dono' then 'por você'
                                                 else 'pela confirmação' end,
                         coalesce(' em ' || public._dia_curto((pl.prometido_em at time zone 'America/Sao_Paulo')::date), ''))
               || case when pl.prometido_original_ate is not null and pl.prometido_original_ate <> pl.prometido_ate
                       then format('; a 1ª data dita foi %s', public._dia_curto(pl.prometido_original_ate)) else '' end,
      'risco_texto', v_risco_t);
  end if;

  -- as mensagens desta OS: as 5 mais recentes (a que vai sair primeiro, depois as que saíram), com o estado como o dono lê
  select count(*)::int into v_total from public.agenda_cliente_mensagens m where m.service_order_id = p_os;
  select coalesce(jsonb_agg(y.j order by y.quando desc, y.id desc), '[]'::jsonb) into v_msgs
    from (select m.id, coalesce(m.enviada_em, m.enviar_em) as quando,
                 jsonb_build_object(
                   'tipo', m.tipo,
                   'tipo_texto', public._agenda_maiuscula(public._agenda_cliente_tipo_texto(m.tipo)),
                   'quando_texto', case
                     -- a viva: quando sai ("agora", "amanhã às 09:00"; a do teste, só a que ainda vai sair); a que saiu
                     -- ou a do teste que teria saído: o dia e a hora
                     when m.enviada_em is null and m.estado in ('registrada', 'aguardando_dono', 'enfileirada')
                          and (m.modo = 'ligado' or m.enviar_em > v_agora)
                       then public._agenda_cliente_quando_texto(m.enviar_em, v_agora)
                     else public._dia_curto((coalesce(m.enviada_em, m.enviar_em) at time zone 'America/Sao_Paulo')::date)
                          || ' às ' || to_char(coalesce(m.enviada_em, m.enviar_em) at time zone 'America/Sao_Paulo', 'HH24:MI') end,
                   'estado', m.estado,
                   'estado_texto', case
                     when m.modo = 'sombra' then case
                       when m.estado = 'recusada' then 'em teste: não sairia'
                       when m.enviar_em <= v_agora then 'em teste: teria saído'
                       else 'em teste: sairia' end
                     when m.estado = 'aguardando_dono' and m.aprovacao = 'critica'
                       then 'é uma decisão sua: responda na conversa (1, 2 ou 3)'
                     when m.estado = 'aguardando_dono' and m.aprovacao = 'pedida'
                       then 'espera você'
                     when m.estado in ('registrada', 'aguardando_dono') and m.aprovacao = 'aprovada'
                       then format('você aprovou (para não mandar: *segura cliente %s*)', so.nome)
                     when m.estado in ('registrada', 'aguardando_dono')
                       then format('sai sozinha (para não mandar: *segura cliente %s*)', so.nome)
                     when m.estado = 'enfileirada' then 'na fila do WhatsApp'
                     when m.estado = 'enviada' then 'mandada'
                     when m.estado = 'sem_resposta' then 'mandada; sem resposta'
                     when m.estado = 'respondida'
                       then 'mandada; respondeu: ' || public._agenda_cliente_efeito_texto(a.efeito)
                     when m.recusa_motivo = 'segurada' then 'você segurou: não saiu'
                     else 'não saiu: ' || case
                       when m.recusa_motivo in ('modo', 'tipo_em_teste') then 'estava em teste'
                       when m.recusa_motivo = 'opt_out' then 'ele pediu para não receber mensagens'
                       when m.recusa_motivo = 'sem_telefone' then 'sem telefone no cadastro'
                       when m.recusa_motivo = 'sem_conversa' then 'ele não escreveu para a HBR no último ano'
                       when m.recusa_motivo in ('domingo', 'feriado', 'janela', 'vencida') then 'passou da hora'
                       when m.recusa_motivo in ('teto_dia', 'teto_semana', 'teto_total')
                         then 'ele já tinha recebido as mensagens que cabem'
                       -- o motivo do mesmo tipo recente vai pelo prefixo: o nome dele leva o número de horas, que a
                       -- varredura do agenda-sem-literal não deixa no corpo
                       when m.recusa_motivo = 'intervalo' or left(m.recusa_motivo, 10) = 'mesmo_tipo'
                         then 'ele tinha acabado de receber outra'
                       when m.recusa_motivo in ('status', 'data_mudou', 'material', 'desatualizada')
                         then 'o serviço mudou antes de sair'
                       when m.recusa_motivo = 'passou_da_data' then 'a data que ele ouviu já tinha passado'
                       else 'o texto não passou na conferência' end end,
                   'texto', m.texto,
                   'em_teste', m.modo = 'sombra',
                   'espera_voce', m.modo = 'ligado' and m.estado = 'aguardando_dono' and m.aprovacao in ('pedida', 'critica')) as j
            from public.agenda_cliente_mensagens m
            left join public.agenda_cliente_respostas a on a.id = m.resposta_id
           where m.service_order_id = p_os
           order by coalesce(m.enviada_em, m.enviar_em) desc, m.id desc
           limit c_lista) y;

  -- o que espera o dono: a mesma conta do foco clientes (a mensagem que espera *manda cliente*, a decisão do aviso, a
  -- resposta que foi ao dono); a palavra só em ligado (em teste ela responde que nada sai ainda)
  v_esp := coalesce((public._agenda_ver_clientes(p_os, p_hoje) #>> '{dados,esperando}')::int, 0);
  select count(*)::int into v_ped from public.agenda_cliente_mensagens m
   where m.service_order_id = p_os and m.modo = 'ligado' and m.estado = 'aguardando_dono' and m.aprovacao = 'pedida';
  if cf.modo_cliente = 'ligado' and v_esp > 0 then
    v_esp_t := case when v_ped > 0
                    then format('%s esperando você: *manda cliente %s* manda; *segura cliente %s* segura.',
                                public._agenda_plural(v_ped, 'mensagem', 'mensagens'), so.nome, so.nome)
                    else '' end
               || case when v_esp > v_ped
                       then case when v_ped > 0 then ' ' else '' end
                            || 'Há decisão ou resposta dele esperando você: responda na conversa (*agenda clientes* mostra).'
                       else '' end;
  end if;

  return jsonb_build_object(
    'modo', cf.modo_cliente,
    'em_teste', cf.modo_cliente = 'sombra',
    'em_teste_texto', case when cf.modo_cliente = 'sombra'
                           then 'Em teste: nada sai ainda. Aqui fica o que eu teria mandado.' end,
    'nome', so.nome,
    'telefone_ok', v_tel, 'conversou', v_conv, 'opt_out', v_sem, 'contato_texto', v_contato,
    'servico', pl.servico_cliente,
    'prometido', v_prom,
    'confirmado_texto', case when so.client_confirmed_for is not null
                             then format('Ele confirmou %s.',
                                         public._dia_curto((so.client_confirmed_for at time zone 'America/Sao_Paulo')::date)) end,
    'mensagens', v_msgs,
    'mensagens_mais', greatest(v_total - jsonb_array_length(v_msgs), 0),
    'esperando_voce', jsonb_build_object('n', v_esp, 'texto', v_esp_t));
end;
$function$;

comment on function public._agenda_cliente_da_os(uuid, date) is
  'Agenda de Produção (Fase 5, P6): a chave cliente do cartão "Plano" (os_plano_da_os) — {modo, em_teste, em_teste_texto, nome, telefone_ok, conversou, opt_out (não recebe: opt-out, inativo ou bloqueado), contato_texto ("sem telefone no cadastro" | "pediu para não receber mensagens" | "não escreveu para a HBR no último ano…" | null), servico (como o serviço é dito ao cliente), prometido {tipo, de, ate, original_ate, fonte, texto "qui 05/11 (data firme, por mensagem da agenda em qui 22/10)", risco_texto (_agenda_cliente_risco: "Pode atrasar: agora a previsão é de qui 12/11 a sex 13/11.")} | null, confirmado_texto, mensagens (as 5 mais recentes desta OS: [{tipo, tipo_texto, quando_texto, estado, estado_texto, texto, em_teste, espera_voce}]), mensagens_mais, esperando_voce {n (a conta do foco clientes, _agenda_ver_clientes), texto (só em ligado: *manda cliente <nome>* / *segura cliente <nome>*)}}. Nenhum botão de mandar: a aprovação é pela palavra. A hora de agora: agenda.agora (a bancada), senão now(). Invoker e sem grant: só os_plano_da_os a chama. null sem a OS ou sem o cliente.';

-- ── 2. A função recriada (o corpo da definição mais nova; a mudança marcada "-- FASE 5:") ──────────────────
-- os_plano_da_os: corpo de 20261026100600 (a mais nova, conferida com grep em 27/10). Fora do bloco "-- FASE 5:" nenhuma
-- linha muda (o T2 confere). A casca não muda.

create or replace function public.os_plano_da_os(p_os uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  v_uid   uuid := auth.uid();
  so      record;
  p       jsonb;
  pl      public.os_planejamento%rowtype;
  v_pres  jsonb;
  v_fim   date;
  v_prec  date;
  v_folga int;
  v_dono  uuid := public._agenda_dono(null);
begin
  if p_os is null or p_hoje is null then
    raise exception 'os_plano_da_os: sem a OS ou o dia de hoje' using errcode = '22004';
  end if;
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'O plano da OS é com o administrador.' using errcode = '42501';
  end if;
  select s.id, s.service_order_number as numero, s.status, s.check_out_at, s.delivered_at into so
    from public.service_orders s where s.id = p_os;
  if not found then
    raise exception 'Não encontrei a OS.' using errcode = 'P0002';
  end if;
  p := public.os_prontidao(p_os, p_hoje);
  select * into pl from public.os_planejamento x where x.service_order_id = p_os;
  v_pres := p -> 'presenca_dono';
  v_fim  := (p #>> '{plano,fim_publicado}')::date;
  v_prec := pl.precisa_ate;
  v_folga := case when v_fim is not null and v_prec is not null then public.agenda_du_entre(v_fim, v_prec) end;

  return jsonb_build_object(
    -- FASE 5: o bloco "Cliente" do cartão (o que foi dito, a confirmação, as mensagens desta OS e o que espera você;
    -- _agenda_cliente_da_os). null sem o cliente.
    'cliente', public._agenda_cliente_da_os(p_os, p_hoje),
    -- FASE 5: fim
    'os', so.id, 'numero', so.numero, 'status', so.status, 'estado', p ->> 'estado_texto',
    'marcos', public.agenda_marcos_da_os(p_os, p_hoje),
    'pode_entregar', so.status = 'completed' and so.delivered_at is null,
    'duracao', jsonb_build_object(
      'dias', p #> '{duracao,dias}', 'fonte', p #>> '{duracao,fonte}',
      'fonte_texto', case p #>> '{duracao,fonte}' when 'dono' then 'você disse' when 'aceita' then 'você aceitou a minha estimativa'
                                                  else 'estimativa minha' end,
      'faixa', jsonb_build_object('otimista', p #> '{duracao,dias_otimista}', 'realista', p #> '{duracao,dias_realista}'),
      'faixa_texto', case when p #>> '{duracao,dias_otimista}' is not null
                          then 'faixa ' || public._agenda_faixa_dias((p #>> '{duracao,dias_otimista}')::numeric,
                                                                    (p #>> '{duracao,dias_realista}')::numeric) end,
      'texto', p #>> '{duracao,texto}'),
    'presenca_dono', jsonb_build_object(
      'valor', v_pres ->> 'presenca', 'pela_regra', coalesce(v_pres ->> 'fonte', 'regra') = 'regra',
      'texto', case v_pres ->> 'presenca' when 'abre_e_fecha' then 'Você abre e fecha'
                                          when 'sempre' then 'Você fica o tempo todo'
                                          when 'nunca' then 'Você não precisa ir'
                                          else 'Sem regra' end
               || case when coalesce(v_pres ->> 'fonte', 'regra') <> 'regra' then ' (você disse)'
                       when coalesce(v_pres ->> 'motivo', 'padrão') = 'padrão' then ' (pela regra)'
                       else ' (pela regra: ' || (v_pres ->> 'motivo') || ')' end),
    'material', jsonb_build_object(
      'estado', p #>> '{material,estado}',
      'itens', coalesce((select jsonb_agg(jsonb_build_object(
                  'descricao', i ->> 'descricao', 'nivel', i ->> 'nivel',
                  'nivel_texto', case i ->> 'nivel' when 'A' then 'na mão'
                                                    when 'B' then 'previsão do fornecedor'
                                                    when 'C' then 'previsão sua'
                                                    when 'D' then 'sem previsão firme'
                                                    else 'a comprar, sem prazo' end,
                  'situacao', i ->> 'situacao', 'previsao', i ->> 'data_texto', 'trecho', i ->> 'trecho',
                  'critico', coalesce((i ->> 'critico')::boolean, true), 'fornecedor', i ->> 'fornecedor')
                  order by o)
                  from jsonb_array_elements(coalesce(p #> '{material,itens}', '[]'::jsonb)) with ordinality t(i, o)), '[]'::jsonb)),
    'janela', jsonb_build_object(
      'bem_indisponivel', (select r ->> 'texto' from jsonb_array_elements(coalesce(p -> 'restricoes', '[]'::jsonb)) r
                            where r ->> 'tipo' = 'bem' limit 1),
      'nao_antes_de', pl.nao_antes_de, 'motivo', pl.nao_antes_motivo, 'precisa_ate', v_prec,
      'nao_antes_texto', case when pl.nao_antes_de is not null
                              then format('não antes de %s: %s', public._dia_curto(pl.nao_antes_de), pl.nao_antes_motivo) end,
      'precisa_ate_texto', case when v_prec is not null then 'o cliente precisa até ' || public._dia_curto(v_prec) end),
    'prometido_planejado', jsonb_build_object(
      'precisa_ate', v_prec, 'fim_publicado', v_fim, 'folga_du', v_folga,
      'texto', case
        when v_fim is not null and v_prec is not null and v_folga = 0
          then format('O plano termina %s, o dia em que o cliente precisa.', public._dia_curto(v_fim))
        when v_fim is not null and v_prec is not null and v_folga > 0
          then format('O plano termina %s; o cliente precisa até %s (%s de folga).', public._dia_curto(v_fim),
                      public._dia_curto(v_prec), public._agenda_plural(v_folga, 'dia útil', 'dias úteis'))
        when v_fim is not null and v_prec is not null
          then format('O plano termina %s, %s depois do que o cliente precisa (%s).', public._dia_curto(v_fim),
                      public._agenda_plural(-v_folga, 'dia útil', 'dias úteis'), public._dia_curto(v_prec))
        when v_fim is not null then format('O plano termina %s; o cliente não deu data.', public._dia_curto(v_fim))
        when v_prec is not null then format('O cliente precisa até %s; ainda não há plano.', public._dia_curto(v_prec))
        end),
    'planejado_realizado', coalesce((
      select jsonb_agg(jsonb_build_object(
               'dia', d.dia, 'rotulo', public._agenda_maiuscula(public._dia_curto(d.dia)),
               'pessoas_texto', nullif(public._agenda_pessoas_do_dia(d.pessoas), ''),
               'dia_texto', case when coalesce(d.dias_total, 1) > 1 and d.dia_n is not null
                                 then format('dia %s de %s', d.dia_n, d.dias_total) end,
               'meios', r.meios, 'resultado', r.resultado,
               'resultado_texto', case r.resultado when 'cumprido' then 'feito' when 'parcial' then 'feito em parte'
                                                   when 'sem_registro' then 'sem registro'
                                                   when 'nao_cumprido' then 'não aconteceu'
                                                   else case when d.dia < p_hoje then 'sem conferência' else 'previsto' end end,
               'motivo_texto', public._agenda_motivo_texto(r.motivo),
               'diaria', case when r.diaristas = 0 then null
                              when r.diaristas = r.com_diaria then 'lançada'
                              when d.dia <= p_hoje then 'a confirmar' end)
             order by d.dia)
        from public.v_agenda_dia d
        cross join lateral (
          select count(distinct (a.payee_id, a.turno)) filter (where a.presenca = 'turno')::int as meios,
                 case when bool_and(a.resultado is null) then null
                      when bool_or(a.resultado = 'cumprido') then 'cumprido'
                      when bool_or(a.resultado = 'parcial') then 'parcial'
                      when bool_or(a.resultado = 'sem_registro') then 'sem_registro'
                      else 'nao_cumprido' end as resultado,
                 min(a.motivo) filter (where a.resultado in ('parcial', 'nao_cumprido')) as motivo,
                 count(distinct a.payee_id) filter (where a.payee_id is distinct from v_dono)::int as diaristas,
                 count(distinct a.payee_id) filter (
                   where a.payee_id is distinct from v_dono
                     and (a.work_shift_id is not null
                          or exists (select 1 from public.work_shifts w join public.work_profiles wp on wp.id = w.work_profile_id
                                      where wp.payee_id = a.payee_id and w.data = a.dia and w.tipo = 'diaria'
                                        and coalesce(w.fracao, 0) > 0)))::int as com_diaria
            from public.agenda_alocacoes a
           where a.service_order_id = p_os and a.dia = d.dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva') r
       where d.service_order_id = p_os and not d.reserva), '[]'::jsonb),
    'intervencoes', coalesce((
      select jsonb_agg(jsonb_build_object('dia', i.dia,
               'texto', format('%s: você %s (no plano: %s)', public._agenda_maiuscula(public._dia_curto(i.dia)),
                               case i.dita when 'manha' then 'foi de manhã' when 'tarde' then 'foi à tarde'
                                           when 'dia' then 'ficou o dia todo' else 'passou lá' end,
                               case i.prevista when 'nenhuma' then 'nada' when 'abertura' then 'abrir'
                                               when 'fechamento' then 'fechar' when 'abre_e_fecha' then 'abrir e fechar'
                                               else 'o turno' end))
             order by i.dia, i.criado_em)
        from public.agenda_intervencoes_do_dono i where i.service_order_id = p_os), '[]'::jsonb));
end;
$function$;

comment on function public.os_plano_da_os(uuid, date) is
  'Agenda de Produção (Fase 3, P7a; Fase 5, P6): o cartão "Plano" da OS — {cliente (Fase 5: _agenda_cliente_da_os — o contato, o que foi dito ao cliente e se ainda vale, a confirmação, as 5 mensagens mais recentes desta OS e o que espera o dono; null sem o cliente), os, numero, status, estado, marcos (agenda_marcos_da_os), pode_entregar (concluída sem entrega), duracao {dias, fonte dono|aceita|sugerida, fonte_texto, faixa {otimista, realista}, faixa_texto, texto}, presenca_dono {valor, pela_regra, texto "Você abre e fecha (pela regra)"}, material {estado, itens:[{descricao, nivel A–E, nivel_texto, situacao, previsao, trecho, critico, fornecedor}]}, janela {bem_indisponivel, nao_antes_de, motivo, precisa_ate, nao_antes_texto, precisa_ate_texto}, prometido_planejado {precisa_ate, fim_publicado, folga_du, texto}, planejado_realizado:[{dia, rotulo, pessoas_texto, dia_texto, meios, resultado, resultado_texto, motivo_texto, diaria ("lançada" | "a confirmar" | null — nunca o valor)}], intervencoes:[{dia, texto}]}. Administrador e financeiro (com login) ou service_role; senão 42501.';

-- ── 3. Portas ───────────────────────────────────────────────────────────────────────────────────────────
-- A chave cliente: invoker e sem grant a ninguém (nem service_role): só os_plano_da_os (definer) a chama por dentro.
revoke all on function public._agenda_cliente_da_os(uuid, date) from public, anon, authenticated, service_role;

-- A recriada mantém a porta dela (create or replace não muda a ACL; repetida aqui para a migration se bastar).
revoke all on function public.os_plano_da_os(uuid, date) from public, anon;
grant execute on function public.os_plano_da_os(uuid, date) to authenticated, service_role;
