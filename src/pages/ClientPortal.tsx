import { Anchor } from 'lucide-react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';

/**
 * O antigo "Portal do Cliente", aposentado em 29/09/2026 (decisão do dono: nenhum cliente
 * acessa o site, todos preferem o PDF).
 *
 * Ele estava quebrado desde maio (a função pedia colunas que não existem mais) e, consertado
 * como estava escrito, abriria dados de clientes: o "login" era digitar 5 dígitos de qualquer
 * telefone ou um CPF, e a resposta trazia as OS com o link público, que abre o cadastro
 * completo. A rota continua existindo só para quem guardou o endereço não cair numa tela
 * quebrada. A função client-portal foi apagada do servidor (03/10/2026) e do repo (06/10).
 */
export default function ClientPortal() {
  return (
    <div className="min-h-screen bg-muted/30 flex items-center justify-center p-4">
      <Card className="w-full max-w-md shadow-lg border-primary/10">
        <CardHeader className="text-center pb-2">
          <div className="mx-auto w-16 h-16 bg-primary/10 rounded-full flex items-center justify-center mb-4 text-primary">
            <Anchor className="h-8 w-8" />
          </div>
          <CardTitle className="text-2xl font-bold">Portal do Cliente</CardTitle>
          <CardDescription className="text-base">Esta página não está mais disponível.</CardDescription>
        </CardHeader>
        <CardContent className="text-center text-sm text-muted-foreground space-y-2 pt-2">
          <p>Orçamentos e ordens de serviço chegam em PDF pelo WhatsApp, junto com o link de cada documento.</p>
          <p>Precisa de uma segunda via? Fale com a HBR pelo WhatsApp.</p>
        </CardContent>
      </Card>
    </div>
  );
}
