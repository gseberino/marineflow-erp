// Faixas do agrupamento de OS (28/10/2026), no topo da tela da OS. Mesmo desenho das de orçamento (que moram
// no ServiceOrderForm), com o texto de OS: a origem diz para onde foi e que o dinheiro dela está lá; a agrupada
// diz o que reúne, que as assinaturas ficaram nas originais e, enquanto dá, oferece o Desagrupar.
import { Link } from 'react-router-dom';
import { Combine, Ungroup } from 'lucide-react';
import { Button } from '@/components/ui/button';

/** Origem: esta OS foi agrupada em outra e fica cancelada como histórico (a edição já está travada). */
export function FaixaOsAgrupadaEm({
  agrupadoId,
  agrupadoNumero,
  desagrupavel,
  motivo = null,
}: {
  agrupadoId: string;
  /** null enquanto a consulta não chega. */
  agrupadoNumero: string | null;
  /** A agrupada ainda pode ser desagrupada (a leitura do banco; sem ela, o palpite pela situação). null = ainda não se sabe. */
  desagrupavel: boolean | null;
  /** Por que o banco não deixa desagrupar (a frase dele), quando desagrupavel === false. */
  motivo?: string | null;
}) {
  const destino = agrupadoNumero ?? 'outra OS';
  return (
    <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-slate-200 bg-slate-50 p-4">
      <div className="flex min-w-0 items-center gap-2">
        <Combine className="h-5 w-5 shrink-0 text-slate-600" />
        <div className="min-w-0">
          <p className="text-sm font-medium text-slate-800">Esta OS foi agrupada em {destino}.</p>
          <p className="mt-0.5 break-words text-xs text-slate-600">
            {desagrupavel === false
              ? motivo
                ? `${motivo} Enquanto não for desagrupada, esta fica só como histórico.`
                : `A ${destino} já começou a ser executada (ou foi assinada, concluída ou cancelada), então não dá mais para desagrupar: esta fica só como histórico.`
              : `Sinais, contas a receber, tarefas e compras desta OS estão na ${destino}. Para mexer nesta, desagrupe a ${destino}.`}
          </p>
        </div>
      </div>
      <Button asChild variant="outline" size="sm" className="shrink-0">
        <Link to={`/v2/service-orders/${agrupadoId}`}>Abrir {agrupadoNumero ?? 'a OS agrupada'}</Link>
      </Button>
    </div>
  );
}

/** Agrupada: esta OS reúne outras; o Desagrupar aparece enquanto ela não começou e o cargo pode. */
export function FaixaOsQueReune({
  origens,
  podeDesagrupar,
  cancelarPedeDesagrupar,
  motivoSemDesagrupar = null,
  onDesagrupar,
}: {
  origens: Array<{ id: string; numero: string; assinada?: boolean }>;
  podeDesagrupar: boolean;
  /** O banco recusa cancelar a agrupada desfazível: a faixa diz o caminho (o menu tira o Cancelar). */
  cancelarPedeDesagrupar: boolean;
  /** Por que o banco não deixa mais desagrupar (a frase dele): a faixa mostra, e o Cancelar volta ao menu. */
  motivoSemDesagrupar?: string | null;
  onDesagrupar: () => void;
}) {
  const assinadas = origens.filter((o) => o.assinada).map((o) => o.numero);
  return (
    <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-sky-200 bg-sky-50 p-4">
      <div className="flex min-w-0 items-center gap-2">
        <Combine className="h-5 w-5 shrink-0 text-sky-600" />
        <div className="min-w-0">
          <p className="text-sm font-medium text-sky-800">Esta OS reúne {origens.map((o) => o.numero).join(', ')}.</p>
          {assinadas.length > 0 && (
            <p className="mt-0.5 break-words text-xs text-sky-700">
              {assinadas.length === 1
                ? `A assinatura do cliente ficou na ${assinadas[0]}, como histórico; esta OS nasceu sem assinatura.`
                : `As assinaturas do cliente ficaram nas OS originais (${assinadas.join(', ')}), como histórico; esta OS nasceu sem assinatura.`}
            </p>
          )}
          {cancelarPedeDesagrupar && (
            <p className="mt-0.5 break-words text-xs text-sky-700">
              Para cancelá-la, desagrupe primeiro: as originais voltam a valer e depois você decide o que fazer com elas.
            </p>
          )}
          {!podeDesagrupar && !cancelarPedeDesagrupar && motivoSemDesagrupar && (
            <p className="mt-0.5 break-words text-xs text-sky-700">{motivoSemDesagrupar}</p>
          )}
        </div>
      </div>
      {podeDesagrupar && (
        <Button
          variant="outline"
          size="sm"
          className="shrink-0 gap-1 border-sky-300 text-sky-800 hover:bg-sky-100"
          onClick={onDesagrupar}
        >
          <Ungroup className="h-4 w-4" /> Desagrupar
        </Button>
      )}
    </div>
  );
}
