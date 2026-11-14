extends RefCounted
## The boot rule's decision (STATE-API 2.1), pure so a test can run it without booting.

## The only user args that leave a session a normal player session (resume and autosave).
const PLAYER_ARGS: Array[String] = ["--reduced-motion"]

## The dev args we know of. A dev flag given without the `--` separator lands in the engine args,
## where the player-flag rule never sees it, so these are matched there (`--flag` or `--flag=value`).
const DEV_ARGS: Array[String] = ["--shot", "--new-game", "--fixture", "--teleport", "--scene",
		"--select", "--speed", "--cheat", "--finish-raid", "--trace", "--clicks"]


## The full decision (STATE-API 2.1): a harness session when any user arg is outside PLAYER_ARGS,
## when any engine arg is a DEV_ARGS entry or `--write-movie`, or when the display server is headless.
static func is_harness(user_args: PackedStringArray, engine_args: PackedStringArray, headless: bool) -> bool:
	if headless or is_harness_args(user_args):
		return true
	for arg in engine_args:
		if arg == "--write-movie":
			return true
		for a in DEV_ARGS:
			if arg == a or arg.begins_with(a + "="):
				return true
	return false


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
