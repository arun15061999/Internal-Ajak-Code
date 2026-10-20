-- Migration: Create course feedback and survey system tables
-- Purpose: Implements Phase 1 quick win features for collecting and analyzing student feedback

-- ============================================================================
-- Table 1: course_feedback
-- Purpose: Private per-student rating for enrolled courses (separate from public course_reviews)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.course_feedback (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id         UUID NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
  student_id        UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  enrollment_id     UUID REFERENCES public.enrollments(id) ON DELETE SET NULL,
  overall_rating    SMALLINT NOT NULL CHECK (overall_rating BETWEEN 1 AND 5),
  content_rating    SMALLINT CHECK (content_rating BETWEEN 1 AND 5),
  instructor_rating SMALLINT CHECK (instructor_rating BETWEEN 1 AND 5),
  platform_rating   SMALLINT CHECK (platform_rating BETWEEN 1 AND 5),
  comment           TEXT CHECK (char_length(comment) <= 2000),
  is_anonymous      BOOLEAN NOT NULL DEFAULT false,
  created_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE (course_id, student_id)
);

CREATE INDEX IF NOT EXISTS idx_course_feedback_course_id ON public.course_feedback(course_id);
CREATE INDEX IF NOT EXISTS idx_course_feedback_student_id ON public.course_feedback(student_id);
CREATE INDEX IF NOT EXISTS idx_course_feedback_created_at ON public.course_feedback(created_at);

ALTER TABLE public.course_feedback ENABLE ROW LEVEL SECURITY;

-- Student: can read, insert, and update their own feedback
CREATE POLICY course_feedback_student_select ON public.course_feedback
  FOR SELECT USING (auth.uid() = student_id);

CREATE POLICY course_feedback_student_insert ON public.course_feedback
  FOR INSERT WITH CHECK (auth.uid() = student_id);

CREATE POLICY course_feedback_student_update ON public.course_feedback
  FOR UPDATE USING (auth.uid() = student_id);

-- Teacher: can read feedback for their own courses
CREATE POLICY course_feedback_teacher_select ON public.course_feedback
  FOR SELECT USING (
    false
  );

CREATE OR REPLACE VIEW public.course_feedback_for_teachers
WITH (security_invoker = true) AS
SELECT
  cf.id,
  cf.course_id,
  CASE WHEN cf.is_anonymous THEN NULL ELSE cf.student_id END AS student_id,
  cf.enrollment_id,
  cf.overall_rating,
  cf.content_rating,
  cf.instructor_rating,
  cf.platform_rating,
  cf.comment,
  cf.is_anonymous,
  cf.created_at,
  cf.updated_at
FROM public.course_feedback cf
WHERE
  EXISTS (
    SELECT 1 FROM public.courses c
    JOIN public.teachers t ON t.id = c.teacher_id
    WHERE c.id = cf.course_id AND t.user_id = auth.uid()
  )
  OR EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'admin');

GRANT SELECT ON public.course_feedback_for_teachers TO authenticated;

-- Admin: can read all feedback
CREATE POLICY course_feedback_admin_select ON public.course_feedback
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

-- Admin: can delete feedback
CREATE POLICY course_feedback_admin_delete ON public.course_feedback
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

COMMENT ON TABLE public.course_feedback IS 'Private per-student feedback for courses. Separate from public course_reviews. Supports multiple rating dimensions and optional anonymous submissions.';
COMMENT ON COLUMN public.course_feedback.overall_rating IS 'Overall course satisfaction (1-5 required)';
COMMENT ON COLUMN public.course_feedback.content_rating IS 'Quality of course content (1-5 optional)';
COMMENT ON COLUMN public.course_feedback.instructor_rating IS 'Quality of instructor/teaching (1-5 optional)';
COMMENT ON COLUMN public.course_feedback.platform_rating IS 'Platform experience (1-5 optional)';

-- ============================================================================
-- Table 2: surveys
-- Purpose: Admin/instructor-created survey forms for custom feedback collection
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.surveys (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title        VARCHAR(200) NOT NULL,
  description  TEXT,
  course_id    UUID REFERENCES public.courses(id) ON DELETE SET NULL,
  created_by   UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  is_active    BOOLEAN NOT NULL DEFAULT true,
  is_anonymous BOOLEAN NOT NULL DEFAULT false,
  starts_at    TIMESTAMP,
  ends_at      TIMESTAMP,
  created_at   TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMP NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_surveys_starts_before_ends
    CHECK (starts_at IS NULL OR ends_at IS NULL OR starts_at < ends_at)
);

CREATE INDEX IF NOT EXISTS idx_surveys_course_id ON public.surveys(course_id);
CREATE INDEX IF NOT EXISTS idx_surveys_created_by ON public.surveys(created_by);
CREATE INDEX IF NOT EXISTS idx_surveys_is_active ON public.surveys(is_active);

ALTER TABLE public.surveys ENABLE ROW LEVEL SECURITY;

-- Anyone authenticated can view active surveys or surveys they created
CREATE POLICY surveys_select ON public.surveys
  FOR SELECT USING (
    is_active = true OR created_by = auth.uid() OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role IN ('admin', 'teacher'))
  );

