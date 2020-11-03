tool
extends Reference
class_name GDMLParser

# TODO: Validate GDML files when opening
# TODO: Validate elements of the tree against available nodes

const CONTEXT_DOCUMENT : int = 0
const CONTEXT_TAG : int = 1
const CONTEXT_STRING : int = 2
const CONTEXT_ARRAY : int = 4
const CONTEXT_DICTIONARY : int = 8
const CONTEXT_LITERAL : int = 16

const TK_TAG_BEGIN : String = "<"
const TK_TAG_BEGIN_CLOSING : String = "</"
const TK_TAG_END : String = ">"
const TK_TAG_END_CLOSING : String = "/>"
const TK_TAG_CLOSING : String = "/"
const TK_TAG_NAME : String = ":"
const TK_ATTR_META : String = "@"
const TK_ATTR_VALUE : String = "="
const TK_STRING_DELIMITER : String = "\""
const TK_STRING_QUOTE_ESCAPED : String = "\\\""
const TK_ARRAY_BEGIN : String = "["
const TK_ARRAY_END : String = "]"
const TK_DICT_BEGIN : String = "{"
const TK_DICT_END : String = "}"
const TK_TYPE_LITERAL_BEGIN : String = "("
const TK_TYPE_LITERAL_END : String = ")"
const TK_EXTERNAL : String = "#"
const TK_EXTERNAL_REF : String = "&"

const TK_LF : String = "\n"
const TK_CR : String = "\r"
const TK_CRLF : String = "\r\n"

const TOKEN_PATTERNS : Dictionary = {
	CONTEXT_DOCUMENT: [
		TK_TAG_BEGIN_CLOSING,
		TK_TAG_BEGIN,
		TK_CRLF,
		TK_LF,
		TK_CR,
	],
	CONTEXT_TAG: [
		TK_TAG_END_CLOSING,
		TK_TAG_END,
		TK_TAG_NAME,
		TK_ATTR_META,
		TK_ATTR_VALUE,
		TK_STRING_DELIMITER,
		TK_ARRAY_BEGIN,
		TK_DICT_BEGIN,
		TK_CRLF,
		TK_LF,
		TK_CR,
	],
	CONTEXT_STRING: [
		TK_STRING_QUOTE_ESCAPED,
		TK_STRING_DELIMITER,
		TK_CRLF,
		TK_LF,
		TK_CR,
	],
	CONTEXT_ARRAY: [
		TK_ARRAY_BEGIN,
		TK_ARRAY_END,
		TK_STRING_DELIMITER,
		TK_CRLF,
		TK_LF,
		TK_CR,
	],
	CONTEXT_DICTIONARY: [
		TK_DICT_BEGIN,
		TK_DICT_END,
		TK_STRING_DELIMITER,
		TK_CRLF,
		TK_LF,
		TK_CR,
	],
	CONTEXT_LITERAL: [
		TK_TYPE_LITERAL_BEGIN,
		TK_TYPE_LITERAL_END,
		TK_STRING_DELIMITER,
		TK_CRLF,
		TK_LF,
		TK_CR,
	],
}

class GDExternalResource:
	var res_type : String = ""
	var res_name : String = ""
	var res_path : String = ""

class GDExternalReference:
	var res_name : String = ""

class GDTag:
	var node_class : String = "Node"
	var node_name : String = ""
	var attributes : Dictionary = {}
	var external : bool = false
	var parent : GDTag
	var children : Array = []

var _file : File
var _file_content : String
var _scene_tree : GDTag
var _external : Dictionary

var _cursor : int = 0
var _line_number : int = 1
var _char_number : int = 0
var _current_token : String = ""
var _current_tag : GDTag = null
var _context : int = CONTEXT_DOCUMENT

func _init() -> void:
	_file = null
	_file_content = ""
	_scene_tree = null
	_external = {}

func open(file_path : String) -> int:
	# Gracefully close a file if it exists
	close()
	
	_file = File.new()
	var error = _file.open(file_path, File.READ)
	if (error != OK):
		_file = null
		return error
	
	_parse()
	return OK

func close() -> void:
	_file_content = ""
	_scene_tree = null
	_external = {}
	
	if (_file != null):
		_file.close()
		_file = null

func get_scene_tree() -> GDTag:
	return _scene_tree

func get_external_resources() -> Dictionary:
	return _external

