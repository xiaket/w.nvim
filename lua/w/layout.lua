local M = {}

-- Dependencies
local config = require("w.config")
local debug = require("w.debug")

-- Track the previously active window
-- This value is updated in init.lua via an autocmd.
---@type number?
local prev_active_window = nil

-- Internal helpers
--- Find a window node and its parent node in the window tree
---@param tree table The window layout tree from vim.fn.winlayout()
---@param winid number The window ID to find
---@param parent table|nil The parent node of current tree node
---@return table|nil node The found window node
---@return table|nil parent The parent node of found window
local function find_window_in_tree(tree, winid, parent)
  local type = tree[1]
  if type == "leaf" then
    if tree[2] == winid then
      return tree, parent
    end
    return nil, nil
  end

  for _, subtree in ipairs(tree[2]) do
    local found, found_parent = find_window_in_tree(subtree, winid, tree)
    if found then
      return found, found_parent
    end
  end
  return nil, nil
end

--- Find leaf window in a tree branch based on direction
---@param tree table Window layout tree branch
---@param direction string "left"|"right"|"up"|"down"
---@return number|nil window_id Window handle or nil if not found
local function find_directional_leaf(tree, direction)
  if tree[1] == "leaf" then
    return tree[2]
  end
  -- When direction is "left", return the rightmost leaf node
  -- When direction is "right", return the leftmost leaf node
  local children = tree[2]
  local child_index = direction == "left" and #children or 1
  return find_directional_leaf(children[child_index], direction)
end

--- Find path from root to target window
---@param tree table Window layout tree
---@param winid number Window handle to find
---@param path table Path accumulator
---@return table|nil path Array of {node, index} pairs from root to window
local function find_path_to_window(tree, winid, path)
  debug.log(
    "In find_path_to_window:",
    "tree:",
    vim.inspect(tree),
    "winid:",
    winid,
    "path:",
    vim.inspect(path)
  )
  local type = tree[1]
  if type == "leaf" then
    if tree[2] == winid then
      debug.log("found path: ", vim.inspect(path))
      return path
    end
    debug.log("path no found")
    return nil
  end

  debug.log("Entering loop:", vim.inspect(tree[2]))
  for i, child in ipairs(tree[2]) do
    local child_path = vim.deepcopy(path)
    -- Index, either 1 or 2, marks the relative position of the node.
    -- For example, for the following layout:
    -- +---+---+---+
    -- |   |   B   |
    -- | A +---+---+
    -- |   | C | D |
    -- +---+---+---+
    -- The tree may look like:
    -- { "row",                              -- root
    --   {
    --     { "leaf", 1001 },                -- A
    --     { "col",                         -- B|C|D
    --       {
    --         { "leaf", 1002 },            -- B
    --         { "row",                     -- C|D
    --           {
    --             { "leaf", 1003 },        -- C
    --             { "leaf", 1004 }         -- D
    --           }
    --         }
    --       }
    --     }
    --   }
    -- }
    -- For window C, the response will look like:
    -- {
    --   {
    --     index = 2,  -- BCD is the second item in the top-level row
    --     node = <root row node>
    --   },
    --   {
    --     index = 2,  -- CD is the second item in the BCD column.
    --     node = <col node>
    --   },
    --   {
    --     index = 1,  -- C is the first item in C|D
    --     node = <inner row node>
    --   }
    -- }
    table.insert(child_path, { node = tree, index = i })
    local result = find_path_to_window(child, winid, child_path)
    if result then
      return result
    end
  end
  return nil
end

--- Check if two nodes in layout tree are the same
---@param node1 table First node from window layout tree
---@param node2 table Second node from window layout tree
---@return boolean true if nodes are the same, false otherwise
local function is_same_node(node1, node2)
  if node1[1] ~= node2[1] then
    return false
  end
  if node1[1] == "leaf" then
    return node1[2] == node2[2]
  end
  return true
end

--- Get relative direction of target window compared to source window
---@param source_win number Source window handle
---@param target_win number Target window handle
---@return string|nil direction "left"|"right"|"up"|"down" or nil if not related
local function get_relative_direction(source_win, target_win)
  local tree = vim.fn.winlayout()
  local source_path = find_path_to_window(tree, source_win, {})
  local target_path = find_path_to_window(tree, target_win, {})
  debug.log("source path:", vim.inspect(source_path))
  debug.log("target path:", vim.inspect(target_path))

  if not source_path or not target_path then
    return nil
  end

  -- Start from path end, find the first different position
  local i = 1
  while i <= #source_path and i <= #target_path do
    if not is_same_node(source_path[i].node, target_path[i].node) then
      break
    end
    i = i + 1
  end
  i = i - 1 -- Step back to the last common node

  if i == 0 then
    return nil
  end

  -- Use the last common node to determine direction
  local common_node = source_path[i].node
  local source_idx = source_path[i].index
  local target_idx = target_path[i].index

  if common_node[1] == "row" then
    return target_idx < source_idx and "left" or "right"
  elseif common_node[1] == "col" then
    return target_idx < source_idx and "up" or "down"
  end

  return nil
