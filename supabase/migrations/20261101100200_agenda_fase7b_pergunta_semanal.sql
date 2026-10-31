-- Agenda de Produção, Fase 7, etapa 7b ("os dias de verdade de quem trabalha e a dupla pela tarefa"), pacote P3: a pergunta da
-- semana (à equipe com dias fixos e telefone; ao dono só quando faz diferença), as respostas, o cadastro da equipe pela régua de
-- 30/10 (a chamada com o telefone dentro, o contato de quem vem sob demanda, a regra d14 só de quem tem dias fixos, o "2) Não"
-- gravado) e a linha (n) da equipe no fechamento.
-- Spec: scratchpad agenda-pesquisa/spec-fase7b.md (§R4.1, §R4.2, §R4.6, §R4.7 P3, §5.2, §6.1–§6.4, §8.3 agenda_fase7b_pergunta.sql);
-- nomes: fase7-registro.md §1 (7b P3); respostas do dono: fase7-padroes.md (AG7-02 o dono em campo; AG7-03 a equipe: Alex, o dono e
-- quem vem sob demanda — Mateus e Vinicius —; AG7-13 os telefones; AG7-15 sem resposta até o prazo, fica como está).
-- Depende das Fases 1 a 6, do lote de 30/10 (20261030100000 .. 100600, em produção), da 7a inteira (20261031100000 .. 100985 e o
-- dado 20261031100990) e do 7b P1 (20261101100000: modo_dias, modo_cadastro, modo_chamar, os parâmetros equipe_*, dias_semana_motivos,
-- os tipos dias e dias_semana, a rotina equipe_semana) e P2 (20261101100100: _agenda_dias_curtos, _agenda_semana_perguntada,
-- _agenda_dias_declarados, _agenda_chance_de_falta, _agenda_equipe_dias_gravar).
--
-- ═══ DDL — OK NOMEADO ═══ (5 funções novas e 8 recriadas, as mesmas assinaturas; nenhuma tabela, nenhuma coluna, nenhum dado)
-- NÃO APLICADA. Existe para revisão e espera o OK do dono. Este arquivo foi MONTADO por
-- scratchpad/agenda-pesquisa/f7b/p3/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA (conferida a cada montagem: o
-- montador para se outra migration a definir depois da origem), e as mudanças estão só nos blocos "-- FASE 7b: … -- FASE 7b: fim"
-- (só acréscimo: nenhuma linha de antes muda; tirados os blocos, o corpo é o da origem, byte a byte).
--
-- POR QUE: a capacidade passa a ser o que cada um diz que pode. Quem tem dias fixos e telefone diz, toda quinta, os dias da semana
-- seguinte à próxima; o dono só é perguntado quando a resposta muda alguma coisa (um serviço que depende dele sem os dias dele, um
-- palpite da semente); a chamada da equipe lista quem o dono declarou e pede o telefone de quem conta e não tem (o Alex); e as
-- perguntas da equipe chegam de fato ao dono, numa linha própria do fechamento — pela pergunta de fato (e) elas nunca entrariam nas
-- vagas (as duas de fornecedor estão abertas e nunca vistas desde 28/10).
--
-- O QUE MUDA:
--   1. Novas: _agenda_ler_dias_da_equipe (a resposta da pessoa sem IA: os dias, "nenhum", "igual" ou "não entendi"; "segunda não
--      posso" nunca vira "não vou", A3 = NOVO-agenda-54); _agenda_equipe_previstas_hoje (quantas mensagens a rotina ainda vai
--      começar hoje para a pessoa: o "como foi" e a ficha); _agenda_equipe_texto_dias (a pergunta à pessoa, §6.1);
--      _agenda_dias_semana_motivos (por que perguntar ao dono nesta quinta: dono_sem_padrao, semente; sem motivo, nada — o motivo
--      chamar é do P6, que a recria); agenda_equipe_semana (a rodada a cada tique do task-automations, passo 0b1: contatos, cadastro,
--      fechar, perguntar; definer, só o service_role).
--   2. _agenda_equipe_registrar: o tipo dias (a segunda da semana perguntada), ligado só com modo_equipe e modo_dias ligados; com
--      modo_dias desligado, nada.
--   3. _agenda_rotina_sem_resposta: a pergunta da semana não fecha em 14 h (A2 = NOVO-agenda-53): quem a fecha é o prazo da semana.
--   4. agenda_resposta_da_equipe: a resposta à pergunta da semana tem o ramo dela, antes do "não vou" e do "como foi" (A1 =
--      NOVO-agenda-52): os dias e o "nenhum" gravam a semana (e o padrão de quem tem) pelo _agenda_equipe_dias_gravar e respondem
--      "Anotei: …"; o "igual" com a pergunta por último só responde; o "não entendi" pergunta de novo uma vez e, na 2ª, vai ao dono
--      (equipe_resposta). A "última que o sistema começou" do resto não é mais a pergunta da semana.
--   5. agenda_decidir: a chamada (1 está certo; 2 mudou: "Me diga quem saiu ou quem entrou e em que dias vem …"), o contato (1 põe
--      na rotina, com *desfaz*; 2 grava a recusa: a linha parada, e nem a d14 nem a pergunta voltam) e a pergunta dos dias do dono (a
--      opção com dias grava a semana pelo _agenda_equipe_dias_gravar — a 2, "Fico em campo de seg a sex", cria o padrão do dono —;
--      a 1 só fica respondida).
--   6. agenda_desfazer: a entrada na rotina pela regra d14 ou pelo "1) Ponho" sai (recebe_rotina false, a linha parada: a regra não
--      a põe de novo).
--   7. _agenda_ver_equipe (foco equipe): os dias da semana perguntada e da seguinte por pessoa, as faltas nos dias ditos, as duplas
--      dos últimos dias, quem vem sob demanda e quem saiu da agenda (com os modos da 7b desligados, o de antes, byte a byte).
--   8. _agenda_linhas_do_fechamento: a linha (n) da equipe — a chamada, a pergunta dos dias, o telefone e o contato numa linha só,
--      perda 75 enquanto alguma nunca foi mostrada ou perde hoje (senão 30), as outras curtas, todas em pergunta_ids; a (e) não as
--      repete (com os modos da 7b desligados, a saída de antes, byte a byte).
--   9. _agenda_gestor_equipe (7a): com modo_cadastro fora de desligado, {pulado: modo_cadastro} — a chamada é uma só, a desta etapa.
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7b_pergunta.sql; registradas em notas-fase77b.md, P3):
--   · O perda_em da chamada fica nulo: o prazo só existe depois de mostrada (veto_ate, gravado aqui na 1ª vez), e o gatilho das
--     perguntas (_agenda_perguntas_antes) não deixa o perda_em mudar depois de criada. A linha (n) lê o veto_ate para o "perde hoje".
--   · A chamada nasce com expira_em = criada + 7 dias (o teto do R4.2(d)): a que ninguém viu vence pela limpeza da vigia; ao ser vista,
--     o expira_em passa ao prazo + desfazer_validade.
--   · A espera da chamada (a 1ª pergunta da semana em ligado) vale só para a pergunta à equipe; a do dono tem os motivos dela.
--   · A linha (n) e a exclusão na (e) só valem com modo_dias ou modo_cadastro fora de desligado (com os dois desligados, a chamada da
--     7a continua na (e), byte a byte).
--   · Quem saiu da agenda vem na ordem em que entrou no cadastro ("Roberto e João").
--
-- ORDEM DE LIGAR: nada muda com os 5 modos da 7b desligados (como a migration nasce). O dado 20261101100900 (P5, OK nomeado) põe os
-- modos em sombra: a chamada, o contato, a d14 e a pergunta da semana ficam só em teste (perguntas em sombra, mensagem registrada com
-- ":sombra"). O ligar é UPDATE do mesmo dia (AG7-01): "OK ligar o cadastro" (modo_cadastro), depois "OK ligar a pergunta dos dias"
-- (modo_dias; a 1ª pergunta à equipe em ligado espera a chamada respondida ou vencida, no máximo 7 dias).
--
-- PROVA: supabase/tests/agenda_fase7b_pergunta.sql (na bancada: node scripts/bancada-agenda/rodar.mjs).
-- APLICAR (só com o OK do dono, depois das do 7b P1 e P2): npx supabase@2.111.0 db push (ou o roteiro de publicar da etapa).
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.

-- ── 1. As funções novas ────────────────────────────────────────────────────────────────────────────────────────

-- A resposta da pessoa à pergunta da semana, sem IA (spec §5.2): vazio → não entendi; "nenhum" (e "essa semana não posso"); turno junto
-- de dia útil ("terça só de manhã") → não entendi (dia inteiro só; o turno é pela data, com o dono); "não" junto de um dia ("segunda
-- não posso") → não entendi (A3: nunca vira o "não vou" da ficha); os dias (agenda_dias_da_semana_ditos; "todos", "a semana toda" =
-- todo dia; o sábado, com ou sem "de manhã", vira sabado); "igual" (ou a concordância: ok, sim); senão não entendi.
create or replace function public._agenda_ler_dias_da_equipe(p_texto text)
 returns jsonb
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  -- os dias como agenda_dias_da_semana_ditos os lê (o plural também: "terças e quintas")
  c_util constant text := '(segunda|terca|quarta|quinta|sexta|seg|ter|qua|qui|sex)s?';
  c_dia  constant text := '(segunda|terca|quarta|quinta|sexta|sabado|domingo|seg|ter|qua|qui|sex|sab|dom)s?';
  c_nada constant jsonb := jsonb_build_object('tipo', 'nao_entendi', 'dias', '[]'::jsonb, 'sabado', false);
  t      text := public._agenda_normal(p_texto);
  v_t    text;
  v_dias smallint[];
  v_sab  boolean;
begin
  -- 1. vazio
  if t = '' then
    return c_nada;
  end if;
  -- 2. nenhum
  if t ~ '^(nenhum|nenhum dia|nao posso|nao vou poder|nao da)( (nessa|essa|na|a) semana)?$'
     or t ~ '^(essa|nessa|a) semana (nao|nenhum)'
     or t ~ '\msemana (toda )?(nao posso|de folga|viajando)\M' then
    return jsonb_build_object('tipo', 'nenhum', 'dias', '[]'::jsonb, 'sabado', false);
  end if;
  -- 3. turno junto de dia útil, salvo o sábado de manhã (o sábado só vale de manhã: o "de manhã" dele sai antes); "ter que"/"ter de"
  -- é o verbo, não a terça ("vou ter que ver")
  v_t := regexp_replace(t, '\m(sabado|sab)( (de|pela|a) manha)?\M', 'sabado', 'g');
  v_t := regexp_replace(v_t, '\mter (que|de)\M', ' ', 'g');
  if v_t ~ ('\m' || c_util || '\M[^.]*\m(manha|tarde|meio periodo|meio dia)\M')
     or v_t ~ ('\m(manha|tarde|meio periodo|meio dia)\M[^.]*\m' || c_util || '\M') then
    return c_nada;
  end if;
  -- 4. "não" junto de um dia, sem menos/exceto/tirando/salvo (A3)
  if v_t ~ '\mnao\M' and v_t ~ ('\m' || c_dia || '\M') and v_t !~ '\m(menos|exceto|tirando|salvo)\M' then
    return c_nada;
  end if;
  -- 5. os dias ("todos", "todos os dias", "a semana toda" = todo dia)
  if v_t ~ ('\m' || c_dia || '\M') or v_t ~ '\m(todo dia|todos|semana toda|semana inteira)\M' then
    v_t := regexp_replace(v_t, '\mtodos os dias\M', 'todo dia', 'g');
    v_t := regexp_replace(v_t, '\m(a )?semana (toda|inteira)\M', 'todo dia', 'g');
    v_t := regexp_replace(v_t, '\mtodos\M', 'todo dia', 'g');
    begin
      v_dias := public.agenda_dias_da_semana_ditos(v_t);
    exception when sqlstate '22007' then
      return c_nada;
    end;
    v_sab := 6 = any (v_dias);
    v_dias := array_remove(v_dias, 6::smallint);
    return jsonb_build_object('tipo', 'dias', 'dias', to_jsonb(v_dias), 'sabado', v_sab);
  end if;
  -- 6. igual
  if public._e_concordancia(p_texto)
     or t ~ '^(igual|o mesmo|os mesmos|mesma coisa|mesmos dias|mantem|pode manter|isso)\M' then
    return jsonb_build_object('tipo', 'igual', 'dias', '[]'::jsonb, 'sabado', false);
  end if;
  return c_nada;
end;
$function$;

comment on function public._agenda_ler_dias_da_equipe(text) is
  'Agenda de Produção (Fase 7b, P3; §5.2): a resposta da pessoa à pergunta dos dias da semana, sem IA (normalizada por _agenda_normal), nesta ordem — vazio: nao_entendi; "nenhum", "nenhum dia", "não posso (nessa semana)", "essa semana não …", "semana de folga": nenhum; turno junto de dia útil ("terça só de manhã", "seg à tarde"; o sábado de manhã não conta): nao_entendi; "não" junto de um dia sem menos/exceto ("segunda não posso", A3): nao_entendi — nunca o "não vou" da ficha; os dias por agenda_dias_da_semana_ditos ("seg ter qui", "de segunda a quarta", "todos menos quarta"; "todos", "todos os dias", "a semana toda" = todo dia; domingo = nao_entendi; o 6 vira sabado): dias; "igual", "o mesmo", "pode manter" ou a concordância (ok, sim): igual; o resto: nao_entendi. {tipo, dias (1..5), sabado}. IMMUTABLE.';

-- Quantas mensagens a rotina da equipe ainda vai começar hoje para a pessoa (os critérios de _agenda_rotina_como_foi e de
-- _agenda_rotina_ficha): +1 pelo "como foi" (meio-dia vigente hoje e o "como foi" de hoje ainda não registrado); +1 pela ficha (dia
-- útil, meio-dia vigente no próximo dia útil, sem a ficha dele, sem o "como foi" que a leve e sem a confirmação de hoje — no dia em que
-- a confirmação sai, a ficha vai dentro do "como foi").
create or replace function public._agenda_equipe_previstas_hoje(p_payee uuid, p_hoje date, p_agora timestamptz)
 returns integer
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_modo text;
  v_am   date;
  v_n    int := 0;
