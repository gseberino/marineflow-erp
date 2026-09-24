// A tradução de erro de banco tem que errar para o lado seguro.
//
// Os casos aqui não são inventados: as mensagens vieram de `app_error_logs`, que registra
// o que o dono viu na tela. A de chave duplicada apareceu cinco vezes em agosto/2026,
// enquanto ele cadastrava produto.
//
// O teste cobre os dois riscos, e o segundo é o pior: traduzir o que não devia. Uma
// mensagem já escrita em português ("Preencha cliente...") que virasse outra coisa deixaria
// o usuário sem saber o que fazer, e um palpite errado sobre um erro técnico é pior que o
// texto técnico — este, ao menos, dá para pesquisar.
import { describe, it, expect } from 'vitest';
import { traduzErroDoBanco, paraOUsuario } from './erro-em-portugues';

describe('traduz o que o Postgres escreve', () => {
  it('chave duplicada nomeia a coisa e o campo — o caso real de 27/08', () => {
    expect(traduzErroDoBanco(
      'duplicate key value violates unique constraint "products_sku_key"',
    )).toBe('Já existe um(a) produto com este SKU.');
  });

  it('chave duplicada com campo de nome composto', () => {
    expect(traduzErroDoBanco(
      'duplicate key value violates unique constraint "clients_cpf_cnpj_key"',
    )).toBe('Já existe um(a) cliente com este CPF/CNPJ.');
  });

  it('índice desconhecido ainda vira frase útil, sem inventar o campo', () => {
    const frase = traduzErroDoBanco(
      'duplicate key value violates unique constraint "tabela_exotica_xyz_key"',
    );
    expect(frase).toBe('Já existe um registro com esse valor — ele precisa ser único.');
    expect(frase).not.toContain('exotica');
  });

  it('apagar algo que outro registro usa', () => {
    expect(traduzErroDoBanco(
      'update or delete on table "clients" violates foreign key constraint "service_orders_client_id_fkey" on table "service_orders", key is still referenced from table "service_orders"',
    )).toBe('Não dá para excluir: existe ordem de serviço usando este registro.');
  });

  it('apontar para algo que não existe é o erro OPOSTO, e a frase muda', () => {
    expect(traduzErroDoBanco(
      'insert or update on table "service_orders" violates foreign key constraint "service_orders_client_id_fkey"',
    )).toBe('O registro relacionado não existe (ou foi removido).');
  });

  it('campo obrigatório vazio', () => {
    expect(traduzErroDoBanco(
      'null value in column "name" of relation "products" violates not-null constraint',
    )).toBe('Falta preencher: nome.');
  });

  it('permissão (RLS)', () => {
    expect(traduzErroDoBanco(
      'new row violates row-level security policy for table "payables"',
    )).toBe('Seu usuário não tem permissão para fazer isso.');
  });

  it('texto acima do limite diz QUAL é o limite', () => {
    expect(traduzErroDoBanco(
      'value too long for type character varying(60)',
    )).toBe('Texto longo demais: o limite é 60 caracteres.');
  });

  it.each([
    ['numeric', 'Número em formato inválido.'],
    ['date', 'Data em formato inválido.'],
    ['uuid', 'Identificador inválido.'],
  ])('formato inválido de %s', (tipo, esperado) => {
    expect(traduzErroDoBanco(`invalid input syntax for type ${tipo}: "abc"`)).toBe(esperado);
  });

  // PGRST201 derruba o embed inteiro e a tela fica vazia — dizer "sem registros" mentiria.
  it('ligação ambígua avisa que os dados estão salvos', () => {
    const frase = traduzErroDoBanco(
      "Could not embed because more than one relationship was found for 'service_orders' and 'clients'",
    );
    expect(frase).toContain('ligação ambígua');
    expect(frase).toContain('dados estão salvos');
  });

  it('DELETE sem filtro diz que nada foi alterado', () => {
    expect(traduzErroDoBanco('DELETE requires a WHERE clause')).toContain('nada foi alterado');
  });
});

describe('não traduz o que não deve', () => {
  it.each([
    'Preencha cliente, embarcação e descrição do problema',
    'Escolha o cliente antes de confirmar',
    'Estoque insuficiente. Disponível: -1, solicitado adicional: 1',
    'Espelho: Código IBGE do município não foi resolvido — confira UF e cidade.',
    'Homologação: SEFAZ rejected (321) — Rejeicao: NF-e de devolucao',
    'Edge Function returned a non-2xx status code',
    'Failed to fetch',
    '',
  ])('deixa passar: %s', (msg) => {
    expect(traduzErroDoBanco(msg)).toBeNull();
    expect(paraOUsuario(msg)).toBe(msg);
  });

  it('entrada que não é texto não quebra nada', () => {
    expect(traduzErroDoBanco(undefined as unknown as string)).toBeNull();
    expect(traduzErroDoBanco(null as unknown as string)).toBeNull();
    expect(traduzErroDoBanco({ message: 'x' } as unknown as string)).toBeNull();
  });
});
