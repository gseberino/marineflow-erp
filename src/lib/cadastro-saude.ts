// Saúde do cadastro de fornecedores.
//
// POR QUE ISTO EXISTE
// O cadastro da Coremma tinha nome fantasia "Itajai" — a CIDADE. Como o casamento por nome
// aceitava substring, todo estabelecimento de Itajaí virou Coremma: 160 despesas
// (R$ 17 mil) atribuídas ao fornecedor errado, e com elas o histórico aprendido do errado
// sobrepondo a classificação certa. Nenhuma linha de erro em lugar nenhum.
//
// O matcher já foi corrigido para não cair mais nisso. Mas o dado continua sujo, e dado
// sujo encontra outro caminho para estragar — o próximo será diferente e igualmente mudo.
//
// O PRINCÍPIO QUE ORIENTA OS DETECTORES
// Não julgar se o nome é "bonito". Medir se ele IDENTIFICA. Um apelido que aparece em
// transações de outros fornecedores não é apelido — é ruído com aparência de identidade, e
// é exatamente isso que sequestra o casamento. A evidência é contável, então a acusação
// pode vir com número em vez de opinião.

export interface FornecedorParaAnalise {
  id: string;
  name: string;
  trade_name: string | null;
  cnpj_cpf: string | null;
  active: boolean;
  /** Quantos lançamentos usam este fornecedor. Zero = cadastro inerte. */
  lancamentos: number;
  /**
   * Em quantas transações do extrato o texto da fantasia aparece SEM que a transação
   * seja deste fornecedor. É a medida de "este apelido identifica outra gente".
   */
  fantasia_em_terceiros?: number;
}

export type GravidadeDoProblema = 'alta' | 'media' | 'baixa';

export interface ProblemaDeCadastro {
  fornecedorId: string;
  fornecedor: string;
  tipo:
    | 'fantasia_generica'
    | 'fantasia_igual_razao'
    | 'sem_documento'
    | 'documento_invalido'
    | 'duplicado'
    | 'inerte';
  gravidade: GravidadeDoProblema;
  /** O que está errado, em uma frase. */
  diagnostico: string;
  /** O dado que sustenta a acusação — sem isto é opinião. */
  evidencia: string;
  /** O que fazer, e o que acontece se fizer. */
  sugestao: string;
  /** Valor a gravar quando a sugestão é aceita. `null` limpa o campo. */
  correcao?: { campo: 'trade_name' | 'active'; valor: string | boolean | null };
}

const SO_DIGITOS = (v: string | null | undefined) => (v ?? '').replace(/\D/g, '');

