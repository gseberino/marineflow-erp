import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Loader2, Save, RefreshCw } from "lucide-react";
import { toast } from "@/hooks/use-toast";
import { PageHeader } from "@/components/PageHeader";

type TableKey = "clients" | "vessels" | "whatsapp_leads" | "service_orders";

const TABLES: Record<TableKey, { label: string; fields: string[]; labelField: string }> = {
  clients: {
    label: "Clientes",
    labelField: "full_name_or_company_name",
    fields: ["full_name_or_company_name", "address_line_1", "address_line_2", "city", "state", "notes"],
  },
  vessels: {
    label: "Embarcações",
    labelField: "boat_name",
    fields: ["boat_name", "manufacturer", "model", "current_marina_name_snapshot"],
  },
  whatsapp_leads: {
    label: "Leads WhatsApp",
    labelField: "display_name",
    fields: ["display_name"],
  },
  service_orders: {
    label: "Ordens de Serviço",
    labelField: "service_order_number",
    fields: [
      "problem_description",
      "diagnosis",
      "solution_applied",
      "customer_visible_report",
      "extra_notes",
      "payment_conditions",
    ],
  },
};

const BAD_RE = /[?\uFFFD]/;

function hasBad(v: any) {
  return typeof v === "string" && BAD_RE.test(v);
}

function TableEditor({ table }: { table: TableKey }) {
  const cfg = TABLES[table];
  const [rows, setRows] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);
  const [edits, setEdits] = useState<Record<string, Record<string, string>>>({});
  const [saving, setSaving] = useState<string | null>(null);

  const load = async () => {
    setLoading(true);
    const selectCols = ["id", cfg.labelField, ...cfg.fields].filter((v, i, a) => a.indexOf(v) === i).join(",");
    const orParts = cfg.fields
      .flatMap((f) => [`${f}.ilike.%?%`, `${f}.ilike.%\uFFFD%`])
      .join(",");
    const { data, error } = await supabase.from(table).select(selectCols).or(orParts).limit(500);
    if (error) {
      toast({ title: "Erro ao carregar", description: error.message, variant: "destructive" });
    } else {
      // Filter strictly client-side to avoid false positives
      const filtered = (data || []).filter((r: any) => cfg.fields.some((f) => hasBad(r[f])));
      setRows(filtered);
      setEdits({});
    }
    setLoading(false);
  };

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [table]);

  const updateField = (id: string, field: string, value: string) => {
    setEdits((prev) => ({ ...prev, [id]: { ...(prev[id] || {}), [field]: value } }));
  };

  const save = async (row: any) => {
    const patch = edits[row.id];
    if (!patch || Object.keys(patch).length === 0) {
      toast({ title: "Nada para salvar" });
      return;
    }
    setSaving(row.id);
    const { error } = await (supabase.from(table) as any).update(patch).eq("id", row.id);
    setSaving(null);
    if (error) {
      toast({ title: "Erro ao salvar", description: error.message, variant: "destructive" });
      return;
    }
    toast({ title: "Registro corrigido" });
    setRows((prev) => prev.filter((r) => r.id !== row.id));
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <p className="text-sm text-muted-foreground">
          {loading ? "Carregando..." : `${rows.length} registros com caracteres suspeitos (? ou \uFFFD)`}
        </p>
        <Button variant="outline" size="sm" onClick={load} disabled={loading}>
          <RefreshCw className="h-4 w-4 mr-2" />
          Recarregar
        </Button>
      </div>

      {loading && (
        <div className="flex justify-center py-8">
          <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
        </div>
      )}

      {!loading && rows.length === 0 && (
        <Card>
          <CardContent className="py-8 text-center text-muted-foreground">
            Nenhum registro com caracteres suspeitos encontrado.
          </CardContent>
        </Card>
      )}

      {rows.map((row) => (
        <Card key={row.id}>
          <CardHeader>
            <CardTitle className="text-base">
              {row[cfg.labelField] || row.id}
              <span className="ml-2 text-xs text-muted-foreground font-normal">{row.id}</span>
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {cfg.fields.map((f) => {
              const original = row[f];
              if (!hasBad(original)) return null;
              const current = edits[row.id]?.[f] ?? original;
              const stillBad = hasBad(current);
              return (
                <div key={f} className="space-y-1">
                  <div className="flex justify-between text-xs text-muted-foreground">
                    <span className="font-medium">{f}</span>
                    {stillBad && <span className="text-destructive">contém ? ou \uFFFD</span>}
                  </div>
                  <div className="text-xs bg-muted/50 p-2 rounded border">
                    <span className="text-muted-foreground">Original: </span>
                    <span className="font-mono">{original}</span>
                  </div>
                  <Input
                    value={current}
                    onChange={(e) => updateField(row.id, f, e.target.value)}
                    className={stillBad ? "border-destructive" : ""}
                  />
                </div>
              );
            })}
            <div className="flex justify-end">
              <Button onClick={() => save(row)} disabled={saving === row.id}>
                {saving === row.id ? (
                  <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                ) : (
                  <Save className="h-4 w-4 mr-2" />
                )}
                Salvar correções
              </Button>
            </div>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}

export default function EncodingFixerPage() {
  const [tab, setTab] = useState<TableKey>("clients");
  const tabs = useMemo(() => Object.entries(TABLES) as [TableKey, typeof TABLES.clients][], []);

  return (
    <div className="container mx-auto p-4 space-y-4">
      <PageHeader title="Corrigir caracteres inválidos" description="Revise e corrija manualmente registros que contêm ? ou \uFFFD." />
      <Tabs value={tab} onValueChange={(v) => setTab(v as TableKey)}>
        <TabsList className="flex-wrap h-auto">
          {tabs.map(([k, c]) => (
            <TabsTrigger key={k} value={k}>{c.label}</TabsTrigger>
          ))}
        </TabsList>
        {tabs.map(([k]) => (
          <TabsContent key={k} value={k} className="mt-4">
            {tab === k && <TableEditor table={k} />}
          </TabsContent>
        ))}
      </Tabs>
    </div>
  );
}