begin
  if p_payee is null or p_hoje is null or p_agora is null then
    raise exception '_agenda_equipe_previstas_hoje: sem a pessoa, o dia ou a hora' using errcode = '22004';
  end if;
  v_modo := public._agenda_modo_da_equipe();
  v_am := public.agenda_somar_du(p_hoje, 1);
  if exists (select 1 from public.agenda_alocacoes a
              where a.payee_id = p_payee and a.dia = p_hoje and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva')
     and not exists (select 1 from public.agenda_equipe_mensagens m
                      where m.payee_id = p_payee and m.modo = v_modo and m.tipo = 'como_foi' and m.dia = p_hoje) then
    v_n := v_n + 1;
  end if;
  if public.agenda_dia_util(p_hoje)
     and exists (select 1 from public.agenda_alocacoes a
                  where a.payee_id = p_payee and a.dia = v_am and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva')
     and not exists (select 1 from public.agenda_equipe_mensagens m
                      where m.payee_id = p_payee and m.modo = v_modo
                        and ((m.tipo = 'ficha' and m.dia = v_am) or (m.tipo = 'como_foi' and m.leva_ficha_de = v_am)))
     and not exists (select 1 from public.agenda_equipe_mensagens m
                      where m.payee_id = p_payee and m.modo = v_modo and m.tipo = 'confirmar' and m.dia = p_hoje
                        and m.estado <> 'recusada') then
    v_n := v_n + 1;
  end if;
  return v_n;
end;
$function$;

comment on function public._agenda_equipe_previstas_hoje(uuid, date, timestamptz) is
  'Agenda de Produção (Fase 7b, P3; §3.1-7, §5.2): quantas mensagens a rotina da equipe ainda vai começar hoje para a pessoa, pelos critérios de _agenda_rotina_como_foi e _agenda_rotina_ficha — +1 pelo "como foi" (meio-dia não reserva vigente hoje e o "como foi" de hoje ainda não registrado, no modo da equipe); +1 pela ficha (dia útil, meio-dia vigente no próximo dia útil, sem ficha dele registrada, sem o "como foi" que a leve e sem a confirmação de hoje registrada: no dia em que a confirmação sai, a ficha vai dentro do "como foi" e não conta de novo). A pergunta da semana só sai quando as que já entraram + estas cabem no teto do dia (equipe_proativas_dia_max). STABLE, invoker.';

-- A pergunta à pessoa (§6.1): "Oi, Rafael! Para a semana de 16/11 a 20/11, quais dias você pode vir? Na última você disse: de seg a
-- sex. Se mudou, mande só os dias (ex.: seg ter qui) ou "nenhum". Se está igual, não precisa responder."
create or replace function public._agenda_equipe_texto_dias(p_payee uuid, p_seg date)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  v_d    jsonb;
  v_nome text;
  v_txt  text;
begin
  if p_payee is null or p_seg is null then
    raise exception '_agenda_equipe_texto_dias: sem a pessoa ou a semana' using errcode = '22004';
  end if;
  v_d := public._agenda_dias_declarados(p_payee, p_seg);
  v_nome := (select public._agenda_nome_curto(py.name) from public.payees py where py.id = p_payee);
  v_txt := format('Oi, %s! Para a semana de %s a %s, quais dias você pode vir?', v_nome, to_char(p_seg, 'DD/MM'),
                  to_char(p_seg + 4, 'DD/MM'))
           || case when v_d ->> 'fonte' = 'historico' then format(' Pelo que tenho, você costuma vir %s.', v_d ->> 'texto')
                   when v_d ->> 'fonte' in ('padrao', 'semana') and v_d ->> 'origem' = 'diarista'
                     then format(' Na última você disse: %s.', v_d ->> 'texto')
                   when v_d ->> 'fonte' in ('padrao', 'semana') then format(' Pelo que tenho, você vem %s.', v_d ->> 'texto')
                   else '' end
           || ' Se mudou, mande só os dias (ex.: seg ter qui) ou "nenhum". Se está igual, não precisa responder.'
           || case when cf.sabado_manha <> 'nunca' and cf.modo_sabado <> 'desligado'
                   then ' Se puder sábado de manhã, diga "sábado" também.' else '' end;
  return left(v_txt, 600);
end;
$function$;

comment on function public._agenda_equipe_texto_dias(uuid, date) is
  'Agenda de Produção (Fase 7b, P3; §6.1): o texto da pergunta da semana à pessoa — "Oi, Rafael! Para a semana de 16/11 a 20/11, quais dias você pode vir? Na última você disse: de seg a sex. Se mudou, mande só os dias (ex.: seg ter qui) ou "nenhum". Se está igual, não precisa responder." O que vale vem de _agenda_dias_declarados: o que ela disse ("Na última você disse"), o que o dono ou o assistente disse ("Pelo que tenho, você vem …"), a semente ("Pelo que tenho, você costuma vir …"); com sabado_manha fora de nunca e modo_sabado fora de desligado, + "Se puder sábado de manhã, diga "sábado" também." ≤ 600. STABLE, invoker.';

-- Por que perguntar os dias ao dono nesta quinta (R4.2(b); a semana p_seg): dono_sem_padrao (o dono sem dias para a semana, uma OS da
-- carteira que precisa dele o turno inteiro — diagnóstico, comissionamento, presença sempre/equipe — ou fora por padrao_do_dono, e
-- nenhuma pergunta padrao_do_dono aberta: a da vigia já pergunta, uma vez); semente (alguém da grade sem telefone cujos dias vêm só da
-- semente do histórico); sempre (o "toda quinta" do corpo). O motivo chamar é do P6 (20261101100500), que recria esta função.
create or replace function public._agenda_dias_semana_motivos(p_seg date, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  -- estrutural: a mesma janela da proposta que _agenda_vigia_padrao_do_dono lê (o "fora por padrao_do_dono" da última semana)
  c_fora_dias constant int := 7;
  cf       public.agenda_config := public._agenda_cfg();
  v_dono   uuid := public._agenda_dono(null);
  v_mot    text[] := '{}';
  v_partes jsonb := '[]'::jsonb;
  v_fora   jsonb;
  v_os     uuid[];
  v_itens  text[];
  r        record;
begin
  if p_seg is null or p_hoje is null then
    raise exception '_agenda_dias_semana_motivos: sem a semana ou o dia' using errcode = '22004';
  end if;
  if extract(isodow from p_seg)::int <> 1 then
    raise exception '_agenda_dias_semana_motivos: a semana começa na segunda (veio %)', p_seg using errcode = '22023';
  end if;

  -- dono_sem_padrao
  if 'dono_sem_padrao' = any (cf.dias_semana_motivos) and v_dono is not null
     and public._agenda_dias_declarados(v_dono, p_seg) ->> 'fonte' = 'nenhum'
     and not exists (select 1 from public.agenda_perguntas q where q.tipo = 'padrao_do_dono' and q.estado = 'aberta') then
    select p.fora into v_fora from public.agenda_propostas p
     where p.modo = cf.modo_proposta and (p.criada_em at time zone 'America/Sao_Paulo')::date > p_hoje - c_fora_dias
     order by p.criada_em desc, p.id desc limit 1;
    select coalesce(array_agg(z.os order by z.dele desc, z.numero collate "C", z.os), '{}'::uuid[]),
           coalesce(array_agg(case when z.motivo is not null
                                   then regexp_replace(public._agenda_rotulo_da_os(z.os), '\)$', ', ' || z.motivo || ')')
                                   else public._agenda_rotulo_da_os(z.os) end
                              order by z.dele desc, z.numero collate "C", z.os), '{}'::text[])
      into v_os, v_itens
      from (select k.service_order_id as os, k.numero, m.x ->> 'presenca' as presenca, m.x ->> 'regra_motivo' as motivo,
                   coalesce(m.x ->> 'regra_motivo', '') in ('diagnóstico', 'comissionamento') as dele,
                   exists (select 1 from jsonb_array_elements(coalesce(v_fora, '[]'::jsonb)) f
                            where f ->> 'motivo' in ('padrao_do_dono', 'so_com_voce') and f ->> 'os' = k.service_order_id::text) as fora
              from public.os_carteira(p_hoje) k
              cross join lateral (select public.agenda_meios_da_os(k.service_order_id, p_hoje) as x) m) z
     where z.presenca in ('sempre', 'equipe') or z.dele or z.fora;
    if cardinality(v_os) > 0 then
      v_mot := v_mot || 'dono_sem_padrao'::text;
      v_partes := v_partes || jsonb_build_array(jsonb_build_object('motivo', 'dono_sem_padrao', 'os', to_jsonb(v_os),
        'texto', format('%s %s de você em campo e eu não sei seus dias: conto que você só abre e fecha.',
                        public._agenda_lista(v_itens, 2), case when cardinality(v_os) = 1 then 'precisa' else 'precisam' end)));
    end if;
  end if;

  -- semente
  if 'semente' = any (cf.dias_semana_motivos) then
    for r in select g.payee_id, g.pessoa, d.v
               from (select distinct k.payee_id, k.pessoa from public.agenda_capacidade(p_seg, p_seg + 5, p_hoje) k where not k.eh_dono) g
               cross join lateral (select public._agenda_dias_declarados(g.payee_id, p_seg) as v) d
              where d.v ->> 'fonte' = 'historico' and not public._agenda_equipe_tem_telefone(g.payee_id)
              order by g.pessoa, g.payee_id loop
      if not ('semente' = any (v_mot)) then
        v_mot := v_mot || 'semente'::text;
      end if;
      v_partes := v_partes || jsonb_build_array(jsonb_build_object('motivo', 'semente', 'payee', r.payee_id,
        'texto', format('%s (sem telefone): conto %s, pelo que veio nas últimas %s semanas.', r.pessoa, r.v ->> 'texto',
                        cf.medicao_semanas)));
    end loop;
  end if;

  -- sempre (o "toda quinta" do corpo da spec)
  if 'sempre' = any (cf.dias_semana_motivos) then
    v_mot := v_mot || 'sempre'::text;
  end if;
  return jsonb_build_object('motivos', to_jsonb(v_mot), 'partes', v_partes);
end;
$function$;

comment on function public._agenda_dias_semana_motivos(date, date) is
  'Agenda de Produção (Fase 7b, P3; R4.2(b), AG7-02/AG7-03): por que a pergunta dias_semana nasce para o dono na semana de p_seg — só os motivos de agenda_config.dias_semana_motivos: dono_sem_padrao (o dono sem dias para a semana, _agenda_dias_declarados fonte nenhum; alguma OS da carteira precisa dele o turno inteiro — diagnóstico, comissionamento, presença sempre ou equipe — ou ficou fora por padrao_do_dono/so_com_voce na proposta da última semana; e nenhuma pergunta padrao_do_dono aberta: a da vigia pergunta uma vez, a 7b não repete): "Rodrigo (OS-00096, diagnóstico) precisa de você em campo e eu não sei seus dias: conto que você só abre e fecha."; semente (alguém da grade sem telefone cujos dias da semana vêm só da semente do histórico): "Fulano (sem telefone): conto de ter a sex, pelo que veio nas últimas 8 semanas."; sempre (toda quinta). {motivos [...], partes [{motivo, texto, os | payee}]}; sem motivo, motivos vazio (nada nasce). O motivo chamar é do P6 (20261101100500), que recria ESTA função. STABLE, invoker, sem grant (só agenda_equipe_semana a chama).';

-- A rodada da semana da equipe (task-automations, passo 0b1, a cada tique; spec §5.2 com o R4). Cada passo no seu bloco: o que falha vai
-- a app_error_logs (agenda, equipe_semana:<passo>) e os outros rodam; query_canceled sobe. Com modo_dias e modo_cadastro desligados,
-- {rodou: false}.
create or replace function public.agenda_equipe_semana(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  -- estrutural (R4.2(d)): a 1ª pergunta à equipe em ligado espera a chamada respondida ou vencida, mas não mais que isto desde a
  -- criação dela; a chamada que ninguém viu nesse tempo vence pela limpeza da vigia (expira_em)
  c_espera_chamada constant interval := interval '7 days';
  -- estrutural (R4.2(b)): na quinta, com quem chamar ligado, a pergunta do dono espera o diário de hoje do gestor até o tique de
  -- equipe_hora_dias + isto (o das 17:15); depois nasce sem o motivo chamar
  c_espera_diario  constant interval := interval '30 minutes';
  cf          public.agenda_config;
  v_t0        timestamptz := clock_timestamp();
  v_local     timestamp := p_agora at time zone 'America/Sao_Paulo';
  v_dono      uuid;
  v_hora_ok   boolean;
  v_diario    boolean;
  v_qm        text;
  v_gente     jsonb;
  v_sd_nomes  text[];
  v_sd_det    text[];
  v_sd_um     text;
  v_sai_nomes text[];
  v_sai_em    text[];
  v_cont      jsonb := '{}'::jsonb;
  v_erros     int := 0;
  v_falhas    jsonb := '[]'::jsonb;
  v_fez       boolean := false;
  v_estado    text;
  v_msg       text;
  v_passo     text;
  e           jsonb;
  r           record;
  v_id        uuid;
  v_n         int;
  v_m         int;
  v_txt       text;
  v_fim       text;
  v_ps        jsonb;
  v_seg       date;
  v_r         jsonb;
  v_c         jsonb;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_equipe_semana: sem o dia ou a hora' using errcode = '22004';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  cf := public._agenda_cfg();
  if cf.modo_dias = 'desligado' and cf.modo_cadastro = 'desligado' then
    return jsonb_build_object('rodou', false, 'modos', jsonb_build_object('dias', cf.modo_dias, 'cadastro', cf.modo_cadastro));
  end if;
  v_dono := public._agenda_dono(null);
  v_hora_ok := v_local::time >= cf.equipe_hora_dias;
  -- os passos de uma vez por dia (a d14 e o cadastro novo): no 1º tique a partir de equipe_hora_dias (a rodada do dia com "diario")
  v_diario := v_hora_ok and cf.modo_cadastro <> 'desligado'
              and not exists (select 1 from public.agenda_vigia_rodadas x
                               where x.rotina = 'equipe_semana' and x.p_hoje = p_hoje and x.contagens ? 'diario');
  v_qm := case when cf.modo_cadastro = 'ligado' then 'ligado' else 'sombra' end;
  v_ps := public._agenda_semana_perguntada(p_hoje);

  -- A equipe da grade (agenda_capacidade de hoje a +13 dias, sem o dono), uma vez por rodada, só quando um passo precisa: o padrão
  -- vivo (dias fixos), o telefone (a régua do registro), a lista da rotina, as datas ditas de quem vem sob demanda e o "conto com".
  if v_diario or (cf.modo_dias <> 'desligado' and v_hora_ok and extract(isodow from p_hoje)::int <> 7
                  and p_hoje between (v_ps ->> 'quinta')::date and (v_ps ->> 'pode_perguntar_ate')::date) then
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', g.payee_id, 'nome', g.pessoa, 'padrao', p.dias is not null, 'dias', to_jsonb(coalesce(p.dias, '{}'::smallint[])),
             'origem', p.origem, 'dito_em', p.dito_em, 'fone', public._agenda_equipe_tem_telefone(g.payee_id),
             'contato', c.payee_id is not null, 'rotina', coalesce(c.recebe_rotina and c.parou_em is null, false),
             'todo_nao', exists (select 1 from public.agenda_disponibilidade i
                                  where i.payee_id = g.payee_id and i.substituida_em is null and i.turno is null
                                    and i.situacao = 'indisponivel' and i.dias_semana @> array[1, 2, 3, 4, 5]::smallint[]),
             'datas', to_jsonb(coalesce(dt.datas, '{}'::date[])),
             'conta', case when p.dias is null then null
                           when p.origem = 'dono'
                             then format('%s: você disse %s', g.pessoa,
                                         case when p.dias = array[1, 2, 3, 4, 5]::smallint[] then 'todo dia útil'
                                              else public._agenda_dias_curtos(p.dias) end)
                           when p.origem = 'diarista'
                             then format('%s disse %s em %s', g.pessoa, public._agenda_dias_curtos(p.dias),
                                         to_char(p.dito_em at time zone 'America/Sao_Paulo', 'DD/MM'))
                           when p.origem = 'historico'
                             then format('%s %s, pelo que veio nas últimas %s semanas', g.pessoa, public._agenda_dias_curtos(p.dias),
                                         cf.medicao_semanas)
                           else format('%s %s (anotado em %s)', g.pessoa, public._agenda_dias_curtos(p.dias),
                                       to_char(p.dito_em at time zone 'America/Sao_Paulo', 'DD/MM')) end)
             order by g.pessoa, g.payee_id), '[]'::jsonb)
      into v_gente
      from (select distinct k.payee_id, k.pessoa from public.agenda_capacidade(p_hoje, p_hoje + 13, p_hoje) k where not k.eh_dono) g
      cross join lateral (
        select nullif(array(select distinct x from public.agenda_disponibilidade d, unnest(d.dias_semana) x
                             where d.payee_id = g.payee_id and d.substituida_em is null and d.dias_semana is not null
                               and d.situacao in ('disponivel', 'confirmada') order by 1), '{}'::smallint[]) as dias,
               (select d.origem from public.agenda_disponibilidade d
                 where d.payee_id = g.payee_id and d.substituida_em is null and d.dias_semana is not null
                   and d.situacao in ('disponivel', 'confirmada') order by d.criado_em desc, d.id desc limit 1) as origem,
               (select max(d.criado_em) from public.agenda_disponibilidade d
                 where d.payee_id = g.payee_id and d.substituida_em is null and d.dias_semana is not null
                   and d.situacao in ('disponivel', 'confirmada')) as dito_em) p
      left join public.agenda_equipe_contato c on c.payee_id = g.payee_id
      left join lateral (
        select array_agg(distinct x::date order by x::date) as datas
          from public.agenda_disponibilidade d,
               generate_series(greatest(lower(d.periodo), p_hoje), least(upper(d.periodo) - 1, p_hoje + 13), interval '1 day') x
         where d.payee_id = g.payee_id and d.substituida_em is null and d.periodo is not null
           and d.situacao in ('disponivel', 'confirmada') and d.periodo && daterange(p_hoje, p_hoje + 13, '[]')) dt on true;
  end if;

  -- ── 1. contatos: a regra d14 (no dia do plano, uma vez): quem tem dias fixos, telefone e nenhuma linha na lista da rotina ───────
  if v_diario and extract(isodow from p_hoje)::int = cf.dia_do_plano then
    begin
      v_passo := 'contatos';
      v_n := 0;
      v_m := 0;
      for e in select x from jsonb_array_elements(v_gente) x
                where (x ->> 'padrao')::boolean and (x ->> 'fone')::boolean and not (x ->> 'contato')::boolean loop
        if cf.modo_cadastro = 'ligado' then
          insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em)
          values ((e ->> 'id')::uuid, true, 'regra', p_agora)
          on conflict (payee_id) do nothing
          returning payee_id into v_id;
          continue when v_id is null;
          insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, payee_id, depois, texto, desfazivel_ate)
          values (clock_timestamp(), p_hoje, true, 'vigia', 'equipe', (e ->> 'id')::uuid,
                  jsonb_build_object('motivo', 'regra_d14', 'payee', e ->> 'id', 'dias', e -> 'dias'),
                  left(format('Pus %s na rotina da equipe (vem %s e tem telefone): ele passa a receber a ficha e a pergunta dos dias. *desfaz* tira.',
                              e ->> 'nome',
                              public._agenda_dias_curtos(array(select x::smallint from jsonb_array_elements_text(e -> 'dias') x))), 400),
                  p_agora + cf.desfazer_validade);
          v_n := v_n + 1;
        else
          v_m := v_m + 1;
        end if;
      end loop;
      v_cont := v_cont || jsonb_build_object('contatos', jsonb_build_object('pus', v_n, 'em_teste_poria', v_m));
      v_fez := v_fez or v_n + v_m > 0;
    exception
      when query_canceled then raise;
      when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        v_erros := v_erros + 1;
        v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
        perform public.log_app_error('db', format('semana da equipe, passo %s: %s', v_passo, v_msg), 'agenda',
                                     'equipe_semana:' || v_passo, 'error',
                                     jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end if;

  -- ── 2. cadastro: a chamada, o telefone e o contato (a cada tique o prazo e o que fecha sozinho; o novo, uma vez por dia) ─────────
  if cf.modo_cadastro <> 'desligado' then
    begin
      v_passo := 'cadastro';
      v_c := '{}'::jsonb;
      -- a chamada vista pela 1ª vez ganha o prazo (o mecanismo da 7a: equipe_chamada_prazo_du dias úteis depois de vista, às veto_hora)
      with x as (
        update public.agenda_perguntas q
           set veto_ate = public._agenda_veto_ate(q.mostrada_em, cf.equipe_chamada_prazo_du),
               expira_em = greatest(coalesce(q.expira_em, q.criada_em),
                                    public._agenda_veto_ate(q.mostrada_em, cf.equipe_chamada_prazo_du) + cf.desfazer_validade)
         where q.tipo = 'equipe_cadastro' and q.chave like 'equipe_cadastro:chamada:%' and q.estado = 'aberta'
           and q.veto_ate is null and q.mostrada_vezes > 0 and q.mostrada_em is not null
        returning 1)
      select count(*) into v_n from x;
      if v_n > 0 then v_c := v_c || jsonb_build_object('prazo', v_n); end if;
      -- sem resposta até o prazo, depois de vista: segue como está
      with x as (
        update public.agenda_perguntas q
           set estado = 'vencida', resolvida_motivo = 'sem resposta: segui como estava'
         where q.tipo = 'equipe_cadastro' and q.chave like 'equipe_cadastro:chamada:%' and q.estado = 'aberta'
           and q.veto_ate is not null and p_agora > q.veto_ate and q.mostrada_vezes > 0 and q.mostrada_em < q.veto_ate
        returning 1)
      select count(*) into v_n from x;
      if v_n > 0 then v_c := v_c || jsonb_build_object('vencidas', v_n); end if;
      -- o telefone que apareceu e quem entrou na lista fecham a pergunta deles
      with x as (
        update public.agenda_perguntas q
           set estado = 'resolvida', resolvida_motivo = 'telefone cadastrado'
         where q.tipo = 'equipe_cadastro' and q.chave like 'equipe_cadastro:telefone:%' and q.estado = 'aberta'
           and q.payee_id is not null and public._agenda_equipe_tem_telefone(q.payee_id)
        returning 1)
      select count(*) into v_n from x;
      if v_n > 0 then v_c := v_c || jsonb_build_object('telefone_cadastrado', v_n); end if;
      with x as (
        update public.agenda_perguntas q
           set estado = 'resolvida', resolvida_motivo = 'entrou na rotina'
         where q.tipo = 'equipe_cadastro' and q.chave like 'equipe_cadastro:contato:%' and q.estado = 'aberta'
           and exists (select 1 from public.agenda_equipe_contato c
                        where c.payee_id = q.payee_id and c.recebe_rotina and c.parou_em is null)
        returning 1)
      select count(*) into v_n from x;
      if v_n > 0 then v_c := v_c || jsonb_build_object('entrou_na_rotina', v_n); end if;

      if v_diario then
        v_n := (select count(*)::int from public.agenda_perguntas q
                 where q.tipo = 'equipe_cadastro' and q.estado = 'aberta' and q.modo = v_qm);
        -- (a) a chamada (R4.1-2): nunca houve, ou a última tem mais de equipe_chamada_dias dias
        if v_n < cf.equipe_cadastro_abertas_max
           and not exists (select 1 from public.agenda_perguntas q
                            where q.chave like 'equipe_cadastro:chamada:%' and q.modo = v_qm
                              and (q.estado = 'aberta' or q.criada_em > p_agora - make_interval(days => cf.equipe_chamada_dias))) then
          -- quem conta
          v_txt := (select string_agg(x ->> 'conta', '; ' order by o) from jsonb_array_elements(v_gente) with ordinality t(x, o)
                     where (x ->> 'padrao')::boolean);
          v_txt := case when v_txt is null then 'Na agenda não conto com ninguém da equipe.' else 'Na agenda conto com ' || v_txt || '.' end;
          -- quem conta e não tem telefone
          v_txt := v_txt || coalesce((select string_agg(format(' %s não tem telefone no cadastro: sem ele não mando a ficha; para pôr, diga: o telefone do %s é …',
                                                                x ->> 'nome', x ->> 'nome'), '' order by o)
                                        from jsonb_array_elements(v_gente) with ordinality t(x, o) where not (x ->> 'fone')::boolean), '');
          -- quem vem sob demanda (só nas datas que o dono diz)
          select coalesce(array_agg(x ->> 'nome' order by o), '{}'::text[]),
                 coalesce(array_agg((x ->> 'nome') || ' '
                                    || public._agenda_dias_texto(array(select y::date from jsonb_array_elements_text(x -> 'datas') y))
                                    order by o), '{}'::text[]),
                 min(public._agenda_dias_texto(array(select y::date from jsonb_array_elements_text(x -> 'datas') y)))
            into v_sd_nomes, v_sd_det, v_sd_um
            from jsonb_array_elements(v_gente) with ordinality t(x, o)
           where not (x ->> 'padrao')::boolean and jsonb_array_length(x -> 'datas') > 0;
          v_txt := v_txt || case
            when cardinality(v_sd_nomes) = 1 then format(' %s eu só conto nos dias que você diz (%s).', v_sd_nomes[1], v_sd_um)
            when cardinality(v_sd_nomes) > 1 then format(' %s eu só conto nos dias que você diz (%s).',
                                                         public._agenda_lista(v_sd_nomes, null), array_to_string(v_sd_det, '; '))
            else ' Quem você chama quando precisa eu só conto nos dias que você disser (ex.: Mateus vem qua e qui).' end;
          -- quem saiu (tinha linha, nenhuma viva, a última trocada há até equipe_chamada_dias dias; na ordem do cadastro)
          select coalesce(array_agg(z.nomes order by z.em), '{}'::text[]),
                 coalesce(array_agg(to_char(z.em, 'DD/MM') order by z.em), '{}'::text[]), coalesce(sum(z.n), 0)::int
            into v_sai_nomes, v_sai_em, v_m
            from (select y.em, count(*)::int as n, public._agenda_lista(array_agg(y.nome order by y.desde, y.nome), null) as nomes
                    from (select public._agenda_nome_curto(py.name) as nome, py.created_at as desde,
                                 (max(d.substituida_em) at time zone 'America/Sao_Paulo')::date as em
                            from public.agenda_disponibilidade d join public.payees py on py.id = d.payee_id
                           where d.payee_id is distinct from v_dono
                             and not exists (select 1 from jsonb_array_elements(v_gente) g where (g ->> 'id')::uuid = d.payee_id)
                           group by d.payee_id, py.name, py.created_at
                          having bool_and(d.substituida_em is not null)
                             and max(d.substituida_em) >= p_agora - make_interval(days => cf.equipe_chamada_dias)) y
                   group by y.em) z;
          if v_m > 0 then
            v_txt := v_txt || ' '
                     || public._agenda_lista(array(select case when i = 1
                                                               then format('%s %s da agenda em %s', v_sai_nomes[i],
                                                                           case when v_m = 1 then 'saiu' else 'saíram' end, v_sai_em[i])
                                                               else format('%s em %s', v_sai_nomes[i], v_sai_em[i]) end
                                                     from generate_subscripts(v_sai_nomes, 1) i order by i), null)
                     || format(': não conto com %s.', case when v_m = 1 then 'ele' else 'eles' end);
          end if;
          v_fim := format(' Está certo? 1) Está certo (recomendo); 2) Mudou. Se não responder em %s %s depois de ver, sigo assim.',
                          cf.equipe_chamada_prazo_du, case when cf.equipe_chamada_prazo_du = 1 then 'dia útil' else 'dias úteis' end);
          v_txt := public._agenda_corta(v_txt, 600 - char_length(v_fim)) || v_fim;
          insert into public.agenda_perguntas (tipo, chave, perda_em, texto, opcoes, recomendacao, modo, criada_em, expira_em)
          values ('equipe_cadastro', 'equipe_cadastro:chamada:' || (p_hoje - (extract(isodow from p_hoje)::int - 1)), null, v_txt,
                  jsonb_build_array(jsonb_build_object('n', 1, 'texto', 'Está certo', 'efeito', jsonb_build_object('chamada', 'ok')),
                                    jsonb_build_object('n', 2, 'texto', 'Mudou', 'efeito', jsonb_build_object('chamada', 'mudou'))),
                  1, v_qm, p_agora, p_agora + c_espera_chamada)
          on conflict (chave, modo) where estado = 'aberta' do nothing
          returning id into v_id;
          if v_id is not null then
            v_n := v_n + 1;
            v_c := v_c || jsonb_build_object('chamada', 1);
          end if;
        end if;
        -- (b) o telefone de quem está na grade e não tem (R4.1-1), quando a chamada aberta ainda não o pede
        for e in select x from jsonb_array_elements(v_gente) x where not (x ->> 'fone')::boolean loop
          exit when v_n >= cf.equipe_cadastro_abertas_max;
          continue when exists (select 1 from public.agenda_perguntas q
                                 where q.chave like 'equipe_cadastro:chamada:%' and q.modo = v_qm and q.estado = 'aberta'
                                   and position(format('o telefone do %s é', e ->> 'nome') in q.texto) > 0);
          v_txt := case
            when (e ->> 'padrao')::boolean
              then format('%s não tem telefone no cadastro: sem ele não mando a ficha da véspera (conto com %s). Para pôr, diga: o telefone do %s é …',
                          e ->> 'nome', e ->> 'conta', e ->> 'nome')
            else format('%s não tem telefone no cadastro: sem ele não mando a ficha dos dias em que ele vem%s. Para pôr, diga: o telefone do %s é …',
                        e ->> 'nome',
                        coalesce(' (' || nullif(public._agenda_dias_texto(array(select y::date from jsonb_array_elements_text(e -> 'datas') y)), '') || ')', ''),
                        e ->> 'nome') end;
          insert into public.agenda_perguntas (tipo, chave, payee_id, texto, opcoes, modo, criada_em)
          values ('equipe_cadastro', 'equipe_cadastro:telefone:' || (e ->> 'id'), (e ->> 'id')::uuid, left(v_txt, 600), '[]'::jsonb,
                  v_qm, p_agora)
          on conflict (chave, modo) where estado = 'aberta' do nothing
          returning id into v_id;
          if v_id is not null then
            v_n := v_n + 1;
            v_c := v_c || jsonb_build_object('telefone', coalesce((v_c ->> 'telefone')::int, 0) + 1);
          end if;
        end loop;
        -- (c) o contato (R4.1-6): na grade, com telefone, sem dias fixos (vem sob demanda) e sem linha na lista da rotina
        for e in select x from jsonb_array_elements(v_gente) x
                  where (x ->> 'fone')::boolean and not (x ->> 'padrao')::boolean and not (x ->> 'contato')::boolean loop
          exit when v_n >= cf.equipe_cadastro_abertas_max;
          insert into public.agenda_perguntas (tipo, chave, payee_id, texto, opcoes, recomendacao, modo, criada_em)
          values ('equipe_cadastro', 'equipe_cadastro:contato:' || (e ->> 'id'), (e ->> 'id')::uuid,
                  format('%s tem telefone, mas não está na rotina da equipe. Ponho? Ele passa a receber a ficha da véspera nos dias em que vier (os dias dele quem diz é você). 1) Ponho (recomendo); 2) Não.',
                         e ->> 'nome'),
                  jsonb_build_array(jsonb_build_object('n', 1, 'texto', 'Ponho', 'efeito', jsonb_build_object('contato', 'por')),
                                    jsonb_build_object('n', 2, 'texto', 'Não', 'efeito', jsonb_build_object('contato', 'nao'))),
                  1, v_qm, p_agora)
          on conflict (chave, modo) where estado = 'aberta' do nothing
          returning id into v_id;
          if v_id is not null then
            v_n := v_n + 1;
            v_c := v_c || jsonb_build_object('contato', coalesce((v_c ->> 'contato')::int, 0) + 1);
          end if;
        end loop;
        v_cont := v_cont || jsonb_build_object('diario', true);
        v_fez := true;
      end if;
      if v_c <> '{}'::jsonb then
        v_cont := v_cont || jsonb_build_object('cadastro', v_c);
        v_fez := true;
      end if;
    exception
      when query_canceled then raise;
      when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        v_erros := v_erros + 1;
        v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
        perform public.log_app_error('db', format('semana da equipe, passo %s: %s', v_passo, v_msg), 'agenda',
                                     'equipe_semana:' || v_passo, 'error',
                                     jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end if;

  -- ── 3. fechar: a semana cujo prazo passou (uma vez por semana; só com alguém perguntado ou a pergunta do dono dessa semana) ──────
  if cf.modo_dias <> 'desligado' then
    begin
      v_passo := 'fechar';
      v_r := public._agenda_semana_perguntada(p_hoje - 7);
      if (v_r ->> 'prazo_em')::timestamptz > p_agora then
        v_r := public._agenda_semana_perguntada(p_hoje - 14);
      end if;
      v_seg := (v_r ->> 'seg')::date;
      if (v_r ->> 'prazo_em')::timestamptz <= p_agora
         and (exists (select 1 from public.agenda_equipe_mensagens m where m.tipo = 'dias' and m.dia = v_seg)
              or exists (select 1 from public.agenda_perguntas q where q.tipo = 'dias_semana' and q.dia = v_seg))
         and not exists (select 1 from public.agenda_acoes a
                          where a.tipo = 'equipe' and a.depois ->> 'motivo' = 'dias_da_semana' and a.depois ->> 'semana' = v_seg::text) then
        declare
          v_semana text := to_char(v_seg, 'DD/MM');
          v_itens  text[] := '{}';
          v_sem    text[] := '{}';
          v_conf   text[] := '{}';
          v_pes    jsonb := '[]'::jsonb;
          v_confl  jsonb := '[]'::jsonb;
          v_sr     uuid[];
          v_d      jsonb;
          v_item   text;
        begin
          with x as (
            update public.agenda_equipe_mensagens m set estado = 'sem_resposta'
             where m.tipo = 'dias' and m.dia = v_seg and m.estado = 'enfileirada'
            returning m.payee_id)
          select coalesce(array_agg(x.payee_id), '{}'::uuid[]) into v_sr from x;
          update public.agenda_perguntas q set estado = 'vencida', resolvida_motivo = 'sem resposta: vale o que estava'
           where q.tipo = 'dias_semana' and q.dia = v_seg and q.estado = 'aberta';
          -- quem não respondeu (a mensagem que saiu ou, em teste, a registrada)
          v_sr := v_sr || array(select m.payee_id from public.agenda_equipe_mensagens m
                                 where m.tipo = 'dias' and m.dia = v_seg and m.modo = 'sombra' and m.estado = 'registrada');
          for r in select distinct k.payee_id, k.pessoa, k.eh_dono, py.phone
                     from public.agenda_capacidade(v_seg, v_seg + 5, p_hoje) k join public.payees py on py.id = k.payee_id
                    order by k.eh_dono, k.pessoa loop
            v_d := public._agenda_dias_declarados(r.payee_id, v_seg);
            continue when v_d ->> 'fonte' = 'nenhum' and not r.eh_dono;
            v_pes := v_pes || jsonb_build_array(jsonb_build_object('payee', r.payee_id, 'dias', v_d -> 'dias', 'sabado', v_d -> 'sabado',
                                                                   'fonte', v_d ->> 'fonte', 'dito_em', v_d ->> 'dito_em'));
            if r.eh_dono then
              v_item := case when jsonb_array_length(v_d -> 'dias') = 0 and not (v_d ->> 'sabado')::boolean then 'você só abre e fecha'
                             else 'você em campo ' || (v_d ->> 'texto') end;
            elsif r.payee_id = any (v_sr) and v_d ->> 'fonte' <> 'semana' then
              v_sem := v_sem || format('%s não respondeu: vale a última (%s).', r.pessoa, v_d ->> 'texto');
              continue;
            elsif v_d ->> 'fonte' = 'historico' then
              v_item := format('%s %s, pelo histórico', r.pessoa, v_d ->> 'texto')
                        || case when length(regexp_replace(coalesce(r.phone, ''), '\D', '', 'g')) < 10 then ' (sem telefone)' else '' end;
            else
              v_item := r.pessoa || ' '
                        || case when jsonb_array_length(v_d -> 'dias') = 0 and not (v_d ->> 'sabado')::boolean then 'não vem'
                                else v_d ->> 'texto' end
                        || case when v_d ->> 'origem' = 'dono' then ' (você disse)'
                                when v_d ->> 'origem' = 'diarista'
                                  then format(' (disse em %s)', to_char((v_d ->> 'dito_em')::timestamptz at time zone 'America/Sao_Paulo', 'DD/MM'))
                                else '' end;
            end if;
            v_itens := v_itens || v_item;
          end loop;
          -- o que a pessoa disse por cima do que o dono tinha combinado com ela (mantive o do dono)
          for r in select m.payee_id, public._agenda_nome_curto(py.name) as nome, c.x as conflito, m.leitura -> 'dias' as ditos
                     from public.agenda_equipe_mensagens m join public.payees py on py.id = m.payee_id
                     cross join lateral jsonb_array_elements(coalesce(m.leitura -> 'conflitos', '[]'::jsonb)) c(x)
                    where m.tipo = 'dias' and m.dia = v_seg and m.estado = 'respondida'
                    order by py.name, (c.x ->> 'dia')::date loop
            v_confl := v_confl || jsonb_build_array(r.conflito || jsonb_build_object('payee', r.payee_id));
            v_conf := v_conf || case
              when r.conflito ->> 'situacao_do_dono' in ('disponivel', 'confirmada')
                   and not coalesce(r.ditos @> to_jsonb(extract(isodow from (r.conflito ->> 'dia')::date)::int), false)
                then format('%s não incluiu %s, que você tinha combinado com ele: mantive o que você disse.', r.nome,
                            public._dia_curto((r.conflito ->> 'dia')::date))
              when r.conflito ->> 'situacao_do_dono' = 'indisponivel'
                   and coalesce(r.ditos @> to_jsonb(extract(isodow from (r.conflito ->> 'dia')::date)::int), false)
                then format('%s disse que vem %s, que você tinha tirado: mantive o que você disse.', r.nome,
                            public._dia_curto((r.conflito ->> 'dia')::date))
              else null end;
          end loop;
          v_txt := format('Dias da semana de %s: %s.', v_semana,
                          coalesce(nullif(array_to_string(v_itens, '; '), ''), 'ninguém da equipe'))
                   || coalesce(' ' || nullif(array_to_string(v_conf, ' '), ''), '')
                   || coalesce(' ' || nullif(array_to_string(v_sem, ' '), ''), '');
          insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, depois, texto)
          values (clock_timestamp(), p_hoje, cf.modo_dias = 'ligado', 'vigia', 'equipe',
                  jsonb_build_object('motivo', 'dias_da_semana', 'semana', v_seg, 'pessoas', v_pes, 'conflitos', v_confl),
                  public._agenda_corta(v_txt, 400));
          v_cont := v_cont || jsonb_build_object('fechar', jsonb_build_object('semana', v_seg, 'sem_resposta', cardinality(v_sr)));
          v_fez := true;
        end;
      end if;
    exception
      when query_canceled then raise;
      when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        v_erros := v_erros + 1;
        v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
        perform public.log_app_error('db', format('semana da equipe, passo %s: %s', v_passo, v_msg), 'agenda',
                                     'equipe_semana:' || v_passo, 'error',
                                     jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end if;

  -- ── 4. perguntar: a quem tem dias fixos e telefone (da quinta até pode_perguntar_ate, a partir de equipe_hora_dias, nunca no
  -- domingo, no teto do dia sem tirar a vaga da ficha nem do "como foi"); ao dono, só na quinta e só com motivo ─────────────────────
  if cf.modo_dias <> 'desligado' and v_hora_ok and extract(isodow from p_hoje)::int <> 7
     and p_hoje between (v_ps ->> 'quinta')::date and (v_ps ->> 'pode_perguntar_ate')::date then
    begin
      v_passo := 'perguntar';
      v_seg := (v_ps ->> 'seg')::date;
      v_c := '{}'::jsonb;
      -- a equipe; a 1ª vez em ligado (com o cadastro ligado) espera a chamada respondida ou vencida, no máximo c_espera_chamada
      if cf.modo_dias = 'ligado' and cf.modo_cadastro = 'ligado'
         and not exists (select 1 from public.agenda_equipe_mensagens m where m.tipo = 'dias' and m.modo = 'ligado')
         and exists (select 1 from public.agenda_perguntas q
                      where q.chave like 'equipe_cadastro:chamada:%' and q.modo = 'ligado' and q.estado = 'aberta'
                        and q.criada_em > p_agora - c_espera_chamada) then
        v_c := v_c || jsonb_build_object('espera_chamada', true);
      else
        for e in select x from jsonb_array_elements(v_gente) x
                  where (x ->> 'rotina')::boolean and (x ->> 'padrao')::boolean and (x ->> 'fone')::boolean
                    and not (x ->> 'todo_nao')::boolean loop
          continue when exists (select 1 from public.agenda_equipe_mensagens m
                                 where m.payee_id = (e ->> 'id')::uuid and m.tipo = 'dias' and m.dia = v_seg
                                   and m.modo = case when cf.modo_equipe = 'ligado' and cf.modo_dias = 'ligado' then 'ligado' else 'sombra' end);
          if public._agenda_equipe_no_dia((e ->> 'id')::uuid, p_hoje, false, null)
             + public._agenda_equipe_previstas_hoje((e ->> 'id')::uuid, p_hoje, p_agora) < cf.equipe_proativas_dia_max then
            v_r := public._agenda_equipe_registrar((e ->> 'id')::uuid, v_seg, 'dias',
                                                   public._agenda_equipe_texto_dias((e ->> 'id')::uuid, v_seg), p_agora);
            v_c := v_c || jsonb_build_object(coalesce(v_r ->> 'estado', 'nada'),
                                             coalesce((v_c ->> coalesce(v_r ->> 'estado', 'nada'))::int, 0) + 1);
          else
            v_c := v_c || jsonb_build_object('adiada', coalesce((v_c ->> 'adiada')::int, 0) + 1);
          end if;
        end loop;
      end if;
      -- o dono: só na quinta, uma vez por semana, só com motivo (R4.2(b)); decidido uma vez no dia (o "sem motivo" da 1ª rodada que
      -- decidiu vale até a quinta seguinte: a rodada grava a linha com ele)
      if cf.dono_dias_semanal and v_dono is not null and p_hoje = (v_ps ->> 'quinta')::date
         and not exists (select 1 from public.agenda_perguntas q
                          where q.chave = format('dias_semana:%s:%s', v_dono, v_seg)
                            and q.modo = case when cf.modo_dias = 'ligado' then 'ligado' else 'sombra' end)
         and not exists (select 1 from public.agenda_vigia_rodadas x
                          where x.rotina = 'equipe_semana' and x.p_hoje = p_hoje
                            and x.contagens -> 'perguntar' ->> 'dono' = 'sem_motivo') then
        if cf.modo_chamar = 'ligado' and 'chamar' = any (cf.dias_semana_motivos)
           and v_local::time < cf.equipe_hora_dias + c_espera_diario
           and not exists (select 1 from public.agenda_gestor_dia g
                            where g.dia = p_hoje and g.chamar ->> 'calculado_em' is not null
                              and ((g.chamar ->> 'calculado_em')::timestamptz at time zone 'America/Sao_Paulo')::date = p_hoje) then
          v_c := v_c || jsonb_build_object('dono', 'espera_o_diario');
        else
          v_r := public._agenda_dias_semana_motivos(v_seg, p_hoje);
          if jsonb_array_length(v_r -> 'motivos') = 0 then
            v_c := v_c || jsonb_build_object('dono', 'sem_motivo');
          else
            declare
              v_dsp  boolean := v_r -> 'motivos' ? 'dono_sem_padrao';
              v_contam text[];
              v_ops  jsonb;
              v_ini  text;
            begin
              v_contam := array(select z.item
                               from (select k.payee_id, k.pessoa,
                                            k.pessoa || ' ' || (d.v ->> 'texto')
                                            || case when d.v ->> 'fonte' = 'historico' then ' (pelo histórico)'
                                                    when d.v ->> 'origem' = 'dono' then ' (você disse)'
                                                    when d.v ->> 'origem' = 'diarista'
                                                      then format(' (disse em %s)', to_char((d.v ->> 'dito_em')::timestamptz at time zone 'America/Sao_Paulo', 'DD/MM'))
                                                    else '' end as item
                                       from (select distinct c.payee_id, c.pessoa from public.agenda_capacidade(v_seg, v_seg + 5, p_hoje) c
                                              where not c.eh_dono) k
                                       cross join lateral (select public._agenda_dias_declarados(k.payee_id, v_seg) as v) d
                                      where d.v ->> 'fonte' <> 'nenhum'
                                        and (jsonb_array_length(d.v -> 'dias') > 0 or (d.v ->> 'sabado')::boolean)) z
                             order by z.pessoa, z.payee_id);
              v_ini := format('Semana de %s: ', to_char(v_seg, 'DD/MM'))
                       || case when cardinality(v_contam) = 0 then 'não conto com ninguém da equipe.'
                               else 'conto com ' || public._agenda_lista(v_contam, null) || '.' end;
              v_ini := v_ini || coalesce((select string_agg(' ' || (p ->> 'texto'), '' order by o)
                                            from jsonb_array_elements(v_r -> 'partes') with ordinality t(p, o)), '');
              v_fim := ' Se mudar algo, me diga (ex.: fico em campo seg a qua; Mateus vem ter e qua).'
                       || case when v_dsp then ' 1) Fica assim; 2) Fico em campo de seg a sex (recomendo); 3) Nenhum dia: só abro e fecho.'
                               else ' 1) Fica assim.' end;
              v_ops := jsonb_build_array(jsonb_build_object('n', 1, 'texto', 'Fica assim', 'efeito', '{}'::jsonb))
                       || case when v_dsp
                               then jsonb_build_array(
                                      jsonb_build_object('n', 2, 'texto', 'Fico em campo de seg a sex',
                                                         'efeito', jsonb_build_object('dias', jsonb_build_array(1, 2, 3, 4, 5))),
                                      jsonb_build_object('n', 3, 'texto', 'Nenhum dia: só abro e fecho',
                                                         'efeito', jsonb_build_object('dias', '[]'::jsonb)))
                               else '[]'::jsonb end;
              insert into public.agenda_perguntas (tipo, chave, payee_id, dia, perda_em, texto, opcoes, recomendacao, modo, criada_em,
                                                   expira_em)
              values ('dias_semana', format('dias_semana:%s:%s', v_dono, v_seg), v_dono, v_seg, (v_ps ->> 'prazo_dia')::date,
                      public._agenda_corta(v_ini, 600 - char_length(v_fim)) || v_fim, v_ops,
                      case when v_dsp then 2 else 1 end, case when cf.modo_dias = 'ligado' then 'ligado' else 'sombra' end, p_agora,
                      (v_ps ->> 'prazo_em')::timestamptz + cf.desfazer_validade)
              on conflict (chave, modo) where estado = 'aberta' do nothing
              returning id into v_id;
              v_c := v_c || jsonb_build_object('dono', case when v_id is null then 'ja_existe' else 'perguntei' end,
                                               'motivos', v_r -> 'motivos');
            end;
          end if;
        end if;
      end if;
      -- a rodada grava a linha quando algo mudou ou quando o dono ficou decidido sem motivo (as próximas do dia não recalculam)
      if exists (select 1 from jsonb_each(v_c) k
                  where k.key not in ('espera_chamada', 'motivos')
                    and not (k.key = 'dono' and k.value #>> '{}' in ('espera_o_diario', 'ja_existe'))) then
        v_fez := true;
      end if;
      v_cont := v_cont || jsonb_build_object('perguntar', v_c);
    exception
      when query_canceled then raise;
      when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        v_erros := v_erros + 1;
        v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
        perform public.log_app_error('db', format('semana da equipe, passo %s: %s', v_passo, v_msg), 'agenda',
                                     'equipe_semana:' || v_passo, 'error',
                                     jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end if;

  -- ── 5. a rodada: só quando algum passo fez algo ou falhou (não uma linha por tique) ───────────────────────────────────────────
  if v_fez or v_erros > 0 then
    insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms,
                                             rotina, modo_equipe, modo_diaria)
    values (clock_timestamp(), p_hoje, p_agora, cf.modo_proposta, cf.modo_vigia,
            v_cont || jsonb_build_object('falhas', v_falhas, 'modos', jsonb_build_object('dias', cf.modo_dias, 'cadastro', cf.modo_cadastro)),
            least(v_erros, 32767), greatest(0, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int),
            'equipe_semana', cf.modo_equipe, cf.modo_diaria);
  end if;
  return jsonb_build_object('rodou', true, 'modos', jsonb_build_object('dias', cf.modo_dias, 'cadastro', cf.modo_cadastro),
                            'contagens', v_cont, 'erros', v_erros, 'falhas', v_falhas);
end;
$function$;

comment on function public.agenda_equipe_semana(date, timestamptz) is
  'Agenda de Produção (Fase 7b, P3; §5.2 com o R4; AG7-02/03/13/15): a rodada da semana da equipe, a cada tique do task-automations (passo 0b1, depois da rotina e antes do aprendizado). modo_dias e modo_cadastro desligados = {rodou: false}. Passos, cada um no seu bloco (o que falha vai a app_error_logs, context agenda, action equipe_semana:<passo>, e os outros rodam; query_canceled sobe): (1) contatos — a regra d14, no dia do plano, uma vez por dia a partir de equipe_hora_dias: quem está na grade (agenda_capacidade de hoje a +13, sem o dono) com dias fixos (padrão vivo), telefone (_agenda_equipe_tem_telefone) e nenhuma linha em agenda_equipe_contato entra na lista (incluido_por regra; em ligado, com a ação equipe da vigia "Pus Rafael na rotina da equipe (vem de seg a sex e tem telefone): … *desfaz* tira.", depois.motivo regra_d14, desfazível; em sombra só conta); nunca reinclui quem tem linha (parou, ou o "2) Não" do dono); (2) cadastro — a cada tique: a chamada vista pela 1ª vez ganha o prazo (veto_ate = _agenda_veto_ate(mostrada_em, equipe_chamada_prazo_du), expira_em = prazo + desfazer_validade); a chamada vista e sem resposta até o prazo vence ("sem resposta: segui como estava"); a pergunta do telefone fecha quando o telefone aparece e a do contato quando a pessoa entra na rotina; uma vez por dia, até equipe_cadastro_abertas_max abertas no modo de modo_cadastro: a chamada (chave equipe_cadastro:chamada:<segunda de hoje>; quando nunca houve ou a última tem mais de equipe_chamada_dias dias; "Na agenda conto com Alex: você disse todo dia útil. Alex não tem telefone no cadastro: … Quem você chama quando precisa eu só conto nos dias que você disser (ex.: Mateus vem qua e qui). Roberto e João saíram da agenda em 30/10: não conto com eles. Está certo? 1) Está certo (recomendo); 2) Mudou. Se não responder em 3 dias úteis depois de ver, sigo assim."; expira_em = criada + 7 dias), o telefone de quem está na grade e não tem (quando a chamada aberta ainda não o pede) e o contato de quem tem telefone e vem sob demanda (sem dias fixos) e não tem linha na lista ("1) Ponho (recomendo); 2) Não."); (3) fechar — a partir do prazo da semana (a quinta que a planeja, hora_do_plano − equipe_dias_fechar_antes), uma vez (pela ação dias_da_semana), só com alguém perguntado ou a pergunta do dono dessa semana: as mensagens dias enfileiradas viram sem_resposta, a pergunta dias_semana aberta vence ("sem resposta: vale o que estava") e a ação equipe da vigia (executada só com modo_dias ligado) resume a semana ("Dias da semana de 16/11: Alex de seg a sex (você disse); Rafael seg, ter e qui (disse em 06/11); você só abre e fecha." + o que a pessoa disse por cima do que o dono combinou, "mantive o que você disse", e "Fulano não respondeu: vale a última (…)"); (4) perguntar — da quinta até pode_perguntar_ate, a partir de equipe_hora_dias, nunca no domingo: a quem está na lista da rotina, tem dias fixos e telefone (e não tem o padrão "não vem" em todos os dias úteis), uma mensagem dias da semana seguinte à próxima (_agenda_equipe_texto_dias) quando as do dia + as que a rotina ainda vai começar (_agenda_equipe_previstas_hoje) cabem em equipe_proativas_dia_max, senão adiada para o dia seguinte; a 1ª vez em ligado, com modo_cadastro ligado, espera a chamada respondida ou vencida (no máximo 7 dias desde a criação); ao dono (dono_dias_semanal), só na quinta, uma vez por semana, só com motivo (_agenda_dias_semana_motivos) — a pergunta dias_semana (chave dias_semana:<dono>:<segunda>, perda_em = a quinta do prazo, "Semana de 16/11: conto com Alex de seg a sex (você disse). … Se mudar algo, me diga (ex.: fico em campo seg a qua; Mateus vem ter e qua). 1) Fica assim.", com dono_sem_padrao + "2) Fico em campo de seg a sex (recomendo); 3) Nenhum dia: só abro e fecho"); com modo_chamar ligado, espera o diário de hoje do gestor até o tique de equipe_hora_dias + 30 min. (5) Uma linha em agenda_vigia_rodadas (rotina equipe_semana) só quando algum passo fez algo ou falhou (o "diario" marca o dia). {rodou, modos, contagens, erros, falhas}. Security definer, só o service_role.';

-- ── 2. As recriadas (o corpo da definição mais nova; as mudanças só nos blocos "-- FASE 7b:") ─────────────────────────────
-- Fora dos blocos nenhuma linha muda. Quem recriar de novo qualquer uma delas copia DESTA migration.

-- _agenda_equipe_registrar (de 20261026100300_agenda_fase3_equipe_diarias.sql)
create or replace function public._agenda_equipe_registrar(p_payee uuid, p_dia date, p_tipo text, p_texto text,
                                                           p_enviar_em timestamptz, p_leva_ficha_de date default null,
                                                           p_responde text default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  v_modo text;
  v_id   uuid;
  v_r    jsonb;
  v_enviar timestamptz;
begin
  if cf.modo_equipe = 'desligado' then
    return jsonb_build_object('criada', false, 'modo', 'desligado');
  end if;
  -- FASE 7b: (7b P3, §5.2) a pergunta dos dias da semana (tipo dias; p_dia = a segunda da semana perguntada): com a pergunta dos dias
  -- desligada (modo_dias), nada; ligada só com a equipe e a pergunta dos dias ligadas (senão em teste, a chave com ":sombra"); a chave
  -- agenda-equipe:dias:<pessoa>:<segunda>; a janela, o teto do dia e a trava da fila valem como para a ficha (_agenda_equipe_enfileirar)
  if p_tipo = 'dias' then
    if cf.modo_dias = 'desligado' then
      return jsonb_build_object('criada', false, 'modo', 'desligado');
    end if;
    if nullif(btrim(coalesce(p_texto, '')), '') is null then
      raise exception 'A mensagem à equipe veio sem texto.' using errcode = '22023';
    end if;
    if p_dia is null or extract(isodow from p_dia)::int <> 1 then
      raise exception 'A pergunta dos dias é de uma semana: o dia é a segunda (veio %).', p_dia using errcode = '22023';
    end if;
    v_modo := case when cf.modo_equipe = 'ligado' and cf.modo_dias = 'ligado' then 'ligado' else 'sombra' end;
    insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, leva_ficha_de, modo, texto, enviar_em, dedupe_key,
                                                responde_wa_id, criada_em)
    values (p_payee, p_dia, 'dias', null, v_modo, left(p_texto, 600), p_enviar_em,
            format('agenda-equipe:dias:%s:%s', p_payee, p_dia) || case when v_modo = 'sombra' then ':sombra' else '' end,
            null, p_enviar_em)
    on conflict do nothing
    returning id into v_id;
    if v_id is null then
      return jsonb_build_object('criada', false, 'modo', v_modo, 'motivo', 'ja_existe');
    end if;
    v_r := public._agenda_equipe_enfileirar(v_id);
    return v_r || jsonb_build_object('criada', true, 'modo', v_modo, 'id', v_id);
  end if;
  -- FASE 7b: fim
  if p_tipo is null or p_tipo not in ('ficha', 'confirmar', 'como_foi', 'resposta') then
    raise exception 'Tipo de mensagem à equipe desconhecido: "%".', coalesce(p_tipo, '') using errcode = '22023';
  end if;
  if nullif(btrim(coalesce(p_texto, '')), '') is null then
    raise exception 'A mensagem à equipe veio sem texto.' using errcode = '22023';
  end if;
  v_modo := case when cf.modo_equipe = 'ligado' then 'ligado' else 'sombra' end;
  -- (C1, NOVO-agenda-28) a resposta a uma mensagem dele: na hora entre equipe_resposta_direta_inicio e _fim (fora do
  -- domingo); senão no início da janela da equipe (a mensagem registrada nunca muda: a hora entra certa)
  v_enviar := case when p_tipo = 'resposta' then public._agenda_equipe_quando_responder(p_enviar_em) else p_enviar_em end;
  insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, leva_ficha_de, modo, texto, enviar_em, dedupe_key,
                                              responde_wa_id, criada_em)
  values (p_payee, p_dia, p_tipo, p_leva_ficha_de, v_modo, left(p_texto, 600), v_enviar,
          case when p_tipo = 'resposta'
               then format('agenda-equipe:resposta:%s:%s', p_payee, coalesce(p_responde, md5(p_texto || p_enviar_em::text)))
               else format('agenda-equipe:%s:%s:%s', p_tipo, p_payee, p_dia) end
          || case when v_modo = 'sombra' then ':sombra' else '' end,
          case when p_tipo = 'resposta' then p_responde end, p_enviar_em)
  on conflict do nothing
  returning id into v_id;
  if v_id is null then
    return jsonb_build_object('criada', false, 'modo', v_modo, 'motivo', 'ja_existe');
  end if;
  v_r := public._agenda_equipe_enfileirar(v_id);
  return v_r || jsonb_build_object('criada', true, 'modo', v_modo, 'id', v_id);
end;
$function$;

comment on function public._agenda_equipe_registrar(uuid, date, text, text, timestamptz, date, text) is
  'Agenda de Produção (Fase 3, P4; revisão C1): grava a mensagem à equipe no modo de agora (desligado = nada; sombra = estado registrada e a chave agenda-equipe:<tipo>:<pessoa>:<dia> com ":sombra"; ligado = a chave sem sufixo, a mesma da fila) e chama _agenda_equipe_enfileirar. Uma por pessoa, dia, tipo e modo (as respostas pela mensagem dele). A resposta (NOVO-agenda-28) entra com a hora de _agenda_equipe_quando_responder: na hora, entre equipe_resposta_direta_inicio e _fim; senão no início da janela. Sem grant. FASE 7b (P3, §5.2): o tipo dias — a pergunta dos dias da semana (p_dia = a segunda da semana perguntada; outra data = 22023): com modo_dias desligado, {criada: false} e nada; ligada só com modo_equipe e modo_dias ligados (senão sombra, a chave com ":sombra"); a chave agenda-equipe:dias:<pessoa>:<segunda>; a janela, o teto do dia (conta como as que o sistema começa) e a trava da fila valem como para a ficha. Os outros tipos, o de antes, byte a byte.';

-- _agenda_rotina_sem_resposta (de 20261026100300_agenda_fase3_equipe_diarias.sql)
create or replace function public._agenda_rotina_sem_resposta(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf  public.agenda_config := public._agenda_cfg();
  v_n int;
begin
  update public.agenda_equipe_mensagens m set estado = 'sem_resposta'
   where m.tipo <> 'resposta' and m.estado = 'enfileirada' and m.resposta_em is null
     -- FASE 7b: (7b P3; A2 = NOVO-agenda-53) a pergunta dos dias da semana não fecha aqui: quem a fecha é o prazo da semana dela
     -- (agenda_equipe_semana, o passo fechar)
     and m.tipo <> 'dias'
     -- FASE 7b: fim
     and m.enviar_em + cf.equipe_resposta_validade < p_agora;
  get diagnostics v_n = row_count;
  return jsonb_build_object('sem_resposta', v_n);
end;
$function$;

-- (a 20261026100300 não comenta a função)
comment on function public._agenda_rotina_sem_resposta(date, timestamptz) is
  'Agenda de Produção (Fase 3, P4): o passo sem_resposta da rotina da equipe — a mensagem que o sistema começou (não a resposta), enfileirada, sem resposta e com equipe_resposta_validade vencida vira sem_resposta. {sem_resposta}. FASE 7b (P3; A2 = NOVO-agenda-53): menos a pergunta dos dias da semana (tipo dias), que vale até o prazo da semana dela — quem a fecha é o passo fechar de agenda_equipe_semana. Sem grant.';

-- agenda_resposta_da_equipe (de 20261026100300_agenda_fase3_equipe_diarias.sql)
create or replace function public.agenda_resposta_da_equipe(p_phone text, p_body text, p_message_id text,
                                                            p_recebida_em timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_hoje   date := (p_recebida_em at time zone 'America/Sao_Paulo')::date;
  v_hora   time := (p_recebida_em at time zone 'America/Sao_Paulo')::time;
  v_ids    uuid[];
  v_payee  uuid;
  v_nome   text;
  v_l      jsonb;
  v_tipo   text;
  m        public.agenda_equipe_mensagens%rowtype;
  v_recibo timestamptz;
  v_trecho text := left(btrim(coalesce(p_body, '')), 500);
  v_wa     text := nullif(btrim(coalesce(p_message_id, '')), '');
  v_dia    date;
  v_f      jsonb;
  v_r      jsonb;
  v_os     uuid[];
  v_disp   uuid;
  v_rep    jsonb;
  v_acao   uuid;
  v_plano  text[];
  v_ditos  text[];
  v_conf   text[];
  v_term   boolean;
  v_ent    boolean;
  v_estado text;
  v_msg    text;
  v_resp   text;
  v_div    boolean;
  -- FASE 7b: (7b P3, §5.2; A1, A3) a pergunta dos dias da semana: a mensagem aberta dela, a leitura, a gravação e a resposta
  v_7b_mq   public.agenda_equipe_mensagens%rowtype;
  v_7b_vd   jsonb;
  v_7b_g    jsonb;
  v_7b_resp text;
  v_7b_ult  boolean;
  v_7b_sem  text;
  v_7b_dias smallint[];
  v_7b_sab  boolean;
  -- FASE 7b: fim
begin
  if v_trecho = '' or p_recebida_em is null then
    return jsonb_build_object('consumiu', false);
  end if;
  -- desligado: nada lê (o webhook segue como sempre)
  if cf.modo_equipe = 'desligado' then
    return jsonb_build_object('consumiu', false, 'modo', 'desligado');
  end if;
  v_ids := public._agenda_payees_do_telefone(p_phone, v_hoje);
  if cardinality(v_ids) > 1 then
    perform public.log_app_error('db', 'agenda: o telefone de uma mensagem é de mais de uma pessoa da equipe; não li a resposta',
                                 'agenda', 'equipe:telefone', 'warn', jsonb_build_object('payees', to_jsonb(v_ids)));
    return jsonb_build_object('consumiu', false, 'motivo', 'ambiguo');
  end if;
  if cardinality(v_ids) = 0 then
    return jsonb_build_object('consumiu', false);
  end if;
  v_payee := v_ids[1];
  v_nome := (select public._agenda_nome_curto(p.name) from public.payees p where p.id = v_payee);
  -- a mesma mensagem dele de novo: nada muda
  if v_wa is not null and exists (select 1 from public.agenda_equipe_mensagens x
                                   where x.payee_id = v_payee and (x.resposta_wa_id = v_wa or x.responde_wa_id = v_wa)) then
    return jsonb_build_object('consumiu', exists (select 1 from public.agenda_equipe_mensagens x
                                                   where x.payee_id = v_payee and x.modo = 'ligado'
                                                     and (x.resposta_wa_id = v_wa or x.responde_wa_id = v_wa)),
                              'repetida', true);
  end if;

  -- FASE 7b: (7b P3, §5.2 item 1) a pergunta dos dias da semana aberta — ligada, enfileirada, mandada antes desta mensagem e com o
  -- prazo da semana por vir (a quinta que planeja a semana, hora_do_plano − equipe_dias_fechar_antes) — e a leitura dela, sem IA. Só
  -- com a pergunta dos dias ligada (modo_dias): em teste ela nunca sai, e nada daqui muda.
  if cf.modo_dias = 'ligado' then
    select * into v_7b_mq from public.agenda_equipe_mensagens x
     where x.payee_id = v_payee and x.tipo = 'dias' and x.modo = 'ligado' and x.estado = 'enfileirada'
       and x.enviar_em <= p_recebida_em
       and p_recebida_em < (((x.dia - 7 + (cf.dia_do_plano - 1)) + cf.hora_do_plano) - cf.equipe_dias_fechar_antes)
                           at time zone 'America/Sao_Paulo'
     order by x.enviar_em desc, x.criada_em desc limit 1;
    if v_7b_mq.id is not null then
      v_7b_vd := public._agenda_ler_dias_da_equipe(p_body);
    end if;
  end if;
  -- FASE 7b: fim
  v_l := public._agenda_ler_resposta_da_equipe(p_body);
  v_tipo := v_l ->> 'tipo';
  -- a quem ele responde: a última que o sistema começou (ligado, enfileirada, dentro da validade)
  select * into m from public.agenda_equipe_mensagens x
   where x.payee_id = v_payee and x.tipo <> 'resposta' and x.modo = 'ligado' and x.estado = 'enfileirada'
     -- FASE 7b: (7b P3, §5.2 item 2) a pergunta dos dias da semana não é a mensagem a que ele responde no resto (ela tem o ramo dela)
     and x.tipo <> 'dias'
     -- FASE 7b: fim
     and x.enviar_em <= p_recebida_em and x.enviar_em >= p_recebida_em - cf.equipe_resposta_validade
   order by x.enviar_em desc, x.criada_em desc limit 1;
  -- o recibo das diárias mandado depois dela: o "ok" é do recibo (NOVO-agenda-17); a pergunta é sempre da agenda
  select max(a.enviado_ao_freelancer_em) into v_recibo
    from public.acertos_diarias a
   where a.favorecido_id = v_payee and a.status = 'fechado' and a.conferido_em is null
     and a.enviado_ao_freelancer_em > p_recebida_em - interval '7 days' and a.enviado_ao_freelancer_em <= p_recebida_em;
  if v_tipo <> 'pergunta' and v_recibo is not null and (m.id is null or v_recibo > m.enviar_em) then
    return jsonb_build_object('consumiu', false, 'motivo', 'recibo');
  end if;
  -- FASE 7b: (7b P3, §5.2 item 3; A1 = NOVO-agenda-52, A3 = NOVO-agenda-54) a resposta à pergunta dos dias da semana, antes da
  -- pergunta, do "não vou" e do "como foi":
  --   · os dias ou "nenhum" (em qualquer ordem: a frase com os dias é sobre a semana) gravam a semana presa — e o padrão de quem tem —
  --     pelo _agenda_equipe_dias_gravar (origem diarista; a exceção do dono no dia vence e volta em conflitos) e respondem
  --     "Anotei: …" (§6.1);
  --   · "igual" (ou "ok") com a pergunta por último: nada gravado, "Anotei: semana de 16/11 igual (de seg a sex). Obrigado!";
  --   · não entendi com a pergunta por último, e a leitura geral não é pergunta, presença nem turnos (o "não vou" junto de um dia da
  --     semana também: "segunda não posso" é sobre a semana, A3): na 1ª vez, "Não entendi os dias da semana de 16/11. …"; na 2ª, a
  --     pergunta equipe_resposta ao dono, e a mensagem fica respondida.
  -- Fora disso, o de antes (a mensagem a que ele responde é a última que o sistema começou, fora a pergunta da semana).
  if v_7b_mq.id is not null then
    v_7b_ult := v_7b_mq.enviar_em > coalesce(m.enviar_em, '-infinity'::timestamptz);
    v_7b_sem := to_char(v_7b_mq.dia, 'DD/MM');
    if v_7b_vd ->> 'tipo' in ('dias', 'nenhum') then
      v_7b_dias := array(select y::smallint from jsonb_array_elements_text(coalesce(v_7b_vd -> 'dias', '[]'::jsonb)) y);
      v_7b_sab := coalesce((v_7b_vd ->> 'sabado')::boolean, false);
      v_7b_g := public._agenda_equipe_dias_gravar(v_payee, v_7b_mq.dia, v_7b_dias, v_7b_sab, 'diarista', v_trecho, p_recebida_em,
                                                  v_7b_mq.id);
      v_7b_resp := case when cardinality(v_7b_dias) = 0 and not v_7b_sab
                        then format('Anotei: na semana de %s você não pode. Obrigado por avisar!', v_7b_sem)
                        else format('Anotei: na semana de %s você pode %s. Obrigado!', v_7b_sem,
                                    public._agenda_dias_curtos(v_7b_dias, v_7b_sab)) end;
      update public.agenda_equipe_mensagens
         set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa,
             leitura = v_7b_vd || jsonb_build_object('mudou', v_7b_g -> 'mudou', 'padrao_mudou', v_7b_g -> 'padrao_mudou',
                                                     'conflitos', coalesce(v_7b_g -> 'conflitos', '[]'::jsonb))
       where id = v_7b_mq.id;
      v_r := public._agenda_equipe_registrar(v_payee, v_7b_mq.dia, 'resposta', v_7b_resp, p_recebida_em, null,
                                             coalesce(v_wa, md5(v_trecho || p_recebida_em::text)));
      return jsonb_build_object('consumiu', true, 'tipo', 'dias', 'leitura', v_7b_vd ->> 'tipo', 'mudou', v_7b_g -> 'mudou',
                                'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_7b_resp end, 'envio', v_r ->> 'estado');
    end if;
    if v_7b_vd ->> 'tipo' = 'igual' and v_7b_ult then
      v_7b_resp := format('Anotei: semana de %s igual (%s). Obrigado!', v_7b_sem,
                          public._agenda_dias_declarados(v_payee, v_7b_mq.dia) ->> 'texto');
      update public.agenda_equipe_mensagens
         set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa, leitura = v_7b_vd
       where id = v_7b_mq.id;
      v_r := public._agenda_equipe_registrar(v_payee, v_7b_mq.dia, 'resposta', v_7b_resp, p_recebida_em, null,
                                             coalesce(v_wa, md5(v_trecho || p_recebida_em::text)));
      return jsonb_build_object('consumiu', true, 'tipo', 'dias', 'leitura', 'igual',
                                'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_7b_resp end, 'envio', v_r ->> 'estado');
    end if;
    if v_7b_vd ->> 'tipo' = 'nao_entendi' and v_7b_ult
       and (v_tipo not in ('pergunta', 'nao_vou', 'presenca', 'turnos')
            or (v_tipo = 'nao_vou'
                and public._agenda_normal(p_body) ~ '\m(segunda|terca|quarta|quinta|sexta|sabado|seg|ter|qua|qui|sex|sab)s?\M')) then
      if coalesce((v_7b_mq.leitura ->> 'nao_entendi')::int, 0) = 0 then
        v_7b_resp := format('Não entendi os dias da semana de %s. Mande só os dias, assim: seg ter qui (ou "nenhum").', v_7b_sem);
        update public.agenda_equipe_mensagens
           set leitura = coalesce(leitura, '{}'::jsonb)
                         || jsonb_build_object('nao_entendi', 1, 'trecho', v_trecho, 'recebida_em', p_recebida_em)
         where id = v_7b_mq.id;
        v_r := public._agenda_equipe_registrar(v_payee, v_7b_mq.dia, 'resposta', v_7b_resp, p_recebida_em, null,
                                               'dias:' || v_7b_mq.dia);
        return jsonb_build_object('consumiu', true, 'tipo', 'dias', 'leitura', 'nao_entendi', 'vez', 1,
                                  'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_7b_resp end, 'envio', v_r ->> 'estado');
      end if;
      perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:dias', v_payee, v_7b_mq.dia), v_payee,
        null, v_7b_mq.dia,
        format('%s respondeu "%s" à pergunta dos dias da semana de %s, e eu não entendi. Diga os dias dele (ex.: %s vem seg e ter na semana de %s).',
               v_nome, public._agenda_corta(v_trecho, 120), v_7b_sem, v_nome, v_7b_sem),
        'ligado', p_recebida_em);
      update public.agenda_equipe_mensagens
         set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa,
             leitura = coalesce(v_7b_mq.leitura, '{}'::jsonb) || v_7b_vd || jsonb_build_object('nao_entendi', 2)
       where id = v_7b_mq.id;
      return jsonb_build_object('consumiu', true, 'tipo', 'dias', 'leitura', 'nao_entendi', 'vez', 2, 'resposta', null);
    end if;
  end if;
  -- FASE 7b: fim

  -- ── pergunta: a ficha do publicado, sem valores (em sombra só registra) ──────────────────────────────
  if v_tipo = 'pergunta' then
    v_dia := case when v_l ->> 'dia' = 'amanha' then v_hoje + 1 else v_hoje end;
    v_f := public.agenda_equipe_ficha(v_payee, v_dia, v_hoje);
    v_r := public._agenda_equipe_registrar(v_payee, v_dia, 'resposta', v_f ->> 'texto_resposta', p_recebida_em, null,
                                           coalesce(v_wa, md5(v_trecho || p_recebida_em::text)));
    if v_r ? 'id' then
      update public.agenda_equipe_mensagens
         set leitura = v_l || jsonb_build_object('pergunta', v_trecho, 'recebida_em', p_recebida_em)
       where id = (v_r ->> 'id')::uuid;
    end if;
    if not coalesce((v_f ->> 'tem_plano')::boolean, false) and public.agenda_dia_util(v_dia) then
      perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:pergunta', v_payee, v_dia), v_payee,
        null, v_dia, format('O %s perguntou o que tem %s e ainda não tem plano para ele. Diga a ele o que fazer.', v_nome,
                            case when v_dia = v_hoje then 'hoje' else 'amanhã (' || public._dia_curto(v_dia) || ')' end),
        case when cf.modo_equipe = 'ligado' then 'ligado' else 'sombra' end, p_recebida_em);
    end if;
    return jsonb_build_object('consumiu', cf.modo_equipe = 'ligado', 'tipo', v_tipo,
                              'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_f ->> 'texto_resposta' end,
                              'envio', v_r ->> 'estado');
  end if;

  -- ── não vou (à ficha ou à confirmação; sem nada pendente: hoje antes do meio-dia, senão o próximo dia útil) ─
  -- (Revisão C1, item 3) também ao "como foi hoje?": aí o dia é o da ficha que ele levava (senão o próximo dia útil), e o
  -- "como foi" de hoje continua esperando a resposta de hoje (não vira a pergunta da diária de hoje)
  if v_tipo = 'nao_vou' and (m.id is null or m.tipo in ('ficha', 'confirmar', 'como_foi')) then
    -- (antes do fim da manhã, hoje; depois, o próximo dia útil)
    v_dia := case when m.tipo = 'como_foi' then coalesce(m.leva_ficha_de, public.agenda_somar_du(m.dia, 1))
                  else coalesce(m.dia, case when v_hora < cf.manha_fim then v_hoje else public.agenda_somar_du(v_hoje, 1) end) end;
    v_os := array(select distinct a.service_order_id from public.agenda_alocacoes a
                   where a.payee_id = v_payee and a.dia = v_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                   order by 1);
    if cf.modo_equipe <> 'ligado' then
      -- em sombra nada muda: só o que faria
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
      values (clock_timestamp(), v_hoje, false, 'equipe', 'equipe', v_os[1], v_os, v_payee,
              jsonb_build_object('motivo', 'nao_vou', 'dia', v_dia, 'trecho', v_trecho),
              left(format('Em teste: o %s avisou que não vem %s; eu tiraria ele do plano desse dia.', v_nome,
                          public._agenda_dia_ref(v_dia, v_hoje)), 400));
      return jsonb_build_object('consumiu', false, 'tipo', v_tipo, 'modo', 'sombra');
    end if;
    perform set_config('agenda.hoje', v_hoje::text, true);
    if not exists (select 1 from public.agenda_disponibilidade d
                    where d.payee_id = v_payee and d.substituida_em is null and d.situacao = 'indisponivel'
                      and d.turno is null and d.periodo @> v_dia) then
      insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, trecho, criado_em)
      values (v_payee, daterange(v_dia, v_dia, '[]'), 'indisponivel', 'diarista', left('Avisou que não vem: ' || v_trecho, 200),
              left(v_trecho, 300), p_recebida_em)
      returning id into v_disp;
    end if;
    if cf.modo_proposta = 'ligado' and cardinality(v_os) > 0 then
      begin
        -- (C1, NOVO-agenda-27) a falta é evento real: o replano refaz os meios-dias que sobram da OS num bloco só, amanhã
        -- incluído (_agenda_violacoes lê agenda.replano_da_falta); o *desfaz* volta tudo
        perform set_config('agenda.replano_da_falta', 'on', true);
        v_rep := public.agenda_replanejar(v_os, 'equipe_faltou', 'vigia', v_hoje, p_recebida_em, null);
        perform set_config('agenda.replano_da_falta', '', true);
      exception when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        perform set_config('agenda.replano_da_falta', '', true);
        perform public.log_app_error('db', 'agenda: replanejar depois do "não vou" da equipe falhou: ' || v_msg, 'agenda',
                                     'equipe:replanejar', 'error',
                                     jsonb_build_object('os', to_jsonb(v_os), 'sqlstate', v_estado, 'payee', v_payee));
      end;
    end if;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
    values (clock_timestamp(), v_hoje, true, 'equipe', 'equipe', v_os[1], v_os, v_payee,
            jsonb_build_object('motivo', 'nao_vou', 'dia', v_dia, 'trecho', v_trecho, 'disponibilidade', v_disp,
                               'mensagem', m.id, 'replano_acoes', coalesce(v_rep -> 'acoes', '[]'::jsonb),
                               'acorde', v_dia <= public.agenda_somar_du(v_hoje, cf.congelamento_du)),
            left(format('O %s avisou que não vem %s.', v_nome, public._agenda_dia_da_equipe(v_dia, v_hoje))
                 || coalesce(' ' || nullif(v_rep ->> 'texto', ''), ''), 400))
    returning id into v_acao;
    -- (C1, item 3) o "como foi" de hoje não é respondido pelo "não vou" de amanhã: ele segue esperando a resposta de hoje
    if m.id is not null and m.tipo <> 'como_foi' then
      update public.agenda_equipe_mensagens
         set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa, leitura = v_l,
             acao_id = v_acao
       where id = m.id;
    end if;
    v_resp := format('Tá bom, aviso %s.', coalesce('o ' || (select public._agenda_nome_curto(p.name) from public.payees p
                                                              where p.id = public._agenda_dono(null)), 'o responsável'));
    v_r := public._agenda_equipe_registrar(v_payee, v_dia, 'resposta', v_resp, p_recebida_em, null,
                                           coalesce(v_wa, md5(v_trecho || p_recebida_em::text)));
    return jsonb_build_object('consumiu', true, 'tipo', v_tipo, 'acao_id', v_acao, 'dia', v_dia,
                              'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_resp end, 'envio', v_r ->> 'estado');
  end if;

  -- Daqui em diante só a resposta a uma mensagem que o sistema mandou.
  if m.id is null then
    return jsonb_build_object('consumiu', false, 'tipo', v_tipo);
  end if;

  -- ── à ficha ou à confirmação ────────────────────────────────────────────────────────────────────────
  if m.tipo in ('ficha', 'confirmar') then
    -- (Revisão C1, item 7) o "ok" com os turnos ditos diferentes do plano ("ok, só de manhã" com o dia todo no plano) não
    -- confirma o dia: vai ao dono, como o não entendido (com o plano no texto)
    v_plano := array(select distinct a.turno from public.agenda_alocacoes a
                      where a.payee_id = v_payee and a.dia = m.dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                      order by 1);
    v_ditos := case when jsonb_typeof(v_l -> 'turnos') = 'array'
                    then array(select x from jsonb_array_elements_text(v_l -> 'turnos') x order by 1) end;
    v_div := v_tipo = 'turnos' and v_ditos is not null
             and not (v_ditos = v_plano or (v_ditos = array['meio'] and cardinality(v_plano) = 1));
    if not v_div
       and (v_tipo in ('ok', 'presenca') or (v_tipo = 'turnos' and coalesce((v_l ->> 'ok')::boolean, false))) then
      if not exists (select 1 from public.agenda_disponibilidade d
                      where d.payee_id = v_payee and d.substituida_em is null and d.situacao = 'confirmada'
                        and d.turno is null and d.periodo @> m.dia) then
        insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, trecho, criado_em)
        values (v_payee, daterange(m.dia, m.dia, '[]'), 'confirmada', 'diarista',
                left(case m.tipo when 'ficha' then 'Confirmou a ficha: ' else 'Confirmou de manhã: ' end || v_trecho, 200),
                left(v_trecho, 300), p_recebida_em);
      end if;
    else
      -- não entendi (ou turnos sem ok): vai ao dono com o trecho, e nada muda (nem remaneja: não é silêncio)
      perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:%s', v_payee, m.dia, m.tipo), v_payee,
        null, m.dia, format('O %s respondeu "%s" à %s de %s', v_nome, public._agenda_corta(v_trecho, 120),
                            case m.tipo when 'ficha' then 'ficha' else 'confirmação' end, public._dia_curto(m.dia))
                     || case when v_div
                             then ', e o plano é ' || case when v_plano = array['manha', 'tarde'] then 'o dia todo'
                                                           when v_plano = array['manha'] then 'a manhã'
                                                           when v_plano = array['tarde'] then 'a tarde'
                                                           else 'sem nada para ele' end || '.'
                             else '.' end,
        'ligado', p_recebida_em);
    end if;
    update public.agenda_equipe_mensagens
       set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa, leitura = v_l
     where id = m.id;
    return jsonb_build_object('consumiu', true, 'tipo', v_tipo, 'resposta', null);
  end if;

  -- ── ao "como foi hoje?" ─────────────────────────────────────────────────────────────────────────────
  v_plano := array(select distinct a.turno from public.agenda_alocacoes a
                    where a.payee_id = v_payee and a.dia = m.dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                    order by 1);
  v_ent := true;
  if v_tipo = 'ok' or (v_tipo = 'turnos' and v_l -> 'turnos' = 'null'::jsonb and coalesce((v_l ->> 'ok')::boolean, false)) then
    -- "ok" = tudo como o previsto: os turnos do plano e terminou (salvo "ok, mas não terminei")
    v_ditos := v_plano;
    v_term := coalesce((v_l ->> 'terminou')::boolean, true);
  elsif v_tipo = 'turnos' and jsonb_typeof(v_l -> 'turnos') = 'array' then
    v_ditos := array(select x from jsonb_array_elements_text(v_l -> 'turnos') x order by 1);
    v_term := (v_l ->> 'terminou')::boolean;
  else
    -- não entendi, "terminei" sem o dia, "não vou"/presença fora de hora: a diária vira pergunta (crítica)
    v_ent := false;
    v_ditos := null;
    v_term := (v_l ->> 'terminou')::boolean;
  end if;
  update public.agenda_equipe_mensagens
     set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa,
         leitura = v_l || jsonb_build_object('entendeu', v_ent, 'turnos_lidos', to_jsonb(v_ditos), 'turnos_plano', to_jsonb(v_plano),
                                             'terminou', v_term)
   where id = m.id;
  if v_ent then
    v_conf := array(select x from unnest(v_ditos) x where x = any (v_plano) order by 1);
    perform set_config('agenda.hoje', v_hoje::text, true);
    begin
      if cardinality(v_conf) > 0 then
        -- os turnos que ele confirmou viram resultado (via equipe), e a diária é decidida em seguida
        perform set_config('agenda.turnos_equipe', array_to_string(v_conf, ','), true);
        v_r := public.agenda_registrar_dia(null, m.dia, 'cumprido', null, null, array[v_payee], 'equipe', v_trecho, v_hoje,
                                           p_recebida_em, null);
        perform set_config('agenda.turnos_equipe', '', true);
      elsif v_ditos = '{}'::text[] then
        v_r := public.agenda_registrar_dia(null, m.dia, 'nao_cumprido', 'equipe', null, array[v_payee], 'equipe', v_trecho, v_hoje,
                                           p_recebida_em, null);
      end if;
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      perform set_config('agenda.turnos_equipe', '', true);
      perform public.log_app_error('db', 'agenda: anotar o dia pela resposta da equipe falhou: ' || v_msg, 'agenda',
                                   'equipe:dia', 'error', jsonb_build_object('payee', v_payee, 'dia', m.dia, 'sqlstate', v_estado));
    end;
    -- o "ok" ao "como foi" que levava a ficha de amanhã confirma amanhã também — (C1, item 3) salvo se ele já disse que
    -- não vem amanhã (o "ok" depois do "amanhã não vou" é sobre hoje)
    if v_tipo = 'ok' and m.leva_ficha_de is not null
       and not exists (select 1 from public.agenda_disponibilidade d
                        where d.payee_id = v_payee and d.substituida_em is null and d.situacao in ('confirmada', 'indisponivel')
                          and d.turno is null and d.periodo @> m.leva_ficha_de) then
      insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, trecho, criado_em)
      values (v_payee, daterange(m.leva_ficha_de, m.leva_ficha_de, '[]'), 'confirmada', 'diarista',
              left('Confirmou a ficha junto do "como foi": ' || v_trecho, 200), left(v_trecho, 300), p_recebida_em);
    end if;
  end if;
  -- a diária do dia (idempotente: o agenda_registrar_dia já a chamou quando anotou)
  begin
    v_r := public._agenda_diaria_do_dia(v_payee, m.dia, 'equipe', v_hoje, p_recebida_em);
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    perform public.log_app_error('db', 'agenda: a diária pela resposta da equipe falhou: ' || v_msg, 'agenda', 'equipe:diaria',
                                 'error', jsonb_build_object('payee', v_payee, 'dia', m.dia, 'sqlstate', v_estado));
  end;
  return jsonb_build_object('consumiu', true, 'tipo', v_tipo, 'entendeu', v_ent, 'resposta', null, 'diaria', v_r ->> 'status');
end;
$function$;

comment on function public.agenda_resposta_da_equipe(text, text, text, timestamptz) is
  'Agenda de Produção (Fase 3, P4): a mensagem do técnico (número que não é login de admin), chamada pelo whatsapp-webhook antes da confirmação do cliente e da conferência do recibo. modo_equipe desligado, telefone de ninguém da equipe (ou de dois) = {consumiu: false}. A mesma mensagem (p_message_id) de novo = nada muda. Lida por _agenda_ler_resposta_da_equipe. Decide a última mensagem que o sistema mandou (ligado, enfileirada, dentro de equipe_resposta_validade); o recibo de diárias mandado depois dela fica com o "ok" (NOVO-agenda-17: consumiu false). pergunta → a ficha do publicado (agenda_equipe_ficha.texto_resposta) como resposta enfileirada (sem plano: a pergunta equipe_resposta ao dono); em sombra só registra (consumiu false). nao_vou → indisponível no dia (agenda_disponibilidade origem diarista), replano (modo_proposta ligado, origem vigia), ação equipe com o acorde para a rotina e "Tá bom, aviso o Gustavo."; em sombra só a ação executada = false. ok/presença à ficha ou à confirmação → confirmada, sem resposta; não entendido → equipe_resposta ao dono, sem remanejo. Ao "como foi hoje?": ok = os turnos do plano e terminou; os turnos ditos viram resultado (agenda_registrar_dia via equipe, só os turnos confirmados) e a diária (_agenda_diaria_do_dia); não entendido = a pergunta crítica da diária. Sem pendente (ok, turnos, presença, não entendi) = consumiu false. {consumiu, tipo, resposta, acao_id}. Só service_role. FASE 7b (P3, §5.2; A1 = NOVO-agenda-52, A2, A3 = NOVO-agenda-54): com modo_dias ligado, a resposta à pergunta dos dias da semana (a mensagem dias ligada, enfileirada, mandada antes e com o prazo da semana por vir) é lida por _agenda_ler_dias_da_equipe ANTES da pergunta, do "não vou" e do "como foi": os dias ou "nenhum" (em qualquer ordem) gravam a semana presa e o padrão de quem tem (_agenda_equipe_dias_gravar, origem diarista; a exceção do dono no dia vence e volta em leitura.conflitos), a mensagem fica respondida e sai "Anotei: na semana de 16/11 você pode seg, ter e qui. Obrigado!" / "… você não pode. Obrigado por avisar!"; "igual"/"ok" com a pergunta por último: nada gravado, "Anotei: semana de 16/11 igual (de seg a sex). Obrigado!"; não entendido com a pergunta por último (e a leitura geral não é pergunta, presença nem turnos; o "não vou" junto de um dia da semana também — "segunda não posso" nunca vira o "não vou" da ficha): 1ª vez "Não entendi os dias da semana de 16/11. Mande só os dias, assim: seg ter qui (ou "nenhum")." (chave agenda-equipe:resposta:<pessoa>:dias:<segunda>), 2ª vez a pergunta equipe_resposta ao dono e a mensagem respondida. {consumiu: true, tipo: dias, leitura, …}. A "última que o sistema começou" do resto não é mais a pergunta da semana. Fora disso, o de antes, byte a byte.';

-- agenda_decidir (de 20261031100300_agenda_fase7a_perguntas.sql)
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
  if p_via is null or p_via not in ('whatsapp', 'painel', 'tela') then
    raise exception 'Canal desconhecido para a decisão: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
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
        v_7b_g := public._agenda_equipe_dias_gravar(v_q.payee_id, v_q.dia, v_7b_dias,
                                                    coalesce((v_opc #>> '{efeito,sabado}')::boolean, false), 'dono',
                                                    'opção ' || p_opcao, p_agora, null, v_q.id, p_autor);
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
    v_r := public.agenda_propor('replano', null, null, v_q.os_ids, v_rest || jsonb_build_object('decisao', p_pergunta),
                                true, 'dono', p_autor, p_hoje, p_agora);
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      raise exception using errcode = 'P0098', message = coalesce(v_r ->> 'texto', 'não deu');
    end if;
    v_ap := public.agenda_aplicar((v_r ->> 'proposta_id')::uuid, null, 'dono', p_autor, p_pergunta, p_hoje, p_agora);
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
  'Agenda de Produção (Fase 2, P2): a resposta do dono a uma pergunta crítica aberta (só em ligado). Opção que não existe = recusa, nada marcado. Se a agenda mudou desde a pergunta, o efeito da opção é refeito agora e, se não termina como a opção dizia (espera), devolve a pergunta com os dias de agora sem executar. Senão: a pergunta fica respondida (opcao_escolhida, resposta = as palavras do dono, respondida_*) e o efeito é executado — agenda_propor(replano, as OS da pergunta, as restrições da opção + decisao) e agenda_aplicar com p_pergunta (toda ação sai critica = true com pergunta_id). Falhou = nada fica, a pergunta continua aberta. Canais: whatsapp, painel, tela. Fase 3: diaria e diaria_ligar vão a _agenda_decidir_diaria (o lançamento, a correção pelo registrar_diaria ou a ligação às OS, com modo_diaria ligado). Fase 5 (P3): cliente_aprovar e cliente_aviso vão a _agenda_cliente_decidir (manda ou segura a mensagem ao cliente; com modo_cliente ligado). Fase 6 (P6): aprendizado vai a _agenda_aprendizado_decidir (1 o medido passa a valer — na carga, agenda_config.carga_max muda —, 2 trava, 3 volta ao padrão e trava; a 1 e a 3 com a ação crítica desfazível; com modo_aprendizado ligado e o item na lista). CORREÇÃO FASE 6 (C1, regressão B2): a pergunta do aprendizado toma pg_advisory_xact_lock(hashtext(''agenda_aprender'')) antes do for update da pergunta. FASE 7 (7a P4): as perguntas do gestor da agenda (situacao, estimativa, reavaliar, reestimar, ficha_estimativa, onda, sabado, bem_livre, compre_ate, sinal) vão a _agenda_gestor_decidir (o efeito e o modo delas: o do gestor); dia_avisado e dia_prometido seguem a decisão crítica de sempre; equipe_cadastro, a de antes. FASE 7b (P3; R4.1-3, R4.1-6, R4.2(b)): as perguntas da equipe com opções têm o efeito delas, com a pergunta e o modo dela (_agenda_modo_da_pergunta) ligados (senão "ainda está em teste") — equipe_cadastro chamada: 1 "Anotei: sigo com a equipe que tenho."; 2 "Me diga quem saiu ou quem entrou e em que dias vem (ex.: Alex saiu; Mateus vem qua e qui; Mateus vem toda terça)." (sem diária); equipe_cadastro contato: 1 põe na lista da rotina (agenda_equipe_contato recebe_rotina, incluido_por dono) com a ação equipe desfazível ("Pus Mateus na rotina da equipe, como você pediu. *desfaz* tira.", depois.motivo contato); 2 grava a recusa — a linha parada (recebe_rotina false, parou_em agora, "você disse que não"): nem a regra d14 nem a pergunta voltam; dias_semana: a opção com dias grava a semana pelo _agenda_equipe_dias_gravar (origem dono; a 2, "Fico em campo de seg a sex", cria o padrão do dono {1..5} sem frequência; a 3, "Nenhum dia", prende só a semana), com a ação equipe do dono; a 1 ("Fica assim") só fica respondida. A chamada da 7a (sem opções) e o telefone (sem opções) seguem o de antes.';

-- agenda_desfazer (de 20261031100600_agenda_fase7a_rodada.sql)
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
  -- FASE 7: (7a P7) e diz o que não voltou
  if cardinality(v_f7_fora) > 0 then
    v_txt := v_txt || format(' %s não %s mais na equipe: os dias %s não voltam.', v_f7_nomes,
                             case when cardinality(v_f7_fora) = 1 then 'está' else 'estão' end,
                             case when cardinality(v_f7_fora) = 1 then 'dele' else 'deles' end);
  end if;
  -- FASE 7: fim
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
  return jsonb_build_object('ok', true, 'texto', v_txt, 'acao_id', v_acao, 'recriadas', to_jsonb(v_novas), 'canceladas', to_jsonb(v_canc));
end;
$function$;

comment on function public.agenda_desfazer(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): desfaz uma ação executada — recusa (nada muda) se foi sombra, já foi desfeita, não é desfazível (pedido do dono pela tela ou aprovação), passou o desfazivel_ate, algum meio-dia criado já começou ou tem resultado, ou recriar o que saiu bateria em quem já está no lugar ("Não dá para desfazer: o Roberto já está no Giancarlo…"). Faz: o que ela criou → cancelada (desfeito); o que ela tirou volta igual (substitui_id, mesmo estado/fixado); o status pela porta (via desfazer; o que começou não regride); o espelho; nova ação tipo desfazer (desfaz_a) e a original ganha desfeita_*. Desfazer uma decisão crítica cria a pergunta de novo ("A decisão sobre o Nelson volta a ficar com você."). Fase 3: concluir e entregar vão a _agenda_desfazer_marco (as cobranças da conclusão, a saída, a comissão de vendedor e a entrega); a diária da agenda a _agenda_desfazer_diaria (apaga o turno que ela criou, com o acerto aberto); desfazer o replano da ausência da equipe tira a ausência do dia (agenda_disponibilidade substituída). Fase 4 (P4): a ação material (a previsão pela mensagem do fornecedor, a chegada pela nota) vai a _agenda_desfazer_material (as linhas voltam se ninguém mexeu nelas depois). Fase 5 (P4): o que a resposta do cliente mudou (a ação fixar/cliente de origem cliente com depois.resposta_id: a confirmação, o pedido de dia, o acesso) vai a _agenda_desfazer_cliente; a outra ação cliente (a mensagem enviada, o acorde, a decisão do aviso) não se desfaz ("Mensagem enviada não se desmanda."); desfazer direto o replano que o pedido de dia causou também tira o pedido (_agenda_cliente_restaurar_pedido) e deixa a ação do cliente desfeita. Fase 6 (P6): a ação aprendizado vai a _agenda_desfazer_aprendizado (o em_uso de antes volta, nulo = o padrão, e a chave fica travada por aprender_trava_dias; a da carga volta carga_max). FASE 7 (7a P7, spec R3): as ações do gestor que não são de alocação têm o ramo delas — estimar (os_planejamento.dias, estimativa_fonte e estimativa_em voltam ao antes da ação: "Desfeito: o Nelson (OS-00112) volta sem os dias que eu contei (4 dias). Me diga quantos dias são."), dupla (dupla_dita, dupla_meios, dupla_motivo e dupla_em voltam) e gestor (gestor_so_propor e gestor_so_propor_em voltam), cada uma só se nada mudou depois dela (senão a recusa diz o que mudou), dentro do desfazivel_ate; reparar e reestimar seguem o caminho de alocação de sempre. E (a medição de 30/10, item 4) o que a ação tirou e era de quem não está mais na equipe naquele dia (agenda_capacidade) não volta: o desfazer restaura só o que cabe e diz o resto ("… João e Roberto não estão mais na equipe: os dias deles não voltam."); se tudo o que voltaria é de quem saiu e a ação não criou nada de pé, nada muda ({ok: false, status saiu_da_equipe}). FASE 7b (P3, §5.2): a ação equipe que pôs alguém na rotina da equipe — pela regra d14 (vigia, depois.motivo regra_d14) ou pelo "1) Ponho" do dono (depois.motivo contato) — se desfaz dentro do desfazivel_ate: a linha em agenda_equipe_contato fica parada (recebe_rotina false, parou_em, "desfeito pelo dono"; a regra não a põe de novo) e "Desfeito: Rafael sai da rotina da equipe e não recebe mais a ficha nem a pergunta dos dias."; já fora da rotina = nada muda.';

-- _agenda_ver_equipe (de 20261026100500_agenda_fase3_acompanhamento.sql)
create or replace function public._agenda_ver_equipe(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  v_am   date := public.agenda_somar_du(p_hoje, 1);
  v_modo text := case when cf.modo_equipe = 'ligado' then 'ligado' else 'sombra' end;
  v_l    text[] := '{}';
  v_sem  text[];
  p      record;
  d      date;
  v_p    text[];
  -- FASE 7b: (7b P3) o bloco dos dias da semana
  -- estrutural (§6.4): a janela do histórico das duplas, só leitura
  c_7b_duplas_dias constant int := 60;
  v_7b_ps     jsonb;
  v_7b_seg    date;
  v_7b_grade  uuid[];
  v_7b_l      text[];
  v_7b_d      jsonb;
  v_7b_x      record;
  v_7b_quem   text[];
  v_7b_prox   text[];
  v_7b_falta  text[];
  v_7b_sd     text[];
  v_7b_dd     int;
  v_7b_dn     int;
  v_7b_sai    text[];
  v_7b_sai_em text[];
  v_7b_n      int;
  -- FASE 7b: fim
begin
  if cf.modo_equipe = 'desligado' then
    return jsonb_build_object('ok', true, 'texto', 'A rotina da equipe está desligada: eu não mando nada à equipe.', 'dados', '{}'::jsonb);
  end if;
  for p in
    select py.id, public._agenda_nome_curto(py.name) as nome
      from public.payees py
     where py.id in (select c.payee_id from public.agenda_equipe_contato c where c.recebe_rotina)
        or py.id in (select m.payee_id from public.agenda_equipe_mensagens m where m.dia in (p_hoje, v_am) and m.modo = v_modo)
     order by py.name, py.id
  loop
    foreach d in array array[p_hoje, v_am] loop
      v_p := array(
        select case m.tipo when 'ficha' then 'a ficha' when 'confirmar' then 'a confirmação' else 'o "como foi hoje?"' end || ': '
               || case m.estado
                    when 'respondida' then format('respondeu "%s" às %s%s', public._agenda_corta(m.resposta_texto, 60),
                                                  to_char(m.resposta_em at time zone 'America/Sao_Paulo', 'HH24:MI'),
                                                  case when (m.resposta_em at time zone 'America/Sao_Paulo')::date <> p_hoje
                                                       then ' de ' || public._dia_curto((m.resposta_em at time zone 'America/Sao_Paulo')::date) else '' end)
                    when 'enfileirada' then format('mandei às %s%s e ele ainda não respondeu',
                                                   to_char(m.enviar_em at time zone 'America/Sao_Paulo', 'HH24:MI'),
                                                   case when (m.enviar_em at time zone 'America/Sao_Paulo')::date <> p_hoje
                                                        then ' de ' || public._dia_curto((m.enviar_em at time zone 'America/Sao_Paulo')::date) else '' end)
                    when 'sem_resposta' then format('mandei às %s e ele não respondeu', to_char(m.enviar_em at time zone 'America/Sao_Paulo', 'HH24:MI'))
                    when 'recusada' then 'não mandei (' || case m.recusa_motivo when 'teto' then 'já tinha as 2 mensagens do dia'
                                                                 when 'janela' then 'fora do horário' when 'domingo' then 'domingo'
                                                                 when 'sem_telefone' then 'sem telefone' when 'sem_plano' then 'sem plano'
                                                                 when 'parou' then 'ele pediu para parar' else 'a rotina não estava ligada' end || ')'
                    else format('eu mandaria às %s', to_char(m.enviar_em at time zone 'America/Sao_Paulo', 'HH24:MI')) end
          from public.agenda_equipe_mensagens m
         where m.payee_id = p.id and m.dia = d and m.modo = v_modo and m.tipo in ('ficha', 'confirmar', 'como_foi')
         order by m.enviar_em, m.criada_em, m.tipo)
        || array(select case when x.situacao = 'confirmada' then 'confirmou o dia' when x.origem = 'agente' then 'não respondeu: tirei do plano' else 'avisou que não vem' end
                   from public.agenda_disponibilidade x
                  where x.payee_id = p.id and x.substituida_em is null and x.periodo @> d
                    and x.situacao in ('confirmada', 'indisponivel') and x.origem in ('agente', 'diarista')
                  order by x.criado_em desc limit 1);
      if cardinality(v_p) > 0 then
        v_l := v_l || format('%s — %s: %s.', public._agenda_dia_rotulo(d, p_hoje), p.nome, array_to_string(v_p, '; '));
      elsif exists (select 1 from public.agenda_alocacoes a where a.payee_id = p.id and a.dia = d
                       and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva') then
        v_l := v_l || format('%s — %s: nada mandado ainda.', public._agenda_dia_rotulo(d, p_hoje), p.nome);
      end if;
    end loop;
  end loop;
  -- quem está no plano de hoje ou do próximo dia útil e não tem a rotina
  v_sem := array(select distinct public._agenda_nome_curto(py.name)
                   from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
                  where a.dia in (p_hoje, v_am) and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                    and py.kind is distinct from 'socio'
                    and not exists (select 1 from public.agenda_equipe_contato c where c.payee_id = py.id and c.recebe_rotina)
                  order by 1);
  if cardinality(v_sem) > 0 then
    v_l := v_l || ('Sem a rotina (o dia é pelo *dia feito*): ' || public._agenda_lista(v_sem, null) || '.');
  end if;
  if cardinality(v_l) = 0 then
    v_l := array['A equipe não tem plano hoje nem no próximo dia útil.'];
  elsif cf.modo_equipe = 'sombra' then
    v_l := array['Em teste (nada foi mandado à equipe):'] || v_l;
  end if;
  -- FASE 7b: (7b P3, §6.4 com o R4.1-6) com a pergunta dos dias ou o cadastro da 7b fora de desligado, depois das linhas de hoje e
  -- do próximo dia útil, o bloco da semana: a semana perguntada (a seguinte à próxima) com o que vale para cada um da grade e para
  -- você; a semana seguinte (presa, quando alguém já disse); as faltas nos dias ditos; as duplas dos últimos dias; quem vem sob
  -- demanda (só nos dias que você diz) e quem saiu da agenda. Em teste, a 1ª linha diz a quem eu perguntaria. Desligados, o de antes.
  if cf.modo_dias <> 'desligado' or cf.modo_cadastro <> 'desligado' then
    v_7b_ps := public._agenda_semana_perguntada(p_hoje);
    v_7b_seg := (v_7b_ps ->> 'seg')::date;
    -- a grade de hoje a +13 dias, sem o dono (quem está na equipe da agenda)
    v_7b_grade := array(select distinct k.payee_id from public.agenda_capacidade(p_hoje, p_hoje + 13, p_hoje) k where not k.eh_dono);
    -- quem a pergunta da semana alcança: na lista da rotina, com dias fixos e telefone
    v_7b_quem := array(select public._agenda_nome_curto(py.name)
                         from public.payees py
                         join public.agenda_equipe_contato c on c.payee_id = py.id and c.recebe_rotina and c.parou_em is null
                        where py.id = any (v_7b_grade) and length(regexp_replace(coalesce(py.phone, ''), '\D', '', 'g')) >= 10
                          and exists (select 1 from public.agenda_disponibilidade w
                                       where w.payee_id = py.id and w.substituida_em is null and w.dias_semana is not null
                                         and w.situacao in ('disponivel', 'confirmada'))
                        order by py.name, py.id);
    v_7b_l := array[case
      when cf.modo_dias = 'desligado'
        then format('Dias da semana de %s (a pergunta dos dias está desligada; os dias abaixo são os de agora):', to_char(v_7b_seg, 'DD/MM'))
      when cf.modo_dias = 'ligado' and cardinality(v_7b_quem) > 0
        then format('Dias da semana de %s (pergunto toda quinta; o prazo é %s às %s):', to_char(v_7b_seg, 'DD/MM'),
                    public._dia_curto((v_7b_ps ->> 'prazo_dia')::date),
                    to_char((v_7b_ps ->> 'prazo_em')::timestamptz at time zone 'America/Sao_Paulo', 'HH24:MI'))
      when cf.modo_dias = 'ligado'
        then format('Dias da semana de %s (o prazo é %s às %s; ninguém da rotina tem telefone e dias fixos para eu perguntar):',
                    to_char(v_7b_seg, 'DD/MM'), public._dia_curto((v_7b_ps ->> 'prazo_dia')::date),
                    to_char((v_7b_ps ->> 'prazo_em')::timestamptz at time zone 'America/Sao_Paulo', 'HH24:MI'))
      when cardinality(v_7b_quem) > 0
        then format('Em teste (não perguntei a ninguém): eu perguntaria a %s na %s às %s os dias da semana de %s; os dias abaixo são os de agora.',
                    public._agenda_lista(v_7b_quem, null), public._dia_curto((v_7b_ps ->> 'quinta')::date),
                    to_char(cf.equipe_hora_dias, 'HH24:MI'), to_char(v_7b_seg, 'DD/MM'))
      else format('Em teste (não perguntei a ninguém): os dias da semana de %s — ninguém da rotina tem telefone e dias fixos para eu perguntar; os dias abaixo são os de agora.',
                  to_char(v_7b_seg, 'DD/MM')) end];
    -- a semana perguntada, por pessoa (quem vem sob demanda fica na linha dele, abaixo)
    for v_7b_x in select distinct k.payee_id, k.pessoa, k.eh_dono, py.phone
                    from public.agenda_capacidade(v_7b_seg, v_7b_seg + 5, p_hoje) k join public.payees py on py.id = k.payee_id
                   order by k.eh_dono, k.pessoa loop
      v_7b_d := public._agenda_dias_declarados(v_7b_x.payee_id, v_7b_seg);
      if v_7b_x.eh_dono then
        v_7b_l := v_7b_l || ('• Você: ' || case when jsonb_array_length(v_7b_d -> 'dias') = 0 and not (v_7b_d ->> 'sabado')::boolean
                                                  then 'só abre e fecha'
                                                  else 'em campo ' || (v_7b_d ->> 'texto') || ' (você disse)' end || '.');
        continue;
      end if;
      continue when v_7b_d ->> 'fonte' = 'nenhum';
      v_7b_l := v_7b_l || format('• %s: %s%s.', v_7b_x.pessoa,
                                 case when jsonb_array_length(v_7b_d -> 'dias') = 0 and not (v_7b_d ->> 'sabado')::boolean then 'não vem'
                                      else v_7b_d ->> 'texto' end,
                                 case when v_7b_d ->> 'fonte' = 'historico'
                                        then ', pelo histórico'
                                             || case when length(regexp_replace(coalesce(v_7b_x.phone, ''), '\D', '', 'g')) < 10
                                                     then ' (sem telefone)' else '' end
                                      else ' (' || case v_7b_d ->> 'origem' when 'dono' then 'você disse'
                                                       when 'diarista' then 'disse em ' || to_char((v_7b_d ->> 'dito_em')::timestamptz at time zone 'America/Sao_Paulo', 'DD/MM')
                                                       else 'anotado em ' || to_char((v_7b_d ->> 'dito_em')::timestamptz at time zone 'America/Sao_Paulo', 'DD/MM') end
                                           || case when length(regexp_replace(coalesce(v_7b_x.phone, ''), '\D', '', 'g')) < 10
                                                   then '; sem telefone' else '' end || ')' end);
    end loop;
    -- a semana seguinte (a que a quinta passada perguntou)
    v_7b_prox := array(select case when y.eh_dono
                                   then 'você ' || case when jsonb_array_length(y.v -> 'dias') = 0 and not (y.v ->> 'sabado')::boolean
                                                        then 'só abre e fecha' else 'em campo ' || (y.v ->> 'texto') end
                                   else y.pessoa || ' ' || case when jsonb_array_length(y.v -> 'dias') = 0 and not (y.v ->> 'sabado')::boolean
                                                                then 'não vem' else y.v ->> 'texto' end end
                         from (select k.payee_id, k.pessoa, k.eh_dono, public._agenda_dias_declarados(k.payee_id, v_7b_seg - 7) as v
                                 from (select distinct c.payee_id, c.pessoa, c.eh_dono
                                         from public.agenda_capacidade(v_7b_seg - 7, v_7b_seg - 2, p_hoje) c) k) y
                        where y.eh_dono or y.v ->> 'fonte' <> 'nenhum'
                        order by y.eh_dono, y.pessoa, y.payee_id);
    v_7b_l := v_7b_l || format('Semana de %s%s: %s.', to_char(v_7b_seg - 7, 'DD/MM'),
                               case when exists (select 1 from public.agenda_disponibilidade w
                                                  where w.substituida_em is null and w.semana_dita = v_7b_seg - 7)
                                    then ' (já presa)' else '' end,
                               array_to_string(v_7b_prox, '; '));
    -- as faltas nos dias ditos (só medida) de quem tem dias fixos
    v_7b_falta := array(select public._agenda_nome_curto(py.name) || ' ' || (public._agenda_chance_de_falta(py.id, p_hoje) ->> 'texto')
                          from public.payees py
                         where py.id = any (v_7b_grade)
                           and exists (select 1 from public.agenda_disponibilidade w
                                        where w.payee_id = py.id and w.substituida_em is null and w.dias_semana is not null
                                          and w.situacao in ('disponivel', 'confirmada'))
                         order by py.name, py.id);
    if cardinality(v_7b_falta) > 0 then
      v_7b_l := v_7b_l || format('Faltas nos dias ditos (%s semanas): %s.', cf.falta_semanas, array_to_string(v_7b_falta, '; '));
    end if;
    -- as duplas: os dias com diária em que vieram 2 pessoas ou mais
    select count(*) filter (where z.n >= 2), count(*) into v_7b_dd, v_7b_dn
      from (select s.data, count(distinct w.payee_id) as n
              from public.work_shifts s join public.work_profiles w on w.id = s.work_profile_id
             where s.tipo = 'diaria' and s.fracao > 0 and s.data >= p_hoje - c_7b_duplas_dias and s.data < p_hoje
             group by s.data) z;
    v_7b_l := v_7b_l || case when v_7b_dn = 0
                             then format('Duplas nos últimos %s dias: nenhum dia com diária.', c_7b_duplas_dias)
                             else format('Duplas nos últimos %s dias: %s de %s dias com diária tiveram 2 pessoas ou mais.',
                                         c_7b_duplas_dias, v_7b_dd, v_7b_dn) end;
    -- quem vem sob demanda (na grade, sem dias fixos): as datas ditas de hoje a +13 dias
    v_7b_sd := array(select format('%s (%s)', y.nome, public._agenda_dias_texto(y.datas))
                       from (select public._agenda_nome_curto(py.name) as nome, py.name, py.id,
                                    array(select distinct g::date
                                            from public.agenda_disponibilidade w,
                                                 generate_series(greatest(lower(w.periodo), p_hoje), least(upper(w.periodo) - 1, p_hoje + 13), interval '1 day') g
                                           where w.payee_id = py.id and w.substituida_em is null and w.periodo is not null
                                             and w.situacao in ('disponivel', 'confirmada')
                                             and w.periodo && daterange(p_hoje, p_hoje + 13, '[]') order by 1) as datas
                               from public.payees py
                              where py.id = any (v_7b_grade)
                                and not exists (select 1 from public.agenda_disponibilidade w
                                                 where w.payee_id = py.id and w.substituida_em is null and w.dias_semana is not null
                                                   and w.situacao in ('disponivel', 'confirmada'))) y
                      where cardinality(y.datas) > 0
                      order by y.name, y.id);
    v_7b_l := v_7b_l || case when cardinality(v_7b_sd) = 0 then 'Sob demanda: ninguém dito.'
                             else 'Sob demanda (só nos dias que você diz): ' || public._agenda_lista(v_7b_sd, null) || '.' end;
    -- quem saiu da agenda (tinha linha, nenhuma viva, a última trocada há até equipe_chamada_dias dias; na ordem do cadastro)
    select coalesce(array_agg(z.nomes order by z.em), '{}'::text[]),
           coalesce(array_agg(to_char(z.em, 'DD/MM') order by z.em), '{}'::text[]), coalesce(sum(z.n), 0)::int
      into v_7b_sai, v_7b_sai_em, v_7b_n
      from (select y.em, count(*)::int as n, public._agenda_lista(array_agg(y.nome order by y.desde, y.nome), null) as nomes
              from (select public._agenda_nome_curto(py.name) as nome, py.created_at as desde,
                           (max(w.substituida_em) at time zone 'America/Sao_Paulo')::date as em
                      from public.agenda_disponibilidade w join public.payees py on py.id = w.payee_id
                     where w.payee_id is distinct from public._agenda_dono(null) and not (w.payee_id = any (v_7b_grade))
                     group by w.payee_id, py.name, py.created_at
                    having bool_and(w.substituida_em is not null)
                       and (max(w.substituida_em) at time zone 'America/Sao_Paulo')::date >= p_hoje - cf.equipe_chamada_dias) y
             group by y.em) z;
    if cardinality(v_7b_sai) = 1 then
      v_7b_l := v_7b_l || format('%s da agenda em %s: %s.', case when v_7b_n = 1 then 'Saiu' else 'Saíram' end, v_7b_sai_em[1],
                                 v_7b_sai[1]);
    elsif cardinality(v_7b_sai) > 1 then
      v_7b_l := v_7b_l || ('Saíram da agenda: '
                           || array_to_string(array(select v_7b_sai[i] || ' em ' || v_7b_sai_em[i]
                                                      from generate_subscripts(v_7b_sai, 1) i order by i), '; ') || '.');
    end if;
    return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_l || v_7b_l, cf.texto_max),
                              'dados', jsonb_build_object('hoje', p_hoje, 'proximo', v_am, 'modo', cf.modo_equipe,
                                                          'semana', v_7b_seg, 'prazo_em', v_7b_ps -> 'prazo_em',
                                                          'modo_dias', cf.modo_dias, 'modo_cadastro', cf.modo_cadastro));
  end if;
  -- FASE 7b: fim
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_l, cf.texto_max),
                            'dados', jsonb_build_object('hoje', p_hoje, 'proximo', v_am, 'modo', cf.modo_equipe));
end;
$function$;

comment on function public._agenda_ver_equipe(date) is
  'Agenda de Produção (Fase 3, P6): agenda_ver foco equipe — hoje e o próximo dia útil, por pessoa da rotina: a ficha, a confirmação e o "como foi hoje?" (mandei às HH:MI e ele ainda não respondeu; respondeu "…" às HH:MI; não mandei e por quê; em sombra, eu mandaria), confirmou ou avisou que não vem; e quem do plano não tem a rotina ("Sem a rotina (o dia é pelo *dia feito*): João."). Desligada: "A rotina da equipe está desligada". {ok, texto, dados}. FASE 7b (P3, §6.4 com o R4.1-6): com modo_dias ou modo_cadastro fora de desligado, depois das linhas de hoje e do próximo dia útil, o bloco da semana — "Dias da semana de 16/11 (pergunto toda quinta; o prazo é qui 12/11 às 16:00):" (em teste: "Em teste (não perguntei a ninguém): eu perguntaria a Rafael na qui 05/11 às 16:45 os dias da semana de 16/11; os dias abaixo são os de agora."; sem ninguém na rotina com telefone e dias fixos, a frase diz isso), cada pessoa da grade com o que vale (_agenda_dias_declarados: "• Alex: de seg a sex (você disse; sem telefone).", "• Rafael: seg, ter e qui (disse em 06/11).", "• João: de ter a sex, pelo histórico (sem telefone).") e você ("• Você: só abre e fecha."); "Semana de 09/11 (já presa): …"; "Faltas nos dias ditos (8 semanas): Rafael 2 de 13; …" (_agenda_chance_de_falta); "Duplas nos últimos 60 dias: 17 de 34 dias com diária tiveram 2 pessoas ou mais."; "Sob demanda (só nos dias que você diz): Mateus (qua 11 e qui 12/11)." (ninguém: "Sob demanda: ninguém dito."); "Saíram da agenda em 30/10: Roberto e João.". dados ganha semana, prazo_em, modo_dias e modo_cadastro. Desligados, o de antes, byte a byte.';

-- _agenda_linhas_do_fechamento (de 20261031100985_agenda_fase77a_correcao2.sql)
create or replace function public._agenda_linhas_do_fechamento(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_max   constant int := 480;   -- estrutural: uma linha da agenda no fechamento
  -- FASE 3: o fim do texto da conferência da vigia (é o que a linha dia troca quando tem o que contar da equipe)
  c_cauda constant text := ' Foi isso? Responda *dia feito* ou conte o que mudou.';
  v_ini   date;
  v_am1   date;
  v_am2   date;
  v_out   jsonb := '[]'::jsonb;
  q       record;
  g       jsonb;
  v_m     jsonb;
  v_ms    jsonb;
  v_conf  record;
  v_txts  text[];
  v_ids   jsonb;
  v_txt   text;
  v_mod   text;
  v_n     int;
  k       int;
  m       text;
  -- FASE 3
  v_eq    jsonb;
  v_base  text;
  v_dia   text;
  v_som   text;
  v_extra text;
  v_cauda text;
  v_pend  jsonb;
  v_tec   text;
  v_cob   text;
  v_ppc   jsonb;
  v_com   jsonb;
  -- FASE 7: (7a P7) a linha do gestor em teste e a das compras da semana
  v_f7_txt   text;
  v_f7_cmp   jsonb;
  v_f7_min   date;
  v_f7_urg   boolean;
  v_f7_perda int;
  -- FASE 7: fim
  -- FASE 7: (7a correção, achados 15 e 18) a linha das perguntas do gestor
  c_max_perg  constant int := 600;   -- estrutural: até 640 na coleta, como a do cliente
  v_f77_ids   jsonb;
  v_f77_txt   text;
  v_f77_prazo boolean;
  v_f77_segs  text[];
  v_f77_grupo text;
  v_f77_itens text[];
  v_f77_rest  int;
  v_f77_nl    text;
  v_f77_item  text;
  v_f77_ns    text[];
  v_f77_ni    text[];
  v_f77_l     text;
  v_f77_q     record;
  -- FASE 7: fim
  -- FASE 7b: (7b P3, R4.2(d)) a linha (n) da equipe
  v_7b_on     boolean;
  v_7b_ids    jsonb;
  v_7b_txt    text;
  v_7b_itens  text[];
  v_7b_curtos text[];
  v_7b_rest   int;
  v_7b_perde  boolean;
  v_7b_lig    boolean;
  v_7b_item   text;
  v_7b_curto  text;
  v_7b_l      text;
  v_7b_q      record;
  -- FASE 7b: fim
begin
  if p_hoje is null then
    raise exception 'agenda: sem o dia de hoje' using errcode = '22004';
  end if;
  if cf.modo_proposta = 'desligado' and cf.modo_vigia = 'desligado' then
    return '[]'::jsonb;
  end if;
  v_ini := p_hoje - 6;
  v_am1 := public.agenda_somar_du(p_hoje, 1);
  v_am2 := public.agenda_somar_du(p_hoje, 2);

  -- (a) as decisões críticas abertas
  -- FASE 3: menos a da diária, que tem a linha dela (b2)
  for q in select x.* from public.agenda_perguntas x where x.critica and x.estado = 'aberta' and x.tipo <> 'diaria'
            order by x.perda_em nulls last, x.criada_em, x.id loop
    v_out := v_out || jsonb_build_object('tipo', 'decisao',
      'texto', 'Agenda, preciso de você. ' || q.texto || ' Me responda aqui.',
      'perda', case when q.perda_em is not null and q.perda_em <= v_am1 then 100
                    when q.perda_em is not null and q.perda_em <= v_am2 then 80 else 50 end,
      'pergunta_id', q.id, 'acao_ids', '[]'::jsonb,
      'modo', case when q.modo = 'ligado' and cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- FASE 3 (a2): a diária que diverge do plano (crítica): as opções, a recomendação e as palavras que respondem.
  -- A perda: o banco não sabe quando o acerto fecha (o dono fecha quando quer); com 2 dias úteis sem resposta, 80.
  for q in select x.* from public.agenda_perguntas x where x.tipo = 'diaria' and x.estado = 'aberta'
            order by x.perda_em nulls last, x.criada_em, x.id loop
    v_out := v_out || jsonb_build_object('tipo', 'diaria',
      'texto', 'Diária, preciso de você: ' || public._agenda_texto_da_diaria(q.id),
      'perda', case when public.agenda_du_entre(coalesce(q.dia, q.perda_em, p_hoje), p_hoje) >= 2 then 80 else 50 end,
      'pergunta_id', q.id, 'acao_ids', '[]'::jsonb,
      'modo', case when q.modo = 'ligado' and cf.modo_diaria = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- (b) o que mudou sozinho (de verdade e na sombra), ainda não contado
  v_m := public._agenda_mudancas(v_ini, p_hoje, true, true, null);
  v_ms := public._agenda_mudancas(v_ini, p_hoje, false, true, null);

  -- (c) a semana publicada
  for g in select x from jsonb_array_elements(v_m) x where x ->> 'tipo' = 'publicacao' loop
    v_out := v_out || jsonb_build_object('tipo', 'semana',
      'texto', public._agenda_linha_da_semana((g ->> 'proposta_id')::uuid, g -> 'acao_ids', (g ->> 'desfazivel')::boolean, p_hoje),
      'perda', 60, 'pergunta_id', null, 'acao_ids', g -> 'acao_ids',
      'modo', case when cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end);
  end loop;
  for g in select x from jsonb_array_elements(v_ms) x where x ->> 'tipo' = 'publicacao' loop
    v_out := v_out || jsonb_build_object('tipo', 'semana',
      'texto', public._agenda_linha_da_semana((g ->> 'proposta_id')::uuid, g -> 'acao_ids', false, p_hoje),
      'perda', 60, 'pergunta_id', null, 'acao_ids', g -> 'acao_ids', 'modo', 'sombra');
  end loop;

  -- (d) a conferência de hoje, com o que mudou sozinho; sem ela, o que mudou numa linha só
  select x.* into v_conf from public.agenda_perguntas x
   where x.tipo = 'conferencia' and x.estado = 'aberta' and x.dia = p_hoje
   order by (x.modo = 'ligado') desc, x.criada_em desc, x.id desc limit 1;
  -- FASE 3: o que a equipe confirmou, a diária que a agenda lançou, quem falta confirmar e o último dia da OS
  v_eq := public._agenda_dia_da_equipe(p_hoje);
  v_pend := v_eq -> 'pendentes';
  v_extra := nullif(array_to_string(array(select x from jsonb_array_elements_text(v_eq -> 'lig') x
                                          union all select x from jsonb_array_elements_text(v_eq -> 'ultimo') x), ' '), '');
  for m in select unnest(array['ligado', 'sombra']) loop
    v_txts := array(select public._agenda_mudanca_texto(x, false)
                      from jsonb_array_elements(case when m = 'ligado' then v_m else v_ms end) with ordinality t(x, o)
                     where x ->> 'tipo' = 'acao' order by o);
    v_ids := coalesce((select jsonb_agg(y order by o, o2)
                         from jsonb_array_elements(case when m = 'ligado' then v_m else v_ms end) with ordinality t(x, o),
                              jsonb_array_elements(x -> 'acao_ids') with ordinality u(y, o2)
                        where x ->> 'tipo' = 'acao'), '[]'::jsonb);
    v_mod := case when m = 'ligado' and cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end;
    if v_conf.id is not null and v_conf.modo = m then
      -- FASE 3: o texto do dia com a equipe. Sem nada a contar, é o da conferência, byte a byte.
      v_dia := v_conf.texto;
      if v_extra is not null or jsonb_array_length(v_pend) > 0 then
        v_base := case when right(v_conf.texto, char_length(c_cauda)) = c_cauda
                       then left(v_conf.texto, char_length(v_conf.texto) - char_length(c_cauda)) else v_conf.texto end;
        v_cauda := case
          when jsonb_array_length(v_pend) = 1
            then format(' Foi isso para o %s? *dia feito* lança a %s dele, ou conte o que mudou.', v_pend -> 0 ->> 'nome',
                        case when (v_pend -> 0 ->> 'meios')::int = 1 then 'meia diária' else 'diária' end)
          when jsonb_array_length(v_pend) > 1
            then format(' Foi isso para %s? *dia feito* lança as diárias deles, ou conte o que mudou.',
                        public._agenda_lista(array(select 'o ' || (e ->> 'nome') from jsonb_array_elements(v_pend) with ordinality t(e, o)
                                                    order by o), null))
          when (v_eq ->> 'aguardando')::int > 0 and cf.modo_diaria = 'ligado' then ' Foi isso? *dia feito* lança agora.'
          else c_cauda end;
        v_dia := v_base || coalesce(' ' || v_extra, '') || v_cauda;
      end if;
      v_ids := v_ids || (v_eq -> 'ids');
      for k in reverse cardinality(v_txts) .. 0 loop
        v_txt := v_dia
                 || case when k > 0 then ' Mudei sozinho: ' || array_to_string(v_txts[1:k], ' ')
                                         || case when k < cardinality(v_txts) then format(' (e mais %s em *o que mudou*)', cardinality(v_txts) - k) else '' end
                         when cardinality(v_txts) > 0 then format(' Mudei sozinho %s: *o que mudou* mostra.',
                                                                   public._agenda_plural(cardinality(v_txts), 'coisa', 'coisas'))
                         else '' end;
        exit when char_length(v_txt) <= c_max;
      end loop;
      v_out := v_out || jsonb_build_object('tipo', 'dia', 'texto', v_txt, 'perda', 70, 'pergunta_id', v_conf.id, 'acao_ids', v_ids,
        'modo', case when v_conf.modo = 'ligado' and cf.modo_vigia = 'ligado' and v_mod = 'ligado' then 'ligado' else 'sombra' end);
      -- FASE 3: o que a sombra da equipe e da diária diria, só no detalhe
      if jsonb_array_length(v_eq -> 'som') > 0 then
        v_som := v_dia || ' ' || array_to_string(array(select x from jsonb_array_elements_text(v_eq -> 'som') x), ' ');
        v_out := v_out || jsonb_build_object('tipo', 'dia', 'texto', public._agenda_corta(v_som, c_max), 'perda', 70,
                                             'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', 'sombra');
      end if;
    elsif cardinality(v_txts) > 0 then
      for k in reverse cardinality(v_txts) .. 1 loop
        v_txt := 'Agenda, mudei sozinho. ' || array_to_string(v_txts[1:k], ' ')
                 || case when k < cardinality(v_txts) then format(' (e mais %s em *o que mudou*)', cardinality(v_txts) - k) else '' end;
        exit when char_length(v_txt) <= c_max;
      end loop;
      v_out := v_out || jsonb_build_object('tipo', 'mudancas', 'texto', v_txt, 'perda', 40, 'pergunta_id', null, 'acao_ids', v_ids,
                                           'modo', v_mod);
    end if;
  end loop;
  -- a conferência na sombra sem nada a contar junto, ou de um modo sem mudança (o laço acima já cobriu quem teve)
  -- (nada a fazer: o laço passa pelos dois modos)

  -- FASE 3 (d1): sem a conferência aberta (todos confirmaram), o dia com o que a equipe e a diária contam numa linha
  -- própria: a diária que a agenda lançou ("*diária Roberto meia* corrige") e o último dia da OS.
  if v_conf.id is null and (v_extra is not null or jsonb_array_length(v_eq -> 'som') > 0) then
    v_base := public._agenda_texto_do_dia(p_hoje);
    if v_base is not null then
      v_cauda := case when jsonb_array_length(v_eq -> 'lancadas') > 0
                      then format(' *diária %s %s* corrige.', v_eq -> 'lancadas' -> 0 ->> 'nome',
                                  case when (v_eq -> 'lancadas' -> 0 ->> 'fracao')::numeric = 1 then 'meia' else 'inteira' end)
                      else '' end;
      if v_extra is not null then
        v_out := v_out || jsonb_build_object('tipo', 'dia', 'texto', public._agenda_corta(v_base || ' ' || v_extra || v_cauda, c_max),
          'perda', 70, 'pergunta_id', null, 'acao_ids', v_eq -> 'ids',
          'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
      end if;
      if jsonb_array_length(v_eq -> 'som') > 0 then
        v_out := v_out || jsonb_build_object('tipo', 'dia',
          'texto', public._agenda_corta(v_base || coalesce(' ' || v_extra, '') || ' '
                                        || array_to_string(array(select x from jsonb_array_elements_text(v_eq -> 'som') x), ' '), c_max),
          'perda', 70, 'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', 'sombra');
      end if;
    end if;
  end if;

  -- FASE 3 (d2): o que o gestor concluiu pela palavra do técnico (o técnico disse que terminou e era o último dia do
  -- plano), ainda não contado: a cobrança que a conclusão disse e o *desfaz* pelo número (a OS saiu da carteira).
  for q in select x.* from public.agenda_acoes x
            where x.tipo = 'concluir' and x.origem = 'equipe' and x.contada_em is null and x.desfeita_em is null
              and x.dia between v_ini and p_hoje
            order by x.criada_em, x.id loop
    v_tec := (select public._agenda_nome_curto(py.name) from public.agenda_equipe_mensagens em
                join public.payees py on py.id = em.payee_id where em.acao_id = q.id
               order by em.resposta_em desc nulls last limit 1);
    if q.executada then
      -- revisão da Fase 3 (item 5): o "vence hoje" de outro dia pelo ajudante único
      v_cob := public._agenda_vence_no_dia(regexp_replace(q.texto, '^[^—]* — saída [^.]*\.\s*', ''), q.dia, p_hoje);
      v_txt := format('Concluí o %s%s: o %s disse que terminou e era o último dia do plano.%s *desfaz %s* reabre.',
                      public._agenda_rotulo_da_os(q.service_order_id),
                      case when q.dia <> p_hoje then ' ' || public._dia_curto(q.dia) else '' end,
                      coalesce(v_tec, 'técnico'), coalesce(' ' || nullif(v_cob, q.texto), ''),
                      (select so.service_order_number from public.service_orders so where so.id = q.service_order_id));
    else
      v_txt := q.texto;
    end if;
    v_out := v_out || jsonb_build_object('tipo', 'conclusao', 'texto', public._agenda_corta(v_txt, c_max), 'perda', 45,
      'pergunta_id', null, 'acao_ids', jsonb_build_array(q.id),
      'modo', case when q.executada and cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- FASE 7: (7a correção, achados 15 e 18; no lugar da linha (l) do 7a P11) (m) as perguntas do gestor que esperam o dono numa
  -- linha só: a ficha_estimativa de hoje (a ficha das 19:30 de um dia pela estimativa, que perde hoje), a situacao, a estimativa e
  -- o reestimar. Antes, cada uma disputava sozinha a vaga da pergunta de fato (e), de perda 30, e nenhuma chegava ao dono: o prazo
  -- só vale com a pergunta vista, e o gestor não marcava (Nelson, Flávio, Giancarlo e MP fora a semana inteira); a da ficha perdia
  -- para a mensagem ao cliente da véspera, e a ficha do 1º dia ficava segurada. A 1ª (a ficha; depois a de prazo mais perto) vai
  -- com o texto inteiro; as outras curtas, agrupadas pelo prazo ("Também, sem resposta até ter 03/11 18:00: Nelson (OS-00112) 4
  -- dias; Flávio (OS-00104) 3,5 dias."; sem prazo: "Espero você: Giancarlo (OS-00130)."), até c_max_perg; o resto fica para
  -- *agenda gestor*. O fechamento que sai conta como mostradas todas as que a linha leva (pergunta_ids). Perda 75 com alguma de
  -- prazo (ela perde no prazo), 30 sem; modo = o da vigia.
  for m in select unnest(array['ligado', 'sombra']) loop
    v_f77_ids := '[]'::jsonb;
    v_f77_txt := null;
    v_f77_prazo := false;
    v_f77_segs := '{}';
    v_f77_grupo := null;
    v_f77_itens := '{}';
    v_f77_rest := 0;
    for v_f77_q in
      select x.id, x.texto, x.veto_ate, x.service_order_id, x.tipo,
             case when x.veto_ate is null then null
                  else public._dia_curto((x.veto_ate at time zone 'America/Sao_Paulo')::date) || ' '
                       || to_char(x.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI') end as ate,
             (select (o -> 'efeito' ->> 'dias')::numeric from jsonb_array_elements(coalesce(x.opcoes, '[]'::jsonb)) o
               where (o ->> 'n')::int = x.opcao_padrao limit 1) as dias_padrao
        from public.agenda_perguntas x
       where x.estado = 'aberta' and x.modo = m and not x.critica and x.opcao_escolhida is null
         and ((x.tipo = 'ficha_estimativa' and x.veto_ate is not null
               and (x.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
              or (x.tipo in ('situacao', 'estimativa', 'reestimar')
                  and (x.veto_ate is null or (x.veto_ate at time zone 'America/Sao_Paulo')::date >= p_hoje)))
         and x.mostrada_vezes < cf.perguntas_vezes_max
         and not exists (select 1 from public.agenda_dono_avisos v
                          where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
       order by x.tipo = 'ficha_estimativa' desc, x.veto_ate nulls last, x.criada_em, x.id
    loop
      if v_f77_txt is null then
        v_f77_txt := 'Agenda: ' || v_f77_q.texto;
        v_f77_ids := jsonb_build_array(v_f77_q.id);
        v_f77_prazo := v_f77_q.veto_ate is not null;
        continue;
      end if;
      if v_f77_rest > 0 then
        v_f77_rest := v_f77_rest + 1;
        continue;
      end if;
      -- (7a correção 2) sem prazo, o porquê junto: acima do teto de diárias o gestor não marca sozinho
      v_f77_nl := case when v_f77_q.ate is null then 'Espero você (não marco sozinho): ' else format('Também, sem resposta até %s: ', v_f77_q.ate) end;
      v_f77_item := public._agenda_rotulo_da_os(v_f77_q.service_order_id)
                    || case when v_f77_q.dias_padrao is not null then ' ' || public._agenda_dias(v_f77_q.dias_padrao) else '' end;
      if v_f77_nl is distinct from v_f77_grupo then
        v_f77_ns := v_f77_segs || case when v_f77_grupo is not null then array[v_f77_grupo || array_to_string(v_f77_itens, '; ') || '.']
                                       else '{}'::text[] end;
        v_f77_ni := array[v_f77_item];
      else
        v_f77_ns := v_f77_segs;
        v_f77_ni := v_f77_itens || v_f77_item;
      end if;
      v_f77_l := v_f77_txt || ' ' || array_to_string(v_f77_ns || (v_f77_nl || array_to_string(v_f77_ni, '; ') || '.'), ' ');
      -- cabe com o "(e mais N em *agenda gestor*)" que pode vir depois
      if char_length(v_f77_l) > c_max_perg - 32 then
        v_f77_rest := 1;
        continue;
      end if;
      v_f77_segs := v_f77_ns;
      v_f77_grupo := v_f77_nl;
      v_f77_itens := v_f77_ni;
      v_f77_ids := v_f77_ids || to_jsonb(v_f77_q.id);
      v_f77_prazo := v_f77_prazo or v_f77_q.veto_ate is not null;
    end loop;
    continue when v_f77_txt is null;
    v_f77_l := v_f77_txt
               || case when v_f77_grupo is not null
                       then ' ' || array_to_string(v_f77_segs || (v_f77_grupo || array_to_string(v_f77_itens, '; ') || '.'), ' ')
                       else '' end
               || case when v_f77_rest > 0 then format(' (e mais %s em *agenda gestor*)', v_f77_rest) else '' end;
    -- (7a correção 2, os achados 15/18 de novo) perda 76 com alguma de prazo: entre as linhas que perdem hoje ela ganha o desempate
    -- (antes, 75 com a mensagem ao cliente, ela perdia pelo tipo — "cliente" < "pergunta" — e saía primeiro no corte de 1.000)
    -- (7a correção 2) o objeto da linha entre parênteses: a forma curta (abaixo) entra nele, não como outro item da lista
    v_out := v_out || (jsonb_build_object('tipo', 'pergunta', 'texto', v_f77_l, 'perda', case when v_f77_prazo then 76 else 30 end,
      'pergunta_id', v_f77_ids ->> 0, 'pergunta_ids', v_f77_ids, 'acao_ids', '[]'::jsonb,
      'modo', case when m = 'ligado' and cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end)
      -- (7a correção 2, o corte de 1.000 do fechamento) a mesma linha na forma curta (texto_curto), com as MESMAS perguntas: a
      -- ficha sem as opções ("… pela minha estimativa. Para segurar, me diga.") e cada uma pelo prazo e pelo que o gestor faz sem
      -- resposta ("Sem resposta até ter 03/11 18:00, conto: Nelson (OS-00112) 4 dias; …"). O Secretário cheio (3 que ficaram, ~900
      -- caracteres) usa esta antes de tirar a linha — a inteira (~400) não cabia e as perguntas nunca eram vistas.
      || coalesce((select jsonb_build_object('texto_curto', k.t) from (select
           'Agenda: ' || concat_ws(' ',
             (select split_part(pc.texto, ' 1) Mande', 1) || ' Para segurar, me diga.' from public.agenda_perguntas pc
               where pc.id = (v_f77_ids ->> 0)::uuid and pc.tipo = 'ficha_estimativa'),
             (select string_agg(g.grupo || g.itens || '.', ' ' order by g.ord)
                from (select case when y.ate is null then 'Espero você (não marco sozinho): '
                                  else format('Sem resposta até %s, conto: ', y.ate) end as grupo,
                             string_agg(y.item, '; ' order by y.o) as itens, min(y.o) as ord
                        from (select t.o,
                                     case when pc.veto_ate is null then null
                                          else public._dia_curto((pc.veto_ate at time zone 'America/Sao_Paulo')::date) || ' '
                                               || to_char(pc.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI') end as ate,
                                     public._agenda_rotulo_da_os(pc.service_order_id)
                                     || coalesce(' ' || public._agenda_dias((select (op -> 'efeito' ->> 'dias')::numeric
                                                                               from jsonb_array_elements(coalesce(pc.opcoes, '[]'::jsonb)) op
                                                                              where (op ->> 'n')::int = pc.opcao_padrao limit 1)), '') as item
                                from jsonb_array_elements_text(v_f77_ids) with ordinality t(id, o)
                                join public.agenda_perguntas pc on pc.id = t.id::uuid
                               where pc.tipo <> 'ficha_estimativa') y
                       group by y.ate) g)) as t) k
         where char_length(k.t) < char_length(v_f77_l)), '{}'::jsonb));
  end loop;
  -- FASE 7: fim
  -- FASE 7b: (7b P3, R4.2(d)) (n) a equipe: as perguntas abertas da equipe — a chamada (equipe_cadastro:chamada), a dos dias do
  -- dono (dias_semana), o telefone e o contato — numa linha só, nesta ordem e depois a mais antiga. Pela pergunta de fato (e), de perda
  -- 30, elas nunca entravam nas vagas (as de fornecedor estão abertas e nunca vistas desde 28/10): a chamada nunca seria vista nem
  -- venceria, e a pergunta da semana ficaria esperando por ela. A 1ª vai com o texto inteiro; as outras, curtas, até c_max_perg; o
  -- resto "(e mais N em *agenda equipe*)". pergunta_ids = todas as que a linha mostra (o fechamento que sai as conta como mostradas;
  -- a chamada vista ganha o prazo na rodada da semana). Perda 75 enquanto alguma nunca foi mostrada (o prazo só começa depois de vista)
  -- ou perde hoje (o veto_ate ou o perda_em de hoje): vaga própria entre as que perdem hoje; senão 30. Modo ligado só com a pergunta
  -- em ligado e o modo dela (o de _agenda_modo_da_pergunta: modo_dias; modo_cadastro fora de desligado, senão o do gestor) ligado.
  -- texto_curto = as mesmas perguntas só pelo nome. Só com modo_dias ou modo_cadastro fora de desligado (senão, o de antes); a (e)
  -- não as repete.
  v_7b_on := cf.modo_dias <> 'desligado' or cf.modo_cadastro <> 'desligado';
  if v_7b_on then
    for m in select unnest(array['ligado', 'sombra']) loop
      v_7b_ids := '[]'::jsonb;
      v_7b_txt := null;
      v_7b_itens := '{}';
      v_7b_curtos := '{}';
      v_7b_rest := 0;
      v_7b_perde := false;
      v_7b_lig := true;
      for v_7b_q in
        select x.id, x.tipo, x.chave, x.texto, x.dia, x.mostrada_vezes, x.veto_ate, x.perda_em,
               coalesce((select public._agenda_nome_curto(py.name) from public.payees py where py.id = x.payee_id), '') as nome,
               case when x.tipo = 'dias_semana' then cf.modo_dias
                    when cf.modo_cadastro <> 'desligado' then cf.modo_cadastro
                    else public._agenda_gestor_modo('marcar') end as modo_agora
          from public.agenda_perguntas x
         where x.estado = 'aberta' and x.modo = m and not x.critica and x.tipo in ('equipe_cadastro', 'dias_semana')
           and x.mostrada_vezes < cf.perguntas_vezes_max
           and not exists (select 1 from public.agenda_dono_avisos v
                            where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
         order by case when x.chave like 'equipe_cadastro:chamada:%' then 1 when x.tipo = 'dias_semana' then 2
                       when x.chave like 'equipe_cadastro:telefone:%' then 3 else 4 end, x.criada_em, x.id
      loop
        v_7b_curto := case
          when v_7b_q.chave like 'equipe_cadastro:chamada:%' then 'a equipe da agenda está certa?'
          when v_7b_q.tipo = 'dias_semana' then format('os dias da semana de %s', to_char(v_7b_q.dia, 'DD/MM'))
          when v_7b_q.chave like 'equipe_cadastro:telefone:%' then format('o telefone do %s', v_7b_q.nome)
          else format('%s na rotina da equipe?', v_7b_q.nome) end;
        if v_7b_txt is null then
          v_7b_txt := 'Agenda: ' || v_7b_q.texto;
        else
          if v_7b_rest > 0 then
            v_7b_rest := v_7b_rest + 1;
            continue;
          end if;
          v_7b_item := case
            when v_7b_q.chave like 'equipe_cadastro:telefone:%'
              then format('Também: o telefone do %s (sem ele não mando a ficha).', v_7b_q.nome)
            when v_7b_q.chave like 'equipe_cadastro:contato:%'
              then format('Também: %s tem telefone; ponho na rotina? Responda 1 ou 2 em *agenda pendências*.', v_7b_q.nome)
            when v_7b_q.tipo = 'dias_semana'
              then format('Também: os dias da semana de %s (responda em *agenda pendências*).', to_char(v_7b_q.dia, 'DD/MM'))
            else 'Também: a chamada da equipe (responda em *agenda pendências*).' end;
          if char_length(array_to_string(array[v_7b_txt] || v_7b_itens || v_7b_item, ' ')) > c_max_perg - 32 then
            v_7b_rest := 1;
            continue;
          end if;
          v_7b_itens := v_7b_itens || v_7b_item;
        end if;
        v_7b_ids := v_7b_ids || to_jsonb(v_7b_q.id);
        v_7b_curtos := v_7b_curtos || v_7b_curto;
        v_7b_lig := v_7b_lig and v_7b_q.modo_agora = 'ligado';
        v_7b_perde := v_7b_perde or v_7b_q.mostrada_vezes = 0
                      or (v_7b_q.veto_ate is not null and (v_7b_q.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                      or v_7b_q.perda_em is not distinct from p_hoje;
      end loop;
      continue when v_7b_txt is null;
      v_7b_l := array_to_string(array[v_7b_txt] || v_7b_itens, ' ')
                || case when v_7b_rest > 0 then format(' (e mais %s em *agenda equipe*)', v_7b_rest) else '' end;
      v_7b_curto := 'Agenda, equipe: ' || array_to_string(v_7b_curtos, '; ')
                    || case when right(v_7b_curtos[cardinality(v_7b_curtos)], 1) = '?' then '' else '.' end
                    || ' *agenda pendências* mostra.';
      v_out := v_out || (jsonb_build_object('tipo', 'pergunta', 'texto', v_7b_l, 'perda', case when v_7b_perde then 75 else 30 end,
        'pergunta_id', v_7b_ids ->> 0, 'pergunta_ids', v_7b_ids, 'acao_ids', '[]'::jsonb,
        'modo', case when m = 'ligado' and v_7b_lig then 'ligado' else 'sombra' end)
        || case when char_length(v_7b_curto) < char_length(v_7b_l) then jsonb_build_object('texto_curto', v_7b_curto)
                else '{}'::jsonb end);
    end loop;
  end if;
  -- FASE 7b: fim
  -- (e) uma pergunta de fato, a que perde primeiro (cada pergunta aparece em até perguntas_vezes_max fechamentos)
  -- FASE 3: entram também concluir, entrega, equipe_resposta e diaria_ligar (não críticas)
  for m in select unnest(array['ligado', 'sombra']) loop
    select count(*) into v_n from public.agenda_perguntas x
     where not x.critica and x.estado = 'aberta' and x.modo = m and x.tipo <> 'conferencia'
       -- FASE 7: (7a P7) nem a pergunta do gestor (situacao/estimativa) em que o dono já escolheu "eu digo os dias": o prazo
       -- dela não vale mais, e o texto o prometia (notas do P4, desvio 4)
       and not (x.tipo in ('situacao', 'estimativa') and x.opcao_escolhida is not null)
       -- FASE 7: fim
       -- FASE 7: (7a P11) nem a ficha_estimativa: ela tem a linha própria (l), acima
       and x.tipo <> 'ficha_estimativa'
       -- FASE 7: fim
       -- FASE 7: (7a correção, achado 15) nem as perguntas do gestor que esperam o dono: elas vão na linha (m), acima
       and x.tipo not in ('situacao', 'estimativa', 'reestimar')
       -- FASE 7: fim
       -- FASE 7b: (7b P3, R4.2(d)) nem as perguntas da equipe: elas vão na linha (n), acima
       and not (v_7b_on and x.tipo in ('equipe_cadastro', 'dias_semana'))
       -- FASE 7b: fim
       -- CORREÇÃO 29/10 (revisão): nem a pergunta que um aviso do gestor de hoje já levou ou está levando (na fila).
       and not exists (select 1 from public.agenda_dono_avisos v
                        where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
       -- CORREÇÃO 29/10 (revisão): fim
       and x.mostrada_vezes < cf.perguntas_vezes_max;
    continue when v_n = 0;
    select x.* into q from public.agenda_perguntas x
     where not x.critica and x.estado = 'aberta' and x.modo = m and x.tipo <> 'conferencia'
       -- FASE 7: (7a P7) nem a pergunta do gestor (situacao/estimativa) em que o dono já escolheu "eu digo os dias": o prazo
       -- dela não vale mais, e o texto o prometia (notas do P4, desvio 4)
       and not (x.tipo in ('situacao', 'estimativa') and x.opcao_escolhida is not null)
       -- FASE 7: fim
       -- FASE 7: (7a P11) nem a ficha_estimativa: ela tem a linha própria (l), acima
       and x.tipo <> 'ficha_estimativa'
       -- FASE 7: fim
       -- FASE 7: (7a correção, achado 15) nem as perguntas do gestor que esperam o dono: elas vão na linha (m), acima
       and x.tipo not in ('situacao', 'estimativa', 'reestimar')
       -- FASE 7: fim
       -- FASE 7b: (7b P3, R4.2(d)) nem as perguntas da equipe: elas vão na linha (n), acima
       and not (v_7b_on and x.tipo in ('equipe_cadastro', 'dias_semana'))
       -- FASE 7b: fim
       -- CORREÇÃO 29/10 (revisão): nem a pergunta que um aviso do gestor de hoje já levou ou está levando (na fila).
       and not exists (select 1 from public.agenda_dono_avisos v
                        where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
       -- CORREÇÃO 29/10 (revisão): fim
       and x.mostrada_vezes < cf.perguntas_vezes_max
     order by x.perda_em nulls last, x.criada_em, x.id limit 1;
    v_out := v_out || jsonb_build_object('tipo', 'pergunta',
      'texto', 'Agenda: ' || q.texto || case when v_n > 1 then format(' (e mais %s em *agenda pendências*)', v_n - 1) else '' end,
      'perda', 30, 'pergunta_id', q.id, 'acao_ids', '[]'::jsonb,
      'modo', case when m = 'ligado' and cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- FASE 3 (f): o PPC no último dia útil da semana (sexta; com feriado, o dia útil antes), se a semana teve compromisso
  v_ppc := public.agenda_ppc(p_hoje, p_hoje);
  if (v_ppc ->> 'ultimo_dia_util')::boolean and (v_ppc ->> 'compromissos')::int > 0 and v_ppc ->> 'linha' is not null then
    v_out := v_out || jsonb_build_object('tipo', 'ppc', 'texto', public._agenda_corta(v_ppc ->> 'linha', c_max), 'perda', 55,
      'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
  end if;

  -- FASE 3 (g): a comissão do mês que fechou, no 1º dia útil do mês (só a conta: nada é pago). Quem não pode ver a
  -- comissão (42501) não ganha a linha.
  if p_hoje = public.agenda_somar_du(make_date(extract(year from p_hoje)::int, extract(month from p_hoje)::int, 1), 0) then
    begin
      v_com := public.comissao_resumo_do_mes(null, p_hoje);
    exception when sqlstate '42501' then
      v_com := null;
    end;
    if coalesce((v_com ->> 'primeiro_dia_util')::boolean, false) and nullif(v_com ->> 'linha', '') is not null then
      v_out := v_out || jsonb_build_object('tipo', 'comissao', 'texto', v_com ->> 'linha', 'perda', 20,
        'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
    end if;
  end if;

  -- FASE 7: (7a P7) (i) o "eu marcaria assim" do gestor em teste (spec §6.1): com o modo marcar em sombra, o texto_sombra do
  -- diário de hoje (a rodada do gestor das 16:52 o grava), perda 65, com o modo da vigia (o dono lê de verdade o que o gestor
  -- faria). (j) As compras da semana (agenda_gestor_dia.compras de hoje, que o P10 grava, [{texto, compre_ate, urgente}]): perda
  -- 80 com alguma compra urgente (AG7-07: o serviço começa a menos de compra_urgente_du dias úteis — vai como decisão), 65 com
  -- "compre até" hoje ou amanhã, 45 até compras_aviso_du dias úteis; sem nada disso, nenhuma linha. O modo é o do compre_ate.
  if public._agenda_gestor_modo('marcar') = 'sombra' then
    select g.texto_sombra into v_f7_txt from public.agenda_gestor_dia g where g.dia = p_hoje;
    if nullif(btrim(v_f7_txt), '') is not null then
      -- (7a correção, achado 14) em teste, perda 25: abaixo de toda linha de verdade (só a comissão é menor) — a linha de teste
      -- não tira o lugar da semana publicada, da diária, da conclusão nem da pergunta que o dono precisa ver
      v_out := v_out || jsonb_build_object('tipo', 'gestor', 'texto', v_f7_txt, 'perda', 25, 'pergunta_id', null,
        'acao_ids', '[]'::jsonb, 'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
    end if;
  end if;
  select g.compras into v_f7_cmp from public.agenda_gestor_dia g where g.dia = p_hoje;
  if jsonb_array_length(coalesce(v_f7_cmp, '[]'::jsonb)) > 0 then
    select min((e ->> 'compre_ate')::date), coalesce(bool_or((e ->> 'urgente')::boolean), false)
      into v_f7_min, v_f7_urg from jsonb_array_elements(v_f7_cmp) e;
    -- (7a correção, achado 19) o "compre até" de hoje (ou vencido, que comprando hoje ainda chega) é decisão de hoje: perda 80
    v_f7_perda := case when v_f7_urg or (v_f7_min is not null and v_f7_min <= p_hoje) then 80
                       when v_f7_min is not null and v_f7_min <= v_am1 then 65
                       when v_f7_min is not null and v_f7_min <= public.agenda_somar_du(p_hoje, cf.compras_aviso_du) then 45 end;
    v_f7_txt := array_to_string(array(select btrim(e ->> 'texto') from jsonb_array_elements(v_f7_cmp) with ordinality t(e, o)
                                       where nullif(btrim(e ->> 'texto'), '') is not null order by o), ' ');
    if v_f7_perda is not null and nullif(v_f7_txt, '') is not null then
      v_out := v_out || jsonb_build_object('tipo', 'compras', 'texto', public._agenda_corta('Compras: ' || v_f7_txt, c_max),
        'perda', v_f7_perda, 'pergunta_id', null, 'acao_ids', '[]'::jsonb,
        'modo', case when public._agenda_gestor_modo('compre_ate') = 'ligado' then 'ligado' else 'sombra' end);
    end if;
  end if;
  -- FASE 7: fim
  -- FASE 5: (h) a mensagem ao cliente, só com modo_cliente ligado: a que espera *manda cliente* e sai até o próximo dia de
  -- janela (perda 75; até 600 caracteres, c_max_cliente de _agenda_cliente_fechamento) e o que sai sozinho amanhã (perda 40,
  -- com *segura cliente*). As críticas (cliente_aviso) já entram pela linha decisao; o que saiu, pela linha mudancas.
  if cf.modo_cliente = 'ligado' then
    v_out := v_out || public._agenda_cliente_fechamento(p_hoje);
  end if;
  -- FASE 5: fim
  return coalesce((select jsonb_agg(x order by (x ->> 'perda')::int desc, x ->> 'tipo', x ->> 'texto')
                     from jsonb_array_elements(v_out) x), '[]'::jsonb);
end;
$function$;

comment on function public._agenda_linhas_do_fechamento(date) is
  'Agenda de Produção (Fase 2, P5; Fase 3, P6): as linhas da agenda no fechamento das 17:30 — [{tipo (decisao|diaria|dia|ppc|semana|conclusao|mudancas|pergunta|comissao), texto, perda, pergunta_id, acao_ids, modo}] da maior perda para a menor (decisão 100/80/50 pela perda_em; dia 70; semana 60; ppc 55; diaria 50 ou 80 com 2 dias úteis sem resposta; conclusao 45; mudanças 40; pergunta 30; comissao 20). FASE 3: a linha dia conta o que a equipe confirmou, a diária que a agenda lançou ("*diária Roberto meia* corrige"), quem falta confirmar ("Foi isso para o João? *dia feito* lança a meia diária dele") e o último dia da OS (*concluiu <nome>*); sem nada disso, sai byte a byte a da Fase 2. diaria = a pergunta crítica da diária com as opções e as palavras (modo_diaria); conclusao = o que o gestor concluiu pela palavra do técnico, com o *desfaz* pelo número (modo_proposta); ppc = agenda_ppc().linha no último dia útil da semana com compromisso (modo_vigia); comissao = comissao_resumo_do_mes().linha no 1º dia útil do mês (modo_vigia). modo ligado só com o registro em ligado e o modo que o governa ligado agora; o resto sombra (o que diria; vai ao detalhe). O secretário mostra as ligadas que cabem nas vagas (REGRAS.maxManha − as que ficaram) e registra o que saiu (agenda_fechamento_registrar). FASE 5 (P5): cliente (só com modo_cliente ligado; _agenda_cliente_fechamento) — perda 75 com a mensagem que espera *manda cliente* e sai até o próximo dia de janela (a 1ª inteira, até 600 caracteres; acima disso o texto da mensagem é cortado em 300 e *agenda clientes* mostra inteira), perda 40 com o que sai sozinho amanhã e *segura cliente <nome>*. CORREÇÃO 29/10 (revisão): a pergunta de fato (e) não repete a que um aviso do gestor de hoje já levou ou está levando (agenda_dono_avisos enfileirada ou enviada): a pergunta sai uma vez por dia. FASE 7 (7a P7, spec §5.7 e §6.1): (i) com o gestor que marca em teste (_agenda_gestor_modo(''marcar'') = ''sombra''), a linha gestor — o "eu marcaria assim" do diário de hoje (agenda_gestor_dia.texto_sombra, ≤ 640: "Agenda em teste (nada mudou): eu marcaria assim — …"), perda 65, modo = o da vigia; (j) a linha compras — as compras da semana do diário de hoje (agenda_gestor_dia.compras [{texto, compre_ate, urgente}], que o P10 grava): perda 80 com compra urgente (AG7-07: vai como decisão), 65 com "compre até" hoje ou amanhã, 45 até compras_aviso_du dias úteis, modo = o do compre_ate; (k) a pergunta situacao/estimativa em que o dono já escolheu "eu digo os dias" (opcao_escolhida) não volta como linha pergunta (o prazo dela não vale mais). Sem o gestor em teste e sem compras, a saída de antes, byte a byte. FASE 7 (7a P11, spec §3.2 "Equipe" e §5.11): (l) a pergunta ficha_estimativa aberta de hoje (veto_ate hoje: a ficha das 19:30 de um dia pela estimativa, na janela de veto do ligar) numa linha própria, tipo pergunta, perda 75, com o pergunta_id (o fechamento que sai a conta como mostrada), uma por pessoa, modo = o da vigia; a linha (e) não a repete. Sem essa pergunta, a saída de antes, byte a byte. CORREÇÃO DA 7a (revisão da etapa): (achados 15 e 18) (m), no lugar da (l): as perguntas do gestor que esperam o dono — a ficha_estimativa de hoje, situacao, estimativa e reestimar — numa linha só, tipo pergunta: a 1ª (a ficha primeiro, depois a de prazo mais perto) com o texto inteiro, as outras curtas e agrupadas pelo prazo ("Também, sem resposta até ter 03/11 18:00: Nelson (OS-00112) 4 dias; …"; sem prazo: "Espero você: …"), até 600 caracteres, com pergunta_id (a 1ª) e pergunta_ids (todas as que a linha mostra: o fechamento que sai as conta como mostradas); perda 75 com alguma de prazo (ela perde no prazo), 30 sem; a linha (e) não as repete; (achado 14) a linha gestor de teste ("eu marcaria assim") vai com perda 25, abaixo de toda linha de verdade (só a comissão é menor); (achado 19) as compras com "compre até" hoje ou já vencido (comprando hoje ainda chega) vão como decisão, perda 80. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; os achados 15/18 de novo): a linha (m) das perguntas do gestor com prazo vai com perda 76 (ganha o desempate das que perdem hoje: antes perdia para a mensagem ao cliente pelo tipo e saía primeiro no corte de 1.000 do fechamento); as sem prazo dizem o porquê ("Espero você (não marco sozinho): Giancarlo (OS-00130)."); (o corte de 1.000) a linha (m) leva também texto_curto, com as MESMAS perguntas: a ficha sem as opções e cada uma pelo prazo e pelo que o gestor faz sem resposta ("Agenda: Sem resposta até ter 03/11 18:00, conto: Nelson (OS-00112) 4 dias; Flávio (OS-00104) 3,5 dias. Espero você (não marco sozinho): Giancarlo (OS-00130).") — o Secretário cheio a usa antes de tirar a linha. FASE 7b (P3, R4.2(d)): com modo_dias ou modo_cadastro fora de desligado, (n) a equipe — as perguntas abertas da equipe (a chamada equipe_cadastro:chamada, a dias_semana do dono, o telefone e o contato; não críticas, mostradas menos de perguntas_vezes_max vezes, fora as que um aviso de hoje levou) numa linha só, tipo pergunta, nesta ordem e depois a mais antiga: a 1ª com o texto inteiro, as outras curtas ("Também: o telefone do Alex (sem ele não mando a ficha)."; "Também: Mateus tem telefone; ponho na rotina? Responda 1 ou 2 em *agenda pendências*."; "Também: os dias da semana de 16/11 (responda em *agenda pendências*).") até 600 caracteres e o resto "(e mais N em *agenda equipe*)"; pergunta_id = a 1ª e pergunta_ids = todas as que a linha mostra (o fechamento que sai as conta como mostradas); perda 75 enquanto alguma nunca foi mostrada ou perde hoje (veto_ate ou perda_em de hoje), senão 30; modo ligado só com a pergunta em ligado e o modo dela ligado; texto_curto com as mesmas perguntas, só pelo nome ("Agenda, equipe: a equipe da agenda está certa?; o telefone do Alex. *agenda pendências* mostra."). A pergunta de fato (e) não as repete. Com os dois modos desligados, a saída de antes, byte a byte.';

-- _agenda_gestor_equipe (de 20261031100980_agenda_fase77a_correcao.sql)
create or replace function public._agenda_gestor_equipe(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  -- a régua da spec §5.4 ("sem diária em 30 dias"); o 7b traz o parâmetro dele (equipe_inativo_dias)
  c_sem_diaria_dias constant int := 30;
  cf        public.agenda_config;
  v_modo    text;
  v_dono    uuid := public._agenda_dono(null);
  v_seg     date;
  v_chave   text;
  v_hist    text[];
  v_dito    text[];
  v_outro   text[];
  v_semente boolean;
  v_sumidos text[];
  v_partes  text[] := '{}';
  v_txt     text;
  v_id      uuid;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_equipe: sem o dia ou a hora' using errcode = '22004';
  end if;
  -- FASE 7b: (7b P3; R2, §5.2) com o cadastro da equipe da 7b fora de desligado (modo_cadastro), a chamada é a dela
  -- (agenda_equipe_semana: com o telefone dentro e as opções): uma pergunta só ao dono
  if (public._agenda_cfg()).modo_cadastro <> 'desligado' then
    return jsonb_build_object('pulado', 'modo_cadastro');
  end if;
  -- FASE 7b: fim
  v_modo := public._agenda_gestor_modo('marcar');
  if v_modo = 'desligado' then
    return jsonb_build_object('criada', false, 'motivo', 'o gestor está desligado');
  end if;
  cf := public._agenda_cfg();
  if extract(isodow from p_hoje)::int <> cf.dia_do_plano then
    return jsonb_build_object('criada', false, 'motivo', 'a chamada da equipe é no dia do plano');
  end if;
  -- a semana que a próxima publicação monta: depois da hora do plano, a seguinte à que acabou de sair
  v_seg := p_hoje - (extract(isodow from p_hoje)::int - 1)
           + case when (p_agora at time zone 'America/Sao_Paulo')::time >= cf.hora_do_plano then 14 else 7 end;
  v_chave := 'equipe_cadastro:chamada:' || v_seg;
  if exists (select 1 from public.agenda_perguntas q where q.chave = v_chave and q.modo = v_modo) then
    return jsonb_build_object('criada', false, 'motivo', 'já perguntei desta semana', 'semana', v_seg);
  end if;

  -- quem conta na semana (a grade), por pessoa: os dias e de onde eles vêm
  with g as (
    select c.payee_id, c.pessoa, array_agg(distinct extract(isodow from c.dia)::smallint) as dias,
           array_agg(distinct coalesce(c.origem, '-')) as origens
      from public.agenda_capacidade(v_seg, v_seg + 5, p_hoje) c
     where not c.eh_dono and c.meios_esperados > 0
     group by c.payee_id, c.pessoa
  ), t as (
    select g.*, g.pessoa || ' (' || regexp_replace(public._agenda_dias_semana_texto(g.dias), '^de ', '') || ')' as item,
           case when 'dono' = any (g.origens) then 'dito' when g.origens = array['historico'] then 'hist' else 'outro' end as grupo
      from g
  )
  select array_agg(t.item order by cardinality(t.dias) desc, t.pessoa, t.payee_id) filter (where t.grupo = 'hist'),
         array_agg(t.item order by cardinality(t.dias) desc, t.pessoa, t.payee_id) filter (where t.grupo = 'dito'),
         array_agg(t.item order by cardinality(t.dias) desc, t.pessoa, t.payee_id) filter (where t.grupo = 'outro')
    into v_hist, v_dito, v_outro
    from t;
  v_semente := coalesce(cardinality(v_hist), 0) > 0 and coalesce(cardinality(v_dito), 0) = 0
               and coalesce(cardinality(v_outro), 0) = 0;

  -- (7a correção, achado 4) quem só tem a diária cadastrada não entra na chamada: work_profiles é do PAGAMENTO, não da
  -- agenda (a correção de 30/10), e o dono já disse quem saiu (o Mickael, toda quinta, "não vem desde 18/09"). Quem é da equipe
  -- é quem está na grade (agenda_capacidade); a chamada só nasce quando a semana seria montada só com a semente do histórico.
  v_sumidos := null;

  if not v_semente and coalesce(cardinality(v_sumidos), 0) = 0 then
    return jsonb_build_object('criada', false, 'motivo', 'a equipe está dita', 'semana', v_seg);
  end if;

  if coalesce(cardinality(v_dito), 0) > 0 then
    v_partes := v_partes || (public._agenda_lista(v_dito, null) || ', como você disse');
  end if;
  if coalesce(cardinality(v_outro), 0) > 0 then
    v_partes := v_partes || public._agenda_lista(v_outro, null);
  end if;
  if coalesce(cardinality(v_hist), 0) > 0 then
    v_partes := v_partes || (public._agenda_lista(v_hist, null)
                             || case when cardinality(v_hist) = 1 then ', pelo que veio' else ', pelo que vieram' end
                             || format(' nas últimas %s semanas', cf.medicao_semanas));
  end if;
  v_txt := format('Para marcar a semana de %s ', to_char(v_seg, 'DD/MM'))
           || case when cardinality(v_partes) = 0 then 'não conto com ninguém da equipe.'
                   else 'eu conto com ' || array_to_string(v_partes, ', e com ') || '.' end
           || coalesce(' ' || array_to_string(v_sumidos, ' '), '')
           || ' Se a equipe mudou, me diga quem vem e em que dias.';
  v_id := public._agenda_gestor_perguntar('equipe_cadastro', v_chave, null, v_txt, '[]'::jsonb, null, null, null, v_modo, p_agora);
  return jsonb_build_object('criada', v_id is not null, 'pergunta_id', v_id, 'semana', v_seg, 'semente', v_semente,
                            'sumidos', coalesce(cardinality(v_sumidos), 0), 'modo', v_modo, 'texto', v_txt);
end;
$function$;

comment on function public._agenda_gestor_equipe(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P4; AG7-03): a chamada semanal da equipe — no dia_do_plano, a pergunta equipe_cadastro (chave equipe_cadastro:chamada:<segunda da semana que a próxima publicação monta>, sem prazo nem opções, pelo modo do gestor que marca; desligado = nada) quando essa semana seria montada só com a semente do histórico (agenda_capacidade: todo meio-dia esperado de origem historico) ou há alguém com a diária cadastrada vigente que nunca esteve na agenda e não tem diária há 30 dias. O texto: "Para marcar a semana de 09/11 eu conto com Roberto (seg a sex) e João (ter a sex), pelo que vieram nas últimas 8 semanas. Mickael tem cadastro de diarista mas não vem desde 18/09: não conto com ele. Se a equipe mudou, me diga quem vem e em que dias." (com a equipe declarada pelo dono: "Alex (seg a sex), como você disse"). {criada, pergunta_id, semana, semente, sumidos, modo, texto}. Invoker, sem grant. O 7b recria ESTA função ({pulado} com o modo_cadastro dele). CORREÇÃO DA 7a (revisão da etapa; achado 4): a chamada não fala mais de quem só tem a diária cadastrada (work_profiles é do pagamento, não da agenda — a correção de 30/10): o "Mickael tem cadastro de diarista mas não vem desde 18/09" sai, e a pergunta só nasce quando a semana seria montada só com a semente do histórico. FASE 7b (P3; R2, §5.2): com modo_cadastro fora de desligado, {pulado: modo_cadastro} — a chamada da equipe é a da 7b (agenda_equipe_semana, com o telefone dentro e as opções): uma pergunta só ao dono. Desligado, a de antes, byte a byte.';

-- ── 3. Portas ────────────────────────────────────────────────────────────────────────────────────────────────────
-- As novas de leitura e de texto: invoker; nunca anon nem authenticated; service_role (os passos e a resposta da equipe as chamam
-- como dono das funções). O motivo da pergunta do dono: sem grant a ninguém (só a rodada, definer, a chama).
revoke all on function
  public._agenda_ler_dias_da_equipe(text), public._agenda_equipe_previstas_hoje(uuid, date, timestamptz),
  public._agenda_equipe_texto_dias(uuid, date)
  from public, anon, authenticated;
grant execute on function
  public._agenda_ler_dias_da_equipe(text), public._agenda_equipe_previstas_hoje(uuid, date, timestamptz),
  public._agenda_equipe_texto_dias(uuid, date)
  to service_role;
revoke all on function public._agenda_dias_semana_motivos(date, date) from public, anon, authenticated, service_role;
-- A rodada fala com a equipe e grava: definer, só o service_role (o task-automations).
revoke all on function public.agenda_equipe_semana(date, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_equipe_semana(date, timestamptz) to service_role;
-- (P2, a nota "uma leitura invoker do painel que as use precisa do grant na migration dela") o foco equipe (_agenda_ver_equipe:
-- invoker, authenticated e service_role) lê agora a semana perguntada, os dias declarados, os dias em texto e a chance de falta: as
-- quatro ganham authenticated (a RLS de quem lê vale; nunca anon).
grant execute on function
  public._agenda_dias_curtos(smallint[], boolean), public._agenda_semana_perguntada(date),
  public._agenda_dias_declarados(uuid, date), public._agenda_chance_de_falta(uuid, date)
  to authenticated;

-- As recriadas mantêm as portas delas (create or replace não muda a ACL; repetidas aqui para a migration se bastar).
revoke all on function
  public._agenda_equipe_registrar(uuid, date, text, text, timestamptz, date, text),
  public._agenda_rotina_sem_resposta(date, timestamptz),
  public._agenda_gestor_equipe(date, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function
  public.agenda_resposta_da_equipe(text, text, text, timestamptz),
  public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz),
  public.agenda_desfazer(uuid, uuid, text, date, timestamptz)
  from public, anon, authenticated;
grant execute on function
  public.agenda_resposta_da_equipe(text, text, text, timestamptz),
  public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz),
  public.agenda_desfazer(uuid, uuid, text, date, timestamptz)
  to service_role;
revoke all on function public._agenda_ver_equipe(date), public._agenda_linhas_do_fechamento(date) from public, anon;
grant execute on function public._agenda_ver_equipe(date), public._agenda_linhas_do_fechamento(date) to authenticated, service_role;
