import { useState, useEffect, useRef } from 'react';
import { useI18n } from '@/i18n';
import { useAddress } from '@/hooks/use-address';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Button } from '@/components/ui/button';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Command, CommandInput, CommandEmpty, CommandGroup, CommandItem, CommandList } from '@/components/ui/command';
import { Loader2, Check, ChevronsUpDown, MapPin, ExternalLink } from 'lucide-react';
import { cn } from '@/lib/utils';
import { toast } from 'sonner';

interface AddressFieldsProps {
  value: {
    postal_code: string;
    address_line_1: string;
    address_number: string;
    address_complement: string;
    neighborhood: string;
    city: string;
    state: string;
    country: string;
    latitude?: number | null;
    longitude?: number | null;
  };
  onChange: (field: string, value: string | number | null) => void;
  showCoordinates?: boolean;
  coordinatesReadOnly?: boolean;
}

function formatCep(v: string): string {
  const digits = v.replace(/\D/g, '').slice(0, 8);
  if (digits.length <= 5) return digits;
  return `${digits.slice(0, 5)}-${digits.slice(5)}`;
}

export function AddressFields({ value, onChange, showCoordinates = true, coordinatesReadOnly = true }: AddressFieldsProps) {
  const { t } = useI18n();
  const {
    states, cities, citiesLoading, selectedState, setSelectedState,
    cepLoading, cepError, fetchByCep,
    addressSuggestions, addressSearchLoading, searchAddress, clearAddressSuggestions,
    geocodeAddress,
  } = useAddress();

  const [stateOpen, setStateOpen] = useState(false);
  const [cityOpen, setCityOpen] = useState(false);
  const [geoLoading, setGeoLoading] = useState(false);
  const blurTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Sync selectedState with value.state on mount
  useEffect(() => {
    if (value.state && value.state !== selectedState) {
      setSelectedState(value.state);
    }
  }, []);

  const handleCepChange = async (raw: string) => {
    const formatted = formatCep(raw);
    onChange('postal_code', formatted);
    const digits = raw.replace(/\D/g, '');
    if (digits.length === 8) {
      const result = await fetchByCep(digits);
      if (result) {
        onChange('address_line_1', result.logradouro);
        onChange('neighborhood', result.bairro);
        onChange('city', result.localidade);
        onChange('state', result.uf);
        setSelectedState(result.uf);
      }
    }
  };

  const handleGeocode = async () => {
    const query = [value.address_line_1, value.address_number, value.city, value.state].filter(Boolean).join(', ');
    if (!query) return;
    setGeoLoading(true);
    const result = await geocodeAddress(query);
    setGeoLoading(false);
    if (result) {
      onChange('latitude', parseFloat(result.lat));
      onChange('longitude', parseFloat(result.lon));
    } else {
      toast.error(t.address.cepNotFound);
    }
  };

  return (
    <div className="space-y-4">
      {/* 1. CEP */}
      <div className="col-span-2">
        <Label>{t.address.postalCode}</Label>
        <div className="relative">
          <Input
            value={value.postal_code}
            onChange={e => handleCepChange(e.target.value)}
            placeholder="00000-000"
            maxLength={9}
          />
          {cepLoading && <Loader2 className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 animate-spin text-muted-foreground" />}
        </div>
        {cepError && <p className="text-xs text-destructive mt-1">{t.address.cepNotFound}</p>}
        <a
          href="https://buscacepinter.correios.com.br"
          target="_blank"
          rel="noopener noreferrer"
          className="text-xs text-muted-foreground hover:text-foreground mt-1 inline-flex items-center gap-1"
        >
          {t.address.dontKnowCep} <ExternalLink className="h-3 w-3" />
        </a>
      </div>

      {/* 2. Logradouro with autocomplete */}
      <div className="relative">
        <Label>{t.address.street}</Label>
        <div className="relative">
          <Input
            value={value.address_line_1}
            onChange={e => {
              onChange('address_line_1', e.target.value);
              searchAddress(e.target.value);
            }}
            onBlur={() => {
              blurTimeoutRef.current = setTimeout(() => clearAddressSuggestions(), 200);
            }}
            onFocus={() => {
              if (blurTimeoutRef.current) clearTimeout(blurTimeoutRef.current);
            }}
          />
          {addressSearchLoading && <Loader2 className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 animate-spin text-muted-foreground" />}
        </div>
        {addressSuggestions.length > 0 && (
          <div className="absolute top-full left-0 right-0 z-50 max-h-48 overflow-y-auto rounded-lg border bg-popover shadow-md mt-1">
            {addressSuggestions.map((s, i) => (
              <div
                key={i}
                className="px-3 py-2 text-sm cursor-pointer hover:bg-muted truncate"
                onMouseDown={e => e.preventDefault()}
                onClick={() => {
                  onChange('address_line_1', s.display_name.slice(0, 80));
                  onChange('latitude', parseFloat(s.lat));
                  onChange('longitude', parseFloat(s.lon));
                  clearAddressSuggestions();
                }}
              >
                {s.display_name.slice(0, 80)}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* 3. Número + Complemento */}
      <div className="grid grid-cols-3 gap-4">
        <div>
          <Label>{t.address.number}</Label>
          <Input
            value={value.address_number}
            onChange={e => onChange('address_number', e.target.value)}
            placeholder="123"
          />
        </div>
        <div className="col-span-2">
          <Label>{t.address.complement}</Label>
          <Input
            value={value.address_complement}
            onChange={e => onChange('address_complement', e.target.value)}
            placeholder="Apto, Sala, Galpão, Portão..."
          />
        </div>
      </div>

      {/* 4. Bairro */}
      <div>
        <Label>{t.address.neighborhood}</Label>
        <Input
          value={value.neighborhood}
          onChange={e => onChange('neighborhood', e.target.value)}
        />
      </div>

      {/* 5. Estado + Cidade */}
      <div className="grid grid-cols-5 gap-4">
        <div className="col-span-2">
          <Label>{t.address.state}</Label>
          <Popover open={stateOpen} onOpenChange={setStateOpen}>
            <PopoverTrigger asChild>
              <Button variant="outline" role="combobox" className="w-full justify-between font-normal">
                {value.state
                  ? `${value.state} — ${states.find(s => s.sigla === value.state)?.nome ?? ''}`
                  : t.address.selectState}
                <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
              </Button>
            </PopoverTrigger>
            <PopoverContent className="w-[280px] p-0" align="start">
              <Command>
                <CommandInput placeholder={t.address.state} />
                <CommandList>
                  <CommandEmpty>{t.common.noResults}</CommandEmpty>
                  <CommandGroup>
                    {states.map(s => (
                      <CommandItem
                        key={s.sigla}
                        value={`${s.sigla} ${s.nome}`}
                        onSelect={() => {
                          onChange('state', s.sigla);
                          onChange('city', '');
                          setSelectedState(s.sigla);
                          setStateOpen(false);
                        }}
                      >
                        <Check className={cn("mr-2 h-4 w-4", value.state === s.sigla ? "opacity-100" : "opacity-0")} />
                        {s.sigla} — {s.nome}
                      </CommandItem>
                    ))}
                  </CommandGroup>
                </CommandList>
              </Command>
            </PopoverContent>
          </Popover>
        </div>
        <div className="col-span-3">
          <Label>{t.address.city}</Label>
          <Popover open={cityOpen} onOpenChange={setCityOpen}>
            <PopoverTrigger asChild>
              <Button
                variant="outline"
                role="combobox"
                disabled={!value.state}
                className="w-full justify-between font-normal"
              >
                {citiesLoading ? (
                  <span className="flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> {t.common.loading}</span>
                ) : value.city ? value.city : !value.state ? t.address.selectStateFirst : t.address.selectCity}
                <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
              </Button>
            </PopoverTrigger>
            <PopoverContent className="w-[280px] p-0" align="start">
              <Command>
                <CommandInput placeholder={t.address.city} />
                <CommandList>
                  <CommandEmpty>{t.common.noResults}</CommandEmpty>
                  <CommandGroup>
                    {cities.map(c => (
                      <CommandItem
                        key={c}
                        value={c}
                        onSelect={() => {
                          onChange('city', c);
                          setCityOpen(false);
                        }}
                      >
                        <Check className={cn("mr-2 h-4 w-4", value.city === c ? "opacity-100" : "opacity-0")} />
                        {c}
                      </CommandItem>
                    ))}
                  </CommandGroup>
                </CommandList>
              </Command>
            </PopoverContent>
          </Popover>
        </div>
      </div>

      {/* 6. País */}
      <div>
        <Label>{t.address.country}</Label>
        <Input value={value.country} onChange={e => onChange('country', e.target.value)} />
      </div>

      {/* 7. Coordinates */}
      {showCoordinates && (
        <div className="rounded-lg border bg-muted/30 p-3 space-y-2">
          {value.latitude && value.longitude ? (
            <p className="text-sm flex items-center gap-1">
              <MapPin className="h-4 w-4" /> {Number(value.latitude).toFixed(6)}, {Number(value.longitude).toFixed(6)}
            </p>
          ) : (
            <p className="text-sm text-muted-foreground">{t.address.coordinates}: {t.common.noResults}</p>
          )}
          <p className="text-xs text-muted-foreground">{t.address.coordinatesAuto}</p>
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={handleGeocode}
            disabled={geoLoading}
          >
            {geoLoading ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <MapPin className="h-4 w-4 mr-2" />}
            {t.address.searchCoordinates}
          </Button>
        </div>
      )}
    </div>
  );
}
