-- Agenda de Produção, Fase 7, etapa 7d ("onde, quando e com o bem em que estado"), pacote P7: o que o dono diz vira dado no os_planejar.
-- Spec: spec-fase7d.md §5.7, §6.2 (a releitura), §4.2, com R6.1, R6.3-10, R6.5, R6.7b e R6.10. Notas: notas-fase7d.md, seção P7.
-- Depende de 20261107100000 a 20261107100550.
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (5 funções recriadas e 3 novas; nenhuma tabela, nenhuma coluna, nenhum dado)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7d/p7/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA (o montador para se outra
-- migration a definir depois da origem) e só ganha blocos "-- FASE 7d: … -- FASE 7d: fim" inseridos: tirados os blocos, é a origem, byte a byte (o R0 de
-- supabase/tests/agenda_fase7d_rascunho.sql confere).
--
-- O QUE MUDA:
--   1. agenda_rascunho_planejar ganha os 8 campos (25 em c_campos, com os 17 de antes: R6.3-10) e 5 valores no limpar. local → agenda_resolver_local; chega_em e sai_em →
--      agenda_data_dita pelo _agenda_data_conferida, a mesma régua das outras datas (no trecho), conferindo chegada < saída contra o que já está no rascunho e na OS;
--      autorizados → o mesmo resolvedor de pessoa de com_quem. Nada grava: só o *grava* do dono.
--   2. _agenda_aplicar_planejar grava local_id, local_fonte = dono e local_em; bem_situacao, a fonte e a hora; bem_exige; descer_quem; entrada_em, retirada_em e entrada_fonte =
--      dono; viagem; e as linhas de os_autorizados (fonte dono, local_id = o local resolvido, valido_ate nulo). A lista dita substitui a anterior, como a equipe: a releitura diz
--      a lista, e o erro para o lado seguro é perguntar de novo, não dar por autorizado quem saiu. Tudo vai ao histórico (antes, depois, até 20) e a uma ação local com *desfaz*.
--   3. O dono vence (o recado do P6): a pergunta local aberta fecha no *grava* quando ele diz o que ela gravaria, e a combinar ou a acesso que o que ele disse resolveu fecha na
--      hora, pelo _agenda_local_resolver, sem esperar o tique. O *desfaz* devolve a pergunta que o *grava* fechou.
--   4. _agenda_rascunho_frase: a releitura da §6.2, uma linha por campo dito. Sem os campos novos, a de antes, byte a byte.
--   5. _agenda_local_restaurar e _agenda_desfazer_local conhecem o que o os_planejar grava (R6.1 não as lista: sem isso o *desfaz* não voltaria tudo).
--   6. agenda_resolver_local (nova, §5.7), _agenda_local_palavras (as palavras que identificam um local) e _agenda_planejar_linhas (as linhas da §6.2, um lugar só).
--
-- SOMBRA: o que o dono diz é gravado em qualquer modo, porque ele é a fonte (§4.2 não condiciona, e o dia em que o modo ligar a palavra dele já está lá). Nada do motor muda: quem
-- lê estas colunas está atrás de _agenda_local_modo (R6.7b, R6.8). O R5 do teste prova: gravar com os 6 modos em sombra não muda agenda_propor, em md5, e o contraste com o
-- calendário ligado muda. Nenhuma função daqui está no caminho da vigia: só o *grava* e a conversa.
--
-- O QUE NÃO MUDA: agenda_resolver_os; agenda_rascunho_gravar; agenda_rascunho_ler; o motor; _agenda_local_decidir; as linhas do fechamento; nada ao cliente nem à equipe; o teto de
-- 113 ferramentas (nenhuma ferramenta nova); _agenda_chave_telefone, agenda_dia_util, agenda_somar_du, agenda_feriado, _agenda_cliente_dia e _agenda_nome_curto, que a sessão do
-- retorno chama; nada em _shared/ai/prompt.ts (é do P8).
--
-- PROVA: supabase/tests/agenda_fase7d_rascunho.sql na bancada (node scripts/bancada-agenda/rodar.mjs). APLICAR: só pelo roteiro de publicação da 7d, depois da 20261107100550 e
-- ANTES das funções de borda (o TS novo manda campos que a função de antes recusa: "o campo não existe"). IDEMPOTENTE: create or replace function, revoke, grant e comment.
--
-- DESFAZER: recriar _agenda_rascunho_frase de 20261102100550, agenda_rascunho_planejar e _agenda_aplicar_planejar de 20261101100100, _agenda_local_restaurar e
-- _agenda_desfazer_local de 20261107100500; drop de agenda_resolver_local, _agenda_planejar_linhas e _agenda_local_palavras. O que o dono já gravou nas colunas fica.
-- Quem recriar depois uma destas copia DESTA migration.

-- ── 1. Quem é o local ───────────────────────────────────────────────────────────────────────────────
-- As palavras que identificam: sem acento (o nfc vem antes, _agenda_normal não reconhece o acento decomposto: notas do P2) e sem as que não dizem lugar nenhum.
create or replace function public._agenda_local_palavras(p_texto text)
 returns text[]
 language sql
 immutable
 set search_path to 'public'
as $function$
  select coalesce(array_agg(t order by o), '{}'::text[])
    from unnest(string_to_array(public._agenda_normal(normalize(coalesce(p_texto, ''), nfc)), ' ')) with ordinality u(t, o)
   where t <> all (array['a', 'o', 'as', 'os', 'ao', 'aos', 'e', 'na', 'no', 'nas', 'nos', 'em', 'de', 'do', 'da', 'dos', 'das', 'com', 'para', 'pra', 'pro',
                         'la', 'ali', 'aqui', 'ai', 'ta', 'esta', 'fica', 'ficou', 'local', 'lugar']);
$function$;

comment on function public._agenda_local_palavras(text) is
  'Agenda de Produção (Fase 7d, P7; §5.7): as palavras de um texto que identificam um local: normalizadas (com o nfc antes de _agenda_normal), sem preposição, artigo e palavras que não dizem lugar nenhum. Só agenda_resolver_local usa.';

-- O local que o dono quis dizer. Nunca escolhe por conta própria: nome, apelido e as palavras do pátio identificam; cidade não ("Itajaí" são 2 locais; "Penha" pode ser outro lugar).
create or replace function public.agenda_resolver_local(p_ref text, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c_patio   constant text[] := array['patio', 'oficina', 'hbr'];   -- §5.7: as palavras do local patio_hbr; valem mesmo se os apelidos mudarem
  c_prefixo constant int := 3;   -- estrutural: abaixo disso, só a palavra inteira ("mp")
  c_lista   constant int := 6;   -- §5.7: nao_achei lista até 6 locais ativos
  v_ref     text := btrim(coalesce(p_ref, ''));
  v_tok     text[] := public._agenda_local_palavras(p_ref);
  v_toks    text := array_to_string(public._agenda_local_palavras(p_ref), ' ');
  v_c       jsonb;
  v_todos   boolean;
  v_achados jsonb;
  v_n       int;
  v_op      text[];
  v_nomes   text[];
begin
  if v_toks = '' then
    return jsonb_build_object('status', 'nao_achei', 'id', null, 'nome', null, 'opcoes', '[]'::jsonb,
      'texto', 'Diga qual local: o nome da marina ou do estaleiro, ou "pátio".');
  end if;
  if v_toks ~ '^casa (cliente|dele|dela)( |$)' then
    return jsonb_build_object('status', 'casa_cliente', 'id', null, 'nome', null, 'opcoes', '[]'::jsonb, 'texto', 'na casa do cliente');
  end if;

  -- Por local: o que sobra do que o dono disse, tirada a cidade do local ("Kalmar em Itajaí"), e quantas dessas palavras o nome e os apelidos explicam.
  with l as (
    select x.id, x.nome, x.municipio, public._agenda_normal(normalize(x.nome, nfc)) as ordem,
           array_to_string(public._agenda_local_palavras(x.municipio), ' ') as cidade,
           public._agenda_local_palavras(x.nome) || public._agenda_local_palavras(array_to_string(x.apelidos, ' '))
           || case when x.tipo = 'patio_hbr' then c_patio else '{}'::text[] end as palavras
      from public.agenda_locais x
     where x.ativo
  ),
  t as (
    select l.*, string_to_array(btrim(replace(' ' || v_toks || ' ', ' ' || l.cidade || ' ', ' ')), ' ') as resto
      from l
  ),
  c as (
    select t.*,
           (select count(*) from unnest(t.resto) r
             where exists (select 1 from unnest(t.palavras) w where w = r or (char_length(r) >= c_prefixo and w like r || '%')))::int as cobre,
           (select count(*) from unnest(t.resto) r where r = any (t.palavras))::int as exatas,
           array(select k from unnest(v_tok) k
                  where exists (select 1 from unnest(t.palavras) w where w = k or (char_length(k) >= c_prefixo and w like k || '%'))) as dele
      from t
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'municipio', c.municipio, 'so_cidade', v_toks = c.cidade,
                                               'tudo', cardinality(c.resto) > 0 and c.cobre = cardinality(c.resto),
                                               'exato', cardinality(c.resto) > 0 and c.exatas = cardinality(c.resto),
                                               'parte', cardinality(c.dele) > 0) order by c.ordem, c.id), '[]'::jsonb),
         not exists (select 1 from unnest(v_tok) k where not exists (select 1 from c c2 where k = any (c2.dele))),
         array_agg(c.nome order by c.ordem, c.id)
    into v_c, v_todos, v_nomes
    from c;

  -- O nome inteiro vence o "começa com"
  select coalesce(jsonb_agg(e order by o), '[]'::jsonb) into v_achados from jsonb_array_elements(v_c) with ordinality u(e, o)
   where (e ->> 'tudo')::boolean and (e ->> 'exato')::boolean;
  if jsonb_array_length(v_achados) = 0 then
    select coalesce(jsonb_agg(e order by o), '[]'::jsonb) into v_achados from jsonb_array_elements(v_c) with ordinality u(e, o)
     where (e ->> 'tudo')::boolean;
  end if;
  -- Só a cidade: mais de um local nela é pergunta; um só não identifica ("Penha" pode ser a casa do cliente)
  if jsonb_array_length(v_achados) = 0 then
    select coalesce(jsonb_agg(e order by o), '[]'::jsonb) into v_achados from jsonb_array_elements(v_c) with ordinality u(e, o)
     where (e ->> 'so_cidade')::boolean;
    if jsonb_array_length(v_achados) = 1 then
      v_achados := '[]'::jsonb;
    end if;
  end if;
  -- Cada palavra é de um local, mas nenhum explica todas ("pátio da Kalmar"): nunca escolho o pátio sozinho
  if jsonb_array_length(v_achados) = 0 and v_todos then
    select coalesce(jsonb_agg(e order by o), '[]'::jsonb) into v_achados from jsonb_array_elements(v_c) with ordinality u(e, o)
     where (e ->> 'parte')::boolean;
  end if;

  v_n := jsonb_array_length(v_achados);
  if v_n = 0 then
    return jsonb_build_object('status', 'nao_achei', 'id', null, 'nome', null, 'opcoes', '[]'::jsonb,
      'texto', format('Não achei "%s" no cadastro.', v_ref)
               || case when cardinality(v_nomes) > 0 then format(' Os locais que tenho: %s.', public._agenda_lista(v_nomes, c_lista)) else '' end);
  end if;
  if v_n = 1 then
    return jsonb_build_object('status', 'ok', 'id', v_achados -> 0 ->> 'id', 'nome', v_achados -> 0 ->> 'nome', 'opcoes', '[]'::jsonb,
      'texto', public._agenda_local_no(v_achados -> 0 ->> 'nome'));
  end if;
  v_op := array(select format('%s (%s)', e ->> 'nome', e ->> 'municipio') from jsonb_array_elements(v_achados) with ordinality u(e, o) order by o);
  return jsonb_build_object('status', 'ambiguo', 'id', null, 'nome', null,
    'opcoes', (select jsonb_agg(jsonb_build_object('id', e ->> 'id', 'nome', e ->> 'nome', 'municipio', e ->> 'municipio') order by o)
                 from jsonb_array_elements(v_achados) with ordinality u(e, o)),
    'texto', format('Qual deles: %s ou %s?', array_to_string(v_op[1:cardinality(v_op) - 1], ', '), v_op[cardinality(v_op)]));
end;
$function$;

comment on function public.agenda_resolver_local(text, date) is
  'Agenda de Produção (Fase 7d, P7; §5.7): o local que o dono quis dizer, entre os ativos de agenda_locais, no molde de agenda_resolver_os: {status ok|ambiguo|nao_achei|casa_cliente, id, nome, opcoes [{id, nome, municipio}], texto}. Casa pelo nome e pelos apelidos, normalizados: toda palavra dita tem de ser de UM local (o nome inteiro vence o "começa com"; "marina do joão" não é marina nenhuma). As palavras patio, oficina e hbr são do local patio_hbr; "pátio da Kalmar" não vira o pátio: pergunta. A cidade não identifica: cidade com 2 locais é pergunta, com 1 é nao_achei ("Penha" pode ser outro lugar). casa do cliente, casa dele e casa dela = casa_cliente. No ok, texto = o local com a preposição (_agenda_local_no). nao_achei lista os ativos, até 6. Nunca escolhe por conta própria. STABLE, invoker. p_hoje é da assinatura da §5.7: o ativo não depende do dia.';

