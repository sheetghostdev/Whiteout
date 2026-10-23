extends Node
## All audio is synthesised at startup into PCM buffers - no audio files.
## Generation runs on a worker thread; sounds requested before they are ready
## are simply skipped.

const RATE := 22050
const PENTA := [0, 2, 4, 7, 9, 12, 14, 16]

var _streams := {}
var _ready_flag := false
var _task := -1
var _players: Array[AudioStreamPlayer] = []
var _players3d: Array[AudioStreamPlayer3D] = []
var _wind: AudioStreamPlayer
var _storm: AudioStreamPlayer
var _music_timer := 3.0
var _music_players: Array[AudioStreamPlayer] = []
var _chord_root := 0
var wind_level := 0.0
var storm_level := 0.0
var music_enabled := true
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	Settings.apply()
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	for i in 8:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "SFX"
		p3.unit_size = 18.0
		p3.max_distance = 400.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p3)
		_players3d.append(p3)
	for i in 6:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		add_child(m)
		_music_players.append(m)
	_wind = AudioStreamPlayer.new()
	_wind.bus = "Ambience"
	_wind.volume_db = -60.0
	add_child(_wind)
	_storm = AudioStreamPlayer.new()
	_storm.bus = "Ambience"
	_storm.volume_db = -60.0
	add_child(_storm)
	_rng.seed = 4242
	_task = WorkerThreadPool.add_task(_generate_all)


