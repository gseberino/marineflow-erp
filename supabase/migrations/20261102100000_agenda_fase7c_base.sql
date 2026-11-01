-- Agenda de Produção, Fase 7, etapa 7c ("quem sabe fazer o quê"), pacote P1: a base — a tabela das etiquetas por pessoa, os 3
-- interruptores e os parâmetros da etapa, as colunas novas do planejamento da OS e da alocação, as listas fechadas ampliadas, a regra
-- única "a equipe deste meio-dia atende" e as leituras puras (o que cada pessoa faz, o que a OS pede, o responsável da OS, os
-- meios-dias sem quem o serviço pede e sem o responsável). Recria _agenda_e_novato e _agenda_tecnico_declarado (com a etiqueta) e
-- _agenda_modo_da_pergunta (o tipo habilidade).
-- Spec: scratchpad agenda-pesquisa/spec-fase7c.md (§R5.1-5, §R5.4, §R5.5 item 1, §3, §4, §5.1, §6.1, §6.2, §8.3 agenda_fase7c_base.sql);
-- nomes: fase7-registro.md §1 (7c P1); respostas do dono: fase7-padroes.md (AG7-01 ligar direto; AG7-03 a equipe: Alex, o dono e
-- quem vem sob demanda — Mateus e Vinicius —, "ajudante = nunca sozinho em tarefa de risco"; AG7-04 uma pessoa, dupla só quando
-- precisa; AG7-10 "sem etiqueta = pode tudo, menos comissionar, que fica com o dono"; o gestor propõe pelo histórico).
-- Depende das Fases 1 a 6, do lote de 30/10, da 7a inteira (o ampliador de listas, o validador de regex) e da 7b inteira
-- (20261101100000 .. 100500, as correções 100800, 100850 e 100860; o novato e quem vem sob demanda).
--
-- ═══ DDL — OK NOMEADO ═══ (20 colunas novas em agenda_config — 3 interruptores e 17 parâmetros — e o DEFAULT dos 3 interruptores;
-- 5 colunas novas em os_planejamento e 2 em agenda_alocacoes, nulas ou com DEFAULT; 1 tabela nova (agenda_etiquetas) com 2 índices,
-- 3 gatilhos e a RLS de leitura; 5 listas fechadas ampliadas; 26 CHECKs novos por nome; 10 funções novas, 2 de gatilho e 3 recriadas;
-- nenhum dado)
-- NÃO APLICADA. Existe para revisão e espera o OK do dono. Este arquivo foi MONTADO por
-- scratchpad/agenda-pesquisa/f7c/p1/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA (conferida a cada
-- montagem: o montador para se outra migration a definir depois da origem) — _agenda_tecnico_declarado e _agenda_e_novato de
-- 20261101100860_agenda_fase77b_correcao3.sql, _agenda_modo_da_pergunta de 20261101100000_agenda_fase7b_tabelas.sql —, e as mudanças
-- estão só nos blocos "-- FASE 7c: … -- FASE 7c: fim". Tirados os blocos (e devolvida a linha "-- antes:" do único bloco que troca uma
-- linha, o do [c3-conf] em _agenda_tecnico_declarado), o corpo é o da origem, byte a byte (o montador e o B11 de
-- supabase/tests/agenda_fase7c_base.sql conferem).
--
-- POR QUE: a agenda escala hoje sem saber o que cada um sabe fazer. A 7c dá a cada pessoa o que ela faz (instala sozinho, é ajudante,
-- é novo, comissiona, sobe no teto), diz o que cada OS pede (sem IA: pelo tipo, pelo sistema, pelo verbo e pelas palavras da linha) e
-- define UMA regra de "a equipe atende" que o motor, a violação, a rodada e as medidas vão usar. Esta migration só cria o lugar e as
-- leituras; quem muda a escalação são as próximas (20261102100100 a 100550), sempre atrás dos interruptores. Com os 3 desligados (a
-- linha nasce assim), nada muda para ninguém — salvo as duas exceções deliberadas, que só tiram restrição do técnico que o dono
-- declarou (abaixo, item 6).
--
-- O QUE MUDA:
--   1. agenda_config: os interruptores modo_habilidade (os filtros 3 e 4, a ordem nova, a violação), modo_lider (o filtro 5 e a troca
--      avisada) e modo_habilidade_propor (a pergunta ao dono) — desligado | sombra | ligado; a linha fica 'desligado', o DEFAULT da
--      coluna vira 'sombra' (como na 7a e na 7b); quem os põe em sombra é a migration de dado 20261102100600, com OK nomeado — e 17
--      parâmetros: o padrão de quem não tem nada marcado (habilidade_padrao: instala 2, comissiona 0, altura 2 — "pode tudo, menos
--      comissionar") e o do dono (habilidade_dono: 3, 3, 2), os níveis que cada exigência pede (energizado 2, comissionar 3,
--      diagnóstico 2, altura 2, o par do novo 2), o fechamento do dono cobre o último dia (sim), as regras do que a OS pede
--      (habilidade_verbos e habilidade_regras), as palavras que conferem o trecho do dono (habilidade_palavras), a janela e os
--      mínimos da proposta pelo histórico (90 dias; 60 dias e 20 diárias para "instala sozinho"), a hora da rodada (16:10), as semanas
--      da conferência (2) e quanto esperar pelo responsável (2 dias úteis). CHECK por nome em cada um. NÃO existem
--      habilidade_veto_du (vale veto_du/veto_hora da 7a) nem habilidade_novato_* (valem novato_dias/novato_diarias da 7b).
--   2. os_planejamento: exigencias_ditas ({"altura": "nao", "energizado": "todos"}: o que o dono disse que a OS pede) e
--      exigencias_trecho; lider_payee_id, lider_em e lider_trecho (o responsável que o dono disse). agenda_alocacoes: criterio (o que
--      decidiu a pessoa: dono_disse, lider, habilidade, continuidade, local, carga, custo, unico, empate, presenca_do_dono) e
--      criterio_detalhe. Quem escreve: o *grava* do dono (P4) e o motor (P2). Nada escreve aqui.
--   3. agenda_etiquetas (nova): por pessoa, instala | ajudante | comissiona | altura, nível 0..3 (o 0 só em comissiona e altura),
--      origem dono | gestor, estado proposta | vale | recusada | substituida. Não se apaga; só muda o estado (proposta → vale,
--      recusada ou substituida; vale → substituida); uma viva por etiqueta; instala e ajudante se excluem (o gatilho substitui a
--      viva da outra e a viva da mesma); a proposta do gestor nunca troca o que o dono disse. RLS: só leitura, admin/financeiro.
--   4. As listas fechadas (pelo ampliador da 7a): agenda_perguntas.tipo, agenda_acoes.tipo, agenda_rascunho.tipo,
--      agenda_vigia_rodadas.rotina e agenda_alocacoes.cancelada_motivo + habilidade (a pergunta habilidade NÃO é crítica: a
--      expressão de critica não muda).
--   5. As leituras puras (nenhuma escreve): agenda_habilidades (o que cada pessoa faz — o nível de cada etiqueta, o papel
--      responsável | ajudante | novo e o texto ao dono), os_exigencias (o que a OS pede: energizado, comissionamento, altura,
--      diagnóstico, em todos os dias ou só no último), _agenda_atende (a regra única), _agenda_lider_da_os (o responsável),
--      _agenda_meios_sem_quem_pede e _agenda_lideres_ausentes (a avaliação do publicado), os textos (_agenda_etiqueta_texto,
--      _agenda_exigencia_texto), _agenda_du_h (dias úteis entre dois meios-dias do motor) e o validador dos CHECKs de jsonb
--      (_agenda_habilidade_config_ok).
--   6. Recriadas (R5.1-5; as duas exceções deliberadas ao "byte a byte", SEM portão de modo, como as do R4 da 7b: só tiram restrição
--      do técnico que o dono declarou ou de quem ele disse que instala sozinho, nunca de quem ele disse ajudante nem de quem vem sob
--      demanda):
--      · _agenda_tecnico_declarado (de 20261101100860): (a) com a etiqueta — não é técnico declarado quem tem etiqueta viva vale de
--        ajudante (qualquer nível) ou de instala 1; e [c3-conf] o padrão do dono conta pela data em que foi dito, sem o "criada até
--        p_dia": o motor mede o novato na segunda da grade, e quem o dono declarava no meio da semana continuava novato até a segunda
--        seguinte (o achado "baixa" 1 da revisão da correção 3; hoje não atinge ninguém: a linha do Alex é de sex 30/10);
--      · _agenda_e_novato (de 20261101100860): (b) quem tem etiqueta viva vale de instala 2 ou 3 de origem dono (o dono disse que ele
--        instala sozinho) nunca é novato;
--      · _agenda_modo_da_pergunta (de 20261101100000): a pergunta habilidade da equipe (habilidade:equipe:…) é do
--        modo_habilidade_propor; a de uma OS (habilidade:os:<os>), do modo_habilidade.
--   7. [c3-rev] (a decisão do P1, notas-fase77c.md): o Mateus cadastrado agora, SEM perfil de diária, com um dia fixo dito pelo dono
--      ("toda terça"), na 7b conta como técnico (não é novato, não vem sob demanda, não é declarado). Na 7c o papel dele é NOVO
--      (nunca vai sozinho) — em agenda_habilidades, não em _agenda_e_novato: o padrão do dono dito a menos de novato_dias do cadastro
--      e nenhum perfil de diária vigente, com sob_demanda_sozinho falso (é o auxiliar que o dono chama, AG7-03). Vale com a 7c ligada
--      (o filtro 4 do P2, a escada do P3); com a 7c desligada ou em teste, a 7b como está, byte a byte. O papel é medido no dia da
--      rodada (p_hoje), não na segunda da grade (o P2 chama agenda_habilidades(p_hoje, …)).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7c_base.sql; registradas em notas-fase77c.md, P1):
--   · os CHECKs de habilidade_padrao/habilidade_dono, habilidade_regras e habilidade_palavras usam um validador IMMUTABLE
--     (_agenda_habilidade_config_ok, o molde do _agenda_dupla_lista_ok da 7a): CHECK não aceita subconsulta, e a regex inválida tem de
--     ser recusada também num UPDATE de depois, não só na migration;
--   · a fonte palavra de habilidade_regras casa no INÍCIO de palavra ('\m(' || expressão || ')', o molde dos dupla_gatilhos da 7a): sem
--     isso, a OS-00104 do Flávio pedia "quem instala sozinho com 220 V" pela linha "Refrigerador Consul" (refri-GERADOR), contra a
--     tabela do §2 da spec ("nenhuma"); as outras 10 OS da carteira saem iguais (o B6 fixa as 11);
--   · habilidade_verbos é conferido contra service_verbs.slug na migration só quando o catálogo existe e tem verbos (a bancada não o
--     tem);
--   · os_planejamento_lider_coerente = "quem tem responsável tem a data" (lider_payee_id nulo ou lider_em preenchido): a igualdade da
--     spec faria a FK on delete set null de payees recusar o delete da pessoa;
--   · o gatilho de exclusividade substitui também a viva VALE da mesma etiqueta (a spec dizia só a proposta; sem isso o índice de uma
--     viva por etiqueta recusa o "o Roberto instala sozinho" do dono por cima do "instala 2" do gestor) e recusa a proposta do gestor
--     que trocaria uma linha do dono;
--   · _agenda_etiqueta_texto e _agenda_exigencia_texto com grant a authenticated e service_role (a spec dizia "sem grant" para o 1º):
--     agenda_habilidades e os_exigencias são invoker e lidas pelo painel, e o administrador esbarrava no texto (42501);
--   · o texto de quem não tem nada marcado sai dos níveis do padrão: "pode tudo, menos comissionar (padrão)" com os de hoje; se o dono
--     baixar o padrão abaixo do que o serviço pede, as três coisas por extenso (a frase fixa ficaria falsa).
--
-- O QUE NÃO MUDA: com os 3 interruptores desligados, o motor, a violação, a rodada, os textos à equipe e ao cliente e as Fases 1 a 6,
-- a 7a e a 7b, byte a byte (as funções novas não são chamadas por ninguém de antes). As duas exceções do item 6 não mudam nada com a
-- equipe de hoje (o Alex sem perfil não era novato; ninguém tem etiqueta). Os valores de antes continuam nas listas; as críticas
-- continuam as mesmas; o modo de todo tipo de pergunta de antes é o mesmo.
--
-- ORDEM DE LIGAR (spec §10): depois da 7b inteira (as 9 de estrutura e o dado 20261101100900); antes de 20261102100100 (P2), que lê
-- as colunas novas. Aplicar sozinha não muda nada para ninguém (os interruptores ficam 'desligado' na linha).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7c_base.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261102100000
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261102100000_agenda_fase7c_base.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261102100000', 'agenda_fase7c_base');"
--
-- DESFAZER (só a estrutura; nada usa as colunas antes das próximas migrations): recriar _agenda_tecnico_declarado e _agenda_e_novato
-- com o corpo de 20261101100860 e _agenda_modo_da_pergunta com o de 20261101100000; o resto pode ficar (colunas nulas ou com DEFAULT,
-- listas só somadas, a tabela vazia). Para tirar mesmo (só sem linha em agenda_etiquetas e sem valor novo nas listas):
--   drop function if exists public.agenda_habilidades(date, uuid[]), public.os_exigencias(uuid, date),
--     public._agenda_atende(integer, integer[], integer[], integer[], integer[], boolean, integer, jsonb),
--     public._agenda_lider_da_os(uuid, date, uuid[]), public._agenda_meios_sem_quem_pede(date, date, date, uuid[], boolean),
--     public._agenda_lideres_ausentes(date, date, date), public._agenda_du_h(boolean[], integer, integer),
--     public._agenda_etiqueta_texto(text, smallint), public._agenda_exigencia_texto(integer, text, boolean);
--   drop table if exists public.agenda_etiquetas;
--   drop function if exists public._agenda_etiquetas_so_muda(), public._agenda_etiquetas_exclusiva();
--   alter table public.os_planejamento drop column if exists exigencias_ditas, drop column if exists exigencias_trecho,
--     drop column if exists lider_payee_id, drop column if exists lider_em, drop column if exists lider_trecho;
--   alter table public.agenda_alocacoes drop column if exists criterio, drop column if exists criterio_detalhe;
--   (agenda_config: drop dos 18 CHECKs e das 20 colunas; depois drop function public._agenda_habilidade_config_ok(text, jsonb);
--    as listas: recriar o CHECK de cada uma com os valores da 7b)
--
-- IDEMPOTENTE: add column if not exists, CHECK por nome em do $$ (só cria o que falta), as listas pelo ampliador (soma só o que falta),
-- create table/index if not exists, create or replace function, drop trigger/policy if exists + create, revoke/grant e comment.

