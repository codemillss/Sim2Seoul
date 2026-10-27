extends Node
## Small presence protocol client. Tokens/cookies remain in memory only.
## It does not drive local movement or own shared world/vehicle/combat results.
signal changed
signal snapshot_received(value: Dictionary)
signal joined(owner: bool,value: Dictionary)
signal action_result(value: Dictionary)
const BUILD_ID := "sim2seoul-shared-world-v2"
const PROTOCOL := "sim2seoul-presence-v1"
var state := "offline"
var notice := "친구와 같은 도시에 들어와 함께 걸어보세요."
var available := false
var connected := false
var sign_in_required := false
var room_id := ""
var self_id := ""
var invite := ""
var participant_count := 0
var last_round_trip_ms := 0
var last_http_result := -1
var last_http_code := 0
var last_response_bytes := 0
var last_request_error := OK
var last_failure_code := ""
var received_snapshots := 0
var _base := ""
var _sample: Callable
var _http: HTTPRequest
var _pending := ""
var _token := ""
var _cookie := ""
var _mode := ""
var _sequence := 0
var _next_sync_ms := 0
var _sent_ms := 0
var _interval_ms := 550
var _failures := 0
var _leave_notice := "함께 걷기를 마쳤습니다."
var world: Dictionary={}
var _catalog_provider: Callable
var _authority_provider: Callable
var _drive_provider: Callable
var _actions: Array[Dictionary]=[]
var _delivered_actions: Dictionary={}
var _world_sequence := 0

func configure_world(catalog: Callable,authority: Callable,drive: Callable) -> bool:
	if connected or busy() or not catalog.is_valid() or not authority.is_valid() or not drive.is_valid():return false
	_catalog_provider=catalog;_authority_provider=authority;_drive_provider=drive
	return true

func request_action(type: String,entity_id: String) -> String:
	if not connected or _actions.size()>=8 or type not in ["vehicle_enter","vehicle_exit","npc_greet","npc_pet","npc_hit","npc_shove"] or not _entity_id(entity_id):return ""
	var bytes:=Crypto.new().generate_random_bytes(16)
	if bytes.size()!=16:return ""
	bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128
	var encoded:=bytes.hex_encode()
	var id:=encoded.substr(0,8)+"-"+encoded.substr(8,4)+"-"+encoded.substr(12,4)+"-"+encoded.substr(16,4)+"-"+encoded.substr(20,12)
	_actions.append({"requestId":id,"type":type,"entityId":entity_id})
	return id

func configure(base_url: String,sample_provider: Callable) -> bool:
	if is_instance_valid(_http) or not sample_provider.is_valid():return false
	var expression:=RegEx.new()
	expression.compile("^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?$")
	_base=base_url.trim_suffix("/")
	if expression.search(_base)==null:return false
	_sample=sample_provider;process_mode=Node.PROCESS_MODE_ALWAYS
	_http=HTTPRequest.new();_http.timeout=6.;_http.body_size_limit=131072;_http.max_redirects=0
	# Fetch already decodes HTTP content while retaining Content-Encoding.
	if OS.has_feature("web"):_http.accept_gzip=false
	add_child(_http);_http.request_completed.connect(_completed)
	return true

func busy() -> bool:return not _pending.is_empty()

func check_service() -> void:
	if connected or busy():return
	_set_state("checking","함께 걷기를 준비하고 있어요.")
	_request("status","/api/multiplayer/status",HTTPClient.METHOD_GET,{})

func create_room() -> bool:
	if not available or connected or busy() or sign_in_required:return false
	var sample: Dictionary=_sample.call()
	if sample.is_empty():_set_state("ready","야외에서 걸을 수 있는 상태로 방을 만들어 주세요.");return false
	_set_state("creating","새 방을 만들고 있어요.")
	var data:={"buildId":BUILD_ID,"avatar":sample.avatar,"position":sample.position,"yaw":sample.yaw}
	if _catalog_provider.is_valid():
		var entities: Array=_catalog_provider.call()
		if entities.is_empty():_set_state("ready","공동 도시의 차량과 주민을 준비하지 못했습니다.");return false
		data["world"]={"entities":entities}
	return _request("create","/api/multiplayer/rooms",HTTPClient.METHOD_POST,data)

