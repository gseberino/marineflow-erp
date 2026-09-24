/**
 * Erro de banco vira frase que o usuário entende.
 *
 * O log de produção mostra o problema sem margem para dúvida: em 25 e 27/08/2026 o dono
 * viu cinco vezes, na tela, a frase
 *
 *     duplicate key value violates unique constraint "products_sku_key"
 *
 * Ele queria cadastrar um produto e recebeu o nome de um índice. A mensagem está correta —
 * e é inútil: não diz o que fazer, não diz qual campo, e ainda assusta.
 *
 * A tradução acontece num ponto só (o interceptador de `toast.error` em `diagnostics.ts`),
 * pelo mesmo motivo que o log acontece lá: são 232 chamadas espalhadas, e mexer em cada
 * uma seria trocar um problema por 232 oportunidades de esquecer.
 *
 * REGRA DE OURO DESTE MÓDULO: **na dúvida, não traduz.** Devolve `null` e a mensagem
 * original passa intacta. Um palpite errado é pior que o texto técnico, porque o texto
 * técnico pelo menos pode ser pesquisado. E o log guarda sempre o ORIGINAL — a tradução
 * é para a tela, não para o diagnóstico.
 */

/** Tabela → como se fala dela. Só entra aqui o que aparece em mensagem de erro. */
const COISAS: Record<string, string> = {
  products: 'produto',
  services: 'serviço',
  clients: 'cliente',
  vessels: 'embarcação',
  marinas: 'marina',
  suppliers: 'fornecedor',
  service_orders: 'ordem de serviço',
  purchase_orders: 'ordem de compra',
  fiscal_notes: 'nota fiscal',
  receivables: 'conta a receber',
  payables: 'conta a pagar',
  bank_transactions: 'lançamento bancário',
  profiles: 'usuário',
  app_settings: 'configuração',
};

/** Coluna → como se fala dela, quando o nome técnico não basta. */
const CAMPOS: Record<string, string> = {
  sku: 'SKU',
  cpf_cnpj: 'CPF/CNPJ',
  cnpj_cpf: 'CNPJ/CPF',
  nfe_key: 'chave da NF-e',
  email: 'e-mail',
  phone: 'telefone',
  name: 'nome',
  slug: 'identificador',
  key: 'chave',
};

/**
 * Lê `products_sku_key` / `clients_cpf_cnpj_unique` e devolve {coisa, campo}.
 *
 * O nome do índice é convenção, não garantia — por isso cada parte só é usada quando
 * bate com algo conhecido, e o resto vira frase genérica.
 */
function leNomeDoIndice(nome: string): { coisa?: string; campo?: string } {
  const semSufixo = nome.replace(/_(key|unique|uniq|idx|pkey)$/i, '');
  for (const [tabela, coisa] of Object.entries(COISAS)) {
    if (semSufixo === tabela || semSufixo.startsWith(tabela + '_')) {
      const resto = semSufixo.slice(tabela.length).replace(/^_/, '');
      return { coisa, campo: resto ? (CAMPOS[resto] ?? resto.replace(/_/g, ' ')) : undefined };
    }
  }
  return {};
}

/**
 * Traduz, ou devolve `null` quando não reconhece a forma do erro.
 *
 * Nunca traduz mensagem que já está em português: toda regra exige um trecho em inglês
 * que só o Postgres/PostgREST escreve.
 */
export function traduzErroDoBanco(original: string): string | null {
  if (!original || typeof original !== 'string') return null;
  const t = original.toLowerCase();

  // Chave duplicada — o caso que o dono viu cinco vezes.
  if (t.includes('duplicate key value violates unique constraint')) {
    const nome = /constraint\s+"([^"]+)"/i.exec(original)?.[1] ?? '';
    const { coisa, campo } = leNomeDoIndice(nome);
    if (coisa && campo) return `Já existe um(a) ${coisa} com este ${campo}.`;
    if (coisa) return `Já existe um(a) ${coisa} igual a este.`;
    return 'Já existe um registro com esse valor — ele precisa ser único.';
  }

  // Referência: as duas pontas do mesmo erro, e elas pedem frases opostas.
  if (t.includes('violates foreign key constraint')) {
    // "still referenced from table X" = tentou APAGAR algo que outro registro usa.
    if (t.includes('still referenced')) {
      const alvo = /referenced from table "([^"]+)"/i.exec(original)?.[1] ?? '';
      const coisa = COISAS[alvo];
      return coisa
        ? `Não dá para excluir: existe ${coisa} usando este registro.`
        : 'Não dá para excluir: outro registro depende deste.';
    }
    return 'O registro relacionado não existe (ou foi removido).';
  }

  if (t.includes('violates not-null constraint')) {
    const col = /column\s+"([^"]+)"/i.exec(original)?.[1] ?? '';
    const campo = CAMPOS[col] ?? col.replace(/_/g, ' ');
    return campo ? `Falta preencher: ${campo}.` : 'Falta preencher um campo obrigatório.';
  }

  if (t.includes('violates check constraint')) {
    return 'O valor informado não é aceito neste campo.';
  }

  if (t.includes('violates row-level security policy') || t.includes('permission denied for')) {
    return 'Seu usuário não tem permissão para fazer isso.';
  }

  if (t.includes('value too long for type character varying')) {
    const n = /\((\d+)\)/.exec(original)?.[1];
    return n ? `Texto longo demais: o limite é ${n} caracteres.` : 'Texto longo demais para este campo.';
  }

  if (t.includes('invalid input syntax for type')) {
    const tipo = /for type (\w+)/i.exec(original)?.[1] ?? '';
    if (tipo === 'numeric' || tipo === 'integer') return 'Número em formato inválido.';
    if (tipo === 'date' || tipo === 'timestamp' || tipo === 'timestamptz') return 'Data em formato inválido.';
    if (tipo === 'uuid') return 'Identificador inválido.';
    return 'Valor em formato inválido.';
  }

  // PGRST201: duas chaves estrangeiras para a mesma tabela derrubam o embed INTEIRO, e a
  // tela costuma aparecer vazia. Dizer "não há registros" seria mentira.
  if (t.includes('more than one relationship was found')) {
    return 'A lista não pôde ser carregada por um problema na consulta (ligação ambígua). Avise o suporte — os dados estão salvos.';
  }

  // Trava do próprio Postgrest contra apagar/atualizar a tabela inteira. É defeito de
  // código, não do usuário, mas quem lê a tela precisa saber que nada foi alterado.
  if (t.includes('requires a where clause')) {
    return 'A operação foi recusada por segurança e nada foi alterado. Avise o suporte.';
  }

  return null;
}

/** Para o interceptador: a frase da tela. O log continua guardando o original. */
export function paraOUsuario(original: string): string {
  return traduzErroDoBanco(original) ?? original;
}
