extends RefCounted

## The rules of a blow landing, the same whoever throws it. A fighter is
## anything with an arm, facing() and is_evading().

const Strike = preload("res://Experiments/SteelBoss/strike.gd")


## "miss", "evade", "parry", "block" or "hit".
static func resolve(attacker: Node3D, defender: Node3D, strike: Strike) -> String:
	var to := defender.global_position - attacker.global_position
	to.y = 0.0
	if to.length() > strike.reach:
		return "miss"
	var facing: Vector3 = attacker.facing()
	var in_line := facing.angle_to(to) <= strike.half_arc()
	if defender.is_evading():
		return "evade"
	if not in_line:
		return "miss"
	var sees: bool = defender.facing().dot(-to.normalized()) > 0.2
	if sees and defender.arm.covers(strike.comes_from()):
		if defender.arm.is_fresh():
			return "parry"
		if not strike.heavy:
			return "block"
	return "hit"
