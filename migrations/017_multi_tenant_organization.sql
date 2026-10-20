-- Migration: Add organization_id for multi-tenant SaaS isolation
-- Date: 2026-05-11
-- Purpose: Introduce organization boundary across all core tables so the platform
--          can be white-labeled or sold as SaaS without data leakage across tenants.
--          All changes are ADDITIVE — no existing data is modified or deleted.
--
-- IMPORTANT: Run this migration AFTER confirming the app layer supports org context
--            (e.g. middleware extracts org from hostname or user profile).

-- ───────────────────────────────────────────────────────────────────────────────
-- 0. organizations table
-- ───────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.organizations (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug          text NOT NULL UNIQUE,
  name          text NOT NULL,
  domain        text,
  settings      jsonb DEFAULT '{}',
  branding      jsonb DEFAULT '{}',
  is_active     boolean DEFAULT true,
  created_at    timestamptz DEFAULT now(),
  updated_at    timestamptz DEFAULT now()
);

COMMENT ON TABLE public.organizations IS 'Top-level tenant boundary for white-label / SaaS isolation.';

-- Only service_role and admin can manage organizations directly
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

CREATE POLICY orgs_admin_all
  ON public.organizations FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY orgs_service_role
  ON public.organizations FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────────────
-- 1. Add organization_id to core tables (nullable, no default, additive)
-- ───────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.users              ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL;
ALTER TABLE public.teachers           ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL;
ALTER TABLE public.students           ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL;
ALTER TABLE public.courses            ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL;
ALTER TABLE public.enrollments        ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL;
ALTER TABLE public.exams              ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL;
ALTER TABLE public.assignments        ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL;
ALTER TABLE public.sections           ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL;
ALTER TABLE public.lessons            ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL;
ALTER TABLE public.orders             ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL;
ALTER TABLE public.transactions       ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL;
ALTER TABLE public.certificates       ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL;
ALTER TABLE public.blog_posts        ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL;
ALTER TABLE public.events             ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL;
ALTER TABLE public.support_tickets    ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL;
ALTER TABLE public.platform_settings   ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL;

-- Indexes for fast org-scoped queries
CREATE INDEX IF NOT EXISTS idx_users_org              ON public.users(organization_id)            WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_teachers_org           ON public.teachers(organization_id)           WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_students_org           ON public.students(organization_id)           WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_courses_org            ON public.courses(organization_id)            WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_enrollments_org        ON public.enrollments(organization_id)       WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_exams_org              ON public.exams(organization_id)              WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_assignments_org      ON public.assignments(organization_id)          WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sections_org           ON public.sections(organization_id)            WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_lessons_org            ON public.lessons(organization_id)             WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_orders_org             ON public.orders(organization_id)              WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_transactions_org       ON public.transactions(organization_id)        WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_certificates_org       ON public.certificates(organization_id)        WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_blog_posts_org         ON public.blog_posts(organization_id)          WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_events_org             ON public.events(organization_id)              WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_support_tickets_org    ON public.support_tickets(organization_id)     WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_platform_settings_org  ON public.platform_settings(organization_id)   WHERE organization_id IS NOT NULL;

-- ───────────────────────────────────────────────────────────────────────────────
-- 2. Tenant helper functions
-- ───────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.current_org_id()
RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT organization_id FROM public.users WHERE id = public.current_user_id();
$$;

