extends SceneTree
func _initialize():
    run.call_deferred()
func run():
    var scene=load("res://scenes/world/palace_landmarks.tscn").instantiate()
    root.add_child(scene)
    scene.rig.set_capture(false)
    var camera=Camera3D.new()
    scene.add_child(camera)
    camera.position=Vector3(-174.4,5,-113)
    camera.look_at(Vector3(-174.4,1.5,-124))
    camera.make_current()
    await process_frame
    await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("/tmp/sim2seoul_stone_close.png")
    scene.queue_free()
    quit()
