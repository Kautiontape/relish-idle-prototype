class_name RevCache
extends RefCounted
## A tiny cache keyed by a state revision: everything it holds was made under one rev, and a different
## rev starts it over. The shell uses one for the staffing projections (key: [order, extra]) and one for
## the lot hops (key: "hops"), so a panel's bind() never recomputes what the rev already answered.

var _rev := -1
var _items := {}


## The value for `key` at `rev`: made by `producer` (a Callable returning it) the first time only.
func fetch(rev: int, key: Variant, producer: Callable) -> Variant:
	if rev != _rev:
		_items.clear()
		_rev = rev
	var k := var_to_str(key)
	if not _items.has(k):
		_items[k] = producer.call()
	return _items[k]
