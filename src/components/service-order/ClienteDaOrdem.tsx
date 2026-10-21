/* Cliente da OS/orçamento (pedido do dono, 20/10/2026; proteção e rótulos em 21/10/2026).
   Sem cliente, a busca. Com cliente, só a FICHA — a busca some, para um clique perdido não trocar
   o cliente sem ninguém perceber; trocar exige o "Trocar" (na linha do rótulo, longe do "Editar
   cadastro", que é outra coisa: muda o cadastro, não quem é o cliente desta OS). Na troca que tira
   algo já gravado (embarcação, solicitante), a confirmação diz o que sai. A ficha mostra cada dado
   com o rótulo em cima ("CPF", "Telefone / WhatsApp"…), o que falta para a nota e o saldo. */
import { useEffect, useId, useMemo, useRef, useState, type ReactNode, type RefObject } from 'react';
import { flushSync } from 'react-dom';
import { Link } from 'react-router-dom';
import { AlertTriangle, BellOff, ExternalLink, MessageCircle, Pencil, Plus } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Command, CommandInput, CommandItem, CommandList } from '@/components/ui/command';
import { Skeleton } from '@/components/ui/skeleton';
import { ClientFormDialog } from '@/components/ClientFormDialog';
import { useConfirmacao } from '@/components/Confirmacao';
import { Dado, DadosDaFicha } from '@/components/DadosDaFicha';
import { filtrarClientes } from '@/lib/busca-cliente';
import { enderecoEmUmaLinha, faltasParaNota, hrefTelefone } from '@/lib/ficha-cliente';
import { descricaoDaTroca, temPerda, tituloDaTroca, type Perdas } from '@/lib/troca-de-cliente';
import { normalizePhoneE164 } from '@/lib/masks';
import { useClientesRecentes, useSaldoEmAberto } from '@/hooks/use-ficha-cliente';
import type { Client } from '@/hooks/use-clients';

interface Props {
  value: string;
  onChange: (clientId: string, clientName: string) => void;
  clients: Client[] | undefined;
  /** O rótulo do campo ("Cliente *"). */
  rotulo: string;
  /** OS travada: sem troca; a ficha e o "Editar cadastro" ficam. */
  disabled?: boolean;
  /** Por que não dá para trocar (orçamento que reúne outros): aparece no lugar do "Trocar".
      `true` só esconde o "Trocar" (ainda conferindo o agrupamento). */
  semTroca?: string | true;
  /** OS/orçamento já gravado. Só aí trocar com perda pede confirmação: em OS nova a correção é livre. */
  ordemSalva?: boolean;
  /** O que sai da OS se o cliente mudar. */
  perdas?: Perdas;
  documento?: 'OS' | 'orçamento';
}

/* "Trocar" e "Cancelar" ocupam o mesmo lugar na linha do rótulo. Texto em cor de texto e
   sublinhado (o dourado do tema dá 2,4:1, abaixo do mínimo); 44 px de toque onde o ponteiro é
   grosso, sem engordar a linha (margem negativa); relative/z-10 para o alvo ficar por cima da
   ficha logo abaixo. */
const BOTAO_DO_ROTULO =
  'relative z-10 -my-3 h-11 px-1 text-foreground underline underline-offset-2 hover:text-foreground ' +
  '[@media(pointer:fine)]:my-0 [@media(pointer:fine)]:h-auto';

