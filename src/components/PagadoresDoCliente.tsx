// Ficha do cliente → Financeiro: quem paga por este cliente (leva 8, 22/10/2026).
//
// A empresa dele, o cônjuge, um parente, a marina, a seguradora. Cada um nasceu de uma linha do banco (fila do
// Extrato, "Para revisar" ou "Regras") e só vale depois do SIM do administrador: o financeiro propõe, o administrador
// confirma. Daqui se pausa, reativa ou recusa — "Adicionar digitando um documento" fica para depois, de propósito:
// o documento e o nome sempre vêm do banco, nunca de quem digita.
//
// CPF de terceiro é dado pessoal: a seção só aparece para administrador e financeiro, e o CPF sai mascarado.
import { Check, Pause, Play, Ban, Users } from 'lucide-react';
import { useI18n } from '@/i18n';
import { useOptionalAuth } from '@/hooks/use-auth';
import { Skeleton } from '@/components/ui/skeleton';
import { AcoesDaLinha, type AcaoDaLinha } from '@/components/AcoesDaLinha';
import { useConfirmacao } from '@/components/Confirmacao';
import { StatusChip, type StatusTone } from '@/v2/components/StatusChip';
import { useReaplicarRegras } from '@/hooks/use-finance-review';
import { mensagemDoErro } from '@/hooks/use-lancamentos';
import {
  documentoMascarado, nomeSemCpf, pedeRevisarFila, podeVerPagadores, ROTULO_DA_RELACAO, useDecidirPagador,
  usePagadoresDoCliente, type DecisaoSobrePagador, type PagadorDoCliente, type SituacaoDoPagador,
} from '@/hooks/use-pagadores-do-cliente';

const TOM: Record<SituacaoDoPagador, StatusTone> = {
  confirmado: 'success',
  proposto: 'warning',
  pausado: 'neutral',
  recusado: 'critical',
};

const ROTULO: Record<SituacaoDoPagador, string> = {
  confirmado: 'Confirmado',
  proposto: 'Proposto',
  pausado: 'Pausado',
  recusado: 'Recusado',
};

interface Props {
  clientId: string | null | undefined;
  clientName: string;
}

/** Só administrador e financeiro: para os outros cargos a seção não existe (nem a consulta sai). */
export function PagadoresDoCliente(props: Props) {
  const cargo = useOptionalAuth()?.user?.role;
  if (!podeVerPagadores(cargo) || !props.clientId) return null;
  return <ListaDePagadores {...props} ehAdmin={cargo === 'admin'} />;
}

