// A mudança de status pela tela (StatusQuickChange, kanbans, listas de orçamentos, formulário) — Agenda de Produção,
// Fase 3 (P3, 24/10/2026). Quem decide é a porta única do banco (os_transicionar_status, via 'tela'): concluir lança a
// saída e as cobranças da condição na mesma transação, faturar só a concluída, o vendedor não conclui e a OS em andamento
// não volta. Quando a porta não muda nada (ok com mudou = false: "A OS já começou: não volta para aprovada."), não é erro:
// quem chama mostra a frase dela em vez do "Status atualizado".
//
// Fica fora do hook de propósito: os testes de tela trocam o módulo do hook inteiro (vi.mock) e o aviso continua real.
import { toast } from 'sonner';

/** O que useUpdateServiceOrderStatus devolve. */
export interface ResultadoDoStatusPelaTela {
  /** o status mudou (ou o orçamento virou OS) */
  mudou: boolean;
  /** o status em que a OS ficou */
  status: string;
  /** a frase da porta ("Lenine (OS-00074): concluída — saída …"); vazio no caminho de antes da porta */
  texto: string;
  /** a 1ª saída do orçamento (quem chama abre o aviso de compra) */
  justConverted: boolean;
  /** o número depois (a conversão troca só o prefixo: ORÇ-00119 → OS-00119) */
  numero: string | null;
  /** a porta não mudou nada: a frase dela, para o aviso */
  semMudanca?: string;
  /** veio pelo caminho de antes da porta (a migration da Fase 3 ainda não aplicada) */
  semAPorta?: boolean;
}

/**
 * A porta recusou só porque faltou o motivo (Agenda de Produção, revisão da Fase 3, R2): a OS em andamento volta a aguardar
 * (peças ou o cliente) só quando quem pede diz por quê. Quem chama abre a janela do motivo (JanelaDoMotivo) e manda de novo.
 */
export class PortaPedeMotivo extends Error {
  /** o status que a pessoa pediu */
  readonly para: string;
  constructor(texto: string, para: string) {
    super(texto);
    this.name = 'PortaPedeMotivo';
    this.para = para;
  }
}

export function ehPortaPedeMotivo(e: unknown): e is PortaPedeMotivo {
  return e instanceof PortaPedeMotivo;
}

/** O motivo que vai à porta e fica no registro da OS: "falta material: o inversor não chegou", "esperando o cliente". */
export function motivoDaParada(para: string, oQueAconteceu: string): string {
  const base = para === 'awaiting_client' ? 'esperando o cliente' : 'falta material';
  const texto = oQueAconteceu.trim().replace(/\s+/g, ' ');
  return texto ? `${base}: ${texto}` : base;
}

/**
 * A porta não mudou nada? Mostra a frase dela (aviso, não erro) e devolve true — quem chama não diz "Status atualizado"
 * nem abre o que vem depois da mudança (o aviso de compra, o faturar, o saldo ao cliente).
 */
export function avisarSeNaoMudou(r: Pick<ResultadoDoStatusPelaTela, 'semMudanca'> | null | undefined): boolean {
  const texto = r?.semMudanca?.trim();
  if (!texto) return false;
  toast(texto);
  return true;
}
