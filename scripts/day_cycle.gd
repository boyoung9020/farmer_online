extends Node
## 하루 사이클(8분 = 하루): 새벽 → 정오 → 노을 → 밤.
## 태양 고도/색, 하늘색, 안개색, 앰비언트를 함께 굴린다. 밤에도 플레이 가능한 밝기 유지.

const DAY_LEN := 480.0

var sun: DirectionalLight3D
var env: Environment
var sky: ProceduralSkyMaterial
var hud

var _t := DAY_LEN * 0.42   # 오전 10시쯤(그림자 짧은 시간대)부터 시작

func _process(delta: float) -> void:
	_t = fmod(_t + delta, DAY_LEN)
	var ph := _t / DAY_LEN                       # 0..1 (0 = 자정)
	var sun_h := -cos(ph * TAU)                  # -1(자정) .. 1(정오)
	var day := clampf(sun_h * 1.6 + 0.15, 0.0, 1.0)        # 낮 정도
	var dusk := clampf(1.0 - absf(sun_h) * 2.6, 0.0, 1.0)  # 여명/노을 정도

	# 태양 고도 (방위는 탑다운이라 고정)
	var elev := lerpf(3.0, 56.0, clampf(sun_h, 0.0, 1.0))
	sun.rotation_degrees = Vector3(-maxf(elev, 3.0), -38.0, 0.0)
	sun.light_energy = 1.25 * day + 0.07                    # 밤엔 달빛 수준
	var noon_col := Color(1.0, 0.96, 0.87)
	var dusk_col := Color(1.0, 0.60, 0.30)
	var night_col := Color(0.55, 0.65, 0.95)
	var col := noon_col.lerp(dusk_col, dusk)
	sun.light_color = col.lerp(night_col, 1.0 - day)

	# 앰비언트/하늘/안개
	env.ambient_light_energy = lerpf(0.28, 0.75, day)
	var top_day := Color(0.32, 0.55, 0.83)
	var top_night := Color(0.03, 0.05, 0.11)
	var hor_day := Color(0.78, 0.86, 0.90)
	var hor_dusk := Color(0.96, 0.56, 0.30)
	var hor_night := Color(0.06, 0.08, 0.14)
	sky.sky_top_color = top_night.lerp(top_day, day)
	var hor := hor_night.lerp(hor_day, day).lerp(hor_dusk, dusk * 0.8)
	sky.sky_horizon_color = hor
	sky.ground_horizon_color = hor * 0.9
	env.fog_light_color = hor.lerp(Color(0.80, 0.87, 0.92), day * 0.5)

	# 가로등: 어두워지면 점등
	var night := clampf(1.0 - day * 1.5, 0.0, 1.0)
	for lamp in get_tree().get_nodes_in_group("street_lamps"):
		(lamp.get_meta("light") as OmniLight3D).light_energy = night * 2.4
		(lamp.get_meta("glass") as StandardMaterial3D).emission_energy_multiplier = 0.4 + night * 3.0

	if hud != null:
		var hours := ph * 24.0
		hud.set_time("%02d:%02d" % [int(hours), int(fmod(hours, 1.0) * 60.0)])
