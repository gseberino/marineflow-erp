// Decisão do dono (14/09/2026, MF-AUD-037): as 19 telas legadas (v1) serão apagadas em
// 15/10/2026 — as que ninguém abrir até lá. Para isso é preciso SABER quem abre o quê: este
// hook registra um acesso por tela e por sessão do navegador quando a tela legada é
// renderizada de fato (`?legacy=1`). Best-effort: nunca atrapalha a tela.
import { useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';

export function useLegacyHit(path: string, ativo: boolean) {
  useEffect(() => {
    if (!ativo) return;
    const chave = `legacy-hit:${path}`;
    try {
      if (sessionStorage.getItem(chave)) return;
      sessionStorage.setItem(chave, '1');
    } catch { /* sessionStorage indisponível: registra mesmo assim */ }
    (supabase as any)
      .from('legacy_screen_hits')
      .insert({ path, user_agent: typeof navigator !== 'undefined' ? navigator.userAgent.slice(0, 200) : null })
      .then(() => {}, () => {});
  }, [path, ativo]);
}
