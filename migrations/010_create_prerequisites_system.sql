-- Migration: Create content sequencing and prerequisites system
-- Purpose: Define prerequisites, enforce course sequencing, and track completion paths

-- ============================================================================
-- Table 1: course_prerequisites
-- Purpose: Define what courses/exams must be completed before taking another course
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.course_prerequisites (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id         UUID NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
  prerequisite_course_id UUID REFERENCES public.courses(id) ON DELETE CASCADE,
  prerequisite_exam_id UUID REFERENCES public.exams(id) ON DELETE CASCADE,
  -- One of prerequisite_course_id or prerequisite_exam_id must be set
  min_score         SMALLINT, -- minimum score required on prerequisite exam (0-100)
  description       TEXT,
  is_required       BOOLEAN NOT NULL DEFAULT true,
  order_index       INTEGER DEFAULT 0, -- for ordering prerequisites
  created_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  CONSTRAINT check_prerequisite_type CHECK (
    (prerequisite_course_id IS NOT NULL AND prerequisite_exam_id IS NULL) OR
    (prerequisite_course_id IS NULL AND prerequisite_exam_id IS NOT NULL)
  ),
  CONSTRAINT chk_prerequisites_min_score_range CHECK (
    min_score IS NULL OR (min_score BETWEEN 0 AND 100)
  )
);

CREATE INDEX IF NOT EXISTS idx_course_prerequisites_course_id ON public.course_prerequisites(course_id);
CREATE INDEX IF NOT EXISTS idx_course_prerequisites_prerequisite_course_id ON public.course_prerequisites(prerequisite_course_id);
CREATE INDEX IF NOT EXISTS idx_course_prerequisites_prerequisite_exam_id ON public.course_prerequisites(prerequisite_exam_id);

ALTER TABLE public.course_prerequisites ENABLE ROW LEVEL SECURITY;

CREATE POLICY course_prerequisites_select ON public.course_prerequisites
  FOR SELECT USING (true);

COMMENT ON TABLE public.course_prerequisites IS 'Define prerequisite courses or exams that must be completed before enrolling in a course';
COMMENT ON COLUMN public.course_prerequisites.min_score IS 'Minimum exam score required to satisfy this prerequisite (only for exam prerequisites)';

