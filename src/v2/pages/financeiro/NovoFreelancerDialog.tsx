// Cadastrar um freelancer de diária (pedido do dono, 03/10/2026 — antes só pelo assistente).
//
// Duas etapas, como o "sim" do WhatsApp: o formulário, depois a CONFERÊNCIA — a função do banco
// simula o cadastro (nada é gravado) e a tela mostra o que vai acontecer: cadastro novo ou o
// favorecido que já existe, a chave Pix como ela entendeu, a regra por CPF. Só então grava.
// Quem decide tudo isso é cadastrar_freelancer (a mesma do assistente); a tela não repete regra.
import { useState } from 'react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Textarea } from '@/components/ui/textarea';
import { MoneyInput } from '@/components/MoneyInput';
import { useI18n } from '@/i18n';
import { hojeLocal } from '@/lib/dia';
import { diaCurto } from '@/lib/diarias';
import {
  simularCadastro, useCadastrarFreelancer, type PedidoDeCadastro, type ResultadoDoCadastro,
} from '@/hooks/use-diarias';

const TIPOS_DE_CHAVE = [
  { valor: 'auto', rotulo: 'Pelo formato (e-mail, CNPJ, aleatória)' },
  { valor: 'cpf', rotulo: 'CPF' },
  { valor: 'telefone', rotulo: 'Telefone' },
  { valor: 'email', rotulo: 'E-mail' },
  { valor: 'cnpj', rotulo: 'CNPJ' },
  { valor: 'aleatoria', rotulo: 'Chave aleatória' },
] as const;

const ROTULO_DA_CHAVE: Record<string, string> = {
  cpf: 'CPF', cnpj: 'CNPJ', email: 'e-mail', telefone: 'telefone', aleatoria: 'chave aleatória',
};

/** O que a conferência mostra — o mesmo que o assistente mostra antes do "sim". */
export function linhasDaConferencia(r: ResultadoDoCadastro): string[] {
  const linhas: string[] = [];
  if (r.chave_pix) linhas.push(`Pix (${ROTULO_DA_CHAVE[r.tipo_chave ?? ''] ?? r.tipo_chave}): ${r.chave_pix}`);
  if (r.acao === 'diaria_no_cadastro_existente') {
    linhas.push(`Já existe o favorecido ${r.nome}, sem diária: ele ganha a diária — não nasce um cadastro novo.`);
  }
  linhas.push(r.regra === 'criada'
    ? 'Pix para o CPF dele vão entrar sozinhos em Diárias de freelancers.'
    : r.regra === 'ja_existia'
      ? `Já existe regra para o CPF dele (${r.regra_categoria ?? 'sem categoria'}); fica como está.`
      : 'Sem CPF: os Pix para ele vão pedir a sua confirmação na fila do extrato.');
  linhas.push('Meio período = metade da diária. Os dias se lançam em "Registrar dia".');
  return linhas;
}

