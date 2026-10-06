-- Prova: cadastrar_freelancer cria favorecido + diária + conta corrente + categoria (+ regra por
-- CPF), simula sem gravar, reaproveita só cadastro de MESMO nome/CPF, recusa duplicado, chave
-- ambígua, início no futuro e quem não é admin/financeiro
-- (migration 20261001183918_cadastrar_freelancer).
--
-- ═══ COMO RODAR ═══
--
--   supabase db query --linked -f supabase/tests/cadastrar_freelancer.sql --output json
--
-- Seguro em produção: a transação inteira termina em ROLLBACK. Os nomes e CPFs de teste levam um
-- sufixo aleatório e não existem no cadastro.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_dono uuid;
  v_tec uuid;
  v_sufixo text := lpad((floor(random() * 1000000))::int::text, 6, '0');
  v_nome text;
  v_cpf text;
  v_hoje date := public._hoje_brt();
  v_antes integer;
  v_depois integer;
  r jsonb;
  c jsonb;
  v_fav record;
  v_perfil record;
  v_txt text;
  v_id uuid;
begin
  select id into v_dono from public.app_users where role = 'admin' and active order by created_at limit 1;
  if v_dono is null then
    insert into _resultado values ('setup', false, 'sem admin ativo');
    return;
  end if;
  v_nome := 'Freelancer Teste ' || v_sufixo;
  v_cpf := '990' || v_sufixo || '01';

  -- T1. Simular não grava e diz o que faria.
  select count(*) into v_antes from public.payees;
  r := public.cadastrar_freelancer(v_nome, 150, v_hoje - 2, 'Teste' || v_sufixo || '@Exemplo.com', null, null, null, null, true, null);
  select count(*) into v_depois from public.payees;
  insert into _resultado values ('T01 simular nao grava',
    v_antes = v_depois and r->>'acao' = 'criado' and (r->>'simulacao')::boolean and r->>'regra' = 'sem_cpf'
      and r->>'tipo_chave' = 'email',
    r::text);

  -- T2. Cria: chave e-mail deduzida e em minúsculas, categoria, conta corrente desde o 1º dia, diária.
  r := public.cadastrar_freelancer(v_nome, 150, v_hoje - 2, 'Teste' || v_sufixo || '@Exemplo.com', null, null, null, null, false, v_dono);
  select * into v_fav from public.payees where id = (r->>'favorecido_id')::uuid;
  select * into v_perfil from public.work_profiles where payee_id = v_fav.id;
  insert into _resultado values ('T02 cria completo',
    r->>'acao' = 'criado' and v_fav.kind = 'prestador' and v_fav.active
      and v_fav.pix_key = lower('teste' || v_sufixo || '@exemplo.com') and v_fav.pix_key_type = 'email'
      and v_fav.default_category = 'Diárias de freelancers'
      and v_fav.conta_corrente_desde = v_hoje - 2 and v_fav.saldo_anterior = 0
      and v_perfil.modo_pagamento = 'diaria' and v_perfil.tipo_vinculo = 'diarista'
      and v_perfil.valor_diaria = 150 and v_perfil.meia_diaria_ate_horas = 4
      and v_perfil.vigencia_inicio = v_hoje - 2 and v_perfil.vigencia_fim is null
      and r->>'message' like '%Sem CPF%',
    r->>'message');

  -- T3. O dia entra e o saldo fecha: um dia com o valor do cadastro e outro com valor dito.
  perform public.registrar_diaria(v_fav.id, v_hoje - 2, 'inteiro', null, null, null, null, null, 'agente', v_dono);
  perform public.registrar_diaria(v_fav.id, v_hoje - 1, 'inteiro', null, null, null, null, 130, 'agente', v_dono);
  c := public.conta_corrente_freelancer(v_fav.id, null, null, v_dono);
  insert into _resultado values ('T03 dias e saldo',
    (c->>'dias')::numeric = 2 and (c->>'trabalhado')::numeric = 280 and (c->>'saldo_final')::numeric = 280,
    format('dias=%s trabalhado=%s saldo=%s', c->>'dias', c->>'trabalhado', c->>'saldo_final'));

  -- T4. Duplicado: o mesmo nome (outra caixa/acento/espaço) já tem diária — recusa.
  begin
    perform public.cadastrar_freelancer(upper('  freelancer   teste ' || v_sufixo), 160, null, null, null, null, null, null, false, v_dono);
    insert into _resultado values ('T04 recusa duplicado', false, 'cadastrou de novo');
  exception when others then
    insert into _resultado values ('T04 recusa duplicado', sqlerrm like '%já tem diária%', sqlerrm);
  end;

  -- T5. Com CPF pela chave Pix: o CPF vira documento e a regra por CPF nasce (lança sozinha).
  r := public.cadastrar_freelancer('Outro Teste ' || v_sufixo, 140, null, v_cpf, 'cpf', null, '(47) 99999-0000', null, false, v_dono);
  select * into v_fav from public.payees where id = (r->>'favorecido_id')::uuid;
  insert into _resultado values ('T05 cpf e regra',
    r->>'regra' = 'criada' and v_fav.document = v_cpf and v_fav.pix_key = v_cpf
      and v_fav.conta_corrente_desde = v_hoje and v_fav.phone = '5547999990000'
      and exists (select 1 from public.finance_rules where match_type = 'document' and match_value = v_cpf
                    and direction = 'debit' and autonomy = 'apply' and status = 'active'
                    and set_category = 'Diárias de freelancers' and set_dre_group = 'custo_direto'),
    r->>'message');

  -- T6. Favorecido que já existe SEM diária (mesmo nome, com acento diferente): ganha a diária,
  --     não nasce um segundo cadastro.
  insert into public.payees (name, kind) values ('José Existente ' || v_sufixo, 'prestador') returning id into v_id;
  select count(*) into v_antes from public.payees;
  r := public.cadastrar_freelancer('jose existente ' || v_sufixo, 120, null, 'jose' || v_sufixo || '@exemplo.com', null, null, null, null, false, v_dono);
  select count(*) into v_depois from public.payees;
  insert into _resultado values ('T06 reaproveita mesmo nome',
    r->>'acao' = 'diaria_no_cadastro_existente' and (r->>'favorecido_id')::uuid = v_id and v_antes = v_depois
      and r->>'nome' = 'José Existente ' || v_sufixo
      and exists (select 1 from public.work_profiles where payee_id = v_id and valor_diaria = 120),
    r->>'message');

  -- T7. Nome igual, CPF diferente: não é a mesma pessoa — recusa em vez de misturar.
  begin
    perform public.cadastrar_freelancer('Outro Teste ' || v_sufixo, 140, null, null, null, '991' || v_sufixo || '02', null, null, false, v_dono);
    insert into _resultado values ('T07 nome igual cpf outro', false, 'misturou os dois');
  exception when others then
    insert into _resultado values ('T07 nome igual cpf outro', sqlerrm like '%outro CPF%', sqlerrm);
  end;

  -- T8. Chave de 11 dígitos sem tipo: CPF ou celular? Pergunta.
  begin
    perform public.cadastrar_freelancer('Terceiro Teste ' || v_sufixo, 140, null, '47999990000', null, null, null, null, true, null);
    insert into _resultado values ('T08 chave ambigua', false, 'deduziu sozinho');
  exception when others then
    insert into _resultado values ('T08 chave ambigua', sqlerrm like '%CPF ou telefone%', sqlerrm);
  end;

  -- T9. Início no futuro e diária zero: recusa.
  begin
    perform public.cadastrar_freelancer('Quarto Teste ' || v_sufixo, 140, v_hoje + 1, null, null, null, null, null, true, null);
    insert into _resultado values ('T09 futuro e valor', false, 'aceitou o futuro');
  exception when others then
    begin
      perform public.cadastrar_freelancer('Quarto Teste ' || v_sufixo, 0, null, null, null, null, null, null, true, null);
      insert into _resultado values ('T09 futuro e valor', false, 'aceitou diária zero');
    exception when others then
      insert into _resultado values ('T09 futuro e valor', sqlerrm like '%valor da diária%', sqlerrm);
    end;
  end;

  -- T10. Gravar sem autor (só simular pode): recusa.
  begin
    perform public.cadastrar_freelancer('Quinto Teste ' || v_sufixo, 140, null, null, null, null, null, null, false, null);
    insert into _resultado values ('T10 sem autor', false, 'gravou sem autor');
  exception when others then
    insert into _resultado values ('T10 sem autor', sqlerrm like '%quem está cadastrando%', sqlerrm);
  end;

  -- T11. Autor que não é admin/financeiro: 42501.
  select id into v_tec from public.app_users where role not in ('admin', 'financial') and active limit 1;
  if v_tec is null then
    insert into _resultado values ('T11 cargo', true, 'sem usuário de outro cargo para testar');
  else
    begin
      perform public.cadastrar_freelancer('Sexto Teste ' || v_sufixo, 140, null, null, null, null, null, null, true, v_tec);
      insert into _resultado values ('T11 cargo', false, 'outro cargo simulou');
    exception when insufficient_privilege then
      insert into _resultado values ('T11 cargo', true, sqlerrm);
    end;
  end if;

  -- T12. anon não executa.
  insert into _resultado values ('T12 anon',
    not has_function_privilege('anon', 'public.cadastrar_freelancer(text, numeric, date, text, text, text, text, text, boolean, uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.cadastrar_freelancer(text, numeric, date, text, text, text, text, text, boolean, uuid)', 'execute'),
    'sem execução para anon');
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
