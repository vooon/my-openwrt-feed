// SPDX-License-Identifier: LGPL-2.1+
/*
 * rpcd-mod-bird - expose the BIRD control socket via ubus
 *
 * The BIRD CLI protocol is a line based protocol over a unix socket:
 * on connect BIRD sends a banner, then the client sends a command
 * followed by a newline and reads the reply.  Every reply line starts
 * with a four digit code followed by either a '-' (more lines follow)
 * or a space (the last line of the reply).  See doc/reply_codes in the
 * BIRD source tree.
 *
 * This module lets sandboxed processes (like the prometheus node
 * exporter ucode jail) query the BIRD socket via:
 *
 *   ubus call bird query '{ "command": "show protocols all",
 *                          "socket": "/run/bird/bird.ctl" }'
 *
 * The reply is returned with the per-line code prefix stripped and the
 * trailing status line removed.
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

#define DEFAULT_SOCKET	"/run/bird/bird.ctl"

static struct blob_buf buf;

enum {
	BIRD_CMD_COMMAND,
	BIRD_CMD_SOCKET,
	__BIRD_CMD_MAX,
};

static const struct blobmsg_policy bird_cmd_policy[__BIRD_CMD_MAX] = {
	[BIRD_CMD_COMMAND] = { .name = "command", .type = BLOBMSG_TYPE_STRING },
	[BIRD_CMD_SOCKET]  = { .name = "socket",  .type = BLOBMSG_TYPE_STRING },
};

/* A BIRD reply is terminated by a line starting with a return code
 * (0000-0999, 8000-8999 or 9000-9999).  Returns 1 once such a line is
 * the last complete line of @data. */
static int
bird_reply_complete(const char *data, int len)
{
	int i = len;

	/* skip the trailing newline, if any */
	if (i > 0 && data[i - 1] == '\n')
		i--;

	/* find the start of the last line */
	while (i > 0 && data[i - 1] != '\n')
		i--;

	if (len - i < 4)
		return 0;

	return (data[i] == '0' || data[i] == '8' || data[i] == '9') &&
	       data[i + 1] >= '0' && data[i + 1] <= '9' &&
	       data[i + 2] >= '0' && data[i + 2] <= '9' &&
	       data[i + 3] >= '0' && data[i + 3] <= '9';
}

/* Connect to the BIRD control socket, send @command and return the reply
 * with the per-line "<4 digit code><sep>" prefix stripped and without the
 * trailing status line.  Returns 0 on success, -1 on error. */
static int
bird_socket_query(const char *socket_path, const char *command, char **out, int *outlen)
{
	int fd = -1, n, len = 0, cap = 0, olen = 0;
	char *raw = NULL, *clean = NULL;
	char tmp[4096];
	struct sockaddr_un sa;

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

	/* discard the banner BIRD sends on connect */
	do {
		n = read(fd, tmp, sizeof(tmp));
		if (n <= 0)
			goto fail;
	} while (tmp[n - 1] != '\n');

	/* send the command */
	if (write(fd, command, strlen(command)) < 0 ||
	    write(fd, "\n", 1) < 0)
		goto fail;

	/* read the whole reply up to the terminating status line */
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

		if (bird_reply_complete(raw, len))
			break;
	}

	if (!raw) {
		*out = strdup("");
		*outlen = 0;
		close(fd);
		return 0;
	}

	raw[len] = 0;

	/* strip the per-line code prefix and drop the trailing status line */
	{
		char *line = raw, *nl;

		clean = malloc(len + 1);
		if (!clean)
			goto fail;

		while (line < raw + len) {
			nl = strchr(line, '\n');
			if (nl)
				*nl = 0;

			/* the trailing status line starts with 0/8/9 */
			if ((line[0] == '0' || line[0] == '8' || line[0] == '9') &&
			    line[1] >= '0' && line[1] <= '9' &&
			    line[2] >= '0' && line[2] <= '9' &&
			    line[3] >= '0' && line[3] <= '9' &&
			    (line[4] == ' ' || line[4] == '\0'))
				break;

			/* strip "<code>-" or "<code> " prefix */
			if (line[0] >= '0' && line[0] <= '9' &&
			    line[1] >= '0' && line[1] <= '9' &&
			    line[2] >= '0' && line[2] <= '9' &&
			    line[3] >= '0' && line[3] <= '9' &&
			    (line[4] == '-' || line[4] == ' '))
				line += 5;

			olen += sprintf(clean + olen, "%s\n", line);

			if (!nl)
				break;
			line = nl + 1;
		}

		clean[olen] = 0;
	}

	close(fd);
	free(raw);

	*out = clean;
	*outlen = olen;
	return 0;

fail:
	if (fd >= 0)
		close(fd);
	free(raw);
	free(clean);
	return -1;
}

static int
rpc_bird_query(struct ubus_context *ctx, struct ubus_object *obj,
	       struct ubus_request_data *req, const char *method,
	       struct blob_attr *msg)
{
	struct blob_attr *tb[__BIRD_CMD_MAX];
	const char *command, *socket_path;
	char *out = NULL;
	int outlen = 0;

	blobmsg_parse(bird_cmd_policy, __BIRD_CMD_MAX, tb,
	              blob_data(msg), blob_len(msg));

	if (!tb[BIRD_CMD_COMMAND])
		return UBUS_STATUS_INVALID_ARGUMENT;

	command = blobmsg_get_string(tb[BIRD_CMD_COMMAND]);
	socket_path = tb[BIRD_CMD_SOCKET]
		? blobmsg_get_string(tb[BIRD_CMD_SOCKET]) : DEFAULT_SOCKET;

	blob_buf_init(&buf, 0);

	if (bird_socket_query(socket_path, command, &out, &outlen) < 0) {
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
rpc_bird_api_init(const struct rpc_daemon_ops *ops, struct ubus_context *ctx)
{
	static const struct ubus_method bird_methods[] = {
		UBUS_METHOD("query", rpc_bird_query, bird_cmd_policy),
	};

	static struct ubus_object_type bird_type =
		UBUS_OBJECT_TYPE("rpcd-plugin-bird", bird_methods);

	static struct ubus_object obj = {
		.name = "bird",
		.type = &bird_type,
		.methods = bird_methods,
		.n_methods = ARRAY_SIZE(bird_methods),
	};

	return ubus_add_object(ctx, &obj);
}

struct rpc_plugin rpc_plugin = {
	.init = rpc_bird_api_init
};