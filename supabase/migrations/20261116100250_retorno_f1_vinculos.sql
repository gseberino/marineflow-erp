-- Retorno rápido ao cliente, F1 (sobe no pacote F0b-1 de ter 10/11/2026): o lote de vínculos (F0b-10).
--
-- Por quê: o plano põe o "sim" do dono no lote dos contatos que já casam com cliente como condição de
-- ligar a identificação nova em 11/11 (G.0). Medido em 01/11 (pela chave, ainda sem o DDD e a equipe do
-- quem_escreve): 266 leads pendentes e 1 vinculado; 23 pendentes casam com UM cliente ativo, 1 com dois e
-- 1 com a MP (o plano contou 26). link_contact_to_entity não é SQL: é ferramenta
-- do assistente (_shared/ai/tools/contacts.ts, congelado), que regrava client_id em TODAS as mensagens do
-- número, inclusive por cima de vínculo que já existe. Aqui o vínculo é pergunta (regra 2 do dono): a lista
-- vai ao cartão rr-vinculos do Diário, e só o que o dono aprovar é vinculado, uma chamada por letra.
--
-- 1. retorno_vinculos_candidatos(): os whatsapp_leads pendentes, sem linked_client_id, com chave de 8
--    dígitos e que não são grupo nem lista de transmissão, com o papel de quem_escreve (F0b). O NOME NUNCA
--    ENTRA: nem o do lead nem o do cliente identificam; o nome do cliente só aparece no cartão e ordena a
--    lista. O tipo:
--    - unico: 1 cliente ativo, do mesmo DDD, fora de retorno_config.clientes_parceiros. Só ele leva letra;
--    - compartilhado: o número de 2 ou mais clientes, ou de DDD diferente (quem_escreve: cliente_ambiguo).
--      Sem letra: o dono decide na tela;
--    - parceiro: o cliente está em clientes_parceiros (o comercial da MP identificado como a cliente MP,
--      sem vínculo). Sem letra: a pessoa de parceiro é da F4.
--    Equipe, fornecedor, número novo, "Cliente Final" e cliente inativo não entram: quem_escreve já os
--    separa. As letras vão em ordem de nome (sem acento e sem caixa) e pulam E, I, N, O e S (regra 3 do
--    plano): A … Z (21 letras), depois AA, AB, … (_retorno_letra_do_lote). A lista é recalculada a cada
--    chamada: a letra vale para o cartão em que foi mostrada, não para sempre.
--
-- 2. retorno_vincular_lead(lead, cliente): vincula UM lead aprovado, numa transação. Só executa se o lead
--    está pendente, sem vínculo e não é grupo/transmissão (senão "estado"); se quem_escreve dá o papel
--    cliente com ESTE cliente ("compartilhado" no ambíguo, "nao_casa" no resto); e se o cliente está fora
--    de clientes_parceiros ("parceiro"), ativo e fora do genérico. Efeitos:
--    - o lead vira linked, com o cliente;
--    - as mensagens do mesmo telefone SEM client_id ganham o cliente; a que já tem outro client_id fica
--      como está (nunca sobrescreve). "Mesmo telefone" = a chave de 8 dígitos E o mesmo DDD
--      (_mesmo_telefone, F0a): a mensagem de outro DDD com os mesmos 8 dígitos é outra pessoa (para
--      quem_escreve, ambígua) e não ganha o vínculo;
--    - uma linha em audit_log (changed_by 'retorno'), com os ids das mensagens vinculadas em
--      previous_value.mensagens_sem_cliente: é o que permite desfazer exatamente.
--    O lead fica travado (for update) até o fim da transação: duas chamadas juntas nunca vinculam duas vezes.
--
-- Sem a linha de retorno_config as duas funções levantam 55000 (falha fecha): sem a lista de parceiros, o
-- comercial da MP sairia como "unico". Nenhuma das duas manda mensagem nem abre caso.
--
-- Execução (fora desta migration; escrita em produção com OK nomeado): depois do deploy de 10/11 a sessão
-- coordenadora gera a lista (select * from retorno_vinculos_candidatos()), leva ao cartão rr-vinculos e,
-- com o "sim" do dono (ou "sim sem C"), chama retorno_vincular_lead(lead, cliente) para cada letra
-- aprovada, numa transação com commit.
--
-- Sem dado: esta migration não muda nenhuma linha. Reverter: drop function
-- public.retorno_vincular_lead(uuid, uuid), public.retorno_vinculos_candidatos(),
-- public._retorno_letra_do_lote(integer). Desfazer um vínculo já feito, pela linha do audit_log
-- (table_name 'whatsapp_leads', changed_by 'retorno', record_id = o lead): update whatsapp_messages set
-- client_id = null where id in (previous_value.mensagens_sem_cliente) and client_id = new_value.client_id;
-- update whatsapp_leads set status = 'pending', linked_client_id = null where id = record_id.

