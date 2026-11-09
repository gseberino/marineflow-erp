-- Retorno rápido ao cliente, F1 (sobe em sombra na seg 16/11/2026): o prazo que o recibo promete, a
-- calibração aprovada pelo dono, o nome do cliente e os textos fixos. Só funções: nenhuma tabela, nenhum
-- dado, nenhum envio.
--
-- 1. _retorno_prazo(quando, chave, pressa, acorde_agora): o "até X" é do BANCO (B.4.1; IA pensa, sistema
--    preenche). Quem chama passa quando = greatest(aberta_em, agora) (R1-03): a mensagem que chega num lote
--    de ressincronização com horas de atraso nunca ouve "até as 14h" às 15h. A tabela (8 regras, em ordem)
--    só promete a hora que tenha um momento do dono marcado para cumpri-la: manhã (10h), meio-dia (14h,
--    só com meio_dia_ligado, que é da F2) e fechamento (19h). Um acorde só sustenta promessa quando sai
--    junto com o recibo; nesta leva p_acorde_agora é sempre falso (o acorde real não existe).
--    Dia útil, feriado e dia em que o dono marcou indisponível vêm de agenda_dia_util e agenda_somar_du
--    (uma fonte só, a da agenda; só lidas, nunca alteradas).
--    - "fora até <dia>" (retorno_config.fora_ate, o 1º dia em que o dono volta): a promessa vai para esse
--      dia às 10h.
--    - Fora da janela K3 (22:00–06:59), o recibo espera a manhã (_retorno_proxima_manha) e promete as 10h
--      do dia útil em que sai.
--    - Duas guardas que a tabela não escreve, para nunca prometer hora que já passou: o fora_ate no próprio
--      dia da volta, depois das 10h, cai na tabela normal; e a pressa com acorde só promete as 19h antes
--      das 19h (depois, segue a tabela).
--
-- 2. Calibração (retorno_config.promessa_faixa = {"<faixa>": {"dias": 0|1, "hora": "HH:MM"}}; "dias" 0 é
--    o dia que a tabela daria, 1 o próximo dia útil depois dele). Vale só quando ALONGA a promessa da
--    tabela e cai num momento do dono (10h, 14h com o meio-dia ligado, ou 19h). Valor mal formado, fora de
--    um momento ou que encurtaria é ignorado (vale a tabela) e vai ao app_error_logs como 'warn'
--    (contexto 'retorno', ação 'promessa_faixa'; o upsert por impressão digital soma ocorrências, sem
--    linha nova a cada chamada). O valor igual ao da tabela só não muda nada (sem log). Encurtar, só com a
--    palavra do dono, numa leva futura. As faixas fora_ate e promessa_dono nunca são calibradas.
--    Por gravar esse log, _retorno_prazo é VOLATILE (função STABLE não deve escrever).
--
-- 3. _retorno_proxima_manha(agora, chave): o recibo de quem escreveu fora da janela sai às 08:00 (domingo
--    e feriado, 09:00), espalhado em 30 min de forma ESTÁVEL por número e dia (R1-11: sem rajada
--    sincronizada às 08:00 e sem mudar de minuto a cada chamada). O ::bigint antes do abs evita o estouro
--    de abs(-2147483648) (22003); o dia entra no hash por to_char, que não depende do DateStyle da sessão.
--
-- 4. _retorno_x2(prometido): o próximo momento do MESMO dia depois de X (14h com o meio-dia ligado, senão
--    19h); nulo quando X já é o último (19h). É a única fonte do "vai haver adiamento" (P4, P6).
--
-- 5. _retorno_quando, _retorno_hora e _retorno_cumprimento: as palavras que o texto usa para o dia
--    ("hoje", "amanhã", "segunda (23/11)"), para a hora ("10h", "10:30") e o cumprimento pela hora de
--    Brasília (Bom dia, Boa tarde, Boa noite).
--
-- 6. _retorno_nome(cliente): o nome curto da agenda (_agenda_nome_curto: "LENINE LORI BROCCA" → "Lenine"),
--    com o display_name na frente. Empresa sem display_name (R1-22), o "Cliente Final" (genérico, o
--    telefone de um terceiro que ninguém identificou) e cadastro que não existe: nulo, e o texto sai na
--    variante sem nome. Nunca o nome do perfil do WhatsApp.
--
-- 7. _retorno_do_bem(palavra): o complemento da pergunta do número novo ("qual o modelo e o ano da
--    lancha?"): "da" nos femininos de unidade.ts, "do" no resto, "do veículo" nos modelos (Ducato,
--    Sprinter…), com o acento de volta nas palavras que o sinal normalizou ("da embarcação").
--
-- 8. _retorno_texto(tipo, variante, dados): os modelos fixos (T01–T28, mais T07a, T08a, T10a, T12a e T13a, as
--    apresentações) e a linha de risco (L01), letra por letra os do cartão rr-voz-textos, com a voz da Claudia
--    (VOZ-1, VOZ-2, VOZ-6). O prazo sai sem hora: {quando_fala} é "ainda hoje" ou "amanhã de manhã", e a hora
--    fica por dentro (molde _agenda_cliente_texto). Falta de dado é
--    ERRO (22023), nunca texto com buraco; os campos de lista fechada são conferidos (dia, hora,
--    cumprimento, "de ontem à noite", nome sem dígito, "do/da <bem>"). Nenhum texto copia trecho do
--    cliente (R1-12) nem tem emoji. _retorno_oferece_urgente(tipo, variante): os modelos que oferecem
--    responder "urgente" (T04–T06, T20, T21); única fonte para o P4, conferida contra os textos no teste.
--
-- 9. _retorno_quando_fala(quando, hora): como o prazo é dito ao cliente (VOZ-2): "ainda hoje", "ainda esta
--    manhã", "amanhã de manhã", "na segunda, pela manhã". Nulo se não reconhece o dia ou a hora.
--
-- 10. _cliente_ja_apresentada(cliente, chave, hoje): a Claudia já falou com este cliente? (VOZ-1, VOZ-6: uma
--    vez só, seja no retorno ou na agenda.) Conta o que saiu de fato; a 'incerta' não conta, porque repetir a
--    apresentação é melhor que omitir. A janela é retorno_config.apresentacao_intervalo, que passa a 365 dias.
--
-- Auxiliares internas: revoke de public, anon e authenticated, sem grant (quem chama é SECURITY DEFINER).
-- As que leem tabela (retorno_config, clients, a agenda) são SECURITY DEFINER com search_path = public;
-- as puras só fixam o search_path.
--
-- Dado: só a linha de retorno_config, apresentacao_intervalo de 30 para 365 dias. O resto são funções novas.
-- Reverter (depois das migrations seguintes da F1, que chamam estas): drop function
-- public._retorno_texto(text, text, jsonb), public._retorno_oferece_urgente(text, text),
-- public._retorno_prazo(timestamptz, text, boolean, boolean), public._retorno_x2(timestamptz),
-- public._retorno_do_bem(text), public._retorno_nome(uuid), public._retorno_proxima_manha(timestamptz, text),
-- public._retorno_cumprimento(timestamptz), public._retorno_hora(time), public._retorno_quando(date, date),
-- public._retorno_quando_fala(text, text), public._cliente_ja_apresentada(uuid, text, date).
-- Sem deploy: update public.retorno_config set promessa_faixa = '{}' (a promessa volta à tabela) ou
-- fora_ate = null.

