// O "?" que explica um número, um botão ou uma aba.
//
// Pedido do dono (26/09/2026): "ao manter o cursor em cima de um botão, um balão informativo
// com a função". A dica que só abre com o mouse não existe no celular — por isso este balão
// abre ao passar o mouse E ao tocar/clicar (Popover, não Tooltip), e fecha com Esc ou fora.
import { useRef, useState } from 'react';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { HelpCircle } from 'lucide-react';
import { cn } from '@/lib/utils';

export function Ajuda({ children, rotulo = 'O que é isto?', className }: {
  children: React.ReactNode;
  /** Nome acessível do botão "?" (leitor de tela). */
  rotulo?: string;
  className?: string;
}) {
  const [aberto, setAberto] = useState(false);
  // O hover abre; o clique fixa. Sem isso, clicar logo depois do hover fechava o balão.
  const fixado = useRef(false);
  return (
    <Popover open={aberto} onOpenChange={(v) => { setAberto(v); if (!v) fixado.current = false; }}>
      <PopoverTrigger asChild>
        <button
          type="button"
          aria-label={rotulo}
          className={cn('inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-muted-foreground hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring', className)}
          onMouseEnter={() => setAberto(true)}
          onMouseLeave={() => { if (!fixado.current) setAberto(false); }}
          // preventDefault: o clique é tratado aqui (fixa/solta), não pelo alternador do Popover.
          onClick={(e) => {
            e.preventDefault();
            fixado.current = !fixado.current;
            setAberto(fixado.current);
          }}
        >
          <HelpCircle className="h-3.5 w-3.5" />
        </button>
      </PopoverTrigger>
      <PopoverContent side="top" className="max-w-xs text-xs leading-relaxed" onOpenAutoFocus={(e) => e.preventDefault()}>
        {children}
      </PopoverContent>
    </Popover>
  );
}

/** A frase de "para que serve" embaixo do título de uma aba — sempre visível, sem precisar achar. */
export function ParaQueServe({ children, className }: { children: React.ReactNode; className?: string }) {
  return <p className={cn('text-sm text-muted-foreground', className)}>{children}</p>;
}
