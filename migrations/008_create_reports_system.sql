-- Migration: Create reporting system tables
-- Purpose: Enable admins to build, schedule, and export reports

-- ============================================================================
-- Table 1: reports
-- Purpose: Store report configurations and templates
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.reports (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id          UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  title             VARCHAR(200) NOT NULL,
  description       TEXT,
  report_type       VARCHAR(50) NOT NULL
                    CHECK (report_type IN ('enrollments', 'revenue', 'feedback', 'progress', 'engagement', 'custom')),
  filters           JSONB, -- { date_range: {start, end}, course_id, status, role, etc }
  selected_columns  TEXT[], -- which columns to include in export
  schedule          VARCHAR(50) DEFAULT 'once'
                    CHECK (schedule IN ('once', 'daily', 'weekly', 'monthly')),
  schedule_day_of_week VARCHAR(20), -- 'monday', 'tuesday', etc for weekly
  schedule_day_of_month INTEGER CHECK (schedule_day_of_month BETWEEN 1 AND 31), -- 1-31 for monthly
  next_run_at       TIMESTAMP,
  last_run_at       TIMESTAMP,
  recipients_email  TEXT[], -- email list for scheduled reports
  is_active         BOOLEAN NOT NULL DEFAULT true,
  created_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reports_admin_id ON public.reports(admin_id);
CREATE INDEX IF NOT EXISTS idx_reports_report_type ON public.reports(report_type);
CREATE INDEX IF NOT EXISTS idx_reports_next_run_at ON public.reports(next_run_at) WHERE is_active = true;

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

-- Admin can read all reports and manage their own reports
CREATE POLICY reports_admin_select ON public.reports
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY reports_admin_insert ON public.reports
  FOR INSERT WITH CHECK (
    admin_id = auth.uid() AND
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY reports_admin_update ON public.reports
  FOR UPDATE USING (
    admin_id = auth.uid() AND
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY reports_admin_delete ON public.reports
  FOR DELETE USING (
    admin_id = auth.uid() AND
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

COMMENT ON TABLE public.reports IS 'Report definitions and configurations. Admins create reports with filters and schedule them for regular execution.';
COMMENT ON COLUMN public.reports.filters IS 'JSONB with filtering criteria: {date_range, course_id, status, user_role, etc}';
COMMENT ON COLUMN public.reports.selected_columns IS 'Array of column names to include in the export';
COMMENT ON COLUMN public.reports.recipients_email IS 'Email addresses to send scheduled reports to';

-- ============================================================================
-- Table 2: report_exports
-- Purpose: Track generated reports and their file locations
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.report_exports (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id         UUID NOT NULL REFERENCES public.reports(id) ON DELETE CASCADE,
  generated_by      UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  format            VARCHAR(10) NOT NULL
                    CHECK (format IN ('csv', 'xlsx', 'pdf')),
  file_url          VARCHAR(500),
  file_size_kb      INTEGER,
  row_count         INTEGER,
  status            VARCHAR(20) NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'generating', 'completed', 'failed')),
  error_message     TEXT,
  generated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
  expires_at        TIMESTAMP DEFAULT (NOW() + INTERVAL '30 days'),
  created_at        TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_report_exports_report_id ON public.report_exports(report_id);
CREATE INDEX IF NOT EXISTS idx_report_exports_generated_by ON public.report_exports(generated_by);
CREATE INDEX IF NOT EXISTS idx_report_exports_status ON public.report_exports(status);
CREATE INDEX IF NOT EXISTS idx_report_exports_expires_at ON public.report_exports(expires_at);

ALTER TABLE public.report_exports ENABLE ROW LEVEL SECURITY;

-- Admin can read their exports, user can see their own
CREATE POLICY report_exports_select ON public.report_exports
  FOR SELECT USING (
    generated_by = auth.uid() OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY report_exports_insert ON public.report_exports
  FOR INSERT WITH CHECK (
    generated_by = auth.uid()
  );

CREATE POLICY report_exports_update ON public.report_exports
  FOR UPDATE USING (
    generated_by = auth.uid() OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  )
  WITH CHECK (
    generated_by = auth.uid() OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY report_exports_delete ON public.report_exports
  FOR DELETE USING (
    generated_by = auth.uid() OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

COMMENT ON TABLE public.report_exports IS 'Generated report files. Tracks exports with file URLs, formats, and status.';
COMMENT ON COLUMN public.report_exports.file_url IS 'S3 or storage URL where the file is hosted';
COMMENT ON COLUMN public.report_exports.expires_at IS 'When the exported file will be deleted (default 30 days)';

-- ============================================================================
-- Table 3: report_templates
-- Purpose: Pre-built report templates with suggested columns and filters
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.report_templates (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title             VARCHAR(200) NOT NULL,
  description       TEXT,
  report_type       VARCHAR(50) NOT NULL
                    CHECK (report_type IN ('enrollments', 'revenue', 'feedback', 'progress', 'engagement', 'custom')),
  suggested_columns TEXT[],
  default_filters   JSONB,
  icon_name         VARCHAR(50),
  is_system         BOOLEAN DEFAULT true, -- true = built-in, false = custom
  created_by        UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at        TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_report_templates_report_type ON public.report_templates(report_type);
CREATE UNIQUE INDEX IF NOT EXISTS idx_report_templates_title_type ON public.report_templates(title, report_type);

ALTER TABLE public.report_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY report_templates_select ON public.report_templates
  FOR SELECT USING (true); -- All authenticated users can see templates

COMMENT ON TABLE public.report_templates IS 'Pre-built report templates to help admins quickly create common reports.';

-- ============================================================================
-- Insert default templates
-- ============================================================================

INSERT INTO public.report_templates (title, description, report_type, suggested_columns, icon_name, is_system) VALUES
  (
    'Student Enrollments',
    'Enrollment trends and student acquisition metrics',
    'enrollments',
    ARRAY['date', 'course_title', 'student_count', 'course_category', 'status'],
    'Users',
    true
  ),
  (
    'Revenue Report',
    'Sales, refunds, and revenue by course or date range',
    'revenue',
    ARRAY['date', 'course_title', 'order_count', 'total_revenue', 'avg_order_value', 'refunds'],
    'DollarSign',
    true
  ),
  (
    'Course Feedback Summary',
    'Student feedback, ratings, and satisfaction metrics',
    'feedback',
    ARRAY['course_title', 'avg_rating', 'response_count', 'content_rating', 'instructor_rating', 'top_comments'],
    'MessageSquareText',
    true
  ),
  (
    'Student Progress',
    'Course completion, quiz scores, and assignment submissions',
    'progress',
    ARRAY['student_name', 'course_title', 'completion_percentage', 'assignments_completed', 'avg_quiz_score', 'last_activity'],
    'TrendingUp',
    true
  ),
  (
    'Engagement Metrics',
    'User activity, login frequency, and time spent learning',
    'engagement',
    ARRAY['date', 'active_students', 'total_lessons_viewed', 'avg_session_duration', 'new_users'],
    'BarChart3',
    true
  ) ON CONFLICT (title, report_type) DO NOTHING;
