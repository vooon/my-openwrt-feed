// SPDX-License-Identifier: ISC
/*
 * ucode sqlite module
 *
 * Thin binding of the SQLite3 C API to ucode so scripts can open databases,
 * execute statements and prepared queries without shelling out to the
 * sqlite3 CLI.
 *
 * Values are mapped between the two worlds as follows:
 *
 *   ucode -> SQLite:
 *     null        -> NULL
 *     boolean     -> integer 0/1
 *     integer     -> INTEGER
 *     double      -> REAL
 *     string      -> TEXT
 *     array/object-> TEXT (JSON encoded)
 *
 *   SQLite -> ucode:
 *     NULL        -> null
 *     INTEGER     -> integer
 *     REAL        -> double
 *     TEXT        -> string
 *     BLOB        -> string (binary safe)
 *
 * Prepared statement parameters may be bound positionally (`?`) by passing
 * the values either as separate arguments or as a single array, or by name
 * (`:name`, `@name`, `$name`) by passing a single object.
 */

#include <ucode/module.h>

#include <sqlite3.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
	sqlite3 *handle;
} uc_sqlite_db_t;

typedef struct {
	sqlite3_stmt *stmt;
} uc_sqlite_stmt_t;

static uc_resource_type_t *db_type, *stmt_type;

static void
db_free(void *ud)
{
	uc_sqlite_db_t *db = ud;

	if (!db)
		return;

	if (db->handle)
		sqlite3_close_v2(db->handle);

	free(db);
}

static void
stmt_free(void *ud)
{
	uc_sqlite_stmt_t *stmt = ud;

	if (!stmt)
		return;

	if (stmt->stmt)
		sqlite3_finalize(stmt->stmt);

	free(stmt);
}

static uc_value_t *
raise_db_error(uc_vm_t *vm, sqlite3 *db, int rc)
{
	uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "SQLite error: %s",
		db ? sqlite3_errmsg(db) : sqlite3_errstr(rc));

	return NULL;
}

static bool
raise_stmt_error(uc_vm_t *vm, sqlite3_stmt *stmt, int rc)
{
	raise_db_error(vm, sqlite3_db_handle(stmt), rc);

	return false;
}

static uc_sqlite_db_t *
get_db(uc_vm_t *vm)
{
	uc_sqlite_db_t *db = uc_fn_thisval("sqlite.db");

	if (!db || !db->handle) {
		uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "Database is not open");
		return NULL;
	}

	return db;
}

static uc_sqlite_stmt_t *
get_stmt(uc_vm_t *vm)
{
	uc_sqlite_stmt_t *stmt = uc_fn_thisval("sqlite.stmt");

	if (!stmt || !stmt->stmt) {
		uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "Statement is not prepared");
		return NULL;
	}

	return stmt;
}

static int
bind_value(uc_vm_t *vm, sqlite3_stmt *stmt, int index, uc_value_t *val)
{
	char *json;
	int rc;

	switch (ucv_type(val)) {
	case UC_NULL:
		return sqlite3_bind_null(stmt, index);

	case UC_BOOLEAN:
		return sqlite3_bind_int(stmt, index, ucv_boolean_get(val) ? 1 : 0);

	case UC_INTEGER:
		return sqlite3_bind_int64(stmt, index, ucv_int64_get(val));

	case UC_DOUBLE:
		return sqlite3_bind_double(stmt, index, ucv_double_get(val));

	case UC_STRING:
		return sqlite3_bind_text(stmt, index, ucv_string_get(val),
			(int)ucv_string_length(val), SQLITE_TRANSIENT);

	case UC_ARRAY:
	case UC_OBJECT:
		json = ucv_to_jsonstring(vm, val);
		if (!json)
			return SQLITE_NOMEM;

		rc = sqlite3_bind_text(stmt, index, json, -1, SQLITE_TRANSIENT);
		free(json);

		return rc;

	default:
		return sqlite3_bind_null(stmt, index);
	}
}

