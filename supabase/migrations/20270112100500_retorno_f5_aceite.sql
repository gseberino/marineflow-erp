-- Retorno rápido ao cliente, F5 (P6): o aceite por texto (C9) e os dados da nota depois dele. Nada liga aqui.
--
-- 1. _orcamento_aceite: um léxico estrito, sem IA, que erra para o lado de NÃO achar aceite. O "?", o "R$", o número e o
--    "%" são lidos no texto cru (o _retorno_busca tira a pontuação, o "$" e o "%"); o resto, sobre _retorno_busca. Barreiras
--    antes das formas fortes: a contraproposta sem "R$" ("fecho em 4500", "pode fazer por quatro mil", "se for 4000 pode
--    fazer", "pela metade") nunca vira aceite.
-- 2. _orcamento_candidatos: os orçamentos enviados ao cliente na mesma chave ANTES da mensagem, com o 1º envio dentro de
--    aceite_janela; abertos (rascunho, sem conversão e sem agrupamento). Os candidatos são os do instante da mensagem.
-- 3. _orcamento_agenda_esperando: a agenda espera resposta deste cliente (mensagem enviada e sem resposta dentro de
--    cliente_resposta_validade) ou já gravou esta mensagem como resposta dela (agenda_cliente_respostas, modo ligado).
-- 4. _orcamento_aceites_detectar: a marca d'água retorno_config.orcamento_aceite_ate compara retorno_mensagens.processada_em,
--    com 10 minutos de folga (a hora do início da transação do retorno_abrir, não a do commit) e avança até o maior lido.
--    Toda recebida de papel 'cliente', com ou sem caso, por _orcamento_cliente_do_telefone: o papel vem do caso só quando o
--    telefone da mensagem é o mesmo do caso (o retorno_abrir junta a mensagem ao caso vivo só pela chave, e a de outro DDD
--    com os mesmos 8 dígitos é outra pessoa); sem caso, de quem_escreve com o telefone INTEIRO da mensagem (nunca a chave).
--    Áudio só com aceite_audio. A sombra vem antes da agenda: em sombra nada vai ao cartão, e resultado.seria guarda o que
--    seria (agenda, detectado ou duvida). Uma linha por mensagem; o corpo só é lido aqui dentro.
-- 5. _orcamento_cartao_aceites: a lista que o cartão lê (P7), vazia fora de aceite_modo = 'cartao'; o mais recente por
--    cliente e tipo de item.
-- 6. _orcamento_faltas_para_nota, _orcamento_documento_lido e _orcamento_cep_lido: o porte de faltasParaNota (paridade
--    em src/lib/ficha-cliente-paridade.test.ts), o CPF/CNPJ com dígito verificador válido e o CEP junto da palavra "cep".
-- 7. _orcamento_dados_detectar: a resposta com CPF ou CEP depois do pedido de dados enviado, dentro de dados_nota_janela,
--    vinda do mesmo telefone da saída (_mesmo_telefone: os 8 dígitos e o mesmo DDD).
-- 8. orcamento_aceite_com_sinal, orcamento_aceite_registrar (C-ACEITE-REG) e orcamento_dados_gravar: a letra A/C, o
--    registro com o "Fechado" (e o pedido de dados) em retorno_saidas, e a gravação só do que está vazio na ficha. O
--    registro confere de novo, por _orcamento_cliente_do_telefone, que o número fala pelo cliente do aceite; senão nada
--    sai (resultado.saida_nao_saiu = 'numero_compartilhado').
-- 9. _orcamento_aceite_fechar_antigos: decidido o aceite mais recente, os mais antigos do mesmo cliente seguem a decisão
--    (substituido) ou caem por pessoal; com orcamento_mudou ou sem_candidato, ficam.
--
-- Sem dado: só funções. Tudo nasce desligado (aceite_modo = 'desligado': a detecção só avança a marca; aceite_audio e
-- dados_nota_ligado falsos). Reverter: update public.retorno_config set aceite_modo = 'desligado' where id; e drop das
-- funções desta migration (orcamento_vigia, da P3, as chama dentro de begin … exception when undefined_function).

-- ── 1. O léxico do aceite ───────────────────────────────────────────────────────────────────────────────────────────────

create or replace function public._orcamento_aceite(p_texto text)
returns jsonb
language plpgsql
immutable
security definer
set search_path = public
as $$
declare
  c_fortes constant text[] := array[
    '\m((pode|podem|podemos) (fazer|seguir|executar|comecar|iniciar|marcar|agendar|tocar|dar andamento|mandar ver))\M',
    '\m(fechado|fechamos|vamos fechar|quero fechar|pode fechar|fecho)\M',
    '\m(aprovado|aprovada|aprovo|aprovei)\M',
    '\m(autorizo|autorizado|aceito|de acordo|topo)\M',
    '\m(vamos fazer|quero fazer|bora fazer)\M'];
  v_cru text := coalesce(p_texto, '');
  v_b text;
  v_barrado text;
  v_re text;
  v_m text[];
begin
  v_b := public._retorno_busca(v_cru);
  -- 1. Vazio, mídia sem legenda ou [audio] sem transcrição.
  if v_b = '' or v_cru ~ '^\s*\[[^]]*\]\s*$' then
    return jsonb_build_object('aceite', false, 'sinal', null, 'barrado', null);
  end if;

  -- 2. As barreiras. O "?" e o "R$" no texto cru, antes de qualquer normalização.
  if strpos(v_cru, '?') > 0 then
    v_barrado := 'pergunta';
  elsif v_cru ~* 'r\s*\$' then
    v_barrado := 'valor';
  elsif public._e_pedido_de_parar(v_cru) then
    v_barrado := 'parar';
  elsif public._retorno_encerrou(v_cru) then
    v_barrado := 'encerrou';
  elsif v_b ~ '\m(se|caso)\s+(voce|voces|vc|vcs|der|fizer|fizerem|fazer|baixar|conseguir|puder|for|ficar|sair)' then
    v_barrado := 'condicional';
  -- A negociação: qualquer número ou "%" no texto cru (valor, contraproposta, prazo; aceite de verdade quase nunca traz
  -- número, e errar aqui é não achar), o valor por extenso, a metade e o "menos".
  elsif v_cru ~ '[0-9%]'
     or v_b ~ ('(desconto|abatimento|mais barato|parcel|\mreais\M|valor|preco|caro|\m(mil|cem|cento|duzentos|trezentos|'
               || 'quatrocentos|quinhentos|seiscentos|setecentos|oitocentos|novecentos|conto|contos|pila|pilas|metade|menos|'
               || 'por cento)\M)') then
    v_barrado := 'negociacao';
  elsif v_b ~ '\m(nao|ainda nao|vou pensar|vou ver|vou analisar|depois (te )?(falo|aviso|retorno)|mais pra frente|outro momento)\M' then
    v_barrado := 'negacao';
  elsif v_b ~ '\m(pode|podem|consegue|conseguem)( me)? (fazer|mandar|passar|enviar) (o|um|uma|outro|outra)? ?(orcamento|cotacao|valor|preco)\M' then
    v_barrado := 'pedido_de_orcamento';
  end if;
  if v_barrado is not null then
    return jsonb_build_object('aceite', false, 'sinal', null, 'barrado', v_barrado);
  end if;

  -- 3. As formas fortes ("ok", "sim", "beleza", "show", "combinado" e "pode ser" sozinhos ficam de fora de propósito).
  foreach v_re in array c_fortes loop
    v_m := regexp_match(v_b, v_re);
    if v_m is not null then
      return jsonb_build_object('aceite', true, 'sinal', left(v_m[1], 40), 'barrado', null);
    end if;
  end loop;
  return jsonb_build_object('aceite', false, 'sinal', null, 'barrado', null);
end;
$$;

comment on function public._orcamento_aceite(text) is
  'Retorno F5 (P6.1): {aceite, sinal, barrado} do texto do cliente, sem IA. Falso: vazio, mídia sem legenda, [audio]. Barreiras, na ordem: pergunta ("?" no texto cru), valor ("R$" no texto cru), parar, encerrou, condicional (se/caso + você, der, fizer, fazer, baixar, conseguir, puder, for, ficar, sair), negociacao (qualquer número ou "%" no texto cru; desconto, abatimento, mais barato, parcel, reais, valor, preço, caro, o valor por extenso, metade, menos, por cento), negacao, pedido_de_orcamento (as outras sobre _retorno_busca). Aceite: pode/podem/podemos fazer|seguir|executar|começar|iniciar|marcar|agendar|tocar|dar andamento|mandar ver; fechado|fechamos|vamos fechar|quero fechar|pode fechar|fecho; aprovado|aprovada|aprovo|aprovei; autorizo|autorizado|aceito|de acordo|topo; vamos fazer|quero fazer|bora fazer. sinal = o trecho que casou (até 40).';

revoke all on function public._orcamento_aceite(text) from public, anon, authenticated;

-- ── 2. Os candidatos (no instante da mensagem) ──────────────────────────────────────────────────────────────────────────

create or replace function public._orcamento_candidatos(p_client uuid, p_chave text, p_recebida timestamptz, p_agora timestamptz)
returns uuid[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(array_agg(so.id order by so.created_at, so.id), '{}'::uuid[])
    from public.service_orders so
   where so.client_id = p_client
     and p_chave is not null
     and p_recebida is not null
     and p_recebida <= coalesce(p_agora, now())
     and so.status = 'draft'
     and so.converted_to_os_at is null
     and so.merged_into_id is null
     and (so.quote_status in ('sent', 'awaiting_approval')
          or (so.quote_status = 'draft'
              and exists (select 1 from public.orcamento_envios e0 where e0.service_order_id = so.id and e0.ao_cliente)))
     and exists (select 1 from public.orcamento_envios e
                  where e.service_order_id = so.id and e.ao_cliente and e.chave = p_chave and e.em < p_recebida)
     and (select min(e.em) from public.orcamento_envios e
           where e.service_order_id = so.id and e.ao_cliente and e.chave = p_chave)
         > p_recebida - coalesce((select c.aceite_janela from public.retorno_config c where c.id), interval '30 days');
$$;

comment on function public._orcamento_candidatos(uuid, text, timestamptz, timestamptz) is
  'Retorno F5 (P6.1): os orçamentos do cliente que podem ser o objeto do aceite da mensagem de p_recebida: rascunho sem conversão e sem agrupamento, funil em sent/awaiting_approval (ou draft com envio ao cliente), com um envio ao cliente na mesma chave antes da mensagem e o 1º envio a essa chave dentro de aceite_janela antes dela. Ordem de criação.';

revoke all on function public._orcamento_candidatos(uuid, text, timestamptz, timestamptz) from public, anon, authenticated;

-- ── 3. A agenda espera resposta deste cliente ───────────────────────────────────────────────────────────────────────────

-- (b) vale na prática: o webhook roda agenda_resposta_do_cliente antes do retorno, e ela já marca a mensagem da agenda como
-- respondida com a própria mensagem do cliente. (a) é a mensagem da agenda enviada (e sem resposta) dentro da validade,
-- contada da hora da mensagem do cliente.
create or replace function public._orcamento_agenda_esperando(p_client uuid, p_msg uuid, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_quando timestamptz;
  v_validade interval;
  v_os uuid;
begin
  select r.service_order_id into v_os
    from public.agenda_cliente_respostas r
   where r.whatsapp_message_id = p_msg and r.modo = 'ligado'
   order by r.criada_em desc, r.id
   limit 1;
  if found then
    return jsonb_build_object('espera', true,
                              'os', (select so.service_order_number from public.service_orders so where so.id = v_os));
  end if;

  select coalesce(w.hora_real, w.occurred_at) into v_quando from public.whatsapp_messages w where w.id = p_msg;
  v_quando := least(coalesce(v_quando, v_agora), v_agora);
  select a.cliente_resposta_validade into v_validade from public.agenda_config a where a.id;
  select m.service_order_id into v_os
    from public.agenda_cliente_mensagens m
   where m.client_id = p_client
     and m.modo = 'ligado'
     and m.estado in ('enviada', 'sem_resposta')
     and m.resposta_id is null
     and m.enviada_em <= v_quando
     and m.enviada_em > v_quando - coalesce(v_validade, interval '72 hours')
   order by m.enviada_em desc, m.id
   limit 1;
  if found then
    return jsonb_build_object('espera', true,
                              'os', (select so.service_order_number from public.service_orders so where so.id = v_os));
  end if;
  return jsonb_build_object('espera', false, 'os', null);
end;
$$;

comment on function public._orcamento_agenda_esperando(uuid, uuid, timestamptz) is
  'Retorno F5 (P6.1): {espera, os}. Verdadeiro quando esta mensagem já é resposta à agenda (agenda_cliente_respostas pelo whatsapp_message_id, modo ligado) ou quando há mensagem da agenda a este cliente enviada (modo ligado), sem resposta, dentro de agenda_config.cliente_resposta_validade antes da mensagem. os = o número da OS da agenda.';

revoke all on function public._orcamento_agenda_esperando(uuid, uuid, timestamptz) from public, anon, authenticated;

-- ── 4. O que falta para a nota (porte de faltasParaNota) ───────────────────────────────────────────────────────────────

-- Os mesmos rótulos e a mesma ordem de src/lib/ficha-cliente.ts. "Vazio" é o trim() do JavaScript (espaço, tab, quebra
-- de linha e os espaços Unicode); "só dígitos" é o \D do JavaScript (0 a 9).
create or replace function public._orcamento_faltas_para_nota(p_client uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_vazio constant text := '^[\s   -     　﻿]*$';
  v_c record;
  v_doc text;
  v_cep text;
  v_f text[] := '{}'::text[];
begin
  select c.cpf_cnpj, c.address_line_1, c.neighborhood, c.city, c.state, c.postal_code, c.ie_indicator, c.state_registration
    into v_c
    from public.clients c
   where c.id = p_client;
  if not found then
    return null;
  end if;
  v_doc := regexp_replace(coalesce(v_c.cpf_cnpj, ''), '[^0-9]', '', 'g');
  if v_doc = '' then
    v_f := v_f || 'CPF/CNPJ'::text;
  elsif char_length(v_doc) not in (11, 14) then
    v_f := v_f || 'CPF/CNPJ incompleto'::text;
  end if;
  if v_c.ie_indicator = 1 and regexp_replace(coalesce(v_c.state_registration, ''), '[^0-9]', '', 'g') = '' then
    v_f := v_f || 'inscrição estadual'::text;
  end if;
  if coalesce(v_c.address_line_1, '') ~ c_vazio then
    v_f := v_f || 'rua'::text;
  end if;
  if coalesce(v_c.neighborhood, '') ~ c_vazio then
    v_f := v_f || 'bairro'::text;
  end if;
  if coalesce(v_c.city, '') ~ c_vazio then
    v_f := v_f || 'cidade'::text;
  end if;
  if coalesce(v_c.state, '') ~ c_vazio then
    v_f := v_f || 'UF'::text;
  end if;
  v_cep := regexp_replace(coalesce(v_c.postal_code, ''), '[^0-9]', '', 'g');
  if v_cep = '' then
    v_f := v_f || 'CEP'::text;
  elsif char_length(v_cep) <> 8 then
    v_f := v_f || 'CEP incompleto'::text;
  end if;
  return v_f;
end;
$$;

comment on function public._orcamento_faltas_para_nota(uuid) is
  'Retorno F5 (P6.1): o porte de faltasParaNota (src/lib/ficha-cliente.ts): CPF/CNPJ, CPF/CNPJ incompleto, inscrição estadual (ie_indicator = 1 sem IE), rua, bairro, cidade, UF, CEP, CEP incompleto, na mesma ordem. Cliente que não existe: nulo. Paridade em src/lib/ficha-cliente-paridade.test.ts.';

revoke all on function public._orcamento_faltas_para_nota(uuid) from public, anon, authenticated;

-- ── 5. O documento e o CEP lidos da resposta do cliente ─────────────────────────────────────────────────────────────────

-- Os trechos de dígitos com a pontuação de documento (. / -); o 1º com 11 dígitos e o CPF válido, ou 14 e o CNPJ válido (a
-- conta de isValidCPF e isValidCNPJ, src/lib/masks.ts). Nenhum dígito sai daqui a não ser o documento.
create or replace function public._orcamento_documento_lido(p_texto text)
returns text
language plpgsql
immutable
security definer
set search_path = public
as $$
declare
  c_w1 constant integer[] := array[5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
  c_w2 constant integer[] := array[6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
  v_t text;
  v_d text;
  v_s integer;
  v_r integer;
begin
  for v_t in select (regexp_matches(coalesce(p_texto, ''), '[0-9][0-9./-]*[0-9]', 'g'))[1] loop
    v_d := regexp_replace(v_t, '[^0-9]', '', 'g');
    if char_length(v_d) = 11 and v_d <> repeat(left(v_d, 1), 11) then
      select sum(substr(v_d, g, 1)::integer * (11 - g)) into v_s from generate_series(1, 9) g;
      v_r := 11 - (v_s % 11);
      if v_r >= 10 then
        v_r := 0;
      end if;
      continue when v_r <> substr(v_d, 10, 1)::integer;
      select sum(substr(v_d, g, 1)::integer * (12 - g)) into v_s from generate_series(1, 10) g;
      v_r := 11 - (v_s % 11);
      if v_r >= 10 then
        v_r := 0;
      end if;
      continue when v_r <> substr(v_d, 11, 1)::integer;
      return v_d;
    elsif char_length(v_d) = 14 and v_d <> repeat(left(v_d, 1), 14) then
      select sum(substr(v_d, g, 1)::integer * c_w1[g]) into v_s from generate_series(1, 12) g;
      v_r := (case when v_s % 11 < 2 then 0 else 11 - v_s % 11 end);
      continue when v_r <> substr(v_d, 13, 1)::integer;
      select sum(substr(v_d, g, 1)::integer * c_w2[g]) into v_s from generate_series(1, 13) g;
      v_r := (case when v_s % 11 < 2 then 0 else 11 - v_s % 11 end);
      continue when v_r <> substr(v_d, 14, 1)::integer;
      return v_d;
    end if;
  end loop;
  return null;
end;
$$;

comment on function public._orcamento_documento_lido(text) is
  'Retorno F5 (P6.1): o 1º CPF (11 dígitos) ou CNPJ (14) com o dígito verificador válido no texto, com ou sem pontuação, só os dígitos; senão nulo (telefone de 11 dígitos que não é CPF válido: nulo). A conta de isValidCPF/isValidCNPJ.';

revoke all on function public._orcamento_documento_lido(text) from public, anon, authenticated;

create or replace function public._orcamento_cep_lido(p_texto text)
returns text
language plpgsql
immutable
security definer
set search_path = public
as $$
declare
  v_t text := lower(coalesce(p_texto, ''));
  v_m text[];
begin
  v_m := regexp_match(v_t, '\mcep\M[^0-9]{0,4}([0-9]{2}\.?[0-9]{3}-?[0-9]{3})(?![0-9])');
  if v_m is null then
    v_m := regexp_match(v_t, '(?:^|[^0-9])([0-9]{2}\.?[0-9]{3}-?[0-9]{3})[^0-9a-z]{0,3}\mcep\M');
  end if;
  if v_m is null then
    return null;
  end if;
  return regexp_replace(v_m[1], '[^0-9]', '', 'g');
end;
$$;

comment on function public._orcamento_cep_lido(text) is
  'Retorno F5 (P6.1): o CEP (8 dígitos, com ou sem ponto e traço) junto da palavra "cep" (logo depois dela, ou logo antes), só os dígitos; senão nulo.';

revoke all on function public._orcamento_cep_lido(text) from public, anon, authenticated;

-- ── 6. A detecção do aceite ─────────────────────────────────────────────────────────────────────────────────────────────

-- Por qual cliente o telefone fala. Com caso: o do caso (papel 'cliente'), só quando o telefone é o mesmo do caso
-- (_mesmo_telefone: os 8 dígitos e o mesmo DDD). O retorno_abrir junta a mensagem ao caso vivo só pela chave: a de outro DDD
-- com os mesmos 8 dígitos (outra pessoa) entra no caso do cliente, e o caso não fala por ela. O cliente que o dono escolheu
-- para o caso vale para o telefone do caso. Sem caso (ou com o caso apagado): quem_escreve com o telefone inteiro, nunca a
-- chave (com os 8 dígitos, o DDD sairia nulo). Só o papel 'cliente' dá o cliente; senão, nulo.
create or replace function public._orcamento_cliente_do_telefone(p_abertura uuid, p_fone text)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_papel text;
  v_cliente uuid;
  v_fone_caso text;
  v_q jsonb;
begin
  if p_abertura is not null then
    select ab.papel, ab.client_id, ab.phone_normalized into v_papel, v_cliente, v_fone_caso
      from public.retorno_aberturas ab
     where ab.id = p_abertura;
    if found then
      if v_papel = 'cliente' and public._mesmo_telefone(v_fone_caso, p_fone) then
        return v_cliente;
      end if;
      return null;
    end if;
  end if;
  v_q := public.quem_escreve(p_fone);
  if v_q ->> 'papel' = 'cliente' then
    return nullif(v_q ->> 'cliente_id', '')::uuid;
  end if;
  return null;
end;
$$;

comment on function public._orcamento_cliente_do_telefone(uuid, text) is
  'Retorno F5 (P6.1): o cliente por quem p_fone fala. Com o caso p_abertura: o client_id do caso de papel cliente, só quando p_fone é o mesmo telefone do caso (_mesmo_telefone; o retorno_abrir junta a mensagem ao caso só pela chave, e outro DDD com os mesmos 8 dígitos é outra pessoa). Sem caso, ou com o caso apagado: quem_escreve(p_fone) com papel cliente. Senão, nulo.';

revoke all on function public._orcamento_cliente_do_telefone(uuid, text) from public, anon, authenticated;

create or replace function public._orcamento_aceites_detectar(p_agora timestamptz)
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config;
  v_marca timestamptz;
  v_max timestamptz;
  v_r record;
  v_w public.whatsapp_messages;
  v_client uuid;
  v_lex jsonb;
  v_cands uuid[];
  v_ag jsonb;
  v_seria text;
  v_estado text;
  v_os uuid;
  v_total numeric;
  v_res jsonb;
  v_faltas text[];
  v_id uuid;
  v_n integer := 0;
begin
  select * into v_cfg from public.retorno_config c where c.id for update;
  if v_cfg.id is null then
    return 0;
  end if;
  v_marca := v_cfg.orcamento_aceite_ate;
  -- Desligado, ou a 1ª vez: só avança a marca.
  if v_cfg.aceite_modo = 'desligado' or v_marca is null then
    update public.retorno_config c
       set orcamento_aceite_ate = greatest(coalesce(c.orcamento_aceite_ate, v_agora), v_agora)
     where c.id;
    return 0;
  end if;

  v_max := v_marca;
  -- A folga de 10 minutos: processada_em é o now() do retorno_abrir (o início da transação dele, não o commit). Reler a
  -- mesma linha não faz mal: a que gravou aceite para no on conflict, e os candidatos são os do instante recebida_em.
  for v_r in
    select rm.whatsapp_message_id, rm.abertura_id, rm.chave, rm.recebida_em, rm.processada_em, rm.consumida, rm.agenda_ao_dono
      from public.retorno_mensagens rm
     where rm.processada_em > v_marca - interval '10 minutes'
       and rm.processada_em <= v_agora
       and rm.recebida_em <= v_agora
     order by rm.processada_em, rm.whatsapp_message_id
  loop
    v_max := greatest(v_max, v_r.processada_em);
    begin
      continue when exists (select 1 from public.orcamento_aceites a where a.whatsapp_message_id = v_r.whatsapp_message_id);
      select * into v_w from public.whatsapp_messages w where w.id = v_r.whatsapp_message_id;
      continue when not found or v_w.direction is distinct from 'inbound';

      -- O cliente: o do caso, quando há e o telefone da mensagem é o do caso; sem caso, quem_escreve com o telefone inteiro
      -- da mensagem (com a chave, o DDD sairia nulo e um cadastro de outro DDD com os mesmos 8 dígitos viraria o cliente).
      v_client := public._orcamento_cliente_do_telefone(v_r.abertura_id, v_w.phone_normalized);
      continue when v_client is null;

      -- O áudio só com aceite_audio (dúvida 7). Sem transcrição ([audio]), o léxico dá falso; a transcrição traz a linha de
      -- volta pela marca (a reavaliação regrava processada_em).
      continue when v_w.message_type = 'audio' and not coalesce(v_cfg.aceite_audio, false);
      v_lex := public._orcamento_aceite(v_w.body);
      continue when not coalesce((v_lex ->> 'aceite')::boolean, false);
      v_cands := coalesce(public._orcamento_candidatos(v_client, v_r.chave, v_r.recebida_em, v_agora), '{}'::uuid[]);
      continue when cardinality(v_cands) = 0;

      -- O que ele seria: agenda (consumida, passada ao dono ou a agenda esperando), detectado (1 candidato) ou duvida.
      v_ag := public._orcamento_agenda_esperando(v_client, v_r.whatsapp_message_id, v_agora);
      v_seria := (case when v_r.consumida or v_r.agenda_ao_dono or coalesce((v_ag ->> 'espera')::boolean, false) then 'agenda'
                       when cardinality(v_cands) = 1 then 'detectado'
                       else 'duvida' end);
      -- A sombra vem antes de tudo: nada da sombra vai ao cartão.
      v_estado := (case when v_cfg.aceite_modo = 'sombra' then 'sombra' else v_seria end);
      v_os := (case when cardinality(v_cands) = 1 then v_cands[1] end);
      v_total := null;
      if v_os is not null then
        select so.grand_total into v_total from public.service_orders so where so.id = v_os;
      end if;
      v_res := (case when v_estado = 'sombra' then jsonb_build_object('seria', v_seria) else '{}'::jsonb end)
               || (case when v_seria = 'agenda' then jsonb_build_object('os_agenda', v_ag ->> 'os') else '{}'::jsonb end);
      v_faltas := (case when v_estado = 'detectado' then coalesce(public._orcamento_faltas_para_nota(v_client), '{}'::text[])
                        else '{}'::text[] end);
      v_id := null;
      insert into public.orcamento_aceites (abertura_id, whatsapp_message_id, client_id, chave, candidatos, service_order_id,
                                            sinal_lido, estado, faltas_nota, total_visto, resultado)
      values (v_r.abertura_id, v_r.whatsapp_message_id, v_client, v_r.chave, v_cands, v_os,
              left(coalesce(v_lex ->> 'sinal', ''), 40), v_estado, v_faltas, v_total, v_res)
      on conflict (whatsapp_message_id) do nothing
      returning id into v_id;
      if v_id is not null then
        v_n := v_n + 1;
      end if;
    exception when others then
      -- Erro nunca trava a fila: a próxima mensagem segue.
      perform public._retorno_log('orcamento_aceites_detectar', '_orcamento_aceites_detectar: ' || sqlerrm, 'error',
                                  jsonb_build_object('mensagem', v_r.whatsapp_message_id, 'sqlstate', sqlstate));
    end;
  end loop;

  -- A marca avança até o maior lido (nunca a p_agora: a linha confirmada depois volta pela folga).
  update public.retorno_config c
     set orcamento_aceite_ate = greatest(coalesce(c.orcamento_aceite_ate, v_max), v_max)
   where c.id;
  return v_n;
end;
$$;

comment on function public._orcamento_aceites_detectar(timestamptz) is
  'Retorno F5 (P6.1): grava orcamento_aceites a partir de retorno_mensagens com processada_em em (orcamento_aceite_ate − 10 min, p_agora] e recebida_em até p_agora, com ou sem caso. O cliente de _orcamento_cliente_do_telefone (o do caso de papel cliente, só com o telefone da mensagem igual ao do caso; sem caso, quem_escreve com o telefone inteiro da mensagem); áudio só com aceite_audio; _orcamento_aceite; candidatos de _orcamento_candidatos no instante da mensagem. Estado: sombra (com aceite_modo sombra, resultado.seria), agenda (consumida, agenda_ao_dono ou _orcamento_agenda_esperando; resultado.os_agenda), detectado (1 candidato, com total_visto e faltas_nota) ou duvida. Desligado ou 1ª vez: só avança a marca; senão avança até o maior processada_em lido. Devolve quantos gravou.';

revoke all on function public._orcamento_aceites_detectar(timestamptz) from public, anon, authenticated;

-- ── 7. A lista que o cartão lê ──────────────────────────────────────────────────────────────────────────────────────────

-- Aceites à espera da letra (detectado, duvida, agenda, sem executado_em) e os decididos cujo "Fechado" ou pedido de dados
-- não saiu (resultado.saida_nao_saiu, até a marca resultado.nao_saiu_fechado_em, que o cartão e o fechamento gravam: P7 e
-- P8) são o tipo 'aceite'; os com a resposta de dados lida, o tipo 'dados_nota'. O mais recente por cliente e tipo, com a
-- hora da mensagem. Fora de aceite_modo = 'cartao', vazia: a sombra nunca entra, e voltar de 'cartao' tira tudo na hora.
create or replace function public._orcamento_cartao_aceites(p_agora timestamptz)
returns table (aceite_id uuid, tipo_item text, abertura_id uuid, hora timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select x.id, x.tipo, x.abertura, x.quando
    from (select distinct on (b.client_id, b.tipo) b.id, b.tipo, b.abertura, b.quando
            from (select a.id, a.client_id, 'aceite'::text as tipo, a.abertura_id as abertura,
                         coalesce(w.hora_real, w.occurred_at) as quando
                    from public.orcamento_aceites a
                    left join public.whatsapp_messages w on w.id = a.whatsapp_message_id
                   where (a.estado in ('detectado', 'duvida', 'agenda') and a.executado_em is null)
                      or (a.estado in ('com_sinal', 'sem_sinal') and a.resultado ? 'saida_nao_saiu'
                          and not (a.resultado ? 'nao_saiu_fechado_em'))
                  union all
                  select a.id, a.client_id, 'dados_nota'::text, a.abertura_id, coalesce(d.hora_real, d.occurred_at)
                    from public.orcamento_aceites a
                    left join public.whatsapp_messages d on d.id = a.dados_msg_id
                   where a.dados_estado = 'lidos') b
           where exists (select 1 from public.retorno_config c where c.id and c.aceite_modo = 'cartao')
             and b.quando is not null
             and b.quando <= coalesce(p_agora, now())
           order by b.client_id, b.tipo, b.quando desc, b.id desc) x
   order by x.quando, x.id;
$$;

comment on function public._orcamento_cartao_aceites(timestamptz) is
  'Retorno F5 (P6.1): a lista de aceites que o cartão lê (P7): tipo aceite (detectado, duvida e agenda sem executado_em; com_sinal e sem_sinal com resultado.saida_nao_saiu e sem resultado.nao_saiu_fechado_em) e dados_nota (dados_estado = lidos), o mais recente por cliente e tipo, com o abertura_id do aceite (pode ser nulo) e a hora da mensagem até p_agora. Vazia fora de aceite_modo = cartao. Não olha o estado do caso.';

revoke all on function public._orcamento_cartao_aceites(timestamptz) from public, anon, authenticated;

-- ── 8. A resposta com os dados da nota ──────────────────────────────────────────────────────────────────────────────────

-- O aceite esperando dados (a saída orc_dados_nota enviada, ou incerta, há até dados_nota_janela): a 1ª recebida do mesmo
-- telefone da saída (_mesmo_telefone: os 8 dígitos e o mesmo DDD; outro DDD com os mesmos 8 dígitos é outra pessoa, e o CPF
-- dela iria à ficha do cliente) depois dela, dentro da janela, com CPF/CNPJ válido ou CEP. Só o id da mensagem é gravado;
-- nenhum dígito sai daqui.
create or replace function public._orcamento_dados_detectar(p_agora timestamptz)
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_janela interval;
  v_r record;
  v_msg uuid;
  v_n integer := 0;
begin
  select coalesce(c.dados_nota_janela, interval '7 days') into v_janela from public.retorno_config c where c.id;
  v_janela := coalesce(v_janela, interval '7 days');
  for v_r in
    select a.id, a.chave, s.saiu, s.fone
      from public.orcamento_aceites a
      join lateral (select coalesce(rs.enviada_em, rs.decidida_em) as saiu, rs.phone_normalized as fone
                      from public.retorno_saidas rs
                     where rs.emissor = 'orcamento' and rs.tipo = 'orc_dados_nota'
                       and rs.dados ->> 'aceite_id' = a.id::text
                       and rs.estado in ('enviada', 'incerta')
                     order by coalesce(rs.enviada_em, rs.decidida_em) desc, rs.id
                     limit 1) s on true
     where a.dados_estado = 'esperando'
       and s.saiu is not null
       and s.saiu <= v_agora
       and s.saiu > v_agora - v_janela
     order by a.criado_em, a.id
  loop
    begin
      v_msg := null;
      select w.id into v_msg
        from public.whatsapp_messages w
       where w.direction = 'inbound'
         and public._agenda_chave_telefone(w.phone_normalized) = v_r.chave
         and public._mesmo_telefone(w.phone_normalized, v_r.fone)
         and w.occurred_at > v_r.saiu - interval '1 day'
         and w.occurred_at <= v_agora
         and coalesce(w.hora_real, w.occurred_at) > v_r.saiu
         and coalesce(w.hora_real, w.occurred_at) <= v_agora
         and (public._orcamento_documento_lido(w.body) is not null or public._orcamento_cep_lido(w.body) is not null)
       order by coalesce(w.hora_real, w.occurred_at), w.id
       limit 1;
      if v_msg is not null then
        update public.orcamento_aceites a set dados_msg_id = v_msg, dados_estado = 'lidos'
         where a.id = v_r.id and a.dados_estado = 'esperando';
        if found then
          v_n := v_n + 1;
        end if;
      end if;
    exception when others then
      perform public._retorno_log('orcamento_dados_detectar', '_orcamento_dados_detectar: ' || sqlerrm, 'error',
                                  jsonb_build_object('aceite_id', v_r.id, 'sqlstate', sqlstate));
    end;
  end loop;
  return v_n;
end;
$$;

comment on function public._orcamento_dados_detectar(timestamptz) is
  'Retorno F5 (P6.1): o aceite com dados_estado = esperando e a saída orc_dados_nota enviada (ou incerta) há até dados_nota_janela: a 1ª recebida do mesmo telefone da saída (_mesmo_telefone: os 8 dígitos e o mesmo DDD) depois dela, até p_agora, em que _orcamento_documento_lido ou _orcamento_cep_lido não dá nulo vira dados_msg_id, com dados_estado = lidos. Nenhum dígito sai da função. Devolve quantos leu.';

revoke all on function public._orcamento_dados_detectar(timestamptz) from public, anon, authenticated;

-- ── 9. Os aceites mais antigos do mesmo cliente seguem a decisão ────────────────────────────────────────────────────────

create or replace function public._orcamento_aceite_fechar_antigos(p_aceite uuid, p_agora timestamptz)
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_a public.orcamento_aceites;
  v_quando timestamptz;
  v_ids uuid[];
  v_n integer := 0;
begin
  select * into v_a from public.orcamento_aceites a where a.id = p_aceite;
  if not found then
    return 0;
  end if;
  select coalesce(w.hora_real, w.occurred_at) into v_quando from public.whatsapp_messages w where w.id = v_a.whatsapp_message_id;
  v_quando := coalesce(v_quando, v_a.criado_em);
  -- Os mais antigos do mesmo cliente que ainda esperam a letra (e não estão com a ferramenta).
  select coalesce(array_agg(a.id), '{}'::uuid[]) into v_ids
    from public.orcamento_aceites a
    left join public.whatsapp_messages w on w.id = a.whatsapp_message_id
   where a.client_id = v_a.client_id
     and a.id <> v_a.id
     and a.estado in ('detectado', 'duvida', 'agenda')
     and a.executado_em is null
     and coalesce(w.hora_real, w.occurred_at, a.criado_em) < v_quando;
  if cardinality(v_ids) = 0 then
    return 0;
  end if;

  if v_a.estado in ('com_sinal', 'sem_sinal', 'nao_era', 'respondido') then
    -- A decisão é uma só, a do mais recente: os antigos nunca voltam ao cartão nem contam na medida.
    update public.orcamento_aceites a
       set estado = 'substituido', decidido_em = v_a.decidido_em, decidido_por = v_a.decidido_por,
           resultado = a.resultado || jsonb_build_object('substituido_por', v_a.id)
     where a.id = any (v_ids) and a.estado in ('detectado', 'duvida', 'agenda') and a.executado_em is null;
    get diagnostics v_n = row_count;
  elsif v_a.estado = 'caiu' and v_a.resultado ->> 'motivo' = 'pessoal' then
    -- O número é o mesmo: caem por pessoal também.
    update public.orcamento_aceites a
       set estado = 'caiu', decidido_em = coalesce(v_a.decidido_em, v_agora), decidido_por = v_a.decidido_por,
           resultado = a.resultado || jsonb_build_object('motivo', 'pessoal', 'caiu_com', v_a.id)
     where a.id = any (v_ids) and a.estado in ('detectado', 'duvida', 'agenda') and a.executado_em is null;
    get diagnostics v_n = row_count;
  end if;
  -- Caiu por orcamento_mudou ou sem_candidato: os antigos ficam e passam pela conferência e pelo vigia como qualquer aceite.
  return v_n;
end;
$$;

comment on function public._orcamento_aceite_fechar_antigos(uuid, timestamptz) is
  'Retorno F5 (P6.1): decidido o aceite p_aceite, os mais antigos (pela hora da mensagem) do mesmo client_id ainda detectado, duvida ou agenda e sem executado_em seguem a decisão: com_sinal, sem_sinal, nao_era ou respondido → substituido (resultado.substituido_por, decidido_em e decidido_por do recente); caiu por pessoal → caiu/pessoal; caiu por orcamento_mudou ou sem_candidato → ficam. Devolve quantos mudou.';

revoke all on function public._orcamento_aceite_fechar_antigos(uuid, timestamptz) from public, anon, authenticated;

-- ── 10. A letra A ou C: aprovado, aguardando o sinal ────────────────────────────────────────────────────────────────────

-- Só pelo executor do cartão, que na mesma transação chama logo depois orcamento_aceite_registrar(p_ok = true,
-- {escolha: com_sinal, …}). Não cria recebível e não converte (o passo 3b do playbook: com sinal a cobrar, não converte).
create or replace function public.orcamento_aceite_com_sinal(p_aceite uuid, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_a public.orcamento_aceites;
  v_recebida timestamptz;
  v_so record;
begin
  select * into v_a from public.orcamento_aceites a where a.id = p_aceite for update;
  if not found or v_a.estado is distinct from 'detectado' then
    return jsonb_build_object('ok', false, 'motivo', 'estado');
  end if;
  if v_a.service_order_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'orcamento_mudou');
  end if;
  select coalesce(w.hora_real, w.occurred_at) into v_recebida from public.whatsapp_messages w where w.id = v_a.whatsapp_message_id;
  if not (v_a.service_order_id = any (coalesce(public._orcamento_candidatos(v_a.client_id, v_a.chave, v_recebida, v_agora),
                                               '{}'::uuid[]))) then
    return jsonb_build_object('ok', false, 'motivo', 'orcamento_mudou');
  end if;
  select so.service_order_number, so.quote_status, so.grand_total into v_so
    from public.service_orders so where so.id = v_a.service_order_id for update;
  if v_so.grand_total is distinct from v_a.total_visto then
    return jsonb_build_object('ok', false, 'motivo', 'orcamento_mudou');
  end if;
  update public.service_orders so
     set quote_status = 'awaiting_deposit'
   where so.id = v_a.service_order_id and so.status = 'draft' and so.converted_to_os_at is null
     and so.quote_status in ('sent', 'awaiting_approval', 'draft');
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'orcamento_mudou');
  end if;
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
  values ('service_orders', v_a.service_order_id, 'update', coalesce(p_autor::text, 'retorno-f5'),
          jsonb_build_object('quote_status', v_so.quote_status), jsonb_build_object('quote_status', 'awaiting_deposit'),
          'Aceite por texto do cliente (mensagem ' || v_a.whatsapp_message_id || '): aprovado, aguardando o sinal');
  return jsonb_build_object('ok', true, 'numero', v_so.service_order_number, 'quote_status', 'awaiting_deposit');
end;
$$;

comment on function public.orcamento_aceite_com_sinal(uuid, uuid, timestamptz) is
  'Retorno F5 (P6.1): a letra A ou C do aceite. Exige o aceite detectado e o orçamento ainda candidato com o mesmo total visto (senão {ok: false, motivo: estado | orcamento_mudou}); passa o funil a awaiting_deposit (sem recebível e sem conversão) e grava audit_log com o id da mensagem do cliente. {ok, numero, quote_status}.';

revoke all on function public.orcamento_aceite_com_sinal(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.orcamento_aceite_com_sinal(uuid, uuid, timestamptz) to service_role;

-- ── 11. O registro do aceite e o "Fechado" (C-ACEITE-REG) ───────────────────────────────────────────────────────────────

-- Pré-condição: o aceite detectado e, em B/D (escolha sem_sinal), com executado_em (o *sim <PIN>* passou pelo executor).
-- Senão nada é gravado nem agendado: um "Fechado" só. As saídas levam todas as colunas NOT NULL de retorno_saidas: a chave
-- do aceite, o telefone da MENSAGEM do aceite (nunca o do cadastro), enviar_em, o modo inicial (o orcamento_pegar decide
-- de novo ao sair) e a dedupe_key (com :sombra quando nasce em sombra).
create or replace function public.orcamento_aceite_registrar(p_aceite uuid, p_ok boolean, p_resultado jsonb, p_autor uuid,
                                                             p_pedir_dados boolean, p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_pede constant text[] := array['CPF/CNPJ', 'CPF/CNPJ incompleto', 'rua', 'bairro', 'cidade', 'UF', 'CEP', 'CEP incompleto'];
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_res jsonb := (case when jsonb_typeof(p_resultado) = 'object' then p_resultado else '{}'::jsonb end);
  v_escolha text;
  v_a public.orcamento_aceites;
  v_fone text;
  v_recebida timestamptz;
  v_dia date;
  v_modo text;
  v_modo_dados text;
  v_faltas text[];
  v_empresa boolean;
  v_pediu boolean := false;
begin
  v_escolha := v_res ->> 'escolha';
  select * into v_a from public.orcamento_aceites a where a.id = p_aceite for update;
  if not found or v_a.estado is distinct from 'detectado'
     or (v_escolha is not distinct from 'sem_sinal' and v_a.executado_em is null) then
    return jsonb_build_object('ok', false, 'motivo', 'estado');
  end if;

  if not coalesce(p_ok, false) then
    -- A ferramenta não chegou a ele: volta à lista no próximo *retorno*.
    if coalesce((v_res ->> 'adiado')::boolean, false) then
      update public.orcamento_aceites a set executado_em = null where a.id = p_aceite and a.estado = 'detectado';
      return jsonb_build_object('ok', true, 'adiado', true);
    end if;
    -- A conversão falhou: caiu, e nada vai ao cliente.
    update public.orcamento_aceites a
       set estado = 'caiu', resultado = a.resultado || v_res, decidido_em = v_agora, decidido_por = p_autor
     where a.id = p_aceite and a.estado = 'detectado';
    return jsonb_build_object('ok', true, 'caiu', true);
  end if;
  if v_escolha is null or v_escolha not in ('com_sinal', 'sem_sinal') then
    return jsonb_build_object('ok', false, 'motivo', 'escolha');
  end if;

  update public.orcamento_aceites a
     set estado = v_escolha, decidido_em = v_agora, decidido_por = p_autor, resultado = a.resultado || v_res
   where a.id = p_aceite and a.estado = 'detectado';
  perform public._orcamento_aceite_fechar_antigos(p_aceite, v_agora);

  -- O telefone de onde o cliente escreveu.
  select w.phone_normalized, coalesce(w.hora_real, w.occurred_at) into v_fone, v_recebida
    from public.whatsapp_messages w where w.id = v_a.whatsapp_message_id;
  if v_fone is null or public._agenda_chave_telefone(v_fone) is distinct from v_a.chave then
    update public.orcamento_aceites a set resultado = a.resultado || jsonb_build_object('saida_nao_saiu', 'sem_numero')
     where a.id = p_aceite;
    return jsonb_build_object('ok', true, 'fechado', null, 'dados', false, 'motivo', 'sem_numero');
  end if;
  -- E ele fala pelo cliente do aceite, conferido de novo agora (a mesma regra da detecção; o caso ou o cadastro podem ter
  -- mudado): senão o "Fechado" e o pedido de dados iriam a outra pessoa com os mesmos 8 dígitos, e nada sai.
  if public._orcamento_cliente_do_telefone(v_a.abertura_id, v_fone) is distinct from v_a.client_id then
    update public.orcamento_aceites a set resultado = a.resultado || jsonb_build_object('saida_nao_saiu', 'numero_compartilhado')
     where a.id = p_aceite;
    return jsonb_build_object('ok', true, 'fechado', null, 'dados', false, 'motivo', 'numero_compartilhado');
  end if;
  v_modo := (case when v_cfg.modo = 'ligado' and v_cfg.orcamento_modo = 'ligado' and v_cfg.aceite_modo = 'cartao' then 'ligado'
                  else 'sombra' end);
  v_dia := public._orcamento_dia_envio(v_a.service_order_id, v_a.chave, v_recebida);

  insert into public.retorno_saidas (emissor, abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo,
                                     estado, enviar_em, dados, dedupe_key)
  values ('orcamento', v_a.abertura_id, 'orc_fechado', 'retorno_orcamento', 'resposta_imediata', v_a.chave, v_fone, v_a.client_id,
          v_modo, 'agendada', v_agora,
          jsonb_build_object('aceite_id', v_a.id, 'os_id', v_a.service_order_id, 'dia_envio', to_char(v_dia, 'DD/MM')),
          'orcamento:aceite:' || v_a.id || ':fechado' || (case when v_modo = 'sombra' then ':sombra' else '' end))
  on conflict (dedupe_key) do nothing;

  -- Os dados da nota: só com o pedido do dono (C ou D), a chave ligada e alguma falta que o texto pede (só a inscrição
  -- estadual não se pede por mensagem: _orcamento_variante dá nulo).
  if coalesce(p_pedir_dados, false) and coalesce(v_cfg.dados_nota_ligado, false) then
    v_faltas := coalesce(public._orcamento_faltas_para_nota(v_a.client_id), '{}'::text[]);
    if v_faltas && c_pede then
      select c.type = 'company' into v_empresa from public.clients c where c.id = v_a.client_id;
      v_modo_dados := (case when v_modo = 'ligado' and v_cfg.dados_nota_ligado then 'ligado' else 'sombra' end);
      insert into public.retorno_saidas (emissor, abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo,
                                         estado, enviar_em, dados, dedupe_key)
      values ('orcamento', v_a.abertura_id, 'orc_dados_nota', 'retorno_orcamento', 'resposta_imediata', v_a.chave, v_fone,
              v_a.client_id, v_modo_dados, 'agendada', v_agora + interval '2 minutes',
              jsonb_build_object('aceite_id', v_a.id, 'os_id', v_a.service_order_id, 'faltas', to_jsonb(v_faltas),
                                 'documento', (case when coalesce(v_empresa, false) then 'CNPJ' else 'CPF' end)),
              'orcamento:aceite:' || v_a.id || ':dados' || (case when v_modo_dados = 'sombra' then ':sombra' else '' end))
      on conflict (dedupe_key) do nothing;
      update public.orcamento_aceites a set pedir_dados = true, faltas_nota = v_faltas where a.id = p_aceite;
      v_pediu := true;
    end if;
  end if;

  return jsonb_build_object('ok', true, 'fechado', (case when v_modo = 'ligado' then 'agendada' else 'sombra' end), 'dados', v_pediu);
end;
$$;

comment on function public.orcamento_aceite_registrar(uuid, boolean, jsonb, uuid, boolean, timestamptz) is
  'Retorno F5 (P6.1, C-ACEITE-REG): pré-condição aceite detectado (e com executado_em quando escolha = sem_sinal), senão {ok: false, motivo: estado}. p_ok falso com adiado: executado_em nulo (volta à lista); p_ok falso: caiu, nada ao cliente. p_ok verdadeiro: com_sinal ou sem_sinal (escolha), decidido_em/por, resultado, _orcamento_aceite_fechar_antigos; o telefone da mensagem fora da chave do aceite (resultado.saida_nao_saiu = sem_numero) ou que não fala pelo cliente do aceite (_orcamento_cliente_do_telefone; saida_nao_saiu = numero_compartilhado): nada sai; senão a saída orc_fechado em retorno_saidas (resposta_imediata, a chave do aceite, o telefone da mensagem do aceite, enviar_em = p_agora, modo ligado só com retorno, orcamento e aceite ligados/cartao, dedupe orcamento:aceite:<id>:fechado[:sombra], dados {aceite_id, os_id, dia_envio}); com p_pedir_dados, dados_nota_ligado e falta que o texto pede, também orc_dados_nota (+2 min, dados {aceite_id, os_id, faltas, documento}) e pedir_dados. {ok, fechado: agendada | sombra, dados}.';

revoke all on function public.orcamento_aceite_registrar(uuid, boolean, jsonb, uuid, boolean, timestamptz) from public, anon, authenticated;
grant execute on function public.orcamento_aceite_registrar(uuid, boolean, jsonb, uuid, boolean, timestamptz) to service_role;

-- ── 12. Gravar os dados lidos na ficha (letra A do item dados_nota) ─────────────────────────────────────────────────────

-- Relê a mensagem dentro da função; grava só o que está vazio, nunca sobrescreve; o audit_log diz só o campo, sem o valor.
-- Rua, bairro e cidade ficam com o dono, pela tela.
create or replace function public.orcamento_dados_gravar(p_aceite uuid, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_a public.orcamento_aceites;
  v_corpo text;
  v_doc text;
  v_cep text;
  v_rotulo text;
  v_fmt text;
  v_gravou text[] := '{}'::text[];
  v_ja text[] := '{}'::text[];
begin
  select * into v_a from public.orcamento_aceites a where a.id = p_aceite for update;
  if not found or v_a.dados_estado is distinct from 'lidos' or v_a.dados_msg_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'estado');
  end if;
  select w.body into v_corpo from public.whatsapp_messages w where w.id = v_a.dados_msg_id;
  v_doc := public._orcamento_documento_lido(v_corpo);
  v_cep := public._orcamento_cep_lido(v_corpo);

  if v_doc is not null then
    v_rotulo := (case when char_length(v_doc) = 11 then 'CPF' else 'CNPJ' end);
    v_fmt := (case when char_length(v_doc) = 11
                   then substr(v_doc, 1, 3) || '.' || substr(v_doc, 4, 3) || '.' || substr(v_doc, 7, 3) || '-' || substr(v_doc, 10, 2)
                   else substr(v_doc, 1, 2) || '.' || substr(v_doc, 3, 3) || '.' || substr(v_doc, 6, 3) || '/' || substr(v_doc, 9, 4)
                        || '-' || substr(v_doc, 13, 2) end);
    update public.clients c set cpf_cnpj = v_fmt where c.id = v_a.client_id and btrim(coalesce(c.cpf_cnpj, '')) = '';
    if found then
      v_gravou := v_gravou || v_rotulo;
      insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
      values ('clients', v_a.client_id, 'update', coalesce(p_autor::text, 'retorno-f5'), null,
              jsonb_build_object('campo', 'cpf_cnpj'), 'CPF/CNPJ gravado pelo aceite por texto');
    else
      v_ja := v_ja || v_rotulo;
    end if;
  end if;
  if v_cep is not null then
    update public.clients c set postal_code = substr(v_cep, 1, 5) || '-' || substr(v_cep, 6, 3)
     where c.id = v_a.client_id and btrim(coalesce(c.postal_code, '')) = '';
    if found then
      v_gravou := v_gravou || 'CEP'::text;
      insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
      values ('clients', v_a.client_id, 'update', coalesce(p_autor::text, 'retorno-f5'), null,
              jsonb_build_object('campo', 'postal_code'), 'CEP gravado pelo aceite por texto');
    else
      v_ja := v_ja || 'CEP'::text;
    end if;
  end if;
  update public.orcamento_aceites a set dados_estado = 'gravados' where a.id = p_aceite and a.dados_estado = 'lidos';
  return jsonb_build_object('ok', true, 'gravou', to_jsonb(v_gravou), 'ja_tinha', to_jsonb(v_ja),
                            'faltam', to_jsonb(coalesce(public._orcamento_faltas_para_nota(v_a.client_id), '{}'::text[])));
end;
$$;

comment on function public.orcamento_dados_gravar(uuid, uuid, timestamptz) is
  'Retorno F5 (P6.1): a letra A do item dados_nota. Exige dados_estado = lidos; relê a mensagem dados_msg_id, extrai documento e CEP de novo e grava no cadastro só o que está vazio (CPF 000.000.000-00, CNPJ 00.000.000/0000-00, CEP 00000-000), nunca sobrescreve; audit_log com o campo, sem o valor; dados_estado = gravados. {ok, gravou: [CPF | CNPJ, CEP], ja_tinha, faltam}.';

revoke all on function public.orcamento_dados_gravar(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.orcamento_dados_gravar(uuid, uuid, timestamptz) to service_role;