export function ClienteDaOrdem({
  value, onChange, clients, rotulo, disabled, semTroca, ordemSalva, perdas, documento = 'OS',
}: Props) {
  const [dialogo, setDialogo] = useState<'novo' | 'editar' | null>(null);
  const [nomeDoNovo, setNomeDoNovo] = useState('');
  // Cadastrado agora: até a lista recarregar ele ainda não está nela — esqueleto, não o
  // aviso de "não está na lista".
  const [recemCriado, setRecemCriado] = useState<string | null>(null);
  const [trocando, setTrocando] = useState(false);
  const [anuncio, setAnuncio] = useState('');
  const idRotulo = useId();
  const blocoRef = useRef<HTMLDivElement>(null);
  const buscaRef = useRef<HTMLInputElement>(null);
  const trocarRef = useRef<HTMLButtonElement>(null);
  const perguntandoRef = useRef(false);
  const anuncioPendenteRef = useRef<string | null>(null);
  // Lido na hora de confirmar: a trava (OS travada, agrupado) pode chegar com o diálogo aberto.
  const travadoRef = useRef(false);
  travadoRef.current = !!disabled || !!semTroca;
  const { pedir, dialogo: confirmacao } = useConfirmacao();

  const selecionado = clients?.find((c) => c.id === value) ?? null;
  // A OS pode travar (ou o agrupamento terminar de carregar) com a troca aberta: aí ela fecha.
  const emTroca = trocando && !disabled && !semTroca;
  const nomeAtual = selecionado?.name ?? 'o cliente atual';
  const comBusca = !disabled && (!value || emTroca);
  const podeTrocar = !disabled && !!value && !semTroca && !emTroca;
  const pedeConfirmacao = !!value && !!ordemSalva && temPerda(perdas);

  const focarTrocar = () => setTimeout(() => trocarRef.current?.focus({ preventScroll: true }), 0);
  const voltarAoCartao = () => { setTrocando(false); focarTrocar(); };

  // Sair do modo troca tocando FORA do bloco — e não no blur: os diálogos do próprio fluxo (a
  // confirmação, o cadastro novo) abrem fora dele, e o "OK" do teclado do iPhone dispara blur.
  // No toque, espera o click (como o Radix): pointerdown dispara no começo de uma rolagem.
  useEffect(() => {
    if (!emTroca || dialogo) return;
    const ehFora = (alvo: Element | null) =>
      !!alvo && !blocoRef.current?.contains(alvo) && !perguntandoRef.current
      && !alvo.closest('[role="dialog"],[role="alertdialog"]');
    let aoClicar: ((e: MouseEvent) => void) | null = null;
    const fora = (e: PointerEvent) => {
      const alvo = e.target as Element | null;
      if (!ehFora(alvo)) return;
      if (e.pointerType === 'touch') {
        if (aoClicar) document.removeEventListener('click', aoClicar);
        aoClicar = (c: MouseEvent) => { if (ehFora(c.target as Element | null)) setTrocando(false); };
        document.addEventListener('click', aoClicar, { once: true });
        return;
      }
      setTrocando(false);
    };
    document.addEventListener('pointerdown', fora);
    return () => {
      document.removeEventListener('pointerdown', fora);
      if (aoClicar) document.removeEventListener('click', aoClicar);
    };
  }, [emTroca, dialogo]);

  /** `depoisDoDialogo`: o foco e o anúncio esperam o diálogo fechar (aoFechar), senão o leitor de
      tela não ouve — a página fica escondida dele enquanto o diálogo está aberto. */
  const aplicar = (id: string, nome: string, depoisDoDialogo = false) => {
    const texto = value ? `Cliente trocado para ${nome}.` : `Cliente escolhido: ${nome}.`;
    setTrocando(false);
    onChange(id, nome);
    if (depoisDoDialogo) { anuncioPendenteRef.current = texto; return; }
    setAnuncio(texto);
    focarTrocar();
  };

  const perguntar = (para: string | null, seguir: () => void) => {
    perguntandoRef.current = true;
    pedir({
      titulo: tituloDaTroca(documento),
      descricao: descricaoDaTroca(selecionado?.name ?? null, para, perdas ?? {}),
      confirmar: 'Trocar cliente',
      voltar: 'Manter o cliente atual',
      acao: () => {
        perguntandoRef.current = false;
        if (travadoRef.current) { setTrocando(false); return; }
        seguir();
      },
      aoVoltar: () => { perguntandoRef.current = false; setTrocando(false); },
      aoFechar: () => {
        // sem o Trocar na tela (seguiu para o cadastro novo), o foco fica com quem o pegar
        trocarRef.current?.focus({ preventScroll: true });
        if (anuncioPendenteRef.current) { setAnuncio(anuncioPendenteRef.current); anuncioPendenteRef.current = null; }
      },
    });
  };

  const escolher = (c: Client) => {
    if (semTroca && value) return;
    // Escolher o mesmo cliente de novo não é troca: não apaga embarcação e solicitante.
    if (c.id === value) { voltarAoCartao(); return; }
    if (pedeConfirmacao) perguntar(c.name, () => aplicar(c.id, c.name, true));
    else aplicar(c.id, c.name);
  };

  const cadastrarNovo = (termo: string) => {
    const abrir = () => { setNomeDoNovo(termo); setDialogo('novo'); };
    // Com perda, pergunta ANTES de cadastrar: desistir depois deixaria um cadastro órfão.
    if (pedeConfirmacao) perguntar(null, abrir);
    else abrir();
  };

  const comecarTroca = () => {
    // flushSync: a busca precisa existir ainda dentro do toque, senão o iPhone não abre o teclado.
    flushSync(() => setTrocando(true));
    buscaRef.current?.focus();
  };

  return (
    <div ref={blocoRef} role="group" aria-labelledby={idRotulo} className="flex min-w-0 flex-col gap-1.5">
      <div className="flex min-h-5 items-center justify-between gap-2">
        <Label id={idRotulo}>{rotulo}</Label>
        {podeTrocar && (
          <Button
            ref={trocarRef}
            type="button"
            variant="link"
            size="sm"
            className={BOTAO_DO_ROTULO}
            onClick={comecarTroca}
            aria-label={`Trocar cliente (atual: ${nomeAtual})`}
          >
            Trocar
          </Button>
        )}
        {emTroca && (
          <Button
            type="button"
            variant="link"
            size="sm"
            className={BOTAO_DO_ROTULO}
            onClick={voltarAoCartao}
            aria-label={`Cancelar a troca e manter ${nomeAtual}`}
          >
            Cancelar
          </Button>
        )}
      </div>

      {typeof semTroca === 'string' && value && !disabled && <p className="text-xs text-muted-foreground">{semTroca}</p>}

      {emTroca && (
        <p className="text-xs text-muted-foreground">
          Trocar <span className="font-medium text-foreground">{nomeAtual}</span> por:
        </p>
      )}

      {comBusca && (
        <BuscaCliente
          clients={clients}
          atualId={value || null}
          inputRef={buscaRef}
          onEscolher={escolher}
          onNovo={cadastrarNovo}
          onSair={emTroca ? voltarAoCartao : undefined}
        />
      )}

      {!emTroca && value && (
        selecionado ? (
          <FichaDoCliente cliente={selecionado} onEditar={() => setDialogo('editar')} />
        ) : !clients || value === recemCriado ? (
          <Skeleton className="h-24 w-full rounded-lg" />
        ) : (
          <p className="rounded-lg border border-dashed p-3 text-sm text-muted-foreground">
            O cliente desta OS não está na lista de cadastros.
          </p>
        )
      )}
      {disabled && !value && <p className="text-sm text-muted-foreground">—</p>}

      {/* Sempre montada (vazia até a troca): região viva montada já com texto costuma não ser lida. */}
      <p className="sr-only" role="status" aria-live="polite">{anuncio}</p>

      <ClientFormDialog
        open={dialogo !== null}
        onOpenChange={(aberto) => { if (!aberto) setDialogo(null); }}
        client={dialogo === 'editar' ? selecionado : null}
        initialName={nomeDoNovo}
        // O cadastro fecha com animação: foco e anúncio esperam ele sumir (onCloseAutoFocus).
        onCreated={(novo) => { setRecemCriado(novo.id); aplicar(novo.id, novo.name, true); }}
        onCloseAutoFocus={(e) => {
          const texto = anuncioPendenteRef.current;
          if (!texto) return; // fechou sem criar: o Radix devolve o foco a quem abriu
          e.preventDefault();
          anuncioPendenteRef.current = null;
          trocarRef.current?.focus({ preventScroll: true });
          setAnuncio(texto);
        }}
      />
      {confirmacao}
    </div>
  );
}