static bool
bind_args(uc_vm_t *vm, sqlite3_stmt *stmt, size_t nargs, size_t first)
{
	size_t nparams = nargs > first ? nargs - first : 0;
	uc_value_t *arg0 = nparams ? uc_fn_arg(first) : NULL;
	int rc;

	if (nparams == 1 && ucv_type(arg0) == UC_ARRAY) {
		size_t count = ucv_array_length(arg0);

		for (size_t i = 0; i < count; i++) {
			rc = bind_value(vm, stmt, (int)i + 1, ucv_array_get(arg0, i));
			if (rc != SQLITE_OK)
				return raise_stmt_error(vm, stmt, rc);
		}

		return true;
	}

	if (nparams == 1 && ucv_type(arg0) == UC_OBJECT) {
		int count = sqlite3_bind_parameter_count(stmt);

		for (int i = 1; i <= count; i++) {
			const char *name = sqlite3_bind_parameter_name(stmt, i);
			const char *key;
			bool found = false;
			uc_value_t *val;

			if (!name)
				continue;

			key = name;
			if (*key == ':' || *key == '@' || *key == '$')
				key++;

			val = ucv_object_get(arg0, key, &found);
			if (!found)
				continue;

			rc = bind_value(vm, stmt, i, val);
			if (rc != SQLITE_OK)
				return raise_stmt_error(vm, stmt, rc);
		}

		return true;
	}

	for (size_t i = 0; i < nparams; i++) {
		rc = bind_value(vm, stmt, (int)i + 1, uc_fn_arg(first + i));
		if (rc != SQLITE_OK)
			return raise_stmt_error(vm, stmt, rc);
	}

	return true;
}

static uc_value_t *
column_value(sqlite3_stmt *stmt, int col)
{
	switch (sqlite3_column_type(stmt, col)) {
	case SQLITE_INTEGER:
		return ucv_int64_new(sqlite3_column_int64(stmt, col));

	case SQLITE_FLOAT:
		return ucv_double_new(sqlite3_column_double(stmt, col));

	case SQLITE_TEXT:
		return ucv_string_new_length((const char *)sqlite3_column_text(stmt, col),
			(size_t)sqlite3_column_bytes(stmt, col));

	case SQLITE_BLOB:
		return ucv_string_new_length(sqlite3_column_blob(stmt, col),
			(size_t)sqlite3_column_bytes(stmt, col));

	default:
		return NULL;
	}
}

static uc_value_t *
row_object(uc_vm_t *vm, sqlite3_stmt *stmt)
{
	uc_value_t *row = ucv_object_new(vm);
	int count = sqlite3_column_count(stmt);

	for (int i = 0; i < count; i++) {
		const char *name = sqlite3_column_name(stmt, i);

		ucv_object_add(row, name ? name : "", column_value(stmt, i));
	}

	return row;
}

static uc_value_t *
result_info(uc_vm_t *vm, sqlite3 *db)
{
	uc_value_t *res = ucv_object_new(vm);

	ucv_object_add(res, "changes", ucv_int64_new(sqlite3_changes(db)));
	ucv_object_add(res, "last_insert_id", ucv_int64_new(sqlite3_last_insert_rowid(db)));

	return res;
}

static sqlite3_stmt *
prepare(uc_vm_t *vm, sqlite3 *db, uc_value_t *sql)
{
	sqlite3_stmt *stmt = NULL;
	int rc;

	if (ucv_type(sql) != UC_STRING) {
		uc_vm_raise_exception(vm, EXCEPTION_TYPE, "Invalid SQL statement");
		return NULL;
	}

	rc = sqlite3_prepare_v2(db, ucv_string_get(sql), -1, &stmt, NULL);
	if (rc != SQLITE_OK) {
		raise_db_error(vm, db, rc);
		return NULL;
	}

	return stmt;
}

