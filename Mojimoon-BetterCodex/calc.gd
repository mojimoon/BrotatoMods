extends Reference

# 纯计算：攻击冷却（复刻网页图鉴 codexStore.js，1.2 无头逐帧实测过）、诅咒强度范围。价格与异变用游戏函数（preview.gd）。
# 冷却以帧为单位（60 帧 / 秒）；atk = 攻速 / 100。

const FPS = 60.0
const MIN_COOLDOWN = 2	# WeaponService.MIN_COOLDOWN
const MIN_RANGE = 25	# WeaponService.MIN_RANGE
const BASE_ATK_DURATION = 0.2	# MeleeShootingData.BASE_ATK_DURATION
const DEFAULT_WEAPON_COUNT = 6


# WeaponService.apply_attack_speed_mod_to_cooldown
static func cd_frames(base: float, atk: float) -> int:
	base = max(MIN_COOLDOWN, base)
	if atk < 0:
		return int(max(MIN_COOLDOWN, base * (1.0 + abs(atk))))
	return int(max(MIN_COOLDOWN, base / (1.0 + atk)))


# 补间动画的实际帧数（0.05 秒少一帧）
static func tween(d: float) -> int:
	if d == 0.05:
		return 4
	return int(floor(d * 60.0)) + 2


static func _tri(v: float) -> float:
	return v * (v + 1.0) / 2.0


# 冷却在 [mn, mx] 内均匀随机、按整帧 ceil 计时时的平均帧数
static func avg_duration(mn: float, mx: float) -> float:
	if mx <= mn:
		return mx
	var cmin = ceil(mn)
	var fmax = floor(mx)
	return ((cmin - mn) * cmin + _tri(fmax) - _tri(cmin) + (mx - fmax) * ceil(mx)) / (mx - mn)


static func is_melee(stats) -> bool:
	return stats is MeleeWeaponStats


static func is_animation_driven(stats) -> bool:
	return stats is MeleeWeaponStats and stats.attack_duration > 0.0


# MeleeShootingData：攻击 / 收回时长（秒）；eff_range = 已含范围属性的最大射程
static func melee_timing(stats, atk: float, eff_range: float) -> Dictionary:
	var anim = max(0.01, stats.animation_speed)
	var rf = max(0.0, eff_range / clamp(70.0 * (1.0 + atk / 3.0), 70.0, 120.0))
	var atk_d = (max(0.01, BASE_ATK_DURATION - atk / 10.0) + rf * 0.15) / anim
	var back = (BASE_ATK_DURATION / (1.0 + atk * 3.0) if atk > 0 else BASE_ATK_DURATION) / anim
	return {"atk": atk_d, "back": back}


static func effective_range(stats, stat_range: float) -> float:
	var min_range = MIN_RANGE + stats.min_range if stats.min_range != 0 else MIN_RANGE
	return float(int(max(min_range, stats.max_range + stat_range / 2.0)))