/** Caixa alta, sem acento e sem pontuação. */
export function normalizar(v: string | null | undefined): string {
  return (v ?? '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, ' ')
    .trim();
}

/**
 * O dígito verificador confere?
 *
 * CNPJ com número inventado é PIOR que campo vazio: vazio a tela mostra como pendência,
 * inválido passa por identidade e casa transação com quem não devia.
 */
export function documentoValido(doc: string | null | undefined): boolean {
  const d = SO_DIGITOS(doc);
  if (d.length === 11) return cpfValido(d);
  if (d.length === 14) return cnpjValido(d);
  return false;
}

function cpfValido(cpf: string): boolean {
  if (/^(\d)\1{10}$/.test(cpf)) return false;
  for (const [inicio, pos] of [[9, 10], [10, 11]] as const) {
    let soma = 0;
    for (let i = 0; i < inicio; i++) soma += Number(cpf[i]) * (pos - i);
    const resto = (soma * 10) % 11 % 10;
    if (resto !== Number(cpf[inicio])) return false;
  }
  return true;
}

function cnpjValido(cnpj: string): boolean {
  if (/^(\d)\1{13}$/.test(cnpj)) return false;
  const calc = (base: string, pesos: number[]) => {
    const soma = base.split('').reduce((s, d, i) => s + Number(d) * pesos[i], 0);
    const r = soma % 11;
    return r < 2 ? 0 : 11 - r;
  };
  const d1 = calc(cnpj.slice(0, 12), [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]);
  const d2 = calc(cnpj.slice(0, 13), [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]);
  return d1 === Number(cnpj[12]) && d2 === Number(cnpj[13]);
}

/**
 * Analisa um fornecedor e devolve o que há de errado com ele.
 *
 * A ordem importa: o problema que sequestra casamento vem antes do que só ocupa espaço.
 */
export function analisarFornecedor(f: FornecedorParaAnalise): ProblemaDeCadastro[] {
  const problemas: ProblemaDeCadastro[] = [];
  const fantasia = (f.trade_name ?? '').trim();
  const fantasiaLimpa = normalizar(fantasia);
  const razaoLimpa = normalizar(f.name);
  const base = { fornecedorId: f.id, fornecedor: f.name };

  // ── O que faz o sistema errar ────────────────────────────────────────────────
  //
  // Apelido que aparece em transações de OUTROS não identifica ninguém: é o caso "Itajai".
  // A acusação vem com o número de transações, não com um julgamento sobre a palavra.
  if (fantasia && (f.fantasia_em_terceiros ?? 0) >= 3) {
    problemas.push({
      ...base,
      tipo: 'fantasia_generica',
      gravidade: 'alta',
      diagnostico: `"${fantasia}" aparece em transações que não são deste fornecedor.`,
      evidencia: `${f.fantasia_em_terceiros} transações do extrato contêm "${fantasia}" e pertencem a outros.`,
      sugestao:
        'Limpar o nome fantasia. Ele não identifica este fornecedor e pode atrair para cá '
        + 'despesas que são de outros — foi assim que 160 lançamentos foram parar no fornecedor errado.',
      correcao: { campo: 'trade_name', valor: null },
    });
  } else if (fantasia && fantasiaLimpa === razaoLimpa) {
    // Redundante, não perigoso: não muda casamento nenhum, só ocupa espaço e confunde
    // quem lê a ficha.
    problemas.push({
      ...base,
      tipo: 'fantasia_igual_razao',
      gravidade: 'baixa',
      diagnostico: 'O nome fantasia repete a razão social.',
      evidencia: `"${fantasia}" é igual a "${f.name}".`,
      sugestao: 'Limpar o campo. Não muda o reconhecimento — só tira a repetição da ficha.',
      correcao: { campo: 'trade_name', valor: null },
    });
  }

  // ── O que impede o sistema de acertar ───────────────────────────────────────
  const doc = SO_DIGITOS(f.cnpj_cpf);
  if (doc.length > 0 && !documentoValido(doc)) {
    problemas.push({
      ...base,
      tipo: 'documento_invalido',
      gravidade: 'alta',
      diagnostico: 'O CNPJ/CPF cadastrado não passa na conferência do dígito verificador.',
      evidencia: `"${f.cnpj_cpf}" tem ${doc.length} dígitos e o verificador não confere.`,
      sugestao:
        'Corrigir ou apagar. Documento inválido é pior que documento em branco: em branco a '
        + 'tela mostra pendência, inválido passa por identidade e casa transação com quem não devia.',
    });
  } else if (doc.length === 0 && f.lancamentos > 0) {
    // Só cobra documento de quem é usado: exigir de cadastro inerte é criar trabalho.
    problemas.push({
      ...base,
      tipo: 'sem_documento',
      gravidade: 'media',
      diagnostico: 'Sem CNPJ/CPF, e este fornecedor já tem lançamentos.',
      evidencia: `${f.lancamentos} lançamento(s) usam este cadastro.`,
      sugestao:
        'Preencher o documento. É o sinal MAIS FORTE de casamento — com ele, a transação '
        + 'é reconhecida sem depender de como o banco escreve o nome.',
    });
  }

  // ── O que só ocupa espaço ───────────────────────────────────────────────────
  if (f.lancamentos === 0 && f.active) {
    problemas.push({
      ...base,
      tipo: 'inerte',
      gravidade: 'baixa',
      diagnostico: 'Cadastro nunca usado em lançamento nenhum.',
      evidencia: 'Zero despesas vinculadas.',
      sugestao:
        'Arquivar. Some das listas de escolha e para de concorrer no reconhecimento por '
        + 'nome — mas continua no sistema, e volta a qualquer momento.',
      correcao: { campo: 'active', valor: false },
    });
  }

  return problemas;
}

/** Dois cadastros para o mesmo fornecedor racham o histórico aprendido em dois. */
export function acharDuplicados(
  fornecedores: FornecedorParaAnalise[],
): Array<{ chave: string; motivo: string; membros: FornecedorParaAnalise[] }> {
  const porDocumento = new Map<string, FornecedorParaAnalise[]>();
  const porNome = new Map<string, FornecedorParaAnalise[]>();

  for (const f of fornecedores) {
    const doc = SO_DIGITOS(f.cnpj_cpf);
    if (doc.length === 11 || doc.length === 14) {
      porDocumento.set(doc, [...(porDocumento.get(doc) ?? []), f]);
    }
    const nome = normalizar(f.name);
    if (nome) porNome.set(nome, [...(porNome.get(nome) ?? []), f]);
  }

  const grupos: Array<{ chave: string; motivo: string; membros: FornecedorParaAnalise[] }> = [];
  const jaVistos = new Set<string>();

  // Documento primeiro: é identidade, e um par por documento é certeza, não suspeita.
  for (const [doc, membros] of porDocumento) {
    if (membros.length < 2) continue;
    grupos.push({
      chave: `doc:${doc}`,
      motivo: `Mesmo CNPJ/CPF (${doc.length === 14 ? 'CNPJ' : 'CPF'})`,
      membros,
    });
    for (const m of membros) jaVistos.add(m.id);
  }

  for (const [nome, membros] of porNome) {
    if (membros.length < 2) continue;
    if (membros.every((m) => jaVistos.has(m.id))) continue;
    grupos.push({ chave: `nome:${nome}`, motivo: 'Mesmo nome', membros });
  }

  return grupos;
}

/** Ordena o que dói mais primeiro — é a fila de trabalho, não um relatório. */
export function ordenarProblemas(problemas: ProblemaDeCadastro[]): ProblemaDeCadastro[] {
  const peso: Record<GravidadeDoProblema, number> = { alta: 0, media: 1, baixa: 2 };
  return [...problemas].sort(
    (a, b) => peso[a.gravidade] - peso[b.gravidade] || a.fornecedor.localeCompare(b.fornecedor, 'pt-BR'),
  );
}
