-- Agenda de Produção, Fase 7, etapa 7g ("Mostrar como pensou e provar o trabalho"), pacote P7: a conversa e a tela. O assistente e as palavras diretas leem
-- "como você pensou a semana", "por que o Nelson ficou assim" e o placar da semana pelo agenda_ver; a Semana mostra quem marcou cada bloco e a linha do porquê;
-- o cartão da OS ganha "Por que assim".
-- Spec: scratchpad agenda-pesquisa/spec-fase7g.md (§5.7, §7 e o bloco R9, que vale sobre o corpo: R9.5-10, 18, 19 e 20, R9.12, R9.13 — "R9.5-10, 18, 19, 20;
-- R9.15; os_plano_da_os de 20261111100600; dado 20261112100990"); o registro do pacote: notas-fase7g.md (seção P7). Depende das Fases 1 a 6, das etapas 7a a
-- 7d, da 7f inteira, da 7e inteira e da 7g até o P6 (20261112100000: modo_porque, modo_explicar, modo_placar; 20261112100200: _agenda_porque_da_os,
-- _agenda_porque_linha, agenda_como_pensei; 20261112100500: agenda_placar).
--
-- ═══ DDL — OK NOMEADO ═══ (3 funções recriadas; nenhuma função nova, tabela, coluna, gatilho, CHECK, policy ou grant)
-- NÃO APLICADA. Existe para revisão e espera o OK.
--
-- POR QUE: as leituras da 7g (P3 a P6) existem no banco, mas ninguém as chama: o dono não tem como perguntar "como você pensou a semana", "por que o Nelson
-- ficou de fora" nem pedir o placar, e a tela não diz quem marcou nem por quê.
--
-- O QUE MUDA (com os modos da 7g desligados, nada que o dono veja: as respostas são as de antes, byte a byte; em sombra, as de antes e o novo só em dados.teste):
--   1. agenda_ver (recriada de 20261107100700_agenda_fase7d_leituras.sql:574; md5 do corpo de antes ca961e991cf9ad83388b758c0b429dbf): os focos como_pensou, porque e placar, antes da conferência dos 19 da Fase 6 (R9.5-18: como
--      gestor, habilidades e locais; a mensagem dos 19 não muda). como_pensou: a semana dita (sem ela, a que vem) por agenda_como_pensei; com modo_explicar
--      desligado, a leitura de antes da semana (a rota semana, R9.5-10). porque: com a OS, _agenda_porque_da_os (de fora, o motivo de agora e a pergunta dela,
--      R9.12-1); sem a OS, a pergunta "De qual serviço?"; com modo_explicar desligado, a leitura de antes da OS (a rota os). placar: agenda_placar da semana
--      dita (sem ela, a da janela); com modo_placar desligado, a frase com a saída (*como foi a semana*). Em sombra, a resposta de fora de ligado e o novo em
--      dados.teste. O livre e a semana não mudam (agenda_livre_de_verdade só simula com a agenda automática ligada: alargar a condição daqui não mudaria nada).
--   2. agenda_tela_semana (recriada de 20261026100600_agenda_fase3_telas.sql:766; md5 do corpo de antes 469bd10a3cf5e57784a0dbb1e086dce3): com modo_porque ligado (e o plano publicado, não a sombra do motor), cada bloco ganha
--      quem (gestor | dono), quem_texto ("marcado pelo gestor", "marcado por você"; na reserva, "reservado …") e porque_texto (a linha do porquê, ≤ 120). Fora
--      de ligado, as chaves ficam ausentes (R9.5-19).
--   3. os_plano_da_os (recriada de 20261111100600_agenda_fase7e_rodada.sql:1741; md5 do corpo de antes b61e1cc95db65d7dcc5687a680a15f02, a da 7e P7, com os 6 blocos "-- FASE 7e:" que ficam): com modo_porque ligado, na OS marcada
--      ou reservada que ainda vai ser feita, a chave porque = {quem_texto, fonte_texto, suposicoes: [texto], criterio_texto, degrau_texto} (o porquê de
--      _agenda_porque_da_os sem o texto longo). Fora de ligado, sem nada a dizer ou se a leitura falhar, a chave fica ausente (R9.5-19).
--
-- O QUE NÃO MUDA: o motor, a vigia, o que se grava (as 3 só leem), as portas (create or replace não muda a ACL; as leituras da 7g chamadas aqui têm a delas),
-- as respostas de antes dos 19 focos, o ctp, o livre e a semana. Nenhum texto novo ao cliente. Nada de dinheiro. Não toca agenda_cliente_mensagens,
-- agenda_cliente_respostas, a leitura da resposta do cliente nem cliente_resposta_validade.
--
-- ORDEM DE LIGAR (spec R9.14): depois da 20261112100500. Aplicar sozinha não muda nada: os modos da 7g ficam como estiverem (desligados até o dado
-- 20261112100990). Os focos ligam com "OK ligar as leituras" (modo_explicar) e "OK ligar o placar" (modo_placar); a tela e o cartão, com "OK ligar o porquê
-- na tela" (modo_porque). O roteiro em linguagem do dono: fila-do-dono/fase7g-oks.md.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7g_tela.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261112100600
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; pelo publicar/exec/aplicar.sh, nunca db push: esta versão fica antes das 20261116* que já estão em produção):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261112100600_agenda_fase7g_tela.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261112100600', 'agenda_fase7g_tela');"
--
-- DESFAZER: agenda_ver, agenda_tela_semana e os_plano_da_os voltam pelo corpo das origens (acima). Nada a apagar.
--
-- IDEMPOTENTE: create or replace function e comment.

-- ── 1. A conversa: os focos como_pensou, porque e placar ────────────────────────────────────────────

