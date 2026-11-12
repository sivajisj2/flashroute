CREATE TABLE IF NOT EXISTS executions (
    id UUID PRIMARY KEY,
    status TEXT NOT NULL CHECK(status IN ('ready','submitting','submitted','confirmed','reverted','failed','unknown','expired')),
    transaction JSONB NOT NULL,
    opportunity JSONB NOT NULL,
    receipt JSONB,
    gas BIGINT NOT NULL,
    expires_at BIGINT NOT NULL,
    tx_hash TEXT UNIQUE,
    error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS executions_pending ON executions(status) WHERE status IN ('submitted','submitting','ready');
CREATE INDEX IF NOT EXISTS executions_created ON executions(created_at DESC);
