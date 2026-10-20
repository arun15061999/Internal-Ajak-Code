-- Migration: Enable Row-Level Security on Core Tables
-- Date: 2026-05-11
-- Purpose: Add defense-in-depth database access controls aligned with application RBAC.
--          All policies are ADDITIVE — no data is modified or deleted.
--          Existing application-layer auth remains functional as a secondary check.
--
-- IMPORTANT: Run this migration AFTER all existing application code is updated to
--            use the Supabase service-role key for admin/batch operations.
--            Direct anon-key queries from the frontend will be restricted by these policies.

-- ───────────────────────────────────────────────────────────────────────────────
-- 0. Helper functions
-- ───────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.current_user_id()
RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT NULLIF(current_setting('request.jwt.claims', true)::json->>'sub', '')::uuid;
$$;

CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claims', true)::json->>'role', ''),
    (SELECT role FROM public.users WHERE id = public.current_user_id())
  );
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.current_user_role() = 'admin';
$$;

CREATE OR REPLACE FUNCTION public.is_teacher()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.current_user_role() = 'teacher';
$$;

CREATE OR REPLACE FUNCTION public.is_student()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.current_user_role() = 'student';
$$;

-- Helper: get teacher_id for the currently-authenticated user (if they are a teacher)
CREATE OR REPLACE FUNCTION public.current_teacher_id()
RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT id FROM public.teachers WHERE user_id = public.current_user_id();
$$;

-- Helper: get student_id for the currently-authenticated user (if they are a student)
CREATE OR REPLACE FUNCTION public.current_student_id()
RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT id FROM public.students WHERE user_id = public.current_user_id();
$$;

-- ───────────────────────────────────────────────────────────────────────────────
-- 1. users
-- ───────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Users can read their own profile
CREATE POLICY users_select_own
  ON public.users FOR SELECT
  TO authenticated
  USING (id = public.current_user_id() OR public.is_admin());

-- Users can update their own profile (limited columns should be enforced in app layer)
CREATE POLICY users_update_own
  ON public.users FOR UPDATE
  TO authenticated
  USING (id = public.current_user_id() OR public.is_admin())
  WITH CHECK (id = public.current_user_id() OR public.is_admin());

-- Admin insert/delete (app-layer only; disable direct insert from anon)
CREATE POLICY users_admin_all
  ON public.users FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- Allow service-role (used by edge functions / server code) unrestricted access
CREATE POLICY users_service_role
  ON public.users FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────────────
-- 2. teachers
-- ───────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.teachers ENABLE ROW LEVEL SECURITY;

-- Teachers can read their own record
CREATE POLICY teachers_select_own
  ON public.teachers FOR SELECT
  TO authenticated
  USING (user_id = public.current_user_id() OR public.is_admin());

-- Teachers can update their own profile
CREATE POLICY teachers_update_own
  ON public.teachers FOR UPDATE
  TO authenticated
  USING (user_id = public.current_user_id() OR public.is_admin())
  WITH CHECK (user_id = public.current_user_id() OR public.is_admin());

-- Admin full access
CREATE POLICY teachers_admin_all
  ON public.teachers FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY teachers_service_role
  ON public.teachers FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────────────
-- 3. students
-- ───────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;

-- Students can read their own record
CREATE POLICY students_select_own
  ON public.students FOR SELECT
  TO authenticated
  USING (user_id = public.current_user_id() OR public.is_admin());

-- Students can update their own record
CREATE POLICY students_update_own
  ON public.students FOR UPDATE
  TO authenticated
  USING (user_id = public.current_user_id() OR public.is_admin())
  WITH CHECK (user_id = public.current_user_id() OR public.is_admin());

-- Admin full access
CREATE POLICY students_admin_all
  ON public.students FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY students_service_role
  ON public.students FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────────────
-- 4. courses
-- ───────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.courses ENABLE ROW LEVEL SECURITY;

-- Anyone (including anon) can read published courses
CREATE POLICY courses_select_published
  ON public.courses FOR SELECT
  TO anon, authenticated
  USING (is_published = true OR public.is_admin());

-- Teachers can read their own courses (draft or published)
CREATE POLICY courses_select_teacher_own
  ON public.courses FOR SELECT
  TO authenticated
  USING (teacher_id = public.current_teacher_id());

-- Teachers can create courses (teacher_id must match themselves — enforced in WITH CHECK)
CREATE POLICY courses_insert_teacher
  ON public.courses FOR INSERT
  TO authenticated
  WITH CHECK (teacher_id = public.current_teacher_id());

