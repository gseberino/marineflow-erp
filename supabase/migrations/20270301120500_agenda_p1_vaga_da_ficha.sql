-- Agenda de Produção — pacote 1 do assistente (27/11/2026): a vaga da ficha de amanhã, parte 1 (a conta). Achado NOVO-agenda-p1-18.
--
-- Por quê: na qui 26/11/2026 a confirmação das 07:45 saiu, o silêncio das 9h tirou o dia do técnico, a pergunta dos dias das 16:45 ocupou a
--   2ª vaga do dia (1 mensagem na fila + 0 previstas < o teto de 2) e a ficha de sex 27/11 nasceu recusada por teto às 19:30, sem aviso ao
--   dono e sem nova tentativa (a via em PDF, que espera a ficha entregue, também não saiu). _agenda_equipe_previstas_hoje deixava de contar
--   a ficha de amanhã sempre que a confirmação do dia tinha saído, supondo que o "como foi" das 17:00 a levaria; mas o "como foi" só nasce
--   para quem ainda tem plano hoje. Com o dia fora do plano depois da confirmação, as duas parcelas davam zero e ninguém guardava a vaga.
--
-- O que muda: só 1 função, recriada do corpo em vigor (o da 20261109101000, igual ao de produção: md5 do corpo sem CR 7e86318b…), mais 1 bloco
--   "-- P1 AGENDA: (VAGA, 27/11/2026) … -- P1 AGENDA: fim" que troca 3 linhas (as de antes ficam em "--antes:"; tirado o bloco e devolvidas
--   elas, o corpo é o de antes, byte a byte, sem CR):
--   · _agenda_equipe_previstas_hoje: a ficha de amanhã só deixa de contar à parte quando o "como foi" de HOJE ainda vai nascer para levá-la,
--     isto é, quando as três coisas valem juntas: a confirmação de hoje saiu (não recusada), a pessoa ainda tem plano vivo hoje e o "como
--     foi" de hoje ainda não foi registrado. Antes bastava a primeira. Nos outros casos a ficha conta +1 e a pergunta dos dias
--     (agenda_equipe_semana, o único chamador desta conta) espera: tenta de novo no tique seguinte e nos outros dias da janela dela, como já
--     faz hoje. Na reconstituição de 26/11 às 16:45: antes 1 + 0 < 2 (a pergunta saiu); agora 1 + 1 = 2 (a pergunta espera e a ficha sai
--     como a 2ª mensagem do dia).
--     Fica igual: o dia em que a confirmação saiu e o técnico segue no plano (calado com o dia mantido, ou com o "ok" dele): a ficha vai
--     dentro do "como foi" e a conta dá 1, como antes. Fica igual também o dia sem confirmação (a ficha já contava).
--     Muda também, pelo mesmo critério: a confirmação saiu e o "como foi" de hoje já foi registrado SEM a ficha (ela esperava o "mande" do
--     dono): a ficha passa a contar +1 (antes 0).
--
-- Nada mais muda: nenhuma tabela, coluna, CHECK, índice, modo, teto, hora, cron ou edge function; nenhuma mensagem nova e nenhum texto novo;
--   o teto do dia e as duas travas que o contam (_agenda_equipe_enfileirar e o gatilho _agenda_fila_da_equipe) ficam como estão, e também
--   _agenda_equipe_no_dia, agenda_equipe_semana, _agenda_rotina_como_foi e _agenda_rotina_ficha. Nenhum dia passa do teto: a conta só decide
--   quem espera.
-- Portas: create or replace não mexe na ACL nem no dono (STABLE, invoker, search_path = public, EXECUTE só de service_role). A volatilidade
--   e o search_path vêm do texto da função e são os de antes.
-- LIGAR: nada a ligar. Vale ao aplicar, com as duas ações do silêncio ('tirar' e 'manter') e com qualquer hora da ficha: a conta não lê
--   nenhuma das duas chaves.
-- DESFAZER: D:/IA-HBR/Trabalho/rotina-do-time/publicar-vaga/voltar.sql (o corpo e o comentário de antes, byte a byte, com o CR que produção
--   tem). Não há chave nem dado a reverter; não mexe em supabase_migrations.schema_migrations (registrar a volta no repositório).
-- IDEMPOTENTE: create or replace; o comentário só ganha o trecho uma vez.
-- LIMITE (fica aberto; nestes casos a ficha ainda pode nascer recusada por teto):
--   · o plano de amanhã nasce depois das 16:45, com a pergunta dos dias já enviada como a 2ª do dia;
--   · o dono diz "mande" entre o "como foi" das 17:00 e a hora da ficha (o "como foi" foi sem a ficha e já é a 2ª);
--   · tiques perdidos entre as 17:00 e a hora da ficha;
--   · o convite, o previsto e a mudança, quando saírem de teste (o convite confere só a fila, não esta conta);
--   · com o teto em 3 (o CHECK aceita), a conta não espelha a parte "ficha liberada" do "como foi".
--   E a recusa continua calada: o aviso ao dono quando a ficha de amanhã não sai é o segundo passo, em outra migration.
--   A pergunta dos dias cede a vez mais vezes: nas semanas em que o técnico trabalha quinta e sexta ela sai no sábado às 16:45 (já acontece
--   com o dia mantido; aconteceu em 14/11/2026).

