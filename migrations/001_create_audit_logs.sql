-- Create audit_logs table for tracking all mutations
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  action VARCHAR(50) NOT NULL,
  resource_type VARCHAR(50) NOT NULL,
  resource_id VARCHAR(255),
  resource_name VARCHAR(255),
  changes JSONB,
  ip_address VARCHAR(45),
  user_agent VARCHAR(500),
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Create indexes for common queries
CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON public.audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_resource ON public.audit_logs(resource_type, resource_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON public.audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON public.audit_logs(action);

-- Enable RLS
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- Only admins can read audit logs
CREATE POLICY audit_logs_read ON public.audit_logs
  FOR SELECT
  USING (
    auth.role() = 'authenticated' AND
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- System can insert audit logs
CREATE POLICY audit_logs_insert ON public.audit_logs
  FOR INSERT
  WITH CHECK (true);

-- Prevent deletion/updates of audit logs
CREATE POLICY audit_logs_no_delete ON public.audit_logs
  FOR DELETE
  USING (false);

CREATE POLICY audit_logs_no_update ON public.audit_logs
  FOR UPDATE
  USING (false);

COMMENT ON TABLE public.audit_logs IS 'Audit trail of all user mutations for compliance and debugging';
COMMENT ON COLUMN public.audit_logs.action IS 'CREATE, UPDATE, DELETE, READ';
COMMENT ON COLUMN public.audit_logs.changes IS 'JSON object showing before/after values';
