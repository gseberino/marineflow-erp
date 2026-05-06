import React, { useEffect, useRef, useState, useCallback } from 'react';
import { createPortal } from 'react-dom';
import { Sparkles, Send, Loader2, RotateCcw, X, Mic, MicOff } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { useAuth } from '@/hooks/use-auth';
import { useAIContext } from '@/lib/ai-context';
import { useAIAgent } from '@/hooks/use-ai-agent';
import { AIChatMessage } from './AIChatMessage';
import { AIConfirmCard } from './AIConfirmCard';
import { AIOptionsCard } from './AIOptionsCard';
import { toast } from 'sonner';

function DraggableAIButton({ onOpen }: { onOpen: () => void }) {
  const [pos, setPos] = React.useState({ bottom: 24, right: 24 });
  const isDragging = React.useRef(false);
  const hasMoved = React.useRef(false);
  const startRef = React.useRef({ x: 0, y: 0, bottom: 24, right: 24 });

  const handlePointerDown = (e: React.PointerEvent<HTMLButtonElement>) => {
    isDragging.current = true;
    hasMoved.current = false;
    startRef.current = {
      x: e.clientX,
      y: e.clientY,
      bottom: pos.bottom,
      right: pos.right,
    };
    e.currentTarget.setPointerCapture(e.pointerId);
    e.preventDefault();
  };

  const handlePointerMove = (e: React.PointerEvent<HTMLButtonElement>) => {
    if (!isDragging.current) return;
    const dx = e.clientX - startRef.current.x;
    const dy = e.clientY - startRef.current.y;
    if (Math.abs(dx) > 4 || Math.abs(dy) > 4) hasMoved.current = true;
    const newBottom = Math.max(8, Math.min(window.innerHeight - 64, startRef.current.bottom - dy));
    const newRight = Math.max(8, Math.min(window.innerWidth - 64, startRef.current.right - dx));
    setPos({ bottom: newBottom, right: newRight });
  };

  const handlePointerUp = () => {
    isDragging.current = false;
  };

  const handleClick = () => {
    if (!hasMoved.current) onOpen();
  };

  return (
    <button
      style={{ bottom: pos.bottom, right: pos.right, position: 'fixed' }}
      className="z-40 h-14 w-14 rounded-full bg-primary text-primary-foreground shadow-lg flex items-center justify-center touch-none select-none cursor-grab active:cursor-grabbing"
      aria-label="Abrir Assistente de IA"
      title="Assistente de IA — arraste para mover"
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={handlePointerUp}
      onClick={handleClick}
    >
      <Sparkles className="h-6 w-6" />
    </button>
  );
}

// Hook para acompanhar o visualViewport (teclado virtual no mobile)
function useVisualViewportHeight() {
  const [height, setHeight] = useState(() =>
    typeof window !== 'undefined' ? (window.visualViewport?.height ?? window.innerHeight) : 600
  );
  useEffect(() => {
    const vv = window.visualViewport;
    if (!vv) return;
    const update = () => setHeight(vv.height);
    vv.addEventListener('resize', update);
    vv.addEventListener('scroll', update);
    return () => {
      vv.removeEventListener('resize', update);
      vv.removeEventListener('scroll', update);
    };
  }, []);
  return height;
}

