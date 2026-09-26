// "As abas mudaram de lugar" — o aviso da reorganização do Financeiro (26/09/2026).
//
// A barra de 14 abas acabou: cada assunto ganhou o seu lugar. Quem tinha o hábito de clicar
// em "DRE" ou "Cartões" precisa saber para onde eles foram, uma vez, sem ter de perguntar.
// O aviso é discreto, fecha com um clique e some sozinho depois de 10/10/2026.
import { useState } from 'react';
import { ChevronDown, Info, X } from 'lucide-react';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { hojeEmBrasilia } from '@/lib/fluxo-de-caixa';
import { cn } from '@/lib/utils';

/** Até quando o aviso aparece (inclusive), em data de Brasília. */
export const AVISO_VALE_ATE = '2026-10-10';
const CHAVE = 'mf-aviso-abas-mudaram-2026-09';

/** O mini-mapa "antes → agora". */
export const MAPA_ANTES_AGORA: Array<[string, string]> = [
  ['DRE e Aging', 'Central de relatórios'],
  ['Programação', 'Central de relatórios › Fluxo de caixa'],
  ['Cartões e Regras', 'Extrato'],
  ['Fechamento', 'Conciliação'],
  ['Comissões e Reembolsos', 'Contas a Pagar'],
  ['Cobranças', 'Contas a Receber'],
  ['Saúde do cadastro', 'Fornecedores'],
  ['Gerenciais', 'Central de relatórios › Operação'],
  ['Contas bancárias', 'menu Cadastros › Contas Bancárias'],
];

export function avisoAindaVale(hoje: string = hojeEmBrasilia()): boolean {
  return hoje <= AVISO_VALE_ATE;
}

function jaFechado(): boolean {
  try {
    return window.localStorage.getItem(CHAVE) === 'fechado';
  } catch {
    // Navegação privada ou armazenamento bloqueado: o aviso aparece, e fechar vale até recarregar.
    return false;
  }
}

export function AvisoAbasMudaram({ className }: { className?: string }) {
  const [fechado, setFechado] = useState(jaFechado);
  const [aberto, setAberto] = useState(false);
  if (fechado || !avisoAindaVale()) return null;

  const fechar = () => {
    setFechado(true);
    try {
      window.localStorage.setItem(CHAVE, 'fechado');
    } catch {
      /* sem armazenamento: fica fechado só nesta visita */
    }
  };

  return (
    <div role="note" className={cn('rounded-lg border border-info/30 bg-info/5 px-3 py-2 text-sm', className)}>
      <Collapsible open={aberto} onOpenChange={setAberto}>
        <div className="flex items-start gap-2">
          <Info className="mt-0.5 h-4 w-4 shrink-0 text-info" aria-hidden />
          <div className="min-w-0 flex-1">
            <p>
              <b>As abas mudaram de lugar.</b>{' '}
              <span className="text-muted-foreground">Cada assunto do Financeiro agora tem a sua tela.</span>{' '}
              <CollapsibleTrigger asChild>
                <button type="button" className="inline-flex items-center gap-0.5 font-medium text-info underline-offset-2 hover:underline">
                  {aberto ? 'Esconder o mapa' : 'Ver o que foi para onde'}
                  <ChevronDown className={cn('h-3.5 w-3.5 transition-transform', aberto && 'rotate-180')} aria-hidden />
                </button>
              </CollapsibleTrigger>
            </p>
            <CollapsibleContent>
              <ul className="mt-2 space-y-1">
                {MAPA_ANTES_AGORA.map(([antes, agora]) => (
                  <li key={antes} className="flex flex-wrap items-baseline gap-x-1.5 text-xs">
                    <span className="font-medium">{antes}</span>
                    <span aria-hidden className="text-muted-foreground">→</span>
                    <span className="sr-only">agora em</span>
                    <span className="text-muted-foreground">{agora}</span>
                  </li>
                ))}
              </ul>
            </CollapsibleContent>
          </div>
          <button
            type="button"
            onClick={fechar}
            aria-label="Fechar o aviso de que as abas mudaram de lugar"
            className="-mr-1 shrink-0 rounded p-1 text-muted-foreground hover:bg-muted hover:text-foreground"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
      </Collapsible>
    </div>
  );
}
