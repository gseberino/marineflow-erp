import { useMemo, useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import {
  Check, ChevronDown, ChevronRight, ClipboardList, Loader2, Pencil, Send, Sparkles, X,
} from 'lucide-react';
import { toast } from 'sonner';
import {
  useSurveyTemplates, useApproveSurveyQuestion, useRejectSurveyQuestion,
  useUpdateSurveyQuestion, surveyPendingApproval, groupSurveyQuestions,
  type SurveyTemplate,
} from '@/hooks/use-survey-templates';

const IMPACT_LABEL: Record<string, string> = {
  alto: 'muda o preço', medio: 'pesa no preço', baixo: 'bom saber',
};
const ANSWER_LABEL: Record<string, string> = {
  sim_nao: 'sim/não', escolha: 'escolha', numero: 'número',
  texto: 'texto', foto: 'foto', medida: 'medida',
};

/**
 * Perguntas de levantamento — o que se pergunta antes de orçar.
 *
 * Mesma disciplina dos blocos: a pergunta pertence ao sistema ou ao verbo, e
 * nenhuma entra em uso sem assinatura. O selo "pode pedir ao cliente" marca as
 * que um leigo responde com uma foto — são elas, e só elas, que o botão
 * "Pedir foto ao cliente" envia.
 */
export function SurveyQuestionsSection() {
  const { data: questions = [], isLoading } = useSurveyTemplates();
  const approve = useApproveSurveyQuestion();
  const reject = useRejectSurveyQuestion();
  const update = useUpdateSurveyQuestion();

  const [aberto, setAberto] = useState<Record<string, boolean>>({});
  const [editando, setEditando] = useState<string | null>(null);
  const [rascunho, setRascunho] = useState({ question: '', help_text: '' });

  const grupos = useMemo(() => groupSurveyQuestions(questions), [questions]);
  const totalPendente = useMemo(() => questions.filter(surveyPendingApproval).length, [questions]);

  function abrirEdicao(q: SurveyTemplate) {
    setEditando(q.id);
    setRascunho({ question: q.question, help_text: q.help_text || '' });
  }

  function salvarEAprovar(q: SurveyTemplate) {
    const mudou =
      rascunho.question.trim() !== q.question ||
      (rascunho.help_text.trim() || null) !== q.help_text;

    update.mutate(
      { id: q.id, patch: { question: rascunho.question.trim(), help_text: rascunho.help_text.trim() || null } },
      {
        onSuccess: () => {
          approve.mutate(
            { question: { ...q, question: rascunho.question.trim() }, edited: mudou },
            {
              onSuccess: () => { setEditando(null); toast.success('Pergunta aprovada.'); },
              onError: (e: any) => toast.error(e?.message || 'Erro ao aprovar'),
            },
          );
        },
        onError: (e: any) => toast.error(e?.message || 'Erro ao salvar'),
      },
    );
  }

  if (isLoading) {
    return (
      <p className="flex items-center gap-2 text-sm text-muted-foreground">
        <Loader2 className="h-4 w-4 animate-spin" /> Carregando perguntas…
      </p>
    );
  }

  if (questions.length === 0) return null;

  return (
    <section className="space-y-3">
      <div className="flex items-start gap-2">
        <ClipboardList className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
        <div className="min-w-0">
          <h2 className="text-sm font-semibold">Perguntas de levantamento</h2>
          <p className="text-xs text-muted-foreground">
            O que se pergunta antes de orçar, quando o serviço exige olhar antes de dar preço.
            A pergunta pertence ao sistema ou ao verbo — por isso vale para todos os serviços
            daquele eixo, e não só para um.
          </p>
        </div>
      </div>

      {totalPendente > 0 && (
        <Card className="flex items-start gap-2 border-primary/40 bg-primary/5 p-3 text-sm">
          <Sparkles className="mt-0.5 h-4 w-4 shrink-0 text-primary" />
          <span className="min-w-0">
            <strong>{totalPendente} pergunta(s) aguardando sua revisão.</strong>{' '}
            Enquanto nenhuma for aprovada, os botões de levantamento no orçamento continuam
            dizendo que não há perguntas cadastradas. O levantamento mostra no máximo 9 por vez,
            começando pelas que mais mexem no preço.
          </span>
        </Card>
      )}

      <div className="space-y-3">
        {grupos.map((g) => {
          const expandido = aberto[g.key] ?? false;
          return (
            <Card key={g.key} className="overflow-hidden">
              <button
                className="flex w-full items-center justify-between gap-3 p-3 text-left transition-colors hover:bg-muted/50"
                onClick={() => setAberto((s) => ({ ...s, [g.key]: !expandido }))}
              >
                <div className="flex min-w-0 items-center gap-2">
                  {expandido ? <ChevronDown className="h-4 w-4 shrink-0" /> : <ChevronRight className="h-4 w-4 shrink-0" />}
                  <span className="truncate text-sm font-medium">{g.eixoLabel}</span>
                  <Badge variant="secondary" className="shrink-0 text-[10px]">{g.tipo}</Badge>
                </div>
                <div className="flex shrink-0 flex-wrap items-center justify-end gap-2 text-xs tabular-nums text-muted-foreground">
                  <span>{g.questions.length} perguntas</span>
                  {g.remotas > 0 && <span>{g.remotas} p/ cliente</span>}
                  {g.pendentes > 0 && (
                    <Badge className="bg-primary text-[10px] text-primary-foreground">
                      {g.pendentes} a revisar
                    </Badge>
                  )}
                </div>
              </button>

              {expandido && (
                <div className="divide-y border-t">
                  {g.questions.map((q) => {
                    const pendente = surveyPendingApproval(q);
                    const emEdicao = editando === q.id;
                    return (
                      <div key={q.id} className={`p-3 ${pendente ? 'bg-primary/5' : ''}`}>
                        {emEdicao ? (
                          <div className="space-y-2">
                            <Input
                              value={rascunho.question}
                              onChange={(e) => setRascunho((r) => ({ ...r, question: e.target.value }))}
                              placeholder="A pergunta, como você faria ao cliente"
                              className="h-9"
                            />
                            <Textarea
                              value={rascunho.help_text}
                              onChange={(e) => setRascunho((r) => ({ ...r, help_text: e.target.value }))}
                              placeholder="Ajuda para quem pergunta — por que isso importa. Opcional."
                              rows={2}
                            />
                            <div className="flex flex-wrap items-center gap-2">
                              <Button size="sm" variant="ghost" onClick={() => setEditando(null)}>
                                Cancelar
                              </Button>
                              <Button
                                size="sm"
                                disabled={!rascunho.question.trim() || update.isPending || approve.isPending}
                                onClick={() => salvarEAprovar(q)}
                              >
                                Salvar e aprovar
                              </Button>
                            </div>
                          </div>
                        ) : (
                          <div className="flex items-start gap-3">
                            <span className="mt-0.5 w-5 shrink-0 text-[11px] tabular-nums text-muted-foreground">
                              {q.seq}
                            </span>
                            <div className="min-w-0 flex-1 space-y-1">
                              <div className="flex flex-wrap items-center gap-1.5">
                                <span className="text-sm font-medium">{q.question}</span>
                                {q.price_impact === 'alto' && (
                                  <Badge variant="outline" className="border-amber-500 text-[10px] text-amber-700 dark:text-amber-400">
                                    {IMPACT_LABEL[q.price_impact]}
                                  </Badge>
                                )}
                                <Badge variant="outline" className="text-[10px]">
                                  {ANSWER_LABEL[q.answer_type] ?? q.answer_type}
                                </Badge>
                                {q.ask_remotely && (
                                  <Badge variant="outline" className="gap-1 text-[10px]">
                                    <Send className="h-3 w-3" /> pode pedir ao cliente
                                  </Badge>
                                )}
                              </div>
                              {q.help_text && (
                                <p className="text-xs leading-snug text-muted-foreground">{q.help_text}</p>
                              )}
                              <div className="text-[11px] text-muted-foreground">
                                {pendente ? (
                                  <span className="text-primary">rascunho da IA — aguarda sua decisão</span>
                                ) : q.active ? (
                                  <span className="text-emerald-700 dark:text-emerald-400">em uso</span>
                                ) : (
                                  <span>inativa</span>
                                )}
                              </div>
                            </div>

                            {pendente && (
                              <div className="flex shrink-0 gap-1">
                                <Button
                                  size="sm" variant="ghost" className="h-7 px-2 text-destructive"
                                  title="Descartar esta pergunta"
                                  onClick={() => reject.mutate(q, {
                                    onError: (e: any) => toast.error(e?.message || 'Erro'),
                                  })}
                                >
                                  <X className="h-3.5 w-3.5" />
                                </Button>
                                <Button
                                  size="sm" variant="outline" className="h-7 px-2"
                                  title="Editar antes de aprovar"
                                  onClick={() => abrirEdicao(q)}
                                >
                                  <Pencil className="h-3.5 w-3.5" />
                                </Button>
                                <Button
                                  size="sm" className="h-7 px-2"
                                  title="Aprovar como está"
                                  onClick={() => approve.mutate({ question: q }, {
                                    onSuccess: () => toast.success('Pergunta aprovada.'),
                                    onError: (e: any) => toast.error(e?.message || 'Erro'),
                                  })}
                                >
                                  <Check className="h-3.5 w-3.5" />
                                </Button>
                              </div>
                            )}
                          </div>
                        )}
                      </div>
                    );
                  })}
                </div>
              )}
            </Card>
          );
        })}
      </div>
    </section>
  );
}
