-- Agenda de Produção, Fase 7, etapa 7d ("onde, quando e com o bem em que estado"), pacote P8: o que o dono lê do local, a ficha e a saúde.
-- Spec: spec-fase7d.md §5.8, §6.2, §6.4, §11, com R1, R6.1, R6.3-11, R6.3-12, R6.9-1 e R6.10. Notas: notas-fase7d.md, seção P8.
-- Depende de 20261107100000 a 20261107100600.
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (7 funções recriadas e 4 novas; nenhuma tabela, nenhuma coluna, nenhum dado)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7d/p8/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA (o montador para se outra
-- migration a definir depois da origem) e só ganha blocos inseridos: tirados os blocos, é a origem, byte a byte (o V6 de supabase/tests/agenda_fase7d_leituras.sql confere). A
-- exceção é _agenda_local_da_os: a 1ª linha do select virou 2, com o bloco no meio; o texto dela é o mesmo (language sql, um select só).
--
-- O QUE MUDA:
--   1. Nova _agenda_local_bloco: o que se diz do local de uma OS, num lugar só (o foco e o cartão): o local e a fonte, o bem, a viagem, o que combinar, as notas e as suposições.
--   2. Nova _agenda_ver_locais: o foco locais de agenda_ver (*agenda locais*), §6.2. Definer, com a porta dentro (R6.3-12): lê _agenda_local_conflitos e _agenda_combinar_da_os,
--      que são só do service_role. Molde: _agenda_ver_habilidades.
--   3. Nova _agenda_saude_local: a chave local de agenda_saude, §11 (R6.3-11: o molde de _agenda_saude_equipe7b, uma função própria e uma linha em v_gr).
--   4. agenda_ver: o foco locais, antes da conferência dos 19 (R6.9-9), no molde do foco habilidades.
--   5. os_plano_da_os: o bloco local do cartão. Nulo com os 6 modos desligados e na OS concluída, faturada ou cancelada (o resto do cartão, byte a byte).
--   6. _agenda_local_da_os: o texto_equipe (só quando NÃO é suposição); sem ele, o de hoje, byte a byte. A ficha a chama de definer. Nas 128 OS de produção, 0 diferentes (P3).
--   7. agenda_equipe_ficha (R1, R6.9-1, AG7-14): com modo_local_autorizacao ligado, o dia em local de terceiro sem o acesso combinado ganha " O acesso na {local} ainda não está
--      confirmado: eu te aviso.", antes do "Responde OK", em texto_ficha (nas 2 saídas) e em texto_curto (descontada dos 590 na saída da 7c). texto_confirmar não muda.
--   8. agenda_saude: a chave local, com os zeros no ok; onde_fica em tipos_liberados (o recado do P6).
--   9. _agenda_cliente_da_os: a resposta ao M11 no cartão diz "disse onde fica, e eu anotei e perguntei a você", não "disse o acesso, e eu anotei na OS" (o recado do P6: cópia pequena).
--  10. agenda_rascunho_aplicar (de 20261107100550) e _agenda_disse_em_palavras (nova): os evals acharam o que a bancada do P6b não via. Com mais de uma pergunta esperando, a régua do "número nas
--      palavras" recusava "lança meia pro Roberto" e "na decisão do aviso do Nelson, pode mandar": o dono respondeu, e o modelo achou os números pela lista, como o prompt manda. A régua fica
--      para o número solto; quando as palavras dizem a pergunta e a opção, ela não se aplica. "pode ser" continua perguntando. Vale na hora em que entra, sem modo, como a 20261107100550.
--
-- SOMBRA: com os 6 modos desligados, o bloco local é nulo. A FICHA MUDA COM O LOCAL DITO, SEM MODO (correção C4): _agenda_local_da_os lê o que o dono gravou em qualquer modo, e a ficha passa a dizer
-- o lugar dele; é de propósito, para o dono e a equipe lerem o mesmo lugar, e está no roteiro. O que espera o modo é a frase do acesso (o texto novo à equipe espera o "OK ligar o preparo do
-- acesso", R6.11); o foco, o cartão e a saúde são leituras do dono, a pedido. Nenhuma função daqui está no caminho da vigia, e nada novo sai a ninguém
-- (R6.8). Texto novo à equipe: 1, atrás do modo. Ao cliente: nenhum.
--
-- O QUE NÃO MUDA: _agenda_mudancas (R6.3-6: a ação local só entra com origem vigia, e só em teste); _agenda_rotina_ficha; os `_agenda_vigia_*`; texto_confirmar; _agenda_chave_telefone,
-- agenda_dia_util, agenda_somar_du, agenda_feriado, _agenda_cliente_dia e _agenda_nome_curto, que a sessão do retorno chama.
--
-- PROVA: supabase/tests/agenda_fase7d_leituras.sql na bancada (node scripts/bancada-agenda/rodar.mjs). APLICAR: só pelo roteiro de publicação da 7d, depois da 20261107100600.
-- IDEMPOTENTE: create or replace function, revoke, grant e comment.
--
-- DESFAZER: recriar agenda_ver de 20261102100500, os_plano_da_os e agenda_saude de 20261101100400, _agenda_local_da_os de 20261026100300, agenda_equipe_ficha de 20261102100550 e
-- _agenda_cliente_da_os de 20261029100700 e agenda_rascunho_aplicar de 20261107100550; drop de _agenda_ver_locais, _agenda_saude_local, _agenda_local_bloco e _agenda_disse_em_palavras. Quem recriar
-- depois uma destas copia DESTA migration.

-- ── 1. O bloco do local de uma OS ─────────────────────────────────────────────────────────────────
create or replace function public._agenda_local_bloco(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  v_mc    text := public._agenda_local_modo('calendario');
  v_ma    text := public._agenda_local_modo('acesso');
  v_mb    text := public._agenda_local_modo('bem');
  v_mp    text := public._agenda_local_modo('patio');
  v_mv    text := public._agenda_local_modo('viagem');
  v_ml    text := public._agenda_local_modo('mesmo_local');
  v_modos text[];
  v_lr    jsonb;
  v_vi    jsonb;
  v_vtxt  text;
  v_bem   jsonb;
  v_au    jsonb;
  v_cmb   jsonb;
  v_perg  date;
  v_tr    text;
  v_notas text[] := '{}';
  v_sup   text[] := '{}';
  v_vagas int;
begin
  v_modos := array[v_mc, v_ma, v_mb, v_mp, v_mv, v_ml];
  if 'sombra' <> all (v_modos) and 'ligado' <> all (v_modos) then
    return null;   -- os 6 desligados: nada disto existe para o dono (§3.2)
  end if;
  v_lr := public._agenda_local_resolvido(p_os, p_hoje);
  if v_lr is null then
    return null;
  end if;

  -- O barco cadastrado noutro lugar, ou a marina da OS fora do cadastro (NOVO-agenda-63)
  if nullif(v_lr ->> 'nota_bem', '') is not null then
    v_notas := v_notas || (public._agenda_maiuscula(v_lr ->> 'nota_bem') || '.');
  end if;
  -- "Na casa do cliente" não vira local (§5.7, NOVO-agenda-93): só o trecho guarda. O dono lê o que ele disse, ao lado do que a agenda ainda supõe.
  select pl.trecho into v_tr from public.os_planejamento pl where pl.service_order_id = p_os;
  if v_lr ->> 'fonte' in ('patio', 'cidade', 'nenhum') and public._agenda_normal(v_tr) ~ '\mcasa (do cliente|dele|dela)\M' then
    v_notas := v_notas || 'Você disse: na casa do cliente (anotei).'::text;
  end if;

  if v_mv <> 'desligado' then
    v_vi := public._agenda_viagem_da_os(p_os, p_hoje, v_lr);
    if v_vi ->> 'tipo' <> 'regional' then
      v_vtxt := case when v_mv = 'sombra' then 'Em teste: ' || lower(left(v_vi ->> 'texto', 1)) || substr(v_vi ->> 'texto', 2) else v_vi ->> 'texto' end;
    end if;
  end if;

  if v_mb <> 'desligado' then
    v_bem := public._agenda_estado_do_bem(p_os, p_hoje);
    -- "supus o motorhome na MP Motorhomes" é o que o texto do local já diz
    v_sup := v_sup || array(select x from jsonb_array_elements_text(coalesce(v_bem -> 'suposicoes', '[]'::jsonb)) x where x !~ '^supus o (motorhome|barco|bem) n[ao] ');
  end if;

  if v_ma <> 'desligado' then
    v_au := public._agenda_autorizacao_da_os(p_os, p_hoje, v_lr);
    if jsonb_array_length(coalesce(v_au -> 'nomes', '[]'::jsonb)) > 0 then
      v_notas := v_notas || (v_au ->> 'texto');
    end if;
  end if;

  -- As regras que ainda são nota. Um dia só basta: as notas não dependem da janela.
  v_notas := v_notas || array(select x from jsonb_array_elements_text(coalesce(public._agenda_local_mascara(p_os, p_hoje, p_hoje, p_hoje, v_lr) -> 'notas', '[]'::jsonb)) x);

  -- O que o motor supôs na última montagem desta OS: as chaves só existem com os modos ligados (R6.8-3). A do local e a da viagem já estão no texto.
  if 'ligado' = any (v_modos) then
    v_sup := v_sup || array(
      select x
        from (select i -> 'suposicoes' as s
                from public.agenda_propostas pr
               cross join lateral jsonb_array_elements(coalesce(pr.itens, '[]'::jsonb)) i
               where i ->> 'os' = p_os::text and i ? 'suposicoes'
               order by pr.criada_em desc, pr.id desc limit 1) u
       cross join lateral jsonb_array_elements_text(u.s) x
       where x !~ '^supus o (motorhome|barco|bem) n[ao] ' and x !~ ': supus ' and x is distinct from v_lr ->> 'texto');
  end if;
  -- As suposições, como frase: a maiúscula e o ponto (no item da proposta elas vão em minúscula e sem ponto, §6.2)
  v_sup := array(select public._agenda_maiuscula(x) || case when right(x, 1) = '.' then '' else '.' end from unnest(v_sup) with ordinality u(x, o) order by u.o);
  v_notas := array(select y.x from (select u.x, min(u.o) as o from unnest(v_notas || v_sup) with ordinality u(x, o) group by u.x) y order by y.o);

  select coalesce(jsonb_agg(jsonb_build_object('texto', e ->> 'texto', 'ate', e ->> 'ate', 'vencido', (e ->> 'vencido')::boolean,
                                               'em_teste', e ->> 'modo' <> 'ligado') order by o), '[]'::jsonb)
    into v_cmb
    from jsonb_array_elements(public._agenda_combinar_da_os(p_os, p_hoje)) with ordinality t(e, o)
   where not (e ->> 'combinado')::boolean and e ->> 'modo' <> 'desligado'
     and (e ->> 'para')::date > p_hoje;   -- no dia, não há mais o que combinar (a régua de _agenda_local_combinar)

  -- "Perguntei" só com o M11 que saiu de verdade (a lição do plano falso; a nota do P3, item 7)
  if v_lr ->> 'fonte' not in ('dono', 'cliente') then
    select (coalesce(m.enviada_em, m.enviar_em) at time zone 'America/Sao_Paulo')::date into v_perg
      from public.agenda_cliente_mensagens m
     where m.service_order_id = p_os and m.tipo = 'onde_fica' and m.modo = 'ligado' and m.estado in ('enviada', 'respondida', 'sem_resposta')
     order by coalesce(m.enviada_em, m.enviar_em) desc limit 1;
  end if;

  if v_lr ->> 'local_id' is not null then
    select l.vagas into v_vagas from public.agenda_locais l where l.id = (v_lr ->> 'local_id')::uuid;
  end if;

  return jsonb_build_object(
    'texto', v_lr ->> 'texto', 'fonte', v_lr ->> 'fonte', 'suposicao', v_lr -> 'suposicao', 'tipo', v_lr ->> 'tipo', 'nome', v_lr ->> 'nome', 'vagas', v_vagas,
    'viagem_texto', v_vtxt, 'bem_texto', v_bem ->> 'texto',
    'perguntei', case when v_perg is not null then format('Perguntei ao cliente em %s.', to_char(v_perg, 'DD/MM')) end,
    'combinar', v_cmb, 'notas', to_jsonb(v_notas));
end;
$function$;

comment on function public._agenda_local_bloco(uuid, date) is
  'Agenda de Produção (Fase 7d, P8; §5.8, §6.2): o que se diz do local de uma OS, num lugar só, para o foco locais e o cartão: {texto, fonte, suposicao, tipo, nome, vagas, viagem_texto (só fora da região; "Em teste: …" com modo_viagem em sombra), bem_texto, perguntei (só com o M11 que saiu), combinar [{texto, ate, vencido, em_teste}] (o que falta, sem o que está combinado nem o tipo com o modo desligado), notas [] (o barco noutro lugar, "na casa do cliente", os autorizados, as regras ainda não conferidas, as suposições do bem e, com algum modo ligado, as do motor na última montagem da OS)}. Null com os 6 modos desligados e na OS que não existe. Todo modo por _agenda_local_modo. STABLE, invoker, sem grant: quem chama é definer (_agenda_ver_locais e os_plano_da_os).';

-- ── 2. O foco locais (§6.2) ───────────────────────────────────────────────────────────────────────
create or replace function public._agenda_ver_locais(p_hoje date, p_os uuid default null)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_semanas constant int := 3;    -- estrutural: as próximas 3 semanas (§6.2)
  c_linha   constant int := 400;  -- estrutural: o teto de cada linha (§6.2)
  c_nomes   constant int := 3;    -- estrutural: quantos locais a linha do cadastro cita (o resto: "e mais N")
  c_teste   constant int := 3;    -- estrutural: quantas linhas "Em teste" o texto mostra (em_teste leva todas)
  cf        public.agenda_config;
  v_uid     uuid := auth.uid();
  v_papel   text;
  v_mc      text;
  v_ma      text;
  v_mp      text;
  v_mv      text;
  v_modos   text[];
  v_ate     date;
  r         record;
  e         jsonb;
  v_b       jsonb;
  v_rot     text;
  v_linha   text;
  v_lig     text[];
  v_tes     text[];
  v_n       text;
  v_nome    text;
  v_resto   text;
  v_lin     jsonb := '[]'::jsonb;
  v_l       text[] := '{}';
  v_fora    text[] := '{}';
  v_pat     text;
  v_pn      int := 0;
  v_pnome   text;
  v_total   int;
  v_dono    text[];
  v_mar     int;
  v_notas   text[];
  v_cad     text;
  v_cadj    jsonb;
  v_teste   text[] := '{}';
  v_rodape  text[];
  v_final   text[];
  v_cab     text;
  v_corte   int;
begin
  -- Quem vê: com login, só admin/financeiro; sem login, só o service_role (o WhatsApp do dono).
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'Os locais dos serviços são com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'Os locais dos serviços são com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;
  if p_hoje is null then
    raise exception '_agenda_ver_locais: p_hoje é obrigatório.' using errcode = '22004';
  end if;
  cf := public._agenda_cfg();
  v_mc := public._agenda_local_modo('calendario');
  v_ma := public._agenda_local_modo('acesso');
  v_mp := public._agenda_local_modo('patio');
  v_mv := public._agenda_local_modo('viagem');
  v_modos := array[v_mc, v_ma, public._agenda_local_modo('bem'), v_mp, v_mv, public._agenda_local_modo('mesmo_local')];
  if 'sombra' <> all (v_modos) and 'ligado' <> all (v_modos) then
    return jsonb_build_object('ok', true, 'texto', 'Os locais ainda estão desligados na agenda.', 'linhas', '[]'::jsonb, 'cadastro', '{}'::jsonb, 'em_teste', '[]'::jsonb);
  end if;

  -- ── uma linha por OS: a da carteira com plano ou reserva nas próximas semanas, ou só a p_os ──
  v_ate := p_hoje + 7 * c_semanas;
  for r in
    select x.os from (
      select k.service_order_id as os, min(a.dia) as ini
        from public.os_carteira(p_hoje) k
        join public.agenda_alocacoes a on a.service_order_id = k.service_order_id
       where p_os is null and a.estado in ('publicada', 'fixada') and a.dia between p_hoje and v_ate
       group by 1
      union all
      select p_os, null::date where p_os is not null) x
     order by x.ini, public._agenda_rotulo_da_os(x.os), x.os
  loop
    v_b := public._agenda_local_bloco(r.os, p_hoje);
    continue when v_b is null;
    v_rot := public._agenda_rotulo_da_os(r.os);
    v_lig := array(select c ->> 'texto' from jsonb_array_elements(v_b -> 'combinar') with ordinality t(c, o) where not (c ->> 'em_teste')::boolean order by o);
    v_tes := array(select c ->> 'texto' from jsonb_array_elements(v_b -> 'combinar') with ordinality t(c, o) where (c ->> 'em_teste')::boolean order by o);
    v_linha := concat_ws(' ', format('%s: %s.', v_rot, v_b ->> 'texto'), v_b ->> 'bem_texto', v_b ->> 'perguntei', v_b ->> 'viagem_texto',
                         case when cardinality(v_lig) > 0 then 'Combinar: ' || array_to_string(v_lig, '; ') || '.' end,
                         case when cardinality(v_tes) > 0 then 'Em teste, eu cobraria: ' || array_to_string(v_tes, '; ') || '.' end);
    -- As notas por último, inteiras, só as que cabem: o que falta combinar nunca sai por causa delas
    for v_n in select x from jsonb_array_elements_text(v_b -> 'notas') with ordinality t(x, o) order by o loop
      if char_length(v_linha) + 1 + char_length(v_n) <= c_linha then
        v_linha := v_linha || ' ' || v_n;
      end if;
    end loop;
    v_linha := public._agenda_corta(v_linha, c_linha - 1);   -- o "…" conta nas 400
    v_l := v_l || (case when p_os is null then '- ' else '' end || v_linha);
    v_lin := v_lin || jsonb_build_object('os', r.os, 'rotulo', v_rot, 'local', v_b, 'texto', v_linha);
    if v_mp <> 'desligado' and v_b ->> 'tipo' like 'patio\_%' and v_b -> 'vagas' = 'null'::jsonb then
      v_pn := v_pn + 1;
      v_pnome := v_b ->> 'nome';
    end if;
  end loop;

  -- ── quem ficou de fora porque o pátio encheu: a última montagem que citou a OS (só com modo_patio ligado: o motor só diz isso ligado) ──
  if v_mp = 'ligado' then
    v_fora := array(
      select '- ' || (z.f ->> 'texto')
        from (select distinct on (y.os) y.f, y.criada_em, y.os
                from (select (f ->> 'os')::uuid as os, f, pr.criada_em, pr.id
                        from public.agenda_propostas pr cross join lateral jsonb_array_elements(coalesce(pr.fora, '[]'::jsonb)) f
                      union all
                      select (i ->> 'os')::uuid, null::jsonb, pr.criada_em, pr.id
                        from public.agenda_propostas pr cross join lateral jsonb_array_elements(coalesce(pr.itens, '[]'::jsonb)) i) y
               where (y.criada_em at time zone 'America/Sao_Paulo')::date <= p_hoje
                 and y.os in (select k.service_order_id from public.os_carteira(p_hoje) k where p_os is null or k.service_order_id = p_os)
               order by y.os, y.criada_em desc, y.id desc) z
       where coalesce((z.f ->> 'patio_cheio')::boolean, false)
       order by z.criada_em, z.os);
  end if;

  -- ── o cadastro ──
  select count(*)::int into v_total from public.agenda_locais l where l.ativo;
  v_dono := array(select format('%s, em %s', l.nome, to_char(l.conferido_em, 'DD/MM'))
                    from public.agenda_locais l
                   where l.ativo and l.conferido_por = 'dono' and public._agenda_local_conferido(l.id, p_hoje)
                   order by l.conferido_em desc, l.nome);
  select count(*)::int into v_mar from public.agenda_locais l where l.ativo and l.conferido_por = 'marina' and public._agenda_local_conferido(l.id, p_hoje);
  v_notas := array(
    select format('%s %s (%s)', y.nome, public._agenda_lista(y.f, null), case when y.conferido_por = 'pesquisa' then 'pesquisa' else 'a conferir de novo' end)
      from (select l.nome, l.conferido_por, l.conferido_em,
                   array_remove(array[case when l.exige_autorizacao then 'pede autorização' end,
                                      case when l.seguro_exigido then 'pede seguro' end,
                                      case l.sabado when 'nao' then 'não abre no sábado' when 'manha' then 'no sábado só abre de manhã' when 'dia' then 'abre no sábado' end,
                                      case when l.tem_garagem_seca then 'tem garagem seca' end], null) as f
              from public.agenda_locais l
             where l.ativo and l.conferido_por is not null and not public._agenda_local_conferido(l.id, p_hoje)) y
     where cardinality(y.f) > 0
     order by y.conferido_em desc, y.nome);
  v_cad := format('Locais: %s no cadastro; ', v_total)
           || case cardinality(v_dono) when 0 then 'nenhum conferido por você'
                when 1 then format('1 conferido por você (%s)', v_dono[1])
                else format('%s conferidos por você (%s%s)', cardinality(v_dono), array_to_string(v_dono[1:c_nomes], '; '),
                            case when cardinality(v_dono) > c_nomes then format('; e mais %s', cardinality(v_dono) - c_nomes) else '' end) end
           || case when v_mar > 0 then format(', %s pela marina', v_mar) else '' end || '.'
           || case when cardinality(v_notas) > 0
                   then ' Só como nota: ' || array_to_string(v_notas[1:c_nomes], '; ')
                        || case when cardinality(v_notas) > c_nomes then format('; e mais %s', cardinality(v_notas) - c_nomes) else '' end || '.'
                   else '' end;
  v_cadj := jsonb_build_object('locais', v_total, 'conferidos', cardinality(v_dono) + v_mar, 'nomes', to_jsonb(v_dono), 'notas', to_jsonb(v_notas));
  if v_pn > 0 then
    v_pat := format('%s: %s nas próximas %s semanas (sem número de vagas, só conto).', v_pnome, public._agenda_plural(v_pn, 'serviço', 'serviços'), c_semanas);
  end if;

  -- ── o que eu faria com os modos ligados ──
  if 'sombra' = any (array[v_mc, v_ma, v_mp, v_mv]) then
    for e in select x from jsonb_array_elements(public._agenda_local_conflitos(p_hoje)) with ordinality t(x, o) order by o loop
      continue when p_os is not null and (e ->> 'os')::uuid is distinct from p_os;
      v_rot := public._agenda_rotulo_da_os((e ->> 'os')::uuid);
      v_nome := split_part(v_rot, ' (', 1);
      -- o motivo sem o dia: "ter 20/07 é feriado em X", "sáb 24/07: X não abre no sábado", "ter 20/07 de manhã: X não recebe a equipe"
      v_resto := regexp_replace(e ->> 'motivo', '^.*?(: | é )', '');
      if e ->> 'tipo' = 'calendario' and v_mc = 'sombra' and (e ->> 'origem' = 'mascara' or v_mp <> 'desligado') then
        v_teste := v_teste || format('Em teste: com o calendário do local ligado, eu não marcaria %s para %s (%s).',
                                     case when e ->> 'turno' is not null then public._agenda_meio_texto((e ->> 'dia')::date, e ->> 'turno')
                                          else public._dia_curto((e ->> 'dia')::date) end, v_nome, v_resto);
      elsif e ->> 'tipo' = 'acesso' and v_ma = 'sombra' then
        v_teste := v_teste || format('Em teste: eu perguntaria a você hoje sobre %s: %s.', v_rot, e ->> 'motivo');
      elsif e ->> 'tipo' = 'patio' and v_mp = 'sombra' then
        v_teste := v_teste || format('Em teste: com o pátio ligado, eu não marcaria %s para %s: %s.', public._dia_curto((e ->> 'dia')::date), v_nome, v_resto);
      elsif e ->> 'tipo' = 'viagem' and v_mv = 'sombra' then
        v_teste := v_teste || format('Em teste: com a viagem ligada, eu remarcaria %s: %s.', v_rot, e ->> 'motivo');
      end if;
    end loop;
  end if;

  -- O que vem depois das linhas das OS. O corte tira as linhas de OS do fim ("- e mais N serviços."): o cadastro e o "Em teste" ficam; só depois, o corte de sempre (_agenda_juntar).
  v_rodape := v_teste[1:c_teste];
  if cardinality(v_teste) > c_teste then
    v_rodape := v_rodape || format('Em teste: e mais %s.', cardinality(v_teste) - c_teste);
  end if;
  if cardinality(v_l) = 0 and cardinality(v_fora) = 0 then
    v_final := array[format('Nenhum serviço marcado nas próximas %s semanas. %s', c_semanas, v_cad)] || v_rodape;
  elsif p_os is not null then
    v_final := v_l || v_fora || v_rodape;
  else
    v_rodape := v_fora || v_cad || coalesce(v_pat, '') || v_rodape;
    v_cab := format('Onde é cada serviço (próximas %s semanas):', c_semanas);
    for v_corte in 0 .. cardinality(v_l) loop
      v_final := array[v_cab] || v_l[1:cardinality(v_l) - v_corte]
                 || case when v_corte > 0 then array[format('- e mais %s.', public._agenda_plural(v_corte, 'serviço', 'serviços'))] else '{}'::text[] end || v_rodape;
      exit when char_length(array_to_string(v_final, E'\n')) <= cf.texto_max;
    end loop;
  end if;
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_final, cf.texto_max), 'linhas', v_lin, 'cadastro', v_cadj, 'em_teste', to_jsonb(v_teste));
end;
$function$;

