/**
 * Como chamar a "unidade" da OS (barco, motorhome, trailer, camper) — decisão 9 do relatório de
 * 21/10/2026, pedido do dono: "Embarcação: Iveco Daily" não faz sentido.
 *
 * Não há em português uma palavra só para barco e motorhome (a lei também separa: embarcação é da
 * Marinha, NORMAM-211/212; motorhome, trailer e camper são do trânsito, CTB/CONTRAN). Então:
 *   - com UMA unidade à vista (documento, ficha, mensagem, via do técnico), o rótulo é o próprio
 *     tipo: "Motorhome: Iveco Daily · placa ABC1D23", "Lancha: Netuno II";
 *   - sem unidade escolhida (menu, lista, campo vazio), o termo geral: "Embarcação ou veículo".
 *
 * Módulo puro (sem import): o app (src/lib/unidade.ts) e as funções do servidor (PDF do
 * assistente, mensagens) usam o mesmo texto.
 */

export const TERMO_GERAL = 'Embarcação ou veículo';
export const TERMO_GERAL_PLURAL = 'Embarcações e veículos';

export type GrupoDoTipo = 'embarcacao' | 'veiculo' | 'outro';

const EMBARCACOES = ['lancha', 'veleiro', 'catamarã', 'catamara', 'jet ski', 'moto aquática', 'moto aquatica', 'barco', 'embarcação', 'embarcacao', 'outra embarcação', 'outra embarcacao', 'escuna', 'traineira', 'bote'];
const VEICULOS = ['motorhome', 'trailer', 'camper', 'automóvel', 'automovel', 'van', 'picape', 'veículo', 'veiculo', 'outro veículo', 'outro veiculo', 'ônibus', 'onibus', 'caminhão', 'caminhao'];
/** Tipos femininos ("a lancha"); o resto é masculino ("o motorhome"). Sem tipo: feminino ("a embarcação ou veículo"). */
const FEMININOS = ['lancha', 'moto aquática', 'moto aquatica', 'embarcação', 'embarcacao', 'van', 'picape', 'escuna', 'traineira'];

const norm = (s: string | null | undefined) => (s ?? '').trim().toLowerCase();
const limpo = (s: string | null | undefined) => (s ?? '').trim();

/** "Outra embarcação"/"Outro veículo" (decisão 10, 22/10/2026) viram o rótulo do grupo: "Embarcação: Netuno". */
const ROTULO_DO_OUTRO: Record<string, string> = {
  'outra embarcação': 'Embarcação', 'outra embarcacao': 'Embarcação',
  'outro veículo': 'Veículo', 'outro veiculo': 'Veículo',
  // Valor antigo: até 22/10/2026 a lista tinha "Jet Ski", que é marca da Kawasaki.
  'jet ski': 'Moto aquática',
};

/** Tipo que vale como rótulo: vazio ou "Outro" (sem grupo) não vale. */
function tipoValido(tipo: string | null | undefined): string {
  const t = limpo(tipo);
  if (!t || norm(t) === 'outro') return '';
  return ROTULO_DO_OUTRO[norm(t)] ?? t;
}

/**
 * O nome sem o tipo repetido na frente: "Trailer Darlan" (tipo Trailer) → "Darlan"; nome igual ao tipo → ''.
 * Em 21/10/2026 eram 6 cadastros assim ("Motorhome NVT", "Trailer Apolo 3000"…), e a mensagem ao
 * cliente saía "do trailer Trailer Darlan".
 */
function semTipoNaFrente(nome: string, tipo: string): string {
  if (!tipo) return nome;
  const n = norm(nome), t = norm(tipo);
  if (n === t) return '';
  return n.startsWith(t + ' ') ? nome.slice(tipo.length).trim() : nome;
}

export function grupoDoTipo(tipo: string | null | undefined): GrupoDoTipo {
  const t = norm(tipo);
  if (EMBARCACOES.includes(t)) return 'embarcacao';
  if (VEICULOS.includes(t)) return 'veiculo';
  return 'outro';
}

