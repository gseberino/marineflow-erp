// Botão + diálogo "Deixar a IA acompanhar" (Fase 0/1 do dossiê plans/marineflow-ia-acompanha.md).
//
// O botão é autocontido (guarda o próprio estado) para caber em qualquer tela sem plumbing:
// tarefa da agenda, orçamento, futuramente fio solto. Quando a origem já tem missão em
// andamento, ele vira um atalho para o painel em vez de abrir outra.
import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { Bot, Loader2 } from 'lucide-react';
import { toast } from 'sonner';
import { Button, type ButtonProps } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useSuppliers } from '@/hooks/use-suppliers';
import {
  useCreateFollowupMission,
  useFollowupMissionDaOrigem,
  type FollowupContraparteTipo,
  type FollowupOrigemTipo,
} from '@/hooks/use-followup-missions';

export interface OrigemDaMissao {
  tipo: FollowupOrigemTipo;
  id?: string | null;
  /** Como a origem aparece para o dono (ex.: "ORÇ-00083", título da tarefa). */
  rotulo: string;
}

export interface ContraparteSugerida {
  tipo: FollowupContraparteTipo;
  id?: string | null;
  label?: string | null;
  phone?: string | null;
}

interface DialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  origem: OrigemDaMissao;
  contraparte?: ContraparteSugerida | null;
  sugestaoObjetivo?: string;
  /** ISO ou yyyy-mm-dd. */
  sugestaoPrazo?: string | null;
}

type ModoContraparte = 'sugerida' | 'supplier' | 'phone';