/* sqlite.version() -> the SQLite version the module was compiled against */
static uc_value_t *
uc_sqlite_version(uc_vm_t *vm, size_t nargs)
{
	return ucv_string_new(SQLITE_VERSION);
}

/* sqlite.libversion() -> the runtime SQLite library version */
static uc_value_t *
uc_sqlite_libversion(uc_vm_t *vm, size_t nargs)
{
	return ucv_string_new(sqlite3_libversion());
}

/* sqlite.open(path[, flags[, vfs]]) -> db */
static uc_value_t *
uc_sqlite_open(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *pathv = uc_fn_arg(0);
	uc_value_t *flagsv = uc_fn_arg(1);
	uc_value_t *vfsv = uc_fn_arg(2);
	const char *vfs = NULL;
	uc_sqlite_db_t *db;
	sqlite3 *handle;
	int flags, rc;

	if (ucv_type(pathv) != UC_STRING) {
		uc_vm_raise_exception(vm, EXCEPTION_TYPE, "Invalid database path");
		return NULL;
	}

	flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE;

	if (ucv_type(flagsv) == UC_INTEGER)
		flags = (int)ucv_int64_get(flagsv);
	else if (ucv_type(flagsv) != UC_NULL) {
		uc_vm_raise_exception(vm, EXCEPTION_TYPE, "Invalid open flags");
		return NULL;
	}

	if (ucv_type(vfsv) == UC_STRING)
		vfs = ucv_string_get(vfsv);
	else if (ucv_type(vfsv) != UC_NULL) {
		uc_vm_raise_exception(vm, EXCEPTION_TYPE, "Invalid VFS name");
		return NULL;
	}

	rc = sqlite3_open_v2(ucv_string_get(pathv), &handle, flags, vfs);
	if (rc != SQLITE_OK) {
		if (handle) {
			raise_db_error(vm, handle, rc);
			sqlite3_close_v2(handle);
		}
		else {
			raise_db_error(vm, NULL, rc);
		}

		return NULL;
	}

	db = calloc(1, sizeof(*db));
	if (!db) {
		sqlite3_close_v2(handle);
		uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "Out of memory");
		return NULL;
	}

	db->handle = handle;

	return ucv_resource_new(db_type, db);
}

/* db.exec(sql) -> true */
static uc_value_t *
uc_sqlite_db_exec(uc_vm_t *vm, size_t nargs)
{
	uc_sqlite_db_t *db = get_db(vm);
	uc_value_t *sqlv = uc_fn_arg(0);
	char *errmsg = NULL;
	int rc;

	if (!db)
		return NULL;

	if (ucv_type(sqlv) != UC_STRING) {
		uc_vm_raise_exception(vm, EXCEPTION_TYPE, "Invalid SQL statement");
		return NULL;
	}

	rc = sqlite3_exec(db->handle, ucv_string_get(sqlv), NULL, NULL, &errmsg);
	if (rc != SQLITE_OK) {
		uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "SQLite error: %s",
			errmsg ? errmsg : sqlite3_errmsg(db->handle));
		sqlite3_free(errmsg);
		return NULL;
	}

	sqlite3_free(errmsg);

	return ucv_boolean_new(true);
}

/* db.query(sql, ...params) -> [ { column: value, ... }, ... ] */
static uc_value_t *
uc_sqlite_db_query(uc_vm_t *vm, size_t nargs)
{
	uc_sqlite_db_t *db = get_db(vm);
	sqlite3_stmt *stmt;
	uc_value_t *rows;
	int rc;

	if (!db)
		return NULL;

	stmt = prepare(vm, db->handle, uc_fn_arg(0));
	if (!stmt)
		return NULL;

	if (!bind_args(vm, stmt, nargs, 1)) {
		sqlite3_finalize(stmt);
		return NULL;
	}

	rows = ucv_array_new(vm);

	for (;;) {
		rc = sqlite3_step(stmt);

		if (rc == SQLITE_ROW) {
			ucv_array_push(rows, row_object(vm, stmt));
			continue;
		}

		if (rc == SQLITE_DONE)
			break;

		sqlite3_finalize(stmt);
		ucv_put(rows);

		return raise_db_error(vm, db->handle, rc);
	}

	sqlite3_finalize(stmt);

	return rows;
}