-- ── 0. O validador dos CHECKs de jsonb da etapa ──────────────────────────────────────────────────────────────────

-- O CHECK de habilidade_padrao e habilidade_dono (p_qual = 'niveis': exatamente instala 1..3, comissiona 0..3 e altura 0..3,
-- inteiros), de habilidade_regras ('regras': uma lista não vazia de [exigência, alcance, fonte, valor] — exigência em energizado,
-- comissionamento, altura, diagnostico; alcance em todos, ultimo; fonte em tipo, sistema, verbo, verbo_principal, palavra; o valor
-- preenchido; a palavra uma expressão regular que compila) e de habilidade_palavras ('palavras': exatamente as 6 chaves — as 4
-- etiquetas e energizado e diagnostico —, cada uma uma expressão que compila). CHECK não aceita subconsulta: a função é IMMUTABLE e
-- só olha o jsonb. A expressão é validada pelo validador único da 7a (_agenda_regex_valido).
create or replace function public._agenda_habilidade_config_ok(p_qual text, p_valor jsonb)
 returns boolean
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  e jsonb;
  k text;
begin
  if p_valor is null then
    return false;
  end if;
  if p_qual = 'niveis' then
    if jsonb_typeof(p_valor) <> 'object'
       or (select array_agg(x order by x) from jsonb_object_keys(p_valor) x) is distinct from array['altura', 'comissiona', 'instala'] then
      return false;
    end if;
    foreach k in array array['instala', 'comissiona', 'altura'] loop
      if jsonb_typeof(p_valor -> k) <> 'number' or (p_valor ->> k) !~ '^[0-9]$' or (p_valor ->> k)::int > 3
         or (k = 'instala' and (p_valor ->> k)::int < 1) then
        return false;
      end if;
    end loop;
    return true;
  elsif p_qual = 'regras' then
    if jsonb_typeof(p_valor) <> 'array' or jsonb_array_length(p_valor) = 0 then
      return false;
    end if;
    for e in select x from jsonb_array_elements(p_valor) x loop
      if jsonb_typeof(e) <> 'array' or jsonb_array_length(e) <> 4
         or exists (select 1 from jsonb_array_elements(e) y where jsonb_typeof(y) <> 'string') then
        return false;
      end if;
      if (e ->> 0) <> all (array['energizado', 'comissionamento', 'altura', 'diagnostico'])
         or (e ->> 1) <> all (array['todos', 'ultimo'])
         or (e ->> 2) <> all (array['tipo', 'sistema', 'verbo', 'verbo_principal', 'palavra'])
         or btrim(e ->> 3) = ''
         or ((e ->> 2) = 'palavra' and not public._agenda_regex_valido('\m(' || (e ->> 3) || ')')) then
        return false;
      end if;
    end loop;
    return true;
  elsif p_qual = 'palavras' then
    if jsonb_typeof(p_valor) <> 'object'
       or (select array_agg(x order by x) from jsonb_object_keys(p_valor) x)
          is distinct from array['ajudante', 'altura', 'comissiona', 'diagnostico', 'energizado', 'instala'] then
      return false;
    end if;
    foreach k in array array['instala', 'ajudante', 'comissiona', 'altura', 'energizado', 'diagnostico'] loop
      if jsonb_typeof(p_valor -> k) <> 'string' or btrim(p_valor ->> k) = '' or not public._agenda_regex_valido(p_valor ->> k) then
        return false;
      end if;
    end loop;
    return true;
  end if;
  return false;
end;
$function$;

comment on function public._agenda_habilidade_config_ok(text, jsonb) is
  'Agenda de Produção (Fase 7c, P1): o validador dos CHECKs de jsonb da 7c em agenda_config — niveis (habilidade_padrao e habilidade_dono: exatamente instala 1..3, comissiona 0..3 e altura 0..3, inteiros), regras (habilidade_regras: lista não vazia de [exigência em energizado/comissionamento/altura/diagnostico, alcance todos/ultimo, fonte tipo/sistema/verbo/verbo_principal/palavra, valor preenchido], a palavra uma expressão que compila casada no início de palavra, como os_exigencias a usa) e palavras (habilidade_palavras: exatamente instala, ajudante, comissiona, altura, energizado e diagnostico, cada uma uma expressão que compila, por _agenda_regex_valido). Outro p_qual ou nulo = false. IMMUTABLE.';

revoke all on function public._agenda_habilidade_config_ok(text, jsonb) from public, anon;
grant execute on function public._agenda_habilidade_config_ok(text, jsonb) to authenticated, service_role;

-- ── 1. agenda_config: os interruptores e os parâmetros ──────────────────────────────────────────────────────────
alter table public.agenda_config
  -- a linha fica 'desligado' até a migration de dado 20261102100600 (o molde da 7a e da 7b); o DEFAULT passa a 'sombra' abaixo
  add column if not exists modo_habilidade              text     not null default 'desligado',  -- AG7-10 (os filtros 3 e 4, a ordem nova, a violação)
  add column if not exists modo_lider                   text     not null default 'desligado',  -- desenho (o filtro 5 e a troca avisada)
  add column if not exists modo_habilidade_propor       text     not null default 'desligado',  -- AG7-10 (a pergunta ao dono)
  add column if not exists habilidade_padrao            jsonb    not null
    default '{"instala": 2, "comissiona": 0, "altura": 2}',                                      -- AG7-10: sem etiqueta = pode tudo, menos comissionar
  add column if not exists habilidade_dono              jsonb    not null
    default '{"instala": 3, "comissiona": 3, "altura": 2}',                                      -- AG7-10: comissionar fica com o dono
  add column if not exists habilidade_nivel_energizado  smallint not null default 2,             -- AG7-04 / AG7-10
  add column if not exists habilidade_nivel_comissionar smallint not null default 3,             -- AG7-10
  add column if not exists habilidade_nivel_diagnostico smallint not null default 2,             -- AG7-10
  add column if not exists habilidade_nivel_altura      smallint not null default 2,             -- AG7-10
  add column if not exists habilidade_nivel_par         smallint not null default 2,             -- AG7-04 (o novo)
  add column if not exists habilidade_fechamento_cobre  boolean  not null default true,          -- AG7-10 (o fechamento do dono conta no último dia)
  add column if not exists habilidade_verbos            text[]   not null
    default '{instalacao,substituicao,adequacao,reparo,configuracao,manutencao}',                -- desenho
  add column if not exists habilidade_regras            jsonb    not null default $j$[
    ["comissionamento","todos","tipo","commissioning"],
    ["diagnostico","todos","tipo","diagnosis"],
    ["diagnostico","todos","verbo_principal","diagnostico"],
    ["energizado","ultimo","sistema","eletrico_ac"],
    ["energizado","ultimo","palavra","(inversor|multiplus|quattro|220 ?v|127 ?v|110 ?v|tomada|energia de terra|shore power|gerador|transferencia|chave reversora)"],
    ["energizado","ultimo","palavra","(litio|lifepo|banco de bateria|baterias? de (litio|chumbo)|8d|barramento|lynx|busbar|usina)"],
    ["comissionamento","ultimo","verbo","configuracao"],
    ["comissionamento","ultimo","palavra","(comissionament|comissionar|parametriza|ve ?configure|vrm|cerbo)"],
    ["altura","todos","palavra","(teto|placa solar|painel solar|paineis solares|modulo fotovoltaico|claraboia|hardtop|mastro|radar|antena|starlink|toldo|arco)"]
  ]$j$,                                                                                          -- AG7-04 (o que é energizado) e AG7-10
  add column if not exists habilidade_palavras          jsonb    not null default $j${
    "instala": "(instal|sozinh|monta|liga|ensina)",
    "ajudante": "(ajudant|ajuda|novo|nova|novato|aprendiz|comec)",
    "comissiona": "(comission|configur|programa|victron|vrm)",
    "altura": "(teto|sobe|subi|altura|escada|nr ?35|telhado|em cima)",
    "energizado": "(220|127|110|energi|litio|bateria|inversor|ligad|tensao|tomada|gerador)",
    "diagnostico": "(diagnos|defeito|achar o problema|procurar)"
  }$j$,                                                                                          -- AG7-10 (a guarda do trecho)
  -- [R] sem habilidade_veto_du (vale veto_du/veto_hora do 7a) e sem habilidade_novato_* (valem novato_dias/novato_diarias do 7b)
  add column if not exists habilidade_janela_dias       smallint not null default 90,            -- desenho
  add column if not exists habilidade_instala_dias      smallint not null default 60,            -- AG7-10
  add column if not exists habilidade_instala_diarias   smallint not null default 20,            -- AG7-10
  add column if not exists habilidade_hora              time     not null default '16:10',       -- desenho (depois do aprender, antes do plano)
  add column if not exists habilidade_conferir_semanas  smallint not null default 2,             -- desenho
  add column if not exists lider_espera_max_du          smallint not null default 2;             -- desenho (a confirmar: §13 item 6)

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('agenda_config_modo_habilidade_check',        'check (modo_habilidade in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_lider_check',             'check (modo_lider in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_habilidade_propor_check', 'check (modo_habilidade_propor in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_habilidade_padrao_check',      'check (public._agenda_habilidade_config_ok(''niveis'', habilidade_padrao))'),
      ('agenda_config_habilidade_dono_check',        'check (public._agenda_habilidade_config_ok(''niveis'', habilidade_dono))'),
      ('agenda_config_habilidade_nivel_energizado_check',  'check (habilidade_nivel_energizado between 1 and 3)'),
      ('agenda_config_habilidade_nivel_comissionar_check', 'check (habilidade_nivel_comissionar between 1 and 3)'),
      ('agenda_config_habilidade_nivel_diagnostico_check', 'check (habilidade_nivel_diagnostico between 1 and 3)'),
      ('agenda_config_habilidade_nivel_altura_check',      'check (habilidade_nivel_altura between 1 and 3)'),
      ('agenda_config_habilidade_nivel_par_check',         'check (habilidade_nivel_par between 1 and 3)'),
      ('agenda_config_habilidade_regras_check',      'check (public._agenda_habilidade_config_ok(''regras'', habilidade_regras))'),
      ('agenda_config_habilidade_palavras_check',    'check (public._agenda_habilidade_config_ok(''palavras'', habilidade_palavras))'),
      ('agenda_config_habilidade_janela_dias_check',       'check (habilidade_janela_dias between 30 and 365)'),
      ('agenda_config_habilidade_instala_dias_check',      'check (habilidade_instala_dias between 14 and 365)'),
      ('agenda_config_habilidade_instala_diarias_check',   'check (habilidade_instala_diarias between 5 and 120)'),
      ('agenda_config_habilidade_hora_check',
       'check (habilidade_hora >= time ''12:00'' and habilidade_hora <= hora_do_plano)'),
      ('agenda_config_habilidade_conferir_semanas_check',  'check (habilidade_conferir_semanas between 1 and 6)'),
      ('agenda_config_lider_espera_max_du_check',          'check (lider_espera_max_du between 0 and 10)')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.agenda_config'::regclass and conname = r.nome) then
      execute format('alter table public.agenda_config add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

-- ── verbos: início (o B1 de agenda_fase7c_base.sql roda este bloco de novo, pelo texto, com o catálogo semeado) ─────
-- habilidade_verbos é conferido contra o catálogo de verbos (service_verbs.slug; não é FK: o catálogo pode ganhar verbo sem a agenda
-- saber). Só quando o catálogo existe e tem verbos: a bancada não tem o catálogo (as sementes de 03/08 são de antes do snapshot).
do $$
declare
  v_faltam text[];
begin
  if to_regclass('public.service_verbs') is not null then
    execute $q$select array_agg(v order by v)
                 from unnest((select c.habilidade_verbos from public.agenda_config c where c.id)) v
                where exists (select 1 from public.service_verbs)
                  and not exists (select 1 from public.service_verbs s where s.slug = v)$q$
       into v_faltam;
    if v_faltam is not null then
      raise exception 'agenda_config.habilidade_verbos: % não estão no catálogo de verbos (service_verbs).', v_faltam
        using errcode = '23514';
    end if;
  end if;
end
$$;
-- ── verbos: fim ─────────────────────────────────────────────────────────────────────────────────────────────────

-- Como a 7a e a 7b: a estrutura não muda comportamento. A linha que já existe fica 'desligado' (do add column acima); quem a põe em
-- sombra é a migration de dado 20261102100600, com OK nomeado (AG7-01: ligar no mesmo dia do pós-deploy verde).
alter table public.agenda_config
  alter column modo_habilidade        set default 'sombra',
  alter column modo_lider             set default 'sombra',
  alter column modo_habilidade_propor set default 'sombra';

comment on column public.agenda_config.modo_habilidade is
  'Agenda de Produção (Fase 7c, AG7-10): quem faz o quê na escalação — os filtros 3 (quem o meio-dia pede) e 4 (o novo nunca sozinho; o ajudante nunca sozinho em serviço de risco), a ordem nova dos candidatos (o menos qualificado que dá conta) e a violação habilidade do publicado. desligado = a escalação de antes; sombra = escala como antes e a rodada diária grava "Em teste (quem faz o quê)"; ligado = escala por isso. A migration de dado 20261102100600 põe sombra; o ligar é no mesmo dia do pós-deploy verde (AG7-01).';
comment on column public.agenda_config.modo_lider is
  'Agenda de Produção (Fase 7c, desenho): o responsável fixo da OS começada (o filtro 5: o líder — dito pelo dono ou o 1º responsável que trabalhou nela — ou o dono no turno em todo meio-dia) e a troca avisada quando esperar por ele atrasa mais que lider_espera_max_du. desligado = como antes; sombra = só a conferência da rodada; ligado = o motor usa.';
comment on column public.agenda_config.modo_habilidade_propor is
  'Agenda de Produção (Fase 7c, AG7-10): a proposta do gestor pelo histórico (diárias e tempo de casa; o técnico que o dono declarou = instala sozinho) numa pergunta só ao dono (habilidade:equipe), que vale depois do prazo de veto (veto_du/veto_hora da 7a, contado de quando foi mostrada). desligado = não propõe; sombra = a pergunta nasce em teste; ligado = a pergunta vai ao dono.';
comment on column public.agenda_config.habilidade_padrao is
  'Agenda de Produção (Fase 7c, AG7-10): o nível de quem não tem nada marcado — instala 2 (sozinho), comissiona 0 (não), altura 2 (sobe no teto): "pode tudo, menos comissionar, que fica com o dono". Dado que falta não tira ninguém da agenda.';
comment on column public.agenda_config.habilidade_dono is
  'Agenda de Produção (Fase 7c, AG7-10): o nível do dono sem nada marcado — instala 3 (sozinho e ensina), comissiona 3 (comissiona Victron sozinho), altura 2. O dono é sempre responsável.';
comment on column public.agenda_config.habilidade_nivel_energizado is
  'Agenda de Produção (Fase 7c, AG7-04/AG7-10): o nível de instala que o meio-dia de serviço energizado (CA 127/220 V, banco CC de alta corrente aberto ou manuseado; o 12 V comum não conta) pede de alguém da equipe (ou o dono no turno). 1..3.';
comment on column public.agenda_config.habilidade_nivel_comissionar is
  'Agenda de Produção (Fase 7c, AG7-10): o nível de comissiona que o comissionamento pede (3 = comissiona Victron sozinho; sem etiqueta, só o dono). 1..3.';
comment on column public.agenda_config.habilidade_nivel_diagnostico is
  'Agenda de Produção (Fase 7c, AG7-10): o nível de comissiona (ou de instala, pelo energizado) que o diagnóstico pede. 1..3.';
comment on column public.agenda_config.habilidade_nivel_altura is
  'Agenda de Produção (Fase 7c, AG7-10): o nível de altura que o serviço no teto pede (2 = sobe no teto; NR-35). 1..3.';
comment on column public.agenda_config.habilidade_nivel_par is
  'Agenda de Produção (Fase 7c, AG7-04): o nível de instala do responsável que o novo precisa ao lado (o novo nunca vai sozinho). 1..3.';
comment on column public.agenda_config.habilidade_fechamento_cobre is
  'Agenda de Produção (Fase 7c, AG7-10): o fechamento do dono cobre o último dia (ele liga, testa e comissiona no fechamento): com isso, o que a OS pede só no último dia não pede mais ninguém quando o dono fecha naquele dia. Padrão sim.';
comment on column public.agenda_config.habilidade_verbos is
  'Agenda de Produção (Fase 7c, desenho): os verbos de linha que contam na regra de sistema de habilidade_regras (o sistema eletrico_ac só pede quem instala sozinho quando a linha instala, substitui, adequa, repara, configura ou faz manutenção). Conferidos contra service_verbs.slug na migration.';
comment on column public.agenda_config.habilidade_regras is
  'Agenda de Produção (Fase 7c, AG7-04/AG7-10): o que a OS pede, sem IA — lista ordenada de [exigência, alcance, fonte, valor]: exigência energizado/comissionamento/altura/diagnostico; alcance todos (todo meio-dia) ou ultimo (só o último); fonte tipo (service_orders.service_type), sistema (o sistema da linha, com o verbo em habilidade_verbos), verbo (o verbo da linha), verbo_principal (o verbo da linha de maior valor) ou palavra (expressão regular casada no início de palavra, \m(…), sobre o nome e a descrição da linha, sem acento: "refrigerador" não é gerador; como os gatilhos de dupla da 7a). O que o dono disse (os_planejamento.exigencias_ditas) vale sobre as regras.';
comment on column public.agenda_config.habilidade_palavras is
  'Agenda de Produção (Fase 7c, AG7-10): a guarda do trecho do dono — a palavra que tem de estar no que ele disse para o rascunho aceitar o que a pessoa faz (instala, ajudante, comissiona, altura) e o que a OS pede (energizado, diagnostico; comissionamento e altura usam as das etiquetas). Expressões regulares sobre o trecho sem acento.';
comment on column public.agenda_config.habilidade_janela_dias is
  'Agenda de Produção (Fase 7c, desenho): a janela das diárias que a proposta pelo histórico conta (90 dias até hoje). 30..365.';
comment on column public.agenda_config.habilidade_instala_dias is
  'Agenda de Produção (Fase 7c, AG7-10): o tempo de casa (dias desde o 1º perfil de diária) para o gestor propor "instala sozinho". 14..365.';
comment on column public.agenda_config.habilidade_instala_diarias is
  'Agenda de Produção (Fase 7c, AG7-10): as diárias na janela para o gestor propor "instala sozinho". 5..120.';
comment on column public.agenda_config.habilidade_hora is
  'Agenda de Produção (Fase 7c, desenho): a hora da rodada diária de quem faz o quê (16:10: depois do aprender das 16:00, antes da publicação; roda no tique das 16:15). Entre 12:00 e hora_do_plano.';
comment on column public.agenda_config.habilidade_conferir_semanas is
  'Agenda de Produção (Fase 7c, desenho): quantas semanas à frente a rodada confere o publicado com as regras novas (em teste). 1..6.';
comment on column public.agenda_config.lider_espera_max_du is
  'Agenda de Produção (Fase 7c, desenho; a confirmar com o dono): quantos dias úteis o motor espera pelo responsável da OS começada antes de seguir com outro (e dizer no "o que mudou"). 0..10.';

-- ── 2. As colunas novas do planejamento da OS e da alocação ─────────────────────────────────────────────────────
-- (exigencias_ditas sem CHECK na linha da coluna: o nome que o Postgres daria a ele é o do CHECK nomeado abaixo, que leva o objeto, as
-- chaves e os valores — com os dois, o do-bloco acharia o nome e não criaria o completo)
alter table public.os_planejamento
  add column if not exists exigencias_ditas  jsonb not null default '{}',
  add column if not exists exigencias_trecho text check (char_length(exigencias_trecho) <= 500),
  add column if not exists lider_payee_id    uuid references public.payees(id) on delete set null,
  add column if not exists lider_em          timestamptz,
  add column if not exists lider_trecho      text check (char_length(lider_trecho) <= 300);

alter table public.agenda_alocacoes
  add column if not exists criterio          text,
  add column if not exists criterio_detalhe  jsonb not null default '{}' check (jsonb_typeof(criterio_detalhe) = 'object');

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('public.os_planejamento', 'os_planejamento_exigencias_ditas_check',
       'check (jsonb_typeof(exigencias_ditas) = ''object'''
       || ' and (exigencias_ditas - array[''energizado'', ''comissionamento'', ''altura'', ''diagnostico'']) = ''{}''::jsonb'
       || ' and not jsonb_path_exists(exigencias_ditas, ''$.* ? (@.type() != "string" || !(@ == "todos" || @ == "ultimo" || @ == "nao"))''))'),
      ('public.os_planejamento', 'os_planejamento_lider_coerente', 'check (lider_payee_id is null or lider_em is not null)'),
      ('public.agenda_alocacoes', 'agenda_alocacoes_criterio_check',
       'check (criterio in (''dono_disse'', ''lider'', ''habilidade'', ''continuidade'', ''local'', ''carga'', ''custo'', ''unico'', ''empate'', ''presenca_do_dono''))')
    ) as c(tabela, nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = r.tabela::regclass and conname = r.nome) then
      execute format('alter table %s add constraint %I %s', r.tabela, r.nome, r.regra);
    end if;
  end loop;
