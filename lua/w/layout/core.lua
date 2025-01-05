local M = {}

-- Dependencies
local config = require("w.config")
local debug = require("w.debug")
local util = require("w.layout.util")

--- Find target window based on layout tree analysis
---@param current_win number Current window handle
---@param direction string "left"|"right"|"up"|"down"
---@return number|nil target_win Target window handle or nil
function M.find_target_window(current_win, direction)
  local tree = vim.fn.winlayout()
  local prev_active_window = util.get_previous_active_window()
  debug.log(
    "in find_target_window, tree:",
    vim.inspect(tree),
    "prev_active_window:",
    prev_active_window and prev_active_window or "nil",
    "current:",
    vim.api.nvim_get_current_win()
  )

  local path = util.find_path_to_window(tree, current_win, {})
  debug.log("find_path_to_window result:", vim.inspect(path))
  if not path then
    return nil
  end

  -- Check if prev_active_window is an option.
  if prev_active_window and vim.api.nvim_win_is_valid(prev_active_window) then
    local rel_direction = util.get_relative_direction(current_win, prev_active_window)
    debug.log("rel_direction:", rel_direction)
    if rel_direction == direction then
      return prev_active_window
    end
  end

  -- Traverse up the path to find appropriate target
  for i = #path, 1, -1 do
    local node = path[i].node
    local index = path[i].index
    debug.log("i:", i, "index:", index, "node:", vim.inspect(node))

    -- For left/right movement, look for horizontal split ("row")
    if (direction == "left" or direction == "right") and node[1] == "row" then
      local target_index = (direction == "left") and (index - 1) or (index + 1)
      -- Check if target index is valid
      if target_index > 0 and target_index <= #node[2] then
        return util.find_directional_leaf(node[2][target_index], direction)
      end
    end

    -- For up/down movement, look for vertical split ("col")
    if (direction == "up" or direction == "down") and node[1] == "col" then
      local target_index = (direction == "up") and (index - 1) or (index + 1)
      debug.log("target_index:", target_index)
      -- Check if target index is valid
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

--- Calculate ideal window sizes based on layout tree and active window
---@return table<number, {width: number, height: number}> Map of window ID to its ideal size
function M.calculate_window_sizes()
  local total_width = vim.o.columns
  local total_height = vim.o.lines
  local original_tree = vim.fn.winlayout()
  local active_win = vim.api.nvim_get_current_win()
  local sizes = {}

  debug.log(
    "calculate_window_sizes called with",
    "tree:",
    vim.inspect(original_tree),
    "total_width:",
    total_width,
    "total_height:",
    total_height,
    "active_win:",
    active_win
  )

  -- Phase 1: Extract explorer and calculate available width
  local explorer_win = nil
  local available_width = total_width

  -- Find explorer window and remove it from tree
  local function clean_tree(node)
    if node[1] == "leaf" then
      if util.is_explorer(node[2]) then
        explorer_win = node[2]
        return nil
      end
      return node
    end

    local new_children = {}
    for _, child in ipairs(node[2]) do
      local clean_child = clean_tree(child)
      if clean_child then
        table.insert(new_children, clean_child)
      end
    end

    if #new_children == 0 then
      return nil
    elseif #new_children == 1 and node[1] == "row" then
      -- Collapse single-child row
      return new_children[1]
    else
      node[2] = new_children
      return node
    end
  end

  local clean_layout = clean_tree(vim.deepcopy(original_tree))
  debug.log("clean_layout:", vim.inspect(clean_layout))

  -- Set explorer size if found
  if explorer_win then
    sizes[explorer_win] = {
      width = config.options.explorer.window_width,
      height = total_height,
    }
    available_width = total_width - config.options.explorer.window_width
  end

  debug.log(
    "After preprocessing:",
    "explorer_win:",
    explorer_win and explorer_win or "nil",
    "available_width:",
    available_width
  )

  -- Phase 2: Calculate sizes for remaining windows

  -- Check if node contains active window
  local function contains_active(node)
    if node[1] == "leaf" then
      return node[2] == active_win
    end
    for _, child in ipairs(node[2]) do
      if contains_active(child) then
        return true
      end
    end
    return false
  end

  -- Process layout tree with available width
  local function process_node(node, avail_width, avail_height)
    if node[1] == "leaf" then
      sizes[node[2]] = {
        width = avail_width,
        height = avail_height,
      }
      return
    end

    local children = node[2]
    if node[1] == "row" then
      if #children == 2 then
        -- For two windows, active one should get ratio (larger) portion
        local ratio = config.options.split_ratio
        local larger_width = math.floor(avail_width * ratio) -- 0.618
        local smaller_width = avail_width - larger_width -- 0.382

        -- Determine which window gets the larger portion
        if contains_active(children[1]) then
          process_node(children[1], larger_width, avail_height)
          process_node(children[2], smaller_width, avail_height)
        else
          process_node(children[1], smaller_width, avail_height)
          process_node(children[2], larger_width, avail_height)
        end
      else
        -- Equal distribution for more than two windows
        local child_width = math.floor(avail_width / #children)
        for i, child in ipairs(children) do
          local width = i == #children and (avail_width - child_width * (#children - 1))
            or child_width
          process_node(child, width, avail_height)
        end
      end
    else -- col
      if #children == 2 then
        -- For two windows, active one should get ratio (larger) portion
        local ratio = config.options.split_ratio
        local larger_height = math.floor(avail_height * ratio) -- 0.618
        local smaller_height = avail_height - larger_height -- 0.382

        -- Determine which window gets the larger portion
        if contains_active(children[1]) then
          process_node(children[1], avail_width, larger_height)
          process_node(children[2], avail_width, smaller_height)
        else
          process_node(children[1], avail_width, smaller_height)
          process_node(children[2], avail_width, larger_height)
        end
      else
        -- Equal height distribution
        local child_height = math.floor(avail_height / #children)
        for i, child in ipairs(children) do
          local height = i == #children and (avail_height - child_height * (#children - 1))
            or child_height
          process_node(child, avail_width, height)
        end
      end
    end
  end

  if clean_layout then
    process_node(clean_layout, available_width, total_height)
  end

  debug.log("calculate_window_sizes final:", vim.inspect(sizes))
  return sizes
end

--- Create new split in specified direction
---@param direction "left"|"right"|"up"|"down"
function M.create_split(direction)
  debug.dump_state("start layout:create_split")
  debug.log("creating split in", direction)

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
