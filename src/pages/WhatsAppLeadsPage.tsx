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
  Plus, Zap, ShieldOff, ArrowDown, Check, CheckCheck, Mic, FileText, Settings,
} from 'lucide-react';
import {
  useWhatsAppLeads, useWhatsAppLeadMessages,
  useConvertLeadToClient, useLinkLeadToClient, useDiscardLead,
} from '@/hooks/use-whatsapp-leads';
import {
  useWhatsAppConversations, useSendWhatsAppText, useMarkConversationRead,
  useBlockedNumbers, useAddBlockedNumber, useRemoveBlockedNumber,
  useQuickReplies, useUpsertQuickReply, useDeleteQuickReply,
  useWhatsAppInboxRealtime,
} from '@/hooks/use-whatsapp-inbox';
import { useClients } from '@/hooks/use-clients';
import { useI18n } from '@/i18n';
import { WhatsAppWebhookValidator } from '@/components/WhatsAppWebhookValidator';
import { WhatsAppConnectionSettings } from '@/components/WhatsAppSettings';
import { WhatsAppReminderSettings } from '@/components/WhatsAppReminderSettings';
import { WhatsAppQueuePanel } from '@/components/WhatsAppQueuePanel';
import { WhatsAppTemplatesManager } from '@/components/WhatsAppTemplatesManager';

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

// ─── Helpers ────────────────────────────────────────────────────────────────

function playNotif() {
  try {
    const Ctx = window.AudioContext || (window as any).webkitAudioContext;
    if (!Ctx) return;
    const ctx = new Ctx();
    const o = ctx.createOscillator();
    const g = ctx.createGain();
    o.connect(g); g.connect(ctx.destination);
    o.type = 'sine';
    o.frequency.setValueAtTime(880, ctx.currentTime);
    o.frequency.exponentialRampToValueAtTime(660, ctx.currentTime + 0.15);
    g.gain.setValueAtTime(0.12, ctx.currentTime);
    g.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.45);
    o.start(); o.stop(ctx.currentTime + 0.45);
    ctx.close().catch(() => {});
  } catch { /* unsupported */ }
}

function relativeTime(iso: string): string {
  const ms = Date.now() - new Date(iso).getTime();
  const m = Math.floor(ms / 60_000);
  const h = Math.floor(ms / 3_600_000);
  const d = Math.floor(ms / 86_400_000);
  if (m < 1) return 'agora';
  if (m < 60) return `${m}min`;
  if (h < 24) return `${h}h`;
  if (d === 1) return 'ontem';
  return new Date(iso).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
}

function isSameDay(a: Date, b: Date) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

function getDateLabel(iso: string): string {
  const d = new Date(iso);
  const now = new Date();
  if (isSameDay(d, now)) return 'Hoje';
  const yd = new Date(now); yd.setDate(now.getDate() - 1);
  if (isSameDay(d, yd)) return 'Ontem';
  return d.toLocaleDateString('pt-BR');
}

function DateSeparator({ label }: { label: string }) {
  return (
    <div className="flex items-center gap-2 my-2 select-none">
      <div className="flex-1 h-px bg-border/50" />
      <span className="text-[11px] text-muted-foreground px-2 py-0.5 bg-muted rounded-full">{label}</span>
      <div className="flex-1 h-px bg-border/50" />
    </div>
  );
}

function DeliveryIcon({ status }: { status: string | null | undefined }) {
  if (status === 'read' || status === 'played')
    return <CheckCheck className="h-3 w-3 text-blue-300 inline ml-0.5 shrink-0" />;
  if (status === 'delivered')
    return <CheckCheck className="h-3 w-3 opacity-60 inline ml-0.5 shrink-0" />;
  return <Check className="h-3 w-3 opacity-60 inline ml-0.5 shrink-0" />;
}

