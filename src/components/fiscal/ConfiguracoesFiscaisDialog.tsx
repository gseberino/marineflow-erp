/**
 * Dados fiscais da empresa emitente, diagnóstico da conta na Contora, próximo número da NF-e e
 * teste de envio de e-mail. Saiu de FiscalEmission.tsx no D33 (01/10/2026) com o próprio estado
 * (seis useState que só este diálogo usava); o formulário nasce do cadastro a cada abertura.
 * Formulário ↔ banco em funções puras e testadas (src/lib/fiscal-configuracao.ts); JSX copiado.
 */
import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { CheckCircle2, Loader2, Mail, RefreshCw, Send, Stethoscope, XCircle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import { supabase } from '@/integrations/supabase/client';
import { maskCPFCNPJ } from '@/lib/masks';
import { extractInvokeErrorMessage } from '@/lib/invoke-error';
import { formularioDaEmpresa, payloadDasConfiguracoes } from '@/lib/fiscal-configuracao';

const BRAZILIAN_STATES = [
  'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS', 'MG',
  'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO',
];

// Resultado do diagnóstico da conta na Contora (action="diagnostics" no fiscal-emit).
interface DiagnosticsResult {
  token_ok: boolean;
  sefaz_ok: boolean;
  // Candidatos ao verProc (versão do software, máx 20 na NF-e). O que tiver
  // comprimento > 20 é o suspeito do erro "verProc length 21".
  verproc_candidates?: {
    token_name?: string | null;
    token_name_len?: number;
    legal_name?: string | null;
    legal_name_len?: number;
    trade_name?: string | null;
    trade_name_len?: number;
  };
  company: {
    found: boolean;
    id?: string | null;
    legal_name?: string | null;
    trade_name?: string | null;
    state_code?: string | null;
    city_code?: string | null;
    has_certificate?: boolean;
    default_environment?: string | null;
    // Verdade da API: a empresa aceita espelho de homologação? null = a Contora
    // não retornou o campo (recurso novo — pode não constar nesta conta ainda).
    allows_homologation?: boolean | null;
  } | null;
  message?: string;
}

export function ConfiguracoesFiscaisDialog({ company, onClose, onTestarEmail }: {
  /** O cadastro atual (company_fiscal_settings), ou nada se a empresa ainda não foi configurada. */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  company: any;
  onClose: () => void;
  /** Envia uma nota autorizada por e-mail ao próprio usuário (fluxo da tela). */
  onTestarEmail: () => void;
}) {
  const qc = useQueryClient();
  const [savingSettings, setSavingSettings] = useState(false);
  const [runningDiag, setRunningDiag] = useState(false);
  const [diagResult, setDiagResult] = useState<DiagnosticsResult | null>(null);
  const [enablingHomolog, setEnablingHomolog] = useState(false);
  const [settingsForm, setSettingsForm] = useState(() => formularioDaEmpresa(company));
  const [nextNumberInput, setNextNumberInput] = useState('');

  // Alinha o próximo número da NF-e de produção com o histórico da empresa na
  // SEFAZ (empresas que já emitiram em outro sistema). Chama a RPC admin-only
  // set_fiscal_next_number, que guarda contra apontar para um número já autorizado.
  const handleSetNextNumber = async () => {
    const n = parseInt(nextNumberInput, 10);
    if (!n || n < 1) { toast.error('Informe um número válido (maior ou igual a 1).'); return; }
    try {
      const { error } = await supabase.rpc('set_fiscal_next_number' as never, {
        p_document_type: 'nfe',
        p_series: Number(settingsForm.nfe_series_producao) || 1,
        p_environment: 'producao',
        p_next_number: n,
      } as never);
      if (error) throw new Error(error.message);
      toast.success(`Próximo número da série ${settingsForm.nfe_series_producao} (produção) definido como ${n}.`);
      setNextNumberInput('');
    } catch (err) {
      toast.error('Erro ao definir o número: ' + ((err as Error)?.message || 'desconhecido'));
    }
  };

  const handleSaveSettings = async () => {
    // UF é obrigatória: define se o CFOP calculado é interno (5xxx/1xxx) ou
    // interestadual (6xxx/2xxx). Sem ela a emissão trava no backend.
    if (!settingsForm.state_code) {
      toast.error('Selecione a UF da empresa — ela é obrigatória para calcular o CFOP das notas.');
      return;
    }
    setSavingSettings(true);
    try {
      const payload = payloadDasConfiguracoes(settingsForm);
      const { error } = company
        ? await supabase.from('company_fiscal_settings').update(payload).eq('id', company.id)
        : await supabase.from('company_fiscal_settings').insert(payload);
      // Corrida rara: duas pessoas configurando ao mesmo tempo na primeira vez — a constraint
      // de linha única (singleton_guard) rejeita o segundo insert com 23505. Trata como "alguém
      // já salvou primeiro": recarrega e avisa em vez de mostrar um erro de banco cru.
      if (error && (error as { code?: string }).code === '23505' && !company) {
        qc.invalidateQueries({ queryKey: ['company_fiscal_settings'] });
        toast.warning('A empresa já foi configurada por outra pessoa nesse meio-tempo. Reabra para editar.');
        onClose();
        return;
      }
      if (error) throw error;
      toast.success('Dados fiscais da empresa salvos.');
      onClose();
      qc.invalidateQueries({ queryKey: ['company_fiscal_settings'] });
    } catch (err) {
      toast.error('Erro ao salvar: ' + (err as Error).message);
    } finally {
      setSavingSettings(false);
    }
  };

  // Consulta o estado real da conta na Contora (empresa/city_code/certificado/
  // ambiente/SEFAZ). Read-only, não gasta cota — serve para o usuário entender
  // por que a emissão falha (ex.: "empresa sem city_code" é corrigido no console
  // da Contora, não aqui).
  const handleRunDiagnostics = async () => {
    setRunningDiag(true);
    try {
      const { data, error } = await supabase.functions.invoke('fiscal-emit', { body: { action: 'diagnostics' } });
      if (error) throw new Error(await extractInvokeErrorMessage(error));
      if (data?.error) throw new Error(data.error);
      setDiagResult((data?.data ?? data) as DiagnosticsResult);
    } catch (err) {
      toast.error('Erro no diagnóstico: ' + (err as Error).message);
      setDiagResult(null);
    } finally {
      setRunningDiag(false);
    }
  };

  // Liga allows_homologation na empresa PELA API (com a mesma chave), na empresa
  // exata que o token resolve — resolve o caso em que o painel foi ligado mas a
  // API ainda recusa homologação ("A chave de API não permite operações neste
  // ambiente"). Depois recarrega o diagnóstico para confirmar.
  const handleEnableHomolog = async () => {
    setEnablingHomolog(true);
    const tId = toast.loading('Habilitando homologação na Contora…');
    try {
      const { data, error } = await supabase.functions.invoke('fiscal-emit', { body: { action: 'enable_homolog' } });
      if (error) throw new Error(await extractInvokeErrorMessage(error));
      if (data?.error) throw new Error(data.error);
      const results = (data?.results ?? []) as Array<{ ok?: boolean; after?: boolean; company?: string; error?: string }>;
      const okOnes = results.filter((r) => r.ok && r.after === true);
      if (okOnes.length) {
        toast.success(`Homologação habilitada na Contora (${okOnes.map((r) => r.company).join(', ')}). Agora gere o espelho de novo.`, { id: tId });
      } else {
        const errs = results.map((r) => r.error).filter(Boolean).join('; ');
        toast.error('Não consegui habilitar via API: ' + (errs || 'resposta inesperada da Contora.'), { id: tId });
      }
      await handleRunDiagnostics();
    } catch (err) {
      toast.error('Erro ao habilitar homologação: ' + (err as Error).message, { id: tId });
    } finally {
      setEnablingHomolog(false);
    }
  };

  return (
    <Dialog open onOpenChange={(o) => { if (!o) onClose(); }}>
      {/* w-[95vw] + max-h/overflow: com muito conteúdo (empresa, endereço,
          numeração, certificado, diagnóstico, teste de e-mail) o diálogo passava
          da altura da tela e o topo/rodapé saíam do enquadramento. overflow-x-hidden
          garante zero scroll horizontal. */}
      <DialogContent className="max-w-lg w-[95vw] max-h-[90vh] overflow-y-auto overflow-x-hidden">
        <DialogHeader>
          <DialogTitle>Dados Fiscais da Empresa</DialogTitle>
          <DialogDescription>Registro local para controle interno.</DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div>
            <Label>Razão Social</Label>
            <Input value={settingsForm.legal_name} onChange={(e) => setSettingsForm((p) => ({ ...p, legal_name: e.target.value }))} />
          </div>
          <div>
            <Label>Nome Fantasia</Label>
            <Input value={settingsForm.trade_name} onChange={(e) => setSettingsForm((p) => ({ ...p, trade_name: e.target.value }))} />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>CNPJ</Label>
              <Input
                value={maskCPFCNPJ(settingsForm.cnpj)}
                onChange={(e) => setSettingsForm((p) => ({ ...p, cnpj: e.target.value.replace(/\D/g, '').slice(0, 14) }))}
              />
            </div>
            <div>
              <Label>Regime Tributário</Label>
              <Select value={settingsForm.tax_regime} onValueChange={(v) => setSettingsForm((p) => ({ ...p, tax_regime: v }))}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="mei">MEI</SelectItem>
                  <SelectItem value="simples">Simples Nacional</SelectItem>
                  <SelectItem value="presumido">Lucro Presumido</SelectItem>
                  <SelectItem value="real">Lucro Real</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="grid grid-cols-3 gap-3">
            <div>
              <Label>Inscrição Estadual</Label>
              <Input value={settingsForm.state_registration} onChange={(e) => setSettingsForm((p) => ({ ...p, state_registration: e.target.value }))} />
            </div>
            <div>
              <Label>Inscrição Municipal</Label>
              <Input value={settingsForm.municipal_registration} onChange={(e) => setSettingsForm((p) => ({ ...p, municipal_registration: e.target.value }))} />
            </div>
            <div>
              <Label>UF <span className="text-destructive">*</span></Label>
              <Select value={settingsForm.state_code} onValueChange={(v) => setSettingsForm((p) => ({ ...p, state_code: v }))}>
                <SelectTrigger className={!settingsForm.state_code ? 'border-destructive' : ''}><SelectValue placeholder="UF" /></SelectTrigger>
                <SelectContent>
                  {BRAZILIAN_STATES.map((uf) => (
                    <SelectItem key={uf} value={uf}>{uf}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          {/* Endereço do emitente — registro interno (a nota usa o cadastro da Contora). */}
          <div className="grid grid-cols-6 gap-2">
            <div className="col-span-4">
              <Label className="text-xs">Logradouro</Label>
              <Input className="h-8 text-xs" value={settingsForm.street} onChange={(e) => setSettingsForm((p) => ({ ...p, street: e.target.value }))} />
            </div>
            <div className="col-span-2">
              <Label className="text-xs">Número</Label>
              <Input className="h-8 text-xs" value={settingsForm.number} onChange={(e) => setSettingsForm((p) => ({ ...p, number: e.target.value }))} />
            </div>
            <div className="col-span-2">
              <Label className="text-xs">Bairro</Label>
              <Input className="h-8 text-xs" value={settingsForm.district} onChange={(e) => setSettingsForm((p) => ({ ...p, district: e.target.value }))} />
            </div>
            <div className="col-span-2">
              <Label className="text-xs">Cidade</Label>
              <Input className="h-8 text-xs" value={settingsForm.city_name} onChange={(e) => setSettingsForm((p) => ({ ...p, city_name: e.target.value }))} />
            </div>
            <div className="col-span-2">
              <Label className="text-xs">CEP</Label>
              <Input className="h-8 text-xs" value={settingsForm.postal_code} onChange={(e) => setSettingsForm((p) => ({ ...p, postal_code: e.target.value.replace(/\D/g, '').slice(0, 8) }))} />
            </div>
          </div>

          <p className="text-xs text-muted-foreground">
            A <strong>UF é obrigatória</strong>: define se o CFOP calculado em cada emissão é de operação interna (mesmo
            estado) ou interestadual. Os demais dados são registro local, para exibição — não são enviados à Contora e não
            determinam qual empresa efetivamente emite. Quem manda isso é o cadastro feito direto no console da Contora
            (CNPJ + certificado A1), vinculado ao token configurado nos Secrets do Supabase.
          </p>

          {/* Numeração da NF-e em produção (série + próximo número). */}
          <div className="rounded-lg border p-3 space-y-2.5">
            <p className="text-sm font-semibold">Numeração da NF-e (produção)</p>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <Label className="text-xs">Série de produção</Label>
                <Input
                  type="number" min={1} className="h-8 text-xs"
                  value={settingsForm.nfe_series_producao}
                  onChange={(e) => setSettingsForm((p) => ({ ...p, nfe_series_producao: Math.max(1, parseInt(e.target.value, 10) || 1) }))}
                />
              </div>
              <div>
                <Label className="text-xs">Ajustar próximo número</Label>
                <div className="flex gap-1.5">
                  <Input
                    type="number" min={1} className="h-8 text-xs"
                    placeholder="ex.: 1"
                    value={nextNumberInput}
                    onChange={(e) => setNextNumberInput(e.target.value.replace(/\D/g, ''))}
                  />
                  <Button type="button" size="sm" variant="outline" className="h-8 text-xs shrink-0" onClick={handleSetNextNumber}>
                    Definir
                  </Button>
                </div>
              </div>
            </div>
            <p className="text-[11px] text-muted-foreground">
              Se a empresa <strong>já emitiu NF-e em outro sistema</strong>, use uma <strong>série nova</strong> (que nunca
              emitiu em produção) para começar a numeração limpa — assim evita a Rejeição 539 ("número já utilizado").
              O "próximo número" só é necessário para <strong>continuar</strong> uma série existente a partir de um número
              específico (confirme o último número com a contadora). Homologação usa sempre a série 2. Salve a série no botão abaixo.
            </p>
          </div>

          {/* ── NFS-e (padrão nacional) ── */}
          <div className="rounded-lg border p-3 space-y-2.5">
            <p className="text-sm font-semibold">NFS-e — Nota Fiscal de Serviço</p>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <Label className="text-xs">Padrão de emissão</Label>
                <Select
                  value={settingsForm.nfse_standard}
                  onValueChange={(v) => setSettingsForm((p) => ({ ...p, nfse_standard: v }))}
                >
                  <SelectTrigger className="h-8 text-xs"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="nacional">Nacional (Itajaí usa este)</SelectItem>
                    <SelectItem value="municipal">Municipal (layout próprio)</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div>
                <Label className="text-xs">Série da NFS-e</Label>
                <Input
                  type="number" min={1} className="h-8 text-xs"
                  value={settingsForm.nfse_default_series}
                  onChange={(e) => setSettingsForm((p) => ({ ...p, nfse_default_series: Math.max(1, parseInt(e.target.value, 10) || 1) }))}
                />
              </div>
              <div>
                <Label className="text-xs">% total do Simples (pTotTribSN)</Label>
                <Input
                  type="number" min={0} max={100} step="0.01" className="h-8 text-xs"
                  placeholder="ex.: 6,00"
                  value={settingsForm.nfse_total_tax_rate_sn}
                  onChange={(e) => setSettingsForm((p) => ({ ...p, nfse_total_tax_rate_sn: e.target.value }))}
                />
              </div>
              <div>
                <Label className="text-xs">Código IBGE do município</Label>
                <Input
                  className="h-8 text-xs" placeholder="Itajaí = 4208203"
                  value={settingsForm.ibge_city_code}
                  onChange={(e) => setSettingsForm((p) => ({ ...p, ibge_city_code: e.target.value.replace(/\D/g, '').slice(0, 7) }))}
                />
              </div>
            </div>
            <label className="flex items-center gap-2 text-xs">
              <input
                type="checkbox"
                checked={settingsForm.nfse_municipal_registration_in_cnc}
                onChange={(e) => setSettingsForm((p) => ({ ...p, nfse_municipal_registration_in_cnc: e.target.checked }))}
              />
              Inscrição municipal registrada no CNC NFS-e (desmarque se a emissão voltar com E0120)
            </label>
            <p className="text-[11px] text-muted-foreground">
              O <strong>pTotTribSN não é a alíquota de ISS</strong>: é a carga total aproximada de tributos da faixa do
              Simples — sem ele a NFS-e do optante é rejeitada (E0712). O valor de <strong>6,00% foi confirmado pela
              contadora em 18/08/2026</strong> (HBR optante do Simples desde jan/2026). Ele muda com a faixa de
              faturamento — reconfirmar com a contabilidade quando a faixa mudar. Os códigos de tributação dos serviços
              vivem em Configurações → Fiscal → Verbos (confirmados: tudo 14.01, ISS 3%, sem retenção).
            </p>
          </div>

          {/* Diagnóstico da conta na Contora — mostra o que impede a emissão. */}
          <div className="rounded-lg border p-3 space-y-2">
            <div className="flex items-center justify-between">
              <p className="text-sm font-semibold flex items-center gap-1.5">
                <Stethoscope className="h-4 w-4" /> Diagnóstico da conta Contora
              </p>
              <Button type="button" size="sm" variant="outline" onClick={handleRunDiagnostics} disabled={runningDiag}>
                {runningDiag ? <Loader2 className="h-3.5 w-3.5 animate-spin mr-1" /> : <RefreshCw className="h-3.5 w-3.5 mr-1" />}
                Verificar
              </Button>
            </div>
            {!diagResult ? (
              <p className="text-xs text-muted-foreground">
                Confirma, direto na Contora, se a empresa emissora está pronta (município/IBGE, certificado, ambiente) e
                se a SEFAZ está online. Não gasta cota fiscal.
              </p>
            ) : (
              <ul className="space-y-1 text-xs">
                {[
                  { ok: diagResult.token_ok, label: 'Token da Contora válido' },
                  { ok: !!diagResult.company?.found, label: `Empresa cadastrada na Contora${diagResult.company?.legal_name ? ` (${diagResult.company.legal_name})` : ''}` },
                  { ok: !!diagResult.company?.city_code, label: `Município/código IBGE preenchido${diagResult.company?.city_code ? ` (${diagResult.company.city_code})` : ''}` },
                  { ok: !!diagResult.company?.has_certificate, label: 'Certificado A1 enviado' },
                  { ok: diagResult.sefaz_ok, label: 'SEFAZ online' },
                ].map((c, i) => (
                  <li key={i} className={`flex items-center gap-2 ${c.ok ? 'text-success' : 'text-destructive'}`}>
                    {c.ok ? <CheckCircle2 className="h-3.5 w-3.5" /> : <XCircle className="h-3.5 w-3.5" />}
                    {c.label}
                  </li>
                ))}
                {!diagResult.company?.city_code && (
                  <li className="text-amber-700 mt-1">
                    ⚠ Corrija no <strong>console da Contora → Empresas → editar → Município</strong>. Esse campo não é
                    editável por aqui (a API não expõe update de empresa).
                  </li>
                )}
                {/* Espelho de homologação: verdade da API (não do painel). Se
                    bloqueado, liga allows_homologation pela API na empresa exata
                    que o token resolve. */}
                {diagResult.company?.found && (
                  <li className="mt-2 border-t pt-2 list-none">
                    <div className={`flex items-center gap-2 ${diagResult.company.allows_homologation === true ? 'text-success' : 'text-amber-700'}`}>
                      {diagResult.company.allows_homologation === true ? <CheckCircle2 className="h-3.5 w-3.5" /> : <XCircle className="h-3.5 w-3.5" />}
                      Espelho de homologação {diagResult.company.allows_homologation === true ? 'liberado' : diagResult.company.allows_homologation === false ? 'BLOQUEADO nesta empresa' : 'não informado pela Contora'}
                      {diagResult.company.id ? <span className="text-muted-foreground font-mono ml-1">· {String(diagResult.company.id).slice(0, 8)}</span> : null}
                    </div>
                    {diagResult.company.allows_homologation !== true && (
                      <div className="mt-1 space-y-1.5">
                        <p className="text-muted-foreground">
                          O botão “Gerar espelho” precisa disto para trazer a DANFE real de homologação (validada pela SEFAZ).
                          Ligo o flag <strong>pela API, na empresa que a chave usa</strong> — sem depender do painel.
                        </p>
                        <Button size="sm" variant="outline" onClick={handleEnableHomolog} disabled={enablingHomolog}>
                          {enablingHomolog ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
                          Habilitar homologação na Contora
                        </Button>
                      </div>
                    )}
                  </li>
                )}
                {/* Diagnóstico do verProc: o campo que a Contora usa como "versão do
                    software" tem limite de 20 caracteres. Mostramos os candidatos e
                    o comprimento — o que passar de 20 é a causa do erro de schema. */}
                {diagResult.verproc_candidates && (() => {
                  const vc = diagResult.verproc_candidates!;
                  const rows = [
                    { label: 'Nome do token de API', val: vc.token_name, len: vc.token_name_len ?? 0 },
                    { label: 'Razão social (Contora)', val: vc.legal_name, len: vc.legal_name_len ?? 0 },
                    { label: 'Nome fantasia (Contora)', val: vc.trade_name, len: vc.trade_name_len ?? 0 },
                  ].filter((r) => r.val);
                  const suspect = rows.find((r) => r.len > 20);
                  return (
                    <li className="mt-2 border-t pt-2 list-none">
                      <p className="font-semibold text-foreground">verProc (versão do software, máx. 20):</p>
                      {rows.map((r, i) => (
                        <div key={i} className={r.len > 20 ? 'text-destructive' : 'text-muted-foreground'}>
                          {r.len > 20 ? '❌' : '•'} {r.label}: "{r.val}" ({r.len} caract.)
                        </div>
                      ))}
                      {suspect && (
                        <p className="text-amber-700 mt-1">
                          ⚠ O campo <strong>{suspect.label}</strong> tem {suspect.len} caracteres (a Contora provavelmente
                          o usa como verProc, limitado a 20). Renomeie-o para ≤20 no console da Contora e reemita.
                        </p>
                      )}
                    </li>
                  );
                })()}
              </ul>
            )}
          </div>

          {/* Testar envio de e-mail: valida a config SMTP reusando a última nota
              autorizada (PDF+XML reais), sem emitir nada novo. */}
          <div className="rounded-lg border p-3 space-y-2">
            <div className="flex items-center justify-between">
              <p className="text-sm font-semibold flex items-center gap-1.5">
                <Mail className="h-4 w-4" /> Testar envio de e-mail
              </p>
              <Button type="button" size="sm" variant="outline" onClick={onTestarEmail}>
                <Send className="h-3.5 w-3.5 mr-1" />
                Enviar teste
              </Button>
            </div>
            <p className="text-xs text-muted-foreground">
              Envia o PDF + XML da <strong>última NF-e autorizada</strong> para um e-mail que você escolhe
              (por padrão, o seu e-mail de login) — confere se o SMTP está funcionando, <strong>sem emitir nenhuma
              nota nova</strong>.
            </p>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancelar</Button>
          <Button onClick={handleSaveSettings} disabled={savingSettings}>
            {savingSettings ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
            Salvar
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
