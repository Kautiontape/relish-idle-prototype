class_name RaidLogic
extends RefCounted
## Pure raid logic: mass-ledger math, tier mappings, raise, statlines, the result builder,
## sacrifice, essence, telemetry and checkpoint/revive math. The fortress layout generator lives in
## LayoutLogic (RaidLogic keeps one-line delegates). No scene-tree or autoload dependencies —
## every function takes a cfg Dictionary (parsed configs/raid.json) so tests run headless.


# ------------------------------------------------- warned-attack assist ----
## "Longer warnings": an optional accessibility switch. Memory only (session lifetime, no save field): `assist_on`
## is flipped by the legend's toggle row or the --raid-assist dev flag and read where a warned attack's tell
## window is sized (WardenLogic.attack_tell), so a change takes effect on the next tell laid. No loot penalty.
static var assist_on := false
static var assist_mult := 1.5
static var _assist_booted := false


## What the boot applies from raid.json's `assist`: [the switch's first value or null to leave it, tell_mult].
## `enabled` seeds the switch only on a session's first boot (a later raid keeps what the player chose).
static func assist_boot_state(cfg: Dictionary, booted: bool) -> Array:
	var on = null if booted else bool(cfg.get("enabled", false))
	return [on, float(cfg.get("tell_mult", 1.5))]


## Called as each raid is built, with raid.json's `assist` block.
static func assist_boot(cfg: Dictionary) -> void:
	var st := assist_boot_state(cfg, _assist_booted)
	if st[0] != null:
		assist_on = st[0]
	assist_mult = st[1]
	_assist_booted = true


# ------------------------------------------------------------ mass mappings --
static func enemy_count(living: float, cap: float, cfg: Dictionary) -> int:
	var m: Dictionary = cfg.get("mass", {})
	var per: float = float(m.get("enemies_per_cap", 26.0))
	return clampi(int(round(living / maxf(1.0, cap) * per)),
		int(m.get("enemy_min", 5)), int(m.get("enemy_max", 34)))


static func mass_per_enemy(living: float, cap: float, cfg: Dictionary) -> float:
	return living / float(enemy_count(living, cap, cfg))


static func pile_count(dead: float, cfg: Dictionary) -> int:
	var m: Dictionary = cfg.get("mass", {})
	return clampi(int(dead / float(m.get("pile_mass_div", 8.0))),
		int(m.get("pile_min", 2)), int(m.get("pile_max", 24)))


static func garrison_count(undead: float, cfg: Dictionary) -> int:
	var m: Dictionary = cfg.get("mass", {})
	return clampi(int(undead / float(m.get("garrison_mass_div", 10.0))),
		0, int(m.get("garrison_max", 12)))


# ---------------------------------------------------------- raise mappings ---
static func score_class(score: int, cfg: Dictionary) -> String:
	var r: Dictionary = cfg.get("raise", {})
	if score >= int(r.get("elite_min_score", 90)):
		return "elite"
	if score >= int(r.get("soldier_min_score", 60)):
		return "soldier"
	return "chaff"


## What a scored circle raises from N orbs of total mass M. Test-only (Ledger.on_raise, see there).
## Big sloppy circle = many weak idiots; small perfect circle = few strong ones.
static func raise_spec(score: int, total_mass: float, orb_count: int, cfg: Dictionary) -> Dictionary:
	if orb_count <= 0:
		return {"kind": "", "count": 0, "unit_mass": 0.0}
	var r: Dictionary = cfg.get("raise", {})
	match score_class(score, cfg):
		"elite":
			return {"kind": "elite",
				"count": maxi(1, int(orb_count / float(r.get("elite_orb_div", 4.0)))),
				"unit_mass": 0.0}
		"soldier":
			return {"kind": "soldier",
				"count": maxi(1, int(orb_count / float(r.get("soldier_orb_div", 3.0)))),
				"unit_mass": 0.0}
	return {"kind": "chaff", "count": orb_count, "unit_mass": total_mass / orb_count}


# ------------------------------------------------- v2: seed, raise, statlines --
## A dungeon seed in the STATE-API 7.1 shape for standalone runs.
static func demo_seed(cfg: Dictionary) -> Dictionary:
	var d: Dictionary = cfg.get("demo", {})
	var div := float(cfg.get("mass", {}).get("garrison_mass_div", 10.0))
	var undead := float(d.get("undead", 0.0))
	var units := garrison_count(undead, cfg)
	var bu: Dictionary = d.get("big_undead", {})
	var st: Dictionary = bu.get("stats", {})
	var party: Array = []
	if not bu.is_empty():
		party.append({"uid": str(bu.get("uid", "u1")), "name": str(bu.get("name", "")),
			"kind": str(bu.get("kind", "")), "role": str(bu.get("role", "")),
			"stats": {"power": float(st.get("power", 0.0)), "beef": float(st.get("beef", 0.0)),
				"wits": float(st.get("wits", 0.0)), "presence": float(st.get("presence", 0.0)),
				"speed": float(st.get("speed", 0.0))}})
	var w: Dictionary = d.get("warden", {})
	var tier := int(d.get("tier", 1))
	return {
		"v": 2, "kind": "raid", "run_id": int(d.get("run_id", 0)), "seed_rev": int(d.get("seed_rev", 0)),
		"rng_seed": str(d.get("rng_seed", "1")),
		"fort": {"id": str(d.get("fort_id", "")), "name": str(d.get("fort_name", "")), "tier": tier,
			"cap": float(d.get("cap", 100.0)), "first_clear": bool(d.get("first_clear", false)),
			"first_dungeon": bool(d.get("first_dungeon", false)),
			"clears_since_retaken": int(d.get("clears_since_retaken", 0)),
			"yield_mult": float(d.get("yield_mult", 1.0))},
		"living": float(d.get("living", 0.0)), "dead": float(d.get("dead", 0.0)), "undead": undead,
		"garrison_units": units, "garrison_in_mass": float(units) * div, "garrison_mass_div": div,
		"starter_units": int(d.get("starter_units", 0)), "party": party,
		"digest_q": float(d.get("digest_q", 1.0)),
		"phylactery_charges": int(d.get("phylactery_charges", 0)),
		"phylactery_max_per_dungeon": int(d.get("phylactery_max_per_dungeon", 1)),
		"clones_ready": int(d.get("clones_ready", 0)),
		"warden": {"archetype": str(w.get("archetype", "bellringer")), "tier": int(w.get("tier", tier))},
		"warden_spec": {},
		"loot_table_id": "t%d.%s" % [tier, str(w.get("archetype", "bellringer"))],
		"loot_hint": str(d.get("loot_hint", "")), "chest_husk": bool(d.get("chest_husk", false)),
		"watchtower": bool(d.get("watchtower", false)),
		"relish_hp": float(cfg.get("relish", {}).get("hp", 30.0)),
	}


## BALANCE 3's standard "party of tier T" against a world.json fort (DEV: the autopilot's P2/P3
## profiles; GameState seeds real runs). `fort` is the world.json entry {id, name, tier, cap}. The
## fort holds living = cap * autopilot.profile_living_frac and dead = cap * profile_dead_frac, its
## warden is wardens.by_fort's, the first_* flags are false, and there is no phylactery charge.
## The party comes from autopilot.party_profiles[party_tier] (clamped to 1..4):
## {garrison_units, starter_units, party: [{stats, name?, kind?, role?}]}. Validates as raid_seed.
static func profile_seed(fort: Dictionary, party_tier: int, cfg: Dictionary) -> Dictionary:
	var ap: Dictionary = cfg.get("autopilot", {})
	var profs: Dictionary = ap.get("party_profiles", {})
	var prof: Dictionary = profs.get(str(clampi(party_tier, 1, 4)), {})
	var div := float(cfg.get("mass", {}).get("garrison_mass_div", 10.0))
	var units := clampi(int(prof.get("garrison_units", 0)), 0, int(cfg.get("mass", {}).get("garrison_max", 12)))
	var tier := clampi(int(fort.get("tier", 1)), 1, 4)
	var cap := float(fort.get("cap", 100.0))
	var fid := str(fort.get("id", ""))
	var arche := str(cfg.get("wardens", {}).get("by_fort", {}).get(fid, WardenLogic.DEFAULT_ARCHETYPE))
	var party: Array = []
	var entries: Array = prof.get("party", [])
	for i in entries.size():
		var e: Dictionary = entries[i]
		var st: Dictionary = e.get("stats", {})
		party.append({"uid": "p%d" % (i + 1), "name": str(e.get("name", "Profile big %d" % (i + 1))),
			"kind": str(e.get("kind", "hulk")), "role": str(e.get("role", "brute")),
			"stats": {"power": float(st.get("power", 0.0)), "beef": float(st.get("beef", 0.0)),
				"wits": float(st.get("wits", 0.0)), "presence": float(st.get("presence", 0.0)),
				"speed": float(st.get("speed", 0.0))}})
	return {
		"v": 2, "kind": "raid", "run_id": 0, "seed_rev": 0, "rng_seed": "1",
		"fort": {"id": fid, "name": str(fort.get("name", fid)), "tier": tier, "cap": cap,
			"first_clear": false, "first_dungeon": false, "clears_since_retaken": 0, "yield_mult": 1.0},
		"living": cap * float(ap.get("profile_living_frac", 0.85)), "dead": cap * float(ap.get("profile_dead_frac", 0.0)),
		"undead": float(units) * div,
		"garrison_units": units, "garrison_in_mass": float(units) * div, "garrison_mass_div": div,
		"starter_units": maxi(0, int(prof.get("starter_units", 0))), "party": party,
		"digest_q": 1.0, "phylactery_charges": 0, "phylactery_max_per_dungeon": 1, "clones_ready": 0,
		"warden": {"archetype": arche, "tier": tier}, "warden_spec": {},
		"loot_table_id": "t%d.%s" % [tier, arche], "loot_hint": "", "chest_husk": false, "watchtower": false,
		"relish_hp": float(cfg.get("relish", {}).get("hp", 30.0)),
	}


## Pure twin of CircleScorer.multiplier (circle.json keys).
static func stat_mult(score: int, circle_cfg: Dictionary) -> float:
	return float(circle_cfg.get("multiplier_base", 0.5)) \
		+ float(circle_cfg.get("multiplier_per_100", 1.0)) * float(score) / 100.0


## MECHANICS 5.3: every mote raises one undead at stat_mult(score). `motes` is
## [{mass: float, recycled: bool}]. Recycled motes carry mass but are not newly
## raised dead, so they stay out of fresh_mass.
static func raise_spec_v2(score: int, motes: Array, cfg: Dictionary, circle_cfg: Dictionary) -> Dictionary:
	var masses: Array[float] = []
	var fresh := 0.0
	for m in motes:
		var mm := maxf(0.0, float(m.get("mass", 0.0)))
		masses.append(mm)
		if not bool(m.get("recycled", false)):
			fresh += mm
	return {"tier": score_class(score, cfg) if not motes.is_empty() else "",
		"count": motes.size(), "stat_mult": stat_mult(score, circle_cfg),
		"unit_masses": masses, "fresh_mass": fresh}


