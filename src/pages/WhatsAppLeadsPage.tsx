import { useState } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter,
} from '@/components/ui/dialog';
import {
  Tabs, TabsList, TabsTrigger, TabsContent,
} from '@/components/ui/tabs';
import { MessageCircle, UserPlus, Link2, Trash2, Phone } from 'lucide-react';
import {
  useWhatsAppLeads, useWhatsAppLeadMessages,
  useConvertLeadToClient, useLinkLeadToClient, useDiscardLead,
} from '@/hooks/use-whatsapp-leads';
import { useClients } from '@/hooks/use-clients';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import { useI18n } from '@/i18n';

function formatPhone(p: string) {
  // 5521999998888 → +55 (21) 99999-8888 (best-effort)
  if (!p) return '';
  if (p.length >= 12) {
    const ddi = p.slice(0, 2);
    const ddd = p.slice(2, 4);
    const rest = p.slice(4);
    const mid = rest.length > 4 ? rest.slice(0, rest.length - 4) : rest;
    const tail = rest.slice(-4);
    return `+${ddi} (${ddd}) ${mid}-${tail}`;
  }
  return p;
}

export default function WhatsAppLeadsPage() {
  const [tab, setTab] = useState('pending');
  const { data: leads, isLoading } = useWhatsAppLeads(tab);
  const [selected, setSelected] = useState<any | null>(null);
  const [convertOpen, setConvertOpen] = useState(false);
  const [linkOpen, setLinkOpen] = useState(false);
  const [convertName, setConvertName] = useState('');
  const [linkClientId, setLinkClientId] = useState<string | null>(null);
  const { data: clients } = useClients();
  const convertMut = useConvertLeadToClient();
  const linkMut = useLinkLeadToClient();
  const discardMut = useDiscardLead();
  const { formatDate } = useI18n();

  const { data: messages } = useWhatsAppLeadMessages(selected?.phone_normalized);

  const openConvert = (lead: any) => {
    setSelected(lead);
    setConvertName(lead.display_name || '');
    setConvertOpen(true);
  };
  const openLink = (lead: any) => {
    setSelected(lead);
    setLinkClientId(null);
    setLinkOpen(true);
  };

  const statusBadge = (s: string) => {
    const map: Record<string, string> = {
      pending: 'bg-amber-100 text-amber-800',
      linked: 'bg-blue-100 text-blue-800',
      converted: 'bg-emerald-100 text-emerald-800',
      discarded: 'bg-muted text-muted-foreground',
    };
    const label: Record<string, string> = {
      pending: 'Aguardando',
      linked: 'Vinculado',
      converted: 'Convertido',
      discarded: 'Descartado',
    };
    return <Badge className={map[s] || ''}>{label[s] || s}</Badge>;
  };

  return (
    <div className="space-y-4 animate-fade-in">
      <PageHeader
        title="Leads do WhatsApp"
        description="Mensagens recebidas de números não cadastrados aguardando aprovação."
      />

      <Tabs value={tab} onValueChange={setTab}>
        <TabsList>
          <TabsTrigger value="pending">Pendentes</TabsTrigger>
          <TabsTrigger value="linked">Vinculados</TabsTrigger>
          <TabsTrigger value="converted">Convertidos</TabsTrigger>
          <TabsTrigger value="discarded">Descartados</TabsTrigger>
          <TabsTrigger value="all">Todos</TabsTrigger>
        </TabsList>

        <TabsContent value={tab} className="mt-4">
          {isLoading ? (
            <div className="space-y-2">
              {Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-20 w-full" />)}
            </div>
          ) : !leads?.length ? (
            <div className="rounded-xl border bg-card p-12 text-center space-y-2">
              <MessageCircle className="h-10 w-10 mx-auto text-muted-foreground" />
              <p className="text-muted-foreground">Nenhum lead nesta categoria.</p>
            </div>
          ) : (
            <div className="grid gap-3 md:grid-cols-2">
              {leads.map((lead: any) => (
                <div key={lead.id} className="rounded-xl border bg-card p-4 hover:shadow-md transition-shadow">
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <h3 className="font-semibold truncate">
                          {lead.display_name || 'Contato sem nome'}
                        </h3>
                        {statusBadge(lead.status)}
                      </div>
                      <p className="text-xs text-muted-foreground flex items-center gap-1 mt-0.5">
                        <Phone className="h-3 w-3" />
                        {formatPhone(lead.phone_normalized)}
                      </p>
                    </div>
                    <div className="text-right shrink-0">
                      <p className="text-xs text-muted-foreground">
                        {formatDate(lead.last_message_at)}
                      </p>
                      <p className="text-xs text-muted-foreground">{lead.message_count} msgs</p>
                    </div>
                  </div>
                  {lead.first_message && (
                    <p className="mt-3 text-sm text-muted-foreground line-clamp-2 italic">
                      "{lead.first_message}"
                    </p>
                  )}
                  {lead.linked_client && (
                    <p className="mt-2 text-xs text-blue-700">
                      → {lead.linked_client.full_name_or_company_name}
                    </p>
                  )}
                  <div className="mt-3 flex flex-wrap gap-2">
                    <Button size="sm" variant="outline" onClick={() => setSelected(lead)}>
                      Ver mensagens
                    </Button>
                    {lead.status === 'pending' && (
                      <>
                        <Button size="sm" onClick={() => openConvert(lead)} className="gap-1">
                          <UserPlus className="h-3.5 w-3.5" /> Converter
                        </Button>
                        <Button size="sm" variant="secondary" onClick={() => openLink(lead)} className="gap-1">
                          <Link2 className="h-3.5 w-3.5" /> Vincular
                        </Button>
                        <Button
                          size="sm"
                          variant="ghost"
                          onClick={() => discardMut.mutate(lead.id)}
                          className="gap-1 text-destructive hover:text-destructive"
                        >
                          <Trash2 className="h-3.5 w-3.5" /> Descartar
                        </Button>
                      </>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
        </TabsContent>
      </Tabs>

      {/* Modal de mensagens */}
      <Dialog open={!!selected && !convertOpen && !linkOpen} onOpenChange={(v) => !v && setSelected(null)}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle>
              {selected?.display_name || 'Contato'} — {formatPhone(selected?.phone_normalized || '')}
            </DialogTitle>
          </DialogHeader>
          <div className="max-h-[60vh] overflow-y-auto space-y-2 p-1">
            {messages?.length === 0 && (
              <p className="text-sm text-muted-foreground text-center py-8">Sem mensagens.</p>
            )}
            {messages?.map((m: any) => (
              <div
                key={m.id}
                className={`p-2 rounded-lg text-sm ${
                  m.direction === 'inbound'
                    ? 'bg-muted mr-12'
                    : 'bg-primary/10 ml-12 text-right'
                }`}
              >
                <p>{m.body}</p>
                <p className="text-[10px] text-muted-foreground mt-1">
                  {new Date(m.occurred_at).toLocaleString('pt-BR')} • {m.delivery_status}
                </p>
              </div>
            ))}
          </div>
        </DialogContent>
      </Dialog>

      {/* Converter em cliente */}
      <Dialog open={convertOpen} onOpenChange={setConvertOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Converter lead em cliente</DialogTitle>
          </DialogHeader>
          <div className="space-y-3">
            <div>
              <Label>Nome / Razão social</Label>
              <Input
                value={convertName}
                onChange={(e) => setConvertName(e.target.value)}
                placeholder="Nome completo do cliente"
              />
            </div>
            <p className="text-xs text-muted-foreground">
              O telefone {formatPhone(selected?.phone_normalized || '')} será usado como WhatsApp e telefone principal.
            </p>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setConvertOpen(false)}>Cancelar</Button>
            <Button
              onClick={async () => {
                if (!selected || !convertName.trim()) return;
                await convertMut.mutateAsync({ leadId: selected.id, fullName: convertName.trim() });
                setConvertOpen(false);
                setSelected(null);
              }}
              disabled={!convertName.trim() || convertMut.isPending}
            >
              Converter
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Vincular a cliente existente */}
      <Dialog open={linkOpen} onOpenChange={setLinkOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Vincular a cliente existente</DialogTitle>
          </DialogHeader>
          <div className="space-y-3">
            <Label>Cliente</Label>
            <Select value={linkClientId || ''} onValueChange={setLinkClientId}>
              <SelectTrigger>
                <SelectValue placeholder="Selecione um cliente..." />
              </SelectTrigger>
              <SelectContent>
                {(clients || []).map((c: any) => (
                  <SelectItem key={c.id} value={c.id}>{c.full_name_or_company_name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setLinkOpen(false)}>Cancelar</Button>
            <Button
              onClick={async () => {
                if (!selected || !linkClientId) return;
                await linkMut.mutateAsync({ leadId: selected.id, clientId: linkClientId });
                setLinkOpen(false);
                setSelected(null);
              }}
              disabled={!linkClientId || linkMut.isPending}
            >
              Vincular
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
