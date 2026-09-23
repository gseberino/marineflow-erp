import type { ComponentType } from 'react';
import { MoreHorizontal } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel,
  DropdownMenuSeparator, DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { cn } from '@/lib/utils';

/**
 * As ações de uma linha de lista: as comuns à vista, o resto num menu de três pontos.
 *
 * O padrão nasceu da tela de notas fiscais, onde dez botões lado a lado ocupavam metade
 * da largura. Três coisas quebravam ao mesmo tempo: a linha ficava larga demais para
 * caber, o olho não achava a ação que procurava no meio das outras nove, e "cancelar a
 * nota" tinha exatamente o mesmo peso visual de "baixar o PDF" — a ação perigosa a um
 * clique de distância da corriqueira.
 *
 * A regra é: no máximo duas ações ficam fora, e são as que se usa quase todo dia naquele
 * tipo de item. O resto vive no menu, com o nome escrito por extenso — num menu não
 * existe o problema de espaço que obriga a virar ícone, e ícone sozinho é adivinhação.
 * Ação destrutiva vai sempre no menu, marcada, e depois de um separador.
 */

export interface AcaoDaLinha {
  /** O que o botão faz, escrito como se fala. Vira o rótulo do item de menu. */
  texto: string;
  onClick: () => void;
  icone?: ComponentType<{ className?: string }>;
  /** Explicação no hover — para a ação cujo nome curto não basta. */
  titulo?: string;
  desabilitada?: boolean;
  /** Apaga, cancela, bloqueia: ganha cor de alerta e fica isolada no fim do menu. */
  perigo?: boolean;
}

interface Props {
  /**
   * Como esta linha se chama, para quem navega por leitor de tela — "nota 2/25",
   * "lead de João". Sem isto, uma tela com trinta linhas tem trinta botões chamados
   * "mais ações" e nenhum jeito de saber qual é qual.
   */
  rotulo: string;
  /** Até duas; o que passar disso é sinal de que a lista quer virar tela de detalhe. */
  rapidas?: AcaoDaLinha[];
  menu: AcaoDaLinha[];
  /** Título dentro do menu, quando ajuda a confirmar em que linha se clicou. */
  tituloDoMenu?: string;
  ocupada?: boolean;
  className?: string;
}

export function AcoesDaLinha({
  rotulo, rapidas = [], menu, tituloDoMenu, ocupada = false, className,
}: Props) {
  // Item sem ação nenhuma não vira um menu vazio: some, que é mais honesto que um
  // botão que abre no nada.
  const itens = menu.filter(Boolean);
  if (rapidas.length === 0 && itens.length === 0) return null;

  // O destrutivo desce para o fim mesmo que tenha sido declarado no meio: quem escreve a
  // lista pensa na ordem lógica, não na de risco, e a ordem de risco é a que protege.
  const comuns = itens.filter((a) => !a.perigo);
  const perigosas = itens.filter((a) => a.perigo);

  return (
    <div className={cn('flex items-start justify-end gap-1', className)}>
      {rapidas.map((a) => (
        <Button
          key={a.texto}
          size="sm"
          variant="outline"
          className="h-8 px-2 text-xs"
          disabled={a.desabilitada || ocupada}
          title={a.titulo ?? a.texto}
          onClick={a.onClick}
        >
          {a.icone && <a.icone className="h-3.5 w-3.5 sm:mr-1" />}
          {/* Em tela estreita fica só o ícone; o nome continua no title e no menu. */}
          <span className={a.icone ? 'hidden sm:inline' : undefined}>{a.texto}</span>
        </Button>
      ))}

      {itens.length > 0 && (
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button
              size="sm"
              variant="ghost"
              className="h-8 w-8 p-0"
              disabled={ocupada}
              title="Mais ações"
            >
              <MoreHorizontal className="h-4 w-4" />
              <span className="sr-only">Mais ações para {rotulo}</span>
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-60">
            {tituloDoMenu && (
              <>
                <DropdownMenuLabel className="text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">
                  {tituloDoMenu}
                </DropdownMenuLabel>
                <DropdownMenuSeparator />
              </>
            )}
            {comuns.map((a) => (
              <DropdownMenuItem
                key={a.texto}
                className="gap-2 cursor-pointer"
                disabled={a.desabilitada}
                onClick={a.onClick}
              >
                {a.icone && <a.icone className="h-3.5 w-3.5" />}
                {a.texto}
              </DropdownMenuItem>
            ))}
            {perigosas.length > 0 && comuns.length > 0 && <DropdownMenuSeparator />}
            {perigosas.map((a) => (
              <DropdownMenuItem
                key={a.texto}
                className="gap-2 cursor-pointer text-destructive focus:text-destructive focus:bg-destructive/10"
                disabled={a.desabilitada}
                onClick={a.onClick}
              >
                {a.icone && <a.icone className="h-3.5 w-3.5" />}
                {a.texto}
              </DropdownMenuItem>
            ))}
          </DropdownMenuContent>
        </DropdownMenu>
      )}
    </div>
  );
}
