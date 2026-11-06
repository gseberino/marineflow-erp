-- Agenda de Produção, Fase 7, etapa 7d ("onde, quando e com o bem em que estado"), correção da revisão, Onda 2: o que o dono lê e responde na conversa.
-- Ordem de serviço: decisoes-do-fio.md, seção Onda 2 (vale sobre a spec, sobre o R6 e sobre as notas). Achados: f7d/rev-objetivo (O), f7d/rev-conformidade (C), f7d/rev-regressao (R).
-- Notas: notas-fase7d.md, seção "Correção, Onda 2". Depende de 20261107100000 a 20261107100800. Vem antes da semente 20261107100900.
--
-- ═══ SÓ FUNÇÕES — OK NOMEADO ═══ (nenhuma tabela, nenhuma coluna, nenhum dado)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7d/corr2/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA (a regra do "mais nova" é conferida na
-- montagem). Nas que vêm de antes da 7d, só blocos "-- FASE 7d: (correção …)" inseridos, ou a linha trocada dentro de um bloco que já existia: tirados os blocos, é a origem, byte a byte.
--
-- O QUE MUDA, por achado:
--   O8  *agenda pendências* mostra tudo: só nesse foco, até 1.800 letras; dados.abertas leva as perguntas sem número, mesmo as cortadas; quando ainda corta, diz os focos por assunto. "1" sozinho
--       com várias abertas: "Qual decisão?" só com os títulos numerados (_agenda_titulo_da_pergunta). A régua do "1" não muda.
--   O9  a opção "Já terminou" com *gestor, só propor*: a recusa aponta o caminho que funciona, *entreguei {nome}*. As outras opções, a recusa de sempre.
--   O16 a releitura de autorizados marca quem saiu da equipe (_agenda_saiu_da_equipe), sem recusar.
--   O17 (C8) em teste, a releitura de viagem, pátio e acesso acrescenta " (anotei; só muda o plano quando isso for ligado)", enquanto o assunto não estiver ligado por _agenda_local_modo. Só a
--       releitura: a ação do *grava* e o *desfaz* dizem o fato.
--
-- O R1 (a trava do "1" com pendência do assistente) não tem banco: é _shared/ai/whatsapp-channel.ts e a chamada em ai-agent/index.ts. O resto da Onda 2 é prompt, evals e papéis.
--
-- SOMBRA: nada aqui está no caminho do motor, da vigia nem do fechamento (o M1, o M1c e o C8j seguem verdes). O que muda sem modo é só conversa do dono: está na lista "entra sem modo" do roteiro.
--
-- PROVA: supabase/tests/agenda_fase7d_correcao2.sql.
--
-- DESFAZER: reaplicar as definições de 20261107100550 (_agenda_ver_decisoes), 20261107100600 (_agenda_rascunho_frase) e 20261107100800 (agenda_rascunho_aplicar, agenda_rascunho_planejar,
-- _agenda_planejar_linhas) e apagar as 2 novas.

