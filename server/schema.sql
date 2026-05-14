CREATE DATABASE IF NOT EXISTS gym_saas CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE gym_saas;

CREATE TABLE IF NOT EXISTS tenants (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  gym_id BIGINT UNSIGNED GENERATED ALWAYS AS (id) STORED,
  slug VARCHAR(64) NOT NULL,
  name VARCHAR(191) NOT NULL,
  status ENUM('active', 'suspended') NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_tenants_slug (slug),
  KEY ix_tenants_gym (gym_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS users (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id BIGINT UNSIGNED NOT NULL,
  gym_id BIGINT UNSIGNED GENERATED ALWAYS AS (tenant_id) STORED,
  email VARCHAR(191) NOT NULL,
  password_hash VARCHAR(191) NOT NULL,
  full_name VARCHAR(191) NOT NULL,
  status ENUM('active', 'disabled') NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_tenant_email (tenant_id, email),
  KEY ix_users_tenant (tenant_id),
  KEY ix_users_gym (gym_id),
  CONSTRAINT fk_users_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS roles (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id BIGINT UNSIGNED NOT NULL,
  gym_id BIGINT UNSIGNED GENERATED ALWAYS AS (tenant_id) STORED,
  name VARCHAR(64) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_roles_tenant_name (tenant_id, name),
  KEY ix_roles_tenant (tenant_id),
  KEY ix_roles_gym (gym_id),
  CONSTRAINT fk_roles_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS user_roles (
  gym_id BIGINT UNSIGNED NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  role_id BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (user_id, role_id),
  KEY ix_user_roles_gym (gym_id),
  KEY ix_user_roles_role (role_id),
  CONSTRAINT fk_user_roles_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_user_roles_role FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS branches (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id BIGINT UNSIGNED NOT NULL,
  gym_id BIGINT UNSIGNED GENERATED ALWAYS AS (tenant_id) STORED,
  name VARCHAR(191) NOT NULL,
  address VARCHAR(255) NULL,
  status ENUM('active', 'inactive') NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_branches_tenant (tenant_id),
  KEY ix_branches_gym (gym_id),
  CONSTRAINT fk_branches_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS members (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id BIGINT UNSIGNED NOT NULL,
  gym_id BIGINT UNSIGNED GENERATED ALWAYS AS (tenant_id) STORED,
  branch_id BIGINT UNSIGNED NULL,
  member_code VARCHAR(32) NOT NULL,
  full_name VARCHAR(191) NOT NULL,
  phone VARCHAR(32) NULL,
  email VARCHAR(191) NULL,
  gender ENUM('male', 'female', 'other') NULL,
  dob DATE NULL,
  join_date DATE NOT NULL,
  status ENUM('active', 'expired', 'inactive') NOT NULL DEFAULT 'active',
  notes VARCHAR(255) NULL,
  frozen_until DATE NULL,
  frozen_reason VARCHAR(191) NULL,
  frozen_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_members_tenant_code (tenant_id, member_code),
  KEY ix_members_tenant (tenant_id),
  KEY ix_members_gym (gym_id),
  KEY ix_members_branch (branch_id),
  KEY ix_members_frozen_until (frozen_until),
  CONSTRAINT fk_members_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
  CONSTRAINT fk_members_branch FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS leads (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id BIGINT UNSIGNED NOT NULL,
  gym_id BIGINT UNSIGNED GENERATED ALWAYS AS (tenant_id) STORED,
  full_name VARCHAR(191) NOT NULL,
  phone VARCHAR(32) NULL,
  source VARCHAR(64) NULL,
  interest VARCHAR(191) NULL,
  next_contact_date DATE NULL,
  status ENUM('new', 'trial', 'converted', 'lost') NOT NULL DEFAULT 'new',
  notes VARCHAR(255) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_leads_tenant (tenant_id),
  KEY ix_leads_gym (gym_id),
  KEY ix_leads_status (status),
  KEY ix_leads_created (created_at),
  CONSTRAINT fk_leads_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS membership_plans (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id BIGINT UNSIGNED NOT NULL,
  gym_id BIGINT UNSIGNED GENERATED ALWAYS AS (tenant_id) STORED,
  name VARCHAR(191) NOT NULL,
  duration_days INT UNSIGNED NOT NULL,
  price DECIMAL(10,2) NOT NULL,
  admission_fee DECIMAL(10,2) NOT NULL DEFAULT 0,
  status ENUM('active', 'inactive') NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_plans_tenant_name (tenant_id, name),
  KEY ix_plans_tenant (tenant_id),
  KEY ix_plans_gym (gym_id),
  CONSTRAINT fk_plans_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS subscriptions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id BIGINT UNSIGNED NOT NULL,
  gym_id BIGINT UNSIGNED GENERATED ALWAYS AS (tenant_id) STORED,
  member_id BIGINT UNSIGNED NOT NULL,
  plan_id BIGINT UNSIGNED NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  status ENUM('active', 'expired', 'cancelled') NOT NULL DEFAULT 'active',
  auto_renew TINYINT(1) NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_subs_tenant (tenant_id),
  KEY ix_subs_gym (gym_id),
  KEY ix_subs_member (member_id),
  KEY ix_subs_plan (plan_id),
  CONSTRAINT fk_subs_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
  CONSTRAINT fk_subs_member FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE,
  CONSTRAINT fk_subs_plan FOREIGN KEY (plan_id) REFERENCES membership_plans(id) ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS invoices (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id BIGINT UNSIGNED NOT NULL,
  gym_id BIGINT UNSIGNED GENERATED ALWAYS AS (tenant_id) STORED,
  member_id BIGINT UNSIGNED NOT NULL,
  subscription_id BIGINT UNSIGNED NULL,
  invoice_no VARCHAR(64) NOT NULL,
  subtotal DECIMAL(10,2) NOT NULL,
  discount DECIMAL(10,2) NOT NULL DEFAULT 0,
  tax DECIMAL(10,2) NOT NULL DEFAULT 0,
  total DECIMAL(10,2) NOT NULL,
  status ENUM('draft', 'unpaid', 'paid', 'void') NOT NULL DEFAULT 'unpaid',
  due_date DATE NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_invoices_tenant_no (tenant_id, invoice_no),
  KEY ix_invoices_tenant (tenant_id),
  KEY ix_invoices_gym (gym_id),
  KEY ix_invoices_member (member_id),
  KEY ix_invoices_subscription (subscription_id),
  CONSTRAINT fk_invoices_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
  CONSTRAINT fk_invoices_member FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE,
  CONSTRAINT fk_invoices_sub FOREIGN KEY (subscription_id) REFERENCES subscriptions(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS payments (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id BIGINT UNSIGNED NOT NULL,
  gym_id BIGINT UNSIGNED GENERATED ALWAYS AS (tenant_id) STORED,
  invoice_id BIGINT UNSIGNED NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  method ENUM('cash', 'card', 'bank', 'online') NOT NULL,
  txn_ref VARCHAR(128) NULL,
  paid_at DATETIME NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_payments_tenant (tenant_id),
  KEY ix_payments_gym (gym_id),
  KEY ix_payments_invoice (invoice_id),
  CONSTRAINT fk_payments_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
  CONSTRAINT fk_payments_invoice FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS attendance_logs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id BIGINT UNSIGNED NOT NULL,
  gym_id BIGINT UNSIGNED GENERATED ALWAYS AS (tenant_id) STORED,
  member_id BIGINT UNSIGNED NOT NULL,
  branch_id BIGINT UNSIGNED NULL,
  checked_in_at DATETIME NOT NULL,
  checked_out_at DATETIME NULL,
  source ENUM('manual', 'qr', 'rfid') NOT NULL DEFAULT 'manual',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_att_tenant (tenant_id),
  KEY ix_att_gym (gym_id),
  KEY ix_att_member (member_id),
  KEY ix_att_branch (branch_id),
  KEY ix_att_checked_in (checked_in_at),
  CONSTRAINT fk_att_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
  CONSTRAINT fk_att_member FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE,
  CONSTRAINT fk_att_branch FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS classes (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id BIGINT UNSIGNED NOT NULL,
  gym_id BIGINT UNSIGNED GENERATED ALWAYS AS (tenant_id) STORED,
  name VARCHAR(191) NOT NULL,
  capacity INT UNSIGNED NULL,
  status ENUM('active', 'inactive') NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_classes_tenant (tenant_id),
  KEY ix_classes_gym (gym_id),
  CONSTRAINT fk_classes_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS class_sessions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id BIGINT UNSIGNED NOT NULL,
  gym_id BIGINT UNSIGNED GENERATED ALWAYS AS (tenant_id) STORED,
  class_id BIGINT UNSIGNED NOT NULL,
  trainer_name VARCHAR(191) NULL,
  branch_id BIGINT UNSIGNED NULL,
  starts_at DATETIME NOT NULL,
  ends_at DATETIME NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_class_sessions_tenant (tenant_id),
  KEY ix_class_sessions_gym (gym_id),
  KEY ix_class_sessions_class (class_id),
  KEY ix_class_sessions_branch (branch_id),
  CONSTRAINT fk_class_sessions_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
  CONSTRAINT fk_class_sessions_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
  CONSTRAINT fk_class_sessions_branch FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS expenses (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id BIGINT UNSIGNED NOT NULL,
  gym_id BIGINT UNSIGNED GENERATED ALWAYS AS (tenant_id) STORED,
  branch_id BIGINT UNSIGNED NULL,
  category VARCHAR(191) NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  expense_date DATE NOT NULL,
  notes VARCHAR(255) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_expenses_tenant (tenant_id),
  KEY ix_expenses_gym (gym_id),
  KEY ix_expenses_branch (branch_id),
  CONSTRAINT fk_expenses_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
  CONSTRAINT fk_expenses_branch FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS products (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id BIGINT UNSIGNED NOT NULL,
  gym_id BIGINT UNSIGNED GENERATED ALWAYS AS (tenant_id) STORED,
  name VARCHAR(191) NOT NULL,
  sku VARCHAR(64) NULL,
  price DECIMAL(10,2) NOT NULL DEFAULT 0,
  status ENUM('active', 'inactive') NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_products_tenant_sku (tenant_id, sku),
  KEY ix_products_tenant (tenant_id),
  KEY ix_products_gym (gym_id),
  CONSTRAINT fk_products_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS stock_movements (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id BIGINT UNSIGNED NOT NULL,
  gym_id BIGINT UNSIGNED GENERATED ALWAYS AS (tenant_id) STORED,
  product_id BIGINT UNSIGNED NOT NULL,
  qty INT NOT NULL,
  movement_type ENUM('in', 'out') NOT NULL,
  reason VARCHAR(191) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_stock_tenant (tenant_id),
  KEY ix_stock_gym (gym_id),
  KEY ix_stock_product (product_id),
  CONSTRAINT fk_stock_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
  CONSTRAINT fk_stock_product FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS gym_settings (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id BIGINT UNSIGNED NOT NULL,
  gym_id BIGINT UNSIGNED GENERATED ALWAYS AS (tenant_id) STORED,
  currency VARCHAR(16) NOT NULL DEFAULT 'PKR',
  default_tax_percent DECIMAL(5,2) NOT NULL DEFAULT 5,
  enable_sounds TINYINT(1) NOT NULL DEFAULT 1,
  enable_animations TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_gym_settings_tenant (tenant_id),
  KEY ix_gym_settings_gym (gym_id),
  CONSTRAINT fk_gym_settings_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS gym_profile (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id BIGINT UNSIGNED NOT NULL,
  gym_id BIGINT UNSIGNED GENERATED ALWAYS AS (tenant_id) STORED,
  address VARCHAR(255) NULL,
  logo_url MEDIUMTEXT NULL,
  website_url VARCHAR(255) NULL,
  facebook_url VARCHAR(255) NULL,
  instagram_url VARCHAR(255) NULL,
  whatsapp VARCHAR(64) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_gym_profile_tenant (tenant_id),
  KEY ix_gym_profile_gym (gym_id),
  CONSTRAINT fk_gym_profile_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS system_logs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id BIGINT UNSIGNED NOT NULL,
  gym_id BIGINT UNSIGNED GENERATED ALWAYS AS (tenant_id) STORED,
  actor_user_id BIGINT UNSIGNED NULL,
  action VARCHAR(64) NOT NULL,
  entity_type VARCHAR(64) NULL,
  entity_id BIGINT UNSIGNED NULL,
  meta_json TEXT NULL,
  ip VARCHAR(64) NULL,
  user_agent VARCHAR(255) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_system_logs_tenant (tenant_id),
  KEY ix_system_logs_gym (gym_id),
  KEY ix_system_logs_actor (actor_user_id),
  KEY ix_system_logs_action (action),
  KEY ix_system_logs_created (created_at),
  CONSTRAINT fk_system_logs_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
  CONSTRAINT fk_system_logs_actor FOREIGN KEY (actor_user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB;
