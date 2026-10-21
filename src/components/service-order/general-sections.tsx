/* Seções A-D da OS — Identificação, Cliente & Embarcação, Agendamento+Técnicos,
   Problema & Técnico — extraídas 1:1 do ServiceOrderForm (Fase 3, passo 6).
   21/10/2026: todo par rótulo/campo passa pelo <Campo> (rótulo, dica e controle, de cima para
   baixo; perto dentro do par, mais espaço entre os pares) — o dono achou a seção "tudo junto". */
import { useState, type Dispatch, type SetStateAction } from 'react';
import { Camera, ChevronDown, MessageCircle, Phone, Sparkles } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Textarea } from '@/components/ui/textarea';
import { Campo } from '@/components/Campo';
import { ClienteDaOrdem } from './ClienteDaOrdem';
import { EmbarcacaoDaOrdem } from './EmbarcacaoDaOrdem';
import { hrefTelefone } from '@/lib/ficha-cliente';
import { normalizePhoneE164 } from '@/lib/masks';
import { isQuoteStatus } from '@/lib/document-type';
import { perdasDaTrocaDeCliente, trocarClienteNoForm, trocarEmbarcacaoNoForm } from '@/lib/troca-de-cliente';
import { motivosDaTrocaDeEmbarcacao, type UnidadeResumo } from '@/lib/troca-de-embarcacao';
import { useServiceOrderSurvey } from '@/hooks/use-service-survey';
import { EntityCombobox } from '@/components/EntityCombobox';
import { ServiceOrderPhotos } from '@/components/ServiceOrderPhotos';
import { VESSEL_CONTACT_ROLES } from '@/hooks/use-vessel-contacts';
import { useI18n } from '@/i18n';

const SERVICE_TYPES = [
  'diagnosis', 'repair', 'installation', 'preventive_maintenance',
  'consulting', 'engineering_project', 'commissioning', 'inspection',
] as const;

const PRIORITIES = ['low', 'normal', 'high', 'urgent'] as const;
const STATUSES = [
  'draft', 'scheduled', 'open', 'in_progress', 'awaiting_parts',
  'awaiting_client', 'approved', 'completed', 'invoiced', 'cancelled',
] as const;

interface GeneralSectionsProps {
  isNew: boolean;
  isLocked: boolean;
  orderData: any;
  form: Record<string, any>;
  set: (field: string, value: any) => void;
  setForm: Dispatch<SetStateAction<Record<string, any>>>;
  clients: any[] | undefined;
  allVessels: any[] | undefined;
  clientVessels: any[] | undefined;
  marinas: any[] | undefined;
  appUsers: any[] | undefined;
  vesselContacts: any[] | undefined;
  selectedTechnicians: string[];
  setSelectedTechnicians: Dispatch<SetStateAction<string[]>>;
  setQuickMarinaOpen: Dispatch<SetStateAction<boolean>>;
  setQuickMarinaName: Dispatch<SetStateAction<string>>;
  isOptimizing: boolean;
  optimizeText: (...args: any[]) => any;
  /** Lê a descrição e devolve o levantamento meio pronto. Opcional: sem isso a
      seção segue funcionando como antes, só com o reescrever. */
  onAnalisarDescricao?: (texto: string) => void;
  analisandoDescricao?: boolean;
  /** Por que o cliente não pode ser trocado (orçamento que reúne outros, do mesmo cliente);
      `true` só esconde o "Trocar" enquanto isso é conferido. */
  semTrocaDeCliente?: string | true;
  /** Por que a embarcação/veículo não pode ser trocada (OS concluída, agrupamento). */
  semTrocaDeEmbarcacao?: string | true;
}

