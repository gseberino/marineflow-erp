/* Embarcação/veículo da OS com a mesma proteção do cliente (pedido do dono, 21/10/2026: "em casos
   específicos" — a pesquisa disse quais). Escolhida, fica a ficha; trocar exige o "Trocar" da linha
   do rótulo, que abre a lista já aberta, com "Cancelar". A confirmação só aparece quando a troca
   perde algo ou o documento já foi ao cliente (lib/troca-de-embarcacao.ts); quem monta a tela
   passa o bloqueio (OS concluída, agrupamento). */
import { useEffect, useId, useRef, useState, type ReactNode } from 'react';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Skeleton } from '@/components/ui/skeleton';
import { VesselSelect } from '@/components/VesselSelect';
import { useConfirmacao } from '@/components/Confirmacao';
import { FichaDaEmbarcacao } from './FichaDaEmbarcacao';
import { BOTAO_DO_ROTULO } from './ClienteDaOrdem';
import {
  descricaoDaTrocaDeEmbarcacao, nomeDaUnidade, tituloDaTrocaDeEmbarcacao, type UnidadeResumo,
} from '@/lib/troca-de-embarcacao';
import { unidadeNaFrase } from '@/lib/unidade';
import type { Vessel } from '@/hooks/use-vessels';

type VesselDaLista = Vessel & { marinas?: { name?: string | null } | null };
type Criada = { id: string; name: string; marina_id?: string | null; access_notes?: string | null };

interface Props {
  rotulo: string;
  value: string;
  clientId: string;
  /** As unidades do cliente (as opções da lista). */
  vessels: any[];
  /** A unidade escolhida, com a marina (para a ficha). */
  embarcacao?: VesselDaLista;
  /** OS travada ou sem cliente: sem lista e sem troca. */
  disabled?: boolean;
  /** Por que não dá para trocar (OS concluída, agrupamento); `true` só esconde o "Trocar". */
  semTroca?: string | true;
  /** O que a confirmação diz para trocar por `novo` (null = cadastro novo). Vazio = troca direto. */
  motivosDaTroca: (novo: UnidadeResumo | null) => string[];
  documento?: 'OS' | 'orçamento';
  onChange: (vesselId: string) => void;
  onVesselCreated: (vessel: Criada) => void;
  /** Região do aviso logo abaixo da lista (o pai a mantém sempre montada). */
  aviso?: ReactNode;
  ariaDescribedBy?: string;
}

