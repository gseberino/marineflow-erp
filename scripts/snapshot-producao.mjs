#!/usr/bin/env node
// Snapshot do schema de PRODUÇÃO lido dos catálogos do Postgres (pg_catalog), sem pg_dump
// nem Docker — o `supabase db dump` exige o daemon do Docker, que não roda nesta máquina.
//
// Por que existe (MF-AUD-058): 180 migrations foram aplicadas em produção sem arquivo no
// repositório e 111 arquivos foram aplicados sem registro. Nenhuma sequência de arquivos
// reconstrói o banco de verdade. Este snapshot é a descrição fiel do que está no ar, e é
// repetível: rodar de novo e olhar o `git diff` mostra o que mudou no banco desde o último.
//
// Uso:   node scripts/snapshot-producao.mjs          (exige `npx supabase link` já feito)
// Saída: supabase/schemas/producao/*.sql + README.md
//
// O que sai daqui NÃO é para ser aplicado por `db push`: é referência e prova. Para subir um
// ambiente do zero a partir dele, a ordem dos arquivos já é a ordem de criação.
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync, mkdtempSync, rmSync, readdirSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const OUT = join(process.cwd(), 'supabase', 'schemas', 'producao');
const TMP = mkdtempSync(join(tmpdir(), 'snap-'));
let contador = 0;

function query(sql) {
  const f = join(TMP, `q${++contador}.sql`);
  writeFileSync(f, sql);
  const out = execFileSync('npx', ['supabase', 'db', 'query', '--linked', '-f', f], {
    encoding: 'utf8', maxBuffer: 256 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'], shell: true,
  });
  const i = out.indexOf('{');
  if (i < 0) throw new Error(`resposta sem JSON para a consulta ${contador}: ${out.slice(0, 200)}`);
  const j = JSON.parse(out.slice(i));
  if (j.error) throw new Error(`erro na consulta ${contador}: ${JSON.stringify(j.error).slice(0, 300)}`);
  return j.rows || [];
}

const ident = (s) => (/^[a-z_][a-z0-9_]*$/.test(s) ? s : `"${String(s).replace(/"/g, '""')}"`);
const q = (sch, name) => `${ident(sch)}.${ident(name)}`;
const lit = (s) => `'${String(s).replace(/'/g, "''")}'`;
const cabecalho = (titulo) =>
  `-- ${titulo}\n-- Gerado por scripts/snapshot-producao.mjs a partir dos catálogos do banco de produção.\n-- NÃO editar à mão: regenerar. A data e as contagens ficam no README.md ao lado.\n\n`;

// Privilégios em formato aclitem ("anon=X/postgres", "=r/postgres" = PUBLIC) → statements.
function aclParaStatements(acl, alvo, tipo) {
  if (!acl) return [`-- ${alvo}: ACL padrão (sem grants explícitos)`];
  const linhas = [`-- ACL: ${acl}`];
  const nomes = { r: 'SELECT', w: 'UPDATE', a: 'INSERT', d: 'DELETE', D: 'TRUNCATE', x: 'REFERENCES', t: 'TRIGGER', X: 'EXECUTE', U: 'USAGE' };
  for (const item of acl.split(/[\s,{}]+/).filter(Boolean)) {
    const m = item.match(/^(.*?)=([a-zA-Z*]*)\/(.*)$/);
    if (!m) continue;
    const grantee = m[1] === '' ? 'PUBLIC' : ident(m[1]);
    const privs = [...m[2].replace(/\*/g, '')].map((c) => nomes[c] ?? c);
    if (privs.length) linhas.push(`GRANT ${privs.join(', ')} ON ${tipo} ${alvo} TO ${grantee};`);
  }
  return linhas;
}

mkdirSync(OUT, { recursive: true });
for (const f of readdirSync(OUT)) if (f.endsWith('.sql')) unlinkSync(join(OUT, f));

