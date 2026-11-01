import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  decidirSaidaAutomatica,
  ehAutomatica,
  ehDaEquipe,
  horaDeBrasilia,
  manterReservaNaFalha,
  reservaImpedeEnvio,
} from "./saida-automatica.ts";

Deno.test("automático é só a chamada de sistema com origem sistema", () => {
  assert(ehAutomatica("sistema", true));
  assert(!ehAutomatica("assistente", true));
  assert(!ehAutomatica("tela", true));
  // Com o JWT de um usuário a origem nunca é "sistema" (origemDoEnvio), mas a regra não depende disso.
  assert(!ehAutomatica("sistema", false));
});

Deno.test("equipe: compara pela chave do telefone, com e sem 55", () => {
  assert(ehDaEquipe("5547999990001", ["47999990001"]));
  assert(!ehDaEquipe("5547999990002", ["47999990001", null, undefined]));
});

Deno.test("hora de Brasília: a hora certa, e null quando não dá para saber", () => {
  assertEquals(horaDeBrasilia(new Date("2026-11-05T11:00:00Z")), 8);
  assertEquals(horaDeBrasilia(new Date("2026-11-05T02:59:00Z")), 23);
  assertEquals(horaDeBrasilia(new Date("2026-11-05T03:00:00Z")), 0);
  assertEquals(horaDeBrasilia(new Date("data inválida")), null);
});

Deno.test("portão: a equipe passa sempre, mesmo com checagem falhando", () => {
  assertEquals(decidirSaidaAutomatica({ daEquipe: true, bloqueio: "erro", hora: null }), { pode: true });
});

Deno.test("portão: checagem que falhou recusa (falha fechada)", () => {
  const d = decidirSaidaAutomatica({ daEquipe: false, bloqueio: "erro", hora: 10 });
  assert(!d.pode && d.codigo === "checagem_indisponivel");
  // Sem saber se é da equipe, segue como de fora.
  const e = decidirSaidaAutomatica({ daEquipe: "erro", bloqueio: "erro", hora: 10 });
  assert(!e.pode && e.codigo === "checagem_indisponivel");
});

Deno.test("portão: cada motivo de canal_bloqueado recusa, com o texto dele", () => {
  for (const motivo of ["cliente_final", "bloqueado", "opt_out"]) {
    const d = decidirSaidaAutomatica({ daEquipe: false, bloqueio: motivo, hora: 10 });
    assert(!d.pode && d.codigo === motivo && d.mensagem.startsWith("Envio automático recusado: "), motivo);
  }
  const final = decidirSaidaAutomatica({ daEquipe: false, bloqueio: "cliente_final", hora: 10 });
  assert(!final.pode && final.mensagem.includes('"Cliente Final"'));
  // Motivo novo que o banco venha a devolver também recusa.
  const novo = decidirSaidaAutomatica({ daEquipe: false, bloqueio: "outro_motivo", hora: 10 });
  assert(!novo.pode && novo.codigo === "outro_motivo");
});

Deno.test("portão: hora desconhecida recusa; fora de 8h–20h recusa; dentro passa", () => {
  const sem = decidirSaidaAutomatica({ daEquipe: false, bloqueio: null, hora: null });
  assert(!sem.pode && sem.codigo === "hora_indisponivel");
  for (const h of [0, 7, 20, 23]) {
    const d = decidirSaidaAutomatica({ daEquipe: false, bloqueio: null, hora: h });
    assert(!d.pode && d.codigo === "fora_de_horario", `${h}h`);
  }
  for (const h of [8, 12, 19]) {
    assertEquals(decidirSaidaAutomatica({ daEquipe: false, bloqueio: null, hora: h }), { pode: true }, `${h}h`);
  }
});

Deno.test("reserva: banco sem resposta impede só o automático a quem é de fora", () => {
  assert(reservaImpedeEnvio("erro", true));
  assert(!reservaImpedeEnvio("erro", false));
  assert(!reservaImpedeEnvio("nova", true));
});

Deno.test("falha incerta mantém a reserva só no automático a quem é de fora", () => {
  assert(manterReservaNaFalha(true, true));
  assert(!manterReservaNaFalha(false, true));
  assert(!manterReservaNaFalha(undefined, true));
  assert(!manterReservaNaFalha(true, false));
});
