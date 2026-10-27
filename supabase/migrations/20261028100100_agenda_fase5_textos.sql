-- Agenda de Produção, Fase 5 ("Mensagens ao cliente"), pacote P1: os textos — o contexto de uma OS para a mensagem ao
-- cliente, os dez modelos (M1–M10) escritos pelo banco, o que a mensagem ao cliente nunca leva e a gravação do que foi DITO
-- ao cliente (prometido_*).
-- Spec: scratchpad agenda-pesquisa/spec-fase5.md (§3.1, §5.1, §6.1). Depende de 20261028100000 (as colunas e as tabelas).
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (11 funções novas; nenhuma tabela, nenhum dado)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- POR QUE: o gestor fala com o cliente SÓ por modelo. O texto e as datas saem daqui, com os dados do banco (o nome, o bem, o
-- serviço como o cliente o conhece, o dia, o turno, a faixa, o local); o LLM não escreve nem calcula data para o cliente.
-- Estas funções são o contrato dos pacotes seguintes: o envio (P2) registra e revalida com _agenda_cliente_texto, a rodada
-- (P3) passa os dados que calculou, o foco e a tela (P5, P6) mostram o que foi dito.
--
-- O QUE MUDA (só funções novas; nada as chama até as próximas migrations):
--   1. _agenda_cliente_dia ("terça (03/11)"), _agenda_cliente_dia_relativo ("Amanhã", "Na terça (03/11)", "No sábado
--      (31/10)"), _agenda_cliente_faixa ("para terça (03/11)" / "entre quarta (04/11) e sexta (06/11)") e
--      _agenda_cliente_janela ("pela manhã", "à tarde", "o dia todo", pelas alocações vigentes do dia).
--   2. _agenda_cliente_telefone: 55 + DDD + número (o WhatsApp, senão o telefone); null quando os 8 últimos dígitos são do
--      dono, da equipe ou de quem recebe diária (NOVO-agenda-42; o mesmo critério do fornecedor, sem o "cliente com OS").
--   3. _agenda_cliente_contexto(os, hoje): o nome, o bem (com artigo e gênero), o serviço como o cliente o conhece, o
--      local, se o acesso é conhecido, o plano (próximo dia, fim, turno, dias), o nível do material, se é a 1ª mensagem da
--      agenda a ele, quem assina e o que já foi prometido.
--   4. _agenda_cliente_texto(tipo, variante, os, dados, hoje): os 18 textos da §6.1, byte a byte. Assinatura ("Olá, Nelson!
--      Aqui é o Gustavo, da HBR Marine Solutions.") só na 1ª mensagem. Lança 22023 quando falta um dado do modelo; nunca
--      devolve texto pela metade.
--   5. _agenda_cliente_texto_proibido(texto): o que a mensagem ao cliente nunca leva (valor, pagamento, desconto, número de
--      OS ou orçamento, link, mais de 1 emoji, mais de 400 caracteres).
--   6. _agenda_cliente_gravar_prometido, _agenda_cliente_prometer (a mensagem enviada) e
--      _agenda_cliente_prometer_confirmacao (o botão antigo): gravam os_planejamento.prometido_* (a 1ª promessa fica em
--      prometido_original_ate; o histórico guarda antes e depois, 20 no máximo).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase5_textos.sql e anotadas em notas-fase5.md):
--   · {faixa} depois de "para": a spec põe "deve ficar para {faixa}" com {faixa} = "entre quarta (04/11) e sexta (06/11)".
--     "Ficar para entre…" não se diz: o "para" é parte da faixa — "deve ficar para quarta (04/11)" (um dia) ou "deve ficar
--     entre quarta (04/11) e sexta (06/11)" (faixa). O mesmo em "agora está prevista …" e "que estava …".
--   · {dia} = "terça (03/11)" (o dia por extenso, como a spec descreve); _agenda_faixa_texto ("qua 04 a sex 06/11") é a forma
--     curta do dono e não vai ao cliente.
--   · "{n} dia(s)": "1 dia", "2 dias" (nunca "1 dias").
--   · O gênero do serviço e do bem: "a instalação do compressor está concluída", "da instalação", "na sua lancha", "do seu
--     motorhome", "o Brisa"; os tipos femininos de bem estão na lista de _agenda_cliente_contexto.
--   · Assinatura fora do M1: a mensagem que começa por "{nome}, …" vira "Olá, {nome}! Aqui é o … . <Resto com
--     maiúscula>"; a que começa por "Bom dia, {nome}!" ganha a assinatura logo depois; "Boa notícia, {nome}: …" vira "Olá,
--     {nome}! Aqui é o … . Boa notícia: …". O M1 tem as variantes primeira e seguinte (a da spec) e escolhe sozinho quando
--     a variante vem nula.
--   · O nome do bem que COMEÇA pelo tipo ("Lancha Azimut 42") conta como o tipo ("sua lancha"), como o nome igual ao tipo.
--   · {local}: a marina (", na Marina de Itajaí"; o nome que não começa por "marina" ganha a palavra: ", na marina Kalmar
--     Estaleiro") e a vaga (", vaga 12" quando é só número); sem marina, a cidade do cliente (", em Itajaí").
--
-- O QUE NÃO MUDA: nenhum comportamento. Nada chama estas funções antes de 20261028100200 (o envio).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase5_textos.sql (begin/rollback; os 18 textos byte a byte com a
-- fixture, a assinatura, o serviço padrão pelo tipo do bem, o proibido, o dado que falta, o prometido). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261028100100
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261028100100_agenda_fase5_textos.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261028100100', 'agenda_fase5_textos');"
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.

-- ── 1. O dia, a faixa e a janela, como o cliente lê ─────────────────────────────────────────────────────

-- "terça (03/11)". Sem to_char (que depende do locale): o dia da semana por extenso, minúsculo, e dd/mm.
create or replace function public._agenda_cliente_dia(p_dia date)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case when p_dia is null then null else
    (array['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'])[extract(isodow from p_dia)::int]
    || ' (' || lpad(extract(day from p_dia)::int::text, 2, '0') || '/' || lpad(extract(month from p_dia)::int::text, 2, '0')
    || ')' end;
$function$;

comment on function public._agenda_cliente_dia(date) is
  'Agenda de Produção (Fase 5): o dia como o cliente lê — "terça (03/11)", "sábado (31/10)". null = null.';

-- O dia contado de quando a mensagem sai: "Hoje", "Amanhã", "Na terça (03/11)", "No sábado (31/10)" (começa a frase).
create or replace function public._agenda_cliente_dia_relativo(p_dia date, p_envio date)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case when p_dia is null then null
              when p_dia = p_envio then 'Hoje'
              when p_dia = p_envio + 1 then 'Amanhã'
              when extract(isodow from p_dia) in (6, 7) then 'No ' || public._agenda_cliente_dia(p_dia)
              else 'Na ' || public._agenda_cliente_dia(p_dia) end;
$function$;

comment on function public._agenda_cliente_dia_relativo(date, date) is
  'Agenda de Produção (Fase 5): o dia de que a mensagem fala, contado do dia em que ela SAI (p_envio) — "Hoje", "Amanhã", "Na terça (03/11)", "No sábado (31/10)". Começa a frase (maiúscula).';

-- A faixa: um dia só = "terça (03/11)" (com p_para: "para terça (03/11)"); dois = "entre quarta (04/11) e sexta (06/11)"
-- (o "para" não entra: "deve ficar entre …"). A ordem das pontas não importa; uma ponta nula = o dia da outra.
create or replace function public._agenda_cliente_faixa(p_de date, p_ate date, p_para boolean default false)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case when coalesce(p_de, p_ate) is null then null
              when least(coalesce(p_de, p_ate), coalesce(p_ate, p_de)) = greatest(coalesce(p_de, p_ate), coalesce(p_ate, p_de))
                then case when p_para then 'para ' else '' end || public._agenda_cliente_dia(coalesce(p_de, p_ate))
              else 'entre ' || public._agenda_cliente_dia(least(p_de, p_ate)) || ' e '
                   || public._agenda_cliente_dia(greatest(p_de, p_ate)) end;
$function$;

comment on function public._agenda_cliente_faixa(date, date, boolean) is
  'Agenda de Produção (Fase 5): a faixa como o cliente lê — um dia: "terça (03/11)" (p_para: "para terça (03/11)"); dois: "entre quarta (04/11) e sexta (06/11)" (sem o "para": "deve ficar entre …"). null quando as duas pontas são nulas.';

-- O turno do dia na OS, pelas alocações vigentes (publicada ou fixada, sem reserva): "pela manhã", "à tarde", "o dia todo";
-- null sem alocação no dia.
create or replace function public._agenda_cliente_janela(p_os uuid, p_dia date)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case when bool_or(a.turno = 'manha') and bool_or(a.turno = 'tarde') then 'o dia todo'
              when bool_or(a.turno = 'manha') then 'pela manhã'
              when bool_or(a.turno = 'tarde') then 'à tarde' end
    from public.agenda_alocacoes a
   where a.service_order_id = p_os and a.dia = p_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva';
$function$;

comment on function public._agenda_cliente_janela(uuid, date) is
  'Agenda de Produção (Fase 5): a parte do dia em que a equipe vai, como o cliente lê — "pela manhã", "à tarde" ou "o dia todo" —, pelas alocações vigentes (publicada/fixada, sem reserva) da OS no dia. null sem alocação.';

-- ── 2. O telefone do cliente ────────────────────────────────────────────────────────────────────────────

-- 55 + DDD + número, do WhatsApp, senão do telefone (10–11 dígitos ganham o 55; 12–13 têm de começar por 55). Nunca o
-- número do dono, da equipe ou de quem recebe diária (os 8 últimos dígitos de app_users e payees): esses = null
-- (NOVO-agenda-42). O cliente com OS NÃO sai (ao contrário do fornecedor): é ele o destino.
create or replace function public._agenda_cliente_telefone(p_cliente uuid)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case when length(x.d) in (10, 11) then '55' || x.d
              when length(x.d) in (12, 13) and x.d like '55%' then x.d end
    from (select regexp_replace(coalesce(nullif(btrim(cl.whatsapp), ''), cl.phone, ''), '\D', '', 'g') as d
            from public.clients cl where cl.id = p_cliente) x
   where public._agenda_chave_telefone(x.d) is not null
     and not exists (
       select 1 from (
         select public._agenda_chave_telefone(u.phone_normalized) as k from public.app_users u
         union select public._agenda_chave_telefone(u.phone) from public.app_users u
         union select public._agenda_chave_telefone(p.phone) from public.payees p
       ) i where i.k = public._agenda_chave_telefone(x.d));
$function$;

comment on function public._agenda_cliente_telefone(uuid) is
  'Agenda de Produção (Fase 5): o telefone do cliente para a mensagem — 55 + DDD + número, de clients.whatsapp, senão clients.phone (10–11 dígitos ganham o 55; 12–13 têm de começar por 55); null sem telefone válido ou quando os 8 últimos dígitos são do dono, da equipe ou de quem recebe diária (app_users.phone/phone_normalized, payees.phone: NOVO-agenda-42).';

-- ── 3. O contexto de uma OS para a mensagem ─────────────────────────────────────────────────────────────

create or replace function public._agenda_cliente_contexto(p_os uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  so       record;
  p        public.os_planejamento%rowtype;
  v_plano  jsonb;
  v_pront  jsonb;
  v_tipo   text;
  v_fem    boolean;
  v_nome_b text;
  v_proprio boolean;
  v_bem    text;
  v_o_bem  text;
  v_no_bem text;
  v_do_bem text;
  v_serv   text;
  v_art    text;
  v_do_serv text;
  v_marina text;
  v_vaga   text;
  v_cidade text;
  v_local  text := '';
  v_dia    date;
  v_turno  text;
  v_dono   text;
  v_emp    text;
begin
  select o.id, o.client_id, o.status, o.site_access, o.delivered_at, o.check_out_at,
         cl.name as cli_nome, cl.display_name, cl.city as cli_cidade, cl.opt_out_whatsapp, cl.active as cli_ativo,
         v.name as bem_nome, v.asset_type, v.current_dock_position, v.access_notes as bem_acesso,
         m.name as marina_nome, m.access_notes as marina_acesso
    into so
    from public.service_orders o
    join public.clients cl on cl.id = o.client_id
    left join public.vessels v on v.id = o.vessel_id
    left join public.marinas m on m.id = coalesce(o.marina_id, v.marina_id)
   where o.id = p_os;
  if not found then
    raise exception using errcode = '22023', message = 'OS não encontrada para a mensagem ao cliente.';
  end if;
  select * into p from public.os_planejamento where service_order_id = p_os;

  -- O bem: o tipo (minúsculo; sem tipo e com nome de uma palavra, o nome é o tipo; sem os dois, "barco") e o gênero.
  v_nome_b := nullif(btrim(coalesce(so.bem_nome, '')), '');
  v_tipo := lower(coalesce(nullif(btrim(coalesce(so.asset_type, '')), ''),
                           case when v_nome_b !~ '\s' then v_nome_b end, 'barco'));
  v_fem := public._agenda_normal(v_tipo) in ('lancha', 'escuna', 'embarcacao', 'van', 'moto', 'motocicleta', 'caminhonete',
                                             'kombi', 'traineira', 'canoa', 'balsa', 'prancha');
  -- O nome próprio vale ("o Brisa") quando existe e não é o tipo nem começa por ele ("Lancha Azimut 42" = sua lancha).
  v_proprio := v_nome_b is not null
               and public._agenda_normal(v_nome_b) <> public._agenda_normal(v_tipo)
               and public._agenda_normal(v_nome_b) not like public._agenda_normal(v_tipo) || ' %';
  if v_proprio then
    v_bem := 'o ' || v_nome_b; v_o_bem := v_bem; v_no_bem := 'no ' || v_nome_b; v_do_bem := 'do ' || v_nome_b;
  elsif v_fem then
    v_bem := 'sua ' || v_tipo; v_o_bem := 'a sua ' || v_tipo; v_no_bem := 'na sua ' || v_tipo; v_do_bem := 'da sua ' || v_tipo;
  else
    v_bem := 'seu ' || v_tipo; v_o_bem := 'o seu ' || v_tipo; v_no_bem := 'no seu ' || v_tipo; v_do_bem := 'do seu ' || v_tipo;
  end if;

  -- O serviço como o cliente o conhece; o artigo do começo (minúsculo) dá a contração ("da instalação", "do serviço").
  v_serv := coalesce(nullif(btrim(coalesce(p.servico_cliente, '')), ''), 'o serviço ' || v_no_bem);
  v_art := lower((regexp_match(v_serv, '^(\S+)\s'))[1]);
  if v_art in ('o', 'a', 'os', 'as') then
    v_serv := v_art || substr(v_serv, length(v_art) + 1);
    v_do_serv := case v_art when 'o' then 'do' when 'a' then 'da' when 'os' then 'dos' else 'das' end
                 || substr(v_serv, length(v_art) + 1);
  else
    v_art := null;
    v_do_serv := 'de ' || v_serv;
  end if;

  -- O local: a marina (da OS, senão do bem) e a vaga; sem marina, a cidade do cliente (a que veio quebrada fica de fora).
  v_marina := nullif(btrim(coalesce(so.marina_nome, '')), '');
  v_vaga := nullif(btrim(coalesce(so.current_dock_position, '')), '');
  if v_marina is not null then
    v_local := ', na ' || case when public._agenda_normal(v_marina) like 'marina%' then v_marina else 'marina ' || v_marina end;
  else
    v_cidade := nullif(btrim(coalesce(so.cli_cidade, '')), '');
    if v_cidade is not null and position(chr(65533) in v_cidade) = 0 then
      v_local := ', em ' || case when v_cidade = upper(v_cidade) or v_cidade = lower(v_cidade) then initcap(v_cidade)
                                 else v_cidade end;
    end if;
  end if;
  if v_vaga is not null then
    v_local := v_local || case when v_vaga ~ '^\d+$' then ', vaga ' || v_vaga else ', ' || v_vaga end;
  end if;

  -- O plano vigente (a Fase 5 lê o plano, não o espelho scheduled_*): o próximo dia, o fim, o turno do 1º meio-dia.
  v_plano := public._agenda_plano_da_os(p_os, p_hoje);
  v_dia := (v_plano ->> 'proximo_dia')::date;
  select min(a.turno) into v_turno
    from public.agenda_alocacoes a
   where a.service_order_id = p_os and a.dia = v_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva';
  v_pront := public.os_prontidao(p_os, p_hoje);

  v_dono := (select public._agenda_nome_curto(py.name) from public.payees py where py.id = public._agenda_dono(null));
  v_emp := coalesce((select nullif(btrim(s.value), '') from public.app_settings s where s.key = 'company_name'), 'HBR Marine');

  return jsonb_build_object(
    'os', p_os, 'cliente_id', so.client_id, 'status', so.status,
    'nome', public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(so.display_name, '')), ''), so.cli_nome)),
    'telefone_ok', public._agenda_cliente_telefone(so.client_id) is not null,
    'opt_out', so.opt_out_whatsapp or not so.cli_ativo,
    'bem', v_bem, 'o_bem', v_o_bem, 'no_bem', v_no_bem, 'do_bem', v_do_bem, 'bem_feminino', v_fem and not v_proprio,
    'servico', v_serv, 'servico_artigo', v_art, 'do_servico', v_do_serv,
    'local', v_local,
    'acesso_conhecido',
      nullif(btrim(coalesce(so.site_access, '')), '') is not null
      or nullif(btrim(coalesce(so.bem_acesso, '')), '') is not null
      or nullif(btrim(coalesce(so.marina_acesso, '')), '') is not null
      or (p.acesso_ok_em is not null
          and (p.acesso_ok_em at time zone 'America/Sao_Paulo')::date > p_hoje - c.cliente_acesso_validade_dias),
    'plano', v_plano,
    'dia', v_dia,
    'fim', (v_plano ->> 'ultimo_dia')::date,
    'turno', v_turno,
    'janela_texto', public._agenda_cliente_janela(p_os, v_dia),
    'n_dias', (v_plano ->> 'dias')::int,
    'nivel_material', v_pront #>> '{material,confianca}',
    'material_estado', v_pront #>> '{material,estado}',
    -- A 1ª mensagem da agenda a este cliente: nenhuma enviada no último ano (a assinatura).
    'primeira', not exists (select 1 from public.agenda_cliente_mensagens x
                             where x.client_id = so.client_id and x.enviada_em is not null
                               and (x.enviada_em at time zone 'America/Sao_Paulo')::date > p_hoje - 365),
    'dono', v_dono, 'empresa', v_emp,
    'prometido', case when p.prometido_tipo is not null then jsonb_build_object(
      'tipo', p.prometido_tipo, 'de', p.prometido_de, 'ate', p.prometido_ate, 'original_ate', p.prometido_original_ate,
      'fonte', p.prometido_fonte, 'em', p.prometido_em) end);