-- "hoje", "amanhã" ou "segunda (09/11)" (_agenda_cliente_dia), do ponto de vista de p_ref.
create or replace function public._retorno_quando(p_dia date, p_ref date)
returns text
language sql
stable
set search_path = public
as $$
  select case
    when p_dia is null or p_ref is null then null
    when p_dia = p_ref then 'hoje'
    when p_dia = p_ref + 1 then 'amanhã'
    else public._agenda_cliente_dia(p_dia)
  end;
$$;

comment on function public._retorno_quando(date, date) is
  'Retorno F1: o dia como o texto ao cliente diz, visto de p_ref: hoje, amanhã ou "segunda (09/11)" (_agenda_cliente_dia).';

-- "10h" na hora cheia; "10:30" com minutos. Os segundos não contam.
create or replace function public._retorno_hora(p time)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when p is null then null
    when extract(minute from p) = 0 then extract(hour from p)::int::text || 'h'
    else lpad(extract(hour from p)::int::text, 2, '0') || ':' || lpad(extract(minute from p)::int::text, 2, '0')
  end;
$$;

comment on function public._retorno_hora(time) is
  'Retorno F1: a hora como o texto ao cliente diz: 10h na hora cheia, 10:30 com minutos.';

-- Pela hora de Brasília: 05–11 Bom dia; 12–17 Boa tarde; o resto Boa noite.
create or replace function public._retorno_cumprimento(p_quando timestamptz)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when p_quando is null then null
    when extract(hour from p_quando at time zone 'America/Sao_Paulo') between 5 and 11 then 'Bom dia'
    when extract(hour from p_quando at time zone 'America/Sao_Paulo') between 12 and 17 then 'Boa tarde'
    else 'Boa noite'
  end;
$$;

comment on function public._retorno_cumprimento(timestamptz) is
  'Retorno F1: Bom dia (05–11), Boa tarde (12–17) ou Boa noite, pela hora de Brasília.';

-- A manhã em que sai o recibo de quem escreveu fora da janela K3: hoje, se ainda não deu manha_recibo
-- (08:00); senão amanhã. Domingo e feriado começam em manha_recibo_folga (09:00). Espalha por
-- manha_espalhar (30 min) pelo hash da chave e do dia: o mesmo número no mesmo dia cai sempre no mesmo
-- instante, e números diferentes caem em instantes diferentes.
create or replace function public._retorno_proxima_manha(p_agora timestamptz, p_chave text)
returns timestamptz
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_cfg public.retorno_config := public._retorno_cfg();
  v_local timestamp;
  v_dia date;
  v_base time;
  v_janela_s bigint;
  v_seg bigint := 0;
