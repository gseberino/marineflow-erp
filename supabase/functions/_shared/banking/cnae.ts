// Atividade da empresa na Receita (CNAE) → categoria de despesa do plano de contas.
//
// É o equivalente, para Pix e transferência, do que o MCC já faz no cartão: um fato sobre
// quem recebeu, atribuído por terceiro, que não depende de como o nome aparece no extrato.
// Usado só para SUGERIR a categoria de quem está sendo cadastrado agora — nunca passa por
// cima de regra sua ou de histórico.
//
// A tabela vai do código mais específico para o mais geral (o primeiro prefixo que casar
// vence). Atividade que não aparece aqui não sugere nada: "não sei" é melhor que um
// palpite que vira "Outras despesas" com cara de certeza.

const TABELA: Array<[prefixo: string, categoria: string]> = [
  // Combustível e deslocamento
  ["4731", "Combustível e deslocamento"],
  ["4732", "Combustível e deslocamento"],
  // Pedágio e estacionamento
  ["5221", "Pedágio e estacionamento"],
  ["5222", "Pedágio e estacionamento"],
  ["5223", "Pedágio e estacionamento"],
  // Frete e importação
  ["4930", "Frete e importação"],
  ["5211", "Frete e importação"],
  ["5212", "Frete e importação"],
  ["5250", "Frete e importação"],
  ["5310", "Frete e importação"],
  ["5320", "Frete e importação"],
  // Hospedagem
  ["551", "Hospedagem e Hotelaria"],
  ["559", "Hospedagem e Hotelaria"],
  // Alimentação
  ["561", "Alimentação de campo"],
  ["562", "Alimentação de campo"],
  ["4711", "Alimentação de campo"],
  ["4712", "Alimentação de campo"],
  ["4721", "Alimentação de campo"],
  ["4722", "Alimentação de campo"],
  ["4723", "Alimentação de campo"],
  ["4729", "Alimentação de campo"],
  // Veículos
  ["4520", "Manutenção de veículo"],
  ["4530", "Peças e materiais"],
  ["4541", "Peças e materiais"],
  // Material elétrico, náutico e peças — o que a HBR mais compra
  ["4742", "Peças e materiais"],
  ["4673", "Peças e materiais"],
  ["4669", "Peças e materiais"],
  ["4689", "Peças e materiais"],
  ["47636", "Peças e materiais"],     // embarcações, peças e acessórios
  ["4757", "Peças e materiais"],     // peças de eletrodomésticos
  ["2710", "Peças e materiais"],     // fabricação de geradores/transformadores
  ["2731", "Peças e materiais"],
  ["2732", "Peças e materiais"],
  ["2733", "Peças e materiais"],     // fios e cabos
  ["2740", "Peças e materiais"],
  ["2790", "Peças e materiais"],
  // Ferramentas e equipamentos
  ["4744", "Ferramentas e equipamentos"],
  ["4679", "Ferramentas e equipamentos"],
  ["4661", "Ferramentas e equipamentos"],
  ["4662", "Ferramentas e equipamentos"],
  ["4663", "Ferramentas e equipamentos"],
  ["4664", "Ferramentas e equipamentos"],
  ["4665", "Ferramentas e equipamentos"],
  ["4751", "Ferramentas e equipamentos"],
  ["4752", "Ferramentas e equipamentos"],
  ["7732", "Ferramentas e equipamentos"],     // aluguel de máquinas
  // Escritório
  ["4761", "Material de escritório"],
  ["4647", "Material de escritório"],
  // Saúde
  ["4771", "Assistência médica/farmacêutica"],
  ["86", "Assistência médica/farmacêutica"],
  // Serviços de terceiros (instalação, manutenção, engenharia)
  ["331", "Serviços de terceiros"],
  ["332", "Serviços de terceiros"],
  ["432", "Serviços de terceiros"],
  ["711", "Serviços de terceiros"],
  ["8299", "Serviços de terceiros"],
  // Despesa operacional
  ["61", "Telefonia e internet"],
  ["62", "Software e assinaturas"],
  ["631", "Software e assinaturas"],
  ["65", "Seguro"],
  ["68", "Aluguel e condomínio"],
  ["8112", "Aluguel e condomínio"],
  ["69", "Contabilidade e assessoria"],
  ["7020", "Contabilidade e assessoria"],
  ["73", "Marketing e publicidade"],
  // Setor público
  ["841", "Impostos e taxas"],
];

/** Código só com dígitos, sem pontuação ("4744-0/99" → "4744099"). */
function soDigitos(cnae: string | number | null | undefined): string {
  return String(cnae ?? "").replace(/\D/g, "");
}

export function categoriaPorCnae(cnae: string | number | null | undefined): string | null {
  const d = soDigitos(cnae);
  if (d.length < 2) return null;
  let melhor: [string, string] | null = null;
  for (const linha of TABELA) {
    if (d.startsWith(linha[0]) && (!melhor || linha[0].length > melhor[0].length)) melhor = linha;
  }
  return melhor ? melhor[1] : null;
}

/** O que a consulta pública de CNPJ devolve, reduzido ao que o cadastro usa. */
export interface DadosDaReceita {
  cnpj: string;
  razao_social: string | null;
  nome_fantasia: string | null;
  situacao: string | null;
  cnae: string | null;
  cnae_descricao: string | null;
  cep: string | null;
  logradouro: string | null;
  numero: string | null;
  complemento: string | null;
  bairro: string | null;
  cidade: string | null;
  uf: string | null;
  telefone: string | null;
  email: string | null;
  categoria_sugerida: string | null;
}

const vazio = (v: unknown) => {
  const s = String(v ?? "").trim();
  return s === "" ? null : s;
};

/** Converte a resposta da BrasilAPI (/api/cnpj/v1) para o formato do cadastro. */
export function lerRespostaDaReceita(cnpj: string, j: Record<string, unknown>): DadosDaReceita {
  const cnae = vazio(j.cnae_fiscal);
  const tel = vazio(j.ddd_telefone_1);
  return {
    cnpj,
    razao_social: vazio(j.razao_social),
    nome_fantasia: vazio(j.nome_fantasia),
    situacao: vazio(j.descricao_situacao_cadastral),
    cnae,
    cnae_descricao: vazio(j.cnae_fiscal_descricao),
    cep: vazio(j.cep),
    logradouro: [vazio(j.descricao_tipo_de_logradouro), vazio(j.logradouro)].filter(Boolean).join(" ") || null,
    numero: vazio(j.numero),
    complemento: vazio(j.complemento),
    bairro: vazio(j.bairro),
    cidade: vazio(j.municipio),
    uf: vazio(j.uf),
    telefone: tel ? tel.replace(/\D/g, "") : null,
    email: vazio(j.email),
    categoria_sugerida: categoriaPorCnae(cnae),
  };
}
