-- Agenda de Produção, Fase 7, etapa 7g ("Mostrar como pensou e provar o trabalho"), pacote P3: como pensei, o porquê de uma OS e a data dita com a relação.
-- O dono pergunta "como você pensou a semana que vem?" e o banco responde numa função só, em ordem fixa (o que marquei, o que reservei, o que ficou de fora,
-- a folga, os riscos e o que preciso dele); "por que o Nelson ficou para terça?" sai do porquê de uma OS; e "passa o Lenine para depois de quinta" marca a
-- partir de sexta, não na quinta.
-- Spec: scratchpad agenda-pesquisa/spec-fase7g.md (§5.3, §6.2, §6.3 e o bloco R9, que vale sobre o corpo: R9.3-1, R9.4-5, R9.5-10 e 11, R9.6, R9.7, R9.8,
-- R9.12, R9.13); nomes: fase7-registro.md; o registro do pacote: notas-fase7g.md (seção P3).
-- Depende das Fases 1 a 6, das etapas 7a a 7d, da 7f inteira, da 7e até o P6 e da 7g até o P2 (20261112100000: os interruptores, os parâmetros e as peças do
-- porquê; 20261112100100: o porquê gravado nas alocações e nas ações).
--
-- ═══ DDL — OK NOMEADO ═══ (1 função recriada; 6 funções novas, 2 delas SECURITY DEFINER com porta)
-- NÃO APLICADA. Existe para revisão e espera o OK.
--
-- POR QUE: o porquê gravado pelo P2 só vale se alguém o lê. "Como pensei" junta numa leitura o que a agenda já sabe e mostra ao dono o que ela supôs, com os
-- números do banco (o modelo só repassa o texto). E a data dita perdia a relação: "depois de quinta" virava quinta (R9.4-5).
--
-- O QUE MUDA (com modo_explicar desligado, nada que o dono veja: as leituras novas respondem {modo: desligado} e a releitura do rascunho é a de antes):
--   1. _agenda_relacao_dita (nova): a relação dita logo antes da data, nas palavras do dono (depois de, antes de, a partir de, até); nula sem relação, com
--      negação na oração dela ("não antes de quinta", "não pode antes de quinta", "antes de quinta não dá") ou numa oração sem a data ("antes do dia 25,
--      não dá"), com a data também sem relação (2 pedidos no mesmo trecho) e com relações diferentes para a mesma data. Só lê o texto (IMMUTABLE).
--   2. _agenda_data_com_relacao (nova): a data conferida com a relação aplicada — depois = o 1º dia útil depois; antes = o último dia útil antes; a partir =
--      a data como está; até = de hoje até a data. Sem relação, a entrada byte a byte; com ela, a saída ganha relacao e relacao_texto ("você disse depois de
--      quinta"). _agenda_data_conferida NÃO é recriada: os outros 7 chamadores (22 chamadas) seguem como estão (R9.4-5).
--   3. agenda_rascunho_marcar (recriada de 20261025100400_agenda_fase2_rascunho.sql:761; md5 do corpo de antes d73ebf1c9f55537b5ad20887bb144d39): com modo_explicar ligado, a data do dia
--      pedido (p_quando) passa pela relação, e a releitura diz a relação entre parênteses. Em sombra e desligado, byte a byte o de antes (no que devolve e no
--      que grava no rascunho).
--   4. _agenda_porque_fonte (nova): a fonte da duração de uma alocação em palavras, pelo que foi gravado nela (a fonte da 7a; os dias e a mão de obra da
--      suposição duracao_orcamento; sem eles, os dias ditos ou o tamanho do bloco) e, só nas condições do R9.3-1, a frase do viés da 7e (os dois números).
--   5. _agenda_porque_linha (nova): a linha curta de uma marcação, pelas colunas gravadas da 1ª alocação de turno do bloco: a fonte e as primeiras
--      porque_motivos_max suposições (AG7-28: "1, o principal").
--   6. _agenda_porque_da_os (nova, SECURITY DEFINER, porta admin/financeiro ou service_role): o porquê de uma OS — marcada, reservada, de fora (o motivo de
--      agora e a pergunta aberta dela) ou fora da carteira — com o texto da §6.2 (≤ 600).
--   7. agenda_como_pensei (nova, SECURITY DEFINER, mesma porta): "como pensei a semana", as 6 partes em ordem fixa, cada uma lida à parte (falhou: incompleto e
--      a parte diz que não conseguiu ler). Com o freio, a 1ª linha diz que o dono pediu "gestor, só propor" e o "Eu marcaria" vem da última conta do gestor
--      (R9.6). A folga sai da grade do motor nos 2 ramos (com e sem a regra teto_equipe, R9.7). "Preciso de você" usa a linha de agenda_perguntas_em_ordem como
--      vem: o número é o da Decisão de *agenda pendências* (R9.7). 1 painel, 1 grade, nenhuma leitura cara por OS (R9.8, R9.5-11).
--
-- O QUE NÃO MUDA: o motor, as propostas, o que se grava no plano, as mensagens e os outros 7 chamadores da data dita. Nenhum texto novo ao cliente; nenhuma
-- mensagem nova (as leituras só respondem a quem pergunta; quem as liga na conversa e na tela é o P7).
--
-- ORDEM DE LIGAR (spec R9.14): depois da 20261112100100. Aplicar sozinha não muda nada: modo_explicar fica como estiver (desligado até o dado 20261112100990).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7g_como_pensei.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261112100200
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; pelo publicar/exec/aplicar.sh, nunca db push: esta versão fica antes das 20261116* que já estão em produção):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261112100200_agenda_fase7g_como_pensei.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261112100200', 'agenda_fase7g_como_pensei');"
--
-- DESFAZER (na ordem):
--   drop function if exists public.agenda_como_pensei(date, date, timestamptz), public._agenda_porque_da_os(uuid, date, timestamptz),
--     public._agenda_porque_linha(uuid, jsonb, date), public._agenda_porque_fonte(uuid, date), public._agenda_data_com_relacao(jsonb, text, text, date),
--     public._agenda_relacao_dita(text, text);
--   agenda_rascunho_marcar volta pelo corpo da origem (acima), antes do drop de _agenda_data_com_relacao.
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.

-- ── 1. A relação da data dita ────────────────────────────────────────────────────────────────────────
-- R9.4-5 e §5.3: a relação é a expressão logo antes da data nas palavras do dono (o trecho), lidas como _agenda_data_no_passado lê (_agenda_preparar_data e a
-- posição): "depois de", "depois do", "após" → depois; "antes de" → antes; "a partir de", "desde" → a_partir; "até", "até o" → ate (com "dia" no meio também:
-- "depois do dia 10"). O dito que já começa pela relação ("depois de quinta", quando o modelo passa as palavras inteiras) vale pelo resto ("quinta"): a
-- releitura de agenda_data_dita não lê "depois de" nem "antes de" (lê "depois de quinta" como quinta).
-- (correção da conferência, 11/11) A relação só vale quando é a única leitura do trecho; na dúvida, nula: a data como foi dita, a de antes do P3.
--   A oração vai de um "e" ou "mas" ao seguinte (a vírgula e o ponto e vírgula viram "e"; sem o acento, o "é" também parte: "não é antes de quinta"
--   deixa o "não" numa oração sem a data, e a negação solta anula, abaixo).
--   Negação (não, n, nunca, nem, nada, jamais, nenhum, nenhuma) na oração da relação e da data, antes ou depois dela: nula ("não antes de quinta", "não
--   pode antes de quinta", "antes de quinta não dá").
--   A data também sem relação, numa oração sem negação: nula (2 pedidos no mesmo trecho: "o barco A na quinta e o barco B depois de quinta"). A data sem
--   relação numa oração negada não conta: "quinta não, depois de quinta" = depois.
--   Negação numa oração sem a data e sem um "antes", "depois" ou "até" dela: nula ("antes do dia 25, não dá", a vírgula do áudio); com ele, a negação é
--   dele ("só depois do dia 10, antes não dá" = depois).
--   Relações diferentes para a mesma data: nula.
create or replace function public._agenda_relacao_dita(p_trecho text, p_dito text)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  c_rel  constant text := '(?:depois d[aoe]|apos(?: [ao])?|antes d[aoe]|a partir d[aoe]|desde(?: [ao])?|ate(?: [ao])?)(?: dia)?';
  c_nao  constant text := '\m(nao|n|nunca|nem|nada|jamais|nenhuma?)\M';
  v_d    text := public._agenda_preparar_data(p_dito);
  v_t    text := ' ' || public._agenda_preparar_data(regexp_replace(coalesce(p_trecho, ''), '[,;]', ' e ', 'g')) || ' ';
  v_m    text[];
  v_pos  int := 0;
  v_i    int;
  v_k    text;
  v_rels text[] := '{}';
  v_o    text;
  v_nega boolean;
  v_tem  boolean;
  v_solta boolean := false;
begin
  if v_d = '' then
    return null;
  end if;
  v_m := regexp_match(v_d, '^' || c_rel || ' (.+)$');
  if v_m is not null then
    v_d := v_m[1];
  end if;
  foreach v_o in array regexp_split_to_array(v_t, '\m(?:e|mas)\M') loop
    v_nega := v_o ~ c_nao;
    v_tem := false;
    v_pos := 0;
    loop
      v_i := strpos(substr(v_o, v_pos + 1), ' ' || v_d || ' ');
      exit when v_i = 0;
      v_pos := v_pos + v_i;
      v_tem := true;
      v_m := regexp_match(left(v_o, v_pos), '\m(' || c_rel || ') $');
      if v_m is null then
        continue when v_nega;
        return null;
      end if;
      if v_nega then
        return null;
      end if;
      v_k := case when v_m[1] ~ '^(depois|apos)' then 'depois'
                  when v_m[1] ~ '^antes' then 'antes'
                  when v_m[1] ~ '^(a partir|desde)' then 'a_partir'
                  else 'ate' end;
      if not (v_k = any (v_rels)) then
        v_rels := v_rels || v_k;
      end if;
    end loop;
    if v_nega and not v_tem and v_o !~ '\m(depois|antes|ate)\M' then
      v_solta := true;
    end if;
  end loop;
  return case when cardinality(v_rels) = 1 and not v_solta then v_rels[1] end;
end;
$function$;

comment on function public._agenda_relacao_dita(text, text) is
  'Agenda de Produção (Fase 7g, P3; §3.1 item 9, §5.3, R9.4-5): a relação dita logo antes da data no trecho do dono — depois (depois de/da/do, após), antes (antes de/da/do), a_partir (a partir de, desde) ou ate (até, até o/a), com "dia" no meio também. O dito que já começa pela relação vale pelo resto. Só vale quando é a única leitura do trecho (a oração vai de um "e" ou "mas", ou de uma vírgula, ao seguinte). Nula sem relação; com negação (não, n, nunca, nem, nada, jamais, nenhum, nenhuma) na oração da relação, antes ou depois da data ("não pode antes de quinta", "antes de quinta não dá"); com negação numa oração sem a data e sem um antes, depois ou até dela ("antes do dia 25, não dá"); com a data também sem relação fora de oração negada (2 pedidos no mesmo trecho); e com relações diferentes para a mesma data. "quinta não, depois de quinta" = depois. IMMUTABLE.';

-- ── 2. A data com a relação aplicada ─────────────────────────────────────────────────────────────────
-- R9.4-5: depois → o 1º dia útil depois do fim (de = até: um dia; o encaixe estende a marcação); antes → o último dia útil antes do começo (de = até); a_partir
-- → a data como está; ate → de hoje até a data, como agenda_data_dita já faz em "até sexta". Sem relação (ou a data não conferida), a entrada byte a byte:
-- relacao e relacao_texto só existem quando há relação (R9.12-10). O texto da data é o de agenda_data_dita, refeito com as datas novas.
create or replace function public._agenda_data_com_relacao(p_dt jsonb, p_trecho text, p_dito text, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_rel text;
  v_de  date;
  v_ate date;
  v_p   text;
  v_txt text;
begin
  if p_dt is null or not coalesce((p_dt ->> 'ok')::boolean, false) or p_dt ->> 'de' is null or p_dt ->> 'ate' is null then
    return p_dt;
  end if;
  v_rel := public._agenda_relacao_dita(p_trecho, p_dito);
  if v_rel is null then
    return p_dt;
  end if;
  if p_hoje is null then
    raise exception '_agenda_data_com_relacao: sem o dia de hoje' using errcode = '22004';
  end if;
  v_de := (p_dt ->> 'de')::date;
  v_ate := (p_dt ->> 'ate')::date;
  if v_rel = 'depois' then
    v_de := public.agenda_somar_du(v_ate, 1);
    v_ate := v_de;
  elsif v_rel = 'antes' then
    v_ate := public.agenda_somar_du(v_de, -1);
    v_de := v_ate;
  elsif v_rel = 'ate' then
    v_de := p_hoje;
  end if;
  -- "você disse depois de quinta": as palavras do dito como vieram; sem a relação nele, a relação na frente (com o artigo de "dia" e "semana")
  v_p := public._agenda_normal(p_dito);
  v_txt := case when public._agenda_preparar_data(p_dito) ~ '^(depois|apos|antes|a partir|desde|ate)\M' then btrim(p_dito)
                else case v_rel when 'depois' then 'depois ' when 'antes' then 'antes ' when 'a_partir' then 'a partir ' else 'até' end
                     || case when v_rel = 'ate' then case when v_p ~ '^dia\M' then ' o ' when v_p ~ '^(semana|proxima)\M' then ' a ' else ' ' end
                             when v_p ~ '^dia\M' then 'do '
                             when v_p ~ '^(semana|proxima)\M' then 'da '
                             else 'de ' end
                     || btrim(p_dito) end;
  return p_dt || jsonb_build_object(
    'de', v_de, 'ate', v_ate,
    'texto', case when v_de = v_ate then public._dia_curto(v_de) else public._dia_curto(v_de) || ' a ' || public._dia_curto(v_ate) end,
    'relacao', v_rel, 'relacao_texto', 'você disse ' || v_txt);
end;
$function$;

comment on function public._agenda_data_com_relacao(jsonb, text, text, date) is
  'Agenda de Produção (Fase 7g, P3; §5.3, R9.4-5): a data conferida (a saída de _agenda_data_conferida) com a relação de _agenda_relacao_dita aplicada — depois: o 1º dia útil depois (um dia); antes: o último dia útil antes (um dia); a_partir: como está; ate: de hoje até a data. Com relação, ganha relacao e relacao_texto ("você disse depois de quinta"); sem ela (ou sem a data conferida), a entrada byte a byte. Só agenda_rascunho_marcar a chama, no dia pedido.';

-- ── 3. agenda_rascunho_marcar (recriada) ─────────────────────────────────────────────────────────────
create or replace function public.agenda_rascunho_marcar(p_autor uuid, p_canal text, p_os text, p_quando text,
                                                         p_ate text default null, p_pessoa text default null,
                                                         p_trecho text default null,
                                                         p_hoje date default public._hoje_brt(),
                                                         p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor  uuid := public._autor_da_agenda(p_autor);
  v_rec    jsonb := public._agenda_pedido_recusa(p_canal, p_trecho, 'agenda_rascunho_marcar');
  v_ro     jsonb;
  v_os     uuid;
  v_dt     jsonb;
  v_de     date;
  v_ate    date;
  v_rp     jsonb;
  v_pessoa uuid;
  v_s      jsonb;
  v_frase  text;
  v_item   jsonb;
  v_txt    text;
  -- FASE 7g: (7g P3, R9.4-5) a relação dita do dia pedido ("depois de quinta") e onde ela entra na releitura
  v_7g_rel text;
  v_7g_i   int;
  -- FASE 7g: fim
begin
  -- Fora de ligado a agenda não marca, mas mostra como ficaria (a simulação, sem rascunho).
  if v_rec is not null and v_rec ->> 'motivo' <> 'em_teste' then
    return v_rec;
  end if;
  if nullif(btrim(coalesce(p_trecho, '')), '') is null then
    return public._agenda_recusa('Me diga com as suas palavras o que você quer na agenda.', 'sem_trecho');
  end if;
  if nullif(btrim(coalesce(p_quando, '')), '') is null then
    return public._agenda_recusa('Para que dia?', 'sem_dia');
  end if;

  v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
  if v_ro ->> 'status' <> 'ok' then
    return public._agenda_recusa_da_os(v_ro);
  end if;
  v_os := (v_ro ->> 'id')::uuid;

  v_dt := public._agenda_data_conferida(p_quando, p_trecho, p_hoje, 'futuro');
  if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
  -- FASE 7g: (7g P3, §5.3, R9.4-5) com modo_explicar ligado, a relação que o dono disse logo antes do dia pedido muda a data: "depois de quinta" é o 1º dia
  -- útil depois (sexta), "antes de sexta" é o último antes (quinta), "até sexta" é de hoje até sexta, "a partir de" deixa a data; "não antes de quinta" não é
  -- relação. Só o dia pedido (p_quando): o "até" (p_ate) e os outros 7 chamadores de _agenda_data_conferida seguem como estão. Em sombra e desligado, nada
  -- é chamado e a data é a de antes.
  if (public._agenda_cfg()).modo_explicar = 'ligado' then
    v_dt := public._agenda_data_com_relacao(v_dt, p_trecho, p_quando, p_hoje);
    v_7g_rel := v_dt ->> 'relacao_texto';
  end if;
  -- FASE 7g: fim
  v_de := (v_dt ->> 'de')::date;
  v_ate := (v_dt ->> 'ate')::date;
  if nullif(btrim(coalesce(p_ate, '')), '') is not null then
    v_dt := public._agenda_data_conferida(p_ate, p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    v_ate := (v_dt ->> 'ate')::date;
  end if;
  if v_ate < v_de then
    return public._agenda_recusa(format('O período está invertido: %s.', public._agenda_quando_texto(v_ate, v_de)), 'periodo');
  end if;
  if v_ate < p_hoje then
    return public._agenda_recusa(format('"%s" já passou: para que dia?', btrim(p_quando)), 'data_passada');
  end if;
  v_de := greatest(v_de, p_hoje);

  if nullif(btrim(coalesce(p_pessoa, '')), '') is not null then
    v_rp := public.agenda_resolver_pessoa(p_pessoa, v_autor, p_hoje);
    if v_rp ->> 'status' <> 'ok' then
      return public._agenda_recusa(v_rp ->> 'texto', 'pessoa_' || (v_rp ->> 'status'),
        coalesce((select jsonb_agg(e ->> 'nome' order by o)
                    from jsonb_array_elements(coalesce(v_rp -> 'opcoes', '[]'::jsonb)) with ordinality t(e, o)), '[]'::jsonb));
    end if;
    v_pessoa := (v_rp ->> 'payee_id')::uuid;
  end if;

  -- O efeito, calculado agora pelo motor, sem gravar nada.
  v_s := public.agenda_propor('os', null, null, array[v_os],
           jsonb_build_object('fixar', jsonb_build_array(jsonb_build_object('os', v_os, 'de', v_de, 'ate', v_ate, 'pessoa', v_pessoa))),
           false, 'dono', v_autor, p_hoje, p_agora);
  v_frase := public._agenda_frase_do_encaixe(v_s, v_os);
  -- FASE 7g: (7g P3, §5.3) a releitura diz a relação entre parênteses, logo depois dos dias e de quem vai ("Daniel (OS-00204), sex 06/11, Roberto o dia todo
  -- (você disse depois de quinta)"), antes do que sai da agenda e do aviso do material. least ignora o nulo de propósito: o 1º dos 2 que existir.
  if v_7g_rel is not null and v_frase is not null then
    v_7g_i := least(nullif(strpos(v_frase, ' (sai de '), 0), nullif(strpos(v_frase, ' — mas '), 0));
    v_frase := case when v_7g_i is null then v_frase || ' (' || v_7g_rel || ')'
                    else left(v_frase, v_7g_i - 1) || ' (' || v_7g_rel || ')' || substr(v_frase, v_7g_i) end;
  end if;
  -- FASE 7g: fim
  v_item := (select i from jsonb_array_elements(v_s -> 'itens') i
              where i ->> 'op' = 'criar' and (i ->> 'os')::uuid = v_os and i ->> 'tipo' <> 'reserva' limit 1);

  if v_rec is not null then   -- em teste: só a simulação
    return public._agenda_recusa(
      'A agenda automática ainda está em teste: mostro como ficaria, mas não marco nada. '
      || coalesce('Ficaria assim: ' || v_frase || '.', public._agenda_nao_cabe(v_s, v_os, v_de, v_autor, p_hoje, p_agora, false)),
      'em_teste');
  end if;
  if v_frase is null then
    return public._agenda_recusa(public._agenda_nao_cabe(v_s, v_os, v_de, v_autor, p_hoje, p_agora, true), 'nao_cabe');
  end if;

  -- O dia pedido antes de o material estar garantido (o caso da OS-00104): a decisão é do dono, mas a releitura vira a
  -- pergunta — o aviso do material e "Marco mesmo assim?"; o *grava* é o sim.
  v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'marcar', 'marcar:' || v_os::text, v_os,
             jsonb_build_object('grupo', 'marcar:' || v_os::text, 'rotulo_grupo', 'Marco na agenda', 'os', v_os,
                                'numero', v_ro ->> 'numero', 'curto', v_ro ->> 'cliente_curto', 'de', v_de, 'ate', v_ate,
                                'pessoa', v_pessoa, 'pessoa_nome', v_rp ->> 'nome_curto',
                                'simulado', jsonb_build_object('de', v_item ->> 'de', 'ate', v_item ->> 'ate'),
                                'aviso_material', v_item ->> 'aviso_material',
                                'frase_pronta', v_frase || case when v_item ->> 'aviso_material' is not null
                                                                then '. Marco mesmo assim?' else '' end),
             p_trecho, p_hoje);
  return jsonb_build_object('ok', true, 'item', v_txt,
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto')
         || case when v_item ->> 'aviso_material' is not null
                 then jsonb_build_object('aviso_material', v_item ->> 'aviso_material',
                                         'pergunta', format('%s: %s. Marco mesmo assim? Se sim, mande *grava*.',
                                                            public._agenda_rotulo_da_os(v_os), v_item ->> 'aviso_material'))
                 else '{}'::jsonb end;
end;
$function$;

comment on function public.agenda_rascunho_marcar(uuid, text, text, text, text, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P4): "marca o Lenine pra quinta", "passa o Nelson para segunda" vira RASCUNHO (nada na agenda). OS por agenda_resolver_os, o dia (e o até) por agenda_data_dita e dito no trecho, a pessoa por agenda_resolver_pessoa; o encaixe simulado agora pelo motor (agenda_propor os + fixar, sem gravar). Cabe → rascunho marcar:<os> {os, de, ate, pessoa, simulado} com a releitura ("Marco na agenda: Lenine (OS-00074), qui 29 e sex 30/10, você abre e fecha, Roberto os 2 dias."); o dia antes de o material estar garantido entra com o aviso e a pergunta ("… — mas "Compressor 12V SS65" só chega por volta de ter 06/10 (pronto qua 07/10). Marco mesmo assim?"; o *grava* é o sim), e a resposta traz aviso_material e pergunta. Não cabe → {ok:false, pergunta "… O primeiro dia que dá é sex 30/10. Marco nesse dia?"}. Fora de modo_proposta ligado: só a simulação ("ainda está em teste… Ficaria assim: …"), nada no rascunho. O *grava* chama agenda_marcar_os (via dono). FASE 7g (P3): com modo_explicar ligado, o dia pedido (p_quando) passa pela relação dita logo antes dele no trecho (_agenda_data_com_relacao: depois de quinta = o 1º dia útil depois; antes de sexta = o último antes; até sexta = de hoje até sexta; a partir de = a data), e a releitura diz a relação entre parênteses ("você disse depois de quinta"). Em sombra e desligado, a de antes, byte a byte.';

-- ── 4. A fonte da duração de uma alocação ────────────────────────────────────────────────────────────
-- Pelo que foi gravado na alocação (§3.1 item 2): a fonte (duracao_fonte, da 7a) e, na estimativa pelo orçamento, os dias e a mão de obra da suposição
-- duracao_orcamento (o P2 a grava com o número da hora). Dono e aceita: os dias ditos (os_planejamento.dias; OS sem linha é o caso comum: nulo, R9.12-3) e, só
-- quando a 7e corrige ou pode corrigir (vies_marcado diferente de 1, ou o viés ligado de verdade: R9.3-1), a frase do viés de agenda_meios_da_os com os dois
-- números; fora disso nenhuma chamada cara. Sem os dias (a sugerida, a de antes do porquê), o tamanho do bloco: os meios-dias de turno distintos das vigentes da
-- OS do mesmo lado (reserva com reserva).
create or replace function public._agenda_porque_fonte(p_aloc uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  a      public.agenda_alocacoes;
  v_dias numeric;
  v_mo   numeric;
  v_vies text;
begin
  select x.* into a from public.agenda_alocacoes x where x.id = p_aloc;
  if not found then
    return null;
  end if;
  if a.duracao_fonte = 'orcamento' then
    select (s #>> '{detalhe,dias}')::numeric, (s #>> '{detalhe,mo}')::numeric into v_dias, v_mo
      from jsonb_array_elements(case when jsonb_typeof(a.suposicoes) = 'array' then a.suposicoes else '[]'::jsonb end) s
     where s ->> 'codigo' = 'duracao_orcamento'
     limit 1;
  elsif a.duracao_fonte in ('dono', 'aceita') then
    v_dias := (select pl.dias from public.os_planejamento pl where pl.service_order_id = a.service_order_id);
    if coalesce((select pl.vies_marcado from public.os_planejamento pl where pl.service_order_id = a.service_order_id), 1) <> 1
       or public._agenda_margem_modo('vies') = 'ligado' then
      v_vies := public.agenda_meios_da_os(a.service_order_id, p_hoje) ->> 'texto_vies';
    end if;
  end if;
  if v_dias is null then
    v_dias := (select nullif(count(distinct (x.dia, x.turno)), 0)::numeric / 2
                 from public.agenda_alocacoes x
                where x.service_order_id = a.service_order_id and x.estado in ('publicada', 'fixada') and x.presenca = 'turno'
                  and (x.tipo = 'reserva') = (a.tipo = 'reserva'));
  end if;
  return jsonb_build_object('fonte', a.duracao_fonte, 'dias', trim_scale(v_dias), 'mo', v_mo,
                            'texto', public._agenda_duracao_fonte_texto(a.duracao_fonte, v_dias, v_mo, v_vies));
end;
$function$;

comment on function public._agenda_porque_fonte(uuid, date) is
  'Agenda de Produção (Fase 7g, P3; §3.1 item 2, §6.1, R9.3-1): de onde veio a duração de uma alocação, pelo que foi gravado nela — {fonte, dias, mo, texto}. Orçamento: os dias e a mão de obra da suposição duracao_orcamento; dono e aceita: os dias ditos e, só com vies_marcado diferente de 1 ou o viés ligado, a frase do viés da 7e; sem os dias, o tamanho do bloco (meios-dias de turno distintos ÷ 2). Alocação que não existe: nula.';

-- ── 5. A linha curta de uma marcação ─────────────────────────────────────────────────────────────────
-- §5.3 e §3.1 item 11 (AG7-28): a fonte da duração e as primeiras porque_motivos_max suposições que têm texto (duracao_orcamento vai pela fonte), na ordem
-- gravada (a do "1 motivo", P2), da 1ª alocação de turno do bloco (p_alocs = os ids das alocações). Lê o que foi gravado, não o estado de hoje. A marcação de
-- antes do porquê (suposicoes nula) diz isso.
create or replace function public._agenda_porque_linha(p_os uuid, p_alocs jsonb, p_hoje date)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  a     public.agenda_alocacoes;
  v_f   jsonb;
  v_mot text[];
begin
  select x.* into a from public.agenda_alocacoes x
   where x.service_order_id = p_os and x.estado in ('publicada', 'fixada')
     and x.id in (select (e #>> '{}')::uuid from jsonb_array_elements(case when jsonb_typeof(p_alocs) = 'array' then p_alocs else '[]'::jsonb end) e
                   where jsonb_typeof(e) = 'string')
   order by x.presenca <> 'turno', x.dia, x.turno = 'tarde', x.payee_id is not distinct from public._agenda_dono(null), x.id
   limit 1;
  if not found then
    return null;
  end if;
  if a.suposicoes is null then
    return 'de antes de eu guardar o porquê';
  end if;
  v_f := public._agenda_porque_fonte(a.id, p_hoje);
  v_mot := array(select z.t from (select public._agenda_suposicao_texto(s ->> 'codigo', s -> 'detalhe') as t, u.o
                                    from jsonb_array_elements(a.suposicoes) with ordinality u(s, o)) z
                  where z.t is not null order by z.o limit (public._agenda_cfg()).porque_motivos_max);
  return nullif(concat_ws('; ', v_f ->> 'texto', nullif(array_to_string(v_mot, '; '), '')), '');
end;
$function$;

comment on function public._agenda_porque_linha(uuid, jsonb, date) is
  'Agenda de Produção (Fase 7g, P3; §5.3, §3.1 item 11, AG7-28): a linha curta de uma marcação — a fonte da duração (_agenda_porque_fonte) e as primeiras porque_motivos_max suposições com texto, na ordem gravada, da 1ª alocação de turno vigente do bloco (p_alocs = [ids]). Gravada antes do porquê: "de antes de eu guardar o porquê". Nenhuma vigente nos ids: nula.';

-- ── 6. O porquê de uma OS ────────────────────────────────────────────────────────────────────────────
-- §5.3 e §6.2. Os estados: fora_da_carteira (a OS saiu da carteira); marcada (compromisso vigente de hoje em diante) ou reservada (só reserva), pela 1ª
-- alocação de turno do bloco — quem marcou (_agenda_quem_marcou: a alocação e a ação que a criou), a fonte, as suposições gravadas, o critério da pessoa (7c),
-- o degrau e a zona da ação que a criou; e fora (na carteira, sem nada vigente): o motivo de agora (_agenda_classe_agora, o texto da carteira) e a pergunta
-- aberta dela (a linha de agenda_perguntas_em_ordem, com o número da Decisão). SECURITY DEFINER com porta (molde de agenda_perguntas_em_ordem): quem a chamar de
-- uma leitura invoker com login (a P7) não precisa de porta nas peças. Nunca devolve data de pronto (AG7-32): só os dias marcados.
create or replace function public._agenda_porque_da_os(p_os uuid, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  c_max   constant int := 600;   -- estrutural: o teto do porquê de uma OS (§6.2)
  v_uid   uuid := auth.uid();
  v_papel text;
  so      record;
  v_rot   text;
  v_tipo  text;
  a       public.agenda_alocacoes;
  ac      public.agenda_acoes;
  v_alocs jsonb;
  v_dias  date[];
  v_pess  text;
  v_quem  text;
  v_f     jsonb;
  v_m     jsonb;
  v_sup   jsonb;
  v_crit  text;
  v_deg   text;
  v_mot   text;
  v_perg  text;
  v_txt   text;
begin
  -- Quem vê: com login, só admin/financeiro; sem login, só o service_role, ou quem chama de dentro, sem JWT (molde de agenda_perguntas_em_ordem)
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'O porquê da agenda é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'O porquê da agenda é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;
  if p_os is null or p_hoje is null or p_agora is null then
    raise exception '_agenda_porque_da_os: sem a OS, o dia ou a hora.' using errcode = '22004';
  end if;
  select s.id, s.status into so from public.service_orders s where s.id = p_os;
  if not found then
    raise exception 'Não encontrei esse serviço.' using errcode = 'P0002';
  end if;
  v_rot := public._agenda_rotulo_da_os(p_os);

  if not exists (select 1 from public.os_carteira(p_hoje) k where k.service_order_id = p_os) then
    return jsonb_build_object('estado', 'fora_da_carteira', 'quem', null, 'quem_texto', null, 'fonte', null, 'fonte_texto', null, 'suposicoes', '[]'::jsonb,
                              'criterio_texto', null, 'degrau_texto', null, 'zona', null, 'motivo_fora', null,
                              'texto', format('Essa OS não está mais na carteira (%s).', public._agenda_status_texto(so.status)));
  end if;

  -- o bloco vigente de hoje em diante: o compromisso; sem ele, a reserva
  select case when bool_or(x.tipo <> 'reserva') then 'compromisso' when count(*) > 0 then 'reserva' end into v_tipo
    from public.agenda_alocacoes x
   where x.service_order_id = p_os and x.estado in ('publicada', 'fixada') and x.dia >= p_hoje;

  if v_tipo is null then
    v_mot := nullif(btrim(public._agenda_classe_agora(p_os, p_hoje) ->> 'texto'), '');
    v_perg := (select e ->> 'linha' from jsonb_array_elements(public.agenda_perguntas_em_ordem(p_hoje, p_agora)) e
                where e ->> 'os' = p_os::text and nullif(btrim(e ->> 'linha'), '') is not null
                order by (e ->> 'ordem')::int limit 1);
    return jsonb_build_object('estado', 'fora', 'quem', null, 'quem_texto', null, 'fonte', null, 'fonte_texto', null, 'suposicoes', '[]'::jsonb,
                              'criterio_texto', null, 'degrau_texto', null, 'zona', null, 'motivo_fora', v_mot,
                              'texto', public._agenda_corta(v_rot || ' ficou de fora' || coalesce(': ' || v_mot, '') || '.' || coalesce(' ' || v_perg, ''), c_max));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('payee_id', x.payee_id, 'nome', public._agenda_nome_curto(py.name), 'dia', x.dia, 'turno', x.turno,
                                               'presenca', x.presenca) order by x.dia, x.turno = 'tarde', py.name, x.id), '[]'::jsonb),
         array_agg(distinct x.dia)
    into v_alocs, v_dias
    from public.agenda_alocacoes x join public.payees py on py.id = x.payee_id
   where x.service_order_id = p_os and x.estado in ('publicada', 'fixada') and x.dia >= p_hoje and (x.tipo = 'reserva') = (v_tipo = 'reserva');
  select x.* into a from public.agenda_alocacoes x
   where x.service_order_id = p_os and x.estado in ('publicada', 'fixada') and x.dia >= p_hoje and (x.tipo = 'reserva') = (v_tipo = 'reserva')
   order by x.presenca <> 'turno', x.dia, x.turno = 'tarde', x.payee_id is not distinct from public._agenda_dono(null), x.id
   limit 1;
  select c.* into ac from public.agenda_acoes c where c.id = a.acao_id;
  v_quem := public._agenda_quem_marcou(ac.origem, a.origem);
  v_pess := public._agenda_gestor_pessoas(v_alocs);
  v_txt := v_rot || ': '
           || case when v_tipo = 'reserva' then case when v_quem = 'dono' then 'você reservou ' else 'reservei ' end
                   when v_quem = 'dono' then 'você marcou ' else 'marquei ' end
           || public._agenda_dias_texto(v_dias) || ' com ' || v_pess
           || case when v_tipo = 'reserva' and nullif(btrim(a.condicao), '') is not null then ', ' || btrim(a.condicao) else '' end || '.';

  if a.suposicoes is null then
    -- de antes do porquê (§6.2): a duração é a de hoje, e o texto diz que é de hoje
    v_m := public.agenda_meios_da_os(p_os, p_hoje);
    v_f := jsonb_build_object('fonte', v_m ->> 'fonte',
                              'texto', public._agenda_duracao_fonte_texto(v_m ->> 'fonte', (v_m ->> 'dias')::numeric, null, v_m ->> 'texto_vies'));
    v_txt := v_txt || ' Essa marcação é de antes de eu guardar o porquê' || coalesce('; a duração de hoje: ' || (v_f ->> 'texto'), '') || '.';
    v_sup := '[]'::jsonb;
  else
    v_f := public._agenda_porque_fonte(a.id, p_hoje);
    v_sup := coalesce((select jsonb_agg(jsonb_build_object('codigo', z.c, 'texto', z.t) order by z.o)
                         from (select s ->> 'codigo' as c, public._agenda_suposicao_texto(s ->> 'codigo', s -> 'detalhe') as t, u.o
                                 from jsonb_array_elements(a.suposicoes) with ordinality u(s, o)) z
                        where z.t is not null), '[]'::jsonb);
    v_crit := public._agenda_criterio_texto(a.criterio);
    v_deg := public._agenda_degrau_texto(coalesce(ac.degrau, a.degrau));
    v_txt := v_txt
             || coalesce(' Duração: ' || (v_f ->> 'texto') || '.', '')
             || case when v_quem = 'gestor' and jsonb_array_length(v_sup) > 0
                     then ' Contei: ' || (select string_agg(e ->> 'texto', '; ' order by o) from jsonb_array_elements(v_sup) with ordinality t(e, o)) || '.'
                     else '' end
             || case when v_quem = 'gestor' and v_crit is not null
                     then format(' %s: %s.', (select public._agenda_nome_curto(py.name) from public.payees py where py.id = a.payee_id), v_crit)
                     else '' end
             || coalesce(' Última mudança: ' || v_deg || '.', '')
             || case when v_quem = 'gestor' then ' Se algo estiver errado, me diga o certo.' else '' end;
  end if;
  return jsonb_build_object('estado', case when v_tipo = 'reserva' then 'reservada' else 'marcada' end,
                            'quem', v_quem, 'quem_texto', case when v_quem = 'dono' then 'marcado por você' else 'marcado pelo gestor' end,
                            'fonte', v_f ->> 'fonte', 'fonte_texto', v_f ->> 'texto', 'suposicoes', v_sup,
                            'criterio_texto', v_crit, 'degrau_texto', v_deg, 'zona', ac.zona, 'motivo_fora', null,
                            'texto', public._agenda_corta(v_txt, c_max));
end;
$function$;

comment on function public._agenda_porque_da_os(uuid, date, timestamptz) is
  'Agenda de Produção (Fase 7g, P3; §5.3, §6.2): o porquê de uma OS — {estado: marcada|reservada|fora|fora_da_carteira, quem, quem_texto, fonte, fonte_texto, suposicoes [{codigo, texto}], criterio_texto, degrau_texto, zona, motivo_fora, texto (≤ 600)}. Marcada e reservada: pelo que foi gravado na 1ª alocação de turno vigente de hoje em diante e na ação que a criou; de antes do porquê, a duração de hoje e o aviso. Fora: o motivo de agora (_agenda_classe_agora) e a pergunta aberta dela (agenda_perguntas_em_ordem). SECURITY DEFINER; com login, só admin/financeiro (42501 para o resto); sem login, o service_role. OS que não existe: P0002.';

-- ── 7. Como pensei a semana ──────────────────────────────────────────────────────────────────────────
-- §5.3, §6.3 com o R9: a semana de p_de (sem ele, a que vem), em 6 partes nesta ordem, cada uma lida à parte (begin … exception: falhou, incompleto = true e
-- a parte diz que não conseguiu ler; query_canceled não cai ali). Com o freio (gestor_so_propor), a 1ª linha diz isso e, com o gestor em teste, o "Eu marcaria"
-- vem logo depois do "Marquei", da última conta do gestor (agenda_gestor_dia.sombra, as chaves que _agenda_ver_gestor lê; só o que toca a semana) — sem isso
-- "Marquei: nada" seria verdade e enganaria (R9.6). A folga sai da grade do motor (_agenda_grade_de_agora, uma vez), nos 2 ramos do R9.7: com a chave
-- teto_equipe, Σ teto100 da equipe − teto_equipe da semana e as reservas usam max(0, Σ(uso_c + uso_r) − teto_equipe); sem ela (o freio), Σ(teto100 − teto80)
-- e Σ max(0, uso_c + uso_r − teto80). A equipe é a grade sem você (o 7a P5). "De fora" vem do painel (uma vez: _agenda_painel e _agenda_lista_de-like, nunca
-- _agenda_classe_agora por OS, R9.5-11). "Preciso de você" é a linha de agenda_perguntas_em_ordem como vem: com o número, "· Decisão N: …" (o N é o de
-- *agenda pendências*, R9.7); sem número, "• …". O texto corta de baixo para cima pelas listas, sem tirar a 1ª linha de nenhuma parte, depois tira o porquê
-- das marcadas e das reservadas, e só então corta duro. A falha do porquê de um item tira só o porquê dele ("não consegui ler o porquê agora"). Desligado: {modo}.
create or replace function public.agenda_como_pensei(p_de date default null, p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  c_nomes   constant int := 3;   -- estrutural: quantos nomes cada grupo de "De fora" cita (§5.3)
  c_riscos  constant int := 3;   -- estrutural: "até 3" riscos (§5.3)
  cf        public.agenda_config := public._agenda_cfg();
  v_uid     uuid := auth.uid();
  v_papel   text;
  v_de      date;
  v_fim     date;
  v_ult     date;
  v_rot     text;
  v_falhas  text[] := '{}';
  r         record;
  e         jsonb;
  x         jsonb;
  v_os      uuid[] := '{}';
  v_dono    uuid := public._agenda_dono(null);
  v_curto   boolean := false;
  v_itc     text;
  v_sema    boolean;
  -- marcadas
  v_marc    jsonb := '[]'::jsonb;
  v_mi      text[] := '{}';
  v_mmais   int := 0;
  v_mic     text[] := '{}';
  v_quem    text;
  v_fonte   text;
  v_pq      text;
  v_ids     jsonb;
  v_it      text;
  -- eu marcaria
  v_sdia    date;
  v_s       jsonb;
  v_emc     text;
  v_em      text[] := '{}';
  v_emmais  int := 0;
  -- reservadas
  v_resv    jsonb := '[]'::jsonb;
  v_ri      text[] := '{}';
  v_rmais   int := 0;
  v_ric     text[] := '{}';
  v_rnomes  text[] := '{}';
  -- fora
  v_pn      jsonb;
  v_prox    jsonb;
  v_grupos  jsonb := '{}'::jsonb;
  v_g       text;
  v_fora    jsonb := '[]'::jsonb;
  v_fo      text[] := '{}';
  v_fmais   int := 0;
  -- folga
  v_ctx     jsonb;
  v_nw      int;
  v_w       int;
  v_dn      int;
  v_s100    int;
  v_s80     int;
  v_uso     int;
  v_te      int;
  v_fg      int;
  v_usado   int;
  v_pct     int;
  v_cheios  text[] := '{}';
  v_folga   jsonb;
  v_fl      text;
  -- riscos
  v_rc      jsonb := '[]'::jsonb;
  v_rk      text[] := '{}';
  -- preciso de você
  v_prec    jsonb := '[]'::jsonb;
  v_pqs     text[] := '{}';
  v_ptot    int := 0;
  v_pmais   int := 0;
  -- o texto
  v_l       text[];
  v_txt     text;
begin
  -- Quem vê: com login, só admin/financeiro; sem login, só o service_role, ou quem chama de dentro, sem JWT (molde de agenda_perguntas_em_ordem)
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'Como pensei a agenda é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'Como pensei a agenda é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_como_pensei: sem o dia ou a hora.' using errcode = '22004';
  end if;
  if cf.modo_explicar = 'desligado' then
    return jsonb_build_object('modo', 'desligado');
  end if;

  v_de := case when p_de is null then p_hoje + (8 - extract(isodow from p_hoje)::int) else p_de - (extract(isodow from p_de)::int - 1) end;
  v_fim := v_de + 6;
  v_ult := v_de + case when cf.sabado_util then 5 else 4 end;
  v_rot := case when to_char(v_de, 'MM') = to_char(v_ult, 'MM') then to_char(v_de, 'DD') else to_char(v_de, 'DD/MM') end || ' a ' || to_char(v_ult, 'DD/MM');
  v_sema := public._agenda_gestor_modo('marcar') = 'sombra';
  -- as OS com alguma alocação vigente na semana (compromisso ou reserva): o que não vai em "De fora", lido uma vez, fora das partes (a falha de uma parte não muda
  -- as outras)
  v_os := array(select distinct a.service_order_id from public.agenda_alocacoes a where a.estado in ('publicada', 'fixada') and a.dia between v_de and v_fim);

  -- 1. o que marquei: as OS com compromisso vigente na semana, na ordem do 1º meio-dia
  begin
    for r in
      select a.service_order_id as os, so.service_order_number as numero, public._agenda_nome_curto(cl.name) as curto,
             array_agg(distinct a.dia order by a.dia) as dias,
             jsonb_agg(jsonb_build_object('payee_id', a.payee_id, 'nome', public._agenda_nome_curto(py.name), 'dia', a.dia, 'turno', a.turno,
                                          'presenca', a.presenca) order by a.dia, a.turno = 'tarde', py.name, a.id) as alocs,
             jsonb_agg(to_jsonb(a.id::text) order by a.dia, a.turno = 'tarde', a.id) as ids,
             min(a.dia::text || case when a.turno = 'tarde' then '1' else '0' end) as primeiro
        from public.agenda_alocacoes a
        join public.payees py on py.id = a.payee_id
        join public.service_orders so on so.id = a.service_order_id
        left join public.clients cl on cl.id = so.client_id
       where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia between v_de and v_fim
       group by a.service_order_id, so.service_order_number, cl.name
       order by min(a.dia::text || case when a.turno = 'tarde' then '1' else '0' end), so.service_order_number
    loop
      select public._agenda_quem_marcou(c.origem, x2.origem), x2.duracao_fonte into v_quem, v_fonte
        from public.agenda_alocacoes x2 left join public.agenda_acoes c on c.id = x2.acao_id
       where x2.id in (select (i #>> '{}')::uuid from jsonb_array_elements(r.ids) i)
       order by x2.presenca <> 'turno', x2.dia, x2.turno = 'tarde', x2.payee_id is not distinct from v_dono, x2.id
       limit 1;
      begin
        v_pq := public._agenda_porque_linha(r.os, r.ids, p_hoje);
      exception when others then
        v_pq := 'não consegui ler o porquê agora';
        if not ('porque' = any (v_falhas)) then
          v_falhas := v_falhas || 'porque'::text;
        end if;
      end;
      v_itc := coalesce(r.curto || ' (' || r.numero || ')', r.numero) || ' ' || public._agenda_dias_texto(r.dias)
              || ' com ' || public._agenda_gestor_pessoas(r.alocs) || case when v_quem = 'dono' then ' (você marcou)' else '' end;
      v_it := v_itc || coalesce(' — ' || v_pq, '');
      v_marc := v_marc || jsonb_build_object('os', r.os, 'numero', r.numero, 'cliente_curto', r.curto, 'dias', to_jsonb(r.dias),
                                             'pessoas', public._agenda_gestor_pessoas(r.alocs), 'quem', v_quem, 'fonte', v_fonte, 'porque', v_pq,
                                             'texto', v_it);
      if cardinality(v_mi) < cf.como_pensei_itens_max then
        v_mi := v_mi || v_it;
        v_mic := v_mic || v_itc;
      else
        v_mmais := v_mmais + 1;
      end if;
    end loop;
  exception when others then
    v_falhas := v_falhas || 'marcadas'::text;
    v_marc := '[]'::jsonb; v_mi := '{}'; v_mic := '{}'; v_mmais := 0;
  end;

  -- 1b. com o gestor em teste: o que eu marcaria (a última conta do gestor, só o que toca a semana; as chaves de _agenda_ver_gestor)
  if v_sema then
    begin
      select g.dia, g.sombra into v_sdia, v_s from public.agenda_gestor_dia g
       where g.dia <= p_hoje and g.sombra <> '{}'::jsonb order by g.dia desc limit 1;
      if v_s is null then
        v_emc := 'Eu marcaria: ainda não fiz a conta (faço todo dia útil no fim da tarde).';
      else
        for x in select y from jsonb_array_elements(coalesce(v_s -> 'itens', '[]'::jsonb)) with ordinality t(y, o)
                  where (y ->> 'de')::date <= v_fim and coalesce((y ->> 'ate')::date, (y ->> 'de')::date) >= v_de order by o loop
          v_em := v_em || format('• %s: %s, %s — %s (%s).', x ->> 'cliente', public._agenda_gestor_faixa((x ->> 'de')::date, (x ->> 'ate')::date),
                                 x ->> 'pessoas', public._agenda_dias((x ->> 'dias')::numeric),
                                 case x ->> 'fonte' when 'orcamento' then 'estimativa minha' else 'você disse' end);
        end loop;
        for x in select y from jsonb_array_elements(coalesce(v_s -> 'reservas', '[]'::jsonb)) with ordinality t(y, o)
                  where (y ->> 'de')::date <= v_fim and coalesce((y ->> 'ate')::date, (y ->> 'de')::date) >= v_de order by o loop
          v_em := v_em || format('• %s: reservaria %s, %s.', x ->> 'cliente', public._agenda_gestor_faixa((x ->> 'de')::date, (x ->> 'ate')::date),
                                 x ->> 'pessoas');
        end loop;
        v_emc := 'Eu marcaria' || case when v_sdia <> p_hoje then format(' (pela conta de %s)', public._dia_curto(v_sdia)) else '' end
                 || case when cardinality(v_em) = 0 then ': nada nessa semana.' else ':' end;
      end if;
    exception when others then
      v_falhas := v_falhas || 'eu_marcaria'::text;
      v_emc := 'Eu marcaria: não consegui ler agora.'; v_em := '{}';
    end;
  end if;

  -- 2. o que reservei: as reservas vigentes da semana, com a condição gravada
  begin
    for r in
      select a.service_order_id as os, so.service_order_number as numero, public._agenda_nome_curto(cl.name) as curto,
             array_agg(distinct a.dia order by a.dia) as dias,
             jsonb_agg(jsonb_build_object('payee_id', a.payee_id, 'nome', public._agenda_nome_curto(py.name), 'dia', a.dia, 'turno', a.turno,
                                          'presenca', a.presenca) order by a.dia, a.turno = 'tarde', py.name, a.id) as alocs,
             jsonb_agg(to_jsonb(a.id::text) order by a.dia, a.turno = 'tarde', a.id) as ids,
             (array_agg(nullif(btrim(a.condicao), '') order by a.dia, a.turno = 'tarde', a.id) filter (where nullif(btrim(a.condicao), '') is not null))[1] as condicao
        from public.agenda_alocacoes a
        join public.payees py on py.id = a.payee_id
        join public.service_orders so on so.id = a.service_order_id
        left join public.clients cl on cl.id = so.client_id
       where a.estado in ('publicada', 'fixada') and a.tipo = 'reserva' and a.dia between v_de and v_fim
       group by a.service_order_id, so.service_order_number, cl.name
       order by min(a.dia::text || case when a.turno = 'tarde' then '1' else '0' end), so.service_order_number
    loop
      begin
        v_pq := public._agenda_porque_linha(r.os, r.ids, p_hoje);
      exception when others then
        v_pq := 'não consegui ler o porquê agora';
        if not ('porque' = any (v_falhas)) then
          v_falhas := v_falhas || 'porque'::text;
        end if;
      end;
      v_itc := coalesce(r.curto || ' (' || r.numero || ')', r.numero) || ' ' || public._agenda_dias_texto(r.dias) || ' com ' || public._agenda_gestor_pessoas(r.alocs);
      v_it := v_itc || coalesce(', ' || r.condicao, '') || coalesce(' — ' || v_pq, '');
      v_resv := v_resv || jsonb_build_object('os', r.os, 'numero', r.numero, 'cliente_curto', r.curto, 'dias', to_jsonb(r.dias),
                                             'pessoas', public._agenda_gestor_pessoas(r.alocs), 'condicao', r.condicao, 'porque', v_pq, 'texto', v_it);
      if cardinality(v_ri) < cf.como_pensei_itens_max then
        v_ri := v_ri || v_it;
        v_ric := v_ric || v_itc;
      else
        v_rmais := v_rmais + 1;
      end if;
    end loop;
  exception when others then
    v_falhas := v_falhas || 'reservadas'::text;
    v_resv := '[]'::jsonb; v_ri := '{}'; v_ric := '{}'; v_rmais := 0;
  end;

  -- 3. o que ficou de fora: a carteira sem nada vigente na semana, pelos grupos do painel (uma leitura só), na ordem da §5.3; cada grupo com até 3 nomes e
  -- o 1º com o detalhe. A OS com algo vigente em outra semana vai em "em outra semana", seja qual for o grupo (a OS com plano é "programada", que o painel põe no
  -- grupo fora); o grupo fora sem nada de hoje em diante (a concluída, a programada só no passado) não tem lugar aqui (v_g nulo).
  begin
    v_pn := public._agenda_painel(p_hoje);
    select coalesce(jsonb_object_agg(z.os, z.dia), '{}'::jsonb) into v_prox
      from (select a.service_order_id::text as os, min(a.dia) as dia from public.agenda_alocacoes a
             where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and not (a.dia between v_de and v_fim)
             group by a.service_order_id) z;
    for e in select y from jsonb_array_elements(coalesce(v_pn -> 'oss', '[]'::jsonb)) y order by (y ->> 'ordem')::int loop
      continue when (e ->> 'os')::uuid = any (v_os);
      v_g := case when v_prox ? (e ->> 'os') or e ->> 'grupo' = 'marcado' then 'outra_semana'
                  when e ->> 'grupo' in ('travado', 'quase') then 'peca'
                  when e ->> 'grupo' = 'esperando' then 'voce'
                  when e ->> 'grupo' = 'parado' then 'cliente'
                  when e ->> 'grupo' in ('pronto', 'andamento') then 'sem_lugar'
                  when e ->> 'grupo' = 'espera' then 'espera' end;
      continue when v_g is null;
      v_grupos := jsonb_set(v_grupos, array[v_g], coalesce(v_grupos -> v_g, '[]'::jsonb) || jsonb_build_object('o', e, 'sufixo',
        case when jsonb_array_length(coalesce(v_grupos -> v_g, '[]'::jsonb)) > 0 then null
             when v_g = 'peca' then public._agenda_restricao_curta(e -> 'principal')
             when v_g = 'voce' then replace(e ->> 'estado_texto', ' e nunca virou OS', ', nunca virou OS')
             when v_g = 'cliente' then case when e ->> 'estado' = 'sem_sinal' then 'sinal' end
             when v_g = 'outra_semana' then 'a partir de ' || public._dia_curto(coalesce((v_prox ->> (e ->> 'os'))::date, (e ->> 'agendada_de')::date))
             when v_g = 'espera' then substring(e ->> 'estado_texto' from 'até [^ ]+ [^ ]+') end));
    end loop;
    for r in select k.g, k.rotulo from (values (1, 'peca', 'esperando peça'), (2, 'voce', 'esperando você'), (3, 'cliente', 'esperando o cliente'),
                                               (4, 'sem_lugar', 'prontos sem lugar'), (5, 'outra_semana', 'em outra semana'), (6, 'espera', 'em espera')) k(n, g, rotulo)
              where v_grupos ? k.g order by k.n loop
      v_it := r.rotulo || ' — ' || public._agenda_nomes(v_grupos -> r.g, c_nomes);
      v_fo := v_fo || v_it;
      v_fora := v_fora || jsonb_build_object('grupo', r.g, 'texto', v_it, 'oss',
                  (select jsonb_agg(jsonb_build_object('os', y #>> '{o,os}', 'numero', y #>> '{o,numero}', 'cliente_curto', y #>> '{o,curto}') order by o)
                     from jsonb_array_elements(v_grupos -> r.g) with ordinality t(y, o)));
    end loop;
  exception when others then
    v_falhas := v_falhas || 'fora'::text;
    v_fora := '[]'::jsonb; v_fo := '{}';
  end;

  -- 4. a folga guardada na semana, da grade do motor (R9.7: os 2 ramos; a equipe é a grade sem você)
  begin
    v_rnomes := array(select coalesce(public._agenda_nome_curto(cl.name), so.service_order_number)
                        from public.agenda_alocacoes a join public.service_orders so on so.id = a.service_order_id left join public.clients cl on cl.id = so.client_id
                       where a.estado in ('publicada', 'fixada') and a.tipo = 'reserva' and a.dia between v_de and v_fim
                       group by so.id, so.service_order_number, cl.name order by min(a.dia), so.service_order_number);
    v_ctx := public._agenda_grade_de_agora(p_hoje) -> 'ctx';
    v_nw := (v_ctx ->> 'nw')::int;
    v_dn := coalesce((v_ctx ->> 'dono')::int, 0);
    v_w := (v_de - (v_ctx ->> 'seg')::date) / 7 + 1;
    if v_nw is null or v_w < 1 or v_w > v_nw then
      v_fl := 'Folga: essa semana ainda não está na grade.';
      v_folga := jsonb_build_object('ramo', null);
    else
      select coalesce(sum(z.t100), 0), coalesce(sum(z.t80), 0), coalesce(sum(z.uc + z.ur), 0),
             coalesce(sum(greatest(z.t100 - z.t80, 0)), 0), coalesce(sum(greatest(z.uc + z.ur - z.t80, 0)), 0),
             coalesce(array_agg(z.nome order by z.p) filter (where z.t100 > 0 and z.uc + z.ur >= z.t100), '{}')
        into v_s100, v_s80, v_uso, v_fg, v_usado, v_cheios
        from (select p.p, public._agenda_nome_curto(v_ctx -> 'nomes' ->> (p.p - 1)) as nome,
                     coalesce((v_ctx -> 'teto100' ->> ((p.p - 1) * v_nw + v_w - 1))::int, 0) as t100,
                     coalesce((v_ctx -> 'teto80' ->> ((p.p - 1) * v_nw + v_w - 1))::int, 0) as t80,
                     coalesce((v_ctx -> 'uso_c' ->> ((p.p - 1) * v_nw + v_w - 1))::int, 0) as uc,
                     coalesce((v_ctx -> 'uso_r' ->> ((p.p - 1) * v_nw + v_w - 1))::int, 0) as ur
                from generate_series(1, coalesce((v_ctx ->> 'np')::int, 0)) p(p)
               where p.p <> v_dn) z;
      if v_ctx ? 'teto_equipe' then
        v_te := coalesce((v_ctx -> 'teto_equipe' ->> (v_w - 1))::int, 0);
        v_fg := greatest(v_s100 - v_te, 0);
        v_usado := greatest(v_uso - v_te, 0);
      end if;
      v_usado := least(v_usado, v_fg);
      v_pct := case when v_s100 > 0 then round(100 * v_fg::numeric / v_s100)::int end;
      v_folga := jsonb_build_object('ramo', case when v_ctx ? 'teto_equipe' then 'teto_equipe' else 'pessoa' end, 'meios', v_fg, 'usado', v_usado,
                                    'pct', v_pct, 'base', v_s100);
      v_fl := case
        when v_s100 = 0 then 'Folga: ninguém da equipe está na conta dessa semana.'
        when v_fg = 0 then 'Folga: nenhuma nessa semana.'
        else format('Folga: guardei %s da equipe para imprevisto (%s%% da semana)', public._agenda_meios_texto(v_fg), v_pct)
             || case when v_usado > 0
                     then format('; %s já %s %s', public._agenda_meios_texto(v_usado), case when v_usado >= 4 then 'estão' else 'está' end,
                                 case when cardinality(v_rnomes) = 0 then 'ocupado'
                                      when cardinality(v_rnomes) = 1 then 'com a reserva de ' || v_rnomes[1]
                                      else 'com as reservas de ' || public._agenda_lista(v_rnomes, c_nomes) end)
                     else '' end
             || '.' end;
    end if;
  exception when others then
    v_falhas := v_falhas || 'folga'::text;
    v_fl := 'Folga: não consegui ler agora.'; v_folga := null; v_cheios := '{}';
  end;

  -- 5. os riscos (até 3, na ordem da data): o "compre até" das marcadas e reservadas, junto por fornecedor; a suposição que costuma errar e não foi o motivo da
  -- linha (uma por OS); quem está com a semana cheia
  begin
    select coalesce(jsonb_agg(z.j order by z.d, z.k, z.o), '[]'::jsonb) into v_rc from (
      select m.ate as d, 1 as k, row_number() over (order by m.forn) as o,
             jsonb_build_object('tipo', 'compre_ate', 'dia', m.ate, 'texto',
               case when m.ate < p_hoje
                    then format('o "compre até" de %s%s para %s venceu %s (compre hoje)', public._agenda_lista(m.itens, 2), coalesce(' (' || m.forn || ')', ''),
                                public._agenda_lista(m.clis, 2), public._dia_curto(m.ate))
                    else format('compre %s%s até %s para %s', public._agenda_lista(m.itens, 2), coalesce(' (' || m.forn || ')', ''),
                                public._dia_curto(m.ate), public._agenda_lista(m.clis, 2)) end) as j
        from (select nullif(btrim(om.fornecedor_nome), '') as forn, min(om.compre_ate) as ate,
                     array_agg(distinct public._agenda_corta(om.descricao, 40)) as itens,
                     array_agg(distinct coalesce(public._agenda_nome_curto(cl.name), so.service_order_number)) as clis
                from public.os_material om
                join public.service_orders so on so.id = om.service_order_id
                left join public.clients cl on cl.id = so.client_id
               where om.service_order_id = any (v_os) and om.critico and om.situacao = 'falta' and om.compre_ate is not null
               group by nullif(btrim(om.fornecedor_nome), '')) m
      union all
      select s.d, 2, s.o, jsonb_build_object('tipo', 'suposicao', 'codigo', s.codigo, 'dia', s.d, 'texto', s.curto || ' — ' || s.t)
        from (select distinct on (b.os) b.os, b.d, b.curto, b.o, sp.codigo, sp.t
                from (select y.os, y.d, y.curto, y.o, y.sup
                        from (select (i ->> 'os')::uuid as os, (i -> 'dias' ->> 0)::date as d, coalesce(i ->> 'cliente_curto', i ->> 'numero') as curto, o,
                                     (select x3.suposicoes from public.agenda_alocacoes x3
                                       where x3.service_order_id = (i ->> 'os')::uuid and x3.estado in ('publicada', 'fixada') and x3.dia between v_de and v_fim
                                         and x3.suposicoes is not null
                                       order by x3.presenca <> 'turno', x3.dia, x3.turno = 'tarde', x3.payee_id is not distinct from v_dono, x3.id limit 1) as sup
                                from jsonb_array_elements(v_marc || v_resv) with ordinality t(i, o)) y
                       where jsonb_typeof(y.sup) = 'array') b
                cross join lateral (
                  select q.codigo, q.t, q.n from (
                    select s2 ->> 'codigo' as codigo, public._agenda_suposicao_texto(s2 ->> 'codigo', s2 -> 'detalhe') as t, u.n,
                           count(*) filter (where public._agenda_suposicao_texto(s2 ->> 'codigo', s2 -> 'detalhe') is not null) over (order by u.n) as k
                      from jsonb_array_elements(b.sup) with ordinality u(s2, n)) q
                   where q.t is not null and q.k > cf.porque_motivos_max and q.codigo in ('prazo_padrao_peca', 'local_suposto', 'bem_disponivel')) sp
               order by b.os, sp.n) s
      union all
      select v_fim, 3, c.o, jsonb_build_object('tipo', 'semana_cheia', 'dia', null, 'texto', c.nome || ' está com a semana cheia')
        from unnest(v_cheios) with ordinality c(nome, o)
    ) z;
    v_rc := coalesce((select jsonb_agg(y order by o) from jsonb_array_elements(v_rc) with ordinality t(y, o) where o <= c_riscos), '[]'::jsonb);
    v_rk := array(select y ->> 'texto' from jsonb_array_elements(v_rc) with ordinality t(y, o) order by o);
  exception when others then
    v_falhas := v_falhas || 'riscos'::text;
    v_rc := '[]'::jsonb; v_rk := '{}';
  end;

  -- 6. o que preciso de você: as primeiras como_pensei_perguntas de agenda_perguntas_em_ordem (7f), menos as que você já escolheu, com a linha como vem
  begin
    for e in select y from jsonb_array_elements(public.agenda_perguntas_em_ordem(p_hoje, p_agora)) y
                       join public.agenda_perguntas q on q.id = (y ->> 'id')::uuid
              where q.opcao_escolhida is null and nullif(btrim(y ->> 'linha'), '') is not null
              order by (y ->> 'ordem')::int loop
      v_ptot := v_ptot + 1;
      continue when v_ptot > cf.como_pensei_perguntas;
      v_prec := v_prec || jsonb_build_object('id', e -> 'id', 'os', e -> 'os', 'n', e -> 'n', 'linha', e ->> 'linha');
      v_pqs := v_pqs || (case when jsonb_typeof(e -> 'n') = 'number' then '· ' else '• ' end || (e ->> 'linha'));
    end loop;
    v_pmais := greatest(v_ptot - cardinality(v_pqs), 0);
  exception when others then
    v_falhas := v_falhas || 'precisa'::text;
    v_prec := '[]'::jsonb; v_pqs := '{}'; v_ptot := -1; v_pmais := 0;
  end;

  -- O texto: corta de baixo para cima pelas listas (Preciso de você, Riscos, De fora, Reservei, Eu marcaria, Marquei), sem tirar a 1ª linha de nenhuma parte;
  -- com as listas no 1º item, as marcadas e as reservadas ficam na forma curta (sem o porquê e a condição); só então o corte duro (_agenda_corta)
  loop
    v_l := '{}';
    if cf.gestor_so_propor then
      v_l := v_l || 'Você pediu *gestor, só propor*: eu só sugiro.'::text;
    end if;
    v_l := v_l || (case when cf.modo_explicar = 'sombra' then 'Em teste: ' else '' end || format('Como pensei a semana de %s:', v_rot));
    v_l := v_l || case when 'marcadas' = any (v_falhas) then 'Marquei: não consegui ler agora.'
                       when cardinality(v_mi) = 0 then 'Marquei: nada ainda nessa semana.'
                       else 'Marquei: ' || array_to_string(v_mi, '. ')
                            || case when v_mmais > 0 then format(' (e mais %s em *agenda semana que vem*)', v_mmais) else '' end || '.' end;
    if v_emc is not null then
      v_l := v_l || v_emc;
      v_l := v_l || v_em;
      if v_emmais > 0 then
        v_l := v_l || format('(e mais %s em *agenda gestor*)', v_emmais);
      end if;
    end if;
    if 'reservadas' = any (v_falhas) then
      v_l := v_l || 'Reservei: não consegui ler agora.'::text;
    elsif cardinality(v_ri) > 0 then
      v_l := v_l || ('Reservei: ' || array_to_string(v_ri, '. ')
                     || case when v_rmais > 0 then format(' (e mais %s em *agenda semana que vem*)', v_rmais) else '' end || '.');
    end if;
    if 'fora' = any (v_falhas) then
      v_l := v_l || 'De fora: não consegui ler agora.'::text;
    elsif cardinality(v_fo) > 0 then
      v_l := v_l || ('De fora: ' || array_to_string(v_fo, '; ')
                     || case when v_fmais > 0 then format(' (e mais %s em *agenda semana que vem*)', v_fmais) else '' end || '.');
    end if;
    v_l := v_l || v_fl;
    if 'riscos' = any (v_falhas) then
      v_l := v_l || 'Riscos: não consegui ler agora.'::text;
    elsif cardinality(v_rk) > 0 then
      v_l := v_l || ('Riscos: ' || array_to_string(v_rk, '; ') || '.');
    end if;
    if 'precisa' = any (v_falhas) then
      v_l := v_l || 'Preciso de você: não consegui ler agora.'::text;
    elsif v_ptot = 0 then
      v_l := v_l || 'Preciso de você: nada por agora.'::text;
    elsif cardinality(v_pqs) = 0 then
      v_l := v_l || format('Preciso de você: %s em *agenda pendências*.', public._agenda_plural(v_pmais, 'pergunta', 'perguntas'));
    else
      v_l := v_l || 'Preciso de você:'::text;
      v_l := v_l || v_pqs;
      if v_pmais > 0 then
        v_l := v_l || format('(e mais %s em *agenda pendências*)', v_pmais);
      end if;
    end if;
    v_txt := array_to_string(v_l, E'\n');
    exit when char_length(v_txt) <= cf.texto_max;
    if cardinality(v_pqs) > 0 then
      v_pqs := v_pqs[1:cardinality(v_pqs) - 1]; v_pmais := v_pmais + 1;
    elsif cardinality(v_rk) > 1 then
      v_rk := v_rk[1:cardinality(v_rk) - 1];
    elsif cardinality(v_fo) > 1 then
      v_fo := v_fo[1:cardinality(v_fo) - 1]; v_fmais := v_fmais + 1;
    elsif cardinality(v_ri) > 1 then
      v_ri := v_ri[1:cardinality(v_ri) - 1]; v_rmais := v_rmais + 1;
    elsif cardinality(v_em) > 0 then
      v_em := v_em[1:cardinality(v_em) - 1]; v_emmais := v_emmais + 1;
    elsif cardinality(v_mi) > 1 then
      v_mi := v_mi[1:cardinality(v_mi) - 1]; v_mmais := v_mmais + 1;
    elsif not v_curto then
      -- as listas já estão no 1º item: as marcadas e as reservadas perdem o porquê e a condição (ficam o nome, os dias e quem vai)
      v_mi := v_mic[1:cardinality(v_mi)]; v_ri := v_ric[1:cardinality(v_ri)]; v_curto := true;
    else
      v_txt := public._agenda_corta(v_txt, cf.texto_max);
      exit;
    end if;
  end loop;

  return jsonb_build_object('semana', jsonb_build_object('de', v_de, 'ate', v_fim, 'rotulo', v_rot),
                            'marcadas', v_marc, 'reservadas', v_resv, 'fora', v_fora, 'folga', v_folga, 'riscos', v_rc, 'precisa', v_prec,
                            'texto', v_txt, 'incompleto', cardinality(v_falhas) > 0, 'modo', cf.modo_explicar)
         || case when v_sema then jsonb_build_object('eu_marcaria', jsonb_build_object('conta_de', v_sdia, 'linhas', to_jsonb(v_em))) else '{}'::jsonb end
         || case when cardinality(v_falhas) > 0 then jsonb_build_object('falhas', to_jsonb(v_falhas)) else '{}'::jsonb end;
end;
$function$;

comment on function public.agenda_como_pensei(date, date, timestamptz) is
  'Agenda de Produção (Fase 7g, P3; §5.3, §6.3, R9.6, R9.7, R9.8): "como pensei a semana" de p_de (sem ele, a que vem) — {semana {de, ate, rotulo}, marcadas, reservadas, fora, folga, riscos, precisa, texto (≤ texto_max), incompleto, modo}, mais eu_marcaria com o gestor em teste e falhas quando alguma parte não foi lida. Em ordem fixa: Marquei (e, com o gestor em teste, Eu marcaria, da última conta do gestor), Reservei, De fora (pelos grupos do painel), Folga (da grade do motor: com a regra teto_equipe, Σ teto100 da equipe − teto_equipe; sem ela, Σ(teto100 − teto80)), Riscos (até 3) e Preciso de você (a linha de agenda_perguntas_em_ordem como vem: o número é o da Decisão de *agenda pendências*). Com o freio, a 1ª linha diz "Você pediu *gestor, só propor*: eu só sugiro.". Em sombra, "Em teste: " antes de "Como pensei"; desligado, {modo: desligado}. SECURITY DEFINER; com login, só admin/financeiro (42501 para o resto); sem login, o service_role.';

-- ── 8. As portas ─────────────────────────────────────────────────────────────────────────────────────
-- As 4 internas como as peças do P1 (§3.1 item 13): nenhuma porta para public, anon nem authenticated (o revoke de authenticated é explícito: o privilégio
-- padrão do esquema dá execute a quem não for tirado); o service_role tem. Quem as chama são as definer deste pacote e agenda_rascunho_marcar (definer).
-- As 2 leituras (_agenda_porque_da_os e agenda_como_pensei) são definer com porta própria: authenticated e service_role (a porta recusa o técnico com 42501).
revoke all on function public._agenda_relacao_dita(text, text), public._agenda_data_com_relacao(jsonb, text, text, date),
                       public._agenda_porque_fonte(uuid, date), public._agenda_porque_linha(uuid, jsonb, date)
  from public, anon, authenticated;
grant execute on function public._agenda_relacao_dita(text, text), public._agenda_data_com_relacao(jsonb, text, text, date),
                          public._agenda_porque_fonte(uuid, date), public._agenda_porque_linha(uuid, jsonb, date)
  to service_role;
revoke all on function public._agenda_porque_da_os(uuid, date, timestamptz), public.agenda_como_pensei(date, date, timestamptz) from public, anon;
grant execute on function public._agenda_porque_da_os(uuid, date, timestamptz), public.agenda_como_pensei(date, date, timestamptz)
  to authenticated, service_role;
