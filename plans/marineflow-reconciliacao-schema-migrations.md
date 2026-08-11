# Deriva do `schema_migrations` — proposta de reconciliação

**Data:** 11/08/2026 · **Status:** proposta, SOMENTE LEITURA · **Gate:** aplicar é decisão do Gustavo,
e precisa vir **antes** de qualquer `supabase db push` futuro.

---

## 1. O que está errado

Cinco migrations que apliquei em 10–11/08 estão no banco com uma **versão diferente do nome do
arquivo** que as contém. Apliquei pelo MCP do Supabase, que atribui o próprio timestamp em vez de
usar o do arquivo.

| Arquivo em `supabase/migrations/` | Versão no `schema_migrations` |
|---|---|
| `20260810020000_sugere_cliente_nas_entradas_da_fila.sql` | `20260810023803` |
| `20260810021000_motivo_do_cliente_sugerido.sql` | `20260810023855` |
| `20260810030000_fatura_do_cartao_como_entidade.sql` | `20260810024843` |
| `20260810040000_pagamento_de_fatura_nao_e_pedagio.sql` | `20260810025605` |
| `20260810120000_nfse_cadastro_fiscal_de_servicos.sql` | `20260811014317` |

O `name` bate nos cinco casos; só a `version` divergiu. Nenhuma das cinco versões do **arquivo**
existe na tabela.

**A consequência:** o `supabase db push` decide o que aplicar comparando a **versão** do nome do
arquivo com as versões registradas. Para ele, essas cinco **nunca foram aplicadas** — e ele vai
tentar rodar as cinco de novo.

Isto é a mesma família do MF-AUD-058 (35 migrations aplicadas sem arquivo) e do NOVO-003, mas pelo
avesso: lá o banco tinha o que o repositório não tinha; aqui o repositório tem o que o banco não
reconhece.

---

## 2. O que acontece se rodarem `db push` hoje

Reli as cinco. Quatro são inertes numa segunda execução; **uma não é**.

| Migration | Reexecutar faz o quê | Seguro? |
|---|---|---|
| `nfse_cadastro_fiscal_de_servicos` | `add column if not exists` + `drop constraint if exists` antes de cada `add` | **inerte** |
| `fatura_do_cartao_como_entidade` | `create or replace view` | **inerte** |
| `motivo_do_cliente_sugerido` | `UPDATE` com guarda `not like '%Cliente reconhecido%'` | **inerte** |
| `pagamento_de_fatura_nao_e_pedagio` | `UPDATE` com guarda `is distinct from` | **inerte** |
| **`sugere_cliente_nas_entradas_da_fila`** | **`UPDATE` em propostas pendentes onde `suggested_client_id is null`** | **NÃO é inerte** |

### Por que a quinta é diferente

Ela preenche o cliente sugerido nas entradas da fila que ainda não têm um. Reexecutar **não desfaz
nada** — a guarda `is null` protege o que já foi preenchido —, mas **alcança linhas novas**: as
entradas que chegaram ao Extrato depois de 10/08 e ainda não foram tratadas.

O efeito seria preencher sugestões de cliente que ninguém pediu, num momento em que ninguém está
olhando. Não corrompe dado, mas escreve em produção por acidente — e sugestão de cliente é a
antessala de um recebível lançado no cliente errado.

---

## 3. Três saídas

### A. Registrar as versões dos arquivos como já aplicadas *(recomendada)*

Inserir as cinco versões faltantes em `supabase_migrations.schema_migrations`, sem rodar SQL nenhum
de negócio. O `db push` passa a considerá-las aplicadas e nunca mais as reexecuta.

```sql
-- PROPOSTA — não executada.
insert into supabase_migrations.schema_migrations (version, name)
values
  ('20260810020000', 'sugere_cliente_nas_entradas_da_fila'),
  ('20260810021000', 'motivo_do_cliente_sugerido'),
  ('20260810030000', 'fatura_do_cartao_como_entidade'),
  ('20260810040000', 'pagamento_de_fatura_nao_e_pedagio'),
  ('20260810120000', 'nfse_cadastro_fiscal_de_servicos')
on conflict (version) do nothing;
```

**A favor:** o efeito no schema já está aplicado — o que falta é só o registro. Uma linha por
migration, reversível com `delete` pelas mesmas cinco versões.
**Contra:** ficam dez registros para cinco migrations (a versão do arquivo e a do MCP). O histórico
mostra a cicatriz — o que, aqui, prefiro a esconder.

### B. Corrigir as versões existentes com `UPDATE`

`update ... set version = '20260810020000' where name = 'sugere_cliente...'`, e assim por diante.

**A favor:** fica uma linha por migration, histórico limpo.
**Contra:** reescreve registro de auditoria de algo que **de fato aconteceu naquele instante**. A
versão `20260810023803` é a hora real da aplicação. Prefiro não apagar isso.

### C. Renomear os arquivos para casar com o banco

`git mv 20260810020000_... 20260810023803_...` nos cinco.

**A favor:** nenhuma escrita no banco.
**Contra:** os arquivos já estão **commitados e em branches publicados** — dois deles no
`feat/nfse-nacional`, que ainda não foi mergeado. Renomear agora cria conflito onde não há, e
qualquer clone antigo continua com o nome velho.

---

## 4. Recomendação e ordem

**Saída A**, e **antes** do próximo `db push` — não depois. A janela de risco existe desde 10/08 e
só fecha quando alguém rodar isto ou o push.

Ordem sugerida:

1. Você aprova a saída.
2. Aplico o `insert` (é gate seu — não executo sem o "sim").
3. Confiro que as dez versões estão lá e que `db push --dry-run` não lista nenhuma das cinco.
4. Registro o achado como resolvido em `audit/novos-achados.md`.

**Enquanto isso não acontece:** não rodar `supabase db push` neste projeto. Se alguém precisar
aplicar a migration da F-NFSE-03, faça pelo caminho manual (o mesmo de sempre), não pelo push.

---

## 5. O que isto não resolve

A causa: **aplicar migration pelo MCP faz o timestamp divergir do arquivo**. Enquanto o caminho de
aplicação for esse, a deriva volta na próxima. Resolver de verdade é aplicar por `supabase db push`
ou `db query -f <arquivo>`, que respeitam a versão do nome — mas isso é mudança de processo, e vale
uma conversa própria, não um item de lista.
