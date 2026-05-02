import { useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Camera, X, Loader2, Image as ImageIcon, Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

type PhotoType = 'before' | 'progress' | 'after' | 'problem';

const TYPE_LABELS: Record<PhotoType, string> = {
  before: 'Antes',
  progress: 'Andamento',
  after: 'Após',
  problem: 'Problema',
};

const TYPE_BADGE: Record<PhotoType, string> = {
  before: 'bg-blue-100 text-blue-700',
  progress: 'bg-yellow-100 text-yellow-700',
  after: 'bg-green-100 text-green-700',
  problem: 'bg-red-100 text-red-700',
};

interface Props {
  serviceOrderId: string;
}

export function ServiceOrderPhotos({ serviceOrderId }: Props) {
  const qc = useQueryClient();
  const [uploading, setUploading] = useState(false);
  const [photoType, setPhotoType] = useState<PhotoType>('progress');
  const [fullscreen, setFullscreen] = useState<string | null>(null);

  const { data: photos = [], isLoading } = useQuery({
    queryKey: ['so-photos', serviceOrderId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('service_order_photos')
        .select('*')
        .eq('service_order_id', serviceOrderId)
        .order('created_at', { ascending: false });
      if (error) throw error;
      return data || [];
    },
    enabled: !!serviceOrderId,
  });

  const handleUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploading(true);
    try {
      const ext = file.name.split('.').pop() || 'jpg';
      const uuid = crypto.randomUUID();
      const path = `${serviceOrderId}/${uuid}.${ext}`;

      const { error: upErr } = await supabase.storage
        .from('service-order-photos')
        .upload(path, file, { contentType: file.type });
      if (upErr) throw upErr;

      const { data: urlData } = supabase.storage
        .from('service-order-photos')
        .getPublicUrl(path);

      const { data: userData } = await supabase.auth.getUser();

      const { error: dbErr } = await supabase.from('service_order_photos').insert({
        service_order_id: serviceOrderId,
        storage_path: path,
        public_url: urlData.publicUrl,
        photo_type: photoType,
        uploaded_by: userData.user?.id ?? null,
      });
      if (dbErr) {
        await supabase.storage.from('service-order-photos').remove([path]);
        throw dbErr;
      }
      toast.success('Foto adicionada');
      qc.invalidateQueries({ queryKey: ['so-photos', serviceOrderId] });
    } catch (err: any) {
      console.error(err);
      toast.error('Erro ao enviar foto: ' + (err.message || ''));
    } finally {
      setUploading(false);
      e.target.value = '';
    }
  };

  const handleDelete = async (photo: any) => {
    if (!confirm('Excluir esta foto?')) return;
    try {
      await supabase.storage
        .from('service-order-photos')
        .remove([photo.storage_path]);
      const { error } = await supabase
        .from('service_order_photos')
        .delete()
        .eq('id', photo.id);
      if (error) throw error;
      toast.success('Foto removida');
      qc.invalidateQueries({ queryKey: ['so-photos', serviceOrderId] });
    } catch (err: any) {
      toast.error('Erro ao excluir foto');
    }
  };

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <Select value={photoType} onValueChange={(v) => setPhotoType(v as PhotoType)}>
          <SelectTrigger className="w-40 h-9">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {(Object.keys(TYPE_LABELS) as PhotoType[]).map((t) => (
              <SelectItem key={t} value={t}>
                {TYPE_LABELS[t]}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>

        <Button
          type="button"
          variant="outline"
          size="sm"
          className="relative"
          disabled={uploading}
        >
          {uploading ? (
            <Loader2 className="w-4 h-4 mr-2 animate-spin" />
          ) : (
            <Camera className="w-4 h-4 mr-2" />
          )}
          Adicionar foto
          <input
            type="file"
            accept="image/*"
            capture="environment"
            disabled={uploading}
            onChange={handleUpload}
            className="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
          />
        </Button>
      </div>

      {isLoading ? (
        <div className="text-xs text-muted-foreground">Carregando...</div>
      ) : photos.length === 0 ? (
        <div className="p-6 text-center text-sm text-muted-foreground border-2 border-dashed rounded-lg bg-muted/20 flex flex-col items-center gap-2">
          <ImageIcon className="w-6 h-6 opacity-50" />
          Nenhuma foto registrada nesta OS.
        </div>
      ) : (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          {photos.map((p: any) => {
            const type = (p.photo_type || 'progress') as PhotoType;
            return (
              <div
                key={p.id}
                className="group relative overflow-hidden rounded-lg border aspect-square bg-muted"
              >
                <button
                  type="button"
                  onClick={() => setFullscreen(p.public_url)}
                  className="block w-full h-full"
                >
                  <img
                    src={p.public_url}
                    alt={p.caption || TYPE_LABELS[type]}
                    className="w-full h-full object-cover"
                    loading="lazy"
                  />
                </button>
                <span
                  className={`absolute top-1 left-1 text-[10px] px-1.5 py-0.5 rounded font-medium ${TYPE_BADGE[type]}`}
                >
                  {TYPE_LABELS[type]}
                </span>
                <button
                  type="button"
                  onClick={() => handleDelete(p)}
                  className="absolute top-1 right-1 h-6 w-6 inline-flex items-center justify-center rounded-full bg-destructive text-destructive-foreground opacity-0 group-hover:opacity-100 transition"
                  title="Excluir"
                >
                  <Trash2 className="h-3 w-3" />
                </button>
              </div>
            );
          })}
        </div>
      )}

      {fullscreen && (
        <div
          className="fixed inset-0 z-50 bg-black/90 flex items-center justify-center p-4"
          onClick={() => setFullscreen(null)}
        >
          <button
            type="button"
            className="absolute top-4 right-4 h-9 w-9 inline-flex items-center justify-center rounded-full bg-white/10 text-white hover:bg-white/20"
            onClick={() => setFullscreen(null)}
          >
            <X className="h-5 w-5" />
          </button>
          <img
            src={fullscreen}
            alt="Foto"
            className="max-w-full max-h-full object-contain"
          />
        </div>
      )}
    </div>
  );
}
