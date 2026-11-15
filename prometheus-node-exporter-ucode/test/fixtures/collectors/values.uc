// value rendering; the declaration is printed once, unsupported values are skipped
let m = gauge("test_values", "Value rendering");
m({ v: "int" }, 0);
m({ v: "double" }, 1.5);
m({ v: "bool" }, true);
m({ v: "string" }, "42");
m({ v: "inf" }, Infinity);
m({ v: "nan" }, NaN);
m({ v: "null" }, null);
m({ v: "array" }, [ 1 ]);
counter("test_total")({}, 7);