const meta = query(`select now() as agora, current_database() as db,
  (select count(*) from supabase_migrations.schema_migrations) as versoes,
  (select max(version) from supabase_migrations.schema_migrations) as ultima_versao`)[0];
const contagens = {};

// ── 00 · schemas, extensões, tipos ─────────────────────────────────────────────
{
  const schemas = query(`select nspname from pg_namespace where nspname not in ('pg_catalog','information_schema','pg_toast')
    and nspname not like 'pg_temp%' and nspname not like 'pg_toast%' order by 1`);
  const exts = query(`select e.extname, e.extversion, n.nspname from pg_extension e join pg_namespace n on n.oid=e.extnamespace order by 1`);
  const enums = query(`select t.typname as name, string_agg(quote_literal(e.enumlabel), ', ' order by e.enumsortorder) as labels
    from pg_type t join pg_enum e on e.enumtypid=t.oid join pg_namespace n on n.oid=t.typnamespace
    where n.nspname='public' group by 1 order by 1`);
  const domains = query(`select t.typname as name, format_type(t.typbasetype, t.typtypmod) as base, t.typnotnull as nn,
    pg_get_expr(t.typdefaultbin, 0) as dflt,
    (select string_agg(pg_get_constraintdef(c.oid, true), ' ') from pg_constraint c where c.contypid=t.oid) as cons
    from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typtype='d' order by 1`);
  const compostos = query(`select t.typname as name,
    string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), ', ' order by a.attnum) as campos
    from pg_type t join pg_namespace n on n.oid=t.typnamespace join pg_class c on c.oid=t.typrelid and c.relkind='c'
    join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
    where n.nspname='public' and t.typtype='c' group by 1 order by 1`);
  let s = cabecalho('00 · Schemas, extensões e tipos');
  s += `-- Schemas presentes: ${schemas.map((r) => r.nspname).join(', ')}\n\n`;
  s += `-- Extensões (nome · versão · schema):\n` + exts.map((e) => `--   ${e.extname} · ${e.extversion} · ${e.nspname}`).join('\n') + '\n\n';
  for (const e of exts) if (!['plpgsql'].includes(e.extname)) s += `CREATE EXTENSION IF NOT EXISTS ${ident(e.extname)} WITH SCHEMA ${ident(e.nspname)};\n`;
  s += '\n';
  for (const t of enums) s += `CREATE TYPE ${q('public', t.name)} AS ENUM (${t.labels});\n`;
  for (const d of domains) s += `CREATE DOMAIN ${q('public', d.name)} AS ${d.base}${d.dflt ? ` DEFAULT ${d.dflt}` : ''}${d.nn ? ' NOT NULL' : ''}${d.cons ? ` ${d.cons}` : ''};\n`;
  for (const c of compostos) s += `CREATE TYPE ${q('public', c.name)} AS (${c.campos});\n`;
  writeFileSync(join(OUT, '00-schemas-extensoes-tipos.sql'), s);
  Object.assign(contagens, { schemas: schemas.length, extensoes: exts.length, enums: enums.length, domains: domains.length, tipos_compostos: compostos.length });
}

// ── 01 · sequências ────────────────────────────────────────────────────────────
{
  const seqs = query(`select s.relname as seq, sq.data_type, sq.start_value, sq.increment_by, sq.min_value, sq.max_value, sq.cycle,
    d.deptype, t.relname as owned_tbl, a.attname as owned_col
    from pg_class s join pg_namespace n on n.oid=s.relnamespace
    join pg_sequences sq on sq.schemaname=n.nspname and sq.sequencename=s.relname
    left join pg_depend d on d.objid=s.oid and d.classid='pg_class'::regclass and d.deptype in ('a','i')
    left join pg_class t on t.oid=d.refobjid
    left join pg_attribute a on a.attrelid=d.refobjid and a.attnum=d.refobjsubid
    where n.nspname='public' and s.relkind='S' order by 1`);
  let s = cabecalho('01 · Sequências (as de coluna IDENTITY nascem com a tabela e ficam só comentadas)');
  for (const x of seqs) {
    if (x.deptype === 'i') { s += `-- ${x.seq}: identity de ${x.owned_tbl}.${x.owned_col}\n`; continue; }
    s += `CREATE SEQUENCE IF NOT EXISTS ${q('public', x.seq)} AS ${x.data_type} START WITH ${x.start_value} INCREMENT BY ${x.increment_by} MINVALUE ${x.min_value} MAXVALUE ${x.max_value}${x.cycle ? ' CYCLE' : ''};\n`;
  }
  writeFileSync(join(OUT, '01-sequencias.sql'), s);
  contagens.sequencias = seqs.length;
  globalThis.__seqsOwned = seqs.filter((x) => x.deptype === 'a');
}

