CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone VARCHAR(32) UNIQUE NOT NULL,
    display_name VARCHAR(120),
    role VARCHAR(20) NOT NULL DEFAULT 'USER',
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    emergency_alerts_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    location_sharing_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    is_suspended BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS otp_challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone VARCHAR(32) NOT NULL,
    code_hash VARCHAR(128) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    attempts INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_otp_challenges_phone ON otp_challenges(phone);

CREATE TABLE IF NOT EXISTS trusted_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(120) NOT NULL,
    phone VARCHAR(32) NOT NULL,
    relationship VARCHAR(80),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_trusted_contacts_user_id ON trusted_contacts(user_id);

CREATE TABLE IF NOT EXISTS regions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(120) NOT NULL,
    code VARCHAR(32) UNIQUE NOT NULL,
    boundary GEOGRAPHY(POLYGON, 4326),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS control_rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    region_id UUID REFERENCES regions(id) ON DELETE SET NULL,
    name VARCHAR(120) NOT NULL,
    email VARCHAR(120),
    phone VARCHAR(32),
    webhook_url TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS police_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    region_id UUID REFERENCES regions(id) ON DELETE SET NULL,
    name VARCHAR(120) NOT NULL,
    contact_type VARCHAR(20) NOT NULL DEFAULT 'SMS',
    endpoint TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS emergencies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    triggered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    cancellation_reason VARCHAR(120),
    initial_latitude DOUBLE PRECISION NOT NULL,
    initial_longitude DOUBLE PRECISION NOT NULL,
    initial_accuracy DOUBLE PRECISION,
    last_latitude DOUBLE PRECISION NOT NULL,
    last_longitude DOUBLE PRECISION NOT NULL,
    last_accuracy DOUBLE PRECISION,
    last_location_at TIMESTAMPTZ NOT NULL,
    network_status VARCHAR(40),
    device_status JSONB NOT NULL DEFAULT '{}'::jsonb,
    idempotency_key VARCHAR(96) NOT NULL,
    is_test BOOLEAN NOT NULL DEFAULT FALSE,
    protocol_version INTEGER NOT NULL DEFAULT 1,
    hop_count INTEGER NOT NULL DEFAULT 0,
    max_hops INTEGER NOT NULL DEFAULT 3,
    region_id UUID REFERENCES regions(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_emergency_user_idempotency UNIQUE(user_id, idempotency_key)
);
CREATE INDEX IF NOT EXISTS ix_emergencies_user_id ON emergencies(user_id);
CREATE INDEX IF NOT EXISTS ix_emergencies_status ON emergencies(status);
CREATE INDEX IF NOT EXISTS ix_emergencies_region_id ON emergencies(region_id);

CREATE TABLE IF NOT EXISTS relay_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    emergency_id UUID REFERENCES emergencies(id) ON DELETE CASCADE,
    message_id VARCHAR(96) NOT NULL,
    relayed_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    received_via VARCHAR(20) NOT NULL DEFAULT 'BLE',
    hop_count INTEGER NOT NULL DEFAULT 1,
    raw_packet JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_relay_message_id UNIQUE(emergency_id, message_id)
);
CREATE INDEX IF NOT EXISTS ix_relay_messages_emergency_id ON relay_messages(emergency_id);

CREATE TABLE IF NOT EXISTS emergency_locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    emergency_id UUID NOT NULL REFERENCES emergencies(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    accuracy DOUBLE PRECISION,
    recorded_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_emergency_locations_emergency_recorded
    ON emergency_locations(emergency_id, recorded_at);

CREATE TABLE IF NOT EXISTS helper_presence (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    is_available BOOLEAN NOT NULL DEFAULT FALSE,
    last_location GEOGRAPHY(POINT, 4326),
    last_latitude DOUBLE PRECISION,
    last_longitude DOUBLE PRECISION,
    location_updated_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_helper_presence_location ON helper_presence USING GIST(last_location);

CREATE TABLE IF NOT EXISTS emergency_responses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    emergency_id UUID NOT NULL REFERENCES emergencies(id) ON DELETE CASCADE,
    helper_user_id UUID NOT NULL REFERENCES users(id),
    response_type VARCHAR(20) NOT NULL,
    responded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_emergency_response_helper UNIQUE(emergency_id, helper_user_id)
);

CREATE TABLE IF NOT EXISTS devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    push_token TEXT NOT NULL,
    platform VARCHAR(20) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_device_user_push_token UNIQUE(user_id, push_token)
);
CREATE INDEX IF NOT EXISTS ix_devices_user_id ON devices(user_id);

CREATE TABLE IF NOT EXISTS emergency_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    emergency_id UUID NOT NULL REFERENCES emergencies(id) ON DELETE CASCADE,
    recipient_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    trusted_contact_id UUID REFERENCES trusted_contacts(id) ON DELETE SET NULL,
    notification_type VARCHAR(40) NOT NULL,
    delivery_status VARCHAR(40) NOT NULL DEFAULT 'PENDING',
    provider_message_id VARCHAR(120),
    sent_at TIMESTAMPTZ,
    opened_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS emergency_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    emergency_id UUID REFERENCES emergencies(id) ON DELETE SET NULL,
    actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(80) NOT NULL,
    context JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_emergency_audit_logs_emergency_id ON emergency_audit_logs(emergency_id);

-- Live Location Sessions: Independent, asynchronous tracking per user/session
CREATE TABLE IF NOT EXISTS live_location_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    emergency_id UUID REFERENCES emergencies(id) ON DELETE SET NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    initial_latitude DOUBLE PRECISION NOT NULL,
    initial_longitude DOUBLE PRECISION NOT NULL,
    initial_accuracy DOUBLE PRECISION,
    last_latitude DOUBLE PRECISION NOT NULL,
    last_longitude DOUBLE PRECISION NOT NULL,
    last_accuracy DOUBLE PRECISION,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_live_location_sessions_user ON live_location_sessions(user_id);
CREATE INDEX IF NOT EXISTS ix_live_location_sessions_status ON live_location_sessions(status);
CREATE INDEX IF NOT EXISTS ix_live_location_sessions_updated ON live_location_sessions(last_updated_at);

-- Live Location Updates: 5-second coordinate breadcrumbs
CREATE TABLE IF NOT EXISTS live_location_updates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES live_location_sessions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    accuracy DOUBLE PRECISION,
    recorded_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_live_location_updates_session_rec ON live_location_updates(session_id, recorded_at);
CREATE INDEX IF NOT EXISTS ix_live_location_updates_user ON live_location_updates(user_id);

