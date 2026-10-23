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
//
// Leva 8 (22/10/2026, "siga pelo recomendado"): na ENTRADA, "Cadastrar cliente" saiu. Quem pagou
// raramente é o cliente cadastrado (a empresa dele, o cônjuge, a marina), e o cadastro feito com
// os dados de quem pagou virava cliente duplicado. No lugar, a pergunta "De quem é este
// pagamento?" com três saídas — é de um cliente (e, se quem pagou não é ele, "Guardar … como
// quem paga por …"), é cliente novo, ou não é de cliente. O cliente que vem de um pagador
// conhecido ou do histórico de terceiro é sugestão âmbar com "Sim, é do X": a aprovação nunca o
// usa sozinha (clienteExigeSim).
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
import { useClientesParaReceita } from '@/hooks/use-payees';
import { ROTULO_DA_RELACAO } from '@/hooks/use-pagadores-do-cliente';
import { GuardarPagadorDialog, usePodeGuardarPagador } from '@/components/GuardarPagadorDialog';
import {
  clienteExigeSim, documentoNormalizado, nomeLimpo, nomeSemCpf, perguntaDeQuemEValida, RELACAO_DO_NOME_IDENTICO,
  RELACOES_DO_PAGADOR, ROTULO_DA_EVIDENCIA, situacaoDoClienteSugerido,
  type AnotacaoDoDono, type CandidatoDoPagamento, type Identificacao, type Reconhecimento, type TipoDeEvidencia,
} from '../../supabase/functions/_shared/banking/contraparte';
import { entradaSemCliente } from '../../supabase/functions/_shared/banking/entrada-sem-cliente';
import type { VinculoSugerido } from '../../supabase/functions/_shared/banking/vinculo';
import { AlertTriangle, HelpCircle, Link2, ShieldCheck, UserPlus } from 'lucide-react';

type TipoDoChip = 'fornecedor' | 'favorecido' | 'cliente';

/**
 * Prova forte (verde), média (neutra) ou que pede conferência (âmbar). O CLIENTE que pede o SIM
 * (pagador conhecido, histórico de terceiro, vínculo antigo) é âmbar: verde dizia "pode
 * aprovar", e a aprovação não usa esse cliente sem a resposta. Quando a anotação do dono já disse
 * este cliente (pedeSim false), a prova fica neutra: o SIM foi dado. Nas saídas, nada muda.
 */
function tomDaEvidencia(por: TipoDeEvidencia, tipo: TipoDoChip, pedeSim = true): string {
  if (tipo === 'cliente' && clienteExigeSim(por)) return pedeSim ? 'border-amber-500/50 text-amber-600' : 'text-muted-foreground';
  if (por === 'documento' || por === 'conta_bancaria' || por === 'regra' || por === 'historico') {
    return 'border-success/40 text-success';
  }
  // Nome cortado pelo banco pede "confira" como o antigo nome parecido: âmbar, não verde.
  if (por === 'nome_parecido' || por === 'nome_cortado') return 'border-amber-500/50 text-amber-600';
  return 'text-muted-foreground';
}

const ROTULO_DO_TIPO: Record<TipoDoChip, string> = {
  fornecedor: 'Fornecedor', favorecido: 'Favorecido', cliente: 'Cliente',
};

/** As categorias de entrada que não têm cliente (transferência entre contas, aporte de sócio). */
const CATEGORIAS_SEM_CLIENTE = ['Transferência entre contas', 'Aporte de sócio'].filter((c) => !!entradaSemCliente(c));

/** A relação do cliente da regra antiga em conflito (finance-review/identificacao.ts): não é prova de pagador. */
const RELACAO_DA_REGRA_ANTIGA = 'regra antiga';

/**
 * A frase da pergunta "de quem é?" com UM candidato só, pela relação dele (revisão de 23/10/2026, 4ª rodada). Um
 * candidato só aparece quando NÃO deu para ler os pagadores guardados (o pagador de um cliente só, lido, vira prova sem
 * pergunta): o nome idêntico, ou a regra antiga — "já foi guardado" ali seria falso. "Já foi guardado como quem paga
 * por X" só para uma relação de pagador (RELACOES_DO_PAGADOR).
 */
