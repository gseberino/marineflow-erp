-- Retorno rápido ao cliente, F1 (sobe em sombra na seg 16/11/2026): o canal do retorno — se o número pode
-- ouvir uma resposta automática agora — e o modo do caso, a regra que liga as saídas de um caso entre si.
-- Só funções: nenhuma tabela, nenhum dado, nenhum envio.
--
-- 1. canal_pode_enviar(fone, classe, origem, agora, simular, tipo) → {"pode", "motivo", "enviar_em"}
--    (C-CANAL; quem chama é o retorno_pegar, P6). A PRIMEIRA regra que falha decide (falha fecha):
--     1 sem a linha de configuração, ou o retorno desligado   → sem_config
--     2 classe fora de resposta_imediata/resposta_atrasada    → classe_nao_suportada (aviso, comercial e
--       parceiro são do pedido 7: classe que o canal não conhece nunca passa)
--     3 sem os 8 dígitos                                       → sem_numero
--     4 equipe (app_users ou payees ativos, mesmo DDD)         → equipe (o retorno nunca fala com a equipe)
--     5 canal_bloqueado (F0a) não nulo                         → cliente_final | bloqueado | opt_out. A única
--       exceção é a confirmação do PARAR (p_tipo 'parar' com _retorno_parar_permitido)
--     6 whatsapp_leads.lead_tipo = 'pessoal' na chave          → pessoal
--     7 segura_tudo_ate depois de agora                        → segura_tudo
--     8 disjuntor so_reativo e classe que não é a imediata     → so_reativo (só sai resposta a quem escreveu)
--     9 fora da janela da classe (_retorno_janela)             → fora_da_janela, com enviar_em = a próxima abertura
--    10 teto da HBR (respostas_dia_max, 40 por dia, B.6)       → teto_dia
--    11 proximo_envio_em depois de agora, sem simular          → espacamento, com enviar_em = proximo_envio_em
--    12 → pode.
--    Só lê. Quem reserva o espaçamento e conta os tetos por número é o retorno_pegar (P6). Todo motivo está
--    na lista fechada de retorno_saidas.motivo, porque o retorno_pegar grava o motivo como veio.
--    - O teto conta as saídas de resposta decididas entre 00:00 de Brasília e agora (nunca o futuro: o replay
--      reproduz a ordem real) em enviada, incerta ou enviando. Simulando (a saída vai em sombra), conta
--      também sombra e preparada: a simulação imita o que teria acontecido. O espaçamento não vale na
--      simulação, que não reserva nada.
--    - p_origem não muda regra nesta leva: as classes do pedido 7 é que vão usá-la.
--
-- 2. _retorno_janela(classe, agora, chave) → {"dentro", "enviar_em"}: a janela de cada classe numa fonte
--    só, para o canal (no retorno_pegar) e para a autorização (no whatsapp-send).
--    - resposta_imediata (K3): todo dia, de cliente_resposta_direta_inicio a cliente_resposta_direta_fim
--      (07:00–21:59); fora dela, a manhã de _retorno_proxima_manha (08:00, domingo e feriado 09:00,
--      espalhada em 30 min por número).
--    - resposta_atrasada (adiamento, fim do dia): seg–sex de atrasada_inicio a atrasada_fim (08:00–19:59),
--      sáb até atrasada_sabado_fim (12:59), nunca domingo nem feriado (agenda_feriado). Fora dela, o
--      próximo dia permitido às atrasada_inicio, procurando até 7 dias (sem achar: enviar_em nulo).
--
-- 3. _retorno_parar_permitido(chave, agora, exceto): a ÚNICA exceção ao bloqueio, para a confirmação do
--    PARAR (T27/T28). O opt-out que ela confirma foi gravado há no máximo 15 min (o gatilho da F0b grava na
--    hora da mensagem); a chave não tem linha de spam nem é o "Cliente Final"; e nunca houve saída parar da
--    chave em sombra, enviando, enviada ou incerta (fora p_exceto, a própria saída que está enviando).
--    PARAR fora da janela K3 não ganha confirmação: às 08:00 os 15 min já passaram (falha para o lado de
--    mandar menos). O "Cliente Final" é conferido direto em clients.generico, sem a isenção da equipe que
--    canal_bloqueado aplica: com só a chave na mão, isentar pelos 8 dígitos soltaria um estranho.
--    Sem o opt-out gravado (canal_bloqueado nulo), a confirmação também NÃO sai: "não te mando mais" seria
--    mentira. O canal devolve o motivo do bloqueio ou, sem bloqueio, 'canal'.
--
-- 4. _retorno_modo_efetivo(saída, variante, prazo, agora) → {"modo": "sombra" | "ligado", "motivo"}
--    (C-MODO; chamada pelo retorno_pegar, pelo retorno_saida_autorizada e pelo vigia no cadastro). Nenhum
--    cliente ouve um aviso sem ter ouvido a promessa, e nenhum ouve a promessa sem o aviso garantido. A
--    PRIMEIRA regra que falha dá sombra, com o motivo (vai para dados.sombra_motivo):
--     1 retorno_config.modo não é 'ligado' (ou sem a linha)    → modo
--     2 segura_tudo_ate depois de agora                        → segura_tudo
--     3 o tipo não está em tipos_ligados                       → tipo_desligado
--     4 o modelo oferece URGENTE (_retorno_oferece_urgente) e
--       'urgente' está fora de tipos_ligados                   → urgente_desligado
--     5 recibo, saudação ou coleta com segura_recibos          → segura_recibos
--     6 caso em passagem com 'acorde' fora de tipos_ligados    → passagem_sem_acorde (sem o acorde real, risco,
--       reclamação, "quero falar com o Gustavo", LGPD e caso vencido nunca ouvem só um "até as 19h").
--       Exceção: o adiamento e o fim do dia de um caso cujo RECIBO já está enviado ou incerto, decidido até
--       agora. O caso vira passagem também DEPOIS do recibo ouvido (insistências >= 2, reclamação, P5), e o
--       relógio do vigia (P6.2, passo 6) agenda o aviso em qualquer nível. Segurar esse aviso deixaria em
--       silêncio, às 19h, justamente quem mais precisa dele, e quebraria a garantia do §3 (ninguém ouve a
--       promessa sem o aviso). Só o recibo conta aqui: a saudação não promete hora, e o caso que só ouviu a
--       saudação continua preso pela passagem. É um desvio da tabela do P4.1 (regra 6), levado à sessão
--       coordenadora.
--     7 recibo_*: o caso inteiro tem de poder ligar. Com X2 (prazo.x2 não nulo, vai haver adiamento), o
--       adiamento que sairia oferece URGENTE e só liga com 'urgente'; o adiamento e o fim do dia ligados o
--       check do grupo (P1) já garante, e são conferidos de novo aqui           → caso_sem_aviso
--     8 adiamento, fim do dia, coleta, urgente ou cadastro provisório: o recibo ou a saudação DO CASO está
--       enviada ou incerta, decidida até agora (o cliente ouviu, ou pode ter ouvido) → caso_em_sombra
--     9 → ligado.
--    O parar passa só pelas regras 1–3 (não depende de recibo); a saudação, pelas 1–3, 5 e 6. Nesta leva
--    (urgente e acorde fora do check) ligam na prática: o caso de promessa 19h (recibo das 07:00 às 15:29 de
--    dia útil, sem X2), a saudação, a coleta e o cadastro provisório que vêm dele, o parar e o fim do dia
--    desse caso mesmo que ele vire passagem depois do recibo ouvido (o adiamento, que oferece URGENTE, a
--    regra 4 segura antes).
--    Na dúvida, sombra: saída que não existe (sem_saida), saída sem caso (sem_caso), recibo sem o prazo
--    gravado (caso_sem_aviso: não dá para saber se haverá adiamento) e recibo ou adiamento sem a variante
--    (urgente_desligado: a variante pode ser a que oferece URGENTE).
--
-- 5. retorno_saida_autorizada(saída, fone, agora) → {"pode", "motivo"} (C-AUTORIZA): a conferência do
--    whatsapp-send (P12) no instante do envio, sem contar de novo teto nem espaçamento (já reservados).
--    Só pode quando TODAS valem: a saída existe, é do retorno, está enviando, ligada e dentro da reserva
--    (processando_ate); o telefone é o dela (_mesmo_telefone); o modo efetivo, de novo agora, é ligado (modo
--    geral, tipo, URGENTE, segura_*, passagem sem acorde e o modo do caso); canal_bloqueado é nulo, salvo a
--    confirmação do PARAR com _retorno_parar_permitido (a própria saída não conta); e a janela da classe.
--    Qualquer exceção → {"pode": false, "motivo": "erro"}: o whatsapp-send nunca manda na dúvida.
--
-- canal_pode_enviar e retorno_saida_autorizada: SECURITY DEFINER, só o service_role. As internas
-- (_retorno_*): SECURITY DEFINER com search_path (leem retorno_config, retorno_saidas, retorno_aberturas e
-- whatsapp_blocked_numbers), revoke de public, anon e authenticated, sem grant.
--
-- Sem dado: só funções novas; nenhuma linha muda.
-- Reverter (depois das migrations seguintes da F1, que chamam estas): drop function
-- public.retorno_saida_autorizada(uuid, text, timestamptz),
-- public.canal_pode_enviar(text, text, text, timestamptz, boolean, text),
-- public._retorno_modo_efetivo(uuid, text, jsonb, timestamptz), public._retorno_parar_permitido(text, timestamptz, uuid),
-- public._retorno_janela(text, timestamptz, text).
-- Sem deploy: update public.retorno_config set modo = 'sombra' (nada sai ligado), tipos_ligados = '{}' ou
-- segura_tudo_ate = <até quando> (nada sai).