export function EmbarcacaoDaOrdem({
  rotulo, value, clientId, vessels, embarcacao, disabled, semTroca, motivosDaTroca, documento = 'OS',
  onChange, onVesselCreated, aviso, ariaDescribedBy,
}: Props) {
  const [trocando, setTrocando] = useState(false);
  const idRotulo = useId();
  const trocarRef = useRef<HTMLButtonElement>(null);
  // Lido na hora de confirmar: a trava (OS concluída, agrupada, travada) pode chegar com o diálogo aberto.
  const travadoRef = useRef(false);
  travadoRef.current = !!disabled || !!semTroca;
  const { pedir, dialogo: confirmacao } = useConfirmacao();

  // A unidade saiu (troca de cliente) ou chegou uma trava com a troca aberta: a troca fecha.
  useEffect(() => {
    if (!value || disabled || semTroca) setTrocando(false);
  }, [value, disabled, semTroca]);

  const emTroca = trocando && !!value && !disabled && !semTroca;
  const comLista = !disabled ? (!value || emTroca) : !value;
  const podeTrocar = !disabled && !!value && !semTroca && !emTroca;
  const atual = embarcacao ?? null;

  const focarTrocar = () => setTimeout(() => trocarRef.current?.focus({ preventScroll: true }), 0);
  const voltar = () => { setTrocando(false); focarTrocar(); };

  const perguntar = (novo: UnidadeResumo | null, motivos: string[], seguir: () => void) => {
    pedir({
      titulo: tituloDaTrocaDeEmbarcacao(documento, atual),
      descricao: descricaoDaTrocaDeEmbarcacao(atual, novo, motivos),
      confirmar: 'Trocar',
      voltar: 'Manter a atual',
      acao: () => {
        if (travadoRef.current) { setTrocando(false); return; }
        seguir();
      },
      aoVoltar: () => setTrocando(false),
      aoFechar: () => trocarRef.current?.focus({ preventScroll: true }),
    });
  };

  const escolher = (id: string) => {
    // A mesma de novo não é troca (e não apaga o solicitante).
    if (id === value) { voltar(); return; }
    const novo = vessels.find((v) => v.id === id) ?? null;
    const aplicar = () => { setTrocando(false); onChange(id); focarTrocar(); };
    const motivos = value ? motivosDaTroca(novo) : [];
    if (motivos.length) perguntar(novo, motivos, aplicar);
    else aplicar();
  };

  const antesDeCadastrar = (abrir: () => void) => {
    // Com perda, pergunta ANTES de cadastrar, como no cliente.
    const motivos = value ? motivosDaTroca(null) : [];
    if (motivos.length) perguntar(null, motivos, abrir);
    else abrir();
  };

  return (
    <div role="group" aria-labelledby={idRotulo} className="flex min-w-0 flex-col gap-1.5">
      <div className="flex min-h-5 items-center justify-between gap-2">
        <Label id={idRotulo} htmlFor={comLista ? 'os-embarcacao' : undefined}>{rotulo}</Label>
        {podeTrocar && (
          <Button
            ref={trocarRef} type="button" variant="link" size="sm" className={BOTAO_DO_ROTULO}
            onClick={() => setTrocando(true)}
            // Pelo tipo da atual: "Trocar o motorhome Iveco Daily"; sem tipo, "a embarcação ou veículo".
            aria-label={`Trocar ${unidadeNaFrase(atual)}`}
          >
            Trocar
          </Button>
        )}
        {emTroca && (
          <Button
            type="button" variant="link" size="sm" className={BOTAO_DO_ROTULO}
            onClick={voltar}
            aria-label={`Cancelar a troca e manter ${unidadeNaFrase(atual)}`}
          >
            Cancelar
          </Button>
        )}
      </div>

      {typeof semTroca === 'string' && value && !disabled && <p className="text-xs text-muted-foreground">{semTroca}</p>}

      {emTroca && (
        <p className="text-xs text-muted-foreground">
          Trocar <span className="font-medium text-foreground">{atual ? nomeDaUnidade(atual) : 'a embarcação ou veículo atual'}</span> por:
        </p>
      )}

      {/* Seletor e aviso num bloco que sempre existe: a região viva do aviso fica montada (vazia)
          para ser anunciada quando o texto chegar, e vazia não ganha o gap. */}
      <div>
        {comLista && (
          <VesselSelect
            id="os-embarcacao"
            ariaRequired
            ariaDescribedBy={ariaDescribedBy}
            value={value}
            clientId={clientId}
            vessels={vessels}
            disabled={disabled}
            defaultOpen={emTroca}
            onChange={escolher}
            antesDeCadastrar={antesDeCadastrar}
            // Esc ou clique fora com a troca aberta = desistiu: volta a ficha, como no cliente.
            onDispensar={emTroca ? voltar : undefined}
            onVesselCreated={(v) => { setTrocando(false); onVesselCreated(v); focarTrocar(); }}
          />
        )}
        {aviso}
      </div>

      {!emTroca && value && (
        embarcacao ? <FichaDaEmbarcacao embarcacao={embarcacao} />
        : vessels.length === 0 ? <Skeleton className="h-16 w-full rounded-lg" />
        : (
          <p className="rounded-lg border border-dashed p-3 text-sm text-muted-foreground">
            A embarcação ou veículo {documento === 'orçamento' ? 'deste orçamento' : 'desta OS'} não está na lista do cliente.
          </p>
        )
      )}
      {confirmacao}
    </div>
  );
}
