import '@/styles/marineflow-tokens.css';

/* ─────────────────────────────────────────────────────────────────────────────
   Marineflow ERP — Design Preview V01 (Fase 1.2)
   Snapshot preservado. Não altere este arquivo após aprovação.
   V01 — Preview operacional aprovado · linguagem náutica · tokens isolados.
───────────────────────────────────────────────────────────────────────────── */

/* ── Dados mock ──────────────────────────────────────────────────────────── */

const OS_ROWS: OSRow[] = [
  { num: '1052', cliente: 'Ricardo Moura',   embarcacao: 'Phantom 303',    servico: 'Instalação GPSMAP 9×2 + backbone NMEA 2000 — 3 nós', status: 'Em diagnóstico',       prioridade: 'Alta',  tecnico: 'Gustavo', valor: '6.283,00', prazo: 'Hoje',        prazoAlerta: true  },
  { num: '1048', cliente: 'Marcelo Antunes', embarcacao: 'Azimut 42',      servico: 'Falha intermitente DC 12V — painel principal',        status: 'Aguardando peça',      prioridade: 'Alta',  tecnico: 'Gustavo', valor: '8.437,00', prazo: '3 dias atr.', prazoAlerta: true  },
  { num: '1055', cliente: 'Náutica Itajaí',  embarcacao: 'Intermarine 44', servico: 'Diagnóstico banco de baterias + carregador',          status: 'Aguardando aprovação', prioridade: 'Média', tecnico: 'Carlos',  valor: 'A orçar',  prazo: 'Hoje',        prazoAlerta: true  },
  { num: '1057', cliente: 'Pedro Lessa',     embarcacao: 'Azimut 50',      servico: 'Revisão bomba porão Rule 2000 + sensor nível',        status: 'Pronto p/ faturar',    prioridade: 'Baixa', tecnico: 'Gustavo', valor: '1.243,00', prazo: '17/05',       prazoAlerta: false },
  { num: '1059', cliente: 'Igor Faria',      embarcacao: 'Regal 32',       servico: 'Manut. preventiva motor Volvo D6 — troca filtros',    status: 'Aberta',               prioridade: 'Média', tecnico: '—',       valor: '4.657,00', prazo: '19/05',       prazoAlerta: false },
  { num: '1061', cliente: 'Marcelo Antunes', embarcacao: 'Azimut 42',      servico: 'Instalação cobertura de lona — borracha vedação',     status: 'Concluída',            prioridade: 'Baixa', tecnico: 'Carlos',  valor: '783,00',   prazo: '14/05',       prazoAlerta: false },
  { num: '1063', cliente: 'Marina do Saco',  embarcacao: 'Ferretti 550',   servico: 'Inspeção elétrica 220V/12V — vistoria seguro',        status: 'Em diagnóstico',       prioridade: 'Alta',  tecnico: 'Rafael',  valor: '5.118,00', prazo: '16/05',       prazoAlerta: false },
];

const WA_ITEMS: WaRow[] = [
  { nome: 'Marcelo Antunes',  ultima: 'Tudo bem, só queria saber se chegou a peça', tempo: '42 min',   lido: false, embarcacao: 'Azimut 42' },
  { nome: 'Náutica Itajaí',   ultima: 'Aprovado. Podem iniciar.',                   tempo: '1h 18min', lido: false, embarcacao: 'Intermarine 44' },
  { nome: 'Ricardo Moura',    ultima: 'Tem previsão do diagnóstico?',               tempo: '3h 04min', lido: true,  embarcacao: 'Phantom 303' },
  { nome: 'Marina do Saco',   ultima: 'Podem vir na quinta?',                       tempo: '5h 41min', lido: true,  embarcacao: 'Ferretti 550' },
];

const ALERTAS: AlertaRow[] = [
  { tipo: 'danger',  msg: 'OS #1048 vencida há 3 dias — Bomba Volvo D4 aguardando confirmação de prazo (Marine Parts BR)', acao: 'Ver OS'         },
  { tipo: 'warning', msg: 'Orçamento #1055 vence hoje — Náutica Itajaí sem retorno',                                       acao: 'Ver orçamento'  },
  { tipo: 'info',    msg: 'Marcelo Antunes respondeu no WhatsApp — sem leitura (42 min)',                                   acao: 'Abrir conversa' },
  { tipo: 'info',    msg: 'PDF da OS #1044 gerado mas não enviado ao cliente',                                              acao: 'Enviar PDF'     },
  { tipo: 'warning', msg: 'OS #1059 aberta há 2 dias sem técnico atribuído',                                               acao: 'Atribuir'       },
];

/* ── Paleta de tokens para a seção de referência ─────────────────────────── */
type Token = { name: string; value: string; label: string };

const COLOR_GROUPS: { label: string; tokens: Token[] }[] = [
  { label: 'Navy', tokens: [
    { name: '--mf-navy-900', value: '#06182E', label: '900' },
    { name: '--mf-navy-800', value: '#0B2540', label: '800' },
    { name: '--mf-navy-700', value: '#102F52', label: '700' },
    { name: '--mf-navy-600', value: '#1A4274', label: '600' },
    { name: '--mf-navy-500', value: '#2A6FBF', label: '500' },
    { name: '--mf-navy-300', value: '#7AAFD3', label: '300' },
    { name: '--mf-navy-100', value: '#DBE6F2', label: '100' },
    { name: '--mf-navy-50',  value: '#EDF2F8', label: '50'  },
  ]},
  { label: 'Gold', tokens: [
    { name: '--mf-gold-700', value: '#997126', label: '700' },
    { name: '--mf-gold-600', value: '#B8893C', label: '600' },
    { name: '--mf-gold-500', value: '#C8A24B', label: '500' },
    { name: '--mf-gold-300', value: '#E8CC85', label: '300' },
    { name: '--mf-gold-100', value: '#F6E9C4', label: '100' },
    { name: '--mf-gold-50',  value: '#FBF5E4', label: '50'  },
  ]},
  { label: 'Ink', tokens: [
    { name: '--mf-ink-900', value: '#0E1726', label: '900' },
    { name: '--mf-ink-700', value: '#2A3344', label: '700' },
    { name: '--mf-ink-500', value: '#4C5468', label: '500' },
    { name: '--mf-ink-400', value: '#6B7587', label: '400' },
    { name: '--mf-ink-200', value: '#C5CDD9', label: '200' },
    { name: '--mf-ink-100', value: '#E2E7EF', label: '100' },
    { name: '--mf-ink-50',  value: '#EEF1F6', label: '50'  },
  ]},
  { label: 'Semânticas', tokens: [
    { name: '--mf-success-500', value: '#2BA56A', label: 'ok'   },
    { name: '--mf-warning-500', value: '#D89117', label: 'warn' },
    { name: '--mf-danger-500',  value: '#DA4A41', label: 'err'  },
    { name: '--mf-info-500',    value: '#2F7FE0', label: 'info' },
  ]},
];

/* ── Type definitions ────────────────────────────────────────────────────── */
type OSRow = {
  num: string; cliente: string; embarcacao: string; servico: string;
  status: string; prioridade: 'Alta'|'Média'|'Baixa'; tecnico: string;
  valor: string; prazo: string; prazoAlerta: boolean;
};
type WaRow    = { nome: string; ultima: string; tempo: string; lido: boolean; embarcacao: string };
type AlertaRow= { tipo: 'danger'|'warning'|'info'; msg: string; acao: string };
type BtnVariant = 'primary'|'secondary'|'ghost'|'outline'|'danger'|'gold';

