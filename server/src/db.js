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
    namedPlaceholders: true
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

  const hostEnv = process.env.DB_HOST?.trim();
  const hostsToTry = hostEnv?.length ? [hostEnv] : ['localhost', '127.0.0.1', '::1'];
  const portEnv = process.env.DB_PORT?.trim();
  const portsToTry = portEnv?.length ? [Number(portEnv)] : [3306, 3307];

  _initPromise = (async () => {
    let lastError = null;
    for (const host of hostsToTry) {
      for (const port of portsToTry) {
        try {
          const pool = await createPoolWithHostAndPort(host, port);
          _pool = pool;
          return pool;
        } catch (e) {
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
