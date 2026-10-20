-- Create webhook_deliveries table for tracking webhook delivery attempts
CREATE TABLE IF NOT EXISTS public.webhook_deliveries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  webhook_id UUID,
  event_type VARCHAR(100) NOT NULL,
  payload JSONB NOT NULL,
  status VARCHAR(50) NOT NULL DEFAULT 'pending',
  attempts INT DEFAULT 0,
  max_attempts INT DEFAULT 5,
  error_message TEXT,
  latency INT,
  response_status INT,
  response_body TEXT,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Create indexes for common queries
CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_status ON public.webhook_deliveries(status);
CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_created_at ON public.webhook_deliveries(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_event_type ON public.webhook_deliveries(event_type);
CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_webhook_id ON public.webhook_deliveries(webhook_id);
CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_created_status ON public.webhook_deliveries(created_at DESC, status);

-- Enable RLS
ALTER TABLE public.webhook_deliveries ENABLE ROW LEVEL SECURITY;

-- Only admins can read webhook deliveries
CREATE POLICY webhook_deliveries_read ON public.webhook_deliveries
  FOR SELECT
  USING (
    auth.role() = 'authenticated' AND
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- System can insert webhook deliveries
CREATE POLICY webhook_deliveries_insert ON public.webhook_deliveries
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.webhooks w
      WHERE w.id = webhook_deliveries.webhook_id
        AND (
          auth.role() = 'service_role'
          OR (
            auth.uid() IS NOT NULL
            AND w.created_by = auth.uid()
          )
        )
    )
  );

-- Only system/admin can update
CREATE POLICY webhook_deliveries_update ON public.webhook_deliveries
  FOR UPDATE
  USING (
    auth.role() = 'authenticated' AND
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

COMMENT ON TABLE public.webhook_deliveries IS 'Log of all webhook delivery attempts for monitoring and debugging';
COMMENT ON COLUMN public.webhook_deliveries.status IS 'pending, delivered, failed, retrying';
COMMENT ON COLUMN public.webhook_deliveries.latency IS 'Response time in milliseconds';
