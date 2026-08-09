// MCC — Merchant Category Code (ISO 18245) → plano de contas.
//
// POR QUE ISTO VALE MAIS QUE UM CLASSIFICADOR DE TEXTO
// O MCC é atribuído pela bandeira ao credenciar o estabelecimento e viaja em toda compra
// no cartão. 5812 é restaurante em qualquer adquirente do mundo; 5541 é posto de
// combustível; 5251 é loja de ferragens. Não depende de como a maquininha escreve o nome,
// não muda quando o lojista troca de adquirente, e não precisa de adivinhação.
//
// É exatamente o caso que a IA não resolvia bem: "MP *GTEKENERGIASU" e "EC *INOHOUSE" não
// contêm palavra nenhuma do plano de contas, mas carregam MCC. Classificação determinística
// e auditável ganha de palpite — e sai de graça.
//
// A LISTA É CURTA DE PROPÓSITO
// Só MCCs que aparecem de fato no extrato desta empresa (eletroeletrônica e energia para
// lancha e motorhome) ou que são inequívocos. MCC que não está aqui devolve null e segue
// para as camadas seguintes: memória, regra de texto, IA. Mapear mal é pior que não mapear,
// porque uma categoria errada com cara de certeza ninguém revisa.

export interface CategoriaPorMcc {
  categoria: string;
  dreGroup: string;
  /** O que este código significa, para quem for auditar a decisão. */
  rotulo: string;
}

const MAPA: Record<string, CategoriaPorMcc> = {
  // ── Combustível e deslocamento ──
  "5541": { categoria: "Combustível e deslocamento", dreGroup: "custo_direto", rotulo: "Posto de combustível" },
  "5542": { categoria: "Combustível e deslocamento", dreGroup: "custo_direto", rotulo: "Posto automatizado" },
  "5983": { categoria: "Combustível e deslocamento", dreGroup: "custo_direto", rotulo: "Distribuidor de combustível" },
  "4121": { categoria: "Combustível e deslocamento", dreGroup: "custo_direto", rotulo: "Táxi/aplicativo de transporte" },
  "7523": { categoria: "Pedágio e estacionamento", dreGroup: "custo_direto", rotulo: "Estacionamento" },
  "4784": { categoria: "Pedágio e estacionamento", dreGroup: "custo_direto", rotulo: "Pedágio" },

  // ── Peças, materiais e ferramentas ──
  "5251": { categoria: "Ferramentas e equipamentos", dreGroup: "despesa_operacional", rotulo: "Loja de ferragens" },
  "5200": { categoria: "Ferramentas e equipamentos", dreGroup: "despesa_operacional", rotulo: "Material de construção" },
  "5211": { categoria: "Ferramentas e equipamentos", dreGroup: "despesa_operacional", rotulo: "Madeireira/construção" },
  "5722": { categoria: "Peças e materiais", dreGroup: "custo_direto", rotulo: "Eletrodomésticos" },
  "5732": { categoria: "Peças e materiais", dreGroup: "custo_direto", rotulo: "Loja de eletrônicos" },
  "5065": { categoria: "Peças e materiais", dreGroup: "custo_direto", rotulo: "Peças eletrônicas (atacado)" },
  "5013": { categoria: "Peças e materiais", dreGroup: "custo_direto", rotulo: "Peças automotivas (atacado)" },
  "5533": { categoria: "Peças e materiais", dreGroup: "custo_direto", rotulo: "Autopeças" },
  "5551": { categoria: "Peças e materiais", dreGroup: "custo_direto", rotulo: "Náutica e barcos" },
  "5571": { categoria: "Peças e materiais", dreGroup: "custo_direto", rotulo: "Motocicletas" },

  // ── Alimentação de campo ──
  "5812": { categoria: "Alimentação de campo", dreGroup: "custo_direto", rotulo: "Restaurante" },
  "5814": { categoria: "Alimentação de campo", dreGroup: "custo_direto", rotulo: "Lanchonete/fast food" },
  "5462": { categoria: "Alimentação de campo", dreGroup: "custo_direto", rotulo: "Padaria" },
  "5411": { categoria: "Alimentação de campo", dreGroup: "custo_direto", rotulo: "Supermercado" },
  "5499": { categoria: "Alimentação de campo", dreGroup: "custo_direto", rotulo: "Mercearia/conveniência" },

  // ── Serviços e assinaturas ──
  "5817": { categoria: "Software e assinaturas", dreGroup: "despesa_operacional", rotulo: "Aplicativo digital" },
  "5818": { categoria: "Software e assinaturas", dreGroup: "despesa_operacional", rotulo: "Bem digital" },
  "7372": { categoria: "Software e assinaturas", dreGroup: "despesa_operacional", rotulo: "Programação/software" },
  "4816": { categoria: "Software e assinaturas", dreGroup: "despesa_operacional", rotulo: "Serviços de rede/internet" },
  "4814": { categoria: "Telefonia e internet", dreGroup: "despesa_operacional", rotulo: "Telecomunicações" },
  "4899": { categoria: "Telefonia e internet", dreGroup: "despesa_operacional", rotulo: "TV a cabo/streaming" },

  // ── Manutenção ──
  "7538": { categoria: "Manutenção de veículo", dreGroup: "despesa_operacional", rotulo: "Oficina mecânica" },
  "7534": { categoria: "Manutenção de veículo", dreGroup: "despesa_operacional", rotulo: "Borracharia" },
  "7549": { categoria: "Manutenção de veículo", dreGroup: "despesa_operacional", rotulo: "Guincho" },

  // ── Hospedagem e viagem ──
  "7011": { categoria: "Hospedagem e Hotelaria", dreGroup: "despesa_operacional", rotulo: "Hotel/hospedagem" },
  "3000": { categoria: "Hospedagem e Hotelaria", dreGroup: "despesa_operacional", rotulo: "Companhia aérea" },
  "4511": { categoria: "Hospedagem e Hotelaria", dreGroup: "despesa_operacional", rotulo: "Passagem aérea" },

  // ── Serviços profissionais ──
  "8931": { categoria: "Contabilidade e assessoria", dreGroup: "despesa_operacional", rotulo: "Contabilidade/auditoria" },
  "8111": { categoria: "Contabilidade e assessoria", dreGroup: "despesa_operacional", rotulo: "Serviços jurídicos" },
  "6300": { categoria: "Seguro", dreGroup: "despesa_operacional", rotulo: "Seguradora" },

  // ── Frete ──
  "4215": { categoria: "Frete e importação", dreGroup: "custo_direto", rotulo: "Transportadora/courier" },
  "4214": { categoria: "Frete e importação", dreGroup: "custo_direto", rotulo: "Frete rodoviário" },

  // ── Códigos que APARECERAM no extrato desta empresa ─────────────────────────
  //
  // A primeira versão desta tabela foi escrita de cabeça e cobria 34 códigos. Quando o
  // MCC finalmente chegou nas 895 transações, 34 códigos REAIS estavam de fora — mais da
  // metade do volume. Os que entram agora vieram do extrato, cada um com os
  // estabelecimentos que o justificam; o resto continua fora, porque mapear um código
  // ambíguo é criar erro com aparência de certeza.
  "5734": { categoria: "Software e assinaturas", dreGroup: "despesa_operacional", rotulo: "Loja de software" },
  "4722": { categoria: "Hospedagem e Hotelaria", dreGroup: "despesa_operacional", rotulo: "Agência de viagem/hospedagem" },
  "5912": { categoria: "Assistência médica/farmacêutica", dreGroup: "despesa_operacional", rotulo: "Farmácia/drogaria" },
  "5099": { categoria: "Peças e materiais", dreGroup: "custo_direto", rotulo: "Bens duráveis (atacado)" },
  "5085": { categoria: "Peças e materiais", dreGroup: "custo_direto", rotulo: "Suprimentos industriais" },
  "5532": { categoria: "Manutenção de veículo", dreGroup: "despesa_operacional", rotulo: "Autopeças/pneus" },
  "5813": { categoria: "Alimentação de campo", dreGroup: "custo_direto", rotulo: "Bar/casa noturna" },
};

