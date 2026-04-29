import { useEffect, useRef, useState } from 'react';
import { Sparkles, Send, Loader2, RotateCcw, X, Mic, MicOff } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { Textarea } from '@/components/ui/textarea';
import { useAuth } from '@/hooks/use-auth';
import { useAIContext } from '@/lib/ai-context';
import { useAIAgent } from '@/hooks/use-ai-agent';
import { AIChatMessage } from './AIChatMessage';
import { AIConfirmCard } from './AIConfirmCard';
import { toast } from 'sonner';

export function AIAgentWidget() {
  const { user } = useAuth();
  const [open, setOpen] = useState(false);
  const [input, setInput] = useState('');
  const context = useAIContext();
  const { display, loading, loadingMsg, sendMessage, confirmProposal, cancelProposal, reset, activeProposal } =
    useAIAgent(context);
  const scrollRef = useRef<HTMLDivElement>(null);

  // Voice Input State
  const [isListening, setIsListening] = useState(false);
  const recognitionRef = useRef<any>(null);

  useEffect(() => {
    if (typeof window !== 'undefined' && ('SpeechRecognition' in window || 'webkitSpeechRecognition' in window)) {
      const SpeechRecognition = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
      recognitionRef.current = new SpeechRecognition();
      recognitionRef.current.continuous = true;
      recognitionRef.current.interimResults = false;
      recognitionRef.current.lang = 'pt-BR';

      recognitionRef.current.onresult = (event: any) => {
        let finalTranscript = '';
        for (let i = event.resultIndex; i < event.results.length; ++i) {
          if (event.results[i].isFinal) {
            finalTranscript += event.results[i][0].transcript;
          }
        }
        if (finalTranscript) {
          setInput((prev) => {
            const separator = prev && !prev.endsWith(' ') ? ' ' : '';
            return prev + separator + finalTranscript;
          });
        }
      };

      recognitionRef.current.onerror = (event: any) => {
        console.error("Speech recognition error", event.error);
        setIsListening(false);
      };

      recognitionRef.current.onend = () => {
        setIsListening(false);
      };
    }
    return () => {
      if (recognitionRef.current) {
         recognitionRef.current.stop();
      }
    };
  }, []);

  const toggleListening = () => {
    if (isListening) {
      recognitionRef.current?.stop();
      setIsListening(false);
    } else {
      if (!recognitionRef.current) {
        toast.error('Seu navegador não suporta reconhecimento de voz.');
        return;
      }
      try {
        recognitionRef.current.start();
        setIsListening(true);
      } catch (e) {
        console.error(e);
      }
    }
  };

  useEffect(() => {
    if (scrollRef.current) scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
  }, [display, loading]);

  if (!user) return null;

  const [pos, setPos] = useState({ bottom: 24, right: 24 });
  const dragging = useRef(false);
  const startPos = useRef({ x: 0, y: 0, bottom: 24, right: 24 });

  const onPointerDown = (e: React.PointerEvent) => {
    dragging.current = true;
    startPos.current = {
      x: e.clientX,
      y: e.clientY,
      bottom: pos.bottom,
      right: pos.right,
    };
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
  };

  const onPointerMove = (e: React.PointerEvent) => {
    if (!dragging.current) return;
    const dx = e.clientX - startPos.current.x;
    const dy = e.clientY - startPos.current.y;
    setPos({
      bottom: Math.max(8, startPos.current.bottom - dy),
      right: Math.max(8, startPos.current.right - dx),
    });
  };

  const onPointerUp = (e: React.PointerEvent) => {
    dragging.current = false;
  };

  const onClick = (e: React.MouseEvent) => {
    const dx = Math.abs(e.clientX - startPos.current.x);
    const dy = Math.abs(e.clientY - startPos.current.y);
    if (dx > 5 || dy > 5) return;
    setOpen(true);
  };

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
              <div className="min-w-0">
                <SheetTitle className="flex items-center gap-2">
                  <Sparkles className="h-5 w-5 text-primary" />
                  Assistente IA
                </SheetTitle>
                {context.entityType && context.entityType !== 'unknown' && (
                  <div className="flex items-center gap-1.5 mt-1 px-2 py-1 rounded-md bg-primary/10 w-fit">
                    <span className="text-xs font-medium text-primary">
                      {context.entityType === 'service_order' ? '📋 Ordem de Serviço em contexto' :
                       context.entityType === 'client' ? '👤 Cliente em contexto' :
                       context.entityType === 'vessel' ? '⛵ Embarcação em contexto' :
                       context.entityType === 'agenda' ? '📅 Agenda em contexto' :
                       context.entityType === 'products' ? '📦 Produtos em contexto' :
                       context.entityType === 'financial' ? '💰 Financeiro em contexto' :
                       `${context.entityType} em contexto`}
                    </span>
                  </div>
                )}
              </div>
              <Button variant="ghost" size="sm" onClick={reset} title="Nova conversa">
                <RotateCcw className="h-4 w-4" />
              </Button>
            </div>
          </SheetHeader>

          <div ref={scrollRef} className="flex-1 overflow-y-auto p-4 space-y-3">
            {display.length === 0 && !loading && (() => {
              const suggestions = context.entityType === 'service_order' ? [
                "Adicione um serviço de mão de obra nesta OS",
                "Qual o valor total desta OS?",
                "Agende esta OS para amanhã às 9h",
                "Otimize a descrição do problema desta OS",
                "Envie o link desta OS para o cliente",
              ] : context.entityType === 'client' ? [
                "Mostre o histórico de OSs deste cliente",
                "Crie uma nova OS para este cliente",
                "Quais cobranças estão pendentes para este cliente?",
                "Envie uma mensagem para este cliente",
              ] : context.entityType === 'vessel' ? [
                "Mostre o histórico de serviços desta embarcação",
                "Crie uma OS para esta embarcação",
              ] : [
                "Crie uma OS para o barco do João",
                "Quais tarefas tenho hoje na agenda?",
                "Liste as OSs em andamento",
                "Envie um lembrete de cobrança para a Maria",
                "Cadastre o cliente Carlos, telefone 47 99999-0000",
              ];
              return (
                <div className="space-y-3">
                  <p className="text-sm font-medium text-foreground">Como posso ajudar?</p>
                  <div className="flex flex-col gap-1.5">
                    {suggestions.map((s, i) => (
                      <button
                        key={i}
                        onClick={() => sendMessage(s)}
                        className="text-left text-sm px-3 py-2 rounded-lg bg-muted hover:bg-muted/80 transition-colors text-muted-foreground hover:text-foreground"
                      >
                        {s}
                      </button>
                    ))}
                  </div>
                </div>
              );
            })()}

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
                {loadingMsg || 'Processando…'}
              </div>
            )}
          </div>

          <div className="border-t p-3">
            <div className="flex gap-2 items-end">
              <Button
                variant={isListening ? "destructive" : "outline"}
                size="icon"
                onClick={toggleListening}
                disabled={loading}
                title={isListening ? "Parar de ouvir" : "Falar (Ditado)"}
                className={`shrink-0 ${isListening ? 'animate-pulse' : ''}`}
              >
                {isListening ? <MicOff className="h-4 w-4" /> : <Mic className="h-4 w-4" />}
              </Button>
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
