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
import { useSalvarPayee, ROTULO_TIPO, type TipoFavorecido } from '@/hooks/use-payees';

/** A categoria que motivou o cadastro já diz o que a pessoa é para a empresa. */
function tipoPelaCategoria(categoria?: string): TipoFavorecido {
  if (categoria === 'Pró-labore e retirada') return 'socio';
  if (categoria === 'Salários e encargos') return 'funcionario';
  if (categoria === 'Serviços de terceiros') return 'prestador';
  return 'prestador';
}

export function PayeeFormDialog({
  aberto, onFechar, categoriaSugerida, onCriado,
}: {
  aberto: boolean;
  onFechar: () => void;
  categoriaSugerida?: string;
  onCriado?: (id: string) => void;
}) {
  const salvar = useSalvarPayee();

  const [nome, setNome] = useState('');
  const [tipo, setTipo] = useState<TipoFavorecido>(tipoPelaCategoria(categoriaSugerida));
  const [documento, setDocumento] = useState('');
  const [pix, setPix] = useState('');
  const [tipoPix, setTipoPix] = useState('cpf');
  const [banco, setBanco] = useState('');
  const [agencia, setAgencia] = useState('');
  const [conta, setConta] = useState('');
  const [telefone, setTelefone] = useState('');

  const confirmar = () => {
    if (!nome.trim()) return;
    salvar.mutate(
      {
        name: nome.trim(),
        kind: tipo,
        document: documento || null,
        pix_key: pix || null,
        pix_key_type: pix ? tipoPix : null,
        bank_name: banco || null,
        bank_branch: agencia || null,
        bank_account: conta || null,
        phone: telefone || null,
        default_category: categoriaSugerida ?? null,
        active: true,
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
          <DialogTitle>Cadastrar favorecido</DialogTitle>
          <DialogDescription>
            Quem recebe da empresa sem ser fornecedor: sócio, funcionário, diarista ou
            prestador. Os dados bancários ficam aqui para você não precisar procurá-los no
            banco a cada pagamento.
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
