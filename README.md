# <img src="icon.png" width="32" alt="Tyle Map Editor Icon"> Tyle Map Editor

> **Y not map faster?**

A Godot 4.6 editor plugin that makes **terrain painting** on `TileMapLayer` nodes intuitive and fast — pick a terrain, choose a tool, and paint directly in the 2D viewport. Replaces the less user-friendly native TileSet bottom panel workflow with a focused, always-visible toolbar and terrain grid.

<img src="logo.png" width="188" alt="Tyle Map Editor Logo">

> **Important:** This plugin works exclusively with **terrains** (terrain sets defined in your TileSet with configured peering bits). It is not a raw tile painter — if you need to place individual tiles, use the native Godot TileMap editor instead.

---

## Maintainer: create the addon split branch

The public subtree branch is always named `addon`. After changing files under `addons/tyle_map_editor` on `main`, refresh and push the split branch from the Tyle Map Editor repo root:

```powershell
git subtree split --prefix=addons/tyle_map_editor main --branch addon
git push origin addon
```

The `addon` branch contains only the files that belong inside a dependent project's `addons/tyle_map_editor` directory.

The `.github/workflows/sync-addon-branch.yml` workflow runs this split automatically whenever `main` receives changes under `addons/tyle_map_editor`. Use the manual commands above when creating the branch for the first time, repairing it, or refreshing it outside GitHub Actions.

## Using Tyle Map Editor as a subtree dependency

Dependent Godot projects should keep these shared files at:

```text
addons/tyle_map_editor
```

Git subtree is useful here because the dependent repo gets real committed files instead of a submodule pointer. That means the project still opens normally in Godot and does not require an extra clone step.

This repository is a full Godot demo project. The reusable addon files live in `addons/tyle_map_editor`, so subtree consumers should use the generated `addon` split branch.

### Initialize the subtree

From the root of the repo that depends on Tyle Map Editor:

```powershell
git subtree add --prefix=addons/tyle_map_editor https://github.com/Shilo/tyle-map-editor.git addon --squash
```

This adds the shared Tyle Map Editor files into `addons/tyle_map_editor` and records enough subtree history for future updates.

### Update to the latest Tyle Map Editor commit

From the dependent repo root:

```powershell
git subtree pull --prefix=addons/tyle_map_editor https://github.com/Shilo/tyle-map-editor.git addon --squash
```

If Git reports conflicts, resolve them like a normal merge, then commit the result.

## VS Code task for updating without typing the CLI command