/**
 * Códigos que aparecem no extrato e que NÃO mapeamos de propósito.
 *
 * Documentados para que ninguém os "esqueça" de novo — e para deixar claro que a ausência
 * é decisão, não descuido. Cada um agrupa coisas demais para uma categoria só:
 *
 *   8999 Serviços profissionais    · pessoas físicas avulsas, adquirentes (FROGPAY, PGZ)
 *   5947 Presentes/novidades       · um estabelecimento só, e não é presente
 *   8641 Associações               · mensalidade de iate clube — pode ser várias coisas
 *   5311 Loja de departamento      · de refrigeração a bazar
 *   5921 Bebidas                   · aqui é água e gás, não bebida
 *   5999 Varejo diverso            · genérico por definição
 *   8299 Educação                  · aparece com adquirente no meio
 *   5199 Não duráveis (atacado)    · genérico
 *   5942 Livraria                  · é a Amazon vendendo qualquer coisa
 *
 * Todos caem na camada seguinte — memória, regra de texto, IA —, que é onde eles têm mais
 * chance de acertar do que um código que significa "diversos".
 */
export const MCCS_AMBIGUOS_CONHECIDOS = [
  "8999", "5947", "8641", "5311", "5921", "5999", "8299", "5199", "5942",
];

/**
 * Categoria a partir do MCC. Devolve null quando o código não está mapeado — e null aqui
 * significa "não sei", que é uma resposta melhor que um palpite com cara de certeza.
 */
export function categoriaPorMcc(mcc: string | null | undefined): CategoriaPorMcc | null {
  if (!mcc) return null;
  const chave = String(mcc).replace(/\D/g, "").padStart(4, "0");
  return MAPA[chave] ?? null;
}

/** Quantos códigos a tabela conhece — usado no relato do motor. */
export const MCCS_CONHECIDOS = Object.keys(MAPA).length;