-- A janela da classe: {"dentro": true} ou {"dentro": false, "enviar_em": a próxima abertura | null}.
create or replace function public._retorno_janela(p_classe text, p_agora timestamptz, p_chave text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_cfg public.retorno_config := public._retorno_cfg();
  v_local timestamp;
  v_t time;
  v_d date;
  v_dia date;
  v_fim time;
begin
  -- Sem a linha de configuração, sem hora ou classe que a janela não conhece: fora, sem próxima abertura.
  if v_cfg.id is null or p_agora is null
     or p_classe is null or p_classe not in ('resposta_imediata', 'resposta_atrasada') then
    return jsonb_build_object('dentro', false, 'enviar_em', null);
  end if;

  v_local := p_agora at time zone c_fuso;
  v_t := v_local::time;
  v_d := v_local::date;

  if p_classe = 'resposta_imediata' then
    -- K3: todo dia, inclusive domingo e feriado; o fim é exclusivo (22:00 já está fora).
    if v_t >= v_cfg.cliente_resposta_direta_inicio and v_t < v_cfg.cliente_resposta_direta_fim then
      return jsonb_build_object('dentro', true, 'enviar_em', null);
    end if;
    return jsonb_build_object('dentro', false, 'enviar_em', public._retorno_proxima_manha(p_agora, p_chave));
  end if;

  -- resposta_atrasada: o fim da janela do dia (nulo no domingo e no feriado).
  v_fim := case
    when extract(isodow from v_d) = 7 or public.agenda_feriado(v_d) is not null then null
    when extract(isodow from v_d) = 6 then v_cfg.atrasada_sabado_fim
    else v_cfg.atrasada_fim
  end;
  if v_fim is not null and v_t >= v_cfg.atrasada_inicio and v_t < v_fim then
    return jsonb_build_object('dentro', true, 'enviar_em', null);
  end if;

  -- A próxima abertura: hoje, se ainda não deu atrasada_inicio e hoje é permitido; senão o próximo dia
  -- que não é domingo nem feriado (até 7 dias à frente).
  for i in 0 .. 7 loop
    v_dia := v_d + i;
    if extract(isodow from v_dia) <> 7 and public.agenda_feriado(v_dia) is null
       and (i > 0 or v_t < v_cfg.atrasada_inicio) then
      return jsonb_build_object('dentro', false, 'enviar_em', (v_dia + v_cfg.atrasada_inicio) at time zone c_fuso);
    end if;
  end loop;
  return jsonb_build_object('dentro', false, 'enviar_em', null);
end;
$$;

comment on function public._retorno_janela(text, timestamptz, text) is
  'Retorno F1: a janela da classe ({"dentro", "enviar_em"}). resposta_imediata: todo dia, 07:00–21:59 (K3); fora, _retorno_proxima_manha. resposta_atrasada: seg–sex 08:00–19:59, sáb 08:00–12:59, nunca domingo nem feriado; fora, o próximo dia permitido às 08:00 (até 7 dias). Classe desconhecida: fora, sem abertura.';

-- A confirmação do PARAR pode furar o bloqueio? Só a do opt-out recém-gravado, uma vez por chave.
create or replace function public._retorno_parar_permitido(p_chave text, p_agora timestamptz, p_exceto uuid default null)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(p_chave ~ '^[0-9]{8}$', false)
     -- o opt-out que a confirmação confirma, gravado há no máximo 15 min (e nunca depois de agora)
     and exists (select 1 from public.whatsapp_blocked_numbers b
                  where public._agenda_chave_telefone(b.phone_normalized) = p_chave
                    and b.tipo = 'opt_out'
                    and b.created_at <= p_agora
                    and b.created_at >= p_agora - interval '15 minutes')
     -- nenhuma outra linha da chave que não seja opt-out (a lista de spam nunca recebe nada)
     and not exists (select 1 from public.whatsapp_blocked_numbers b
                      where public._agenda_chave_telefone(b.phone_normalized) = p_chave
                        and b.tipo is distinct from 'opt_out')
     -- o "Cliente Final" (o telefone de um terceiro), sem a isenção da equipe de canal_bloqueado
     and not exists (select 1 from public.clients c
                      where c.generico
                        and p_chave in (public._agenda_chave_telefone(c.whatsapp), public._agenda_chave_telefone(c.phone)))
     -- uma confirmação por chave: nenhuma outra saída parar já decidida até agora (fora p_exceto)
     and not exists (select 1 from public.retorno_saidas s
                      where s.chave = p_chave
                        and s.tipo = 'parar'
                        and s.estado in ('sombra', 'enviando', 'enviada', 'incerta')
                        and (s.decidida_em is null or s.decidida_em <= p_agora)
                        and s.id is distinct from p_exceto);
$$;

comment on function public._retorno_parar_permitido(text, timestamptz, uuid) is
  'Retorno F1 (T27/T28): a única exceção ao bloqueio. Verdadeiro só com opt-out da chave gravado há no máximo 15 min, sem linha de spam, fora do "Cliente Final" e sem outra saída parar da chave em sombra/enviando/enviada/incerta (fora p_exceto). Chave ou hora nulas: falso.';

-- O modo do CASO para uma saída (C-MODO).
create or replace function public._retorno_modo_efetivo(p_saida uuid, p_variante text, p_prazo jsonb, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_recibos constant text[] := array['recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo'];
  v_cfg public.retorno_config := public._retorno_cfg();
  v_agora timestamptz := coalesce(p_agora, now());
  v_tipo text;
  v_caso uuid;
  v_nivel text;
begin
  -- 1. O modo geral (sem a linha de configuração = desligado: sombra).
  if v_cfg.id is null or v_cfg.modo is distinct from 'ligado' then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'modo');
  end if;

  select s.tipo, s.abertura_id into v_tipo, v_caso from public.retorno_saidas s where s.id = p_saida;
  if not found then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'sem_saida');
  end if;

  -- 2. "Segura tudo" até uma hora que ainda não chegou.
  if v_cfg.segura_tudo_ate is not null and v_cfg.segura_tudo_ate > v_agora then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'segura_tudo');
  end if;

  -- 3. O tipo ligado (urgente, acorde e fila nunca estão na lista).
  if not coalesce(v_tipo = any (v_cfg.tipos_ligados), false) then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'tipo_desligado');
  end if;

  -- O parar só passa pelas regras 1–3: não depende de recibo.
  if v_tipo = 'parar' then
    return jsonb_build_object('modo', 'ligado', 'motivo', null);
  end if;

  -- 4. O modelo oferece URGENTE, e o URGENTE não liga. Sem a variante, o recibo e o adiamento podem ser os
  --    que oferecem: na dúvida, sombra.
  if (public._retorno_oferece_urgente(v_tipo, p_variante)
      or (p_variante is null and v_tipo in ('recibo_cliente', 'adiamento')))
     and not ('urgente' = any (v_cfg.tipos_ligados)) then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'urgente_desligado');
  end if;

  -- 5. "Segura recibos": recibo, saudação e coleta.
  if v_cfg.segura_recibos and (v_tipo = any (c_recibos) or v_tipo in ('saudacao_numero_novo', 'coleta_numero_novo')) then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'segura_recibos');
  end if;

  -- 6. A passagem só liga com o acorde real. Escapa só o aviso honesto (adiamento, fim do dia) de uma
  --    promessa que o cliente já ouviu: o recibo do caso enviado ou incerto, decidido até agora. O caso pode
  --    ter virado passagem depois do recibo (insistência, reclamação), e calar às 19h seria pior.
  select a.nivel into v_nivel from public.retorno_aberturas a where a.id = v_caso;
  if not found then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'sem_caso');
  end if;
  if v_nivel = 'passagem' and not ('acorde' = any (v_cfg.tipos_ligados))
     and not (v_tipo in ('adiamento', 'fim_do_dia')
              and exists (select 1 from public.retorno_saidas r
                           where r.abertura_id = v_caso
                             and r.emissor = 'retorno'
                             and r.tipo = any (c_recibos)
                             and r.estado in ('enviada', 'incerta')
                             and r.decidida_em <= v_agora)) then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'passagem_sem_acorde');
  end if;

  -- 7. O recibo só liga se o resto do caso também puder ligar: o adiamento que viria (com X2) e o fim do dia.
  if v_tipo = any (c_recibos) then
    if p_prazo is null or jsonb_typeof(p_prazo) is distinct from 'object' or not (p_prazo ? 'x2')
       or not (v_cfg.tipos_ligados @> array['adiamento', 'fim_do_dia']::text[])
       or (p_prazo ->> 'x2' is not null
           and (public._retorno_oferece_urgente('adiamento', 'com_nome') or public._retorno_oferece_urgente('adiamento', 'sem_nome'))
           and not ('urgente' = any (v_cfg.tipos_ligados))) then
      return jsonb_build_object('modo', 'sombra', 'motivo', 'caso_sem_aviso');
    end if;
  end if;

  -- 8. O aviso só liga se o cliente ouviu (ou pode ter ouvido) o recibo ou a saudação deste caso.
  if v_tipo in ('adiamento', 'fim_do_dia', 'coleta_numero_novo', 'urgente', 'cadastro_provisorio')
     and not exists (select 1 from public.retorno_saidas r
                      where r.abertura_id = v_caso
                        and r.emissor = 'retorno'
                        and (r.tipo = any (c_recibos) or r.tipo = 'saudacao_numero_novo')
                        and r.estado in ('enviada', 'incerta')
                        and r.decidida_em <= v_agora) then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'caso_em_sombra');
  end if;

  -- 9.
  return jsonb_build_object('modo', 'ligado', 'motivo', null);
