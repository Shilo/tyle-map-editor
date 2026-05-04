# Tyle Map Editor

> Y not map faster?

A Godot 4.6 editor plugin that makes terrain painting on TileMapLayer nodes intuitive and easy — pick a terrain, pick a tool, and paint directly in the viewport. Supports 7 paint tools, cell selection with cut/copy/paste (Ctrl+X/C/V), move-drag repositioning, and clipboard paste preview. Replaces the less user-friendly native TileSet bottom panel workflow with a focused, always-visible toolbar and terrain grid.

Plugin entry: `addons/tyle_map_editor/plugin.cfg`
Editor plugin: `addons/tyle_map_editor/tyle_map_editor_plugin.gd`
Panel UI: `addons/tyle_map_editor/tyle_map_editor_panel.tscn`
Panel logic: `addons/tyle_map_editor/tyle_map_editor_panel.gd`
Runtime host: `addons/tyle_map_editor/tyle_map_editor.gd`
Project config: `project.godot`
Demo scene: `main.tscn`
TileSet resource: `tileset.tres`
TileSet resource: `tiles/tileset.tres`
Tile atlas (source 0): `tiles/ground.png`
Tile atlas (source 1): `tiles/stone.png`
Project icon: `icon.svg`
MCP server: `.mcp.json`
OpenCode config: `opencode.json`

## Testing Protocol

After every code change, validate by running a **temporary headless Godot instance** and checking the output for script errors, parse errors, and warnings.

### Godot executable

The Godot editor executable path can be found from any running Godot process:

```powershell
$godotExe = (Get-Process -Name "Godot*" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path)
```

### Headless validation command

```powershell
& $godotExe --editor --headless --path "<project_dir>" --quit 2>&1 | Select-Object -First 200
```

- `--editor` — loads editor plugins
- `--headless` — no GUI window
- `--quit` — exits after loading
- `2>&1` — captures stderr merged with stdout

### What to check

| Pattern | Meaning |
|---|---|
| `SCRIPT ERROR: Parse Error` | GDScript syntax or type inference failure — **must fix** |
| `SCRIPT ERROR:` | Runtime error during plugin init — **must fix** |
| `ERROR:` | Engine-level error (missing files, UIDs, etc.) |
| Warnings | Less critical but investigate |

### Editor instance policy

**Never** open a new headed editor instance. Either:
- Re-launch the current headed instance, or
- Use the already-running headed instance

Pre-existing errors unrelated to your changes can be noted but should not block progress.
