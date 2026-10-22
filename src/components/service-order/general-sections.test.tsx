// Seção "Cliente & Embarcação" montada (20 e 21/10/2026): as fichas, o contato do solicitante, os
// rótulos e dicas acima dos campos, e as regras de troca com o formulário de verdade (estado real).
import { useState } from 'react';
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { I18nProvider } from '@/i18n';

vi.mock('@/components/ClientFormDialog', () => ({ ClientFormDialog: () => null }));
vi.mock('@/components/VesselFormDialog', () => ({ VesselFormDialog: () => null }));
vi.mock('@/hooks/use-ficha-cliente', () => ({
  useSaldoEmAberto: () => ({ data: undefined }),
  useClientesRecentes: () => ({ data: [] }),
}));
// Levantamento da OS: o teste decide se há um.
const lev = vi.hoisted(() => ({ tem: false }));
vi.mock('@/hooks/use-service-survey', () => ({
  useServiceOrderSurvey: () => ({ data: lev.tem ? { id: 's1' } : null, isError: false, isLoading: false }),
}));

import { GeneralSections } from './general-sections';

const base = {
  active: true, type: 'individual', whatsapp: null, email: null, cpf_cnpj: null, address_line_1: null,
  neighborhood: null, city: null, state: null, postal_code: null, notes: null, opt_out_whatsapp: false,
  ie_indicator: 9, state_registration: null,
};
const joao = { ...base, id: 'c1', name: 'João da Silva', phone: '(47) 99999-1234' };
const maria = { ...base, id: 'c2', name: 'Maria Souza', phone: null };
const barco = {
  id: 'v1', client_id: 'c1', name: 'Netuno II', active: true, asset_type: 'Lancha', manufacturer: 'Schaefer',
  model: '400', year: 2019, length_feet: 40, marina_id: 'm1', marinas: null, access_notes: 'Vaga B12',
};
// Maria tem dois barcos (com um só, o formulário escolheria sozinho).
const barcosDaMaria = [
  { id: 'v2', client_id: 'c2', name: 'Atlântico', active: true, asset_type: 'Veleiro', manufacturer: null, model: null,
    year: null, length_feet: null, marina_id: 'm2', marinas: null, access_notes: 'Seco, galpão 3' },
  { id: 'v3', client_id: 'c2', name: 'Brisa', active: true, asset_type: 'Lancha', manufacturer: null, model: null,
    year: null, length_feet: null, marina_id: 'm3', marinas: null, access_notes: null },
];
// O João tem um segundo barco (para trocar dentro do mesmo cliente).
const ventoSul = { id: 'v4', client_id: 'c1', name: 'Vento Sul', active: true, asset_type: 'Veleiro', manufacturer: null,
  model: null, year: null, length_feet: null, marina_id: null, marinas: null, access_notes: null };
const todosOsBarcos = [barco, ...barcosDaMaria, ventoSul];
const marinheiro = { id: 'k1', vessel_id: 'v1', full_name: 'Pedro Marinheiro', role: 'captain', phone: '(47) 98888-7777', email: null, active: true };

/** A seção com o formulário em estado de verdade: o que a tela muda, a tela mostra. */
function Tela({ inicial, orderData = null, aoMudar }: {
  inicial: Record<string, unknown>; orderData?: unknown; aoMudar?: (f: Record<string, any>) => void;
}) {
  const [form, setForm] = useState<Record<string, any>>({
    status: 'draft', priority: 'normal', service_type: 'repair', requested_by_name: '', marina_id: '', site_access: '', ...inicial,
  });
  aoMudar?.(form);
  const nada = () => {};
  return (
    <I18nProvider>
      <MemoryRouter>
        <GeneralSections
          isNew={!orderData} isLocked={false} orderData={orderData}
          form={form}
          set={(campo, valor) => setForm((f) => ({ ...f, [campo]: valor }))}
          setForm={setForm}
          clients={[joao, maria]} allVessels={todosOsBarcos}
          clientVessels={todosOsBarcos.filter((b) => b.client_id === form.client_id)}
          marinas={[{ id: 'm1', name: 'Marina Itajaí', active: true }]} appUsers={[]}
          vesselContacts={form.vessel_id === 'v1' ? [marinheiro] : []}
          selectedTechnicians={[]} setSelectedTechnicians={nada}
          setQuickMarinaOpen={nada} setQuickMarinaName={nada}
          isOptimizing={false} optimizeText={nada}
        />
      </MemoryRouter>
    </I18nProvider>
  );
}

