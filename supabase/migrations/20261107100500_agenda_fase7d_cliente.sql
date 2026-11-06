-- Agenda de Produção, Fase 7, etapa 7d ("onde, quando e com o bem em que estado"), pacote P6: a mensagem M11 "onde fica", ao cliente.
-- Spec: scratchpad agenda-pesquisa/spec-fase7d.md (§5.6; §6.1; §6.3; §8.3 agenda_fase7d_cliente.sql; bloco R, R2; R6.0; R6.1; R6.3-4; R6.3-5;
-- R6.7a; R6.7b; R6.8-7; R6.9-5; R6.10, que corrigem o corpo); nomes: fase7-registro.md (7d P6); respostas do dono: fase7-padroes.md (AG7-21,
-- AG7-14, AG7-18). Depende das Fases 1 a 6, do lote de 30/10, da 7a, da 7b, da 7c, do retorno F0a e de 20261107100000 a 20261107100400.
--
-- ═══ DDL — OK NOMEADO ═══ (14 funções recriadas e 5 novas; nenhuma tabela, nenhuma coluna, nenhum dado)
-- NÃO APLICADA. Existe para revisão e espera o OK do dono. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7d/p6/montar-migration.mjs:
-- cada recriada é o corpo da definição MAIS NOVA (o montador para se outra migration a definir depois da origem), e as mudanças estão só em
-- blocos "-- FASE 7d: … -- FASE 7d: fim" INSERIDOS; tirados os blocos, o corpo é o da origem, byte a byte (o montador e o K7 de
-- supabase/tests/agenda_fase7d_cliente.sql conferem). As exceções são as da própria 7d: _agenda_local_decidir, _agenda_desfazer_local, agenda_decisoes_abertas e
-- _agenda_estado_do_bem trocam uma linha cada, e _agenda_ver_decisoes troca a linha do bloco do P5.
--
-- POR QUE: 8 das 11 OS da carteira não têm lugar nenhum, e a agenda ainda não pergunta ao cliente onde o bem fica nem quem desce o barco. O M11 é a
-- ÚNICA pergunta ao cliente "onde fica e quando precisa" (R2), com o texto aprovado (AG7-21). Este é o único pacote da 7d que pode escrever a um
-- cliente real: o erro aqui não é teste vermelho, é mensagem indevida a quem já recebeu o serviço (R6.7a: pela §5.6, a OS-00130, entregue e paga,
-- receberia hoje).
--
-- O QUE MUDA:
--   1. _agenda_cliente_onde_fica: o passo da rodada do cliente. A guarda vem ANTES de qualquer cálculo: o freio (R6.7b), onde_fica_desde (R6.7a-1,
--      R6.8-7: hoje, nenhuma chamada às leituras) e os sinais de que a OS já foi feita (_agenda_cliente_ja_atendida, R6.7a-2). Monta o texto
--      antes de registrar e, acima do teto, tira {prazo}, depois {uso}; ainda acima, pula (R6.9-5).
--   2. _agenda_cliente_revalidar: na hora de sair, a OS é relida (R6.7a-3), e o M11 que perdeu o sentido fica desatualizado.
--   3. agenda_resposta_do_cliente e _agenda_cliente_anotar_onde: a resposta vira uma linha em site_access, com *desfaz*, e a pergunta local ao dono,
--      com a leitura de _agenda_local_proposto. NÃO conta como acesso combinado (R6.3-5): sem acesso_ok_em, senão a crítica de véspera nunca nasceria.
--   4. _agenda_local_decidir e o *desfaz*: o sim do dono grava o local, a situação e quem desce (fonte cliente), e não mexe no plano.
--   5. agenda_decisoes_abertas e _agenda_ver_decisoes: a local tem resposta pela conversa, como a combinar. Os outros tipos não mudam aqui.
--   6. _agenda_estado_do_bem: "perguntei ao cliente os dias de uso" só quando o M11 que saiu levava o {uso} (R6.9-5 pode tirá-lo).
--   7. Os textos, os rótulos e a lista de passos: _agenda_cliente_texto, _agenda_cliente_tipo_texto, _agenda_cliente_o_que,
--      _agenda_cliente_teria_feito, _agenda_ver_clientes e agenda_cliente_vigiar.
--
-- O QUE NÃO MUDA: cliente_tipos_ligados não recebe onde_fica: o tipo fica reconhecido e fora da lista, e nada sai (em teste, a linha "Em teste").
-- _agenda_cliente_registrar, _agenda_cliente_enfileirar e o worker não mudam. Sem onde_fica_desde, o passo não lê nada. Não toca em
-- handle_quote_deposit_payment, diárias nem recebíveis (só lê as cobranças). _agenda_cliente_dia, _agenda_nome_curto e _agenda_chave_telefone,
-- que a sessão do retorno chama, não mudam.
--
-- O FREIO (R6.7b): com *gestor, só propor*, o passo devolve {pulado: gestor_so_propor}: a porta do 1º dia confia no plano, e o plano é o que está em
-- dúvida. A pergunta local segue respondível: nasce da resposta do cliente, só grava com o sim do dono e não mexe no plano.
--
-- O BLOQUEIO DO RETORNO (R6.0): o M11 sai por _agenda_cliente_enfileirar, com source = agenda-cliente, a única fonte agenda-% que o gatilho
-- trg_whatsapp_send_queue_cliente_final olha. O K8 do teste roda a migration 20261105100000 de verdade por baixo do M11.
--
-- PROVA: supabase/tests/agenda_fase7d_cliente.sql na bancada (node scripts/bancada-agenda/rodar.mjs). APLICAR: só pelo roteiro de publicação da
-- 7d, depois da 20261107100400 e antes da 20261107100600. IDEMPOTENTE: create or replace function, revoke/grant e comment.
--
-- DESFAZER: recriar as 14 com o corpo da origem e apagar as 5 novas. Quem recriar depois uma destas copia DESTA migration (a 7e,
-- _agenda_cliente_texto; a 7f, _agenda_cliente_tipo_texto, _agenda_cliente_o_que, agenda_cliente_vigiar, agenda_resposta_do_cliente e
-- _agenda_ver_clientes). Para parar o M11 sem tirar nada: onde_fica_desde = null (R6.11).

-- ── 1. A guarda e a pergunta ──────────────────────────────────────────────────────────────────────

-- A OS já foi feita, ou está sendo? O motivo, ou null. O mesmo juízo na entrada (_agenda_cliente_onde_fica) e na saída (_agenda_cliente_revalidar).
create or replace function public._agenda_cliente_ja_atendida(p_os uuid)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case
    when so.id is null then 'os'
    when so.status = 'draft' then 'orcamento'
    when so.status in ('in_progress', 'awaiting_client', 'completed', 'invoiced') then 'status'
    when so.delivered_at is not null then 'entregue'
    when so.check_out_at is not null then 'check_out'
    when so.check_in_at is not null then 'check_in'
    when exists (select 1 from public.agenda_alocacoes a where a.service_order_id = so.id and a.resultado is not null) then 'resultado'
    when exists (select 1 from public.work_shift_os w where w.service_order_id = so.id) then 'turno'
    when so.grand_total > 0
         and (select coalesce(sum(coalesce(r.paid_amount, 0)), 0) from public.receivables r
               where r.service_order_id = so.id and r.status <> 'cancelled') >= so.grand_total then 'paga'
  end
  from (select p_os as id) x
  left join public.service_orders so on so.id = x.id;
$function$;

comment on function public._agenda_cliente_ja_atendida(uuid) is
  'Agenda de Produção (Fase 7d, P6; R6.7a-2 e -3): a OS já foi feita, ou está sendo? O motivo (orcamento, status, check_in, check_out, entregue, resultado, turno, paga) ou null. "Nenhuma coluna da OS diz o que foi feito" (R6.6): por isso os sinais são todos estes, e por isso nenhum deles sozinho pega Lenine, Vanderlei e Nelson: quem resolve as OS de antes é onde_fica_desde. paga = as cobranças vivas somam o total ou mais (total 0 não conta). Só lê. Invoker, sem grant: chamam _agenda_cliente_onde_fica e _agenda_cliente_revalidar, definer.';

-- O que o M11 ainda tem a perguntar: a classe do bem (barco ou rv) quando falta saber onde ele fica, ou null. Só chega aqui a OS que passou pela guarda.
create or replace function public._agenda_cliente_onde_falta(p_os uuid, p_hoje date)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_classe text := public._agenda_classe_de_campo(p_os) ->> 'bem';
  v_l      jsonb;
  v_sit    text;
  v_ent    date;
begin
  if v_classe is null or v_classe not in ('barco', 'rv') then
    return null;
  end if;
  v_l := public._agenda_local_resolvido(p_os, p_hoje);
  select p.bem_situacao, p.entrada_em into v_sit, v_ent from public.os_planejamento p where p.service_order_id = p_os;
  -- suposicao é falso na fonte nenhum: as duas portas contam
  if coalesce((v_l ->> 'suposicao')::boolean, false) or v_l ->> 'fonte' = 'nenhum'
     or (v_classe = 'barco' and v_sit is null)
     or (v_classe = 'rv' and v_l ->> 'tipo' like 'patio\_%' and v_ent is null) then
    return v_classe;
  end if;
  return null;
end;
$function$;

comment on function public._agenda_cliente_onde_falta(uuid, date) is
  'Agenda de Produção (Fase 7d, P6; §5.6): o que o M11 ainda tem a perguntar — a classe do bem (barco ou rv) com o local como suposição ou nenhum, com o barco sem situação dita, ou com o rv no pátio sem entrada_em; null sem nada a perguntar (ou bem de outra classe). A mesma leitura na entrada e na saída: _agenda_cliente_revalidar recusa desatualizada quando ela vira null. Lê o local: só depois da guarda. Invoker, sem grant.';