function MessageBubble({ m }: { m: any }) {
  const isOut = m.direction === 'outbound';
  return (
    <div className={`flex ${isOut ? 'justify-end' : 'justify-start'}`}>
      <div className={`max-w-[75%] rounded-2xl px-3 py-2 text-sm shadow-sm ${
        isOut ? 'bg-primary text-primary-foreground rounded-br-sm' : 'bg-card border rounded-bl-sm'
      }`}>
        {/* Imagem inline */}
        {m.message_type === 'image' && m.media_url && (
          <img
            src={m.media_url}
            alt="imagem"
            className="max-w-full rounded-lg mb-1 max-h-48 object-contain cursor-zoom-in"
            loading="lazy"
            onError={(e) => { (e.currentTarget as HTMLImageElement).style.display = 'none'; }}
          />
        )}
        {/* Áudio */}
        {m.message_type === 'audio' && (
          <div className={`flex items-center gap-1.5 mb-0.5 ${isOut ? 'opacity-80' : 'text-muted-foreground'}`}>
            <Mic className="h-3.5 w-3.5 shrink-0" />
            <span className="text-xs italic">Mensagem de áudio</span>
          </div>
        )}
        {/* Documento */}
        {m.message_type === 'document' && (
          <div className={`flex items-center gap-1.5 mb-0.5 ${isOut ? 'opacity-80' : 'text-muted-foreground'}`}>
            <FileText className="h-3.5 w-3.5 shrink-0" />
            <span className="text-xs truncate max-w-[200px]">{m.body || 'Documento'}</span>
          </div>
        )}
        {/* Corpo da mensagem */}
        {m.body && m.message_type !== 'document' && (
          <p className="whitespace-pre-wrap break-words leading-snug">{m.body}</p>
        )}
        {/* Rodapé: hora + status */}
        <div className={`flex items-center gap-0.5 mt-0.5 ${isOut ? 'justify-end' : ''}`}>
          <span className={`text-[10px] leading-none ${isOut ? 'opacity-70' : 'text-muted-foreground'}`}>
            {new Date(m.occurred_at).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}
          </span>
          {isOut && <DeliveryIcon status={m.delivery_status} />}
        </div>
      </div>
    </div>
  );
}

