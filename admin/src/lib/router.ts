import { useEffect, useState } from 'react';

/**
 * Hash routes (#/pros/123): the backend serves one static index.html under
 * /admin, so deep links must not depend on server-side routing.
 */
export function useRoute(): string[] {
  const read = () => window.location.hash.replace(/^#\/?/, '').split('/').filter(Boolean);
  const [parts, setParts] = useState(read);
  useEffect(() => {
    const on = () => setParts(read());
    window.addEventListener('hashchange', on);
    return () => window.removeEventListener('hashchange', on);
  }, []);
  return parts;
}

export const go = (path: string) => {
  window.location.hash = path.startsWith('/') ? path : `/${path}`;
};
