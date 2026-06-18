import dotenv from 'dotenv';
import bcrypt from 'bcryptjs';
import cors from 'cors';
import express from 'express';
import jwt from 'jsonwebtoken';
import PDFDocument from 'pdfkit';
import { z } from 'zod';
import { execute, getPool, queryMany, queryOne } from './db.js';

dotenv.config({ override: true });

const app = express();
app.use(cors({ origin: true, credentials: true }));
app.use(express.json({ limit: '1mb' }));

const jwtSecret = process.env.JWT_SECRET?.length ? process.env.JWT_SECRET : 'dev-secret-change-me';

// ── Branded PDF factory ──────────────────────────────────────────────────────
// Creates a buffered PDFKit document and overrides `.end()` so that, right
// before the stream is finalised, a "Powered by Deverosity" signature is
// stamped into the bottom margin of every page. Using buffered pages means the
// footer is drawn after all content is laid out, so it never interferes with
// the document's text flow. All PDF endpoints use this in place of
// `new PDFDocument(...)`.
function createBrandedPdf() {
  const doc = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
  const originalEnd = doc.end.bind(doc);
  doc.end = function brandedEnd() {
    try {
      const range = doc.bufferedPageRange(); // { start, count }
      for (let i = range.start; i < range.start + range.count; i++) {
        doc.switchToPage(i);
        doc
          .font('Helvetica-Bold')
          .fontSize(8)
          .fillColor('#999999')
          .text(
            'Powered by Deverosity (https://deverosity.com)',
            40,
            doc.page.height - 28,
            { align: 'center', width: doc.page.width - 80, lineBreak: false },
          );
      }
    } catch (err) {
      // Footer is decorative — never let it break PDF generation.
      console.error('PDF footer error:', err?.message || err);
    }
    return originalEnd();
  };
  return doc;
}

const signToken = (payload) => {
  return jwt.sign(payload, jwtSecret, { expiresIn: '7d' });
};

const authMiddleware = async (req, res, next) => {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) return res.status(401).json({ error: 'unauthorized' });
  const token = header.substring('Bearer '.length);
  try {
    const decoded = jwt.verify(token, jwtSecret);
    req.user = {
      tenantId: Number(decoded.tid),
      userId: Number(decoded.uid),
      roles: Array.isArray(decoded.roles) ? decoded.roles : []
    };
    return next();
  } catch {
    return res.status(401).json({ error: 'unauthorized' });
  }
};

const requireRole = (...roles) => {
  return (req, res, next) => {
    const userRoles = req.user?.roles ?? [];
    if (userRoles.includes('super_admin')) return next();
    if (roles.some((r) => userRoles.includes(r))) return next();
    return res.status(403).json({ error: 'forbidden' });
  };
};

const buildStamp = new Date().toISOString();
const pdfRoutePaths = [
  '/pdf/dashboard.pdf',
  '/pdf/leads.pdf',
  '/pdf/members.pdf',
  '/pdf/plans.pdf',
  '/pdf/attendance.pdf',
  '/pdf/inventory.pdf',
  '/pdf/invoices.pdf',
  '/pdf/payments.pdf',
  '/pdf/expenses.pdf',
  '/pdf/staff.pdf',
  '/pdf/settings.pdf'
];

app.get('/', (req, res) => {
  return res.json({ ok: true, service: 'gym-management-saas-api', buildStamp });
});

app.get('/__version', (req, res) => {
  return res.json({ ok: true, service: 'gym-management-saas-api', buildStamp, pdfRoutes: pdfRoutePaths });
});

const addDays = (date, days) => {
  const d = new Date(date);
  d.setDate(d.getDate() + Number(days));
  return d;
};

const toDateOnly = (d) => {
  const year = d.getFullYear();
  const month = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
};

const toMysqlDateTime = (d) => {
  return d.toISOString().slice(0, 19).replace('T', ' ');
};

const generateMemberCode = async (conn, tenantId) => {
  const [rows] = await conn.query(
    `SELECT GREATEST(
        COALESCE(MAX(CASE WHEN member_code REGEXP '^[0-9]+$' THEN CAST(member_code AS UNSIGNED) END), 0),
        COALESCE(MAX(CASE WHEN member_code REGEXP '^[A-Za-z]+-[0-9]+$' THEN CAST(SUBSTRING_INDEX(member_code, '-', -1) AS UNSIGNED) END), 0)
      ) AS max_n
     FROM members
     WHERE tenant_id = :tenantId`,
    { tenantId }
  );
  const maxN = Number(rows?.[0]?.max_n ?? 0);
  const next = Math.max(maxN + 1, 1001);
  return String(next);
};

const fmtDateOnlyStr = (raw) => {
  if (raw == null) return '';
  const s = String(raw);
  const m = s.match(/^\d{4}-\d{2}-\d{2}/);
  if (m) return m[0];
  const d = new Date(s);
  if (!Number.isNaN(d.getTime())) return toDateOnly(d);
  return s;
};

const fmtDateTimeShort = (raw) => {
  if (raw == null) return '';
  const s = String(raw);
  const iso = s.replace('T', ' ');
  const m = iso.match(/^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}/);
  if (m) return m[0];
  const d = new Date(s);
  if (Number.isNaN(d.getTime())) return s;
  const hh = String(d.getHours()).padStart(2, '0');
  const mm = String(d.getMinutes()).padStart(2, '0');
  return `${toDateOnly(d)} ${hh}:${mm}`;
};

const pdfDrawRow = (
  doc,
  cols,
  { y = null, rowHeight = 14, fontSize = 10, color = '#000000', bottomPadding = 8, onNewPage = null } = {}
) => {
  const pageHeight = Number(doc.page.height ?? 842);
  const bottomMargin = Number(doc.page.margins.bottom ?? 40);
  const bottomY = pageHeight - bottomMargin - Number(bottomPadding ?? 0);

  let rowY = y ?? doc.y;
  if (rowY + rowHeight > bottomY) {
    doc.addPage();
    if (typeof onNewPage === 'function') onNewPage(doc);
    rowY = y ?? doc.y;
  }
  doc.fontSize(fontSize).fillColor(color);
  for (const c of cols) {
    const text = c?.text == null ? '' : String(c.text);
    const x = Number(c?.x ?? 0);
    const width = Number(c?.width ?? 0);
    const align = c?.align ?? 'left';
    doc.text(text, x, rowY, { width, align, ellipsis: true, lineBreak: false });
  }
  doc.fillColor('#000000');
  doc.y = rowY + rowHeight;
};

const newInvoiceNo = () => {
  const stamp = new Date().toISOString().slice(0, 10).replaceAll('-', '');
  return `INV-${stamp}-${Math.random().toString(16).slice(2, 8).toUpperCase()}`;
};

const ensureOperationalTables = async () => {
  // ── Performance indexes for at-risk member query and 7-day revenue chart ──
  // These are added idempotently; MySQL silently skips if already present.
  try {
    await execute(
      `ALTER TABLE attendance_logs
       ADD INDEX IF NOT EXISTS ix_att_log_tenant_checkin (tenant_id, checked_in_at DESC),
       ADD INDEX IF NOT EXISTS ix_att_log_tenant_member (tenant_id, member_id)`
    );
  } catch {}
  try {
    await execute(
      `ALTER TABLE invoices
       ADD INDEX IF NOT EXISTS ix_inv_tenant_paid_at (tenant_id, status, paid_at),
       ADD INDEX IF NOT EXISTS ix_inv_tenant_created (tenant_id, status, created_at)`
    );
  } catch {}
  // Optional transaction/reference id captured by the manual Record Payment form.
  try {
    await execute('ALTER TABLE payments ADD COLUMN IF NOT EXISTS reference VARCHAR(120) NULL');
  } catch {}

  await execute(
    `CREATE TABLE IF NOT EXISTS attendance_events (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      tenant_id BIGINT UNSIGNED NOT NULL,
      member_id BIGINT UNSIGNED NULL,
      query_value VARCHAR(64) NULL,
      status ENUM('allowed','denied') NOT NULL,
      reason VARCHAR(64) NULL,
      checked_in_at DATETIME NOT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      KEY ix_att_ev_tenant (tenant_id),
      KEY ix_att_ev_member (member_id),
      KEY ix_att_ev_checked_in (checked_in_at),
      CONSTRAINT fk_att_ev_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
      CONSTRAINT fk_att_ev_member FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE SET NULL
    ) ENGINE=InnoDB;`
  );

  await execute(
    `CREATE TABLE IF NOT EXISTS membership_plans (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      tenant_id BIGINT UNSIGNED NOT NULL,
      name VARCHAR(191) NOT NULL,
      duration_days INT UNSIGNED NOT NULL,
      price DECIMAL(10,2) NOT NULL,
      admission_fee DECIMAL(10,2) NOT NULL DEFAULT 0,
      status ENUM('active', 'inactive') NOT NULL DEFAULT 'active',
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY uq_plans_tenant_name (tenant_id, name),
      KEY ix_plans_tenant (tenant_id),
      CONSTRAINT fk_plans_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
    ) ENGINE=InnoDB;`
  );
  try {
    const admissionFeeCol = await queryOne("SHOW COLUMNS FROM membership_plans LIKE 'admission_fee'");
    if (!admissionFeeCol) {
      await execute("ALTER TABLE membership_plans ADD COLUMN admission_fee DECIMAL(10,2) NOT NULL DEFAULT 0");
    }
  } catch {}
  try {
    const statusCol = await queryOne("SHOW COLUMNS FROM membership_plans LIKE 'status'");
    if (!statusCol) {
      await execute("ALTER TABLE membership_plans ADD COLUMN status ENUM('active', 'inactive') NOT NULL DEFAULT 'active'");
    }
  } catch {}
  try {
    const createdAtCol = await queryOne("SHOW COLUMNS FROM membership_plans LIKE 'created_at'");
    if (!createdAtCol) {
      await execute("ALTER TABLE membership_plans ADD COLUMN created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP");
    }
  } catch {}
  try {
    await execute("ALTER TABLE membership_plans MODIFY COLUMN status ENUM('active', 'inactive') NOT NULL DEFAULT 'active'");
  } catch {}
  try {
    await execute("ALTER TABLE membership_plans MODIFY COLUMN created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP");
  } catch {}

  await execute(
    `CREATE TABLE IF NOT EXISTS gym_settings (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      tenant_id BIGINT UNSIGNED NOT NULL,
      currency VARCHAR(16) NOT NULL DEFAULT 'PKR',
      default_tax_percent DECIMAL(5,2) NOT NULL DEFAULT 5,
      enable_sounds TINYINT(1) NOT NULL DEFAULT 1,
      enable_animations TINYINT(1) NOT NULL DEFAULT 1,
      at_risk_days INT UNSIGNED NOT NULL DEFAULT 3,
      at_risk_whatsapp_template VARCHAR(600) NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY uq_gym_settings_tenant (tenant_id),
      CONSTRAINT fk_gym_settings_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
    ) ENGINE=InnoDB;`
  );
  try {
    const atRiskDaysCol = await queryOne("SHOW COLUMNS FROM gym_settings LIKE 'at_risk_days'");
    if (!atRiskDaysCol) await execute("ALTER TABLE gym_settings ADD COLUMN at_risk_days INT UNSIGNED NOT NULL DEFAULT 3");
  } catch {}
  try {
    const atRiskTplCol = await queryOne("SHOW COLUMNS FROM gym_settings LIKE 'at_risk_whatsapp_template'");
    if (!atRiskTplCol) await execute("ALTER TABLE gym_settings ADD COLUMN at_risk_whatsapp_template VARCHAR(600) NULL");
  } catch {}

  await execute(
    `CREATE TABLE IF NOT EXISTS gym_profile (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      tenant_id BIGINT UNSIGNED NOT NULL,
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
      CONSTRAINT fk_gym_profile_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
    ) ENGINE=InnoDB;`
  );
  try {
    const websiteCol = await queryOne("SHOW COLUMNS FROM gym_profile LIKE 'website_url'");
    if (!websiteCol) await execute("ALTER TABLE gym_profile ADD COLUMN website_url VARCHAR(255) NULL");
  } catch {}
  try {
    const facebookCol = await queryOne("SHOW COLUMNS FROM gym_profile LIKE 'facebook_url'");
    if (!facebookCol) await execute("ALTER TABLE gym_profile ADD COLUMN facebook_url VARCHAR(255) NULL");
  } catch {}
  try {
    const instagramCol = await queryOne("SHOW COLUMNS FROM gym_profile LIKE 'instagram_url'");
    if (!instagramCol) await execute("ALTER TABLE gym_profile ADD COLUMN instagram_url VARCHAR(255) NULL");
  } catch {}
  try {
    const whatsappCol = await queryOne("SHOW COLUMNS FROM gym_profile LIKE 'whatsapp'");
    if (!whatsappCol) await execute("ALTER TABLE gym_profile ADD COLUMN whatsapp VARCHAR(64) NULL");
  } catch {}
  try {
    await execute("ALTER TABLE gym_profile MODIFY COLUMN logo_url MEDIUMTEXT NULL");
  } catch {}

  await execute(
    `CREATE TABLE IF NOT EXISTS leads (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      tenant_id BIGINT UNSIGNED NOT NULL,
      full_name VARCHAR(191) NOT NULL,
      phone VARCHAR(32) NULL,
      source VARCHAR(64) NULL,
      interest VARCHAR(191) NULL,
      next_contact_date DATE NULL,
      status ENUM('new','trial','converted','lost') NOT NULL DEFAULT 'new',
      notes VARCHAR(255) NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      KEY ix_leads_tenant (tenant_id),
      KEY ix_leads_status (status),
      KEY ix_leads_created (created_at),
      CONSTRAINT fk_leads_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
    ) ENGINE=InnoDB;`
  );

  try {
    const interestCol = await queryOne("SHOW COLUMNS FROM leads LIKE 'interest'");
    if (!interestCol) await execute("ALTER TABLE leads ADD COLUMN interest VARCHAR(191) NULL");
  } catch {}
  try {
    const nextContactCol = await queryOne("SHOW COLUMNS FROM leads LIKE 'next_contact_date'");
    if (!nextContactCol) await execute("ALTER TABLE leads ADD COLUMN next_contact_date DATE NULL");
  } catch {}
  try {
    await execute("ALTER TABLE leads MODIFY COLUMN status ENUM('new','contacted','trial','converted','lost') NOT NULL DEFAULT 'new'");
  } catch {}
  try {
    await execute("UPDATE leads SET status = 'trial' WHERE status = 'contacted'");
  } catch {}
  try {
    await execute("ALTER TABLE leads MODIFY COLUMN status ENUM('new','trial','converted','lost') NOT NULL DEFAULT 'new'");
  } catch {}

  await execute(
    `CREATE TABLE IF NOT EXISTS system_logs (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      tenant_id BIGINT UNSIGNED NOT NULL,
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
      KEY ix_system_logs_actor (actor_user_id),
      KEY ix_system_logs_action (action),
      KEY ix_system_logs_created (created_at),
      CONSTRAINT fk_system_logs_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
      CONSTRAINT fk_system_logs_actor FOREIGN KEY (actor_user_id) REFERENCES users(id) ON DELETE SET NULL
    ) ENGINE=InnoDB;`
  );

  try {
    const frozenUntilCol = await queryOne("SHOW COLUMNS FROM members LIKE 'frozen_until'");
    if (!frozenUntilCol) await execute("ALTER TABLE members ADD COLUMN frozen_until DATE NULL");
  } catch {}
  try {
    const frozenReasonCol = await queryOne("SHOW COLUMNS FROM members LIKE 'frozen_reason'");
    if (!frozenReasonCol) await execute("ALTER TABLE members ADD COLUMN frozen_reason VARCHAR(191) NULL");
  } catch {}
  try {
    const frozenAtCol = await queryOne("SHOW COLUMNS FROM members LIKE 'frozen_at'");
    if (!frozenAtCol) await execute("ALTER TABLE members ADD COLUMN frozen_at TIMESTAMP NULL DEFAULT NULL");
  } catch {}
  try {
    await execute("ALTER TABLE members ADD KEY ix_members_frozen_until (frozen_until)");
  } catch {}
};

const decodeLogoDataUrl = (logoUrl) => {
  const raw = typeof logoUrl === 'string' ? logoUrl.trim() : '';
  if (!raw.startsWith('data:image/')) return null;
  const commaIdx = raw.indexOf(',');
  if (commaIdx < 0) return null;
  const meta = raw.slice(5, commaIdx);
  const b64 = raw.slice(commaIdx + 1);
  if (!meta.includes(';base64')) return null;
  try {
    const buf = Buffer.from(b64, 'base64');
    if (!buf || buf.length === 0) return null;
    return buf;
  } catch {
    return null;
  }
};

const loadGymProfileForTenant = async (tenantId) => {
  const tenant = await queryOne('SELECT name FROM tenants WHERE id = :tenantId LIMIT 1', { tenantId });
  const profile = await queryOne(
    `SELECT address, logo_url, website_url, facebook_url, instagram_url, whatsapp
     FROM gym_profile
     WHERE tenant_id = :tenantId
     LIMIT 1`,
    { tenantId }
  );
  return {
    gymName: tenant?.name ?? null,
    address: profile?.address ?? null,
    logoUrl: profile?.logo_url ?? null,
    websiteUrl: profile?.website_url ?? null,
    facebookUrl: profile?.facebook_url ?? null,
    instagramUrl: profile?.instagram_url ?? null,
    whatsapp: profile?.whatsapp ?? null
  };
};

const drawGymPdfHeader = (doc, profile, { title = null, subtitle = null } = {}) => {
  const startX = doc.page.margins.left ?? 40;
  const startY = doc.y;
  const maxX = doc.page.width - (doc.page.margins.right ?? 40);
  const logoBuf = decodeLogoDataUrl(profile?.logoUrl);

  const textX = logoBuf ? startX + 64 : startX;
  const headerRightX = maxX;

  if (logoBuf) {
    try {
      doc.image(logoBuf, startX, startY, { width: 52, height: 52 });
    } catch {}
  }

  if (profile?.gymName) {
    doc.fontSize(14).text(String(profile.gymName), textX, startY, { width: 320 });
  } else {
    doc.fontSize(14).text('Gym', textX, startY, { width: 320 });
  }
  doc.fontSize(9).fillColor('#555555');
  if (profile?.address) doc.text(String(profile.address), textX, doc.y, { width: 320 });
  const socials = [
    profile?.websiteUrl ? `Web: ${profile.websiteUrl}` : null,
    profile?.facebookUrl ? `FB: ${profile.facebookUrl}` : null,
    profile?.instagramUrl ? `IG: ${profile.instagramUrl}` : null,
    profile?.whatsapp ? `WhatsApp: ${profile.whatsapp}` : null
  ].filter(Boolean);
  if (socials.length) doc.text(socials.join('  •  '), textX, doc.y, { width: 440 });
  doc.fillColor('#000000');

  if (title) {
    doc.fontSize(16).text(String(title), startX, startY, { align: 'right' });
  }
  if (subtitle) {
    doc.fontSize(9).fillColor('#555555').text(String(subtitle), startX, doc.y, { align: 'right' });
    doc.fillColor('#000000');
  }

  doc.y = Math.max(doc.y, startY + 64);
  doc.moveDown(0.4);
};

const drawObsidianGoldPdfHeader = (doc, profile, { title = null, subtitle = null } = {}) => {
  const left = doc.page.margins.left ?? 40;
  const top = doc.page.margins.top ?? 40;
  const right = doc.page.width - (doc.page.margins.right ?? 40);
  const width = right - left;
  const h = 78;

  const gold1 = '#D4AF37';
  const gold2 = '#FFE9A8';
  const obsidian = '#0B0F14';
  const logoBuf = decodeLogoDataUrl(profile?.logoUrl);

  doc.save();
  doc.rect(left, top, width, h).fill(obsidian);
  const grad = doc.linearGradient(left, top + h - 3, right, top + h - 3);
  grad.stop(0, gold1).stop(1, gold2);
  doc.rect(left, top + h - 3, width, 3).fill(grad);
  doc.restore();

  const padX = 14;
  const padY = 12;
  let textX = left + padX;
  const textY = top + padY;

  if (logoBuf) {
    try {
      doc.image(logoBuf, textX, textY + 2, { width: 40, height: 40 });
      textX += 52;
    } catch {}
  }

  doc.fillColor('#FFFFFF').fontSize(14).text(String(profile?.gymName ?? 'Gym'), textX, textY, { width: 330 });
  doc.fontSize(9).fillColor('#B8B8B8');
  if (profile?.address) doc.text(String(profile.address), textX, textY + 18, { width: 340 });
  doc.fillColor('#FFFFFF');

  if (title) {
    doc.fontSize(18).fillColor(gold1).text(String(title), left, textY - 2, { width, align: 'right' });
  }
  if (subtitle) {
    doc.fontSize(9).fillColor('#D7D7D7').text(String(subtitle), left, textY + 22, { width, align: 'right' });
  }

  doc.fillColor('#000000');
  doc.y = top + h + 18;
};

const maybeLogLowStock = async ({ tenantId, actorUserId, productId }) => {
  const tId = Number(tenantId);
  const pId = Number(productId);
  if (!Number.isFinite(tId) || tId <= 0) return;
  if (!Number.isFinite(pId) || pId <= 0) return;

  const threshold = 5;
  const product = await queryOne(
    `SELECT id, name, status
     FROM products
     WHERE tenant_id = :tenantId AND id = :id
     LIMIT 1`,
    { tenantId: tId, id: pId }
  );
  if (!product || product.status !== 'active') return;

  const stockRow = await queryOne(
    `SELECT COALESCE(SUM(CASE WHEN movement_type = 'in' THEN qty ELSE -qty END), 0) AS on_hand
     FROM stock_movements
     WHERE tenant_id = :tenantId AND product_id = :productId`,
    { tenantId: tId, productId: pId }
  );
  const onHand = Number(stockRow?.on_hand ?? 0);
  if (!Number.isFinite(onHand) || onHand >= threshold) return;

  const recent = await queryOne(
    `SELECT id
     FROM system_logs
     WHERE tenant_id = :tenantId
       AND action = 'stock_low'
       AND entity_type = 'product'
       AND entity_id = :productId
       AND created_at >= DATE_SUB(NOW(), INTERVAL 6 HOUR)
     ORDER BY id DESC
     LIMIT 1`,
    { tenantId: tId, productId: pId }
  );
  if (recent?.id) return;

  await appendSystemLog({
    tenantId: tId,
    actorUserId: actorUserId ?? null,
    action: 'stock_low',
    entityType: 'product',
    entityId: pId,
    meta: { productId: pId, productName: product.name, onHand, threshold }
  });
};

const appendSystemLog = async (
  { tenantId, actorUserId, action, entityType = null, entityId = null, meta = null, ip = null, userAgent = null },
  conn = null
) => {
  const metaJson = meta == null ? null : JSON.stringify(meta);
  const sql =
    'INSERT INTO system_logs (tenant_id, actor_user_id, action, entity_type, entity_id, meta_json, ip, user_agent) VALUES (:tenantId, :actorUserId, :action, :entityType, :entityId, :metaJson, :ip, :userAgent)';
  const params = {
    tenantId,
    actorUserId: actorUserId ?? null,
    action,
    entityType,
    entityId,
    metaJson,
    ip,
    userAgent
  };
  if (conn) {
    await conn.execute(sql, params);
    return;
  }
  await execute(sql, params);
};

const triggerAutomation = async (
  { tenantId, event, memberId = null, invoiceId = null, payload = null },
  conn = null
) => {
  process.stdout.write(
    `[automation] tenant=${tenantId} event=${event} member=${memberId ?? '-'} invoice=${invoiceId ?? '-'} payload=${payload ? JSON.stringify(payload) : '{}'}\n`
  );
  await appendSystemLog(
    {
      tenantId,
      actorUserId: null,
      action: 'automation_trigger',
      entityType: 'member',
      entityId: memberId,
      meta: { event, memberId, invoiceId, payload }
    },
    conn
  );
};

class PlanRepository {
  async getById(tenantId, id) {
    return queryOne(
      `SELECT id, name, duration_days, price, admission_fee, status
       FROM membership_plans
       WHERE tenant_id = :tenantId AND id = :id`,
      { tenantId, id }
    );
  }

  async list(tenantId, limit = 200) {
    return queryMany(
      `SELECT id, name, duration_days, price, admission_fee, status, created_at
       FROM membership_plans
       WHERE tenant_id = :tenantId
       ORDER BY id DESC
       LIMIT :limit`,
      { tenantId, limit }
    );
  }
}

class MemberRepository {
  async getActiveById(tenantId, id) {
    return queryOne(
      `SELECT id, member_code, full_name, phone, email, status, join_date, frozen_until
       FROM members
       WHERE tenant_id = :tenantId AND id = :id AND status = 'active'`,
      { tenantId, id }
    );
  }

  async findByCodeOrPhone(tenantId, queryValue) {
    const q = String(queryValue ?? '').trim();
    if (!q.length) return null;
    const byCode = await queryOne(
      `SELECT id, member_code, full_name, phone, email, status, join_date, frozen_until
       FROM members
       WHERE tenant_id = :tenantId AND status = 'active' AND member_code = :q
       LIMIT 1`,
      { tenantId, q }
    );
    if (byCode) return byCode;
    return queryOne(
      `SELECT id, member_code, full_name, phone, email, status, join_date, frozen_until
       FROM members
       WHERE tenant_id = :tenantId AND status = 'active' AND phone = :q
       ORDER BY id DESC
       LIMIT 1`,
      { tenantId, q }
    );
  }

  async list(tenantId, { q = '', status = '', from = '', to = '', limit = 50 } = {}) {
    const where = ['m.tenant_id = :tenantId'];
    const params = { tenantId, limit };
    if (q.length) {
      where.push('(m.member_code LIKE :q OR m.full_name LIKE :q OR m.phone LIKE :q OR m.email LIKE :q)');
      params.q = `%${q}%`;
    }
    if (status === 'active' || status === 'inactive') {
      where.push('m.status = :status');
      params.status = status;
    }
    if (from?.length) {
      where.push('m.join_date >= :from');
      params.from = from;
    }
    if (to?.length) {
      where.push('m.join_date <= :to');
      params.to = to;
    }

    return queryMany(
      `SELECT
         m.id,
         m.member_code,
         m.full_name,
         m.phone,
         m.email,
         m.status,
         m.join_date,
         m.frozen_until,
         (SELECT s.end_date
          FROM subscriptions s
       WHERE s.tenant_id = m.tenant_id AND s.member_id = m.id AND s.status = 'active'
          ORDER BY s.end_date DESC
          LIMIT 1) AS membership_end_date,
         (SELECT p.name
          FROM subscriptions s
          INNER JOIN membership_plans p ON p.id = s.plan_id
       WHERE s.tenant_id = m.tenant_id AND s.member_id = m.id AND s.status = 'active'
          ORDER BY s.end_date DESC
          LIMIT 1) AS membership_plan_name,
         b.name AS branch_name
       FROM members m
       LEFT JOIN branches b ON b.id = m.branch_id
       WHERE ${where.join(' AND ')}
       ORDER BY m.id DESC
       LIMIT :limit`,
      params
    );
  }
}

class LeadRepository {
  async list(tenantId, { q = '', status = '', limit = 200 } = {}) {
    const where = ['l.tenant_id = :tenantId'];
    const params = { tenantId, limit };
    if (q?.length) {
      where.push('(l.full_name LIKE :q OR l.phone LIKE :q OR l.source LIKE :q OR l.interest LIKE :q OR l.notes LIKE :q)');
      params.q = `%${q}%`;
    }
    if (status === 'new' || status === 'trial' || status === 'converted' || status === 'lost') {
      where.push('l.status = :status');
      params.status = status;
    }
    return queryMany(
      `SELECT l.id, l.full_name, l.phone, l.source, l.interest, l.next_contact_date, l.status, l.notes, l.created_at, l.updated_at
       FROM leads l
       WHERE ${where.join(' AND ')}
       ORDER BY l.id DESC
       LIMIT :limit`,
      params
    );
  }

  async create(
    tenantId,
    { fullName, phone = null, source = null, interest = null, nextContactDate = null, status = 'new', notes = null }
  ) {
    const result = await execute(
      `INSERT INTO leads (tenant_id, full_name, phone, source, interest, next_contact_date, status, notes)
       VALUES (:tenantId, :fullName, :phone, :source, :interest, :nextContactDate, :status, :notes)`,
      { tenantId, fullName, phone, source, interest, nextContactDate, status, notes }
    );
    return Number(result.insertId);
  }