create or replace function public.agenda_ver(p_autor uuid default null, p_periodo text default null,
                                             p_pessoa text default null, p_foco text default null, p_os text default null,
                                             p_simular jsonb default null, p_simular_aprovacao boolean default false,
                                             p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_foco    text := coalesce(nullif(btrim(lower(p_foco)), ''), 'tudo');
  v_rp      jsonb;
  v_payee   uuid;
  v_eh_dono boolean := true;
  v_de      date;
  v_ate     date;
  v_ro      jsonb;
  v_r       jsonb;
  v_pn      jsonb;
  v_rota    text;
  v_max     int;
  v_l       text[];
  k         int;
  -- FASE 2: a hora de agora (desfazer ainda vale? a decisão venceu?). now(); a bancada fixa com agenda.agora.
  v_agora   timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  -- FASE 3: o livre de verdade (a simulação do motor) e o mês da comissão
  v_lv      jsonb;
  v_mes     date;
begin
  -- FASE 7: (7a P7) o foco gestor (spec §6.2: o que o gestor da agenda marcou ou marcaria sozinho e por quê, o que perguntou
  -- antes, o que fica de fora e como ele conta — _agenda_ver_gestor), antes da conferência dos 19 da Fase 6, que o foco gestor
  -- não alcança (o foco que não existe continua com a mensagem dos 19). Com login, só administrador e financeiro (42501, antes
  -- de ler a config); desligada a leitura, a frase de sempre.
  if v_foco = 'gestor' then
    if p_hoje is null then
      raise exception 'agenda_ver: sem o dia de hoje' using errcode = '22004';
    end if;
    if auth.uid() is not null and not public.is_admin_or_financial(auth.uid()) then
      raise exception 'O gestor da agenda é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
    if (public._agenda_cfg()).modo_leitura = 'desligado' then
      return jsonb_build_object('ok', false, 'rota', 'desligada', 'desligada', true,
                                'texto', 'A agenda de produção está desligada agora.');
    end if;
    return public._agenda_ver_gestor(p_hoje) || jsonb_build_object('rota', 'gestor');
  end if;
  -- FASE 7: fim
  -- FASE 7c: (7c P6, spec §5.6, R5.6) o foco habilidades (quem faz o quê na equipe e o que cada OS pede: _agenda_ver_habilidades),
  -- antes da conferência dos 19 da Fase 6, que o foco não alcança (como o gestor: o foco que não existe continua com a mensagem dos 19).
  -- A porta do aprendizado: sem p_hoje, 22004; com login, só administrador e financeiro (42501, antes de ler a config); desligada a
  -- leitura, a frase de sempre. Com os, só o bloco da OS (a que não existe ou é ambígua: a frase do resolvedor, como os outros focos).
  if v_foco = 'habilidades' then
    if p_hoje is null then
      raise exception 'agenda_ver: sem o dia de hoje' using errcode = '22004';
    end if;
    if auth.uid() is not null and not public.is_admin_or_financial(auth.uid()) then
      raise exception 'Quem faz o quê é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
    if (public._agenda_cfg()).modo_leitura = 'desligado' then
      return jsonb_build_object('ok', false, 'rota', 'desligada', 'desligada', true,
                                'texto', 'A agenda de produção está desligada agora.');
    end if;
    if nullif(btrim(p_os), '') is not null then
      v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
      if v_ro ->> 'status' in ('nao_achei', 'ambiguo') then
        return jsonb_build_object('ok', false, 'rota', 'os', 'texto', v_ro ->> 'texto',
                                  'pergunta', case when v_ro ->> 'status' = 'ambiguo' then v_ro ->> 'texto' end,
                                  'opcoes', coalesce(v_ro -> 'opcoes', '[]'::jsonb));
      end if;
    end if;
    return public._agenda_ver_habilidades(p_hoje, v_agora, (v_ro ->> 'id')::uuid) || jsonb_build_object('rota', 'habilidades');
  end if;
  -- FASE 7c: fim
  -- FASE 7d: (7d P8; §5.8, §7, R6.3-12, R6.9-9) o foco locais (onde é cada serviço, o que combinar e as regras dos locais: _agenda_ver_locais), antes da conferência dos 19 da
  -- Fase 6, que o foco não alcança. A porta do foco habilidades: sem p_hoje, 22004; com login, só administrador e financeiro (42501, antes de ler a config); desligada a leitura,
  -- a frase de sempre. Com os, só a OS (a que não existe ou é ambígua: a frase do resolvedor).
  if v_foco = 'locais' then
    if p_hoje is null then
      raise exception 'agenda_ver: sem o dia de hoje' using errcode = '22004';
    end if;
    if auth.uid() is not null and not public.is_admin_or_financial(auth.uid()) then
      raise exception 'Os locais dos serviços são com o administrador ou o financeiro.' using errcode = '42501';
    end if;
    if (public._agenda_cfg()).modo_leitura = 'desligado' then
      return jsonb_build_object('ok', false, 'rota', 'desligada', 'desligada', true,
                                'texto', 'A agenda de produção está desligada agora.');
    end if;
    if nullif(btrim(p_os), '') is not null then
      v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
      if v_ro ->> 'status' in ('nao_achei', 'ambiguo') then
        return jsonb_build_object('ok', false, 'rota', 'os', 'texto', v_ro ->> 'texto',
                                  'pergunta', case when v_ro ->> 'status' = 'ambiguo' then v_ro ->> 'texto' end,
                                  'opcoes', coalesce(v_ro -> 'opcoes', '[]'::jsonb));
      end if;
    end if;
    return public._agenda_ver_locais(p_hoje, (v_ro ->> 'id')::uuid) || jsonb_build_object('rota', 'locais');
  end if;
  -- FASE 7d: fim
  -- FASE 7g: (7g P7; §5.7, R9.5-10, 18 e 19, R9.12-1, R9.14) os focos como_pensou, porque e placar, antes da conferência dos 19 da Fase 6, que eles não
  -- alcançam (como gestor, habilidades e locais: o foco que não existe continua com a mensagem dos 19). Quem lê é a função da 7g de cada um (SECURITY DEFINER,
  -- com a porta dela); a porta daqui é a mesma, antes de ler a config: com login, só administrador e financeiro (42501). Sem p_hoje, 22004; desligada a leitura,
  -- a frase de sempre. Com o modo da leitura (modo_explicar; no placar, modo_placar) fora de ligado, a resposta é a de antes, ou a frase com a saída; em sombra,
  -- ela e o novo em dados.teste (uma falha do novo não derruba a resposta: dados.teste = {erro}):
  --   como_pensou  a semana de p_periodo (sem ele, a que vem). Desligado: a leitura de antes (agenda_ver sem foco: a rota semana, byte a byte, R9.5-10);
  --                ligado: agenda_como_pensei (rota como_pensou).
  --   porque       sem os, a pergunta "De qual serviço?". Com os: desligado, a leitura de antes da OS (agenda_ver com os: a rota os); ligado,
  --                _agenda_porque_da_os (rota porque): marcada, reservada, de fora com o motivo de agora e a pergunta dela (R9.12-1), ou fora da carteira.
  --   placar       a semana de p_periodo (sem ele, a da janela). Desligado: "ainda não está ligado" e a saída, *como foi a semana*; ligado: agenda_placar
  --                (rota placar).
  if v_foco in ('como_pensou', 'porque', 'placar') then
    if p_hoje is null then
      raise exception 'agenda_ver: sem o dia de hoje' using errcode = '22004';
    end if;
    if auth.uid() is not null and not public.is_admin_or_financial(auth.uid()) then
      raise exception '%', case v_foco when 'como_pensou' then 'Como pensei a agenda é com o administrador ou o financeiro.'
                                       when 'porque' then 'O porquê da agenda é com o administrador ou o financeiro.'
                                       else 'O placar da agenda é com o administrador ou o financeiro.' end using errcode = '42501';
    end if;
    if (public._agenda_cfg()).modo_leitura = 'desligado' then
      return jsonb_build_object('ok', false, 'rota', 'desligada', 'desligada', true,
                                'texto', 'A agenda de produção está desligada agora.');
    end if;
    declare
      v_7g_m  text := case when v_foco = 'placar' then (public._agenda_cfg()).modo_placar else (public._agenda_cfg()).modo_explicar end;
      v_7g    jsonb;
      v_7g_de date;
    begin
      if v_foco = 'porque' and nullif(btrim(p_os), '') is null then
        return jsonb_build_object('ok', false, 'rota', 'porque', 'texto', 'De qual serviço? Me diga o nome do cliente.',
                                  'pergunta', 'De qual serviço? Me diga o nome do cliente.');
      end if;
      -- fora de ligado: a resposta de antes (a semana, a OS) ou a frase do placar; desligado, ou a de antes sem ok (o período, a OS que não existe), só ela
      if v_7g_m <> 'ligado' then
        v_r := case v_foco
                 when 'como_pensou' then public.agenda_ver(p_autor, coalesce(nullif(btrim(p_periodo), ''), 'proxima_semana'), null, null, null, null, false, p_hoje)
                 when 'porque' then public.agenda_ver(p_autor, null, null, null, p_os, null, false, p_hoje)
                 else jsonb_build_object('ok', true, 'rota', 'placar',
                        'texto', 'O placar da semana ainda não está ligado. O plano cumprido da semana passada está em *como foi a semana*.') end;
        if v_7g_m = 'desligado' or (v_r ->> 'ok') is distinct from 'true' then
          return v_r;
        end if;
      end if;
      begin
        -- a semana dita (como_pensou: sem ela, a que vem; placar: sem ela, a da janela) e a OS
        if v_foco = 'como_pensou' or (v_foco = 'placar' and nullif(btrim(p_periodo), '') is not null) then
          select x.de into v_7g_de from public._agenda_periodo(coalesce(nullif(btrim(p_periodo), ''), 'proxima_semana'), p_hoje) x;
        end if;
        if v_foco = 'porque' then
          v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
          if v_ro ->> 'status' in ('nao_achei', 'ambiguo') then
            return jsonb_build_object('ok', false, 'rota', 'os', 'texto', v_ro ->> 'texto',
                                      'pergunta', case when v_ro ->> 'status' = 'ambiguo' then v_ro ->> 'texto' end,
                                      'opcoes', coalesce(v_ro -> 'opcoes', '[]'::jsonb));
          end if;
        end if;
        v_7g := case v_foco when 'como_pensou' then public.agenda_como_pensei(v_7g_de, p_hoje, v_agora)
                            when 'porque' then public._agenda_porque_da_os((v_ro ->> 'id')::uuid, p_hoje, v_agora)
                            else public.agenda_placar(v_7g_de, p_hoje, v_agora) end;
      exception
        when sqlstate '22007' then
          -- o período que não se entende: em ligado, a frase de sempre (como a semana); em sombra, a resposta de antes e o erro no teste
          if v_7g_m = 'ligado' then
            return jsonb_build_object('ok', false, 'rota', 'periodo', 'texto', sqlerrm, 'pergunta', sqlerrm);
          end if;
          v_7g := jsonb_build_object('erro', sqlstate);
        when others then
          if v_7g_m = 'ligado' then
            raise;
          end if;
          v_7g := jsonb_build_object('erro', sqlstate);
      end;
      if v_7g_m <> 'ligado' then
        return v_r || jsonb_build_object('dados', coalesce(v_r -> 'dados', '{}'::jsonb) || jsonb_build_object('teste', v_7g));
      end if;
      return jsonb_build_object('ok', true, 'texto', v_7g ->> 'texto', 'dados', v_7g - 'texto', 'rota', v_foco);
    end;
  end if;
  -- FASE 7g: fim
  -- FASE 6: (P8) o foco aprendizado (spec-fase6 §5.8 e §6.2: o que a agenda aprendeu com o que aconteceu,
  -- _agenda_ver_aprendizado) e a conferência do foco com os 19 — antes da conferência dos 18 da Fase 5, que o foco
  -- aprendizado não alcança. Com login, só administrador e financeiro (42501, antes de ler a config); desligada a leitura, a
  -- frase de sempre.
  if v_foco not in ('tudo', 'livre', 'o_que_fazer', 'riscos', 'material', 'atrasos', 'aprontar', 'decisoes', 'mudancas', 'plano',
                    'ppc', 'diarias', 'marcos', 'comissao', 'equipe', 'compras', 'fornecedores', 'clientes', 'aprendizado') then
    raise exception 'agenda_ver: foco "%" não existe (tudo, livre, o_que_fazer, riscos, material, atrasos, aprontar, decisoes, mudancas, plano, ppc, diarias, marcos, comissao, equipe, compras, fornecedores, clientes ou aprendizado)', p_foco
      using errcode = '22023';
  end if;
  if v_foco = 'aprendizado' then
    if p_hoje is null then
      raise exception 'agenda_ver: sem o dia de hoje' using errcode = '22004';
    end if;
    if auth.uid() is not null and not public.is_admin_or_financial(auth.uid()) then
      raise exception 'O que a agenda aprendeu é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
    if (public._agenda_cfg()).modo_leitura = 'desligado' then
      return jsonb_build_object('ok', false, 'rota', 'desligada', 'desligada', true,
                                'texto', 'A agenda de produção está desligada agora.');
    end if;
    return public._agenda_ver_aprendizado(p_hoje) || jsonb_build_object('rota', 'aprendizado');
  end if;
  -- FASE 6: fim
  -- FASE 5: o foco clientes (a mensagem ao cliente: _agenda_ver_clientes, com ou sem a OS; a OS concluída também) e a
  -- conferência do foco com os 18 — antes da conferência dos 17 da Fase 4, que o foco clientes não alcança.
  if v_foco not in ('tudo', 'livre', 'o_que_fazer', 'riscos', 'material', 'atrasos', 'aprontar', 'decisoes', 'mudancas', 'plano',
                    'ppc', 'diarias', 'marcos', 'comissao', 'equipe', 'compras', 'fornecedores', 'clientes') then
    raise exception 'agenda_ver: foco "%" não existe (tudo, livre, o_que_fazer, riscos, material, atrasos, aprontar, decisoes, mudancas, plano, ppc, diarias, marcos, comissao, equipe, compras, fornecedores ou clientes)', p_foco
      using errcode = '22023';
  end if;
  if v_foco = 'clientes' then
    if p_hoje is null then
      raise exception 'agenda_ver: sem o dia de hoje' using errcode = '22004';
    end if;
    if (public._agenda_cfg()).modo_leitura = 'desligado' then
      return jsonb_build_object('ok', false, 'rota', 'desligada', 'desligada', true,
                                'texto', 'A agenda de produção está desligada agora.');
    end if;
    if nullif(btrim(p_os), '') is not null then
      v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
      if v_ro ->> 'status' in ('nao_achei', 'ambiguo') then
        return jsonb_build_object('ok', false, 'rota', 'os', 'texto', v_ro ->> 'texto',
                                  'pergunta', case when v_ro ->> 'status' = 'ambiguo' then v_ro ->> 'texto' end,
                                  'opcoes', coalesce(v_ro -> 'opcoes', '[]'::jsonb));
      end if;
      return public._agenda_ver_clientes((v_ro ->> 'id')::uuid, p_hoje) || jsonb_build_object('rota', 'clientes_os');
    end if;
    return public._agenda_ver_clientes(null, p_hoje) || jsonb_build_object('rota', 'clientes');
  end if;
  -- FASE 5: fim
  -- FASE 2: os focos decisoes, mudancas e plano
  -- FASE 3: os focos ppc, diarias, marcos, comissao e equipe
  -- FASE 4: os focos compras e fornecedores (a conferência e a mensagem com os 17)
  if v_foco not in ('tudo', 'livre', 'o_que_fazer', 'riscos', 'material', 'atrasos', 'aprontar', 'decisoes', 'mudancas', 'plano',
                    'ppc', 'diarias', 'marcos', 'comissao', 'equipe', 'compras', 'fornecedores') then
    raise exception 'agenda_ver: foco "%" não existe (tudo, livre, o_que_fazer, riscos, material, atrasos, aprontar, decisoes, mudancas, plano, ppc, diarias, marcos, comissao, equipe, compras ou fornecedores)', p_foco
      using errcode = '22023';
  end if;
  -- FASE 4: fim
  if p_hoje is null then
    raise exception 'agenda_ver: sem o dia de hoje' using errcode = '22004';
  end if;
  -- Desligada (agenda_config.modo_leitura), a agenda de produção não responde: o assistente volta à agenda de antes
  -- (my_agenda: tarefas e compromissos do dono). Quem não lê agenda_config continua recebendo erro (nunca "livre").
  if (public._agenda_cfg()).modo_leitura = 'desligado' then
    return jsonb_build_object('ok', false, 'rota', 'desligada', 'desligada', true,
                              'texto', 'A agenda de produção está desligada agora.');
  end if;

  -- Pessoa: "eu" ou o nome. Quem não existe ou é ambíguo volta a frase do resolvedor (nunca um erro cru).
  if nullif(btrim(p_pessoa), '') is not null then
    v_rp := public.agenda_resolver_pessoa(p_pessoa, p_autor, p_hoje);
    if v_rp ->> 'status' <> 'ok' then
      return jsonb_build_object('ok', false, 'rota', 'pessoa', 'texto', v_rp ->> 'texto', 'pergunta', v_rp ->> 'texto',
                                'opcoes', coalesce(v_rp -> 'opcoes', '[]'::jsonb));
    end if;
    v_payee := (v_rp ->> 'payee_id')::uuid;
    v_eh_dono := coalesce((v_rp ->> 'eh_dono')::boolean, false);
  end if;

  -- Período: hoje, amanhã, semana, próxima semana ou o que o dono disse.
  -- FASE 3: a comissão lê o mês ("outubro", "mês passado"), não um período de dias.
  if v_foco = 'comissao' then
    begin
      v_mes := public._agenda_mes_dito(p_periodo, p_hoje);
    exception when sqlstate '22007' then
      return jsonb_build_object('ok', false, 'rota', 'periodo', 'texto', sqlerrm, 'pergunta', sqlerrm);
    end;
  else
    begin
      select x.de, x.ate into v_de, v_ate from public._agenda_periodo(p_periodo, p_hoje) x;
    exception when sqlstate '22007' then
      return jsonb_build_object('ok', false, 'rota', 'periodo', 'texto', sqlerrm, 'pergunta', sqlerrm);
    end;
  end if;

  if coalesce(p_simular_aprovacao, false) and nullif(btrim(p_os), '') is null then
    return jsonb_build_object('ok', false, 'rota', 'ctp',
      'texto', 'Diga qual orçamento: o nome do cliente ou o número (por exemplo, ORÇ-00119).',
      'pergunta', 'Diga qual orçamento: o nome do cliente ou o número (por exemplo, ORÇ-00119).');
  end if;

  if nullif(btrim(p_os), '') is not null then
    v_ro := public.agenda_resolver_os(p_os, p_hoje, coalesce(p_simular_aprovacao, false));
    if v_ro ->> 'status' in ('nao_achei', 'ambiguo') then
      return jsonb_build_object('ok', false, 'rota', 'os', 'texto', v_ro ->> 'texto',
                                'pergunta', case when v_ro ->> 'status' = 'ambiguo' then v_ro ->> 'texto' end,
                                'opcoes', coalesce(v_ro -> 'opcoes', '[]'::jsonb));
    end if;
    if coalesce(p_simular_aprovacao, false) then
      v_rota := 'ctp';
      v_r := public.agenda_ctp((v_ro ->> 'id')::uuid, p_hoje);
    -- FASE 3: os marcos da OS (dentro ou fora da carteira: a concluída e a entregue já saíram dela)
    elsif v_foco = 'marcos' then
      v_rota := 'marcos';
      v_r := public._agenda_ver_marcos((v_ro ->> 'id')::uuid, p_hoje);
    -- FASE 4: as compras e a espera de peça da OS (também fora da carteira: a concluída nos últimos 180 dias); os
    -- fornecedores não são de uma OS
    elsif v_foco = 'compras' then
      v_rota := 'compras_os';
      v_r := public._agenda_ver_compras((v_ro ->> 'id')::uuid, p_hoje);
    elsif v_foco = 'fornecedores' then
      v_rota := 'fornecedores';
      v_r := public._agenda_ver_fornecedores(p_hoje);
    -- FASE 4: fim
    elsif v_ro ->> 'status' = 'fora_da_carteira' then
      v_rota := 'os';
      v_r := jsonb_build_object('ok', true, 'texto', v_ro ->> 'texto', 'dados', jsonb_build_object('numero', v_ro ->> 'numero'));
    elsif v_foco = 'material' then
      v_rota := 'material_os';
      v_r := public.agenda_ver_material((v_ro ->> 'id')::uuid, p_hoje);
    else
      v_rota := 'os';
      v_r := public._agenda_ver_os((v_ro ->> 'id')::uuid, p_hoje);
    end if;
  -- FASE 3: os marcos pedem a OS
  elsif v_foco = 'marcos' then
    return jsonb_build_object('ok', false, 'rota', 'marcos',
      'texto', 'Diga qual OS: o nome do cliente ou o número (por exemplo, OS-00074).',
      'pergunta', 'Diga qual OS: o nome do cliente ou o número (por exemplo, OS-00074).');
  elsif p_simular is not null and jsonb_typeof(p_simular) = 'object' then
    v_rota := 'simular';
    v_r := public.agenda_simular((p_simular ->> 'dias')::numeric, coalesce(p_simular -> 'com_quem', '[]'::jsonb),
                                 nullif(p_simular ->> 'dono', ''), p_autor, p_hoje);
  -- FASE 2: o que espera o dono, o que mudou sozinho e o plano publicado
  elsif v_foco = 'decisoes' then
    v_rota := 'decisoes';
    v_r := public._agenda_ver_decisoes(p_hoje, v_agora);
  elsif v_foco = 'mudancas' then
    v_rota := 'mudancas';
    v_r := public._agenda_ver_mudancas(p_hoje, v_agora);
  elsif v_foco = 'plano' then
    v_rota := 'plano';
    v_r := public._agenda_ver_plano(v_de, v_ate, p_hoje, v_agora);
  -- FASE 3: a semana medida, as diárias da agenda, a comissão do mês e o que a equipe respondeu
  elsif v_foco = 'ppc' then
    v_rota := 'ppc';
    v_r := public._agenda_ver_ppc(v_de, p_hoje);
  elsif v_foco = 'diarias' then
    v_rota := 'diarias';
    v_r := public._agenda_ver_diarias(v_de, v_ate, p_hoje);
  elsif v_foco = 'comissao' then
    v_rota := 'comissao';
    v_r := public._agenda_ver_comissao(v_mes, p_hoje);
  elsif v_foco = 'equipe' then
    v_rota := 'equipe';
    v_r := public._agenda_ver_equipe(p_hoje);
  -- FASE 4: o que comprar e até quando, as notas, o tempo até comprar e a pergunta ao fornecedor; como conto o prazo de
  -- cada fornecedor
  elsif v_foco = 'compras' then
    v_rota := 'compras';
    v_r := public._agenda_ver_compras(null, p_hoje);
  elsif v_foco = 'fornecedores' then
    v_rota := 'fornecedores';
    v_r := public._agenda_ver_fornecedores(p_hoje);
  -- FASE 4: fim
  elsif v_foco = 'o_que_fazer' then
    if v_payee is not null and not v_eh_dono then
      v_rota := 'dia_da_pessoa';
      v_r := public.agenda_dia_da_pessoa(v_payee, coalesce(v_de, p_hoje), p_hoje);
    else
      v_rota := 'o_que_fazer';
      v_r := public.agenda_o_que_fazer(coalesce(v_payee, public._agenda_dono(p_autor)), p_hoje);
    end if;
  elsif v_foco in ('atrasos', 'riscos') then
    v_rota := 'atrasos';
    v_r := public.agenda_atrasos(p_hoje);
  elsif v_foco = 'material' then
    v_rota := 'material';
    v_r := public.agenda_ver_material(null, p_hoje);
  elsif v_foco = 'livre' then
    v_rota := 'livre';
    v_r := public.agenda_semana(null, null, p_hoje);
    -- FASE 3: com a agenda automática ligada, o livre de verdade sai da simulação do motor (fora disso, a projeção)
    if (public._agenda_cfg()).modo_proposta = 'ligado' then
      v_lv := public.agenda_livre_de_verdade(p_hoje, v_agora);
    end if;
    v_r := jsonb_build_object('ok', true,
      'texto', public._agenda_juntar(array[v_r #>> '{dados,textos,resumo}',
                                           case when v_lv ->> 'fonte' = 'simulacao' then v_lv ->> 'texto'
                                                else v_r #>> '{dados,textos,livre}' end],
                                     (select texto_max from public._agenda_cfg())),
      'dados', jsonb_build_object('fila', v_r #> '{dados,fila}', 'livre', v_r #> '{dados,livre}',
                                  'capacidade', v_r #> '{dados,capacidade}',
                                  'livre_de_verdade', coalesce(v_lv, jsonb_build_object('fonte', 'projecao'))));
    -- CORREÇÃO 29/10 (P2): com a agenda automática ligada, o livre é UMA resposta, a do plano (quem ainda pega serviço em cada
    -- uma das próximas semanas, pelo marcado, pelo reservado e pelo teto de cada pessoa; o que ocupa a equipe; o que não ocupa
    -- ninguém até destravar), no lugar da fila em faixa da Fase 1 ("Livre ela não está: … de 3 a 6 semanas", que conta a OS
    -- travada como se ocupasse a equipe) seguida da frase da simulação ("a equipe já está livre")
    if v_lv ->> 'fonte' = 'simulacao' and nullif(v_lv ->> 'texto_completo', '') is not null then
      v_r := jsonb_set(v_r, '{texto}', to_jsonb(v_lv ->> 'texto_completo'));
    end if;
    -- CORREÇÃO 29/10 (P2): fim
  elsif v_foco = 'aprontar' then
    v_rota := 'aprontar';
    v_r := public.agenda_aprontar(p_hoje);
  elsif v_payee is not null and not v_eh_dono and (v_de is null or v_de = v_ate) then
    v_rota := 'dia_da_pessoa';
    v_r := public.agenda_dia_da_pessoa(v_payee, coalesce(v_de, p_hoje), p_hoje);
  elsif v_de is not null and v_de = v_ate then
    v_rota := 'dia';
    v_pn := public._agenda_painel(p_hoje);
    v_max := (v_pn ->> 'texto_max')::int;
    for k in reverse 5 .. 1 loop
      v_l := public._agenda_dia_de(v_pn, v_de, k);
      exit when char_length(public._agenda_juntar(v_l, null)) <= v_max;
    end loop;
    v_r := jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_l, v_max), 'dados', jsonb_build_object('dia', v_de));
  else
    v_rota := 'semana';
    v_r := public.agenda_semana(v_de, v_ate, p_hoje);
    -- FASE 3: com a agenda automática ligada, a frase do livre da semana é a da simulação do motor
    if (public._agenda_cfg()).modo_proposta = 'ligado' and nullif(v_r #>> '{dados,textos,livre}', '') is not null
       and position((v_r #>> '{dados,textos,livre}') in (v_r ->> 'texto')) > 0 then
      v_lv := public.agenda_livre_de_verdade(p_hoje, v_agora);
      if v_lv ->> 'fonte' = 'simulacao' then
        v_r := jsonb_set(v_r, '{texto}', to_jsonb(replace(v_r ->> 'texto', v_r #>> '{dados,textos,livre}', v_lv ->> 'texto')));
        v_r := jsonb_set(v_r, '{dados,livre_de_verdade}', v_lv);
      end if;
    end if;
    -- CORREÇÃO 29/10 (P2): com a agenda automática ligada, a linha do livre (a do plano) vai logo depois do marcado, no lugar
    -- da fila em faixa da Fase 1 (o resumo "Livre ela não está: … de 3 a 6 semanas", que contradizia o livre), e a linha do
    -- livre lá de baixo sai: a semana diz o livre uma vez só
    if (public._agenda_cfg()).modo_proposta = 'ligado' and nullif(v_r #>> '{dados,textos,resumo}', '') is not null
       and position((v_r #>> '{dados,textos,resumo}') in (v_r ->> 'texto')) > 0 then
      v_lv := coalesce(v_lv, public.agenda_livre_de_verdade(p_hoje, v_agora));
      if v_lv ->> 'fonte' = 'simulacao' then
        v_r := jsonb_set(v_r, '{texto}', to_jsonb(replace(replace(v_r ->> 'texto', E'\n' || (v_lv ->> 'texto'), ''),
                                                          v_r #>> '{dados,textos,resumo}', v_lv ->> 'texto')));
        v_r := jsonb_set(v_r, '{dados,livre_de_verdade}', v_lv);
      end if;
    end if;
    -- CORREÇÃO 29/10 (P2): fim
  end if;

  return v_r || jsonb_build_object('rota', v_rota);
end;
$function$;

comment on function public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date) is
  'Agenda de Produção (Fase 1, P4; Fase 2, P5; Fase 3, P6; Fase 4, P6; Fase 5, P5): o despacho ÚNICO da ferramenta agenda_ver e dos comandos sem IA. os + simular_aprovacao → agenda_ctp; FASE 3: os + foco marcos → os 4 marcos (agenda_marcos_da_os, também fora da carteira); foco marcos sem os → pede a OS; FASE 4: os + foco compras → a espera de peça e o material da OS (_agenda_ver_compras, também fora da carteira); foco compras → o que comprar e até quando, as notas sem serviço dito, o tempo até comprar, a pergunta ao fornecedor e o detector em teste (_agenda_ver_compras); foco fornecedores → como conto o prazo de cada fornecedor (_agenda_ver_fornecedores; com ou sem os); os + foco material → agenda_ver_material; os → a visão da OS; simular {dias, com_quem, dono} → agenda_simular; FASE 2: foco decisoes → as decisões numeradas (agenda_decisoes_abertas; FASE 3: a da diária com as opções e as palavras) e o que mais a agenda quer saber; mudancas → o que mudou sozinho desde ontem com *desfaz*; plano → o publicado do período dia a dia (sombra: "Em teste"); FASE 3: ppc → agenda_ppc da semana do período; diarias → as diárias que a agenda lançou e as perguntas abertas; comissao → comissao_resumo_do_mes do mês dito em periodo ("outubro", "mês passado"; só a conta, nada é pago); equipe → o que a equipe respondeu hoje e no próximo dia útil; foco o_que_fazer → agenda_o_que_fazer (pessoa que não é o dono: o dia dela); atrasos/riscos → agenda_atrasos; material → agenda_ver_material(null); livre → resumo + livre de agenda_semana (FASE 3: com modo_proposta ligado, o livre de verdade pela simulação do motor, agenda_livre_de_verdade); aprontar → agenda_aprontar; pessoa (não o dono) + 1 dia → agenda_dia_da_pessoa; hoje/amanhã → o dia + o bloco 2 resumido; resto → agenda_semana (em ''ligado'' o marcado é o plano; FASE 3: e a frase do livre é a da simulação). periodo: hoje, amanha, semana, proxima_semana ou o que o dono disse. Referência que não existe (OS, pessoa, data, mês) → {ok:false, texto:"Não encontrei …"/a pergunta}; FASE 5: foco clientes (com ou sem os; a OS concluída também) → as mensagens ao cliente (_agenda_ver_clientes); foco fora da lista (os 18) lança 22023. Devolve {ok, texto, dados, rota}. FASE 6 (P8): foco aprendizado → o que a agenda aprendeu com o que aconteceu (_agenda_ver_aprendizado: o fator por tipo de OS, a presença do dono, os fornecedores, a capacidade do dono, o R$ por diária, o cliente e a revisão da carga, com o n de cada um, e as medidas); com login, só administrador e financeiro (42501). A lista dos focos passa a 19. CORREÇÃO 29/10 (P2): com a agenda automática ligada, o foco livre é UMA resposta, a do plano (agenda_livre_de_verdade.texto_completo: quem ainda pega serviço em cada uma das 3 semanas, pelo marcado, pelo reservado e pelo teto de cada pessoa; o que ocupa a equipe; o que não ocupa ninguém até destravar), sem a fila em faixa da Fase 1; na semana, a linha do livre (agenda_livre_de_verdade.texto) vai logo depois do marcado, no lugar da fila em faixa, e a linha do livre lá de baixo sai; simular (agenda_simular) em ligado é o encaixe do motor. Fora de ligado, tudo como antes. FASE 7 (7a P7, spec §6.2): foco gestor → o que o gestor da agenda marcou (ligado) ou marcaria (em teste) e por quê, o que perguntou antes de marcar, o que fica de fora, as compras da semana, os orçamentos que caberiam e como ele conta (_agenda_ver_gestor); com login, só administrador e financeiro (42501); desligada a leitura, a frase de sempre. A lista dos focos passa a 20. FASE 7c (P6, spec §5.6, R5.6): foco habilidades → _agenda_ver_habilidades (quem faz o quê na equipe, o que cada OS pede, o responsável, o que a agenda teria mudado em teste e as medidas; com os, só o bloco da OS), antes da conferência dos 19 (o foco que não existe continua com a mensagem dos 19, como o gestor); sem p_hoje, 22004; com login, só administrador e financeiro (42501); a leitura desligada, a frase de sempre; a OS que não existe ou é ambígua, a frase do resolvedor. FASE 7d (P8; §5.8, R6.3-12): o foco locais (_agenda_ver_locais): onde é cada serviço, o que combinar e as regras dos locais; com os, só a OS. Sem p_hoje, 22004; com login, só administrador e financeiro (42501); desligada a leitura, a frase de sempre. Fora da conferência dos 19. FASE 7g (P7): os focos como_pensou (a semana dita, sem ela a que vem: agenda_como_pensei), porque (com os: _agenda_porque_da_os; sem os, a pergunta "De qual serviço?") e placar (a semana dita, sem ela a da janela: agenda_placar), antes da conferência dos 19 (a mensagem dos 19 não muda). Com login, só administrador e financeiro (42501); sem p_hoje, 22004; desligada a leitura, a frase de sempre. Com modo_explicar (no placar, modo_placar) desligado: como_pensou é a leitura de antes da semana (a rota semana), porque com os é a leitura de antes da OS (a rota os) e placar diz que ainda não está ligado e manda a *como foi a semana*; em sombra, essa resposta e o novo em dados.teste ({erro} se ele falhar); ligado, o texto da função da 7g, rota = o foco.';

-- ── 2. A Semana: quem marcou e a linha do porquê em cada bloco ──────────────────────────────────────

create or replace function public.agenda_tela_semana(p_de date default null, p_hoje date default public._hoje_brt(),
                                                     p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_uid    uuid := auth.uid();
  v_seg    date;
  v_prop   uuid;
  v_teste  boolean := cf.modo_proposta = 'sombra';
  v_dias   jsonb;
  v_comp   int;
  v_livre  numeric;
  v_ppc    numeric;
  v_sem    jsonb;
  v_den    int;
  v_lv     jsonb;
  v_titulo text;
  v_dec    jsonb;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_tela_semana: sem o dia ou a hora de agora' using errcode = '22004';
  end if;
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
  end if;
  v_seg := coalesce(p_de, p_hoje) - (extract(isodow from coalesce(p_de, p_hoje))::int - 1);

  if cf.modo_proposta = 'desligado' then
    return jsonb_build_object('modo', cf.modo_proposta, 'em_teste', false, 'de', v_seg, 'ate', v_seg + 5,
      'titulo', 'A agenda automática está desligada: não há plano publicado.',
      'resumo', null, 'comprometido_pct', null, 'livre_diarias', null, 'ppc_anterior', null, 'livre_de_verdade', null,
      'dias', '[]'::jsonb, 'mudancas', '[]'::jsonb, 'decisoes', '[]'::jsonb, 'como_responder', null);
  end if;
  -- Em sombra nada é publicado: os blocos são os da última semana que a sombra montou para estes dias.
  if v_teste then
    select pr.id into v_prop from public.agenda_propostas pr
     where pr.modo = 'sombra' and pr.escopo = 'semana' and pr.periodo && daterange(v_seg, v_seg + 6, '[]')
     order by pr.criada_em desc, pr.id desc limit 1;
  end if;

  with
  a0 as (
    select x.* from public.agenda_alocacoes x
     where (not v_teste and x.estado in ('publicada', 'fixada'))
        or (v_prop is not null and x.estado = 'proposta' and x.proposta_id = v_prop)
  ),
  na_semana as (select distinct x.service_order_id from a0 x where x.dia between v_seg and v_seg + 6),
  -- o "dia n de N" pela OS inteira (o dia em que nada foi cumprido não conta, como em v_agenda_dia)
  dias_os as (
    select d.service_order_id, d.dia,
           (row_number() over (partition by d.service_order_id order by d.dia))::int as dia_n,
           (count(*) over (partition by d.service_order_id))::int as dias_total
      from (select x.service_order_id, x.dia from a0 x join na_semana s using (service_order_id)
             where x.tipo <> 'reserva' group by x.service_order_id, x.dia
            having bool_or(x.resultado is distinct from 'nao_cumprido')) d
  ),
  a as (select x.* from a0 x where x.dia between v_seg and v_seg + 6),
  pp as (
    select a.dia, a.service_order_id, a.payee_id,
           array_agg(distinct a.turno order by a.turno) as turnos,
           case when bool_or(a.presenca = 'turno') then 'turno'
                when bool_or(a.presenca = 'abertura') and bool_or(a.presenca = 'fechamento') then 'abre_e_fecha'
                when bool_or(a.presenca = 'abertura') then 'abertura'
                else 'fechamento' end as presenca,
           min(lower(a.periodo)) as ini
      from a group by a.dia, a.service_order_id, a.payee_id
  ),
  pe as (
    select pp.dia, pp.service_order_id,
           jsonb_agg(jsonb_build_object('payee_id', pp.payee_id, 'nome', x.j ->> 'nome',
                                        'eh_dono', coalesce((x.j ->> 'eh_dono')::boolean, false),
                                        'turnos', to_jsonb(pp.turnos), 'presenca', pp.presenca)
                     order by coalesce((x.j ->> 'eh_dono')::boolean, false) desc, pp.ini, x.j ->> 'nome', pp.payee_id) as pessoas
      from pp cross join lateral (select public._agenda_pessoa(pp.payee_id) as j) x
     group by pp.dia, pp.service_order_id
  ),
  g as (
    select a.dia, a.service_order_id,
           bool_and(a.tipo = 'reserva') as reserva,
           case when bool_and(a.tipo = 'reserva') then 'reserva' else min(a.tipo) filter (where a.tipo <> 'reserva') end as tipo,
           min(a.reserva_de) filter (where a.tipo = 'reserva') as reserva_de,
           min(a.condicao) filter (where a.tipo = 'reserva') as condicao,
           min(lower(a.periodo)) as ini,
           bool_or(a.estado = 'fixada') as fixada,
           case when coalesce(bool_and(a.resultado is null) filter (where a.tipo <> 'reserva'), true) then null
                when bool_or(a.resultado = 'cumprido') then 'cumprido'
                when bool_or(a.resultado = 'parcial') then 'parcial'
                when bool_or(a.resultado = 'sem_registro') then 'sem_registro'
                else 'nao_cumprido' end as resultado
      from a group by a.dia, a.service_order_id
  ),
  blocos as (
    select g.dia, jsonb_agg(jsonb_build_object(
             'os', g.service_order_id, 'numero', so.service_order_number, 'cliente', public._agenda_nome_curto(cl.name),
             'bem', v.name, 'local', coalesce(m.name, nullif(btrim(cl.city), '')),
             'hora', to_char(g.ini at time zone 'America/Sao_Paulo', 'HH24:MI'),
             'pessoas_texto', nullif(public._agenda_pessoas_do_dia(pe.pessoas), ''),
             'dia_n', d.dia_n, 'dias_total', d.dias_total,
             'dia_texto', case when coalesce(d.dias_total, 1) > 1 and d.dia_n is not null
                               then format('dia %s de %s', d.dia_n, d.dias_total) end,
             'confirmado_cliente', coalesce((so.client_confirmed_for at time zone 'America/Sao_Paulo')::date = g.dia, false),
             'reserva', g.reserva,
             'reserva_texto', case when g.reserva then case when g.reserva_de = 'patio' then 'Reserva no pátio, a confirmar'
                                                            else 'Reserva, a confirmar' end end,
             'condicao', g.condicao, 'tipo', g.tipo, 'fixada', g.fixada, 'resultado', g.resultado,
             'resultado_texto', case g.resultado when 'cumprido' then 'feito' when 'parcial' then 'feito em parte'
                                                 when 'sem_registro' then 'sem registro' when 'nao_cumprido' then 'não aconteceu' end)
             order by g.ini, so.service_order_number, g.service_order_id) as blocos
      from g
      join public.service_orders so on so.id = g.service_order_id
      left join public.clients cl on cl.id = so.client_id
      left join public.vessels v on v.id = so.vessel_id
      left join public.marinas m on m.id = so.marina_id
      left join pe on pe.dia = g.dia and pe.service_order_id = g.service_order_id
      left join dias_os d on d.service_order_id = g.service_order_id and d.dia = g.dia
     group by g.dia
  ),
  cap as (select k.* from public.agenda_capacidade(v_seg, v_seg + 6, p_hoje) k),
  usado as (select a.payee_id, a.dia, a.turno from a group by a.payee_id, a.dia, a.turno),
  -- por pessoa e dia: os meios-dias esperados (a soma das frequências, ao meio-dia inteiro), os usados (qualquer presença,
  -- como a grade do motor) e os livres (esperados e sem nada no plano)
  pes as (
    select k.dia, k.payee_id, k.pessoa, k.eh_dono,
           round(sum(k.meios_esperados))::int as esp,
           count(u.turno)::int as usados,
           array_remove(array_agg(case when k.situacao = 'livre' and k.meios_esperados > 0 and u.turno is null then k.turno end
                                  order by k.turno = 'tarde'), null) as livres,
           coalesce(sum(k.meios_esperados) filter (where k.situacao = 'livre' and u.turno is null), 0) as livre_esp
      from cap k
      left join usado u on u.payee_id = k.payee_id and u.dia = k.dia and u.turno = k.turno
     group by k.dia, k.payee_id, k.pessoa, k.eh_dono
  ),
  dia as (
    select d::date as dia, b.blocos from generate_series(v_seg, v_seg + 5, interval '1 day') d
      left join blocos b on b.dia = d::date
     where extract(isodow from d) between 1 and 5 or b.blocos is not null or cf.sabado_util
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'dia', dia.dia, 'rotulo', upper(public._dia_curto(dia.dia)), 'hoje', dia.dia = p_hoje,
           'feriado', public.agenda_feriado(dia.dia),
           'pessoas', coalesce((select jsonb_agg(jsonb_build_object(
                         'payee_id', x.payee_id, 'nome', x.pessoa, 'eh_dono', x.eh_dono,
                         'meios_usados', x.usados, 'meios_esperados', x.esp,
                         'pct', case when x.esp > 0 then round(100 * x.usados::numeric / x.esp)::int end,
                         'cor', case when x.esp = 0 then 'vermelho'
                                     when x.usados::numeric / x.esp <= cf.carga_max then 'verde'
                                     when x.usados <= x.esp then 'ambar'
                                     else 'vermelho' end,
                         'texto', format('%s %s/%s', x.pessoa, x.usados, x.esp))
                       order by x.eh_dono desc, x.pessoa, x.payee_id)
                  from pes x where x.dia = dia.dia and (x.esp > 0 or x.usados > 0)), '[]'::jsonb),
           'blocos', coalesce(dia.blocos, '[]'::jsonb),
           'livre_texto', (select 'livre: ' || string_agg(case when x.eh_dono then 'você' else x.pessoa end || ' '
                                    || case when cardinality(x.livres) = 2 then 'dia todo'
                                            when x.livres[1] = 'manha' then 'manhã' else 'tarde' end,
                                    ', ' order by x.eh_dono desc, x.pessoa, x.payee_id)
                             from pes x where x.dia = dia.dia and dia.dia >= p_hoje and cardinality(x.livres) > 0))
           order by dia.dia), '[]'::jsonb),
         (select round(100 * sum(x.usados)::numeric / nullif(sum(x.esp), 0))::int from pes x
           where public.agenda_dia_util(x.dia)),
         (select trim_scale(round(sum(x.livre_esp)) / 2) from pes x where x.dia >= p_hoje and public.agenda_dia_util(x.dia))
    into v_dias, v_comp, v_livre
    from dia;

  -- FASE 7g: (7g P7; §5.7, R9.5-19, R9.12-9 e 10) com modo_porque ligado e o plano publicado (não a sombra do motor, que não tem alocação vigente), cada bloco
  -- ganha quem (gestor | dono: da 1ª alocação vigente do bloco no dia — o compromisso antes da reserva, de turno, a manhã, o técnico antes de você — e da ação
  -- que a criou, _agenda_quem_marcou), quem_texto ("marcado pelo gestor" / "marcado por você"; na reserva, "reservado pelo gestor" / "reservado por você": a
  -- reserva não é marcação) e porque_texto (_agenda_porque_linha dessa alocação: a fonte da duração e as suposições, até c_linha letras). Bloco sem alocação
  -- vigente: as 3 nulas. Fora de ligado, as chaves ficam ausentes: a tela de antes, byte a byte. Uma falha aqui não derruba a tela (os blocos de antes).
  if cf.modo_porque = 'ligado' and not v_teste then
    declare
      c_linha   constant int := 120;   -- estrutural: o teto da linha do porquê no bloco (§5.7)
      v_7g_dono uuid := public._agenda_dono(null);
    begin
      select coalesce(jsonb_agg(d.v || jsonb_build_object('blocos', coalesce((
               select jsonb_agg(b.v || jsonb_build_object(
                        'quem', q.quem,
                        'quem_texto', case when q.quem is null then null
                                           when coalesce((b.v ->> 'reserva')::boolean, false)
                                             then case when q.quem = 'dono' then 'reservado por você' else 'reservado pelo gestor' end
                                           when q.quem = 'dono' then 'marcado por você' else 'marcado pelo gestor' end,
                        'porque_texto', case when q.id is not null
                                             then public._agenda_corta(public._agenda_porque_linha((b.v ->> 'os')::uuid, jsonb_build_array(q.id::text), p_hoje),
                                                                       c_linha) end)
                      order by b.o)
                 from jsonb_array_elements(d.v -> 'blocos') with ordinality b(v, o)
                 left join lateral (
                   select x.id, public._agenda_quem_marcou(ac.origem, x.origem) as quem
                     from public.agenda_alocacoes x
                     left join public.agenda_acoes ac on ac.id = x.acao_id
                    where x.service_order_id = (b.v ->> 'os')::uuid and x.dia = (d.v ->> 'dia')::date and x.estado in ('publicada', 'fixada')
                    order by x.tipo = 'reserva', x.presenca <> 'turno', x.turno = 'tarde', x.payee_id is not distinct from v_7g_dono, x.id
                    limit 1) q on true), '[]'::jsonb))
             order by d.o), '[]'::jsonb)
        into v_dias
        from jsonb_array_elements(v_dias) with ordinality d(v, o);
    exception when others then
      null;   -- a tela de antes: os blocos sem as 3 chaves
    end;
  end if;
  -- FASE 7g: fim
  v_sem := public.agenda_ppc(v_seg - 7, p_hoje);
  v_ppc := (v_sem ->> 'ppc')::numeric;
  v_den := (v_sem ->> 'cumpridos')::int + jsonb_array_length(coalesce(v_sem -> 'nao_cumpridos', '[]'::jsonb));
  if cf.modo_proposta = 'ligado' then
    v_lv := public.agenda_livre_de_verdade(p_hoje, p_agora);
  end if;
  v_titulo := case
    when v_teste and v_prop is null then 'Em teste: ainda não montei esta semana.'
    when v_teste then 'Em teste: eu montaria assim — ' || public._agenda_titulo_da_semana(v_seg) || '.'
    else public._agenda_titulo_da_semana(v_seg) end;

  select coalesce(jsonb_agg(jsonb_build_object(
           'pergunta_id', e ->> 'id', 'n', (e ->> 'n')::int, 'tipo', e ->> 'tipo',
           'texto', format('Decisão %s: %s', e ->> 'n',
                           case when e ->> 'tipo' = 'diaria' then public._agenda_texto_da_diaria((e ->> 'id')::uuid)
                                else e ->> 'texto' end))
           order by (e ->> 'n')::int), '[]'::jsonb)
    into v_dec
    from jsonb_array_elements(public.agenda_decisoes_abertas(p_agora)) e;

  return jsonb_build_object(
    'modo', cf.modo_proposta, 'em_teste', v_teste, 'de', v_seg, 'ate', v_seg + 5, 'titulo', v_titulo,
    'comprometido_pct', v_comp, 'livre_diarias', v_livre,
    'ppc_anterior', case when v_ppc is not null then round(100 * v_ppc)::int end,
    'resumo', concat_ws(' · ',
                case when v_comp is not null then format('comprometido %s%%', v_comp) end,
                case when v_livre is not null then 'livre ' || replace(trim_scale(v_livre)::text, '.', ',')
                                                   || case when v_livre = 1 then ' diária' else ' diárias' end end,
                -- revisão da Fase 3: sem o jargão "PPC" — "semana passada: 5 de 6 dias cumpridos" (sem dia conferido, nada)
                case when v_den > 0
                     then format('semana passada: %s de %s %s', (v_sem ->> 'cumpridos')::int,
                                 public._agenda_plural(v_den, 'dia', 'dias'),
                                 case when (v_sem ->> 'cumpridos')::int = 1 then 'cumprido' else 'cumpridos' end) end),
    'livre_de_verdade', case when v_lv ->> 'fonte' = 'simulacao' then v_lv ->> 'texto' end,
    'dias', v_dias,
    'mudancas', public._agenda_tela_mudancas(p_hoje, p_agora),
    'decisoes', v_dec,
    'como_responder', case when jsonb_array_length(v_dec) > 0
                           then 'Responda no WhatsApp: diga a decisão e a opção (por exemplo, "na decisão 1, a opção 2").' end);
end;
$function$;

comment on function public.agenda_tela_semana(date, date, timestamptz) is
  'Agenda de Produção (Fase 3, P7a): a tela Agenda › Semana da semana ISO de p_de (sem ele, a de p_hoje), seg a sex (o sábado só com plano ou sabado_util) — {modo, em_teste, de, ate, titulo ("Semana de 03 a 06/11 (seg 02 é Finados)"; em sombra "Em teste: eu montaria assim — …", com os blocos da última semana montada pela sombra), comprometido_pct, livre_diarias, ppc_anterior, resumo ("comprometido 54% · livre 5,5 diárias · semana passada: 5 de 6 dias cumpridos"; sem dia conferido na semana passada, sem essa parte), livre_de_verdade (a simulação, só em ligado), dias:[{dia, rotulo "TER 03/11", hoje, feriado, pessoas:[{payee_id, nome, eh_dono, meios_usados, meios_esperados, pct, cor (verde ≤ carga_max, ambar ≤ 100%, vermelho acima; esperado zero com uso = vermelho), texto "Roberto 2/2"}], blocos:[{os, numero, cliente, bem, local, hora, pessoas_texto, dia_n, dias_total, dia_texto "dia 1 de 3", confirmado_cliente, reserva, reserva_texto "Reserva, a confirmar", condicao, tipo, fixada, resultado, resultado_texto}], livre_texto "livre: Roberto tarde"}], mudancas (_agenda_tela_mudancas), decisoes:[{pergunta_id, n, tipo, texto}], como_responder}. Desligado: só o título. Administrador e financeiro (com login) ou service_role; senão 42501. FASE 7g (P7): com modo_porque ligado e o plano publicado, cada bloco ganha quem (gestor | dono, da 1ª alocação vigente do bloco no dia e da ação que a criou), quem_texto ("marcado pelo gestor", "marcado por você"; na reserva, "reservado pelo gestor", "reservado por você") e porque_texto (_agenda_porque_linha, até 120 letras); bloco sem alocação vigente, as 3 nulas. Fora de ligado (e na sombra do motor), as chaves ficam ausentes.';

-- ── 3. O cartão da OS: "Por que assim" ──────────────────────────────────────────────────────────────

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
  -- FASE 6: (P8) a linha do que as OS parecidas levam (agenda_fator_de_campo) e a presença do dono com a aprendida
  v_campo text;
  v_pd    jsonb;
  -- FASE 6: fim
  -- FASE 7b: (7b P5) o bloco "Equipe" do cartão: o molde, a dupla da OS, a dupla no plano, quem está na grade, a classe, o "fora" da
  -- última montagem, as partes do texto
  v_7b_modo  text;
  v_7b_eq    jsonb;
  v_7b_m     jsonb;
  v_7b_d     jsonb;
  v_7b_pl    jsonb;
  v_7b_tec   text[];
  v_7b_tf    text;
  v_7b_cl    jsonb;
  v_7b_fora  jsonb;
  v_7b_pes   int;
  v_7b_txt   text;
  v_7b_esp   boolean := false;
  v_7b_fi    jsonb;
  v_7b_ff    jsonb;
  v_7b_ft    jsonb;
  v_7b_partes text[] := '{}';
  v_7b_nomes text[];
  -- FASE 7b: fim
  -- FASE 7d: (7d P8) o bloco "Local" do cartão
  v_7d_local jsonb;
  -- FASE 7d: fim
  -- FASE 7e: (7e P7) as 2 linhas novas da duração: a estimativa com o viés e o prazo real (só para o dono)
  v_7e_c    public.agenda_config;
  v_7e_m    jsonb;
  v_7e_sug  jsonb;
  v_7e_vi   numeric;
  v_7e_ch   text;
  v_7e_hj   numeric;
  v_7e_dd   numeric;
  v_7e_est  text;
  v_7e_pr   jsonb;
  v_7e_prom text;
  v_7e_dur  jsonb;
  v_7e_gs   text;
  v_7e_hs   numeric;
  -- FASE 7e: fim
  -- FASE 7g: (7g P7) a chave porque do cartão
  v_7g_pq jsonb;
  -- FASE 7g: fim
begin
  if p_os is null or p_hoje is null then
    raise exception 'os_plano_da_os: sem a OS ou o dia de hoje' using errcode = '22004';
  end if;
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'O plano da OS é com o administrador.' using errcode = '42501';
  end if;
  -- CORREÇÃO FASE 6: (C2) regressão B8: sem o "sub" no JWT (auth.uid() nulo) só passa o service_role, ou nenhum JWT (o banco
  -- por dentro: a rodada, o fechamento, os testes) — como agenda_fator_de_campo; o authenticated sem "sub" recebe 42501 (antes
  -- o portão de cima não rodava, e ele lia tudo). Os JWT do Supabase sempre têm "sub": hoje não é explorável.
  if v_uid is null then
    declare
      v_papel text;
    begin
      begin
        v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
      exception when others then
        v_papel := 'invalido';
      end;
      if v_papel not in ('', 'service_role') then
        raise exception 'O plano da OS é com o administrador.' using errcode = '42501';
      end if;
    end;
  end if;
  -- CORREÇÃO FASE 6: fim
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
  -- FASE 6: (P8) (spec-fase6 §5.8) duracao.campo: a linha do fator de campo da classe desta OS ("Em teste: as OS de energia
  -- em motorhome levam até 1,7× o combinado (7 OS); …") — só com o aprendizado fora de desligado e na OS que ainda vai ser
  -- feita (a concluída, a faturada e a cancelada não têm o que perguntar). O 42501 de quem não vê o aprendizado vira nulo.
  if (public._agenda_cfg()).modo_aprendizado <> 'desligado' and so.status not in ('completed', 'invoiced', 'cancelled') then
    begin
      v_campo := public.agenda_fator_de_campo(p_os, p_hoje) ->> 'texto';
    exception when insufficient_privilege then
      v_campo := null;
    end;
  end if;
  -- presenca_dono com a aprendida (os_presenca_do_dono, fonte aprendida): o texto diz de onde veio — o de antes diria
  -- "(você disse)". A chave presenca_dono abaixo (a de antes) fica, e esta, que vem depois no mesmo objeto, vale; sem a
  -- aprendida, o texto é o de sempre.
  v_pd := jsonb_build_object(
    'valor', v_pres ->> 'presenca', 'pela_regra', coalesce(v_pres ->> 'fonte', 'regra') = 'regra',
    'aprendida', case when v_pres ->> 'fonte' = 'aprendida' then v_pres ->> 'motivo' end,
    'texto', case v_pres ->> 'presenca' when 'abre_e_fecha' then 'Você abre e fecha'
                                        when 'sempre' then 'Você fica o tempo todo'
                                        when 'nunca' then 'Você não precisa ir'
                                        else 'Sem regra' end
             || case when v_pres ->> 'fonte' = 'aprendida' then ' (pelo que medi: ' || (v_pres ->> 'motivo') || ')'
                     when coalesce(v_pres ->> 'fonte', 'regra') <> 'regra' then ' (você disse)'
                     when coalesce(v_pres ->> 'motivo', 'padrão') = 'padrão' then ' (pela regra)'
                     else ' (pela regra: ' || (v_pres ->> 'motivo') || ')' end);
  -- FASE 6: fim
  -- CORREÇÃO FASE 6: (C1) item 3: a presença guardada na 1ª publicação diz que é o que a agenda mediu quando planejou
  if coalesce((v_pres ->> 'guardada')::boolean, false) then
    v_pd := v_pd || jsonb_build_object('texto', replace(v_pd ->> 'texto', ' (pelo que medi: ', ' (pelo que medi quando planejei: '));
  end if;
  -- CORREÇÃO FASE 6: fim

  -- FASE 7b: (7b P5, §5.4, §6.4, R4.3, R4.4) o bloco "Equipe" do cartão — só com modo_dupla fora de desligado e na OS que ainda vai
  -- ser feita (desligado, ou a OS concluída, faturada ou cancelada: nulo, e o resto do cartão é o de antes). Quantas pessoas o serviço
  -- pede (pessoas: as da sugestão, ou 2 na dupla o tempo todo; com a equipe dita, as que você disse), a dupla da OS (_agenda_dupla_da_os:
  -- a que a tarefa pede, suposição minha, ou a que você disse), as notas (o espaço apertado), os meios-dias do plano em que a dupla
  -- está sem a 2ª pessoa (falta, de _agenda_dupla_no_plano), a dupla dita que espera a 2ª pessoa (espera: a classe 4 dupla, ou o
  -- "fora" dupla da última montagem que citou a OS, sem compromisso dela de hoje em diante) e o texto: "1 pessoa; nos 2 primeiros
  -- meios-dias (ter 10/11) a troca do banco de baterias pede 2 — falta a 2ª pessoa (só Alex está na equipe).", "Em dupla o tempo todo
  -- (você disse) — espero a 2ª pessoa: só Alex está na equipe.", em teste "Em teste: eu marcaria 1 pessoa, em dupla nos 2 primeiros
  -- meios-dias (troca do banco de baterias). Hoje marco 1 pessoa e ponho a 2ª nesses meios-dias quando alguém está livre."
  v_7b_modo := (public._agenda_cfg()).modo_dupla;
  if v_7b_modo <> 'desligado' and so.status not in ('completed', 'invoiced', 'cancelled') then
    v_7b_m := public.agenda_meios_da_os(p_os, p_hoje);
    v_7b_d := public._agenda_dupla_da_os(p_os);
    v_7b_pl := public._agenda_dupla_no_plano(p_os, p_hoje);
    v_7b_tec := public._agenda_tecnicos_da_grade(p_hoje);
    v_7b_tf := case when cardinality(v_7b_tec) >= 2 then 'ninguém mais está livre nesses meios-dias'
                    else public._agenda_tecnicos_frase(v_7b_tec) end;
    v_7b_pes := case when coalesce((v_7b_m ->> 'equipe_dita')::boolean, false)
                       then greatest(coalesce((v_7b_m #>> '{por_turno,manha,desejado}')::int, 0),
                                     coalesce((v_7b_m #>> '{por_turno,tarde,desejado}')::int, 0))
                     when coalesce((v_7b_d ->> 'todos')::boolean, false) then 2
                     else coalesce((v_7b_m ->> 'pessoas_sugeridas')::int, 1) end;
    v_7b_fi := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(coalesce(v_7b_pl -> 'faltam', '[]'::jsonb)) with ordinality t(e, o)
                         where e ->> 'onde' = 'inicio'), '[]'::jsonb);
    v_7b_ff := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(coalesce(v_7b_pl -> 'faltam', '[]'::jsonb)) with ordinality t(e, o)
                         where e ->> 'onde' = 'fim'), '[]'::jsonb);
    v_7b_ft := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(coalesce(v_7b_pl -> 'faltam', '[]'::jsonb)) with ordinality t(e, o)
                         where e ->> 'onde' = 'todos'), '[]'::jsonb);
    -- a dupla dita que espera a 2ª pessoa: a classe 4 dupla (a grade com menos técnicos do que ela pede), ou a que só passou pela régua
    -- com quem vem sob demanda e ficou no "fora" dupla da última montagem que citou a OS (R4.3(c)), sem compromisso dela de hoje em diante
    if v_7b_d ->> 'fonte' = 'dono' and not coalesce((v_7b_m ->> 'equipe_dita')::boolean, false) then
      v_7b_cl := public._agenda_classe_da_os(p, v_7b_m, p_hoje,
                   exists (select 1 from public.agenda_alocacoes a where a.service_order_id = p_os and a.estado = 'fixada' and a.dia >= p_hoje),
                   false);
      if (v_7b_cl ->> 'classe')::int = 4 and v_7b_cl ->> 'motivo' = 'dupla' then
        v_7b_esp := true;
        v_7b_txt := rtrim(v_7b_d ->> 'texto', '.') || ' — espero a 2ª pessoa: ' || public._agenda_tecnicos_frase(v_7b_tec) || '.';
      elsif not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = p_os and a.estado in ('publicada', 'fixada')
                          and a.tipo <> 'reserva' and a.dia >= p_hoje) then
        select x.f into v_7b_fora
          from (select pr.criada_em, pr.id, (select f from jsonb_array_elements(coalesce(pr.fora, '[]'::jsonb)) f
                                              where f ->> 'os' = p_os::text limit 1) as f,
                       exists (select 1 from jsonb_array_elements(coalesce(pr.itens, '[]'::jsonb)) i where i ->> 'os' = p_os::text) as no_plano
                  from public.agenda_propostas pr
                 where (pr.criada_em at time zone 'America/Sao_Paulo')::date <= p_hoje) x
         where x.f is not null or x.no_plano
         order by x.criada_em desc, x.id desc limit 1;
        if v_7b_fora ->> 'motivo' = 'dupla' then
          v_7b_esp := true;
          v_7b_txt := rtrim(v_7b_d ->> 'texto', '.') || ' — espero a 2ª pessoa: '
                      || case when position('): ' in v_7b_fora ->> 'texto') > 0
                              then substr(v_7b_fora ->> 'texto', position('): ' in v_7b_fora ->> 'texto') + 3)
                              else v_7b_fora ->> 'texto' end;
        end if;
      end if;
    end if;
    if v_7b_txt is null then
      if coalesce((v_7b_m ->> 'equipe_dita')::boolean, false) then
        v_7b_nomes := array(select y.nome from (select distinct on (x ->> 'payee_id') x ->> 'payee_id' as id, x ->> 'nome' as nome
                                                 from (select jsonb_array_elements(coalesce(v_7b_m #> '{por_turno,manha,pessoas}', '[]'::jsonb)) x
                                                       union all
                                                       select jsonb_array_elements(coalesce(v_7b_m #> '{por_turno,tarde,pessoas}', '[]'::jsonb))) z
                                                order by x ->> 'payee_id') y order by y.nome);
        v_7b_txt := format('Quem vai: %s (você disse).',
                           public._agenda_lista(case when v_7b_m ->> 'presenca' = 'equipe' then array['você'] else '{}'::text[] end || v_7b_nomes));
      elsif v_7b_d ->> 'fonte' = 'dono' then
        v_7b_txt := case when jsonb_array_length(coalesce(v_7b_pl -> 'faltam', '[]'::jsonb)) = 0 then v_7b_d ->> 'texto'
                         else rtrim(v_7b_d ->> 'texto', '.') || ' — falta a 2ª pessoa em '
                              || public._agenda_dias_texto(array(select distinct (e ->> 'dia')::date from jsonb_array_elements(v_7b_pl -> 'faltam') e))
                              || ' (' || v_7b_tf || ').' end;
      elsif v_7b_modo = 'sombra' and v_7b_d ->> 'fonte' = 'regra' then
        v_7b_txt := replace(replace(v_7b_d ->> 'texto', ' — suposição minha.', ''), '1 pessoa; ', '1 pessoa, ');
        v_7b_txt := 'Em teste: eu marcaria ' || lower(left(v_7b_txt, 1)) || substr(v_7b_txt, 2) || '.'
                    || case when coalesce((v_7b_m ->> 'pessoas_sugeridas')::int, 1) >= 2 then ' Hoje marco 2 pessoas.'
                            else ' Hoje marco 1 pessoa e ponho a 2ª nesses meios-dias quando alguém está livre.' end;
      elsif v_7b_modo = 'sombra' and coalesce((v_7b_m ->> 'pessoas_sugeridas')::int, 1) >= 2 then
        v_7b_txt := 'Em teste: eu marcaria 1 pessoa. Hoje marco 2 pessoas.';
      elsif v_7b_d ->> 'fonte' = 'regra' and jsonb_array_length(v_7b_ft) > 0 then
        v_7b_txt := format('1 pessoa; o serviço todo pede 2 (%s) — falta a 2ª pessoa em %s (%s).',
                           coalesce((select e ->> 'rotulo' from jsonb_array_elements(v_7b_d -> 'motivos') e where e ->> 'onde' = 'todos' limit 1),
                                    'o orçamento previu 2 técnicos'),
                           public._agenda_plural(jsonb_array_length(v_7b_ft), 'meio-dia', 'meios-dias'), v_7b_tf);
      elsif v_7b_d ->> 'fonte' = 'regra' and jsonb_array_length(v_7b_fi) + jsonb_array_length(v_7b_ff) > 0 then
        if jsonb_array_length(v_7b_fi) > 0 then
          v_7b_partes := v_7b_partes || format('%s (%s) %s',
            case when jsonb_array_length(v_7b_fi) = coalesce((v_7b_pl ->> 'ni')::int, 0)
                   then case when jsonb_array_length(v_7b_fi) = 1 then 'no primeiro meio-dia'
                             else format('nos %s primeiros meios-dias', jsonb_array_length(v_7b_fi)) end
                 else format('em %s dos %s primeiros meios-dias', jsonb_array_length(v_7b_fi), v_7b_pl ->> 'ni') end,
            public._agenda_dias_texto(array(select distinct (e ->> 'dia')::date from jsonb_array_elements(v_7b_fi) e)),
            coalesce(nullif(public._agenda_lista(array(select distinct on (e ->> 'motivo') e ->> 'frase' from jsonb_array_elements(v_7b_d -> 'motivos') e
                                                        where e ->> 'onde' = 'inicio' order by e ->> 'motivo')), ''), 'a tarefa'));
        end if;
        if jsonb_array_length(v_7b_ff) > 0 then
          v_7b_partes := v_7b_partes || format('%s (%s) %s',
            case when jsonb_array_length(v_7b_ff) = coalesce((v_7b_pl ->> 'nf')::int, 0)
                   then case when jsonb_array_length(v_7b_ff) = 1 then 'no último meio-dia'
                             else format('nos %s últimos meios-dias', jsonb_array_length(v_7b_ff)) end
                 else format('em %s dos %s últimos meios-dias', jsonb_array_length(v_7b_ff), v_7b_pl ->> 'nf') end,
            public._agenda_dias_texto(array(select distinct (e ->> 'dia')::date from jsonb_array_elements(v_7b_ff) e)),
            coalesce(nullif(public._agenda_lista(array(select distinct on (e ->> 'motivo') e ->> 'frase' from jsonb_array_elements(v_7b_d -> 'motivos') e
                                                        where e ->> 'onde' = 'fim' order by e ->> 'motivo')), ''), 'a tarefa'));
        end if;
        v_7b_txt := '1 pessoa; ' || public._agenda_lista(v_7b_partes)
                    || case when cardinality(v_7b_partes) > 1 then ' pedem 2' else ' pede 2' end || ' — falta a 2ª pessoa (' || v_7b_tf || ').';
      else
        v_7b_txt := v_7b_d ->> 'texto';
      end if;
    end if;
    v_7b_eq := jsonb_build_object(
      'pessoas', v_7b_pes,
      'dupla', jsonb_build_object('inicio', v_7b_d -> 'inicio', 'fim', v_7b_d -> 'fim', 'todos', v_7b_d -> 'todos',
                                  'fonte', v_7b_d ->> 'fonte', 'texto', v_7b_d ->> 'texto'),
      'notas', coalesce((select jsonb_agg(n ->> 'texto' order by o) from jsonb_array_elements(coalesce(v_7b_d -> 'notas', '[]'::jsonb))
                                                                   with ordinality t(n, o)), '[]'::jsonb),
      'modo', v_7b_modo,
      'falta', coalesce((select jsonb_agg(jsonb_build_object('dia', e -> 'dia', 'turno', e -> 'turno', 'onde', e -> 'onde') order by o)
                           from jsonb_array_elements(coalesce(v_7b_pl -> 'faltam', '[]'::jsonb)) with ordinality t(e, o)), '[]'::jsonb),
      'espera', v_7b_esp,
      'texto', v_7b_txt);
  end if;
  -- FASE 7b: fim
  -- FASE 7d: (7d P8; §5.8, §6.2) o bloco "Local" do cartão: nulo com os 6 modos desligados e na OS que já foi feita (o resto do cartão é o de antes, byte a byte)
  if so.status not in ('completed', 'invoiced', 'cancelled') then
    v_7d_local := public._agenda_local_bloco(p_os, p_hoje);
  end if;
  -- FASE 7d: fim
  -- FASE 7e: (7e P7, §5.6, §6.4, R7.3-1, R7.3-2) duracao.estimativa e duracao.promessa, só na OS que ainda vai ser feita (como o campo, a equipe e o local):
  --   estimativa: com o viés aplicado ao que o motor marca (agenda_meios_da_os traz vies: ligado de verdade, o congelado na marcação ou o aprovado; o congelado vale também com o freio e
  --   com o interruptor desligado, R7.14), os 2 números ("Estimativa minha: 2,5 dias pelo valor do orçamento × 1,17 (…) = 3 dias."); nos dias do dono, o texto do P3 ("Você disse 3 dias;
  --   contei 3,5 …", AG7-33). Em teste (o interruptor fora de desligado, sem o viés em uso): o que eu marcaria pelo medido da classe da OS, senão do geral, só se o número muda (lição 5),
  --   na simulação de "sem o freio" (agenda.gestor = sombra), o único regime em que o viés vale; nunca na OS marcada (o congelado da marcação vale, também o 1,00).
  --   Sem base, diagnóstico (R7.5-8) e os dias do dono em teste: nada. A leitura cara (agenda_meios_da_os) só roda com o interruptor fora de desligado ou com a OS marcada ou aprovada com viés.
  --   promessa: com modo_promessa fora de desligado (o cru: o efetivo dele é sombra sempre), o prazo real com folga (agenda_promessa_da_os; AG7-32: nunca ao cliente), só com o fator
  --   medido (com o padrão, "pela folga do histórico" seria falso, R7.12-9) e quando a folga acrescenta dia (o fim com folga depois do fim do plano, lição 5).
  -- Sem nada a dizer, as 2 chaves ficam ausentes. Abaixo, no retorno, a mesma conta de duracao com as 2 a mais (a última chave igual do objeto vale): sem elas, a de cima, byte a byte.
  if so.status not in ('completed', 'invoiced', 'cancelled') then
    v_7e_c := public._agenda_cfg();
    if v_7e_c.modo_vies <> 'desligado' or coalesce(pl.vies_marcado <> 1, false) or pl.aprovado_com_vies is not null then
      v_7e_m := public.agenda_meios_da_os(p_os, p_hoje);
      if v_7e_m ? 'vies' and v_7e_m ? 'texto_vies' then
        v_7e_est := v_7e_m ->> 'texto_vies';
      elsif v_7e_m ? 'vies' and v_7e_m ? 'dias_sem_vies' then
        v_7e_vi := (v_7e_m ->> 'vies')::numeric;
        v_7e_ch := case when v_7e_m ->> 'vies_fonte' = 'marcado' then pl.vies_marcado_chave else public._agenda_vies_da_os(p_os) ->> 'chave' end;
        v_7e_est := format('Estimativa minha: %s pelo valor do orçamento × %s (%s costumam levar %s) = %s%s.',
                           public._agenda_dias((v_7e_m ->> 'dias_sem_vies')::numeric), public._agenda_num(v_7e_vi, 2),
                           coalesce(public._agenda_classe_texto_do_nivel(regexp_replace(coalesce(v_7e_ch, ''), '^estimativa:', '')), 'as OS'),
                           case when v_7e_vi > 1 then 'mais' else 'um pouco menos' end, public._agenda_dias((v_7e_m ->> 'dias')::numeric),
                           case v_7e_m ->> 'vies_fonte' when 'marcado' then ' (o que valia quando marquei)' when 'aprovado' then ' (o que você aprovou)' else '' end);
      -- (a conferência do P7) a OS marcada guarda o viés da marcação (§3.1-10): agenda_meios_da_os lê o congelado antes do de agora, e o 1,00 congelado também vale. Ligar não
      -- muda os dias dela, e "eu marcaria" seria falso (a OS#72 do replay: o cartão dizia 8,5 dias, o de verdade ficava em 6). A mesma regra do motor: o congelado vale quando a chave
      -- dele é da mesma conta (aqui, a da estimativa: sem chave, ou uma que não é dono:).
      elsif v_7e_c.modo_aprendizado <> 'desligado' and v_7e_c.modo_vies <> 'desligado' and public._agenda_margem_modo('vies') <> 'ligado'
            and coalesce(pl.estimativa_fonte, '') not in ('dono', 'aceita')
            and (pl.vies_marcado is null or pl.vies_marcado_chave like 'dono:%') then
        select x.calculado, x.chave into v_7e_vi, v_7e_ch
          from public.agenda_aprendizado x
         where x.item = 'vies' and x.calculado is not null
           and x.chave in ('estimativa:' || (public._agenda_classe_de_campo(p_os) ->> 'chave'), 'estimativa:todas')
         order by x.chave = 'estimativa:todas', x.chave
         limit 1;
        if v_7e_vi is not null and v_7e_vi <> 1 then
          -- (a conferência do P7) a conta em teste roda no regime em que o viés vale, sem o freio: com o gestor ligado (modo_marcar_sozinho), as regras dele (a mão de obra limpa, uma
          -- pessoa, a estimativa…) mudam a sugestão (a OS#73 do replay: 2,5 h e R$ 500 com o freio, 1,5 h e R$ 300 sem ele; o cartão dizia 1 dia, o de verdade ficava em meio), e a conta
          -- roda na simulação de "sem o freio" da 7a (agenda.gestor = sombra, a de _agenda_aprender_congelar); sem o gestor ligado, sem o freio as regras também ficam de fora, e a conta
          -- é a de hoje. A sugestão e os dias sem o viés saem dela; o valor de antes volta logo depois (num erro, pelo rollback de quem chamou). Só se o viés muda o número nela
          -- (lição 5); se o que ela marcaria sem o viés não é o de hoje (as regras do gestor mudam os dias), o texto diz os dois.
          v_7e_gs := coalesce(current_setting('agenda.gestor', true), '');
          if v_7e_c.modo_marcar_sozinho = 'ligado' then
            perform set_config('agenda.gestor', 'sombra', true);
          end if;
          v_7e_sug := public.os_duracao_sugerida(p_os);
          v_7e_hs := (public.agenda_meios_da_os(p_os, p_hoje) ->> 'dias')::numeric;
          perform set_config('agenda.gestor', v_7e_gs, true);
          if not coalesce((v_7e_sug ->> 'sem_base')::boolean, false) and public._agenda_margem_tipo_os(p_os) is distinct from 'diagnóstico' then
            v_7e_hj := (v_7e_m ->> 'dias')::numeric;
            v_7e_dd := case when pl.dias is not null then greatest(0.5, round(pl.dias * v_7e_vi * 2) / 2)
                            else (public._agenda_dias_com_vies(v_7e_sug, v_7e_vi) ->> 'dias')::numeric end;
            if v_7e_hs is not null and v_7e_dd <> v_7e_hs then
              v_7e_est := format('Em teste: com o que %s costumam levar, eu marcaria %s (%s).',
                                 coalesce(public._agenda_classe_texto_do_nivel(regexp_replace(v_7e_ch, '^estimativa:', '')), 'as OS'), public._agenda_dias(v_7e_dd),
                                 case when v_7e_hs = v_7e_hj then 'hoje ' || public._agenda_num(v_7e_hj, 1)
                                      else 'sem isso, ' || public._agenda_num(v_7e_hs, 1)
                                           || coalesce('; hoje ' || public._agenda_num(v_7e_hj, 1), '') end);
            end if;
          end if;
        end if;
      end if;
    end if;
    if v_7e_c.modo_aprendizado <> 'desligado' and v_7e_c.modo_promessa <> 'desligado' then
      begin
        v_7e_pr := public.agenda_promessa_da_os(p_os, p_hoje);
      exception when insufficient_privilege then
        v_7e_pr := null;
      end;
      if coalesce((v_7e_pr ->> 'ok')::boolean, false) and not coalesce((v_7e_pr ->> 'sem_plano')::boolean, false)
         and v_7e_pr ->> 'fonte' = 'aprendido' and coalesce((v_7e_pr ->> 'n')::int, 0) >= 1
         and (v_7e_pr ->> 'fim_com_folga')::date > (v_7e_pr ->> 'fim_plano')::date then
        v_7e_prom := format('Pela folga do histórico, pronto até %s (só para você: ao cliente não digo data de pronto).',
                            public._dia_curto((v_7e_pr ->> 'fim_com_folga')::date));
      end if;
    end if;
  end if;
  v_7e_dur := jsonb_build_object(
      'campo', v_campo,
      'dias', p #> '{duracao,dias}', 'fonte', p #>> '{duracao,fonte}',
      'fonte_texto', case p #>> '{duracao,fonte}' when 'dono' then 'você disse' when 'aceita' then 'você aceitou a minha estimativa'
                                                  else 'estimativa minha' end,
      'faixa', jsonb_build_object('otimista', p #> '{duracao,dias_otimista}', 'realista', p #> '{duracao,dias_realista}'),
      'faixa_texto', case when p #>> '{duracao,dias_otimista}' is not null
                          then 'faixa ' || public._agenda_faixa_dias((p #>> '{duracao,dias_otimista}')::numeric,
                                                                    (p #>> '{duracao,dias_realista}')::numeric) end,
      'texto', p #>> '{duracao,texto}')
    || case when v_7e_est is not null then jsonb_build_object('estimativa', v_7e_est) else '{}'::jsonb end
    || case when v_7e_prom is not null then jsonb_build_object('promessa', v_7e_prom) else '{}'::jsonb end;
  -- FASE 7e: fim
  -- FASE 7g: (7g P7; §5.7, R9.5-19, R9.12-9 e 10) a chave porque do cartão ("Por que assim"), só com modo_porque ligado e na OS que ainda vai ser feita (como o
  -- campo, a equipe e o local), da OS marcada ou reservada de hoje em diante (de fora ou fora da carteira, nada a dizer): o porquê de _agenda_porque_da_os sem o
  -- texto longo, {quem_texto, fonte_texto, suposicoes: [texto], criterio_texto, degrau_texto}. As suposições e o critério só do gestor (como o texto de lá:
  -- "Contei" e o critério da pessoa são dele). Na reserva, "reservado pelo gestor" / "reservado por você" (a reserva não é marcação). Marcada antes do porquê:
  -- fonte_texto = "de antes de eu guardar o porquê" (a duração de hoje não é a da marcação). Sem nada a dizer, fora de ligado ou se a leitura falhar, a chave
  -- fica ausente: o cartão de antes, byte a byte.
  if (public._agenda_cfg()).modo_porque = 'ligado' and so.status not in ('completed', 'invoiced', 'cancelled') then
    begin
      v_7g_pq := public._agenda_porque_da_os(p_os, p_hoje, now());
      v_7g_pq := case when v_7g_pq ->> 'estado' in ('marcada', 'reservada') then jsonb_build_object(
          'quem_texto', case when v_7g_pq ->> 'estado' = 'reservada'
                               then case when v_7g_pq ->> 'quem' = 'dono' then 'reservado por você' else 'reservado pelo gestor' end
                             else v_7g_pq ->> 'quem_texto' end,
          'fonte_texto', case when position('Essa marcação é de antes de eu guardar o porquê' in v_7g_pq ->> 'texto') > 0 then 'de antes de eu guardar o porquê'
                              else v_7g_pq ->> 'fonte_texto' end,
          'suposicoes', case when v_7g_pq ->> 'quem' = 'gestor'
                               then coalesce((select jsonb_agg(e -> 'texto' order by o) from jsonb_array_elements(v_7g_pq -> 'suposicoes') with ordinality t(e, o)),
                                             '[]'::jsonb)
                             else '[]'::jsonb end,
          'criterio_texto', case when v_7g_pq ->> 'quem' = 'gestor' then v_7g_pq ->> 'criterio_texto' end,
          'degrau_texto', v_7g_pq ->> 'degrau_texto') end;
    exception when others then
      v_7g_pq := null;
    end;
  end if;
  -- FASE 7g: fim
  return jsonb_build_object(
    -- FASE 7g: (7g P7) a chave porque (acima); sem ela, o par é ('os', nulo), e o 'os' de baixo, o último igual do objeto, vale: a chave fica ausente
    case when v_7g_pq is not null then 'porque' else 'os' end, v_7g_pq,
    -- FASE 7g: fim
    -- FASE 5: o bloco "Cliente" do cartão (o que foi dito, a confirmação, as mensagens desta OS e o que espera você;
    -- _agenda_cliente_da_os). null sem o cliente.
    'cliente', public._agenda_cliente_da_os(p_os, p_hoje),
    -- FASE 5: fim
    -- FASE 7b: (7b P5) o bloco "Equipe" do cartão (nulo com modo_dupla desligado e na OS concluída, faturada ou cancelada)
    'equipe', v_7b_eq,
    -- FASE 7b: fim
    -- FASE 7d: (7d P8) o bloco "Local" do cartão
    'local', v_7d_local,
    -- FASE 7d: fim
    'os', so.id, 'numero', so.numero, 'status', so.status, 'estado', p ->> 'estado_texto',
    'marcos', public.agenda_marcos_da_os(p_os, p_hoje),
    'pode_entregar', so.status = 'completed' and so.delivered_at is null,
    'duracao', jsonb_build_object(
      -- FASE 6: (P8) a linha do fator de campo (nula em desligado e na OS concluída)
      'campo', v_campo,
      -- FASE 6: fim
      'dias', p #> '{duracao,dias}', 'fonte', p #>> '{duracao,fonte}',
      'fonte_texto', case p #>> '{duracao,fonte}' when 'dono' then 'você disse' when 'aceita' then 'você aceitou a minha estimativa'
                                                  else 'estimativa minha' end,
      'faixa', jsonb_build_object('otimista', p #> '{duracao,dias_otimista}', 'realista', p #> '{duracao,dias_realista}'),
      'faixa_texto', case when p #>> '{duracao,dias_otimista}' is not null
                          then 'faixa ' || public._agenda_faixa_dias((p #>> '{duracao,dias_otimista}')::numeric,
                                                                    (p #>> '{duracao,dias_realista}')::numeric) end,
      'texto', p #>> '{duracao,texto}'),
    -- FASE 7e: (7e P7) a duração com a estimativa e o prazo real (calculada logo acima, a mesma conta de cima com as 2 chaves a mais): a última chave igual do objeto vale e substitui a de
    -- cima; sem as 2, é a de cima, byte a byte
    'duracao', v_7e_dur,
    -- FASE 7e: fim
    'presenca_dono', jsonb_build_object(
      'valor', v_pres ->> 'presenca', 'pela_regra', coalesce(v_pres ->> 'fonte', 'regra') = 'regra',
      'texto', case v_pres ->> 'presenca' when 'abre_e_fecha' then 'Você abre e fecha'
                                          when 'sempre' then 'Você fica o tempo todo'
                                          when 'nunca' then 'Você não precisa ir'
                                          else 'Sem regra' end
               || case when coalesce(v_pres ->> 'fonte', 'regra') <> 'regra' then ' (você disse)'
                       when coalesce(v_pres ->> 'motivo', 'padrão') = 'padrão' then ' (pela regra)'
                       else ' (pela regra: ' || (v_pres ->> 'motivo') || ')' end),
    -- FASE 6: (P8) a presença com a aprendida (a última chave igual do objeto vale: substitui a de cima)
    'presenca_dono', v_pd,
    -- FASE 6: fim
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
  'Agenda de Produção (Fase 3, P7a; Fase 5, P6): o cartão "Plano" da OS — {cliente (Fase 5: _agenda_cliente_da_os — o contato, o que foi dito ao cliente e se ainda vale, a confirmação, as 5 mensagens mais recentes desta OS e o que espera o dono; null sem o cliente), os, numero, status, estado, marcos (agenda_marcos_da_os), pode_entregar (concluída sem entrega), duracao {dias, fonte dono|aceita|sugerida, fonte_texto, faixa {otimista, realista}, faixa_texto, texto}, presenca_dono {valor, pela_regra, texto "Você abre e fecha (pela regra)"}, material {estado, itens:[{descricao, nivel A–E, nivel_texto, situacao, previsao, trecho, critico, fornecedor}]}, janela {bem_indisponivel, nao_antes_de, motivo, precisa_ate, nao_antes_texto, precisa_ate_texto}, prometido_planejado {precisa_ate, fim_publicado, folga_du, texto}, planejado_realizado:[{dia, rotulo, pessoas_texto, dia_texto, meios, resultado, resultado_texto, motivo_texto, diaria ("lançada" | "a confirmar" | null — nunca o valor)}], intervencoes:[{dia, texto}]}. Administrador e financeiro (com login) ou service_role; senão 42501. FASE 6 (P8): duracao.campo = a linha do fator de campo da classe da OS (agenda_fator_de_campo: "Em teste: as OS de energia em motorhome levam até 1,7× o combinado (7 OS); hoje seria 1,7×, e vale 1,5× (padrão).") — nula com modo_aprendizado desligado e na OS concluída, faturada ou cancelada; presenca_dono.aprendida = o motivo da presença aprendida ("você foi a 3 de 4 OS de energia em motorhome"; nulo sem ela), e o texto "Você fica o tempo todo (pelo que medi: …)". CORREÇÃO FASE 6 (C1, item 3): com a presença guardada na 1ª publicação, o texto diz "(pelo que medi quando planejei: …)". CORREÇÃO FASE 6 (C2, regressão B8): sem o sub no JWT, só o service_role (ou nenhum JWT); o authenticated sem sub recebe 42501. FASE 7b (P5, §5.4, §6.4, R4.3, R4.4): o bloco equipe {pessoas (as que o serviço pede fora da dupla: as da sugestão, 2 na dupla o tempo todo, as da equipe dita), dupla {inicio, fim, todos, fonte dono|regra|nenhuma, texto} (_agenda_dupla_da_os), notas [texto] (o espaço apertado: "Atenção: casa de máquinas — confira se precisa de duas pessoas."), modo, falta [{dia, turno, onde}] (os meios-dias do plano em que a dupla está sem a 2ª pessoa, de hoje em diante: _agenda_dupla_no_plano), espera (a dupla dita que espera a 2ª pessoa: a classe 4 dupla, ou o "fora" dupla da última montagem que citou a OS, sem compromisso dela de hoje em diante), texto} — o texto: a regra "1 pessoa; em dupla nos 2 primeiros meios-dias (troca do banco de baterias) — suposição minha."; com a 2ª pessoa faltando no plano "1 pessoa; nos 2 primeiros meios-dias (ter 10/11) a troca do banco de baterias pede 2 — falta a 2ª pessoa (só Alex está na equipe)." (o tempo todo: "1 pessoa; o serviço todo pede 2 (o orçamento previu 2 técnicos) — falta a 2ª pessoa em 12 meios-dias (só Alex está na equipe)."); a dita "Em dupla nos 2 primeiros meios-dias (você disse)." e, esperando, "Em dupla o tempo todo (você disse) — espero a 2ª pessoa: só Alex está na equipe."; a equipe dita "Quem vai: Roberto e João (você disse)."; em teste a regra "Em teste: eu marcaria 1 pessoa, em dupla nos 2 primeiros meios-dias (troca do banco de baterias). Hoje marco 1 pessoa e ponho a 2ª nesses meios-dias quando alguém está livre." (sem a regra uma_pessoa: "Hoje marco 2 pessoas."); nada "1 pessoa.". Nulo com modo_dupla desligado e na OS concluída, faturada ou cancelada (o resto do cartão é o de antes, byte a byte). FASE 7d (P8; §5.8, §6.2): o bloco local {texto, fonte, suposicao, tipo, nome, vagas, viagem_texto, bem_texto, perguntei, combinar [{texto, ate, vencido, em_teste}], notas []} (_agenda_local_bloco). Nulo com os 6 modos desligados e na OS concluída, faturada ou cancelada. Nunca valor. FASE 7e (P7, §5.6, §6.4, R7.3-1, R7.3-2): duracao.estimativa (com o viés aplicado ao que o motor marca, os 2 números; nos dias do dono, o texto do P3; em teste, o que eu marcaria, só se muda) e duracao.promessa (o prazo real com folga, só para o dono e só com o fator medido e dia a mais), ausentes sem nada a dizer; o resto de duracao igual. FASE 7g (P7): com modo_porque ligado, na OS marcada ou reservada de hoje em diante que ainda vai ser feita, a chave porque = {quem_texto ("marcado pelo gestor", "marcado por você"; na reserva, "reservado …"), fonte_texto ("de antes de eu guardar o porquê" na marcação de antes da 7g), suposicoes [texto] e criterio_texto (só do gestor), degrau_texto}, de _agenda_porque_da_os sem o texto longo. Fora de ligado, sem nada a dizer ou se a leitura falhar, a chave fica ausente (o cartão de antes, byte a byte).';
