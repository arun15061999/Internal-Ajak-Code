-- Create integration_health table for tracking integration status
CREATE TABLE IF NOT EXISTS public.integration_health (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  integration_name VARCHAR(100) NOT NULL UNIQUE,
  status VARCHAR(50) NOT NULL DEFAULT 'unknown',
  last_sync_at TIMESTAMP,
  error_count INT DEFAULT 0,
  success_count INT DEFAULT 0,
  uptime FLOAT DEFAULT 100.0,
  latency INT DEFAULT 0,
  message TEXT,
  details JSONB,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Create indexes for common queries
CREATE INDEX IF NOT EXISTS idx_integration_health_name ON public.integration_health(integration_name);
CREATE INDEX IF NOT EXISTS idx_integration_health_status ON public.integration_health(status);
CREATE INDEX IF NOT EXISTS idx_integration_health_updated_at ON public.integration_health(updated_at DESC);

-- Enable RLS
ALTER TABLE public.integration_health ENABLE ROW LEVEL SECURITY;

-- Everyone can read integration health
CREATE POLICY integration_health_read ON public.integration_health
  FOR SELECT
  USING (true);

-- System can insert/update integration health
CREATE POLICY integration_health_write ON public.integration_health
  FOR INSERT
  WITH CHECK (
    auth.role() = 'service_role'
    OR EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY integration_health_update ON public.integration_health
  FOR UPDATE
  USING (
    auth.role() = 'authenticated' AND
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

COMMENT ON TABLE public.integration_health IS 'Current health status of all integrated services';
COMMENT ON COLUMN public.integration_health.status IS 'healthy, warning, error, unknown';
COMMENT ON COLUMN public.integration_health.uptime IS 'Uptime percentage (0-100)';
COMMENT ON COLUMN public.integration_health.latency IS 'Average response time in milliseconds';
