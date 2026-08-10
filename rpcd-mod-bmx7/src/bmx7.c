// SPDX-License-Identifier: LGPL-2.1+
/*
 * rpcd-mod-bmx7 - expose the BMX7 control socket via ubus
 *
 * The BMX7 CLI protocol is a line based protocol over a unix socket: the
 * client connects, sends a command followed by the quit character '#' and
 * reads the reply until the connection-end character '$'.
 *
 * This module lets sandboxed processes (like the prometheus node exporter
 * ucode jail) query the BMX7 socket via:
 *
 *   ubus call bmx7 query '{ "command": "list links",
 *                           "socket": "/var/run/bmx7/sock" }'
 *
 * The reply is returned with the trailing '$' removed.
 *
 * Copyright (C) 2026 Vladimir Ermakov <vooon341@gmail.com>
 */

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/un.h>

#include <libubox/blobmsg.h>
#include <libubox/blobmsg_json.h>
#include <libubus.h>

#include <rpcd/plugin.h>

#define DEFAULT_SOCKET	"/var/run/bmx7/sock"
#define BMX_QUIT_CHR	'#'
#define BMX_END_CHR	'$'

static struct blob_buf buf;

enum {
	BMX_CMD_COMMAND,
	BMX_CMD_SOCKET,
	__BMX_CMD_MAX,
};

static const struct blobmsg_policy bmx_cmd_policy[__BMX_CMD_MAX] = {
	[BMX_CMD_COMMAND] = { .name = "command", .type = BLOBMSG_TYPE_STRING },
	[BMX_CMD_SOCKET]  = { .name = "socket",  .type = BLOBMSG_TYPE_STRING },
};

/* Connect to the BMX7 control socket, send @command and return the reply up
 * to (excluding) the '$' connection-end character.  Returns 0 on success,
 * -1 on error. */
static int
bmx_socket_query(const char *socket_path, const char *command, char **out)
{
	int fd = -1, n, len = 0, cap = 0;
	char *raw = NULL;
	char tmp[4096];
	struct sockaddr_un sa;
	const char *p;

	fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0)
		goto fail;

	memset(&sa, 0, sizeof(sa));
	sa.sun_family = AF_UNIX;
	if (strlen(socket_path) >= sizeof(sa.sun_path))
		goto fail;
	strcpy(sa.sun_path, socket_path);

	if (connect(fd, (struct sockaddr *)&sa, sizeof(sa)) < 0)
		goto fail;

	/* send "<command> #" */
	{
		char quit[2] = { ' ', BMX_QUIT_CHR };

		if (write(fd, command, strlen(command)) < 0 ||
		    write(fd, quit, sizeof(quit)) < 0)
			goto fail;
	}

	/* read until the '$' connection-end character */
	for (;;) {
		n = read(fd, tmp, sizeof(tmp));
		if (n <= 0) {
			if (n < 0 && errno == EINTR)
				continue;
			break;
		}

		if (len + n > cap) {
			cap = len + n + 512;
			raw = realloc(raw, cap);
			if (!raw)
				goto fail;
		}

		memcpy(raw + len, tmp, n);
		len += n;

		if (memchr(raw + len - n, BMX_END_CHR, n))
			break;
	}

	if (!raw) {
		*out = strdup("");
		close(fd);
		return 0;
	}

	/* cut everything at and after the '$' */
	if ((p = memchr(raw, BMX_END_CHR, len)))
		len = p - raw;

	raw[len] = 0;
	close(fd);

	*out = raw;
	return 0;

fail:
	if (fd >= 0)
		close(fd);
	free(raw);
	return -1;
}

static int
rpc_bmx7_query(struct ubus_context *ctx, struct ubus_object *obj,
	       struct ubus_request_data *req, const char *method,
	       struct blob_attr *msg)
{
	struct blob_attr *tb[__BMX_CMD_MAX];
	const char *command, *socket_path;
	char *out = NULL;

	blobmsg_parse(bmx_cmd_policy, __BMX_CMD_MAX, tb,
	              blob_data(msg), blob_len(msg));

	if (!tb[BMX_CMD_COMMAND])
		return UBUS_STATUS_INVALID_ARGUMENT;

	command = blobmsg_get_string(tb[BMX_CMD_COMMAND]);
	socket_path = tb[BMX_CMD_SOCKET]
		? blobmsg_get_string(tb[BMX_CMD_SOCKET]) : DEFAULT_SOCKET;

	blob_buf_init(&buf, 0);

	if (bmx_socket_query(socket_path, command, &out) < 0) {
		blobmsg_add_u32(&buf, "code", 1);
	} else {
		blobmsg_add_u32(&buf, "code", 0);
		blobmsg_add_string(&buf, "stdout", out);
		free(out);
	}

	ubus_send_reply(ctx, req, buf.head);

	return UBUS_STATUS_OK;
}

static int
rpc_bmx7_api_init(const struct rpc_daemon_ops *ops, struct ubus_context *ctx)
{
	static const struct ubus_method bmx7_methods[] = {
		UBUS_METHOD("query", rpc_bmx7_query, bmx_cmd_policy),
	};

	static struct ubus_object_type bmx7_type =
		UBUS_OBJECT_TYPE("rpcd-plugin-bmx7", bmx7_methods);

	static struct ubus_object obj = {
		.name = "bmx7",
		.type = &bmx7_type,
		.methods = bmx7_methods,
		.n_methods = ARRAY_SIZE(bmx7_methods),
	};

	return ubus_add_object(ctx, &obj);
}

struct rpc_plugin rpc_plugin = {
	.init = rpc_bmx7_api_init
};