-- Teachers can update their own courses
CREATE POLICY courses_update_teacher_own
  ON public.courses FOR UPDATE
  TO authenticated
  USING (teacher_id = public.current_teacher_id())
  WITH CHECK (teacher_id = public.current_teacher_id());

-- Teachers can delete their own courses (soft-delete recommended in app layer)
CREATE POLICY courses_delete_teacher_own
  ON public.courses FOR DELETE
  TO authenticated
  USING (teacher_id = public.current_teacher_id());

-- Admin full access
CREATE POLICY courses_admin_all
  ON public.courses FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY courses_service_role
  ON public.courses FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────────────
-- 5. sections
-- ───────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.sections ENABLE ROW LEVEL SECURITY;

-- Anyone can read sections of published courses
CREATE POLICY sections_select_published
  ON public.sections FOR SELECT
  TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.courses c
      WHERE c.id = sections.course_id AND (c.status = 'published' OR public.is_admin())
    )
  );

-- Teachers can CRUD sections for their own courses
CREATE POLICY sections_teacher_own
  ON public.sections FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.courses c
      WHERE c.id = sections.course_id AND c.teacher_id = public.current_teacher_id()
    ) OR public.is_admin()
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.courses c
      WHERE c.id = sections.course_id AND c.teacher_id = public.current_teacher_id()
    ) OR public.is_admin()
  );

CREATE POLICY sections_service_role
  ON public.sections FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────────────
-- 6. lessons
-- ───────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.lessons ENABLE ROW LEVEL SECURITY;

-- Anyone can read lessons of published courses
CREATE POLICY lessons_select_published
  ON public.lessons FOR SELECT
  TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.courses c
      WHERE c.id = lessons.course_id AND (c.status = 'published' OR public.is_admin())
    )
  );

-- Teachers can CRUD lessons for their own courses
CREATE POLICY lessons_teacher_own
  ON public.lessons FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.courses c
      WHERE c.id = lessons.course_id AND c.teacher_id = public.current_teacher_id()
    ) OR public.is_admin()
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.courses c
      WHERE c.id = lessons.course_id AND c.teacher_id = public.current_teacher_id()
    ) OR public.is_admin()
  );

CREATE POLICY lessons_service_role
  ON public.lessons FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────────────
-- 7. enrollments
-- ───────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.enrollments ENABLE ROW LEVEL SECURITY;

-- Students can read their own enrollments
CREATE POLICY enrollments_select_student
  ON public.enrollments FOR SELECT
  TO authenticated
  USING (
    student_id = public.current_student_id()
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.courses c
      WHERE c.id = enrollments.course_id AND c.teacher_id = public.current_teacher_id()
    )
  );

-- Students can insert their own enrollments
CREATE POLICY enrollments_insert_student
  ON public.enrollments FOR INSERT
  TO authenticated
  WITH CHECK (student_id = public.current_student_id() OR public.is_admin());

-- Students can update their own enrollments (progress, status)
CREATE POLICY enrollments_update_student
  ON public.enrollments FOR UPDATE
  TO authenticated
  USING (student_id = public.current_student_id() OR public.is_admin())
  WITH CHECK (student_id = public.current_student_id() OR public.is_admin());

-- Admin full access
CREATE POLICY enrollments_admin_all
  ON public.enrollments FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY enrollments_service_role
  ON public.enrollments FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────────────
-- 8. assignments
-- ───────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.assignments ENABLE ROW LEVEL SECURITY;

-- Anyone can read assignments of published courses
CREATE POLICY assignments_select_published
  ON public.assignments FOR SELECT
  TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.courses c
      WHERE c.id = assignments.course_id AND (c.status = 'published' OR public.is_admin())
    )
  );

-- Teachers can CRUD assignments for their own courses
CREATE POLICY assignments_teacher_own
  ON public.assignments FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.courses c
      WHERE c.id = assignments.course_id AND c.teacher_id = public.current_teacher_id()
    ) OR public.is_admin()
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.courses c
      WHERE c.id = assignments.course_id AND c.teacher_id = public.current_teacher_id()
    ) OR public.is_admin()
  );

CREATE POLICY assignments_service_role
  ON public.assignments FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────────────
-- 9. assignment_submissions
-- ───────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.assignment_submissions ENABLE ROW LEVEL SECURITY;

-- Students can read their own submissions
CREATE POLICY submissions_select_student
  ON public.assignment_submissions FOR SELECT
  TO authenticated
  USING (
    student_id = public.current_student_id()
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.assignments a
      JOIN public.courses c ON c.id = a.course_id
      WHERE a.id = assignment_submissions.assignment_id
        AND c.teacher_id = public.current_teacher_id()
    )
  );