CREATE OR REPLACE FUNCTION public._agenda_equipe_previstas_hoje(p_payee uuid, p_hoje date, p_agora timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
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
     -- P1 AGENDA: (VAGA, 27/11/2026) a ficha de amanhã só deixa de reservar a vaga dela quando o "como foi" de HOJE ainda vai nascer para
     -- levá-la: a confirmação de hoje saiu E a pessoa ainda tem plano vivo hoje E o "como foi" de hoje ainda não foi registrado (os
     -- critérios de _agenda_rotina_como_foi). Antes bastava a confirmação ter saído: com o dia fora do plano depois dela (o silêncio da
     -- manhã que tira o dia, o "não vou", o dono) ninguém guardava a vaga, a pergunta dos dias a ocupava e a ficha nascia recusada por teto
     -- (qui 26/11/2026). Vale com as duas ações do silêncio e com qualquer hora da ficha: a conta não lê nenhuma dessas chaves.
--antes:     and not exists (select 1 from public.agenda_equipe_mensagens m
--antes:                      where m.payee_id = p_payee and m.modo = v_modo and m.tipo = 'confirmar' and m.dia = p_hoje
--antes:                        and m.estado <> 'recusada') then
     and not (exists (select 1 from public.agenda_equipe_mensagens m
                       where m.payee_id = p_payee and m.modo = v_modo and m.tipo = 'confirmar' and m.dia = p_hoje
                         and m.estado <> 'recusada')
              and exists (select 1 from public.agenda_alocacoes a
                           where a.payee_id = p_payee and a.dia = p_hoje and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva')
              and not exists (select 1 from public.agenda_equipe_mensagens m
                               where m.payee_id = p_payee and m.modo = v_modo and m.tipo = 'como_foi' and m.dia = p_hoje)) then
     -- P1 AGENDA: fim
    v_n := v_n + 1;
  end if;
  -- FASE 7f: (7f P5, R8.5-19, R2) na quinta, o previsto que vai SOZINHO às 19:30 (a pessoa não tem a ficha de amanhã, ou ela já saiu no "como foi")
  -- também é mensagem do dia: a pergunta dos dias (7b) o conta, e o previsto nunca é a 3ª. O que vai junto da ficha já está contado nela. Só com o
  -- previsto ligado de verdade (_agenda_fala_modo: com o freio é teste) e a equipe ligada; fora disso, a conta de antes.
  if v_modo = 'ligado' and public._agenda_fala_modo('previsto') = 'ligado' and public._agenda_equipe_previsto_sozinho(p_payee, p_hoje) then
    v_n := v_n + 1;
  end if;
  -- FASE 7f: fim
  return v_n;
end;
$function$;

-- ── O comentário da recriada (o de antes + o que mudou; uma vez só, no fim) ───────────────────────────────────────────────────────────
do $c$
declare
  c_p constant text := 'public._agenda_equipe_previstas_hoje(uuid,date,timestamptz)';
begin
  if coalesce(obj_description(to_regprocedure(c_p), 'pg_proc'), '') not like '%P1 AGENDA (VAGA, 27/11/2026%' then
    execute format('comment on function %s is %L', c_p, ltrim(coalesce(obj_description(to_regprocedure(c_p), 'pg_proc'), '')
      || ' P1 AGENDA (VAGA, 27/11/2026, 20270301120500): a ficha de amanhã só deixa de contar à parte quando o "como foi" de hoje ainda vai nascer para levá-la (a confirmação de hoje saiu, a pessoa ainda tem plano hoje e o "como foi" de hoje não foi registrado); troca o "sem a confirmação de hoje registrada" de cima. Com a confirmação enviada e o dia fora do plano, ou com o "como foi" de hoje já registrado sem a ficha, ela conta +1 e a pergunta dos dias espera. Vale com as duas ações do silêncio e com qualquer hora da ficha.'));
  end if;
end
$c$;

insert into supabase_migrations.schema_migrations (version, name) values ('20270301120500','agenda_p1_vaga_da_ficha');