export function AIAgentWidget() {
  const { user } = useAuth();
  const [open, setOpen] = useState(false);
  const [input, setInput] = useState('');
  const context = useAIContext();
  const { display, loading, loadingMsg, sendMessage, confirmProposal, cancelProposal, selectOption, reset, activeProposal, activeOptions } =
    useAIAgent(context);
  const scrollRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const vpHeight = useVisualViewportHeight();

  // Altura do popup: 78% da viewport visível (respeita teclado virtual)
  const popupHeight = Math.min(Math.round(vpHeight * 0.78), 640);

  // Voice Input
  const [isListening, setIsListening] = useState(false);
  const recognitionRef = useRef<any>(null);

  useEffect(() => {
    if (typeof window !== 'undefined' && ('SpeechRecognition' in window || 'webkitSpeechRecognition' in window)) {
      const SR = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
      recognitionRef.current = new SR();
      recognitionRef.current.continuous = true;
      recognitionRef.current.interimResults = false;
      recognitionRef.current.lang = 'pt-BR';
      recognitionRef.current.onresult = (event: any) => {
        let t = '';
        for (let i = event.resultIndex; i < event.results.length; ++i) {
          if (event.results[i].isFinal) t += event.results[i][0].transcript;
        }
        if (t) setInput((prev) => prev + (prev && !prev.endsWith(' ') ? ' ' : '') + t);
      };
      recognitionRef.current.onerror = () => setIsListening(false);
      recognitionRef.current.onend = () => setIsListening(false);
    }
    return () => recognitionRef.current?.stop();
  }, []);

  const toggleListening = useCallback(() => {
    if (isListening) {
      recognitionRef.current?.stop();
      setIsListening(false);
    } else {
      if (!recognitionRef.current) { toast.error('Seu navegador não suporta reconhecimento de voz.'); return; }
      try { recognitionRef.current.start(); setIsListening(true); } catch (e) { console.error(e); }
    }
  }, [isListening]);

  // Fecha ao pressionar Escape
  useEffect(() => {
    if (!open) return;
    const handler = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(false); };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [open]);

  // Scroll para o fim ao receber nova mensagem
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
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleSend(); }
  };

  const entityLabel =
    context.entityType === 'service_order' ? '📋 OS em contexto' :
    context.entityType === 'client' ? '👤 Cliente em contexto' :
    context.entityType === 'vessel' ? '⛵ Embarcação em contexto' :
    context.entityType === 'agenda' ? '📅 Agenda em contexto' :
    context.entityType === 'products' ? '📦 Produtos em contexto' :
    context.entityType === 'financial' ? '💰 Financeiro em contexto' : null;

  const suggestions =
    context.entityType === 'service_order' ? [
      'Adicione mão de obra nesta OS',
      'Qual o valor total desta OS?',
      'Agende para amanhã às 9h',
      'Envie o link desta OS para o cliente',
    ] : context.entityType === 'client' ? [
      'Histórico de OSs deste cliente',
      'Crie uma nova OS para este cliente',
      'Cobranças pendentes deste cliente',
    ] : context.entityType === 'vessel' ? [
      'Histórico de serviços desta embarcação',
      'Crie uma OS para esta embarcação',
    ] : [
      'Crie uma OS para o barco do João',
      'Tarefas de hoje na agenda',
      'OSs em andamento',
      'Cadastre o cliente Carlos, tel 47 99999-0000',
    ];

  const popup = open ? (
    <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center px-3 pb-4 sm:pb-0">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/50 backdrop-blur-sm"
        onClick={() => setOpen(false)}
        aria-hidden
      />

      {/* Popup */}
      <div
        className="relative w-full max-w-md rounded-2xl bg-background shadow-2xl flex flex-col overflow-hidden border border-border"
        style={{ height: popupHeight }}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-4 py-3 border-b shrink-0">
          <div className="flex items-center gap-2 min-w-0">
            <Sparkles className="h-5 w-5 text-primary shrink-0" />
            <span className="font-semibold text-sm">Assistente IA</span>
            {entityLabel && context.entityType !== 'unknown' && (
              <span className="text-xs px-2 py-0.5 rounded-full bg-primary/10 text-primary font-medium truncate">
                {entityLabel}
              </span>
            )}
          </div>
          <div className="flex items-center gap-1 shrink-0">
            <Button variant="ghost" size="icon" className="h-8 w-8" onClick={reset} title="Nova conversa">
              <RotateCcw className="h-3.5 w-3.5" />
            </Button>
            <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => setOpen(false)} title="Fechar">
              <X className="h-4 w-4" />
            </Button>
          </div>
        </div>

        {/* Messages */}
        <div ref={scrollRef} className="flex-1 overflow-y-auto p-4 space-y-3">
          {display.length === 0 && !loading && (
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
          )}

          {display.map((item, i) => {
            if (item.kind === 'message')
              return <AIChatMessage key={i} role={item.role} content={item.content} />;
            if (item.kind === 'proposal')
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
            if (item.kind === 'options')
              return (
                <AIOptionsCard
                  key={i}
                  question={item.data.question}
                  options={item.data.options}
                  status={item.status}
                  selectedValue={item.selectedValue}
                  onSelect={selectOption}
                />
              );
            return null;
          })}

          {loading && (
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <Loader2 className="h-4 w-4 animate-spin" />
              {loadingMsg || 'Processando…'}
            </div>
          )}
        </div>

        {/* Input */}
        <div className="border-t px-3 py-2.5 shrink-0">
          <div className="flex gap-2 items-end">
            <Button
              variant={isListening ? 'destructive' : 'outline'}
              size="icon"
              onClick={toggleListening}
              disabled={loading}
              className={`h-9 w-9 shrink-0 ${isListening ? 'animate-pulse' : ''}`}
              title={isListening ? 'Parar de ouvir' : 'Falar'}
            >
              {isListening ? <MicOff className="h-4 w-4" /> : <Mic className="h-4 w-4" />}
            </Button>
            <Textarea
              ref={textareaRef}
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={handleKey}
              placeholder="Pergunte ou descreva uma ação…"
              rows={1}
              disabled={loading}
              className="resize-none text-sm min-h-[36px] max-h-[80px] py-2"
            />
            <Button
              onClick={handleSend}
              disabled={loading || !input.trim()}
              size="icon"
              className="h-9 w-9 shrink-0"
            >
              <Send className="h-4 w-4" />
            </Button>
          </div>
          <p className="text-[10px] text-muted-foreground mt-1 text-center">
            Enter envia · Shift+Enter quebra linha
          </p>
        </div>
      </div>
    </div>
  ) : null;

  return (
    <>
      <DraggableAIButton onOpen={() => setOpen(true)} />
      {typeof document !== 'undefined' ? createPortal(popup, document.body) : popup}
    </>
  );
}
