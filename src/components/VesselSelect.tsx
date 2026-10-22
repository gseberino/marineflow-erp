import { useState } from 'react';
import { VesselFormDialog } from '@/components/VesselFormDialog';
import { EntityCombobox } from '@/components/EntityCombobox';
import { TERMO_GERAL, rotuloDaUnidade } from '@/lib/unidade';

interface VesselOption {
  id: string;
  name: string;
  /** Lancha, Motorhome…: vai na descrição da opção (cliente com barco e motorhome). */
  asset_type?: string | null;
  manufacturer?: string | null;
  model?: string | null;
  hull_id_or_registration?: string | null;
  marina_id?: string | null;
  active: boolean;
}

interface Props {
  value: string;
  onChange: (vesselId: string) => void;
  vessels: VesselOption[];
  clientId: string;
  disabled?: boolean;
  onVesselCreated?: (vessel: { id: string; name: string; marina_id?: string | null; access_notes?: string | null }) => void;
  /** Repassados ao gatilho (nome e descrição para o leitor de tela). */
  id?: string;
  ariaDescribedBy?: string;
  ariaRequired?: boolean;
  /** Lista já aberta (depois de um "Trocar"). */
  defaultOpen?: boolean;
  /** Antes de abrir o cadastro novo: quem usa pode perguntar primeiro e só então chamar `abrir`. */
  antesDeCadastrar?: (abrir: () => void) => void;
  /** A lista fechou sem escolha (Esc, clique fora). */
  onDispensar?: () => void;
}

export function VesselSelect({
  value, onChange, vessels, clientId, disabled, onVesselCreated, id, ariaDescribedBy, ariaRequired,
  defaultOpen, antesDeCadastrar, onDispensar,
}: Props) {
  const [showCreate, setShowCreate] = useState(false);

  const options = vessels
    .filter(v => v.active)
    .map(v => {
      // O tipo de cada opção ("Motorhome · Iveco Daily 55C17"); sem tipo (ou "Outro"), só o modelo.
      // A busca já olha a descrição: digitar "motorhome" acha.
      const tipo = rotuloDaUnidade(v.asset_type);
      return {
        value: v.id,
        label: v.name,
        description: [tipo === TERMO_GERAL ? '' : tipo, [v.manufacturer, v.model].filter(Boolean).join(' ')]
          .filter(Boolean).join(' · ') || undefined,
        searchTerms: [
          v.manufacturer || '',
          v.model || '',
          v.hull_id_or_registration || '',
        ],
      };
    });

  return (
    <>
      <EntityCombobox
        value={value}
        onChange={onChange}
        options={options}
        disabled={disabled}
        // Nada escolhido ainda: o termo geral (decisão 9, 21/10/2026).
        placeholder="Selecionar embarcação ou veículo"
        searchPlaceholder="Buscar embarcação ou veículo... (digite 3+ letras)"
        emptyText="Nenhuma embarcação ou veículo encontrado"
        onCreate={() => (antesDeCadastrar ? antesDeCadastrar(() => setShowCreate(true)) : setShowCreate(true))}
        createLabel="Nova embarcação ou veículo para este cliente"
        id={id}
        ariaDescribedBy={ariaDescribedBy}
        ariaRequired={ariaRequired}
        defaultOpen={defaultOpen}
        onDispensar={onDispensar}
      />

      <VesselFormDialog
        open={showCreate}
        onOpenChange={setShowCreate}
        initialClientId={clientId}
        onCreated={(vessel) => {
          if (onVesselCreated) onVesselCreated(vessel);
        }}
      />
    </>
  );
}
