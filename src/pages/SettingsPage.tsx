import { PageHeader } from '@/components/PageHeader';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { MapPin, DollarSign, Users } from 'lucide-react';

export default function SettingsPage() {
  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader title="Settings" description="Company configuration and system preferences" />

      <Tabs defaultValue="company">
        <TabsList><TabsTrigger value="company">Company</TabsTrigger><TabsTrigger value="travel">Travel Costs</TabsTrigger><TabsTrigger value="users">Users</TabsTrigger></TabsList>

        <TabsContent value="company" className="mt-4 space-y-4">
          <div className="rounded-xl border bg-card p-6 shadow-sm max-w-2xl">
            <h3 className="text-sm font-semibold mb-4 flex items-center gap-2"><MapPin className="h-4 w-4" /> Company Information</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div><label className="text-xs font-medium text-muted-foreground">Company Name</label><Input defaultValue="NautiTech Marine Services" className="mt-1" /></div>
              <div><label className="text-xs font-medium text-muted-foreground">CNPJ</label><Input defaultValue="11.222.333/0001-44" className="mt-1" /></div>
              <div className="md:col-span-2"><label className="text-xs font-medium text-muted-foreground">Base Address</label><Input defaultValue="Av. Brasil, 500 - Centro, Rio de Janeiro, RJ" className="mt-1" /></div>
              <div><label className="text-xs font-medium text-muted-foreground">Latitude</label><Input defaultValue="-22.9068" className="mt-1" /></div>
              <div><label className="text-xs font-medium text-muted-foreground">Longitude</label><Input defaultValue="-43.1729" className="mt-1" /></div>
              <div><label className="text-xs font-medium text-muted-foreground">Phone</label><Input defaultValue="+55 21 3000-0000" className="mt-1" /></div>
              <div><label className="text-xs font-medium text-muted-foreground">Email</label><Input defaultValue="contact@nautitech.com" className="mt-1" /></div>
            </div>
            <Button className="mt-6 bg-accent text-accent-foreground hover:bg-accent/90">Save Changes</Button>
          </div>
        </TabsContent>

        <TabsContent value="travel" className="mt-4 space-y-4">
          <div className="rounded-xl border bg-card p-6 shadow-sm max-w-2xl">
            <h3 className="text-sm font-semibold mb-4 flex items-center gap-2"><DollarSign className="h-4 w-4" /> Travel / Displacement Settings</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div><label className="text-xs font-medium text-muted-foreground">Default Cost per KM (USD)</label><Input type="number" defaultValue="3.50" className="mt-1" /></div>
              <div><label className="text-xs font-medium text-muted-foreground">Default Hourly Rate (USD)</label><Input type="number" defaultValue="150" className="mt-1" /></div>
            </div>
            <div className="mt-4 space-y-3">
              <label className="flex items-center gap-2 text-sm">
                <input type="checkbox" defaultChecked className="rounded border-input" />
                Multiply travel cost by number of technicians
              </label>
              <label className="flex items-center gap-2 text-sm">
                <input type="checkbox" className="rounded border-input" />
                Calculate round trip (×2) by default
              </label>
              <label className="flex items-center gap-2 text-sm">
                <input type="checkbox" defaultChecked className="rounded border-input" />
                Allow manual travel cost override on service orders
              </label>
            </div>
            <Button className="mt-6 bg-accent text-accent-foreground hover:bg-accent/90">Save Settings</Button>
          </div>
        </TabsContent>

        <TabsContent value="users" className="mt-4 space-y-4">
          <div className="rounded-xl border bg-card p-6 shadow-sm">
            <h3 className="text-sm font-semibold mb-4 flex items-center gap-2"><Users className="h-4 w-4" /> Team Members</h3>
            <p className="text-sm text-muted-foreground mb-4">User management requires Lovable Cloud integration for authentication and role-based access control.</p>
            <div className="space-y-3">
              {[
                { name: 'Carlos Mendes', role: 'Admin', email: 'carlos@nautitech.com' },
                { name: 'Ricardo Silva', role: 'Technician', email: 'ricardo@nautitech.com' },
                { name: 'André Costa', role: 'Technician', email: 'andre@nautitech.com' },
                { name: 'Fernanda Lima', role: 'Financial', email: 'fernanda@nautitech.com' },
              ].map(u => (
                <div key={u.email} className="flex items-center justify-between p-3 rounded-lg bg-muted/50 border">
                  <div>
                    <p className="text-sm font-medium">{u.name}</p>
                    <p className="text-xs text-muted-foreground">{u.email}</p>
                  </div>
                  <span className="text-xs font-medium px-2 py-1 rounded bg-primary/10 text-primary">{u.role}</span>
                </div>
              ))}
            </div>
          </div>
        </TabsContent>
      </Tabs>
    </div>
  );
}
