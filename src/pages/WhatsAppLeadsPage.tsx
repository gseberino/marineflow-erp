import { useState, useMemo, useEffect, useRef } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import {
  MessageCircle, UserPlus, Link2, Trash2, Phone, Send, Ban, Search, ArrowLeft,
  Plus, Zap, ShieldOff, AlertCircle, CheckCircle2,
} from 'lucide-react';
import {
  useWhatsAppLeads, useWhatsAppLeadMessages,
  useConvertLeadToClient, useLinkLeadToClient, useDiscardLead,
} from '@/hooks/use-whatsapp-leads';
import {
  useWhatsAppConversations, useSendWhatsAppText, useMarkConversationRead,
  useBlockedNumbers, useAddBlockedNumber, useRemoveBlockedNumber,
  useQuickReplies, useUpsertQuickReply, useDeleteQuickReply,
  useCreateWhatsAppLead, useLinkConversationToClient,
} from '@/hooks/use-whatsapp-inbox';
import { useClients } from '@/hooks/use-clients';
import { useI18n } from '@/i18n';

function formatPhone(p: string) {
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

function outboundStatusLabel(status: string | null | undefined): string {
  switch (status) {
    case 'read': case 'played': case 'read_by_me': return '✓✓';
    case 'delivered': return '✓✓';
    case 'failed': return 'Falhou';
    default: return '✓';
  }
}

function formatConvTime(at: string | null | undefined) {
  if (!at) return '';
  const d = new Date(at);
  const now = new Date();
  const isToday = d.toDateString() === now.toDateString();
  return isToday
    ? d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })
    : d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
}

