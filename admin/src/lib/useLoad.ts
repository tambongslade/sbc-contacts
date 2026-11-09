import { useCallback, useEffect, useState } from 'react';

/** Results kept across mounts, keyed by the caller's `cacheKey`. */
const cache = new Map<string, unknown>();

/**
 * Load data, re-run when [deps] change, and expose a manual reload.
 *
 * Pass `cacheKey` to remember the result per key: revisiting a page, search,
 * or tab you have already seen shows the kept copy at once and refreshes it in
 * the background (stale-while-revalidate), so no spinner and no refetch wait on
 * paths already loaded this session.
 */
export function useLoad<T>(load: () => Promise<T>, deps: unknown[], cacheKey?: string) {
  const cached = cacheKey !== undefined ? (cache.get(cacheKey) as T | undefined) : undefined;
  const [data, setData] = useState<T | null>(cached ?? null);
  const [error, setError] = useState<unknown>(null);
  const [loading, setLoading] = useState(cached === undefined);
  const [tick, setTick] = useState(0);

  // eslint-disable-next-line react-hooks/exhaustive-deps
  const run = useCallback(load, deps);
  useEffect(() => {
    let alive = true;
    const hit = cacheKey !== undefined ? (cache.get(cacheKey) as T | undefined) : undefined;
    // Show the kept copy right away; only block with a spinner on a cache miss.
    if (hit !== undefined) {
      setData(hit);
      setError(null);
    }
    setLoading(hit === undefined);
    run()
      .then((d) => {
        if (!alive) return;
        if (cacheKey !== undefined) cache.set(cacheKey, d);
        setData(d);
        setError(null);
      })
      .catch((e) => alive && setError(e))
      .finally(() => alive && setLoading(false));
    return () => {
      alive = false;
    };
  }, [run, tick, cacheKey]);

  return { data, error, loading, reload: () => setTick((t) => t + 1), setData };
}
