import { useState, useMemo } from 'react';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Loader2 } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { useSurveyQuestions, useStartSurvey } from '@/hooks/use-service-survey';

/**
 * Lançar a folha que voltou do campo — tudo de uma vez.
 *
 * O levantamento na tela pergunta uma coisa por vez, e isso é certo em campo:
 * quem está de pé, com luva, responde uma e passa. Mas quem volta com a folha
 * PREENCHIDA está sentado, com nove respostas na mão, e a fila de uma em uma
 * vira um formulário de nove telas. O que acontece então é o que sempre
 * acontece: o papel fica na gaveta e o levantamento nunca entra no sistema.
 *
 * Aqui é o contrário: tudo na frente, transcrição direta, e o que ficou em
 * branco no papel fica em branco aqui — campo vazio vira "não respondida", não
 * some. A diferença importa: pergunta não respondida é informação (alguém não
 * conseguiu ver), pergunta ausente é esquecimento.
 */
export function SurveySheetEntryDialog({
  open, onOpenChange, serviceOrderId, serviceId, clientId, vesselId, orderNumber,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  serviceOrderId?: string;
  serviceId: string | undefined;
  clientId?: string | null;
  vesselId?: string | null;
  orderNumber?: string | null;
}) {
  const { data: questions = [] } = useSurveyQuestions(serviceId, 'local');
  const start = useStartSurvey();

  const [respostas, setRespostas] = useState<Record<string, string>>({});
  const [motivos, setMotivos] = useState<Record<string, string>>({});
  const [confidence, setConfidence] = useState<'alta' | 'media' | 'baixa' | ''>('');
  const [rationale, setRationale] = useState('');
  const [extras, setExtras] = useState('');
  const [salvando, setSalvando] = useState(false);

  const preenchidas = useMemo(
    () => questions.filter((q) => (respostas[q.id] || '').trim()).length,
    [questions, respostas],
  );

  async function lancar() {
    if (!serviceId) return;
    if (!confidence || !rationale.trim()) {
      toast.error('Diga a confiança e escreva em uma linha o que ficou em aberto.');
      return;
    }
    setSalvando(true);
    try {
      // Um levantamento novo, já fechado: a folha é o registro do que foi feito
      // em campo, não um rascunho a continuar.
      const surveyId = await start.mutateAsync({
        serviceId,
        serviceOrderId,
        clientId, vesselId,
        mode: 'local',
        triggerReason: 'Folha de campo preenchida à mão',
        questionsPlanned: questions.length,
      });

      const linhas = questions.map((q, i) => {
        const resp = (respostas[q.id] || '').trim();
        return {
          survey_id: surveyId,
          template_id: q.id,
          seq: i + 1,
          question_snapshot: q.question,
          answer_value: resp || null,
          // Campo em branco no papel NÃO é resposta vazia: é algo que não deu
          // para verificar, e isso vira contingência no preço.
          skipped_reason: resp
            ? null
            : (motivos[q.id] || '').trim() || 'em branco na folha de campo',
        };
      });

      const { error } = await supabase.from('service_survey_answers').insert(linhas);
      if (error) throw error;

      // O bloco "enquanto eu estava lá" entra junto da justificativa: é ali que
      // o preço vai ser defendido depois.
      const justificativa = extras.trim()
        ? `${rationale.trim()}\n\nEnquanto estava lá: ${extras.trim()}`
        : rationale.trim();

      const { error: e2 } = await supabase
        .from('service_surveys')
        .update({
          status: 'closed',
          confidence,
          confidence_rationale: justificativa,
          answered_at: new Date().toISOString(),
        })
        .eq('id', surveyId);
      if (e2) throw e2;

      toast.success(`Folha lançada: ${preenchidas} de ${questions.length} respondidas.`);
      onOpenChange(false);
      setRespostas({}); setMotivos({}); setConfidence(''); setRationale(''); setExtras('');
    } catch (e: any) {
      console.error('[folha] lançamento falhou:', e);
      toast.error(e?.message || 'Não deu para lançar a folha.');
    } finally {
      setSalvando(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={(v) => { if (!salvando) onOpenChange(v); }}>
      <DialogContent className="max-h-[88vh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Lançar a folha de campo{orderNumber ? ` — ${orderNumber}` : ''}</DialogTitle>
          <DialogDescription>
            Transcreva o que está escrito no papel. O que ficou em branco lá pode ficar em
            branco aqui — vira "não verificado", e isso conta no preço.
          </DialogDescription>
        </DialogHeader>

        {questions.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            Este serviço ainda não tem perguntas de levantamento aprovadas.
          </p>
        ) : (
          <div className="space-y-3">
            {questions.map((q, i) => {
              const vazia = !(respostas[q.id] || '').trim();
              return (
                <div key={q.id} className="space-y-1.5 rounded-md border p-2.5">
                  <div className="flex items-start justify-between gap-2">
                    <p className="min-w-0 flex-1 text-sm font-medium">
                      <span className="mr-1.5 text-muted-foreground">{i + 1}.</span>
                      {q.question}
                    </p>
                    {q.price_impact === 'alto' && (
                      <Badge variant="outline" className="shrink-0 border-amber-500 text-[10px] text-amber-700 dark:text-amber-400">
                        muda o preço
                      </Badge>
                    )}
                  </div>
                  <Input
                    value={respostas[q.id] || ''}
                    onChange={(e) => setRespostas((s) => ({ ...s, [q.id]: e.target.value }))}
                    placeholder="o que está escrito na folha"
                    className="h-9"
                  />
                  {/* Só aparece quando ficou em branco: perguntar o motivo de
                      algo que foi respondido seria ruído. */}
                  {vazia && (
                    <Input
                      value={motivos[q.id] || ''}
                      onChange={(e) => setMotivos((s) => ({ ...s, [q.id]: e.target.value }))}
                      placeholder="por que não deu para verificar (opcional)"
                      className="h-8 text-xs"
                    />
                  )}
                </div>
              );
            })}

            <div className="space-y-1.5 rounded-md border border-dashed p-2.5">
              <p className="text-sm font-medium">Enquanto estava lá</p>
              <p className="text-xs text-muted-foreground">
                O que o cliente pediu além do combinado, e o que você viu que vai dar
                problema. É aqui que o preço se defende depois.
              </p>
              <Textarea
                value={extras}
                onChange={(e) => setExtras(e.target.value)}
                rows={2}
                placeholder="copie do bloco da folha"
              />
            </div>

            <div className="space-y-2 rounded-md border p-2.5">
              <p className="text-sm font-medium">Dá para orçar com o que foi visto?</p>
              <div className="flex flex-wrap gap-2">
                {([
                  ['alta', 'Sim, com segurança'],
                  ['media', 'Sim, com ressalva'],
                  ['baixa', 'Não — precisa voltar'],
                ] as const).map(([v, label]) => (
                  <Button
                    key={v}
                    size="sm"
                    variant={confidence === v ? 'default' : 'outline'}
                    onClick={() => setConfidence(v)}
                  >
                    {label}
                  </Button>
                ))}
              </div>
              <Textarea
                value={rationale}
                onChange={(e) => setRationale(e.target.value)}
                rows={2}
                placeholder="Em uma linha: o que já se sabe e o que ficou em aberto."
              />
            </div>
          </div>
        )}

        <div className="flex flex-wrap items-center justify-between gap-2 border-t pt-3">
          <span className="text-xs text-muted-foreground">
            {preenchidas} de {questions.length} respondidas
          </span>
          <div className="flex gap-2">
            <Button variant="ghost" onClick={() => onOpenChange(false)} disabled={salvando}>
              Cancelar
            </Button>
            <Button onClick={lancar} disabled={salvando || questions.length === 0}>
              {salvando && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />}
              Lançar folha
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
