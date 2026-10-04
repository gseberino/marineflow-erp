/**
 * "Exportar XMLs para a contadora": um .zip com os XMLs das NF-e e NFS-e autorizadas e canceladas
 * de um período + o resumo CSV do livro de saída. A cancelada vai junto de propósito: sem ela, o
 * número parece uma inutilização ou lacuna no livro. As NFS-e entraram em 04/10/2026 (decisão do
 * dono); o proxy já devolvia o XML delas (xml_nfse) pelo mesmo pedido "xml_authorized".
 *
 * Saiu de FiscalEmission.tsx no D33 (01/10/2026) com o próprio estado. O CSV, o nome de cada XML
 * e o período são funções puras e testadas (src/lib/fiscal-exportacao.ts); o JSX veio copiado.
 *
 * Os XMLs são baixados pelo proxy autenticado (fiscal-emit, action "artifact"): as URLs da
 * Contora exigem token, que nunca sai do servidor.
 */
import { useState } from 'react';
import { toast } from 'sonner';
import { FileDown, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog';
import { supabase } from '@/integrations/supabase/client';
import { createZipBlob, type ZipEntry } from '@/lib/zip';
import {
  janelaDaConsultaDeNfse, limitesDoPeriodo, nfseDoPeriodo, nomeDoXml, periodoInicialDaExportacao,
  resumoDoLivroDeSaida,
} from '@/lib/fiscal-exportacao';

export function ExportarXmlsDialog({ onClose }: { onClose: () => void }) {
  const [exporting, setExporting] = useState(false);
  const [inicial] = useState(() => periodoInicialDaExportacao());
  const [exportFrom, setExportFrom] = useState(inicial.de);
  const [exportTo, setExportTo] = useState(inicial.ate);

  const handleExportXmls = async () => {
    if (!exportFrom || !exportTo || exportFrom > exportTo) {
      toast.error('Informe um período válido (início ≤ fim).');
      return;
    }
    setExporting(true);
    const tId = toast.loading('Consultando notas do período…');
    try {
      // NF-e: autorizadas E canceladas, pelo instante da autorização dentro dos dias LOCAIS escolhidos.
      const { inicio, fim } = limitesDoPeriodo(exportFrom, exportTo);
      const { data: nfes, error } = await supabase.from('issued_fiscal_documents')
        .select('id, document_type, series, number, access_key, status, authorized_at, environment, request_payload')
        .neq('document_type', 'nfse')
        .in('status', ['authorized', 'cancelled'])
        .gte('authorized_at', inicio)
        .lte('authorized_at', fim)
        .order('number', { ascending: true });
      if (error) throw error;

      // NFS-e: não tem authorized_at; a data é a do evento do provedor (dataDaNota). Consulta com
      // folga pelo created_at e corta pela data da nota.
      const janela = janelaDaConsultaDeNfse(inicio, fim);
      const { data: nfsesDaJanela, error: erroNfse } = await supabase.from('issued_fiscal_documents')
        .select('id, document_type, series, number, access_key, status, authorized_at, created_at, environment, request_payload, provider_status')
        .eq('document_type', 'nfse')
        .in('status', ['authorized', 'cancelled'])
        .gte('created_at', janela.inicio)
        .lte('created_at', janela.fim)
        .order('number', { ascending: true });
      if (erroNfse) throw erroNfse;

      const docs = [...(nfes ?? []), ...nfseDoPeriodo(nfsesDaJanela ?? [], inicio, fim)];
      if (!docs.length) {
        toast.error('Nenhuma nota autorizada/cancelada nesse período.', { id: tId });
        return;
      }

      const entries: ZipEntry[] = [];
      let ok = 0;
      let failed = 0;
      for (let i = 0; i < docs.length; i++) {
        const d = docs[i];
        toast.loading(`Baixando XML ${i + 1}/${docs.length}…`, { id: tId });
        try {
          const { data: xmlData, error: xmlErr } = await supabase.functions.invoke('fiscal-emit', {
            body: { action: 'artifact', document_id: d.id, artifact: 'xml_authorized' },
          });
          if (xmlErr) throw xmlErr;
          const text = xmlData instanceof Blob
            ? await xmlData.text()
            : typeof xmlData === 'string'
              ? xmlData
              : new TextDecoder().decode(xmlData as ArrayBuffer);
          if (text && text.trim().startsWith('<')) {
            entries.push({ name: nomeDoXml(d), content: text });
            ok++;
          } else {
            failed++;
          }
        } catch {
          failed++;
        }
      }

      entries.push({ name: '_resumo-livro-saida.csv', content: resumoDoLivroDeSaida(docs) });
      const blob = createZipBlob(entries);
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `XMLs-notas-fiscais_${exportFrom}_a_${exportTo}.zip`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 60_000);

      toast.success(`Exportadas ${ok} nota(s)${failed ? ` (${failed} XML não baixado)` : ''} + resumo CSV.`, { id: tId });
      onClose();
    } catch (err) {
      toast.error('Erro ao exportar: ' + ((err as Error)?.message || 'desconhecido'), { id: tId });
    } finally {
      setExporting(false);
    }
  };

  return (
    <Dialog open onOpenChange={(o) => { if (!exporting && !o) onClose(); }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Exportar XMLs para a contadora</DialogTitle>
          <DialogDescription>
            Baixa, num único arquivo .zip, os XMLs de todas as NF-e e NFS-e <strong>autorizadas e canceladas</strong> no
            período escolhido, mais um resumo em CSV (livro de saída: modelo, série/nº, chave, data, valor, destinatário).
          </DialogDescription>
        </DialogHeader>
        <div className="grid grid-cols-2 gap-3">
          <div>
            <Label>Início</Label>
            <Input type="date" value={exportFrom} max={exportTo} onChange={(e) => setExportFrom(e.target.value)} />
          </div>
          <div>
            <Label>Fim</Label>
            <Input type="date" value={exportTo} min={exportFrom} onChange={(e) => setExportTo(e.target.value)} />
          </div>
        </div>
        <p className="text-xs text-muted-foreground">
          Cada XML é baixado com autenticação (a chave/token nunca sai do servidor). Em períodos com muitas
          notas o download pode levar alguns segundos.
        </p>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={exporting}>Voltar</Button>
          <Button onClick={handleExportXmls} disabled={exporting}>
            {exporting ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <FileDown className="h-4 w-4 mr-2" />}
            Exportar .zip
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
