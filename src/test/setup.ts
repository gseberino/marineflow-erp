import "@testing-library/jest-dom";

// O jsdom não implementa ResizeObserver, e o ResponsiveContainer do recharts o usa para
// medir o espaço disponível. Sem este stub, qualquer teste de render de tela com gráfico
// morre com "ResizeObserver is not defined" — erro que não diz nada sobre o componente.
if (!("ResizeObserver" in globalThis)) {
  (globalThis as Record<string, unknown>).ResizeObserver = class {
    observe() {}
    unobserve() {}
    disconnect() {}
  };
}

Object.defineProperty(window, "matchMedia", {
  writable: true,
  value: (query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: () => {},
    removeListener: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    dispatchEvent: () => {},
  }),
});