/* db.run(sql, ...params) -> { changes, last_insert_id } */
static uc_value_t *
uc_sqlite_db_run(uc_vm_t *vm, size_t nargs)
{
	uc_sqlite_db_t *db = get_db(vm);
	sqlite3_stmt *stmt;
	uc_value_t *res;
	int rc;

	if (!db)
		return NULL;

	stmt = prepare(vm, db->handle, uc_fn_arg(0));
	if (!stmt)
		return NULL;

	if (!bind_args(vm, stmt, nargs, 1)) {
		sqlite3_finalize(stmt);
		return NULL;
	}

	while ((rc = sqlite3_step(stmt)) == SQLITE_ROW)
		;

	if (rc != SQLITE_DONE) {
		sqlite3_finalize(stmt);

		return raise_db_error(vm, db->handle, rc);
	}

	res = result_info(vm, db->handle);
	sqlite3_finalize(stmt);

	return res;
}

/* db.prepare(sql) -> stmt */
static uc_value_t *
uc_sqlite_db_prepare(uc_vm_t *vm, size_t nargs)
{
	uc_sqlite_db_t *db = get_db(vm);
	uc_sqlite_stmt_t *wrapper;
	sqlite3_stmt *stmt;

	if (!db)
		return NULL;

	stmt = prepare(vm, db->handle, uc_fn_arg(0));
	if (!stmt)
		return NULL;

	wrapper = calloc(1, sizeof(*wrapper));
	if (!wrapper) {
		sqlite3_finalize(stmt);
		uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "Out of memory");
		return NULL;
	}

	wrapper->stmt = stmt;

	return ucv_resource_new(stmt_type, wrapper);
}

/* db.last_insert_id() -> integer */
static uc_value_t *
uc_sqlite_db_last_insert_id(uc_vm_t *vm, size_t nargs)
{
	uc_sqlite_db_t *db = get_db(vm);

	if (!db)
		return NULL;

	return ucv_int64_new(sqlite3_last_insert_rowid(db->handle));
}

/* db.changes() -> integer */
static uc_value_t *
uc_sqlite_db_changes(uc_vm_t *vm, size_t nargs)
{
	uc_sqlite_db_t *db = get_db(vm);

	if (!db)
		return NULL;

	return ucv_int64_new(sqlite3_changes(db->handle));
}

/* db.busy_timeout(ms) -> true */
static uc_value_t *
uc_sqlite_db_busy_timeout(uc_vm_t *vm, size_t nargs)
{
	uc_sqlite_db_t *db = get_db(vm);
	uc_value_t *msv = uc_fn_arg(0);
	int rc;

	if (!db)
		return NULL;

	if (ucv_type(msv) != UC_INTEGER) {
		uc_vm_raise_exception(vm, EXCEPTION_TYPE, "Invalid timeout");
		return NULL;
	}

	rc = sqlite3_busy_timeout(db->handle, (int)ucv_int64_get(msv));
	if (rc != SQLITE_OK)
		return raise_db_error(vm, db->handle, rc);

	return ucv_boolean_new(true);
}

/* db.close() -> true */
static uc_value_t *
uc_sqlite_db_close(uc_vm_t *vm, size_t nargs)
{
	uc_sqlite_db_t *db = uc_fn_thisval("sqlite.db");

	if (!db || !db->handle) {
		uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "Database is not open");
		return NULL;
	}

	sqlite3_close_v2(db->handle);
	db->handle = NULL;

	return ucv_boolean_new(true);
}

