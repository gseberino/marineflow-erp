import { useEffect, useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Smartphone, Share, PlusSquare, CheckCircle2 } from 'lucide-react';
import { toast } from 'sonner';

/**
 * "Agenda no celular" — o convite para instalar, fora da própria Agenda.
 *
 * Existe porque o botão que havia só aparecia DENTRO da Agenda e só quando o navegador
 * dispara `beforeinstallprompt`. O iPhone nunca dispara esse evento: quem abriu pelo Safari
 * simplesmente nunca viu que dava para instalar. Aqui o caso do iOS é tratado como o que
 * ele é — instrução manual, não um botão que não funciona.
 *
 * Os três estados são excludentes: já instalado / dá para instalar por botão / instruções.
 */
export function InstallAgendaCard() {
  const [promptEvent, setPromptEvent] = useState<any>(null);
  const [installed, setInstalled] = useState(false);

  // Mesmo truque do botão da Agenda: enquanto este cartão está montado, o manifest aponta
  // para o da Agenda, então o que se instala é "Agenda HBR" abrindo em /agenda — e não o
  // ERP inteiro. Restaura ao desmontar para não afetar o resto do sistema.
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

  const ehIOS = typeof navigator !== 'undefined'
    && /iphone|ipad|ipod/i.test(navigator.userAgent);
  const jaInstalado = installed
    || (typeof window !== 'undefined'
      && (window.matchMedia?.('(display-mode: standalone)').matches
        || (window.navigator as any).standalone === true));

  return (
    <Card className="p-5 space-y-3">
      <div className="flex items-center gap-2">
        <Smartphone className="h-5 w-5 text-primary shrink-0" />
        <div className="min-w-0">
          <h3 className="font-semibold text-sm">Agenda no celular</h3>
          <p className="text-xs text-muted-foreground">
            Instalada, ela vira um ícone próprio que abre direto na agenda — sem passar pelo
            ERP, sem login toda vez, e funciona com internet ruim.
          </p>
        </div>
      </div>

      {jaInstalado ? (
        <p className="flex items-center gap-2 text-sm text-emerald-700 dark:text-emerald-400">
          <CheckCircle2 className="h-4 w-4 shrink-0" /> Já está instalada neste aparelho.
        </p>
      ) : promptEvent ? (
        <Button
          size="sm"
          onClick={async () => {
            try {
              promptEvent.prompt();
              const { outcome } = await promptEvent.userChoice;
              if (outcome === 'accepted') {
                toast.success('Agenda instalada', {
                  description: 'O ícone abre direto na agenda.',
                });
              }
              setPromptEvent(null);
            } catch {
              toast.error('Não deu por aqui. Use o menu do navegador → Instalar aplicativo.');
            }
          }}
        >
          <Smartphone className="h-4 w-4 mr-1.5" /> Instalar agora
        </Button>
      ) : ehIOS ? (
        // iPhone/iPad: o Safari não oferece instalação por botão. Só o passo a passo resolve.
        <div className="space-y-2 rounded-md border bg-muted/40 p-3">
          <p className="text-xs font-medium">No iPhone, a instalação é manual — são três toques:</p>
          <ol className="space-y-1.5 text-xs text-muted-foreground">
            <li className="flex items-start gap-2">
              <Share className="h-3.5 w-3.5 mt-0.5 shrink-0" />
              <span><strong>1.</strong> Toque em Compartilhar (o quadrado com a seta para cima, embaixo).</span>
            </li>
            <li className="flex items-start gap-2">
              <PlusSquare className="h-3.5 w-3.5 mt-0.5 shrink-0" />
              <span><strong>2.</strong> Role e escolha “Adicionar à Tela de Início”.</span>
            </li>
            <li className="flex items-start gap-2">
              <CheckCircle2 className="h-3.5 w-3.5 mt-0.5 shrink-0" />
              <span><strong>3.</strong> Confirme em “Adicionar”. O ícone aparece na tela inicial.</span>
            </li>
          </ol>
          <p className="text-[11px] text-muted-foreground">
            Precisa ser pelo Safari — pelo Chrome no iPhone essa opção não aparece.
          </p>
        </div>
      ) : (
        <p className="text-xs text-muted-foreground">
          Este navegador não oferece instalação. Abra o ERP pelo Chrome ou Edge no computador,
          ou pelo Safari no iPhone, e o convite aparece aqui.
        </p>
      )}
    </Card>
  );
}
