-- Create security_audit_logs table for tracking security events
CREATE TABLE IF NOT EXISTS public.security_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID,
  user_email VARCHAR(255),
  event_type VARCHAR(100) NOT NULL,
  severity VARCHAR(50) DEFAULT 'info',
  details JSONB,
  ip_address VARCHAR(45),
  user_agent VARCHAR(500),
  successful BOOLEAN DEFAULT false,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Create indexes for common queries
CREATE INDEX IF NOT EXISTS idx_security_audit_logs_event_type ON public.security_audit_logs(event_type);
CREATE INDEX IF NOT EXISTS idx_security_audit_logs_created_at ON public.security_audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_security_audit_logs_user_id ON public.security_audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_security_audit_logs_severity ON public.security_audit_logs(severity);
CREATE INDEX IF NOT EXISTS idx_security_audit_logs_ip ON public.security_audit_logs(ip_address);

-- Enable RLS
ALTER TABLE public.security_audit_logs ENABLE ROW LEVEL SECURITY;

-- Only admins can read security logs
CREATE POLICY security_audit_logs_read ON public.security_audit_logs
  FOR SELECT
  USING (
    auth.role() = 'authenticated' AND
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- System can insert security logs
CREATE POLICY security_audit_logs_insert ON public.security_audit_logs
  FOR INSERT
  WITH CHECK (true);

-- Prevent deletion/updates
CREATE POLICY security_audit_logs_no_delete ON public.security_audit_logs
  FOR DELETE
  USING (false);

CREATE POLICY security_audit_logs_no_update ON public.security_audit_logs
  FOR UPDATE
  USING (false);

COMMENT ON TABLE public.security_audit_logs IS 'Security events like failed logins, permission changes, etc.';
COMMENT ON COLUMN public.security_audit_logs.event_type IS 'failed_login, successful_login, permission_change, account_locked, etc.';
COMMENT ON COLUMN public.security_audit_logs.severity IS 'info, warning, error, critical';