In any dependent repo, create `.vscode/tasks.json` with this task:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Update Tyle Map Editor subtree",
      "type": "shell",
      "command": "git",
      "args": [
        "subtree",
        "pull",
        "--prefix=addons/tyle_map_editor",
        "https://github.com/Shilo/tyle-map-editor.git",
        "addon",
        "--squash"
      ],
      "problemMatcher": []
    }
  ]
}
```

Then run it from VS Code:

1. Open the Command Palette with `Ctrl+Shift+P`.
2. Choose `Tasks: Run Task`.
3. Choose `Update Tyle Map Editor subtree`.

Optional keyboard shortcut in VS Code `keybindings.json`:

```json
{
  "key": "ctrl+alt+u",
  "command": "workbench.action.tasks.runTask",
  "args": "Update Tyle Map Editor subtree"
}
```

The task still runs Git under the hood, but you can trigger it from VS Code without retyping the subtree command.

## Features

### Paint Tools

| Tool            | Shortcut | Description                                                                                                                      |
| --------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------- |
| **Draw**        | `D`      | Freehand brush with continuous stroke support                                                                                    |
| **Line**        | `L`      | Straight lines using Bresenham and tileset-aware algorithms                                                                      |
| **Rectangle**   | `R`      | Fill a rectangular region with the selected terrain                                                                              |
| **Bucket Fill** | `B`      | Flood fill contiguous areas (BFS-based)                                                                                          |
| **Pick**        | `P`      | Sample a terrain from an existing cell to select it                                                                              |
| **Erase**       | `E`      | Remove individual cells from the current layer                                                                                   |
| **Select**      | `S`      | Rectangle-select cells; `Shift` to add (discontiguous), `Ctrl` to subtract; click selection to move; cut/copy/paste (Ctrl+X/C/V) |

All tools support **undo/redo** with per-stroke merging, so a continuous drag is a single undo step.

### Selection Tool

The Select tool (`S`) supports a full selection workflow:

- **Rectangle-select** — click and drag to select all painted cells in a region
- **Discontiguous selection** — hold `Shift` while drag-selecting to add more cells to an existing selection, even in non-adjacent regions
- **Subtraction** — hold `Ctrl` (or `Cmd` on macOS) while drag-selecting to remove cells from the current selection
- **Move selection** — click on an existing selection (without modifiers) and drag to reposition tiles (with undo)
- **Selection undo/redo** — every selection modification (add, subtract, or clear) is recorded as its own undo step
- Selection outline uses cell-aware borders (only outer edges are highlighted)

### Cut, Copy & Paste

| Action    | Shortcut | Description                                                              |
| --------- | -------- | ------------------------------------------------------------------------ |
| **Copy**  | `Ctrl+C` | Copy selected cells to clipboard                                         |
| **Cut**   | `Ctrl+X` | Copy and remove selected cells                                           |
| **Paste** | `Ctrl+V` | Enter paste mode with live preview; left-click to place, `Esc` to cancel |

Paste mode shows a translucent preview of the clipboard tiles under the cursor. Click **left** or **right mouse button** to place them.

### Right-Click Erase

Hold the right mouse button and drag to erase cells while using any paint tool — no need to switch tools mid-edit.

### Quick Pick

**Ctrl+Click** any painted cell in the viewport to instantly pick that cell's terrain. Picking a terrain from the grid while not in a paint tool auto-switches to the Draw tool.

### Erase All

Remove every used cell from the current layer in one click, with full undo support.

### Terrain Grid

A scrollable grid of terrain previews — each shows a tile icon from the atlas, the terrain name, and a selection highlight. Click to select a terrain, then paint. The grid auto-refreshes whenever you modify terrains via the native TileSet bottom panel.

### Layer Switcher

A dropdown in the toolbar lists all visible `TileMapLayer` nodes in the scene. Switch layers without leaving the viewport or hunting through the scene tree.

### Layer Highlight & Grid Toggles

- **Layer Highlight** — highlights the selected layer for visual clarity
- **Grid** — toggles the tile grid overlay

Both settings stay in sync with the native Godot TileMap editor.

### Canvas Overlay

A real-time preview is drawn over the 2D viewport while editing:

- **Brush preview** — colored polygon under the cursor while painting
- **Flood fill highlight** — cell outline showing the fill target
- **Selection outline** — cell-aware border around selected cells
- **Move preview** — translucent tile preview showing where the selection will land
- **Paste preview** — textured or colored preview of clipboard tiles before placing

### Custom Grid Rendering

- Viewport culling — only draws grid cells visible on screen
- Scale fading — grid fades out when cells drop below 5px to avoid visual noise
- Performance clamping — caps grid drawing at 100×100 cells
- Edge fade-out — smooth fade on irregular layer edges

---

## Installation

1. Copy the `addons/tyle_map_editor/` folder into your Godot project's `addons/` directory
2. Open your project in the Godot editor
3. Go to **Project → Project Settings → Plugins**
4. Find **Tyle Map Editor** and check **Enable**

The plugin adds a **Tyle** tab to the bottom panel.

---

## Quick Start

### Prerequisites

Your `TileSet` must have:

- At least one **terrain set** defined
- **Peering bits** configured for each tile (so Godot knows which tile to use at terrain boundaries)

> If you're new to Godot terrains, see the official docs: [Using terrains in the TileSet editor](https://docs.godotengine.org/en/stable/tutorials/2d/using_tilemaps.html#creating-terrain-sets)

### Painting Workflow

1. Open the **TileSet** bottom panel and configure your terrain sets with peering bits
2. Click the **Tyle** tab in the bottom panel
3. Select a `TileMapLayer` node in the scene tree (or use the layer dropdown in the toolbar)
4. Click a terrain icon from the terrain grid to select it
5. Choose a paint tool — press `D` for Draw, or click a tool button
6. Click and drag in the 2D viewport to paint

### Example: Grass & Stone Path

1. Create a `TileMapLayer` node and assign a `TileSet` with two terrains: **Grass** and **Stone**
2. Paint the entire layer with Grass (use `B` for Bucket Fill to fill quickly)
3. Select the **Stone** terrain from the grid
4. Press `D` and paint stone paths across the grass — tiles auto-transition along terrain boundaries based on your peering bits

---

## Tips

- **Ctrl+Click** any cell to quick-pick its terrain without switching to the Pick tool
- **Right-click + drag** to erase cells without switching to Erase mode
- Use the **layer dropdown** (right side of the toolbar) to jump between TileMapLayer nodes
- Toggle **Grid** to see cell boundaries while painting
- The terrain grid updates automatically when you modify terrains in the native TileSet panel
- For large areas, start with **Bucket Fill** (`B`) then refine edges with **Draw** (`D`)
- **Select** (`S`) a region, then **Cut/Copy/Paste** (Ctrl+X/C/V) to duplicate or rearrange terrain sections
- **Shift + drag-select** to add to an existing selection (discontiguous); **Ctrl + drag-select** to subtract from it
- **Click a pasted selection** and drag to move it before committing (useful for fine-tuning placement)
- Press **Esc** to cancel paste mode if you change your mind

---

## Troubleshooting

| Issue                                     | Solution                                                                                                                                  |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| **"No terrain sets defined"**             | Open the native **TileSet** bottom panel, select your TileSet, go to the **Terrains** tab, and add at least one terrain to a terrain set. |
| **Tiles don't appear when painting**      | Your tiles are missing peering bits. In the native TileSet panel, select each tile and configure its terrain assignment and peering bits. |
| **Wrong tile appears at terrain borders** | Ensure all peering bit combinations are covered by tiles in your atlas. Missing combinations fall back to a default tile.                 |
| **Can I paint individual tiles?**         | No. This plugin only works with terrains. For raw tile placement, use the native Godot TileMap editor.                                    |
| **Blank/empty terrain icons**             | The tile you used to set up the terrain may not have a visible texture. Pick a tile with a clear visual for that terrain.                 |

---

## Customizing Shortcuts

The plugin registers input actions in Godot's Input Map. To change key bindings:

1. Go to **Project → Project Settings → Input Map**
2. Search for `tyle_` to find all plugin tool shortcuts
3. Click an action and assign a new key

> Clipboard shortcuts (`Ctrl+C`, `Ctrl+X`, `Ctrl+V`) and `Esc` to cancel paste are hardcoded editor shortcuts and cannot be changed via the Input Map.

---

## Requirements

- **Godot 4.6 or later**
- `TileSet` resource with **terrain sets** and **peering bits** configured
- Works with `TileMapLayer` nodes (not the legacy `TileMap` node)

---

## License

This project is provided as-is. See `addons/tyle_map_editor/plugin.cfg` for author and version info.

---

**Created by Shilo · Version 1.0**
