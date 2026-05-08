import { useState, useCallback, useMemo } from 'react';

// ─── Types ────────────────────────────────────────────────────────────────────

/** Fields whose value is string[] (multi-select) */
type ArrayField<T> = { [K in keyof T]: T[K] extends string[] ? K : never }[keyof T];

/** Generic filter state: mix of string[] (multi-select) and string (text/date) */
export type MultiFilterState = Record<string, string[] | string>;

// ─── Hook ─────────────────────────────────────────────────────────────────────

export function useMultiFilter<T extends MultiFilterState>(initialState: T) {
  const [filters, setFilters] = useState<T>(initialState);

  /** Toggle a value inside a string[] field */
  const toggle = useCallback((field: ArrayField<T>, value: string) => {
    setFilters(prev => {
      const arr = (prev[field] as string[]);
      const next = arr.includes(value)
        ? arr.filter(v => v !== value)
        : [...arr, value];
      return { ...prev, [field]: next };
    });
  }, []);

  /** Set any field directly (string or string[]) */
  const setField = useCallback(<K extends keyof T>(field: K, value: T[K]) => {
    setFilters(prev => ({ ...prev, [field]: value }));
  }, []);

  /** Reset a single field to its initial value */
  const clearField = useCallback((field: keyof T) => {
    setFilters(prev => ({
      ...prev,
      [field]: Array.isArray(initialState[field]) ? [] : '',
    }));
  }, [initialState]);

  /** Reset ALL fields to initial state + reset page  */
  const clearAll = useCallback(() => {
    setFilters(initialState);
  }, [initialState]);

  /** How many filters are currently active */
  const activeCount = useMemo(() => {
    let n = 0;
    for (const key of Object.keys(filters)) {
      const v = filters[key];
      if (Array.isArray(v) ? v.length > 0 : v !== '') n++;
    }
    return n;
  }, [filters]);

  /** Whether a specific value is selected in a string[] field */
  const isActive = useCallback(
    (field: ArrayField<T>, value: string) =>
      (filters[field] as string[]).includes(value),
    [filters],
  );

  /** Replace full state (used by FilterPresets) */
  const applyAll = useCallback((newState: Partial<T>) => {
    setFilters(prev => ({ ...prev, ...newState }));
  }, []);

  return {
    filters,
    toggle,
    setField,
    clearField,
    clearAll,
    applyAll,
    activeCount,
    isActive,
  };
}