end
$$;

comment on column public.os_planejamento.exigencias_ditas is
  'Agenda de Produção (Fase 7c, AG7-10): o que o dono disse que a OS pede — {exigência: todos | ultimo | nao}, exigência em energizado, comissionamento, altura, diagnostico. Vale sobre as regras (habilidade_regras): nao tira, todos/ultimo põe ou troca o alcance. Escreve só o *grava* do dono (_agenda_aplicar_habilidade, P4).';
comment on column public.os_planejamento.exigencias_trecho is 'Agenda de Produção (Fase 7c): as palavras do dono do que a OS pede.';
comment on column public.os_planejamento.lider_payee_id is
  'Agenda de Produção (Fase 7c): o responsável da OS que o dono disse ("no Lenine o responsável é o Roberto"). Com modo_lider ligado e a OS começada, ele (ou o dono) fica em todos os meios-dias. Escreve só o *grava* do dono.';
comment on column public.os_planejamento.lider_em is 'Agenda de Produção (Fase 7c): quando o dono disse o responsável (quem tem responsável tem a data).';
comment on column public.os_planejamento.lider_trecho is 'Agenda de Produção (Fase 7c): as palavras do dono do responsável.';
comment on column public.agenda_alocacoes.criterio is
  'Agenda de Produção (Fase 7c): o que decidiu a pessoa deste meio-dia — dono_disse, lider, habilidade (o responsável que o serviço pedia), continuidade, local, carga, custo, unico (o único livre), empate ou presenca_do_dono. Gravado pelo motor em qualquer modo (é medida para o 7g); nulo = alocação de antes da 7c.';
comment on column public.agenda_alocacoes.criterio_detalhe is
  'Agenda de Produção (Fase 7c): {regra (7c | antes; as que nascem fora do motor: escada, dupla, corte, fora_do_motor), exigencias (o que o meio-dia pedia, curto), suposicoes (pessoa_sem_etiqueta, exigencia_pelo_texto), lider_trocado}.';

-- ── 3. As etiquetas por pessoa ──────────────────────────────────────────────────────────────────────────────────
create table if not exists public.agenda_etiquetas (
  id             uuid primary key default gen_random_uuid(),
  payee_id       uuid not null references public.payees(id) on delete cascade,
  etiqueta       text not null check (etiqueta in ('instala', 'ajudante', 'comissiona', 'altura')),
  nivel          smallint not null check (nivel between 0 and 3),
  origem         text not null check (origem in ('dono', 'gestor')),
  estado         text not null check (estado in ('proposta', 'vale', 'recusada', 'substituida')),
  motivo         text not null check (char_length(motivo) between 3 and 200),
  evidencia      jsonb not null default '{}' check (jsonb_typeof(evidencia) = 'object'),
  trecho         text check (char_length(trecho) <= 500),
  pergunta_id    uuid references public.agenda_perguntas(id) on delete set null,
  vale_desde     timestamptz,
  criado_em      timestamptz not null,
  criado_por     uuid references public.app_users(id) on delete set null,
  substituida_em timestamptz,
  constraint etiqueta_nivel_zero        check (nivel > 0 or etiqueta in ('comissiona', 'altura')),
  constraint etiqueta_vale_tem_data     check (estado <> 'vale' or vale_desde is not null),
  constraint etiqueta_proposta_sem_data check (estado not in ('proposta', 'recusada') or vale_desde is null),
  constraint etiqueta_dono_vale         check (origem = 'gestor' or estado in ('vale', 'substituida')),
  constraint etiqueta_substituida       check ((estado = 'substituida') = (substituida_em is not null))
);
create unique index if not exists agenda_etiquetas_viva on public.agenda_etiquetas(payee_id, etiqueta)
  where estado in ('proposta', 'vale');
create index if not exists agenda_etiquetas_pessoa on public.agenda_etiquetas(payee_id) where estado = 'vale';

comment on table public.agenda_etiquetas is
  'Agenda de Produção (Fase 7c, AG7-10): o que cada pessoa da equipe faz — instala (1 só com alguém junto, 2 sozinho, 3 sozinho e ensina), ajudante (1 é novo: nunca vai sozinho; 2 não vai sozinho em serviço de risco; 3 já quase instala), comissiona (0 não, 1 acompanha, 2 faz diagnóstico, 3 comissiona Victron sozinho) e altura (0 não sobe, 1 só acompanhado, 2 sobe no teto, 3 sobe e orienta). origem dono (o que ele disse, já vale) ou gestor (a proposta pelo histórico, vale depois do prazo de veto). instala e ajudante se excluem; uma viva (proposta ou vale) por etiqueta; não se apaga, só muda o estado. Sem etiqueta, vale habilidade_padrao (o dono: habilidade_dono). Leitura: agenda_habilidades.';
comment on column public.agenda_etiquetas.motivo is
  'O porquê, ao dono: "você disse" (dono) ou "32 diárias desde 23/08" · "entrou em 29/09, 15 diárias" · "começou em 20/10, 3 diárias" · "você disse que ele vem todo dia útil" (gestor).';
comment on column public.agenda_etiquetas.evidencia is 'A evidência da proposta do gestor: {diarias, desde, dias_de_casa, janela} ou {declarado, desde, cadastro, dias}.';
comment on column public.agenda_etiquetas.pergunta_id is 'A pergunta habilidade:equipe que levou a proposta ao dono (a mais nova).';
comment on column public.agenda_etiquetas.vale_desde is 'Desde quando vale (o *grava* do dono, o prazo de veto vencido ou a confirmação).';

