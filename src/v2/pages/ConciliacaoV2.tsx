// [F2-UI] Conciliação — "o que eu registrei bate com o banco?"
//
// ═══ O SENTIDO ESTAVA INVERTIDO ═══
//
// A tela antiga partia do EXTRATO: listava toda linha que o banco trouxe e chamava isso de
// conciliação. O gestor descreveu o problema melhor do que qualquer documento:
//
//   "Conciliação bancária eu faço com tudo aquilo que eu lancei no sistema e vou comparar
//    com o extrato. E não o inverso."
//
// É a divisão que o mercado faz — QuickBooks separa "For Review" de "Reconcile"; NetSuite
// separa "Match Bank Data" de "Reconcile Account Statement". Triagem do extrato é o Extrato.
// Conferir o que foi registrado é esta tela, e ela parte dos LANÇAMENTOS.
//
// ═══ POR QUE O FECHAMENTO MUDOU PARA CÁ ═══
//
// `FechamentoPanel` morava numa aba solta da tela financeira. Fechar o período contra o saldo
// final do banco é o último passo da conciliação, não um assunto à parte — é o equivalente ao
// *Reconcile Account Statement*. Ele não mudou por dentro; mudou de endereço.
//
// ═══ A ABA "SUGERIDAS" NÃO EXISTE AQUI, E ISSO É PROPOSITAL ═══
//
// O desenho previa quatro abas, sendo uma delas os casamentos sugeridos pelo sistema
// aguardando confirmação. Esse motor não existe: hoje há apenas ordenação de candidatos por
// proximidade de valor, dentro do fluxo de "sem par" — o que é outra coisa. Definir o que
// qualifica uma sugestão (tolerância de valor, janela de data, se o casamento fica gravado
// como estado) é decisão de negócio sobre dinheiro, e inventá-la produziria uma aba que
// promete o que o sistema não sabe fazer. Registrado como NOVO-015.
import { useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { V2Shell } from '@/v2/components/V2Shell';
import { PageShell } from '@/v2/components/PageShell';
import { ConciliacaoPanel } from '@/components/ConciliacaoPanel';
import { FechamentoPanel } from '@/components/FechamentoPanel';

const ABAS = ['sem_par', 'casadas', 'fechamento'] as const;
type Aba = (typeof ABAS)[number];

export default function ConciliacaoV2() {
  const [searchParams, setSearchParams] = useSearchParams();

  const bruto = searchParams.get('aba');
  const aba: Aba = (ABAS as readonly string[]).includes(bruto ?? '') ? (bruto as Aba) : 'sem_par';

  const setAba = (v: string) =>
    setSearchParams((prev) => { prev.set('aba', v); return prev; }, { replace: true });

  // O painel renderiza as duas listas; quem manda na aba é a URL, para que um link
  // compartilhado abra onde deveria. Montado uma vez só — remontar a cada troca de aba
  // descartaria busca, filtro de lado e a linha aberta.
  const [abaDoPainel, setAbaDoPainel] = useState<'sem_extrato' | 'conciliados'>('sem_extrato');
  const abaEfetiva = aba === 'casadas' ? 'conciliados' : aba === 'sem_par' ? 'sem_extrato' : abaDoPainel;

  return (
    <V2Shell>
      <PageShell
        breadcrumb={[{ label: 'Financeiro' }, { label: 'Conciliação' }]}
        title="Conciliação"
        description="O que foi registrado no sistema bate com o que o banco mostra."
      >
        <Tabs value={aba} onValueChange={setAba}>
          <TabsList className="flex h-auto w-full flex-wrap justify-start">
            <TabsTrigger value="sem_par">Sem par</TabsTrigger>
            <TabsTrigger value="casadas">Casadas</TabsTrigger>
            <TabsTrigger value="fechamento">Fechamento</TabsTrigger>
          </TabsList>

          <TabsContent value="sem_par" className="mt-4">
            <ConciliacaoPanel aba={abaEfetiva} onAbaChange={setAbaDoPainel} ocultarAbas />
          </TabsContent>

          <TabsContent value="casadas" className="mt-4">
            <ConciliacaoPanel aba={abaEfetiva} onAbaChange={setAbaDoPainel} ocultarAbas />
          </TabsContent>

          <TabsContent value="fechamento" className="mt-4">
            <FechamentoPanel />
          </TabsContent>
        </Tabs>
      </PageShell>
    </V2Shell>
  );
}
