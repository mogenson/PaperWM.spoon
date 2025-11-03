--- === PaperWM.spoon ===
---
--- Tile windows horizontally. Inspired by PaperWM Gnome extension.
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
local Spaces <const> = hs.spaces

local PaperWM = {}
PaperWM.__index = PaperWM

-- Metadata
PaperWM.name = "PaperWM"
PaperWM.version = "0.9"
PaperWM.author = "Michael Mogenson"
PaperWM.homepage = "https://github.com/mogenson/PaperWM.spoon"
PaperWM.license = "MIT - https://opensource.org/licenses/MIT"

-- Types

---@alias PaperWM table PaperWM module object
---@alias Window userdata a ui.window
---@alias Frame table hs.geometry.rect
---@alias Index { row: number, col: number, space: number }
---@alias Space number a Mission Control space ID
---@alias Screen userdata hs.screen
---@alias Mapping { [string]: (table | string)[]}

-- logger
PaperWM.logger = hs.logger.new(PaperWM.name)

-- Load modules
PaperWM.config = dofile(hs.spoons.resourcePath("config.lua"))
PaperWM.state = dofile(hs.spoons.resourcePath("state.lua"))
PaperWM.windows = dofile(hs.spoons.resourcePath("windows.lua"))
PaperWM.space = dofile(hs.spoons.resourcePath("space.lua"))
PaperWM.events = dofile(hs.spoons.resourcePath("events.lua"))
PaperWM.actions = dofile(hs.spoons.resourcePath("actions.lua"))
PaperWM.floating = dofile(hs.spoons.resourcePath("floating.lua"))
PaperWM.tiling = dofile(hs.spoons.resourcePath("tiling.lua"))

-- Initialize modules
PaperWM.windows.init(PaperWM)
PaperWM.space.init(PaperWM)
PaperWM.events.init(PaperWM)
PaperWM.actions.init(PaperWM)
PaperWM.state.init(PaperWM)
PaperWM.floating.init(PaperWM)
PaperWM.tiling.init(PaperWM)

-- Apply config
for k, v in pairs(PaperWM.config) do
    PaperWM[k] = v
end

---start automatic window tiling
---@return PaperWM
function PaperWM:start()
    -- check for some settings
    if not Spaces.screensHaveSeparateSpaces() then
        self.logger.e(
            "please check 'Displays have separate Spaces' in System Preferences -> Mission Control")
    end

    -- clear state
    self.state.clear();

    -- restore floating windows
    self.floating.restoreFloating()

    -- populate window list, index table, ui_watchers, and set initial layout
    self.windows.refreshWindows()

    -- start event listeners
    self.events.start()

    return self
end

---stop automatic window tiling
---@return PaperWM
function PaperWM:stop()
    -- stop events
    self.events.stop()

    -- fit all windows within the bounds of the screen
    for _, window in ipairs(self.window_filter:getWindows()) do
        window:setFrameInScreenBounds()
    end

    return self
end

function PaperWM:tileSpace(space)
    self.tiling.tileSpace(space)
end

function PaperWM:bindHotkeys(mapping)
    self.actions.bindHotkeys(mapping)
end

return PaperWM
