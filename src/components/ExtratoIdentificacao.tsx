// Quem é e o que paga — as duas perguntas de cada linha do Extrato, com a prova à vista.
//
// Fase 2 do Financeiro Confiável. Até aqui a linha mostrava uma categoria e, às vezes, um
// seletor de cliente, sem dizer POR QUE o sistema achava aquilo — e o dono tinha razão em
// não confiar numa sugestão que não se explica. Agora:
//   * cada cadastro reconhecido vem com a prova ("por CNPJ", "por lançamentos anteriores",
//     "nome parecido — confira");
//   * quando nada bate, "Cadastrar" abre o cadastro já preenchido (Receita, para CNPJ);
//   * quando a linha pode já estar lançada, a tela pede para escolher entre casar com o que
//     existe e lançar novo — e não deixa aprovar no escuro.
import { useEffect, useState } from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { CategoriaDespesaSelect } from '@/components/CategoriaDespesaSelect';
import { useI18n } from '@/i18n';
import { ROTULO_TIPO, type TipoFavorecido } from '@/hooks/use-payees';
import {
  useCadastrarContraparte, useConsultaDeDocumento, type TipoDeCadastro,
} from '@/hooks/use-contraparte';
import { opcoesDoVinculo, precisaDecidir, vinculoEfetivo, type EscolhaDeVinculo } from '@/lib/extrato-vinculo';
import { ROTULO_DA_EVIDENCIA, type Identificacao, type Reconhecimento, type TipoDeEvidencia } from '../../supabase/functions/_shared/banking/contraparte';
import type { VinculoSugerido } from '../../supabase/functions/_shared/banking/vinculo';
import { AlertTriangle, Link2, ShieldCheck, UserPlus } from 'lucide-react';

/** Prova forte (verde), média (neutra) ou que pede conferência (âmbar). */
function tomDaEvidencia(por: TipoDeEvidencia): string {
  if (por === 'documento' || por === 'conta_bancaria' || por === 'regra' || por === 'historico') {
    return 'border-success/40 text-success';
  }
  if (por === 'nome_parecido') return 'border-amber-500/50 text-amber-600';
  return 'text-muted-foreground';
}

const ROTULO_DO_TIPO: Record<'fornecedor' | 'favorecido' | 'cliente', string> = {
  fornecedor: 'Fornecedor', favorecido: 'Favorecido', cliente: 'Cliente',
};

function Chip({ tipo, r }: { tipo: 'fornecedor' | 'favorecido' | 'cliente'; r: Reconhecimento }) {
  return (
    <Badge variant="outline" className={`max-w-full gap-1 text-xs font-normal ${tomDaEvidencia(r.por)}`} title={r.detalhe}>
      <ShieldCheck className="h-3 w-3 shrink-0" />
      <span className="truncate">
        {ROTULO_DO_TIPO[tipo]}: <b className="font-semibold">{r.nome}</b> · por {ROTULO_DA_EVIDENCIA[r.por] ?? r.por}
      </span>
    </Badge>
  );
}