### Parser subroutines ###
func _parse() -> void:
	_scene_tree = null
	_external = {}
	
	# Document must have only one root node; this can be a recoverable error (just ignore any additional root nodes)
	# Tags must be either self-closing or have a closing counterpart
	# Tag and attribute names must be an alpha-numeric sequence, first character cannot be a number; additionally "_" (underscore) is supported, while " " (whitespace) is not supported
	# Tags without any prefix are mapped one to one to qualified Node-derived class names; custom names can be provided following ":" (colon)
	# Tags prefixed with "#" (hash) and "&" (ampersand) are used for external resources; in place of custom names they have identifiers that should be used for referencing
	# Attributes are mapped one to one to each Node's properties
	# Attributes starting with "@" (at) are mapped to the __meta__ properties 
	# Attribute values must be one of the following types: int, float, string, boolean, a reference to a resource or another dictionary type, an array or a dictionary of everything above
	# ^ See also TSCN serialization for all supported types and their string conversions
	
	_cursor = 0
	_line_number = 1
	_char_number = 0
	_current_tag = null
	_file_content = _file.get_as_text()
	
	var _parse_failed := false
	while (_cursor < _file_content.length()):
		# Find the next tag.
		var tag_found = _parse_document()
		# Found something invalid instead, aborting.
		if (!tag_found):
			_parse_failed = true
			break
		
		var tag_parsed = _parse_tag()
		if (!tag_parsed):
			_parse_failed = true
			break
	
	if (_scene_tree == null):
		printerr("Document is empty")

func _advance_line(by_number : int = 1) -> void:
	_line_number = _line_number + by_number
	_char_number = 0

func _advance_char(by_number : int = 1) -> void:
	_char_number = _char_number + by_number

func _print_error(message : String, at_line : int, at_char : int) -> void:
	printerr(message + " at line " + str(at_line) + ", position " + str(at_char))

func _is_whitespace(token : String) -> bool:
	var sanitized_token := token.strip_edges()
	return sanitized_token.empty()

func _is_newline(token : String) -> bool:
	return (token == TK_CRLF || token == TK_CR || token == TK_LF)

func _get_next_token() -> String:
	var next_token := ""
	
	# Try to find a complete token from a list for the current context.
	var pattern_list := []
	if (TOKEN_PATTERNS.has(_context)):
		pattern_list = TOKEN_PATTERNS[_context]
	
	# Token can be extended to multiple characters during matching.
	var matched_token := _file_content[_cursor]
	var matched := false
	# Iterate over the list of possible tokens, order is important.
	for pattern in pattern_list:
		# The pattern we are checking doesn't even begin with the correct character, skipping.
		if (!pattern.begins_with(matched_token)):
			continue
		
		# The pattern is one character long, so we can just trust the match at this point.
		if (pattern.length() == 1):
			next_token = matched_token
			matched = true
			break
		
		# The pattern is long and we need an appropriate substring to test it.
		matched_token = _file_content.substr(_cursor, pattern.length())
		if (matched_token == pattern):
			next_token = matched_token
			matched = true
			break
	
	if (!matched):
		next_token = _file_content[_cursor]
	
	_cursor = _cursor + next_token.length()
	if (_is_newline(next_token)):
		_advance_line()
	else:
		_advance_char(next_token.length())
	
	_current_token = next_token
	return next_token

# In Document context we look for tags.
func _parse_document() -> bool:
	var found_tag := false
	
	while (_cursor < _file_content.length()):
		_context = CONTEXT_DOCUMENT
		var next_token := _get_next_token()
		
		# Caught a newline or a whitespace-like character.
		if (_is_newline(next_token) || _is_whitespace(next_token)):
			continue
		# Found a tag.
		if (next_token == TK_TAG_BEGIN || next_token == TK_TAG_BEGIN_CLOSING):
			found_tag = true
			break
		
		_print_error("Unexpected token '" + next_token + "'", _line_number, _char_number - next_token.length())
		break
	
	return found_tag

# In Tag context we parse closing and opening tags including all attributes.
func _parse_tag() -> bool:
	# Check if we've entered a closing tag.
	if (_current_token == TK_TAG_BEGIN_CLOSING):
		return _parse_closing_tag()
	# Otherwise, we are attempting to parse an opening tag.
	else:
		return _parse_opening_tag()

