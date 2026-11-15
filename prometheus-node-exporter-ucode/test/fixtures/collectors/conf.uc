// config options and the scope helpers
gauge("test_config")({ opt: config.opt, keys: join(",", sort(keys(config))) }, 1);
raw("test_raw 7");
raw("");
raw(null);
gauge("test_ubus")({}, ubus.call("system", "info").uptime);
