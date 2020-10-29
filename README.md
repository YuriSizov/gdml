# GDML, Godot Markup Language
**GDML** is an XML-like markup language that can be used to describe Godot scenes in a more traditional human-readable way than `.tscn` files provided by the engine.

## Features
This plugin aims to be a complete replacement for `.tscn` files allowing users to edit text representation of scenes with the same ease as they might edit HTML templates or JSX components. It features:

- Importing and exporting scenes from and into a new `.gdml` format.
- Built-in editor for scenes with syntax highlighting and code completion.
- Validation based on the same rules as the Scene Dock warnings.

## TODO
- [ ] Implement a GDML parser/builder using GDScript for a PoC.
- [ ] Re-implement a GDML parser/builder using GDNative for performance.
- [ ] Introduce a way to view scenes as a well-formed GDML document.
- [ ] Implement exporting scenes to `.gdml` files.
- [ ] Implement importing scenes from `.gdml` files without validation.
- [ ] Implement a generalized way to validate GDML documents against available nodes.
- [ ] Implement a `TextEdit` based GDML editor with basic highlighting.
- [ ] Implement code completion for the GDML editor.