end;
$function$;

comment on function public._agenda_cliente_contexto(uuid, date) is
  'Agenda de Produção (Fase 5): o que a mensagem ao cliente de uma OS precisa, em p_hoje — nome (1º nome de display_name, senão de name), telefone_ok, opt_out (ou cliente inativo), o bem com artigo e gênero (bem "seu motorhome"/"sua lancha"/"o Brisa", o_bem, no_bem, do_bem), servico (os_planejamento.servico_cliente, senão "o serviço no seu motorhome"), do_servico, local (", na Marina de Itajaí, vaga 12" / ", em Itajaí" / vazio), acesso_conhecido (site_access, vessels.access_notes, marinas.access_notes ou acesso_ok_em em cliente_acesso_validade_dias), o plano (_agenda_plano_da_os), dia (proximo_dia), fim (ultimo_dia), turno e janela_texto do 1º meio-dia, n_dias, nivel_material (o pior nível dos críticos, de os_prontidao) e material_estado, primeira (nenhuma mensagem da agenda enviada a ele no último ano), dono e empresa (a assinatura) e o prometido. Lança 22023 sem a OS.';

-- ── 4. Os textos (spec §6.1; o teste fixa cada um byte a byte) ──────────────────────────────────────────

-- p_dados (o que o passo calculou; o que faltar sai do contexto quando dá):
--   envio (date, o dia em que a mensagem SAI: "Amanhã" é contado dele; padrão p_hoje), primeira (boolean; padrão o do
--   contexto), dia, fim (date), janela ('manha' | 'tarde' | 'dia'; padrão: as alocações do dia), n (dias de trabalho),
--   n_feitos, quando ('hoje' | 'amanhã' no M10; 'hoje' | 'ontem' no M5 primeiro_dia), faixa_de/faixa_ate (a faixa nova),
--   peca_de/peca_ate (a previsão da peça, M6 peca), dito_de/dito_ate ou dia_dito (o que o cliente ouviu; padrão o prometido).
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
                                      'nova_data', 'pronto', 'pronto_lembrete', 'pos_servico', 'mudanca_no_dia') then
    raise exception using errcode = '22023', message = format('Tipo de mensagem ao cliente desconhecido: %s.', p_tipo);
  end if;
  if p_tipo = 'confirmar' then
    v_var := coalesce(v_var, case when v_prim then 'primeira' else 'seguinte' end);
  end if;
  if (p_tipo = 'confirmar' and v_var not in ('primeira', 'seguinte', 'unico'))
     or (p_tipo = 'pode_atrasar' and coalesce(v_var, '') not in ('peca', 'execucao', 'remarcado'))
     or (p_tipo = 'andamento' and coalesce(v_var, '') not in ('primeiro_dia', 'semanal'))
     or (p_tipo = 'mudanca_no_dia' and coalesce(v_var, '') not in ('clima', 'equipe', 'geral'))
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
  'Agenda de Produção (Fase 5): a mensagem-modelo ao cliente (spec §6.1), pronta, com os dados do banco — tipos confirmar (M1: primeira, seguinte, unico; nula = primeira ou seguinte pelo contexto), vespera (M2), acesso (M4), material_chegou (M3), pode_atrasar (M6: peca, execucao, remarcado), nova_data (M7), andamento (M5: primeiro_dia, semanal), pronto e pronto_lembrete (M8), pos_servico (M9) e mudanca_no_dia (M10: clima, equipe, geral). p_dados = o que o passo calculou (envio, primeira, dia, fim, janela, n, n_feitos, quando, faixa_de/ate, peca_de/ate, dito_de/ate ou dia_dito); o que faltar sai do contexto (_agenda_cliente_contexto). Assinatura só na 1ª mensagem. Lança 22023 com o tipo ou a variante que não existe e quando falta um dado; nunca devolve texto pela metade.';

