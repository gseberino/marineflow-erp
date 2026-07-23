import { useState } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { Check, Copy, ThumbsUp, ThumbsDown } from 'lucide-react';
import { cn } from '@/lib/utils';
import { supabase } from '@/integrations/supabase/client';

export function AIChatMessage({
  role,
  content,
}: {
  role: 'user' | 'assistant';
  content: string;
}) {
  const isUser = role === 'user';
  const [copied, setCopied] = useState(false);
  const [rated, setRated] = useState<'up' | 'down' | null>(null);

  const avaliar = async (rating: 'up' | 'down') => {
    setRated(rating);
    try {
      // ai_message_feedback ainda não está nos types gerados.
      await (supabase as unknown as { from: (t: string) => { insert: (v: unknown) => Promise<unknown> } })
        .from('ai_message_feedback')
        .insert({ rating, message_excerpt: content.slice(0, 300) });
    } catch {
      /* best-effort — não bloqueia a UI */
    }
  };

  const copiar = async () => {
    try {
      await navigator.clipboard.writeText(content);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      // Fallback para navegadores/contextos sem Clipboard API.
      const ta = document.createElement('textarea');
      ta.value = content;
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      try { document.execCommand('copy'); setCopied(true); setTimeout(() => setCopied(false), 1500); } catch { /* nada a fazer */ }
      document.body.removeChild(ta);
    }
  };

  return (
    <div className={cn('group flex w-full', isUser ? 'justify-end' : 'justify-start')}>
      <div className="relative max-w-[85%]">
        <div
          className={cn(
            'rounded-lg px-3 py-2 text-sm',
            isUser ? 'bg-primary text-primary-foreground' : 'bg-muted text-foreground'
          )}
        >
          {isUser ? (
            <p className="whitespace-pre-wrap">{content}</p>
          ) : (
            <div className="prose prose-sm dark:prose-invert max-w-none [&>*:first-child]:mt-0 [&>*:last-child]:mb-0">
              <ReactMarkdown remarkPlugins={[remarkGfm]}>{content}</ReactMarkdown>
            </div>
          )}
        </div>

        {/* Ações — aparecem no hover; sempre acessíveis por teclado. */}
        <div
          className={cn(
            'absolute -bottom-2 flex items-center gap-1',
            'opacity-0 transition-opacity group-hover:opacity-100 focus-within:opacity-100',
            rated ? 'opacity-100' : '',
            isUser ? 'left-1' : 'right-1'
          )}
        >
          <button
            type="button"
            onClick={copiar}
            aria-label={copied ? 'Copiado' : 'Copiar mensagem'}
            title={copied ? 'Copiado' : 'Copiar'}
            className="flex h-6 w-6 items-center justify-center rounded-md border bg-background text-muted-foreground shadow-sm hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            {copied ? <Check className="h-3.5 w-3.5 text-green-600" /> : <Copy className="h-3.5 w-3.5" />}
          </button>
          {!isUser && (
            <>
              <button
                type="button"
                onClick={() => avaliar('up')}
                aria-label="Resposta boa"
                title="Resposta boa"
                className={cn(
                  'flex h-6 w-6 items-center justify-center rounded-md border bg-background shadow-sm hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                  rated === 'up' ? 'text-green-600' : 'text-muted-foreground'
                )}
              >
                <ThumbsUp className="h-3.5 w-3.5" />
              </button>
              <button
                type="button"
                onClick={() => avaliar('down')}
                aria-label="Resposta ruim"
                title="Resposta ruim"
                className={cn(
                  'flex h-6 w-6 items-center justify-center rounded-md border bg-background shadow-sm hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                  rated === 'down' ? 'text-red-600' : 'text-muted-foreground'
                )}
              >
                <ThumbsDown className="h-3.5 w-3.5" />
              </button>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
