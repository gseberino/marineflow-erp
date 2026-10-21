/* Cliente da OS/orçamento: a busca em cima, a ficha embaixo (pedido do dono, 20/10/2026).
   Antes era um campo só — o botão com o nome abria a busca — e a tela não mostrava nada do
   cliente além do nome. Agora a ficha traz o contato, o endereço, as observações do cadastro,
   o que falta para a nota e o "Editar cadastro", sem sair da OS. */
import { useMemo, useState, type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import {
  AlertTriangle, BellOff, ExternalLink, IdCard, Mail, MapPin, MessageCircle, Pencil, Phone, Plus, StickyNote, Wallet,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Command, CommandInput, CommandItem, CommandList } from '@/components/ui/command';
import { Skeleton } from '@/components/ui/skeleton';
import { ClientFormDialog } from '@/components/ClientFormDialog';
import { filtrarClientes } from '@/lib/busca-cliente';
import { enderecoEmUmaLinha, faltasParaNota, hrefTelefone } from '@/lib/ficha-cliente';
import { normalizePhoneE164 } from '@/lib/masks';
import { useClientesRecentes, useSaldoEmAberto } from '@/hooks/use-ficha-cliente';
import type { Client } from '@/hooks/use-clients';

interface Props {
  value: string;
  onChange: (clientId: string, clientName: string) => void;
  clients: Client[] | undefined;
  /** OS travada: a busca some (não troca o cliente), a ficha e o editar cadastro ficam. */
  disabled?: boolean;
}

export function ClienteDaOrdem({ value, onChange, clients, disabled }: Props) {
  const [dialogo, setDialogo] = useState<'novo' | 'editar' | null>(null);
  const [nomeDoNovo, setNomeDoNovo] = useState('');
  // Cadastrado agora: até a lista recarregar ele ainda não está nela — esqueleto, não o
  // aviso de "não está na lista".
  const [recemCriado, setRecemCriado] = useState<string | null>(null);
  const selecionado = clients?.find((c) => c.id === value) ?? null;

  return (
    <div className="space-y-2">
      {!disabled && (
        <BuscaCliente
          clients={clients}
          temSelecionado={!!selecionado}
          onEscolher={(c) => {
            // Escolher o mesmo cliente de novo não é troca: não apaga embarcação e solicitante.
            if (c.id !== value) onChange(c.id, c.name);
          }}
          onNovo={(termo) => { setNomeDoNovo(termo); setDialogo('novo'); }}
        />
      )}

      {selecionado ? (
        <FichaDoCliente cliente={selecionado} onEditar={() => setDialogo('editar')} />
      ) : value && (!clients || value === recemCriado) ? (
        <Skeleton className="h-24 w-full rounded-lg" />
      ) : value ? (
        <p className="rounded-lg border border-dashed p-3 text-sm text-muted-foreground">
          O cliente desta OS não está na lista de cadastros.
        </p>
      ) : disabled ? (
        <p className="text-sm text-muted-foreground">—</p>
      ) : null}

      <ClientFormDialog
        open={dialogo !== null}
        onOpenChange={(aberto) => { if (!aberto) setDialogo(null); }}
        client={dialogo === 'editar' ? selecionado : null}
        initialName={nomeDoNovo}
        onCreated={(novo) => { setRecemCriado(novo.id); onChange(novo.id, novo.name); }}
      />
    </div>
  );
}

/* ------------------------------------------------------------------ busca */

function BuscaCliente({
  clients, temSelecionado, onEscolher, onNovo,
}: {
  clients: Client[] | undefined;
  temSelecionado: boolean;
  onEscolher: (c: Client) => void;
  onNovo: (termo: string) => void;
}) {
  const [termo, setTermo] = useState('');
  const [aberta, setAberta] = useState(false);
  const resultados = useMemo(() => filtrarClientes(clients, termo), [clients, termo]);
  const curto = termo.trim().length < 3;
  // Antes de digitar: os clientes das últimas OS no topo (quase sempre é um deles), depois o resto.
  const { data: idsRecentes } = useClientesRecentes();
  const recentes = useMemo(() => {
    const porId = new Map((clients ?? []).filter((c) => c.active).map((c) => [c.id, c]));
    return (idsRecentes ?? []).map((id) => porId.get(id)).filter((c): c is Client => !!c);
  }, [clients, idsRecentes]);
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
      className="relative overflow-visible bg-transparent [&_[cmdk-input-wrapper]]:border-b-0 [&_[cmdk-input]]:h-10"
      onKeyDown={(e) => {
        if (e.key === 'Escape') fechar();
        if (e.key === 'ArrowDown' && !aberta) setAberta(true);
      }}
    >
      <div className="rounded-md border border-input bg-background focus-within:ring-2 focus-within:ring-ring focus-within:ring-offset-2 ring-offset-background">
        <CommandInput
          value={termo}
          onValueChange={(v) => { setTermo(v); setAberta(true); }}
          // Clique abre; foco por Tab não — senão a lista cobre a ficha a cada passagem.
          onClick={() => setAberta(true)}
          onBlur={fechar}
          placeholder={temSelecionado
            ? 'Trocar cliente: nome, CPF/CNPJ ou telefone…'
            : 'Buscar cliente: nome, CPF/CNPJ, telefone ou e-mail…'}
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
          {lista.map((c) => <ItemCliente key={c.id} valor={c.id} cliente={c} onEscolher={escolher} />)}
          <CommandItem
            value="__novo_cliente__"
            onSelect={() => { const t = termo.trim(); fechar(); onNovo(t); }}
            className="mt-1 cursor-pointer border-t text-primary"
          >
            <Plus className="mr-2 h-4 w-4" />
            {curto ? 'Novo cliente' : `Cadastrar "${termo.trim()}"`}
          </CommandItem>
        </CommandList>
      )}
    </Command>
  );
}