-- A n-ésima letra do lote (1 = A), sem E, I, N, O e S: base 21 bijetiva (… Z, AA, AB, … ZZ, AAA).
-- Nulo para n nulo ou menor que 1.
create or replace function public._retorno_letra_do_lote(p_n integer)
returns text
language sql
immutable
set search_path = public
as $$
  with recursive r(resto, letra) as (
    select p_n, ''::text
     where p_n >= 1
    union all
    select (r.resto - 1) / 21, substr('ABCDFGHJKLMPQRTUVWXYZ', (r.resto - 1) % 21 + 1, 1) || r.letra
      from r
     where r.resto > 0
  )
  select r.letra from r where r.resto = 0;
$$;

comment on function public._retorno_letra_do_lote(integer) is
  'Retorno F0b-10: a n-ésima letra do lote de vínculos (1 = A), pulando E, I, N, O e S: A … Z, AA, AB, …; nulo fora de n >= 1.';

revoke all on function public._retorno_letra_do_lote(integer) from public, anon, authenticated;

create or replace function public.retorno_vinculos_candidatos()
returns table (letra text, lead_id uuid, phone text, tipo text, clientes jsonb)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_cfg public.retorno_config := public._retorno_cfg();
begin
  -- Sem a linha não há a lista de parceiros: o comercial da MP sairia "unico". Falha fecha, em voz alta.
  if v_cfg.id is null then
    raise exception using
      errcode = '55000',
      message = 'Lote de vínculos: retorno_config sem a linha de configuração (sem a lista de parceiros, nada é listado).';
  end if;

  -- As colunas de saída (letra, lead_id, phone, tipo, clientes) são variáveis do plpgsql: toda coluna
  -- abaixo vai qualificada, e os nomes internos são outros.
  -- quem_escreve só dá cliente ou cliente_ambiguo quando há cliente ativo, fora do genérico, com a mesma
  -- chave: as chaves de cliente saem uma vez só, e quem_escreve roda só nos leads que caem nelas (medido em
  -- 01/11: ~20 ms por chamada, 266 pendentes). "materialized": uma chamada por lead, e não uma por
  -- referência a q.
  return query
  with chaves_de_clientes as materialized (
    select distinct k.chave
      from public.clients c
      cross join lateral (values (public._agenda_chave_telefone(c.whatsapp)), (public._agenda_chave_telefone(c.phone))) as k(chave)
     where c.active and not c.generico and k.chave is not null
  ),
  pendentes as materialized (
    select l.id as lead, l.phone_normalized as fone, public.quem_escreve(l.phone_normalized) as q
      from public.whatsapp_leads l
     where l.status = 'pending'
       and l.linked_client_id is null
       and not coalesce(l.is_broadcast, false)
       and l.phone_normalized !~ '@'
       and public._agenda_chave_telefone(l.phone_normalized) is not null
       and public._agenda_chave_telefone(l.phone_normalized) in (select ch.chave from chaves_de_clientes ch)
  ),
  tipados as (
    select p.lead, p.fone, p.q,
           case
             when p.q ->> 'papel' = 'cliente_ambiguo' then 'compartilhado'
             when p.q ->> 'papel' = 'cliente' and (p.q ->> 'cliente_id')::uuid = any (v_cfg.clientes_parceiros) then 'parceiro'
             when p.q ->> 'papel' = 'cliente' then 'unico'
           end as classe
      from pendentes p
  ),
  nomes as (          -- cada cliente de cada lead, com o nome curto que vai ao cartão
    select t.lead, c.id as cliente,
           public._agenda_nome_curto(coalesce(nullif(btrim(c.display_name), ''), c.name)) as curto,
           public._texto_simples(coalesce(nullif(btrim(c.display_name), ''), c.name)) as completo
      from tipados t
      cross join lateral jsonb_array_elements_text(t.q -> 'clientes') as e(id_texto)
      join public.clients c on c.id = e.id_texto::uuid
     where t.classe is not null
  ),
  listas as (
    select nm.lead,
           jsonb_agg(jsonb_build_object('id', nm.cliente, 'nome', nm.curto)
                     order by public._texto_simples(nm.curto) collate "C", nm.completo collate "C", nm.cliente) as lista,
           min(public._texto_simples(nm.curto) collate "C") as ordem_curto,
           min(nm.completo collate "C") as ordem_nome
      from nomes nm
     group by nm.lead
  ),
  ordenados as (
    select t.lead, t.fone, t.classe, coalesce(li.lista, '[]'::jsonb) as lista, li.ordem_curto, li.ordem_nome,
           case when t.classe = 'unico' then
             row_number() over (partition by t.classe = 'unico'
                                order by li.ordem_curto collate "C", li.ordem_nome collate "C", t.fone collate "C", t.lead)
           end as posicao
      from tipados t
      left join listas li on li.lead = t.lead
     where t.classe is not null
  )
  select public._retorno_letra_do_lote(o.posicao::integer), o.lead, o.fone, o.classe, o.lista
    from ordenados o
   order by case o.classe when 'unico' then 0 when 'compartilhado' then 1 else 2 end,
            o.posicao, o.ordem_curto collate "C", o.ordem_nome collate "C", o.fone collate "C", o.lead;
