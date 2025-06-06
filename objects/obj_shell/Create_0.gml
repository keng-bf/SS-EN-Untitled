// feather disable all
// feather ignore all
depth = -9999
isOpen = false;
isAutocompleteOpen = false;

shellSurface = noone;
scrollSurface = noone;
shellOriginX = 0;
shellOriginY = 0;
visibleWidth = 0;
visibleHeight = 0;

cursorPos = 1;
consoleString = "";
savedConsoleString = "";
scrollPosition = 0;
maxScrollPosition = 0;
targetScrollPosition = 0;
commandSubmitted = false; // Need to update scroll position one frame after a command is submitted
insertMode = true;

historyPos = 0;
history = [];
output = [];
outputHeight = 0;

filteredSuggestions = [];
inputArray = [];
suggestionIndex = 0;
autocompleteMaxWidth = 0;
autocompleteScrollPosition = 0;
autocompleteOriginX = 0;
autocompleteOriginY = 0;
mousePreviousX = get_mouse_x_screen(0);
mousePreviousY = get_mouse_y_screen(0);

shellPropertiesHash = "";

// for the bash-style "kill" copy/paste
killedString = "";
// whether we just performed a meta-action, as the keyboard_check_pressed for that key will still register on the next frame...
metaDeleted = false;
metaMovedLeft = false;
metaMovedRight = false;

// Set up queue for deferred script calls
deferredQueue = ds_queue_create();

// Variables for the saved history feature
savedHistoryFilePath = working_directory + "rt-shell-saved-history.data";
loadedSavedHistory = false;
loadedHistoryScrolled = false;

// Mouse-argument data types
enum mouseArgumentType {
	worldX,
	worldY,
	guiX,
	guiY,
	instanceId,
	objectId
}
activeMouseArgType = undefined;
activeMouseArgValue = "";

// Initialize native shell scripts
event_user(0);

// If another instance of rt-shell already exists, destroy ourself
// Must do after initializing surface and lists so our clean-up step succeeds
if (instance_number(object_index) > 1) {
	instance_destroy();
}

/// Opens the shell
function open() {
	isOpen = true;
	keyboard_string = "";
	if (!is_undefined(openFunction)) {
		openFunction();
	}
}

/// Closes the shell
function close() {
	isOpen = false;
	if (!is_undefined(closeFunction)) {
		closeFunction();
	}
	// Execute any deferred functions
	// This should happen after the close function, as the canonical use-case is for 
	// running scripts that must happen while the game is not paused
	while (!ds_queue_empty(deferredQueue)) {
		var args = ds_queue_dequeue(deferredQueue);
		self._execute_script(args, true);
	}
	// Save the current history to disk, if enabled
	if (saveHistory) {
		self._save_history();
	}
}

/// Closes autocomplete
function _close_autocomplete() {
	array_resize(filteredSuggestions, 0);
}

// Create a list of shell functions in the global namespace to
// filter for autocompletion
availableFunctions = [];
allFunctions = [];
functionData = {};
var global_variables = variable_instance_get_names(global);
// Fetch the metadata first so we can utilize it in the available function storage
for (var i = 0; i < array_length(global_variables); i++) {
	// Only looking for variables that start with meta_
	if (string_pos("meta_", string_lower(global_variables[i])) == 1) {
		// Strip off the meta_ when we store them in our data struct
		var name = string_delete(string_lower(global_variables[i]), 1, 5);
		functionData[$ name] = variable_instance_get(global, global_variables[i])();
	}
}
// Then fetch all the functions themselves
for (var i = 0; i < array_length(global_variables); i++) {
	// Only looking for variables that start with sh_
	if (string_pos("sh_", string_lower(global_variables[i])) == 1) {
		// Strip off the sh_ when we store them in our array
		var name = string_delete(string_lower(global_variables[i]), 1, 3);
		// #32 : don't display hidden functions in the autocomplete
		var hidden = false;
		var metadata = functionData[$ name];
		if (!is_undefined(metadata)) {
			if (variable_struct_exists(metadata, "hidden")) {
				hidden = metadata.hidden;
			}
		}
		if (!hidden) {
			array_push(availableFunctions, name);
		}
		array_push(allFunctions, name);
	}
	// Sort available functions list alphabetically for help command
	array_sort(availableFunctions, true);
}

