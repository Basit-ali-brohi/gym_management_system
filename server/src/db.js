import mysql from 'mysql2/promise';

const requiredEnv = (key, fallback) => {
  const value = process.env[key];
  if (value && value.length > 0) return value;
  if (fallback !== undefined) return fallback;
  throw new Error(`Missing env var: ${key}`);
};

let _pool = null;
let _initPromise = null;

const createPoolWithHostAndPort = async (host, port) => {
  const pool = mysql.createPool({
    host,
    port,
    user: requiredEnv('DB_USER', 'root'),
    password: requiredEnv('DB_PASSWORD', ''),
    database: requiredEnv('DB_NAME', 'gym_saas'),
    waitForConnections: true,
    connectionLimit: Number(requiredEnv('DB_POOL_SIZE', '10')),
    namedPlaceholders: true,
    // Managed cloud MySQL (Railway, Aiven, PlanetScale, etc.) usually needs SSL.
    // Set DB_SSL=true in the host's env vars to enable it.
    ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : undefined
  });
  const conn = await pool.getConnection();
  try {
    await conn.ping();
  } finally {
    conn.release();
  }
  return pool;
};

export const getPool = async () => {
  if (_pool) return _pool;
  if (_initPromise) return _initPromise;

  const hostEnvRaw = process.env.DB_HOST?.trim();
  const hostEnvNormalized =
    hostEnvRaw === 'localhost' || hostEnvRaw === '::1' || hostEnvRaw === '[::1]' ? '127.0.0.1' : hostEnvRaw;
  const hostsToTry = hostEnvNormalized?.length ? [hostEnvNormalized] : ['127.0.0.1'];

  const portEnvRaw = process.env.DB_PORT?.trim();
  let portsToTry = [3306];
  if (portEnvRaw?.length) {
    const parsed = Number(portEnvRaw);
    if (!Number.isFinite(parsed) || parsed <= 0) throw new Error(`Invalid DB_PORT: ${portEnvRaw}`);
    portsToTry = [parsed];
  }

  _initPromise = (async () => {
    let lastError = null;
    for (const host of hostsToTry) {
      for (const port of portsToTry) {
        try {
          const pool = await createPoolWithHostAndPort(host, port);
          _pool = pool;
          return pool;
        } catch (e) {
          if (e?.code === 'ER_ACCESS_DENIED_ERROR') throw e;
          lastError = e;
        }
      }
    }
    throw lastError ?? new Error('db_connect_failed');
  })();

  try {
    return await _initPromise;
  } finally {
    _initPromise = null;
  }
};

export const queryOne = async (sql, params) => {
  const pool = await getPool();
  const [rows] = await pool.query(sql, params);
  if (!Array.isArray(rows) || rows.length === 0) return null;
  return rows[0];
};

export const queryMany = async (sql, params) => {
  const pool = await getPool();
  const [rows] = await pool.query(sql, params);
  return Array.isArray(rows) ? rows : [];
};

export const execute = async (sql, params) => {
  const pool = await getPool();
  const [result] = await pool.execute(sql, params);
  return result;
};
