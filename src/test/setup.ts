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

// O Radix (Select, DropdownMenu, Popover) usa Pointer Events e scrollIntoView para
// posicionar o painel. O jsdom não implementa nenhum dos dois, e sem estes stubs o menu
// simplesmente não abre no teste — o componente parece quebrado quando o quebrado é o
// ambiente.
if (typeof window !== "undefined") {
  for (const metodo of ["hasPointerCapture", "setPointerCapture", "releasePointerCapture"] as const) {
    if (!(metodo in window.HTMLElement.prototype)) {
      (window.HTMLElement.prototype as unknown as Record<string, unknown>)[metodo] = () => false;
    }
  }
  if (!window.HTMLElement.prototype.scrollIntoView) {
    window.HTMLElement.prototype.scrollIntoView = () => {};
  }
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
