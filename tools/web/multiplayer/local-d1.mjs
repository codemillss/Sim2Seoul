/** Local-only SQLite adapter for exercising D1-compatible SQL. No credentials. */
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";

class LocalStatement {
  constructor(db, sql, values = []) { this.db = db; this.sql = sql; this.values = values; }
  bind(...values) { return new LocalStatement(this.db, this.sql, values); }
  async first() { return this.db.prepare(this.sql).get(...this.values) ?? null; }
  async all() { return { results: this.db.prepare(this.sql).all(...this.values), success: true }; }
  runSync() {
    const result = this.db.prepare(this.sql).run(...this.values);
    return { success: true, meta: { changes: Number(result.changes) } };
  }
  async run() { return this.runSync(); }
}

export function createLocalD1() {
  const sqlite = new DatabaseSync(":memory:");
  sqlite.exec("PRAGMA foreign_keys = ON");
  sqlite.exec(readFileSync(new URL("./schema.sql", import.meta.url), "utf8"));
  return {
    sqlite,
    prepare(sql) { return new LocalStatement(sqlite, sql); },
    async batch(statements) {
      sqlite.exec("BEGIN IMMEDIATE");
      try {
        const result = statements.map(statement => statement.runSync());
        sqlite.exec("COMMIT");
        return result;
      } catch (error) {
        sqlite.exec("ROLLBACK");
        throw error;
      }
    },
    close() { sqlite.close(); },
  };
}