  async update(
    tenantId,
    id,
    { fullName, phone = null, source = null, interest = null, nextContactDate = null, status = 'new', notes = null }
  ) {
    await execute(
      `UPDATE leads
       SET full_name = :fullName,
           phone = :phone,
           source = :source,
           interest = :interest,
           next_contact_date = :nextContactDate,
           status = :status,
           notes = :notes
       WHERE tenant_id = :tenantId AND id = :id`,
      { tenantId, id, fullName, phone, source, interest, nextContactDate, status, notes }
    );
  }

  async remove(tenantId, id) {
    await execute('DELETE FROM leads WHERE tenant_id = :tenantId AND id = :id', { tenantId, id });
  }
}

class SubscriptionRepository {
  async getActiveForMember(tenantId, memberId) {
    return queryOne(
      `SELECT s.id, s.plan_id, s.start_date, s.end_date, s.status, p.name AS plan_name, p.duration_days, p.price, p.admission_fee
       FROM subscriptions s
       INNER JOIN membership_plans p ON p.id = s.plan_id
       WHERE s.tenant_id = :tenantId AND s.member_id = :memberId AND s.status = 'active'
       ORDER BY s.end_date DESC
       LIMIT 1`,
      { tenantId, memberId }
    );
  }

  async getLatestForMember(tenantId, memberId) {
    return queryOne(
      `SELECT s.id, s.plan_id, s.start_date, s.end_date, s.status, p.name AS plan_name, p.duration_days, p.price, p.admission_fee
       FROM subscriptions s
       INNER JOIN membership_plans p ON p.id = s.plan_id
       WHERE s.tenant_id = :tenantId AND s.member_id = :memberId
       ORDER BY s.end_date DESC
       LIMIT 1`,
      { tenantId, memberId }
    );
  }
}

class InvoiceRepository {
  async countUnpaidForMember(tenantId, memberId) {
    const row = await queryOne(
      "SELECT COUNT(*) AS c FROM invoices WHERE tenant_id = :tenantId AND member_id = :memberId AND status = 'unpaid'",
      { tenantId, memberId }
    );
    return Number(row?.c ?? 0);
  }

  async listForMember(tenantId, memberId, limit = 10) {
    return queryMany(
      `SELECT id, invoice_no, subtotal, discount, tax, total, status, created_at
       FROM invoices
       WHERE tenant_id = :tenantId AND member_id = :memberId
       ORDER BY id DESC
       LIMIT :limit`,
      { tenantId, memberId, limit }
    );
  }

  async getById(tenantId, invoiceId) {
    return queryOne(
      `SELECT i.id, i.invoice_no, i.subtotal, i.discount, i.tax, i.total, i.status, i.created_at, i.due_date,
              m.full_name AS member_name, m.member_code, m.phone, m.email
       FROM invoices i
       INNER JOIN members m ON m.id = i.member_id
       WHERE i.tenant_id = :tenantId AND i.id = :id`,
      { tenantId, id: invoiceId }
    );
  }

  async totalRevenue(tenantId) {
    const row = await queryOne(
      "SELECT COALESCE(SUM(total), 0) AS s FROM invoices WHERE tenant_id = :tenantId AND status = 'paid'",
      { tenantId }
    );
    return Number(row?.s ?? 0);
  }
}

class AttendanceRepository {
  async hasOpenSession(tenantId, memberId) {
    return queryOne(
      `SELECT id, checked_in_at
       FROM attendance_logs
       WHERE tenant_id = :tenantId AND member_id = :memberId AND checked_out_at IS NULL
       ORDER BY id DESC
       LIMIT 1`,
      { tenantId, memberId }
    );
  }

  async insertCheckIn(tenantId, memberId, { branchId = null, source = 'manual' } = {}) {
    const now = new Date();
    const result = await execute(
      `INSERT INTO attendance_logs (tenant_id, member_id, branch_id, checked_in_at, source)
       VALUES (:tenantId, :memberId, :branchId, :checkedInAt, :source)`,
      {
        tenantId,
        memberId,
        branchId,
        checkedInAt: toMysqlDateTime(now),
        source
      }
    );
    return Number(result.insertId);
  }

  async countToday(tenantId, { q = '' } = {}) {
    const where = ['a.tenant_id = :tenantId', 'a.checked_in_at >= CURDATE()', 'a.checked_in_at < DATE_ADD(CURDATE(), INTERVAL 1 DAY)'];
    const params = { tenantId };
    if (q?.trim().length) {
      where.push('(m.full_name LIKE :q OR m.member_code LIKE :q)');
      params.q = `%${q.trim()}%`;
    }
    const row = await queryOne(
      `SELECT COUNT(*) AS c
       FROM attendance_logs a
       INNER JOIN members m ON m.id = a.member_id
       WHERE ${where.join(' AND ')}`,
      params
    );
    return Number(row?.c ?? 0);
  }

  async listToday(tenantId, { q = '', limit = 200, offset = 0, sort = 'newest' } = {}) {
    const where = ['a.tenant_id = :tenantId', 'a.checked_in_at >= CURDATE()', 'a.checked_in_at < DATE_ADD(CURDATE(), INTERVAL 1 DAY)'];
    const params = { tenantId, limit, offset };
    if (q?.trim().length) {
      where.push('(m.full_name LIKE :q OR m.member_code LIKE :q)');
      params.q = `%${q.trim()}%`;
    }
    const order = sort === 'oldest' ? 'a.checked_in_at ASC, a.id ASC' : 'a.checked_in_at DESC, a.id DESC';
    return queryMany(
      `SELECT a.id, a.member_id, a.checked_in_at, a.checked_out_at, m.full_name, m.member_code
       FROM attendance_logs a
       INNER JOIN members m ON m.id = a.member_id
       WHERE ${where.join(' AND ')}
       ORDER BY ${order}
       LIMIT :limit OFFSET :offset`,
      params
    );
  }

  async countSince(tenantId, fromDateTime, { q = '' } = {}) {
    const where = ['a.tenant_id = :tenantId', 'a.checked_in_at >= :fromDateTime'];
    const params = { tenantId, fromDateTime };
    if (q?.trim().length) {
      where.push('(m.full_name LIKE :q OR m.member_code LIKE :q)');
      params.q = `%${q.trim()}%`;
    }
    const row = await queryOne(
      `SELECT COUNT(*) AS c
       FROM attendance_logs a
       INNER JOIN members m ON m.id = a.member_id
       WHERE ${where.join(' AND ')}`,
      params
    );
    return Number(row?.c ?? 0);
  }

  async listSince(tenantId, fromDateTime, { q = '', limit = 200, offset = 0, sort = 'newest' } = {}) {
    const where = ['a.tenant_id = :tenantId', 'a.checked_in_at >= :fromDateTime'];
    const params = { tenantId, fromDateTime, limit, offset };
    if (q?.trim().length) {
      where.push('(m.full_name LIKE :q OR m.member_code LIKE :q)');
      params.q = `%${q.trim()}%`;
    }
    const order = sort === 'oldest' ? 'a.checked_in_at ASC, a.id ASC' : 'a.checked_in_at DESC, a.id DESC';
    return queryMany(
      `SELECT a.id, a.member_id, a.checked_in_at, a.checked_out_at, m.full_name, m.member_code
       FROM attendance_logs a
       INNER JOIN members m ON m.id = a.member_id
       WHERE ${where.join(' AND ')}
       ORDER BY ${order}
       LIMIT :limit OFFSET :offset`,
      params
    );
  }

  async listForMember(tenantId, memberId, limit = 20) {
    return queryMany(
      `SELECT id, checked_in_at, checked_out_at, source
       FROM attendance_logs
       WHERE tenant_id = :tenantId AND member_id = :memberId
       ORDER BY checked_in_at DESC
       LIMIT :limit`,
      { tenantId, memberId, limit }
    );
  }

  async logEvent(tenantId, { memberId = null, queryValue = null, status, reason = null } = {}) {
    await execute(
      `INSERT INTO attendance_events (tenant_id, member_id, query_value, status, reason, checked_in_at)
       VALUES (:tenantId, :memberId, :queryValue, :status, :reason, :checkedInAt)`,
      {
        tenantId,
        memberId,
        queryValue,
        status,
        reason,
        checkedInAt: toMysqlDateTime(new Date())
      }
    );
  }

  async listEventsForMember(tenantId, memberId, limit = 50) {
    return queryMany(
      `SELECT id, status, reason, query_value, checked_in_at
       FROM attendance_events
       WHERE tenant_id = :tenantId AND member_id = :memberId
       ORDER BY checked_in_at DESC
       LIMIT :limit`,
      { tenantId, memberId, limit }
    );
  }
}

class SettingsRepository {
  async getOrCreate(tenantId) {
    const row = await queryOne(
      `SELECT currency, default_tax_percent, enable_sounds, enable_animations, at_risk_days, at_risk_whatsapp_template
       FROM gym_settings
       WHERE tenant_id = :tenantId
       LIMIT 1`,
      { tenantId }
    );
    if (row) return row;

    await execute('INSERT INTO gym_settings (tenant_id) VALUES (:tenantId)', { tenantId });
    return queryOne(
      `SELECT currency, default_tax_percent, enable_sounds, enable_animations, at_risk_days, at_risk_whatsapp_template
       FROM gym_settings
       WHERE tenant_id = :tenantId
       LIMIT 1`,
      { tenantId }
    );
  }

  async update(tenantId, patch) {
    const current = await this.getOrCreate(tenantId);
    const atRiskDays =
      patch.atRiskDays !== undefined && patch.atRiskDays !== null
        ? patch.atRiskDays
        : Number(current.at_risk_days ?? 3);
    const atRiskWhatsAppTemplate =
      patch.atRiskWhatsAppTemplate !== undefined ? patch.atRiskWhatsAppTemplate : current.at_risk_whatsapp_template ?? null;
    await execute(
      `UPDATE gym_settings
       SET currency = :currency,
           default_tax_percent = :defaultTaxPercent,
           enable_sounds = :enableSounds,
           enable_animations = :enableAnimations,
           at_risk_days = :atRiskDays,
           at_risk_whatsapp_template = :atRiskWhatsAppTemplate
       WHERE tenant_id = :tenantId`,
      {
        tenantId,
        currency: patch.currency,
        defaultTaxPercent: patch.defaultTaxPercent,
        enableSounds: patch.enableSounds ? 1 : 0,
        enableAnimations: patch.enableAnimations ? 1 : 0,
        atRiskDays,
        atRiskWhatsAppTemplate
      }
    );
    return this.getOrCreate(tenantId);
  }
}

class PaymentRepository {
  async count(tenantId, { q = '', from = '', to = '', method = '' } = {}) {
    const where = ['p.tenant_id = :tenantId'];
    const params = { tenantId };

    if (q?.length) {
      where.push('(i.invoice_no LIKE :q OR m.full_name LIKE :q OR m.member_code LIKE :q OR m.phone LIKE :q)');
      params.q = `%${q}%`;
    }
    if (method?.length) {
      where.push('p.method = :method');
      params.method = method;
    }
    if (from?.length) {
      where.push('DATE(p.paid_at) >= :from');
      params.from = from;
    }
    if (to?.length) {
      where.push('DATE(p.paid_at) <= :to');
      params.to = to;
    }

    const row = await queryOne(
      `SELECT COUNT(*) AS c
       FROM payments p
       INNER JOIN invoices i ON i.id = p.invoice_id
       INNER JOIN members m ON m.id = i.member_id
       WHERE ${where.join(' AND ')}`,
      params
    );
    return Number(row?.c ?? 0);
  }

  async list(tenantId, { q = '', from = '', to = '', method = '', limit = 200, offset = 0, sort = 'newest' } = {}) {
    const where = ['p.tenant_id = :tenantId'];
    const params = { tenantId, limit, offset };

    if (q?.length) {
      where.push(
        '(i.invoice_no LIKE :q OR m.full_name LIKE :q OR m.member_code LIKE :q OR m.phone LIKE :q)'
      );
      params.q = `%${q}%`;
    }
    if (method?.length) {
      where.push('p.method = :method');
      params.method = method;
    }
    if (from?.length) {
      where.push('DATE(p.paid_at) >= :from');
      params.from = from;
    }
    if (to?.length) {
      where.push('DATE(p.paid_at) <= :to');
      params.to = to;
    }

    const order = sort === 'oldest' ? 'p.paid_at ASC, p.id ASC' : 'p.paid_at DESC, p.id DESC';
    return queryMany(
      `SELECT p.id, p.invoice_id, p.amount, p.method, p.paid_at,
              i.invoice_no,
              m.full_name, m.member_code
       FROM payments p
       INNER JOIN invoices i ON i.id = p.invoice_id
       INNER JOIN members m ON m.id = i.member_id
       WHERE ${where.join(' AND ')}
       ORDER BY ${order}
       LIMIT :limit OFFSET :offset`,
      params
    );
  }

  async summary(tenantId) {
    const today = await queryOne(
      "SELECT COALESCE(SUM(amount), 0) AS s, COUNT(*) AS c FROM payments WHERE tenant_id = :tenantId AND DATE(paid_at) = CURDATE()",
      { tenantId }
    );
    const last7 = await queryOne(
      "SELECT COALESCE(SUM(amount), 0) AS s, COUNT(*) AS c FROM payments WHERE tenant_id = :tenantId AND paid_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)",
      { tenantId }
    );
    const last30 = await queryOne(
      "SELECT COALESCE(SUM(amount), 0) AS s, COUNT(*) AS c FROM payments WHERE tenant_id = :tenantId AND paid_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)",
      { tenantId }
    );
    const byMethod = await queryMany(
      `SELECT method, COALESCE(SUM(amount), 0) AS s, COUNT(*) AS c
       FROM payments
       WHERE tenant_id = :tenantId AND paid_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
       GROUP BY method
       ORDER BY s DESC`,
      { tenantId }
    );

    const revenueRows = await queryMany(
      `SELECT DATE(paid_at) AS d, COALESCE(SUM(amount), 0) AS s
       FROM payments
       WHERE tenant_id = :tenantId AND paid_at >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)
       GROUP BY DATE(paid_at)
       ORDER BY d ASC`,
      { tenantId }
    );
    const revenueMap = new Map(revenueRows.map((r) => [toDateOnly(new Date(r.d)), Number(r.s ?? 0)]));
    const last7d = [];
    for (let i = 6; i >= 0; i -= 1) {
      const date = addDays(new Date(), -i);
      const key = toDateOnly(date);
      last7d.push({ date: key, amount: Number(revenueMap.get(key) ?? 0) });
    }

    return {
      today: { total: Number(today?.s ?? 0), count: Number(today?.c ?? 0) },
      last7Days: { total: Number(last7?.s ?? 0), count: Number(last7?.c ?? 0) },
      last30Days: { total: Number(last30?.s ?? 0), count: Number(last30?.c ?? 0) },
      byMethod: byMethod.map((r) => ({ method: r.method, total: Number(r.s ?? 0), count: Number(r.c ?? 0) })),
      last7d
    };
  }
}

class ExpenseRepository {
  async list(tenantId, { q = '', from = '', to = '', category = '', limit = 200 } = {}) {
    const where = ['e.tenant_id = :tenantId'];
    const params = { tenantId, limit };

    if (q?.length) {
      where.push('(e.category LIKE :q OR e.notes LIKE :q)');
      params.q = `%${q}%`;
    }
    if (category?.length) {
      where.push('e.category = :category');
      params.category = category;
    }
    if (from?.length) {
      where.push('e.expense_date >= :from');
      params.from = from;
    }
    if (to?.length) {
      where.push('e.expense_date <= :to');
      params.to = to;
    }

    return queryMany(
      `SELECT e.id, e.category, e.amount, e.expense_date, e.notes, e.created_at
       FROM expenses e
       WHERE ${where.join(' AND ')}
       ORDER BY e.expense_date DESC, e.id DESC
       LIMIT :limit`,
      params
    );
  }

  async create(tenantId, { category, amount, expenseDate, notes = null }) {
    const result = await execute(
      `INSERT INTO expenses (tenant_id, category, amount, expense_date, notes)
       VALUES (:tenantId, :category, :amount, :expenseDate, :notes)`,
      { tenantId, category, amount, expenseDate, notes }
    );
    return Number(result.insertId);
  }

  async remove(tenantId, id) {
    await execute('DELETE FROM expenses WHERE tenant_id = :tenantId AND id = :id', { tenantId, id });
  }

  async summary(tenantId) {
    const today = await queryOne(
      "SELECT COALESCE(SUM(amount), 0) AS s, COUNT(*) AS c FROM expenses WHERE tenant_id = :tenantId AND expense_date = CURDATE()",
      { tenantId }
    );
    const month = await queryOne(
      "SELECT COALESCE(SUM(amount), 0) AS s, COUNT(*) AS c FROM expenses WHERE tenant_id = :tenantId AND expense_date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')",
      { tenantId }
    );
    const byCategory = await queryMany(
      `SELECT category, COALESCE(SUM(amount), 0) AS s, COUNT(*) AS c
       FROM expenses
       WHERE tenant_id = :tenantId AND expense_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
       GROUP BY category
       ORDER BY s DESC
       LIMIT 10`,
      { tenantId }
    );
    return {
      today: { total: Number(today?.s ?? 0), count: Number(today?.c ?? 0) },
      thisMonth: { total: Number(month?.s ?? 0), count: Number(month?.c ?? 0) },
      byCategory: byCategory.map((r) => ({ category: r.category, total: Number(r.s ?? 0), count: Number(r.c ?? 0) }))
    };
  }
}

class ProductRepository {
  async list(tenantId, { q = '', status = '', lowStock = false, from = '', to = '', limit = 200 } = {}) {
    const where = ['p.tenant_id = :tenantId'];
    const params = { tenantId, limit };

    if (q?.length) {
      where.push('(p.name LIKE :q OR p.sku LIKE :q)');
      params.q = `%${q}%`;
    }
    if (status === 'active' || status === 'inactive') {
      where.push('p.status = :status');
      params.status = status;
    }
    if (from?.length) {
      where.push('DATE(p.created_at) >= :from');
      params.from = from;
    }
    if (to?.length) {
      where.push('DATE(p.created_at) <= :to');
      params.to = to;
    }

    const rows = await queryMany(
      `SELECT p.id, p.name, p.sku, p.price, p.status,
              COALESCE((
                SELECT SUM(CASE WHEN sm.movement_type = 'in' THEN sm.qty ELSE -sm.qty END)
                FROM stock_movements sm
                WHERE sm.tenant_id = p.tenant_id AND sm.product_id = p.id
              ), 0) AS on_hand
       FROM products p
       WHERE ${where.join(' AND ')}
       ORDER BY p.id DESC
       LIMIT :limit`,
      params
    );

    if (!lowStock) return rows;
    return rows.filter((r) => Number(r.on_hand ?? 0) < 5);
  }

  async create(tenantId, { name, sku = null, price = 0, status = 'active' }) {
    const result = await execute(
      `INSERT INTO products (tenant_id, name, sku, price, status)
       VALUES (:tenantId, :name, :sku, :price, :status)`,
      { tenantId, name, sku, price, status }
    );
    return Number(result.insertId);
  }

  async update(tenantId, id, patch) {
    await execute(
      `UPDATE products
       SET name = :name, sku = :sku, price = :price, status = :status
       WHERE tenant_id = :tenantId AND id = :id`,
      { tenantId, id, name: patch.name, sku: patch.sku, price: patch.price, status: patch.status }
    );
  }

  async getById(tenantId, id) {
    return queryOne(
      `SELECT id, name, sku, price, status
       FROM products
       WHERE tenant_id = :tenantId AND id = :id`,
      { tenantId, id }
    );
  }
}

class StockRepository {
  async move(tenantId, { productId, qty, movementType, reason = null }) {
    const result = await execute(
      `INSERT INTO stock_movements (tenant_id, product_id, qty, movement_type, reason)
       VALUES (:tenantId, :productId, :qty, :movementType, :reason)`,
      { tenantId, productId, qty, movementType, reason }
    );
    return Number(result.insertId);
  }

  async listMovements(tenantId, { productId = null, limit = 200 } = {}) {
    const where = ['sm.tenant_id = :tenantId'];
    const params = { tenantId, limit };
    if (productId) {
      where.push('sm.product_id = :productId');
      params.productId = productId;
    }
    return queryMany(
      `SELECT sm.id, sm.product_id, sm.qty, sm.movement_type, sm.reason, sm.created_at, p.name AS product_name
       FROM stock_movements sm
       INNER JOIN products p ON p.id = sm.product_id
       WHERE ${where.join(' AND ')}
       ORDER BY sm.id DESC
       LIMIT :limit`,
      params
    );
  }
}

class StaffRepository {
  async listUsers(tenantId, limit = 200) {
    const users = await queryMany(
      `SELECT id, email, full_name, status, created_at
       FROM users
       WHERE tenant_id = :tenantId
       ORDER BY id DESC
       LIMIT :limit`,
      { tenantId, limit }
    );
    const roles = await queryMany(
      `SELECT ur.user_id, r.name
       FROM user_roles ur
       INNER JOIN roles r ON r.id = ur.role_id
       INNER JOIN users u ON u.id = ur.user_id
       WHERE u.tenant_id = :tenantId`,
      { tenantId }
    );
    const byUser = new Map();
    for (const r of roles) {
      const userId = Number(r.user_id);
      const list = byUser.get(userId) ?? [];
      list.push(r.name);
      byUser.set(userId, list);
    }
    return users.map((u) => ({
      ...u,
      roles: byUser.get(Number(u.id)) ?? []
    }));
  }

  async createUser(tenantId, { email, fullName, password, roles = ['staff'] }) {
    const passwordHash = await bcrypt.hash(password, 10);
    const pool = await getPool();
    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();
      const [userRes] = await conn.execute(
        `INSERT INTO users (tenant_id, email, password_hash, full_name)
         VALUES (:tenantId, :email, :passwordHash, :fullName)`,
        { tenantId, email, passwordHash, fullName }
      );
      const userId = Number(userRes.insertId);

      for (const roleName of roles) {
        const [roleRows] = await conn.query(
          'SELECT id FROM roles WHERE tenant_id = :tenantId AND name = :name LIMIT 1',
          { tenantId, name: roleName }
        );
        const roleId = Array.isArray(roleRows) && roleRows[0]?.id ? Number(roleRows[0].id) : null;
        if (!roleId) continue;
        await conn.execute('INSERT IGNORE INTO user_roles (user_id, role_id) VALUES (:userId, :roleId)', {
          userId,
          roleId
        });
      }

      await conn.commit();
      return userId;
    } catch (e) {
      await conn.rollback();
      throw e;
    } finally {
      conn.release();
    }
  }

  async setUserRoles(tenantId, userId, roleNames) {
    const pool = await getPool();
    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();
      const [userRows] = await conn.query(
        'SELECT id FROM users WHERE tenant_id = :tenantId AND id = :id LIMIT 1',
        { tenantId, id: userId }
      );
      if (!Array.isArray(userRows) || !userRows[0]?.id) {
        await conn.rollback();
        return { ok: false, error: 'user_not_found' };
      }

      await conn.execute(
        `DELETE ur FROM user_roles ur
         INNER JOIN roles r ON r.id = ur.role_id
         WHERE ur.user_id = :userId AND r.tenant_id = :tenantId`,
        { userId, tenantId }
      );

      for (const roleName of roleNames) {
        const [roleRows] = await conn.query(
          'SELECT id FROM roles WHERE tenant_id = :tenantId AND name = :name LIMIT 1',
          { tenantId, name: roleName }
        );
        const roleId = Array.isArray(roleRows) && roleRows[0]?.id ? Number(roleRows[0].id) : null;
        if (!roleId) continue;
        await conn.execute('INSERT IGNORE INTO user_roles (user_id, role_id) VALUES (:userId, :roleId)', {
          userId,
          roleId
        });
      }

      await conn.commit();
      return { ok: true };
    } catch (e) {
      await conn.rollback();
      throw e;
    } finally {
      conn.release();
    }
  }
}

class SentinelService {
  constructor() {
    this.members = new MemberRepository();
    this.subs = new SubscriptionRepository();
    this.invoices = new InvoiceRepository();
    this.attendance = new AttendanceRepository();
  }

  async validateAccess(tenantId, queryValue) {
    const member = await this.members.findByCodeOrPhone(tenantId, queryValue);
    if (!member) {
      await this.attendance.logEvent(tenantId, { queryValue, status: 'denied', reason: 'member_not_found' });
      return {
        allowed: false,
        reason: 'member_not_found'
      };
    }

    const activeSub = await this.subs.getActiveForMember(tenantId, Number(member.id));
    const today = toDateOnly(new Date());
    const frozenUntil = member.frozen_until ?? null;
    const membershipFrozen = frozenUntil && String(frozenUntil) >= today;
    const expiryDate = activeSub?.end_date ?? null;
    const membershipExpired = !expiryDate || String(expiryDate) < today;

    const unpaidCount = await this.invoices.countUnpaidForMember(tenantId, Number(member.id));
    const feesPending = unpaidCount > 0;

    if (membershipFrozen || membershipExpired || feesPending) {
      const reason = membershipFrozen ? 'membership_frozen' : membershipExpired ? 'membership_expired' : 'fees_pending';
      await this.attendance.logEvent(tenantId, {
        memberId: Number(member.id),
        queryValue,
        status: 'denied',
        reason
      });
      return {
        allowed: false,
        reason,
        member: {
          id: Number(member.id),
          memberCode: member.member_code,
          fullName: member.full_name,
          phone: member.phone
        },
        plan: activeSub
          ? {
              id: Number(activeSub.plan_id),
              name: activeSub.plan_name,
              endDate: activeSub.end_date
            }
          : null,
        unpaidInvoices: unpaidCount,
        frozenUntil: frozenUntil
      };
    }

    return {
      allowed: true,
      member: {
        id: Number(member.id),
        memberCode: member.member_code,
        fullName: member.full_name,
        phone: member.phone
      },
      plan: activeSub
        ? {
            id: Number(activeSub.plan_id),
            name: activeSub.plan_name,
            endDate: activeSub.end_date
          }
        : null,
      unpaidInvoices: unpaidCount
    };
  }
}

app.get('/health', async (req, res) => {
  try {
    await queryOne('SELECT 1 AS ok');
    return res.json({ ok: true, db: true });
  } catch {
    return res.json({ ok: true, db: false });
  }
});

app.post('/dev/seed', async (req, res) => {
  const isProd = (process.env.NODE_ENV ?? '').toLowerCase() === 'production';
  const allow = (process.env.ALLOW_DEV_SEED ?? '').toLowerCase() !== 'false';
  if (isProd || !allow) return res.status(403).json({ error: 'forbidden' });

  const bodySchema = z.object({
    tenantSlug: z.string().min(2).max(64),
    tenantName: z.string().min(2).max(191),
    adminEmail: z.string().email().max(191),
    adminPassword: z.string().min(6).max(191),
    adminName: z.string().min(2).max(191)
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });

  const { tenantSlug, tenantName, adminEmail, adminPassword, adminName } = parsed.data;
  const pool = await getPool();
  const conn = await pool.getConnection();
  try {
    const connQueryOne = async (sql, params) => {
      const [rows] = await conn.query(sql, params);
      if (!Array.isArray(rows) || rows.length === 0) return null;
      return rows[0];
    };

    await conn.beginTransaction();
    let tenant = await connQueryOne('SELECT id, slug, name FROM tenants WHERE slug = :slug', { slug: tenantSlug });
    if (!tenant) {
      const [result] = await conn.execute('INSERT INTO tenants (slug, name) VALUES (:slug, :name)', {
        slug: tenantSlug,
        name: tenantName
      });
      tenant = { id: Number(result.insertId), slug: tenantSlug, name: tenantName };
    }

    const defaultRoles = ['owner', 'admin', 'staff', 'receptionist'];
    for (const roleName of defaultRoles) {
      await conn.query(
        'INSERT IGNORE INTO roles (tenant_id, name) VALUES (:tenantId, :name)',
        { tenantId: tenant.id, name: roleName }
      );
    }

    const passwordHash = await bcrypt.hash(adminPassword, 10);
    const existingUser = await connQueryOne(
      'SELECT id FROM users WHERE tenant_id = :tenantId AND email = :email',
      { tenantId: tenant.id, email: adminEmail }
    );

    let userId = existingUser?.id ? Number(existingUser.id) : null;
    if (!userId) {
      const userResult = await conn.query(
        'INSERT INTO users (tenant_id, email, password_hash, full_name) VALUES (:tenantId, :email, :passwordHash, :fullName)',
        {
          tenantId: tenant.id,
          email: adminEmail,
          passwordHash,
          fullName: adminName
        }
      );
      userId = Number(userResult[0].insertId);
    }

    const ownerRole = await connQueryOne(
      'SELECT id FROM roles WHERE tenant_id = :tenantId AND name = :name',
      { tenantId: tenant.id, name: 'owner' }
    );
    if (ownerRole?.id) {
      await conn.query(
        'INSERT IGNORE INTO user_roles (user_id, role_id) VALUES (:userId, :roleId)',
        { userId, roleId: Number(ownerRole.id) }
      );
    }

    await conn.commit();
    return res.json({ ok: true, tenant, adminUserId: userId });
  } catch (e) {
    await conn.rollback();
    return res.status(500).json({ error: 'server_error' });
  } finally {
    conn.release();
  }
});

