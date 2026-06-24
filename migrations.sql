-- qb-management migrations (idempotent)
-- Runtime also applies equivalent migrations in server/main.lua.

CREATE TABLE IF NOT EXISTS bossmenu_accounts (
  job VARCHAR(64) NOT NULL PRIMARY KEY,
  balance BIGINT NOT NULL DEFAULT 0,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS bossmenu_ledger (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  job VARCHAR(64) NOT NULL,
  action VARCHAR(32) NOT NULL,
  amount INT NOT NULL,
  actor_identifier VARCHAR(80) NULL,
  target_identifier VARCHAR(80) NULL,
  note VARCHAR(255) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_job_created (job, created_at)
);

CREATE TABLE IF NOT EXISTS bossmenu_audit (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  job VARCHAR(64) NOT NULL,
  action VARCHAR(64) NOT NULL,
  actor_identifier VARCHAR(80) NULL,
  target_identifier VARCHAR(80) NULL,
  payload JSON NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_job_created (job, created_at)
);

ALTER TABLE bossmenu_audit ADD COLUMN IF NOT EXISTS org_type VARCHAR(16) NULL;
ALTER TABLE bossmenu_audit ADD COLUMN IF NOT EXISTS org_name VARCHAR(64) NULL;
ALTER TABLE bossmenu_audit ADD COLUMN IF NOT EXISTS actor_name VARCHAR(120) NULL;
ALTER TABLE bossmenu_audit ADD COLUMN IF NOT EXISTS target_name VARCHAR(120) NULL;
ALTER TABLE bossmenu_audit ADD COLUMN IF NOT EXISTS metadata_json JSON NULL;

CREATE TABLE IF NOT EXISTS bossmenu_gangs (
  name VARCHAR(64) NOT NULL PRIMARY KEY,
  label VARCHAR(80) NOT NULL,
  max_grade INT NOT NULL DEFAULT 4,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS bossmenu_gang_members (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  gang_name VARCHAR(64) NOT NULL,
  identifier VARCHAR(80) NOT NULL,
  grade INT NOT NULL DEFAULT 0,
  joined_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_gang_identifier (gang_name, identifier),
  UNIQUE KEY uq_identifier (identifier),
  INDEX idx_gang_grade (gang_name, grade)
);

CREATE TABLE IF NOT EXISTS bossmenu_rank_permissions (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  org_type VARCHAR(16) NOT NULL,
  org_name VARCHAR(64) NOT NULL,
  grade INT NOT NULL,
  permission_key VARCHAR(64) NOT NULL,
  allowed TINYINT(1) NOT NULL DEFAULT 0,
  updated_by VARCHAR(80) NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_rank_permission (org_type, org_name, grade, permission_key)
);

CREATE TABLE IF NOT EXISTS bossmenu_custom_ranks (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  org_type VARCHAR(16) NOT NULL,
  org_name VARCHAR(64) NOT NULL,
  grade INT NOT NULL,
  rank_name VARCHAR(64) NOT NULL,
  rank_icon VARCHAR(64) NULL,
  rank_style JSON NULL,
  salary_type VARCHAR(24) NULL,
  salary_amount INT NULL,
  description TEXT NULL,
  protected_rank TINYINT(1) NOT NULL DEFAULT 0,
  created_by VARCHAR(80) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_custom_rank (org_type, org_name, grade)
);

CREATE TABLE IF NOT EXISTS bossmenu_employee_profiles (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  org_type VARCHAR(16) NOT NULL,
  org_name VARCHAR(64) NOT NULL,
  identifier VARCHAR(80) NOT NULL,
  joined_at DATETIME NULL,
  hired_by VARCHAR(80) NULL,
  notes TEXT NULL,
  strikes INT NOT NULL DEFAULT 0,
  photo_url LONGTEXT NULL,
  metadata JSON NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_profile (org_type, org_name, identifier)
);

ALTER TABLE bossmenu_employee_profiles
  MODIFY COLUMN photo_url LONGTEXT NULL;

CREATE TABLE IF NOT EXISTS bossmenu_employee_activity (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  org_type VARCHAR(16) NOT NULL,
  org_name VARCHAR(64) NOT NULL,
  identifier VARCHAR(80) NOT NULL,
  action VARCHAR(64) NOT NULL,
  details JSON NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_emp_activity (org_type, org_name, identifier, created_at)
);

CREATE TABLE IF NOT EXISTS bossmenu_salary_overrides (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  org_type VARCHAR(16) NOT NULL,
  org_name VARCHAR(64) NOT NULL,
  identifier VARCHAR(80) NULL,
  grade INT NULL,
  salary_type VARCHAR(24) NOT NULL DEFAULT 'custom',
  salary_amount INT NOT NULL DEFAULT 0,
  updated_by VARCHAR(80) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS bossmenu_payroll_runs (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  org_type VARCHAR(16) NOT NULL,
  org_name VARCHAR(64) NOT NULL,
  run_type VARCHAR(16) NOT NULL DEFAULT 'manual',
  total_amount INT NOT NULL DEFAULT 0,
  paid_count INT NOT NULL DEFAULT 0,
  failed_count INT NOT NULL DEFAULT 0,
  status VARCHAR(24) NOT NULL DEFAULT 'completed',
  metadata JSON NULL,
  created_by VARCHAR(80) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_payroll_org_created (org_type, org_name, created_at)
);

CREATE TABLE IF NOT EXISTS bossmenu_org_inventory (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  org_type VARCHAR(16) NOT NULL,
  org_name VARCHAR(64) NOT NULL,
  item_name VARCHAR(80) NOT NULL,
  amount INT NOT NULL DEFAULT 0,
  metadata JSON NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_org_item (org_type, org_name, item_name)
);

CREATE TABLE IF NOT EXISTS bossmenu_org_inventory_logs (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  org_type VARCHAR(16) NOT NULL,
  org_name VARCHAR(64) NOT NULL,
  action VARCHAR(24) NOT NULL,
  item_name VARCHAR(80) NOT NULL,
  amount INT NOT NULL,
  actor_identifier VARCHAR(80) NULL,
  target_identifier VARCHAR(80) NULL,
  metadata JSON NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_org_item_logs (org_type, org_name, created_at)
);

CREATE TABLE IF NOT EXISTS bossmenu_org_uniforms (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  org_type VARCHAR(16) NOT NULL,
  org_name VARCHAR(64) NOT NULL,
  uniform_name VARCHAR(80) NOT NULL,
  male_data JSON NULL,
  female_data JSON NULL,
  rank_map JSON NULL,
  created_by VARCHAR(80) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS bossmenu_org_markers (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  org_type VARCHAR(16) NOT NULL,
  org_name VARCHAR(64) NOT NULL,
  marker_type VARCHAR(32) NOT NULL,
  coords JSON NOT NULL,
  marker_data JSON NULL,
  created_by VARCHAR(80) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS bossmenu_org_garages (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  org_type VARCHAR(16) NOT NULL,
  org_name VARCHAR(64) NOT NULL,
  name VARCHAR(80) NOT NULL,
  coords JSON NOT NULL,
  options_json JSON NULL,
  created_by VARCHAR(80) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS bossmenu_job_applications (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  org_type VARCHAR(16) NOT NULL,
  org_name VARCHAR(64) NOT NULL,
  applicant_identifier VARCHAR(80) NULL,
  applicant_name VARCHAR(120) NOT NULL,
  applicant_phone VARCHAR(40) NULL,
  answers JSON NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'pending',
  decision_reason VARCHAR(255) NULL,
  decided_by VARCHAR(80) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS bossmenu_announcements (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  org_type VARCHAR(16) NOT NULL,
  org_name VARCHAR(64) NOT NULL,
  title VARCHAR(120) NOT NULL,
  body TEXT NOT NULL,
  pinned TINYINT(1) NOT NULL DEFAULT 0,
  visibility_json JSON NULL,
  expires_at DATETIME NULL,
  created_by VARCHAR(80) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS bossmenu_admin_actions (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  admin_identifier VARCHAR(80) NOT NULL,
  action VARCHAR(64) NOT NULL,
  org_type VARCHAR(16) NULL,
  org_name VARCHAR(64) NULL,
  target_identifier VARCHAR(80) NULL,
  metadata JSON NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS bossmenu_webhook_settings (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  scope_type VARCHAR(16) NOT NULL,
  org_type VARCHAR(16) NOT NULL DEFAULT '',
  org_name VARCHAR(64) NOT NULL DEFAULT '',
  category VARCHAR(32) NOT NULL,
  webhook_url TEXT NULL,
  enabled TINYINT(1) NOT NULL DEFAULT 1,
  updated_by VARCHAR(80) NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_webhook_scope (scope_type, org_type, org_name, category),
  INDEX idx_webhook_scope (scope_type, org_type, org_name)
);

CREATE TABLE IF NOT EXISTS bossmenu_org_state (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  org_type VARCHAR(16) NOT NULL,
  org_name VARCHAR(64) NOT NULL,
  disabled TINYINT(1) NOT NULL DEFAULT 0,
  reason VARCHAR(255) NULL,
  updated_by VARCHAR(80) NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_org_state (org_type, org_name)
);

CREATE TABLE IF NOT EXISTS bossmenu_tax_accounts (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  org_type VARCHAR(16) NOT NULL,
  org_name VARCHAR(64) NOT NULL,
  balance_due INT NOT NULL DEFAULT 0,
  next_due_at DATETIME NULL,
  grace_ends_at DATETIME NULL,
  metadata JSON NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_tax_account (org_type, org_name)
);

CREATE TABLE IF NOT EXISTS bossmenu_bills_invoices (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  org_type VARCHAR(16) NOT NULL,
  org_name VARCHAR(64) NOT NULL,
  issuer_identifier VARCHAR(80) NOT NULL,
  target_identifier VARCHAR(80) NULL,
  target_org_type VARCHAR(16) NULL,
  target_org_name VARCHAR(64) NULL,
  amount INT NOT NULL,
  reason VARCHAR(255) NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'pending',
  metadata JSON NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS bossmenu_scheduled_tasks (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  module_name VARCHAR(40) NOT NULL,
  task_type VARCHAR(48) NOT NULL,
  payload JSON NULL,
  next_run_at DATETIME NULL,
  last_run_at DATETIME NULL,
  enabled TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_sched_next_run (enabled, next_run_at)
);

CREATE TABLE IF NOT EXISTS bossmenu_gang_notoriety (
  gang_name VARCHAR(64) NOT NULL PRIMARY KEY,
  points INT NOT NULL DEFAULT 0,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS bossmenu_gang_markers (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  gang_name VARCHAR(64) NOT NULL,
  marker_type VARCHAR(32) NOT NULL,
  coords JSON NOT NULL,
  marker_data JSON NULL,
  created_by VARCHAR(80) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS bossmenu_gang_territories (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  territory_name VARCHAR(80) NOT NULL,
  territory_type VARCHAR(32) NOT NULL DEFAULT 'basic',
  owner_gang VARCHAR(64) NULL,
  coords JSON NOT NULL,
  metadata JSON NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_territory_name (territory_name)
);

CREATE TABLE IF NOT EXISTS bossmenu_gang_rackets (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  gang_name VARCHAR(64) NOT NULL,
  territory_name VARCHAR(80) NULL,
  level INT NOT NULL DEFAULT 1,
  stored_income INT NOT NULL DEFAULT 0,
  upgrades JSON NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS bossmenu_gang_graffiti (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  gang_name VARCHAR(64) NOT NULL,
  style_name VARCHAR(64) NULL,
  text_label VARCHAR(120) NULL,
  coords JSON NOT NULL,
  metadata JSON NULL,
  expires_at DATETIME NULL,
  placed_by VARCHAR(80) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE bossmenu_gang_graffiti
  ADD COLUMN IF NOT EXISTS metadata JSON NULL;

CREATE TABLE IF NOT EXISTS bossmenu_gang_contracts (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  gang_name VARCHAR(64) NOT NULL,
  contract_type VARCHAR(40) NOT NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'available',
  reward_json JSON NULL,
  payload JSON NULL,
  accepted_by VARCHAR(80) NULL,
  accepted_at DATETIME NULL,
  completed_at DATETIME NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS bossmenu_hidden_workshop_profiles (
  gang_name VARCHAR(64) NOT NULL PRIMARY KEY,
  reputation INT NOT NULL DEFAULT 0,
  level INT NOT NULL DEFAULT 1,
  jobs_completed INT NOT NULL DEFAULT 0,
  jobs_failed INT NOT NULL DEFAULT 0,
  early_cashouts INT NOT NULL DEFAULT 0,
  cars_stripped INT NOT NULL DEFAULT 0,
  total_cash_earned INT NOT NULL DEFAULT 0,
  total_parts_earned INT NOT NULL DEFAULT 0,
  heat INT NOT NULL DEFAULT 0,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