static func undead_stats(mult: float, tier: String, cfg: Dictionary) -> Dictionary:
	var u: Dictionary = cfg.get("undead", {})
	var b: Dictionary = u.get("base", {})
	return {"hp": float(b.get("hp", 10.0)) * mult, "dmg": float(b.get("dmg", 2.0)) * mult,
		"speed": float(b.get("speed", 118.0)), "cadence_s": float(b.get("cadence_s", 0.9)),
		"radius": float(u.get("radius_by_tier", {}).get(tier, b.get("radius", 9.0)))}


static func big_undead_stats(stats: Dictionary, cfg: Dictionary) -> Dictionary:
	var p: Dictionary = cfg.get("party", {})
	return {"hp": float(p.get("hp_base", 30.0)) + float(p.get("hp_per_beef", 8.0)) * float(stats.get("beef", 0.0)),
		"dmg": float(p.get("dmg_base", 3.0)) + float(p.get("dmg_per_power", 1.2)) * float(stats.get("power", 0.0)),
		"speed": float(p.get("speed_base", 90.0)) + float(p.get("speed_per_speed", 10.0)) * float(stats.get("speed", 0.0)),
		"cadence_s": float(p.get("cadence_s", 1.0)), "radius": float(p.get("radius", 20.0))}


static func empty_loot() -> Dictionary:
	return {"relics": 0, "blueprints": [], "husks": [], "remnants": [], "essence": 0}


## `found` with `add` (the loot shape) merged in: relics add, arrays append, essence is skipped
## (it is the carried cluster, counted when the loot is banked). A new dictionary; inputs unchanged.
static func merge_loot(found: Dictionary, add: Dictionary) -> Dictionary:
	var out := found.duplicate(true)
	for k in add:
		if k == "essence":
			continue
		if add[k] is Array:
			var cur: Array = out.get(k, [])
			cur.append_array((add[k] as Array).duplicate(true))
			out[k] = cur
		elif k == "relics":
			out[k] = int(out.get(k, 0)) + int(add[k])
		else:
			out[k] = add[k]
	return out


## A deep copy of `found` (loot shape minus essence) in the full loot shape, with essence set to
## what Relish carries now: the checkpoint's banked loot (MECHANICS 7).
static func loot_snapshot(found: Dictionary, carried: int) -> Dictionary:
	var out := empty_loot()
	for k in out:
		if found.has(k) and k != "essence":
			out[k] = found[k].duplicate(true) if (found[k] is Array or found[k] is Dictionary) else found[k]
	out["essence"] = maxi(0, carried)
	return out


## What a close, a load or a crash pays (IDLE I5): the last checkpoint snapshot, as a deep copy in
## the full loot shape. Whatever was found since is lost, the same bound as a death.
static func close_loot(banked: Dictionary) -> Dictionary:
	var out := empty_loot()
	for k in out:
		if banked.has(k):
			out[k] = banked[k].duplicate(true) if (banked[k] is Array or banked[k] is Dictionary) else banked[k]
	return out


## How a window close mid-run ends a dungeon (IDLE I5: no run survives a close): as a retreat,
## unless an ending beat is already playing (`ended`, with `pending_exit` the exit it will emit):
## Relish's death beat (`relish_died`) or the warden's victory beat (`warden_beaten`). That ending
## happened while she was present, so it stands; a close can't turn a death or a win into a retreat.
static func close_exit(ended: bool, pending_exit: String) -> String:
	return pending_exit if ended and pending_exit in ["relish_died", "warden_beaten"] else "retreated"


## The outcome a checkpoint sent to the state carries (RaidEndings._send_checkpoint): the ending beat already
## playing (`pending_exit`: relish_died or warden_beaten, from pending_on), else "retreated". A save written
## mid-beat, or a crash, then ends the run as that ending on the next load, and no later checkpoint can
## write "retreated" back over it. Any other string reads as a retreat.
static func checkpoint_outcome(pending_exit: String) -> String:
	return pending_exit if pending_exit in ["relish_died", "warden_beaten"] else "retreated"


## What a checkpoint sends the state (RaidEndings._send_checkpoint): {outcome, loot}. Sticky in both: once an
## ending beat has begun (`pending_exit` set) the loot is the one the ending sent (`ending_loot`: the win's,
## or the death's banked), never the pre-ending `banked`, so no later call can write the chest back out. Before
## an ending it is `banked` and "retreated". An empty loot is the empty loot shape (the state refuses {}). A copy.
static func checkpoint_payload(pending_exit: String, ending_loot: Dictionary, banked: Dictionary) -> Dictionary:
	var loot := ending_loot if (pending_exit != "" and not ending_loot.is_empty()) else banked
	return {"outcome": checkpoint_outcome(pending_exit), "loot": empty_loot() if loot.is_empty() else loot.duplicate(true)}


## The exit an ending beat leaves pending when it starts: `chest_opened` (the warden's victory beat)
## -> warden_beaten, `relish_died` (her death beat) -> relish_died; "" for anything else.
static func pending_on(event: String) -> String:
	match event:
		"chest_opened":
			return "warden_beaten"
		"relish_died":
			return "relish_died"
	return ""


## How a window close finishes a dungeon run (RaidEndings.close_request): {exit (close_exit), closing}.
## `closing` (the result pays only the last checkpoint snapshot, RaidLogic.result_loot) is true for the
## retreat a close stands in for; an ending beat already playing finishes as that beat would have.
static func close_plan(ended: bool, pending_exit: String) -> Dictionary:
	var exit := close_exit(ended, pending_exit)
	return {"exit": exit, "closing": exit == "retreated"}


## Does a game event end this raid (raid.gd `_on_game_event`; the state ended the run underneath it after a gap above
## idle.gap_s)? A `run_ended` with our run id, or an `away_report` while the run open in the state is not ours
## (`open_run_id` is view_relish.run_id, -1 for none): the backstop if the run_ended was missed.
static func gap_ends_run(ev: Dictionary, run_id: int, open_run_id: int) -> bool:
	match str(ev.get("type", "")):
		"run_ended":
			return int(ev.get("run_id", -1)) == run_id
		"away_report":
			return open_run_id != run_id
	return false


## The exit the state already recorded for the run a gap ended (run_ended.outcome); an away_report carries none,
## and anything unknown, so a retreat.
static func gap_outcome(ev: Dictionary, pending_exit := "") -> String:
	if str(ev.get("type", "")) == "away_report":
		return checkpoint_outcome(pending_exit)   # the rule the checkpoint uses: never contradicts a recorded death or win
	return checkpoint_outcome(str(ev.get("outcome", "")))


## A gap while an ending beat is already running (`ended` with a `pending_exit`: the death or victory beat): the beat
## already matches what the state recorded (the checkpoint carries pending_exit), so the gap only suppresses sends;
## no banner, no card freed, no second timer, and the beat's own single finish runs.
static func gap_leaves_beat(ended: bool, pending_exit: String) -> bool:
	return ended and pending_exit != ""


## The banner a gap-ended raid shows (the glossary's words: "checkpoint" is the banked point).
static func gap_banner() -> String:
	return "AWAY TOO LONG · the raid ended at its last checkpoint"


## What is pending after a checkpoint send (RaidEndings._send_checkpoint): the payload when the state refused it
## with catching_up (it is resent later), else nothing (accepted, or refused for a reason that will not pass).
## Each send replaces what was pending, so a newer checkpoint supersedes an older one. (Today state_runs.gd's
## checkpoint does not refuse with catching_up, no run being open during a catch-up: this is a guard for if it does.)
static func checkpoint_pending_after(payload: Dictionary, res: Dictionary) -> Dictionary:
	if not bool(res.get("ok", false)) and str(res.get("reason", "")) == "catching_up":
		return payload
	return {}


## Resend a pending checkpoint only when the catch-up is over.
static func checkpoint_resend_due(pending: Dictionary, catching_up: bool) -> bool:
	return not pending.is_empty() and not catching_up


## The seed with the fields a catch-up could change re-read from `fresh` (the state's view_dungeon_seed): the
## phylactery stock the HUD and the revive rule read. `fresh` {} (no such run) or missing keys change nothing. A copy.
static func reread_seed(seed: Dictionary, fresh: Dictionary) -> Dictionary:
	var out := seed.duplicate(true)
	for k in ["phylactery_charges", "phylactery_max_per_dungeon"]:
		if fresh.has(k):
			out[k] = fresh[k]
	return out


## The width the awake WardenBlock wraps its break rows to: the plate's inner width, floored so a plate with no
## width yet (size.x 0) cannot wrap to one word per line.
static func break_wrap_width(plate_w: float, inset: float, min_px: float) -> float:
	return maxf(plate_w - 2.0 * inset, min_px)


## The loot a raid result carries (RaidEndings.build_result): a retreat or a win banks everything found
## plus the carried motes, a death keeps the last checkpoint snapshot (`banked`), and a close
## (`closing`) pays that snapshot whatever the exit. Always the full loot shape; inputs unchanged.
static func result_loot(exit: String, closing: bool, found: Dictionary, carried: int, banked: Dictionary) -> Dictionary:
	var loot := loot_snapshot(found, carried) if exit in ["retreated", "warden_beaten"] else banked.duplicate(true)
	if closing:
		loot = close_loot(banked)
	if loot.is_empty():
		loot = empty_loot()
	return loot


## The warden is a target for an undead of `radius` at `pos` when it is within `reach` px of walking
## (LayoutLogic.walk_within: the same walking leash as the enemies; a straight line through a sealed
## wall does not count). RaidWardenRun.target_in delegates here.
static func warden_in_reach(layout: Dictionary, pos: Vector2, warden_pos: Vector2, reach: float, radius: float) -> bool:
	return LayoutLogic.walk_within(layout, pos, warden_pos, reach, radius)


## A held fort's counter-garrison is cleared when its last living enemy falls (IDLE I3).
## `living_left` counts the living still alive; `started` is true once the clear has fired.
static func held_clear_due(held: bool, boss: bool, living_left: int, started: bool) -> bool:
	return held and not boss and living_left <= 0 and not started


## A held fort with no living at all when the raid builds has no last kill to trigger the clear:
## it clears `held.empty_clear_s` after the build instead. That delay, or -1 when it does not apply
## (not held, the boss, or living spawned).
static func held_empty_clear_s(held: bool, boss: bool, living_spawned: int, cfg: Dictionary) -> float:
	if not held_clear_due(held, boss, living_spawned, false):
		return -1.0
	return maxf(0.0, float(cfg.get("held", {}).get("empty_clear_s", 1.0)))