-- Não se apaga (o de Fase 2); muda só o estado, pelas trocas permitidas; instala e ajudante se excluem.
create or replace function public._agenda_etiquetas_so_muda()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  if not public._agenda_so_mudou(to_jsonb(old), to_jsonb(new), array['estado', 'vale_desde', 'substituida_em', 'pergunta_id'],
                                 array['criado_por']) then
    raise exception 'agenda_etiquetas: a etiqueta não muda; só o estado (o rastro fica).' using errcode = '23514';
  end if;
  if new.estado is distinct from old.estado
     and not ((old.estado = 'proposta' and new.estado in ('vale', 'recusada', 'substituida'))
              or (old.estado = 'vale' and new.estado = 'substituida')) then
    raise exception 'agenda_etiquetas: a etiqueta não volta de % para %.', old.estado, new.estado using errcode = '23514';
  end if;
  return new;
end;
$function$;

comment on function public._agenda_etiquetas_so_muda() is
  'Agenda de Produção (Fase 7c, P1): gatilho BEFORE UPDATE de agenda_etiquetas — só mudam estado, vale_desde, substituida_em e pergunta_id (o criado_por pode virar nulo pela FK); as trocas de estado são proposta → vale, recusada ou substituida e vale → substituida. O resto = 23514.';

create or replace function public._agenda_etiquetas_exclusiva()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  if new.estado not in ('proposta', 'vale') then
    return new;
  end if;
  -- A proposta do gestor nunca troca o que o dono disse (a rodada nem propõe para quem tem linha do dono em instala ou ajudante).
  if new.origem = 'gestor'
     and exists (select 1 from public.agenda_etiquetas e
                  where e.payee_id = new.payee_id and e.estado in ('proposta', 'vale') and e.origem = 'dono'
                    and (e.etiqueta = new.etiqueta
                         or (new.etiqueta = 'instala' and e.etiqueta = 'ajudante')
                         or (new.etiqueta = 'ajudante' and e.etiqueta = 'instala'))) then
    raise exception 'agenda_etiquetas: a proposta do gestor não troca o que o dono disse.' using errcode = '23514';
  end if;
  -- A viva da mesma etiqueta e a viva da outra (instala × ajudante) viram substituídas.
  update public.agenda_etiquetas e
     set estado = 'substituida', substituida_em = new.criado_em
   where e.payee_id = new.payee_id and e.estado in ('proposta', 'vale')
     and (e.etiqueta = new.etiqueta
          or (new.etiqueta = 'instala' and e.etiqueta = 'ajudante')
          or (new.etiqueta = 'ajudante' and e.etiqueta = 'instala'));
  return new;
end;
$function$;

comment on function public._agenda_etiquetas_exclusiva() is
  'Agenda de Produção (Fase 7c, P1): gatilho BEFORE INSERT da etiqueta viva (proposta ou vale) — a viva da mesma etiqueta e a viva da outra de instala × ajudante (as duas se excluem) da mesma pessoa viram substituida (substituida_em = criado_em da nova). A proposta do gestor que trocaria uma linha do dono é recusada (23514).';

drop trigger if exists agenda_etiquetas_nao_apaga on public.agenda_etiquetas;
create trigger agenda_etiquetas_nao_apaga before delete on public.agenda_etiquetas
  for each row execute function public._agenda_registro_nao_apaga();
drop trigger if exists agenda_etiquetas_so_muda on public.agenda_etiquetas;
create trigger agenda_etiquetas_so_muda before update on public.agenda_etiquetas
  for each row execute function public._agenda_etiquetas_so_muda();
drop trigger if exists agenda_etiquetas_exclusiva on public.agenda_etiquetas;
create trigger agenda_etiquetas_exclusiva before insert on public.agenda_etiquetas
  for each row execute function public._agenda_etiquetas_exclusiva();

alter table public.agenda_etiquetas enable row level security;

drop policy if exists agenda_etiquetas_leitura on public.agenda_etiquetas;
create policy agenda_etiquetas_leitura on public.agenda_etiquetas
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

revoke all on table public.agenda_etiquetas from public, anon, authenticated;
grant select on table public.agenda_etiquetas to authenticated;
grant all on table public.agenda_etiquetas to service_role;

revoke all on function public._agenda_etiquetas_so_muda(), public._agenda_etiquetas_exclusiva() from public, anon, authenticated;

-- ── 4. As listas fechadas (pelo ampliador da 7a: lê a lista viva e soma) ─────────────────────────────────────────
-- habilidade NÃO é crítica: a expressão gerada de agenda_perguntas.critica não muda.
select public._agenda_ampliar_lista('public.agenda_perguntas', 'agenda_perguntas_tipo_check', 'tipo', array['habilidade']);
select public._agenda_ampliar_lista('public.agenda_acoes', 'agenda_acoes_tipo_check', 'tipo', array['habilidade']);
select public._agenda_ampliar_lista('public.agenda_rascunho', 'agenda_rascunho_tipo_check', 'tipo', array['habilidade']);
select public._agenda_ampliar_lista('public.agenda_vigia_rodadas', 'agenda_vigia_rodadas_rotina_check', 'rotina', array['habilidade']);
select public._agenda_ampliar_lista('public.agenda_alocacoes', 'agenda_alocacoes_cancelada_motivo_check', 'cancelada_motivo',
                                    array['habilidade']);

comment on column public.agenda_vigia_rodadas.rotina is
  'Agenda de Produção (Fase 3): vigia (o tique da Fase 2) ou rotina (a rotina da equipe e da diária); Fase 4: material (a nota, o Pix, o detector e a mensagem ao fornecedor); Fase 5: cliente (as mensagens-modelo ao cliente); Fase 6: aprender (a medição e o aprendizado, uma vez por dia); Fase 7a: gestor (a rodada do gestor da agenda, o job agenda-gestor); Fase 7b: equipe_semana (a pergunta da semana, o passo 0b1 do task-automations); Fase 7c: habilidade (a rodada de quem faz o quê, o passo 0b2a). As rodadas de antes são da vigia.';

-- ── 5. Os textos, a conta de dias úteis e a regra única ──────────────────────────────────────────────────────────

-- O que cada nível de etiqueta é, na palavra do dono (spec §3.2). Etiqueta ou nível que não existe = nulo.
create or replace function public._agenda_etiqueta_texto(p_etiqueta text, p_nivel smallint)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case p_etiqueta
    when 'instala' then case p_nivel when 1 then 'instala só com alguém junto' when 2 then 'instala sozinho'
                                     when 3 then 'instala sozinho e ensina' end
    when 'ajudante' then case p_nivel when 1 then 'é novo: nunca vai sozinho'
                                      when 2 then 'é ajudante: não vai sozinho em serviço de risco'
                                      when 3 then 'é ajudante e já quase instala sozinho' end
    when 'comissiona' then case p_nivel when 0 then 'não comissiona' when 1 then 'acompanha o comissionamento'
                                        when 2 then 'faz diagnóstico sozinho' when 3 then 'comissiona Victron sozinho' end
    when 'altura' then case p_nivel when 0 then 'não sobe no teto' when 1 then 'sobe no teto só acompanhado'
                                    when 2 then 'sobe no teto' when 3 then 'sobe no teto e orienta' end
  end;
$function$;

comment on function public._agenda_etiqueta_texto(text, smallint) is
  'Agenda de Produção (Fase 7c, P1; spec §3.2): o texto ao dono de cada etiqueta e nível ("instala sozinho", "é ajudante: não vai sozinho em serviço de risco", "não sobe no teto"…). O que não existe = nulo. IMMUTABLE; authenticated e service_role (agenda_habilidades, leitura do painel, o chama).';

-- O que a OS pede, na palavra do dono (spec §6.1): os bits juntam com " e "; p_meios ultimo = " no último dia", todos = " em todos os
-- dias", nulo = nada. p_curto = sem o "quem" (para "ninguém que … fica livre"). Máscara 0 ou nula = nulo.
create or replace function public._agenda_exigencia_texto(p_mask integer, p_meios text, p_curto boolean default false)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case when coalesce(p_mask, 0) & 15 = 0 then null else
    array_to_string(array_remove(array[
      case when p_mask & 1 <> 0 then case when coalesce(p_curto, false) then '' else 'quem ' end
                                     || 'instala sozinho com 220 V ou banco de bateria' end,
      case when p_mask & 2 <> 0 then case when coalesce(p_curto, false) then '' else 'quem ' end || 'comissiona Victron' end,
      case when p_mask & 4 <> 0 then case when coalesce(p_curto, false) then '' else 'quem ' end || 'sobe no teto' end,
      case when p_mask & 8 <> 0 then case when coalesce(p_curto, false) then '' else 'quem ' end || 'faz diagnóstico' end
    ], null), ' e ')
    || case p_meios when 'ultimo' then ' no último dia' when 'todos' then ' em todos os dias' else '' end
  end;
$function$;

comment on function public._agenda_exigencia_texto(integer, text, boolean) is
  'Agenda de Produção (Fase 7c, P1; spec §6.1): o texto do que a OS pede pela máscara (1 energizado "quem instala sozinho com 220 V ou banco de bateria", 2 "quem comissiona Victron", 4 "quem sobe no teto", 8 "quem faz diagnóstico"; juntos com " e "), com " no último dia" (ultimo) ou " em todos os dias" (todos); p_curto sem o "quem". Máscara 0 ou nula = nulo. IMMUTABLE; authenticated e service_role (os_exigencias, leitura do painel, o chama).';

-- Quantos dias úteis há entre dois meios-dias do motor: d útil com dia(h1) < d <= dia(h2), dia(h) = (h + 1) / 2 (o índice do meio-dia
-- na grade: 1 = 1º dia de manhã, 2 = 1º dia à tarde…); p_util[d] é o vetor "útil" do contexto. Negativo se h2 < h1. Nulo com nulo.
create or replace function public._agenda_du_h(p_util boolean[], p_h1 integer, p_h2 integer)
 returns integer
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
    when p_h1 is null or p_h2 is null then null
    when p_h2 >= p_h1 then (select count(*)::int from generate_series((p_h1 + 1) / 2 + 1, (p_h2 + 1) / 2) d
                             where coalesce(p_util[d], false))
    else -(select count(*)::int from generate_series((p_h2 + 1) / 2 + 1, (p_h1 + 1) / 2) d where coalesce(p_util[d], false))
  end;
$function$;

comment on function public._agenda_du_h(boolean[], integer, integer) is
  'Agenda de Produção (Fase 7c, P1; spec §5.1): os dias úteis d com dia(p_h1) < d <= dia(p_h2), dia(h) = (h + 1) / 2 (h = o índice do meio-dia na grade do motor), contados pelo vetor útil do contexto; negativo se p_h2 < p_h1. A troca avisada do responsável (P2) mede por ela quanto esperar atrasa. IMMUTABLE, sem grant.';

-- A regra única de "a equipe deste meio-dia atende" (spec §3.5): o 1º código que falta, ou nulo. p_ex = a máscara do meio-dia (1
-- energizado, 2 comissionamento, 4 altura, 8 diagnóstico); os níveis da equipe escolhida, um por pessoa, na mesma ordem (instala,
-- comissiona, altura, papel 0 responsável | 1 ajudante | 2 novo); o dono no turno e a altura dele; p_n = {ene, com, dia, alt, par}, os
-- habilidade_nivel_* (quem chama passa; a chave que falta não é atendida por ninguém). Arrays vazios = equipe vazia. O motor, a
-- violação, a conferência da rodada, as medidas e o aviso chamam esta (uma regra só).
create or replace function public._agenda_atende(p_ex integer, p_inst integer[], p_com integer[], p_alt integer[], p_pap integer[],
                                                 p_dono_turno boolean, p_dono_alt integer, p_n jsonb)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
    when coalesce(p_ex, 0) & 1 <> 0 and not coalesce(p_dono_turno, false)
         and not exists (select 1 from unnest(p_inst) i where i >= (p_n ->> 'ene')::int)
      then 'energizado'
    when coalesce(p_ex, 0) & 2 <> 0 and not coalesce(p_dono_turno, false)
         and not exists (select 1 from unnest(p_com) x where x >= (p_n ->> 'com')::int)
      then 'comissionamento'
    when coalesce(p_ex, 0) & 8 <> 0 and not coalesce(p_dono_turno, false)
         and not exists (select 1 from unnest(p_com) x where x >= (p_n ->> 'dia')::int)
         and not exists (select 1 from unnest(p_inst) i where i >= (p_n ->> 'ene')::int)
      then 'diagnostico'
    when coalesce(p_ex, 0) & 4 <> 0
         and not (coalesce(p_dono_turno, false) and coalesce(p_dono_alt >= (p_n ->> 'alt')::int, false))
         and not exists (select 1 from unnest(p_alt) x where x >= (p_n ->> 'alt')::int)
      then 'altura'
    when exists (select 1 from unnest(p_pap) x where x = 2) and not coalesce(p_dono_turno, false)
         and not exists (select 1 from unnest(p_inst, p_pap) t(i, x) where x = 0 and i >= (p_n ->> 'par')::int)
      then 'novato_sozinho'
  end;
$function$;

comment on function public._agenda_atende(integer, integer[], integer[], integer[], integer[], boolean, integer, jsonb) is
  'Agenda de Produção (Fase 7c, P1; spec §3.5): a regra única "a equipe deste meio-dia atende" — o 1º código que falta: energizado (p_ex & 1, sem o dono no turno e ninguém com instala >= ene), comissionamento (& 2: comissiona >= com), diagnostico (& 8: comissiona >= dia nem instala >= ene), altura (& 4: ninguém nem o dono no turno com altura >= alt), novato_sozinho (um novo — papel 2 — sem o dono no turno e sem um responsável — papel 0 — com instala >= par); nulo = atende. Os níveis vêm de agenda_habilidades, um por pessoa, na mesma ordem; p_n = {ene, com, dia, alt, par} (habilidade_nivel_*). IMMUTABLE, sem grant.';

