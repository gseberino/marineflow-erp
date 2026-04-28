import { useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { PageHeader } from '@/components/PageHeader';
import { Loader2, Upload, FileCheck2, AlertCircle } from 'lucide-react';
import { toast } from 'sonner';

type Result = {
  ok?: boolean;
  fiscal_note_id?: string;
  payable_id?: string | null;
  items_count?: number;
  matched_count?: number;
  already_imported?: boolean;
  parsed?: any;
  error?: string;
};

function fileToBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => {
      const s = String(r.result || '');
      resolve(s.split(',')[1] || s);
    };
    r.onerror = () => reject(r.error);
    r.readAsDataURL(file);
  });
}

export default function ImportFiscalXML() {
  const [file, setFile] = useState<File | null>(null);
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<Result | null>(null);

  const handleImport = async () => {
    if (!file) {
      toast.error('Selecione um arquivo XML');
      return;
    }
    setLoading(true);
    setResult(null);
    try {
      const xml_base64 = await fileToBase64(file);
      const { data, error } = await supabase.functions.invoke('process-nfe-xml', {
        body: { xml_base64, persist: true, create_inventory: true, create_payable: true },
      });
      if (error) throw error;
      const r = data as Result;
      if (r?.error) throw new Error(r.error);
      setResult(r);
      if (r.already_imported) {
        toast.info('NFe já importada anteriormente');
      } else {
        toast.success(`NFe importada: ${r.matched_count}/${r.items_count} itens vinculados`);
      }
    } catch (e: any) {
      const msg = e?.message || 'Erro ao importar XML';
      setResult({ error: msg });
      toast.error(msg);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader title="Importar XML de NFe" subtitle="Entrada de estoque automática a partir do XML do fornecedor" />

      <Card>
        <CardHeader>
          <CardTitle>Selecionar arquivo</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div>
            <Label htmlFor="xml-file">Arquivo XML da NFe</Label>
            <Input
              id="xml-file"
              type="file"
              accept=".xml,text/xml,application/xml"
              onChange={(e) => setFile(e.target.files?.[0] || null)}
            />
          </div>
          <Button onClick={handleImport} disabled={!file || loading}>
            {loading ? (
              <>
                <Loader2 className="h-4 w-4 mr-2 animate-spin" /> Processando...
              </>
            ) : (
              <>
                <Upload className="h-4 w-4 mr-2" /> Importar XML
              </>
            )}
          </Button>
        </CardContent>
      </Card>

      {result?.error && (
        <Card className="border-destructive">
          <CardContent className="pt-6 flex items-start gap-2 text-destructive">
            <AlertCircle className="h-5 w-5 mt-0.5" />
            <div>
              <div className="font-medium">Falha na importação</div>
              <div className="text-sm">{result.error}</div>
            </div>
          </CardContent>
        </Card>
      )}

      {result?.parsed && !result.error && (
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <FileCheck2 className="h-5 w-5 text-primary" />
              Resultado da importação
              {result.already_imported && <Badge variant="secondary">já importada</Badge>}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3 text-sm">
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
              <div>
                <div className="text-muted-foreground text-xs">NFe nº</div>
                <div className="font-medium">{result.parsed.nfe_number || '—'}</div>
              </div>
              <div>
                <div className="text-muted-foreground text-xs">Emissor</div>
                <div className="font-medium">{result.parsed.issuer_name || '—'}</div>
              </div>
              <div>
                <div className="text-muted-foreground text-xs">Data</div>
                <div className="font-medium">{result.parsed.issue_date || '—'}</div>
              </div>
              <div>
                <div className="text-muted-foreground text-xs">Total</div>
                <div className="font-medium">
                  {Number(result.parsed.total_value || 0).toLocaleString('pt-BR', {
                    style: 'currency',
                    currency: 'BRL',
                  })}
                </div>
              </div>
            </div>

            <div className="text-sm text-muted-foreground">
              {result.matched_count ?? 0} de {result.items_count ?? 0} itens vinculados a produtos
              cadastrados (pelo SKU/EAN). Os demais foram registrados sem entrada de estoque.
            </div>

            {result.payable_id && (
              <Badge variant="outline">Conta a pagar criada automaticamente</Badge>
            )}
          </CardContent>
        </Card>
      )}
    </div>
  );
}
