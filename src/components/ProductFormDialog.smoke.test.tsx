// Smoke de render do cadastro de produto.
//
// Existe por causa do bloco "Cabo de potência CC": são dois campos que o
// dimensionamento lê para escolher o cabo, e um erro de render aqui não aparece
// no `tsc` nem no build — aparece quando alguém vai cadastrar um cabo.
// Ver a memória `feedback_validar_por_render` (incidente TDZ de 24/07).
//
// NOTA PARA QUEM MEXER: todo mock devolve a MESMA referência a cada chamada.
// Devolver `() => ({ data: [] })` cria um objeto novo por render, e os
// `useEffect` do formulário que dependem desses valores entram em laço infinito
// — o teste não falha, ele trava e come CPU. Em produção não acontece porque o
// React Query devolve referência estável.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { I18nProvider } from '@/i18n';
import { ProductFormDialog } from './ProductFormDialog';

vi.mock('@/integrations/supabase/client', () => {
  const storage = {
    upload: async () => ({ error: null }),
    getPublicUrl: () => ({ data: { publicUrl: '' } }),
  };
  return { supabase: { storage: { from: () => storage } } };
});
vi.mock('@/hooks/use-products', () => {
  const m = { mutateAsync: async () => ({}), isPending: false };
  return { useCreateProduct: () => m, useUpdateProduct: () => m };
});
vi.mock('@/hooks/use-product-suppliers', () => {
  const lista = { data: [], isLoading: false };
  const m = { mutateAsync: async () => ({}), isPending: false };
  return {
    useProductSuppliers: () => lista,
    useAddProductSupplier: () => m,
    useUpdateProductSupplier: () => m,
    useRemoveProductSupplier: () => m,
  };
});
vi.mock('@/hooks/use-suppliers', () => {
  const r = { data: [] };
  return { useSuppliers: () => r };
});
vi.mock('@/hooks/use-product-categories', () => {
  const r = { data: [] };
  return { useProductCategories: () => r };
});
vi.mock('@/hooks/use-app-settings', () => {
  const r = { data: {} };
  return { useAppSettings: () => r };
});
// Sugestão fiscal por IA, do trabalho da frente fiscal que entrou neste diálogo.
vi.mock('@/hooks/use-nfse', () => {
  const m = { mutate: () => {}, mutateAsync: async () => ({}), isPending: false };
  return { useFiscalSuggest: () => m };
});

const abrir = () =>
  render(
    <I18nProvider>
      <ProductFormDialog open onOpenChange={() => {}} />
    </I18nProvider>,
  );

describe('ProductFormDialog — smoke de render', () => {
  it('abre sem crashar', () => {
    abrir();
    expect(document.querySelector('input')).toBeTruthy();
  });

  // Os dois campos que ligam o catálogo ao dimensionamento. Sem eles na tela,
  // todo cabo novo nasce invisível para a escolha de bitola.
  it('mostra a seção e a isolação do condutor', () => {
    abrir();
    expect(screen.getByText(/Cabo de potência CC/i)).toBeTruthy();
    expect(screen.getByText(/Seção do condutor/i)).toBeTruthy();
    expect(screen.getByText('Isolação')).toBeTruthy();
  });

  // A política impressa ao lado do campo é o que impede a próxima pessoa de
  // deduzir a isolação pelo nome do produto — errar para cima libera bitola que
  // o cabo não aguenta.
  // Por texto do documento, não por elemento: "90 °C" aparece duas vezes na
  // tela — na política e como opção do seletor —, e `getByText` recusa ambiguidade.
  it('imprime a política da HBR junto do campo', () => {
    abrir();
    const tela = document.body.textContent ?? '';
    expect(tela).toContain('Política da HBR');
    expect(tela).toContain('90 °C');
    expect(tela).toContain('105 °C');
    expect(tela).toContain('a partir de 25 mm²');
  });
});