// ── 02 · tabelas (colunas, PK/UNIQUE/CHECK, RLS, comentários) ─────────────────
{
  const tbls = query(`select c.relname as tbl, c.relkind, c.relrowsecurity as rls, c.relforcerowsecurity as force_rls,
    obj_description(c.oid,'pg_class') as cmt, case when c.relkind='p' then pg_get_partkeydef(c.oid) end as partkey,
    array_to_string(c.relacl, ' ') as acl
    from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p') order by 1`);
  const cols = query(`select c.relname as tbl, a.attnum, a.attname, format_type(a.atttypid, a.atttypmod) as typ, a.attnotnull as nn,
    pg_get_expr(d.adbin, d.adrelid) as dflt, a.attidentity as ident, a.attgenerated as gen, col_description(c.oid, a.attnum) as cmt
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
    left join pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum
    where n.nspname='public' and c.relkind in ('r','p') order by c.relname, a.attnum`);
  const cons = query(`select c.relname as tbl, con.conname, con.contype, pg_get_constraintdef(con.oid, true) as def
    from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and con.contype in ('p','u','c','x','f') order by c.relname, con.contype, con.conname`);
  const porTabela = new Map();
  for (const c of cols) { if (!porTabela.has(c.tbl)) porTabela.set(c.tbl, []); porTabela.get(c.tbl).push(c); }
  const consPorTabela = new Map();
  for (const c of cons) { if (!consPorTabela.has(c.tbl)) consPorTabela.set(c.tbl, []); consPorTabela.get(c.tbl).push(c); }
  let s = cabecalho('02 · Tabelas: colunas, PK/UNIQUE/CHECK, RLS e comentários (FKs no arquivo 03)');
  for (const t of tbls) {
    const linhas = [];
    for (const c of porTabela.get(t.tbl) ?? []) {
      let l = `  ${ident(c.attname)} ${c.typ}`;
      if (c.gen === 's') l += ` GENERATED ALWAYS AS (${c.dflt}) STORED`;
      else if (c.ident === 'a') l += ' GENERATED ALWAYS AS IDENTITY';
      else if (c.ident === 'd') l += ' GENERATED BY DEFAULT AS IDENTITY';
      else if (c.dflt != null) l += ` DEFAULT ${c.dflt}`;
      if (c.nn) l += ' NOT NULL';
      linhas.push(l);
    }
    for (const c of consPorTabela.get(t.tbl) ?? []) if (c.contype !== 'f') linhas.push(`  CONSTRAINT ${ident(c.conname)} ${c.def}`);
    s += `-- ── ${t.tbl} ──\nCREATE TABLE ${q('public', t.tbl)} (\n${linhas.join(',\n')}\n)${t.partkey ? ` PARTITION BY ${t.partkey}` : ''};\n`;
    if (t.cmt) s += `COMMENT ON TABLE ${q('public', t.tbl)} IS ${lit(t.cmt)};\n`;
    for (const c of porTabela.get(t.tbl) ?? []) if (c.cmt) s += `COMMENT ON COLUMN ${q('public', t.tbl)}.${ident(c.attname)} IS ${lit(c.cmt)};\n`;
    if (t.rls) s += `ALTER TABLE ${q('public', t.tbl)} ENABLE ROW LEVEL SECURITY;\n`;
    if (t.force_rls) s += `ALTER TABLE ${q('public', t.tbl)} FORCE ROW LEVEL SECURITY;\n`;
    s += '\n';
  }
  s += `-- Sequências de colunas serial: vínculo OWNED BY\n`;
  for (const x of globalThis.__seqsOwned) if (x.owned_tbl) s += `ALTER SEQUENCE ${q('public', x.seq)} OWNED BY ${q('public', x.owned_tbl)}.${ident(x.owned_col)};\n`;
  writeFileSync(join(OUT, '02-tabelas.sql'), s);
  Object.assign(contagens, { tabelas: tbls.length, colunas: cols.length, tabelas_com_rls: tbls.filter((t) => t.rls).length, tabelas_sem_rls: tbls.filter((t) => !t.rls).map((t) => t.tbl) });
  globalThis.__fks = cons.filter((c) => c.contype === 'f');
  globalThis.__tblAcl = tbls.map((t) => ({ tbl: t.tbl, acl: t.acl }));
}