func _parse_opening_tag() -> bool:
	var tag_name := ""
	var tag_parsed := false
	var tag_self_closing := false
	var tag_external := false
	var tag_external_ref := false
	var tag_start_position = _char_number
	
	var node_name := ""
	var parsing_node_name := false
	
	while (_cursor < _file_content.length()):
		_context = CONTEXT_TAG
		var next_token := _get_next_token()
		
		# Caught a newline or a whitespace-like character.
		if (_is_newline(next_token) || _is_whitespace(next_token)):
			break
		# Found the end of the tag.
		if (next_token == TK_TAG_END):
			tag_parsed = true
			break
		# Found the end of the self-closing tag.
		if (next_token == TK_TAG_END_CLOSING):
			tag_parsed = true
			tag_self_closing = true
			break
		# Found the special character for defining the node name.
		if (next_token == TK_TAG_NAME):
			parsing_node_name = true
			continue
		
		if (parsing_node_name):
			node_name = node_name + next_token
		else:
			tag_name = tag_name + next_token
	
	if (tag_name.begins_with(TK_EXTERNAL)):
		tag_external = true
		tag_name = tag_name.trim_prefix(TK_EXTERNAL)
	elif (tag_name.begins_with(TK_EXTERNAL_REF)):
		tag_external_ref = true
		tag_name = tag_name.trim_prefix(TK_EXTERNAL_REF)
		
		if (!_external.has(tag_name) || _external[tag_name].res_type != "PackedScene"):
			_print_error("External scene has an undefined identifier '" + tag_name + "'", _line_number, tag_start_position)
			return false
	
	if (!tag_name.is_valid_identifier()):
		_print_error("Opening tag has an invalid identifier '" + tag_name + "'", _line_number, tag_start_position)
		return false
	if (!node_name.empty() && !node_name.is_valid_identifier()):
		_print_error("Opening tag has an invalid node name '" + node_name + "'", _line_number, tag_start_position)
		return false
	
	if (tag_external):
		if (node_name.empty()):
			_print_error("External resource tag is missing an identifier", _line_number, tag_start_position + tag_name.length())
			return false
		if (_external.has(node_name)):
			_print_error("External resource tag has a duplicate identifier '" + node_name + "'", _line_number, tag_start_position + tag_name.length())
			return false
		
		var external_struct := GDExternalResource.new()
		external_struct.res_type = tag_name
		external_struct.res_name = node_name
		
		_external[node_name] = external_struct
		
		if (!tag_parsed):
			var attributes = _parse_attributes()
			if (attributes.has("path")):
				external_struct.res_path = attributes["path"]
			if (_current_token == TK_TAG_END_CLOSING): # Self-closing.
				tag_self_closing = true
		
		if (!tag_self_closing):
			_print_error("External resource tag is not self-closing; content will be ignored", _line_number, tag_start_position - 1)
			return false
		
	else:
		var tag_struct := GDTag.new()
		tag_struct.node_class = tag_name
		tag_struct.node_name = node_name if !node_name.empty() else tag_name
		tag_struct.parent = _current_tag
		
		if (tag_external_ref):
			tag_struct.external = true
		
		if (_scene_tree == null):
			_scene_tree = tag_struct
		elif (_current_tag != null):
			_current_tag.children.append(tag_struct)
		else:
			_print_error("Document has multiple root nodes; additional root node is ignored ", _line_number, tag_start_position - 1)
			return false
		
		if (!tag_parsed):
			tag_struct.attributes = _parse_attributes()
			if (_current_token == TK_TAG_END_CLOSING): # Self-closing.
				tag_self_closing = true
		
		if (!tag_self_closing):
			_current_tag = tag_struct
	
	return true

func _parse_closing_tag() -> bool:
	if (_current_tag == null):
		_print_error("Attempting to close a non-existent tag at root", _line_number, _char_number - _current_token.length())
		return false
	
	var tag_name := ""
	var tag_start_position = _char_number
	
	while (_cursor < _file_content.length()):
		_context = CONTEXT_TAG
		var next_token := _get_next_token()
		
		# Caught a newline.
		if (_is_newline(next_token)):
			_print_error("Unexpected newline token", _line_number, _char_number - next_token.length())
			break
		# Caught a whitespace-like character.
		if (_is_whitespace(next_token)):
			_print_error("Unexpected whitespace token", _line_number, _char_number - next_token.length())
			break
		# Found the end of the tag.
		if (next_token == TK_TAG_END):
			break
		
		tag_name = tag_name + next_token
	
	if (!tag_name.is_valid_identifier()):
		_print_error("Closing tag has an invalid identifier '" + tag_name + "'", _line_number, tag_start_position)
		return false
	
	if (_current_tag.node_class != tag_name):
		_print_error("Attempting to close a non-existent tag '" + tag_name + "'", _line_number, tag_start_position - _current_token.length())
		return false
	
	# The tag is closed, move one level up.
	_current_tag = _current_tag.parent
	return true