-- ── 6. As leituras ───────────────────────────────────────────────────────────────────────────────────────────────

-- O que cada pessoa faz (spec §3.2, §5.1 e §6.2; R5.1-5): o nível de cada etiqueta (a linha VALE, do dono ou do gestor; sem linha, o
-- padrão: habilidade_padrao, ou habilidade_dono para o dono; a proposta não vale), o papel (0 responsável, 1 ajudante, 2 novo), de onde
-- veio cada coisa e o texto ao dono. O papel novo (nunca vai sozinho): a etiqueta ajudante 1, OU, sem etiqueta viva vale de instala 2/3
-- de origem dono: o novato da 7b (_agenda_e_novato, com novato_sozinho falso), quem vem sob demanda (_agenda_e_sob_demanda, com
-- sob_demanda_sozinho falso) ou [c3-rev] quem tem um padrão do dono dito a menos de novato_dias do cadastro e nenhum perfil de diária
-- vigente (o Mateus cadastrado agora com "toda terça"), com sob_demanda_sozinho falso. A etiqueta ajudante 2/3 não tira o papel novo
-- (vale a mais protetora); fora dele, ajudante 2/3 ou instala 1 = ajudante (instala até 1). O dono é sempre responsável. O papel é
-- medido em p_hoje. População: p_payees (na ordem; só quem é payee), senão a grade de p_hoje a p_hoje + 13 (agenda_capacidade) e quem
-- tem etiqueta viva. STABLE, invoker: lê agenda_etiquetas sob a RLS (o motor roda como service_role).
create or replace function public.agenda_habilidades(p_hoje date, p_payees uuid[] default null)
 returns table (payee_id uuid, nome text, eh_dono boolean, instala smallint, comissiona smallint, altura smallint,
                papel smallint, fonte jsonb, texto text)
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c         public.agenda_config := public._agenda_cfg();
  v_dono    uuid := public._agenda_dono(null);
  v_ids     uuid[];
  r         record;
  e_inst    record;
  e_ajud    record;
  e_com     record;
  e_alt     record;
  v_base    jsonb;
  v_regra   text;
  v_inst    smallint;
  v_com     smallint;
  v_alt     smallint;
  v_pap     smallint;
  v_fi      text;
  v_fp      text;
  v_partes  jsonb;
  v_txt     text;
  v_suf     text;
  v_grupo   text;
  v_gsuf    text;
  p         jsonb;
  v_desde   date;
  v_diarias numeric;
  v_qtas    text;
begin
  if p_hoje is null then
    raise exception 'agenda_habilidades: p_hoje é obrigatório.' using errcode = '22004';
  end if;
  if p_payees is not null then
    v_ids := array(select u.x from unnest(p_payees) with ordinality u(x, o) where u.x is not null group by u.x order by min(u.o));
  else
    v_ids := array(select g.id
                     from (select k.payee_id as id from public.agenda_capacidade(p_hoje, p_hoje + 13, p_hoje) k
                           union
                           select e.payee_id from public.agenda_etiquetas e where e.estado in ('proposta', 'vale')) g
                     join public.payees py on py.id = g.id
                    order by (g.id is not distinct from v_dono) desc, public._agenda_nome_curto(py.name), g.id);
  end if;

  for r in
    select py.id, public._agenda_nome_curto(py.name) as nm, py.created_at, py.id is not distinct from v_dono as dono
      from unnest(v_ids) with ordinality u(id, o) join public.payees py on py.id = u.id
     order by u.o
  loop
    select e.nivel, e.origem, e.motivo into e_inst from public.agenda_etiquetas e
     where e.payee_id = r.id and e.etiqueta = 'instala' and e.estado = 'vale' order by e.criado_em desc, e.id desc limit 1;
    select e.nivel, e.origem, e.motivo into e_ajud from public.agenda_etiquetas e
     where e.payee_id = r.id and e.etiqueta = 'ajudante' and e.estado = 'vale' order by e.criado_em desc, e.id desc limit 1;
    select e.nivel, e.origem, e.motivo into e_com from public.agenda_etiquetas e
     where e.payee_id = r.id and e.etiqueta = 'comissiona' and e.estado = 'vale' order by e.criado_em desc, e.id desc limit 1;
    select e.nivel, e.origem, e.motivo into e_alt from public.agenda_etiquetas e
     where e.payee_id = r.id and e.etiqueta = 'altura' and e.estado = 'vale' order by e.criado_em desc, e.id desc limit 1;
    v_base := case when r.dono then c.habilidade_dono else c.habilidade_padrao end;

    -- o papel novo pela regra (sem a etiqueta ajudante 1 e sem o "instala sozinho" do dono)
    v_regra := null;
    if not r.dono and e_ajud.nivel is distinct from 1
       and not coalesce(e_inst.origem = 'dono' and e_inst.nivel >= 2, false) then
      if not c.novato_sozinho and public._agenda_e_novato(r.id, p_hoje) then
        v_regra := 'novato';
      elsif not c.sob_demanda_sozinho and public._agenda_e_sob_demanda(r.id, p_hoje) then
        v_regra := 'sob_demanda';
      elsif not c.sob_demanda_sozinho
            and not exists (select 1 from public.work_profiles w
                             where w.payee_id = r.id and w.vigencia_inicio <= p_hoje
                               and (w.vigencia_fim is null or w.vigencia_fim >= p_hoje))
            and coalesce((select min(d.criado_em) from public.agenda_disponibilidade d
                           where d.payee_id = r.id and d.origem = 'dono' and d.dias_semana is not null
                             and cardinality(d.dias_semana) > 0 and d.situacao in ('disponivel', 'confirmada'))
                         < r.created_at + make_interval(days => c.novato_dias), false) then
        v_regra := 'dia_fixo';
      end if;
    end if;

    if r.dono then
      v_pap := 0;
      v_inst := coalesce(e_inst.nivel, (v_base ->> 'instala')::smallint);
      v_fi := coalesce(e_inst.origem, 'padrao');
      v_fp := 'padrao';
    elsif e_ajud.nivel = 1 then
      v_pap := 2; v_inst := 0; v_fi := e_ajud.origem; v_fp := e_ajud.origem;
    elsif v_regra is not null then
      v_pap := 2; v_inst := 0; v_fi := v_regra; v_fp := v_regra;
    elsif e_ajud.nivel >= 2 then
      v_pap := 1; v_inst := least((v_base ->> 'instala')::smallint, 1::smallint); v_fi := e_ajud.origem; v_fp := e_ajud.origem;
    elsif e_inst.nivel = 1 then
      v_pap := 1; v_inst := 1; v_fi := e_inst.origem; v_fp := e_inst.origem;
    else
      v_pap := 0;
      v_inst := coalesce(e_inst.nivel, (v_base ->> 'instala')::smallint);
      v_fi := coalesce(e_inst.origem, 'padrao');
      v_fp := coalesce(e_inst.origem, 'padrao');
    end if;

    -- o texto (§6.2): [texto, de onde] de cada coisa; o dono diz as três (comissiona, instala, altura); os outros, só o que está
    -- marcado (e a regra do novo); sem nada, "pode tudo, menos comissionar (padrão)"
    v_partes := '[]'::jsonb;
    if r.dono then
      v_partes := jsonb_build_array(
        jsonb_build_array(public._agenda_etiqueta_texto('comissiona', coalesce(e_com.nivel, (v_base ->> 'comissiona')::smallint)),
                          coalesce(e_com.origem, 'padrao'), e_com.motivo),
        jsonb_build_array(public._agenda_etiqueta_texto('instala', v_inst), coalesce(e_inst.origem, 'padrao'), e_inst.motivo),
        jsonb_build_array(public._agenda_etiqueta_texto('altura', coalesce(e_alt.nivel, (v_base ->> 'altura')::smallint)),
                          coalesce(e_alt.origem, 'padrao'), e_alt.motivo));
    else
      if v_regra in ('novato', 'dia_fixo') then
        v_desde := case when v_regra = 'novato'
                        then (select min(w.vigencia_inicio) from public.work_profiles w where w.payee_id = r.id)
                        else (r.created_at at time zone 'America/Sao_Paulo')::date end;
        v_diarias := coalesce((select sum(ws.fracao) from public.work_shifts ws join public.work_profiles w on w.id = ws.work_profile_id
                                where w.payee_id = r.id and ws.data <= p_hoje and ws.tipo = 'diaria' and ws.fracao is not null), 0);
        v_qtas := case when v_diarias = 0 then 'ainda sem diária'
                       when v_diarias = 1 then '1 diária'
                       else replace(trim_scale(v_diarias)::text, '.', ',') || ' diárias' end;
        v_partes := v_partes || jsonb_build_array(jsonb_build_array('é novo: nunca vai sozinho', 'regra',
                                  format('começou em %s, %s', to_char(v_desde, 'DD/MM'), v_qtas)));
      elsif v_regra = 'sob_demanda' then
        v_partes := v_partes || jsonb_build_array(jsonb_build_array('nunca vai sozinho', 'regra', 'vem só nos dias que você diz'));
      elsif e_ajud.nivel is not null then
        v_partes := v_partes || jsonb_build_array(jsonb_build_array(public._agenda_etiqueta_texto('ajudante', e_ajud.nivel),
                                                                    e_ajud.origem, e_ajud.motivo));
      elsif e_inst.nivel is not null then
        v_partes := v_partes || jsonb_build_array(jsonb_build_array(public._agenda_etiqueta_texto('instala', e_inst.nivel),
                                                                    e_inst.origem, e_inst.motivo));
      end if;
      if e_com.nivel is not null then
        v_partes := v_partes || jsonb_build_array(jsonb_build_array(public._agenda_etiqueta_texto('comissiona', e_com.nivel),
                                                                    e_com.origem, e_com.motivo));
      end if;
      if e_alt.nivel is not null then
        v_partes := v_partes || jsonb_build_array(jsonb_build_array(public._agenda_etiqueta_texto('altura', e_alt.nivel),
                                                                    e_alt.origem, e_alt.motivo));
      end if;
    end if;

    v_com := coalesce(e_com.nivel, (v_base ->> 'comissiona')::smallint);
    v_alt := coalesce(e_alt.nivel, (v_base ->> 'altura')::smallint);
    if jsonb_array_length(v_partes) = 0 then
      -- nada marcado: o padrão da casa, dito pelo que ele deixa (com os níveis de hoje, AG7-10: "pode tudo, menos comissionar");
      -- se o dono mudar o padrão para baixo dos níveis que o serviço pede, as três coisas por extenso
      if v_inst >= c.habilidade_nivel_energizado and v_alt >= c.habilidade_nivel_altura then
        v_txt := case when v_com >= c.habilidade_nivel_comissionar then 'pode tudo (padrão)'
                      else 'pode tudo, menos comissionar (padrão)' end;
      else
        v_txt := concat_ws('; ', public._agenda_etiqueta_texto('instala', v_inst), public._agenda_etiqueta_texto('comissiona', v_com),
                           public._agenda_etiqueta_texto('altura', v_alt)) || ' (padrão)';
      end if;
    else
      -- as coisas seguidas de mesma origem (padrão ou "você disse") dividem o parêntese; o "eu marquei" leva o motivo de cada uma
      v_txt := null;
      v_grupo := null;
      v_gsuf := null;
      for p in select x from jsonb_array_elements(v_partes) x loop
        v_suf := case p ->> 1 when 'padrao' then ' (padrão)' when 'dono' then ' (você disse)'
                              when 'gestor' then format(' (eu marquei: %s)', p ->> 2)
                              else format(' (%s)', p ->> 2) end;
        if v_grupo is not null and v_suf = v_gsuf and (p ->> 1) in ('padrao', 'dono') then
          v_grupo := v_grupo || '; ' || (p ->> 0);
        else
          if v_grupo is not null then
            v_txt := concat_ws('; ', v_txt, v_grupo || v_gsuf);
          end if;
          v_grupo := p ->> 0;
          v_gsuf := v_suf;
        end if;
      end loop;
      v_txt := concat_ws('; ', v_txt, v_grupo || v_gsuf);
    end if;

    payee_id := r.id;
    nome := r.nm;
    eh_dono := r.dono;
    instala := v_inst;
    comissiona := v_com;
    altura := v_alt;
    papel := v_pap;
    fonte := jsonb_build_object('instala', v_fi, 'comissiona', coalesce(e_com.origem, 'padrao'),
                                'altura', coalesce(e_alt.origem, 'padrao'), 'papel', v_fp);
    texto := format('%s: %s.', case when r.dono then 'Você' else r.nm end, v_txt);
    return next;
  end loop;
end;
$function$;

comment on function public.agenda_habilidades(date, uuid[]) is
  'Agenda de Produção (Fase 7c, P1; spec §3.2, §5.1, §6.2; R5.1-5): o que cada pessoa faz — instala, comissiona e altura (a etiqueta VALE, do dono ou do gestor; sem ela, habilidade_padrao, ou habilidade_dono para o dono; a proposta não vale), o papel (0 responsável, 1 ajudante — ajudante 2/3 ou instala 1, instala até 1 —, 2 novo — ajudante 1, ou, sem instala 2/3 do dono, o novato da 7b, quem vem sob demanda ou quem tem um dia fixo dito pelo dono a menos de novato_dias do cadastro e nenhum perfil de diária vigente [c3-rev] —; o dono sempre 0), fonte {instala, comissiona, altura, papel: dono | gestor | padrao | novato | sob_demanda | dia_fixo} e o texto ao dono ("Roberto: instala sozinho (eu marquei: 32 diárias desde 23/08)."; "Mickael: pode tudo, menos comissionar (padrão)."; "Você: comissiona Victron sozinho; instala sozinho e ensina; sobe no teto (padrão)."). Medido em p_hoje. População: p_payees na ordem (só payees), senão a grade de p_hoje a p_hoje + 13 e quem tem etiqueta viva (o dono primeiro, depois o nome). STABLE, invoker: as etiquetas sob a RLS.';