# 一次攻击的帧数。stats = 武器基础属性（未经玩家属性修正）；atk = 攻速 / 100（含武器自身 attack_speed_mod）。
# 返回 {wcf, add_cd, min, max, avg, tooltip（秒，游戏 tooltip 的算法）, shots, reload（换弹帧数，无则 -1）, reload_tooltip}
static func timing(stats, atk: float, stat_range: float = 0.0, count: int = DEFAULT_WEAPON_COUNT) -> Dictionary:
	count = int(clamp(count, 1, 6))
	var wcf = cd_frames(stats.cooldown, atk)
	var recoil = stats.recoil_duration / (1.0 + atk) if atk > 0 else stats.recoil_duration
	var add_cd = 0
	var tooltip = wcf / FPS
	var alt_fix = false
	if is_animation_driven(stats):
		add_cd = int(ceil(stats.attack_duration * FPS))
		tooltip += stats.attack_duration
	elif is_melee(stats):
		var t = melee_timing(stats, atk, effective_range(stats, stat_range))
		add_cd = tween(recoil) + tween(t.back) - 1
		var half = tween(t.atk / 2.0)
		var quarter = tween(t.atk / 4.0)
		add_cd += half if stats.attack_type == MeleeWeaponStats.AttackType.THRUST else 2 * quarter
		alt_fix = stats.alternate_attack_type and half > 2 * quarter
		tooltip += recoil + t.atk / 2.0 + t.back
	else:
		add_cd = 2 * tween(recoil) - 1
		tooltip += recoil * 2.0
	var spread = min(count * wcf / 5.0, count * 5.0)
	var r = {
		"wcf": wcf, "add_cd": add_cd,
		"min": add_cd + int(floor(max(1, wcf - spread))) + 1,
		"max": add_cd + int(ceil(wcf + spread)),
		"avg": add_cd + avg_duration(max(1, wcf - spread), wcf + spread),
		"tooltip": tooltip, "shots": 0, "reload": -1, "reload_tooltip": 0.0,
	}
	if alt_fix:
		r.min -= 2
		r.avg -= 1
	if stats.additional_cooldown_every_x_shots > 0 and stats.additional_cooldown_multiplier > 0:
		# WeaponService.init_base_stats：换弹 = max(普通冷却, 攻速作用于 round(基础冷却 × 倍率))
		var big = max(wcf, cd_frames(round(stats.cooldown * stats.additional_cooldown_multiplier), atk))
		r.shots = stats.additional_cooldown_every_x_shots
		r.reload = add_cd + big
		r.reload_tooltip = tooltip + (big - wcf) / FPS
	return r


# 含换弹的等效每次攻击秒数
static func effective_seconds(t: Dictionary) -> float:
	var cd = t.avg / FPS
	if t.shots > 0:
		return cd + (t.reload / FPS - cd) / t.shots
	return cd


# 相对攻速 0 的 DPS 变化（%）
static func dps_change(stats, atk: float, stat_range: float, count: int) -> float:
	var base = effective_seconds(timing(stats, 0.0, stat_range, count))
	var cur = effective_seconds(timing(stats, atk, stat_range, count))
	return (base / cur - 1.0) * 100.0 if cur > 0 else 0.0


# 攻速断点（1–67）：平均帧数变化且 DPS 提升 ≥ 1% 的攻速；只对实际冷却 < 0.25 秒的武器有意义
static func breakpoints(stats, stat_range: float, count: int) -> Array:
	var t0 = timing(stats, 0.0, stat_range, count)
	if t0.avg / FPS >= 0.25:
		return []
	var base = effective_seconds(t0)
	var out = []
	var prev = -1
	for a in range(1, 68):
		var t = timing(stats, a / 100.0, stat_range, count)
		var frames = int(round(t.avg))
		if frames != prev:
			prev = frames
			var pct = (base / effective_seconds(t) - 1.0) * 100.0
			if pct >= 1.0:
				out.push_back([a, pct])
	return out


# 游戏 tooltip 的冷却文字（WeaponStats.get_cooldown_text 去掉颜色）
static func cooldown_str(seconds: float) -> String:
	return str(stepify(seconds, 0.001 if seconds < 0.2 else 0.01)) + "s"


static func actual_str(frames: float) -> String:
	return cooldown_str(frames / FPS)


# DLC1Data._get_cursed_item_effect_modifier 的取值范围（%）：[中位 - 随机, 中位 + 随机]，中位 = 基础 + 每波增量 × min(20, 波次 - 1)
static func curse_range(dlc1, wave: int) -> Array:
	var mid = dlc1.cursed_item_base_percent_modifier + dlc1.cursed_item_percent_modifier_increase_each_wave * min(20, wave - 1)
	var rnd = dlc1.cursed_item_random_percent_modifier
	return [max(0, mid - rnd), mid, mid + rnd]

