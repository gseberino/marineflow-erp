// Core domain types for the nautical ERP

export type ClientType = 'individual' | 'company';

export interface Client {
  id: string;
  type: ClientType;
  name: string; // Temporarily keeping for compatibility while migrating others
  name: string;
  cpf_cnpj: string;
  phone: string;
  whatsapp: string;
  email: string;
  address_line_1: string;
  address_line_2?: string;
  city: string;
  state: string;
  postal_code: string;
  country: string;
  notes?: string;
  active: boolean;
  created_at: string;
  updated_at: string;
}

export interface Vessel {
  id: string;
  client_id: string;
  marina_id?: string;
  name: string;
  manufacturer: string;
  model: string;
  year: number;
  hull_id_or_registration: string;
  length_feet: number;
  beam_feet?: number;
  draft_feet?: number;
  engine_type: string;
  engine_brand: string;
  engine_model: string;
  engine_quantity: number;
  propulsion_type: string;
  shore_power_type?: string;
  battery_bank_summary?: string;
  inverter_charger_summary?: string;
  navigation_electronics_summary?: string;
  electrical_system_notes?: string;
  current_name_snapshot?: string;
  current_dock_position?: string;
  active: boolean;
  created_at: string;
  updated_at: string;
}

export interface Marina {
  id: string;
  name: string;
  contact_name: string;
  phone: string;
  email: string;
  address_line_1: string;
  city: string;
  state: string;
  postal_code: string;
  country: string;
  latitude?: number;
  longitude?: number;
  access_notes?: string;
  billing_notes?: string;
  active: boolean;
  created_at: string;
  updated_at: string;
}

export interface Product {
  id: string;
  sku: string;
  name: string;
  category: string;
  brand: string;
  supplier_id?: string;
  unit: string;
  cost_price: number;
  sale_price: number;
  stock_quantity: number;
  minimum_stock: number;
  location_bin?: string;
  barcode?: string;
  notes?: string;
  active: boolean;
  created_at: string;
  updated_at: string;
}

export type ServiceOrderStatus = 'draft' | 'scheduled' | 'open' | 'in_progress' | 'awaiting_parts' | 'awaiting_client' | 'approved' | 'completed' | 'invoiced' | 'cancelled';
export type ServiceOrderPriority = 'low' | 'normal' | 'high' | 'urgent';
export type ServiceType = 'diagnosis' | 'repair' | 'installation' | 'preventive_maintenance' | 'consulting' | 'engineering_project' | 'commissioning' | 'inspection';

export interface ServiceOrder {
  id: string;
  service_order_number: string;
  client_id: string;
  vessel_id: string;
  marina_id?: string;
  requested_by_name: string;
  scheduled_start_at?: string;
  scheduled_end_at?: string;
  check_in_at?: string;
  check_out_at?: string;
  status: ServiceOrderStatus;
  priority: ServiceOrderPriority;
  service_type: ServiceType;
  problem_description: string;
  initial_findings?: string;
  diagnosis?: string;
  solution_applied?: string;
  technician_notes?: string;
  internal_notes?: string;
  customer_visible_report?: string;
  hourly_rate: number;
  estimated_hours: number;
  labor_hours_total: number;
  labor_cost_total: number;
  travel_distance_km: number;
  travel_cost_per_km: number;
  technician_count_for_travel: number;
  travel_cost_total: number;
  parts_cost_total: number;
  subcontract_cost_total: number;
  discount_amount: number;
  tax_amount: number;
  grand_total: number;
  invoicing_status: 'not_invoiced' | 'invoiced' | 'partially_invoiced';
  payment_status: 'unpaid' | 'partially_paid' | 'paid';
  created_by: string;
  created_at: string;
  updated_at: string;
}

export interface ServiceOrderPart {
  id: string;
  service_order_id: string;
  product_id: string;
  quantity: number;
  unit_cost_snapshot: number;
  unit_sale_snapshot: number;
  line_total_cost: number;
  line_total_sale: number;
  notes?: string;
}

export interface TimeEntry {
  id: string;
  service_order_id: string;
  technician_user_id: string;
  started_at: string;
  ended_at?: string;
  duration_minutes: number;
  billable: boolean;
  notes?: string;
}

export interface Receivable {
  id: string;
  client_id: string;
  service_order_id?: string;
  description: string;
  issue_date: string;
  due_date: string;
  amount: number;
  status: 'pending' | 'partially_paid' | 'paid' | 'overdue' | 'cancelled';
  payment_method?: string;
  paid_amount: number;
  balance_amount: number;
  notes?: string;
}

export interface Payable {
  id: string;
  supplier_id?: string;
  expense_category?: string;
  description: string;
  issue_date: string;
  due_date: string;
  amount: number;
  status: 'pending' | 'partially_paid' | 'paid' | 'overdue' | 'cancelled';
  payment_method?: string;
  paid_amount: number;
  balance_amount: number;
  linked_service_order_id?: string;
  notes?: string;
}

export interface AppUser {
  id: string;
  full_name: string;
  email: string;
  phone: string;
  role: 'admin' | 'technician' | 'financial';
  active: boolean;
  avatar_url?: string;
  created_at: string;
}

export interface InventoryMovement {
  id: string;
  product_id: string;
  movement_type: 'purchase' | 'manual_adjustment' | 'service_usage' | 'return' | 'transfer';
  quantity_delta: number;
  reference_type?: string;
  reference_id?: string;
  unit_cost_snapshot?: number;
  notes?: string;
  created_by: string;
  created_at: string;
}
