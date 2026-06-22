import { useState } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Bot, Send, Loader2, ShieldCheck, FlaskConical } from 'lucide-react';
import { useAIOperatorGateway, type OperatorResult } from '@/hooks/use-ai-operator-gateway';

const PLAN_LABEL: Record<string, string> = {
  read: 'Leitura (busca)',
  create: 'Criação (back-office)',
  outbound: 'Saída ao cliente',
  llm: 'Escalado ao modelo',
  none: 'Sem ação',
};

const DECISION_STYLE: Record<string, string> = {
  auto_send: 'bg-green-500/10 text-green-700 border-green-200',
  needs_approval: 'bg-amber-500/10 text-amber-700 border-amber-200',
  blocked: 'bg-red-500/10 text-red-700 border-red-200',
};

const EXAMPLES = [
  'Criar orçamento para o cliente João',
  'Buscar cliente Ana Paula',
  'Abrir uma nova OS para o cliente Pedro',
  'Enviar o orçamento para o cliente no whatsapp',
  'O motor faz um barulho estranho, o que pode ser?',
];

function ResultView({ r }: { r: OperatorResult }) {
  return (
    <Card className="border-primary/20">
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <Bot className="h-4 w-4 text-primary" /> Resposta do Operador
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4 text-sm">
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant="secondary">intenção: {r.intent.kind}</Badge>
          <Badge variant="outline">plano: {PLAN_LABEL[r.plan] ?? r.plan}</Badge>
          {typeof r.intent.confidence === 'number' && (
            <Badge variant="outline">confiança: {(r.intent.confidence * 100).toFixed(0)}%</Badge>
          )}
          <Badge className="bg-blue-500/10 text-blue-700 border-blue-200">
            executou escrita: não
          </Badge>
        </div>

        <p className="text-muted-foreground">{r.message}</p>

        {Object.keys(r.params || {}).length > 0 && (
          <div className="text-xs">
            <span className="font-medium">Parâmetros extraídos:</span>{' '}
            {Object.entries(r.params).map(([k, v]) => (
              <code key={k} className="mx-1 rounded bg-muted px-1.5 py-0.5">{k}={v}</code>
            ))}
          </div>
        )}

        {r.llmText && (
          <div className="rounded-lg border bg-muted/40 p-3">
            <div className="mb-1 text-xs font-medium text-muted-foreground">Resposta do modelo (LLM):</div>
            {r.llmText}
          </div>
        )}

        {r.policyDecision && (
          <div className="rounded-lg border p-3 space-y-2">
            <div className="flex items-center gap-2">
              <span className="text-xs font-medium">Motor de Regras de Saída:</span>
              <Badge className={DECISION_STYLE[r.policyDecision.decision]}>
                {r.policyDecision.decision}
              </Badge>
              {r.policyDecision.shadow && (
                <Badge variant="outline" className="gap-1">
                  <FlaskConical className="h-3 w-3" /> shadow — não executa
                </Badge>
              )}
            </div>
            <ul className="space-y-1 text-xs text-muted-foreground">
              {r.policyDecision.reasons.map((reason, i) => (
                <li key={i}>• [{reason.level}] {reason.message}</li>
              ))}
            </ul>
            {r.policyDecision.approvalRoute && (
              <div className="text-xs">
                Aprovação roteada para:{' '}
                <strong>
                  {r.policyDecision.approvalRoute.kind === 'manager_whatsapp'
                    ? `WhatsApp do gestor (${r.policyDecision.approvalRoute.to})`
                    : 'card no app (gestor não configurado)'}
                </strong>
              </div>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

export default function AIOperatorPage() {
  const [text, setText] = useState('');
  const { send, loading, result, error } = useAIOperatorGateway();

  const handleSend = async () => {
    if (!text.trim()) return;
    await send(text.trim());
  };

  return (
    <div className="flex flex-col gap-6 max-w-3xl">
      <PageHeader
        title="Modo Operador (beta)"
        description="Converse com o AI Operator. Ele interpreta o pedido e mostra o plano/decisão — sem executar nada ainda."
      />

      <Alert className="border-amber-300 bg-amber-50 dark:bg-amber-950/20">
        <ShieldCheck className="h-4 w-4 text-amber-600" />
        <AlertTitle className="text-amber-700 font-semibold">Modo Sombra ativo</AlertTitle>
        <AlertDescription className="text-amber-700 text-sm">
          Nesta fase o operador <strong>não cria nem envia nada</strong> — apenas mostra o que
          faria e como o motor de regras decidiria. Seguro para testar à vontade.
        </AlertDescription>
      </Alert>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base">O que você precisa?</CardTitle>
          <CardDescription>Descreva em português. Ex: "criar orçamento para o cliente João".</CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <Textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder="Digite seu pedido..."
            className="min-h-[90px]"
            onKeyDown={(e) => {
              if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) handleSend();
            }}
          />
          <div className="flex flex-wrap gap-1.5">
            {EXAMPLES.map((ex) => (
              <button
                key={ex}
                onClick={() => setText(ex)}
                className="rounded-full border px-2.5 py-1 text-xs text-muted-foreground hover:bg-muted transition-colors"
              >
                {ex}
              </button>
            ))}
          </div>
          <div className="flex justify-end">
            <Button onClick={handleSend} disabled={loading || !text.trim()} className="gap-2">
              {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
              Enviar
            </Button>
          </div>
        </CardContent>
      </Card>

      {error && (
        <Alert variant="destructive">
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}

      {result && <ResultView r={result} />}
    </div>
  );
}
