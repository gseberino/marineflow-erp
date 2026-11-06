-- Agenda de Produção, Fase 7, etapa 7d ("onde, quando e com o bem em que estado"), pacote P5: combinar com data.
-- Spec: scratchpad agenda-pesquisa/spec-fase7d.md (§3.1 itens 7 e 11; §5.5; §6.3; §8.3 agenda_fase7d_combinar.sql; bloco R, R1; R6.1; R6.3-3;
-- R6.5; R6.7b; R6.7c; R6.8-4; R6.10; R6.12, que corrigem o corpo); nomes: fase7-registro.md (7d P5); respostas do dono: fase7-padroes.md
-- (AG7-14, AG7-18). Depende das Fases 1 a 6, do lote de 30/10, da 7a, da 7b, da 7c e de 20261107100000 a 20261107100300.
--
-- ═══ DDL — OK NOMEADO ═══ (5 funções recriadas e 10 novas; nenhuma tabela, nenhuma coluna, nenhum dado)
-- NÃO APLICADA. Existe para revisão e espera o OK do dono. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7d/p5/montar-migration.mjs:
-- cada recriada é o corpo da definição MAIS NOVA (o montador para se outra migration a definir depois da origem), e as mudanças estão só em
-- blocos "-- FASE 7d: … -- FASE 7d: fim" INSERIDOS (dentro de um bloco "-- FASE 7c:", com as marcas "-- (7d …" … "-- (7d: fim)"); tirados os blocos, o corpo é o da
-- origem, byte a byte (o montador e o C9 de
-- supabase/tests/agenda_fase7d_combinar.sql conferem). A exceção é agenda_decisoes_abertas, de uma consulta só: a linha do where mudou (ver abaixo).
--
-- POR QUE: o dono disse que o acesso "deve ser sempre tratado antes do técnico chegar ao local" (AG7-14). Hoje ninguém cobra: nem o acesso, nem a
-- vaga na garagem seca, nem a descida para o teste na água, nem a entrada do motorhome no pátio. Agora cada uma dessas dependências tem data, e
-- a data vira pergunta; a véspera sem acesso vira decisão urgente.
--
-- O QUE MUDA:
--   1. _agenda_combinar_da_os: o que falta combinar de cada OS, calculado (nada novo é guardado além do fato combinado).
--   2. _agenda_local_combinar: o item vencido abre a pergunta combinar (ligado) ou a ação "Em teste" (sombra), uma vez por chave. Na véspera sem
--      acesso, a combinar fecha ("virou decisão") e nasce a crítica acesso: o dono nunca recebe as duas.
--   3. _agenda_local_conflitos: o que a 7d tiraria com os modos ligados, com o texto (o foco e a saúde do P8 leem daqui). Não lê modo.
--   4. agenda_local_vigiar: a rodada do dia (a partir de local_hora), passo 0b3 do task-automations, chamada a cada tique como agenda_aprender e
--      agenda_habilidade. Os passos: calendario (o único que liga agenda.local_violacao), combinar e conflitos. agenda_vigiar não a chama.
--   5. _agenda_local_decidir e _agenda_desfazer_local: as respostas e o *desfaz*, despachados por agenda_decidir e agenda_desfazer.
--   6. _agenda_linhas_do_fechamento: a combinar que perde em até 2 dias úteis sobe a 75 (R6.7c-3), e o remendo do achado 13 sai (R6.12).
--   7. agenda_decisoes_abertas e _agenda_ver_decisoes: a combinar passa a ser respondível pela conversa (ver "desvios").
--
-- O QUE NÃO MUDA: com os 6 modos em sombra ou desligados, as linhas do fechamento são as de antes, byte a byte, salvo o remendo do achado 13
-- (R6.12), que é deliberado. Nenhum texto ao cliente, nenhuma mensagem a ninguém: as perguntas chegam ao dono pelo fechamento e pela conversa
-- (R6.3-2). agenda_vigiar, _agenda_vigia_*, _agenda_mudancas e o motor não são recriados. Não toca em handle_quote_deposit_payment, diárias nem
-- recebíveis.
--
-- O FREIO (R6.7b): quem abre pergunta lê _agenda_local_modo: com *gestor, só propor*, nenhuma pergunta nova, só a ação "Em teste". A pergunta já
-- aberta segue respondível: _agenda_local_decidir confere a pergunta e o modo CRU (_agenda_modo_da_pergunta). "Segure o dia" é pedido do dono:
-- o motor aplica com origem dono. agenda_local_vigiar roda com o freio; {rodou: false} só com os 6 desligados.
--
-- A DEPENDÊNCIA DE PUBLICAÇÃO (R6.12): o remendo do achado 13 só pode ir ao ar com o ai-daily-briefing com 62d1fd95 no ar antes ou junto. Fora dessa
-- ordem, a véspera do último dia some nos dias de revisão.
--
-- PROVA: supabase/tests/agenda_fase7d_combinar.sql na bancada (node scripts/bancada-agenda/rodar.mjs). APLICAR: só pelo roteiro de publicação da
-- 7d, depois da 20261107100300 e antes da 20261107100500. IDEMPOTENTE: create or replace function, revoke/grant e comment.
--
-- DESFAZER: recriar as 5 com o corpo da origem e apagar as 10 novas. Quem recriar depois uma destas copia DESTA migration (o P6,
-- _agenda_local_decidir e _agenda_local_restaurar; a 7f, _agenda_linhas_do_fechamento).

-- ── 1. O que combinar ─────────────────────────────────────────────────────────────────────────────

-- Os textos do combinar, num lugar só (§6.2 e §6.3). p_forma: foco (o pedaço da linha "Combinar:"), pergunta, urgente (a crítica de D-1), em_teste,
-- anotei (a ação da opção 1) e desfeito.
create or replace function public._agenda_combinar_texto(p_item jsonb, p_forma text, p_hoje date)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_tipo   text := p_item ->> 'tipo';
  v_para   date := (p_item ->> 'para')::date;
  v_ate    date := (p_item ->> 'ate')::date;
  v_fim    date := (p_item ->> 'fim')::date;
  v_cli    text := coalesce(p_item ->> 'cliente', 'cliente');
  v_bem    text := coalesce(p_item ->> 'bem', 'bem');
  v_no     text := case when nullif(p_item ->> 'local', '') is not null then public._agenda_local_no(p_item ->> 'local') end;
  v_quem   text := public._agenda_lista(array(select x from jsonb_array_elements_text(coalesce(p_item -> 'nomes', '[]'::jsonb)) x), null);
  v_varios boolean := jsonb_array_length(coalesce(p_item -> 'nomes', '[]'::jsonb)) > 1;
  v_nom    boolean := coalesce((p_item ->> 'nominal')::boolean, false);
  v_de     text;
  v_prazo  text;
  v_dia    text;
  v_dias   text;
  v_lugar  text;
begin
  if p_forma is null or p_forma <> all (array['foco', 'pergunta', 'urgente', 'em_teste', 'anotei', 'desfeito']) then
    raise exception '_agenda_combinar_texto: a forma "%" não existe.', p_forma using errcode = '22023';
  end if;
  v_de := coalesce(' de ' || nullif(v_quem, ''), '');
  v_dia := public._dia_curto(v_para);
  v_lugar := coalesce(' ' || v_no, '');
  -- R6.7c-2: o prazo do acesso é o próprio dia em que a pergunta nasce
  v_prazo := case when v_ate = p_hoje then 'O prazo é hoje.' else format('O prazo era %s.', public._dia_curto(v_ate)) end;
  v_dias := case when v_fim is null or v_fim = v_para then v_dia
                 when to_char(v_para, 'MM') = to_char(v_fim, 'MM') then public._agenda_dia_sem_mes(v_para) || ' a ' || public._dia_curto(v_fim)
                 else v_dia || ' a ' || public._dia_curto(v_fim) end;

  if p_forma = 'foco' then
    return case v_tipo
      when 'acesso' then format('o acesso%s para %s, %s', v_de, v_dia,
                                case when v_ate = p_hoje then format('até hoje (%s)', public._dia_curto(v_ate))
                                     else 'até ' || public._dia_curto(v_ate) end)
                         || case when nullif(p_item ->> 'nota', '') is not null then ' (regra a confirmar)' else '' end
      when 'reserva_marina' then format('a vaga de serviço com a marina, até %s', public._dia_curto(v_ate))
      when 'descida' then format('a descida para o teste na água em %s', v_dia)
      else format('a entrada do %s no pátio para %s, até %s', v_bem, v_dia, public._dia_curto(v_ate)) end;
  elsif p_forma = 'pergunta' then
    return case v_tipo
      when 'acesso' then
        case when v_nom then format('%s já autorizou %s%s para %s? %s 1) Já está (anoto); 2) Ainda não.', v_cli, v_quem, v_lugar, v_dia, v_prazo)
             else format('O acesso%s%s para %s (o serviço do %s) já está combinado? %s 1) Já está (anoto); 2) Ainda não.',
                         v_de, v_lugar, v_dia, v_cli, v_prazo) end
      when 'reserva_marina' then format('A vaga de serviço%s para o barco de %s (%s) já está combinada? %s 1) Já combinei; 2) Ainda não.',
                                        v_lugar, v_cli, v_dias, v_prazo)
      when 'descida' then format('A descida do barco de %s para o teste na água (%s) já está combinada? Quem desce: %s. 1) Já combinei; 2) Ainda não.',
                                 v_cli, v_dia, p_item ->> 'quem')
      else format('%s já combinou trazer o %s ao pátio para %s? %s 1) Já combinou (anoto que chega %s); 2) Ainda não.',
                  v_cli, v_bem, v_dia, v_prazo, v_dia) end;
  elsif p_forma = 'urgente' then
    -- "Amanhã" só quando é amanhã: na sexta, o dia útil seguinte é a segunda (a lição do achado 15 da 7c)
    return format('%s %s %s ao %s%s e o acesso ainda não está combinado. 1) Está combinado (anoto); 2) Vou combinar hoje (recomendo); 3) Segure o dia: eu remarco.',
                  case when v_para = p_hoje + 1 then 'Amanhã (' || v_dia || ')' else public._agenda_maiuscula(v_dia) end,
                  coalesce(nullif(v_quem, ''), 'você'),
                  case when v_quem = '' then 'vai' when v_varios then 'vão' else 'vai' end, v_cli, v_lugar);
  elsif p_forma = 'em_teste' then
    return case v_tipo
      when 'acesso' then format('Em teste: eu cobraria o acesso%s%s até %s.', v_de, v_lugar, public._dia_curto(v_ate))
      when 'reserva_marina' then format('Em teste: eu cobraria a vaga de serviço%s para o barco de %s até %s.', v_lugar, v_cli, public._dia_curto(v_ate))
      when 'descida' then format('Em teste: eu cobraria a descida do barco de %s para o teste na água (%s).', v_cli, v_dia)
      else format('Em teste: eu cobraria a entrada do %s de %s no pátio até %s.', v_bem, v_cli, public._dia_curto(v_ate)) end;
  elsif p_forma = 'anotei' then
    return case v_tipo
      when 'acesso' then
        case when v_nom then format('Anotei: %s %s%s no serviço de %s. *desfaz* volta.', v_quem,
                                    case when v_varios then 'autorizados' else 'autorizado' end, v_lugar, v_cli)
             else format('Anotei: o acesso%s%s está combinado no serviço de %s. *desfaz* volta.', v_de, v_lugar, v_cli) end
      when 'reserva_marina' then format('Anotei: a vaga de serviço%s para o barco de %s está combinada. *desfaz* volta.', v_lugar, v_cli)
      when 'descida' then format('Anotei: a descida do barco de %s para o teste na água está combinada. *desfaz* volta.', v_cli)
      else format('Anotei: o %s de %s chega %s. *desfaz* volta.', v_bem, v_cli, v_dia) end;
  end if;
  return case v_tipo
    when 'acesso' then
      case when v_nom then format('Desfeito: a autorização de %s saiu.', v_quem)
           else format('Desfeito: o acesso no serviço de %s voltou a ficar sem combinar.', v_cli) end
    when 'reserva_marina' then format('Desfeito: a vaga de serviço para o barco de %s voltou a ficar sem combinar.', v_cli)
    when 'descida' then format('Desfeito: a descida do barco de %s voltou a ficar sem combinar.', v_cli)
    else format('Desfeito: a chegada do %s de %s saiu.', v_bem, v_cli) end;
end;
$function$;

comment on function public._agenda_combinar_texto(jsonb, text, date) is
  'Agenda de Produção (Fase 7d, P5; §6.2, §6.3; R6.5, R6.7c-2): os textos de um item de _agenda_combinar_da_os — foco, pergunta, urgente (a crítica acesso de D-1: "Amanhã (qui 22/07)" só quando é amanhã), em_teste, anotei e desfeito. O prazo do acesso em D-2 diz "O prazo é hoje.". STABLE, invoker.';

