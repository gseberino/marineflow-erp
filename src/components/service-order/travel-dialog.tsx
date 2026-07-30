/* Diálogo de Deslocamento da OS, extraído 1:1 do ServiceOrderForm (Fase 3, passo 5). */
import { MapPin, RefreshCw } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { MoneyInput } from '@/components/MoneyInput';
import { useI18n } from '@/i18n';
import type { Dispatch, SetStateAction } from 'react';

interface TravelDialogProps {
  isNew: boolean;
  form: Record<string, any>;
  set: (field: string, value: any) => void;
  marina: any;
  travelRates: any;
  manualTravel: boolean;
  setManualTravel: Dispatch<SetStateAction<boolean>>;
  showTravelDialog: boolean;
  setShowTravelDialog: Dispatch<SetStateAction<boolean>>;
  calcTravelCost: (...args: any[]) => any;
  runDisplacement: (...args: any[]) => any;
}

export function TravelDialog(props: TravelDialogProps) {
  const {
    isNew, form, set, marina, travelRates,
    manualTravel, setManualTravel, showTravelDialog, setShowTravelDialog,
    calcTravelCost, runDisplacement,
  } = props;
  const { t, formatCurrency } = useI18n();

  return (
    <>
      {!isNew && (
        <Dialog open={showTravelDialog} onOpenChange={setShowTravelDialog}>
          <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2">
                <MapPin className="h-4 w-4" /> Deslocamento
              </DialogTitle>
            </DialogHeader>
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <h2 className="font-semibold text-sm">{t.serviceOrders.travel}</h2>
                {marina?.latitude && (
                  <Button variant="outline" size="sm" onClick={runDisplacement} className="gap-1">
                    <RefreshCw className="h-3 w-3" />
                    {t.serviceOrders.recalculate}
                  </Button>
                )}
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 mt-3">
                <div>
                  <Label>Distância total (km ida+volta)</Label>
                  <Input type="number" min={0} step="0.1"
                    value={form.travel_distance_km}
                    onChange={(e) => {
                      const km = parseFloat(e.target.value) || 0;
                      set('travel_distance_km', km);
                      if (!manualTravel) {
                        set('travel_cost_total', calcTravelCost({
                          distance_km: km,
                          travel_hours: form.travel_hours,
                          technician_count: form.technician_count_for_travel,
                          ferry_cost: form.ferry_cost,
                          travel_type: form.travel_type,
                        }));
                      }
                    }}
                  />
                </div>
                <div>
                  <Label>Tempo de deslocamento (horas)</Label>
                  <Input type="number" min={0} step="0.5"
                    value={form.travel_hours}
                    onChange={(e) => {
                      const hours = parseFloat(e.target.value) || 0;
                      set('travel_hours', hours);
                      if (!manualTravel) {
                        set('travel_cost_total', calcTravelCost({
                          distance_km: form.travel_distance_km,
                          travel_hours: hours,
                          technician_count: form.technician_count_for_travel,
                          ferry_cost: form.ferry_cost,
                          travel_type: form.travel_type,
                        }));
                      }
                    }}
                  />
                </div>
                <div>
                  <Label>Técnicos no deslocamento</Label>
                  <Select
                    value={String(form.technician_count_for_travel)}
                    onValueChange={(v) => {
                      const count = parseInt(v) || 1;
                      set('technician_count_for_travel', count);
                      if (!manualTravel) {
                        set('travel_cost_total', calcTravelCost({
                          distance_km: form.travel_distance_km,
                          travel_hours: form.travel_hours,
                          technician_count: count,
                          ferry_cost: form.ferry_cost,
                          travel_type: form.travel_type,
                        }));
                      }
                    }}
                  >
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="1">1 técnico — {formatCurrency(travelRates.hourly[1])}/h</SelectItem>
                      <SelectItem value="2">2 técnicos — {formatCurrency(travelRates.hourly[2])}/h</SelectItem>
                      <SelectItem value="3">3 técnicos — {formatCurrency(travelRates.hourly[3])}/h</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label>Tipo de atendimento</Label>
                  <Select
                    value={form.travel_type}
                    onValueChange={(v: any) => {
                      set('travel_type', v);
                      if (!manualTravel) {
                        set('travel_cost_total', calcTravelCost({
                          distance_km: form.travel_distance_km,
                          travel_hours: form.travel_hours,
                          technician_count: form.technician_count_for_travel,
                          ferry_cost: form.ferry_cost,
                          travel_type: v,
                        }));
                      }
                    }}
                  >
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="comercial">Comercial (sem acréscimo)</SelectItem>
                      <SelectItem value="urgencia">Urgência fora do horário (+50%)</SelectItem>
                      <SelectItem value="fds_feriado">Final de semana / Feriado (+30%)</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </div>

              {/* Travessia de balsa */}
              <div className="mt-3 space-y-2">
                <div>
                  <Label>Valor da travessia de balsa / ferry (R$)</Label>
                  <MoneyInput
                    value={form.ferry_cost}
                    onValueChange={(v) => {
                      set('ferry_cost', v);
                      if (!manualTravel) {
                        set('travel_cost_total', calcTravelCost({
                          distance_km: form.travel_distance_km,
                          travel_hours: form.travel_hours,
                          technician_count: form.technician_count_for_travel,
                          ferry_cost: v,
                          travel_type: form.travel_type,
                        }));
                      }
                    }}
                  />
                </div>
              </div>

              {/* Total calculado */}
              <div className="mt-4 flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <Label>Total deslocamento</Label>
                  <label className="flex items-center gap-1 text-xs text-muted-foreground">
                    <input type="checkbox" checked={manualTravel}
                      onChange={(e) => setManualTravel(e.target.checked)} />
                    Ajuste manual
                  </label>
                </div>
                {manualTravel ? (
                  <MoneyInput
                    value={form.travel_cost_total}
                    onValueChange={(v) => set('travel_cost_total', v)}
                  />
                ) : (
                  <span className="text-lg font-semibold">
                    {formatCurrency(form.travel_cost_total)}
                  </span>
                )}
              </div>

              <label className="flex items-center gap-2 text-sm cursor-pointer">
                <input type="checkbox" checked={form.is_travel_billable !== false}
                  onChange={(e) => set('is_travel_billable', e.target.checked)} />
                Repassar deslocamento ao cliente
                <span className="text-xs text-muted-foreground">(desmarque para custo interno, não repassado no orçamento/OS)</span>
              </label>

              {/* Breakdown do cálculo */}
              {!manualTravel && form.travel_cost_total > 0 && (
                <div className="mt-2 text-xs text-muted-foreground space-y-0.5">
                  <div>• Km: {form.travel_distance_km} km × R$ 1,10 = {formatCurrency(form.travel_distance_km * 1.10)}</div>
                  {form.travel_hours > 0 && (
                    <div>• Horas: {form.travel_hours}h × {formatCurrency(
                      form.technician_count_for_travel === 1 ? 90 :
                      form.technician_count_for_travel === 2 ? 170 : 250
                    )}/h = {formatCurrency(form.travel_hours * (
                      form.technician_count_for_travel === 1 ? 90 :
                      form.technician_count_for_travel === 2 ? 170 : 250
                    ))}</div>
                  )}
                  {form.ferry_cost > 0 && <div>• Balsa: {formatCurrency(form.ferry_cost)}</div>}
                  {form.travel_type !== 'comercial' && (
                    <div>• Acréscimo {form.travel_type === 'urgencia' ? '50% (urgência)' : '30% (FDS/feriado)'}</div>
                  )}
                </div>
              )}
            </div>
          </DialogContent>
        </Dialog>
      )}
    </>
  );
}
