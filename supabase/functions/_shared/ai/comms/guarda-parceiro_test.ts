// Retorno F4 (P4.3): a audiência "parceiro" no perfil de voz e a trava dura valor_a_parceiro da guarda de conformidade.
//
// O que estes testes protegem:
//  · valor ao parceiro (no texto ou no documento) só passa com o papel contratante ou pagador; indicou, nulo ou papel
//    ausente travam (falha fecha);
//  · o horário de envio (8h–20h) vale para o parceiro, como para cliente e fornecedor;
//  · o perfil de voz do parceiro: saudação pelo nome, até 18 linhas, nunca preço, jargão nem ameaça.
//
// Reverter: apagar este arquivo junto com as mudanças da F4 em compliance-guard.ts e voice-profiles.ts.

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { checarConformidade, ehDeFora } from "./compliance-guard.ts";
import { perfilDeVoz } from "./voice-profiles.ts";

const BASE = { tipo: "os_link", audiencia: "parceiro", canal: "whatsapp", horaBrasilia: 10 } as const;

Deno.test("valor_a_parceiro: texto com valor trava com indicou, nulo e papel ausente", () => {
  for (const texto of ["O total ficou R$ 1.200", "Pode pagar pelo Pix", "O valor de 350 está no orçamento", "Valores e 1200 no total"]) {
    assertEquals(checarConformidade({ ...BASE, texto, papelDoParceiro: "indicou" })?.codigo, "valor_a_parceiro", texto);
    assertEquals(checarConformidade({ ...BASE, texto, papelDoParceiro: null })?.codigo, "valor_a_parceiro", texto);
    assertEquals(checarConformidade({ ...BASE, texto })?.codigo, "valor_a_parceiro", texto);
  }
});

Deno.test("valor_a_parceiro: documento com valor trava sem papel de contratante ou pagador", () => {
  const texto = "Segue o orçamento do motorhome de João, válido até 15/01.";
  assertEquals(checarConformidade({ ...BASE, texto, documentoComValor: true, papelDoParceiro: "indicou" })?.codigo, "valor_a_parceiro");
  assertEquals(checarConformidade({ ...BASE, texto, documentoComValor: true, papelDoParceiro: null })?.codigo, "valor_a_parceiro");
  assertEquals(checarConformidade({ ...BASE, texto, documentoComValor: true })?.codigo, "valor_a_parceiro");
});

Deno.test("valor_a_parceiro: passa com contratante e com pagador, no texto e no documento", () => {
  for (const papelDoParceiro of ["contratante", "pagador"] as const) {
    assertEquals(checarConformidade({ ...BASE, texto: "O total ficou R$ 1.200", papelDoParceiro }), null, papelDoParceiro);
    assertEquals(
      checarConformidade({ ...BASE, texto: "Segue o orçamento.", documentoComValor: true, papelDoParceiro }),
      null,
      papelDoParceiro,
    );
  }
});

Deno.test("parceiro sem valor nenhum passa, com qualquer papel; 'Valores e dados ficam com cada cliente' não é valor", () => {
  for (const papelDoParceiro of ["indicou", null, undefined] as const) {
    assertEquals(
      checarConformidade({ ...BASE, texto: "Pátio HBR: nenhum veículo dos clientes de vocês por aqui agora.", papelDoParceiro }),
      null,
    );
    assertEquals(checarConformidade({ ...BASE, texto: "Valores e dados ficam com cada cliente.", papelDoParceiro }), null);
  }
});

Deno.test("fora_de_horario vale para o parceiro (é de fora), e a hora vem antes do valor", () => {
  assertEquals(ehDeFora({ canal: "whatsapp", audiencia: "parceiro" }), true);
  assertEquals(ehDeFora({ canal: "panel", audiencia: "parceiro" }), false);
  assertEquals(checarConformidade({ ...BASE, horaBrasilia: 22, texto: "Pátio HBR" })?.codigo, "fora_de_horario");
  assertEquals(checarConformidade({ ...BASE, horaBrasilia: 7, texto: "R$ 10", papelDoParceiro: "indicou" })?.codigo, "fora_de_horario");
  assertEquals(checarConformidade({ ...BASE, horaBrasilia: 8, texto: "Pátio HBR" }), null);
});

Deno.test("as outras audiências não mudam: cliente com valor passa; técnico com preço segue travado", () => {
  assertEquals(checarConformidade({ tipo: "os_link", audiencia: "cliente", canal: "whatsapp", horaBrasilia: 10, texto: "Total R$ 1.200" }), null);
  assertEquals(
    checarConformidade({ tipo: "generico", audiencia: "tecnico", canal: "whatsapp", horaBrasilia: 10, texto: "Total R$ 1.200" })?.codigo,
    "preco_a_tecnico",
  );
});

Deno.test("perfilDeVoz('parceiro'): pelo nome, até 18 linhas, nunca preço, jargão nem ameaça", () => {
  const p = perfilDeVoz("parceiro");
  assertEquals(p.audiencia, "parceiro");
  assertEquals(p.canal, "whatsapp");
  assertEquals(p.saudacao, "nome");
  assertEquals(p.tetoLinhas, 18);
  assertEquals(p.proibicoes, ["preco", "jargao_tecnico", "ameaca"]);
  assertEquals(p.registro, "Cordial e objetivo, falando do cliente em terceira pessoa. Nunca valor nem dado pessoal.");
  assertEquals(perfilDeVoz("parceiro", "panel").tetoLinhas, 0);
});
