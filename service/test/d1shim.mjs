// A small D1-compatible wrapper over node:sqlite for tests: the same
// prepare().bind().first()/all()/run() and batch() surface the Worker uses.
import { DatabaseSync } from 'node:sqlite';
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const MIG = join(dirname(fileURLToPath(import.meta.url)), '..', 'migrations');

class Stmt {
  constructor(db, sql) {
    this.db = db;
    this.sql = sql;
    this.args = [];
  }
  bind(...a) {
    this.args = a.map((v) => (v === undefined ? null : typeof v === 'boolean' ? (v ? 1 : 0) : v));
    return this;
  }
  async first() {
    const r = this.db.prepare(this.sql).get(...this.args);
    return r === undefined ? null : { ...r };
  }
  async all() {
    return { results: this.db.prepare(this.sql).all(...this.args).map((r) => ({ ...r })), success: true };
  }
  async run() {
    const r = this.db.prepare(this.sql).run(...this.args);
    return { success: true, meta: { changes: r.changes, last_row_id: Number(r.lastInsertRowid) } };
  }
  _runSync() {
    return this.db.prepare(this.sql).run(...this.args);
  }
}

export class D1Shim {
  constructor() {
    this.db = new DatabaseSync(':memory:');
    this.db.exec('PRAGMA foreign_keys = ON');
    for (const f of readdirSync(MIG).filter((x) => x.endsWith('.sql')).sort()) {
      this.db.exec(readFileSync(join(MIG, f), 'utf8'));
    }
  }
  prepare(sql) {
    return new Stmt(this.db, sql);
  }
  // D1 batches run as one transaction: all or nothing
  async batch(stmts) {
    this.db.exec('BEGIN');
    try {
      const out = stmts.map((s) => s._runSync());
      this.db.exec('COMMIT');
      return out.map((r) => ({ success: true, meta: { changes: r.changes } }));
    } catch (e) {
      this.db.exec('ROLLBACK');
      throw e;
    }
  }
}