export function ehFeminino(tipo: string | null | undefined): boolean {
  const t = norm(tipoValido(tipo));
  return !t || FEMININOS.includes(t);
}

export interface UnidadeResumo {
  name?: string | null;
  asset_type?: string | null;
  manufacturer?: string | null;
  model?: string | null;
  hull_id_or_registration?: string | null;
}

/** "Lancha Netuno II"; sem tipo (ou "Outro"), só o nome; o tipo não se repete (nome igual ao tipo, ou
    que já começa por ele: "Trailer Darlan"). Sem nada: o termo geral. */
export function nomeDaUnidade(u: UnidadeResumo | null | undefined): string {
  const tipo = tipoValido(u?.asset_type);
  const nome = limpo(u?.name);
  if (!tipo) return nome || TERMO_GERAL;
  const resto = semTipoNaFrente(nome, tipo);
  return resto ? `${tipo} ${resto}` : tipo;
}

/** Rótulo do campo com uma unidade à vista: o tipo ("Motorhome"); sem tipo, o termo geral. */
export function rotuloDaUnidade(tipo: string | null | undefined): string {
  return tipoValido(tipo) || TERMO_GERAL;
}

/** Como se chama a identificação oficial de cada tipo: placa (CRLV), inscrição (TIE), série. */
export function rotuloDaIdentificacao(tipo: string | null | undefined): string {
  if (norm(tipo) === 'equipamento') return 'Nº de série';
  const g = grupoDoTipo(tipo);
  if (g === 'veiculo') return 'Placa';
  if (g === 'embarcacao') return 'Inscrição';
  return 'Inscrição / placa';
}

/**
 * A unidade num documento ou ficha, como par rótulo/valor:
 *   { rotulo: 'Motorhome', valor: 'Iveco Daily 55C17 · placa ABC1D23' }
 *   { rotulo: 'Lancha', valor: 'Netuno II · Schaefer 400' }
 * Nome igual ao tipo e nada mais: { rotulo: 'Embarcação ou veículo', valor: 'Motorhome' } — nunca
 * "Motorhome: Motorhome" (11 cadastros eram assim em 21/10/2026).
 * `comIdentificacao` false deixa a placa/inscrição de fora (quando o documento já a mostra à parte).
 */
export function campoDaUnidade(
  u: UnidadeResumo | null | undefined,
  { comIdentificacao = true, comModelo = true }: { comIdentificacao?: boolean; comModelo?: boolean } = {},
): { rotulo: string; valor: string } {
  if (!u) return { rotulo: TERMO_GERAL, valor: '' };
  const tipo = tipoValido(u.asset_type);
  const nome = limpo(u.name);
  // "Trailer Darlan" com tipo Trailer: o rótulo já diz "Trailer", o valor fica "Darlan".
  const nomeProprio = semTipoNaFrente(nome, tipo);
  const modelo = [limpo(u.manufacturer), limpo(u.model)].filter(Boolean).join(' ');
  const partes: string[] = [];
  if (nomeProprio) partes.push(nomeProprio);
  // O modelo só entra se acrescenta (motorhome "Iveco Daily" com modelo "Iveco Daily" não repete).
  if (comModelo && modelo && !norm(nome).includes(norm(modelo))) partes.push(modelo);
  const ident = limpo(u.hull_id_or_registration);
  if (comIdentificacao && ident && norm(ident) !== norm(nome)) {
    partes.push(`${rotuloDaIdentificacao(u.asset_type).toLowerCase()} ${ident}`);
  }
  if (!partes.length) return { rotulo: TERMO_GERAL, valor: tipo || nome };
  return { rotulo: rotuloDaUnidade(u.asset_type), valor: partes.join(' · ') };
}

