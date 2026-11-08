
-- Agenda de Produção, Fase 7, etapa 7f ("Falar só o que importa"), pacote P9 (o final): a semana que mudou (M12 "mudou") e a saúde da comunicação com a
-- equipe e o cliente.
-- Spec: scratchpad agenda-pesquisa/spec-fase7f.md (§5.6, §6.3, §6.5, §11 aceites 6 e 7, e o bloco R8, que vale sobre o corpo: R8.3-2, R8.5-20 a 25, R8.6, R8.8,
-- R8.12, R8.13, R8.14); nomes: fase7-registro.md; notas: notas-fase7f.md, seções P5, P6, "Conferência do P6" (a decisão do fio sobre o achado 135) e P9.
-- Respostas do dono que valem aqui (respostas/<id> da página Respostas do Diário, conferidas em 08/11): ag7-texto-semana (AG7-36) "Aprovo o texto" — o cartão
-- mostrou 3 textos, e o 3º é o "Se mudar": "Nelson, o serviço no seu veleiro precisou passar para a semana de 23/11. Desculpe pela mudança. O dia certo eu confirmo
-- na véspera. Se algum dia dessa semana não der, me diga." (literal aqui, só trocando o nome, o serviço e a semana); ag7-cliente-data (AG7-16) "Concordo: semana
-- prevista até ficar seguro"; ag7-ligar "Ligar direto quando estiver pronto" (publicar em teste pelo OK permanente, cada *ligar* pelo OK nomeado).
-- Depende das Fases 1 a 6, do lote de 30/10, das etapas 7a a 7d, de 20261109100000 a 20261109100300, 20261109100600, do dado 20261109100900, do P5
-- (20261109101000) e do P6 (20261109101100) da 7f (nasce depois deles: R8.2). NÃO depende da 7e.
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (1 nova; 5 recriadas; nenhum dado, nenhuma tabela, nenhuma coluna, nenhuma lista fechada)
-- NÃO APLICADA. Existe para revisão e espera o OK. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7f/p9/montar-migration.mjs: cada recriada é o corpo da
-- definição MAIS NOVA do grep (conferida a cada montagem), e a mudança está só nos blocos "-- FASE 7f: (7f P9 … -- FASE 7f: fim". Tirados os blocos, o corpo é o da
-- origem, byte a byte (o montador e o K9 de supabase/tests/agenda_fase7f_final.sql conferem). As origens e o md5 do corpo de antes (prosrc, sem CR):
--   _agenda_cliente_texto         20261109101100_agenda_fase7f_cliente.sql:279  492249a6704bf222f7489647fc3150d3
--   _agenda_cliente_registrar     20261109101100_agenda_fase7f_cliente.sql:685  e010a19e9dc27a594446793742c9e853
--   _agenda_cliente_revalidar     20261109101100_agenda_fase7f_cliente.sql:938  c4033b6b3fce8baf63182962ad94bb2b
--   _agenda_cliente_atraso        20261028100800_agenda_fase5_correcao_rodada.sql:2021  5b0ffa73b23994821534dba3c172381a
--   _agenda_saude_comunicacao     20261109100600_agenda_fase7f_leituras.sql:393  cdaf787853237abfc460924d9df8a520
-- As 3 primeiras vêm do P6 (20261109101100, não publicado com este arquivo ainda): o md5 de PRODUÇÃO de hoje delas é o "antes" do P6 (sql/wf7f9_md5_antes, dom
-- 08/11); o de _agenda_cliente_atraso (5b0ffa73…) e o de _agenda_saude_comunicacao (cdaf7878…) são os de produção.
--
-- POR QUE: o dono aprovou o texto "Se mudar" (AG7-36) e decidiu "semana prevista até ficar seguro" (AG7-16). Sem esta migration, o cliente que ouviu a semana
-- prevista e cujo serviço saiu dela receberia o aviso de hoje (o M6 "remarcado"), com o dia novo exato — o contrário do que o dono decidiu. E a saúde da
-- comunicação (P7) não contava a equipe e o cliente (aceites 6 e 7 da §11): os pacotes P5 e P6 não existiam.
--
-- O QUE MUDA (só com modo_cliente_camadas fora de desligado; ele respeita o freio por _agenda_fala_modo('camadas'): com *gestor, só propor*, o ligado vale teste):
--   1. _agenda_cliente_semana_mudou (nova): a OS cujo cliente OUVIU a semana prevista (o prometido de agora veio de uma mensagem semana que saiu, faixa ou
--      condicional) e cujo plano saiu da semana dita (o risco "remarcado" de _agenda_cliente_risco), ainda em camada (_agenda_cliente_camada: marcada pela
--      estimativa, a semana nova inteira — duas semanas não), recebe a mensagem semana variante mudou, com a semana nova (chave mudou:<a segunda da semana nova>).
--      Com as camadas em teste (ou ligadas com o freio), ela só se registra (":sombra"; a ação nasce contada, como a semana do P6) e nada mais muda.
--   2. _agenda_cliente_atraso (recriada): onde nasceria o M6 "remarcado", com as camadas ligadas de verdade, nasce a semana que mudou no lugar dele (o M6 não sai);
--      em teste, o M6 de hoje sai como sempre e a semana que mudou só se registra. A semana que mudou ainda não enviada sai do caminho quando o plano volta à semana
--      dita ou vai para outra. As contagens ganham semana_mudou* só quando houve (sem ela, a chave não existe).
--   3. _agenda_cliente_texto (recriada): o texto do "Se mudar", literal (só o nome, o serviço e a semana).
--   4. _agenda_cliente_registrar (recriada): a semana que mudou nasce SEMPRE pedida (o *manda cliente* do dono; §5.6 item 3), mesmo com o tipo semana liberado pela
--      d11 e mesmo com motivo crítico, com a pergunta cliente_aprovar "Vou mudar o que Nelson ouviu: era a semana de 16/11, fica a semana de 23/11. Mensagem pronta,
--      sai amanhã às 09:00: "…". *manda cliente Nelson* ou *segura cliente Nelson*.". A semana nova só vira o prometido quando a mensagem sai (o gatilho do envio).
--   5. _agenda_cliente_revalidar (recriada): a semana que mudou tem regra própria, além da da semana do P6 (o 1º ou o último dia do plano fora da semana nova =
--      desatualizada): o prometido mudou desde que ela nasceu (outra mensagem saiu, o dono mandou outra data) = desatualizada.
--   6. _agenda_saude_comunicacao (recriada): os zeros da equipe (equipe_fora_da_janela, equipe_acima_do_teto, ficha_sem_sim, mudanca_19h_repetida) e do cliente
--      (dia_exato_cedo, promessa_mudou_sem_dono, semana_como_dia_ouvido), que entram no zeros_ok e no ok de agenda_saude; 0 hoje em produção (sql/wf7f9_zeros, dom
--      08/11); e os números (numeros.equipe com o previsto ou o convite fora de desligado; numeros.cliente com as camadas fora de desligado).
--
-- O QUE NÃO MUDA: com modo_cliente_camadas desligado (como está em produção e como esta migration deixa) as 11 mensagens ao cliente de hoje saem como antes, byte a
-- byte (o passo do atraso nem chama a função nova: o cf que ele já leu); em teste, o M6 sai como hoje. A semana que mudou não muda a véspera, o M1, o M3/M7 dentro
-- da semana (do P6) nem a resposta (SIM = ciência; o resto ao dono, como a semana). Nenhum texto novo à equipe; ao dono, só a pergunta da semana que mudou, que só
-- nasce com as camadas ligadas de verdade. _agenda_cliente_risco, _agenda_cliente_ouviu, _agenda_cliente_prometer, agenda_saude e as demais não são recriadas.
--
-- ORDEM DE LIGAR (spec R8.14): depois de 20261109101100 (o P6). Aplicar sozinha não muda nada para ninguém. O dado que põe previsto, convite e camadas em teste é
-- a 20261109101900; o roteiro é fila-do-dono/fase77f-publicar-final.md.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7f_final.sql (begin/rollback) e supabase/tests/agenda_fase7f_pos_deploy_final.sql. Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261109101200
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK): PONTA=<a ponta> bash publicar/exec/aplicar.sh 20261109101200_agenda_fase7f_mudou
--
-- DESFAZER: com modo_cliente_camadas desligado nada disto roda. Para voltar o código: publicar/exec/volta-funcoes-7f-final.sql (as recriadas voltam ao corpo de
-- produção de antes e as novas saem), ou reaplicar as definições das origens acima e
--   drop function if exists public._agenda_cliente_semana_mudou(uuid, jsonb, date, timestamptz, timestamptz, timestamptz);
-- Mensagem que já saiu ao cliente não volta.
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.

