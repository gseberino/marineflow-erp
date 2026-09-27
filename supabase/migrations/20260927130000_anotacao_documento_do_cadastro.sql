-- Anotação com o nome de um e o CPF/CNPJ de outro não nasce (revisão de 27/09/2026).
--
-- Na identidade da anotação o documento DITO toma o lugar do documento do cadastro
-- (_quem_da_anotacao: coalesce(an.documento, f.cnpj_cpf, …)). Então "o Pix de R$ 100 é do Roberto"
-- dito com o CNPJ de uma loja casava com o Pix da loja e punha o Roberto nele — nome e documento
-- diferentes, o que a regra P1 do dono proíbe ("o sistema nunca pode lançar transação com nomes
-- diferentes"). A ferramenta do assistente já pergunta antes; esta trava vale para qualquer
-- caminho (assistente, tela, função): documento dito que contradiz o do cadastro de quem foi dito
-- (CPF diferente, ou CNPJ de outra raiz — filial é a mesma empresa) é recusado com a pergunta.
-- Cadastro sem documento não tem o que contradizer: passa, e a confirmação do assistente avisa.
--
-- Hoje não há nenhuma anotação no banco (conferido em 27/09/2026): nada a corrigir para trás.

create or replace function public._anotacao_documento_confere()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nome text;
  v_doc text;
begin
  if new.documento is null then
    return new;
  end if;
  select x.nome, x.doc into v_nome, v_doc
    from (
      select f.name as nome, f.cnpj_cpf as doc from public.suppliers f where f.id = new.fornecedor_id
      union all
      select pe.name, pe.document from public.payees pe where pe.id = new.favorecido_id
      union all
      select c.name, c.cpf_cnpj from public.clients c where c.id = new.cliente_id
    ) x
   where public._documento_contradiz(new.documento, x.doc)
   limit 1;
  -- Outra pessoa pagando (ou recebendo) em nome de alguém é caso de tela: a anotação só com o
  -- nome nunca casaria com a linha, que chega com o nome de quem pagou.
  if v_nome is not null then
    raise exception 'O documento % não é o de % (no cadastro: %): o sistema não junta nome e documento diferentes. Se é outra pessoa pagando ou recebendo em nome de %, classifique pela tela do Extrato quando a transação chegar; se o nome estava errado, anote só com o documento.',
      new.documento, v_nome, v_doc, v_nome;
  end if;
  return new;
end;
$$;

drop trigger if exists anotacao_documento_confere on public.anotacoes_do_extrato;
create trigger anotacao_documento_confere
  before insert or update of documento, fornecedor_id, favorecido_id, cliente_id on public.anotacoes_do_extrato
  for each row execute function public._anotacao_documento_confere();

-- Função de gatilho: ninguém chama direto.
revoke all on function public._anotacao_documento_confere() from public, anon, authenticated;

-- ───────────────────────────────────────────────────────────────────────────────────────────
-- Conferências: se algo acima não ficou como deveria, nada é gravado.
-- ───────────────────────────────────────────────────────────────────────────────────────────
do $$
begin
  if has_function_privilege('anon', 'public._anotacao_documento_confere()', 'EXECUTE')
     or has_function_privilege('authenticated', 'public._anotacao_documento_confere()', 'EXECUTE') then
    raise exception 'a função da trava ficou executável por anon/authenticated';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'anotacao_documento_confere'
                    and tgrelid = 'public.anotacoes_do_extrato'::regclass and not tgisinternal) then
    raise exception 'a trava não foi criada';
  end if;
end $$;
