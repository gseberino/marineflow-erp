import '@/styles/marineflow-tokens.css';
import { useState, useMemo } from 'react';
import { useMarinas } from '@/hooks/use-marinas';
import { useAuth } from '@/hooks/use-auth';
import { useNavigate } from 'react-router-dom';
import type { Marina } from '@/hooks/use-marinas';

const V3 = {
  hdrBg:   '#020E1A',
  paper:   '#F7F6F2',
  gold:    '#C8A24B',
  goldDim: 'rgba(200,162,75,0.45)',
  navy900: '#0A1929',
  navy950: '#071420',
} as const;

// ─── CadStatus ────────────────────────────────────────────────────────────────

type CadStatus = 'completo' | 'sem-contato' | 'sem-localizacao' | 'revisar';

function getCadStatus(m: Marina): CadStatus {
  const row = m as any;
  const hasContact  = !!(m.contact_name || row.phone);
  const hasLocation = !!m.city;
  if (hasContact && hasLocation)   return 'completo';
  if (!hasContact && !hasLocation) return 'revisar';
  if (!hasContact)                 return 'sem-contato';
  return 'sem-localizacao';
}

const CAD_CFG: Record<CadStatus, { label: string; color: string; bg: string; border: string }> = {
  'completo':        { label: 'Completo',        color: '#15803d', bg: '#dcfce7', border: '#86efac' },
  'sem-contato':     { label: 'Sem contato',     color: '#b45309', bg: '#fef3c7', border: '#fcd34d' },
  'sem-localizacao': { label: 'Sem localização', color: '#0369a1', bg: '#e0f2fe', border: '#7dd3fc' },
  'revisar':         { label: 'Revisar',          color: '#b91c1c', bg: '#fee2e2', border: '#fca5a5' },
};

// ─── Types ────────────────────────────────────────────────────────────────────

type FilterAtivo  = 'all' | 'ativo' | 'inativo';
type FilterStatus = 'all' | CadStatus;
type SortKey = 'name' | 'cidade' | 'contato' | 'fone' | 'email' | 'status' | 'ativo';
type SortDir = 'asc' | 'desc';
type ColKey  = 'name' | 'cidade' | 'endereco' | 'contato' | 'fone' | 'email' | 'status' | 'ativo' | 'acoes';

interface ColDef {
  label: string;
  weight: number;
  required: boolean;
  sortKey?: SortKey;
  align: 'left' | 'center';
}

const COL_DEF: Record<ColKey, ColDef> = {
  name:     { label: 'Marina',           weight: 22, required: true,  sortKey: 'name',    align: 'left'   },
  cidade:   { label: 'Cidade · UF',      weight: 13, required: false, sortKey: 'cidade',  align: 'left'   },
  endereco: { label: 'Endereço',         weight: 16, required: false, sortKey: undefined, align: 'left'   },
  contato:  { label: 'Contato',          weight: 13, required: false, sortKey: 'contato', align: 'left'   },
  fone:     { label: 'Telefone',         weight: 12, required: false, sortKey: 'fone',    align: 'left'   },
  email:    { label: 'E-mail',           weight: 15, required: false, sortKey: 'email',   align: 'left'   },
  status:   { label: 'Status cadastral', weight: 14, required: false, sortKey: 'status',  align: 'center' },
  ativo:    { label: 'Ativo',            weight:  8, required: false, sortKey: 'ativo',   align: 'center' },
  acoes:    { label: 'Ações',            weight:  9, required: true,  sortKey: undefined, align: 'center' },
};

const COL_ORDER: ColKey[] = ['name', 'cidade', 'endereco', 'contato', 'fone', 'email', 'status', 'ativo', 'acoes'];

// Default: name, cidade, contato, fone, status, ativo, acoes (endereco, email initially hidden)
const DEFAULT_VISIBLE = new Set<ColKey>(['name', 'cidade', 'contato', 'fone', 'status', 'ativo', 'acoes']);

const PAGE_SIZES = [10, 25, 50] as const;

