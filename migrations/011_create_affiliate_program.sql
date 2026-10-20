-- Migration: Create affiliate program and commission tracking system
-- Purpose: Enable instructors/creators to earn commissions through referrals

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- Table 1: affiliates
-- Purpose: Store affiliate program participants and their settings
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.affiliates (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  referral_code     VARCHAR(50) NOT NULL UNIQUE,
  commission_rate   NUMERIC(5,2) NOT NULL DEFAULT 10.00, -- percentage (0-100)
  status            VARCHAR(20) NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active', 'inactive', 'suspended')),
  total_referrals   INTEGER DEFAULT 0,
  total_earnings    NUMERIC(15,2) DEFAULT 0,
  monthly_earnings  NUMERIC(15,2) DEFAULT 0,
  bio               TEXT,
  social_links      JSONB, -- { twitter, linkedin, instagram, website }
  is_verified       BOOLEAN NOT NULL DEFAULT false,
  verification_date TIMESTAMP,
  bank_details_encrypted BYTEA, -- encrypted with pgp_sym_encrypt before persistence
  created_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_affiliates_user_id ON public.affiliates(user_id);
CREATE INDEX IF NOT EXISTS idx_affiliates_referral_code ON public.affiliates(referral_code);
CREATE INDEX IF NOT EXISTS idx_affiliates_status ON public.affiliates(status);
CREATE INDEX IF NOT EXISTS idx_affiliates_is_verified ON public.affiliates(is_verified);

ALTER TABLE public.affiliates ENABLE ROW LEVEL SECURITY;

CREATE POLICY affiliates_select ON public.affiliates
  FOR SELECT USING (
    user_id = auth.uid() OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY affiliates_update ON public.affiliates
  FOR UPDATE USING (user_id = auth.uid() OR EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'));

COMMENT ON TABLE public.affiliates IS 'Affiliate program participants with referral codes and earnings tracking';
COMMENT ON COLUMN public.affiliates.referral_code IS 'Unique code for tracking referrals (e.g., AFFILIATE_ABC123)';
COMMENT ON COLUMN public.affiliates.bank_details_encrypted IS 'Encrypted bank details payload (BYTEA). Store only encrypted data, decrypt in trusted service paths.';

-- ============================================================================
-- Table 2: referral_links
-- Purpose: Track referral links and their usage
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.referral_links (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  affiliate_id      UUID NOT NULL REFERENCES public.affiliates(id) ON DELETE CASCADE,
  course_id         UUID REFERENCES public.courses(id) ON DELETE CASCADE,
  product_id        UUID REFERENCES public.products(id) ON DELETE SET NULL, -- for digital products
  tracking_code     VARCHAR(100) NOT NULL UNIQUE,
  short_url         VARCHAR(100), -- shortened link (e.g., ajak.io/ref/abc123)
  clicks            INTEGER DEFAULT 0,
  conversions       INTEGER DEFAULT 0,
  conversion_rate   NUMERIC(5,2) DEFAULT 0, -- percentage
  created_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  last_clicked_at   TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_referral_links_affiliate_id ON public.referral_links(affiliate_id);
CREATE INDEX IF NOT EXISTS idx_referral_links_tracking_code ON public.referral_links(tracking_code);
CREATE INDEX IF NOT EXISTS idx_referral_links_course_id ON public.referral_links(course_id);

ALTER TABLE public.referral_links ENABLE ROW LEVEL SECURITY;

CREATE POLICY referral_links_select ON public.referral_links
  FOR SELECT USING (EXISTS (SELECT 1 FROM public.affiliates WHERE id = affiliate_id AND user_id = auth.uid()));

COMMENT ON TABLE public.referral_links IS 'Specific referral links for each affiliate, course, or product';

-- ============================================================================
-- Table 3: affiliate_commissions
-- Purpose: Track individual commissions earned from referrals
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.affiliate_commissions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  affiliate_id      UUID NOT NULL REFERENCES public.affiliates(id) ON DELETE CASCADE,
  order_id          UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  course_id         UUID REFERENCES public.courses(id) ON DELETE CASCADE,
  referral_link_id  UUID REFERENCES public.referral_links(id) ON DELETE SET NULL,

  -- Commission calculation
  order_amount      NUMERIC(15,2) NOT NULL, -- original order amount in INR
  commission_rate   NUMERIC(5,2) NOT NULL,  -- percentage at time of transaction
  commission_amount NUMERIC(15,2) NOT NULL, -- calculated commission
  status            VARCHAR(20) NOT NULL DEFAULT 'earned'
                    CHECK (status IN ('earned', 'pending_verification', 'approved', 'paid', 'rejected')),

  -- Tracking
  earned_at         TIMESTAMP NOT NULL DEFAULT NOW(),
  verified_at       TIMESTAMP,
  paid_at           TIMESTAMP,
  payout_id         UUID,

  notes             TEXT
);

CREATE INDEX IF NOT EXISTS idx_affiliate_commissions_affiliate_id ON public.affiliate_commissions(affiliate_id);
CREATE INDEX IF NOT EXISTS idx_affiliate_commissions_order_id ON public.affiliate_commissions(order_id);
CREATE INDEX IF NOT EXISTS idx_affiliate_commissions_status ON public.affiliate_commissions(status);
CREATE INDEX IF NOT EXISTS idx_affiliate_commissions_earned_at ON public.affiliate_commissions(earned_at);

ALTER TABLE public.affiliate_commissions ENABLE ROW LEVEL SECURITY;

CREATE POLICY affiliate_commissions_select ON public.affiliate_commissions
  FOR SELECT USING (EXISTS (SELECT 1 FROM public.affiliates WHERE id = affiliate_id AND user_id = auth.uid()));

COMMENT ON TABLE public.affiliate_commissions IS 'Individual commissions earned from referral-sourced orders';
COMMENT ON COLUMN public.affiliate_commissions.status IS 'earned (newly recorded), pending_verification (awaiting review), approved (verified), paid (payment processed), rejected';

-- ============================================================================
-- Table 4: affiliate_payouts
-- Purpose: Track payout requests and payments to affiliates
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.affiliate_payouts (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  affiliate_id      UUID NOT NULL REFERENCES public.affiliates(id) ON DELETE CASCADE,

  -- Payout details
  payout_period_start DATE NOT NULL,
  payout_period_end   DATE NOT NULL,
  total_commissions   NUMERIC(15,2) NOT NULL,
  total_approved      NUMERIC(15,2) NOT NULL, -- after deductions/holds
  platform_fee       NUMERIC(15,2) DEFAULT 0, -- transaction fee
  net_payout         NUMERIC(15,2) NOT NULL,

  -- Payment info
  payout_method      VARCHAR(50) NOT NULL DEFAULT 'bank_transfer'
                     CHECK (payout_method IN ('bank_transfer', 'upi', 'wallet', 'crypto')),
  payment_reference  VARCHAR(200), -- transaction ID from payment processor
  status             VARCHAR(20) NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),

  -- Tracking
  requested_at       TIMESTAMP NOT NULL DEFAULT NOW(),
  processed_at       TIMESTAMP,
  paid_at            TIMESTAMP,
  failure_reason     TEXT,

  created_at         TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_affiliate_payouts_affiliate_id ON public.affiliate_payouts(affiliate_id);
CREATE INDEX IF NOT EXISTS idx_affiliate_payouts_status ON public.affiliate_payouts(status);
CREATE INDEX IF NOT EXISTS idx_affiliate_payouts_payout_period_start ON public.affiliate_payouts(payout_period_start);

ALTER TABLE public.affiliate_payouts ENABLE ROW LEVEL SECURITY;

CREATE POLICY affiliate_payouts_select ON public.affiliate_payouts
  FOR SELECT USING (EXISTS (SELECT 1 FROM public.affiliates WHERE id = affiliate_id AND user_id = auth.uid()));

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint c
    WHERE c.conname = 'fk_affiliate_commissions_payout_id'
  ) THEN
    ALTER TABLE public.affiliate_commissions
      ADD CONSTRAINT fk_affiliate_commissions_payout_id
      FOREIGN KEY (payout_id) REFERENCES public.affiliate_payouts(id) ON DELETE SET NULL;
  END IF;
END $$;

COMMENT ON TABLE public.affiliate_payouts IS 'Payout requests and payment records for affiliates';
COMMENT ON COLUMN public.affiliate_payouts.platform_fee IS 'Fee charged by platform for payment processing (0-5%)';

-- ============================================================================
-- Table 5: affiliate_performance_metrics
-- Purpose: Pre-aggregated metrics for affiliate dashboard
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.affiliate_performance_metrics (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  affiliate_id      UUID NOT NULL REFERENCES public.affiliates(id) ON DELETE CASCADE,
  metric_date       DATE NOT NULL,

  -- Daily metrics
  clicks            INTEGER DEFAULT 0,
  conversions       INTEGER DEFAULT 0,
  conversion_rate   NUMERIC(5,2) DEFAULT 0,
  revenue_generated NUMERIC(15,2) DEFAULT 0,
  commissions_earned NUMERIC(15,2) DEFAULT 0,

  created_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE (affiliate_id, metric_date)
);

CREATE INDEX IF NOT EXISTS idx_affiliate_performance_metrics_affiliate_id ON public.affiliate_performance_metrics(affiliate_id);
CREATE INDEX IF NOT EXISTS idx_affiliate_performance_metrics_metric_date ON public.affiliate_performance_metrics(metric_date);

ALTER TABLE public.affiliate_performance_metrics ENABLE ROW LEVEL SECURITY;

CREATE POLICY affiliate_performance_metrics_select ON public.affiliate_performance_metrics
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.affiliates WHERE id = affiliate_id AND user_id = auth.uid()) OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY affiliate_performance_metrics_insert ON public.affiliate_performance_metrics
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.affiliates WHERE id = affiliate_id AND user_id = auth.uid()) OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY affiliate_performance_metrics_update ON public.affiliate_performance_metrics
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM public.affiliates WHERE id = affiliate_id AND user_id = auth.uid()) OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.affiliates WHERE id = affiliate_id AND user_id = auth.uid()) OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY affiliate_performance_metrics_delete ON public.affiliate_performance_metrics
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM public.affiliates WHERE id = affiliate_id AND user_id = auth.uid()) OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

