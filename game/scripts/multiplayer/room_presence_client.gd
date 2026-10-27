extends Node
## Small presence protocol client. Tokens/cookies remain in memory only.
## It does not drive local movement or own shared world/vehicle/combat results.
signal changed
signal snapshot_received(value: Dictionary)
signal joined(owner: bool,value: Dictionary)
const BUILD_ID := "sim2seoul-shared-walk-v1"
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
	return _request("create","/api/multiplayer/rooms",HTTPClient.METHOD_POST,{"buildId":BUILD_ID,"avatar":sample.avatar,"position":sample.position,"yaw":sample.yaw})

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
		if not row.get("avatar") is Dictionary:return false
		if row.avatar.get("modelId","") not in ["SeoulResident_M01","SeoulResident_F01"] or row.avatar.get("bodyProfile","") not in ["standard","soft","athletic"] or not row.avatar.get("swimwear") is bool:return false
	if connected and not ids.has(self_id):return false
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
	changed.emit()

func _set_state(value: String,message: String) -> void:
	state=value;notice=message;changed.emit()

func _process(_delta: float) -> void:
	if not connected or busy() or Time.get_ticks_msec()<_next_sync_ms:return
	var sample: Dictionary=_sample.call()
	if sample.is_empty():leave_room("실내나 탈것으로 이동해 함께 걷기를 마쳤습니다. 야외에서 다시 참가할 수 있습니다.");return
	_sequence+=1
	_request("sync",_player_path("sync"),HTTPClient.METHOD_POST,{"sequence":_sequence,"position":sample.position,"yaw":sample.yaw,"motion":sample.motion,"avatar":sample.avatar})

func diagnostic() -> Dictionary:
	# Deliberately excludes room bearer token, development cookie and invite.
	return {"state":state,"available":available,"connected":connected,"sign_in_required":sign_in_required,"participants":participant_count,"received_snapshots":received_snapshots,"round_trip_ms":last_round_trip_ms,"last_http_result":last_http_result,"last_http_code":last_http_code,"last_response_bytes":last_response_bytes,"last_request_error":last_request_error,"sequence":_sequence,"transport":"http-presence"}
