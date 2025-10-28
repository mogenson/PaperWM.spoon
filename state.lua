local Watcher <const> = hs.uielement.watcher

local State = {}
State.__index = State

---hs.settings key for persisting is_floating, stored as an array of window id
local IsFloatingKey <const> = "PaperWM_is_floating"
State.IsFloatingKey = IsFloatingKey

---array of windows sorted from left to right
State.window_list = {} -- 3D array of tiles in order of [space][x][y]
State.index_table = {} -- dictionary of {space, x, y} with window id for keys
local ui_watchers = {} -- dictionary of uielement watchers with window id for keys
State.is_floating = {} -- dictionary of boolean with window id for keys
State.x_positions = {} -- dictionary of horizontal positions with [space][id] for keys

---initialize module with reference to PaperWM
---@param paperwm PaperWM
function State.init(paperwm)
    State.PaperWM = paperwm
    State.clear()
end

---clear all internal state
function State.clear()
    State.window_list = {}
    State.index_table = {}
    ui_watchers = {}
    State.is_floating = {}
    State.x_positions = {}
end

---create and start a UI watcher for a new window
---@param window Window
function State.uiWatcherCreate(window)
    local id = window:id()
    ui_watchers[id] = window:newWatcher(
        function(window, event, _, self)
            State.PaperWM.events.windowEventHandler(window, event, self)
        end, State.PaperWM)
    State.uiWatcherStart(id)
end

---delete a UI watcher
---@param id number Window ID
function State.uiWatcherDelete(id)
    State.uiWatcherStop(id)
    ui_watchers[id] = nil
end

---start a UI watcher
---@param id number Window ID
function State.uiWatcherStart(id)
    local watcher = ui_watchers[id]
    if watcher then watcher:start({ Watcher.windowMoved, Watcher.windowResized }) end
end

---stop a UI watcher
---@param id number Window ID
function State.uiWatcherStop(id)
    local watcher = ui_watchers[id]
    if watcher then watcher:stop() end
end

---stop all UI watchers
function State.uiWatcherStopAll()
    for _, watcher in pairs(ui_watchers) do watcher:stop() end
end

State.prev_focused_window = nil ---@type Window|nil
State.pending_window = nil ---@type Window|nil

---return internal state for debugging purposes
function State.get()
    return {
        window_list = State.window_list,
        index_table = State.index_table,
        ui_watchers = ui_watchers,
        is_floating = State.is_floating,
        x_positions = State.x_positions,
    }
end

---pretty print the current state
function State.dump()
    local output = { "--- PaperWM State ---" }

    table.insert(output, "window_list:")
    for space, columns in pairs(State.window_list) do
        table.insert(output, string.format("  Space %s:", tostring(space)))
        for col_idx, column in ipairs(columns) do
            table.insert(output, string.format("    Column %d:", col_idx))
            for row_idx, window in ipairs(column) do
                table.insert(output, string.format("      Row %d: %s (%d)", row_idx, window:title(), window:id()))
            end
        end
    end

    table.insert(output, "\nindex_table:")
    for id, index in pairs(State.index_table) do
        table.insert(output, string.format("  Window ID %d: space=%s, col=%d, row=%d",
            id, tostring(index.space), index.col, index.row))
    end

    table.insert(output, "\nis_floating:")
    for id, floating in pairs(State.is_floating) do
        if floating then table.insert(output, string.format("  Window ID %d is floating", id)) end
    end

    table.insert(output, "\nx_positions:")
    for space, positions in pairs(State.x_positions) do
        table.insert(output, string.format("  Space %s:", tostring(space)))
        for id, x in pairs(positions) do
            table.insert(output, string.format("    Window %s (%d): x=%d", hs.window(id):title(), id, x))
        end
    end

    if State.prev_focused_window then
        table.insert(output, string.format("\nprev_focused_window: %s (%d)",
            State.prev_focused_window:title(),
            State.prev_focused_window:id()))
    else
        table.insert(output, "\nprev_focused_window: nil")
    end

    if State.pending_window then
        table.insert(output, string.format("pending_window: %s (%d)",
            State.pending_window:title(),
            State.pending_window:id()))
    else
        table.insert(output, "pending_window: nil")
    end

    table.insert(output, "---------------------")
    print(table.concat(output, "\n"))
end

return State
