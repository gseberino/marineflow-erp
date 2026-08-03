// Cadastro de favorecido — quem recebe dinheiro sem ser fornecedor nem usuário do sistema.
//
// Abre de dentro da caixa de entrada, no momento em que a falta aparece: descobrir que o
// diarista não está cadastrado no meio da conferência não pode custar sair da tela, achar
// o cadastro, criar, voltar e reencontrar a linha.
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useSalvarPayee, ROTULO_TIPO, type Favorecido, type TipoFavorecido } from '@/hooks/use-payees';

/** A categoria que motivou o cadastro já diz o que a pessoa é para a empresa. */
function tipoPelaCategoria(categoria?: string): TipoFavorecido {
  if (categoria === 'Pró-labore e retirada') return 'socio';
  if (categoria === 'Salários e encargos') return 'funcionario';
  if (categoria === 'Serviços de terceiros') return 'prestador';
  return 'prestador';
}

export function PayeeFormDialog({
  aberto, onFechar, categoriaSugerida, onCriado, favorecido,
}: {
  aberto: boolean;
  onFechar: () => void;
  categoriaSugerida?: string;
  onCriado?: (id: string) => void;
  /** Quando presente, o diálogo edita em vez de criar. */
  favorecido?: Favorecido;
}) {
  const salvar = useSalvarPayee();
  const editando = !!favorecido;

  const [nome, setNome] = useState(favorecido?.name ?? '');
  const [tipo, setTipo] = useState<TipoFavorecido>(favorecido?.kind ?? tipoPelaCategoria(categoriaSugerida));
  const [documento, setDocumento] = useState(favorecido?.document ?? '');
  const [pix, setPix] = useState(favorecido?.pix_key ?? '');
  const [tipoPix, setTipoPix] = useState(favorecido?.pix_key_type ?? 'cpf');
  const [banco, setBanco] = useState(favorecido?.bank_name ?? '');
  const [agencia, setAgencia] = useState(favorecido?.bank_branch ?? '');
  const [conta, setConta] = useState(favorecido?.bank_account ?? '');
  const [telefone, setTelefone] = useState(favorecido?.phone ?? '');
  const [percentual, setPercentual] = useState(
    favorecido?.commission_percentage != null ? String(favorecido.commission_percentage) : '',
  );

  const confirmar = () => {
    if (!nome.trim()) return;
    salvar.mutate(
      {
        id: favorecido?.id,
        name: nome.trim(),
        kind: tipo,
        document: documento || null,
        pix_key: pix || null,
        pix_key_type: pix ? tipoPix : null,
        bank_name: banco || null,
        bank_branch: agencia || null,
        bank_account: conta || null,
        phone: telefone || null,
        commission_percentage: tipo === 'comissionado' && percentual ? Number(percentual) : null,
        default_category: favorecido?.default_category ?? categoriaSugerida ?? null,
        active: favorecido?.active ?? true,
      },
      {
        onSuccess: (id) => {
          onCriado?.(id);
          onFechar();
        },
      },
    );
  };

  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>{editando ? `Editar ${favorecido!.name}` : 'Cadastrar favorecido'}</DialogTitle>
          <DialogDescription>
            Quem recebe da empresa sem ser fornecedor: sócio, funcionário, diarista,
            prestador ou comissionado. Os dados bancários ficam aqui para você não precisar
            procurá-los no banco a cada pagamento.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <div>
              <Label className="text-xs">Nome *</Label>
              <Input value={nome} onChange={(e) => setNome(e.target.value)} placeholder="Nome completo" />
            </div>
            <div>
              <Label className="text-xs">O que é para a empresa</Label>
              <Select value={tipo} onValueChange={(v) => setTipo(v as TipoFavorecido)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {(Object.keys(ROTULO_TIPO) as TipoFavorecido[]).map((k) => (
                    <SelectItem key={k} value={k}>{ROTULO_TIPO[k]}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <div>
              <Label className="text-xs">CPF ou CNPJ</Label>
              {/* É por ele que o extrato reconhece a pessoa nas próximas vezes. */}
              <Input value={documento} onChange={(e) => setDocumento(e.target.value)} placeholder="Só números" />
            </div>
            <div>
              <Label className="text-xs">Telefone</Label>
              <Input value={telefone} onChange={(e) => setTelefone(e.target.value)} />
            </div>
          </div>

          {/* Só aparece para comissionado: percentual em cadastro de sócio é campo que
              confunde mais do que serve. */}
          {tipo === 'comissionado' && (
            <div className="max-w-[12rem]">
              <Label className="text-xs">Comissão habitual (%)</Label>
              <Input
                type="number" inputMode="decimal" min="0" max="100" step="0.5"
                value={percentual}
                onChange={(e) => setPercentual(e.target.value)}
                placeholder="ex.: 5"
              />
              <p className="mt-1 text-xs text-muted-foreground">
                Vale como padrão nas vendas; sempre editável em cada uma.
              </p>
            </div>
          )}

          <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
            <div className="sm:col-span-2">
              <Label className="text-xs">Chave Pix</Label>
              <Input value={pix} onChange={(e) => setPix(e.target.value)} />
            </div>
            <div>
              <Label className="text-xs">Tipo da chave</Label>
              <Select value={tipoPix} onValueChange={setTipoPix}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {['cpf', 'cnpj', 'email', 'telefone', 'aleatoria'].map((t) => (
                    <SelectItem key={t} value={t}>{t}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
            <div>
              <Label className="text-xs">Banco</Label>
              <Input value={banco} onChange={(e) => setBanco(e.target.value)} />
            </div>
            <div>
              <Label className="text-xs">Agência</Label>
              <Input value={agencia} onChange={(e) => setAgencia(e.target.value)} />
            </div>
            <div>
              <Label className="text-xs">Conta</Label>
              <Input value={conta} onChange={(e) => setConta(e.target.value)} />
            </div>
          </div>
        </div>

        <DialogFooter>
          <Button variant="ghost" onClick={onFechar}>Cancelar</Button>
          <Button disabled={!nome.trim() || salvar.isPending} onClick={confirmar}>Salvar</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
