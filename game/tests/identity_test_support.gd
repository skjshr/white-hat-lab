extends RefCounted
static func authenticate_current(game) -> bool:
	var vm=game._vm()
	if int(vm.state.get("identity_model_version",1))<2: return true
	var snapshot: Dictionary=vm.identity_snapshot()
	var users: Array=snapshot.get("users",[])
	var current: Array=users.filter(func(user):return str(user.user)=="current")
	if current.is_empty() or not bool(current[0].enabled): return true
	var response=JSON.parse_string(game.vm_run("identity login current Training-117!"))
	if not response is Dictionary or not bool(response.get("ok",false)): return false
	if response.has("challenge"):
		response=JSON.parse_string(game.vm_run("identity otp "+str(response.challenge)+" 123456"))
	return response is Dictionary and bool(response.get("ok",false)) and response.has("token")
