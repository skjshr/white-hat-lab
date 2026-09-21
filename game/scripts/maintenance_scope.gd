extends RefCounted

# The current simulation gives each client one service host per chapter and
# one or more sites. Contract IDs are not asset IDs: a later repair can update
# the same host without discarding unrelated hosts or other sites.
static func normalize(targets: Array) -> Array:
	var result: Array=[];var ordinals: Dictionary={}
	for source in targets:
		if not source is Dictionary:continue
		var target: Dictionary=source.duplicate(true)
		var chapter:=int(target.get("chapter",0));var ordinal:=int(ordinals.get(chapter,0))
		ordinals[chapter]=ordinal+1
		if str(target.get("asset_id","")).is_empty():target.asset_id="service-%d/site-%d" % [chapter,ordinal]
		result.append(target)
	return result

static func merge(existing: Array,incoming: Array) -> Array:
	var result:=normalize(existing);var additions:=normalize(incoming)
	for target in additions:
		var found:=false
		for index in result.size():
			if str(result[index].asset_id)==str(target.asset_id):result[index]=target;found=true;break
		if not found:result.append(target)
	return result

static func migrate(g) -> bool:
	if int(g.state.get("maintenance_scope_version",1))>=2:return false
	var recovered: Dictionary={}
	# History supplies delivery order; only completed, explicitly contracted
	# care projects with surviving VM data are evidence for a recoverable asset.
	for receipt in g.state.history:
		var id:=str(receipt.get("id",""));var context: Dictionary=g.state.contract_contexts.get(id,{})
		if not bool(context.get("completed",false)) or str(context.get("contract_plan",""))!="care":continue
		var client:=str(context.get("contract",{}).get("client",""))
		if not g.state.care_agreements.has(client):continue
		var targets: Array=[];var ordinals: Dictionary={}
		for index in context.get("targets",[]).size():
			var source: Dictionary=context.targets[index];var chapter:=int(source.get("chapter",context.get("chapter",0)))
			var ordinal:=int(ordinals.get(chapter,0));ordinals[chapter]=ordinal+1
			var key: String=id+"/site-"+str(index);var saved: Dictionary=g.state.vm_states.get(key,{})
			if saved.is_empty():continue
			targets.append({"asset_id":str(source.get("maintenance_asset_id","service-%d/site-%d" % [chapter,ordinal])),"chapter":chapter,"vm_key":key,"vm_state":saved.duplicate(true),"scenario":saved.get("scenario",{}).duplicate(true)})
		recovered[client]=merge(recovered.get(client,[]),targets)
	for client in g.state.maintenance_targets.keys():
		var previous:=normalize(g.state.maintenance_targets[client])
		# Current operational snapshots (including incident drift) always win.
		var targets:=merge(recovered.get(client,[]),previous)
		g.state.maintenance_targets[client]=targets
		if targets.size()<=previous.size():continue
		var job: Dictionary=g._maintenance_job_for(client)
		if job.is_empty():continue
		job.targets=targets.duplicate(true);job.result="";job.remaining=float(job.get("total",12.0))
		if str(job.get("status",""))=="working":
			job.erase("work_started_at");job.erase("work_started_day")
			g._assignments[str(job.get("assignee",""))]=job.duplicate(true)
		else:job.status="pending";job.assignee=""
	g.state.assignments=g._assignments.duplicate(true)
	g.state.maintenance_scope_version=2
	return true

static func retain_delivery(g,client: String,incoming: Array) -> void:
	var previous: Array=g._maintenance_targets_for(client)
	var additions:=normalize(incoming);var targets:=merge(previous,additions)
	var replaced: Dictionary={}
	for target in additions:replaced[str(target.asset_id)]=true
	var existing: Dictionary=g._maintenance_job_for(client)
	var checked: Dictionary={}
	if str(existing.get("status",""))=="done":
		for target in normalize(existing.get("targets",[])):checked[str(target.asset_id)]=target
	var all_verified:=true
	for target in targets:
		var id:=str(target.asset_id)
		if replaced.has(id):continue
		if not checked.has(id) or checked[id].get("vm_state",{})!=target.get("vm_state",{}):all_verified=false
	if str(g.state.care_incidents.get(client,{}).get("status","closed"))!="closed":all_verified=false
	# An in-flight assignment remains the authority until its refreshed check
	# finishes, including a delivery replacing the client's entire scope.
	if str(existing.get("status","")) in ["working","queued","paused"]:all_verified=false
	g.state.maintenance_targets[client]=targets
	var job: Dictionary={"id":"maintenance-%s-%d" % [client,int(g.state.day)],"client":client,"day":int(g.state.day),"status":"done" if all_verified else "pending","assignee":"verified" if all_verified else "","remaining":0.0 if all_verified else 12.0,"total":12.0,"fee":int(g.state.care_agreements.get(client,{}).get("fee",150)),"cost":100,"minutes":12.0,"result":"PASS\nverified at delivery" if all_verified else "","paid":bool(existing.get("paid",false)),"missed_day":int(existing.get("missed_day",-1)),"targets":targets.duplicate(true)}
	# A newly delivered service joins the scheduled inspection. Preserve its
	# identity and effort, while every future probe uses the expanded live scope.
	var status:=str(existing.get("status",""))
	if status in ["working","queued","paused"]:
		for field in ["id","status","assignee","remaining","total","minutes"]:
			if existing.has(field):job[field]=existing[field]
		if status=="working":
			var member:=str(existing.get("assignee","")); var active: Dictionary=g._assignments.get(member,{})
			if not active.is_empty():
				active.targets=targets.duplicate(true); active.maintenance_job_id=str(job.id)
				job.remaining=float(active.get("remaining",job.remaining))
				g.state.assignments=g._assignments.duplicate(true)
	if existing.is_empty():g.state.maintenance_jobs.append(job)
	else:existing.clear();existing.merge(job,true)
