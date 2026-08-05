import { useMemo, useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import {
  AlertTriangle, Camera, Check, ClipboardCheck, ClipboardList, Gauge, HelpCircle,
  Loader2, Play,
} from 'lucide-react';
import { toast } from 'sonner';
import {
  useSurveyTrigger, useCaseEstimate, useSurveyQuestions, useServiceOrderSurvey,
  useStartSurvey, useAnswerSurvey, useCloseSurvey, formatMinutes, finalContingency,
  uploadSurveyPhoto, surveyPhotoUrl,
  type SurveyQuestion,
} from '@/hooks/use-service-survey';

/**
 * Levantamento antes de orçar, na tela.
 *
 * Uma pergunta por vez, na ordem de impacto no preço. O botão de fechar só
 * aparece depois da justificativa escrita — decidir sem dizer por quê é o que
 * produz a pergunta ruim seguinte.
 */
export function SurveyPanel({
  serviceOrderId, serviceId, clientId, vesselId, valorEstimado,
}: {
  serviceOrderId?: string;
  serviceId: string | undefined;
  clientId?: string | null;
  vesselId?: string | null;
  valorEstimado?: number | null;
}) {
  const { data: trigger, isLoading: loadingTrigger } = useSurveyTrigger(serviceId, {
    clientId, vesselId, valor: valorEstimado,
  });
  const { data: estimate } = useCaseEstimate(serviceId);
  const { data: questions = [] } = useSurveyQuestions(serviceId, 'local');
  const { data: survey } = useServiceOrderSurvey(serviceOrderId);
  const start = useStartSurvey();
  const answer = useAnswerSurvey();
  const close = useCloseSurvey();

  const [surveyId, setSurveyId] = useState<string | null>(null);
  const [idx, setIdx] = useState(0);
  const [resposta, setResposta] = useState('');
  const [confidence, setConfidence] = useState<'alta' | 'media' | 'baixa' | ''>('');
  const [rationale, setRationale] = useState('');
  const [foto, setFoto] = useState<string | null>(null);
  const [subindo, setSubindo] = useState(false);

  /** O que já foi levantado, para a tela devolver o registro em vez de engolir. */
  const respostas = useMemo(
    () =>
      [...(((survey as any)?.service_survey_answers ?? []) as any[])].sort(
        (a, b) => a.seq - b.seq,
      ),
    [survey],
  );

  const ativo = surveyId || (survey?.status && survey.status !== 'closed' ? survey.id : null);
  const fechado = survey?.status === 'closed';
  const atual: SurveyQuestion | undefined = questions[idx];

  const contingencia = useMemo(
    () => (confidence ? finalContingency(estimate, confidence) : estimate?.contingencia_pct ?? null),
    [estimate, confidence],
  );

  if (!serviceId) {
    return (
      <Card className="p-4">
        <p className="text-sm text-muted-foreground">
          Escolha o serviço para o sistema avaliar se vale levantar antes de orçar.
        </p>
      </Card>
    );
  }

  function handleStart(mode: 'local' | 'remoto') {
    if (questions.length === 0) {
      toast.warning('Este serviço ainda não tem perguntas de levantamento cadastradas.');
      return;
    }
    start.mutate(
      {
        serviceId: serviceId!,
        serviceOrderId,
        clientId, vesselId, mode,
        triggerReason: (trigger?.motivos || []).join(' · ') || 'Levantamento manual',
        questionsPlanned: questions.length,
      },
      {
        onSuccess: (id) => { setSurveyId(id); setIdx(0); setResposta(''); },
        onError: (e: any) => toast.error(e?.message || 'Não deu para abrir o levantamento'),
      },
    );
  }

  function gravar(skip?: string) {
    if (!ativo || !atual) return;
    answer.mutate(
      {
        surveyId: ativo, serviceOrderId, seq: idx + 1,
        question: atual.question, templateId: atual.id,
        answer: skip ? undefined : resposta, skippedReason: skip,
        // A foto vale mesmo quando a resposta escrita ficou em branco: às vezes
        // a imagem é a resposta.
        ...(foto ? { photoPath: foto } : {}),
      },
      {
        onSuccess: () => { setResposta(''); setFoto(null); setIdx((i) => i + 1); },
        onError: (e: any) => toast.error(e?.message || 'Erro ao gravar a resposta'),
      },
    );
  }

  return (
    <Card className="p-4 space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2 text-sm font-semibold">
          <ClipboardCheck className="h-4 w-4 text-primary" /> Levantamento técnico
        </div>
        {fechado && survey?.confidence && (
          <Badge variant="outline" className="text-[11px]">
            confiança {survey.confidence}
          </Badge>
        )}
      </div>

      {/* O gatilho, com o motivo dito em português */}
      {loadingTrigger && <p className="text-sm text-muted-foreground">Avaliando o histórico…</p>}

      {trigger && !ativo && !fechado && (
        <div className={`rounded-md border p-3 text-sm space-y-2 ${
          trigger.precisa ? 'border-amber-500/50 bg-amber-50 dark:bg-amber-950/30' : 'border-dashed'
        }`}>
          {trigger.precisa ? (
            <>
              <p className="flex items-center gap-1.5 font-medium">
                <AlertTriangle className="h-4 w-4 text-amber-600" /> Vale levantar antes de orçar
              </p>
              <ul className="list-disc pl-5 text-xs text-muted-foreground space-y-0.5">
                {trigger.motivos.map((m) => <li key={m}>{m}</li>)}
              </ul>
            </>
          ) : (
            <p className="flex items-center gap-1.5">
              <Check className="h-4 w-4 text-emerald-600" />
              Histórico consistente ({trigger.casos_conhecidos} execução(ões)) — dá para orçar direto.
            </p>
          )}
          <div className="flex flex-wrap gap-2 pt-1">
            <Button size="sm" onClick={() => handleStart('local')} disabled={start.isPending}>
              <Play className="h-4 w-4 mr-1.5" /> Levantar no local
            </Button>
            <Button size="sm" variant="outline" onClick={() => handleStart('remoto')} disabled={start.isPending}>
              <Camera className="h-4 w-4 mr-1.5" /> Pedir foto ao cliente
            </Button>
          </div>
        </div>
      )}

      {/* Uma pergunta por vez */}
      {ativo && !fechado && atual && (
        <div className="space-y-3 rounded-md border p-3">
          <div className="flex items-center justify-between text-xs text-muted-foreground">
            <span>pergunta {idx + 1} de {questions.length}</span>
            <Badge variant="outline" className="text-[10px]">
              impacto {atual.price_impact}
            </Badge>
          </div>
          <p className="font-medium">{atual.question}</p>
          {atual.help_text && (
            <p className="flex items-start gap-1.5 text-xs text-muted-foreground">
              <HelpCircle className="h-3.5 w-3.5 mt-0.5 shrink-0" /> {atual.help_text}
            </p>
          )}

          {atual.answer_type === 'escolha' && atual.options?.length ? (
            <Select value={resposta} onValueChange={setResposta}>
              <SelectTrigger className="h-10"><SelectValue placeholder="Escolha" /></SelectTrigger>
              <SelectContent>
                {atual.options.map((o) => <SelectItem key={o} value={o}>{o}</SelectItem>)}
              </SelectContent>
            </Select>
          ) : (
            <Input
              value={resposta}
              onChange={(e) => setResposta(e.target.value)}
              placeholder={atual.answer_type === 'numero' || atual.answer_type === 'medida' ? 'valor' : 'resposta'}
              className="h-10"
            />
          )}

          {/* A foto sustenta o preço: quem orça de memória orça errado, e quem
              discordar depois não tem o que olhar. Vale em qualquer pergunta,
              não só nas do tipo "foto". */}
          <div className="flex flex-wrap items-center gap-2">
            <label className="inline-flex cursor-pointer items-center gap-1.5 rounded-md border px-2.5 py-1.5 text-xs hover:bg-muted">
              <Camera className="h-3.5 w-3.5" />
              {foto ? 'Trocar foto' : 'Anexar foto'}
              <input
                type="file"
                accept="image/*"
                capture="environment"
                className="hidden"
                onChange={async (e) => {
                  const file = e.target.files?.[0];
                  if (!file || !ativo) return;
                  setSubindo(true);
                  try {
                    setFoto(await uploadSurveyPhoto(ativo, idx + 1, file));
                    toast.success('Foto anexada.');
                  } catch (err: any) {
                    toast.error(err?.message || 'Não deu para subir a foto');
                  } finally {
                    setSubindo(false);
                  }
                }}
              />
            </label>
            {subindo && <Loader2 className="h-3.5 w-3.5 animate-spin text-muted-foreground" />}
            {foto && !subindo && (
              <a
                href={surveyPhotoUrl(foto)} target="_blank" rel="noreferrer"
                className="text-xs text-primary underline"
              >
                ver foto anexada
              </a>
            )}
          </div>

          <div className="grid grid-cols-2 gap-2">
            <Button variant="ghost" onClick={() => gravar('não consegui ver')} disabled={answer.isPending}>
              Não consegui ver
            </Button>
            <Button
              onClick={() => gravar()}
              disabled={(!resposta.trim() && !foto) || answer.isPending}
            >
              Responder
            </Button>
          </div>
        </div>
      )}

      {/* Todas respondidas: registrar confiança e fechar */}
      {ativo && !fechado && !atual && (
        <div className="space-y-3 rounded-md border p-3">
          <p className="text-sm font-medium">Perguntas respondidas. Dá para orçar?</p>
          <Select value={confidence} onValueChange={(v) => setConfidence(v as any)}>
            <SelectTrigger className="h-10"><SelectValue placeholder="Confiança para orçar" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="alta">Alta — dá para orçar agora</SelectItem>
              <SelectItem value="media">Média — falta algo específico</SelectItem>
              <SelectItem value="baixa">Baixa — ainda no escuro</SelectItem>
            </SelectContent>
          </Select>
          <Textarea
            value={rationale}
            onChange={(e) => setRationale(e.target.value)}
            rows={2}
            placeholder="O que você já sabe e o que ficou em aberto. Ex.: sei o acesso e o suporte, não sei se há inversor no barramento."
          />
          <Button
            className="w-full"
            disabled={!confidence || !rationale.trim() || close.isPending}
            onClick={() =>
              close.mutate(
                { surveyId: ativo!, serviceOrderId, confidence: confidence as any, rationale, estimate },
                {
                  onSuccess: () => toast.success('Levantamento fechado.'),
                  onError: (e: any) => toast.error(e?.message || 'Erro ao fechar'),
                },
              )}
          >
            Fechar levantamento
          </Button>
        </div>
      )}

      {/* Estimativa, sempre com os casos que a sustentam */}
      <div className="rounded-md border p-3 space-y-1.5">
        <p className="flex items-center gap-1.5 text-xs font-medium text-muted-foreground uppercase tracking-wide">
          <Gauge className="h-3.5 w-3.5" /> Estimativa por analogia
        </p>
        {estimate?.tem_base ? (
          <>
            <p className="text-sm tabular-nums">
              provável <strong>{formatMinutes(estimate.p50_min)}</strong>
              {' · '}pior caso <strong>{formatMinutes(estimate.p80_min)}</strong>
              {contingencia !== null && <> {' · '}contingência <strong>{contingencia}%</strong></>}
            </p>
            <p className="text-xs text-muted-foreground">
              base: {estimate.casos} execução(ões) —{' '}
              {(estimate.baseado_em || []).map((c) => `${c.os} ${formatMinutes(c.minutos)}`).join(' · ')}
            </p>
          </>
        ) : (
          <p className="text-sm text-muted-foreground">
            {estimate?.mensagem || 'Sem histórico suficiente para estimar por analogia.'}
          </p>
        )}
      </div>

      {/* O que foi levantado, por extenso.
          Antes as respostas eram gravadas e nunca mais apareciam: o técnico
          respondia nove perguntas e nada disso voltava para a tela. Levantamento
          que não deixa registro visível não sustenta preço nem defende o
          orçamento quando alguém questiona três semanas depois. */}
      {respostas.length > 0 && (
        <div className="space-y-2 rounded-md border p-3">
          <p className="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-muted-foreground">
            <ClipboardList className="h-3.5 w-3.5" /> O que foi levantado
          </p>
          <ul className="space-y-2">
            {respostas.map((r) => (
              <li key={r.seq} className="border-b pb-2 text-sm last:border-0 last:pb-0">
                <p className="text-xs text-muted-foreground">{r.question_snapshot}</p>
                <div className="flex flex-wrap items-center gap-2">
                  {r.skipped_reason ? (
                    <span className="text-sm italic text-muted-foreground">
                      não respondida — {r.skipped_reason}
                    </span>
                  ) : (
                    <span className="font-medium">{r.answer_value || '—'}</span>
                  )}
                  {r.photo_path && (
                    <a
                      href={surveyPhotoUrl(r.photo_path)} target="_blank" rel="noreferrer"
                      className="inline-flex items-center gap-1 text-xs text-primary underline"
                    >
                      <Camera className="h-3 w-3" /> foto
                    </a>
                  )}
                </div>
              </li>
            ))}
          </ul>
        </div>
      )}

      {fechado && survey?.confidence_rationale && (
        <p className="text-xs text-muted-foreground border-t pt-2">
          <strong>Quem levantou anotou:</strong> {survey.confidence_rationale}
        </p>
      )}
    </Card>
  );
}
