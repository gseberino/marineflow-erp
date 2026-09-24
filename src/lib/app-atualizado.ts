/**
 * Quando o sistema é publicado com a aba do usuário aberta.
 *
 * O app carrega cada tela sob demanda (`lazy(() => import(...))`), e cada publicação
 * gera arquivos com nome novo — `index-nyr_pAs-.js` vira outro hash. A aba que ficou
 * aberta continua apontando para os nomes ANTIGOS, que não existem mais no servidor.
 * O efeito é uma falha que não parece o que é: navegar para uma tela ainda não visitada,
 * ou pedir o PDF, devolve "Failed to fetch dynamically imported module" — e o usuário lê
 * isso como "o sistema quebrou", quando o conserto é recarregar a página.
 *
 * Aconteceu de verdade em 24/09/2026 16:05: o dono pediu o PDF de uma OS e recebeu esse
 * erro, minutos depois de uma publicação.
 *
 * Tentar de novo não resolve — o arquivo não está lento, ele não existe mais. O que
 * resolve é recarregar, e é isso que este módulo oferece, em vez de deixar a mensagem
 * técnica na cara de quem só queria o PDF.
 */
import { toast } from 'sonner';

/**
 * Cada navegador escreve esta falha com outras palavras, e é sempre a mesma coisa:
 * o arquivo pedido não voltou como JavaScript.
 *
 * O caso do "MIME type" merece explicação: hospedagem de página única devolve o
 * `index.html` para qualquer caminho desconhecido, então o arquivo some e o navegador
 * recebe HTML onde esperava um módulo.
 */
const SINAIS = [
  'failed to fetch dynamically imported module',   // Chrome, Edge
  'error loading dynamically imported module',     // Firefox
  'importing a module script failed',              // Safari
  'unable to preload css',                         // Vite, folha de estilo do chunk
  'is not a valid javascript mime type',           // caiu no index.html
  'failed to load module script',                  // Chrome, mesma causa
  'dynamically imported module',                   // rede de segurança
];

/** O erro é "o arquivo sumiu porque o sistema foi publicado de novo"? */
export function ehChunkQueSumiu(erro: unknown): boolean {
  if (!erro) return false;
  // O empacotador antigo marcava pelo nome; o Vite, pela mensagem.
  const nome = String((erro as { name?: unknown })?.name ?? '');
  if (nome === 'ChunkLoadError') return true;

  const texto = String(
    (erro as { message?: unknown })?.message ?? (typeof erro === 'string' ? erro : ''),
  ).toLowerCase();
  if (!texto) return false;
  return SINAIS.some((s) => texto.includes(s));
}

let jaAvisou = false;

/** Só para o teste: devolve o módulo ao estado de quem ainda não avisou ninguém. */
export function esqueceQueAvisou() {
  jaAvisou = false;
}

/**
 * Avisa que o sistema foi atualizado e oferece recarregar.
 *
 * Uma vez por sessão: o mesmo deploy derruba o próximo clique também, e três avisos
 * empilhados dizem a mesma coisa três vezes. Não recarrega sozinho de propósito —
 * pode haver formulário meio preenchido na tela, e perder o que o usuário digitou
 * para consertar um problema que ele nem viu seria pior que o problema.
 */
export function avisarAppAtualizado() {
  if (jaAvisou || typeof window === 'undefined') return;
  jaAvisou = true;
  toast.warning('O sistema foi atualizado', {
    description: 'Esta aba ainda usa a versão anterior. Recarregue para continuar.',
    duration: Infinity,
    action: {
      label: 'Recarregar',
      onClick: () => window.location.reload(),
    },
  });
}

/**
 * Avisa SE for este caso. Devolve se avisou, para quem chama decidir o que dizer depois.
 */
export function avisarSeForAppAtualizado(erro: unknown): boolean {
  if (!ehChunkQueSumiu(erro)) return false;
  avisarAppAtualizado();
  return true;
}
