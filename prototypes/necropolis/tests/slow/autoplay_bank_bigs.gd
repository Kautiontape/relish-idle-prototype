extends RefCounted
## E3-7, the autoplayer's `bank_bigs` profile (tests/autoplay/autoplayer.gd; IDLE §8; the manager's ruling 4 at the
## E3-6b stop): sessions, but once the giants or carvers front is short no raid takes a big. Between raids the party
## holds the bigs on giants and carvers (only a party member has a front); before each raid it is emptied, so the bot
## raids t1 only and no big goes through the held door. It runs the sessions baseline alongside and prints the delta,
## in days to Vei-ready or in fronts and backlog at the end. 8 days (AUTOPLAY_DAYS=n sets it).
## tests/run.sh --slow --only=autoplay_bank_bigs

var t := TestUtil.new()


func run() -> int:
	return Autoplayer.run_profile("bank_bigs", t)
