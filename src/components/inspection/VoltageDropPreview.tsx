import { useMemo, useState } from 'react';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { calculateVoltageDrop, type VoltageDropResult } from '@/lib/inspection/voltage-drop';

type Props = {
  onResultChange?: (result: VoltageDropResult | null) => void;
};

const CLASS_COLORS: Record<VoltageDropResult['classification'], string> = {
  ok: 'border-emerald-300 bg-emerald-50 text-emerald-800 dark:bg-emerald-900/30 dark:text-emerald-200 dark:border-emerald-800',
  attention: 'border-amber-300 bg-amber-50 text-amber-800 dark:bg-amber-900/30 dark:text-amber-200 dark:border-amber-800',
  critical: 'border-red-300 bg-red-50 text-red-800 dark:bg-red-900/30 dark:text-red-200 dark:border-red-800',
  invalid: 'border-dashed border-muted-foreground/30 bg-muted/30 text-muted-foreground',
};

const CLASS_LABEL: Record<VoltageDropResult['classification'], string> = {
  ok: 'Conforme',
  attention: 'Atenção',
  critical: 'Crítico',
  invalid: 'Preencha todos os campos',
};

export function VoltageDropPreview({ onResultChange }: Props) {
  const [systemVoltage, setSystemVoltage] = useState<string>('12');
  const [currentAmps, setCurrentAmps] = useState<string>('');
  const [lengthMeters, setLengthMeters] = useState<string>('');
  const [crossSectionMm2, setCrossSectionMm2] = useState<string>('');

  const result = useMemo(() => {
    const res = calculateVoltageDrop({
      systemVoltage: Number(systemVoltage),
      currentAmps: Number(currentAmps),
      lengthMeters: Number(lengthMeters),
      crossSectionMm2: Number(crossSectionMm2),
    });
    onResultChange?.(res.classification === 'invalid' ? null : res);
    return res;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [systemVoltage, currentAmps, lengthMeters, crossSectionMm2]);

  return (
    <div className="rounded-lg border bg-card p-4 flex flex-col gap-4">
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <div>
          <Label className="text-xs text-muted-foreground">Tensão do sistema (V)</Label>
          <Select value={systemVoltage} onValueChange={setSystemVoltage}>
            <SelectTrigger className="mt-1">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="12">12 V</SelectItem>
              <SelectItem value="24">24 V</SelectItem>
              <SelectItem value="48">48 V</SelectItem>
              <SelectItem value="110">110 V</SelectItem>
              <SelectItem value="220">220 V</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div>
          <Label className="text-xs text-muted-foreground">Corrente (A)</Label>
          <Input
            type="number"
            inputMode="decimal"
            min={0}
            step="any"
            value={currentAmps}
            onChange={(e) => setCurrentAmps(e.target.value)}
            className="mt-1"
            placeholder="ex.: 30"
          />
        </div>
        <div>
          <Label className="text-xs text-muted-foreground">Comprimento (m)</Label>
          <Input
            type="number"
            inputMode="decimal"
            min={0}
            step="any"
            value={lengthMeters}
            onChange={(e) => setLengthMeters(e.target.value)}
            className="mt-1"
            placeholder="ex.: 8"
          />
        </div>
        <div>
          <Label className="text-xs text-muted-foreground">Bitola (mm²)</Label>
          <Input
            type="number"
            inputMode="decimal"
            min={0}
            step="any"
            value={crossSectionMm2}
            onChange={(e) => setCrossSectionMm2(e.target.value)}
            className="mt-1"
            placeholder="ex.: 10"
          />
        </div>
      </div>
      <div className={`rounded border p-3 text-sm ${CLASS_COLORS[result.classification]}`}>
        <div className="flex items-baseline gap-3 flex-wrap">
          <span className="font-semibold">{CLASS_LABEL[result.classification]}</span>
          {result.classification !== 'invalid' && (
            <>
              <span>
                Queda: <strong>{result.dropVolts.toFixed(3)} V</strong>
              </span>
              <span>
                Percentual: <strong>{result.dropPercent.toFixed(2)}%</strong>
              </span>
            </>
          )}
        </div>
        <p className="text-xs mt-1 opacity-90">{result.message}</p>
      </div>
      <p className="text-xs text-muted-foreground">
        Cálculo auxiliar baseado em condutor de cobre. Sempre validado tecnicamente antes de aplicar.
      </p>
    </div>
  );
}