function fraseDoCandidatoUnico(c: CandidatoDoPagamento, quemPagou: string | null) {
  if (c.relacao === RELACAO_DO_NOME_IDENTICO) {
    return <>O nome é idêntico ao do cliente {c.nome}, mas não deu para conferir os pagadores guardados — confirme.</>;
  }
  if (c.relacao === RELACAO_DA_REGRA_ANTIGA) {
    return <>Uma regra antiga diz que este CPF/CNPJ é do cliente {c.nome}, mas não deu para conferir os pagadores guardados — confirme.</>;
  }
  if ((RELACOES_DO_PAGADOR as string[]).includes(c.relacao)) {
    return <><b>{quemPagou ?? 'Quem pagou'}</b> já foi guardado como quem paga por {c.nome}.</>;
  }
  return <>Pode ser do {c.nome} — confirme.</>;
}

function Chip({ tipo, r, pedeSim = true }: { tipo: TipoDoChip; r: Reconhecimento; pedeSim?: boolean }) {
  return (
    <Badge variant="outline" className={`max-w-full gap-1 text-xs font-normal ${tomDaEvidencia(r.por, tipo, pedeSim)}`} title={r.detalhe}>
      <ShieldCheck className="h-3 w-3 shrink-0" />
      <span className="truncate">
        {ROTULO_DO_TIPO[tipo]}: <b className="font-semibold">{r.nome}</b> · por {ROTULO_DA_EVIDENCIA[r.por] ?? r.por}
      </span>
    </Badge>
  );
}

/**
 * Quem é a contraparte, com a prova. Na SAÍDA, o botão de cadastrar quando nada bateu. Na ENTRADA, a pergunta "De
 * quem é este pagamento?" e o "Sim, é do X" do cliente que pede o SIM — nunca "Cadastrar cliente" com os dados de
 * quem pagou (leva 8, 22/10/2026).
 */
