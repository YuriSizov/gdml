tool
extends Reference
class_name GDMLParser

# TODO: Implement basic grammar for XML-like files
# TODO: Add support for JSX-like object attributes
# TODO: Validate GDML files when opening
# TODO: Validate elements of the tree against available nodes

const CONTEXT_DOCUMENT : int = 0
const CONTEXT_TAG : int = 1
const CONTEXT_STRING : int = 2
const CONTEXT_OBJECT : int = 4

const TK_TAG_BEGIN : String = "<"
const TK_TAG_BEGIN_CLOSING : String = "</"
const TK_TAG_END : String = ">"
const TK_TAG_END_CLOSING : String = "/>"
const TK_TAG_CLOSING : String = "/"
const TK_TAG_NAME : String = ":"
const TK_ATTR_META : String = "@"
const TK_ATTR_VALUE : String = "="

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
		TK_CRLF,
		TK_LF,
		TK_CR,
	],
	CONTEXT_STRING: [
		
	],
	CONTEXT_OBJECT: [
		
	],
}

var _file : File
var _file_content : String
var _scene_tree : Dictionary

var _cursor : int = 0
var _line_number : int = 1
var _char_number : int = 0
var _current_token : String = ""
var _current_tag : Dictionary = {}
var _context : int = CONTEXT_DOCUMENT

func _init() -> void:
	_file = null
	_file_content = ""
	_scene_tree = {}

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
	_scene_tree = {}
	
	if (_file != null):
		_file.close()
		_file = null

func get_scene_tree() -> Dictionary:
	return _scene_tree

func _parse() -> void:
	_scene_tree = {}
	
	# TODO: Implement a state machine parser
	# TODO: Parser must support contexts to be able to parse strings without breaking the document and to support dictionaries and arrays as values
	# 
	# Document must have only one root node; this can be a recoverable error (just ignore any additional root nodes)
	# Tags must be either self-closing or have a closing counterpart
	# Tag and attribute names must be an alpha-numeric sequence, first character cannot be a number; additionally "_" (underscore) is supported, while " " (whitespace) is not supported
	# Tags are mapped one to one to qualified Node-derived class names; tags starting with "#" (hash) are used for special cases, like instanced children
	# ^ User-defined node names are stored in a "name" attribute instead (TODO: Change to something that won't conflict, maybe use a special character)
	# Attributes are mapped one to one to each Node's properties; attributes starting with "@" (at) are mapped to the __meta__ properties 
	# ^ Other special characters may be introduced in future
	# Attribute values must be one of the following types: int, float, string, boolean, a reference to a resource or another object type, an array or a dictionary of everything above
	# ^ See also TSCN serialization for all supported types and their string conversions
	
	_cursor = 0
	_line_number = 1
	_char_number = 0
	_current_tag = {}
	_file_content = _file.get_as_text()
	
	var _found_root := false
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
	
	if (_scene_tree.empty()):
		printerr("Document is empty")

func _advance_line(by_number : int = 1) -> void:
	_line_number = _line_number + by_number
	_char_number = 0

func _advance_char(by_number : int = 1) -> void:
	_char_number = _char_number + by_number

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

func _get_current_token() -> String:
	return _current_token

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
		
		printerr("Unexpected token '" + next_token + "' at line " + str(_line_number) + ", position " + str(_char_number - next_token.length()))
		break
	
	return found_tag

