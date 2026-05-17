import '@/styles/marineflow-tokens.css';

/* ─────────────────────────────────────────────────────────────────────────────
   Marineflow ERP — Comparativo de Previews UI/UX
   Página estática. Zero dados reais. Zero chamadas externas.
   Acessível em /design-preview-compare — role admin.
───────────────────────────────────────────────────────────────────────────── */

type VersionCard = {
  tag: string;
  name: string;
  fase: string;
  status: 'aprovado' | 'atual' | 'em-progresso';
  desc: string;
  route: string;
  label: string;
  pontosFortres: string;
  limitacao: string;
};

const VERSIONS: VersionCard[] = [
  {
    tag: 'V01',
    name: 'V01 — Preview operacional aprovado',
    fase: 'Fase 1.2',
    status: 'aprovado',
    desc: 'Primeira versão com linguagem operacional náutica, tabela de OS com highlight de linhas críticas, card de OS detalhado, WhatsApp inbox mockado, tokens de design isolados e microcopy real (Marine Parts BR, Cabo NMEA 2000, Fusível ANL 150A, Bomba Rule 2000).',
    route: '/design-preview-v01',
    label: 'Abrir V01',
    pontosFortres: 'Corpo operacional limpo, densidade controlada, tabela como centro da tela, equilíbrio entre dados e hierarquia, linguagem náutica específica.',
    limitacao: 'Identidade HBR Systems menos presente no cabeçalho; menos distinção visual entre ferramenta e template genérico.',
  },
  {
    tag: 'V02',
    name: 'V02 — Identidade HBR Systems',
    fase: 'Fase 1.4',
    status: 'aprovado',
    desc: 'Identidade HBR Systems reforçada: marca tipográfica (HBR / SYSTEMS), linha fluida dourada abaixo do header, fundo quente #F7F6F2, cabeçalho de tabela navy-900, seções com borda esquerda dourada, KpiCards com topo colorido por severidade, raios reduzidos e rodapé 2 linhas com slogan.',
    route: '/design-preview-v02',
    label: 'Abrir V02',
    pontosFortres: 'Cabeçalho com marca HBR Systems clara, linhas douradas e separadores de identidade, fundo quente, navy profundo no header.',
    limitacao: 'Evolução visual pequena em relação à V01; barra de contexto muito escura (#010B13) pode pesar; alguns elementos mais institucionais que operacionais.',
  },
  {
    tag: 'V03',
    name: 'V03 — Híbrida curada',
    fase: 'Fase 1.5',
    status: 'atual',
    desc: 'Combinação curada: cabeçalho e identidade da V02 (HBR mark, linha fluida, navy profundo) com corpo operacional da V01 (borda crítica 3px, rótulos de seção operacionais, "WhatsApp Inbox", subtitle específico de OS, botões e inputs 32px). Fundo quente, rodapé HBR, sem barra de contexto excessivamente escura.',
    route: '/design-preview-v03',
    label: 'Abrir V03',
    pontosFortres: 'Combina cabeçalho/linhas da V02 com equilíbrio operacional da V01. Card radius 6px (entre V01=8 e V02=5). Botões confortáveis (5px, 28/34px). Alertas com borda 3px. Barra de contexto navy-950 — menos pesada.',
    limitacao: 'Versão candidata para base visual. Aguarda validação visual manual para confirmar se o equilíbrio híbrido foi bem-sucedido.',
  },
];

const CURRENT: Omit<VersionCard, 'tag' | 'fase' | 'status' | 'pontosFortres' | 'limitacao'> = {
  name: 'Versão atual',
  desc: 'Alias para a versão mais recente. Sempre aponta para o último snapshot candidato. Atualmente aponta para V03.',
  route: '/design-preview',
  label: 'Abrir /design-preview',
};

const STATUS_LABEL: Record<VersionCard['status'], { label: string; bg: string; color: string }> = {
  aprovado:       { label: 'Aprovado',      bg: 'var(--mf-success-100)', color: 'var(--mf-success-700)' },
  atual:          { label: 'Candidata',     bg: 'var(--mf-navy-100)',    color: 'var(--mf-navy-700)'    },
  'em-progresso': { label: 'Em progresso',  bg: 'var(--mf-warning-100)', color: 'var(--mf-warning-700)' },
};