app.post('/dev/seed-mock', async (req, res) => {
  const isProd = (process.env.NODE_ENV ?? '').toLowerCase() === 'production';
  const allow = (process.env.ALLOW_DEV_SEED ?? '').toLowerCase() !== 'false';
  if (isProd || !allow) return res.status(403).json({ error: 'forbidden' });

  const bodySchema = z.object({
    tenantSlug: z.string().min(2).max(64)
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });

  const tenant = await queryOne('SELECT id FROM tenants WHERE slug = :slug', { slug: parsed.data.tenantSlug });
  if (!tenant) return res.status(404).json({ error: 'tenant_not_found' });
  const tenantId = Number(tenant.id);

  const now = new Date();
  const day0 = new Date(now);
  day0.setHours(10, 0, 0, 0);

  const planDefs = [
    { name: 'Monthly', durationDays: 30, price: 3000, admissionFee: 500 },
    { name: 'Quarterly', durationDays: 90, price: 8000, admissionFee: 0 },
    { name: 'Yearly', durationDays: 365, price: 25000, admissionFee: 0 }
  ];

  const memberDefs = [
    { memberCode: 'M-1001', fullName: 'Ali Khan', phone: '03001234567' },
    { memberCode: 'M-1002', fullName: 'Hassan Ahmed', phone: '03019876543' },
    { memberCode: 'M-1003', fullName: 'Sara Noor', phone: '03111222333' },
    { memberCode: 'M-1004', fullName: 'Umer Farooq', phone: '03223334444' },
    { memberCode: 'M-1005', fullName: 'Ayesha Tariq', phone: '03335556666' }
  ];

  const pool = await getPool();
  const conn = await pool.getConnection();
  try {
    const connQueryOne = async (sql, params) => {
      const [rows] = await conn.query(sql, params);
      if (!Array.isArray(rows) || rows.length === 0) return null;
      return rows[0];
    };
    const connQueryMany = async (sql, params) => {
      const [rows] = await conn.query(sql, params);
      return Array.isArray(rows) ? rows : [];
    };

    await conn.beginTransaction();

    let plansInserted = 0;
    for (const p of planDefs) {
      const existing = await connQueryOne(
        'SELECT id FROM membership_plans WHERE tenant_id = :tenantId AND name = :name LIMIT 1',
        { tenantId, name: p.name }
      );
      if (existing?.id) continue;
      await conn.execute(
        `INSERT INTO membership_plans (tenant_id, name, duration_days, price, admission_fee, status)
         VALUES (:tenantId, :name, :durationDays, :price, :admissionFee, 'active')`,
        {
          tenantId,
          name: p.name,
          durationDays: p.durationDays,
          price: p.price,
          admissionFee: p.admissionFee
        }
      );
      plansInserted += 1;
    }

    const plans = await connQueryMany(
      `SELECT id, name, duration_days, price, admission_fee
       FROM membership_plans
       WHERE tenant_id = :tenantId AND status = 'active'
       ORDER BY id ASC`,
      { tenantId }
    );
    if (plans.length < 1) {
      await conn.rollback();
      return res.status(400).json({ error: 'no_plans_available' });
    }

    let membersInserted = 0;
    for (const m of memberDefs) {
      const existing = await connQueryOne(
        'SELECT id FROM members WHERE tenant_id = :tenantId AND member_code = :code LIMIT 1',
        { tenantId, code: m.memberCode }
      );
      if (existing?.id) continue;

      const joinDate = m.memberCode === 'M-1001' ? addDays(new Date(), -90) : addDays(new Date(), -12);
      await conn.execute(
        `INSERT INTO members (tenant_id, member_code, full_name, phone, join_date, status)
         VALUES (:tenantId, :memberCode, :fullName, :phone, :joinDate, 'active')`,
        {
          tenantId,
          memberCode: m.memberCode,
          fullName: m.fullName,
          phone: m.phone,
          joinDate: toDateOnly(joinDate)
        }
      );
      membersInserted += 1;
    }

    const members = await connQueryMany(
      `SELECT id, member_code, join_date
       FROM members
       WHERE tenant_id = :tenantId AND status = 'active'
       ORDER BY id ASC
       LIMIT 50`,
      { tenantId }
    );

    let subsInserted = 0;
    for (let i = 0; i < members.length; i += 1) {
      const member = members[i];
      const existingSub = await connQueryOne(
        'SELECT id FROM subscriptions WHERE tenant_id = :tenantId AND member_id = :memberId LIMIT 1',
        { tenantId, memberId: Number(member.id) }
      );
      if (existingSub?.id) continue;

      const plan = plans[i % plans.length];
      const startDate = new Date(String(member.join_date));
      const endDate = addDays(startDate, Number(plan.duration_days));
      await conn.execute(
        `INSERT INTO subscriptions (tenant_id, member_id, plan_id, start_date, end_date, status)
         VALUES (:tenantId, :memberId, :planId, :startDate, :endDate, 'active')`,
        {
          tenantId,
          memberId: Number(member.id),
          planId: Number(plan.id),
          startDate: toDateOnly(startDate),
          endDate: toDateOnly(endDate)
        }
      );
      subsInserted += 1;
    }

    const seedKey = `SEED-${parsed.data.tenantSlug}-${toDateOnly(new Date()).replaceAll('-', '')}`;
    let invoicesInserted = 0;
    let paymentsInserted = 0;
    let attendanceInserted = 0;

    const pickMember = (dayIndex) => members[dayIndex % Math.max(members.length, 1)];
    for (let i = 0; i < 7; i += 1) {
      const d = addDays(day0, -i);
      const day = toDateOnly(d);

      const memA = pickMember(i);
      const memB = pickMember(i + 2);

      const planA = plans[i % plans.length];
      const planB = plans[(i + 1) % plans.length];

      const paidInvoiceNo = `${seedKey}-P-${i + 1}`;
      const unpaidInvoiceNo = `${seedKey}-U-${i + 1}`;

      const hasPaid = await connQueryOne(
        'SELECT id FROM invoices WHERE tenant_id = :tenantId AND invoice_no = :no LIMIT 1',
        { tenantId, no: paidInvoiceNo }
      );
      if (!hasPaid?.id && memA?.id) {
        const subtotal = Number(planA.price) + Number(planA.admission_fee ?? 0);
        const tax = Number(((subtotal * 5) / 100).toFixed(2));
        const total = Number((subtotal + tax).toFixed(2));
        const [invRes] = await conn.execute(
          `INSERT INTO invoices (tenant_id, member_id, invoice_no, subtotal, discount, tax, total, status, due_date, created_at)
           VALUES (:tenantId, :memberId, :invoiceNo, :subtotal, 0, :tax, :total, 'paid', :dueDate, :createdAt)`,
          {
            tenantId,
            memberId: Number(memA.id),
            invoiceNo: paidInvoiceNo,
            subtotal,
            tax,
            total,
            dueDate: day,
            createdAt: `${day} 11:00:00`
          }
        );
        invoicesInserted += 1;

        const invoiceId = Number(invRes.insertId);
        await conn.execute(
          `INSERT INTO payments (tenant_id, invoice_id, amount, method, paid_at, created_at)
           VALUES (:tenantId, :invoiceId, :amount, :method, :paidAt, :createdAt)`,
          {
            tenantId,
            invoiceId,
            amount: total,
            method: i % 2 === 0 ? 'cash' : 'online',
            paidAt: `${day} 12:00:00`,
            createdAt: `${day} 12:00:00`
          }
        );
        paymentsInserted += 1;
      }

      const hasUnpaid = await connQueryOne(
        'SELECT id FROM invoices WHERE tenant_id = :tenantId AND invoice_no = :no LIMIT 1',
        { tenantId, no: unpaidInvoiceNo }
      );
      if (!hasUnpaid?.id && memB?.id) {
        const subtotal = Number(planB.price) + Number(planB.admission_fee ?? 0);
        const tax = Number(((subtotal * 5) / 100).toFixed(2));
        const total = Number((subtotal + tax).toFixed(2));
        await conn.execute(
          `INSERT INTO invoices (tenant_id, member_id, invoice_no, subtotal, discount, tax, total, status, due_date, created_at)
           VALUES (:tenantId, :memberId, :invoiceNo, :subtotal, 0, :tax, :total, 'unpaid', :dueDate, :createdAt)`,
          {
            tenantId,
            memberId: Number(memB.id),
            invoiceNo: unpaidInvoiceNo,
            subtotal,
            tax,
            total,
            dueDate: day,
            createdAt: `${day} 16:00:00`
          }
        );
        invoicesInserted += 1;
      }

      for (const mem of [memA, memB]) {
        if (!mem?.id) continue;
        const existsAtt = await connQueryOne(
          `SELECT id
           FROM attendance_logs
           WHERE tenant_id = :tenantId AND member_id = :memberId AND DATE(checked_in_at) = :day
           LIMIT 1`,
          { tenantId, memberId: Number(mem.id), day }
        );
        if (existsAtt?.id) continue;
        const hour = 9 + (i % 4);
        await conn.execute(
          `INSERT INTO attendance_logs (tenant_id, member_id, branch_id, checked_in_at, source)
           VALUES (:tenantId, :memberId, NULL, :checkedInAt, 'manual')`,
          { tenantId, memberId: Number(mem.id), checkedInAt: `${day} ${String(hour).padStart(2, '0')}:15:00` }
        );
        attendanceInserted += 1;
      }
    }

    await conn.commit();
    return res.json({
      ok: true,
      tenantId,
      inserted: {
        plans: plansInserted,
        members: membersInserted,
        subscriptions: subsInserted,
        invoices: invoicesInserted,
        payments: paymentsInserted,
        attendance: attendanceInserted
      }
    });
  } catch (e) {
    await conn.rollback();
    return res.status(500).json({ error: 'seed_mock_failed' });
  } finally {
    conn.release();
  }
});

app.post('/auth/login', async (req, res) => {
  const bodySchema = z.object({
    tenantSlug: z.string().min(2).max(64),
    email: z.string().email().max(191),
    password: z.string().min(1).max(191)
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });

  const { tenantSlug, email, password } = parsed.data;
  const tenant = await queryOne('SELECT id, status FROM tenants WHERE slug = :slug', { slug: tenantSlug });
  if (!tenant || tenant.status !== 'active') return res.status(401).json({ error: 'invalid_credentials' });

  const user = await queryOne(
    'SELECT id, password_hash, full_name, status FROM users WHERE tenant_id = :tenantId AND email = :email',
    { tenantId: Number(tenant.id), email }
  );
  if (!user || user.status !== 'active') return res.status(401).json({ error: 'invalid_credentials' });

  const ok = await bcrypt.compare(password, user.password_hash);
  if (!ok) return res.status(401).json({ error: 'invalid_credentials' });

  const roles = await queryMany(
    `SELECT r.name
     FROM user_roles ur
     INNER JOIN roles r ON r.id = ur.role_id
     WHERE ur.user_id = :userId`,
    { userId: Number(user.id) }
  );
  let roleNames = roles.map((r) => r.name);
  if (roleNames.length === 0) {
    const hasOwner = await queryOne(
      `SELECT 1 AS ok
       FROM user_roles ur
       INNER JOIN roles r ON r.id = ur.role_id
       INNER JOIN users u ON u.id = ur.user_id
       WHERE u.tenant_id = :tenantId AND r.name = 'owner'
       LIMIT 1`,
      { tenantId: Number(tenant.id) }
    );
    if (!hasOwner?.ok) {
      const oldestUser = await queryOne(
        `SELECT id
         FROM users
         WHERE tenant_id = :tenantId
         ORDER BY id ASC
         LIMIT 1`,
        { tenantId: Number(tenant.id) }
      );
      if (Number(oldestUser?.id) === Number(user.id)) {
        await execute(
          `INSERT IGNORE INTO roles (tenant_id, name)
           VALUES (:tenantId, 'owner'), (:tenantId, 'admin'), (:tenantId, 'staff')`,
          { tenantId: Number(tenant.id) }
        );
        const ownerRole = await queryOne(
          'SELECT id FROM roles WHERE tenant_id = :tenantId AND name = :name LIMIT 1',
          { tenantId: Number(tenant.id), name: 'owner' }
        );
        if (ownerRole?.id) {
          await execute('INSERT IGNORE INTO user_roles (user_id, role_id) VALUES (:userId, :roleId)', {
            userId: Number(user.id),
            roleId: Number(ownerRole.id)
          });
          roleNames = ['owner'];
        }
      }
    }
  }
  const token = signToken({ tid: Number(tenant.id), uid: Number(user.id), roles: roleNames });

  return res.json({
    token,
    user: {
      id: Number(user.id),
      fullName: user.full_name,
      email,
      roles: roleNames,
      tenantSlug
    }
  });
});

await ensureOperationalTables();

const planRepo = new PlanRepository();
const memberRepo = new MemberRepository();
const leadRepo = new LeadRepository();
const subRepo = new SubscriptionRepository();
const invoiceRepo = new InvoiceRepository();
const attendanceRepo = new AttendanceRepository();
const sentinelService = new SentinelService();
const settingsRepo = new SettingsRepository();
const paymentRepo = new PaymentRepository();
const expenseRepo = new ExpenseRepository();
const productRepo = new ProductRepository();
const stockRepo = new StockRepository();
const staffRepo = new StaffRepository();

const tryAcquireDbLock = async (name) => {
  const row = await queryOne('SELECT GET_LOCK(:name, 0) AS got', { name });
  return Number(row?.got ?? 0) === 1;
};

const releaseDbLock = async (name) => {
  try {
    await queryOne('SELECT RELEASE_LOCK(:name) AS r', { name });
  } catch {}
};

const runMembershipExpiryJob = async () => {
  const got = await tryAcquireDbLock('gms_membership_expiry_job_v2');
  if (!got) return;

  const connPool = await getPool();
  const conn = await connPool.getConnection();
  try {
    await conn.beginTransaction();

    const byTenant = await conn.query(
      `SELECT tenant_id, COUNT(*) AS c
       FROM subscriptions
       WHERE status = 'active' AND end_date < CURDATE()
       GROUP BY tenant_id`
    );
    const rows = Array.isArray(byTenant?.[0]) ? byTenant[0] : [];

    const [invResult] = await conn.execute(
      `INSERT IGNORE INTO invoices (tenant_id, member_id, subscription_id, invoice_no, subtotal, discount, tax, total, status, due_date)
       SELECT s.tenant_id,
              s.member_id,
              s.id,
              CONCAT('REN-', DATE_FORMAT(s.end_date, '%Y%m%d'), '-', LPAD(s.id, 8, '0')) AS invoice_no,
              p.price AS subtotal,
              0 AS discount,
              0 AS tax,
              p.price AS total,
              'unpaid' AS status,
              CURDATE() AS due_date
       FROM subscriptions s
       INNER JOIN members m ON m.tenant_id = s.tenant_id AND m.id = s.member_id
       INNER JOIN membership_plans p ON p.tenant_id = s.tenant_id AND p.id = s.plan_id
       WHERE s.end_date < CURDATE()
         AND s.status IN ('active', 'expired')
         AND m.status <> 'inactive'
         AND NOT EXISTS (
           SELECT 1
           FROM invoices i
           WHERE i.tenant_id = s.tenant_id
             AND i.member_id = s.member_id
             AND i.status = 'unpaid'
         )`
    );
    const invoicesCreated = Number(invResult?.affectedRows ?? 0);

    await conn.execute(
      `UPDATE subscriptions
       SET status = 'expired'
       WHERE status = 'active' AND end_date < CURDATE()`
    );

    try {
      await conn.execute(
        `UPDATE members m
         SET m.status = 'expired'
         WHERE m.status = 'active'
           AND EXISTS (
             SELECT 1
             FROM subscriptions s
             WHERE s.tenant_id = m.tenant_id
               AND s.member_id = m.id
               AND s.status = 'expired'
               AND s.end_date < CURDATE()
           )
           AND NOT EXISTS (
             SELECT 1
             FROM subscriptions s2
             WHERE s2.tenant_id = m.tenant_id
               AND s2.member_id = m.id
               AND s2.status = 'active'
               AND s2.end_date >= CURDATE()
           )`
      );
      await conn.execute(
        `UPDATE members m
         SET m.status = 'active'
         WHERE m.status = 'expired'
           AND EXISTS (
             SELECT 1
             FROM subscriptions s
             WHERE s.tenant_id = m.tenant_id
               AND s.member_id = m.id
               AND s.status = 'active'
               AND s.end_date >= CURDATE()
           )`
      );
    } catch {}

    await conn.commit();

    if (rows.length) {
      for (const r of rows) {
        await appendSystemLog(
          {
            tenantId: Number(r.tenant_id),
            actorUserId: null,
            action: 'membership_auto_expire',
            entityType: 'subscription',
            entityId: null,
            meta: { count: Number(r.c ?? 0), invoicesCreated }
          },
          conn
        );
      }
    }
  } catch {
    try {
      await conn.rollback();
    } catch {}
  } finally {
    conn.release();
    await releaseDbLock('gms_membership_expiry_job_v2');
  }
};

runMembershipExpiryJob().then(
  () => {},
  () => {}
);
setInterval(() => {
  runMembershipExpiryJob().then(
    () => {},
    () => {}
  );
}, 60 * 60 * 1000);

const runExpirySoonAlertJob = async () => {
  const tenants = await queryMany('SELECT id FROM tenants WHERE status = \'active\'');
  for (const t of tenants) {
    const tenantId = Number(t.id);
    if (!Number.isFinite(tenantId) || tenantId <= 0) continue;
    const row = await queryOne(
      `SELECT COUNT(*) AS c
       FROM subscriptions s
       INNER JOIN members m ON m.id = s.member_id
       WHERE s.tenant_id = :tenantId
         AND s.status = 'active'
         AND m.status = 'active'
         AND s.end_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 3 DAY)`,
      { tenantId }
    );
    const c = Number(row?.c ?? 0);
    if (c <= 0) continue;
    process.stdout.write(`[alerts] tenant=${tenantId} expiring_in_3_days=${c}\n`);
    await appendSystemLog({
      tenantId,
      actorUserId: null,
      action: 'membership_expiry_soon',
      entityType: 'subscription',
      entityId: null,
      meta: { count: c }
    });
  }
};

runExpirySoonAlertJob().then(
  () => {},
  () => {}
);
setInterval(() => {
  runExpirySoonAlertJob().then(
    () => {},
    () => {}
  );
}, 24 * 60 * 60 * 1000);

app.get('/auth/me', authMiddleware, async (req, res) => {
  const user = await queryOne(
    'SELECT id, email, full_name, status FROM users WHERE id = :id AND tenant_id = :tenantId',
    { id: req.user.userId, tenantId: req.user.tenantId }
  );
  if (!user || user.status !== 'active') return res.status(401).json({ error: 'unauthorized' });
  return res.json({
    id: Number(user.id),
    email: user.email,
    fullName: user.full_name,
    roles: req.user.roles
  });
});

app.get('/settings', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const row = await settingsRepo.getOrCreate(req.user.tenantId);
  const profile = await loadGymProfileForTenant(req.user.tenantId);
  return res.json({
    gymName: profile.gymName,
    currency: row.currency,
    defaultTaxPercent: Number(row.default_tax_percent ?? 0),
    enableSounds: Boolean(row.enable_sounds),
    enableAnimations: Boolean(row.enable_animations),
    atRiskDays: Number(row.at_risk_days ?? 3),
    atRiskWhatsAppTemplate: row.at_risk_whatsapp_template ?? null,
    address: profile.address,
    logoUrl: profile.logoUrl,
    websiteUrl: profile.websiteUrl,
    facebookUrl: profile.facebookUrl,
    instagramUrl: profile.instagramUrl,
    whatsapp: profile.whatsapp
  });
});

app.put('/settings', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const bodySchema = z.object({
    gymName: z.string().min(1).max(191).optional().nullable(),
    currency: z.string().min(1).max(16).optional().default('PKR'),
    defaultTaxPercent: z.number().min(0).max(100).optional().default(5),
    enableSounds: z.boolean().optional().default(true),
    enableAnimations: z.boolean().optional().default(true),
    atRiskDays: z.number().int().min(1).max(60).optional(),
    atRiskWhatsAppTemplate: z.string().max(600).optional().nullable(),
    address: z.string().max(255).optional().nullable(),
    logoUrl: z.string().max(60000).optional().nullable(),
    websiteUrl: z.string().max(255).optional().nullable(),
    facebookUrl: z.string().max(255).optional().nullable(),
    instagramUrl: z.string().max(255).optional().nullable(),
    whatsapp: z.string().max(64).optional().nullable()
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });
  if (parsed.data.gymName != null) {
    await execute('UPDATE tenants SET name = :name WHERE id = :tenantId', { tenantId: req.user.tenantId, name: parsed.data.gymName });
  }
  const updated = await settingsRepo.update(req.user.tenantId, parsed.data);
  await execute(
    `INSERT INTO gym_profile (tenant_id, address, logo_url, website_url, facebook_url, instagram_url, whatsapp)
     VALUES (:tenantId, :address, :logoUrl, :websiteUrl, :facebookUrl, :instagramUrl, :whatsapp)
     ON DUPLICATE KEY UPDATE
       address = :address,
       logo_url = :logoUrl,
       website_url = :websiteUrl,
       facebook_url = :facebookUrl,
       instagram_url = :instagramUrl,
       whatsapp = :whatsapp`,
    {
      tenantId: req.user.tenantId,
      address: parsed.data.address ?? null,
      logoUrl: parsed.data.logoUrl ?? null,
      websiteUrl: parsed.data.websiteUrl ?? null,
      facebookUrl: parsed.data.facebookUrl ?? null,
      instagramUrl: parsed.data.instagramUrl ?? null,
      whatsapp: parsed.data.whatsapp ?? null
    }
  );
  await appendSystemLog({
    tenantId: req.user.tenantId,
    actorUserId: req.user.userId,
    action: 'settings_update',
    entityType: 'settings',
    entityId: null,
    meta: { gymName: parsed.data.gymName ?? null, currency: parsed.data.currency, defaultTaxPercent: parsed.data.defaultTaxPercent },
    ip: req.ip,
    userAgent: req.headers['user-agent']?.toString() ?? null
  });
  return res.json({
    gymName: parsed.data.gymName ?? null,
    currency: updated.currency,
    defaultTaxPercent: Number(updated.default_tax_percent ?? 0),
    enableSounds: Boolean(updated.enable_sounds),
    enableAnimations: Boolean(updated.enable_animations),
    atRiskDays: Number(updated.at_risk_days ?? 3),
    atRiskWhatsAppTemplate: updated.at_risk_whatsapp_template ?? null,
    address: parsed.data.address ?? null,
    logoUrl: parsed.data.logoUrl ?? null,
    websiteUrl: parsed.data.websiteUrl ?? null,
    facebookUrl: parsed.data.facebookUrl ?? null,
    instagramUrl: parsed.data.instagramUrl ?? null,
    whatsapp: parsed.data.whatsapp ?? null
  });
});

app.get(
  '/dashboard/at-risk-members',
  authMiddleware,
  requireRole('owner', 'admin', 'staff', 'receptionist'),
  async (req, res) => {
    const tenantId = req.user.tenantId;
    const limit = Math.min(Math.max(Number(req.query.limit ?? 10), 1), 30);
    const settings = await settingsRepo.getOrCreate(tenantId);
    const profile = await loadGymProfileForTenant(tenantId);
    const configuredDays = Number(settings.at_risk_days ?? 3);
    const days = Math.min(
      Math.max(Number(req.query.days ?? configuredDays), 1),
      60
    );
    const template =
      settings.at_risk_whatsapp_template ??
      'Hello {name}, you have not visited the gym for {days} days. Please visit soon. {gym}';

    const items = await queryMany(
      `SELECT m.id AS member_id,
              m.full_name,
              m.member_code,
              m.phone,
              last.last_checkin_at
       FROM members m
       LEFT JOIN (
         SELECT member_id, MAX(checked_in_at) AS last_checkin_at
         FROM attendance_logs
         WHERE tenant_id = :tenantId
         GROUP BY member_id
       ) last ON last.member_id = m.id
       WHERE m.tenant_id = :tenantId
         AND m.status = 'active'
         AND (
           last.last_checkin_at IS NULL
           OR last.last_checkin_at < DATE_SUB(CURDATE(), INTERVAL :days DAY)
         )
       ORDER BY COALESCE(last.last_checkin_at, '1900-01-01') ASC, m.id ASC
       LIMIT :limit`,
      { tenantId, days, limit }
    );

    return res.json({
      days,
      template,
      gymName: profile.gymName ?? null,
      items: items.map((r) => ({
        memberId: Number(r.member_id),
        fullName: r.full_name ?? '',
        memberCode: r.member_code ?? '',
        phone: r.phone ?? null,
        lastCheckinAt: r.last_checkin_at ?? null,
      })),
    });
  }
);

app.get('/payments', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const q = typeof req.query.q === 'string' ? req.query.q.trim() : '';
  const from = typeof req.query.from === 'string' ? req.query.from.trim() : '';
  const to = typeof req.query.to === 'string' ? req.query.to.trim() : '';
  const method = typeof req.query.method === 'string' ? req.query.method.trim() : '';
  const limit = Math.min(Math.max(Number(req.query.limit ?? 200), 1), 400);
  const offset = Math.min(Math.max(Number(req.query.offset ?? 0), 0), 100000);
  const sort = typeof req.query.sort === 'string' ? req.query.sort.trim() : 'newest';

  const tenantId = req.user.tenantId;
  const total = await paymentRepo.count(tenantId, { q, from, to, method });
  const rows = await paymentRepo.list(tenantId, { q, from, to, method, limit, offset, sort });
  return res.json({
    total,
    limit,
    offset,
    items: rows.map((r) => ({
      id: Number(r.id),
      invoiceId: Number(r.invoice_id),
      invoiceNo: r.invoice_no,
      memberName: r.full_name,
      memberCode: r.member_code,
      amount: Number(r.amount),
      method: r.method,
      paidAt: r.paid_at
    }))
  });
});

app.get('/payments/summary', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const data = await paymentRepo.summary(req.user.tenantId);
  return res.json(data);
});

app.patch('/payments/:id', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) return res.status(400).json({ error: 'invalid_request' });

  const bodySchema = z.object({
    method: z.enum(['cash', 'card', 'bank', 'online']).optional(),
    paidAt: z.string().optional().nullable()
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });

  const existing = await queryOne(
    `SELECT id
     FROM payments
     WHERE tenant_id = :tenantId AND id = :id
     LIMIT 1`,
    { tenantId, id }
  );
  if (!existing) return res.status(404).json({ error: 'payment_not_found' });

  const updates = [];
  const params = { tenantId, id };
  if (parsed.data.method) {
    updates.push('method = :method');
    params.method = parsed.data.method;
  }
  if (parsed.data.paidAt !== undefined) {
    updates.push('paid_at = :paidAt');
    params.paidAt = parsed.data.paidAt ?? null;
  }
  if (updates.length === 0) return res.json({ ok: true });

  await execute(`UPDATE payments SET ${updates.join(', ')} WHERE tenant_id = :tenantId AND id = :id`, params);
  return res.json({ ok: true });
});

