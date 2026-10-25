extends SceneTree
const PROFILE := preload("res://scripts/web_runtime_profile.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var host:=Node3D.new();root.add_child(host)
	var profile:=PROFILE.new();host.add_child(profile);profile.set_process(false)
	profile._host=host;profile._viewport=root
	var now:=Time.get_ticks_usec()
	profile._start_usec=now-400_000_000;profile._last_enforce_usec=now
	profile._last_sample_usec=now-5_100_000;profile._sample_count=60
	profile._process(0.)
	var past_sixty: bool=profile._sample_count==61
	profile._process(0.)
	var interval_kept: bool=profile._sample_count==61
	profile._last_sample_usec=now-5_100_000;profile._sample_count=1024
	profile._process(0.)
	var later: bool=profile._sample_count==1025
	var result:={"task":"WEB_PERF_CONTINUITY","result":"PASS" if past_sixty and interval_kept and later else "FAIL","checks":3,"publishes_sample_61":past_sixty,"keeps_five_second_interval":interval_kept,"publishes_sample_1025":later,"scope":"Synthetic past timestamps exercise the actual profile _process. Confirms no sixty-sample cutoff and no immediate duplicate log. Not a real five-minute browser/FPS run."}
	print("WEB_PERF_CONTINUITY_CHECK ",JSON.stringify(result))
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():
		var file:=FileAccess.open(args[0],FileAccess.WRITE)
		if file==null:push_error("Could not save performance continuity check");quit(1);return
		file.store_string(JSON.stringify(result,"  ")+"\n");file.close()
	host.free();quit(0 if result.result=="PASS" else 1)
