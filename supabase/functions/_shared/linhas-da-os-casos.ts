// Os casos da ordem e do número das linhas da OS (F0 do porte da via v2, E17). Uma lista só: o Deno roda agora
// (linhas-da-os_test.ts) e o teste SQL da F2 roda a MESMA lista contra private._via_linhas_numeradas, para o "3" do
// cartão do WhatsApp ser sempre o "3" do papel. Dado sintético.

/** Uma linha como o banco devolve (o nome só para conferir). */
export interface LinhaDoCaso {
  id: string;
  created_at: string;
  nome: string;
}

export interface CasoDeOrdem {
  caso: string;
  /** Na ordem FÍSICA (a que o banco poderia devolver sem desempate). */
  linhas: LinhaDoCaso[];
  /** Os ids na ordem canônica; o número de cada um é a posição + 1. */
  ordem: string[];
}

const U = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

export const CASOS_DE_ORDEM: CasoDeOrdem[] = [
  {
    caso: 'empate com microssegundos: decide o microssegundo, não o id (Date.parse empataria)',
    linhas: [
      { id: U(1), created_at: '2026-11-16T18:01:02.123457+00:00', nome: 'Segundo' },
      { id: U(2), created_at: '2026-11-16T18:01:02.123456+00:00', nome: 'Primeiro' },
    ],
    ordem: [U(2), U(1)],
  },
  {
    caso: 'fração com zeros cortados: .12 < .1201 < .13, e sem fração < .000001',
    linhas: [
      { id: U(1), created_at: '2026-11-16T18:01:00.13+00:00', nome: 'C' },
      { id: U(2), created_at: '2026-11-16T18:01:00.1201+00:00', nome: 'B' },
      { id: U(3), created_at: '2026-11-16T18:01:00.12+00:00', nome: 'A' },
      { id: U(4), created_at: '2026-11-16T18:00:59.000001+00:00', nome: 'Zero e um' },
      { id: U(5), created_at: '2026-11-16T18:00:59+00:00', nome: 'Zero' },
    ],
    ordem: [U(5), U(4), U(3), U(2), U(1)],
  },
  {
    caso: 'empate total (INSERT de várias linhas): decide o id, em minúsculas',
    linhas: [
      { id: 'c0000000-0000-4000-8000-000000000000', created_at: '2026-11-14T04:25:59.5+00:00', nome: 'C' },
      { id: '0a000000-0000-4000-8000-000000000000', created_at: '2026-11-14T04:25:59.5+00:00', nome: 'A' },
      { id: '9f000000-0000-4000-8000-000000000000', created_at: '2026-11-14T04:25:59.5+00:00', nome: 'B' },
    ],
    ordem: ['0a000000-0000-4000-8000-000000000000', '9f000000-0000-4000-8000-000000000000', 'c0000000-0000-4000-8000-000000000000'],
  },
  {
    caso: 'mesmo instante escrito em outro fuso (texto do Postgres com espaço e -03): empata e decide o id',
    linhas: [
      { id: U(9), created_at: '2026-11-16 15:01:02.5-03', nome: 'Depois pelo id' },
      { id: U(8), created_at: '2026-11-16T18:01:02.5+00:00', nome: 'Antes pelo id' },
    ],
    ordem: [U(8), U(9)],
  },
  {
    caso: 'linha de cobrança conta no número (regra 4A): o serviço depois do deslocamento é o 3',
    linhas: [
      { id: U(3), created_at: '2026-11-16T18:01:03+00:00', nome: 'Troca do inversor' },
      { id: U(2), created_at: '2026-11-16T18:01:02+00:00', nome: 'Deslocamento' },
      { id: U(1), created_at: '2026-11-16T18:01:01+00:00', nome: 'Instalação do conversor DC-DC' },
    ],
    ordem: [U(1), U(2), U(3)],
  },
];

/** A OS fictícia do achador (a reprodução do defeito, m3 §1.2), já na ordem da via. */
export const LINHAS_DO_ACHADOR = [
  { id: 'l1', numero: 1, nome: 'Instalação de bateria LiFePO4 200 Ah' },
  { id: 'l2', numero: 2, nome: 'Serviço de revisão do gerador' },
  { id: 'l3', numero: 3, nome: 'Troca do inversor 3000 W' },
  { id: 'l4', numero: 4, nome: 'Fita LED externa' },
  { id: 'l5', numero: 5, nome: 'Deslocamento' },
];

/** O que foi dito → o número da linha (ou o motivo da pergunta). */
export const CASOS_DO_ACHADOR: Array<[dito: string, esperado: number | 'fora_da_faixa' | 'ambiguo' | 'nao_achei']> = [
  ['4', 4],
  ['serviço 4', 4],
  ['servico 4', 4],
  ['o 4', 4],
  ['nº 4', 4],
  ['n° 4', 4],
  ['no 4', 4],
  ['4º', 4],
  ['#4', 4],
  ['item 4', 4],
  ['linha 4', 4],
  ['serviço número 4', 4],
  ['3', 3],
  ['200', 'fora_da_faixa'],
  ['0', 'fora_da_faixa'],
  ['LiFePO4', 1],
  ['bateria', 1],
  ['gerador', 2],
  ['inversor', 3],
  ['LED', 4],
  ['deslocamento', 5],
  ['serviço de revisão do gerador', 2],
  ['revis', 2],
  ['pintura', 'nao_achei'],
  ['do', 'nao_achei'],
  ['', 'nao_achei'],
];

/** numeroDito: o texto inteiro é número? */
export const CASOS_DO_NUMERO_DITO: Array<[texto: string, numero: number | null]> = [
  ['4', 4],
  [' 4 ', 4],
  ['o 4', 4],
  ['a 4', 4],
  ['serviço 4', 4],
  ['Serviço 4?', 4],
  ['serv. 4', 4],
  ['serviço número 4', 4],
  ['serviço nº 4', 4],
  ['nº 4', 4],
  ['n° 4', 4],
  ['no 4', 4],
  ['número 4', 4],
  ['4º', 4],
  ['#4', 4],
  ['item 12', 12],
  ['linha 4', 4],
  ['LiFePO4', null],
  ['bateria 200 Ah', null],
  ['220V', null],
  ['4 baterias', null],
  ['serviço do inversor', null],
  ['', null],
];
