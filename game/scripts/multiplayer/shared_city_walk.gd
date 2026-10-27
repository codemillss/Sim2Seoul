extends Node
## Opt-in outdoor presence. Existing local gameplay remains the movement owner.
const CLIENT := preload("res://scripts/multiplayer/room_presence_client.gd")
const REMOTE := preload("res://scripts/multiplayer/remote_resident.gd")
var host: Node3D
var client: Node
var ui_open := false
var remotes: Dictionary={}
var menu_button: Button
var _layer: CanvasLayer
var _overlay: ColorRect
var _status: Label
var _participants: Label
var _badge: Label
var _invite_input: LineEdit
var _invite_output: LineEdit
var _create: Button
var _join: Button
var _copy: Button
var _leave: Button
var _check: Button
var _sign_in: Button
var _box: PanelContainer
var _scroll: ScrollContainer

func setup(scene: Node3D) -> bool:
	if is_instance_valid(client) or not is_instance_valid(scene):return false
	host=scene;process_mode=Node.PROCESS_MODE_ALWAYS
	client=CLIENT.new();client.name="RoomPresenceClient";add_child(client)
	var endpoint:="http://127.0.0.1:8766"
	if OS.has_feature("web"):endpoint=String(JavaScriptBridge.eval("window.location.origin",true))
	else:
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--room-server="):endpoint=argument.trim_prefix("--room-server=").trim_suffix("/")
	if not client.configure(endpoint,_local_sample):return false
	client.changed.connect(_refresh)
	client.joined.connect(_joined)
	client.snapshot_received.connect(_snapshot_received)
	_build_ui();_refresh()
	return true

func _text(value: String,size: int=18) -> Label:
	var label:=Label.new();label.text=value;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",size)
	return label

func _button(value: String,action: Callable) -> Button:
	var button:=Button.new();button.text=value;button.custom_minimum_size.y=42
	button.pressed.connect(action);return button

func _build_ui() -> void:
	var options:=host.exploration_menu_content as VBoxContainer
	menu_button=_button("함께 걷기 · 친구 초대",open_panel);options.add_child(menu_button)
	options.move_child(menu_button,mini(2,options.get_child_count()-1))
	for child: Node in options.get_children():
		if child is Button and child.text=="종료":options.move_child(child,options.get_child_count()-1);break
	if host.has_method("_queue_menu_layout"):host._queue_menu_layout()
	_layer=CanvasLayer.new();_layer.name="SharedCityWalkUI";_layer.layer=70;add_child(_layer)
	_overlay=ColorRect.new();_overlay.name="RoomPanel";_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color=Color(.025,.04,.055,.90);_overlay.visible=false;_layer.add_child(_overlay)
	var centre:=CenterContainer.new();centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_overlay.add_child(centre)
	_box=PanelContainer.new();centre.add_child(_box)
	_scroll=ScrollContainer.new();_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;_scroll.follow_focus=true;_box.add_child(_scroll)
	var margin:=MarginContainer.new()
	margin.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for side: String in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,22)
	_scroll.add_child(margin)
	var content:=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;content.add_theme_constant_override("separation",12);margin.add_child(content)
	content.add_child(_text("함께 걷기",28))
	content.add_child(_text("같은 방에 들어온 친구와 야외에서 만나요.",17))
	_status=_text("연결을 확인하고 있어요.",17);_status.custom_minimum_size.y=66;content.add_child(_status)
	_participants=_text("",17);content.add_child(_participants)
	_sign_in=_button("ChatGPT로 로그인하고 함께 걷기",_open_sign_in);content.add_child(_sign_in)
	_create=_button("새 방 만들기",_create_room);content.add_child(_create)
	content.add_child(_text("초대받았다면",16))
	_invite_input=LineEdit.new();_invite_input.name="InviteInput";_invite_input.placeholder_text="받은 초대 코드를 붙여넣으세요"
	_invite_input.custom_minimum_size.y=42;_invite_input.max_length=100
	_invite_input.text_submitted.connect(func(_value: String):_join_room());content.add_child(_invite_input)
	_join=_button("초대 코드로 참가",_join_room);content.add_child(_join)
	_invite_output=LineEdit.new();_invite_output.name="InviteOutput";_invite_output.editable=false
	_invite_output.placeholder_text="내 방을 만들면 초대 코드가 표시됩니다";_invite_output.custom_minimum_size.y=40;content.add_child(_invite_output)
	var row:=HBoxContainer.new();content.add_child(row)
	_copy=_button("초대 코드 복사",_copy_invite);_copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(_copy)
	_leave=_button("방 나가기",func():client.leave_room());_leave.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(_leave)
	_check=_button("연결 다시 확인",func():client.check_service());content.add_child(_check)
	content.add_child(_text("지금은 야외 보행·외형을 공유합니다. 실내나 탈것으로 이동하면 함께 걷기를 마칩니다. NPC·차량·사건은 아직 각 게임에서 따로 움직입니다.",14))
	content.add_child(_button("게임 메뉴로 돌아가기 · Esc",close_panel))
	_badge=_text("",18);_badge.name="SharedCityBadge";_badge.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	_badge.add_theme_color_override("font_color",Color(.3,.95,.95));_badge.add_theme_color_override("font_shadow_color",Color.BLACK)
	_badge.add_theme_constant_override("shadow_offset_x",2);_badge.add_theme_constant_override("shadow_offset_y",2)
	_badge.mouse_filter=Control.MOUSE_FILTER_IGNORE;_layer.add_child(_badge)
	_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_badge.offset_left=-360;_badge.offset_right=-20;_badge.offset_top=145;_badge.offset_bottom=200
	get_viewport().size_changed.connect(_fit_panel);_fit_panel()

