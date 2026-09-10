extends Node # Creates the starter input map before gameplay scenes begin.

func _enter_tree() -> void: # Registers the project's named keyboard and gamepad actions.
    _ensure_axis_action(&"StickLeft_North", KEY_W, KEY_UP, JOY_AXIS_LEFT_Y, -1.0) # Maps forward movement to keyboard and left-stick input.
    _ensure_axis_action(&"StickLeft_South", KEY_S, KEY_DOWN, JOY_AXIS_LEFT_Y, 1.0) # Maps backward movement to keyboard and left-stick input.
    _ensure_axis_action(&"StickLeft_West", KEY_A, KEY_LEFT, JOY_AXIS_LEFT_X, -1.0) # Maps left movement to keyboard and left-stick input.
    _ensure_axis_action(&"StickLeft_East", KEY_D, KEY_RIGHT, JOY_AXIS_LEFT_X, 1.0) # Maps right movement to keyboard and left-stick input.
    _ensure_joy_axis_action(&"StickRight_North", JOY_AXIS_RIGHT_Y, -1.0) # Maps upward right-stick movement for camera control.
    _ensure_joy_axis_action(&"StickRight_South", JOY_AXIS_RIGHT_Y, 1.0) # Maps downward right-stick movement for camera control.
    _ensure_joy_axis_action(&"StickRight_West", JOY_AXIS_RIGHT_X, -1.0) # Maps leftward right-stick movement for camera control.
    _ensure_joy_axis_action(&"StickRight_East", JOY_AXIS_RIGHT_X, 1.0) # Maps rightward right-stick movement for camera control.
    _ensure_button_action(&"Button_A", KEY_SPACE, JOY_BUTTON_A) # Maps the primary action button for interactions.
    _ensure_button_action(&"Button_Start", KEY_ESCAPE, JOY_BUTTON_START) # Maps the start button for menu handling.
    _ensure_button_action(&"Button_LeftStick", KEY_SHIFT, JOY_BUTTON_LEFT_STICK) # Maps sprint to keyboard Shift and the left-stick click.

func _ensure_axis_action(action: StringName, primary_key: Key, alternate_key: Key, axis: JoyAxis, axis_value: float) -> void: # Adds one directional action only when the project does not already define it.
    if InputMap.has_action(action): # Preserves any action configuration the project already contains.
        return # Avoids replacing user-defined input settings.
    InputMap.add_action(action, 0.2) # Creates the named action with a controller-friendly deadzone.
    var primary_event: InputEventKey = InputEventKey.new() # Creates the primary keyboard binding.
    primary_event.physical_keycode = primary_key # Uses physical key placement so movement remains layout-consistent.
    InputMap.action_add_event(action, primary_event) # Adds the primary keyboard binding to the action.
    var alternate_event: InputEventKey = InputEventKey.new() # Creates the alternate keyboard binding.
    alternate_event.physical_keycode = alternate_key # Uses the matching arrow key as a secondary binding.
    InputMap.action_add_event(action, alternate_event) # Adds the alternate keyboard binding to the action.
    var axis_event: InputEventJoypadMotion = InputEventJoypadMotion.new() # Creates the matching gamepad-stick binding.
    axis_event.axis = axis # Selects the appropriate left-stick axis.
    axis_event.axis_value = axis_value # Selects the positive or negative side of the axis.
    InputMap.action_add_event(action, axis_event) # Adds the gamepad-stick binding to the action.

func _ensure_joy_axis_action(action: StringName, axis: JoyAxis, axis_value: float) -> void: # Adds one right-stick direction only when the project does not already define it.
    if InputMap.has_action(action): # Preserves any action configuration the project already contains.
        return # Avoids replacing user-defined input settings.
    InputMap.add_action(action, 0.2) # Creates the named analog action with a controller-friendly deadzone.
    var axis_event: InputEventJoypadMotion = InputEventJoypadMotion.new() # Creates the matching gamepad-stick binding.
    axis_event.axis = axis # Selects the appropriate right-stick axis.
    axis_event.axis_value = axis_value # Selects the positive or negative side of the axis.
    InputMap.action_add_event(action, axis_event) # Adds the gamepad-stick binding to the action.

func _ensure_button_action(action: StringName, keyboard_key: Key, joy_button: JoyButton) -> void: # Adds one digital action only when the project does not already define it.
    if InputMap.has_action(action): # Preserves any action configuration the project already contains.
        return # Avoids replacing user-defined input settings.
    InputMap.add_action(action) # Creates the named digital action.
    var key_event: InputEventKey = InputEventKey.new() # Creates the keyboard binding.
    key_event.physical_keycode = keyboard_key # Uses the requested physical keyboard key.
    InputMap.action_add_event(action, key_event) # Adds the keyboard binding to the action.
    var button_event: InputEventJoypadButton = InputEventJoypadButton.new() # Creates the controller-button binding.
    button_event.button_index = joy_button # Uses the matching gamepad button index.
    InputMap.action_add_event(action, button_event) # Adds the controller binding to the action.
