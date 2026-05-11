import { analyzeBackupDataset } from './migration-report';

describe('analyzeBackupDataset', () => {
  test('counts records, duplicate ids, duplicate keys and missing foreign keys', () => {
    const report = analyzeBackupDataset(
      {
        clients: [
          { id: 'c1', email: 'a@example.com' },
          { id: 'c1', email: 'a@example.com' },
          { id: 'c2', email: 'b@example.com' },
        ],
        service_orders: [
          { id: 'so1', client_id: 'c2' },
          { id: 'so2', client_id: 'missing' },
        ],
      },
      {
        duplicateKeyRules: {
          clients: ['email'],
        },
        foreignKeys: [
          { table: 'service_orders', column: 'client_id', references: 'clients' },
        ],
      },
    );

    expect(report.tableCounts).toEqual({
      clients: 3,
      service_orders: 2,
    });
    expect(report.duplicateIds).toEqual([
      { table: 'clients', id: 'c1', count: 2 },
    ]);
    expect(report.duplicateKeys).toEqual([
      { table: 'clients', key: 'email', value: 'a@example.com', count: 2 },
    ]);
    expect(report.missingReferences).toEqual([
      {
        table: 'service_orders',
        column: 'client_id',
        value: 'missing',
        referencedTable: 'clients',
      },
    ]);
  });
});
