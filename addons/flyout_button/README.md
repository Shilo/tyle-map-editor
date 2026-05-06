# Flyout Button
Flyout Button is a reusable Godot 4 addon that provides a compact button control with a directional flyout menu. It is useful for editor toolbars and runtime UI where one visible button should expose several selectable actions. Items support custom textures, editor theme icons, tooltips, shortcuts, and Godot resources through `FlyoutButtonItem`.

## Using Flyout Button as a subtree dependency

Dependent Godot projects should keep these shared files at:

```text
addons/flyout_button
```

Git subtree is useful here because the dependent repo gets real committed files instead of a submodule pointer. That means the project still opens normally in Godot and does not require an extra clone step.

This repository's `main` branch is the addon payload. When a dependent project pulls it as a subtree, the repo root is placed directly into `addons/flyout_button`.

### Initialize the subtree

From the root of the repo that depends on Flyout Button:

```powershell
git subtree add --prefix=addons/flyout_button https://github.com/Shilo/flyout-button.git main --squash
```

This adds the shared Flyout Button files into `addons/flyout_button` and records enough subtree history for future updates.

### Update to the latest Flyout Button commit

From the dependent repo root:

```powershell
git subtree pull --prefix=addons/flyout_button https://github.com/Shilo/flyout-button.git main --squash
```

If Git reports conflicts, resolve them like a normal merge, then commit the result.

## VS Code task for updating without typing the CLI command

In any dependent repo, create `.vscode/tasks.json` with this task:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Update Flyout Button subtree",
      "type": "shell",
      "command": "git",
      "args": [
        "subtree",
        "pull",
        "--prefix=addons/flyout_button",
        "https://github.com/Shilo/flyout-button.git",
        "main",
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
3. Choose `Update Flyout Button subtree`.

Optional keyboard shortcut in VS Code `keybindings.json`:

```json
{
  "key": "ctrl+alt+u",
  "command": "workbench.action.tasks.runTask",
  "args": "Update Flyout Button subtree"
}
```

The task still runs Git under the hood, but you can trigger it from VS Code without retyping the subtree command.

## Rare: push subtree changes back to Flyout Button

Most Flyout Button changes should be made in this repo directly. If a dependent repo makes a useful fix inside `addons/flyout_button`, it can be pushed back with:

```powershell
git subtree push --prefix=addons/flyout_button https://github.com/Shilo/flyout-button.git main
```

Only use this when you intentionally want the dependent repo's `addons/flyout_button` changes to become the latest Flyout Button `main`.
