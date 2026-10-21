/**
 * Trocar a embarcação/veículo de uma OS já salva: quando passa direto e quando a confirmação diz o
 * que acontece (pedido do dono, 21/10/2026: "a mesma proteção do cliente, em casos específicos").
 *
 * Pesquisa (21/10/2026, 6 frentes + verificação): passa direto o que não perde nada — OS nova,
 * campo vazio, a mesma de novo, cliente de unidade única. Marina e local sugeridos NÃO contam: eles
 * são trocados pelos da unidade nova, não perdidos (confirmar por eles seria atrito sem perda).
 * Confirma o que sai ou o que já foi ao cliente; o bloqueio (OS concluída, agrupamento) é de quem
 * monta a tela. Falha ao conferir conta como motivo, nunca como "passa".
 *
 * O texto diz o nome uma vez ("De Lancha Netuno II para Motorhome Iveco Daily.") e depois só
 * "a antiga"/"o antigo", com o gênero do tipo — "contato da Motorhome" estava errado.
 */

export type GrupoDoTipo = 'embarcacao' | 'veiculo' | 'outro';

const EMBARCACOES = ['lancha', 'veleiro', 'catamarã', 'catamara', 'jet ski', 'moto aquática', 'moto aquatica', 'barco', 'embarcação'];
const VEICULOS = ['motorhome', 'trailer', 'camper', 'automóvel', 'automovel', 'van', 'picape', 'veículo', 'veiculo'];
/** Tipos femininos ("a lancha"); o resto é masculino ("o motorhome"). Sem tipo: "a unidade". */
const FEMININOS = ['lancha', 'moto aquática', 'moto aquatica', 'embarcação', 'van', 'picape'];

const norm = (tipo: string | null | undefined) => (tipo ?? '').trim().toLowerCase();

export function grupoDoTipo(tipo: string | null | undefined): GrupoDoTipo {
  const t = norm(tipo);
  if (EMBARCACOES.includes(t)) return 'embarcacao';
  if (VEICULOS.includes(t)) return 'veiculo';
  return 'outro';
}

function feminino(tipo: string | null | undefined): boolean {
  const t = norm(tipo);
  return !t || t === 'outro' || FEMININOS.includes(t);
}

export interface UnidadeResumo { name?: string | null; asset_type?: string | null }

/** "Lancha Netuno II"; sem tipo (ou "Outro"), só o nome; nome igual ao tipo não se repete. */
export function nomeDaUnidade(u: UnidadeResumo | null | undefined): string {
  if (!u) return 'a unidade escolhida';
  const tipo = (u.asset_type ?? '').trim();
  const nome = (u.name ?? '').trim();
  if (!tipo || norm(tipo) === 'outro') return nome || 'a unidade escolhida';
  if (!nome || nome.toLowerCase() === tipo.toLowerCase()) return tipo;
  return `${tipo} ${nome}`;
}

export interface SituacaoDaOS {
  /** A OS/orçamento já existe no banco. Nova: nada pede confirmação. */
  salva: boolean;
  documento?: 'OS' | 'orçamento';
  quoteStatus?: string | null;
  convertidaEmOS?: boolean;
  confirmacaoDoAgendamentoPedida?: boolean;
  assinadaPeloCliente?: boolean;
  checkInFeito?: boolean;
  /** Levantamento ligado à OS: true/false; null = não deu para conferir. */
  temLevantamento: boolean | null;
  /** Há um contato da unidade como solicitante (sai na troca): o nome, ou '' quando não se sabe
      (contato inativo, lista carregando). null/ausente = não há. */
  contatoSolicitante?: string | null;
}

const JA_FOI_AO_CLIENTE = ['sent', 'approved', 'awaiting_deposit', 'awaiting_approval'];

/** Os motivos (frases) que a confirmação mostra. Vazio = troca direto. `novo` null = cadastro novo.
    `antigo` desconhecido (lista ainda carregando ou com erro) numa OS salva também pede confirmação. */
export function motivosDaTrocaDeEmbarcacao(
  s: SituacaoDaOS,
  antigo: UnidadeResumo | null | undefined,
  novo: UnidadeResumo | null,
): string[] {
  if (!s.salva) return [];
  const f = feminino(antigo?.asset_type);
  const daAntiga = f ? 'da antiga' : 'do antigo';
  const naAntiga = f ? 'na antiga' : 'no antigo';
  const comEla = f ? 'com ela' : 'com ele';
  const doc = s.documento === 'orçamento' ? 'este orçamento' : 'esta OS';
  const motivos: string[] = [];
  if (!antigo) motivos.push('Não deu para conferir a embarcação ou veículo atual.');
  if (s.contatoSolicitante != null) {
    const quem = s.contatoSolicitante.trim();
    motivos.push(`Sai o solicitante${quem ? ` ${quem}` : ''}, que é contato ${daAntiga}.`);
  }
  if (s.temLevantamento === true) motivos.push(`O levantamento feito ${naAntiga} fica ${comEla}: ${doc} vai precisar de outro.`);
  if (s.temLevantamento === null) motivos.push(`Não deu para conferir se ${doc} tem levantamento.`);
  // O banco não pede nova assinatura sozinho quando a unidade muda: quem troca, pede.
  if (s.assinadaPeloCliente) motivos.push(`O cliente já assinou ${doc}: depois da troca, peça uma nova assinatura.`);
  else if (JA_FOI_AO_CLIENTE.includes(s.quoteStatus ?? '') || s.convertidaEmOS || s.confirmacaoDoAgendamentoPedida) {
    motivos.push(`O cliente já recebeu ${doc}: reenvie depois da troca.`);
  }
  if (s.checkInFeito) motivos.push('O trabalho já começou (check-in feito).');
  if (antigo && novo && grupoDoTipo(antigo.asset_type) !== 'outro' && grupoDoTipo(novo.asset_type) !== 'outro'
      && grupoDoTipo(antigo.asset_type) !== grupoDoTipo(novo.asset_type)) {
    motivos.push(`Muda o tipo, de ${norm(antigo.asset_type)} para ${norm(novo.asset_type)}: confira serviços, peças e roteiro.`);
  }
  return motivos;
}

export function tituloDaTrocaDeEmbarcacao(documento: 'OS' | 'orçamento'): string {
  return documento === 'orçamento'
    ? 'Trocar a embarcação ou veículo deste orçamento?'
    : 'Trocar a embarcação ou veículo desta OS?';
}

/** "De Lancha Netuno II para Motorhome Iveco Daily." + os motivos. */
export function descricaoDaTrocaDeEmbarcacao(antigo: UnidadeResumo | null | undefined, novo: UnidadeResumo | null, motivos: string[]): string {
  const para = novo ? nomeDaUnidade(novo) : 'um cadastro novo';
  return [`De ${nomeDaUnidade(antigo)} para ${para}.`, ...motivos].join(' ');
}
