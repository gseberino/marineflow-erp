import '@/styles/marineflow-tokens.css';
import { useDashboardData } from '@/hooks/use-dashboard';
import { useAuth } from '@/hooks/use-auth';
import { useNavigate } from 'react-router-dom';

const V3 = {
  hdrBg:   '#020E1A',
  paper:   '#F7F6F2',
  gold:    '#C8A24B',
  goldDim: 'rgba(200,162,75,0.45)',
  navy900: '#0A1929',
  navy950: '#071420',
} as const;

const STATUS: Record<string, { label: string; color: string; bg: string; border: string }> = {
  draft:           { label: 'Rascunho',       color: '#64748b', bg: '#f1f5f9', border: '#cbd5e1' },
  scheduled:       { label: 'Agendado',        color: '#0369a1', bg: '#e0f2fe', border: '#7dd3fc' },
  open:            { label: 'Aberta',          color: '#1d4ed8', bg: '#dbeafe', border: '#93c5fd' },
  in_progress:     { label: 'Em andamento',    color: '#b45309', bg: '#fef3c7', border: '#fcd34d' },
  awaiting_parts:  { label: 'Aguard. Peças',   color: '#b91c1c', bg: '#fee2e2', border: '#fca5a5' },
  awaiting_client: { label: 'Aguard. Cliente', color: '#475569', bg: '#f1f5f9', border: '#cbd5e1' },
  approved:        { label: 'Aprovada',        color: '#15803d', bg: '#dcfce7', border: '#86efac' },
  completed:       { label: 'Concluída',       color: '#15803d', bg: '#dcfce7', border: '#86efac' },
  invoiced:        { label: 'Faturada',        color: '#6d28d9', bg: '#ede9fe', border: '#c4b5fd' },
  cancelled:       { label: 'Cancelada',       color: '#94a3b8', bg: '#f1f5f9', border: '#e2e8f0' },
};

const fmtBRL = (v: number) =>
  v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

const fmtDate = (d: string | null | undefined) => {
  if (!d) return '—';
  return new Date(d).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
};

// ─── Sub-components ─────────────────────────────────────────────────────────

function SectionHeader({ children }: { children: React.ReactNode }) {
  return (
    <div style={{
      display: 'flex',
      alignItems: 'center',
      marginBottom: 12,
      paddingLeft: 10,
      borderLeft: `2px solid ${V3.goldDim}`,
    }}>
      <span style={{
        fontSize: 11,
        fontWeight: 700,
        color: V3.hdrBg,
        letterSpacing: '0.07em',
        textTransform: 'uppercase',
      }}>
        {children}
      </span>
    </div>
  );
}

