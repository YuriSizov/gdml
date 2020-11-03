tool
extends EditorScript

func _run() -> void:
	print("Starting Demo generation...")

	var parser = GDMLParser.new()
	parser.open("res://tests/Demo.gdml")
	var demo_scene = parser.generate_scene()
	parser.close()
	
	if (demo_scene == null):
		printerr("Failed to generate the scene from the GDML file.")
		return
	
	var packed_resource = PackedScene.new()
	var error = packed_resource.pack(demo_scene)
	if (error != OK):
		printerr("Failed to pack the generated demo scene.")
		return
	
	var directory = Directory.new()
	if (directory.file_exists("res://tests/Demo.gen.tscn")):
		error = directory.remove("res://tests/Demo.gen.tscn")
		if (error != OK):
			printerr("Failed to delete the previous generated result.")
			return
	
	error = ResourceSaver.save("res://tests/Demo.gen.tscn", packed_resource)
	if (error != OK):
		printerr("Failed to save the packed scene resource.")
		return
	
	print("Finished Demo generation.")
