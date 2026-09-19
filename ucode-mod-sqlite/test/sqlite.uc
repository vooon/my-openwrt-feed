// SPDX-License-Identifier: ISC
/*
 * Runtime smoke test for the ucode sqlite module (ucode-mod-sqlite).
 *
 * Exercises open()/exec()/query()/run()/prepare() plus the value mapping
 * (integers, doubles, booleans, nulls, JSON encoding, blobs) against an
 * in-memory database. No filesystem side effects.
 *
 * Run from CI with the upstream ucode modules plus the sqlite.so built from
 * this package on the module path:
 *   ucode -L <dir-with-upstream-and-sqlite.so> test/sqlite.uc
 */

import * as sqlite from 'sqlite';

let failures = 0;

function check(cond, msg) {
	if (!cond) {
		warn("FAIL: ", msg, "\n");
		failures++;
	}
}

check(sqlite.version() != null, "sqlite.version() returned null");
check(sqlite.libversion() != null, "sqlite.libversion() returned null");

let db = sqlite.open(':memory:');
check(db != null, "sqlite.open() failed");
if (db == null)
	exit(1);

check(db.exec(`
	CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, score REAL, active INTEGER);
	CREATE TABLE docs (id INTEGER PRIMARY KEY, payload TEXT);
`) == true, "db.exec() failed");

let r = db.run('INSERT INTO users (name, score, active) VALUES (?, ?, ?)', 'alice', 3.5, true);
check(r.changes == 1, "INSERT changes != 1");
check(r.last_insert_id == 1, "last_insert_id != 1");

r = db.run('INSERT INTO users (name, score, active) VALUES (:name, :score, :active)',
	{ name: 'bob', score: null, active: false });
check(r.last_insert_id == 2, "named insert last_insert_id != 2");

r = db.run('INSERT INTO users (name, score, active) VALUES (@name, @score, @active)',
	{ name: 'carol', score: 9.25, active: true });
check(r.last_insert_id == 3, "@-prefixed named insert failed");

r = db.run('INSERT INTO users (name, score, active) VALUES ($name, $score, $active)',
	{ name: 'dave', score: 0, active: null });
check(r.last_insert_id == 4, "$-prefixed named insert failed");

check(db.last_insert_id() == 4, "db.last_insert_id() != 4");

let rows = db.query('SELECT id, name, score, active FROM users ORDER BY id');
check(length(rows) == 4, "query returned wrong row count");

check(rows[0].id == 1 && rows[0].name == 'alice', "row 0 mismatch");
check(rows[0].score == 3.5, "row 0 score mismatch");
check(rows[0].active == 1, "row 0 active mismatch");
check(rows[1].score == null, "NULL score not mapped to null");
check(rows[1].active == 0, "false active not mapped to 0");
check(rows[2].score == 9.25, "row 2 score mismatch");
check(rows[3].active == null, "null active not mapped to null");

rows = db.query('SELECT ? AS a, ? AS b, ? AS c', [1, 'two', 3.0]);
check(rows[0].a == 1 && rows[0].b == 'two' && rows[0].c == 3.0, "array binding mismatch");

let payload = { key: 'value', list: [1, 2, 3] };
db.run('INSERT INTO docs (payload) VALUES (:payload)', { payload: payload });
rows = db.query('SELECT payload FROM docs WHERE id = 1');
check(rows[0].payload == '{ "key": "value", "list": [ 1, 2, 3 ] }', "object not JSON encoded");

db.run('INSERT INTO docs (payload) VALUES (:payload)', { payload: ['a', 'b'] });
rows = db.query('SELECT payload FROM docs WHERE id = 2');
check(rows[0].payload == '[ "a", "b" ]', "array not JSON encoded");

rows = db.query('SELECT zeroblob(3) AS blob');
check(length(rows[0].blob) == 3, "blob not mapped to a length-3 string");

r = db.run('UPDATE users SET score = score + 1 WHERE active = 1');
check(r.changes == 2, "UPDATE changes != 2");
check(db.changes() == 2, "db.changes() != 2");

let stmt = db.prepare('SELECT name FROM users WHERE id = ?');
check(stmt != null, "db.prepare() failed");
check(stmt.sql() == 'SELECT name FROM users WHERE id = ?', "stmt.sql() mismatch");
check(length(stmt.columns()) == 1 && stmt.columns()[0] == 'name', "stmt.columns() mismatch");

stmt.bind(2);
let row = stmt.step();
check(row != null && row.name == 'bob', "stmt.step() mismatch");
check(stmt.step() == null, "stmt.step() did not signal completion");

stmt.reset();
stmt.clear_bindings();
stmt.bind([3]);
check(stmt.all()[0].name == 'carol', "stmt.all() mismatch");

let srun = db.prepare('UPDATE users SET active = 1 WHERE name = ?');
srun.bind('dave');
r = srun.run();
check(r.changes == 1, "stmt.run() changes != 1");
check(srun.finalize() == true, "stmt.finalize() failed");

let closed_ok = false;
try {
	db.close();
	check(db.query('SELECT 1') == null, "query on closed db did not throw");
}
catch (e) {
	closed_ok = true;
}
check(closed_ok, "query on a closed database should raise");

if (failures) {
	warn(failures, " assertion(s) failed\n");
	exit(1);
}

print("sqlite module smoke test OK\n");