// Update the list of functions prefixed by the user's current input
// for use in autocompletion
function _update_filtered_suggestions() {
	array_resize(filteredSuggestions, 0);
	autocompleteMaxWidth = 0;
	suggestionIndex = 0;
	activeMouseArgType = undefined;
	var input_string = string(consoleString);
	inputArray = self._input_string_split(input_string);
	
	// Return if we have nothing to parse
	if (string_length(input_string) <= 0 || array_length(inputArray) <= 0) { return; }
	
	// Set font for string_width calculation
	draw_set_font(consoleFont);
	
	// Parse through functions
	var space_count = array_length(inputArray) - 1;
	if (space_count == 0) {
		for (var i = 0; i < array_length(availableFunctions); i++) {
			if (string_pos(input_string, availableFunctions[i]) == 1 && input_string != availableFunctions[i]) {
				array_push(filteredSuggestions, availableFunctions[i]);
				autocompleteMaxWidth = max(autocompleteMaxWidth, string_width(availableFunctions[i]));
			}
		}
	} else {
		// Parse through argument suggestions
		var function_name = inputArray[0];
		var argument_index = space_count - 1;
		var data_exists = variable_struct_exists(functionData, function_name);
		var no_extra_space = (string_char_at(input_string, string_last_pos(" ", input_string) - 1) != " ");
		if (data_exists && no_extra_space && space_count <= array_length(inputArray)) {
			var suggestion_data = functionData[$ inputArray[0]][$ "suggestions"];
			var argument_suggestions = [];
			if (argument_index < array_length(suggestion_data)) {
				if (is_array(suggestion_data[argument_index])) {
					// Suggestion data is a static array
					argument_suggestions = suggestion_data[argument_index];
				} else if (is_method(suggestion_data[argument_index])) {
					// #18: Suggestion data is a dynamic function that returns an array
					argument_suggestions = suggestion_data[argument_index]();
				} else if (is_int64(suggestion_data[argument_index])) {
					// int64 is the datatype of enum values, we can hopefully assume this means
					// our argument suggestion is a mouseArgumentType
					activeMouseArgType = suggestion_data[argument_index];
				}
				var current_argument = inputArray[array_length(inputArray) - 1];
				for (var i = 0; i < array_length(argument_suggestions); i++) {
					var prefix_match = string_pos(current_argument, string_lower(argument_suggestions[i])) == 1;
					if (string_last_pos(" ", input_string) == string_length(input_string) || prefix_match) {
						array_push(filteredSuggestions, argument_suggestions[i]);
						autocompleteMaxWidth = max(autocompleteMaxWidth, string_width(argument_suggestions[i]));
					}
				}
			}
		}
	}
	autocompleteScrollPosition = 0;
	array_sort(filteredSuggestions, true);
}

// Find the prefix string that the list of suggestions has in common
// used to update the consoleString when user is tab-completing
function _find_common_prefix() {
	if (array_length(filteredSuggestions) <= 0) {
		return "";
	}
	
	var first = string(filteredSuggestions[0]);
	var last = string(filteredSuggestions[array_length(filteredSuggestions) - 1]);
		
	var result = "";
	var space_count = string_count(" ", consoleString);
	if (space_count > 0) {
		for (var i = 0; i < space_count; i++) {
			result += inputArray[i] + " ";
		}
	}
	// string_char_at is 1-indexed.... sigh
	for (var i = 1; i < string_length(first) + 1; i++) {
		if (string_char_at(first, i) == string_char_at(last, i)) {
			result += string_char_at(first, i);
		} else {
			break;
		}
	}
	
	return result;
}

function _key_combo_pressed(modifier_array, key) {
	for (var i = 0; i < array_length(modifier_array); i++) {
		if (!keyboard_check(modifier_array[i])) {
			return false;
		}
	}

	if (keyboard_check_pressed(key)) {
		if (array_length(modifier_array) == 0) {
			if (keyboard_check(vk_shift) || keyboard_check(vk_control) || keyboard_check(vk_alt)) {
				return false;
			}
		}
		
		return true;
	}
}

