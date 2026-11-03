class_name AmmoType
extends RefCounted
## One kind of shroom shooter ammo: how it fires, what it does and how it looks. The registry
## (ORDER, by_name) is built in code, so every peer has the same table; tune the numbers here.
##
## Fire modes:
##   hitscan     `pellets` instant rays (Combat.ray_hit) spread over `spread` degrees
##   cone        a short cone (`reach`, `spread` = half-angle) checked `rate` times a second while
##               held; each check costs one unit (fuel)
##   projectile  a Projectile moved each physics tick (speed, gravity, bounces, pierce, homing)
## Impacts (projectiles): "" (direct damage only), "blast" (carve + Combat.sphere_hit through
## WorldSync / EnemyManager), "cloud" (a host-owned Cloud of `cloud_type`, see Weapon.spawn_cloud).
##
## Flasks (thrown with alt_fire) are AmmoTypes too, named "flask_<type>" (FLASK_DEFS, by_name):
## arcing projectiles drawn with their item model, which shatter into a Cloud. They're never
## loaded into the gun and aren't in ORDER.

## Ammo names in slot order: ammo_1..4 pick the first four, Shift cycles through them.
const ORDER := ["basic", "shotgun", "flame", "explosive", "ricochet", "homing", "poison"]

## name -> settings; anything left out takes the defaults of the fields below.
const DEFS := {
	basic = {label = "Basic", color = Color(0.45, 1.0, 0.75), mode = "hitscan", damage = 12.0, rate = 8.0,
			reach = 120.0, spread = 0.4, infinite = true, sound = "rifle", kind = "rifle",
			carve_radius = 0.14, carve_power = 4},
	shotgun = {label = "Shotgun", color = Color(1.0, 0.8, 0.3), mode = "hitscan", damage = 7.0, pellets = 8,
			spread = 7.0, rate = 1.4, reach = 16.0, sound = "shotgun", kind = "shotgun", carve_radius = 0.12,
			carve_power = 3, recoil = 0.07, shake = 0.4, pickup = 12, max_count = 48},
	flame = {label = "Flame", color = Color(1.0, 0.45, 0.1), mode = "cone", damage = 4.0, spread = 20.0,
			rate = 10.0, reach = 4.5, sound = "flame", sound_db = -6.0, kind = "flame", status = "burning",
			status_seconds = 3.0, recoil = 0.0, shake = 0.04, pickup = 60, max_count = 240, ignite_radius = 0.35,
			ignite_count = 6},
	explosive = {label = "Explosive", color = Color(1.0, 0.28, 0.2), mode = "projectile", damage = 20.0,
			rate = 1.2, speed = 30.0, gravity = 6.0, impact = "blast", blast_radius = 1.2, blast_power = 6,
			blast_damage = 40.0, splash_radius = 2.0, sound = "blast", sound_db = -8.0, sound_pitch = 1.8,
			kind = "blast", recoil = 0.06, shake = 0.3, pickup = 4, max_count = 16, ignite_radius = 1.6,
			ignite_count = 25},
	ricochet = {label = "Ricochet", color = Color(0.6, 0.78, 1.0), mode = "projectile", damage = 18.0,
			rate = 3.0, speed = 40.0, bounces = 4, pierce = true, sound = "ricochet", kind = "ricochet",
			carve_radius = 0.1, carve_power = 3, pickup = 15, max_count = 60},
	homing = {label = "Homing", color = Color(0.92, 0.4, 1.0), mode = "projectile", damage = 20.0, rate = 2.5,
			speed = 20.0, homing_angle = 30.0, homing_turn = 5.0, sound = "homing", kind = "homing",
			carve_radius = 0.2, carve_power = 4, pickup = 10, max_count = 40},
	poison = {label = "Poison", color = Color(0.45, 1.0, 0.3), mode = "projectile", damage = 10.0, rate = 1.5,
			speed = 22.0, gravity = 4.0, impact = "cloud", cloud_type = "poison", cloud_radius = 2.0,
			cloud_seconds = 5.0, sound = "poison_shot", kind = "poison", pickup = 6, max_count = 24},
}

