/**
 * As telas da Agenda de Produção (Fase 3, P7a — 24/10/2026): Agenda › Semana, Agenda › Carteira, o cartão "Plano" da OS
 * e as linhas da grade como a equipe (payees).
 *
 * Tudo sai pronto do banco (migration 20261026100600): o texto, a cor da carga (pela carga_max de agenda_config), a idade
 * em dias úteis e a cor dela, a próxima ação e quem trava. A tela não tem número de parâmetro: a jornada do dia vem de
 * agenda_config.jornada_horas (useAgendaConfig) e o JORNADA_PADRAO_HORAS de _shared/agenda-dia.ts fica só como o valor
 * de quando a migration ainda não foi aplicada.
 *
 * PLANO B (o padrão de _shared/porta-ausente.ts e dos hooks das Fases 1 e 2): se a tela sair antes das migrations, ela
 * não quebra.
 *   · agenda_config ausente (PGRST205/42P01), sem linha ou fora do alcance do login (o técnico: a RLS é de
 *     admin/financeiro) = a jornada padrão e a agenda desligada — a tela de antes;
 *   · a função da tela ausente (PGRST202/42883) = null: quem chama mostra a tela de antes, sem erro;
 *   · qualquer outro erro de leitura LANÇA e a tela mostra o erro — nunca "nada marcado".
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { JORNADA_PADRAO_HORAS } from '../../supabase/functions/_shared/agenda-dia';
import { ehPortaAusente, ehSemDireitoNaPorta } from '../../supabase/functions/_shared/porta-ausente';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Cliente = any;

export type ModoDaAgenda = 'desligado' | 'sombra' | 'ligado';

export interface AgendaConfigDaTela {
  jornada_horas: number;
  carga_max: number | null;
  modo_leitura: ModoDaAgenda;
  modo_proposta: ModoDaAgenda;
  /** a linha veio do banco (false = o padrão de quando a migration não foi aplicada ou o login não lê) */
  doBanco: boolean;
}

/** Só enquanto a migration não foi aplicada (ou para quem não lê agenda_config): a tela de antes. */
export const CONFIG_DE_ANTES: AgendaConfigDaTela = {
  jornada_horas: JORNADA_PADRAO_HORAS,
  carga_max: null,
  modo_leitura: 'desligado',
  modo_proposta: 'desligado',
  doBanco: false,
};

function lerModo(v: unknown): ModoDaAgenda {
  const s = typeof v === 'string' ? v.trim().toLowerCase() : '';
  return s === 'sombra' || s === 'ligado' ? s : 'desligado';
}

/** A tabela não existe (PostgREST PGRST205: fora do cache do esquema; Postgres 42P01)? */
export function ehTabelaAusente(e: unknown): boolean {
  if (!e || typeof e !== 'object') return false;
  const code = (e as { code?: unknown }).code;
  return code === 'PGRST205' || code === '42P01';
}

/**
 * agenda_config para a tela. Só as colunas da Fase 1 (as das fases seguintes podem ainda não existir em produção: pedir
 * uma coluna que não existe dá erro). Tabela ausente ou sem linha = CONFIG_DE_ANTES; outro erro lança.
 */
export async function lerAgendaConfig(db: Cliente): Promise<AgendaConfigDaTela> {
  const { data, error } = await db
    .from('agenda_config')
    .select('jornada_horas, carga_max, modo_leitura, modo_proposta')
    .maybeSingle();
  if (error) {
    if (ehTabelaAusente(error)) return CONFIG_DE_ANTES;
    throw error;
  }
  if (!data) return CONFIG_DE_ANTES;
  const jornada = Number(data.jornada_horas);
  return {
    jornada_horas: Number.isFinite(jornada) && jornada > 0 ? jornada : JORNADA_PADRAO_HORAS,
    carga_max: data.carga_max == null ? null : Number(data.carga_max),
    modo_leitura: lerModo(data.modo_leitura),
    modo_proposta: lerModo(data.modo_proposta),
    doBanco: true,
  };
}

export const CHAVE_AGENDA_CONFIG = ['agenda-config-da-tela'] as const;

/**
 * Os parâmetros da agenda para a tela. Nunca derruba a tela: enquanto carrega ou se a leitura falhar, `config` é o de
 * antes (a jornada padrão, a agenda desligada) — o erro fica em `error` para quem quiser mostrar.
 */