// ─── Sub-components ──────────────────────────────────────────────────────────

function SectionHeader({ children }: { children: React.ReactNode }) {
  return (
    <div style={{ marginBottom: 10, paddingLeft: 10, borderLeft: `2px solid ${V3.goldDim}` }}>
      <span style={{ fontSize: 11, fontWeight: 700, color: V3.hdrBg, letterSpacing: '0.07em', textTransform: 'uppercase' }}>
        {children}
      </span>
    </div>
  );
}

function CadBadge({ status }: { status: CadStatus }) {
  const c = CAD_CFG[status];
  return (
    <span style={{
      display: 'inline-block', fontSize: 10, fontWeight: 700, letterSpacing: '0.04em',
      textTransform: 'uppercase', padding: '2px 7px', borderRadius: 3,
      color: c.color, background: c.bg, border: `1px solid ${c.border}`, whiteSpace: 'nowrap',
    }}>
      {c.label}
    </span>
  );
}

function KpiCard({ label, value, sub, accent }: {
  label: string; value: string | number; sub?: string;
  accent: 'ok' | 'warning' | 'danger' | 'info' | 'none';
}) {
  const topColor = { ok: '#22c55e', warning: '#f59e0b', danger: '#ef4444', info: '#3b82f6', none: 'transparent' }[accent];
  return (
    <div style={{ background: '#fff', borderRadius: 6, border: '1px solid #e2e8e0', borderTop: `2px solid ${topColor}`, padding: '14px 18px', minWidth: 0 }}>
      <div style={{ fontSize: 10, fontWeight: 700, color: '#64748b', textTransform: 'uppercase', letterSpacing: '0.08em', marginBottom: 5 }}>{label}</div>
      <div style={{ fontSize: 22, fontWeight: 700, color: V3.hdrBg, lineHeight: 1.2 }}>{value}</div>
      {sub && <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 3 }}>{sub}</div>}
    </div>
  );
}

function SkeletonRect({ h = 14, w = '100%' }: { h?: number; w?: string }) {
  return <div style={{ height: h, width: w, background: '#e9e8e4', borderRadius: 4 }} />;
}

function LoadingView() {
  return (
    <div style={{ background: V3.paper, minHeight: '100%', padding: '24px 32px' }}>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4,1fr)', gap: 16, marginBottom: 28 }}>
        {[0, 1, 2, 3].map(i => (
          <div key={i} style={{ background: '#fff', borderRadius: 6, border: '1px solid #e2e8e0', padding: '14px 18px' }}>
            <SkeletonRect h={10} w="55%" />
            <div style={{ marginTop: 8 }}><SkeletonRect h={22} w="40%" /></div>
          </div>
        ))}
      </div>
      <SkeletonRect h={300} />
    </div>
  );
}

// ─── Main component ──────────────────────────────────────────────────────────

