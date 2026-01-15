const path = require('path');
const sqlite3 = require('sqlite3').verbose();

const dbPath = path.join(__dirname, 'data.sqlite');
const db = new sqlite3.Database(dbPath);

function setup() {
  db.serialize(() => {
    db.run(`
      CREATE TABLE IF NOT EXISTS services (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )
    `);

    db.run(`
      CREATE TABLE IF NOT EXISTS environments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )
    `);

    db.run(`
      CREATE TABLE IF NOT EXISTS schedules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        service_id INTEGER NOT NULL,
        environment_id INTEGER NOT NULL,
        scheduled_for TEXT NOT NULL,
        note TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(service_id) REFERENCES services(id),
        FOREIGN KEY(environment_id) REFERENCES environments(id)
      )
    `);

    db.run(`
      CREATE TABLE IF NOT EXISTS run_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        schedule_id INTEGER NOT NULL,
        executed_at TEXT NOT NULL,
        status TEXT NOT NULL,
        message TEXT NOT NULL,
        FOREIGN KEY(schedule_id) REFERENCES schedules(id)
      )
    `);

    const seedServices = db.prepare('INSERT OR IGNORE INTO services (name) VALUES (?)');
    ['Inventory API', 'Billing Worker', 'Customer Portal'].forEach((name) => seedServices.run(name));
    seedServices.finalize();

    const seedEnvironments = db.prepare('INSERT OR IGNORE INTO environments (name) VALUES (?)');
    ['Staging', 'QA', 'Production'].forEach((name) => seedEnvironments.run(name));
    seedEnvironments.finalize();
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
