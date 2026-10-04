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
  // As buscas (IBGE, ViaCEP, Nominatim) respondem DEPOIS: se a tela já fechou, não há o que
  // atualizar. Sem isto, no CI a resposta do IBGE chegava com o ambiente de teste desmontado e
  // derrubava a suíte ("window is not defined", 04/10/2026) — mesmo com todos os testes passando.
  const montado = useRef(true);
  // Só a resposta do ÚLTIMO estado escolhido vale: trocar de UF rápido não deixa as cidades do
  // estado anterior chegarem depois e sobrescreverem as do novo.
  const ufPedida = useRef('');

  useEffect(() => {
    montado.current = true;
    return () => {
      montado.current = false;
      if (searchDebounceRef.current) clearTimeout(searchDebounceRef.current);
    };
  }, []);

  // Fetch states once on mount
  useEffect(() => {
    setStatesLoading(true);
    fetch('https://servicodados.ibge.gov.br/api/v1/localidades/estados?orderBy=nome')
      .then(r => r.json())
      .then((data: IbgeState[]) => { if (montado.current) setStates(data); })
      .catch(() => { if (montado.current) setStates([]); })
      .finally(() => { if (montado.current) setStatesLoading(false); });
  }, []);

  const setSelectedState = useCallback((uf: string) => {
    setSelectedStateInternal(uf);
    ufPedida.current = uf;
    if (!uf) {
      setCities([]);
      setCitiesLoading(false);
      return;
    }
    setCitiesLoading(true);
    const vale = () => montado.current && ufPedida.current === uf;
    fetch(`https://servicodados.ibge.gov.br/api/v1/localidades/estados/${uf}/municipios?orderBy=nome`)
      .then(r => r.json())
      .then((data: Array<{ nome: string }>) => { if (vale()) setCities(data.map(c => c.nome)); })
      .catch(() => { if (vale()) setCities([]); })
      .finally(() => { if (vale()) setCitiesLoading(false); });
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
        if (montado.current) setCepError('CEP não encontrado');
        return null;
      }
      return data;
    } catch {
      if (montado.current) setCepError('Erro ao buscar CEP');
      return null;
    } finally {
      if (montado.current) setCepLoading(false);
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
      if (!montado.current) return;
      setAddressSearchLoading(true);
      try {
        lastNominatimCall.current = Date.now();
        const r = await fetch(
          `https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(query)}&countrycodes=br&limit=5`,
          { headers: { 'User-Agent': 'MarineFlow-ERP/1.0' } }
        );
        const data: NominatimResult[] = await r.json();
        if (montado.current) setAddressSuggestions(data);
      } catch {
        if (montado.current) setAddressSuggestions([]);
      } finally {
        if (montado.current) setAddressSearchLoading(false);
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
