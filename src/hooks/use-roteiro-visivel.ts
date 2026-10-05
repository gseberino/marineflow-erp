import { useAppSetting } from '@/hooks/use-app-settings';

/**
 * Roteiro de execução e levantamento na tela (05/10/2026).
 *
 * A reavaliação de 04/10 (audit/reavaliacao-roteiro-levantamento-20261004.md) mediu: 255 passos de
 * roteiro intocados, nenhuma OS com roteiro desde 14/08, 2 levantamentos (o último em 31/08) e
 * nenhum técnico com login. Conclusão dada ao dono: esconder sem apagar. Ficam atrás desta chave,
 * DESLIGADA por padrão (sem a chave em app_settings = escondido): as abas Roteiro e Levantamento da
 * OS, os menus Quadro do Dia e Roteiros Padrão e o painel "costuma entrar junto". Os dados e as
 * rotas continuam; religa em Configurações › Ordens de Serviço.
 *
 * A segurança por sistema da via do técnico NÃO depende disto: sai do catálogo mesmo sem roteiro
 * (seguranca_da_via).
 */
export const CHAVE_ROTEIRO_VISIVEL = 'roteiro_execucao_visivel';

export function useRoteiroVisivel(): boolean {
  return useAppSetting(CHAVE_ROTEIRO_VISIVEL, 'false').trim().toLowerCase() === 'true';
}
