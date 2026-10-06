-- Anotação de transação só com o NOME (sem cadastro) — 06/10/2026.
--
-- Pedido do dono: "registrar o Pix de 493 para a Eliane Aparecida Uberti como alimentação, sem
-- precisar cadastrar ninguém — só a categoria". A anotação já gravava o nome dito (anotacoes_do_extrato.nome),
-- mas a identidade dela (_quem_da_anotacao) só olhava nomes de CADASTRO: anotação sem cadastro valia só
-- para transação SEM nome no extrato, e o Pix da Eliane (que chega com o nome dela) nunca casaria.
--
-- Agora o nome dito entra na identidade. Vale a regra do dono de 26/09: só nome IGUAL (ou cortado pelo
-- banco, a partir de 25 letras) identifica — nunca nome parecido (_identidade_serve, inalterada).
-- E duas anotações só com nome, de pessoas DIFERENTES e mesmo valor, deixam de ser "a mesma dita de novo".
--
-- Só troca duas funções: nenhum dado é escrito. Em 06/10 havia 1 anotação no histórico, já aplicada.

create or replace function public._quem_da_anotacao(p_anotacao uuid)
returns table(q_fornecedor uuid, q_favorecido uuid, q_cliente uuid, q_doc text, q_nomes text[], q_diz_quem boolean)
language sql
stable
security definer
set search_path to 'public'
as $function$
  select an.fornecedor_id, an.favorecido_id, cli.id,
         public._doc_normalizado(coalesce(an.documento, f.cnpj_cpf, pe.document, cli.cpf_cnpj)),
         array_remove(array[public._nome_comparavel(f.name), public._nome_comparavel(f.trade_name),
                            public._nome_comparavel(pe.name), public._nome_comparavel(cli.name),
                            -- o nome DITO, quando não há cadastro (06/10/2026)
                            case when an.fornecedor_id is null and an.favorecido_id is null and cli.id is null
                                 then public._nome_comparavel(an.nome) end], ''),
         (an.fornecedor_id is not null or an.favorecido_id is not null or cli.id is not null
          or nullif(btrim(coalesce(an.nome, '')), '') is not null)
    from public.anotacoes_do_extrato an
    left join public.suppliers f on f.id = an.fornecedor_id
    left join public.payees pe on pe.id = an.favorecido_id
    left join public.service_orders so on so.id = an.os_id and an.sentido = 'credit' and an.cliente_id is null
    left join public.clients cli on cli.id = coalesce(an.cliente_id, so.client_id)
   where an.id = p_anotacao;
$function$;

-- "A mesma anotação dita de novo" (a nova substitui a anterior): com cadastro, pelos cadastros; só com
-- nome, pelo NOME — senão a anotação da Eliane trocaria a da padaria do mesmo valor e dias.
create or replace function public._anotacoes_repetidas_esperando(p_anotacao uuid)
returns setof uuid
language sql
stable
security definer
set search_path to 'public'
as $function$
  select b.id
    from public.anotacoes_do_extrato a
    cross join lateral public._quem_da_anotacao(a.id) qa
    join public.anotacoes_do_extrato b
      on b.id <> a.id and b.status = 'aguardando'
     and b.sentido = a.sentido and abs(b.valor - a.valor) < 0.01
     and b.data_prevista - case when b.data_exata then 1 else 3 end <= a.data_prevista + case when a.data_exata then 1 else 7 end
     and a.data_prevista - case when a.data_exata then 1 else 3 end <= b.data_prevista + case when b.data_exata then 1 else 7 end
    cross join lateral public._quem_da_anotacao(b.id) qb
   where a.id = p_anotacao
     and qa.q_diz_quem and qb.q_diz_quem
     and not public._documento_contradiz(qa.q_doc, qb.q_doc)
     and (qa.q_fornecedor is not distinct from qb.q_fornecedor or public._mesma_empresa(qa.q_fornecedor, qb.q_fornecedor))
     and qa.q_favorecido is not distinct from qb.q_favorecido
     and qa.q_cliente is not distinct from qb.q_cliente
     -- Sem cadastro dos dois lados: só é a mesma se o nome dito for o mesmo.
     and (qa.q_fornecedor is not null or qa.q_favorecido is not null or qa.q_cliente is not null
          or qa.q_nomes && qb.q_nomes);
$function$;

revoke all on function public._quem_da_anotacao(uuid) from public, anon, authenticated;
grant execute on function public._quem_da_anotacao(uuid) to service_role;
revoke all on function public._anotacoes_repetidas_esperando(uuid) from public, anon, authenticated;
grant execute on function public._anotacoes_repetidas_esperando(uuid) to service_role;

do $$
begin
  if has_function_privilege('anon', 'public._quem_da_anotacao(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public._quem_da_anotacao(uuid)', 'execute')
     or has_function_privilege('anon', 'public._anotacoes_repetidas_esperando(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public._anotacoes_repetidas_esperando(uuid)', 'execute') then
    raise exception 'função da anotação exposta além do previsto';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261006150000', 'anotacao_por_nome')
on conflict do nothing;