/** Quem é a contraparte, com a prova; e o botão de cadastrar quando nada bateu. */
export function EvidenciaDaLinha({
  evidencia, ehReceita, categoria, ocupado,
}: {
  evidencia: Partial<Identificacao> | null | undefined;
  ehReceita: boolean;
  categoria: string;
  ocupado: boolean;
}) {
  const [cadastrando, setCadastrando] = useState(false);
  if (!evidencia) return null;
  const { fornecedor, favorecido, cliente, outroCadastro, cadastrar, nomeConhecido } = evidencia;
  if (!fornecedor && !favorecido && !cliente && !outroCadastro && !cadastrar && !nomeConhecido) return null;

  return (
    <div className="mt-2 flex max-w-2xl flex-wrap items-center gap-1.5">
      {fornecedor && <Chip tipo="fornecedor" r={fornecedor} />}
      {favorecido && <Chip tipo="favorecido" r={favorecido} />}
      {cliente && <Chip tipo="cliente" r={cliente} />}
      {nomeConhecido && !fornecedor && !favorecido && !cliente && (
        <span className="text-xs text-muted-foreground">O banco não mandou o nome; pelo documento é <b>{nomeConhecido}</b>.</span>
      )}
      {outroCadastro && (
        <span className="text-xs text-muted-foreground">
          O documento é do {outroCadastro.tipo} <b>{outroCadastro.nome}</b>
          {ehReceita && outroCadastro.tipo === 'fornecedor' ? ' — devolução ou reembolso?' : ''}
          {ehReceita && outroCadastro.tipo === 'favorecido' ? ' — aporte de sócio?' : ''}.
        </span>
      )}
      {cadastrar && (
        <>
          <Button size="sm" variant="outline" className="h-7 gap-1 text-xs" disabled={ocupado} onClick={() => setCadastrando(true)}>
            <UserPlus className="h-3.5 w-3.5" />
            Cadastrar {cadastrar.tipo}
          </Button>
          {cadastrando && (
            <CadastrarContraparteDialog
              sugestao={cadastrar}
              categoriaAtual={ehReceita ? null : categoria}
              onFechar={() => setCadastrando(false)}
            />
          )}
        </>
      )}
    </div>
  );
}

/**
 * Cadastro a partir do extrato. Com CNPJ, os campos chegam da Receita; o que vier pode ser
 * corrigido antes de salvar. Um documento, um cadastro: se já existir, o banco devolve o que
 * existe em vez de duplicar.
 */
