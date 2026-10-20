-- Create system_metrics table for API performance telemetry
CREATE TABLE IF NOT EXISTS public.system_metrics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  metric_type VARCHAR(50) NOT NULL,
  metric_value FLOAT NOT NULL,
  endpoint VARCHAR(255),
  status_code INT,
  response_time_ms INT,
  error_message TEXT,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  CONSTRAINT valid_metric_type CHECK (metric_type IN ('response_time', 'error_rate', 'request_count'))
);

-- Create indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_system_metrics_type ON public.system_metrics(metric_type);
CREATE INDEX IF NOT EXISTS idx_system_metrics_created_at ON public.system_metrics(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_system_metrics_endpoint ON public.system_metrics(endpoint, created_at DESC);

-- Enable RLS
ALTER TABLE public.system_metrics ENABLE ROW LEVEL SECURITY;

-- Admins can read metrics
CREATE POLICY system_metrics_read_admin ON public.system_metrics
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- System can insert metrics
CREATE POLICY system_metrics_insert ON public.system_metrics
  FOR INSERT
  WITH CHECK (auth.role() = 'service_role');

COMMENT ON TABLE public.system_metrics IS 'Tracks API performance metrics and error rates';
COMMENT ON COLUMN public.system_metrics.metric_type IS 'Type of metric: response_time, error_rate, request_count';
COMMENT ON COLUMN public.system_metrics.response_time_ms IS 'Response time in milliseconds';