/** "Motorhome: Iveco Daily · placa ABC1D23" numa linha só. */
export function linhaDaUnidade(u: UnidadeResumo | null | undefined, opcoes?: { comIdentificacao?: boolean; comModelo?: boolean }): string {
  const { rotulo, valor } = campoDaUnidade(u, opcoes);
  return valor ? `${rotulo}: ${valor}` : '';
}

/**
 * A unidade dentro de uma frase, com artigo/preposição e o tipo em minúscula:
 *   unidadeNaFrase(u, 'em') → "no motorhome Iveco Daily" / "na lancha Netuno II"
 *   unidadeNaFrase(u, 'de') → "do motorhome Iveco Daily" / "da lancha Netuno II"
 *   unidadeNaFrase(u)       → "o motorhome Iveco Daily" / "a lancha Netuno II"
 * Sem tipo: "na embarcação ou veículo Netuno II" — ou só o nome com o artigo, se não houver tipo.
 */
export function unidadeNaFrase(u: UnidadeResumo | null | undefined, preposicao: '' | 'em' | 'de' | 'para' = ''): string {
  const tipo = tipoValido(u?.asset_type);
  const nome = limpo(u?.name);
  const f = ehFeminino(u?.asset_type);
  const artigo = { '': f ? 'a' : 'o', em: f ? 'na' : 'no', de: f ? 'da' : 'do', para: f ? 'para a' : 'para o' }[preposicao];
  const nucleo = tipo ? tipo.toLowerCase() : TERMO_GERAL.toLowerCase();
  const proprio = semTipoNaFrente(nome, tipo);
  const resto = proprio ? ` ${proprio}` : '';
  return `${artigo} ${nucleo}${resto}`;
}

/**
 * "Seu motorhome", "sua lancha", "seu trailer" — para falar com o CLIENTE (pedido do dono, 22/10/2026:
 * "para motorhome use seu motorhome, para trailer, seu trailer e assim por diante").
 *   suaUnidade(u)       → "seu motorhome" / "sua lancha"
 *   suaUnidade(u, 'em') → "no seu motorhome" / "na sua lancha"
 *   suaUnidade(u, 'de') → "do seu motorhome" / "da sua lancha"
 * Sem tipo: "sua embarcação ou veículo".
 * Com `comNome`, o nome próprio vem depois (sem repetir o tipo): "no seu motorhome Iveco Daily",
 * "da sua lancha Netuno II" — cliente com duas unidades precisa saber qual.
 */
export function suaUnidade(
  u: UnidadeResumo | null | undefined,
  preposicao: '' | 'em' | 'de' | 'para' = '',
  { comNome = false }: { comNome?: boolean } = {},
): string {
  const tipo = tipoValido(u?.asset_type);
  const f = ehFeminino(u?.asset_type);
  const antes = { '': '', em: f ? 'na ' : 'no ', de: f ? 'da ' : 'do ', para: f ? 'para a ' : 'para o ' }[preposicao];
  const proprio = comNome ? semTipoNaFrente(limpo(u?.name), tipo) : '';
  return `${antes}${f ? 'sua' : 'seu'} ${(tipo || TERMO_GERAL).toLowerCase()}${proprio ? ` ${proprio}` : ''}`;
}

/** Emoji da unidade nas mensagens: barco 🛥️, veículo 🚐; o resto, nenhum (nada de barquinho para motorhome). */
export function emojiDaUnidade(tipo: string | null | undefined): string {
  const g = grupoDoTipo(tipo);
  return g === 'embarcacao' ? '🛥️' : g === 'veiculo' ? '🚐' : '';
}

