'use strict';

/*
 * textfile collector: serves the *.prom files of a real temporary directory.
 */

import { describe, it, assert, contains, not, pred } from 'utest';
import * as fs from 'fs';
import { run_collector } from 'harness';

const COLLECTOR = 'files/extra/textfile.uc';

function with_dir(files, cb) {
	let dir = sprintf('%s/prom-tf-test-%d-%d', getenv('TMPDIR') || '/tmp', time(), clock()[1]);
	let rv, err = null;

	fs.mkdir(dir);
	for (let name, content in files)
		fs.writefile(`${dir}/${name}`, content);

	try {
		rv = cb(dir);
	} catch (e) {
		err = e;
	}

	for (let name in files)
		fs.unlink(`${dir}/${name}`);
	fs.rmdir(dir);

	if (err)
		die(err);

	return rv;
}

const FILES = {
	'b.prom': '# HELP second Something\n# TYPE second gauge\nsecond{label="x"} 1\n',
	'a.prom': '# HELP my_metric_total A counter\n# TYPE my_metric_total counter\nmy_metric_total 42\n',
	'ignored.txt': 'ignored\n',
};

describe('textfile collector', () => {
	it('exports the mtime of each .prom file, sorted by name', () => {
		let r = with_dir(FILES, (dir) => run_collector(COLLECTOR, { fs, config: { directory: dir } }));

		assert.match(true, r.ok);
		assert.match([
			contains({ name: 'node_textfile_mtime_seconds', labels: { file: 'a.prom' }, value: pred(v => v > 0) }),
			contains({ name: 'node_textfile_mtime_seconds', labels: { file: 'b.prom' }, value: pred(v => v > 0) }),
		], r.metrics);
	});

	it('passes the .prom files through verbatim, without trailing blank lines', () => {
		let r = with_dir(FILES, (dir) => run_collector(COLLECTOR, { fs, config: { directory: dir } }));

		assert.match(
			'# HELP my_metric_total A counter\n# TYPE my_metric_total counter\nmy_metric_total 42\n' +
			'# HELP second Something\n# TYPE second gauge\nsecond{label="x"} 1',
			r.raw);
		assert.match(not(contains('ignored')), r.raw);
	});

	it('fails when the directory does not exist', () => {
		let r = run_collector(COLLECTOR, { fs, config: { directory: '/nonexistent/prom-tf-test' } });

		assert.match(false, r.ok);
		assert.match([], r.metrics);
	});
});
