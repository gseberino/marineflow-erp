// Retorno rápido, F2 (P9): tira dado pessoal do texto do cliente antes de ele ir ao modelo. Puro.
//
// CPF, CNPJ, telefone, e-mail e placa viram [dado]. A ordem importa: o CNPJ tem mais dígitos que o CPF, e os dois, mais que o
// telefone. O dono lê o caso inteiro em *ver N*; isto é só para o modelo, que não precisa desses dados para organizar o que o
// dono ditou.
//
// Reverter: tirar a chamada de retorno_ler_caso.

const MARCA = "[dado]";

const EMAIL = /[\p{L}\p{N}._%+-]+@[\p{L}\p{N}-]+(?:\.[\p{L}\p{N}-]+)+/gu;
const CNPJ = /\b\d{2}\.?\d{3}\.?\d{3}\/?\d{4}-?\d{2}\b/g;
const CPF = /\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b/g;
const TELEFONE = /(?:\+?55[\s.-]?)?(?:\(?\b\d{2}\)?[\s.-]?)?\b9?\d{4}[\s.-]?\d{4}\b/g;
const PLACA = /\b[A-Z]{3}-?\d[A-Z0-9]\d{2}\b/gi;

export function mascararDadosPessoais(texto: string): string {
  return String(texto ?? "")
    .replace(EMAIL, MARCA)
    .replace(CNPJ, MARCA)
    .replace(CPF, MARCA)
    .replace(TELEFONE, MARCA)
    .replace(PLACA, MARCA);
}