-- Admin/teacher can insert, update, delete surveys
CREATE POLICY surveys_write ON public.surveys
  FOR ALL USING (
    created_by = auth.uid() OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  )
  WITH CHECK (
    created_by = auth.uid() OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

COMMENT ON TABLE public.surveys IS 'Customizable survey forms created by instructors/admins for feedback collection. Can be course-specific or platform-wide.';

-- ============================================================================
-- Table 3: survey_questions
-- Purpose: Individual questions within a survey (multiple question types)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.survey_questions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  survey_id     UUID NOT NULL REFERENCES public.surveys(id) ON DELETE CASCADE,
  question_text TEXT NOT NULL CHECK (char_length(question_text) <= 500),
  question_type VARCHAR(30) NOT NULL DEFAULT 'rating'
                CHECK (question_type IN ('rating', 'text', 'multiple_choice', 'boolean')),
  options       JSONB,
  is_required   BOOLEAN NOT NULL DEFAULT true,
  order_index   INTEGER NOT NULL DEFAULT 0,
  created_at    TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_survey_questions_survey_id ON public.survey_questions(survey_id);
CREATE INDEX IF NOT EXISTS idx_survey_questions_order_index ON public.survey_questions(survey_id, order_index);

ALTER TABLE public.survey_questions ENABLE ROW LEVEL SECURITY;

-- Anyone can read survey questions (needed to display surveys)
CREATE POLICY survey_questions_select ON public.survey_questions
  FOR SELECT USING (true);

-- Admin/teacher can insert/update/delete questions
CREATE POLICY survey_questions_write ON public.survey_questions
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.surveys s
      WHERE s.id = survey_id AND (s.created_by = auth.uid() OR
        EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role IN ('admin', 'teacher')))
    )
  );

COMMENT ON TABLE public.survey_questions IS 'Individual questions within a survey. Supports rating (1-5), text, multiple choice, and boolean question types.';
COMMENT ON COLUMN public.survey_questions.options IS 'JSONB array of options for multiple_choice questions, e.g., ["Strongly Agree", "Agree", "Neutral", "Disagree"]';

-- ============================================================================
-- Table 4: survey_responses
-- Purpose: Track which students/users have submitted responses to a survey
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.survey_responses (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  survey_id   UUID NOT NULL REFERENCES public.surveys(id) ON DELETE CASCADE,
  student_id  UUID REFERENCES public.users(id) ON DELETE SET NULL,
  submitted_at TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE (survey_id, student_id)
);

CREATE INDEX IF NOT EXISTS idx_survey_responses_survey_id ON public.survey_responses(survey_id);
CREATE INDEX IF NOT EXISTS idx_survey_responses_student_id ON public.survey_responses(student_id);

ALTER TABLE public.survey_responses ENABLE ROW LEVEL SECURITY;

-- Student can insert their own response
CREATE POLICY survey_responses_insert ON public.survey_responses
  FOR INSERT WITH CHECK (
    auth.uid() = student_id OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role IN ('admin', 'teacher'))
  );

-- Admin/teacher can read responses for surveys they created or all if admin
CREATE POLICY survey_responses_select ON public.survey_responses
  FOR SELECT USING (
    student_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM public.surveys s
      WHERE s.id = survey_id AND (s.created_by = auth.uid() OR
        EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role IN ('admin', 'teacher')))
    )
  );

COMMENT ON TABLE public.survey_responses IS 'Represents a completed survey submission by a student. UNIQUE constraint ensures one response per student per survey.';

-- ============================================================================
-- Table 5: survey_answers
-- Purpose: Individual answers to survey questions
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.survey_answers (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  response_id UUID NOT NULL REFERENCES public.survey_responses(id) ON DELETE CASCADE,
  question_id UUID NOT NULL REFERENCES public.survey_questions(id) ON DELETE CASCADE,
  answer_text TEXT,
  answer_value INTEGER CHECK (answer_value IS NULL OR answer_value BETWEEN 1 AND 10),
  created_at  TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE (response_id, question_id)
);

CREATE INDEX IF NOT EXISTS idx_survey_answers_response_id ON public.survey_answers(response_id);
CREATE INDEX IF NOT EXISTS idx_survey_answers_question_id ON public.survey_answers(question_id);

ALTER TABLE public.survey_answers ENABLE ROW LEVEL SECURITY;

-- Student can insert their own answers
CREATE POLICY survey_answers_insert ON public.survey_answers
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.survey_responses sr
      WHERE sr.id = response_id AND sr.student_id = auth.uid()
    ) OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role IN ('admin', 'teacher'))
  );

-- Admin/teacher can read answers for surveys they created
CREATE POLICY survey_answers_select ON public.survey_answers
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.survey_responses sr
      JOIN public.survey_questions sq ON sq.id = survey_answers.question_id AND sq.survey_id = sr.survey_id
      JOIN public.surveys s ON s.id = sq.survey_id
      WHERE sr.id = survey_answers.response_id
        AND (
        s.created_by = auth.uid() OR
        EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role IN ('admin', 'teacher'))
      )
    )
  );

COMMENT ON TABLE public.survey_answers IS 'Individual answer to a survey question. Can be text (for open-ended) or numeric (for ratings/scales).';
COMMENT ON COLUMN public.survey_answers.answer_text IS 'Text answer for open-ended questions';
COMMENT ON COLUMN public.survey_answers.answer_value IS 'Numeric answer (1-10 scale) for rating/Likert questions';