func _exit_tree() -> void:
	# Never let the synthesis thread outlive the node whose lambdas it calls.
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _setup_buses() -> void:
	for b in ["Music", "SFX", "Ambience"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	var amb := AudioServer.get_bus_index("Ambience")
	if AudioServer.get_bus_effect_count(amb) == 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 5000.0
		AudioServer.add_bus_effect(amb, lp)
	var mus := AudioServer.get_bus_index("Music")
	if AudioServer.get_bus_effect_count(mus) == 0:
		var rev := AudioEffectReverb.new()
		rev.room_size = 0.85
		rev.damping = 0.4
		rev.wet = 0.35
		rev.dry = 0.8
		AudioServer.add_bus_effect(mus, rev)
	var sfx := AudioServer.get_bus_index("SFX")
	if AudioServer.get_bus_effect_count(sfx) == 0:
		var rev2 := AudioEffectReverb.new()
		rev2.room_size = 0.5
		rev2.wet = 0.15
		AudioServer.add_bus_effect(sfx, rev2)


func is_ready() -> bool:
	return _ready_flag


func _process(delta: float) -> void:
	if not _ready_flag:
		if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
			_ready_flag = true
			_wind.stream = _streams["wind"]
			_wind.play()
			_storm.stream = _streams["storm_loop"]
			_storm.play()
		return
	var wind_target := linear_to_db(maxf(0.18 + wind_level * 0.5, 0.0001))
	_wind.volume_db = lerpf(_wind.volume_db, wind_target, 1.0 - exp(-delta * 1.5))
	var storm_target := linear_to_db(maxf(storm_level * 0.7, 0.0001))
	_storm.volume_db = lerpf(_storm.volume_db, storm_target, 1.0 - exp(-delta * 1.0))
	if music_enabled:
		_music_timer -= delta
		if _music_timer <= 0.0:
			_play_music_phrase()


# ------------------------------------------------------------- playback
func play(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _ready_flag or not _streams.has(name):
		return
	for p in _players:
		if not p.playing:
			p.stream = _streams[name]
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return


func play_at(name: String, at: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _ready_flag or not _streams.has(name):
		return
	for p in _players3d:
		if not p.playing:
			p.stream = _streams[name]
			p.global_position = at
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return


func _play_music_phrase() -> void:
	# Gentle generative ambience: a soft pad chord and a few bell notes.
	_music_timer = _rng.randf_range(6.0, 10.0)
	var roots := [0, 5, 7, 9, -3]
	_chord_root = roots[_rng.randi() % roots.size()]
	var chord := [0, 4, 7] if _chord_root in [0, 5, 7] else [0, 3, 7]
	var k := 0
	for n in chord:
		var mp := _music_players[k]
		k += 1
		mp.stream = _streams["pad"]
		mp.pitch_scale = pow(2.0, float(_chord_root + n - 12) / 12.0)
		mp.volume_db = -14.0
		mp.play()
	var notes := _rng.randi_range(1, 3)
	for i in notes:
		var mp2 := _music_players[3 + i % 3]
		var semi: int = PENTA[_rng.randi() % PENTA.size()] + _chord_root
		mp2.stream = _streams["bell"]
		mp2.pitch_scale = pow(2.0, float(semi) / 12.0)
		mp2.volume_db = -20.0
		get_tree().create_timer(_rng.randf_range(0.5, 4.5)).timeout.connect(mp2.play)


# ------------------------------------------------------------- synthesis
func _to_stream(buf: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = buf.size()
	return s


func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


static func _env(t: float, attack: float, decay: float) -> float:
	if t < attack:
		return t / attack
	return exp(-(t - attack) / decay)


## Filtered noise with a moving cutoff (0..1 one-pole coefficient curve).
func _noise(seconds: float, cutoff: Callable, amp: Callable, seed_value: int) -> PackedFloat32Array:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var b := _buf(seconds)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var c: float = cutoff.call(t)
		lp += (r.randf_range(-1.0, 1.0) - lp) * c
		lp2 += (lp - lp2) * c
		b[i] = lp2 * float(amp.call(t))
	return b


func _bell(freq: float, seconds: float, amp: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	for i in b.size():
		var t := float(i) / RATE
		var e := _env(t, 0.004, seconds * 0.28)
		b[i] = amp * e * (sin(TAU * freq * t) * 0.7 + sin(TAU * freq * 2.0 * t) * 0.2 * exp(-t * 3.0) + sin(TAU * freq * 3.01 * t) * 0.08 * exp(-t * 5.0))
	return b


func _mix(a: PackedFloat32Array, b: PackedFloat32Array, offset_s: float = 0.0, gain: float = 1.0) -> PackedFloat32Array:
	var off := int(offset_s * RATE)
	var n := maxi(a.size(), b.size() + off)
	var out := a.duplicate()
	out.resize(n)
	for i in b.size():
		out[i + off] += b[i] * gain
	return out


func _normalize(b: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0001
	for v in b:
		m = maxf(m, absf(v))
	var k := peak / m
	for i in b.size():
		b[i] *= k
	return b


func _loopify(b: PackedFloat32Array, fade_s: float) -> PackedFloat32Array:
	var f := int(fade_s * RATE)
	var n := b.size() - f
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = b[i]
	for i in f:
		var t := float(i) / f
		out[i] = b[i] * t + b[n + i] * (1.0 - t)
	return out


func _generate_all() -> void:
	var s := {}
	# Ambient wind loop: slow-moving filtered noise.
	var wind := _noise(7.0, func(t): return 0.012 + 0.018 * (0.5 + 0.5 * sin(t * 0.9) * sin(t * 0.37 + 1.0)),
		func(t): return 0.8 + 0.2 * sin(t * 0.6), 11)
	s["wind"] = _to_stream(_normalize(_loopify(wind, 1.0), 0.35), true)
	var storm := _noise(6.0, func(t): return 0.006 + 0.006 * (0.5 + 0.5 * sin(t * 1.3)), func(_t): return 1.0, 12)
	s["storm_loop"] = _to_stream(_normalize(_loopify(storm, 1.0), 0.45), true)
	# Casts.
	var poof := _noise(0.9, func(t): return 0.25 * exp(-t * 3.0) + 0.02, func(t): return _env(t, 0.02, 0.18), 21)
	poof = _mix(_normalize(poof, 0.4), _bell(1318.5, 0.9, 0.18), 0.02)
	poof = _mix(poof, _bell(1975.5, 0.8, 0.10), 0.07)
	s["cast_cloud"] = _to_stream(_normalize(poof, 0.6))
	var whoosh := _noise(1.0, func(t): return 0.04 + 0.2 * sin(PI * clampf(t / 1.0, 0.0, 1.0)), func(t): return sin(PI * clampf(t / 1.0, 0.0, 1.0)), 22)
	whoosh = _mix(_normalize(whoosh, 0.5), _bell(880.0, 0.7, 0.08), 0.05)
	s["cast_front"] = _to_stream(_normalize(whoosh, 0.6))
	var gust := _noise(1.6, func(t): return 0.02 + 0.06 * sin(PI * t / 1.6), func(t): return pow(sin(PI * t / 1.6), 1.5), 23)
	s["cast_wind"] = _to_stream(_normalize(gust, 0.6))
	var rumble := _noise(2.4, func(_t): return 0.008, func(t): return _env(t, 0.4, 0.9), 24)
	var low := _buf(2.4)
	for i in low.size():
		var t := float(i) / RATE
		low[i] = sin(TAU * 52.0 * t) * _env(t, 0.3, 0.8) * 0.4
	s["cast_blizzard"] = _to_stream(_normalize(_mix(_normalize(rumble, 0.6), low), 0.7))
	var aval := _noise(3.0, func(t): return 0.01 + 0.02 * exp(-t), func(t): return _env(t, 0.25, 1.2), 25)
	var r := RandomNumberGenerator.new()
	r.seed = 99
	for k in 60:
		var at := r.randf_range(0.1, 2.0)
		var i0 := int(at * RATE)
		for j in 300:
			if i0 + j < aval.size():
				aval[i0 + j] += r.randf_range(-1, 1) * exp(-j / 60.0) * 0.08
	s["cast_avalanche"] = _to_stream(_normalize(aval, 0.75))
	var vort := _buf(3.2)
	var lp := 0.0
	r.seed = 77
	for i in vort.size():
		var t := float(i) / RATE
		var c := 0.02 + 0.05 * (0.5 + 0.5 * sin(t * 6.0))
		lp += (r.randf_range(-1, 1) - lp) * c
		vort[i] = (lp * 0.8 + sin(TAU * (40.0 + 10.0 * sin(t * 2.0)) * t) * 0.25) * _env(t, 0.6, 1.4)
	s["cast_vortex"] = _to_stream(_normalize(vort, 0.75))
	# UI and rewards.
	var buy := _bell(1046.5, 0.6, 0.4)
	buy = _mix(buy, _bell(1318.5, 0.6, 0.35), 0.07)
	buy = _mix(buy, _bell(1568.0, 0.8, 0.3), 0.14)
	s["purchase"] = _to_stream(_normalize(buy, 0.55))
	var ms := _bell(523.25, 2.0, 0.3)
	for n in [659.25, 783.99, 1046.5]:
		ms = _mix(ms, _bell(n, 2.0, 0.25), 0.05)
	s["milestone"] = _to_stream(_normalize(ms, 0.6))
	var core := PackedFloat32Array()
	var notes := [1046.5, 1174.7, 1318.5, 1568.0, 1760.0, 2093.0]
	for k in notes.size():
		core = _mix(core, _bell(notes[k], 1.2, 0.3), k * 0.07)
	s["core"] = _to_stream(_normalize(core, 0.6))
	var combo := _bell(1568.0, 0.8, 0.3)
	combo = _mix(combo, _bell(2093.0, 0.9, 0.25), 0.08)
	combo = _mix(combo, _noise(0.8, func(_t): return 0.6, func(t): return _env(t, 0.01, 0.15) * 0.15, 31), 0.0)
	s["combo"] = _to_stream(_normalize(combo, 0.5))
	var click := _buf(0.06)
	for i in click.size():
		var t := float(i) / RATE
		click[i] = sin(TAU * 1300.0 * t) * exp(-t * 90.0) * 0.5
	s["click"] = _to_stream(click)
	var hover := _buf(0.04)
	for i in hover.size():
		var t := float(i) / RATE
		hover[i] = sin(TAU * 2100.0 * t) * exp(-t * 140.0) * 0.18
	s["hover"] = _to_stream(hover)
	var err := _buf(0.3)
	for i in err.size():
		var t := float(i) / RATE
		var f := 330.0 if t < 0.12 else 247.0
		err[i] = sin(TAU * f * t) * _env(fmod(t, 0.12), 0.005, 0.05) * 0.3
	s["error"] = _to_stream(err)
	var pulse := _buf(1.0)
	for i in pulse.size():
		var t := float(i) / RATE
		pulse[i] = (sin(TAU * 1760.0 * t) + sin(TAU * 2217.5 * t) * 0.6 + sin(TAU * 2637.0 * t) * 0.4) * _env(t, 0.01, 0.3) * (0.7 + 0.3 * sin(t * 60.0)) * 0.15
	s["pulse"] = _to_stream(pulse)
	# Music voices.
	var pad := _buf(6.0)
	for i in pad.size():
		var t := float(i) / RATE
		var e := minf(t / 1.8, 1.0) * minf((6.0 - t) / 2.5, 1.0)
		var f0 := 261.63
		pad[i] = e * (sin(TAU * f0 * t) * 0.5 + sin(TAU * f0 * 1.003 * t) * 0.35 + sin(TAU * f0 * 2.0 * t) * 0.12 + sin(TAU * f0 * 0.5 * t) * 0.2)
	s["pad"] = _to_stream(_normalize(pad, 0.4))
	s["bell"] = _to_stream(_normalize(_bell(523.25, 3.0, 0.4), 0.45))
	var done := _bell(261.63, 5.0, 0.3)
	for n in [329.63, 392.0, 523.25, 659.25, 783.99]:
		done = _mix(done, _bell(n, 5.0, 0.22), 0.25)
	s["complete"] = _to_stream(_normalize(done, 0.6))
	_streams = s
