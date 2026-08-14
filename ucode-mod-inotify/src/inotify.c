// SPDX-License-Identifier: ISC
/*
 * ucode inotify module
 *
 * Exposes the Linux inotify API to ucode so scripts can monitor filesystem
 * events without shelling out to the busybox inotifyd applet (which would
 * become an orphaned child if the daemon process dies).
 *
 * The mask strings follow the busybox inotifyd lettering so existing
 * config values like "wDMnd" keep working:
 *
 *   bit 0  a = IN_ACCESS
 *   bit 1  c = IN_MODIFY
 *   bit 2  e = IN_ATTRIB
 *   bit 3  w = IN_CLOSE_WRITE
 *   bit 4  0 = IN_CLOSE_NOWRITE
 *   bit 5  r = IN_OPEN
 *   bit 6  m = IN_MOVED_FROM
 *   bit 7  y = IN_MOVED_TO
 *   bit 8  n = IN_CREATE
 *   bit 9  d = IN_DELETE
 *   bit 10 D = IN_DELETE_SELF
 *   bit 11 M = IN_MOVE_SELF
 *   bit 13 u = IN_UNMOUNT
 *   bit 14 o = IN_Q_OVERFLOW
 *   bit 15 x = IN_IGNORED
 */

#include <ucode/module.h>

#include <sys/inotify.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <limits.h>

static const char mask_chars[] = {
	'a', 'c', 'e', 'w', '0', 'r', 'm', 'y',
	'n', 'd', 'D', 'M', '\0', 'u', 'o', 'x'
};
#define MASK_BITS (sizeof(mask_chars))

static uint32_t
parse_mask(uc_value_t *val)
{
	uint32_t mask = 0;

	if (ucv_type(val) == UC_INTEGER)
		return (uint32_t)ucv_int64_get(val);

	if (ucv_type(val) != UC_STRING)
		return mask;

	for (const char *p = ucv_string_get(val); *p; p++) {
		for (size_t i = 0; i < MASK_BITS; i++) {
			if (mask_chars[i] == *p) {
				mask |= (1U << i);
				break;
			}
		}
	}

	return mask;
}

/* inotify.init() -> fd */
static uc_value_t *
uc_inotify_init(uc_vm_t *vm, size_t nargs)
{
	int fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);

	if (fd < 0)
		return NULL;

	return ucv_int64_new(fd);
}

/* inotify.close(fd) */
static uc_value_t *
uc_inotify_close(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *farg = uc_fn_arg(0);
	int fd;

	if (ucv_type(farg) != UC_INTEGER)
		return NULL;

	fd = ucv_int64_get(farg);

	if (close(fd) < 0)
		return NULL;

	return ucv_boolean_new(true);
}

/* inotify.add(fd, path[, mask]) -> watch descriptor */
static uc_value_t *
uc_inotify_add(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *farg = uc_fn_arg(0);
	uc_value_t *path = uc_fn_arg(1);
	uc_value_t *mask_arg = uc_fn_arg(2);
	uint32_t mask = 0x0fff;
	int fd, wd;

	if (ucv_type(farg) != UC_INTEGER || ucv_type(path) != UC_STRING)
		return NULL;

	if (ucv_type(mask_arg) == UC_STRING || ucv_type(mask_arg) == UC_INTEGER)
		mask = parse_mask(mask_arg);

	fd = ucv_int64_get(farg);
	wd = inotify_add_watch(fd, ucv_string_get(path), mask);

	if (wd < 0)
		return NULL;

	return ucv_int64_new(wd);
}

/* inotify.read(fd) -> [ { wd, mask, cookie, name, events } ... ] */
static uc_value_t *
uc_inotify_read(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *farg = uc_fn_arg(0);
	uc_value_t *events;
	int fd, buflen;
	char *buf;
	ssize_t off;

	if (ucv_type(farg) != UC_INTEGER)
		return NULL;

	fd = ucv_int64_get(farg);

	buflen = 0;
	if (ioctl(fd, FIONREAD, &buflen) < 0 || buflen <= 0)
		buflen = sizeof(struct inotify_event) + (NAME_MAX + 1);

	buf = malloc(buflen);
	if (!buf)
		return NULL;

	events = ucv_array_new(vm);

	for (;;) {
		struct inotify_event *ev;
		ssize_t len = read(fd, buf, buflen);

		if (len < 0) {
			if (errno == EINTR)
				continue;
			break;
		}

		if (len == 0)
			break;

		for (off = 0; off < len; ) {
			uc_value_t *obj;

			ev = (struct inotify_event *)&buf[off];

			obj = ucv_object_new(vm);
			ucv_object_add(obj, "wd", ucv_int64_new(ev->wd));
			ucv_object_add(obj, "mask", ucv_int64_new(ev->mask));
			ucv_object_add(obj, "cookie", ucv_int64_new(ev->cookie));
			if (ev->len)
				ucv_object_add(obj, "name",
					ucv_string_new_length(ev->name, strnlen(ev->name, ev->len)));
			ucv_array_push(events, obj);

			off += sizeof(struct inotify_event) + ev->len;
		}
	}

	free(buf);

	return events;
}

static const uc_function_list_t global_fns[] = {
	{ "init",	uc_inotify_init },
	{ "close",	uc_inotify_close },
	{ "add",	uc_inotify_add },
	{ "read",	uc_inotify_read },
};

void
uc_module_init(uc_vm_t *vm, uc_value_t *scope)
{
	uc_function_list_register(scope, global_fns);
}