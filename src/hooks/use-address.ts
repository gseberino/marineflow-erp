import { useState, useEffect, useRef, useCallback } from 'react';

export type ViaCepResult = {
  logradouro: string;
  bairro: string;
  localidade: string;
  uf: string;
  erro?: boolean;
};

export type NominatimResult = {
  name: string;
  lat: string;
  lon: string;
};

export type IbgeState = {
  id: number;
  sigla: string;
  nome: string;
};

export function useAddress() {
  const [states, setStates] = useState<IbgeState[]>([]);
  const [statesLoading, setStatesLoading] = useState(false);
  const [cities, setCities] = useState<string[]>([]);
  const [citiesLoading, setCitiesLoading] = useState(false);
  const [selectedState, setSelectedStateInternal] = useState('');
  const [cepLoading, setCepLoading] = useState(false);
  const [cepError, setCepError] = useState<string | null>(null);
  const [addressSuggestions, setAddressSuggestions] = useState<NominatimResult[]>([]);
  const [addressSearchLoading, setAddressSearchLoading] = useState(false);

  const searchDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lastNominatimCall = useRef(0);

  // Fetch states once on mount
  useEffect(() => {
    setStatesLoading(true);
    fetch('https://servicodados.ibge.gov.br/api/v1/localidades/estados?orderBy=nome')
      .then(r => r.json())
      .then((data: IbgeState[]) => setStates(data))
      .catch(() => setStates([]))
      .finally(() => setStatesLoading(false));
  }, []);

  const setSelectedState = useCallback((uf: string) => {
    setSelectedStateInternal(uf);
    if (!uf) {
      setCities([]);
      return;
    }
    setCitiesLoading(true);
    fetch(`https://servicodados.ibge.gov.br/api/v1/localidades/estados/${uf}/municipios?orderBy=nome`)
      .then(r => r.json())
      .then((data: Array<{ nome: string }>) => setCities(data.map(c => c.nome)))
      .catch(() => setCities([]))
      .finally(() => setCitiesLoading(false));
  }, []);

  const fetchByCep = useCallback(async (cep: string): Promise<ViaCepResult | null> => {
    const clean = cep.replace(/\D/g, '');
    if (clean.length !== 8) return null;
    setCepLoading(true);
    setCepError(null);
    try {
      const r = await fetch(`https://viacep.com.br/ws/${clean}/json/`);
      const data: ViaCepResult = await r.json();
      if (data.erro) {
        setCepError('CEP não encontrado');
        return null;
      }
      return data;
    } catch {
      setCepError('Erro ao buscar CEP');
      return null;
    } finally {
      setCepLoading(false);
    }
  }, []);

  const searchAddress = useCallback(async (query: string) => {
    if (searchDebounceRef.current) clearTimeout(searchDebounceRef.current);
    if (query.length < 4) {
      setAddressSuggestions([]);
      return;
    }
    searchDebounceRef.current = setTimeout(async () => {
      const now = Date.now();
      const timeSinceLast = now - lastNominatimCall.current;
      if (timeSinceLast < 1000) {
        await new Promise(resolve => setTimeout(resolve, 1000 - timeSinceLast));
      }
      setAddressSearchLoading(true);
      try {
        lastNominatimCall.current = Date.now();
        const r = await fetch(
          `https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(query)}&countrycodes=br&limit=5`,
          { headers: { 'User-Agent': 'MarineFlow-ERP/1.0' } }
        );
        const data: NominatimResult[] = await r.json();
        setAddressSuggestions(data);
      } catch {
        setAddressSuggestions([]);
      } finally {
        setAddressSearchLoading(false);
      }
    }, 400);
  }, []);

  const clearAddressSuggestions = useCallback(() => {
    setAddressSuggestions([]);
  }, []);

  const geocodeAddress = useCallback(async (address: string): Promise<NominatimResult | null> => {
    const now = Date.now();
    const timeSinceLast = now - lastNominatimCall.current;
    if (timeSinceLast < 1000) {
      await new Promise(resolve => setTimeout(resolve, 1000 - timeSinceLast));
    }
    try {
      lastNominatimCall.current = Date.now();
      const r = await fetch(
        `https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(address)}&countrycodes=br&limit=1`,
        { headers: { 'User-Agent': 'MarineFlow-ERP/1.0' } }
      );
      const data: NominatimResult[] = await r.json();
      return data[0] ?? null;
    } catch {
      return null;
    }
  }, []);

  return {
    states,
    statesLoading,
    cities,
    citiesLoading,
    selectedState,
    setSelectedState,
    cepLoading,
    cepError,
    fetchByCep,
    addressSuggestions,
    addressSearchLoading,
    searchAddress,
    clearAddressSuggestions,
    geocodeAddress,
  };
}