export default function MarinasV2() {
  const { data: marinas, isLoading, isError } = useMarinas();
  const { user } = useAuth();
  const navigate = useNavigate();

  // ── Filter state ──
  const [search,       setSearch]       = useState('');
  const [filterStatus, setFilterStatus] = useState<FilterStatus>('all');
  const [filterAtivo,  setFilterAtivo]  = useState<FilterAtivo>('all');
  const [filterUF,     setFilterUF]     = useState('all');

  // ── Sort state ──
  const [sortKey, setSortKey] = useState<SortKey | null>(null);
  const [sortDir, setSortDir] = useState<SortDir>('asc');

  // ── Pagination state ──
  const [page,     setPage]     = useState(1);
  const [pageSize, setPageSize] = useState<10 | 25 | 50>(25);

  // ── Column visibility state ──
  const [visibleCols,     setVisibleCols]     = useState<Set<ColKey>>(new Set(DEFAULT_VISIBLE));
  const [showColSelector, setShowColSelector] = useState(false);

  // ── Helpers ──
  const resetPage  = () => setPage(1);

  const toggleSort = (k: SortKey) => {
    if (sortKey === k) setSortDir(d => d === 'asc' ? 'desc' : 'asc');
    else { setSortKey(k); setSortDir('asc'); }
  };

  const toggleCol = (k: ColKey) => {
    if (COL_DEF[k].required) return;
    setVisibleCols(prev => {
      const next = new Set(prev);
      next.has(k) ? next.delete(k) : next.add(k);
      return next;
    });
  };

  const clearFilters = () => {
    setSearch(''); setFilterStatus('all'); setFilterAtivo('all'); setFilterUF('all'); setPage(1);
  };

  // ── UF list derived from data ──
  const ufList = useMemo(() => {
    if (!marinas) return [];
    const set = new Set<string>();
    marinas.forEach(m => { if (m.state) set.add(m.state); });
    return [...set].sort();
  }, [marinas]);

  // ── 1. Filter (in-memory) ──
  const filtered = useMemo(() => {
    if (!marinas) return [];
    const q = search.toLowerCase().trim();
    return marinas.filter(m => {
      const row = m as any;
      if (q) {
        const hit =
          (m.marina_name    ?? '').toLowerCase().includes(q) ||
          (m.contact_name   ?? '').toLowerCase().includes(q) ||
          (row.phone        ?? '').toLowerCase().includes(q) ||
          (row.email        ?? '').toLowerCase().includes(q) ||
          (m.city           ?? '').toLowerCase().includes(q) ||
          (m.state          ?? '').toLowerCase().includes(q) ||
          (m.address_line_1 ?? '').toLowerCase().includes(q);
        if (!hit) return false;
      }
      if (filterStatus !== 'all' && getCadStatus(m) !== filterStatus) return false;
      if (filterAtivo === 'ativo'   && !m.active) return false;
      if (filterAtivo === 'inativo' &&  m.active) return false;
      if (filterUF !== 'all' && (m.state ?? '') !== filterUF) return false;
      return true;
    });
  }, [marinas, search, filterStatus, filterAtivo, filterUF]);

  // ── 2. Sort (in-memory, after filter) ──
  const sorted = useMemo(() => {
    if (!sortKey) return filtered;
    return [...filtered].sort((a, b) => {
      const ra = a as any, rb = b as any;
      let av = '', bv = '';
      switch (sortKey) {
        case 'name':    av = a.marina_name   ?? ''; bv = b.marina_name   ?? ''; break;
        case 'cidade':  av = `${a.city ?? ''}${a.state ?? ''}`; bv = `${b.city ?? ''}${b.state ?? ''}`; break;
        case 'contato': av = a.contact_name  ?? ''; bv = b.contact_name  ?? ''; break;
        case 'fone':    av = ra.phone ?? ''; bv = rb.phone ?? ''; break;
        case 'email':   av = ra.email ?? ''; bv = rb.email ?? ''; break;
        case 'status':  av = getCadStatus(a); bv = getCadStatus(b); break;
        case 'ativo':   av = a.active ? '1' : '0'; bv = b.active ? '1' : '0'; break;
        default:        break;
      }
      const cmp = av.localeCompare(bv, 'pt-BR', { sensitivity: 'base' });
      return sortDir === 'asc' ? cmp : -cmp;
    });
  }, [filtered, sortKey, sortDir]);

  // ── 3. Paginate (after sort) ──
  const totalPages = Math.max(1, Math.ceil(sorted.length / pageSize));
  const safePage   = Math.min(page, totalPages);
  const paginated  = sorted.slice((safePage - 1) * pageSize, safePage * pageSize);
  const rangeStart = sorted.length === 0 ? 0 : (safePage - 1) * pageSize + 1;
  const rangeEnd   = Math.min(safePage * pageSize, sorted.length);

  const hasActiveFilters = !!(search || filterStatus !== 'all' || filterAtivo !== 'all' || filterUF !== 'all');

  // ── Column layout (percentage-based, sums to 100%) ──
  const visibleColList = COL_ORDER.filter(k => visibleCols.has(k));
  const totalWeight    = visibleColList.reduce((s, k) => s + COL_DEF[k].weight, 0);
  const colPct         = (k: ColKey) => `${(COL_DEF[k].weight / totalWeight * 100).toFixed(1)}%`;

  const sortInd = (sk: SortKey) =>
    sortKey === sk
      ? <span style={{ color: V3.gold, marginLeft: 3, fontSize: 10 }}>{sortDir === 'asc' ? '↑' : '↓'}</span>
      : <span style={{ color: 'rgba(255,255,255,0.22)', marginLeft: 3, fontSize: 9 }}>⇅</span>;

  // ── Loading / Error ──
  if (isLoading) return <LoadingView />;
  if (isError || !marinas) {
    return (
      <div style={{ background: V3.paper, minHeight: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <div style={{ textAlign: 'center', color: '#64748b', fontSize: 14 }}>
          <div style={{ fontSize: 28, marginBottom: 10 }}>⚠</div>
          <div>Falha ao carregar marinas. Tente recarregar a página.</div>
        </div>
      </div>
    );
  }

  // ── KPI values ──
  const total          = marinas.length;
  const ativas         = marinas.filter(m => m.active).length;
  const semContato     = marinas.filter(m => !m.contact_name && !(m as any).phone).length;
  const semLocalizacao = marinas.filter(m => !m.city).length;

  // ── Shared td style ──
  const tdBase: React.CSSProperties = {
    padding: '9px 12px',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
    verticalAlign: 'middle',
  };

  const selectStyle: React.CSSProperties = {
    height: 32, padding: '0 8px', fontSize: 12,
    border: '1px solid #d1d5db', borderRadius: 5,
    background: '#fff', color: V3.hdrBg, outline: 'none', cursor: 'pointer',
  };

  return (
    <div style={{ background: V3.paper, minHeight: '100%', fontFamily: "'Inter', system-ui, sans-serif" }}>

      {/* ── Pilot env bar ── */}
      <div style={{ background: V3.navy950, padding: '5px 32px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <span style={{ fontSize: 10, color: V3.gold, fontWeight: 700, letterSpacing: '0.13em', textTransform: 'uppercase' }}>
          Marinas V2 · Piloto Visual · Linguagem V03
        </span>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
          <button onClick={() => navigate('/marinas')}
            style={{ fontSize: 10, color: 'rgba(255,255,255,0.50)', background: 'transparent', border: 'none', cursor: 'pointer', letterSpacing: '0.04em' }}>
            ← Tela atual de Marinas
          </button>
          {user && <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.35)' }}>{user.full_name}</span>}
        </div>
      </div>

      {/* ── Content ── */}
      <div style={{ padding: '24px 32px 40px' }}>

        {/* ── Page header + action toolbar ── */}
        <div style={{ marginBottom: 6, display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', flexWrap: 'wrap', gap: 12 }}>

          {/* Title */}
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 4 }}>
              <h1 style={{ fontSize: 20, fontWeight: 700, color: V3.hdrBg, margin: 0, lineHeight: 1 }}>Marinas</h1>
              <span style={{ fontSize: 9, fontWeight: 700, letterSpacing: '0.10em', textTransform: 'uppercase', padding: '2px 6px', borderRadius: 3, color: V3.gold, background: V3.navy950, border: `1px solid ${V3.goldDim}` }}>
                Preview V2
              </span>
            </div>
            <p style={{ fontSize: 13, color: '#64748b', margin: 0 }}>
              Cadastro operacional de locais de atendimento náutico · rota paralela · sem alteração no cadastro atual
            </p>
          </div>

          {/* Action buttons */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexShrink: 0 }}>
            <button
              title="Criar marina na tela atual"
              onClick={() => navigate('/marinas')}
              style={{
                height: 34, padding: '0 16px', fontSize: 13, fontWeight: 600,
                color: '#fff', background: V3.hdrBg, border: `1px solid ${V3.hdrBg}`,
                borderRadius: 5, cursor: 'pointer', whiteSpace: 'nowrap',
              }}
              onMouseEnter={e => { e.currentTarget.style.background = V3.navy900; }}
              onMouseLeave={e => { e.currentTarget.style.background = V3.hdrBg; }}
            >
              + Nova marina
            </button>
            {/* CSV export exists in MarinaList — navigate there */}
            <button
              title="Exportar CSV na tela atual de Marinas"
              onClick={() => navigate('/marinas')}
              style={{
                height: 34, padding: '0 14px', fontSize: 13, fontWeight: 500,
                color: '#475569', background: '#fff', border: '1px solid #d1d5db',
                borderRadius: 5, cursor: 'pointer', whiteSpace: 'nowrap',
              }}
              onMouseEnter={e => { e.currentTarget.style.background = '#f1f5f9'; }}
              onMouseLeave={e => { e.currentTarget.style.background = '#fff'; }}
            >
              ↓ Exportar CSV
            </button>
            {/* No import flow in MarinaList — disabled */}
            <button
              title="Importação não disponível nesta fase"
              disabled
              style={{
                height: 34, padding: '0 14px', fontSize: 13, fontWeight: 500,
                color: '#c0c9d6', background: '#f8fafc', border: '1px solid #e2e8f0',
                borderRadius: 5, cursor: 'not-allowed', whiteSpace: 'nowrap',
              }}
            >
              ↑ Importar
            </button>
          </div>
        </div>

        {/* Phase note */}
        <div style={{ marginBottom: 20, textAlign: 'right', fontSize: 11, color: '#94a3b8', fontStyle: 'italic' }}>
          Criação, edição, importação e exportação permanecem na tela atual nesta fase.
        </div>

        {/* ── KPI row ── */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4,1fr)', gap: 16, marginBottom: 24 }}>
          <KpiCard label="Total de marinas" value={total}          accent="none" />
          <KpiCard label="Ativas"           value={ativas}         sub={`${total - ativas} inativas`} accent="ok" />
          <KpiCard label="Sem contato"      value={semContato}     accent={semContato > 0 ? 'warning' : 'none'} />
          <KpiCard label="Sem localização"  value={semLocalizacao} accent={semLocalizacao > 0 ? 'info' : 'none'} />
        </div>

        {/* ── Filter + controls row ── */}
        <div style={{ marginBottom: 14, display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'center' }}>

          {/* Search */}
          <div style={{ position: 'relative', flex: '1 1 220px', maxWidth: 360 }}>
            <span style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', fontSize: 13, color: '#94a3b8', pointerEvents: 'none' }}>⌕</span>
            <input
              value={search}
              onChange={e => { setSearch(e.target.value); resetPage(); }}
              placeholder="Nome, cidade, UF, contato, telefone…"
              style={{ width: '100%', height: 32, paddingLeft: 30, paddingRight: 10, fontSize: 13, border: '1px solid #d1d5db', borderRadius: 5, background: '#fff', color: V3.hdrBg, outline: 'none', boxSizing: 'border-box' }}
            />
          </div>

          {/* Status */}
          <select value={filterStatus} onChange={e => { setFilterStatus(e.target.value as FilterStatus); resetPage(); }} style={selectStyle}>
            <option value="all">Status: todos</option>
            <option value="completo">Completo</option>
            <option value="sem-contato">Sem contato</option>
            <option value="sem-localizacao">Sem localização</option>
            <option value="revisar">Revisar</option>
          </select>

          {/* Ativo */}
          <select value={filterAtivo} onChange={e => { setFilterAtivo(e.target.value as FilterAtivo); resetPage(); }} style={selectStyle}>
            <option value="all">Ativo: todos</option>
            <option value="ativo">Ativas</option>
            <option value="inativo">Inativas</option>
          </select>

          {/* UF */}
          {ufList.length > 0 && (
            <select value={filterUF} onChange={e => { setFilterUF(e.target.value); resetPage(); }} style={selectStyle}>
              <option value="all">UF: todas</option>
              {ufList.map(uf => <option key={uf} value={uf}>{uf}</option>)}
            </select>
          )}

          {/* Clear */}
          {hasActiveFilters && (
            <button onClick={clearFilters} style={{ height: 32, padding: '0 12px', fontSize: 12, fontWeight: 600, color: '#64748b', background: '#f1f5f9', border: '1px solid #e2e8f0', borderRadius: 5, cursor: 'pointer' }}>
              Limpar filtros ×
            </button>
          )}

          {/* Spacer */}
          <div style={{ flex: 1, minWidth: 0 }} />

          {/* Column selector */}
          <div style={{ position: 'relative' }}>
            <button
              onClick={() => setShowColSelector(v => !v)}
              style={{
                height: 32, padding: '0 12px', fontSize: 12, fontWeight: 500,
                color: showColSelector ? V3.hdrBg : '#475569',
                background: showColSelector ? '#e8edf2' : '#fff',
                border: `1px solid ${showColSelector ? '#94a3b8' : '#d1d5db'}`,
                borderRadius: 5, cursor: 'pointer', whiteSpace: 'nowrap',
              }}
            >
              Colunas ▾
            </button>
            {showColSelector && (
              <>
                <div style={{ position: 'fixed', inset: 0, zIndex: 40 }} onClick={() => setShowColSelector(false)} />
                <div style={{ position: 'absolute', top: 'calc(100% + 4px)', right: 0, zIndex: 50, background: '#fff', border: '1px solid #e2e8f0', borderRadius: 6, padding: '6px 0', minWidth: 196, boxShadow: '0 4px 16px rgba(0,0,0,0.10)' }}>
                  <div style={{ padding: '4px 14px 8px', fontSize: 10, fontWeight: 700, color: '#94a3b8', textTransform: 'uppercase', letterSpacing: '0.08em', borderBottom: '1px solid #f0efeb', marginBottom: 4 }}>
                    Colunas visíveis
                  </div>
                  {COL_ORDER.filter(k => !COL_DEF[k].required).map(k => (
                    <label key={k} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '5px 14px', cursor: 'pointer', fontSize: 13, color: V3.hdrBg }}>
                      <input type="checkbox" checked={visibleCols.has(k)} onChange={() => toggleCol(k)} style={{ cursor: 'pointer', accentColor: V3.hdrBg }} />
                      {COL_DEF[k].label}
                    </label>
                  ))}
                  <div style={{ padding: '8px 14px 2px', fontSize: 10, color: '#94a3b8', borderTop: '1px solid #f0efeb', marginTop: 4 }}>
                    Marina e Ações são obrigatórias.
                  </div>
                </div>
              </>
            )}
          </div>

          {/* Range count */}
          <span style={{ fontSize: 12, color: '#94a3b8', whiteSpace: 'nowrap' }}>
            {sorted.length === 0
              ? 'Nenhum resultado'
              : `${rangeStart}–${rangeEnd} de ${sorted.length} marina${sorted.length !== 1 ? 's' : ''}`
            }
          </span>
        </div>

        {/* ── Table ── */}
        <SectionHeader>Cadastro de Marinas e Locais de Atendimento</SectionHeader>
        <div style={{ background: '#fff', borderRadius: 6, border: '1px solid #e2e8e0', overflow: 'hidden' }}>
          {sorted.length === 0 ? (
            <div style={{ padding: '48px 20px', textAlign: 'center' }}>
              <div style={{ fontSize: 13, color: '#94a3b8', marginBottom: 12 }}>
                {hasActiveFilters ? 'Nenhuma marina encontrada com os filtros atuais.' : 'Nenhuma marina cadastrada.'}
              </div>
              {hasActiveFilters && (
                <button onClick={clearFilters} style={{ fontSize: 12, fontWeight: 600, color: V3.hdrBg, background: '#f1f5f9', border: '1px solid #e2e8f0', borderRadius: 5, padding: '6px 14px', cursor: 'pointer' }}>
                  Limpar filtros
                </button>
              )}
            </div>
          ) : (
            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', minWidth: 560, tableLayout: 'fixed', borderCollapse: 'collapse', fontSize: 13 }}>
                <colgroup>
                  {visibleColList.map(k => <col key={k} style={{ width: colPct(k) }} />)}
                </colgroup>
                <thead>
                  <tr style={{ background: V3.navy900 }}>
                    {visibleColList.map((k, i) => {
                      const def = COL_DEF[k];
                      return (
                        <th
                          key={k}
                          onClick={() => def.sortKey && toggleSort(def.sortKey)}
                          title={def.sortKey ? `Ordenar por ${def.label}` : undefined}
                          style={{
                            padding: '9px 12px',
                            textAlign: def.align,
                            fontSize: 10, fontWeight: 600,
                            letterSpacing: '0.08em', textTransform: 'uppercase',
                            color: 'rgba(255,255,255,0.55)',
                            borderLeft: i > 0 ? '1px solid rgba(255,255,255,0.08)' : 'none',
                            overflow: 'hidden', whiteSpace: 'nowrap',
                            cursor: def.sortKey ? 'pointer' : 'default',
                            userSelect: 'none',
                          }}
                        >
                          {def.label}
                          {def.sortKey && sortInd(def.sortKey)}
                        </th>
                      );
                    })}
                  </tr>
                </thead>
                <tbody>
                  {paginated.map((m, idx) => {
                    const row = m as any;
                    const cad = getCadStatus(m);
                    const rowBorder = idx < paginated.length - 1 ? '1px solid #f0efeb' : 'none';
                    return (
                      <tr
                        key={m.id}
                        style={{
                          borderBottom: rowBorder,
                          borderLeft: cad === 'revisar' ? '3px solid #f87171' : '3px solid transparent',
                        }}
                        onMouseEnter={e => { e.currentTarget.style.background = '#f9f8f5'; }}
                        onMouseLeave={e => { e.currentTarget.style.background = ''; }}
                      >
                        {visibleColList.map((k, ci): React.ReactNode => {
                          const base: React.CSSProperties = {
                            ...tdBase,
                            borderLeft: ci === 0 ? 'none' : '1px solid #f0efeb',
                            textAlign: COL_DEF[k].align,
                          };
                          switch (k) {
                            case 'name':
                              return (
                                <td key={k} style={{ ...base, borderLeft: 'none' }}>
                                  <div style={{ fontWeight: 600, color: V3.hdrBg, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                                    {m.marina_name}
                                  </div>
                                </td>
                              );
                            case 'cidade':
                              return (
                                <td key={k} style={{ ...base, color: '#475569' }}>
                                  {m.city
                                    ? <>{m.city}{m.state ? <span style={{ color: '#94a3b8' }}> · {m.state}</span> : null}</>
                                    : <span style={{ color: '#cbd5e1' }}>—</span>
                                  }
                                </td>
                              );
                            case 'endereco':
                              return (
                                <td key={k} style={{ ...base, color: '#475569', fontSize: 12 }}>
                                  {m.address_line_1 || <span style={{ color: '#cbd5e1' }}>—</span>}
                                </td>
                              );
                            case 'contato':
                              return (
                                <td key={k} style={{ ...base, color: '#475569' }}>
                                  {m.contact_name || <span style={{ color: '#cbd5e1' }}>—</span>}
                                </td>
                              );
                            case 'fone':
                              return (
                                <td key={k} style={{ ...base, color: '#475569' }}>
                                  {row.phone || <span style={{ color: '#cbd5e1' }}>—</span>}
                                </td>
                              );
                            case 'email':
                              return (
                                <td key={k} style={{ ...base, color: '#475569', fontSize: 12 }}>
                                  {row.email || <span style={{ color: '#cbd5e1' }}>—</span>}
                                </td>
                              );
                            case 'status':
                              return (
                                <td key={k} style={base}>
                                  <CadBadge status={cad} />
                                </td>
                              );
                            case 'ativo':
                              return (
                                <td key={k} style={base}>
                                  <span style={{
                                    display: 'inline-block', fontSize: 10, fontWeight: 700,
                                    letterSpacing: '0.04em', textTransform: 'uppercase',
                                    padding: '2px 7px', borderRadius: 3,
                                    color:      m.active ? '#15803d' : '#94a3b8',
                                    background: m.active ? '#dcfce7' : '#f1f5f9',
                                    border:     `1px solid ${m.active ? '#86efac' : '#e2e8f0'}`,
                                  }}>
                                    {m.active ? 'Ativo' : 'Inativo'}
                                  </span>
                                </td>
                              );
                            case 'acoes':
                              return (
                                <td key={k} style={base}>
                                  <button
                                    title="Editar cadastro na tela atual de Marinas"
                                    onClick={() => navigate('/marinas')}
                                    style={{
                                      fontSize: 11, fontWeight: 600, color: V3.hdrBg,
                                      background: '#f1f5f9', border: '1px solid #e2e8f0',
                                      borderRadius: 4, padding: '3px 10px', cursor: 'pointer', whiteSpace: 'nowrap',
                                    }}
                                    onMouseEnter={e => { e.currentTarget.style.background = '#e2e8f0'; }}
                                    onMouseLeave={e => { e.currentTarget.style.background = '#f1f5f9'; }}
                                  >
                                    Editar
                                  </button>
                                </td>
                              );
                            default:
                              return null;
                          }
                        })}
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>

        {/* ── Pagination ── */}
        {sorted.length > 0 && (
          <div style={{ marginTop: 14, display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: 10 }}>

            {/* Page size */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <span style={{ fontSize: 12, color: '#64748b' }}>Linhas por página:</span>
              {PAGE_SIZES.map(sz => (
                <button
                  key={sz}
                  onClick={() => { setPageSize(sz); setPage(1); }}
                  style={{
                    fontSize: 12, fontWeight: pageSize === sz ? 700 : 400,
                    color:      pageSize === sz ? V3.hdrBg : '#64748b',
                    background: pageSize === sz ? '#e2e8f0' : 'transparent',
                    border: '1px solid #e2e8f0', borderRadius: 4,
                    padding: '2px 9px', cursor: 'pointer',
                  }}
                >
                  {sz}
                </button>
              ))}
            </div>

            {/* Page info */}
            <span style={{ fontSize: 12, color: '#64748b' }}>
              Página {safePage} de {totalPages}
            </span>

            {/* Prev / Next */}
            <div style={{ display: 'flex', gap: 6 }}>
              <button
                onClick={() => setPage(p => Math.max(1, p - 1))}
                disabled={safePage === 1}
                style={{
                  fontSize: 12, fontWeight: 600,
                  color:      safePage === 1 ? '#cbd5e1' : V3.hdrBg,
                  background: '#fff', border: '1px solid #e2e8f0', borderRadius: 5,
                  padding: '4px 14px', cursor: safePage === 1 ? 'default' : 'pointer',
                }}
              >
                ← Anterior
              </button>
              <button
                onClick={() => setPage(p => Math.min(totalPages, p + 1))}
                disabled={safePage === totalPages}
                style={{
                  fontSize: 12, fontWeight: 600,
                  color:      safePage === totalPages ? '#cbd5e1' : V3.hdrBg,
                  background: '#fff', border: '1px solid #e2e8f0', borderRadius: 5,
                  padding: '4px 14px', cursor: safePage === totalPages ? 'default' : 'pointer',
                }}
              >
                Próxima →
              </button>
            </div>
          </div>
        )}

        {/* ── Footer ── */}
        <div style={{ marginTop: 20, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <span style={{ fontSize: 11, color: '#94a3b8', fontStyle: 'italic' }}>
            Edição de cadastro permanece na tela atual nesta fase.
          </span>
          <button
            onClick={() => navigate('/marinas')}
            style={{ fontSize: 11, color: V3.gold, background: 'transparent', border: 'none', cursor: 'pointer', fontWeight: 700, letterSpacing: '0.04em', padding: 0 }}
          >
            Gerenciar cadastro na tela atual →
          </button>
        </div>

      </div>
    </div>
  );
}
