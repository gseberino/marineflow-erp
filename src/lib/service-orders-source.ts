/**
 * De onde cada cargo LÊ a ordem de serviço — e o que cada cargo pode ESCREVER nela
 * (NOVO-006 / NOVO-008 / NOVO-020).
 *
 * O técnico lê de views sem nenhuma coluna de valor (a OS e os seus itens); todos os
 * outros cargos leem das tabelas. A escrita continua sempre na tabela, mas o payload do
 * técnico passa por `payloadParaCargo`, que tira as colunas de valor: sem isso, um
 * formulário semeado a partir da view (onde o campo não existe) mandaria `0`/`''` para
 * a tabela base e apagaria desconto, comissão e condição de pagamento a cada Salvar
 * (NOVO-020b — foi o que derrubou a primeira tentativa, em 11/08).
 *
 * Isto NÃO é controle de acesso: é o frontend pedindo a fonte certa e não devolvendo o que
 * não leu. Quem impede de verdade é a migration
 * `20260910120000_views_tecnico_sem_valores.sql` junto com a RLS. Um técnico que chamasse a
 * REST na mão continuaria lendo `service_orders` enquanto a política daquela tabela
 * permitir — fechar isso é o passo seguinte (RLS por cargo na tabela-mãe).
 */

export const OS_TABELA = 'service_orders' as const;
export const OS_VIEW_TECNICO = 'service_orders_tecnico' as const;
export const OS_PARTS_VIEW_TECNICO = 'service_order_parts_tecnico' as const;
export const OS_SERVICES_VIEW_TECNICO = 'service_order_services_tecnico' as const;

export type FonteDaOS = typeof OS_TABELA | typeof OS_VIEW_TECNICO;

/**
 * Colunas que a view da OS NÃO pode ter — a mesma lista que a migration deixou de fora.
 *
 * Existe em código para o teste conseguir cobrar a migration: se alguém acrescentar uma
 * coluna de valor à view, o teste falha antes de o banco receber. Critério: valor monetário,
 * percentual de precificação/comissão, forma/condição de pagamento, situação financeira
 * (decisão (b) do dono, 11/08) e `share_token` — que abre o link público onde os valores
 * aparecem.
 *
 * É também a lista que `payloadParaCargo` retira do Salvar do técnico.
 */
export const COLUNAS_DE_VALOR_DA_OS = [
  'hourly_rate',
  'labor_cost_total',
  'travel_cost_per_km',
  'travel_cost_total',
  'parts_cost_total',
  'subcontract_cost_total',
  'operational_cost_total',
  'discount_amount',
  'discount_services_pct',
  'discount_parts_pct',
  'tax_amount',
  'grand_total',
  'original_quote_amount',
  'contingency_pct',
  'commission_rate',
  'commission_amount',
  'commissioned_person',
  'commissioned_user_id',
  'card_fee_amount',
  'card_fee_passthrough_enabled',
  'card_installments',
  'ferry_cost',
  'financial_notes',
  'payment_conditions',
  'payment_condition_preset_id',
  'payment_method',
  'payment_method_preferred',
  'custom_payment_installments',
  'invoicing_status',
  'payment_status',
  'share_token',
] as const;

/** Colunas de valor dos ITENS que as views irmãs deixam de fora (NOVO-008). */
export const COLUNAS_DE_VALOR_DAS_PECAS = [
  'unit_cost_snapshot', 'unit_sale_snapshot', 'line_total_cost', 'line_total_sale',
  'discount_amount', 'discount_pct', 'currency_snapshot',
] as const;
export const COLUNAS_DE_VALOR_DOS_SERVICOS = [
  'unit_price_snapshot', 'line_total', 'discount_amount', 'discount_pct',
] as const;

/** Cargos, como gravados em `app_users.role`. */
export type CargoDoUsuario = 'admin' | 'technician' | 'financial' | 'seller' | 'external_seller' | 'other';