-- O que a OS pede (spec §3.3 e §6.1), sem IA: o que o dono disse (os_planejamento.exigencias_ditas; nao tira, todos/ultimo põe ou troca
-- o alcance) vale sobre as regras de habilidade_regras, na ordem do array — tipo (service_type), sistema (o da linha, com o verbo em
-- habilidade_verbos), verbo, verbo_principal (o da linha de maior valor; desempate created_at, id) e palavra (regex casada no início
-- de palavra, '\m(' || expressão || ')', como os gatilhos de dupla da 7a: "refrigerador" não é "gerador", "barco" não é "arco"; sobre
-- o nome e a descrição da linha, sem acento) —, sobre as linhas da OS menos as de verbo logistica e as de sistema nenhum (o
-- deslocamento não é serviço). Máscara: 1 energizado, 2 comissionamento, 4 altura, 8 diagnóstico; todos ganha de ultimo. {ok, todos, ultimo,
-- fonte_texto (1 = alguma veio do sistema, do verbo ou da palavra), itens [{exigencia, meios, fonte, linha, linha_id}], texto,
-- texto_curto}. Com login sem admin/financeiro = 42501. STABLE, invoker.
create or replace function public.os_exigencias(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c_bits   constant jsonb := '{"energizado": 1, "comissionamento": 2, "altura": 4, "diagnostico": 8}';
  v_uid    uuid := auth.uid();
  v_papel  text;
  c        public.agenda_config;
  v_tipo   text;
  v_cli    text;
  v_ditas  jsonb;
  x        record;
  v_l      text;
  v_b      int;
  v_itens  jsonb := '[]'::jsonb;
  v_todos  int := 0;
  v_ult    int := 0;
  v_ft     int := 0;
  v_cit_t  text;
  v_cit_u  text;
  v_partes text[] := '{}';
  v_curtas text[] := '{}';
begin
  -- Quem vê: com login, só admin/financeiro; sem login, só o service_role (a vigia, a rodada, o motor).
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'O que a OS pede é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'O que a OS pede é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;

  select so.service_type, coalesce(public._agenda_nome_curto(cl.name), so.service_order_number)
    into v_tipo, v_cli
    from public.service_orders so left join public.clients cl on cl.id = so.client_id
   where so.id = p_os;
  if not found then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
  end if;
  c := public._agenda_cfg();
  select pl.exigencias_ditas into v_ditas from public.os_planejamento pl where pl.service_order_id = p_os;
  v_ditas := coalesce(v_ditas, '{}'::jsonb);

  for x in
    with l as (
      select sos.id, sos.name_snapshot as nome, sos.line_total as total, sos.created_at as criado,
             coalesce(sos.service_system, s.service_system) as sistema, coalesce(sos.service_verb, s.service_verb) as verbo,
             public._agenda_normal(coalesce(sos.name_snapshot, '') || ' ' || coalesce(sos.description_snapshot, '')) as txt
        from public.service_order_services sos
        left join public.services s on s.id = sos.service_id
       where sos.service_order_id = p_os
         and coalesce(sos.service_verb, s.service_verb, '') <> 'logistica'
         and coalesce(sos.service_system, s.service_system, '') <> 'nenhum'
    ),
    pr as (select l.* from l order by l.total desc nulls last, l.criado nulls last, l.id limit 1),
    rg as (select t.e, t.o from jsonb_array_elements(c.habilidade_regras) with ordinality t(e, o)),
    casou as (
      select rg.o, rg.e ->> 0 as exig, rg.e ->> 1 as meios, 'tipo'::text as fonte, null::uuid as linha_id, null::text as linha,
             null::numeric as total, null::timestamptz as criado
        from rg where rg.e ->> 2 = 'tipo' and v_tipo is not distinct from (rg.e ->> 3)
      union all
      select rg.o, rg.e ->> 0, rg.e ->> 1, rg.e ->> 2, l.id, l.nome, l.total, l.criado
        from rg join l on case rg.e ->> 2
                            when 'sistema' then l.sistema = (rg.e ->> 3) and l.verbo = any (c.habilidade_verbos)
                            when 'verbo' then l.verbo = (rg.e ->> 3)
                            when 'palavra' then l.txt ~ ('\m(' || (rg.e ->> 3) || ')')
                            else false end
      union all
      select rg.o, rg.e ->> 0, rg.e ->> 1, 'verbo_principal', pr.id, pr.nome, pr.total, pr.criado
        from rg join pr on rg.e ->> 2 = 'verbo_principal' and pr.verbo = (rg.e ->> 3)
    ),
    -- uma por (exigência, alcance, linha): a da 1ª regra; fora as exigências que o dono disse (a palavra dele vale)
    regra as (
      select distinct on (k.exig, k.meios, coalesce(k.linha_id::text, '')) k.*
        from casou k
       where not (v_ditas ? k.exig)
       order by k.exig, k.meios, coalesce(k.linha_id::text, ''), k.o
    ),
    dito as (
      select 0::bigint as o, d.key as exig, d.value as meios, 'dito'::text as fonte, null::uuid as linha_id, null::text as linha,
             null::numeric as total, null::timestamptz as criado
        from jsonb_each_text(v_ditas) d
       where d.value in ('todos', 'ultimo') and c_bits ? d.key
    )
    select t.* from (select * from dito union all select * from regra) t
     order by (t.fonte = 'dito') desc, (c_bits ->> t.exig)::int, t.o, t.total desc nulls last, t.criado nulls last, t.linha_id
  loop
    -- a linha como o dono lê: toda em maiúscula vira só a 1ª maiúscula; corte em 60 letras com "…"
    v_l := null;
    if x.linha is not null then
      v_l := btrim(regexp_replace(x.linha, '\s+', ' ', 'g'));
      if v_l ~ '[A-ZÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ]' and v_l !~ '[a-záàâãäéèêëíìîïóòôõöúùûüçñ]' then
        v_l := lower(translate(v_l, 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ', 'áàâãäéèêëíìîïóòôõöúùûüçñ'));
        v_l := translate(upper(left(v_l, 1)), 'áàâãäéèêëíìîïóòôõöúùûüçñ', 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ') || substr(v_l, 2);
      end if;
      if char_length(v_l) > 60 then
        v_l := rtrim(left(v_l, 59)) || '…';
      end if;
    end if;
    v_b := (c_bits ->> x.exig)::int;
    v_itens := v_itens || jsonb_build_array(jsonb_build_object('exigencia', x.exig, 'meios', x.meios, 'fonte', x.fonte,
                                                               'linha', v_l, 'linha_id', x.linha_id));
    if x.meios = 'todos' then
      v_todos := v_todos | v_b;
    else
      v_ult := v_ult | v_b;
    end if;
    if x.fonte in ('sistema', 'verbo', 'verbo_principal', 'palavra') then
      v_ft := 1;
    end if;
  end loop;
  v_ult := v_ult & ~v_todos;

  -- de onde veio cada parte: a 1ª coisa dela, na ordem dos itens
  select case i ->> 'fonte' when 'dito' then 'você disse' when 'tipo' then 'pelo tipo do serviço'
                            else format('pela linha "%s"', i ->> 'linha') end
    into v_cit_t
    from jsonb_array_elements(v_itens) with ordinality t(i, o)
   where i ->> 'meios' = 'todos' and v_todos & (c_bits ->> (i ->> 'exigencia'))::int <> 0
   order by o limit 1;
  select case i ->> 'fonte' when 'dito' then 'você disse' when 'tipo' then 'pelo tipo do serviço'
                            else format('pela linha "%s"', i ->> 'linha') end
    into v_cit_u
    from jsonb_array_elements(v_itens) with ordinality t(i, o)
   where i ->> 'meios' = 'ultimo' and v_ult & (c_bits ->> (i ->> 'exigencia'))::int <> 0
   order by o limit 1;

  if v_todos = 0 and v_ult = 0 then
    return jsonb_build_object('ok', true, 'todos', 0, 'ultimo', 0, 'fonte_texto', v_ft, 'itens', v_itens,
                              'texto', format('%s não pede ninguém em especial.', v_cli), 'texto_curto', null);
  end if;
  if v_todos <> 0 then
    v_partes := v_partes || format('%s (%s)', public._agenda_exigencia_texto(v_todos, null), v_cit_t);
    v_curtas := v_curtas || public._agenda_exigencia_texto(v_todos, null);
  end if;
  if v_ult <> 0 then
    v_partes := v_partes || format('%s (%s)', public._agenda_exigencia_texto(v_ult, 'ultimo'), v_cit_u);
    v_curtas := v_curtas || (public._agenda_exigencia_texto(v_ult, null) || ', no último dia');
  end if;
  return jsonb_build_object('ok', true, 'todos', v_todos, 'ultimo', v_ult, 'fonte_texto', v_ft, 'itens', v_itens,
                            'texto', format('%s pede %s.', v_cli, array_to_string(v_partes, ' e ')),
                            'texto_curto', array_to_string(v_curtas, ' e '));
end;
$function$;

comment on function public.os_exigencias(uuid, date) is
  'Agenda de Produção (Fase 7c, P1; spec §3.3, §5.1, §6.1): o que a OS pede, sem IA — o que o dono disse (os_planejamento.exigencias_ditas) e as regras de habilidade_regras (tipo, sistema com verbo de habilidade_verbos, verbo, verbo_principal, palavra) sobre as linhas da OS (menos verbo logistica e sistema nenhum). {ok, todos, ultimo (máscaras 1 energizado, 2 comissionamento, 4 altura, 8 diagnóstico; todos ganha de ultimo), fonte_texto, itens [{exigencia, meios, fonte dito|tipo|sistema|verbo|verbo_principal|palavra, linha, linha_id}], texto ("Lenine pede quem instala sozinho com 220 V ou banco de bateria no último dia (pela linha "Substituição baterias - chumbo para litio")."; "Flávio não pede ninguém em especial."), texto_curto ("quem instala sozinho com 220 V ou banco de bateria, no último dia")}. OS que não existe = {ok: false, texto: "Não encontrei esse serviço."}. Com login sem admin/financeiro = 42501. STABLE, invoker.';

-- O responsável da OS (spec §3.6): 1) dito — os_planejamento.lider_payee_id com a pessoa ativa (fonte dono); 2) fez — o responsável
-- (papel 0 de agenda_habilidades, nunca o dono) do meio-dia feito mais antigo da OS: as alocações de turno, não reserva, vigentes,
-- cumpridas, parciais ou sem registro (ou passadas sem resultado), e as diárias ligadas à OS (work_shift_os, contam como manhã);
-- desempate: mais meios-dias na OS, depois o nome; o ajudante nunca é líder (vale o 1º dia de um responsável); 3) planejado — o
-- responsável do 1º meio-dia vigente futuro (de turno, não reserva, fora de p_ignorar). Senão, nulo. {payee_id, nome, fonte, desde,
-- texto}. STABLE, sem grant.
create or replace function public._agenda_lider_da_os(p_os uuid, p_hoje date, p_ignorar uuid[] default '{}')
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_dono uuid := public._agenda_dono(null);
  r      record;
begin
  if p_os is null or p_hoje is null then
    return null;
  end if;
  -- 1) o que o dono disse
  select pl.lider_payee_id as id, public._agenda_nome_curto(py.name) as nm, pl.lider_em
    into r
    from public.os_planejamento pl join public.payees py on py.id = pl.lider_payee_id and py.active
   where pl.service_order_id = p_os;
  if r.id is not null then
    return jsonb_build_object('payee_id', r.id, 'nome', r.nm, 'fonte', 'dono',
                              'desde', (r.lider_em at time zone 'America/Sao_Paulo')::date,
                              'texto', format('%s (você disse)', r.nm));
  end if;

  -- 2) quem fez: o responsável do meio-dia feito mais antigo
  with feitos as (
    select a.payee_id, a.dia, case a.turno when 'manha' then 1 else 2 end as t
      from public.agenda_alocacoes a
     where a.service_order_id = p_os and a.presenca = 'turno' and a.tipo <> 'reserva' and a.estado in ('publicada', 'fixada')
       and a.payee_id is distinct from v_dono
       and (a.resultado in ('cumprido', 'parcial', 'sem_registro') or (a.resultado is null and a.dia < p_hoje))
    union
    select w.payee_id, ws.data, 1
      from public.work_shift_os x
      join public.work_shifts ws on ws.id = x.shift_id
      join public.work_profiles w on w.id = ws.work_profile_id
     where x.service_order_id = p_os and ws.data <= p_hoje and coalesce(ws.fracao, 1) > 0
       and w.payee_id is distinct from v_dono
  ),
  resp as (
    select f.* from feitos f
      join public.agenda_habilidades(p_hoje, array(select distinct f2.payee_id from feitos f2)) h
        on h.payee_id = f.payee_id and h.papel = 0
  )
  select x.payee_id as id, public._agenda_nome_curto(py.name) as nm, x.dia
    into r
    from (select distinct on (1) rp.payee_id, rp.dia, rp.t from resp rp order by 1, rp.dia, rp.t) x
    join public.payees py on py.id = x.payee_id
   order by x.dia, x.t, (select count(*) from resp z where z.payee_id = x.payee_id) desc, public._agenda_nome_curto(py.name), x.payee_id
   limit 1;
  if r.id is not null then
    return jsonb_build_object('payee_id', r.id, 'nome', r.nm, 'fonte', 'fez', 'desde', r.dia,
                              'texto', format('%s (fez o 1º dia, %s)', r.nm, public._dia_curto(r.dia)));
  end if;

  -- 3) o planejado: o responsável do 1º meio-dia vigente futuro
  with futuros as (
    select a.payee_id, a.dia, case a.turno when 'manha' then 1 else 2 end as t
      from public.agenda_alocacoes a
     where a.service_order_id = p_os and a.presenca = 'turno' and a.tipo <> 'reserva' and a.estado in ('publicada', 'fixada')
       and a.payee_id is distinct from v_dono and a.dia >= p_hoje and a.resultado is null
       and not (a.id = any (coalesce(p_ignorar, '{}')))
  ),
  resp as (
    select f.* from futuros f
      join public.agenda_habilidades(p_hoje, array(select distinct f2.payee_id from futuros f2)) h
        on h.payee_id = f.payee_id and h.papel = 0
  )
  select x.payee_id as id, public._agenda_nome_curto(py.name) as nm, x.dia
    into r
    from (select distinct on (1) rp.payee_id, rp.dia, rp.t from resp rp order by 1, rp.dia, rp.t) x
    join public.payees py on py.id = x.payee_id
   order by x.dia, x.t, (select count(*) from resp z where z.payee_id = x.payee_id) desc, public._agenda_nome_curto(py.name), x.payee_id
   limit 1;
  if r.id is not null then
    return jsonb_build_object('payee_id', r.id, 'nome', r.nm, 'fonte', 'planejado', 'desde', r.dia,
                              'texto', format('%s (está no 1º dia marcado)', r.nm));
  end if;
  return null;
