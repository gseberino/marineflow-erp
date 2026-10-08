import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { limiteDoPedido, paraGuardar, precisaRenovar } from "./feed.ts";

const agora = new Date("2026-10-08T12:00:00Z");
const dias = (n: number) => new Date(agora.getTime() + n * 24 * 60 * 60 * 1000);

Deno.test("token recém-colado (sem renovação registrada) → tenta renovar", () => {
  assertEquals(precisaRenovar(null, null, agora), true);
});

Deno.test("renovado há 2 dias e vence em 58 → não renova", () => {
  assertEquals(precisaRenovar(dias(58), dias(-2), agora), false);
});

Deno.test("renovado há 7 dias → renova", () => {
  assertEquals(precisaRenovar(dias(53), dias(-7), agora), true);
});

Deno.test("vence em menos de 15 dias → renova, mesmo com renovação recente", () => {
  assertEquals(precisaRenovar(dias(10), dias(-1), agora), true);
});

Deno.test("imagem e carrossel usam media_url; vídeo usa a capa", () => {
  assertEquals(paraGuardar({ id: "1", media_type: "IMAGE", media_url: "https://x/i.jpg", permalink: "https://ig/p/1" })?.imagem, "https://x/i.jpg");
  assertEquals(paraGuardar({ id: "2", media_type: "CAROUSEL_ALBUM", media_url: "https://x/c.jpg", permalink: "https://ig/p/2" })?.imagem, "https://x/c.jpg");
  assertEquals(paraGuardar({ id: "3", media_type: "VIDEO", media_url: "https://x/v.mp4", thumbnail_url: "https://x/t.jpg", permalink: "https://ig/p/3" })?.imagem, "https://x/t.jpg");
});

Deno.test("post sem imagem ou sem link é descartado; legenda vazia vira null", () => {
  assertEquals(paraGuardar({ id: "4", media_type: "VIDEO", media_url: "https://x/v.mp4", permalink: "https://ig/p/4" }), null);
  assertEquals(paraGuardar({ id: "5", media_url: "https://x/i.jpg" }), null);
  assertEquals(paraGuardar({ id: "6", media_url: "https://x/i.jpg", permalink: "https://ig/p/6", caption: "   " })?.legenda, null);
});

Deno.test("limite do pedido: padrão 9, teto 12, lixo vira 9", () => {
  assertEquals(limiteDoPedido(null), 9);
  assertEquals(limiteDoPedido("6"), 6);
  assertEquals(limiteDoPedido("50"), 12);
  assertEquals(limiteDoPedido("abc"), 9);
  assertEquals(limiteDoPedido("0"), 9);
});
