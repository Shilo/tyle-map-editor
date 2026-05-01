# EZ Tile Map Editor

A Godot 4.6 editor plugin that makes terrain painting on TileMapLayer nodes intuitive and easy - pick a terrain, pick a tool, and paint directly in the viewport. Replaces the less user-friendly native TileSet bottom panel workflow with a focused, always-visible toolbar and terrain grid.

## Features

- Paint terrains with **Draw**, **Line**, **Rectangle**, and **Bucket Fill** tools
- **Pick** terrain from existing cells (Ctrl+Click or Pick tool)
- **Erase** individual cells or erase entire layers
- **Right-click drag** to erase while painting
- Terrain management: **Add**, **Edit**, **Rename**, **Recolor**, **Reorder**, and **Remove** terrains right from the panel
- **Layer switcher** — select between visible TileMapLayer nodes in the scene
- **Layer highlight** and **grid visibility** toggles
- Full **undo/redo** support for all paint and terrain operations
- Canvas overlay preview while painting

## Installation

1. Copy `addons/ez_tile_map_editor/` into your Godot project's `addons/` folder
2. Enable the plugin at **Project > Project Settings > Plugins > EZ Tile Map Editor**

## Usage

1. Open the **EZ TileMap** bottom panel tab
2. Select a **TileMapLayer** node in the scene tree
3. Make sure your TileSet has **terrains defined** (use the built-in TileSet bottom panel to set up terrains and paint peering bits)
4. Choose a terrain from the grid and a paint tool from the toolbar
5. Paint directly on the 2D viewport

## Requirements

- Godot 4.6+
- TileSet with terrains and peering bits configured

## License

See the plugin's `plugin.cfg` for author and version info.
