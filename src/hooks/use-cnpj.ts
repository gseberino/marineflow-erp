import { useState, useCallback } from 'react';

export type BrasilApiCnpjResult = {
  cnpj: string;
  razao_social: string;
  nome_fantasia: string;
  descricao_situacao_cadastral: string;
  logradouro: string;
  numero: string;
  complemento: string;
  bairro: string;
  municipio: string;
  uf: string;
  cep: string;
  ddd_telefone_1: string;
  email: string;
  cnae_fiscal_descricao: string;
};

export function useCnpj() {
  const [cnpjLoading, setCnpjLoading] = useState(false);
  const [cnpjError, setCnpjError] = useState<string | null>(null);

  const fetchByCnpj = useCallback(async (cnpj: string): Promise<BrasilApiCnpjResult | null> => {
    const clean = cnpj.replace(/\D/g, '');
    if (clean.length !== 14) return null;
    
    setCnpjLoading(true);
    setCnpjError(null);
    try {
      const r = await fetch(`https://brasilapi.com.br/api/cnpj/v1/${clean}`);
      if (!r.ok) {
        throw new Error('CNPJ não encontrado ou erro na API');
      }
      const data: BrasilApiCnpjResult = await r.json();
      return data;
    } catch (e: any) {
      setCnpjError(e.message || 'Erro ao buscar CNPJ');
      return null;
    } finally {
      setCnpjLoading(false);
    }
  }, []);

  return {
    cnpjLoading,
    cnpjError,
    fetchByCnpj,
  };
}
