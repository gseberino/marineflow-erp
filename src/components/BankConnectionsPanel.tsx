import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { StatusBadge } from '@/components/StatusBadge';
import { useI18n } from '@/i18n';
import {
  useBankConnections, useSaveBankConnection, useDeleteBankConnection, useSyncBank,
  useListPluggyItems,
  type BankConnection, type PluggyItemDisponivel,
} from '@/hooks/use-bank-connections';
import { toast } from 'sonner';
import { RefreshCw, Plus, Trash2, AlertTriangle, CheckCircle2, Link2 } from 'lucide-react';

/**
 * Conexões de leitura do extrato (Open Finance).
 *
 * O modelo gratuito do Pluggy não tem widget de conexão dentro do sistema: a conta é
 * ligada pelo titular no portal do Meu Pluggy, e o que o ERP guarda é o identificador do
 * vínculo. Por isso a tela pede um código em vez de abrir a tela do banco — e explica de
 * onde tirar esse código, que é a parte que ninguém adivinha.
 */
export function BankConnectionsPanel() {
  const { formatDate } = useI18n();
  const { data: conexoes, isLoading } = useBankConnections();
  const salvar = useSaveBankConnection();
  const excluir = useDeleteBankConnection();
  const sincronizar = useSyncBank();

  const listarItens = useListPluggyItems();
  const [novoAberto, setNovoAberto] = useState(false);
  const [disponiveis, setDisponiveis] = useState<PluggyItemDisponivel[] | null>(null);
  const [clientIdPrefixo, setClientIdPrefixo] = useState('');
  const [form, setForm] = useState({ external_id: '', label: '', account_kind: 'bank' as 'bank' | 'credit_card' });

  const handleListar = async () => {
    try {
      const { itens, clientIdPrefixo: prefixo } = await listarItens.mutateAsync();
      setDisponiveis(itens);
      setClientIdPrefixo(prefixo);
      if (itens.length === 0) {
        toast.warning('Nenhuma conexão visível com as credenciais atuais.');
      }
    } catch (e: any) {
      toast.error(e?.message || 'Não consegui consultar as conexões');
    }
  };

  const handleSalvar = async () => {
    if (!form.external_id.trim() || !form.label.trim()) {
      toast.error('Informe o apelido e o Item ID');
      return;
    }
    // Client ID e Item ID têm o mesmo formato e ficam na mesma tela do painel — trocar um
    // pelo outro dá "conexão não encontrada", que parece erro de digitação e faz a pessoa
    // reconferir o código certo por horas. Barrar aqui é mais barato que diagnosticar depois.
    if (clientIdPrefixo && form.external_id.trim().toLowerCase().startsWith(clientIdPrefixo.toLowerCase())) {
      toast.error('Isto é o Client ID da aplicação, não o Item ID da conexão. Pegue o Item ID em "Ir para Demo", no painel do provedor.');
      return;
    }
    try {
      await salvar.mutateAsync(form);
      toast.success('Conexão cadastrada. Use "Buscar extrato" para trazer as transações.');
      setForm({ external_id: '', label: '', account_kind: 'bank' });
      setNovoAberto(false);
    } catch (e: any) {
      toast.error(e?.message?.includes('duplicate') ? 'Esta conexão já está cadastrada.' : (e?.message || 'Erro ao salvar'));
    }
  };

  const handleSincronizar = async (connectionId?: string, full = false) => {
    try {
      const r = await sincronizar.mutateAsync({ connectionId, full });
      const comErro = r.resultados.filter(x => x.status === 'error');
      if (comErro.length > 0) {
        toast.warning(comErro.map(x => `${x.conexao}: ${x.mensagem}`).join(' · '));
      } else {
        toast.success(r.message);
      }
    } catch (e: any) {
      toast.error(e?.message || 'Não consegui buscar o extrato');
    }
  };

  const handleExcluir = async (c: BankConnection) => {
    try {
      await excluir.mutateAsync(c.id);
      toast.success(`Conexão "${c.label}" removida. As transações já importadas continuam no sistema.`);
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao remover');
    }
  };

  const diasDesde = (iso: string | null) =>
    iso ? Math.floor((Date.now() - new Date(iso).getTime()) / 86400000) : null;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <div>
          <h3 className="font-semibold">Contas conectadas</h3>
          <p className="text-sm text-muted-foreground">
            O extrato entra sozinho, sem exportar arquivo do banco.
          </p>
        </div>
        <div className="flex gap-2">
          {(conexoes?.length ?? 0) > 0 && (
            <Button size="sm" onClick={() => handleSincronizar()} disabled={sincronizar.isPending}>
              <RefreshCw className={`h-3.5 w-3.5 mr-1.5 ${sincronizar.isPending ? 'animate-spin' : ''}`} />
              {sincronizar.isPending ? 'Buscando...' : 'Buscar extrato'}
            </Button>
          )}
          <Button size="sm" variant="outline" onClick={() => setNovoAberto(v => !v)}>
            <Plus className="h-3.5 w-3.5 mr-1.5" />Conectar conta
          </Button>
        </div>
      </div>

      {novoAberto && (
        <div className="rounded-lg border bg-card p-4 space-y-3">
          {/* Sem este roteiro, o campo "Item ID" é impossível de preencher: ele não existe
              em lugar nenhum do banco, só dentro do painel do Pluggy. */}
          <div className="rounded-lg bg-muted/50 p-3 text-sm space-y-1.5">
            <p className="font-medium flex items-center gap-1.5">
              <Link2 className="h-3.5 w-3.5" />Onde encontrar o Item ID
            </p>
            <ol className="list-decimal ml-4 space-y-1 text-muted-foreground">
              <li>Conecte a conta em <span className="font-mono text-xs">meu.pluggy.ai</span> (é onde você autoriza o banco).</li>
              <li>No painel do Pluggy, abra sua aplicação e escolha o conector <strong>MeuPluggy</strong> para autorizar o acesso.</li>
              <li>
                Clique em <strong>"Ir para Demo"</strong> e copie o <strong>Item ID</strong> da conexão —
                não confunda com o Client ID da aplicação: têm o mesmo formato e ficam próximos na tela.
              </li>
            </ol>
          </div>

          {/* Em vez de digitar um código que não se sabe de onde tirar, perguntar ao
              provedor o que ele enxerga com as credenciais atuais. */}
          <div className="space-y-2">
            <Button size="sm" variant="outline" onClick={handleListar} disabled={listarItens.isPending}>
              <Link2 className="h-3.5 w-3.5 mr-1.5" />
              {listarItens.isPending ? 'Consultando...' : 'Tentar detectar conexões'}
            </Button>

            {disponiveis && disponiveis.length > 0 && (
              <div className="rounded-lg border divide-y">
                {disponiveis.map(item => (
                  <div key={item.id} className="p-2 flex items-center justify-between gap-2 flex-wrap text-sm">
                    <div className="min-w-0">
                      <span className="font-medium">{item.connector}</span>
                      <span className="text-muted-foreground ml-2">{item.status}</span>
                      <p className="text-xs text-muted-foreground font-mono">{item.id}</p>
                    </div>
                    {item.ja_cadastrado ? (
                      <StatusBadge className="bg-muted text-muted-foreground">já cadastrada</StatusBadge>
                    ) : (
                      <Button size="sm" variant="outline"
                        onClick={() => setForm(f => ({ ...f, external_id: item.id, label: f.label || item.connector }))}>
                        Usar esta
                      </Button>
                    )}
                  </div>
                ))}
              </div>
            )}
            {disponiveis && disponiveis.length === 0 && (
              <div className="rounded-lg border border-warning/40 bg-warning/5 p-3 text-sm space-y-1.5">
                <p className="font-medium">O provedor não permite listar as conexões por aqui.</p>
                <p className="text-muted-foreground">
                  É preciso copiar o Item ID no painel, seguindo o roteiro acima. Atenção: o Item ID
                  <strong> não é</strong> o Client ID da aplicação — são códigos diferentes e ambos
                  têm o mesmo formato, o que torna fácil trocar um pelo outro.
                  {clientIdPrefixo && (
                    <> O Client ID em uso aqui começa com{' '}
                    <span className="font-mono font-medium">{clientIdPrefixo}</span> — se o código
                    que você copiou começar assim, é o Client ID, não a conexão.</>
                  )}
                </p>
              </div>
            )}
            {disponiveis && disponiveis.length > 0 && clientIdPrefixo && (
              <p className="text-xs text-muted-foreground">
                Aplicação em uso: <span className="font-mono">{clientIdPrefixo}…</span>
              </p>
            )}
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <Label>Apelido</Label>
              <Input
                placeholder="C6 — conta PJ"
                value={form.label}
                onChange={e => setForm({ ...form, label: e.target.value })}
              />
            </div>
            <div>
              <Label>Item ID</Label>
              <Input
                placeholder="00000000-0000-0000-0000-000000000000"
                value={form.external_id}
                onChange={e => setForm({ ...form, external_id: e.target.value })}
                className="font-mono text-sm"
              />
            </div>
          </div>

          <div className="flex items-center gap-2 flex-wrap">
            <span className="text-sm text-muted-foreground">Tipo:</span>
            {([
              { v: 'bank' as const, l: 'Conta corrente' },
              { v: 'credit_card' as const, l: 'Cartão de crédito' },
            ]).map(({ v, l }) => (
              <Button key={v} size="sm" variant={form.account_kind === v ? 'default' : 'outline'}
                onClick={() => setForm({ ...form, account_kind: v })}>
                {l}
              </Button>
            ))}
          </div>

          <div className="flex gap-2">
            <Button size="sm" onClick={handleSalvar} disabled={salvar.isPending}>Salvar conexão</Button>
            <Button size="sm" variant="outline" onClick={() => setNovoAberto(false)}>Cancelar</Button>
          </div>
        </div>
      )}

      {isLoading && <p className="text-sm text-muted-foreground">Carregando...</p>}

      {!isLoading && (conexoes?.length ?? 0) === 0 && !novoAberto && (
        <div className="rounded-lg border border-dashed p-6 text-center">
          <p className="text-sm text-muted-foreground">
            Nenhuma conta conectada. Enquanto isso, o extrato pode ser importado por arquivo
            OFX na aba de conciliação.
          </p>
        </div>
      )}

      <div className="space-y-2">
        {(conexoes || []).map(c => {
          const dias = diasDesde(c.last_synced_at);
          const desatualizada = dias !== null && dias > 2;
          return (
            <div key={c.id} className="rounded-lg border bg-card p-3 flex items-start justify-between gap-3 flex-wrap">
              <div className="min-w-0">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="font-medium">{c.label}</span>
                  <StatusBadge className={c.account_kind === 'credit_card' ? 'bg-accent/15 text-accent' : 'bg-muted text-muted-foreground'}>
                    {c.account_kind === 'credit_card' ? 'Cartão' : 'Conta corrente'}
                  </StatusBadge>
                  {c.last_sync_status === 'ok' && !desatualizada && (
                    <StatusBadge className="bg-success/15 text-success">
                      <CheckCircle2 className="h-3 w-3 mr-1 inline" />em dia
                    </StatusBadge>
                  )}
                  {c.last_sync_status === 'error' && (
                    <StatusBadge className="bg-destructive/10 text-destructive">
                      <AlertTriangle className="h-3 w-3 mr-1 inline" />com problema
                    </StatusBadge>
                  )}
                  {c.last_sync_status === 'ok' && desatualizada && (
                    <StatusBadge className="bg-warning/15 text-warning">sem atualizar há {dias} dias</StatusBadge>
                  )}
                </div>
                <p className="text-xs text-muted-foreground font-mono mt-0.5">{c.external_id}</p>
                {c.last_sync_message && (
                  <p className={`text-xs mt-1 ${c.last_sync_status === 'error' ? 'text-destructive' : 'text-muted-foreground'}`}>
                    {c.last_sync_message}
                    {c.last_synced_at && c.last_sync_status === 'ok' && ` · ${formatDate(c.last_synced_at)}`}
                  </p>
                )}
                {!c.last_synced_at && (
                  <p className="text-xs text-muted-foreground mt-1">Ainda não sincronizada.</p>
                )}
              </div>

              <div className="flex items-center gap-1 shrink-0">
                <Button size="sm" variant="outline" onClick={() => handleSincronizar(c.id)} disabled={sincronizar.isPending}>
                  <RefreshCw className="h-3 w-3 mr-1" />Buscar
                </Button>
                <Button size="sm" variant="ghost" onClick={() => handleSincronizar(c.id, true)}
                  disabled={sincronizar.isPending} title="Rebusca o último ano inteiro">
                  Histórico
                </Button>
                <Button size="sm" variant="ghost" onClick={() => handleExcluir(c)} disabled={excluir.isPending}>
                  <Trash2 className="h-3 w-3 text-destructive" />
                </Button>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
