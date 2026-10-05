import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Switch } from '@/components/ui/switch';
import { useUpdateAppSetting } from '@/hooks/use-app-settings';
import { CHAVE_ROTEIRO_VISIVEL, useRoteiroVisivel } from '@/hooks/use-roteiro-visivel';

/**
 * Liga e desliga o roteiro de execução e o levantamento na tela (05/10/2026). Escondidos por
 * padrão enquanto não houver técnico usando o sistema; nada é apagado (ver use-roteiro-visivel.ts).
 */
export function RoteiroExecucaoCard() {
  const visivel = useRoteiroVisivel();
  const salvar = useUpdateAppSetting();
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Roteiro de execução e levantamento</CardTitle>
        <CardDescription>
          Mostra a aba Roteiro e a aba Levantamento na OS, os menus Quadro do Dia e Roteiros Padrão e o
          painel "costuma entrar junto". Ficam escondidos enquanto nenhum técnico marca passos pelo
          sistema; os dados continuam guardados. A segurança por sistema na via do técnico sai sempre,
          ligado ou não.
        </CardDescription>
      </CardHeader>
      <CardContent className="flex items-center gap-3">
        <Switch
          id="roteiro-visivel"
          checked={visivel}
          disabled={salvar.isPending}
          onCheckedChange={(ligado) => salvar.mutate({ key: CHAVE_ROTEIRO_VISIVEL, value: ligado ? 'true' : 'false' })}
          aria-label="Mostrar roteiro de execução e levantamento"
        />
        <label htmlFor="roteiro-visivel" className="text-sm">
          {visivel ? 'Mostrando na tela' : 'Escondido'}
        </label>
      </CardContent>
    </Card>
  );
}
