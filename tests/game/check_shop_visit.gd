extends SceneTree
## Actual production physics/UI/E routing. Named observer placements and blockers
## are test fixtures; none are a claim of ordinary OS input or visual acceptance.
var scene: Node3D
var service: Node3D
var checks: Array[Dictionary]=[]
var report_path:="/tmp/sim2seoul-shop-visit.json"
var started:=0
var finished:=false
var _fixtures: Array[Node3D]=[]
var _sources: Dictionary={}
var _source_node_ids: Dictionary={}
var captures: Array[Dictionary]=[]

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	started=Time.get_ticks_msec();Engine.max_fps=0
	create_timer(300.,true,false,true).timeout.connect(func()->void:
		if not finished:_check("bounded_test_timeout",false);_finish()
	)
	_run.call_deferred()

func _json(value: Variant) -> Variant:
	if value is Color:return [value.r,value.g,value.b,value.a]
	if value is Vector2:return [value.x,value.y]
	if value is Vector3:return [value.x,value.y,value.z]
	if value is AABB:return {"position":_json(value.position),"size":_json(value.size)}
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value:result[str(key)]=_json(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item: Variant in value:result.append(_json(item))
		return result
	if value is float:return value if is_finite(value) else null
	return value

func _check(title: String,passed: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":_json(evidence)});print("SHOP_CHECK ",title," ",passed)
	if not passed:push_warning("SHOP_CHECK_FAIL "+title)

func _ticks(count: int) -> void:
	for index: int in range(count):await physics_frame

func _tap_e(device:=0) -> void:
	var press:=InputEventKey.new();press.keycode=KEY_E;press.physical_keycode=KEY_E;press.device=device;press.pressed=true;Input.parse_input_event(press)
	await _ticks(3)
	var release:=InputEventKey.new();release.keycode=KEY_E;release.physical_keycode=KEY_E;release.device=device;release.pressed=false;Input.parse_input_event(release);await _ticks(5)

func _tap_i() -> void:
	var press:=InputEventKey.new();press.keycode=KEY_I;press.physical_keycode=KEY_I;press.pressed=true;Input.parse_input_event(press);await _ticks(2)
	var release:=InputEventKey.new();release.keycode=KEY_I;release.physical_keycode=KEY_I;release.pressed=false;Input.parse_input_event(release);await _ticks(3)

func _place(point: Vector3) -> void:
	scene.player.global_position=point;scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation();await _ticks(7)

func _fixture(point: Vector3,size: Vector3,basis:=Basis.IDENTITY) -> StaticBody3D:
	var body:=StaticBody3D.new();body.name="ShopTestOnlyBlocker";body.collision_layer=1;body.collision_mask=0
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box;body.add_child(shape);scene.add_child(body);body.global_transform=Transform3D(basis,point);_fixtures.append(body);return body

func _clear() -> void:
	for body: Node3D in _fixtures:body.queue_free()
	_fixtures.clear();await _ticks(4)

func _hashes() -> Dictionary:
	var result: Dictionary={}
	for path: String in ["res://scripts/shop_visit_service.gd","res://assets/authored/shop_service.json","res://../tests/game/check_shop_visit.gd","res://assets/authored/street_businesses.json","res://resources/world_geometry/world.json","res://scripts/building_visit_catalog.gd","res://scripts/player/exploration_avatar.gd"]:result[path]=FileAccess.get_sha256(path)
	return result

func _capture(title: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await _ticks(3);await process_frame;RenderingServer.force_draw()
	var image:=root.get_texture().get_image();var path: String=report_path.get_basename()+"_"+title+".png";var error: Error=image.save_png(path)
	_check("native_capture_"+title,error==OK,{"file":path,"image_size":image.get_size()})
	if error==OK:captures.append({"file":path,"sha256":FileAccess.get_sha256(path),"observer_position":scene.player.global_position,"camera_yaw":scene.rig.yaw,"camera_pitch":scene.rig.pitch,"scope":"Production camera rig with explicitly placed test observer and test camera orbit. Clothing/swimwear views use the empty room arrival aisle, away from display mannequins; earlier final01 mannequin occlusion was an observer-position defect. Saved images require separate visual review; this is not ordinary OS gameplay proof."})

func _outfit_capture(title: String) -> void:
	# The first native run orbited in front of a display point, putting the
	# camera behind its mannequin. Move the observer to the ordinary empty
	# arrival aisle instead; source/player/camera geometry is not altered.
	if not service.active or String(service._current.kind)!="clothing":
		_check("outfit_observer_"+title+"_valid_clothing_room",false);return
	await _place(service._current.spawn);service._orient(PI,deg_to_rad(-10.),3.4);await _ticks(4)
	var camera: Camera3D=scene.rig.camera;var clear:=true;var samples: Array=[]
	for mesh: MeshInstance3D in scene.exploration_avatar._meshes:
		var part: String=String(mesh.get_meta("avatar_part",""))
		if part not in ["Head","Torso","LeftShoe","RightShoe"]:continue
		var center: Vector3=mesh.global_transform*mesh.get_aabb().get_center();var blockers: Array=[]
		for display: Node in service._current.room.get_children():
			if not display is MeshInstance3D or not (String(display.name).begins_with("DisplayTorso") or String(display.name).begins_with("DisplaySleeve") or String(display.name).begins_with("MannequinHead")):continue
			var bounds: AABB=display.global_transform*display.get_aabb()
			if bounds.intersects_segment(camera.global_position,center):blockers.append(String(display.name))
		var projection: Vector2=camera.unproject_position(center);var inside: bool=not camera.is_position_behind(center) and scene.get_viewport().get_visible_rect().grow(-12.).has_point(projection)
		clear=clear and blockers.is_empty() and inside;samples.append({"part":part,"projection":projection,"inside_view":inside,"mannequin_occluders":blockers})
	_check("outfit_observer_"+title+"_head_body_feet_clear_of_mannequins",clear and samples.size()==4,{"observer_position":scene.player.global_position,"samples":samples,"scope":"Explicit test observer relocation to the real empty arrival aisle plus front camera orbit. AABB ray checks for retained mannequin display meshes and viewport center projection; native image review remains separate."})
	await _capture(title)

func _small_ui_capture(title: String,panel: Control) -> void:
	if DisplayServer.get_name()=="headless":return
	var previous_size: Vector2i=root.size;var previous_mode: int=root.content_scale_mode;var previous_scale: Vector2i=root.content_scale_size
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.size=Vector2i(640,480);await _ticks(5);await process_frame;RenderingServer.force_draw()
	var view: Rect2=scene.get_viewport().get_visible_rect();var bounds: Rect2=panel.get_global_rect()
	_check("native_640x480_"+title+"_panel_within_view",view.size.is_equal_approx(Vector2(640.,480.)) and view.grow(-8.).encloses(bounds),{"viewport":view.size,"panel_position":bounds.position,"panel_size":bounds.size,"scope":"Panel geometry and actual capture; scroll content/legibility still require native image review."})
	await _capture("small640_"+title)
	root.content_scale_mode=previous_mode;root.content_scale_size=previous_scale;root.size=previous_size;await _ticks(5)

func _finish() -> void:
	if finished:return
	finished=true
	if is_instance_valid(service) and not _source_node_ids.is_empty():
		_check("module_and_original_inputs_stable_during_run",not _sources.values().has("") and _hashes()==_sources,{"loaded":_sources,"finished":_hashes()})
		var current: Dictionary={}
		for key: Variant in scene.city.source_nodes:current[str(key)]=scene.city.source_nodes[key].get_instance_id()
		_check("same_original_source_nodes_and_player_capsule",current==_source_node_ids and scene.player.get_node("CollisionShape").shape.get_instance_id()==int(scene.get_meta("shop_test_capsule_id")))
	var passed: int=checks.filter(func(row: Dictionary)->bool:return bool(row.passed)).size()
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Cannot save shop report: "+report_path);quit(2);return
	file.store_string(JSON.stringify(_json({"task":"shop_visit_service","result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"captures":captures,"snapshot":service.snapshot() if is_instance_valid(service) else {},"engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"physics_hz":Engine.physics_ticks_per_second,"recorded_at":Time.get_datetime_string_from_system(),"elapsed_ms":Time.get_ticks_msec()-started,"source_sha256":_sources,"scope":"Actual production scene/terrain/capsules. Physical KEY_E and UI signals; test-only observer placements, blockers and insufficient-balance fixture are explicit. Session game credits, no real payment. Headless does not prove visible layout or actual OS keyboard control."}),"  "));file.close();print("SHOP_RESULT ",passed,"/",checks.size());quit(0 if passed==checks.size() else 1)

func _run() -> void:
	_sources=_hashes()
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/shop-test-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(10)
	service=scene.get("shop_visit_service")
	if not is_instance_valid(service):
		service=load("res://scripts/shop_visit_service.gd").new();scene.add_child(service);scene.set("shop_visit_service",service);service.setup(scene)
	_check("production_setup_three_source_bound_distinct_shops",scene.runtime_ok and service.loaded and service.shops.size()==3,{"runtime_error":scene.exploration_error,"shop_error":service.load_error})
	if not scene.runtime_ok or not service.loaded:_finish();return
	for key: Variant in scene.city.source_nodes:_source_node_ids[str(key)]=scene.city.source_nodes[key].get_instance_id()
	scene.set_meta("shop_test_capsule_id",scene.player.get_node("CollisionShape").shape.get_instance_id())
	if scene.menu.visible:scene.toggle_menu()
	await _ticks(6)
	var destination: Dictionary=service.destination("shop")
	_check("convenience_real_displayed_left_door_supported_destination",not destination.is_empty(),destination)
	if destination.is_empty():_finish();return
	var row: Dictionary=service.shops[0];var out: Vector3=service._outward(row);var door: Vector3=service._door(row)
	var expected: Vector3=row.facade.to_global(Vector3(float(row.source.facade_width_m)*-.31,0.,.045))
	_check("entry_anchor_matches_existing_visible_door_not_facade_center",door.distance_to(expected)<.00001 and door.distance_to(row.facade.global_position)>1.9,{"door":door,"facade_center":row.facade.global_position})
	await _place(destination.point)
	scene.rig.yaw=atan2(out.x,out.z);scene.rig.pitch=deg_to_rad(-13.);scene.rig.requested_distance=3.8;scene.rig.snap_to_target_pose();await _ticks(3)
	await _capture("convenience_source_door")
	_check("supported_foot_approach_is_actionable",service.can_interact(),{"hint":service.prompt_text(),"position":scene.player.global_position})
	_fixture(door+out*.7+Vector3.UP*1.1,Vector3(2.8,2.2,.15),Basis(Vector3(out.z,0.,-out.x),Vector3.UP,out));await _ticks(4)
	await _tap_e();_check("retained_wall_blocks_through_wall_shop_entry",not service.active and not service.can_interact())
	await _clear();await _place(destination.point+Vector3.UP*1.8);scene.player.velocity=Vector3.UP*3.
	_check("airborne_shop_entry_rejected",not service.can_interact())
	await _place(destination.point);await _tap_e()
	_check("physical_E_enters_convenience_without_replacing_building_visit",service.active and scene.player.interior_active and not scene.interior_visit.active and service.current_shop_id=="gs25_game_shop",service.snapshot())
	if not service.active:_finish();return
	_check("room_has_unique_shelves_products_floor_and_normal_capsule",service._current.interactions.size()==6 and service._current.room.has_node("Checkout") and service._current.room.has_node("ShelfBack") and service._current.bounds.has_point(scene.player.global_position))
	_check("shop_region_blocks_original_transport_and_building_ownership",not scene.city_bike_service.can_interact() and not scene.city_scooter_service.can_interact() and not scene.city_bus_service.can_interact() and not scene.interior_visit.active)
	await _capture("convenience_interior")
	var walk_from: Vector3=scene.player.global_position;var recoveries_before: int=scene.player.recoveries
	for index: int in range(12):Input.action_press("move_forward");await _ticks(1)
	Input.action_release("move_forward");await _ticks(3)
	_check("actual_controller_walks_inside_shop_on_native_floor",scene.player.global_position.distance_to(walk_from)>.5 and service._current.bounds.has_point(scene.player.global_position) and scene.player.is_on_floor() and scene.player.recoveries==recoveries_before,{"from":walk_from,"to":scene.player.global_position,"recovery_delta":scene.player.recoveries-recoveries_before,"last_recovery_reason":scene.player.last_recovery_reason,"input_latched":scene.player.input_latched,"gameplay_enabled":scene.input_router.gameplay_enabled,"scope":"Synthetic held action, actual production movement; observer start was the real portal spawn."})
	var target: Dictionary=service._current.interactions[0];await _place(target.point)
	await _tap_e(42)
	_check("physical_E_at_product_opens_selector_and_wallet_inventory",service.ui_open and service._picker.visible and not scene.input_router.gameplay_enabled and scene.player.facility_control,{"picker_title":service._picker_title.text,"wallet":service._wallet_text.text,"inventory":service._inventory_text.text})
	if not service.ui_open:_finish();return
	var before: int=service.balance;var item: Dictionary=service._product("rice_triangle");service._buy_button.pressed.emit();await _ticks(2)
	_check("real_purchase_button_debits_credits_adds_inventory_receipt",service.balance==before-int(item.price) and int(service.inventory.get("rice_triangle",0))==1 and service.transactions.size()==1,{"receipt":service.transactions,"text":service._receipt_text.text})
	await _capture("convenience_purchase_receipt")
	await _small_ui_capture("purchase",service._picker)
	service._buy_button.pressed.emit();service.purchase_selected();await _ticks(2)
	_check("same_selection_token_cannot_purchase_twice",service.balance==before-int(item.price) and service.transactions.size()==1 and int(service.inventory.rice_triangle)==1)
	service.select_item("water");var credit_fixture: int=service.balance;service.balance=0
	var denied: bool=service.purchase_selected();_check("insufficient_credit_fixture_does_not_mutate_inventory",not denied and service.balance==0 and not service.inventory.has("water") and service.transactions.size()==1,{"notice":service._receipt_text.text,"fixture":"Balance temporarily set to zero; restored after this assertion."});service.balance=credit_fixture
	service.select_item("water");scene.toggle_menu();await _ticks(3);await process_frame;var paused_buy: bool=service.purchase_selected()
	_check("menu_pauses_purchase_and_hides_picker",not paused_buy and not service._picker.visible and service.transactions.size()==1,{"menu_visible":scene.menu.visible,"picker_visible":service._picker.visible,"purchase_allowed":paused_buy,"transactions":service.transactions.size(),"process_frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames(),"scope":"Observe the real UI process boundary after menu opens; keep purchase rejection, picker hidden and transaction denominator unchanged."})
	scene.toggle_menu();await _ticks(4)
	_check("menu_return_restores_visible_cursor_purchase_focus_and_modal_input",Input.mouse_mode==Input.MOUSE_MODE_VISIBLE and not scene.input_router.gameplay_enabled and service._buy_button.has_focus())
	await _tap_e()
	_check("E_closes_picker_and_restores_walking_without_extra_purchase",not service.ui_open and not scene.player.facility_control and scene.input_router.gameplay_enabled and service.transactions.size()==1)
	await _place(target.point);await _tap_e();service.select_item("water")
	var press:=InputEventKey.new();press.physical_keycode=KEY_ENTER;press.keycode=KEY_ENTER;press.pressed=true;Input.parse_input_event(press)
	var repeated:=InputEventKey.new();repeated.physical_keycode=KEY_ENTER;repeated.keycode=KEY_ENTER;repeated.pressed=true;Input.parse_input_event(repeated);await _ticks(3)
	var release:=InputEventKey.new();release.physical_keycode=KEY_ENTER;release.keycode=KEY_ENTER;release.pressed=false;Input.parse_input_event(release);await _ticks(2)
	_check("physical_Enter_confirm_is_one_transaction_per_press_and_selection",service.transactions.size()==2 and int(service.inventory.get("water",0))==1)
	service.close_picker();await _ticks(5)
	# A failed external destination must retain the current room/player/UI state.
	await _place(target.point);service.open_picker("rice_triangle");var inside: Vector3=scene.player.global_position
	var invalid_exit: bool=service.leave_for_teleport(Vector3(999999.,0.,999999.))
	_check("invalid_external_teleport_is_atomic_keeps_room_and_picker",not invalid_exit and service.active and service.ui_open and scene.player.interior_active and scene.player.global_position.distance_to(inside)<.001)
	var invalid_roof: bool=service.leave_for_rooftop({})
	_check("invalid_rooftop_keeps_owned_interior_and_picker",not invalid_roof and service.active and service.ui_open and scene.player.global_position.distance_to(inside)<.001)
	service.close_picker();await _ticks(4);await _place(service._current.exit)
	for distance: float in [.1,.8,1.4,1.8]:_fixture(door+out*distance+Vector3.UP*1.,Vector3(5.,2.,.55),Basis(Vector3(out.z,0.,-out.x),Vector3.UP,out))
	await _ticks(4);await _tap_e()
	_check("blocked_exit_preserves_current_safe_interior",service.active and scene.player.interior_active and service.rejected_exits>0,{"notice":service._notice})
	await _clear();await _tap_e();await _ticks(5)
	_check("physical_E_exit_restores_supported_original_outdoor_capsule",not service.active and not scene.player.interior_active and not scene.player.facility_control and scene.input_router.gameplay_enabled and not scene.interior_visit.active,{"position":scene.player.global_position})
	var restaurant: Dictionary=service.destination("restaurant");_check("second_source_restaurant_has_clear_native_entrance",not restaurant.is_empty(),restaurant)
	if restaurant.is_empty():_finish();return
	await _place(restaurant.point);await _tap_e()
	_check("physical_E_enters_distinct_Korean_restaurant_menu",service.active and service.current_shop_id=="jinju_game_restaurant" and service._current.interactions.size()==3 and service._current.room.has_node("DiningTable") and not service._current.room.has_node("Checkout"))
	if not service.active:_finish();return
	await _capture("restaurant_interior")
	await _place(service._current.interactions[0].point);await _tap_e();service._buy_button.pressed.emit();await _ticks(2)
	_check("restaurant_purchase_keeps_shared_wallet_and_game_inventory",service.transactions.size()==3 and int(service.inventory.get("soybean_noodles",0))==1 and int(service.inventory.get("rice_triangle",0))==1,{"balance":service.balance,"inventory":service.inventory})
	await _capture("restaurant_purchase_receipt")
	var exit_target: Dictionary=service.destination("shop");var left: bool=service.leave_for_teleport(exit_target.point) if not exit_target.is_empty() else false;await _ticks(6)
	_check("validated_external_teleport_restores_UI_camera_input_and_outdoor_recovery",left and not service.active and not service.ui_open and not scene.player.interior_active and not scene.player.facility_control and scene.input_router.gameplay_enabled and scene.hud_panel.visible and scene.building_names.is_physics_processing())
	_check("outside_shop_does_not_steal_building_or_ride_ownership",not service._busy_elsewhere() and not scene.city_bike_service.riding and not scene.city_scooter_service.riding and not scene.city_bus_service.riding and not scene.interior_visit.active)
	var clothing: Dictionary=service.destination("clothing")
	_check("fictional_clothing_source_edge_has_supported_clear_own_door",not clothing.is_empty(),clothing)
	if clothing.is_empty():_finish();return
	await _place(clothing.point);await _tap_e()
	_check("physical_E_enters_clothing_mannequins_fitting_distinct_room",service.active and service.current_shop_id=="citywear_game_clothing" and service._current.room.has_node("MannequinPlinth") and service._current.room.has_node("FittingCurtain") and service._current.products.size()==3)
	if not service.active:_finish();return
	await _capture("clothing_interior")
	await _place(service._current.interactions[0].point);await _tap_e()
	var clothing_start_balance: int=service.balance;var clothing_start_transactions: int=service.transactions.size();var price_total:=0;var outfit_checks: Array=[]
	var original_jacket: StandardMaterial3D=scene.exploration_avatar._materials.jacket
	var original_jacket_color: Color=original_jacket.albedo_color
	var actual_surface: Node3D=scene.exploration_avatar._textured_surface
	var original_palette: int=hash(actual_surface.visible_meshes[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR])
	var actual_palettes: Array[int]=[]
	for product: Dictionary in service._current.products:
		service.select_item(String(product.id));service._buy_button.pressed.emit();await _ticks(2);price_total+=int(product.price)
		var parts: Array=service.outfit_snapshot().parts;var changed: int=parts.filter(func(part: Dictionary)->bool:return not part.original_material).size()
		var torso: Color=Color.TRANSPARENT
		for part: Dictionary in parts:
			if part.part=="Torso":torso=part.color
		var expected_color:=Color(float(product.outfit.body[0]),float(product.outfit.body[1]),float(product.outfit.body[2]))
		outfit_checks.append({"id":product.id,"equipped":service.equipped_item_id,"changed_parts":changed,"torso_color":torso,"expected_color":expected_color,"details":service.outfit_snapshot().cosmetic_detail_count})
		_check("purchase_equip_real_avatar_"+String(product.id),service.equipped_item_id==String(product.id) and int(service.inventory.get(String(product.id),0))==1 and changed>=9 and torso.is_equal_approx(expected_color) and service.outfit_snapshot().cosmetic_detail_count>0,outfit_checks.back())
		service.close_picker();await _ticks(3)
		var rendered_palette: int=hash(actual_surface.visible_meshes[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR])
		_check("purchase_updates_visible_weighted_clothing_"+String(product.id),actual_surface.visible_meshes[0].is_visible_in_tree() and rendered_palette!=original_palette and rendered_palette not in actual_palettes,{"original_palette":original_palette,"actual_rendered_palette":rendered_palette})
		actual_palettes.append(rendered_palette);await _outfit_capture("outfit_"+String(product.id))
		await _place(service._current.interactions[0].point);service.open_picker("ivory_cardigan");await _ticks(3)
	_check("three_outfits_share_wallet_without_modifying_original_materials",service.balance==clothing_start_balance-price_total and service.transactions.size()==clothing_start_transactions+3 and scene.exploration_avatar._materials.jacket==original_jacket and original_jacket.albedo_color.is_equal_approx(original_jacket_color),{"outfits":outfit_checks,"balance":service.balance,"original_jacket_before":original_jacket_color,"original_jacket_after":original_jacket.albedo_color})
	var clothing_paid: int=service.balance;var purchases: int=service.transactions.size();service.select_item("ivory_cardigan");service._buy_button.pressed.emit();service.purchase_selected();await _ticks(2)
	_check("owned_clothing_rebuy_equips_without_duplicate_charge_or_quantity",service.balance==clothing_paid and service.transactions.size()==purchases and int(service.inventory.ivory_cardigan)==1 and service.equipped_item_id=="ivory_cardigan")
	service.close_picker();await _ticks(3);var swim_in_shop: bool=service.begin_swimwear();service.open_picker("ivory_cardigan");var swimsuit_purchase: bool=service.purchase_selected()
	_check("swimwear_clothing_purchase_API_rejects_before_debit_or_inventory_change",swim_in_shop and not swimsuit_purchase and service.balance==clothing_paid and service.transactions.size()==purchases and int(service.inventory.ivory_cardigan)==1)
	service.close_picker();service.end_swimwear();await _ticks(3)
	service.close_picker();await _ticks(3);await _outfit_capture("purchased_cardigan_actual_avatar")
	var wardrobe_place: Dictionary=service.destination("shop")
	await _tap_i();_check("physical_I_opens_owned_clothing_inventory",service.inventory_open and service.ui_open and service._wardrobe.visible and service._wardrobe_buttons.get_child_count()==3 and not scene.input_router.gameplay_enabled)
	service.restore_default_outfit();await _ticks(2)
	_check("default_outfit_restores_original_material_references_and_details",service.equipped_item_id.is_empty() and service.outfit_snapshot().parts.all(func(part: Dictionary)->bool:return part.original_material) and service.outfit_snapshot().cosmetic_detail_count==0)
	for button: Button in service._wardrobe_buttons.get_children():
		if button.text.begins_with("코발트 컬러 상의"):button.pressed.emit();break
	await _ticks(2);_check("owned_inventory_button_reequips_real_avatar_without_payment",service.equipped_item_id=="cobalt_hoodie" and service.balance==clothing_paid and service.transactions.size()==purchases)
	await _capture("inventory_reequipped_hoodie")
	await _small_ui_capture("inventory",service._wardrobe)
	scene.toggle_menu();await _ticks(3);scene.toggle_menu();await _ticks(4)
	_check("inventory_menu_return_keeps_visible_cursor_and_owned_button_focus",service.inventory_open and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE and not scene.input_router.gameplay_enabled and (service._wardrobe_buttons.get_child(0) as Button).has_focus())
	var entries: int=service.entry_count;await _tap_e()
	_check("inventory_E_consumed_without_shop_or_ride_fallthrough",not service.inventory_open and not service.ui_open and service.entry_count==entries and not scene.player.facility_control and scene.input_router.gameplay_enabled)
	await _outfit_capture("inventory_hoodie_actual_avatar")
	var clothing_left: bool=service.leave_for_teleport(wardrobe_place.point) if not wardrobe_place.is_empty() else false;await _ticks(6)
	_check("outfit_persists_after_clothing_shop_exit",clothing_left and service.equipped_item_id=="cobalt_hoodie" and not service.active)
	await _tap_i();_check("owned_clothing_inventory_also_opens_outdoors",service.inventory_open and not service.active and scene.player.facility_control)
	await _tap_e()
	var bicycle_view: Dictionary=scene.city_bike_service.viewpoint()
	if not bicycle_view.is_empty():
		await _place(bicycle_view.point);await _tap_e();await _ticks(5)
		_check("actual_bicycle_mount_retains_purchased_outfit",scene.city_bike_service.riding and service.equipped_item_id=="cobalt_hoodie" and service.outfit_snapshot().parts.any(func(part: Dictionary)->bool:return not part.original_material))
		await _tap_i();_check("inventory_I_rejected_while_transport_owns_control",scene.city_bike_service.riding and not service.ui_open)
		await _tap_e();await _ticks(8)
		_check("actual_bicycle_dismount_retains_outfit_and_restores_controls",not scene.city_bike_service.riding and service.equipped_item_id=="cobalt_hoodie" and scene.player.is_physics_processing() and not scene.player.facility_control)
	else:_check("actual_bicycle_outfit_persistence_destination_available",false)
	# Return through the actual shop portal for an unoccluded indoor swimsuit
	# observer start. This is the clothing visual-hook fixture, not pool entry.
	var swim_observer_destination: Dictionary=service.destination("clothing")
	if not swim_observer_destination.is_empty():await _place(swim_observer_destination.point);await _tap_e()
	_check("swimwear_visual_observer_reenters_real_clothing_portal",service.active and service.current_shop_id=="citywear_game_clothing")
	if not service.active:_finish();return
	var before_swim: Array=[]
	for mesh: MeshInstance3D in scene.exploration_avatar._meshes:before_swim.append({"node":mesh,"material":mesh.material_override,"visible":mesh.visible})
	var previous_outfit: String=service.equipped_item_id;var details_id: int=service._outfit_details.get_instance_id() if is_instance_valid(service._outfit_details) else 0
	var previous_details_visible: bool=service._outfit_details.visible if is_instance_valid(service._outfit_details) else false
	var changed_to_swim: bool=service.begin_swimwear();var swim_torso: Color=Color.TRANSPARENT;var shorts_color: Color=Color.TRANSPARENT
	for mesh: MeshInstance3D in scene.exploration_avatar._meshes:
		if mesh.get_meta("avatar_part","")=="Torso":swim_torso=mesh.material_override.albedo_color
		if mesh.get_meta("avatar_part","")=="Pelvis":shorts_color=mesh.material_override.albedo_color
	var hidden_shoes:=true
	for mesh: MeshInstance3D in scene.exploration_avatar._meshes:
		if mesh.get_meta("avatar_part","") in ["LeftShoe","RightShoe","LeftShoeSole","RightShoeSole","LeftShoeLaces","RightShoeLaces"]:hidden_shoes=hidden_shoes and not mesh.visible
	_check("swimwear_changes_real_upper_body_skin_and_swim_shorts",changed_to_swim and service.swimwear_active and swim_torso.is_equal_approx(scene.exploration_avatar._materials.skin.albedo_color) and shorts_color.is_equal_approx(Color(.035,.35,.45)) and hidden_shoes and service._swim_feet.size()==2 and (not is_instance_valid(service._outfit_details) or not service._outfit_details.visible),{"torso":swim_torso,"shorts":shorts_color,"outfit_saved":previous_outfit,"original_shoes_hidden":hidden_shoes,"bare_feet":service._swim_feet.size()})
	await _outfit_capture("swimwear_actual_avatar")
	_check("swimwear_prevents_clothing_inventory_equip_or_default_override",not service.equip_owned("ivory_cardigan") and not service.restore_default_outfit() and not service.open_inventory() and service.equipped_item_id==previous_outfit and service.swimwear_active)
	_check("repeated_begin_swimwear_does_not_replace_saved_outfit",service.begin_swimwear() and service.equipped_item_id==previous_outfit)
	var ended: bool=service.end_swimwear();var references_restored:=true
	for saved: Dictionary in before_swim:references_restored=references_restored and saved.node.material_override==saved.material and saved.node.visible==saved.visible
	_check("end_swimwear_restores_exact_purchased_materials_visibility_and_details",ended and not service.swimwear_active and service._swim_feet.is_empty() and service.equipped_item_id==previous_outfit and references_restored and (details_id==0 or (service._outfit_details.get_instance_id()==details_id and service._outfit_details.visible==previous_details_visible)))
	service.leave_for_teleport(wardrobe_place.point);await _ticks(5)
	_finish()