// =============== INBOX ===============
function InboxView() {
  const { data: conversations, isLoading } = useWhatsAppConversations();
  const [activePhone, setActivePhone] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [draft, setDraft] = useState('');
  const [showLinkConfirm, setShowLinkConfirm] = useState(false);
  const sendMut = useSendWhatsAppText();
  const markRead = useMarkConversationRead();
  const addBlocked = useAddBlockedNumber();
  const createLead = useCreateWhatsAppLead();
  const linkToClient = useLinkConversationToClient();
  const { data: messages } = useWhatsAppLeadMessages(activePhone || undefined);
  const { data: quickReplies } = useQuickReplies();
  const scrollRef = useRef<HTMLDivElement>(null);

  const filtered = useMemo(() => {
    const list = conversations || [];
    if (!search.trim()) return list;
    const q = search.toLowerCase();
    return list.filter((c: any) =>
      (c.name || '').toLowerCase().includes(q) ||
      (c.suggested_client?.name || '').toLowerCase().includes(q) ||
      c.phone.includes(q.replace(/\D/g, '')),
    );
  }, [conversations, search]);

  const active = useMemo(
    () => filtered.find((c: any) => c.phone === activePhone) || null,
    [filtered, activePhone],
  );

  useEffect(() => {
    if (activePhone) markRead.mutate(activePhone);
    setShowLinkConfirm(false);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activePhone]);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight });
  }, [messages]);

  const send = async () => {
    if (!activePhone || !draft.trim()) return;
    await sendMut.mutateAsync({ phone: activePhone, message: draft.trim() });
    setDraft('');
  };

  const block = async () => {
    if (!activePhone) return;
    if (!confirm('Bloquear este número? Não receberá mais mensagens registradas.')) return;
    await addBlocked.mutateAsync({ phone: activePhone, reason: 'Bloqueado pelo inbox' });
    setActivePhone(null);
  };

  const handleLinkToSuggestedClient = async () => {
    if (!active?.suggested_client) return;
    await linkToClient.mutateAsync({
      phone: active.phone,
      clientId: active.suggested_client.id,
      clientName: active.suggested_client.name,
    });
    setShowLinkConfirm(false);
  };

  const handleCreateLead = async () => {
    if (!active) return;
    await createLead.mutateAsync({
      phone: active.phone,
      displayName: active.name || null,
    });
  };

  // Determine link status for active conversation
  const isLinkedToClient = active && (active.client_id || active.lead_status === 'linked');
  const hasSuggestion = active && active.suggested_client && !isLinkedToClient;
  const isUnlinked = active && !isLinkedToClient && !active.suggested_client && !active.lead_status;

  return (
    <div className="grid md:grid-cols-[320px_1fr] gap-3 h-[calc(100vh-220px)] min-h-[500px]">
      {/* Lista de conversas */}
      <div className={`rounded-xl border bg-card flex flex-col ${activePhone ? 'hidden md:flex' : 'flex'}`}>
        <div className="p-3 border-b">
          <div className="relative">
            <Search className="h-4 w-4 absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
            <Input
              placeholder="Buscar nome ou telefone…"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="pl-9"
            />
          </div>
        </div>
        <div className="flex-1 overflow-y-auto">
          {isLoading ? (
            <div className="p-3 space-y-2">
              {Array.from({ length: 5 }).map((_, i) => <Skeleton key={i} className="h-14 w-full" />)}
            </div>
          ) : filtered.length === 0 ? (
            <div className="p-8 text-center text-sm text-muted-foreground">
              <MessageCircle className="h-8 w-8 mx-auto mb-2 opacity-50" />
              Nenhuma conversa.
            </div>
          ) : (
            filtered.map((c: any) => {
              // Determine display name for list item
              const displayName = c.name || (c.suggested_client ? c.suggested_client.name : null);
              // Determine badge state
              const linkedToClient = !!(c.client_id);
              const linkedViaLead = c.lead_status === 'linked';
              const isPendingLead = c.lead_status === 'pending';
              const hasSuggestedClient = !!c.suggested_client && !linkedToClient && !linkedViaLead;
              const isPending = !linkedToClient && !linkedViaLead && !isPendingLead && !hasSuggestedClient;

              return (
                <button
                  key={c.phone}
                  onClick={() => setActivePhone(c.phone)}
                  className={`w-full text-left px-3 py-3 border-b hover:bg-muted/50 transition-colors ${
                    activePhone === c.phone ? 'bg-muted' : ''
                  }`}
                >
                  <div className="flex items-center justify-between gap-2">
                    <span className="font-medium text-sm truncate">
                      {displayName || formatPhone(c.phone)}
                    </span>
                    <div className="flex flex-col items-end shrink-0">
                      <span className="text-[10px] text-muted-foreground">{formatConvTime(c.last_at)}</span>
                      {c.unread_count > 0 && (
                        <Badge className="bg-primary text-primary-foreground h-5 min-w-5 px-1.5 text-[10px] mt-0.5">
                          {c.unread_count}
                        </Badge>
                      )}
                    </div>
                  </div>
                  <p className="text-xs text-muted-foreground truncate mt-0.5">
                    {c.last_direction === 'outbound' ? '✓ ' : ''}
                    {c.last_body || '—'}
                  </p>
                  <div className="flex items-center gap-1 mt-1 flex-wrap">
                    {linkedToClient && (
                      <Badge variant="outline" className="text-[9px] py-0 border-emerald-500 text-emerald-700">Cliente</Badge>
                    )}
                    {!linkedToClient && linkedViaLead && (
                      <Badge variant="outline" className="text-[9px] py-0 border-blue-500 text-blue-700">Vinculado</Badge>
                    )}
                    {isPendingLead && (
                      <Badge variant="outline" className="text-[9px] py-0 border-amber-500 text-amber-700">Lead</Badge>
                    )}
                    {hasSuggestedClient && (
                      <Badge variant="outline" className="text-[9px] py-0 border-sky-500 text-sky-700">Possível vínculo</Badge>
                    )}
                    {isPending && (
                      <Badge variant="outline" className="text-[9px] py-0 border-gray-400 text-gray-500">Pendente</Badge>
                    )}
                    {c.is_broadcast && (
                      <Badge variant="outline" className="text-[9px] py-0">Broadcast</Badge>
                    )}
                  </div>
                </button>
              );
            })
          )}
        </div>
      </div>

      {/* Painel de conversa */}
      <div className={`rounded-xl border bg-card flex flex-col ${!activePhone ? 'hidden md:flex' : 'flex'}`}>
        {!active ? (
          <div className="flex-1 flex items-center justify-center text-muted-foreground">
            <div className="text-center">
              <MessageCircle className="h-12 w-12 mx-auto mb-3 opacity-40" />
              <p>Selecione uma conversa</p>
            </div>
          </div>
        ) : (
          <>
            <div className="p-3 border-b flex items-center justify-between gap-2">
              <div className="flex items-center gap-2 min-w-0">
                <Button variant="ghost" size="icon" className="md:hidden" onClick={() => setActivePhone(null)}>
                  <ArrowLeft className="h-4 w-4" />
                </Button>
                <div className="min-w-0">
                  <p className="font-semibold truncate">{active.name || formatPhone(active.phone)}</p>
                  <p className="text-xs text-muted-foreground">{formatPhone(active.phone)}</p>
                </div>
              </div>
              <Button variant="ghost" size="sm" onClick={block} className="text-destructive">
                <Ban className="h-3.5 w-3.5 mr-1" /> Bloquear
              </Button>
            </div>

            {/* Banner: Possível vínculo com cliente existente */}
            {hasSuggestion && !showLinkConfirm && (
              <div className="px-3 py-2 border-b bg-sky-50 dark:bg-sky-950/30 flex items-center justify-between gap-2">
                <div className="flex items-center gap-2 min-w-0">
                  <AlertCircle className="h-4 w-4 text-sky-600 shrink-0" />
                  <p className="text-xs text-sky-700 dark:text-sky-400 truncate">
                    Possível cliente: <strong>{active.suggested_client!.name}</strong>
                  </p>
                </div>
                <Button
                  size="sm"
                  variant="outline"
                  className="h-7 text-xs border-sky-500 text-sky-700 hover:bg-sky-100 shrink-0"
                  onClick={() => setShowLinkConfirm(true)}
                >
                  <Link2 className="h-3 w-3 mr-1" />
                  Vincular
                </Button>
              </div>
            )}

            {/* Banner: Confirmação de vínculo */}
            {hasSuggestion && showLinkConfirm && (
              <div className="px-3 py-2 border-b bg-sky-50 dark:bg-sky-950/30 flex items-center justify-between gap-2">
                <p className="text-xs text-sky-700 dark:text-sky-400">
                  Confirmar vínculo com <strong>{active.suggested_client!.name}</strong>?
                </p>
                <div className="flex gap-1 shrink-0">
                  <Button
                    size="sm"
                    variant="ghost"
                    className="h-7 text-xs"
                    onClick={() => setShowLinkConfirm(false)}
                  >
                    Cancelar
                  </Button>
                  <Button
                    size="sm"
                    className="h-7 text-xs bg-sky-600 hover:bg-sky-700"
                    onClick={handleLinkToSuggestedClient}
                    disabled={linkToClient.isPending}
                  >
                    <CheckCircle2 className="h-3 w-3 mr-1" />
                    Confirmar
                  </Button>
                </div>
              </div>
            )}

            {/* Banner: Conversa pendente sem nenhum vínculo */}
            {isUnlinked && (
              <div className="px-3 py-2 border-b bg-muted/50 flex items-center justify-between gap-2">
                <p className="text-xs text-muted-foreground">
                  Conversa pendente — número não vinculado a nenhum cadastro.
                </p>
                <Button
                  size="sm"
                  variant="outline"
                  className="h-7 text-xs shrink-0"
                  onClick={handleCreateLead}
                  disabled={createLead.isPending}
                >
                  <UserPlus className="h-3 w-3 mr-1" />
                  Criar lead
                </Button>
              </div>
            )}

            <div ref={scrollRef} className="flex-1 overflow-y-auto p-3 space-y-2 bg-muted/30">
              {(messages || []).length === 0 && (
                <p className="text-sm text-muted-foreground text-center py-8">Sem mensagens.</p>
              )}
              {(messages || []).map((m: any) => (
                <div key={m.id} className={`flex ${m.direction === 'outbound' ? 'justify-end' : 'justify-start'}`}>
                  <div
                    className={`max-w-[75%] rounded-2xl px-3 py-2 text-sm ${
                      m.direction === 'outbound'
                        ? 'bg-primary text-primary-foreground rounded-br-sm'
                        : 'bg-card border rounded-bl-sm'
                    }`}
                  >
                    <p className="whitespace-pre-wrap break-words">{m.body}</p>
                    <p className={`text-[10px] mt-1 opacity-70`}>
                      {new Date(m.occurred_at).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}
                      {m.direction === 'outbound' && (
                        <span className={m.delivery_status === 'read' || m.delivery_status === 'played' ? 'text-blue-400' : ''}>
                          {` · ${outboundStatusLabel(m.delivery_status)}`}
                        </span>
                      )}
                    </p>
                  </div>
                </div>
              ))}
            </div>

            {/* Quick replies */}
            {(quickReplies || []).length > 0 && (
              <div className="px-3 pt-2 flex gap-1 flex-wrap border-t">
                {(quickReplies || []).map((q: any) => (
                  <Button
                    key={q.id}
                    size="sm"
                    variant="outline"
                    className="h-7 text-xs"
                    onClick={() => setDraft((d) => (d ? `${d}\n${q.body}` : q.body))}
                  >
                    <Zap className="h-3 w-3 mr-1" />
                    {q.shortcut}
                  </Button>
                ))}
              </div>
            )}

            {/* Compositor */}
            <div className="p-3 border-t flex gap-2 items-end">
              <Textarea
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault();
                    send();
                  }
                }}
                placeholder="Escreva uma mensagem… (Enter envia, Shift+Enter quebra linha)"
                rows={2}
                className="resize-none"
              />
              <Button onClick={send} disabled={!draft.trim() || sendMut.isPending}>
                <Send className="h-4 w-4" />
              </Button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

