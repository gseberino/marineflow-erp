// Renderização por audiência (parte do módulo C). O MESMO item, dito diferente:
// - fornecedor / dono / técnico: técnico (nome + SKU/modelo — precisa da precisão).
// - cliente: linguagem simples / benefício ("o controlador solar do seu sistema").
// Do assento do cliente: "MPPT 100/50" não significa nada; pode até confundir.

import type { Audiencia } from "./voice-profiles.ts";

// Termos técnicos → tradução simples para o cliente.
const SIMPLES: Array<{ re: RegExp; plain: string }> = [
  { re: /multiplus|inversor\s*\/?\s*carregador/i, plain: "inversor/carregador" },
  { re: /\bmppt\b|smartsolar|controlador solar/i, plain: "controlador solar" },
  { re: /smartshunt|monitor de bateria|\bbmv\b/i, plain: "monitor de bateria" },
  { re: /\borion\b|dc\s*\/?\s*dc|dc-dc/i, plain: "carregador de bateria (DC-DC)" },
  { re: /lifepo4|l[ií]tio/i, plain: "bateria de lítio" },
  { re: /fus[ií]vel|porta.?fus[ií]vel|\bmidi\b/i, plain: "proteção elétrica" },
  { re: /cerbo|central de monitoramento/i, plain: "central de monitoramento" },
  { re: /estabilizador|kebo|citex/i, plain: "estabilizador de tensão" },
];

export function renderizarItem(item: { nome?: string; sku?: string | null }, audiencia: Audiencia): string {
  const nome = String(item?.nome || "").trim();
  if (!nome) return "";
  // Técnico é o correto para quem trabalha com a peça.
  if (audiencia !== "cliente") {
    return item?.sku ? `${nome} (${item.sku})` : nome;
  }
  // Cliente: mapeia para termo simples; senão, remove número de modelo (ex.: 100/50).
  for (const s of SIMPLES) if (s.re.test(nome)) return s.plain;
  const semModelo = nome.replace(/\s*\b\d{2,4}\/\d{2,4}\b/g, "").replace(/\s{2,}/g, " ").trim();
  return semModelo || nome;
}
