import { useState, useEffect, useRef } from 'react';
import { Button } from '@/components/ui/button';
import { Play, Pause, Square, Timer } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

interface ServiceTimerProps {
  serviceLineId: string;
  serviceOrderId: string;
  startedAt: string | null;
  finishedAt: string | null;
  elapsedMinutes: number;
  onUpdate: () => void;
  /**
   * A linha tem passos no Roteiro de Execução. Quando tem, o tempo vem da soma
   * dos passos (trigger rollup_step_time_to_service_line) e este cronômetro vira
   * leitura: dois donos do mesmo número é como o dado se perde.
   */
  managedByRoute?: boolean;
}

export function ServiceTimer({
  serviceLineId,
  serviceOrderId,
  startedAt,
  finishedAt,
  elapsedMinutes,
  onUpdate,
  managedByRoute = false,
}: ServiceTimerProps) {
  // Com o roteiro no comando, este cronômetro é só leitura — não deixa um
  // intervalo rodando invisível no fundo.
  const [running, setRunning] = useState(!managedByRoute && !!startedAt && !finishedAt);
  const [display, setDisplay] = useState(elapsedMinutes * 60);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    if (running) {
      const base = startedAt
        ? Math.floor((Date.now() - new Date(startedAt).getTime()) / 1000) +
          elapsedMinutes * 60
        : elapsedMinutes * 60;
      setDisplay(base);
      intervalRef.current = setInterval(() => setDisplay((d) => d + 1), 1000);
    } else {
      if (intervalRef.current) clearInterval(intervalRef.current);
    }
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [running]);

  const fmt = (s: number) => {
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const sec = s % 60;
    return h > 0
      ? `${h}h ${String(m).padStart(2, '0')}m`
      : `${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}`;
  };

  const handleStart = async () => {
    const { error } = await supabase
      .from('service_order_services')
      .update({ started_at: new Date().toISOString(), finished_at: null })
      .eq('id', serviceLineId);
    if (error) {
      toast.error('Erro ao iniciar timer');
      return;
    }
    setRunning(true);
    onUpdate();
  };

  const handlePause = async () => {
    const elapsed = Math.floor(display / 60);
    const { error } = await supabase
      .from('service_order_services')
      .update({ elapsed_minutes: elapsed })
      .eq('id', serviceLineId);
    if (error) {
      toast.error('Erro ao pausar timer');
      return;
    }
    setRunning(false);
    onUpdate();
  };

  const handleStop = async () => {
    const elapsed = Math.floor(display / 60);
    const { error } = await supabase
      .from('service_order_services')
      .update({
        finished_at: new Date().toISOString(),
        elapsed_minutes: elapsed,
      })
      .eq('id', serviceLineId);
    if (error) {
      toast.error('Erro ao finalizar timer');
      return;
    }
    setRunning(false);
    onUpdate();
  };

  // Roteiro no comando: mostra o total somado dos passos, sem botões. Quem
  // controla o relógio é o Modo Foco, na aba Roteiro.
  if (managedByRoute) {
    return (
      <div
        className="inline-flex items-center gap-1 text-xs text-muted-foreground"
        title="O tempo desta linha vem dos passos do roteiro"
      >
        <Timer className="h-3 w-3" />
        {fmt(elapsedMinutes * 60)}
        <span className="text-[10px] opacity-70">· pelo roteiro</span>
      </div>
    );
  }

  if (finishedAt) {
    return (
      <div className="inline-flex items-center gap-1 text-xs text-muted-foreground">
        <Timer className="h-3 w-3" />
        {fmt(elapsedMinutes * 60)} (concluído)
      </div>
    );
  }

  return (
    <div className="inline-flex items-center gap-2">
      <span className="font-mono text-xs tabular-nums">{fmt(display)}</span>
      {!running ? (
        <Button
          type="button"
          variant="outline"
          size="icon"
          className="h-7 w-7"
          onClick={handleStart}
          title="Iniciar"
        >
          <Play className="h-3.5 w-3.5" />
        </Button>
      ) : (
        <>
          <Button
            type="button"
            variant="outline"
            size="icon"
            className="h-7 w-7"
            onClick={handlePause}
            title="Pausar"
          >
            <Pause className="h-3.5 w-3.5" />
          </Button>
          <Button
            type="button"
            variant="outline"
            size="icon"
            className="h-7 w-7 text-destructive"
            onClick={handleStop}
            title="Finalizar"
          >
            <Square className="h-3.5 w-3.5" />
          </Button>
        </>
      )}
    </div>
  );
}
