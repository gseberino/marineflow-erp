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

// ─── Status cadastral (derived, frontend-only, nothing saved) ────────────────

type CadStatus = 'completo' | 'sem-contato' | 'sem-localizacao' | 'revisar';

function getCadStatus(m: Marina): CadStatus {
  const hasContact  = !!(m.contact_name || (m as any).phone);
  const hasLocation = !!(m.city);
  if (hasContact && hasLocation)  return 'completo';
  if (!hasContact && !hasLocation) return 'revisar';
  if (!hasContact)                return 'sem-contato';
  return 'sem-localizacao';
}

const CAD_STATUS_CFG: Record<CadStatus, { label: string; color: string; bg: string; border: string }> = {
  'completo':        { label: 'Completo',       color: '#15803d', bg: '#dcfce7', border: '#86efac' },
  'sem-contato':     { label: 'Sem contato',    color: '#b45309', bg: '#fef3c7', border: '#fcd34d' },
  'sem-localizacao': { label: 'Sem localização',color: '#0369a1', bg: '#e0f2fe', border: '#7dd3fc' },
  'revisar':         { label: 'Revisar',         color: '#b91c1c', bg: '#fee2e2', border: '#fca5a5' },
};

// ─── Sub-components ──────────────────────────────────────────────────────────

function SectionHeader({ children }: { children: React.ReactNode }) {
  return (
    <div style={{ marginBottom: 12, paddingLeft: 10, borderLeft: `2px solid ${V3.goldDim}` }}>
      <span style={{ fontSize: 11, fontWeight: 700, color: V3.hdrBg, letterSpacing: '0.07em', textTransform: 'uppercase' }}>
        {children}
      </span>
    </div>
  );
}

function CadBadge({ status }: { status: CadStatus }) {
  const c = CAD_STATUS_CFG[status];
  return (
    <span style={{
      display: 'inline-block',
      fontSize: 10,
      fontWeight: 700,
      letterSpacing: '0.04em',
      textTransform: 'uppercase',
      padding: '2px 7px',
      borderRadius: 3,
      color: c.color,
      background: c.bg,
      border: `1px solid ${c.border}`,
      whiteSpace: 'nowrap',
    }}>
      {c.label}
    </span>
  );
}

type KpiAccent = 'ok' | 'warning' | 'danger' | 'info' | 'none';

function KpiCard({ label, value, sub, accent }: {
  label: string;
  value: string | number;
  sub?: string;
  accent: KpiAccent;
}) {
  const topColor: Record<KpiAccent, string> = {
    ok:      '#22c55e',
    warning: '#f59e0b',
    danger:  '#ef4444',
    info:    '#3b82f6',
    none:    'transparent',
  };
  return (
    <div style={{
      background: '#fff',
      borderRadius: 6,
      border: '1px solid #e2e8e0',
      borderTop: `2px solid ${topColor[accent]}`,
      padding: '14px 18px',
      minWidth: 0,
    }}>
      <div style={{ fontSize: 10, fontWeight: 700, color: '#64748b', textTransform: 'uppercase', letterSpacing: '0.08em', marginBottom: 5 }}>
        {label}
      </div>
      <div style={{ fontSize: 22, fontWeight: 700, color: V3.hdrBg, lineHeight: 1.2 }}>
        {value}
      </div>
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
        {[0,1,2,3].map(i => (
          <div key={i} style={{ background: '#fff', borderRadius: 6, border: '1px solid #e2e8e0', padding: '14px 18px' }}>
            <SkeletonRect h={10} w="55%" />
            <div style={{ marginTop: 8 }}><SkeletonRect h={22} w="40%" /></div>
          </div>
        ))}
      </div>
      <SkeletonRect h={280} />
    </div>
  );
}

// ─── Main component ──────────────────────────────────────────────────────────

