import { useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Upload, X, Loader2, Image as ImageIcon } from 'lucide-react';
import { toast } from 'sonner';

export function ServiceOrderPhotos({ orderId, initialPhotos }: { orderId: string, initialPhotos?: string[] }) {
  const [photos, setPhotos] = useState<string[]>(initialPhotos || []);
  const [uploading, setUploading] = useState(false);

  const handleUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    if (!e.target.files || e.target.files.length === 0) return;
    setUploading(true);
    
    const file = e.target.files[0];
    const fileExt = file.name.split('.').pop();
    const fileName = `${orderId}-${Math.random()}.${fileExt}`;
    const filePath = `photos/${fileName}`;

    try {
      // Usamos o bucket "documents", que geralmente já existe, ou criamos um "photos".
      // Vamos tentar upload para "documents".
      const { error: uploadError } = await supabase.storage
        .from('documents')
        .upload(filePath, file);

      if (uploadError) throw uploadError;

      const { data } = supabase.storage.from('documents').getPublicUrl(filePath);
      const newUrl = data.publicUrl;

      const updatedPhotos = [...photos, newUrl];
      
      const { error: dbError } = await supabase
        .from('service_orders')
        .update({ photos: updatedPhotos })
        .eq('id', orderId);

      if (dbError) throw dbError;

      setPhotos(updatedPhotos);
      toast.success('Foto anexada com sucesso!');
    } catch (err: any) {
      console.error(err);
      toast.error('Erro ao enviar foto: ' + err.message);
    } finally {
      setUploading(false);
    }
  };

  const removePhoto = async (url: string) => {
    const updatedPhotos = photos.filter(p => p !== url);
    try {
      await supabase.from('service_orders').update({ photos: updatedPhotos }).eq('id', orderId);
      setPhotos(updatedPhotos);
      toast.success('Foto removida');
    } catch (e) {
      toast.error('Erro ao remover foto');
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-semibold flex items-center"><ImageIcon className="w-4 h-4 mr-2"/> Fotos do Serviço / Acompanhamento</h3>
        <Button variant="outline" size="sm" className="relative cursor-pointer" disabled={uploading}>
          {uploading ? <Loader2 className="w-4 h-4 animate-spin mr-2" /> : <Upload className="w-4 h-4 mr-2" />}
          Adicionar Foto
          <input 
            type="file" 
            accept="image/*" 
            className="absolute inset-0 w-full h-full opacity-0 cursor-pointer" 
            onChange={handleUpload}
            disabled={uploading}
          />
        </Button>
      </div>

      {photos.length === 0 ? (
        <div className="p-8 text-center text-muted-foreground border-2 border-dashed rounded-xl bg-muted/20">
          Nenhuma foto anexada a esta OS ainda.
        </div>
      ) : (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          {photos.map((url, i) => (
            <Card key={i} className="overflow-hidden group relative">
              <Button 
                variant="destructive" 
                size="icon" 
                className="absolute top-2 right-2 h-6 w-6 opacity-0 group-hover:opacity-100 transition-opacity z-10"
                onClick={() => removePhoto(url)}
              >
                <X className="h-3 w-3" />
              </Button>
              <CardContent className="p-0 aspect-square relative">
                <img src={url} alt={`Foto ${i+1}`} className="w-full h-full object-cover" />
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