/** Os tipos do cadastro, na ordem do seletor (decisão 10, dono 22/10/2026). */
export const TIPOS_DE_UNIDADE: ReadonlyArray<{
  grupo: string;
  tipos: ReadonlyArray<{ valor: string; dica?: string; sinonimos?: readonly string[] }>;
}> = [
  { grupo: 'Embarcações', tipos: [
    { valor: 'Lancha' }, { valor: 'Veleiro' }, { valor: 'Catamarã' },
    { valor: 'Moto aquática', sinonimos: ['jet ski', 'jetski'] }, { valor: 'Outra embarcação' },
  ] },
  { grupo: 'Veículos', tipos: [
    { valor: 'Motorhome', dica: 'inclui van convertida', sinonimos: ['van', 'motor home'] },
    { valor: 'Trailer' }, { valor: 'Camper' }, { valor: 'Automóvel' }, { valor: 'Outro veículo' },
  ] },
  { grupo: 'Bancada', tipos: [{ valor: 'Equipamento', dica: 'atendido na bancada' }] },
];

/** O valor do seletor para um tipo gravado: "Jet Ski" antigo → "Moto aquática"; "Outro" sem grupo → '' (escolher). */
export function tipoDoSeletor(tipo: string | null | undefined): string {
  const t = norm(tipo);
  if (!t || t === 'outro') return '';
  if (t === 'jet ski') return 'Moto aquática';
  for (const g of TIPOS_DE_UNIDADE) for (const x of g.tipos) if (norm(x.valor) === t) return x.valor;
  return limpo(tipo);
}

/** Palavras a mais para a busca achar o tipo ("jet ski" acha moto aquática; "van" acha motorhome). */
export function sinonimosDoTipo(tipo: string | null | undefined): string[] {
  const t = norm(tipoValido(tipo));
  for (const g of TIPOS_DE_UNIDADE) for (const x of g.tipos) if (norm(x.valor) === t) return [...(x.sinonimos ?? [])];
  return [];
}

/**
 * Quais campos o cadastro e a ficha mostram para cada tipo (decisão do dono, 22/10/2026: "ajustar
 * conforme cada tipo"). Barco ou sem tipo: tudo, como era. Veículo: sem boca, calado, píer,
 * propulsão e eletrônica de navegação; comprimento em metros. Equipamento: nem comprimento nem motores.
 */
export interface CamposDoTipo {
  nauticos: boolean;
  comprimento: 'pes' | 'metros' | null;
  motores: boolean;
  rotuloEnergiaExterna: string;
  rotuloOndeFica: string;
}
export function camposDoTipo(tipo: string | null | undefined): CamposDoTipo {
  if (norm(tipo) === 'equipamento') {
    return { nauticos: false, comprimento: null, motores: false, rotuloEnergiaExterna: 'Energia externa', rotuloOndeFica: 'Onde fica' };
  }
  if (grupoDoTipo(tipo) === 'veiculo') {
    return { nauticos: false, comprimento: 'metros', motores: true, rotuloEnergiaExterna: 'Energia externa (tomada ou camping)', rotuloOndeFica: 'Onde fica' };
  }
  return { nauticos: true, comprimento: 'pes', motores: true, rotuloEnergiaExterna: 'Energia de cais', rotuloOndeFica: 'Marina' };
}

const PE_EM_METROS = 0.3048;
/** O banco guarda em pés (length_feet); veículo se mede em metros. */
export const pesParaMetros = (pes: number) => Math.round(pes * PE_EM_METROS * 100) / 100;
export const metrosParaPes = (metros: number) => Math.round((metros / PE_EM_METROS) * 100) / 100;

/** "40 pés" para barco; "12,2 m" para veículo; '' para equipamento ou sem medida. */
export function comprimentoDoTipo(pes: number | null | undefined, tipo: string | null | undefined): string {
  const n = Number(pes);
  if (!pes || !Number.isFinite(n)) return '';
  const c = camposDoTipo(tipo).comprimento;
  if (c === 'metros') return `${(Math.round(n * PE_EM_METROS * 10) / 10).toLocaleString('pt-BR')} m`;
  if (c === 'pes') return `${n.toLocaleString('pt-BR')} pés`;
  return '';
}
