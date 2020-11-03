tool
extends EditorScript

func _run():
	print("Starting parser tests...")
	
	var test_dir = Directory.new()
	var parser = GDMLParser.new()
	
	var error = test_dir.change_dir("res://tests/parser")
	if (error != OK):
		printerr("Failed to open the tests directory, aborting...")
		return
	
	error = test_dir.list_dir_begin(true, true)
	if (error != OK):
		printerr("Failed to read the tests directory, aborting...")
		return
	
	print("")
	var file_name = test_dir.get_next()
	while (!file_name.empty()):
		var file_path = "res://tests/parser/" + file_name
		print("Running test file " + file_path)
		
		parser.open(file_path)
		var scene_tree = parser.get_scene_tree()
		if (!scene_tree == null):
			print("Root node is " + scene_tree.node_class + (" named " + scene_tree.node_name if scene_tree.node_class != scene_tree.node_name else ""))
			if (!scene_tree.attributes.empty()):
				print("Root node has the following attributes:")
				
				var attr_string = var2str(scene_tree.attributes)
				attr_string = attr_string.replace("\n", "")
				print(attr_string)
		parser.close()
		file_name = test_dir.get_next()
		print("-----")
		print("")
	
	print("")
	print("Finished parser tests.")