func _fit_panel() -> void:
	if not is_instance_valid(_box):return
	var viewport_size:=get_viewport().get_visible_rect().size
	var width:=minf(590.,maxf(300.,viewport_size.x-36.))
	_box.custom_minimum_size.x=width
	_scroll.custom_minimum_size=Vector2(width,minf(680.,maxf(300.,viewport_size.y-36.)))

func open_panel() -> void:
	if not is_instance_valid(host) or ui_open:return
	if not host.menu.visible:host.toggle_menu()
	if not host.menu.visible:return
	ui_open=true;host.menu.visible=false;_overlay.visible=true
	if not client.connected:client.check_service()
	_refresh();_invite_input.grab_focus()

func close_panel() -> void:
	if not ui_open:return
	ui_open=false;_overlay.visible=false;host.menu.visible=true;menu_button.grab_focus()

func _input(event: InputEvent) -> void:
	if ui_open and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		close_panel();get_viewport().set_input_as_handled()

func _create_room() -> void:client.create_room()
func _join_room() -> void:client.join_room(_invite_input.text)

func _copy_invite() -> void:
	var value: String=client.invite_code()
	if value.is_empty():return
	DisplayServer.clipboard_set(value)
	_status.text="초대 코드를 복사했습니다. 친구에게 전달해 주세요."

func _open_sign_in() -> void:
	var url: String=client.sign_in_url()
	if url.is_empty():return
	if OS.has_feature("web"):JavaScriptBridge.eval("window.top.location.assign("+JSON.stringify(url)+")",true)
	else:OS.shell_open(url)

func _refresh() -> void:
	if not is_instance_valid(_status):return
	_status.text=client.notice
	_participants.text="같은 방 · %d명 참여"%client.participant_count if client.connected else ""
	_create.disabled=not client.available or client.connected or client.busy() or client.sign_in_required
	_join.disabled=_create.disabled
	_sign_in.visible=client.sign_in_required;_sign_in.disabled=client.busy()
	_copy.disabled=client.invite_code().is_empty();_leave.disabled=not client.connected
	_check.disabled=client.connected or client.busy()
	_invite_output.text=client.invite_code()
	_badge.text="함께 걷기 · %d명 · Esc에서 방 보기"%client.participant_count if client.connected else ""
	if not client.connected:_clear_remotes()

