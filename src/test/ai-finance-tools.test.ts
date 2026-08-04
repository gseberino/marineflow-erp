// Contrato das ferramentas financeiras do agente.
//
// O que se testa aqui não é a implementação, é a GOVERNANÇA: quem pode chamar, o que
// exige confirmação e o que o modelo lê para decidir. Um erro nesses metadados não quebra
// build nem teste de render — só aparece quando o agente lança dinheiro sozinho, ou
// quando um vendedor recebe silêncio em vez de "sem acesso".
import { describe, it, expect } from 'vitest';
import { financeRulesTools } from '../../supabase/functions/_shared/ai/tools/finance-rules';

const porNome = (n: string) => financeRulesTools.find((t) => t.name === n)!;

describe('governança das ferramentas financeiras do agente', () => {
  it('nenhuma ferramenta fica disponível para técnico ou vendedor', () => {
    // A RLS destas tabelas exige admin/financeiro. Se a ferramenta aparecesse para
    // vendedor, o SELECT voltaria VAZIO (não erro) e o agente diria "não há regras
    // cadastradas" — uma mentira convincente.
    for (const tool of financeRulesTools) {
      expect(tool.roles, `${tool.name} sem restrição de cargo`).toBeDefined();
      expect(tool.roles).toEqual(['admin', 'financial']);
    }
  });

  it('o que CRIA LANÇAMENTO exige confirmação humana', () => {
    // Aprovar proposta vira despesa registrada, mexe em saldo e pode aprovar orçamento.
    expect(porNome('aprovar_propostas_de_lancamento').risk).toBe('high');
  });

  it('o que só ENSINA não é tratado como se movesse dinheiro', () => {
    // Regra não move um centavo e desfazer é pausar. Tratar como alto risco geraria
    // fadiga de aprovação — e fadiga faz o gestor aprovar tudo no automático.
    expect(porNome('criar_regra_financeira').risk).toBe('medium');
    expect(porNome('criar_categoria_de_despesa').risk).toBe('medium');
    expect(porNome('cadastrar_favorecido').risk).toBe('medium');
  });

  it('o que só LÊ não pede confirmação nenhuma', () => {
    for (const n of ['listar_regras_financeiras', 'listar_propostas_de_lancamento',
                     'listar_favorecidos', 'listar_categorias_financeiras', 'resultado_do_periodo']) {
      expect(porNome(n).risk, `${n} deveria ser low`).toBe('low');
    }
  });

  it('recusar proposta é baixo risco — não cria nem apaga nada', () => {
    expect(porNome('recusar_propostas_de_lancamento').risk).toBe('low');
  });

  it('toda ferramenta se explica para o modelo com exemplo de uso', () => {
    // A descrição é a ÚNICA coisa que o modelo lê para escolher a ferramenta. Descrição
    // vaga é ferramenta que nunca é chamada, ou chamada na hora errada.
    for (const tool of financeRulesTools) {
      expect(tool.description.length, `${tool.name} com descrição curta demais`).toBeGreaterThan(60);
      expect(tool.input_schema).toHaveProperty('type', 'object');
    }
  });

  it('criar regra exige o essencial e nada mais', () => {
    const schema = porNome('criar_regra_financeira').input_schema as any;
    expect(schema.required).toEqual(['reconhecer_por', 'valor_de_busca', 'categoria']);
    // Lançar sozinha NÃO pode ser obrigatório: o padrão seguro é esperar o OK.
    expect(schema.required).not.toContain('lancar_sozinha');
  });

  it('aprovar exige a lista de ids — nunca "aprove tudo" implícito', () => {
    const schema = porNome('aprovar_propostas_de_lancamento').input_schema as any;
    expect(schema.required).toEqual(['ids']);
  });

  it('os nomes não colidem entre si', () => {
    const nomes = financeRulesTools.map((t) => t.name);
    expect(new Set(nomes).size).toBe(nomes.length);
  });
});
