import { downloadCSV } from './download';

export function exportToCSV(
  data: Record<string, any>[],
  filename: string,
  columns: { key: string; label: string; format?: (v: any) => string }[]
): void {
  const header = columns.map((c) => `"${c.label}"`).join(';');
  const rows = data.map((row) =>
    columns
      .map((c) => {
        const val = c.format ? c.format(row[c.key]) : row[c.key] ?? '';
        return `"${String(val).replace(/"/g, '""')}"`;
      })
      .join(';')
  );
  const csv = '\uFEFF' + [header, ...rows].join('\n');
  downloadCSV(csv, `${filename}_${new Date().toISOString().slice(0, 10)}.csv`);
}
