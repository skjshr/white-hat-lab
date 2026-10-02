extends RefCounted

# Representative legacy-schema fixtures, not recovered release artifacts.
# VM.setup accepts schema=2 without the service-specific v2 model marker;
# it keeps flat applied configuration and the legacy HTTP implementation.
# Measure through that implementation, then serialize as a real save would.
# Never assign passed/fresh flags or synthesize response/measurement hashes.
static func measured(chapter: int) -> Dictionary:
	assert(chapter in [2,5])
	var VM = load("res://scripts/virtual_machine.gd")
	var source = VM.new()
	source.setup(chapter)
	var saved: Dictionary = source.export_state()
	var prefix := "firewall_" if chapter == 2 else "portal_"
	for key in saved.keys():
		if str(key).begins_with(prefix): saved.erase(key)
	if chapter == 2:
		saved.applied = {"dns":"on","business":"allow","admin_public":"deny","tls":"on"}
		saved.fs[str(saved.config_path)] = "dns=on\nbusiness=allow\nadmin_public=deny\ntls=on\n"
	else:
		saved.applied = {"staff":"write","partner":"read","public":"none","expires":"7d","mfa":"on","tls":"on","audit":"on"}
		saved.fs[str(saved.config_path)] = "staff=write\npartner=read\npublic=none\nexpires=7d\nmfa=on\ntls=on\naudit=on\n"
		# The v1 portal renders a virtual document; loading it must not invent
		# v2 file storage, shares, versions, or activity history.
		saved.fs.erase("/srv/share/partner-order.csv")
	saved.erase("probes")
	var machine = VM.new()
	machine.setup(chapter,saved)
	machine.run("ssh client")
	for probe in machine.probes(): machine.execute_probe(str(probe.id))
	return JSON.parse_string(JSON.stringify(machine.export_state()))
