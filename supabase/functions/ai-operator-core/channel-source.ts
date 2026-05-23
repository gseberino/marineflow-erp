// MarineFlow AI Operator — fonte determinística do canal no core implantável.
//
// Nesta fase, a única Edge Function autenticada do operador é
// `ai-operator-core`. Ela é acionada exclusivamente pelo frontend web
// autenticado do MarineFlow. Por isso, a procedência registrada precisa ser
// 'web' independentemente do que o corpo da requisição declarar.
//
// Quando, em ciclo futuro, formos receber eventos WhatsApp/sistêmicos, eles
// entrarão por endpoints dedicados (`ai-operator-channel-intake` ou bridges
// que se autentiquem por canal próprio), e a procedência será fixada lá.

export type EnforcedChannel = "web";

export type ChannelResolution = {
  enforced: EnforcedChannel;
  declared: string | null;
  spoofAttempt: boolean;
};

export function resolveCoreChannel(declared: unknown): ChannelResolution {
  const declaredStr =
    typeof declared === "string" && declared.length > 0 ? declared : null;
  return {
    enforced: "web",
    declared: declaredStr,
    spoofAttempt: declaredStr !== null && declaredStr !== "web",
  };
}