-- As dependências com data da OS (§3.1, item 11; §5.5; R1): calculadas, nunca guardadas. O que fica guardado é o fato combinado.
create or replace function public._agenda_combinar_da_os(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_dono   uuid := public._agenda_dono(null);
  v_dias   date[];
  v_meios  int;
  v_d1     date;
  v_dn     date;
  v_l      jsonb;
  v_tipo   text;
  v_bem    jsonb;
  v_sit    text;
  v_o_bem  text;
  v_cli    text;
  v_au     jsonb;
  v_aut    uuid[];
  v_exige  boolean;
  v_falta  uuid[];
  v_nomes  text[];
  v_ok     boolean;
  v_ate    date;
  v_base   jsonb;
  v_i      jsonb;
  v_out    jsonb := '[]'::jsonb;
  pl       public.os_planejamento;
begin
  if p_os is null or p_hoje is null then
    raise exception '_agenda_combinar_da_os: faltam a OS ou o dia' using errcode = '22004';
  end if;
  -- O plano vigente, sem reserva, de hoje em diante
  select coalesce(array_agg(distinct a.dia order by a.dia), '{}'::date[]), count(distinct (a.dia, a.turno)) filter (where a.presenca = 'turno')::int
    into v_dias, v_meios
    from public.agenda_alocacoes a
   where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje;
  if cardinality(v_dias) = 0 then
    return v_out;
  end if;
  v_d1 := v_dias[1];
  v_dn := v_dias[cardinality(v_dias)];
  v_l := public._agenda_local_resolvido(p_os, p_hoje);
  v_tipo := v_l ->> 'tipo';
  v_bem := public._agenda_estado_do_bem(p_os, p_hoje);
  v_sit := v_bem ->> 'situacao';
  v_o_bem := case v_bem ->> 'classe' when 'rv' then 'motorhome' when 'barco' then 'barco' else 'bem' end;
  select * into pl from public.os_planejamento x where x.service_order_id = p_os;
  select public._agenda_nome_curto(cl.name) into v_cli
    from public.service_orders so join public.clients cl on cl.id = so.client_id where so.id = p_os;
  v_base := jsonb_build_object('fim', v_dn, 'cliente', v_cli, 'bem', v_o_bem, 'local', v_l ->> 'nome', 'local_id', v_l ->> 'local_id',
                               'nominal', false, 'pessoas', '[]'::jsonb, 'nomes', '[]'::jsonb, 'nota', null);

  -- [R] o acesso, em local de terceiro: o combinado é o acesso_ok_em dentro da validade (a régua da Fase 5) OU, no local que exige autorização
  -- com o nome, todas as pessoas alocadas (sem o dono) em os_autorizados. O pátio da HBR não é de terceiro.
  if v_tipo in ('marina', 'estaleiro', 'patio_parceiro', 'casa_cliente', 'outro') then
    v_au := public._agenda_autorizacao_da_os(p_os, p_hoje, v_l);
    v_aut := array(select x::uuid from jsonb_array_elements_text(coalesce(v_au -> 'autorizados', '[]'::jsonb)) x);
    v_exige := coalesce((v_au ->> 'exige')::boolean, false);
    select coalesce(array_agg(x.payee_id order by x.nome, x.payee_id), '{}'::uuid[]), coalesce(array_agg(x.nome order by x.nome, x.payee_id), '{}'::text[])
      into v_falta, v_nomes
      from (select distinct a.payee_id, public._agenda_nome_curto(py.name) as nome
              from public.agenda_alocacoes a
              join public.payees py on py.id = a.payee_id
             where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
               and a.payee_id is distinct from v_dono and not (a.payee_id = any (v_aut))) x;
    v_ok := (pl.acesso_ok_em at time zone 'America/Sao_Paulo')::date > p_hoje - c.cliente_acesso_validade_dias;
    v_ok := coalesce(v_ok, false) or (v_exige and cardinality(v_falta) = 0);
    v_ate := public.agenda_somar_du(v_d1, -c.autorizacao_antecedencia_du);
    v_i := v_base || jsonb_build_object('tipo', 'acesso', 'para', v_d1, 'ate', v_ate, 'quem', 'cliente', 'pessoas', to_jsonb(v_falta),
                                        'nomes', to_jsonb(v_nomes), 'combinado', v_ok, 'vencido', not v_ok and v_ate <= p_hoje,
                                        'nota', v_au -> 'nota', 'nominal', v_exige and coalesce((v_au ->> 'conferido')::boolean, false),
                                        'modo', public._agenda_local_modo('acesso'));
    v_out := v_out || jsonb_build_array(v_i || jsonb_build_object('texto', public._agenda_combinar_texto(v_i, 'foco', p_hoje)));
  end if;

  -- A vaga de serviço na garagem seca
  if v_sit = 'garagem_seca' and v_meios >= c.garagem_reserva_min_meios then
    v_ok := pl.reserva_marina_ok_em is not null;
    v_ate := public.agenda_somar_du(v_d1, -c.marina_reserva_antecedencia_du);
    v_i := v_base || jsonb_build_object('tipo', 'reserva_marina', 'para', v_d1, 'ate', v_ate, 'quem', 'marina', 'combinado', v_ok,
                                        'vencido', not v_ok and v_ate < p_hoje, 'modo', public._agenda_local_modo('bem'));
    v_out := v_out || jsonb_build_array(v_i || jsonb_build_object('texto', public._agenda_combinar_texto(v_i, 'foco', p_hoje)));
  end if;

  -- A descida para o teste na água: o último dia. A spec não dá antecedência: é a da marina, a mesma régua da vaga (notas do P5, desvio 3).
  if v_bem ->> 'exige' = 'agua' and v_sit in ('seco', 'garagem_seca') then
    v_ok := pl.descida_ok_em is not null;
    v_ate := public.agenda_somar_du(v_dn, -c.marina_reserva_antecedencia_du);
    v_i := v_base || jsonb_build_object('tipo', 'descida', 'para', v_dn, 'ate', v_ate, 'quem', coalesce(v_bem ->> 'descer_quem', 'o cliente ou a marina'),
                                        'combinado', v_ok, 'vencido', not v_ok and v_ate < p_hoje, 'modo', public._agenda_local_modo('bem'));
    v_out := v_out || jsonb_build_array(v_i || jsonb_build_object('texto', public._agenda_combinar_texto(v_i, 'foco', p_hoje)));
  end if;

  -- A entrada do bem no pátio
  if v_tipo in ('patio_hbr', 'patio_parceiro') then
    v_ok := pl.entrada_em is not null and pl.entrada_em <= v_d1;
    v_ate := public.agenda_somar_du(v_d1, -c.patio_entrada_antecedencia_du);
    v_i := v_base || jsonb_build_object('tipo', 'entrada', 'para', v_d1, 'ate', v_ate, 'quem', 'cliente', 'combinado', v_ok,
                                        'vencido', not v_ok and v_ate < p_hoje, 'modo', public._agenda_local_modo('patio'));
    v_out := v_out || jsonb_build_array(v_i || jsonb_build_object('texto', public._agenda_combinar_texto(v_i, 'foco', p_hoje)));
  end if;
  return v_out;
end;
$function$;

comment on function public._agenda_combinar_da_os(uuid, date) is
  'Agenda de Produção (Fase 7d, P5; §3.1, item 11; §5.5; R1; R6.7c-2): as dependências com data da OS, pelo plano vigente sem reserva, de hoje em diante: [{tipo (acesso, reserva_marina, descida, entrada), para, ate, fim, quem, pessoas uuid[], nomes[], combinado, vencido, nota, nominal, modo (o efetivo, de _agenda_local_modo), texto, cliente, bem, local, local_id}]. O item do acesso vence em ate <= hoje; os outros, em ate < hoje. A nota é o texto da regra do local não conferida (R1). Só leitura; nunca filtro de pessoa. STABLE, invoker: quem chama é definer.';

-- ── 2. A pergunta que ficou sem objeto ────────────────────────────────────────────────────────────

-- A cada tique com pergunta aberta (agenda_local_vigiar) e no começo da rodada: "resolvida sozinha quando o acesso entra" (R1). Sem isso, o acesso
-- que o cliente dá às 17:00 ainda sairia como decisão no fechamento das 17:30.
create or replace function public._agenda_local_resolver(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  q      record;
  v_tipo text;
  v_i    jsonb;
  v_mot  text;
  v_res  int := 0;
  v_desc int := 0;
begin
  for q in select x.id, x.tipo, x.chave, x.service_order_id, x.perda_em from public.agenda_perguntas x
            where x.estado = 'aberta' and x.tipo in ('combinar', 'acesso') order by x.criada_em, x.id loop
    -- O modo CRU: com *gestor, só propor* a pergunta segue de pé (R6.7b). O modo voltou a teste ou foi desligado: ela não pode mais ser respondida
    if coalesce(public._agenda_modo_da_pergunta(q.tipo, q.chave), 'desligado') <> 'ligado' then
      update public.agenda_perguntas set estado = 'descartada', resolvida_motivo = 'o modo voltou a teste: a pergunta não vale mais'
       where id = q.id;
      v_desc := v_desc + 1;
      continue;
    end if;
    v_tipo := case when q.tipo = 'acesso' then 'acesso' else split_part(q.chave, ':', 2) end;
    v_mot := null;
    v_i := null;
    -- A crítica diz "amanhã": no dia, ela já não tem o que perguntar
    if q.perda_em < p_hoje or (q.tipo = 'acesso' and q.perda_em = p_hoje) then
      v_mot := 'o dia passou';
    else
      select e into v_i from jsonb_array_elements(public._agenda_combinar_da_os(q.service_order_id, p_hoje)) e where e ->> 'tipo' = v_tipo;
      if v_i is null or (v_i ->> 'para')::date is distinct from q.perda_em then
        v_mot := 'o plano mudou';
      elsif (v_i ->> 'combinado')::boolean then
        v_mot := case when v_tipo = 'acesso' and (v_i ->> 'nominal')::boolean and jsonb_array_length(v_i -> 'pessoas') = 0 then 'a autorização foi anotada'
                      when v_tipo = 'acesso' then 'o acesso foi anotado'
                      else 'já foi combinado' end;
      end if;
    end if;
    if v_mot is not null then
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = v_mot where id = q.id;
      v_res := v_res + 1;
    end if;
  end loop;
  return jsonb_build_object('resolvidas', v_res, 'descartadas', v_desc);
end;
$function$;

comment on function public._agenda_local_resolver(date, timestamptz) is
  'Agenda de Produção (Fase 7d, P5; §5.5; R1; R6.7b): fecha as perguntas combinar e acesso abertas que ficaram sem objeto — o modo cru fora de ligado (descartada), o dia passou (a crítica já no dia, porque ela diz amanhã), o plano mudou (o item sumiu ou o dia dele é outro) ou o item ficou combinado (resolvida, com o motivo). {resolvidas, descartadas}. Invoker, sem grant: quem chama é definer.';

-- ── 3. A pergunta do dia ──────────────────────────────────────────────────────────────────────────
-- _agenda_gestor_perguntar não serve (R6.3-3): põe perda_em no dia do prazo e expira em 7 dias.
create or replace function public._agenda_local_combinar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  c_janela constant int := 21;   -- estrutural: o plano das próximas 3 semanas (§5.5)
  cf      public.agenda_config := public._agenda_cfg();
  r       record;
  e       jsonb;
  v_para  date;
  v_crit  boolean;
  v_chave text;
  v_r     jsonb;
  v_ab    int := 0;
  v_cr    int := 0;
  v_tes   int := 0;
  v_vd    int := 0;
  v_n     int;
  v_opc   jsonb;
begin
  v_r := public._agenda_local_resolver(p_hoje, p_agora);
  for r in
    select distinct a.service_order_id as os
      from public.agenda_alocacoes a
      join public.os_carteira(p_hoje) k on k.service_order_id = a.service_order_id
     where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia between p_hoje and p_hoje + c_janela
     order by 1
  loop
    for e in select x from jsonb_array_elements(public._agenda_combinar_da_os(r.os, p_hoje)) x loop
      continue when (e ->> 'combinado')::boolean or e ->> 'modo' = 'desligado';
      v_para := (e ->> 'para')::date;
      -- No dia, não há mais o que combinar: a ficha da véspera já avisou
      continue when v_para <= p_hoje;
      v_crit := e ->> 'tipo' = 'acesso' and p_hoje >= public.agenda_somar_du(v_para, -cf.acesso_urgente_du);
      continue when not (e ->> 'vencido')::boolean;
      v_chave := format('combinar:%s:%s:%s', e ->> 'tipo', r.os, v_para);

      -- Em teste (também com o freio: nenhuma pergunta nova): só a ação, uma vez por chave, e sem entrar no fechamento (contada): as linhas ficam
      -- byte a byte. O "o que mudou" a mostra.
      if e ->> 'modo' = 'sombra' then
        if not exists (select 1 from public.agenda_acoes a
                        where a.tipo = 'local' and not a.executada and a.service_order_id = r.os and a.depois ->> 'chave' = v_chave) then
          insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, depois, texto, contada_em)
          values (clock_timestamp(), p_hoje, false, 'vigia', 'local', r.os, array[r.os], jsonb_build_object('chave', v_chave),
                  public._agenda_corta(public._agenda_combinar_texto(e, 'em_teste', p_hoje), 400), p_agora);
          v_tes := v_tes + 1;
        end if;
        continue;
      end if;

      v_opc := jsonb_build_object('n', 1, 'efeito', jsonb_build_object('local', 'combinado', 'item', e - 'texto'));
      if v_crit then
        -- D-1: a combinar fecha e nasce a crítica, na mesma rodada: o dono nunca recebe as duas (R6.7c-2)
        update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'virou decisão'
         where chave = v_chave and modo = 'ligado' and estado = 'aberta';
        v_chave := format('acesso:%s:%s', r.os, v_para);
        insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, dia, perda_em, texto, opcoes, recomendacao, versao_base, modo,
                                             criada_em, expira_em)
        values ('acesso', v_chave, r.os, array[r.os], v_para, v_para, left(public._agenda_corta(public._agenda_combinar_texto(e, 'urgente', p_hoje), 600), 600),
                jsonb_build_array(v_opc || jsonb_build_object('texto', 'Está combinado'),
                                  jsonb_build_object('n', 2, 'texto', 'Vou combinar hoje', 'efeito', jsonb_build_object('local', 'nada')),
                                  jsonb_build_object('n', 3, 'texto', 'Segure o dia', 'efeito', jsonb_build_object('local', 'segurar'))),
                2, cf.versao_plano, 'ligado', p_agora, ((v_para + 1)::timestamp at time zone 'America/Sao_Paulo'))
        on conflict (chave, modo) where estado = 'aberta' do nothing;
        get diagnostics v_n = row_count;
        v_cr := v_cr + v_n;
      else
        -- "Amanhã eu pergunto de novo": a que o dono respondeu hoje volta só na rodada de amanhã
        continue when exists (select 1 from public.agenda_perguntas q
                               where q.chave = v_chave and q.modo = 'ligado'
                                 and (q.respondida_em at time zone 'America/Sao_Paulo')::date = p_hoje);
        insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, dia, perda_em, texto, opcoes, modo, criada_em, expira_em)
        values ('combinar', v_chave, r.os, array[r.os], v_para, v_para, left(public._agenda_corta(public._agenda_combinar_texto(e, 'pergunta', p_hoje), 600), 600),
                jsonb_build_array(v_opc || jsonb_build_object('texto', case e ->> 'tipo' when 'acesso' then 'Já está' when 'entrada' then 'Já combinou'
                                                                                         else 'Já combinei' end),
                                  jsonb_build_object('n', 2, 'texto', 'Ainda não', 'efeito', jsonb_build_object('local', 'nada'))),
                'ligado', p_agora, ((v_para + 1)::timestamp at time zone 'America/Sao_Paulo'))
        on conflict (chave, modo) where estado = 'aberta' do nothing;
        get diagnostics v_n = row_count;
        v_ab := v_ab + v_n;
      end if;
    end loop;
  end loop;
  v_vd := coalesce((v_r ->> 'resolvidas')::int, 0);
  return jsonb_build_object('abertas', v_ab, 'criticas', v_cr, 'resolvidas', v_vd, 'descartadas', coalesce((v_r ->> 'descartadas')::int, 0),
                            'em_teste', v_tes);
end;
$function$;

comment on function public._agenda_local_combinar(date, timestamptz) is
  'Agenda de Produção (Fase 7d, P5; §5.5; R1; R6.3-3; R6.7b; R6.7c-2): olha as OS da carteira com plano vigente nos próximos 21 dias e, em cada item vencido e não combinado, antes do dia: com o modo do tipo ligado por _agenda_local_modo, a pergunta combinar (não crítica; chave combinar:<tipo>:<os>:<para>; perda_em = para; expira no fim do dia para); no item acesso, a partir de agenda_somar_du(para, -acesso_urgente_du), a combinar fecha ("virou decisão") e nasce a crítica acesso (chave acesso:<os>:<para>, recomendação 2, veto_ate nulo); em sombra (também com o freio), só a ação local com executada = false, uma vez por chave e já contada: não entra no fechamento. A que o dono respondeu hoje volta só na rodada de amanhã. {abertas, criticas, resolvidas, descartadas, em_teste}. Definer, sem grant.';