end

--- Find target window based on layout tree analysis
---@param current_win number Current window handle
---@param direction string "left"|"right"|"up"|"down"
---@return number|nil target_win Target window handle or nil
local function find_target_window(current_win, direction)
  local tree = vim.fn.winlayout()
  debug.log(
    "in find_target_window, tree:",
    vim.inspect(tree),
    "prev_active_window:",
    prev_active_window and prev_active_window or "nil",
    "current:",
    vim.api.nvim_get_current_win()
  )

  local path = find_path_to_window(tree, current_win, {})
  debug.log("find_path_to_window result:", vim.inspect(path))
  if not path then
    return nil
  end

  -- Check if prev_active_window is an option.
  if prev_active_window and vim.api.nvim_win_is_valid(prev_active_window) then
    local rel_direction = get_relative_direction(current_win, prev_active_window)
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
        return find_directional_leaf(node[2][target_index], direction)
      end
    end

    -- For up/down movement, look for vertical split ("col")
    if (direction == "up" or direction == "down") and node[1] == "col" then
      local target_index = (direction == "up") and (index - 1) or (index + 1)
      debug.log("target_index:", target_index)
      -- Check if target index is valid
      if target_index > 0 and target_index <= #node[2] then
        return find_directional_leaf(node[2][target_index], direction)
      end
    end
  end

  return nil
end

function M.update_previous_active_window()
  local current = prev_active_window ~= nil and prev_active_window or "nil"
  prev_active_window = vim.api.nvim_get_current_win()
  debug.log("updating previous active window from", current, "to", prev_active_window)
end

function M.get_previous_active_window()
  return prev_active_window
end

--- Check if new split is allowed in direction
---@param current_win number Window handle
---@param direction "left"|"right"|"up"|"down"
---@return boolean
local function can_split(current_win, direction)
  local tree = vim.fn.winlayout()
  local _, parent = find_window_in_tree(tree, current_win, nil)

  if not parent then
    return true -- First split always allowed
  end

  local split_type = parent[1]
  local sibling_count = 0
  for _, child in ipairs(parent[2]) do
    if child[1] == "leaf" then
      sibling_count = sibling_count + 1
    end
  end

  -- Check split direction and count
  if
    (direction == "left" or direction == "right")
    and split_type == "row"
    and sibling_count >= 2
  then
    return false
  end
  if (direction == "up" or direction == "down") and split_type == "col" and sibling_count >= 2 then
    return false
  end

  return true
end

---Check if window is an explorer window
---@param win_id number window ID to check
---@return boolean is explorer window
local function is_explorer(win_id)
  debug.log("layout", string.format("checking if win %d is explorer", win_id))
  if not win_id or not vim.api.nvim_win_is_valid(win_id) then
    debug.log("layout", "invalid window")
    return false
  end
  local buf = vim.api.nvim_win_get_buf(win_id)
  local ft = vim.api.nvim_buf_get_option(buf, "filetype")
  debug.log("layout", string.format("window %d buffer %d filetype: %s", win_id, buf, ft))
  return ft == config.const.filetype
end

--- Create new split in specified direction
---@param direction "left"|"right"|"up"|"down"
local function create_split(direction)
  -- Map direction to vim split commands
  debug.log("creating split in", direction)
  local split_commands = {
    left = { "v", "h" },
    right = { "v", "l" },
    up = { "s", "k" },
    down = { "s", "j" },
  }

  local commands = split_commands[direction]
  if commands then
    local tree = vim.fn.winlayout()
    debug.log("before tree:", vim.inspect(tree))
    local current_win = vim.api.nvim_get_current_win()
    debug.log("Window before split:", current_win)

    debug.log("running wincmd:", commands[1])
    vim.api.nvim_command("wincmd " .. commands[1]) -- Create split
    debug.log("Window after first command:", vim.api.nvim_get_current_win())

    debug.log("running wincmd:", commands[2])
    vim.api.nvim_command("wincmd " .. commands[2]) -- Move to the new split
    debug.log("Window after second command:", vim.api.nvim_get_current_win())
    tree = vim.fn.winlayout()
    debug.log("after tree:", vim.inspect(tree))
  end
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
      if is_explorer(node[2]) then
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