app.delete('/payments/:id', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) return res.status(400).json({ error: 'invalid_request' });

  const pool = await getPool();
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [rows] = await conn.query(
      `SELECT id, invoice_id
       FROM payments
       WHERE tenant_id = :tenantId AND id = :id
       LIMIT 1`,
      { tenantId, id }
    );
    const payment = Array.isArray(rows) && rows.length ? rows[0] : null;
    if (!payment) {
      await conn.rollback();
      return res.status(404).json({ error: 'payment_not_found' });
    }
    const invoiceId = Number(payment.invoice_id);

    await conn.execute('DELETE FROM payments WHERE tenant_id = :tenantId AND id = :id', { tenantId, id });

    const [countRows] = await conn.query(
      'SELECT COUNT(*) AS c FROM payments WHERE tenant_id = :tenantId AND invoice_id = :invoiceId',
      { tenantId, invoiceId }
    );
    const c = Array.isArray(countRows) && countRows[0]?.c != null ? Number(countRows[0].c) : 0;
    if (c === 0) {
      await conn.execute(
        `UPDATE invoices
         SET status = 'unpaid'
         WHERE tenant_id = :tenantId AND id = :invoiceId AND status = 'paid'`,
        { tenantId, invoiceId }
      );
    }

    await conn.commit();
    return res.json({ ok: true });
  } catch (e) {
    await conn.rollback();
    return res.status(500).json({ error: 'payment_delete_failed' });
  } finally {
    conn.release();
  }
});

app.get('/expenses', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const q = typeof req.query.q === 'string' ? req.query.q.trim() : '';
  const from = typeof req.query.from === 'string' ? req.query.from.trim() : '';
  const to = typeof req.query.to === 'string' ? req.query.to.trim() : '';
  const category = typeof req.query.category === 'string' ? req.query.category.trim() : '';
  const limit = Math.min(Math.max(Number(req.query.limit ?? 200), 1), 400);

  const rows = await expenseRepo.list(req.user.tenantId, { q, from, to, category, limit });
  return res.json({
    items: rows.map((r) => ({
      id: Number(r.id),
      category: r.category,
      amount: Number(r.amount),
      expenseDate: r.expense_date,
      notes: r.notes ?? null,
      createdAt: r.created_at
    }))
  });
});

app.get('/expenses/summary', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const data = await expenseRepo.summary(req.user.tenantId);
  return res.json(data);
});

app.post('/expenses', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const bodySchema = z.object({
    category: z.string().min(1).max(191),
    amount: z.number().positive(),
    expenseDate: z.string().min(10).max(10),
    notes: z.string().max(255).optional().nullable()
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });
  const id = await expenseRepo.create(req.user.tenantId, {
    category: parsed.data.category,
    amount: Number(parsed.data.amount),
    expenseDate: parsed.data.expenseDate,
    notes: parsed.data.notes ?? null
  });
  return res.status(201).json({ id });
});

app.patch('/expenses/:id', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) return res.status(400).json({ error: 'invalid_request' });

  const bodySchema = z.object({
    category: z.string().min(1).max(191),
    amount: z.number().positive(),
    expenseDate: z.string().min(10).max(10),
    notes: z.string().max(255).optional().nullable()
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });

  const exists = await queryOne('SELECT id FROM expenses WHERE tenant_id = :tenantId AND id = :id', { tenantId, id });
  if (!exists) return res.status(404).json({ error: 'expense_not_found' });

  await execute(
    `UPDATE expenses
     SET category = :category,
         amount = :amount,
         expense_date = :expenseDate,
         notes = :notes
     WHERE tenant_id = :tenantId AND id = :id`,
    {
      tenantId,
      id,
      category: parsed.data.category,
      amount: Number(parsed.data.amount),
      expenseDate: parsed.data.expenseDate,
      notes: parsed.data.notes ?? null
    }
  );
  return res.json({ ok: true });
});

app.delete('/expenses/:id', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) return res.status(400).json({ error: 'invalid_request' });
  await expenseRepo.remove(req.user.tenantId, id);
  return res.json({ ok: true });
});

app.get('/products', authMiddleware, requireRole('owner', 'admin', 'staff'), async (req, res) => {
  const q = typeof req.query.q === 'string' ? req.query.q.trim() : '';
  const status = typeof req.query.status === 'string' ? req.query.status.trim() : '';
  const lowStock = String(req.query.lowStock ?? '').toLowerCase() === 'true';
  const from = typeof req.query.from === 'string' ? req.query.from.trim() : '';
  const to = typeof req.query.to === 'string' ? req.query.to.trim() : '';
  const limit = Math.min(Math.max(Number(req.query.limit ?? 200), 1), 400);
  const rows = await productRepo.list(req.user.tenantId, { q, status, lowStock, from, to, limit });
  return res.json({
    items: rows.map((r) => ({
      id: Number(r.id),
      name: r.name,
      sku: r.sku ?? null,
      price: Number(r.price ?? 0),
      status: r.status,
      onHand: Number(r.on_hand ?? 0)
    }))
  });
});

app.post('/products', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const bodySchema = z.object({
    name: z.string().min(1).max(191),
    sku: z.string().max(64).optional().nullable(),
    price: z.number().min(0).optional().default(0),
    status: z.enum(['active', 'inactive']).optional().default('active')
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });
  const id = await productRepo.create(req.user.tenantId, {
    name: parsed.data.name,
    sku: parsed.data.sku ?? null,
    price: Number(parsed.data.price ?? 0),
    status: parsed.data.status
  });
  await appendSystemLog({
    tenantId: req.user.tenantId,
    actorUserId: req.user.userId,
    action: 'product_create',
    entityType: 'product',
    entityId: id,
    meta: { name: parsed.data.name, sku: parsed.data.sku ?? null },
    ip: req.ip,
    userAgent: req.headers['user-agent']?.toString() ?? null
  });
  return res.status(201).json({ id });
});

app.patch('/products/:id', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) return res.status(400).json({ error: 'invalid_request' });
  const bodySchema = z.object({
    name: z.string().min(1).max(191),
    sku: z.string().max(64).optional().nullable(),
    price: z.number().min(0).optional().default(0),
    status: z.enum(['active', 'inactive']).optional().default('active')
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });
  const exists = await productRepo.getById(req.user.tenantId, id);
  if (!exists) return res.status(404).json({ error: 'product_not_found' });
  await productRepo.update(req.user.tenantId, id, parsed.data);
  await appendSystemLog({
    tenantId: req.user.tenantId,
    actorUserId: req.user.userId,
    action: 'product_update',
    entityType: 'product',
    entityId: id,
    meta: { name: parsed.data.name, sku: parsed.data.sku ?? null, status: parsed.data.status },
    ip: req.ip,
    userAgent: req.headers['user-agent']?.toString() ?? null
  });
  return res.json({ ok: true });
});

app.delete('/products/:id', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) return res.status(400).json({ error: 'invalid_request' });
  const tenantId = req.user.tenantId;
  const exists = await productRepo.getById(tenantId, id);
  if (!exists) return res.status(404).json({ error: 'product_not_found' });
  await execute(
    `UPDATE products SET status = 'inactive' WHERE tenant_id = :tenantId AND id = :id`,
    { tenantId, id }
  );
  await appendSystemLog({
    tenantId: req.user.tenantId,
    actorUserId: req.user.userId,
    action: 'product_deactivate',
    entityType: 'product',
    entityId: id,
    ip: req.ip,
    userAgent: req.headers['user-agent']?.toString() ?? null
  });
  return res.json({ ok: true });
});

app.post('/products/sell', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const bodySchema = z.object({
    productId: z.number().int().positive(),
    memberId: z.number().int().positive(),
    qty: z.number().int().positive(),
    method: z.enum(['cash', 'card', 'bank', 'online']).optional().default('cash'),
    unitPrice: z.number().min(0).optional().nullable()
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });

  const tenantId = req.user.tenantId;
  const connPool = await getPool();
  const conn = await connPool.getConnection();
  try {
    await conn.beginTransaction();

    const [productRows] = await conn.query(
      `SELECT id, name, price, status
       FROM products
       WHERE tenant_id = :tenantId AND id = :id
       LIMIT 1
       FOR UPDATE`,
      { tenantId, id: parsed.data.productId }
    );
    const product = Array.isArray(productRows) && productRows.length ? productRows[0] : null;
    if (!product) {
      await conn.rollback();
      return res.status(404).json({ error: 'product_not_found' });
    }
    if (product.status !== 'active') {
      await conn.rollback();
      return res.status(400).json({ error: 'product_inactive' });
    }

    const [memberRows] = await conn.query(
      `SELECT id, status
       FROM members
       WHERE tenant_id = :tenantId AND id = :id
       LIMIT 1`,
      { tenantId, id: parsed.data.memberId }
    );
    const member = Array.isArray(memberRows) && memberRows.length ? memberRows[0] : null;
    if (!member) {
      await conn.rollback();
      return res.status(404).json({ error: 'member_not_found' });
    }
    if (member.status !== 'active') {
      await conn.rollback();
      return res.status(400).json({ error: 'member_inactive' });
    }

    const [stockRows] = await conn.query(
      `SELECT COALESCE(SUM(CASE WHEN movement_type = 'in' THEN qty ELSE -qty END), 0) AS on_hand
       FROM stock_movements
       WHERE tenant_id = :tenantId AND product_id = :productId`,
      { tenantId, productId: parsed.data.productId }
    );
    const onHand = Number((Array.isArray(stockRows) && stockRows.length ? stockRows[0].on_hand : 0) ?? 0);
    if (onHand < parsed.data.qty) {
      await conn.rollback();
      return res.status(400).json({ error: 'insufficient_stock', onHand });
    }

    const unitPrice = Number(parsed.data.unitPrice ?? product.price ?? 0);
    const subtotal = Number((unitPrice * Number(parsed.data.qty)).toFixed(2));
    const invoiceNo = newInvoiceNo();
    const dueDate = toDateOnly(new Date());
    const paidAt = toMysqlDateTime(new Date());

    const [invResult] = await conn.execute(
      `INSERT INTO invoices (tenant_id, member_id, invoice_no, subtotal, discount, tax, total, status, due_date)
       VALUES (:tenantId, :memberId, :invoiceNo, :subtotal, 0, 0, :total, 'paid', :dueDate)`,
      {
        tenantId,
        memberId: parsed.data.memberId,
        invoiceNo,
        subtotal,
        total: subtotal,
        dueDate
      }
    );
    const invoiceId = Number(invResult.insertId);

    await conn.execute(
      `INSERT INTO payments (tenant_id, invoice_id, amount, method, paid_at)
       VALUES (:tenantId, :invoiceId, :amount, :method, :paidAt)`,
      {
        tenantId,
        invoiceId,
        amount: subtotal,
        method: parsed.data.method,
        paidAt
      }
    );

    await conn.execute(
      `INSERT INTO stock_movements (tenant_id, product_id, qty, movement_type, reason)
       VALUES (:tenantId, :productId, :qty, 'out', :reason)`,
      {
        tenantId,
        productId: parsed.data.productId,
        qty: parsed.data.qty,
        reason: `sale:${invoiceNo}`
      }
    );

    await appendSystemLog(
      {
        tenantId,
        actorUserId: req.user.userId,
        action: 'product_sell',
        entityType: 'product',
        entityId: parsed.data.productId,
        meta: {
          invoiceId,
          invoiceNo,
          memberId: parsed.data.memberId,
          qty: parsed.data.qty,
          unitPrice,
          total: subtotal
        },
        ip: req.ip,
        userAgent: req.headers['user-agent']?.toString() ?? null
      },
      conn
    );

    await triggerAutomation(
      {
        tenantId,
        event: 'payment_received',
        memberId: parsed.data.memberId,
        invoiceId,
        payload: { invoiceNo, amount: subtotal, method: parsed.data.method, source: 'inventory_sell' }
      },
      conn
    );

    await conn.commit();
    maybeLogLowStock({ tenantId, actorUserId: req.user.userId, productId: parsed.data.productId }).then(
      () => {},
      () => {}
    );
    return res.status(201).json({
      ok: true,
      invoiceId,
      invoiceNo,
      unitPrice,
      qty: parsed.data.qty,
      total: subtotal,
      onHandBefore: onHand,
      onHandAfter: onHand - parsed.data.qty
    });
  } catch {
    await conn.rollback();
    return res.status(400).json({ error: 'product_sale_failed' });
  } finally {
    conn.release();
  }
});

app.post('/stock/move', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const bodySchema = z.object({
    productId: z.number().int().positive(),
    qty: z.number().int().positive(),
    movementType: z.enum(['in', 'out']),
    reason: z.string().max(191).optional().nullable()
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });
  const product = await productRepo.getById(req.user.tenantId, parsed.data.productId);
  if (!product) return res.status(404).json({ error: 'product_not_found' });
  const id = await stockRepo.move(req.user.tenantId, {
    productId: parsed.data.productId,
    qty: Number(parsed.data.qty),
    movementType: parsed.data.movementType,
    reason: parsed.data.reason ?? null
  });
  await appendSystemLog({
    tenantId: req.user.tenantId,
    actorUserId: req.user.userId,
    action: 'stock_move',
    entityType: 'product',
    entityId: parsed.data.productId,
    meta: { qty: parsed.data.qty, movementType: parsed.data.movementType, reason: parsed.data.reason ?? null },
    ip: req.ip,
    userAgent: req.headers['user-agent']?.toString() ?? null
  });
  maybeLogLowStock({ tenantId: req.user.tenantId, actorUserId: req.user.userId, productId: parsed.data.productId }).then(
    () => {},
    () => {}
  );
  return res.status(201).json({ id });
});

app.get('/stock/movements', authMiddleware, async (req, res) => {
  const productId = req.query.productId ? Number(req.query.productId) : null;
  const limit = Math.min(Math.max(Number(req.query.limit ?? 200), 1), 400);
  const rows = await stockRepo.listMovements(req.user.tenantId, {
    productId: Number.isFinite(productId) && productId > 0 ? productId : null,
    limit
  });
  return res.json({
    items: rows.map((r) => ({
      id: Number(r.id),
      productId: Number(r.product_id),
      productName: r.product_name,
      qty: Number(r.qty),
      movementType: r.movement_type,
      reason: r.reason ?? null,
      createdAt: r.created_at
    }))
  });
});

app.get('/staff', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const rows = await staffRepo.listUsers(req.user.tenantId, 200);
  return res.json({
    items: rows.map((u) => ({
      id: Number(u.id),
      email: u.email,
      fullName: u.full_name,
      status: u.status,
      roles: u.roles ?? [],
      createdAt: u.created_at
    }))
  });
});

app.post('/staff', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const bodySchema = z.object({
    email: z.string().email().max(191),
    fullName: z.string().min(2).max(191),
    password: z.string().min(6).max(191),
    roles: z.array(z.enum(['owner', 'admin', 'staff', 'receptionist', 'super_admin']))
      .min(1)
      .max(3)
      .optional()
      .default(['staff'])
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });
  try {
    const userId = await staffRepo.createUser(req.user.tenantId, parsed.data);
    return res.status(201).json({ id: userId });
  } catch {
    return res.status(400).json({ error: 'create_staff_failed' });
  }
});

app.put('/staff/:id/roles', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) return res.status(400).json({ error: 'invalid_request' });
  const bodySchema = z.object({
    roles: z.array(z.enum(['owner', 'admin', 'staff', 'receptionist', 'super_admin'])).min(1).max(3)
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });
  const result = await staffRepo.setUserRoles(req.user.tenantId, id, parsed.data.roles);
  if (!result.ok) return res.status(404).json({ error: result.error });
  return res.json({ ok: true });
});

app.patch('/staff/:id/status', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) return res.status(400).json({ error: 'invalid_request' });

  const bodySchema = z.object({
    status: z.enum(['active', 'disabled'])
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });

  const exists = await queryOne(
    'SELECT id FROM users WHERE tenant_id = :tenantId AND id = :id',
    { tenantId, id }
  );
  if (!exists) return res.status(404).json({ error: 'user_not_found' });

  await execute(
    'UPDATE users SET status = :status WHERE tenant_id = :tenantId AND id = :id',
    { tenantId, id, status: parsed.data.status }
  );
  return res.json({ ok: true });
});

app.get('/dashboard/summary', authMiddleware, async (req, res) => {
  const tenantId = req.user.tenantId;
  const canSeeRevenue = (req.user.roles ?? []).some((r) => r === 'owner' || r === 'admin' || r === 'super_admin');
  const membersTotal = await queryOne(
    'SELECT COUNT(*) AS c FROM members WHERE tenant_id = :tenantId',
    { tenantId }
  );
  const activeMembers = await queryOne(
    "SELECT COUNT(*) AS c FROM members WHERE tenant_id = :tenantId AND status = 'active'",
    { tenantId }
  );
  const plansTotal = await queryOne(
    'SELECT COUNT(*) AS c FROM membership_plans WHERE tenant_id = :tenantId',
    { tenantId }
  );
  const todayCheckins = await queryOne(
    'SELECT COUNT(*) AS c FROM attendance_logs WHERE tenant_id = :tenantId AND DATE(checked_in_at) = CURDATE()',
    { tenantId }
  );
  const unpaidInvoices = await queryOne(
    "SELECT COUNT(*) AS c FROM invoices WHERE tenant_id = :tenantId AND status = 'unpaid'",
    { tenantId }
  );
  const unpaidAmount = await queryOne(
    "SELECT COALESCE(SUM(total), 0) AS s FROM invoices WHERE tenant_id = :tenantId AND status = 'unpaid'",
    { tenantId }
  );
  const revenueLast30Days = await queryOne(
    "SELECT COALESCE(SUM(total), 0) AS s FROM invoices WHERE tenant_id = :tenantId AND status = 'paid' AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)",
    { tenantId }
  );
  const revenueTotal = await queryOne(
    "SELECT COALESCE(SUM(total), 0) AS s FROM invoices WHERE tenant_id = :tenantId AND status = 'paid'",
    { tenantId }
  );

  const membershipCounts = await queryOne(
    `SELECT
        SUM(CASE WHEN x.end_date IS NOT NULL AND x.end_date >= CURDATE() THEN 1 ELSE 0 END) AS active_c,
        SUM(CASE WHEN x.end_date IS NULL OR x.end_date < CURDATE() THEN 1 ELSE 0 END) AS expired_c
     FROM (
       SELECT m.id AS member_id,
              (SELECT MAX(s.end_date)
               FROM subscriptions s
               WHERE s.tenant_id = m.tenant_id AND s.member_id = m.id AND s.status = 'active') AS end_date
       FROM members m
       WHERE m.tenant_id = :tenantId AND m.status = 'active'
     ) x`,
    { tenantId }
  );

  const frozenMembers = await queryOne(
    `SELECT COUNT(*) AS c
     FROM members
     WHERE tenant_id = :tenantId
       AND frozen_until IS NOT NULL
       AND frozen_until >= CURDATE()`,
    { tenantId }
  );

  const expiringMembers = await queryMany(
    `SELECT m.id AS member_id, m.member_code, m.full_name, m.frozen_until, s.end_date, DATEDIFF(s.end_date, CURDATE()) AS days_left
     FROM subscriptions s
     INNER JOIN members m ON m.id = s.member_id
     WHERE s.tenant_id = :tenantId
       AND s.status = 'active'
       AND m.status = 'active'
       AND s.end_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 3 DAY)
     ORDER BY s.end_date ASC
     LIMIT 10`,
    { tenantId }
  );

  const revenueRows = await queryMany(
    `SELECT DATE(paid_at) AS d, COALESCE(SUM(amount), 0) AS s
     FROM payments
     WHERE tenant_id = :tenantId AND paid_at >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)
     GROUP BY DATE(paid_at)
     ORDER BY d ASC`,
    { tenantId }
  );
  const revenueMap = new Map(revenueRows.map((r) => [toDateOnly(new Date(r.d)), Number(r.s ?? 0)]));
  const revenue7d = [];
  for (let i = 6; i >= 0; i -= 1) {
    const date = addDays(new Date(), -i);
    const key = toDateOnly(date);
    revenue7d.push({ date: key, amount: Number(revenueMap.get(key) ?? 0) });
  }

  return res.json({
    membersTotal: Number(membersTotal?.c ?? 0),
    activeMembers: Number(activeMembers?.c ?? 0),
    membershipActiveMembers: Number(membershipCounts?.active_c ?? 0),
    membershipExpiredMembers: Number(membershipCounts?.expired_c ?? 0),
    frozenMembers: Number(frozenMembers?.c ?? 0),
    plansTotal: Number(plansTotal?.c ?? 0),
    todayCheckins: Number(todayCheckins?.c ?? 0),
    unpaidInvoices: Number(unpaidInvoices?.c ?? 0),
    unpaidAmount: canSeeRevenue ? Number(unpaidAmount?.s ?? 0) : 0,
    revenueLast30Days: canSeeRevenue ? Number(revenueLast30Days?.s ?? 0) : 0,
    revenueTotal: canSeeRevenue ? Number(revenueTotal?.s ?? 0) : 0,
    revenue7d: canSeeRevenue ? revenue7d : revenue7d.map((r) => ({ date: r.date, amount: 0 })),
    expiringMembers: expiringMembers.map((r) => ({
      memberId: Number(r.member_id),
      memberCode: r.member_code,
      fullName: r.full_name,
      endDate: r.end_date,
      daysLeft: Number(r.days_left),
      frozenUntil: r.frozen_until ?? null
    }))
  });
});

app.get('/dashboard/activity', authMiddleware, async (req, res) => {
  const tenantId = req.user.tenantId;
  const canSeeRevenue = (req.user.roles ?? []).some((r) => r === 'owner' || r === 'admin' || r === 'super_admin');
  const limit = Math.min(Math.max(Number(req.query.limit ?? 20), 1), 50);

  const checkins = await queryMany(
    `SELECT a.id, a.checked_in_at, m.id AS member_id, m.member_code, m.full_name
     FROM attendance_logs a
     INNER JOIN members m ON m.id = a.member_id
     WHERE a.tenant_id = :tenantId
     ORDER BY a.checked_in_at DESC
     LIMIT :limit`,
    { tenantId, limit }
  );

  const payments = canSeeRevenue
    ? await queryMany(
        `SELECT p.id, p.amount, p.method, p.paid_at, i.invoice_no, m.id AS member_id, m.member_code, m.full_name
         FROM payments p
         INNER JOIN invoices i ON i.id = p.invoice_id
         INNER JOIN members m ON m.id = i.member_id
         WHERE p.tenant_id = :tenantId
         ORDER BY p.paid_at DESC
         LIMIT :limit`,
        { tenantId, limit }
      )
    : [];

  const stockAlerts = await queryMany(
    `SELECT id, created_at, entity_id, meta_json
     FROM system_logs
     WHERE tenant_id = :tenantId
       AND action = 'stock_low'
     ORDER BY id DESC
     LIMIT :limit`,
    { tenantId, limit }
  );

  const toIso = (v) => {
    const d = new Date(v);
    if (Number.isNaN(d.getTime())) return String(v ?? '');
    return d.toISOString();
  };

  const items = [
    ...checkins.map((r) => ({
      id: `checkin_${r.id}`,
      type: 'checkin',
      at: toIso(r.checked_in_at),
      title: `${r.full_name ?? ''} (${r.member_code ?? ''})`,
      subtitle: `Checked in • ${fmtDateTimeShort(r.checked_in_at)}`,
      memberId: Number(r.member_id),
      amount: null,
      method: null,
      invoiceNo: null
    })),
    ...payments.map((r) => ({
      id: `payment_${r.id}`,
      type: 'payment',
      at: toIso(r.paid_at),
      title: `${r.full_name ?? ''} (${r.member_code ?? ''})`,
      subtitle: `Payment • ${r.invoice_no ?? ''} • ${String(r.method ?? '').toUpperCase()} • ${fmtDateTimeShort(r.paid_at)}`,
      memberId: Number(r.member_id),
      amount: Number(r.amount ?? 0),
      method: r.method ?? null,
      invoiceNo: r.invoice_no ?? null
    })),
    ...stockAlerts.map((r) => {
      let meta = null;
      try {
        meta = r.meta_json ? JSON.parse(String(r.meta_json)) : null;
      } catch {
        meta = null;
      }
      const name = meta?.productName ?? meta?.product_name ?? 'Product';
      const onHand = meta?.onHand ?? meta?.on_hand ?? null;
      const threshold = meta?.threshold ?? null;
      const subtitle = onHand == null
        ? 'Low stock • Reorder recommended'
        : `Low stock • On hand: ${onHand}${threshold != null ? ` (Threshold: ${threshold})` : ''}`;
      return {
        id: `stock_low_${r.id}`,
        type: 'alert',
        at: toIso(r.created_at),
        title: `Low stock: ${name}`,
        subtitle,
        memberId: null,
        amount: null,
        method: null,
        invoiceNo: null
      };
    }),
  ];

  items.sort((a, b) => String(b.at ?? '').localeCompare(String(a.at ?? '')));
  return res.json({ items: items.slice(0, limit) });
});

app.get('/search', authMiddleware, async (req, res) => {
  const tenantId = req.user.tenantId;
  const rawQ = typeof req.query.q === 'string' ? req.query.q.trim() : '';
  const limit = Math.min(Math.max(Number(req.query.limit ?? 8), 1), 20);

  if (rawQ.length < 2) {
    return res.json({ members: [], leads: [], invoices: [] });
  }

  const q = `%${rawQ}%`;
  const roles = (req.user.roles ?? []).map((r) => String(r));
  const canSeeRevenue = roles.some((r) => r === 'owner' || r === 'admin' || r === 'super_admin');
  const canSeeLeads = roles.some((r) => r === 'owner' || r === 'admin' || r === 'super_admin' || r === 'staff' || r === 'receptionist');

  const members = await queryMany(
    `SELECT id, member_code, full_name, phone
     FROM members
     WHERE tenant_id = :tenantId
       AND (member_code LIKE :q OR full_name LIKE :q OR phone LIKE :q)
     ORDER BY id DESC
     LIMIT :limit`,
    { tenantId, q, limit }
  );

  const leads = canSeeLeads
    ? await queryMany(
        `SELECT id, full_name, phone, status, source, interest
         FROM leads
         WHERE tenant_id = :tenantId
           AND (full_name LIKE :q OR phone LIKE :q OR source LIKE :q OR interest LIKE :q)
         ORDER BY updated_at DESC
         LIMIT :limit`,
        { tenantId, q, limit }
      )
    : [];

  const invoices = canSeeRevenue
    ? await queryMany(
        `SELECT i.id, i.invoice_no, i.total, i.status, i.created_at,
                m.full_name, m.member_code, m.phone
         FROM invoices i
         INNER JOIN members m ON m.id = i.member_id
         WHERE i.tenant_id = :tenantId
           AND (i.invoice_no LIKE :q OR m.full_name LIKE :q OR m.member_code LIKE :q OR m.phone LIKE :q)
         ORDER BY i.id DESC
         LIMIT :limit`,
        { tenantId, q, limit }
      )
    : [];

  return res.json({
    members: members.map((r) => ({
      id: Number(r.id),
      memberCode: r.member_code,
      fullName: r.full_name,
      phone: r.phone ?? null
    })),
    leads: leads.map((r) => ({
      id: Number(r.id),
      fullName: r.full_name,
      phone: r.phone ?? null,
      status: r.status,
      source: r.source ?? null,
      interest: r.interest ?? null
    })),
    invoices: invoices.map((r) => ({
      id: Number(r.id),
      invoiceNo: r.invoice_no,
      total: Number(r.total ?? 0),
      status: r.status,
      createdAt: r.created_at,
      memberName: r.full_name,
      memberCode: r.member_code,
      phone: r.phone ?? null
    }))
  });
});

app.get('/leads', authMiddleware, requireRole('owner', 'admin', 'staff', 'receptionist'), async (req, res) => {
  const q = typeof req.query.q === 'string' ? req.query.q.trim() : '';
  const status = typeof req.query.status === 'string' ? req.query.status.trim() : '';
  const limit = Math.min(Math.max(Number(req.query.limit ?? 200), 1), 400);
  const rows = await leadRepo.list(req.user.tenantId, { q, status, limit });
  return res.json({
    items: rows.map((r) => ({
      id: Number(r.id),
      fullName: r.full_name,
      phone: r.phone ?? null,
      source: r.source ?? null,
      interest: r.interest ?? null,
      nextContactDate: r.next_contact_date ?? null,
      status: r.status,
      notes: r.notes ?? null,
      createdAt: r.created_at,
      updatedAt: r.updated_at
    }))
  });
});

