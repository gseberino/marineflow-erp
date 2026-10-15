-- Secretário, Passo 4 ("uma voz só"), P4.4 (15/10/2026): a janela da manhã. Das 07:30 às 09:30 o dono
-- lê a manhã e responde as letras dela; nenhuma outra pergunta sai nesse intervalo. O vigia dos
-- comprovantes (pergunta "para quê?" de um CMP da fila e a do extrato, F3) passa a perguntar só a partir
-- das 09:30, e não mais das 08:00. Nada é descartado: o CMP continua na fila e o vigia (cron a cada 2 min)
-- pergunta na primeira rodada depois das 09:30.
-- Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-uma-voz.md (§5)
--
-- Medido (02–15/10): 2 perguntas do vigia às 08:00 (12 e 13/10), as duas em cima da manhã das 07:30.
--
-- Só muda UMA linha de _comprovante_vigia_pode: `v_agora::time < time '08:00'` → `< time '09:30'`.
-- _comprovante_banco_pode (F3), _comprovante_proxima, comprovantes_vigia_conversa e as guardas do cron
-- (20261011204000, 20261011304000) chamam esta função: a regra vale para todas de uma vez.
--
-- O corpo de antes foi conferido em produção em 15/10/2026: md5 do prosrc normalizado (A-Z em minúscula,
-- sem espaços) = e1562d0d5673d05a8c5f8a053e5f975e, igual ao de 20261011202000_comprovantes_conversa_rpcs.sql
-- (a última definição nas migrations). A migration confere de novo antes de recriar e para se o corpo for
-- outro (alguém mudou por fora). Sem dado gravado. Idempotente. Não depende de chave: vale ao publicar.

do $$
declare
  v_md5 text;
begin
  select md5(regexp_replace(translate(p.prosrc, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), '\s+', '', 'g'))
    into v_md5
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = '_comprovante_vigia_pode';
  if v_md5 is null then
    raise exception '_comprovante_vigia_pode não existe: aplique antes as migrations dos comprovantes (20261011202000)';
  end if;
  -- o de 20261011202000 (produção em 15/10/2026) ou já este
  if v_md5 not in ('e1562d0d5673d05a8c5f8a053e5f975e', '18cc79aa84225c9f1df6b7f72311a879') then
    raise exception '_comprovante_vigia_pode não é o esperado (md5 %): confira o corpo em produção antes de recriar', v_md5;
  end if;
end $$;

-- O vigia pode perguntar a este telefone agora? null = pode; senão o motivo. Só leitura (a guarda
-- do cron usa a mesma regra): conversa ligada e do dono, sem pausa, de 09:30 a 20:00 de São Paulo
-- de segunda a sábado (das 07:30 às 09:30 é a janela da manhã: só a manhã pergunta), sem texto/áudio
-- do dono nos últimos 2 min, sem pergunta aberta nem pendência viva, e um CMP da fila dentro do
-- espaçamento (4 h), do limite (3 perguntas automáticas) e fora do adiamento do "pular"/"deixar para
-- depois" (adiado_ate).
create or replace function public._comprovante_vigia_pode(p_phone text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_agora timestamp := now() at time zone 'America/Sao_Paulo';
  v_fila record;
begin
  if not public._comprovante_conversa_ligada()
     or p_phone is distinct from (select d.phone from public._comprovante_dono() d) then
    return 'desligada';
  end if;
  select f.pausada_ate, f.ultima_pergunta_fechada_em into v_fila
    from public.comprovantes_fila_do_telefone f where f.phone_normalized = p_phone;
  if v_fila.pausada_ate > now() then
    return 'pausada';
  end if;
  if extract(isodow from v_agora) = 7 or v_agora::time < time '09:30' or v_agora::time >= time '20:00' then
    return 'fora_do_horario';
  end if;
  if public._comprovante_conversa_em_andamento(p_phone) then
    return 'conversa_em_andamento';
  end if;
  if exists (select 1 from public.whatsapp_perguntas w
              where w.phone_normalized = p_phone and w.status = 'aberta' and w.expira_em > now()
                and (w.tipo = 'pergunta'
                     or (w.tipo = 'confirmacao' and exists (
                           select 1 from public.ai_operator_pending_actions a
                            where a.id = w.referencia_id and a.status = 'pending'
                              and (a.expires_at is null or a.expires_at > now())))
                     or (w.tipo = 'opcoes' and exists (
                           select 1 from public.ai_operator_sessions s
                            where s.id = w.referencia_id and s.status = 'open'
                              and jsonb_typeof(s.metadata->'pending_options') = 'array'
                              and jsonb_array_length(s.metadata->'pending_options') > 0))))
     or public._pendencia_viva_do_telefone(p_phone) is not null then
    return 'ocupado';
  end if;
  if exists (select 1 from public.comprovantes x
              where x.phone_normalized = p_phone and x.situacao = 'aguardando_vez' and x.perguntas_automaticas < 3
                and (x.adiado_ate is null or x.adiado_ate <= now())
                and (x.perguntas_automaticas = 0 or v_fila.ultima_pergunta_fechada_em is null
                     or v_fila.ultima_pergunta_fechada_em <= now() - interval '4 hours')) then
    return null;
  end if;
  if exists (select 1 from public.comprovantes x where x.phone_normalized = p_phone and x.situacao = 'aguardando_vez') then
    return 'limite_de_tentativas';
  end if;
  return 'fila_vazia';
end $$;

comment on function public._comprovante_vigia_pode(text) is
  'Comprovantes: o vigia pode perguntar a este telefone agora? null = pode; senão o motivo. Horário: 09:30–20:00 de São Paulo, seg–sáb (das 07:30 às 09:30 só a manhã do secretário pergunta — Passo 4, 15/10/2026). Interna (sem execute para ninguém além do dono das funções).';

-- os mesmos privilégios de 20261011202000: ninguém executa direto (só as funções do dono a chamam)
revoke all on function public._comprovante_vigia_pode(text) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- Prova: a linha nova está lá, a velha não, e a porta continua fechada.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_def text := pg_get_functiondef('public._comprovante_vigia_pode(text)'::regprocedure);
begin
  if position('time ''09:30''' in v_def) = 0 or position('time ''08:00''' in v_def) > 0 then
    raise exception 'o vigia dos comprovantes não ficou com a janela das 09:30';
  end if;
  if position('time ''20:00''' in v_def) = 0 or position('isodow from v_agora) = 7' in v_def) = 0 then
    raise exception 'o fim do horário (20:00) ou o domingo sumiram do vigia dos comprovantes';
  end if;
  if has_function_privilege('anon', 'public._comprovante_vigia_pode(text)', 'execute')
     or has_function_privilege('authenticated', 'public._comprovante_vigia_pode(text)', 'execute') then
    raise exception '_comprovante_vigia_pode exposta para anon/authenticated';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261016100000', 'janela_da_manha_comprovantes')
on conflict do nothing;