/* stmt.bind(...params) -> true */
static uc_value_t *
uc_sqlite_stmt_bind(uc_vm_t *vm, size_t nargs)
{
	uc_sqlite_stmt_t *stmt = get_stmt(vm);

	if (!stmt)
		return NULL;

	if (!bind_args(vm, stmt->stmt, nargs, 0))
		return NULL;

	return ucv_boolean_new(true);
}

/* stmt.reset() -> true */
static uc_value_t *
uc_sqlite_stmt_reset(uc_vm_t *vm, size_t nargs)
{
	uc_sqlite_stmt_t *stmt = get_stmt(vm);
	int rc;

	if (!stmt)
		return NULL;

	rc = sqlite3_reset(stmt->stmt);
	if (rc != SQLITE_OK)
		return raise_db_error(vm, sqlite3_db_handle(stmt->stmt), rc);

	return ucv_boolean_new(true);
}

/* stmt.clear_bindings() -> true */
static uc_value_t *
uc_sqlite_stmt_clear_bindings(uc_vm_t *vm, size_t nargs)
{
	uc_sqlite_stmt_t *stmt = get_stmt(vm);
	int rc;

	if (!stmt)
		return NULL;

	rc = sqlite3_clear_bindings(stmt->stmt);
	if (rc != SQLITE_OK)
		return raise_db_error(vm, sqlite3_db_handle(stmt->stmt), rc);

	return ucv_boolean_new(true);
}

/* stmt.step() -> row object, or null once the statement is done */
static uc_value_t *
uc_sqlite_stmt_step(uc_vm_t *vm, size_t nargs)
{
	uc_sqlite_stmt_t *stmt = get_stmt(vm);
	int rc;

	if (!stmt)
		return NULL;

	rc = sqlite3_step(stmt->stmt);

	if (rc == SQLITE_ROW)
		return row_object(vm, stmt->stmt);

	if (rc == SQLITE_DONE)
		return NULL;

	return raise_db_error(vm, sqlite3_db_handle(stmt->stmt), rc);
}

/* stmt.all() -> [ row, ... ] */
static uc_value_t *
uc_sqlite_stmt_all(uc_vm_t *vm, size_t nargs)
{
	uc_sqlite_stmt_t *stmt = get_stmt(vm);
	uc_value_t *rows;
	int rc;

	if (!stmt)
		return NULL;

	rows = ucv_array_new(vm);

	for (;;) {
		rc = sqlite3_step(stmt->stmt);

		if (rc == SQLITE_ROW) {
			ucv_array_push(rows, row_object(vm, stmt->stmt));
			continue;
		}

		if (rc == SQLITE_DONE)
			break;

		ucv_put(rows);

		return raise_db_error(vm, sqlite3_db_handle(stmt->stmt), rc);
	}

	return rows;
}

/* stmt.run() -> { changes, last_insert_id } */
static uc_value_t *
uc_sqlite_stmt_run(uc_vm_t *vm, size_t nargs)
{
	uc_sqlite_stmt_t *stmt = get_stmt(vm);
	int rc;

	if (!stmt)
		return NULL;

	while ((rc = sqlite3_step(stmt->stmt)) == SQLITE_ROW)
		;

	if (rc != SQLITE_DONE)
		return raise_db_error(vm, sqlite3_db_handle(stmt->stmt), rc);

	return result_info(vm, sqlite3_db_handle(stmt->stmt));
}

/* stmt.columns() -> [ name, ... ] */
static uc_value_t *
uc_sqlite_stmt_columns(uc_vm_t *vm, size_t nargs)
{
	uc_sqlite_stmt_t *stmt = get_stmt(vm);
	uc_value_t *cols;
	int count;

	if (!stmt)
		return NULL;

	count = sqlite3_column_count(stmt->stmt);
	cols = ucv_array_new(vm);

	for (int i = 0; i < count; i++) {
		const char *name = sqlite3_column_name(stmt->stmt, i);

		ucv_array_push(cols, ucv_string_new(name ? name : ""));
	}

	return cols;
}