func join_room(code: String) -> bool:
	if not available or connected or busy() or sign_in_required:return false
	var parts:=code.strip_edges().split(".")
	var pattern:=RegEx.new();pattern.compile("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
	var secret:=RegEx.new();secret.compile("^[0-9a-f]{32}$")
	if parts.size()!=2 or pattern.search(parts[0])==null or secret.search(parts[1])==null:
		_set_state("ready","초대 코드를 다시 확인해 주세요.");return false
	var sample: Dictionary=_sample.call()
	if sample.is_empty():_set_state("ready","야외에서 걸을 수 있는 상태로 참가해 주세요.");return false
	room_id=parts[0];invite=parts[1]
	_set_state("joining","같은 도시로 들어가고 있어요.")
	return _request("join","/api/multiplayer/rooms/"+room_id+"/join",HTTPClient.METHOD_POST,{"invite":invite,"buildId":BUILD_ID,"avatar":sample.avatar})

func invite_code() -> String:
	return room_id+"."+invite if connected and not invite.is_empty() else ""

func sign_in_url() -> String:
	return _base+"/signin-with-chatgpt?return_to=%2Fplay.html" if _mode=="sites" else ""

func leave_room(message: String="함께 걷기를 마쳤습니다.") -> void:
	if not connected:
		if busy():_http.cancel_request();_pending=""
		_clear_room();_set_state("ready" if available else "offline",message);return
	_leave_notice=message
	if busy():_http.cancel_request();_pending=""
	connected=false
	_set_state("leaving","함께 걷기를 마무리하고 있어요.")
	_request("leave",_player_path("leave"),HTTPClient.METHOD_POST,{})

func _player_path(action: String) -> String:
	return "/api/multiplayer/rooms/"+room_id+"/players/"+self_id+"/"+action

func _request(operation: String,path: String,method: int,body: Dictionary) -> bool:
	if busy() or not is_instance_valid(_http):return false
	var headers:=PackedStringArray(["Accept: application/json"])
	if method==HTTPClient.METHOD_POST:headers.append("Content-Type: application/json")
	if not OS.has_feature("web"):
		if method==HTTPClient.METHOD_POST:headers.append("Origin: "+_base)
		if not _cookie.is_empty():headers.append("Cookie: "+_cookie)
	if not _token.is_empty():headers.append("Authorization: Bearer "+_token)
	_pending=operation;_sent_ms=Time.get_ticks_msec()
	changed.emit()
	var error:=_http.request(_base+path,headers,method,JSON.stringify(body) if method==HTTPClient.METHOD_POST else "")
	last_request_error=error
	if error!=OK:
		_pending="";_request_failure(operation,0,{})
		return false
	return true

func _completed(result: int,code: int,headers: PackedStringArray,bytes: PackedByteArray) -> void:
	var operation:=_pending
	if operation.is_empty():return
	_pending="";last_round_trip_ms=Time.get_ticks_msec()-_sent_ms
	last_http_result=result;last_http_code=code;last_response_bytes=bytes.size()
	if result!=HTTPRequest.RESULT_SUCCESS:
		_request_failure(operation,code,{});return
	var media_type:=""
	for header: String in headers:
		if header.to_lower().begins_with("content-type:"):media_type=header.substr(13).strip_edges().get_slice(";",0).strip_edges().to_lower()
	if bytes.is_empty() or media_type!="application/json":
		_request_failure(operation,code if code<200 or code>=300 else 0,{"error":"invalid_json_response"});return
	# JSON.parse_string logs engine errors for empty/malformed transport bodies.
	# The parser instance returns an error code so failures stay in client state.
	var parser:=JSON.new()
	if parser.parse(bytes.get_string_from_utf8())!=OK or not parser.data is Dictionary:
		_request_failure(operation,code if code<200 or code>=300 else 0,{"error":"invalid_json_response"});return
	var value: Dictionary=parser.data
	if code<200 or code>=300:
		_request_failure(operation,code,value);return
	if operation=="status":
		if value.get("available")!=true or value.get("apiVersion")!=1 or value.get("mode","") not in ["local_development","sites"]:
			_unavailable();return
		_mode=String(value.mode)
		sign_in_required=_mode=="sites" and value.get("signInRequired")==true
		if _mode=="local_development":_request("session","/api/multiplayer/dev-session",HTTPClient.METHOD_POST,{})
		else:available=true;_set_state("ready","함께 걷기는 로그인 후 이용할 수 있습니다." if sign_in_required else "방을 만들거나 받은 초대 코드로 참가해 주세요.")
		return
	if operation=="session":
		if value.get("developmentOnly")!=true:_unavailable();return
		if not OS.has_feature("web"):
			for header: String in headers:
				if header.to_lower().begins_with("set-cookie:"):_cookie=header.substr(11).strip_edges().split(";")[0]
			if _cookie.is_empty():_unavailable();return
		available=true;_set_state("ready","방을 만들거나 받은 초대 코드로 참가해 주세요.");return
	if operation=="leave":
		_clear_room();_set_state("ready",_leave_notice);return
	if not _valid_snapshot(value):
		_request_failure(operation,0,{"error":"invalid_snapshot"});return
	world=value.get("world",{}).duplicate(true)
	if operation in ["create","join"]:
		if not _uuid(value.get("selfId")) or not _hex(value.get("sessionToken"),48):
			_request_failure(operation,0,{});return
		var own_present:=false
		for row: Dictionary in value.players:
			if row.id==value.selfId:own_present=true;break
		if not own_present or (operation=="create" and not _hex(value.get("invite"),32)):_request_failure(operation,0,{});return
		room_id=String(value.room.id);self_id=String(value.selfId);_token=String(value.sessionToken)
		if operation=="create":invite=String(value.get("invite",""))
		_sequence=0;connected=true;_failures=0
		_next_sync_ms=Time.get_ticks_msec()+_interval_ms
		_set_state("connected","같은 도시에 연결됐습니다. 야외에서 함께 걸어보세요.")
		joined.emit(operation=="create",value)
	else:
		_failures=0;_next_sync_ms=Time.get_ticks_msec()+_interval_ms
		_set_state("connected","같은 도시에 연결됐습니다. 야외에서 함께 걸어보세요.")
	if not connected:return
	participant_count=value.players.size();received_snapshots+=1
	if not world.is_empty():
		for receipt: Dictionary in world.get("actionResults",[]):
			if receipt.playerId!=self_id or _delivered_actions.has(receipt.requestId):continue
			for index in range(_actions.size()-1,-1,-1):
				if _actions[index].requestId==receipt.requestId:_actions.remove_at(index)
			_delivered_actions[receipt.requestId]=true
			while _delivered_actions.size()>64:_delivered_actions.erase(_delivered_actions.keys()[0])
			action_result.emit(receipt)
	snapshot_received.emit(value);changed.emit()

func _valid_snapshot(value: Dictionary) -> bool:
	if value.get("protocol")!=PROTOCOL or not value.get("room") is Dictionary or not value.get("players") is Array:return false
	if value.room.get("buildId")!=BUILD_ID or not _uuid(value.room.get("id")) or value.players.size()>8:return false
	if not room_id.is_empty() and value.room.id!=room_id:return false
	if connected and value.has("selfId") and value.selfId!=self_id:return false
	if not _number(value.get("serverNowMs")) or float(value.serverNowMs)<=0:return false
	var ids: Dictionary={}
	for row: Variant in value.players:
		if not row is Dictionary or not _uuid(row.get("id")) or ids.has(row.id):return false
		ids[row.id]=true
		if not _number(row.get("sequence")) or float(row.sequence)<0 or float(row.sequence)>2147483647 or fmod(float(row.sequence),1.)!=0:return false
		if not row.get("position") is Array or row.position.size()!=3:return false
		for component: Variant in row.position:
			if not _number(component):return false
		if absf(float(row.position[0]))>1000 or absf(float(row.position[2]))>1000 or float(row.position[1])< -100 or float(row.position[1])>500:return false
		if not _number(row.get("yaw")) or absf(float(row.yaw))>PI or not _number(row.get("updatedAtMs")):return false
		if row.get("motion","") not in ["idle","walk","run","jump","swim"]:return false
		if row.has("activity"):
			if not row.activity is Dictionary or row.activity.get("kind") not in ["walk","vehicle"]:return false
			if row.activity.kind=="vehicle" and not _entity_id(row.activity.get("entityId")):return false
		if not row.get("avatar") is Dictionary:return false
		if row.avatar.get("modelId","") not in ["SeoulResident_M01","SeoulResident_F01"] or row.avatar.get("bodyProfile","") not in ["standard","soft","athletic"] or not row.avatar.get("swimwear") is bool:return false
	if connected and not ids.has(self_id):return false
	if value.has("world") and not _valid_world(value.world,float(value.serverNowMs)):return false
	return true

func _entity_id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length()>96:return false
	var pattern:=RegEx.new();pattern.compile("^[A-Za-z0-9:_-]+$")
	return pattern.search(value)!=null

func _vector(value: Variant,position_: bool=false) -> bool:
	if not value is Array or value.size()!=3:return false
	for component: Variant in value:
		if not _number(component):return false
	return not position_ or (absf(value[0])<=1000 and absf(value[2])<=1000 and value[1]>=-100 and value[1]<=500)

func _valid_world(value: Variant,server_ms: float) -> bool:
	if not value is Dictionary or value.get("version")!=1 or not _uuid(value.get("hostId")):return false
	if not _number(value.get("sequence")) or value.sequence<0 or not _number(value.get("updatedAtMs")) or value.updatedAtMs>server_ms:return false
	if not value.get("entities") is Array or value.entities.size()>96 or value.entities.is_empty():return false
	var ids: Dictionary={}
	for row: Variant in value.entities:
		if not row is Dictionary or not _entity_id(row.get("id")) or ids.has(row.id) or row.get("kind") not in ["vehicle","npc","dog"]:return false
		ids[row.id]=true
		if not _vector(row.get("position"),true) or not _vector(row.get("rotation")) or not _vector(row.get("velocity")):return false
		for angle: Variant in row.rotation:
			if absf(float(angle))>PI:return false
		if row.get("motion") not in ["ai","parked","idle","walk","run","react","driven","driving","stop"]:return false
		if not row.get("driverId","") is String or (not row.get("driverId","").is_empty() and not _uuid(row.driverId)):return false
		if not _number(row.get("leaseEpoch",0)) or int(row.get("leaseEpoch",0))<0:return false
		if row.get("mode","ai") not in ["ai","parked","driven"]:return false
		if row.get("reactionKind","") not in ["","greet","pet","shove","hit"]:return false
		if not _number(row.get("reactionUntilMs",0)) or not row.get("reactorId","") is String:return false
	if not value.get("actionResults",[]) is Array or value.get("actionResults",[]).size()>32:return false
	for result: Variant in value.get("actionResults",[]):
		if not result is Dictionary or not _uuid(result.get("playerId")) or not _uuid(result.get("requestId")) or not result.get("ok") is bool:return false
		if not _entity_id(result.get("entityId")) or not result.get("error","") is String or result.get("error","").length()>80:return false
		if result.get("type") not in ["vehicle_enter","vehicle_exit","npc_greet","npc_pet","npc_shove","npc_hit"]:return false
	return true

func _number(value: Variant) -> bool:return (value is float or value is int) and is_finite(float(value))

func _uuid(value: Variant) -> bool:
	if not value is String:return false
	var pattern:=RegEx.new();pattern.compile("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
	return pattern.search(value)!=null

func _hex(value: Variant,length: int) -> bool:
	if not value is String:return false
	var pattern:=RegEx.new();pattern.compile("^[0-9a-f]{%d}$"%length)
	return pattern.search(value)!=null

func _request_failure(operation: String,code: int,value: Dictionary) -> void:
	var safe_reason:=String(value.get("error","connection_failed"))
	var safe_pattern:=RegEx.new();safe_pattern.compile("^[a-z0-9_]{1,80}$")
	last_failure_code=safe_reason if safe_pattern.search(safe_reason)!=null else "invalid_response"
	if operation=="leave":_clear_room();_set_state("ready",_leave_notice);return
	if operation in ["status","session"]:_unavailable();return
	var reason:=String(value.get("error","connection_failed"))
	if _mode=="sites" and code==401 and reason=="sign_in_required":
		_clear_room();sign_in_required=true;_set_state("ready","함께 걷기는 로그인 후 이용할 수 있습니다.");return
	if connected and code==429:
		var supplied: Variant=value.get("retryAfterMs",1000)
		var retry_ms:=1000
		if _number(supplied) and float(supplied)>=0.:retry_ms=ceili(minf(float(supplied),60_000.))
		_next_sync_ms=Time.get_ticks_msec()+maxi(550,retry_ms)
		_set_state("connected","연결을 유지하며 다음 응답을 기다리고 있어요.");return
	if connected and operation=="sync" and code==422 and reason in ["world_movement_out_of_range","world_speed_out_of_range","movement_out_of_range"]:
		# A rejected proposal never changes approved state. Allow a fresh sample
		# after a bounded delay, just as for transient transport failures. Keep
		# every server bound intact and leave safely after three rejections.
		_failures+=1;_next_sync_ms=Time.get_ticks_msec()+1000
		print("SHARED_CITY_SYNC_REJECT ",JSON.stringify({"status":code,"reason":last_failure_code,"attempt":_failures}))
		if _failures<3:_set_state("connected","도시 상태를 다시 확인하고 있어요.");return
	if connected and (code==0 or code>=500):
		_failures+=1;_next_sync_ms=Time.get_ticks_msec()+1000
		if _failures<3:_set_state("connected","응답이 늦어 다시 연결하고 있어요.");return
	if connected:
		leave_room("함께 걷기 연결이 끊겼습니다. 초대 코드로 다시 참가할 수 있습니다.");return
	_clear_room()
	var message:="방에 들어가지 못했습니다. 초대 코드와 연결을 확인해 주세요."
	if reason in ["room_unavailable","room_full_or_expired"]:message="방이 만료됐거나 가득 찼습니다. 새 방을 만들어 주세요."
	elif reason=="build_mismatch":message="게임 버전이 다릅니다. 두 게임을 같은 버전으로 열어 주세요."
	elif code==429:message="잠시 기다린 뒤 다시 시도해 주세요."
	_set_state("ready",message)

func _unavailable() -> void:
	available=false;sign_in_required=false;_cookie="";_clear_room()
	_set_state("unavailable","이 실행 주소에는 함께 걷기 서버가 아직 연결되지 않았습니다. 혼자 탐험은 계속할 수 있습니다.")

func _clear_room() -> void:
	connected=false;room_id="";self_id="";invite="";_token="";participant_count=0
	world={};_actions.clear();_delivered_actions.clear();_world_sequence=0
	changed.emit()

func _set_state(value: String,message: String) -> void:
	state=value;notice=message;changed.emit()

func _process(_delta: float) -> void:
	if not connected or busy() or Time.get_ticks_msec()<_next_sync_ms:return
	var sample: Dictionary=_sample.call()
	if sample.is_empty():leave_room("실내나 탈것으로 이동해 함께 걷기를 마쳤습니다. 야외에서 다시 참가할 수 있습니다.");return
	_sequence+=1
	var data:={"sequence":_sequence,"position":sample.position,"yaw":sample.yaw,"motion":sample.motion,"avatar":sample.avatar}
	if not world.is_empty():
		if world.get("hostId")==self_id and _authority_provider.is_valid():
			var entities: Array=_authority_provider.call()
			if not entities.is_empty():
				_world_sequence+=1;data["world"]={"sequence":_world_sequence,"entities":entities}
		if _drive_provider.is_valid():
			var drive: Dictionary=_drive_provider.call()
			if not drive.is_empty():data["drive"]=drive
		if not _actions.is_empty():data["actions"]=_actions.slice(0,4)
	_request("sync",_player_path("sync"),HTTPClient.METHOD_POST,data)

func diagnostic() -> Dictionary:
	# Deliberately excludes room bearer token, development cookie and invite.
	return {"state":state,"available":available,"connected":connected,"sign_in_required":sign_in_required,"participants":participant_count,"received_snapshots":received_snapshots,"round_trip_ms":last_round_trip_ms,"last_http_result":last_http_result,"last_http_code":last_http_code,"last_response_bytes":last_response_bytes,"last_request_error":last_request_error,"last_failure_code":last_failure_code,"sequence":_sequence,"transport":"http-presence"}
