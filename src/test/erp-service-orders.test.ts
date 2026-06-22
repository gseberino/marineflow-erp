import { describe, it, expect } from "vitest";
import {
  createServiceOrder,
  generateServiceOrderNumber,
  type DbClientLike,
} from "../../supabase/functions/_shared/erp/service-orders.ts";

// Mock mínimo do client Supabase, registrando o insert para assertar.
function mockClient(opts: {
  existing?: string[];
  insertError?: string;
}): { client: DbClientLike; captured: { payload?: any } } {
  const captured: { payload?: any } = {};
  const client: DbClientLike = {
    from() {
      return {
        select: async () => ({
          data: (opts.existing ?? []).map((n) => ({ service_order_number: n })),
          error: null,
        }),
        insert: (payload: unknown) => {
          captured.payload = payload;
          return {
            select: () => ({
              single: async () =>
                opts.insertError
                  ? { data: null, error: { message: opts.insertError } }
                  : { data: { id: "so-1", ...(payload as object) }, error: null },
            }),
          };
        },
      };
    },
  };
  return { client, captured };
}

describe("erp/service-orders — numeração", () => {
  it("primeiro número é OS-00001", async () => {
    const { client } = mockClient({ existing: [] });
    expect(await generateServiceOrderNumber(client)).toBe("OS-00001");
  });

  it("incrementa a partir do maior existente", async () => {
    const { client } = mockClient({ existing: ["OS-00007", "OS-00003"] });
    expect(await generateServiceOrderNumber(client)).toBe("OS-00008");
  });
});

describe("erp/service-orders — criação (caminho único)", () => {
  it("cria OS com número gerado e devolve a linha", async () => {
    const { client, captured } = mockClient({ existing: ["OS-00010"] });
    const res = await createServiceOrder(client, {
      client_id: "c1",
      status: "draft",
    });
    expect(res.ok).toBe(true);
    expect(captured.payload.service_order_number).toBe("OS-00011");
    expect(captured.payload.client_id).toBe("c1");
    expect(res.data.id).toBe("so-1");
  });

  it("erro de insert retorna ok:false com mensagem", async () => {
    const { client } = mockClient({ existing: [], insertError: "RLS denied" });
    const res = await createServiceOrder(client, { client_id: "c1" });
    expect(res.ok).toBe(false);
    expect(res.error).toContain("RLS denied");
  });
});