-- Students can insert their own submissions
CREATE POLICY submissions_insert_student
  ON public.assignment_submissions FOR INSERT
  TO authenticated
  WITH CHECK (student_id = public.current_student_id() OR public.is_admin());

-- Students can update their own submissions (before grading)
CREATE POLICY submissions_update_student
  ON public.assignment_submissions FOR UPDATE
  TO authenticated
  USING (student_id = public.current_student_id() OR public.is_admin())
  WITH CHECK (student_id = public.current_student_id() OR public.is_admin());

-- Teachers can update submissions (grading)
CREATE POLICY submissions_update_teacher
  ON public.assignment_submissions FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.assignments a
      JOIN public.courses c ON c.id = a.course_id
      WHERE a.id = assignment_submissions.assignment_id
        AND c.teacher_id = public.current_teacher_id()
    ) OR public.is_admin()
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.assignments a
      JOIN public.courses c ON c.id = a.course_id
      WHERE a.id = assignment_submissions.assignment_id
        AND c.teacher_id = public.current_teacher_id()
    ) OR public.is_admin()
  );

CREATE POLICY submissions_service_role
  ON public.assignment_submissions FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────────────
-- 10. exams
-- ───────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.exams ENABLE ROW LEVEL SECURITY;

-- Anyone can read exams of published courses
CREATE POLICY exams_select_published
  ON public.exams FOR SELECT
  TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.courses c
      WHERE c.id = exams.course_id AND (c.status = 'published' OR public.is_admin())
    )
  );

-- Teachers can CRUD exams for their own courses
CREATE POLICY exams_teacher_own
  ON public.exams FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.courses c
      WHERE c.id = exams.course_id AND c.teacher_id = public.current_teacher_id()
    ) OR public.is_admin()
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.courses c
      WHERE c.id = exams.course_id AND c.teacher_id = public.current_teacher_id()
    ) OR public.is_admin()
  );

CREATE POLICY exams_service_role
  ON public.exams FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────────────
-- 11. exam_attempts
-- ───────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.exam_attempts ENABLE ROW LEVEL SECURITY;

-- Students can read their own attempts
CREATE POLICY exam_attempts_select_student
  ON public.exam_attempts FOR SELECT
  TO authenticated
  USING (
    student_id = public.current_student_id()
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.exams e
      JOIN public.courses c ON c.id = e.course_id
      WHERE e.id = exam_attempts.exam_id AND c.teacher_id = public.current_teacher_id()
    )
  );

-- Students can insert their own attempts
CREATE POLICY exam_attempts_insert_student
  ON public.exam_attempts FOR INSERT
  TO authenticated
  WITH CHECK (student_id = public.current_student_id() OR public.is_admin());

-- Students can update their own attempts (during exam)
CREATE POLICY exam_attempts_update_student
  ON public.exam_attempts FOR UPDATE
  TO authenticated
  USING (student_id = public.current_student_id() OR public.is_admin())
  WITH CHECK (student_id = public.current_student_id() OR public.is_admin());

CREATE POLICY exam_attempts_service_role
  ON public.exam_attempts FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────────────
-- 12. certificates
-- ───────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.certificates ENABLE ROW LEVEL SECURITY;

-- Anyone can verify/read certificates (public verification)
CREATE POLICY certificates_select_public
  ON public.certificates FOR SELECT
  TO anon, authenticated
  USING (true);

-- Students/teachers can read their own certificates (no student_id/course_id — join through enrollments)
CREATE POLICY certificates_select_student
  ON public.certificates FOR SELECT
  TO authenticated
  USING (
    public.is_admin()
    OR EXISTS (SELECT 1 FROM public.enrollments e WHERE e.id = certificates.enrollment_id AND e.student_id = public.current_student_id())
    OR EXISTS (SELECT 1 FROM public.enrollments e JOIN public.courses c ON c.id = e.course_id WHERE e.id = certificates.enrollment_id AND c.teacher_id = public.current_teacher_id())
  );

-- Admin full access (issue, revoke)
CREATE POLICY certificates_admin_all
  ON public.certificates FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY certificates_service_role
  ON public.certificates FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────────────
-- 13. transactions
-- ───────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

-- Students can read their own transactions
CREATE POLICY transactions_select_student
  ON public.transactions FOR SELECT
  TO authenticated
  USING (
    student_id = public.current_student_id()
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.courses c
      WHERE c.id = transactions.course_id AND c.teacher_id = public.current_teacher_id()
    )
  );

-- Admin full access
CREATE POLICY transactions_admin_all
  ON public.transactions FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY transactions_service_role
  ON public.transactions FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────────────
