local Window <const> = hs.window

local Floating = {}
Floating.__index = Floating

---hs.settings key for persisting is_floating, stored as an array of window id
local IsFloatingKey <const> = "PaperWM_is_floating"

---initialize module with reference to PaperWM
---@param paperwm PaperWM
function Floating.init(paperwm)
    Floating.PaperWM = paperwm
end

---save the is floating state to settings
function Floating.persistFloatingList()
    local persisted = {}
    for k, _ in pairs(Floating.PaperWM.state.is_floating) do
        table.insert(persisted, k)
    end
    hs.settings.set(IsFloatingKey, persisted)
end

---remove window from the floating list before it is destroyed
---@param window Window
function Floating.removeFloating(window)
    Floating.PaperWM.state.is_floating[window:id()] = nil
    Floating.persistFloatingList()
end

---restore floating windows from persistant settings, filtering for valid windows
function Floating.restoreFloating()
    local persisted = hs.settings.get(IsFloatingKey) or {}
    for _, id in ipairs(persisted) do
        local window = Window.get(id)
        if window and Floating.PaperWM.window_filter:isWindowAllowed(window) then
            Floating.PaperWM.state.is_floating[id] = true
        end
    end
    Floating.persistFloatingList()
end

---return true if window is floating, false if not or state cannot be determined
---@param window Window
---@return boolean
function Floating.isFloating(window)
    return Floating.PaperWM.state.is_floating[window:id()] or false
end

---add or remove focused window from the floating layer and retile the space
---@param window Window|nil optional window to float and focus
function Floating.toggleFloating(window)
    window = window or Window.focusedWindow()
    if not window then
        Floating.PaperWM.logger.d("focused window not found")
        return
    end

    Floating.PaperWM.state.is_floating[window:id()] = (Floating.isFloating(window) == false) and true or nil
    Floating.persistFloatingList()

    local space = (function()
        if Floating.isFloating(window) then
            return Floating.PaperWM.windows.removeWindow(window, true)
        else
            return Floating.PaperWM.windows.addWindow(window)
        end
    end)()
    if space then
        window:focus()
        Floating.PaperWM:tileSpace(space)
    end
end

return Floating