function ItemCliente({ cliente: c, valor, onEscolher }: { cliente: Client; valor: string; onEscolher: (c: Client) => void }) {
  const detalhe = [c.cpf_cnpj, c.whatsapp || c.phone, [c.city, c.state].filter(Boolean).join('/')]
    .filter(Boolean).join(' · ');
  return (
    <CommandItem value={valor} onSelect={() => onEscolher(c)} className="cursor-pointer">
      <div className="min-w-0">
        <p className="truncate text-sm">{c.name}</p>
        {detalhe && <p className="truncate text-xs text-muted-foreground">{detalhe}</p>}
      </div>
    </CommandItem>
  );
}

/* ------------------------------------------------------------------ ficha */

const brl = (v: number) => new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

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
    <div className="space-y-2 rounded-lg border bg-muted/30 p-3 text-sm" aria-label="Dados do cliente">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="break-words font-semibold leading-tight">{c.name}</p>
          <p className="mt-0.5 text-xs text-muted-foreground">
            {c.type === 'company' ? 'Pessoa jurídica' : 'Pessoa física'}
            {!c.active && ' · cadastro inativo'}
          </p>
        </div>
        <Button type="button" variant="outline" size="sm" className="h-8 shrink-0 gap-1 px-2.5" onClick={onEditar}>
          <Pencil className="h-3.5 w-3.5" /> Editar cadastro
        </Button>
      </div>

      <ul className="space-y-1">
        {c.cpf_cnpj && (
          <Linha icone={IdCard}>{c.cpf_cnpj}</Linha>
        )}
        {zap && (
          <Linha icone={Phone}>
            <a href={hrefTelefone(zap)} className="hover:underline">{zap}</a>
            {zapE164.length >= 12 && (
              <a
                href={`https://wa.me/${zapE164}`}
                target="_blank"
                rel="noopener noreferrer"
                className="ml-2 inline-flex items-center gap-0.5 text-xs text-primary hover:underline"
                aria-label="Abrir conversa no WhatsApp"
              >
                <MessageCircle className="h-3.5 w-3.5" /> WhatsApp
              </a>
            )}
          </Linha>
        )}
        {foneSeparado && (
          <Linha icone={Phone}>
            <a href={hrefTelefone(foneSeparado)} className="hover:underline">{foneSeparado}</a>
            <span className="ml-1 text-xs text-muted-foreground">(fixo)</span>
          </Linha>
        )}
        {c.email && (
          <Linha icone={Mail}>
            <a href={`mailto:${c.email}`} className="break-all hover:underline">{c.email}</a>
          </Linha>
        )}
        {endereco && (
          <Linha icone={MapPin}>
            {endereco}
            {c.postal_code && <span className="text-muted-foreground"> · CEP {c.postal_code}</span>}
          </Linha>
        )}
        {c.notes && (
          <Linha icone={StickyNote}>
            <span className="line-clamp-3 whitespace-pre-line italic text-muted-foreground" title={c.notes}>{c.notes}</span>
          </Linha>
        )}
        {saldo && saldo.emAberto > 0.009 && (
          <Linha icone={Wallet}>
            <span className={saldo.vencidos ? 'font-medium text-amber-700 dark:text-amber-400' : undefined}>
              Em aberto: {brl(saldo.emAberto)}
              {saldo.vencidos > 0 && ` · ${saldo.vencidos} vencido${saldo.vencidos > 1 ? 's' : ''} (${brl(saldo.valorVencido)})`}
            </span>
          </Linha>
        )}
      </ul>

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
        className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground hover:underline"
      >
        Histórico e financeiro do cliente <ExternalLink className="h-3 w-3" />
      </Link>
    </div>
  );
}

function Linha({ icone: Icone, children }: { icone: typeof Phone; children: ReactNode }) {
  return (
    <li className="flex items-start gap-2">
      <Icone className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted-foreground" aria-hidden />
      <span className="min-w-0 break-words">{children}</span>
    </li>
  );
}

function Aviso({ icone: Icone, children }: { icone: typeof Phone; children: ReactNode }) {
  return (
    <li className="flex items-start gap-1.5">
      <Icone className="mt-0.5 h-3.5 w-3.5 shrink-0" aria-hidden />
      <span>{children}</span>
    </li>
  );
}
