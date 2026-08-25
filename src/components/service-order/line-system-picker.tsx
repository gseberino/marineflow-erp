import { useEffect, useState } from 'react';
import { AlertTriangle, Check, Loader2 } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import {
  useServiceSystems, useServiceVerbs, useSetLineClassification,
  type LineMissingSystem,
} from '@/hooks/use-service-systems';

/**
 * Classificação da linha de serviço, no orçamento.
 *
 * Serve a dois casos que parecem diferentes e são o mesmo:
 *   · serviço genérico do catálogo ("diagnóstico no local") — falta o sistema;
 *   · linha digitada à mão, sem serviço nenhum — falta tudo, e é dela que
 *     dependem três das maiores OS abertas, hoje invisíveis para o roteiro.
 *
 * O sistema muda o tempo previsto (o mesmo diagnóstico vai de 1h45 a 3h45,
 * porque carrega a preparação e o fechamento de segurança), então isto não é
 * detalhe de execução: é o que faz o orçamento fechar no valor certo.
 *
 * ═══ POR QUE EXISTE UM BOTÃO DE CONFIRMAR ═══
 *
 * Antes os dois Select usavam `defaultValue` e gravavam no `onValueChange`, sem
 * botão. Só que o campo já vem PREENCHIDO com o palpite da regra, e
 * `onValueChange` não dispara quando se escolhe o valor que já estava lá —
 * confirmar a sugestão era um clique que não gravava nada. A linha continuava
 * pendente, e a tela não tinha como dizer por quê.
 *
 * Agora os Select são controlados, a escolha é local, e o Confirmar grava os
 * DOIS eixos numa tacada. Aceitar o palpite passou a ser uma ação de verdade.
 *
 * A confiança do palpite aparece na tela. Lido no texto da própria linha é
 * forte; deduzido do problema da OS é fraco, e a frase diz isso — palpite
 * fraco com cara de certeza é convite a confirmar sem ler.
 */
export function LineSystemPicker({ linha }: { linha: LineMissingSystem }) {
  const { data: sistemas = [] } = useServiceSystems();
  const { data: verbos = [] } = useServiceVerbs();
  const salvar = useSetLineClassification();

  const precisaVerbo = !linha.service_verb;

  // A escolha vive aqui até o Confirmar. Começa no palpite, quando há um.
  const [sistema, setSistema] = useState<string | undefined>(linha.sistema_sugerido ?? undefined);
  const [verbo, setVerbo] = useState<string | undefined>(linha.verbo_sugerido ?? undefined);

  // A lista de pendências é refeita depois de cada gravação. Se esta linha
  // continuar nela (porque só um eixo entrou), o palpite pode ter mudado — o
  // estado local acompanha em vez de congelar no primeiro render.
  useEffect(() => {
    setSistema(linha.sistema_sugerido ?? undefined);
    setVerbo(linha.verbo_sugerido ?? undefined);
  }, [linha.line_id, linha.sistema_sugerido, linha.verbo_sugerido]);

  const faltaEscolher = !sistema || (precisaVerbo && !verbo);

  function confirmar() {
    if (faltaEscolher) return;
    salvar.mutate(
      { lineId: linha.line_id, system: sistema, ...(precisaVerbo ? { verb: verbo } : {}) },
      {
        onSuccess: () => toast.success('Classificação confirmada.'),
        onError: (e: any) => toast.error(e?.message || 'Erro ao confirmar a classificação'),
      },
    );
  }

  return (
    <div className="mt-1.5 space-y-1.5 rounded-md border border-amber-500/50 bg-amber-50 p-2 dark:bg-amber-950/30">
      <p className="flex items-start gap-1.5 text-[11px] leading-snug">
        <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-amber-600" />
        <span>
          Sem classificação, esta linha não entra no roteiro e o tempo previsto sai menor do que o
          trabalho.
        </span>
      </p>

      <div className="flex flex-wrap items-center gap-2">
        <Select value={sistema} onValueChange={setSistema}>
          <SelectTrigger className="h-8 w-full text-xs sm:w-56">
            <SelectValue placeholder="Sistema / categoria" />
          </SelectTrigger>
          <SelectContent>
            {sistemas.map((s) => (
              <SelectItem key={s.slug} value={s.slug}>{s.name}</SelectItem>
            ))}
          </SelectContent>
        </Select>

        {precisaVerbo && (
          <Select value={verbo} onValueChange={setVerbo}>
            <SelectTrigger className="h-8 w-full text-xs sm:w-48">
              <SelectValue placeholder="O que se faz" />
            </SelectTrigger>
            <SelectContent>
              {verbos.map((v) => (
                <SelectItem key={v.slug} value={v.slug}>{v.name}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        )}

        <Button
          size="sm"
          className="h-8 shrink-0 text-xs"
          disabled={faltaEscolher || salvar.isPending}
          onClick={confirmar}
        >
          {salvar.isPending
            ? <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />
            : <Check className="mr-1.5 h-3.5 w-3.5" />}
          Confirmar
        </Button>
      </div>

      {/* Dizer o que falta é o que impede o "confirmei e não aconteceu nada":
          o botão desabilitado sem motivo visível é a mesma frustração de antes. */}
      {faltaEscolher && (
        <p className="text-[10px] text-muted-foreground">
          {!sistema && precisaVerbo && !verbo
            ? 'Escolha a categoria e o tipo de serviço para confirmar.'
            : !sistema
              ? 'Escolha a categoria para confirmar.'
              : 'Escolha o tipo de serviço para confirmar.'}
        </p>
      )}

      {!faltaEscolher && linha.sistema_sugerido && (
        <p className="text-[10px] text-muted-foreground">
          {linha.origem_sistema === 'linha'
            ? 'Sugerido pelo texto desta linha — confira e confirme.'
            : 'Palpite fraco, tirado do contexto da OS — confira com atenção antes de confirmar.'}
        </p>
      )}
      {!linha.sistema_sugerido && (
        <p className="text-[10px] text-muted-foreground">
          A regra não arriscou um palpite aqui — escolha você.
        </p>
      )}
    </div>
  );
}