-- ============================================================================
-- Table 2: learning_paths
-- Purpose: Define curated sequences of courses for learner progress
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.learning_paths (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title             VARCHAR(200) NOT NULL,
  description       TEXT,
  target_role       VARCHAR(50), -- e.g., 'web_developer', 'data_scientist'
  target_level      VARCHAR(20) DEFAULT 'beginner' CHECK (target_level IN ('beginner', 'intermediate', 'advanced')),
  estimated_hours   INTEGER,
  difficulty_score  SMALLINT CHECK (difficulty_score BETWEEN 1 AND 10), -- 1-10
  created_by        UUID NOT NULL REFERENCES public.users(id),
  is_published      BOOLEAN NOT NULL DEFAULT false,
  created_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_learning_paths_target_role ON public.learning_paths(target_role);
CREATE INDEX IF NOT EXISTS idx_learning_paths_target_level ON public.learning_paths(target_level);

ALTER TABLE public.learning_paths ENABLE ROW LEVEL SECURITY;

CREATE POLICY learning_paths_select ON public.learning_paths
  FOR SELECT USING (is_published OR created_by = auth.uid() OR EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'));

COMMENT ON TABLE public.learning_paths IS 'Curated learning sequences with ordered courses for specific roles or goals';

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_learning_paths_updated_at ON public.learning_paths;
CREATE TRIGGER update_learning_paths_updated_at
BEFORE UPDATE ON public.learning_paths
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================================
-- Table 3: learning_path_courses
-- Purpose: Define the sequence of courses within a learning path
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.learning_path_courses (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  learning_path_id  UUID NOT NULL REFERENCES public.learning_paths(id) ON DELETE CASCADE,
  course_id         UUID NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
  sequence_order    INTEGER NOT NULL, -- position in the path (1, 2, 3, ...)
  is_optional       BOOLEAN NOT NULL DEFAULT false,
  estimated_hours   INTEGER,
  UNIQUE (learning_path_id, course_id)
);

CREATE INDEX IF NOT EXISTS idx_learning_path_courses_learning_path_id ON public.learning_path_courses(learning_path_id);
CREATE INDEX IF NOT EXISTS idx_learning_path_courses_course_id ON public.learning_path_courses(course_id);
CREATE INDEX IF NOT EXISTS idx_learning_path_courses_sequence ON public.learning_path_courses(learning_path_id, sequence_order);

ALTER TABLE public.learning_path_courses ENABLE ROW LEVEL SECURITY;

CREATE POLICY learning_path_courses_select ON public.learning_path_courses
  FOR SELECT USING (EXISTS (
    SELECT 1 FROM public.learning_paths
    WHERE id = learning_path_id AND (
      is_published OR
      created_by = auth.uid() OR
      EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
    )
  ));

COMMENT ON TABLE public.learning_path_courses IS 'Ordered courses within a learning path';

-- ============================================================================
-- Table 4: student_learning_paths
-- Purpose: Track student progress through learning paths
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.student_learning_paths (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  learning_path_id  UUID NOT NULL REFERENCES public.learning_paths(id) ON DELETE CASCADE,
  student_id        UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  started_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  completed_at      TIMESTAMP,
  current_course_index INTEGER DEFAULT 0, -- position in the path
  progress_percentage SMALLINT DEFAULT 0 CHECK (progress_percentage BETWEEN 0 AND 100), -- 0-100%
  UNIQUE (learning_path_id, student_id)
);

CREATE INDEX IF NOT EXISTS idx_student_learning_paths_student_id ON public.student_learning_paths(student_id);
CREATE INDEX IF NOT EXISTS idx_student_learning_paths_learning_path_id ON public.student_learning_paths(learning_path_id);
CREATE INDEX IF NOT EXISTS idx_student_learning_paths_completed_at ON public.student_learning_paths(completed_at) WHERE completed_at IS NULL;

ALTER TABLE public.student_learning_paths ENABLE ROW LEVEL SECURITY;

CREATE POLICY student_learning_paths_select ON public.student_learning_paths
  FOR SELECT USING (student_id = auth.uid() OR EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role IN ('admin', 'teacher')));

COMMENT ON TABLE public.student_learning_paths IS 'Track student progress through a learning path';

-- ============================================================================
-- Table 5: adaptive_content_branches
-- Purpose: Define branching paths based on learner performance
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.adaptive_content_branches (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lesson_id         UUID NOT NULL REFERENCES public.lessons(id) ON DELETE CASCADE,
  quiz_id           UUID REFERENCES public.exams(id) ON DELETE SET NULL,

  -- Branching logic
  score_threshold_low  SMALLINT, -- if score <= this, take remedial path
  score_threshold_high SMALLINT, -- if score >= this, take advanced path

  -- Paths
  remedial_lesson_id   UUID REFERENCES public.lessons(id) ON DELETE SET NULL,
  advanced_lesson_id   UUID REFERENCES public.lessons(id) ON DELETE SET NULL,
  default_lesson_id    UUID REFERENCES public.lessons(id) ON DELETE SET NULL,

  is_active         BOOLEAN NOT NULL DEFAULT true,
  created_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_adaptive_content_branches_low_threshold_range CHECK (
    score_threshold_low IS NULL OR score_threshold_low BETWEEN 0 AND 100
  ),
  CONSTRAINT chk_adaptive_content_branches_high_threshold_range CHECK (
    score_threshold_high IS NULL OR score_threshold_high BETWEEN 0 AND 100
  ),
  CONSTRAINT chk_adaptive_content_branches_threshold_order CHECK (
    score_threshold_low IS NULL OR
    score_threshold_high IS NULL OR
    score_threshold_low <= score_threshold_high
  )
);

CREATE INDEX IF NOT EXISTS idx_adaptive_content_branches_lesson_id ON public.adaptive_content_branches(lesson_id);
CREATE INDEX IF NOT EXISTS idx_adaptive_content_branches_quiz_id ON public.adaptive_content_branches(quiz_id);

ALTER TABLE public.adaptive_content_branches ENABLE ROW LEVEL SECURITY;

CREATE POLICY adaptive_content_branches_select ON public.adaptive_content_branches
  FOR SELECT USING (true);

COMMENT ON TABLE public.adaptive_content_branches IS 'Adaptive branching: route students to remedial or advanced content based on quiz performance';
COMMENT ON COLUMN public.adaptive_content_branches.score_threshold_low IS 'If quiz score is <= this, student takes remedial path';
COMMENT ON COLUMN public.adaptive_content_branches.score_threshold_high IS 'If quiz score is >= this, student takes advanced path';
COMMENT ON COLUMN public.adaptive_content_branches.default_lesson_id IS 'Fallback lesson used when score lies between low and high thresholds';

-- ============================================================================
-- Table 6: prerequisite_completion_tracking
-- Purpose: Track which prerequisites students have satisfied
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.prerequisite_completion_tracking (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id        UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  course_id         UUID NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
  prerequisite_id   UUID NOT NULL REFERENCES public.course_prerequisites(id) ON DELETE CASCADE,

  -- Completion details
  completed_at      TIMESTAMP NOT NULL DEFAULT NOW(),
  score             SMALLINT CHECK (score BETWEEN 0 AND 100), -- if prerequisite is an exam
  is_satisfied      BOOLEAN NOT NULL DEFAULT false,

  UNIQUE (student_id, prerequisite_id)
);

CREATE INDEX IF NOT EXISTS idx_prerequisite_completion_student_id ON public.prerequisite_completion_tracking(student_id);
CREATE INDEX IF NOT EXISTS idx_prerequisite_completion_course_id ON public.prerequisite_completion_tracking(course_id);
CREATE INDEX IF NOT EXISTS idx_prerequisite_completion_prerequisite_id ON public.prerequisite_completion_tracking(prerequisite_id);

ALTER TABLE public.prerequisite_completion_tracking ENABLE ROW LEVEL SECURITY;

CREATE POLICY prerequisite_completion_select ON public.prerequisite_completion_tracking
  FOR SELECT USING (student_id = auth.uid() OR EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role IN ('admin', 'teacher')));

COMMENT ON TABLE public.prerequisite_completion_tracking IS 'Track which students have completed prerequisite requirements';