func _local_sample() -> Dictionary:
	if not is_instance_valid(host) or not is_instance_valid(host.player):return {}
	var player: CharacterBody3D=host.player
	if player.facility_control or player.interior_active:return {}
	for method: String in ["_street_transport_riding","_shop_active","_subway_active","_police_facility_active","_sandbox_detained"]:
		if host.has_method(method) and bool(host.call(method)):return {}
	var position:=player.global_position
	if not position.is_finite() or absf(position.x)>1000 or absf(position.z)>1000 or position.y< -100 or position.y>500:return {}
	var visual:=player.get_node_or_null("Visual") as Node3D
	if visual==null:return {}
	var avatar: Node=host.exploration_avatar
	var model:=String(player.get_meta("human_model_id","SeoulResident_M01"))
	var profile:=String(player.get_meta("human_body_profile","standard"))
	var surface: Node=avatar.get("_textured_surface") if is_instance_valid(avatar) else null
	var swimwear: bool=is_instance_valid(surface) and bool(surface.get("_swimwear_active"))
	var motion:=String(avatar.get("state")) if is_instance_valid(avatar) else "idle"
	if motion=="air":motion="jump"
	if motion not in ["idle","walk","run","jump"]:motion="idle"
	return {"position":[position.x,position.y,position.z],"yaw":wrapf(visual.global_rotation.y,-PI,PI),"motion":motion,"avatar":{"modelId":model,"bodyProfile":profile,"swimwear":swimwear}}

func _joined(owner: bool,value: Dictionary) -> void:
	# A delayed join must not take ownership back from a room/vehicle entered
	# after the request was sent.
	if _local_sample().is_empty():client.leave_room("활동 상태가 바뀌어 참가를 취소했습니다. 야외에서 다시 참가해 주세요.");return
	if owner:
		_invite_input.text=client.invite_code()
		return
	var own: Dictionary={}
	for row: Dictionary in value.players:
		if row.id==client.self_id:own=row;break
	if own.is_empty():client.leave_room("참가 위치를 확인하지 못했습니다.");return
	var raw: Array=own.position
	var desired:=Vector3(float(raw[0]),float(raw[1]),float(raw[2]))
	var accepted:=false
	for offset: Vector3 in [Vector3(1.4,0,0),Vector3(-1.4,0,0),Vector3(0,0,1.4),Vector3(0,0,-1.4),Vector3.ZERO]:
		var safe: Dictionary=host._exploration_destination(desired+offset)
		if safe.is_empty():continue
		if safe.point.distance_to(desired)>4.:continue
		accepted=host._commit_exploration_teleport(safe.point)
		if accepted:break
	if not accepted:client.leave_room("함께 걸을 시작 위치가 막혀 있습니다. 다른 야외 위치에서 방을 만들어 주세요.");return
	host.player.velocity=Vector3.ZERO;host.player.require_neutral_input();host.player.reset_physics_interpolation()
	host.rig.snap_to_target_pose()

func _snapshot_received(value: Dictionary) -> void:
	var seen: Dictionary={}
	var server_ms:=int(value.serverNowMs);var now_ms:=Time.get_ticks_msec()
	for row: Dictionary in value.players:
		var id:=String(row.id)
		if id==client.self_id:continue
		seen[id]=true
		if not remotes.has(id):
			var resident: Node3D=REMOTE.new();resident.name="SharedResident_"+id.left(8);host.add_child(resident)
			if not resident.setup(row,server_ms,now_ms):resident.queue_free();continue
			remotes[id]=resident
		else:remotes[id].ingest(row,server_ms,now_ms)
	for id: String in remotes.keys():
		if not seen.has(id):remotes[id].queue_free();remotes.erase(id)

func _clear_remotes() -> void:
	for resident: Node in remotes.values():
		if is_instance_valid(resident):resident.queue_free()
	remotes.clear()

func diagnostic() -> Dictionary:
	var result: Dictionary=client.diagnostic() if is_instance_valid(client) else {}
	result["remote_count"]=remotes.size();result["ui_open"]=ui_open
	return result

func _exit_tree() -> void:
	_clear_remotes()