end;
$function$;

comment on function public._agenda_lider_da_os(uuid, date, uuid[]) is
  'Agenda de Produção (Fase 7c, P1; spec §3.6): o responsável da OS — dono (os_planejamento.lider_payee_id, a pessoa ativa: "Roberto (você disse)"), fez (o responsável do meio-dia feito mais antigo, pelas alocações de turno cumpridas/parciais/sem registro ou passadas e pelas diárias ligadas à OS por work_shift_os, como manhã; desempate mais meios-dias e o nome; o ajudante e o novo nunca: "Roberto (fez o 1º dia, ter 03/11)") ou planejado (o responsável do 1º meio-dia vigente futuro fora de p_ignorar: "Roberto (está no 1º dia marcado)"); nulo sem nenhum. {payee_id, nome, fonte, desde, texto}. Duro (o filtro 5 do P2) só dono ou fez, com modo_lider ligado. STABLE, sem grant.';

-- A avaliação do publicado (spec §5.1), a única que o P3, o P5 e as medidas usam: para cada (OS, dia, turno) com alocação vigente
-- de turno, não reserva, na janela — a equipe (as pessoas de turno sem o dono), o dono no turno, se é o último meio-dia vigente de
-- turno da OS (no plano inteiro) e a máscara do meio-dia (todos | o último, menos quando o dono fecha naquele dia e
-- habilidade_fechamento_cobre) — devolve as linhas em que _agenda_atende diz o que falta. Pula as OS com equipe dita pelo dono
-- (os_planejamento_equipe), salvo com p_com_dita. As habilidades por uma chamada de agenda_habilidades; o que a OS pede por uma de
-- os_exigencias por OS. STABLE, sem grant.
create or replace function public._agenda_meios_sem_quem_pede(p_de date, p_ate date, p_hoje date, p_os uuid[] default null,
                                                             p_com_dita boolean default false)
 returns table (os uuid, dia date, turno text, falta text, equipe uuid[], dono_turno boolean, ultimo boolean)
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c      public.agenda_config := public._agenda_cfg();
  v_dono uuid := public._agenda_dono(null);
  v_n    jsonb;
  v_md   jsonb;
  v_hab  jsonb := '{}'::jsonb;
  v_exg  jsonb := '{}'::jsonb;
  v_dalt int;
  m      jsonb;
  h      record;
  k      text;
  v_ex   int;
  v_f    text;
  v_eq   uuid[];