app.post('/leads', authMiddleware, requireRole('owner', 'admin', 'staff', 'receptionist'), async (req, res) => {
  const bodySchema = z.object({
    fullName: z.string().min(2).max(191),
    phone: z.string().max(32).optional().nullable(),
    source: z.string().max(64).optional().nullable(),
    interest: z.string().max(191).optional().nullable(),
    nextContactDate: z.string().min(10).max(10).optional().nullable(),
    status: z.enum(['new', 'trial', 'converted', 'lost']).optional().default('new'),
    notes: z.string().max(255).optional().nullable()
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });
  const id = await leadRepo.create(req.user.tenantId, {
    fullName: parsed.data.fullName,
    phone: parsed.data.phone ?? null,
    source: parsed.data.source ?? null,
    interest: parsed.data.interest ?? null,
    nextContactDate: parsed.data.nextContactDate ?? null,
    status: parsed.data.status,
    notes: parsed.data.notes ?? null
  });
  await appendSystemLog({
    tenantId: req.user.tenantId,
    actorUserId: req.user.userId,
    action: 'lead_create',
    entityType: 'lead',
    entityId: id,
    meta: { fullName: parsed.data.fullName, status: parsed.data.status },
    ip: req.ip,
    userAgent: req.headers['user-agent']?.toString() ?? null
  });
  return res.status(201).json({ id });
});

app.patch('/leads/:id', authMiddleware, requireRole('owner', 'admin', 'staff', 'receptionist'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) return res.status(400).json({ error: 'invalid_request' });
  const bodySchema = z.object({
    fullName: z.string().min(2).max(191),
    phone: z.string().max(32).optional().nullable(),
    source: z.string().max(64).optional().nullable(),
    interest: z.string().max(191).optional().nullable(),
    nextContactDate: z.string().min(10).max(10).optional().nullable(),
    status: z.enum(['new', 'trial', 'converted', 'lost']).optional().default('new'),
    notes: z.string().max(255).optional().nullable()
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });

  const exists = await queryOne('SELECT id FROM leads WHERE tenant_id = :tenantId AND id = :id', { tenantId, id });
  if (!exists) return res.status(404).json({ error: 'lead_not_found' });

  await leadRepo.update(tenantId, id, {
    fullName: parsed.data.fullName,
    phone: parsed.data.phone ?? null,
    source: parsed.data.source ?? null,
    interest: parsed.data.interest ?? null,
    nextContactDate: parsed.data.nextContactDate ?? null,
    status: parsed.data.status,
    notes: parsed.data.notes ?? null
  });
  await appendSystemLog({
    tenantId: req.user.tenantId,
    actorUserId: req.user.userId,
    action: 'lead_update',
    entityType: 'lead',
    entityId: id,
    meta: { status: parsed.data.status },
    ip: req.ip,
    userAgent: req.headers['user-agent']?.toString() ?? null
  });
  return res.json({ ok: true });
});

app.post('/leads/:id/convert', authMiddleware, requireRole('owner', 'admin', 'staff', 'receptionist'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) return res.status(400).json({ error: 'invalid_request' });

  const exists = await queryOne('SELECT id FROM leads WHERE tenant_id = :tenantId AND id = :id', { tenantId, id });
  if (!exists) return res.status(404).json({ error: 'lead_not_found' });

  await execute('UPDATE leads SET status = :status WHERE tenant_id = :tenantId AND id = :id', {
    tenantId,
    id,
    status: 'converted'
  });
  await appendSystemLog({
    tenantId: req.user.tenantId,
    actorUserId: req.user.userId,
    action: 'lead_convert',
    entityType: 'lead',
    entityId: id,
    meta: { status: 'converted' },
    ip: req.ip,
    userAgent: req.headers['user-agent']?.toString() ?? null
  });
  return res.json({ ok: true });
});

app.delete('/leads/:id', authMiddleware, requireRole('owner', 'admin', 'staff', 'receptionist'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) return res.status(400).json({ error: 'invalid_request' });
  await leadRepo.remove(tenantId, id);
  await appendSystemLog({
    tenantId: req.user.tenantId,
    actorUserId: req.user.userId,
    action: 'lead_delete',
    entityType: 'lead',
    entityId: id,
    meta: null,
    ip: req.ip,
    userAgent: req.headers['user-agent']?.toString() ?? null
  });
  return res.json({ ok: true });
});

app.get('/members', authMiddleware, async (req, res) => {
  const q = typeof req.query.q === 'string' ? req.query.q.trim() : '';
  const status = typeof req.query.status === 'string' ? req.query.status : '';
  const from = typeof req.query.from === 'string' ? req.query.from.trim() : '';
  const to = typeof req.query.to === 'string' ? req.query.to.trim() : '';
  const limit = Math.min(Math.max(Number(req.query.limit ?? 50), 1), 200);

  const where = ['m.tenant_id = :tenantId'];
  const params = { tenantId: req.user.tenantId, limit };
  if (q.length) {
    where.push('(m.member_code LIKE :q OR m.full_name LIKE :q OR m.phone LIKE :q OR m.email LIKE :q)');
    params.q = `%${q}%`;
  }
  if (status === 'active' || status === 'expired' || status === 'inactive') {
    where.push('m.status = :status');
    params.status = status;
  }
  if (from.length) {
    where.push('m.join_date >= :from');
    params.from = from;
  }
  if (to.length) {
    where.push('m.join_date <= :to');
    params.to = to;
  }

  const rows = await queryMany(
    `SELECT
       m.id,
       m.member_code,
       m.full_name,
       m.phone,
       m.email,
       m.status,
       m.join_date,
       m.frozen_until,
       (SELECT s.end_date
        FROM subscriptions s
        WHERE s.tenant_id = m.tenant_id AND s.member_id = m.id AND s.status = 'active'
        ORDER BY s.end_date DESC
        LIMIT 1) AS membership_end_date,
       (SELECT p.name
        FROM subscriptions s
        INNER JOIN membership_plans p ON p.id = s.plan_id
        WHERE s.tenant_id = m.tenant_id AND s.member_id = m.id AND s.status = 'active'
        ORDER BY s.end_date DESC
        LIMIT 1) AS membership_plan_name,
       b.name AS branch_name
     FROM members m
     LEFT JOIN branches b ON b.id = m.branch_id
     WHERE ${where.join(' AND ')}
     ORDER BY m.id DESC
     LIMIT :limit`,
    params
  );
  return res.json({ items: rows });
});

app.get('/members/:id', authMiddleware, async (req, res) => {
  const tenantId = req.user.tenantId;
  const memberId = Number(req.params.id);
  if (!Number.isFinite(memberId) || memberId <= 0) return res.status(400).json({ error: 'invalid_request' });

  const row = await queryOne(
    `SELECT id, member_code, full_name, phone, email, status, join_date, notes, frozen_until, frozen_reason, frozen_at, created_at
     FROM members
     WHERE tenant_id = :tenantId AND id = :id`,
    { tenantId, id: memberId }
  );
  if (!row) return res.status(404).json({ error: 'member_not_found' });
  return res.json({
    id: Number(row.id),
    memberCode: row.member_code,
    fullName: row.full_name,
    phone: row.phone ?? null,
    email: row.email ?? null,
    status: row.status,
    joinDate: row.join_date,
    notes: row.notes ?? null,
    frozenUntil: row.frozen_until ?? null,
    frozenReason: row.frozen_reason ?? null,
    frozenAt: row.frozen_at ?? null,
    createdAt: row.created_at
  });
});

app.patch('/members/:id', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const memberId = Number(req.params.id);
  if (!Number.isFinite(memberId) || memberId <= 0) return res.status(400).json({ error: 'invalid_request' });

  const bodySchema = z.object({
    fullName: z.string().min(2).max(191),
    phone: z.string().max(32).optional().nullable(),
    email: z.string().email().max(191).optional().nullable(),
    status: z.enum(['active', 'expired', 'inactive']).optional().default('active'),
    notes: z.string().max(255).optional().nullable()
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });

  const exists = await queryOne(
    'SELECT id FROM members WHERE tenant_id = :tenantId AND id = :id',
    { tenantId, id: memberId }
  );
  if (!exists) return res.status(404).json({ error: 'member_not_found' });

  await execute(
    `UPDATE members
     SET full_name = :fullName,
         phone = :phone,
         email = :email,
         status = :status,
         notes = :notes
     WHERE tenant_id = :tenantId AND id = :id`,
    {
      tenantId,
      id: memberId,
      fullName: parsed.data.fullName,
      phone: parsed.data.phone ?? null,
      email: parsed.data.email ?? null,
      status: parsed.data.status,
      notes: parsed.data.notes ?? null
    }
  );
  return res.json({ ok: true });
});

app.post('/members/:id/change-membership', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const memberId = Number(req.params.id);
  if (!Number.isFinite(memberId) || memberId <= 0) return res.status(400).json({ error: 'invalid_request' });

  const bodySchema = z.object({
    planId: z.number().int().positive(),
    startDate: z.string().optional().nullable(),
    createInvoice: z.boolean().optional().default(true)
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });

  const member = await queryOne('SELECT id, status FROM members WHERE tenant_id = :tenantId AND id = :id', {
    tenantId,
    id: memberId
  });
  if (!member) return res.status(404).json({ error: 'member_not_found' });

  const plan = await queryOne(
    `SELECT id, name, duration_days, price, admission_fee, status
     FROM membership_plans
     WHERE tenant_id = :tenantId AND id = :id`,
    { tenantId, id: parsed.data.planId }
  );
  if (!plan || plan.status !== 'active') return res.status(400).json({ error: 'invalid_plan' });

  const startDateRaw = parsed.data.startDate?.length ? parsed.data.startDate : toDateOnly(new Date());
  const startDate = new Date(`${startDateRaw}T00:00:00`);
  const endDate = addDays(startDate, Number(plan.duration_days));

  const connPool = await getPool();
  const conn = await connPool.getConnection();
  try {
    await conn.beginTransaction();

    await conn.execute(
      `UPDATE subscriptions
       SET status = 'cancelled'
       WHERE tenant_id = :tenantId AND member_id = :memberId AND status = 'active'`,
      { tenantId, memberId }
    );

    const [subResult] = await conn.execute(
      `INSERT INTO subscriptions (tenant_id, member_id, plan_id, start_date, end_date, status)
       VALUES (:tenantId, :memberId, :planId, :startDate, :endDate, 'active')`,
      {
        tenantId,
        memberId,
        planId: Number(plan.id),
        startDate: toDateOnly(startDate),
        endDate: toDateOnly(endDate)
      }
    );
    const subscriptionId = Number(subResult.insertId);

    if (String(member.status) !== 'inactive') {
      await conn.execute(
        `UPDATE members SET status = 'active' WHERE tenant_id = :tenantId AND id = :id`,
        { tenantId, id: memberId }
      );
    }

    let invoiceId = null;
    let invoiceNo = null;
    if (parsed.data.createInvoice) {
      const subtotal = Number(plan.price) + Number(plan.admission_fee ?? 0);
      const total = Number(subtotal.toFixed(2));
      invoiceNo = newInvoiceNo();
      const [invResult] = await conn.execute(
        `INSERT INTO invoices (tenant_id, member_id, subscription_id, invoice_no, subtotal, discount, tax, total, status, due_date)
         VALUES (:tenantId, :memberId, :subscriptionId, :invoiceNo, :subtotal, 0, 0, :total, 'unpaid', :dueDate)`,
        {
          tenantId,
          memberId,
          subscriptionId,
          invoiceNo,
          subtotal,
          total,
          dueDate: toDateOnly(startDate)
        }
      );
      invoiceId = Number(invResult.insertId);
    }

    await conn.commit();

    await triggerAutomation(
      {
        tenantId,
        event: 'membership_changed',
        memberId,
        invoiceId,
        payload: { planId: Number(plan.id), planName: plan.name, startDate: toDateOnly(startDate), endDate: toDateOnly(endDate) }
      },
      conn
    );

    return res.json({
      ok: true,
      subscriptionId,
      startDate: toDateOnly(startDate),
      endDate: toDateOnly(endDate),
      invoiceId,
      invoiceNo
    });
  } catch {
    await conn.rollback();
    return res.status(400).json({ error: 'membership_change_failed' });
  } finally {
    conn.release();
  }
});

app.post('/members/:id/remove-membership', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const memberId = Number(req.params.id);
  if (!Number.isFinite(memberId) || memberId <= 0) return res.status(400).json({ error: 'invalid_request' });

  const exists = await queryOne('SELECT id FROM members WHERE tenant_id = :tenantId AND id = :id', {
    tenantId,
    id: memberId
  });
  if (!exists) return res.status(404).json({ error: 'member_not_found' });

  await execute(
    `UPDATE subscriptions
     SET status = 'cancelled'
     WHERE tenant_id = :tenantId AND member_id = :memberId`,
    { tenantId, memberId }
  );

  const remainingActive = await queryOne(
    "SELECT COUNT(*) AS c FROM subscriptions WHERE tenant_id = :tenantId AND member_id = :memberId AND status = 'active'",
    { tenantId, memberId }
  );
  return res.json({ ok: true, remainingActiveSubscriptions: Number(remainingActive?.c ?? 0) });
});

app.post('/members/:id/freeze', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const memberId = Number(req.params.id);
  if (!Number.isFinite(memberId) || memberId <= 0) return res.status(400).json({ error: 'invalid_request' });

  const bodySchema = z.object({
    untilDate: z.string().min(10).max(10),
    reason: z.string().max(191).optional().nullable()
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });

  const exists = await queryOne('SELECT id FROM members WHERE tenant_id = :tenantId AND id = :id', {
    tenantId,
    id: memberId
  });
  if (!exists) return res.status(404).json({ error: 'member_not_found' });

  const today = toDateOnly(new Date());
  if (String(parsed.data.untilDate) < today) return res.status(400).json({ error: 'invalid_until_date' });

  await execute(
    `UPDATE members
     SET frozen_until = :untilDate, frozen_reason = :reason, frozen_at = NOW()
     WHERE tenant_id = :tenantId AND id = :id`,
    {
      tenantId,
      id: memberId,
      untilDate: parsed.data.untilDate,
      reason: parsed.data.reason?.trim()?.length ? parsed.data.reason.trim() : null
    }
  );
  return res.json({ ok: true, frozenUntil: parsed.data.untilDate });
});

app.post('/members/:id/unfreeze', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const memberId = Number(req.params.id);
  if (!Number.isFinite(memberId) || memberId <= 0) return res.status(400).json({ error: 'invalid_request' });

  const exists = await queryOne('SELECT id FROM members WHERE tenant_id = :tenantId AND id = :id', {
    tenantId,
    id: memberId
  });
  if (!exists) return res.status(404).json({ error: 'member_not_found' });

  await execute(
    `UPDATE members
     SET frozen_until = NULL, frozen_reason = NULL, frozen_at = NULL
     WHERE tenant_id = :tenantId AND id = :id`,
    { tenantId, id: memberId }
  );
  return res.json({ ok: true });
});

app.get('/members/expiring', authMiddleware, requireRole('owner', 'admin', 'staff', 'receptionist'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const days = Math.min(Math.max(Number(req.query.days ?? 7), 1), 60);
  const untilDate = toDateOnly(addDays(new Date(), days));

  const rows = await queryMany(
    `SELECT m.id AS member_id, m.member_code, m.full_name, m.phone, m.frozen_until,
            x.end_date, DATEDIFF(x.end_date, CURDATE()) AS days_left, p.name AS plan_name
     FROM members m
     INNER JOIN (
       SELECT s1.member_id, s1.end_date, s1.plan_id
       FROM subscriptions s1
       INNER JOIN (
         SELECT member_id, MAX(end_date) AS max_end
         FROM subscriptions
         WHERE tenant_id = :tenantId
         GROUP BY member_id
       ) latest ON latest.member_id = s1.member_id AND latest.max_end = s1.end_date
       WHERE s1.tenant_id = :tenantId
     ) x ON x.member_id = m.id
     INNER JOIN membership_plans p ON p.id = x.plan_id
     WHERE m.tenant_id = :tenantId
       AND m.status = 'active'
       AND x.end_date BETWEEN CURDATE() AND :untilDate
     ORDER BY x.end_date ASC
     LIMIT 200`,
    { tenantId, untilDate }
  );

  return res.json({
    items: rows.map((r) => ({
      memberId: Number(r.member_id),
      memberCode: r.member_code,
      fullName: r.full_name,
      phone: r.phone ?? null,
      planName: r.plan_name,
      endDate: r.end_date,
      daysLeft: Number(r.days_left),
      frozenUntil: r.frozen_until ?? null
    }))
  });
});

app.delete('/members/:id', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const memberId = Number(req.params.id);
  if (!Number.isFinite(memberId) || memberId <= 0) return res.status(400).json({ error: 'invalid_request' });

  const exists = await queryOne(
    'SELECT id FROM members WHERE tenant_id = :tenantId AND id = :id',
    { tenantId, id: memberId }
  );
  if (!exists) return res.status(404).json({ error: 'member_not_found' });

  await execute('DELETE FROM members WHERE tenant_id = :tenantId AND id = :id', { tenantId, id: memberId });
  return res.json({ ok: true });
});

app.get('/members/:id/detail', authMiddleware, async (req, res) => {
  const tenantId = req.user.tenantId;
  const memberId = Number(req.params.id);
  if (!Number.isFinite(memberId) || memberId <= 0) return res.status(400).json({ error: 'invalid_request' });

  const member = await queryOne(
    `SELECT id, member_code, full_name, phone, email, status, join_date, frozen_until, frozen_reason, frozen_at, created_at
     FROM members
     WHERE tenant_id = :tenantId AND id = :id`,
    { tenantId, id: memberId }
  );
  if (!member) return res.status(404).json({ error: 'member_not_found' });

  const activeSub = await queryOne(
    `SELECT s.id, s.start_date, s.end_date, s.status, p.name AS plan_name, p.duration_days
     FROM subscriptions s
     INNER JOIN membership_plans p ON p.id = s.plan_id
     WHERE s.tenant_id = :tenantId AND s.member_id = :memberId
       AND s.status = 'active'
     ORDER BY s.end_date DESC
     LIMIT 1`,
    { tenantId, memberId }
  );

  const checkins = await queryOne(
    'SELECT COUNT(*) AS c FROM attendance_logs WHERE tenant_id = :tenantId AND member_id = :memberId',
    { tenantId, memberId }
  );
  const lastCheckin = await queryOne(
    `SELECT checked_in_at
     FROM attendance_logs
     WHERE tenant_id = :tenantId AND member_id = :memberId
     ORDER BY checked_in_at DESC
     LIMIT 1`,
    { tenantId, memberId }
  );

  const invoices = await queryMany(
    `SELECT id, invoice_no, subtotal, discount, tax, total, status, created_at
     FROM invoices
     WHERE tenant_id = :tenantId AND member_id = :memberId
     ORDER BY id DESC
     LIMIT 10`,
    { tenantId, memberId }
  );

  const attendanceHistory = await attendanceRepo.listForMember(tenantId, memberId, 20);
  const attendanceEvents = await attendanceRepo.listEventsForMember(tenantId, memberId, 30);

  const paymentTimeline = await queryMany(
    `SELECT i.id AS invoice_id, i.invoice_no, i.total, i.status AS invoice_status, i.created_at AS invoice_created_at,
            p.id AS payment_id, p.amount AS payment_amount, p.method AS payment_method, p.paid_at AS paid_at
     FROM invoices i
     LEFT JOIN payments p ON p.invoice_id = i.id
     WHERE i.tenant_id = :tenantId AND i.member_id = :memberId
     ORDER BY COALESCE(p.paid_at, i.created_at) DESC
     LIMIT 20`,
    { tenantId, memberId }
  );

  return res.json({
    member: {
      id: Number(member.id),
      memberCode: member.member_code,
      fullName: member.full_name,
      phone: member.phone,
      email: member.email,
      status: member.status,
      joinDate: member.join_date,
      frozenUntil: member.frozen_until ?? null,
      frozenReason: member.frozen_reason ?? null,
      frozenAt: member.frozen_at ?? null,
      createdAt: member.created_at
    },
    subscription: activeSub
      ? {
          id: Number(activeSub.id),
          planName: activeSub.plan_name,
          startDate: activeSub.start_date,
          endDate: activeSub.end_date,
          status: activeSub.status,
          durationDays: Number(activeSub.duration_days)
        }
      : null,
    checkinsTotal: Number(checkins?.c ?? 0),
    lastCheckinAt: lastCheckin?.checked_in_at ?? null,
    attendanceHistory: attendanceHistory.map((a) => ({
      id: Number(a.id),
      checkedInAt: a.checked_in_at,
      checkedOutAt: a.checked_out_at ?? null,
      source: a.source
    })),
    attendanceEvents: attendanceEvents.map((e) => ({
      id: Number(e.id),
      status: e.status,
      reason: e.reason,
      queryValue: e.query_value,
      checkedInAt: e.checked_in_at
    })),
    invoices: invoices.map((i) => ({
      id: Number(i.id),
      invoiceNo: i.invoice_no,
      subtotal: Number(i.subtotal),
      discount: Number(i.discount),
      tax: Number(i.tax),
      total: Number(i.total),
      status: i.status,
      createdAt: i.created_at
    })),
    paymentTimeline: paymentTimeline.map((r) => ({
      invoiceId: Number(r.invoice_id),
      invoiceNo: r.invoice_no,
      total: Number(r.total),
      paymentStatus: r.invoice_status,
      invoiceCreatedAt: r.invoice_created_at,
      paymentId: r.payment_id ? Number(r.payment_id) : null,
      paidAt: r.paid_at ?? null,
      method: r.payment_method ?? null,
      paidAmount: r.payment_amount != null ? Number(r.payment_amount) : null
    }))
  });
});

app.post('/members/register', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const bodySchema = z.object({
    memberCode: z.preprocess((v) => {
      if (v == null) return undefined;
      if (typeof v !== 'string') return v;
      const t = v.trim();
      return t.length ? t : undefined;
    }, z.string().min(2).max(32).optional()),
    fullName: z.string().min(2).max(191),
    phone: z.string().max(32).optional().nullable(),
    email: z.string().email().max(191).optional().nullable(),
    gender: z.enum(['male', 'female', 'other']).optional().nullable(),
    joinDate: z.string().optional().nullable(),
    branchId: z.number().int().positive().optional().nullable(),
    notes: z.string().max(255).optional().nullable(),
    planId: z.number().int().positive(),
    startDate: z.string().optional().nullable(),
    createInvoice: z.boolean().optional().default(true)
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });

  const tenantId = req.user.tenantId;
  const startDateRaw = parsed.data.startDate?.length ? parsed.data.startDate : parsed.data.joinDate;
  const startDate = startDateRaw?.length ? new Date(`${startDateRaw}T00:00:00`) : new Date();
  const joinDate = parsed.data.joinDate?.length ? parsed.data.joinDate : toDateOnly(new Date());

  const plan = await queryOne(
    `SELECT id, duration_days, price, admission_fee, status
     FROM membership_plans
     WHERE tenant_id = :tenantId AND id = :id`,
    { tenantId, id: parsed.data.planId }
  );
  if (!plan || plan.status !== 'active') return res.status(400).json({ error: 'invalid_plan' });

  const endDate = addDays(startDate, Number(plan.duration_days));
  const connPool = await getPool();
  const conn = await connPool.getConnection();
  try {
    await conn.beginTransaction();

    let memberCode = parsed.data.memberCode;
    for (let i = 0; i < 4; i += 1) {
      if (!memberCode?.length) memberCode = await generateMemberCode(conn, tenantId);
      try {
        const [memberResult] = await conn.execute(
          `INSERT INTO members (tenant_id, branch_id, member_code, full_name, phone, email, gender, join_date, notes)
           VALUES (:tenantId, :branchId, :memberCode, :fullName, :phone, :email, :gender, :joinDate, :notes)`,
          {
            tenantId,
            branchId: parsed.data.branchId ?? null,
            memberCode,
            fullName: parsed.data.fullName,
            phone: parsed.data.phone ?? null,
            email: parsed.data.email ?? null,
            gender: parsed.data.gender ?? null,
            joinDate,
            notes: parsed.data.notes ?? null
          }
        );
        const memberId = Number(memberResult.insertId);

        const [subResult] = await conn.execute(
          `INSERT INTO subscriptions (tenant_id, member_id, plan_id, start_date, end_date, status)
           VALUES (:tenantId, :memberId, :planId, :startDate, :endDate, 'active')`,
          {
            tenantId,
            memberId,
            planId: parsed.data.planId,
            startDate: toDateOnly(startDate),
            endDate: toDateOnly(endDate)
          }
        );
        const subscriptionId = Number(subResult.insertId);

        let invoiceId = null;
        let invoiceNo = null;
        if (parsed.data.createInvoice) {
          const subtotal = Number(plan.price) + Number(plan.admission_fee ?? 0);
          const total = Number(subtotal.toFixed(2));
          invoiceNo = newInvoiceNo();
          const [invResult] = await conn.execute(
            `INSERT INTO invoices (tenant_id, member_id, subscription_id, invoice_no, subtotal, discount, tax, total, status, due_date)
             VALUES (:tenantId, :memberId, :subscriptionId, :invoiceNo, :subtotal, 0, 0, :total, 'unpaid', :dueDate)`,
            {
              tenantId,
              memberId,
              subscriptionId,
              invoiceNo,
              subtotal,
              total,
              dueDate: toDateOnly(startDate)
            }
          );
          invoiceId = Number(invResult.insertId);
        }

        await conn.commit();
        await triggerAutomation(
          {
            tenantId,
            event: 'member_welcome',
            memberId,
            payload: { fullName: parsed.data.fullName, phone: parsed.data.phone ?? null, email: parsed.data.email ?? null }
          },
          conn
        );
        return res.status(201).json({
          memberId,
          memberCode,
          subscriptionId,
          startDate: toDateOnly(startDate),
          endDate: toDateOnly(endDate),
          invoiceId,
          invoiceNo
        });
      } catch (e) {
        if (String(e?.code ?? '') !== 'ER_DUP_ENTRY') throw e;
        memberCode = null;
      }
    }
    throw new Error('member_code_conflict');
  } catch {
    await conn.rollback();
    return res.status(400).json({ error: 'member_register_failed' });
  } finally {
    conn.release();
  }
});

app.post('/members', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const bodySchema = z.object({
    memberCode: z.preprocess((v) => {
      if (v == null) return undefined;
      if (typeof v !== 'string') return v;
      const t = v.trim();
      return t.length ? t : undefined;
    }, z.string().min(2).max(32).optional()),
    fullName: z.string().min(2).max(191),
    phone: z.string().max(32).optional().nullable(),
    email: z.string().email().max(191).optional().nullable(),
    gender: z.enum(['male', 'female', 'other']).optional().nullable(),
    joinDate: z.string().optional().nullable(),
    branchId: z.number().int().positive().optional().nullable(),
    notes: z.string().max(255).optional().nullable()
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });

  const joinDate = parsed.data.joinDate?.length ? parsed.data.joinDate : new Date().toISOString().slice(0, 10);
  const connPool = await getPool();
  const conn = await connPool.getConnection();
  try {
    let memberCode = parsed.data.memberCode;
    for (let i = 0; i < 4; i += 1) {
      if (!memberCode?.length) memberCode = await generateMemberCode(conn, req.user.tenantId);
      try {
        const [memberResult] = await conn.execute(
          `INSERT INTO members (tenant_id, branch_id, member_code, full_name, phone, email, gender, join_date, notes)
           VALUES (:tenantId, :branchId, :memberCode, :fullName, :phone, :email, :gender, :joinDate, :notes)`,
          {
            tenantId: req.user.tenantId,
            branchId: parsed.data.branchId ?? null,
            memberCode,
            fullName: parsed.data.fullName,
            phone: parsed.data.phone ?? null,
            email: parsed.data.email ?? null,
            gender: parsed.data.gender ?? null,
            joinDate,
            notes: parsed.data.notes ?? null
          }
        );
        const memberId = Number(memberResult.insertId);
        await triggerAutomation({
          tenantId: req.user.tenantId,
          event: 'member_welcome',
          memberId,
          payload: { fullName: parsed.data.fullName, phone: parsed.data.phone ?? null, email: parsed.data.email ?? null }
        });
        return res.status(201).json({ id: memberId, memberCode });
      } catch (e) {
        if (String(e?.code ?? '') !== 'ER_DUP_ENTRY') throw e;
        memberCode = null;
      }
    }
    return res.status(400).json({ error: 'member_create_failed' });
  } catch {
    return res.status(400).json({ error: 'member_create_failed' });
  } finally {
    conn.release();
  }
});