-- ── 2. As linhas da §6.2 ────────────────────────────────────────────────────────────────────────────
-- Um lugar só: a releitura (_agenda_rascunho_frase) e o texto da ação (_agenda_aplicar_planejar). Os textos do bem são os de _agenda_estado_do_bem.
create or replace function public._agenda_planejar_linhas(p_d jsonb)
 returns text[]
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v     text[] := '{}';
  v_bem text := coalesce(nullif(p_d ->> 'bem_nome', ''), 'o barco');
  v_ent date := (p_d ->> 'entrada_em')::date;
  v_sai date := (p_d ->> 'retirada_em')::date;
begin
  if p_d ? 'local_id' then
    v := v || case when p_d ->> 'local_id' is not null then format('Local: %s.', p_d ->> 'local_nome')
                   when coalesce((p_d ->> 'local_casa')::boolean, false) then 'Local: na casa do cliente (anotei).'
                   else 'Tirei o local que eu tinha (volto a supor).' end;
  end if;
  if p_d ->> 'bem_situacao' is not null then
    v := v || format('%s: %s.', public._agenda_maiuscula(v_bem),
                     case p_d ->> 'bem_situacao' when 'agua' then 'na água' when 'seco' then 'em seco' when 'garagem_seca' then 'em seco (garagem)'
                                                 when 'patio' then 'no pátio' else 'com o cliente' end);
  end if;
  if p_d ->> 'descer_quem' is not null then
    v := v || format('Quem desce: %s.', p_d ->> 'descer_quem');
  end if;
  if p_d ->> 'bem_exige' is not null then
    v := v || case p_d ->> 'bem_exige' when 'agua' then 'O teste final é na água.'
                                       when 'seco' then format('O serviço é com %s em seco.', v_bem)
                                       else 'Tanto faz na água ou em seco.' end;
  end if;
  if v_ent is not null and v_sai is not null then
    v := v || format('%s chega %s e sai %s.', public._agenda_maiuscula(v_bem), public._dia_curto(v_ent), public._dia_curto(v_sai));
  elsif v_ent is not null then
    v := v || format('%s chega %s.', public._agenda_maiuscula(v_bem), public._dia_curto(v_ent));
  elsif v_sai is not null then
    v := v || format('%s sai %s.', public._agenda_maiuscula(v_bem), public._dia_curto(v_sai));
  end if;
  if p_d ? 'viagem' then
    v := v || case p_d ->> 'viagem' when 'regional' then 'Sem viagem (aqui na região).'
                                    when 'bate_volta' then 'Viagem: ida e volta no mesmo dia.'
                                    when 'pernoite' then 'Viagem com pernoite: a equipe vai e volta junta, em dias seguidos.'
                                    else 'Tirei a viagem que eu tinha (volto a supor).' end;
  end if;
  if jsonb_array_length(coalesce(p_d -> 'autorizados', '[]'::jsonb)) > 0 then
    v := v || format('Autorizados nesse serviço: %s.', public._agenda_lista(array(
                select case when (e ->> 'eh_dono')::boolean then 'você' else e ->> 'nome' end
                  from jsonb_array_elements(p_d -> 'autorizados') with ordinality t(e, o) order by o), null));
  end if;
  -- O que limpou
  if p_d ? 'entrada_em' and v_ent is null then
    v := v || 'Tirei a data de chegada.'::text;
  end if;
  if p_d ? 'retirada_em' and v_sai is null then
    v := v || 'Tirei a data de saída.'::text;
  end if;
  if p_d ? 'autorizados' and jsonb_array_length(p_d -> 'autorizados') = 0 then
    v := v || 'Tirei a lista de autorizados.'::text;
  end if;
  return v;
end;
$function$;

comment on function public._agenda_planejar_linhas(jsonb) is
  'Agenda de Produção (Fase 7d, P7; §6.2): as linhas da releitura do os_planejar, uma por campo dito, na ordem — o local (dito, na casa do cliente ou o que limpou), onde o bem está, quem desce, o que o serviço pede, a chegada e a saída, a viagem, os autorizados e o que limpou. Lê as chaves do rascunho (local_id, local_nome, local_casa, bem_situacao, descer_quem, bem_exige, entrada_em, retirada_em, viagem, autorizados, bem_nome). Chave nula = o dono tirou. Só _agenda_rascunho_frase e _agenda_aplicar_planejar chamam.';

-- ── 3. As recriadas ─────────────────────────────────────────────────────────────────────────────────

-- _agenda_rascunho_frase (de 20261102100550_agenda_fase7c_tarefas.sql). Fora da R6.1: a releitura mora aqui, não em agenda_rascunho_planejar
create or replace function public._agenda_rascunho_frase(p_tipo text, p_d jsonb)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_partes text[] := '{}';
  v_t      text;
  v_forn   text := nullif(p_d ->> 'fornecedor_txt', '');
  v_hoje   date := (p_d ->> 'hoje')::date;
  v_quando text;
  -- FASE 4: (P3) de onde veio o aviso ("nota 51038 da Kamell", "Pix de R$ 480,00 à Premel, seg 26/10").
  v_aviso  text;
  -- FASE 4: fim
  -- FASE 7b: (7b P2) a semana dita e as datas
  v_7b_dias smallint[];
  v_7b_fora smallint[];
  v_7b_n    int;
  -- FASE 7b: fim
  -- FASE 7d: (7d P7) a frase do resto da linha
  v_7d_cab  text;
  -- FASE 7d: fim
