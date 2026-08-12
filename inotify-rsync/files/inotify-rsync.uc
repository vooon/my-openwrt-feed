#!/usr/bin/ucode

let fs = require("fs");
let uloop = require("uloop");
let uci = require("uci");
let log = require("log");

log.ulog_open(log.ULOG_SYSLOG, log.LOG_DAEMON, "inotify-rsync");

const CONF = "inotify-rsync";
const INSTANCE = ARGV[0];
const SYNC_ONLY = ARGV[1] == "sync";

if (!INSTANCE)
	exit(1, "usage: inotify-rsync.uc <instance> [sync]\n");

let ctx = uci.cursor();

if (!ctx.get(CONF, INSTANCE))
	exit(1, "no such watch section: " + INSTANCE + "\n");

let enabled = ctx.get(CONF, INSTANCE, "enabled");
if (enabled === "0" || enabled === "false")
	exit(0);

let dest = ctx.get(CONF, INSTANCE, "dest");
let debounce_ms = int(ctx.get(CONF, INSTANCE, "debounce_ms") || "1000");
let event_mask = ctx.get(CONF, INSTANCE, "event_mask") || "wDMndc";
let textfile_dir = ctx.get(CONF, INSTANCE, "textfile_dir");
let rsync_args = split(trim(ctx.get(CONF, INSTANCE, "rsync_args") || "-Ppra --delete --delete-delay"), /\s+/);

let srcs = [];
for (let s in ctx.get_all(CONF, INSTANCE, "src") || [])
	push(srcs, s);

let filters = [];
for (let f in ctx.get_all(CONF, INSTANCE, "filter") || [])
	push(filters, f);

if (length(srcs) == 0 || !dest)
	exit(1, "watch '" + INSTANCE + "': missing src/dest\n");

function build_rsync_argv()
{
	let argv = ["rsync"];
	for (let a in rsync_args)
		push(argv, a);
	for (let f in filters)
		push(argv, "--filter=" + f);
	for (let s in srcs)
		push(argv, s);
	push(argv, dest);
	return argv;
}

let metrics_file = null;
let m_events = 0;
let m_runs = 0;
let m_errors = 0;
let m_last_run = 0;

function read_counter(content, name)
{
	for (let line in split(content, "\n")) {
		if (index(line, name + "{") == 0) {
			let parts = split(line, " ");
			return int(parts[length(parts) - 1]);
		}
	}
	return 0;
}

function init_metrics()
{
	if (!textfile_dir)
		return;

	if (!fs.stat(textfile_dir))
		fs.mkdir(textfile_dir);

	metrics_file = textfile_dir + "/inotify-rsync-" + INSTANCE + ".prom";

	let content = fs.readfile(metrics_file);
	if (!content)
		return;

	m_events = read_counter(content, "inotify_rsync_events_total");
	m_runs = read_counter(content, "inotify_rsync_runs_total");
	m_errors = read_counter(content, "inotify_rsync_errors_total");
	m_last_run = read_counter(content, "inotify_rsync_last_run_seconds");
}

function write_metrics()
{
	if (!metrics_file)
		return;

	let body = "";
	body += "# HELP inotify_rsync_events_total Number of filesystem events observed.\n";
	body += "# TYPE inotify_rsync_events_total counter\n";
	body += sprintf("inotify_rsync_events_total{watch=\"%s\"} %d\n", INSTANCE, m_events);
	body += "# HELP inotify_rsync_runs_total Number of rsync runs.\n";
	body += "# TYPE inotify_rsync_runs_total counter\n";
	body += sprintf("inotify_rsync_runs_total{watch=\"%s\"} %d\n", INSTANCE, m_runs);
	body += "# HELP inotify_rsync_errors_total Number of rsync errors.\n";
	body += "# TYPE inotify_rsync_errors_total counter\n";
	body += sprintf("inotify_rsync_errors_total{watch=\"%s\"} %d\n", INSTANCE, m_errors);
	body += "# HELP inotify_rsync_last_run_seconds Last rsync run unix timestamp.\n";
	body += "# TYPE inotify_rsync_last_run_seconds gauge\n";
	body += sprintf("inotify_rsync_last_run_seconds{watch=\"%s\"} %d\n", INSTANCE, m_last_run);

	let tmp = metrics_file + ".tmp";
	if (fs.writefile(tmp, body)) {
		fs.rename(tmp, metrics_file);
	}
}

function run_rsync()
{
	let argv = build_rsync_argv();
	log.NOTE("running rsync for watch '" + INSTANCE + "'");
	m_runs++;
	m_last_run = time();
	if (system(argv) != 0)
		m_errors++;
	write_metrics();
}

init_metrics();

if (SYNC_ONLY) {
	run_rsync();
	exit(0);
}

function dirs(root)
{
	let out = [];
	let stack = [root];

	while (length(stack) > 0) {
		let cur = pop(stack);
		let st = fs.stat(cur);

		if (!st || st.type != "directory")
			continue;

		push(out, cur);

		let entries = fs.lsdir(cur);
		if (!entries)
			continue;

		for (let e in entries)
			push(stack, cur + "/" + e);
	}

	return out;
}

let watch_dirs = [];
for (let s in srcs) {
	for (let d in dirs(s))
		push(watch_dirs, d + ":" + event_mask);
}

if (length(watch_dirs) == 0)
	exit(1, "watch '" + INSTANCE + "': no watchable dirs\n");

let inotify_args = "inotifyd -";
for (let w in watch_dirs)
	inotify_args += " " + w;

let fd;
let proc = fs.popen(inotify_args);

if (!proc)
	exit(1, "inotifyd start failed\n");

fd = proc.fileno();

uloop.init();

let timer = null;

function on_event(flags, eof)
{
	try {
		let line = proc.read("line");
		if (!line)
			eof = true;
	}
	catch (e) {
		eof = true;
	}

	if (eof) {
		m_errors++;
		write_metrics();
		log.ERR("inotifyd exited, respawning");
		exit(3);
	}

	m_events++;
	write_metrics();

	if (timer)
		timer.set(debounce_ms);
	else
		timer = uloop.timer(debounce_ms, function() {
			run_rsync();
			timer = null;
		});
}

uloop.handle(fd, on_event, uloop.ULOOP_READ);
uloop.run();