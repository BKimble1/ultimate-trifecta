-- V6 social moderation: message reports.  Typed chat text is never stored
-- by the service; a reported message keeps the approved text the reporter
-- quoted (from the service-signed chat token) as evidence for moderators.
ALTER TABLE reports ADD COLUMN kind TEXT NOT NULL DEFAULT 'player';   -- player | message
ALTER TABLE reports ADD COLUMN evidence TEXT;                         -- the reported message (<= 200 chars)
ALTER TABLE reports ADD COLUMN evidence_ref TEXT;                     -- chat token id (one report per reporter per message)
CREATE UNIQUE INDEX reports_evidence ON reports(reporter_id, evidence_ref) WHERE evidence_ref IS NOT NULL;