export function NovoFreelancerDialog({ onFechar }: { onFechar: () => void }) {
  const { formatCurrency } = useI18n();
  const cadastrar = useCadastrarFreelancer();
  const hoje = hojeLocal();
  const [nome, setNome] = useState('');
  const [diaria, setDiaria] = useState(0);
  const [desde, setDesde] = useState(hoje);
  const [chavePix, setChavePix] = useState('');
  const [tipoChave, setTipoChave] = useState<string>('auto');
  const [cpf, setCpf] = useState('');
  const [telefone, setTelefone] = useState('');
  const [observacao, setObservacao] = useState('');
  const [conferindo, setConferindo] = useState(false);
  const [simulado, setSimulado] = useState<ResultadoDoCadastro | null>(null);
  const [recusa, setRecusa] = useState<string | null>(null);

  const erro = !nome.trim() ? 'Informe o nome.'
    : diaria <= 0 ? 'Informe o valor da diária.'
    : !desde ? 'Informe o primeiro dia de trabalho.'
    : desde > hoje ? 'O primeiro dia não pode estar no futuro.'
    : null;

  const pedido = (): PedidoDeCadastro => ({
    nome, valorDiaria: diaria, desde, chavePix, tipoChave: tipoChave === 'auto' ? '' : tipoChave,
    cpf, telefone, observacao,
  });

  // Qualquer mudança no formulário invalida a conferência: o "Cadastrar" vale para o que foi conferido.
  const mudou = <T,>(set: (v: T) => void) => (v: T) => { set(v); setSimulado(null); setRecusa(null); };

  async function conferir() {
    if (erro) return;
    setConferindo(true);
    setRecusa(null);
    try {
      setSimulado(await simularCadastro(pedido()));
    } catch (e) {
      setRecusa((e as Error).message || 'O cadastro seria recusado.');
    } finally {
      setConferindo(false);
    }
  }

  async function gravar() {
    try {
      const r = await cadastrar.mutateAsync(pedido());
      toast.success(r.message ?? `${r.nome} cadastrado.`);
      onFechar();
    } catch (e) {
      setSimulado(null);
      setRecusa((e as Error).message || 'Não foi possível cadastrar.');
    }
  }

  return (
    <Dialog open onOpenChange={(aberto) => !aberto && onFechar()}>
      <DialogContent className="max-h-[90dvh] overflow-y-auto sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>{simulado ? 'Conferir o cadastro' : 'Novo freelancer'}</DialogTitle>
          <DialogDescription>
            {simulado
              ? 'Nada foi gravado ainda. Confira e cadastre — ou volte para corrigir.'
              : 'Quem trabalha por dia. Já trabalhou antes de hoje? Ponha o primeiro dia, senão os dias anteriores não entram.'}
          </DialogDescription>
        </DialogHeader>

        {simulado ? (
          <div className="space-y-3 text-sm">
            <p className="font-medium">
              {simulado.nome} · diária de <span className="tabular-nums">{formatCurrency(simulado.valor_diaria)}</span> · desde {diaCurto(simulado.desde)}
            </p>
            <ul className="list-disc space-y-1 pl-5 text-muted-foreground">
              {linhasDaConferencia(simulado).map((l) => <li key={l}>{l}</li>)}
            </ul>
          </div>
        ) : (
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-1.5 sm:col-span-2">
              <Label htmlFor="novo-nome">Nome</Label>
              <Input id="novo-nome" value={nome} onChange={(e) => mudou(setNome)(e.target.value)} placeholder="Nome completo, se souber" />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="novo-diaria">Diária (R$)</Label>
              <MoneyInput id="novo-diaria" value={diaria} onValueChange={mudou(setDiaria)} />
              <p className="text-xs text-muted-foreground">O dia inteiro; meio período é metade.</p>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="novo-desde">Primeiro dia de trabalho</Label>
              <Input id="novo-desde" type="date" value={desde} max={hoje} onChange={(e) => mudou(setDesde)(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="novo-chave">Chave Pix (opcional)</Label>
              <Input id="novo-chave" value={chavePix} onChange={(e) => mudou(setChavePix)(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="novo-tipo">Tipo da chave</Label>
              <Select value={tipoChave} onValueChange={mudou(setTipoChave)}>
                <SelectTrigger id="novo-tipo"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {TIPOS_DE_CHAVE.map((t) => <SelectItem key={t.valor} value={t.valor}>{t.rotulo}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="novo-cpf">CPF (opcional)</Label>
              <Input id="novo-cpf" inputMode="numeric" value={cpf} onChange={(e) => mudou(setCpf)(e.target.value)} />
              <p className="text-xs text-muted-foreground">Com CPF, os Pix dele entram sozinhos como diária.</p>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="novo-telefone">Telefone (opcional)</Label>
              <Input id="novo-telefone" inputMode="tel" value={telefone} onChange={(e) => mudou(setTelefone)(e.target.value)} />
            </div>
            <div className="space-y-1.5 sm:col-span-2">
              <Label htmlFor="novo-obs">Observação</Label>
              <Textarea id="novo-obs" rows={2} value={observacao} onChange={(e) => mudou(setObservacao)(e.target.value)}
                        placeholder="Ex.: entrou no lugar do Mickael" />
            </div>
          </div>
        )}

        {recusa && <p role="alert" className="text-sm text-destructive">{recusa}</p>}

        <DialogFooter className="flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-sm text-destructive">{!simulado && erro && nome ? erro : ''}</p>
          <div className="flex gap-2">
            {simulado ? (
              <>
                <Button type="button" variant="outline" onClick={() => setSimulado(null)}>Voltar</Button>
                <Button type="button" onClick={gravar} disabled={cadastrar.isPending}>
                  {cadastrar.isPending ? 'Cadastrando…' : 'Cadastrar'}
                </Button>
              </>
            ) : (
              <>
                <Button type="button" variant="outline" onClick={onFechar}>Cancelar</Button>
                <Button type="button" onClick={conferir} disabled={!!erro || conferindo}>
                  {conferindo ? 'Conferindo…' : 'Conferir'}
                </Button>
              </>
            )}
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