export function EvidenciaDaLinha({
  evidencia, ehReceita, categoria, ocupado, clienteId = null, clienteSugeridoId, onMudar, transacao = null,
}: {
  /** A evidência da proposta; `anotacao` é a anotação do dono aplicada à linha (_aplicar_anotacao grava {id, os_id}). */
  evidencia: (Partial<Identificacao> & { anotacao?: AnotacaoDoDono | null }) | null | undefined;
  ehReceita: boolean;
  categoria: string;
  ocupado: boolean;
  /** Entrada: o cliente que vale agora (clienteEscolhido) — a escolha da pessoa, ou o sugerido que não pede SIM. */
  clienteId?: string | null;
  /**
   * Entrada: o cliente SUGERIDO da proposta (suggested_client_id). Com ele, a linha decide pela mesma conta do servidor
   * (situacaoDoClienteSugerido): a anotação do dono que trocou o cliente vence a prova antiga; a pergunta "de quem é?"
   * que sobrou depois da anotação ou do cadastro não volta (perguntaDeQuemEValida); e o sugerido que ninguém disse ser o
   * da linha (anotação desfeita) não vale — falta escolher o cliente. Ausente: o sugerido é o da prova (cliente.id).
   */
  clienteSugeridoId?: string | null;
  /** Entrada: responder na própria linha ("Sim, é do X", um dos candidatos, "não é de cliente"). Sem ele, só mostra. */
  onMudar?: (c: { clientId?: string | null; category?: string }) => void;
  /** A linha do banco, para guardar quem pagou. O documento e o nome aqui são só para MOSTRAR: o banco relê a linha. */
  transacao?: { id: string | null; documento: string | null; nome: string | null } | null;
}) {
  const [cadastrando, setCadastrando] = useState<{ tipo: TipoDeCadastro; documento: string | null; nome: string | null } | null>(null);
  const [guardando, setGuardando] = useState(false);
  const podeGuardar = usePodeGuardarPagador();
  const { data: clientes = [] } = useClientesParaReceita(ehReceita && !!clienteId);
  if (!evidencia) return null;
  const { fornecedor, favorecido, cliente, outroCadastro, cadastrar, deQuemE, nomeConhecido } = evidencia;
  const anotacao = evidencia.anotacao ?? null;
  const sugeridoId = clienteSugeridoId === undefined ? (cliente?.id ?? null) : clienteSugeridoId;

  // Entrada que dispensa cliente (transferência, aporte): a pergunta "de quem é?" já foi respondida.
  const semCliente = ehReceita && !!entradaSemCliente(categoria);
  // Como fica o cliente sugerido na aprovação — a MESMA conta do servidor (situacaoDoClienteSugerido): "vale",
  // "pede_sim" ("Sim, é do X"), "escolher" (o sugerido não é o da prova e nenhuma anotação em vigor o disse: ninguém
  // resolveu de quem é — 4ª rodada) ou "sem_sugestao".
  const situacao = ehReceita && !semCliente ? situacaoDoClienteSugerido(sugeridoId, cliente, anotacao) : 'sem_sugestao';
  const faltaEscolher = situacao === 'escolher';
  // A ENTRADA nunca propõe cadastrar cliente com os dados de quem pagou. A linha antiga da fila que ainda traz o
  // `cadastrar` de cliente (até a varredura refazê-la, MOTOR_DA_FILA 3) vira a mesma pergunta. A pergunta que SOBROU
  // depois da anotação do dono ou do "É cliente novo" (a proposta já tem cliente) não vale (revisão de 23/10/2026) —
  // menos quando falta escolher: a anotação que a resolvia não vale mais, e a pergunta volta (como no assistente).
  const pergunta = ehReceita && !semCliente
    ? perguntaDeQuemEValida({ suggested_client_id: faltaEscolher ? null : sugeridoId, evidencia: { deQuemE, cadastrar, cliente } })
    : null;
  const cadastrarDaSaida = ehReceita ? null : cadastrar;
  // Cliente sugerido que pede o SIM: pagador conhecido, histórico de terceiro, vínculo antigo — a mesma conta do
  // servidor; a anotação do dono que disse o cliente é o SIM dele.
  const pedeSim = situacao === 'pede_sim' && !!cliente;
  // O sugerido não veio da prova do motor: a anotação do dono ("o Pix de 1.500 é da TSD") ou o cadastro pela linha o
  // trocou, e a prova antiga aponta OUTRO cliente — ou a pergunta "de quem é?" sobrou. A prova antiga não vira chip
  // de cliente (diria um cliente que a aprovação não vai usar).
  const provaDeOutro = ehReceita && !!cliente && !!sugeridoId && cliente.id !== sugeridoId;
  const perguntaSobrou = ehReceita && !cliente && !!sugeridoId && !pergunta
    && !!(deQuemE || (cadastrar && cadastrar.tipo === 'cliente'));
  const clienteDaProva = provaDeOutro ? null : cliente;
  // A prova pediria o SIM, mas a anotação do dono disse este mesmo cliente (a OS anotada é dele): o SIM foi dado.
  const anotacaoDisseAProva = ehReceita && !!cliente && !provaDeOutro && !!sugeridoId && clienteExigeSim(cliente.por)
    && !pedeSim && !!anotacao;
  // A linha está com o cliente que veio de fora do motor (ou que a anotação confirmou), e ninguém escolheu outro: diz
  // de onde veio. Só quando o sugerido VALE (a anotação em vigor o disse).
  const mostraDeOnde = situacao === 'vale' && clienteId === sugeridoId
    && (provaDeOutro || (perguntaSobrou && !!anotacao) || anotacaoDisseAProva);
  // Falta escolher e ninguém escolheu: diz por quê, sem oferecer cliente nenhum — nem o sugerido, nem o da prova
  // antiga (nunca "Sim, é do <prova>"). Com a pergunta "de quem é?" de volta, ela já pede a escolha.
  const avisoDeEscolha = faltaEscolher && !clienteId && !pergunta;

  if (!fornecedor && !favorecido && !cliente && !outroCadastro && !cadastrarDaSaida && !nomeConhecido && !pergunta
    && !mostraDeOnde && !avisoDeEscolha) return null;

  const candidatos = pergunta?.candidatos ?? [];
  // O nome como o banco escreveu, para comparar; para MOSTRAR, sem o CPF que o banco põe no nome ("12345678901-MARIA").
  const quemPagouDoBanco = transacao?.nome?.trim() || pergunta?.nome?.trim() || null;
  const quemPagou = nomeSemCpf(quemPagouDoBanco);
  const nomeDoCliente = !clienteId ? null
    : (cliente?.id === clienteId ? cliente.nome : null)
      ?? candidatos.find((c) => c.id === clienteId)?.nome
      ?? clientes.find((c) => c.id === clienteId)?.name
      ?? null;
  const doc = documentoNormalizado(transacao?.documento ?? pergunta?.documento);
  // "Guardar … como quem paga por …": o cliente foi escolhido (ou confirmado) e quem pagou não é ele pela prova —
  // nem pelo documento, nem por uma regra, nem já guardado. Só administrador e financeiro guardam.
  const clienteJaProvado = !!cliente && cliente.id === clienteId && cliente.por !== 'historico' && cliente.por !== 'vinculo';
  // O escolhido é um dos candidatos da pergunta: quem pagou já é pagador confirmado dele (CNPJ pela raiz) ou o
  // documento é o dele — guardar de novo só regravaria a relação. O "regra antiga" (a regra de outro cliente em
  // conflito com o pagador guardado) não é prova de pagador: ali guardar é o SIM que falta.
  const escolhidoJaProvado = candidatos.some((c) => c.id === clienteId && c.relacao !== 'regra antiga');
  const ofereceGuardar = ehReceita && !semCliente && podeGuardar && !!transacao?.id && !!clienteId
    && (doc.length === 11 || doc.length === 14) && !clienteJaProvado && !escolhidoJaProvado;
  const mesmoNome = !!quemPagouDoBanco && !!nomeDoCliente && nomeLimpo(quemPagouDoBanco) === nomeLimpo(nomeDoCliente);

  const temProva = !!(fornecedor || favorecido || clienteDaProva || nomeConhecido || outroCadastro || cadastrarDaSaida);

  return (
    <div className="mt-2 max-w-2xl space-y-1.5">
      {temProva && <div className="flex flex-wrap items-center gap-1.5">
        {fornecedor && <Chip tipo="fornecedor" r={fornecedor} />}
        {favorecido && <Chip tipo="favorecido" r={favorecido} />}
        {clienteDaProva && <Chip tipo="cliente" r={clienteDaProva} pedeSim={!anotacaoDisseAProva} />}
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
        {cadastrarDaSaida && (
          <Button size="sm" variant="outline" className="h-7 gap-1 text-xs" disabled={ocupado}
            onClick={() => setCadastrando(cadastrarDaSaida)}>
            <UserPlus className="h-3.5 w-3.5" />
            Cadastrar {cadastrarDaSaida.tipo}
          </Button>
        )}
      </div>}

      {/* O cliente da linha veio da anotação do dono (ou do cadastro pela linha), não da prova do motor — ou a anotação
          confirmou o da prova: vale ele, sem "Sim, é do <outro>". A prova antiga de outro cliente só aparece como o que
          o sistema TINHA sugerido. */}
      {mostraDeOnde && (
        <p className="text-xs text-muted-foreground" data-testid="cliente-de-fora-do-motor">
          {anotacao
            ? <>Você anotou: é do <b>{nomeDoCliente ?? 'cliente anotado'}</b>.</>
            : <>Esta linha já está com o cliente <b>{nomeDoCliente ?? 'escolhido'}</b>.</>}
          {provaDeOutro && cliente && (
            <>
              {' '}O sistema tinha sugerido {cliente.nome} ({ROTULO_DA_EVIDENCIA[cliente.por] ?? cliente.por})
              {anotacao ? ' — vale a sua anotação.' : '.'}
            </>
          )}
        </p>
      )}

      {/* Ninguém disse de quem é: o sugerido não veio da prova do motor nem de uma anotação em vigor (a que o pôs foi
          desfeita). A mesma recusa do servidor (PEDIDO_DE_ESCOLHA_DO_CLIENTE) — e nenhum cliente oferecido. */}
      {avisoDeEscolha && (
        <div className="flex items-start gap-1.5 rounded-md border border-amber-500/40 bg-amber-500/5 p-2 text-xs"
          data-testid="cliente-falta-escolher">
          <HelpCircle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-amber-600" />
          <span className="min-w-0">
            <b>De quem é este pagamento?</b> A sugestão da fila não veio da prova do sistema nem de uma anotação sua em
            vigor (a anotação pode ter sido desfeita). Escolha o cliente em "De qual cliente veio?".
          </span>
        </div>
      )}

      {/* Sugestão que pede o SIM: a prova escrita e a resposta na própria linha. */}
      {pedeSim && cliente && (
        clienteId === cliente.id ? (
          <p className="text-xs text-muted-foreground">
            Você confirmou: é do <b>{cliente.nome}</b>.{' '}
            {onMudar && (
              <button type="button" className="underline" disabled={ocupado}
                onClick={() => onMudar({ clientId: undefined })}>desfazer</button>
            )}
          </p>
        ) : !clienteId ? (
          <div className="flex flex-wrap items-center gap-2 rounded-md border border-amber-500/40 bg-amber-500/5 p-2 text-xs"
            data-testid="cliente-pede-sim">
            <span className="min-w-0">{cliente.detalhe}. É dele?</span>
            {onMudar && (
              <Button size="sm" variant="outline" className="h-auto min-h-7 whitespace-normal text-left text-xs" disabled={ocupado}
                onClick={() => onMudar({ clientId: cliente.id })}>
                Sim, é do {cliente.nome}
              </Button>
            )}
            <span className="text-muted-foreground">Se não for, escolha o cliente em "De qual cliente veio?".</span>
          </div>
        ) : null
      )}

      {/* A pergunta "De quem é este pagamento?" — três saídas, nenhuma com os dados de quem pagou num cadastro. */}
      {pergunta && (
        clienteId ? (
          <p className="text-xs text-muted-foreground">
            De quem é este pagamento: <b>{nomeDoCliente ?? 'o cliente escolhido'}</b> (escolhido por você).
          </p>
        ) : (
          <div className="space-y-1.5 rounded-md border border-primary/30 bg-primary/5 p-2 text-xs" data-testid="de-quem-e">
            <p className="flex items-center gap-1.5 font-medium">
              <HelpCircle className="h-3.5 w-3.5 shrink-0 text-primary" />
              De quem é este pagamento?
            </p>
            <p className="text-muted-foreground">
              {candidatos.length > 1
                ? <><b>{quemPagou ?? 'Quem pagou'}</b> paga por mais de um cliente — de qual é este?</>
                : candidatos.length === 1
                  ? fraseDoCandidatoUnico(candidatos[0], quemPagou)
                  : <><b>{quemPagou ?? 'Quem pagou'}</b> ainda não pagou por nenhum cliente.</>}
            </p>
            {candidatos.length > 0 && onMudar && (
              <div className="flex flex-wrap gap-1.5">
                {candidatos.map((c) => (
                  <Button key={c.id} size="sm" variant="outline" className="h-auto min-h-7 whitespace-normal text-left text-xs" disabled={ocupado}
                    onClick={() => onMudar({ clientId: c.id })}>
                    É do {c.nome}{c.relacao ? ` (${ROTULO_DA_RELACAO[c.relacao as keyof typeof ROTULO_DA_RELACAO] ?? c.relacao})` : ''}
                  </Button>
                ))}
              </div>
            )}
            <ul className="space-y-1">
              <li>
                <b>É de um cliente cadastrado:</b> escolha em "De qual cliente veio?". Se quem pagou não for o próprio
                cliente, dá para guardá-lo como quem paga por ele.
              </li>
              <li className="flex flex-wrap items-center gap-1.5">
                <Button size="sm" variant="outline" className="h-auto min-h-7 gap-1 whitespace-normal text-left text-xs" disabled={ocupado}
                  onClick={() => setCadastrando({ tipo: 'cliente', documento: pergunta.documento, nome: pergunta.nome })}>
                  <UserPlus className="h-3.5 w-3.5" />
                  É cliente novo (quem pagou é o próprio cliente)
                </Button>
              </li>
              {onMudar && CATEGORIAS_SEM_CLIENTE.length > 0 && (
                <li className="flex flex-wrap items-center gap-1.5">
                  <span>Não é de cliente:</span>
                  {CATEGORIAS_SEM_CLIENTE.map((c) => (
                    <Button key={c} size="sm" variant="ghost" className="h-7 text-xs underline" disabled={ocupado}
                      onClick={() => onMudar({ category: c })}>
                      {c}
                    </Button>
                  ))}
                </li>
              )}
            </ul>
          </div>
        )
      )}

      {ofereceGuardar && (
        <p className="text-xs">
          <button type="button" className="text-primary underline" disabled={ocupado} onClick={() => setGuardando(true)}>
            Guardar {quemPagou ?? 'quem pagou'} como quem paga por {nomeDoCliente ?? 'este cliente'}
          </button>
          {mesmoNome && (
            <span className="text-muted-foreground">
              {' '}· Mesmo nome do cliente: se for ele mesmo, complete o CPF/CNPJ na ficha dele em vez de guardar.
            </span>
          )}
        </p>
      )}

      {cadastrando && (
        <CadastrarContraparteDialog
          sugestao={cadastrando}
          categoriaAtual={ehReceita ? null : categoria}
          onFechar={() => setCadastrando(null)}
        />
      )}
      {guardando && transacao?.id && clienteId && (
        <GuardarPagadorDialog
          pedido={{
            clientId: clienteId, clienteNome: nomeDoCliente, bankTransactionId: transacao.id,
            pagadorNome: quemPagou, pagadorDocumento: doc, origem: 'fila',
          }}
          onFechar={() => setGuardando(false)}
        />
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
  vinculo, escolha, onEscolher, ocupado, semReceita = false,
}: {
  vinculo: VinculoSugerido | null | undefined;
  escolha: EscolhaDeVinculo;
  onEscolher: (e: EscolhaDeVinculo) => void;
  ocupado: boolean;
  /** Entrada classificada como transferência ou aporte: "nenhum destes" não lança receita. */
  semReceita?: boolean;
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
          <span>
            {semReceita
              ? 'Nenhum destes — sai sem receita (transferência ou aporte)'
              : `Nenhum destes — lançar como ${principal.lado === 'payable' ? 'despesa' : 'receita'} nova`}
          </span>
        </label>
      </div>
    </div>
  );
}