COMMENT ON TABLE public.affiliate_performance_metrics IS 'Daily aggregated performance data for affiliate dashboards';

-- ============================================================================
-- Table 6: affiliate_tiers
-- Purpose: Define commission tiers based on performance
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.affiliate_tiers (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name              VARCHAR(50) NOT NULL, -- Bronze, Silver, Gold, Platinum
  min_monthly_earnings NUMERIC(15,2),
  min_referrals     INTEGER,
  commission_boost  NUMERIC(5,2) DEFAULT 0, -- additional percentage points
  benefits          JSONB, -- { marketing_materials, priority_support, exclusive_products }
  is_active         BOOLEAN NOT NULL DEFAULT true,
  created_at        TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_affiliate_tiers_is_active ON public.affiliate_tiers(is_active);

ALTER TABLE public.affiliate_tiers ENABLE ROW LEVEL SECURITY;

CREATE POLICY affiliate_tiers_select ON public.affiliate_tiers
  FOR SELECT USING (is_active OR EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'));

COMMENT ON TABLE public.affiliate_tiers IS 'Commission tier definitions with thresholds and benefits';

-- ============================================================================
-- Insert default affiliate tiers
-- ============================================================================

INSERT INTO public.affiliate_tiers (name, min_monthly_earnings, min_referrals, commission_boost, benefits) VALUES
  (
    'Bronze',
    0,
    1,
    0,
    '{"marketing_materials": false, "priority_support": false, "exclusive_products": false}'::jsonb
  ),
  (
    'Silver',
    5000,
    20,
    2,
    '{"marketing_materials": true, "priority_support": false, "exclusive_products": false}'::jsonb
  ),
  (
    'Gold',
    15000,
    50,
    5,
    '{"marketing_materials": true, "priority_support": true, "exclusive_products": false}'::jsonb
  ),
  (
    'Platinum',
    50000,
    150,
    10,
    '{"marketing_materials": true, "priority_support": true, "exclusive_products": true}'::jsonb
  )
  ON CONFLICT DO NOTHING;