export function useAgendaConfig() {
  const q = useQuery({
    queryKey: CHAVE_AGENDA_CONFIG,
    queryFn: () => lerAgendaConfig(supabase),
    staleTime: 60_000,
    retry: false,
  });
  return { ...q, config: q.data ?? CONFIG_DE_ANTES };
}

/** A jornada do dia para quem não está num componente (as mutações): a mesma consulta, pelo cache. */
export async function jornadaDaAgenda(qc: ReturnType<typeof useQueryClient>): Promise<number> {
  try {
    const c = await qc.fetchQuery({ queryKey: CHAVE_AGENDA_CONFIG, queryFn: () => lerAgendaConfig(supabase), staleTime: 60_000 });
    return c.jornada_horas;
  } catch {
    return JORNADA_PADRAO_HORAS;
  }
}

/** Chama uma leitura da tela: a função ausente = null (a tela de antes); outro erro lança. */
async function lerDaTela<T>(nome: string, args: Record<string, unknown>): Promise<T | null> {
  const { data, error } = await (supabase.rpc as Cliente)(nome, args);
  if (error) {
    if (ehPortaAusente(error)) return null;
    throw new Error((error as { message?: string }).message || 'O banco não respondeu a agenda de produção.');
  }
  return (data ?? null) as T | null;
}

// ─── Agenda › Semana ────────────────────────────────────────────────────────────────────────────────

export type CorDaCarga = 'verde' | 'ambar' | 'vermelho';

export interface PessoaDoDia {
  payee_id: string;
  nome: string;
  eh_dono: boolean;
  meios_usados: number;
  meios_esperados: number;
  pct: number | null;
  cor: CorDaCarga;
  /** "Roberto 2/2" */
  texto: string;
}

export interface BlocoDoDia {
  os: string;
  numero: string;
  cliente: string | null;
  bem: string | null;
  local: string | null;
  hora: string | null;
  pessoas_texto: string | null;
  dia_n: number | null;
  dias_total: number | null;
  /** "dia 1 de 3" (só quando a OS tem mais de um dia) */
  dia_texto: string | null;
  confirmado_cliente: boolean;
  reserva: boolean;
  /** "Reserva, a confirmar" */
  reserva_texto: string | null;
  condicao: string | null;
  tipo: string | null;
  fixada: boolean;
  resultado: string | null;
  resultado_texto: string | null;
}

export interface DiaDaSemana {
  dia: string;
  /** "TER 03/11" */
  rotulo: string;
  hoje: boolean;
  feriado: string | null;
  pessoas: PessoaDoDia[];
  blocos: BlocoDoDia[];
  /** "livre: Roberto tarde" */
  livre_texto: string | null;
}

export interface MudancaDoGestor {
  acao_id: string | null;
  tipo: string;
  os: string | null;
  numero: string | null;
  texto: string;
  desfazivel: boolean;
  desfeita: boolean;
  desfazivel_ate: string | null;
  /** desfazer cancela a cobrança da conclusão ou apaga a diária lançada: a tela pede confirmação */
  perda: 'cobranca' | 'diaria' | null;
}

export interface DecisaoAberta {
  pergunta_id: string;
  n: number;
  tipo: string;
  texto: string;
}

export interface SemanaDeProducao {
  modo: ModoDaAgenda;
  em_teste: boolean;
  de: string;
  ate: string;
  titulo: string;
  resumo: string | null;
  comprometido_pct: number | null;
  livre_diarias: number | null;
  ppc_anterior: number | null;
  livre_de_verdade: string | null;
  dias: DiaDaSemana[];
  mudancas: MudancaDoGestor[];
  decisoes: DecisaoAberta[];
  como_responder: string | null;
}

/** A semana de `de` (yyyy-mm-dd; sem ele, a de hoje). null = a tela ainda não está no banco. */
export function useSemanaProducao(de: string | null, habilitado = true) {
  return useQuery({
    queryKey: ['agenda-producao', 'semana', de],
    queryFn: () => lerDaTela<SemanaDeProducao>('agenda_tela_semana', { p_de: de }),
    enabled: habilitado,
    staleTime: 30_000,
    retry: false,
  });
}

// ─── Agenda › Carteira ──────────────────────────────────────────────────────────────────────────────

export type CorDaIdade = 'normal' | 'laranja' | 'vermelho';

export interface GrupoDaCarteira {
  chave: string;
  rotulo: string;
  n: number;
}

