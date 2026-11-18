// Enviar o conjunto ("Agrupar para o cliente") pelo WhatsApp: UM PDF com a capa e os documentos completos.
// Mesmo caminho do envio de hoje (useWhatsAppSend → whatsapp-send): sem link, saudação opcional, e cada orçamento do
// conjunto marcado como enviado pelas mesmas regras (só quando vai ao número do cliente).
import { useEffect, useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Download, Loader2, Send } from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { supabase } from '@/integrations/supabase/client';
import { useAppSettings } from '@/hooks/use-app-settings';
import { fetchPDFData } from '@/hooks/use-pdf';
import { useWhatsAppSend } from '@/hooks/use-whatsapp-send';
import { normalizePhoneE164 } from '@/lib/masks';
import { type Conjunto, alvosDoEnvio, mensagemPadraoDoConjunto } from '@/lib/conjunto';
import { gerarPdfDoConjunto } from '@/lib/pdf-conjunto';
import {
  CHAVE_DA_SAUDACAO,
  SAUDACAO_PADRAO,
  type Saudacao,
  ehSaudacao,
  opcoesDeSaudacao,
  textoDaSaudacao,
  trocarSaudacao,
} from '@/lib/whatsapp-mensagem-ao-cliente';

interface Props {
  aberto: boolean;
  onFechar: () => void;
  conjunto: Conjunto;
}

function saudacaoSalva(): Saudacao {
  try {
    const s = localStorage.getItem(CHAVE_DA_SAUDACAO);
    return ehSaudacao(s) ? s : SAUDACAO_PADRAO;
  } catch {
    return SAUDACAO_PADRAO;
  }
}

/** Baixa um Blob com o nome dado (sem abrir aba). */
export function baixarArquivo(blob: Blob, nome: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = nome;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}

export function EnviarConjuntoDialog({ aberto, onFechar, conjunto }: Props) {
  const { data: appSettings } = useAppSettings();
  const { send, sending } = useWhatsAppSend();
  const cliente = useQuery({
    queryKey: ['conjunto-cliente', conjunto.client_id],
    enabled: aberto && !!conjunto.client_id,
    queryFn: async () => {
      const { data, error } = await supabase.from('clients').select('name, whatsapp, phone').eq('id', conjunto.client_id).maybeSingle();
      if (error) throw error;
      return data as { name: string | null; whatsapp: string | null; phone: string | null } | null;
    },
  });
  const nomeDoCliente = cliente.data?.name ?? conjunto.cliente;
  const [saudacao, setSaudacao] = useState<Saudacao>(saudacaoSalva);
  const [telefone, setTelefone] = useState('');
  const [mensagem, setMensagem] = useState('');
  const [gerando, setGerando] = useState(false);
  const agora = useMemo(() => new Date(), [aberto]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!aberto) return;
    const abertura = textoDaSaudacao(saudacao, nomeDoCliente, agora);
    const corpo = mensagemPadraoDoConjunto(conjunto);
    setMensagem(abertura ? `${abertura} ${corpo}` : corpo);
  }, [aberto, conjunto]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (aberto && cliente.data) setTelefone(normalizePhoneE164(cliente.data.whatsapp || cliente.data.phone || ''));
  }, [aberto, cliente.data]);

  const escolherSaudacao = (v: string) => {
    if (!ehSaudacao(v)) return;
    setSaudacao(v);
    try { localStorage.setItem(CHAVE_DA_SAUDACAO, v); } catch { /* sem armazenamento: só nesta janela */ }
    setMensagem((m) => trocarSaudacao(m, textoDaSaudacao(v, nomeDoCliente, new Date()), nomeDoCliente));
  };

  const gerar = () => gerarPdfDoConjunto(conjunto, appSettings as Record<string, string> | undefined, { carregar: (id) => fetchPDFData(id) });

  async function baixar() {
    setGerando(true);
    try {
      const { blob, filename } = await gerar();
      baixarArquivo(blob, filename);
    } catch (e) {
      toast.error((e as Error).message || 'Não deu para gerar o PDF.');
    } finally {
      setGerando(false);
    }
  }

  async function enviar() {
    setGerando(true);
    let pdf: { blob: Blob; filename: string };
    try {
      pdf = await gerar();
    } catch (e) {
      toast.error((e as Error).message || 'Não deu para gerar o PDF.');
      setGerando(false);
      return;
    }
    setGerando(false);
    const alvo = alvosDoEnvio(conjunto);
    const ok = await send(
      {
        phone: telefone,
        message: mensagem,
        mode: 'document',
        context: alvo.context,
        service_order_id: alvo.serviceOrderId,
        conjunto_orcamento_ids: alvo.outrosOrcamentos,
        pdfBlob: pdf.blob,
        filename: pdf.filename,
        caption: mensagem,
      },
      { autoRetry: true, maxAttempts: 3 },
    );
    if (ok) onFechar();
  }

  const ocupado = gerando || sending;
  const opcoes = opcoesDeSaudacao(nomeDoCliente, agora);

  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && !ocupado && onFechar()}>
      <DialogContent className="max-h-[90dvh] max-w-lg overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Send className="h-5 w-5" /> Enviar ao cliente
          </DialogTitle>
          <DialogDescription className="break-words">{conjunto.nome}: um PDF só, com a capa e os documentos completos.</DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="conjunto-telefone">Telefone (com DDI)</Label>
            <Input
              id="conjunto-telefone"
              value={telefone}
              onChange={(e) => setTelefone(e.target.value)}
              placeholder="5521999998888"
              disabled={ocupado}
            />
            <p className="text-xs text-muted-foreground">
              Os orçamentos do conjunto só ficam como "enviados" quando o PDF vai para o número do cliente.
            </p>
          </div>

          <div className="space-y-2">
            <Label htmlFor="conjunto-saudacao">Saudação</Label>
            <Select value={saudacao} onValueChange={escolherSaudacao} disabled={ocupado}>
              <SelectTrigger id="conjunto-saudacao"><SelectValue /></SelectTrigger>
              <SelectContent>
                {opcoes.map((o) => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label htmlFor="conjunto-mensagem">Mensagem</Label>
            <Textarea
              id="conjunto-mensagem"
              value={mensagem}
              onChange={(e) => setMensagem(e.target.value)}
              rows={4}
              disabled={ocupado}
            />
          </div>
        </div>

        <DialogFooter className="gap-2 pb-[env(safe-area-inset-bottom)] sm:gap-0">
          <Button variant="outline" onClick={baixar} disabled={ocupado} className="gap-1.5">
            {gerando && !sending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
            Baixar PDF
          </Button>
          <Button onClick={enviar} disabled={ocupado || !mensagem.trim()} className="gap-1.5">
            {ocupado ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
            Enviar
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
