-- Migration: Create video engagement tracking system
-- Purpose: Track detailed video viewing patterns, engagement metrics, and heatmaps

-- ============================================================================
-- Table 1: video_engagement
-- Purpose: Track per-student video viewing activity
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.video_engagement (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lesson_id         UUID NOT NULL REFERENCES public.lessons(id) ON DELETE CASCADE,
  student_id        UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  enrollment_id     UUID REFERENCES public.enrollments(id) ON DELETE SET NULL,
  video_duration    INTEGER,            -- total video duration in seconds
  watch_duration    INTEGER NOT NULL,   -- total seconds watched
  completion_percentage SMALLINT CHECK (completion_percentage BETWEEN 0 AND 100), -- 0-100% of video watched
  watched_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE (lesson_id, student_id)
);

CREATE INDEX IF NOT EXISTS idx_video_engagement_student_id ON public.video_engagement(student_id);
CREATE INDEX IF NOT EXISTS idx_video_engagement_lesson_id ON public.video_engagement(lesson_id);
CREATE INDEX IF NOT EXISTS idx_video_engagement_enrollment_id ON public.video_engagement(enrollment_id);
CREATE INDEX IF NOT EXISTS idx_video_engagement_watched_at ON public.video_engagement(watched_at);

ALTER TABLE public.video_engagement ENABLE ROW LEVEL SECURITY;

-- Student can see their own engagement, teacher can see their course's, admin sees all
CREATE POLICY video_engagement_select ON public.video_engagement
  FOR SELECT USING (
    student_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM public.courses
      WHERE id IN (SELECT course_id FROM public.lessons WHERE id = lesson_id)
      AND instructor_id = auth.uid()
    ) OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY video_engagement_insert ON public.video_engagement
  FOR INSERT WITH CHECK (student_id = auth.uid());

CREATE POLICY video_engagement_update ON public.video_engagement
  FOR UPDATE USING (student_id = auth.uid());

COMMENT ON TABLE public.video_engagement IS 'Track video viewing activity, duration watched, and completion percentage per student per lesson';
COMMENT ON COLUMN public.video_engagement.completion_percentage IS 'Percentage of total video watched (0-100)';

-- ============================================================================
-- Table 2: video_heatmap
-- Purpose: Track viewing patterns at second-level granularity
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.video_heatmap (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lesson_id         UUID NOT NULL REFERENCES public.lessons(id) ON DELETE CASCADE,
  timestamp_second  SMALLINT NOT NULL, -- second position in video (0-N)
  view_count        INTEGER DEFAULT 0, -- how many times this second was viewed
  rewind_count      INTEGER DEFAULT 0, -- how many times viewers rewound from here
  dropout_count     INTEGER DEFAULT 0, -- how many viewers left after this second
  created_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE (lesson_id, timestamp_second)
);

CREATE INDEX IF NOT EXISTS idx_video_heatmap_lesson_id ON public.video_heatmap(lesson_id);
CREATE INDEX IF NOT EXISTS idx_video_heatmap_timestamp_second ON public.video_heatmap(timestamp_second);

ALTER TABLE public.video_heatmap ENABLE ROW LEVEL SECURITY;

CREATE POLICY video_heatmap_select ON public.video_heatmap
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.courses
      WHERE id IN (SELECT course_id FROM public.lessons WHERE id = lesson_id)
      AND instructor_id = auth.uid()
    ) OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY video_heatmap_insert ON public.video_heatmap
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.courses
      WHERE id IN (SELECT course_id FROM public.lessons WHERE id = lesson_id)
      AND instructor_id = auth.uid()
    ) OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY video_heatmap_update ON public.video_heatmap
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.courses
      WHERE id IN (SELECT course_id FROM public.lessons WHERE id = lesson_id)
      AND instructor_id = auth.uid()
    ) OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.courses
      WHERE id IN (SELECT course_id FROM public.lessons WHERE id = lesson_id)
      AND instructor_id = auth.uid()
    ) OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

COMMENT ON TABLE public.video_heatmap IS 'Second-by-second viewing heatmap showing engagement patterns throughout the video';

-- ============================================================================
-- Table 3: learner_metrics
-- Purpose: Aggregate learner performance and engagement metrics
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.learner_metrics (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id        UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  enrollment_id     UUID NOT NULL REFERENCES public.enrollments(id) ON DELETE CASCADE,
  course_id         UUID NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,

  -- Learning metrics
  total_lessons_viewed     INTEGER DEFAULT 0,
  total_video_minutes      INTEGER DEFAULT 0,
  avg_completion_rate      SMALLINT DEFAULT 0,  -- 0-100%
  quiz_attempts            INTEGER DEFAULT 0,
  avg_quiz_score           SMALLINT DEFAULT 0,  -- 0-100%
  assignments_submitted    INTEGER DEFAULT 0,

  -- Engagement metrics
  days_active              INTEGER DEFAULT 0,   -- days with activity
  last_activity_at         TIMESTAMP,
  streak_days              INTEGER DEFAULT 0,   -- current study streak
  longest_streak_days      INTEGER DEFAULT 0,   -- longest streak ever

  -- Performance indicators
  learning_velocity        NUMERIC(5,2) DEFAULT 0,  -- lessons/day over last 7 days
  time_to_completion_days  INTEGER,                 -- estimated days to complete course
  risk_level               VARCHAR(20) DEFAULT 'low' CHECK (risk_level IN ('low', 'medium', 'high')),

  created_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE (enrollment_id)
);