export interface CartaoDaCarteiraDados {
  os: string;
  numero: string;
  cliente: string | null;
  bem: string | null;
  grupo: string;
  estado: string | null;
  desde: string | null;
  idade_du: number;
  /** "há 23 dias úteis" */
  idade_texto: string;
  cor: CorDaIdade;
  proxima_acao: string | null;
  quem_trava: 'voce' | 'cliente' | 'fornecedor' | 'equipe' | null;
  /** "trava: você" */
  quem_trava_texto: string | null;
}

export interface CarteiraDeProducao {
  grupos: GrupoDaCarteira[];
  cartoes: CartaoDaCarteiraDados[];
  modo: ModoDaAgenda;
}

export function useCarteiraProducao(habilitado = true) {
  return useQuery({
    queryKey: ['agenda-producao', 'carteira'],
    queryFn: () => lerDaTela<CarteiraDeProducao>('agenda_tela_carteira', {}),
    enabled: habilitado,
    staleTime: 30_000,
    retry: false,
  });
}

// ─── O cartão "Plano" da OS ─────────────────────────────────────────────────────────────────────────

export interface MaterialDoPlano {
  descricao: string;
  nivel: 'A' | 'B' | 'C' | 'D' | 'E';
  nivel_texto: string;
  situacao: string | null;
  previsao: string | null;
  trecho: string | null;
  critico: boolean;
  fornecedor: string | null;
}

export interface DiaDoPlano {
  dia: string;
  rotulo: string;
  pessoas_texto: string | null;
  dia_texto: string | null;
  meios: number | null;
  resultado: string | null;
  resultado_texto: string | null;
  motivo_texto: string | null;
  /** só se a diária foi lançada; o valor nunca aparece */
  diaria: 'lançada' | 'a confirmar' | null;
}

/** Uma mensagem ao cliente desta OS, como o dono lê (Fase 5, P6: _agenda_cliente_da_os). */
export interface MensagemAoClienteDoPlano {
  tipo: string;
  /** "Confirmação", "Aviso de atraso", "Véspera, com a pergunta do acesso"… */
  tipo_texto: string;
  /** "amanhã às 09:00", "agora", "qui 22/10 às 10:00" */
  quando_texto: string | null;
  estado: string;
  /** "espera você", "mandada; sem resposta", "em teste: sairia", "você segurou: não saiu"… (pode citar *segura cliente <nome>*) */
  estado_texto: string | null;
  /** o texto do banco, inteiro (nunca valor, número de OS nem link) */
  texto: string;
  em_teste: boolean;
  espera_voce: boolean;
}

/** O bloco "Cliente" do cartão (Fase 5, P6). Nenhum botão de mandar: a aprovação é pela palavra, na conversa. */
export interface ClienteDoPlano {
  modo: ModoDaAgenda;
  em_teste: boolean;
  em_teste_texto: string | null;
  nome: string | null;
  telefone_ok: boolean;
  conversou: boolean;
  /** o cliente não recebe (pediu para parar, cadastro inativo ou número bloqueado) */
  opt_out: boolean;
  /** "sem telefone no cadastro" | "pediu para não receber mensagens" | "não escreveu para a HBR no último ano…" | null */
  contato_texto: string | null;
  /** como o serviço é dito ao cliente ("a instalação do compressor") */
  servico: string | null;
  prometido: {
    tipo: 'firme' | 'faixa' | 'condicional';
    de: string;
    ate: string;
    original_ate: string | null;
    fonte: 'mensagem' | 'dono' | 'confirmacao' | null;
    /** "qui 05/11 (data firme, por mensagem da agenda em qui 22/10)" */
    texto: string;
    /** "Pode atrasar: agora a previsão é de qui 12/11 a sex 13/11." | null */
    risco_texto: string | null;
  } | null;
  confirmado_texto: string | null;
  /** as 5 mais recentes desta OS */
  mensagens: MensagemAoClienteDoPlano[];
  /** quantas passam das 5 (*agenda clientes* mostra) */
  mensagens_mais: number;
  /** o texto só em ligado, com *manda cliente <nome>* / *segura cliente <nome>* */
  esperando_voce: { n: number; texto: string | null };
}