function ListaDePagadores({ clientId, clientName, ehAdmin }: Props & { ehAdmin: boolean }) {
  const { formatDate } = useI18n();
  const { data: lidos, isLoading, error } = usePagadoresDoCliente(clientId);
  // O nome vem da linha do banco como o banco escreveu — às vezes com o CPF dentro ("12345678901-MARIA"); a observação
  // e o motivo são texto livre. Na tela, o CPF embutido sai mascarado como o documento (nomeSemCpf).
  const data = lidos?.map((p) => ({
    ...p, nome: nomeSemCpf(p.nome), observacao: nomeSemCpf(p.observacao), decidido_motivo: nomeSemCpf(p.decidido_motivo),
  }));
  const decidir = useDecidirPagador();
  const reaplicar = useReaplicarRegras();
  const { pedir, dialogo } = useConfirmacao();

  const executar = (p: PagadorDoCliente, decisao: DecisaoSobrePagador) => {
    // Toda decisão muda o que a fila do Extrato sugere (revisão de 23/10/2026): o confirmado passa a sugerir, e o
    // recusado e o pausado são o VETO do motor — inclusive os de um PROPOSTO, que o histórico e o nome idêntico
    // deixam de sugerir. Então "Revisar a fila" em silêncio sempre que o resultado pede (pedeRevisarFila).
    decidir.mutate({ id: p.id, decisao }, {
      onSuccess: (r) => { if (pedeRevisarFila(r)) reaplicar.mutate({ silencioso: true }); },
    });
  };

  const acoes = (p: PagadorDoCliente): { rapidas: AcaoDaLinha[]; menu: AcaoDaLinha[] } => {
    const rapidas: AcaoDaLinha[] = [];
    const menu: AcaoDaLinha[] = [];
    if (ehAdmin && p.situacao === 'proposto') {
      rapidas.push({ texto: 'Confirmar', icone: Check, titulo: 'É o SIM: passa a sugerir este cliente na fila do Extrato', onClick: () => executar(p, 'confirmar') });
    }
    if (ehAdmin && (p.situacao === 'pausado' || p.situacao === 'recusado')) {
      rapidas.push({ texto: 'Reativar', icone: Play, titulo: 'Volta a valer como pagador confirmado', onClick: () => executar(p, 'reativar') });
    }
    // Só o administrador desfaz o que ele confirmou (decisão do dono, 23/10/2026): o financeiro pausa ou recusa
    // apenas um PROPOSTO — o banco recusa o resto (decidir_pagador_do_cliente).
    const podeMexer = ehAdmin || p.situacao === 'proposto';
    if (podeMexer && (p.situacao === 'proposto' || p.situacao === 'confirmado')) {
      menu.push({ texto: 'Pausar', icone: Pause, titulo: 'Deixa de ser sugerido até o administrador reativar', onClick: () => executar(p, 'pausar') });
    }
    if (podeMexer && p.situacao !== 'recusado') {
      menu.push({
        texto: 'Recusar', icone: Ban, perigo: true,
        onClick: () => pedir({
          titulo: `Recusar ${p.nome} como pagador de ${clientName}?`,
          descricao: ehAdmin
            ? 'Deixa de ser sugerido na fila do Extrato e não volta para a lista de conferir. Você pode reativar depois.'
            : 'Deixa de ser sugerido na fila do Extrato e não volta para a lista de conferir. Só o administrador traz de volta.',
          confirmar: 'Recusar',
          acao: () => executar(p, 'recusar'),
        }),
      });
    }
    return { rapidas, menu };
  };

  const quemDecidiu = (p: PagadorDoCliente): string => {
    if (p.situacao === 'confirmado') {
      const quem = p.confirmado_por_nome ? ` por ${p.confirmado_por_nome}` : '';
      return p.confirmado_em ? `Confirmado${quem} em ${formatDate(p.confirmado_em)}` : `Confirmado${quem}`;
    }
    if (p.situacao === 'proposto') {
      const quem = p.proposto_por_nome ? ` por ${p.proposto_por_nome}` : '';
      return `Proposto${quem} em ${formatDate(p.proposto_em)} — falta o SIM do administrador`;
    }
    if (p.situacao === 'pausado') return 'Pausado: não é sugerido na fila do Extrato até ser reativado';
    return 'Recusado: não é sugerido nem volta para a lista de conferir';
  };

  return (
    <section aria-labelledby="pagadores-do-cliente" className="rounded-lg border bg-card p-4">
      <div className="mb-1 flex items-center gap-2">
        <Users className="h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
        <h3 id="pagadores-do-cliente" className="text-sm font-semibold">Quem paga por este cliente</h3>
      </div>
      <p className="mb-3 text-xs text-muted-foreground">
        Pessoas e empresas que costumam pagar por {clientName}. A fila do Extrato só SUGERE este cliente quando um deles
        paga — nunca dá baixa sozinha. Para guardar um novo, parta da linha do banco: Financeiro → Extrato (Para revisar
        ou Regras).
      </p>

      {isLoading ? (
        <div className="space-y-2"><Skeleton className="h-12 w-full" /><Skeleton className="h-12 w-full" /></div>
      ) : error ? (
        <p role="alert" className="rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">
          Não consegui ler quem paga por este cliente: {mensagemDoErro(error)}
        </p>
      ) : !data || data.length === 0 ? (
        <p className="text-sm text-muted-foreground">Ninguém guardado como pagador deste cliente.</p>
      ) : (
        <ul className="divide-y">
          {data.map((p) => {
            const { rapidas, menu } = acoes(p);
            const doc = documentoMascarado(p.documento);
            return (
              <li key={p.id} className="flex flex-wrap items-start justify-between gap-2 py-3">
                <div className="min-w-0 flex-1 space-y-0.5">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="min-w-0 break-words font-medium">{p.nome}</span>
                    <StatusChip dot tone={TOM[p.situacao]}>{ROTULO[p.situacao]}</StatusChip>
                  </div>
                  <p className="text-xs text-muted-foreground">
                    {ROTULO_DA_RELACAO[p.relacao] ?? p.relacao}
                    {doc ? ` · ${p.documento.length === 14 ? 'CNPJ' : 'CPF'} ${doc}` : ''}
                    {` · desde ${formatDate(p.proposto_em)}`}
                  </p>
                  <p className="text-xs text-muted-foreground">{quemDecidiu(p)}</p>
                  {p.decidido_motivo && <p className="text-xs text-muted-foreground">Motivo: {p.decidido_motivo}</p>}
                  {p.observacao && <p className="text-xs italic text-muted-foreground">{p.observacao}</p>}
                </div>
                <AcoesDaLinha
                  rotulo={`pagador ${p.nome}`}
                  tituloDoMenu={p.nome}
                  rapidas={rapidas}
                  menu={menu}
                  ocupada={decidir.isPending}
                />
              </li>
            );
          })}
        </ul>
      )}
      {dialogo}
    </section>
  );
}
