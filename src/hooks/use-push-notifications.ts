import { useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/use-auth';

const VAPID_PUBLIC_KEY = (import.meta.env.VITE_VAPID_PUBLIC_KEY as string) || '';

function urlBase64ToUint8Array(base64String: string) {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = atob(base64);
  return new Uint8Array([...rawData].map((c) => c.charCodeAt(0)));
}

export function usePushNotifications() {
  const { user } = useAuth();

  useEffect(() => {
    if (!user || !('serviceWorker' in navigator) || !('PushManager' in window)) return;
    if (!VAPID_PUBLIC_KEY) return;

    (async () => {
      try {
        const reg = await navigator.serviceWorker.ready;
        let sub = await reg.pushManager.getSubscription();
        if (!sub) {
          sub = await reg.pushManager.subscribe({
            userVisibleOnly: true,
            applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY),
          });
        }
        const { endpoint, keys } = sub.toJSON() as any;
        await supabase.from('push_subscriptions').upsert(
          {
            user_id: user.id,
            endpoint,
            p256dh: keys.p256dh,
            auth: keys.auth,
            user_agent: navigator.userAgent.slice(0, 200),
          },
          { onConflict: 'endpoint' },
        );
      } catch (e) {
        console.warn('Push subscription failed:', e);
      }
    })();
  }, [user?.id]);
}
