# WorldWake Painter Prototype

This branch is a small Godot proof-of-concept for the future WorldWake world-authoring app. It intentionally tests only the foundation we care about before porting the full HTML Painter feature set.

## What this prototype tests

- Godot-native desktop UI shell
- the forked `procedural_world_map` renderer
- progressive rendering while panning/zooming
- a finite 1024 x 1024 WorldWake-style world
- terrain painting with continuous stroke interpolation
- brush radius control
- terrain override erasing
- mouse-centered wheel zoom
- right/middle-mouse panning
- frame-rate and painted-cell readout

The generated terrain is placeholder noise. It is **not** the WorldWake generator yet. Painted edits are also intentionally not saved yet.

## Run it

1. Check out the `worldwake-painter-prototype` branch.
2. Open this repository's `project.godot` in a standard (non-.NET is fine) Godot 4 editor.
3. Press **F5** / Run Project.

The project is configured to launch `res://worldwake_painter/painter.tscn` directly.

## Controls

- **Left drag:** paint terrain
- **Right or middle drag:** pan
- **Mouse wheel:** zoom around the cursor
- **Fit whole world:** reset the view
- **Clear painted edits:** remove all manual overrides

The map intentionally renders at very low resolution while it is actively moving or changing, then progressively sharpens after a short idle period. That is the behavior we are evaluating for Painter v3.

## Architecture note

The upstream renderer remains mostly intact. The only addon compatibility change on this branch is that `session_factory.gd` no longer preloads the optional C# datasource, allowing the prototype to run as a normal GDScript project.