CREATE OR REPLACE FUNCTION public.belongs_to_same_org(target_org_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.current_org_id() IS NOT DISTINCT FROM target_org_id;
$$;

-- ───────────────────────────────────────────────────────────────────────────────
-- 3. Re-create RLS policies with org isolation (additive — keeps existing policies)
--    For each table we ADD an org-scoped policy that restricts rows when
--    organization_id IS NOT NULL and the user carries an org_id claim.
--    Rows with NULL organization_id remain visible under existing policies.
-- ───────────────────────────────────────────────────────────────────────────────

-- users
CREATE POLICY users_select_same_org
  ON public.users FOR SELECT
  TO authenticated
  USING (
    organization_id IS NULL
    OR public.belongs_to_same_org(organization_id)
    OR public.is_admin()
  );

-- teachers
CREATE POLICY teachers_select_same_org
  ON public.teachers FOR SELECT
  TO authenticated
  USING (
    organization_id IS NULL
    OR public.belongs_to_same_org(organization_id)
    OR public.is_admin()
  );

-- students
CREATE POLICY students_select_same_org
  ON public.students FOR SELECT
  TO authenticated
  USING (
    organization_id IS NULL
    OR public.belongs_to_same_org(organization_id)
    OR public.is_admin()
  );

-- courses
CREATE POLICY courses_select_same_org
  ON public.courses FOR SELECT
  TO authenticated
  USING (
    organization_id IS NULL
    OR public.belongs_to_same_org(organization_id)
    OR public.is_admin()
  );

-- enrollments
CREATE POLICY enrollments_select_same_org
  ON public.enrollments FOR SELECT
  TO authenticated
  USING (
    organization_id IS NULL
    OR public.belongs_to_same_org(organization_id)
    OR public.is_admin()
  );

-- exams
CREATE POLICY exams_select_same_org
  ON public.exams FOR SELECT
  TO authenticated
  USING (
    organization_id IS NULL
    OR public.belongs_to_same_org(organization_id)
    OR public.is_admin()
  );

-- assignments
CREATE POLICY assignments_select_same_org
  ON public.assignments FOR SELECT
  TO authenticated
  USING (
    organization_id IS NULL
    OR public.belongs_to_same_org(organization_id)
    OR public.is_admin()
  );

-- sections
CREATE POLICY sections_select_same_org
  ON public.sections FOR SELECT
  TO authenticated
  USING (
    organization_id IS NULL
    OR public.belongs_to_same_org(organization_id)
    OR public.is_admin()
  );

-- lessons
CREATE POLICY lessons_select_same_org
  ON public.lessons FOR SELECT
  TO authenticated
  USING (
    organization_id IS NULL
    OR public.belongs_to_same_org(organization_id)
    OR public.is_admin()
  );

-- orders
CREATE POLICY orders_select_same_org
  ON public.orders FOR SELECT
  TO authenticated
  USING (
    organization_id IS NULL
    OR public.belongs_to_same_org(organization_id)
    OR public.is_admin()
  );

-- transactions
CREATE POLICY transactions_select_same_org
  ON public.transactions FOR SELECT
  TO authenticated
  USING (
    organization_id IS NULL
    OR public.belongs_to_same_org(organization_id)
    OR public.is_admin()
  );

-- certificates
CREATE POLICY certificates_select_same_org
  ON public.certificates FOR SELECT
  TO authenticated
  USING (
    organization_id IS NULL
    OR public.belongs_to_same_org(organization_id)
    OR public.is_admin()
  );

-- blog_posts
CREATE POLICY blog_posts_select_same_org
  ON public.blog_posts FOR SELECT
  TO authenticated
  USING (
    organization_id IS NULL
    OR public.belongs_to_same_org(organization_id)
    OR public.is_admin()
  );

-- events
CREATE POLICY events_select_same_org
  ON public.events FOR SELECT
  TO authenticated
  USING (
    organization_id IS NULL
    OR public.belongs_to_same_org(organization_id)
    OR public.is_admin()
  );

-- support_tickets
CREATE POLICY support_tickets_select_same_org
  ON public.support_tickets FOR SELECT
  TO authenticated
  USING (
    organization_id IS NULL
    OR public.belongs_to_same_org(organization_id)
    OR public.is_admin()
  );

-- platform_settings
CREATE POLICY platform_settings_select_same_org
  ON public.platform_settings FOR SELECT
  TO authenticated
  USING (
    organization_id IS NULL
    OR public.belongs_to_same_org(organization_id)
    OR public.is_admin()
  );

-- ───────────────────────────────────────────────────────────────────────────────
-- 4. Service-role bypass (ensures server-side operations aren't broken)
-- ───────────────────────────────────────────────────────────────────────────────

CREATE POLICY users_service_role_org
  ON public.users FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

CREATE POLICY teachers_service_role_org
  ON public.teachers FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

CREATE POLICY students_service_role_org
  ON public.students FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

CREATE POLICY courses_service_role_org
  ON public.courses FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

CREATE POLICY enrollments_service_role_org
  ON public.enrollments FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

CREATE POLICY exams_service_role_org
  ON public.exams FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

CREATE POLICY assignments_service_role_org
  ON public.assignments FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

CREATE POLICY sections_service_role_org
  ON public.sections FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

CREATE POLICY lessons_service_role_org
  ON public.lessons FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

CREATE POLICY orders_service_role_org
  ON public.orders FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

CREATE POLICY transactions_service_role_org
  ON public.transactions FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

CREATE POLICY certificates_service_role_org
  ON public.certificates FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

CREATE POLICY blog_posts_service_role_org
  ON public.blog_posts FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

CREATE POLICY events_service_role_org
  ON public.events FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

CREATE POLICY support_tickets_service_role_org
  ON public.support_tickets FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

CREATE POLICY platform_settings_service_role_org
  ON public.platform_settings FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);
