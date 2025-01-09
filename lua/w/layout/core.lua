local M = {}

-- Dependencies
local debug = require("w.debug")
local util = require("w.layout.util")

--- Find target window based on layout tree analysis
---@param current_win number Current window handle
---@param direction string "left"|"right"|"up"|"down"
---@return number|nil target_win Target window handle or nil
---
--- This function implements an intelligent window finding algorithm that:
--- 1. First checks if the previously active window is in the requested direction
--- 2. If not, traverses the window layout tree to find an appropriate target
--- 3. For horizontal movement (left/right), looks for windows in horizontal splits
--- 4. For vertical movement (up/down), looks for windows in vertical splits
--- 5. Returns nil if no valid target window is found
function M.find_target_window(current_win, direction)
  local tree = vim.fn.winlayout()
  local prev_active_window = util.get_previous_active_window()
  debug.dump_state("layout:find_target_window")

  local path = util.find_path_to_window(tree, current_win, {})
  debug.log("layout:find_path_to_window result:", vim.inspect(path))
  if not path then
    return nil
  end

  -- Check if prev_active_window is an option.
  if prev_active_window and vim.api.nvim_win_is_valid(prev_active_window) then
    local rel_direction = util.get_relative_direction(current_win, prev_active_window)
    debug.log(
      "layout:find_target_window",
      string.format("prev_active_window relative direction: %s", rel_direction)
    )
    if rel_direction == direction then
      return prev_active_window
    end
  end

  -- Traverse up the path to find appropriate target
  for i = #path, 1, -1 do
    local node = path[i].node
    local index = path[i].index
    debug.log("layout:find_target_window loop. i:", i, "index:", index, "node:", vim.inspect(node))

    -- For left/right movement, look for horizontal split ("row")
    if (direction == "left" or direction == "right") and node[1] == "row" then
      local target_index = (direction == "left") and (index - 1) or (index + 1)
      if target_index > 0 and target_index <= #node[2] then
        return util.find_directional_leaf(node[2][target_index], direction)
      end
    end

    -- For up/down movement, look for vertical split ("col")
    if (direction == "up" or direction == "down") and node[1] == "col" then
      local target_index = (direction == "up") and (index - 1) or (index + 1)
      if target_index > 0 and target_index <= #node[2] then
        return util.find_directional_leaf(node[2][target_index], direction)
      end
    end
  end

  return nil
end

--- Check if new split is allowed in direction
---@param current_win number Window handle
---@param direction "left"|"right"|"up"|"down"
---@return boolean
function M.can_split(current_win, direction)
  local tree = vim.fn.winlayout()
  local _, parent = util.find_window_in_tree(tree, current_win, nil)
  debug.log("layout:find_window_in_tree result:", vim.inspect(parent))

  if not parent then
    return true -- First split always allowed
  end

  local split_type = parent[1]
  local sibling_count = 0
  for _, child in ipairs(parent[2]) do
    if child[1] == "leaf" then
      local win_id = child[2]
      if not util.is_explorer(win_id) then
        sibling_count = sibling_count + 1
      end
    end
  end

  if sibling_count < 2 then
    return true
  end
  -- Check split direction
  if (direction == "left" or direction == "right") and split_type == "row" then
    return false
  end
  if (direction == "up" or direction == "down") and split_type == "col" then
    return false
  end

  return true
end

--- Create new split in specified direction
---@param direction "left"|"right"|"up"|"down"
function M.create_split(direction)
  debug.log("creating split in", direction)
  debug.dump_state("start layout:create_split")

  local split_commands = {
    left = "wincmd v|wincmd h",
    right = "wincmd v|wincmd l",
    up = "wincmd s|wincmd k",
    down = "wincmd s|wincmd j",
  }

  local command = split_commands[direction]
  if command then
    debug.log("running command:", command)
    vim.cmd(command)
  end

  debug.dump_state("exit layout:create_split")
end

return M