## Flask types (Inventory.FLASKS) -> settings over FLASK_BASE. The cloud sizes and times default
## to the Cloud type's own (Cloud.TYPES) when left at -1.
const FLASK_BASE := {mode = "projectile", damage = 5.0, rate = 1.25, speed = 14.0, gravity = 12.0, reach = 56.0,
		impact = "cloud", cloud_radius = -1.0, cloud_seconds = -1.0, sound = "flask_throw", kind = "flask",
		recoil = 0.0, shake = 0.08, flask = true}
const FLASK_DEFS := {
	fire = {label = "Fire", color = Color(1.0, 0.5, 0.15), cloud_type = "fire"},
	poison = {label = "Poison", color = Color(0.45, 1.0, 0.3), cloud_type = "poison"},
	rage = {label = "Rage", color = Color(1.0, 0.2, 0.3), cloud_type = "rage"},
	freeze = {label = "Freeze", color = Color(0.55, 0.85, 1.0), cloud_type = "freeze"},
}

var name := ""
var label := ""
var color := Color.WHITE
var mode := "hitscan"
## Per pellet, per cone check, or per projectile hit.
var damage := 10.0
var pellets := 1
## Degrees: the pellet spread cone for hitscan, the half-angle for cone.
var spread := 0.0
## Shots (or cone checks) per second.
var rate := 5.0
## Meters: hitscan and cone reach; projectiles live for reach / speed seconds.
var reach := 120.0
var infinite := false
## Fire sound (Sfx name), its volume and pitch.
var sound := "rifle"
var sound_db := 0.0
var sound_pitch := 1.0
## Damage kind for EnemyManager.request_hit (knockback).
var kind := "rifle"
## Terrain chip where a hitscan pellet or a bouncing / impacting projectile hits voxels (0 = none).
var carve_radius := 0.0
var carve_power := 0
## Sets flammable voxels alight (Fire.ignite_at) where it lands: the cone's aim point, a blast's
## crater. At most ignite_count voxels within ignite_radius meters (0 = none).
var ignite_radius := 0.0
var ignite_count := 0
## Status applied to enemies hit (Enemy.apply_status), "" for none.
var status := ""
var status_seconds := 0.0
var recoil := 0.018
var shake := 0.12
## Rounds an ammo pickup gives, and the most a player carries.
var pickup := 10
var max_count := 50

# Projectiles.
var speed := 30.0
var gravity := 0.0
var bounces := 0
## Passes through enemies, damaging each once.
var pierce := false
## Steers toward the nearest enemy within this many degrees of its heading (0 = no homing), turning
## at most homing_turn radians per second.
var homing_angle := 0.0
var homing_turn := 0.0
var impact := ""
var blast_radius := 0.0
var blast_power := 0
var blast_damage := 0.0
var splash_radius := 0.0
## "cloud" impacts: the Cloud type, its radius and seconds (-1: the type's defaults).
var cloud_type := ""
var cloud_radius := 0.0
var cloud_seconds := 0.0
## A thrown flask ("flask_<type>"), drawn with its item model (GearModels.item(name)).
var flask := false

static var _types := {}


## The ammo type called name (see ORDER), or a flask ("flask_fire"), or null.
static func by_name(ammo_name: String) -> AmmoType:
	if _types.is_empty():
		for key: String in ORDER:
			_types[key] = _make(key, DEFS[key])
		for key: String in FLASK_DEFS:
			var settings := FLASK_BASE.duplicate()
			settings.merge(FLASK_DEFS[key], true)
			_types["flask_" + key] = _make("flask_" + key, settings)
	return _types.get(ammo_name)


## The flask type thrown for an Inventory flask name ("fire"), or null.
static func flask_type(flask_name: String) -> AmmoType:
	return by_name("flask_" + flask_name)


static func _make(type_name: String, settings: Dictionary) -> AmmoType:
	var type := AmmoType.new()
	type.name = type_name
	for field: String in settings:
		type.set(field, settings[field])
	return type


## Every type in slot order.
static func all() -> Array[AmmoType]:
	var out: Array[AmmoType] = []
	for key: String in ORDER:
		out.append(by_name(key))
	return out


## Seconds a projectile lives.
func lifetime() -> float:
	return reach / maxf(speed, 0.1) if mode == "projectile" else 0.0