function StatusBadge({ status }: { status: string }) {
  const c = STATUS[status] ?? { label: status, color: '#64748b', bg: '#f1f5f9', border: '#e2e8f0' };
  return (
    <span style={{
      display: 'inline-block',
      fontSize: 10,
      fontWeight: 700,
      letterSpacing: '0.05em',
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

type KpiAccent = 'danger' | 'warning' | 'info' | 'ok' | 'none';

function KpiCard({ label, value, sub, accent }: {
  label: string;
  value: string;
  sub?: string;
  accent: KpiAccent;
}) {
  const borderColor: Record<KpiAccent, string> = {
    danger:  '#ef4444',
    warning: '#f59e0b',
    info:    '#3b82f6',
    ok:      '#22c55e',
    none:    'transparent',
  };
  return (
    <div style={{
      background: '#fff',
      borderRadius: 6,
      border: '1px solid #e2e8e0',
      borderTop: `2px solid ${borderColor[accent]}`,
      padding: '16px 20px',
      minWidth: 0,
    }}>
      <div style={{
        fontSize: 10,
        fontWeight: 700,
        color: '#64748b',
        textTransform: 'uppercase',
        letterSpacing: '0.08em',
        marginBottom: 6,
      }}>
        {label}
      </div>
      <div style={{ fontSize: 21, fontWeight: 700, color: V3.hdrBg, lineHeight: 1.2 }}>
        {value}
      </div>
      {sub && (
        <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 4 }}>{sub}</div>
      )}
    </div>
  );
}

function SkeletonRect({ h = 16, w = '100%' }: { h?: number; w?: string }) {
  return <div style={{ height: h, width: w, background: '#e9e8e4', borderRadius: 4 }} />;
}

function LoadingView() {
  return (
    <div style={{ background: V3.paper, minHeight: '100%', padding: '24px 32px' }}>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4,1fr)', gap: 16, marginBottom: 28 }}>
        {[0, 1, 2, 3].map(i => (
          <div key={i} style={{ background: '#fff', borderRadius: 6, border: '1px solid #e2e8e0', padding: '16px 20px' }}>
            <SkeletonRect h={10} w="50%" />
            <div style={{ marginTop: 10 }}><SkeletonRect h={22} w="65%" /></div>
          </div>
        ))}
      </div>
      <SkeletonRect h={240} />
    </div>
  );
}

// ─── Main component ──────────────────────────────────────────────────────────

export default function DashboardV2() {
  const { data, isLoading, isError } = useDashboardData();
  const { user } = useAuth();
  const navigate = useNavigate();

  if (isLoading) return <LoadingView />;

  if (isError || !data) {
    return (
      <div style={{
        background: V3.paper,
        minHeight: '100%',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
      }}>
        <div style={{ textAlign: 'center', color: '#64748b', fontSize: 14 }}>
          <div style={{ fontSize: 28, marginBottom: 12 }}>⚠</div>
          <div>Falha ao carregar dados. Tente recarregar a página.</div>
        </div>
      </div>
    );
  }

  const {
    totalReceivable,
    totalPayable,
    collectedThisMonth,
    revenueGrowth,
    overdueReceivables,
    openOrders,
    openOrdersCount,
    completedThisMonth,
    completedThisMonthValue,
    upcomingOrders,
    lowStock,
  } = data;

  const hasOverdue = overdueReceivables > 0;

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
        <span style={{
          fontSize: 10,
          color: V3.gold,
          fontWeight: 700,
          letterSpacing: '0.13em',
          textTransform: 'uppercase',
        }}>
          Dashboard V2 · Piloto Visual · Linguagem V03
        </span>
        {user && (
          <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.40)' }}>
            {user.full_name}
          </span>
        )}
      </div>

      {/* Content */}
      <div style={{ padding: '24px 32px 40px', maxWidth: 1400 }}>

        {/* KPI row */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4,1fr)', gap: 16, marginBottom: 28 }}>
          <KpiCard
            label="A receber"
            value={fmtBRL(totalReceivable)}
            sub={hasOverdue ? `Vencido: ${fmtBRL(overdueReceivables)}` : undefined}
            accent={hasOverdue ? 'danger' : 'info'}
          />
          <KpiCard
            label="A pagar"
            value={fmtBRL(totalPayable)}
            accent="warning"
          />
          <KpiCard
            label="Recebido este mês"
            value={fmtBRL(collectedThisMonth)}
            sub={revenueGrowth !== null
              ? `${revenueGrowth >= 0 ? '+' : ''}${revenueGrowth}% vs. mês anterior`
              : undefined}
            accent={revenueGrowth !== null ? (revenueGrowth >= 0 ? 'ok' : 'warning') : 'none'}
          />
          <KpiCard
            label="OS concluídas (mês)"
            value={String(completedThisMonth)}
            sub={completedThisMonthValue > 0 ? fmtBRL(completedThisMonthValue) : undefined}
            accent="none"
          />
        </div>

        {/* Main grid: OS table (3fr) + right panel (2fr) */}
        <div style={{ display: 'grid', gridTemplateColumns: '3fr 2fr', gap: 20, marginBottom: 24 }}>

          {/* ── OS Fila operacional ── */}
          <div>
            <SectionHeader>Fila Operacional — Ordens de Serviço</SectionHeader>
            <div style={{ background: '#fff', borderRadius: 6, border: '1px solid #e2e8e0', overflow: 'hidden' }}>
              {openOrders.length === 0 ? (
                <div style={{ padding: '32px 20px', textAlign: 'center', color: '#94a3b8', fontSize: 13 }}>
                  Nenhuma ordem em aberto.
                </div>
              ) : (
                <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
                  <thead>
                    <tr style={{ background: V3.navy900 }}>
                      {['OS', 'Cliente · Embarcação', 'Status', 'Valor', 'Data'].map(h => (
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
                    {openOrders.map((so, idx) => {
                      const row = so as any;
                      const isCritical = so.status === 'awaiting_parts' || so.status === 'awaiting_client';
                      const client  = row.clients?.full_name_or_company_name ?? '—';
                      const vessel  = row.vessels?.boat_name ?? '—';
                      return (
                        <tr
                          key={so.id}
                          title={so.id ? 'Abrir OS' : undefined}
                          onClick={() => { if (so.id) navigate(`/service-orders/${so.id}`); }}
                          style={{
                            borderBottom: idx < openOrders.length - 1 ? '1px solid #f0efeb' : 'none',
                            borderLeft: isCritical
                              ? '3px solid var(--mf-danger-400, #f87171)'
                              : '3px solid transparent',
                            cursor: so.id ? 'pointer' : 'default',
                          }}
                          onMouseEnter={e => { if (so.id) e.currentTarget.style.background = '#f9f8f5'; }}
                          onMouseLeave={e => { e.currentTarget.style.background = ''; }}
                        >
                          <td style={{ padding: '10px 14px', fontWeight: 600, color: V3.hdrBg, whiteSpace: 'nowrap' }}>
                            #{so.service_order_number}
                          </td>
                          <td style={{ padding: '10px 14px', color: '#334155' }}>
                            <div style={{ fontWeight: 500 }}>{client}</div>
                            <div style={{ fontSize: 11, color: '#94a3b8' }}>{vessel}</div>
                          </td>
                          <td style={{ padding: '10px 14px' }}>
                            <StatusBadge status={so.status} />
                          </td>
                          <td style={{ padding: '10px 14px', fontWeight: 600, color: V3.hdrBg, whiteSpace: 'nowrap' }}>
                            {so.grand_total ? fmtBRL(Number(so.grand_total)) : '—'}
                          </td>
                          <td style={{ padding: '10px 14px', color: '#64748b', whiteSpace: 'nowrap' }}>
                            {fmtDate(so.scheduled_start_at)}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              )}
            </div>
            <div style={{ marginTop: 6, textAlign: 'right', fontSize: 11, color: '#94a3b8' }}>
              {openOrdersCount} ordem{openOrdersCount !== 1 ? 's' : ''} ativa{openOrdersCount !== 1 ? 's' : ''}
            </div>
          </div>

          {/* ── Right column ── */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>

            {/* Próximas ações */}
            <div>
              <SectionHeader>Próximas Ações — 7 dias</SectionHeader>
              <div style={{ background: '#fff', borderRadius: 6, border: '1px solid #e2e8e0' }}>
                {upcomingOrders.length === 0 ? (
                  <div style={{ padding: '20px 16px', color: '#94a3b8', fontSize: 13, textAlign: 'center' }}>
                    Nenhuma OS agendada nos próximos 7 dias.
                  </div>
                ) : upcomingOrders.map((so, idx) => {
                  const row    = so as any;
                  const client = row.clients?.full_name_or_company_name ?? '—';
                  const vessel = row.vessels?.boat_name ?? '—';
                  return (
                    <div
                      key={so.id}
                      title={so.id ? 'Abrir OS' : undefined}
                      onClick={() => { if (so.id) navigate(`/service-orders/${so.id}`); }}
                      style={{
                        padding: '10px 16px',
                        borderBottom: idx < upcomingOrders.length - 1 ? '1px solid #f0efeb' : 'none',
                        cursor: so.id ? 'pointer' : 'default',
                        display: 'flex',
                        gap: 12,
                        alignItems: 'flex-start',
                      }}
                      onMouseEnter={e => { e.currentTarget.style.background = '#f9f8f5'; }}
                      onMouseLeave={e => { e.currentTarget.style.background = ''; }}
                    >
                      <div style={{
                        minWidth: 38,
                        textAlign: 'center',
                        background: V3.hdrBg,
                        color: V3.gold,
                        borderRadius: 4,
                        padding: '4px 0',
                        fontSize: 11,
                        fontWeight: 700,
                        lineHeight: 1.3,
                      }}>
                        {fmtDate(so.scheduled_start_at)}
                      </div>
                      <div style={{ minWidth: 0 }}>
                        <div style={{ fontSize: 12, fontWeight: 600, color: V3.hdrBg }}>
                          #{so.service_order_number} · {client}
                        </div>
                        <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 2 }}>{vessel}</div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>

            {/* WhatsApp Inbox */}
            <div>
              <SectionHeader>WhatsApp Inbox</SectionHeader>
              <div style={{
                background: '#fff',
                borderRadius: 6,
                border: '1px solid #e2e8e0',
                padding: '24px 16px',
                textAlign: 'center',
              }}>
                <div style={{ fontSize: 24, marginBottom: 8 }}>💬</div>
                <div style={{ fontSize: 12, color: '#94a3b8', lineHeight: 1.5 }}>
                  Seção reservada para integração WhatsApp.
                </div>
                <button
                  onClick={() => navigate('/whatsapp/leads')}
                  style={{
                    marginTop: 10,
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
                  Ver leads WhatsApp →
                </button>
              </div>
            </div>

          </div>
        </div>

        {/* Low stock (conditional) */}
        {lowStock.length > 0 && (
          <div>
            <SectionHeader>Estoque Crítico</SectionHeader>
            <div style={{ background: '#fff', borderRadius: 6, border: '1px solid #e2e8e0', overflow: 'hidden' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
                <thead>
                  <tr style={{ background: V3.navy900 }}>
                    {['Produto', 'Categoria', 'Estoque', 'Mínimo'].map(h => (
                      <th key={h} style={{
                        padding: '9px 14px',
                        textAlign: 'left',
                        fontSize: 10,
                        fontWeight: 600,
                        letterSpacing: '0.08em',
                        textTransform: 'uppercase',
                        color: 'rgba(255,255,255,0.50)',
                      }}>
                        {h}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {lowStock.map((p, idx) => (
                    <tr
                      key={p.id}
                      style={{
                        borderBottom: idx < lowStock.length - 1 ? '1px solid #f0efeb' : 'none',
                        borderLeft: '3px solid var(--mf-danger-400, #f87171)',
                      }}
                    >
                      <td style={{ padding: '10px 14px', fontWeight: 500, color: V3.hdrBg }}>
                        {p.product_name}
                      </td>
                      <td style={{ padding: '10px 14px', color: '#64748b' }}>
                        {(p as any).product_categories?.name ?? '—'}
                      </td>
                      <td style={{ padding: '10px 14px', color: '#ef4444', fontWeight: 700 }}>
                        {p.stock_quantity ?? 0}
                      </td>
                      <td style={{ padding: '10px 14px', color: '#64748b' }}>
                        {p.minimum_stock ?? 0}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}

      </div>
    </div>
  );
}