func _parse_attributes() -> Dictionary:
	var attributes := {}
	var attribute_name := ""
	var attribute_value = null
	
	while (_cursor < _file_content.length()):
		_context = CONTEXT_TAG
		var next_token := _get_next_token()
		
		# Caught a newline or a whitespace-like character.
		if (_is_newline(next_token) || _is_whitespace(next_token)):
			_collect_attribute(attributes, attribute_name, attribute_value)
			attribute_name = ""
			attribute_value = null
			continue
		# Found the end of the tag.
		if (next_token == TK_TAG_END || next_token == TK_TAG_END_CLOSING):
			break
		# Found a special character that delimits the attribute's value.
		if (next_token == TK_ATTR_VALUE):
			attribute_value = _parse_value()
			continue
		
		attribute_name = attribute_name + next_token
	
	if (!attribute_name.empty()):
		_collect_attribute(attributes, attribute_name, attribute_value)
	
	return attributes

func _collect_attribute(attributes : Dictionary, name : String, value) -> void:
	if (name.empty() || value == null):
		return
	
	if (name.begins_with(TK_ATTR_META)):
		var meta_name = name.trim_prefix(TK_ATTR_META)
		if (!meta_name.is_valid_identifier()):
			_print_error("Meta attribute has an invalid identifier '" + meta_name + "'", _line_number, _char_number - meta_name.length())
		
		if (!attributes.has("__meta__")):
			attributes["__meta__"] = {}
		attributes["__meta__"][meta_name] = value
	else:
		if (!name.is_valid_identifier()):
			_print_error("Attribute has an invalid identifier '" + name + "'", _line_number, _char_number - name.length())
		attributes[name] = value

func _parse_value(): # -> Variant
	var parsed_value = null
	# str2var is used for conversion to the actual Godot type.
	
	# Check if the value is a string, an array, or an dictionary by its starting character.
	var first_token := _get_next_token()
	# If so, parse it using a special method for each type.
	if (first_token == TK_STRING_DELIMITER):
		parsed_value = _parse_string()
	elif (first_token == TK_ARRAY_BEGIN):
		parsed_value = _parse_array()
	elif (first_token == TK_DICT_BEGIN):
		parsed_value = _parse_dictionary()
	# Check if the value is an external resource reference.
	elif (first_token == TK_EXTERNAL_REF):
		parsed_value = _parse_reference()
	# Otherwise, start collecting the literal value.
	else:
		parsed_value = _parse_literal()
	
	return parsed_value

func _parse_string() -> String:
	var parsed_string := ""
	
	while (_cursor < _file_content.length()):
		_context = CONTEXT_STRING
		var next_token := _get_next_token()
		
		# Caught a newline character.
		if (_is_newline(next_token)):
			_print_error("Unexpected newline token in a string literal", _line_number, _char_number)
			break
		# Found the end of the string.
		if (next_token == TK_STRING_DELIMITER):
			break
		
		parsed_string = parsed_string + next_token
		
	return parsed_string

func _parse_array() -> Array:
	var parsed_array := "" + _current_token
	var depth := 0
	
	while (_cursor < _file_content.length()):
		_context = CONTEXT_ARRAY
		var next_token := _get_next_token()
		
		# Found a string inside a literal.
		if (next_token == TK_STRING_DELIMITER):
			parsed_array = parsed_array + "\"" + _parse_string() + "\""
			continue
		# Found the end of the array.
		if (depth == 0 && next_token == TK_ARRAY_END):
			parsed_array = parsed_array + next_token
			break
		# Found the start of an inner array.
		if (next_token == TK_ARRAY_BEGIN):
			depth = depth + 1
		# Found the end of an inner array.
		if (depth > 0 && next_token == TK_ARRAY_END):
			depth = depth - 1
		
		parsed_array = parsed_array + next_token
		
	return str2var(parsed_array)

func _parse_dictionary() -> Dictionary:
	var parsed_dictionary := "" + _current_token
	var depth := 0
	
	while (_cursor < _file_content.length()):
		_context = CONTEXT_ARRAY
		var next_token := _get_next_token()
		
		# Found a string inside a literal.
		if (next_token == TK_STRING_DELIMITER):
			parsed_dictionary = parsed_dictionary + "\"" + _parse_string() + "\""
			continue
		# Found the end of the array.
		if (depth == 0 && next_token == TK_ARRAY_END):
			parsed_dictionary = parsed_dictionary + next_token
			break
		# Found the start of an inner dictionary.
		if (next_token == TK_DICT_BEGIN):
			depth = depth + 1
		# Found the end of an inner dictionary.
		if (depth > 0 && next_token == TK_DICT_END):
			depth = depth - 1
		
		parsed_dictionary = parsed_dictionary + next_token
		
	return str2var(parsed_dictionary)