---Split current window in specified direction or focus existing window
---@param direction "left"|"right"|"up"|"down"
---
---Usage scenarios:
---1. User wants to create a new split in specified direction
---   - Creates new window if no existing window in that direction
---   - Respects explorer window constraints (only allows right splits)
---   - Maintains golden ratio after split
---2. User wants to focus an existing window in that direction
---   - Switches focus to existing window if one exists
---   - Maintains window layout and split structure
---3. User triggers split in invalid direction for current layout
---   - Shows warning and prevents invalid split
---
---Expected behavior:
---1. For explorer windows:
---   - Only allows splits to the right
---   - Other directions are ignored with warning
---2. For normal windows:
---   - If adjacent window exists: focuses that window
---   - If no adjacent window: creates new split
---   - If split would violate layout rules: shows warning
---3. After any successful operation:
---   - Updates split tree structure
---   - Maintains golden ratio
---   - Records previous active window
---
---Split rules:
---1. Each split direction (horizontal or vertical) can contain at most two splits. Splits can be
---  nested. A horizontal split can only nest vertical splits inside it, and vice versa
---2. Explorer windows are special cases that don't follow the split tree rule
---3. When moving focus is desired, start searching from current split in the split tree, find the
---  nearest split in target direction. If not found, search in parent split, if no target found up
---  to root, do nothing (no-op). If multiple targets found, prefer the last active window
---
---Examples:
---1. User opens a file, then executes :WSplitLeft, this will create a horizontal split on the left
---  side, A|B. Focus switches to A. If user executes :WSplitLeft in A, it will be an no-op. If
---  user executes :WSplitRight in A, focus will be switched to B. No horizontal split will be created
---  when A and B are the only splits, except explorer window.
---2. In the following layout:
---  +---+---+
---  |   | B |
---  + A +---+
---  |   | C |
---  +---+---+
---    a. :WSplitLeft in either B or C will land in A.
---    b. No further vertical splits can be made among B/C, but we can do it in A.
---    c. We can create horizontal splits in B and C, but not A.
---    d. If we were in B then switched focus to A, running :WSplitRight in A will land in B as it
---      is the last active window.
---3. In the following layout:
---  +---+---+---+
---  |   |   B   |
---  + A +---+---+
---  |   | C | D |
---  +---+---+---+
---    a. When our focus is in C, :WSplitLeft will land in A, :WSplitRight will land in D, :WSplitUp
---      will land in B, and :WSplitDown will create new vertical splits.
---    b. If we were in C then switched focus to A, running :WSplitRight in A will land in C.
function M.split(direction)
  debug.log(string.rep("=", 40), "split called with direction:", direction, string.rep("=", 40))
  local current = vim.api.nvim_get_current_win()
  debug.log("current window:", current)

  -- Only allow right split for explorer windows
  if is_explorer(current) then
    if direction ~= "right" then
      debug.log("explorer window only allows right split")
      return
    end
  end

  -- Try to find existing window to focus
  local target_win = find_target_window(current, direction)
  if target_win then
    debug.log("found target window", target_win)
    vim.api.nvim_set_current_win(target_win)
    debug.log("current window:", vim.api.nvim_get_current_win())
    debug.log("End of run.", string.rep("=", 80))
    return
  end

  debug.log("target window not found")
  -- Check if new split is allowed
  if not can_split(current, direction) then
    debug.log("Cannot create new split in this direction")
    debug.log("current window:", vim.api.nvim_get_current_win())
    debug.log("End of run.", string.rep("=", 80))
    return
  end

  create_split(direction)
  debug.log("current window:", vim.api.nvim_get_current_win())
  debug.log(string.rep("=", 40), "Finished split.", string.rep("=", 40))
end

---Redraw all windows according to golden ratio
---
---The resize rules:
---1. Golden Ratio Rule:
---   - In any split, the active window takes up 0.618 of the space
---   - The inactive window naturally takes up the remaining 0.382 of the space
---   - Due to the split tree nesting rule in M.split, this ratio applies at any level of splits
---
---2. Explorer Window Rule:
---   - Explorer window has a fixed width, not following the golden ratio
---   - Creating explorer window will reduce maximum window width, triggers a redraw.
---
---3. Active Window Rule:
---   - When a window gains focus, it should get 0.618 of the space in its containing split
function M.redraw()
  debug.log("redraw called")

  local sizes = M.calculate_window_sizes()
  for win_id, size in pairs(sizes) do
    if vim.api.nvim_win_is_valid(win_id) then
      vim.api.nvim_win_set_width(win_id, size.width)
      vim.api.nvim_win_set_height(win_id, size.height)
    end
  end
end

return M