// ── 03 · chaves estrangeiras ───────────────────────────────────────────────────
{
  let s = cabecalho('03 · Chaves estrangeiras (depois de todas as tabelas, para não depender de ordem)');
  for (const c of globalThis.__fks) s += `ALTER TABLE ${q('public', c.tbl)} ADD CONSTRAINT ${ident(c.conname)} ${c.def};\n`;
  writeFileSync(join(OUT, '03-chaves-estrangeiras.sql'), s);
  contagens.fks = globalThis.__fks.length;
}

// ── 04 · índices (os que não sustentam constraint) ─────────────────────────────
{
  const idx = query(`select i.tablename as tbl, i.indexname as name, i.indexdef as def
    from pg_indexes i where i.schemaname='public'
      and not exists (select 1 from pg_constraint con join pg_class ic on ic.oid=con.conindid where ic.relname=i.indexname)
    order by 1,2`);
  let s = cabecalho('04 · Índices que não sustentam constraint (PK/UNIQUE estão no arquivo 02)');
  for (const x of idx) s += `${x.def};\n`;
  writeFileSync(join(OUT, '04-indices.sql'), s);
  contagens.indices = idx.length;
}

// ── 05 · funções e procedures ──────────────────────────────────────────────────
{
  // `private` guarda as funções do operador de IA (ai_op_*); sem elas o snapshot não fecha.
  const fns = query(`select n.nspname as sch, p.proname as name, pg_get_function_identity_arguments(p.oid) as args, pg_get_functiondef(p.oid) as def,
    array_to_string(p.proacl, ' ') as acl, obj_description(p.oid,'pg_proc') as cmt, p.prosecdef as secdef,
    (select string_agg(cfg, ' ') from unnest(p.proconfig) cfg) as config
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('public','private') and p.prokind in ('f','p')
      and not exists (select 1 from pg_depend d where d.objid=p.oid and d.deptype='e')
    order by n.nspname, p.proname, args`);
  let s = cabecalho('05 · Funções e procedures dos schemas public e private (definição viva + privilégios)');
  for (const f of fns) {
    const sig = `${q(f.sch, f.name)}(${f.args})`;
    s += `-- ── ${f.sch}.${f.name}(${f.args}) ──${f.secdef ? ' SECURITY DEFINER' : ''}${f.config ? ` [${f.config}]` : ''}\n${f.def};\n`;
    if (f.cmt) s += `COMMENT ON FUNCTION ${sig} IS ${lit(f.cmt)};\n`;
    s += aclParaStatements(f.acl, sig, 'FUNCTION').join('\n') + '\n\n';
  }
  writeFileSync(join(OUT, '05-funcoes.sql'), s);
  contagens.funcoes = fns.length;
  contagens.funcoes_security_definer = fns.filter((f) => f.secdef).length;
  contagens.funcoes_sem_search_path_fixo = fns.filter((f) => f.secdef && !/search_path/.test(f.config || '')).map((f) => f.name);
  contagens.funcoes_executaveis_por_anon = fns.filter((f) => !f.acl || /(^|[\s,{])anon=/.test(f.acl) || /(^|[\s,{])=[a-zA-Z]*X/.test(f.acl)).map((f) => `${f.name}(${f.args})`);
}

// ── 06 · views (em ordem de dependência) ───────────────────────────────────────
{
  const views = query(`select c.relname as name, c.relkind, pg_get_viewdef(c.oid, true) as def, array_to_string(c.reloptions, ', ') as opts,
    array_to_string(c.relacl, ' ') as acl, obj_description(c.oid,'pg_class') as cmt
    from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('v','m') order by 1`);
  const deps = query(`select distinct dependent.relname as v, source.relname as dep
    from pg_depend d join pg_rewrite r on r.oid=d.objid join pg_class dependent on dependent.oid=r.ev_class
    join pg_class source on source.oid=d.refobjid join pg_namespace n on n.oid=dependent.relnamespace
    where n.nspname='public' and dependent.relkind in ('v','m') and source.relkind in ('v','m') and dependent.oid<>source.oid`);
  const depMap = new Map(); for (const d of deps) { if (!depMap.has(d.v)) depMap.set(d.v, new Set()); depMap.get(d.v).add(d.dep); }
  const ordem = []; const visto = new Set();
  const visita = (nome) => { if (visto.has(nome)) return; visto.add(nome); for (const d of depMap.get(nome) ?? []) visita(d); ordem.push(nome); };
  for (const v of views) visita(v.name);
  const porNome = new Map(views.map((v) => [v.name, v]));
  let s = cabecalho('06 · Views e materialized views, em ordem de dependência');
  for (const nome of ordem) {
    const v = porNome.get(nome); if (!v) continue;
    const kind = v.relkind === 'm' ? 'MATERIALIZED VIEW' : 'VIEW';
    s += `-- ── ${v.name} ──\nCREATE ${kind} ${q('public', v.name)}${v.opts ? ` WITH (${v.opts})` : ''} AS\n${v.def.replace(/;\s*$/, '')};\n`;
    if (v.cmt) s += `COMMENT ON ${kind} ${q('public', v.name)} IS ${lit(v.cmt)};\n`;
    s += aclParaStatements(v.acl, q('public', v.name), 'TABLE').join('\n') + '\n\n';
  }
  writeFileSync(join(OUT, '06-views.sql'), s);
  contagens.views = views.length;
  contagens.views_sem_security_invoker = views.filter((v) => v.relkind === 'v' && !/security_invoker\s*=\s*(on|true)/i.test(v.opts || '')).map((v) => v.name);
}

// ── 07 · triggers (public, auth.users, storage) ────────────────────────────────
{
  const trg = query(`select n.nspname as sch, c.relname as tbl, t.tgname as name, pg_get_triggerdef(t.oid, true) as def, t.tgenabled
    from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
    where not t.tgisinternal and n.nspname in ('public','auth','storage') order by 1,2,3`);
  let s = cabecalho('07 · Triggers (public, auth e storage — os de auth/storage chamam funções do public)');
  for (const t of trg) {
    s += `${t.def};\n`;
    if (t.tgenabled === 'D') s += `ALTER TABLE ${q(t.sch, t.tbl)} DISABLE TRIGGER ${ident(t.name)};\n`;
  }
  writeFileSync(join(OUT, '07-triggers.sql'), s);
  contagens.triggers = trg.length;
}

// ── 08 · políticas de RLS (public e storage) ───────────────────────────────────
{
  const pol = query(`select schemaname as sch, tablename as tbl, policyname as name, permissive, array_to_string(roles, ', ') as roles, cmd, qual, with_check
    from pg_policies where schemaname in ('public','storage') order by 1,2,3`);
  let s = cabecalho('08 · Políticas de RLS (public e storage)');
  let atual = '';
  for (const p of pol) {
    const chave = `${p.sch}.${p.tbl}`;
    if (chave !== atual) { s += `\n-- ── ${chave} ──\n`; atual = chave; }
    s += `CREATE POLICY "${p.name.replace(/"/g, '""')}" ON ${q(p.sch, p.tbl)} AS ${p.permissive} FOR ${p.cmd} TO ${p.roles}`;
    if (p.qual) s += `\n  USING (${p.qual})`;
    if (p.with_check) s += `\n  WITH CHECK (${p.with_check})`;
    s += ';\n';
  }
  writeFileSync(join(OUT, '08-politicas-rls.sql'), s);
  contagens.politicas = pol.length;
  contagens.politicas_para_anon = pol.filter((p) => /\b(anon|public)\b/.test(p.roles)).length;
}

// ── 09 · privilégios de tabela/view ────────────────────────────────────────────
{
  const gr = query(`select table_name as tbl, grantee, string_agg(privilege_type, ', ' order by privilege_type) as privs
    from information_schema.role_table_grants where table_schema='public' and grantee in ('anon','authenticated','service_role','PUBLIC')
    group by 1,2 order by 1,2`);
  let s = cabecalho('09 · Privilégios de tabela/view para anon, authenticated e service_role');
  for (const g of gr) s += `GRANT ${g.privs} ON ${q('public', g.tbl)} TO ${g.grantee === 'PUBLIC' ? 'PUBLIC' : ident(g.grantee)};\n`;
  writeFileSync(join(OUT, '09-privilegios.sql'), s);
  contagens.grants = gr.length;
}

// ── 10 · cron e storage ────────────────────────────────────────────────────────
{
  let cron = [];
  try { cron = query(`select jobname, schedule, command, active from cron.job order by jobname`); } catch (e) { cron = [{ jobname: `-- cron.job inacessível: ${e.message.slice(0, 120)}`, schedule: '', command: '', active: null }]; }
  const buckets = query(`select id, name, public, file_size_limit, array_to_string(allowed_mime_types, ', ') as mimes from storage.buckets order by id`);
  let s = cabecalho('10 · Agendamentos (pg_cron) e buckets do Storage');
  for (const j of cron) {
    if (!j.schedule) { s += `${j.jobname}\n`; continue; }
    s += `-- ${j.jobname} · ${j.schedule}${j.active === false ? ' · INATIVO' : ''}\nselect cron.schedule(${lit(j.jobname)}, ${lit(j.schedule)}, $cron$${j.command}$cron$);\n`;
    if (j.active === false) s += `update cron.job set active = false where jobname = ${lit(j.jobname)};\n`;
    s += '\n';
  }
  for (const b of buckets) s += `insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values (${lit(b.id)}, ${lit(b.name)}, ${b.public}, ${b.file_size_limit ?? 'null'}, ${b.mimes ? `'{${b.mimes}}'` : 'null'}) on conflict (id) do nothing;\n`;
  writeFileSync(join(OUT, '10-cron-e-storage.sql'), s);
  contagens.crons = cron.filter((j) => j.schedule).length;
  contagens.buckets = buckets.length;
  contagens.buckets_publicos = buckets.filter((b) => b.public).map((b) => b.id);
}

// ── README ─────────────────────────────────────────────────────────────────────
{
  const lista = (arr) => (arr && arr.length ? arr.map((x) => `\`${x}\``).join(', ') : '—');
  const md = `# Snapshot do schema de produção

Gerado por \`node scripts/snapshot-producao.mjs\` em **${meta.agora}** (banco \`${meta.db}\`),
lendo os catálogos do Postgres pela CLI (\`supabase db query --linked\`) — sem pg_dump e sem Docker.

**Por que existe (MF-AUD-058):** o histórico de migrations não reconstrói a produção — havia
migrations aplicadas sem arquivo e arquivos aplicados sem registro. Este diretório é a descrição
fiel do que está no ar. Regenerar e olhar o \`git diff\` é a forma de ver deriva.

**Não é para \`db push\`.** É referência, prova e ponto de partida para subir um ambiente do zero
(os arquivos estão em ordem de criação).

## Contagens

| objeto | quantidade |
|---|---:|
| versões em \`schema_migrations\` | ${meta.versoes} (última: \`${meta.ultima_versao}\`) |
| schemas | ${contagens.schemas} |
| extensões | ${contagens.extensoes} |
| enums / domains / tipos compostos | ${contagens.enums} / ${contagens.domains} / ${contagens.tipos_compostos} |
| sequências | ${contagens.sequencias} |
| tabelas (colunas) | ${contagens.tabelas} (${contagens.colunas}) |
| tabelas com RLS | ${contagens.tabelas_com_rls} de ${contagens.tabelas} |
| chaves estrangeiras | ${contagens.fks} |
| índices (fora de constraint) | ${contagens.indices} |
| funções/procedures | ${contagens.funcoes} (${contagens.funcoes_security_definer} SECURITY DEFINER) |
| views | ${contagens.views} |
| triggers | ${contagens.triggers} |
| políticas de RLS | ${contagens.politicas} (${contagens.politicas_para_anon} alcançam anon/public) |
| grants de tabela | ${contagens.grants} |
| crons | ${contagens.crons} |
| buckets | ${contagens.buckets} |

## Sinais que valem olhar

- Tabelas **sem RLS**: ${lista(contagens.tabelas_sem_rls)}
- Funções SECURITY DEFINER **sem \`search_path\` fixo**: ${lista(contagens.funcoes_sem_search_path_fixo)}
- Funções **executáveis por anon** (ACL padrão ou grant explícito): ${contagens.funcoes_executaveis_por_anon.length} — ${lista(contagens.funcoes_executaveis_por_anon.slice(0, 40))}${contagens.funcoes_executaveis_por_anon.length > 40 ? ' …' : ''}
- Views **sem \`security_invoker\`**: ${lista(contagens.views_sem_security_invoker)}
- Buckets **públicos**: ${lista(contagens.buckets_publicos)}

## Arquivos

| arquivo | conteúdo |
|---|---|
| \`00-schemas-extensoes-tipos.sql\` | schemas, extensões, enums, domains, tipos compostos |
| \`01-sequencias.sql\` | sequências (as de IDENTITY só comentadas) |
| \`02-tabelas.sql\` | CREATE TABLE com colunas, PK/UNIQUE/CHECK, comentários, RLS |
| \`03-chaves-estrangeiras.sql\` | ALTER TABLE ADD CONSTRAINT … FOREIGN KEY |
| \`04-indices.sql\` | índices fora de constraint |
| \`05-funcoes.sql\` | \`pg_get_functiondef\` de cada função + COMMENT + privilégios |
| \`06-views.sql\` | views em ordem de dependência, com \`reloptions\` e privilégios |
| \`07-triggers.sql\` | triggers de public, auth e storage |
| \`08-politicas-rls.sql\` | CREATE POLICY reconstruído de \`pg_policies\` |
| \`09-privilegios.sql\` | grants de tabela/view para anon/authenticated/service_role |
| \`10-cron-e-storage.sql\` | jobs do pg_cron e buckets |
`;
  writeFileSync(join(OUT, 'README.md'), md);
}

rmSync(TMP, { recursive: true, force: true });
console.log(JSON.stringify({ saida: OUT, ...contagens, tabelas_sem_rls: undefined, funcoes_sem_search_path_fixo: undefined, funcoes_executaveis_por_anon: contagens.funcoes_executaveis_por_anon.length, views_sem_security_invoker: contagens.views_sem_security_invoker.length, buckets_publicos: undefined }, null, 1));
