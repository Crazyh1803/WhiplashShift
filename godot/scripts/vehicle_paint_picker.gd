extends HBoxContainer

signal color_changed(value: Color)
const PALETTE := preload("res://scripts/blackjack_paint_palette.gd")
static var _chips: Dictionary={}
var unrestricted: ColorPickerButton
var preset: MenuButton
var color := Color.WHITE:
	set(value):
		color=value
		_sync_color()


func _init() -> void:
	unrestricted=ColorPickerButton.new()
	unrestricted.edit_alpha=false
	unrestricted.custom_minimum_size=Vector2(130,38)
	unrestricted.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	unrestricted.color_changed.connect(func(value: Color) -> void:
		color=value
		color_changed.emit(value))
	add_child(unrestricted)
	preset=MenuButton.new()
	preset.custom_minimum_size=Vector2(130,38)
	preset.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	preset.add_theme_font_size_override("font_size",12)
	add_child(preset)
	for index in range(PALETTE.SWATCHES.size()):
		var swatch: Dictionary=PALETTE.SWATCHES[index]
		preset.get_popup().add_icon_item(_chip(Color(swatch["hex"])),swatch["name"],index)
	preset.get_popup().id_pressed.connect(choose_palette)
	limit_to_palette(false)
	_sync_color()


func limit_to_palette(enabled: bool) -> void:
	unrestricted.visible=not enabled
	preset.visible=enabled
	if enabled:
		_sync_color()


func choose_palette(index: int) -> void:
	if index<0 or index>=PALETTE.SWATCHES.size():
		return
	var new_color:=Color(PALETTE.SWATCHES[index]["hex"])
	if color==new_color:
		return
	color=new_color
	color_changed.emit(color)


func _sync_color() -> void:
	if unrestricted==null or preset==null:
		return
	unrestricted.color=color
	if not preset.visible:
		return
	preset.icon=_chip(color)
	preset.text=PALETTE.label_for(color)
	preset.tooltip_text="12 metallic finishes. Saved custom colors are preserved until you choose a swatch."


func _chip(value: Color) -> ImageTexture:
	var key:=value.to_html(false)
	if _chips.has(key):
		return _chips[key]
	var image:=Image.create(16,16,false,Image.FORMAT_RGBA8)
	image.fill(value)
	var result:=ImageTexture.create_from_image(image)
	# Cache the finite palette, not every intermediate unrestricted drag color.
	if PALETTE.label_for(value)!="SAVED CUSTOM":
		_chips[key]=result
	return result