/* ── Status config ───────────────────────────────────────────────────────── */
const STATUS_CFG: Record<string, { bg: string; color: string; dot: string }> = {
  'Aberta':               { bg: 'var(--mf-info-100)',    color: 'var(--mf-info-700)',    dot: 'var(--mf-info-500)'    },
  'Em diagnóstico':       { bg: 'var(--mf-warning-100)', color: 'var(--mf-warning-700)', dot: 'var(--mf-warning-500)' },
  'Aguardando peça':      { bg: 'var(--mf-ink-100)',     color: 'var(--mf-ink-600)',     dot: 'var(--mf-ink-400)'     },
  'Aguardando aprovação': { bg: 'var(--mf-gold-100)',    color: 'var(--mf-gold-700)',    dot: 'var(--mf-gold-500)'    },
  'Pronto p/ faturar':    { bg: 'var(--mf-success-100)', color: 'var(--mf-success-700)', dot: 'var(--mf-success-500)' },
  'Concluída':            { bg: 'var(--mf-ink-50)',      color: 'var(--mf-ink-400)',     dot: 'var(--mf-ink-300)'     },
};

const PRIOR_CFG: Record<string, { color: string; bg: string }> = {
  'Alta':  { color: 'var(--mf-danger-700)',  bg: 'var(--mf-danger-50)'  },
  'Média': { color: 'var(--mf-warning-700)', bg: 'var(--mf-warning-50)' },
  'Baixa': { color: 'var(--mf-ink-500)',     bg: 'var(--mf-ink-50)'     },
};

const ALERTA_CFG = {
  success: { bg: 'var(--mf-success-50)',  border: 'var(--mf-success-500)', color: 'var(--mf-success-700)', icon: '✓' },
  danger:  { bg: 'var(--mf-danger-50)',   border: 'var(--mf-danger-500)',  color: 'var(--mf-danger-700)',  icon: '!' },
  warning: { bg: 'var(--mf-warning-50)',  border: 'var(--mf-warning-500)', color: 'var(--mf-warning-700)', icon: '!' },
  info:    { bg: 'var(--mf-info-50)',     border: 'var(--mf-info-500)',    color: 'var(--mf-info-700)',    icon: 'i' },
} as const;

/* ── Nav items ───────────────────────────────────────────────────────────── */
const NAV = [
  { id: 'atencao',       label: 'Atenção' },
  { id: 'fila',          label: 'Fila OS' },
  { id: 'os-detalhe',    label: 'OS Detalhe' },
  { id: 'relacionamento',label: 'Relacionamento' },
  { id: 'ui-elementos',  label: 'Componentes' },
  { id: 'tokens',        label: 'Tokens' },
];