# In Tag context we parse closing and opening tags including all attributes.
func _parse_tag() -> bool:
	var current_token := _get_current_token()
	
	# Check if we've entered a closing tag.
	if (current_token == TK_TAG_BEGIN_CLOSING):
		if (_current_tag.empty()):
			printerr("Attempting to close a non-existent tag at root at line " + str(_line_number) + ", position " + str(_char_number - current_token.length()))
			return false
		
		var tag_name := ""
		var tag_start_number = _char_number
		
		while (_cursor < _file_content.length()):
			_context = CONTEXT_TAG
			var next_token := _get_next_token()
			
			# Caught a newline.
			if (_is_newline(next_token)):
				printerr("Unexpected newline token at line " + str(_line_number) + ", position " + str(_char_number - next_token.length()))
				break
			# Caught a whitespace-like character.
			if (_is_whitespace(next_token)):
				printerr("Unexpected whitespace token at line " + str(_line_number) + ", position " + str(_char_number - next_token.length()))
				break
			# Found the end of the tag.
			if (next_token == TK_TAG_END):
				break
			
			tag_name = tag_name + next_token
		
		if (!tag_name.is_valid_identifier()):
			printerr("Closing tag has an invalid identifier '" + tag_name + "' at line " + str(_line_number) + ", position " + str(tag_start_number))
			return false
		
		if (_current_tag.node_class != tag_name):
			printerr("Attempting to close a non-existent tag '" + tag_name + "' at line " + str(_line_number) + ", position " + str(tag_start_number - current_token.length()))
			return false
		
		# The tag is closed, move one level up.
		_current_tag = _current_tag.parent
		return true
	
	# We are attempting to parse an opening tag.
	else:
		var tag_name := ""
		var tag_parsed := false
		var tag_self_closing := false
		var tag_start_number = _char_number
		
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
		
		if (!tag_name.is_valid_identifier()):
			printerr("Opening tag has an invalid identifier '" + tag_name + "' at line " + str(_line_number) + ", position " + str(tag_start_number))
			return false
		if (!node_name.empty() && !node_name.is_valid_identifier()):
			printerr("Opening tag has an invalid node name '" + node_name + "' at line " + str(_line_number) + ", position " + str(tag_start_number))
			return false
		
		var tag_struct := {
			"node_class": tag_name,
			"node_name": node_name if !node_name.empty() else tag_name,
			"attributes": {},
			"parent": _current_tag,
			"children": [],
		}
		
		if (_scene_tree.empty()):
			_scene_tree = tag_struct
		elif (!_current_tag.empty()):
			_current_tag.children.append(tag_struct)
		else:
			printerr("Document has multiple root nodes; only the first one is used, the rest are ignored.")
			return false
		
		if (!tag_self_closing):
			_current_tag = tag_struct
		if (!tag_parsed):
			_parse_attributes()
		return true
	
	return false

func _parse_attributes() -> bool:
	var tag_self_closing := false
	var attribute_name := ""
	var attribute_value := "" # Raw value is parsed to a string.
	var parsing_value := false
	
	while (_cursor < _file_content.length()):
		_context = CONTEXT_TAG
		var next_token := _get_next_token()
		
		# Caught a newline or a whitespace-like character.
		if (_is_newline(next_token) || _is_whitespace(next_token)):
			_collect_attribute(attribute_name, attribute_value)
			attribute_name = ""
			attribute_value = ""
			parsing_value = false
			continue
		# Found the end of the tag.
		if (next_token == TK_TAG_END):
			break
		# Found the end of the self-closing tag.
		if (next_token == TK_TAG_END_CLOSING):
			tag_self_closing = true
			break
		# Found a special character that delimits the attribute's value.
		if (next_token == TK_ATTR_VALUE):
			parsing_value = true
			continue
		
		if (parsing_value):
			attribute_value = attribute_value + next_token
		else:
			attribute_name = attribute_name + next_token
	
	if (!attribute_name.empty()):
		_collect_attribute(attribute_name, attribute_value)
	
	if (tag_self_closing):
		_current_tag = _current_tag.parent
	
	return true

func _collect_attribute(name : String, value : String) -> bool:
	if (_current_tag.empty()):
		return false
	if (name.empty() || value.empty()):
		return false
	
	# TODO: Parse values into appropriate Godot types
	# TODO: Parse strings
	# TODO: Parse objects
	
	if (name.begins_with(TK_ATTR_META)):
		var meta_name = name.trim_prefix(TK_ATTR_META)
		if (!meta_name.is_valid_identifier()):
			printerr("Meta attribute has an invalid identifier '" + meta_name + "' at line " + str(_line_number) + ", position " + str(_char_number - meta_name.length()))
		
		if (!_current_tag.attributes.has("__meta__")):
			_current_tag.attributes["__meta__"] = {}
		_current_tag.attributes["__meta__"][meta_name] = value
	else:
		if (!name.is_valid_identifier()):
			printerr("Attribute has an invalid identifier '" + name + "' at line " + str(_line_number) + ", position " + str(_char_number - name.length()))
		_current_tag.attributes[name] = value
	
	return true

# In String context we parse string literals.
func _parse_string() -> bool:
	var next_token := _get_next_token()
	return false

# In Object context we parse object literals.
func _parse_object() -> bool:
	var next_token := _get_next_token()
	return false