begin
  if p_tipo = 'planejar' then
    -- FASE 7d: (7d P7; §6.2) o que o dono disse do local e do bem: uma linha por campo, na ordem, depois da frase de sempre (a mesma função, sem essas chaves: o resto, byte a byte)
    if p_d ?| array['local_id', 'bem_situacao', 'bem_exige', 'descer_quem', 'entrada_em', 'retirada_em', 'viagem', 'autorizados'] then
      v_7d_cab := public._agenda_rascunho_frase(p_tipo, p_d - array['local_id', 'bem_situacao', 'bem_exige', 'descer_quem', 'entrada_em', 'retirada_em', 'viagem', 'autorizados']);
      return case when v_7d_cab = '' then '' else rtrim(v_7d_cab, '.') || '.' || E'\n' end
             || array_to_string(public._agenda_planejar_linhas(p_d), E'\n');
    end if;
    -- FASE 7d: fim
    if nullif(p_d ->> 'escopo_decidido', '') is not null then
      v_partes := v_partes || (p_d ->> 'escopo_decidido');
    end if;
    v_t := null;
    if p_d ->> 'dias' is not null then
      v_t := public._agenda_dias((p_d ->> 'dias')::numeric)
             || case when p_d ->> 'estimativa_fonte' = 'aceita' then ' (a minha estimativa, que você aceitou)' else '' end;
    end if;
    if jsonb_array_length(coalesce(p_d -> 'equipe', '[]'::jsonb)) > 0 then
      v_t := concat_ws(' ', v_t, 'com ' || public._agenda_lista(array(
               select case when (e ->> 'eh_dono')::boolean then 'você' else e ->> 'nome' end
                      || case e ->> 'turnos' when 'manha' then ' (de manhã)' when 'tarde' then ' (à tarde)' else '' end
                 from jsonb_array_elements(p_d -> 'equipe') with ordinality t(e, o) order by o), null));
    elsif p_d ? 'equipe' and p_d ->> 'dias' is null then
      v_t := 'sem ninguém marcado para ir';
    end if;
    if v_t is not null then
      v_partes := v_partes || v_t;
    end if;
    if p_d ->> 'dono' is not null then
      v_partes := v_partes || case p_d ->> 'dono' when 'abre_e_fecha' then 'você abre e fecha'
                                                 when 'sempre' then 'você fica o tempo todo' else 'você não vai' end;
    end if;
    if p_d ->> 'precisa_ate' is not null then
      v_partes := v_partes || ('o cliente precisa até ' || public._dia_curto((p_d ->> 'precisa_ate')::date));
    elsif p_d ? 'precisa_ate' then
      v_partes := v_partes || 'o cliente não tem mais prazo'::text;
    end if;
    if p_d ? 'bem' then
      v_partes := v_partes || case p_d #>> '{bem,modo}'
        when 'livre' then coalesce(p_d ->> 'bem_nome', 'o barco') || ' já está livre'
        when 'fora' then coalesce(p_d ->> 'bem_nome', 'o barco') || ' fica fora '
                         || public._agenda_quando_texto((p_d #>> '{bem,de}')::date, (p_d #>> '{bem,ate}')::date)
        else coalesce(p_d ->> 'bem_nome', 'o barco') || ' fica livre ' || public._dia_curto((p_d #>> '{bem,livre_em}')::date) end;
    end if;
    if p_d ->> 'nao_antes_de' is not null then
      v_partes := v_partes || ('não antes de ' || public._dia_curto((p_d ->> 'nao_antes_de')::date)
                               || case when coalesce(p_d ->> 'nao_antes_motivo', 'você disse') = 'você disse' then ''
                                       else ' (' || (p_d ->> 'nao_antes_motivo') || ')' end);
    elsif p_d ? 'nao_antes_de' then
      v_partes := v_partes || 'pode começar sem esperar data'::text;
    end if;
    if nullif(p_d ->> 'escopo_em_aberto', '') is not null then
      v_partes := v_partes || ('falta decidir: ' || (p_d ->> 'escopo_em_aberto'));
    elsif p_d ? 'escopo_em_aberto' and nullif(p_d ->> 'escopo_decidido', '') is null then
      v_partes := v_partes || 'nada mais a decidir no escopo'::text;
    end if;
    if p_d ->> 'congelada_ate' is not null then
      v_partes := v_partes || ('em espera até ' || public._dia_curto((p_d ->> 'congelada_ate')::date)
                               || case when p_d ->> 'revisar_em' is distinct from p_d ->> 'congelada_ate'
                                       then ' (rever ' || public._dia_curto((p_d ->> 'revisar_em')::date) || ')' else '' end);
    elsif p_d ? 'congelada_ate' then
      v_partes := v_partes || 'sai da espera'::text;
    end if;
    if p_d ->> 'prioridade' is not null then
      v_partes := v_partes || case when (p_d ->> 'prioridade')::int = 1 then 'passa na frente (prioridade 1)'
                                   else 'prioridade ' || (p_d ->> 'prioridade') end;
    end if;
    if p_d ->> 'sem_material' is not null then
      v_partes := v_partes || case when (p_d ->> 'sem_material')::boolean then 'não tem peça a comprar'
                                   else 'tem peça a conferir' end;
    end if;
    -- FASE 2: quanto dá para adiantar no pátio sem o bem (bancada: barramento, chicote).
    if p_d ? 'adiantavel_patio' then
      v_partes := v_partes || case when p_d ->> 'adiantavel_patio' is null then 'nada a adiantar no pátio'
                                   else 'dá para adiantar ' || public._agenda_dias((p_d ->> 'adiantavel_patio')::numeric) || ' no pátio' end;
    end if;
    -- FASE 5: o que o dono disse ao cliente ("você disse ao Flávio: ter 03/11 (data firme)") e como o serviço é dito a ele
    if jsonb_typeof(p_d -> 'prometido') = 'object' then
      v_partes := v_partes || format('você disse ao %s: %s (%s)', coalesce(nullif(p_d ->> 'curto', ''), 'cliente'),
        case when p_d #>> '{prometido,de}' = p_d #>> '{prometido,ate}' then public._dia_curto((p_d #>> '{prometido,ate}')::date)
             else format('de %s a %s', public._dia_curto((p_d #>> '{prometido,de}')::date),
                         public._dia_curto((p_d #>> '{prometido,ate}')::date)) end,
        case when p_d #>> '{prometido,tipo}' = 'firme' then 'data firme' else 'uma faixa' end);
    end if;
    if nullif(p_d ->> 'servico_cliente', '') is not null then
      v_partes := v_partes || format('o serviço, para o cliente: %s', p_d ->> 'servico_cliente');
    end if;
    -- FASE 5: fim
    -- FASE 7b: (7b P2, §6.6) a dupla dita ("vai com 1 pessoa só", "vai em dupla o tempo todo", "vai em dupla nos 2 primeiros
    -- meios-dias") e, com menos técnicos do que ela pede, o aviso de que a OS espera
    if p_d ->> 'dupla' is not null then
      v_7b_n := (p_d ->> 'dupla_meios')::int;
      v_partes := v_partes || case p_d ->> 'dupla'
        when 'nao' then 'vai com 1 pessoa só'
        when 'todos' then 'vai em dupla o tempo todo'
        when 'inicio' then case when v_7b_n = 1 then 'vai em dupla no primeiro meio-dia'
                                else format('vai em dupla nos %s primeiros meios-dias', v_7b_n) end
        else case when v_7b_n = 1 then 'vai em dupla no último meio-dia'
                  else format('vai em dupla nos %s últimos meios-dias', v_7b_n) end end;
    end if;
    if nullif(p_d ->> 'dupla_aviso', '') is not null then
      return array_to_string(v_partes, '; ') || '. ' || (p_d ->> 'dupla_aviso');
    end if;
    -- FASE 7b: fim
    return array_to_string(v_partes, '; ');
  end if;

  if p_tipo = 'material' then
    v_t := case p_d ->> 'acao'
      when 'na_mao' then
        case when p_d ->> 'quantidade_na_mao' is not null
             then format('%s de %s na mão', public._os_material_qtd((p_d ->> 'quantidade_na_mao')::numeric),
                         public._os_material_qtd((p_d ->> 'quantidade_necessaria')::numeric))
             when (p_d ->> 'chegou_em')::date = v_hoje then 'na mão (desde hoje)'
             else 'na mão desde ' || public._dia_curto((p_d ->> 'chegou_em')::date) end
      when 'comprado' then
        'comprado' || case when (p_d ->> 'comprado_em')::date = v_hoje then ' hoje'
                           else ' em ' || public._dia_curto((p_d ->> 'comprado_em')::date) end
        || case when p_d ->> 'previsao_ate' is not null
                then ', chega ' || public._dia_curto((p_d ->> 'previsao_ate')::date) || ' (você disse)' else '' end
      when 'a_caminho' then
        case when p_d ->> 'previsao_ate' is null then 'a caminho, sem previsão'
             when p_d ->> 'previsao_de' is not null then
               format('chega entre %s e %s (você disse)', public._dia_curto((p_d ->> 'previsao_de')::date),
                      public._dia_curto((p_d ->> 'previsao_ate')::date))
             else 'chega ' || public._dia_curto((p_d ->> 'previsao_ate')::date) || ' (você disse)' end
      when 'falta' then
        case when coalesce((p_d ->> 'vou_comprar')::boolean, false) then
               case when p_d ->> 'compra_prevista_em' is null then 'você vai comprar'
                    else 'você compra ' || public._dia_curto((p_d ->> 'compra_prevista_em')::date) end
             else 'falta comprar' end
      when 'sem_previsao' then 'comprado, sem previsão de chegada'
      when 'dispensado' then 'não precisa mais (sai da lista)'
      else null end;
    -- FASE 4: (P3) o aviso (a nota, o Pix ou a mensagem que a agenda perguntou) diz de onde veio; o fornecedor já está nele.
    if jsonb_typeof(p_d -> 'aviso') = 'object' then
      v_aviso := p_d -> 'aviso' ->> 'curto';
      v_t := case
        when coalesce((p_d ->> 'nota_chegou')::boolean, false) then
          format('na mão desde %s (a %s entrou no estoque)', public._dia_curto((p_d ->> 'chegou_em')::date), v_aviso)
        when p_d ->> 'acao' = 'na_mao' and p_d ->> 'quantidade_na_mao' is null then
          format('na mão desde %s (%s)', case when (p_d ->> 'chegou_em')::date = v_hoje then 'hoje'
                                              else public._dia_curto((p_d ->> 'chegou_em')::date) end, v_aviso)
        when p_d ->> 'acao' = 'a_caminho' and p_d -> 'aviso' ->> 'tipo' = 'nfe' then
          'a caminho pela ' || v_aviso
          || case when p_d ->> 'previsao_ate' is null then ', sem previsão de chegada'
                  when p_d ->> 'previsao_fonte' = 'dono' then ', chega ' || public._dia_curto((p_d ->> 'previsao_ate')::date) || ' (você disse)'
                  else ', chega por volta de ' || public._dia_curto((p_d ->> 'previsao_ate')::date) end
        when p_d ->> 'acao' = 'a_caminho' and p_d ->> 'previsao_ate' is not null and p_d ->> 'previsao_fonte' = 'fornecedor' then
          format('a caminho, chega por volta de %s (%s)', public._dia_curto((p_d ->> 'previsao_ate')::date), v_aviso)
        when p_d ->> 'acao' = 'comprado' and p_d -> 'aviso' ->> 'tipo' = 'pix' and p_d ->> 'previsao_ate' is null
             and v_aviso like 'Pix %' then
          'comprado pelo ' || v_aviso
        else coalesce(v_t || ' (' || v_aviso || ')', v_t) end;
      if p_d ->> 'critico' is not null and not (p_d ->> 'critico')::boolean then
        v_t := coalesce(v_t || ' (dá para começar sem)', 'dá para começar sem');
      end if;
      return v_t;
    end if;
    -- FASE 4: fim
    if v_t is not null and v_forn is not null and p_d ->> 'acao' <> 'dispensado' then
      v_t := v_t || ', fornecedor ' || v_forn;
    end if;
    if p_d ->> 'critico' is not null and not (p_d ->> 'critico')::boolean then
      v_t := coalesce(v_t || ' (dá para começar sem)', 'dá para começar sem');
    end if;
    return v_t;
  end if;

  if p_tipo = 'disponibilidade' then
    -- FASE 7b: (7b P2, §6.6, R4.2(c)) quem não está na equipe (a pessoa do cadastro): a frase de sempre e o aviso de que, com
    -- *grava*, ela entra
    if coalesce((p_d ->> 'fora_da_equipe')::boolean, false) then
      return public._agenda_rascunho_frase(p_tipo, p_d - 'fora_da_equipe')
             || format('. %s ainda não está na equipe da agenda: com *grava*, ele entra %s', p_d ->> 'nome',
                       case when coalesce((p_d ->> 'padrao')::boolean, false) then 'com esses dias, toda semana'
                            when p_d ? 'semana' or p_d ? 'datas' or p_d ->> 'de' is distinct from p_d ->> 'ate' then 'só nesses dias'
                            else 'só nesse dia' end);
    end if;
    -- a semana dita ("vem seg, ter e qui (e não vem qua e sex)"; o dono: "fica em campo seg e qua; nos outros dias, só abre e
    -- fecha"); o rótulo leva a semana ("Roberto, semana de 16/11")
    if p_d ? 'semana' then
      v_7b_dias := array(select jsonb_array_elements_text(coalesce(p_d -> 'dias_semana', '[]'::jsonb))::smallint);
      v_7b_fora := array(select x::smallint from generate_series(1, 5) x where not (x::smallint = any (v_7b_dias)) order by 1);
      if cardinality(v_7b_dias) = 0 and not coalesce((p_d ->> 'sabado')::boolean, false) then
        return case when (p_d ->> 'eh_dono')::boolean then 'só abre e fecha' else 'não vem' end;
      end if;
      if (p_d ->> 'eh_dono')::boolean then
        return 'fica em campo ' || public._agenda_dias_curtos(v_7b_dias, (p_d ->> 'sabado')::boolean)
               || case when cardinality(v_7b_fora) > 0 then '; nos outros dias, só abre e fecha' else '' end;
      end if;
      return 'vem ' || public._agenda_dias_curtos(v_7b_dias, (p_d ->> 'sabado')::boolean)
             || case when cardinality(v_7b_fora) > 0 then ' (e não vem ' || public._agenda_dias_curtos(v_7b_fora) || ')' else '' end;
    end if;
    -- as datas de quem vem sob demanda ("vem qua 11/11 e qui 12/11 (só nesses dias)")
    if p_d ? 'datas' then
      return case when (p_d ->> 'eh_dono')::boolean then 'em campo ' else 'vem ' end
             || public._agenda_lista(array(select public._dia_curto(x::date)
                                                  || case when extract(isodow from x::date)::int = 6 then ' de manhã' else '' end
                                             from jsonb_array_elements_text(p_d -> 'datas') with ordinality t(x, o) order by o), null)
             || ' (só nesses dias)';
    end if;
    -- FASE 7b: fim
    v_quando := case when (p_d ->> 'padrao')::boolean
                     then public._agenda_dias_semana_texto(array(select jsonb_array_elements_text(p_d -> 'dias_semana')::smallint))
                     else public._agenda_quando_texto((p_d ->> 'de')::date, (p_d ->> 'ate')::date) end;
    return case p_d ->> 'dito'
      when 'vem' then case when (p_d ->> 'eh_dono')::boolean then 'em campo ' else 'vem ' end || v_quando
      when 'nao_vem' then case when (p_d ->> 'eh_dono')::boolean then 'fora de campo ' else 'não vem ' end || v_quando
      when 'so_manha' then v_quando || ' à tarde, não'
      else v_quando || ' de manhã, não' end
      || case when coalesce((p_d ->> 'sabado_por_data')::boolean, false) then ' (sábado eu só conto por data)' else '' end;
  end if;

  -- FASE 2: os pedidos da conversa (marcar, aplicar/decidir, desfazer, andamento) chegam com a frase pronta do banco.
  if p_tipo in ('marcar', 'aplicar', 'desfazer', 'andamento') then
    return p_d ->> 'frase_pronta';
  end if;

  -- FASE 4: o prazo do fornecedor chega com a frase pronta do banco (agenda_rascunho_fornecedor).
  if p_tipo = 'fornecedor' then
    return p_d ->> 'frase_pronta';
  end if;
  -- FASE 4: fim
  -- FASE 4: (P3) "não é material de serviço" (a nota, o Pix ou a mensagem) chega com a frase pronta (agenda_rascunho_material).
  if p_tipo = 'aviso' then
    return p_d ->> 'frase_pronta';
  end if;
  -- FASE 4: fim
  -- FASE 7c: (7c P4, §5.4, §6.3) quem faz o quê, o que a OS pede e o responsável (agenda_rascunho_habilidade): a releitura sai dos
  -- dados (_agenda_habilidade_frase: "Roberto instala sozinho", "pede quem sobe no teto em todos os dias", "o responsável é Roberto
  -- (fica em todos os dias)", "fica como eu marquei (…)")
  if p_tipo = 'habilidade' then
    return public._agenda_habilidade_frase(p_d);
  end if;
  -- FASE 7c: fim
  -- FASE 7c: (7c P8, §16.5.6, §16.6.9) as etapas de um serviço (agenda_rascunho_etapa): a releitura sai dos dados (_agenda_etapa_frase:
  -- ""…" já está feita", "acrescentar "…" (no fim, antes de testar e entregar)", "dividir "…" em 3: …")
  if p_tipo = 'etapa' then
    return public._agenda_etapa_frase(p_d);
  end if;
  -- FASE 7c: fim
  raise exception '_agenda_rascunho_frase: tipo "%" não existe', p_tipo using errcode = '22023';
end;
$function$;

comment on function public._agenda_rascunho_frase(text, jsonb) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): a frase de uma linha do rascunho, montada dos dados já resolvidos — planejar ("2 dias com Roberto e João (à tarde); você abre e fecha; dá para adiantar 1 dia no pátio"), material ("chega ter 03/11 (você disse)", "você compra ter 27/10, fornecedor Premel") e disponibilidade ("em campo de seg a sex", "toda sexta à tarde, não"); os pedidos da Fase 2 (marcar, aplicar, desfazer, andamento), o prazo do fornecedor (Fase 4) e o "não é de serviço" (tipo aviso, Fase 4, P3) trazem a frase pronta (dados.frase_pronta); o material com o aviso diz de onde veio ("a caminho pela nota 51038 da Kamell, chega por volta de sex 30/10", "na mão desde hoje (Pix de R$ 480,00 à Premel, seg 26/10)", "na mão desde qua 28/10 (a nota 51038 da Kamell entrou no estoque)"). Fase 5 (P5): o planejar diz o que o dono disse ao cliente ("você disse ao Flávio: ter 03/11 (data firme)"; faixa: "de qua 04/11 a dom 08/11 (uma faixa)") e como o serviço é dito a ele ("o serviço, para o cliente: a instalação do compressor"). Fase 7b (P2, §6.6): o planejar com a dupla dita ("vai com 1 pessoa só", "vai em dupla o tempo todo", "vai em dupla nos 2 primeiros meios-dias", "… nos 2 últimos meios-dias"; 1 = "no primeiro meio-dia") e, com menos técnicos do que ela pede, o aviso "Hoje só Alex está na equipe: até você chamar alguém e me dizer os dias, eu não marco Lenine"; a disponibilidade com a semana ("vem seg, ter e qui (e não vem qua e sex)"; o dono: "fica em campo seg e qua; nos outros dias, só abre e fecha"; "não vem"; "só abre e fecha") e com as datas ("vem qua 11/11 e qui 12/11 (só nesses dias)"; o sábado "de manhã"); quem não está na equipe ganha "Mateus ainda não está na equipe da agenda: com *grava*, ele entra só nesses dias". FASE 7c (P4, §5.4, §6.3): o tipo habilidade sai de _agenda_habilidade_frase — "Roberto instala sozinho", "pede quem sobe no teto em todos os dias", "o responsável é Roberto (fica em todos os dias)", "fica sem responsável fixo", "fica como eu marquei (Roberto instala sozinho; João é ajudante)". Os outros tipos, os de antes, byte a byte. FASE 7c (P8, §16.5.6, §16.6.9): o tipo etapa sai de _agenda_etapa_frase — ""Instalação de porta fusíveis - distribuição de energia 12v" já está feita", "acrescentar "Trocar a bomba d''água" (no fim, antes de testar e entregar)", "dividir "…" em 3: …". Os outros tipos, os de antes, byte a byte. FASE 7d (P7, §6.2): com as chaves do local e do bem (local_id, bem_situacao, bem_exige, descer_quem, entrada_em, retirada_em, viagem, autorizados), a frase de sempre do resto da linha e, depois, uma linha por campo dito (_agenda_planejar_linhas). Sem elas, a de antes, byte a byte.';

-- agenda_rascunho_planejar (de 20261101100100_agenda_fase7b_disponibilidade.sql, a da R6.1)
create or replace function public.agenda_rascunho_planejar(p_autor uuid, p_canal text, p_os text, p_dados jsonb,
                                                           p_trecho text, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor  uuid := public._autor_da_agenda(p_autor);
  d        jsonb := coalesce(p_dados, '{}'::jsonb);
  c_campos constant text[] := array['dias', 'com_quem', 'dono', 'precisa_ate', 'bem_fora', 'bem_livre_em', 'nao_antes_de',
                                    -- FASE 7d: (7d P7; §5.7, R6.3-10) os 8 do local e do bem: 25 com os 17 de antes
                                    'local', 'bem_onde', 'bem_exige', 'descer_quem', 'chega_em', 'sai_em', 'viagem', 'autorizados',
                                    -- FASE 7d: fim
                                    'nao_antes_motivo', 'escopo_em_aberto', 'escopo_decidido', 'congelar_ate', 'revisar_em',
                                    'prioridade', 'sem_material', 'aceitar_sugestao', 'limpar',
                                    'adiantavel_patio'];   -- FASE 2: adiantavel_patio
  -- O que o dono desfaz ("pode voltar", "tira da espera", "não tem mais data mínima", "o cliente não tem mais prazo",
  -- "o escopo está resolvido"): o campo volta a vazio.
  c_limpar constant text[] := array['espera', 'nao_antes', 'prazo', 'escopo', 'patio'];   -- FASE 2: patio
  v_limpar text[] := '{}';
  v_k      text;
  v_ro     jsonb;
  v_os     uuid;
  v_out    jsonb := '{}'::jsonb;
  v_n      numeric;
  v_sug    jsonb;
  v_x      jsonb;
  v_rp     jsonb;
  v_turnos text;
  v_equipe jsonb := '[]'::jsonb;
  v_dt     jsonb;
  v_dt2    jsonb;
  v_bem    text;
  v_txt    text;
  v_dias_os numeric;   -- FASE 2
  -- FASE 5: o que foi dito ao cliente e como o serviço é dito a ele
  c_serv_max constant int := 40;   -- estrutural: o serviço aparece duas vezes no aviso de atraso (que tem de caber em 400)
  v_prom   text;
  v_serv   text;
  v_dtp    jsonb;
  -- FASE 5: fim
  -- FASE 7b: (7b P2; R4.3(b)) a dupla dita pelo planejar
  v_7b_dupla text;
  v_7b_meios_txt text;
  v_7b_tem_meios boolean := false;
  v_7b_meios int;
  v_7b_tec   text[];
  v_7b_aviso text;
  -- FASE 7b: fim
  -- FASE 7d: (7d P7; §5.7) o que o dono desfaz do local e do bem, o local, os autorizados e as datas contra o que já foi dito
  c_7d_limpar constant text[] := array['local', 'entrada', 'retirada', 'viagem', 'autorizados'];
  c_7d_quem_min constant int := 2;    -- estrutural: o CHECK de os_planejamento.descer_quem
  c_7d_quem_max constant int := 80;   -- estrutural: o CHECK de os_planejamento.descer_quem
  v_7d_limpar text[] := '{}';
  v_7d_rl    jsonb;
  v_7d_txt   text;
  v_7d_aut   jsonb := '[]'::jsonb;
  v_7d_velho jsonb;
  v_7d_ent   date;
  v_7d_sai   date;
  -- FASE 7d: fim
begin
  if p_canal is null or p_canal not in ('whatsapp', 'painel') then
    raise exception 'agenda_rascunho_planejar: canal "%" inválido (whatsapp ou painel)', p_canal using errcode = '22023';
  end if;
  -- A agenda desligada (agenda_config.modo_leitura) não anota: sem o *grava* ligado, o rascunho não teria saída.
  if (public._agenda_cfg()).modo_leitura = 'desligado' then
    return public._agenda_recusa('A agenda de produção está desligada agora: não anotei nada.', 'desligada');
  end if;
  if jsonb_typeof(d) <> 'object' then
    raise exception 'agenda_rascunho_planejar: p_dados tem de ser um objeto' using errcode = '22023';
  end if;
  -- FASE 5: prometido (a data como o dono disse ao cliente) e servico_cliente (como o cliente chama o serviço) saem de d
  -- antes da conferência dos campos; entram no rascunho no fim (v_out), conferidos.
  v_prom := nullif(btrim(coalesce(d ->> 'prometido', '')), '');
  v_serv := nullif(btrim(regexp_replace(coalesce(d ->> 'servico_cliente', ''), '\s+', ' ', 'g')), '');
  d := d - 'prometido' - 'servico_cliente';
  -- FASE 5: fim
  -- FASE 7b: (7b P2) a dupla (nao | todos | inicio | fim) e os meios-dias dela saem de d antes da conferência dos campos; entram no
  -- rascunho no fim (v_out), conferidos
  v_7b_dupla := nullif(lower(btrim(coalesce(d ->> 'dupla', ''))), '');
  v_7b_tem_meios := d ? 'dupla_meios' and jsonb_typeof(d -> 'dupla_meios') <> 'null';
  v_7b_meios_txt := d ->> 'dupla_meios';
  d := d - 'dupla' - 'dupla_meios';
  -- FASE 7b: fim
  select k into v_k from jsonb_object_keys(d) k where k <> all (c_campos) order by k limit 1;
  if v_k is not null then
    raise exception 'agenda_rascunho_planejar: o campo "%" não existe', v_k using errcode = '22023';
  end if;
  d := jsonb_strip_nulls(d);
  -- FASE 7d: (7d P7; §5.7) o que o dono desfaz do local e do bem sai de limpar aqui: a lista de antes e as frases dela ficam como estavam. Pôr e tirar a mesma coisa na mesma
  -- chamada é erro de quem chamou.
  if jsonb_typeof(d -> 'limpar') = 'array' then
    v_7d_limpar := array(select distinct x from jsonb_array_elements_text(d -> 'limpar') x where x = any (c_7d_limpar) order by 1);
    d := jsonb_set(d, '{limpar}', coalesce((select jsonb_agg(e) from jsonb_array_elements(d -> 'limpar') e where e #>> '{}' <> all (c_7d_limpar)), '[]'::jsonb));
    if ('local' = any (v_7d_limpar) and d ? 'local')
       or ('entrada' = any (v_7d_limpar) and d ? 'chega_em')
       or ('retirada' = any (v_7d_limpar) and d ? 'sai_em')
       or ('viagem' = any (v_7d_limpar) and d ? 'viagem')
       or ('autorizados' = any (v_7d_limpar) and d ? 'autorizados') then
      raise exception 'agenda_rascunho_planejar: limpar e o mesmo campo na mesma chamada' using errcode = '22023';
    end if;
  end if;
  -- FASE 7d: fim
  if d ? 'limpar' then
    if jsonb_typeof(d -> 'limpar') <> 'array' then
      raise exception 'agenda_rascunho_planejar: limpar tem de ser uma lista (espera, nao_antes, prazo ou escopo)' using errcode = '22023';
    end if;
    v_limpar := array(select distinct x from jsonb_array_elements_text(d -> 'limpar') x order by 1);
    select x into v_k from unnest(v_limpar) x where x <> all (c_limpar) order by 1 limit 1;
    if v_k is not null then
      raise exception 'agenda_rascunho_planejar: limpar "%" não existe (espera, nao_antes, prazo ou escopo)', v_k using errcode = '22023';
    end if;
    -- Pôr e tirar a mesma coisa na mesma chamada é erro de quem chamou.
    if ('espera' = any (v_limpar) and (d ? 'congelar_ate' or d ? 'revisar_em'))
       or ('nao_antes' = any (v_limpar) and (d ? 'nao_antes_de' or d ? 'nao_antes_motivo'))
       or ('prazo' = any (v_limpar) and d ? 'precisa_ate')
       or ('escopo' = any (v_limpar) and d ? 'escopo_em_aberto')
       or ('patio' = any (v_limpar) and d ? 'adiantavel_patio') then   -- FASE 2
      raise exception 'agenda_rascunho_planejar: limpar e o mesmo campo na mesma chamada' using errcode = '22023';
    end if;
  end if;
  if nullif(btrim(p_trecho), '') is null then
    return public._agenda_recusa('Me diga com as suas palavras o que mudou nesse serviço.', 'sem_trecho');
  end if;

  v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
  if v_ro ->> 'status' <> 'ok' then
    return public._agenda_recusa_da_os(v_ro);
  end if;
  v_os := (v_ro ->> 'id')::uuid;

  -- Dias: o número dito (no trecho) ou "aceito a sua estimativa" (a sugestão, com fonte 'aceita').
  if d ? 'dias' then
    begin
      v_n := (d ->> 'dias')::numeric;
    exception when others then
      v_n := null;
    end;
    if v_n is null or v_n <= 0 or v_n > 60 or v_n * 2 <> trunc(v_n * 2) then
      return public._agenda_recusa('Quantos dias? Diga em dias ou meio dia (por exemplo, "2 dias" ou "um dia e meio").', 'dias_invalido');
    end if;
    if not public._agenda_trecho_tem_numero(p_trecho, v_n) then
      return public._agenda_recusa(format('Não achei "%s" no que você disse; me diga de novo quantos dias.', public._agenda_dias(v_n)),
                                   'fora_do_trecho');
    end if;
    v_out := v_out || jsonb_build_object('dias', trim_scale(v_n), 'estimativa_fonte', 'dono');
  elsif coalesce((d ->> 'aceitar_sugestao')::boolean, false) then
    v_sug := public.os_duracao_sugerida(v_os);
    if coalesce((v_sug ->> 'sem_base')::boolean, false) or v_sug ->> 'sugerida' is null then
      return public._agenda_recusa('O orçamento não dá base para eu estimar: quantos dias?', 'sem_base');
    end if;
    v_out := v_out || jsonb_build_object('dias', (v_sug ->> 'sugerida')::numeric, 'estimativa_fonte', 'aceita');
  end if;

  -- Quem vai, por turno ("dia" quando não disse).
  if d ? 'com_quem' then
    if jsonb_typeof(d -> 'com_quem') <> 'array' then
      raise exception 'agenda_rascunho_planejar: com_quem tem de ser uma lista' using errcode = '22023';
    end if;
    for v_x in select e from jsonb_array_elements(d -> 'com_quem') with ordinality t(e, o) order by o loop
      if jsonb_typeof(v_x) = 'string' then
        v_x := jsonb_build_object('pessoa', v_x #>> '{}');
      end if;
      v_turnos := coalesce(nullif(btrim(v_x ->> 'turnos'), ''), 'dia');
      if v_turnos not in ('dia', 'manha', 'tarde') then
        raise exception 'agenda_rascunho_planejar: turnos "%" inválido (dia, manha ou tarde)', v_turnos using errcode = '22023';
      end if;
      v_rp := public.agenda_resolver_pessoa(v_x ->> 'pessoa', v_autor, p_hoje);
      if v_rp ->> 'status' <> 'ok' then
        return public._agenda_recusa(v_rp ->> 'texto', 'pessoa_' || (v_rp ->> 'status'),
          coalesce((select jsonb_agg(e ->> 'nome' order by o)
                      from jsonb_array_elements(coalesce(v_rp -> 'opcoes', '[]'::jsonb)) with ordinality t(e, o)), '[]'::jsonb));
      end if;
      v_equipe := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_equipe) with ordinality t(e, o)
                             where e ->> 'payee_id' <> v_rp ->> 'payee_id'), '[]'::jsonb)
                  || jsonb_build_array(jsonb_build_object('payee_id', v_rp ->> 'payee_id', 'nome', v_rp ->> 'nome_curto',
                                                          'eh_dono', coalesce((v_rp ->> 'eh_dono')::boolean, false),
                                                          'turnos', v_turnos));
    end loop;
    v_out := v_out || jsonb_build_object('equipe', v_equipe);
  end if;

  if d ? 'dono' then
    if d ->> 'dono' not in ('abre_e_fecha', 'sempre', 'nunca') then
      raise exception 'agenda_rascunho_planejar: dono "%" inválido (abre_e_fecha, sempre ou nunca)', d ->> 'dono' using errcode = '22023';
    end if;
    v_out := v_out || jsonb_build_object('dono', d ->> 'dono');
  end if;

  if d ? 'precisa_ate' then
    v_dt := public._agenda_data_conferida(d ->> 'precisa_ate', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if (v_dt ->> 'ate')::date < p_hoje then
      return public._agenda_recusa(format('"%s" já passou. Até quando o cliente precisa?', btrim(d ->> 'precisa_ate')), 'data_passada');
    end if;
    v_out := v_out || jsonb_build_object('precisa_ate', v_dt ->> 'ate');
  end if;

  -- O bem fora: "fora de 26 a 30/10", "fora até dia 3" (inclusive) ou "só fica livre dia 3" (livre nesse dia).
  if d ? 'bem_fora' then
    v_dt := public._agenda_data_conferida(d ->> 'bem_fora', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if (v_dt ->> 'ate')::date < p_hoje then
      return public._agenda_recusa(format('"%s" já passou. Até quando o bem fica fora?', btrim(d ->> 'bem_fora')), 'data_passada');
    end if;
    v_out := v_out || jsonb_build_object('bem', jsonb_build_object(
      'modo', 'fora', 'de', greatest((v_dt ->> 'de')::date, p_hoje), 'ate', (v_dt ->> 'ate')::date,
      'livre_em', (v_dt ->> 'ate')::date + 1));
  end if;
  if d ? 'bem_livre_em' then
    v_dt := public._agenda_data_conferida(d ->> 'bem_livre_em', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    v_out := v_out || jsonb_build_object('bem', case
      when (v_dt ->> 'de')::date <= p_hoje then jsonb_build_object('modo', 'livre')
      else jsonb_build_object('modo', 'livre_em', 'de', p_hoje, 'ate', (v_dt ->> 'de')::date - 1, 'livre_em', (v_dt ->> 'de')::date) end);
  end if;

  if d ? 'nao_antes_de' then
    v_dt := public._agenda_data_conferida(d ->> 'nao_antes_de', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    v_out := v_out || jsonb_build_object('nao_antes_de', v_dt ->> 'de',
      'nao_antes_motivo', coalesce(left(nullif(btrim(d ->> 'nao_antes_motivo'), ''), 120), 'você disse'));
  elsif d ? 'nao_antes_motivo' then
    return public._agenda_recusa('Não antes de que dia?', 'sem_data');
  end if;

  if d ? 'escopo_em_aberto' then
    v_out := v_out || jsonb_build_object('escopo_em_aberto', nullif(left(btrim(d ->> 'escopo_em_aberto'), 160), ''));
  end if;
  if d ? 'escopo_decidido' then
    v_out := v_out || jsonb_build_object('escopo_decidido', nullif(left(btrim(d ->> 'escopo_decidido'), 160), ''));
    if not d ? 'escopo_em_aberto' then
      -- O que o dono decidiu fecha a pergunta em aberto.
      v_out := v_out || jsonb_build_object('escopo_em_aberto', null);
    end if;
  end if;

  if d ? 'congelar_ate' then
    v_dt := public._agenda_data_conferida(d ->> 'congelar_ate', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if d ? 'revisar_em' then
      v_dt2 := public._agenda_data_conferida(d ->> 'revisar_em', p_trecho, p_hoje, 'futuro');
      if not (v_dt2 ->> 'ok')::boolean then return v_dt2; end if;
    else
      v_dt2 := v_dt;   -- sem data para rever: revê no dia em que a espera acaba
    end if;
    v_out := v_out || jsonb_build_object('congelada_ate', v_dt ->> 'ate', 'revisar_em', v_dt2 ->> 'de');
  elsif d ? 'revisar_em' then
    return public._agenda_recusa('Em espera até quando?', 'sem_data');
  end if;

  if d ? 'prioridade' then
    begin
      v_n := (d ->> 'prioridade')::numeric;
    exception when others then
      v_n := null;
    end;
    if v_n is null or v_n not in (1, 2, 3) then
      raise exception 'agenda_rascunho_planejar: prioridade "%" inválida (1, 2 ou 3)', d ->> 'prioridade' using errcode = '22023';
    end if;
    v_out := v_out || jsonb_build_object('prioridade', v_n::int);
  end if;

  if d ? 'sem_material' then
    v_out := v_out || jsonb_build_object('sem_material', (d ->> 'sem_material')::boolean);
  end if;

  -- FASE 2: quanto do serviço dá para adiantar no pátio sem o bem — o número tem de estar no que o dono disse e não
  -- passa dos dias do serviço (os ditos agora, ou os que já estavam).
  if d ? 'adiantavel_patio' then
    begin
      v_n := (d ->> 'adiantavel_patio')::numeric;
    exception when others then
      v_n := null;
    end;
    if v_n is null or v_n <= 0 or v_n > 60 or v_n * 2 <> trunc(v_n * 2) then
      return public._agenda_recusa('Quanto dá para adiantar no pátio? Diga em dias ou meio dia (por exemplo, "um dia").', 'patio_invalido');
    end if;
    if not public._agenda_trecho_tem_numero(p_trecho, v_n) then
      return public._agenda_recusa(format('Não achei "%s" no que você disse; me diga de novo quanto dá para adiantar no pátio.',
                                          public._agenda_dias(v_n)), 'fora_do_trecho');
    end if;
    v_dias_os := coalesce((v_out ->> 'dias')::numeric,
                          (select pl.dias from public.os_planejamento pl where pl.service_order_id = v_os));
    if v_dias_os is not null and v_n > v_dias_os then
      return public._agenda_recusa(format('O serviço todo é de %s: no pátio dá para adiantar no máximo isso. Quanto dá?',
                                          public._agenda_dias(v_dias_os)), 'patio_maior');
    end if;
    v_out := v_out || jsonb_build_object('adiantavel_patio', trim_scale(v_n));
  end if;

  -- O que o dono desfez: o campo vai como nulo (o *grava* grava vazio; a correção na mesma releitura também apaga).
  if 'espera' = any (v_limpar) then
    v_out := v_out || jsonb_build_object('congelada_ate', null, 'revisar_em', null);
  end if;
  if 'nao_antes' = any (v_limpar) then
    v_out := v_out || jsonb_build_object('nao_antes_de', null, 'nao_antes_motivo', null);
  end if;
  if 'prazo' = any (v_limpar) then
    v_out := v_out || jsonb_build_object('precisa_ate', null);
  end if;
  if 'escopo' = any (v_limpar) then
    v_out := v_out || jsonb_build_object('escopo_em_aberto', null);
  end if;
  if 'patio' = any (v_limpar) then   -- FASE 2
    v_out := v_out || jsonb_build_object('adiantavel_patio', null);
  end if;

  -- FASE 5: o que o dono disse ao cliente: a data conferida no trecho e entendida pelo banco (agenda_data_dita: "dia 3" é
  -- firme; "entre 4 e 8/11" e "semana que vem" são faixa), nunca no passado; o serviço como o cliente diz (3 a c_serv_max
  -- caracteres, sem valor, pagamento, número de OS nem link).
  if v_prom is not null then
    v_dtp := public._agenda_data_conferida(v_prom, p_trecho, p_hoje, 'futuro');
    if not (v_dtp ->> 'ok')::boolean then return v_dtp; end if;
    if (v_dtp ->> 'ate')::date < p_hoje then
      return public._agenda_recusa(format('"%s" já passou. Que dia você disse ao cliente?', v_prom), 'data_passada');
    end if;
    v_out := v_out || jsonb_build_object('prometido', jsonb_build_object(
      'tipo', case when v_dtp ->> 'de' = v_dtp ->> 'ate' then 'firme' else 'faixa' end,
      'de', v_dtp ->> 'de', 'ate', v_dtp ->> 'ate', 'dito', left(v_prom, 60)));
  end if;
  if v_serv is not null then
    if char_length(v_serv) < 3 or char_length(v_serv) > c_serv_max then
      return public._agenda_recusa(format('Diga em poucas palavras como o cliente chama o serviço (até %s letras), por exemplo "a instalação do compressor".',
                                          c_serv_max), 'servico_longo');
    end if;
    if public._agenda_cliente_texto_proibido(v_serv) is not null then
      return public._agenda_recusa('Como o cliente chama o serviço não leva valor, pagamento, número de OS nem link: diga só o serviço ("a troca das baterias").',
                                   'servico_proibido');
    end if;
    v_out := v_out || jsonb_build_object('servico_cliente', v_serv);
  end if;
  -- FASE 5: fim
  -- FASE 7b: (7b P2; R4.3(b), §6.6) a dupla dita: nao = 1 pessoa (sem a inferência); todos = o tempo todo; inicio/fim = nos
  -- dupla_meios primeiros ou últimos meios-dias (1 a 20, no trecho; "no primeiro dia" = 2 meios-dias, com "dia" no trecho). Com
  -- modo_dupla desligado, inicio/fim é recusado (a 7a não enxerga a dupla numa parte: o motor mandaria 1 pessoa num serviço de
  -- segurança e a releitura teria prometido a dupla); todos e nao valem em todo modo, como a palavra da 7a. Com menos técnicos
  -- na grade do que a dupla pede, a releitura avisa que a OS espera (a classe dupla de _agenda_classe_da_os).
  if v_7b_dupla is not null or v_7b_tem_meios then
    if v_7b_dupla is null or v_7b_dupla not in ('nao', 'todos', 'inicio', 'fim') then
      raise exception 'agenda_rascunho_planejar: dupla "%" inválida (nao, todos, inicio ou fim)', coalesce(v_7b_dupla, '')
        using errcode = '22023';
    end if;
    if v_7b_dupla in ('inicio', 'fim') then
      if (public._agenda_cfg()).modo_dupla = 'desligado' then
        return public._agenda_recusa(format('A dupla só numa parte do serviço ainda não está ligada. Diga *%s com dupla* (o tempo todo) ou ''vai com um só''.',
                                            v_ro ->> 'cliente_curto'), 'dupla_parte_desligada');
      end if;
      begin
        v_7b_meios := v_7b_meios_txt::int;
      exception when others then
        v_7b_meios := null;
      end;
      if v_7b_meios is null or v_7b_meios < 1 or v_7b_meios > 20 then
        return public._agenda_recusa('Em quantos meios-dias vai a dupla? (por exemplo, "dois no primeiro dia" = 2 meios-dias)', 'dupla_meios');
      end if;
      if not (public._agenda_trecho_tem_numero(p_trecho, v_7b_meios)
              or (public._agenda_normal(p_trecho) ~ '\mdias?\M'
                  and (v_7b_meios = 2 or (v_7b_meios % 2 = 0 and public._agenda_trecho_tem_numero(p_trecho, v_7b_meios / 2))))) then
        return public._agenda_recusa(format('Não achei "%s" no que você disse; me diga de novo em quantos meios-dias vai a dupla.', v_7b_meios),
                                     'fora_do_trecho');
      end if;
    elsif v_7b_tem_meios then
      raise exception 'agenda_rascunho_planejar: dupla_meios só com dupla inicio ou fim' using errcode = '22023';
    end if;
    if v_7b_dupla <> 'nao' then
      v_7b_tec := public._agenda_tecnicos_da_grade(p_hoje);
      if cardinality(v_7b_tec) < greatest((public._agenda_cfg()).equipe_sugerida, 2) then
        v_7b_aviso := format('Hoje %s: até você chamar alguém e me dizer os dias, eu não marco %s',
                             public._agenda_tecnicos_frase(v_7b_tec), v_ro ->> 'cliente_curto');
      end if;
    end if;
    v_out := v_out || jsonb_build_object('dupla', v_7b_dupla, 'dupla_meios', v_7b_meios, 'dupla_aviso', v_7b_aviso);
  end if;
  -- FASE 7b: fim
  -- FASE 7d: (7d P7; §5.7) o que o dono disse do local e do bem. O local e as pessoas pelo banco (ambíguo ou não achado = a pergunta, nada no rascunho); as datas conferidas no
  -- trecho e entendidas por agenda_data_dita (a chegada e a saída, o de da faixa); o resto, as listas fechadas. Vale em todo modo: ele é a fonte, e quem lê está atrás de _agenda_local_modo.
  if d ? 'local' then
    v_7d_rl := public.agenda_resolver_local(d ->> 'local', p_hoje);
    if v_7d_rl ->> 'status' = 'casa_cliente' then
      v_out := v_out || jsonb_build_object('local_id', null, 'local_nome', null, 'local_casa', true);
    elsif v_7d_rl ->> 'status' = 'ok' then
      v_out := v_out || jsonb_build_object('local_id', v_7d_rl ->> 'id', 'local_nome', v_7d_rl ->> 'nome', 'local_casa', false);
    else
      return public._agenda_recusa(v_7d_rl ->> 'texto', 'local_' || (v_7d_rl ->> 'status'),
        coalesce((select jsonb_agg(e ->> 'nome' order by o) from jsonb_array_elements(v_7d_rl -> 'opcoes') with ordinality t(e, o)), '[]'::jsonb));
    end if;
  end if;
  if d ? 'bem_onde' then
    if d ->> 'bem_onde' not in ('agua', 'seco', 'garagem_seca', 'patio', 'com_cliente') then
      raise exception 'agenda_rascunho_planejar: bem_onde "%" inválido (agua, seco, garagem_seca, patio ou com_cliente)', d ->> 'bem_onde' using errcode = '22023';
    end if;
    v_out := v_out || jsonb_build_object('bem_situacao', d ->> 'bem_onde');
  end if;
  if d ? 'bem_exige' then
    if d ->> 'bem_exige' not in ('agua', 'seco', 'tanto_faz') then
      raise exception 'agenda_rascunho_planejar: bem_exige "%" inválido (agua, seco ou tanto_faz)', d ->> 'bem_exige' using errcode = '22023';
    end if;
    v_out := v_out || jsonb_build_object('bem_exige', d ->> 'bem_exige');
  end if;
  if d ? 'descer_quem' then
    v_7d_txt := btrim(regexp_replace(d ->> 'descer_quem', '\s+', ' ', 'g'));
    if char_length(v_7d_txt) not between c_7d_quem_min and c_7d_quem_max then
      return public._agenda_recusa('Quem desce o barco? Diga em poucas palavras, por exemplo "a marina".', 'descer_quem');
    end if;
    v_out := v_out || jsonb_build_object('descer_quem', v_7d_txt);
  end if;
  -- "até dia 13" é uma faixa que começa hoje: o de seria um dia que ninguém disse
  if d ? 'chega_em' then
    v_dt := public._agenda_data_conferida(d ->> 'chega_em', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if (v_dt ->> 'de')::date = p_hoje and (v_dt ->> 'ate')::date > p_hoje then
      return public._agenda_recusa('Que dia chega? Diga um dia só (por exemplo, "dia 13").', 'data_faixa');
    end if;
    v_out := v_out || jsonb_build_object('entrada_em', v_dt ->> 'de');
  end if;
  if d ? 'sai_em' then
    v_dt := public._agenda_data_conferida(d ->> 'sai_em', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if (v_dt ->> 'de')::date = p_hoje and (v_dt ->> 'ate')::date > p_hoje then
      return public._agenda_recusa('Que dia sai? Diga um dia só (por exemplo, "dia 13").', 'data_faixa');
    end if;
    v_out := v_out || jsonb_build_object('retirada_em', v_dt ->> 'de');
  end if;
  if d ? 'viagem' then
    if d ->> 'viagem' not in ('regional', 'bate_volta', 'pernoite') then
      raise exception 'agenda_rascunho_planejar: viagem "%" inválida (regional, bate_volta ou pernoite)', d ->> 'viagem' using errcode = '22023';
    end if;
    v_out := v_out || jsonb_build_object('viagem', d ->> 'viagem');
  end if;
  if d ? 'autorizados' then
    if jsonb_typeof(d -> 'autorizados') <> 'array' or jsonb_array_length(d -> 'autorizados') = 0 then
      raise exception 'agenda_rascunho_planejar: autorizados tem de ser a lista de nomes' using errcode = '22023';
    end if;
    for v_x in select e from jsonb_array_elements(d -> 'autorizados') with ordinality t(e, o) order by o loop
      v_rp := public.agenda_resolver_pessoa(v_x #>> '{}', v_autor, p_hoje);
      if v_rp ->> 'status' <> 'ok' then
        return public._agenda_recusa(v_rp ->> 'texto', 'pessoa_' || (v_rp ->> 'status'),
          coalesce((select jsonb_agg(e ->> 'nome' order by o)
                      from jsonb_array_elements(coalesce(v_rp -> 'opcoes', '[]'::jsonb)) with ordinality t(e, o)), '[]'::jsonb));
      end if;
      -- a mesma pessoa dita 2 vezes fica uma, na posição da última (a régua de com_quem)
      v_7d_aut := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_7d_aut) with ordinality t(e, o)
                             where e ->> 'payee_id' <> v_rp ->> 'payee_id'), '[]'::jsonb)
                  || jsonb_build_array(jsonb_build_object('payee_id', v_rp ->> 'payee_id', 'nome', v_rp ->> 'nome_curto',
                                                          'eh_dono', coalesce((v_rp ->> 'eh_dono')::boolean, false)));
    end loop;
    v_out := v_out || jsonb_build_object('autorizados', v_7d_aut);
  end if;
  if 'local' = any (v_7d_limpar) then
    v_out := v_out || jsonb_build_object('local_id', null, 'local_nome', null, 'local_casa', false);
  end if;
  if 'entrada' = any (v_7d_limpar) then
    v_out := v_out || jsonb_build_object('entrada_em', null);
  end if;
  if 'retirada' = any (v_7d_limpar) then
    v_out := v_out || jsonb_build_object('retirada_em', null);
  end if;
  if 'viagem' = any (v_7d_limpar) then
    v_out := v_out || jsonb_build_object('viagem', null);
  end if;
  if 'autorizados' = any (v_7d_limpar) then
    v_out := v_out || jsonb_build_object('autorizados', '[]'::jsonb);
  end if;
  -- A chegada antes da saída, contra o que já está no rascunho aberto e na OS (o CHECK entrada_antes_saida recusaria no *grava*, sem dizer por quê)
  if v_out ?| array['entrada_em', 'retirada_em'] then
    select r.dados into v_7d_velho from public.agenda_rascunho r
     where r.autor = v_autor and r.chave = 'planejar:' || v_os::text and r.estado = 'aberto' and r.expira_em > now();
    v_7d_velho := coalesce(v_7d_velho, '{}'::jsonb);
    select case when v_out ? 'entrada_em' then (v_out ->> 'entrada_em')::date
                when v_7d_velho ? 'entrada_em' then (v_7d_velho ->> 'entrada_em')::date else x.entrada_em end,
           case when v_out ? 'retirada_em' then (v_out ->> 'retirada_em')::date
                when v_7d_velho ? 'retirada_em' then (v_7d_velho ->> 'retirada_em')::date else x.retirada_em end
      into v_7d_ent, v_7d_sai
      from (select 1) u left join public.os_planejamento x on x.service_order_id = v_os;
    if v_7d_ent >= v_7d_sai then
      return public._agenda_recusa(format('Não anotei: a saída (%s) tem de ser depois da chegada (%s). Me diga as datas certas.',
                                          public._dia_curto(v_7d_sai), public._dia_curto(v_7d_ent)), 'chega_depois_de_sai');
    end if;
  end if;
  -- FASE 7d: fim
  if v_out = '{}'::jsonb then
    return public._agenda_recusa('O que mudou nesse serviço? (quantos dias, quem vai, até quando o cliente precisa…)', 'nada');
  end if;

  select case when public._agenda_normal(coalesce(vs.asset_type, vs.name)) ~ 'motorhome|motor home|trailer'
              then 'o motorhome' else 'o barco' end
    into v_bem
    from public.service_orders so left join public.vessels vs on vs.id = so.vessel_id
   where so.id = v_os;

  v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'planejar', 'planejar:' || v_os::text, v_os,
                                          public._agenda_os_do_rascunho(v_ro) || jsonb_build_object('bem_nome', v_bem) || v_out,
                                          p_trecho, p_hoje);
  return jsonb_build_object('ok', true, 'item', v_txt,
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
end;
$function$;

comment on function public.agenda_rascunho_planejar(uuid, text, text, jsonb, text, date) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): o que o dono disse do serviço vira RASCUNHO (nada em os_planejamento). p_dados: dias, com_quem [{pessoa, turnos dia|manha|tarde}], dono (abre_e_fecha|sempre|nunca), precisa_ate, bem_fora, bem_livre_em, nao_antes_de + nao_antes_motivo, escopo_em_aberto, escopo_decidido, congelar_ate + revisar_em, prioridade 1–3, sem_material, aceitar_sugestao, adiantavel_patio (dias que dá para adiantar no pátio sem o bem; Fase 2), limpar (espera, nao_antes, prazo, escopo, patio). OS e pessoas resolvidas no banco (ambíguo/não achado = pergunta, nada no rascunho); dias, dias no pátio e datas têm de estar no trecho; datas por agenda_data_dita. Devolve {ok, item, releitura} ou {ok:false, pergunta, opcoes}. Fase 5 (P5): prometido (a data que o cliente OUVIU, como o dono disse: "dia 3" firme, "entre 4 e 8/11" ou "semana que vem" faixa; conferida no trecho, nunca no passado) e servico_cliente (como o cliente chama o serviço, 3 a 40 caracteres, sem valor, número de OS nem link). Fase 7b (P2; R4.3(b), §6.6): a chave dupla — nao (1 pessoa, sem a inferência), todos (o tempo todo), inicio ou fim (com dupla_meios 1 a 20 no trecho; "no primeiro dia" = 2 meios-dias, com "dia" no trecho); dupla_meios sem inicio/fim, ou dupla fora da lista, é erro de quem chamou. Com modo_dupla desligado, inicio/fim volta a frase "A dupla só numa parte do serviço ainda não está ligada. Diga *Lenine com dupla* (o tempo todo) ou ''vai com um só''." (todos e nao valem em todo modo). Com menos técnicos na grade do que a dupla pede, a releitura avisa: "Hoje só Alex está na equipe: até você chamar alguém e me dizer os dias, eu não marco Lenine." Fase 7d (P7; §5.7, R6.3-10): 25 campos em c_campos, com os 8 do local e do bem — local (agenda_resolver_local: fora de ok e casa_cliente, a pergunta dela), bem_onde (agua, seco, garagem_seca, patio, com_cliente), bem_exige (agua, seco, tanto_faz), descer_quem, chega_em e sai_em (como as outras datas: no trecho e por agenda_data_dita, sentido futuro, o de da faixa; "até dia 13" pede um dia só; a saída tem de ser depois da chegada, contando o rascunho aberto e a OS), viagem (regional, bate_volta, pernoite) e autorizados (a lista de nomes, pelo resolvedor de pessoa de com_quem; "eu" = o dono). limpar ganha local, entrada, retirada, viagem e autorizados. Nada grava: só o *grava*. Vale em todo modo: o dono é a fonte, e quem lê está atrás de _agenda_local_modo.';

-- _agenda_aplicar_planejar (de 20261101100100_agenda_fase7b_disponibilidade.sql, a da R6.1)
create or replace function public._agenda_aplicar_planejar(p_autor uuid, p_os uuid, p_dados jsonb, p_trecho text, p_hoje date)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  d           jsonb := coalesce(p_dados, '{}'::jsonb);
  v_old       public.os_planejamento%rowtype;
  v_new       public.os_planejamento%rowtype;
  v_eq_antes  jsonb;
  v_eq_depois jsonb;
  v_antes     jsonb := '{}'::jsonb;
  v_depois    jsonb := '{}'::jsonb;
  v_k         text;
  -- FASE 5: o prometido de antes e o gravado
  v_prom_antes jsonb;
  v_prom      jsonb;
  -- FASE 5: fim
  -- FASE 7d: (7d P7; §5.7) o que o dono disse do local e do bem: as chaves, a hora do *grava*, os autorizados, o antes e o depois da ação e as perguntas que ele fechou
  c_7d_chaves constant text[] := array['local_id', 'bem_situacao', 'bem_exige', 'descer_quem', 'entrada_em', 'retirada_em', 'viagem', 'autorizados'];
  v_7d_tem    boolean := coalesce(p_dados, '{}'::jsonb) ?| array['local_id', 'bem_situacao', 'bem_exige', 'descer_quem', 'entrada_em', 'retirada_em', 'viagem', 'autorizados'];
  v_7d_agora  timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  v_7d_ids    uuid[];
  v_7d_vig_a  uuid[];
  v_7d_vig_d  uuid[];
  v_7d_linhas jsonb;
  v_7d_lin_d  jsonb;
  v_7d_local  uuid;
  v_7d_antes  jsonb := '{}'::jsonb;
  v_7d_dep    jsonb := '{}'::jsonb;
  v_7d_q      public.agenda_perguntas%rowtype;
  v_7d_item   jsonb;
  v_7d_abert  uuid[];
  v_7d_fech   uuid[] := '{}';
  v_7d_trecho text;
  -- FASE 7d: fim
begin
  if not exists (select 1 from public.service_orders where id = p_os) then
    raise exception 'o serviço % não existe mais', coalesce(d ->> 'numero', p_os::text) using errcode = 'P0001';
  end if;
  insert into public.os_planejamento (service_order_id) values (p_os) on conflict (service_order_id) do nothing;
  -- FASE 5: o que o dono disse ao cliente vira o prometido (fonte dono; a 1ª promessa fica em prometido_original_ate; o
  -- histórico ganha a linha própria, pelo _agenda_cliente_gravar_prometido). Gravado antes de ler a linha: o diff abaixo é
  -- só do resto. Só o prometido na linha = nada mais a gravar.
  if jsonb_typeof(d -> 'prometido') = 'object' then
    select jsonb_build_object('tipo', pl.prometido_tipo, 'de', pl.prometido_de, 'ate', pl.prometido_ate, 'fonte', pl.prometido_fonte)
      into v_prom_antes from public.os_planejamento pl where pl.service_order_id = p_os;
    v_prom := public._agenda_cliente_gravar_prometido(p_os, d #>> '{prometido,tipo}', (d #>> '{prometido,de}')::date,
                (d #>> '{prometido,ate}')::date, 'dono', null,
                coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now()), p_trecho);
    -- FASE 7b: (7b P2) com a dupla na mesma linha, o resto da linha ainda grava (não volta só com o prometido)
    if not (d ? 'dupla') then
    -- FASE 7b: fim
    -- FASE 7d: (7d P7) com o local ou o bem na mesma linha, o resto da linha ainda grava: a volta de baixo só serve ao prometido sozinho
    if not (d ?| c_7d_chaves) then
    -- FASE 7d: fim
    if not (d ?| array['dias', 'equipe', 'dono', 'precisa_ate', 'bem', 'nao_antes_de', 'escopo_em_aberto', 'escopo_decidido',
                       'congelada_ate', 'prioridade', 'sem_material', 'adiantavel_patio', 'servico_cliente']) then
      return jsonb_build_object('antes', jsonb_build_object('prometido', v_prom_antes), 'depois', jsonb_build_object('prometido', v_prom));
    end if;
    -- FASE 7d: (7d P7) fecha o "com o local ou o bem na mesma linha"
    end if;
    -- FASE 7d: fim
    -- FASE 7b: (7b P2) fecha o "com a dupla na mesma linha"
    end if;
    -- FASE 7b: fim
  end if;
  -- FASE 5: fim
  select * into v_old from public.os_planejamento where service_order_id = p_os for update;
  v_new := v_old;
  -- FASE 7b: (7b P2) a dupla dita (o histórico abaixo guarda o antes e o depois): nao = 1 pessoa (sem a inferência), todos, ou
  -- inicio/fim com os meios-dias
  if d ? 'dupla' then
    v_new.dupla_dita := d ->> 'dupla';
    v_new.dupla_meios := case when d ->> 'dupla' in ('inicio', 'fim') then (d ->> 'dupla_meios')::smallint end;
    v_new.dupla_motivo := left('você disse: ' || public._agenda_rascunho_frase('planejar',
                                 jsonb_build_object('dupla', d ->> 'dupla', 'dupla_meios', d -> 'dupla_meios')), 80);
    v_new.dupla_em := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  end if;
  -- FASE 7b: fim

  if d ? 'dias' then
    v_new.dias := (d ->> 'dias')::numeric;
    v_new.estimativa_fonte := d ->> 'estimativa_fonte';
    v_new.estimativa_em := now();
  end if;
  if d ? 'dono' then v_new.dono_presenca := d ->> 'dono'; end if;
  if d ? 'precisa_ate' then v_new.precisa_ate := (d ->> 'precisa_ate')::date; end if;
  if d ? 'bem' then
    v_new.bem_indisponivel := case when d #>> '{bem,modo}' = 'livre' then '{}'::datemultirange
                                   else datemultirange(daterange((d #>> '{bem,de}')::date, (d #>> '{bem,livre_em}')::date, '[)')) end;
  end if;
  if d ? 'nao_antes_de' then
    v_new.nao_antes_de := (d ->> 'nao_antes_de')::date;
    v_new.nao_antes_motivo := d ->> 'nao_antes_motivo';
  end if;
  if d ? 'escopo_em_aberto' then v_new.escopo_em_aberto := d ->> 'escopo_em_aberto'; end if;
  if d ? 'escopo_decidido' then v_new.escopo_decidido := d ->> 'escopo_decidido'; end if;
  if d ? 'congelada_ate' then
    v_new.congelada_ate := (d ->> 'congelada_ate')::date;
    v_new.revisar_em := (d ->> 'revisar_em')::date;
  end if;
  if d ? 'prioridade' then v_new.prioridade_manual := (d ->> 'prioridade')::smallint; end if;
  if d ? 'sem_material' then
    v_new.material_conferido_em := case when (d ->> 'sem_material')::boolean then now() end;
  end if;
  -- FASE 2: o que dá para adiantar no pátio (null = o dono tirou).
  if d ? 'adiantavel_patio' then
    v_new.adiantavel_patio_dias := (d ->> 'adiantavel_patio')::numeric;
  end if;
  -- FASE 5: como o serviço é dito ao cliente
  if d ? 'servico_cliente' then
    v_new.servico_cliente := d ->> 'servico_cliente';
  end if;
  -- FASE 5: fim

  -- FASE 7d: (7d P7; §5.7) o que o dono disse do local e do bem, fonte dono. Vai para a linha aqui, antes de ler o local resolvido dos autorizados; o histórico abaixo guarda o antes
  -- e o depois (o update de antes não tem estas colunas). A chegada e a saída têm uma fonte só: entrada_coerente.
  if v_7d_tem then
    if d ? 'local_id' then
      v_new.local_id := (d ->> 'local_id')::uuid;
      v_new.local_fonte := case when d ->> 'local_id' is not null then 'dono' end;
      v_new.local_em := case when d ->> 'local_id' is not null then v_7d_agora end;
    end if;
    if d ? 'bem_situacao' then
      v_new.bem_situacao := d ->> 'bem_situacao';
      v_new.bem_situacao_fonte := 'dono';
      v_new.bem_situacao_em := v_7d_agora;
    end if;
    if d ? 'bem_exige' then v_new.bem_exige := d ->> 'bem_exige'; end if;
    if d ? 'descer_quem' then v_new.descer_quem := d ->> 'descer_quem'; end if;
    if d ? 'viagem' then v_new.viagem := d ->> 'viagem'; end if;
    if d ?| array['entrada_em', 'retirada_em'] then
      if d ? 'entrada_em' then v_new.entrada_em := (d ->> 'entrada_em')::date; end if;
      if d ? 'retirada_em' then v_new.retirada_em := (d ->> 'retirada_em')::date; end if;
      v_new.entrada_fonte := case when coalesce(v_new.entrada_em, v_new.retirada_em) is not null then 'dono' end;
      -- o que mudou entre a releitura e o *grava*: a frase dele, não "o banco recusou"
      if v_new.entrada_em >= v_new.retirada_em then
        raise exception 'a saída (%) tem de ser depois da chegada (%)', public._dia_curto(v_new.retirada_em), public._dia_curto(v_new.entrada_em) using errcode = 'P0001';
      end if;
    end if;
    update public.os_planejamento
       set local_id = v_new.local_id, local_fonte = v_new.local_fonte, local_em = v_new.local_em,
           bem_situacao = v_new.bem_situacao, bem_situacao_fonte = v_new.bem_situacao_fonte, bem_situacao_em = v_new.bem_situacao_em,
           bem_exige = v_new.bem_exige, descer_quem = v_new.descer_quem, viagem = v_new.viagem,
           entrada_em = v_new.entrada_em, retirada_em = v_new.retirada_em, entrada_fonte = v_new.entrada_fonte
     where service_order_id = p_os;
    -- A lista dita substitui a anterior, como a equipe: a linha nunca se apaga (quem saiu ganha revogado_em). O antes vai inteiro para a ação: o *desfaz* volta linha por linha.
    if d ? 'autorizados' then
      select coalesce(jsonb_agg(to_jsonb(x) order by x.payee_id), '[]'::jsonb) into v_7d_linhas
        from public.os_autorizados x where x.service_order_id = p_os;
      v_7d_vig_a := array(select x.payee_id from public.os_autorizados x where x.service_order_id = p_os and x.revogado_em is null order by 1);
      v_7d_ids := array(select distinct (e ->> 'payee_id')::uuid from jsonb_array_elements(d -> 'autorizados') e order by 1);
      update public.os_autorizados x set revogado_em = v_7d_agora
       where x.service_order_id = p_os and x.revogado_em is null and not (x.payee_id = any (v_7d_ids));
      if cardinality(v_7d_ids) > 0 then
        v_7d_local := (public._agenda_local_resolvido(p_os, p_hoje) ->> 'local_id')::uuid;
        insert into public.os_autorizados (service_order_id, payee_id, local_id, valido_ate, fonte, trecho, criado_em, criado_por)
        select p_os, u.id, v_7d_local, null, 'dono', left(p_trecho, 300), v_7d_agora, p_autor from unnest(v_7d_ids) u(id)
        on conflict (service_order_id, payee_id) do update
          set local_id = excluded.local_id, valido_ate = null, fonte = excluded.fonte, trecho = excluded.trecho, revogado_em = null,
              criado_em = excluded.criado_em, criado_por = excluded.criado_por
          -- dizer de novo o que já está não mexe na linha
          where (os_autorizados.local_id, os_autorizados.valido_ate, os_autorizados.fonte, os_autorizados.revogado_em)
                is distinct from (excluded.local_id, null::date, excluded.fonte, null::timestamptz);
      end if;
      v_7d_vig_d := v_7d_ids;
      select coalesce(jsonb_agg(to_jsonb(x) order by x.payee_id), '[]'::jsonb) into v_7d_lin_d
        from public.os_autorizados x where x.service_order_id = p_os;
      -- a mesma lista pode ter mudado por dentro (o local, a validade, a fonte): a comparação é das linhas, não dos nomes
      if v_7d_linhas is distinct from v_7d_lin_d then
        v_antes := v_antes || jsonb_build_object('autorizados', to_jsonb(v_7d_vig_a));
        v_depois := v_depois || jsonb_build_object('autorizados', to_jsonb(v_7d_vig_d));
      end if;
    end if;
  end if;
  -- FASE 7d: fim
  select coalesce(jsonb_agg(jsonb_build_object('payee_id', e.payee_id, 'turnos', e.turnos) order by e.payee_id), '[]'::jsonb)
    into v_eq_antes
    from public.os_planejamento_equipe e where e.service_order_id = p_os;
  if d ? 'equipe' then
    delete from public.os_planejamento_equipe where service_order_id = p_os;
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos)
    select p_os, (e ->> 'payee_id')::uuid, e ->> 'turnos' from jsonb_array_elements(d -> 'equipe') e;
    select coalesce(jsonb_agg(jsonb_build_object('payee_id', e.payee_id, 'turnos', e.turnos) order by e.payee_id), '[]'::jsonb)
      into v_eq_depois
      from public.os_planejamento_equipe e where e.service_order_id = p_os;
  else
    v_eq_depois := v_eq_antes;
  end if;

  -- O histórico guarda só o que mudou: {campo: antes} e {campo: depois}.
  for v_k in select key from jsonb_each(to_jsonb(v_new) - array['historico', 'atualizado_em', 'atualizado_por', 'trecho', 'estimativa_em'])
  loop
    if to_jsonb(v_old) -> v_k is distinct from to_jsonb(v_new) -> v_k then
      v_antes := v_antes || jsonb_build_object(v_k, to_jsonb(v_old) -> v_k);
      v_depois := v_depois || jsonb_build_object(v_k, to_jsonb(v_new) -> v_k);
    end if;
  end loop;
  if v_eq_antes is distinct from v_eq_depois then
    v_antes := v_antes || jsonb_build_object('equipe', v_eq_antes);
    v_depois := v_depois || jsonb_build_object('equipe', v_eq_depois);
  end if;

  update public.os_planejamento
     set dias = v_new.dias, estimativa_fonte = v_new.estimativa_fonte, estimativa_em = v_new.estimativa_em,
         dono_presenca = v_new.dono_presenca, precisa_ate = v_new.precisa_ate, bem_indisponivel = v_new.bem_indisponivel,
         nao_antes_de = v_new.nao_antes_de, nao_antes_motivo = v_new.nao_antes_motivo,
         escopo_em_aberto = v_new.escopo_em_aberto, escopo_decidido = v_new.escopo_decidido,
         congelada_ate = v_new.congelada_ate, revisar_em = v_new.revisar_em, prioridade_manual = v_new.prioridade_manual,
         material_conferido_em = v_new.material_conferido_em,
         adiantavel_patio_dias = v_new.adiantavel_patio_dias,   -- FASE 2
         -- FASE 5: como o serviço é dito ao cliente
         servico_cliente = v_new.servico_cliente,
         -- FASE 5: fim
         trecho = public._agenda_corta(p_trecho, 500),
         historico = public._os_material_historico(v_old.historico, jsonb_build_object(
           'em', p_hoje, 'autor', p_autor, 'trecho', public._agenda_corta(p_trecho, 500), 'antes', v_antes, 'depois', v_depois)),
         atualizado_em = now(), atualizado_por = p_autor
   where service_order_id = p_os;
  -- FASE 7b: (7b P2) a dupla dita vai para a linha (o update acima é o de antes, sem as colunas da dupla)
  if d ? 'dupla' then
    update public.os_planejamento
       set dupla_dita = v_new.dupla_dita, dupla_meios = v_new.dupla_meios, dupla_motivo = v_new.dupla_motivo,
           dupla_em = v_new.dupla_em
     where service_order_id = p_os;
  end if;
  -- FASE 7b: fim
  -- FASE 7d: (7d P7) o dono vence e o *desfaz* volta tudo.
  -- (a) A pergunta local aberta da OS: o sim dela gravaria depois, por cima do que o dono disse, o que o cliente falou. Fecha quando ele disse o que ela gravaria (a sem leitura, que
  -- pede "me diga onde é", com o local, o bem ou a chegada). "Tirei o local" não diz onde é: ela fica.
  -- (b) A combinar e a acesso: o sim é a palavra do próprio dono, com a data escrita, mas o que ele disse pode já ter resolvido; o tique levaria até 15 minutos. O mesmo resolvedor, agora.
  -- (c) A ação local: só o que mudou de fato, mais a pergunta que fechou. Sem as chaves novas, nada disto roda: os_planejar_pela_tela e as linhas de antes não têm ação.
  if v_7d_tem then
    if coalesce((d ->> 'local_casa')::boolean, false) and public._agenda_normal(p_trecho) !~ '\mcasa\M' then
      update public.os_planejamento set trecho = public._agenda_corta('na casa do cliente: ' || p_trecho, 500) where service_order_id = p_os;
    end if;
    select q.* into v_7d_q from public.agenda_perguntas q where q.chave = 'local:' || p_os and q.estado = 'aberta' limit 1;
    if found then
      v_7d_item := v_7d_q.opcoes -> 0 #> '{efeito,item}';
      if d ->> 'local_id' is not null or coalesce((d ->> 'local_casa')::boolean, false)
         or (d ? 'bem_situacao' and (v_7d_item is null or v_7d_item ->> 'situacao' is not null))
         or (d ? 'descer_quem' and v_7d_item ->> 'descer_quem' is not null)
         or (d ->> 'entrada_em' is not null and v_7d_item is null) then
        update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'você disse onde é' where id = v_7d_q.id;
        v_7d_fech := v_7d_fech || v_7d_q.id;
      end if;
    end if;
    v_7d_abert := array(select q.id from public.agenda_perguntas q where q.service_order_id = p_os and q.tipo in ('combinar', 'acesso') and q.estado = 'aberta');
    if cardinality(v_7d_abert) > 0 then
      perform public._agenda_local_resolver(p_hoje, v_7d_agora);
      v_7d_fech := v_7d_fech || array(select q.id from public.agenda_perguntas q where q.id = any (v_7d_abert) and q.estado <> 'aberta');
    end if;

    if (v_old.local_id, v_old.local_fonte) is distinct from (v_new.local_id, v_new.local_fonte) then
      v_7d_antes := v_7d_antes || jsonb_build_object('local_id', v_old.local_id, 'local_fonte', v_old.local_fonte, 'local_em', v_old.local_em);
      v_7d_dep := v_7d_dep || jsonb_build_object('local_id', v_new.local_id, 'local_fonte', v_new.local_fonte, 'local_em', v_new.local_em);
    end if;
    if (v_old.bem_situacao, v_old.bem_situacao_fonte) is distinct from (v_new.bem_situacao, v_new.bem_situacao_fonte) then
      v_7d_antes := v_7d_antes || jsonb_build_object('bem_situacao', v_old.bem_situacao, 'bem_situacao_fonte', v_old.bem_situacao_fonte, 'bem_situacao_em', v_old.bem_situacao_em);
      v_7d_dep := v_7d_dep || jsonb_build_object('bem_situacao', v_new.bem_situacao, 'bem_situacao_fonte', v_new.bem_situacao_fonte, 'bem_situacao_em', v_new.bem_situacao_em);
    end if;
    if v_old.bem_exige is distinct from v_new.bem_exige then
      v_7d_antes := v_7d_antes || jsonb_build_object('bem_exige', v_old.bem_exige);
      v_7d_dep := v_7d_dep || jsonb_build_object('bem_exige', v_new.bem_exige);
    end if;
    if v_old.descer_quem is distinct from v_new.descer_quem then
      v_7d_antes := v_7d_antes || jsonb_build_object('descer_quem', v_old.descer_quem);
      v_7d_dep := v_7d_dep || jsonb_build_object('descer_quem', v_new.descer_quem);
    end if;
    if v_old.viagem is distinct from v_new.viagem then
      v_7d_antes := v_7d_antes || jsonb_build_object('viagem', v_old.viagem);
      v_7d_dep := v_7d_dep || jsonb_build_object('viagem', v_new.viagem);
    end if;
    if (v_old.entrada_em, v_old.retirada_em, v_old.entrada_fonte) is distinct from (v_new.entrada_em, v_new.retirada_em, v_new.entrada_fonte) then
      v_7d_antes := v_7d_antes || jsonb_build_object('entrada_em', v_old.entrada_em, 'retirada_em', v_old.retirada_em, 'entrada_fonte', v_old.entrada_fonte);
      v_7d_dep := v_7d_dep || jsonb_build_object('entrada_em', v_new.entrada_em, 'retirada_em', v_new.retirada_em, 'entrada_fonte', v_new.entrada_fonte);
    end if;
    if v_7d_linhas is distinct from v_7d_lin_d then
      v_7d_antes := v_7d_antes || jsonb_build_object('autorizados_linhas', v_7d_linhas);
      v_7d_dep := v_7d_dep || jsonb_build_object('autorizados', to_jsonb(v_7d_ids), 'autorizados_vigentes', to_jsonb(v_7d_vig_d));
    end if;
    if v_7d_antes <> '{}'::jsonb or cardinality(v_7d_fech) > 0 then
      select x.trecho into v_7d_trecho from public.os_planejamento x where x.service_order_id = p_os;
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, critica, antes, depois, texto, motivo, autor, desfazivel_ate)
      values (clock_timestamp(), p_hoje, true, 'dono', 'local', p_os, array[p_os], false, v_7d_antes || jsonb_build_object('trecho', v_old.trecho),
              v_7d_dep || jsonb_build_object('trecho', v_7d_trecho, 'efeito', 'planejar', 'perguntas_fechadas', to_jsonb(v_7d_fech),
                                             'item', jsonb_build_object('cliente', d ->> 'curto')),
              public._agenda_corta(concat_ws(': ', d ->> 'curto', array_to_string(public._agenda_planejar_linhas(d), ' ')), 400), 'você disse', p_autor,
              v_7d_agora + (public._agenda_cfg()).desfazer_validade);
    end if;
  end if;
  -- FASE 7d: fim
  return jsonb_build_object('antes', v_antes, 'depois', v_depois);
end;
$function$;

comment on function public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): grava em os_planejamento (e os_planejamento_equipe) uma linha de rascunho planejar — só os campos ditos (Fase 2: adiantavel_patio → adiantavel_patio_dias); a equipe dita substitui a anterior. Histórico {em, autor, trecho, antes, depois} com só o que mudou (os 20 mais novos). Só pelo agenda_rascunho_gravar; só service_role. Fase 5 (P5): prometido → os_planejamento.prometido_* pelo _agenda_cliente_gravar_prometido (fonte dono; o original só na 1ª vez; linha própria no histórico); servico_cliente → os_planejamento.servico_cliente. Fase 7b (P2): a dupla dita → os_planejamento.dupla_dita (nao | todos | inicio | fim), dupla_meios (só inicio/fim), dupla_motivo ("você disse: vai em dupla nos 2 primeiros meios-dias") e dupla_em (a hora do *grava*), no histórico com o antes e o depois; com o prometido na mesma linha, o resto da linha ainda grava. Fase 7d (P7; §5.7): o que o dono disse do local e do bem → local_id, local_fonte = dono e local_em; bem_situacao e a fonte; bem_exige; descer_quem; entrada_em, retirada_em e entrada_fonte = dono; viagem; e os_autorizados (fonte dono, local_id = o local resolvido, valido_ate nulo; a lista dita substitui a anterior; quem saiu ganha revogado_em). Tudo no histórico. A pergunta local aberta fecha (resolvida, "você disse onde é") quando ele disse o que ela gravaria: o dono vence. A combinar e a acesso da OS passam pelo _agenda_local_resolver na hora. Uma ação local (origem dono, efeito planejar), com o que mudou e as perguntas que fechou: o *desfaz* (_agenda_desfazer_local) volta só isso; dias, equipe e os outros campos da mesma linha não têm *desfaz*, como sempre. Sem essas chaves, a de antes, byte a byte, e nenhuma ação.';

-- _agenda_local_restaurar (de 20261107100500_agenda_fase7d_cliente.sql). Fora da R6.1: é quem volta as colunas no *desfaz*
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
     -- FASE 7d: (7d P7, §5.7) o que o os_planejar grava. Os autorizados: a lista de agora tem de ser a que a ação deixou
     or (a.antes ? 'bem_exige' and pl.bem_exige is distinct from a.depois ->> 'bem_exige')
     or (a.antes ? 'retirada_em' and pl.retirada_em is distinct from (a.depois ->> 'retirada_em')::date)
     or (a.antes ? 'viagem' and pl.viagem is distinct from a.depois ->> 'viagem')
     or (a.depois ? 'autorizados_vigentes'
         and to_jsonb(array(select x.payee_id from public.os_autorizados x where x.service_order_id = a.service_order_id and x.revogado_em is null order by 1))
             is distinct from a.depois -> 'autorizados_vigentes')
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
         -- FASE 7d: (7d P7, §5.7) o que o os_planejar grava. O trecho só volta se ainda é o da ação: outra fala do dono depois não some
         bem_exige = case when a.antes ? 'bem_exige' then a.antes ->> 'bem_exige' else p.bem_exige end,
         retirada_em = case when a.antes ? 'retirada_em' then (a.antes ->> 'retirada_em')::date else p.retirada_em end,
         viagem = case when a.antes ? 'viagem' then a.antes ->> 'viagem' else p.viagem end,
         trecho = case when a.antes ? 'trecho' and p.trecho is not distinct from a.depois ->> 'trecho' then a.antes ->> 'trecho' else p.trecho end,
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
  'Agenda de Produção (Fase 7d, P5; §5.5): volta as colunas de os_planejamento que a ação local gravou (o antes: acesso_ok_em, reserva_marina_ok_em, descida_ok_em, entrada_em e entrada_fonte, nao_antes_de e nao_antes_motivo), só se o que está gravado ainda é o depois dela; senão false, nada muda. Guarda no histórico. Invoker, sem grant: chamam _agenda_desfazer_local e agenda_desfazer, definer. FASE 7d (P6, §5.6): volta também local_id, local_fonte e local_em; bem_situacao, bem_situacao_fonte e bem_situacao_em; descer_quem. FASE 7d (P7, §5.7): volta também bem_exige, retirada_em e viagem, e o trecho, se ainda é o da ação; recusa se a lista de autorizados não é a que a ação deixou.';

-- _agenda_desfazer_local (de 20261107100500_agenda_fase7d_cliente.sql). Fora da R6.1: é quem volta os autorizados e a pergunta
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

  -- FASE 7d: (7d P7, §5.7) o que o *grava* do os_planejar fez fora das colunas: as linhas de os_autorizados voltam como estavam (quem saiu da lista volta; quem já estava fica) e a
  -- pergunta que ele fechou volta a esperar, se ainda vale: fechada não muda, então é outra linha, com o mesmo texto e as mesmas opções
  update public.os_autorizados x
     set local_id = (e.l ->> 'local_id')::uuid, valido_ate = (e.l ->> 'valido_ate')::date, fonte = e.l ->> 'fonte', trecho = e.l ->> 'trecho',
         revogado_em = (e.l ->> 'revogado_em')::timestamptz, criado_em = (e.l ->> 'criado_em')::timestamptz, criado_por = (e.l ->> 'criado_por')::uuid
    from jsonb_array_elements(coalesce(a.antes -> 'autorizados_linhas', '[]'::jsonb)) e(l)
   where x.service_order_id = v_os and x.payee_id = (e.l ->> 'payee_id')::uuid;
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, dia, perda_em, texto, opcoes, recomendacao, versao_base, modo, criada_em, expira_em)
  select q.tipo, q.chave, q.service_order_id, q.os_ids, q.dia, q.perda_em, q.texto, q.opcoes, q.recomendacao, q.versao_base, q.modo, p_agora, q.expira_em
    from public.agenda_perguntas q
   where q.id in (select y::uuid from jsonb_array_elements_text(coalesce(a.depois -> 'perguntas_fechadas', '[]'::jsonb)) y)
     and (q.expira_em is null or q.expira_em > p_agora)
  on conflict (chave, modo) where estado = 'aberta' do nothing;
  -- FASE 7d: fim
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
  -- FASE 7d: (7d P7, §6.3) só o local suposto ou só quem entrou na lista: os textos da §6.3; o resto, a frase de uma linha
  elsif v_ef = 'planejar' then
    v_txt := case when (a.antes - 'trecho' - 'local_id' - 'local_fonte' - 'local_em') = '{}'::jsonb and a.antes ? 'local_id' and a.antes ->> 'local_id' is null
                    then format('Desfeito: o local do serviço de %s voltou a ser o que eu supunha.', v_nome)
                  when (a.antes - 'trecho' - 'autorizados_linhas') = '{}'::jsonb and jsonb_array_length(coalesce(a.depois -> 'autorizados', '[]'::jsonb)) > 0
                    then public._agenda_combinar_texto(jsonb_build_object('tipo', 'acesso', 'nominal', true, 'nomes', (
                           select jsonb_agg(public._agenda_nome_curto(py.name) order by py.name)
                             from public.payees py
                            where py.id in (select y::uuid from jsonb_array_elements_text(a.depois -> 'autorizados') y))), 'desfeito', p_hoje)
                  else format('Desfeito: o serviço de %s voltou como estava.', v_nome) end;
  -- FASE 7d: fim
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
  'Agenda de Produção (Fase 7d, P5; §5.5; R6.7c-1): o *desfaz* da ação local — dentro do desfazivel_ate e só se nada mudou depois: as colunas voltam (_agenda_local_restaurar), as linhas de os_autorizados que ela criou ganham revogado_em e o replano do "Segure o dia" volta, cada ação pelo agenda_desfazer de sempre (com agenda.desfazer_local ligada, para não restaurar duas vezes). Só agenda_desfazer chama (o plano já travado). FASE 7d (P6, §6.3): a ação do que o cliente disse (efeito local) diz "Desfeito: o local do serviço de Nelson voltou a ser o que eu supunha.". FASE 7d (P7, §5.7, §6.3): a ação do os_planejar (efeito planejar) volta também as linhas de os_autorizados como estavam (autorizados_linhas) e devolve a pergunta que fechou (perguntas_fechadas), numa linha nova, se ainda não venceu.';

-- ── 4. As portas ────────────────────────────────────────────────────────────────────────────────────
-- agenda_resolver_local é invoker e a tela e o assistente a chamam: a palavra de apoio segue com ela. As linhas são internas, como a frase. O revoke de anon é explícito: o
-- privilégio padrão do esquema dá execute a quem não for tirado.
revoke all on function public.agenda_resolver_local(text, date), public._agenda_local_palavras(text) from public, anon;
grant execute on function public.agenda_resolver_local(text, date), public._agenda_local_palavras(text) to authenticated, service_role;
revoke all on function public._agenda_planejar_linhas(jsonb) from public, anon, authenticated;
grant execute on function public._agenda_planejar_linhas(jsonb) to service_role;