-- O passo onde_fica da rodada do cliente (M11). A guarda vem antes de qualquer cálculo, e cada OS tem o seu bloco: o registrar lança exceção.
create or replace function public._agenda_cliente_onde_fica(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  c_du_min constant int := 2;   -- §5.6: a menos disso, a véspera e o M4 perguntam o acesso
  v_modo   text := case when cf.modo_cliente = 'ligado' and 'onde_fica' = any (cf.cliente_tipos_ligados) then 'ligado' else 'sombra' end;
  r        record;
  v_motivo text;
  v_classe text;
  v_dia    date;
  v_var    text;
  v_dados  jsonb;
  v_txt    text;
  v_parte  text;
  v_envio  date;
  v_seg    date;
  v_r      jsonb;
  n_reg    int := 0;
  n_erro   int := 0;
  v_pul    jsonb := '{}'::jsonb;
begin
  -- R6.7b: a porta do 1º dia confia no plano, e com o freio o plano é o que está em dúvida
  if cf.gestor_so_propor then
    return jsonb_build_object('pulado', 'gestor_so_propor');
  end if;
  -- R6.7a-1, R6.8-7: nula = ninguém, e nenhuma leitura
  if cf.onde_fica_desde is null then
    return jsonb_build_object('registradas', 0, 'puladas', v_pul, 'erros', 0);
  end if;

  -- onde_fica_desde filtra antes do cálculo. Em ligado e em teste: nas duas portas. A OS que já tem o M11 deste modo também sai aqui: é uma por OS na vida.
  for r in
    select k.service_order_id as os, k.aprovada_em, so.client_id
      from public.os_carteira(p_hoje) k
      join public.service_orders so on so.id = k.service_order_id
     where k.aprovada_em >= cf.onde_fica_desde
       and not exists (select 1 from public.agenda_cliente_mensagens m
                        where m.service_order_id = k.service_order_id and m.tipo = 'onde_fica' and m.modo = v_modo)
     order by k.numero collate "C", k.service_order_id
  loop
    begin
      v_motivo := public._agenda_cliente_ja_atendida(r.os);
      if v_motivo is null then
        select min(a.dia) into v_dia from public.agenda_alocacoes a
         where a.service_order_id = r.os and a.estado in ('publicada', 'fixada');
        v_classe := public._agenda_cliente_onde_falta(r.os, p_hoje);
        v_motivo := case
          -- o plano diz que já começou (ou começa hoje): a porta da aprovação não pergunta "para eu deixar encaminhado" a esse cliente
          when v_dia <= p_hoje then 'plano_comecou'
          when v_classe is null then 'nada_a_perguntar'
          when not (r.aprovada_em >= p_hoje - cf.onde_fica_janela_dias
                    or coalesce(v_dia <= p_hoje + cf.onde_fica_antes_dias and public.agenda_du_entre(p_hoje, v_dia) > c_du_min, false))
            then 'fora_da_janela'
        end;
      end if;
      if v_motivo is null then
        -- R6.9-5: o registrar LANÇA acima do teto. O texto aprovado sem uma parte opcional, sem palavra nova
        v_var := case when v_classe = 'barco' then 'barco' else 'motorhome' end;
        v_dados := jsonb_build_object('chave', 'unica',
          'primeira', (public._agenda_cliente_contexto(r.os, p_hoje) ->> 'primeira')::boolean,
          'uso', v_classe = 'rv' or extract(month from p_hoje)::smallint = any (cf.temporada_meses),
          'prazo', v_classe = 'barco'
                   and not exists (select 1 from public.os_planejamento p where p.service_order_id = r.os and p.precisa_ate is not null));
        v_txt := public._agenda_cliente_texto('onde_fica', v_var, r.os, v_dados, p_hoje);
        foreach v_parte in array array['prazo', 'uso'] loop
          exit when public._agenda_cliente_texto_proibido(v_txt) is distinct from 'tamanho';
          if (v_dados ->> v_parte)::boolean then
            v_dados := v_dados || jsonb_build_object(v_parte, false);
            v_txt := public._agenda_cliente_texto('onde_fica', v_var, r.os, v_dados, p_hoje);
          end if;
        end loop;
        if public._agenda_cliente_texto_proibido(v_txt) = 'tamanho' then
          v_motivo := 'tamanho';
        end if;
      end if;
      if v_motivo is null then
        -- O M11 cede o dia: o teto recusa de vez (a chave do M1 é a do dia, a do M11 é única), e nenhuma das duas volta. Quem cede é o M11, que tenta de novo no
        -- tique seguinte. Conta também o que ainda não entrou na fila; a mesma regra do mesmo tipo em 24 h, que a revalidação recusaria.
        v_envio := (public._agenda_cliente_quando(hashtext(r.os::text), p_agora, p_agora) at time zone 'America/Sao_Paulo')::date;
        v_seg := date_trunc('week', v_envio)::date;
        if (select count(*) from public.agenda_cliente_mensagens m
             where m.client_id = r.client_id and m.modo = 'ligado'
               and m.estado in ('registrada', 'aguardando_dono', 'enfileirada', 'enviada', 'respondida', 'sem_resposta')
               and (m.enviar_em at time zone 'America/Sao_Paulo')::date = v_envio) >= cf.cliente_dia_max
           or public._agenda_cliente_no_periodo(r.client_id, v_seg, v_seg + 6, null) >= cf.cliente_semana_max
           or exists (select 1 from public.agenda_cliente_mensagens m
                       where m.client_id = r.client_id and m.tipo = 'onde_fica' and m.enviada_em is not null
                         and m.enviada_em > p_agora - make_interval(hours => cf.cliente_mesmo_tipo_horas)) then
          v_motivo := 'cliente_ja_tem_mensagem';
        end if;
      end if;
      if v_motivo is null then
        v_r := public._agenda_cliente_registrar('onde_fica', v_var, r.os, null, v_dados, p_agora, null, 'rodada', null, p_agora);
        if coalesce((v_r ->> 'criada')::boolean, false) then
          n_reg := n_reg + 1;
        else
          v_motivo := coalesce(v_r ->> 'motivo', v_r ->> 'modo', 'nao_criada');
        end if;
      end if;
      if v_motivo is not null then
        v_pul := v_pul || jsonb_build_object(v_motivo, coalesce((v_pul ->> v_motivo)::int, 0) + 1);
      end if;
    exception when others then
      perform public._agenda_cliente_erro_da_os('onde_fica', r.os, sqlstate, sqlerrm, p_hoje);
      n_erro := n_erro + 1;
    end;
  end loop;
  return jsonb_build_object('registradas', n_reg, 'puladas', v_pul, 'erros', n_erro);
end;
$function$;

comment on function public._agenda_cliente_onde_fica(date, timestamptz) is
  'Agenda de Produção (Fase 7d, P6; §5.6; R6.3-4; R6.7a; R6.7b; R6.8-7; R6.9-5): o passo onde_fica da rodada do cliente, o M11 — com o freio, {pulado: gestor_so_propor}; sem onde_fica_desde, nada; entra só OS com aprovada_em >= onde_fica_desde, nas duas portas e em teste, sem chamar nenhuma leitura para as outras. Tira a OS _agenda_cliente_ja_atendida (motivo dela), o plano que já começou ou começa hoje (plano_comecou), o que já foi dito (nada_a_perguntar) e o que não está nas portas de tempo (fora_da_janela): aprovada há até onde_fica_janela_dias, ou com o 1º dia vigente, reserva inclusive, em até onde_fica_antes_dias e a mais de 2 dias úteis. Monta o texto antes de registrar: acima do teto, tira {prazo}, depois {uso}; ainda acima, tamanho. Cede o dia (cliente_ja_tem_mensagem) quando o cliente já tem mensagem nesse dia, mesmo ainda não enfileirada, ou o teto da semana, ou outro M11 em cliente_mesmo_tipo_horas: tenta de novo no tique seguinte. Registra por _agenda_cliente_registrar (chave unica, uma por OS na vida; p_alvo = p_agora). Cada OS no seu bloco (_agenda_cliente_erro_da_os). {registradas, puladas: {motivo: n}, erros}. Definer, sem grant: só agenda_cliente_vigiar a chama.';

-- A leitura por regra do que o cliente disse: nada aqui grava, e as datas não são lidas (elas vão ao dono no texto).
create or replace function public._agenda_local_proposto(p_os uuid, p_trecho text, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_t    text := public._agenda_normal(normalize(coalesce(p_trecho, ''), nfc));
  v_ids  uuid[];
  l      public.agenda_locais;
  v_sit  text;
  v_quem text;
begin
  select coalesce(array_agg(x.id), '{}'::uuid[]) into v_ids
    from public.agenda_locais x
   where x.ativo
     and exists (select 1 from unnest(x.apelidos || x.nome) a(t)
                  where char_length(public._agenda_normal(normalize(a.t, nfc))) >= 3
                    and v_t ~ ('\m' || public._agenda_normal(normalize(a.t, nfc)) || '\M'));
  if cardinality(v_ids) = 1 then
    select * into l from public.agenda_locais x where x.id = v_ids[1];
  end if;

  -- \M também: "fico no aguardo" não é água, "secador" não é seco
  if v_t ~ '\m(agua|molhad\w*|pier|flutuante)\M' then
    v_sit := 'agua';
  elsif v_t ~ '\m(garagem|hangar|empilhadeira|vaga seca|seco|seca|em terra|carreta)\M' then
    -- o local que o cliente disse manda, mesmo sem a garagem dita: o da OS é outro lugar
    v_sit := case when coalesce(case when l.id is not null then l.tem_garagem_seca
                                     else (select x.tem_garagem_seca from public.agenda_locais x
                                            where x.id = (public._agenda_local_resolvido(p_os, p_hoje) ->> 'local_id')::uuid) end, false)
                  then 'garagem_seca' else 'seco' end;
  elsif v_t ~ '\m(patio|com voces|levo|trago|deixo ai)\M' then
    v_sit := 'patio';
  end if;

  v_quem := case when v_t ~ '\mmarinheiro\M' then 'o marinheiro'
                 when v_t ~ '\m(a marina|o pessoal da marina|marina desce)\M' then 'a marina'
                 when v_t ~ '\m(eu (mesmo )?desco|eu levo)\M' then 'o cliente' end;

  return jsonb_build_object('local_id', l.id, 'local_nome', l.nome, 'situacao', v_sit, 'descer_quem', v_quem,
    'entendi', nullif(concat_ws(', ', l.nome,
                                case v_sit when 'agua' then 'na água' when 'seco' then 'em seco' when 'garagem_seca' then 'em seco (garagem)'
                                           when 'patio' then 'no pátio' end,
                                'quem desce: ' || v_quem), ''));
end;
$function$;

comment on function public._agenda_local_proposto(uuid, text, date) is
  'Agenda de Produção (Fase 7d, P6; §5.6): a leitura por regra do que o cliente respondeu ao M11, sem IA. Local: o nome ou um apelido (3 letras ou mais) de exatamente UM local ativo, palavra inteira; nenhum ou mais de um = null. Situação: agua; garagem_seca quando o local (o dito, senão o resolvido) tem garagem seca, senão seco; patio. Quem desce: o marinheiro, a marina, o cliente. Datas: não lê. {local_id, local_nome, situacao, descer_quem, entendi} ("Marina Itajaí, em seco (garagem), quem desce: a marina", ou null). Nada grava. Invoker, sem grant: quem chama é _agenda_cliente_anotar_onde.';

-- A resposta do cliente ao M11: a linha em site_access (a mesma de _agenda_cliente_anotar_acesso, mas SEM acesso_ok_em, R6.3-5) e a pergunta local ao dono.
create or replace function public._agenda_cliente_anotar_onde(p_msg uuid, p_resposta uuid, p_trecho text, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_validade constant interval := interval '7 days';   -- §5.6: a pergunta local some em 7 dias
  m       public.agenda_cliente_mensagens%rowtype;
  x       jsonb;
  v_prop  jsonb;
  v_os    uuid;
  v_nome  text;
  v_bem   text;
  v_disse text;
  v_antes text;
  v_dep   text;
  v_linha text;
  v_ok    timestamptz;
  v_txt   text;
  v_acao  uuid;
  v_perg  uuid;
  v_q     text;
  v_opc2  jsonb := jsonb_build_object('n', 2, 'texto', 'Não gravo, eu te digo como é', 'efeito', jsonb_build_object('local', 'nada'));
begin
  select * into m from public.agenda_cliente_mensagens where id = p_msg;
  v_os := m.service_order_id;
  x := public._agenda_cliente_contexto(v_os, p_hoje);
  v_nome := coalesce(x ->> 'nome', 'cliente');
  v_bem := regexp_replace(regexp_replace(x ->> 'bem', '^seu ', 'o '), '^sua ', 'a ');   -- ao dono: "o veleiro", "a lancha", "o Brisa"
  v_disse := public._agenda_corta(btrim(coalesce(p_trecho, '')), 200);

  -- R6.3-5: a linha e a ação de sempre, com efeito anotou_acesso (o *desfaz* já conhece). acesso_ok_em NÃO muda: antes e depois levam o valor de antes.
  -- Se contasse, gravaria o acesso por cliente_acesso_validade_dias, e a crítica de véspera nunca nasceria.
  select so.site_access into v_antes from public.service_orders so where so.id = v_os for update;
  v_linha := format('Cliente (%s): %s', to_char(p_hoje, 'DD/MM'), left(btrim(coalesce(p_trecho, '')), 300));
  v_dep := case when coalesce(v_antes, '') = '' then v_linha else v_antes || E'\n' || v_linha end;
  update public.service_orders set site_access = v_dep where id = v_os;
  select pl.acesso_ok_em into v_ok from public.os_planejamento pl where pl.service_order_id = v_os;
  v_txt := format('Anotei o que %s disse sobre onde fica %s: "%s".', v_nome, v_bem, v_disse);
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto,
                                   motivo, desfazivel_ate)
  values (clock_timestamp(), p_hoje, true, 'cliente', 'cliente', v_os, array[v_os],
          jsonb_build_object('site_access', v_antes, 'acesso_ok_em', v_ok),
          jsonb_build_object('efeito', 'anotou_acesso', 'resposta_id', p_resposta, 'mensagem_id', m.id,
                             'site_access', v_dep, 'acesso_ok_em', v_ok, 'linha', v_linha),
          public._agenda_corta(v_txt, 400), 'o cliente disse onde fica', p_agora + cf.desfazer_validade)
  returning id into v_acao;

  -- A pergunta ao dono: o vínculo com o local nunca é gravado sem ele
  v_prop := public._agenda_local_proposto(v_os, p_trecho, p_hoje);
  if v_prop ->> 'entendi' is not null then
    v_q := format('%s respondeu onde fica %s: "%s". Entendi: %s. 1) Gravo assim (recomendo); 2) Não gravo, eu te digo como é.',
                  v_nome, v_bem, v_disse, v_prop ->> 'entendi');
  else
    v_q := format('%s respondeu onde fica %s: "%s". Não achei esse lugar no cadastro. Me diga onde é, por exemplo: "%s".', v_nome, v_bem, v_disse,
                  case when m.variante = 'barco' then format('o barco de %s está na Marina Itajaí, em seco', v_nome)
                       else format('o motorhome de %s chega dia 5', v_nome) end);
  end if;
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, texto, opcoes, recomendacao, modo, criada_em, expira_em)
  values ('local', 'local:' || v_os, v_os, array[v_os], left(public._agenda_corta(v_q, 600), 600),
          case when v_prop ->> 'entendi' is not null
               then jsonb_build_array(jsonb_build_object('n', 1, 'texto', 'Gravo assim', 'efeito', jsonb_build_object('local', 'gravar',
                      'item', (v_prop - 'entendi') || jsonb_build_object('cliente', v_nome, 'bem', v_bem))), v_opc2)
               else jsonb_build_array(v_opc2) end,
          case when v_prop ->> 'entendi' is not null then 1 end, 'ligado', p_agora, p_agora + c_validade)
  on conflict (chave, modo) where estado = 'aberta' do nothing
  returning id into v_perg;
  if v_perg is null then
    select q.id into v_perg from public.agenda_perguntas q where q.chave = 'local:' || v_os and q.modo = 'ligado' and q.estado = 'aberta';
  end if;

  -- O bem_livre do 7a: o dono deixa de esperar (R2)
  update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'o cliente respondeu onde fica'
   where chave = 'bem_livre:' || v_os and estado = 'aberta';

  return jsonb_build_object('ok', true, 'acao_id', v_acao, 'pergunta_id', v_perg, 'texto', public._agenda_corta(v_txt, 400));
end;
$function$;

comment on function public._agenda_cliente_anotar_onde(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 7d, P6; §5.6; §6.3; R2; R6.3-5): a resposta do cliente ao M11 — uma linha nova no fim de service_orders.site_access ("Cliente (31/10): <até 300>") e a ação cliente com efeito anotou_acesso, desfazível, SEM tocar em acesso_ok_em (antes e depois levam o valor de antes: a resposta é só anotada e não conta como acesso combinado; _agenda_cliente_anotar_acesso não é chamada); a pergunta local (não crítica; chave local:<os>; some em 7 dias) com a leitura de _agenda_local_proposto, opções 1 "Gravo assim", recomendada, e 2; sem nada entendido, só a opção 2 e o pedido "me diga onde é"; e a pergunta bem_livre:<os> do 7a, se aberta, fica resolvida ("o cliente respondeu onde fica"). O plano não muda. {ok, acao_id, pergunta_id, texto}. Invoker, sem grant: quem chama é agenda_resposta_do_cliente, definer.';

-- ── 2. Os textos e o que a rodada faz ─────────────────────────────────────────────────────────────

-- _agenda_cliente_texto (de 20261029100700_agenda_fase6_acabamento.sql)
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
  'Agenda de Produção (Fase 5): a mensagem-modelo ao cliente (spec §6.1), pronta, com os dados do banco — tipos confirmar (M1: primeira, seguinte, unico; nula = primeira ou seguinte pelo contexto), vespera (M2), acesso (M4), material_chegou (M3), pode_atrasar (M6: peca, execucao, remarcado), nova_data (M7), andamento (M5: primeiro_dia, semanal), pronto e pronto_lembrete (M8), pos_servico (M9) e mudanca_no_dia (M10: clima, equipe, geral). p_dados = o que o passo calculou (envio, primeira, dia, fim, janela, n, n_feitos, quando, faixa_de/ate, peca_de/ate, dito_de/ate ou dia_dito); o que faltar sai do contexto (_agenda_cliente_contexto). Assinatura só na 1ª mensagem. Lança 22023 com o tipo ou a variante que não existe e quando falta um dado; nunca devolve texto pela metade. CORREÇÃO FASE 5 (C2): (item 12) p_dados.saudacao ("Bom dia" | "Boa tarde"; padrão "Bom dia") abre a véspera, o acesso e o M10 de chuva; (item 6) p_dados.forma = fim no M6 remarcado com o mesmo início ("{nome}, {servico} vai precisar de mais um dia: agora fica de {dia} até {fim}. Desculpe pela mudança. Pode ser? Responda SIM ou me diga outro dia."); (item 8) M6 peca_sem_data, sem data ("{nome}, quero te avisar com antecedência: ainda faltam peças {d}o serviço sem data de chegada, então {servico}, que estava {dito}, vai atrasar. Te digo a nova data assim que elas chegarem. Se isso atrapalhar algum plano seu, me diga."). FASE 6 (P7, spec-fase6 §6.1): a forma fim diz quantos dias o fim andou ("{nome}, {servico} vai terminar um dia depois do previsto: agora fica de {dia} até {fim}. …"; n ≥ 2: "… vai terminar {n} dias depois do previsto: …"; n = agenda_du_entre(dito_ate, fim); n < 1 = 22023); a peça sem data sem a repetição ("{nome}, quero te avisar com antecedência: ainda faltam peças sem data de chegada, então {servico}, que estava {dito}, vai atrasar. …"). Os dois textos novos ao cliente esperam o OK do dono antes de ligar. FASE 7d (P6, §6.1, AG7-21): o M11 onde_fica, variantes barco e motorhome, com p_dados.uso e p_dados.prazo; abre com o nome (com a assinatura na 1ª mensagem); o dia não é exigido. Texto aprovado; qualquer palavra fora da §6.1 volta a pedir o OK do dono.';

-- _agenda_cliente_tipo_texto (de 20261028100200_agenda_fase5_envio.sql)
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
    when 'mudanca_no_dia' then 'mudança no dia'
  end;
$function$;

comment on function public._agenda_cliente_tipo_texto(text) is
  'Agenda de Produção (Fase 5, P2): o tipo da mensagem ao cliente como o dono lê ("confirmação", "véspera", "aviso de atraso", "ficou pronto"…). FASE 7d (P6): onde_fica = "onde fica o bem".';

-- _agenda_cliente_o_que (de 20261028100200_agenda_fase5_envio.sql)
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
    when 'mudanca_no_dia' then 'a mudança do dia' || coalesce(' (novo dia: ' || public._dia_curto(p_dia) || ')', '')
  end;
$function$;

comment on function public._agenda_cliente_o_que(text, date) is
  'Agenda de Produção (Fase 5, P2): o que a mensagem ao cliente diz, como o dono lê na linha do que mudou sozinho ("Mandei ao Nelson a confirmação de qui 05/11."). FASE 7d (P6): onde_fica = "a pergunta de onde fica o bem" (quem chama põe o verbo e o nome: "Em teste: eu teria mandado para Nelson a pergunta de onde fica o bem").';

-- _agenda_cliente_revalidar (de 20261028100800_agenda_fase5_correcao_rodada.sql)
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
    if public._agenda_cliente_ja_atendida(m.service_order_id) is not null then
      return 'status';
    end if;
    if public._agenda_cliente_onde_falta(m.service_order_id, v_hoje) is null then
      return 'desatualizada';
    end if;
  end if;
  -- FASE 7d: fim
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
  'Agenda de Produção (Fase 5, P2): a mensagem ao cliente ainda vale em p_agora? null = sai; senão, na ordem: opt_out (_agenda_cliente_sem_mensagem); status (OS cancelada/rascunho; confirmar, véspera, acesso, material chegou, nova data e mudança no dia com a OS aguardando peça, aguardando o cliente ou concluída; andamento fora de in_progress; pronto e lembrete fora de completed ou já entregue; pós-serviço fora de completed; aviso de atraso com a OS concluída); data_mudou (o próximo dia do plano — sem plano no registro, o dia agendado da OS — ≠ base.dia_alvo; no andamento e no atraso da execução, o último dia ≠ base.fim); material (data firme com algum crítico fora de A, os_prontidao); passou_da_data (aviso de atraso com o prometido_ate antes de hoje); mesmo_tipo_24h (outra do mesmo tipo a ele enviada nas últimas cliente_mesmo_tipo_horas); desatualizada (_agenda_cliente_texto com os dados do registro, a 1ª mensagem de base e o dia do envio de agora ≠ o texto registrado, ou o modelo que não fecha mais). STABLE, definer, sem grant (o pode_sair do worker e as travas a chamam). CORREÇÃO FASE 5 (C1, item 13): depois do opt_out, sem_conversa (o d10: _agenda_cliente_conversou em p_agora; sem telefone válido, sem_telefone) — vale também no gatilho da fila e no pode_sair. CORREÇÃO FASE 5 (C2): (item 24) a OS faturada vale como concluída; (item 6) o M6 remarcado na forma fim também recusa data_mudou quando o último dia ≠ base.fim; (item 7) a data firme do dono (origem dono, base.dados.firme_do_dono) não passa pelo passo 4 (material). FASE 7d (P6; R6.7a-3, §5.6): onde_fica é relida na hora de sair — status com _agenda_cliente_ja_atendida (in_progress, awaiting_client, completed, faturada, entregue, check-in, check-out, resultado, turno, paga) e desatualizada com _agenda_cliente_onde_falta nula (o local e a situação já ditos).';

-- agenda_cliente_vigiar (de 20261028100300_agenda_fase5_rodada.sql)
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
  'Agenda de Produção (Fase 5, P3): a rodada da mensagem ao cliente, a cada 15 min, pelo task-automations (depois da vigia, antes das regras). Antes de tudo, em qualquer modo, o passo fila (_agenda_cliente_fila). modo_cliente desligado = {rodou: false}. Passos, cada um no seu bloco (o que falha vai para app_error_logs, context agenda, action cliente:<passo>, e os outros rodam): material (o material chegou M3 / a nova data M7), mudanca_no_dia (M10, ou o acorde sem decisão), confirmar (a confirmação M1 em D − cliente_confirmar_du dias úteis, a véspera M2 ou o acesso M4 no último dia de janela antes de D, ou um toque só), atraso (o aviso M6 no 1º tique a partir de cliente_hora_preparo, ou na hora com o prometido a até cliente_atraso_na_hora_du dias úteis; nunca depois da data: cliente_aviso passou; 2º atraso e atraso longo = pergunta crítica), andamento (M5), pronto (M8 e o lembrete), pos_servico (M9), sem_resposta (a pergunta cliente_resposta). Tudo pelo _agenda_cliente_registrar (o modo, a aprovação dos primeiros dias, as travas). Uma linha em agenda_vigia_rodadas (rotina = cliente). {rodou, modo, tipos_ligados, contagens, erros, falhas, acordes} — os acordes só com a vigia ligada, na cota acordes_dia_max. Só service_role. FASE 7d (P6, §5.6): o passo onde_fica (M11), depois de pronto e antes de pos_servico: o teto de 1 por dia recusa de vez quem chega por último, e quem cede é o M11.';

-- ── 3. A resposta ─────────────────────────────────────────────────────────────────────────────────

-- agenda_resposta_do_cliente (de 20261029100700_agenda_fase6_acabamento.sql)
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
    -- o PARAR, a reclamação, a negociação e o acordo seguem o caminho de sempre, abaixo
    elsif m.tipo = 'onde_fica' and v_int not in ('opt_out', 'disputa', 'negociacao', 'acordo') then
      v_x := public._agenda_cliente_anotar_onde(m.id, v_rid, v_trecho, v_hoje, p_agora);
      v_efeito := 'anotou_acesso';
      v_acao := (v_x ->> 'acao_id')::uuid;
      v_perg := (v_x ->> 'pergunta_id')::uuid;
      v_texto := v_x ->> 'texto';
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
  'Agenda de Produção (Fase 5, P4): a mensagem do cliente que chega pelo WhatsApp (o webhook chama depois da equipe e antes da confirmação de 30/09 e da conferência do recibo: o "ok" tem um dono só). modo_cliente desligado, número de ninguém (ou do dono, da equipe, de quem recebe diária), a mesma mensagem de novo ou sem mensagem da agenda esperando resposta (a última dos tipos que esperam, enviada dentro de cliente_resposta_validade e ainda sem resposta; em teste, a que teria saído) = consumiu false. Em teste: registra a resposta (efeito sombra, com a intenção) e consumiu false. Ligado, a 1ª que vale: duas OS ou dois clientes no número = ambígua (ao dono); áudio e mídia ao dono (o áudio NUNCA confirma); o SIM curto (_e_concordancia) confirma o M1/M3/M7/M10 e o M6 remarcado (_agenda_cliente_confirmar_dia: fixa o dia, com *desfaz*), registra a véspera e o acesso, é ciência no aviso de atraso, vai ao dono no "ficou pronto" e não faz nada no pós-serviço; opt-out = as vivas recusadas (opt_out) e o cadastro marcado, calado; reclamação (na hora, por acorde), negociação, acordo e pergunta ao dono; o dia pedido (data) e o recusado (remarcar, falta) — só nas mensagens que propõem um dia e com modo_proposta ligado — viram o "não antes de" e o bem indisponível com o replano (_agenda_cliente_pedido_de_dia, com *desfaz*; o dia combinado em até 1 dia útil = acorde); o dia passado, de hoje, o mesmo ou mais cedo que o combinado vai ao dono; o acesso dito vai para o campo da OS (_agenda_cliente_anotar_acesso, com *desfaz*); o resto ao dono. Ao dono = a pergunta cliente_resposta:<resposta> (some em 7 dias). A mensagem fica respondida (resposta_id) e a pergunta do "não respondeu" dela se resolve. O efeito que falha vai ao dono e a app_error_logs (cliente:resposta). {consumiu, modo, efeito, intencao, texto, resposta_id, mensagem_id, acao_id, pergunta_id}. Só service_role. CORREÇÃO FASE 5 (C1): (A1) a resposta só é da agenda quando a última mensagem da HBR ao número é a dela — o botão antigo ou outra mensagem outbound depois dela (_agenda_cliente_outra_conversa) = {consumiu:false, motivo:outra_conversa}, em teste também; (item 2) o opt-out vale para quem recebeu mensagem da agenda em 30 dias, mesmo sem mensagem esperando, depois de outra conversa ou com o número ambíguo (efeito opt_out, consumiu true); (item 16) o acesso com negação vai ao dono; (item 17) falta/remarcar com um número de dia não entendido vai ao dono; (item 9) o dia pedido ou o fim do recusado a mais de cliente_pedido_max_du dias úteis do combinado vai ao dono. CORREÇÃO FASE 5 (C2, item 15): o texto devolvido (o da pergunta cliente_resposta ao dono) sem artigo antes do nome. FASE 6 (P7, spec-fase6 §6.4): a ação do opt-out sem artigo e sem "a ele" ("Nelson pediu para não receber mais mensagens: não mando mais nada."), a ambígua escrita já sem artigo ("Chegou "ok" do número de Kalmar, mas há 2 serviços esperando resposta do cliente: …"), o motivo da pergunta do "não respondeu" ("Nelson respondeu."); a pergunta ao dono sai sem "ele" pelo ralo ("não entendi o pedido", "o dia pedido já passou ou é hoje", "combine a entrega com o cliente"); as ações do SIM, do dia pedido e do acesso vêm sem artigo das funções delas. FASE 7d (P6; §5.6, R6.3-5): o M11 onde_fica espera resposta; a resposta de texto que não é PARAR, reclamação, negociação nem acordo vai a _agenda_cliente_anotar_onde (efeito anotou_acesso, a pergunta local ao dono), e NÃO conta como acesso combinado: acesso_ok_em não muda.';

-- _agenda_cliente_teria_feito (de 20261029100700_agenda_fase6_acabamento.sql)
create or replace function public._agenda_cliente_teria_feito(p_intencao text, p_dia date)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
    -- FASE 7d: (7d P6, §5.6) a resposta ao M11 em teste (_agenda_ver_clientes passa onde_fica: a intenção da resposta não diz a qual mensagem ela é)
    when p_intencao = 'onde_fica' then 'eu teria anotado onde fica e perguntado a você'
    -- FASE 7d: fim
    when p_intencao = 'confirma' then 'eu teria confirmado' || coalesce(' ' || public._dia_curto(p_dia), '')
    when p_intencao in ('remarcar', 'falta', 'data') then 'eu teria tirado o dia e replanejado'
    when p_intencao = 'acesso' then 'eu teria anotado o acesso na OS'
    -- FASE 6: (P7) sem "a ele" (spec-fase6 §6.4); o "when" de antes, logo abaixo, não é mais alcançado
    when p_intencao = 'opt_out' then 'eu teria parado as mensagens'
    -- FASE 6: fim
    when p_intencao = 'opt_out' then 'eu teria parado as mensagens a ele'
    else 'eu teria passado a você' end;
$function$;

comment on function public._agenda_cliente_teria_feito(text, date) is
  'Agenda de Produção (Fase 5, P5): o que a agenda teria feito com uma resposta do cliente em teste ("eu teria confirmado ter 03/11", "eu teria tirado o dia e replanejado", "eu teria passado a você"). FASE 6 (P7, spec-fase6 §6.4): "eu teria parado as mensagens" (sem "a ele"). FASE 7d (P6, §5.6): onde_fica = "eu teria anotado onde fica e perguntado a você".';

-- _agenda_ver_clientes (de 20261029100700_agenda_fase6_acabamento.sql)
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
  'Agenda de Produção (Fase 5, P5): agenda_ver foco clientes (*agenda clientes*) — as mensagens ao cliente em blocos: "Esperando você" (a mensagem que espera *manda cliente*/*segura cliente*, INTEIRA; o aviso de atraso que é decisão; a data dita que passou sem aviso; a resposta que foi ao dono), "Vou mandar (hoje e amanhã)", "Mandei (7 dias)", "Em teste, eu teria mandado" (a sombra), "Responderam (7 dias)" com o efeito (em teste: o que eu teria feito), "Sem resposta" e "Não consigo mandar" (sem telefone, opt-out, sem conversa no último ano, tipos ainda em teste). Com p_os, só dela, mais o que foi dito (prometido_*) e a confirmação. modo_cliente desligado = "As mensagens ao cliente estão desligadas". Até texto_max, cortado por linha. A hora de agora: agenda.agora (a bancada), senão now(). Definer (lê a fila e as respostas): com login, só administrador e financeiro (42501). {ok, texto, dados:{esperando, vou_mandar, mandei, em_teste, responderam, sem_resposta, nao_consigo, modo, os}}. FASE 6 (P7, spec-fase6 §6.4): sem artigo antes do nome e sem "ele" ("O que foi dito ao cliente: …", "O cliente confirmou …", "• Em teste: Nelson respondeu …", "o aviso de atraso de Nelson espera você …"). FASE 7d (P6, §5.6): onde_fica na lista dos tipos ("Ainda em teste (não saem): onde fica o bem."), e a resposta ao M11 diz o que houve, não "o acesso".';

-- ── 4. A decisão do dono (copiadas de 20261107100400: o tipo local entra) ─────────────────────────

-- _agenda_local_restaurar (de 20261107100400_agenda_fase7d_combinar.sql)
create or replace function public._agenda_local_restaurar(p_acao uuid, p_autor uuid, p_agora timestamptz)
 returns boolean
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  a  public.agenda_acoes%rowtype;
  pl public.os_planejamento%rowtype;
begin
  select * into a from public.agenda_acoes where id = p_acao;
  select * into pl from public.os_planejamento where service_order_id = a.service_order_id for update;
  if not found then
    return false;
  end if;
  if (a.antes ? 'acesso_ok_em' and pl.acesso_ok_em is distinct from (a.depois ->> 'acesso_ok_em')::timestamptz)
     or (a.antes ? 'reserva_marina_ok_em' and pl.reserva_marina_ok_em is distinct from (a.depois ->> 'reserva_marina_ok_em')::timestamptz)
     or (a.antes ? 'descida_ok_em' and pl.descida_ok_em is distinct from (a.depois ->> 'descida_ok_em')::timestamptz)
     or (a.antes ? 'entrada_em' and pl.entrada_em is distinct from (a.depois ->> 'entrada_em')::date)
     -- FASE 7d: (7d P6, §5.6) as colunas do que o cliente disse
     or (a.antes ? 'local_id' and pl.local_id is distinct from (a.depois ->> 'local_id')::uuid)
     or (a.antes ? 'bem_situacao' and pl.bem_situacao is distinct from a.depois ->> 'bem_situacao')
     or (a.antes ? 'descer_quem' and pl.descer_quem is distinct from a.depois ->> 'descer_quem')
     -- FASE 7d: fim
     or (a.antes ? 'nao_antes_de' and pl.nao_antes_de is distinct from (a.depois ->> 'nao_antes_de')::date) then
    return false;
  end if;
  update public.os_planejamento p
     set acesso_ok_em = case when a.antes ? 'acesso_ok_em' then (a.antes ->> 'acesso_ok_em')::timestamptz else p.acesso_ok_em end,
         reserva_marina_ok_em = case when a.antes ? 'reserva_marina_ok_em' then (a.antes ->> 'reserva_marina_ok_em')::timestamptz else p.reserva_marina_ok_em end,
         descida_ok_em = case when a.antes ? 'descida_ok_em' then (a.antes ->> 'descida_ok_em')::timestamptz else p.descida_ok_em end,
         entrada_em = case when a.antes ? 'entrada_em' then (a.antes ->> 'entrada_em')::date else p.entrada_em end,
         entrada_fonte = case when a.antes ? 'entrada_em' then a.antes ->> 'entrada_fonte' else p.entrada_fonte end,
         nao_antes_de = case when a.antes ? 'nao_antes_de' then (a.antes ->> 'nao_antes_de')::date else p.nao_antes_de end,
         nao_antes_motivo = case when a.antes ? 'nao_antes_de' then a.antes ->> 'nao_antes_motivo' else p.nao_antes_motivo end,
         -- FASE 7d: (7d P6, §5.6) as colunas do que o cliente disse
         local_id = case when a.antes ? 'local_id' then (a.antes ->> 'local_id')::uuid else p.local_id end,
         local_fonte = case when a.antes ? 'local_id' then a.antes ->> 'local_fonte' else p.local_fonte end,
         local_em = case when a.antes ? 'local_id' then (a.antes ->> 'local_em')::timestamptz else p.local_em end,
         bem_situacao = case when a.antes ? 'bem_situacao' then a.antes ->> 'bem_situacao' else p.bem_situacao end,
         bem_situacao_fonte = case when a.antes ? 'bem_situacao' then a.antes ->> 'bem_situacao_fonte' else p.bem_situacao_fonte end,
         bem_situacao_em = case when a.antes ? 'bem_situacao' then (a.antes ->> 'bem_situacao_em')::timestamptz else p.bem_situacao_em end,
         descer_quem = case when a.antes ? 'descer_quem' then a.antes ->> 'descer_quem' else p.descer_quem end,
         -- FASE 7d: fim
         historico = public._os_material_historico(p.historico, jsonb_build_object(
           'em', (p_agora at time zone 'America/Sao_Paulo')::date, 'quando', p_agora, 'autor', p_autor, 'por', 'dono', 'motivo', 'desfeito',
           'acao', a.id, 'antes', a.depois - 'item' - 'replano_acoes', 'depois', a.antes)),
         atualizado_em = p_agora, atualizado_por = p_autor
   where p.service_order_id = a.service_order_id;
  return true;
end;
$function$;

comment on function public._agenda_local_restaurar(uuid, uuid, timestamptz) is
  'Agenda de Produção (Fase 7d, P5; §5.5): volta as colunas de os_planejamento que a ação local gravou (o antes: acesso_ok_em, reserva_marina_ok_em, descida_ok_em, entrada_em e entrada_fonte, nao_antes_de e nao_antes_motivo), só se o que está gravado ainda é o depois dela; senão false, nada muda. Guarda no histórico. Invoker, sem grant: chamam _agenda_desfazer_local e agenda_desfazer, definer. FASE 7d (P6, §5.6): volta também local_id, local_fonte e local_em; bem_situacao, bem_situacao_fonte e bem_situacao_em; descer_quem.';

-- _agenda_desfazer_local (de 20261107100400_agenda_fase7d_combinar.sql): uma linha trocada, a do texto
create or replace function public._agenda_desfazer_local(p_acao uuid, p_autor uuid, p_via text, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  a       public.agenda_acoes%rowtype;
  v_os    uuid;
  v_ef    text;
  v_nome  text;
  v_id    uuid;
  v_r     jsonb;
  v_txts  text[] := '{}';
  v_falha text;
  v_txt   text;
  v_acao  uuid;
begin
  select * into a from public.agenda_acoes where id = p_acao;
  v_os := a.service_order_id;
  v_ef := a.depois ->> 'efeito';
  v_nome := coalesce(a.depois #>> '{item,cliente}', public._agenda_rotulo_da_os(v_os), 'serviço');
  if a.desfazivel_ate is null or p_agora > a.desfazivel_ate then
    return jsonb_build_object('ok', false, 'texto', format('Não dá mais para desfazer o %s: passou o prazo. Se quiser mudar, me diga.', v_nome));
  end if;
  if not public._agenda_local_restaurar(a.id, p_autor, p_agora) then
    return jsonb_build_object('ok', false, 'texto', format('Não desfaço: depois disso o plano do %s mudou. Se quiser mudar, me diga.', v_nome));
  end if;
  update public.os_autorizados x set revogado_em = p_agora
   where x.service_order_id = v_os and x.revogado_em is null
     and x.payee_id in (select y::uuid from jsonb_array_elements_text(coalesce(a.depois -> 'autorizados', '[]'::jsonb)) y);

  -- O replano do "Segure o dia" volta junto (cada ação dele, pelo desfazer de sempre)
  perform set_config('agenda.desfazer_local', 'on', true);
  for v_id in select x::uuid from jsonb_array_elements_text(coalesce(a.depois -> 'replano_acoes', '[]'::jsonb)) x loop
    if exists (select 1 from public.agenda_acoes e where e.id = v_id and e.executada and e.desfeita_em is null) then
      v_r := public.agenda_desfazer(v_id, p_autor, p_via, p_hoje, p_agora);
      if coalesce((v_r ->> 'ok')::boolean, false) then
        v_txts := v_txts || (v_r ->> 'texto');
      else
        v_falha := v_r ->> 'texto';
      end if;
    end if;
  end loop;
  perform set_config('agenda.desfazer_local', '', true);

  if v_ef = 'local' then
    v_txt := format('Desfeito: o local do serviço de %s voltou a ser o que eu supunha.', v_nome);
  elsif v_ef = 'segurar' then
    v_txt := case when cardinality(v_txts) > 0 then array_to_string(v_txts, ' ')
                  else format('Desfeito: não seguro mais o dia do %s.', v_nome) end || coalesce(' ' || v_falha, '');
  else
    v_txt := public._agenda_combinar_texto(a.depois -> 'item', 'desfeito', p_hoje);
  end if;
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, critica, antes, depois, texto, autor, desfaz_a)
  values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer', v_os, a.os_ids, false,
          jsonb_build_object('acao', a.id), a.antes, public._agenda_corta(v_txt, 400), p_autor, a.id)
  returning id into v_acao;
  update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = a.id;
  return jsonb_build_object('ok', true, 'texto', public._agenda_corta(v_txt, 400), 'acao_id', v_acao, 'recriadas', '[]'::jsonb, 'canceladas', '[]'::jsonb);
end;
$function$;

comment on function public._agenda_desfazer_local(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 7d, P5; §5.5; R6.7c-1): o *desfaz* da ação local — dentro do desfazivel_ate e só se nada mudou depois: as colunas voltam (_agenda_local_restaurar), as linhas de os_autorizados que ela criou ganham revogado_em e o replano do "Segure o dia" volta, cada ação pelo agenda_desfazer de sempre (com agenda.desfazer_local ligada, para não restaurar duas vezes). Só agenda_desfazer chama (o plano já travado). FASE 7d (P6, §6.3): a ação do que o cliente disse (efeito local) diz "Desfeito: o local do serviço de Nelson voltou a ser o que eu supunha.".';

-- _agenda_local_decidir (de 20261107100400_agenda_fase7d_combinar.sql): a linha do tipo trocada, e o bloco da local
create or replace function public._agenda_local_decidir(p_pergunta uuid, p_opcao smallint, p_autor uuid, p_via text, p_trecho text, p_hoje date,
                                                        p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_q     public.agenda_perguntas%rowtype;
  pl      public.os_planejamento%rowtype;
  v_opc   jsonb;
  v_ef    text;
  v_item  jsonb;
  v_tipo  text;
  v_os    uuid;
  v_para  date;
  v_pess  uuid[] := '{}';
  v_antes jsonb;
  v_dep   jsonb;
  v_nao   date;
  v_r     jsonb;
  v_acoes jsonb := '[]'::jsonb;
  v_txt   text;
  v_acao  uuid;
  v_nome  text;
begin
  if p_via is null or p_via not in ('whatsapp', 'painel', 'tela') then
    raise exception 'Canal desconhecido para a decisão: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  select * into v_q from public.agenda_perguntas where id = p_pergunta for update;
  if not found then
    raise exception 'Não encontrei essa pergunta.' using errcode = 'P0002';
  end if;
  if v_q.tipo not in ('combinar', 'acesso', 'local') then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta não é do que combinar.');
  end if;
  if v_q.estado <> 'aberta' then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta já foi respondida ou resolvida.');
  end if;
  -- R6.7b: a pergunta e o modo CRU, não o freio: com *gestor, só propor*, a pergunta já aberta continua respondível
  if v_q.modo <> 'ligado' or coalesce(public._agenda_modo_da_pergunta(v_q.tipo, v_q.chave), 'desligado') <> 'ligado' then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta ainda está em teste: mostro como ficaria, mas não mudo nada.');
  end if;
  select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
  if v_opc is null then
    return jsonb_build_object('ok', false,
      'texto', 'Essa opção não existe. As opções são: '
               || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                     from jsonb_array_elements(v_q.opcoes) o) || '.');
  end if;
  v_ef := v_opc #>> '{efeito,local}';
  v_os := v_q.service_order_id;
  v_para := v_q.perda_em;
  v_item := v_q.opcoes -> 0 #> '{efeito,item}';
  v_tipo := v_item ->> 'tipo';

  -- FASE 7d: (7d P6; §5.6, §6.3, R6.7b) a local: nasce da resposta do cliente, só grava com o sim do dono e não mexe no plano (nenhum replano). A opção 1 grava o
  -- que a leitura achou (fonte cliente), com a ação local e *desfaz*; a opção 2 só responde
  if v_q.tipo = 'local' then
    if v_ef is distinct from 'gravar' then
      update public.agenda_perguntas
         set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
             respondida_por = p_autor, respondida_via = p_via
       where id = v_q.id;
      return jsonb_build_object('ok', true, 'texto', 'Certo, não gravei. Quando souber, me diga onde é.');
    end if;
    insert into public.os_planejamento (service_order_id) values (v_os) on conflict (service_order_id) do nothing;
    select * into pl from public.os_planejamento x where x.service_order_id = v_os for update;
    v_antes := '{}'::jsonb;
    v_dep := '{}'::jsonb;
    if v_item ->> 'local_id' is not null then
      v_antes := v_antes || jsonb_build_object('local_id', pl.local_id, 'local_fonte', pl.local_fonte, 'local_em', pl.local_em);
      v_dep := v_dep || jsonb_build_object('local_id', v_item ->> 'local_id', 'local_fonte', 'cliente', 'local_em', p_agora);
    end if;
    if v_item ->> 'situacao' is not null then
      v_antes := v_antes || jsonb_build_object('bem_situacao', pl.bem_situacao, 'bem_situacao_fonte', pl.bem_situacao_fonte, 'bem_situacao_em', pl.bem_situacao_em);
      v_dep := v_dep || jsonb_build_object('bem_situacao', v_item ->> 'situacao', 'bem_situacao_fonte', 'cliente', 'bem_situacao_em', p_agora);
    end if;
    if v_item ->> 'descer_quem' is not null then
      v_antes := v_antes || jsonb_build_object('descer_quem', pl.descer_quem);
      v_dep := v_dep || jsonb_build_object('descer_quem', v_item ->> 'descer_quem');
    end if;
    update public.os_planejamento p
       set local_id = case when v_dep ? 'local_id' then (v_dep ->> 'local_id')::uuid else p.local_id end,
           local_fonte = case when v_dep ? 'local_id' then 'cliente' else p.local_fonte end,
           local_em = case when v_dep ? 'local_id' then p_agora else p.local_em end,
           bem_situacao = case when v_dep ? 'bem_situacao' then v_dep ->> 'bem_situacao' else p.bem_situacao end,
           bem_situacao_fonte = case when v_dep ? 'bem_situacao' then 'cliente' else p.bem_situacao_fonte end,
           bem_situacao_em = case when v_dep ? 'bem_situacao' then p_agora else p.bem_situacao_em end,
           descer_quem = case when v_dep ? 'descer_quem' then v_dep ->> 'descer_quem' else p.descer_quem end,
           historico = public._os_material_historico(p.historico, jsonb_build_object(
             'em', p_hoje, 'quando', p_agora, 'autor', p_autor, 'por', 'dono', 'motivo', 'você respondeu: local', 'pergunta', v_q.id,
             'antes', v_antes, 'depois', v_dep)),
           atualizado_em = p_agora, atualizado_por = p_autor
     where p.service_order_id = v_os;
    update public.agenda_perguntas
       set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
           respondida_por = p_autor, respondida_via = p_via
     where id = v_q.id;
    v_txt := format('Gravei o que %s disse: %s. *desfaz* volta.', coalesce(v_item ->> 'cliente', 'cliente'),
                    concat_ws(', e ',
                      (v_item ->> 'bem') || ' está ' || nullif(concat_ws(', ',
                        case when v_item ->> 'local_nome' is not null then public._agenda_local_no(v_item ->> 'local_nome') end,
                        case v_item ->> 'situacao' when 'agua' then 'na água' when 'patio' then 'no pátio'
                                                   when 'seco' then 'em seco' when 'garagem_seca' then 'em seco' end), ''),
                      'quem desce é ' || (v_item ->> 'descer_quem')));
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, pergunta_id, critica, antes, depois, texto,
                                     motivo, autor, desfazivel_ate)
    values (clock_timestamp(), p_hoje, true, 'dono', 'local', v_os, array[v_os], v_q.id, v_q.critica, v_antes,
            v_dep || jsonb_build_object('efeito', 'local', 'item', v_item), public._agenda_corta(v_txt, 400), 'você respondeu', p_autor,
            p_agora + cf.desfazer_validade)
    returning id into v_acao;
    return jsonb_build_object('ok', true, 'texto', public._agenda_corta(v_txt, 400), 'acao_id', v_acao);
  end if;
  -- FASE 7d: fim
  -- A opção "ainda não" só responde. A crítica fica aberta até o dia ("fica a pergunta do dia"): quem disse "vou combinar hoje" ainda pode dizer que
  -- combinou ou segurar o dia; ela não volta no fechamento e o resolvedor a fecha quando o dia chega.
  if v_ef = 'nada' then
    if v_q.tipo = 'acesso' then
      update public.agenda_perguntas set opcao_escolhida = p_opcao, resposta = left(p_trecho, 500) where id = v_q.id;
      return jsonb_build_object('ok', true, 'texto', 'Certo. Se não der, responda 3 que eu remarco.');
    end if;
    update public.agenda_perguntas
       set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
           respondida_por = p_autor, respondida_via = p_via
     where id = v_q.id;
    return jsonb_build_object('ok', true,
      'texto', case when public.agenda_somar_du(p_hoje, 1) < v_para then 'Certo. Amanhã eu pergunto de novo.' else 'Certo, não anotei.' end);
  end if;

  insert into public.os_planejamento (service_order_id) values (v_os) on conflict (service_order_id) do nothing;
  select * into pl from public.os_planejamento x where x.service_order_id = v_os for update;

  -- "Segure o dia": agenda_replanejar não recebe restrição e, sem violação, o dia fica. O "não antes de" é o que faz o dia cair
  -- (a regra a.dia < pl.nao_antes_de); o fixado pelo dono fica, e o texto diz; o dia já avisado ao cliente abre a dia_avisado, o caminho de sempre.
  if v_ef = 'segurar' then
    if cf.modo_proposta <> 'ligado' then
      return jsonb_build_object('ok', false, 'texto', 'A agenda automática ainda está em teste: mostro como ficaria, mas não marco nada.');
    end if;
    v_nao := greatest(coalesce(pl.nao_antes_de, v_para), public.agenda_somar_du(v_para, 1));
    v_antes := jsonb_build_object('nao_antes_de', pl.nao_antes_de, 'nao_antes_motivo', pl.nao_antes_motivo);
    v_dep := jsonb_build_object('nao_antes_de', v_nao, 'nao_antes_motivo', 'sem acesso', 'efeito', 'segurar', 'item', v_item);
    begin
      update public.os_planejamento p
         set nao_antes_de = v_nao, nao_antes_motivo = 'sem acesso',
             historico = public._os_material_historico(p.historico, jsonb_build_object(
               'em', p_hoje, 'quando', p_agora, 'autor', p_autor, 'por', 'dono', 'motivo', 'segure o dia: sem acesso', 'pergunta', v_q.id,
               'antes', v_antes, 'depois', v_dep - 'item' - 'efeito')),
             atualizado_em = p_agora, atualizado_por = p_autor
       where p.service_order_id = v_os;
      update public.agenda_perguntas
         set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
             respondida_por = p_autor, respondida_via = p_via
       where id = v_q.id;
      v_r := public.agenda_replanejar(array[v_os], 'sem acesso', 'dono', p_hoje, p_agora, p_autor);
      if not coalesce((v_r ->> 'ok')::boolean, false) then
        raise exception using errcode = 'P0098', message = coalesce(v_r ->> 'texto', 'não deu');
      end if;
    exception when sqlstate 'P0098' then
      -- nada fica: a pergunta continua aberta
      return jsonb_build_object('ok', false, 'texto', 'Não consegui segurar o dia: ' || sqlerrm || ' Nada mudou.');
    end;
    v_acoes := coalesce(v_r -> 'acoes', '[]'::jsonb);
    v_nome := coalesce(v_item ->> 'cliente', 'cliente');
    v_txt := format('Segurei o dia: %s não começa antes de %s (sem acesso). *desfaz* volta.', v_nome, public._dia_curto(v_nao));
    if exists (select 1 from public.agenda_alocacoes a
                where a.service_order_id = v_os and a.dia = v_para and a.estado in ('publicada', 'fixada') and a.fixado_por = 'dono') then
      v_txt := v_txt || format(' %s fica no plano, porque foi você que marcou esse dia: para tirar, me diga.', public._agenda_maiuscula(public._dia_curto(v_para)));
    end if;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, pergunta_id, critica, antes, depois, texto,
                                     motivo, autor, desfazivel_ate)
    values (clock_timestamp(), p_hoje, true, 'dono', 'local', v_os, array[v_os], v_q.id, v_q.critica, v_antes,
            v_dep || jsonb_build_object('replano_acoes', v_acoes), public._agenda_corta(v_txt, 400), 'você escolheu na pergunta', p_autor,
            p_agora + cf.desfazer_validade)
    returning id into v_acao;
    return jsonb_build_object('ok', true, 'texto', concat_ws(' ', v_txt, nullif(v_r ->> 'texto', '')), 'acao_id', v_acao, 'acoes', v_acoes);
  end if;

  -- A opção 1: grava o fato. No acesso, sempre acesso_ok_em; e, só no local que exige autorização com o nome, uma linha por pessoa da pergunta
  -- (R6.5).
  if v_tipo = 'acesso' then
    v_antes := jsonb_build_object('acesso_ok_em', pl.acesso_ok_em);
    v_dep := jsonb_build_object('acesso_ok_em', p_agora);
    update public.os_planejamento p set acesso_ok_em = p_agora where p.service_order_id = v_os;
    if coalesce((v_item ->> 'nominal')::boolean, false) then
      v_pess := array(select x::uuid from jsonb_array_elements_text(coalesce(v_item -> 'pessoas', '[]'::jsonb)) x);
      insert into public.os_autorizados (service_order_id, payee_id, local_id, valido_ate, fonte, trecho, criado_em, criado_por)
      select v_os, u.id, nullif(v_item ->> 'local_id', '')::uuid, (v_item ->> 'fim')::date, 'dono', left(p_trecho, 300), p_agora, p_autor
        from unnest(v_pess) u(id)
      on conflict (service_order_id, payee_id) do update
        set local_id = excluded.local_id, valido_ate = excluded.valido_ate, fonte = excluded.fonte, trecho = excluded.trecho,
            revogado_em = null, criado_em = excluded.criado_em, criado_por = excluded.criado_por;
      v_dep := v_dep || jsonb_build_object('autorizados', to_jsonb(v_pess));
    end if;
  elsif v_tipo = 'reserva_marina' then
    v_antes := jsonb_build_object('reserva_marina_ok_em', pl.reserva_marina_ok_em);
    v_dep := jsonb_build_object('reserva_marina_ok_em', p_agora);
    update public.os_planejamento p set reserva_marina_ok_em = p_agora where p.service_order_id = v_os;
  elsif v_tipo = 'descida' then
    v_antes := jsonb_build_object('descida_ok_em', pl.descida_ok_em);
    v_dep := jsonb_build_object('descida_ok_em', p_agora);
    update public.os_planejamento p set descida_ok_em = p_agora where p.service_order_id = v_os;
  else
    -- entrada_antes_saida: o CHECK recusaria; a recusa diz por quê
    if pl.retirada_em is not null and v_para >= pl.retirada_em then
      return jsonb_build_object('ok', false,
        'texto', format('Não anotei: você disse que o %s sai %s, antes da chegada. Me diga as datas certas.', coalesce(v_item ->> 'bem', 'bem'),
                        public._dia_curto(pl.retirada_em)));
    end if;
    v_antes := jsonb_build_object('entrada_em', pl.entrada_em, 'entrada_fonte', pl.entrada_fonte);
    v_dep := jsonb_build_object('entrada_em', v_para, 'entrada_fonte', 'dono');
    update public.os_planejamento p set entrada_em = v_para, entrada_fonte = 'dono' where p.service_order_id = v_os;
  end if;
  update public.os_planejamento p
     set historico = public._os_material_historico(p.historico, jsonb_build_object(
           'em', p_hoje, 'quando', p_agora, 'autor', p_autor, 'por', 'dono', 'motivo', 'você respondeu: ' || v_tipo, 'pergunta', v_q.id,
           'antes', v_antes, 'depois', v_dep)),
         atualizado_em = p_agora, atualizado_por = p_autor
   where p.service_order_id = v_os;
  update public.agenda_perguntas
     set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
         respondida_por = p_autor, respondida_via = p_via
   where id = v_q.id;
  v_txt := public._agenda_corta(public._agenda_combinar_texto(v_item, 'anotei', p_hoje), 400);
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, pergunta_id, critica, antes, depois, texto,
                                   motivo, autor, desfazivel_ate)
  values (clock_timestamp(), p_hoje, true, 'dono', 'local', v_os, array[v_os], v_q.id, v_q.critica, v_antes,
          v_dep || jsonb_build_object('efeito', v_tipo, 'item', v_item), v_txt, 'você respondeu', p_autor, p_agora + cf.desfazer_validade)
  returning id into v_acao;
  return jsonb_build_object('ok', true, 'texto', v_txt, 'acao_id', v_acao);