/* stmt.sql() -> the SQL text the statement was prepared from */
static uc_value_t *
uc_sqlite_stmt_sql(uc_vm_t *vm, size_t nargs)
{
	uc_sqlite_stmt_t *stmt = get_stmt(vm);
	const char *sql;

	if (!stmt)
		return NULL;

	sql = sqlite3_sql(stmt->stmt);

	return ucv_string_new(sql ? sql : "");
}

/* stmt.finalize() -> true */
static uc_value_t *
uc_sqlite_stmt_finalize(uc_vm_t *vm, size_t nargs)
{
	uc_sqlite_stmt_t *stmt = uc_fn_thisval("sqlite.stmt");

	if (!stmt || !stmt->stmt) {
		uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "Statement is not prepared");
		return NULL;
	}

	sqlite3_finalize(stmt->stmt);
	stmt->stmt = NULL;

	return ucv_boolean_new(true);
}

static const uc_function_list_t global_fns[] = {
	{ "version",	uc_sqlite_version },
	{ "libversion",	uc_sqlite_libversion },
	{ "open",	uc_sqlite_open },
};

static const uc_function_list_t db_fns[] = {
	{ "exec",		uc_sqlite_db_exec },
	{ "query",		uc_sqlite_db_query },
	{ "run",		uc_sqlite_db_run },
	{ "prepare",		uc_sqlite_db_prepare },
	{ "last_insert_id",	uc_sqlite_db_last_insert_id },
	{ "changes",		uc_sqlite_db_changes },
	{ "busy_timeout",	uc_sqlite_db_busy_timeout },
	{ "close",		uc_sqlite_db_close },
};

static const uc_function_list_t stmt_fns[] = {
	{ "bind",		uc_sqlite_stmt_bind },
	{ "reset",		uc_sqlite_stmt_reset },
	{ "clear_bindings",	uc_sqlite_stmt_clear_bindings },
	{ "step",		uc_sqlite_stmt_step },
	{ "all",		uc_sqlite_stmt_all },
	{ "run",		uc_sqlite_stmt_run },
	{ "columns",		uc_sqlite_stmt_columns },
	{ "sql",		uc_sqlite_stmt_sql },
	{ "finalize",		uc_sqlite_stmt_finalize },
};

static void
register_constants(uc_value_t *scope)
{
	static const struct {
		const char *name;
		int value;
	} constants[] = {
		{ "OPEN_READONLY",	SQLITE_OPEN_READONLY },
		{ "OPEN_READWRITE",	SQLITE_OPEN_READWRITE },
		{ "OPEN_CREATE",	SQLITE_OPEN_CREATE },
		{ "OPEN_URI",		SQLITE_OPEN_URI },
		{ "OPEN_MEMORY",	SQLITE_OPEN_MEMORY },
		{ "OPEN_NOMUTEX",	SQLITE_OPEN_NOMUTEX },
		{ "OPEN_FULLMUTEX",	SQLITE_OPEN_FULLMUTEX },
		{ "OPEN_SHAREDCACHE",	SQLITE_OPEN_SHAREDCACHE },
		{ "OPEN_PRIVATECACHE",	SQLITE_OPEN_PRIVATECACHE },
	};

	for (size_t i = 0; i < ARRAY_SIZE(constants); i++)
		ucv_object_add(scope, constants[i].name, ucv_int64_new(constants[i].value));
}

void
uc_module_init(uc_vm_t *vm, uc_value_t *scope)
{
	uc_function_list_register(scope, global_fns);
	register_constants(scope);

	db_type = uc_type_declare(vm, "sqlite.db", db_fns, db_free);
	stmt_type = uc_type_declare(vm, "sqlite.stmt", stmt_fns, stmt_free);
}
