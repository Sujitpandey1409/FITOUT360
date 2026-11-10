
BEGIN;

-- =====================================================
-- FITOUT360
-- Migration: 001_initial_core.sql
-- Purpose: Initial project, tower, flat and user schema
-- PostgreSQL: 18+
-- =====================================================

-- 1. Migration history
CREATE TABLE schema_migrations (
    version VARCHAR(20) PRIMARY KEY,
    filename VARCHAR(255) NOT NULL UNIQUE,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Projects
CREATE TABLE projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(150) NOT NULL,
    code VARCHAR(50) NOT NULL UNIQUE,
    location TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'inactive', 'archived')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Towers
CREATE TABLE towers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL
        REFERENCES projects(id) ON DELETE RESTRICT,
    tower_name VARCHAR(30) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_tower_project_name
        UNIQUE (project_id, tower_name)
);

-- 4. Flats
CREATE TABLE flats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tower_id UUID NOT NULL
        REFERENCES towers(id) ON DELETE RESTRICT,
    floor_number SMALLINT NOT NULL,
    flat_number INTEGER NOT NULL,
    unit_position SMALLINT NOT NULL,
    unit_type VARCHAR(20) NOT NULL DEFAULT 'residential'
        CHECK (unit_type IN ('residential', 'refuge')),
    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'inactive')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_flat_floor
        CHECK (floor_number BETWEEN 1 AND 23),

    CONSTRAINT chk_flat_position
        CHECK (
            (floor_number = 1 AND unit_position BETWEEN 1 AND 6)
            OR
            (floor_number BETWEEN 2 AND 23
                AND unit_position BETWEEN 1 AND 8)
        ),

    CONSTRAINT chk_flat_number
        CHECK (flat_number = floor_number * 100 + unit_position),

    CONSTRAINT uq_tower_flat_number
        UNIQUE (tower_id, flat_number)
);

-- 5. Users
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(255) NOT NULL,
    password_hash TEXT,
    account_status VARCHAR(20) NOT NULL DEFAULT 'invited'
        CHECK (
            account_status IN (
                'invited', 'active', 'suspended', 'disabled'
            )
        ),
    email_verified_at TIMESTAMPTZ,
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX uq_users_email_lower
    ON users (LOWER(email));

-- 6. Roles
CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 7. User role assignments
CREATE TABLE user_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL
        REFERENCES users(id) ON DELETE RESTRICT,
    role_id UUID NOT NULL
        REFERENCES roles(id) ON DELETE RESTRICT,
    project_id UUID
        REFERENCES projects(id) ON DELETE RESTRICT,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    assigned_by UUID
        REFERENCES users(id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX uq_user_role_scope
    ON user_roles (
        user_id,
        role_id,
        COALESCE(
            project_id,
            '00000000-0000-0000-0000-000000000000'::UUID
        )
    );

-- 8. Flat access
CREATE TABLE flat_access (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL
        REFERENCES users(id) ON DELETE RESTRICT,
    flat_id UUID NOT NULL
        REFERENCES flats(id) ON DELETE RESTRICT,
    access_type VARCHAR(35) NOT NULL
        CHECK (
            access_type IN (
                'owner',
                'authorized_representative',
                'contractor_representative'
            )
        ),
    access_status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (access_status IN ('active', 'revoked')),
    granted_by UUID
        REFERENCES users(id) ON DELETE RESTRICT,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMPTZ,

    CONSTRAINT chk_flat_access_revocation
        CHECK (
            (access_status = 'active' AND revoked_at IS NULL)
            OR
            (access_status = 'revoked' AND revoked_at IS NOT NULL)
        )
);

CREATE UNIQUE INDEX uq_active_user_flat_access
    ON flat_access (user_id, flat_id)
    WHERE access_status = 'active';

-- 9. Seed initial system roles
INSERT INTO roles (role_name, description)
VALUES
    ('super_admin', 'Global system administrator'),
    ('admin', 'Project administrator'),
    ('pm', 'Property management user'),
    ('owner', 'Flat owner'),
    ('contractor', 'Contractor user');

-- 10. Useful indexes
CREATE INDEX idx_towers_project
    ON towers(project_id);

CREATE INDEX idx_flats_tower_floor
    ON flats(tower_id, floor_number);

CREATE INDEX idx_user_roles_user
    ON user_roles(user_id);

CREATE INDEX idx_user_roles_project
    ON user_roles(project_id);

CREATE INDEX idx_flat_access_flat
    ON flat_access(flat_id);

-- Record successful migration
INSERT INTO schema_migrations (version, filename)
VALUES ('001', '001_initial_core.sql');

COMMIT;