-- ── 1. A semana que mudou ───────────────────────────────────────────────────────────────────────────
-- §5.6 ("com prometido em faixa e a faixa nova diferente → variante mudou com p_critica null"), §6.5, AG7-36, NOVO-agenda-135. Quem chama é o passo do atraso
-- (_agenda_cliente_atraso), no lugar onde nasceria o M6 remarcado: a mesma hora (v_alvo), a mesma validade (v_lim) e a mesma espera do fechamento.
create or replace function public._agenda_cliente_semana_mudou(p_os uuid, p_risco jsonb, p_hoje date, p_agora timestamptz, p_alvo timestamptz,
                                                               p_valida timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  p        public.os_planejamento%rowtype;
  m        record;
  v_status text;
  c        jsonb;
  v_seg    date;
  v_compra boolean;
  v_r      jsonb;
  n_m6     int := 0;
begin
  if p_os is null or p_hoje is null or p_agora is null or p_alvo is null then
    raise exception '_agenda_cliente_semana_mudou: sem a OS, o dia, a hora ou o alvo.' using errcode = '22004';
  end if;
  -- desligadas: nada se lê (o passo do atraso nem chama esta função; aqui por garantia)
  if cf.modo_cliente_camadas = 'desligado' then
    return jsonb_build_object('aplica', false, 'motivo', 'desligado');
  end if;
  -- só onde nasceria o M6 remarcado: o plano publicado andou para depois do que o cliente ouviu (a peça e a execução seguem o M6 de hoje)
  if p_risco is null or not coalesce((p_risco ->> 'risco')::boolean, false) or p_risco ->> 'variante' is distinct from 'remarcado' then
    return jsonb_build_object('aplica', false, 'motivo', 'sem_risco');
  end if;
  -- o cliente ouviu a semana: o prometido de agora veio de uma mensagem semana que SAIU (faixa ou condicional). Sem ela, o M6 de hoje
  select * into p from public.os_planejamento x where x.service_order_id = p_os;
  if not found or p.prometido_tipo is null or p.prometido_tipo not in ('faixa', 'condicional')
     or not exists (select 1 from public.agenda_cliente_mensagens s
                     where s.id = p.prometido_mensagem_id and s.tipo = 'semana' and s.enviada_em is not null) then
    return jsonb_build_object('aplica', false, 'motivo', 'sem_semana_dita');
  end if;
  -- o filtro da semana do P6 (R8.5-21): a OS começada, esperando peça ou cliente, o orçamento e a encerrada seguem o caminho de hoje
  select so.status into v_status from public.service_orders so where so.id = p_os;
  if v_status is null or v_status not in ('open', 'approved', 'scheduled') then
    return jsonb_build_object('aplica', false, 'motivo', 'status');
  end if;
  -- ainda em camada, com a semana nova inteira (duas semanas e sem fim: o M6 de hoje, R8.3-2); a OS que deixou de ser marcada pela estimativa (o dono deu os dias)
  -- também: o dia já é seguro
  c := public._agenda_cliente_camada(p_os, p_hoje);
  if c ->> 'camada' is distinct from 'semana' or c ->> 'motivo' is not null then
    return jsonb_build_object('aplica', false, 'motivo', coalesce(c ->> 'motivo', c ->> 'camada', 'fora_da_camada'));
  end if;
  v_seg := (c ->> 'semana')::date;
  -- o plano ainda na semana que ele ouviu (o fim passou do último dia útil dela, num sábado marcado): não é outra semana, e o M6 diz o fim
  if v_seg = date_trunc('week', coalesce(p.prometido_de, p.prometido_ate))::date then
    return jsonb_build_object('aplica', false, 'motivo', 'mesma_semana');
  end if;
  v_compra := coalesce(public.os_prontidao(p_os, p_hoje) #>> '{material,estado}' = 'completo', false);
  v_r := public._agenda_cliente_registrar('semana', 'mudou', p_os, (c ->> 'faixa_de')::date,
           jsonb_build_object('dia', c -> 'faixa_de', 'faixa_de', c -> 'faixa_de', 'faixa_ate', c -> 'faixa_ate', 'n', c -> 'n_dias',
                              'dito_de', p.prometido_de, 'dito_ate', p.prometido_ate, 'dito_msg', p.prometido_mensagem_id,
                              'chave', 'mudou:' || v_seg::text,
                              'prometido_tipo', case when v_compra then 'faixa' else 'condicional' end),
           p_alvo, p_valida, 'rodada', null, p_agora);
  -- em teste (molde da semana do P6 e do M11): a ação nasce contada — fica no foco, e não ocupa linha do fechamento nem do aviso
  if coalesce((v_r ->> 'criada')::boolean, false) and v_r ->> 'modo' = 'sombra' then
    update public.agenda_acoes a set contada_em = p_agora
     where a.id = (select x.acao_id from public.agenda_cliente_mensagens x where x.id = (v_r ->> 'id')::uuid);
  end if;
  -- de verdade: o M6 vivo dela (registrado antes de as camadas ligarem) sai do caminho, porque a semana que mudou vai no lugar dele
  if v_r ->> 'modo' = 'ligado' and (coalesce((v_r ->> 'criada')::boolean, false) or v_r ->> 'motivo' = 'ja_existe') then
    for m in
      select a.id from public.agenda_cliente_mensagens a
       where a.service_order_id = p_os and a.tipo = 'pode_atrasar' and a.estado in ('registrada', 'aguardando_dono', 'enfileirada')
       order by a.criada_em, a.id
    loop
      if public._agenda_cliente_cancelar(m.id, 'desatualizada', 'a semana que mudou vai no lugar do aviso de atraso') then
        n_m6 := n_m6 + 1;
      end if;
    end loop;
  end if;
  return jsonb_build_object('aplica', true, 'modo', v_r ->> 'modo', 'criada', coalesce((v_r ->> 'criada')::boolean, false), 'motivo', v_r ->> 'motivo',
                            'id', v_r ->> 'id', 'semana', v_seg, 'm6_cancelados', n_m6);
end;
$function$;
comment on function public._agenda_cliente_semana_mudou(uuid, jsonb, date, timestamptz, timestamptz, timestamptz) is
  'Agenda de Produção (Fase 7f, P9; §5.6, §6.5, AG7-36 "Se mudar", AG7-16, NOVO-agenda-135): a semana que mudou. Chamada pelo passo do atraso onde nasceria o M6 remarcado (p_risco = _agenda_cliente_risco, com a hora e a validade dele). {aplica: false, motivo} quando não é o caso — desligado (as camadas; nada lido), sem_risco (sem risco, ou a peça e a execução), sem_semana_dita (o prometido de agora não veio de uma mensagem semana que saiu), status (fora de open, approved e scheduled), normal/desligado/sem_plano/nao_e_estimativa/sem_fim/duas_semanas (_agenda_cliente_camada), mesma_semana; senão registra a semana variante mudou (a semana nova pelo calendário, chave mudou:<segunda>, dito_de/dito_ate/dito_msg = o que o cliente ouviu, prometido_tipo faixa com a compra feita, senão condicional) e devolve {aplica: true, modo, criada, motivo, id, semana, m6_cancelados}. Em teste a ação nasce contada; de verdade (ligado), o M6 vivo da OS sai do caminho (desatualizada). Volatile, invoker, sem grant.';

-- ── 2. O passo do atraso ────────────────────────────────────────────────────────────────────────────
create or replace function public._agenda_cliente_atraso(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_modo  text := case when cf.modo_cliente = 'ligado' then 'ligado' else 'sombra' end;
  v_local timestamp := p_agora at time zone 'America/Sao_Paulo';
  r       record;
  m       record;
  x       jsonb;
  v_urg   boolean;
  v_alvo  timestamptz;
  v_lim   timestamptz;
  v_crit  text;
  v_dados jsonb;
  v_r     jsonb;
  v_chave text;
  v_perg  uuid;
  v_ctx   jsonb;
  n_reg   int := 0;
  n_crit  int := 0;
  n_pass  int := 0;
  n_esp   int := 0;
  n_semd  int := 0;
  n_canc  int := 0;
  -- CORREÇÃO FASE 5: (item 3b) o aviso que não saiu; (item 4) as OS puladas por erro
  c_validade constant interval := interval '7 days';   -- spec §3.2: a cliente_resposta some em 7 dias
  n_nao_saiu int := 0;
  n_erro  int := 0;
  -- CORREÇÃO FASE 5: fim
  -- FASE 7f: (7f P9) a semana que mudou: o que a função nova devolveu e as contagens (só aparecem quando houve)
  v_7f        jsonb;
  n_7f_lig    int := 0;
  n_7f_teste  int := 0;
  n_7f_canc   int := 0;
  -- FASE 7f: fim
begin
  for r in
    select k.service_order_id as os, p.prometido_ate
      from public.os_carteira(p_hoje) k
      join public.os_planejamento p on p.service_order_id = k.service_order_id
     where p.prometido_ate is not null
     order by k.numero collate "C", k.service_order_id
  loop
    -- CORREÇÃO FASE 5: (item 4) cada OS no seu bloco: o erro de uma (o texto que não fecha, o proibido) vai a
    -- app_error_logs (agenda / cliente:atraso:os) e o passo segue para as outras
    begin
    -- CORREÇÃO FASE 5: fim
    x := public._agenda_cliente_risco(r.os, p_hoje);
    -- o aviso vivo que não é mais o de agora sai do caminho
    for m in
      select a.id, a.dia_alvo from public.agenda_cliente_mensagens a
       where a.service_order_id = r.os and a.tipo = 'pode_atrasar' and a.estado in ('registrada', 'aguardando_dono', 'enfileirada')
    loop
      if x is null or not coalesce((x ->> 'risco')::boolean, false) or coalesce((x ->> 'passou')::boolean, false)
         or m.dia_alvo is distinct from (x ->> 'faixa_de')::date then
        if public._agenda_cliente_cancelar(m.id, 'desatualizada', 'o risco de atraso mudou antes de a mensagem sair') then
          n_canc := n_canc + 1;
        end if;
      end if;
    end loop;
    -- FASE 7f: (7f P9, §5.6; molde do M6 vivo logo acima) a semana que mudou, ainda não enviada, que não é mais a de agora sai do caminho: o risco sumiu (o plano
    -- voltou à semana dita), não é mais o remarcado, ou o plano foi para outra semana. Com as camadas desligadas nada se lê (o cf que o passo já leu); a que
    -- ficou na fila, a revalidação recusa (tipo_em_teste)
    if cf.modo_cliente_camadas <> 'desligado' then
      for m in
        select a.id, a.faixa_de from public.agenda_cliente_mensagens a
         where a.service_order_id = r.os and a.tipo = 'semana' and a.variante = 'mudou' and a.estado in ('registrada', 'aguardando_dono', 'enfileirada')
      loop
        if x is null or not coalesce((x ->> 'risco')::boolean, false) or x ->> 'variante' is distinct from 'remarcado'
           or date_trunc('week', m.faixa_de) is distinct from date_trunc('week', (x ->> 'faixa_de')::date) then
          if public._agenda_cliente_cancelar(m.id, 'desatualizada', 'a semana mudou de novo antes de a mensagem sair') then
            n_7f_canc := n_7f_canc + 1;
          end if;
        end if;
      end loop;
    end if;
    -- FASE 7f: fim
    continue when x is null or not coalesce((x ->> 'risco')::boolean, false);
    -- CORREÇÃO FASE 5: (item 3b) o aviso de atraso de agora que NÃO saiu — recusado pelo canal (sem conversa, sem telefone,
    -- opt-out, o teto, o horário, vencido, o texto) ou pelo provedor (entrega) — com a data dita ainda por vir: o dono fica
    -- sabendo para ligar (uma vez por mensagem: a mesma pergunta do "não saiu" da correção C1, que cobre a aprovada pelo
    -- dono); com a data em até 1 dia útil, o acorde. A segurada (o dono decidiu) e a desatualizada (o risco mudou) não.
    if not coalesce((x ->> 'passou')::boolean, false) and r.prometido_ate >= p_hoje then
      for m in
        select a.id, a.recusa_motivo from public.agenda_cliente_mensagens a
         where a.service_order_id = r.os and a.tipo = 'pode_atrasar' and a.modo = 'ligado' and a.estado = 'recusada'
           and a.dia_alvo is not distinct from (x ->> 'faixa_de')::date
           and a.recusa_motivo in ('sem_conversa', 'sem_telefone', 'opt_out', 'teto_dia', 'teto_semana', 'teto_total',
                                   'janela', 'domingo', 'feriado', 'vencida', 'intervalo', 'texto', 'entrega')
           and not exists (select 1 from public.agenda_perguntas q where q.chave = 'cliente_resposta:nao_saiu:' || a.id)
         order by a.criada_em, a.id
      loop
        v_ctx := public._agenda_cliente_contexto(r.os, p_hoje);
        v_perg := public._agenda_cliente_perguntar('cliente_resposta', 'cliente_resposta:nao_saiu:' || m.id, r.os,
                    r.prometido_ate, r.prometido_ate,
                    format('Não consegui avisar %s do atraso (%s): recomendo você ligar hoje.', coalesce(v_ctx ->> 'nome', 'o cliente'),
                           public._agenda_cliente_motivo_texto(m.recusa_motivo)),
                    'ligado', p_agora, p_agora + c_validade);
        n_nao_saiu := n_nao_saiu + 1;
        if r.prometido_ate <= public.agenda_somar_du(p_hoje, 1) then
          perform public._agenda_cliente_acorde(r.os, 'cliente_resposta:nao_saiu:' || m.id,
            format('Não consegui avisar %s do atraso (%s): recomendo você ligar hoje.', coalesce(v_ctx ->> 'nome', 'o cliente'),
                   public._agenda_cliente_motivo_texto(m.recusa_motivo)),
            r.prometido_ate, p_hoje, v_perg);
        end if;
      end loop;
    end if;
    -- CORREÇÃO FASE 5: fim
    v_lim := public._agenda_cliente_ultimo_fim(r.prometido_ate);
    v_urg := public.agenda_du_entre(p_hoje, r.prometido_ate) <= cf.cliente_atraso_na_hora_du;
    v_alvo := case when v_urg then p_agora else public._agenda_cliente_toque(public._agenda_cliente_dia_seguinte(p_hoje)) end;
    -- a data dita já passou, ou o aviso só sairia depois dela: não sai; o dono liga (pergunta crítica, uma vez)
    if coalesce((x ->> 'passou')::boolean, false) or v_lim is null
       or public._agenda_cliente_quando(0, v_alvo, p_agora) > v_lim then
      v_chave := format('cliente_aviso:%s:%s', r.os, r.prometido_ate);
      if not exists (select 1 from public.agenda_perguntas q where q.chave = v_chave and q.modo = v_modo) then
        v_perg := public._agenda_cliente_perguntar('cliente_aviso', v_chave, r.os, r.prometido_ate, p_hoje,
                    public._agenda_cliente_texto_do_aviso('passou', 'pode_atrasar', r.os, x, p_hoje), v_modo, p_agora,
                    public._agenda_cliente_fim_da_janela(p_hoje, 1));
        n_pass := n_pass + 1;
        if v_modo = 'ligado' then
          v_ctx := public._agenda_cliente_contexto(r.os, p_hoje);
          perform public._agenda_cliente_acorde(r.os, v_chave,
            format('A data que o %s ouviu (%s) passou sem aviso: recomendo você ligar hoje. A decisão está nas perguntas da agenda (1, 2 ou 3).',
                   coalesce(v_ctx ->> 'nome', 'cliente'), public._dia_curto(r.prometido_ate)),
            p_hoje, p_hoje, v_perg);
        end if;
      end if;
      continue;
    end if;
    if coalesce((x ->> 'sem_data')::boolean, false) then
      -- sem nenhuma previsão da peça não há o que dizer (a vigia já pede a previsão ao dono)
      n_semd := n_semd + 1;
      continue;
    end if;
    -- sem urgência, espera o fechamento do dia (o 1º tique a partir de cliente_hora_preparo)
    if not v_urg and v_local::time < cf.cliente_hora_preparo then
      n_esp := n_esp + 1;
      continue;
    end if;
    -- FASE 7f: (7f P9, §5.6, §6.5; AG7-36 o "Se mudar" aprovado; AG7-16 "semana prevista até ficar seguro"; NOVO-agenda-135) o cliente que OUVIU a semana prevista
    -- e cujo plano saiu dela: no lugar do M6 remarcado (o dia novo exato), a semana que mudou, na mesma hora e com a mesma validade, sempre pedida ao dono. Só com
    -- as camadas ligadas de verdade (pelo freio) ela vai no lugar e o M6 não nasce; em teste, o M6 de hoje sai como sempre e a semana que mudou só se registra
    -- (":sombra"). Desligadas: nem chamada (o cf que o passo já leu). Quem não ouviu a semana, a peça, a execução, as duas semanas: o M6 de hoje
    if cf.modo_cliente_camadas <> 'desligado' and x ->> 'variante' = 'remarcado' then
      v_7f := public._agenda_cliente_semana_mudou(r.os, x, p_hoje, p_agora, v_alvo, v_lim);
      if coalesce((v_7f ->> 'aplica')::boolean, false) then
        if v_7f ->> 'modo' = 'ligado' then
          n_7f_lig := n_7f_lig + case when coalesce((v_7f ->> 'criada')::boolean, false) then 1 else 0 end;
          continue;
        end if;
        n_7f_teste := n_7f_teste + case when coalesce((v_7f ->> 'criada')::boolean, false) then 1 else 0 end;
      end if;
    end if;
    -- FASE 7f: fim
    v_crit := case when coalesce((x ->> 'segundo')::boolean, false) then 'segundo_atraso'
                   when (x ->> 'atraso_du')::int >= cf.atraso_longo_dias then 'atraso_longo' end;
    v_dados := jsonb_build_object('faixa_de', x -> 'faixa_de', 'faixa_ate', x -> 'faixa_ate', 'prometido_tipo', x -> 'tipo',
                                  'dito_de', x -> 'dito_de', 'dito_ate', x -> 'dito_ate', 'atraso_dias', x -> 'atraso_dias')
               || case when x ->> 'variante' = 'peca' then jsonb_build_object('peca_de', x -> 'peca', 'peca_ate', x -> 'peca')
                       else '{}'::jsonb end;
    -- CORREÇÃO FASE 5: (item 6) a forma fim leva o dia e o fim novos (a revalidação compara o último dia com o fim)
    if x ->> 'forma' = 'fim' then
      v_dados := v_dados || jsonb_build_object('forma', 'fim', 'dia', x -> 'faixa_de', 'fim', x -> 'faixa_ate');
    end if;
    -- CORREÇÃO FASE 5: fim
    v_r := public._agenda_cliente_registrar('pode_atrasar', x ->> 'variante', r.os, (x ->> 'faixa_de')::date, v_dados,
             v_alvo, v_lim, 'rodada', v_crit, p_agora);
    if coalesce((v_r ->> 'criada')::boolean, false) then
      n_reg := n_reg + 1;
      if v_r ->> 'aprovacao' = 'critica' then
        n_crit := n_crit + 1;
        -- a crítica que perde em até 1 dia útil acorda o dono
        if v_r ->> 'modo' = 'ligado' and r.prometido_ate <= public.agenda_somar_du(p_hoje, 1) then
          v_ctx := public._agenda_cliente_contexto(r.os, p_hoje);
          perform public._agenda_cliente_acorde(r.os, 'cliente_aviso:' || (v_r ->> 'id'),
            format('O aviso de atraso do %s precisa de você hoje (%s → %s): recomendo ligar. A decisão está nas perguntas da agenda (1, 2 ou 3).',
                   coalesce(v_ctx ->> 'nome', 'cliente'), public._dia_curto(r.prometido_ate),
                   public._agenda_faixa_texto((x ->> 'faixa_de')::date, 'manha', (x ->> 'faixa_ate')::date, 'tarde')),
            r.prometido_ate, p_hoje, (v_r ->> 'pergunta_id')::uuid);
        end if;
      end if;
    end if;
    -- CORREÇÃO FASE 5: (item 4) o erro desta OS: registrado e pulado
    exception when others then
      perform public._agenda_cliente_erro_da_os('atraso', r.os, sqlstate, sqlerrm, p_hoje);
      n_erro := n_erro + 1;
    end;
    -- CORREÇÃO FASE 5: fim
  end loop;
  -- FASE 7f: (7f P9) a semana que mudou nas contagens só quando houve (sem ela, a chave não existe: o de antes, byte a byte)
  if n_7f_lig + n_7f_teste + n_7f_canc > 0 then
    return jsonb_build_object('registradas', n_reg, 'criticas', n_crit, 'passou', n_pass, 'esperando_fechamento', n_esp,
                              'sem_data', n_semd, 'desatualizadas', n_canc, 'nao_saiu', n_nao_saiu, 'erros_os', n_erro,
                              'semana_mudou', n_7f_lig, 'semana_mudou_teste', n_7f_teste, 'semana_mudou_desatualizadas', n_7f_canc);
  end if;
  -- FASE 7f: fim
  -- CORREÇÃO FASE 5: (itens 3b e 4) o aviso que não saiu e as OS puladas por erro nas contagens
  return jsonb_build_object('registradas', n_reg, 'criticas', n_crit, 'passou', n_pass, 'esperando_fechamento', n_esp,
                            'sem_data', n_semd, 'desatualizadas', n_canc, 'nao_saiu', n_nao_saiu, 'erros_os', n_erro);
  -- CORREÇÃO FASE 5: fim
  return jsonb_build_object('registradas', n_reg, 'criticas', n_crit, 'passou', n_pass, 'esperando_fechamento', n_esp,
                            'sem_data', n_semd, 'desatualizadas', n_canc);
end;
$function$;
comment on function public._agenda_cliente_atraso(date, timestamptz) is
  'Agenda de Produção (Fase 5, P3): o passo atraso da rodada do cliente — a data que o cliente ouviu e que não vai se cumprir (_agenda_cliente_risco): o aviso (M6) no 1º tique a partir de cliente_hora_preparo, ou na hora com o prometido a até cliente_atraso_na_hora_du dias úteis; nunca depois da data (cliente_aviso passou); o 2º atraso e o atraso longo = pergunta crítica; o aviso vivo que não bate mais com o risco sai do caminho. CORREÇÃO FASE 5 (C2): (item 3b) o M6 de agora recusado pelo canal ou pelo provedor, com a data ainda por vir, abre uma vez cliente_resposta:nao_saiu:<mensagem> ("Não consegui avisar Nelson do atraso (<motivo>): recomendo você ligar hoje."), com o acorde se a data é em até 1 dia útil (nao_saiu); (item 6) a forma fim; (item 8) a variante peca_sem_data vem do risco; (item 4) o erro de uma OS vai a app_error_logs (agenda / cliente:atraso:os) e o passo segue (erros_os). Interna (sem grant). FASE 7f (P9): onde nasceria o M6 remarcado de quem OUVIU a semana prevista (o prometido veio de uma mensagem semana que saiu), com as camadas fora de desligado, chama _agenda_cliente_semana_mudou: com as camadas ligadas de verdade (pelo freio) a semana que mudou vai no lugar e o M6 não nasce; em teste o M6 de hoje sai e ela só se registra. A semana que mudou ainda não enviada que não bate mais com o risco sai do caminho (desatualizada). As contagens ganham semana_mudou, semana_mudou_teste e semana_mudou_desatualizadas só quando houve. Com as camadas desligadas, o de antes, byte a byte (nada novo é lido).';

-- ── 3. O texto ──────────────────────────────────────────────────────────────────────────────────────
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
  -- FASE 7f: (7f P9, §6.5; AG7-36 "Aprovo o texto": o "Se mudar" do cartão, literal, só trocando o nome, o serviço e a semana; NOVO-agenda-135) a semana que mudou:
  -- "Nelson, o serviço no seu veleiro precisou passar para a semana de 23/11. Desculpe pela mudança. O dia certo eu confirmo na véspera. Se algum dia dessa semana
  -- não der, me diga." A semana nova é a segunda da semana de faixa_de. Sem dia exato, sem data de pronto, sem valor, sem número de OS. O serviço no plural
  -- ("os serviços") diz "precisaram passar". A assinatura só na 1ª mensagem, como os outros tipos (aqui nunca: a semana já saiu antes)
  if p_tipo = 'semana' and v_var = 'mudou' then
    if v_nome is null then
      raise exception using errcode = '22023', message = 'Falta o nome do cliente para a mensagem semana ao cliente.';
    end if;
    if (d ->> 'faixa_de') is null then
      raise exception using errcode = '22023', message = 'Falta a semana nova para a mensagem semana ao cliente.';
    end if;
    v_resto := format('%s %s para a semana de %s. Desculpe pela mudança. O dia certo eu confirmo na véspera. Se algum dia dessa semana não der, me diga.',
                      v_serv, case when v_art in ('os', 'as') then 'precisaram passar' else 'precisou passar' end,
                      to_char(date_trunc('week', (d ->> 'faixa_de')::date), 'DD/MM'));
    if v_prim then
      return format('Olá, %s! %s %s', v_nome,
                    case when x ->> 'dono' is not null then format('Aqui é o %s, da %s.', x ->> 'dono', x ->> 'empresa')
                         else format('Aqui é da %s.', x ->> 'empresa') end,
                    upper(left(v_resto, 1)) || substr(v_resto, 2));
    end if;
    return v_nome || ', ' || v_resto;
  end if;
  -- FASE 7f: fim
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
  'Agenda de Produção (Fase 5): a mensagem-modelo ao cliente (spec §6.1), pronta, com os dados do banco — tipos confirmar (M1: primeira, seguinte, unico; nula = primeira ou seguinte pelo contexto), vespera (M2), acesso (M4), material_chegou (M3), pode_atrasar (M6: peca, execucao, remarcado), nova_data (M7), andamento (M5: primeiro_dia, semanal), pronto e pronto_lembrete (M8), pos_servico (M9) e mudanca_no_dia (M10: clima, equipe, geral). p_dados = o que o passo calculou (envio, primeira, dia, fim, janela, n, n_feitos, quando, faixa_de/ate, peca_de/ate, dito_de/ate ou dia_dito); o que faltar sai do contexto (_agenda_cliente_contexto). Assinatura só na 1ª mensagem. Lança 22023 com o tipo ou a variante que não existe e quando falta um dado; nunca devolve texto pela metade. CORREÇÃO FASE 5 (C2): (item 12) p_dados.saudacao ("Bom dia" | "Boa tarde"; padrão "Bom dia") abre a véspera, o acesso e o M10 de chuva; (item 6) p_dados.forma = fim no M6 remarcado com o mesmo início ("{nome}, {servico} vai precisar de mais um dia: agora fica de {dia} até {fim}. Desculpe pela mudança. Pode ser? Responda SIM ou me diga outro dia."); (item 8) M6 peca_sem_data, sem data ("{nome}, quero te avisar com antecedência: ainda faltam peças {d}o serviço sem data de chegada, então {servico}, que estava {dito}, vai atrasar. Te digo a nova data assim que elas chegarem. Se isso atrapalhar algum plano seu, me diga."). FASE 6 (P7, spec-fase6 §6.1): a forma fim diz quantos dias o fim andou ("{nome}, {servico} vai terminar um dia depois do previsto: agora fica de {dia} até {fim}. …"; n ≥ 2: "… vai terminar {n} dias depois do previsto: …"; n = agenda_du_entre(dito_ate, fim); n < 1 = 22023); a peça sem data sem a repetição ("{nome}, quero te avisar com antecedência: ainda faltam peças sem data de chegada, então {servico}, que estava {dito}, vai atrasar. …"). Os dois textos novos ao cliente esperam o OK do dono antes de ligar. FASE 7d (P6, §6.1, AG7-21): o M11 onde_fica, variantes barco e motorhome, com p_dados.uso e p_dados.prazo; abre com o nome (com a assinatura na 1ª mensagem); o dia não é exigido. Texto aprovado; qualquer palavra fora da §6.1 volta a pedir o OK do dono. FASE 7f (P6): o tipo semana (M12, a semana prevista; AG7-36): compra_feita ("… está previsto para a semana de 16/11 (segunda 16/11 a quinta 19/11), com uns 3 dias de trabalho. O dia certo eu confirmo na véspera. Se algum dia dessa semana não der, me diga.") e compra_pendente ("… para a semana de 16/11, se as peças chegarem a tempo, com uns 3 dias …"). Exige faixa_de e faixa_ate na mesma semana e n ≥ 1 (22023). Sem data de pronto (AG7-32), sem "duas semanas" (R8.3-2). FASE 7f (P9): a semana variante mudou (o "Se mudar" de AG7-36, literal: "Nelson, o serviço no seu veleiro precisou passar para a semana de 23/11. Desculpe pela mudança. O dia certo eu confirmo na véspera. Se algum dia dessa semana não der, me diga."; a semana é a segunda de faixa_de; no plural, "precisaram passar"). Sem o nome ou sem faixa_de = 22023.';

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
  -- FASE 7f: (7f P9, §5.6 item 3, §6.3; o pedido do fio: a mudança da promessa nasce SEMPRE pedida) a semana que mudou espera o *manda cliente* do dono,
  -- mesmo com o tipo semana liberado pela d11 e mesmo com um motivo crítico. A pergunta diz o que o cliente ouviu e o que passa a ouvir (o motivo não: a última ação
  -- que moveu a OS nem sempre diz por quê, e a pergunta não afirma o que não está no banco — R8.12-9; *o que mudou* mostra). A semana nova só vira o prometido
  -- quando a mensagem sai (o gatilho do envio, _agenda_cliente_prometer). Em teste (acima) ela é livre e não pergunta nada, como toda mensagem em teste
  elsif p_tipo = 'semana' and v_var = 'mudou' then
    if coalesce((p_dados ->> 'dito_de')::date, (x #>> '{prometido,de}')::date, (x #>> '{prometido,ate}')::date) is null or p_dia_alvo is null then
      raise exception 'A semana que mudou veio sem a semana que o cliente ouviu ou sem a nova.' using errcode = '22023';
    end if;
    v_aprov := 'pedida';
    v_estado := 'aguardando_dono';
    v_perg := public._agenda_cliente_perguntar('cliente_aprovar', 'cliente_aprovar:' || v_id, p_os, p_dia_alvo,
                (v_enviar at time zone 'America/Sao_Paulo')::date,
                format('Vou mudar o que %s ouviu: era a semana de %s, fica a semana de %s. Mensagem pronta, sai %s: "%s". *manda cliente %s* ou *segura cliente %s*.',
                       x ->> 'nome',
                       to_char(date_trunc('week', coalesce((p_dados ->> 'dito_de')::date, (x #>> '{prometido,de}')::date, (x #>> '{prometido,ate}')::date)), 'DD/MM'),
                       to_char(date_trunc('week', p_dia_alvo), 'DD/MM'), public._agenda_cliente_quando_texto(v_enviar, p_agora), v_txt,
                       x ->> 'nome', x ->> 'nome'),
                'ligado', p_agora, v_valida);
  -- FASE 7f: fim
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
  'Agenda de Produção (Fase 5, P2): grava a mensagem-modelo ao cliente e decide o envio — desligado = nada; o texto é o do banco (_agenda_cliente_texto, contado do dia do envio, com a assinatura só na 1ª mensagem; o proibido = 22023); o modo da linha: ligado só com modo_cliente ligado E o tipo em cliente_tipos_ligados, senão sombra (chave com :sombra, a ação "Em teste: eu teria mandado…"); a chave agenda-cliente:<tipo>:<os>:<p_dados.chave | dia_alvo | o dia do alvo> (uma só: a 2ª devolve ja_existe); enviar_em pelo _agenda_cliente_quando; valida_ate = p_valida_ate, senão o fim da janela do dia do envio (passou dela = recusada/vencida); a aprovação em ligado: p_critica (segundo_atraso, atraso_longo, passou, teto) = critica + pergunta cliente_aviso; origem dono ou tipo ainda não liberado = pedida + pergunta cliente_aprovar; botão = aprovada (aprovada_por = p_autor); senão livre. base guarda {status, dia_alvo, fim, nivel, prometido_ate, primeira, envio, referencia, dados} para a revalidação. A livre/aprovada que sai até o próximo tique vai a _agenda_cliente_enfileirar. p_dados: os do modelo (dia, fim, janela, n, faixa_de/ate, peca_de/ate, dito_de/ate, dia_dito, quando, n_feitos), primeira, prometido_tipo, chave (o sufixo da chave no lugar do dia: o lembrete e o andamento semanal), atraso_dias (o aviso crítico). Sem grant. CORREÇÃO FASE 5 (C2): (item 12) a véspera, o acesso e a mudança no dia ganham p_dados.saudacao pela hora do envio (Brasília: "Bom dia" antes das 12:00, "Boa tarde" depois), guardada em base.dados; (item 8) o M6 peca_sem_data não tem prometido_tipo; (item 15) a ação da sombra sem artigo antes do nome. CORREÇÃO FASE 6 (C1, item 4): o aviso de atraso (peca/execucao) com a folga do aprendizado em uso guarda em base.dados.faixa_ate_plano o fim da faixa sem a folga (a medição mede o estouro contra ele). FASE 7 (7a P11, spec §3.2 "Cliente" e §5.11; AG7-16): confirmar, nova_data e material_chegou de uma OS marcada pela estimativa do gestor (_agenda_os_por_estimativa no dia da mensagem) levam base.dados.por_estimativa = true e, fora da crítica, do botão e da do dono, pedem o sim do dono (aprovacao pedida, a pergunta cliente_aprovar "Mensagem para Lenine (confirmação do dia; o dia é pela minha estimativa), sai …") enquanto o tipo não somou cliente_aprovacao_dias dias distintos aprovados por estimativa (_agenda_cliente_estimativa_liberada), mesmo com o tipo já liberado. O texto ao cliente não muda; a véspera e os outros tipos, também não. Sem OS por estimativa, a de antes, byte a byte. FASE 7f (P6): a semana (M12) só fica ligada com as camadas ligadas pelo freio (_agenda_fala_modo); senão é teste. O prometido_tipo dela vem de p_dados (faixa ou condicional). FASE 7f (P9): a semana que mudou (variante mudou) nasce SEMPRE pedida em ligado (mesmo com o tipo liberado e com motivo crítico), com a pergunta cliente_aprovar "Vou mudar o que Nelson ouviu: era a semana de 16/11, fica a semana de 23/11. Mensagem pronta, sai …: "…". *manda cliente Nelson* ou *segura cliente Nelson*."; sem a semana dita ou a nova = 22023. Em teste, livre e sem pergunta, como as outras.';

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
  -- FASE 7f: (7f P9, §5.6; a revalidação da semana que mudou tem regra própria) a semana que mudou passa pela regra da semana logo acima (o 1º ou o último dia do
  -- plano de agora fora da semana NOVA = desatualizada: a semana nova também saiu) e, além dela: o prometido mudou desde que ela nasceu (outra mensagem saiu, o dono
  -- mandou outra data, o prometido foi tirado) = desatualizada. Sem base.dados.dito_msg (não nasceu pela rodada), também
  if m.tipo = 'semana' and m.variante = 'mudou'
     and ((m.base #>> '{dados,dito_msg}') is null
          or (m.base #>> '{dados,dito_msg}') is distinct from (select p.prometido_mensagem_id::text from public.os_planejamento p
                                                                where p.service_order_id = m.service_order_id)) then
    return 'desatualizada';
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
  'Agenda de Produção (Fase 5, P2): a mensagem ao cliente ainda vale em p_agora? null = sai; senão, na ordem: opt_out (_agenda_cliente_sem_mensagem); status (OS cancelada/rascunho; confirmar, véspera, acesso, material chegou, nova data e mudança no dia com a OS aguardando peça, aguardando o cliente ou concluída; andamento fora de in_progress; pronto e lembrete fora de completed ou já entregue; pós-serviço fora de completed; aviso de atraso com a OS concluída); data_mudou (o próximo dia do plano — sem plano no registro, o dia agendado da OS — ≠ base.dia_alvo; no andamento e no atraso da execução, o último dia ≠ base.fim); material (data firme com algum crítico fora de A, os_prontidao); passou_da_data (aviso de atraso com o prometido_ate antes de hoje); mesmo_tipo_24h (outra do mesmo tipo a ele enviada nas últimas cliente_mesmo_tipo_horas); desatualizada (_agenda_cliente_texto com os dados do registro, a 1ª mensagem de base e o dia do envio de agora ≠ o texto registrado, ou o modelo que não fecha mais). STABLE, definer, sem grant (o pode_sair do worker e as travas a chamam). CORREÇÃO FASE 5 (C1, item 13): depois do opt_out, sem_conversa (o d10: _agenda_cliente_conversou em p_agora; sem telefone válido, sem_telefone) — vale também no gatilho da fila e no pode_sair. CORREÇÃO FASE 5 (C2): (item 24) a OS faturada vale como concluída; (item 6) o M6 remarcado na forma fim também recusa data_mudou quando o último dia ≠ base.fim; (item 7) a data firme do dono (origem dono, base.dados.firme_do_dono) não passa pelo passo 4 (material). FASE 7d (P6; R6.7a-3, §5.6): onde_fica é relida na hora de sair — status com _agenda_cliente_ja_atendida (in_progress, awaiting_client, completed, faturada, entregue, check-in, check-out, resultado, turno, paga) e desatualizada com _agenda_cliente_onde_falta nula (o local e a situação já ditos). FASE 7f (P6): a semana: tipo_em_teste sem as camadas ligadas de verdade; status com a OS começada, esperando peça ou cliente, ou concluída; desatualizada quando o 1º ou o último dia do plano de agora saiu da faixa dita. FASE 7f (P9): a semana que mudou passa pela regra da semana (a semana nova também saiu = desatualizada) e, além dela, é desatualizada quando o prometido mudou desde que ela nasceu (base.dados.dito_msg ≠ o prometido_mensagem_id de agora, ou sem ele).';

-- ── 5. A saúde da comunicação: a equipe e o cliente ─────────────────────────────────────────────────
-- §11 aceites 6 e 7 (NOVO-agenda-131 e 138). Os zeros só contam o que a 7f manda de verdade (ligado): 0 hoje em produção (sql/wf7f9_zeros, dom 08/11). Os números,
-- como os de antes, só com o modo deles fora de desligado.
create or replace function public._agenda_saude_comunicacao(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_semana  constant int := 7;    -- estrutural: os números "na semana" (§11)
  c_quinze  constant int := 14;   -- estrutural: "desfeitas em 2 semanas" (§11, parar)
  c_lotes   constant int := 2;    -- estrutural: o alvo de §11 é 2 lotes (o fechamento e a quinta) mais acordes_dia_max
  -- estrutural: a lista do CHECK agenda_config_veto_tipos_check (20261109100000), o que nunca vence pelo prazo; o V3 confere que é a mesma
  c_nunca   constant text[] := array['diaria', 'diaria_ligar', 'nfe_vincular', 'pix_material', 'concluir', 'entrega', 'cliente_aprovar', 'cliente_aviso',
                                     'cliente_resposta', 'aprendizado', 'conferencia', 'remarcar_confirmado', 'compre_ate', 'sinal', 'tarefa', 'local',
                                     'combinar', 'acesso', 'dia_prometido', 'dia_avisado'];
  cf        public.agenda_config;
  v_uid     uuid := auth.uid();
  v_papel   text;
  v_modos   jsonb;
  v_algum   boolean;
  v_ult     timestamptz;
  v_rod24   int;
  v_abertas int;
  v_acima   int;
  v_bloco   jsonb := '{}'::jsonb;
  v_bgrande int := 0;
  v_z       jsonb;
  v_n       jsonb := '{}'::jsonb;
begin
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
    raise exception '_agenda_saude_comunicacao: sem o dia de hoje ou a hora' using errcode = '22004';
  end if;
  cf := public._agenda_cfg();
  v_modos := jsonb_build_object('bloco', cf.modo_bloco_agenda, 'lote', cf.modo_lote_dono, 'veto', cf.modo_veto, 'previsto', cf.modo_equipe_previsto,
                                'convite', cf.modo_equipe_convite, 'camadas', cf.modo_cliente_camadas);
  v_algum := exists (select 1 from jsonb_each_text(v_modos) m where m.value <> 'desligado');
  select max(r.p_agora), count(*) filter (where r.p_agora > p_agora - interval '1 day' and r.p_agora <= p_agora)
    into v_ult, v_rod24
    from public.agenda_vigia_rodadas r
   where r.rotina = 'comunicar' and r.p_agora <= p_agora;
  -- as que contam no teto, como _agenda_comunicar_teto: ligadas, sem conferencia, que valem
  select count(*)::int into v_abertas from public.agenda_perguntas x
   where x.estado = 'aberta' and x.modo = 'ligado' and x.tipo <> 'conferencia' and (x.expira_em is null or x.expira_em > p_agora);
  v_acima := greatest(v_abertas - cf.perguntas_abertas_max, 0);

  -- o bloco nos fechamentos dos últimos 7 dias, pelo detalhe de resumo_tarde (P3): em sombra, bloco_seria (o texto que sairia com ele ligado); ligado, bloco_mostrou e o texto que saiu.
  -- No mínimo o bloco é o veredito e a 1ª decisão (com o "e mais N"): acima de texto_max com qualquer outra linha, ele ainda podia ceder, e isso é o bloco_grande.
  -- A tabela é a do Secretário (20261015210000); um resumo_tarde sem as colunas que o bloco lê (o da bancada da Fase 2 tem só dia, telefone e detalhe) conta como sem a tabela.
  if to_regclass('public.resumo_tarde') is not null
     and (select count(*) from pg_attribute a where a.attrelid = to_regclass('public.resumo_tarde') and a.attnum > 0 and not a.attisdropped
             and a.attname in ('dia', 'turno', 'detalhe', 'criado_em')) = 4 then
    execute $q$
      select coalesce(jsonb_build_object(
               'em_sombra', count(*) filter (where t.detalhe -> 'agenda' ? 'bloco_seria'),
               'seria_dentro', count(*) filter (where (t.detalhe #>> '{agenda,bloco_seria,caracteres}')::int <= $3),
               'seria_acima', count(*) filter (where (t.detalhe #>> '{agenda,bloco_seria,caracteres}')::int > $3),
               'seria_dentro_por_turno', coalesce((select jsonb_object_agg(z.turno, z.n) from (
                   select u.turno, count(*) as n from public.resumo_tarde u
                    where u.dia between $1 and $2 and (u.detalhe #>> '{agenda,bloco_seria,caracteres}')::int <= $3 group by u.turno) z), '{}'::jsonb),
               'ligado', count(*) filter (where t.detalhe -> 'agenda' ? 'bloco_mostrou'),
               'ligado_acima', count(*) filter (where t.detalhe -> 'agenda' ? 'bloco_mostrou' and (t.detalhe ->> 'caracteres')::int > $3),
               'ultimo', (select jsonb_build_object('dia', u.dia, 'turno', u.turno, 'modo', u.detalhe #>> '{agenda,bloco_diria,modo}',
                                                    'caracteres', coalesce((u.detalhe #>> '{agenda,bloco_seria,caracteres}')::int, (u.detalhe ->> 'caracteres')::int))
                            from public.resumo_tarde u
                           where u.dia between $1 and $2 and u.detalhe -> 'agenda' ? 'bloco_diria'
                           order by u.dia desc, u.criado_em desc limit 1)), '{}'::jsonb),
             count(*) filter (where t.detalhe -> 'agenda' ? 'bloco_mostrou' and (t.detalhe ->> 'caracteres')::int > $3
                                and ((select count(*) from jsonb_array_elements(t.detalhe #> '{agenda,bloco_mostrou}') l where l ->> 'parte' not in ('veredito', 'decisao')) > 0
                                     or (select count(*) from jsonb_array_elements(t.detalhe #> '{agenda,bloco_mostrou}') l where l ->> 'parte' = 'decisao') > 2))::int
        from public.resumo_tarde t
       where t.dia between $1 and $2 and t.detalhe -> 'agenda' ? 'bloco_diria'
    $q$ into v_bloco, v_bgrande using p_hoje - c_semana + 1, p_hoje, cf.texto_max;
  end if;

  v_z := jsonb_build_object(
    'assumida_sem_prazo_mostrado', (select count(*) from public.agenda_perguntas q
                                     where q.assumida_por = 'prazo'
                                       and not coalesce(q.veto_ate is not null and q.mostrada_vezes > 0 and q.mostrada_em < q.veto_ate, false)),
    'assumida_que_esperava', (select count(*) from public.agenda_perguntas q where q.assumida_por is not null and q.veto_espera is not null),
    'assumida_tipo_proibido', (select count(*) from public.agenda_perguntas q where q.assumida_por is not null and q.tipo = any (c_nunca)),
    'teto_passou_sem_motivo', case when v_acima = 0 or public._agenda_fala_modo('veto') <> 'ligado' then 0 else
       least(v_acima, (select count(*)::int from public.agenda_perguntas x
                        where x.estado = 'aberta' and x.modo = 'ligado' and x.tipo <> 'conferencia' and (x.expira_em is null or x.expira_em > p_agora)
                          and x.padrao_efeito = 'nada' and x.opcao_escolhida is null and x.criada_em < v_ult
                          and public._agenda_pergunta_espera(x, p_hoje) is null)) end,
    'bloco_grande', coalesce(v_bgrande, 0),
    'excecao_acima_do_teto', greatest(- public._agenda_lote_cota(p_hoje), 0));
  -- FASE 7f: (7f P9, §11 aceites 6 e 7; NOVO-agenda-131 e 138) os zeros da equipe e do cliente, que entram no zeros_ok (e por ele no ok de agenda_saude). Só o que
  -- a 7f manda de verdade (ligado): em teste nada conta. Hoje 0 em produção (sql/wf7f9_zeros, dom 08/11). A equipe: o previsto, a mudança e o convite fora da janela
  -- ou no domingo; o dia com mais que equipe_proativas_dia_max mensagens de quem recebeu alguma da 7f; a ficha do dia com convite sem o SIM antes dela (AG7-23); mais
  -- de uma mudança das 19:30 por pessoa e dia. O cliente: o dia exato (o M1 e o M3 marcados pela estimativa) antes de cliente_dia_exato_du dias úteis do dia, ao
  -- cliente que ouviu a semana daquele dia; a semana que mudou enviada sem o *manda cliente*; a semana como dia ouvido (firme)
  v_z := v_z || jsonb_build_object(
    'equipe_fora_da_janela', (select count(*) from public.agenda_equipe_mensagens e
                               where e.tipo in ('previsto', 'mudanca', 'convite') and e.modo = 'ligado' and e.estado in ('enfileirada', 'respondida', 'sem_resposta')
                                 and (extract(isodow from e.enviar_em at time zone 'America/Sao_Paulo') = 7
                                      or (e.enviar_em at time zone 'America/Sao_Paulo')::time < cf.equipe_janela_inicio
                                      or (e.enviar_em at time zone 'America/Sao_Paulo')::time > cf.equipe_janela_fim)),
    'equipe_acima_do_teto', (select count(*) from (select e.payee_id from public.agenda_equipe_mensagens e
                                                    where e.modo = 'ligado' and e.tipo <> 'resposta' and e.estado in ('enfileirada', 'respondida', 'sem_resposta')
                                                    group by e.payee_id, (e.enviar_em at time zone 'America/Sao_Paulo')::date
                                                   having count(*) > cf.equipe_proativas_dia_max and bool_or(e.tipo in ('previsto', 'mudanca', 'convite'))) g),
    'ficha_sem_sim', (select count(*) from public.agenda_equipe_mensagens f
                       where f.tipo = 'ficha' and f.modo = 'ligado' and f.estado in ('enfileirada', 'respondida', 'sem_resposta')
                         and exists (select 1 from public.agenda_equipe_mensagens c
                                      where c.tipo = 'convite' and c.modo = 'ligado' and c.payee_id = f.payee_id and c.dia = f.dia and c.estado <> 'recusada'
                                        and c.criada_em <= f.enviar_em
                                        and not coalesce(c.leitura ->> 'convite' = 'sim' and c.resposta_em <= f.enviar_em, false))),
    'mudanca_19h_repetida', (select count(*) from (select 1 from public.agenda_equipe_mensagens e
                                                    where e.tipo = 'mudanca' and e.modo = 'ligado' and e.dedupe_key like '%:19h' and e.estado <> 'recusada'
                                                    group by e.payee_id, (e.enviar_em at time zone 'America/Sao_Paulo')::date having count(*) > 1) g),
    'dia_exato_cedo', (select count(*) from public.agenda_cliente_mensagens m
                        where m.tipo in ('confirmar', 'material_chegou') and m.modo = 'ligado' and m.enviada_em is not null and m.dia_alvo is not null
                          and coalesce((m.base #>> '{dados,por_estimativa}')::boolean, false)
                          and exists (select 1 from public.agenda_cliente_mensagens s
                                       where s.service_order_id = m.service_order_id and s.tipo = 'semana' and s.modo = 'ligado' and s.enviada_em is not null
                                         and s.enviada_em < m.enviada_em and m.dia_alvo between s.faixa_de and s.faixa_ate)
                          and (m.enviada_em at time zone 'America/Sao_Paulo')::date < public.agenda_somar_du(m.dia_alvo, - cf.cliente_dia_exato_du)),
    'promessa_mudou_sem_dono', (select count(*) from public.agenda_cliente_mensagens m
                                 where m.tipo = 'semana' and m.variante = 'mudou' and m.enviada_em is not null and m.aprovacao is distinct from 'aprovada'),
    'semana_como_dia_ouvido', (select count(*) from public.agenda_cliente_mensagens m where m.tipo = 'semana' and m.prometido_tipo = 'firme')
                              + (select count(*) from public.os_planejamento p join public.agenda_cliente_mensagens m on m.id = p.prometido_mensagem_id
                                  where m.tipo = 'semana' and p.prometido_tipo = 'firme'));
  -- FASE 7f: fim

  if v_algum then
    v_n := jsonb_build_object(
      'perguntas', (select jsonb_build_object(
                             'abertas', v_abertas, 'teto', cf.perguntas_abertas_max, 'acima_do_teto', v_acima,
                             'com_prazo', count(*) filter (where q.estado = 'aberta' and q.veto_ate is not null and q.veto_espera is null),
                             'esperam_voce', count(*) filter (where q.estado = 'aberta' and q.veto_espera = 'dono'),
                             'respondidas_semana', count(*) filter (where q.estado = 'respondida' and q.assumida_por is null
                                                                     and q.respondida_em > p_agora - make_interval(days => c_semana)),
                             'assumidas_prazo_semana', count(*) filter (where q.assumida_por = 'prazo' and q.assumida_em > p_agora - make_interval(days => c_semana)),
                             'assumidas_teto_semana', count(*) filter (where q.assumida_por = 'teto' and q.assumida_em > p_agora - make_interval(days => c_semana)),
                             'teria_semana', count(*) filter (where q.veto_teria_em > p_agora - make_interval(days => c_semana)))
                      from public.agenda_perguntas q where q.modo = 'ligado')
                   || jsonb_build_object(
                        'idade_media_du', (select round(avg((select count(*) from generate_series((x.criada_em at time zone 'America/Sao_Paulo')::date + 1, p_hoje, interval '1 day') d
                                                              where public.agenda_dia_util(d::date)))::numeric, 1)
                                             from public.agenda_perguntas x
                                            where x.estado = 'aberta' and x.modo = 'ligado' and x.tipo <> 'conferencia' and (x.expira_em is null or x.expira_em > p_agora)),
                        'complacencia', (select jsonb_build_object('assumidas', count(*),
                                                                   'desfeitas', count(*) filter (where exists (select 1 from public.agenda_acoes a
                                                                                                                where a.pergunta_id = q.id and a.desfeita_em is not null)))
                                           from public.agenda_perguntas q
                                          where q.assumida_por = 'prazo' and q.assumida_em > p_agora - make_interval(days => c_quinze))),
      'excecoes', jsonb_build_object(
        'hoje', (select count(*) from public.agenda_dono_avisos v where v.dia = p_hoje and v.fila_id is not null and v.dedupe_key like 'agenda-dono:excecao:%'),
        'cota_livre', greatest(public._agenda_lote_cota(p_hoje), 0),
        'acima_da_cota_hoje', (select count(distinct x) from public.agenda_vigia_rodadas r
                                 cross join lateral jsonb_array_elements_text(coalesce(r.contagens #> '{lote_guardaria,acima_da_cota_ids}', '[]'::jsonb)) x
                                where r.rotina = 'comunicar' and r.p_hoje = p_hoje),
        'em_sombra_hoje', (select jsonb_build_object('avisos', count(*),
                                                     'levaria', coalesce(sum((r.contagens #>> '{lote_guardaria,levaria,acoes}')::int), 0),
                                                     'guardaria', coalesce(sum((r.contagens #>> '{lote_guardaria,guardaria,acoes}')::int), 0),
                                                     'guardaria_perguntas', coalesce(sum((r.contagens #>> '{lote_guardaria,guardaria,perguntas}')::int), 0),
                                                     'acima_da_cota', coalesce(sum((r.contagens #>> '{lote_guardaria,acima_da_cota}')::int), 0))
                             from public.agenda_vigia_rodadas r
                            where r.rotina = 'comunicar' and r.p_hoje = p_hoje and r.contagens #> '{lote_guardaria,aviso}' is not null)),
      'quinta', jsonb_build_object(
        'saiu', (select jsonb_build_object('dia', v.dia, 'estado', v.estado, 'enviada_em', v.enviada_em,
                                           'mudancas', cardinality(v.acao_ids), 'perguntas', cardinality(v.pergunta_ids))
                   from public.agenda_dono_avisos v
                  where v.dedupe_key like 'agenda-dono:semana:%' and v.dia between p_hoje - c_semana + 1 and p_hoje
                  order by v.dia desc limit 1),
        'diria', (select jsonb_build_object('dia', r.p_hoje, 'caracteres', (r.contagens #>> '{quinta,quinta_diria,caracteres}')::int,
                                            'cabe', (r.contagens #>> '{quinta,quinta_diria,cabe}')::boolean, 'motivo', r.contagens #>> '{quinta,quinta_diria,motivo}',
                                            'mudancas', (r.contagens #>> '{quinta,quinta_diria,mudancas}')::int, 'perguntas', (r.contagens #>> '{quinta,quinta_diria,perguntas}')::int)
                    from public.agenda_vigia_rodadas r
                   where r.rotina = 'comunicar' and r.p_hoje between p_hoje - c_semana + 1 and p_hoje and r.contagens #> '{quinta,quinta_diria}' is not null
                   order by r.p_agora desc limit 1)),
      'bloco', v_bloco,
      'mensagens_hoje', (select jsonb_build_object('fechamento', count(*) filter (where f.source = 'ai_briefing_tarde'),
                                                   'aviso', count(*) filter (where f.source = 'agenda-dono'),
                                                   'acorde', count(*) filter (where f.source = 'agenda'),
                                                   'alvo', c_lotes + cf.acordes_dia_max)
                           from public.whatsapp_send_queue f
                          where f.source in ('ai_briefing_tarde', 'agenda-dono', 'agenda') and f.status not in ('failed', 'cancelled')
                            and f.created_at >= (p_hoje::timestamp at time zone 'America/Sao_Paulo')
                            and f.created_at < ((p_hoje + 1)::timestamp at time zone 'America/Sao_Paulo')));
  end if;

  -- FASE 7f: (7f P9, §11 "Métricas": equipe e cliente, por semana) os números, como os de antes, só com o modo deles fora de desligado. Em teste conta o que foi
  -- registrado (em_teste); de verdade, o que saiu e o que voltou. Só contagens
  if cf.modo_equipe_previsto <> 'desligado' or cf.modo_equipe_convite <> 'desligado' then
    v_n := v_n || jsonb_build_object('equipe', (
      select jsonb_build_object(
               'previstos', count(*) filter (where e.tipo = 'previsto' and e.modo = 'ligado' and e.estado <> 'recusada'),
               'mudancas', count(*) filter (where e.tipo = 'mudanca' and e.modo = 'ligado' and e.estado <> 'recusada'),
               'mudancas_19h', count(*) filter (where e.tipo = 'mudanca' and e.modo = 'ligado' and e.estado <> 'recusada' and e.dedupe_key like '%:19h'),
               'convites', count(*) filter (where e.tipo = 'convite' and e.modo = 'ligado' and e.estado <> 'recusada'),
               'convites_sim', count(*) filter (where e.tipo = 'convite' and e.modo = 'ligado' and e.leitura ->> 'convite' = 'sim'),
               'convites_nao', count(*) filter (where e.tipo = 'convite' and e.modo = 'ligado' and e.leitura ->> 'convite' = 'nao'),
               'convites_sem_resposta', count(*) filter (where e.tipo = 'convite' and e.modo = 'ligado' and e.estado = 'sem_resposta'),
               'recusadas', count(*) filter (where e.modo = 'ligado' and e.estado = 'recusada'),
               'em_teste', count(*) filter (where e.modo = 'sombra'),
               'nao_depois_de_mudanca', (select count(*) from public.agenda_disponibilidade d
                                          where d.origem = 'diarista' and d.situacao = 'indisponivel' and d.substituida_em is null
                                            and d.criado_em > p_agora - make_interval(days => c_semana)
                                            and exists (select 1 from public.agenda_equipe_mensagens x
                                                         where x.payee_id = d.payee_id and x.tipo in ('mudanca', 'convite') and x.modo = 'ligado'
                                                           and x.estado <> 'recusada' and x.criada_em < d.criado_em
                                                           and (d.periodo @> x.dia or exists (select 1 from unnest(coalesce(x.dias, '{}'::date[])) u(dia) where d.periodo @> u.dia)))))
        from public.agenda_equipe_mensagens e
       where e.tipo in ('previsto', 'mudanca', 'convite') and e.criada_em > p_agora - make_interval(days => c_semana)));
  end if;
  if cf.modo_cliente_camadas <> 'desligado' then
    v_n := v_n || jsonb_build_object('cliente', (
      select jsonb_build_object(
               'semanas', jsonb_build_object(
                 'registradas', count(*) filter (where m.tipo = 'semana' and m.variante is distinct from 'mudou' and m.modo = 'ligado'),
                 'enviadas', count(*) filter (where m.tipo = 'semana' and m.variante is distinct from 'mudou' and m.modo = 'ligado' and m.enviada_em is not null),
                 'seguradas', count(*) filter (where m.tipo = 'semana' and m.variante is distinct from 'mudou' and m.aprovacao = 'segurada'),
                 'vencidas', count(*) filter (where m.tipo = 'semana' and m.variante is distinct from 'mudou' and m.aprovacao = 'vencida'),
                 'em_teste', count(*) filter (where m.tipo = 'semana' and m.variante is distinct from 'mudou' and m.modo = 'sombra')),
               'semana_mudou', jsonb_build_object(
                 'registradas', count(*) filter (where m.tipo = 'semana' and m.variante = 'mudou' and m.modo = 'ligado'),
                 'mandadas', count(*) filter (where m.tipo = 'semana' and m.variante = 'mudou' and m.aprovacao = 'aprovada'),
                 'seguradas', count(*) filter (where m.tipo = 'semana' and m.variante = 'mudou' and m.aprovacao = 'segurada'),
                 'vencidas', count(*) filter (where m.tipo = 'semana' and m.variante = 'mudou' and m.aprovacao = 'vencida'),
                 'enviadas', count(*) filter (where m.tipo = 'semana' and m.variante = 'mudou' and m.enviada_em is not null),
                 'em_teste', count(*) filter (where m.tipo = 'semana' and m.variante = 'mudou' and m.modo = 'sombra')),
               'mudancas_ao_cliente', count(*) filter (where m.modo = 'ligado' and m.enviada_em is not null
                                                         and (m.tipo in ('pode_atrasar', 'nova_data', 'mudanca_no_dia') or (m.tipo = 'semana' and m.variante = 'mudou'))))
        from public.agenda_cliente_mensagens m
       where m.criada_em > p_agora - make_interval(days => c_semana)));
  end if;
  -- FASE 7f: fim
  return jsonb_build_object(
    'modos', v_modos, 'freio', cf.gestor_so_propor,
    'ultima_rodada', v_ult, 'rodadas_24h', coalesce(v_rod24, 0),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.action like 'comunicar:%' and e.last_seen_at >= least(p_agora, now()) - interval '1 day'),
    'falhas_lote_guardaria_24h', (select count(*) from public.app_error_logs e
                                   where e.context = 'agenda' and e.action = 'comunicar:lote_guardaria' and e.last_seen_at >= least(p_agora, now()) - interval '1 day'),
    'zeros_ok', not exists (select 1 from jsonb_each(v_z) z where (z.value)::text <> '0'),
    'numeros', v_n) || v_z;
end;
$function$;
comment on function public._agenda_saude_comunicacao(date, timestamptz) is
  'Agenda de Produção (Fase 7f, P7; §11, R8.5-27, R8.5-29, R8.6): a saúde da comunicação — {modos (os 6, crus), freio, ultima_rodada e rodadas_24h (rotina comunicar), erros_24h (comunicar:%), falhas_lote_guardaria_24h, zeros_ok, numeros} e os zeros: assumida_sem_prazo_mostrado, assumida_que_esperava, assumida_tipo_proibido, teto_passou_sem_motivo, bloco_grande, excecao_acima_do_teto. numeros só com algum modo fora de desligado: perguntas (abertas, teto, com prazo, esperam você, respondidas, assumidas por prazo e por teto, teria, idade média em dias úteis, complacência de 2 semanas), excecoes (hoje, cota livre, os ids distintos acima da cota; em sombra o que o lote levaria e guardaria), quinta (a que saiu; em sombra a que diria), bloco (resumo_tarde de 7 dias), mensagens_hoje por origem (aviso = agenda-dono, acorde = agenda; só contagens). A porta de _agenda_saude_local: administrador, financeiro ou service_role; o resto 42501. FASE 7f (P9): os zeros da equipe (equipe_fora_da_janela, equipe_acima_do_teto, ficha_sem_sim, mudanca_19h_repetida; aceite 6) e do cliente (dia_exato_cedo, promessa_mudou_sem_dono, semana_como_dia_ouvido; aceite 7), só do que a 7f manda de verdade, no zeros_ok; numeros.equipe (com o previsto ou o convite fora de desligado: previstos, mudanças, convites com SIM, NÃO e sem resposta, recusadas, em teste, "não vou" depois de mudança ou convite, na semana) e numeros.cliente (com as camadas fora de desligado: as semanas registradas, enviadas, seguradas, vencidas e em teste, a semana que mudou mandada, segurada, vencida e enviada, e as mudanças que chegaram ao cliente, na semana).';

-- ── 6. Portas ───────────────────────────────────────────────────────────────────────────────────────
-- A nova: sem grant (quem a chama é o passo do atraso, na rodada do cliente, definer). As recriadas: as portas de antes, as de produção em 08/11
-- (sql/wf7f9_md5_antes), repetidas para a migration valer sozinha.
revoke all on function public._agenda_cliente_semana_mudou(uuid, jsonb, date, timestamptz, timestamptz, timestamptz),
                       public._agenda_cliente_atraso(date, timestamptz),
                       public._agenda_cliente_registrar(text, text, uuid, date, jsonb, timestamptz, timestamptz, text, text, timestamptz, uuid),
                       public._agenda_cliente_revalidar(uuid, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public._agenda_cliente_texto(text, text, uuid, jsonb, date),
                       public._agenda_saude_comunicacao(date, timestamptz)
  from public, anon;
grant execute on function public._agenda_cliente_texto(text, text, uuid, jsonb, date),
                          public._agenda_saude_comunicacao(date, timestamptz)
  to authenticated, service_role;
