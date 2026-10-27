extends SceneTree
## Two production HTTPRequest clients in ONE headless Godot process. This is
## protocol/lifecycle acceptance, not two GUI games or remote-avatar rendering.
const CLIENT := preload("res://scripts/multiplayer/room_presence_client.gd")
var _a: Node
var _b: Node
var _last_a: Dictionary={}
var _last_b: Dictionary={}
var _sample_a: Dictionary={"position":[0.,0.,0.],"yaw":.2,"motion":"idle","avatar":{"modelId":"SeoulResident_M01","bodyProfile":"standard","swimwear":false}}
var _sample_b: Dictionary={"position":[0.,0.,0.],"yaw":-.2,"motion":"idle","avatar":{"modelId":"SeoulResident_F01","bodyProfile":"soft","swimwear":false}}
var _secrets: Array[String]=[]
var _checks: Array=[]
var _timeline: Array=[]
var _started_ms:=0
var _report:=""
var _base:="http://127.0.0.1:8766"
var _gzip_base:=""
var _finished:=false

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):_report=argument.trim_prefix("--report=")
		if argument.begins_with("--base="):_base=argument.trim_prefix("--base=")
		if argument.begins_with("--gzip-base="):_gzip_base=argument.trim_prefix("--gzip-base=")
	if not _report.is_absolute_path():quit(2);return
	_run.call_deferred()

func _provider_a() -> Dictionary:return _sample_a.duplicate(true)
func _provider_b() -> Dictionary:return _sample_b.duplicate(true)