static func held_banner(fort_name: String) -> String:
	return "COUNTER-GARRISON CLEARED" if fort_name == "" else "COUNTER-GARRISON CLEARED · %s holds" % fort_name


## The banner's second line: what the clear paid (the essence bonus counts as the motes that spawn), and
## the husk when the roll gave one (E4 step 2: held_clear's chest husk roll).
static func held_payoff(loot: Dictionary) -> String:
	var c := loot_counts(loot)
	var line := "+%d relics · +%d remnants · +%d essence" % [int(c["relics"]), int(c["remnants"]), int(c["essence"])]
	var hk: Array = loot.get("husks", [])
	return line + (" · +%d husk" % hk.size() if not hk.is_empty() else "")


## The held_clear roll's essence bonus: how many fresh mass-0 motes the scene spawns.
static func held_motes(loot: Dictionary) -> int:
	return maxi(0, int(loot.get("essence", 0)))


## The checkpoint snapshot with its essence capped at what is still carried: motes circled into
## undead after the checkpoint are spent, so a death must not pay them out. A copy; an empty
## snapshot stays empty.
static func clamp_banked_essence(banked: Dictionary, carried: int) -> Dictionary:
	var out := banked.duplicate(true)
	if out.has("essence"):
		out["essence"] = mini(int(out["essence"]), maxi(0, carried))
	return out


## Item counts of a loot-shaped dictionary (relics, remnants, husks, blueprints) plus essence:
## `items` is the four without essence, `total` is all five. `{}` counts as zeros.
static func loot_counts(loot: Dictionary) -> Dictionary:
	var out := {"relics": int(loot.get("relics", 0)), "remnants": (loot.get("remnants", []) as Array).size(),
		"husks": (loot.get("husks", []) as Array).size(), "blueprints": (loot.get("blueprints", []) as Array).size(),
		"essence": int(loot.get("essence", 0))}
	out["items"] = int(out["relics"]) + int(out["remnants"]) + int(out["husks"]) + int(out["blueprints"])
	out["total"] = int(out["items"]) + int(out["essence"])
	return out


## What a death would lose right now (MECHANICS 7): found loot plus the carried essence, minus the
## last checkpoint snapshot (`banked`, {} before the first), as counts. Never negative.
static func unbanked(found: Dictionary, carried: int, banked: Dictionary) -> Dictionary:
	var f := loot_counts(found)
	var b := loot_counts(banked)
	var out := {}
	for k in ["relics", "remnants", "husks", "blueprints"]:
		out[k] = maxi(0, int(f[k]) - int(b[k]))
	out["essence"] = maxi(0, carried - int(b["essence"]))
	out["items"] = int(out["relics"]) + int(out["remnants"]) + int(out["husks"]) + int(out["blueprints"])
	out["total"] = int(out["items"]) + int(out["essence"])
	return out


## The first-dungeon ghost ring (and the autopilot's raise circle): the centroid of the motes within
## `reach_px` of Relish, and the radius to the farthest of them plus `pad_px`. {ok, center, radius,
## count}; ok is false with no mote in reach.
static func ghost_ring(mote_positions: Array, relish_pos: Vector2, reach_px: float, pad_px: float) -> Dictionary:
	var near: Array[Vector2] = []
	for p in mote_positions:
		if (p as Vector2).distance_to(relish_pos) <= reach_px:
			near.append(p)
	if near.is_empty():
		return {"ok": false, "center": relish_pos, "radius": 0.0, "count": 0}
	var c := Vector2.ZERO
	for p in near:
		c += p
	c /= float(near.size())
	var rad := 0.0
	for p in near:
		rad = maxf(rad, p.distance_to(c))
	return {"ok": true, "center": c, "radius": rad + pad_px, "count": near.size()}


## True when a phylactery charge is left to spend in this dungeon (MECHANICS 7).
static func can_revive(revived: int, seed: Dictionary) -> bool:
	return revives_left(revived, seed) > 0


## Phylactery charges still spendable this run: min(charges, max_per_dungeon) - revived.
static func revives_left(revived: int, seed: Dictionary) -> int:
	return maxi(0, mini(int(seed.get("phylactery_charges", 0)), int(seed.get("phylactery_max_per_dungeon", 0))) - revived)