/**
 * A view já existe no banco?
 *
 * `false` até a migration estar aplicada em produção E os tipos regenerados. Enquanto for
 * `false`, TODO cargo lê da tabela — inclusive o técnico, exatamente como antes.
 *
 * As duas metades não sobem juntas: a migration é commitada antes de ser aplicada (regra 1
 * do CLAUDE.md) e o frontend é publicado a cada push na main. Sem a chave, a janela entre
 * publicar e aplicar deixaria o técnico consultando uma view inexistente — a tela do
 * trabalho dele responderia erro.
 *
 * PARA LIGAR, nesta ordem: (1) aplicar a migration; (2) regenerar
 * `src/integrations/supabase/types.ts`; (3) virar esta chave para `true`; (4) provar com a
 * chave anon que os embeds resolvem (42501 = resolvido; PGRST200 = falhou).
 */
export const VIEW_TECNICO_DISPONIVEL = true;

/**
 * Fonte de LEITURA da OS para um cargo.
 *
 * Cargo desconhecido ou ausente cai na tabela, e é deliberado: a view é uma restrição para
 * um cargo específico, não um modo seguro genérico. Devolver a view para quem não se sabe
 * quem é esconderia dados de um financeiro cujo perfil ainda não carregou, e o sintoma
 * (campos sumindo da tela sem explicação) seria pior de diagnosticar do que o problema.
 */
export function fonteDeLeituraDaOS(
  cargo: string | null | undefined,
  viewDisponivel: boolean = VIEW_TECNICO_DISPONIVEL,
): FonteDaOS {
  return viewDisponivel && cargo === 'technician' ? OS_VIEW_TECNICO : OS_TABELA;
}

/** O cargo lê pelas views do técnico? (mesma regra da fonte — um lugar só decide.) */
export function leDaViewDoTecnico(
  cargo: string | null | undefined,
  viewDisponivel: boolean = VIEW_TECNICO_DISPONIVEL,
): boolean {
  return fonteDeLeituraDaOS(cargo, viewDisponivel) === OS_VIEW_TECNICO;
}

/**
 * O que um cargo pode mandar no UPDATE/INSERT da OS.
 *
 * Técnico: o payload sai SEM as colunas de valor. Não é só porque ele não deve editá-las —
 * é porque o formulário dele foi semeado a partir da view, onde essas colunas não existem;
 * reenviá-las gravaria `0`/`''` por cima do que o financeiro negociou (NOVO-020b).
 * Demais cargos: payload intacto. Função pura, testada.
 */
export function payloadParaCargo<T extends Record<string, unknown>>(
  cargo: string | null | undefined,
  payload: T,
  viewDisponivel: boolean = VIEW_TECNICO_DISPONIVEL,
): Partial<T> {
  if (!leDaViewDoTecnico(cargo, viewDisponivel)) return payload;
  const proibidas = new Set<string>(COLUNAS_DE_VALOR_DA_OS);
  const limpo: Record<string, unknown> = {};
  for (const [chave, valor] of Object.entries(payload)) {
    if (!proibidas.has(chave)) limpo[chave] = valor;
  }
  return limpo as Partial<T>;
}

/** Quem é "o escritório" — uma definição só, para a tela e para as regras de troca. */
export const CARGOS_DO_ESCRITORIO = ['admin', 'financial', 'seller'] as const;

export function ehDoEscritorio(cargo: string | null | undefined): boolean {
  return (CARGOS_DO_ESCRITORIO as readonly string[]).includes(cargo ?? '');
}

/**
 * O cargo pode trocar o cliente de uma OS que já existe? Só o escritório (decisão do dono,
 * 21/10/2026: técnico não troca). Cargo ainda não carregado também NÃO — a regra falha fechada:
 * esconder o "Trocar" por um instante é melhor que deixá-lo aberto ao técnico. Criar a OS e
 * escolher o primeiro cliente, pode qualquer um.
 */
export function podeTrocarClienteDaOS(cargo: string | null | undefined): boolean {
  return ehDoEscritorio(cargo);
}

/**
 * O cargo pode trocar a embarcação/veículo de uma OS que JÁ TEM uma? Só o escritório (decisão do
 * dono, 22/10/2026). Escolher a primeira unidade de uma OS sem unidade continua livre (do mesmo
 * cliente). Cargo ainda não carregado também não: falha fechada, como no cliente.
 */
