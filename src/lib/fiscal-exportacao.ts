/**
 * Pacote para a contadora: os XMLs das notas de um período + um resumo CSV (livro de saída).
 * As partes puras saíram de FiscalEmission.tsx no D33 (01/10/2026), para ter teste: o CSV vai
 * para fora da empresa, e três números diferentes para a mesma nota é pior que nenhum.
 */
import { dataDaNota, tomadorDaNota, totalDaNota } from './nota-fiscal-leitura';

const diaLocal = (d: Date) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

/**
 * O período com que o diálogo abre: do dia 1º do mês corrente até hoje, no dia LOCAL. (O fim era
 * o dia UTC: depois das 21h o campo abria com amanhã.)
 */
export function periodoInicialDaExportacao(agora: Date = new Date()): { de: string; ate: string } {
  return { de: `${diaLocal(agora).slice(0, 8)}01`, ate: diaLocal(agora) };
}

/**
 * Os limites do período como instantes UTC, a partir do dia LOCAL. authorized_at é timestamptz:
 * comparar a data como texto colocaria as notas da virada do dia no mês errado.
 */
export function limitesDoPeriodo(de: string, ate: string): { inicio: string; fim: string } {
  return {
    inicio: new Date(`${de}T00:00:00`).toISOString(),
    fim: new Date(`${ate}T23:59:59.999`).toISOString(),
  };
}

export const CABECALHO_DO_LIVRO = 'Serie;Numero;Chave de Acesso;Data;Valor Total;Destinatario;CNPJ/CPF;Situacao;Ambiente';

/** Campo livre no CSV com ";" (Excel pt-BR): sem ponto e vírgula nem quebra de linha. */
const csvSeguro = (s: string) => String(s ?? '').replace(/[;\r\n]+/g, ' ').trim();

/**
 * Uma linha do livro de saída. Mesmo valor e mesma data da lista e do DANFE (as funções de
 * nota-fiscal-leitura); o destinatário pelo mesmo tradutor da lista.
 */
export function linhaDoLivroDeSaida(doc: unknown): string {
  const d = doc as { series?: unknown; number?: unknown; access_key?: string | null; status?: string; environment?: string };
  const { nome, documento } = tomadorDaNota(doc);
  const bruta = dataDaNota(doc);
  return [
    d.series, d.number, d.access_key || '',
    bruta ? new Date(bruta).toLocaleDateString('pt-BR') : '',
    totalDaNota(doc).toFixed(2).replace('.', ','),
    csvSeguro(nome), csvSeguro(documento),
    d.status === 'cancelled' ? 'Cancelada' : 'Autorizada',
    d.environment === 'producao' ? 'Producao' : 'Homologacao',
  ].join(';');
}

/** O CSV inteiro: BOM UTF-8 (o Excel abre os acentos certos), cabeçalho e uma linha por nota. */
export function resumoDoLivroDeSaida(docs: readonly unknown[]): string {
  return '﻿' + [CABECALHO_DO_LIVRO, ...docs.map(linhaDoLivroDeSaida)].join('\r\n') + '\r\n';
}

/** Nome do XML dentro do .zip: série, número com 9 dígitos e a chave. */
export function nomeDoXml(doc: { series?: unknown; number?: unknown; access_key?: string | null; id: string }): string {
  return `NFe-${doc.series}-${String(doc.number).padStart(9, '0')}-${doc.access_key || doc.id}.xml`;
}