-- ── As novas ───────────────────────────────────────────────────────────────────────────────
-- (O8) O título de uma pergunta: o texto até as opções, a 1ª frase, em até 90 letras.
create or replace function public._agenda_titulo_da_pergunta(p_texto text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select public._agenda_corta(rtrim(split_part(regexp_replace(btrim(p_texto), '\s+1\)\s.*$', ''), '. ', 1), ' .:;'), 90);
$function$;

comment on function public._agenda_titulo_da_pergunta(text) is
  'Agenda de Produção (Fase 7d, correção O8): o título de uma pergunta aberta, para o "Qual decisão?": o texto até " 1) ", a 1ª frase, sem a pontuação do fim, cortada em 90 letras (_agenda_corta). Só agenda_rascunho_aplicar chama.';

-- (O16) Saiu da equipe: a regra de "quem saiu da agenda" da chamada, sem a janela: tinha linha em agenda_disponibilidade e nenhuma viva. Quem está na grade tem linha viva (agenda_capacidade exige). O
-- terceiro, que nunca teve linha, não saiu.
create or replace function public._agenda_saiu_da_equipe(p_payee uuid)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select p_payee is distinct from public._agenda_dono(null)
         and exists (select 1 from public.agenda_disponibilidade w where w.payee_id = p_payee)
         and not exists (select 1 from public.agenda_disponibilidade w where w.payee_id = p_payee and w.substituida_em is null);
$function$;

comment on function public._agenda_saiu_da_equipe(uuid) is
  'Agenda de Produção (Fase 7d, correção O16): a pessoa saiu da equipe? A mesma regra da chamada da 7b (_agenda_ver_equipe, "quem saiu da agenda"), sem a janela de dias: tinha linha em agenda_disponibilidade e nenhuma viva. O dono nunca; o terceiro que nunca teve linha também não. Só agenda_rascunho_planejar chama.';

-- ── As recriadas ───────────────────────────────────────────────────────────────────────────
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
  -- FASE 7d: (correção O8) só neste foco o teto é outro; o que os outros focos usam (cf.texto_max) não muda. dados leva todas as abertas, mesmo as cortadas
  c_7d_teto    constant int := greatest(cf.texto_max, 1800);   -- estrutural: as decisões numeradas ocupam a maior parte, e este foco existe para mostrar tudo
  c_7d_assunto constant text := 'Para ver por assunto: *agenda compras*, *agenda clientes* ou *agenda gestor*.';
  v_7d_abertas jsonb;
  v_7d_txt     text;
  -- FASE 7d: fim
begin
  for e in select x from jsonb_array_elements(v_dec) x loop
    -- FASE 3: a da diária com as opções, a recomendação e as palavras
    v_l := v_l || format('Decisão %s: %s', e ->> 'n',
                         case when e ->> 'tipo' = 'diaria' then public._agenda_texto_da_diaria((e ->> 'id')::uuid) else e ->> 'texto' end);
  end loop;
  v_outra := array(select q.texto from public.agenda_perguntas q
                    where not q.critica and q.estado = 'aberta' and q.modo = 'ligado'
                      -- FASE 7d: (7d P5, P6, P6b) quem tem número já vem em v_dec (agenda_decisoes_abertas): pelo id, uma pergunta nunca aparece duas vezes. Quem não tem
                      -- número (sem opções, sem efeito em agenda_decidir ou com a opção já dita) segue aqui, como antes.
                      and not exists (select 1 from jsonb_array_elements(v_dec) x where x ->> 'id' = q.id::text)
                      -- FASE 7d: fim
                      and (q.expira_em is null or q.expira_em > p_agora)
                    order by q.perda_em nulls last, q.criada_em, q.id);
  -- FASE 7d: (correção O8) as abertas sem número, com o texto: vão em dados, mesmo as cortadas (as numeradas já estão em decisoes). Quem tem opções vem primeiro: o corte tira do fim, e a nota se
  -- responde por número ("na nota, a 2"): as opções dela não podem ser as que somem. O resto, na ordem de antes.
  v_7d_abertas := coalesce((select jsonb_agg(jsonb_build_object('tipo', q.tipo, 'texto', q.texto)
                                             order by (case when jsonb_typeof(q.opcoes) = 'array' then jsonb_array_length(q.opcoes) > 0 else false end) desc,
                                                      q.perda_em nulls last, q.criada_em, q.id)
                              from public.agenda_perguntas q
                             where not q.critica and q.estado = 'aberta' and q.modo = 'ligado'
                               and not exists (select 1 from jsonb_array_elements(v_dec) x where x ->> 'id' = q.id::text)
                               and (q.expira_em is null or q.expira_em > p_agora)), '[]'::jsonb);
  v_outra := array(select y ->> 'texto' from jsonb_array_elements(v_7d_abertas) with ordinality u(y, o) order by o);
  -- FASE 7d: fim
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
  -- FASE 7d: (correção O8) o foco que mostra tudo: até c_7d_teto letras. Quando ainda corta, diz por onde pedir por assunto: só focos que existem. O return de baixo não roda mais; fica para os
  -- tiradores das etapas anteriores.
  v_7d_txt := case when char_length(array_to_string(v_l, E'\n')) <= c_7d_teto then public._agenda_juntar(v_l, c_7d_teto)
                   else public._agenda_juntar(v_l, c_7d_teto - char_length(c_7d_assunto) - 1) || E'\n' || c_7d_assunto end;
  return jsonb_build_object('ok', true, 'texto', v_7d_txt,
                            'dados', jsonb_build_object('decisoes', v_dec, 'outras', cardinality(v_outra), 'abertas', v_7d_abertas));
  -- FASE 7d: fim
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_l, cf.texto_max),
                            'dados', jsonb_build_object('decisoes', v_dec, 'outras', cardinality(v_outra)));
end;
$function$;

comment on function public._agenda_ver_decisoes(date, timestamptz) is
  'Agenda de Produção (Fase 2, P5; Fase 3, P6: a da diária com as opções e as palavras): agenda_ver foco decisoes — as decisões críticas abertas numeradas por agenda_decisoes_abertas ("Decisão 1: <a pergunta com as opções e a recomendação>"), como responder, e o que mais a agenda quer saber (chegou?, parada?, o que falta?), uma linha cada; sem nada em ligado, o que a sombra perguntaria ("Em teste"); nada = "Nada esperando você na agenda agora.". {ok, texto, dados{decisoes, outras}}. FASE 7d (P5): a combinar vem numerada, como decisão, e sai de "Também quero saber". FASE 7d (P6): a local também vem numerada. FASE 7d (P6b): quem tem número sai de "Também quero saber" pelo id; quem não tem segue lá. Correção da 7d (O8): só neste foco, até 1.800 letras; dados.abertas leva as sem número com o texto, mesmo as cortadas; quando ainda corta, diz os focos por assunto.';

