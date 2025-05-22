-- Event handling system for PaperWM

local event_handler = {}

-- Core Hammerspoon API dependencies
local Spaces = hs.spaces
local Timer = hs.timer
local Watcher = hs.uielement.watcher
local Window = hs.window

-- Module references
local PaperWM
local window_manager

-- Initialize with references to required objects
function event_handler.init(paperWM, windowManager)
    PaperWM = paperWM
    window_manager = windowManager

    -- Set up event subscriptions for window management
    PaperWM.window_filter:subscribe({
        Window.filter.windowFocused,
        Window.filter.windowVisible,
        Window.filter.windowNotVisible,
        Window.filter.windowFullscreened,
        Window.filter.windowUnfullscreened,
        Window.filter.windowDestroyed
    }, function(window, _, event) event_handler.windowEventHandler(window, event) end)

    return event_handler
end

-- Stop monitoring for events
function event_handler.stop()
    PaperWM.window_filter:unsubscribeAll()
end

---Window event handler
---Processes all window events and updates window state
---@param window Window
---@param event string name of the event
function event_handler.windowEventHandler(window, event)
    -- Log the event for debugging
    PaperWM.logger.df("%s for [%s] id: %d", event, window,
        window and window:id() or -1)
    local space = nil

    -- For floating windows, only handle destruction events
    local is_floating = window_manager.getIsFloating()
    if is_floating[window:id()] then
        -- Handle floating window destruction
        if event == "windowDestroyed" then
            is_floating[window:id()] = nil
            window_manager.persistFloatingList()
        end
        -- Ignore all other events for floating windows
        return
    end

    -- Handle window focus events
    if event == "windowFocused" then
        -- If this is a pending window, schedule the event to run later
        local pending_window = window_manager.getPendingWindow()

        if pending_window and window == pending_window then
            Timer.doAfter(Window.animationDuration,
                function()
                    PaperWM.logger.vf("pending window timer for %s", window)
                    event_handler.windowEventHandler(window, event)
                end)
            return
        end

        -- Track the window for future addWindow calls
        window_manager.setPrevFocusedWindow(window)
        space = Spaces.windowSpaces(window)[1]

        -- Handle window creation events
    elseif event == "windowVisible" or event == "windowUnfullscreened" then
        space = window_manager.addWindow(window)

        -- Handle pending window logic
        if pending_window and window == pending_window then
            window_manager.setPendingWindow(nil) -- tried to add window for the second time
        elseif not space then
            -- If we couldn't add the window (likely no space yet), retry later
            window_manager.setPendingWindow(window)
            Timer.doAfter(Window.animationDuration,
                function()
                    event_handler.windowEventHandler(window, event)
                end)
            return
        end

        -- Handle window removal events
    elseif event == "windowNotVisible" then
        space = window_manager.removeWindow(window)

        -- Handle fullscreen toggling
    elseif event == "windowFullscreened" then
        space = window_manager.removeWindow(window, true) -- don't focus new window if fullscreened

        -- Handle window movement/resize events
    elseif event == "AXWindowMoved" or event == "AXWindowResized" then
        space = Spaces.windowSpaces(window)[1]
    end

    -- Retile the space if necessary
    if space then
        local layout_engine = require("modules.layout_engine")
        layout_engine.tileSpace(space)
    end
end

return event_handler
