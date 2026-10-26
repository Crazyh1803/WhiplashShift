## Writes pickup, rail and car-impact WAV previews for listening. Usage:
##   godot --headless --path godot res://tests/vehicle_audio_export.tscn -- --export-audio [out_dir]
## Default out_dir is <repo>/.ai/captures/vehicle-feedback-audio.
extends Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--export-audio")
	if at < 0:
		print("vehicle_audio_export: pass -- --export-audio [out_dir] to write WAVs")
		get_tree().quit(0)
		return
	var dir := ProjectSettings.globalize_path("res://").path_join("../.ai/captures/vehicle-feedback-audio").simplify_path()
	if at + 1 < args.size():
		dir = args[at + 1]
	DirAccess.make_dir_recursive_absolute(dir)
	var failed := false
	var sounds := {"pickup": ItemAudio.make_sound("pickup"),
		"rail_impact": VehicleAudio.make_rail_sound(),
		"car_impact": VehicleAudio.make_car_sound()}
	for name: String in sounds:
		var path := dir.path_join(name + ".wav")
		var err := (sounds[name] as AudioStreamWAV).save_to_wav(path)
		print("AUDIO %s %s" % [path, "ok" if err == OK else "error %d" % err])
		failed = failed or err != OK
	get_tree().quit(1 if failed else 0)