export default function DesignPreviewIndex() {
  return (
    <div style={{ fontFamily: 'var(--mf-font-sans)', background: 'var(--mf-paper)', color: 'var(--mf-ink-900)', minHeight: '100vh', fontSize: 'var(--mf-text-base)', lineHeight: 1.5 }}>

      {/* ── Header ──────────────────────────────────────────────────────── */}
      <div style={{ position: 'sticky', top: 0, zIndex: 40, background: 'var(--mf-navy-900)', borderBottom: '1px solid var(--mf-navy-800)', height: 48, display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 20px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{ width: 26, height: 26, background: 'rgba(200,162,75,0.12)', borderRadius: 6, display: 'grid', placeItems: 'center', fontWeight: 700, fontSize: 12, color: 'var(--mf-gold-400)', border: '1px solid rgba(200,162,75,0.2)' }}>M</div>
          <span style={{ color: 'var(--mf-ink-100)', fontWeight: 600, fontSize: 'var(--mf-text-md)', letterSpacing: '-0.01em' }}>Marineflow ERP</span>
          <span style={{ color: 'var(--mf-ink-500)', fontSize: 'var(--mf-text-sm)' }}>·</span>
          <span style={{ color: 'var(--mf-ink-400)', fontSize: 'var(--mf-text-xs)' }}>Comparativo UI/UX</span>
        </div>
        <span style={{ background: 'rgba(200,162,75,0.1)', color: 'var(--mf-gold-400)', fontSize: 10, fontWeight: 700, padding: '2px 7px', borderRadius: 3, border: '1px solid rgba(200,162,75,0.2)', letterSpacing: '0.06em', textTransform: 'uppercase' }}>PREVIEW</span>
      </div>

      {/* ── Aviso de ambiente ───────────────────────────────────────────── */}
      <div style={{ background: 'var(--mf-navy-950)', borderBottom: '1px solid var(--mf-navy-800)', padding: '6px 20px', display: 'flex', alignItems: 'center', gap: 8 }}>
        <span style={{ fontSize: 10, fontWeight: 700, letterSpacing: '0.08em', textTransform: 'uppercase', color: 'var(--mf-ink-500)' }}>Ambiente de preview visual</span>
        <span style={{ color: 'var(--mf-ink-600)', fontSize: 'var(--mf-text-xs)' }}>—</span>
        <span style={{ fontSize: 'var(--mf-text-xs)', color: 'var(--mf-ink-500)' }}>sem dados reais · zero chamadas externas · feat/ui-design-phase-1-preview</span>
      </div>

      {/* ── Conteúdo ────────────────────────────────────────────────────── */}
      <div style={{ maxWidth: 900, margin: '0 auto', padding: '32px 20px 64px' }}>

        {/* Título da página */}
        <div style={{ marginBottom: 32 }}>
          <h1 style={{ margin: '0 0 6px', fontSize: 'var(--mf-text-2xl)', fontWeight: 800, color: 'var(--mf-navy-900)', letterSpacing: '-0.02em' }}>
            Comparativo de previews UI/UX
          </h1>
          <p style={{ margin: 0, fontSize: 'var(--mf-text-sm)', color: 'var(--mf-ink-500)', lineHeight: 1.6 }}>
            Snapshots visuais para comparação incremental do redesign do Marineflow ERP.<br />
            Cada versão é um arquivo preservado e não deve ser alterado após aprovação.
          </p>
        </div>

        {/* Versão atual — alias */}
        <div style={{ marginBottom: 24 }}>
          <div style={{ fontSize: 10, fontWeight: 700, color: 'var(--mf-ink-400)', letterSpacing: '0.08em', textTransform: 'uppercase', marginBottom: 10 }}>Versão ativa</div>
          <div style={{ background: '#fff', border: '1px solid var(--mf-navy-200)', borderRadius: 8, padding: '16px 20px', display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 20 }}>
            <div style={{ flex: 1 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
                <span style={{ fontWeight: 700, fontSize: 'var(--mf-text-md)', color: 'var(--mf-navy-900)' }}>{CURRENT.name}</span>
                <span style={{ background: 'var(--mf-navy-100)', color: 'var(--mf-navy-700)', fontSize: 11, fontWeight: 600, padding: '1px 7px', borderRadius: 3 }}>→ V03</span>
              </div>
              <p style={{ margin: 0, fontSize: 'var(--mf-text-sm)', color: 'var(--mf-ink-500)', lineHeight: 1.55 }}>{CURRENT.desc}</p>
            </div>
            <a href={CURRENT.route} style={{ display: 'inline-flex', alignItems: 'center', height: 34, padding: '0 14px', background: 'var(--mf-navy-800)', color: '#fff', borderRadius: 5, fontSize: 'var(--mf-text-sm)', fontWeight: 600, textDecoration: 'none', whiteSpace: 'nowrap', flexShrink: 0 }}>
              {CURRENT.label}
            </a>
          </div>
        </div>

        {/* Snapshots com notas decisórias */}
        <div>
          <div style={{ fontSize: 10, fontWeight: 700, color: 'var(--mf-ink-400)', letterSpacing: '0.08em', textTransform: 'uppercase', marginBottom: 10 }}>Snapshots — leitura comparativa</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            {VERSIONS.map(v => {
              const st = STATUS_LABEL[v.status];
              return (
                <div key={v.tag} style={{ background: '#fff', border: '1px solid var(--mf-ink-100)', borderRadius: 8, overflow: 'hidden' }}>
                  <div style={{ padding: '14px 20px', display: 'flex', alignItems: 'flex-start', gap: 20 }}>
                    {/* Tag lateral */}
                    <div style={{ flexShrink: 0, width: 48, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, paddingTop: 2 }}>
                      <span style={{ fontFamily: 'var(--mf-font-mono)', fontSize: 'var(--mf-text-lg)', fontWeight: 800, color: 'var(--mf-navy-700)', lineHeight: 1 }}>{v.tag}</span>
                      <span style={{ fontSize: 10, color: 'var(--mf-ink-400)', fontFamily: 'var(--mf-font-mono)' }}>{v.fase}</span>
                    </div>

                    {/* Conteúdo */}
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 5 }}>
                        <span style={{ fontWeight: 700, fontSize: 'var(--mf-text-sm)', color: 'var(--mf-ink-900)' }}>{v.name}</span>
                        <span style={{ background: st.bg, color: st.color, fontSize: 11, fontWeight: 600, padding: '1px 7px', borderRadius: 3 }}>{st.label}</span>
                      </div>
                      <p style={{ margin: '0 0 10px', fontSize: 'var(--mf-text-sm)', color: 'var(--mf-ink-500)', lineHeight: 1.55 }}>{v.desc}</p>
                    </div>

                    {/* Ação */}
                    <div style={{ flexShrink: 0 }}>
                      <a href={v.route} style={{ display: 'inline-flex', alignItems: 'center', height: 30, padding: '0 12px', background: 'transparent', color: 'var(--mf-navy-700)', border: '1px solid var(--mf-navy-300)', borderRadius: 5, fontSize: 'var(--mf-text-xs)', fontWeight: 600, textDecoration: 'none', whiteSpace: 'nowrap' }}>
                        {v.label}
                      </a>
                    </div>
                  </div>

                  {/* Notas decisórias */}
                  <div style={{ borderTop: '1px solid var(--mf-ink-50)', background: 'var(--mf-paper)', padding: '10px 20px 10px 68px', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
                    <div>
                      <div style={{ fontSize: 10, fontWeight: 700, color: 'var(--mf-success-700)', letterSpacing: '0.06em', textTransform: 'uppercase', marginBottom: 3 }}>Pontos fortes</div>
                      <p style={{ margin: 0, fontSize: 'var(--mf-text-xs)', color: 'var(--mf-ink-600)', lineHeight: 1.55 }}>{v.pontosFortres}</p>
                    </div>
                    <div>
                      <div style={{ fontSize: 10, fontWeight: 700, color: 'var(--mf-warning-700)', letterSpacing: '0.06em', textTransform: 'uppercase', marginBottom: 3 }}>Limitação / observação</div>
                      <p style={{ margin: 0, fontSize: 'var(--mf-text-xs)', color: 'var(--mf-ink-600)', lineHeight: 1.55 }}>{v.limitacao}</p>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Próximas versões — placeholder */}
        <div style={{ marginTop: 24, background: 'var(--mf-ink-50)', border: '1px dashed var(--mf-ink-200)', borderRadius: 8, padding: '14px 20px' }}>
          <div style={{ fontSize: 10, fontWeight: 700, color: 'var(--mf-ink-400)', letterSpacing: '0.08em', textTransform: 'uppercase', marginBottom: 6 }}>Próximas versões</div>
          <p style={{ margin: 0, fontSize: 'var(--mf-text-sm)', color: 'var(--mf-ink-400)', lineHeight: 1.5 }}>
            V04… serão adicionadas aqui à medida que novas iterações forem aprovadas.<br />
            Cada versão preserva o estado visual exato do snapshot no momento da aprovação.
          </p>
        </div>

        {/* Nota sobre logo HBR Systems */}
        <div style={{ marginTop: 16, background: 'var(--mf-gold-50)', border: '1px solid var(--mf-gold-200)', borderRadius: 6, padding: '10px 14px' }}>
          <div style={{ fontSize: 10, fontWeight: 700, color: 'var(--mf-gold-700)', letterSpacing: '0.08em', textTransform: 'uppercase', marginBottom: 4 }}>Nota — Logo HBR Systems</div>
          <p style={{ margin: 0, fontSize: 'var(--mf-text-xs)', color: 'var(--mf-gold-700)', lineHeight: 1.55 }}>
            O logotipo oficial HBR Systems deve ser adicionado futuramente em <code style={{ fontFamily: 'var(--mf-font-mono)', background: 'var(--mf-gold-100)', padding: '0 4px', borderRadius: 2 }}>public/brand/hbr-systems-logo.png</code> e referenciado nos cabeçalhos dos previews. Não foi incluído nesta fase para evitar alteração de assets de produção.
          </p>
        </div>

        {/* Footer */}
        <div style={{ marginTop: 32, paddingTop: 16, borderTop: '1px solid var(--mf-ink-100)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span style={{ fontSize: 'var(--mf-text-xs)', color: 'var(--mf-ink-300)' }}>Marineflow ERP · Comparativo UI/UX · Fase 1.5 · {new Date().toLocaleDateString('pt-BR')}</span>
          <span style={{ fontSize: 10, color: 'var(--mf-ink-200)', fontFamily: 'var(--mf-font-mono)' }}>feat/ui-design-phase-1-preview · HBR Systems</span>
        </div>
      </div>

      <style>{`@keyframes mf-spin { to { transform: rotate(360deg); } }`}</style>
    </div>
  );
}
