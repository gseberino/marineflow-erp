-- Cadastro de fornecedores (NOVO-agenda-30, achado da Fase 4 da Agenda de Produção, pacote P6): a cidade com o caractere
-- quebrado (U+FFFD, "Itaja�") volta a ter o acento ("Itajaí"), só nas 24 grafias da lista fechada medida em 25/10/2026.
-- Spec: scratchpad agenda-pesquisa/spec-fase4.md (§1 NOVO-agenda-30, d7, §10 passo 8, §12, §13 item 7).
--
-- ═══ MUDA CADASTRO DE PRODUÇÃO — OPCIONAL, OK NOMEADO À PARTE ═══ (só dado de suppliers.city + a tabela do "antes")
-- NÃO APLICADA. Só roda com o OK nomeado do dono ("OK acento das cidades"), depois de tudo da Fase 4 (fila-do-dono/
-- fase4-oks.md, passo 8). A agenda NÃO precisa disto: desde a 20261027100100 ela compara a cidade tolerando o caractere
-- quebrado ("Itaja�" já conta como Itajaí, entrega local). Isto só conserta o cadastro para quem lê a tela e os relatórios.
--
-- POR QUE: a importação de 12/04/2026 gravou 197 fornecedores (16 ativos) com U+FFFD no lugar da letra acentuada da cidade.
-- Na tela aparece "Itaja�"; em busca e relatório, "Itajaí" e "Itaja�" são cidades diferentes.
--
-- O QUE FAZ:
--   1. Cria public.fornecedores_cidade_corrigida (o "antes" de cada linha trocada: supplier_id, cidade_antes,
--      cidade_depois, corrigida_em), fechada (RLS ligada, sem grant para anon nem authenticated): é o que o DESFAZER lê.
--   2. Troca suppliers.city SÓ quando a cidade é EXATAMENTE uma das 24 grafias abaixo (comparação byte a byte, o U+FFFD
--      montado por chr(65533)). Não mexe em nome, endereço, UF nem em cidade nenhuma fora da lista; não mexe em clientes.
--      Os 19 nomes e os 25 endereços com o mesmo caractere ficam como estão (decisão do dono, §12).
--
-- O ANTES (SELECT de 25/10/2026, sql/j06c_substituicao: 197 fornecedores, 16 ativos, todos criados em 12/04/2026). As 24
-- grafias e o que viram (o "�" é o U+FFFD; cada letra acentuada virou um):
--    Arma��o dos B�zios → Armação dos Búzios      Balne�rio Cambori� → Balneário Camboriú     Bar�o → Barão
--    Bigua�u → Biguaçu                            Bras�lia → Brasília                        Campo Mour�o → Campo Mourão
--    Florian�polis → Florianópolis                Itaja� → Itajaí                            ITAJA� → ITAJAÍ
--    Jundia� → Jundiaí                            Maring� → Maringá                          Palho�a → Palhoça
--    Paranagu� → Paranaguá                        Santo Andr� → Santo André                  S�o Caetano do Sul → São Caetano do Sul
--    S�o Francisco do Sul → São Francisco do Sul  S�o Jos� → São José                        S�o Jos� dos Campos → São José dos Campos
--    S�o Jos� dos Pinhais → São José dos Pinhais  S�o Jo�o Batista → São João Batista        S�o Jo�o da Boa Vista → São João da Boa Vista
--    S�o Paulo → São Paulo                        Tr�s Rios → Três Rios                      Tubar�o → Tubarão
--   Grafia com U+FFFD que apareça depois de 25/10 e não esteja aqui NÃO é trocada (a prova de depois mostra o que sobrou).
--
-- PROVA ANTES (só leitura):
--   npx supabase db query --linked -e "select city, count(*) as n, count(*) filter (where active) as ativos
--     from public.suppliers where strpos(coalesce(city, ''), chr(65533)) > 0 group by city order by city;"
--   Esperado em 25/10: as 24 grafias acima, 197 linhas (16 ativas).
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK nomeado do dono, à parte de todo o resto):
--   npx supabase db query --linked -f supabase/migrations/20261027102000_fornecedores_cidade_com_acento.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261027102000', 'fornecedores_cidade_com_acento');"
--
-- PROVA DEPOIS (só leitura): o SELECT do fim deste arquivo (as cidades trocadas, quantas, e o que sobrou com U+FFFD fora da
-- lista — esperado: nada) e o PROVA ANTES de novo (esperado: nenhuma linha).
--
-- IDEMPOTENTE: rodar de novo não troca nada (a cidade já não é a grafia quebrada) e não duplica o "antes" (on conflict do
-- nothing). A bancada NÃO aplica este arquivo (FORA_DA_BANCADA); supabase/tests/agenda_fase4_cidade_com_acento.sql o roda
-- numa subtransação desfeita (só as 24 grafias; "S�o Paulo" não vira "Itajaí"; de novo não muda nada; o DESFAZER).
--
-- DESFAZER (só se o dono pedir; volta a cidade de antes só onde ela ainda é a que esta migration gravou — se o dono mudou a
-- cidade depois, fica a dele; o "antes" fica guardado como rastro):
--   update public.suppliers s set city = b.cidade_antes from public.fornecedores_cidade_corrigida b where b.supplier_id = s.id and s.city = b.cidade_depois;
--