end;
$function$;

comment on function public._agenda_local_decidir(uuid, smallint, uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 7d, P5; §5.5; R1; R6.5; R6.7b; R6.7c-1): a resposta do dono às perguntas combinar, acesso e local. Recusa a fechada, a de outro tipo e a que está fora de ligado pelo modo CRU (_agenda_modo_da_pergunta, não o freio: com *gestor, só propor* a aberta continua respondível). combinar, opção 1 e acesso, opção 1: grava o fato com a ação local desfazível — acesso_ok_em (no local que exige autorização com o nome e conferido, também uma linha de os_autorizados por pessoa da pergunta, fonte dono, valido_ate = o último dia), reserva_marina_ok_em, descida_ok_em ou entrada_em = para com entrada_fonte = dono. combinar, opção 2: só responde; a rodada de amanhã pergunta de novo. acesso, opção 2: fica aberta até o dia, com a opção anotada. acesso, opção 3 ("Segure o dia"): grava nao_antes_de = greatest(coalesce(nao_antes_de, para), agenda_somar_du(para, 1)) e nao_antes_motivo = sem acesso e só então chama agenda_replanejar(os, sem acesso, dono): o dia cai pela regra a.dia < nao_antes_de; o fixado pelo dono fica, e o texto diz; o dia avisado ao cliente abre a dia_avisado. A ação local leva replano_acoes: o *desfaz* volta tudo. Falhou = nada fica. Definer, sem grant: só agenda_decidir chama. FASE 7d (P6; §5.6, §6.3, R6.7b): local, opção 1: grava o que a leitura achou (local_id, bem_situacao, descer_quem; fonte cliente), com a ação local desfazível, sem mexer no plano; opção 2: só responde. Respondível com o freio: a pergunta e o modo cru.';