begin
  if p_agora is null then
    return null;
  end if;
  -- Sem a linha de configuração não há manhã a calcular: sobe, e quem chama recusa o item (falha fecha).
  if v_cfg.id is null then
    raise exception using errcode = '55000', message = 'retorno_proxima_manha: sem a linha de retorno_config';
  end if;

  v_local := p_agora at time zone c_fuso;
  v_dia := case when v_local::time < v_cfg.manha_recibo then v_local::date else v_local::date + 1 end;
  v_base := case when extract(isodow from v_dia) = 7 or public.agenda_feriado(v_dia) is not null
                 then v_cfg.manha_recibo_folga else v_cfg.manha_recibo end;

  v_janela_s := floor(extract(epoch from v_cfg.manha_espalhar))::bigint;
  if v_janela_s > 0 then
    -- ::bigint ANTES do abs: abs(-2147483648::int) estoura (22003).
    v_seg := abs(hashtext(coalesce(p_chave, '') || to_char(v_dia, 'YYYY-MM-DD'))::bigint) % v_janela_s;
  end if;

  return ((v_dia + v_base) at time zone c_fuso) + make_interval(secs => v_seg::double precision);
end;
$$;

comment on function public._retorno_proxima_manha(timestamptz, text) is
  'Retorno F1: quando sai o recibo de quem escreveu fora da janela K3: 08:00 (domingo e feriado 09:00) de hoje ou de amanhã, espalhado em manha_espalhar de forma estável por chave e dia (R1-11).';

