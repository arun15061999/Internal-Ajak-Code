-- Create integration_configs table for managing integration configurations
CREATE TABLE IF NOT EXISTS public.integration_configs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  integration_name VARCHAR(100) NOT NULL UNIQUE,
  is_enabled BOOLEAN NOT NULL DEFAULT false,
  api_key_encrypted TEXT,
  api_secret_encrypted TEXT,
  config JSONB DEFAULT '{}',
  webhook_url VARCHAR(500),
  webhook_secret_encrypted TEXT,
  health_check_url VARCHAR(500),
  health_check_interval_minutes INT DEFAULT 5,
  last_health_check TIMESTAMP,
  last_error_message TEXT,
  retry_count INT DEFAULT 0,
  max_retries INT DEFAULT 3,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  updated_by UUID REFERENCES public.users(id) ON DELETE SET NULL
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_integration_configs_name ON public.integration_configs(integration_name);
CREATE INDEX IF NOT EXISTS idx_integration_configs_enabled ON public.integration_configs(is_enabled);
CREATE INDEX IF NOT EXISTS idx_integration_configs_updated_at ON public.integration_configs(updated_at DESC);

-- Enable RLS
ALTER TABLE public.integration_configs ENABLE ROW LEVEL SECURITY;

-- Admins can read all configs
CREATE POLICY integration_configs_read_admin ON public.integration_configs
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Admins can manage configs
CREATE POLICY integration_configs_manage_admin ON public.integration_configs
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

COMMENT ON TABLE public.integration_configs IS 'Stores configuration and credentials for all integrations';
COMMENT ON COLUMN public.integration_configs.is_enabled IS 'Whether the integration is currently active';
COMMENT ON COLUMN public.integration_configs.config IS 'Additional configuration stored as JSON';
COMMENT ON COLUMN public.integration_configs.health_check_interval_minutes IS 'How often to check integration health';
