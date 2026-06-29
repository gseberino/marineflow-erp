import { useState } from 'react';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { CalendarClock } from 'lucide-react';
import type { RecurrenceType } from '@/hooks/use-scheduled-sends';

export interface ScheduleConfig {
  enabled: boolean;
  scheduledAt: string; // datetime-local string
  recurrenceType: RecurrenceType;
  daysOfWeek: number[]; // 0..6
  dayOfMonth: number;
  endDate: string; // date string
}

const DAYS = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S']; // dom..sáb

interface Props {
  value: ScheduleConfig;
  onChange: (v: ScheduleConfig) => void;
  disabled?: boolean;
}

export function ScheduleSettings({ value, onChange, disabled }: Props) {
  const update = (patch: Partial<ScheduleConfig>) => onChange({ ...value, ...patch });

  const toggleDay = (d: number) => {
    const set = new Set(value.daysOfWeek);
    if (set.has(d)) set.delete(d);
    else set.add(d);
    update({ daysOfWeek: Array.from(set).sort() });
  };

  return (
    <div className="rounded-lg border p-3 space-y-3 bg-muted/30">
      <label className="flex items-center gap-2 text-sm font-medium cursor-pointer">
        <Checkbox
          checked={value.enabled}
          onCheckedChange={(v) => update({ enabled: !!v })}
          disabled={disabled}
        />
        <CalendarClock className="h-3.5 w-3.5" />
        Agendar envio
      </label>

      {value.enabled && (
        <div className="space-y-3 pl-6">
          <div className="space-y-1">
            <Label className="text-xs">Data e hora do primeiro envio</Label>
            <Input
              type="datetime-local"
              value={value.scheduledAt}
              onChange={(e) => update({ scheduledAt: e.target.value })}
              disabled={disabled}
              className="h-8 text-sm"
            />
          </div>

          <div className="space-y-1">
            <Label className="text-xs">Repetição</Label>
            <Select
              value={value.recurrenceType}
              onValueChange={(v) => update({ recurrenceType: v as RecurrenceType })}
              disabled={disabled}
            >
              <SelectTrigger className="h-8 text-sm">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="once">Apenas uma vez</SelectItem>
                <SelectItem value="daily">Diariamente</SelectItem>
                <SelectItem value="weekly">Semanalmente (dias específicos)</SelectItem>
                <SelectItem value="monthly">Mensalmente</SelectItem>
              </SelectContent>
            </Select>
          </div>

          {value.recurrenceType === 'weekly' && (
            <div className="space-y-1">
              <Label className="text-xs">Dias da semana</Label>
              <div className="flex gap-1 flex-wrap">
                {DAYS.map((label, idx) => {
                  const active = value.daysOfWeek.includes(idx);
                  return (
                    <button
                      key={idx}
                      type="button"
                      onClick={() => toggleDay(idx)}
                      disabled={disabled}
                      className={`h-8 w-8 rounded text-xs font-medium border transition-colors ${
                        active
                          ? 'bg-primary text-primary-foreground border-primary'
                          : 'bg-background border-input hover:bg-muted'
                      }`}
                    >
                      {label}
                    </button>
                  );
                })}
              </div>
              <p className="text-[10px] text-muted-foreground">D=Dom, S=Seg, T=Ter, Q=Qua, Q=Qui, S=Sex, S=Sáb</p>
            </div>
          )}

          {value.recurrenceType === 'monthly' && (
            <div className="space-y-1">
              <Label className="text-xs">Dia do mês</Label>
              <Input
                type="number"
                min={1}
                max={31}
                value={value.dayOfMonth}
                onChange={(e) => update({ dayOfMonth: parseInt(e.target.value, 10) || 1 })}
                disabled={disabled}
                className="h-8 text-sm w-24"
              />
            </div>
          )}

          {value.recurrenceType !== 'once' && (
            <div className="space-y-1">
              <Label className="text-xs">Encerrar em (opcional)</Label>
              <Input
                type="date"
                value={value.endDate}
                onChange={(e) => update({ endDate: e.target.value })}
                disabled={disabled}
                className="h-8 text-sm"
              />
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export function defaultScheduleConfig(): ScheduleConfig {
  const d = new Date();
  d.setMinutes(d.getMinutes() + 30);
  d.setSeconds(0, 0);
  const pad = (n: number) => String(n).padStart(2, '0');
  const datetimeLocal = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  return {
    enabled: false,
    scheduledAt: datetimeLocal,
    recurrenceType: 'once',
    daysOfWeek: [1], // segunda
    dayOfMonth: 1,
    endDate: '',
  };
}
