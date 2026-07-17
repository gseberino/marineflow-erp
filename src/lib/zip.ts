// Minimal, dependency-free ZIP writer (STORE method — no compression).
//
// Usado para empacotar os XMLs autorizados de NF-e + um resumo CSV num único
// download para a contadora. Os XMLs fiscais são arquivos de texto pequenos, e o
// método "store" (sem compressão) mantém a implementação exata e auditável —
// sem adicionar dependências ao bundle. Produz um .zip padrão, abrível por
// qualquer ferramenta (Windows Explorer, 7-Zip, software contábil).
//
// Referência do formato: PKWARE APPNOTE (Local File Header 0x04034b50,
// Central Directory 0x02014b50, End Of Central Directory 0x06054b50).

// Tabela CRC-32 (polinômio IEEE 0xEDB88320) — a mesma usada pelo ZIP/PNG.
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    t[n] = c >>> 0;
  }
  return t;
})();

export function crc32(bytes: Uint8Array): number {
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) {
    c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) >>> 0;
}

export interface ZipEntry {
  name: string;
  content: string; // conteúdo textual (UTF-8) — XML ou CSV
}

/**
 * Monta os bytes de um .zip (método store) a partir de entradas de texto. Nomes
 * de arquivo são gravados em UTF-8 (flag bit 11), então acentos funcionam. Datas
 * são fixas (1980-01-01) — irrelevantes para o uso contábil e mantêm a saída
 * determinística. Puro (Uint8Array), sem depender de Blob — testável em Node.
 */
export function createZipBytes(entries: ZipEntry[]): Uint8Array {
  const enc = new TextEncoder();
  const parts: Uint8Array[] = [];
  const central: Uint8Array[] = [];
  let offset = 0;

  const DOS_TIME = 0;
  const DOS_DATE = 0x21; // 1980-01-01

  for (const entry of entries) {
    const nameBytes = enc.encode(entry.name);
    const data = enc.encode(entry.content);
    const crc = crc32(data);
    const size = data.length;

    // Local File Header (30 bytes fixos + nome).
    const lfh = new DataView(new ArrayBuffer(30));
    lfh.setUint32(0, 0x04034b50, true);
    lfh.setUint16(4, 20, true); // versão necessária
    lfh.setUint16(6, 0x0800, true); // flags: bit 11 = nomes UTF-8
    lfh.setUint16(8, 0, true); // método 0 = store
    lfh.setUint16(10, DOS_TIME, true);
    lfh.setUint16(12, DOS_DATE, true);
    lfh.setUint32(14, crc, true);
    lfh.setUint32(18, size, true); // tamanho comprimido (= tamanho, store)
    lfh.setUint32(22, size, true); // tamanho original
    lfh.setUint16(26, nameBytes.length, true);
    lfh.setUint16(28, 0, true); // extra field length
    const lfhBytes = new Uint8Array(lfh.buffer);

    parts.push(lfhBytes, nameBytes, data);
    const localHeaderOffset = offset;
    offset += lfhBytes.length + nameBytes.length + data.length;

    // Central Directory Record (46 bytes fixos + nome).
    const cdr = new DataView(new ArrayBuffer(46));
    cdr.setUint32(0, 0x02014b50, true);
    cdr.setUint16(4, 20, true); // versão que criou
    cdr.setUint16(6, 20, true); // versão necessária
    cdr.setUint16(8, 0x0800, true); // flags UTF-8
    cdr.setUint16(10, 0, true); // método
    cdr.setUint16(12, DOS_TIME, true);
    cdr.setUint16(14, DOS_DATE, true);
    cdr.setUint32(16, crc, true);
    cdr.setUint32(20, size, true);
    cdr.setUint32(24, size, true);
    cdr.setUint16(28, nameBytes.length, true);
    cdr.setUint16(30, 0, true); // extra
    cdr.setUint16(32, 0, true); // comentário
    cdr.setUint16(34, 0, true); // disco
    cdr.setUint16(36, 0, true); // attrs internos
    cdr.setUint32(38, 0, true); // attrs externos
    cdr.setUint32(42, localHeaderOffset, true);
    central.push(new Uint8Array(cdr.buffer), nameBytes);
  }

  const centralStart = offset;
  let centralSize = 0;
  for (const c of central) centralSize += c.length;

  // End Of Central Directory (22 bytes).
  const eocd = new DataView(new ArrayBuffer(22));
  eocd.setUint32(0, 0x06054b50, true);
  eocd.setUint16(4, 0, true); // disco atual
  eocd.setUint16(6, 0, true); // disco do início do central dir
  eocd.setUint16(8, entries.length, true); // registros neste disco
  eocd.setUint16(10, entries.length, true); // total de registros
  eocd.setUint32(12, centralSize, true);
  eocd.setUint32(16, centralStart, true);
  eocd.setUint16(20, 0, true); // comentário

  // Concatena tudo (LFHs+dados, diretório central, EOCD) num só Uint8Array.
  const all = [...parts, ...central, new Uint8Array(eocd.buffer)];
  let total = 0;
  for (const c of all) total += c.length;
  const out = new Uint8Array(total);
  let pos = 0;
  for (const c of all) {
    out.set(c, pos);
    pos += c.length;
  }
  return out;
}

/**
 * Envolve os bytes do zip num Blob application/zip (para download no browser).
 */
export function createZipBlob(entries: ZipEntry[]): Blob {
  return new Blob([createZipBytes(entries)], { type: "application/zip" });
}