create or replace function public.agenda_rascunho_aplicar(p_autor uuid, p_canal text, p_proposta text default null,
                                                          p_os text[] default null, p_decisao text default null,
                                                          p_opcao text default null, p_trecho text default null,
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
  v_rec    jsonb := public._agenda_pedido_recusa(p_canal, p_trecho, 'agenda_rascunho_aplicar');
  cf       public.agenda_config := public._agenda_cfg();
  v_lista  jsonb;
  v_q      jsonb;
  v_qs     jsonb;
  v_opc    jsonb;
  v_opcs   jsonb;
  v_ro     jsonb;
  v_n      int;
  v_ref    text;
  v_sim    jsonb;
  v_mud    text;
  v_p      public.agenda_propostas%rowtype;
  v_os     uuid[];
  v_x      text;
  v_viol   jsonb;
  v_sel    jsonb;
  v_frase  text;
  v_txt    text;
  -- FASE 7d: (7d P6b) as perguntas com opções e sem número, se mais de uma espera, a pergunta "qual?" e a linha da pergunta escolhida
  v_7d_fora   jsonb;
  v_7d_varias boolean;
  v_7d_qual   text;
  v_7d_linha  public.agenda_perguntas%rowtype;
  -- FASE 7d: fim
  v_ncanc  int;
begin
  if v_rec is not null then
    return v_rec;
  end if;
  if p_decisao is not null and p_proposta is not null then
    raise exception 'agenda_rascunho_aplicar: diga a proposta OU a decisão, não as duas' using errcode = '22023';
  end if;

  -- ── Responder uma decisão crítica ──
  if nullif(btrim(coalesce(p_decisao, '')), '') is not null or nullif(btrim(coalesce(p_opcao, '')), '') is not null then
    v_lista := public.agenda_decisoes_abertas(p_agora);
    -- FASE 7d: (7d P6b) quem também espera o dono sem ter número: tem opções, mas agenda_decidir não sabe o que fazer com elas (a nota e o aviso do fornecedor, que se
    -- respondem por material_informar) ou ele já escolheu "eu digo". "1" pode ser para ela: com mais de uma esperando, ninguém escolhe por ele.
    v_7d_fora := coalesce((select jsonb_agg(p.texto order by p.perda_em nulls last, p.criada_em, p.id)
                             from public.agenda_perguntas p
                            where p.estado = 'aberta' and p.modo = 'ligado'
                              and (p.expira_em is null or p.expira_em > p_agora)
                              and case when jsonb_typeof(p.opcoes) = 'array' then jsonb_array_length(p.opcoes) > 0 else false end
                              and not exists (select 1 from jsonb_array_elements(v_lista) e where e ->> 'id' = p.id::text)), '[]'::jsonb);
    if jsonb_array_length(v_lista) = 0 and jsonb_array_length(v_7d_fora) > 0 then
      return public._agenda_recusa('Essa pergunta não tem número de decisão: me responda com as suas palavras. '
        || (select string_agg(x, ' ') from jsonb_array_elements_text(v_7d_fora) x), 'sem_numero');
    end if;
    v_7d_varias := jsonb_array_length(v_lista) + jsonb_array_length(v_7d_fora) > 1;
    -- (correção O8) só os títulos, numerados: as opções aninhadas davam 1.100 letras e números dentro de números ("1) … 1) …; 2) …; 2) …")
    v_7d_qual := format('Qual decisão? %s. Diga a decisão e a opção (por exemplo, "na decisão 1, a opção 2"). Eu não escolho por você.',
                        (select string_agg((q ->> 'n') || ') ' || public._agenda_titulo_da_pergunta(q ->> 'texto'), '; ' order by (q ->> 'n')::int)
                           from jsonb_array_elements(v_lista) q))
                 || coalesce(' Sem número, responda com as suas palavras: '
                             || (select string_agg(public._agenda_titulo_da_pergunta(x), '; ') from jsonb_array_elements_text(v_7d_fora) x) || '.', '');
    -- FASE 7d: fim
    if jsonb_array_length(v_lista) = 0 then
      return public._agenda_recusa('Não tenho decisão da agenda esperando você agora.', 'sem_decisao');
    end if;
    v_ref := btrim(coalesce(p_decisao, ''));
    if v_ref ~ '^\d{1,3}$' then
      select q into v_q from jsonb_array_elements(v_lista) q where (q ->> 'n')::int = v_ref::int;
      if v_q is null then
        return public._agenda_recusa(format('Não tenho a decisão %s. As que esperam você: %s.', v_ref,
          (select string_agg((q ->> 'n') || ') ' || rtrim(q ->> 'texto', '.'), '; ' order by (q ->> 'n')::int)
             from jsonb_array_elements(v_lista) q)), 'decisao_nao_existe');
      end if;
    elsif v_ref <> '' then
      v_ro := public.agenda_resolver_os(v_ref, p_hoje, false);
      if v_ro ->> 'status' <> 'ok' then
        return public._agenda_recusa_da_os(v_ro);
      end if;
      select coalesce(jsonb_agg(q order by (q ->> 'n')::int), '[]'::jsonb) into v_qs
        from jsonb_array_elements(v_lista) q
       where q ->> 'os' = v_ro ->> 'id' or (q -> 'os_ids') ? (v_ro ->> 'id');
      if jsonb_array_length(v_qs) = 0 then
        return public._agenda_recusa(format('Não tenho decisão esperando você sobre %s.', v_ro ->> 'cliente_curto'), 'decisao_nao_existe');
      end if;
      if jsonb_array_length(v_qs) > 1 then
        return public._agenda_recusa(format('Qual delas? %s.',
          (select string_agg((q ->> 'n') || ') ' || rtrim(q ->> 'texto', '.'), '; ' order by (q ->> 'n')::int)
             from jsonb_array_elements(v_qs) q)), 'decisao_ambigua');
      end if;
      v_q := v_qs -> 0;
    -- FASE 7d: (7d P6b) sem dizer qual: com a lista de uma só, mas outra pergunta com opções esperando, também pergunta qual
    elsif v_7d_varias then
      return public._agenda_recusa(v_7d_qual, 'decisao_ambigua');
    -- FASE 7d: fim
    elsif jsonb_array_length(v_lista) = 1 then
      v_q := v_lista -> 0;
    else
      return public._agenda_recusa(format('Qual decisão? %s.',
        (select string_agg((q ->> 'n') || ') ' || rtrim(q ->> 'texto', '.'), '; ' order by (q ->> 'n')::int)
           from jsonb_array_elements(v_lista) q)), 'decisao_ambigua');
    end if;

    -- FASE 7d: (7d P8; os evals S24 e K57) a resposta em palavras: "lança meia pro Roberto" e "na decisão do aviso do Nelson, pode mandar" são respostas, e o modelo achou os números
    -- pela lista, como o prompt manda. A régua abaixo é para o número solto: quando as palavras dele identificam a pergunta e falam da opção, ela não se aplica. "pode ser" não diz nada, e continua perguntando.
    if v_7d_varias and btrim(coalesce(p_opcao, '')) ~ '^\d{1,2}$'
       and public._agenda_disse_em_palavras(p_trecho, v_q ->> 'texto',
             (select o ->> 'texto' from jsonb_array_elements(v_q -> 'opcoes') o where (o ->> 'n')::int = btrim(p_opcao)::int),
             array(select q ->> 'texto' from jsonb_array_elements(v_lista) q where q ->> 'id' <> v_q ->> 'id')
             || array(select x from jsonb_array_elements_text(v_7d_fora) x)) then
      v_7d_varias := false;
    end if;
    -- FASE 7d: fim
    -- FASE 7d: (7d P6b) com mais de uma esperando, a decisão e a opção têm de estar nas palavras do dono: "1" sozinho não é a decisão 1, opção 1, e a decisão pelo nome só
    -- vale com o nome dito. A opção pelo nome da OS ("pode atrasar o Nelson") não passa aqui: ela mesma diz qual.
    if v_7d_varias and btrim(coalesce(p_opcao, '')) ~ '^\d{1,2}$'
       and not (case when v_ref ~ '^\d{1,3}$' then public._agenda_disse_os_numeros(p_trecho, v_ref::int, btrim(p_opcao)::int)
                     else exists (select 1 from regexp_split_to_table(public._agenda_normal(v_ref), ' ') w
                                   where char_length(w) >= 3
                                     and public._agenda_normal(p_trecho) ~ ('(^| )' || w || '( |$)'))
                          and public._agenda_disse_os_numeros(p_trecho, null, btrim(p_opcao)::int) end) then
      return public._agenda_recusa(v_7d_qual, 'decisao_ambigua');
    end if;
    -- FASE 7d: fim
    -- A opção: o nº ou o nome da OS que aceita atrasar. Sem ela, a pergunta volta como está (o banco não escolhe).
    v_ref := btrim(coalesce(p_opcao, ''));
    if v_ref = '' then
      return public._agenda_recusa(rtrim(v_q ->> 'texto', ' ')
        || case when (v_q ->> 'texto') ~ '\d\)' then '' else ' ' || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; '
                                                                   order by (o ->> 'n')::int) from jsonb_array_elements(v_q -> 'opcoes') o) end,
        'sem_opcao',
        (select jsonb_agg((o ->> 'n') || ') ' || (o ->> 'texto') order by (o ->> 'n')::int) from jsonb_array_elements(v_q -> 'opcoes') o));
    end if;
    if v_ref ~ '^\d{1,2}$' then
      select o into v_opc from jsonb_array_elements(v_q -> 'opcoes') o where (o ->> 'n')::int = v_ref::int;
    else
      v_ro := public.agenda_resolver_os(v_ref, p_hoje, false);
      if v_ro ->> 'status' <> 'ok' then
        return public._agenda_recusa_da_os(v_ro);
      end if;
      select coalesce(jsonb_agg(o order by (o ->> 'n')::int), '[]'::jsonb) into v_opcs
        from jsonb_array_elements(v_q -> 'opcoes') o where o ->> 'os' = v_ro ->> 'id';
      if jsonb_array_length(v_opcs) > 1 then
        return public._agenda_recusa(format('Qual das opções? %s',
          (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
             from jsonb_array_elements(v_opcs) o)) || '.', 'opcao_ambigua');
      end if;
      v_opc := v_opcs -> 0;
    end if;
    if v_opc is null then
      return public._agenda_recusa('Essa opção não existe. As opções são: '
        || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
              from jsonb_array_elements(v_q -> 'opcoes') o) || '.', 'opcao_nao_existe',
        (select jsonb_agg((o ->> 'n') || ') ' || (o ->> 'texto') order by (o ->> 'n')::int) from jsonb_array_elements(v_q -> 'opcoes') o));
    end if;

    -- FASE 7d: (7d P6b, R6.7b) a não crítica cujo modo não vale agora: agenda_decidir recusaria no *grava*, e a frase seria "a agenda mudou". Com o freio, as do gestor têm
    -- número e não têm resposta, como sempre foi: nenhum caminho novo marca dia.
    select p.* into v_7d_linha from public.agenda_perguntas p where p.id = (v_q ->> 'id')::uuid;
    if not v_7d_linha.critica and coalesce(public._agenda_modo_da_pergunta(v_7d_linha.tipo, v_7d_linha.chave), 'desligado') <> 'ligado' then
      return public._agenda_recusa(
        -- (correção O9) o "Já terminou" tem caminho que funciona com o freio: a palavra do dono. As outras opções, a recusa de sempre
        case when cf.gestor_so_propor and v_7d_linha.tipo in ('situacao', 'estimativa', 'reavaliar', 'reestimar') and coalesce((v_opc #>> '{efeito,terminou}')::boolean, false)
             then format('Com *gestor, só propor* essa resposta não muda nada agora. Para dizer que terminou, mande *entreguei %s*: eu concluo e marco a entrega.',
                         regexp_replace(public._agenda_rotulo_da_os(v_7d_linha.service_order_id), ' \([^()]*\)$', ''))
             when cf.gestor_so_propor and v_7d_linha.tipo in ('situacao', 'estimativa', 'reavaliar', 'reestimar')
             then 'Com *gestor, só propor* essa resposta não muda nada agora. Se quiser, me diga com as suas palavras (por exemplo, os dias do serviço).'
             else 'Essa pergunta ainda está em teste: mostro como ficaria, mas não mudo nada.' end, 'em_teste');
    end if;
    -- FASE 7d: fim
    -- A agenda mudou desde a pergunta: o efeito da opção é refeito agora; se não termina como a opção dizia, a pergunta
    -- volta com os dias de agora (a mesma régua do agenda_decidir).
    if (v_q ->> 'versao_base')::bigint is distinct from cf.versao_plano and jsonb_typeof(v_opc -> 'espera') = 'object'
       and v_opc -> 'espera' <> '{}'::jsonb then
      v_sim := public.agenda_propor('replano', null, null, array(select x::uuid from jsonb_array_elements_text(v_q -> 'os_ids') x),
                                    coalesce(v_opc #> '{efeito,restricoes}', '{}'::jsonb), false, 'dono', v_autor, p_hoje, p_agora);
      select string_agg(format('%s termina %s (antes eu disse %s)', public._agenda_rotulo_da_os(e.key::uuid),
                               coalesce(public._dia_curto(x.fim), 'sem encaixe'), public._dia_curto((e.value #>> '{}')::date)), '; ')
        into v_mud
        from jsonb_each(v_opc -> 'espera') e
        left join lateral (select max((i ->> 'fim_depois')::date) as fim from jsonb_array_elements(v_sim -> 'itens') i
                            where i ->> 'op' = 'criar' and i ->> 'os' = e.key and i ->> 'tipo' <> 'reserva') x on true
       where x.fim is distinct from (e.value #>> '{}')::date;
      if v_mud is not null then
        return public._agenda_recusa('A agenda mudou desde a pergunta: ' || v_mud || '. Me responda de novo com os dias de agora.',
                                     'decisao_mudou');
      end if;
    end if;

    -- FASE 7d: (7d P6b; correção O18) a releitura diz de qual pergunta é a opção: "Está combinado" sozinho não diz nada, e o *grava* é o único portão. Vale para a crítica também: com 2
    -- perguntas da mesma OS abertas, ele conferia às cegas. O caminho de baixo, o de antes, não roda mais; fica para os tiradores das etapas anteriores.
    if true then
      v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'aplicar', 'decisao:' || (v_q ->> 'id'),
                 nullif(v_q ->> 'os', '')::uuid,
                 jsonb_build_object('grupo', 'decisao:' || (v_q ->> 'id'), 'rotulo_grupo', 'Decisão', 'pergunta_id', v_q ->> 'id',
                                    'opcao', (v_opc ->> 'n')::int, 'opcao_texto', v_opc ->> 'texto',
                                    'frase_pronta', format('na pergunta "%s": %s', public._agenda_corta(v_7d_linha.texto, 90), rtrim(v_opc ->> 'texto', '.'))),
                 p_trecho, p_hoje);
      return jsonb_build_object('ok', true, 'item', v_txt,
                                'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
    end if;
    -- FASE 7d: fim
    v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'aplicar', 'decisao:' || (v_q ->> 'id'),
               nullif(v_q ->> 'os', '')::uuid,
               jsonb_build_object('grupo', 'decisao:' || (v_q ->> 'id'), 'rotulo_grupo', 'Decisão', 'pergunta_id', v_q ->> 'id',
                                  'opcao', (v_opc ->> 'n')::int, 'opcao_texto', v_opc ->> 'texto',
                                  'frase_pronta', rtrim(v_opc ->> 'texto', '.')),
               p_trecho, p_hoje);
    return jsonb_build_object('ok', true, 'item', v_txt,
                              'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
  end if;

  -- ── Publicar uma proposta aberta ──
  v_lista := public.agenda_propostas_abertas(p_agora);
  if jsonb_array_length(v_lista) = 0 then
    return public._agenda_recusa('Não tenho plano montado para publicar. Peça para eu montar (por exemplo, "monta a semana que vem").',
                                 'sem_proposta');
  end if;
  v_ref := public._agenda_normal(p_proposta);
  v_n := case when v_ref in ('', 'a ultima', 'ultima', 'essa', 'esta', 'a proposta', 'proposta', 'ela', 'isso', 'a semana', 'semana')
              then 1
              when v_ref ~ '^\d{1,3}$' then v_ref::int end;
  if v_n is null then
    return public._agenda_recusa(format('Qual plano? %s.',
      (select string_agg((p ->> 'n') || ') ' || coalesce(p ->> 'titulo', 'plano'), '; ' order by (p ->> 'n')::int)
         from jsonb_array_elements(v_lista) p)), 'proposta_ambigua');
  end if;
  select pr.* into v_p from public.agenda_propostas pr
   where pr.id = (select (p ->> 'id')::uuid from jsonb_array_elements(v_lista) p where (p ->> 'n')::int = v_n);
  if not found then
    return public._agenda_recusa(format('Não tenho o plano %s montado.', v_n), 'proposta_nao_existe');
  end if;
  if v_p.versao_base <> cf.versao_plano then
    return public._agenda_recusa('A agenda mudou desde que eu montei: peça de novo que eu refaço.', 'proposta_obsoleta');
  end if;

  -- só as OS ditas ("publica só o Lenine e o Flávio"), e só se estão na proposta
  if p_os is not null and cardinality(p_os) > 0 then
    v_os := '{}';
    foreach v_x in array p_os loop
      v_ro := public.agenda_resolver_os(v_x, p_hoje, false);
      if v_ro ->> 'status' <> 'ok' then
        return public._agenda_recusa_da_os(v_ro);
      end if;
      if not exists (select 1 from jsonb_array_elements(v_p.itens) i where i ->> 'os' = v_ro ->> 'id') then
        return public._agenda_recusa(format('%s não está nesse plano.', v_ro ->> 'cliente_curto'), 'os_fora_da_proposta');
      end if;
      v_os := v_os || (v_ro ->> 'id')::uuid;
    end loop;
    v_os := array(select distinct x from unnest(v_os) x order by 1);
  end if;

  v_viol := public.agenda_validar(v_p.id, v_os, p_hoje, p_agora);
  if jsonb_array_length(v_viol) > 0 then
    return public._agenda_recusa('Não dá para publicar: '
      || (select string_agg(e ->> 'texto', ' ' order by o) from jsonb_array_elements(v_viol) with ordinality t(e, o)), 'proposta_invalida');
  end if;
  v_sel := public._agenda_itens_escolhidos(v_p.itens, v_os, null);
  if not exists (select 1 from jsonb_array_elements(v_sel) i where i ->> 'op' = 'criar') and jsonb_array_length(v_sel) = 0 then
    return public._agenda_recusa('No plano que eu montei não há nada para publicar sem a sua decisão: veja o que a agenda precisa de você.',
                                 'so_critico');
  end if;
  v_ncanc := (select count(*) from jsonb_array_elements(v_sel) i where i ->> 'op' = 'cancelar');
  v_frase := case when v_p.escopo = 'semana'
                  then lower(left(coalesce(v_p.textos ->> 'titulo', 'a semana'), 1)) || substr(coalesce(v_p.textos ->> 'titulo', 'a semana'), 2) || ': '
                  else '' end
             || coalesce(nullif(array_to_string(array(
                  select regexp_replace(rtrim(i ->> 'texto', '.'), '^([^:]*): ', '\1, ')
                    from jsonb_array_elements(v_sel) with ordinality t(i, k)
                   where i ->> 'op' = 'criar'
                   order by (i ->> 'de')::date, i ->> 'numero' collate "C", k), '; '), ''), 'nada novo')
             || case when v_ncanc > 0 then format('; e tiro da agenda %s que não pode mais acontecer',
                                                   public._agenda_plural(v_ncanc, 'serviço', 'serviços')) else '' end;

  v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'aplicar', 'aplicar:' || v_p.id::text, null,
             jsonb_build_object('grupo', 'aplicar:' || v_p.id::text, 'rotulo_grupo', 'Publico na agenda', 'proposta_id', v_p.id,
                                'os_ids', to_jsonb(v_os), 'frase_pronta', v_frase),
             p_trecho, p_hoje);
  return jsonb_build_object('ok', true, 'item', v_txt,
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
end;
$function$;

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
  -- (correção O17) só a releitura leva a nota (a chave releitura vem de _agenda_rascunho_frase): a ação do *grava* e o *desfaz* dizem o fato. As chaves em_teste_* vêm do rascunho, por _agenda_local_modo
  c_nota constant text := ' (anotei; só muda o plano quando isso for ligado)';
  v_nota boolean := coalesce((p_d ->> 'releitura')::boolean, false);
begin
  if p_d ? 'local_id' then
    -- (correção O2, O3) antes do local_id: depois do *grava* a casa também tem local_id. O lugar novo só existe até o *grava*
    v := v || case when coalesce((p_d ->> 'local_casa')::boolean, false) then 'Local: na casa do cliente (anotei).'
                   when p_d ->> 'local_novo' is not null then format('Local: %s (lugar novo: entra no cadastro quando você gravar).', p_d ->> 'local_novo')
                   when p_d ->> 'local_id' is not null then format('Local: %s.', p_d ->> 'local_nome')
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
    v := v || (format('%s chega %s e sai %s.', public._agenda_maiuscula(v_bem), public._dia_curto(v_ent), public._dia_curto(v_sai))
               || case when v_nota and p_d ? 'em_teste_patio' then c_nota else '' end);
  elsif v_ent is not null then
    v := v || (format('%s chega %s.', public._agenda_maiuscula(v_bem), public._dia_curto(v_ent))
               || case when v_nota and p_d ? 'em_teste_patio' then c_nota else '' end);
  elsif v_sai is not null then
    v := v || (format('%s sai %s.', public._agenda_maiuscula(v_bem), public._dia_curto(v_sai))
               || case when v_nota and p_d ? 'em_teste_patio' then c_nota else '' end);
  end if;
  if p_d ? 'viagem' then
    v := v || (case p_d ->> 'viagem' when 'regional' then 'Sem viagem (aqui na região).'
                                     when 'bate_volta' then 'Viagem: ida e volta no mesmo dia.'
                                     when 'pernoite' then 'Viagem com pernoite: a equipe vai e volta junta, em dias seguidos.'
                                     else 'Tirei a viagem que eu tinha (volto a supor).' end
               || case when v_nota and p_d ? 'em_teste_viagem' and p_d ->> 'viagem' in ('bate_volta', 'pernoite') then c_nota else '' end);
  end if;
  if jsonb_array_length(coalesce(p_d -> 'autorizados', '[]'::jsonb)) > 0 then
    -- (correção O16) quem saiu da equipe fica marcado, sem recusar: terceiro autorizado pode ser legítimo
    v := v || (format('Autorizados nesse serviço: %s.', public._agenda_lista(array(
                select case when (e ->> 'eh_dono')::boolean then 'você'
                            when e ? 'saiu' then (e ->> 'nome') || ' (saiu da equipe)'
                            else e ->> 'nome' end
                  from jsonb_array_elements(p_d -> 'autorizados') with ordinality t(e, o) order by o), null))
               || case when v_nota and p_d ? 'em_teste_acesso' then c_nota else '' end);
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
             -- (correção O17) a releitura: só aqui a nota do "ainda não muda o plano" sai
             || array_to_string(public._agenda_planejar_linhas(p_d || jsonb_build_object('releitura', true)), E'\n');
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
  v_7d_novo  jsonb;   -- (correção O2) o lugar novo
  v_7d_mun   jsonb;   -- (correção O2) a cidade dele, se é conhecida
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
      v_out := v_out || jsonb_build_object('local_id', null, 'local_nome', null, 'local_casa', true, 'local_novo', null);
    elsif v_7d_rl ->> 'status' = 'ok' then
      v_out := v_out || jsonb_build_object('local_id', v_7d_rl ->> 'id', 'local_nome', v_7d_rl ->> 'nome', 'local_casa', false, 'local_novo', null);
    -- (correção O2) o lugar fora do cadastro: se o texto é um nome plausível, entra; o *grava* cria a linha (só o dono passa por aqui: o M11 só pergunta). A cidade só se é conhecida
    elsif v_7d_rl ->> 'status' = 'nao_achei' then
      v_7d_novo := public._agenda_local_novo(d ->> 'local');
      if not (v_7d_novo ->> 'ok')::boolean then
        return public._agenda_recusa(v_7d_novo ->> 'texto', 'local_' || (v_7d_novo ->> 'motivo'));
      end if;
      v_7d_mun := public._agenda_municipio_conhecido(v_7d_novo ->> 'nome', v_os);
      v_out := v_out || jsonb_build_object('local_id', null, 'local_nome', v_7d_novo ->> 'nome', 'local_casa', false, 'local_novo', v_7d_novo ->> 'nome',
                                           'local_municipio', v_7d_mun ->> 'municipio', 'local_uf', v_7d_mun ->> 'uf');
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
    -- (correção O7a) verbo no passado com a data sem mês: já aconteceu. "chegou dia 5", dito em 06/11, é 05/11, não 05/12; "dia 20" é 20/10. agenda_data_dita não muda: quem chama pede o sentido
    if public._agenda_data_sem_mes(d ->> 'chega_em') and (v_dt ->> 'de')::date > p_hoje
       and public._agenda_normal(p_trecho) ~ '\m(chegou|entrou|veio|trouxe|deixou|ja esta)\M' then
      v_dt := public._agenda_data_conferida(d ->> 'chega_em', p_trecho, p_hoje, 'passado');
      if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    end if;
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
    -- (correção O7b) a chegada sem mês depois da saída dita na mesma frase: "chega dia 5 e ele busca dia 13", dito em 06/11, é 05/11 e 13/11. A chegada cai no mês da saída ou no anterior,
    -- se assim ficar antes dela. A releitura mostra as 2 datas por extenso antes do *grava*.
    if d ? 'chega_em' and public._agenda_data_sem_mes(d ->> 'chega_em')
       and (v_out ->> 'entrada_em')::date >= (v_out ->> 'retirada_em')::date then
      v_7d_ent := public._agenda_data_um(public._agenda_preparar_data(d ->> 'chega_em'), p_hoje, 'futuro', true, (v_out ->> 'retirada_em')::date - 1, null);
      if v_7d_ent is not null and v_7d_ent < (v_out ->> 'retirada_em')::date then
        v_out := v_out || jsonb_build_object('entrada_em', v_7d_ent);
      end if;
    end if;
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
                                                          'eh_dono', coalesce((v_rp ->> 'eh_dono')::boolean, false))
                                       -- (correção O16) a chave só para quem saiu da equipe
                                       || case when public._agenda_saiu_da_equipe((v_rp ->> 'payee_id')::uuid) then jsonb_build_object('saiu', true) else '{}'::jsonb end);
    end loop;
    v_out := v_out || jsonb_build_object('autorizados', v_7d_aut);
  end if;
  if 'local' = any (v_7d_limpar) then
    v_out := v_out || jsonb_build_object('local_id', null, 'local_nome', null, 'local_casa', false, 'local_novo', null);
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

  -- FASE 7d: (correção O17, C8) em teste, a releitura diz a verdade: viagem, pátio e acesso ficam anotados, e o plano só muda quando o assunto for ligado. Uma chave por assunto, porque o
  -- rascunho junta as frases da mesma OS; só com o assunto dito, e ausente com o modo ligado. Pelo freio também: _agenda_local_modo.
  if (v_out ->> 'entrada_em' is not null or v_out ->> 'retirada_em' is not null) and public._agenda_local_modo('patio') <> 'ligado' then
    v_out := v_out || jsonb_build_object('em_teste_patio', true);
  end if;
  if v_out ->> 'viagem' is not null and public._agenda_local_modo('viagem') <> 'ligado' then
    v_out := v_out || jsonb_build_object('em_teste_viagem', true);
  end if;
  if jsonb_array_length(coalesce(v_out -> 'autorizados', '[]'::jsonb)) > 0 and public._agenda_local_modo('acesso') <> 'ligado' then
    v_out := v_out || jsonb_build_object('em_teste_acesso', true);
  end if;
  -- FASE 7d: fim
  v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'planejar', 'planejar:' || v_os::text, v_os,
                                          public._agenda_os_do_rascunho(v_ro) || jsonb_build_object('bem_nome', v_bem) || v_out,
                                          p_trecho, p_hoje);
  return jsonb_build_object('ok', true, 'item', v_txt,
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
end;
$function$;

-- ── As portas das novas: internas, de ninguém; quem as chama é definer ──
revoke all on function public._agenda_titulo_da_pergunta(text), public._agenda_saiu_da_equipe(uuid)
  from public, anon, authenticated, service_role;
