
BEGIN;

-- =====================================================
-- FITOUT360
-- Migration: 002_fitout_applications.sql
-- Purpose: Fit-out application and commencement workflow
-- =====================================================

-- 1. Fit-out applications
CREATE TABLE fitout_applications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    application_number VARCHAR(50) NOT NULL UNIQUE,

    flat_id UUID NOT NULL
        REFERENCES flats(id) ON DELETE RESTRICT,

    submitted_by UUID NOT NULL
        REFERENCES users(id) ON DELETE RESTRICT,

    application_status VARCHAR(30) NOT NULL DEFAULT 'draft'
        CHECK (
            application_status IN (
                'draft',
                'submitted',
                'under_review',
                'correction_required',
                'approved',
                'rejected',
                'cancelled',
                'closed'
            )
        ),

    commencement_status VARCHAR(30) NOT NULL DEFAULT 'not_ready'
        CHECK (
            commencement_status IN (
                'not_ready',
                'pending_checks',
                'ready_for_authorization',
                'authorized',
                'blocked'
            )
        ),

    work_status VARCHAR(30) NOT NULL DEFAULT 'not_started'
        CHECK (
            work_status IN (
                'not_started',
                'in_progress',
                'completion_submitted',
                'first_inspection',
                'rectification',
                'final_inspection',
                'completed'
            )
        ),

    proposed_start_date DATE,
    actual_start_date DATE,
    actual_completion_date DATE,

    submitted_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_application_actual_dates
        CHECK (
            actual_start_date IS NULL
            OR actual_completion_date IS NULL
            OR actual_completion_date >= actual_start_date
        ),

    CONSTRAINT chk_authorization_requires_approval
        CHECK (
            commencement_status <> 'authorized'
            OR application_status IN ('approved', 'closed')
        )
);

-- One non-terminal application per flat.
-- Rejected, cancelled and closed applications are historical.
CREATE UNIQUE INDEX uq_one_active_application_per_flat
    ON fitout_applications(flat_id)
    WHERE application_status NOT IN (
        'rejected',
        'cancelled',
        'closed'
    );

-- 2. Application review history
CREATE TABLE application_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    application_id UUID NOT NULL
        REFERENCES fitout_applications(id) ON DELETE RESTRICT,

    reviewer_id UUID NOT NULL
        REFERENCES users(id) ON DELETE RESTRICT,

    decision VARCHAR(30) NOT NULL
        CHECK (
            decision IN (
                'approved',
                'rejected',
                'correction_required'
            )
        ),

    comments TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Commencement readiness checks
CREATE TABLE commencement_checks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    application_id UUID NOT NULL
        REFERENCES fitout_applications(id) ON DELETE RESTRICT,

    check_type VARCHAR(80) NOT NULL,

    check_round SMALLINT NOT NULL DEFAULT 1
        CHECK (check_round >= 1),

    is_required BOOLEAN NOT NULL DEFAULT TRUE,

    check_status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (
            check_status IN (
                'pending',
                'submitted',
                'verified',
                'rejected',
                'not_applicable'
            )
        ),

    verified_by UUID
        REFERENCES users(id) ON DELETE RESTRICT,

    verified_at TIMESTAMPTZ,

    notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_application_check_round
        UNIQUE (application_id, check_type, check_round),

    CONSTRAINT chk_verified_check_has_reviewer
        CHECK (
            check_status <> 'verified'
            OR (
                verified_by IS NOT NULL
                AND verified_at IS NOT NULL
            )
        ),

    CONSTRAINT chk_not_applicable_not_required
        CHECK (
            check_status <> 'not_applicable'
            OR is_required = FALSE
        )
);

-- 4. Indexes
CREATE INDEX idx_applications_flat
    ON fitout_applications(flat_id);

CREATE INDEX idx_applications_status
    ON fitout_applications(application_status);

CREATE INDEX idx_applications_commencement
    ON fitout_applications(commencement_status);

CREATE INDEX idx_applications_work_status
    ON fitout_applications(work_status);

CREATE INDEX idx_reviews_application
    ON application_reviews(application_id);

CREATE INDEX idx_checks_application
    ON commencement_checks(application_id);

CREATE INDEX idx_checks_status
    ON commencement_checks(check_status);

-- 5. Record migration
INSERT INTO schema_migrations (version, filename)
VALUES ('002', '002_fitout_applications.sql');

COMMIT;