end;
$$;

comment on function public.retorno_vinculos_candidatos() is
  'Retorno F0b-10: os leads pendentes que casam com cliente pela chave de 8 dígitos (quem_escreve), nunca pelo nome: unico (com letra, sem E/I/N/O/S, em ordem de nome), compartilhado e parceiro (sem letra). clientes = [{id, nome curto}]. Sem retorno_config: 55000.';

revoke all on function public.retorno_vinculos_candidatos() from public, anon, authenticated;
grant execute on function public.retorno_vinculos_candidatos() to service_role;

create or replace function public.retorno_vincular_lead(p_lead uuid, p_client uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_cfg public.retorno_config := public._retorno_cfg();
  v_lead public.whatsapp_leads;
  v_q jsonb;
  v_cliente uuid;
  v_n integer;
  v_ids jsonb;
begin
  if v_cfg.id is null then
    raise exception using
      errcode = '55000',
      message = 'Lote de vínculos: retorno_config sem a linha de configuração (sem a lista de parceiros, nada é vinculado).';
  end if;

  -- O lead travado até o fim da transação: duas chamadas juntas nunca vinculam duas vezes.
  select l.* into v_lead from public.whatsapp_leads l where l.id = p_lead for update;
  if not found or v_lead.status is distinct from 'pending' or v_lead.linked_client_id is not null
     or coalesce(v_lead.is_broadcast, false) or v_lead.phone_normalized ~ '@' then
    return jsonb_build_object('ok', false, 'motivo', 'estado');
  end if;

  -- Quem é o número, pela chave de 8 dígitos e o DDD (o nome nunca entra).
  v_q := public.quem_escreve(v_lead.phone_normalized);
  if v_q ->> 'papel' = 'cliente_ambiguo' then
    return jsonb_build_object('ok', false, 'motivo', 'compartilhado');
  end if;
  if v_q ->> 'papel' = 'cliente' then
    v_cliente := (v_q ->> 'cliente_id')::uuid;
  end if;
  -- O parceiro (o do número ou o pedido) fica para a F4.
  if v_cliente = any (v_cfg.clientes_parceiros) or p_client = any (v_cfg.clientes_parceiros) then
    return jsonb_build_object('ok', false, 'motivo', 'parceiro');
  end if;
  -- Só o cliente da chave, ativo e fora do "Cliente Final" (quem_escreve já filtra; conferido de novo aqui).
  if v_cliente is null or p_client is distinct from v_cliente
     or not exists (select 1 from public.clients c where c.id = p_client and c.active and not c.generico) then
    return jsonb_build_object('ok', false, 'motivo', 'nao_casa');
  end if;

  update public.whatsapp_leads l
     set status = 'linked', linked_client_id = p_client
   where l.id = p_lead;

  -- Só as mensagens sem client_id: um vínculo que já existe nunca é sobrescrito. Mesmo telefone = a chave
  -- e o mesmo DDD (outro DDD com os mesmos 8 dígitos é outra pessoa).
  with vinculadas as (
    update public.whatsapp_messages m
       set client_id = p_client
     where public._agenda_chave_telefone(m.phone_normalized) = public._agenda_chave_telefone(v_lead.phone_normalized)
       and public._mesmo_telefone(m.phone_normalized, v_lead.phone_normalized)
       and m.client_id is null
    returning m.id
  )
  select count(*)::integer, coalesce(jsonb_agg(vi.id order by vi.id), '[]'::jsonb)
    into v_n, v_ids
    from vinculadas vi;

  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
  values ('whatsapp_leads', p_lead, 'update', 'retorno',
          jsonb_build_object('status', v_lead.status, 'linked_client_id', v_lead.linked_client_id,
                             'mensagens_sem_cliente', v_ids),
          jsonb_build_object('client_id', p_client, 'mensagens', v_n),
          'Lote de vínculos (sim do dono)');

  return jsonb_build_object('ok', true, 'mensagens', v_n);
end;
$$;

comment on function public.retorno_vincular_lead(uuid, uuid) is
  'Retorno F0b-10: vincula um lead aprovado no lote ao cliente da chave (só papel cliente, fora dos parceiros, ativo e não genérico): lead linked, mensagens do mesmo telefone SEM client_id (nunca sobrescreve) e audit_log. {"ok": true, "mensagens": n} ou {"ok": false, "motivo": estado|nao_casa|compartilhado|parceiro}. Sem retorno_config: 55000.';

revoke all on function public.retorno_vincular_lead(uuid, uuid) from public, anon, authenticated;
grant execute on function public.retorno_vincular_lead(uuid, uuid) to service_role;