CREATE INDEX IF NOT EXISTS idx_learner_metrics_student_id ON public.learner_metrics(student_id);
CREATE INDEX IF NOT EXISTS idx_learner_metrics_course_id ON public.learner_metrics(course_id);
CREATE INDEX IF NOT EXISTS idx_learner_metrics_risk_level ON public.learner_metrics(risk_level);

ALTER TABLE public.learner_metrics ENABLE ROW LEVEL SECURITY;

CREATE POLICY learner_metrics_select ON public.learner_metrics
  FOR SELECT USING (
    student_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM public.courses
      WHERE id = course_id AND instructor_id = auth.uid()
    ) OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY learner_metrics_insert ON public.learner_metrics
  FOR INSERT WITH CHECK (
    student_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM public.courses
      WHERE id = course_id AND instructor_id = auth.uid()
    ) OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY learner_metrics_update ON public.learner_metrics
  FOR UPDATE USING (
    student_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM public.courses
      WHERE id = course_id AND instructor_id = auth.uid()
    ) OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  )
  WITH CHECK (
    student_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM public.courses
      WHERE id = course_id AND instructor_id = auth.uid()
    ) OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

COMMENT ON TABLE public.learner_metrics IS 'Aggregate metrics for student performance, engagement, and learning patterns per enrollment';
COMMENT ON COLUMN public.learner_metrics.risk_level IS 'Predicted risk: low (on track), medium (at risk), high (critical intervention needed)';

-- ============================================================================
-- Table 4: predictive_insights
-- Purpose: Store ML-powered predictions and recommendations
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.predictive_insights (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id        UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  enrollment_id     UUID NOT NULL REFERENCES public.enrollments(id) ON DELETE CASCADE,

  -- Predictive fields
  dropout_probability NUMERIC(3,2)
                      CHECK (dropout_probability >= 0 AND dropout_probability <= 1), -- 0.0-1.0 likelihood of dropout
  completion_by_date  DATE,                -- predicted completion date
  will_pass_exam      BOOLEAN,             -- binary prediction for pass/fail
  recommended_action  VARCHAR(50),         -- suggest: 'catch_up', 'accelerate', 'review', 'mentor_connect'
  confidence_score    NUMERIC(3,2)
                      CHECK (confidence_score >= 0 AND confidence_score <= 1), -- 0.0-1.0 model confidence
  reason_summary      TEXT,                -- human-readable explanation

  created_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  expires_at        TIMESTAMP DEFAULT (NOW() + INTERVAL '7 days'),
  UNIQUE (enrollment_id)
);

CREATE INDEX IF NOT EXISTS idx_predictive_insights_student_id ON public.predictive_insights(student_id);
CREATE INDEX IF NOT EXISTS idx_predictive_insights_dropout_probability ON public.predictive_insights(dropout_probability DESC);
CREATE INDEX IF NOT EXISTS idx_predictive_insights_expires_at ON public.predictive_insights(expires_at);

ALTER TABLE public.predictive_insights ENABLE ROW LEVEL SECURITY;

CREATE POLICY predictive_insights_select ON public.predictive_insights
  FOR SELECT USING (
    student_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM public.courses c
      INNER JOIN public.enrollments e ON c.id = e.course_id
      WHERE e.id = enrollment_id AND c.instructor_id = auth.uid()
    ) OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY predictive_insights_insert ON public.predictive_insights
  FOR INSERT WITH CHECK (
    student_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM public.courses c
      INNER JOIN public.enrollments e ON c.id = e.course_id
      WHERE e.id = enrollment_id AND c.instructor_id = auth.uid()
    ) OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY predictive_insights_update ON public.predictive_insights
  FOR UPDATE USING (
    student_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM public.courses c
      INNER JOIN public.enrollments e ON c.id = e.course_id
      WHERE e.id = enrollment_id AND c.instructor_id = auth.uid()
    ) OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  )
  WITH CHECK (
    student_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM public.courses c
      INNER JOIN public.enrollments e ON c.id = e.course_id
      WHERE e.id = enrollment_id AND c.instructor_id = auth.uid()
    ) OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

COMMENT ON TABLE public.predictive_insights IS 'ML-powered predictions about student outcomes, risk levels, and recommended interventions';