-- ── 4. O que a 7d tiraria ─────────────────────────────────────────────────────────────────────────
create or replace function public._agenda_local_conflitos(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c      public.agenda_config := public._agenda_cfg();
  v_oss  uuid[];
  v_ate  date;
  v_lrs  jsonb := '[]'::jsonb;
  v_out  jsonb := '[]'::jsonb;
  v_os   uuid;
  v_lr   jsonb;
  v_lm   jsonb;
  v_rot  text;
  v_dias int[];
  v_mei  int[];
  v_sai  int;
  v_ret  date;
  v_i    int;
  v_h    int;
  v_mot  text;
  v_or   text;
  r      record;
  t      record;
  v_it   jsonb;
  v_pc   jsonb;
  v_ds   date[];
  v_n    int;
  v_util boolean[];
begin
  select coalesce(array_agg(distinct a.service_order_id order by a.service_order_id), '{}'::uuid[]), max(a.dia) into v_oss, v_ate
    from public.agenda_alocacoes a
   where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null;
  if cardinality(v_oss) = 0 then
    return v_out;
  end if;

  foreach v_os in array v_oss loop
    v_lr := public._agenda_local_resolvido(v_os, p_hoje);
    v_lrs := v_lrs || jsonb_build_array(v_lr);
    v_rot := public._agenda_rotulo_da_os(v_os);

    -- O dia fechado pelo local: a régua de _agenda_violacoes. O fixado pelo dono aparece com fica = true: ele não sai.
    v_lm := public._agenda_local_mascara(v_os, p_hoje, v_ate, p_hoje, v_lr);
    v_dias := public._agenda_ints(v_lm -> 'dias');
    v_mei := public._agenda_ints(v_lm -> 'meios');
    v_sai := coalesce((v_lm ->> 'sai')::int, 0);
    for r in
      select a.dia, array_agg(a.id order by a.id) as ids, bool_and(a.fixado_por is not distinct from 'dono') as fica
        from public.agenda_alocacoes a
       where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
       group by a.dia order by a.dia
    loop
      v_i := r.dia - p_hoje + 1;
      v_mot := null;
      if v_i = any (v_dias) then
        -- o motivo sem o parêntese da máscara (§6.2)
        v_mot := regexp_replace(v_lm -> 'motivos' ->> v_i::text, ' \([^()]*\)$', '');
        v_or := 'mascara';
      elsif v_sai > 0 and v_i >= v_sai then
        select pl.retirada_em into v_ret from public.os_planejamento pl where pl.service_order_id = v_os;
        v_mot := format('%s: o bem sai %s', public._dia_curto(r.dia), public._dia_curto(v_ret));
        v_or := 'retirada';
      end if;
      if v_mot is not null then
        v_out := v_out || jsonb_build_object('tipo', 'calendario', 'origem', v_or, 'os', v_os, 'dia', r.dia, 'turno', null, 'alocacoes', to_jsonb(r.ids),
                                             'fica', r.fica, 'motivo', v_mot, 'texto', format('%s: %s', v_rot, v_mot));
        continue;
      end if;
      -- O meio-dia fora do horário do local conferido
      for t in
        select a.turno, array_agg(a.id order by a.id) as ids, bool_and(a.fixado_por is not distinct from 'dono') as fica
          from public.agenda_alocacoes a
         where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.dia = r.dia and a.resultado is null
         group by a.turno order by a.turno = 'tarde'
      loop
        v_h := 2 * (v_i - 1) + case when t.turno = 'manha' then 1 else 2 end;
        if v_h = any (v_mei) then
          v_mot := format('%s: %s não recebe a equipe', public._agenda_meio_texto(r.dia, t.turno), coalesce(v_lr ->> 'nome', 'o local'));
          v_out := v_out || jsonb_build_object('tipo', 'calendario', 'origem', 'mascara', 'os', v_os, 'dia', r.dia, 'turno', t.turno, 'alocacoes', to_jsonb(t.ids),
                                               'fica', t.fica, 'motivo', v_mot, 'texto', format('%s: %s', v_rot, v_mot));
        end if;
      end loop;
    end loop;

    -- O acesso não combinado na véspera: só conta, não tira ninguém
    select e into v_it from jsonb_array_elements(public._agenda_combinar_da_os(v_os, p_hoje)) e where e ->> 'tipo' = 'acesso';
    if v_it is not null and not (v_it ->> 'combinado')::boolean and (v_it ->> 'para')::date > p_hoje
       and p_hoje >= public.agenda_somar_du((v_it ->> 'para')::date, -c.acesso_urgente_du) then
      v_mot := format('o acesso%s para %s ainda não está combinado', coalesce(' ' || public._agenda_local_no(v_it ->> 'local'), ''),
                      public._dia_curto((v_it ->> 'para')::date));
      v_out := v_out || jsonb_build_object('tipo', 'acesso', 'os', v_os, 'dia', v_it ->> 'para', 'fica', true, 'motivo', v_mot,
                                           'texto', format('%s: %s', v_rot, v_mot));
    end if;

    -- A viagem com pernoite quebrada: dias úteis seguidos, com a mesma equipe
    if public._agenda_viagem_da_os(v_os, p_hoje, v_lr) ->> 'tipo' = 'pernoite' then
      v_ds := array(select distinct a.dia from public.agenda_alocacoes a
                     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
                     order by 1);
      v_n := cardinality(v_ds);
      if v_n > 1 and (exists (select 1 from generate_series(1, v_n - 1) g(i) where public.agenda_du_entre(v_ds[g.i], v_ds[g.i + 1]) <> 1)
                      or (select count(distinct x.eq) from (
                            select string_agg(a.payee_id::text, ',' order by a.payee_id) as eq
                              from public.agenda_alocacoes a
                             where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
                               and a.presenca = 'turno'
                             group by a.dia, a.turno) x) > 1) then
        v_mot := format('a viagem precisa de %s dias úteis seguidos com a mesma equipe', v_n);
        v_out := v_out || jsonb_build_object('tipo', 'viagem', 'os', v_os, 'dia', v_ds[1], 'fica', false, 'motivo', v_mot,
                                             'texto', format('%s: %s', v_rot, v_mot));
      end if;
    end if;
  end loop;

  -- O pátio acima das vagas: em cada dia, quem chegou depois das vagas (a ocupação do motor, _agenda_patio_contexto). Até o último dia do plano: depois dele ninguém
  -- chega, e quem já estava junto já contou.
  v_util := array(select public.agenda_dia_util(p_hoje + g.d) from generate_series(0, v_ate - p_hoje) g(d) order by g.d);
  v_pc := public._agenda_patio_contexto(p_hoje, v_ate, p_hoje, v_oss, v_lrs, '{}'::uuid[], v_util);
  for r in
    select distinct on (y.k, y.i) y.k, y.i, y.d
      from (select x.k, x.i, g.d, row_number() over (partition by x.k, g.d order by x.d1, x.i) as pos
              from (select (e ->> 'k')::int as k, (e ->> 'i')::int as i, (e ->> 'd1')::int as d1, (e ->> 'd2')::int as d2
                      from jsonb_array_elements(v_pc -> 'pat_int') e) x
             cross join lateral generate_series(x.d1, x.d2) g(d)) y
     where y.pos > (v_pc -> 'pat_max' ->> (y.k - 1))::int
     order by y.k, y.i, y.d
  loop
    continue when r.i < 1;
    v_mot := format('%s: %s', public._dia_curto(p_hoje + r.d - 1),
                    public._agenda_patio_frase(v_pc -> 'pat_nomes' ->> (r.k - 1), (v_pc -> 'pat_max' ->> (r.k - 1))::int, true));
    v_out := v_out || jsonb_build_object('tipo', 'patio', 'os', v_oss[r.i], 'dia', p_hoje + r.d - 1, 'fica', false, 'motivo', v_mot,
                                         'texto', format('%s: %s', public._agenda_rotulo_da_os(v_oss[r.i]), v_mot));
  end loop;
  return v_out;
end;
$function$;

comment on function public._agenda_local_conflitos(date) is
  'Agenda de Produção (Fase 7d, P5; §5.5; R1; R6.8-4): o que a 7d tiraria ou apontaria no plano vigente de hoje em diante, sem ler modo nenhum: [{tipo (calendario, acesso, patio, viagem), os, dia, fica, motivo, texto; no calendario, origem (mascara ou retirada), turno e alocacoes}]. calendario = o dia ou o meio-dia que o local não recebe, ou depois da retirada, com a régua de _agenda_violacoes (fica = true no que o dono fixou: ele não sai); acesso = a véspera sem acesso (só conta); patio = quem está acima das vagas; viagem = a pernoite com dia quebrado ou equipe diferente. O foco e a saúde do P8 leem daqui, e o passo calendario de agenda_local_vigiar. STABLE, invoker: quem chama é definer.';

-- ── 5. O passo calendario e a rodada ──────────────────────────────────────────────────────────────

-- R6.8-4: o ÚNICO que liga agenda.local_violacao. Cada OS no seu bloco: o set_config de dentro volta com a subtransação quando agenda_replanejar
-- lança, e a variável nunca fica ligada para a OS seguinte, para o resto da transação nem para o tique seguinte.
create or replace function public._agenda_local_calendario(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  v_patio  boolean := public._agenda_local_modo('patio') = 'ligado';
  v_oss    uuid[];
  v_os     uuid;
  v_r      jsonb;
  v_ok     int := 0;
  v_err    int := 0;
  v_estado text;
  v_msg    text;
begin
  v_oss := array(select distinct (e ->> 'os')::uuid
                   from jsonb_array_elements(public._agenda_local_conflitos(p_hoje)) e
                  where e ->> 'tipo' = 'calendario' and not (e ->> 'fica')::boolean and (e ->> 'origem' = 'mascara' or v_patio)
                  order by 1);
  foreach v_os in array v_oss loop
    begin
      perform set_config('agenda.local_violacao', 'on', true);
      v_r := public.agenda_replanejar(array[v_os], 'local', 'vigia', p_hoje, p_agora);
      perform set_config('agenda.local_violacao', '', true);
      if coalesce((v_r ->> 'ok')::boolean, false) then
        v_ok := v_ok + 1;
      end if;
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_err := v_err + 1;
      perform public.log_app_error('db', format('o local, passo calendario (%s): %s', public._agenda_rotulo_da_os(v_os), v_msg), 'agenda', 'local:calendario',
                                   'error', jsonb_build_object('passo', 'calendario', 'os', v_os, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end loop;
  return jsonb_build_object('os', cardinality(v_oss), 'replanejadas', v_ok, 'erros', v_err);
end;
$function$;

comment on function public._agenda_local_calendario(date, timestamptz) is
  'Agenda de Produção (Fase 7d, P5; R6.8-4): o passo calendario da rodada do local, só com modo_local_calendario ligado por _agenda_local_modo (quem chama confere): para cada OS de _agenda_local_conflitos com dia fechado que não ficou fixado pelo dono (a retirada, só com modo_patio ligado), liga agenda.local_violacao, chama agenda_replanejar(array[os], ''local'', ''vigia'', …) e desliga. Cada OS no seu bloco: o que falha vai a app_error_logs (agenda, local:calendario), e a variável volta com a subtransação. {os, replanejadas, erros}. Invoker, sem grant.';

create or replace function public.agenda_local_vigiar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_passos constant text[] := array['calendario', 'combinar', 'conflitos'];
  cf       public.agenda_config;
  v_t0     timestamptz := clock_timestamp();
  v_modos  jsonb;
  v_passo  text;
  v_r      jsonb;
  v_cont   jsonb := '{}'::jsonb;
  v_erros  int := 0;
  v_falhas jsonb := '[]'::jsonb;
  v_estado text;
  v_msg    text;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da rodada do local.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_local'));
  cf := public._agenda_cfg();
  v_modos := jsonb_build_object('calendario', public._agenda_local_modo('calendario'), 'acesso', public._agenda_local_modo('acesso'),
                                'bem', public._agenda_local_modo('bem'), 'patio', public._agenda_local_modo('patio'),
                                'viagem', public._agenda_local_modo('viagem'), 'mesmo_local', public._agenda_local_modo('mesmo_local'));

  -- A cada tique, só com pergunta aberta: o acesso que entrou resolve a pergunta antes do fechamento (R1). Sem pergunta, uma consulta só.
  if exists (select 1 from public.agenda_perguntas q where q.estado = 'aberta' and q.tipo in ('combinar', 'acesso')) then
    begin
      perform public._agenda_local_resolver(p_hoje, p_agora);
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      perform public.log_app_error('db', format('o local, passo resolver: %s', v_msg), 'agenda', 'local:resolver', 'error',
                                   jsonb_build_object('passo', 'resolver', 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end if;

  if not exists (select 1 from jsonb_each_text(v_modos) m where m.value <> 'desligado') then
    return jsonb_build_object('rodou', false, 'modos', v_modos);
  end if;
  if (p_agora at time zone 'America/Sao_Paulo')::time < cf.local_hora then
    return jsonb_build_object('rodou', false, 'cedo', true, 'modos', v_modos, 'hora', cf.local_hora);
  end if;
  if exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'local' and x.p_hoje = p_hoje) then
    return jsonb_build_object('rodou', false, 'ja_rodou', true, 'modos', v_modos);
  end if;

  -- calendario primeiro: o combinar olha o plano já replanejado. calendario só com o modo ligado; conflitos só conta.
  foreach v_passo in array c_passos loop
    continue when v_passo = 'calendario' and v_modos ->> 'calendario' <> 'ligado';
    begin
      if v_passo = 'calendario' then
        v_r := public._agenda_local_calendario(p_hoje, p_agora);
        v_erros := v_erros + coalesce((v_r ->> 'erros')::int, 0);
      elsif v_passo = 'combinar' then
        v_r := public._agenda_local_combinar(p_hoje, p_agora);
      else
        v_r := (select coalesce(jsonb_object_agg(x.tipo, x.n), '{}'::jsonb)
                  from (select e ->> 'tipo' as tipo, count(*) as n
                          from jsonb_array_elements(public._agenda_local_conflitos(p_hoje)) e group by 1) x);
      end if;
      v_cont := v_cont || jsonb_build_object(v_passo, coalesce(v_r, '{}'::jsonb));
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_erros := v_erros + 1;
      v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
      perform public.log_app_error('db', format('o local, passo %s: %s', v_passo, v_msg), 'agenda', 'local:' || v_passo, 'error',
                                   jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end loop;

  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms,
                                           rotina, modo_equipe, modo_diaria)
  values (clock_timestamp(), p_hoje, p_agora, cf.modo_proposta, cf.modo_vigia,
          v_cont || jsonb_build_object('modos', v_modos, 'falhas', v_falhas),
          least(v_erros, 32767), greatest(0, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int),
          'local', cf.modo_equipe, cf.modo_diaria);

  return jsonb_build_object('rodou', true, 'modos', v_modos, 'contagens', v_cont, 'erros', v_erros, 'falhas', v_falhas);
end;
$function$;

comment on function public.agenda_local_vigiar(date, timestamptz) is
  'Agenda de Produção (Fase 7d, P5; §5.5; R6.7b; R6.8-4): a rodada do local (o passo 0b3 do task-automations, a cada tique, o molde de agenda_habilidade; agenda_vigiar não a chama) — uma vez por dia, a partir de local_hora (antes: {rodou: false, cedo: true}; o 2º tique do dia: {rodou: false, ja_rodou: true}); com os 6 modos desligados, {rodou: false}; com o freio, roda (só lê e grava "Em teste"). A cada tique, só com pergunta combinar ou acesso aberta, _agenda_local_resolver. Os passos, cada um no seu bloco (o que falha vai a log_app_error, context agenda, action local:<passo>, e os outros seguem): calendario (com modo_local_calendario ligado, o único que liga agenda.local_violacao), combinar e conflitos (só conta). Grava agenda_vigia_rodadas (rotina local). {rodou, modos (os efetivos), contagens, erros, falhas}. Nenhuma mensagem a ninguém. Definer; só service_role.';

-- ── 6. A resposta do dono ─────────────────────────────────────────────────────────────────────────

-- Volta as colunas de os_planejamento que a ação local gravou, só se ainda são as que ela gravou. As colunas do P6 entram quando ele recriar.
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
         historico = public._os_material_historico(p.historico, jsonb_build_object(
           'em', (p_agora at time zone 'America/Sao_Paulo')::date, 'quando', p_agora, 'autor', p_autor, 'por', 'dono', 'motivo', 'desfeito',
           'acao', a.id, 'antes', a.depois - 'item' - 'replano_acoes', 'depois', a.antes)),
         atualizado_em = p_agora, atualizado_por = p_autor
   where p.service_order_id = a.service_order_id;
  return true;
end;
$function$;

comment on function public._agenda_local_restaurar(uuid, uuid, timestamptz) is
  'Agenda de Produção (Fase 7d, P5; §5.5): volta as colunas de os_planejamento que a ação local gravou (o antes: acesso_ok_em, reserva_marina_ok_em, descida_ok_em, entrada_em e entrada_fonte, nao_antes_de e nao_antes_motivo), só se o que está gravado ainda é o depois dela; senão false, nada muda. Guarda no histórico. Invoker, sem grant: chamam _agenda_desfazer_local e agenda_desfazer, definer.';

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

  if v_ef = 'segurar' then
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
  'Agenda de Produção (Fase 7d, P5; §5.5; R6.7c-1): o *desfaz* da ação local — dentro do desfazivel_ate e só se nada mudou depois: as colunas voltam (_agenda_local_restaurar), as linhas de os_autorizados que ela criou ganham revogado_em e o replano do "Segure o dia" volta, cada ação pelo agenda_desfazer de sempre (com agenda.desfazer_local ligada, para não restaurar duas vezes). Só agenda_desfazer chama (o plano já travado).';

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
  if v_q.tipo not in ('combinar', 'acesso') then
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
  'Agenda de Produção (Fase 7d, P5; §5.5; R1; R6.5; R6.7b; R6.7c-1): a resposta do dono às perguntas combinar e acesso (o tipo local é do P6). Recusa a fechada, a de outro tipo e a que está fora de ligado pelo modo CRU (_agenda_modo_da_pergunta, não o freio: com *gestor, só propor* a aberta continua respondível). combinar, opção 1 e acesso, opção 1: grava o fato com a ação local desfazível — acesso_ok_em (no local que exige autorização com o nome e conferido, também uma linha de os_autorizados por pessoa da pergunta, fonte dono, valido_ate = o último dia), reserva_marina_ok_em, descida_ok_em ou entrada_em = para com entrada_fonte = dono. combinar, opção 2: só responde; a rodada de amanhã pergunta de novo. acesso, opção 2: fica aberta até o dia, com a opção anotada. acesso, opção 3 ("Segure o dia"): grava nao_antes_de = greatest(coalesce(nao_antes_de, para), agenda_somar_du(para, 1)) e nao_antes_motivo = sem acesso e só então chama agenda_replanejar(os, sem acesso, dono): o dia cai pela regra a.dia < nao_antes_de; o fixado pelo dono fica, e o texto diz; o dia avisado ao cliente abre a dia_avisado. A ação local leva replano_acoes: o *desfaz* volta tudo. Falhou = nada fica. Definer, sem grant: só agenda_decidir chama.';

-- ── 7. As recriadas ───────────────────────────────────────────────────────────────────────────────

-- agenda_decidir (de 20261101100800_agenda_fase77b_correcao.sql)
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
  -- FASE 7d: (7d P5, §5.5, R1) as perguntas do que combinar têm o efeito delas e a regra delas (a pergunta e o modo cru, não o freio: R6.7b):
  -- _agenda_local_decidir. Vem antes do "não é de decisão": a combinar não é crítica. O tipo local é do P6.
  if v_q.tipo in ('combinar', 'local', 'acesso') then
    return public._agenda_local_decidir(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_hoje, p_agora);
  end if;
  -- FASE 7d: fim
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
        -- (correção da revisão da 7b, achados 3 e 10) a opção com dias da pergunta dos dias do dono ("Fico em campo de seg a
        -- sex") diz os dias dele de toda semana: só ela troca o padrão (o gravador prende só a semana em qualquer outra fala do dono)
        if cardinality(v_7b_dias) > 0 and v_q.payee_id is not distinct from public._agenda_dono(null) then
          perform set_config('agenda.dias_padrao_do_dono', 'sim', true);
        end if;
        -- (correção da revisão da 7b: fim)
        v_7b_g := public._agenda_equipe_dias_gravar(v_q.payee_id, v_q.dia, v_7b_dias,
                                                    coalesce((v_opc #>> '{efeito,sabado}')::boolean, false), 'dono',
                                                    'opção ' || p_opcao, p_agora, null, v_q.id, p_autor);
        -- (correção da revisão da 7b, achados 3 e 10) a variável volta a vazio logo depois
        perform set_config('agenda.dias_padrao_do_dono', '', true);
        -- (correção da revisão da 7b: fim)
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
  'Agenda de Produção (Fase 2, P2): a resposta do dono a uma pergunta crítica aberta (só em ligado). Opção que não existe = recusa, nada marcado. Se a agenda mudou desde a pergunta, o efeito da opção é refeito agora e, se não termina como a opção dizia (espera), devolve a pergunta com os dias de agora sem executar. Senão: a pergunta fica respondida (opcao_escolhida, resposta = as palavras do dono, respondida_*) e o efeito é executado — agenda_propor(replano, as OS da pergunta, as restrições da opção + decisao) e agenda_aplicar com p_pergunta (toda ação sai critica = true com pergunta_id). Falhou = nada fica, a pergunta continua aberta. Canais: whatsapp, painel, tela. Fase 3: diaria e diaria_ligar vão a _agenda_decidir_diaria (o lançamento, a correção pelo registrar_diaria ou a ligação às OS, com modo_diaria ligado). Fase 5 (P3): cliente_aprovar e cliente_aviso vão a _agenda_cliente_decidir (manda ou segura a mensagem ao cliente; com modo_cliente ligado). Fase 6 (P6): aprendizado vai a _agenda_aprendizado_decidir (1 o medido passa a valer — na carga, agenda_config.carga_max muda —, 2 trava, 3 volta ao padrão e trava; a 1 e a 3 com a ação crítica desfazível; com modo_aprendizado ligado e o item na lista). CORREÇÃO FASE 6 (C1, regressão B2): a pergunta do aprendizado toma pg_advisory_xact_lock(hashtext(''agenda_aprender'')) antes do for update da pergunta. FASE 7 (7a P4): as perguntas do gestor da agenda (situacao, estimativa, reavaliar, reestimar, ficha_estimativa, onda, sabado, bem_livre, compre_ate, sinal) vão a _agenda_gestor_decidir (o efeito e o modo delas: o do gestor); dia_avisado e dia_prometido seguem a decisão crítica de sempre; equipe_cadastro, a de antes. FASE 7b (P3; R4.1-3, R4.1-6, R4.2(b)): as perguntas da equipe com opções têm o efeito delas, com a pergunta e o modo dela (_agenda_modo_da_pergunta) ligados (senão "ainda está em teste") — equipe_cadastro chamada: 1 "Anotei: sigo com a equipe que tenho."; 2 "Me diga quem saiu ou quem entrou e em que dias vem (ex.: Alex saiu; Mateus vem qua e qui; Mateus vem toda terça)." (sem diária); equipe_cadastro contato: 1 põe na lista da rotina (agenda_equipe_contato recebe_rotina, incluido_por dono) com a ação equipe desfazível ("Pus Mateus na rotina da equipe, como você pediu. *desfaz* tira.", depois.motivo contato); 2 grava a recusa — a linha parada (recebe_rotina false, parou_em agora, "você disse que não"): nem a regra d14 nem a pergunta voltam; dias_semana: a opção com dias grava a semana pelo _agenda_equipe_dias_gravar (origem dono; a 2, "Fico em campo de seg a sex", cria o padrão do dono {1..5} sem frequência; a 3, "Nenhum dia", prende só a semana), com a ação equipe do dono; a 1 ("Fica assim") só fica respondida. A chamada da 7a (sem opções) e o telefone (sem opções) seguem o de antes. CORREÇÃO DA REVISÃO DA 7b (achados 3 e 10): na pergunta dias_semana do dono, a opção com dias grava com agenda.dias_padrao_do_dono = sim (só nessa chamada): ela é a única fala do dono que troca o padrão dele ("Fico em campo de seg a sex" = toda semana); a resposta diz "toda semana a partir de agora". FASE 7d (P5, §5.5, R1): os tipos combinar, local e acesso vão a _agenda_local_decidir (o efeito e a regra delas: a pergunta e o modo cru, não o freio), antes do "não é de decisão".';

-- agenda_desfazer (de 20261101100800_agenda_fase77b_correcao.sql)
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
  -- FASE 7b: (correção da revisão da 7b, achado 18) desfazer a 2ª pessoa da dupla
  v_7bc_ajud text;
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
  -- FASE 7d: (7d P5, §5.5) a ação local tem o desfazer dela: as colunas de os_planejamento voltam ao antes, as linhas de os_autorizados que ela criou
  -- ganham revogado_em e o replano do "Segure o dia" volta (_agenda_desfazer_local)
  if v_a.tipo = 'local' then
    return public._agenda_desfazer_local(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 7d: fim
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
    -- FASE 7b: (correção da revisão da 7b, achado 18) no serviço em que o gestor completou a dupla, a revisão encurtou o fim e outra OS
    -- ocupou o meio-dia que sobrou: a recusa (a regra de sempre: o *desfaz* nunca sobrepõe) diz como voltar — desfazer antes o que
    -- ocupou o lugar
    if v_os is not null and exists (select 1 from public.agenda_alocacoes a
                                     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.motivos ? 'dupla_completa') then
      v_7bc_ajud := public._agenda_lista(array(
                      select distinct public._agenda_nome_curto(py.name) from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
                       where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.motivos ? 'dupla_completa' order by 1));
      return jsonb_build_object('ok', false,
        'texto', format('Não dá para desfazer: o %s já está no %s %s. Com %s junto, o %s acaba antes; se quiser o dia de volta mesmo assim, diga *desfaz %s* e depois *desfaz %s*.',
                        public._agenda_nome_curto(v_x.pessoa), coalesce(public._agenda_nome_curto(v_x.cliente), 'outro serviço'),
                        public._agenda_meio_texto(v_x.dia, v_x.turno), v_7bc_ajud, v_nome,
                        coalesce(public._agenda_nome_curto(v_x.cliente), 'outro serviço'), v_nome));
    end if;
    -- FASE 7b: fim
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
  -- FASE 7b: (correção da revisão da 7b, achado 18) desfazer a 2ª pessoa que o gestor pôs na dupla (as alocações com o motivo
  -- dupla_completa) tira só ela: o serviço continua marcado — o texto de antes dizia que ele saía da agenda
  if cardinality(v_novas) = 0 and cardinality(v_canc) > 0 and v_os is not null and public._agenda_os_tem_dia(v_os, p_hoje)
     and not exists (select 1 from public.agenda_alocacoes a where a.id = any (v_canc) and not coalesce(a.motivos ? 'dupla_completa', false)) then
    v_txt := format('Desfeito: tirei %s do %s %s; o resto do serviço fica como estava.',
                    public._agenda_lista(array(select distinct public._agenda_nome_curto(py.name)
                                                 from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
                                                where a.id = any (v_canc) order by 1)),
                    public._agenda_rotulo_da_os(v_os),
                    public._agenda_meios_frase((select jsonb_agg(jsonb_build_object('dia', a.dia, 'turno', a.turno) order by a.dia, a.turno)
                                                  from public.agenda_alocacoes a where a.id = any (v_canc))));
  end if;
  -- FASE 7b: fim
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
  -- FASE 7d: (7d P5, R6.7c-1) o replano do "Segure o dia", desfeito direto (sem a ação local): o "não antes de" volta junto, senão a vigia tiraria o
  -- dia de novo no tique seguinte; e a ação local fica desfeita. Quem desfaz pela ação local liga agenda.desfazer_local e faz isso ela.
  if coalesce(current_setting('agenda.desfazer_local', true), '') <> 'on' then
    for v_x in select e.id from public.agenda_acoes e
                where e.tipo = 'local' and e.executada and e.desfeita_em is null
                  and coalesce(e.depois -> 'replano_acoes', '[]'::jsonb) ? v_a.id::text loop
      perform public._agenda_local_restaurar(v_x.id, p_autor, p_agora);
      update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_x.id;
    end loop;
  end if;
  -- FASE 7d: fim
  return jsonb_build_object('ok', true, 'texto', v_txt, 'acao_id', v_acao, 'recriadas', to_jsonb(v_novas), 'canceladas', to_jsonb(v_canc));
end;
$function$;

comment on function public.agenda_desfazer(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): desfaz uma ação executada — recusa (nada muda) se foi sombra, já foi desfeita, não é desfazível (pedido do dono pela tela ou aprovação), passou o desfazivel_ate, algum meio-dia criado já começou ou tem resultado, ou recriar o que saiu bateria em quem já está no lugar ("Não dá para desfazer: o Roberto já está no Giancarlo…"). Faz: o que ela criou → cancelada (desfeito); o que ela tirou volta igual (substitui_id, mesmo estado/fixado); o status pela porta (via desfazer; o que começou não regride); o espelho; nova ação tipo desfazer (desfaz_a) e a original ganha desfeita_*. Desfazer uma decisão crítica cria a pergunta de novo ("A decisão sobre o Nelson volta a ficar com você."). Fase 3: concluir e entregar vão a _agenda_desfazer_marco (as cobranças da conclusão, a saída, a comissão de vendedor e a entrega); a diária da agenda a _agenda_desfazer_diaria (apaga o turno que ela criou, com o acerto aberto); desfazer o replano da ausência da equipe tira a ausência do dia (agenda_disponibilidade substituída). Fase 4 (P4): a ação material (a previsão pela mensagem do fornecedor, a chegada pela nota) vai a _agenda_desfazer_material (as linhas voltam se ninguém mexeu nelas depois). Fase 5 (P4): o que a resposta do cliente mudou (a ação fixar/cliente de origem cliente com depois.resposta_id: a confirmação, o pedido de dia, o acesso) vai a _agenda_desfazer_cliente; a outra ação cliente (a mensagem enviada, o acorde, a decisão do aviso) não se desfaz ("Mensagem enviada não se desmanda."); desfazer direto o replano que o pedido de dia causou também tira o pedido (_agenda_cliente_restaurar_pedido) e deixa a ação do cliente desfeita. Fase 6 (P6): a ação aprendizado vai a _agenda_desfazer_aprendizado (o em_uso de antes volta, nulo = o padrão, e a chave fica travada por aprender_trava_dias; a da carga volta carga_max). FASE 7 (7a P7, spec R3): as ações do gestor que não são de alocação têm o ramo delas — estimar (os_planejamento.dias, estimativa_fonte e estimativa_em voltam ao antes da ação: "Desfeito: o Nelson (OS-00112) volta sem os dias que eu contei (4 dias). Me diga quantos dias são."), dupla (dupla_dita, dupla_meios, dupla_motivo e dupla_em voltam) e gestor (gestor_so_propor e gestor_so_propor_em voltam), cada uma só se nada mudou depois dela (senão a recusa diz o que mudou), dentro do desfazivel_ate; reparar e reestimar seguem o caminho de alocação de sempre. E (a medição de 30/10, item 4) o que a ação tirou e era de quem não está mais na equipe naquele dia (agenda_capacidade) não volta: o desfazer restaura só o que cabe e diz o resto ("… João e Roberto não estão mais na equipe: os dias deles não voltam."); se tudo o que voltaria é de quem saiu e a ação não criou nada de pé, nada muda ({ok: false, status saiu_da_equipe}). FASE 7b (P3, §5.2): a ação equipe que pôs alguém na rotina da equipe — pela regra d14 (vigia, depois.motivo regra_d14) ou pelo "1) Ponho" do dono (depois.motivo contato) — se desfaz dentro do desfazivel_ate: a linha em agenda_equipe_contato fica parada (recebe_rotina false, parou_em, "desfeito pelo dono"; a regra não a põe de novo) e "Desfeito: Rafael sai da rotina da equipe e não recebe mais a ficha nem a pergunta dos dias."; já fora da rotina = nada muda. CORREÇÃO DA REVISÃO DA 7b (achado 18): desfazer a ação que só pôs a 2ª pessoa na dupla (alocações com o motivo dupla_completa) diz "Desfeito: tirei Mateus do Lenine (OS-00074) em ter 10/11 (manhã e tarde); o resto do serviço fica como estava." (não "sai da agenda"); a recusa por sobreposição no serviço com a dupla completada acrescenta "Com Mateus junto, o Lenine acaba antes; se quiser o dia de volta mesmo assim, diga *desfaz Tânia* e depois *desfaz Lenine*.". FASE 7d (P5, §5.5, R6.7c-1): a ação local vai a _agenda_desfazer_local; o replano do "Segure o dia" desfeito direto também volta o "não antes de" (_agenda_local_restaurar) e deixa a ação local desfeita.';

-- _agenda_linhas_do_fechamento (de 20261102100590_agenda_fase77c_correcao2.sql)
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
  -- (correção 3) o prazo de quem vence, na forma curta
  v_c3_ate    timestamptz;
  -- (correção 3: fim)
  -- FASE 7b: fim
  -- FASE 7c: (7c P5, R5.4 item 4) a linha (n) com as perguntas de quem faz o quê
  v_7c_on    boolean;
  v_7c_7b    boolean;
  v_7c_q     record;
  v_7c_eq    boolean;
  v_7c_marc  text;
  v_7c_exig  text;
  v_7c_ate   timestamptz;
  -- FASE 7c: fim
  -- FASE 7c: (7c P8, R5.4 item 4, R5.2-2(b)) as perguntas das etapas na linha (n) e a linha (o) das etapas
  v_p8_on     boolean;
  v_p8_q      record;
  v_p8_quem   boolean;
  v_p8_pess   record;
  v_p8_h      jsonb;
  v_p8_a      jsonb;
  v_p8_hi     jsonb;
  v_p8_ai     jsonb;
  v_p8_nomes  text[] := '{}';
  v_p8_nfone  int;
  v_p8_nrot   int;
  v_p8_hoje   jsonb := '[]'::jsonb;
  v_p8_amanha jsonb := '[]'::jsonb;
  v_p8_txt    text;
  v_p8_curto  text;
  v_p8_alta   boolean;
  v_p8_k      int;
  v_p8_g      record;
  v_p8_parte  text[];
  v_p8_dia    text;
  -- FASE 7c: fim
  -- FASE 7c: (7c correção, achados 14, 8 e 2) a 7b que espera a vez dela, a forma curta do cliente e a (n) que ficou de fora
  c_c2_dias   constant int := 2;    -- estrutural: os dias úteis que a pergunta de quem faz o quê espera sem ser vista antes de subir
  c_c2_perda  constant int := 77;   -- estrutural: acima das perguntas do gestor (76), abaixo da compra e da decisão (80)
  v_c14_pula  boolean;
  v_c8_agora  timestamptz;
  v_c8_tipo   text;
  v_c8_env    timestamptz;
  v_c8_qid    uuid;
  v_c8_nome   text;
  v_c8_n      int;
  v_c8_curto  text;
  -- FASE 7c: fim
  -- FASE 7c: (7c correção 2, achados 1, 11, 13 e 15) a cobrança do último dia antes de um dia de revisão, as linhas de 75 que sobem
  -- juntas e a "Também" de quem faz o quê que conta
  v_c13_av     jsonb := '[]'::jsonb;
  v_c13_d      date;
  v_c13_prox   date;
  v_c13_k      int;
  v_c13_p      record;
  v_c13_u      jsonb;
  v_c13_rev    boolean;
  v_c13_q      text;
  v_c13_parte  text[];
  v_c13_ult    boolean := false;
  v_c11_tambem boolean := false;
  -- FASE 7c: fim
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
            -- FASE 7d: (7d P5, §5.5) a crítica acesso em que o dono já disse "vou combinar hoje" fica aberta até o dia, mas não volta ao fechamento
            and not (x.tipo = 'acesso' and x.opcao_escolhida is not null)
            -- FASE 7d: fim
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
  -- (7c P5, R5.4 item 4, R5.10-8) o portão da linha separado por etapa: o bloco roda com a 7b (modo_dias ou modo_cadastro) OU com
  -- a 7c (modo_habilidade_propor ou modo_habilidade) fora de desligado; dentro dele, as perguntas da 7b só entram com o portão da 7b
  -- (v_7c_7b) e as de quem faz o quê só com o da 7c (v_7c_on). v_7b_on volta a ser só o da 7b logo depois do bloco: a pergunta de fato
  -- (e) exclui só os tipos que a (n) levou (sem isso, com a 7b desligada e a 7c em teste, a chamada da 7a sairia da (e), perda 30,
  -- para a (n), perda 75, e o texto do dono mudaria).
  v_7c_on := cf.modo_habilidade_propor <> 'desligado' or cf.modo_habilidade <> 'desligado';
  v_7c_7b := v_7b_on;
  v_7b_on := v_7b_on or v_7c_on;
  -- (7c: fim)
  -- (7c P8, R5.4 item 4) e com as etapas (modo_tarefas) fora de desligado: as perguntas das etapas (tarefa) só com o portão delas
  v_p8_on := cf.modo_tarefas <> 'desligado';
  v_7b_on := v_7b_on or v_p8_on;
  -- (7c: fim)
  if v_7b_on then
    for m in select unnest(array['ligado', 'sombra']) loop
      v_7b_ids := '[]'::jsonb;
      v_7b_txt := null;
      v_7b_itens := '{}';
      v_7b_curtos := '{}';
      v_7b_rest := 0;
      v_7b_perde := false;
      v_7b_lig := true;
      -- (7c correção, achado 14) a 7b não gasta a vez dela por causa da 7c: sem nenhuma pergunta da 7b que perca hoje (nunca vista, o
      -- veto ou o prazo de hoje) e com uma de quem faz o quê ou das etapas que perde hoje, as da 7b ficam fora da linha neste dia — a da
      -- 7c vai primeiro e inteira (conta como vista) e a chamada não é contada como mostrada num dia que não é o dela. Antes, com a de
      -- quem faz o quê só como "Também" (não conta), a perda 75 dela fazia a chamada sair e gastar as 2 vezes antes do dia em que vence,
      -- e quem faz o quê só era vista quando a chamada saía da linha. Com a 7b perdendo hoje, a de antes (a 7b primeiro). Sem a 7c, a de antes.
      v_c14_pula := v_7c_7b and (v_7c_on or v_p8_on)
        and not exists (select 1 from public.agenda_perguntas x
                         where x.estado = 'aberta' and x.modo = m and not x.critica and x.tipo in ('equipe_cadastro', 'dias_semana')
                           and x.mostrada_vezes < cf.perguntas_vezes_max
                           and not exists (select 1 from public.agenda_dono_avisos v
                                            where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
                           and (x.mostrada_vezes = 0
                                or (x.veto_ate is not null and (x.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                                or x.perda_em is not distinct from p_hoje))
        and exists (select 1 from public.agenda_perguntas x
                     where x.estado = 'aberta' and x.modo = m and not x.critica
                       and ((v_7c_on and x.tipo = 'habilidade') or (v_p8_on and x.tipo = 'tarefa'))
                       and x.mostrada_vezes < cf.perguntas_vezes_max
                       and not exists (select 1 from public.agenda_dono_avisos v
                                        where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
                       and (x.mostrada_vezes = 0
                            or (x.tipo = 'habilidade'
                                and ((x.veto_ate is not null and (x.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                                     or x.perda_em is not distinct from p_hoje))
                            or (x.tipo = 'tarefa' and x.chave not like 'tarefa:quem:%' and x.perda_em is not null and x.perda_em <= v_am1)));
      -- (7c: fim)
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
        -- (7c P5) as perguntas da equipe da 7b só com o portão da 7b (o bloco pode estar rodando só pela 7c)
        continue when not v_7c_7b;
        -- (7c: fim)
        -- (7c correção, achado 14) neste dia as da 7b esperam o dia delas (acima)
        continue when v_c14_pula;
        -- (7c: fim)
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
        -- (correção da revisão da 7b, achado 17) a chamada e a pergunta dos dias que vão só como "Também: … (responda em *agenda
        -- pendências*)" não contam como mostradas: o dono não leu a pergunta (a dos dias, com a sugestão de quem chamar, contava como vista
        -- e vencia na quinta seguinte sem ele a ter lido). Elas ficam com mostrada_vezes 0 (a linha segue com perda 75) e saem inteiras no
        -- fechamento em que vierem primeiro. O telefone e o contato vão com a pergunta toda na forma curta e contam.
        if jsonb_array_length(v_7b_ids) > 1 and (v_7b_q.tipo = 'dias_semana' or v_7b_q.chave like 'equipe_cadastro:chamada:%') then
          v_7b_ids := v_7b_ids - (jsonb_array_length(v_7b_ids) - 1);
        end if;
        -- (correção da revisão da 7b: fim)
        -- (correção 3) a forma curta (texto_curto, a que o Secretário cheio usa) leva o prazo de cada pergunta que vence e o
        -- "sigo assim": o registro não sabe qual das formas saiu e conta como vistas todas as pergunta_ids (agenda_fechamento_registrar),
        -- então a chamada vista só como "a equipe da agenda está certa?" ganhava o prazo de equipe_chamada_prazo_du dias úteis sem o dono
        -- ter lido o "sigo assim". A data é a que o vencimento grava: a chamada contada aqui (a 1ª da linha; a do "Também" não conta, achado
        -- 17), com o cadastro fora de desligado, vence em _agenda_veto_ate(o dia do registro, equipe_chamada_prazo_du) (a rodada da semana
        -- grava o veto_ate no tique seguinte; já gravado, o dele); a dos dias da semana, com modo_dias fora de desligado, vence no prazo da
        -- semana dela (o dia do plano em perda_em, hora_do_plano − equipe_dias_fechar_antes: o passo fechar de agenda_equipe_semana), vista
        -- ou não. O telefone e o contato não vencem: como antes. A forma longa não muda.
        v_c3_ate := case
          when v_7b_q.chave like 'equipe_cadastro:chamada:%' and cf.modo_cadastro <> 'desligado' and v_7b_ids ? v_7b_q.id::text
            then coalesce(v_7b_q.veto_ate,
                          public._agenda_veto_ate(p_hoje::timestamp at time zone 'America/Sao_Paulo', cf.equipe_chamada_prazo_du))
          when v_7b_q.tipo = 'dias_semana' and cf.modo_dias <> 'desligado' and v_7b_q.perda_em is not null
            then ((v_7b_q.perda_em + cf.hora_do_plano) - cf.equipe_dias_fechar_antes) at time zone 'America/Sao_Paulo' end;
        if v_c3_ate is not null then
          v_7b_curto := v_7b_curto || format(' — sem resposta até %s às %s, sigo assim',
                                             public._dia_curto((v_c3_ate at time zone 'America/Sao_Paulo')::date),
                                             to_char(v_c3_ate at time zone 'America/Sao_Paulo', 'HH24:MI'));
        end if;
        -- (correção 3: fim)
        v_7b_curtos := v_7b_curtos || v_7b_curto;
        -- (correção da revisão da 7b, achado 7) a chamada da 7a (sem opções) é do gestor que marca, também com o cadastro da 7b
        -- em teste: a de antes, já aberta e ligada, não vira teste (o dono deixava de vê-la)
        if v_7b_q.chave like 'equipe_cadastro:chamada:%' and cf.modo_cadastro <> 'ligado'
           and not exists (select 1 from public.agenda_perguntas p where p.id = v_7b_q.id and jsonb_array_length(p.opcoes) > 0) then
          v_7b_q.modo_agora := public._agenda_gestor_modo('marcar');
        end if;
        -- (correção da revisão da 7b: fim)
        v_7b_lig := v_7b_lig and v_7b_q.modo_agora = 'ligado';
        v_7b_perde := v_7b_perde or v_7b_q.mostrada_vezes = 0
                      or (v_7b_q.veto_ate is not null and (v_7b_q.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                      or v_7b_q.perda_em is not distinct from p_hoje;
      end loop;
      -- (7c P5, R5.4 item 4, R5.1-6, R5.10-7) as perguntas de quem faz o quê (habilidade), depois das da 7b: primeiro a da equipe
      -- (habilidade:equipe:…), depois as de OS (habilidade:os:…), e a mais antiga; só com o portão da 7c. A 1ª da linha vai inteira; as
      -- outras curtas, até c_max_perg ("Também: quem faz o quê (marquei: Alex instala sozinho; responda em *agenda pendências*)."; a de
      -- OS: "Também: Caio (OS-97173): falta quem comissiona Victron em todos os dias; quem pode? (responda em *agenda pendências*).").
      -- A da equipe que vai só como "Também" não conta como mostrada (sai de pergunta_ids: o achado 17 da 7b estendido) e sai inteira no
      -- fechamento em que vier primeiro; a de OS conta (vai com a pergunta toda, como o telefone e o contato). Na forma curta
      -- (texto_curto, a que o Secretário cheio usa — o registro não sabe qual forma saiu), a da equipe leva o que foi marcado e, quando é
      -- contada e vence (modo ligado), o prazo: "quem faz o quê — marquei: Alex instala sozinho; sem resposta até qua 04/11 às 18:00,
      -- fica assim" (a data que _agenda_habilidade_vetos grava depois do registro: o veto_ate, ou _agenda_veto_ate do dia de hoje). O
      -- modo de cada uma é o de _agenda_modo_da_pergunta (a da equipe: modo_habilidade_propor; a de OS: modo_habilidade), que a linha não
      -- pode chamar (é só do service_role; a linha é lida pelo painel). A perda é a da (n): 75 enquanto alguma nunca foi vista inteira ou
      -- perde hoje.
      if v_7c_on then
        for v_7c_q in
          select x.id, x.tipo, x.chave, x.texto, x.modo, x.mostrada_vezes, x.veto_ate, x.perda_em,
                 coalesce(public._agenda_rotulo_da_os(x.service_order_id), '') as nome,
                 case when x.chave like 'habilidade:os:%' then cf.modo_habilidade else cf.modo_habilidade_propor end as modo_agora
            from public.agenda_perguntas x
           where x.estado = 'aberta' and x.modo = m and not x.critica and x.tipo = 'habilidade'
             and x.mostrada_vezes < cf.perguntas_vezes_max
             and not exists (select 1 from public.agenda_dono_avisos v
                              where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
           order by case when x.chave like 'habilidade:equipe:%' then 1 else 2 end, x.criada_em, x.id
        loop
          v_7c_eq := v_7c_q.chave like 'habilidade:equipe:%';
          -- o que foi marcado (as propostas vivas da pergunta, lidas sob a RLS de agenda_etiquetas) e o que a OS pede
          v_7c_marc := case when v_7c_eq then nullif(public._agenda_lista(array(
                         select public._agenda_nome_curto(py.name) || ' ' || split_part(public._agenda_etiqueta_texto(e.etiqueta, e.nivel), ':', 1)
                           from public.agenda_etiquetas e join public.payees py on py.id = e.payee_id
                          where e.pergunta_id = v_7c_q.id and e.estado = 'proposta'
                          order by case e.etiqueta when 'instala' then 0 when 'ajudante' then 1 else 2 end, e.nivel desc,
                                   public._agenda_nome_curto(py.name), e.id), null), '') end;
          v_7c_exig := case when not v_7c_eq then substring(v_7c_q.texto from ': o serviço pede (.*), e nas próximas ') end;
          v_7b_curto := case when v_7c_eq then 'quem faz o quê' || coalesce(' — marquei: ' || v_7c_marc, '')
                             else format('%s: falta %s', v_7c_q.nome, coalesce(v_7c_exig, 'quem o serviço pede')) end;
          if v_7b_txt is null then
            v_7b_txt := 'Agenda: ' || v_7c_q.texto;
          else
            if v_7b_rest > 0 then
              v_7b_rest := v_7b_rest + 1;
              continue;
            end if;
            v_7b_item := case
              when v_7c_eq then format('Também: quem faz o quê (%sresponda em *agenda pendências*).',
                                       coalesce('marquei: ' || v_7c_marc || '; ', ''))
              else format('Também: %s: falta %s; quem pode? (responda em *agenda pendências*).', v_7c_q.nome,
                          coalesce(v_7c_exig, 'quem o serviço pede')) end;
            -- (7c correção 2, achado 11) a de quem faz o quê da equipe, ligada (a pergunta e o modo dela), que vai como "Também" atrás de
            -- uma pergunta da 7b que perde hoje leva o que foi marcado E o prazo — o mesmo que a forma curta dela, que já contava como
            -- vista — e conta (abaixo). Antes, só como "Também: quem faz o quê (marquei: …; responda em *agenda pendências*)." ela nunca
            -- contava: na semana real a chamada (no dia do prazo) e depois o telefone do Alex iam primeiro, e o prazo nunca começava. Em
            -- teste, a de antes.
            v_c11_tambem := v_7c_eq and m = 'ligado' and v_7c_q.modo = 'ligado' and v_7c_q.modo_agora = 'ligado';
            if v_c11_tambem then
              v_7c_ate := coalesce(v_7c_q.veto_ate, public._agenda_veto_ate(p_hoje::timestamp at time zone 'America/Sao_Paulo'));
              v_7b_item := format('Também: quem faz o quê (%ssem resposta até %s às %s, fica assim; responda em *agenda pendências*).',
                                  coalesce('marquei: ' || v_7c_marc || '; ', ''),
                                  public._dia_curto((v_7c_ate at time zone 'America/Sao_Paulo')::date),
                                  to_char(v_7c_ate at time zone 'America/Sao_Paulo', 'HH24:MI'));
            end if;
            -- (7c: fim)
            if char_length(array_to_string(array[v_7b_txt] || v_7b_itens || v_7b_item, ' ')) > c_max_perg - 32 then
              v_7b_rest := 1;
              continue;
            end if;
            v_7b_itens := v_7b_itens || v_7b_item;
          end if;
          v_7b_ids := v_7b_ids || to_jsonb(v_7c_q.id);
          if jsonb_array_length(v_7b_ids) > 1 and v_7c_eq then
            v_7b_ids := v_7b_ids - (jsonb_array_length(v_7b_ids) - 1);
          end if;
          -- (7c correção 2, achado 11) e a "Também" com o prazo conta: volta a pergunta_ids (o achado 17 da 7b a tirava)
          if v_c11_tambem and not v_7b_ids ? v_7c_q.id::text then
            v_7b_ids := v_7b_ids || to_jsonb(v_7c_q.id);
          end if;
          v_c11_tambem := false;
          -- (7c: fim)
          if v_7c_eq and v_7c_q.modo = 'ligado' and v_7b_ids ? v_7c_q.id::text then
            v_7c_ate := coalesce(v_7c_q.veto_ate, public._agenda_veto_ate(p_hoje::timestamp at time zone 'America/Sao_Paulo'));
            v_7b_curto := v_7b_curto || format('; sem resposta até %s às %s, fica assim',
                                               public._dia_curto((v_7c_ate at time zone 'America/Sao_Paulo')::date),
                                               to_char(v_7c_ate at time zone 'America/Sao_Paulo', 'HH24:MI'));
          end if;
          v_7b_curtos := v_7b_curtos || v_7b_curto;
          v_7b_lig := v_7b_lig and v_7c_q.modo_agora = 'ligado';
          v_7b_perde := v_7b_perde or v_7c_q.mostrada_vezes = 0
                        or (v_7c_q.veto_ate is not null and (v_7c_q.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                        or v_7c_q.perda_em is not distinct from p_hoje;
        end loop;
      end if;
      -- (7c: fim)
      -- (7c P8, R5.4 item 4, R5.2-2(c)) as perguntas das etapas (tarefa), depois das de quem faz o quê: primeiro a de quem faça a etapa de
      -- risco (tarefa:quem:<os>), depois a de prazo (tarefa:prazo:<os>), e a mais antiga; só com o portão das etapas. A 1ª da linha vai
      -- inteira; as outras curtas, até c_max_perg ("Também: Lenine: quem vai junto em "…"? (responda em *agenda pendências*)."). As duas
      -- contam como mostradas (vão com a pergunta toda, como a de OS de quem faz o quê). O modo é o de _agenda_modo_da_pergunta
      -- (modo_tarefas), que a linha não pode chamar. A de prazo cujo prazo (perda_em) é hoje ou o próximo dia útil perde hoje.
      if v_p8_on then
        for v_p8_q in
          select x.id, x.chave, x.texto, x.mostrada_vezes, x.perda_em,
                 coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                             join public.clients cl on cl.id = so.client_id where so.id = x.service_order_id),
                          public._agenda_rotulo_da_os(x.service_order_id), '') as cli
            from public.agenda_perguntas x
           where x.estado = 'aberta' and x.modo = m and not x.critica and x.tipo = 'tarefa'
             and x.mostrada_vezes < cf.perguntas_vezes_max
             and not exists (select 1 from public.agenda_dono_avisos v
                              where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
           order by case when x.chave like 'tarefa:quem:%' then 1 else 2 end, x.criada_em, x.id
        loop
          v_p8_quem := v_p8_q.chave like 'tarefa:quem:%';
          v_7b_curto := case when v_p8_quem then format('%s: quem vai junto%s?', v_p8_q.cli,
                                                         coalesce(' em ' || substring(v_p8_q.texto from '"[^"]+"'), ''))
                             else format('%s: as etapas não cabem até %s', v_p8_q.cli, public._dia_curto(v_p8_q.perda_em)) end;
          if v_7b_txt is null then
            v_7b_txt := 'Agenda: ' || v_p8_q.texto;
          else
            if v_7b_rest > 0 then
              v_7b_rest := v_7b_rest + 1;
              continue;
            end if;
            v_7b_item := format('Também: %s (responda em *agenda pendências*).', v_7b_curto);
            if char_length(array_to_string(array[v_7b_txt] || v_7b_itens || v_7b_item, ' ')) > c_max_perg - 32 then
              v_7b_rest := 1;
              continue;
            end if;
            v_7b_itens := v_7b_itens || v_7b_item;
          end if;
          v_7b_ids := v_7b_ids || to_jsonb(v_p8_q.id);
          v_7b_curtos := v_7b_curtos || v_7b_curto;
          v_7b_lig := v_7b_lig and cf.modo_tarefas = 'ligado';
          v_7b_perde := v_7b_perde or v_p8_q.mostrada_vezes = 0
                        or (not v_p8_quem and v_p8_q.perda_em is not null and v_p8_q.perda_em <= v_am1);
        end loop;
      end if;
      -- (7c: fim)
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
  -- FASE 7c: (7c P5, R5.10-8) o portão da 7b volta a ser só o dela: a (e) exclui as perguntas da 7b só com ele (e as de quem faz o quê
  -- só com o da 7c, abaixo)
  v_7b_on := v_7c_7b;
  -- FASE 7c: fim
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
       -- FASE 7c: (7c P5, R5.4 item 4) nem as perguntas de quem faz o quê com a 7c fora de desligado: elas vão na linha (n), acima
       and not (v_7c_on and x.tipo = 'habilidade')
       -- FASE 7c: fim
       -- FASE 7c: (7c P8, R5.4 item 4) nem as perguntas das etapas com o modo_tarefas fora de desligado: elas vão na linha (n), acima
       and not (v_p8_on and x.tipo = 'tarefa')
       -- FASE 7c: fim
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
       -- FASE 7c: (7c P5, R5.4 item 4) nem as perguntas de quem faz o quê com a 7c fora de desligado: elas vão na linha (n), acima
       and not (v_7c_on and x.tipo = 'habilidade')
       -- FASE 7c: fim
       -- FASE 7c: (7c P8, R5.4 item 4) nem as perguntas das etapas com o modo_tarefas fora de desligado: elas vão na linha (n), acima
       and not (v_p8_on and x.tipo = 'tarefa')
       -- FASE 7c: fim
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
    -- FASE 7d: (7d P5, R6.7c-3) a combinar que perde em até 2 dias úteis sobe a 75: sem isso ela cai atrás de tudo no corte por perda do Secretário
    -- (vagas = maxManha − as que ficaram + as garantidas), e reserva_marina, descida e entrada não têm rede em D-1. Uma linha só, e os 75 dão a vaga
    -- garantida (agenda_textos_do_fechamento). A local fica em 30: nada espera por ela.
    if q.tipo = 'combinar' and q.perda_em <= v_am2 then
      v_out := jsonb_set(v_out, array[(jsonb_array_length(v_out) - 1)::text, 'perda'], to_jsonb(75));
    end if;
    -- FASE 7d: fim
  end loop;

  -- FASE 7c: (7c P8, R5.2-2(b), R5.10-6, -10, -13) (o) as etapas de quem não recebe pelo WhatsApp (sem telefone pela régua da 7a,
  -- _agenda_equipe_tem_telefone — a mesma do registro —, ou fora da lista da rotina) com etapa no plano de hoje ou do próximo dia útil: o
  -- que hoje devia ficar pronto (o dono passa e confere) e o que fazer amanhã, sem números (as listas do dia e a da OS numeram
  -- diferente), até c_max, cortando por etapa inteira ("e mais N"); o texto_curto para o Secretário cheio. Perda 75 só quando amanhã é
  -- o último dia de uma OS (a cobrança da véspera) ou volta primeiro uma pendente dita; senão 70 (a etapa de risco sozinha não sobe a
  -- perda). Tipo dia, sem pergunta: nada vence por ela. Em teste, modo sombra e "Em teste: " (vai ao detalhe, nunca ao texto do dono).
  -- Só com a porta das etapas aberta (o administrador ou o financeiro logado, ou sem login).
  if cf.modo_tarefas <> 'desligado' and (auth.uid() is null or public.is_admin_or_financial(auth.uid())) then
    for v_p8_pess in
      select x.payee_id, x.nome, public._agenda_equipe_tem_telefone(x.payee_id) as fone,
             exists (select 1 from public.agenda_equipe_contato c
                      where c.payee_id = x.payee_id and c.recebe_rotina and c.parou_em is null) as rotina
        from (select distinct a.payee_id, public._agenda_nome_curto(py.name) as nome
                from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
               where a.dia in (p_hoje, v_am1) and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno'
                 and a.payee_id is distinct from public._agenda_dono(null)) x
       order by x.nome, x.payee_id
    loop
      continue when v_p8_pess.fone and v_p8_pess.rotina;
      v_p8_h := public._agenda_tarefas_da_pessoa(v_p8_pess.payee_id, p_hoje, p_hoje);
      v_p8_a := public._agenda_tarefas_da_pessoa(v_p8_pess.payee_id, v_am1, p_hoje);
      -- hoje: o que terminava e ainda não tem resultado (uma vez por etapa)
      v_p8_hi := coalesce((select jsonb_agg(i order by (i ->> 'n')::int) from jsonb_array_elements(v_p8_h -> 'itens') i
                            where (i ->> 'termina')::boolean and i -> 'resultado' = 'null'::jsonb
                              and not exists (select 1 from jsonb_array_elements(v_p8_hoje) j where j ->> 'tarefa' = i ->> 'tarefa')),
                           '[]'::jsonb);
      -- amanhã: o que a pessoa faz, por OS, com o último dia e a pendente dita que volta primeiro
      v_p8_ai := coalesce((select jsonb_agg(i || jsonb_build_object('nome', v_p8_pess.nome, 'payee', v_p8_pess.payee_id,
                                  'com', case when (i ->> 'com_dono')::boolean then 'você' end,
                                  'ultimo', (v_p8_a -> 'ultimo_dia') @> jsonb_build_array(jsonb_build_object('os', i ->> 'os')),
                                  'pdita', exists (select 1 from public.os_tarefas t where t.id = (i ->> 'tarefa')::uuid
                                                      and t.estado = 'viva' and t.pendente_vezes > 0))
                                order by (i ->> 'n')::int)
                           from jsonb_array_elements(v_p8_a -> 'itens') i), '[]'::jsonb);
      -- só quem tem o que conferir hoje ou o que fazer amanhã entra no "Etapas (… não tem telefone …)"
      continue when jsonb_array_length(v_p8_hi) = 0 and jsonb_array_length(v_p8_ai) = 0;
      v_p8_nomes := v_p8_nomes || v_p8_pess.nome;
      v_p8_nfone := coalesce(v_p8_nfone, 0) + case when v_p8_pess.fone then 0 else 1 end;
      v_p8_nrot := coalesce(v_p8_nrot, 0) + case when v_p8_pess.rotina then 0 else 1 end;
      v_p8_hoje := v_p8_hoje || v_p8_hi;
      v_p8_amanha := v_p8_amanha || v_p8_ai;
    end loop;
    -- (7c correção 2, achado 13) o dia útil de amanhã é dia de revisão (o 1º dia útil da semana ou do mês: a tarde do Secretário é a
    -- revisão, sem as linhas da agenda) — a véspera do último dia que cai no dia útil seguinte a ele nunca chegava ao dono (a OS que
    -- termina na terça; o dia útil depois de um feriado na segunda). A linha de hoje já cobra esse último dia, de quem trabalha amanhã;
    -- até 2 dias de revisão seguidos (a do mês e a da semana).
    v_c13_d := v_am1;
    for v_c13_k in 1 .. 2 loop
      -- (7d P5, R6.12) o remendo do achado 13 sai: com 62d1fd95 as linhas saem nos dias de revisão, e a (o) já cobra a véspera do último dia no próprio dia.
      -- Com o exit, v_c13_av fica [] e tudo o que dependia dele vira o caminho sem remendo. A parte do achado 15 fica (usa v_am1). A remoção física é da 7f.
      exit;
      -- (7d: fim)
        select exists (
          with s as (
            select w.x, (select min(make_date(extract(year from w.x)::int, extract(month from w.x)::int, 1) + c13n)
                           from generate_series(0, 9) c13n
                          where extract(isodow from make_date(extract(year from w.x)::int, extract(month from w.x)::int, 1) + c13n) between 1 and 5
                            and public.agenda_feriado(make_date(extract(year from w.x)::int, extract(month from w.x)::int, 1) + c13n) is null) as rm
              from (select v_c13_d - (extract(isodow from v_c13_d)::int - 1) + c13n as x from generate_series(0, 4) c13n) w
          )
          select 1 where extract(isodow from v_c13_d) between 1 and 5 and public.agenda_feriado(v_c13_d) is null
            and (v_c13_d = (select s.rm from s where s.x = v_c13_d)
                 or v_c13_d = (select min(s.x) from s where extract(isodow from s.x) between 1 and 5 and public.agenda_feriado(s.x) is null
                                                  and s.x <> s.rm))) into v_c13_rev;
      exit when not v_c13_rev;
      v_c13_prox := public.agenda_somar_du(v_c13_d, 1);
      for v_c13_p in select distinct i ->> 'payee' as payee, i ->> 'nome' as nome from jsonb_array_elements(v_p8_amanha) i order by 2, 1 loop
        v_c13_u := public._agenda_tarefas_da_pessoa((v_c13_p.payee)::uuid, v_c13_prox, p_hoje) -> 'ultimo_dia';
        v_c13_av := v_c13_av || coalesce((select jsonb_agg(jsonb_build_object('dia', v_c13_prox, 'rev', v_c13_d, 'nome', v_c13_p.nome,
                                                                              'cliente', u ->> 'cliente', 'os', u ->> 'os') order by o)
                                            from jsonb_array_elements(coalesce(v_c13_u, '[]'::jsonb)) with ordinality t(u, o)), '[]'::jsonb);
      end loop;
      v_c13_d := v_c13_prox;
    end loop;
    -- (7c: fim)
    if jsonb_array_length(v_p8_hoje) > 0 or jsonb_array_length(v_p8_amanha) > 0 then
      v_p8_dia := case when v_am1 = p_hoje + 1 then 'Amanhã (' || public._dia_curto(v_am1) || ')'
                       else public._agenda_maiuscula(public._dia_curto(v_am1)) end;
      -- monta com até v_p8_k etapas por lista; corta por etapa inteira até caber em c_max
      v_p8_k := 5;
      loop
        v_p8_txt := format('Etapas (%s %s: quem passa e confere é você).', public._agenda_lista(v_p8_nomes, null),
                           case when v_p8_nfone = cardinality(v_p8_nomes)
                                  then case when cardinality(v_p8_nomes) = 1 then 'não tem telefone' else 'não têm telefone' end
                                when v_p8_nrot = cardinality(v_p8_nomes)
                                  then case when cardinality(v_p8_nomes) = 1 then 'não está na rotina da equipe' else 'não estão na rotina da equipe' end
                                else 'não recebem pelo WhatsApp' end);
        for v_p8_g in select i ->> 'cliente' as cli, min((i ->> 'n')::int) as o,
                             jsonb_agg(i order by (i ->> 'n')::int) as its
                        from jsonb_array_elements(v_p8_hoje) i group by i ->> 'cliente' order by 2 loop
          v_p8_txt := v_p8_txt || format(' Hoje no %s devia ficar pronto: %s.', v_p8_g.cli,
                                         public._agenda_tarefas_lista_texto(v_p8_g.its, v_p8_k, null, false, false));
        end loop;
        if jsonb_array_length(v_p8_hoje) > 0 then
          v_p8_txt := v_p8_txt || format(' Se faltou alguma, me diga qual (ex.: no %s falta "%s").', v_p8_hoje -> 0 ->> 'cliente',
                                         lower(left(v_p8_hoje -> 0 ->> 'texto', 1)) || substr(v_p8_hoje -> 0 ->> 'texto', 2));
        end if;
        for v_p8_g in select i ->> 'nome' as nome, i ->> 'cliente' as cli, min((i ->> 'n')::int) as o,
                             bool_or((i ->> 'ultimo')::boolean) as ult, jsonb_agg(i order by (i ->> 'n')::int) as its
                        from jsonb_array_elements(v_p8_amanha) i group by i ->> 'nome', i ->> 'payee', i ->> 'cliente'
                       order by i ->> 'nome', 3 loop
          v_p8_txt := v_p8_txt || format(' %s, %s no %s: %s.', v_p8_dia, v_p8_g.nome, v_p8_g.cli,
                                         public._agenda_tarefas_lista_texto(v_p8_g.its, v_p8_k, null, true, false))
                      || case when v_p8_g.ult then ' É o último dia: tem que ficar tudo pronto.' else '' end;
        end loop;
        -- (7c correção 2, achado 13) a cobrança do último dia depois do dia de revisão, sempre inteira: com o porquê, quando cabe; sem
        -- ele, quando não ("Qui 05/11 é o último dia do Lenine (Alex): tem que ficar tudo pronto."); o que não cabe sai das listas (o k)
        for v_c13_p in select a ->> 'dia' as dia, a ->> 'rev' as rev, a ->> 'nome' as nome, a ->> 'cliente' as cli
                         from jsonb_array_elements(v_c13_av) with ordinality t(a, o) order by o loop
          v_c13_q := format(' %s é o último dia do %s (%s): tem que ficar tudo pronto — aviso hoje porque %s é dia de revisão.',
                            public._agenda_maiuscula(public._dia_curto(v_c13_p.dia::date)), v_c13_p.cli, v_c13_p.nome,
                            public._dia_curto(v_c13_p.rev::date));
          if char_length(v_p8_txt || v_c13_q) + (case when cf.modo_tarefas = 'ligado' then 0 else 10 end) > c_max then
            v_c13_q := format(' %s é o último dia do %s (%s): tem que ficar tudo pronto.',
                              public._agenda_maiuscula(public._dia_curto(v_c13_p.dia::date)), v_c13_p.cli, v_c13_p.nome);
          end if;
          v_p8_txt := v_p8_txt || v_c13_q;
        end loop;
        -- (7c: fim)
        v_p8_txt := case when cf.modo_tarefas = 'ligado' then '' else 'Em teste: ' end || v_p8_txt;
        exit when char_length(v_p8_txt) <= c_max or v_p8_k = 1;
        v_p8_k := v_p8_k - 1;
      end loop;
      v_p8_txt := public._agenda_corta(v_p8_txt, c_max);
      -- a forma curta (o Secretário cheio)
      v_p8_parte := array(select case when bool_or((i ->> 'ultimo')::boolean)
                                      then format('amanhã é o último dia do %s (%s, %s)', i ->> 'cliente', i ->> 'nome',
                                                  public._agenda_plural(count(*)::int, 'etapa', 'etapas'))
                                      else format('amanhã, %s no %s (%s)', i ->> 'nome', i ->> 'cliente',
                                                  public._agenda_plural(count(*)::int, 'etapa', 'etapas')) end
                            from jsonb_array_elements(v_p8_amanha) i group by i ->> 'nome', i ->> 'payee', i ->> 'cliente'
                           order by i ->> 'nome', min((i ->> 'n')::int))
                  || case when jsonb_array_length(v_p8_hoje) > 0
                          then array[format('hoje, %s para conferir', jsonb_array_length(v_p8_hoje))] else '{}'::text[] end;
      v_p8_curto := case when cf.modo_tarefas = 'ligado' then '' else 'Em teste: ' end
                    || 'Etapas: ' || array_to_string(v_p8_parte, '; ') || '.'
                    || case when jsonb_array_length(v_p8_amanha) > 0
                            then format(' Pergunte o que o %s faz amanhã.', v_p8_amanha -> 0 ->> 'nome') else '' end;
      v_p8_alta := exists (select 1 from jsonb_array_elements(v_p8_amanha) i where (i ->> 'ultimo')::boolean or (i ->> 'pdita')::boolean);
      -- (7c correção 2, achados 15 e 13) a forma curta com o dia quando o próximo dia útil não é amanhã (a sexta, a véspera de feriado:
      -- "seg 09/11 é o último dia do Lenine (Alex, 2 etapas). Pergunte o que o Alex faz na seg 09/11." — antes, "amanhã", e o "o que o
      -- Alex faz amanhã?" respondia pelo sábado) e com o último dia depois do dia de revisão; o último dia (o de amanhã ou o depois da
      -- revisão) marca a linha para subir com as outras de 75 (no fim). Sem nada disso, a de antes.
      if v_am1 <> p_hoje + 1 or jsonb_array_length(v_c13_av) > 0 then
        v_c13_q := case when v_am1 = p_hoje + 1 then 'amanhã' else public._dia_curto(v_am1) end;
        v_c13_parte := array(select case when bool_or((i ->> 'ultimo')::boolean)
                                         then format('%s é o último dia do %s (%s, %s)', v_c13_q, i ->> 'cliente', i ->> 'nome',
                                                     public._agenda_plural(count(*)::int, 'etapa', 'etapas'))
                                         else format('%s, %s no %s (%s)', v_c13_q, i ->> 'nome', i ->> 'cliente',
                                                     public._agenda_plural(count(*)::int, 'etapa', 'etapas')) end
                               from jsonb_array_elements(v_p8_amanha) i group by i ->> 'nome', i ->> 'payee', i ->> 'cliente'
                              order by i ->> 'nome', min((i ->> 'n')::int))
                       || array(select format('%s é o último dia do %s (%s)', public._dia_curto((a ->> 'dia')::date), a ->> 'cliente',
                                              a ->> 'nome')
                                  from jsonb_array_elements(v_c13_av) with ordinality t(a, o) order by o)
                       || case when jsonb_array_length(v_p8_hoje) > 0
                               then array[format('hoje, %s para conferir', jsonb_array_length(v_p8_hoje))] else '{}'::text[] end;
        v_p8_curto := case when cf.modo_tarefas = 'ligado' then '' else 'Em teste: ' end
                      || 'Etapas: ' || array_to_string(v_c13_parte, '; ') || '.'
                      || case when jsonb_array_length(v_p8_amanha) > 0
                              then format(' Pergunte o que o %s faz %s.', v_p8_amanha -> 0 ->> 'nome',
                                          case when v_am1 = p_hoje + 1 then 'amanhã' else 'na ' || public._dia_curto(v_am1) end)
                              else '' end;
      end if;
      v_p8_alta := v_p8_alta or jsonb_array_length(v_c13_av) > 0;
      v_c13_ult := cf.modo_tarefas = 'ligado'
                   and (jsonb_array_length(v_c13_av) > 0
                        or exists (select 1 from jsonb_array_elements(v_p8_amanha) i where (i ->> 'ultimo')::boolean));
      -- (7c: fim)
      v_out := v_out || (jsonb_build_object('tipo', 'dia', 'texto', v_p8_txt, 'perda', case when v_p8_alta then 75 else 70 end,
        'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', case when cf.modo_tarefas = 'ligado' then 'ligado' else 'sombra' end)
        || case when char_length(v_p8_curto) < char_length(v_p8_txt) then jsonb_build_object('texto_curto', v_p8_curto)
                else '{}'::jsonb end);
    end if;
  end if;
  -- FASE 7c: fim
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
  -- FASE 7c: (7c correção, achados 8 e 2) o fechamento cheio com uma linha da 7c ligada que perde hoje (a (o) "Etapas" ou a (n) com
  -- uma pergunta de quem faz o quê ou das etapas). O Secretário (textoDaTarde) encolhe só as linhas que têm forma curta antes de tirar
  -- uma, e a do cliente (75, a mensagem que espera *manda cliente*, até 600 letras) não tinha: com ela, a (o) e a (n) caíam (a semana
  -- real da revisão, 5 fechamentos com uma linha de cliente). Sem a 7c ligada (desligada ou em teste), a de antes, byte a byte.
  if exists (select 1 from jsonb_array_elements(v_out) x
              where x ->> 'modo' = 'ligado' and (x ->> 'perda')::int >= 75
                and ((x ->> 'tipo' = 'dia' and x ->> 'texto' like 'Etapas%')
                     or exists (select 1 from jsonb_array_elements_text(coalesce(x -> 'pergunta_ids', '[]'::jsonb)) u(id)
                                  join public.agenda_perguntas qq on qq.id = u.id::uuid
                                 where qq.tipo in ('habilidade', 'tarefa')))) then
    -- (8) a mensagem ao cliente ganha a forma curta (a coleta só a usa no fechamento enxuto, com linha garantida prestes a sair): quem,
    -- o tipo, quando sai e a palavra — "Mensagem para Vera (véspera, com a pergunta do acesso) espera *manda cliente Vera* (sai ter
    -- 10/11 às 09:00); *agenda clientes* mostra." — com a mesma 1ª mensagem de _agenda_cliente_fechamento
    if cf.modo_cliente = 'ligado' then
      v_c8_agora := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
      select m2.tipo, m2.enviar_em, q2.id,
             public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)), count(*) over ()
        into v_c8_tipo, v_c8_env, v_c8_qid, v_c8_nome, v_c8_n
        from public.agenda_cliente_mensagens m2
        join public.agenda_perguntas q2 on q2.id = m2.pergunta_id
        join public.clients cl on cl.id = m2.client_id
       where m2.modo = 'ligado' and m2.estado = 'aguardando_dono' and m2.aprovacao = 'pedida'
         and q2.tipo = 'cliente_aprovar' and q2.estado = 'aberta'
         and (m2.enviar_em at time zone 'America/Sao_Paulo')::date <= public._agenda_cliente_dia_seguinte(p_hoje)
       order by m2.enviar_em, cl.name, m2.tipo, m2.id
       limit 1;
      if v_c8_qid is not null then
        v_c8_curto := case when v_c8_n > 1
          then format('Mensagem para %s (%s) e mais %s esperam *manda cliente* (a 1ª sai %s); *agenda clientes* mostra.', v_c8_nome,
                      public._agenda_cliente_tipo_texto(v_c8_tipo), v_c8_n - 1, public._agenda_cliente_quando_texto(v_c8_env, v_c8_agora))
          else format('Mensagem para %s (%s) espera *manda cliente %s* (sai %s); *agenda clientes* mostra.', v_c8_nome,
                      public._agenda_cliente_tipo_texto(v_c8_tipo), v_c8_nome, public._agenda_cliente_quando_texto(v_c8_env, v_c8_agora)) end;
        v_out := (select coalesce(jsonb_agg(case when x ->> 'tipo' = 'cliente' and (x ->> 'perda')::int = 75
                                                  and x ->> 'pergunta_id' = v_c8_qid::text and not x ? 'texto_curto'
                                                  and char_length(v_c8_curto) < char_length(x ->> 'texto')
                                             then x || jsonb_build_object('texto_curto', v_c8_curto) else x end order by o), '[]'::jsonb)
                    from jsonb_array_elements(v_out) with ordinality t(x, o));
      end if;
    end if;
    -- (2) a (n) com uma pergunta de quem faz o quê ou das etapas, ligada, contada na linha e nunca vista há c_c2_dias dias úteis (ela
    -- perdeu c_c2_dias fechamentos: com a compra (80) e as perguntas do gestor (76), as três não cabem nem na forma curta, e a de menor
    -- perda saía todo dia — o prazo nunca corria e a proposta nunca valia) sobe a c_c2_perda: neste dia sai a de menor perda das outras
    -- (a das perguntas do gestor, ou uma de 75), uma vez, e no dia seguinte, vista, ela volta à de sempre. Não sobe se a linha que ela
    -- tiraria (perda 76 a 79) perde algo hoje: a ficha de amanhã (ficha_estimativa) ou um prazo (veto ou perda) de hoje.
    if not exists (select 1 from jsonb_array_elements(v_out) x
                    where x ->> 'modo' = 'ligado' and (x ->> 'perda')::int between 76 and 79
                      and exists (select 1 from jsonb_array_elements_text(coalesce(x -> 'pergunta_ids', '[]'::jsonb)) u(id)
                                    join public.agenda_perguntas qq on qq.id = u.id::uuid
                                   where qq.tipo = 'ficha_estimativa'
                                      or (qq.veto_ate is not null and (qq.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                                      or qq.perda_em is not distinct from p_hoje)) then
      v_out := (select coalesce(jsonb_agg(case when x ->> 'modo' = 'ligado' and x ->> 'tipo' = 'pergunta' and (x ->> 'perda')::int = 75
                                                and exists (select 1 from jsonb_array_elements_text(coalesce(x -> 'pergunta_ids', '[]'::jsonb)) u(id)
                                                              join public.agenda_perguntas qq on qq.id = u.id::uuid
                                                             where qq.tipo in ('habilidade', 'tarefa') and qq.modo = 'ligado'
                                                               and qq.estado = 'aberta' and qq.mostrada_vezes = 0
                                                               and public.agenda_du_entre((qq.criada_em at time zone 'America/Sao_Paulo')::date,
                                                                                          p_hoje) >= c_c2_dias)
                                           then jsonb_set(x, '{perda}', to_jsonb(c_c2_perda)) else x end order by o), '[]'::jsonb)
                  from jsonb_array_elements(v_out) with ordinality t(x, o));
    end if;
  end if;
  -- FASE 7c: fim
  -- FASE 7c: (7c correção 2, achados 1 e 13) quando uma linha da 7c ligada espera demais — a (n) com quem faz o quê nunca vista há
  -- c_c2_dias dias úteis (a 100580 a subiu a c_c2_perda, acima) ou a (o) "Etapas" da véspera do último dia (o de amanhã ou o depois
  -- de um dia de revisão) —, sobem a c_c2_perda TODAS as linhas ligadas de 75 (as que perdem hoje: a mensagem ao cliente que espera
  -- *manda cliente*, a (o), a (n)), na ordem de sempre entre elas. Quem sai no corte de 1.000 é a pergunta do gestor (76) que não perde
  -- hoje — ela espera um dia —, nunca a mensagem ao cliente (antes, só a (n) subia: com 4 linhas de 75 ou mais, saía o cliente, a de
  -- menor perda). Não sobe se uma linha de 76 a 79 perde algo hoje (a ficha de amanhã, um veto ou um prazo de hoje: a mesma guarda
  -- da 100580). Só com a pergunta do gestor de 76 para ceder; sem ela, nada passa à frente, e a (n) que a 100580 subiu volta a 75 (ela
  -- só tiraria o lugar de outra de 75). A vaga garantida não muda (75 e 77 contam igual). Sem a 7c ligada, nada disto acontece.
  if (exists (select 1 from jsonb_array_elements(v_out) x
               where x ->> 'modo' = 'ligado' and x ->> 'tipo' = 'pergunta' and (x ->> 'perda')::int = c_c2_perda)
      or (v_c13_ult
         and exists (select 1 from jsonb_array_elements(v_out) x
                      where x ->> 'modo' = 'ligado' and x ->> 'tipo' = 'dia' and x ->> 'texto' like 'Etapas%' and (x ->> 'perda')::int = 75)
         and not exists (select 1 from jsonb_array_elements(v_out) x
                          where x ->> 'modo' = 'ligado' and (x ->> 'perda')::int between 76 and 79
                          and exists (select 1 from jsonb_array_elements_text(coalesce(x -> 'pergunta_ids', '[]'::jsonb)) u(id)
                                        join public.agenda_perguntas qq on qq.id = u.id::uuid
                                       where qq.tipo = 'ficha_estimativa'
                                          or (qq.veto_ate is not null and (qq.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                                          or qq.perda_em is not distinct from p_hoje)
                         ))) then
    if exists (select 1 from jsonb_array_elements(v_out) x where x ->> 'modo' = 'ligado' and x ->> 'tipo' = 'pergunta' and (x ->> 'perda')::int = 76) then
      v_out := (select coalesce(jsonb_agg(case when x ->> 'modo' = 'ligado' and (x ->> 'perda')::int = 75
                                               then jsonb_set(x, '{perda}', to_jsonb(c_c2_perda)) else x end order by o), '[]'::jsonb)
                  from jsonb_array_elements(v_out) with ordinality t(x, o));
    else
      -- sem a de 76, a (n) que a 100580 subiu só passaria à frente das outras de 75 (a mensagem ao cliente): volta a 75
      v_out := (select coalesce(jsonb_agg(case when x ->> 'modo' = 'ligado' and x ->> 'tipo' = 'pergunta' and (x ->> 'perda')::int = c_c2_perda
                                               then jsonb_set(x, '{perda}', to_jsonb(75)) else x end order by o), '[]'::jsonb)
                  from jsonb_array_elements(v_out) with ordinality t(x, o));
    end if;
  end if;
  -- FASE 7c: fim
  return coalesce((select jsonb_agg(x order by (x ->> 'perda')::int desc, x ->> 'tipo', x ->> 'texto')
                     from jsonb_array_elements(v_out) x), '[]'::jsonb);
end;
$function$;

comment on function public._agenda_linhas_do_fechamento(date) is
  'Agenda de Produção (Fase 2, P5; Fase 3, P6): as linhas da agenda no fechamento das 17:30 — [{tipo (decisao|diaria|dia|ppc|semana|conclusao|mudancas|pergunta|comissao), texto, perda, pergunta_id, acao_ids, modo}] da maior perda para a menor (decisão 100/80/50 pela perda_em; dia 70; semana 60; ppc 55; diaria 50 ou 80 com 2 dias úteis sem resposta; conclusao 45; mudanças 40; pergunta 30; comissao 20). FASE 3: a linha dia conta o que a equipe confirmou, a diária que a agenda lançou ("*diária Roberto meia* corrige"), quem falta confirmar ("Foi isso para o João? *dia feito* lança a meia diária dele") e o último dia da OS (*concluiu <nome>*); sem nada disso, sai byte a byte a da Fase 2. diaria = a pergunta crítica da diária com as opções e as palavras (modo_diaria); conclusao = o que o gestor concluiu pela palavra do técnico, com o *desfaz* pelo número (modo_proposta); ppc = agenda_ppc().linha no último dia útil da semana com compromisso (modo_vigia); comissao = comissao_resumo_do_mes().linha no 1º dia útil do mês (modo_vigia). modo ligado só com o registro em ligado e o modo que o governa ligado agora; o resto sombra (o que diria; vai ao detalhe). O secretário mostra as ligadas que cabem nas vagas (REGRAS.maxManha − as que ficaram) e registra o que saiu (agenda_fechamento_registrar). FASE 5 (P5): cliente (só com modo_cliente ligado; _agenda_cliente_fechamento) — perda 75 com a mensagem que espera *manda cliente* e sai até o próximo dia de janela (a 1ª inteira, até 600 caracteres; acima disso o texto da mensagem é cortado em 300 e *agenda clientes* mostra inteira), perda 40 com o que sai sozinho amanhã e *segura cliente <nome>*. CORREÇÃO 29/10 (revisão): a pergunta de fato (e) não repete a que um aviso do gestor de hoje já levou ou está levando (agenda_dono_avisos enfileirada ou enviada): a pergunta sai uma vez por dia. FASE 7 (7a P7, spec §5.7 e §6.1): (i) com o gestor que marca em teste (_agenda_gestor_modo(''marcar'') = ''sombra''), a linha gestor — o "eu marcaria assim" do diário de hoje (agenda_gestor_dia.texto_sombra, ≤ 640: "Agenda em teste (nada mudou): eu marcaria assim — …"), perda 65, modo = o da vigia; (j) a linha compras — as compras da semana do diário de hoje (agenda_gestor_dia.compras [{texto, compre_ate, urgente}], que o P10 grava): perda 80 com compra urgente (AG7-07: vai como decisão), 65 com "compre até" hoje ou amanhã, 45 até compras_aviso_du dias úteis, modo = o do compre_ate; (k) a pergunta situacao/estimativa em que o dono já escolheu "eu digo os dias" (opcao_escolhida) não volta como linha pergunta (o prazo dela não vale mais). Sem o gestor em teste e sem compras, a saída de antes, byte a byte. FASE 7 (7a P11, spec §3.2 "Equipe" e §5.11): (l) a pergunta ficha_estimativa aberta de hoje (veto_ate hoje: a ficha das 19:30 de um dia pela estimativa, na janela de veto do ligar) numa linha própria, tipo pergunta, perda 75, com o pergunta_id (o fechamento que sai a conta como mostrada), uma por pessoa, modo = o da vigia; a linha (e) não a repete. Sem essa pergunta, a saída de antes, byte a byte. CORREÇÃO DA 7a (revisão da etapa): (achados 15 e 18) (m), no lugar da (l): as perguntas do gestor que esperam o dono — a ficha_estimativa de hoje, situacao, estimativa e reestimar — numa linha só, tipo pergunta: a 1ª (a ficha primeiro, depois a de prazo mais perto) com o texto inteiro, as outras curtas e agrupadas pelo prazo ("Também, sem resposta até ter 03/11 18:00: Nelson (OS-00112) 4 dias; …"; sem prazo: "Espero você: …"), até 600 caracteres, com pergunta_id (a 1ª) e pergunta_ids (todas as que a linha mostra: o fechamento que sai as conta como mostradas); perda 75 com alguma de prazo (ela perde no prazo), 30 sem; a linha (e) não as repete; (achado 14) a linha gestor de teste ("eu marcaria assim") vai com perda 25, abaixo de toda linha de verdade (só a comissão é menor); (achado 19) as compras com "compre até" hoje ou já vencido (comprando hoje ainda chega) vão como decisão, perda 80. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; os achados 15/18 de novo): a linha (m) das perguntas do gestor com prazo vai com perda 76 (ganha o desempate das que perdem hoje: antes perdia para a mensagem ao cliente pelo tipo e saía primeiro no corte de 1.000 do fechamento); as sem prazo dizem o porquê ("Espero você (não marco sozinho): Giancarlo (OS-00130)."); (o corte de 1.000) a linha (m) leva também texto_curto, com as MESMAS perguntas: a ficha sem as opções e cada uma pelo prazo e pelo que o gestor faz sem resposta ("Agenda: Sem resposta até ter 03/11 18:00, conto: Nelson (OS-00112) 4 dias; Flávio (OS-00104) 3,5 dias. Espero você (não marco sozinho): Giancarlo (OS-00130).") — o Secretário cheio a usa antes de tirar a linha. FASE 7b (P3, R4.2(d)): com modo_dias ou modo_cadastro fora de desligado, (n) a equipe — as perguntas abertas da equipe (a chamada equipe_cadastro:chamada, a dias_semana do dono, o telefone e o contato; não críticas, mostradas menos de perguntas_vezes_max vezes, fora as que um aviso de hoje levou) numa linha só, tipo pergunta, nesta ordem e depois a mais antiga: a 1ª com o texto inteiro, as outras curtas ("Também: o telefone do Alex (sem ele não mando a ficha)."; "Também: Mateus tem telefone; ponho na rotina? Responda 1 ou 2 em *agenda pendências*."; "Também: os dias da semana de 16/11 (responda em *agenda pendências*).") até 600 caracteres e o resto "(e mais N em *agenda equipe*)"; pergunta_id = a 1ª e pergunta_ids = todas as que a linha mostra (o fechamento que sai as conta como mostradas); perda 75 enquanto alguma nunca foi mostrada ou perde hoje (veto_ate ou perda_em de hoje), senão 30; modo ligado só com a pergunta em ligado e o modo dela ligado; texto_curto com as mesmas perguntas, só pelo nome ("Agenda, equipe: a equipe da agenda está certa?; o telefone do Alex. *agenda pendências* mostra."). A pergunta de fato (e) não as repete. Com os dois modos desligados, a saída de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achados 7 e 17): na linha (n) da equipe, a chamada e a pergunta dos dias que vão só como "Também: … (responda em *agenda pendências*)" ficam fora de pergunta_ids (não contam como mostradas; saem inteiras no fechamento em que vierem primeiro); a chamada da 7a (sem opções) usa o modo do gestor que marca, também com o cadastro da 7b em teste. CORREÇÃO 3 DA 7b (o R5.9 da spec da 7c; o R5.10-7): na linha (n) da equipe, a forma curta (texto_curto, a que o Secretário cheio usa, e o registro conta as pergunta_ids da linha sem saber qual forma saiu) leva, em cada pergunta que vence, o prazo e o "sigo assim" — "Agenda, equipe: a equipe da agenda está certa? — sem resposta até ter 10/11 às 18:00, sigo assim. *agenda pendências* mostra." —, com a data que o vencimento grava: a chamada contada na linha, com o cadastro fora de desligado, em _agenda_veto_ate(o dia do registro, equipe_chamada_prazo_du) (ou o veto_ate já gravado); a dos dias da semana, com modo_dias fora de desligado, no prazo da semana dela (perda_em, hora_do_plano − equipe_dias_fechar_antes). O telefone e o contato não vencem: como antes. A forma longa e o resto, byte a byte. FASE 7c (P5, R5.4 item 4, R5.1-6, R5.10-7/-8): o portão da linha (n) passa a "a 7b (modo_dias ou modo_cadastro) OU a 7c (modo_habilidade_propor ou modo_habilidade) fora de desligado"; dentro dela, as perguntas da 7b só com o portão da 7b e, depois delas, as de quem faz o quê (habilidade: primeiro a habilidade:equipe, depois as habilidade:os) só com o da 7c, com o modo de _agenda_modo_da_pergunta (a da equipe: modo_habilidade_propor; a de OS: modo_habilidade). A da equipe que vai só como "Também: quem faz o quê (marquei: Alex instala sozinho; responda em *agenda pendências*)." fica fora de pergunta_ids (não conta como vista); a de OS ("Também: Caio (OS-97173): falta quem comissiona Victron em todos os dias; quem pode? (responda em *agenda pendências*).") conta. A forma curta leva o que foi marcado e, na da equipe contada e ligada, o prazo: "quem faz o quê — marquei: Alex instala sozinho; sem resposta até qua 04/11 às 18:00, fica assim" (o veto_ate, ou _agenda_veto_ate do dia de hoje: a data que _agenda_habilidade_vetos grava depois do registro). A pergunta de fato (e) exclui as da 7b só com o portão da 7b e as de quem faz o quê só com o da 7c. Com os modos da 7c desligados, a saída de antes, byte a byte (com a 7b desligada e em teste). FASE 7c (P8, R5.4 item 4, R5.2-2(b) e (c)): com modo_tarefas fora de desligado, a linha (n) leva também as perguntas das etapas (tarefa:quem:<os>, depois tarefa:prazo:<os>; a de prazo que vence hoje ou no próximo dia útil perde hoje), só com o portão delas, e a (e) não as repete; e a linha (o) das etapas (tipo dia; até 480, sem números): a quem não recebe pelo WhatsApp (sem telefone pela régua da 7a ou fora da rotina) com etapa hoje ou no próximo dia útil — "Etapas (Alex não tem telefone: quem passa e confere é você). Hoje no Lenine devia ficar pronto: …. Se faltou alguma, me diga qual (…). Amanhã (qui 05/11), Alex no Lenine: Terminar: …; … — com você. É o último dia: tem que ficar tudo pronto." —, texto_curto "Etapas: amanhã é o último dia do Lenine (Alex, 2 etapas); hoje, 2 para conferir. Pergunte o que o Alex faz amanhã.", perda 75 só com o último dia de uma OS amanhã ou com uma pendente dita que volta primeiro (senão 70), sem pergunta; em teste, modo sombra e "Em teste: ". Com modo_tarefas desligado, a de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7c (20261102100580): (achado 14) na linha (n), sem nenhuma pergunta da 7b que perca hoje e com uma de quem faz o quê ou das etapas que perde hoje, as da 7b ficam fora da linha neste dia (a da 7c vai primeiro, inteira, e conta como vista; a chamada não gasta a vez dela num dia que não é o seu); (achado 8) com uma linha da 7c ligada de perda >= 75 (a (o) "Etapas" ou a (n) com pergunta de quem faz o quê ou das etapas), a linha do cliente de perda 75 ganha a forma curta ("Mensagem para Vera (véspera, com a pergunta do acesso) espera *manda cliente Vera* (sai ter 10/11 às 09:00); *agenda clientes* mostra."; com mais de uma, "… e mais N esperam *manda cliente* (a 1ª sai …) …"), para o Secretário cheio encolher a do cliente antes de tirar a da 7c; (achado 2) a (n) com uma pergunta de quem faz o quê ou das etapas ligada, contada, aberta e nunca vista há 2 dias úteis ou mais sobe de 75 a 77 (acima das perguntas do gestor, abaixo da compra e da decisão), salvo se uma linha de perda 76 a 79 perde algo hoje (a ficha de amanhã, um veto ou um prazo de hoje). Sem a 7c ligada, a de antes, byte a byte. CORREÇÃO 2 DA REVISÃO DA 7c (20261102100590): (achados 1 e 13) com a (n) de quem faz o quê nunca vista há 2 dias úteis (a que a 100580 sobe a 77) ou com a (o) "Etapas" ligada da véspera do último dia, todas as linhas ligadas de 75 sobem a 77 juntas quando há a pergunta do gestor de 76 para ceder (sai no corte a de 76, que não perde hoje, nunca a mensagem ao cliente) — sem ela, a (n) que a 100580 sobe volta a 75 —, salvo com uma linha de 76 a 79 que perde algo hoje; (achado 13) quando o próximo dia útil é dia de revisão da tarde (o 1º dia útil da semana ou do mês: turnoDaTarde), a (o) de hoje já cobra o último dia que cai no dia útil seguinte ("Ter 10/11 é o último dia do Lenine (Alex): tem que ficar tudo pronto — aviso hoje porque seg 09/11 é dia de revisão."), também na forma curta, com perda 75; (achado 15) a forma curta da (o) diz o dia ("seg 09/11", "Pergunte o que o Alex faz na seg 09/11.") quando o próximo dia útil não é amanhã; (achado 11) a de quem faz o quê da equipe, ligada, que vai como "Também" leva o que foi marcado e o prazo e conta como vista. Sem a 7c ligada, a de antes. FASE 7d (P5, R6.7c-3, R6.12): (a) a crítica acesso com a opção 2 já dita não volta ao fechamento; (e) a combinar com perda_em até o 2º dia útil sobe a 75 (a vaga garantida de agenda_textos_do_fechamento), a local fica em 30; (achado 13) o remendo "aviso hoje porque … é dia de revisão" sai: com as linhas nos dias de revisão (62d1fd95), a (o) cobra a véspera do último dia no próprio dia, e o v_c13_av fica vazio. A parte do achado 15 fica. Só pode ir ao ar com o ai-daily-briefing com 62d1fd95 no ar antes ou junto.';

-- agenda_decisoes_abertas (de 20261025100400_agenda_fase2_rascunho.sql): UMA linha mudou, a do where (desvio 1 das notas do P5). A combinar tem opções e só
-- agenda_decisoes_abertas leva ao agenda_decidir (agenda_rascunho_aplicar, a tela): crítica só, ela ficaria sem resposta pela conversa.
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
           where (q.critica or q.tipo = 'combinar') and q.estado = 'aberta' and q.modo = 'ligado'
             and (q.expira_em is null or q.expira_em > p_agora)) x;
$function$;

comment on function public.agenda_decisoes_abertas(timestamptz) is
  'Agenda de Produção (Fase 2, P4): as decisões críticas abertas (modo ligado) numeradas — n = 1 é a que perde primeiro (perda_em, depois a mais antiga). [{n, id, tipo, os, os_ids, texto, opcoes, recomendacao, recomendacao_texto, perda_em, versao_base}]. O rascunho resolve "a 1" por aqui; agenda_ver (foco decisoes) numera igual. FASE 7d (P5): a pergunta combinar (não crítica, com opções) entra na lista: é só por aqui que uma pergunta chega a agenda_decidir pela conversa e pela tela.';

-- _agenda_ver_decisoes (de 20261026100500_agenda_fase3_acompanhamento.sql)
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
                      -- FASE 7d: (7d P5) a combinar já vem numerada em v_dec (agenda_decisoes_abertas)
                      and q.tipo <> 'combinar'
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
  'Agenda de Produção (Fase 2, P5; Fase 3, P6: a da diária com as opções e as palavras): agenda_ver foco decisoes — as decisões críticas abertas numeradas por agenda_decisoes_abertas ("Decisão 1: <a pergunta com as opções e a recomendação>"), como responder, e o que mais a agenda quer saber (chegou?, parada?, o que falta?), uma linha cada; sem nada em ligado, o que a sombra perguntaria ("Em teste"); nada = "Nada esperando você na agenda agora.". {ok, texto, dados{decisoes, outras}}. FASE 7d (P5): a combinar vem numerada, como decisão, e sai de "Também quero saber".';

-- ── 8. Portas ─────────────────────────────────────────────────────────────────────────────────────
-- Revoke de public, anon e authenticated, e o grant explícito: o privilégio padrão do esquema daria o execute a todos.
-- As leituras e agenda_local_vigiar têm a porta do motor (só o service_role; quem as alcança é definer). As escritas internas: ninguém.
revoke all on function
  public._agenda_combinar_texto(jsonb, text, date),
  public._agenda_combinar_da_os(uuid, date),
  public._agenda_local_resolver(date, timestamptz),
  public._agenda_local_combinar(date, timestamptz),
  public._agenda_local_conflitos(date),
  public._agenda_local_calendario(date, timestamptz),
  public.agenda_local_vigiar(date, timestamptz),
  public._agenda_local_restaurar(uuid, uuid, timestamptz),
  public._agenda_desfazer_local(uuid, uuid, text, date, timestamptz),
  public._agenda_local_decidir(uuid, smallint, uuid, text, text, date, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function
  public._agenda_combinar_texto(jsonb, text, date),
  public._agenda_combinar_da_os(uuid, date),
  public._agenda_local_conflitos(date),
  public.agenda_local_vigiar(date, timestamptz)
  to service_role;

-- As recriadas mantêm as portas delas: create or replace não muda a ACL, e nenhuma é nova.
