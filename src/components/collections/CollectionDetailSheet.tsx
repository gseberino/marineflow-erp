import { useEffect, useMemo, useState } from 'react';
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { MessageCircle, Pencil, Plus } from 'lucide-react';
import {
  useCollection, useCollectionContacts, useCollectionTemplates,
  useUpdateCollection, useSendCollectionWhatsApp, renderTemplate,
  type CollectionStatus,
} from '@/hooks/use-collections';
import { useAppSettings } from '@/hooks/use-app-settings';
import { CollectionStatusBadge, COLLECTION_STATUS_OPTIONS } from './CollectionStatusBadge';
import { ContactHistoryTimeline } from './ContactHistoryTimeline';
import { AddContactDialog } from './AddContactDialog';
import { EditContactDialog } from './EditContactDialog';

interface Props { collectionId: string | null; onClose: () => void }

export function CollectionDetailSheet({ collectionId, onClose }: Props) {
  const open = !!collectionId;
  const { data: collection } = useCollection(collectionId || undefined);
  const { data: contacts } = useCollectionContacts(collectionId || undefined);
  const { data: templates } = useCollectionTemplates();
  const { data: settings } = useAppSettings();
  const update = useUpdateCollection();
  const send = useSendCollectionWhatsApp();

  const [templateId, setTemplateId] = useState('');
  const [editContact, setEditContact] = useState(false);
  const [addContact, setAddContact] = useState(false);

  useEffect(() => {
    if (templates?.length && !templateId) {
      setTemplateId((templates.find(t => t.is_default) || templates[0]).id);
    }
  }, [templates, templateId]);

  const selectedTpl = templates?.find(t => t.id === templateId);

  const preview = useMemo(() => {
    if (!collection || !selectedTpl) return '';
    return renderTemplate(selectedTpl.body, {
      nome: collection.contact_name || collection.client?.name || 'Cliente',
      numero_os: collection.service_order?.service_order_number || 'Avulso',
      valor: Number(collection.amount),
      vencimento: collection.due_date,
      pix: settings?.['pix_key'] || settings?.['company_pix'] || '',
      empresa: settings?.['company_name'] || 'HBR Marine',
    });
  }, [collection, selectedTpl, settings]);

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
              <Label>Template</Label>
              <Select value={templateId} onValueChange={setTemplateId}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {(templates || []).map(t => (
                    <SelectItem key={t.id} value={t.id}>{t.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <div className="rounded-lg bg-muted p-3 text-sm whitespace-pre-wrap font-mono max-h-48 overflow-y-auto">
                {preview}
              </div>
              <Button
                className="w-full bg-green-600 hover:bg-green-700 text-white"
                disabled={send.isPending}
                onClick={() => send.mutate({ collection, template: selectedTpl })}
              >
                <MessageCircle className="h-4 w-4 mr-2" />
                {send.isPending ? 'Enviando...' : 'Enviar via WhatsApp'}
              </Button>
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
    </>
  );
}