function paraDateInput(v: string | null | undefined): string {
  if (!v) return '';
  const d = new Date(v);
  if (isNaN(d.getTime())) return String(v).slice(0, 10);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

export function FollowupMissionDialog({ open, onOpenChange, origem, contraparte, sugestaoObjetivo, sugestaoPrazo }: DialogProps) {
  const [objetivo, setObjetivo] = useState(sugestaoObjetivo ?? '');
  const [prazo, setPrazo] = useState(paraDateInput(sugestaoPrazo));
  const [modo, setModo] = useState<ModoContraparte>(contraparte?.id || contraparte?.phone ? 'sugerida' : 'supplier');
  const [supplierId, setSupplierId] = useState('');
  const [phone, setPhone] = useState('');
  const [label, setLabel] = useState('');
  const criar = useCreateFollowupMission();
  const { data: suppliers = [] } = useSuppliers();

  useEffect(() => {
    if (!open) return;
    setObjetivo(sugestaoObjetivo ?? '');
    setPrazo(paraDateInput(sugestaoPrazo));
    setModo(contraparte?.id || contraparte?.phone ? 'sugerida' : 'supplier');
  }, [open, sugestaoObjetivo, sugestaoPrazo, contraparte?.id, contraparte?.phone]);

  const fornecedoresComTelefone = useMemo(
    () => (suppliers as any[]).filter((s) => s.active !== false && String(s.phone || '').replace(/\D/g, '').length >= 10),
    [suppliers],
  );

  const tipoFinal: FollowupContraparteTipo = modo === 'sugerida' ? (contraparte?.tipo ?? 'client') : modo === 'supplier' ? 'supplier' : 'lead';
  const maxToques = tipoFinal === 'supplier' ? 3 : 2;

  async function confirmar() {
    if (!objetivo.trim()) { toast.error('Diga o que a IA deve acompanhar.'); return; }
    if (modo === 'supplier' && !supplierId) { toast.error('Escolha o fornecedor.'); return; }
    if (modo === 'phone' && phone.replace(/\D/g, '').length < 10) { toast.error('Informe um telefone com DDD.'); return; }
    try {
      await criar.mutateAsync({
        origem_tipo: origem.tipo,
        origem_id: origem.id ?? null,
        objetivo: objetivo.trim(),
        prazo_final: prazo ? new Date(`${prazo}T12:00:00`).toISOString() : null,
        contraparte_tipo: tipoFinal,
        contraparte_id: modo === 'sugerida' ? contraparte?.id ?? null : modo === 'supplier' ? supplierId : null,
        phone: modo === 'phone' ? phone : modo === 'sugerida' ? contraparte?.phone ?? null : null,
        label: modo === 'phone' ? label || null : modo === 'sugerida' ? contraparte?.label ?? null : null,
      });
      toast.success('A IA vai redigir o primeiro toque na próxima janela (seg–sex, 9h–18h) e pedir sua aprovação no sino.');
      onOpenChange(false);
    } catch (e: any) {
      toast.error(e?.message || 'Não deu para criar a missão.');
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2"><Bot className="h-5 w-5" /> Deixar a IA acompanhar</DialogTitle>
          <DialogDescription>
            A IA passa a cobrar a outra pessoa sobre este assunto até resolver. Cada mensagem é redigida por ela e
            <strong> passa pela sua aprovação</strong> antes de sair — nada é enviado sozinho.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="rounded-md border bg-muted/40 px-3 py-2 text-sm">
            <span className="text-muted-foreground">Origem:</span> <span className="font-medium">{origem.rotulo}</span>
          </div>

          <div className="space-y-2">
            <Label htmlFor="followup-objetivo">O que acompanhar</Label>
            <Textarea id="followup-objetivo" rows={2} value={objetivo} onChange={(e) => setObjetivo(e.target.value)}
              placeholder="Ex.: confirmar a entrega das baterias e dos outros equipamentos" />
          </div>

          <div className="space-y-2">
            <Label>Com quem</Label>
            <Select value={modo} onValueChange={(v) => setModo(v as ModoContraparte)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {(contraparte?.id || contraparte?.phone) && (
                  <SelectItem value="sugerida">
                    {contraparte?.tipo === 'supplier' ? 'Fornecedor' : 'Cliente'}: {contraparte?.label || contraparte?.phone}
                  </SelectItem>
                )}
                <SelectItem value="supplier">Um fornecedor do cadastro</SelectItem>
                <SelectItem value="phone">Outro telefone</SelectItem>
              </SelectContent>
            </Select>
            {modo === 'supplier' && (
              <Select value={supplierId} onValueChange={setSupplierId}>
                <SelectTrigger><SelectValue placeholder="Escolha o fornecedor (só os com telefone)" /></SelectTrigger>
                <SelectContent>
                  {fornecedoresComTelefone.map((s: any) => (
                    <SelectItem key={s.id} value={s.id}>{s.display_name || s.trade_name || s.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            )}
            {modo === 'phone' && (
              <div className="grid gap-2 sm:grid-cols-2">
                <Input placeholder="Telefone com DDD" value={phone} onChange={(e) => setPhone(e.target.value)} inputMode="tel" />
                <Input placeholder="Como chamar a pessoa" value={label} onChange={(e) => setLabel(e.target.value)} />
              </div>
            )}
          </div>

          <div className="space-y-2">
            <Label htmlFor="followup-prazo">Prazo que importa para você (opcional)</Label>
            <Input id="followup-prazo" type="date" value={prazo} onChange={(e) => setPrazo(e.target.value)} className="sm:w-48" />
            <p className="text-[11px] text-muted-foreground">
              Com prazo, a IA toca em D-7, D-3 e D-1. Sem prazo, começa já e espaça 2, 4 e 7 dias.
            </p>
          </div>

          <ul className="space-y-1 rounded-md border px-3 py-2 text-[12px] text-muted-foreground">
            <li>• Até <strong>{maxToques} toques</strong> ({tipoFinal === 'supplier' ? 'fornecedor' : 'cliente'}); depois a missão volta para você.</li>
            <li>• Só em dia útil, das 9h às 18h; nunca duas mensagens no mesmo dia.</li>
            <li>• No primeiro toque a IA se apresenta como assistente da empresa.</li>
            <li>• Se a pessoa responder, a IA para e você lê a resposta.</li>
            <li>• Se o ERP mostrar que resolveu (tarefa concluída, orçamento decidido), fecha sozinha.</li>
          </ul>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancelar</Button>
          <Button onClick={confirmar} disabled={criar.isPending}>
            {criar.isPending && <Loader2 className="mr-1 h-4 w-4 animate-spin" />}
            Deixar a IA acompanhar
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

interface BotaoProps extends Pick<ButtonProps, 'size' | 'variant' | 'className'> {
  origem: OrigemDaMissao;
  contraparte?: ContraparteSugerida | null;
  sugestaoObjetivo?: string;
  sugestaoPrazo?: string | null;
  /** Em barras apertadas (celular): só o ícone abaixo de `sm`. */
  compacto?: boolean;
}

/** Botão autocontido: abre o diálogo ou, se já há missão nesta origem, leva ao painel. */
export function FollowupMissionButton({ origem, contraparte, sugestaoObjetivo, sugestaoPrazo, size = 'sm', variant = 'outline', className, compacto }: BotaoProps) {
  const [aberto, setAberto] = useState(false);
  const { data: emAndamento } = useFollowupMissionDaOrigem(origem.tipo, origem.id);
  const rotuloCls = compacto ? 'hidden sm:inline' : undefined;

  if (emAndamento) {
    return (
      <Button asChild size={size} variant={variant} className={className}>
        <Link to="/v2/agenda/acompanhamentos" title={`Toques: ${emAndamento.toques_feitos}/${emAndamento.max_toques}`} aria-label="IA acompanhando">
          <Bot className="h-4 w-4 sm:mr-1" /> <span className={rotuloCls}>IA acompanhando</span>
        </Link>
      </Button>
    );
  }
  return (
    <>
      <Button size={size} variant={variant} className={className} onClick={() => setAberto(true)} aria-label="Deixar a IA acompanhar">
        <Bot className="h-4 w-4 sm:mr-1" /> <span className={rotuloCls}>Deixar a IA acompanhar</span>
      </Button>
      <FollowupMissionDialog
        open={aberto}
        onOpenChange={setAberto}
        origem={origem}
        contraparte={contraparte}
        sugestaoObjetivo={sugestaoObjetivo}
        sugestaoPrazo={sugestaoPrazo}
      />
    </>
  );
}