app.get('/plans', authMiddleware, async (req, res) => {
  const rows = await planRepo.list(req.user.tenantId, 200);
  return res.json({ items: rows });
});

app.post('/plans', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const bodySchema = z.object({
    name: z.string().min(2).max(191),
    durationDays: z.number().int().positive().max(3660),
    price: z.number().positive(),
    admissionFee: z.number().min(0).optional().default(0)
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });

  try {
    const result = await execute(
      `INSERT INTO membership_plans (tenant_id, name, duration_days, price, admission_fee)
       VALUES (:tenantId, :name, :durationDays, :price, :admissionFee)`,
      {
        tenantId: req.user.tenantId,
        name: parsed.data.name,
        durationDays: parsed.data.durationDays,
        price: parsed.data.price,
        admissionFee: parsed.data.admissionFee
      }
    );
    return res.status(201).json({ id: Number(result.insertId) });
  } catch (e) {
    const code = e?.code ?? null;
    const message = e?.message ?? null;
    await appendSystemLog({
      tenantId: req.user.tenantId,
      actorUserId: req.user.userId,
      action: 'plan_create_failed',
      entityType: 'membership_plan',
      entityId: null,
      meta: { code, message }
    });
    if (code === 'ER_DUP_ENTRY') return res.status(400).json({ error: 'plan_name_exists' });
    return res.status(400).json({ error: 'plan_create_failed' });
  }
});

app.patch('/plans/:id', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) return res.status(400).json({ error: 'invalid_request' });

  const bodySchema = z.object({
    name: z.string().min(2).max(191),
    durationDays: z.number().int().positive().max(3660),
    price: z.number().min(0),
    admissionFee: z.number().min(0).optional().default(0),
    status: z.enum(['active', 'inactive']).optional().default('active')
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });

  const exists = await queryOne(
    'SELECT id FROM membership_plans WHERE tenant_id = :tenantId AND id = :id',
    { tenantId, id }
  );
  if (!exists) return res.status(404).json({ error: 'plan_not_found' });

  await execute(
    `UPDATE membership_plans
     SET name = :name,
         duration_days = :durationDays,
         price = :price,
         admission_fee = :admissionFee,
         status = :status
     WHERE tenant_id = :tenantId AND id = :id`,
    {
      tenantId,
      id,
      name: parsed.data.name,
      durationDays: parsed.data.durationDays,
      price: parsed.data.price,
      admissionFee: parsed.data.admissionFee,
      status: parsed.data.status
    }
  );
  return res.json({ ok: true });
});

app.delete('/plans/:id', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) return res.status(400).json({ error: 'invalid_request' });

  const exists = await queryOne(
    'SELECT id FROM membership_plans WHERE tenant_id = :tenantId AND id = :id',
    { tenantId, id }
  );
  if (!exists) return res.status(404).json({ error: 'plan_not_found' });

  await execute(
    `UPDATE membership_plans SET status = 'inactive' WHERE tenant_id = :tenantId AND id = :id`,
    { tenantId, id }
  );
  return res.json({ ok: true });
});

app.delete('/plans/:id/hard', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) return res.status(400).json({ error: 'invalid_request' });

  const exists = await queryOne(
    'SELECT id FROM membership_plans WHERE tenant_id = :tenantId AND id = :id',
    { tenantId, id }
  );
  if (!exists) return res.status(404).json({ error: 'plan_not_found' });

  try {
    await execute('DELETE FROM membership_plans WHERE tenant_id = :tenantId AND id = :id', { tenantId, id });
    await appendSystemLog({
      tenantId,
      actorUserId: req.user.userId,
      action: 'plan_deleted',
      entityType: 'membership_plan',
      entityId: id,
      meta: null
    });
    return res.json({ ok: true });
  } catch (e) {
    const code = e?.code ?? null;
    const message = e?.message ?? null;
    await appendSystemLog({
      tenantId,
      actorUserId: req.user.userId,
      action: 'plan_delete_failed',
      entityType: 'membership_plan',
      entityId: id,
      meta: { code, message }
    });
    if (code === 'ER_ROW_IS_REFERENCED_2') return res.status(400).json({ error: 'plan_in_use' });
    return res.status(400).json({ error: 'plan_delete_failed' });
  }
});

app.get('/sentinel/validate', authMiddleware, async (req, res) => {
  const q = typeof req.query.q === 'string' ? req.query.q.trim() : '';
  if (!q.length) return res.status(400).json({ error: 'invalid_request' });
  const result = await sentinelService.validateAccess(req.user.tenantId, q);
  return res.json(result);
});

app.post('/attendance/checkin', authMiddleware, async (req, res) => {
  const bodySchema = z
    .object({
      memberId: z.number().int().positive().optional(),
      query: z.string().min(1).max(64).optional(),
      branchId: z.number().int().positive().optional().nullable(),
      source: z.enum(['manual', 'qr', 'rfid']).optional().default('manual')
    })
    .refine((v) => Boolean(v.memberId) || Boolean(v.query?.trim().length), { message: 'memberId_or_query_required' });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });

  const tenantId = req.user.tenantId;
  let memberId = parsed.data.memberId ? Number(parsed.data.memberId) : null;
  let queryValue = parsed.data.query?.trim() ?? null;
  if (queryValue?.length) {
    const validation = await sentinelService.validateAccess(tenantId, queryValue);
    if (!validation.allowed) {
      return res.json({
        ok: false,
        allowed: false,
        reason: validation.reason ?? 'denied',
        memberId: validation.member?.id ?? null,
        memberName: validation.member?.fullName ?? null,
        membershipEndDate: validation.plan?.endDate ?? null,
        unpaidInvoices: validation.unpaidInvoices ?? 0
      });
    }
    memberId = validation.member.id;
  }

  const member = await memberRepo.getActiveById(tenantId, memberId);
  if (!member) {
    await attendanceRepo.logEvent(tenantId, { memberId: memberId ?? null, queryValue, status: 'denied', reason: 'member_not_found' });
    return res.status(404).json({ error: 'member_not_found' });
  }
  const unpaidRow = await queryOne(
    `SELECT COUNT(*) AS c
     FROM invoices
     WHERE tenant_id = :tenantId AND member_id = :memberId AND status = 'unpaid'`,
    { tenantId, memberId: Number(member.id) }
  );
  const unpaidInvoices = Number(unpaidRow?.c ?? 0);
  const today = toDateOnly(new Date());
  if (member.frozen_until && String(member.frozen_until) >= today) {
    await attendanceRepo.logEvent(tenantId, { memberId: Number(member.id), queryValue, status: 'denied', reason: 'membership_frozen' });
    return res.json({
      ok: false,
      allowed: false,
      reason: 'membership_frozen',
      memberId: Number(member.id),
      memberName: member.full_name,
      memberCode: member.member_code,
      membershipEndDate: null,
      unpaidInvoices,
      frozenUntil: member.frozen_until
    });
  }

  const activeSub = await subRepo.getActiveForMember(tenantId, Number(member.id));
  const membershipEndDate = activeSub?.end_date ?? null;

  const open = await attendanceRepo.hasOpenSession(tenantId, Number(member.id));
  if (open?.id) {
    const checkedInAt = new Date(open.checked_in_at);
    const diffHours = (Date.now() - checkedInAt.getTime()) / (1000 * 60 * 60);
    if (diffHours < 16) {
      await attendanceRepo.logEvent(tenantId, { memberId: Number(member.id), queryValue, status: 'allowed', reason: 'already_checked_in' });
      return res.json({
        ok: true,
        allowed: true,
        attendanceId: Number(open.id),
        alreadyCheckedIn: true,
        memberId: Number(member.id),
        memberName: member.full_name,
        memberCode: member.member_code,
        membershipEndDate,
        unpaidInvoices
      });
    }
  }

  const attendanceId = await attendanceRepo.insertCheckIn(tenantId, Number(member.id), {
    branchId: parsed.data.branchId ?? null,
    source: parsed.data.source
  });
  await attendanceRepo.logEvent(tenantId, { memberId: Number(member.id), queryValue, status: 'allowed', reason: 'ok' });
  return res.status(201).json({
    ok: true,
    allowed: true,
    attendanceId,
    memberId: Number(member.id),
    memberName: member.full_name,
    memberCode: member.member_code,
    membershipEndDate,
    unpaidInvoices
  });
});

app.get('/attendance', authMiddleware, async (req, res) => {
  const tenantId = req.user.tenantId;
  const range = typeof req.query.range === 'string' ? req.query.range.trim() : 'today';
  const limit = Math.min(Math.max(Number(req.query.limit ?? 200), 1), 400);
  const offset = Math.min(Math.max(Number(req.query.offset ?? 0), 0), 100000);
  const q = typeof req.query.q === 'string' ? req.query.q.trim() : '';
  const sort = typeof req.query.sort === 'string' ? req.query.sort.trim() : 'newest';

  if (range === 'today' || !range.length) {
    const total = await attendanceRepo.countToday(tenantId, { q });
    const rows = await attendanceRepo.listToday(tenantId, { q, limit, offset, sort });
    return res.json({ total, limit, offset, items: rows });
  }

  let days = 0;
  if (range === '7d') days = 7;
  if (range === '30d') days = 30;
  if (!days) return res.status(400).json({ error: 'invalid_request' });

  const from = addDays(new Date(), -(days - 1));
  from.setHours(0, 0, 0, 0);
  const fromDateTime = toMysqlDateTime(from);
  const total = await attendanceRepo.countSince(tenantId, fromDateTime, { q });
  const rows = await attendanceRepo.listSince(tenantId, fromDateTime, { q, limit, offset, sort });
  return res.json({ total, limit, offset, items: rows });
});

app.get('/attendance/today', authMiddleware, async (req, res) => {
  const rows = await attendanceRepo.listToday(req.user.tenantId, { limit: 200, offset: 0, sort: 'newest' });
  return res.json({ items: rows });
});

app.get('/invoices', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const q = typeof req.query.q === 'string' ? req.query.q.trim() : '';
  const status = typeof req.query.status === 'string' ? req.query.status.trim() : '';
  const from = typeof req.query.from === 'string' ? req.query.from.trim() : '';
  const to = typeof req.query.to === 'string' ? req.query.to.trim() : '';
  const limit = Math.min(Math.max(Number(req.query.limit ?? 200), 1), 400);
  const offset = Math.min(Math.max(Number(req.query.offset ?? 0), 0), 100000);
  const sort = typeof req.query.sort === 'string' ? req.query.sort.trim() : 'newest';

  const where = ['i.tenant_id = :tenantId'];
  const params = { tenantId, limit, offset };

  if (q?.length) {
    where.push('(i.invoice_no LIKE :q OR m.full_name LIKE :q OR m.member_code LIKE :q OR m.phone LIKE :q)');
    params.q = `%${q}%`;
  }
  if (status?.length && status !== 'all') {
    // Support comma-separated statuses, e.g. "unpaid,partial" from the Record
    // Payment picker. A single value still uses equality.
    const statuses = status.split(',').map((s) => s.trim()).filter(Boolean);
    if (statuses.length === 1) {
      where.push('i.status = :status');
      params.status = statuses[0];
    } else if (statuses.length > 1) {
      const placeholders = statuses.map((_, idx) => `:status${idx}`);
      where.push(`i.status IN (${placeholders.join(', ')})`);
      statuses.forEach((s, idx) => {
        params[`status${idx}`] = s;
      });
    }
  }
  if (from?.length) {
    where.push('DATE(i.created_at) >= :from');
    params.from = from;
  }
  if (to?.length) {
    where.push('DATE(i.created_at) <= :to');
    params.to = to;
  }

  const order =
    sort === 'oldest'
      ? 'i.id ASC'
      : sort === 'total_desc'
        ? 'i.total DESC, i.id DESC'
        : 'i.id DESC';

  const countRow = await queryOne(
    `SELECT COUNT(*) AS c
     FROM invoices i
     INNER JOIN members m ON m.id = i.member_id
     WHERE ${where.join(' AND ')}`,
    params
  );
  const total = Number(countRow?.c ?? 0);

  const rows = await queryMany(
    `SELECT i.id, i.invoice_no, i.total, i.status, i.created_at, m.full_name, m.member_code, m.phone,
            COALESCE((SELECT SUM(p.amount) FROM payments p
                      WHERE p.invoice_id = i.id AND p.tenant_id = i.tenant_id), 0) AS amount_paid
     FROM invoices i
     INNER JOIN members m ON m.id = i.member_id
     WHERE ${where.join(' AND ')}
     ORDER BY ${order}
     LIMIT :limit OFFSET :offset`,
    params
  );
  return res.json({ total, limit, offset, items: rows });
});

app.get('/invoices/:id', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const invoiceId = Number(req.params.id);
  if (!Number.isFinite(invoiceId) || invoiceId <= 0) return res.status(400).json({ error: 'invalid_request' });
  const inv = await invoiceRepo.getById(tenantId, invoiceId);
  if (!inv) return res.status(404).json({ error: 'invoice_not_found' });
  return res.json({
    id: Number(inv.id),
    invoiceNo: inv.invoice_no,
    subtotal: Number(inv.subtotal),
    discount: Number(inv.discount),
    tax: Number(inv.tax),
    total: Number(inv.total),
    status: inv.status,
    dueDate: inv.due_date ?? null,
    createdAt: inv.created_at,
    member: {
      name: inv.member_name,
      code: inv.member_code,
      phone: inv.phone ?? null,
      email: inv.email ?? null
    }
  });
});

app.patch('/invoices/:id', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const invoiceId = Number(req.params.id);
  if (!Number.isFinite(invoiceId) || invoiceId <= 0) return res.status(400).json({ error: 'invalid_request' });

  const bodySchema = z.object({
    discount: z.number().min(0).optional(),
    tax: z.number().min(0).optional(),
    dueDate: z.string().min(10).max(10).optional().nullable(),
    status: z.enum(['draft', 'unpaid', 'void']).optional()
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });

  const inv = await queryOne(
    `SELECT id, subtotal, discount, tax, status
     FROM invoices
     WHERE tenant_id = :tenantId AND id = :id`,
    { tenantId, id: invoiceId }
  );
  if (!inv) return res.status(404).json({ error: 'invoice_not_found' });
  if (inv.status === 'paid') return res.status(400).json({ error: 'cannot_edit_paid_invoice' });

  const nextDiscount = parsed.data.discount != null ? Number(parsed.data.discount) : Number(inv.discount);
  const nextTax = parsed.data.tax != null ? Number(parsed.data.tax) : Number(inv.tax);
  const nextStatus = parsed.data.status ?? inv.status;
  const subtotal = Number(inv.subtotal);
  const total = Number((subtotal - nextDiscount + nextTax).toFixed(2));
  if (total < 0) return res.status(400).json({ error: 'invalid_total' });

  await execute(
    `UPDATE invoices
     SET discount = :discount,
         tax = :tax,
         total = :total,
         due_date = :dueDate,
         status = :status
     WHERE tenant_id = :tenantId AND id = :id`,
    {
      tenantId,
      id: invoiceId,
      discount: nextDiscount,
      tax: nextTax,
      total,
      dueDate: parsed.data.dueDate ?? null,
      status: nextStatus
    }
  );
  return res.json({ ok: true, total });
});

app.get('/invoices/:id/pdf', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const invoiceId = Number(req.params.id);
  if (!Number.isFinite(invoiceId) || invoiceId <= 0) return res.status(400).json({ error: 'invalid_request' });

  const inv = await invoiceRepo.getById(tenantId, invoiceId);
  if (!inv) return res.status(404).json({ error: 'invoice_not_found' });
  const profile = await loadGymProfileForTenant(tenantId);

  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="${inv.invoice_no}.pdf"`);

  const doc = createBrandedPdf();
  doc.pipe(res);

  drawGymPdfHeader(doc, profile, {
    title: 'INVOICE',
    subtitle: `Invoice No: ${inv.invoice_no}  •  Date: ${toDateOnly(new Date(inv.created_at))}`
  });

  doc.moveDown(1.2);
  doc.fontSize(14).text('Bill To', { underline: true });
  doc.moveDown(0.4);
  doc.fontSize(11).text(`${inv.member_name} (${inv.member_code})`);
  if (inv.phone) doc.text(`Phone: ${inv.phone}`);
  if (inv.email) doc.text(`Email: ${inv.email}`);

  doc.moveDown(1.2);
  const startX = 40;
  const rightX = 555;
  const lineY = doc.y;
  doc.moveTo(startX, lineY).lineTo(rightX, lineY).strokeColor('#DDDDDD').stroke();
  doc.moveDown(0.6);

  doc.fontSize(11).text('Description', startX, doc.y, { continued: true });
  doc.text('Amount', 0, doc.y, { align: 'right' });
  doc.moveDown(0.4);
  doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#DDDDDD').stroke();
  doc.moveDown(0.6);

  doc.text('Membership / Services');
  doc.text(Number(inv.subtotal).toFixed(2), 0, doc.y - 12, { align: 'right' });

  doc.moveDown(1.2);
  doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#DDDDDD').stroke();
  doc.moveDown(0.6);

  const money = (v) => Number(v ?? 0).toFixed(2);
  doc.fontSize(11);
  doc.text(`Subtotal: ${money(inv.subtotal)}`, { align: 'right' });
  doc.text(`Tax: ${money(inv.tax)}`, { align: 'right' });
  doc.fontSize(12).text(`Total: ${money(inv.total)}`, { align: 'right' });

  doc.moveDown(1.2);
  doc.fontSize(10).fillColor('#666666').text('Thank you for your business.', { align: 'center' });
  doc.end();
});

app.get('/reports/monthly-revenue.pdf', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const monthRaw = typeof req.query.month === 'string' ? req.query.month.trim() : '';
  const validMonth = /^\d{4}-\d{2}$/.test(monthRaw) ? monthRaw : toDateOnly(new Date()).slice(0, 7);
  const year = Number(validMonth.slice(0, 4));
  const month = Number(validMonth.slice(5, 7));
  const start = `${validMonth}-01`;
  const endDate = new Date(year, month, 0);
  const end = toDateOnly(endDate);

  const profile = await loadGymProfileForTenant(tenantId);
  const rows = await queryMany(
    `SELECT i.invoice_no, i.total, i.created_at, m.full_name, m.member_code
     FROM invoices i
     INNER JOIN members m ON m.id = i.member_id
     WHERE i.tenant_id = :tenantId
       AND i.status = 'paid'
       AND DATE(i.created_at) BETWEEN :start AND :end
     ORDER BY i.created_at ASC
     LIMIT 500`,
    { tenantId, start, end }
  );
  const total = rows.reduce((sum, r) => sum + Number(r.total ?? 0), 0);
  const collectedRow = await queryOne(
    `SELECT COALESCE(SUM(amount), 0) AS s
     FROM payments
     WHERE tenant_id = :tenantId
       AND DATE(paid_at) BETWEEN :start AND :end`,
    { tenantId, start, end }
  );
  const expensesRow = await queryOne(
    `SELECT COALESCE(SUM(amount), 0) AS s
     FROM expenses
     WHERE tenant_id = :tenantId
       AND expense_date BETWEEN :start AND :end`,
    { tenantId, start, end }
  );
  const totalCollected = Number(collectedRow?.s ?? 0);
  const totalExpenses = Number(expensesRow?.s ?? 0);
  const netProfit = Number((totalCollected - totalExpenses).toFixed(2));

  const byDayRows = await queryMany(
    `SELECT DATE(created_at) AS d, COALESCE(SUM(total), 0) AS s
     FROM invoices
     WHERE tenant_id = :tenantId
       AND status = 'paid'
       AND DATE(created_at) BETWEEN :start AND :end
     GROUP BY DATE(created_at)
     ORDER BY d ASC`,
    { tenantId, start, end }
  );

  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="monthly_revenue_${validMonth}.pdf"`);
  const doc = createBrandedPdf();
  doc.pipe(res);

  drawGymPdfHeader(doc, profile, {
    title: 'Revenue Report',
    subtitle: `Month: ${validMonth}  •  Range: ${start} → ${end}`
  });
  doc.moveDown(0.4);

  doc.fontSize(12).text(`Total Collected: ${totalCollected.toFixed(2)}`, { align: 'left' });
  doc.fontSize(12).text(`Total Expenses: ${totalExpenses.toFixed(2)}`, { align: 'left' });
  doc.fontSize(12).text(`Net Profit: ${netProfit.toFixed(2)}`, { align: 'left' });
  doc.moveDown(0.6);
  doc.fontSize(10).fillColor('#555555').text(`Paid Invoices Total: ${Number(total).toFixed(2)}`);
  doc.moveDown(0.8);

  doc.fontSize(12).text('Daily Totals', { underline: true });
  doc.moveDown(0.4);
  doc.fontSize(10);
  for (const r of byDayRows) {
    doc.text(`${toDateOnly(new Date(r.d))}  •  ${Number(r.s ?? 0).toFixed(2)}`);
  }

  doc.moveDown(0.8);
  doc.fontSize(12).text('Paid Invoices', { underline: true });
  doc.moveDown(0.4);

  const startX = 40;
  const rightX = 555;
  const drawPaidInvoicesHeader = () => {
    pdfDrawRow(
      doc,
      [
        { text: 'Invoice', x: startX, width: 90 },
        { text: 'Member', x: startX + 95, width: 330 },
        { text: 'Total', x: startX + 430, width: 85, align: 'right' }
      ],
      { color: '#555555' }
    );
    doc.moveDown(0.3);
    doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#DDDDDD').stroke();
    doc.moveDown(0.5);
  };
  const redrawRevenuePaidInvoicesPage = () => {
    drawGymPdfHeader(doc, profile, {
      title: 'Revenue Report',
      subtitle: `Month: ${validMonth}  •  Range: ${start} → ${end}`
    });
    doc.moveDown(0.8);
    doc.fontSize(12).text('Paid Invoices (cont.)', { underline: true });
    doc.moveDown(0.4);
    drawPaidInvoicesHeader();
  };
  drawPaidInvoicesHeader();

  for (const r of rows) {
    pdfDrawRow(
      doc,
      [
        { text: r.invoice_no ?? '', x: startX, width: 90 },
        { text: `${r.full_name ?? ''} (${r.member_code ?? ''})`, x: startX + 95, width: 330 },
        { text: Number(r.total ?? 0).toFixed(2), x: startX + 430, width: 85, align: 'right' }
      ],
      { onNewPage: redrawRevenuePaidInvoicesPage }
    );
  }

  doc.end();
});

app.get('/reports/profit-series', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const monthRaw = typeof req.query.month === 'string' ? req.query.month.trim() : '';
  const validMonth = /^\d{4}-\d{2}$/.test(monthRaw) ? monthRaw : toDateOnly(new Date()).slice(0, 7);
  const year = Number(validMonth.slice(0, 4));
  const month = Number(validMonth.slice(5, 7));
  const start = `${validMonth}-01`;
  const endDate = new Date(year, month, 0);
  const end = toDateOnly(endDate);

  const revenueRows = await queryMany(
    `SELECT DATE(paid_at) AS d, COALESCE(SUM(amount), 0) AS s
     FROM payments
     WHERE tenant_id = :tenantId
       AND DATE(paid_at) BETWEEN :start AND :end
     GROUP BY DATE(paid_at)
     ORDER BY d ASC`,
    { tenantId, start, end }
  );
  const expenseRows = await queryMany(
    `SELECT expense_date AS d, COALESCE(SUM(amount), 0) AS s
     FROM expenses
     WHERE tenant_id = :tenantId
       AND expense_date BETWEEN :start AND :end
     GROUP BY expense_date
     ORDER BY d ASC`,
    { tenantId, start, end }
  );

  const revenueMap = new Map(revenueRows.map((r) => [fmtDateOnlyStr(r.d), Number(r.s ?? 0)]));
  const expenseMap = new Map(expenseRows.map((r) => [fmtDateOnlyStr(r.d), Number(r.s ?? 0)]));

  const items = [];
  const startDt = new Date(`${start}T00:00:00`);
  const endDt = new Date(`${end}T00:00:00`);
  for (let d = new Date(startDt); d.getTime() <= endDt.getTime(); d = addDays(d, 1)) {
    const key = toDateOnly(d);
    const revenue = Number(revenueMap.get(key) ?? 0);
    const expense = Number(expenseMap.get(key) ?? 0);
    const profit = Number((revenue - expense).toFixed(2));
    items.push({ date: key, revenue, expense, profit });
  }

  const totalRevenue = Number(items.reduce((sum, r) => sum + Number(r.revenue ?? 0), 0).toFixed(2));
  const totalExpense = Number(items.reduce((sum, r) => sum + Number(r.expense ?? 0), 0).toFixed(2));
  const totalProfit = Number((totalRevenue - totalExpense).toFixed(2));
  const marginPct = totalRevenue > 0 ? Number(((totalProfit / totalRevenue) * 100).toFixed(2)) : 0;

  return res.json({
    month: validMonth,
    start,
    end,
    totals: {
      revenue: totalRevenue,
      expense: totalExpense,
      profit: totalProfit,
      marginPct
    },
    items
  });
});

app.get('/reports/revenue-prediction', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const months = 3;

  const now = new Date();
  const curMonthStart = new Date(now.getFullYear(), now.getMonth(), 1);

  const monthStart = (d) => new Date(d.getFullYear(), d.getMonth(), 1);
  const addMonths = (d, n) => new Date(d.getFullYear(), d.getMonth() + n, 1);
  const ym = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;

  const lastMonthStart = addMonths(curMonthStart, -1);
  const firstMonthStart = addMonths(curMonthStart, -(months));
  const rangeStart = toDateOnly(firstMonthStart);
  const rangeEndExclusive = toDateOnly(curMonthStart);

  const rows = await queryMany(
    `SELECT DATE_FORMAT(paid_at, '%Y-%m') AS ym, COALESCE(SUM(amount), 0) AS s
     FROM payments
     WHERE tenant_id = :tenantId
       AND paid_at >= :start
       AND paid_at < :endExclusive
     GROUP BY DATE_FORMAT(paid_at, '%Y-%m')
     ORDER BY ym ASC`,
    { tenantId, start: rangeStart, endExclusive: rangeEndExclusive }
  );
  const map = new Map(rows.map((r) => [String(r.ym), Number(r.s ?? 0)]));

  const history = [];
  for (let i = months; i >= 1; i -= 1) {
    const m = addMonths(curMonthStart, -i);
    const key = ym(m);
    history.push({ month: key, revenue: Number(map.get(key) ?? 0) });
  }

  const x = [1, 2, 3];
  const y = history.map((h) => Number(h.revenue ?? 0));
  const meanX = x.reduce((a, b) => a + b, 0) / x.length;
  const meanY = y.reduce((a, b) => a + b, 0) / y.length;
  let cov = 0;
  let varX = 0;
  for (let i = 0; i < x.length; i += 1) {
    cov += (x[i] - meanX) * (y[i] - meanY);
    varX += (x[i] - meanX) * (x[i] - meanX);
  }
  const slope = varX === 0 ? 0 : cov / varX;
  const intercept = meanY - slope * meanX;
  const predictedRaw = intercept + slope * 4;
  const predictedRevenue = Number(Math.max(0, predictedRaw).toFixed(2));

  const lastRevenue = Number(history[history.length - 1]?.revenue ?? 0);
  const delta = Number((predictedRevenue - lastRevenue).toFixed(2));
  const deltaPct = lastRevenue > 0 ? Number(((delta / lastRevenue) * 100).toFixed(2)) : (predictedRevenue > 0 ? 100 : 0);

  const predictedMonth = ym(curMonthStart);
  return res.json({
    basis: {
      months: history.length,
      method: 'linear_regression',
      rangeStart,
      rangeEndExclusive
    },
    history,
    prediction: {
      month: predictedMonth,
      revenue: predictedRevenue,
      delta,
      deltaPct
    }
  });
});

