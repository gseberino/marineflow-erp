import { useEffect, useRef, useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Slider } from '@/components/ui/slider';
import { Label } from '@/components/ui/label';

// Canvas output (matches the standardized display ratio ~ 320x160 = 2:1)
const OUT_W = 320;
const OUT_H = 160;
const SNAP_THRESHOLD = 6; // px to center snap

interface Props {
  file: File | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onConfirm: (blob: Blob) => void;
}

export function LogoCropDialog({ file, open, onOpenChange, onConfirm }: Props) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const imgRef = useRef<HTMLImageElement | null>(null);
  const [imgLoaded, setImgLoaded] = useState(false);
  const [scale, setScale] = useState(1);
  const [offset, setOffset] = useState({ x: 0, y: 0 });
  const [dragging, setDragging] = useState<{ sx: number; sy: number; ox: number; oy: number } | null>(null);
  const [snapH, setSnapH] = useState(false);
  const [snapV, setSnapV] = useState(false);

  // Load file into image
  useEffect(() => {
    if (!file || !open) return;
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      imgRef.current = img;
      // initial scale: fit-contain inside output
      const s = Math.min(OUT_W / img.width, OUT_H / img.height);
      setScale(s);
      setOffset({ x: 0, y: 0 });
      setImgLoaded(true);
    };
    img.src = url;
    return () => URL.revokeObjectURL(url);
  }, [file, open]);

  // Redraw whenever state changes
  useEffect(() => {
    const canvas = canvasRef.current;
    const img = imgRef.current;
    if (!canvas || !img || !imgLoaded) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.clearRect(0, 0, OUT_W, OUT_H);
    // checkered background for transparency
    const tile = 10;
    for (let y = 0; y < OUT_H; y += tile) {
      for (let x = 0; x < OUT_W; x += tile) {
        ctx.fillStyle = ((x + y) / tile) % 2 === 0 ? '#f3f4f6' : '#ffffff';
        ctx.fillRect(x, y, tile, tile);
      }
    }
    const w = img.width * scale;
    const h = img.height * scale;
    const cx = OUT_W / 2 + offset.x - w / 2;
    const cy = OUT_H / 2 + offset.y - h / 2;
    ctx.drawImage(img, cx, cy, w, h);

    // snap guides
    if (snapV) {
      ctx.strokeStyle = '#ef4444';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(OUT_W / 2, 0);
      ctx.lineTo(OUT_W / 2, OUT_H);
      ctx.stroke();
    }
    if (snapH) {
      ctx.strokeStyle = '#ef4444';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(0, OUT_H / 2);
      ctx.lineTo(OUT_W, OUT_H / 2);
      ctx.stroke();
    }
  }, [scale, offset, imgLoaded, snapH, snapV]);

  const onPointerDown = (e: React.PointerEvent) => {
    (e.target as Element).setPointerCapture(e.pointerId);
    setDragging({ sx: e.clientX, sy: e.clientY, ox: offset.x, oy: offset.y });
  };
  const onPointerMove = (e: React.PointerEvent) => {
    if (!dragging) return;
    const rect = (e.target as HTMLCanvasElement).getBoundingClientRect();
    const ratio = OUT_W / rect.width;
    let nx = dragging.ox + (e.clientX - dragging.sx) * ratio;
    let ny = dragging.oy + (e.clientY - dragging.sy) * ratio;
    let sV = false;
    let sH = false;
    if (Math.abs(nx) <= SNAP_THRESHOLD) { nx = 0; sV = true; }
    if (Math.abs(ny) <= SNAP_THRESHOLD) { ny = 0; sH = true; }
    setOffset({ x: nx, y: ny });
    setSnapV(sV);
    setSnapH(sH);
  };
  const onPointerUp = () => {
    setDragging(null);
    // keep snap guides briefly off after release
    setTimeout(() => { setSnapH(false); setSnapV(false); }, 200);
  };

  const center = () => {
    setOffset({ x: 0, y: 0 });
    setSnapH(true);
    setSnapV(true);
    setTimeout(() => { setSnapH(false); setSnapV(false); }, 400);
  };

  const fit = () => {
    const img = imgRef.current;
    if (!img) return;
    const s = Math.min(OUT_W / img.width, OUT_H / img.height);
    setScale(s);
    setOffset({ x: 0, y: 0 });
  };

  const confirm = () => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    // Re-render WITHOUT background tiles or guides for export — use a clean canvas
    const out = document.createElement('canvas');
    out.width = OUT_W;
    out.height = OUT_H;
    const ctx = out.getContext('2d');
    const img = imgRef.current;
    if (!ctx || !img) return;
    const w = img.width * scale;
    const h = img.height * scale;
    const cx = OUT_W / 2 + offset.x - w / 2;
    const cy = OUT_H / 2 + offset.y - h / 2;
    ctx.drawImage(img, cx, cy, w, h);
    out.toBlob((blob) => {
      if (blob) onConfirm(blob);
    }, 'image/png');
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Ajustar logo</DialogTitle>
          <DialogDescription>
            Arraste para reposicionar. As linhas vermelhas indicam o centro (snap automático).
          </DialogDescription>
        </DialogHeader>

        <div className="flex justify-center bg-muted rounded-lg p-3">
          <canvas
            ref={canvasRef}
            width={OUT_W}
            height={OUT_H}
            onPointerDown={onPointerDown}
            onPointerMove={onPointerMove}
            onPointerUp={onPointerUp}
            onPointerCancel={onPointerUp}
            className="w-full max-w-[320px] aspect-[2/1] border rounded bg-white touch-none cursor-move select-none"
          />
        </div>

        <div className="space-y-2">
          <Label className="text-xs">Zoom</Label>
          <Slider
            min={0.1}
            max={3}
            step={0.01}
            value={[scale]}
            onValueChange={([v]) => setScale(v)}
          />
        </div>

        <div className="flex gap-2 justify-between">
          <div className="flex gap-2">
            <Button type="button" variant="outline" size="sm" onClick={center}>Centralizar</Button>
            <Button type="button" variant="outline" size="sm" onClick={fit}>Ajustar</Button>
          </div>
          <DialogFooter className="gap-2">
            <Button type="button" variant="ghost" onClick={() => onOpenChange(false)}>Cancelar</Button>
            <Button type="button" onClick={confirm}>Aplicar</Button>
          </DialogFooter>
        </div>
      </DialogContent>
    </Dialog>
  );
}