delayFrame = 0;
delayFrames = 1;
function _keyboard_check_delay(input) {
	if (keyboard_check_released(input)) {
		delayFrame = 0;
		delayFrames = 1;
		return false;
	} else if (!keyboard_check(input)) {
		return false;
	}
	delayFrame = (delayFrame + 1) % delayFrames;
	if (delayFrame == 0) {
		delayFrames = keyRepeatDelay;
	}
	if (keyboard_check_pressed(input)) {
		delayFrame = 0;
		delayFrames = keyRepeatInitialDelay;
		return true;
	} else {
		if (keyboard_check(input) && delayFrame == 0) {
			return true;
		}
	}
	return false;
}

// Calculates a hash of the configurable variables that would cause shell properties to 
// need recalculation if they changed
function _shell_properties_hash() {
	return md5_string_unicode(string(width) + "~" + string(height) + "~" + string(anchorMargin) 
			+ "~" + string(consolePaddingH) + "~" + string(scrollbarWidth) + "~" + 
			string(consolePaddingV) + "~" + string(screenAnchorPointH) + "~" + string(screenAnchorPointV));
}

// Recalculates origin, mainly for changing themes and intializing
function _recalculate_shell_properties() {
	var screen_center_x = display_get_gui_width() / 2;
	var screen_center_y = display_get_gui_height() / 2;
	draw_set_font(consoleFont);
	var em_height = string_height("M");
	
	// Clamp size of shell to available screen dimensions
	var max_width = display_get_gui_width() - (anchorMargin * 2);
	var max_height = display_get_gui_height() - (anchorMargin * 2);
	width = clamp(width, 50, max_width);
	height = clamp(height, em_height, max_height);
	
	var half_width = width / 2;
	var half_height = height / 2;
	switch (screenAnchorPointH) {
		case "left":
			shellOriginX = anchorMargin - 1;
			break;
		case "center":
			shellOriginX = screen_center_x - half_width - 1;
			break;
		case "right":
			shellOriginX = display_get_gui_width() - width - anchorMargin - 1;
			break;
	}
	
	switch (screenAnchorPointV) {
		case "top":
			shellOriginY = anchorMargin - 1;
			break;
		case "middle":
			shellOriginY = screen_center_y - half_height - 1;
			break;
		case "bottom":
			shellOriginY = display_get_gui_height() - height - anchorMargin - 1;
			break;
	}
	
	// Calculate the width of the visible text area, taking into account all margins
	visibleWidth = width - (2 * anchorMargin) - scrollbarWidth - (2 * consolePaddingH);
	visibleHeight = height - (2 * consolePaddingV);
	
	// Save a hash of the shell properties, so we can detect if we need to recalculate
	shellPropertiesHash = self._shell_properties_hash();
}

// Recalculates the scroll offset/position based on the suggestion index within the autocomplete list
function _calculate_scroll_from_suggestion_index() {
	if (suggestionIndex == 0)  {
		autocompleteScrollPosition = 0;
	} else {
		if (suggestionIndex >= autocompleteScrollPosition + autocompleteMaxLines) {
			autocompleteScrollPosition = max(0, suggestionIndex - autocompleteMaxLines + 1);
		} else if (suggestionIndex < autocompleteScrollPosition) {
			autocompleteScrollPosition = autocompleteScrollPosition - suggestionIndex;
		}
	}
}

function _confirm_current_suggestion() {
	var space_count = string_count(" ", consoleString);
	consoleString = "";
	for (var i = 0; i < space_count; i++) {
		consoleString += inputArray[i] + " ";
	}
	consoleString += filteredSuggestions[suggestionIndex] + " ";
	cursorPos = string_length(consoleString) + 1;
}

function _confirm_current_mouse_argument_data() {
	if (activeMouseArgValue != "") {
		consoleString += string(activeMouseArgValue) + " ";
		cursorPos = string_length(consoleString) + 1;
	}
}

