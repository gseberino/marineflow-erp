/**
 * Dados só de leitura em pares rótulo/valor — o rótulo pequeno em cima, o valor embaixo (21/10/2026).
 *
 * As fichas do cliente e da embarcação na OS mostravam só ícone + valor: "123.456.789-00" sem dizer
 * que é o CPF, e o leitor de tela ouvia só o número (NN/g: ícone sem rótulo é ambíguo). O padrão é
 * a lista descritiva (<dl>), o mesmo do DiariasPanel. Valor vazio que o processo exige mostra
 * "Não informado" — as posições não mudam de um cadastro para outro e já dizem o que falta.
 */
import type { ReactNode } from 'react';
import { cn } from '@/lib/utils';

export function DadosDaFicha({ children, className }: { children: ReactNode; className?: string }) {
  return <dl className={cn('grid grid-cols-1 gap-x-4 gap-y-2.5 sm:grid-cols-2', className)}>{children}</dl>;
}

interface DadoProps {
  rotulo: ReactNode;
  /** Ocupa a linha toda (e-mail, endereço, observações). */
  largo?: boolean;
  children?: ReactNode;
}

/** Sem valor (null, undefined ou ""): mostra "Não informado". Para o par sumir, não o renderize. */
export function Dado({ rotulo, largo, children }: DadoProps) {
  const vazio = children == null || children === '' || children === false;
  return (
    <div className={cn('min-w-0', largo && 'col-span-full')}>
      <dt className="text-xs text-muted-foreground">{rotulo}</dt>
      <dd className={cn('mt-0.5 min-w-0 break-words', vazio && 'text-muted-foreground')}>
        {vazio ? 'Não informado' : children}
      </dd>
    </div>
  );
}
