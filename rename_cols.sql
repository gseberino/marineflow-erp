ALTER TABLE public.clients RENAME COLUMN full_name_or_company_name TO name;
ALTER TABLE public.external_quote_leads RENAME COLUMN full_name_or_company_name TO name;

ALTER TABLE public.suppliers RENAME COLUMN supplier_name TO name;
ALTER TABLE public.suppliers RENAME COLUMN contact_phone TO phone;
ALTER TABLE public.suppliers RENAME COLUMN contact_email TO email;

ALTER TABLE public.marinas RENAME COLUMN marina_name TO name;
ALTER TABLE public.marinas RENAME COLUMN contact_phone TO phone;
ALTER TABLE public.marinas RENAME COLUMN contact_email TO email;

ALTER TABLE public.products RENAME COLUMN product_name TO name;
ALTER TABLE public.services RENAME COLUMN service_name TO name;

ALTER TABLE public.whatsapp_leads RENAME COLUMN display_name TO name;

ALTER TABLE public.external_quote_parts RENAME COLUMN product_name_snapshot TO name_snapshot;

ALTER TABLE public.service_order_services RENAME COLUMN service_name_snapshot TO name_snapshot;
ALTER TABLE public.external_quote_services RENAME COLUMN service_name_snapshot TO name_snapshot;

ALTER TABLE public.collections RENAME COLUMN contact_phone TO phone;
