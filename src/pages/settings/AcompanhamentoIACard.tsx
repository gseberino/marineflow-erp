import { Link } from 'react-router-dom';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Switch } from '@/components/ui/switch';
import { useFollowupSwitch } from '@/hooks/use-followup-missions';

/**
 * Liga e desliga o "Deixar a IA acompanhar" (06/10/2026). Desligado desde 15/09: com ele
 * desligado, o botão de criar missão e o link "IA acompanhando" da Agenda somem — então o
 * caminho para religar precisa morar aqui. Religar também pede reativar a rotina
 * ai-followup-runner, pausada em 05/10 (migration 20261005100000).
 */
export function AcompanhamentoIACard() {
  const { ligado, isLoading, alternar, isPending } = useFollowupSwitch();
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Acompanhamento pela IA</CardTitle>
        <CardDescription>
          A IA acompanha um orçamento ou uma tarefa e redige a cobrança para você aprovar. Está desligado
          desde 15/09; ligado, volta o botão "Deixar a IA acompanhar" e o painel{' '}
          <Link to="/v2/agenda/acompanhamentos" className="underline">IA acompanhando</Link>. Para a IA voltar a
          redigir sozinha, a rotina horária também precisa ser reativada (peça ao suporte do sistema).
        </CardDescription>
      </CardHeader>
      <CardContent className="flex items-center gap-3">
        <Switch
          id="acompanhamento-ia"
          checked={ligado}
          disabled={isLoading || isPending}
          onCheckedChange={(v) => { void alternar(v); }}
          aria-label="Acompanhamento pela IA"
        />
        <label htmlFor="acompanhamento-ia" className="text-sm">{ligado ? 'Ligado' : 'Desligado'}</label>
      </CardContent>
    </Card>
  );
}
