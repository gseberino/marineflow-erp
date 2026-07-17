import { describe, it, expect } from "vitest";
import { crc32, createZipBytes, createZipBlob } from "../lib/zip";

const enc = new TextEncoder();

describe("crc32", () => {
  it("bate com o vetor de referência '123456789' = 0xCBF43926", () => {
    expect(crc32(enc.encode("123456789")) >>> 0).toBe(0xcbf43926);
  });

  it("é 0 para entrada vazia", () => {
    expect(crc32(new Uint8Array(0))).toBe(0);
  });

  it("é determinístico e não-negativo (uint32)", () => {
    const a = crc32(enc.encode("<NFe>teste</NFe>"));
    const b = crc32(enc.encode("<NFe>teste</NFe>"));
    expect(a).toBe(b);
    expect(a).toBeGreaterThanOrEqual(0);
  });
});

describe("createZipBytes", () => {
  it("começa com a assinatura de Local File Header PK\\x03\\x04", () => {
    const bytes = createZipBytes([{ name: "a.xml", content: "<x/>" }]);
    expect([bytes[0], bytes[1], bytes[2], bytes[3]]).toEqual([0x50, 0x4b, 0x03, 0x04]);
  });

  it("registra no EOCD a contagem correta de arquivos", () => {
    const bytes = createZipBytes([
      { name: "1.xml", content: "<a/>" },
      { name: "2.xml", content: "<b/>" },
      { name: "resumo.csv", content: "col1;col2\n1;2\n" },
    ]);
    // EOCD são os últimos 22 bytes; contagem total de registros em offset +10.
    const eocd = bytes.subarray(bytes.length - 22);
    const view = new DataView(eocd.buffer, eocd.byteOffset, eocd.byteLength);
    expect(view.getUint32(0, true)).toBe(0x06054b50); // assinatura EOCD
    expect(view.getUint16(10, true)).toBe(3); // total de arquivos
  });

  it("inclui a assinatura do diretório central (0x02014b50)", () => {
    const bytes = createZipBytes([{ name: "nota.xml", content: "<NFe/>" }]);
    // Procura a assinatura little-endian 50 4b 01 02 em algum ponto.
    let found = false;
    for (let i = 0; i + 3 < bytes.length; i++) {
      if (bytes[i] === 0x50 && bytes[i + 1] === 0x4b && bytes[i + 2] === 0x01 && bytes[i + 3] === 0x02) {
        found = true;
        break;
      }
    }
    expect(found).toBe(true);
  });

  it("createZipBlob envolve os mesmos bytes num Blob application/zip", () => {
    const blob = createZipBlob([{ name: "a.xml", content: "<x/>" }]);
    expect(blob.type).toBe("application/zip");
    expect(blob.size).toBe(createZipBytes([{ name: "a.xml", content: "<x/>" }]).length);
  });
});