export function podeTrocarEmbarcacaoDaOS(cargo: string | null | undefined): boolean {
  return ehDoEscritorio(cargo);
}

/**
 * O payload de ATUALIZAÇÃO de uma OS que já existe: o de payloadParaCargo e, para quem não troca,
 * sem client_id e — se a OS já tinha embarcação/veículo — sem vessel_id. Sem o vessel_id, a tela
 * do técnico aberta antes de o escritório trocar a unidade não a devolve para a antiga ao salvar.
 * É a defesa do lado do app; quem garante é o gatilho no banco (os_tecnico_nao_troca_cliente).
 *
 * `unidadeGravada`: o vessel_id da OS como a tela a leu. `null`/'' = a OS não tinha unidade (a
 * primeira escolha vai). `undefined` = não se sabe: sai também (falha fechada).
 */
export function payloadDeAtualizacaoParaCargo<T extends Record<string, unknown>>(
  cargo: string | null | undefined,
  payload: T,
  opcoes: { unidadeGravada?: string | null; viewDisponivel?: boolean } = {},
): Partial<T> {
  const porCargo = payloadParaCargo(cargo, payload, opcoes.viewDisponivel ?? VIEW_TECNICO_DISPONIVEL);
  if (podeTrocarClienteDaOS(cargo)) return porCargo;
  const { client_id: _naoTroca, ...semCliente } = porCargo as Record<string, unknown>;
  const osSemUnidade = opcoes.unidadeGravada === null || opcoes.unidadeGravada === '';
  if (osSemUnidade || podeTrocarEmbarcacaoDaOS(cargo)) return semCliente as Partial<T>;
  const { vessel_id: _naoTrocaUnidade, ...semUnidade } = semCliente;
  return semUnidade as Partial<T>;
}

/**
 * Cadastros que já existem (decisão do dono, 22/10/2026): só o escritório troca o DONO de uma
 * embarcação/veículo e muda o nome, o CPF/CNPJ ou o tipo (PF/PJ) de um cliente. Telefone, e-mail,
 * endereço e o resto, o técnico continua podendo. Criar o cadastro continua livre. Cargo ainda não
 * carregado: travado (falha fechada). Quem garante é o banco (gatilhos da migration 20261022180000).
 */
export function podeMudarDonoEIdentidadeDoCadastro(cargo: string | null | undefined): boolean {
  return ehDoEscritorio(cargo);
}

/** As colunas que identificam o cliente — as que só o escritório muda. */
export const COLUNAS_DE_IDENTIDADE_DO_CLIENTE = ['name', 'cpf_cnpj', 'type'] as const;

/**
 * O payload de EDIÇÃO de um cliente: para quem não muda a identidade, sem nome, CPF/CNPJ e tipo.
 * Sem isso, o diálogo aberto antes de o escritório corrigir o nome o desfaria ao salvar o telefone
 * (e o gatilho do banco recusaria a gravação inteira).
 */
export function payloadDeEdicaoDoClienteParaCargo<T extends Record<string, unknown>>(
  cargo: string | null | undefined,
  payload: T,
): Partial<T> {
  if (podeMudarDonoEIdentidadeDoCadastro(cargo)) return payload;
  const travadas = new Set<string>(COLUNAS_DE_IDENTIDADE_DO_CLIENTE);
  const limpo: Record<string, unknown> = {};
  for (const [chave, valor] of Object.entries(payload)) {
    if (!travadas.has(chave)) limpo[chave] = valor;
  }
  return limpo as Partial<T>;
}

/** O payload de EDIÇÃO de uma embarcação/veículo: para quem não troca o dono, sem client_id. */
export function payloadDeEdicaoDaUnidadeParaCargo<T extends Record<string, unknown>>(
  cargo: string | null | undefined,
  payload: T,
): Partial<T> {
  if (podeMudarDonoEIdentidadeDoCadastro(cargo)) return payload;
  const { client_id: _naoTrocaDono, ...semDono } = payload as Record<string, unknown>;
  return semDono as Partial<T>;
}
