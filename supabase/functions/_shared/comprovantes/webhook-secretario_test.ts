// Secretário (Passo 2, 15/10/2026): com a conversa dos comprovantes ligada e a pergunta de um CMP aberta
// no passo "confirmar", um comando do resumo da manhã ("A", "lista", "B feito") vai ao assistente — e não
// vira o "ok" do CMP. Sem a dependência (ou com o formato antigo), o caminho é o de hoje.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type DependenciasDoTexto, rotearTextoDoDono } from "./webhook.ts";
import type { EstadoDoTelefone } from "../whatsapp/pergunta-ativa.ts";
import { lerComandoDoSecretario } from "../secretario/comandos.ts";

const FONE = "5547999990000";

function estado(): EstadoDoTelefone {
  return {
    conversa: true, dono: true,
    ativa: {
      id: "p-1", origem: "comprovante", tipo: "pergunta", referencia_id: "c-1", referencia_codigo: "CMP-00124", passo: "confirmar",
      opcoes: [], wa_message_id: "WA-P", aberta_em: new Date(Date.now() - 60_000).toISOString(),
    },
    citada: null, pendencia: null, cmp_em_contexto: null,
  };
}

function deps(op: { secretario?: "novo" | "antigo" | "erro" | "sem"; transcricao?: string } = {}) {
  const c = { chamar: [] as Array<Record<string, unknown>>, despachos: [] as Array<string | undefined>, perguntou: [] as string[], interrompeu: 0 };
  const d: DependenciasDoTexto = {
    estado: () => Promise.resolve(estado()),
    transcrever: () => Promise.resolve(op.transcricao ?? null),
    chamarComprovantes: (corpo) => {
      c.chamar.push(corpo);
      return Promise.resolve({ status: 200, tratada: true });
    },
    despacharAoAgente: (texto) => {
      c.despachos.push(texto);
      return Promise.resolve();
    },
    avisarFalha: () => Promise.resolve(),
    interromper: () => {
      c.interrompeu++;
      return Promise.resolve();
    },
  };
  if (op.secretario !== "sem") {
    d.comandoDoSecretario = (t) => {
      c.perguntou.push(t);
      if (op.secretario === "erro") return Promise.reject(new Error("rede"));
      return Promise.resolve(lerComandoDoSecretario(t) !== null && (op.secretario ?? "novo") === "novo");
    };
  }
  return { d, c };
}

const TEXTO = (texto: string, tipo = "text") => ({ msgId: "msg-1", phone: FONE, tipo, texto, citado: null });

Deno.test("formato novo: 'A', 'lista' e 'B feito' vão ao assistente com o texto, e o CMP fica interrompido", async () => {
  for (const t of ["A", "lista", "B feito", "por que o C?"]) {
    const { d, c } = deps();
    assertEquals(await rotearTextoDoDono(TEXTO(t), d), "assistente", t);
    assertEquals(c.chamar.length, 0, t);
    assertEquals(c.despachos, [t]);
    assertEquals(c.interrompeu, 1);
  }
});

Deno.test("formato antigo, sem a dependência ou erro ao ler a chave: o caminho de hoje (o CMP responde)", async () => {
  for (const secretario of ["antigo", "sem", "erro"] as const) {
    const { d, c } = deps({ secretario });
    assertEquals(await rotearTextoDoDono(TEXTO("A"), d), "comprovante", secretario);
    assertEquals(c.chamar.length, 1);
    assertEquals(c.despachos.length, 0);
  }
});

Deno.test("o '1', o 'sim' e o 'não' continuam do CMP mesmo com o formato novo", async () => {
  for (const t of ["1", "sim", "não", "2"]) {
    const { d, c } = deps();
    assertEquals(await rotearTextoDoDono(TEXTO(t), d), "comprovante", t);
    assertEquals(c.despachos.length, 0);
  }
});

Deno.test("áudio: a pergunta ao secretário usa a transcrição", async () => {
  const { d, c } = deps({ transcricao: "Lista." });
  assertEquals(await rotearTextoDoDono(TEXTO("[audio]", "audio"), d), "assistente");
  assertEquals(c.perguntou, ["Lista."]);
  assertEquals(c.despachos, ["Lista."]);
});
