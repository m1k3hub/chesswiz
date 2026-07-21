// Enable React act() environment for jsdom tests.
// Without this, React emits "The current testing environment is not
// configured to support act(...)" warnings for every component test.
globalThis.IS_REACT_ACT_ENVIRONMENT = true;

// Minimal localStorage stub for Zustand persist middleware under jsdom.
const store: Record<string, string> = {};
Object.defineProperty(window, 'localStorage', {
  value: {
    getItem: (key: string) => store[key] || null,
    setItem: (key: string, value: string) => { store[key] = String(value); },
    removeItem: (key: string) => { delete store[key]; },
    clear: () => { Object.keys(store).forEach((key) => delete store[key]); },
  },
  writable: true,
});
