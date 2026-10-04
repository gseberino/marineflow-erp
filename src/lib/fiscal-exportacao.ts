/**
 * Pacote para a contadora: os XMLs das notas de um período + um resumo CSV (livro de saída).
 * As partes puras saíram de FiscalEmission.tsx no D33 (01/10/2026), para ter teste: o CSV vai
 * para fora da empresa, e três números diferentes para a mesma nota é pior que nenhum.
 *
 * NFS-e no pacote (04/10/2026, decisão do dono): até aqui o pacote levava só NF-e, porque o
 * filtro era a data de autorização e a NFS-e não preenche `authorized_at` (a data dela vem do
 * evento do provedor). As NFS-e do período entram agora com o XML e uma linha no CSV, marcadas
 * na coluna "Modelo".
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

const UM_DIA_MS = 86_400_000;

/**
 * A janela da consulta das NFS-e, pelo `created_at` da linha: um dia de folga de cada lado. A data
 * que vale é a da nota (`dataDaNota`, o evento do provedor), que fica segundos depois da criação
 * da linha; a folga só garante que a nota da virada do dia venha na consulta, e
 * `nfseDoPeriodo` corta pela data certa.
 */
export function janelaDaConsultaDeNfse(inicio: string, fim: string): { inicio: string; fim: string } {
  return {
    inicio: new Date(new Date(inicio).getTime() - UM_DIA_MS).toISOString(),
    fim: new Date(new Date(fim).getTime() + UM_DIA_MS).toISOString(),
  };
}

/** As NFS-e cuja data (a impressa na nota) cai dentro do período. */
export function nfseDoPeriodo<T>(docs: readonly T[], inicio: string, fim: string): T[] {
  const de = new Date(inicio).getTime();
  const ate = new Date(fim).getTime();
  return docs.filter((doc) => {
    const data = dataDaNota(doc);
    if (!data) return false;
    const t = new Date(data).getTime();
    return t >= de && t <= ate;
  });
}

const ehNfse = (doc: unknown) => (doc as { document_type?: string } | null)?.document_type === 'nfse';

/** "NF-e" ou "NFS-e": a primeira coluna do livro, para a contadora separar produto de serviço. */
export function modeloDaNota(doc: unknown): 'NF-e' | 'NFS-e' {
  return ehNfse(doc) ? 'NFS-e' : 'NF-e';
}

export const CABECALHO_DO_LIVRO = 'Modelo;Serie;Numero;Chave de Acesso;Data;Valor Total;Destinatario;CNPJ/CPF;Situacao;Ambiente';

/** Campo livre no CSV com ";" (Excel pt-BR): sem ponto e vírgula nem quebra de linha. */
const csvSeguro = (s: string) => String(s ?? '').replace(/[;\r\n]+/g, ' ').trim();

/**
 * Uma linha do livro de saída. Mesmo valor e mesma data da lista e do DANFE (as funções de
 * nota-fiscal-leitura); o destinatário pelo mesmo tradutor da lista (na NFS-e, o tomador).
 */
export function linhaDoLivroDeSaida(doc: unknown): string {
  const d = doc as { series?: unknown; number?: unknown; access_key?: string | null; status?: string; environment?: string };
  const { nome, documento } = tomadorDaNota(doc);
  const bruta = dataDaNota(doc);
  return [
    modeloDaNota(doc),
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

/** Nome do XML dentro do .zip: modelo, série, número com 9 dígitos e a chave. */
export function nomeDoXml(doc: { document_type?: string | null; series?: unknown; number?: unknown; access_key?: string | null; id: string }): string {
  const modelo = ehNfse(doc) ? 'NFSe' : 'NFe';
  return `${modelo}-${doc.series}-${String(doc.number).padStart(9, '0')}-${doc.access_key || doc.id}.xml`;
}