app.get('/reports/expired-members.pdf', authMiddleware, async (req, res) => {
  const tenantId = req.user.tenantId;
  const profile = await loadGymProfileForTenant(tenantId);
  const rows = await queryMany(
    `SELECT m.id AS member_id, m.member_code, m.full_name, m.phone, s.end_date,
            DATEDIFF(CURDATE(), s.end_date) AS days_expired
     FROM members m
     INNER JOIN subscriptions s ON s.member_id = m.id AND s.tenant_id = m.tenant_id
     WHERE m.tenant_id = :tenantId
       AND m.status = 'active'
       AND s.end_date = (
         SELECT MAX(s2.end_date) FROM subscriptions s2
         WHERE s2.tenant_id = m.tenant_id AND s2.member_id = m.id
       )
       AND s.end_date < CURDATE()
     ORDER BY s.end_date ASC
     LIMIT 500`,
    { tenantId }
  );

  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="expired_members_${toDateOnly(new Date())}.pdf"`);
  const doc = createBrandedPdf();
  doc.pipe(res);

  drawGymPdfHeader(doc, profile, {
    title: 'Expired Members',
    subtitle: `As of: ${toDateOnly(new Date())}  •  Count: ${rows.length}`
  });
  doc.moveDown(0.8);

  const startX = 40;
  const rightX = 555;
  const drawHeader = () => {
    pdfDrawRow(
      doc,
      [
        { text: 'Code', x: startX, width: 70 },
        { text: 'Member', x: startX + 75, width: 210 },
        { text: 'Phone', x: startX + 290, width: 90 },
        { text: 'Expiry', x: startX + 385, width: 70 },
        { text: 'Days', x: startX + 460, width: 55, align: 'right' }
      ],
      { color: '#555555' }
    );
    doc.moveDown(0.3);
    doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#DDDDDD').stroke();
    doc.moveDown(0.5);
  };
  const redrawPage = () => {
    drawGymPdfHeader(doc, profile, {
      title: 'Expired Members',
      subtitle: `As of: ${toDateOnly(new Date())}`
    });
    doc.moveDown(0.8);
    drawHeader();
  };
  drawHeader();

  for (const r of rows) {
    pdfDrawRow(
      doc,
      [
        { text: r.member_code ?? '', x: startX, width: 70 },
        { text: r.full_name ?? '', x: startX + 75, width: 210 },
        { text: r.phone ?? '-', x: startX + 290, width: 90 },
        { text: fmtDateOnlyStr(r.end_date), x: startX + 385, width: 70 },
        { text: r.days_expired ?? '', x: startX + 460, width: 55, align: 'right' }
      ],
      { onNewPage: redrawPage }
    );
  }

  doc.end();
});

app.get('/reports/daily-attendance.pdf', authMiddleware, async (req, res) => {
  const tenantId = req.user.tenantId;
  const dateRaw = typeof req.query.date === 'string' ? req.query.date.trim() : '';
  const validDate = /^\d{4}-\d{2}-\d{2}$/.test(dateRaw) ? dateRaw : toDateOnly(new Date());
  const profile = await loadGymProfileForTenant(tenantId);

  const rows = await queryMany(
    `SELECT a.checked_in_at, a.checked_out_at, m.full_name, m.member_code
     FROM attendance_logs a
     INNER JOIN members m ON m.id = a.member_id
     WHERE a.tenant_id = :tenantId AND DATE(a.checked_in_at) = :d
     ORDER BY a.checked_in_at ASC
     LIMIT 800`,
    { tenantId, d: validDate }
  );

  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="attendance_${validDate}.pdf"`);
  const doc = createBrandedPdf();
  doc.pipe(res);

  drawGymPdfHeader(doc, profile, {
    title: 'Daily Attendance',
    subtitle: `Date: ${validDate}  •  Count: ${rows.length}`
  });
  doc.moveDown(0.8);

  const startX = 40;
  const rightX = 555;
  const drawHeader = () => {
    pdfDrawRow(
      doc,
      [
        { text: 'Code', x: startX, width: 70 },
        { text: 'Member', x: startX + 75, width: 235 },
        { text: 'In', x: startX + 315, width: 60 },
        { text: 'Out', x: startX + 380, width: 135, align: 'right' }
      ],
      { color: '#555555' }
    );
    doc.moveDown(0.3);
    doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#DDDDDD').stroke();
    doc.moveDown(0.5);
  };
  const redrawPage = () => {
    drawGymPdfHeader(doc, profile, {
      title: 'Daily Attendance',
      subtitle: `Date: ${validDate}`
    });
    doc.moveDown(0.8);
    drawHeader();
  };
  drawHeader();

  const fmt = (raw) => {
    const d = new Date(raw);
    if (Number.isNaN(d.getTime())) return String(raw ?? '');
    const hh = String(d.getHours()).padStart(2, '0');
    const mm = String(d.getMinutes()).padStart(2, '0');
    return `${hh}:${mm}`;
  };

  for (const r of rows) {
    pdfDrawRow(
      doc,
      [
        { text: r.member_code ?? '', x: startX, width: 70 },
        { text: r.full_name ?? '', x: startX + 75, width: 235 },
        { text: fmt(r.checked_in_at), x: startX + 315, width: 60 },
        { text: r.checked_out_at ? fmt(r.checked_out_at) : '-', x: startX + 380, width: 135, align: 'right' }
      ],
      { onNewPage: redrawPage }
    );
  }

  doc.end();
});

app.get('/pdf/dashboard.pdf', authMiddleware, async (req, res) => {
  const tenantId = req.user.tenantId;
  const canSeeRevenue = (req.user.roles ?? []).some((r) => r === 'owner' || r === 'admin' || r === 'super_admin');
  const profile = await loadGymProfileForTenant(tenantId);

  const membersTotal = await queryOne('SELECT COUNT(*) AS c FROM members WHERE tenant_id = :tenantId', { tenantId });
  const activeMembers = await queryOne(
    "SELECT COUNT(*) AS c FROM members WHERE tenant_id = :tenantId AND status = 'active'",
    { tenantId }
  );
  const plansTotal = await queryOne('SELECT COUNT(*) AS c FROM membership_plans WHERE tenant_id = :tenantId', { tenantId });
  const todayCheckins = await queryOne(
    'SELECT COUNT(*) AS c FROM attendance_logs WHERE tenant_id = :tenantId AND DATE(checked_in_at) = CURDATE()',
    { tenantId }
  );
  const unpaidInvoices = await queryOne("SELECT COUNT(*) AS c FROM invoices WHERE tenant_id = :tenantId AND status = 'unpaid'", {
    tenantId
  });
  const unpaidAmount = await queryOne(
    "SELECT COALESCE(SUM(total), 0) AS s FROM invoices WHERE tenant_id = :tenantId AND status = 'unpaid'",
    { tenantId }
  );
  const revenueLast30Days = await queryOne(
    "SELECT COALESCE(SUM(total), 0) AS s FROM invoices WHERE tenant_id = :tenantId AND status = 'paid' AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)",
    { tenantId }
  );
  const revenueTotal = await queryOne(
    "SELECT COALESCE(SUM(total), 0) AS s FROM invoices WHERE tenant_id = :tenantId AND status = 'paid'",
    { tenantId }
  );
  const membershipCounts = await queryOne(
    `SELECT
        SUM(CASE WHEN x.end_date IS NOT NULL AND x.end_date >= CURDATE() THEN 1 ELSE 0 END) AS active_c,
        SUM(CASE WHEN x.end_date IS NULL OR x.end_date < CURDATE() THEN 1 ELSE 0 END) AS expired_c
     FROM (
       SELECT m.id AS member_id,
              (SELECT MAX(s.end_date)
               FROM subscriptions s
               WHERE s.tenant_id = m.tenant_id AND s.member_id = m.id) AS end_date
       FROM members m
       WHERE m.tenant_id = :tenantId AND m.status = 'active'
     ) x`,
    { tenantId }
  );
  const expiringMembers = await queryMany(
    `SELECT m.member_code, m.full_name, s.end_date, DATEDIFF(s.end_date, CURDATE()) AS days_left
     FROM subscriptions s
     INNER JOIN members m ON m.id = s.member_id
     WHERE s.tenant_id = :tenantId
       AND s.status = 'active'
       AND m.status = 'active'
       AND s.end_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 3 DAY)
     ORDER BY s.end_date ASC
     LIMIT 10`,
    { tenantId }
  );

  const today = toDateOnly(new Date());
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="dashboard_${today}.pdf"`);
  const doc = createBrandedPdf();
  doc.pipe(res);

  drawGymPdfHeader(doc, profile, { title: 'Dashboard', subtitle: `Date: ${today}` });
  doc.moveDown(0.8);

  const money = (v) => Number(v ?? 0).toFixed(2);
  const line = (label, value) => {
    doc.fontSize(11).text(String(label), { continued: true });
    doc.text(String(value), { align: 'right' });
  };

  line('Total Members', Number(membersTotal?.c ?? 0));
  line('Active Members', Number(activeMembers?.c ?? 0));
  line('Membership Active', Number(membershipCounts?.active_c ?? 0));
  line('Membership Expired', Number(membershipCounts?.expired_c ?? 0));
  line('Plans', Number(plansTotal?.c ?? 0));
  line("Today's Check-ins", Number(todayCheckins?.c ?? 0));
  line('Unpaid Invoices', Number(unpaidInvoices?.c ?? 0));
  if (canSeeRevenue) {
    line('Unpaid Amount', money(unpaidAmount?.s ?? 0));
    line('Revenue (30d)', money(revenueLast30Days?.s ?? 0));
    line('Total Revenue', money(revenueTotal?.s ?? 0));
  }

  doc.moveDown(1.2);
  doc.fontSize(12).text('Urgent Alerts (3 days)', { underline: true });
  doc.moveDown(0.5);

  const startX = 40;
  const rightX = 555;
  pdfDrawRow(
    doc,
    [
      { text: 'Code', x: startX, width: 70 },
      { text: 'Member', x: startX + 75, width: 280 },
      { text: 'Expiry', x: startX + 360, width: 90 },
      { text: 'Days', x: startX + 455, width: 60, align: 'right' }
    ],
    { color: '#555555' }
  );
  doc.moveDown(0.3);
  doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#DDDDDD').stroke();
  doc.moveDown(0.5);

  if (!expiringMembers.length) {
    doc.text('No urgent alerts.');
    doc.end();
    return;
  }
  const redrawUrgentHeader = () => {
    drawGymPdfHeader(doc, profile, { title: 'Dashboard', subtitle: `Date: ${today}` });
    doc.moveDown(0.8);
    doc.fontSize(12).text('Urgent Alerts (3 days)', { underline: true });
    doc.moveDown(0.5);
    pdfDrawRow(
      doc,
      [
        { text: 'Code', x: startX, width: 70 },
        { text: 'Member', x: startX + 75, width: 280 },
        { text: 'Expiry', x: startX + 360, width: 90 },
        { text: 'Days', x: startX + 455, width: 60, align: 'right' }
      ],
      { color: '#555555' }
    );
    doc.moveDown(0.3);
    doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#DDDDDD').stroke();
    doc.moveDown(0.5);
  };
  for (const r of expiringMembers) {
    pdfDrawRow(
      doc,
      [
        { text: r.member_code ?? '', x: startX, width: 70 },
        { text: r.full_name ?? '', x: startX + 75, width: 280 },
        { text: fmtDateOnlyStr(r.end_date ?? ''), x: startX + 360, width: 90 },
        { text: r.days_left ?? '', x: startX + 455, width: 60, align: 'right' }
      ],
      { onNewPage: redrawUrgentHeader }
    );
  }
  doc.end();
});

app.get('/pdf/leads.pdf', authMiddleware, requireRole('owner', 'admin', 'staff', 'receptionist'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const profile = await loadGymProfileForTenant(tenantId);
  const rows = await queryMany(
    `SELECT full_name, phone, source, interest, next_contact_date, status
     FROM leads
     WHERE tenant_id = :tenantId
     ORDER BY id DESC
     LIMIT 500`,
    { tenantId }
  );

  const today = toDateOnly(new Date());
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="leads_${today}.pdf"`);
  const doc = createBrandedPdf();
  doc.pipe(res);

  drawGymPdfHeader(doc, profile, { title: 'Leads', subtitle: `Date: ${today}  •  Count: ${rows.length}` });
  doc.moveDown(0.8);

  const startX = 40;
  const rightX = 555;
  const drawHeader = () => {
    pdfDrawRow(
      doc,
      [
        { text: 'Name', x: startX, width: 160 },
        { text: 'Phone', x: startX + 160, width: 80 },
        { text: 'Source', x: startX + 240, width: 75 },
        { text: 'Interest', x: startX + 315, width: 95 },
        { text: 'Next', x: startX + 410, width: 60 },
        { text: 'Status', x: startX + 470, width: 45, align: 'right' }
      ],
      { color: '#555555' }
    );
    doc.moveDown(0.3);
    doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#DDDDDD').stroke();
    doc.moveDown(0.5);
  };
  drawHeader();
  const redraw = () => {
    drawGymPdfHeader(doc, profile, { title: 'Leads', subtitle: `Date: ${today}` });
    doc.moveDown(0.8);
    drawHeader();
  };

  for (const r of rows) {
    pdfDrawRow(
      doc,
      [
        { text: r.full_name ?? '', x: startX, width: 160 },
        { text: r.phone ?? '-', x: startX + 160, width: 80 },
        { text: r.source ?? '-', x: startX + 240, width: 75 },
        { text: r.interest ?? '-', x: startX + 315, width: 95 },
        { text: r.next_contact_date ? fmtDateOnlyStr(r.next_contact_date) : '-', x: startX + 410, width: 60 },
        { text: r.status ?? '', x: startX + 470, width: 45, align: 'right' }
      ],
      { onNewPage: redraw }
    );
  }
  doc.end();
});

app.get('/pdf/members.pdf', authMiddleware, async (req, res) => {
  const tenantId = req.user.tenantId;
  const profile = await loadGymProfileForTenant(tenantId);
  const rows = await queryMany(
    `SELECT member_code, full_name, phone, status, join_date
     FROM members
     WHERE tenant_id = :tenantId
     ORDER BY id DESC
     LIMIT 500`,
    { tenantId }
  );

  const today = toDateOnly(new Date());
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="members_${today}.pdf"`);
  const doc = createBrandedPdf();
  doc.pipe(res);

  drawGymPdfHeader(doc, profile, { title: 'Members', subtitle: `Date: ${today}  •  Count: ${rows.length}` });
  doc.moveDown(0.8);

  const startX = 40;
  const rightX = 555;
  const drawHeader = () => {
    pdfDrawRow(
      doc,
      [
        { text: 'Code', x: startX, width: 70 },
        { text: 'Member', x: startX + 75, width: 210 },
        { text: 'Phone', x: startX + 290, width: 90 },
        { text: 'Join', x: startX + 385, width: 70 },
        { text: 'Status', x: startX + 460, width: 55, align: 'right' }
      ],
      { color: '#555555' }
    );
    doc.moveDown(0.3);
    doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#DDDDDD').stroke();
    doc.moveDown(0.5);
  };
  drawHeader();

  const redrawMembersHeader = () => {
    drawGymPdfHeader(doc, profile, { title: 'Members', subtitle: `Date: ${today}` });
    doc.moveDown(0.8);
    drawHeader();
  };
  for (const r of rows) {
    pdfDrawRow(
      doc,
      [
        { text: r.member_code ?? '', x: startX, width: 70 },
        { text: r.full_name ?? '', x: startX + 75, width: 210 },
        { text: r.phone ?? '-', x: startX + 290, width: 90 },
        { text: fmtDateOnlyStr(r.join_date ?? ''), x: startX + 385, width: 70 },
        { text: r.status ?? '', x: startX + 460, width: 55, align: 'right' }
      ],
      { onNewPage: redrawMembersHeader }
    );
  }

  doc.end();
});

app.get('/pdf/plans.pdf', authMiddleware, async (req, res) => {
  const tenantId = req.user.tenantId;
  const profile = await loadGymProfileForTenant(tenantId);
  const rows = await queryMany(
    `SELECT name, duration_days, price, admission_fee, status
     FROM membership_plans
     WHERE tenant_id = :tenantId
     ORDER BY status DESC, name ASC
     LIMIT 500`,
    { tenantId }
  );

  const today = toDateOnly(new Date());
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="plans_${today}.pdf"`);
  const doc = createBrandedPdf();
  doc.pipe(res);

  drawGymPdfHeader(doc, profile, { title: 'Plans', subtitle: `Date: ${today}  •  Count: ${rows.length}` });
  doc.moveDown(0.8);

  const startX = 40;
  const rightX = 555;
  const drawHeader = () => {
    pdfDrawRow(
      doc,
      [
        { text: 'Plan', x: startX, width: 250 },
        { text: 'Days', x: startX + 255, width: 50, align: 'right' },
        { text: 'Price', x: startX + 310, width: 70, align: 'right' },
        { text: 'Fee', x: startX + 385, width: 70, align: 'right' },
        { text: 'Status', x: startX + 460, width: 55, align: 'right' }
      ],
      { color: '#555555' }
    );
    doc.moveDown(0.3);
    doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#DDDDDD').stroke();
    doc.moveDown(0.5);
  };
  drawHeader();

  const redrawPlansHeader = () => {
    drawGymPdfHeader(doc, profile, { title: 'Plans', subtitle: `Date: ${today}` });
    doc.moveDown(0.8);
    drawHeader();
  };
  for (const r of rows) {
    pdfDrawRow(
      doc,
      [
        { text: r.name ?? '', x: startX, width: 250 },
        { text: r.duration_days ?? '', x: startX + 255, width: 50, align: 'right' },
        { text: Number(r.price ?? 0).toFixed(2), x: startX + 310, width: 70, align: 'right' },
        { text: Number(r.admission_fee ?? 0).toFixed(2), x: startX + 385, width: 70, align: 'right' },
        { text: r.status ?? '', x: startX + 460, width: 55, align: 'right' }
      ],
      { onNewPage: redrawPlansHeader }
    );
  }

  doc.end();
});

app.get('/pdf/attendance.pdf', authMiddleware, async (req, res) => {
  const tenantId = req.user.tenantId;
  const dateRaw = typeof req.query.date === 'string' ? req.query.date.trim() : '';
  const validDate = /^\d{4}-\d{2}-\d{2}$/.test(dateRaw) ? dateRaw : toDateOnly(new Date());
  const profile = await loadGymProfileForTenant(tenantId);
  const rows = await queryMany(
    `SELECT a.checked_in_at, a.checked_out_at, m.full_name, m.member_code
     FROM attendance_logs a
     INNER JOIN members m ON m.id = a.member_id
     WHERE a.tenant_id = :tenantId AND DATE(a.checked_in_at) = :d
     ORDER BY a.checked_in_at ASC
     LIMIT 800`,
    { tenantId, d: validDate }
  );

  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="attendance_${validDate}.pdf"`);
  const doc = createBrandedPdf();
  doc.pipe(res);

  drawGymPdfHeader(doc, profile, { title: 'Attendance', subtitle: `Date: ${validDate}  •  Count: ${rows.length}` });
  doc.moveDown(0.8);

  const startX = 40;
  const rightX = 555;
  const drawHeader = () => {
    pdfDrawRow(
      doc,
      [
        { text: 'Code', x: startX, width: 70 },
        { text: 'Member', x: startX + 75, width: 235 },
        { text: 'In', x: startX + 315, width: 60 },
        { text: 'Out', x: startX + 380, width: 135, align: 'right' }
      ],
      { color: '#555555' }
    );
    doc.moveDown(0.3);
    doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#DDDDDD').stroke();
    doc.moveDown(0.5);
  };
  drawHeader();

  const fmt = (raw) => {
    const d = new Date(raw);
    if (Number.isNaN(d.getTime())) return String(raw ?? '');
    const hh = String(d.getHours()).padStart(2, '0');
    const mm = String(d.getMinutes()).padStart(2, '0');
    return `${hh}:${mm}`;
  };
  const redrawAttendanceHeader = () => {
    drawGymPdfHeader(doc, profile, { title: 'Attendance', subtitle: `Date: ${validDate}` });
    doc.moveDown(0.8);
    drawHeader();
  };
  for (const r of rows) {
    pdfDrawRow(
      doc,
      [
        { text: r.member_code ?? '', x: startX, width: 70 },
        { text: r.full_name ?? '', x: startX + 75, width: 235 },
        { text: fmt(r.checked_in_at), x: startX + 315, width: 60 },
        { text: r.checked_out_at ? fmt(r.checked_out_at) : '-', x: startX + 380, width: 135, align: 'right' }
      ],
      { onNewPage: redrawAttendanceHeader }
    );
  }

  doc.end();
});

app.get('/pdf/inventory.pdf', authMiddleware, requireRole('owner', 'admin', 'staff'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const profile = await loadGymProfileForTenant(tenantId);
  const rows = await queryMany(
    `SELECT p.name, p.sku, p.price, p.status,
            COALESCE(SUM(CASE WHEN sm.movement_type = 'in' THEN sm.qty ELSE -sm.qty END), 0) AS on_hand
     FROM products p
     LEFT JOIN stock_movements sm ON sm.tenant_id = p.tenant_id AND sm.product_id = p.id
     WHERE p.tenant_id = :tenantId
     GROUP BY p.id
     ORDER BY p.status DESC, p.name ASC
     LIMIT 500`,
    { tenantId }
  );

  const today = toDateOnly(new Date());
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="inventory_${today}.pdf"`);
  const doc = createBrandedPdf();
  doc.pipe(res);

  drawGymPdfHeader(doc, profile, { title: 'Inventory', subtitle: `Date: ${today}  •  Count: ${rows.length}` });
  doc.moveDown(0.8);

  const startX = 40;
  const rightX = 555;
  const drawHeader = () => {
    pdfDrawRow(
      doc,
      [
        { text: 'Item', x: startX, width: 230 },
        { text: 'SKU', x: startX + 235, width: 80 },
        { text: 'Price', x: startX + 320, width: 60, align: 'right' },
        { text: 'On Hand', x: startX + 385, width: 70, align: 'right' },
        { text: 'Status', x: startX + 460, width: 55, align: 'right' }
      ],
      { color: '#555555' }
    );
    doc.moveDown(0.3);
    doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#DDDDDD').stroke();
    doc.moveDown(0.5);
  };
  drawHeader();

  const redrawInventoryHeader = () => {
    drawGymPdfHeader(doc, profile, { title: 'Inventory', subtitle: `Date: ${today}` });
    doc.moveDown(0.8);
    drawHeader();
  };
  for (const r of rows) {
    pdfDrawRow(
      doc,
      [
        { text: r.name ?? '', x: startX, width: 230 },
        { text: r.sku ?? '-', x: startX + 235, width: 80 },
        { text: Number(r.price ?? 0).toFixed(2), x: startX + 320, width: 60, align: 'right' },
        { text: r.on_hand ?? 0, x: startX + 385, width: 70, align: 'right' },
        { text: r.status ?? '', x: startX + 460, width: 55, align: 'right' }
      ],
      { onNewPage: redrawInventoryHeader }
    );
  }

  doc.end();
});

app.get('/pdf/invoices.pdf', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const profile = await loadGymProfileForTenant(tenantId);
  const rows = await queryMany(
    `SELECT i.invoice_no, i.total, i.status, i.created_at, m.full_name, m.member_code
     FROM invoices i
     INNER JOIN members m ON m.id = i.member_id
     WHERE i.tenant_id = :tenantId
     ORDER BY i.id DESC
     LIMIT 500`,
    { tenantId }
  );

  const today = toDateOnly(new Date());
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="invoices_${today}.pdf"`);
  const doc = createBrandedPdf();
  doc.pipe(res);

  drawGymPdfHeader(doc, profile, { title: 'Invoices', subtitle: `Date: ${today}  •  Count: ${rows.length}` });
  doc.moveDown(0.8);

  const startX = 40;
  const rightX = 555;
  const drawHeader = () => {
    pdfDrawRow(
      doc,
      [
        { text: 'Invoice', x: startX, width: 110 },
        { text: 'Member', x: startX + 115, width: 230 },
        { text: 'Total', x: startX + 350, width: 60, align: 'right' },
        { text: 'Status', x: startX + 415, width: 45 },
        { text: 'Date', x: startX + 465, width: 50, align: 'right' }
      ],
      { color: '#555555' }
    );
    doc.moveDown(0.3);
    doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#DDDDDD').stroke();
    doc.moveDown(0.5);
  };
  drawHeader();

  const redrawInvoicesHeader = () => {
    drawGymPdfHeader(doc, profile, { title: 'Invoices', subtitle: `Date: ${today}` });
    doc.moveDown(0.8);
    drawHeader();
  };
  for (const r of rows) {
    pdfDrawRow(
      doc,
      [
        { text: r.invoice_no ?? '', x: startX, width: 110 },
        { text: `${r.full_name ?? ''} (${r.member_code ?? ''})`, x: startX + 115, width: 230 },
        { text: Number(r.total ?? 0).toFixed(2), x: startX + 350, width: 60, align: 'right' },
        { text: r.status ?? '', x: startX + 415, width: 45 },
        { text: fmtDateOnlyStr(r.created_at), x: startX + 465, width: 50, align: 'right' }
      ],
      { onNewPage: redrawInvoicesHeader }
    );
  }

  doc.end();
});

app.get('/pdf/invoice/:id.pdf', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const invoiceId = Number(req.params.id);
  if (!Number.isFinite(invoiceId) || invoiceId <= 0) return res.status(400).json({ error: 'invalid_request' });

  const profile = await loadGymProfileForTenant(tenantId);
  const inv = await invoiceRepo.getById(tenantId, invoiceId);
  if (!inv) return res.status(404).json({ error: 'invoice_not_found' });

  const money = (v) => Number(v ?? 0).toFixed(2);
  const today = toDateOnly(new Date());
  const safeNo = String(inv.invoice_no ?? invoiceId).replaceAll(/[^A-Za-z0-9_-]/g, '_');
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="invoice_${safeNo}_${today}.pdf"`);
  const doc = createBrandedPdf();
  doc.pipe(res);

  drawGymPdfHeader(doc, profile, {
    title: 'Invoice',
    subtitle: `Invoice: ${inv.invoice_no ?? ''}  •  Status: ${inv.status ?? ''}`
  });
  doc.moveDown(0.8);

  doc.fontSize(11).fillColor('#000000');
  doc.text(`Member: ${inv.member_name ?? ''} (${inv.member_code ?? ''})`);
  if (inv.phone) doc.text(`Phone: ${inv.phone}`);
  if (inv.email) doc.text(`Email: ${inv.email}`);
  doc.moveDown(0.3);
  doc.fillColor('#444444').fontSize(10);
  doc.text(`Created: ${fmtDateOnlyStr(inv.created_at)}   Due: ${fmtDateOnlyStr(inv.due_date)}`);
  doc.moveDown(0.8);

  doc.fillColor('#000000').fontSize(12).text('Summary', { underline: true });
  doc.moveDown(0.6);
  doc.fontSize(11);
  doc.text(`Subtotal: ${money(inv.subtotal)}`, { align: 'right' });
  doc.text(`Discount: ${money(inv.discount)}`, { align: 'right' });
  doc.text(`Tax: ${money(inv.tax)}`, { align: 'right' });
  doc.moveDown(0.2);
  doc.fontSize(13).text(`Total: ${money(inv.total)}`, { align: 'right' });
  doc.moveDown(1.2);
  doc.fontSize(10).fillColor('#666666').text('Thank you for your business.', { align: 'center' });

  doc.end();
});