begin
  if p_de is null or p_ate is null or p_hoje is null then
    raise exception '_agenda_meios_sem_quem_pede: p_de, p_ate e p_hoje são obrigatórios.' using errcode = '22004';
  end if;
  v_n := jsonb_build_object('ene', c.habilidade_nivel_energizado, 'com', c.habilidade_nivel_comissionar,
                            'dia', c.habilidade_nivel_diagnostico, 'alt', c.habilidade_nivel_altura, 'par', c.habilidade_nivel_par);
  with vig as (
    select a.service_order_id as so, a.dia as d, a.turno as t, a.payee_id as pid
      from public.agenda_alocacoes a
     where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno'
       and a.dia between p_de and p_ate and (p_os is null or a.service_order_id = any (p_os))
       and (coalesce(p_com_dita, false)
            or not exists (select 1 from public.os_planejamento_equipe q where q.service_order_id = a.service_order_id))
  ),
  md as (
    select v.so, v.d, v.t,
           coalesce(array_agg(v.pid order by v.pid) filter (where v.pid is distinct from v_dono), '{}'::uuid[]) as eq,
           coalesce(bool_or(v.pid is not distinct from v_dono), false) as dt
      from vig v group by v.so, v.d, v.t
  ),
  fim as (
    select distinct on (a.service_order_id) a.service_order_id as so, a.dia as d, a.turno as t
      from public.agenda_alocacoes a
     where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno'
       and a.service_order_id in (select md.so from md)
     order by a.service_order_id, a.dia desc, a.turno desc
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'os', md.so, 'dia', md.d, 'turno', md.t, 'equipe', to_jsonb(md.eq), 'dono_turno', md.dt,
           'ultimo', (md.d, md.t) = (f.d, f.t),
           'fecha', exists (select 1 from public.agenda_alocacoes x
                             where x.service_order_id = md.so and x.dia = md.d and x.presenca = 'fechamento'
                               and x.payee_id is not distinct from v_dono and x.estado in ('publicada', 'fixada')))
           order by md.so, md.d, md.t), '[]'::jsonb)
    into v_md
    from md left join fim f on f.so = md.so;
  if jsonb_array_length(v_md) = 0 then
    return;
  end if;

  -- as habilidades de todos (uma chamada) e o que cada OS pede (uma por OS)
  for h in
    select * from public.agenda_habilidades(p_hoje,
             array(select distinct u.x::uuid from jsonb_array_elements(v_md) e, jsonb_array_elements_text(e -> 'equipe') u(x))
             || v_dono)
  loop
    v_hab := v_hab || jsonb_build_object(h.payee_id::text, jsonb_build_array(h.instala, h.comissiona, h.altura, h.papel));
    if h.eh_dono then
      v_dalt := h.altura;
    end if;
  end loop;
  for k in select distinct e ->> 'os' from jsonb_array_elements(v_md) e loop
    v_exg := v_exg || jsonb_build_object(k, public.os_exigencias(k::uuid, p_hoje));
  end loop;

  for m in select e from jsonb_array_elements(v_md) e loop
    v_ex := coalesce((v_exg #>> array[m ->> 'os', 'todos'])::int, 0)
            | case when (m ->> 'ultimo')::boolean
                        and not (c.habilidade_fechamento_cobre and (m ->> 'fecha')::boolean)
                   then coalesce((v_exg #>> array[m ->> 'os', 'ultimo'])::int, 0) else 0 end;
    v_eq := array(select u.x::uuid from jsonb_array_elements_text(m -> 'equipe') with ordinality u(x, o) order by u.o);
    v_f := public._agenda_atende(
             v_ex,
             array(select (v_hab -> u.x::text ->> 0)::int from unnest(v_eq) with ordinality u(x, o) order by u.o),
             array(select (v_hab -> u.x::text ->> 1)::int from unnest(v_eq) with ordinality u(x, o) order by u.o),
             array(select (v_hab -> u.x::text ->> 2)::int from unnest(v_eq) with ordinality u(x, o) order by u.o),
             array(select (v_hab -> u.x::text ->> 3)::int from unnest(v_eq) with ordinality u(x, o) order by u.o),
             (m ->> 'dono_turno')::boolean, v_dalt, v_n);
    if v_f is not null then
      os := (m ->> 'os')::uuid;
      dia := (m ->> 'dia')::date;
      turno := m ->> 'turno';
      falta := v_f;
      equipe := v_eq;
      dono_turno := (m ->> 'dono_turno')::boolean;
      ultimo := (m ->> 'ultimo')::boolean;
      return next;
    end if;
  end loop;
end;
$function$;

comment on function public._agenda_meios_sem_quem_pede(date, date, date, uuid[], boolean) is
  'Agenda de Produção (Fase 7c, P1; spec §5.1): a avaliação do publicado — para cada (OS, dia, turno) com alocação vigente de turno, não reserva, de p_de a p_ate (p_os, se veio): a equipe (as pessoas de turno sem o dono), o dono no turno, se é o último meio-dia vigente de turno da OS e o que falta pela regra única (_agenda_atende) com a máscara do meio-dia (todos | ultimo, menos quando o dono tem o fechamento vigente naquele dia e habilidade_fechamento_cobre); só as linhas com falta. Pula as OS com equipe dita pelo dono (os_planejamento_equipe), salvo com p_com_dita. As habilidades por agenda_habilidades(p_hoje) e o que a OS pede por os_exigencias. A única avaliação que o P3 (a violação), o P5 (a conferência) e as medidas usam. STABLE, sem grant.';

-- Os meios-dias sem o responsável (spec §5.1): os vigentes de turno, não reserva, de p_de a p_ate, de OS cujo responsável é dito
-- (dono) ou fez, sem ele e sem o dono no turno. Pula as OS com equipe dita (o filtro 5 não vale para elas). STABLE, sem grant.
create or replace function public._agenda_lideres_ausentes(p_de date, p_ate date, p_hoje date)
 returns table (os uuid, dia date, turno text, lider uuid, lider_nome text, equipe uuid[])
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  v_dono uuid := public._agenda_dono(null);
  r      record;
  v_l    jsonb;
begin
  if p_de is null or p_ate is null or p_hoje is null then
    raise exception '_agenda_lideres_ausentes: p_de, p_ate e p_hoje são obrigatórios.' using errcode = '22004';
  end if;
  for r in
    select distinct a.service_order_id as so
      from public.agenda_alocacoes a
     where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno' and a.dia between p_de and p_ate
       and not exists (select 1 from public.os_planejamento_equipe q where q.service_order_id = a.service_order_id)
     order by 1
  loop
    v_l := public._agenda_lider_da_os(r.so, p_hoje);
    continue when v_l is null or v_l ->> 'fonte' not in ('dono', 'fez');
    return query
      select r.so, g.dia, g.turno, (v_l ->> 'payee_id')::uuid, v_l ->> 'nome', g.eq
        from (select a.dia, a.turno,
                     coalesce(array_agg(a.payee_id order by a.payee_id) filter (where a.payee_id is distinct from v_dono),
                              '{}'::uuid[]) as eq,
                     coalesce(bool_or(a.payee_id is not distinct from v_dono), false) as dt
                from public.agenda_alocacoes a
               where a.service_order_id = r.so and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                 and a.presenca = 'turno' and a.dia between p_de and p_ate
               group by a.dia, a.turno) g
       where not g.dt and not ((v_l ->> 'payee_id')::uuid = any (g.eq))
       order by g.dia, g.turno;
  end loop;
end;
$function$;

comment on function public._agenda_lideres_ausentes(date, date, date) is
  'Agenda de Produção (Fase 7c, P1; spec §5.1): os meios-dias vigentes de turno, não reserva, de p_de a p_ate, de OS com responsável dito pelo dono ou que fez (_agenda_lider_da_os), sem ele e sem o dono no turno: {os, dia, turno, lider, lider_nome, equipe}. Pula as OS com equipe dita. A conferência da rodada em teste (P5) e as medidas. STABLE, sem grant.';

-- ── 7. As recriadas (o corpo da definição mais nova; as mudanças só nos blocos "-- FASE 7c:") ─────────────────────
-- Fora dos blocos nenhuma linha muda (no bloco do [c3-conf], a linha de antes fica como "-- antes:"). Quem recriar de novo qualquer
-- uma delas copia DESTA migration (spec-fase7c §R5.4 item 3: _agenda_e_novato do P1; _agenda_modo_da_pergunta do P8, que copia
-- desta; _agenda_tecnico_declarado desta).

-- _agenda_tecnico_declarado (de 20261101100860_agenda_fase77b_correcao3.sql)
create or replace function public._agenda_tecnico_declarado(p_payee uuid, p_dia date)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(p_payee is not null and p_dia is not null
     and p_payee is distinct from public._agenda_dono(null)
     -- FASE 7c: (7c P1, R5.1-5 (a)) a etiqueta: não é o técnico declarado quem tem etiqueta viva vale de ajudante (qualquer nível)
     -- ou de "instala só com alguém junto" (instala 1) — a palavra do dono (ou a proposta do gestor que valeu) de que ele não vai
     -- sozinho devolve a proteção do novato da 7b. Lida sob a RLS de agenda_etiquetas (o motor roda como service_role). Sem
     -- portão de modo: só devolve uma proteção.
     and not exists (select 1 from public.agenda_etiquetas e
                      where e.payee_id = p_payee and e.estado = 'vale'
                        and (e.etiqueta = 'ajudante' or (e.etiqueta = 'instala' and e.nivel = 1)))
     -- FASE 7c: fim
     and (select min(d.criado_em) from public.agenda_disponibilidade d
           where d.payee_id = p_payee and d.origem = 'dono' and d.dias_semana is not null and cardinality(d.dias_semana) > 0
             -- FASE 7c: [c3-conf] a linha do dono conta pelo que foi dito, sem o "criada até p_dia": o motor mede o novato na segunda da
             -- grade (_agenda_contexto, p_d_ini), e quem o dono declarava no meio da semana continuava novato para ele até a segunda
             -- seguinte (o achado "baixa" 1 da revisão da correção 3 da 7b). Em produção ninguém declara no futuro: é o greatest(p_dia,
             -- hoje) da spec, sem o relógio. Só tira restrição de quem o dono declarou.
             -- antes: and d.situacao in ('disponivel', 'confirmada') and (d.criado_em at time zone 'America/Sao_Paulo')::date <= p_dia)
             and d.situacao in ('disponivel', 'confirmada'))
             -- FASE 7c: fim
         >= (select py.created_at from public.payees py where py.id = p_payee)
            + make_interval(days => (public._agenda_cfg()).novato_dias), false);
$function$;

comment on function public._agenda_tecnico_declarado(uuid, date) is
  'Agenda de Produção (Fase 7b, correção 3; o R5.1-5 da spec da 7c, (a), sem a etiqueta): true para quem o dono declarou técnico — tem ou teve (viva ou substituída) uma linha de agenda_disponibilidade de origem dono com dias_semana não vazio, disponível ou confirmada, criada até p_dia, e o cadastro (payees.created_at) é de novato_dias ou mais antes da 1ª dessas linhas. O Alex (cadastro 05/08, padrão seg a sex do dono desde 30/10) é, também depois de responder os próprios dias (a linha do dono substituída por uma de origem diarista); o Mateus cadastrado agora com "toda terça" dita pelo dono não é. O dono nunca. _agenda_e_novato nunca marca quem é. STABLE, invoker. A 7c P1 a recria com a etiqueta. FASE 7c (P1; R5.1-5 (a) e [c3-conf]): com a etiqueta — não é declarado quem tem etiqueta viva vale de ajudante (qualquer nível) ou de instala 1 (a proteção do novato volta); e a linha do dono conta pelo que foi dito, sem o "criada até p_dia" (o motor mede o novato na segunda da grade: quem o dono declarava no meio da semana continuava novato até a segunda seguinte).';

-- _agenda_e_novato (de 20261101100860_agenda_fase77b_correcao3.sql)
create or replace function public._agenda_e_novato(p_payee uuid, p_dia date)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(p_payee is not null and p_dia is not null
     and p_payee is distinct from public._agenda_dono(null)
     -- FASE 7b: (correção 3) o técnico que o dono declarou nunca é novato (_agenda_tecnico_declarado: o padrão do dono, vivo
     -- ou substituído, e o cadastro de novato_dias ou mais antes dele). Sem isso, o perfil de diária do Alex (cadastro 05/08; o padrão do
     -- dono seg a sex desde 30/10), quando o dono o cadastrar, fazia dele novato por 30 dias, e com modo_dupla fora de desligado o motor
     -- nunca o deixava sozinho num meio-dia: sendo ele o único técnico, a agenda inteira parava. Quem não é declarado continua como antes.
     and not public._agenda_tecnico_declarado(p_payee, p_dia)
     -- FASE 7b: fim (correção 3)
     -- FASE 7c: (7c P1, R5.1-5 (b)) quem o dono disse que instala sozinho (etiqueta viva vale de instala 2 ou 3, de origem dono)
     -- nunca é novato: a palavra do dono vale sobre o perfil de diária. A etiqueta do gestor e a de ajudante não tiram o novato.
     -- Lida sob a RLS de agenda_etiquetas. Sem portão de modo: só tira restrição de quem o dono disse que vai sozinho.
     and not exists (select 1 from public.agenda_etiquetas e
                      where e.payee_id = p_payee and e.etiqueta = 'instala' and e.nivel >= 2 and e.origem = 'dono'
                        and e.estado = 'vale')
     -- FASE 7c: fim
     and exists (select 1 from public.work_profiles w
                  where w.payee_id = p_payee and w.vigencia_inicio <= p_dia and (w.vigencia_fim is null or w.vigencia_fim >= p_dia))
     and (select min(w.vigencia_inicio) from public.work_profiles w where w.payee_id = p_payee)
         > p_dia - (public._agenda_cfg()).novato_dias
     and coalesce((select sum(ws.fracao) from public.work_shifts ws join public.work_profiles w on w.id = ws.work_profile_id
                    where w.payee_id = p_payee and ws.data <= p_dia and ws.tipo = 'diaria' and ws.fracao is not null), 0)
         < (public._agenda_cfg()).novato_diarias, false);
$function$;

comment on function public._agenda_e_novato(uuid, date) is
  'Agenda de Produção (Fase 7b, P4; spec §5.3, AG7-04/AG7-10): true para quem tem perfil de diária vigente em p_dia, a 1ª vigência há menos de novato_dias e menos de novato_diarias diárias (a soma das frações lançadas até p_dia). O dono nunca. O motor (_agenda_contexto, com modo_dupla fora de desligado) nunca o deixa sozinho num meio-dia. É a regra única do novato (o 7c a usa). STABLE, invoker. CORREÇÃO 3 DA 7b (o R5.9 da spec da 7c; o (a) do R5.1-5 sem a etiqueta): nunca é novato quem o dono declarou técnico (_agenda_tecnico_declarado: tem ou teve, viva ou substituída, uma linha de origem dono com dias_semana, disponível ou confirmada, e o cadastro de novato_dias ou mais antes da 1ª delas) — o perfil de diária do Alex, cadastrado depois, não o faz novato, nem depois de ele responder os próprios dias (o padrão do dono substituído por um de origem diarista). Quem não é declarado, como antes: novato só com o perfil de diária (o Mateus cadastrado agora com "toda terça" e um perfil de hoje; o Bruno da fixture); sem perfil, o Mateus com um dia fixo não é novato nem vem sob demanda e conta como técnico (o limite da 7b; o ajudante nunca sozinho é da 7c, a etiqueta). FASE 7c (P1; R5.1-5 (b)): nunca é novato quem tem etiqueta viva vale de instala 2 ou 3 de origem dono (o dono disse que ele instala sozinho); o técnico declarado já não era (e, com a 7c, não é declarado quem tem etiqueta de ajudante ou de instala 1). O dia fixo sem perfil de diária ([c3-rev]) não passa por aqui: é o papel novo de agenda_habilidades.';

-- (FASE 7b P1, 20261101100000, a origem; a 7c P8 recria de novo a partir desta)
-- _agenda_modo_da_pergunta (de 20261101100000_agenda_fase7b_tabelas.sql)
create or replace function public._agenda_modo_da_pergunta(p_tipo text, p_chave text)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case
    when p_tipo in ('nao_cabe', 'segundo_atraso', 'atraso_longo', 'remarcar_confirmado', 'fixada_pelo_dono') then c.modo_proposta
    when p_tipo = 'chegou' and coalesce(p_chave, '') like 'chegou:fornecedor:%' then c.modo_material
    -- CORREÇÃO 29/10 (revisão): a equipe sem dias é da vigia.
    when p_tipo = 'equipe_sem_dias' then c.modo_vigia
    -- CORREÇÃO 29/10 (revisão): fim
    when p_tipo in ('conferencia', 'chegou', 'parada', 'estouro', 'duracao', 'material_conferir', 'padrao_do_dono', 'entrega')
      then c.modo_vigia
    when p_tipo in ('nfe_vincular', 'pix_material', 'previsao_fornecedor', 'fornecedor_cadastro', 'fornecedores_prazo')
      then c.modo_material
    when p_tipo in ('diaria', 'diaria_ligar') then c.modo_diaria
    when p_tipo in ('equipe_resposta', 'concluir') then c.modo_equipe
    when p_tipo in ('cliente_aprovar', 'cliente_aviso', 'cliente_resposta') then c.modo_cliente
    when p_tipo = 'aprendizado' then c.modo_aprendizado
    -- FASE 7: (7a P11) a pergunta da ficha da equipe de um dia pela estimativa (ficha_estimativa) é das mensagens à equipe
    -- (modo_equipe), não do gestor que marca: a proteção vale enquanto houver dia marcado pela estimativa na janela, também com
    -- *gestor, só propor* (sem isso a pergunta nasceria em teste e a ficha ficaria segurada sem o dono poder soltá-la). Vem antes
    -- da linha do 7a P1, que ainda a cita.
    when p_tipo = 'ficha_estimativa' then c.modo_equipe
    -- FASE 7: fim
    -- FASE 7b: (7b P1) a pergunta dos dias da semana ao dono (dias_semana) é do modo_dias; a chamada da equipe (equipe_cadastro)
    -- passa a ser do modo_cadastro quando ele sai de desligado (o 7b P3 faz o passo equipe do gestor ceder: uma pergunta só);
    -- desligado, continua a do gestor que marca (a linha do 7a P1, abaixo, que ainda a cita). Vem antes dela.
    when p_tipo = 'dias_semana' then c.modo_dias
    when p_tipo = 'equipe_cadastro' and c.modo_cadastro <> 'desligado' then c.modo_cadastro
    -- FASE 7b: fim
    -- FASE 7c: (7c P1) a pergunta de quem faz o quê (habilidade): a da equipe (habilidade:equipe:…, a proposta pelo histórico) é do
    -- modo_habilidade_propor; a de uma OS (habilidade:os:<os>, "ninguém com isso fica livre") é do modo_habilidade.
    when p_tipo = 'habilidade' and coalesce(p_chave, '') like 'habilidade:os:%' then c.modo_habilidade
    when p_tipo = 'habilidade' then c.modo_habilidade_propor
    -- FASE 7c: fim
    -- FASE 7: os tipos do gestor da agenda (7a P1). O dia avisado e o prometido são críticas do plano, como o remarcar
    -- confirmado; a revisão diária faz reavaliar e reestimar; a cobrança do "compre até", a dela; o resto é do gestor que marca.
    when p_tipo in ('dia_avisado', 'dia_prometido') then c.modo_proposta
    when p_tipo in ('reavaliar', 'reestimar') then public._agenda_gestor_modo('revisao')
    when p_tipo = 'compre_ate' then public._agenda_gestor_modo('compre_ate')
    when p_tipo in ('situacao', 'estimativa', 'equipe_cadastro', 'ficha_estimativa', 'bem_livre', 'sinal', 'onda', 'sabado')
      then public._agenda_gestor_modo('marcar')
    -- FASE 7: fim
  end
    from public.agenda_config c
   where c.id;
$function$;

comment on function public._agenda_modo_da_pergunta(text, text) is
  'Agenda de Produção (correção de 29/10, P3): o modo de agenda_config de quem grava cada tipo de pergunta — críticas do plano: modo_proposta; conferencia, chegou, parada, estouro, duracao, material_conferir, padrao_do_dono, entrega: modo_vigia; chegou:fornecedor:…, nfe_vincular, pix_material, previsao_fornecedor, fornecedor_cadastro, fornecedores_prazo: modo_material; diaria, diaria_ligar: modo_diaria; equipe_resposta, concluir: modo_equipe; cliente_*: modo_cliente; aprendizado: modo_aprendizado; outro tipo: null. A limpeza da vigia fecha a pergunta aberta em sombra quando este modo está ligado. STABLE, invoker, só o service_role. CORREÇÃO 29/10 (revisão): o tipo novo equipe_sem_dias é da vigia (modo_vigia). Fase 7a (P1): dia_avisado e dia_prometido = modo_proposta (críticas do plano); reavaliar e reestimar = o modo da revisão do gestor; compre_ate = o da cobrança; situacao, estimativa, equipe_cadastro, ficha_estimativa, bem_livre, sinal, onda e sabado = o do gestor que marca (_agenda_gestor_modo). Fase 7a (P11): ficha_estimativa = modo_equipe (a pergunta é das mensagens à equipe: a proteção da ficha vale com *gestor, só propor*); o bloco vem antes da linha do P1, que ainda a cita. Fase 7b (P1): dias_semana = modo_dias (a pergunta dos dias da semana ao dono); equipe_cadastro = modo_cadastro fora de desligado (a chamada da equipe passa a ser da 7b), senão o do gestor que marca, como antes. Fase 7c (P1): habilidade = modo_habilidade_propor (a pergunta de quem faz o quê da equipe, habilidade:equipe:…) ou modo_habilidade (a de uma OS, habilidade:os:<os>).';

-- ── 8. Portas ────────────────────────────────────────────────────────────────────────────────────────────────────
-- As leituras do painel (o que cada pessoa faz, o que a OS pede) e os dois textos que elas chamam (invoker: sem o grant, o
-- administrador que lê pelo painel esbarraria no texto): authenticated e service_role; nunca anon (spec §3.1-7: revogar de public E de
-- anon). As peças de dentro (a conta, a regra, o responsável e as duas avaliações do publicado): sem grant a ninguém, nem
-- service_role (só o motor, a violação, a rodada e as medidas as chamam, por dentro de quem é definer).
revoke all on function public.agenda_habilidades(date, uuid[]), public.os_exigencias(uuid, date),
  public._agenda_etiqueta_texto(text, smallint), public._agenda_exigencia_texto(integer, text, boolean) from public, anon;
grant execute on function public.agenda_habilidades(date, uuid[]), public.os_exigencias(uuid, date),
  public._agenda_etiqueta_texto(text, smallint), public._agenda_exigencia_texto(integer, text, boolean) to authenticated, service_role;

revoke all on function
  public._agenda_du_h(boolean[], integer, integer),
  public._agenda_atende(integer, integer[], integer[], integer[], integer[], boolean, integer, jsonb),
  public._agenda_lider_da_os(uuid, date, uuid[]), public._agenda_meios_sem_quem_pede(date, date, date, uuid[], boolean),
  public._agenda_lideres_ausentes(date, date, date)
  from public, anon, authenticated, service_role;

-- As recriadas mantêm as portas delas (create or replace não muda a ACL; repetidas aqui para a migration se bastar).
revoke all on function public._agenda_tecnico_declarado(uuid, date), public._agenda_e_novato(uuid, date) from public, anon;
grant execute on function public._agenda_tecnico_declarado(uuid, date), public._agenda_e_novato(uuid, date)
  to authenticated, service_role;
revoke all on function public._agenda_modo_da_pergunta(text, text) from public, anon, authenticated;
grant execute on function public._agenda_modo_da_pergunta(text, text) to service_role;