comment on function public._agenda_ver_locais(date, uuid) is
  'Agenda de Produção (Fase 7d, P8; §5.8, §6.2; R6.3-12): o foco locais de agenda_ver (*agenda locais*). "Onde é cada serviço (próximas 3 semanas):", uma linha por OS da carteira com plano ou reserva nessas semanas, a que começa primeiro antes (até 400 letras, de _agenda_local_bloco: o local e a fonte, o bem, "Perguntei ao cliente em 15/07." só com o M11 que saiu, a viagem fora da região, "Combinar: …" do que tem o modo ligado, "Em teste, eu cobraria: …" do que está em teste, e as notas que couberem); quem ficou de fora porque o pátio encheu (modo_patio ligado); o cadastro ("Locais: 6 no cadastro; 1 conferido por você (Marina Itajaí, em 01/07). Só como nota: …"); sem vagas ditas, quantos serviços no pátio (só conta); e, com algum modo em teste, o que eu faria (_agenda_local_conflitos: "Em teste: com o calendário do local ligado, eu não marcaria ter 20/07 para Lenine (feriado em Balneário Camboriú)."), até 3 no texto. Sem nada: "Nenhum serviço marcado nas próximas 3 semanas. Locais: …". Com p_os, só a OS, sem o cadastro. Com os 6 modos desligados, "Os locais ainda estão desligados na agenda.". {ok, texto (até texto_max), linhas [{os, rotulo, local, texto}], cadastro {locais, conferidos, nomes, notas}, em_teste []}. Só lê. STABLE; definer (o combinar e os conflitos são só do service_role), com a porta dentro (com login, só admin/financeiro: 42501; sem login, só o service_role); authenticated e service_role (agenda_ver, invoker, a chama).';

-- ── 3. A saúde do local (§11) ─────────────────────────────────────────────────────────────────────
create or replace function public._agenda_saude_local(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_atraso  constant interval := interval '26 hours';  -- estrutural: §11, aceite 8
  c_resp    constant interval := interval '48 hours';  -- estrutural: §11, "respondidos em 48 h"
  c_janela  constant int := 30;    -- estrutural: a janela dos números
  c_semana  constant int := 7;     -- estrutural: os dias perdidos, "por semana" (§11)
  c_plano   constant int := 21;    -- estrutural: as próximas 3 semanas, como o foco
  c_de_terceiro constant text[] := array['marina', 'estaleiro', 'patio_parceiro', 'casa_cliente', 'outro'];  -- R1: o pátio da HBR não é de terceiro
  cf        public.agenda_config;
  v_uid     uuid := auth.uid();
  v_papel   text;
  v_mc      text;
  v_ma      text;
  v_mp      text;
  v_mv      text;
  v_modos   jsonb;
  v_algum   boolean;
  v_ult     timestamptz;
  v_rod24   int;
  v_cal     timestamptz;
  v_hoje_r  boolean;
  v_base    timestamptz;
  v_conf    jsonb := '[]'::jsonb;
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
    raise exception '_agenda_saude_local: sem o dia de hoje ou a hora' using errcode = '22004';
  end if;
  cf := public._agenda_cfg();
  v_mc := public._agenda_local_modo('calendario');
  v_ma := public._agenda_local_modo('acesso');
  v_mp := public._agenda_local_modo('patio');
  v_mv := public._agenda_local_modo('viagem');
  v_modos := jsonb_build_object('calendario', v_mc, 'acesso', v_ma, 'bem', public._agenda_local_modo('bem'), 'patio', v_mp, 'viagem', v_mv,
                                'mesmo_local', public._agenda_local_modo('mesmo_local'));
  v_algum := exists (select 1 from jsonb_each_text(v_modos) m where m.value <> 'desligado');

  select max(r.p_agora), count(*) filter (where r.p_agora > p_agora - interval '1 day' and r.p_agora <= p_agora)
    into v_ult, v_rod24
    from public.agenda_vigia_rodadas r
   where r.rotina = 'local' and r.p_agora <= p_agora;
  -- A rodada com o passo calendario, o único que tira: o que entrou depois dela ainda tem a rodada de amanhã (R6.8-4)
  select max(r.p_agora) into v_cal
    from public.agenda_vigia_rodadas r
   where r.rotina = 'local' and r.p_agora <= p_agora and r.contagens ? 'calendario';
  -- A crítica de D-1 nasce na rodada do dia: antes dela, o dia ainda não está sem preparo
  v_hoje_r := exists (select 1 from public.agenda_vigia_rodadas r where r.rotina = 'local' and r.p_hoje = p_hoje and r.p_agora <= p_agora);
  -- Antes da 1ª rodada, conta do dia do dado (onde_fica_desde), à local_hora: publicar à noite não pode acusar atraso
  v_base := coalesce(v_ult, (cf.onde_fica_desde + cf.local_hora) at time zone 'America/Sao_Paulo');

  if v_algum then
    v_conf := public._agenda_local_conflitos(p_hoje);
  end if;

  v_z := jsonb_build_object(
    -- o dia de OS em local de terceiro na véspera, sem o acesso combinado e sem a pergunta acesso (R1), depois da rodada do dia
    'acesso_sem_preparo', case when v_ma <> 'ligado' or not v_hoje_r then 0 else
      (select count(*) from jsonb_array_elements(v_conf) e
        where e ->> 'tipo' = 'acesso'
          and not exists (select 1 from public.agenda_perguntas q
                           where q.chave = format('acesso:%s:%s', e ->> 'os', e ->> 'dia') and q.modo = 'ligado' and q.estado = 'aberta')) end,
    -- o serviço em feriado do município do local, que já estava lá na última rodada com o passo calendario; o que o dono fixou fica de fora: foi ele que marcou
    'feriado_local_marcado', case when v_mc <> 'ligado' or v_cal is null then 0 else
      (select count(*) from jsonb_array_elements(v_conf) e
        where e ->> 'tipo' = 'calendario' and e ->> 'origem' = 'mascara' and not (e ->> 'fica')::boolean and e ->> 'motivo' like '% é feriado em %'
          and exists (select 1 from public.agenda_alocacoes a
                       where a.id in (select x::uuid from jsonb_array_elements_text(e -> 'alocacoes') x) and a.publicada_em < v_cal)) end,
    'patio_acima_das_vagas', case when v_mp <> 'ligado' then 0 else
      (select count(*) from jsonb_array_elements(v_conf) e where e ->> 'tipo' = 'patio') end,
    'viagem_quebrada', case when v_mv <> 'ligado' then 0 else
      (select count(*) from jsonb_array_elements(v_conf) e where e ->> 'tipo' = 'viagem') end,
    -- nenhuma rodada em 26 h, com algum modo fora de desligado
    'rodada_local_atrasada', case when v_algum and v_base < p_agora - c_atraso then 1 else 0 end);

  -- Os números (§11). Fora de todo modo não há o que contar.
  if v_algum then
    with os_plano as (
      select a.service_order_id as os, min(a.dia) as d1
        from public.agenda_alocacoes a
       where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
       group by 1
      having min(a.dia) between p_hoje - c_janela and p_hoje)
    select jsonb_build_object(
             'ate_d2', count(*) filter (where y.ok is not null and y.ok <= public.agenda_somar_du(y.d1, -cf.autorizacao_antecedencia_du)),
             'so_d1', count(*) filter (where y.ok > public.agenda_somar_du(y.d1, -cf.autorizacao_antecedencia_du) and y.ok < y.d1),
             'sem_acesso', count(*) filter (where y.ok is null or y.ok >= y.d1))
      into v_n
      from (select o.d1, (pl.acesso_ok_em at time zone 'America/Sao_Paulo')::date as ok
              from os_plano o
              left join public.os_planejamento pl on pl.service_order_id = o.os
             where public._agenda_local_resolvido(o.os, p_hoje) ->> 'tipo' = any (c_de_terceiro)) y;
    v_n := jsonb_build_object('acesso', v_n);

    v_n := v_n || jsonb_build_object(
      'dias_perdidos_semana', (select count(distinct (a.service_order_id, a.dia))
                                 from public.agenda_alocacoes a
                                where a.resultado = 'nao_cumprido' and a.motivo = 'cliente_ou_bem' and a.dia > p_hoje - c_semana and a.dia <= p_hoje
                                  and public._agenda_local_resolvido(a.service_order_id, p_hoje) ->> 'tipo' in ('marina', 'estaleiro')),
      'feriado_em_teste', (select count(*) from jsonb_array_elements(v_conf) e where e ->> 'motivo' like '% é feriado em %'),
      'mesmo_local', (
        with dias as (
          select distinct a.service_order_id as os, a.dia
            from public.agenda_alocacoes a
           where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia between p_hoje and p_hoje + c_plano),
        chaves as (
          select t.os, public._agenda_local_resolvido(t.os, p_hoje) ->> 'chave' as chave from (select distinct os from dias) t),
        pares as (
          select x.os as a, y.os as b,
                 exists (select 1 from dias d1 join dias d2 on d2.dia = d1.dia where d1.os = x.os and d2.os = y.os) as juntos
            from chaves x join chaves y on y.chave = x.chave and x.os < y.os
           where exists (select 1 from dias d1 join dias d2 on date_trunc('week', d2.dia) = date_trunc('week', d1.dia) where d1.os = x.os and d2.os = y.os))
        select jsonb_build_object('pares', count(*), 'juntos', count(*) filter (where juntos)) from pares),
      'carteira', (
        select jsonb_build_object('supostas', count(*) filter (where (z.l ->> 'suposicao')::boolean or z.l ->> 'fonte' = 'nenhum'),
                                  'pelo_cliente', count(*) filter (where z.l ->> 'fonte' = 'cliente'))
          from (select public._agenda_local_resolvido(k.service_order_id, p_hoje) as l from public.os_carteira(p_hoje) k) z),
      'm11', (
        select jsonb_build_object(
                 'enviados', count(*),
                 'respondidos_48h', count(*) filter (where exists (select 1 from public.agenda_cliente_respostas a
                                                                    where a.mensagem_id = m.id and a.recebida_em <= m.enviada_em + c_resp)),
                 'com_leitura', (select count(*) from public.agenda_perguntas q where q.tipo = 'local' and q.criada_em > p_agora - make_interval(days => c_janela)
                                                                                 and jsonb_array_length(q.opcoes) > 1),
                 'sem_leitura', (select count(*) from public.agenda_perguntas q where q.tipo = 'local' and q.criada_em > p_agora - make_interval(days => c_janela)
                                                                                 and jsonb_array_length(q.opcoes) <= 1))
          from public.agenda_cliente_mensagens m
         where m.tipo = 'onde_fica' and m.modo = 'ligado' and m.estado in ('enviada', 'respondida', 'sem_resposta')
           and m.enviada_em > p_agora - make_interval(days => c_janela)),
      'combinar', (
        select jsonb_build_object('abertas', count(*) filter (where q.estado = 'aberta'),
                                  'combinadas', count(*) filter (where (q.estado = 'respondida' and q.opcao_escolhida = 1)
                                                                       or q.resolvida_motivo in ('já foi combinado', 'o acesso foi anotado', 'a autorização foi anotada')),
                                  'vencidas', count(*) filter (where q.resolvida_motivo = 'o dia passou'))
          from public.agenda_perguntas q
         where q.tipo = 'combinar' and q.modo = 'ligado' and q.criada_em > p_agora - make_interval(days => c_janela)));
  end if;

  return jsonb_build_object(
    'modos', v_modos, 'onde_fica_desde', cf.onde_fica_desde,
    'ultima_rodada', v_ult, 'rodadas_24h', coalesce(v_rod24, 0),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.action like 'local:%' and e.last_seen_at >= least(p_agora, now()) - interval '1 day'),
    'zeros_ok', not exists (select 1 from jsonb_each(v_z) z where (z.value)::text <> '0'),
    'numeros', v_n) || v_z;
end;
$function$;

comment on function public._agenda_saude_local(date, timestamptz) is
  'Agenda de Produção (Fase 7d, P8; §11; R1; R6.3-11): a saúde do local, a chave local de agenda_saude — {modos (os 6, efetivos), onde_fica_desde, ultima_rodada, rodadas_24h, erros_24h (app_error_logs context agenda, action local:%), zeros_ok, numeros {acesso {ate_d2, so_d1, sem_acesso} (as OS em local de terceiro que começaram nos últimos 30 dias), dias_perdidos_semana, feriado_em_teste, mesmo_local {pares, juntos}, carteira {supostas, pelo_cliente}, m11 {enviados, respondidos_48h, com_leitura, sem_leitura}, combinar {abertas, combinadas, vencidas}}} || os zeros obrigatórios: acesso_sem_preparo (modo ligado, depois da rodada do dia: a véspera sem acesso e sem a pergunta acesso aberta), feriado_local_marcado (modo ligado: serviço em feriado do município que já estava lá na última rodada com o passo calendario, fora o que o dono fixou), patio_acima_das_vagas, viagem_quebrada (modos ligados) e rodada_local_atrasada (algum modo fora de desligado e nenhuma rodada em 26 h; antes da 1ª, conta de onde_fica_desde à local_hora). Sem os modos, os zeros são 0 e o ok é o de antes. Modo por _agenda_local_modo: com o freio, ligado conta como em teste. STABLE; definer (os conflitos são só do service_role), com a porta dentro; authenticated e service_role (agenda_saude, invoker, a chama).';

-- ── 4. A resposta em palavras ─────────────────────────────────────────────────────────────────────
-- Nunca o modelo escolhe: aqui só se confere que as palavras do dono identificam a pergunta, entre as que esperam, e falam da opção que veio. Radical de 4 letras: "mandar" é "mando", "lança" é
-- "lançar". Fora as palavras que não dizem nada ("pode ser", "decisão", "opção"). A pergunta conta só até a 1ª opção: o texto dela traz as opções.
create or replace function public._agenda_disse_em_palavras(p_trecho text, p_pergunta text, p_opcao text, p_outras text[])
 returns boolean
 language sql
 immutable
 set search_path to 'public'
as $function$
  with d as (
    select distinct left(w, 4) as r
      from regexp_split_to_table(public._agenda_normal(normalize(p_trecho, nfc)), '[^a-z0-9]+') w
     where char_length(w) >= 4 and w <> all (array['pode', 'isso', 'esse', 'essa', 'esta', 'para', 'pela', 'pelo', 'decisao', 'opcao', 'numero', 'favor'])
  ), o as (
    select distinct left(w, 4) as r from regexp_split_to_table(public._agenda_normal(normalize(p_opcao, nfc)), '[^a-z0-9]+') w where char_length(w) >= 4
  ), q as (
    select distinct left(w, 4) as r from regexp_split_to_table(public._agenda_normal(normalize(split_part(p_pergunta, ' 1) ', 1), nfc)), '[^a-z0-9]+') w where char_length(w) >= 4
  ), x as (
    select distinct left(w, 4) as r
      from unnest(coalesce(p_outras, '{}'::text[])) u
     cross join lateral regexp_split_to_table(public._agenda_normal(normalize(split_part(u, ' 1) ', 1), nfc)), '[^a-z0-9]+') w
     where char_length(w) >= 4
  )
  select exists (select 1 from d join o on o.r = d.r)
     and exists (select 1 from d join q on q.r = d.r where d.r not in (select x.r from x));
