"""Create the action picker Widget Blueprint in an Unreal 5.7 editor project."""
import unreal as u

path = "/Game/PBZActionMenu"
tools = u.AssetToolsHelpers.get_asset_tools()
editor = u.EditorUtilityLibrary
asset_path = path + "/WBP_ActionMenu"
bp = (u.load_asset(asset_path) if u.EditorAssetLibrary.does_asset_exist(asset_path)
      else tools.create_asset("WBP_ActionMenu", path, u.WidgetBlueprint, u.WidgetBlueprintFactory()))
assert bp


def source_widget(kind, name, parent):
    return editor.find_source_widget_by_name(bp, name) or editor.add_source_widget(bp, kind, name, parent)


root = source_widget(u.CanvasPanel, "Root", "None")
assert root


def place(widget, x, y, width, height, layer):
    slot = widget.get_editor_property("slot")
    slot.set_anchors(u.Anchors(minimum=u.Vector2D(.5, .5), maximum=u.Vector2D(.5, .5)))
    slot.set_position(u.Vector2D(x - 332, y - 157))
    slot.set_size(u.Vector2D(width, height))
    slot.set_z_order(layer)


def panel(name, x, y, width, height, rgba, layer=2):
    widget = source_widget(u.Border, name, "Root")
    place(widget, x, y, width, height, layer)
    widget.set_brush_color(u.LinearColor(*rgba))
    return widget


def label(name, text, size, x, y, width, height):
    widget = source_widget(u.TextBlock, name, "Root")
    place(widget, x, y, width, height, 3)
    font = widget.get_editor_property("font")
    font.set_editor_property("size", size)
    widget.set_font(font)
    widget.set_text(text)
    widget.set_color_and_opacity(u.SlateColor(specified_color=u.LinearColor(.88, .83, .73, 1)))
    return widget


panel("Frame", 0, 0, 664, 314, (.22, .18, .12, 1), 0)
panel("Backdrop", 1, 1, 662, 312, (.028, .025, .023, .97), 1)
panel("TitleStrip", 18, 12, 628, 55, (.19, .055, .035, .95))
label("Title", "GESTURES", 28, 36, 21, 580, 40)
for i, text in enumerate(("Point Down", "Weapon Enchant", "Dung Pie", "Stalk Dung Pie")):
    x, y = 24 + (i % 2) * 314, 78 + (i // 2) * 78
    panel(f"Tile{i + 1}", x, y, 302, 66, (.09, .08, .07, .94))
    label(f"Action{i + 1}", text, 21, x + 20, y + 19, 270, 36)
panel("FooterLine", 24, 234, 616, 1, (.37, .29, .20, .82))
label("Help", "ARROWS Select  |  ENTER Perform  |  O / BACKSPACE Close", 15, 25, 247, 614, 54)
u.BlueprintEditorLibrary.compile_blueprint(bp)
assert u.EditorAssetLibrary.save_loaded_asset(bp, False)
u.log_warning("PBZ_ACTION_MENU_READY")