## A BANKED / UNBANKED line from loot_counts / unbanked: the non-zero kinds only ("relics 1 ·
## remnants 2 · essence 5"); "" when every kind is zero (the HUD shows one dim word then).
static func loot_line(c: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in ["relics", "remnants", "husks", "blueprints", "essence"]:
		if int(c.get(k, 0)) > 0:
			parts.append("%s %d" % [k, int(c[k])])
	return " · ".join(parts)


## The 8-way compass word for a direction on the dungeon floor (y grows down, so N is up the screen):
## "N", "NE", "E", "SE", "S", "SW", "W", "NW"; "" for a zero vector.
static func compass(v: Vector2) -> String:
	if v.length() < 0.001:
		return ""
	var words := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
	var i := int(posmod(roundi(v.angle() / (PI / 4.0)), 8))
	return words[i]


## What a death would lose, as a phrase: "1 remnant + 5 essence at risk", "nothing at risk".
static func risk_phrase(c: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in ["relics", "remnants", "husks", "blueprints"]:
		var n := int(c.get(k, 0))
		if n > 0:
			parts.append("%d %s" % [n, k if n > 1 else k.trim_suffix("s")])
	if int(c.get("essence", 0)) > 0:
		parts.append("%d essence" % int(c["essence"]))
	return "nothing at risk" if parts.is_empty() else " + ".join(parts) + " at risk"


## The push-or-retreat line (D-b review MF-5): "LIVING 6 left · exit W, 2 rooms · 1 remnant at risk".
## `at_exit`: Relish stands at an exit ("AT EXIT"). Otherwise `exit_word` is the compass word of the
## way to the nearest exit (the first step of its route, so never through a wall), "" when there is
## none (the clause is dropped); `hops` the rooms between her room and the exit's (0 this room, -1
## unknown: a doorway band).
static func push_line(living: int, exit_word: String, hops: int, at_risk: Dictionary, at_exit := false, rooms_seen := 0, rooms_total := 0, with_risk := true) -> String:
	var parts: PackedStringArray = []
	if rooms_total > 0:
		parts.append(rooms_phrase(rooms_seen, rooms_total))
	parts.append("LIVING %d left" % maxi(0, living))
	if at_exit:
		parts.append("AT EXIT")
	elif exit_word != "":
		parts.append("exit " + exit_word + ("" if hops <= 0 else (", next room" if hops == 1 else ", %d rooms" % hops)))
	if with_risk:   # false once the win is banked (the clear card): nothing is at risk to name
		parts.append(risk_phrase(at_risk))
	return " · ".join(parts)


## T4: the raid's goal line. A dungeon: break its warden to take the fort. A held fort: clear the
## counter-garrison (the last living falls and pays loot).
static func goal_line(fort_name: String, warden_name: String, held: bool) -> String:
	if held:
		return "YOUR FORT · clear its counter-garrison for loot"
	return "GOAL · break %s to take %s" % [warden_name.to_upper(), fort_name.to_upper()]


## T4: where the warden is. `route_len` is the hops from the spawn's room to the warden's room plus one (the
## rooms on the shortest route), `hops_left` the hops from Relish's room to the warden's, `compass` the word
## of the next step, the door to take ("" drops that clause). The warden itself may lie in another direction
## (its WARDEN chevron points straight at it), so the word is named "next door". An off-route detour (more
## hops left than the route has) reads as room 1.
static func route_line(route_len: int, hops_left: int, compass_word: String) -> String:
	if hops_left <= 0:
		return "you are in the warden's room"
	var tail := "the warden is %d room%s on%s" % [hops_left, "" if hops_left == 1 else "s", "" if compass_word == "" else " · next door " + compass_word]
	if route_len <= 0:   # the spawn's room has no walk to the warden's: no "room n of m"
		return tail
	return "room %d of %d · %s" % [clampi(route_len - hops_left, 1, route_len), route_len, tail]


## T4: the GoalBlock's chest row, once the warden is down and its chest stands.
const CHEST_ROW := "open the chest to take the fort"


## T4: the GoalBlock's rows [{text, px, key}] for `s`: held (bool), fort_name, warden_alive (bool), warden_name,
## route_text, break_rows (Array of String), chest (bool: the warden is down and its chest stands), no_army
## (bool), goal_px / route_px / row_px (font sizes). A held raid keeps only its goal; a living warden adds the
## route and how to break it; a fallen one the chest; the no-army row follows any of them. No rows: none shown.
static func goal_rows(s: Dictionary) -> Array:
	var rows: Array = []
	var gpx := int(s.get("goal_px", 17))
	var rpx := int(s.get("route_px", 14))
	var xpx := int(s.get("row_px", 13))
	var fort := str(s.get("fort_name", ""))
	var compact := bool(s.get("compact", false))   # the sleeping warden's ring lies under the full block: goal, BREAK, COUNTER, the short no-army row
	if bool(s.get("held", false)):
		rows.append({"text": goal_line(fort, "", true), "px": gpx, "key": "vei"})
	elif bool(s.get("warden_alive", false)):
		rows.append({"text": goal_line(fort, str(s.get("warden_name", "")), false), "px": gpx, "key": "vei"})
		if not compact:
			rows.append({"text": str(s.get("route_text", "")), "px": rpx, "key": "text"})
		var br: Array = s.get("break_rows", [])
		for i in br.size():
			if compact and br.size() > 2 and i > 0 and i < br.size() - 1:
				continue   # the TAKES row (between the BREAK and COUNTER rows) waits for the full block
			rows.append({"text": str(br[i]), "px": xpx, "key": "text_dim"})
	elif bool(s.get("chest", false)):
		rows.append({"text": goal_line(fort, str(s.get("warden_name", "")), false), "px": gpx, "key": "vei"})
		rows.append({"text": CHEST_ROW, "px": rpx, "key": "text"})
	if not rows.is_empty() and bool(s.get("no_army", false)):
		rows.append({"text": NO_ARMY_SHORT if compact else NO_ARMY_LINE, "px": xpx, "key": "danger"})
	return rows


## The goal block shows its compact rows while the sleeping warden's ring (its screen rect, `ring_rect`; empty
## when there is none to protect) meets the block's FULL rect (`full_rect`: the full rows' height, measured even
## while compact is showing, so the block cannot flicker between the two).
static func goal_compact(full_rect: Rect2, ring_rect: Rect2) -> bool:
	return full_rect.has_area() and ring_rect.has_area() and full_rect.intersects(ring_rect)


## A sleeping warden's presence picture as a screen rect: a square around the dashed outer ring. `center` is the
## warden's screen point, `scale` the canvas scale (camera zoom), `radius` its world radius; `pc` is wardens.presence
## (ring_mult, dash_gap_px). The glyph and the plinth lie inside it; `pad` screen px of margin.
static func warden_ring_rect(center: Vector2, scale: float, radius: float, pc: Dictionary, pad := 4.0) -> Rect2:
	var rs := radius * float(pc.get("ring_mult", 1.9)) * scale + float(pc.get("dash_gap_px", 7.0)) + pad
	return Rect2(center - Vector2(rs, rs), Vector2(rs, rs) * 2.0)


## WCAG 2 relative luminance of an sRGB colour.
static func rel_luminance(c: Color) -> float:
	var ch := [c.r, c.g, c.b]
	for i in 3:
		var v: float = ch[i]
		ch[i] = v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * float(ch[0]) + 0.7152 * float(ch[1]) + 0.0722 * float(ch[2])


## WCAG contrast ratio of two opaque colours, 1 to 21 (alpha ignored: composite with `over` first).
static func contrast_ratio(fg: Color, bg: Color) -> float:
	var a := rel_luminance(fg)
	var b := rel_luminance(bg)
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)


## `top` at `alpha` (times its own alpha) composited over the opaque `under` in sRGB, as Godot's 2D blend does
## (this project does not enable hdr_2d). Opaque result.
static func over(top: Color, alpha: float, under: Color) -> Color:
	var a := clampf(alpha * top.a, 0.0, 1.0)
	return Color(top.r * a + under.r * (1.0 - a), top.g * a + under.g * (1.0 - a), top.b * a + under.b * (1.0 - a), 1.0)


## The banner's top: `base` while no top-centre block shows, else stepped down 14 px under it, and further by
## what the block is taller than its TOP_BLOCK_BASE_H base (`block_h` is its height).
const TOP_BLOCK_BASE_H := 62.0   # the awake WardenBlock's height with no extra rows

const WARDEN_BLOCK_W := 680.0    # the awake WardenBlock's plate width
const WARDEN_BLOCK_INSET := 12.0   # its text's inset each side
const BREAK_ROW_PX := 13           # the break / takes / counter rows' font size
const BREAK_ROW_STEP := 20.0       # one wrapped line's height


## `text` in lines no wider than `max_w` at `font_px`: whole " · " chunks where they fit, a long chunk
## broken at spaces (draw only: the StatBlock's DOOR row and the WardenBlock's break rows wrap on their plates).
static func wrap_chunks(text: String, font: Font, font_px: int, max_w: float) -> PackedStringArray:
	var out := PackedStringArray()
	if text == "":
		return out
	var words := PackedStringArray()
	var chunks := text.split(" · ")
	for i in chunks.size():
		var ws := chunks[i].split(" ")
		for j in ws.size():
			words.append(ws[j] + (" ·" if j == ws.size() - 1 and i < chunks.size() - 1 else ""))
	var line := ""
	for wd in words:
		var trial := wd if line == "" else line + " " + wd
		if line != "" and font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x > max_w:
			out.append(line)
			line = wd
		else:
			line = trial
	if line != "":
		out.append(line)
	return out


## The awake WardenBlock's break rows (break / takes / counter) wrapped to `max_w`, as the lines it draws.
static func wrap_break_rows(rows: Array, font: Font, font_px: int, max_w: float) -> PackedStringArray:
	var out := PackedStringArray()
	for r in rows:
		out.append_array(wrap_chunks(str(r), font, font_px, max_w))
	return out


## The hint's plate stacked up from `bottom_px` above the screen bottom (offsets from the bottom edge, negative
## up): the sub-line (height `sub_h`, 0 for none) `gap` over the plate's bottom, the hint line over it, the plate
## `gap` over the hint and `pad` wider than the wider line each side.
static func hint_plate_layout(bottom_px: float, pad: float, gap: float, hint_w: float, hint_h: float, sub_w: float, sub_h: float) -> Dictionary:
	var bottom := -bottom_px
	var y := bottom - gap
	var d := {"plate_bottom": bottom}
	if sub_h > 0.0:
		d["sub_bottom"] = y
		y -= sub_h
		d["sub_top"] = y
	d["hint_bottom"] = y
	y -= hint_h
	d["hint_top"] = y
	var w := maxf(hint_w, sub_w if sub_h > 0.0 else 0.0)
	d["plate_left"] = -w * 0.5 - pad
	d["plate_right"] = w * 0.5 + pad
	d["plate_top"] = y - gap
	return d


static func banner_top(base: float, block_visible: bool, block_h: float) -> float:
	if not block_visible:
		return base
	return base + 14.0 + maxf(0.0, block_h - TOP_BLOCK_BASE_H)


## Where an edge chevron at `p` (with its label at `label_rect`) goes so it never sits under the top-centre
## HUD block `block_rect` (an empty rect: no block): a chevron whose point or label falls inside the block
## moves to just below the block's bottom edge, same x, clamped into `view` (inset EDGE_INSET). Else `p`.
const EDGE_INSET := 34.0
const EDGE_BELOW := 18.0   # the chevron's point stands 12 px ahead of `p`: p sits this far under the block


## True when an in-world plate's screen rect `plate` runs under any of the HUD's screen rects `occluders`
## (RaidHud.occluder_rects): the sleeping warden then moves its name plate below its ring.
static func plate_hidden(plate: Rect2, occluders: Array) -> bool:
	for r in occluders:
		if (r as Rect2).has_area() and (r as Rect2).intersects(plate):
			return true
	return false


## The sideways shift (screen px) that takes plate rect `plate` clear of the first HUD rect it runs under:
## right past a rect whose centre is left of the plate's, else left past it, `gap` px beyond its edge. 0 when clear.
static func plate_nudge_x(plate: Rect2, occluders: Array, gap: float) -> float:
	for r in occluders:
		var o := r as Rect2
		if not o.has_area() or not o.intersects(plate):
			continue
		if o.get_center().x < plate.get_center().x:
			return o.end.x + gap - plate.position.x
		return -(plate.end.x - o.position.x + gap)
	return 0.0


static func edge_clear_of(p: Vector2, label_rect: Rect2, block_rect: Rect2, view: Vector2) -> Vector2:
	if block_rect.size.x <= 0.0 or block_rect.size.y <= 0.0:
		return p
	var chev := Rect2(p - Vector2(12.0, 12.0), Vector2(24.0, 24.0))
	if not (block_rect.has_point(p) or block_rect.intersects(chev) or block_rect.intersects(label_rect)):
		return p
	return Vector2(clampf(p.x, EDGE_INSET, maxf(EDGE_INSET, view.x - EDGE_INSET)),
		clampf(block_rect.end.y + EDGE_BELOW, EDGE_INSET, maxf(EDGE_INSET, view.y - EDGE_INSET)))


## The shared skip rule of the death and clear cards: once `t` has reached `gate`, any mouse button press, or
## a non-echo press of Space, Enter or keypad Enter, skips the card. Before the gate, nothing does.
static func card_skips(ev: InputEvent, t: float, gate: float) -> bool:
	if t < gate:
		return false
	if ev is InputEventMouseButton:
		return (ev as InputEventMouseButton).pressed
	if ev is InputEventKey:
		var k := ev as InputEventKey
		return k.pressed and not k.echo and (k.keycode == KEY_SPACE or k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER)
	return false


## T4: she has no undead with her, no loose essence, nothing carried and no corpse pile left to stir:
## nothing can be raised here.
const NO_ARMY_LINE := "NO UNDEAD WITH YOU AND NOTHING TO RAISE · retreat, then send WAR here or bring big undead"
## The StatBlock's floor-loot key, second line (13 px, on the 420 px plate: a test pins it to fit).
const KEY_PILE_LINE := "grey ×9 = a corpse pile (bodies in it): walk close, it gives essence"
const NO_ARMY_SHORT := "NO UNDEAD, NOTHING TO RAISE · retreat, then send WAR here or bring big undead"   # the compact goal block's form

static func no_army(allies_alive: int, loose_motes: int, carried: int, piles_left: int) -> bool:
	return allies_alive == 0 and loose_motes == 0 and carried == 0 and piles_left == 0


## The run's shape: "3 of 7 rooms seen" (rooms Relish has stood in, of the layout's rooms). Seen, not
## cleared: a room can be crossed with the living still in it. Never below 1 once she is in one.
static func rooms_phrase(seen: int, total: int) -> String:
	return "%d of %d rooms seen" % [clampi(seen, 0, maxi(0, total)), maxi(0, total)]


## What the death card says killed her: `src` is Relish.last_hit_src ("slam", "toll", "lunge", "bash", "fire", "hound", "living", or ""
## when nothing named it, e.g. a dev kill), `warden_name` the warden's spec name ("The Bellringer").
static func death_cause(src: String, warden_name: String) -> String:
	var who := warden_name if warden_name != "" else "The warden"
	match src:
		"slam":
			return "%s's slam" % who
		"toll":
			return "%s's toll" % who
		"lunge":
			return "%s's lunge" % who
		"bash":
			return "%s's bash" % who
		"rush":
			return "%s's rush" % who
		"fire":
			return "%s's fire" % who
		"hound":
			return "%s's hounds" % who
		"pack":
			return "%s's pack" % who
		"living":
			return "the living"
	return "a wound"


## The tell the killing attack showed, for the death card (D-d/E 3c: "missed: the swing"): the
## Bellringer's clapper swing (its toll: the ring at her feet), the Huntsman's locked line, the Shieldwall's lit arc (bash or rush), the
## Pyre-priest's marked ground. "" for a source with no one-beat tell (a pack, the living, a wound).
static func death_tell(src: String) -> String:
	match src:
		"slam":
			return "the swing"
		"toll":
			return "the ring at your feet"
		"lunge":
			return "the line"
		"bash", "rush":
			return "the lit arc"
		"fire":
			return "the marked ground"
	return ""


## The death card's KILLED BY text: the cause, then the tell she missed when the attack had one
## ("The Bellringer's slam · missed: the swing").
static func death_line(src: String, warden_name: String) -> String:
	var tell := death_tell(src)
	var cause := death_cause(src, warden_name)
	return cause if tell == "" else "%s · missed: %s" % [cause, tell]


## What she loses with the party: the unbanked loot ("relics 1 · essence 4") and the big undead of the
## party (a death costs the whole party; the garrison and raised survive). "nothing" when neither.
static func death_lost_line(unbanked: Dictionary, party_n: int) -> String:
	var parts: PackedStringArray = []
	var l := loot_line(unbanked)
	if l != "":
		parts.append(l)
	if party_n > 0:
		parts.append("%d big undead" % party_n)
	return "nothing" if parts.is_empty() else " · ".join(parts)


## The clear card's title (the raid's win, RaidClearCard): "OLD SLUICE IS YOURS".
static func clear_card_title(fort_name: String) -> String:
	return "%s IS YOURS" % fort_name.to_upper()


## The clear card's rows [{label, text, key}]: the warden broken, what taking the fort means, the loot the win
## pays (`loot` = loot_counts of RaidLogic.result_loot("warden_beaten", ...)), and what comes next.
static func clear_card_rows(warden_name: String, loot: Dictionary) -> Array:
	var ll := loot_line(loot)
	var rows: Array = [
		{"label": "BROKEN", "text": warden_name, "key": "vei"},
		{"label": "TAKEN", "text": "its living become your dead · it joins your realm as a held fort", "key": "text"},
		{"label": "LOOT", "text": ll if ll != "" else "nothing this time", "key": "text"},
	]
	var uses := loot_uses_line(loot)
	if uses != "":
		rows.append({"label": "USE", "text": uses, "key": "text_dim"})
	rows.append({"label": "NEXT", "text": "Vei contests it once its grace runs out · send WAR there to hold it", "key": "text_dim"})
	return rows


## The death card's geometry (RaidDeathCard._draw reads it, and so does the clear card; the test measures the
## widest value against it): card width, padding, the label column, the value font size.
## label_px / foot_px: the dim label column and footer sizes; backdrop_a the world-dimming rect behind the card,
## plate_a the card's own ground plate (the contrast test composites both over the brightest world colour).
const DEATH_CARD := {"w": 560.0, "pad": 22.0, "label_w": 120.0, "value_px": 18, "label_px": 14, "foot_px": 14, "backdrop_a": 0.55, "plate_a": 0.96}


## The death card's rows [{label, text, key}] (key: a Palette key): who killed her, the tell she missed when
## the attack had one (its own row, so a long cause never clips: "The Bellringer's toll" / "the ring at your
## feet"), what the last checkpoint banked, what is lost.
static func death_card_rows(cause: String, banked_counts: Dictionary, unbanked: Dictionary, party_n: int, missed := "", after := {}) -> Array:
	var bl := loot_line(banked_counts)
	var lost := death_lost_line(unbanked, party_n)
	var rows: Array = [{"label": "KILLED BY", "text": cause, "key": "danger"}]
	if missed != "":
		rows.append({"label": "MISSED", "text": missed, "key": "danger"})
	rows.append({"label": "BANKED", "text": bl if bl != "" else "nothing", "key": "text" if bl != "" else "text_dim"})
	rows.append({"label": "LOST", "text": lost, "key": "danger" if lost != "nothing" else "text_dim"})
	if not after.is_empty():
		rows.append(after)
	return rows


## A wait for the death card's AFTER row: "45 s" under a minute, m:ss from 60 s ("1:30"); never "0 s".
static func death_wait_text(secs: float) -> String:
	var n := maxi(1, roundi(secs))
	return "%d s" % n if n < 60 else "%d:%02d" % [n / 60, n % 60]


## The death card's AFTER row {label, text, key}: what a run-ending death costs in time. Read from the raid
## seed's `death_ends` {outcome: "clone"|"unmade", respawn_s} (economy's, after any phylactery revives); the
## card copies no rule. "clone": "wakes at Covington", with " in N s" only when respawn_s > 0. "unmade":
## "unmade", with " · reforms in N s" when respawn_s > 0. Without `death_ends` (an older save), or with an
## outcome it does not know (a newer economy's, or a broken key): the seed's clones_ready, "wakes at
## Covington" if > 0 else "unmade", with no number. A missing or non-positive respawn_s shows no number.
static func death_next_row(seed: Dictionary) -> Dictionary:
	var de: Variant = seed.get("death_ends", null)
	var clone := false
	var secs := 0.0
	if de is Dictionary and str((de as Dictionary).get("outcome", "")) in ["clone", "unmade"]:
		clone = str(de["outcome"]) == "clone"
		secs = float(de.get("respawn_s", 0.0))
	else:
		clone = int(seed.get("clones_ready", 0)) > 0
	var text := "wakes at Covington" if clone else "unmade"
	if secs > 0.0:
		text += (" in %s" if clone else " · reforms in %s") % death_wait_text(secs)
	return {"label": "AFTER", "text": text, "key": "text" if clone else "danger"}


## How much loose essence can still be banked: what lies loose, capped by the carry room left.
static func bankable(loose: int, carried: int, cfg: Dictionary) -> int:
	return mini(maxi(0, loose), carry_room(carried, cfg))


## An angle for a new mark on a ring that already has marks at `taken`: `want` when nothing lies
## within `sep` of it, else the first of want + sep, want + 2 sep, ... that is clear (want itself
## when the ring is full). Keeps marks countable when they keep coming from the same side.
static func spread_angle(want: float, taken: PackedFloat32Array, sep: float) -> float:
	var steps := maxi(1, ceili(TAU / maxf(0.01, sep)))
	for k in steps:
		var a := want + sep * k
		var clear := true
		for t in taken:
			if absf(angle_difference(a, t)) < sep - 0.0001:
				clear = false
				break
		if clear:
			return wrapf(a, -PI, PI)
	return wrapf(want, -PI, PI)


## The antechamber's last-chance banner, with the loose essence lit there (D-b review SF-4).
static func last_chance_banner(lit: int) -> String:
	return "LAST CHANCE · a free trance" + ("" if lit <= 0 else " · %d loose essence here: walk close and it drifts to you" % lit)


## T2: the words that say what the circle is for (never that it gathers essence).
const HINT_TRANCE := "DRAG A LOOP AROUND ESSENCE · each mote inside becomes one undead"
const HINT_EXIT := "AT EXIT · RETREAT banks your loot"
const HINT_IDLE := "HOLD SPACE · circle essence to RAISE undead"
const CUE_FIRST_MOTE := "ESSENCE IN YOUR SLOTS · circle it to RAISE undead · or carry it out an exit to BANK it"
const CUE_UNDEAD := "YOUR UNDEAD FIGHT ON THEIR OWN · keep Relish safe and raise more"
const ESSENCE_MEANING := "circle it: RAISE undead · leave by an exit: BANK it"


## The dungeon's bottom-centre hint: the trance's instruction wins, then the exit's, then the idle one.
static func hint_text(trance_active: bool, at_exit: bool) -> String:
	if trance_active:
		return HINT_TRANCE
	if at_exit:
		return HINT_EXIT
	return HINT_IDLE


## The idle hint's second line (dim, under HINT_IDLE): shown while nothing has been raised yet, and only
## when the idle line itself shows (the trance's and the exit's instructions stand alone).
const HINT_IDLE_SUB := "your undead fight on their own · keep Relish safe and raise more"


static func hint_sub_text(trance_active: bool, at_exit: bool, raised_any: bool) -> String:
	return "" if (trance_active or at_exit or raised_any) else HINT_IDLE_SUB


## The "your undead fight on their own" cue is due once: an undead stands and (a living has died or
## `delay_s` scene seconds have passed).
static func undead_cue_due(shown: bool, kills: int, scene_s: float, delay_s: float, allies_alive: int) -> bool:
	return not shown and allies_alive > 0 and (kills > 0 or scene_s >= delay_s)


## The held-fort clear's effect on the map (D-b review SF-5): the counter-garrison mass this run
## killed comes off the fort's living.
static func held_map_effect(killed_mass: float) -> String:
	return "on the map: counter-garrison −%d" % roundi(maxf(0.0, killed_mass))


## How exposed Relish is, 0..1, for her halo's danger rim. 0 while a phylactery charge is left.
## With none, a faint `danger.exposed_min` at full hp rising to `exposed_max` as her hp falls: a hit
## still has to get through the sacrifice chain and her hp first, so this is a rim, never an alarm
## (day 1 starts with no charges, and a steady strong halo would be noise).
static func exposed_level(phyl_left: int, hp_frac: float, cfg: Dictionary) -> float:
	if phyl_left > 0:
		return 0.0
	var d: Dictionary = cfg.get("danger", {})
	return lerpf(float(d.get("exposed_min", 0.2)), float(d.get("exposed_max", 1.0)), 1.0 - clampf(hp_frac, 0.0, 1.0))


## How far an exposed_level sits from the faint full-hp rim (0) to the strong no-hp one (1): the
## PHYLACT. words lean from text_dim to danger by it, as the halo does.
static func exposed_tint(level: float, cfg: Dictionary) -> float:
	var d: Dictionary = cfg.get("danger", {})
	return clampf(inverse_lerp(float(d.get("exposed_min", 0.2)), float(d.get("exposed_max", 1.0)), level), 0.0, 1.0)


## The PHYLACT. row's words: "" while a charge is left; with none, what a death would mean (true
## whatever her hp: the chain and her hp still stand between her and it).
static func phylactery_word(phyl_left: int) -> String:
	return "" if phyl_left > 0 else "NO REVIVE · death ends the run"


## The PHYLACT. row's dim sub-lines, one string per row. No charge: the glossary's Jargon line in two rows (where a
## charge comes from matters most then). With charges: one row, what one does now.
static func phylactery_meaning(phyl_left: int) -> PackedStringArray:
	if phyl_left > 0:
		return PackedStringArray(["a death here revives her in place, once"])
	return PackedStringArray(["revives Relish in place, at most once per dungeon.", "The Ossuary Tower crafts it from essence."])


## Sacrifice chain (MECHANICS 5.0): rank 0 chaff tier (raised chaff, garrison, starters),
## 1 soldier, 2 elite, 3 big undead (party).
static func ally_rank(role: String, tier: String) -> int:
	if role == "party" or tier == "big":
		return 3
	match tier:
		"soldier":
			return 1
		"elite":
			return 2
	return 0


## Candidates are [{rank: int, dist: float}]. The lowest rank wins, then the nearest.
## Returns its index, or -1 when there are none.
static func sacrifice_pick(candidates: Array) -> int:
	var best := -1
	for i in candidates.size():
		var c: Dictionary = candidates[i]
		if best < 0:
			best = i
			continue
		var b: Dictionary = candidates[best]
		var cr := int(c.get("rank", 0))
		var br := int(b.get("rank", 0))
		if cr < br or (cr == br and float(c.get("dist", 0.0)) < float(b.get("dist", 0.0))):
			best = i
	return best


## RTS-drift guard (MECHANICS 5.0): move clicks per successful raise.
static func drift_ratio(moves: int, raises: int) -> float:
	if raises <= 0:
		return float(moves)
	return float(moves) / float(raises)


static func is_drifting(moves: int, raises: int, cfg: Dictionary) -> bool:
	return drift_ratio(moves, raises) > float(cfg.get("telemetry", {}).get("drift_ratio", 8.0))


## Split a mass into n equal parts (n >= 1); the parts sum to mass.
static func split_mass(mass: float, n: int) -> Array:
	var k := maxi(1, n)
	var out: Array = []
	var each := mass / float(k)
	var acc := 0.0
	for i in k - 1:
		out.append(each)
		acc += each
	out.append(mass - acc)
	return out


## Free places in Relish's carried cluster.
static func carry_room(carried: int, cfg: Dictionary) -> int:
	return maxi(0, int(cfg.get("essence", {}).get("carry_max", 12)) - carried)


## The angle of a carried-cluster slot around Relish: the position that COUNTS (enclosure, the bot's
## aim, the absorb streak). It reads no animation state, so reduced motion cannot change a raid.
static func carry_slot_angle(slot: int, slots: int) -> float:
	return -PI * 0.5 + TAU * slot / float(maxi(1, slots))


## The swing the cluster is DRAWN rocking through at sim time `t`: a sine of at most `swing_rad`
## either way (0 under reduced motion), so a drawn mote stays within ~orbit * swing_rad px of the
## slot it counts at. Draw only: nothing that scores, aims or collides may read it.
static func carry_draw_spin(t: float, rad_s: float, swing_rad: float, reduced: bool) -> float:
	return 0.0 if reduced else sin(t * rad_s) * swing_rad


## The most a drawn carried mote can be from where it counts, in px (the knob the swing is made from).
static func carry_swing_rad(swing_px: float, orbit_px: float) -> float:
	return swing_px / maxf(1.0, orbit_px)


## Raid result v2 builder (STATE-API 8.1). Pure bookkeeping, no scene state.
class LedgerV2:
	extends RefCounted
	var garrison_in_mass := 0.0
	var cap := 1.0
	var keep_frac := 0.25
	var killed := 0.0
	var buckets: Array = []  # {score, count, mass}
	var _cfg: Dictionary = {}

	func _init(seed: Dictionary, cfg: Dictionary) -> void:
		_cfg = cfg
		garrison_in_mass = float(seed.get("garrison_in_mass", 0.0))
		cap = maxf(1.0, float(seed.get("fort", {}).get("cap", 1.0)))
		keep_frac = float(cfg.get("mass", {}).get("garrison_keep_cap_frac", 0.25))

	func on_kill(mass: float) -> void:
		killed += maxf(0.0, mass)

	func on_raise(score: int, fresh_mass: float, count: int) -> void:
		if count <= 0:
			return
		for b in buckets:
			if int(b["score"]) == score:
				b["count"] = int(b["count"]) + count
				b["mass"] = float(b["mass"]) + maxf(0.0, fresh_mass)
				return
		buckets.append({"score": score, "count": count, "mass": maxf(0.0, fresh_mass)})

	func raised_counts() -> Dictionary:
		var out := {"chaff": 0, "soldier": 0, "elite": 0}
		for b in buckets:
			var tier := RaidLogic.score_class(int(b["score"]), _cfg)
			out[tier] = int(out[tier]) + int(b["count"])
		return out

	func build_result(seed: Dictionary, exit: String, survivors: Array, party_died: Array,
			revived: int, loot: Dictionary, cfg: Dictionary) -> Dictionary:
		var garrison := 0.0
		var pool := 0.0
		for s in survivors:
			var m := maxf(0.0, float(s.get("mass", 0.0)))
			match str(s.get("role", "")):
				"garrison":
					garrison += m
				"raised":
					if str(s.get("tier", "chaff")) == "chaff":
						pool += m
					else:
						garrison += m
		var kept := minf(pool, keep_frac * cap)
		garrison += kept
		var chaff := pool - kept
		var raised_total := 0.0
		for b in buckets:
			raised_total += float(b["mass"])
		var limit := garrison_in_mass + raised_total
		var total := garrison + chaff
		if total > limit + 1e-6:
			var f := limit / total
			garrison *= f
			chaff *= f
		var lost: Array = []
		for u in seed.get("party", []):
			var uid := str(u.get("uid", ""))
			if (exit == "relish_died" or party_died.has(uid)) and not lost.has(uid):
				lost.append(uid)
		var full := RaidLogic.empty_loot()
		for k in full:
			if loot.has(k):
				full[k] = loot[k]
		var raised_out: Array = []
		for b in buckets:
			raised_out.append(b.duplicate())
		return {"v": 2, "run_id": int(seed.get("run_id", 0)), "seed_rev": int(seed.get("seed_rev", 0)),
			"fort_id": str(seed.get("fort", {}).get("id", "")),
			"warden_beaten": exit == "warden_beaten", "retreated": exit == "retreated",
			"relish_died": exit == "relish_died", "revived_in_place": maxi(0, revived),
			"killed_living_mass": killed, "raised": raised_out,
			"chaff_mass": maxf(0.0, chaff), "garrison_mass": maxf(0.0, garrison),
			"party_lost": lost, "loot": full}


## Which enemy kinds a tier fields (keys of the tier's mix).
static func tier_kinds(tier: int, cfg: Dictionary) -> Array:
	var mix: Dictionary = cfg.get("tier_mix", {}).get(str(clampi(tier, 1, 4)), {"spearman": 1.0})
	return mix.keys()


## `fort_id` with an entry in `tier_mix_by_fort` (D-d/E Step 4b) rolls from that fort's own mix instead.
static func roll_enemy_kind(rng: RandomNumberGenerator, tier: int, cfg: Dictionary, fort_id := "") -> String:
	var byf: Dictionary = cfg.get("tier_mix_by_fort", {})
	var mix: Dictionary = byf[fort_id] if fort_id != "" and fort_id != "_doc" and byf.has(fort_id) \
		else cfg.get("tier_mix", {}).get(str(clampi(tier, 1, 4)), {"spearman": 1.0})
	var total := 0.0
	for k in mix:
		total += float(mix[k])
	var roll := rng.randf() * maxf(0.0001, total)
	for k in mix:
		roll -= float(mix[k])
		if roll <= 0.0:
			return k
	return "spearman"


# -------------------------------------------------------------- the ledger ---
## TEST-ONLY v1 result builder: no scene uses it any more (the dungeon is LedgerV2, the boss has its
## own result). Kept because tests/test_results.gd (from_v1) builds its v1 fixture with it; delete it
## with that fixture. Tracks how in-scene events map onto the abstract map-mass result dict.
## Conservation invariant: everything reported as raised (chaff out + good mass
## + garrison) can never exceed initial dead + mass of living killed. Chaff that
## is re-killed inside the raid drops out of the pool (its corpse stays at the
## fort), so the surviving pool is what splits at the exit.
class Ledger:
	extends RefCounted
	var initial_dead := 0.0
	var cap := 0.0
	var killed := 0.0          # mass of living killed this raid
	var chaff_pool := 0.0      # mass currently walking around as raised chaff
	var soldiers := 0
	var elites := 0
	var good_mass := 0.0       # mass consumed by soldier/elite raises
	var raised_any := false
	var essence_consumed := 0.0

	func _init(dead0: float, cap0: float) -> void:
		initial_dead = maxf(0.0, dead0)
		cap = maxf(1.0, cap0)

	func on_kill(mass: float) -> void:
		killed += maxf(0.0, mass)

	## Apply a scored raise of N orbs totalling M mass. Returns the spawn spec.
	func on_raise(score: int, total_mass: float, orb_count: int, cfg: Dictionary) -> Dictionary:
		var spec := RaidLogic.raise_spec(score, total_mass, orb_count, cfg)
		if spec["count"] <= 0:
			return spec
		raised_any = true
		essence_consumed += total_mass
		if spec["kind"] == "chaff":
			chaff_pool += total_mass
		else:
			good_mass += total_mass
			if spec["kind"] == "soldier":
				soldiers += int(spec["count"])
			else:
				elites += int(spec["count"])
		return spec

	func on_chaff_death(mass: float) -> void:
		chaff_pool = maxf(0.0, chaff_pool - mass)

	func aborted() -> bool:
		return killed <= 0.0 and not raised_any

	## Final result dict. Surviving chaff mass splits: up to keep_frac*cap stays
	## as garrison, the remainder leaves with Relish as chaff mass.
	func result(fort_id: String, relish_died: bool, cfg: Dictionary) -> Dictionary:
		var keep_frac: float = float(cfg.get("mass", {}).get("garrison_keep_cap_frac", 0.25))
		var garrison := minf(chaff_pool, keep_frac * cap)
		var chaff_out := chaff_pool - garrison
		# safety clamp: never report more raised mass than existed (never expected
		# to trigger — orbs only ever carry killed or pile mass)
		var avail := initial_dead + killed
		var total := chaff_out + garrison + good_mass
		if total > avail and total > 0.0:
			var s := avail / total
			chaff_out *= s
			garrison *= s
			good_mass *= s
		return {
			"fort_id": fort_id,
			"killed_living_mass": killed,
			"raised_chaff_mass": chaff_out,
			"raised_soldiers": soldiers,
			"raised_elites": elites,
			"good_mass": good_mass,
			"garrison_mass": garrison,
			"relish_died": relish_died,
			"aborted": aborted(),
		}


# ------------------------------------------- layout (LayoutLogic delegates) ----
static func gen_layout(fort_id: String, tier: int, is_boss: bool, cfg: Dictionary, opts: Dictionary = {}) -> Dictionary:
	return LayoutLogic.gen_layout(fort_id, tier, is_boss, cfg, opts)


static func room_of(layout: Dictionary, p: Vector2) -> int:
	return LayoutLogic.room_of(layout, p)


static func room_adjacency(layout: Dictionary) -> Array:
	return LayoutLogic.room_adjacency(layout)


static func room_hops(adj: Array, start: int) -> Array[int]:
	return LayoutLogic.room_hops(adj, start)


static func layout_reachable(layout: Dictionary, cell: float) -> bool:
	return LayoutLogic.layout_reachable(layout, cell)


static func populate_enemies(fort_id: String, layout: Dictionary, count: int, tier: int, cfg: Dictionary) -> Array:
	return LayoutLogic.populate_enemies(fort_id, layout, count, tier, cfg)


## D-e task 3, the room leash (raid.json enemy_leash_by_fort; off with no entry): the rooms of `fort_id` whose
## living hold their own room until Relish steps into it. [] for a fort with no entry.
static func leash_rooms(fort_id: String, cfg: Dictionary) -> Array:
	var e: Dictionary = (cfg.get("enemy_leash_by_fort", {}) as Dictionary).get(fort_id, {})
	var out: Array = []
	for r in e.get("rooms", []):
		out.append(int(r))
	return out


## True while a leashed foe still holds: Relish is not yet in its room (its rect grown by `margin`).
## It never reverts: the caller clears its hold the first time this is false.
static func leash_holds(relish_pos: Vector2, room: Rect2, margin: float) -> bool:
	return not room.grow(margin).has_point(relish_pos)


## D-d/E Step 3: the guarded detour's site and guard (LayoutLogic.detour_site / detour_guard).
static func detour_site(layout: Dictionary, tier: int, cfg: Dictionary) -> Dictionary:
	return LayoutLogic.detour_site(layout, tier, cfg)


static func detour_guard(fort_id: String, layout: Dictionary, tier: int, cfg: Dictionary) -> Array:
	return LayoutLogic.detour_guard(fort_id, layout, tier, cfg)


## The sacrifice chain's reach over sources (D-d/E Step 4b, the manager's option A): where the risk gate is on
## (`bypass_on`: WardenLogic.lever_on, tier >= wardens.lever_min_tier and not the first dungeon; off with no
## warden), a warden's telegraphed tell-attacks (the Bellringer's slam, the Huntsman's lunge, the
## Shieldwall's bash and rush, the Pyre-priest's fire) strike Relish directly; the chain does not soak them,
## only the warden's own counter answers them. Everything else (the living, packs, hounds, any other blow,
## Vei's weaves), and everything at tier 1 and in the first dungeon, still follows the chain. MECHANICS §5.0.
const TELL_ATTACKS := ["slam", "toll", "lunge", "bash", "rush", "fire"]


static func chain_soaks(src: String, bypass_on: bool) -> bool:
	return not (bypass_on and TELL_ATTACKS.has(src))


## The measuring bot (D-d/E Step 4 review): can she still raise with no undead standing? `motes` is the
## essence she has (carried, and loose within collect_px: `_motes_near` counts both), `piles` the unstirred
## corpse piles within pile_px (stirring one gives motes). A raise needs `min_motes`.
static func can_raise_from(motes: int, piles: int, min_motes: int) -> bool:
	return motes >= min_motes or piles > 0


## The measuring bot's hold (D-d/E 3c): a living foe holds her back when it is hostile and stands in her room
## or the next one on her way. A taken detour is a push: its guard (`push_room`, -1 with none) does not hold
## her at its door, only once she is inside.
static func hold_blocks(hostile: bool, foe_room: int, cur_room: int, next_room: int, push_room: int) -> bool:
	if not hostile or foe_room < 0 or (foe_room != cur_room and foe_room != next_room):
		return false
	return not (foe_room == push_room and foe_room != cur_room)


## The measuring bot's unstick watch, one think on its sticky target (D-d/E 3c; autopilot unstick_*):
## `st` {d, t, in, room} is the watch's state, updated in place; `same` whether the target is the one
## watched, `d` her walking distance to it now, `last` the last think it was walked to, `room` the room she
## stands in (-1 in a doorway). Returns "new" (a new target: the clock starts), "closing" (closer by
## unstick_px; the first think back after one spent on something else; or a new room of hers, since the
## walking distance jumps at a doorway: straight in the doorway, round by the room centres beyond it),
## "wait", "aim_in" (not closing for unstick_s: aim inside its room) or "give_up" (still not closing
## another unstick_s after that).
static func unstick_step(st: Dictionary, same: bool, now: float, d: float, last: float, ap: Dictionary, room := -1) -> String:
	if not same:
		st["d"] = d
		st["t"] = now
		st["in"] = false
		st["room"] = room
		return "new"
	if now - last > float(ap.get("think_frames", 3.0)) / 60.0 + 1e-6 or d < float(st["d"]) - float(ap.get("unstick_px", 8.0)) \
			or room != int(st.get("room", room)):
		st["d"] = d
		st["t"] = now
		st["room"] = room
		return "closing"
	if now - float(st["t"]) >= float(ap.get("unstick_s", 1.5)) - 1e-6:
		var out := "give_up" if bool(st["in"]) else "aim_in"
		st["in"] = true
		st["t"] = now
		return out
	return "wait"


## The measuring bot's detour rule (raid.json autopilot detour_*; NOTES-RAID "the detour rule"): take the
## cache when her hp fraction is at least `detour_hp_frac` (`detour_hp_frac_revive` with a revive left) and
## her army is at least `detour_army_mult` times the guard she can see.
static func detour_take(hp_frac: float, revives: int, allies: int, guard: int, ap: Dictionary) -> bool:
	var need := float(ap.get("detour_hp_frac_revive", 0.4)) if revives > 0 else float(ap.get("detour_hp_frac", 0.6))
	return hp_frac >= need and float(allies) >= float(ap.get("detour_army_mult", 1.5)) * float(guard)


## On the way in: turn back when her hp fraction is below `detour_retreat_hp_frac` (`..._revive` with a
## revive left) or her army is below `detour_retreat_army_mult` times the guard still standing.
static func detour_retreat(hp_frac: float, revives: int, allies: int, guard: int, ap: Dictionary) -> bool:
	var floor_hp := float(ap.get("detour_retreat_hp_frac_revive", 0.3)) if revives > 0 else float(ap.get("detour_retreat_hp_frac", 0.5))
	return hp_frac < floor_hp or float(allies) < float(ap.get("detour_retreat_army_mult", 1.0)) * float(guard)


## D-e task 6, the held door (raid.json held_door; RaidHeldDoor). Its site: LayoutLogic.held_door_site.
static func held_door_site(layout: Dictionary, tier: int, cfg: Dictionary) -> Dictionary:
	return LayoutLogic.held_door_site(layout, tier, cfg)


## The held door's states (RaidHeldDoor; pure, so the order of events can be tested): "unused" (no big spent on
## it), "sent" (on its way to the plate), "held" (on the plate: the door open), "shut" (shut in behind the door)
## and "freed" (the warden fell: it rejoined). One live step of a big sent or holding: fallen, the door is free
## again ("unused": it is in party_died); else it holds the plate or is on its way; and once she stands in
## another room it is shut in. Every other state stands.
static func held_door_step(state: String, holder_alive: bool, on_plate: bool, left_room: bool) -> String:
	if state != "sent" and state != "held":
		return state
	if not holder_alive:
		return "unused"
	if left_room:
		return "shut"
	return "held" if on_plate else "sent"


## The warden's fall: a big spent on the door rejoins whether it was shut in, on the plate or on its way.
static func held_door_fall(state: String) -> String:
	return "freed" if state in ["sent", "held", "shut"] else state


## A big spent on the door that has not rejoined (sent, on the plate, or shut in).
static func held_door_committed(state: String) -> bool:
	return state in ["sent", "held", "shut"]


## THE SHUT-IN BIG'S FATE (the manager's ruling, 2026-11-15; the one place the rule lives): a big sent to
## the held door's plate (`committed`) rejoins her party when the warden falls; if the run ends any other
## way (a death, a retreat, a window close) it is lost and goes in party_lost.
static func held_door_lost(exit: String, committed: bool) -> bool:
	return committed and exit != "warden_beaten"


## A big undead's value in a warden weak point's stat ("beef", "speed", "wits", "power"; 0 for any other): the
## RaidUnit fields the party's stats land in (RaidPopulate). The pack's counter (RaidWardenRun.breaks_pack) and
## the bot's door rule read it here.
static func unit_stat(u, stat: String) -> float:
	match stat:
		"beef":
			return u.beef
		"speed":
			return u.speed_stat
		"wits":
			return u.wits
		"power":
			return u.power
	return 0.0


## The measuring bot's held-door rule (raid.json autopilot door_*; NOTES-RAID "D-e task 6", frozen once
## written). `stats`: the standing party bigs' values in this warden's weak-point stat, in party order;
## `threshold` the weak point's. Take the door when at least `door_min_bigs` bigs stand and, after one is
## spent, a big that meets the weak point still stands (or none met it to begin with). The big spent is the
## lowest in that stat (the first in party order on a tie). Returns its index, or -1 to skip.
static func held_door_pick(stats: Array, threshold: float, ap: Dictionary) -> int:
	if stats.size() < int(ap.get("door_min_bigs", 2)):
		return -1
	var low := 0
	var meets := 0
	for i in stats.size():
		if float(stats[i]) < float(stats[low]):
			low = i
		if float(stats[i]) >= threshold:
			meets += 1
	var left := meets - (1 if float(stats[low]) >= threshold else 0)
	return low if meets == 0 or left >= 1 else -1


## The held door's words (the world label, the plate's prompt, the HUD row, the death card's row and the
## retreat panel's line). `name` is the big's.
const HELD_DOOR_ENTRY := "HELD DOOR · a big on the plate holds it · it stays behind · the warden fight is harder without it"


static func held_door_prompt() -> String:
	return "AT THE HELD DOOR · click a big to send it (the plate sends the nearest) · it stays shut in until the warden falls · a retreat or a death loses it"


static func held_door_label(state: String, name: String) -> String:
	match state:
		"held":
			return "HELD · %s" % name
		"sent":
			return "SENT · %s" % name
		"shut":
			return "SHUT IN · %s" % name
		"freed":
			return "REJOINS · %s" % name
	return HELD_DOOR_ENTRY


## The HUD row while a big is spent on the door ("" when none is).
static func held_door_row(state: String, name: String) -> String:
	match state:
		"sent", "held":
			return "HELD DOOR · %s holds it · leaving the room shuts it in until the warden falls" % name
		"shut":
			return "SHUT IN · %s · rejoins when the warden falls · a retreat or a death loses it" % name
	return ""


## The death card's row for a big shut in at the door (apart from the party that fell in the fight).
static func held_door_card_row(name: String) -> Dictionary:
	return {"label": "SHUT IN", "text": "%s · lost at the cache" % name, "key": "danger"}


## The death card's rows with a shut-in big (`shut`, its name; "" for none): its SHUT IN row goes before the
## card's last row (AFTER), apart from LOST (RaidEndings.death_rows).
static func death_rows_with_shut(rows: Array, shut: String) -> Array:
	var out := rows.duplicate()
	if shut != "":
		out.insert(maxi(0, out.size() - 1), held_door_card_row(shut))
	return out


## The retreat panel's lines (Phase I item 6/8, the glossary's words): what a retreat keeps, as counts
## (`keep` is loot_counts of what a retreat pays: everything found plus the carried essence, as
## result_loot builds it), and what stays: the fort stays Vei's (a held fort stays yours). `door_line`
## is held_door_retreat_line's text, its leading newline dropped ("" for none).
## The panel's left column ("RETREAT NOW"), lines [{text, key}]: what a retreat keeps, its counts, what
## the loot is for (dim, only with something found), then what stays.
static func retreat_keep_lines(held: bool, keep: Dictionary, door_line: String) -> Array:
	var out: Array = [{"text": "You keep everything you found and all carried essence.", "key": "text"}]
	var now := loot_line(keep)
	out.append({"text": "  " + (now if now != "" else "nothing found yet"), "key": "text"})
	var uses := loot_uses_line(keep)
	if uses != "":
		out.append({"text": uses, "key": "text_dim"})
	out.append({"text": "The fort stays yours." if held else "The fort stays Vei's · you can come back and break its warden.", "key": "text"})
	var d := door_line.strip_edges()
	if d != "":
		out.append({"text": d, "key": "text"})
	return out


const RETREAT_HEAD := "RETREAT NOW"
const FALL_HEAD := "IF RELISH FALLS"


## The panel's right column ("IF RELISH FALLS"), lines [{text, key}], from the death card's own pieces:
## `revive_left` phylactery charges spendable now (the once-per-dungeon rule applied: RaidEndings.phylactery_left),
## the unbanked loot and party big count the card's LOST row reads (death_lost_line), and its AFTER row
## (death_next_row). With a charge left a death revives her in place, so LOST and AFTER would not apply.
static func retreat_fall_lines(revive_left: int, unbanked: Dictionary, party_n: int, next_row: Dictionary, shut := "") -> Array:
	if revive_left > 0:
		return [{"text": "a phylactery charge revives her here (at most once per dungeon)", "key": "relish"}]
	var lost := death_lost_line(unbanked, party_n)
	var out: Array = [{"text": "LOST · " + lost, "key": "danger" if lost != "nothing" else "text_dim"}]
	if shut != "":
		# the big shut in at the cache (`shut`, its name) is lost too: the death card's own row, before AFTER
		var sr := held_door_card_row(shut)
		out.append({"text": "%s · %s" % [sr["label"], sr["text"]], "key": sr["key"]})
	out.append({"text": "AFTER · " + str(next_row.get("text", "")), "key": str(next_row.get("key", "text"))})
	return out


## What each kind of loot in `counts` (loot_counts) is for, in the glossary's words: "" when none applies.
## Blueprints have no use line.
static func loot_uses_line(counts: Dictionary) -> String:
	var parts: PackedStringArray = []
	if int(counts.get("relics", 0)) > 0:
		parts.append("relics are spent when you build")
	if int(counts.get("husks", 0)) > 0:
		parts.append("husk: the frame a big undead is raised in · lay it on the crypt slab and slot remnants to shape it")
	elif int(counts.get("remnants", 0)) > 0:
		parts.append("remnants feed the crypt slab, which raises big undead")
	if int(counts.get("essence", 0)) > 0:
		parts.append("essence pays for backups (Ossuary Tower)")
	return " · ".join(parts)


## The big undead whose stat the COUNTER line counts: alive, a big (kind), in the party (role), and not the
## one spent on the held door (`holder`: its plate-bound big stays in raid.allies until it is shut in, but
## the warden's own counter checks must not see it as standing). Their `stat` values (unit_stat), in order.
static func counter_party_values(allies: Array, stat: String, holder = null) -> Array:
	var out: Array = []
	for a in allies:
		if is_instance_valid(a) and a.alive and a.kind == "big" and a.role == "party" and a != holder:
			out.append(unit_stat(a, stat))
	return out


## The retreat panel's line for a big spent on the door, by its state ("" when none is spent).
static func held_door_retreat_line(state: String, name: String) -> String:
	match state:
		"sent":
			return "\n%s is sent to the plate · lost if you retreat." % name
		"held":
			return "\n%s is on the plate · lost if you retreat." % name
		"shut":
			return "\n%s is shut in at the cache: a retreat loses it." % name
	return ""


static func populate_piles(fort_id: String, layout: Dictionary, count: int) -> Array:
	return LayoutLogic.populate_piles(fort_id, layout, count)


static func near_exit(layout: Dictionary, p: Vector2, radius: float) -> int:
	return LayoutLogic.near_exit(layout, p, radius)


static func merge_walls(rects: Array) -> Array:
	return LayoutLogic.merge_walls(rects)


static func wall_touches_room(wall: Rect2, room: Rect2) -> bool:
	return LayoutLogic.wall_touches_room(wall, room)


static func checkpoint_entered(layout: Dictionary, prev_room: int, room: int) -> bool:
	return LayoutLogic.checkpoint_entered(layout, prev_room, room)


## Warden spec for a fort {id, tier, archetype?, first_dungeon?} (see WardenLogic.spec).
static func warden_spec(fort: Dictionary, cfg: Dictionary) -> Dictionary:
	return WardenLogic.spec(fort, cfg)


# ------------------------------------------------------ the run's time split ---
## The measuring bot's time split (D-d/E; NOTES-RAID "Run length and risk calibration"): every physics
## tick of a live run goes to one bucket, the first that matches: "trance" (the trance is open),
## "fight" (something is engaged, `foe_engaged` or an awake warden), "travel" (Relish moved more than
## `move_px` this tick), else "idle". The bot never opens the trance (its raise is instant), so its
## trance share is 0 by construction.
const SPLIT_BUCKETS := ["travel", "fight", "trance", "idle"]


static func time_class(in_trance: bool, engaged: bool, moved_px: float, move_px: float) -> String:
	if in_trance:
		return "trance"
	if engaged:
		return "fight"
	if moved_px > move_px:
		return "travel"
	return "idle"


## A living foe is engaged once it is hostile (aggro'd: it never calms) and stands in Relish's room
## (`rel_room` >= 0, a doorway band is no room) or within `fight_px` of her, wherever the wall is.
static func foe_engaged(rel_pos: Vector2, rel_room: int, foe_pos: Vector2, foe_room: int, hostile: bool, fight_px: float) -> bool:
	if not hostile:
		return false
	if rel_room >= 0 and foe_room == rel_room:
		return true
	return rel_pos.distance_to(foe_pos) <= fight_px


## The measuring bot's reaction rule (raid.json autopilot react_*): a value set at a few target scores,
## linear between them and clamped outside (`pts` ascending, `vals` the same length). Empty: 0.
static func react_at(score: float, pts: Array, vals: Array) -> float:
	var n := mini(pts.size(), vals.size())
	if n == 0:
		return 0.0
	if score <= float(pts[0]):
		return float(vals[0])
	for i in range(1, n):
		if score <= float(pts[i]):
			var f := (score - float(pts[i - 1])) / maxf(1e-9, float(pts[i]) - float(pts[i - 1]))
			return lerpf(float(vals[i - 1]), float(vals[i]), f)
	return float(vals[n - 1])


## The degraded bot's knobs (D-e; raid.json autopilot.human): `--raid-autopilot-<name>=<s>` gives `value`,
## the bare `--raid-autopilot-<name>` gives `bare` true and takes `def` (the config's defended value).
## Absent: 0, the knob is off. Never negative, and never past `cap`.
static func human_knob(value: String, bare: bool, def: float, cap: float) -> float:
	var v := 0.0
	if value != "":
		v = float(value)
	elif bare:
		v = def
	return clampf(v, 0.0, cap)


## The longest circle a player can draw in one trance, in scene seconds: the focus runs out after
## trance.max_hold_s of real time, and the scene runs at trance.time_scale meanwhile.
static func draw_cap(trance_cfg: Dictionary) -> float:
	return float(trance_cfg.get("max_hold_s", 4.0)) * float(trance_cfg.get("time_scale", 0.35))


## One look at a degraded bot's open circle (`--raid-autopilot-draw`): "hold" while it is drawn (she stands,
## the trance open), "done" once `draw_s` scene seconds have passed (grade it and raise), "lost" when the
## trance closed under her first (its focus ran out, or the run ended it), "cancel" when she must dodge a
## warden tell she answered (a player lets go of the trance to move: the lockout, no raise).
static func draw_step(draw_t: float, draw_s: float, trance_open: bool, dodging: bool) -> String:
	if not trance_open:
		return "lost"
	if dodging:
		return "cancel"
	if draw_t >= draw_s - 1e-6:
		return "done"
	return "hold"


## The read pause (`--raid-autopilot-read`): on her first entry into a room (a doorway band is no room) she
## stands for `read_s` scene seconds before acting. True when this room starts one.
static func read_starts(read_s: float, room: int, seen: Dictionary) -> bool:
	return read_s > 0.0 and room >= 0 and not seen.has(room)


## The bot's goal branches that move her off a warden tell she answered (`_why`): the degraded bot's
## draw gives way to these, and they, or a due kite, end a read pause.
const DODGE_WHYS := ["toll-out", "bell-out", "wall-out", "pyre-off", "dodge"]


## Real seconds for a run measured in scene seconds: outside the trance they are the same, inside it
## the scene runs at `time_scale` of real time (trance.gd), so each trance scene second took 1 / time_scale
## real seconds. The degraded bot's draw lands in `trance_s`; its other knobs are scene time already.
static func human_real_s(scene_s: float, trance_s: float, time_scale: float) -> float:
	return scene_s + trance_s * (1.0 / maxf(0.05, time_scale) - 1.0)


## The control legend starts open every raid until a fort has been taken (dungeon-i T1), then collapsed.
static func legend_open_at_start(highest_tier_flipped: int) -> bool:
	return highest_tier_flipped <= 0


## Capture mode (D-e; RaidCapture, NOTES-RAID "Capture mode"): where a live run's record goes. `--capture`
## gives `def_path`, `--capture=<path>` that path; "" is off. It is read from the engine args too, so a
## player launch can pass it before `--` (BootRule only matches its DEV_ARGS there: the save resumes).
static func capture_path(user_args: PackedStringArray, engine_args: PackedStringArray, def_path: String) -> String:
	for args in [user_args, engine_args]:
		for a in args:
			if a == "--capture":
				return def_path
			if a.begins_with("--capture="):
				var p: String = a.trim_prefix("--capture=")
				return p if p != "" else def_path
	return ""


## Capture's outcome for a finished run (RaidCapture.write): the result's own flags, and "timeout" when it has
## none of them (only the measuring bot's time-out ends a run so: no exit, the last checkpoint's loot).
static func capture_exit(relish_died: bool, warden_beaten: bool, retreated: bool) -> String:
	if relish_died:
		return "relish_died"
	if warden_beaten:
		return "warden_beaten"
	return "retreated" if retreated else "timeout"


## Capture's outcome for a run that ends with no `finished` (a standalone window close, the scene freed): the
## ending a beat was already playing when there is one (`pending`, RaidEndings.pending_exit: a close during
## the death beat is the death, with its killer), else `why` ("closed", "freed").
static func capture_unfinished(why: String, pending: String) -> String:
	return pending if pending in ["relish_died", "warden_beaten"] else why


## A tell-attack's outcome on the game side, first match: "struck" (its blow reached her hp), "countered"
## (the warden's counter took it: muffled, intercepted, pinned, snuffed), "dodged" (it was aimed at her:
## her edge warned through its tell, or a toll was placed at her feet), else "clear" (it never reached her).
static func capture_outcome(struck: bool, countered: bool, aimed: bool) -> String:
	if struck:
		return "struck"
	if countered:
		return "countered"
	if aimed:
		return "dodged"
	return "clear"


## Count one closed tell into a capture tally {kind: {tells, shown, struck, countered, dodged, clear,
## cancelled}}: `shown` when she stood in the warden's room as it began; `outcome` one capture_outcome gives,
## or "cancelled" (a horn took it before it struck).
static func capture_count(tally: Dictionary, kind: String, outcome: String, shown: bool) -> void:
	if not tally.has(kind):
		tally[kind] = {"tells": 0, "shown": 0, "struck": 0, "countered": 0, "dodged": 0, "clear": 0, "cancelled": 0}
	var k: Dictionary = tally[kind]
	k["tells"] = int(k["tells"]) + 1
	if shown:
		k["shown"] = int(k["shown"]) + 1
	if k.has(outcome):
		k[outcome] = int(k[outcome]) + 1