// =============== LEADS (lista clássica) ===============
function LeadsView() {
  const [tab, setTab] = useState('pending');
  const [search, setSearch] = useState('');
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
  const addBlocked = useAddBlockedNumber();
  const { formatDate } = useI18n();
  const { data: messages } = useWhatsAppLeadMessages(selected?.phone_normalized);

  const filteredLeads = useMemo(() => {
    const list = leads || [];
    if (!search.trim()) return list;
    const q = search.toLowerCase();
    const digits = q.replace(/\D/g, '');
    return list.filter((l: any) =>
      (l.display_name || '').toLowerCase().includes(q) ||
      (digits.length >= 4 && l.phone_normalized.includes(digits)),
    );
  }, [leads, search]);

  const statusBadge = (s: string) => {
    const map: Record<string, string> = {
      pending: 'bg-amber-100 text-amber-800',
      linked: 'bg-blue-100 text-blue-800',
      converted: 'bg-emerald-100 text-emerald-800',
      discarded: 'bg-muted text-muted-foreground',
    };
    const label: Record<string, string> = {
      pending: 'Aguardando', linked: 'Vinculado', converted: 'Convertido', discarded: 'Descartado',
    };
    return <Badge className={map[s] || ''}>{label[s] || s}</Badge>;
  };

  return (
    <>
      <div className="mb-4 relative max-w-xs">
        <Search className="h-4 w-4 absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
        <Input
          placeholder="Buscar por nome ou telefone…"
          value={search}
          onChange={e => setSearch(e.target.value)}
          className="pl-9"
        />
      </div>
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
            <div className="space-y-2">{Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-20 w-full" />)}</div>
          ) : !filteredLeads?.length ? (
            <div className="rounded-xl border bg-card p-12 text-center space-y-2">
              <MessageCircle className="h-10 w-10 mx-auto text-muted-foreground" />
              <p className="text-muted-foreground">{search.trim() ? 'Nenhum lead encontrado para a busca.' : 'Nenhum lead.'}</p>
            </div>
          ) : (
            <div className="grid gap-3 md:grid-cols-2">
              {filteredLeads.map((lead: any) => (
                <div key={lead.id} className="rounded-xl border bg-card p-4 hover:shadow-md transition-shadow">
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <h3 className="font-semibold truncate">{lead.display_name || 'Contato sem nome'}</h3>
                        {statusBadge(lead.status)}
                        {lead.is_broadcast && <Badge variant="outline" className="text-[10px]">Broadcast</Badge>}
                      </div>
                      <p className="text-xs text-muted-foreground flex items-center gap-1 mt-0.5">
                        <Phone className="h-3 w-3" />{formatPhone(lead.phone_normalized)}
                      </p>
                    </div>
                    <div className="text-right shrink-0">
                      <p className="text-xs text-muted-foreground">{formatDate(lead.last_message_at)}</p>
                      <p className="text-xs text-muted-foreground">{lead.message_count} msgs</p>
                    </div>
                  </div>
                  {lead.first_message && (
                    <p className="mt-3 text-sm text-muted-foreground line-clamp-2 italic">"{lead.first_message}"</p>
                  )}
                  {lead.linked_client && (
                    <p className="mt-2 text-xs text-blue-700">→ {lead.linked_client.full_name_or_company_name}</p>
                  )}
                  <div className="mt-3 flex flex-wrap gap-2">
                    <Button size="sm" variant="outline" onClick={() => setSelected(lead)}>Ver mensagens</Button>
                    {lead.status === 'pending' && (
                      <>
                        <Button size="sm" onClick={() => { setSelected(lead); setConvertName(lead.display_name || ''); setConvertOpen(true); }}><UserPlus className="h-3.5 w-3.5 mr-1" />Converter</Button>
                        <Button size="sm" variant="secondary" onClick={() => { setSelected(lead); setLinkClientId(null); setLinkOpen(true); }}><Link2 className="h-3.5 w-3.5 mr-1" />Vincular</Button>
                        <Button size="sm" variant="ghost" onClick={() => discardMut.mutate(lead.id)} className="text-destructive"><Trash2 className="h-3.5 w-3.5 mr-1" />Descartar</Button>
                        <Button size="sm" variant="ghost" onClick={() => addBlocked.mutate({ phone: lead.phone_normalized, reason: 'Bloqueado da lista de leads' })} className="text-destructive"><Ban className="h-3.5 w-3.5 mr-1" />Bloquear</Button>
                      </>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
        </TabsContent>
      </Tabs>

      <Dialog open={!!selected && !convertOpen && !linkOpen} onOpenChange={(v) => !v && setSelected(null)}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle>{selected?.display_name || 'Contato'} — {formatPhone(selected?.phone_normalized || '')}</DialogTitle>
          </DialogHeader>
          <div className="max-h-[60vh] overflow-y-auto space-y-2 p-1">
            {messages?.length === 0 && <p className="text-sm text-muted-foreground text-center py-8">Sem mensagens.</p>}
            {messages?.map((m: any) => (
              <div key={m.id} className={`p-2 rounded-lg text-sm ${m.direction === 'inbound' ? 'bg-muted mr-12' : 'bg-primary/10 ml-12 text-right'}`}>
                <p>{m.body}</p>
                <p className="text-[10px] text-muted-foreground mt-1">{new Date(m.occurred_at).toLocaleString('pt-BR')} • {m.delivery_status}</p>
              </div>
            ))}
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={convertOpen} onOpenChange={setConvertOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>Converter lead em cliente</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div>
              <label className="text-sm font-medium">Nome / Razão social</label>
              <Input value={convertName} onChange={(e) => setConvertName(e.target.value)} />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setConvertOpen(false)}>Cancelar</Button>
            <Button onClick={async () => { if (!selected) return; await convertMut.mutateAsync({ leadId: selected.id, fullName: convertName.trim() }); setConvertOpen(false); setSelected(null); }} disabled={!convertName.trim()}>Converter</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={linkOpen} onOpenChange={setLinkOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>Vincular a cliente existente</DialogTitle></DialogHeader>
          <Select value={linkClientId || ''} onValueChange={setLinkClientId}>
            <SelectTrigger><SelectValue placeholder="Selecione um cliente..." /></SelectTrigger>
            <SelectContent>{(clients || []).map((c: any) => <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>)}</SelectContent>
          </Select>
          <DialogFooter>
            <Button variant="outline" onClick={() => setLinkOpen(false)}>Cancelar</Button>
            <Button onClick={async () => { if (!selected || !linkClientId) return; await linkMut.mutateAsync({ leadId: selected.id, clientId: linkClientId }); setLinkOpen(false); setSelected(null); }} disabled={!linkClientId}>Vincular</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

// =============== BLOCKLIST ===============
function BlocklistView() {
  const { data: blocked, isLoading } = useBlockedNumbers();
  const addMut = useAddBlockedNumber();
  const removeMut = useRemoveBlockedNumber();
  const [phone, setPhone] = useState('');
  const [reason, setReason] = useState('');

  return (
    <div className="space-y-4">
      <div className="rounded-xl border bg-card p-4">
        <p className="text-sm font-medium mb-2">Adicionar número à blocklist</p>
        <p className="text-xs text-muted-foreground mb-3">Mensagens vindas destes números serão ignoradas (não criam leads nem notificam).</p>
        <div className="grid md:grid-cols-[1fr_2fr_auto] gap-2">
          <Input placeholder="Ex: 5521999998888" value={phone} onChange={(e) => setPhone(e.target.value)} />
          <Input placeholder="Motivo (opcional): lista de transmissão de fornecedor X…" value={reason} onChange={(e) => setReason(e.target.value)} />
          <Button onClick={async () => { await addMut.mutateAsync({ phone, reason }); setPhone(''); setReason(''); }} disabled={!phone || addMut.isPending}>
            <Plus className="h-4 w-4 mr-1" />Bloquear
          </Button>
        </div>
      </div>

      <div className="rounded-xl border bg-card">
        {isLoading ? (
          <div className="p-4 space-y-2">{Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-10 w-full" />)}</div>
        ) : !blocked?.length ? (
          <p className="p-8 text-center text-sm text-muted-foreground">Nenhum número bloqueado.</p>
        ) : (
          <div className="divide-y">
            {blocked.map((b: any) => (
              <div key={b.id} className="p-3 flex items-center justify-between gap-2">
                <div className="min-w-0">
                  <p className="font-medium text-sm">{formatPhone(b.phone_normalized)}</p>
                  {b.reason && <p className="text-xs text-muted-foreground truncate">{b.reason}</p>}
                </div>
                <Button size="sm" variant="ghost" onClick={() => removeMut.mutate(b.id)} className="text-destructive">
                  <ShieldOff className="h-3.5 w-3.5 mr-1" />Desbloquear
                </Button>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

// =============== QUICK REPLIES ===============
function QuickRepliesView() {
  const { data: items, isLoading } = useQuickReplies();
  const upsert = useUpsertQuickReply();
  const del = useDeleteQuickReply();
  const [shortcut, setShortcut] = useState('');
  const [body, setBody] = useState('');

  return (
    <div className="space-y-4">
      <div className="rounded-xl border bg-card p-4 space-y-2">
        <p className="text-sm font-medium">Nova resposta rápida</p>
        <div className="grid md:grid-cols-[180px_1fr] gap-2">
          <Input placeholder="Atalho (ex: ola)" value={shortcut} onChange={(e) => setShortcut(e.target.value)} />
          <Textarea placeholder="Texto que será inserido…" value={body} onChange={(e) => setBody(e.target.value)} rows={2} />
        </div>
        <Button onClick={async () => { await upsert.mutateAsync({ shortcut, body }); setShortcut(''); setBody(''); }} disabled={!shortcut.trim() || !body.trim()}>
          <Plus className="h-4 w-4 mr-1" />Adicionar
        </Button>
      </div>

      <div className="rounded-xl border bg-card">
        {isLoading ? <div className="p-4 space-y-2">{Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-12" />)}</div>
          : !items?.length ? <p className="p-8 text-center text-sm text-muted-foreground">Nenhuma resposta rápida.</p>
          : <div className="divide-y">{items.map((q: any) => (
              <div key={q.id} className="p-3 flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <p className="font-medium text-sm">/{q.shortcut}</p>
                  <p className="text-xs text-muted-foreground whitespace-pre-wrap">{q.body}</p>
                </div>
                <Button size="sm" variant="ghost" onClick={() => del.mutate(q.id)} className="text-destructive">
                  <Trash2 className="h-3.5 w-3.5" />
                </Button>
              </div>
            ))}</div>
        }
      </div>
    </div>
  );
}

// =============== PAGE ===============
export default function WhatsAppLeadsPage() {
  const [view, setView] = useState('inbox');
  return (
    <div className="space-y-4 animate-fade-in">
      <PageHeader
        title="WhatsApp"
        description="Inbox de conversas, leads, blocklist e respostas rápidas."
      />
      <Tabs value={view} onValueChange={setView}>
        <TabsList>
          <TabsTrigger value="inbox">Inbox</TabsTrigger>
          <TabsTrigger value="leads">Leads</TabsTrigger>
          <TabsTrigger value="blocklist">Bloqueados</TabsTrigger>
          <TabsTrigger value="quick">Respostas rápidas</TabsTrigger>
        </TabsList>
        <TabsContent value="inbox" className="mt-4"><InboxView /></TabsContent>
        <TabsContent value="leads" className="mt-4"><LeadsView /></TabsContent>
        <TabsContent value="blocklist" className="mt-4"><BlocklistView /></TabsContent>
        <TabsContent value="quick" className="mt-4"><QuickRepliesView /></TabsContent>
      </Tabs>
    </div>
  );
}