export default function MarinasV2() {
  const { data: marinas, isLoading, isError } = useMarinas();
  const { user } = useAuth();
  const navigate = useNavigate();
  const [search, setSearch] = useState('');

  const filtered = useMemo(() => {
    if (!marinas) return [];
    const q = search.toLowerCase().trim();
    if (!q) return marinas;
    return marinas.filter(m =>
      (m.marina_name ?? '').toLowerCase().includes(q) ||
      (m.city ?? '').toLowerCase().includes(q) ||
      (m.state ?? '').toLowerCase().includes(q)
    );
  }, [marinas, search]);

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

  // KPI derivations — frontend only
  const total         = marinas.length;
  const ativas        = marinas.filter(m => m.active).length;
  const semContato    = marinas.filter(m => !m.contact_name && !(m as any).phone).length;
  const semLocalizacao = marinas.filter(m => !m.city).length;

  return (
    <div style={{ background: V3.paper, minHeight: '100%', fontFamily: "'Inter', system-ui, sans-serif" }}>

      {/* Pilot env bar */}
      <div style={{
        background: V3.navy950,
        padding: '5px 32px',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
      }}>
        <span style={{ fontSize: 10, color: V3.gold, fontWeight: 700, letterSpacing: '0.13em', textTransform: 'uppercase' }}>
          Marinas V2 · Piloto Visual · Linguagem V03
        </span>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
          <button
            onClick={() => navigate('/marinas')}
            style={{ fontSize: 10, color: 'rgba(255,255,255,0.50)', background: 'transparent', border: 'none', cursor: 'pointer', letterSpacing: '0.04em' }}
          >
            ← Tela atual de Marinas
          </button>
          {user && <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.35)' }}>{user.full_name}</span>}
        </div>
      </div>

      {/* Content */}
      <div style={{ padding: '24px 32px 40px', maxWidth: 1400 }}>

        {/* Page header */}
        <div style={{ marginBottom: 24 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 4 }}>
            <h1 style={{ fontSize: 20, fontWeight: 700, color: V3.hdrBg, margin: 0, lineHeight: 1 }}>
              Marinas
            </h1>
            <span style={{
              fontSize: 9,
              fontWeight: 700,
              letterSpacing: '0.10em',
              textTransform: 'uppercase',
              padding: '2px 6px',
              borderRadius: 3,
              color: V3.gold,
              background: V3.navy950,
              border: `1px solid ${V3.goldDim}`,
            }}>
              Preview V2
            </span>
          </div>
          <p style={{ fontSize: 13, color: '#64748b', margin: 0 }}>
            Cadastro operacional de locais de atendimento náutico · rota paralela · sem alteração no cadastro atual
          </p>
        </div>

        {/* KPI row */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4,1fr)', gap: 16, marginBottom: 28 }}>
          <KpiCard label="Total de marinas"     value={total}         accent="none" />
          <KpiCard label="Ativas"               value={ativas}        sub={`${total - ativas} inativas`}   accent="ok" />
          <KpiCard label="Sem contato"          value={semContato}    accent={semContato > 0 ? 'warning' : 'none'} />
          <KpiCard label="Sem localização"      value={semLocalizacao} accent={semLocalizacao > 0 ? 'info' : 'none'} />
        </div>

        {/* Search */}
        <div style={{ marginBottom: 16, display: 'flex', alignItems: 'center', gap: 12 }}>
          <div style={{ position: 'relative', flex: 1, maxWidth: 380 }}>
            <span style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', fontSize: 13, color: '#94a3b8', pointerEvents: 'none' }}>
              ⌕
            </span>
            <input
              value={search}
              onChange={e => setSearch(e.target.value)}
              placeholder="Buscar por nome, cidade ou UF…"
              style={{
                width: '100%',
                height: 32,
                paddingLeft: 30,
                paddingRight: 12,
                fontSize: 13,
                border: '1px solid #d1d5db',
                borderRadius: 5,
                background: '#fff',
                color: V3.hdrBg,
                outline: 'none',
                boxSizing: 'border-box',
              }}
            />
          </div>
          <span style={{ fontSize: 12, color: '#94a3b8' }}>
            {filtered.length} de {total} marina{total !== 1 ? 's' : ''}
          </span>
        </div>

        {/* Table */}
        <SectionHeader>Cadastro de Marinas e Locais de Atendimento</SectionHeader>
        <div style={{ background: '#fff', borderRadius: 6, border: '1px solid #e2e8e0', overflow: 'hidden' }}>
          {filtered.length === 0 ? (
            <div style={{ padding: '40px 20px', textAlign: 'center', color: '#94a3b8', fontSize: 13 }}>
              {search ? 'Nenhuma marina encontrada para esta busca.' : 'Nenhuma marina cadastrada.'}
            </div>
          ) : (
            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13, minWidth: 720 }}>
                <thead>
                  <tr style={{ background: V3.navy900 }}>
                    {['Marina', 'Cidade · UF', 'Contato', 'Telefone', 'Status cadastral', 'Ativo', 'Ações'].map(h => (
                      <th key={h} style={{
                        padding: '9px 14px',
                        textAlign: 'left',
                        fontSize: 10,
                        fontWeight: 600,
                        letterSpacing: '0.08em',
                        textTransform: 'uppercase',
                        color: 'rgba(255,255,255,0.50)',
                        whiteSpace: 'nowrap',
                      }}>
                        {h}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {filtered.map((m, idx) => {
                    const row    = m as any;
                    const cad    = getCadStatus(m);
                    const isCritical = cad === 'revisar';
                    return (
                      <tr
                        key={m.id}
                        style={{
                          borderBottom: idx < filtered.length - 1 ? '1px solid #f0efeb' : 'none',
                          borderLeft: isCritical
                            ? '3px solid var(--mf-danger-400, #f87171)'
                            : '3px solid transparent',
                        }}
                        onMouseEnter={e => { e.currentTarget.style.background = '#f9f8f5'; }}
                        onMouseLeave={e => { e.currentTarget.style.background = ''; }}
                      >
                        {/* Nome */}
                        <td style={{ padding: '10px 14px' }}>
                          <div style={{ fontWeight: 600, color: V3.hdrBg }}>{m.marina_name}</div>
                          {m.address_line_1 && (
                            <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 2 }}>{m.address_line_1}</div>
                          )}
                        </td>

                        {/* Cidade · UF */}
                        <td style={{ padding: '10px 14px', color: '#475569', whiteSpace: 'nowrap' }}>
                          {m.city
                            ? <>{m.city}{m.state ? <span style={{ color: '#94a3b8' }}> · {m.state}</span> : null}</>
                            : <span style={{ color: '#cbd5e1' }}>—</span>
                          }
                        </td>

                        {/* Contato */}
                        <td style={{ padding: '10px 14px', color: '#475569' }}>
                          {m.contact_name
                            ? m.contact_name
                            : <span style={{ color: '#cbd5e1' }}>—</span>
                          }
                        </td>

                        {/* Telefone */}
                        <td style={{ padding: '10px 14px', color: '#475569', whiteSpace: 'nowrap' }}>
                          {row.phone
                            ? row.phone
                            : <span style={{ color: '#cbd5e1' }}>—</span>
                          }
                        </td>

                        {/* Status cadastral */}
                        <td style={{ padding: '10px 14px' }}>
                          <CadBadge status={cad} />
                        </td>

                        {/* Ativo */}
                        <td style={{ padding: '10px 14px' }}>
                          <span style={{
                            display: 'inline-block',
                            fontSize: 10,
                            fontWeight: 700,
                            letterSpacing: '0.04em',
                            textTransform: 'uppercase',
                            padding: '2px 7px',
                            borderRadius: 3,
                            color:  m.active ? '#15803d' : '#94a3b8',
                            background: m.active ? '#dcfce7' : '#f1f5f9',
                            border: `1px solid ${m.active ? '#86efac' : '#e2e8f0'}`,
                          }}>
                            {m.active ? 'Ativo' : 'Inativo'}
                          </span>
                        </td>

                        {/* Ações */}
                        <td style={{ padding: '10px 14px' }}>
                          <button
                            title="Editar cadastro na tela atual de Marinas"
                            onClick={() => navigate('/marinas')}
                            style={{
                              fontSize: 11,
                              fontWeight: 600,
                              color: V3.hdrBg,
                              background: '#f1f5f9',
                              border: '1px solid #e2e8f0',
                              borderRadius: 4,
                              padding: '3px 10px',
                              cursor: 'pointer',
                              letterSpacing: '0.02em',
                              whiteSpace: 'nowrap',
                            }}
                            onMouseEnter={e => { e.currentTarget.style.background = '#e2e8f0'; }}
                            onMouseLeave={e => { e.currentTarget.style.background = '#f1f5f9'; }}
                          >
                            Editar
                          </button>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>

        {/* Footer note */}
        <div style={{ marginTop: 16, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <span style={{ fontSize: 11, color: '#94a3b8', fontStyle: 'italic' }}>
            Edição de cadastro permanece na tela atual nesta fase.
          </span>
          <button
            onClick={() => navigate('/marinas')}
            style={{
              fontSize: 11,
              color: V3.gold,
              background: 'transparent',
              border: 'none',
              cursor: 'pointer',
              fontWeight: 700,
              letterSpacing: '0.04em',
              padding: 0,
            }}
          >
            Gerenciar cadastro na tela atual →
          </button>
        </div>

      </div>
    </div>
  );
}