/* ════════════════════════════════════════════════════════════════════════════
   COMPONENTE PRINCIPAL — V01
════════════════════════════════════════════════════════════════════════════ */
export default function DesignPreviewV01() {
  return (
    <div style={{ fontFamily: 'var(--mf-font-sans)', background: 'var(--mf-paper)', color: 'var(--mf-ink-900)', minHeight: '100vh', fontSize: 'var(--mf-text-base)', lineHeight: 1.5 }}>

      {/* ── Header ──────────────────────────────────────────────────────── */}
      <div style={{ position: 'sticky', top: 0, zIndex: 40, background: 'var(--mf-navy-900)', borderBottom: '1px solid var(--mf-navy-800)', height: 48, display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 20px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{ width: 26, height: 26, background: 'rgba(200,162,75,0.12)', borderRadius: 6, display: 'grid', placeItems: 'center', fontWeight: 700, fontSize: 12, color: 'var(--mf-gold-400)', border: '1px solid rgba(200,162,75,0.2)' }}>M</div>
          <span style={{ color: 'var(--mf-ink-100)', fontWeight: 600, fontSize: 'var(--mf-text-md)', letterSpacing: '-0.01em' }}>Marineflow ERP</span>
          <span style={{ color: 'var(--mf-ink-500)', fontSize: 'var(--mf-text-sm)' }}>·</span>
          <span style={{ color: 'var(--mf-ink-400)', fontSize: 'var(--mf-text-xs)' }}>Itajaí Marine Center</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
          <nav style={{ display: 'flex', gap: 2 }}>
            {NAV.map(n => (
              <a key={n.id} href={`#${n.id}`} style={{ color: 'var(--mf-ink-400)', fontSize: 'var(--mf-text-xs)', padding: '3px 8px', borderRadius: 4, textDecoration: 'none', fontWeight: 500 }}
                onMouseEnter={e => { const el = e.target as HTMLElement; el.style.color = 'var(--mf-gold-300)'; el.style.background = 'rgba(255,255,255,0.05)'; }}
                onMouseLeave={e => { const el = e.target as HTMLElement; el.style.color = 'var(--mf-ink-400)'; el.style.background = 'transparent'; }}>
                {n.label}
              </a>
            ))}
          </nav>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span style={{ background: 'rgba(200,162,75,0.1)', color: 'var(--mf-gold-400)', fontSize: 10, fontWeight: 700, padding: '2px 7px', borderRadius: 3, border: '1px solid rgba(200,162,75,0.2)', letterSpacing: '0.06em', textTransform: 'uppercase' }}>V01</span>
            <span style={{ background: 'rgba(200,162,75,0.1)', color: 'var(--mf-gold-400)', fontSize: 10, fontWeight: 700, padding: '2px 7px', borderRadius: 3, border: '1px solid rgba(200,162,75,0.2)', letterSpacing: '0.06em', textTransform: 'uppercase' }}>PREVIEW</span>
          </div>
        </div>
      </div>

      {/* ── Aviso de ambiente ───────────────────────────────────────────── */}
      <div style={{ background: 'var(--mf-navy-950)', borderBottom: '1px solid var(--mf-navy-800)', padding: '6px 20px', display: 'flex', alignItems: 'center', gap: 8 }}>
        <span style={{ fontSize: 10, fontWeight: 700, letterSpacing: '0.08em', textTransform: 'uppercase', color: 'var(--mf-ink-500)' }}>Snapshot V01 — aprovado</span>
        <span style={{ color: 'var(--mf-ink-600)', fontSize: 'var(--mf-text-xs)' }}>—</span>
        <span style={{ fontSize: 'var(--mf-text-xs)', color: 'var(--mf-ink-500)' }}>sem dados reais · zero chamadas externas · feat/ui-design-phase-1-preview</span>
        <span style={{ marginLeft: 'auto' }}>
          <a href="/design-preview-compare" style={{ fontSize: 'var(--mf-text-xs)', color: 'var(--mf-navy-300)', textDecoration: 'none', fontWeight: 500 }}>← Comparativo de versões</a>
        </span>
      </div>

      {/* ── Conteúdo ────────────────────────────────────────────────────── */}
      <div style={{ maxWidth: 1280, margin: '0 auto', padding: '20px 20px 48px' }}>

        {/* ── ATENÇÃO DE HOJE ────────────────────────────────────────────── */}
        <BlockHeader id="atencao" title="Atenção de hoje" sub="16 mai 2026 · sexta-feira" />

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 10, marginBottom: 28 }}>
          <KpiCard label="OS abertas" value="19" detalhe="3 atrasadas" detalheColor="var(--mf-danger-600)" />
          <KpiCard label="Orçamentos pendentes" value="5" detalhe="1 vence hoje" detalheColor="var(--mf-warning-600)" />
          <KpiCard label="WhatsApp aguardando" value="2" detalhe="sem leitura há 42 min" detalheColor="var(--mf-info-600)" />
          <KpiCard label="A receber esta semana" value="R$ 12.843" detalhe="2 vencidas ontem" detalheColor="var(--mf-danger-600)" />
        </div>

        {/* Alertas operacionais */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginBottom: 32 }}>
          {ALERTAS.map((a, i) => {
            const c = ALERTA_CFG[a.tipo] ?? ALERTA_CFG.info;
            return (
              <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 10, background: c.bg, border: `1px solid ${c.border}`, borderLeft: `3px solid ${c.border}`, borderRadius: 6, padding: '7px 12px' }}>
                <span style={{ width: 16, height: 16, borderRadius: '50%', background: c.border, color: '#fff', display: 'grid', placeItems: 'center', fontSize: 9, fontWeight: 800, flexShrink: 0 }}>{c.icon}</span>
                <span style={{ fontSize: 'var(--mf-text-sm)', color: c.color, flex: 1 }}>{a.msg}</span>
                <button style={{ fontSize: 'var(--mf-text-xs)', fontWeight: 600, color: c.color, background: 'transparent', border: `1px solid ${c.border}`, borderRadius: 4, padding: '2px 8px', cursor: 'pointer', whiteSpace: 'nowrap', fontFamily: 'var(--mf-font-sans)' }}>{a.acao}</button>
              </div>
            );
          })}
        </div>

        {/* ── FILA OPERACIONAL ───────────────────────────────────────────── */}
        <BlockHeader id="fila" title="Fila operacional — Ordens de Serviço" sub="19 registros · exibindo 7 · filtro: em aberto" />

        <div style={{ background: '#fff', border: '1px solid var(--mf-ink-100)', borderRadius: 8, overflow: 'hidden', marginBottom: 32 }}>
          {/* Toolbar */}
          <div style={{ padding: '8px 12px', borderBottom: '1px solid var(--mf-ink-100)', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8, background: 'var(--mf-paper)' }}>
            <div style={{ display: 'flex', gap: 6, alignItems: 'center', flex: 1 }}>
              <input placeholder="Buscar por OS, cliente ou embarcação…" style={{ height: 30, padding: '0 8px', border: '1px solid var(--mf-ink-200)', borderRadius: 4, fontSize: 'var(--mf-text-sm)', color: 'var(--mf-ink-700)', background: '#fff', outline: 'none', width: 260, fontFamily: 'var(--mf-font-sans)' }} />
              <FilterChip active>Em aberto</FilterChip>
              <FilterChip>Alta prioridade</FilterChip>
              <FilterChip>Sem técnico</FilterChip>
              <FilterChip>Aguardando peça</FilterChip>
            </div>
            <MfButton variant="primary" size="sm">+ Nova OS</MfButton>
          </div>

          {/* Tabela */}
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            <thead>
              <tr style={{ borderBottom: '1px solid var(--mf-ink-100)', background: 'var(--mf-paper)' }}>
                {['OS', 'Cliente', 'Embarcação', 'Serviço', 'Status', 'Prior.', 'Técnico', 'Valor', 'Prazo'].map(h => (
                  <th key={h} style={{ padding: '7px 10px', textAlign: 'left', fontSize: 10, fontWeight: 700, color: 'var(--mf-ink-400)', letterSpacing: '0.05em', textTransform: 'uppercase', whiteSpace: 'nowrap' }}>{h}</th>
                ))}
                <th style={{ padding: '7px 10px', width: 32 }} />
              </tr>
            </thead>
            <tbody>
              {OS_ROWS.map((row, i) => {
                const sc = STATUS_CFG[row.status] ?? STATUS_CFG['Aberta'];
                const pc = PRIOR_CFG[row.prioridade];
                const critical = row.prioridade === 'Alta' && row.prazoAlerta;
                return (
                  <tr key={row.num} style={{ borderBottom: i < OS_ROWS.length - 1 ? '1px solid var(--mf-ink-50)' : undefined, background: critical ? 'var(--mf-danger-50)' : 'transparent', borderLeft: critical ? '3px solid var(--mf-danger-400)' : '3px solid transparent' }}
                    onMouseEnter={e => (e.currentTarget.style.background = critical ? '#FDECEA' : '#F7F8FA')}
                    onMouseLeave={e => (e.currentTarget.style.background = critical ? 'var(--mf-danger-50)' : 'transparent')}>
                    <td style={{ padding: '8px 10px', fontFamily: 'var(--mf-font-mono)', fontSize: 'var(--mf-text-sm)', color: 'var(--mf-navy-600)', fontWeight: 600, whiteSpace: 'nowrap' }}>#{row.num}</td>
                    <td style={{ padding: '8px 10px', fontSize: 'var(--mf-text-sm)', fontWeight: 500, color: 'var(--mf-ink-900)', whiteSpace: 'nowrap' }}>{row.cliente}</td>
                    <td style={{ padding: '8px 10px', fontSize: 'var(--mf-text-sm)', color: 'var(--mf-ink-500)', whiteSpace: 'nowrap' }}>{row.embarcacao}</td>
                    <td style={{ padding: '8px 10px', fontSize: 'var(--mf-text-sm)', color: 'var(--mf-ink-700)', maxWidth: 220 }}>
                      <span style={{ display: 'block', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{row.servico}</span>
                    </td>
                    <td style={{ padding: '8px 10px', whiteSpace: 'nowrap' }}>
                      <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, background: sc.bg, color: sc.color, borderRadius: 99, padding: '2px 7px', fontSize: 11, fontWeight: 600, whiteSpace: 'nowrap' }}>
                        <span style={{ width: 4, height: 4, borderRadius: '50%', background: sc.dot, flexShrink: 0 }} />
                        {row.status}
                      </span>
                    </td>
                    <td style={{ padding: '8px 10px' }}>
                      <span style={{ display: 'inline-block', background: pc.bg, color: pc.color, borderRadius: 3, padding: '1px 6px', fontSize: 11, fontWeight: 600 }}>{row.prioridade}</span>
                    </td>
                    <td style={{ padding: '8px 10px', fontSize: 'var(--mf-text-sm)', color: row.tecnico === '—' ? 'var(--mf-ink-300)' : 'var(--mf-ink-600)', whiteSpace: 'nowrap' }}>
                      {row.tecnico === '—' ? <span style={{ fontStyle: 'italic' }}>Sem técnico</span> : row.tecnico}
                    </td>
                    <td style={{ padding: '8px 10px', fontFamily: 'var(--mf-font-mono)', fontSize: 'var(--mf-text-sm)', fontWeight: 600, color: 'var(--mf-ink-800)', whiteSpace: 'nowrap', textAlign: 'right' }}>
                      {row.valor === 'A orçar' ? <span style={{ color: 'var(--mf-ink-400)', fontStyle: 'italic', fontWeight: 400, fontFamily: 'var(--mf-font-sans)' }}>A orçar</span> : `R$ ${row.valor}`}
                    </td>
                    <td style={{ padding: '8px 10px', fontSize: 'var(--mf-text-sm)', whiteSpace: 'nowrap', color: row.prazoAlerta ? 'var(--mf-danger-600)' : 'var(--mf-ink-400)', fontWeight: row.prazoAlerta ? 600 : 400 }}>
                      {row.prazo}
                    </td>
                    <td style={{ padding: '8px 10px' }}>
                      <button style={{ fontSize: 11, color: 'var(--mf-navy-600)', background: 'transparent', border: '1px solid var(--mf-navy-200)', borderRadius: 4, padding: '2px 7px', cursor: 'pointer', fontWeight: 500, fontFamily: 'var(--mf-font-sans)', whiteSpace: 'nowrap' }}>Ver OS</button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>

          <div style={{ padding: '7px 12px', borderTop: '1px solid var(--mf-ink-100)', display: 'flex', justifyContent: 'space-between', alignItems: 'center', background: 'var(--mf-paper)' }}>
            <span style={{ fontSize: 'var(--mf-text-xs)', color: 'var(--mf-ink-400)' }}>7 de 19 registros · R$ 26.521,00 em aberto · 1 a orçar</span>
            <div style={{ display: 'flex', gap: 2 }}>
              {['‹', '1', '2', '3', '›'].map((p, i) => (
                <button key={i} style={{ width: 26, height: 24, borderRadius: 4, border: p === '1' ? '1px solid var(--mf-navy-400)' : '1px solid var(--mf-ink-200)', background: p === '1' ? 'var(--mf-navy-800)' : 'transparent', color: p === '1' ? '#fff' : 'var(--mf-ink-500)', fontSize: 'var(--mf-text-xs)', cursor: 'pointer', fontFamily: 'var(--mf-font-sans)' }}>{p}</button>
              ))}
            </div>
          </div>
        </div>

        {/* ── OS EM DETALHE ──────────────────────────────────────────────── */}
        <BlockHeader id="os-detalhe" title="Ordem de Serviço #1048" sub="Marcelo Antunes · Azimut 42 · Aguardando Volvo D4 (Marine Parts BR)" />

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 340px', gap: 12, marginBottom: 32 }}>
          {/* Corpo principal da OS */}
          <div style={{ background: '#fff', border: '1px solid var(--mf-ink-100)', borderRadius: 8, overflow: 'hidden' }}>
            {/* Cabeçalho */}
            <div style={{ borderLeft: '3px solid var(--mf-warning-500)', padding: '12px 16px', borderBottom: '1px solid var(--mf-ink-100)', display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
              <div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
                  <span style={{ fontFamily: 'var(--mf-font-mono)', fontSize: 'var(--mf-text-sm)', color: 'var(--mf-navy-500)', fontWeight: 700 }}>OS #1048</span>
                  <StatusPill status="Aguardando peça" />
                  <PriorPill p="Alta" />
                </div>
                <div style={{ fontWeight: 600, fontSize: 'var(--mf-text-lg)', color: 'var(--mf-ink-900)', letterSpacing: '-0.01em' }}>Falha intermitente no sistema DC 12V</div>
              </div>
              <div style={{ display: 'flex', gap: 6 }}>
                <MfButton variant="ghost" size="sm">Gerar PDF</MfButton>
                <MfButton variant="primary" size="sm">Editar OS</MfButton>
              </div>
            </div>

            {/* Grid de info */}
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 0, borderBottom: '1px solid var(--mf-ink-100)' }}>
              <OsInfoCell k="Cliente" v="Marcelo Antunes" />
              <OsInfoCell k="Embarcação" v="Azimut 42 · 2019" border />
              <OsInfoCell k="Marina" v="Itajaí Marine Center" border />
              <OsInfoCell k="Técnico responsável" v="Gustavo Ferreira" />
              <OsInfoCell k="Abertura" v="13/05/2026" border />
              <OsInfoCell k="Prazo estimado" v={<span style={{ color: 'var(--mf-danger-600)', fontWeight: 600 }}>Atrasada (3 dias)</span>} border />
            </div>

            {/* Descrição */}
            <div style={{ padding: '12px 16px', borderBottom: '1px solid var(--mf-ink-100)' }}>
              <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: '0.08em', textTransform: 'uppercase', color: 'var(--mf-ink-400)', marginBottom: 6 }}>Diagnóstico</div>
              <p style={{ margin: 0, fontSize: 'var(--mf-text-sm)', color: 'var(--mf-ink-700)', lineHeight: 1.55 }}>
                Embarcação apresenta falha intermitente na alimentação DC 12V do painel de controle. Sintoma: painel apaga e reinicia a cada 20–40 min de operação em alta rotação. Suspeita de falha no relê principal do barramento. Bomba de óleo Volvo D4 solicitada ao fornecedor — pedido realizado em 13/05.
              </p>
            </div>

            {/* Itens */}
            <div style={{ padding: '12px 16px' }}>
              <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: '0.08em', textTransform: 'uppercase', color: 'var(--mf-ink-400)', marginBottom: 8 }}>Itens da OS</div>
              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 'var(--mf-text-sm)' }}>
                <thead>
                  <tr style={{ borderBottom: '1px solid var(--mf-ink-100)' }}>
                    {['Descrição', 'Tipo', 'Qtd', 'Unit.', 'Total'].map(h => (
                      <th key={h} style={{ padding: '4px 8px', textAlign: 'left', fontSize: 10, color: 'var(--mf-ink-400)', fontWeight: 600, letterSpacing: '0.04em', textTransform: 'uppercase' }}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {[
                    { desc: 'M.o. — diagnóstico elétrico DC/12V',      tipo: 'Serviço', qtd: '4h', unit: 'R$ 185,00',   total: 'R$ 740,00'   },
                    { desc: 'Bomba de óleo Volvo D4 — PN 21414606',    tipo: 'Peça',    qtd: '1',  unit: 'R$ 7.215,00', total: 'R$ 7.215,00' },
                    { desc: 'Fusível ANL 150A (Marine Parts BR)',       tipo: 'Peça',    qtd: '2',  unit: 'R$ 89,50',    total: 'R$ 179,00'   },
                    { desc: 'Cabo NMEA 2000 backbone 6m',               tipo: 'Peça',    qtd: '1',  unit: 'R$ 303,00',   total: 'R$ 303,00'   },
                  ].map((it, i) => (
                    <tr key={i} style={{ borderBottom: '1px solid var(--mf-ink-50)' }}>
                      <td style={{ padding: '6px 8px', color: 'var(--mf-ink-800)' }}>{it.desc}</td>
                      <td style={{ padding: '6px 8px' }}>
                        <span style={{ background: it.tipo === 'Peça' ? 'var(--mf-navy-50)' : 'var(--mf-gold-50)', color: it.tipo === 'Peça' ? 'var(--mf-navy-600)' : 'var(--mf-gold-700)', borderRadius: 3, padding: '1px 6px', fontSize: 11, fontWeight: 600 }}>{it.tipo}</span>
                      </td>
                      <td style={{ padding: '6px 8px', fontFamily: 'var(--mf-font-mono)', color: 'var(--mf-ink-600)' }}>{it.qtd}</td>
                      <td style={{ padding: '6px 8px', fontFamily: 'var(--mf-font-mono)', color: 'var(--mf-ink-600)', textAlign: 'right' }}>{it.unit}</td>
                      <td style={{ padding: '6px 8px', fontFamily: 'var(--mf-font-mono)', fontWeight: 600, color: 'var(--mf-ink-900)', textAlign: 'right' }}>{it.total}</td>
                    </tr>
                  ))}
                  <tr style={{ background: 'var(--mf-paper)' }}>
                    <td colSpan={4} style={{ padding: '8px 8px 4px', textAlign: 'right', fontSize: 'var(--mf-text-sm)', fontWeight: 600, color: 'var(--mf-ink-500)' }}>Total da OS</td>
                    <td style={{ padding: '8px 8px 4px', fontFamily: 'var(--mf-font-mono)', fontSize: 'var(--mf-text-md)', fontWeight: 700, color: 'var(--mf-navy-800)', textAlign: 'right' }}>R$ 8.437,00</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          {/* Painel lateral */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            {/* Próxima ação */}
            <div style={{ background: '#fff', border: '1px solid var(--mf-ink-100)', borderRadius: 8, padding: '12px 14px' }}>
              <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: '0.08em', textTransform: 'uppercase', color: 'var(--mf-ink-400)', marginBottom: 8 }}>Próxima ação</div>
              <div style={{ fontSize: 'var(--mf-text-sm)', color: 'var(--mf-ink-700)', marginBottom: 10, lineHeight: 1.5 }}>
                Aguardando Bomba Volvo D4 — pedido em 13/05 (Marine Parts BR). Confirmar prazo e avisar Marcelo.
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                <MfButton variant="outline" size="sm">Atualizar status</MfButton>
                <MfButton variant="ghost" size="sm">Enviar WhatsApp ao cliente</MfButton>
              </div>
            </div>

            {/* Timeline compacta */}
            <div style={{ background: '#fff', border: '1px solid var(--mf-ink-100)', borderRadius: 8, padding: '12px 14px' }}>
              <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: '0.08em', textTransform: 'uppercase', color: 'var(--mf-ink-400)', marginBottom: 10 }}>Histórico</div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
                {[
                  { d: '13/05 09:14', ev: 'OS aberta — Gustavo',                color: 'var(--mf-navy-300)'   },
                  { d: '13/05 11:30', ev: 'Diagnóstico iniciado',               color: 'var(--mf-warning-400)'},
                  { d: '13/05 14:52', ev: 'Peça solicitada ao fornecedor',       color: 'var(--mf-ink-300)'    },
                  { d: '14/05 08:00', ev: 'WhatsApp enviado ao cliente',         color: 'var(--mf-info-400)'   },
                ].map((ev, i, arr) => (
                  <div key={i} style={{ display: 'flex', gap: 10, position: 'relative' }}>
                    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', flexShrink: 0 }}>
                      <div style={{ width: 8, height: 8, borderRadius: '50%', background: ev.color, marginTop: 4, flexShrink: 0 }} />
                      {i < arr.length - 1 && <div style={{ width: 1, flex: 1, background: 'var(--mf-ink-100)', marginTop: 2 }} />}
                    </div>
                    <div style={{ paddingBottom: i < arr.length - 1 ? 10 : 0 }}>
                      <div style={{ fontSize: 'var(--mf-text-sm)', color: 'var(--mf-ink-700)' }}>{ev.ev}</div>
                      <div style={{ fontSize: 10, color: 'var(--mf-ink-400)', fontFamily: 'var(--mf-font-mono)' }}>{ev.d}</div>
                    </div>
                  </div>
                ))}
              </div>
            </div>

            {/* Obs interna */}
            <div style={{ background: 'var(--mf-warning-50)', border: '1px solid var(--mf-warning-100)', borderRadius: 8, padding: '10px 14px' }}>
              <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: '0.08em', textTransform: 'uppercase', color: 'var(--mf-warning-600)', marginBottom: 6 }}>Observação interna</div>
              <p style={{ margin: 0, fontSize: 'var(--mf-text-xs)', color: 'var(--mf-warning-700)', lineHeight: 1.5 }}>
                Cliente solicitou retorno até sexta-feira (16/05). Não iniciar a OS sem confirmar o recebimento da peça.
              </p>
            </div>
          </div>
        </div>

        {/* ── RELACIONAMENTO / WHATSAPP ───────────────────────────────────── */}
        <BlockHeader id="relacionamento" title="Relacionamento — WhatsApp Inbox" sub="4 conversas ativas · 2 sem leitura · última há 42 min" />

        <div style={{ display: 'grid', gridTemplateColumns: '340px 1fr', gap: 12, marginBottom: 32, maxHeight: 340 }}>
          {/* Lista de conversas */}
          <div style={{ background: '#fff', border: '1px solid var(--mf-ink-100)', borderRadius: 8, overflow: 'hidden' }}>
            <div style={{ padding: '8px 12px', borderBottom: '1px solid var(--mf-ink-100)', background: 'var(--mf-paper)' }}>
              <input placeholder="Buscar conversa…" style={{ width: '100%', height: 28, padding: '0 8px', border: '1px solid var(--mf-ink-200)', borderRadius: 4, fontSize: 'var(--mf-text-sm)', color: 'var(--mf-ink-700)', background: '#fff', outline: 'none', fontFamily: 'var(--mf-font-sans)', boxSizing: 'border-box' }} />
            </div>
            {WA_ITEMS.map((wa, i) => (
              <div key={i} style={{ padding: '10px 12px', borderBottom: i < WA_ITEMS.length - 1 ? '1px solid var(--mf-ink-50)' : undefined, display: 'flex', gap: 10, alignItems: 'flex-start', background: i === 0 ? 'var(--mf-navy-50)' : 'transparent', cursor: 'pointer' }}>
                <div style={{ width: 34, height: 34, borderRadius: '50%', background: i === 0 ? 'var(--mf-navy-200)' : 'var(--mf-ink-100)', display: 'grid', placeItems: 'center', fontSize: 12, fontWeight: 700, color: i === 0 ? 'var(--mf-navy-800)' : 'var(--mf-ink-500)', flexShrink: 0 }}>
                  {wa.nome.split(' ').slice(0,2).map(n => n[0]).join('')}
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 2 }}>
                    <span style={{ fontSize: 'var(--mf-text-sm)', fontWeight: wa.lido ? 400 : 700, color: 'var(--mf-ink-900)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{wa.nome}</span>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 4, flexShrink: 0 }}>
                      {!wa.lido && <span style={{ width: 7, height: 7, borderRadius: '50%', background: 'var(--mf-info-500)', display: 'inline-block' }} />}
                      <span style={{ fontSize: 10, color: 'var(--mf-ink-400)', fontFamily: 'var(--mf-font-mono)' }}>{wa.tempo}</span>
                    </div>
                  </div>
                  <div style={{ fontSize: 'var(--mf-text-xs)', color: 'var(--mf-ink-400)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{wa.ultima}</div>
                  <div style={{ fontSize: 10, color: 'var(--mf-navy-400)', marginTop: 2 }}>{wa.embarcacao}</div>
                </div>
              </div>
            ))}
          </div>

          {/* Preview de conversa */}
          <div style={{ background: '#fff', border: '1px solid var(--mf-ink-100)', borderRadius: 8, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
            <div style={{ padding: '10px 14px', borderBottom: '1px solid var(--mf-ink-100)', display: 'flex', justifyContent: 'space-between', alignItems: 'center', background: 'var(--mf-paper)' }}>
              <div>
                <div style={{ fontWeight: 600, fontSize: 'var(--mf-text-sm)', color: 'var(--mf-ink-900)' }}>Marcelo Antunes</div>
                <div style={{ fontSize: 10, color: 'var(--mf-ink-400)' }}>Azimut 42 · OS #1048 ativa</div>
              </div>
              <div style={{ display: 'flex', gap: 6 }}>
                <MfButton variant="ghost" size="sm">Ver OS #1048</MfButton>
                <MfButton variant="outline" size="sm">Abrir no WhatsApp</MfButton>
              </div>
            </div>
            <div style={{ flex: 1, padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 8, overflowY: 'auto' }}>
              {[
                { lado: 'deles', msg: 'Boa tarde, tem novidades da Azimut?', hora: 'ontem 15:43' },
                { lado: 'nos',   msg: 'Oi Marcelo! Peça solicitada em 13/05 (Marine Parts BR). Prazo: 16–17/05. Te avisamos quando confirmar.', hora: 'ontem 16:02' },
                { lado: 'deles', msg: 'Tudo bem, só queria saber se chegou a peça', hora: 'hoje 09:31' },
              ].map((m, i) => (
                <div key={i} style={{ display: 'flex', justifyContent: m.lado === 'nos' ? 'flex-end' : 'flex-start' }}>
                  <div style={{ maxWidth: '68%', background: m.lado === 'nos' ? 'var(--mf-navy-800)' : 'var(--mf-ink-50)', color: m.lado === 'nos' ? '#fff' : 'var(--mf-ink-800)', borderRadius: m.lado === 'nos' ? '10px 2px 10px 10px' : '2px 10px 10px 10px', padding: '7px 10px', fontSize: 'var(--mf-text-sm)', lineHeight: 1.45 }}>
                    <div>{m.msg}</div>
                    <div style={{ fontSize: 10, opacity: 0.55, marginTop: 3, textAlign: 'right', fontFamily: 'var(--mf-font-mono)' }}>{m.hora}</div>
                  </div>
                </div>
              ))}
              <div style={{ display: 'flex', alignItems: 'center', gap: 4, color: 'var(--mf-ink-300)', fontSize: 10 }}>
                <div style={{ flex: 1, height: 1, background: 'var(--mf-ink-100)' }} />
                <span>Não lido</span>
                <div style={{ flex: 1, height: 1, background: 'var(--mf-ink-100)' }} />
              </div>
              <div style={{ display: 'flex', justifyContent: 'flex-start' }}>
                <div style={{ maxWidth: '68%', background: 'var(--mf-ink-50)', color: 'var(--mf-ink-800)', borderRadius: '2px 10px 10px 10px', padding: '7px 10px', fontSize: 'var(--mf-text-sm)', border: '1px solid var(--mf-info-200)' }}>
                  Tudo bem, só queria saber se chegou a peça
                  <div style={{ fontSize: 10, opacity: 0.55, marginTop: 3, fontFamily: 'var(--mf-font-mono)' }}>hoje 09:31</div>
                </div>
              </div>
            </div>
            <div style={{ padding: '8px 12px', borderTop: '1px solid var(--mf-ink-100)', display: 'flex', gap: 6 }}>
              <input placeholder="Responder a Marcelo…" style={{ flex: 1, height: 32, padding: '0 10px', border: '1px solid var(--mf-ink-200)', borderRadius: 4, fontSize: 'var(--mf-text-sm)', outline: 'none', fontFamily: 'var(--mf-font-sans)' }} />
              <MfButton variant="primary" size="sm">Enviar</MfButton>
            </div>
          </div>
        </div>

        {/* ── COMPONENTES — REFERÊNCIA ────────────────────────────────────── */}
        <BlockHeader id="ui-elementos" title="Componentes — referência" sub="botões, campos, badges e estados" />

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 12, marginBottom: 32 }}>
          {/* Botões em contexto */}
          <div style={{ background: '#fff', border: '1px solid var(--mf-ink-100)', borderRadius: 8, padding: '14px 16px' }}>
            <Label>Ações de OS</Label>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginBottom: 12 }}>
              <MfButton variant="primary">Salvar OS</MfButton>
              <MfButton variant="gold">Aprovar orçamento</MfButton>
              <MfButton variant="outline">Gerar PDF</MfButton>
              <MfButton variant="secondary">Cancelar</MfButton>
              <MfButton variant="danger">Excluir OS</MfButton>
            </div>
            <Label>Estado de envio</Label>
            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
              <MfButton variant="primary" loading>Salvando</MfButton>
              <MfButton variant="primary" disabled>Enviando PDF…</MfButton>
            </div>
          </div>

          {/* Campos em contexto */}
          <div style={{ background: '#fff', border: '1px solid var(--mf-ink-100)', borderRadius: 8, padding: '14px 16px' }}>
            <Label>Campos — Nova OS</Label>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              <MfField label="Cliente" placeholder="Buscar cliente…" />
              <MfField label="Embarcação" placeholder="Selecionar embarcação…" />
              <MfField label="Serviço" placeholder="Descrever o problema…" multiline />
              <MfField label="Valor (R$)" placeholder="0,00" />
              <MfField label="Técnico responsável" value="Gustavo Ferreira" disabled />
              <MfField label="Peça vinculada" error="Peça não vinculada à OS" placeholder="Buscar peça…" />
            </div>
          </div>

          {/* Badges em contexto */}
          <div style={{ background: '#fff', border: '1px solid var(--mf-ink-100)', borderRadius: 8, padding: '14px 16px' }}>
            <Label>Status de OS</Label>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 14 }}>
              {Object.entries(STATUS_CFG).map(([label, c]) => (
                <span key={label} style={{ display: 'inline-flex', alignItems: 'center', gap: 4, background: c.bg, color: c.color, borderRadius: 99, padding: '3px 8px', fontSize: 11, fontWeight: 600 }}>
                  <span style={{ width: 4, height: 4, borderRadius: '50%', background: c.dot }} />{label}
                </span>
              ))}
            </div>
            <Label>Prioridade</Label>
            <div style={{ display: 'flex', gap: 6, marginBottom: 14 }}>
              {Object.entries(PRIOR_CFG).map(([p, c]) => (
                <span key={p} style={{ background: c.bg, color: c.color, borderRadius: 4, padding: '2px 8px', fontSize: 11, fontWeight: 600 }}>{p}</span>
              ))}
            </div>
            <Label>Roles</Label>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 14 }}>
              {[
                { l: 'Admin',     bg: 'var(--mf-navy-800)', c: 'var(--mf-ink-100)'  },
                { l: 'Técnico',   bg: 'var(--mf-navy-100)', c: 'var(--mf-navy-700)' },
                { l: 'Financeiro',bg: 'var(--mf-gold-100)', c: 'var(--mf-gold-700)' },
                { l: 'Vendedor',  bg: 'var(--mf-ink-100)',  c: 'var(--mf-ink-600)'  },
              ].map(r => (
                <span key={r.l} style={{ background: r.bg, color: r.c, borderRadius: 4, padding: '2px 8px', fontSize: 11, fontWeight: 600 }}>{r.l}</span>
              ))}
            </div>
            <Label>Financeiro</Label>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 14 }}>
              {[
                { l: 'Pago',     bg: 'var(--mf-success-100)', c: 'var(--mf-success-700)', border: true },
                { l: 'Vencido',  bg: 'var(--mf-danger-100)',  c: 'var(--mf-danger-700)',  border: true },
                { l: 'Parcial',  bg: 'var(--mf-warning-100)', c: 'var(--mf-warning-700)', border: true },
                { l: 'Pendente', bg: 'var(--mf-ink-100)',     c: 'var(--mf-ink-500)',     border: false},
              ].map(r => (
                <span key={r.l} style={{ background: r.bg, color: r.c, borderRadius: 4, padding: '2px 8px', fontSize: 11, fontWeight: 600, border: r.border ? `1px solid ${r.c}` : undefined }}>{r.l}</span>
              ))}
            </div>
            <Label>Empty state</Label>
            <div style={{ background: 'var(--mf-paper)', border: '1px solid var(--mf-ink-100)', borderRadius: 6, padding: '16px', textAlign: 'center' }}>
              <div style={{ fontSize: 'var(--mf-text-sm)', fontWeight: 600, color: 'var(--mf-ink-600)', marginBottom: 4 }}>Nenhuma OS encontrada</div>
              <div style={{ fontSize: 'var(--mf-text-xs)', color: 'var(--mf-ink-400)', marginBottom: 10 }}>Ajuste o filtro ou crie uma nova OS.</div>
              <MfButton variant="primary" size="sm">+ Nova OS</MfButton>
            </div>
          </div>
        </div>

        {/* Toasts em contexto */}
        <div style={{ background: '#fff', border: '1px solid var(--mf-ink-100)', borderRadius: 8, padding: '14px 16px', marginBottom: 32 }}>
          <Label>Notificações do sistema</Label>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 6 }}>
            {[
              { tipo: 'success' as const, msg: 'OS #1057 salva. Status atualizado para "Pronto p/ faturar".' },
              { tipo: 'danger'  as const, msg: 'Erro ao gerar PDF da OS #1044. Tente novamente ou contate o suporte.' },
              { tipo: 'warning' as const, msg: 'Orçamento #221 vence em menos de 24h sem resposta do cliente.' },
              { tipo: 'info'    as const, msg: 'PDF da OS #1055 enviado por WhatsApp para Náutica Itajaí.' },
            ].map((t, i) => {
              const c = ALERTA_CFG[t.tipo] ?? ALERTA_CFG.info;
              return (
                <div key={i} style={{ display: 'flex', alignItems: 'flex-start', gap: 8, background: c.bg, borderLeft: `3px solid ${c.border}`, borderRadius: 4, padding: '8px 10px' }}>
                  <span style={{ width: 16, height: 16, borderRadius: '50%', background: c.border, color: '#fff', display: 'grid', placeItems: 'center', fontSize: 9, fontWeight: 800, flexShrink: 0, marginTop: 1 }}>{c.icon}</span>
                  <span style={{ fontSize: 'var(--mf-text-xs)', color: c.color, lineHeight: 1.5 }}>{t.msg}</span>
                </div>
              );
            })}
          </div>
        </div>

        {/* ── TOKENS ─────────────────────────────────────────────────────── */}
        <BlockHeader id="tokens" title="Tokens de design — referência" sub="paleta, tipografia e fundamentos visuais" />

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 16, marginBottom: 24 }}>
          {COLOR_GROUPS.map(g => (
            <div key={g.label}>
              <div style={{ fontSize: 10, fontWeight: 700, color: 'var(--mf-ink-400)', letterSpacing: '0.08em', textTransform: 'uppercase', marginBottom: 6 }}>{g.label}</div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
                {g.tokens.map(t => {
                  const r = parseInt(t.value.slice(1,3),16), gr = parseInt(t.value.slice(3,5),16), b2 = parseInt(t.value.slice(5,7),16);
                  const dark = (r*0.299+gr*0.587+b2*0.114) < 128;
                  return (
                    <div key={t.name} style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                      <div style={{ width: 20, height: 20, borderRadius: 3, background: t.value, border: '1px solid rgba(0,0,0,0.08)', flexShrink: 0, display: 'grid', placeItems: 'center' }}>
                        <span style={{ fontSize: 8, fontWeight: 700, color: dark ? 'rgba(255,255,255,0.55)' : 'rgba(0,0,0,0.35)', fontFamily: 'var(--mf-font-mono)' }}>{t.label}</span>
                      </div>
                      <span style={{ fontSize: 10, color: 'var(--mf-ink-400)', fontFamily: 'var(--mf-font-mono)' }}>{t.value}</span>
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </div>

        {/* Tipografia compacta */}
        <div style={{ background: '#fff', border: '1px solid var(--mf-ink-100)', borderRadius: 8, padding: '14px 16px', marginBottom: 32 }}>
          <Label>Escala tipográfica — Plus Jakarta Sans</Label>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 0 }}>
            {[
              { s: 'var(--mf-text-2xl)', w: 800, ex: 'OS #1048 — Falha DC 12V',            l: '2xl · 24px · 800' },
              { s: 'var(--mf-text-xl)',  w: 700, ex: 'Marcelo Antunes — Azimut 42',         l: 'xl · 20px · 700'  },
              { s: 'var(--mf-text-lg)',  w: 600, ex: 'Itajaí Marine Center · Prioridade Alta', l: 'lg · 18px · 600' },
              { s: 'var(--mf-text-md)',  w: 500, ex: 'Motor de popa 4 tempos, revisão completa com troca de óleo e filtros.', l: 'md · 16px · 500' },
              { s: 'var(--mf-text-base)',w: 400, ex: 'Diagnóstico: falha intermitente no sistema DC 12V do painel de controle.', l: 'base · 14px · 400' },
              { s: 'var(--mf-text-sm)', w: 400, ex: 'Última atualização: 14/05/2026 09:31 · Técnico: Gustavo Ferreira', l: 'sm · 12px · 400' },
            ].map(t => (
              <div key={t.l} style={{ padding: '8px 0', borderBottom: '1px solid var(--mf-ink-50)', display: 'flex', alignItems: 'baseline', gap: 12 }}>
                <span style={{ width: 110, fontSize: 10, color: 'var(--mf-ink-300)', fontFamily: 'var(--mf-font-mono)', flexShrink: 0 }}>{t.l}</span>
                <span style={{ fontSize: t.s, fontWeight: t.w, color: 'var(--mf-ink-900)', letterSpacing: t.w >= 700 ? '-0.02em' : 0 } as React.CSSProperties}>{t.ex}</span>
              </div>
            ))}
          </div>
          <div style={{ marginTop: 10, background: 'var(--mf-navy-950)', borderRadius: 4, padding: '8px 12px' }}>
            <span style={{ fontSize: 10, color: 'var(--mf-ink-500)', fontFamily: 'var(--mf-font-mono)', display: 'block', marginBottom: 4 }}>Mono — valores e referências</span>
            <span style={{ fontFamily: 'var(--mf-font-mono)', color: 'var(--mf-gold-300)', fontSize: 'var(--mf-text-sm)' }}>OS-1048 · R$ 8.437,00 · 2026-05-16 · PN 21414606 · #0B2540</span>
          </div>
        </div>

        {/* Footer */}
        <div style={{ paddingTop: 16, borderTop: '1px solid var(--mf-ink-100)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span style={{ fontSize: 'var(--mf-text-xs)', color: 'var(--mf-ink-300)' }}>Marineflow ERP · Design Preview V01 · Fase 1.2 · {new Date().toLocaleDateString('pt-BR')}</span>
          <span style={{ fontSize: 10, color: 'var(--mf-ink-200)', fontFamily: 'var(--mf-font-mono)' }}>feat/ui-design-phase-1-preview · HBR Systems</span>
        </div>
      </div>

      {/* Shimmer */}
      <style>{`@keyframes mf-spin { to { transform: rotate(360deg); } }`}</style>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════════════
   PRIMITIVOS INTERNOS
════════════════════════════════════════════════════════════════════════════ */

function BlockHeader({ id, title, sub }: { id: string; title: string; sub: string }) {
  return (
    <div id={id} style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 10, paddingBottom: 8, borderBottom: '1px solid var(--mf-ink-100)' }}>
      <h2 style={{ margin: 0, fontSize: 'var(--mf-text-md)', fontWeight: 700, color: 'var(--mf-navy-800)', letterSpacing: '-0.01em' }}>{title}</h2>
      <span style={{ fontSize: 'var(--mf-text-xs)', color: 'var(--mf-ink-400)' }}>{sub}</span>
    </div>
  );
}

function KpiCard({ label, value, detalhe, detalheColor }: { label: string; value: string; detalhe: string; detalheColor: string }) {
  return (
    <div style={{ background: '#fff', border: '1px solid var(--mf-ink-100)', borderRadius: 6, padding: '12px 14px' }}>
      <div style={{ fontSize: 10, fontWeight: 600, color: 'var(--mf-ink-400)', letterSpacing: '0.06em', textTransform: 'uppercase', marginBottom: 6 }}>{label}</div>
      <div style={{ fontFamily: 'var(--mf-font-mono)', fontSize: 'var(--mf-text-xl)', fontWeight: 800, color: 'var(--mf-navy-900)', letterSpacing: '-0.02em', lineHeight: 1 }}>{value}</div>
      <div style={{ marginTop: 4, fontSize: 'var(--mf-text-xs)', color: detalheColor, fontWeight: 500 }}>{detalhe}</div>
    </div>
  );
}

function FilterChip({ children, active }: { children: React.ReactNode; active?: boolean }) {
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', height: 24, padding: '0 8px', borderRadius: 4, border: active ? '1px solid var(--mf-navy-400)' : '1px solid var(--mf-ink-200)', background: active ? 'var(--mf-navy-800)' : 'transparent', color: active ? '#fff' : 'var(--mf-ink-500)', fontSize: 11, fontWeight: 500, cursor: 'pointer', userSelect: 'none' as const, whiteSpace: 'nowrap' as const }}>
      {children}
    </span>
  );
}

function StatusPill({ status }: { status: string }) {
  const c = STATUS_CFG[status] ?? STATUS_CFG['Aberta'];
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, background: c.bg, color: c.color, borderRadius: 99, padding: '2px 7px', fontSize: 11, fontWeight: 600 }}>
      <span style={{ width: 5, height: 5, borderRadius: '50%', background: c.dot }} />{status}
    </span>
  );
}

function PriorPill({ p }: { p: 'Alta'|'Média'|'Baixa' }) {
  const c = PRIOR_CFG[p];
  return <span style={{ background: c.bg, color: c.color, borderRadius: 3, padding: '2px 7px', fontSize: 11, fontWeight: 600 }}>{p}</span>;
}

function OsInfoCell({ k, v, border }: { k: string; v: React.ReactNode; border?: boolean }) {
  return (
    <div style={{ padding: '10px 16px', borderLeft: border ? '1px solid var(--mf-ink-100)' : undefined }}>
      <div style={{ fontSize: 10, fontWeight: 600, color: 'var(--mf-ink-400)', letterSpacing: '0.06em', textTransform: 'uppercase', marginBottom: 3 }}>{k}</div>
      <div style={{ fontSize: 'var(--mf-text-sm)', fontWeight: 500, color: 'var(--mf-ink-800)' }}>{v}</div>
    </div>
  );
}

function Label({ children }: { children: React.ReactNode }) {
  return <div style={{ fontSize: 10, fontWeight: 700, color: 'var(--mf-ink-400)', letterSpacing: '0.08em', textTransform: 'uppercase', marginBottom: 8 }}>{children}</div>;
}

type BtnSize = 'sm' | 'md' | 'lg';

function MfButton({ variant = 'primary', size = 'md', disabled, loading, children }: {
  variant?: BtnVariant; size?: BtnSize; disabled?: boolean; loading?: boolean; children: React.ReactNode;
}) {
  const sz = { sm: { h: 28, p: '0 10px', f: 'var(--mf-text-xs)' }, md: { h: 34, p: '0 14px', f: 'var(--mf-text-sm)' }, lg: { h: 40, p: '0 18px', f: 'var(--mf-text-md)' } }[size];
  const vars: Record<BtnVariant, React.CSSProperties> = {
    primary:   { background: 'var(--mf-navy-800)', color: '#fff',                  border: 'none' },
    secondary: { background: 'var(--mf-ink-100)',  color: 'var(--mf-ink-700)',      border: '1px solid var(--mf-ink-200)' },
    ghost:     { background: 'transparent',        color: 'var(--mf-ink-600)',      border: 'none' },
    outline:   { background: 'transparent',        color: 'var(--mf-navy-700)',     border: '1px solid var(--mf-navy-300)' },
    danger:    { background: 'var(--mf-danger-500)',color: '#fff',                  border: 'none' },
    gold:      { background: 'var(--mf-gold-500)', color: 'var(--mf-navy-900)',     border: 'none' },
  };
  return (
    <button disabled={disabled || loading} style={{ display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 5, cursor: disabled || loading ? 'not-allowed' : 'pointer', fontFamily: 'var(--mf-font-sans)', fontWeight: 600, borderRadius: 5, outline: 'none', opacity: disabled ? 0.5 : 1, height: sz.h, padding: sz.p, fontSize: sz.f, transition: 'opacity 120ms', whiteSpace: 'nowrap', ...vars[variant] }}>
      {loading && <span style={{ width: 11, height: 11, border: '2px solid currentColor', borderTopColor: 'transparent', borderRadius: '50%', animation: 'mf-spin 0.7s linear infinite', display: 'inline-block', flexShrink: 0 }} />}
      {children}
    </button>
  );
}

function MfField({ label, placeholder, value, type = 'text', readOnly, disabled, error, multiline }: {
  label: string; placeholder?: string; value?: string; type?: string;
  readOnly?: boolean; disabled?: boolean; error?: string; multiline?: boolean;
}) {
  const base: React.CSSProperties = { width: '100%', padding: '0 8px', height: 32, border: `1px solid ${error ? 'var(--mf-danger-400)' : 'var(--mf-ink-200)'}`, borderRadius: 4, fontSize: 'var(--mf-text-sm)', color: disabled ? 'var(--mf-ink-300)' : 'var(--mf-ink-800)', background: disabled ? 'var(--mf-ink-50)' : readOnly ? 'var(--mf-paper)' : '#fff', outline: 'none', fontFamily: 'var(--mf-font-sans)', boxSizing: 'border-box' as const };
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
      <label style={{ fontSize: 11, fontWeight: 600, color: 'var(--mf-ink-600)', letterSpacing: '0.02em' }}>{label}</label>
      {multiline ? <textarea placeholder={placeholder} disabled={disabled} style={{ ...base, height: 60, padding: '6px 8px', resize: 'none' }} /> : <input type={type} placeholder={placeholder} defaultValue={value} readOnly={readOnly} disabled={disabled} style={base} />}
      {error && <span style={{ fontSize: 10, color: 'var(--mf-danger-600)', fontWeight: 500 }}>{error}</span>}
    </div>
  );
}
