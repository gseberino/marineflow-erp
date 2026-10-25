/**
 * A janela do motivo (Agenda de Produção, revisão da Fase 3, R2 — 25/10/2026).
 *
 * A OS que já começou só volta a aguardar (peças ou o cliente) quando quem pede diz por quê: a porta do banco recusa sem o
 * motivo (_os_porta_regra). A lista rápida pergunta ANTES de chamar a porta (os_status_da_tela diz quais passagens pedem o
 * motivo); o formulário pergunta quando a porta responde que só faltou ele (PortaPedeMotivo). O que a pessoa escolhe e
 * escreve vai à porta como "falta material: o inversor não chegou" ou "esperando o cliente" e fica no registro da OS.
 *
 * Rótulo acima de cada campo (pedido do dono, 21/10/2026: o componente Campo). Nada aqui decide quem pode: a lista de
 * opções vem do banco; sem ela, só o status que a pessoa escolheu.
 */
import { useEffect, useId, useState } from 'react';
import { Loader2 } from 'lucide-react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { Textarea } from '@/components/ui/textarea';
import { Campo } from '@/components/Campo';
import { motivoDaParada } from '@/lib/status-pela-tela';

const POR_QUE: Record<string, string> = {
  awaiting_parts: 'Falta material',
  awaiting_client: 'Esperando o cliente',
};

/** O tamanho do que a pessoa escreve (a porta guarda o motivo inteiro até 200 caracteres). */
const TAMANHO_DO_TEXTO = 160;

interface Props {
  /** o status que a pessoa escolheu (awaiting_parts ou awaiting_client); null = fechada */
  para: string | null;
  /** as passagens desta OS que pedem o motivo (os_status_da_tela); vazio = só a escolhida */
  opcoes?: readonly string[];
  /** a porta está respondendo */
  ocupado?: boolean;
  onFechar: () => void;
  /** o status escolhido (pode trocar de peças para o cliente) e o motivo pronto para a porta */
  onConfirmar: (para: string, motivo: string) => void | Promise<void>;
}

export function JanelaDoMotivo({ para, opcoes, ocupado = false, onFechar, onConfirmar }: Props) {
  const id = useId();
  const [escolha, setEscolha] = useState<string>(para ?? '');
  const [texto, setTexto] = useState('');
  useEffect(() => {
    if (para) {
      setEscolha(para);
      setTexto('');
    }
  }, [para]);

  const lista = (opcoes && opcoes.length > 0 ? [...opcoes] : para ? [para] : []).filter((s) => s in POR_QUE);
  const podeConfirmar = !ocupado && lista.includes(escolha);

  return (
    <Dialog open={!!para} onOpenChange={(aberta) => { if (!aberta && !ocupado) onFechar(); }}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>Parar a OS</DialogTitle>
          <DialogDescription>
            A OS já começou. Para ela voltar a aguardar, diga por que parou: fica registrado na OS.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <Campo rotulo="Por que parou?">
            {lista.length > 1 ? (
              <RadioGroup value={escolha} onValueChange={setEscolha} className="flex flex-col gap-2" aria-label="Por que parou?">
                {lista.map((s) => (
                  <div key={s} className="flex items-center gap-2">
                    <RadioGroupItem value={s} id={`${id}-${s}`} disabled={ocupado} />
                    <Label htmlFor={`${id}-${s}`} className="cursor-pointer font-normal">{POR_QUE[s]}</Label>
                  </div>
                ))}
              </RadioGroup>
            ) : (
              <p className="text-sm">{lista[0] ? POR_QUE[lista[0]] : '—'}</p>
            )}
          </Campo>
          <Campo rotulo="O que aconteceu (se quiser)" htmlFor={`${id}-texto`}>
            <Textarea
              id={`${id}-texto`}
              value={texto}
              onChange={(e) => setTexto(e.target.value)}
              maxLength={TAMANHO_DO_TEXTO}
              rows={3}
              placeholder="Ex.: o inversor não chegou"
              className="resize-none"
              disabled={ocupado}
            />
          </Campo>
        </div>
        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={onFechar} disabled={ocupado}>Voltar</Button>
          <Button onClick={() => { void onConfirmar(escolha, motivoDaParada(escolha, texto)); }} disabled={!podeConfirmar}>
            {ocupado && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            Parar a OS
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
