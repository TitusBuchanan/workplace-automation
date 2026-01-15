const path = require('path');
const sqlite3 = require('sqlite3').verbose();
const bcrypt = require('bcryptjs');

const dbPath = path.join(__dirname, 'data.sqlite');
const db = new sqlite3.Database(dbPath);

function setup() {
  db.serialize(() => {
    db.run(`
      PRAGMA foreign_keys = ON;
    `);

    db.run(`
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        disabled INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    `);

    db.run(`
      CREATE TABLE IF NOT EXISTS password_resets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        token_hash TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        used_at TEXT,
        request_ip TEXT,
        request_ua TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id)
      )
    `);

    db.run(`
      CREATE INDEX IF NOT EXISTS idx_password_resets_token_hash
      ON password_resets(token_hash)
    `);

    db.run(`
      CREATE TABLE IF NOT EXISTS outbox_emails (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        to_address TEXT NOT NULL,
        subject TEXT NOT NULL,
        body TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    `);

    db.run(`
      CREATE TABLE IF NOT EXISTS audit_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        user_id INTEGER,
        ip TEXT,
        ua TEXT,
        details_json TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id)
      )
    `);

    const now = new Date().toISOString();
    const demoEmail = 'demo.user@company.test';
    const demoDisplayName = 'Demo User';
    const demoPassword = 'ChangeMe123!ChangeMe123!';
    const demoHash = bcrypt.hashSync(demoPassword, 12);

    db.run(
      `
      INSERT OR IGNORE INTO users (email, display_name, password_hash, disabled, created_at, updated_at)
      VALUES (?, ?, ?, 0, ?, ?)
      `,
      [demoEmail, demoDisplayName, demoHash, now, now],
    );

    const extraSeedEmail = String(process.env.SEED_USER_EMAIL || '').trim().toLowerCase();
    if (extraSeedEmail) {
      const extraSeedName = String(process.env.SEED_USER_NAME || 'Seeded User').trim() || 'Seeded User';
      const extraSeedPassword = String(process.env.SEED_USER_PASSWORD || 'ChangeMe123!ChangeMe123!');
      const extraHash = bcrypt.hashSync(extraSeedPassword, 12);
      db.run(
        `
        INSERT OR IGNORE INTO users (email, display_name, password_hash, disabled, created_at, updated_at)
        VALUES (?, ?, ?, 0, ?, ?)
        `,
        [extraSeedEmail, extraSeedName, extraHash, now, now],
      );
    }
  });
}

setup();

function run(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.run(sql, params, function callback(err) {
      if (err) {
        reject(err);
        return;
      }
      resolve({ id: this.lastID, changes: this.changes });
    });
  });
}

function get(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.get(sql, params, (err, row) => {
      if (err) {
        reject(err);
        return;
      }
      resolve(row);
    });
  });
}

function all(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.all(sql, params, (err, rows) => {
      if (err) {
        reject(err);
        return;
      }
      resolve(rows);
    });
  });
}

module.exports = {
  db,
  run,
  get,
  all,
};
