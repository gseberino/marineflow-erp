/**
 * Um campo de formulário: rótulo, a dica e o controle — nessa ordem, de cima para baixo (pedido do
 * dono, 21/10/2026: "a descrição de cada campo deve estar acima do campo"; padrão "hint" do GOV.UK).
 *
 * O "tudo junto" da seção vinha do espaçamento igual em tudo: o Label tem leading-none e nenhuma
 * margem, então o rótulo encostava no campo e o próximo rótulo ficava à mesma distância. Aqui o
 * par rótulo→controle fica perto (6 px) e quem monta a grade põe mais espaço entre os campos.
 * A dica vai ligada ao controle por aria-describedby (quem monta passa `idAjuda` ao controle).
 */
import type { ReactNode } from 'react';
import { Label } from '@/components/ui/label';
import { cn } from '@/lib/utils';

interface Props {
  rotulo: ReactNode;
  /** id do controle, para o clique no rótulo levar a ele. */
  htmlFor?: string;
  /** Texto curto que explica o campo; aparece entre o rótulo e o controle. */
  ajuda?: ReactNode;
  /** id da dica, para o aria-describedby do controle. */
  idAjuda?: string;
  /** Algo à direita do rótulo, na mesma linha (ex.: o "Trocar" do cliente). */
  acao?: ReactNode;
  className?: string;
  children: ReactNode;
}

export function Campo({ rotulo, htmlFor, ajuda, idAjuda, acao, className, children }: Props) {
  return (
    <div className={cn('flex min-w-0 flex-col gap-1.5', className)}>
      {/* Linha do rótulo sempre com a mesma altura (com ou sem ação ao lado): lado a lado, os
          rótulos e os campos das duas colunas começam na mesma altura. */}
      <div className="flex min-h-5 items-center justify-between gap-2">
        <Label htmlFor={htmlFor}>{rotulo}</Label>
        {acao}
      </div>
      {ajuda && <p id={idAjuda} className="text-xs text-muted-foreground">{ajuda}</p>}
      {children}
    </div>
  );
}