describe('GeneralSections — cliente, embarcação e solicitante', () => {
  it('com cliente, embarcação e solicitante escolhidos, as fichas e o contato aparecem', () => {
    render(<Tela inicial={{ client_id: 'c1', vessel_id: 'v1', requested_by_contact_id: 'k1', requested_by_name: 'Pedro Marinheiro' }} />);
    expect(screen.getByLabelText('Dados do cliente')).toHaveTextContent('João da Silva');
    expect(screen.getByLabelText('Dados da embarcação ou veículo')).toHaveTextContent('Schaefer 400');
    expect(screen.getByRole('link', { name: /\(47\) 98888-7777/ })).toHaveAttribute('href', 'tel:+5547988887777');
    expect(screen.getByRole('link', { name: 'Abrir conversa com o solicitante no WhatsApp' }))
      .toHaveAttribute('href', 'https://wa.me/5547988887777');
  });

  it('sem embarcação e sem solicitante, nenhuma ficha a mais', () => {
    render(<Tela inicial={{ client_id: 'c1', vessel_id: '', requested_by_contact_id: '' }} />);
    expect(screen.queryByLabelText('Dados da embarcação ou veículo')).not.toBeInTheDocument();
    expect(screen.queryByRole('link', { name: /98888-7777/ })).not.toBeInTheDocument();
  });

  it('unidade sem contatos: a dica do solicitante diz o tipo dela (decisão 9)', () => {
    render(<Tela inicial={{ client_id: 'c1', vessel_id: 'v4' }} />);
    expect(screen.getByText('Cadastre os contatos do veleiro Vento Sul para aparecerem aqui.')).toBeInTheDocument();
    expect(screen.queryByText(/contatos na embarcação/)).not.toBeInTheDocument();
  });

  it('a dica fica ENTRE o rótulo e o campo, e o campo aponta para ela', () => {
    render(<Tela inicial={{ client_id: 'c1', vessel_id: 'v1' }} />);
    const campo = screen.getByLabelText('Local do serviço e acesso');
    const dica = screen.getByText(/^Sai na via do técnico\./);
    expect(campo).toHaveAttribute('aria-describedby', dica.id);
    // rótulo → dica → campo, nessa ordem no documento
    const rotulo = screen.getByText('Local do serviço e acesso', { selector: 'label' });
    expect(rotulo.compareDocumentPosition(dica) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(dica.compareDocumentPosition(campo) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it('trocar o cliente numa OS salva: confirma, tira embarcação, solicitante e as sugestões do barco antigo; o barco novo traz as dele', async () => {
    const user = userEvent.setup();
    let form: Record<string, any> = {};
    render(<Tela
      orderData={{ id: 'os1' }}
      inicial={{ status: 'open', client_id: 'c1', vessel_id: 'v1', marina_id: 'm1', requested_by_contact_id: 'k1', requested_by_name: 'Pedro Marinheiro', site_access: 'Vaga B12' }}
      aoMudar={(f) => { form = f; }}
    />);
    await user.click(screen.getByRole('button', { name: /^Trocar cliente/ }));
    await user.type(screen.getByRole('combobox', { name: 'Buscar cliente' }), 'maria');
    await user.click(await screen.findByRole('option', { name: /Maria Souza/ }));
    // diz tudo o que sai — inclusive marina e local, que vieram do barco do João
    expect(await screen.findByText(
      'De João da Silva para Maria Souza. Saem: a lancha Netuno II, o solicitante Pedro Marinheiro, '
      + 'a marina sugerida (Marina Itajaí) e o local e acesso da lancha.',
    )).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Trocar cliente' }));

    expect(form).toMatchObject({
      client_id: 'c2', vessel_id: '', requested_by_contact_id: '', requested_by_name: '',
      marina_id: '', site_access: '',
    });
    expect(screen.getByText('Escolha a embarcação ou veículo de Maria Souza. Até lá, a troca do cliente não fica salva.'))
      .toBeInTheDocument();
    // o seletor de embarcação aponta para o aviso
    const seletor = screen.getByRole('combobox', { name: /Embarcação/ });
    expect(seletor).toHaveAttribute('aria-describedby', 'os-aviso-embarcacao');

    // escolhido o barco da Maria, entram a marina e o acesso DELE (não ficam os do barco do João)
    await user.click(seletor);
    await user.click(await screen.findByRole('option', { name: /Atlântico/ }));
    expect(form).toMatchObject({ vessel_id: 'v2', marina_id: 'm2', site_access: 'Seco, galpão 3' });
    expect(screen.queryByText(/Escolha a embarcação ou veículo/)).not.toBeInTheDocument();
  });

  it('cliente com um barco só já entra com ele, no mesmo passo (sem o aviso de escolher)', async () => {
    const user = userEvent.setup();
    let form: Record<string, any> = {};
    // Maria com um barco só: o Brisa vira do João para o teste
    const soUm = todosOsBarcos.filter((b) => b.id !== 'v3');
    function TelaSoUm() {
      const [f, setF] = useState<Record<string, any>>({ status: 'open', client_id: 'c1', vessel_id: '', marina_id: '', site_access: '', requested_by_name: '' });
      form = f;
      const nada = () => {};
      return (
        <I18nProvider><MemoryRouter>
          <GeneralSections isNew isLocked={false} orderData={null} form={f}
            set={(c, v) => setF((x) => ({ ...x, [c]: v }))} setForm={setF}
            clients={[joao, maria]} allVessels={soUm} clientVessels={soUm.filter((b) => b.client_id === f.client_id)}
            marinas={[]} appUsers={[]} vesselContacts={[]} selectedTechnicians={[]} setSelectedTechnicians={nada}
            setQuickMarinaOpen={nada} setQuickMarinaName={nada} isOptimizing={false} optimizeText={nada} />
        </MemoryRouter></I18nProvider>
      );
    }
    render(<TelaSoUm />);
    await user.click(screen.getByRole('button', { name: /^Trocar cliente/ }));
    await user.type(screen.getByRole('combobox', { name: 'Buscar cliente' }), 'maria');
    await user.click(await screen.findByRole('option', { name: /Maria Souza/ }));
    expect(form).toMatchObject({ client_id: 'c2', vessel_id: 'v2', marina_id: 'm2', site_access: 'Seco, galpão 3' });
    expect(screen.queryByText(/Escolha a embarcação ou veículo/)).not.toBeInTheDocument();
  });

  it('escolher de novo a mesma embarcação não apaga o solicitante', async () => {
    const user = userEvent.setup();
    let form: Record<string, any> = {};
    render(<Tela
      inicial={{ client_id: 'c1', vessel_id: 'v1', requested_by_contact_id: 'k1', requested_by_name: 'Pedro Marinheiro' }}
      aoMudar={(f) => { form = f; }}
    />);
    // escolhida, é ficha; o "Trocar" abre a lista já aberta
    await user.click(screen.getByRole('button', { name: 'Trocar a lancha Netuno II' }));
    await user.click(await screen.findByRole('option', { name: /Netuno II/ }));
    expect(form).toMatchObject({ vessel_id: 'v1', requested_by_contact_id: 'k1', requested_by_name: 'Pedro Marinheiro' });
  });

  it('trocar a embarcação de OS salva com solicitante e levantamento: confirma dizendo o que acontece', async () => {
    lev.tem = true;
    const user = userEvent.setup();
    let form: Record<string, any> = {};
    render(<Tela
      orderData={{ id: 'os1' }}
      inicial={{ status: 'open', client_id: 'c1', vessel_id: 'v1', requested_by_contact_id: 'k1', requested_by_name: 'Pedro Marinheiro' }}
      aoMudar={(f) => { form = f; }}
    />);
    await user.click(screen.getByRole('button', { name: 'Trocar a lancha Netuno II' }));
    await user.click(await screen.findByRole('option', { name: /Vento Sul/ }));
    expect(await screen.findByText(
      'De Lancha Netuno II para Veleiro Vento Sul. Sai o solicitante Pedro Marinheiro, que é contato da antiga. '
      + 'O levantamento feito na antiga fica com ela: esta OS vai precisar de outro.',
    )).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Trocar' }));
    expect(form).toMatchObject({ vessel_id: 'v4', requested_by_contact_id: '', requested_by_name: '' });
    lev.tem = false;
  });

  it('OS nova: trocar a embarcação passa direto, mesmo com solicitante', async () => {
    const user = userEvent.setup();
    let form: Record<string, any> = {};
    render(<Tela
      inicial={{ client_id: 'c1', vessel_id: 'v1', requested_by_contact_id: 'k1', requested_by_name: 'Pedro Marinheiro' }}
      aoMudar={(f) => { form = f; }}
    />);
    await user.click(screen.getByRole('button', { name: 'Trocar a lancha Netuno II' }));
    await user.click(await screen.findByRole('option', { name: /Vento Sul/ }));
    expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument();
    expect(form).toMatchObject({ vessel_id: 'v4' });
  });

  it('solicitante que não está entre os contatos ativos (desativado depois) também pede confirmação', async () => {
    const user = userEvent.setup();
    let form: Record<string, any> = {};
    render(<Tela
      orderData={{ id: 'os1' }}
      inicial={{ status: 'open', client_id: 'c1', vessel_id: 'v1', requested_by_contact_id: 'k9', requested_by_name: 'Ana Antiga' }}
      aoMudar={(f) => { form = f; }}
    />);
    await user.click(screen.getByRole('button', { name: 'Trocar a lancha Netuno II' }));
    await user.click(await screen.findByRole('option', { name: /Vento Sul/ }));
    expect(await screen.findByText(
      'De Lancha Netuno II para Veleiro Vento Sul. Sai o solicitante Ana Antiga, que é contato da antiga.',
    )).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Manter a atual' }));
    expect(form).toMatchObject({ vessel_id: 'v1', requested_by_contact_id: 'k9', requested_by_name: 'Ana Antiga' });
  });
});
