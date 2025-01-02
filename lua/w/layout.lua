local M = {}

M.EXPLORER_FILETYPE = "WExplorer"

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
  return ft == M.EXPLORER_FILETYPE
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
  local tree = vim.fn.winlayout()
  local active_win = vim.api.nvim_get_current_win()
  local sizes = {}
  debug.log(
    "calculate_window_sizes called with",
    "tree:",
    vim.inspect(tree),
    "total_width:",
    total_width,
    "total_height:",
    total_height,
    "active_win:",
    active_win
  )

  -- First handle explorer if exists
  local has_explorer = false
  local explorer_win = nil
  for _, win_id in ipairs(vim.api.nvim_list_wins()) do
    if is_explorer(win_id) then
      has_explorer = true
      explorer_win = win_id
      break
    end
  end

  local explorer_width = 0
  if has_explorer and explorer_win ~= nil then
    explorer_width = config.options.explorer_window_width

    -- Force explorer window size
    sizes[explorer_win] = {
      width = explorer_width,
      height = total_height,
    }
  end
  debug.log("has_explorer:", has_explorer, "total_width:", total_width)

  --- Divide space among children, giving active child golden ratio if exists
  ---@param children table Array of child nodes
  ---@param avail_space number Total available space
  ---@param active_child_idx number|nil Index of child containing active window
  ---@return table Array of allocated sizes
  local function process_split_dimension(children, avail_space, active_child_idx)
    debug.log(
      "split_dimension",
      string.format(
        "Starting process_split_dimension with avail_space=%d, active_child_idx=%s",
        avail_space,
        active_child_idx or "nil"
      )
    )
    debug.log("split_dimension", "Children:", vim.inspect(children))

    local used_space = 0
    local sizes = {}

    local explorer_indices = {}
    for i, child in ipairs(children) do
      if child[1] == "leaf" and is_explorer(child[2]) then
        sizes[i] = config.options.explorer_window_width
        used_space = used_space + sizes[i]
        explorer_indices[i] = true
        debug.log(
          "split_dimension",
          string.format(
            "Found explorer at index %d, width=%d, used_space=%d",
            i,
            sizes[i],
            used_space
          )
        )
      end
    end

    -- 第二步: 识别非explorer的active window
    local active_non_explorer_idx
    if active_child_idx and not explorer_indices[active_child_idx] then
      active_non_explorer_idx = active_child_idx
      debug.log(
        "split_dimension",
        string.format("Found non-explorer active window at index %d", active_non_explorer_idx)
      )
    end

    -- 第三步: 计算剩余空间和非explorer窗口数
    local remaining_space = avail_space - used_space
    local non_explorer_count = 0
    for i, _ in ipairs(children) do
      if not explorer_indices[i] then
        non_explorer_count = non_explorer_count + 1
      end
    end
    debug.log(
      "split_dimension",
      string.format(
        "After explorer allocation: remaining_space=%d, non_explorer_count=%d",
        remaining_space,
        non_explorer_count
      )
    )

    if non_explorer_count > 0 then
      if non_explorer_count == 2 then -- 只有两个非explorer窗口的情况
        local split_ratio = config.options.split_ratio
        local first_width = math.floor(remaining_space * (1 - split_ratio))
        local second_width = remaining_space - first_width

        local non_explorer_indices = {}
        for i, child in ipairs(children) do
          if not explorer_indices[i] then
            table.insert(non_explorer_indices, i)
          end
        end

        sizes[non_explorer_indices[1]] = first_width
        sizes[non_explorer_indices[2]] = second_width

        debug.log(
          "split_dimension",
          string.format(
            "Allocated golden ratio windows: first=%d, second=%d",
            first_width,
            second_width
          )
        )
      else
        local window_width = math.floor(remaining_space / non_explorer_count)
        for i, child in ipairs(children) do
          if not explorer_indices[i] then
            sizes[i] = window_width
          end
        end
      end
    end

    debug.log("split_dimension", "Final sizes:", vim.inspect(sizes))
    return sizes
  end

  --- Process a window layout node recursively and calculate sizes for all windows
  ---@param node table Layout tree node from vim.fn.winlayout()
  ---      node[1] is type: "row", "col", or "leaf"
  ---      node[2] is content: array of child nodes or window id for leaf
  ---@param avail_width number Available width for this subtree
  ---@param avail_height number Available height for this subtree
  ---@return number wins_count Total number of windows in this subtree
  ---@return boolean has_active Whether this subtree contains active window
  local function process_node(node, avail_width, avail_height)
    debug.log(
      "Processing node:",
      vim.inspect(node),
      "avail_width:",
      avail_width,
      "avail_height:",
      avail_height
    )

    if node[1] == "leaf" then
      local win_id = node[2]
      -- Skip if this is explorer window as its size is already set
      if not is_explorer(win_id) then
        sizes[win_id] = {
          width = avail_width,
          height = avail_height,
        }
      end
      return 1, (win_id == active_win)
    end

    -- Find active child
    local active_child_idx = nil
    for i, child in ipairs(node[2]) do
      local _, has_active = process_node(child, 0, 0)
      if has_active then
        active_child_idx = i
        break
      end
    end

    -- Calculate child sizes
    local child_sizes = process_split_dimension(
      node[2],
      node[1] == "row" and avail_width or avail_height,
      active_child_idx
    )

    -- Process children with calculated sizes
    local total_wins, has_active = 0, false
    for i, child in ipairs(node[2]) do
      local child_wins, child_active = process_node(
        child,
        node[1] == "row" and child_sizes[i] or avail_width,
        node[1] == "row" and avail_height or child_sizes[i]
      )
      total_wins = total_wins + child_wins
      has_active = has_active or child_active
    end

    return total_wins, has_active
  end

  process_node(tree, total_width, total_height)
  debug.log("calculate_window_sizes:", vim.inspect(sizes))
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
  debug.log("Start new run.", string.rep("=", 80))
  debug.log("split called with direction:", direction)
  local current = vim.api.nvim_get_current_win()
  debug.log("current window:", debug.format_win(current))

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
    debug.log("found target window", debug.format_win(target_win))
    vim.api.nvim_set_current_win(target_win)
    debug.log("current window:", debug.format_win(vim.api.nvim_get_current_win()))
    debug.log("End of run.", string.rep("=", 80))
    return
  end

  debug.log("target window not found")
  -- Check if new split is allowed
  if not can_split(current, direction) then
    debug.log("Cannot create new split in this direction")
    debug.log("current window:", debug.format_win(vim.api.nvim_get_current_win()))
    debug.log("End of run.", string.rep("=", 80))
    return
  end

  create_split(direction)
  debug.log("current window:", debug.format_win(vim.api.nvim_get_current_win()))
  debug.log("End of run.", string.rep("=", 80))
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

  local explorer = require("w.explorer")
  if not explorer.get_state().ready then
    debug.log("redraw early exit - explorer not ready")
    return
  end

  local sizes = M.calculate_window_sizes()
  for win_id, size in pairs(sizes) do
    if vim.api.nvim_win_is_valid(win_id) then
      vim.api.nvim_win_set_width(win_id, size.width)
      vim.api.nvim_win_set_height(win_id, size.height)
    end
  end
end

return M