$function$;

comment on function public._agenda_disse_em_palavras(text, text, text, text[]) is
  'Agenda de Produção (Fase 7d, P8; os evals S24 e K57): as palavras do dono identificam a pergunta, entre as que esperam (p_outras), e falam da opção? Radical de 4 letras, sem acento, fora as que não dizem nada; a pergunta só até a 1ª opção. "lança meia pro Roberto": sim; "pode ser": não; "1": não; "já combinei", com 2 perguntas de combinar: não. Quem escolhe é o dono, a releitura diz qual e só o *grava* grava. Só agenda_rascunho_aplicar chama. IMMUTABLE, invoker, sem grant.';

-- ── 5. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 7d:" e "-- (7d P8") ─────────────────
-- agenda_ver (de 20261102100500_agenda_fase7c_leituras.sql)
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
  'Agenda de Produção (Fase 1, P4; Fase 2, P5; Fase 3, P6; Fase 4, P6; Fase 5, P5): o despacho ÚNICO da ferramenta agenda_ver e dos comandos sem IA. os + simular_aprovacao → agenda_ctp; FASE 3: os + foco marcos → os 4 marcos (agenda_marcos_da_os, também fora da carteira); foco marcos sem os → pede a OS; FASE 4: os + foco compras → a espera de peça e o material da OS (_agenda_ver_compras, também fora da carteira); foco compras → o que comprar e até quando, as notas sem serviço dito, o tempo até comprar, a pergunta ao fornecedor e o detector em teste (_agenda_ver_compras); foco fornecedores → como conto o prazo de cada fornecedor (_agenda_ver_fornecedores; com ou sem os); os + foco material → agenda_ver_material; os → a visão da OS; simular {dias, com_quem, dono} → agenda_simular; FASE 2: foco decisoes → as decisões numeradas (agenda_decisoes_abertas; FASE 3: a da diária com as opções e as palavras) e o que mais a agenda quer saber; mudancas → o que mudou sozinho desde ontem com *desfaz*; plano → o publicado do período dia a dia (sombra: "Em teste"); FASE 3: ppc → agenda_ppc da semana do período; diarias → as diárias que a agenda lançou e as perguntas abertas; comissao → comissao_resumo_do_mes do mês dito em periodo ("outubro", "mês passado"; só a conta, nada é pago); equipe → o que a equipe respondeu hoje e no próximo dia útil; foco o_que_fazer → agenda_o_que_fazer (pessoa que não é o dono: o dia dela); atrasos/riscos → agenda_atrasos; material → agenda_ver_material(null); livre → resumo + livre de agenda_semana (FASE 3: com modo_proposta ligado, o livre de verdade pela simulação do motor, agenda_livre_de_verdade); aprontar → agenda_aprontar; pessoa (não o dono) + 1 dia → agenda_dia_da_pessoa; hoje/amanhã → o dia + o bloco 2 resumido; resto → agenda_semana (em ''ligado'' o marcado é o plano; FASE 3: e a frase do livre é a da simulação). periodo: hoje, amanha, semana, proxima_semana ou o que o dono disse. Referência que não existe (OS, pessoa, data, mês) → {ok:false, texto:"Não encontrei …"/a pergunta}; FASE 5: foco clientes (com ou sem os; a OS concluída também) → as mensagens ao cliente (_agenda_ver_clientes); foco fora da lista (os 18) lança 22023. Devolve {ok, texto, dados, rota}. FASE 6 (P8): foco aprendizado → o que a agenda aprendeu com o que aconteceu (_agenda_ver_aprendizado: o fator por tipo de OS, a presença do dono, os fornecedores, a capacidade do dono, o R$ por diária, o cliente e a revisão da carga, com o n de cada um, e as medidas); com login, só administrador e financeiro (42501). A lista dos focos passa a 19. CORREÇÃO 29/10 (P2): com a agenda automática ligada, o foco livre é UMA resposta, a do plano (agenda_livre_de_verdade.texto_completo: quem ainda pega serviço em cada uma das 3 semanas, pelo marcado, pelo reservado e pelo teto de cada pessoa; o que ocupa a equipe; o que não ocupa ninguém até destravar), sem a fila em faixa da Fase 1; na semana, a linha do livre (agenda_livre_de_verdade.texto) vai logo depois do marcado, no lugar da fila em faixa, e a linha do livre lá de baixo sai; simular (agenda_simular) em ligado é o encaixe do motor. Fora de ligado, tudo como antes. FASE 7 (7a P7, spec §6.2): foco gestor → o que o gestor da agenda marcou (ligado) ou marcaria (em teste) e por quê, o que perguntou antes de marcar, o que fica de fora, as compras da semana, os orçamentos que caberiam e como ele conta (_agenda_ver_gestor); com login, só administrador e financeiro (42501); desligada a leitura, a frase de sempre. A lista dos focos passa a 20. FASE 7c (P6, spec §5.6, R5.6): foco habilidades → _agenda_ver_habilidades (quem faz o quê na equipe, o que cada OS pede, o responsável, o que a agenda teria mudado em teste e as medidas; com os, só o bloco da OS), antes da conferência dos 19 (o foco que não existe continua com a mensagem dos 19, como o gestor); sem p_hoje, 22004; com login, só administrador e financeiro (42501); a leitura desligada, a frase de sempre; a OS que não existe ou é ambígua, a frase do resolvedor. FASE 7d (P8; §5.8, R6.3-12): o foco locais (_agenda_ver_locais): onde é cada serviço, o que combinar e as regras dos locais; com os, só a OS. Sem p_hoje, 22004; com login, só administrador e financeiro (42501); desligada a leitura, a frase de sempre. Fora da conferência dos 19.';

-- os_plano_da_os (de 20261101100400_agenda_fase7b_leituras.sql)
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
  return jsonb_build_object(
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
  'Agenda de Produção (Fase 3, P7a; Fase 5, P6): o cartão "Plano" da OS — {cliente (Fase 5: _agenda_cliente_da_os — o contato, o que foi dito ao cliente e se ainda vale, a confirmação, as 5 mensagens mais recentes desta OS e o que espera o dono; null sem o cliente), os, numero, status, estado, marcos (agenda_marcos_da_os), pode_entregar (concluída sem entrega), duracao {dias, fonte dono|aceita|sugerida, fonte_texto, faixa {otimista, realista}, faixa_texto, texto}, presenca_dono {valor, pela_regra, texto "Você abre e fecha (pela regra)"}, material {estado, itens:[{descricao, nivel A–E, nivel_texto, situacao, previsao, trecho, critico, fornecedor}]}, janela {bem_indisponivel, nao_antes_de, motivo, precisa_ate, nao_antes_texto, precisa_ate_texto}, prometido_planejado {precisa_ate, fim_publicado, folga_du, texto}, planejado_realizado:[{dia, rotulo, pessoas_texto, dia_texto, meios, resultado, resultado_texto, motivo_texto, diaria ("lançada" | "a confirmar" | null — nunca o valor)}], intervencoes:[{dia, texto}]}. Administrador e financeiro (com login) ou service_role; senão 42501. FASE 6 (P8): duracao.campo = a linha do fator de campo da classe da OS (agenda_fator_de_campo: "Em teste: as OS de energia em motorhome levam até 1,7× o combinado (7 OS); hoje seria 1,7×, e vale 1,5× (padrão).") — nula com modo_aprendizado desligado e na OS concluída, faturada ou cancelada; presenca_dono.aprendida = o motivo da presença aprendida ("você foi a 3 de 4 OS de energia em motorhome"; nulo sem ela), e o texto "Você fica o tempo todo (pelo que medi: …)". CORREÇÃO FASE 6 (C1, item 3): com a presença guardada na 1ª publicação, o texto diz "(pelo que medi quando planejei: …)". CORREÇÃO FASE 6 (C2, regressão B8): sem o sub no JWT, só o service_role (ou nenhum JWT); o authenticated sem sub recebe 42501. FASE 7b (P5, §5.4, §6.4, R4.3, R4.4): o bloco equipe {pessoas (as que o serviço pede fora da dupla: as da sugestão, 2 na dupla o tempo todo, as da equipe dita), dupla {inicio, fim, todos, fonte dono|regra|nenhuma, texto} (_agenda_dupla_da_os), notas [texto] (o espaço apertado: "Atenção: casa de máquinas — confira se precisa de duas pessoas."), modo, falta [{dia, turno, onde}] (os meios-dias do plano em que a dupla está sem a 2ª pessoa, de hoje em diante: _agenda_dupla_no_plano), espera (a dupla dita que espera a 2ª pessoa: a classe 4 dupla, ou o "fora" dupla da última montagem que citou a OS, sem compromisso dela de hoje em diante), texto} — o texto: a regra "1 pessoa; em dupla nos 2 primeiros meios-dias (troca do banco de baterias) — suposição minha."; com a 2ª pessoa faltando no plano "1 pessoa; nos 2 primeiros meios-dias (ter 10/11) a troca do banco de baterias pede 2 — falta a 2ª pessoa (só Alex está na equipe)." (o tempo todo: "1 pessoa; o serviço todo pede 2 (o orçamento previu 2 técnicos) — falta a 2ª pessoa em 12 meios-dias (só Alex está na equipe)."); a dita "Em dupla nos 2 primeiros meios-dias (você disse)." e, esperando, "Em dupla o tempo todo (você disse) — espero a 2ª pessoa: só Alex está na equipe."; a equipe dita "Quem vai: Roberto e João (você disse)."; em teste a regra "Em teste: eu marcaria 1 pessoa, em dupla nos 2 primeiros meios-dias (troca do banco de baterias). Hoje marco 1 pessoa e ponho a 2ª nesses meios-dias quando alguém está livre." (sem a regra uma_pessoa: "Hoje marco 2 pessoas."); nada "1 pessoa.". Nulo com modo_dupla desligado e na OS concluída, faturada ou cancelada (o resto do cartão é o de antes, byte a byte). FASE 7d (P8; §5.8, §6.2): o bloco local {texto, fonte, suposicao, tipo, nome, vagas, viagem_texto, bem_texto, perguntei, combinar [{texto, ate, vencido, em_teste}], notas []} (_agenda_local_bloco). Nulo com os 6 modos desligados e na OS concluída, faturada ou cancelada. Nunca valor.';

-- _agenda_local_da_os (de 20261026100300_agenda_fase3_equipe_diarias.sql)
create or replace function public._agenda_local_da_os(p_os uuid)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(
                  -- FASE 7d: (7d P8; §5.8, §6.4) o texto_equipe de _agenda_local_resolvido: só quando o local NÃO é suposição. Sem ele, o de hoje, byte a byte. A hora não importa ao
                  -- texto_equipe (ela só serve à conferência). Quem chama é a ficha, definer: direto, pelo técnico, a cadeia lança o P0002 de _agenda_cfg.
                  public._agenda_local_resolvido(p_os, public._hoje_brt()) ->> 'texto_equipe',
                  -- FASE 7d: fim
                  'na ' || nullif(btrim(m.name), ''), 'em ' || nullif(btrim(cl.city), ''))
    from public.service_orders so
    left join public.vessels vs on vs.id = so.vessel_id
    left join public.marinas m on m.id = coalesce(so.marina_id, vs.marina_id)
    left join public.clients cl on cl.id = so.client_id
   where so.id = p_os;
$function$;

comment on function public._agenda_local_da_os(uuid) is
  'Agenda de Produção (Fase 3, P4): onde é o serviço, para a ficha da equipe — "na <marina>" (da OS ou do bem), senão "em <cidade do cliente>", senão null. Sem pátio: o dado não existe. FASE 7d (P8; §5.8, §6.4): o texto_equipe de _agenda_local_resolvido, só quando o local NÃO é suposição (a fonte é dono, cliente, os ou bem); sem ele, o de hoje, byte a byte. Quem chama é agenda_equipe_ficha, definer.';

-- agenda_equipe_ficha (de 20261102100550_agenda_fase7c_tarefas.sql)
create or replace function public.agenda_equipe_ficha(p_payee uuid, p_dia date, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  cf        public.agenda_config := public._agenda_cfg();
  v_nome    text;
  v_dono    uuid := public._agenda_dono(null);
  v_gustavo text;
  v_dia_txt text;
  v_ref     text;
  r         record;
  v_quem    text[];
  v_parte   text;
  v_partes  text[] := '{}';
  v_resp    text[] := '{}';
  v_conf    text[] := '{}';
  v_os      jsonb := '[]'::jsonb;
  v_m       boolean := false;
  v_t       boolean := false;
  v_serv    text;
  v_n       int := 0;
  -- FASE 7c: (7c P8) o que fazer, na ficha
  v_p8_tp    jsonb;
  v_p8_its   jsonb;
  v_p8_lst   text;
  v_p8_cob   text;
  v_p8_ficha text;
  v_p8_cf    text;
  v_p8_curto text;
  v_p8_hoje  text;
  v_p8_perg  jsonb;
  v_p8_k     int;
  v_p8_suf   text;
  -- FASE 7c: fim
  -- FASE 7d: (7d P8) a frase do acesso
  c_7d_ok    constant text := ' Responde OK se tá certo.';
  v_7d_frase text;
  -- FASE 7d: fim
begin
  if p_payee is null or p_dia is null or p_hoje is null then
    raise exception 'Faltam a pessoa e o dia da ficha.' using errcode = '22023';
  end if;
  select public._agenda_nome_curto(p.name) into v_nome from public.payees p where p.id = p_payee;
  v_gustavo := coalesce('o ' || (select public._agenda_nome_curto(p.name) from public.payees p where p.id = v_dono), 'o responsável');
  v_dia_txt := public._agenda_dia_da_equipe(p_dia, p_hoje);
  v_ref := case when p_dia = p_hoje then 'hoje' when p_dia = p_hoje + 1 then 'amanhã' else v_dia_txt end;

  if cf.modo_proposta = 'ligado' then
    for r in
      select a.service_order_id as os, min(lower(a.periodo)) as ini, bool_or(a.turno = 'manha') as m, bool_or(a.turno = 'tarde') as t,
             array_agg(distinct a.turno) as turnos
        from public.agenda_alocacoes a
       where a.payee_id = p_payee and a.dia = p_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
       group by a.service_order_id
       order by 2, 1
    loop
      v_n := v_n + 1;
      v_m := v_m or r.m;
      v_t := v_t or r.t;
      -- com quem: as outras pessoas da mesma OS nos mesmos turnos (o dono pela abertura ou o fechamento também), "o X"
      v_quem := array(
        select 'o ' || x.nome
          from (select distinct on (b.payee_id) b.payee_id, public._agenda_nome_curto(py.name) as nome,
                       b.payee_id = v_dono or py.kind = 'socio' as dono
                  from public.agenda_alocacoes b join public.payees py on py.id = b.payee_id
                 where b.service_order_id = r.os and b.dia = p_dia and b.estado in ('publicada', 'fixada') and b.tipo <> 'reserva'
                   and b.payee_id <> p_payee and b.turno = any (r.turnos)) x
         order by x.dono desc, x.nome, x.payee_id);
      v_parte := public._agenda_hora_curta(r.ini) || ' ' || public._agenda_bem_da_os(r.os)
                 || coalesce(', ' || public._agenda_local_da_os(r.os), '')
                 || case when cardinality(v_quem) > 0 then ', com ' || public._agenda_lista(v_quem, null) else '' end;
      v_partes := v_partes || v_parte;
      v_resp := v_resp || (v_parte || ', ' || case when r.m and r.t then 'o dia todo' when r.m then 'só de manhã' else 'só à tarde' end);
      v_conf := v_conf || (coalesce(public._agenda_nome_curto((select cl.name from public.service_orders so
                                                                  join public.clients cl on cl.id = so.client_id where so.id = r.os)),
                                    'o serviço') || ' às ' || public._agenda_hora_curta(r.ini));
      v_os := v_os || jsonb_build_object('os', r.os, 'inicio', r.ini, 'manha', r.m, 'tarde', r.t);
    end loop;
  end if;

  if v_n = 0 then
    return jsonb_build_object('tem_plano', false, 'turnos', '[]'::jsonb, 'os', '[]'::jsonb,
      'texto_ficha', null, 'texto_confirmar', null, 'texto_curto', null, 'texto_como_foi', null,
      'texto_resposta', case
        when extract(isodow from p_dia) = 7 then public._agenda_maiuscula(v_ref) || ' é domingo: não tem serviço marcado.'
        when not public.agenda_dia_util(p_dia) then public._agenda_maiuscula(v_dia_txt) || ' não tem serviço marcado.'
        else format('Ainda não tenho o plano de %s. Vou ver com %s e te falo.', v_ref, v_gustavo) end);
  end if;

  -- FASE 7d: (7d P8; R1, R6.9-1, AG7-14) o dia não vira "confirmado" à equipe sem o acesso: a ficha sai, e a pessoa sabe que pode mudar. Só com modo_local_autorizacao ligado (o
  -- texto novo à equipe espera o OK dele); em teste ou desligado, nada é lido e a ficha é a de antes, byte a byte. Por OS do dia, o item acesso de _agenda_combinar_da_os, que já diz
  -- se o local é de terceiro. Sem nenhuma, nulo: having, porque o agregado devolveria uma linha com a frase sem lugar.
  if public._agenda_local_modo('acesso') = 'ligado' then
    select ' O acesso ' || public._agenda_lista(array_agg(x.no order by x.o), null) || ' ainda não está confirmado: eu te aviso.' into v_7d_frase
      from (select distinct on (e ->> 'local') public._agenda_local_no(e ->> 'local') as no, t.o
              from jsonb_array_elements(v_os) with ordinality t(j, o)
             cross join lateral jsonb_array_elements(public._agenda_combinar_da_os((t.j ->> 'os')::uuid, p_hoje)) e
             where e ->> 'tipo' = 'acesso' and not (e ->> 'combinado')::boolean and nullif(e ->> 'local', '') is not null
             order by e ->> 'local', t.o) x
    having count(*) > 0;
  end if;
  -- FASE 7d: fim
  -- FASE 7c: (7c P8, §16.5.7, §16.6.1–16.6.3; AG7-10, AG7-10e) com modo_tarefas ligado e o que fazer no dia (_agenda_tarefas_da_pessoa):
  -- a ficha troca o "Serviço: …" por "O que fazer: 1) …; 2) …" (tarefas_linhas_max linhas, 300 letras; a ficha inteira em até 440, para
  -- o acesso do 7d e o previsto do 7f caberem nos 600 da fila) e, a quem responde por uma OS no último dia dela ou no dia do prazo
  -- (tarefas_cobrar_vespera), "É o último dia no barco do Lenine: tem que ficar tudo pronto." (e o que sobra, até 2); o "como foi" de quem
  -- responde ganha a lista do que devia ficar pronto hoje (sem prefixo; até 330 letras); a ficha que vai junto do "como foi"
  -- (texto_curto) ganha "O que fazer" (3 linhas) só quando os dois cabem em 590 letras; o "o que tem pra amanhã" ganha "O que fazer" (8
  -- linhas). Desligado, em teste ou sem etapa: a de antes, byte a byte. O texto_confirmar nunca muda.
  if cf.modo_tarefas = 'ligado' then
    v_p8_tp := public._agenda_tarefas_da_pessoa(p_payee, p_dia, p_hoje);
  end if;
  if coalesce((v_p8_tp ->> 'tem')::boolean, false) then
    v_p8_its := (select jsonb_agg(i || jsonb_build_object('com', case when (i ->> 'com_dono')::boolean then v_gustavo end,
                                                          'rotulo', case when (v_p8_tp ->> 'duas_os')::boolean then i ->> 'cliente' end)
                                  order by (i ->> 'n')::int)
                   from jsonb_array_elements(v_p8_tp -> 'itens') i);
    -- a cobrança: a OS do último dia (ou do prazo) pela qual ela responde
    select string_agg(format(' É %s %s: tem que ficar tudo pronto.', case when u.k = 'ultimo' then 'o último dia' else 'o dia do prazo' end,
                             u.bem)
                      || case when jsonb_array_length(u.sobra) > 0
                              then ' Ainda falta: ' || public._agenda_lista(array(select x from jsonb_array_elements_text(u.sobra)
                                                                                    with ordinality s(x, o) where s.o <= 2 order by s.o), null) || '.'
                              else '' end, '' order by u.o)
      into v_p8_cob
      from (select distinct on (z.e ->> 'os') z.e ->> 'os' as os, z.e ->> 'bem' as bem, coalesce(z.e -> 'sobra', '[]'::jsonb) as sobra, z.k, z.o
              from (select e, 'ultimo'::text as k, o from jsonb_array_elements(v_p8_tp -> 'ultimo_dia') with ordinality t(e, o)
                    union all
                    select e, 'prazo'::text as k, 100 + o from jsonb_array_elements(v_p8_tp -> 'prazo') with ordinality t(e, o)) z
             where cf.tarefas_cobrar_vespera and (v_p8_tp -> 'responde') ? (z.e ->> 'os')
             order by z.e ->> 'os', z.o) u;
    v_p8_k := cf.tarefas_linhas_max;
    loop
      v_p8_lst := public._agenda_tarefas_lista_texto(v_p8_its, v_p8_k, 300);
      v_p8_ficha := format('%s, %s: %s.', v_nome, v_dia_txt, array_to_string(v_partes, '; ')) || ' O que fazer: ' || v_p8_lst || '.'
                    || coalesce(v_p8_cob, '') || ' Responde OK se tá certo.';
      exit when char_length(v_p8_ficha) <= 440 or v_p8_k = 1;
      v_p8_k := v_p8_k - 1;
    end loop;
    -- FASE 7d: (7d P8, R6.9-1) antes do "Responde OK", depois do corte dos 440: a ficha reservou o lugar dela
    if v_7d_frase is not null then
      v_p8_ficha := left(v_p8_ficha, char_length(v_p8_ficha) - char_length(c_7d_ok)) || v_7d_frase || c_7d_ok;
    end if;
    -- FASE 7d: fim
    -- o "como foi" de quem responde: o que devia ficar pronto hoje (os números do dia)
    v_p8_perg := coalesce(v_p8_tp -> 'pergunta', '[]'::jsonb);
    v_p8_cf := 'Como foi hoje? ' || case when v_m and v_t then 'Ficou manhã e tarde?' when v_m then 'Ficou a manhã?' else 'Ficou a tarde?' end;
    if jsonb_array_length(v_p8_perg) = 1 then
      v_p8_cf := v_p8_cf || format(' Do de hoje: %s. Se ficou pronto, responde OK. Se faltou, responde: ok, faltou.',
                                   public._agenda_tarefas_lista_texto(v_p8_perg, 1, 200, false));
    elsif jsonb_array_length(v_p8_perg) > 1 then
      v_p8_suf := format('. Se fez tudo, responde OK. Se faltou alguma, responde OK e o número (ex.: ok, faltou a %s).', v_p8_perg -> -1 ->> 'n');
      v_p8_cf := v_p8_cf || ' Do de hoje: '
                 || public._agenda_tarefas_lista_texto(v_p8_perg, 8, 330 - char_length(v_p8_cf) - char_length(' Do de hoje: ')
                                                                       - char_length(v_p8_suf), false)
                 || v_p8_suf;
    else
      v_p8_cf := v_p8_cf || ' Terminou o previsto? Se foi tudo como o previsto, responde OK.';
    end if;
    -- a ficha que vai junto do "como foi" de hoje: com "O que fazer" só quando os dois cabem em 590 letras
    v_p8_curto := format('%s: %s.', public._agenda_maiuscula(v_dia_txt), array_to_string(v_partes, '; '));
    v_p8_hoje := case when p_dia = p_hoje then v_p8_cf
                      else public.agenda_equipe_ficha(p_payee, p_hoje, p_hoje) ->> 'texto_como_foi' end;
    -- FASE 7d: (7d P8, R6.9-1) a frase vai colada no "como foi": ela conta nos 590. Daqui em diante v_p8_hoje só mede.
    if v_7d_frase is not null then
      v_p8_hoje := coalesce(v_p8_hoje, '') || v_7d_frase;
    end if;
    -- FASE 7d: fim
    v_p8_lst := public._agenda_tarefas_lista_texto(v_p8_its, 3,
                  590 - coalesce(char_length(v_p8_hoje), 0) - 1 - char_length(v_p8_curto) - char_length(' O que fazer: .'));
    if v_p8_lst is not null and coalesce(char_length(v_p8_hoje), 0) + 1 + char_length(v_p8_curto || ' O que fazer: ' || v_p8_lst || '.') <= 590
       and char_length(v_p8_lst) >= 20 then
      v_p8_curto := v_p8_curto || ' O que fazer: ' || v_p8_lst || '.';
    end if;
    -- FASE 7d: (7d P8, R6.9-1) quem trabalha hoje e amanhã recebe a ficha colada no "como foi": sem isto não leria o aviso
    v_p8_curto := v_p8_curto || coalesce(v_7d_frase, '');
    -- FASE 7d: fim
    return jsonb_build_object(
      'tem_plano', true,
      'turnos', to_jsonb(array_remove(array[case when v_m then 'manha' end, case when v_t then 'tarde' end], null)),
      'os', v_os,
      'texto_ficha', v_p8_ficha,
      'texto_resposta', format('%s, %s: %s.', v_nome, v_dia_txt, array_to_string(v_resp, '; '))
                        || ' O que fazer: ' || public._agenda_tarefas_lista_texto(v_p8_its, 8, 400) || '.'
                        || format(' Dúvida, fala com %s.', v_gustavo),
      'texto_confirmar', format('Bom dia, %s. Hoje é %s. Tá confirmado?', v_nome, public._agenda_lista(v_conf, null)),
      'texto_curto', v_p8_curto,
      'texto_como_foi', v_p8_cf,
      'tarefas', v_p8_tp);
  end if;
  -- FASE 7c: fim
  v_serv := case when v_n = 1 then public._agenda_servico_curto((v_os -> 0 ->> 'os')::uuid) end;
  return jsonb_build_object(
    'tem_plano', true,
    'turnos', to_jsonb(array_remove(array[case when v_m then 'manha' end, case when v_t then 'tarde' end], null)),
    'os', v_os,
    'texto_ficha', format('%s, %s: %s.', v_nome, v_dia_txt, array_to_string(v_partes, '; '))
                   || coalesce(' Serviço: ' || v_serv || '.', '') || ' Responde OK se tá certo.',
    'texto_resposta', format('%s, %s: %s. Dúvida, fala com %s.', v_nome, v_dia_txt, array_to_string(v_resp, '; '), v_gustavo),
    'texto_confirmar', format('Bom dia, %s. Hoje é %s. Tá confirmado?', v_nome, public._agenda_lista(v_conf, null)),
    'texto_curto', format('%s: %s.', public._agenda_maiuscula(v_dia_txt), array_to_string(v_partes, '; ')),
    -- FASE 7d: (7d P8, R6.9-1) as 2 com a frase do acesso, antes do "Responde OK" (a última chave igual do objeto vale: substitui as de cima; sem a frase, o mesmo texto)
    'texto_ficha', format('%s, %s: %s.', v_nome, v_dia_txt, array_to_string(v_partes, '; '))
                   || coalesce(' Serviço: ' || v_serv || '.', '') || coalesce(v_7d_frase, '') || c_7d_ok,
    'texto_curto', format('%s: %s.', public._agenda_maiuscula(v_dia_txt), array_to_string(v_partes, '; ')) || coalesce(v_7d_frase, ''),
    -- FASE 7d: fim
    'texto_como_foi', 'Como foi hoje? ' || case when v_m and v_t then 'Ficou manhã e tarde?' when v_m then 'Ficou a manhã?'
                                                else 'Ficou a tarde?' end
                      || ' Terminou o previsto? Se foi tudo como o previsto, responde OK.');
end;
$function$;

comment on function public.agenda_equipe_ficha(uuid, date, date) is
  'Agenda de Produção (Fase 3, P4): a ficha de uma pessoa num dia, só do publicado (alocações vigentes sem reserva, com modo_proposta ligado; fora disso tem_plano = false) — {tem_plano, turnos, os[{os, inicio, manha, tarde}], texto_ficha ("Roberto, terça (03/11): 8h no barco do Vanderlei, com o Gustavo. Serviço: … Responde OK se tá certo."), texto_resposta (o "o que tem pra amanhã", com o turno; sem plano "Ainda não tenho o plano de amanhã. Vou ver com o Gustavo e te falo."; domingo "Amanhã é domingo: não tem serviço marcado."), texto_confirmar ("Bom dia, Roberto. Hoje é Vanderlei às 8h. Tá confirmado?"), texto_curto (a ficha que vai junto do "como foi hoje?") e texto_como_foi}. Nunca valor, número de OS, cliente de outra pessoa nem acesso. Só service_role. FASE 7c (P8, §16.5.7, §16.6.1–16.6.3; AG7-10): com modo_tarefas ligado e etapas no dia (_agenda_tarefas_da_pessoa), texto_ficha troca o "Serviço: …" por "O que fazer: 1) …; 2) …" (tarefas_linhas_max linhas, 300 letras; a ficha em até 440) e, a quem responde por uma OS no último dia dela ou no dia do prazo (tarefas_cobrar_vespera), "É o último dia no barco do Lenine: tem que ficar tudo pronto." (e "Ainda falta: …", até 2); texto_como_foi de quem responde: "Do de hoje: 1) …. Se fez tudo, responde OK. Se faltou alguma, responde OK e o número (ex.: ok, faltou a 3)." (com 1: "Se ficou pronto, responde OK. Se faltou, responde: ok, faltou."); texto_curto com "O que fazer" (3 linhas) só quando cabe junto do "como foi" de hoje em 590 letras; texto_resposta com "O que fazer" (8 linhas) antes do "Dúvida, fala com …"; a saída ganha tarefas. Desligado, em teste ou sem etapa: a de antes, byte a byte; o texto_confirmar nunca muda. FASE 7d (P8; R1, R6.9-1, AG7-14): com modo_local_autorizacao ligado (por _agenda_local_modo) e o dia numa OS em local de terceiro sem o acesso combinado (o item acesso de _agenda_combinar_da_os), " O acesso na {local} ainda não está confirmado: eu te aviso." antes do "Responde OK" em texto_ficha (nas 2 saídas) e no fim de texto_curto (descontada dos 590 na saída da 7c). texto_confirmar não muda. Em teste ou desligado, a de antes, byte a byte.';

-- agenda_saude (de 20261101100400_agenda_fase7b_leituras.sql)
create or replace function public.agenda_saude(p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf        public.agenda_config := public._agenda_cfg();
  v_cart    uuid[];
  v_ult     record;
  v_vig     jsonb;
  v_hoje    jsonb;
  v_crit    jsonb;
  v_perg    jsonb;
  v_prop    jsonb;
  v_plano   jsonb;
  v_inv     jsonb;
  v_fech    jsonb;
  v_sem     int;
  v_regra   jsonb;
  v_leu     boolean;
  v_choques int;
  -- FASE 3
  v_rot     jsonb;
  v_eq      jsonb;
  v_dia     jsonb;
  v_conc    jsonb;
  v_marcos  jsonb;
  v_com     jsonb;
  v_teto    int;
  v_janela  int;
  v_semconf int;
  v_sobre   int;
  v_semrec  int;
  v_pay     int;
  -- FASE 4: o material e a mensagem ao fornecedor
  v_mrod    jsonb;
  v_rem     jsonb;
  v_mperg   jsonb;
  v_semdono int;
  v_semorig int;
  v_prec    jsonb;
  v_det     jsonb;
  v_fsombra int;
  v_ffora   int;
  v_fteto   int;
  v_fproib  int;
  v_forn    jsonb;
  v_cob     jsonb;
  v_med     numeric;
  v_zeros4  boolean;
  v_mat     jsonb;
  -- FASE 4: fim
  -- FASE 5: a mensagem ao cliente
  v_crod    jsonb;
  v_cmsg    jsonb;
  v_caprov  jsonb;
  v_cjan    int;
  v_cdom    int;
  v_cteto   int;
  v_cint    int;
  v_cproib  int;
  v_csombra int;
  v_csemap  int;
  v_ccrit   int;
  v_cvesp   int;
  v_cdepois int;
  v_caudio  int;
  v_cmet    jsonb;
  v_zeros5  boolean;
  v_cli     jsonb;
  -- FASE 5: fim
  -- FASE 6: o aprendizado
  v_arod    record;
  v_apeq    int;
  v_afora   int;
  v_agrande int;
  v_aatras  int;
  v_asemcl  int;
  v_afat    int;
  v_amet    jsonb;
  v_zeros6  boolean;
  v_apr     jsonb;
  -- FASE 6: fim
  -- CORREÇÃO FASE 6: (C2) item 12: os zeros de antes do aprendizado (para o ok sair com as janelas de agenda_config)
  v_z4_antes boolean;
  -- FASE 7: (7a P7) o gestor da agenda
  v_ges     jsonb;
  v_gz      jsonb;
  v_gzeros  boolean;
  v_gdesde  timestamptz;
  v_gmodos  jsonb;
  v_gult    record;
  v_gr      jsonb;
  -- FASE 7: fim
  -- CORREÇÃO FASE 6: fim
begin
  v_cart := array(select k.service_order_id from public.os_carteira(p_hoje) k);

  select max(x.p_agora) as ultima, max(x.rodou_em) as rodou_em,
         count(*) filter (where x.p_agora > p_agora - interval '1 day' and x.p_agora <= p_agora) as n24,
         (array_agg(x.erros order by x.p_agora desc, x.rodou_em desc))[1] as erros_ult
    into v_ult from public.agenda_vigia_rodadas x
   -- FASE 3: a rotina da equipe grava na mesma tabela (rotina = 'rotina'); a vigia é só a dela.
   where x.rotina = 'vigia';
  v_vig := jsonb_build_object(
    'ultima_rodada', v_ult.ultima, 'rodou_em', v_ult.rodou_em,
    'rodou_nas_ultimas_2h', coalesce(v_ult.ultima > p_agora - interval '2 hours', false),
    'rodadas_24h', coalesce(v_ult.n24, 0), 'erros_ultima_rodada', coalesce(v_ult.erros_ult, 0),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.last_seen_at >= least(p_agora, now()) - interval '1 day'));

  select jsonb_build_object(
           'publicar', count(*) filter (where a.executada and a.tipo = 'publicar'),
           'criar', count(*) filter (where a.executada and a.tipo = 'criar'),
           'mover', count(*) filter (where a.executada and a.tipo = 'mover'),
           'cancelar', count(*) filter (where a.executada and a.tipo = 'cancelar'),
           'promover', count(*) filter (where a.executada and a.tipo = 'promover_reserva'),
           'soltar', count(*) filter (where a.executada and a.tipo = 'soltar_reserva'),
           'status', count(*) filter (where a.executada and a.tipo = 'status'),
           'resultado', count(*) filter (where a.executada and a.tipo = 'resultado'),
           'desfeitas', count(*) filter (where a.executada and a.tipo = 'desfazer'),
           'sombra', count(*) filter (where not a.executada))
    into v_hoje from public.agenda_acoes a where a.dia = p_hoje;

  -- A prova: nenhuma ação crítica executada sem a decisão registrada (o gatilho impede; isto confere).
  select count(*) into v_sem
    from public.agenda_acoes a left join public.agenda_perguntas q on q.id = a.pergunta_id
   where a.executada and a.critica and (q.id is null or q.estado <> 'respondida' or q.opcao_escolhida is null);
  -- E o erro de classificação: ação autônoma executada como não crítica que a regra diz crítica.
  select jsonb_build_object('n', count(*), 'acoes', coalesce(jsonb_agg(a.id order by a.criada_em, a.id), '[]'::jsonb)) into v_regra
    from public.agenda_acoes a
   where a.executada and not a.critica and a.origem in ('motor', 'vigia', 'conferencia')
     and a.tipo in ('publicar', 'criar', 'mover', 'cancelar', 'promover_reserva', 'soltar_reserva')
     and public._agenda_criticidade_da_acao(a.id) is not null;
  v_crit := jsonb_build_object(
    'abertas', (select count(*) from public.agenda_perguntas q where q.critica and q.estado = 'aberta'),
    'respondidas_7d', (select count(*) from public.agenda_perguntas q
                        where q.critica and q.estado = 'respondida' and q.respondida_em > p_agora - interval '7 days'),
    'sem_decisao', v_sem, 'pela_regra_sem_decisao', (v_regra ->> 'n')::int, 'pela_regra_acoes', v_regra -> 'acoes');

  v_perg := jsonb_build_object(
    'abertas_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select q.tipo, count(*) as n from public.agenda_perguntas q where q.estado = 'aberta' group by q.tipo) t), '{}'::jsonb),
    'abertas_sombra', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.modo = 'sombra'),
    'mostradas_hoje', (select count(*) from public.agenda_perguntas q
                        where (q.mostrada_em at time zone 'America/Sao_Paulo')::date = p_hoje));

  select jsonb_build_object(
           'abertas', count(*) filter (where p.estado = 'aberta'),
           'obsoletas_7d', count(*) filter (where p.estado = 'obsoleta' and p.criada_em > p_agora - interval '7 days'),
           'aplicadas_7d', count(*) filter (where p.estado = 'aplicada' and p.criada_em > p_agora - interval '7 days'),
           'sombra_7d', count(*) filter (where p.modo = 'sombra' and p.criada_em > p_agora - interval '7 days'))
    into v_prop from public.agenda_propostas p;

  select jsonb_build_object(
           'alocacoes_vigentes_futuras', count(*) filter (where a.dia >= p_hoje and a.resultado is null),
           'os_programadas', count(distinct a.service_order_id) filter (where a.dia >= p_hoje and a.resultado is null and a.tipo <> 'reserva'),
           'reservas', count(*) filter (where a.dia >= p_hoje and a.tipo = 'reserva'),
           'sem_registro_7d', count(*) filter (where a.resultado = 'sem_registro' and a.dia > p_hoje - 7))
    into v_plano from public.agenda_alocacoes a where a.estado in ('publicada', 'fixada');

  select count(*) into v_choques
    from public.agenda_alocacoes a join public.agenda_alocacoes b
      on b.payee_id = a.payee_id and b.id > a.id and b.periodo && a.periodo
   where a.estado in ('publicada', 'fixada') and b.estado in ('publicada', 'fixada');
  v_inv := jsonb_build_object(
    'vigente_de_os_fora_da_carteira', (select count(distinct a.service_order_id) from public.agenda_alocacoes a
                                        where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
                                          and not (a.service_order_id = any (v_cart))),
    'espelho_divergente', case when cf.modo_proposta <> 'ligado' then 0 else (
       select count(*) from public.service_orders so
        cross join lateral (select min(lower(a.periodo)) as ini, max(upper(a.periodo)) as fim from public.agenda_alocacoes a
                             where a.service_order_id = so.id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                               and a.resultado is distinct from 'nao_cumprido') m
        where so.id = any (v_cart)
          and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = so.id)
          and (so.scheduled_start_at is distinct from m.ini or so.scheduled_end_at is distinct from m.fim)) end,
    'choques', v_choques);

  if to_regclass('public.resumo_tarde') is not null then
    execute $q$select exists (select 1 from public.resumo_tarde t
                               where t.dia = $1 and jsonb_typeof(t.detalhe -> 'agenda') = 'object'
                                 and (t.detalhe -> 'agenda' ? 'linhas_diria' or t.detalhe -> 'agenda' ? 'linhas'))$q$
      into v_leu using p_hoje;
  end if;
  v_fech := jsonb_build_object(
    'leu_o_plano_hoje', v_leu,
    'linhas_mostradas', (select count(*) from public.agenda_acoes a
                          where a.contada_via = 'fechamento' and (a.contada_em at time zone 'America/Sao_Paulo')::date = p_hoje)
                        + (select count(*) from public.agenda_perguntas q
                            where q.mostrada_via = 'fechamento' and (q.mostrada_em at time zone 'America/Sao_Paulo')::date = p_hoje));

  -- FASE 3: a rotina, a equipe, as diárias, a conclusão, os marcos e a comissão. Os "0 obrigatórios": acima do teto, fora
  -- da janela, diária sem confirmação, turno sobrescrito pela agenda, conclusão sem cobrança quando devia, pagamento de
  -- comissão de técnico.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'rotina:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_rot from public.agenda_vigia_rodadas x where x.rotina = 'rotina';
  select count(*) into v_teto
    from (select m.payee_id, (m.enviar_em at time zone 'America/Sao_Paulo')::date as dia, m.tipo = 'resposta' as resp, count(*) as n
            from public.agenda_equipe_mensagens m
           where m.modo = 'ligado' and m.estado in ('enfileirada', 'respondida', 'sem_resposta')
           group by 1, 2, 3) t
   where t.n > case when t.resp then cf.equipe_respostas_dia_max else cf.equipe_proativas_dia_max end;
  -- (revisão C1) pela regra única da janela (_agenda_equipe_fora_da_janela): a resposta direta tem a dela
  select count(*) into v_janela
    from public.whatsapp_send_queue q
    left join public.agenda_equipe_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-equipe'
     and (x.id is null
          or public._agenda_equipe_fora_da_janela(x.tipo, x.enviar_em, q.scheduled_for) is not null
          -- o que SAIU fora da janela (o worker atrasado): também conta
          or (q.sent_at is not null and public._agenda_equipe_fora_da_janela(x.tipo, x.enviar_em, q.sent_at) is not null));
  v_eq := jsonb_build_object(
    'mensagens_hoje_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select m.tipo, count(*) as n from public.agenda_equipe_mensagens m
         where (m.enviar_em at time zone 'America/Sao_Paulo')::date = p_hoje group by m.tipo) t), '{}'::jsonb),
    'recusadas_hoje_por_motivo', coalesce((select jsonb_object_agg(t.recusa_motivo, t.n) from (
        select m.recusa_motivo, count(*) as n from public.agenda_equipe_mensagens m
         where m.estado = 'recusada' and (m.enviar_em at time zone 'America/Sao_Paulo')::date = p_hoje group by m.recusa_motivo) t), '{}'::jsonb),
    'acima_do_teto', v_teto, 'fora_da_janela', v_janela);
  select count(*) into v_semconf
    from public.agenda_acoes a
   where a.tipo = 'diaria' and a.executada and not a.critica and a.origem <> 'dono' and a.desfeita_em is null
     and coalesce(public._agenda_confirmacao_do_dia(a.payee_id, (a.depois ->> 'dia')::date) ->> 'estado', '') <> 'confirmada';
  select count(*) into v_sobre
    from public.agenda_acoes a left join public.work_shifts ws on ws.id = a.work_shift_id
   where a.tipo = 'diaria' and a.executada and not a.critica and a.origem <> 'dono'
     and (coalesce(jsonb_typeof(a.antes -> 'turno'), 'null') <> 'null' or (ws.id is not null and ws.origem <> 'agente'));
  v_dia := jsonb_build_object(
    -- (o dia de quem agiu: a.dia é o p_hoje dele; criada_em é o relógio do banco)
    'lancadas_7d', (select count(*) from public.agenda_acoes a
                     where a.tipo = 'diaria' and a.executada and a.origem <> 'dono' and a.dia > p_hoje - 7),
    'sombra_7d', (select count(*) from public.agenda_acoes a
                   where a.tipo = 'diaria' and not a.executada and a.dia > p_hoje - 7),
    'perguntas_abertas', (select count(*) from public.agenda_perguntas q where q.tipo in ('diaria', 'diaria_ligar') and q.estado = 'aberta'),
    'sem_confirmacao', v_semconf, 'sobrescreveu_turno', v_sobre);
  -- a conclusão pela porta sem cobrança viva quando a regra da condição dá parcelas ou título (a releitura é só service_role)
  if has_function_privilege('public._os_recebiveis_da_conclusao(uuid, date)', 'execute') then
    select count(*) into v_semrec
      from (select distinct so.id, so.check_out_at
              from public.agenda_acoes a join public.service_orders so on so.id = a.service_order_id
             where a.tipo = 'concluir' and a.executada and a.desfeita_em is null and so.status in ('completed', 'invoiced')
               and so.check_out_at is not null
               and not exists (select 1 from public.receivables r where r.service_order_id = so.id and r.status <> 'cancelled')) t
     where public._os_recebiveis_da_conclusao(t.id, (t.check_out_at at time zone 'America/Sao_Paulo')::date) ->> 'motivo'
           in ('parcelas', 'titulo_unico');
  end if;
  v_conc := jsonb_build_object(
    'pela_agenda_7d', (select count(*) from public.agenda_acoes a
                        where a.tipo = 'concluir' and a.executada and a.origem in ('equipe', 'dono')
                          and a.dia > p_hoje - 7),
    'desfeitas_7d', (select count(*) from public.agenda_acoes a
                      where a.tipo = 'concluir' and a.desfeita_em > p_agora - interval '7 days'),
    'sem_recebivel_quando_devia', v_semrec);
  select jsonb_build_object(
           'concluidas_30d', count(*),
           'entregues_em_ate_5du', count(*) filter (where so.delivered_at is not null
             and public.agenda_du_entre((so.check_out_at at time zone 'America/Sao_Paulo')::date,
                                        (so.delivered_at at time zone 'America/Sao_Paulo')::date) <= cf.entrega_aviso_du),
           'sem_entrega_ha_mais_de_5du', count(*) filter (where so.delivered_at is null and so.status = 'completed'
             and public.agenda_du_entre((so.check_out_at at time zone 'America/Sao_Paulo')::date, p_hoje) > cf.entrega_aviso_du))
    into v_marcos
    from public.service_orders so
   where so.check_out_at > p_agora - interval '30 days'
     and exists (select 1 from public.agenda_acoes a
                  where a.service_order_id = so.id and a.tipo = 'concluir' and a.executada and a.desfeita_em is null);
  select count(*) into v_pay
    from public.payables pa
   where pa.origin = 'commission' and pa.created_at > p_agora - interval '7 days'
     and pa.payee_id in (select w.payee_id from public.work_profiles w where w.modo_pagamento = 'diaria' and w.payee_id is not null);
  v_com := jsonb_build_object('pagamento', (select c.pagamento from public.comissao_config c where c.id),
                              'payables_de_comissao_tecnico_7d', v_pay);
  -- FASE 3: fim
  -- FASE 4: o material (a nota, o Pix, o detector, o cadastro) e a mensagem ao fornecedor. Os "0 obrigatórios": linha
  -- ligada a nota ou Pix sem a palavra do dono (vinculo_sem_resposta_do_dono), previsão sem o original guardado, e na
  -- mensagem ao fornecedor: nada na fila em sombra (ou sem a mensagem registrada), nada saindo ou que saiu fora da janela,
  -- nada acima do teto, nada com valor, pagamento, OS, link ou o nome do cliente.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'material:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_mrod from public.agenda_vigia_rodadas x where x.rotina = 'material';
  select jsonb_build_object(
           'a_caminho', count(*) filter (where r.estado = 'a_caminho'),
           'sem_resposta', count(*) filter (where r.vinculo = 'sem_resposta' and r.estado <> 'descartada'),
           'ligadas_7d', count(*) filter (where r.vinculo = 'ligada' and r.respondida_em > p_agora - interval '7 days'),
           'sem_servico_7d', count(*) filter (where r.vinculo = 'sem_servico' and r.respondida_em > p_agora - interval '7 days'),
           'chegaram_7d', count(*) filter (where r.estado = 'chegou' and r.chegou_em > p_hoje - 7))
    into v_rem from public.material_remessas r;
  v_mperg := jsonb_build_object(
    'abertas_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select q.tipo, count(*) as n from public.agenda_perguntas q
         where q.estado = 'aberta'
           and q.tipo in ('nfe_vincular', 'pix_material', 'previsao_fornecedor', 'fornecedor_cadastro', 'fornecedores_prazo')
         group by q.tipo) t), '{}'::jsonb),
    -- o teto do Pix (pix_perguntas_semana_max por semana ISO, no total), no modo de agora
    'pix_na_semana', (select count(*) from public.agenda_perguntas q
                       where q.tipo = 'pix_material'
                         and q.modo = case when cf.modo_material = 'ligado' then 'ligado' else 'sombra' end
                         and (q.criada_em at time zone 'America/Sao_Paulo')::date
                             between date_trunc('week', p_hoje)::date and date_trunc('week', p_hoje)::date + 6));
  -- a linha que a agenda ligou a uma nota ou a um Pix tem de ter a palavra do dono (ou a compra que ele já ligou)
  select count(*) into v_semdono
    from public.os_material m
   where (m.remessa_id is not null or m.fonte in ('nfe', 'pix'))
     and coalesce(m.evidencia ->> 'vinculo_por', '') not in ('dono', 'compra_ligada');
  select count(*) into v_semorig from public.os_material m where m.previsao_ate is not null and m.previsao_original is null;
  -- a precisão do detector é do administrador e do financeiro (para outro login ela lançaria 42501)
  if (select auth.uid()) is null or public.is_admin_or_financial((select auth.uid())) then
    v_prec := public.agenda_detector_precisao(p_hoje - 13, p_hoje);
  end if;
  v_det := jsonb_build_object(
    'sinais_14d', v_prec -> 'sinais', 'julgados_14d', v_prec -> 'julgados', 'certos_14d', v_prec -> 'certos',
    'precisao_14d', v_prec -> 'precisao', 'pronto_para_ligar', coalesce((v_prec ->> 'pronto_para_ligar')::boolean, false),
    'aplicados_7d', (select count(*) from public.material_sinais s where s.estado = 'aplicado' and s.dia > p_hoje - 7),
    'desfeitos_7d', (select count(*) from public.material_sinais s join public.agenda_acoes a on a.id = s.acao_id
                      where a.desfeita_em > p_agora - interval '7 days'));
  -- a mensagem ao fornecedor: o que entrou na fila sem a mensagem registrada em ligado (nada sai em sombra)
  select count(*) into v_fsombra
    from public.whatsapp_send_queue q
    left join public.agenda_fornecedor_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-fornecedor' and (x.id is null or x.modo <> 'ligado');
  v_fsombra := v_fsombra + (select count(*) from public.agenda_fornecedor_mensagens x
                             where x.modo <> 'ligado' and (x.fila_id is not null or x.estado = 'enfileirada'));
  -- o que está na fila, saindo ou saiu fora da janela da mensagem (pela regra única); o que falhou não saiu
  select count(*) into v_ffora
    from public.whatsapp_send_queue q
    join public.agenda_fornecedor_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-fornecedor'
     and ((q.status in ('pending', 'sending', 'sent')
           and public._agenda_fornecedor_fora_da_janela(x.enviar_em, q.scheduled_for) is not null)
          or (q.sent_at is not null and public._agenda_fornecedor_fora_da_janela(x.enviar_em, q.sent_at) is not null));
  -- acima do teto: o que entrou na fila (ligado), por fornecedor no dia e na semana ISO, e no dia a todos
  with ent as (
    select x.fornecedor_id as f, (x.enviar_em at time zone 'America/Sao_Paulo')::date as dia
      from public.agenda_fornecedor_mensagens x
     where x.modo = 'ligado'
       and (x.fila_id is not null
            or exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-fornecedor' and q.source_ref_id = x.id))
  )
  select (select count(*) from (select e.f, e.dia from ent e group by 1, 2 having count(*) > cf.fornecedor_dia_max) a)
       + (select count(*) from (select e.f, date_trunc('week', e.dia) from ent e group by 1, 2
                                 having count(*) > cf.fornecedor_semana_max) b)
       + (select count(*) from (select e.dia from ent e group by 1 having count(*) > cf.fornecedor_total_dia_max) t)
    into v_fteto;
  select count(*) into v_fproib
    from public.agenda_fornecedor_mensagens x
   where public._agenda_fornecedor_texto_proibido(x.texto, x.service_order_id) is not null;
  select jsonb_build_object(
           'registradas_7d', count(*),
           'enfileiradas_7d', count(*) filter (where x.estado = 'enfileirada'),
           'em_teste_7d', count(*) filter (where x.modo = 'sombra'),
           'recusadas_7d_por_motivo', coalesce((
             select jsonb_object_agg(t.recusa_motivo, t.n) from (
               select y.recusa_motivo, count(*) as n from public.agenda_fornecedor_mensagens y
                where y.estado = 'recusada' and (y.enviar_em at time zone 'America/Sao_Paulo')::date > p_hoje - 7
                group by y.recusa_motivo) t), '{}'::jsonb))
    into v_forn
    from public.agenda_fornecedor_mensagens x
   where (x.enviar_em at time zone 'America/Sao_Paulo')::date > p_hoje - 7;
  -- a cobertura: os itens críticos das OS que começam nas próximas material_inicio_dias, e quantos têm data (nível A a D)
  select jsonb_build_object(
           'itens_criticos_proximos', count(*),
           'com_previsao', count(*) filter (where e ->> 'nivel' <> 'E'),
           'pct', case when count(*) > 0 then round(100 * (count(*) filter (where e ->> 'nivel' <> 'E'))::numeric / count(*)) end)
    into v_cob
    from (select k.id from unnest(v_cart) k(id)
           where public._agenda_inicio_previsto(k.id, p_hoje) between p_hoje and p_hoje + cf.material_inicio_dias) o
    cross join lateral jsonb_array_elements(coalesce(public.os_prontidao(o.id, p_hoje) #> '{material,itens}', '[]'::jsonb)) e
   where coalesce((e ->> 'critico')::boolean, false);
  -- a espera: a mediana dos dias corridos da aprovação (a régua de os_carteira) até a 1ª compra (o dia dito ou o da OC),
  -- das OS aprovadas nos últimos 90 dias que já compraram
  select percentile_cont(0.5) within group (order by t.d) into v_med
    from (select min(coalesce(m.comprado_em, (po.created_at at time zone 'America/Sao_Paulo')::date))
                 - (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date as d
            from public.service_orders so
            join public.os_material m on m.service_order_id = so.id
            left join public.purchase_order_items poi on poi.id = m.purchase_order_item_id
            left join public.purchase_orders po on po.id = poi.purchase_order_id and po.status <> 'cancelled'
           where so.merged_into_id is null and so.status <> 'cancelled'
             and (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date
                 between p_hoje - 90 and p_hoje
           group by so.id
          having min(coalesce(m.comprado_em, (po.created_at at time zone 'America/Sao_Paulo')::date)) is not null) t;
  v_zeros4 := v_semdono = 0 and v_semorig = 0 and v_fsombra = 0 and v_ffora = 0 and v_fteto = 0 and v_fproib = 0;
  v_mat := jsonb_build_object(
    'modos', jsonb_build_object('material', cf.modo_material, 'detector', cf.modo_detector, 'fornecedor', cf.modo_fornecedor),
    'ultima_rodada', v_mrod -> 'ultima_rodada', 'rodou_nas_ultimas_2h', v_mrod -> 'rodou_nas_ultimas_2h',
    'erros_24h', v_mrod -> 'erros_24h',
    'remessas', v_rem, 'perguntas', v_mperg,
    'vinculo_sem_resposta_do_dono', v_semdono, 'previsao_sem_original', v_semorig,
    'detector', v_det,
    'fornecedor', v_forn || jsonb_build_object('na_fila_em_sombra', v_fsombra, 'fora_da_janela', v_ffora,
                                               'acima_do_teto', v_fteto, 'com_valor_ou_cliente', v_fproib),
    'cobertura', v_cob,
    'espera', jsonb_build_object('mediana_ate_comprar_90d', v_med));
  -- FASE 4: fim
  -- FASE 5: a mensagem ao cliente — o modo, as ondas e os tipos liberados, a rodada, as mensagens e a aprovação em 7 dias.
  -- Os "0 obrigatórios" (entram no ok pelo v_zeros4, para o ok ficar igual linha a linha): nada fora da janela (nem o que
  -- saiu fora dela), nada em feriado ou domingo, nada acima do teto, nada a menos do intervalo de outra, nada com texto
  -- proibido, nada na fila em teste, nada enviado sem a aprovação dos primeiros dias, nada crítico enviado sem a opção 2,
  -- nenhuma véspera com a OS aguardando peça, nenhum aviso de atraso depois da data dita, nenhum áudio que confirmou. As
  -- métricas não reprovam.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'cliente:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_crod from public.agenda_vigia_rodadas x where x.rotina = 'cliente';
  select coalesce(jsonb_object_agg(t.tipo, jsonb_build_object('registradas', t.reg, 'aguardando', t.agu, 'enviadas', t.env,
                                                              'recusadas_por_motivo', t.rec)), '{}'::jsonb)
    into v_cmsg
    from (select m.tipo, count(*) as reg, count(*) filter (where m.estado = 'aguardando_dono') as agu,
                 count(*) filter (where m.enviada_em is not null) as env,
                 coalesce((select jsonb_object_agg(y.recusa_motivo, y.n)
                             from (select z.recusa_motivo, count(*) as n from public.agenda_cliente_mensagens z
                                    where z.tipo = m.tipo and z.estado = 'recusada' and z.criada_em > p_agora - interval '7 days'
                                    group by z.recusa_motivo) y), '{}'::jsonb) as rec
            from public.agenda_cliente_mensagens m
           where m.criada_em > p_agora - interval '7 days'
           group by m.tipo) t;
  select jsonb_build_object(
           'pedidas_abertas', count(*) filter (where m.estado = 'aguardando_dono' and m.aprovacao in ('pedida', 'critica')),
           'vencidas_7d', count(*) filter (where m.aprovacao = 'vencida' and m.criada_em > p_agora - interval '7 days'),
           'aprovadas_7d', count(*) filter (where m.aprovacao = 'aprovada' and m.aprovada_em > p_agora - interval '7 days'),
           'seguradas_7d', count(*) filter (where m.aprovacao = 'segurada' and m.aprovada_em > p_agora - interval '7 days'))
    into v_caprov from public.agenda_cliente_mensagens m where m.modo = 'ligado';
  -- a janela (a regra única): o que está na fila, saindo ou saiu fora da janela da mensagem; o feriado e o domingo à parte
  select count(*) filter (where t.f is not null), count(*) filter (where t.f in ('feriado', 'domingo'))
    into v_cjan, v_cdom
    from (select coalesce(case when q.status in ('pending', 'sending', 'sent')
                               then public._agenda_cliente_fora_da_janela(x.enviar_em, q.scheduled_for) end,
                          case when q.sent_at is not null then public._agenda_cliente_fora_da_janela(x.enviar_em, q.sent_at) end) as f
            from public.whatsapp_send_queue q
            join public.agenda_cliente_mensagens x on x.id = q.source_ref_id
           where q.source = 'agenda-cliente') t;
  -- o teto: o que entrou na fila (ligado), por cliente no dia e na semana ISO, e no dia a todos
  with ent as (
    select m.client_id as c, (m.enviar_em at time zone 'America/Sao_Paulo')::date as dia
      from public.agenda_cliente_mensagens m
     where m.modo = 'ligado' and m.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta')
  )
  select (select count(*) from (select e.c, e.dia from ent e group by 1, 2 having count(*) > cf.cliente_dia_max) a)
       + (select count(*) from (select e.c, date_trunc('week', e.dia) from ent e group by 1, 2
                                 having count(*) > cf.cliente_semana_max) b)
       + (select count(*) from (select e.dia from ent e group by 1 having count(*) > cf.cliente_total_dia_max) t)
    into v_cteto;
  -- o intervalo: duas linhas agenda-cliente (na fila, saindo ou saídas) a menos de cliente_intervalo_min_s uma da outra
  select count(*) into v_cint
    from public.whatsapp_send_queue a
    join public.whatsapp_send_queue b
      on b.source = 'agenda-cliente' and b.id > a.id and b.status in ('pending', 'sending', 'sent')
     and abs(extract(epoch from coalesce(b.sent_at, b.scheduled_for) - coalesce(a.sent_at, a.scheduled_for)))
         < cf.cliente_intervalo_min_s
   where a.source = 'agenda-cliente' and a.status in ('pending', 'sending', 'sent');
  select count(*) into v_cproib
    from public.agenda_cliente_mensagens m where public._agenda_cliente_texto_proibido(m.texto) is not null;
  -- em teste nada entra na fila (nem linha da fila sem a mensagem registrada em ligado)
  select (select count(*) from public.whatsapp_send_queue q
            left join public.agenda_cliente_mensagens x on x.id = q.source_ref_id
           where q.source = 'agenda-cliente' and (x.id is null or x.modo <> 'ligado'))
       + (select count(*) from public.agenda_cliente_mensagens x
           where x.modo <> 'ligado' and (x.fila_id is not null or x.enviada_em is not null
                                         or x.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta')))
    into v_csombra;
  -- enviada sem a aprovação do dono quando o tipo ainda não somava os dias aprovados (ou a preparada pelo dono)
  select count(*) into v_csemap
    from public.agenda_cliente_mensagens m
   where m.modo = 'ligado' and m.enviada_em is not null and m.aprovacao <> 'aprovada'
     and (m.origem <> 'rodada'
          or (cf.cliente_aprovacao_dias > 0
              and (select count(distinct (y.aprovada_em at time zone 'America/Sao_Paulo')::date)
                     from public.agenda_cliente_mensagens y
                    where y.tipo = m.tipo and y.aprovacao = 'aprovada' and y.origem = 'rodada' and y.modo = 'ligado'
                      and y.aprovada_em < m.criada_em) < cf.cliente_aprovacao_dias));
  -- a crítica enviada sem a decisão "2) eu mando o aviso escrito"
  select count(*) into v_ccrit
    from public.agenda_cliente_mensagens m
    left join public.agenda_perguntas q on q.id = m.pergunta_id
   where m.enviada_em is not null
     and (m.aprovacao = 'critica'
          or (q.tipo = 'cliente_aviso' and not (q.estado = 'respondida' and q.opcao_escolhida = 2)));
  -- a véspera (M2/M4) enviada com a OS aguardando peça (no registro, ou pela última mudança de status antes do envio)
  select count(*) into v_cvesp
    from public.agenda_cliente_mensagens m
   where m.tipo in ('vespera', 'acesso') and m.enviada_em is not null
     and (m.base ->> 'status' = 'awaiting_parts'
          or (select a.status_depois from public.agenda_acoes a
               where a.service_order_id = m.service_order_id and a.tipo = 'status' and a.executada
                 and a.criada_em <= m.enviada_em
               order by a.criada_em desc, a.id desc limit 1) = 'awaiting_parts');
  -- o aviso de atraso enviado depois da data que o cliente ouviu
  select count(*) into v_cdepois
    from public.agenda_cliente_mensagens m
   where m.tipo = 'pode_atrasar' and m.enviada_em is not null and m.base ? 'prometido_ate'
     and (m.enviada_em at time zone 'America/Sao_Paulo')::date > (m.base ->> 'prometido_ate')::date;
  select count(*) into v_caudio
    from public.agenda_cliente_respostas r where r.tipo_msg = 'audio' and r.efeito = 'confirmou';
  -- as métricas (para depois; nenhuma reprova)
  select jsonb_build_object(
    'm6_antes_da_data_pct_90d', (
      select case when count(*) > 0 then round(100 * (count(*) filter (
               where (m.enviada_em at time zone 'America/Sao_Paulo')::date <= (m.base ->> 'prometido_ate')::date))::numeric
               / count(*)) end
        from public.agenda_cliente_mensagens m
       where m.tipo = 'pode_atrasar' and m.enviada_em > p_agora - interval '90 days' and m.base ? 'prometido_ate'),
    'aprovadas_sem_segurar_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where m.aprovacao = 'aprovada'))::numeric / count(*)) end
        from public.agenda_cliente_mensagens m
       where m.modo = 'ligado' and m.aprovacao in ('aprovada', 'segurada') and m.aprovada_em > p_agora - interval '30 days'),
    'resposta_24h_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where r.recebida_em <= m.enviada_em + interval '1 day'))::numeric
               / count(*)) end
        from public.agenda_cliente_mensagens m
        left join public.agenda_cliente_respostas r on r.id = m.resposta_id
       where m.modo = 'ligado' and m.enviada_em > p_agora - interval '30 days'
         and m.tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')),
    'sim_automatico_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where r.efeito = 'confirmou'))::numeric / count(*)) end
        from public.agenda_cliente_respostas r
       where r.modo = 'ligado' and r.recebida_em > p_agora - interval '30 days' and r.intencao = 'confirma'),
    'opt_outs_30d', (select count(*) from public.agenda_cliente_respostas r
                      where r.intencao = 'opt_out' and r.recebida_em > p_agora - interval '30 days'),
    'falhas_de_entrega_30d', (select count(*) from public.whatsapp_send_queue q
                               where q.source = 'agenda-cliente' and q.status = 'failed'
                                 and q.created_at > p_agora - interval '30 days'),
    'idas_perdidas_por_acesso_90d', (
      select jsonb_build_object('com_aviso', count(*) filter (where t.avisado), 'sem_aviso', count(*) filter (where not t.avisado))
        from (select distinct a.service_order_id, a.dia,
                     exists (select 1 from public.agenda_cliente_mensagens m
                              where m.service_order_id = a.service_order_id and m.tipo in ('vespera', 'acesso')
                                and m.enviada_em is not null and coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) = a.dia) as avisado
                from public.agenda_alocacoes a
               where a.resultado = 'nao_cumprido' and a.motivo = 'cliente_ou_bem' and a.dia > p_hoje - 90 and a.dia <= p_hoje) t))
    into v_cmet;
  v_zeros5 := v_cjan = 0 and v_cdom = 0 and v_cteto = 0 and v_cint = 0 and v_cproib = 0 and v_csombra = 0 and v_csemap = 0
              and v_ccrit = 0 and v_cvesp = 0 and v_cdepois = 0 and v_caudio = 0;
  v_zeros4 := v_zeros4 and v_zeros5;
  v_cli := jsonb_build_object(
    'modo', cf.modo_cliente, 'tipos_ligados', to_jsonb(cf.cliente_tipos_ligados),
    'tipos_liberados', to_jsonb(array(select t from unnest(array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento',
                                                                  'pode_atrasar', 'nova_data', 'pronto', 'pronto_lembrete',
                                                                  'pos_servico', 'mudanca_no_dia']) t
                                       where public._agenda_cliente_tipo_liberado(t))),
    'ultima_rodada', v_crod -> 'ultima_rodada', 'rodou_nas_ultimas_2h', v_crod -> 'rodou_nas_ultimas_2h',
    'erros_24h', v_crod -> 'erros_24h',
    'mensagens_7d', jsonb_build_object('por_tipo', v_cmsg),
    'aprovacao', v_caprov,
    'fora_da_janela', v_cjan, 'em_feriado_ou_domingo', v_cdom, 'acima_do_teto', v_cteto, 'intervalo_curto', v_cint,
    'com_texto_proibido', v_cproib, 'na_fila_em_sombra', v_csombra, 'sem_aprovacao_no_periodo', v_csemap,
    'critica_sem_decisao', v_ccrit, 'vespera_com_os_aguardando_peca', v_cvesp, 'aviso_depois_da_data', v_cdepois,
    'audio_que_confirmou', v_caudio,
    'metricas', v_cmet);
  -- FASE 5: fim
  -- CORREÇÃO FASE 6: (C2) item 12: os zeros obrigatórios de antes do aprendizado (o bloco do aprendizado os junta aos dele; o
  -- bloco da C2 depois dele refaz essa junta com as janelas de agenda_config)
  v_z4_antes := v_zeros4;
  -- CORREÇÃO FASE 6: fim
  -- FASE 6: (P6) o aprendizado (spec-fase6 §11) — o modo, a lista, a rodada, os itens e as métricas. Os "0 obrigatórios"
  -- (entram no ok pelo v_zeros4, como os das Fases 4 e 5): nada em uso com menos medidas que o mínimo; nada que a ÚLTIMA
  -- rodada gravou em uso com o modo dela fora de ligado ou o item fora da lista dela (logo depois de o dono desligar, o leitor
  -- já devolve o padrão; a linha muda na rodada seguinte); nenhuma troca grande que entrou sozinha (as ações da vigia em 7 dias
  -- contra os limites de hoje: a regra de _agenda_aprendizado_troca_cabe, que não tem porta para quem lê a saúde); nenhuma
  -- rodada atrasada (depois da 1ª, nenhuma em 26 h); nenhuma medida sem classe; nenhum fator fora de [fator_min, fator_max].
  -- Os erros de aprender:% em 24 h e as métricas não reprovam.
  select x.p_agora, x.p_hoje, x.contagens into v_arod
    from public.agenda_vigia_rodadas x where x.rotina = 'aprender'
   order by x.p_agora desc, x.rodou_em desc, x.id desc limit 1;
  select count(*) into v_apeq
    from public.agenda_aprendizado a
   where a.estado in ('em_uso', 'pergunta', 'travado') and a.em_uso is not null and a.n < a.n_min;
  select count(*) into v_afora
    from public.agenda_aprendizado a
   where v_arod.p_agora is not null and a.estado = 'em_uso' and a.em_uso is not null and a.calculado_em >= v_arod.p_agora
     and (coalesce(v_arod.contagens ->> 'modo_aprendizado', '') <> 'ligado'
          or not coalesce(v_arod.contagens -> 'ligados' ? public._agenda_aprendizado_da_lista(a.item), false));
  select count(*) into v_agrande
    from public.agenda_acoes a
   where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada and a.criada_em > p_agora - interval '7 days'
     and not coalesce(case a.antes ->> 'item'
           when 'fator' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.fator_troca_max
           when 'mo' then (a.antes ->> 'valor')::numeric > 0
                          and abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                              / (a.antes ->> 'valor')::numeric <= cf.mo_troca_max
           when 'fornecedor_atraso' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                         <= cf.fornecedor_troca_max_du
           when 'fornecedor_prazo' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                        <= cf.fornecedor_troca_max_du
           when 'capacidade_dono' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                       <= cf.capacidade_troca_max
           when 'aviso_folga' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.aviso_troca_max_du
           when 'presenca' then a.antes ->> 'nivel' in ('fina', 'sistema')
         end, false);
  v_aatras := case when v_arod.p_agora is not null and v_arod.p_agora < p_agora - interval '26 hours' then 1 else 0 end;
  select count(*) into v_asemcl from public.agenda_medidas_os m where m.classe_bem is null or m.classe_sistema is null;
  select count(*) into v_afat
    from public.agenda_aprendizado a
   where a.item = 'fator'
     and ((a.calculado is not null and a.calculado not between cf.fator_min and cf.fator_max)
          or (a.em_uso is not null and a.em_uso not between cf.fator_min and cf.fator_max));
  -- as métricas (para depois; nenhuma reprova)
  select jsonb_build_object(
    'itens', coalesce((select jsonb_object_agg(t.item, jsonb_build_object('chaves', t.chaves, 'n_max', t.n_max, 'n_min', t.n_min,
                                                                         'estados', t.estados))
                         from (select a.item, count(*) as chaves, max(a.n) as n_max, max(a.n_min) as n_min,
                                      (select jsonb_object_agg(s.estado, s.n)
                                         from (select b.estado, count(*) as n from public.agenda_aprendizado b
                                                where b.item = a.item group by b.estado) s) as estados
                                 from public.agenda_aprendizado a group by a.item) t), '{}'::jsonb),
    'medidas', (select jsonb_build_object('total', count(*), 'validas', count(*) filter (where m.valida),
                                          'invalidas', coalesce((select jsonb_object_agg(y.motivo, y.n)
                                                                   from (select z.motivo, count(*) as n from public.agenda_medidas_os z
                                                                          where not z.valida
                                                                            and z.concluida_em > p_hoje - cf.aprender_janela_dias
                                                                          group by z.motivo) y), '{}'::jsonb))
                  from public.agenda_medidas_os m where m.concluida_em > p_hoje - cf.aprender_janela_dias),
    'trocas_30d', jsonb_build_object(
      'sozinhas', (select count(*) from public.agenda_acoes a
                    where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada and a.criada_em > p_agora - interval '30 days'),
      'perguntas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.criada_em > p_agora - interval '30 days'),
      'decididas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.estado = 'respondida' and q.respondida_em > p_agora - interval '30 days'),
      'desfeitas', (select count(*) from public.agenda_acoes a
                     where a.tipo = 'aprendizado' and a.desfeita_em > p_agora - interval '30 days')),
    -- o erro do fator: das OS válidas concluídas depois que o fator da classe delas passou a valer, quantas ficaram dentro dele
    'erro_do_fator', (select case when count(*) > 0 then jsonb_build_object('dentro', count(*) filter (where t.fator <= t.uso),
                                                                           'medidas', count(*),
                                                                           'pct', round(100 * (count(*) filter (where t.fator <= t.uso))::numeric / count(*))) end
                        from (select m.fator, u.em_uso as uso
                                from public.agenda_medidas_os m
                                cross join lateral (
                                  select a.em_uso, a.em_uso_desde from public.agenda_aprendizado a
                                   where a.item = 'fator' and a.estado = 'em_uso'
                                     and a.chave in (m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                     'bem:' || m.classe_bem, 'todas')
                                   order by array_position(array[m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                                 'bem:' || m.classe_bem, 'todas'], a.chave)
                                   limit 1) u
                               where m.valida and m.concluida_em >= (u.em_uso_desde at time zone 'America/Sao_Paulo')::date) t),
    -- a pontualidade com o cliente antes e depois de a folga do aviso valer
    'pontualidade_folga', (select case when f.desde is not null then jsonb_build_object(
                                     'desde', f.desde,
                                     'antes_pct', (select round(100 * avg((m.atraso_cliente_du <= 0)::int)) from public.agenda_medidas_os m
                                                    where m.atraso_cliente_du is not null and m.concluida_em < f.desde),
                                     'depois_pct', (select round(100 * avg((m.atraso_cliente_du <= 0)::int)) from public.agenda_medidas_os m
                                                     where m.atraso_cliente_du is not null and m.concluida_em >= f.desde)) end
                             from (select (min(a.em_uso_desde) at time zone 'America/Sao_Paulo')::date as desde
                                     from public.agenda_aprendizado a where a.item = 'aviso_folga' and a.em_uso is not null) f),
    -- parar (§11): o item que o dono desfez 2 vezes em 4 semanas (recomendar tirá-lo da lista; a decisão é dele)
    'desfeito_2x_em_4_semanas', coalesce((select jsonb_agg(t.item order by t.item)
                                            from (select a.antes ->> 'item' as item from public.agenda_acoes a
                                                   where a.tipo = 'aprendizado' and a.desfeita_em > p_agora - interval '28 days'
                                                   group by 1 having count(distinct a.desfeita_em) >= 2) t), '[]'::jsonb))
    into v_amet;
  v_zeros6 := v_apeq = 0 and v_afora = 0 and v_agrande = 0 and v_aatras = 0 and v_asemcl = 0 and v_afat = 0;
  v_zeros4 := v_zeros4 and v_zeros6;
  v_apr := jsonb_build_object(
    'modo', cf.modo_aprendizado, 'ligados', to_jsonb(cf.aprendizado_ligados),
    'ultima_rodada', v_arod.p_agora,
    'rodou_hoje', exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'aprender' and x.p_hoje = p_hoje),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.action like 'aprender:%'
                     and e.last_seen_at >= least(p_agora, now()) - interval '1 day'),
    'em_uso_com_amostra_pequena', v_apeq, 'em_uso_fora_de_ligado', v_afora, 'troca_grande_sem_pergunta', v_agrande,
    'rodada_atrasada', v_aatras, 'medida_sem_classe', v_asemcl, 'fator_fora_dos_limites', v_afat,
    'metricas', v_amet);
  -- FASE 6: fim
  -- CORREÇÃO FASE 6: (C2) item 12: as janelas do aprendizado na saúde vêm de agenda_config (eram números escritos aqui): a
  -- troca grande que entrou sozinha, nas ações dos últimos aprender_saude_dias (era 7 dias); a rodada atrasada, sem rodada há
  -- mais de aprender_atraso_h (era 26 h); as trocas das métricas, nos últimos aprender_parar_dias (era 30 dias; a chave
  -- trocas_30d fica com o nome); o item desfeito 2 vezes dentro de aprender_trava_dias (era 28 dias, as "4 semanas" da §11).
  -- As contas de cima não valem mais: refeitas aqui com o parâmetro (com os DEFAULTs, o mesmo resultado), e com elas os
  -- zeros, o ok e o bloco aprendizado.
  select count(*) into v_agrande
    from public.agenda_acoes a
   where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada
     and a.criada_em > p_agora - make_interval(days => cf.aprender_saude_dias)
     and not coalesce(case a.antes ->> 'item'
           when 'fator' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.fator_troca_max
           when 'mo' then (a.antes ->> 'valor')::numeric > 0
                          and abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                              / (a.antes ->> 'valor')::numeric <= cf.mo_troca_max
           when 'fornecedor_atraso' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                         <= cf.fornecedor_troca_max_du
           when 'fornecedor_prazo' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                        <= cf.fornecedor_troca_max_du
           when 'capacidade_dono' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                       <= cf.capacidade_troca_max
           when 'aviso_folga' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.aviso_troca_max_du
           when 'presenca' then a.antes ->> 'nivel' in ('fina', 'sistema')
         end, false);
  v_aatras := case when v_arod.p_agora is not null
                        and v_arod.p_agora < p_agora - make_interval(hours => cf.aprender_atraso_h) then 1 else 0 end;
  v_amet := v_amet || jsonb_build_object(
    'trocas_30d', jsonb_build_object(
      'sozinhas', (select count(*) from public.agenda_acoes a
                    where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada
                      and a.criada_em > p_agora - make_interval(days => cf.aprender_parar_dias)),
      'perguntas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.criada_em > p_agora - make_interval(days => cf.aprender_parar_dias)),
      'decididas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.estado = 'respondida'
                       and q.respondida_em > p_agora - make_interval(days => cf.aprender_parar_dias)),
      'desfeitas', (select count(*) from public.agenda_acoes a
                     where a.tipo = 'aprendizado' and a.desfeita_em > p_agora - make_interval(days => cf.aprender_parar_dias))),
    'desfeito_2x_em_4_semanas', coalesce((select jsonb_agg(t.item order by t.item)
                                            from (select a.antes ->> 'item' as item from public.agenda_acoes a
                                                   where a.tipo = 'aprendizado'
                                                     and a.desfeita_em > p_agora - make_interval(days => cf.aprender_trava_dias)
                                                   group by 1 having count(distinct a.desfeita_em) >= 2) t), '[]'::jsonb));
  v_zeros6 := v_apeq = 0 and v_afora = 0 and v_agrande = 0 and v_aatras = 0 and v_asemcl = 0 and v_afat = 0;
  v_zeros4 := v_z4_antes and v_zeros6;
  v_apr := v_apr || jsonb_build_object('troca_grande_sem_pergunta', v_agrande, 'rodada_atrasada', v_aatras, 'metricas', v_amet);
  -- CORREÇÃO FASE 6: fim
  -- FASE 7: (7a P7, spec §11) o bloco gestor: os modos efetivos, a última rodada (rotina gestor), os erros de gestor:% em 24 h, os
  -- zeros obrigatórios (entram no ok, salvo prazo_vencido_sem_mostrar, que só se conta: a pergunta fica aberta) e os números. Os
  -- zeros do que o gestor muda sozinho contam a partir do OK de ligar (marcar_sozinho_desde): antes dele não há o que contar.
  -- E (aviso do P6) o erro do fator só com as medidas que têm fator: a medida por estimativa é válida e não tem fator.
  v_gdesde := cf.marcar_sozinho_desde;
  v_gmodos := jsonb_build_object('marcar', public._agenda_gestor_modo('marcar'), 'encaixe', public._agenda_gestor_modo('encaixe'),
                                 'revisao', public._agenda_gestor_modo('revisao'), 'compre_ate', public._agenda_gestor_modo('compre_ate'),
                                 'vaga', public._agenda_gestor_modo('vaga'), 'so_propor', cf.gestor_so_propor, 'desde', v_gdesde);
  select max(x.p_agora) as ultima,
         count(*) filter (where x.p_agora > p_agora - interval '1 day' and x.p_agora <= p_agora) as n24,
         coalesce(bool_or(x.p_hoje = p_hoje and x.contagens ? 'diaria'), false) as diaria_hoje,
         (array_agg(x.erros order by x.p_agora desc, x.rodou_em desc))[1] as erros_ult
    into v_gult from public.agenda_vigia_rodadas x where x.rotina = 'gestor';
  v_gz := jsonb_build_object(
    -- o dia que o cliente ouviu e o dia que a equipe já sabia, mudados sem a pergunta crítica (a regra de _agenda_criticidade_da_acao)
    'zona_travada_mexida', (select count(*) from public.agenda_acoes a
                             where v_gdesde is not null and a.criada_em >= v_gdesde and a.executada and not a.critica
                               and a.origem in ('motor', 'vigia', 'conferencia')
                               and a.tipo in ('publicar', 'criar', 'mover', 'cancelar', 'promover_reserva', 'soltar_reserva')
                               and public._agenda_criticidade_da_acao(a.id) = 'dia_prometido'),
    'dia_avisado_sem_pergunta', (select count(*) from public.agenda_acoes a
                                  where v_gdesde is not null and a.criada_em >= v_gdesde and a.executada and not a.critica
                                    and a.origem in ('motor', 'vigia', 'conferencia')
                                    and a.tipo in ('publicar', 'criar', 'mover', 'cancelar', 'promover_reserva', 'soltar_reserva')
                                    and public._agenda_criticidade_da_acao(a.id) = 'dia_avisado'),
    -- marcada pela estimativa sem a pergunta que ela pedia (grande, começada/parada, sem mão de obra, peça embutida)
    'estimativa_sem_pergunta', case when not public._agenda_gestor_regra('estimativa') then 0 else (
       select count(*) from (select distinct a.service_order_id as os from public.agenda_alocacoes a
                               left join public.os_planejamento pl on pl.service_order_id = a.service_order_id
                              where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
                                and a.resultado is null and a.duracao_fonte = 'orcamento' and pl.dias is null) o
        where coalesce(public._agenda_gestor_estimativa(o.os, p_hoje) ->> 'motivo', '') in ('grande', 'situacao', 'sem_base', 'embutida')) end,
    'prazo_em_critica', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.critica and q.veto_ate is not null),
    'prazo_em_dia_prometido', (select count(*) from public.agenda_perguntas q
                                where q.estado = 'aberta' and q.veto_ate is not null and q.tipo = 'dia_prometido'),
    -- aprovada há mais de aprovada_sem_data_min sem dia, sem reserva, sem pergunta aberta e sem o motor ter dito por que fica de
    -- fora depois da aprovação (com o encaixe na aprovação ligado: antes dele, quem encaixa é a vigia e a publicação)
    'aprovada_sem_data', case when public._agenda_gestor_modo('encaixe') <> 'ligado' then 0 else (
       select count(*) from public.os_carteira(p_hoje) k join public.service_orders so on so.id = k.service_order_id
        where coalesce(so.converted_to_os_at, so.signed_at) is not null
          and coalesce(so.converted_to_os_at, so.signed_at) < p_agora - make_interval(mins => cf.aprovada_sem_data_min)
          and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = k.service_order_id
                           and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null)
          and not exists (select 1 from public.agenda_perguntas q where q.estado = 'aberta' and q.service_order_id = k.service_order_id)
          and not exists (select 1 from public.agenda_propostas pr cross join lateral jsonb_array_elements(coalesce(pr.fora, '[]'::jsonb)) f
                           where pr.criada_em >= coalesce(so.converted_to_os_at, so.signed_at)
                             and (f ->> 'os')::uuid = k.service_order_id)) end,
    -- sem rodada do gestor em 40 min, de 07:30 a 21:00 de dia útil, com algum modo do gestor fora de desligado
    'rodada_gestor_atrasada', case when (v_gmodos ->> 'marcar' <> 'desligado' or v_gmodos ->> 'encaixe' <> 'desligado'
                                         or v_gmodos ->> 'revisao' <> 'desligado' or v_gmodos ->> 'compre_ate' <> 'desligado')
                                        and public.agenda_dia_util(p_hoje)
                                        and (p_agora at time zone 'America/Sao_Paulo')::time between time '07:30' and time '21:00'
                                        and coalesce(v_gult.ultima < p_agora - interval '40 minutes', true) then 1 else 0 end,
    -- a mensagem ao cliente por estimativa que saiu sem o sim do dono antes de somar cliente_aprovacao_dias dias aprovados
    'cliente_estimativa_sem_aprovacao', (
       select count(*) from public.agenda_cliente_mensagens m
        where v_gdesde is not null and m.criada_em >= v_gdesde and m.base -> 'dados' ->> 'por_estimativa' = 'true'
          and m.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta') and m.aprovacao <> 'aprovada'
          and (select count(distinct (n.aprovada_em at time zone 'America/Sao_Paulo')::date) from public.agenda_cliente_mensagens n
                where n.tipo = m.tipo and n.base -> 'dados' ->> 'por_estimativa' = 'true' and n.aprovacao = 'aprovada'
                  and n.aprovada_em < m.criada_em) < cf.cliente_aprovacao_dias),
    -- a ficha de um dia por estimativa que saiu na janela de veto sem a pergunta ficha_estimativa mostrada (ou segurada com 2)
    'ficha_estimativa_sem_veto', (
       select count(*) from public.agenda_equipe_mensagens em
        where v_gdesde is not null and em.tipo = 'ficha' and em.modo = 'ligado'
          and em.estado in ('enfileirada', 'respondida', 'sem_resposta')
          and em.dia >= (v_gdesde at time zone 'America/Sao_Paulo')::date
          and em.dia < (v_gdesde at time zone 'America/Sao_Paulo')::date + cf.ficha_veto_dias
          and exists (select 1 from public.agenda_alocacoes a where a.payee_id = em.payee_id and a.dia = em.dia
                       and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.duracao_fonte = 'orcamento')
          and not exists (select 1 from public.agenda_perguntas q
                           where q.chave = 'ficha_estimativa:' || em.payee_id || ':' || em.dia and q.mostrada_vezes > 0
                             and q.opcao_escolhida is distinct from 2)),
    -- a rodada que mudou o dia de mais de gestor_k_os OS de uma vez sem a pergunta onda
    'onda_aplicada_sem_pergunta', (
       select count(*) from (select a.proposta_id from public.agenda_acoes a
                               where v_gdesde is not null and a.criada_em >= v_gdesde and a.executada and not a.critica
                                 and a.origem in ('motor', 'vigia') and a.tipo = 'mover' and a.proposta_id is not null
                               group by a.proposta_id having count(distinct a.service_order_id) > cf.gestor_k_os) p
        where not exists (select 1 from public.agenda_perguntas q where q.tipo = 'onda' and q.proposta_id = p.proposta_id)),
    -- o compromisso novo sem de onde veio a duração (o gatilho _agenda_alocacao_fonte grava em toda alocação nova)
    'alocacao_sem_fonte', (select count(*) from public.agenda_alocacoes a
                            where v_gdesde is not null and a.criado_em >= v_gdesde and a.tipo <> 'reserva' and a.duracao_fonte is null),
    -- a ação do gestor feita numa rodada em que o modo dela não estava ligado (estimar: marcar; reestimar e reparar: revisao)
    'regra_em_sombra_aplicada', (
       select count(*) from public.agenda_acoes a
        where a.executada and a.origem = 'vigia' and a.tipo in ('estimar', 'reestimar', 'reparar')
          and a.criada_em > p_agora - interval '7 days'
          and coalesce((select r.contagens -> 'modos' ->> case when a.tipo = 'estimar' then 'marcar' else 'revisao' end
                          from public.agenda_vigia_rodadas r
                         where r.rotina = 'gestor' and r.p_agora <= a.criada_em
                         order by r.p_agora desc, r.rodou_em desc limit 1), 'desligado') <> 'ligado'),
    -- a pergunta com prazo vencido que o dono nunca viu antes do prazo: fica aberta (aqui só se conta; não entra no ok)
    'prazo_vencido_sem_mostrar', (select count(*) from public.agenda_perguntas q
                                   where q.estado = 'aberta' and q.veto_ate is not null and q.veto_ate < p_agora
                                     and not coalesce(q.mostrada_vezes > 0 and q.mostrada_em < q.veto_ate, false)));
  v_gzeros := not exists (select 1 from jsonb_each(v_gz) z where z.key <> 'prazo_vencido_sem_mostrar' and (z.value)::text <> '0');
  v_ges := jsonb_build_object(
    'modos', v_gmodos, 'regras', to_jsonb(cf.marcar_regras),
    'ultima_rodada', v_gult.ultima, 'rodadas_24h', coalesce(v_gult.n24, 0), 'diaria_hoje', coalesce(v_gult.diaria_hoje, false),
    'erros_ultima_rodada', coalesce(v_gult.erros_ult, 0),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.action like 'gestor:%' and e.last_seen_at >= least(p_agora, now()) - interval '1 day'),
    'zeros_ok', v_gzeros,
    'numeros', jsonb_build_object(
      'os_por_estimativa', (select count(distinct a.service_order_id) from public.agenda_alocacoes a
                             where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
                               and a.resultado is null and a.duracao_fonte = 'orcamento'),
      'perguntas_com_prazo', jsonb_build_object(
        'abertas', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.veto_ate is not null),
        'vencidas', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.veto_ate is not null and q.veto_ate < p_agora),
        'respondidas_7d', (select count(*) from public.agenda_perguntas q where q.estado = 'respondida' and q.veto_ate is not null
                             and q.respondida_em > p_agora - interval '7 days'),
        'pelo_prazo_7d', (select count(*) from public.agenda_acoes a where a.tipo = 'estimar' and a.origem = 'vigia' and a.executada
                            and a.criada_em > p_agora - interval '7 days')),
      'compre_ate', jsonb_build_object(
        'gravados', (select count(*) from public.os_material m where m.compre_ate is not null),
        'cobrados', (select count(*) from public.os_material m where m.cobrado_vezes > 0),
        'empurrados', (select count(*) from public.os_material m where m.empurrada_vezes > 0)),
      'fichas_seguradas_7d', (select count(*) from public.agenda_equipe_mensagens em
                               where em.recusa_motivo = 'veto' and em.criada_em > p_agora - interval '7 days'))) || v_gz;
  v_amet := v_amet || jsonb_build_object(
    'erro_do_fator', (select case when count(*) > 0 then jsonb_build_object('dentro', count(*) filter (where t.fator <= t.uso),
                                                                           'medidas', count(*),
                                                                           'pct', round(100 * (count(*) filter (where t.fator <= t.uso))::numeric / count(*))) end
                        from (select m.fator, u.em_uso as uso
                                from public.agenda_medidas_os m
                                cross join lateral (
                                  select a.em_uso, a.em_uso_desde from public.agenda_aprendizado a
                                   where a.item = 'fator' and a.estado = 'em_uso'
                                     and a.chave in (m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                     'bem:' || m.classe_bem, 'todas')
                                   order by array_position(array[m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                                 'bem:' || m.classe_bem, 'todas'], a.chave)
                                   limit 1) u
                               where m.valida and m.fator is not null
                                 and m.concluida_em >= (u.em_uso_desde at time zone 'America/Sao_Paulo')::date) t));
  v_apr := v_apr || jsonb_build_object('metricas', v_amet);
  v_gr := jsonb_build_object(
    -- os zeros obrigatórios da execução (a Fase 3), do material e da mensagem ao fornecedor (a Fase 4) e os do gestor entram no ok
    'ok', v_sem = 0 and (v_regra ->> 'n')::int = 0 and v_choques = 0
          and v_teto = 0 and v_janela = 0 and v_semconf = 0 and v_sobre = 0 and coalesce(v_semrec, 0) = 0 and v_pay = 0
          and v_zeros4
          and v_gzeros,
    'modos', jsonb_build_object('leitura', cf.modo_leitura, 'proposta', cf.modo_proposta, 'vigia', cf.modo_vigia),
    'vigia', v_vig, 'hoje', v_hoje, 'criticas', v_crit, 'perguntas', v_perg, 'propostas', v_prop, 'plano', v_plano,
    'invariantes', v_inv, 'fechamento', v_fech,
    'rotina', v_rot, 'equipe', v_eq, 'diarias', v_dia, 'conclusao', v_conc, 'marcos', v_marcos, 'comissao', v_com,
    'modos_fase3', jsonb_build_object('equipe', cf.modo_equipe, 'diaria', cf.modo_diaria),
    'cliente', v_cli,
    'aprendizado', v_apr,
    'material', v_mat,
    'gestor', v_ges);
  -- FASE 7b (P5, §5.4, R4.3(g); dentro do bloco do gestor da 7a, que monta a saída e volta aqui — por isso sem os dois-pontos depois
  -- de "7b": os tiradores de antes tiram o bloco do gestor inteiro e não o leem como bloco próprio): a chave equipe_dias
  -- (_agenda_saude_equipe7b: as mensagens dias à equipe, a dupla no plano, quem nunca fica sozinho, o sábado, o dono numa vaga e a
  -- resposta gravada), com os zeros obrigatórios no ok. Sem os modos da 7b, os zeros são 0 e o ok é o de antes.
  v_gr := v_gr || jsonb_build_object('equipe_dias', public._agenda_saude_equipe7b(p_hoje, p_agora));
  v_gr := jsonb_set(v_gr, '{ok}', to_jsonb(coalesce((v_gr ->> 'ok')::boolean, false)
                                            and coalesce((v_gr #>> '{equipe_dias,zeros_ok}')::boolean, true)));
  -- FASE 7b (P5): fim
  -- (7d P8; §11, R6.3-11; dentro do bloco do gestor: por isso a marca, não o bloco) a chave local (_agenda_saude_local), com os zeros obrigatórios no ok. Sem os modos da 7d, os
  -- zeros são 0 e o ok é o de antes.
  v_gr := v_gr || jsonb_build_object('local', public._agenda_saude_local(p_hoje, p_agora));
  v_gr := jsonb_set(v_gr, '{ok}', to_jsonb(coalesce((v_gr ->> 'ok')::boolean, false)
                                            and coalesce((v_gr #>> '{local,zeros_ok}')::boolean, true)));
  -- O M11 na lista dos liberados (o recado do P6): aqui, e não na lista dos 11 lá em cima, que fica dentro do bloco da Fase 5
  if public._agenda_cliente_tipo_liberado('onde_fica') then
    v_gr := jsonb_set(v_gr, '{cliente,tipos_liberados}', (v_gr #> '{cliente,tipos_liberados}') || '["onde_fica"]'::jsonb);
  end if;
  -- (7d: fim)
  return v_gr;
  -- FASE 7: fim
  return jsonb_build_object(
    -- FASE 3: os zeros obrigatórios da execução entram no ok.
    'ok', v_sem = 0 and (v_regra ->> 'n')::int = 0 and v_choques = 0
          and v_teto = 0 and v_janela = 0 and v_semconf = 0 and v_sobre = 0 and coalesce(v_semrec, 0) = 0 and v_pay = 0
          -- FASE 4: os zeros obrigatórios do material e da mensagem ao fornecedor entram no ok.
          and v_zeros4,
          -- FASE 4: fim
    'modos', jsonb_build_object('leitura', cf.modo_leitura, 'proposta', cf.modo_proposta, 'vigia', cf.modo_vigia),
    'vigia', v_vig, 'hoje', v_hoje, 'criticas', v_crit, 'perguntas', v_perg, 'propostas', v_prop, 'plano', v_plano,
    'invariantes', v_inv, 'fechamento', v_fech,
    -- FASE 3
    'rotina', v_rot, 'equipe', v_eq, 'diarias', v_dia, 'conclusao', v_conc, 'marcos', v_marcos, 'comissao', v_com,
    'modos_fase3', jsonb_build_object('equipe', cf.modo_equipe, 'diaria', cf.modo_diaria),
    -- FASE 5: a mensagem ao cliente
    'cliente', v_cli,
    -- FASE 5: fim
    -- FASE 6: o aprendizado
    'aprendizado', v_apr,
    -- FASE 6: fim
    -- FASE 4: o material
    'material', v_mat);
    -- FASE 4: fim
end;
$function$;

comment on function public.agenda_saude(date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): a conferência depois de cada deploy e o painel da sombra — {ok, modos, vigia (última rodada, rodou nas últimas 2 h, erros em 24 h no app_error_logs context agenda, rodadas em 24 h), hoje (publicar, criar, mover, cancelar, promover, soltar, status, resultado, desfeitas, sombra), criticas (abertas, respondidas em 7 dias, sem_decisao e pela_regra_sem_decisao — têm de ser 0), perguntas (abertas por tipo, mostradas hoje), propostas, plano (vigentes futuras, OS programadas, reservas, sem registro em 7 dias), invariantes (vigente de OS fora da carteira, espelho divergente em ligado, choques = 0), fechamento (leu o plano hoje: resumo_tarde.detalhe.agenda; linhas mostradas)}. Leitura (invoker): authenticated (a RLS do admin vale) e service_role. Fase 3: a vigia lê só as rodadas dela (rotina = vigia); blocos rotina (última rodada, rodou nas últimas 2 h, erros 24 h), equipe (mensagens e recusas de hoje; acima_do_teto e fora_da_janela — também o que saiu fora dela — têm de ser 0), diarias (lançadas e em teste em 7 dias, perguntas abertas; sem_confirmacao e sobrescreveu_turno têm de ser 0), conclusao (pela agenda e desfeitas em 7 dias; sem_recebivel_quando_devia = 0, só para quem lê a releitura), marcos (N4), comissao (pagamento desligado; payables de comissão de técnico em 7 dias = 0) e modos_fase3; o ok inclui esses zeros. Fase 4 (P5): o bloco material — modos (material, detector, fornecedor), a rodada do material (rotina = material: última, rodou nas últimas 2 h, erros 24 h em material:%), remessas (a caminho, sem resposta, ligadas/sem serviço/chegaram em 7 dias), perguntas (as abertas da Fase 4 por tipo; pix_na_semana), detector (agenda_detector_precisao dos últimos 14 dias — só para administrador/financeiro ou sem login —, aplicados e desfeitos em 7 dias), fornecedor (registradas, enfileiradas, em teste e recusadas por motivo em 7 dias), cobertura (itens críticos das OS que começam nas próximas material_inicio_dias e quantos têm data, nível A–D), espera (mediana da aprovação à 1ª compra, OS aprovadas em 90 dias); os zeros obrigatórios entram no ok: vinculo_sem_resposta_do_dono, previsao_sem_original e, do fornecedor, na_fila_em_sombra, fora_da_janela, acima_do_teto e com_valor_ou_cliente. Fase 5 (P3): o bloco cliente — modo, tipos_ligados, tipos_liberados (somaram cliente_aprovacao_dias dias aprovados), a rodada do cliente (rotina = cliente: última, rodou nas últimas 2 h, erros 24 h em cliente:%), mensagens_7d por tipo (registradas, aguardando, enviadas, recusadas por motivo), aprovacao (pedidas abertas, vencidas, aprovadas e seguradas em 7 dias) e as métricas (M6 antes da data, aprovadas sem segurar, resposta em 1 dia, SIM automático, opt-outs, falhas de entrega, idas perdidas por acesso com e sem véspera); os zeros obrigatórios entram no ok: fora_da_janela, em_feriado_ou_domingo, acima_do_teto, intervalo_curto, com_texto_proibido, na_fila_em_sombra, sem_aprovacao_no_periodo, critica_sem_decisao, vespera_com_os_aguardando_peca, aviso_depois_da_data e audio_que_confirmou. Fase 6 (P6): a chave aprendizado — o modo, a lista, a última rodada, os erros de aprender:% em 24 h, os 6 zeros (em_uso_com_amostra_pequena, em_uso_fora_de_ligado, troca_grande_sem_pergunta, rodada_atrasada, medida_sem_classe, fator_fora_dos_limites; entram no ok) e as métricas (itens, medidas, trocas em 30 dias, o erro do fator, a pontualidade antes e depois da folga, o item desfeito 2 vezes em 4 semanas). CORREÇÃO FASE 6 (C2, item 12): as janelas do aprendizado vêm de agenda_config — a troca grande em aprender_saude_dias, a rodada atrasada em aprender_atraso_h, as métricas das trocas em aprender_parar_dias e o desfeito 2 vezes em aprender_trava_dias. FASE 7 (7a P7, spec §11): a chave gestor — os modos efetivos (marcar, encaixe, revisao, compre_ate, vaga, so_propor, desde), as regras, a última rodada (rotina gestor), as rodadas em 24 h, se os passos diários rodaram hoje, os erros de gestor:% em 24 h, os zeros obrigatórios (entram no ok: zona_travada_mexida e dia_avisado_sem_pergunta pela regra de _agenda_criticidade_da_acao, estimativa_sem_pergunta, prazo_em_critica, prazo_em_dia_prometido, aprovada_sem_data, rodada_gestor_atrasada, cliente_estimativa_sem_aprovacao, ficha_estimativa_sem_veto, onda_aplicada_sem_pergunta, alocacao_sem_fonte, regra_em_sombra_aplicada; os do que o gestor muda sozinho contam a partir de marcar_sozinho_desde) e prazo_vencido_sem_mostrar (só se conta: fica fora do ok), e os números (OS por estimativa, perguntas com prazo abertas/vencidas/respondidas/aplicadas pelo prazo, compre até gravados/cobrados/empurrados, fichas seguradas). E o erro do fator (métricas do aprendizado) só com as medidas que têm fator (a medida por estimativa é válida e não tem fator). FASE 7b (P5, §5.4, R4.3(g)): a chave equipe_dias (_agenda_saude_equipe7b): modos (dias, dupla, sabado, cadastro, chamar), a última rodada da semana da equipe e os erros de equipe_semana:% em 24 h, os zeros obrigatórios (entram no ok: dias_fora_da_janela, dias_duas_na_semana, dia_acima_do_teto, ficha_recusada_por_teto_com_dias, dupla_com_uma_pessoa — só a dita —, dupla_incompleta_com_gente_livre, novato_sozinho, sabado_sem_prazo, sabado_tarde, dono_em_vaga_sem_ok, resposta_sem_gravar) e os números (perguntadas × respondidas na última semana fechada e o %, adiadas pelo teto em 7 dias, a dupla inferida esperando o ajudante, duplas inferidas × ditas, sábados usados e em teste, a semana passada por pessoa: declarada × usada × cumprida). Sem os modos da 7b, os zeros são 0 e o ok é o de antes. FASE 7d (P8; §11, R6.3-11): a chave local (_agenda_saude_local), com os zeros obrigatórios no ok (acesso_sem_preparo, feriado_local_marcado, patio_acima_das_vagas, viagem_quebrada, rodada_local_atrasada); onde_fica em tipos_liberados. Sem os modos da 7d, os zeros são 0 e o ok é o de antes.';

-- _agenda_cliente_da_os (de 20261029100700_agenda_fase6_acabamento.sql)
create or replace function public._agenda_cliente_da_os(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf        public.agenda_config := public._agenda_cfg();
  v_agora   timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  so        record;
  pl        public.os_planejamento%rowtype;
  v_tel     boolean;
  v_sem     boolean;
  v_conv    boolean;
  v_contato text;
  v_prom    jsonb;
  v_risco   jsonb;
  v_risco_t text;
  v_msgs    jsonb;
  v_total   int;
  v_esp     int;
  v_ped     int;
  v_esp_t   text;
  -- estrutura, não parâmetro: a lista curta do cartão (spec §5.6, "até 5"); o resto, *agenda clientes* mostra
  c_lista   constant int := 5;
begin
  select s.id, s.client_id, s.client_confirmed_for,
         public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(c.display_name, '')), ''), c.name)) as nome
    into so
    from public.service_orders s left join public.clients c on c.id = s.client_id
   where s.id = p_os;
  if so.id is null or so.client_id is null then
    return null;
  end if;
  select * into pl from public.os_planejamento x where x.service_order_id = p_os;

  -- o contato (as mesmas regras do envio e do foco: o número que é de alguém da HBR conta como sem telefone)
  v_tel := public._agenda_cliente_telefone(so.client_id) is not null;
  v_sem := public._agenda_cliente_sem_mensagem(so.client_id);
  v_conv := public._agenda_cliente_conversou(so.client_id, v_agora);
  v_contato := case when not v_tel then 'sem telefone no cadastro'
                    when v_sem then 'pediu para não receber mensagens'
                    when not v_conv then 'não escreveu para a HBR no último ano; por ora só mando a quem já escreveu' end;

  -- o que foi dito ao cliente (≠ o plano) e se ainda vale
  if pl.prometido_ate is not null then
    v_risco := public._agenda_cliente_risco(p_os, p_hoje);
    if coalesce((v_risco ->> 'risco')::boolean, false) then
      v_risco_t := case
        when coalesce((v_risco ->> 'sem_data')::boolean, false)
          then 'Pode atrasar: o material ainda não tem previsão, então ainda não sei a data nova.'
        when v_risco ->> 'faixa_de' = v_risco ->> 'faixa_ate'
          then format('Pode atrasar: agora a previsão é %s.', public._dia_curto((v_risco ->> 'faixa_de')::date))
        else format('Pode atrasar: agora a previsão é de %s a %s.', public._dia_curto((v_risco ->> 'faixa_de')::date),
                    public._dia_curto((v_risco ->> 'faixa_ate')::date)) end
        || case when coalesce((v_risco ->> 'passou')::boolean, false) then ' A data que ele ouviu já passou.' else '' end;
      -- FASE 6: (P7) sem "ele" (spec-fase6 §6.4): " A data dita já passou." (pelo ralo do texto ao dono)
      v_risco_t := public._agenda_cliente_sem_artigo(v_risco_t, p_os);
      -- FASE 6: fim
    end if;
    v_prom := jsonb_build_object(
      'tipo', pl.prometido_tipo, 'de', coalesce(pl.prometido_de, pl.prometido_ate), 'ate', pl.prometido_ate,
      'original_ate', pl.prometido_original_ate, 'fonte', pl.prometido_fonte,
      'texto', case when coalesce(pl.prometido_de, pl.prometido_ate) = pl.prometido_ate then public._dia_curto(pl.prometido_ate)
                    else format('de %s a %s', public._dia_curto(pl.prometido_de), public._dia_curto(pl.prometido_ate)) end
               || format(' (%s, %s%s)',
                         case pl.prometido_tipo when 'firme' then 'data firme' when 'faixa' then 'uma faixa'
                                                else 'depende da peça' end,
                         case pl.prometido_fonte when 'mensagem' then 'por mensagem da agenda' when 'dono' then 'por você'
                                                 else 'pela confirmação' end,
                         coalesce(' em ' || public._dia_curto((pl.prometido_em at time zone 'America/Sao_Paulo')::date), ''))
               || case when pl.prometido_original_ate is not null and pl.prometido_original_ate <> pl.prometido_ate
                       then format('; a 1ª data dita foi %s', public._dia_curto(pl.prometido_original_ate)) else '' end,
      'risco_texto', v_risco_t);
  end if;

  -- as mensagens desta OS: as 5 mais recentes (a que vai sair primeiro, depois as que saíram), com o estado como o dono lê
  select count(*)::int into v_total from public.agenda_cliente_mensagens m where m.service_order_id = p_os;
  select coalesce(jsonb_agg(y.j order by y.quando desc, y.id desc), '[]'::jsonb) into v_msgs
    from (select m.id, coalesce(m.enviada_em, m.enviar_em) as quando,
                 jsonb_build_object(
                   'tipo', m.tipo,
                   'tipo_texto', public._agenda_maiuscula(public._agenda_cliente_tipo_texto(m.tipo)),
                   'quando_texto', case
                     -- a viva: quando sai ("agora", "amanhã às 09:00"; a do teste, só a que ainda vai sair); a que saiu
                     -- ou a do teste que teria saído: o dia e a hora
                     when m.enviada_em is null and m.estado in ('registrada', 'aguardando_dono', 'enfileirada')
                          and (m.modo = 'ligado' or m.enviar_em > v_agora)
                       then public._agenda_cliente_quando_texto(m.enviar_em, v_agora)
                     else public._dia_curto((coalesce(m.enviada_em, m.enviar_em) at time zone 'America/Sao_Paulo')::date)
                          || ' às ' || to_char(coalesce(m.enviada_em, m.enviar_em) at time zone 'America/Sao_Paulo', 'HH24:MI') end,
                   'estado', m.estado,
                   'estado_texto', case
                     when m.modo = 'sombra' then case
                       when m.estado = 'recusada' then 'em teste: não sairia'
                       when m.enviar_em <= v_agora then 'em teste: teria saído'
                       else 'em teste: sairia' end
                     when m.estado = 'aguardando_dono' and m.aprovacao = 'critica'
                       then 'é uma decisão sua: responda na conversa (1, 2 ou 3)'
                     when m.estado = 'aguardando_dono' and m.aprovacao = 'pedida'
                       then 'espera você'
                     when m.estado in ('registrada', 'aguardando_dono') and m.aprovacao = 'aprovada'
                       then format('você aprovou (para não mandar: *segura cliente %s*)', so.nome)
                     when m.estado in ('registrada', 'aguardando_dono')
                       then format('sai sozinha (para não mandar: *segura cliente %s*)', so.nome)
                     when m.estado = 'enfileirada' then 'na fila do WhatsApp'
                     when m.estado = 'enviada' then 'mandada'
                     when m.estado = 'sem_resposta' then 'mandada; sem resposta'
                     -- FASE 7d: (7d P8, o recado do P6; R6.3-5) a resposta ao M11 não é o acesso: o texto de _agenda_ver_clientes
                     when m.estado = 'respondida' and m.tipo = 'onde_fica' and a.efeito = 'anotou_acesso'
                       then 'mandada; respondeu: disse onde fica, e eu anotei e perguntei a você'
                     -- FASE 7d: fim
                     when m.estado = 'respondida'
                       then 'mandada; respondeu: ' || public._agenda_cliente_efeito_texto(a.efeito)
                     when m.recusa_motivo = 'segurada' then 'você segurou: não saiu'
                     else 'não saiu: ' || case
                       when m.recusa_motivo in ('modo', 'tipo_em_teste') then 'estava em teste'
                       when m.recusa_motivo = 'opt_out' then 'ele pediu para não receber mensagens'
                       when m.recusa_motivo = 'sem_telefone' then 'sem telefone no cadastro'
                       when m.recusa_motivo = 'sem_conversa' then 'ele não escreveu para a HBR no último ano'
                       when m.recusa_motivo in ('domingo', 'feriado', 'janela', 'vencida') then 'passou da hora'
                       when m.recusa_motivo in ('teto_dia', 'teto_semana', 'teto_total')
                         then 'ele já tinha recebido as mensagens que cabem'
                       -- o motivo do mesmo tipo recente vai pelo prefixo: o nome dele leva o número de horas, que a
                       -- varredura do agenda-sem-literal não deixa no corpo
                       when m.recusa_motivo = 'intervalo' or left(m.recusa_motivo, 10) = 'mesmo_tipo'
                         then 'ele tinha acabado de receber outra'
                       when m.recusa_motivo in ('status', 'data_mudou', 'material', 'desatualizada')
                         then 'o serviço mudou antes de sair'
                       when m.recusa_motivo = 'passou_da_data' then 'a data que ele ouviu já tinha passado'
                       else 'o texto não passou na conferência' end end,
                   'texto', m.texto,
                   'em_teste', m.modo = 'sombra',
                   'espera_voce', m.modo = 'ligado' and m.estado = 'aguardando_dono' and m.aprovacao in ('pedida', 'critica')) as j
            from public.agenda_cliente_mensagens m
            left join public.agenda_cliente_respostas a on a.id = m.resposta_id
           where m.service_order_id = p_os
           order by coalesce(m.enviada_em, m.enviar_em) desc, m.id desc
           limit c_lista) y;
  -- FASE 6: (P7) o estado de cada mensagem como o dono lê, sem "ele" ("não saiu: o cliente pediu para não receber
  -- mensagens", "não saiu: a data dita já tinha passado"), pelo ralo do texto ao dono
  select coalesce(jsonb_agg(case when t.e ->> 'estado_texto' is null then t.e
                                 else jsonb_set(t.e, '{estado_texto}',
                                                to_jsonb(public._agenda_cliente_sem_artigo(t.e ->> 'estado_texto', p_os))) end
                            order by t.o), '[]'::jsonb)
    into v_msgs
    from jsonb_array_elements(v_msgs) with ordinality t(e, o);
  -- FASE 6: fim

  -- o que espera o dono: a mesma conta do foco clientes (a mensagem que espera *manda cliente*, a decisão do aviso, a
  -- resposta que foi ao dono); a palavra só em ligado (em teste ela responde que nada sai ainda)
  -- CORREÇÃO FASE 5: (regressão B3) a conta do que espera o dono direto nas tabelas — as mesmas condições do bloco
  -- "Esperando você" do foco clientes (a mensagem que espera *manda cliente* ou que é decisão; a decisão sem mensagem; a
  -- resposta que foi ao dono, sem o "não respondeu"), e desligado = 0 como o foco —, sem montar o foco inteiro (e o d10 de
  -- cada cliente) a cada abertura do cartão
  v_esp := case when cf.modo_cliente = 'desligado' then 0 else
             (select count(*)::int from public.agenda_cliente_mensagens m
               where m.modo = 'ligado' and m.estado = 'aguardando_dono' and m.aprovacao in ('pedida', 'critica')
                 and m.service_order_id = p_os)
           + (select count(*)::int from public.agenda_perguntas q
               where q.modo = 'ligado' and q.estado = 'aberta' and (q.expira_em is null or q.expira_em > v_agora)
                 and q.service_order_id = p_os
                 and ((q.tipo = 'cliente_resposta' and q.chave not like 'cliente_resposta:sem_resposta:%')
                      or (q.tipo = 'cliente_aviso'
                          and not exists (select 1 from public.agenda_cliente_mensagens x where x.pergunta_id = q.id)))) end;
  if v_esp is null then
  -- CORREÇÃO FASE 5: fim
  v_esp := coalesce((public._agenda_ver_clientes(p_os, p_hoje) #>> '{dados,esperando}')::int, 0);
  -- CORREÇÃO FASE 5: o foco inteiro não roda mais (a conta acima nunca é nula)
  end if;
  -- CORREÇÃO FASE 5: fim
  select count(*)::int into v_ped from public.agenda_cliente_mensagens m
   where m.service_order_id = p_os and m.modo = 'ligado' and m.estado = 'aguardando_dono' and m.aprovacao = 'pedida';
  if cf.modo_cliente = 'ligado' and v_esp > 0 then
    v_esp_t := case when v_ped > 0
                    then format('%s esperando você: *manda cliente %s* manda; *segura cliente %s* segura.',
                                public._agenda_plural(v_ped, 'mensagem', 'mensagens'), so.nome, so.nome)
                    else '' end
               || case when v_esp > v_ped
                       then case when v_ped > 0 then ' ' else '' end
                            || 'Há decisão ou resposta dele esperando você: responda na conversa (*agenda clientes* mostra).'
                       else '' end;
  end if;

  -- FASE 6: (P7) o cartão sem "ele" (spec-fase6 §6.4): "O cliente confirmou qui 05/11." e "Há decisão ou resposta do cliente
  -- esperando você …"; o retorno de antes, logo abaixo, não roda mais
  return jsonb_build_object(
    'modo', cf.modo_cliente,
    'em_teste', cf.modo_cliente = 'sombra',
    'em_teste_texto', case when cf.modo_cliente = 'sombra'
                           then 'Em teste: nada sai ainda. Aqui fica o que eu teria mandado.' end,
    'nome', so.nome,
    'telefone_ok', v_tel, 'conversou', v_conv, 'opt_out', v_sem, 'contato_texto', v_contato,
    'servico', pl.servico_cliente,
    'prometido', v_prom,
    'confirmado_texto', case when so.client_confirmed_for is not null
                             then format('O cliente confirmou %s.',
                                         public._dia_curto((so.client_confirmed_for at time zone 'America/Sao_Paulo')::date)) end,
    'mensagens', v_msgs,
    'mensagens_mais', greatest(v_total - jsonb_array_length(v_msgs), 0),
    'esperando_voce', jsonb_build_object('n', v_esp, 'texto', public._agenda_cliente_sem_artigo(v_esp_t, p_os)));
  -- FASE 6: fim
  return jsonb_build_object(
    'modo', cf.modo_cliente,
    'em_teste', cf.modo_cliente = 'sombra',
    'em_teste_texto', case when cf.modo_cliente = 'sombra'
                           then 'Em teste: nada sai ainda. Aqui fica o que eu teria mandado.' end,
    'nome', so.nome,
    'telefone_ok', v_tel, 'conversou', v_conv, 'opt_out', v_sem, 'contato_texto', v_contato,
    'servico', pl.servico_cliente,
    'prometido', v_prom,
    'confirmado_texto', case when so.client_confirmed_for is not null
                             then format('Ele confirmou %s.',
                                         public._dia_curto((so.client_confirmed_for at time zone 'America/Sao_Paulo')::date)) end,
    'mensagens', v_msgs,
    'mensagens_mais', greatest(v_total - jsonb_array_length(v_msgs), 0),
    'esperando_voce', jsonb_build_object('n', v_esp, 'texto', v_esp_t));
end;
$function$;

-- agenda_rascunho_aplicar (de 20261107100550_agenda_fase7d_responder.sql)
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
    v_7d_qual := format('Qual decisão? %s. Diga a decisão e a opção (por exemplo, "na decisão 1, a opção 2"). Eu não escolho por você.',
                        (select string_agg((q ->> 'n') || ') ' || rtrim(q ->> 'texto', '.'), '; ' order by (q ->> 'n')::int)
                           from jsonb_array_elements(v_lista) q))
                 || coalesce(' Sem número, responda com as suas palavras: '
                             || (select string_agg(x, ' ') from jsonb_array_elements_text(v_7d_fora) x), '');
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
        case when cf.gestor_so_propor and v_7d_linha.tipo in ('situacao', 'estimativa', 'reavaliar', 'reestimar')
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

    -- FASE 7d: (7d P6b) a releitura da não crítica diz de qual pergunta é a opção: "Está certo" sozinho não diz nada, e o *grava* é o único portão. A crítica, como sempre foi.
    if not v_7d_linha.critica then
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

comment on function public.agenda_rascunho_aplicar(uuid, text, text, text[], text, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P4): vira RASCUNHO (nada muda) — publicar uma proposta aberta ("pode publicar", "publica só o Lenine e o Flávio": p_proposta "a última" ou o nº de agenda_propostas_abertas, p_os as OS ditas; obsoleta, inválida ou só com crítico = recusa) ou responder uma decisão crítica (p_decisao = o nº de agenda_decisoes_abertas ou o nome da OS; p_opcao = o nº ou o nome da OS que aceita atrasar). Sem opção dita: a pergunta com as opções volta como está — o banco não escolhe. Se a agenda mudou desde a pergunta e o efeito da opção também, a pergunta volta com os dias de agora. Chave aplicar:<proposta> / decisao:<pergunta>; releitura "Publico na agenda: …" / "Decisão: …". O *grava* chama agenda_aplicar (via dono) ou agenda_decidir (respondida_via = o canal). FASE 7d (P6b, NOVO-agenda-91): com a lista levando as não críticas, responder por número não pode virar a pergunta errada. Contam como esperando a lista e as perguntas com opções e sem número (nfe_vincular, previsao_fornecedor, a com opção já escolhida). Com mais de uma: sem a decisão dita, "Qual decisão?" (decisao_ambigua), também com uma só na lista; com a decisão e a opção em número, os 2 têm de estar nas palavras do dono (_agenda_disse_os_numeros); pelo nome e a opção em número, o nome e o número no trecho. A opção pelo nome da OS não passa por isso. Só pergunta sem número: a recusa diz que é por palavras (sem_numero). A não crítica cujo modo não vale agora é recusada aqui (em_teste), não no *grava*; a releitura dela diz de qual pergunta é a opção. A crítica, como antes. FASE 7d (P8; os evals S24 e K57): a régua das palavras é para o número solto: quando as palavras do dono dizem a pergunta e a opção (_agenda_disse_em_palavras), o número que o modelo achou pela lista vale.';

-- ── 6. As portas ──────────────────────────────────────────────────────────────────────────────────
-- Revoke de public E de anon, e prova (o L0 do teste). _agenda_local_bloco é invoker e só definer a chama; as outras 2 são definer com a porta dentro (R6.3-12).
revoke all on function public._agenda_local_bloco(uuid, date) from public, anon, authenticated;
grant execute on function public._agenda_local_bloco(uuid, date) to service_role;
revoke all on function public._agenda_ver_locais(date, uuid) from public, anon;
grant execute on function public._agenda_ver_locais(date, uuid) to authenticated, service_role;
revoke all on function public._agenda_saude_local(date, timestamptz) from public, anon;
grant execute on function public._agenda_saude_local(date, timestamptz) to authenticated, service_role;
revoke all on function public._agenda_disse_em_palavras(text, text, text, text[]) from public, anon, authenticated, service_role;
