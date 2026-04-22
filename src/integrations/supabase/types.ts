export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      agenda_tasks: {
        Row: {
          client_id: string | null
          created_at: string
          created_by: string | null
          description: string | null
          id: string
          location: string | null
          notes: string | null
          priority: string
          scheduled_end_at: string | null
          scheduled_start_at: string
          status: string
          technician_user_id: string
          title: string
          updated_at: string
        }
        Insert: {
          client_id?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          location?: string | null
          notes?: string | null
          priority?: string
          scheduled_end_at?: string | null
          scheduled_start_at: string
          status?: string
          technician_user_id: string
          title: string
          updated_at?: string
        }
        Update: {
          client_id?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          location?: string | null
          notes?: string | null
          priority?: string
          scheduled_end_at?: string | null
          scheduled_start_at?: string
          status?: string
          technician_user_id?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "agenda_tasks_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_tasks_technician_user_id_fkey"
            columns: ["technician_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      app_settings: {
        Row: {
          created_at: string
          default_cofins_rate: number | null
          default_commission_rate: number | null
          default_csosn: string | null
          default_fiscal_origin: number | null
          default_icms_rate: number | null
          default_ipi_rate: number | null
          default_pis_rate: number | null
          default_profit_margin: number | null
          description: string | null
          key: string
          simples_aliquota: number | null
          updated_at: string
          value: string
        }
        Insert: {
          created_at?: string
          default_cofins_rate?: number | null
          default_commission_rate?: number | null
          default_csosn?: string | null
          default_fiscal_origin?: number | null
          default_icms_rate?: number | null
          default_ipi_rate?: number | null
          default_pis_rate?: number | null
          default_profit_margin?: number | null
          description?: string | null
          key: string
          simples_aliquota?: number | null
          updated_at?: string
          value: string
        }
        Update: {
          created_at?: string
          default_cofins_rate?: number | null
          default_commission_rate?: number | null
          default_csosn?: string | null
          default_fiscal_origin?: number | null
          default_icms_rate?: number | null
          default_ipi_rate?: number | null
          default_pis_rate?: number | null
          default_profit_margin?: number | null
          description?: string | null
          key?: string
          simples_aliquota?: number | null
          updated_at?: string
          value?: string
        }
        Relationships: []
      }
      app_users: {
        Row: {
          active: boolean
          address_complement: string | null
          address_line_1: string | null
          address_number: string | null
          avatar_url: string | null
          city: string | null
          country: string | null
          created_at: string
          email: string
          full_name: string
          id: string
          neighborhood: string | null
          notes: string | null
          phone: string | null
          postal_code: string | null
          role: string
          state: string | null
          updated_at: string
        }
        Insert: {
          active?: boolean
          address_complement?: string | null
          address_line_1?: string | null
          address_number?: string | null
          avatar_url?: string | null
          city?: string | null
          country?: string | null
          created_at?: string
          email: string
          full_name: string
          id: string
          neighborhood?: string | null
          notes?: string | null
          phone?: string | null
          postal_code?: string | null
          role: string
          state?: string | null
          updated_at?: string
        }
        Update: {
          active?: boolean
          address_complement?: string | null
          address_line_1?: string | null
          address_number?: string | null
          avatar_url?: string | null
          city?: string | null
          country?: string | null
          created_at?: string
          email?: string
          full_name?: string
          id?: string
          neighborhood?: string | null
          notes?: string | null
          phone?: string | null
          postal_code?: string | null
          role?: string
          state?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      audit_log: {
        Row: {
          action: string
          changed_at: string | null
          changed_by: string
          id: string
          new_value: Json | null
          previous_value: Json | null
          reason: string | null
          record_id: string
          table_name: string
          triggered_by_id: string | null
          triggered_by_table: string | null
        }
        Insert: {
          action: string
          changed_at?: string | null
          changed_by?: string
          id?: string
          new_value?: Json | null
          previous_value?: Json | null
          reason?: string | null
          record_id: string
          table_name: string
          triggered_by_id?: string | null
          triggered_by_table?: string | null
        }
        Update: {
          action?: string
          changed_at?: string | null
          changed_by?: string
          id?: string
          new_value?: Json | null
          previous_value?: Json | null
          reason?: string | null
          record_id?: string
          table_name?: string
          triggered_by_id?: string | null
          triggered_by_table?: string | null
        }
        Relationships: []
      }
      bank_transactions: {
        Row: {
          amount: number
          bank_ref_id: string | null
          created_at: string | null
          description: string
          id: string
          import_batch_id: string | null
          reconciled: boolean | null
          reconciled_payment_id: string | null
          reconciled_service_order_id: string | null
          source_type: string | null
          transaction_date: string
          transaction_type: string
        }
        Insert: {
          amount: number
          bank_ref_id?: string | null
          created_at?: string | null
          description: string
          id?: string
          import_batch_id?: string | null
          reconciled?: boolean | null
          reconciled_payment_id?: string | null
          reconciled_service_order_id?: string | null
          source_type?: string | null
          transaction_date: string
          transaction_type: string
        }
        Update: {
          amount?: number
          bank_ref_id?: string | null
          created_at?: string | null
          description?: string
          id?: string
          import_batch_id?: string | null
          reconciled?: boolean | null
          reconciled_payment_id?: string | null
          reconciled_service_order_id?: string | null
          source_type?: string | null
          transaction_date?: string
          transaction_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "bank_transactions_reconciled_payment_id_fkey"
            columns: ["reconciled_payment_id"]
            isOneToOne: false
            referencedRelation: "payments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_transactions_reconciled_service_order_id_fkey"
            columns: ["reconciled_service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      card_installment_fees: {
        Row: {
          fee_percent: number
          installments: number
          updated_at: string | null
        }
        Insert: {
          fee_percent?: number
          installments: number
          updated_at?: string | null
        }
        Update: {
          fee_percent?: number
          installments?: number
          updated_at?: string | null
        }
        Relationships: []
      }
      client_whatsapp_settings: {
        Row: {
          client_id: string
          context: string
          created_at: string
          id: string
          link_description: string | null
          link_title: string | null
          message_body: string | null
          pdf_filename_pattern: string | null
          updated_at: string
        }
        Insert: {
          client_id: string
          context: string
          created_at?: string
          id?: string
          link_description?: string | null
          link_title?: string | null
          message_body?: string | null
          pdf_filename_pattern?: string | null
          updated_at?: string
        }
        Update: {
          client_id?: string
          context?: string
          created_at?: string
          id?: string
          link_description?: string | null
          link_title?: string | null
          message_body?: string | null
          pdf_filename_pattern?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "client_whatsapp_settings_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      clients: {
        Row: {
          active: boolean
          address_line_1: string | null
          address_line_2: string | null
          city: string | null
          country: string | null
          cpf_cnpj: string | null
          created_at: string
          email: string | null
          full_name_or_company_name: string
          id: string
          notes: string | null
          phone: string | null
          postal_code: string | null
          state: string | null
          type: string
          updated_at: string
          whatsapp: string | null
        }
        Insert: {
          active?: boolean
          address_line_1?: string | null
          address_line_2?: string | null
          city?: string | null
          country?: string | null
          cpf_cnpj?: string | null
          created_at?: string
          email?: string | null
          full_name_or_company_name: string
          id?: string
          notes?: string | null
          phone?: string | null
          postal_code?: string | null
          state?: string | null
          type: string
          updated_at?: string
          whatsapp?: string | null
        }
        Update: {
          active?: boolean
          address_line_1?: string | null
          address_line_2?: string | null
          city?: string | null
          country?: string | null
          cpf_cnpj?: string | null
          created_at?: string
          email?: string | null
          full_name_or_company_name?: string
          id?: string
          notes?: string | null
          phone?: string | null
          postal_code?: string | null
          state?: string | null
          type?: string
          updated_at?: string
          whatsapp?: string | null
        }
        Relationships: []
      }
      collection_contacts: {
        Row: {
          collection_id: string
          contact_type: string
          created_at: string
          created_by: string | null
          id: string
          notes: string | null
          promised_date: string | null
        }
        Insert: {
          collection_id: string
          contact_type: string
          created_at?: string
          created_by?: string | null
          id?: string
          notes?: string | null
          promised_date?: string | null
        }
        Update: {
          collection_id?: string
          contact_type?: string
          created_at?: string
          created_by?: string | null
          id?: string
          notes?: string | null
          promised_date?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "collection_contacts_collection_id_fkey"
            columns: ["collection_id"]
            isOneToOne: false
            referencedRelation: "collections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "collection_contacts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      collection_templates: {
        Row: {
          body: string
          created_at: string
          id: string
          is_default: boolean | null
          name: string
          send_method: string | null
        }
        Insert: {
          body: string
          created_at?: string
          id?: string
          is_default?: boolean | null
          name: string
          send_method?: string | null
        }
        Update: {
          body?: string
          created_at?: string
          id?: string
          is_default?: boolean | null
          name?: string
          send_method?: string | null
        }
        Relationships: []
      }
      collections: {
        Row: {
          amount: number
          auto_rule_enabled: boolean | null
          client_id: string
          contact_name: string | null
          contact_phone: string | null
          contact_whatsapp: string | null
          created_at: string
          created_by: string | null
          description: string | null
          due_date: string
          id: string
          last_auto_sent_at: string | null
          message_template: string | null
          notes: string | null
          paid_amount: number | null
          paid_at: string | null
          paid_method: string | null
          payment_confirmed_by: string | null
          receivable_id: string | null
          rule_days_after: number | null
          rule_days_before: number | null
          send_method: string | null
          service_order_id: string | null
          standalone_amount: number | null
          status: string
          updated_at: string
        }
        Insert: {
          amount: number
          auto_rule_enabled?: boolean | null
          client_id: string
          contact_name?: string | null
          contact_phone?: string | null
          contact_whatsapp?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          due_date: string
          id?: string
          last_auto_sent_at?: string | null
          message_template?: string | null
          notes?: string | null
          paid_amount?: number | null
          paid_at?: string | null
          paid_method?: string | null
          payment_confirmed_by?: string | null
          receivable_id?: string | null
          rule_days_after?: number | null
          rule_days_before?: number | null
          send_method?: string | null
          service_order_id?: string | null
          standalone_amount?: number | null
          status?: string
          updated_at?: string
        }
        Update: {
          amount?: number
          auto_rule_enabled?: boolean | null
          client_id?: string
          contact_name?: string | null
          contact_phone?: string | null
          contact_whatsapp?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          due_date?: string
          id?: string
          last_auto_sent_at?: string | null
          message_template?: string | null
          notes?: string | null
          paid_amount?: number | null
          paid_at?: string | null
          paid_method?: string | null
          payment_confirmed_by?: string | null
          receivable_id?: string | null
          rule_days_after?: number | null
          rule_days_before?: number | null
          send_method?: string | null
          service_order_id?: string | null
          standalone_amount?: number | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "collections_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "collections_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "collections_receivable_id_fkey"
            columns: ["receivable_id"]
            isOneToOne: false
            referencedRelation: "receivables"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "collections_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      exchange_rates: {
        Row: {
          created_at: string
          from_currency: string
          id: string
          rate: number
          recorded_at: string
          source: string | null
          to_currency: string
        }
        Insert: {
          created_at?: string
          from_currency: string
          id?: string
          rate: number
          recorded_at?: string
          source?: string | null
          to_currency: string
        }
        Update: {
          created_at?: string
          from_currency?: string
          id?: string
          rate?: number
          recorded_at?: string
          source?: string | null
          to_currency?: string
        }
        Relationships: []
      }
      financial_categories: {
        Row: {
          active: boolean | null
          color: string | null
          created_at: string | null
          id: string
          name: string
          type: string
        }
        Insert: {
          active?: boolean | null
          color?: string | null
          created_at?: string | null
          id?: string
          name: string
          type: string
        }
        Update: {
          active?: boolean | null
          color?: string | null
          created_at?: string | null
          id?: string
          name?: string
          type?: string
        }
        Relationships: []
      }
      import_sessions: {
        Row: {
          column_mapping: Json | null
          conflict_rows: number | null
          created_at: string | null
          entity_type: string
          filename: string
          id: string
          imported_rows: number | null
          skipped_rows: number | null
          status: string | null
          total_rows: number | null
        }
        Insert: {
          column_mapping?: Json | null
          conflict_rows?: number | null
          created_at?: string | null
          entity_type: string
          filename: string
          id?: string
          imported_rows?: number | null
          skipped_rows?: number | null
          status?: string | null
          total_rows?: number | null
        }
        Update: {
          column_mapping?: Json | null
          conflict_rows?: number | null
          created_at?: string | null
          entity_type?: string
          filename?: string
          id?: string
          imported_rows?: number | null
          skipped_rows?: number | null
          status?: string | null
          total_rows?: number | null
        }
        Relationships: []
      }
      inventory_movements: {
        Row: {
          adjusted_by: string | null
          created_at: string
          created_by: string | null
          id: string
          movement_type: string
          notes: string | null
          product_id: string
          quantity_delta: number
          reference_id: string | null
          reference_type: string | null
          unit_cost_snapshot: number | null
        }
        Insert: {
          adjusted_by?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          movement_type: string
          notes?: string | null
          product_id: string
          quantity_delta: number
          reference_id?: string | null
          reference_type?: string | null
          unit_cost_snapshot?: number | null
        }
        Update: {
          adjusted_by?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          movement_type?: string
          notes?: string | null
          product_id?: string
          quantity_delta?: number
          reference_id?: string | null
          reference_type?: string | null
          unit_cost_snapshot?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "inventory_movements_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_movements_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
        ]
      }
      invoices: {
        Row: {
          client_id: string
          created_at: string
          currency: string | null
          discount_amount: number | null
          due_date: string
          id: string
          invoice_number: string
          issue_date: string
          notes: string | null
          service_order_id: string | null
          status: string | null
          subtotal: number | null
          tax_amount: number | null
          total_amount: number | null
          updated_at: string
        }
        Insert: {
          client_id: string
          created_at?: string
          currency?: string | null
          discount_amount?: number | null
          due_date: string
          id?: string
          invoice_number: string
          issue_date: string
          notes?: string | null
          service_order_id?: string | null
          status?: string | null
          subtotal?: number | null
          tax_amount?: number | null
          total_amount?: number | null
          updated_at?: string
        }
        Update: {
          client_id?: string
          created_at?: string
          currency?: string | null
          discount_amount?: number | null
          due_date?: string
          id?: string
          invoice_number?: string
          issue_date?: string
          notes?: string | null
          service_order_id?: string | null
          status?: string | null
          subtotal?: number | null
          tax_amount?: number | null
          total_amount?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "invoices_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      marinas: {
        Row: {
          access_notes: string | null
          active: boolean
          address_line_1: string | null
          billing_notes: string | null
          city: string | null
          contact_email: string | null
          contact_name: string | null
          contact_phone: string | null
          country: string | null
          created_at: string
          id: string
          latitude: number | null
          longitude: number | null
          marina_name: string
          postal_code: string | null
          state: string | null
          updated_at: string
        }
        Insert: {
          access_notes?: string | null
          active?: boolean
          address_line_1?: string | null
          billing_notes?: string | null
          city?: string | null
          contact_email?: string | null
          contact_name?: string | null
          contact_phone?: string | null
          country?: string | null
          created_at?: string
          id?: string
          latitude?: number | null
          longitude?: number | null
          marina_name: string
          postal_code?: string | null
          state?: string | null
          updated_at?: string
        }
        Update: {
          access_notes?: string | null
          active?: boolean
          address_line_1?: string | null
          billing_notes?: string | null
          city?: string | null
          contact_email?: string | null
          contact_name?: string | null
          contact_phone?: string | null
          country?: string | null
          created_at?: string
          id?: string
          latitude?: number | null
          longitude?: number | null
          marina_name?: string
          postal_code?: string | null
          state?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      payables: {
        Row: {
          amount: number
          balance_amount: number | null
          bank_transaction_id: string | null
          created_at: string
          currency: string | null
          description: string
          due_date: string
          expense_category: string | null
          id: string
          issue_date: string
          linked_service_order_id: string | null
          notes: string | null
          origin: string | null
          paid_amount: number | null
          payment_method: string | null
          status: string | null
          supplier_id: string | null
          supplier_name: string | null
          updated_at: string
        }
        Insert: {
          amount: number
          balance_amount?: number | null
          bank_transaction_id?: string | null
          created_at?: string
          currency?: string | null
          description: string
          due_date: string
          expense_category?: string | null
          id?: string
          issue_date: string
          linked_service_order_id?: string | null
          notes?: string | null
          origin?: string | null
          paid_amount?: number | null
          payment_method?: string | null
          status?: string | null
          supplier_id?: string | null
          supplier_name?: string | null
          updated_at?: string
        }
        Update: {
          amount?: number
          balance_amount?: number | null
          bank_transaction_id?: string | null
          created_at?: string
          currency?: string | null
          description?: string
          due_date?: string
          expense_category?: string | null
          id?: string
          issue_date?: string
          linked_service_order_id?: string | null
          notes?: string | null
          origin?: string | null
          paid_amount?: number | null
          payment_method?: string | null
          status?: string | null
          supplier_id?: string | null
          supplier_name?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payables_bank_transaction_id_fkey"
            columns: ["bank_transaction_id"]
            isOneToOne: false
            referencedRelation: "bank_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payables_linked_service_order_id_fkey"
            columns: ["linked_service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payables_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_condition_presets: {
        Row: {
          active: boolean | null
          auto_generate_collections: boolean | null
          created_at: string | null
          id: string
          installments: Json | null
          label: string
          sort_order: number | null
        }
        Insert: {
          active?: boolean | null
          auto_generate_collections?: boolean | null
          created_at?: string | null
          id?: string
          installments?: Json | null
          label: string
          sort_order?: number | null
        }
        Update: {
          active?: boolean | null
          auto_generate_collections?: boolean | null
          created_at?: string | null
          id?: string
          installments?: Json | null
          label?: string
          sort_order?: number | null
        }
        Relationships: []
      }
      payments: {
        Row: {
          amount: number
          cancellation_reason: string | null
          cancelled_at: string | null
          card_fee_percent: number | null
          created_at: string | null
          id: string
          installments: number | null
          net_amount: number | null
          notes: string | null
          payable_id: string | null
          payment_date: string
          payment_method: string
          receivable_id: string | null
          status: string | null
        }
        Insert: {
          amount: number
          cancellation_reason?: string | null
          cancelled_at?: string | null
          card_fee_percent?: number | null
          created_at?: string | null
          id?: string
          installments?: number | null
          net_amount?: number | null
          notes?: string | null
          payable_id?: string | null
          payment_date?: string
          payment_method?: string
          receivable_id?: string | null
          status?: string | null
        }
        Update: {
          amount?: number
          cancellation_reason?: string | null
          cancelled_at?: string | null
          card_fee_percent?: number | null
          created_at?: string | null
          id?: string
          installments?: number | null
          net_amount?: number | null
          notes?: string | null
          payable_id?: string | null
          payment_date?: string
          payment_method?: string
          receivable_id?: string | null
          status?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "payments_payable_id_fkey"
            columns: ["payable_id"]
            isOneToOne: false
            referencedRelation: "payables"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payments_receivable_id_fkey"
            columns: ["receivable_id"]
            isOneToOne: false
            referencedRelation: "receivables"
            referencedColumns: ["id"]
          },
        ]
      }
      product_categories: {
        Row: {
          active: boolean | null
          created_at: string | null
          default_cofins_rate: number | null
          default_commission_rate: number | null
          default_csosn: string | null
          default_fiscal_origin: number | null
          default_icms_rate: number | null
          default_ipi_rate: number | null
          default_ncm: string | null
          default_pis_rate: number | null
          default_profit_margin: number | null
          description: string | null
          id: string
          is_commissionable: boolean | null
          name: string
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          created_at?: string | null
          default_cofins_rate?: number | null
          default_commission_rate?: number | null
          default_csosn?: string | null
          default_fiscal_origin?: number | null
          default_icms_rate?: number | null
          default_ipi_rate?: number | null
          default_ncm?: string | null
          default_pis_rate?: number | null
          default_profit_margin?: number | null
          description?: string | null
          id?: string
          is_commissionable?: boolean | null
          name: string
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          created_at?: string | null
          default_cofins_rate?: number | null
          default_commission_rate?: number | null
          default_csosn?: string | null
          default_fiscal_origin?: number | null
          default_icms_rate?: number | null
          default_ipi_rate?: number | null
          default_ncm?: string | null
          default_pis_rate?: number | null
          default_profit_margin?: number | null
          description?: string | null
          id?: string
          is_commissionable?: boolean | null
          name?: string
          updated_at?: string | null
        }
        Relationships: []
      }
      product_suppliers: {
        Row: {
          cost_price: number | null
          created_at: string | null
          currency: string | null
          id: string
          is_preferred: boolean | null
          last_purchase_date: string | null
          last_purchase_price: number | null
          lead_time_days: number | null
          minimum_order_qty: number | null
          notes: string | null
          product_id: string
          supplier_id: string
          supplier_sku: string | null
          updated_at: string | null
        }
        Insert: {
          cost_price?: number | null
          created_at?: string | null
          currency?: string | null
          id?: string
          is_preferred?: boolean | null
          last_purchase_date?: string | null
          last_purchase_price?: number | null
          lead_time_days?: number | null
          minimum_order_qty?: number | null
          notes?: string | null
          product_id: string
          supplier_id: string
          supplier_sku?: string | null
          updated_at?: string | null
        }
        Update: {
          cost_price?: number | null
          created_at?: string | null
          currency?: string | null
          id?: string
          is_preferred?: boolean | null
          last_purchase_date?: string | null
          last_purchase_price?: number | null
          lead_time_days?: number | null
          minimum_order_qty?: number | null
          notes?: string | null
          product_id?: string
          supplier_id?: string
          supplier_sku?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "product_suppliers_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_suppliers_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      products: {
        Row: {
          active: boolean
          barcode: string | null
          brand: string | null
          category: string | null
          cofins_rate: number | null
          commission_rate: number | null
          cost_currency: string | null
          cost_price: number | null
          created_at: string
          csosn: string | null
          fiscal_origin: number | null
          icms_rate: number | null
          id: string
          ipi_rate: number | null
          is_commissionable: boolean | null
          location_bin: string | null
          minimum_stock: number | null
          ncm: string | null
          notes: string | null
          pis_rate: number | null
          product_category_id: string | null
          product_name: string
          profit_margin: number | null
          sale_currency: string | null
          sale_price: number | null
          sku: string | null
          stock_quantity: number | null
          unit: string | null
          updated_at: string
          use_global_fiscal: boolean | null
        }
        Insert: {
          active?: boolean
          barcode?: string | null
          brand?: string | null
          category?: string | null
          cofins_rate?: number | null
          commission_rate?: number | null
          cost_currency?: string | null
          cost_price?: number | null
          created_at?: string
          csosn?: string | null
          fiscal_origin?: number | null
          icms_rate?: number | null
          id?: string
          ipi_rate?: number | null
          is_commissionable?: boolean | null
          location_bin?: string | null
          minimum_stock?: number | null
          ncm?: string | null
          notes?: string | null
          pis_rate?: number | null
          product_category_id?: string | null
          product_name: string
          profit_margin?: number | null
          sale_currency?: string | null
          sale_price?: number | null
          sku?: string | null
          stock_quantity?: number | null
          unit?: string | null
          updated_at?: string
          use_global_fiscal?: boolean | null
        }
        Update: {
          active?: boolean
          barcode?: string | null
          brand?: string | null
          category?: string | null
          cofins_rate?: number | null
          commission_rate?: number | null
          cost_currency?: string | null
          cost_price?: number | null
          created_at?: string
          csosn?: string | null
          fiscal_origin?: number | null
          icms_rate?: number | null
          id?: string
          ipi_rate?: number | null
          is_commissionable?: boolean | null
          location_bin?: string | null
          minimum_stock?: number | null
          ncm?: string | null
          notes?: string | null
          pis_rate?: number | null
          product_category_id?: string | null
          product_name?: string
          profit_margin?: number | null
          sale_currency?: string | null
          sale_price?: number | null
          sku?: string | null
          stock_quantity?: number | null
          unit?: string | null
          updated_at?: string
          use_global_fiscal?: boolean | null
        }
        Relationships: [
          {
            foreignKeyName: "products_product_category_id_fkey"
            columns: ["product_category_id"]
            isOneToOne: false
            referencedRelation: "product_categories"
            referencedColumns: ["id"]
          },
        ]
      }
      receivables: {
        Row: {
          amount: number
          balance_amount: number | null
          category: string | null
          client_id: string
          created_at: string
          currency: string | null
          description: string
          due_date: string
          id: string
          invoice_id: string | null
          issue_date: string
          notes: string | null
          paid_amount: number | null
          payment_method: string | null
          service_order_id: string | null
          status: string | null
          updated_at: string
        }
        Insert: {
          amount: number
          balance_amount?: number | null
          category?: string | null
          client_id: string
          created_at?: string
          currency?: string | null
          description: string
          due_date: string
          id?: string
          invoice_id?: string | null
          issue_date: string
          notes?: string | null
          paid_amount?: number | null
          payment_method?: string | null
          service_order_id?: string | null
          status?: string | null
          updated_at?: string
        }
        Update: {
          amount?: number
          balance_amount?: number | null
          category?: string | null
          client_id?: string
          created_at?: string
          currency?: string | null
          description?: string
          due_date?: string
          id?: string
          invoice_id?: string | null
          issue_date?: string
          notes?: string | null
          paid_amount?: number | null
          payment_method?: string | null
          service_order_id?: string | null
          status?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "receivables_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receivables_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receivables_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      saved_filters: {
        Row: {
          created_at: string | null
          filter_config: Json
          filter_type: string
          id: string
          name: string
        }
        Insert: {
          created_at?: string | null
          filter_config?: Json
          filter_type: string
          id?: string
          name: string
        }
        Update: {
          created_at?: string | null
          filter_config?: Json
          filter_type?: string
          id?: string
          name?: string
        }
        Relationships: []
      }
      service_order_expenses: {
        Row: {
          amount: number
          category: string
          created_at: string | null
          created_by: string | null
          currency: string | null
          description: string
          expense_date: string
          id: string
          linked_payable_id: string | null
          notes: string | null
          paid_by: string
          receipt_url: string | null
          reimbursed: boolean | null
          reimbursed_at: string | null
          reimbursed_payment_id: string | null
          service_order_id: string | null
          technician_user_id: string | null
          updated_at: string | null
        }
        Insert: {
          amount: number
          category: string
          created_at?: string | null
          created_by?: string | null
          currency?: string | null
          description: string
          expense_date?: string
          id?: string
          linked_payable_id?: string | null
          notes?: string | null
          paid_by?: string
          receipt_url?: string | null
          reimbursed?: boolean | null
          reimbursed_at?: string | null
          reimbursed_payment_id?: string | null
          service_order_id?: string | null
          technician_user_id?: string | null
          updated_at?: string | null
        }
        Update: {
          amount?: number
          category?: string
          created_at?: string | null
          created_by?: string | null
          currency?: string | null
          description?: string
          expense_date?: string
          id?: string
          linked_payable_id?: string | null
          notes?: string | null
          paid_by?: string
          receipt_url?: string | null
          reimbursed?: boolean | null
          reimbursed_at?: string | null
          reimbursed_payment_id?: string | null
          service_order_id?: string | null
          technician_user_id?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "service_order_expenses_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_expenses_linked_payable_id_fkey"
            columns: ["linked_payable_id"]
            isOneToOne: false
            referencedRelation: "payables"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_expenses_reimbursed_payment_id_fkey"
            columns: ["reimbursed_payment_id"]
            isOneToOne: false
            referencedRelation: "payments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_expenses_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_expenses_technician_user_id_fkey"
            columns: ["technician_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      service_order_parts: {
        Row: {
          created_at: string
          currency_snapshot: string | null
          id: string
          line_total_cost: number
          line_total_sale: number
          notes: string | null
          product_id: string
          quantity: number
          service_order_id: string
          unit_cost_snapshot: number
          unit_sale_snapshot: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          currency_snapshot?: string | null
          id?: string
          line_total_cost: number
          line_total_sale: number
          notes?: string | null
          product_id: string
          quantity: number
          service_order_id: string
          unit_cost_snapshot: number
          unit_sale_snapshot: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          currency_snapshot?: string | null
          id?: string
          line_total_cost?: number
          line_total_sale?: number
          notes?: string | null
          product_id?: string
          quantity?: number
          service_order_id?: string
          unit_cost_snapshot?: number
          unit_sale_snapshot?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_order_parts_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_parts_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      service_order_services: {
        Row: {
          billing_unit_snapshot: string
          created_at: string | null
          description_snapshot: string | null
          id: string
          line_total: number
          notes: string | null
          quantity: number
          service_id: string | null
          service_name_snapshot: string
          service_order_id: string
          unit_price_snapshot: number
          updated_at: string | null
        }
        Insert: {
          billing_unit_snapshot?: string
          created_at?: string | null
          description_snapshot?: string | null
          id?: string
          line_total?: number
          notes?: string | null
          quantity?: number
          service_id?: string | null
          service_name_snapshot: string
          service_order_id: string
          unit_price_snapshot?: number
          updated_at?: string | null
        }
        Update: {
          billing_unit_snapshot?: string
          created_at?: string | null
          description_snapshot?: string | null
          id?: string
          line_total?: number
          notes?: string | null
          quantity?: number
          service_id?: string | null
          service_name_snapshot?: string
          service_order_id?: string
          unit_price_snapshot?: number
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "service_order_services_service_id_fkey"
            columns: ["service_id"]
            isOneToOne: false
            referencedRelation: "services"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_services_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      service_order_signatures: {
        Row: {
          accepted_name: string
          accepted_terms_snapshot: string | null
          created_at: string
          document_hash: string
          id: string
          ip_address: string | null
          service_order_id: string
          share_token: string
          signature_image_url: string | null
          signed_at: string
          signed_pdf_url: string | null
          superseded_at: string | null
          superseded_reason: string | null
          user_agent: string | null
        }
        Insert: {
          accepted_name: string
          accepted_terms_snapshot?: string | null
          created_at?: string
          document_hash: string
          id?: string
          ip_address?: string | null
          service_order_id: string
          share_token: string
          signature_image_url?: string | null
          signed_at?: string
          signed_pdf_url?: string | null
          superseded_at?: string | null
          superseded_reason?: string | null
          user_agent?: string | null
        }
        Update: {
          accepted_name?: string
          accepted_terms_snapshot?: string | null
          created_at?: string
          document_hash?: string
          id?: string
          ip_address?: string | null
          service_order_id?: string
          share_token?: string
          signature_image_url?: string | null
          signed_at?: string
          signed_pdf_url?: string | null
          superseded_at?: string | null
          superseded_reason?: string | null
          user_agent?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "service_order_signatures_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      service_order_technicians: {
        Row: {
          created_at: string
          id: string | null
          role_in_order: string | null
          service_order_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string | null
          role_in_order?: string | null
          service_order_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string | null
          role_in_order?: string | null
          service_order_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_order_technicians_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_technicians_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      service_orders: {
        Row: {
          cancellation_reason: string | null
          cancelled_at: string | null
          card_installments: number | null
          check_in_at: string | null
          check_out_at: string | null
          client_id: string
          client_signature_url: string | null
          commission_amount: number | null
          commission_rate: number | null
          commissioned_person: string | null
          commissioned_user_id: string | null
          created_at: string
          created_by: string | null
          currency: string | null
          customer_visible_report: string | null
          diagnosis: string | null
          discount_amount: number | null
          estimated_hours: number | null
          extra_notes: string | null
          grand_total: number | null
          hourly_rate: number | null
          id: string
          initial_findings: string | null
          internal_notes: string | null
          invoicing_status: string | null
          labor_cost_total: number | null
          labor_hours_total: number | null
          marina_id: string | null
          operational_cost_total: number | null
          parts_cost_total: number | null
          payment_condition_preset_id: string | null
          payment_conditions: string | null
          payment_method: string | null
          payment_status: string | null
          priority: string
          problem_description: string | null
          quote_validity_date: string | null
          quote_validity_days: number | null
          reopen_reason: string | null
          reopened_at: string | null
          requested_by_contact_id: string | null
          requested_by_name: string | null
          requires_resignature: boolean
          resignature_requested_at: string | null
          scheduled_end_at: string | null
          scheduled_start_at: string | null
          service_order_number: string
          service_type: string | null
          share_token: string | null
          signed_at: string | null
          signed_by_name: string | null
          signed_document_hash: string | null
          solution_applied: string | null
          status: string
          subcontract_cost_total: number | null
          tax_amount: number | null
          technician_count_for_travel: number | null
          technician_notes: string | null
          travel_cost_per_km: number | null
          travel_cost_total: number | null
          travel_distance_km: number | null
          updated_at: string
          vessel_id: string
        }
        Insert: {
          cancellation_reason?: string | null
          cancelled_at?: string | null
          card_installments?: number | null
          check_in_at?: string | null
          check_out_at?: string | null
          client_id: string
          client_signature_url?: string | null
          commission_amount?: number | null
          commission_rate?: number | null
          commissioned_person?: string | null
          commissioned_user_id?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string | null
          customer_visible_report?: string | null
          diagnosis?: string | null
          discount_amount?: number | null
          estimated_hours?: number | null
          extra_notes?: string | null
          grand_total?: number | null
          hourly_rate?: number | null
          id?: string
          initial_findings?: string | null
          internal_notes?: string | null
          invoicing_status?: string | null
          labor_cost_total?: number | null
          labor_hours_total?: number | null
          marina_id?: string | null
          operational_cost_total?: number | null
          parts_cost_total?: number | null
          payment_condition_preset_id?: string | null
          payment_conditions?: string | null
          payment_method?: string | null
          payment_status?: string | null
          priority?: string
          problem_description?: string | null
          quote_validity_date?: string | null
          quote_validity_days?: number | null
          reopen_reason?: string | null
          reopened_at?: string | null
          requested_by_contact_id?: string | null
          requested_by_name?: string | null
          requires_resignature?: boolean
          resignature_requested_at?: string | null
          scheduled_end_at?: string | null
          scheduled_start_at?: string | null
          service_order_number: string
          service_type?: string | null
          share_token?: string | null
          signed_at?: string | null
          signed_by_name?: string | null
          signed_document_hash?: string | null
          solution_applied?: string | null
          status?: string
          subcontract_cost_total?: number | null
          tax_amount?: number | null
          technician_count_for_travel?: number | null
          technician_notes?: string | null
          travel_cost_per_km?: number | null
          travel_cost_total?: number | null
          travel_distance_km?: number | null
          updated_at?: string
          vessel_id: string
        }
        Update: {
          cancellation_reason?: string | null
          cancelled_at?: string | null
          card_installments?: number | null
          check_in_at?: string | null
          check_out_at?: string | null
          client_id?: string
          client_signature_url?: string | null
          commission_amount?: number | null
          commission_rate?: number | null
          commissioned_person?: string | null
          commissioned_user_id?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string | null
          customer_visible_report?: string | null
          diagnosis?: string | null
          discount_amount?: number | null
          estimated_hours?: number | null
          extra_notes?: string | null
          grand_total?: number | null
          hourly_rate?: number | null
          id?: string
          initial_findings?: string | null
          internal_notes?: string | null
          invoicing_status?: string | null
          labor_cost_total?: number | null
          labor_hours_total?: number | null
          marina_id?: string | null
          operational_cost_total?: number | null
          parts_cost_total?: number | null
          payment_condition_preset_id?: string | null
          payment_conditions?: string | null
          payment_method?: string | null
          payment_status?: string | null
          priority?: string
          problem_description?: string | null
          quote_validity_date?: string | null
          quote_validity_days?: number | null
          reopen_reason?: string | null
          reopened_at?: string | null
          requested_by_contact_id?: string | null
          requested_by_name?: string | null
          requires_resignature?: boolean
          resignature_requested_at?: string | null
          scheduled_end_at?: string | null
          scheduled_start_at?: string | null
          service_order_number?: string
          service_type?: string | null
          share_token?: string | null
          signed_at?: string | null
          signed_by_name?: string | null
          signed_document_hash?: string | null
          solution_applied?: string | null
          status?: string
          subcontract_cost_total?: number | null
          tax_amount?: number | null
          technician_count_for_travel?: number | null
          technician_notes?: string | null
          travel_cost_per_km?: number | null
          travel_cost_total?: number | null
          travel_distance_km?: number | null
          updated_at?: string
          vessel_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_orders_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_orders_commissioned_user_id_fkey"
            columns: ["commissioned_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_orders_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_orders_marina_id_fkey"
            columns: ["marina_id"]
            isOneToOne: false
            referencedRelation: "marinas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_orders_payment_condition_preset_id_fkey"
            columns: ["payment_condition_preset_id"]
            isOneToOne: false
            referencedRelation: "payment_condition_presets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_orders_requested_by_contact_id_fkey"
            columns: ["requested_by_contact_id"]
            isOneToOne: false
            referencedRelation: "vessel_contacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_orders_vessel_id_fkey"
            columns: ["vessel_id"]
            isOneToOne: false
            referencedRelation: "vessels"
            referencedColumns: ["id"]
          },
        ]
      }
      services: {
        Row: {
          active: boolean | null
          billing_unit: string
          category: string | null
          created_at: string | null
          currency: string | null
          default_price: number | null
          description: string | null
          id: string
          service_name: string
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          billing_unit?: string
          category?: string | null
          created_at?: string | null
          currency?: string | null
          default_price?: number | null
          description?: string | null
          id?: string
          service_name: string
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          billing_unit?: string
          category?: string | null
          created_at?: string | null
          currency?: string | null
          default_price?: number | null
          description?: string | null
          id?: string
          service_name?: string
          updated_at?: string | null
        }
        Relationships: []
      }
      suppliers: {
        Row: {
          active: boolean | null
          address_complement: string | null
          address_line_1: string | null
          address_number: string | null
          city: string | null
          cnpj_cpf: string | null
          contact_email: string | null
          contact_name: string | null
          contact_phone: string | null
          country: string | null
          created_at: string | null
          id: string
          neighborhood: string | null
          notes: string | null
          payment_terms: string | null
          postal_code: string | null
          state: string | null
          supplier_name: string
          trade_name: string | null
          updated_at: string | null
          website: string | null
        }
        Insert: {
          active?: boolean | null
          address_complement?: string | null
          address_line_1?: string | null
          address_number?: string | null
          city?: string | null
          cnpj_cpf?: string | null
          contact_email?: string | null
          contact_name?: string | null
          contact_phone?: string | null
          country?: string | null
          created_at?: string | null
          id?: string
          neighborhood?: string | null
          notes?: string | null
          payment_terms?: string | null
          postal_code?: string | null
          state?: string | null
          supplier_name: string
          trade_name?: string | null
          updated_at?: string | null
          website?: string | null
        }
        Update: {
          active?: boolean | null
          address_complement?: string | null
          address_line_1?: string | null
          address_number?: string | null
          city?: string | null
          cnpj_cpf?: string | null
          contact_email?: string | null
          contact_name?: string | null
          contact_phone?: string | null
          country?: string | null
          created_at?: string | null
          id?: string
          neighborhood?: string | null
          notes?: string | null
          payment_terms?: string | null
          postal_code?: string | null
          state?: string | null
          supplier_name?: string
          trade_name?: string | null
          updated_at?: string | null
          website?: string | null
        }
        Relationships: []
      }
      time_entries: {
        Row: {
          billable: boolean | null
          created_at: string
          duration_minutes: number | null
          ended_at: string | null
          id: string
          notes: string | null
          service_order_id: string
          started_at: string
          technician_user_id: string
          updated_at: string
        }
        Insert: {
          billable?: boolean | null
          created_at?: string
          duration_minutes?: number | null
          ended_at?: string | null
          id?: string
          notes?: string | null
          service_order_id: string
          started_at: string
          technician_user_id: string
          updated_at?: string
        }
        Update: {
          billable?: boolean | null
          created_at?: string
          duration_minutes?: number | null
          ended_at?: string | null
          id?: string
          notes?: string | null
          service_order_id?: string
          started_at?: string
          technician_user_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "time_entries_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "time_entries_technician_user_id_fkey"
            columns: ["technician_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      vessel_contacts: {
        Row: {
          active: boolean | null
          created_at: string | null
          email: string | null
          full_name: string
          id: string
          notes: string | null
          phone: string | null
          role: string
          vessel_id: string
        }
        Insert: {
          active?: boolean | null
          created_at?: string | null
          email?: string | null
          full_name: string
          id?: string
          notes?: string | null
          phone?: string | null
          role?: string
          vessel_id: string
        }
        Update: {
          active?: boolean | null
          created_at?: string | null
          email?: string | null
          full_name?: string
          id?: string
          notes?: string | null
          phone?: string | null
          role?: string
          vessel_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vessel_contacts_vessel_id_fkey"
            columns: ["vessel_id"]
            isOneToOne: false
            referencedRelation: "vessels"
            referencedColumns: ["id"]
          },
        ]
      }
      vessels: {
        Row: {
          active: boolean
          battery_bank_summary: string | null
          beam_feet: number | null
          boat_name: string
          client_id: string
          created_at: string
          current_dock_position: string | null
          current_marina_name_snapshot: string | null
          draft_feet: number | null
          electrical_system_notes: string | null
          engine_brand: string | null
          engine_model: string | null
          engine_quantity: number | null
          engine_type: string | null
          hull_id_or_registration: string | null
          id: string
          inverter_charger_summary: string | null
          length_feet: number | null
          manufacturer: string | null
          marina_id: string | null
          model: string | null
          navigation_electronics_summary: string | null
          propulsion_type: string | null
          shore_power_type: string | null
          updated_at: string
          year: number | null
        }
        Insert: {
          active?: boolean
          battery_bank_summary?: string | null
          beam_feet?: number | null
          boat_name: string
          client_id: string
          created_at?: string
          current_dock_position?: string | null
          current_marina_name_snapshot?: string | null
          draft_feet?: number | null
          electrical_system_notes?: string | null
          engine_brand?: string | null
          engine_model?: string | null
          engine_quantity?: number | null
          engine_type?: string | null
          hull_id_or_registration?: string | null
          id?: string
          inverter_charger_summary?: string | null
          length_feet?: number | null
          manufacturer?: string | null
          marina_id?: string | null
          model?: string | null
          navigation_electronics_summary?: string | null
          propulsion_type?: string | null
          shore_power_type?: string | null
          updated_at?: string
          year?: number | null
        }
        Update: {
          active?: boolean
          battery_bank_summary?: string | null
          beam_feet?: number | null
          boat_name?: string
          client_id?: string
          created_at?: string
          current_dock_position?: string | null
          current_marina_name_snapshot?: string | null
          draft_feet?: number | null
          electrical_system_notes?: string | null
          engine_brand?: string | null
          engine_model?: string | null
          engine_quantity?: number | null
          engine_type?: string | null
          hull_id_or_registration?: string | null
          id?: string
          inverter_charger_summary?: string | null
          length_feet?: number | null
          manufacturer?: string | null
          marina_id?: string | null
          model?: string | null
          navigation_electronics_summary?: string | null
          propulsion_type?: string | null
          shore_power_type?: string | null
          updated_at?: string
          year?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "vessels_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vessels_marina_id_fkey"
            columns: ["marina_id"]
            isOneToOne: false
            referencedRelation: "marinas"
            referencedColumns: ["id"]
          },
        ]
      }
      whatsapp_blocked_numbers: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          phone_normalized: string
          reason: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          phone_normalized: string
          reason?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          phone_normalized?: string
          reason?: string | null
        }
        Relationships: []
      }
      whatsapp_conversation_assignments: {
        Row: {
          assigned_to: string | null
          notified_at: string | null
          phone_normalized: string
          updated_at: string
        }
        Insert: {
          assigned_to?: string | null
          notified_at?: string | null
          phone_normalized: string
          updated_at?: string
        }
        Update: {
          assigned_to?: string | null
          notified_at?: string | null
          phone_normalized?: string
          updated_at?: string
        }
        Relationships: []
      }
      whatsapp_leads: {
        Row: {
          assigned_to: string | null
          created_at: string
          display_name: string | null
          first_message: string | null
          id: string
          is_broadcast: boolean | null
          last_inbound_at: string | null
          last_message_at: string
          last_outbound_at: string | null
          linked_client_id: string | null
          message_count: number
          notes: string | null
          phone_normalized: string
          status: string
          unread_count: number | null
          updated_at: string
        }
        Insert: {
          assigned_to?: string | null
          created_at?: string
          display_name?: string | null
          first_message?: string | null
          id?: string
          is_broadcast?: boolean | null
          last_inbound_at?: string | null
          last_message_at?: string
          last_outbound_at?: string | null
          linked_client_id?: string | null
          message_count?: number
          notes?: string | null
          phone_normalized: string
          status?: string
          unread_count?: number | null
          updated_at?: string
        }
        Update: {
          assigned_to?: string | null
          created_at?: string
          display_name?: string | null
          first_message?: string | null
          id?: string
          is_broadcast?: boolean | null
          last_inbound_at?: string | null
          last_message_at?: string
          last_outbound_at?: string | null
          linked_client_id?: string | null
          message_count?: number
          notes?: string | null
          phone_normalized?: string
          status?: string
          unread_count?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "whatsapp_leads_linked_client_id_fkey"
            columns: ["linked_client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      whatsapp_messages: {
        Row: {
          body: string | null
          client_id: string | null
          created_at: string
          delivery_status: string | null
          direction: string
          id: string
          is_broadcast: boolean | null
          lead_id: string | null
          media_url: string | null
          message_type: string
          occurred_at: string
          phone_normalized: string
          raw_payload: Json | null
          sent_by: string | null
          service_order_id: string | null
          zapi_message_id: string | null
        }
        Insert: {
          body?: string | null
          client_id?: string | null
          created_at?: string
          delivery_status?: string | null
          direction: string
          id?: string
          is_broadcast?: boolean | null
          lead_id?: string | null
          media_url?: string | null
          message_type?: string
          occurred_at?: string
          phone_normalized: string
          raw_payload?: Json | null
          sent_by?: string | null
          service_order_id?: string | null
          zapi_message_id?: string | null
        }
        Update: {
          body?: string | null
          client_id?: string | null
          created_at?: string
          delivery_status?: string | null
          direction?: string
          id?: string
          is_broadcast?: boolean | null
          lead_id?: string | null
          media_url?: string | null
          message_type?: string
          occurred_at?: string
          phone_normalized?: string
          raw_payload?: Json | null
          sent_by?: string | null
          service_order_id?: string | null
          zapi_message_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "whatsapp_messages_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "whatsapp_messages_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: false
            referencedRelation: "whatsapp_leads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "whatsapp_messages_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      whatsapp_quick_replies: {
        Row: {
          active: boolean
          body: string
          created_at: string
          id: string
          shortcut: string
          sort_order: number | null
        }
        Insert: {
          active?: boolean
          body: string
          created_at?: string
          id?: string
          shortcut: string
          sort_order?: number | null
        }
        Update: {
          active?: boolean
          body?: string
          created_at?: string
          id?: string
          shortcut?: string
          sort_order?: number | null
        }
        Relationships: []
      }
      whatsapp_read_state: {
        Row: {
          last_read_at: string
          updated_at: string
          user_id: string
        }
        Insert: {
          last_read_at?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          last_read_at?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      whatsapp_scheduled_sends: {
        Row: {
          attempt_count: number
          auto_retry: boolean
          caption: string | null
          client_id: string | null
          context: string | null
          created_at: string
          created_by: string | null
          document_type: string | null
          id: string
          include_link_in_caption: boolean
          last_error: string | null
          last_response: Json | null
          last_run_at: string | null
          link_description: string | null
          link_title: string | null
          max_attempts: number
          message: string
          next_run_at: string
          pdf_filename: string | null
          phone: string
          receivable_id: string | null
          recurrence_day_of_month: number | null
          recurrence_days_of_week: number[] | null
          recurrence_end_date: string | null
          recurrence_type: string
          scheduled_at: string
          send_mode: string
          service_order_id: string | null
          status: string
          target_kind: string
          updated_at: string
        }
        Insert: {
          attempt_count?: number
          auto_retry?: boolean
          caption?: string | null
          client_id?: string | null
          context?: string | null
          created_at?: string
          created_by?: string | null
          document_type?: string | null
          id?: string
          include_link_in_caption?: boolean
          last_error?: string | null
          last_response?: Json | null
          last_run_at?: string | null
          link_description?: string | null
          link_title?: string | null
          max_attempts?: number
          message: string
          next_run_at: string
          pdf_filename?: string | null
          phone: string
          receivable_id?: string | null
          recurrence_day_of_month?: number | null
          recurrence_days_of_week?: number[] | null
          recurrence_end_date?: string | null
          recurrence_type?: string
          scheduled_at: string
          send_mode?: string
          service_order_id?: string | null
          status?: string
          target_kind: string
          updated_at?: string
        }
        Update: {
          attempt_count?: number
          auto_retry?: boolean
          caption?: string | null
          client_id?: string | null
          context?: string | null
          created_at?: string
          created_by?: string | null
          document_type?: string | null
          id?: string
          include_link_in_caption?: boolean
          last_error?: string | null
          last_response?: Json | null
          last_run_at?: string | null
          link_description?: string | null
          link_title?: string | null
          max_attempts?: number
          message?: string
          next_run_at?: string
          pdf_filename?: string | null
          phone?: string
          receivable_id?: string | null
          recurrence_day_of_month?: number | null
          recurrence_days_of_week?: number[] | null
          recurrence_end_date?: string | null
          recurrence_type?: string
          scheduled_at?: string
          send_mode?: string
          service_order_id?: string | null
          status?: string
          target_kind?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "whatsapp_scheduled_sends_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "whatsapp_scheduled_sends_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "whatsapp_scheduled_sends_receivable_id_fkey"
            columns: ["receivable_id"]
            isOneToOne: false
            referencedRelation: "receivables"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "whatsapp_scheduled_sends_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      whatsapp_send_queue: {
        Row: {
          attempts: number
          created_at: string
          failed_reason: string | null
          id: string
          max_attempts: number
          message: string
          phone_normalized: string
          priority: number
          processing_started_at: string | null
          scheduled_for: string
          sent_at: string | null
          source: string
          source_ref_id: string | null
          status: string
          updated_at: string
          zapi_message_id: string | null
        }
        Insert: {
          attempts?: number
          created_at?: string
          failed_reason?: string | null
          id?: string
          max_attempts?: number
          message: string
          phone_normalized: string
          priority?: number
          processing_started_at?: string | null
          scheduled_for?: string
          sent_at?: string | null
          source?: string
          source_ref_id?: string | null
          status?: string
          updated_at?: string
          zapi_message_id?: string | null
        }
        Update: {
          attempts?: number
          created_at?: string
          failed_reason?: string | null
          id?: string
          max_attempts?: number
          message?: string
          phone_normalized?: string
          priority?: number
          processing_started_at?: string | null
          scheduled_for?: string
          sent_at?: string | null
          source?: string
          source_ref_id?: string | null
          status?: string
          updated_at?: string
          zapi_message_id?: string | null
        }
        Relationships: []
      }
      whatsapp_templates: {
        Row: {
          active: boolean
          body: string
          category: string
          created_at: string
          id: string
          name: string
          sort_order: number
          updated_at: string
        }
        Insert: {
          active?: boolean
          body: string
          category?: string
          created_at?: string
          id?: string
          name: string
          sort_order?: number
          updated_at?: string
        }
        Update: {
          active?: boolean
          body?: string
          category?: string
          created_at?: string
          id?: string
          name?: string
          sort_order?: number
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      compute_next_run: {
        Args: {
          _day_of_month: number
          _days_of_week: number[]
          _from: string
          _recurrence_type: string
        }
        Returns: string
      }
      is_admin: { Args: { _user_id: string }; Returns: boolean }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