-- _agenda_estado_do_bem (de 20261107100200_agenda_fase7d_local.sql): a linha do M11 trocada
create or replace function public._agenda_estado_do_bem(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_classe text := public._agenda_classe_de_campo(p_os) ->> 'bem';
  v_pl     record;
  v_l      jsonb;
  v_o_bem  text;
  v_sit    text;
  v_sit_f  text;
  v_exige  text;
  v_ex_f   text := 'padrao';
  v_linhas text;
  v_temp   boolean;
  v_sup    text[] := '{}';
  v_quem   text;
  v_parte  text;
  v_cab    text;
  v_datas  text;
  v_texto  text;
begin
  if v_classe is null then
    return null;
  end if;
  v_o_bem := case v_classe when 'rv' then 'motorhome' when 'barco' then 'barco' else 'bem' end;
  v_temp := extract(month from p_hoje)::smallint = any (c.temporada_meses);

  select pl.bem_situacao, pl.bem_situacao_fonte, pl.bem_exige, pl.descer_quem, pl.entrada_em, pl.retirada_em, pl.entrada_fonte,
         coalesce(not isempty(pl.bem_indisponivel), false) as tem_fora
    into v_pl
    from public.service_orders so
    left join public.os_planejamento pl on pl.service_order_id = so.id
   where so.id = p_os;

  v_l := public._agenda_local_resolvido(p_os, p_hoje);
  v_quem := nullif(btrim(coalesce(v_pl.descer_quem, '')), '');

  -- Onde ele está: o que foi dito → o pátio, pelo tipo do local → não sei.
  if v_pl.bem_situacao is not null then
    v_sit := v_pl.bem_situacao;
    v_sit_f := v_pl.bem_situacao_fonte;
  elsif v_l ->> 'tipo' like 'patio\_%' then
    v_sit := 'patio';
    v_sit_f := 'local';
  end if;
  if v_l ->> 'fonte' = 'patio' then
    v_sup := v_sup || format('supus o %s %s', v_o_bem, v_l ->> 'texto_curto');
  end if;

  -- O que o serviço exige: o que foi dito → a palavra da linha de serviço → tanto faz. As palavras só valem para barco: a linha real
  -- "Substituição da hélice do exaustor da claraboia", de um motorhome, casaria "helice".
  if v_pl.bem_exige is not null then
    v_exige := v_pl.bem_exige;
    v_ex_f := 'dono';
  else
    if v_classe = 'barco' then
      -- As 2 primeiras linhas (a ordem de _agenda_servico_curto) e a de maior valor (a de _agenda_classe_de_campo).
      select string_agg(public._agenda_normal(normalize(x.name_snapshot, nfc)), ' | ') into v_linhas
        from (select s.name_snapshot,
                     row_number() over (order by s.created_at, s.id) as pela_ordem,
                     row_number() over (order by s.line_total desc nulls last, s.created_at nulls last, s.id) as pelo_valor
                from public.service_order_services s
               where s.service_order_id = p_os) x
       where x.pela_ordem <= 2 or x.pelo_valor = 1;
      -- O teste final na água pesa mais: é ele que pede a descida (d9 da §3.3).
      if v_linhas ~ ('\m(' || c.bem_agua_palavras || ')\M') then
        v_exige := 'agua';
      elsif v_linhas ~ ('\m(' || c.bem_seco_palavras || ')\M') then
        v_exige := 'seco';
      end if;
    end if;
    if v_exige = 'agua' then
      v_ex_f := 'palavra';
      v_sup := v_sup || 'supus o teste final na água (pela linha de serviço)'::text;
    elsif v_exige = 'seco' then
      v_ex_f := 'palavra';
      v_sup := v_sup || 'supus o serviço com o barco em seco (pela linha de serviço)'::text;
    end if;
    v_exige := coalesce(v_exige, 'tanto_faz');
  end if;

  -- Na temporada, sem os dias de uso ditos, o barco está suposto livre. "Perguntei" só com o M11 que saiu de verdade.
  if v_classe = 'barco' and v_temp and not coalesce(v_pl.tem_fora, false) and v_sit is distinct from 'com_cliente' then
    v_sup := v_sup || case when exists (select 1 from public.agenda_cliente_mensagens m
                                         where m.service_order_id = p_os and m.tipo = 'onde_fica'
                                           and m.estado in ('enviada', 'respondida', 'sem_resposta')
                                           and coalesce((m.base #>> '{dados,uso}')::boolean, false))
                           then 'supus o barco livre nos dias úteis (temporada: perguntei ao cliente os dias de uso)'
                           else 'supus o barco livre nos dias úteis (temporada: ainda não sei os dias de uso)' end;
  end if;

  -- O texto só diz o que foi dito ou o que o serviço pede; o que o local supõe sai no texto do local.
  v_cab := case when v_pl.bem_situacao is not null then
             case v_sit when 'agua' then 'na água' when 'seco' then 'em seco' when 'garagem_seca' then 'em seco (garagem)'
                        when 'patio' then 'no pátio' else 'com o cliente' end end;
  v_parte := case v_exige when 'agua' then 'o teste final é na água'
                          when 'seco' then format('o serviço é com o %s em seco', v_o_bem) end;
  v_datas := case when v_pl.entrada_em is not null and v_pl.retirada_em is not null
                    then format('O %s chega %s e sai %s.', v_o_bem, public._dia_curto(v_pl.entrada_em), public._dia_curto(v_pl.retirada_em))
                  when v_pl.entrada_em is not null then format('O %s chega %s.', v_o_bem, public._dia_curto(v_pl.entrada_em))
                  when v_pl.retirada_em is not null then format('O %s sai %s.', v_o_bem, public._dia_curto(v_pl.retirada_em)) end;
  if v_cab is not null then
    v_texto := format('O %s: %s', v_o_bem, v_cab) || coalesce(', quem desce: ' || v_quem, '') || coalesce('; ' || v_parte, '') || '.';
  elsif v_quem is not null then
    v_texto := 'Quem desce: ' || v_quem || coalesce('; ' || v_parte, '') || '.';
  elsif v_parte is not null then
    v_texto := upper(left(v_parte, 1)) || substr(v_parte, 2) || '.';
  end if;
  if v_datas is not null then
    v_texto := coalesce(v_texto || ' ', '') || v_datas;
  end if;

  return jsonb_build_object(
    'classe', v_classe, 'situacao', v_sit, 'situacao_fonte', v_sit_f, 'exige', v_exige, 'exige_fonte', v_ex_f,
    'descer_quem', v_quem, 'temporada', v_temp, 'entrada_em', v_pl.entrada_em, 'retirada_em', v_pl.retirada_em,
    'entrada_fonte', v_pl.entrada_fonte, 'suposicoes', to_jsonb(v_sup), 'texto', v_texto);
end;
$function$;

comment on function public._agenda_estado_do_bem(uuid, date) is
  'Agenda de Produção (Fase 7d, P3; §3.1, item 10; AG7-14, AG7-20): {classe, situacao, situacao_fonte, exige, exige_fonte, descer_quem, temporada, entrada_em, retirada_em, entrada_fonte, suposicoes[], texto}. situacao: a dita → patio pelo tipo do local (fonte local) → null. exige: o dito → a palavra (bem_agua_palavras, bem_seco_palavras, só em barco, nas 2 primeiras linhas de serviço e na de maior valor, com a água primeiro) → tanto_faz. Em uso pelo cliente é bem_indisponivel, que já existe. A OS que não existe: null. STABLE, invoker. FASE 7d (P6, R6.9-5): "perguntei ao cliente os dias de uso" só com o M11 que saiu com o {uso}: o que passou do teto sai sem ele, e dizer ao dono que perguntou sem ter perguntado seria plano falso.';

-- agenda_decisoes_abertas (de 20261107100400_agenda_fase7d_combinar.sql): a linha do where trocada
create or replace function public.agenda_decisoes_abertas(p_agora timestamptz default now())
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
           'n', x.n, 'id', x.id, 'tipo', x.tipo, 'os', x.service_order_id, 'os_ids', to_jsonb(x.os_ids), 'texto', x.texto,
           'opcoes', x.opcoes, 'recomendacao', x.recomendacao, 'recomendacao_texto', x.recomendacao_texto,
           'perda_em', x.perda_em, 'versao_base', x.versao_base) order by x.n), '[]'::jsonb)
    from (select q.*, row_number() over (order by q.perda_em nulls last, q.criada_em, q.id) as n
            from public.agenda_perguntas q
           where (q.critica or q.tipo in ('combinar', 'local')) and q.estado = 'aberta' and q.modo = 'ligado'
             and (q.expira_em is null or q.expira_em > p_agora)) x;
$function$;

comment on function public.agenda_decisoes_abertas(timestamptz) is
  'Agenda de Produção (Fase 2, P4): as decisões críticas abertas (modo ligado) numeradas — n = 1 é a que perde primeiro (perda_em, depois a mais antiga). [{n, id, tipo, os, os_ids, texto, opcoes, recomendacao, recomendacao_texto, perda_em, versao_base}]. O rascunho resolve "a 1" por aqui; agenda_ver (foco decisoes) numera igual. FASE 7d (P5): a pergunta combinar (não crítica, com opções) entra na lista: é só por aqui que uma pergunta chega a agenda_decidir pela conversa e pela tela. FASE 7d (P6): a pergunta local também entra: ela tem opções e nasce da resposta do cliente.';

-- _agenda_ver_decisoes (de 20261107100400_agenda_fase7d_combinar.sql): a linha do bloco do P5 trocada
create or replace function public._agenda_ver_decisoes(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_dec   jsonb := public.agenda_decisoes_abertas(p_agora);
  v_l     text[] := '{}';
  v_outra text[];
  v_som   text[];
  e       jsonb;
begin
  for e in select x from jsonb_array_elements(v_dec) x loop
    -- FASE 3: a da diária com as opções, a recomendação e as palavras
    v_l := v_l || format('Decisão %s: %s', e ->> 'n',
                         case when e ->> 'tipo' = 'diaria' then public._agenda_texto_da_diaria((e ->> 'id')::uuid) else e ->> 'texto' end);
  end loop;
  v_outra := array(select q.texto from public.agenda_perguntas q
                    where not q.critica and q.estado = 'aberta' and q.modo = 'ligado'
                      -- FASE 7d: (7d P5, P6) a combinar e a local já vêm numeradas em v_dec (agenda_decisoes_abertas)
                      and q.tipo not in ('combinar', 'local')
                      -- FASE 7d: fim
                      and (q.expira_em is null or q.expira_em > p_agora)
                    order by q.perda_em nulls last, q.criada_em, q.id);
  if jsonb_array_length(v_dec) > 0 then
    v_l := array[case when jsonb_array_length(v_dec) = 1 then 'Uma decisão espera você na agenda:'
                      else format('%s decisões esperam você na agenda:', jsonb_array_length(v_dec)) end]
           || v_l
           || 'Para responder, diga a decisão e a opção (por exemplo, "na decisão 1, a opção 2"). Eu não escolho por você.'::text;
  end if;
  if cardinality(v_outra) > 0 then
    v_l := v_l || array(select 'Também quero saber: ' || x from unnest(v_outra) with ordinality u(x, o) order by o);
  end if;
  if cardinality(v_l) = 0 then
    v_som := array(select q.texto from public.agenda_perguntas q
                    where q.estado = 'aberta' and q.modo = 'sombra' and (q.expira_em is null or q.expira_em > p_agora)
                    order by q.critica desc, q.perda_em nulls last, q.criada_em, q.id);
    if cardinality(v_som) > 0 and (cf.modo_proposta = 'sombra' or cf.modo_vigia = 'sombra') then
      v_l := array['Em teste (nada foi perguntado de verdade): eu perguntaria isto.']
             || array(select '• ' || x from unnest(v_som) with ordinality u(x, o) order by o);
    else
      v_l := array['Nada esperando você na agenda agora.'];
    end if;
  end if;
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_l, cf.texto_max),
                            'dados', jsonb_build_object('decisoes', v_dec, 'outras', cardinality(v_outra)));