/* ------------------------------------------------------------------ busca */

function BuscaCliente({
  clients, atualId, inputRef, onEscolher, onNovo, onSair,
}: {
  clients: Client[] | undefined;
  /** O cliente da OS (no modo troca): fora dos recentes e marcado na busca. */
  atualId: string | null;
  inputRef: RefObject<HTMLInputElement>;
  onEscolher: (c: Client) => void;
  onNovo: (termo: string) => void;
  /** Esc com a lista fechada e o campo vazio: sai do modo troca. */
  onSair?: () => void;
}) {
  const [termo, setTermo] = useState('');
  // Começa FECHADA e abre ao digitar, com a seta ou com clique: lista aberta destaca o primeiro
  // item, e um Enter dado por hábito trocaria o cliente.
  const [aberta, setAberta] = useState(false);
  const resultados = useMemo(() => filtrarClientes(clients, termo), [clients, termo]);
  const curto = termo.trim().length < 3;
  // Antes de digitar: os clientes das últimas OS no topo (quase sempre é um deles), depois o resto.
  const { data: idsRecentes } = useClientesRecentes();
  const recentes = useMemo(() => {
    const porId = new Map((clients ?? []).filter((c) => c.active).map((c) => [c.id, c]));
    return (idsRecentes ?? [])
      .filter((id) => id !== atualId)
      .map((id) => porId.get(id))
      .filter((c): c is Client => !!c);
  }, [clients, idsRecentes, atualId]);
  const lista = curto && recentes.length
    ? resultados.filter((c) => !recentes.some((r) => r.id === c.id))
    : resultados;

  const fechar = () => { setAberta(false); setTermo(''); };
  const escolher = (c: Client) => { onEscolher(c); fechar(); };

  return (
    <Command
      shouldFilter={false}
      label="Buscar cliente"
      // A lista abre por baixo do campo e por cima da ficha; o overflow do Command a cortaria.
      className="relative overflow-visible bg-transparent [&_[cmdk-input-wrapper]]:border-b-0"
      onKeyDown={(e) => {
        if (e.key === 'Escape') {
          if (aberta || termo) fechar();
          else onSair?.();
        }
        if (e.key === 'ArrowDown' && !aberta) setAberta(true);
      }}
    >
      <div className="rounded-md border border-input bg-background ring-offset-background focus-within:ring-2 focus-within:ring-ring focus-within:ring-offset-2">
        <CommandInput
          ref={inputRef}
          value={termo}
          onValueChange={(v) => { setTermo(v); setAberta(true); }}
          // Clique abre; foco por Tab não — senão a lista cobre a ficha a cada passagem.
          onClick={() => setAberta(true)}
          // Só fecha a lista: o "OK" do teclado do iPhone tira o foco, e apagar o que foi
          // digitado aí seria perder a busca.
          onBlur={() => setAberta(false)}
          placeholder="Nome, CPF/CNPJ, telefone ou e-mail"
          aria-required
          // 16 px no celular: com menos o iPhone dá zoom ao focar.
          className="h-11 text-base sm:h-10 md:text-sm"
        />
      </div>

      {aberta && (
        <CommandList
          className="absolute left-0 right-0 top-full z-50 mt-1 rounded-md border bg-popover p-1 text-popover-foreground shadow-md"
          // Sem isso o clique num item tira o foco do campo, o onBlur fecha a lista e o
          // clique cai no vazio.
          onMouseDown={(e) => e.preventDefault()}
        >
          {curto && (
            <p className="px-2 py-1.5 text-xs text-muted-foreground">
              Digite 3 letras do nome, ou números do CPF/CNPJ ou do telefone.
            </p>
          )}
          {!curto && resultados.length === 0 && (
            <p className="px-2 py-3 text-center text-sm text-muted-foreground">
              {clients ? 'Nenhum cliente encontrado.' : 'Carregando clientes…'}
            </p>
          )}
          {curto && recentes.length > 0 && (
            <>
              <p className="px-2 pb-1 pt-2 text-xs font-medium text-muted-foreground">Últimos clientes</p>
              {/* value com prefixo: o mesmo cliente não pode ter dois itens com o mesmo value no cmdk. */}
              {recentes.map((c) => <ItemCliente key={`r-${c.id}`} valor={`recente-${c.id}`} cliente={c} onEscolher={escolher} />)}
              {lista.length > 0 && <p className="px-2 pb-1 pt-2 text-xs font-medium text-muted-foreground">Todos</p>}
            </>
          )}
          {lista.map((c) => (
            <ItemCliente key={c.id} valor={c.id} cliente={c} atual={c.id === atualId} onEscolher={escolher} />
          ))}
          <CommandItem
            value="__novo_cliente__"
            onSelect={() => { const t = termo.trim(); fechar(); onNovo(t); }}
            className="mt-1 min-h-11 cursor-pointer border-t font-medium sm:min-h-0"
          >
            <Plus className="mr-2 h-4 w-4" aria-hidden />
            {curto ? 'Novo cliente' : `Cadastrar "${termo.trim()}"`}
          </CommandItem>
        </CommandList>
      )}
    </Command>
  );
}

