import { useState, useMemo, useRef } from 'react';
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
import { checkMeasure } from '@/lib/survey-measure';

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
  // NOVO-lev-23: o levantamento criado numa tentativa que falhou é REAPROVEITADO
  // na próxima — sem isto, cada clique em "Lançar folha" após um erro criava
  // mais um levantamento aberto e vazio no banco.
  const surveyIdRef = useRef<string | null>(null);

  const preenchidas = useMemo(
    () => questions.filter((q) => (respostas[q.id] || '').trim()).length,
    [questions, respostas],
  );

  // NOVO-lev-22: na transcrição é que a conferência mais faz falta — quem digita
  // está lendo a letra de outra pessoa dias depois, e é aí que 2,5 vira 25.
  // Mesma rede da tela viva (checkMeasure): AVISA, nunca barra.
  const medidas = useMemo(() => {
    const out: Record<string, ReturnType<typeof checkMeasure>> = {};
    for (const q of questions) {
      const eGrandeza = (q as any).answer_type === 'medida' || (q as any).answer_type === 'numero';
      if (!eGrandeza) continue;
      const texto = (respostas[q.id] || '').trim();
      if (!texto) continue;
      out[q.id] = checkMeasure(texto, {
        unit: (q as any).expected_unit,
        min: (q as any).min_expected,
        max: (q as any).max_expected,
      });
    }
    return out;
  }, [questions, respostas]);

  async function lancar() {
    if (!serviceId) return;
    if (!confidence || !rationale.trim()) {
      toast.error('Diga a confiança e escreva em uma linha o que ficou em aberto.');
      return;
    }
    setSalvando(true);
    try {
      // Um levantamento novo, já fechado: a folha é o registro do que foi feito
      // em campo, não um rascunho a continuar. NOVO-lev-23: se a tentativa
      // anterior criou o levantamento e falhou depois, reaproveita em vez de
      // deixar um órfão aberto e criar outro.
      const surveyId = surveyIdRef.current ?? await start.mutateAsync({
        serviceId,
        serviceOrderId,
        clientId, vesselId,
        mode: 'local',
        triggerReason: 'Folha de campo preenchida à mão',
        questionsPlanned: questions.length,
      });
      surveyIdRef.current = surveyId;

      const linhas = questions.map((q, i) => {
        const resp = (respostas[q.id] || '').trim();
        // NOVO-lev-22: grandeza transcrita com UM número vira número estruturado
        // (é o que o dimensionamento lê); com mais de um, fica só o texto e o
        // aviso na tela já pediu para escrever o total.
        const medida = resp ? medidas[q.id] : undefined;
        const numeroUnico = medida && medida.numberCount === 1 ? medida.value : null;
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
          numeric_value: numeroUnico,
          answer_unit: numeroUnico !== null ? ((q as any).expected_unit ?? null) : null,
        };
      });

      // Upsert por (survey_id, seq): retry após falha parcial REGRAVA as mesmas
      // linhas em vez de duplicá-las (NOVO-lev-23, segunda metade).
      const { error } = await supabase
        .from('service_survey_answers')
        .upsert(linhas, { onConflict: 'survey_id,seq' });
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
      surveyIdRef.current = null;
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
                  {/* NOVO-lev-22: a mesma conferência da tela viva, onde ela mais
                      faz falta — lendo letra alheia é que 2,5 vira 25. */}
                  {medidas[q.id]?.warning && (
                    <p className="text-xs text-amber-700 dark:text-amber-400">
                      {medidas[q.id].warning}
                    </p>
                  )}
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