-- 1. O "antes" de cada linha trocada (fechada: só quem tem a chave do banco lê).
create table if not exists public.fornecedores_cidade_corrigida (
  supplier_id   uuid primary key references public.suppliers(id) on delete cascade,
  cidade_antes  text not null,
  cidade_depois text not null,
  corrigida_em  timestamptz not null default now()
);
alter table public.fornecedores_cidade_corrigida enable row level security;
revoke all on table public.fornecedores_cidade_corrigida from public, anon, authenticated;
comment on table public.fornecedores_cidade_corrigida is
  'NOVO-agenda-30 (migration 20261027102000): a cidade de cada fornecedor que a correção do acento trocou — o antes (com U+FFFD) e o depois. É o que o DESFAZER da migration lê. Fechada: RLS ligada, sem grant para anon nem authenticated.';

-- 2. A troca, só nas 24 grafias da lista fechada ("#" = U+FFFD).
with lista(de, para) as (values
  ('Arma##o dos B#zios', 'Armação dos Búzios'), ('Balne#rio Cambori#', 'Balneário Camboriú'), ('Bar#o', 'Barão'),
  ('Bigua#u', 'Biguaçu'), ('Bras#lia', 'Brasília'), ('Campo Mour#o', 'Campo Mourão'),
  ('Florian#polis', 'Florianópolis'), ('Itaja#', 'Itajaí'), ('ITAJA#', 'ITAJAÍ'),
  ('Jundia#', 'Jundiaí'), ('Maring#', 'Maringá'), ('Palho#a', 'Palhoça'),
  ('Paranagu#', 'Paranaguá'), ('Santo Andr#', 'Santo André'), ('S#o Caetano do Sul', 'São Caetano do Sul'),
  ('S#o Francisco do Sul', 'São Francisco do Sul'), ('S#o Jos#', 'São José'), ('S#o Jos# dos Campos', 'São José dos Campos'),
  ('S#o Jos# dos Pinhais', 'São José dos Pinhais'), ('S#o Jo#o Batista', 'São João Batista'),
  ('S#o Jo#o da Boa Vista', 'São João da Boa Vista'),
  ('S#o Paulo', 'São Paulo'), ('Tr#s Rios', 'Três Rios'), ('Tubar#o', 'Tubarão')),
alvo as (
  select s.id, s.city as antes, l.para
    from public.suppliers s
    join lista l on s.city = replace(l.de, '#', chr(65533))
),
guarda as (
  insert into public.fornecedores_cidade_corrigida (supplier_id, cidade_antes, cidade_depois)
  select a.id, a.antes, a.para from alvo a
  on conflict (supplier_id) do nothing
  returning supplier_id
)
update public.suppliers s
   set city = a.para
  from alvo a
 where s.id = a.id;

-- O estado depois: as cidades trocadas por esta migration e o que sobrou com U+FFFD (fora da lista; esperado: nada).
select 'trocadas' as o_que, b.cidade_depois as cidade, count(*) as n
  from public.fornecedores_cidade_corrigida b
 group by b.cidade_depois
union all
select 'sobrou com U+FFFD', s.city, count(*)
  from public.suppliers s
 where strpos(coalesce(s.city, ''), chr(65533)) > 0
 group by s.city
 order by 1, 2;
