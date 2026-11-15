// label rendering: numbers (including 0), bools, null, escaping, unsupported
gauge("test_labels", "Label rendering")({
	zero: 0,
	num: 5,
	yes: true,
	no: false,
	empty: null,
	text: "a\"b\\c\nd",
	list: [ 1 ],
}, 1);