export function CadastrarContraparteDialog({
  sugestao, categoriaAtual, onFechar,
}: {
  sugestao: { tipo: TipoDeCadastro; documento: string | null; nome: string | null };
  categoriaAtual: string | null;
  onFechar: () => void;
}) {
  const doc = (sugestao.documento ?? '').replace(/\D/g, '');
  const consulta = useConsultaDeDocumento(doc, doc.length === 14);
  const cadastrar = useCadastrarContraparte();

  const [tipo, setTipo] = useState<TipoDeCadastro>(sugestao.tipo);
  const [nome, setNome] = useState(sugestao.nome ?? '');
  const [fantasia, setFantasia] = useState('');
  const [tipoFav, setTipoFav] = useState<TipoFavorecido>('prestador');
  const [categoria, setCategoria] = useState(categoriaAtual && categoriaAtual !== 'Outras despesas' ? categoriaAtual : '');
  const [cidade, setCidade] = useState('');
  const [uf, setUf] = useState('');
  const [telefone, setTelefone] = useState('');
  const [email, setEmail] = useState('');

  // A Receita manda a razão social certa: ela vence o nome como o banco escreveu.
  const receita = consulta.data?.dados ?? null;
  useEffect(() => {
    if (!receita) return;
    if (receita.razao_social) setNome(receita.razao_social);
    setFantasia(receita.nome_fantasia ?? '');
    setCidade(receita.cidade ?? '');
    setUf(receita.uf ?? '');
    setTelefone(receita.telefone ?? '');
    setEmail(receita.email ?? '');
    if (receita.categoria_sugerida && !categoria) setCategoria(receita.categoria_sugerida);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [receita]);

  const salvar = () => {
    if (!nome.trim()) return;
    cadastrar.mutate({
      tipo,
      dados: {
        documento: doc || null, nome: nome.trim(), nome_fantasia: fantasia.trim() || null,
        tipo_de_favorecido: tipo === 'favorecido' ? tipoFav : null,
        categoria: tipo !== 'cliente' ? (categoria || null) : null,
        telefone: telefone || null, email: email || null, cidade: cidade || null, uf: uf || null,
        cep: receita?.cep ?? null, logradouro: receita?.logradouro ?? null, numero: receita?.numero ?? null,
        complemento: receita?.complemento ?? null, bairro: receita?.bairro ?? null,
        observacao: receita?.cnae_descricao ? `Atividade na Receita: ${receita.cnae_descricao}` : 'Cadastrado a partir do extrato',
      },
    }, { onSuccess: () => onFechar() });
  };

  const inativa = receita?.situacao && receita.situacao.toUpperCase() !== 'ATIVA';

  return (
    <Dialog open onOpenChange={(v) => { if (!v) onFechar(); }}>
      <DialogContent className="max-h-[90vh] max-w-lg overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Cadastrar a partir do extrato</DialogTitle>
          <DialogDescription>
            {doc.length === 14 ? `CNPJ ${doc.replace(/(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})/, '$1.$2.$3/$4-$5')}`
              : doc.length === 11 ? `CPF ${doc.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, '$1.$2.$3-$4')}` : 'Sem documento no extrato'}
            {consulta.isLoading && ' · consultando a Receita…'}
            {receita?.cnae_descricao && ` · ${receita.cnae_descricao}`}
          </DialogDescription>
        </DialogHeader>

        {consulta.data?.aviso && <p className="text-xs text-muted-foreground">{consulta.data.aviso}</p>}
        {inativa && (
          <p className="flex items-start gap-1.5 rounded-md border border-amber-500/40 bg-amber-500/5 p-2 text-xs">
            <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-amber-600" />
            A Receita informa situação <b>{receita?.situacao}</b> para este CNPJ.
          </p>
        )}

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div className="sm:col-span-2">
            <Label>Cadastrar como</Label>
            <Select value={tipo} onValueChange={(v) => setTipo(v as TipoDeCadastro)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="fornecedor">Fornecedor (empresa de quem compro)</SelectItem>
                <SelectItem value="favorecido">Favorecido (pessoa que recebe: sócio, funcionário, diarista)</SelectItem>
                <SelectItem value="cliente">Cliente (quem me paga)</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="sm:col-span-2">
            <Label htmlFor="cad-nome">{doc.length === 14 ? 'Razão social' : 'Nome'} *</Label>
            <Input id="cad-nome" value={nome} onChange={(e) => setNome(e.target.value)} />
          </div>
          {doc.length === 14 && (
            <div className="sm:col-span-2">
              <Label htmlFor="cad-fantasia">Nome fantasia</Label>
              <Input id="cad-fantasia" value={fantasia} onChange={(e) => setFantasia(e.target.value)} />
            </div>
          )}
          {tipo === 'favorecido' && (
            <div>
              <Label>Tipo</Label>
              <Select value={tipoFav} onValueChange={(v) => setTipoFav(v as TipoFavorecido)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {(Object.keys(ROTULO_TIPO) as TipoFavorecido[]).map((k) => (
                    <SelectItem key={k} value={k}>{ROTULO_TIPO[k]}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}
          {tipo !== 'cliente' && (
            <div className={tipo === 'favorecido' ? '' : 'sm:col-span-2'}>
              <Label>Categoria de despesa</Label>
              <CategoriaDespesaSelect valor={categoria} onMudar={setCategoria} className="h-10 text-sm" />
              {receita?.categoria_sugerida && (
                <p className="mt-0.5 text-[11px] text-muted-foreground">Sugerida pela atividade na Receita: {receita.categoria_sugerida}</p>
              )}
            </div>
          )}
          <div>
            <Label htmlFor="cad-cidade">Cidade</Label>
            <Input id="cad-cidade" value={cidade} onChange={(e) => setCidade(e.target.value)} />
          </div>
          <div>
            <Label htmlFor="cad-uf">UF</Label>
            <Input id="cad-uf" value={uf} maxLength={2} onChange={(e) => setUf(e.target.value.toUpperCase())} />
          </div>
          <div>
            <Label htmlFor="cad-tel">Telefone</Label>
            <Input id="cad-tel" value={telefone} onChange={(e) => setTelefone(e.target.value)} />
          </div>
          <div>
            <Label htmlFor="cad-email">E-mail</Label>
            <Input id="cad-email" value={email} onChange={(e) => setEmail(e.target.value)} />
          </div>
        </div>
        <p className="text-xs text-muted-foreground">
          Toda linha do Extrato com este documento passa a apontar para o cadastro. A categoria
          só entra onde o sistema não sabia nada ("Outras despesas" sem regra sua).
        </p>
        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={onFechar}>Cancelar</Button>
          <Button onClick={salvar} disabled={!nome.trim() || cadastrar.isPending}>
            {cadastrar.isPending ? 'Salvando…' : 'Cadastrar'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/**
 * O que a linha paga. Mostra a principal e as alternativas, e "lançar como novo". Quando a
 * linha pode já estar lançada, ninguém escolheu e o vínculo não é forte, aprovar fica
 * bloqueado — é o que impede a receita (ou a despesa) em dobro.
 */
export function VinculoDaLinha({
  vinculo, escolha, onEscolher, ocupado,
}: {
  vinculo: VinculoSugerido | null | undefined;
  escolha: EscolhaDeVinculo;
  onEscolher: (e: EscolhaDeVinculo) => void;
  ocupado: boolean;
}) {
  const { formatCurrency } = useI18n();
  const opcoes = opcoesDoVinculo(vinculo);
  if (opcoes.length === 0) return null;
  const efetivo = vinculoEfetivo(vinculo, escolha);
  const decidir = precisaDecidir(vinculo, escolha);
  const principal = opcoes[0];

  return (
    <div className={`mt-2 max-w-2xl rounded-md border p-2 text-xs ${decidir ? 'border-amber-500/50 bg-amber-500/5' : ''}`}>
      <p className="mb-1.5 flex items-center gap-1.5 font-medium">
        {principal.jaLancado
          ? <><AlertTriangle className="h-3.5 w-3.5 text-amber-600" /> Pode já estar lançado</>
          : <><Link2 className="h-3.5 w-3.5 text-primary" /> Parece pagar</>}
        {decidir && <span className="font-normal text-amber-700">— escolha antes de aprovar</span>}
      </p>
      <div role="radiogroup" className="space-y-1">
        {opcoes.map((o) => {
          const marcada = efetivo?.id === o.id;
          return (
            <label key={o.id} className={`flex cursor-pointer items-start gap-2 rounded px-1.5 py-1 hover:bg-muted/50 ${marcada ? 'bg-muted/60' : ''}`}>
              <input
                type="radio" className="mt-0.5" name={`vinculo-${principal.id}`} disabled={ocupado}
                checked={marcada} onChange={() => onEscolher({ id: o.id })}
              />
              <span className="min-w-0 flex-1">
                <span className="block break-words">
                  {o.jaLancado ? 'Casar com ' : o.converteOrcamento ? 'Registrar como ' : 'Casar com '}
                  <b>{o.rotulo.replace(/^Pagamento já lançado: /, '')}</b>
                  {' · '}{formatCurrency(o.valor)}
                  {o.clienteNome ? ` · ${o.clienteNome}` : ''}
                </span>
                <span className="block text-muted-foreground">
                  {o.confianca} pontos · {o.motivos.slice(0, 3).join(' · ')}
                  {o.converteOrcamento && ' · aprovar registra o sinal e converte o orçamento em OS'}
                  {o.tipo === 'service_order_balance' && ' · aprovar lança a receita ligada a esta OS'}
                </span>
              </span>
            </label>
          );
        })}
        <label className={`flex cursor-pointer items-center gap-2 rounded px-1.5 py-1 hover:bg-muted/50 ${!efetivo && escolha === 'nenhum' ? 'bg-muted/60' : ''}`}>
          <input
            type="radio" name={`vinculo-${principal.id}`} disabled={ocupado}
            checked={!efetivo && escolha === 'nenhum'} onChange={() => onEscolher('nenhum')}
          />
          <span>Nenhum destes — lançar como {principal.lado === 'payable' ? 'despesa' : 'receita'} nova</span>
        </label>
      </div>
    </div>
  );
}
