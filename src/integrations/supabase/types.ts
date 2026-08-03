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
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      agenda_detector_exclusions: {
        Row: {
          created_at: string
          created_by: string | null
          label: string | null
          phone_normalized: string
          reason: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          label?: string | null
          phone_normalized: string
          reason?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          label?: string | null
          phone_normalized?: string
          reason?: string | null
        }
        Relationships: []
      }
      agenda_suggestions: {
        Row: {
          client_id: string | null
          confidence: number
          contact_label: string | null
          created_at: string
          created_task_id: string | null
          detector: string
          dismiss_reason: string | null
          evidence: string
          evidence_at: string | null
          id: string
          kind: string
          open_loop_id: string | null
          origin: string
          priority: string
          related_entity_id: string | null
          related_entity_type: string | null
          resolved_at: string | null
          resolved_by: string | null
          source_message_id: string | null
          source_phone: string | null
          status: string
          suggested_due_at: string | null
          suggested_start_at: string | null
          target_user_id: string | null
          title: string
        }
        Insert: {
          client_id?: string | null
          confidence: number
          contact_label?: string | null
          created_at?: string
          created_task_id?: string | null
          detector: string
          dismiss_reason?: string | null
          evidence: string
          evidence_at?: string | null
          id?: string
          kind?: string
          open_loop_id?: string | null
          origin?: string
          priority?: string
          related_entity_id?: string | null
          related_entity_type?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          source_message_id?: string | null
          source_phone?: string | null
          status?: string
          suggested_due_at?: string | null
          suggested_start_at?: string | null
          target_user_id?: string | null
          title: string
        }
        Update: {
          client_id?: string | null
          confidence?: number
          contact_label?: string | null
          created_at?: string
          created_task_id?: string | null
          detector?: string
          dismiss_reason?: string | null
          evidence?: string
          evidence_at?: string | null
          id?: string
          kind?: string
          open_loop_id?: string | null
          origin?: string
          priority?: string
          related_entity_id?: string | null
          related_entity_type?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          source_message_id?: string | null
          source_phone?: string | null
          status?: string
          suggested_due_at?: string | null
          suggested_start_at?: string | null
          target_user_id?: string | null
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "agenda_suggestions_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_suggestions_created_task_id_fkey"
            columns: ["created_task_id"]
            isOneToOne: false
            referencedRelation: "agenda_tasks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_suggestions_open_loop_id_fkey"
            columns: ["open_loop_id"]
            isOneToOne: false
            referencedRelation: "entity_open_loops"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_suggestions_resolved_by_fkey"
            columns: ["resolved_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_suggestions_source_message_id_fkey"
            columns: ["source_message_id"]
            isOneToOne: false
            referencedRelation: "whatsapp_messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_suggestions_target_user_id_fkey"
            columns: ["target_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      agenda_tasks: {
        Row: {
          all_day: boolean
          assignee_user_id: string | null
          automation_key: string | null
          checklist: Json
          client_id: string | null
          completed_at: string | null
          completed_by: string | null
          created_at: string
          created_by: string | null
          description: string | null
          due_at: string | null
          id: string
          is_private: boolean
          kind: string
          location: string | null
          notes: string | null
          origin_session_id: string | null
          priority: string
          recurrence_parent_id: string | null
          related_entity_id: string | null
          related_entity_type: string | null
          rrule: string | null
          scheduled_end_at: string | null
          scheduled_start_at: string | null
          snoozed_until: string | null
          source: string
          status: string
          title: string
          updated_at: string
        }
        Insert: {
          all_day?: boolean
          assignee_user_id?: string | null
          automation_key?: string | null
          checklist?: Json
          client_id?: string | null
          completed_at?: string | null
          completed_by?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          due_at?: string | null
          id?: string
          is_private?: boolean
          kind?: string
          location?: string | null
          notes?: string | null
          origin_session_id?: string | null
          priority?: string
          recurrence_parent_id?: string | null
          related_entity_id?: string | null
          related_entity_type?: string | null
          rrule?: string | null
          scheduled_end_at?: string | null
          scheduled_start_at?: string | null
          snoozed_until?: string | null
          source?: string
          status?: string
          title: string
          updated_at?: string
        }
        Update: {
          all_day?: boolean
          assignee_user_id?: string | null
          automation_key?: string | null
          checklist?: Json
          client_id?: string | null
          completed_at?: string | null
          completed_by?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          due_at?: string | null
          id?: string
          is_private?: boolean
          kind?: string
          location?: string | null
          notes?: string | null
          origin_session_id?: string | null
          priority?: string
          recurrence_parent_id?: string | null
          related_entity_id?: string | null
          related_entity_type?: string | null
          rrule?: string | null
          scheduled_end_at?: string | null
          scheduled_start_at?: string | null
          snoozed_until?: string | null
          source?: string
          status?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "agenda_tasks_assignee_user_id_fkey"
            columns: ["assignee_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_tasks_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_tasks_completed_by_fkey"
            columns: ["completed_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_tasks_recurrence_parent_id_fkey"
            columns: ["recurrence_parent_id"]
            isOneToOne: false
            referencedRelation: "agenda_tasks"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_agent_memory: {
        Row: {
          confidence: string
          created_at: string
          created_by_user_id: string | null
          entity_id: string | null
          entity_name: string | null
          id: string
          memory_key: string
          memory_value: string
          scope: string
          source: string | null
          updated_at: string
        }
        Insert: {
          confidence?: string
          created_at?: string
          created_by_user_id?: string | null
          entity_id?: string | null
          entity_name?: string | null
          id?: string
          memory_key: string
          memory_value: string
          scope: string
          source?: string | null
          updated_at?: string
        }
        Update: {
          confidence?: string
          created_at?: string
          created_by_user_id?: string | null
          entity_id?: string | null
          entity_name?: string | null
          id?: string
          memory_key?: string
          memory_value?: string
          scope?: string
          source?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      ai_agent_tasks: {
        Row: {
          created_at: string
          created_by_agent: boolean
          description: string
          due_at: string
          entity_id: string | null
          entity_number: string | null
          entity_type: string | null
          id: string
          metadata: Json
          priority: string
          status: string
          task_type: string
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by_agent?: boolean
          description: string
          due_at: string
          entity_id?: string | null
          entity_number?: string | null
          entity_type?: string | null
          id?: string
          metadata?: Json
          priority?: string
          status?: string
          task_type?: string
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by_agent?: boolean
          description?: string
          due_at?: string
          entity_id?: string | null
          entity_number?: string | null
          entity_type?: string | null
          id?: string
          metadata?: Json
          priority?: string
          status?: string
          task_type?: string
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      ai_business_alerts: {
        Row: {
          alert_type: string
          description: string
          entity_id: string | null
          entity_number: string | null
          entity_type: string | null
          first_seen_at: string
          id: string
          last_seen_at: string
          metadata: Json
          resolved_at: string | null
          severity: string
          title: string
        }
        Insert: {
          alert_type: string
          description: string
          entity_id?: string | null
          entity_number?: string | null
          entity_type?: string | null
          first_seen_at?: string
          id?: string
          last_seen_at?: string
          metadata?: Json
          resolved_at?: string | null
          severity?: string
          title: string
        }
        Update: {
          alert_type?: string
          description?: string
          entity_id?: string | null
          entity_number?: string | null
          entity_type?: string | null
          first_seen_at?: string
          id?: string
          last_seen_at?: string
          metadata?: Json
          resolved_at?: string | null
          severity?: string
          title?: string
        }
        Relationships: []
      }
      ai_comms_log: {
        Row: {
          audiencia: string | null
          block_code: string | null
          created_at: string
          entity_id: string | null
          entity_kind: string | null
          id: string
          message_preview: string | null
          phone: string | null
          reply_intent: string | null
          responded_at: string | null
          status: string
          tipo: string
        }
        Insert: {
          audiencia?: string | null
          block_code?: string | null
          created_at?: string
          entity_id?: string | null
          entity_kind?: string | null
          id?: string
          message_preview?: string | null
          phone?: string | null
          reply_intent?: string | null
          responded_at?: string | null
          status?: string
          tipo: string
        }
        Update: {
          audiencia?: string | null
          block_code?: string | null
          created_at?: string
          entity_id?: string | null
          entity_kind?: string | null
          id?: string
          message_preview?: string | null
          phone?: string | null
          reply_intent?: string | null
          responded_at?: string | null
          status?: string
          tipo?: string
        }
        Relationships: []
      }
      ai_correction_patterns: {
        Row: {
          client_id: string | null
          context: string
          corrected_value: string | null
          correction_type: string
          created_at: string
          entity_id: string | null
          entity_number: string | null
          entity_type: string | null
          id: string
          lesson_learned: string
          metadata: Json
          operator_user_id: string | null
          original_value: string | null
          scope: string
        }
        Insert: {
          client_id?: string | null
          context: string
          corrected_value?: string | null
          correction_type: string
          created_at?: string
          entity_id?: string | null
          entity_number?: string | null
          entity_type?: string | null
          id?: string
          lesson_learned: string
          metadata?: Json
          operator_user_id?: string | null
          original_value?: string | null
          scope?: string
        }
        Update: {
          client_id?: string | null
          context?: string
          corrected_value?: string | null
          correction_type?: string
          created_at?: string
          entity_id?: string | null
          entity_number?: string | null
          entity_type?: string | null
          id?: string
          lesson_learned?: string
          metadata?: Json
          operator_user_id?: string | null
          original_value?: string | null
          scope?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_correction_patterns_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_daily_briefings: {
        Row: {
          agenda_count: number
          critical_count: number
          date: string
          generated_at: string
          id: string
          sections: Json
          summary_text: string
          tasks_due_count: number
          warning_count: number
          whatsapp_sent: boolean
          whatsapp_sent_at: string | null
        }
        Insert: {
          agenda_count?: number
          critical_count?: number
          date: string
          generated_at?: string
          id?: string
          sections?: Json
          summary_text: string
          tasks_due_count?: number
          warning_count?: number
          whatsapp_sent?: boolean
          whatsapp_sent_at?: string | null
        }
        Update: {
          agenda_count?: number
          critical_count?: number
          date?: string
          generated_at?: string
          id?: string
          sections?: Json
          summary_text?: string
          tasks_due_count?: number
          warning_count?: number
          whatsapp_sent?: boolean
          whatsapp_sent_at?: string | null
        }
        Relationships: []
      }
      ai_inbound_sessions: {
        Row: {
          client_id: string | null
          created_at: string
          id: string
          last_intent: string | null
          messages: Json
          phone: string
          session_data: Json
          updated_at: string
        }
        Insert: {
          client_id?: string | null
          created_at?: string
          id?: string
          last_intent?: string | null
          messages?: Json
          phone: string
          session_data?: Json
          updated_at?: string
        }
        Update: {
          client_id?: string | null
          created_at?: string
          id?: string
          last_intent?: string | null
          messages?: Json
          phone?: string
          session_data?: Json
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_inbound_sessions_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_learned_routines: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          automation_payload: Json | null
          category: string
          created_at: string
          description: string | null
          evidence: string | null
          id: string
          last_observed_at: string
          observations: number
          pattern_key: string
          rejected_reason: string | null
          status: string
          suggested_automation: string | null
          title: string
          updated_at: string
          user_id: string | null
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          automation_payload?: Json | null
          category?: string
          created_at?: string
          description?: string | null
          evidence?: string | null
          id?: string
          last_observed_at?: string
          observations?: number
          pattern_key: string
          rejected_reason?: string | null
          status?: string
          suggested_automation?: string | null
          title: string
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          automation_payload?: Json | null
          category?: string
          created_at?: string
          description?: string | null
          evidence?: string | null
          id?: string
          last_observed_at?: string
          observations?: number
          pattern_key?: string
          rejected_reason?: string | null
          status?: string
          suggested_automation?: string | null
          title?: string
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_learned_routines_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_learned_routines_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_lifecycle_events: {
        Row: {
          created_at: string
          entity_id: string
          entity_number: string | null
          entity_type: string
          event_type: string
          id: string
          metadata: Json
          new_value: string | null
          old_value: string | null
        }
        Insert: {
          created_at?: string
          entity_id: string
          entity_number?: string | null
          entity_type?: string
          event_type: string
          id?: string
          metadata?: Json
          new_value?: string | null
          old_value?: string | null
        }
        Update: {
          created_at?: string
          entity_id?: string
          entity_number?: string | null
          entity_type?: string
          event_type?: string
          id?: string
          metadata?: Json
          new_value?: string | null
          old_value?: string | null
        }
        Relationships: []
      }
      ai_message_feedback: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          message_excerpt: string | null
          rating: string
          session_id: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          message_excerpt?: string | null
          rating: string
          session_id?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          message_excerpt?: string | null
          rating?: string
          session_id?: string | null
        }
        Relationships: []
      }
      ai_operator_alerts_log: {
        Row: {
          alert_key: string
          channel: string
          created_at: string
          id: string
          meta: Json | null
        }
        Insert: {
          alert_key: string
          channel?: string
          created_at?: string
          id?: string
          meta?: Json | null
        }
        Update: {
          alert_key?: string
          channel?: string
          created_at?: string
          id?: string
          meta?: Json | null
        }
        Relationships: []
      }
      ai_operator_audit: {
        Row: {
          actor_kind: string
          actor_user_id: string | null
          created_at: string
          draft_id: string | null
          event_category: string
          event_type: string
          id: string
          payload: Json
          pending_action_id: string | null
          session_id: string | null
        }
        Insert: {
          actor_kind: string
          actor_user_id?: string | null
          created_at?: string
          draft_id?: string | null
          event_category?: string
          event_type: string
          id?: string
          payload?: Json
          pending_action_id?: string | null
          session_id?: string | null
        }
        Update: {
          actor_kind?: string
          actor_user_id?: string | null
          created_at?: string
          draft_id?: string | null
          event_category?: string
          event_type?: string
          id?: string
          payload?: Json
          pending_action_id?: string | null
          session_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_operator_audit_actor_user_id_fkey"
            columns: ["actor_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_audit_draft_id_fkey"
            columns: ["draft_id"]
            isOneToOne: false
            referencedRelation: "ai_operator_drafts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_audit_pending_action_id_fkey"
            columns: ["pending_action_id"]
            isOneToOne: false
            referencedRelation: "ai_operator_pending_actions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_audit_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "ai_operator_sessions"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_operator_channel_events: {
        Row: {
          attempts: number
          channel: string
          created_at: string
          direction: string
          draft_id: string | null
          external_event_id: string | null
          external_thread_key: string | null
          id: string
          last_error: string | null
          payload: Json
          processed_at: string | null
          provider: string
          session_id: string | null
          status: string
        }
        Insert: {
          attempts?: number
          channel: string
          created_at?: string
          direction?: string
          draft_id?: string | null
          external_event_id?: string | null
          external_thread_key?: string | null
          id?: string
          last_error?: string | null
          payload: Json
          processed_at?: string | null
          provider: string
          session_id?: string | null
          status?: string
        }
        Update: {
          attempts?: number
          channel?: string
          created_at?: string
          direction?: string
          draft_id?: string | null
          external_event_id?: string | null
          external_thread_key?: string | null
          id?: string
          last_error?: string | null
          payload?: Json
          processed_at?: string | null
          provider?: string
          session_id?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_operator_channel_events_draft_id_fkey"
            columns: ["draft_id"]
            isOneToOne: false
            referencedRelation: "ai_operator_drafts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_channel_events_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "ai_operator_sessions"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_operator_draft_items: {
        Row: {
          confidence: string | null
          created_at: string
          description: string
          draft_id: string
          estimated_total: number | null
          id: string
          item_kind: string
          metadata: Json
          notes: string | null
          position: number
          product_id: string | null
          quantity: number | null
          service_id: string | null
          source_reference: string | null
          unit: string | null
          unit_price: number | null
        }
        Insert: {
          confidence?: string | null
          created_at?: string
          description: string
          draft_id: string
          estimated_total?: number | null
          id?: string
          item_kind: string
          metadata?: Json
          notes?: string | null
          position?: number
          product_id?: string | null
          quantity?: number | null
          service_id?: string | null
          source_reference?: string | null
          unit?: string | null
          unit_price?: number | null
        }
        Update: {
          confidence?: string | null
          created_at?: string
          description?: string
          draft_id?: string
          estimated_total?: number | null
          id?: string
          item_kind?: string
          metadata?: Json
          notes?: string | null
          position?: number
          product_id?: string | null
          quantity?: number | null
          service_id?: string | null
          source_reference?: string | null
          unit?: string | null
          unit_price?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_operator_draft_items_draft_id_fkey"
            columns: ["draft_id"]
            isOneToOne: false
            referencedRelation: "ai_operator_drafts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_draft_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "product_availability"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_draft_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_draft_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_entradas_pendentes"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "ai_operator_draft_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_variancia"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "ai_operator_draft_items_service_id_fkey"
            columns: ["service_id"]
            isOneToOne: false
            referencedRelation: "services"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_operator_drafts: {
        Row: {
          client_id: string | null
          converted_service_order_id: string | null
          created_at: string
          created_by: string | null
          estimated_labor_hours: number | null
          estimated_labor_value: number | null
          estimated_parts_value: number | null
          estimated_total: number | null
          estimated_travel_value: number | null
          hypotheses: Json
          id: string
          interpreted_category: string | null
          interpreted_intent: string | null
          kind: string
          metadata: Json
          next_steps: Json
          pending_questions: Json
          service_order_id: string | null
          session_id: string | null
          status: string
          summary: string | null
          title: string | null
          updated_at: string
          vessel_id: string | null
        }
        Insert: {
          client_id?: string | null
          converted_service_order_id?: string | null
          created_at?: string
          created_by?: string | null
          estimated_labor_hours?: number | null
          estimated_labor_value?: number | null
          estimated_parts_value?: number | null
          estimated_total?: number | null
          estimated_travel_value?: number | null
          hypotheses?: Json
          id?: string
          interpreted_category?: string | null
          interpreted_intent?: string | null
          kind: string
          metadata?: Json
          next_steps?: Json
          pending_questions?: Json
          service_order_id?: string | null
          session_id?: string | null
          status?: string
          summary?: string | null
          title?: string | null
          updated_at?: string
          vessel_id?: string | null
        }
        Update: {
          client_id?: string | null
          converted_service_order_id?: string | null
          created_at?: string
          created_by?: string | null
          estimated_labor_hours?: number | null
          estimated_labor_value?: number | null
          estimated_parts_value?: number | null
          estimated_total?: number | null
          estimated_travel_value?: number | null
          hypotheses?: Json
          id?: string
          interpreted_category?: string | null
          interpreted_intent?: string | null
          kind?: string
          metadata?: Json
          next_steps?: Json
          pending_questions?: Json
          service_order_id?: string | null
          session_id?: string | null
          status?: string
          summary?: string | null
          title?: string | null
          updated_at?: string
          vessel_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_operator_drafts_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_drafts_converted_service_order_id_fkey"
            columns: ["converted_service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_drafts_converted_service_order_id_fkey"
            columns: ["converted_service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_drafts_converted_service_order_id_fkey"
            columns: ["converted_service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_drafts_converted_service_order_id_fkey"
            columns: ["converted_service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
          {
            foreignKeyName: "ai_operator_drafts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_drafts_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_drafts_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_drafts_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_drafts_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
          {
            foreignKeyName: "ai_operator_drafts_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "ai_operator_sessions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_drafts_vessel_id_fkey"
            columns: ["vessel_id"]
            isOneToOne: false
            referencedRelation: "vessels"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_operator_memory_notes: {
        Row: {
          body: string
          client_id: string | null
          confidence: string
          created_at: string
          created_by: string | null
          draft_id: string | null
          id: string
          rejected_at: string | null
          rejected_by: string | null
          scope: string
          source: string
          source_reference: string | null
          supplier_id: string | null
          title: string
          topic: string
          updated_at: string
          verification_status: string
          verified_at: string | null
          verified_by: string | null
          vessel_id: string | null
        }
        Insert: {
          body: string
          client_id?: string | null
          confidence?: string
          created_at?: string
          created_by?: string | null
          draft_id?: string | null
          id?: string
          rejected_at?: string | null
          rejected_by?: string | null
          scope?: string
          source?: string
          source_reference?: string | null
          supplier_id?: string | null
          title: string
          topic: string
          updated_at?: string
          verification_status?: string
          verified_at?: string | null
          verified_by?: string | null
          vessel_id?: string | null
        }
        Update: {
          body?: string
          client_id?: string | null
          confidence?: string
          created_at?: string
          created_by?: string | null
          draft_id?: string | null
          id?: string
          rejected_at?: string | null
          rejected_by?: string | null
          scope?: string
          source?: string
          source_reference?: string | null
          supplier_id?: string | null
          title?: string
          topic?: string
          updated_at?: string
          verification_status?: string
          verified_at?: string | null
          verified_by?: string | null
          vessel_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_operator_memory_notes_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_memory_notes_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_memory_notes_draft_id_fkey"
            columns: ["draft_id"]
            isOneToOne: false
            referencedRelation: "ai_operator_drafts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_memory_notes_rejected_by_fkey"
            columns: ["rejected_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_memory_notes_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_memory_notes_verified_by_fkey"
            columns: ["verified_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_memory_notes_vessel_id_fkey"
            columns: ["vessel_id"]
            isOneToOne: false
            referencedRelation: "vessels"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_operator_messages: {
        Row: {
          attachments: Json | null
          cache_read_tokens: number | null
          content: string | null
          created_at: string
          id: string
          model: string | null
          role: string
          session_id: string
          source: string | null
          source_message_id: string | null
          tokens_in: number | null
          tokens_out: number | null
          tool_call_id: string | null
          tool_calls: Json | null
          tool_name: string | null
        }
        Insert: {
          attachments?: Json | null
          cache_read_tokens?: number | null
          content?: string | null
          created_at?: string
          id?: string
          model?: string | null
          role: string
          session_id: string
          source?: string | null
          source_message_id?: string | null
          tokens_in?: number | null
          tokens_out?: number | null
          tool_call_id?: string | null
          tool_calls?: Json | null
          tool_name?: string | null
        }
        Update: {
          attachments?: Json | null
          cache_read_tokens?: number | null
          content?: string | null
          created_at?: string
          id?: string
          model?: string | null
          role?: string
          session_id?: string
          source?: string | null
          source_message_id?: string | null
          tokens_in?: number | null
          tokens_out?: number | null
          tool_call_id?: string | null
          tool_calls?: Json | null
          tool_name?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_operator_messages_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "ai_operator_sessions"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_operator_pending_actions: {
        Row: {
          action_name: string
          approved_at: string | null
          approved_by_user_id: string | null
          created_at: string
          draft_id: string | null
          executed_at: string | null
          expires_at: string | null
          id: string
          payload: Json
          rejected_at: string | null
          rejected_by_user_id: string | null
          requested_by_user_id: string | null
          result: Json | null
          risk_level: string
          risk_reason: string | null
          session_id: string | null
          status: string
          summary: string | null
          title: string | null
        }
        Insert: {
          action_name: string
          approved_at?: string | null
          approved_by_user_id?: string | null
          created_at?: string
          draft_id?: string | null
          executed_at?: string | null
          expires_at?: string | null
          id?: string
          payload: Json
          rejected_at?: string | null
          rejected_by_user_id?: string | null
          requested_by_user_id?: string | null
          result?: Json | null
          risk_level?: string
          risk_reason?: string | null
          session_id?: string | null
          status?: string
          summary?: string | null
          title?: string | null
        }
        Update: {
          action_name?: string
          approved_at?: string | null
          approved_by_user_id?: string | null
          created_at?: string
          draft_id?: string | null
          executed_at?: string | null
          expires_at?: string | null
          id?: string
          payload?: Json
          rejected_at?: string | null
          rejected_by_user_id?: string | null
          requested_by_user_id?: string | null
          result?: Json | null
          risk_level?: string
          risk_reason?: string | null
          session_id?: string | null
          status?: string
          summary?: string | null
          title?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_operator_pending_actions_approved_by_user_id_fkey"
            columns: ["approved_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_pending_actions_draft_id_fkey"
            columns: ["draft_id"]
            isOneToOne: false
            referencedRelation: "ai_operator_drafts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_pending_actions_rejected_by_user_id_fkey"
            columns: ["rejected_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_pending_actions_requested_by_user_id_fkey"
            columns: ["requested_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_pending_actions_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "ai_operator_sessions"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_operator_sessions: {
        Row: {
          channel: string
          channel_provider: string | null
          client_id: string | null
          created_at: string
          external_thread_key: string | null
          id: string
          last_activity_at: string
          metadata: Json
          owner_user_id: string | null
          service_order_id: string | null
          status: string
          updated_at: string
          vessel_id: string | null
        }
        Insert: {
          channel: string
          channel_provider?: string | null
          client_id?: string | null
          created_at?: string
          external_thread_key?: string | null
          id?: string
          last_activity_at?: string
          metadata?: Json
          owner_user_id?: string | null
          service_order_id?: string | null
          status?: string
          updated_at?: string
          vessel_id?: string | null
        }
        Update: {
          channel?: string
          channel_provider?: string | null
          client_id?: string | null
          created_at?: string
          external_thread_key?: string | null
          id?: string
          last_activity_at?: string
          metadata?: Json
          owner_user_id?: string | null
          service_order_id?: string | null
          status?: string
          updated_at?: string
          vessel_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_operator_sessions_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_sessions_owner_user_id_fkey"
            columns: ["owner_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_sessions_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_sessions_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_sessions_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_operator_sessions_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
          {
            foreignKeyName: "ai_operator_sessions_vessel_id_fkey"
            columns: ["vessel_id"]
            isOneToOne: false
            referencedRelation: "vessels"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_suggestion_reviews: {
        Row: {
          ai_model: string | null
          approved: Json | null
          change_summary: string | null
          id: string
          prompt_version: string | null
          reviewed_at: string
          reviewer_id: string | null
          service_id: string | null
          suggested: Json
          suggestion_type: string
          target_id: string | null
          target_table: string
          verdict: string
        }
        Insert: {
          ai_model?: string | null
          approved?: Json | null
          change_summary?: string | null
          id?: string
          prompt_version?: string | null
          reviewed_at?: string
          reviewer_id?: string | null
          service_id?: string | null
          suggested: Json
          suggestion_type: string
          target_id?: string | null
          target_table: string
          verdict: string
        }
        Update: {
          ai_model?: string | null
          approved?: Json | null
          change_summary?: string | null
          id?: string
          prompt_version?: string | null
          reviewed_at?: string
          reviewer_id?: string | null
          service_id?: string | null
          suggested?: Json
          suggestion_type?: string
          target_id?: string | null
          target_table?: string
          verdict?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_suggestion_reviews_reviewer_id_fkey"
            columns: ["reviewer_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_suggestion_reviews_service_id_fkey"
            columns: ["service_id"]
            isOneToOne: false
            referencedRelation: "services"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_workflows: {
        Row: {
          client_id: string | null
          context: Json
          created_at: string
          current_step: string
          entity_id: string
          entity_number: string | null
          entity_type: string
          id: string
          next_action_at: string | null
          status: string
          steps_completed: string[]
          updated_at: string
          workflow_type: string
        }
        Insert: {
          client_id?: string | null
          context?: Json
          created_at?: string
          current_step: string
          entity_id: string
          entity_number?: string | null
          entity_type?: string
          id?: string
          next_action_at?: string | null
          status?: string
          steps_completed?: string[]
          updated_at?: string
          workflow_type: string
        }
        Update: {
          client_id?: string | null
          context?: Json
          created_at?: string
          current_step?: string
          entity_id?: string
          entity_number?: string | null
          entity_type?: string
          id?: string
          next_action_at?: string | null
          status?: string
          steps_completed?: string[]
          updated_at?: string
          workflow_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_workflows_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      api_references: {
        Row: {
          category: string
          created_at: string | null
          description: string | null
          endpoint_name: string
          http_method: string
          id: string
          is_implemented: boolean | null
          path: string
          payload_example: Json | null
          provider: string
          updated_at: string | null
        }
        Insert: {
          category: string
          created_at?: string | null
          description?: string | null
          endpoint_name: string
          http_method?: string
          id?: string
          is_implemented?: boolean | null
          path: string
          payload_example?: Json | null
          provider: string
          updated_at?: string | null
        }
        Update: {
          category?: string
          created_at?: string | null
          description?: string | null
          endpoint_name?: string
          http_method?: string
          id?: string
          is_implemented?: boolean | null
          path?: string
          payload_example?: Json | null
          provider?: string
          updated_at?: string | null
        }
        Relationships: []
      }
      app_error_logs: {
        Row: {
          action: string | null
          context: string | null
          details: Json | null
          fingerprint: string
          first_seen_at: string
          id: string
          last_seen_at: string
          level: string
          message: string
          occurrences: number
          resolved_at: string | null
          source: string
          user_agent: string | null
          user_email: string | null
          user_id: string | null
        }
        Insert: {
          action?: string | null
          context?: string | null
          details?: Json | null
          fingerprint: string
          first_seen_at?: string
          id?: string
          last_seen_at?: string
          level?: string
          message: string
          occurrences?: number
          resolved_at?: string | null
          source: string
          user_agent?: string | null
          user_email?: string | null
          user_id?: string | null
        }
        Update: {
          action?: string | null
          context?: string | null
          details?: Json | null
          fingerprint?: string
          first_seen_at?: string
          id?: string
          last_seen_at?: string
          level?: string
          message?: string
          occurrences?: number
          resolved_at?: string | null
          source?: string
          user_agent?: string | null
          user_email?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      app_notifications: {
        Row: {
          body: string | null
          created_at: string
          id: string
          navigate_to: string | null
          read_at: string | null
          title: string
          type: string
          user_id: string
        }
        Insert: {
          body?: string | null
          created_at?: string
          id?: string
          navigate_to?: string | null
          read_at?: string | null
          title: string
          type: string
          user_id: string
        }
        Update: {
          body?: string | null
          created_at?: string
          id?: string
          navigate_to?: string | null
          read_at?: string | null
          title?: string
          type?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "app_notifications_user_id_fkey"
            columns: ["user_id"]
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
          ai_whatsapp_enabled: boolean
          ai_whatsapp_pin_hash: string | null
          avatar_url: string | null
          birth_date: string | null
          city: string | null
          country: string | null
          cpf: string | null
          created_at: string
          department: string | null
          email: string
          emergency_contact_name: string | null
          emergency_contact_phone: string | null
          full_name: string
          hiring_date: string | null
          id: string
          metadata: Json | null
          neighborhood: string | null
          notes: string | null
          phone: string | null
          phone_normalized: string | null
          pix_key: string | null
          postal_code: string | null
          resignation_date: string | null
          rg: string | null
          role: string
          salary_base: number | null
          state: string | null
          updated_at: string
        }
        Insert: {
          active?: boolean
          address_complement?: string | null
          address_line_1?: string | null
          address_number?: string | null
          ai_whatsapp_enabled?: boolean
          ai_whatsapp_pin_hash?: string | null
          avatar_url?: string | null
          birth_date?: string | null
          city?: string | null
          country?: string | null
          cpf?: string | null
          created_at?: string
          department?: string | null
          email: string
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          full_name: string
          hiring_date?: string | null
          id: string
          metadata?: Json | null
          neighborhood?: string | null
          notes?: string | null
          phone?: string | null
          phone_normalized?: string | null
          pix_key?: string | null
          postal_code?: string | null
          resignation_date?: string | null
          rg?: string | null
          role: string
          salary_base?: number | null
          state?: string | null
          updated_at?: string
        }
        Update: {
          active?: boolean
          address_complement?: string | null
          address_line_1?: string | null
          address_number?: string | null
          ai_whatsapp_enabled?: boolean
          ai_whatsapp_pin_hash?: string | null
          avatar_url?: string | null
          birth_date?: string | null
          city?: string | null
          country?: string | null
          cpf?: string | null
          created_at?: string
          department?: string | null
          email?: string
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          full_name?: string
          hiring_date?: string | null
          id?: string
          metadata?: Json | null
          neighborhood?: string | null
          notes?: string | null
          phone?: string | null
          phone_normalized?: string | null
          pix_key?: string | null
          postal_code?: string | null
          resignation_date?: string | null
          rg?: string | null
          role?: string
          salary_base?: number | null
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
      bank_charges: {
        Row: {
          amount: number
          barcode: string | null
          client_id: string | null
          created_at: string
          created_by: string | null
          digitable_line: string | null
          due_date: string | null
          error_message: string | null
          id: string
          kind: string
          paid_amount: number | null
          paid_at: string | null
          pdf_url: string | null
          pix_copy_paste: string | null
          pix_end_to_end_id: string | null
          pix_qr_base64: string | null
          provider: string
          provider_charge_id: string | null
          raw: Json | null
          receivable_id: string | null
          service_order_id: string | null
          status: string
          updated_at: string
        }
        Insert: {
          amount: number
          barcode?: string | null
          client_id?: string | null
          created_at?: string
          created_by?: string | null
          digitable_line?: string | null
          due_date?: string | null
          error_message?: string | null
          id?: string
          kind: string
          paid_amount?: number | null
          paid_at?: string | null
          pdf_url?: string | null
          pix_copy_paste?: string | null
          pix_end_to_end_id?: string | null
          pix_qr_base64?: string | null
          provider: string
          provider_charge_id?: string | null
          raw?: Json | null
          receivable_id?: string | null
          service_order_id?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          amount?: number
          barcode?: string | null
          client_id?: string | null
          created_at?: string
          created_by?: string | null
          digitable_line?: string | null
          due_date?: string | null
          error_message?: string | null
          id?: string
          kind?: string
          paid_amount?: number | null
          paid_at?: string | null
          pdf_url?: string | null
          pix_copy_paste?: string | null
          pix_end_to_end_id?: string | null
          pix_qr_base64?: string | null
          provider?: string
          provider_charge_id?: string | null
          raw?: Json | null
          receivable_id?: string | null
          service_order_id?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "bank_charges_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_charges_receivable_id_fkey"
            columns: ["receivable_id"]
            isOneToOne: false
            referencedRelation: "receivables"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_charges_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_charges_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_charges_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_charges_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
        ]
      }
      bank_connections: {
        Row: {
          account_kind: string
          active: boolean
          created_at: string
          external_id: string
          id: string
          institution: string | null
          label: string
          last_sync_imported: number | null
          last_sync_message: string | null
          last_sync_status: string | null
          last_synced_at: string | null
          last_transaction_date: string | null
          provider: string
          updated_at: string
        }
        Insert: {
          account_kind?: string
          active?: boolean
          created_at?: string
          external_id: string
          id?: string
          institution?: string | null
          label: string
          last_sync_imported?: number | null
          last_sync_message?: string | null
          last_sync_status?: string | null
          last_synced_at?: string | null
          last_transaction_date?: string | null
          provider?: string
          updated_at?: string
        }
        Update: {
          account_kind?: string
          active?: boolean
          created_at?: string
          external_id?: string
          id?: string
          institution?: string | null
          label?: string
          last_sync_imported?: number | null
          last_sync_message?: string | null
          last_sync_status?: string | null
          last_synced_at?: string | null
          last_transaction_date?: string | null
          provider?: string
          updated_at?: string
        }
        Relationships: []
      }
      bank_transactions: {
        Row: {
          amount: number
          balance_after: number | null
          bank_connection_id: string | null
          bank_ref_id: string | null
          counterparty_account: string | null
          counterparty_bank: string | null
          counterparty_branch: string | null
          counterparty_document: string | null
          counterparty_name: string | null
          created_at: string | null
          description: string
          dismissed_reason: string | null
          id: string
          import_batch_id: string | null
          installment_label: string | null
          merchant_document: string | null
          merchant_name: string | null
          payment_method: string | null
          payment_reason: string | null
          pix_end_to_end_id: string | null
          provider: string
          reconciled: boolean | null
          reconciled_payment_id: string | null
          reconciled_service_order_id: string | null
          source_type: string
          transaction_date: string
          transaction_type: string
        }
        Insert: {
          amount: number
          balance_after?: number | null
          bank_connection_id?: string | null
          bank_ref_id?: string | null
          counterparty_account?: string | null
          counterparty_bank?: string | null
          counterparty_branch?: string | null
          counterparty_document?: string | null
          counterparty_name?: string | null
          created_at?: string | null
          description: string
          dismissed_reason?: string | null
          id?: string
          import_batch_id?: string | null
          installment_label?: string | null
          merchant_document?: string | null
          merchant_name?: string | null
          payment_method?: string | null
          payment_reason?: string | null
          pix_end_to_end_id?: string | null
          provider?: string
          reconciled?: boolean | null
          reconciled_payment_id?: string | null
          reconciled_service_order_id?: string | null
          source_type?: string
          transaction_date: string
          transaction_type: string
        }
        Update: {
          amount?: number
          balance_after?: number | null
          bank_connection_id?: string | null
          bank_ref_id?: string | null
          counterparty_account?: string | null
          counterparty_bank?: string | null
          counterparty_branch?: string | null
          counterparty_document?: string | null
          counterparty_name?: string | null
          created_at?: string | null
          description?: string
          dismissed_reason?: string | null
          id?: string
          import_batch_id?: string | null
          installment_label?: string | null
          merchant_document?: string | null
          merchant_name?: string | null
          payment_method?: string | null
          payment_reason?: string | null
          pix_end_to_end_id?: string | null
          provider?: string
          reconciled?: boolean | null
          reconciled_payment_id?: string | null
          reconciled_service_order_id?: string | null
          source_type?: string
          transaction_date?: string
          transaction_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "bank_transactions_bank_connection_id_fkey"
            columns: ["bank_connection_id"]
            isOneToOne: false
            referencedRelation: "bank_connections"
            referencedColumns: ["id"]
          },
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
          {
            foreignKeyName: "bank_transactions_reconciled_service_order_id_fkey"
            columns: ["reconciled_service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_transactions_reconciled_service_order_id_fkey"
            columns: ["reconciled_service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_transactions_reconciled_service_order_id_fkey"
            columns: ["reconciled_service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
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
          address_complement: string | null
          address_line_1: string | null
          address_line_2: string | null
          address_number: string | null
          city: string | null
          communication_tone: string | null
          country: string | null
          cpf_cnpj: string | null
          created_at: string
          display_name: string | null
          email: string | null
          id: string
          ie_indicator: number | null
          name: string
          neighborhood: string | null
          notes: string | null
          opt_out_whatsapp: boolean
          phone: string | null
          postal_code: string | null
          state: string | null
          state_registration: string | null
          type: string
          updated_at: string
          whatsapp: string | null
        }
        Insert: {
          active?: boolean
          address_complement?: string | null
          address_line_1?: string | null
          address_line_2?: string | null
          address_number?: string | null
          city?: string | null
          communication_tone?: string | null
          country?: string | null
          cpf_cnpj?: string | null
          created_at?: string
          display_name?: string | null
          email?: string | null
          id?: string
          ie_indicator?: number | null
          name: string
          neighborhood?: string | null
          notes?: string | null
          opt_out_whatsapp?: boolean
          phone?: string | null
          postal_code?: string | null
          state?: string | null
          state_registration?: string | null
          type: string
          updated_at?: string
          whatsapp?: string | null
        }
        Update: {
          active?: boolean
          address_complement?: string | null
          address_line_1?: string | null
          address_line_2?: string | null
          address_number?: string | null
          city?: string | null
          communication_tone?: string | null
          country?: string | null
          cpf_cnpj?: string | null
          created_at?: string
          display_name?: string | null
          email?: string | null
          id?: string
          ie_indicator?: number | null
          name?: string
          neighborhood?: string | null
          notes?: string | null
          opt_out_whatsapp?: boolean
          phone?: string | null
          postal_code?: string | null
          state?: string | null
          state_registration?: string | null
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
          phone: string | null
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
          phone?: string | null
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
          phone?: string | null
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
          {
            foreignKeyName: "collections_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "collections_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "collections_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
        ]
      }
      commissions: {
        Row: {
          amount: number
          base_value: number | null
          created_at: string | null
          id: string
          paid_at: string | null
          payable_id: string | null
          percentage: number | null
          service_order_id: string | null
          status: string | null
          updated_at: string | null
          user_id: string | null
        }
        Insert: {
          amount: number
          base_value?: number | null
          created_at?: string | null
          id?: string
          paid_at?: string | null
          payable_id?: string | null
          percentage?: number | null
          service_order_id?: string | null
          status?: string | null
          updated_at?: string | null
          user_id?: string | null
        }
        Update: {
          amount?: number
          base_value?: number | null
          created_at?: string | null
          id?: string
          paid_at?: string | null
          payable_id?: string | null
          percentage?: number | null
          service_order_id?: string | null
          status?: string | null
          updated_at?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "commissions_payable_id_fkey"
            columns: ["payable_id"]
            isOneToOne: false
            referencedRelation: "payables"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "commissions_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "commissions_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "commissions_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "commissions_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
          {
            foreignKeyName: "commissions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      company_fiscal_settings: {
        Row: {
          active_environment: string
          city_name: string | null
          cnpj: string | null
          complement: string | null
          contora_template_id: string | null
          created_at: string | null
          crt: number
          district: string | null
          ibge_city_code: string | null
          id: string
          legal_name: string | null
          municipal_registration: string | null
          nfe_series_producao: number
          number: string | null
          postal_code: string | null
          provider: string
          singleton_guard: boolean
          state_code: string | null
          state_registration: string | null
          street: string | null
          tax_regime: string
          trade_name: string | null
          updated_at: string | null
        }
        Insert: {
          active_environment?: string
          city_name?: string | null
          cnpj?: string | null
          complement?: string | null
          contora_template_id?: string | null
          created_at?: string | null
          crt?: number
          district?: string | null
          ibge_city_code?: string | null
          id?: string
          legal_name?: string | null
          municipal_registration?: string | null
          nfe_series_producao?: number
          number?: string | null
          postal_code?: string | null
          provider?: string
          singleton_guard?: boolean
          state_code?: string | null
          state_registration?: string | null
          street?: string | null
          tax_regime?: string
          trade_name?: string | null
          updated_at?: string | null
        }
        Update: {
          active_environment?: string
          city_name?: string | null
          cnpj?: string | null
          complement?: string | null
          contora_template_id?: string | null
          created_at?: string | null
          crt?: number
          district?: string | null
          ibge_city_code?: string | null
          id?: string
          legal_name?: string | null
          municipal_registration?: string | null
          nfe_series_producao?: number
          number?: string | null
          postal_code?: string | null
          provider?: string
          singleton_guard?: boolean
          state_code?: string | null
          state_registration?: string | null
          street?: string | null
          tax_regime?: string
          trade_name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      cost_centers: {
        Row: {
          active: boolean | null
          created_at: string | null
          id: string
          name: string
          parent_id: string | null
          type: string
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          created_at?: string | null
          id?: string
          name: string
          parent_id?: string | null
          type: string
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          created_at?: string | null
          id?: string
          name?: string
          parent_id?: string | null
          type?: string
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "cost_centers_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "cost_centers"
            referencedColumns: ["id"]
          },
        ]
      }
      entity_open_loops: {
        Row: {
          created_at: string
          detail: string | null
          due_at: string | null
          entity_id: string
          entity_type: string
          evidence: string | null
          evidence_at: string | null
          id: string
          kind: string
          last_seen_at: string
          loop_key: string
          mentions: number
          opened_at: string
          priority: string
          ref_id: string | null
          ref_table: string | null
          resolved_at: string | null
          resolved_reason: string | null
          service_order_id: string | null
          source: string
          source_message_id: string | null
          status: string
          task_id: string | null
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          detail?: string | null
          due_at?: string | null
          entity_id: string
          entity_type: string
          evidence?: string | null
          evidence_at?: string | null
          id?: string
          kind: string
          last_seen_at?: string
          loop_key: string
          mentions?: number
          opened_at?: string
          priority?: string
          ref_id?: string | null
          ref_table?: string | null
          resolved_at?: string | null
          resolved_reason?: string | null
          service_order_id?: string | null
          source: string
          source_message_id?: string | null
          status?: string
          task_id?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          detail?: string | null
          due_at?: string | null
          entity_id?: string
          entity_type?: string
          evidence?: string | null
          evidence_at?: string | null
          id?: string
          kind?: string
          last_seen_at?: string
          loop_key?: string
          mentions?: number
          opened_at?: string
          priority?: string
          ref_id?: string | null
          ref_table?: string | null
          resolved_at?: string | null
          resolved_reason?: string | null
          service_order_id?: string | null
          source?: string
          source_message_id?: string | null
          status?: string
          task_id?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "entity_open_loops_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "entity_open_loops_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "entity_open_loops_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "entity_open_loops_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
          {
            foreignKeyName: "entity_open_loops_task_id_fkey"
            columns: ["task_id"]
            isOneToOne: false
            referencedRelation: "agenda_tasks"
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
      external_quote_leads: {
        Row: {
          address_line_1: string | null
          address_line_2: string | null
          boat_length_feet: number | null
          boat_manufacturer: string | null
          boat_model: string | null
          boat_name: string | null
          boat_year: number | null
          city: string | null
          country: string | null
          cpf_cnpj: string | null
          created_at: string
          created_by: string
          email: string | null
          id: string
          marina_name: string | null
          name: string
          notes: string | null
          phone: string | null
          postal_code: string | null
          promoted_at: string | null
          promoted_client_id: string | null
          state: string | null
          type: string
          updated_at: string
          whatsapp: string | null
        }
        Insert: {
          address_line_1?: string | null
          address_line_2?: string | null
          boat_length_feet?: number | null
          boat_manufacturer?: string | null
          boat_model?: string | null
          boat_name?: string | null
          boat_year?: number | null
          city?: string | null
          country?: string | null
          cpf_cnpj?: string | null
          created_at?: string
          created_by: string
          email?: string | null
          id?: string
          marina_name?: string | null
          name: string
          notes?: string | null
          phone?: string | null
          postal_code?: string | null
          promoted_at?: string | null
          promoted_client_id?: string | null
          state?: string | null
          type?: string
          updated_at?: string
          whatsapp?: string | null
        }
        Update: {
          address_line_1?: string | null
          address_line_2?: string | null
          boat_length_feet?: number | null
          boat_manufacturer?: string | null
          boat_model?: string | null
          boat_name?: string | null
          boat_year?: number | null
          city?: string | null
          country?: string | null
          cpf_cnpj?: string | null
          created_at?: string
          created_by?: string
          email?: string | null
          id?: string
          marina_name?: string | null
          name?: string
          notes?: string | null
          phone?: string | null
          postal_code?: string | null
          promoted_at?: string | null
          promoted_client_id?: string | null
          state?: string | null
          type?: string
          updated_at?: string
          whatsapp?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "external_quote_leads_promoted_client_id_fkey"
            columns: ["promoted_client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      external_quote_parts: {
        Row: {
          created_at: string
          currency_snapshot: string | null
          external_quote_id: string
          id: string
          line_total_cost: number
          line_total_sale: number
          name_snapshot: string
          notes: string | null
          product_id: string | null
          quantity: number
          unit_cost_snapshot: number
          unit_sale_snapshot: number
          updated_at: string
          warranty_days: number | null
        }
        Insert: {
          created_at?: string
          currency_snapshot?: string | null
          external_quote_id: string
          id?: string
          line_total_cost?: number
          line_total_sale?: number
          name_snapshot: string
          notes?: string | null
          product_id?: string | null
          quantity?: number
          unit_cost_snapshot?: number
          unit_sale_snapshot?: number
          updated_at?: string
          warranty_days?: number | null
        }
        Update: {
          created_at?: string
          currency_snapshot?: string | null
          external_quote_id?: string
          id?: string
          line_total_cost?: number
          line_total_sale?: number
          name_snapshot?: string
          notes?: string | null
          product_id?: string | null
          quantity?: number
          unit_cost_snapshot?: number
          unit_sale_snapshot?: number
          updated_at?: string
          warranty_days?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "external_quote_parts_external_quote_id_fkey"
            columns: ["external_quote_id"]
            isOneToOne: false
            referencedRelation: "external_quotes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "external_quote_parts_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "product_availability"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "external_quote_parts_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "external_quote_parts_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_entradas_pendentes"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "external_quote_parts_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_variancia"
            referencedColumns: ["product_id"]
          },
        ]
      }
      external_quote_services: {
        Row: {
          billing_unit_snapshot: string
          created_at: string
          description_snapshot: string | null
          external_quote_id: string
          id: string
          line_total: number
          name_snapshot: string
          notes: string | null
          quantity: number
          service_id: string | null
          unit_price_snapshot: number
          updated_at: string
          warranty_days: number | null
        }
        Insert: {
          billing_unit_snapshot?: string
          created_at?: string
          description_snapshot?: string | null
          external_quote_id: string
          id?: string
          line_total?: number
          name_snapshot: string
          notes?: string | null
          quantity?: number
          service_id?: string | null
          unit_price_snapshot?: number
          updated_at?: string
          warranty_days?: number | null
        }
        Update: {
          billing_unit_snapshot?: string
          created_at?: string
          description_snapshot?: string | null
          external_quote_id?: string
          id?: string
          line_total?: number
          name_snapshot?: string
          notes?: string | null
          quantity?: number
          service_id?: string | null
          unit_price_snapshot?: number
          updated_at?: string
          warranty_days?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "external_quote_services_external_quote_id_fkey"
            columns: ["external_quote_id"]
            isOneToOne: false
            referencedRelation: "external_quotes"
            referencedColumns: ["id"]
          },
        ]
      }
      external_quotes: {
        Row: {
          ai_operator_draft_id: string | null
          client_id: string | null
          converted_at: string | null
          converted_service_order_id: string | null
          created_at: string
          created_by: string
          currency: string | null
          customer_visible_report: string | null
          discount_amount: number | null
          estimated_hours: number | null
          grand_total: number | null
          hourly_rate: number | null
          id: string
          initial_findings: string | null
          internal_notes: string | null
          labor_cost_total: number | null
          lead_id: string | null
          marina_id: string | null
          parts_cost_total: number | null
          payment_conditions: string | null
          problem_description: string | null
          quote_number: string
          quote_validity_date: string | null
          quote_validity_days: number | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          service_type: string | null
          status: string
          subcontract_cost_total: number | null
          submitted_at: string | null
          tax_amount: number | null
          travel_cost_per_km: number | null
          travel_cost_total: number | null
          travel_distance_km: number | null
          updated_at: string
          vessel_id: string | null
        }
        Insert: {
          ai_operator_draft_id?: string | null
          client_id?: string | null
          converted_at?: string | null
          converted_service_order_id?: string | null
          created_at?: string
          created_by: string
          currency?: string | null
          customer_visible_report?: string | null
          discount_amount?: number | null
          estimated_hours?: number | null
          grand_total?: number | null
          hourly_rate?: number | null
          id?: string
          initial_findings?: string | null
          internal_notes?: string | null
          labor_cost_total?: number | null
          lead_id?: string | null
          marina_id?: string | null
          parts_cost_total?: number | null
          payment_conditions?: string | null
          problem_description?: string | null
          quote_number?: string
          quote_validity_date?: string | null
          quote_validity_days?: number | null
          rejection_reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          service_type?: string | null
          status?: string
          subcontract_cost_total?: number | null
          submitted_at?: string | null
          tax_amount?: number | null
          travel_cost_per_km?: number | null
          travel_cost_total?: number | null
          travel_distance_km?: number | null
          updated_at?: string
          vessel_id?: string | null
        }
        Update: {
          ai_operator_draft_id?: string | null
          client_id?: string | null
          converted_at?: string | null
          converted_service_order_id?: string | null
          created_at?: string
          created_by?: string
          currency?: string | null
          customer_visible_report?: string | null
          discount_amount?: number | null
          estimated_hours?: number | null
          grand_total?: number | null
          hourly_rate?: number | null
          id?: string
          initial_findings?: string | null
          internal_notes?: string | null
          labor_cost_total?: number | null
          lead_id?: string | null
          marina_id?: string | null
          parts_cost_total?: number | null
          payment_conditions?: string | null
          problem_description?: string | null
          quote_number?: string
          quote_validity_date?: string | null
          quote_validity_days?: number | null
          rejection_reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          service_type?: string | null
          status?: string
          subcontract_cost_total?: number | null
          submitted_at?: string | null
          tax_amount?: number | null
          travel_cost_per_km?: number | null
          travel_cost_total?: number | null
          travel_distance_km?: number | null
          updated_at?: string
          vessel_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "external_quotes_ai_operator_draft_id_fkey"
            columns: ["ai_operator_draft_id"]
            isOneToOne: false
            referencedRelation: "ai_operator_drafts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "external_quotes_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "external_quotes_converted_service_order_id_fkey"
            columns: ["converted_service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "external_quotes_converted_service_order_id_fkey"
            columns: ["converted_service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "external_quotes_converted_service_order_id_fkey"
            columns: ["converted_service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "external_quotes_converted_service_order_id_fkey"
            columns: ["converted_service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
          {
            foreignKeyName: "external_quotes_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: false
            referencedRelation: "external_quote_leads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "external_quotes_marina_id_fkey"
            columns: ["marina_id"]
            isOneToOne: false
            referencedRelation: "marinas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "external_quotes_vessel_id_fkey"
            columns: ["vessel_id"]
            isOneToOne: false
            referencedRelation: "vessels"
            referencedColumns: ["id"]
          },
        ]
      }
      finance_review_queue: {
        Row: {
          applied_rule_id: string | null
          bank_transaction_id: string | null
          confidence: number
          created_at: string
          created_payable_id: string | null
          created_receivable_id: string | null
          decided_at: string | null
          decided_by: string | null
          decision_note: string | null
          dre_group: string | null
          id: string
          kind: string
          reasoning: string | null
          related_transaction_id: string | null
          status: string
          suggested_amount: number | null
          suggested_category: string | null
          suggested_client_id: string | null
          suggested_date: string | null
          suggested_description: string | null
          suggested_payee_id: string | null
          suggested_purchase_order_id: string | null
          suggested_service_order_id: string | null
          suggested_supplier_id: string | null
          title: string
          updated_at: string
        }
        Insert: {
          applied_rule_id?: string | null
          bank_transaction_id?: string | null
          confidence?: number
          created_at?: string
          created_payable_id?: string | null
          created_receivable_id?: string | null
          decided_at?: string | null
          decided_by?: string | null
          decision_note?: string | null
          dre_group?: string | null
          id?: string
          kind: string
          reasoning?: string | null
          related_transaction_id?: string | null
          status?: string
          suggested_amount?: number | null
          suggested_category?: string | null
          suggested_client_id?: string | null
          suggested_date?: string | null
          suggested_description?: string | null
          suggested_payee_id?: string | null
          suggested_purchase_order_id?: string | null
          suggested_service_order_id?: string | null
          suggested_supplier_id?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          applied_rule_id?: string | null
          bank_transaction_id?: string | null
          confidence?: number
          created_at?: string
          created_payable_id?: string | null
          created_receivable_id?: string | null
          decided_at?: string | null
          decided_by?: string | null
          decision_note?: string | null
          dre_group?: string | null
          id?: string
          kind?: string
          reasoning?: string | null
          related_transaction_id?: string | null
          status?: string
          suggested_amount?: number | null
          suggested_category?: string | null
          suggested_client_id?: string | null
          suggested_date?: string | null
          suggested_description?: string | null
          suggested_payee_id?: string | null
          suggested_purchase_order_id?: string | null
          suggested_service_order_id?: string | null
          suggested_supplier_id?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "finance_review_queue_applied_rule_id_fkey"
            columns: ["applied_rule_id"]
            isOneToOne: false
            referencedRelation: "finance_rules"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "finance_review_queue_bank_transaction_id_fkey"
            columns: ["bank_transaction_id"]
            isOneToOne: false
            referencedRelation: "bank_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "finance_review_queue_created_payable_id_fkey"
            columns: ["created_payable_id"]
            isOneToOne: false
            referencedRelation: "payables"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "finance_review_queue_created_receivable_id_fkey"
            columns: ["created_receivable_id"]
            isOneToOne: false
            referencedRelation: "receivables"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "finance_review_queue_related_transaction_id_fkey"
            columns: ["related_transaction_id"]
            isOneToOne: false
            referencedRelation: "bank_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "finance_review_queue_suggested_client_id_fkey"
            columns: ["suggested_client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "finance_review_queue_suggested_payee_id_fkey"
            columns: ["suggested_payee_id"]
            isOneToOne: false
            referencedRelation: "payees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "finance_review_queue_suggested_purchase_order_id_fkey"
            columns: ["suggested_purchase_order_id"]
            isOneToOne: false
            referencedRelation: "purchase_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "finance_review_queue_suggested_service_order_id_fkey"
            columns: ["suggested_service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "finance_review_queue_suggested_service_order_id_fkey"
            columns: ["suggested_service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "finance_review_queue_suggested_service_order_id_fkey"
            columns: ["suggested_service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "finance_review_queue_suggested_service_order_id_fkey"
            columns: ["suggested_service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
          {
            foreignKeyName: "finance_review_queue_suggested_supplier_id_fkey"
            columns: ["suggested_supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      finance_rules: {
        Row: {
          autonomy: string
          created_at: string
          created_by: string | null
          direction: string
          id: string
          last_applied_at: string | null
          match_type: string
          match_value: string
          max_amount: number | null
          min_amount: number | null
          note: string | null
          origin: string
          reasoning: string | null
          set_category: string | null
          set_dre_group: string | null
          set_supplier_id: string | null
          status: string
          times_applied: number
          updated_at: string
        }
        Insert: {
          autonomy?: string
          created_at?: string
          created_by?: string | null
          direction?: string
          id?: string
          last_applied_at?: string | null
          match_type: string
          match_value: string
          max_amount?: number | null
          min_amount?: number | null
          note?: string | null
          origin?: string
          reasoning?: string | null
          set_category?: string | null
          set_dre_group?: string | null
          set_supplier_id?: string | null
          status?: string
          times_applied?: number
          updated_at?: string
        }
        Update: {
          autonomy?: string
          created_at?: string
          created_by?: string | null
          direction?: string
          id?: string
          last_applied_at?: string | null
          match_type?: string
          match_value?: string
          max_amount?: number | null
          min_amount?: number | null
          note?: string | null
          origin?: string
          reasoning?: string | null
          set_category?: string | null
          set_dre_group?: string | null
          set_supplier_id?: string | null
          status?: string
          times_applied?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "finance_rules_set_supplier_id_fkey"
            columns: ["set_supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      financial_categories: {
        Row: {
          active: boolean | null
          color: string | null
          created_at: string | null
          description: string | null
          dre_group: string | null
          id: string
          name: string
          sort_order: number
          type: string
        }
        Insert: {
          active?: boolean | null
          color?: string | null
          created_at?: string | null
          description?: string | null
          dre_group?: string | null
          id?: string
          name: string
          sort_order?: number
          type: string
        }
        Update: {
          active?: boolean | null
          color?: string | null
          created_at?: string | null
          description?: string | null
          dre_group?: string | null
          id?: string
          name?: string
          sort_order?: number
          type?: string
        }
        Relationships: []
      }
      fiscal_document_sequences: {
        Row: {
          document_type: string
          environment: string
          last_number: number
          series: number
          updated_at: string | null
        }
        Insert: {
          document_type: string
          environment?: string
          last_number?: number
          series?: number
          updated_at?: string | null
        }
        Update: {
          document_type?: string
          environment?: string
          last_number?: number
          series?: number
          updated_at?: string | null
        }
        Relationships: []
      }
      fiscal_emission_drafts: {
        Row: {
          created_at: string
          created_by: string | null
          form_state: Json
          id: string
          label: string | null
          nature_of_operation: string | null
          recipient_name: string | null
          status: string
          total_amount: number | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          form_state: Json
          id?: string
          label?: string | null
          nature_of_operation?: string | null
          recipient_name?: string | null
          status?: string
          total_amount?: number | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          form_state?: Json
          id?: string
          label?: string | null
          nature_of_operation?: string | null
          recipient_name?: string | null
          status?: string
          total_amount?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "fiscal_emission_drafts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      fiscal_note_items: {
        Row: {
          c_prod: string | null
          cfop: string | null
          created_at: string | null
          description: string | null
          fiscal_note_id: string | null
          id: string
          inventory_movement_id: string | null
          item_index: number | null
          matched_product_id: string | null
          ncm: string | null
          processed: boolean | null
          product_id: string | null
          q_com: number | null
          quantity: number | null
          sku_internal: string | null
          sku_supplier: string | null
          total_price: number | null
          unit: string | null
          unit_price: number | null
          v_prod: number | null
          v_un_com: number | null
          x_prod: string | null
        }
        Insert: {
          c_prod?: string | null
          cfop?: string | null
          created_at?: string | null
          description?: string | null
          fiscal_note_id?: string | null
          id?: string
          inventory_movement_id?: string | null
          item_index?: number | null
          matched_product_id?: string | null
          ncm?: string | null
          processed?: boolean | null
          product_id?: string | null
          q_com?: number | null
          quantity?: number | null
          sku_internal?: string | null
          sku_supplier?: string | null
          total_price?: number | null
          unit?: string | null
          unit_price?: number | null
          v_prod?: number | null
          v_un_com?: number | null
          x_prod?: string | null
        }
        Update: {
          c_prod?: string | null
          cfop?: string | null
          created_at?: string | null
          description?: string | null
          fiscal_note_id?: string | null
          id?: string
          inventory_movement_id?: string | null
          item_index?: number | null
          matched_product_id?: string | null
          ncm?: string | null
          processed?: boolean | null
          product_id?: string | null
          q_com?: number | null
          quantity?: number | null
          sku_internal?: string | null
          sku_supplier?: string | null
          total_price?: number | null
          unit?: string | null
          unit_price?: number | null
          v_prod?: number | null
          v_un_com?: number | null
          x_prod?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fiscal_note_items_fiscal_note_id_fkey"
            columns: ["fiscal_note_id"]
            isOneToOne: false
            referencedRelation: "fiscal_notes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fiscal_note_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "product_availability"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fiscal_note_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fiscal_note_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_entradas_pendentes"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "fiscal_note_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_variancia"
            referencedColumns: ["product_id"]
          },
        ]
      }
      fiscal_notes: {
        Row: {
          company_id: string | null
          confirmed_at: string | null
          created_at: string | null
          id: string
          import_result: Json | null
          issue_date: string | null
          issued_at: string | null
          issuer_cnpj: string | null
          issuer_name: string | null
          items: Json | null
          nfe_key: string | null
          nfe_number: string | null
          purchase_order_id: string | null
          status: string | null
          supplier_id: string | null
          tax_cofins: number | null
          tax_icms: number | null
          tax_ipi: number | null
          tax_pis: number | null
          total_amount: number | null
          total_discount: number | null
          total_freight: number | null
          total_insurance: number | null
          total_other: number | null
          total_products: number | null
          total_value: number | null
          updated_at: string | null
          xml_content: string | null
          xml_url: string | null
        }
        Insert: {
          company_id?: string | null
          confirmed_at?: string | null
          created_at?: string | null
          id?: string
          import_result?: Json | null
          issue_date?: string | null
          issued_at?: string | null
          issuer_cnpj?: string | null
          issuer_name?: string | null
          items?: Json | null
          nfe_key?: string | null
          nfe_number?: string | null
          purchase_order_id?: string | null
          status?: string | null
          supplier_id?: string | null
          tax_cofins?: number | null
          tax_icms?: number | null
          tax_ipi?: number | null
          tax_pis?: number | null
          total_amount?: number | null
          total_discount?: number | null
          total_freight?: number | null
          total_insurance?: number | null
          total_other?: number | null
          total_products?: number | null
          total_value?: number | null
          updated_at?: string | null
          xml_content?: string | null
          xml_url?: string | null
        }
        Update: {
          company_id?: string | null
          confirmed_at?: string | null
          created_at?: string | null
          id?: string
          import_result?: Json | null
          issue_date?: string | null
          issued_at?: string | null
          issuer_cnpj?: string | null
          issuer_name?: string | null
          items?: Json | null
          nfe_key?: string | null
          nfe_number?: string | null
          purchase_order_id?: string | null
          status?: string | null
          supplier_id?: string | null
          tax_cofins?: number | null
          tax_icms?: number | null
          tax_ipi?: number | null
          tax_pis?: number | null
          total_amount?: number | null
          total_discount?: number | null
          total_freight?: number | null
          total_insurance?: number | null
          total_other?: number | null
          total_products?: number | null
          total_value?: number | null
          updated_at?: string | null
          xml_content?: string | null
          xml_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fiscal_notes_purchase_order_id_fkey"
            columns: ["purchase_order_id"]
            isOneToOne: false
            referencedRelation: "purchase_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fiscal_notes_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
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
          reverses_movement_id: string | null
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
          reverses_movement_id?: string | null
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
          reverses_movement_id?: string | null
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
            referencedRelation: "product_availability"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_movements_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_movements_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_entradas_pendentes"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "inventory_movements_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_variancia"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "inventory_movements_reverses_movement_id_fkey"
            columns: ["reverses_movement_id"]
            isOneToOne: false
            referencedRelation: "inventory_movements"
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
          {
            foreignKeyName: "invoices_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
        ]
      }
      issued_fiscal_documents: {
        Row: {
          access_key: string | null
          authorized_at: string | null
          cancelled_at: string | null
          client_id: string | null
          created_at: string | null
          customer_buyer_name: string | null
          customer_po_number: string | null
          document_type: string
          environment: string
          id: string
          idempotency_key: string | null
          number: number | null
          origin_id: string | null
          origin_type: string
          payment_terms: Json | null
          pdf_storage_path: string | null
          pdf_url: string | null
          protocol: string | null
          provider: string
          provider_document_id: string | null
          provider_status: Json | null
          receivable_id: string | null
          request_payload: Json | null
          series: number | null
          source_items: Json | null
          status: string
          status_code: string | null
          status_message: string | null
          stock_reversed_at: string | null
          stock_settled_at: string | null
          updated_at: string | null
          xml_storage_path: string | null
          xml_url: string | null
        }
        Insert: {
          access_key?: string | null
          authorized_at?: string | null
          cancelled_at?: string | null
          client_id?: string | null
          created_at?: string | null
          customer_buyer_name?: string | null
          customer_po_number?: string | null
          document_type: string
          environment?: string
          id?: string
          idempotency_key?: string | null
          number?: number | null
          origin_id?: string | null
          origin_type?: string
          payment_terms?: Json | null
          pdf_storage_path?: string | null
          pdf_url?: string | null
          protocol?: string | null
          provider?: string
          provider_document_id?: string | null
          provider_status?: Json | null
          receivable_id?: string | null
          request_payload?: Json | null
          series?: number | null
          source_items?: Json | null
          status?: string
          status_code?: string | null
          status_message?: string | null
          stock_reversed_at?: string | null
          stock_settled_at?: string | null
          updated_at?: string | null
          xml_storage_path?: string | null
          xml_url?: string | null
        }
        Update: {
          access_key?: string | null
          authorized_at?: string | null
          cancelled_at?: string | null
          client_id?: string | null
          created_at?: string | null
          customer_buyer_name?: string | null
          customer_po_number?: string | null
          document_type?: string
          environment?: string
          id?: string
          idempotency_key?: string | null
          number?: number | null
          origin_id?: string | null
          origin_type?: string
          payment_terms?: Json | null
          pdf_storage_path?: string | null
          pdf_url?: string | null
          protocol?: string | null
          provider?: string
          provider_document_id?: string | null
          provider_status?: Json | null
          receivable_id?: string | null
          request_payload?: Json | null
          series?: number | null
          source_items?: Json | null
          status?: string
          status_code?: string | null
          status_message?: string | null
          stock_reversed_at?: string | null
          stock_settled_at?: string | null
          updated_at?: string | null
          xml_storage_path?: string | null
          xml_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "issued_fiscal_documents_receivable_id_fkey"
            columns: ["receivable_id"]
            isOneToOne: false
            referencedRelation: "receivables"
            referencedColumns: ["id"]
          },
        ]
      }
      maintenance_plans: {
        Row: {
          active: boolean
          advance_days: number
          created_at: string
          created_by: string | null
          estimated_value: number | null
          id: string
          interval_months: number
          last_service_at: string | null
          name: string
          notes: string | null
          scope: string | null
          updated_at: string
          vessel_id: string
        }
        Insert: {
          active?: boolean
          advance_days?: number
          created_at?: string
          created_by?: string | null
          estimated_value?: number | null
          id?: string
          interval_months: number
          last_service_at?: string | null
          name: string
          notes?: string | null
          scope?: string | null
          updated_at?: string
          vessel_id: string
        }
        Update: {
          active?: boolean
          advance_days?: number
          created_at?: string
          created_by?: string | null
          estimated_value?: number | null
          id?: string
          interval_months?: number
          last_service_at?: string | null
          name?: string
          notes?: string | null
          scope?: string | null
          updated_at?: string
          vessel_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "maintenance_plans_vessel_id_fkey"
            columns: ["vessel_id"]
            isOneToOne: false
            referencedRelation: "vessels"
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
          contact_name: string | null
          country: string | null
          created_at: string
          email: string | null
          id: string
          latitude: number | null
          longitude: number | null
          name: string
          phone: string | null
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
          contact_name?: string | null
          country?: string | null
          created_at?: string
          email?: string | null
          id?: string
          latitude?: number | null
          longitude?: number | null
          name: string
          phone?: string | null
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
          contact_name?: string | null
          country?: string | null
          created_at?: string
          email?: string | null
          id?: string
          latitude?: number | null
          longitude?: number | null
          name?: string
          phone?: string | null
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
          cost_center_id: string | null
          created_at: string
          currency: string | null
          description: string
          due_date: string
          expense_category: string | null
          fiscal_note_id: string | null
          id: string
          issue_date: string
          linked_service_order_id: string | null
          notes: string | null
          origin: string | null
          paid_amount: number | null
          payee_id: string | null
          payment_method: string | null
          status: string | null
          sub_category: string | null
          supplier_id: string | null
          supplier_name: string | null
          updated_at: string
        }
        Insert: {
          amount: number
          balance_amount?: number | null
          bank_transaction_id?: string | null
          cost_center_id?: string | null
          created_at?: string
          currency?: string | null
          description: string
          due_date: string
          expense_category?: string | null
          fiscal_note_id?: string | null
          id?: string
          issue_date: string
          linked_service_order_id?: string | null
          notes?: string | null
          origin?: string | null
          paid_amount?: number | null
          payee_id?: string | null
          payment_method?: string | null
          status?: string | null
          sub_category?: string | null
          supplier_id?: string | null
          supplier_name?: string | null
          updated_at?: string
        }
        Update: {
          amount?: number
          balance_amount?: number | null
          bank_transaction_id?: string | null
          cost_center_id?: string | null
          created_at?: string
          currency?: string | null
          description?: string
          due_date?: string
          expense_category?: string | null
          fiscal_note_id?: string | null
          id?: string
          issue_date?: string
          linked_service_order_id?: string | null
          notes?: string | null
          origin?: string | null
          paid_amount?: number | null
          payee_id?: string | null
          payment_method?: string | null
          status?: string | null
          sub_category?: string | null
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
            foreignKeyName: "payables_cost_center_id_fkey"
            columns: ["cost_center_id"]
            isOneToOne: false
            referencedRelation: "cost_centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payables_fiscal_note_id_fkey"
            columns: ["fiscal_note_id"]
            isOneToOne: false
            referencedRelation: "fiscal_notes"
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
            foreignKeyName: "payables_linked_service_order_id_fkey"
            columns: ["linked_service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payables_linked_service_order_id_fkey"
            columns: ["linked_service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payables_linked_service_order_id_fkey"
            columns: ["linked_service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
          {
            foreignKeyName: "payables_payee_id_fkey"
            columns: ["payee_id"]
            isOneToOne: false
            referencedRelation: "payees"
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
      payees: {
        Row: {
          account_type: string | null
          active: boolean
          bank_account: string | null
          bank_branch: string | null
          bank_name: string | null
          created_at: string
          default_category: string | null
          document: string | null
          email: string | null
          id: string
          kind: string
          name: string
          notes: string | null
          phone: string | null
          pix_key: string | null
          pix_key_type: string | null
          updated_at: string
        }
        Insert: {
          account_type?: string | null
          active?: boolean
          bank_account?: string | null
          bank_branch?: string | null
          bank_name?: string | null
          created_at?: string
          default_category?: string | null
          document?: string | null
          email?: string | null
          id?: string
          kind?: string
          name: string
          notes?: string | null
          phone?: string | null
          pix_key?: string | null
          pix_key_type?: string | null
          updated_at?: string
        }
        Update: {
          account_type?: string | null
          active?: boolean
          bank_account?: string | null
          bank_branch?: string | null
          bank_name?: string | null
          created_at?: string
          default_category?: string | null
          document?: string | null
          email?: string | null
          id?: string
          kind?: string
          name?: string
          notes?: string | null
          phone?: string | null
          pix_key?: string | null
          pix_key_type?: string | null
          updated_at?: string
        }
        Relationships: []
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
          receipt_storage_path: string | null
          receipt_url: string | null
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
          receipt_storage_path?: string | null
          receipt_url?: string | null
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
          receipt_storage_path?: string | null
          receipt_url?: string | null
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
      price_update_suggestions: {
        Row: {
          created_at: string | null
          current_sale_price: number | null
          fiscal_note_id: string | null
          id: string
          margin_percent: number | null
          product_id: string | null
          status: string | null
          suggested_sale_price: number | null
        }
        Insert: {
          created_at?: string | null
          current_sale_price?: number | null
          fiscal_note_id?: string | null
          id?: string
          margin_percent?: number | null
          product_id?: string | null
          status?: string | null
          suggested_sale_price?: number | null
        }
        Update: {
          created_at?: string | null
          current_sale_price?: number | null
          fiscal_note_id?: string | null
          id?: string
          margin_percent?: number | null
          product_id?: string | null
          status?: string | null
          suggested_sale_price?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "price_update_suggestions_fiscal_note_id_fkey"
            columns: ["fiscal_note_id"]
            isOneToOne: false
            referencedRelation: "fiscal_notes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "price_update_suggestions_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "product_availability"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "price_update_suggestions_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "price_update_suggestions_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_entradas_pendentes"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "price_update_suggestions_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_variancia"
            referencedColumns: ["product_id"]
          },
        ]
      }
      product_aliases: {
        Row: {
          alias_normalized: string
          alias_original: string
          created_at: string | null
          created_by: string | null
          id: string
          product_id: string
        }
        Insert: {
          alias_normalized: string
          alias_original: string
          created_at?: string | null
          created_by?: string | null
          id?: string
          product_id: string
        }
        Update: {
          alias_normalized?: string
          alias_original?: string
          created_at?: string | null
          created_by?: string | null
          id?: string
          product_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "product_aliases_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "product_availability"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_aliases_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_aliases_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_entradas_pendentes"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "product_aliases_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_variancia"
            referencedColumns: ["product_id"]
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
      product_components: {
        Row: {
          component_product_id: string
          created_at: string
          id: string
          parent_product_id: string
          quantity: number
        }
        Insert: {
          component_product_id: string
          created_at?: string
          id?: string
          parent_product_id: string
          quantity?: number
        }
        Update: {
          component_product_id?: string
          created_at?: string
          id?: string
          parent_product_id?: string
          quantity?: number
        }
        Relationships: [
          {
            foreignKeyName: "product_components_component_product_id_fkey"
            columns: ["component_product_id"]
            isOneToOne: false
            referencedRelation: "product_availability"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_components_component_product_id_fkey"
            columns: ["component_product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_components_component_product_id_fkey"
            columns: ["component_product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_entradas_pendentes"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "product_components_component_product_id_fkey"
            columns: ["component_product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_variancia"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "product_components_parent_product_id_fkey"
            columns: ["parent_product_id"]
            isOneToOne: false
            referencedRelation: "product_availability"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_components_parent_product_id_fkey"
            columns: ["parent_product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_components_parent_product_id_fkey"
            columns: ["parent_product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_entradas_pendentes"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "product_components_parent_product_id_fkey"
            columns: ["parent_product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_variancia"
            referencedColumns: ["product_id"]
          },
        ]
      }
      product_price_history: {
        Row: {
          created_at: string | null
          fiscal_note_id: string | null
          id: string
          new_cost: number | null
          old_cost: number | null
          product_id: string | null
        }
        Insert: {
          created_at?: string | null
          fiscal_note_id?: string | null
          id?: string
          new_cost?: number | null
          old_cost?: number | null
          product_id?: string | null
        }
        Update: {
          created_at?: string | null
          fiscal_note_id?: string | null
          id?: string
          new_cost?: number | null
          old_cost?: number | null
          product_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "product_price_history_fiscal_note_id_fkey"
            columns: ["fiscal_note_id"]
            isOneToOne: false
            referencedRelation: "fiscal_notes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_price_history_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "product_availability"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_price_history_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_price_history_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_entradas_pendentes"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "product_price_history_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_variancia"
            referencedColumns: ["product_id"]
          },
        ]
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
            referencedRelation: "product_availability"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_suppliers_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_suppliers_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_entradas_pendentes"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "product_suppliers_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_variancia"
            referencedColumns: ["product_id"]
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
          cfop: string | null
          cofins_rate: number | null
          commission_rate: number | null
          cost_currency: string | null
          cost_price: number | null
          created_at: string
          csosn: string | null
          default_warranty_days: number | null
          fiscal_complete: boolean
          fiscal_origin: number | null
          icms_rate: number | null
          id: string
          image_url: string | null
          ipi_rate: number | null
          is_commissionable: boolean | null
          is_equipment: boolean | null
          last_stock_entry_at: string | null
          location_bin: string | null
          minimum_stock: number | null
          name: string
          ncm: string | null
          notes: string | null
          pis_rate: number | null
          product_category_id: string | null
          product_type: string
          profit_margin: number | null
          reserved_quantity: number
          sale_currency: string | null
          sale_price: number | null
          sku: string | null
          stock_quantity: number | null
          supplier_id: string | null
          unit: string | null
          updated_at: string
          use_global_fiscal: boolean | null
          vende_isolado: boolean
        }
        Insert: {
          active?: boolean
          barcode?: string | null
          brand?: string | null
          category?: string | null
          cfop?: string | null
          cofins_rate?: number | null
          commission_rate?: number | null
          cost_currency?: string | null
          cost_price?: number | null
          created_at?: string
          csosn?: string | null
          default_warranty_days?: number | null
          fiscal_complete?: boolean
          fiscal_origin?: number | null
          icms_rate?: number | null
          id?: string
          image_url?: string | null
          ipi_rate?: number | null
          is_commissionable?: boolean | null
          is_equipment?: boolean | null
          last_stock_entry_at?: string | null
          location_bin?: string | null
          minimum_stock?: number | null
          name: string
          ncm?: string | null
          notes?: string | null
          pis_rate?: number | null
          product_category_id?: string | null
          product_type?: string
          profit_margin?: number | null
          reserved_quantity?: number
          sale_currency?: string | null
          sale_price?: number | null
          sku?: string | null
          stock_quantity?: number | null
          supplier_id?: string | null
          unit?: string | null
          updated_at?: string
          use_global_fiscal?: boolean | null
          vende_isolado?: boolean
        }
        Update: {
          active?: boolean
          barcode?: string | null
          brand?: string | null
          category?: string | null
          cfop?: string | null
          cofins_rate?: number | null
          commission_rate?: number | null
          cost_currency?: string | null
          cost_price?: number | null
          created_at?: string
          csosn?: string | null
          default_warranty_days?: number | null
          fiscal_complete?: boolean
          fiscal_origin?: number | null
          icms_rate?: number | null
          id?: string
          image_url?: string | null
          ipi_rate?: number | null
          is_commissionable?: boolean | null
          is_equipment?: boolean | null
          last_stock_entry_at?: string | null
          location_bin?: string | null
          minimum_stock?: number | null
          name?: string
          ncm?: string | null
          notes?: string | null
          pis_rate?: number | null
          product_category_id?: string | null
          product_type?: string
          profit_margin?: number | null
          reserved_quantity?: number
          sale_currency?: string | null
          sale_price?: number | null
          sku?: string | null
          stock_quantity?: number | null
          supplier_id?: string | null
          unit?: string | null
          updated_at?: string
          use_global_fiscal?: boolean | null
          vende_isolado?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "products_product_category_id_fkey"
            columns: ["product_category_id"]
            isOneToOne: false
            referencedRelation: "product_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "products_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      products_stock_backup_pre_v2: {
        Row: {
          backed_up_at: string | null
          id: string | null
          reserved_quantity: number | null
          stock_quantity: number | null
        }
        Insert: {
          backed_up_at?: string | null
          id?: string | null
          reserved_quantity?: number | null
          stock_quantity?: number | null
        }
        Update: {
          backed_up_at?: string | null
          id?: string | null
          reserved_quantity?: number | null
          stock_quantity?: number | null
        }
        Relationships: []
      }
      purchase_order_items: {
        Row: {
          created_at: string
          description: string
          id: string
          product_id: string | null
          purchase_order_id: string
          quantity: number
          received_qty: number
          unit_cost: number
        }
        Insert: {
          created_at?: string
          description: string
          id?: string
          product_id?: string | null
          purchase_order_id: string
          quantity?: number
          received_qty?: number
          unit_cost?: number
        }
        Update: {
          created_at?: string
          description?: string
          id?: string
          product_id?: string | null
          purchase_order_id?: string
          quantity?: number
          received_qty?: number
          unit_cost?: number
        }
        Relationships: [
          {
            foreignKeyName: "purchase_order_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "product_availability"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_order_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_order_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_entradas_pendentes"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "purchase_order_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_variancia"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "purchase_order_items_purchase_order_id_fkey"
            columns: ["purchase_order_id"]
            isOneToOne: false
            referencedRelation: "purchase_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      purchase_orders: {
        Row: {
          created_at: string
          created_by: string
          expected_date: string | null
          id: string
          notes: string | null
          payable_id: string | null
          po_number: string
          received_date: string | null
          service_order_id: string | null
          status: string
          supplier_id: string | null
          total_amount: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string
          expected_date?: string | null
          id?: string
          notes?: string | null
          payable_id?: string | null
          po_number: string
          received_date?: string | null
          service_order_id?: string | null
          status?: string
          supplier_id?: string | null
          total_amount?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string
          expected_date?: string | null
          id?: string
          notes?: string | null
          payable_id?: string | null
          po_number?: string
          received_date?: string | null
          service_order_id?: string | null
          status?: string
          supplier_id?: string | null
          total_amount?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "purchase_orders_payable_id_fkey"
            columns: ["payable_id"]
            isOneToOne: false
            referencedRelation: "payables"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_orders_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_orders_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_orders_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_orders_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
          {
            foreignKeyName: "purchase_orders_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      push_subscriptions: {
        Row: {
          auth: string
          created_at: string
          endpoint: string
          id: string
          p256dh: string
          user_agent: string | null
          user_id: string
        }
        Insert: {
          auth: string
          created_at?: string
          endpoint: string
          id?: string
          p256dh: string
          user_agent?: string | null
          user_id: string
        }
        Update: {
          auth?: string
          created_at?: string
          endpoint?: string
          id?: string
          p256dh?: string
          user_agent?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "push_subscriptions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      quote_request_items: {
        Row: {
          created_at: string | null
          description: string
          id: string
          position: number
          product_id: string | null
          quantity: number
          quote_request_id: string
          service_order_part_id: string | null
          service_order_service_id: string | null
        }
        Insert: {
          created_at?: string | null
          description: string
          id?: string
          position?: number
          product_id?: string | null
          quantity?: number
          quote_request_id: string
          service_order_part_id?: string | null
          service_order_service_id?: string | null
        }
        Update: {
          created_at?: string | null
          description?: string
          id?: string
          position?: number
          product_id?: string | null
          quantity?: number
          quote_request_id?: string
          service_order_part_id?: string | null
          service_order_service_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "quote_request_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "product_availability"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_request_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_request_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_entradas_pendentes"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "quote_request_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_variancia"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "quote_request_items_quote_request_id_fkey"
            columns: ["quote_request_id"]
            isOneToOne: false
            referencedRelation: "quote_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_request_items_service_order_part_id_fkey"
            columns: ["service_order_part_id"]
            isOneToOne: false
            referencedRelation: "service_order_parts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_request_items_service_order_service_id_fkey"
            columns: ["service_order_service_id"]
            isOneToOne: false
            referencedRelation: "service_order_services"
            referencedColumns: ["id"]
          },
        ]
      }
      quote_requests: {
        Row: {
          closed_at: string | null
          code: string
          created_at: string | null
          created_by: string | null
          id: string
          notes: string | null
          sent_supplier_ids: string[]
          service_order_id: string | null
          status: string
          updated_at: string | null
        }
        Insert: {
          closed_at?: string | null
          code: string
          created_at?: string | null
          created_by?: string | null
          id?: string
          notes?: string | null
          sent_supplier_ids?: string[]
          service_order_id?: string | null
          status?: string
          updated_at?: string | null
        }
        Update: {
          closed_at?: string | null
          code?: string
          created_at?: string | null
          created_by?: string | null
          id?: string
          notes?: string | null
          sent_supplier_ids?: string[]
          service_order_id?: string | null
          status?: string
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "quote_requests_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_requests_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_requests_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_requests_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
        ]
      }
      quote_responses: {
        Row: {
          confirmed: boolean
          created_at: string | null
          id: string
          lead_time_days: number | null
          quote_request_id: string
          quote_request_item_id: string | null
          source: string
          source_excerpt: string | null
          supplier_id: string
          unit_price: number | null
          updated_at: string | null
          whatsapp_message_id: string | null
        }
        Insert: {
          confirmed?: boolean
          created_at?: string | null
          id?: string
          lead_time_days?: number | null
          quote_request_id: string
          quote_request_item_id?: string | null
          source?: string
          source_excerpt?: string | null
          supplier_id: string
          unit_price?: number | null
          updated_at?: string | null
          whatsapp_message_id?: string | null
        }
        Update: {
          confirmed?: boolean
          created_at?: string | null
          id?: string
          lead_time_days?: number | null
          quote_request_id?: string
          quote_request_item_id?: string | null
          source?: string
          source_excerpt?: string | null
          supplier_id?: string
          unit_price?: number | null
          updated_at?: string | null
          whatsapp_message_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "quote_responses_quote_request_id_fkey"
            columns: ["quote_request_id"]
            isOneToOne: false
            referencedRelation: "quote_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_responses_quote_request_item_id_fkey"
            columns: ["quote_request_item_id"]
            isOneToOne: false
            referencedRelation: "quote_request_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_responses_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      receivables: {
        Row: {
          amount: number
          balance_amount: number | null
          bank_transaction_id: string | null
          category: string | null
          client_id: string
          cost_center_id: string | null
          created_at: string
          currency: string | null
          description: string
          due_date: string
          due_on_completion: boolean
          id: string
          invoice_id: string | null
          is_deposit: boolean | null
          issue_date: string
          issued_fiscal_document_id: string | null
          notes: string | null
          paid_amount: number | null
          payment_method: string | null
          reminder_sent_at: string | null
          service_order_id: string | null
          status: string | null
          sub_category: string | null
          updated_at: string
        }
        Insert: {
          amount: number
          balance_amount?: number | null
          bank_transaction_id?: string | null
          category?: string | null
          client_id: string
          cost_center_id?: string | null
          created_at?: string
          currency?: string | null
          description: string
          due_date: string
          due_on_completion?: boolean
          id?: string
          invoice_id?: string | null
          is_deposit?: boolean | null
          issue_date: string
          issued_fiscal_document_id?: string | null
          notes?: string | null
          paid_amount?: number | null
          payment_method?: string | null
          reminder_sent_at?: string | null
          service_order_id?: string | null
          status?: string | null
          sub_category?: string | null
          updated_at?: string
        }
        Update: {
          amount?: number
          balance_amount?: number | null
          bank_transaction_id?: string | null
          category?: string | null
          client_id?: string
          cost_center_id?: string | null
          created_at?: string
          currency?: string | null
          description?: string
          due_date?: string
          due_on_completion?: boolean
          id?: string
          invoice_id?: string | null
          is_deposit?: boolean | null
          issue_date?: string
          issued_fiscal_document_id?: string | null
          notes?: string | null
          paid_amount?: number | null
          payment_method?: string | null
          reminder_sent_at?: string | null
          service_order_id?: string | null
          status?: string | null
          sub_category?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "receivables_bank_transaction_id_fkey"
            columns: ["bank_transaction_id"]
            isOneToOne: false
            referencedRelation: "bank_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receivables_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receivables_cost_center_id_fkey"
            columns: ["cost_center_id"]
            isOneToOne: false
            referencedRelation: "cost_centers"
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
            foreignKeyName: "receivables_issued_fiscal_document_id_fkey"
            columns: ["issued_fiscal_document_id"]
            isOneToOne: false
            referencedRelation: "issued_fiscal_documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receivables_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receivables_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receivables_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receivables_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
        ]
      }
      reconciliation_memory: {
        Row: {
          candidate_kind: string | null
          client_id: string | null
          created_at: string
          hits: number
          id: string
          last_seen_at: string
          statement_key: string
        }
        Insert: {
          candidate_kind?: string | null
          client_id?: string | null
          created_at?: string
          hits?: number
          id?: string
          last_seen_at?: string
          statement_key: string
        }
        Update: {
          candidate_kind?: string | null
          client_id?: string | null
          created_at?: string
          hits?: number
          id?: string
          last_seen_at?: string
          statement_key?: string
        }
        Relationships: [
          {
            foreignKeyName: "reconciliation_memory_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
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
          is_default: boolean
          name: string
          user_id: string | null
        }
        Insert: {
          created_at?: string | null
          filter_config?: Json
          filter_type: string
          id?: string
          is_default?: boolean
          name: string
          user_id?: string | null
        }
        Update: {
          created_at?: string | null
          filter_config?: Json
          filter_type?: string
          id?: string
          is_default?: boolean
          name?: string
          user_id?: string | null
        }
        Relationships: []
      }
      service_cases: {
        Row: {
          actual_minutes: number | null
          asset_type: string | null
          client_id: string | null
          created_at: string
          features: Json
          id: string
          marina_id: string | null
          materials_cost: number | null
          outcome: string | null
          parts_used: Json | null
          planned_minutes: number | null
          service_id: string | null
          service_order_id: string
          unusable_reason: string | null
          updated_at: string
          usable: boolean
          variance_pct: number | null
          vessel_id: string | null
        }
        Insert: {
          actual_minutes?: number | null
          asset_type?: string | null
          client_id?: string | null
          created_at?: string
          features?: Json
          id?: string
          marina_id?: string | null
          materials_cost?: number | null
          outcome?: string | null
          parts_used?: Json | null
          planned_minutes?: number | null
          service_id?: string | null
          service_order_id: string
          unusable_reason?: string | null
          updated_at?: string
          usable?: boolean
          variance_pct?: number | null
          vessel_id?: string | null
        }
        Update: {
          actual_minutes?: number | null
          asset_type?: string | null
          client_id?: string | null
          created_at?: string
          features?: Json
          id?: string
          marina_id?: string | null
          materials_cost?: number | null
          outcome?: string | null
          parts_used?: Json | null
          planned_minutes?: number | null
          service_id?: string | null
          service_order_id?: string
          unusable_reason?: string | null
          updated_at?: string
          usable?: boolean
          variance_pct?: number | null
          vessel_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "service_cases_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_cases_marina_id_fkey"
            columns: ["marina_id"]
            isOneToOne: false
            referencedRelation: "marinas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_cases_service_id_fkey"
            columns: ["service_id"]
            isOneToOne: false
            referencedRelation: "services"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_cases_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_cases_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_cases_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_cases_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
          {
            foreignKeyName: "service_cases_vessel_id_fkey"
            columns: ["vessel_id"]
            isOneToOne: false
            referencedRelation: "vessels"
            referencedColumns: ["id"]
          },
        ]
      }
      service_order_expenses: {
        Row: {
          amount: number
          billable_to_client: boolean
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
          receipt_storage_path: string | null
          receipt_url: string | null
          reimbursed: boolean | null
          reimbursed_at: string | null
          reimbursed_payment_id: string | null
          service_order_id: string | null
          supplier_id: string | null
          technician_user_id: string | null
          updated_at: string | null
        }
        Insert: {
          amount: number
          billable_to_client?: boolean
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
          receipt_storage_path?: string | null
          receipt_url?: string | null
          reimbursed?: boolean | null
          reimbursed_at?: string | null
          reimbursed_payment_id?: string | null
          service_order_id?: string | null
          supplier_id?: string | null
          technician_user_id?: string | null
          updated_at?: string | null
        }
        Update: {
          amount?: number
          billable_to_client?: boolean
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
          receipt_storage_path?: string | null
          receipt_url?: string | null
          reimbursed?: boolean | null
          reimbursed_at?: string | null
          reimbursed_payment_id?: string | null
          service_order_id?: string | null
          supplier_id?: string | null
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
            foreignKeyName: "service_order_expenses_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_expenses_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_expenses_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
          {
            foreignKeyName: "service_order_expenses_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
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
          discount_amount: number
          discount_pct: number
          id: string
          line_total_cost: number
          line_total_sale: number
          notes: string | null
          product_id: string
          quantity: number
          serial_number: string | null
          service_order_id: string
          service_order_service_id: string | null
          source: string
          unit_cost_snapshot: number
          unit_sale_snapshot: number
          updated_at: string
          warranty_days: number | null
          warranty_expires_at: string | null
          warranty_months: number | null
        }
        Insert: {
          created_at?: string
          currency_snapshot?: string | null
          discount_amount?: number
          discount_pct?: number
          id?: string
          line_total_cost: number
          line_total_sale: number
          notes?: string | null
          product_id: string
          quantity: number
          serial_number?: string | null
          service_order_id: string
          service_order_service_id?: string | null
          source?: string
          unit_cost_snapshot: number
          unit_sale_snapshot: number
          updated_at?: string
          warranty_days?: number | null
          warranty_expires_at?: string | null
          warranty_months?: number | null
        }
        Update: {
          created_at?: string
          currency_snapshot?: string | null
          discount_amount?: number
          discount_pct?: number
          id?: string
          line_total_cost?: number
          line_total_sale?: number
          notes?: string | null
          product_id?: string
          quantity?: number
          serial_number?: string | null
          service_order_id?: string
          service_order_service_id?: string | null
          source?: string
          unit_cost_snapshot?: number
          unit_sale_snapshot?: number
          updated_at?: string
          warranty_days?: number | null
          warranty_expires_at?: string | null
          warranty_months?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "service_order_parts_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "product_availability"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_parts_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_parts_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_entradas_pendentes"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "service_order_parts_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_variancia"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "service_order_parts_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_parts_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_parts_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_parts_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
          {
            foreignKeyName: "service_order_parts_service_order_service_id_fkey"
            columns: ["service_order_service_id"]
            isOneToOne: false
            referencedRelation: "service_order_services"
            referencedColumns: ["id"]
          },
        ]
      }
      service_order_photos: {
        Row: {
          caption: string | null
          captured_live: boolean
          created_at: string
          id: string
          photo_type: string
          public_url: string
          service_order_id: string
          step_id: string | null
          storage_path: string
          uploaded_by: string | null
        }
        Insert: {
          caption?: string | null
          captured_live?: boolean
          created_at?: string
          id?: string
          photo_type?: string
          public_url: string
          service_order_id: string
          step_id?: string | null
          storage_path: string
          uploaded_by?: string | null
        }
        Update: {
          caption?: string | null
          captured_live?: boolean
          created_at?: string
          id?: string
          photo_type?: string
          public_url?: string
          service_order_id?: string
          step_id?: string | null
          storage_path?: string
          uploaded_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "service_order_photos_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_photos_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_photos_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_photos_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
          {
            foreignKeyName: "service_order_photos_step_id_fkey"
            columns: ["step_id"]
            isOneToOne: false
            referencedRelation: "service_order_steps"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_photos_uploaded_by_fkey"
            columns: ["uploaded_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      service_order_services: {
        Row: {
          billing_unit_snapshot: string
          created_at: string | null
          description_snapshot: string | null
          discount_amount: number
          discount_pct: number
          elapsed_minutes: number | null
          finished_at: string | null
          id: string
          line_total: number
          name_snapshot: string
          notes: string | null
          quantity: number
          service_id: string | null
          service_order_id: string
          service_system: string | null
          started_at: string | null
          technician_user_id: string | null
          unit_price_snapshot: number
          updated_at: string | null
          warranty_days: number | null
          warranty_expires_at: string | null
          warranty_months: number | null
        }
        Insert: {
          billing_unit_snapshot?: string
          created_at?: string | null
          description_snapshot?: string | null
          discount_amount?: number
          discount_pct?: number
          elapsed_minutes?: number | null
          finished_at?: string | null
          id?: string
          line_total?: number
          name_snapshot: string
          notes?: string | null
          quantity?: number
          service_id?: string | null
          service_order_id: string
          service_system?: string | null
          started_at?: string | null
          technician_user_id?: string | null
          unit_price_snapshot?: number
          updated_at?: string | null
          warranty_days?: number | null
          warranty_expires_at?: string | null
          warranty_months?: number | null
        }
        Update: {
          billing_unit_snapshot?: string
          created_at?: string | null
          description_snapshot?: string | null
          discount_amount?: number
          discount_pct?: number
          elapsed_minutes?: number | null
          finished_at?: string | null
          id?: string
          line_total?: number
          name_snapshot?: string
          notes?: string | null
          quantity?: number
          service_id?: string | null
          service_order_id?: string
          service_system?: string | null
          started_at?: string | null
          technician_user_id?: string | null
          unit_price_snapshot?: number
          updated_at?: string | null
          warranty_days?: number | null
          warranty_expires_at?: string | null
          warranty_months?: number | null
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
          {
            foreignKeyName: "service_order_services_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_services_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_services_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
          {
            foreignKeyName: "service_order_services_service_system_fkey"
            columns: ["service_system"]
            isOneToOne: false
            referencedRelation: "service_systems"
            referencedColumns: ["slug"]
          },
          {
            foreignKeyName: "service_order_services_service_system_fkey"
            columns: ["service_system"]
            isOneToOne: false
            referencedRelation: "v_service_systems_status"
            referencedColumns: ["slug"]
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
          {
            foreignKeyName: "service_order_signatures_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_signatures_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_signatures_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
        ]
      }
      service_order_steps: {
        Row: {
          actual_minutes: number | null
          ai_confidence: number | null
          ai_source: string | null
          approved_at: string | null
          approved_by: string | null
          assigned_user_id: string | null
          block: string | null
          block_key: string | null
          block_note: string | null
          blocked_note: string | null
          blocked_reason_code: string | null
          completed_at: string | null
          created_at: string
          detail: string | null
          id: string
          is_killer: boolean
          kind: string
          measure_unit: string | null
          measure_value: number | null
          mode: string
          na_reason: string | null
          notes: string | null
          origin: string
          requires_measure: string | null
          requires_photo: boolean
          seq: number
          service_order_id: string
          service_order_service_id: string | null
          standard_minutes: number | null
          started_at: string | null
          status: string
          template_id: string | null
          title: string
          updated_at: string
        }
        Insert: {
          actual_minutes?: number | null
          ai_confidence?: number | null
          ai_source?: string | null
          approved_at?: string | null
          approved_by?: string | null
          assigned_user_id?: string | null
          block?: string | null
          block_key?: string | null
          block_note?: string | null
          blocked_note?: string | null
          blocked_reason_code?: string | null
          completed_at?: string | null
          created_at?: string
          detail?: string | null
          id?: string
          is_killer?: boolean
          kind?: string
          measure_unit?: string | null
          measure_value?: number | null
          mode?: string
          na_reason?: string | null
          notes?: string | null
          origin?: string
          requires_measure?: string | null
          requires_photo?: boolean
          seq: number
          service_order_id: string
          service_order_service_id?: string | null
          standard_minutes?: number | null
          started_at?: string | null
          status?: string
          template_id?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          actual_minutes?: number | null
          ai_confidence?: number | null
          ai_source?: string | null
          approved_at?: string | null
          approved_by?: string | null
          assigned_user_id?: string | null
          block?: string | null
          block_key?: string | null
          block_note?: string | null
          blocked_note?: string | null
          blocked_reason_code?: string | null
          completed_at?: string | null
          created_at?: string
          detail?: string | null
          id?: string
          is_killer?: boolean
          kind?: string
          measure_unit?: string | null
          measure_value?: number | null
          mode?: string
          na_reason?: string | null
          notes?: string | null
          origin?: string
          requires_measure?: string | null
          requires_photo?: boolean
          seq?: number
          service_order_id?: string
          service_order_service_id?: string | null
          standard_minutes?: number | null
          started_at?: string | null
          status?: string
          template_id?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_order_steps_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_steps_assigned_user_id_fkey"
            columns: ["assigned_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_steps_blocked_reason_code_fkey"
            columns: ["blocked_reason_code"]
            isOneToOne: false
            referencedRelation: "work_stop_reasons"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "service_order_steps_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_steps_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_steps_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_steps_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
          {
            foreignKeyName: "service_order_steps_service_order_service_id_fkey"
            columns: ["service_order_service_id"]
            isOneToOne: false
            referencedRelation: "service_order_services"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_steps_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "service_step_templates"
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
            foreignKeyName: "service_order_technicians_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_technicians_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_order_technicians_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
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
          card_fee_amount: number
          card_fee_passthrough_enabled: boolean
          card_installments: number | null
          check_in_at: string | null
          check_out_at: string | null
          client_id: string
          client_signature_url: string | null
          commission_amount: number | null
          commission_rate: number | null
          commissioned_person: string | null
          commissioned_user_id: string | null
          contingency_pct: number | null
          converted_to_os_at: string | null
          created_at: string
          created_by: string | null
          currency: string | null
          custom_payment_installments: Json | null
          customer_buyer_name: string | null
          customer_po_number: string | null
          customer_visible_report: string | null
          diagnosis: string | null
          discount_amount: number | null
          discount_parts_pct: number
          discount_services_pct: number
          estimate_confidence: string | null
          estimated_hours: number | null
          extra_notes: string | null
          ferry_cost: number | null
          financial_notes: string | null
          grand_total: number | null
          hourly_rate: number | null
          id: string
          initial_findings: string | null
          internal_notes: string | null
          invoicing_status: string | null
          is_travel_billable: boolean
          labor_cost_total: number | null
          labor_hours_total: number | null
          marina_id: string | null
          operational_cost_total: number | null
          original_quote_amount: number | null
          parts_cost_total: number | null
          payment_condition_preset_id: string | null
          payment_conditions: string | null
          payment_method: string | null
          payment_method_preferred: string | null
          payment_status: string | null
          photos: Json | null
          priority: string
          problem_description: string | null
          quote_status: string | null
          quote_validity_date: string | null
          quote_validity_days: number | null
          reminder_sent_at: string | null
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
          survey_id: string | null
          tax_amount: number | null
          technician_count_for_travel: number | null
          technician_notes: string | null
          travel_cost_per_km: number | null
          travel_cost_total: number | null
          travel_distance_km: number | null
          travel_hours: number | null
          travel_type: string | null
          updated_at: string
          vessel_id: string
        }
        Insert: {
          cancellation_reason?: string | null
          cancelled_at?: string | null
          card_fee_amount?: number
          card_fee_passthrough_enabled?: boolean
          card_installments?: number | null
          check_in_at?: string | null
          check_out_at?: string | null
          client_id: string
          client_signature_url?: string | null
          commission_amount?: number | null
          commission_rate?: number | null
          commissioned_person?: string | null
          commissioned_user_id?: string | null
          contingency_pct?: number | null
          converted_to_os_at?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string | null
          custom_payment_installments?: Json | null
          customer_buyer_name?: string | null
          customer_po_number?: string | null
          customer_visible_report?: string | null
          diagnosis?: string | null
          discount_amount?: number | null
          discount_parts_pct?: number
          discount_services_pct?: number
          estimate_confidence?: string | null
          estimated_hours?: number | null
          extra_notes?: string | null
          ferry_cost?: number | null
          financial_notes?: string | null
          grand_total?: number | null
          hourly_rate?: number | null
          id?: string
          initial_findings?: string | null
          internal_notes?: string | null
          invoicing_status?: string | null
          is_travel_billable?: boolean
          labor_cost_total?: number | null
          labor_hours_total?: number | null
          marina_id?: string | null
          operational_cost_total?: number | null
          original_quote_amount?: number | null
          parts_cost_total?: number | null
          payment_condition_preset_id?: string | null
          payment_conditions?: string | null
          payment_method?: string | null
          payment_method_preferred?: string | null
          payment_status?: string | null
          photos?: Json | null
          priority?: string
          problem_description?: string | null
          quote_status?: string | null
          quote_validity_date?: string | null
          quote_validity_days?: number | null
          reminder_sent_at?: string | null
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
          survey_id?: string | null
          tax_amount?: number | null
          technician_count_for_travel?: number | null
          technician_notes?: string | null
          travel_cost_per_km?: number | null
          travel_cost_total?: number | null
          travel_distance_km?: number | null
          travel_hours?: number | null
          travel_type?: string | null
          updated_at?: string
          vessel_id: string
        }
        Update: {
          cancellation_reason?: string | null
          cancelled_at?: string | null
          card_fee_amount?: number
          card_fee_passthrough_enabled?: boolean
          card_installments?: number | null
          check_in_at?: string | null
          check_out_at?: string | null
          client_id?: string
          client_signature_url?: string | null
          commission_amount?: number | null
          commission_rate?: number | null
          commissioned_person?: string | null
          commissioned_user_id?: string | null
          contingency_pct?: number | null
          converted_to_os_at?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string | null
          custom_payment_installments?: Json | null
          customer_buyer_name?: string | null
          customer_po_number?: string | null
          customer_visible_report?: string | null
          diagnosis?: string | null
          discount_amount?: number | null
          discount_parts_pct?: number
          discount_services_pct?: number
          estimate_confidence?: string | null
          estimated_hours?: number | null
          extra_notes?: string | null
          ferry_cost?: number | null
          financial_notes?: string | null
          grand_total?: number | null
          hourly_rate?: number | null
          id?: string
          initial_findings?: string | null
          internal_notes?: string | null
          invoicing_status?: string | null
          is_travel_billable?: boolean
          labor_cost_total?: number | null
          labor_hours_total?: number | null
          marina_id?: string | null
          operational_cost_total?: number | null
          original_quote_amount?: number | null
          parts_cost_total?: number | null
          payment_condition_preset_id?: string | null
          payment_conditions?: string | null
          payment_method?: string | null
          payment_method_preferred?: string | null
          payment_status?: string | null
          photos?: Json | null
          priority?: string
          problem_description?: string | null
          quote_status?: string | null
          quote_validity_date?: string | null
          quote_validity_days?: number | null
          reminder_sent_at?: string | null
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
          survey_id?: string | null
          tax_amount?: number | null
          technician_count_for_travel?: number | null
          technician_notes?: string | null
          travel_cost_per_km?: number | null
          travel_cost_total?: number | null
          travel_distance_km?: number | null
          travel_hours?: number | null
          travel_type?: string | null
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
            foreignKeyName: "service_orders_survey_id_fkey"
            columns: ["survey_id"]
            isOneToOne: false
            referencedRelation: "service_surveys"
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
      service_step_blocks: {
        Row: {
          active: boolean
          applies_to_system: string | null
          applies_to_verb: string | null
          approved_at: string | null
          approved_by: string | null
          block_role: string
          created_at: string
          detail: string | null
          id: string
          is_killer: boolean
          kind: string
          measure_unit: string | null
          mode: string
          origin: string
          requires_measure: string | null
          requires_photo: boolean
          seq: number
          standard_minutes: number | null
          title: string
          updated_at: string
        }
        Insert: {
          active?: boolean
          applies_to_system?: string | null
          applies_to_verb?: string | null
          approved_at?: string | null
          approved_by?: string | null
          block_role: string
          created_at?: string
          detail?: string | null
          id?: string
          is_killer?: boolean
          kind?: string
          measure_unit?: string | null
          mode?: string
          origin?: string
          requires_measure?: string | null
          requires_photo?: boolean
          seq: number
          standard_minutes?: number | null
          title: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          applies_to_system?: string | null
          applies_to_verb?: string | null
          approved_at?: string | null
          approved_by?: string | null
          block_role?: string
          created_at?: string
          detail?: string | null
          id?: string
          is_killer?: boolean
          kind?: string
          measure_unit?: string | null
          mode?: string
          origin?: string
          requires_measure?: string | null
          requires_photo?: boolean
          seq?: number
          standard_minutes?: number | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_step_blocks_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "step_blocks_system_fk"
            columns: ["applies_to_system"]
            isOneToOne: false
            referencedRelation: "service_systems"
            referencedColumns: ["slug"]
          },
          {
            foreignKeyName: "step_blocks_system_fk"
            columns: ["applies_to_system"]
            isOneToOne: false
            referencedRelation: "v_service_systems_status"
            referencedColumns: ["slug"]
          },
          {
            foreignKeyName: "step_blocks_verb_fk"
            columns: ["applies_to_verb"]
            isOneToOne: false
            referencedRelation: "service_verbs"
            referencedColumns: ["slug"]
          },
          {
            foreignKeyName: "step_blocks_verb_fk"
            columns: ["applies_to_verb"]
            isOneToOne: false
            referencedRelation: "v_service_verbs_status"
            referencedColumns: ["slug"]
          },
        ]
      }
      service_step_templates: {
        Row: {
          active: boolean
          approved_at: string | null
          approved_by: string | null
          block: string | null
          created_at: string
          created_by: string | null
          detail: string | null
          id: string
          is_killer: boolean
          kind: string
          measure_unit: string | null
          mode: string
          origin: string
          requires_measure: string | null
          requires_part: boolean
          requires_photo: boolean
          role_hint: string | null
          seq: number
          service_id: string
          standard_minutes: number | null
          title: string
          updated_at: string
          version: number
        }
        Insert: {
          active?: boolean
          approved_at?: string | null
          approved_by?: string | null
          block?: string | null
          created_at?: string
          created_by?: string | null
          detail?: string | null
          id?: string
          is_killer?: boolean
          kind?: string
          measure_unit?: string | null
          mode?: string
          origin?: string
          requires_measure?: string | null
          requires_part?: boolean
          requires_photo?: boolean
          role_hint?: string | null
          seq: number
          service_id: string
          standard_minutes?: number | null
          title: string
          updated_at?: string
          version?: number
        }
        Update: {
          active?: boolean
          approved_at?: string | null
          approved_by?: string | null
          block?: string | null
          created_at?: string
          created_by?: string | null
          detail?: string | null
          id?: string
          is_killer?: boolean
          kind?: string
          measure_unit?: string | null
          mode?: string
          origin?: string
          requires_measure?: string | null
          requires_part?: boolean
          requires_photo?: boolean
          role_hint?: string | null
          seq?: number
          service_id?: string
          standard_minutes?: number | null
          title?: string
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "service_step_templates_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_step_templates_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_step_templates_service_id_fkey"
            columns: ["service_id"]
            isOneToOne: false
            referencedRelation: "services"
            referencedColumns: ["id"]
          },
        ]
      }
      service_survey_answers: {
        Row: {
          answer_json: Json | null
          answer_value: string | null
          answered_at: string
          id: string
          photo_path: string | null
          question_snapshot: string
          seq: number
          skipped_reason: string | null
          survey_id: string
          template_id: string | null
        }
        Insert: {
          answer_json?: Json | null
          answer_value?: string | null
          answered_at?: string
          id?: string
          photo_path?: string | null
          question_snapshot: string
          seq: number
          skipped_reason?: string | null
          survey_id: string
          template_id?: string | null
        }
        Update: {
          answer_json?: Json | null
          answer_value?: string | null
          answered_at?: string
          id?: string
          photo_path?: string | null
          question_snapshot?: string
          seq?: number
          skipped_reason?: string | null
          survey_id?: string
          template_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "service_survey_answers_survey_id_fkey"
            columns: ["survey_id"]
            isOneToOne: false
            referencedRelation: "service_surveys"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_survey_answers_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "service_survey_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      service_survey_templates: {
        Row: {
          active: boolean
          affects: string[] | null
          answer_type: string
          applies_to_system: string | null
          applies_to_verb: string | null
          approved_at: string | null
          approved_by: string | null
          ask_remotely: boolean
          branch_on: Json | null
          created_at: string
          created_by: string | null
          help_text: string | null
          id: string
          options: Json | null
          origin: string
          price_impact: string
          question: string
          seq: number
          service_id: string | null
          updated_at: string
          version: number
        }
        Insert: {
          active?: boolean
          affects?: string[] | null
          answer_type?: string
          applies_to_system?: string | null
          applies_to_verb?: string | null
          approved_at?: string | null
          approved_by?: string | null
          ask_remotely?: boolean
          branch_on?: Json | null
          created_at?: string
          created_by?: string | null
          help_text?: string | null
          id?: string
          options?: Json | null
          origin?: string
          price_impact?: string
          question: string
          seq: number
          service_id?: string | null
          updated_at?: string
          version?: number
        }
        Update: {
          active?: boolean
          affects?: string[] | null
          answer_type?: string
          applies_to_system?: string | null
          applies_to_verb?: string | null
          approved_at?: string | null
          approved_by?: string | null
          ask_remotely?: boolean
          branch_on?: Json | null
          created_at?: string
          created_by?: string | null
          help_text?: string | null
          id?: string
          options?: Json | null
          origin?: string
          price_impact?: string
          question?: string
          seq?: number
          service_id?: string | null
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "service_survey_templates_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_survey_templates_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_survey_templates_service_id_fkey"
            columns: ["service_id"]
            isOneToOne: false
            referencedRelation: "services"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "survey_tpl_system_fk"
            columns: ["applies_to_system"]
            isOneToOne: false
            referencedRelation: "service_systems"
            referencedColumns: ["slug"]
          },
          {
            foreignKeyName: "survey_tpl_system_fk"
            columns: ["applies_to_system"]
            isOneToOne: false
            referencedRelation: "v_service_systems_status"
            referencedColumns: ["slug"]
          },
          {
            foreignKeyName: "survey_tpl_verb_fk"
            columns: ["applies_to_verb"]
            isOneToOne: false
            referencedRelation: "service_verbs"
            referencedColumns: ["slug"]
          },
          {
            foreignKeyName: "survey_tpl_verb_fk"
            columns: ["applies_to_verb"]
            isOneToOne: false
            referencedRelation: "v_service_verbs_status"
            referencedColumns: ["slug"]
          },
        ]
      }
      service_surveys: {
        Row: {
          answered_at: string | null
          answered_by: string | null
          cases_used: Json | null
          client_id: string | null
          confidence: string | null
          confidence_rationale: string | null
          contingency_pct: number | null
          created_at: string
          created_by: string | null
          estimated_minutes_p50: number | null
          estimated_minutes_p80: number | null
          id: string
          materials_draft: Json | null
          mode: string
          questions_asked: number | null
          questions_planned: number | null
          service_id: string | null
          service_order_id: string | null
          share_token: string | null
          status: string
          trigger_reason: string
          updated_at: string
          vessel_id: string | null
        }
        Insert: {
          answered_at?: string | null
          answered_by?: string | null
          cases_used?: Json | null
          client_id?: string | null
          confidence?: string | null
          confidence_rationale?: string | null
          contingency_pct?: number | null
          created_at?: string
          created_by?: string | null
          estimated_minutes_p50?: number | null
          estimated_minutes_p80?: number | null
          id?: string
          materials_draft?: Json | null
          mode?: string
          questions_asked?: number | null
          questions_planned?: number | null
          service_id?: string | null
          service_order_id?: string | null
          share_token?: string | null
          status?: string
          trigger_reason: string
          updated_at?: string
          vessel_id?: string | null
        }
        Update: {
          answered_at?: string | null
          answered_by?: string | null
          cases_used?: Json | null
          client_id?: string | null
          confidence?: string | null
          confidence_rationale?: string | null
          contingency_pct?: number | null
          created_at?: string
          created_by?: string | null
          estimated_minutes_p50?: number | null
          estimated_minutes_p80?: number | null
          id?: string
          materials_draft?: Json | null
          mode?: string
          questions_asked?: number | null
          questions_planned?: number | null
          service_id?: string | null
          service_order_id?: string | null
          share_token?: string | null
          status?: string
          trigger_reason?: string
          updated_at?: string
          vessel_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "service_surveys_answered_by_fkey"
            columns: ["answered_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_surveys_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_surveys_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_surveys_service_id_fkey"
            columns: ["service_id"]
            isOneToOne: false
            referencedRelation: "services"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_surveys_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "service_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_surveys_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_surveys_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_surveys_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
          {
            foreignKeyName: "service_surveys_vessel_id_fkey"
            columns: ["vessel_id"]
            isOneToOne: false
            referencedRelation: "vessels"
            referencedColumns: ["id"]
          },
        ]
      }
      service_systems: {
        Row: {
          active: boolean
          created_at: string
          is_physical: boolean
          name: string
          short_name: string | null
          slug: string
          sort: number
          updated_at: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          is_physical?: boolean
          name: string
          short_name?: string | null
          slug: string
          sort?: number
          updated_at?: string
        }
        Update: {
          active?: boolean
          created_at?: string
          is_physical?: boolean
          name?: string
          short_name?: string | null
          slug?: string
          sort?: number
          updated_at?: string
        }
        Relationships: []
      }
      service_verbs: {
        Row: {
          active: boolean
          created_at: string
          is_fieldwork: boolean
          name: string
          slug: string
          sort: number
          updated_at: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          is_fieldwork?: boolean
          name: string
          slug: string
          sort?: number
          updated_at?: string
        }
        Update: {
          active?: boolean
          created_at?: string
          is_fieldwork?: boolean
          name?: string
          slug?: string
          sort?: number
          updated_at?: string
        }
        Relationships: []
      }
      services: {
        Row: {
          active: boolean | null
          billing_unit: string
          category: string | null
          classification_confidence: number | null
          classified_at: string | null
          classified_by: string | null
          created_at: string | null
          currency: string | null
          default_price: number | null
          default_warranty_days: number | null
          description: string | null
          field_factor: number
          id: string
          material_kit_product_id: string | null
          name: string
          requires_survey: boolean
          service_system: string | null
          service_verb: string | null
          standard_minutes: number | null
          standard_source: string | null
          supplies_cap: number | null
          supplies_pct: number | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          billing_unit?: string
          category?: string | null
          classification_confidence?: number | null
          classified_at?: string | null
          classified_by?: string | null
          created_at?: string | null
          currency?: string | null
          default_price?: number | null
          default_warranty_days?: number | null
          description?: string | null
          field_factor?: number
          id?: string
          material_kit_product_id?: string | null
          name: string
          requires_survey?: boolean
          service_system?: string | null
          service_verb?: string | null
          standard_minutes?: number | null
          standard_source?: string | null
          supplies_cap?: number | null
          supplies_pct?: number | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          billing_unit?: string
          category?: string | null
          classification_confidence?: number | null
          classified_at?: string | null
          classified_by?: string | null
          created_at?: string | null
          currency?: string | null
          default_price?: number | null
          default_warranty_days?: number | null
          description?: string | null
          field_factor?: number
          id?: string
          material_kit_product_id?: string | null
          name?: string
          requires_survey?: boolean
          service_system?: string | null
          service_verb?: string | null
          standard_minutes?: number | null
          standard_source?: string | null
          supplies_cap?: number | null
          supplies_pct?: number | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "services_material_kit_product_id_fkey"
            columns: ["material_kit_product_id"]
            isOneToOne: false
            referencedRelation: "product_availability"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "services_material_kit_product_id_fkey"
            columns: ["material_kit_product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "services_material_kit_product_id_fkey"
            columns: ["material_kit_product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_entradas_pendentes"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "services_material_kit_product_id_fkey"
            columns: ["material_kit_product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_variancia"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "services_system_fk"
            columns: ["service_system"]
            isOneToOne: false
            referencedRelation: "service_systems"
            referencedColumns: ["slug"]
          },
          {
            foreignKeyName: "services_system_fk"
            columns: ["service_system"]
            isOneToOne: false
            referencedRelation: "v_service_systems_status"
            referencedColumns: ["slug"]
          },
          {
            foreignKeyName: "services_verb_fk"
            columns: ["service_verb"]
            isOneToOne: false
            referencedRelation: "service_verbs"
            referencedColumns: ["slug"]
          },
          {
            foreignKeyName: "services_verb_fk"
            columns: ["service_verb"]
            isOneToOne: false
            referencedRelation: "v_service_verbs_status"
            referencedColumns: ["slug"]
          },
        ]
      }
      supplier_product_mappings: {
        Row: {
          created_at: string | null
          id: string
          internal_product_id: string | null
          supplier_description: string | null
          supplier_id: string | null
          supplier_sku: string
          updated_at: string | null
        }
        Insert: {
          created_at?: string | null
          id?: string
          internal_product_id?: string | null
          supplier_description?: string | null
          supplier_id?: string | null
          supplier_sku: string
          updated_at?: string | null
        }
        Update: {
          created_at?: string | null
          id?: string
          internal_product_id?: string | null
          supplier_description?: string | null
          supplier_id?: string | null
          supplier_sku?: string
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "supplier_product_mappings_internal_product_id_fkey"
            columns: ["internal_product_id"]
            isOneToOne: false
            referencedRelation: "product_availability"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_product_mappings_internal_product_id_fkey"
            columns: ["internal_product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_product_mappings_internal_product_id_fkey"
            columns: ["internal_product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_entradas_pendentes"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "supplier_product_mappings_internal_product_id_fkey"
            columns: ["internal_product_id"]
            isOneToOne: false
            referencedRelation: "v_estoque_variancia"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "supplier_product_mappings_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      suppliers: {
        Row: {
          active: boolean | null
          address_complement: string | null
          address_line_1: string | null
          address_number: string | null
          city: string | null
          cnpj_cpf: string | null
          communication_tone: string | null
          contact_name: string | null
          country: string | null
          created_at: string | null
          display_name: string | null
          email: string | null
          id: string
          name: string
          neighborhood: string | null
          notes: string | null
          opt_out_whatsapp: boolean
          payment_terms: string | null
          phone: string | null
          postal_code: string | null
          state: string | null
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
          communication_tone?: string | null
          contact_name?: string | null
          country?: string | null
          created_at?: string | null
          display_name?: string | null
          email?: string | null
          id?: string
          name: string
          neighborhood?: string | null
          notes?: string | null
          opt_out_whatsapp?: boolean
          payment_terms?: string | null
          phone?: string | null
          postal_code?: string | null
          state?: string | null
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
          communication_tone?: string | null
          contact_name?: string | null
          country?: string | null
          created_at?: string | null
          display_name?: string | null
          email?: string | null
          id?: string
          name?: string
          neighborhood?: string | null
          notes?: string | null
          opt_out_whatsapp?: boolean
          payment_terms?: string | null
          phone?: string | null
          postal_code?: string | null
          state?: string | null
          trade_name?: string | null
          updated_at?: string | null
          website?: string | null
        }
        Relationships: []
      }
      task_reminders: {
        Row: {
          channel: string
          created_at: string
          id: string
          remind_at: string
          sent_at: string | null
          task_id: string
        }
        Insert: {
          channel?: string
          created_at?: string
          id?: string
          remind_at: string
          sent_at?: string | null
          task_id: string
        }
        Update: {
          channel?: string
          created_at?: string
          id?: string
          remind_at?: string
          sent_at?: string | null
          task_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "task_reminders_task_id_fkey"
            columns: ["task_id"]
            isOneToOne: false
            referencedRelation: "agenda_tasks"
            referencedColumns: ["id"]
          },
        ]
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
          step_id: string | null
          stop_reason_code: string | null
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
          step_id?: string | null
          stop_reason_code?: string | null
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
          step_id?: string | null
          stop_reason_code?: string | null
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
            foreignKeyName: "time_entries_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "time_entries_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "time_entries_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
          {
            foreignKeyName: "time_entries_step_id_fkey"
            columns: ["step_id"]
            isOneToOne: false
            referencedRelation: "service_order_steps"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "time_entries_stop_reason_code_fkey"
            columns: ["stop_reason_code"]
            isOneToOne: false
            referencedRelation: "work_stop_reasons"
            referencedColumns: ["code"]
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
          asset_type: string | null
          battery_bank_summary: string | null
          beam_feet: number | null
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
          name: string
          navigation_electronics_summary: string | null
          propulsion_type: string | null
          shore_power_type: string | null
          updated_at: string
          year: number | null
        }
        Insert: {
          active?: boolean
          asset_type?: string | null
          battery_bank_summary?: string | null
          beam_feet?: number | null
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
          name: string
          navigation_electronics_summary?: string | null
          propulsion_type?: string | null
          shore_power_type?: string | null
          updated_at?: string
          year?: number | null
        }
        Update: {
          active?: boolean
          asset_type?: string | null
          battery_bank_summary?: string | null
          beam_feet?: number | null
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
          name?: string
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
          first_message: string | null
          id: string
          is_broadcast: boolean | null
          last_inbound_at: string | null
          last_message_at: string
          last_outbound_at: string | null
          linked_client_id: string | null
          message_count: number
          muted_at: string | null
          name: string | null
          notes: string | null
          phone_normalized: string
          status: string
          unread_count: number | null
          updated_at: string
        }
        Insert: {
          assigned_to?: string | null
          created_at?: string
          first_message?: string | null
          id?: string
          is_broadcast?: boolean | null
          last_inbound_at?: string | null
          last_message_at?: string
          last_outbound_at?: string | null
          linked_client_id?: string | null
          message_count?: number
          muted_at?: string | null
          name?: string | null
          notes?: string | null
          phone_normalized: string
          status?: string
          unread_count?: number | null
          updated_at?: string
        }
        Update: {
          assigned_to?: string | null
          created_at?: string
          first_message?: string | null
          id?: string
          is_broadcast?: boolean | null
          last_inbound_at?: string | null
          last_message_at?: string
          last_outbound_at?: string | null
          linked_client_id?: string | null
          message_count?: number
          muted_at?: string | null
          name?: string | null
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
          supplier_id: string | null
          wa_message_id: string | null
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
          supplier_id?: string | null
          wa_message_id?: string | null
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
          supplier_id?: string | null
          wa_message_id?: string | null
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
          {
            foreignKeyName: "whatsapp_messages_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "whatsapp_messages_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "whatsapp_messages_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
          },
          {
            foreignKeyName: "whatsapp_messages_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
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
          document_url: string | null
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
          document_url?: string | null
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
          document_url?: string | null
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
          {
            foreignKeyName: "whatsapp_scheduled_sends_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_labor_variance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "whatsapp_scheduled_sends_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "v_service_order_margin"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "whatsapp_scheduled_sends_service_order_id_fkey"
            columns: ["service_order_id"]
            isOneToOne: false
            referencedRelation: "vw_os_profitability"
            referencedColumns: ["os_id"]
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
      whatsapp_status_scheduled: {
        Row: {
          background_color: string | null
          content_type: string
          created_at: string
          created_by: string | null
          error_message: string | null
          font_type: number | null
          id: string
          media_url: string | null
          scheduled_at: string
          status: string
          text_content: string | null
          updated_at: string
          zapi_message_id: string | null
        }
        Insert: {
          background_color?: string | null
          content_type: string
          created_at?: string
          created_by?: string | null
          error_message?: string | null
          font_type?: number | null
          id?: string
          media_url?: string | null
          scheduled_at: string
          status?: string
          text_content?: string | null
          updated_at?: string
          zapi_message_id?: string | null
        }
        Update: {
          background_color?: string | null
          content_type?: string
          created_at?: string
          created_by?: string | null
          error_message?: string | null
          font_type?: number | null
          id?: string
          media_url?: string | null
          scheduled_at?: string
          status?: string
          text_content?: string | null
          updated_at?: string
          zapi_message_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "whatsapp_status_scheduled_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
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
      work_stop_reasons: {
        Row: {
          active: boolean
          category: string
          code: string
          counts_as_billable: boolean
          label: string
          sort: number
        }
        Insert: {
          active?: boolean
          category: string
          code: string
          counts_as_billable?: boolean
          label: string
          sort?: number
        }
        Update: {
          active?: boolean
          category?: string
          code?: string
          counts_as_billable?: boolean
          label?: string
          sort?: number
        }
        Relationships: []
      }
    }
    Views: {
      erp_open_loop_facts: {
        Row: {
          detail: string | null
          due_at: string | null
          entity_id: string | null
          entity_type: string | null
          kind: string | null
          loop_key: string | null
          priority: string | null
          ref_id: string | null
          ref_table: string | null
          service_order_id: string | null
          title: string | null
        }
        Relationships: []
      }
      product_availability: {
        Row: {
          available_quantity: number | null
          id: string | null
          name: string | null
          reserved_quantity: number | null
          sku: string | null
          stock_quantity: number | null
          unit: string | null
        }
        Insert: {
          available_quantity?: never
          id?: string | null
          name?: string | null
          reserved_quantity?: number | null
          sku?: string | null
          stock_quantity?: number | null
          unit?: string | null
        }
        Update: {
          available_quantity?: never
          id?: string | null
          name?: string | null
          reserved_quantity?: number | null
          sku?: string | null
          stock_quantity?: number | null
          unit?: string | null
        }
        Relationships: []
      }
      unidentified_contacts: {
        Row: {
          mensagens: number | null
          phone_normalized: string | null
          ultima_frase: string | null
          ultima_mensagem: string | null
        }
        Relationships: []
      }
      v_estoque_entradas_pendentes: {
        Row: {
          brand: string | null
          custo_estimado: number | null
          is_equipment: boolean | null
          name: string | null
          product_id: string | null
          saldo: number | null
          sku: string | null
          ultimo_alerta: string | null
          unidades_a_lancar: number | null
          vezes_que_ficou_negativo: number | null
        }
        Insert: {
          brand?: string | null
          custo_estimado?: never
          is_equipment?: boolean | null
          name?: string | null
          product_id?: string | null
          saldo?: number | null
          sku?: string | null
          ultimo_alerta?: never
          unidades_a_lancar?: never
          vezes_que_ficou_negativo?: never
        }
        Update: {
          brand?: string | null
          custo_estimado?: never
          is_equipment?: boolean | null
          name?: string | null
          product_id?: string | null
          saldo?: number | null
          sku?: string | null
          ultimo_alerta?: never
          unidades_a_lancar?: never
          vezes_que_ficou_negativo?: never
        }
        Relationships: []
      }
      v_estoque_variancia: {
        Row: {
          ajustes: number | null
          baixas: number | null
          brand: string | null
          compras: number | null
          contradicao: string | null
          delta_desde_backup: number | null
          disponivel: number | null
          estornos: number | null
          name: string | null
          product_id: string | null
          qtd_movimentos: number | null
          reservado: number | null
          saldo_atual: number | null
          saldo_no_backup: number | null
          sale_price: number | null
          sku: string | null
          valor_em_risco: number | null
        }
        Relationships: []
      }
      v_service_order_labor_variance: {
        Row: {
          client_id: string | null
          id: string | null
          orcado_min: number | null
          padrao_roteiro_min: number | null
          passos: number | null
          passos_feitos: number | null
          passos_na: number | null
          passos_travados: number | null
          real_min: number | null
          service_order_number: string | null
          status: string | null
          variacao_pct: number | null
        }
        Relationships: [
          {
            foreignKeyName: "service_orders_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      v_service_order_margin: {
        Row: {
          client_id: string | null
          custo_mao_de_obra: number | null
          custo_material: number | null
          custo_material_extra: number | null
          faturado: number | null
          horas_reais: number | null
          id: string | null
          margem_pct: number | null
          margem_reais: number | null
          service_order_number: string | null
          status: string | null
          taxa_materiais: number | null
        }
        Relationships: [
          {
            foreignKeyName: "service_orders_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      v_service_systems_status: {
        Row: {
          active: boolean | null
          is_physical: boolean | null
          name: string | null
          passos_abertura: number | null
          passos_fechamento: number | null
          perguntas: number | null
          servicos: number | null
          short_name: string | null
          slug: string | null
          sort: number | null
        }
        Insert: {
          active?: boolean | null
          is_physical?: boolean | null
          name?: string | null
          passos_abertura?: never
          passos_fechamento?: never
          perguntas?: never
          servicos?: never
          short_name?: string | null
          slug?: string | null
          sort?: number | null
        }
        Update: {
          active?: boolean | null
          is_physical?: boolean | null
          name?: string | null
          passos_abertura?: never
          passos_fechamento?: never
          perguntas?: never
          servicos?: never
          short_name?: string | null
          slug?: string | null
          sort?: number | null
        }
        Relationships: []
      }
      v_service_verbs_status: {
        Row: {
          active: boolean | null
          is_fieldwork: boolean | null
          name: string | null
          passos_corpo: number | null
          perguntas: number | null
          servicos: number | null
          slug: string | null
          sort: number | null
        }
        Insert: {
          active?: boolean | null
          is_fieldwork?: boolean | null
          name?: string | null
          passos_corpo?: never
          perguntas?: never
          servicos?: never
          slug?: string | null
          sort?: number | null
        }
        Update: {
          active?: boolean | null
          is_fieldwork?: boolean | null
          name?: string | null
          passos_corpo?: never
          perguntas?: never
          servicos?: never
          slug?: string | null
          sort?: number | null
        }
        Relationships: []
      }
      vw_os_profitability: {
        Row: {
          client_name: string | null
          commission_cost: number | null
          created_at: string | null
          finished_at: string | null
          gross_profit: number | null
          net_margin_percent: number | null
          net_profit: number | null
          operational_cost: number | null
          os_id: string | null
          parts_cost: number | null
          revenue: number | null
          service_order_number: string | null
          status: string | null
          travel_cost: number | null
        }
        Relationships: []
      }
    }
    Functions: {
      ai_op_can_approve: {
        Args: { _action: string; _user_id: string }
        Returns: boolean
      }
      ai_op_can_reject: {
        Args: { _pending_action_id: string; _user_id: string }
        Returns: boolean
      }
      apply_service_material_kit: {
        Args: { p_service_id: string; p_service_order_id: string }
        Returns: Json
      }
      archive_old_fiscal_drafts: { Args: { p_days?: number }; Returns: number }
      backfill_message_identity: {
        Args: { p_limit?: number }
        Returns: {
          linked_clients: number
          linked_leads: number
          linked_suppliers: number
        }[]
      }
      bi_margin_by_category: {
        Args: { _since?: string }
        Returns: {
          category: string
          cost: number
          revenue: number
        }[]
      }
      bi_revenue_by_brand: {
        Args: { _brand?: string; _since?: string }
        Returns: {
          brand: string
          cost: number
          qty: number
          revenue: number
        }[]
      }
      bi_top_clients: {
        Args: { _limit?: number; _since?: string }
        Returns: {
          client_id: string
          name: string
          os_count: number
          revenue: number
        }[]
      }
      cancel_service_order_cascade: {
        Args: { p_reason: string; p_service_order_id: string }
        Returns: Json
      }
      classify_service_text: { Args: { p_texto: string }; Returns: Json }
      compose_route_for_service: {
        Args: { p_service_id: string }
        Returns: {
          block: string
          detail: string
          is_killer: boolean
          kind: string
          measure_unit: string
          mode: string
          origem_bloco: string
          requires_measure: string
          requires_photo: boolean
          seq: number
          standard_minutes: number
          title: string
        }[]
      }
      compose_survey_for_service: {
        Args: { p_mode?: string; p_service_id: string }
        Returns: {
          answer_type: string
          ask_remotely: boolean
          help_text: string
          id: string
          options: Json
          origem: string
          price_impact: string
          question: string
          seq: number
        }[]
      }
      compute_next_run: {
        Args: {
          _day_of_month: number
          _days_of_week: number[]
          _from: string
          _recurrence_type: string
        }
        Returns: string
      }
      confirm_nfe_import: {
        Args: {
          p_manual_mappings?: Json
          p_note_id: string
          p_purchase_order_id?: string
          p_supplier_id?: string
        }
        Returns: Json
      }
      convert_external_quote_to_so: {
        Args: { _quote_id: string }
        Returns: string
      }
      estimate_from_cases: {
        Args: { p_min_casos?: number; p_service_id: string }
        Returns: Json
      }
      frase_legivel: { Args: { p_texto: string }; Returns: string }
      generate_service_order_steps: {
        Args: { p_service_order_id: string }
        Returns: number
      }
      get_agenda_conflicts: {
        Args: {
          p_end: string
          p_exclude_so?: string
          p_exclude_task?: string
          p_start: string
          p_user_id: string
        }
        Returns: {
          ends_at: string
          label: string
          ref_id: string
          source: string
          starts_at: string
        }[]
      }
      get_entity_open_loops: {
        Args: { p_entity_id: string; p_entity_type: string; p_limit?: number }
        Returns: {
          atrasado: boolean
          detail: string
          due_at: string
          evidence: string
          id: string
          kind: string
          last_seen_at: string
          mentions: number
          opened_at: string
          priority: string
          service_order_id: string
          service_order_number: string
          source: string
          title: string
        }[]
      }
      get_promo_candidates: {
        Args: { p_limit?: number }
        Returns: {
          available: number
          cost_price: number
          days_since_sold: number
          has_image: boolean
          image_url: string
          last_sold_at: string
          margin_pct: number
          name: string
          product_id: string
          reserved_quantity: number
          sale_price: number
          score: number
          sku: string
          stock_quantity: number
        }[]
      }
      increment_finance_rule_usage: {
        Args: { rule_id: string }
        Returns: undefined
      }
      is_admin: { Args: { _user_id: string }; Returns: boolean }
      is_admin_or_financial: { Args: { _user_id: string }; Returns: boolean }
      is_external_seller: { Args: { _user_id: string }; Returns: boolean }
      lines_missing_system: {
        Args: { p_service_order_id: string }
        Returns: {
          line_id: string
          service_name: string
          service_verb: string
        }[]
      }
      log_app_error: {
        Args: {
          p_action?: string
          p_context?: string
          p_details?: Json
          p_level?: string
          p_message: string
          p_source: string
        }
        Returns: string
      }
      match_nfe_item: {
        Args: {
          p_barcode: string
          p_description: string
          p_manual_product_id?: string
          p_sku_supplier: string
          p_supplier_id: string
        }
        Returns: {
          match_reason: string
          product_id: string
        }[]
      }
      next_document_number: { Args: never; Returns: number }
      next_fiscal_number: {
        Args: {
          p_document_type: string
          p_environment?: string
          p_series?: number
        }
        Returns: number
      }
      normalize_alias: { Args: { _s: string }; Returns: string }
      normalize_product_text: { Args: { t: string }; Returns: string }
      preview_nfe_import: {
        Args: {
          p_manual_mappings?: Json
          p_note_id: string
          p_supplier_id?: string
        }
        Returns: Json
      }
      produce_composed_product: {
        Args: { p_parent: string; p_qty?: number }
        Returns: Json
      }
      prune_app_error_logs: { Args: { p_days?: number }; Returns: number }
      recalc_po_total: { Args: { p_po_id: string }; Returns: undefined }
      recalc_so_totals: { Args: { so_id: string }; Returns: undefined }
      receive_po: {
        Args: { p_due_days?: number; p_items: Json; p_po_id: string }
        Returns: Json
      }
      recompute_product_cost: { Args: { _parent: string }; Returns: undefined }
      recompute_product_reservations: {
        Args: { _product: string }
        Returns: undefined
      }
      reconcile_stock_to_v2: { Args: never; Returns: undefined }
      record_conversation_loop: {
        Args: {
          p_detail?: string
          p_due_at?: string
          p_entity_id: string
          p_entity_type: string
          p_evidence?: string
          p_evidence_at?: string
          p_kind: string
          p_loop_key: string
          p_priority?: string
          p_service_order_id?: string
          p_source_message_id?: string
          p_title: string
        }
        Returns: {
          criado: boolean
          loop_id: string
        }[]
      }
      refresh_entity_open_loops: {
        Args: never
        Returns: {
          abertos: number
          fechados: number
        }[]
      }
      register_deposit_and_convert: {
        Args: {
          p_amount: number
          p_balance_installments?: Json
          p_card_fee_percent?: number
          p_create_collections?: boolean
          p_notes?: string
          p_payment_date: string
          p_payment_method: string
          p_service_order_id: string
        }
        Returns: Json
      }
      register_payment_and_update_balance: {
        Args: {
          p_amount: number
          p_card_fee_percent: number
          p_installments: number
          p_net_amount: number
          p_notes: string
          p_payable_id: string
          p_payment_date: string
          p_payment_method: string
          p_receivable_id: string
        }
        Returns: Json
      }
      remember_reconciliation: {
        Args: {
          p_candidate_kind?: string
          p_client_id: string
          p_statement_key: string
        }
        Returns: undefined
      }
      resolve_contact_identity: {
        Args: { p_phone: string }
        Returns: {
          entity_id: string
          entity_name: string
          kind: string
        }[]
      }
      resolve_practiced_price: {
        Args: { p_client_id?: string; p_product_id: string }
        Returns: {
          price: number
          ref_date: string
          source: string
        }[]
      }
      revert_nfe_import: { Args: { p_note_id: string }; Returns: Json }
      search_products_trgm: {
        Args: { _lim?: number; _term: string }
        Returns: {
          brand: string
          cost_price: number
          id: string
          name: string
          sale_price: number
          sim: number
          sku: string
        }[]
      }
      service_system_label: { Args: { p_system: string }; Returns: string }
      set_fiscal_next_number: {
        Args: {
          p_document_type: string
          p_environment: string
          p_next_number: number
          p_series: number
        }
        Returns: number
      }
      settle_nfe_stock_and_receivable: {
        Args: { p_document_id: string; p_installments?: Json }
        Returns: Json
      }
      share_token_da_requisicao: { Args: never; Returns: string }
      should_survey_service: {
        Args: {
          p_client_id?: string
          p_service_id: string
          p_valor?: number
          p_vessel_id?: string
        }
        Returns: Json
      }
      show_limit: { Args: never; Returns: number }
      show_trgm: { Args: { "": string }; Returns: string[] }
      stock_model_v2_on: { Args: never; Returns: boolean }
      touch_open_loop: {
        Args: {
          p_evidence?: string
          p_evidence_at?: string
          p_loop_id: string
          p_source_message_id?: string
        }
        Returns: number
      }
      wa_extract_body_text: { Args: { p: Json }; Returns: string }
      wa_extract_message_type: { Args: { p: Json }; Returns: string }
      wa_normalize_phone: { Args: { raw: string }; Returns: string }
      whatsapp_pending_inbox: {
        Args: { _limit?: number; _since?: string }
        Returns: {
          contato: string
          is_client: boolean
          last_body: string
          last_inbound_at: string
          last_outbound_at: string
          phone: string
          unread_count: number
        }[]
      }
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
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const
