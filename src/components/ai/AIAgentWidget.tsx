import { useEffect, useRef, useState } from 'react';
import { Sparkles, Send, Loader2, RotateCcw, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { Textarea } from '@/components/ui/textarea';
import { useAuth } from '@/hooks/use-auth';
import { useAIContext } from '@/lib/ai-context';
import { useAIAgent } from '@/hooks/use-ai-agent';
import { AIChatMessage } from './AIChatMessage';
import { AIConfirmCard } from './AIConfirmCard';

export function AIAgentWidget() {
  const { user } = useAuth();
  const [open, setOpen] = useState(false);
  const [input, setInput] = useState('');
  const context = useAIContext();
  const { display, loading, sendMessage, confirmProposal, cancelProposal, reset, activeProposal } =
    useAIAgent(context);
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (scrollRef.current) scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
  }, [display, loading]);

  if (!user) return null;

  const handleSend = () => {
    const txt = input.trim();
    if (!txt || loading) return;
    setInput('');
    sendMessage(txt);
  };

  const handleKey = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  return (
    <>
      {/* Floating button */}
      <button
        onClick={() => setOpen(true)}
        className="fixed bottom-6 right-6 z-40 h-14 w-14 rounded-full bg-primary text-primary-foreground shadow-lg hover:scale-105 transition-transform flex items-center justify-center"
        aria-label="Abrir Assistente de IA"
        title="Assistente de IA"
      >
        <Sparkles className="h-6 w-6" />
      </button>

      <Sheet open={open} onOpenChange={setOpen}>
        <SheetContent side="right" className="w-full sm:max-w-md flex flex-col p-0 gap-0">
          <SheetHeader className="px-4 py-3 border-b">
            <div className="flex items-center justify-between">
              <SheetTitle className="flex items-center gap-2">
                <Sparkles className="h-5 w-5 text-primary" />
                Assistente IA
              </SheetTitle>
              <Button variant="ghost" size="sm" onClick={reset} title="Nova conversa">
                <RotateCcw className="h-4 w-4" />
              </Button>
            </div>
          </SheetHeader>

          <div ref={scrollRef} className="flex-1 overflow-y-auto p-4 space-y-3">
            {display.length === 0 && !loading && (
              <div className="text-sm text-muted-foreground space-y-2">
                <p className="font-medium text-foreground">Olá! Como posso ajudar?</p>
                <p>Exemplos:</p>
                <ul className="list-disc pl-5 space-y-1">
                  <li>"Crie uma OS para o barco do João amanhã às 10h"</li>
                  <li>"Quais minhas tarefas de hoje?"</li>
                  <li>"Envie um lembrete de cobrança para a Maria"</li>
                  <li>"Cadastre o cliente Carlos, telefone 11 99999-0000"</li>
                  <li>"Liste as OSs em andamento"</li>
                </ul>
              </div>
            )}

            {display.map((item, i) => {
              if (item.kind === 'message') {
                return <AIChatMessage key={i} role={item.role} content={item.content} />;
              }
              if (item.kind === 'proposal') {
                return (
                  <AIConfirmCard
                    key={i}
                    proposal={item.proposal}
                    status={item.status}
                    onConfirm={confirmProposal}
                    onCancel={cancelProposal}
                    disabled={loading || !activeProposal}
                  />
                );
              }
              return null;
            })}

            {loading && (
              <div className="flex items-center gap-2 text-sm text-muted-foreground">
                <Loader2 className="h-4 w-4 animate-spin" />
                Processando…
              </div>
            )}
          </div>

          <div className="border-t p-3">
            <div className="flex gap-2">
              <Textarea
                value={input}
                onChange={(e) => setInput(e.target.value)}
                onKeyDown={handleKey}
                placeholder="Pergunte ou descreva uma ação…"
                rows={2}
                disabled={loading}
                className="resize-none text-sm"
              />
              <Button onClick={handleSend} disabled={loading || !input.trim()} size="icon">
                <Send className="h-4 w-4" />
              </Button>
            </div>
            <p className="text-[10px] text-muted-foreground mt-1">
              Enter envia · Shift+Enter quebra linha
            </p>
          </div>
        </SheetContent>
      </Sheet>
    </>
  );
}