export function GeneralSections(props: GeneralSectionsProps) {
  const {
    isNew, isLocked, orderData, form, set, setForm,
    clients, allVessels, clientVessels, marinas, appUsers, vesselContacts,
    selectedTechnicians, setSelectedTechnicians,
    setQuickMarinaOpen, setQuickMarinaName,
    isOptimizing, optimizeText, onAnalisarDescricao, analisandoDescricao, semTrocaDeCliente,
    semTrocaDeEmbarcacao,
  } = props;
  const { t } = useI18n();
  // Levantamento da OS: trocar a unidade o deixa na antiga. Erro na consulta = "não deu para
  // conferir" (pede confirmação), nunca "não tem".
  const levantamento = useServiceOrderSurvey(orderData?.id);
  // Trocou de um cliente para outro nesta tela: até escolher a embarcação nova, a OS salva não
  // grava (o salvamento automático exige embarcação) — o aviso abaixo do campo diz isso.
  const [clienteTrocado, setClienteTrocado] = useState(false);

  const embarcacao = form.vessel_id ? allVessels?.find((v) => v.id === form.vessel_id) : undefined;
  const nomeDoCliente = clients?.find((c) => c.id === form.client_id)?.name;
  const contatoEscolhido = vesselContacts?.find((c) => c.id === form.requested_by_contact_id);
  // O que sai da OS se o cliente mudar (pelos mesmos critérios da troca): vai no texto da confirmação.
  const perdasDaTroca = perdasDaTrocaDeCliente(form, embarcacao, {
    embarcacao: embarcacao?.name,
    solicitante: contatoEscolhido?.full_name,
    marina: marinas?.find((m) => m.id === form.marina_id)?.name,
  });
  const temContatos = !!vesselContacts && vesselContacts.length > 0;
  const faltaEmbarcacao = clienteTrocado && !!form.client_id && !form.vessel_id;
  const documento: 'OS' | 'orçamento' = isQuoteStatus(form.status) ? 'orçamento' : 'OS';
  const motivosDaTrocaDeUnidade = (novo: UnidadeResumo | null) => motivosDaTrocaDeEmbarcacao({
    salva: !!orderData?.id,
    documento,
    quoteStatus: orderData?.quote_status,
    convertidaEmOS: !!orderData?.converted_to_os_at,
    confirmacaoDoAgendamentoPedida: !!orderData?.client_confirmation_requested_at,
    assinadaPeloCliente: !!orderData?.signed_at && !orderData?.requires_resignature,
    checkInFeito: !!orderData?.check_in_at,
    temLevantamento: levantamento.isError ? null : !!levantamento.data,
    // Mesmo critério da troca (trocarEmbarcacaoNoForm): o id preenchido é o que sai, esteja o
    // contato na lista de ativos ou não (desativado, lista carregando ou com erro).
    contatoSolicitante: form.requested_by_contact_id
      ? (contatoEscolhido?.full_name || form.requested_by_name || '')
      : null,
  }, embarcacao, novo);

  return (
    <>
      {/* A - Identification */}
      <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
        <h2 className="font-semibold text-sm">{t.serviceOrders.tabOverview}</h2>
        <div className="grid grid-cols-1 gap-x-4 gap-y-6 sm:grid-cols-3">
          <Campo rotulo={t.common.status} htmlFor="os-status">
            <Select value={form.status} onValueChange={(v) => set('status', v)} disabled={!isNew}>
              <SelectTrigger id="os-status"><SelectValue /></SelectTrigger>
              <SelectContent>
                {STATUSES.map((s) => (
                  <SelectItem key={s} value={s}>{(t.status as Record<string, string>)[s]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Campo>
          <Campo rotulo={t.serviceOrders.priority} htmlFor="os-prioridade">
            <Select value={form.priority} onValueChange={(v) => set('priority', v)}>
              <SelectTrigger id="os-prioridade"><SelectValue /></SelectTrigger>
              <SelectContent>
                {PRIORITIES.map((p) => (
                  <SelectItem key={p} value={p}>{(t.priority as Record<string, string>)[p]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Campo>
          <Campo rotulo={t.common.type} htmlFor="os-tipo">
            <Select value={form.service_type} onValueChange={(v) => set('service_type', v)}>
              <SelectTrigger id="os-tipo"><SelectValue /></SelectTrigger>
              <SelectContent>
                {SERVICE_TYPES.map((st) => (
                  <SelectItem key={st} value={st}>{(t.serviceType as Record<string, string>)[st]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Campo>
        </div>
      </section>

      {/* B - Client & Vessel */}
      <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
        <h2 className="font-semibold text-sm">{t.serviceOrders.clientAndVessel}</h2>
        {/* Duas colunas a partir de md (o menu lateral só aparece em lg, então de 768 px em diante
            sobra largura): à esquerda o cliente; à direita, na ordem de dependência, a embarcação,
            o solicitante (contatos dela) e a marina. No celular, uma coluna na ordem do código. */}
        <div className="grid grid-cols-1 gap-x-6 gap-y-6 md:grid-cols-2 md:items-start">
          <ClienteDaOrdem
            rotulo={`${t.serviceOrders.client} *`}
            value={form.client_id}
            onChange={(clientId) => {
              const barcoAntigo = allVessels?.find((v) => v.id === form.vessel_id);
              // Cliente com um barco só já entra com ele, no mesmo passo (o efeito do formulário
              // faria isso um render depois, e o aviso de "escolha a embarcação" piscaria).
              const barcos = allVessels?.filter((v) => v.client_id === clientId) ?? [];
              const unico = barcos.length === 1 ? barcos[0] : null;
              if (form.client_id) setClienteTrocado(true);
              setForm((f) => {
                const trocado = trocarClienteNoForm(f, clientId, barcoAntigo);
                return unico ? trocarEmbarcacaoNoForm(trocado, unico.id, undefined, unico) : trocado;
              });
            }}
            clients={clients}
            disabled={isLocked}
            semTroca={semTrocaDeCliente}
            ordemSalva={!!orderData?.id}
            perdas={perdasDaTroca}
            documento={documento}
          />

          <div className="flex min-w-0 flex-col gap-6">
            <EmbarcacaoDaOrdem
              rotulo={`${t.serviceOrders.vessel} *`}
              value={form.vessel_id}
              clientId={form.client_id}
              vessels={clientVessels ?? []}
              embarcacao={embarcacao}
              disabled={!form.client_id || isLocked}
              // Enquanto o levantamento carrega, o "Trocar" espera (sem ele não dá para saber o que sai).
              semTroca={semTrocaDeEmbarcacao ?? (orderData?.id && levantamento.isLoading ? true : undefined)}
              motivosDaTroca={motivosDaTrocaDeUnidade}
              documento={documento}
              ariaDescribedBy={faltaEmbarcacao ? 'os-aviso-embarcacao' : undefined}
              onChange={(vesselId) => {
                const antigo = allVessels?.find((v) => v.id === form.vessel_id);
                const novo = allVessels?.find((v) => v.id === vesselId);
                // Mesma embarcação de novo devolve o mesmo form: nada muda (antes apagava o
                // solicitante em silêncio). Marina e local sugeridos acompanham; escolhidos à mão, ficam.
                setForm((f) => trocarEmbarcacaoNoForm(f, vesselId, antigo, novo));
              }}
              onVesselCreated={(vessel) => {
                // Mesma regra da escolha: o contato do barco anterior sai; marina e local sugeridos acompanham.
                const antigo = allVessels?.find((v) => v.id === form.vessel_id);
                setForm((f) => trocarEmbarcacaoNoForm(f, vessel.id, antigo, {
                  marina_id: vessel.marina_id ?? null, access_notes: vessel.access_notes ?? null,
                }));
              }}
              aviso={
                // Sempre montado: o aviso entra como anúncio quando a troca fica pendente.
                <div role="status" aria-live="polite">
                  {faltaEmbarcacao && (
                    <p id="os-aviso-embarcacao" className="mt-1.5 text-xs text-amber-700 dark:text-amber-400">
                      {nomeDoCliente ? `Escolha a embarcação de ${nomeDoCliente}.` : 'Escolha a embarcação do cliente novo.'}
                      {/* O salvamento automático não grava a OS sem embarcação (peças e serviços, sim:
                          esses gravam na hora). O que fica parado é a troca. */}
                      {orderData?.id && ' Até lá, a troca do cliente não fica salva.'}
                    </p>
                  )}
                </div>
              }
            />

            <Campo
              rotulo={t.serviceOrders.requestedBy}
              htmlFor="os-solicitante"
              ajuda={!temContatos && form.vessel_id ? 'Cadastre contatos na embarcação para aparecerem aqui.' : undefined}
              idAjuda="os-solicitante-ajuda"
            >
              {temContatos ? (
                <>
                  <Select
                    value={form.requested_by_contact_id || 'none'}
                    onValueChange={(v) => {
                      const contact = vesselContacts!.find(c => c.id === v);
                      setForm(f => ({
                        ...f,
                        requested_by_contact_id: v === 'none' ? '' : v,
                        requested_by_name: contact?.full_name || '',
                      }));
                    }}
                    disabled={isLocked}
                  >
                    <SelectTrigger id="os-solicitante">
                      <SelectValue placeholder="Selecionar contato" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="none">—</SelectItem>
                      {vesselContacts!.map(c => (
                        <SelectItem key={c.id} value={c.id}>
                          <span className="flex items-center gap-1">
                            {c.full_name}
                            <span className="text-xs text-muted-foreground">
                              ({VESSEL_CONTACT_ROLES.find(r => r.value === c.role)?.label || c.role})
                            </span>
                          </span>
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <ContatoDoSolicitante contato={contatoEscolhido} />
                </>
              ) : (
                <Input
                  id="os-solicitante"
                  value={form.requested_by_name}
                  onChange={e => set('requested_by_name', e.target.value)}
                  placeholder="Nome do solicitante"
                  disabled={isLocked}
                  aria-describedby={form.vessel_id ? 'os-solicitante-ajuda' : undefined}
                />
              )}
            </Campo>

            <Campo rotulo={t.serviceOrders.marina} htmlFor="os-marina">
              <EntityCombobox
                id="os-marina"
                value={form.marina_id}
                onChange={(v) => set('marina_id', v)}
                options={(marinas || []).filter((m) => m.active).map((m) => ({
                  value: m.id,
                  label: m.name,
                  description: m.city || undefined,
                }))}
                placeholder="—"
                onCreate={(typed) => {
                  setQuickMarinaName(typed);
                  setQuickMarinaOpen(true);
                }}
                createLabel="+ Cadastrar nova marina"
              />
            </Campo>
          </div>

          {/* Onde o serviço acontece: motorhome muda de lugar a cada serviço, barco
              tem vaga. Vem sugerido do cadastro do veículo; sai na via do técnico. A dica
              fica fixa acima do campo: ele costuma vir preenchido e o placeholder some. */}
          <Campo
            className="md:col-span-2"
            rotulo="Local do serviço e acesso"
            htmlFor="os-local-acesso"
            ajuda="Sai na via do técnico. Endereço ou vaga, como entrar, onde está a chave, portaria, horário permitido."
            idAjuda="os-local-acesso-ajuda"
          >
            <Textarea
              id="os-local-acesso"
              value={form.site_access || ''}
              onChange={(e) => set('site_access', e.target.value)}
              rows={2}
              disabled={isLocked}
              aria-describedby="os-local-acesso-ajuda"
            />
          </Campo>

          {/* Pedido do cliente: viaja até a NF-e ao faturar e sai no início das
              informações complementares da nota. */}
          <Campo rotulo="Ordem de compra do cliente" htmlFor="os-oc" ajuda="Sai na NF-e ao faturar." idAjuda="os-oc-ajuda">
            <Input
              id="os-oc"
              value={form.customer_po_number}
              onChange={e => set('customer_po_number', e.target.value)}
              placeholder="Ex.: 05447"
              maxLength={15}
              disabled={isLocked}
              aria-describedby="os-oc-ajuda"
            />
          </Campo>

          <Campo rotulo="Comprador" htmlFor="os-comprador" ajuda="Em branco, usa o solicitante." idAjuda="os-comprador-ajuda">
            <Input
              id="os-comprador"
              value={form.customer_buyer_name}
              onChange={e => set('customer_buyer_name', e.target.value)}
              placeholder="Ex.: Everton"
              disabled={isLocked}
              aria-describedby="os-comprador-ajuda"
            />
          </Campo>
        </div>
      </section>

      {/* C - Scheduling + Technicians (merged) */}
      <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
        <h2 className="font-semibold text-sm">{t.serviceOrders.schedule}</h2>
        <div className="space-y-6">
          <div className="grid grid-cols-1 gap-x-4 gap-y-6 sm:grid-cols-2">
            <Campo rotulo={t.serviceOrders.scheduledStart} htmlFor="os-inicio">
              <Input id="os-inicio" type="datetime-local" value={form.scheduled_start_at} onChange={(e) => set('scheduled_start_at', e.target.value)} />
            </Campo>
            <Campo rotulo={t.serviceOrders.scheduledEnd} htmlFor="os-fim">
              <Input id="os-fim" type="datetime-local" value={form.scheduled_end_at} onChange={(e) => set('scheduled_end_at', e.target.value)} />
            </Campo>
          </div>
          {/* Grupo de caixas: fieldset/legend, não Label (o rótulo é do grupo, não de um campo). */}
          <fieldset className="flex min-w-0 flex-col gap-1.5">
            <legend className="mb-1.5 text-sm font-medium leading-none">{t.serviceOrders.technicians}</legend>
            <div className="flex flex-wrap gap-2">
              {(appUsers || []).filter((u: any) =>
                u.id && u.id.trim() !== '' &&
                ['admin', 'technician', 'seller'].includes(u.role)
              ).map((u) => (
                <label key={u.id} className="flex items-center gap-1.5 text-sm border rounded-lg px-3 py-1.5 cursor-pointer hover:bg-muted transition-colors">
                  <input
                    type="checkbox"
                    checked={selectedTechnicians.includes(u.id)}
                    onChange={(e) => {
                      const next = e.target.checked
                        ? [...selectedTechnicians, u.id]
                        : selectedTechnicians.filter((id) => id !== u.id);
                      setSelectedTechnicians(next);
                      set('technician_count_for_travel', next.length || 1);
                    }}
                  />
                  {u.full_name}
                </label>
              ))}
            </div>
          </fieldset>
        </div>
      </section>

      {/* D - Problem & Technical (compact with collapsible) */}
      <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
        <div className="flex items-center justify-between">
          <h2 className="font-semibold text-sm">{t.serviceOrders.problemDescription}</h2>
        </div>
        <div className="space-y-6">
          <div className="flex min-w-0 flex-col gap-1.5">
            <div className="flex items-center justify-between">
              <Label htmlFor="os-descricao">{t.serviceOrders.problemDescription} *</Label>
              <div className="flex items-center gap-1">
                {/* Analisar vem primeiro porque é o que rende: reescrever deixa o
                    texto mais bonito, analisar transforma o texto em levantamento
                    meio pronto. O texto já diz o verbo, o sistema e metade das
                    respostas — até aqui ninguém lia. */}
                {onAnalisarDescricao && (
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    className="h-6 px-2 text-xs text-primary hover:text-primary hover:bg-primary/10"
                    onClick={() => onAnalisarDescricao(form.problem_description)}
                    disabled={analisandoDescricao || !form.problem_description || isLocked}
                  >
                    <Sparkles className="h-3 w-3 mr-1" />
                    {analisandoDescricao ? 'Lendo…' : 'Analisar'}
                  </Button>
                )}
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  className="h-6 px-2 text-xs text-muted-foreground hover:bg-muted"
                  title="Reescrever o texto de forma mais técnica"
                  onClick={async () => {
                    const optimized = await optimizeText(form.problem_description);
                    if (optimized) set('problem_description', optimized);
                  }}
                  disabled={isOptimizing || !form.problem_description || isLocked}
                >
                  Reescrever
                </Button>
              </div>
            </div>
            <Textarea id="os-descricao" value={form.problem_description} onChange={(e) => set('problem_description', e.target.value)} rows={3} disabled={isLocked} />
          </div>
          {/* Sai só na via do técnico: o lugar das ressalvas que hoje se perdem nas
              observações do orçamento (decisão de 01/10/2026). */}
          <Campo
            rotulo="Instrução ao técnico"
            htmlFor="os-instrucao-tecnico"
            ajuda="Sai só na via do técnico."
            idAjuda="os-instrucao-tecnico-ajuda"
          >
            <Textarea
              id="os-instrucao-tecnico"
              value={form.technician_instructions || ''}
              onChange={(e) => set('technician_instructions', e.target.value)}
              rows={2}
              disabled={isLocked}
              placeholder="Ressalvas, o que não fazer, o que precisa de aprovação antes, onde parar"
              aria-describedby="os-instrucao-tecnico-ajuda"
            />
          </Campo>
        </div>
        <Collapsible>
          <CollapsibleTrigger asChild>
            <button id="os-obs-pdf-rotulo" type="button" className="flex items-center gap-2 text-sm font-medium text-muted-foreground hover:text-foreground transition-colors w-full text-left">
              <ChevronDown className="h-3.5 w-3.5 transition-transform [[data-state=open]>&]:rotate-180" />
              Observações para impressão (PDF)
            </button>
          </CollapsibleTrigger>
          <CollapsibleContent className="pt-2">
            <Textarea
              aria-labelledby="os-obs-pdf-rotulo"
              value={form.extra_notes || ''}
              onChange={e => set('extra_notes', e.target.value)}
              placeholder="Informações específicas para este cliente, condições especiais, garantias, prazos..."
              rows={2}
              disabled={isLocked}
            />
          </CollapsibleContent>
        </Collapsible>

        {/* Photos (Only if editing existing OS) */}
        {orderData?.id && (
          <Collapsible>
            <CollapsibleTrigger asChild>
              <button type="button" className="flex items-center gap-2 text-sm font-medium text-muted-foreground hover:text-foreground transition-colors w-full text-left">
                <ChevronDown className="h-3.5 w-3.5 transition-transform [[data-state=open]>&]:rotate-180" />
                <Camera className="h-3.5 w-3.5" />
                Fotos da OS
              </button>
            </CollapsibleTrigger>
            <CollapsibleContent className="pt-3">
              <ServiceOrderPhotos serviceOrderId={orderData.id} />
            </CollapsibleContent>
          </Collapsible>
        )}
      </section>
    </>
  );
}

/** Telefone e e-mail do contato escolhido como solicitante. No náutico quem atende no dia
    costuma ser o marinheiro ou o capitão, não o dono — e o número dele só estava no cadastro
    do barco. */
function ContatoDoSolicitante({ contato }: { contato?: { phone?: string | null; email?: string | null } }) {
  if (!contato || (!contato.phone && !contato.email)) return null;
  const e164 = normalizePhoneE164(contato.phone);
  return (
    <p className="flex flex-wrap items-center gap-x-3 gap-y-0.5 text-xs text-muted-foreground">
      {contato.phone && (
        <a href={hrefTelefone(contato.phone)} className="inline-flex min-h-6 items-center gap-1 hover:text-foreground hover:underline">
          <Phone className="h-3 w-3" aria-hidden /> {contato.phone}
        </a>
      )}
      {e164.length >= 12 && (
        <a
          href={`https://wa.me/${e164}`}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex min-h-6 items-center gap-1 text-foreground underline underline-offset-2"
          aria-label="Abrir conversa com o solicitante no WhatsApp"
        >
          <MessageCircle className="h-3 w-3" aria-hidden /> WhatsApp
        </a>
      )}
      {contato.email && (
        <a href={`mailto:${contato.email}`} className="break-all hover:text-foreground hover:underline">{contato.email}</a>
      )}
    </p>
  );
}