-- 14. orders
-- ───────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- Students can read their own orders
CREATE POLICY orders_select_student
  ON public.orders FOR SELECT
  TO authenticated
  USING (user_id = public.current_user_id() OR public.is_admin());

-- Students can insert their own orders
CREATE POLICY orders_insert_student
  ON public.orders FOR INSERT
  TO authenticated
  WITH CHECK (user_id = public.current_user_id() OR public.is_admin());

-- Admin full access
CREATE POLICY orders_admin_all
  ON public.orders FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY orders_service_role
  ON public.orders FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────────────
-- 15. blog_posts
-- ───────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.blog_posts ENABLE ROW LEVEL SECURITY;

-- Anyone can read published blog posts (uses is_published bool, no status column)
CREATE POLICY blog_posts_select_published
  ON public.blog_posts FOR SELECT
  TO anon, authenticated
  USING (is_published = true OR public.is_admin());

-- Authors can CRUD their own posts
CREATE POLICY blog_posts_author_own
  ON public.blog_posts FOR ALL
  TO authenticated
  USING (author_id = public.current_user_id() OR public.is_admin())
  WITH CHECK (author_id = public.current_user_id() OR public.is_admin());

CREATE POLICY blog_posts_service_role
  ON public.blog_posts FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────────────
-- 16. events
-- ───────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

-- Anyone can read non-draft/cancelled events (no visibility column, uses status)
CREATE POLICY events_select_public
  ON public.events FOR SELECT
  TO anon, authenticated
  USING (status NOT IN ('draft', 'cancelled') OR public.is_admin());

-- Hosts can CRUD their own events
CREATE POLICY events_host_own
  ON public.events FOR ALL
  TO authenticated
  USING (host_id = public.current_user_id() OR public.is_admin())
  WITH CHECK (host_id = public.current_user_id() OR public.is_admin());

CREATE POLICY events_service_role
  ON public.events FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────────────
-- 17. event_registrations
-- ───────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.event_registrations ENABLE ROW LEVEL SECURITY;

-- Users can read their own registrations
CREATE POLICY event_registrations_select_own
  ON public.event_registrations FOR SELECT
  TO authenticated
  USING (
    user_id = public.current_user_id()
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_registrations.event_id AND e.host_id = public.current_user_id()
    )
  );

-- Users can insert their own registrations
CREATE POLICY event_registrations_insert_own
  ON public.event_registrations FOR INSERT
  TO authenticated
  WITH CHECK (user_id = public.current_user_id() OR public.is_admin());

CREATE POLICY event_registrations_service_role
  ON public.event_registrations FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────────────
-- 18. products
-- ───────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- Anyone can read published products (uses is_published bool, no status column)
CREATE POLICY products_select_published
  ON public.products FOR SELECT
  TO anon, authenticated
  USING (is_published = true OR public.is_admin());

-- Sellers can CRUD their own products
CREATE POLICY products_seller_own
  ON public.products FOR ALL
  TO authenticated
  USING (seller_id = public.current_user_id() OR public.is_admin())
  WITH CHECK (seller_id = public.current_user_id() OR public.is_admin());

CREATE POLICY products_service_role
  ON public.products FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────────────
-- 19. support_tickets
-- ───────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;

-- Users can read their own tickets
CREATE POLICY support_tickets_select_own
  ON public.support_tickets FOR SELECT
  TO authenticated
  USING (user_id = public.current_user_id() OR public.is_admin());

-- Users can create their own tickets
CREATE POLICY support_tickets_insert_own
  ON public.support_tickets FOR INSERT
  TO authenticated
  WITH CHECK (user_id = public.current_user_id() OR public.is_admin());

-- Users can update their own tickets (before resolution)
CREATE POLICY support_tickets_update_own
  ON public.support_tickets FOR UPDATE
  TO authenticated
  USING (user_id = public.current_user_id() OR public.is_admin())
  WITH CHECK (user_id = public.current_user_id() OR public.is_admin());

CREATE POLICY support_tickets_service_role
  ON public.support_tickets FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────────────
-- 20. platform_settings
-- ───────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.platform_settings ENABLE ROW LEVEL SECURITY;

-- Anyone can read platform settings (needed for frontend config)
CREATE POLICY platform_settings_select_public
  ON public.platform_settings FOR SELECT
  TO anon, authenticated
  USING (true);

-- Only admin can modify
CREATE POLICY platform_settings_admin_modify
  ON public.platform_settings FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY platform_settings_service_role
  ON public.platform_settings FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────────────