-- O nome curto do cadastro, para o {nome} dos textos. Nulo = o texto sai na variante sem nome.
create or replace function public._retorno_nome(p_client uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when c.generico then null                                                -- "Cliente Final": um terceiro
    when c.type = 'company' and nullif(btrim(c.display_name), '') is null then null   -- R1-22
    else public._agenda_nome_curto(coalesce(nullif(btrim(c.display_name), ''), c.name))
  end
  from public.clients c
  where c.id = p_client;
$$;

comment on function public._retorno_nome(uuid) is
  'Retorno F1: _agenda_nome_curto(display_name ou name) do cliente; nulo para empresa sem display_name (R1-22), para o "Cliente Final" (genérico) e para cadastro que não existe. Nunca o nome do perfil do WhatsApp.';

-- "da lancha", "do motorhome", "do veículo": o fim da pergunta "qual o modelo e o ano …?".
-- Femininos de unidade.ts:23; modelos de veículo viram "do veículo"; sem palavra, nulo.
create or replace function public._retorno_do_bem(p_bem text)
returns text
language sql
immutable
set search_path = public
as $$
  with b as (
    select nullif(btrim(regexp_replace(
             translate(lower(coalesce(p_bem, '')), 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'áàâãäéèêëíìîïóòôõöúùûüç'),
             '\s+', ' ', 'g')), '') as palavra
  ), k as (
    select b.palavra, translate(b.palavra, 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc') as chave
      from b
  )
  select case
    when k.palavra is null then null
    when k.chave in ('ducato', 'sprinter', 'iveco', 'daily', 'master', 'boxer') then 'do veículo'
    else case when k.chave in ('lancha', 'moto aquatica', 'embarcacao', 'van', 'picape', 'escuna', 'traineira')
              then 'da ' else 'do ' end
         -- o sinal (P2) normaliza sem acento; o texto ao cliente leva o acento de volta
         || case k.chave
              when 'motor home' then 'motorhome'
              when 'catamara' then 'catamarã'
              when 'embarcacao' then 'embarcação'
              when 'moto aquatica' then 'moto aquática'
              when 'automovel' then 'automóvel'
              when 'veiculo' then 'veículo'
              when 'onibus' then 'ônibus'
              when 'caminhao' then 'caminhão'
              else k.palavra
            end
  end
  from k;
$$;

comment on function public._retorno_do_bem(text) is
  'Retorno F1: o complemento da pergunta ao número novo: "da" + feminino de unidade.ts, "do" + o resto, "do veículo" nos modelos (ducato, sprinter, iveco, daily, master, boxer); nulo sem palavra.';

-- O próximo momento de promessa do MESMO dia depois de X: o meio-dia (se ligado) ou o fechamento; nulo
-- quando X já é o último momento do dia.
create or replace function public._retorno_x2(p_prometido timestamptz)
returns timestamptz
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_cfg public.retorno_config := public._retorno_cfg();
  v_local timestamp;
begin
  if p_prometido is null then
    return null;
  end if;
  if v_cfg.id is null then
    raise exception using errcode = '55000', message = 'retorno_x2: sem a linha de retorno_config';
  end if;
  v_local := p_prometido at time zone c_fuso;
  if v_cfg.meio_dia_ligado and v_cfg.promessa_meio_dia > v_local::time then
    return (v_local::date + v_cfg.promessa_meio_dia) at time zone c_fuso;
  end if;
  if v_cfg.promessa_fechamento > v_local::time then
    return (v_local::date + v_cfg.promessa_fechamento) at time zone c_fuso;
  end if;
  return null;
end;
$$;

comment on function public._retorno_x2(timestamptz) is
  'Retorno F1: X2, o próximo momento de promessa do mesmo dia depois de X (promessa_meio_dia com o meio-dia ligado, senão promessa_fechamento); nulo depois do último. Única fonte do "vai haver adiamento".';

-- Os modelos cujo texto oferece responder "urgente" (T04–T06, T20, T21).
create or replace function public._retorno_oferece_urgente(p_tipo text, p_variante text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(
    (p_tipo = 'recibo_cliente' and p_variante in ('outro_dia', 'outro_dia_apresentacao', 'outro_dia_sem_nome'))
    or (p_tipo = 'adiamento' and p_variante in ('com_nome', 'sem_nome')),
    false);
$$;

comment on function public._retorno_oferece_urgente(text, text) is
  'Retorno F1: verdadeiro nos modelos que oferecem responder "urgente" (recibo_cliente outro_dia*, adiamento com_nome/sem_nome). Única fonte; o teste confere contra _retorno_texto.';

-- O "até X" do recibo (B.4.1). Devolve {faixa, fonte, prometido_ate, recibo_em, dia, ref, quando, hora,
-- outro_dia, x2}; "agora" = p_quando (a carência é somada por quem chama).
create or replace function public._retorno_prazo(p_quando timestamptz, p_chave text,
                                                 p_pressa boolean default false,
                                                 p_acorde_agora boolean default false)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_cfg public.retorno_config := public._retorno_cfg();
  v_local timestamp;
  v_t time;
  v_d date;
  v_na_janela boolean;
  v_recibo timestamptz;
  v_dia date;
  v_hora time;
  v_prom timestamptz;
  v_fonte text;
  v_faixa text;
  v_cal jsonb;
  v_cal_hora time;
  v_cal_dia date;
  v_cal_prom timestamptz;
  v_invalido text;
  v_igual boolean := false;
begin
  if p_quando is null then
    return null;
  end if;
  -- Sem a linha de configuração não há prazo: sobe, e quem chama recusa o item (falha fecha).
  if v_cfg.id is null then
    raise exception using errcode = '55000', message = 'retorno_prazo: sem a linha de retorno_config';
  end if;

  v_local := p_quando at time zone c_fuso;
  v_t := v_local::time;
  v_d := v_local::date;
  v_na_janela := v_t >= v_cfg.cliente_resposta_direta_inicio and v_t < v_cfg.cliente_resposta_direta_fim;

  -- 1. "fora até <dia>": a promessa vai para o 1º dia útil a partir do dia da volta, às 10h. Guarda: no
  --    próprio dia da volta, a promessa que já passou (ou que vence antes do recibo) não vale, e segue a
  --    tabela normal.
  if v_cfg.fora_ate is not null and v_cfg.fora_ate >= v_d then
    v_recibo := case when v_na_janela then p_quando else public._retorno_proxima_manha(p_quando, p_chave) end;
    v_dia := public.agenda_somar_du(v_cfg.fora_ate, 0);
    v_hora := v_cfg.promessa_manha;
    if ((v_dia + v_hora) at time zone c_fuso) > v_recibo then
      v_fonte := 'fora_ate';
      v_faixa := 'fora_ate';
    end if;
  end if;

  if v_faixa is null then
    if not v_na_janela then
      -- 2. Fora da janela K3: o recibo espera a manhã e promete as 10h do dia útil em que sai.
      v_recibo := public._retorno_proxima_manha(p_quando, p_chave);
      v_dia := public.agenda_somar_du((v_recibo at time zone c_fuso)::date, 0);
      v_hora := v_cfg.promessa_manha;
      v_fonte := 'manha';
      v_faixa := 'noite';
    elsif not public.agenda_dia_util(v_d) then
      -- 3. Sábado, domingo, feriado ou dia em que o dono marcou indisponível: o próximo dia útil às 10h.
      v_recibo := p_quando;
      v_dia := public.agenda_somar_du(v_d, 0);
      v_hora := v_cfg.promessa_manha;
      v_fonte := 'manha';
      v_faixa := 'folga';
    elsif coalesce(p_pressa, false) and coalesce(p_acorde_agora, false)
          and v_t >= time '08:00' and v_t < time '20:00'      -- a janela do acorde (aviso_registrar)
          and v_t < v_cfg.promessa_fechamento then            -- guarda: nunca "até as 19h" depois das 19h
      -- 4. Pressa, com o acorde saindo agora junto com o recibo: o fechamento de hoje.
      v_recibo := p_quando;
      v_dia := v_d;
      v_hora := v_cfg.promessa_fechamento;
      v_fonte := 'acorde';
      v_faixa := 'pressa';
    elsif v_t < v_cfg.corte_meio_dia and v_cfg.meio_dia_ligado then
      -- 5. Manhã cedo, com o meio-dia ligado: hoje às 14h.
      v_recibo := p_quando;
      v_dia := v_d;
      v_hora := v_cfg.promessa_meio_dia;
      v_fonte := 'meio_dia';
      v_faixa := 'manha_cedo';
    elsif v_t < v_cfg.corte_meio_dia then
      -- 6. Manhã cedo, meio-dia desligado: hoje às 19h.
      v_recibo := p_quando;
      v_dia := v_d;
      v_hora := v_cfg.promessa_fechamento;
      v_fonte := 'fechamento';
      v_faixa := 'manha_cedo';
    elsif v_t < v_cfg.corte_tarde then
      -- 7. Do corte do meio-dia ao corte da tarde: hoje às 19h.
      v_recibo := p_quando;
      v_dia := v_d;
      v_hora := v_cfg.promessa_fechamento;
      v_fonte := 'fechamento';
      v_faixa := 'meio';
    else
      -- 8. Do corte da tarde ao fim da janela, em dia útil: o próximo dia útil às 10h.
      v_recibo := p_quando;
      v_dia := public.agenda_somar_du(v_d + 1, 0);
      v_hora := v_cfg.promessa_manha;
      v_fonte := 'manha';
      v_faixa := 'tarde';
    end if;
  end if;

  v_prom := (v_dia + v_hora) at time zone c_fuso;

  -- Calibração aprovada: só alonga, e sempre num momento do dono.
  if v_cfg.promessa_faixa ? v_faixa then
    v_cal := v_cfg.promessa_faixa -> v_faixa;
    v_invalido := case
      when v_faixa in ('fora_ate', 'promessa_dono') then 'faixa_sem_calibracao'
      when jsonb_typeof(v_cal) is distinct from 'object' then 'formato'
      when v_cal -> 'dias' is null or v_cal -> 'dias' not in ('0'::jsonb, '1'::jsonb) then 'dias'
      when coalesce(v_cal ->> 'hora', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then 'hora'
    end;
    if v_invalido is null then
      v_cal_hora := (v_cal ->> 'hora')::time;
      if not (v_cal_hora = v_cfg.promessa_manha
              or (v_cfg.meio_dia_ligado and v_cal_hora = v_cfg.promessa_meio_dia)
              or v_cal_hora = v_cfg.promessa_fechamento) then
        v_invalido := 'nao_e_momento';
      else
        v_cal_dia := case when v_cal -> 'dias' = '0'::jsonb then v_dia else public.agenda_somar_du(v_dia, 1) end;
        v_cal_prom := (v_cal_dia + v_cal_hora) at time zone c_fuso;
        if v_cal_prom < v_prom then
          v_invalido := 'encurtaria';
        elsif v_cal_prom = v_prom then
          v_igual := true;                     -- igual à tabela: nada muda, e não é erro
        else
          v_dia := v_cal_dia;
          v_hora := v_cal_hora;
          v_prom := v_cal_prom;
          v_fonte := case v_cal_hora when v_cfg.promessa_manha then 'manha'
                                     when v_cfg.promessa_meio_dia then 'meio_dia'
                                     else 'fechamento' end;
        end if;
      end if;
    end if;
    if v_invalido is not null and not v_igual then
      perform public.log_app_error('db',
        format('calibração da promessa ignorada na faixa %s (%s)', v_faixa, v_invalido),
        'retorno', 'promessa_faixa', 'warn',
        jsonb_build_object('faixa', v_faixa, 'motivo', v_invalido, 'valor', v_cal,
                           'tabela', jsonb_build_object('dia', v_dia, 'hora', public._retorno_hora(v_hora))));
    end if;
  end if;

  return jsonb_build_object(
    'faixa', v_faixa,
    'fonte', v_fonte,
    'prometido_ate', v_prom,
    'recibo_em', v_recibo,
    'dia', v_dia,
    'ref', (v_recibo at time zone c_fuso)::date,
    'quando', public._retorno_quando(v_dia, (v_recibo at time zone c_fuso)::date),
    'hora', public._retorno_hora(v_hora),
    'outro_dia', v_dia > (v_recibo at time zone c_fuso)::date,
    'x2', public._retorno_x2(v_prom));
end;
$$;

comment on function public._retorno_prazo(timestamptz, text, boolean, boolean) is
  'Retorno F1 (B.4.1): o "até X" do recibo, pela tabela de 8 regras (fora_ate, noite, folga, pressa com acorde, manhã cedo, meio, tarde) e pela calibração aprovada (promessa_faixa: só alonga, sempre num momento; inválida é ignorada e registrada). Quem chama passa greatest(aberta_em, agora). VOLATILE por gravar o log.';

-- Como o prazo é dito ao cliente (VOZ-2): sem hora exata; a hora fica por dentro.
create or replace function public._retorno_quando_fala(p_quando text, p_hora text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when v.h is null then null
    when v.q = 'hoje' then case when v.h < 12 then 'ainda esta manhã' else 'ainda hoje' end
    when v.q = 'amanhã' then case when v.h < 12 then 'amanhã de manhã' else 'amanhã' end
    when v.q ~ '^(segunda|terça|quarta|quinta|sexta) \([0-9]{2}/[0-9]{2}\)$'
      then 'na ' || split_part(v.q, ' (', 1) || case when v.h < 12 then ', pela manhã' else '' end
    when v.q ~ '^(sábado|domingo) \([0-9]{2}/[0-9]{2}\)$'
      then 'no ' || split_part(v.q, ' (', 1) || case when v.h < 12 then ', pela manhã' else '' end
  end
  from (select btrim(p_quando) as q, (regexp_match(btrim(p_hora), '^([0-9]{1,2})(h|:[0-9]{2})$'))[1]::int as h) v;
$$;

comment on function public._retorno_quando_fala(text, text) is
  'Retorno F1 (VOZ-2): o prazo como o cliente lê, a partir de {quando} e {hora}: ainda hoje, ainda esta manhã, amanhã de manhã, amanhã, na segunda, pela manhã. Nulo se não reconhece.';

-- A Claudia se apresenta uma vez por cliente (VOZ-1, VOZ-6).
alter table public.retorno_config alter column apresentacao_intervalo set default '365 days';
update public.retorno_config set apresentacao_intervalo = interval '365 days' where apresentacao_intervalo = interval '30 days';

create or replace function public._cliente_ja_apresentada(p_client_id uuid, p_chave text, p_hoje date)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  with j as (
    select (p_hoje::timestamp at time zone 'America/Sao_Paulo')
             - coalesce((public._retorno_cfg()).apresentacao_intervalo, interval '365 days') as desde,
           ((p_hoje + 1)::timestamp at time zone 'America/Sao_Paulo') as ate
  )
  select exists (select 1 from public.agenda_cliente_mensagens m, j
                  where p_client_id is not null
                    and m.client_id = p_client_id
                    and m.enviada_em > j.desde and m.enviada_em < j.ate)
      or exists (select 1 from public.retorno_saidas s, j
                  where s.emissor = 'retorno'
                    and s.estado = 'enviada'
                    and s.tipo not in ('acorde', 'cadastro_provisorio', 'fila')
                    and (s.client_id = p_client_id or s.chave = p_chave)
                    and s.enviada_em > j.desde and s.enviada_em < j.ate);
$$;

comment on function public._cliente_ja_apresentada(uuid, text, date) is
  'VOZ-1 e VOZ-6: a Claudia já falou com este cliente? Conta agenda_cliente_mensagens enviada (por cliente) e retorno_saidas enviada ao cliente (por cliente ou chave de 8 dígitos), na janela de retorno_config.apresentacao_intervalo. A incerta não conta: repetir a apresentação é melhor que omitir.';

-- Os textos fixos. Falta de dado ou valor fora da lista fechada = 22023.
create or replace function public._retorno_texto(p_tipo text, p_variante text, p_dados jsonb)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  c_dia constant text := '^(hoje|amanhã|(segunda|terça|quarta|quinta|sexta|sábado|domingo) \([0-9]{2}/[0-9]{2}\))$';
  c_hora constant text := '^[0-9]{1,2}h$|^[0-9]{2}:[0-9]{2}$';
  c_risco constant text := 'Se houver fogo, fumaça ou água entrando, ligue 193 (Bombeiros).';   -- L01
  d jsonb := case when jsonb_typeof(p_dados) = 'object' then p_dados else '{}'::jsonb end;
  v_modelo text;
  v_texto text;
  v_campo text;
  v_valor text;
  v_parte text;
  v_ok boolean;
begin
  v_modelo := case p_tipo || '/' || p_variante
    when 'recibo_cliente/padrao' then -- T01
      'Oi, {nome}! Já passei sua mensagem ao Gustavo, e ele retorna para você {quando_fala}.'
    when 'recibo_cliente/padrao_apresentacao' then -- T02
      'Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. Já passei sua mensagem ao Gustavo, e ele retorna para você {quando_fala}.'
    when 'recibo_cliente/sem_nome' then -- T03
      'Olá! Aqui é a Claudia, assistente virtual da HBR. Já passei sua mensagem ao Gustavo, e ele retorna para você {quando_fala}.'
    when 'recibo_cliente/outro_dia' then -- T04
      'Oi, {nome}! Já passei sua mensagem ao Gustavo, e ele retorna para você {quando_fala}. Se for urgente, é só responder "urgente" que eu aviso o Gustavo na hora.'
    when 'recibo_cliente/outro_dia_apresentacao' then -- T05
      'Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. Já passei sua mensagem ao Gustavo, e ele retorna para você {quando_fala}. Se for urgente, é só responder "urgente" que eu aviso o Gustavo na hora.'
    when 'recibo_cliente/outro_dia_sem_nome' then -- T06
      'Olá! Aqui é a Claudia, assistente virtual da HBR. Já passei sua mensagem ao Gustavo, e ele retorna para você {quando_fala}. Se for urgente, é só responder "urgente" que eu aviso o Gustavo na hora.'
    when 'recibo_cliente/manha' then -- T07
      'Bom dia, {nome}! Vi sua mensagem {de_quando} e já passei ao Gustavo. Ele retorna para você {quando_fala}.'
    when 'recibo_cliente/manha_apresentacao' then -- T07a
      'Bom dia, {nome}! Aqui é a Claudia, assistente virtual da HBR. Vi sua mensagem {de_quando} e já passei ao Gustavo. Ele retorna para você {quando_fala}.'
    when 'recibo_cliente/manha_outro_dia' then -- T08
      'Bom dia, {nome}! Vi sua mensagem {de_quando} e já passei ao Gustavo. Ele retorna para você {quando_fala}.'
    when 'recibo_cliente/manha_outro_dia_apresentacao' then -- T08a
      'Bom dia, {nome}! Aqui é a Claudia, assistente virtual da HBR. Vi sua mensagem {de_quando} e já passei ao Gustavo. Ele retorna para você {quando_fala}.'
    when 'recibo_cliente/manha_sem_nome' then -- T09
      'Bom dia! Aqui é a Claudia, assistente virtual da HBR. Vi sua mensagem {de_quando} e já passei ao Gustavo. Ele retorna para você {quando_fala}.'
    when 'recibo_cliente/fora_ate' then -- T10
      'Oi, {nome}! O Gustavo está fora até {quando}, mas sua mensagem já está com ele. Ele retorna para você {quando_fala}.'
    when 'recibo_cliente/fora_ate_apresentacao' then -- T10a
      'Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. O Gustavo está fora até {quando}, mas sua mensagem já está com ele. Ele retorna para você {quando_fala}.'
    when 'recibo_cliente/fora_ate_sem_nome' then -- T11
      'Olá! Aqui é a Claudia, assistente virtual da HBR. O Gustavo está fora até {quando}, mas sua mensagem já está com ele. Ele retorna para você {quando_fala}.'
    when 'recibo_cliente/volta' then -- T12
      'Oi, {nome}! Sua mensagem de {dia_msg} às {hora_msg} só chegou para nós agora. Desculpe a demora. Já passei ao Gustavo, e ele retorna para você {quando_fala}.'
    when 'recibo_cliente/volta_apresentacao' then -- T12a
      'Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. Sua mensagem de {dia_msg} às {hora_msg} só chegou para nós agora. Desculpe a demora. Já passei ao Gustavo, e ele retorna para você {quando_fala}.'
    when 'recibo_cliente/volta_queda' then -- T13
      'Oi, {nome}! Nosso WhatsApp ficou fora do ar por um tempo, e sua mensagem de {dia_msg} às {hora_msg} só chegou agora. Desculpe a demora. Já passei ao Gustavo, e ele retorna para você {quando_fala}.'
    when 'recibo_cliente/volta_queda_apresentacao' then -- T13a
      'Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. Nosso WhatsApp ficou fora do ar por um tempo, e sua mensagem de {dia_msg} às {hora_msg} só chegou agora. Desculpe a demora. Já passei ao Gustavo, e ele retorna para você {quando_fala}.'
    when 'recibo_ambiguo/padrao' then -- T14
      'Olá! Aqui é a Claudia, assistente virtual da HBR. Já passei sua mensagem ao Gustavo, e ele retorna para você {quando_fala}.'
    when 'recibo_numero_novo/pergunta_necessidade' then -- T15
      '{cumprimento}! Aqui é a Claudia, assistente virtual da HBR. Já passei seu pedido ao Gustavo, que cuida dos orçamentos, e ele retorna para você {quando_fala}. Para adiantar, pode me contar o que precisa resolver ou instalar? Pode ser por áudio.'
    when 'recibo_numero_novo/pergunta_modelo' then -- T16
      '{cumprimento}! Aqui é a Claudia, assistente virtual da HBR. Já passei seu pedido ao Gustavo, que cuida dos orçamentos, e ele retorna para você {quando_fala}. Para adiantar, qual é o modelo e o ano {do_bem}?'
    when 'recibo_numero_novo/sem_pergunta' then -- T17
      '{cumprimento}! Aqui é a Claudia, assistente virtual da HBR. Já passei seu pedido ao Gustavo, que cuida dos orçamentos, e ele retorna para você {quando_fala}.'
    when 'coleta_numero_novo/nome' then -- T18
      'Obrigada! Já passei ao Gustavo. Como posso chamar você?'
    when 'saudacao_numero_novo/padrao' then -- T19
      '{cumprimento}! Aqui é a Claudia, assistente virtual da HBR. Em que posso ajudar? Se preferir, pode mandar um áudio.'
    when 'adiamento/com_nome' then -- T20
      '{nome}, o Gustavo ainda não conseguiu retornar, mas seu pedido está com ele e a resposta sai ainda hoje. Se for urgente, é só responder "urgente" que eu aviso o Gustavo na hora.'
    when 'adiamento/sem_nome' then -- T21
      'O Gustavo ainda não conseguiu retornar, mas seu pedido está com ele e a resposta sai ainda hoje. Se for urgente, é só responder "urgente" que eu aviso o Gustavo na hora.'
    when 'fim_do_dia/com_nome' then -- T22
      '{nome}, o Gustavo não conseguiu retornar hoje, peço desculpas. Seu pedido é o primeiro da lista dele {quando_lista} cedo.'
    when 'fim_do_dia/sem_nome' then -- T23
      'O Gustavo não conseguiu retornar hoje, peço desculpas. Seu pedido é o primeiro da lista dele {quando_lista} cedo.'
    when 'urgente/acorde' then -- T24
      'Avisei o Gustavo agora mesmo, {nome}.'
    when 'urgente/sem_acorde' then -- T25
      'Anotei como urgente, {nome}. O Gustavo vê {quando_lista} cedo, antes de tudo.'
    when 'urgente/sem_acorde_sem_nome' then -- T26
      'Anotei como urgente. O Gustavo vê {quando_lista} cedo, antes de tudo.'
    when 'parar/com_nome' then -- T27
      'Combinado, {nome}. Não envio mais mensagens automáticas. Quando precisar, é só escrever.'
    when 'parar/sem_nome' then -- T28
      'Combinado. Não envio mais mensagens automáticas. Quando precisar, é só escrever.'
  end;
  if v_modelo is null then
    raise exception using errcode = '22023',
      message = format('retorno_texto: modelo desconhecido %s/%s', coalesce(p_tipo, '(nenhum)'), coalesce(p_variante, '(nenhuma)'));
  end if;

  -- Cada {campo} do modelo, na ordem em que aparece: presente, não vazio e dentro da lista fechada.
  -- Nenhum valor aceito tem chave ({ ou }), então a troca de um campo nunca cria outro campo.
  v_texto := v_modelo;
  for v_campo in
    select x.m[1] from regexp_matches(v_modelo, '\{([a-z_]+)\}', 'g') with ordinality as x(m, n)
     group by x.m[1] order by min(x.n)
  loop
    -- {quando_fala} sai de quando + hora, que passam pela mesma conferência dos outros campos.
    if v_campo = 'quando_fala' then
      foreach v_parte in array array['quando', 'hora'] loop
        v_valor := btrim(d ->> v_parte);
        if coalesce(v_valor, '') = '' then
          raise exception using errcode = '22023', message = 'retorno_texto: falta ' || v_parte;
        end if;
        if v_valor !~ case v_parte when 'quando' then c_dia else c_hora end then
          raise exception using errcode = '22023', message = 'retorno_texto: valor fora da lista em ' || v_parte;
        end if;
      end loop;
      v_valor := public._retorno_quando_fala(btrim(d ->> 'quando'), btrim(d ->> 'hora'));
      if v_valor is null then
        raise exception using errcode = '22023', message = 'retorno_texto: valor fora da lista em quando';
      end if;
      v_texto := replace(v_texto, '{quando_fala}', v_valor);
      continue;
    end if;
    v_valor := btrim(d ->> v_campo);
    if coalesce(v_valor, '') = '' then
      raise exception using errcode = '22023', message = 'retorno_texto: falta ' || v_campo;
    end if;
    v_ok := case v_campo
      when 'cumprimento' then v_valor in ('Bom dia', 'Boa tarde', 'Boa noite')
      when 'de_quando' then v_valor in ('de ontem à noite', 'desta madrugada')
      when 'quando' then v_valor ~ c_dia
      when 'quando_lista' then v_valor ~ c_dia
      when 'dia_msg' then v_valor ~ c_dia
      when 'hora' then v_valor ~ c_hora
      when 'hora_msg' then v_valor ~ c_hora
      when 'nome' then char_length(v_valor) between 1 and 40 and v_valor !~ '[0-9]' and v_valor !~ '[[:cntrl:]{}]'
      when 'do_bem' then v_valor ~ '^d[oa] [a-záéíóúâêôãõç ]{2,20}$'
      else false
    end;
    if not coalesce(v_ok, false) then
      raise exception using errcode = '22023', message = 'retorno_texto: valor fora da lista em ' || v_campo;
    end if;
    v_texto := replace(v_texto, '{' || v_campo || '}', v_valor);
  end loop;

  -- A linha de risco (B.3) só nos recibos.
  if p_tipo in ('recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo') and d ->> 'risco' = 'true' then
    v_texto := v_texto || E'\n' || c_risco;
  end if;
  return v_texto;
end;
$$;

comment on function public._retorno_texto(text, text, jsonb) is
  'Retorno F1: os textos fixos da Claudia, T01–T28 e as apresentações T07a, T08a, T10a, T12a e T13a (e a linha de risco L01 nos recibos), com os {campos} de p_dados. Falta de dado, valor fora da lista fechada ou modelo desconhecido = 22023. Nenhum texto copia trecho do cliente nem tem emoji.';

revoke all on function public._retorno_quando(date, date) from public, anon, authenticated;
revoke all on function public._retorno_hora(time) from public, anon, authenticated;
revoke all on function public._retorno_cumprimento(timestamptz) from public, anon, authenticated;
revoke all on function public._retorno_proxima_manha(timestamptz, text) from public, anon, authenticated;
revoke all on function public._retorno_nome(uuid) from public, anon, authenticated;
revoke all on function public._retorno_do_bem(text) from public, anon, authenticated;
revoke all on function public._retorno_x2(timestamptz) from public, anon, authenticated;
revoke all on function public._retorno_oferece_urgente(text, text) from public, anon, authenticated;
revoke all on function public._retorno_prazo(timestamptz, text, boolean, boolean) from public, anon, authenticated;
revoke all on function public._retorno_texto(text, text, jsonb) from public, anon, authenticated;
revoke all on function public._retorno_quando_fala(text, text) from public, anon, authenticated;
revoke all on function public._cliente_ja_apresentada(uuid, text, date) from public, anon, authenticated;