func _public_snapshot(value: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for key: String in ["protocol","room","players","serverNowMs"]:
		if value.has(key):result[key]=value[key].duplicate(true) if value[key] is Dictionary or value[key] is Array else value[key]
	return result

func _check(label_: String,passed: bool) -> void:
	_checks.append({"name":label_,"passed":passed})
	if not passed:push_warning("ROOM_PRESENCE_CHECK_FAIL "+label_)

func _until(predicate: Callable,timeout_ms:=6000) -> bool:
	var deadline:=Time.get_ticks_msec()+timeout_ms
	while Time.get_ticks_msec()<deadline:
		if predicate.call():return true
		await process_frame
	return bool(predicate.call())

func _wait(milliseconds: int) -> void:
	var deadline:=Time.get_ticks_msec()+milliseconds
	while Time.get_ticks_msec()<deadline:await process_frame

func _seen(snapshot: Dictionary,id: String,point: Array) -> bool:
	for row: Dictionary in snapshot.get("players",[]):
		if row.id!=id:continue
		return Vector3(row.position[0],row.position[1],row.position[2]).distance_to(Vector3(point[0],point[1],point[2]))<.025
	return false

func _remember_credentials(client: Node) -> void:
	for value: String in [client._token,client._cookie,client.invite,client.invite_code()]:
		if not value.is_empty() and not _secrets.has(value):_secrets.append(value)

func _observe(stage: String) -> void:
	_timeline.append({"stage":stage,"elapsed_ms":Time.get_ticks_msec()-_started_ms,"a":_a.diagnostic(),"b":_b.diagnostic()})

func _run() -> void:
	Engine.max_fps=60;_started_ms=Time.get_ticks_msec()
	_a=CLIENT.new();_b=CLIENT.new();root.add_child(_a);root.add_child(_b)
	_check("two_production_clients_configure",_a.configure(_base,_provider_a) and _b.configure(_base,_provider_b))
	_check("gzip_policy_matches_runtime_transport",_a._http.accept_gzip==(not OS.has_feature("web")) and _b._http.accept_gzip==(not OS.has_feature("web")))
	_a.snapshot_received.connect(func(value: Dictionary)->void:_last_a=_public_snapshot(value))
	_b.snapshot_received.connect(func(value: Dictionary)->void:_last_b=_public_snapshot(value))
	paused=true
	_a.check_service();_b.check_service()
	var ready: bool=await _until(func()->bool:return _a.available and _b.available and not _a.busy() and not _b.busy())
	_check("actual_bootstrap_completes_with_scene_tree_paused",paused and ready)
	paused=false
	_check("actual_status_then_dev_session_cookie_both_ready",ready)
	if not ready:await _finish();return
	_check("native_cookie_has_only_server_name_value",not _a._cookie.is_empty() and not _b._cookie.is_empty() and not _a._cookie.contains(";") and not _b._cookie.contains(";"))
	_check("independent_server_cookie_identities",_a._cookie!=_b._cookie)
	_remember_credentials(_a);_remember_credentials(_b);_observe("ready")
	_check("create_request_started",_a.create_room())
	var created: bool=await _until(func()->bool:return _a.connected and not _a.busy())
	_check("actual_create_returns_connected_owner",created)
	if not created:await _finish();return
	var invite_code: String=_a.invite_code();_remember_credentials(_a)
	_check("join_request_started",_b.join_room(invite_code))
	var joined: bool=await _until(func()->bool:return _a.connected and _b.connected and _a.participant_count==2 and _b.participant_count==2)
	_check("both_clients_observe_two_participants",joined)
	if not joined:await _finish();return
	_remember_credentials(_b)
	var old_b_id: String=_b.self_id;var old_b_token: String=_b._token;var old_b_cookie: String=_b._cookie
	_check("same_room_distinct_self_ids",_a.room_id==_b.room_id and _a.self_id!=old_b_id)
	_check("both_start_at_same_server_spawn",_seen(_last_a,old_b_id,[0.,0.,0.]) and _seen(_last_b,_a.self_id,[0.,0.,0.]))
	_observe("joined")
	for step in range(1,11):
		_sample_a.position=[float(step)/10.,0.,0.];_sample_a.motion="walk"
		_sample_b.position=[0.,0.,float(step)/10.];_sample_b.motion="walk"
		await _wait(200)
	var mutual: bool=await _until(func()->bool:return _seen(_last_a,old_b_id,[0.,0.,1.]) and _seen(_last_b,_a.self_id,[1.,0.,0.]),3000)
	_check("actual_550ms_sync_both_observe_peer_one_metre_walk",mutual)
	await _wait(1800)
	_check("repeated_production_snapshots_continue",_a.received_snapshots>=5 and _b.received_snapshots>=4 and _a.connected and _b.connected)
	_observe("mutual_walk")
	# Observe the real automatic request in flight; do not raise polling frequency.
	var in_flight: bool=await _until(func()->bool:return _b.busy() and _b._pending=="sync",2000)
	_check("observed_live_sync_before_cancel_leave",in_flight)
	_b.leave_room()
	var left: bool=await _until(func()->bool:return not _b.connected and not _b.busy() and _b.state=="ready",3000)
	_check("cancel_then_leave_completes_ready",left)
	var removed: bool=await _until(func()->bool:return _a.connected and _a.participant_count==1 and _last_a.get("players",[]).size()==1,3000)
	_check("owner_observes_departed_peer_removed",removed)
	_check("leave_clears_room_bearer_and_invite_memory",_b._token.is_empty() and _b.invite.is_empty() and _b.self_id.is_empty() and _b.room_id.is_empty())
	_observe("peer_left")
	_check("rejoin_request_started",_b.join_room(invite_code))
	var rejoined: bool=await _until(func()->bool:return _b.connected and _a.participant_count==2 and _b.participant_count==2,4000)
	_check("actual_rejoin_rotates_self_and_room_session",rejoined and _b.self_id!=old_b_id and _b._token!=old_b_token and _b._cookie==old_b_cookie)
	_remember_credentials(_b)
	var resumed: bool=await _until(func()->bool:return _seen(_last_a,_b.self_id,[0.,0.,1.]) and _seen(_last_b,_a.self_id,[1.,0.,0.]),3000)
	_check("mutual_snapshots_resume_after_rejoin",resumed)
	await _wait(1000);_observe("rejoined")
	_negative_fixtures()
	await _unavailable_endpoint()
	if not _gzip_base.is_empty():await _gzip_responses()
	var diagnostics:=JSON.stringify({"a":_a.diagnostic(),"b":_b.diagnostic()})
	var secrets_excluded:=true
	for secret: String in _secrets:secrets_excluded=secrets_excluded and not diagnostics.contains(secret)
	_check("all_real_bearers_cookies_invites_excluded_from_diagnostic",secrets_excluded and not _secrets.is_empty())
	await _finish()

func _negative_fixtures() -> void:
	var fixture:=CLIENT.new();root.add_child(fixture);fixture.configure(_base,_provider_a);fixture.set_process(false)
	fixture.room_id=_a.room_id;fixture.self_id=_a.self_id;fixture.connected=true;fixture.available=true
	var valid:=_last_a.duplicate(true)
	_check("current_public_snapshot_valid",fixture._valid_snapshot(valid))
	var malformed: Array=[]
	var wrong_room:=valid.duplicate(true);wrong_room.room.id=("0" if fixture.room_id[0]!="0" else "1")+fixture.room_id.substr(1);malformed.append(wrong_room)
	var missing_self:=valid.duplicate(true);missing_self.players=missing_self.players.filter(func(row: Dictionary)->bool:return row.id!=fixture.self_id);malformed.append(missing_self)
	var wrong_self:=valid.duplicate(true);wrong_self.selfId=_b.self_id;malformed.append(wrong_self)
	var duplicate:=valid.duplicate(true);duplicate.players.append(duplicate.players[0].duplicate(true));malformed.append(duplicate)
	var bad_build:=valid.duplicate(true);bad_build.room.buildId="different-build";malformed.append(bad_build)
	var bad_protocol:=valid.duplicate(true);bad_protocol.protocol="other";malformed.append(bad_protocol)
	var bad_position:=valid.duplicate(true);bad_position.players[0].position=[INF,0.,0.];malformed.append(bad_position)
	var bad_sequence:=valid.duplicate(true);bad_sequence.players[0].sequence=1.5;malformed.append(bad_sequence)
	var bad_yaw:=valid.duplicate(true);bad_yaw.players[0].yaw=PI+.1;malformed.append(bad_yaw)
	var bad_avatar:=valid.duplicate(true);bad_avatar.players[0].avatar.modelId="../private.glb";malformed.append(bad_avatar)
	var rejected:=0
	for value: Dictionary in malformed:
		if not fixture._valid_snapshot(value):rejected+=1
	_check("ten_malformed_snapshot_fixtures_rejected",rejected==malformed.size())
	fixture._pending="sync";fixture._sent_ms=Time.get_ticks_msec()
	fixture._completed(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(["Content-Type: application/json"]),JSON.stringify(wrong_room).to_utf8_buffer())
	_check("invalid_snapshot_not_published_as_accepted_state",fixture.received_snapshots==0 and fixture.connected)
	var retry_safe:=true
	for value: Variant in [{},[],"bad",false,-1.,INF,1e100,0.,550.]:
		var before:=Time.get_ticks_msec();fixture._request_failure("sync",429,{"retryAfterMs":value})
		var delay: int=fixture._next_sync_ms-before
		retry_safe=retry_safe and delay>=550 and delay<=60_010 and fixture.connected
	_check("malformed_429_retry_values_never_cast_unsafely",retry_safe)
	fixture._failures=0
	var before_reject:=Time.get_ticks_msec()
	fixture._request_failure("sync",422,{"error":"world_movement_out_of_range"})
	_check("rejected_world_proposal_keeps_connection_for_bounded_fresh_sample",fixture.connected and fixture._failures==1 and fixture._next_sync_ms-before_reject>=1000 and fixture._next_sync_ms-before_reject<=1010 and fixture.received_snapshots==0 and fixture.last_failure_code=="world_movement_out_of_range")
	fixture._pending="sync";fixture._sent_ms=Time.get_ticks_msec()
	fixture._completed(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(["Content-Type: application/json"]),JSON.stringify(valid).to_utf8_buffer())
	_check("accepted_fresh_sample_resets_rejection_budget",fixture.connected and fixture._failures==0 and fixture.received_snapshots==1)
	# Prevent the injected fixture from sending leave with another client's IDs.
	fixture.room_id="";fixture.self_id=""
	for _attempt in range(3):fixture._request_failure("sync",422,{"error":"world_movement_out_of_range"})
	_check("three_consecutive_rejected_samples_end_connection_safely",not fixture.connected and fixture._failures==3)
	fixture.connected=false;fixture._pending="status";fixture._cookie="fixture-cookie"
	fixture._completed(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(["Content-Type: application/json"]),JSON.stringify({"available":false}).to_utf8_buffer())
	_check("unsupported_status_keeps_solo_available_with_no_session_memory",fixture.state=="unavailable" and not fixture.available and fixture._cookie.is_empty() and not fixture.connected)
	var response_failures: Array=[
		{"result":HTTPRequest.RESULT_CANT_CONNECT,"code":0,"headers":PackedStringArray(),"body":PackedByteArray()},
		{"result":HTTPRequest.RESULT_SUCCESS,"code":200,"headers":PackedStringArray(["Content-Type: application/json"]),"body":PackedByteArray()},
		{"result":HTTPRequest.RESULT_SUCCESS,"code":200,"headers":PackedStringArray(["Content-Type: text/html"]),"body":"<html>not protocol</html>".to_utf8_buffer()},
		{"result":HTTPRequest.RESULT_SUCCESS,"code":200,"headers":PackedStringArray(["Content-Type: application/json"]),"body":"{".to_utf8_buffer()},
	]
	var safe_failures:=true
	for response: Dictionary in response_failures:
		fixture._pending="status";fixture._sent_ms=Time.get_ticks_msec()
		fixture._completed(response.result,response.code,response.headers,response.body)
		safe_failures=safe_failures and fixture.state=="unavailable" and fixture.last_http_result==response.result and fixture.last_http_code==response.code and fixture.last_response_bytes==response.body.size()
	_check("empty_nonjson_malformed_and_transport_failures_stay_in_state",safe_failures)
	fixture._pending="status";fixture._sent_ms=Time.get_ticks_msec()
	fixture._completed(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(["Content-Type: application/json"]),JSON.stringify({"available":true,"apiVersion":1,"mode":"sites","signInRequired":true}).to_utf8_buffer())
	_check("sites_status_flag_requires_signin_with_fixed_same_origin_url",fixture.available and fixture.sign_in_required and not fixture.create_room() and fixture.sign_in_url()==_base+"/signin-with-chatgpt?return_to=%2Fplay.html")
	fixture.sign_in_required=false;fixture.connected=true;fixture._token="fixture-token";fixture._pending="create";fixture._sent_ms=Time.get_ticks_msec()
	fixture._completed(HTTPRequest.RESULT_SUCCESS,401,PackedStringArray(["Content-Type: application/json"]),JSON.stringify({"error":"sign_in_required"}).to_utf8_buffer())
	_check("sites_401_requires_signin_without_login_request_or_retained_room_token",fixture.sign_in_required and not fixture.connected and fixture._token.is_empty() and fixture.state=="ready" and not fixture.busy())
	fixture.queue_free()

func _unavailable_endpoint() -> void:
	var unreachable:=CLIENT.new();root.add_child(unreachable)
	_check("unavailable_loopback_endpoint_configures",unreachable.configure("http://127.0.0.1:1",_provider_a))
	unreachable.check_service()
	var unavailable: bool=await _until(func()->bool:return unreachable.state=="unavailable" and not unreachable.busy(),7000)
	_check("actual_unavailable_endpoint_records_transport_and_preserves_solo",unavailable and not unreachable.available and unreachable.last_http_code==0 and (unreachable.last_http_result!=HTTPRequest.RESULT_SUCCESS or unreachable.last_request_error!=OK) and unreachable.notice.contains("혼자 탐험"))
	unreachable.queue_free()

func _gzip_responses() -> void:
	# The last two HTTP responses retain Content-Encoding but contain JSON,
	# reproducing Fetch's already-decoded body at HTTPClientWeb's boundary.
	for index in range(4):
		var fixture:=CLIENT.new();root.add_child(fixture)
		var configured: bool=fixture.configure(_gzip_base,_provider_a)
		if index>=2:fixture._http.accept_gzip=false
		fixture.check_service()
		var completed: bool=await _until(func()->bool:return not fixture.busy(),6000)
		var names: Array[String]=["native_gzip_response_decoded_once","native_deflate_response_decoded_once","browser_decoded_gzip_body_not_decoded_twice","browser_decoded_deflate_body_not_decoded_twice"]
		_check(names[index],configured and completed and fixture.available and fixture.sign_in_required and fixture.state=="ready" and fixture.last_http_result==HTTPRequest.RESULT_SUCCESS and fixture.last_http_code==200 and fixture.last_response_bytes>0)
		fixture.queue_free();await process_frame

func _finish() -> void:
	if _finished:return
	_finished=true
	for client: Node in [_a,_b]:
		if is_instance_valid(client):client.leave_room()
	await _until(func()->bool:return not _a.busy() and not _b.busy(),2500)
	var failed:=0
	for row: Dictionary in _checks:
		if not row.passed:failed+=1
	var result:={"task":"EXP40_PRODUCTION_PRESENCE_CLIENT","result":"PASS" if failed==0 else "FAIL","checks":_checks.size(),"failed":failed,"cases":_checks,"timeline":_timeline,"elapsed_ms":Time.get_ticks_msec()-_started_ms,"engine":Engine.get_version_info().string,"transport":"Two actual production Node HTTPRequest clients, one headless Godot process, root-owned loopback host and actual SQLite adapter","client_sha256":FileAccess.get_sha256("res://scripts/multiplayer/room_presence_client.gd"),"scope":"Actual status, native development cookie, create/join, 550ms accepted movement in both directions, in-flight sync cancellation followed by leave, peer removal and credential-rotating rejoin. Negative snapshot/retry/status fixtures are injected and labelled. No two-GUI-game, 3D remote actor, public hosting, production identity or concurrency/performance acceptance. Credentials and invite codes are never written to this report."}
	if not _gzip_base.is_empty():result["gzip_fixture_scope"]="Four actual loopback HTTP responses: native gzip/deflate defaults and explicitly disabled decompression with already-decoded JSON retaining gzip/deflate headers. The latter emulate Fetch's transport boundary; they are not browser execution."
	var file:=FileAccess.open(_report,FileAccess.WRITE)
	if file==null:push_error("Could not save room client report");quit(1);return
	file.store_string(JSON.stringify(result,"  ")+"\n");file.close()
	_a.queue_free();_b.queue_free();await process_frame
	print("ROOM_PRESENCE_CLIENT_CHECK result=",result.result," checks=",result.checks," failed=",failed," elapsed_ms=",result.elapsed_ms)
	quit(0 if failed==0 else 1)
