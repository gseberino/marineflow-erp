// Regras da OS que vira nota fiscal — separadas do index.ts para serem testáveis sem subir a função.
//
// [FECHAR-JUNTAS 0b, item 4] Colunas da OS que a ponte da NFS-e lê. Faltava `customer_po_number`
// (o select antigo, index.ts:815-819, não o trazia) e a nota saía SEM o "Pedido do cliente"
// mesmo quando a OS tinha um, porque `montarInfoComplementar` recebia `undefined`.
export const COLUNAS_OS_PONTE_NFSE = "id, service_order_number, status, client_id, customer_po_number, "
  + "discount_amount, is_travel_billable, travel_cost_total, operational_cost_total, "
  + "subcontract_cost_total, card_fee_amount, tax_amount";

// [FECHAR-JUNTAS 0b, item 5] Nota de OS só sai de OS de verdade e concluída. As pontes só
// recusavam OS cancelada, e a emissão detalhada (que manda `items`/`service` próprios) passava
// por fora delas — foi assim que a NFS-e nº 6 saiu autorizada para o ORÇ-00109, em rascunho.
// A regra vale para TODA criação com origin_type "service_order" (handleCreate e
// handleCreateNfse), na hora da emissão, venha o corpo da ponte ou da tela, e também no
// pré-voo do Faturar (handleBillingPreflight), para a tela não prometer o que a emissão recusa.

/** Status em que a OS está concluída e pode gerar nota. */
export const STATUS_OS_EMITIVEL = ["completed", "invoiced"] as const;

const ROTULO_STATUS: Record<string, string> = {
  draft: "em rascunho",
  scheduled: "agendada",
  open: "aberta",
  in_progress: "em execução",
  awaiting_parts: "aguardando peças",
  awaiting_client: "aguardando o cliente",
  approved: "aprovada",
  completed: "concluída",
  invoiced: "faturada",
  cancelled: "cancelada",
};

export interface OsParaNota {
  service_order_number?: string | null;
  status?: string | null;
  converted_to_os_at?: string | null;
  merged_into_id?: string | null;
}

/**
 * Por que esta OS NÃO pode gerar nota, ou `null` se pode. `numeroDestino` é o número da OS
 * que recebeu esta no Agrupar OS (só usado quando `merged_into_id` está preenchido).
 */
export function motivoOsSemNota(so: OsParaNota, numeroDestino?: string | null): string | null {
  const numero = so.service_order_number || "Esta OS";
  // Agrupada primeiro: a OS agrupada também está cancelada, e a mensagem útil é para onde ela foi.
  if (so.merged_into_id) {
    const destino = numeroDestino || "outra OS";
    return `${numero} foi agrupada na ${destino}: a nota sai pela ${destino}, não por esta.`;
  }
  // Mesmo critério de "é OS" do banco (agrupar_os) e da tela do Agrupar (src/lib/agrupar-os.ts):
  // rascunho sem conversão é orçamento; fora do rascunho é OS, mesmo a antiga sem
  // converted_to_os_at (ORÇ-00070 e OS-00105, concluídas sem a data; o "Duplicar" também cria
  // OS sem ela). Exigir a data barrava a nota de OS concluída de verdade.
  if (so.status === "draft" && !so.converted_to_os_at) {
    return `${numero} ainda é orçamento (não virou OS): nota fiscal só sai de OS. `
      + "Converta o orçamento em OS e conclua o serviço antes de emitir.";
  }
  if (so.status === "cancelled") return "OS cancelada não pode gerar nota.";
  if (!(STATUS_OS_EMITIVEL as readonly string[]).includes(String(so.status))) {
    const rotulo = ROTULO_STATUS[String(so.status)] ?? `com status "${so.status}"`;
    return `${numero} está ${rotulo}: nota só sai de OS concluída. Conclua a OS antes de emitir.`;
  }
  return null;
}

// Só o pedaço do cliente do Supabase que esta função usa — permite testar com um falso.
// deno-lint-ignore no-explicit-any
type BancoMinimo = { from: (tabela: string) => any };

/**
 * Relê a OS no banco e diz se ela pode gerar nota AGORA. Chamada no começo de toda criação com
 * origin_type "service_order": o que a tela ou o assistente viram antes pode ter mudado.
 */
export async function conferirOsParaNota(
  admin: BancoMinimo,
  originId: string | null | undefined,
): Promise<{ ok: true } | { ok: false; error: string; status: number }> {
  if (!originId) {
    return { ok: false, status: 422, error: "Nota de OS sem a OS de origem (origin_id). Nada foi emitido." };
  }
  const { data: so, error } = await admin
    .from("service_orders")
    .select("id, service_order_number, status, converted_to_os_at, merged_into_id")
    .eq("id", String(originId))
    .maybeSingle();
  if (error) return { ok: false, status: 500, error: "Falha ao conferir a OS: " + (error.message ?? String(error)) };
  if (!so) return { ok: false, status: 404, error: "Ordem de serviço não encontrada." };

  let numeroDestino: string | null = null;
  if (so.merged_into_id) {
    // Leitura à parte, e não embed da autorrelação: não depende do nome da FK nem arrisca um
    // embed ambíguo (PGRST201) se outra relação aparecer. Falhar aqui só tira o número da mensagem.
    const { data: destino } = await admin
      .from("service_orders")
      .select("service_order_number")
      .eq("id", String(so.merged_into_id))
      .maybeSingle();
    numeroDestino = destino?.service_order_number ?? null;
  }

  const motivo = motivoOsSemNota(so, numeroDestino);
  if (motivo) return { ok: false, status: 422, error: motivo + " Nada foi emitido." };
  return { ok: true };
}