end;
$function$;

comment on function public._agenda_ver_decisoes(date, timestamptz) is
  'Agenda de Produção (Fase 2, P5; Fase 3, P6: a da diária com as opções e as palavras): agenda_ver foco decisoes — as decisões críticas abertas numeradas por agenda_decisoes_abertas ("Decisão 1: <a pergunta com as opções e a recomendação>"), como responder, e o que mais a agenda quer saber (chegou?, parada?, o que falta?), uma linha cada; sem nada em ligado, o que a sombra perguntaria ("Em teste"); nada = "Nada esperando você na agenda agora.". {ok, texto, dados{decisoes, outras}}. FASE 7d (P5): a combinar vem numerada, como decisão, e sai de "Também quero saber". FASE 7d (P6): a local também vem numerada.';

-- ── 5. Portas ─────────────────────────────────────────────────────────────────────────────────────
-- Revoke de public, anon, authenticated e service_role: o privilégio padrão do esquema daria o execute a todos. Os 5 são internos, como os outros
-- passos da rodada: quem os alcança é definer. As recriadas mantêm as portas delas: create or replace não muda a ACL, e nenhuma é nova.
revoke all on function
  public._agenda_cliente_ja_atendida(uuid),
  public._agenda_cliente_onde_falta(uuid, date),
  public._agenda_cliente_onde_fica(date, timestamptz),
  public._agenda_local_proposto(uuid, text, date),
  public._agenda_cliente_anotar_onde(uuid, uuid, text, date, timestamptz)
  from public, anon, authenticated, service_role;
