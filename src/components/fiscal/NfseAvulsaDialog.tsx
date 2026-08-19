// [NFSE-PAGE] NFS-e AVULSA — serviço que não virou OS (cobrança pontual).
//
// Fluxo em dois passos DENTRO do diálogo: preencher → conferir → emitir. A conferência
// mostra exatamente o que vai na nota (cliente, descrição, valor, código, ISS) e grita o
// ambiente quando é produção — nota de serviço real não tem "desfazer" barato (o
// cancelamento tem prazo municipal).
//
// Os campos fiscais nascem do VERBO FISCAL escolhido (herança confirmada pela contadora
// em 18/08/2026: tudo 14.01/3%), editáveis para a exceção.
import { useEffect, useMemo, useState } from 'react';
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { MoneyInput } from '@/components/MoneyInput';
import { EntityCombobox, type EntityOption } from '@/components/EntityCombobox';
import { useClients } from '@/hooks/use-clients';
import { useServiceFiscalVerbs } from '@/hooks/use-service-fiscal';
import { useAmbienteFiscal, useEmitirNfseAvulsa } from '@/hooks/use-nfse';
import { useI18n } from '@/i18n';
import { FileText, Loader2, ArrowLeft } from 'lucide-react';
import { toast } from 'sonner';

export function NfseAvulsaDialog({ open, onOpenChange }: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const { formatCurrency } = useI18n();
  const { data: clients = [] } = useClients();
  const { data: verbos = [] } = useServiceFiscalVerbs();
  const ambiente = useAmbienteFiscal();
  const emitir = useEmitirNfseAvulsa();

  const [etapa, setEtapa] = useState<'form' | 'conferencia'>('form');
  const [clientId, setClientId] = useState('');
  const [descricao, setDescricao] = useState('');
  const [valor, setValor] = useState(0);
  const [verbo, setVerbo] = useState('');
  const [codigo, setCodigo] = useState('');
  const [cnae, setCnae] = useState('');
  const [issRate, setIssRate] = useState('');
  const [issRetido, setIssRetido] = useState(false);

  useEffect(() => {
    if (open) {
      setEtapa('form');
      setClientId('');
      setDescricao('');
      setValor(0);
      setVerbo('');
      setCodigo('');
      setCnae('');
      setIssRate('');
      setIssRetido(false);
    }
  }, [open]);

  // Escolher o verbo pré-preenche os campos fiscais com a herança dele (editáveis).
  const aplicarVerbo = (slug: string) => {
    setVerbo(slug);
    const v = verbos.find((x) => x.verb_slug === slug);
    if (v) {
      setCodigo(v.default_national_tax_code ?? '');
      setCnae(v.default_cnae ?? '');
      setIssRate(v.default_iss_rate != null ? String(v.default_iss_rate) : '');
      setIssRetido(v.default_iss_withheld === true);
    }
  };

  const clienteOptions: EntityOption[] = useMemo(
    () => clients.map((c) => ({
      value: c.id,
      label: c.name,
      description: c.cpf_cnpj ?? undefined,
      searchTerms: [c.cpf_cnpj ?? ''],
    })),
    [clients],
  );
  const cliente = clients.find((c) => c.id === clientId);

  const codigoDigits = codigo.replace(/\D/g, '');
  const cnaeDigits = cnae.replace(/\D/g, '');
  const podeConferir = !!clientId && descricao.trim().length > 0 && valor > 0
    && codigoDigits.length === 6 && (!cnae || cnaeDigits.length === 7);

  const validarEConferir = () => {
    if (!cliente?.cpf_cnpj) {
      toast.error('O cliente precisa de CPF/CNPJ no cadastro — sem tomador identificado não há NFS-e.');
      return;
    }
    if (!cliente.city || !cliente.state || !cliente.postal_code) {
      toast.error('O cliente precisa de endereço completo (cidade, UF e CEP) no cadastro.');
      return;
    }
    setEtapa('conferencia');
  };

  const handleEmitir = async () => {
    try {
      await emitir.mutateAsync({
        clientId,
        descricao: descricao.trim(),
        valor,
        nationalTaxCode: codigoDigits,
        cnae: cnaeDigits || null,
        issRate: issRate === '' ? null : Number(issRate),
        issWithheld: issRetido,
      });
      onOpenChange(false);
    } catch {
      // toast do hook; o diálogo fica aberto para corrigir
    }
  };

  const producao = ambiente.data === 'producao';

  return (
    <Dialog open={open} onOpenChange={(v) => { if (!emitir.isPending) onOpenChange(v); }}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto overflow-x-hidden">
        <DialogHeader>
          <DialogTitle>NFS-e avulsa</DialogTitle>
          <DialogDescription>
            Serviço que não virou OS. Só a mão de obra — peça/produto é NF-e.
          </DialogDescription>
        </DialogHeader>

        {producao && (
          <div className="rounded-md border border-destructive/50 bg-destructive/5 p-2 text-sm font-medium text-destructive">
            ⚠ Ambiente de PRODUÇÃO — esta será uma nota real.
          </div>
        )}

        {etapa === 'form' ? (
          <div className="space-y-3">
            <div>
              <Label>Cliente (tomador) *</Label>
              <EntityCombobox
                value={clientId}
                onChange={setClientId}
                options={clienteOptions}
                placeholder="Selecionar cliente…"
                className="mt-1"
              />
            </div>
            <div>
              <Label>Descrição do serviço *</Label>
              <Textarea
                value={descricao}
                onChange={(e) => setDescricao(e.target.value)}
                rows={3}
                className="mt-1"
                placeholder="O que foi feito — a prefeitura e o cliente leem isto."
              />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <Label>Valor do serviço *</Label>
                <MoneyInput value={valor} onValueChange={setValor} className="mt-1" />
              </div>
              <div>
                <Label>Atividade (verbo fiscal)</Label>
                <Select value={verbo} onValueChange={aplicarVerbo}>
                  <SelectTrigger className="mt-1"><SelectValue placeholder="Escolher…" /></SelectTrigger>
                  <SelectContent>
                    {verbos.map((v) => (
                      <SelectItem key={v.verb_slug} value={v.verb_slug}>
                        {v.name}{v.default_national_tax_code ? ` · ${v.default_national_tax_code}` : ''}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </div>
            <div className="grid grid-cols-3 gap-3">
              <div>
                <Label className="text-xs">Código nacional *</Label>
                <Input value={codigo} onChange={(e) => setCodigo(e.target.value)} placeholder="140101" className="mt-1" inputMode="numeric" />
              </div>
              <div>
                <Label className="text-xs">CNAE</Label>
                <Input value={cnae} onChange={(e) => setCnae(e.target.value)} placeholder="3317102" className="mt-1" inputMode="numeric" />
              </div>
              <div>
                <Label className="text-xs">ISS (%)</Label>
                <Input type="number" min="0" max="100" step="0.01" value={issRate} onChange={(e) => setIssRate(e.target.value)} placeholder="3" className="mt-1" />
              </div>
            </div>
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={issRetido} onChange={(e) => setIssRetido(e.target.checked)} />
              ISS retido pelo tomador (confirmado pela contadora: normalmente NÃO)
            </label>
            <div className="flex justify-end gap-2 pt-1">
              <Button variant="outline" onClick={() => onOpenChange(false)}>Cancelar</Button>
              <Button onClick={validarEConferir} disabled={!podeConferir}>
                Conferir antes de emitir
              </Button>
            </div>
          </div>
        ) : (
          <div className="space-y-3">
            <div className="rounded-md border p-3 text-sm space-y-1.5">
              <p><span className="text-muted-foreground">Tomador:</span> <strong>{cliente?.name}</strong> · {cliente?.cpf_cnpj}</p>
              <p><span className="text-muted-foreground">Serviço:</span> {descricao.trim()}</p>
              <p><span className="text-muted-foreground">Valor:</span> <strong>{formatCurrency(valor)}</strong></p>
              <p>
                <span className="text-muted-foreground">Tributação:</span> código {codigoDigits}
                {cnaeDigits ? ` · CNAE ${cnaeDigits}` : ''}{issRate !== '' ? ` · ISS ${issRate}%` : ''}
                {issRetido ? ' · RETIDO pelo tomador' : ''}
              </p>
              <p className="text-xs text-muted-foreground">
                Ambiente: {producao ? 'PRODUÇÃO (nota real)' : 'homologação (sem valor fiscal)'} ·
                o % do Simples (pTotTribSN) sai do cadastro da empresa.
              </p>
            </div>
            <div className="flex justify-between gap-2">
              <Button variant="outline" onClick={() => setEtapa('form')} disabled={emitir.isPending}>
                <ArrowLeft className="mr-1.5 h-4 w-4" />Voltar e corrigir
              </Button>
              <Button onClick={handleEmitir} disabled={emitir.isPending}>
                {emitir.isPending ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <FileText className="mr-2 h-4 w-4" />}
                {producao ? 'Emitir NFS-e REAL' : 'Emitir em homologação'}
              </Button>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
