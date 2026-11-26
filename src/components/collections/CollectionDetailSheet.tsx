// 26/11/2026 (dono: "1. A"): o "Enviar via WhatsApp" daqui mandava o modelo com o valor guardado na cobrança, sem
// trava nenhuma. Agora "Cobrar o cliente" abre a cobrança do cliente com a conferência da ficha (CobrarClienteDialog).
import { useState } from 'react';
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { MessageCircle, Pencil, Plus } from 'lucide-react';
import {
  useCollection, useCollectionContacts, useUpdateCollection,
  type CollectionStatus,
} from '@/hooks/use-collections';
import { CobrarClienteDialog } from '@/components/client/CobrarClienteDialog';
import { CollectionStatusBadge, COLLECTION_STATUS_OPTIONS } from './CollectionStatusBadge';
import { ContactHistoryTimeline } from './ContactHistoryTimeline';
import { AddContactDialog } from './AddContactDialog';
import { EditContactDialog } from './EditContactDialog';

interface Props { collectionId: string | null; onClose: () => void }

export function CollectionDetailSheet({ collectionId, onClose }: Props) {
  const open = !!collectionId;
  const { data: collection } = useCollection(collectionId || undefined);
  const { data: contacts } = useCollectionContacts(collectionId || undefined);
  const update = useUpdateCollection();

  const [editContact, setEditContact] = useState(false);
  const [addContact, setAddContact] = useState(false);
  const [cobrar, setCobrar] = useState(false);

  if (!collection) {
    return (
      <Sheet open={open} onOpenChange={(v) => !v && onClose()}>
        <SheetContent className="sm:max-w-xl w-full overflow-y-auto" />
      </Sheet>
    );
  }

  return (
    <>
      <Sheet open={open} onOpenChange={(v) => !v && onClose()}>
        <SheetContent className="sm:max-w-xl w-full overflow-y-auto">
          <SheetHeader>
            <SheetTitle>{collection.client?.name || 'Cliente'}</SheetTitle>
            <SheetDescription>
              {collection.service_order?.service_order_number || 'Avulso'} •
              {' '}R$ {Number(collection.amount).toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
              {' '}• Vence {new Date(collection.due_date).toLocaleDateString('pt-BR')}
            </SheetDescription>
          </SheetHeader>

          <div className="mt-6 space-y-6">
            <div className="flex items-center gap-3">
              <CollectionStatusBadge status={collection.status} />
              <Select
                value={collection.status}
                onValueChange={(v) =>
                  update.mutate({ id: collection.id, patch: { status: v as CollectionStatus } })
                }
              >
                <SelectTrigger className="h-8 w-40 text-xs"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {COLLECTION_STATUS_OPTIONS.map(opt => (
                    <SelectItem key={opt.value} value={opt.value}>{opt.label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="rounded-lg border p-3 space-y-1">
              <div className="flex items-center justify-between">
                <Label className="text-sm font-semibold">Contato</Label>
                <Button variant="ghost" size="sm" onClick={() => setEditContact(true)}>
                  <Pencil className="h-3.5 w-3.5 mr-1" /> Editar
                </Button>
              </div>
              <p className="text-sm">{collection.contact_name || collection.client?.name}</p>
              <p className="text-xs text-muted-foreground">
                Tel: {collection.phone || collection.client?.phone || '—'} •
                {' '}WhatsApp: {collection.contact_whatsapp || collection.client?.whatsapp || '—'}
              </p>
            </div>

            <div className="space-y-2">
              <Label>Cobrar pelo WhatsApp</Label>
              <p className="text-xs text-muted-foreground">
                A mensagem vai com tudo que o cliente tem em aberto, só para o WhatsApp do cadastro e com as travas da
                ficha (entrada esperando no Extrato, piso, horário, opt-out). Você confere antes de enviar.
              </p>
              <Button
                className="w-full gap-2"
                disabled={!collection.client_id || collection.status === 'paid' || collection.status === 'cancelled'}
                onClick={() => setCobrar(true)}
              >
                <MessageCircle className="h-4 w-4" /> Cobrar o cliente
              </Button>
              {!collection.client_id && (
                <p className="text-xs text-destructive">Esta cobrança não está ligada a um cliente do cadastro: ligue-a a um cliente para cobrar pelo WhatsApp.</p>
              )}
            </div>

            <div className="space-y-3 border-t pt-4">
              <div className="flex items-center justify-between">
                <Label className="text-sm font-semibold">Histórico de Contatos</Label>
                <Button variant="outline" size="sm" onClick={() => setAddContact(true)}>
                  <Plus className="h-3.5 w-3.5 mr-1" /> Registrar
                </Button>
              </div>
              <ContactHistoryTimeline items={contacts || []} />
            </div>
          </div>
        </SheetContent>
      </Sheet>

      <AddContactDialog open={addContact} onOpenChange={setAddContact} collectionId={collection.id} />
      <EditContactDialog open={editContact} onOpenChange={setEditContact} collection={collection} />
      <CobrarClienteDialog clienteId={cobrar ? collection.client_id || null : null} onFechar={() => setCobrar(false)} />
    </>
  );
}
