class_name RaidQuit
extends RefCounted
## How the headless bots end the process: after the result line is printed, silence the Synth, pause
## the tree (the sim must not advance past the printed result) and wait DRAIN_MS of wall-clock time,
## then quit. Quitting at once leaves voices playing: under the Dummy audio driver the sim runs faster
## than the driver mixes, and Godot then reports their AudioStreamWAV / playback objects as leaked at
## exit. Game time runs faster than wall time here, so the wait reads the OS clock.

const DRAIN_MS := 100


## A coroutine: the caller need not await it.
static func finish(tree: SceneTree) -> void:
	RaidSound.silence()
	tree.paused = true
	var until := Time.get_ticks_msec() + DRAIN_MS
	while Time.get_ticks_msec() < until:
		await tree.process_frame
	tree.quit()