func _parse_reference() -> GDExternalReference:
	var parsed_reference := ""
	var attribute_position := _char_number
	
	while (_cursor < _file_content.length()):
		_context = CONTEXT_LITERAL
		var next_token := _get_next_token()
		
		# Caught a newline or a whitespace-like character.
		if (_is_newline(next_token) || _is_whitespace(next_token)):
			break
		# Found the end of the tag.
		if (next_token == TK_TAG_END || next_token == TK_TAG_END_CLOSING):
			break
		
		parsed_reference = parsed_reference + next_token
	
	if (!parsed_reference.is_valid_identifier()):
		_print_error("External reference attribute has an invalid identifier '" + parsed_reference + "'", _line_number - 1, attribute_position)
		return null
	
	if (!_external.has(parsed_reference)):
		_print_error("External reference attribute has an undefined identifier '" + parsed_reference + "'", _line_number - 1, attribute_position)
		return null
	
	var ext_reference = GDExternalReference.new()
	ext_reference.res_name = parsed_reference
	
	return ext_reference

func _parse_literal(): # -> Variant
	# Here by literals we mean integers, floats, booleans, and serialized built-in types, such as Vector2.
	
	# TODO: Improve value validation
	# If the literal looks like an identifier instead, keep trying to parse until an opening parentheses is found.
	# If it is found, parse the rest of it until a closing parentheses is found.
	# If there is no opening parentheses, this is an invalid value.
	
	var parsed_literal := "" + _current_token
	var type_literal := false
	
	while (_cursor < _file_content.length()):
		_context = CONTEXT_LITERAL
		var next_token := _get_next_token()
		
		if (type_literal):
			# Found a string inside a literal.
			if (next_token == TK_STRING_DELIMITER):
				parsed_literal = parsed_literal + "\"" + _parse_string() + "\""
				continue
			# Found the end of the type literal.
			if (next_token == TK_TYPE_LITERAL_END):
				parsed_literal = parsed_literal + next_token
				break
		else:
			# Caught a newline or a whitespace-like character.
			if (_is_newline(next_token) || _is_whitespace(next_token)):
				break
			# Found the end of the tag.
			if (next_token == TK_TAG_END || next_token == TK_TAG_END_CLOSING):
				break
			# Found the start of the type literal (identifier excluded).
			if (next_token == TK_TYPE_LITERAL_BEGIN):
				type_literal = true
		
		parsed_literal = parsed_literal + next_token
	
	return str2var(parsed_literal)

### Scene builder methods & subroutines ###
func generate_scene() -> Node:
	if (_scene_tree == null):
		return null
	
	var root := _instance_node(_scene_tree)
	if (root == null):
		printerr("Failed to generate the root for the scene.")
		return null
	
	return root

func _instance_node(tag_struct : GDTag, parent : Node = null, root : Node = null) -> Node:
	var node : Node
	
	if (tag_struct.external):
		var external_ref = _external[tag_struct.node_class]
		var external_scene : PackedScene = load(external_ref.res_path)
		node = external_scene.instance()
	else:
		if (!ClassDB.can_instance(tag_struct.node_class)):
			printerr("The root node cannot be instanced by ClassDB.")
			return null
		node = ClassDB.instance(tag_struct.node_class)
	
	node.name = tag_struct.node_name
	
	if (tag_struct.attributes.has("script")):
		var attribute_value = tag_struct.attributes["script"]
		
		var external_value_ref = _external[attribute_value.res_name]
		var external_value = load(external_value_ref.res_path)
		attribute_value = external_value.new()
		
		node.set_script(external_value)
	
	for attribute_name in tag_struct.attributes:
		if (attribute_name == "script"):
			continue # Already handled.
		
		var attribute_value = tag_struct.attributes[attribute_name]
		if (attribute_value is GDExternalReference):
			var external_value_ref = _external[attribute_value.res_name]
			var external_value = load(external_value_ref.res_path)
			attribute_value = external_value.new()
		
		node.set(attribute_name, attribute_value)
	
	if (parent != null):
		parent.add_child(node)
	if (root != null):
		node.owner = root
	else:
		root = node
	
	for child_tag in tag_struct.children:
		_instance_node(child_tag, node, root)
	
	return node
