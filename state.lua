local Watcher <const> = hs.uielement.watcher

local State = {}
State.__index = State

---private state
local window_list = {} -- 3D array of tiles in order of [space][x][y]
local index_table = {} -- dictionary of {space, x, y} with window id for keys
local ui_watchers = {} -- dictionary of uielement watchers with window id for keys
local x_positions = {} -- dictionary of horizontal positions with [space][id] for keys
---public state
State.is_floating = {} -- dictionary of boolean with window id for keys
State.prev_focused_window = nil ---@type Window|nil
State.pending_window = nil ---@type Window|nil

---initialize module with reference to PaperWM
---@param paperwm PaperWM
function State.init(paperwm)
    State.PaperWM = paperwm
    State.clear()
end

---clear all internal state
function State.clear()
    window_list = {}
    index_table = {}
    ui_watchers = {}
    x_positions = {}
    State.is_floating = {}
    State.prev_focused_window = nil
    State.pending_window = nil
end

---walk through all tiled windows in a space and update the index table
---@param space Space
local function update_index(space)
    for col, rows in ipairs(window_list[space] or {}) do
        for row, window in ipairs(rows) do
            index_table[window:id()] = { space = space, col = col, row = row }
        end
    end
end

---get a proxy table for a space, column, or row of tiled windows
---the proxy table can be used to iterate over, insert, remove, and access
---windows while keeping track of internal state
---@param space Space get a list of columns for a space
---@param column number|nil get a list of windows for a column
---@param row number|nil get a window for a row in a column
---@return Window[][]|Window[]|Window|nil
function State.windowList(space, column, row)
    if space then
        local columns = window_list[space]
        if column then
            local rows = columns and columns[column]
            if row then
                return rows and rows[row]
            end

            return rows and setmetatable({}, {
                __index = function(_, row) return rows[row] end,
                __newindex = function(_, row, window)
                    rows[row] = window
                    if not next(columns[column]) then table.remove(columns, column) end
                    if not next(window_list[space]) then window_list[space] = nil end
                    update_index(space)
                end,
                __len = function(_) return #rows end,
                __pairs = function(_) return pairs(rows) end,
                __ipairs = function(_) return ipairs(rows) end,
            })
        end

        return setmetatable({}, columns and {
            __index = function(_, column) return columns[column] end,
            __newindex = function(_, column, rows)
                -- space is guaranteed to exist here
                columns[column] = rows -- add a new column
                -- handle case where all columns have been removed from a space
                if not next(window_list[space]) then window_list[space] = nil end
                update_index(space)
            end,
            __len = function(_) return #columns end,
            __pairs = function(_) return pairs(columns) end,
            __ipairs = function(_) return ipairs(columns) end,
        } or { -- metatable for a nil space
            __newindex = function(_, column, rows)
                -- space may not exist here so create it
                if not window_list[space] then window_list[space] = {} end
                window_list[space][column] = rows
                update_index(space)
            end,
        })
    end
end

---get the index { space, col, row } of a tiled window
---@param window Window
---@param remove boolean|nil Set to true to remove the entry
---@return table|nil
function State.windowIndex(window, remove)
    local index = index_table[window:id()]
    if remove then index_table[window:id()] = nil end
    return index
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

---return a table that provides accessor methods to x_positions via a metatable
---@param space Space
function State.xPositions(space)
    return setmetatable({}, {
        __index = function(_, id) return (x_positions[space] or {})[id] end,
        __newindex = function(_, id, x)
            if not x_positions[space] then x_positions[space] = {} end
            x_positions[space][id] = x
            if not next(x_positions[space]) then x_positions[space] = nil end
        end,
        __pairs = function(_) return pairs(x_positions[space] or {}) end,
    })
end

---return internal state for debugging purposes
function State.get()
    return {
        window_list = window_list,
        index_table = index_table,
        ui_watchers = ui_watchers,
        x_positions = x_positions,
        is_floating = State.is_floating,
        prev_focused_window = State.prev_focused_window,
        pending_window = State.pending_window,
    }
end

---pretty print the current state
function State.dump()
    local output = { "--- PaperWM State ---" }

    table.insert(output, "window_list:")
    for space, columns in pairs(window_list) do
        table.insert(output, string.format("  Space %s:", tostring(space)))
        for col_idx, column in ipairs(columns) do
            table.insert(output, string.format("    Column %d:", col_idx))
            for row_idx, window in ipairs(column) do
                table.insert(output, string.format("      Row %d: %s (%d)", row_idx, window:title(), window:id()))
            end
        end
    end

    table.insert(output, "\nindex_table:")
    for id, index in pairs(index_table) do
        table.insert(output, string.format("  Window ID %d: space=%s, col=%d, row=%d",
            id, tostring(index.space), index.col, index.row))
    end

    table.insert(output, "\nis_floating:")
    for id, floating in pairs(State.is_floating) do
        if floating then table.insert(output, string.format("  Window ID %d is floating", id)) end
    end

    table.insert(output, "\nx_positions:")
    for space, positions in pairs(x_positions) do
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