app.get('/pdf/payments.pdf', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const profile = await loadGymProfileForTenant(tenantId);
  const rows = await queryMany(
    `SELECT i.invoice_no, p.amount, p.method, p.paid_at
     FROM payments p
     INNER JOIN invoices i ON i.id = p.invoice_id
     WHERE p.tenant_id = :tenantId
     ORDER BY p.id DESC
     LIMIT 500`,
    { tenantId }
  );

  const today = toDateOnly(new Date());
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="payments_${today}.pdf"`);
  const doc = createBrandedPdf();
  doc.pipe(res);

  drawGymPdfHeader(doc, profile, { title: 'Payments', subtitle: `Date: ${today}  •  Count: ${rows.length}` });
  doc.moveDown(0.8);

  const startX = 40;
  const rightX = 555;
  const drawHeader = () => {
    pdfDrawRow(
      doc,
      [
        { text: 'Invoice', x: startX, width: 150 },
        { text: 'Amount', x: startX + 155, width: 80, align: 'right' },
        { text: 'Method', x: startX + 240, width: 80 },
        { text: 'Paid At', x: startX + 325, width: 190, align: 'right' }
      ],
      { color: '#555555' }
    );
    doc.moveDown(0.3);
    doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#DDDDDD').stroke();
    doc.moveDown(0.5);
  };
  drawHeader();

  const redrawPaymentsHeader = () => {
    drawGymPdfHeader(doc, profile, { title: 'Payments', subtitle: `Date: ${today}` });
    doc.moveDown(0.8);
    drawHeader();
  };
  for (const r of rows) {
    pdfDrawRow(
      doc,
      [
        { text: r.invoice_no ?? '', x: startX, width: 150 },
        { text: Number(r.amount ?? 0).toFixed(2), x: startX + 155, width: 80, align: 'right' },
        { text: r.method ?? '', x: startX + 240, width: 80 },
        { text: fmtDateTimeShort(r.paid_at), x: startX + 325, width: 190, align: 'right' }
      ],
      { onNewPage: redrawPaymentsHeader }
    );
  }

  doc.end();
});

app.get('/pdf/reports.pdf', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const monthRaw = typeof req.query.month === 'string' ? req.query.month.trim() : '';
  const validMonth = /^\d{4}-\d{2}$/.test(monthRaw) ? monthRaw : toDateOnly(new Date()).slice(0, 7);
  const year = Number(validMonth.slice(0, 4));
  const month = Number(validMonth.slice(5, 7));
  const monthStart = new Date(year, month - 1, 1);
  const nextMonthStart = new Date(year, month, 1);
  const rangeStart = toDateOnly(monthStart);
  const rangeEnd = toDateOnly(new Date(year, month, 0));
  const rangeEndExclusive = toDateOnly(nextMonthStart);

  const profile = await loadGymProfileForTenant(tenantId);

  const money = (v) => Number(v ?? 0).toFixed(2);

  const paidInvoicesAgg = await queryOne(
    `SELECT COUNT(*) AS c, COALESCE(SUM(total), 0) AS s
     FROM invoices
     WHERE tenant_id = :tenantId
       AND status = 'paid'
       AND created_at >= :start
       AND created_at < :endExclusive`,
    { tenantId, start: rangeStart, endExclusive: rangeEndExclusive }
  );
  const unpaidInvoicesAgg = await queryOne(
    `SELECT COUNT(*) AS c, COALESCE(SUM(total), 0) AS s
     FROM invoices
     WHERE tenant_id = :tenantId
       AND status = 'unpaid'`,
    { tenantId }
  );
  const collectedAgg = await queryOne(
    `SELECT COALESCE(SUM(amount), 0) AS s
     FROM payments
     WHERE tenant_id = :tenantId
       AND paid_at >= :start
       AND paid_at < :endExclusive`,
    { tenantId, start: rangeStart, endExclusive: rangeEndExclusive }
  );
  const expensesAgg = await queryOne(
    `SELECT COALESCE(SUM(amount), 0) AS s
     FROM expenses
     WHERE tenant_id = :tenantId
       AND expense_date BETWEEN :start AND :end`,
    { tenantId, start: rangeStart, end: rangeEnd }
  );

  const paidInvoicesCount = Number(paidInvoicesAgg?.c ?? 0);
  const paidInvoicesTotal = Number(paidInvoicesAgg?.s ?? 0);
  const unpaidInvoicesCount = Number(unpaidInvoicesAgg?.c ?? 0);
  const unpaidInvoicesTotal = Number(unpaidInvoicesAgg?.s ?? 0);
  const collected = Number(collectedAgg?.s ?? 0);
  const expenses = Number(expensesAgg?.s ?? 0);
  const netProfit = Number((collected - expenses).toFixed(2));
  const marginPct = collected > 0 ? Number(((netProfit / collected) * 100).toFixed(2)) : 0;

  const revRows = await queryMany(
    `SELECT DATE(paid_at) AS d, COALESCE(SUM(amount), 0) AS s
     FROM payments
     WHERE tenant_id = :tenantId
       AND paid_at >= :start
       AND paid_at < :endExclusive
     GROUP BY DATE(paid_at)
     ORDER BY d ASC`,
    { tenantId, start: rangeStart, endExclusive: rangeEndExclusive }
  );
  const expRows = await queryMany(
    `SELECT expense_date AS d, COALESCE(SUM(amount), 0) AS s
     FROM expenses
     WHERE tenant_id = :tenantId
       AND expense_date BETWEEN :start AND :end
     GROUP BY expense_date
     ORDER BY d ASC`,
    { tenantId, start: rangeStart, end: rangeEnd }
  );
  const revenueMap = new Map(revRows.map((r) => [toDateOnly(new Date(r.d)), Number(r.s ?? 0)]));
  const expenseMap = new Map(expRows.map((r) => [fmtDateOnlyStr(r.d), Number(r.s ?? 0)]));

  const daily = [];
  for (let d = new Date(monthStart); d <= new Date(year, month, 0); d = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1)) {
    const key = toDateOnly(d);
    const revenue = Number(revenueMap.get(key) ?? 0);
    const expense = Number(expenseMap.get(key) ?? 0);
    const profit = Number((revenue - expense).toFixed(2));
    daily.push({ date: key, revenue, expense, profit });
  }

  const topExpenseCats = await queryMany(
    `SELECT category, COALESCE(SUM(amount), 0) AS s
     FROM expenses
     WHERE tenant_id = :tenantId
       AND expense_date BETWEEN :start AND :end
     GROUP BY category
     ORDER BY s DESC
     LIMIT 10`,
    { tenantId, start: rangeStart, end: rangeEnd }
  );

  const months = 3;
  const now = new Date();
  const curMonthStart = new Date(now.getFullYear(), now.getMonth(), 1);
  const addMonths = (d, n) => new Date(d.getFullYear(), d.getMonth() + n, 1);
  const ym = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;

  const firstMonthStart = addMonths(curMonthStart, -months);
  const histStart = toDateOnly(firstMonthStart);
  const histEndExclusive = toDateOnly(curMonthStart);

  const histRows = await queryMany(
    `SELECT DATE_FORMAT(paid_at, '%Y-%m') AS ym, COALESCE(SUM(amount), 0) AS s
     FROM payments
     WHERE tenant_id = :tenantId
       AND paid_at >= :start
       AND paid_at < :endExclusive
     GROUP BY DATE_FORMAT(paid_at, '%Y-%m')
     ORDER BY ym ASC`,
    { tenantId, start: histStart, endExclusive: histEndExclusive }
  );
  const histMap = new Map(histRows.map((r) => [String(r.ym), Number(r.s ?? 0)]));
  const history = [];
  for (let i = months; i >= 1; i -= 1) {
    const m = addMonths(curMonthStart, -i);
    const key = ym(m);
    history.push({ month: key, revenue: Number(histMap.get(key) ?? 0) });
  }
  const x = [1, 2, 3];
  const y = history.map((h) => Number(h.revenue ?? 0));
  const meanX = x.reduce((a, b) => a + b, 0) / x.length;
  const meanY = y.reduce((a, b) => a + b, 0) / y.length;
  let cov = 0;
  let varX = 0;
  for (let i = 0; i < x.length; i += 1) {
    cov += (x[i] - meanX) * (y[i] - meanY);
    varX += (x[i] - meanX) * (x[i] - meanX);
  }
  const slope = varX === 0 ? 0 : cov / varX;
  const intercept = meanY - slope * meanX;
  const predictedRaw = intercept + slope * 4;
  const predictedRevenue = Number(Math.max(0, predictedRaw).toFixed(2));
  const lastRevenue = Number(history[history.length - 1]?.revenue ?? 0);
  const delta = Number((predictedRevenue - lastRevenue).toFixed(2));
  const deltaPct = lastRevenue > 0 ? Number(((delta / lastRevenue) * 100).toFixed(2)) : (predictedRevenue > 0 ? 100 : 0);
  const predictedMonth = ym(curMonthStart);

  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="reports_${validMonth}.pdf"`);
  const doc = createBrandedPdf();
  doc.pipe(res);

  const subtitle = `Month: ${validMonth}  •  Range: ${rangeStart} → ${rangeEnd}`;
  drawObsidianGoldPdfHeader(doc, profile, { title: 'REPORTS', subtitle });

  const startX = 40;
  const rightX = 555;
  const gold = '#D4AF37';

  doc.fontSize(12).fillColor(gold).text('Executive Summary');
  doc.moveDown(0.3);
  doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#E6E6E6').stroke();
  doc.moveDown(0.6);

  const summaryRows = [
    ['Payments Collected (month)', money(collected)],
    ['Paid Invoices (month)', `${paidInvoicesCount}  •  ${money(paidInvoicesTotal)}`],
    ['Total Expenses (month)', money(expenses)],
    ['Net Profit (month)', `${money(netProfit)}  •  Margin: ${marginPct.toFixed(2)}%`],
    ['Unpaid Invoices (all)', `${unpaidInvoicesCount}  •  ${money(unpaidInvoicesTotal)}`]
  ];
  for (const r of summaryRows) {
    pdfDrawRow(
      doc,
      [
        { text: r[0], x: startX, width: 330 },
        { text: r[1], x: startX + 335, width: 180, align: 'right' }
      ],
      { rowHeight: 16, fontSize: 10 }
    );
  }

  doc.moveDown(0.9);
  doc.fontSize(12).fillColor(gold).text('Revenue Prediction (Next Month)');
  doc.moveDown(0.3);
  doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#E6E6E6').stroke();
  doc.moveDown(0.6);
  doc.fillColor('#000000').fontSize(10);
  doc.text(`Method: linear_regression  •  Basis: last 3 months (${histStart} → ${histEndExclusive})`);
  doc.text(`Prediction: ${predictedMonth}  •  ${money(predictedRevenue)}  •  Change: ${delta >= 0 ? '+' : ''}${money(delta)} (${delta >= 0 ? '+' : ''}${deltaPct.toFixed(2)}%)`);
  doc.moveDown(0.6);

  const drawHistHeader = () => {
    pdfDrawRow(
      doc,
      [
        { text: 'Month', x: startX, width: 120 },
        { text: 'Revenue', x: startX + 125, width: 140, align: 'right' }
      ],
      { color: '#555555' }
    );
    doc.moveDown(0.3);
    doc.moveTo(startX, doc.y).lineTo(startX + 265, doc.y).strokeColor('#DDDDDD').stroke();
    doc.moveDown(0.5);
  };
  const redrawHist = () => {
    drawObsidianGoldPdfHeader(doc, profile, { title: 'REPORTS', subtitle });
    doc.fontSize(12).fillColor(gold).text('Revenue Prediction (Next Month)');
    doc.moveDown(0.3);
    doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#E6E6E6').stroke();
    doc.moveDown(0.6);
    drawHistHeader();
  };
  drawHistHeader();
  for (const h of history) {
    pdfDrawRow(
      doc,
      [
        { text: h.month ?? '', x: startX, width: 120 },
        { text: money(h.revenue), x: startX + 125, width: 140, align: 'right' }
      ],
      { onNewPage: redrawHist }
    );
  }

  doc.moveDown(0.9);
  doc.fontSize(12).fillColor(gold).text('Top Expense Categories (Month)');
  doc.moveDown(0.3);
  doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#E6E6E6').stroke();
  doc.moveDown(0.6);

  const drawCatHeader = () => {
    pdfDrawRow(
      doc,
      [
        { text: 'Category', x: startX, width: 360 },
        { text: 'Amount', x: startX + 365, width: 150, align: 'right' }
      ],
      { color: '#555555' }
    );
    doc.moveDown(0.3);
    doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#DDDDDD').stroke();
    doc.moveDown(0.5);
  };
  const redrawCats = () => {
    drawObsidianGoldPdfHeader(doc, profile, { title: 'REPORTS', subtitle });
    doc.moveDown(0.2);
    doc.fontSize(12).fillColor(gold).text('Top Expense Categories (Month)');
    doc.moveDown(0.3);
    doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#E6E6E6').stroke();
    doc.moveDown(0.6);
    drawCatHeader();
  };
  drawCatHeader();
  if (!topExpenseCats.length) {
    doc.fillColor('#444444').fontSize(10).text('No expenses found in selected month.');
  } else {
    for (const r of topExpenseCats) {
      pdfDrawRow(
        doc,
        [
          { text: r.category ?? '', x: startX, width: 360 },
          { text: money(r.s), x: startX + 365, width: 150, align: 'right' }
        ],
        { onNewPage: redrawCats }
      );
    }
  }

  doc.moveDown(0.9);
  doc.fontSize(12).fillColor(gold).text('Daily Profit (Payments vs Expenses)');
  doc.moveDown(0.3);
  doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#E6E6E6').stroke();
  doc.moveDown(0.6);

  const drawDailyHeader = () => {
    pdfDrawRow(
      doc,
      [
        { text: 'Date', x: startX, width: 110 },
        { text: 'Revenue', x: startX + 115, width: 110, align: 'right' },
        { text: 'Expense', x: startX + 230, width: 110, align: 'right' },
        { text: 'Profit', x: startX + 345, width: 110, align: 'right' }
      ],
      { color: '#555555' }
    );
    doc.moveDown(0.3);
    doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#DDDDDD').stroke();
    doc.moveDown(0.5);
  };
  const redrawDaily = () => {
    drawObsidianGoldPdfHeader(doc, profile, { title: 'REPORTS', subtitle });
    doc.moveDown(0.2);
    doc.fontSize(12).fillColor(gold).text('Daily Profit (Payments vs Expenses)');
    doc.moveDown(0.3);
    doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#E6E6E6').stroke();
    doc.moveDown(0.6);
    drawDailyHeader();
  };
  drawDailyHeader();
  for (const r of daily) {
    pdfDrawRow(
      doc,
      [
        { text: r.date ?? '', x: startX, width: 110 },
        { text: money(r.revenue), x: startX + 115, width: 110, align: 'right' },
        { text: money(r.expense), x: startX + 230, width: 110, align: 'right' },
        { text: money(r.profit), x: startX + 345, width: 110, align: 'right' }
      ],
      { onNewPage: redrawDaily }
    );
  }

  doc.end();
});

app.get('/pdf/expenses.pdf', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const profile = await loadGymProfileForTenant(tenantId);
  const rows = await queryMany(
    `SELECT category, amount, expense_date, notes
     FROM expenses
     WHERE tenant_id = :tenantId
     ORDER BY id DESC
     LIMIT 500`,
    { tenantId }
  );

  const today = toDateOnly(new Date());
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="expenses_${today}.pdf"`);
  const doc = createBrandedPdf();
  doc.pipe(res);

  drawGymPdfHeader(doc, profile, { title: 'Expenses', subtitle: `Date: ${today}  •  Count: ${rows.length}` });
  doc.moveDown(0.8);

  const startX = 40;
  const rightX = 555;
  const drawHeader = () => {
    pdfDrawRow(
      doc,
      [
        { text: 'Category', x: startX, width: 200 },
        { text: 'Amount', x: startX + 205, width: 80, align: 'right' },
        { text: 'Date', x: startX + 290, width: 70 },
        { text: 'Notes', x: startX + 365, width: 150 }
      ],
      { color: '#555555' }
    );
    doc.moveDown(0.3);
    doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#DDDDDD').stroke();
    doc.moveDown(0.5);
  };
  drawHeader();

  const redrawExpensesHeader = () => {
    drawGymPdfHeader(doc, profile, { title: 'Expenses', subtitle: `Date: ${today}` });
    doc.moveDown(0.8);
    drawHeader();
  };
  for (const r of rows) {
    pdfDrawRow(
      doc,
      [
        { text: r.category ?? '', x: startX, width: 200 },
        { text: Number(r.amount ?? 0).toFixed(2), x: startX + 205, width: 80, align: 'right' },
        { text: fmtDateOnlyStr(r.expense_date), x: startX + 290, width: 70 },
        { text: r.notes ?? '', x: startX + 365, width: 150 }
      ],
      { onNewPage: redrawExpensesHeader }
    );
  }

  doc.end();
});

app.get('/pdf/staff.pdf', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const profile = await loadGymProfileForTenant(tenantId);
  const rows = await queryMany(
    `SELECT u.id, u.email, u.full_name, u.status
     FROM users u
     WHERE u.tenant_id = :tenantId
     ORDER BY u.id DESC
     LIMIT 500`,
    { tenantId }
  );
  const roles = await queryMany(
    `SELECT ur.user_id, r.name
     FROM user_roles ur
     INNER JOIN roles r ON r.id = ur.role_id
     INNER JOIN users u ON u.id = ur.user_id
     WHERE u.tenant_id = :tenantId
     ORDER BY ur.user_id ASC`,
    { tenantId }
  );
  const byUser = new Map();
  for (const r of roles) {
    const uid = Number(r.user_id);
    if (!byUser.has(uid)) byUser.set(uid, []);
    byUser.get(uid).push(String(r.name));
  }

  const today = toDateOnly(new Date());
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="staff_${today}.pdf"`);
  const doc = createBrandedPdf();
  doc.pipe(res);

  drawGymPdfHeader(doc, profile, { title: 'Staff', subtitle: `Date: ${today}  •  Count: ${rows.length}` });
  doc.moveDown(0.8);

  const startX = 40;
  const rightX = 555;
  const drawHeader = () => {
    pdfDrawRow(
      doc,
      [
        { text: 'Name', x: startX, width: 150 },
        { text: 'Email', x: startX + 155, width: 170 },
        { text: 'Roles', x: startX + 330, width: 130 },
        { text: 'Status', x: startX + 465, width: 50, align: 'right' }
      ],
      { color: '#555555' }
    );
    doc.moveDown(0.3);
    doc.moveTo(startX, doc.y).lineTo(rightX, doc.y).strokeColor('#DDDDDD').stroke();
    doc.moveDown(0.5);
  };
  drawHeader();

  const redrawStaffHeader = () => {
    drawGymPdfHeader(doc, profile, { title: 'Staff', subtitle: `Date: ${today}` });
    doc.moveDown(0.8);
    drawHeader();
  };
  for (const u of rows) {
    const roleList = (byUser.get(Number(u.id)) ?? []).join(', ');
    pdfDrawRow(
      doc,
      [
        { text: u.full_name ?? '', x: startX, width: 150 },
        { text: u.email ?? '', x: startX + 155, width: 170 },
        { text: roleList, x: startX + 330, width: 130 },
        { text: u.status ?? '', x: startX + 465, width: 50, align: 'right' }
      ],
      { onNewPage: redrawStaffHeader }
    );
  }

  doc.end();
});

app.get('/pdf/settings.pdf', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const tenantId = req.user.tenantId;
  const profile = await loadGymProfileForTenant(tenantId);
  const today = toDateOnly(new Date());

  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="settings_${today}.pdf"`);
  const doc = createBrandedPdf();
  doc.pipe(res);

  drawGymPdfHeader(doc, profile, { title: 'Gym Profile', subtitle: `Date: ${today}` });
  doc.moveDown(1.2);

  const rows = [
    ['Gym Name', profile?.gymName ?? ''],
    ['Address', profile?.address ?? ''],
    ['Website', profile?.websiteUrl ?? ''],
    ['Facebook', profile?.facebookUrl ?? ''],
    ['Instagram', profile?.instagramUrl ?? ''],
    ['WhatsApp', profile?.whatsapp ?? ''],
  ];
  for (const [k, v] of rows) {
    doc.fontSize(11).text(String(k), { continued: true });
    doc.text(String(v ?? ''), { align: 'right' });
    doc.moveDown(0.2);
  }

  doc.end();
});

app.post('/billing/auto-invoice', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const bodySchema = z.object({
    memberId: z.number().int().positive(),
    planId: z.number().int().positive().optional().nullable(),
    taxPercent: z.number().min(0).max(100).optional().default(5)
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });

  const tenantId = req.user.tenantId;
  const member = await queryOne(
    'SELECT id FROM members WHERE id = :id AND tenant_id = :tenantId',
    { id: parsed.data.memberId, tenantId }
  );
  if (!member) return res.status(404).json({ error: 'member_not_found' });

  let plan = null;
  if (parsed.data.planId) {
    plan = await queryOne(
      `SELECT id, price, admission_fee, status
       FROM membership_plans
       WHERE tenant_id = :tenantId AND id = :id`,
      { tenantId, id: parsed.data.planId }
    );
  } else {
    plan = await queryOne(
      `SELECT p.id, p.price, p.admission_fee, p.status
       FROM subscriptions s
       INNER JOIN membership_plans p ON p.id = s.plan_id
       WHERE s.tenant_id = :tenantId AND s.member_id = :memberId AND s.status = 'active'
       ORDER BY s.end_date DESC
       LIMIT 1`,
      { tenantId, memberId: parsed.data.memberId }
    );
  }

  if (!plan || plan.status !== 'active') return res.status(400).json({ error: 'invalid_plan' });

  const subtotal = Number(plan.price) + Number(plan.admission_fee ?? 0);
  const tax = Number(((subtotal * Number(parsed.data.taxPercent)) / 100).toFixed(2));
  const total = Number((subtotal + tax).toFixed(2));
  const invoiceNo = newInvoiceNo();
  const result = await execute(
    `INSERT INTO invoices (tenant_id, member_id, invoice_no, subtotal, discount, tax, total, status, due_date)
     VALUES (:tenantId, :memberId, :invoiceNo, :subtotal, 0, :tax, :total, 'unpaid', :dueDate)`,
    {
      tenantId,
      memberId: parsed.data.memberId,
      invoiceNo,
      subtotal,
      tax,
      total,
      dueDate: toDateOnly(new Date())
    }
  );
  return res.status(201).json({ id: Number(result.insertId), invoiceNo, subtotal, tax, total });
});

app.post('/invoices/mark-paid', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const bodySchema = z.object({
    invoiceId: z.number().int().positive(),
    method: z.enum(['cash', 'card', 'bank', 'online']).optional().default('cash')
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });

  const tenantId = req.user.tenantId;
  const invoice = await queryOne(
    'SELECT id, invoice_no, member_id, total, status FROM invoices WHERE id = :id AND tenant_id = :tenantId',
    { id: parsed.data.invoiceId, tenantId }
  );
  if (!invoice) return res.status(404).json({ error: 'invoice_not_found' });
  if (invoice.status === 'paid') return res.json({ ok: true, alreadyPaid: true });

  const connPool = await getPool();
  const conn = await connPool.getConnection();
  try {
    await conn.beginTransaction();
    await conn.execute(
      "UPDATE invoices SET status = 'paid' WHERE id = :id AND tenant_id = :tenantId",
      { id: parsed.data.invoiceId, tenantId }
    );
    await conn.execute(
      `INSERT INTO payments (tenant_id, invoice_id, amount, method, paid_at)
       VALUES (:tenantId, :invoiceId, :amount, :method, :paidAt)`,
      {
        tenantId,
        invoiceId: parsed.data.invoiceId,
        amount: Number(invoice.total),
        method: parsed.data.method,
        paidAt: toMysqlDateTime(new Date())
      }
    );
    await triggerAutomation(
      {
        tenantId,
        event: 'payment_received',
        memberId: Number(invoice.member_id),
        invoiceId: parsed.data.invoiceId,
        payload: { invoiceNo: invoice.invoice_no, amount: Number(invoice.total), method: parsed.data.method }
      },
      conn
    );
    await conn.commit();
    return res.json({ ok: true });
  } catch {
    await conn.rollback();
    return res.status(400).json({ error: 'mark_paid_failed' });
  } finally {
    conn.release();
  }
});

// Manual payment recording with ledger re-evaluation.
//   • Inserts a payment row against an open invoice.
//   • If the cumulative paid amount covers the total → invoice becomes 'paid'.
//   • Otherwise the invoice stays open (partially paid) and the balance shrinks.
app.post('/payments/record', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const bodySchema = z.object({
    invoiceId: z.number().int().positive(),
    amount: z.number().positive(),
    method: z.enum(['cash', 'card', 'bank', 'online']).optional().default('cash'),
    reference: z.string().trim().max(120).optional().nullable()
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });

  const tenantId = req.user.tenantId;
  const { invoiceId, amount, method } = parsed.data;
  const reference = parsed.data.reference?.length ? parsed.data.reference : null;

  const invoice = await queryOne(
    'SELECT id, invoice_no, member_id, total, status FROM invoices WHERE id = :id AND tenant_id = :tenantId',
    { id: invoiceId, tenantId }
  );
  if (!invoice) return res.status(404).json({ error: 'invoice_not_found' });
  if (invoice.status === 'paid') return res.status(400).json({ error: 'invoice_already_paid' });
  if (invoice.status === 'void') return res.status(400).json({ error: 'invoice_voided' });

  const total = Number(invoice.total);
  const paidRow = await queryOne(
    'SELECT COALESCE(SUM(amount), 0) AS s FROM payments WHERE tenant_id = :tenantId AND invoice_id = :invoiceId',
    { tenantId, invoiceId }
  );
  const paidSoFar = Number(paidRow?.s ?? 0);
  const balance = Math.max(0, total - paidSoFar);
  // Never record more than what is outstanding.
  const applied = Math.min(amount, balance > 0 ? balance : amount);
  if (applied <= 0) return res.status(400).json({ error: 'invoice_already_settled' });

  const newPaid = paidSoFar + applied;
  const fullyPaid = newPaid + 0.009 >= total; // float tolerance
  const newStatus = fullyPaid ? 'paid' : 'unpaid'; // stays open until covered

  const connPool = await getPool();
  const conn = await connPool.getConnection();
  try {
    await conn.beginTransaction();
    await conn.execute(
      `INSERT INTO payments (tenant_id, invoice_id, amount, method, reference, paid_at)
       VALUES (:tenantId, :invoiceId, :amount, :method, :reference, :paidAt)`,
      { tenantId, invoiceId, amount: applied, method, reference, paidAt: toMysqlDateTime(new Date()) }
    );
    if (newStatus !== invoice.status) {
      await conn.execute(
        'UPDATE invoices SET status = :status WHERE id = :id AND tenant_id = :tenantId',
        { status: newStatus, id: invoiceId, tenantId }
      );
    }
    if (fullyPaid) {
      await triggerAutomation(
        {
          tenantId,
          event: 'payment_received',
          memberId: Number(invoice.member_id),
          invoiceId,
          payload: { invoiceNo: invoice.invoice_no, amount: applied, method }
        },
        conn
      );
    }
    await conn.commit();
    return res.json({
      ok: true,
      status: newStatus,
      applied,
      paid: newPaid,
      balance: Math.max(0, total - newPaid)
    });
  } catch {
    await conn.rollback();
    return res.status(400).json({ error: 'record_payment_failed' });
  } finally {
    conn.release();
  }
});

app.post('/invoices', authMiddleware, requireRole('owner', 'admin'), async (req, res) => {
  const bodySchema = z.object({
    memberId: z.number().int().positive(),
    subtotal: z.number().positive(),
    discount: z.number().min(0).optional().default(0),
    tax: z.number().min(0).optional().default(0),
    dueDate: z.string().optional().nullable()
  });
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'invalid_request', details: parsed.error.flatten() });

  const member = await queryOne(
    'SELECT id FROM members WHERE id = :id AND tenant_id = :tenantId',
    { id: parsed.data.memberId, tenantId: req.user.tenantId }
  );
  if (!member) return res.status(404).json({ error: 'member_not_found' });

  const total = Number((parsed.data.subtotal - parsed.data.discount + parsed.data.tax).toFixed(2));
  const stamp = new Date().toISOString().slice(0, 10).replaceAll('-', '');
  const invoiceNo = `INV-${stamp}-${Math.random().toString(16).slice(2, 8).toUpperCase()}`;
  const result = await execute(
    `INSERT INTO invoices (tenant_id, member_id, invoice_no, subtotal, discount, tax, total, status, due_date)
     VALUES (:tenantId, :memberId, :invoiceNo, :subtotal, :discount, :tax, :total, 'unpaid', :dueDate)`,
    {
      tenantId: req.user.tenantId,
      memberId: parsed.data.memberId,
      invoiceNo,
      subtotal: parsed.data.subtotal,
      discount: parsed.data.discount,
      tax: parsed.data.tax,
      total,
      dueDate: parsed.data.dueDate ?? null
    }
  );
  return res.status(201).json({ id: Number(result.insertId), invoiceNo, total });
});

app.use((req, res) => res.status(404).json({ error: 'not_found' }));

const port = Number(process.env.PORT ?? 8081);
const host = process.env.HOST?.length ? process.env.HOST : '0.0.0.0';
app.listen(port, host, () => {
  process.stdout.write(`API listening on http://${host}:${port}\n`);
  process.stdout.write(`Build: ${buildStamp}\n`);
  process.stdout.write(`Version: http://localhost:${port}/__version\n`);
});
