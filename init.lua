--- === PaperWM.spoon ===
---
--- Tile windows horizontally. Inspired by PaperWM Gnome extension.
---
--- # System Architecture Overview
---
--- PaperWM implements a column-based tiling window manager for macOS. The system is built 
--- with several interconnected components that work together:
---
--- 1. Window Tracking System:
---    - Maintains a 3D array structure of windows (space -> column -> row)
---    - Tracks window positions, dimensions, and relationships
---    - Handles adding/removing windows from management
---
--- 2. Layout Engine:
---    - Arranges windows in columns with configurable gaps
---    - Ensures proper sizing of windows to fill vertical space
---    - Handles special cases like center window, full width, etc.
---
--- 3. Space Management:
---    - Integrates with macOS Mission Control spaces
---    - Supports moving windows between spaces
---    - Preserves layouts when switching between spaces
---
--- 4. Event Management:
---    - Watches for window creation, destruction, focus, and size changes
---    - Maintains consistency of window layouts when events occur
---    - Handles swipe gestures for scrolling windows
---
--- 5. State Persistence:
---    - Saves floating window status between sessions
---    - Restores window arrangements when spaces are revisited
---
--- # Usage
---
--- `PaperWM:start()` will begin automatically tiling new and existing windows.
--- `PaperWM:stop()` will release control over windows.
---
--- Set window gaps using `PaperWM.window_gap`:
--- - As a single number: same gap for all sides
--- - As a table with specific sides: `{top=8, bottom=8, left=8, right=8}`
---
--- For example:
--- ```
--- PaperWM.window_gap = 10  -- 10px gap on all sides
--- -- or
--- PaperWM.window_gap = {top=10, bottom=8, left=12, right=12}
--- ```
---
--- Overwrite `PaperWM.window_filter` to ignore specific applications. For example:
---
--- ```
--- PaperWM.window_filter = PaperWM.window_filter:setAppFilter("Finder", false)
--- PaperWM:start() -- restart for new window filter to take effect
--- ```
---
--- # Limitations
---
--- MacOS does not allow a window to be moved fully off-screen. Windows that would
--- be tiled off-screen are placed in a margin on the left and right edge of the
--- screen. They are still visible and clickable.
---
--- It's difficult to detect when a window is dragged from one space or screen to
--- another. Use the move_window_N commands to move windows between spaces and
--- screens.
---
--- Arrange screens vertically to prevent windows from bleeding into other screens.
---
---
--- Download: [https://github.com/mogenson/PaperWM.spoon](https://github.com/mogenson/PaperWM.spoon)

package.cpath = package.cpath .. ";/Users/phischi/.vscode/extensions/tangzx.emmylua-0.9.18-darwin-arm64/debugger/emmy/mac/arm64/emmy_core.dylib"
local dbg = require("emmy_core")
dbg.tcpListen("localhost", 9966)
-- stupid workaround to undefined global hs
_hs = hs
hs = _hs

-- Self-determine the spoon's path for reliable module loading
local obj = {}
obj.__index = obj

-- Extract the module path from the running script path
local function getSpoonPath()
    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*/)")
end

-- Set up the package path for module loading
local spoonPath = getSpoonPath()
package.path = spoonPath .. "?.lua;" .. package.path

-- Load external modules from external/ directory
local MissionControl = dofile(hs.spoons.resourcePath("external/mission_control.lua"))
local Swipe = dofile(hs.spoons.resourcePath("external/swipe.lua"))


local config = require("modules.config")
local utils = require("modules.utils")
local window_manager = require("modules.window_manager")
local layout_engine = require("modules.layout_engine")
local space_manager = require("modules.space_manager")
local event_handler = require("modules.event_handler")
local action_manager = require("modules.action_manager")

-- Main module definition
local PaperWM = {}
PaperWM.__index = PaperWM

-- Metadata
PaperWM.name = "PaperWM"
PaperWM.version = "0.7"
PaperWM.author = "Michael Mogenson"
PaperWM.homepage = "https://github.com/mogenson/PaperWM.spoon"
PaperWM.license = "MIT - https://opensource.org/licenses/MIT"

-- Import configuration from config module
PaperWM.default_hotkeys = config.default_hotkeys
PaperWM.window_filter = config.window_filter
PaperWM.window_gap = config.window_gap
PaperWM.window_ratios = config.window_ratios
PaperWM.screen_margin = config.screen_margin
PaperWM.swipe_fingers = config.swipe_fingers
PaperWM.swipe_gain = config.swipe_gain
PaperWM.Direction = config.Direction
PaperWM.IsFloatingKey = config.IsFloatingKey

-- Set up logger
PaperWM.logger = hs.logger.new(PaperWM.name)
PaperWM.logger.setLogLevel("debug")
MissionControl.log = PaperWM.logger

-- Initialize core module components immediately
window_manager.init(PaperWM, MissionControl)
layout_engine.init(PaperWM, window_manager)
space_manager.init(PaperWM, MissionControl, window_manager, layout_engine)
event_handler.init(PaperWM, window_manager)
action_manager.init(PaperWM, {
    window_manager = window_manager,
    layout_engine = layout_engine,
    space_manager = space_manager,
    mission_control = MissionControl
})

-- Initialize modules
function PaperWM:start()
    -- Check for required system settings
    if not hs.spaces.screensHaveSeparateSpaces() then
        self.logger.e(
            "please check 'Displays have separate Spaces' in System Preferences -> Mission Control")
    end
    
    -- Start swipe handler if enabled
    if self.swipe_fingers > 1 then
        self.logger.d("starting swipe handler")
        Swipe:start(self.swipe_fingers, window_manager.swipeHandler())
    end
    
    -- Start by scanning existing windows
    window_manager.refreshWindows()
    
    return self
end

-- Stop all modules
function PaperWM:stop()
    window_manager.stop()
    Swipe:stop()
    
    -- Release all windows from tiling
    for _, window in ipairs(self.window_filter:getWindows()) do
        window:setFrameInScreenBounds()
    end
    
    return self
end

-- Set up hotkey binding (maps directly to action_manager)
function PaperWM:bindHotkeys(mapping)
    hs.spoons.bindHotkeysToSpec(action_manager.getActions(), mapping)
end

return PaperWM
