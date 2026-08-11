// [F2-UI] Extrato — "o que o banco trouxe e eu ainda não registrei?"
//
// ═══ POR QUE ESTA TELA EXISTE COMO ROTA PRÓPRIA ═══
//
// Até aqui, Extrato e Conciliação eram duas ABAS da mesma tela financeira, e o menu lateral
// apontava para elas com `?tab=`. O gestor descreveu o efeito: não dava para saber se o
// caminho era clicar na lateral ou em cima. Aba é recorte do MESMO material; destino
// diferente é rota. Extrato e Conciliação respondem a perguntas diferentes — viram rotas.
//
// ═══ A FILA É UMA SÓ ═══
//
// Havia duas filas sobre a mesma matéria-prima: a "Caixa de entrada" e a fila da antiga
// Conciliação. A mesma linha do banco aparecia nas duas, com ferramentas diferentes — e a
// melhor delas (agrupamento por favorecido, multi-seleção, MCC, aprovação em lote) só existia
// na Caixa de entrada. Aqui sobra uma fila, com a mecânica boa.
//
// As abas abaixo são recorte legítimo: é o mesmo material (linha de extrato não tratada),
// separado por ONDE a linha nasceu. Banco e cartão se tratam de formas diferentes — uma
// compra de cartão não é uma conta a pagar, a fatura é.
import { useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { V2Shell } from '@/v2/components/V2Shell';
import { PageShell } from '@/v2/components/PageShell';
import { FinanceReviewInbox, type SementeDeRegra } from '@/components/FinanceReviewInbox';
import { CartoesPanel } from '@/components/CartoesPanel';
import { IgnoradasPanel } from '@/components/IgnoradasPanel';
import { EditorDeRegra } from '@/components/FinanceRulesPanel';

/** Abas válidas. Valor fora desta lista cai em `banco` em vez de renderizar vazio. */
const ABAS = ['banco', 'cartao', 'fora'] as const;
type Aba = (typeof ABAS)[number];

export default function ExtratoV2() {
  const [searchParams, setSearchParams] = useSearchParams();

  const bruto = searchParams.get('aba');
  const aba: Aba = (ABAS as readonly string[]).includes(bruto ?? '') ? (bruto as Aba) : 'banco';

  const setAba = (v: string) =>
    setSearchParams((prev) => { prev.set('aba', v); return prev; }, { replace: true });

  // A criação de regra nasce de uma linha do extrato ("toda vez que vier deste favorecido,
  // classifique assim"). O diálogo vive aqui porque a lista que o dispara vive aqui — na
  // organização antiga ele morava na tela financeira inteira, longe de quem o aciona.
  const [sementeRegra, setSementeRegra] = useState<SementeDeRegra | null>(null);

  return (
    <V2Shell>
      <PageShell
        breadcrumb={[{ label: 'Financeiro' }, { label: 'Extrato' }]}
        title="Extrato"
        description="O que o banco trouxe e ainda não virou lançamento. Débitos e créditos."
      >
        <Tabs value={aba} onValueChange={setAba}>
          <TabsList className="flex h-auto w-full flex-wrap justify-start">
            <TabsTrigger value="banco">Conta bancária</TabsTrigger>
            <TabsTrigger value="cartao">Cartão</TabsTrigger>
            <TabsTrigger value="fora">Fora da fila</TabsTrigger>
          </TabsList>

          <TabsContent value="banco" className="mt-4">
            <FinanceReviewInbox onCriarRegra={setSementeRegra} />
          </TabsContent>

          <TabsContent value="cartao" className="mt-4">
            <CartoesPanel />
          </TabsContent>

          {/* Não é lixeira: é o que alguém decidiu que não vira lançamento. Fica visível para
              poder voltar — descarte silencioso é como dinheiro some do DRE. */}
          <TabsContent value="fora" className="mt-4">
            <IgnoradasPanel />
          </TabsContent>
        </Tabs>
      </PageShell>

      {sementeRegra && (
        <EditorDeRegra
          key={sementeRegra.match_value}
          aberto
          onFechar={() => setSementeRegra(null)}
          regra={sementeRegra}
        />
      )}
    </V2Shell>
  );
}