function ItemCliente({ cliente: c, valor, atual, onEscolher }: {
  cliente: Client; valor: string; atual?: boolean; onEscolher: (c: Client) => void;
}) {
  const detalhe = [atual ? 'Cliente atual' : null, c.cpf_cnpj, c.whatsapp || c.phone, [c.city, c.state].filter(Boolean).join('/')]
    .filter(Boolean).join(' · ');
  return (
    <CommandItem value={valor} onSelect={() => onEscolher(c)} className="group min-h-11 cursor-pointer sm:min-h-0">
      <div className="min-w-0">
        <p className="truncate text-sm">{c.name}</p>
        {/* No item destacado o fundo muda: o cinza do detalhe some nele (2,2:1), então herda a cor. */}
        {detalhe && <p className="truncate text-xs text-muted-foreground group-data-[selected=true]:text-current">{detalhe}</p>}
      </div>
    </CommandItem>
  );
}

/* ------------------------------------------------------------------ ficha */

const brl = (v: number) => new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

/** CPF, CNPJ ou os dois: pelo número quando ele está completo; sem número, pelo tipo do cadastro. */
function rotuloDoDocumento(c: Client): string {
  const n = (c.cpf_cnpj ?? '').replace(/\D/g, '').length;
  if (n === 14) return 'CNPJ';
  if (n === 11) return 'CPF';
  if (n) return 'CPF/CNPJ';
  return c.type === 'company' ? 'CNPJ' : 'CPF';
}