-- ── 5. O que a mensagem ao cliente nunca leva ───────────────────────────────────────────────────────────

-- null = nada; senão o motivo: 'valor' (R$, "valor"), 'pagamento' (pag…, boleto, pix, cobrança), 'desconto', 'os' (OS-,
-- ORÇ-/ORC-, 5 dígitos seguidos: o número de OS), 'link' (http, www.), 'emoji' (mais de 1) ou 'tamanho' (mais de 400).
create or replace function public._agenda_cliente_texto_proibido(p_texto text)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v text := lower(coalesce(p_texto, ''));
begin
  if v ~ 'r\$' or v ~ '\mvalor' then
    return 'valor';
  end if;
  if v ~ '\mpag' or v ~ 'boleto' or v ~ 'pix' or v ~ 'cobran' then
    return 'pagamento';
  end if;
  if v ~ 'desconto' then
    return 'desconto';
  end if;
  if coalesce(p_texto, '') ~* '\m(os|or[cç]|OR[CÇ])-' or v ~ '\d{5}' then
    return 'os';
  end if;
  if v ~ '(http|www\.)' then
    return 'link';
  end if;
  if (select count(*) from regexp_matches(coalesce(p_texto, ''), '[\U0001F000-\U0001FAFF☀-➿]', 'g')) > 1 then
    return 'emoji';
  end if;
  if char_length(coalesce(p_texto, '')) > 400 then
    return 'tamanho';
  end if;
  return null;
