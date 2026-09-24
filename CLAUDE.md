# Quarto 3D

A 3D version of Quarto, in Godot 4.7 (Forward+). Two players share one set of
64 pieces on a 4x4x4 lattice.

**The rule that shapes everything:** you never choose your own piece. You place
whatever your opponent handed you, then you choose the piece they must place.
So the active player changes in the *middle* of a turn, not at the end, and the
opening move is a choice with nothing to place.

A piece has six binary properties - sphere/cube, black/white, big/small,
hollow/solid, spotted/plain, spinning/still - which gives exactly 64. A line of
four pieces agreeing on **any one** property wins. There are 76 such lines in a
4x4x4 grid: 48 along the axes, 24 in-plane diagonals, 4 space diagonals.

## Running Godot

Godot is **not vendored in this repo**. Find whatever the current machine has,
in this order:

1. `godot` or `godot4` on `PATH`.
2. A `GODOT` environment variable, if one is set.
3. A local install. On the author's Windows box it is at
   `C:\Users\leonb\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe`
   - note that the `.exe` there is a **directory**, with the real binary one
   level inside it.

If no Godot is available (a plain cloud container usually has none), say so
plainly and stick to static work - reading, editing, reasoning. Do not claim a
change is verified when nothing was run. Everything below assumes
`GODOT` points at the binary.

### Import before anything else

```bash
"$GODOT" --headless --path . --import
```

**Run this first on any fresh clone.** `.godot/` is ignored, so a new checkout
has no class cache, and every `class_name` type (`Board`, `GameState`,
`WinCheck`, ...) fails to resolve until it is built. `--quit` does *not*
populate it; only `--import` does. Skipping this produces a wall of
"Could not find type X" errors that look like broken code and are not.

### Running and verifying

```bash
"$GODOT" --path .                        # play it
"$GODOT" --path . --quit-after 180       # smoke test, expect exit 0, no SCRIPT ERROR
"$GODOT" --path . -s _check.gd           # run a harness (see below)
```

## Layout

```
project.godot          main scene is scenes/menu.tscn
scenes/
  menu.tscn            title screen, and an empty settings page
  main.tscn            game root: camera rig, board, HUD, piece panel
  board.tscn           bare Node3D, all geometry is built in code
  piece.tscn           Node3D + MeshInstance3D, driven by PieceView
  piece_panel.tscn     PanelContainer wrapping a SubViewport with its own world
scripts/               see below
shaders/piece.gdshader one shader, four materials, triplanar jittered spots
```

## Architecture

Rules and visuals are kept apart, and the dependency arrows only ever point one
way. The three `RefCounted` classes know nothing about nodes and can be
exercised headlessly with no scene at all.

```
board_lines.gd    BoardLines    the 76 lines. geometry only, no traits
piece_traits.gd   PieceTraits   the 6-bit encoding. no geometry
  win_check.gd    WinCheck      the two combined: which lines have won
  game_state.gd   GameState     whose turn, which phase, who won
board.gd          Board         storage + visuals for the lattice. no rules
piece_view.gd     PieceView     one piece: mesh, material, scale, spin
piece_assets.gd   PieceAssets   shared mesh/material caches (4 meshes, 4 mats)
piece_panel.gd    PiecePanel    the 64-slot HUD tray, and picking from it
orbit_camera.gd   OrbitCamera   orbit/pinch rig, emits tapped + hovered
main.gd           (no class)    the only script that knows about both sides
menu.gd           (no class)    title screen
```

`main.gd` is the controller and the only place board and panel meet. Board and
panel do not reference each other.

### Conventions worth keeping

**Derived, not maintained.** Anything that could be stored twice is instead
computed from the one place that owns it, and then *asserted*. Panel
availability is derived from `Board.placed_ids()`; the panel's selection during
the placing phase is derived from `GameState.held_id`. Both have an
`assert`-based invariant check in `main.gd` that runs on every change. Prefer
adding a derivation plus an assert over adding a second copy of a fact.

**Trait ids are a bitmask**, and the win check is a bitwise test - see
`PieceTraits.shared_property_names()`. The bit layout is fixed and the panel
layout depends on it.

**One vocabulary.** `PieceTraits.PROPERTY_NAMES` is the single table of
property words; `describe()` and the win banner both read it so they cannot
drift.

**Style.** Tabs for indent. `##` doc comments on anything non-obvious.
Comments explain *why*, not what - the existing ones are the model. Avoid
backslash line continuations in new code.

## Verifying changes

There is no test framework. The established method is a throwaway
`extends SceneTree` script at the repo root, run with `-s`, then deleted:

- instantiate the real scene with `load("res://scenes/main.tscn").instantiate()`
- drive the real handlers, or real input via `Input.parse_input_event()`
- press real buttons with `button.pressed.emit()`
- for visuals, `root.get_texture().get_image().save_png(path)` after
  `await RenderingServer.frame_post_draw`
- accumulate failures and print a count rather than aborting on the first

This has repeatedly caught things reasoning alone missed. **Delete the harness
when done** and leave the tree clean.

## Gotchas

**Touch input arrives twice.** `emulate_mouse_from_touch` is left ON (engine
default) because the piece panel and every HUD button only read mouse events -
turning it off makes the whole UI untouchable. The cost is that one finger
produces both a touch event and a synthesized mouse event, and `OrbitCamera`
handles both, so touch orbits at exactly 2.00x speed. The fix belongs in
`OrbitCamera`, ignoring mouse events whose `device` is
`InputEvent.DEVICE_ID_EMULATION`. **This is still outstanding.** See the
comment in `project.godot`.

**`.uid` and `.import` files are committed on purpose.** They carry stable
`uid://` values that the editor writes into scene files on save. See the note
in `.gitignore` before changing it.

**`SurfaceTool.deindex()` + `generate_normals()` does not give flat normals.**
It honours smoothing groups and re-averages coincident vertices. `PieceAssets`
computes per-triangle normals by hand, referencing the face *centroid* for
outward orientation (a single vertex is meaningless at a sphere pole, where
`SphereMesh` collapses its rings) and skipping degenerate slivers.

**Shell heredocs mangle GDScript** in this environment - apostrophes and
backslash continuations get eaten, producing files that will not parse. Write
`.gd` files with a file-writing tool, or via a Python script, not
`cat > file <<EOF`.
