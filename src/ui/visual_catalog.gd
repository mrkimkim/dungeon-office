class_name VisualCatalog
extends RefCounted

## Presentation-only lookup for optional runtime artwork. Gameplay and save data
## continue to use stable content IDs; a missing or unmapped texture falls back
## to the existing text UI instead of blocking the play screen.

const FACILITY_TEXTURE_PATHS: Dictionary = {
	"FAC_SUPPLY": "res://art/mvp/runtime/facilities/fac_supply.png",
	"FAC_FURNACE": "res://art/mvp/runtime/facilities/fac_furnace.png",
	"FAC_WEAPON_BENCH": "res://art/mvp/runtime/facilities/fac_weapon_bench.png",
	"FAC_SYNTH_BENCH": "res://art/mvp/runtime/facilities/fac_synth_bench.png",
	"FAC_ENHANCE_ANVIL": "res://art/mvp/runtime/facilities/fac_enhance_anvil.png",
	"FAC_DELIVERY": "res://art/mvp/runtime/facilities/fac_delivery.png",
	"FAC_TRASH": "res://art/mvp/runtime/facilities/fac_trash.png",
}

const ITEM_TEXTURE_PATHS: Dictionary = {
	"MAT_IRON_ORE": "res://art/mvp/runtime/items/mat_iron_ore.png",
	"MAT_WOOD": "res://art/mvp/runtime/items/mat_wood.png",
	"MAT_MANA_SHARD": "res://art/mvp/runtime/items/mat_mana_shard.png",
	"MAT_IRON_INGOT": "res://art/mvp/runtime/items/mat_iron_ingot.png",
	"MAT_CHARCOAL": "res://art/mvp/runtime/items/mat_charcoal.png",
	"MAT_ENHANCEMENT_STONE": "res://art/mvp/runtime/items/mat_enhancement_stone.png",
	"EQ_DAGGER": "res://art/mvp/runtime/items/eq_dagger.png",
	"EQ_IRON_SWORD": "res://art/mvp/runtime/items/eq_iron_sword.png",
}

static var _facility_textures: Dictionary = {}
static var _item_textures: Dictionary = {}


static func facility_texture(facility_id: String) -> Texture2D:
	return _texture_for_id(facility_id, FACILITY_TEXTURE_PATHS, _facility_textures)


static func item_texture(item_id: String) -> Texture2D:
	return _texture_for_id(item_id, ITEM_TEXTURE_PATHS, _item_textures)


static func _texture_for_id(
	content_id: String,
	paths: Dictionary,
	cache: Dictionary
) -> Texture2D:
	if cache.has(content_id):
		return cache[content_id] as Texture2D
	var path := str(paths.get(content_id, ""))
	if path.is_empty() or not ResourceLoader.exists(path, "Texture2D"):
		cache[content_id] = null
		return null
	var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
	cache[content_id] = texture
	return texture