end;
$function$;

comment on function public._agenda_cliente_texto_proibido(text) is
  'Agenda de Produção (Fase 5): o que a mensagem ao cliente nunca leva — null = nada; ''valor'' (R$, valor), ''pagamento'' (pag…, boleto, pix, cobrança), ''desconto'', ''os'' (OS-, ORÇ-/ORC-, 5 dígitos seguidos), ''link'' (http, www.), ''emoji'' (mais de 1) ou ''tamanho'' (mais de 400 caracteres). O registro recusa (22023); a saúde conta (com_texto_proibido = 0).';

-- ── 6. O que foi DITO ao cliente ────────────────────────────────────────────────────────────────────────

-- Grava os_planejamento.prometido_* (cria a linha da OS só com isso quando não existe). A 1ª promessa fica em
-- prometido_original_ate (depois não muda); o histórico ganha {em, autor, trecho, antes, depois} e corta nos 20 mais
-- novos. Interna: sem grant (o envio, o botão antigo e o *grava* do dono a chamam por dentro).
create or replace function public._agenda_cliente_gravar_prometido(p_os uuid, p_tipo text, p_de date, p_ate date,
                                                                   p_fonte text, p_mensagem uuid, p_agora timestamptz,
                                                                   p_trecho text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  p        public.os_planejamento%rowtype;
  v_de     date := least(coalesce(p_de, p_ate), coalesce(p_ate, p_de));
  v_ate    date := greatest(coalesce(p_de, p_ate), coalesce(p_ate, p_de));
  v_antes  jsonb;
  v_depois jsonb;
begin
  if p_tipo not in ('condicional', 'faixa', 'firme') or v_ate is null then
    raise exception using errcode = '22023', message = 'O que foi dito ao cliente precisa do tipo e do dia.';
  end if;
  insert into public.os_planejamento (service_order_id) values (p_os) on conflict (service_order_id) do nothing;
  select * into p from public.os_planejamento where service_order_id = p_os for update;
  v_antes := jsonb_build_object('prometido_tipo', p.prometido_tipo, 'prometido_de', p.prometido_de,
                                'prometido_ate', p.prometido_ate, 'prometido_fonte', p.prometido_fonte);
  v_depois := jsonb_build_object('prometido_tipo', p_tipo, 'prometido_de', v_de, 'prometido_ate', v_ate,
                                 'prometido_fonte', p_fonte);
  update public.os_planejamento
     set prometido_tipo = p_tipo, prometido_de = v_de, prometido_ate = v_ate,
         prometido_original_ate = coalesce(p.prometido_original_ate, v_ate),
         prometido_em = p_agora, prometido_fonte = p_fonte, prometido_mensagem_id = p_mensagem,
         historico = public._os_material_historico(p.historico, jsonb_build_object(
           'em', (p_agora at time zone 'America/Sao_Paulo')::date, 'autor', null,
           'trecho', public._agenda_corta(p_trecho, 500), 'antes', v_antes, 'depois', v_depois)),
         atualizado_em = p_agora
   where service_order_id = p_os;
  return jsonb_build_object('gravou', true, 'os', p_os, 'tipo', p_tipo, 'de', v_de, 'ate', v_ate,
                            'original_ate', coalesce(p.prometido_original_ate, v_ate),
                            'primeira_promessa', p.prometido_original_ate is null);
end;
$function$;

comment on function public._agenda_cliente_gravar_prometido(uuid, text, date, date, text, uuid, timestamptz, text) is
  'Agenda de Produção (Fase 5): grava o que foi dito ao cliente em os_planejamento (prometido_tipo/de/ate/em/fonte/mensagem_id), criando a linha da OS só com isso quando não existe. prometido_original_ate = o prometido_ate da 1ª vez (depois não muda). O histórico ganha {em, autor, trecho, antes, depois} (20 no máximo). Interna (sem grant): a chamam o envio (_agenda_cliente_prometer), o botão antigo (_agenda_cliente_prometer_confirmacao) e o *grava* do dono (P5).';

-- A mensagem enviada que diz data vira o prometido: firme = do dia ao fim (base.fim, senão a faixa, senão o dia); faixa e
-- condicional = a faixa. A mensagem sem data (prometido_tipo nulo) não grava nada.
create or replace function public._agenda_cliente_prometer(p_msg uuid, p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  m     public.agenda_cliente_mensagens%rowtype;
  v_de  date;
  v_ate date;
begin
  select * into m from public.agenda_cliente_mensagens where id = p_msg;
  if not found then
    return jsonb_build_object('gravou', false, 'motivo', 'sem_mensagem');
  end if;
  if m.prometido_tipo is null then
    return jsonb_build_object('gravou', false, 'motivo', 'sem_data');
  end if;
  if m.prometido_tipo = 'firme' then
    v_de := coalesce(m.dia_alvo, m.faixa_de);
    v_ate := coalesce((m.base ->> 'fim')::date, m.faixa_ate, v_de);
  else
    v_de := coalesce(m.faixa_de, m.dia_alvo);
    v_ate := coalesce(m.faixa_ate, v_de);
  end if;
  return public._agenda_cliente_gravar_prometido(m.service_order_id, m.prometido_tipo, v_de, v_ate, 'mensagem', m.id, p_agora,
                                                 format('mensagem ao cliente (%s): %s', m.modelo, m.texto));
end;
$function$;

comment on function public._agenda_cliente_prometer(uuid, timestamptz) is
  'Agenda de Produção (Fase 5): a mensagem ao cliente que saiu (o gatilho do envio, P2) vira o prometido da OS — firme: do dia_alvo ao fim (base.fim, senão faixa_ate, senão o dia); faixa e condicional: a faixa (faixa_de/faixa_ate). Sem data = {gravou: false, motivo: sem_data}. Fonte mensagem, com o id da mensagem. Interna (sem grant).';

-- O botão antigo (agenda-confirmacao, D9): o dia confirmado vira o prometido firme, do dia ao fim agendado da OS.
create or replace function public._agenda_cliente_prometer_confirmacao(p_os uuid, p_dia timestamptz, p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_de  date := (p_dia at time zone 'America/Sao_Paulo')::date;
  v_ate date;
begin
  if p_os is null or p_dia is null then
    return jsonb_build_object('gravou', false, 'motivo', 'sem_data');
  end if;
  select greatest(v_de, coalesce((so.scheduled_end_at at time zone 'America/Sao_Paulo')::date, v_de)) into v_ate
    from public.service_orders so where so.id = p_os;
  if not found then
    return jsonb_build_object('gravou', false, 'motivo', 'sem_os');
  end if;
  return public._agenda_cliente_gravar_prometido(p_os, 'firme', v_de, v_ate, 'confirmacao', null, p_agora,
                                                 'o botão de pedir a confirmação ao cliente');
end;
$function$;

comment on function public._agenda_cliente_prometer_confirmacao(uuid, timestamptz, timestamptz) is
  'Agenda de Produção (Fase 5, D9): a confirmação pedida pelo botão antigo (origem agenda-confirmacao) também é data dita — prometido firme do dia de p_dia (Brasília) até o fim agendado da OS (scheduled_end_at, nunca antes do dia), fonte confirmacao. Interna (sem grant).';

-- ── 7. Portas ───────────────────────────────────────────────────────────────────────────────────────────

-- As leituras e os textos (invoker, STABLE/IMMUTABLE): authenticated (a tela e o foco, com a RLS de quem lê) e service_role;
-- nunca anon.
revoke all on function
  public._agenda_cliente_dia(date), public._agenda_cliente_dia_relativo(date, date),
  public._agenda_cliente_faixa(date, date, boolean), public._agenda_cliente_janela(uuid, date),
  public._agenda_cliente_telefone(uuid), public._agenda_cliente_contexto(uuid, date),
  public._agenda_cliente_texto(text, text, uuid, jsonb, date), public._agenda_cliente_texto_proibido(text)
  from public, anon;
grant execute on function
  public._agenda_cliente_dia(date), public._agenda_cliente_dia_relativo(date, date),
  public._agenda_cliente_faixa(date, date, boolean), public._agenda_cliente_janela(uuid, date),
  public._agenda_cliente_telefone(uuid), public._agenda_cliente_contexto(uuid, date),
  public._agenda_cliente_texto(text, text, uuid, jsonb, date), public._agenda_cliente_texto_proibido(text)
  to authenticated, service_role;

-- O que grava o prometido: ninguém de fora (nem service_role) — só as funções security definer da agenda o chamam.
revoke all on function
  public._agenda_cliente_gravar_prometido(uuid, text, date, date, text, uuid, timestamptz, text),
  public._agenda_cliente_prometer(uuid, timestamptz),
  public._agenda_cliente_prometer_confirmacao(uuid, timestamptz, timestamptz)
  from public, anon, authenticated, service_role;