function _execute_script(args, deferred = false) {
	var script = variable_global_get("sh_" + args[0]);
	if (!is_undefined(script)) {
		var response;
		try {
			response = script_execute(asset_get_index(script_get_name(script)), args);
		} catch (_exception) {
			response = "-- ERROR: see debug output for details --";
			show_debug_message("---- ERROR executing rt-shell command [" + args[0] + "] ----");
			show_debug_message(_exception.message);
			show_debug_message(_exception.longMessage);
			show_debug_message(_exception.script);
			show_debug_message(_exception.stacktrace);
			show_debug_message("----------------------------");
		}
		if (!deferred) {
			array_push(history, consoleString);
			if (response != "") { array_push(output, ">" + consoleString); }
		}
		if (is_string(response)) {
			array_push(output, response);
		}
		
		self._update_positions();
	} else {
		array_push(output, ">" + consoleString);
		array_push(output, "No such command: " + consoleString);
		array_push(history, consoleString);
		self._update_positions();
	}
}

function _update_positions() {
	historyPos = array_length(history);
	consoleString = "";
	savedConsoleString = "";
	cursorPos = 1;
}

function _save_history() {
	var truncated_history = [];
	var truncated_output = [];
	
	array_copy(truncated_history, 0, history, max(0, array_length(history) - savedHistoryMaxSize),
		min(array_length(history), savedHistoryMaxSize));
	
	array_copy(truncated_output, 0, output, max(0, array_length(output) - savedHistoryMaxSize), 
		min(array_length(output), savedHistoryMaxSize));

	var to_save = {
		history: truncated_history,
		output: truncated_output
	}
	var open_file = file_text_open_write(savedHistoryFilePath);
	file_text_write_string(open_file, json_stringify(to_save));
	file_text_close(open_file);
}

function _load_history() {
	var save_data_file = file_find_first(savedHistoryFilePath, fa_directory);
	if (save_data_file != "") {
		var open_file = file_text_open_read(savedHistoryFilePath);
		var temp_data = json_parse(file_text_read_string(open_file));
		file_text_close(open_file);
		history = temp_data.history;
		output = temp_data.output;
		historyPos = array_length(history);
	}
}

/// @function _input_string_split(_input)
/// @description Splits a console input string on spaces (handling quoted arguments)
/// @param _input The input string to split
/// @returns An array containing the function name followed by each argument
function _input_string_split(_input) {
	var slot = 0;
	var splits = []; //array to hold all splits
	var str2 = ""; //var to hold the current split we're working on building

	var in_quotes = false;
	
	for (var i = 1; i < (string_length(_input) + 1); i++) {
	    var curr_str = string_char_at(_input, i);
		// Ignore spaces as a delimiter if we are currently inside of quotes
		if (!in_quotes) {
			if (curr_str == "\"") {
				in_quotes = true;
				continue;
			}
		    if (curr_str == " ") {
				if (str2 != "") { // Make sure we don't include the space
			        splits[slot] = str2; //add this split to the array of all splits
			        slot++;
				}
		        str2 = "";
		    } else {
		        str2 = str2 + curr_str;
		        splits[slot] = str2;
		    }
		} else {
			if (curr_str == "\"") {
				in_quotes = false;
				splits[slot] = str2;
				continue;
			}
		    str2 = str2 + curr_str;
		}
	}
	// If we ended on our delimiter character, include an empty string as the final split
	// If we ended without closing a quote, include what's been written in quotes so far as a complete argument
	if (str2 == "" || in_quotes) {
		splits[slot] = str2;
	}

	return splits;
}

function _array_contains(array, value)
{
    var i;
    
    for (i = 0; i < array_length(array); i++)
    {
        if (array[i] == value)
            return true;
    }
    
    return false;
}

/// @param value
/// @param min_input
/// @param max_input
/// @param min_output
/// @param max_output
function _remap(value, min_input, max_input, min_output, max_output) {
	var _t = (value - min_input) / (max_input - min_input);
	return lerp(min_output, max_output, _t);
}

if os_type != os_windows
	instance_destroy()