// =============== INBOX ===============
function InboxView() {
  const { data: conversations, isLoading } = useWhatsAppConversations();
  const [activePhone, setActivePhone] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [draft, setDraft] = useState('');
  const sendMut = useSendWhatsAppText();
  const markRead = useMarkConversationRead();
  const addBlocked = useAddBlockedNumber();
  const { data: messages } = useWhatsAppLeadMessages(activePhone || undefined);
  const { data: quickReplies } = useQuickReplies();
  const scrollRef = useRef<HTMLDivElement>(null);
  const [showScrollDown, setShowScrollDown] = useState(false);
  const prevUnreadRef = useRef(0);
  const windowFocusedRef = useRef(true);

  // Rastreia foco da janela para decidir quando tocar som
  useEffect(() => {
    const onFocus = () => { windowFocusedRef.current = true; };
    const onBlur = () => { windowFocusedRef.current = false; };
    window.addEventListener('focus', onFocus);
    window.addEventListener('blur', onBlur);
    return () => { window.removeEventListener('focus', onFocus); window.removeEventListener('blur', onBlur); };
  }, []);

  // Realtime: invalida queries automaticamente e toca som em mensagens inbound novas
  useWhatsAppInboxRealtime((phone) => {
    if (!windowFocusedRef.current || phone !== activePhone) playNotif();
  });

  const scrollToBottom = (behavior: ScrollBehavior = 'auto') => {
    requestAnimationFrame(() => {
      const el = scrollRef.current;
      if (el) el.scrollTo({ top: el.scrollHeight, behavior });
    });
  };

  const handleScroll = () => {
    const el = scrollRef.current;
    if (!el) return;
    const distanceFromBottom = el.scrollHeight - el.scrollTop - el.clientHeight;
    setShowScrollDown(distanceFromBottom > 200);
  };

  const filtered = useMemo(() => {
    const list = conversations || [];
    if (!search.trim()) return list;
    const q = search.toLowerCase();
    return list.filter((c: any) =>
      (c.name || '').toLowerCase().includes(q) ||
      c.phone.includes(q.replace(/\D/g, '')),
    );
  }, [conversations, search]);

  const active = useMemo(
    () => filtered.find((c: any) => c.phone === activePhone) || null,
    [filtered, activePhone],
  );

  // Total de não lidas → badge no título da aba
  const totalUnread = useMemo(
    () => (conversations || []).reduce((s: number, c: any) => s + (c.unread_count || 0), 0),
    [conversations],
  );
  useEffect(() => {
    if (totalUnread > prevUnreadRef.current && prevUnreadRef.current >= 0) {
      if (!windowFocusedRef.current) playNotif();
    }
    prevUnreadRef.current = totalUnread;
    const bare = document.title.replace(/^\(\d+\) /, '');
    document.title = totalUnread > 0 ? `(${totalUnread}) ${bare}` : bare;
    return () => { document.title = document.title.replace(/^\(\d+\) /, ''); };
  }, [totalUnread]);

  // Lista de itens para renderização: separadores de data + mensagens
  const renderedMessages = useMemo(() => {
    const list = messages || [];
    const items: Array<{ kind: 'sep'; label: string } | { kind: 'msg'; m: any }> = [];
    let lastLabel = '';
    for (const m of list) {
      const label = getDateLabel(m.occurred_at);
      if (label !== lastLabel) { items.push({ kind: 'sep', label }); lastLabel = label; }
      items.push({ kind: 'msg', m });
    }
    return items;
  }, [messages]);

  useEffect(() => {
    if (activePhone) markRead.mutate(activePhone);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activePhone]);

  // Salta para a mensagem mais recente ao abrir a conversa ou quando chegam novas.
  useEffect(() => {
    scrollToBottom('auto');
    setShowScrollDown(false);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [messages, activePhone]);

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

  return (
    <div className="grid md:grid-cols-[320px_1fr] gap-3 h-[calc(100dvh-220px)] min-h-[500px]">
      {/* Lista de conversas */}
      <div className={`rounded-xl border bg-card flex flex-col min-h-0 ${activePhone ? 'hidden md:flex' : 'flex'}`}>
        <div className="p-3 border-b shrink-0">
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
        <div className="flex-1 min-h-0 overflow-y-auto wa-scroll">
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
            filtered.map((c: any) => (
              <button
                key={c.phone}
                onClick={() => setActivePhone(c.phone)}
                className={`w-full text-left px-3 py-3 border-b hover:bg-muted/50 transition-colors ${
                  activePhone === c.phone ? 'bg-muted' : ''
                }`}
              >
                <div className="flex items-center justify-between gap-2">
                  <span className="font-medium text-sm truncate">
                    {c.name || formatPhone(c.phone)}
                  </span>
                  <div className="flex items-center gap-1.5 shrink-0">
                    <span className="text-[10px] text-muted-foreground">{relativeTime(c.last_at)}</span>
                    {c.unread_count > 0 && (
                      <Badge className="bg-primary text-primary-foreground h-5 min-w-5 px-1.5 text-[10px]">
                        {c.unread_count}
                      </Badge>
                    )}
                  </div>
                </div>
                <p className="text-xs text-muted-foreground truncate mt-0.5">
                  {c.last_direction === 'outbound' && <Check className="h-3 w-3 opacity-50 inline mr-0.5" />}
                  {c.last_body || '—'}
                </p>
                <div className="flex items-center gap-1 mt-1">
                  {c.client_id && <Badge variant="outline" className="text-[9px] py-0">Cliente</Badge>}
                  {c.lead_status === 'pending' && <Badge variant="outline" className="text-[9px] py-0 border-amber-500 text-amber-700">Lead</Badge>}
                  {c.is_broadcast && <Badge variant="outline" className="text-[9px] py-0">Broadcast</Badge>}
                </div>
              </button>
            ))
          )}
        </div>
      </div>

      {/* Painel de conversa */}
      <div className={`relative rounded-xl border bg-card flex flex-col min-h-0 ${!activePhone ? 'hidden md:flex' : 'flex'}`}>
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

            <div ref={scrollRef} onScroll={handleScroll} className="flex-1 min-h-0 overflow-y-auto wa-scroll p-3 space-y-1 bg-muted/30">
              {renderedMessages.length === 0 && (
                <p className="text-sm text-muted-foreground text-center py-8">Sem mensagens.</p>
              )}
              {renderedMessages.map((item, i) =>
                item.kind === 'sep'
                  ? <DateSeparator key={`sep-${item.label}-${i}`} label={item.label} />
                  : <MessageBubble key={item.m.id} m={item.m} />
              )}
            </div>

            {/* Botão flutuante: ir para a mensagem mais recente */}
            {showScrollDown && (
              <button
                type="button"
                onClick={() => scrollToBottom('smooth')}
                aria-label="Ir para a mensagem mais recente"
                className="absolute right-5 bottom-28 z-10 h-10 w-10 rounded-full bg-primary text-primary-foreground shadow-lg flex items-center justify-center hover:opacity-90 transition-opacity"
              >
                <ArrowDown className="h-5 w-5" />
              </button>
            )}

            {/* Quick replies */}
            {(quickReplies || []).length > 0 && (
              <div className="px-3 pt-2 flex gap-1 flex-wrap border-t shrink-0">
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
            <div className="p-3 border-t flex gap-2 items-end shrink-0">
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
  const dialogScrollRef = useRef<HTMLDivElement>(null);

  // Ao abrir o histórico de um lead, rola para a mensagem mais recente.
  useEffect(() => {
    if (!selected || !messages) return;
    requestAnimationFrame(() => {
      const el = dialogScrollRef.current;
      if (el) el.scrollTo({ top: el.scrollHeight });
    });
  }, [messages, selected]);

  const filteredLeads = useMemo(() => {
    const list = leads || [];
    if (!search.trim()) return list;
    const q = search.toLowerCase();
    const digits = q.replace(/\D/g, '');
    return list.filter((l: any) =>
      (l.name || '').toLowerCase().includes(q) ||
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
                        <h3 className="font-semibold truncate">{lead.name || 'Contato sem nome'}</h3>
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
                    <p className="mt-2 text-xs text-blue-700">→ {lead.linked_client.name}</p>
                  )}
                  <div className="mt-3 flex flex-wrap gap-2">
                    <Button size="sm" variant="outline" onClick={() => setSelected(lead)}>Ver mensagens</Button>
                    {lead.status === 'pending' && (
                      <>
                        <Button size="sm" onClick={() => { setSelected(lead); setConvertName(lead.name || ''); setConvertOpen(true); }}><UserPlus className="h-3.5 w-3.5 mr-1" />Converter</Button>
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
            <DialogTitle>{selected?.name || 'Contato'} — {formatPhone(selected?.phone_normalized || '')}</DialogTitle>
          </DialogHeader>
          <div ref={dialogScrollRef} className="max-h-[60vh] overflow-y-auto space-y-1 p-1">
            {messages?.length === 0 && <p className="text-sm text-muted-foreground text-center py-8">Sem mensagens.</p>}
            {(() => {
              const items: Array<{ kind: 'sep'; label: string } | { kind: 'msg'; m: any }> = [];
              let lastLabel = '';
              for (const m of messages || []) {
                const label = getDateLabel(m.occurred_at);
                if (label !== lastLabel) { items.push({ kind: 'sep', label }); lastLabel = label; }
                items.push({ kind: 'msg', m });
              }
              return items.map((item, i) =>
                item.kind === 'sep'
                  ? <DateSeparator key={`sep-${item.label}-${i}`} label={item.label} />
                  : <MessageBubble key={item.m.id} m={item.m} />
              );
            })()}
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

// =============== SETTINGS ===============
function SettingsView() {
  return (
    <div className="space-y-6">
      <WhatsAppWebhookValidator />
      <WhatsAppConnectionSettings />
      <WhatsAppReminderSettings />
      <WhatsAppQueuePanel />
      <WhatsAppTemplatesManager />
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
          <TabsTrigger value="settings"><Settings className="h-3.5 w-3.5 mr-1.5 inline" />Configurações</TabsTrigger>
        </TabsList>
        <TabsContent value="inbox" className="mt-4"><InboxView /></TabsContent>
        <TabsContent value="leads" className="mt-4"><LeadsView /></TabsContent>
        <TabsContent value="blocklist" className="mt-4"><BlocklistView /></TabsContent>
        <TabsContent value="quick" className="mt-4"><QuickRepliesView /></TabsContent>
        <TabsContent value="settings" className="mt-4"><SettingsView /></TabsContent>
      </Tabs>
    </div>
  );
}