function FichaDoCliente({ cliente: c, onEditar }: { cliente: Client; onEditar: () => void }) {
  const zap = c.whatsapp || c.phone;
  const zapE164 = normalizePhoneE164(zap);
  // Telefone e WhatsApp iguais (o comum) aparecem uma vez só.
  const foneSeparado = c.phone && normalizePhoneE164(c.phone) !== zapE164 ? c.phone : null;
  const endereco = enderecoEmUmaLinha(c);
  const faltas = faltasParaNota(c);
  // Só admin/financeiro (o hook nem consulta para os outros cargos); erro = a linha não aparece.
  const { data: saldo } = useSaldoEmAberto(c.id);

  return (
    <div role="group" aria-label="Dados do cliente" className="space-y-3 rounded-lg border bg-muted/30 p-3 text-sm">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="break-words font-semibold leading-tight">{c.name}</p>
          <p className="mt-0.5 text-xs text-muted-foreground">
            {c.type === 'company' ? 'Pessoa jurídica' : 'Pessoa física'}
            {!c.active && ' · cadastro inativo'}
          </p>
        </div>
        {/* "Editar cadastro" por extenso também no celular: "Editar" sozinho, colado ao nome,
            parece o caminho para trocar o cliente — e renomearia o cadastro. */}
        <Button type="button" variant="outline" size="sm" className="h-11 shrink-0 gap-1 px-2.5 sm:h-8" onClick={onEditar}>
          <Pencil className="h-3.5 w-3.5" aria-hidden /> Editar cadastro
        </Button>
      </div>

      <DadosDaFicha>
        <Dado rotulo={rotuloDoDocumento(c)}>{c.cpf_cnpj}</Dado>
        <Dado rotulo="Telefone / WhatsApp">
          {zap && (
            <span className="flex flex-wrap items-center gap-x-3">
              <a href={hrefTelefone(zap)} className="inline-flex min-h-6 items-center hover:underline">{zap}</a>
              {zapE164.length >= 12 && (
                <a
                  href={`https://wa.me/${zapE164}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex min-h-6 items-center gap-1 text-xs underline underline-offset-2"
                  aria-label="Abrir conversa no WhatsApp"
                >
                  <MessageCircle className="h-3.5 w-3.5" aria-hidden /> WhatsApp
                </a>
              )}
            </span>
          )}
        </Dado>
        {foneSeparado && (
          <Dado rotulo="Outro telefone">
            <a href={hrefTelefone(foneSeparado)} className="inline-flex min-h-6 items-center hover:underline">{foneSeparado}</a>
          </Dado>
        )}
        {c.email && (
          <Dado rotulo="E-mail" largo>
            <a href={`mailto:${c.email}`} className="break-all hover:underline">{c.email}</a>
          </Dado>
        )}
        <Dado rotulo="Endereço" largo>
          {endereco && <>{endereco}{c.postal_code && <span className="text-muted-foreground"> · CEP {c.postal_code}</span>}</>}
        </Dado>
        {c.notes && (
          <Dado rotulo="Observações do cadastro" largo>
            <span className="line-clamp-3 whitespace-pre-line" title={c.notes}>{c.notes}</span>
          </Dado>
        )}
        {saldo && saldo.emAberto > 0.009 && (
          <Dado rotulo="Em aberto" largo>
            {brl(saldo.emAberto)}
            {saldo.vencidos > 0 && (
              <span className="font-medium text-amber-700 dark:text-amber-400">
                {` · ${saldo.vencidos} vencido${saldo.vencidos > 1 ? 's' : ''} (${brl(saldo.valorVencido)})`}
              </span>
            )}
          </Dado>
        )}
      </DadosDaFicha>

      {/* Os avisos dizem o que deixa de funcionar, não só o campo vazio — e o conserto está
          no botão aí em cima. */}
      {(!zap || c.opt_out_whatsapp || faltas.length > 0) && (
        <ul className="space-y-1 border-t pt-2 text-xs text-amber-700 dark:text-amber-400">
          {!zap && (
            <Aviso icone={AlertTriangle}>Sem telefone: o orçamento e os avisos não chegam pelo WhatsApp.</Aviso>
          )}
          {c.opt_out_whatsapp && (
            <Aviso icone={BellOff}>Pediu para não receber mensagens pelo WhatsApp.</Aviso>
          )}
          {faltas.length > 0 && (
            <Aviso icone={AlertTriangle}>Para a nota fiscal falta: {faltas.join(', ')}.</Aviso>
          )}
        </ul>
      )}

      {/* Em outra aba: a OS pode ter alteração ainda não salva. */}
      <Link
        to={`/v2/clients/${c.id}`}
        target="_blank"
        rel="noopener noreferrer"
        className="inline-flex min-h-6 items-center gap-1 text-xs text-muted-foreground hover:text-foreground hover:underline"
      >
        Histórico e financeiro do cliente <ExternalLink className="h-3 w-3" aria-hidden />
      </Link>
    </div>
  );
}

function Aviso({ icone: Icone, children }: { icone: typeof AlertTriangle; children: ReactNode }) {
  return (
    <li className="flex items-start gap-1.5">
      <Icone className="mt-0.5 h-3.5 w-3.5 shrink-0" aria-hidden />
      <span>{children}</span>
    </li>
  );
}
