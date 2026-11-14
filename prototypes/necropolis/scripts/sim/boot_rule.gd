extends RefCounted
## The boot rule's decision (STATE-API 2.1), pure so a test can run it without booting.

## The only user args that leave a session a normal player session (resume and autosave).
const PLAYER_ARGS: Array[String] = ["--reduced-motion"]


## True when any user arg is not a PLAYER_ARGS entry (`--flag` or `--flag=value`): safe by default,
## so a debug flag nobody registered can never load and overwrite the shared autosave.
static func is_harness_args(args: PackedStringArray) -> bool:
	for arg in args:
		var player := false
		for a in PLAYER_ARGS:
			if arg == a or arg.begins_with(a + "="):
				player = true
		if not player:
			return true
	return false
