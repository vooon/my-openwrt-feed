// Prometheus textfile collector.
//
// Reads Prometheus text-exposition files (*.prom) from a directory and
// serves their contents verbatim.  This lets external tools (cron jobs,
// shell scripts, ...) drop metrics into the exporter without writing a
// dedicated collector, mirroring the upstream node_exporter textfile
// collector.

const dir = config.directory || "/run/prometheus/textfile";

let files = fs.lsdir(dir, "*.prom");
if (!files)
	return false;

sort(files);

let m_mtime = gauge("node_textfile_mtime_seconds",
	"Unix time of the last modification of a textfile collector file");

for (let i = 0; i < length(files); i++) {
	let name = files[i];
	let path = dir + "/" + name;

	let st = fs.stat(path);
	if (st && st.mtime != null)
		m_mtime({ file: name }, st.mtime);

	let f = fs.open(path);
	if (!f)
		continue;

	let content = f.read("all");
	raw(content);
}