export interface PlanoDaOsDados {
  /** Fase 5 (P6): ausente antes da migration 20261028100600; null sem o cliente na OS */
  cliente?: ClienteDoPlano | null;
  os: string;
  numero: string;
  status: string;
  estado: string | null;
  marcos: { texto: string; sem_entrega_du: number | null };
  pode_entregar: boolean;
  duracao: {
    dias: number | null;
    fonte: 'dono' | 'aceita' | 'sugerida' | null;
    fonte_texto: string | null;
    faixa: { otimista: number | null; realista: number | null };
    faixa_texto: string | null;
    texto: string | null;
  };
  presenca_dono: { valor: string | null; pela_regra: boolean; texto: string };
  material: { estado: string | null; itens: MaterialDoPlano[] };
  janela: {
    bem_indisponivel: string | null;
    nao_antes_de: string | null;
    motivo: string | null;
    precisa_ate: string | null;
    nao_antes_texto: string | null;
    precisa_ate_texto: string | null;
  };
  prometido_planejado: { precisa_ate: string | null; fim_publicado: string | null; folga_du: number | null; texto: string | null };
  planejado_realizado: DiaDoPlano[];
  intervencoes: { dia: string; texto: string }[];
}

export function usePlanoDaOs(osId: string | undefined, habilitado = true) {
  return useQuery({
    queryKey: ['agenda-producao', 'plano', osId],
    queryFn: () => lerDaTela<PlanoDaOsDados>('os_plano_da_os', { p_os: osId }),
    enabled: !!osId && habilitado,
    staleTime: 30_000,
    retry: false,
  });
}

// ─── As linhas da grade técnico × dia ───────────────────────────────────────────────────────────────

export interface PessoaDaGrade {
  payee_id: string;
  nome: string;
  nome_curto: string | null;
  eh_dono: boolean;
  /** o login da pessoa (casa com a OS e a tarefa); null = a pessoa não tem login */
  app_user_id: string | null;
}

/**
 * As linhas da grade como a equipe da agenda (o dono e quem tem perfil de diária e padrão). null = a tela de antes (a
 * função ainda não está no banco, ou o login não é admin/financeiro: a grade volta às linhas dos técnicos).
 */
export async function lerEquipeDaGrade(db: Cliente): Promise<PessoaDaGrade[] | null> {
  const { data, error } = await db.rpc('agenda_equipe_da_grade', {});
  if (error) {
    if (ehPortaAusente(error) || ehSemDireitoNaPorta(error)) return null;
    throw new Error((error as { message?: string }).message || 'O banco não respondeu a equipe da agenda.');
  }
  return Array.isArray(data) ? (data as PessoaDaGrade[]) : null;
}

export function useEquipeDaGrade(habilitado = true) {
  return useQuery({
    queryKey: ['agenda-producao', 'equipe-da-grade'],
    queryFn: () => lerEquipeDaGrade(supabase),
    enabled: habilitado,
    staleTime: 5 * 60_000,
    retry: false,
  });
}

// ─── As escritas da tela (a ordem exata do dono) ────────────────────────────────────────────────────

interface RespostaDaEscrita {
  ok?: boolean;
  texto?: string;
}

async function escrever(nome: string, args: Record<string, unknown>, padrao: string): Promise<string> {
  const { data, error } = await (supabase.rpc as Cliente)(nome, args);
  if (error) throw new Error((error as { message?: string }).message || padrao);
  const r = (data ?? {}) as RespostaDaEscrita;
  const texto = String(r.texto ?? '').trim();
  if (r.ok === false) throw new Error(texto || padrao);
  return texto;
}

function invalidarProducao(qc: ReturnType<typeof useQueryClient>) {
  qc.invalidateQueries({ queryKey: ['agenda-producao'] });
  qc.invalidateQueries({ queryKey: ['service-orders'] });
}

/** O Desfazer de "O que eu mudei sozinho": devolve a frase do banco. */
export function useDesfazerAcao() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (acaoId: string) => escrever('agenda_desfazer_pela_tela', { p_acao: acaoId }, 'Não deu para desfazer.'),
    onSuccess: () => invalidarProducao(qc),
  });
}

/** O "Corrigir dias" do cartão Plano: a duração dita pelo dono (meio em meio dia). */
export function usePlanejarPelaTela() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ osId, dias }: { osId: string; dias: number }) =>
      escrever('os_planejar_pela_tela', { p_os: osId, p_dias: dias }, 'O banco não gravou a duração.'),
    onSuccess: () => invalidarProducao(qc),
  });
}

/** O botão Entregue do cartão Plano: a entrega pela porta (os_registrar_marco, via tela). */
export function useRegistrarEntrega() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (osId: string) =>
      escrever('os_registrar_marco', { p_os: osId, p_marco: 'entrega', p_via: 'tela' }, 'O banco não registrou a entrega.'),
    onSuccess: () => invalidarProducao(qc),
  });
}
