import { useState, useEffect } from 'react';

import { PageHeader } from '@/components/PageHeader';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Calendar } from '@/components/ui/calendar';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { cn } from '@/lib/utils';
import { format } from 'date-fns';
import { ptBR } from 'date-fns/locale';
import { CalendarIcon, Image as ImageIcon, Video, Type, Send, Clock, Trash2, Smartphone, Palette, CheckCircle2, Loader2, AlertCircle } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/use-auth';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Badge } from '@/components/ui/badge';

type StatusType = 'text' | 'image' | 'video';

const BACKGROUND_COLORS = [
  '#000000', '#746764', '#25D366', '#128C7E', '#34B7F1', '#D62976', '#FA7E1E', '#962FBF', '#4F5BD5'
];

export default function WhatsAppStatusPage() {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [contentType, setContentType] = useState<StatusType>('image');
  const [textContent, setTextContent] = useState('');
  const [backgroundColor, setBackgroundColor] = useState('#746764');
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [scheduledAt, setScheduledAt] = useState<Date | undefined>(new Date());
  const [isSubmitting, setIsSubmitting] = useState(false);

  // Limpa preview ao trocar arquivo
  useEffect(() => {
    if (!selectedFile) {
      setPreviewUrl(null);
      return;
    }
    const objectUrl = URL.createObjectURL(selectedFile);
    setPreviewUrl(objectUrl);
    return () => URL.revokeObjectURL(objectUrl);
  }, [selectedFile]);

  const { data: scheduledStatuses, isLoading } = useQuery({
    queryKey: ['whatsapp-status-scheduled'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('whatsapp_status_scheduled')
        .select('*')
        .order('scheduled_at', { ascending: true });
      if (error) throw error;
      return data;
    }
  });

  const deleteMutation = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('whatsapp_status_scheduled').delete().eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['whatsapp-status-scheduled'] });
      toast.success('Agendamento removido');
    }
  });

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      if (file.size > 16 * 1024 * 1024) {
        toast.error('Arquivo muito grande. Limite de 16MB.');
        return;
      }
      setSelectedFile(file);
    }
  };

  const handleSubmit = async () => {
    if (!scheduledAt) {
      toast.error('Selecione uma data e hora para o agendamento.');
      return;
    }
    if (contentType === 'text' && !textContent.trim()) {
      toast.error('Digite o texto do status.');
      return;
    }
    if (contentType !== 'text' && !selectedFile) {
      toast.error('Selecione um arquivo de imagem ou vídeo.');
      return;
    }

    setIsSubmitting(true);
    try {
      let mediaUrl = null;
      if (selectedFile) {
        const fileExt = selectedFile.name.split('.').pop();
        const fileName = `${crypto.randomUUID()}.${fileExt}`;
        const filePath = `status/${fileName}`;

        const { error: uploadError } = await supabase.storage
          .from('whatsapp_status')
          .upload(filePath, selectedFile);

        if (uploadError) throw uploadError;

        const { data: urlData } = supabase.storage
          .from('whatsapp_status')
          .getPublicUrl(filePath);
        
        mediaUrl = urlData.publicUrl;
      }

      const { error: insertError } = await supabase
        .from('whatsapp_status_scheduled')
        .insert({
          content_type: contentType,
          text_content: textContent,
          media_url: mediaUrl,
          background_color: backgroundColor,
          scheduled_at: scheduledAt.toISOString(),
          created_by: user?.id,
          status: 'pending'
        });

      if (insertError) throw insertError;

      toast.success('Status agendado com sucesso!');
      // Reset form
      setTextContent('');
      setSelectedFile(null);
      queryClient.invalidateQueries({ queryKey: ['whatsapp-status-scheduled'] });
    } catch (err: any) {
      console.error(err);
      toast.error(`Erro ao agendar: ${err.message}`);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <>
      <div className="flex flex-col gap-6">
        <PageHeader 
          title="Agendador de Status" 
          description="Crie e agende postagens automáticas para o seu Status do WhatsApp."
        />

        <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
          {/* ── Formulário de Criação ── */}
          <div className="lg:col-span-4 flex flex-col gap-6">
            <Card className="border-primary/10">
              <CardHeader className="pb-4">
                <CardTitle className="text-lg flex items-center gap-2">
                  <Palette className="h-5 w-5 text-primary" />
                  Criar Novo Post
                </CardTitle>
                <CardDescription>Escolha o tipo e configure o conteúdo.</CardDescription>
              </CardHeader>
              <CardContent className="space-y-6">
                <div className="space-y-3">
                  <Label>Tipo de Status</Label>
                  <Tabs value={contentType} onValueChange={(v) => setContentType(v as StatusType)} className="w-full">
                    <TabsList className="grid grid-cols-3 w-full">
                      <TabsTrigger value="text" className="gap-2"><Type className="h-4 w-4" /> Texto</TabsTrigger>
                      <TabsTrigger value="image" className="gap-2"><ImageIcon className="h-4 w-4" /> Imagem</TabsTrigger>
                      <TabsTrigger value="video" className="gap-2"><Video className="h-4 w-4" /> Vídeo</TabsTrigger>
                    </TabsList>
                  </Tabs>
                </div>

                {contentType === 'text' ? (
                  <div className="space-y-4">
                    <div className="space-y-2">
                      <Label>Texto do Status</Label>
                      <Textarea 
                        placeholder="O que você quer dizer?"
                        className="min-h-[120px] resize-none"
                        value={textContent}
                        onChange={(e) => setTextContent(e.target.value)}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label>Cor de Fundo</Label>
                      <div className="flex flex-wrap gap-2">
                        {BACKGROUND_COLORS.map(color => (
                          <button
                            key={color}
                            onClick={() => setBackgroundColor(color)}
                            className={cn(
                              "h-8 w-8 rounded-full border-2 transition-transform hover:scale-110",
                              backgroundColor === color ? "border-primary scale-110" : "border-transparent"
                            )}
                            style={{ backgroundColor: color }}
                          />
                        ))}
                      </div>
                    </div>
                  </div>
                ) : (
                  <div className="space-y-4">
                    <div className="space-y-2">
                      <Label>{contentType === 'image' ? 'Imagem' : 'Vídeo'}</Label>
                      <div className="flex items-center gap-4">
                        <Input 
                          type="file" 
                          accept={contentType === 'image' ? "image/*" : "video/*"}
                          onChange={handleFileChange}
                          className="cursor-pointer"
                        />
                      </div>
                    </div>
                    <div className="space-y-2">
                      <Label>Legenda (opcional)</Label>
                      <Textarea 
                        placeholder="Adicione uma legenda..."
                        className="h-20 resize-none"
                        value={textContent}
                        onChange={(e) => setTextContent(e.target.value)}
                      />
                    </div>
                  </div>
                )}

                <div className="space-y-2">
                  <Label>Agendar Para</Label>
                  <div className="flex gap-2">
                    <Popover>
                      <PopoverTrigger asChild>
                        <Button
                          variant="outline"
                          className={cn(
                            "w-full justify-start text-left font-normal",
                            !scheduledAt && "text-muted-foreground"
                          )}
                        >
                          <CalendarIcon className="mr-2 h-4 w-4" />
                          {scheduledAt ? format(scheduledAt, "PPP", { locale: ptBR }) : "Selecione data"}
                        </Button>
                      </PopoverTrigger>
                      <PopoverContent className="w-auto p-0" align="start">
                        <Calendar
                          mode="single"
                          selected={scheduledAt}
                          onSelect={setScheduledAt}
                          initialFocus
                        />
                      </PopoverContent>
                    </Popover>
                    <Input 
                      type="time" 
                      className="w-[120px]" 
                      onChange={(e) => {
                        if (!scheduledAt) return;
                        const [h, m] = e.target.value.split(':');
                        const d = new Date(scheduledAt);
                        d.setHours(parseInt(h), parseInt(m));
                        setScheduledAt(d);
                      }}
                    />
                  </div>
                </div>

                <Button 
                  className="w-full gap-2 bg-[#C9A064] hover:bg-[#B38D56]" 
                  disabled={isSubmitting}
                  onClick={handleSubmit}
                >
                  {isSubmitting ? <Loader2 className="h-4 w-4 animate-spin" /> : <Clock className="h-4 w-4" />}
                  Agendar Status
                </Button>
              </CardContent>
            </Card>
          </div>

          {/* ── Preview em Tempo Real ── */}
          <div className="lg:col-span-4 flex flex-col items-center">
            <div className="sticky top-6 flex flex-col items-center gap-4">
              <span className="text-sm font-medium text-muted-foreground flex items-center gap-2">
                <Smartphone className="h-4 w-4" /> Live Preview
              </span>
              
              {/* Moldura do Celular */}
              <div className="relative w-[280px] h-[580px] bg-black rounded-[3rem] border-[8px] border-[#1f1f1f] shadow-2xl overflow-hidden flex flex-col">
                {/* Notch */}
                <div className="absolute top-0 left-1/2 -translate-x-1/2 w-32 h-6 bg-[#1f1f1f] rounded-b-2xl z-20" />
                
                {/* Conteúdo do Status */}
                <div 
                  className="flex-1 flex flex-col items-center justify-center relative p-6 text-center overflow-hidden"
                  style={{ backgroundColor: contentType === 'text' ? backgroundColor : '#000' }}
                >
                  {contentType === 'text' ? (
                    <p className="text-white text-xl font-medium break-words max-w-full leading-relaxed animate-in fade-in zoom-in duration-300">
                      {textContent || 'Seu texto aqui...'}
                    </p>
                  ) : (
                    <>
                      {previewUrl ? (
                        contentType === 'image' ? (
                          <img src={previewUrl} alt="Preview" className="absolute inset-0 w-full h-full object-cover" />
                        ) : (
                          <video src={previewUrl} className="absolute inset-0 w-full h-full object-cover" muted autoPlay loop />
                        )
                      ) : (
                        <div className="text-white/30 flex flex-col items-center gap-2">
                          <ImageIcon className="h-12 w-12 opacity-20" />
                          <span className="text-xs uppercase tracking-widest">Nenhuma mídia</span>
                        </div>
                      )}
                      {textContent && (
                        <div className="absolute bottom-12 left-0 right-0 bg-black/40 backdrop-blur-sm p-4 text-white text-sm">
                          {textContent}
                        </div>
                      )}
                    </>
                  )}

                  {/* WhatsApp UI elements overlay */}
                  <div className="absolute top-10 left-4 right-4 flex gap-1 h-0.5">
                    <div className="flex-1 bg-white/40 rounded-full h-full" />
                    <div className="flex-1 bg-white/20 rounded-full h-full" />
                  </div>
                  <div className="absolute top-12 left-4 flex items-center gap-2">
                    <div className="h-8 w-8 rounded-full bg-white/20 border border-white/10" />
                    <div className="flex flex-col items-start">
                      <div className="h-2 w-20 bg-white/30 rounded" />
                      <div className="h-1.5 w-12 bg-white/20 rounded mt-1" />
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          {/* ── Fila de Agendamentos ── */}
          <div className="lg:col-span-4 space-y-4">
            <h3 className="text-sm font-semibold flex items-center gap-2 text-muted-foreground uppercase tracking-wider">
              <Clock className="h-4 w-4" /> Próximos Status
            </h3>
            
            <div className="space-y-3">
              {isLoading ? (
                Array(3).fill(0).map((_, i) => <div key={i} className="h-24 w-full rounded-xl bg-muted animate-pulse" />)
              ) : scheduledStatuses?.length === 0 ? (
                <div className="flex flex-col items-center justify-center p-12 border-2 border-dashed rounded-2xl text-center gap-3">
                  <div className="h-12 w-12 rounded-full bg-muted flex items-center justify-center">
                    <Send className="h-5 w-5 text-muted-foreground opacity-30" />
                  </div>
                  <div className="space-y-1">
                    <p className="text-sm font-medium">Fila vazia</p>
                    <p className="text-xs text-muted-foreground">Você ainda não agendou nenhum status.</p>
                  </div>
                </div>
              ) : (
                scheduledStatuses?.map((status) => (
                  <Card key={status.id} className="group overflow-hidden hover:border-primary/30 transition-all">
                    <CardContent className="p-0 flex h-24">
                      <div 
                        className="w-20 shrink-0 flex items-center justify-center relative bg-muted"
                        style={{ backgroundColor: status.content_type === 'text' ? status.background_color : undefined }}
                      >
                        {status.content_type === 'image' && (
                          <img src={status.media_url} className="absolute inset-0 w-full h-full object-cover" />
                        )}
                        {status.content_type === 'video' && <Video className="h-5 w-5 text-white" />}
                        {status.content_type === 'text' && <Type className="h-5 w-5 text-white" />}
                      </div>
                      <div className="flex-1 p-3 flex flex-col justify-between min-w-0">
                        <div className="flex items-start justify-between">
                          <div className="space-y-0.5 min-w-0">
                            <div className="flex items-center gap-2">
                              {status.status === 'pending' ? (
                                <Badge variant="secondary" className="bg-yellow-500/10 text-yellow-600 border-yellow-200/50 text-[10px] h-4">Pendente</Badge>
                              ) : status.status === 'sent' ? (
                                <Badge variant="secondary" className="bg-green-500/10 text-green-600 border-green-200/50 text-[10px] h-4">Enviado</Badge>
                              ) : (
                                <Badge variant="destructive" className="text-[10px] h-4">Falhou</Badge>
                              )}
                              <span className="text-[10px] text-muted-foreground font-medium uppercase tracking-tighter">
                                {status.content_type}
                              </span>
                            </div>
                            <p className="text-sm font-medium truncate">
                              {status.text_content || 'Sem legenda'}
                            </p>
                          </div>
                          <Button 
                            variant="ghost" 
                            size="icon" 
                            className="h-7 w-7 text-destructive opacity-0 group-hover:opacity-100 transition-opacity"
                            onClick={() => deleteMutation.mutate(status.id)}
                            disabled={deleteMutation.isPending}
                          >
                            <Trash2 className="h-4 w-4" />
                          </Button>
                        </div>
                        <div className="flex items-center gap-1.5 text-xs text-muted-foreground font-mono">
                          <CalendarIcon className="h-3 w-3" />
                          {format(new Date(status.scheduled_at), "dd/MM 'às' HH:mm")}
                        </div>
                      </div>
                    </CardContent>
                  </Card>
                ))
              )}
            </div>

            {scheduledStatuses && scheduledStatuses.length > 0 && (
              <div className="p-4 bg-primary/5 rounded-xl border border-primary/10 flex gap-3">
                <AlertCircle className="h-5 w-5 text-primary shrink-0" />
                <p className="text-xs text-primary/80 leading-relaxed">
                  Os status são processados automaticamente no horário agendado. Certifique-se de que sua instância Z-API esteja conectada.
                </p>
              </div>
            )}
          </div>
        </div>
      </div>
    </>
  );
}
