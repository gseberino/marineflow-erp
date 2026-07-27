import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Smartphone } from 'lucide-react';
import { toast } from 'sonner';

/**
 * Instalar a Agenda como app próprio na tela inicial.
 * Enquanto esta página está aberta, o manifest da página aponta para
 * /agenda.webmanifest — então o que o navegador instala é "Agenda HBR",
 * abrindo direto em /agenda (e não no ERP inteiro).
 */
export function InstallAgendaButton() {
  const [promptEvent, setPromptEvent] = useState<any>(null);
  const [installed, setInstalled] = useState(false);

  // Troca o manifest enquanto a Agenda estiver montada; restaura ao sair.
  useEffect(() => {
    const link = document.querySelector<HTMLLinkElement>('link[rel="manifest"]');
    if (!link) return;
    const original = link.getAttribute('href');
    link.setAttribute('href', '/agenda.webmanifest');
    return () => { if (original) link.setAttribute('href', original); };
  }, []);

  useEffect(() => {
    const onPrompt = (e: Event) => { e.preventDefault(); setPromptEvent(e); };
    const onInstalled = () => { setInstalled(true); setPromptEvent(null); };
    window.addEventListener('beforeinstallprompt', onPrompt);
    window.addEventListener('appinstalled', onInstalled);
    return () => {
      window.removeEventListener('beforeinstallprompt', onPrompt);
      window.removeEventListener('appinstalled', onInstalled);
    };
  }, []);

  // Já rodando como app instalado, ou navegador sem suporte: não mostra nada
  const standalone = typeof window !== 'undefined'
    && (window.matchMedia?.('(display-mode: standalone)').matches
      || (window.navigator as any).standalone === true);
  if (installed || standalone || !promptEvent) return null;

  return (
    <Button
      size="sm"
      variant="outline"
      title="Instalar a Agenda como app na tela inicial"
      onClick={async () => {
        try {
          promptEvent.prompt();
          const { outcome } = await promptEvent.userChoice;
          if (outcome === 'accepted') {
            toast.success('Agenda instalada', {
              description: 'O ícone abre direto aqui, sem passar pelo ERP.',
            });
          }
          setPromptEvent(null);
        } catch {
          toast.error('Não foi possível instalar por aqui. Use o menu do navegador → Instalar aplicativo.');
        }
      }}
    >
      <Smartphone className="h-4 w-4 mr-1" /> Instalar
    </Button>
  );
}