-- 21. user_two_factor (sensitive — restrict heavily)
-- ───────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.user_two_factor ENABLE ROW LEVEL SECURITY;

-- Users can read their own 2FA record
CREATE POLICY user_two_factor_select_own
  ON public.user_two_factor FOR SELECT
  TO authenticated
  USING (user_id = public.current_user_id() OR public.is_admin());

-- Users can update their own 2FA record
CREATE POLICY user_two_factor_update_own
  ON public.user_two_factor FOR UPDATE
  TO authenticated
  USING (user_id = public.current_user_id() OR public.is_admin())
  WITH CHECK (user_id = public.current_user_id() OR public.is_admin());

CREATE POLICY user_two_factor_service_role
  ON public.user_two_factor FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────────────
-- 22. two_factor_sessions (sensitive — restrict heavily)
-- ───────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.two_factor_sessions ENABLE ROW LEVEL SECURITY;

-- Users can read their own sessions
CREATE POLICY two_factor_sessions_select_own
  ON public.two_factor_sessions FOR SELECT
  TO authenticated
  USING (user_id = public.current_user_id() OR public.is_admin());

CREATE POLICY two_factor_sessions_service_role
  ON public.two_factor_sessions FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────────────
-- 23. chat_messages (if table exists)
-- ───────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'chat_messages') THEN
    EXECUTE 'ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;';
    EXECUTE 'CREATE POLICY chat_messages_select_participant ON public.chat_messages FOR SELECT TO authenticated USING (sender_id = public.current_user_id() OR receiver_id = public.current_user_id() OR public.is_admin());';
    EXECUTE 'CREATE POLICY chat_messages_insert_sender ON public.chat_messages FOR INSERT TO authenticated WITH CHECK (sender_id = public.current_user_id() OR public.is_admin());';
    EXECUTE 'CREATE POLICY chat_messages_service_role ON public.chat_messages FOR ALL TO service_role USING (true) WITH CHECK (true);';
  END IF;
END $$;

-- ───────────────────────────────────────────────────────────────────────────────
-- 24. notifications
-- ───────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'notifications') THEN
    EXECUTE 'ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;';
    EXECUTE 'CREATE POLICY notifications_select_recipient ON public.notifications FOR SELECT TO authenticated USING (user_id = public.current_user_id() OR public.is_admin());';
    EXECUTE 'CREATE POLICY notifications_update_recipient ON public.notifications FOR UPDATE TO authenticated USING (user_id = public.current_user_id() OR public.is_admin()) WITH CHECK (user_id = public.current_user_id() OR public.is_admin());';
    EXECUTE 'CREATE POLICY notifications_service_role ON public.notifications FOR ALL TO service_role USING (true) WITH CHECK (true);';
  END IF;
END $$;

-- ───────────────────────────────────────────────────────────────────────────────
-- 25. reviews
-- ───────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'reviews') THEN
    EXECUTE 'ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;';
    EXECUTE 'CREATE POLICY reviews_select_public ON public.reviews FOR SELECT TO anon, authenticated USING (true);';
    EXECUTE 'CREATE POLICY reviews_insert_authenticated ON public.reviews FOR INSERT TO authenticated WITH CHECK (user_id = public.current_user_id() OR public.is_admin());';
    EXECUTE 'CREATE POLICY reviews_update_author ON public.reviews FOR UPDATE TO authenticated USING (user_id = public.current_user_id() OR public.is_admin()) WITH CHECK (user_id = public.current_user_id() OR public.is_admin());';
    EXECUTE 'CREATE POLICY reviews_service_role ON public.reviews FOR ALL TO service_role USING (true) WITH CHECK (true);';
  END IF;
END $$;

-- ───────────────────────────────────────────────────────────────────────────────
-- 26. resources
-- ───────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'resources') THEN
    EXECUTE 'ALTER TABLE public.resources ENABLE ROW LEVEL SECURITY;';
    EXECUTE 'CREATE POLICY resources_select_public ON public.resources FOR SELECT TO anon, authenticated USING (true);';
    EXECUTE 'CREATE POLICY resources_insert_teacher ON public.resources FOR INSERT TO authenticated WITH CHECK (public.is_teacher() OR public.is_admin());';
    EXECUTE 'CREATE POLICY resources_service_role ON public.resources FOR ALL TO service_role USING (true) WITH CHECK (true);';
  END IF;
END $$;

-- ───────────────────────────────────────────────────────────────────────────────
-- Final verification helper
-- ───────────────────────────────────────────────────────────────────────────────

SELECT 'RLS policies applied successfully. Review the policies above and test with anon/service-role keys before enabling in production.' AS migration_status;
