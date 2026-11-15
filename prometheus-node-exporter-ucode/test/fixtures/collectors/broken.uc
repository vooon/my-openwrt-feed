// a failing collector
gauge("test_broken")({}, 1);
return false;