end;
$$;

comment on function public._retorno_modo_efetivo(uuid, text, jsonb, timestamptz) is
  'Retorno F1 (C-MODO): {"modo": sombra|ligado, "motivo"}. A 1ª regra que falha dá sombra: modo, segura_tudo, tipo_desligado, urgente_desligado, segura_recibos, passagem_sem_acorde (salvo o adiamento e o fim do dia de um caso com o recibo já enviado ou incerto), caso_sem_aviso (recibo com X2 sem o URGENTE), caso_em_sombra (aviso sem recibo/saudação do caso enviada ou incerta). O parar passa só por 1–3. Na dúvida (sem saída, sem caso, sem prazo, sem variante), sombra.';

revoke all on function public._retorno_janela(text, timestamptz, text) from public, anon, authenticated;
revoke all on function public._retorno_parar_permitido(text, timestamptz, uuid) from public, anon, authenticated;
revoke all on function public._retorno_modo_efetivo(uuid, text, jsonb, timestamptz) from public, anon, authenticated;

-- Pode mandar a resposta automática a este número agora? (C-CANAL)
create or replace function public.canal_pode_enviar(p_fone text, p_classe text, p_origem text,
                                                    p_agora timestamptz default now(),
                                                    p_simular boolean default false,
                                                    p_tipo text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_cfg public.retorno_config := public._retorno_cfg();
  v_agora timestamptz := coalesce(p_agora, now());
  v_simular boolean := coalesce(p_simular, false);
  v_chave text := public._agenda_chave_telefone(p_fone);
  v_bloqueio text;
  v_janela jsonb;
  v_desde timestamptz;
  v_n bigint;
begin
  -- 1. Sem a linha de configuração, ou o retorno desligado: nada sai.
  if v_cfg.id is null or v_cfg.modo = 'desligado' then
    return jsonb_build_object('pode', false, 'motivo', 'sem_config', 'enviar_em', null);
  end if;

  -- 2. Só as duas classes de resposta (as do pedido 7 nunca passam aqui).
  if p_classe is null or p_classe not in ('resposta_imediata', 'resposta_atrasada') then
    return jsonb_build_object('pode', false, 'motivo', 'classe_nao_suportada', 'enviar_em', null);
  end if;

  -- 3. Sem os 8 dígitos não há a quem mandar.
  if v_chave is null then
    return jsonb_build_object('pode', false, 'motivo', 'sem_numero', 'enviar_em', null);
  end if;

  -- 4. A equipe, pelo mesmo telefone (8 dígitos e o mesmo DDD, como em quem_escreve).
  if exists (select 1 from public.app_users u
              where u.active and (public._mesmo_telefone(p_fone, u.phone_normalized) or public._mesmo_telefone(p_fone, u.phone)))
     or exists (select 1 from public.payees p where p.active and public._mesmo_telefone(p_fone, p.phone)) then
    return jsonb_build_object('pode', false, 'motivo', 'equipe', 'enviar_em', null);
  end if;

  -- 5. Bloqueio da F0a. O parar só sai confirmando o opt-out recém-gravado (e nunca sem ele).
  v_bloqueio := public.canal_bloqueado(p_fone);
  if p_tipo = 'parar' then
    if not coalesce(public._retorno_parar_permitido(v_chave, v_agora), false) then
      return jsonb_build_object('pode', false, 'motivo', coalesce(v_bloqueio, 'canal'), 'enviar_em', null);
    end if;
  elsif v_bloqueio is not null then
    return jsonb_build_object('pode', false, 'motivo', v_bloqueio, 'enviar_em', null);
  end if;

  -- 6. O número que o dono marcou como pessoal.
  if exists (select 1 from public.whatsapp_leads l
              where l.lead_tipo = 'pessoal' and public._agenda_chave_telefone(l.phone_normalized) = v_chave) then
    return jsonb_build_object('pode', false, 'motivo', 'pessoal', 'enviar_em', null);
  end if;

  -- 7. "Segura tudo".
  if v_cfg.segura_tudo_ate is not null and v_cfg.segura_tudo_ate > v_agora then
    return jsonb_build_object('pode', false, 'motivo', 'segura_tudo', 'enviar_em', null);
  end if;

  -- 8. Disjuntor: só sai a resposta imediata a quem escreveu.
  if v_cfg.so_reativo and p_classe <> 'resposta_imediata' then
    return jsonb_build_object('pode', false, 'motivo', 'so_reativo', 'enviar_em', null);
  end if;

  -- 9. A janela da classe.
  v_janela := public._retorno_janela(p_classe, v_agora, v_chave);
  if not coalesce((v_janela ->> 'dentro')::boolean, false) then
    return jsonb_build_object('pode', false, 'motivo', 'fora_da_janela', 'enviar_em', v_janela -> 'enviar_em');
  end if;

  -- 10. O teto da HBR: as respostas decididas desde 00:00 de Brasília até agora.
  v_desde := ((v_agora at time zone c_fuso)::date)::timestamp at time zone c_fuso;
  select count(*) into v_n
    from public.retorno_saidas s
   where s.classe in ('resposta_imediata', 'resposta_atrasada')
     and s.decidida_em >= v_desde
     and s.decidida_em <= v_agora
     and (s.estado in ('enviada', 'incerta', 'enviando')
          or (v_simular and s.estado in ('sombra', 'preparada')));
  if v_n >= v_cfg.respostas_dia_max then
    return jsonb_build_object('pode', false, 'motivo', 'teto_dia', 'enviar_em', null);
  end if;

  -- 11. O espaçamento global entre saídas automáticas (a simulação não reserva, então não espera).
  if not v_simular and v_cfg.proximo_envio_em is not null and v_cfg.proximo_envio_em > v_agora then
    return jsonb_build_object('pode', false, 'motivo', 'espacamento', 'enviar_em', v_cfg.proximo_envio_em);
  end if;

  -- 12.
  return jsonb_build_object('pode', true, 'motivo', null, 'enviar_em', null);
end;
$$;

comment on function public.canal_pode_enviar(text, text, text, timestamptz, boolean, text) is
  'Retorno F1 (C-CANAL): {"pode", "motivo", "enviar_em"}. A 1ª regra que falha decide: sem_config, classe_nao_suportada, sem_numero, equipe, cliente_final/bloqueado/opt_out (salvo a confirmação do PARAR com _retorno_parar_permitido), pessoal, segura_tudo, so_reativo, fora_da_janela (com a próxima abertura), teto_dia, espacamento (com proximo_envio_em). Só lê.';

revoke all on function public.canal_pode_enviar(text, text, text, timestamptz, boolean, text) from public, anon, authenticated;
grant execute on function public.canal_pode_enviar(text, text, text, timestamptz, boolean, text) to service_role;

-- A conferência do whatsapp-send no instante do envio (C-AUTORIZA).
create or replace function public.retorno_saida_autorizada(p_saida uuid, p_fone text, p_agora timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_s public.retorno_saidas;
  v_modo jsonb;
  v_bloqueio text;
  v_janela jsonb;
begin
  begin
    select * into v_s from public.retorno_saidas s where s.id = p_saida;
    if not found then
      return jsonb_build_object('pode', false, 'motivo', 'sem_saida');
    end if;
    -- A saída reservada pelo retorno_pegar: do retorno, enviando, ligada e dentro da reserva.
    if v_s.emissor is distinct from 'retorno' then
      return jsonb_build_object('pode', false, 'motivo', 'emissor');
    end if;
    if v_s.estado is distinct from 'enviando' then
      return jsonb_build_object('pode', false, 'motivo', 'estado');
    end if;
    if v_s.modo is distinct from 'ligado' then
      return jsonb_build_object('pode', false, 'motivo', 'saida_em_sombra');
    end if;
    if v_s.processando_ate is null or v_s.processando_ate <= v_agora then
      return jsonb_build_object('pode', false, 'motivo', 'reserva_vencida');
    end if;
    -- O destino é o telefone da saída (8 dígitos e o mesmo DDD).
    if not coalesce(public._mesmo_telefone(p_fone, v_s.phone_normalized), false) then
      return jsonb_build_object('pode', false, 'motivo', 'telefone');
    end if;
    -- As mesmas regras do retorno_pegar, de novo agora.
    v_modo := public._retorno_modo_efetivo(v_s.id, v_s.variante, v_s.dados -> 'prazo', v_agora);
    if v_modo ->> 'modo' is distinct from 'ligado' then
      return jsonb_build_object('pode', false, 'motivo', coalesce(v_modo ->> 'motivo', 'modo'));
    end if;
    -- O bloqueio; a única exceção é a confirmação do PARAR (a própria saída, enviando, não conta).
    v_bloqueio := public.canal_bloqueado(p_fone);
    if v_s.tipo = 'parar' then
      if not coalesce(public._retorno_parar_permitido(v_s.chave, v_agora, v_s.id), false) then
        return jsonb_build_object('pode', false, 'motivo', coalesce(v_bloqueio, 'canal'));
      end if;
    elsif v_bloqueio is not null then
      return jsonb_build_object('pode', false, 'motivo', v_bloqueio);
    end if;
    -- A janela da classe.
    v_janela := public._retorno_janela(v_s.classe, v_agora, v_s.chave);
    if not coalesce((v_janela ->> 'dentro')::boolean, false) then
      return jsonb_build_object('pode', false, 'motivo',
        case when v_s.classe in ('resposta_imediata', 'resposta_atrasada') then 'fora_da_janela' else 'classe_nao_suportada' end);
    end if;
    return jsonb_build_object('pode', true, 'motivo', null);
  exception when others then
    -- Na dúvida, não manda.
    return jsonb_build_object('pode', false, 'motivo', 'erro');
  end;
end;
$$;

comment on function public.retorno_saida_autorizada(uuid, text, timestamptz) is
  'Retorno F1 (C-AUTORIZA): {"pode", "motivo"} para o whatsapp-send. Só pode com a saída do retorno enviando, ligada e dentro da reserva, o telefone dela, o modo efetivo ligado agora, sem bloqueio (salvo a confirmação do PARAR) e dentro da janela da classe. Não conta teto nem espaçamento (já reservados). Exceção = {"pode": false, "motivo": "erro"}.';

revoke all on function public.retorno_saida_autorizada(uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_saida_autorizada(uuid, text, timestamptz) to service_role;
