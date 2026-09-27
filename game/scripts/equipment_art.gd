extends RefCounted

## Catalog renders use the same equipment factory as installed models.
const ORDER := ["backup", "monitor", "plant", "workstation", "diagnostic", "teamdesk", "annexdesk_a", "annexdesk_b"]
static var _icons: Dictionary = {}
static var _customer_atlas: Texture2D

static func icon(id: String) -> Texture2D:
	if _icons.has(id): return _icons[id]
	if id in ["stock_gateway", "stock_backup"]:
		if _customer_atlas == null: _customer_atlas = load("res://assets/ui/customer-appliances.png")
		var customer_texture := AtlasTexture.new()
		customer_texture.atlas = _customer_atlas
		var half := float(_customer_atlas.get_width()) / 2.0
		customer_texture.region = Rect2(0 if id == "stock_gateway" else half, 0, half, _customer_atlas.get_height())
		customer_texture.filter_clip = true
		_icons[id] = customer_texture
		return customer_texture
	if id not in ORDER: return null
	var texture: Texture2D = load("res://assets/ui/equipment_catalog_polish/%s.png" % id)
	_icons[id] = texture
	return texture
