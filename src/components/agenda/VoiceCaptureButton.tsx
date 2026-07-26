import { useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Mic, Square, Loader2 } from 'lucide-react';
import { cn } from '@/lib/utils';
import { toast } from 'sonner';
import { useVoiceCapture } from '@/hooks/use-agenda';

/**
 * Gravador de recado (Fase 9): fala → transcrição (Groq) → sugestões na caixa de entrada.
 * Um recado pode virar várias tarefas. Nada é criado direto — tudo passa pela caixa.
 */
export function VoiceCaptureButton() {
  const [recording, setRecording] = useState(false);
  const [seconds, setSeconds] = useState(0);
  const recorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const timerRef = useRef<number | null>(null);
  const capture = useVoiceCapture();

  const supported = typeof window !== 'undefined'
    && typeof navigator !== 'undefined'
    && !!navigator.mediaDevices?.getUserMedia
    && typeof MediaRecorder !== 'undefined';

  const stopTimer = () => {
    if (timerRef.current !== null) { window.clearInterval(timerRef.current); timerRef.current = null; }
    setSeconds(0);
  };

  const start = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const mime = MediaRecorder.isTypeSupported('audio/webm') ? 'audio/webm' : '';
      const rec = new MediaRecorder(stream, mime ? { mimeType: mime } : undefined);
      chunksRef.current = [];
      rec.ondataavailable = (e) => { if (e.data.size > 0) chunksRef.current.push(e.data); };
      rec.onstop = async () => {
        stream.getTracks().forEach((t) => t.stop());
        stopTimer();
        const blob = new Blob(chunksRef.current, { type: rec.mimeType || 'audio/webm' });
        if (blob.size < 1200) { toast.error('Recado muito curto'); return; }
        const buf = await blob.arrayBuffer();
        // base64 sem estourar a pilha em áudios maiores
        let binary = '';
        const bytes = new Uint8Array(buf);
        for (let i = 0; i < bytes.length; i += 8192) {
          binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
        }
        capture.mutate(
          { audioBase64: btoa(binary), mimetype: rec.mimeType || 'audio/webm' },
          {
            onSuccess: (res) => {
              if (res.sugestoes > 0) {
                toast.success(`${res.sugestoes} sugestão(ões) na caixa de entrada`, {
                  description: res.itens.join(' · '),
                });
              } else {
                toast.info(res.mensagem || 'Não identifiquei tarefas nesse recado', {
                  description: res.transcript?.slice(0, 120),
                });
              }
            },
            onError: (e: any) => toast.error(e?.message || 'Erro ao processar o recado'),
          },
        );
      };
      rec.start();
      recorderRef.current = rec;
      setRecording(true);
      setSeconds(0);
      timerRef.current = window.setInterval(() => setSeconds((s) => {
        if (s >= 119) { rec.stop(); setRecording(false); return 0; } // teto de 2 min
        return s + 1;
      }), 1000);
    } catch {
      toast.error('Não consegui acessar o microfone. Verifique a permissão do navegador.');
    }
  };

  const stop = () => {
    recorderRef.current?.stop();
    setRecording(false);
  };

  if (!supported) return null;

  return (
    <Button
      size="sm"
      variant={recording ? 'destructive' : 'outline'}
      onClick={recording ? stop : start}
      disabled={capture.isPending}
      title="Ditar um recado: vira sugestão de tarefa"
      className={cn(recording && 'animate-pulse')}
    >
      {capture.isPending
        ? <Loader2 className="h-4 w-4 animate-spin" />
        : recording
          ? <><Square className="h-4 w-4 mr-1" /> {seconds}s</>
          : <Mic className="h-4 w-4" />}
    </Button>
  );
}
