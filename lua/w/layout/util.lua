local M = {}

-- Dependencies
local config = require("w.config")
local debug = require("w.debug")

-- Private window state
local prev_active_window = nil

function M.update_previous_active_window()
  local current_win = vim.api.nvim_get_current_win()
  debug.log("previous active window:", prev_active_window, "->", current_win)
  prev_active_window = current_win
end

function M.get_previous_active_window()
  return prev_active_window
end

-- Internal helpers
--- Find a window node and its parent node in the window tree
---@param tree table The window layout tree from vim.fn.winlayout()
---@param winid number The window ID to find
---@param parent table|nil The parent node of current tree node
---@return table|nil node The found window node
---@return table|nil parent The parent node of found window
function M.find_window_in_tree(tree, winid, parent)
  local type = tree[1]
  if type == "leaf" then
    if tree[2] == winid then
      return tree, parent
    end
    return nil, nil
  end

  for _, subtree in ipairs(tree[2]) do
    local found, found_parent = M.find_window_in_tree(subtree, winid, tree)
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
function M.find_directional_leaf(tree, direction)
  while tree[1] ~= "leaf" do
    local children = tree[2]
    if not children or #children == 0 then
      return nil
    end
    tree = children[direction == "left" and #children or 1]
  end
  return tree[2]
end

--- Find the path from root to target window in the window tree
---
--- This function traverses the window layout tree and finds the sequence of nodes
--- that lead from root to the target window. For each node in the path, it records
--- both the node itself and the index of the child that leads to the target window.
---
--- For example, given the following window layout:
--- +---+---+---+
--- |   |   B   |
--- | A +---+---+
--- |   | C | D |
--- +---+---+---+
---
--- The window tree would look like:
--- {
---   "row",                              -- root node
---   {
---     { "leaf", 1001 },                -- A
---     { "col",                         -- B|C|D vertical split container
---       {
---         { "leaf", 1002 },            -- B
---         { "row",                     -- C|D horizontal split container
---           {
---             { "leaf", 1003 },        -- C
---             { "leaf", 1004 }         -- D
---           }
---         }
---       }
---     }
---   }
--- }
---
--- For window C (window ID 1003), the function would return:
--- {
---   {                      -- root level
---     index = 2,          -- BCD is the second item in root row
---     node = <root row node>
---   },
---   {                      -- first split level
---     index = 2,          -- CD is the second item in the B|C|D column
---     node = <col node>
---   },
---   {                      -- second split level
---     index = 1,          -- C is the first item in C|D row
---     node = <row node>
---   }
--- }
---
--- This path information is used for:
--- 1. Finding relative positions of windows
--- 2. Making intelligent decisions about window navigation
--- 3. Understanding the nested split structure
---
---@param tree table Window layout tree from vim.fn.winlayout()
---@param winid number Window handle to find
---@param path table Path accumulator (initially empty table)
---@return table|nil Array of {node, index} pairs from root to window, or nil if not found
function M.find_path_to_window(tree, winid, path)
  debug.log("tree:", vim.inspect(tree), "winid:", winid, "path:", vim.inspect(path))
  local type = tree[1]
  if type == "leaf" then
    if tree[2] == winid then
      debug.log("found path: ", vim.inspect(path))
      return path
    end
    debug.log("path not found")
    return nil
  end

  debug.log("Entering loop:", vim.inspect(tree[2]))
  for i, child in ipairs(tree[2]) do
    local child_path = vim.deepcopy(path)
    table.insert(child_path, { node = tree, index = i })
    local result = M.find_path_to_window(child, winid, child_path)
    if result then
      return result
    end
  end
  return nil
end

--- Get relative direction of target window compared to source window
---@param source_win number Source window handle
---@param target_win number Target window handle
---@return string|nil direction "left"|"right"|"up"|"down" or nil if not related
function M.get_relative_direction(source_win, target_win)
  local tree = vim.fn.winlayout()
  local source_path = M.find_path_to_window(tree, source_win, {})
  local target_path = M.find_path_to_window(tree, target_win, {})
  debug.log("source path:", vim.inspect(source_path))
  debug.log("target path:", vim.inspect(target_path))

  if not source_path or not target_path then
    return nil
  end

  local is_same_node = function(node1, node2)
    if node1[1] == "leaf" and node2[1] == "leaf" then
      return node1[2] == node2[2]
    end
    return node1[1] == node2[1]
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

---Check if window is an explorer window
---@param win_id number window ID to check
---@return boolean is explorer window
function M.is_explorer(win_id)
  debug.log(string.format("checking if win %d is explorer", win_id))
  if not win_id or not vim.api.nvim_win_is_valid(win_id) then
    debug.log("invalid window")
    return false
  end
  local buf = vim.api.nvim_win_get_buf(win_id)
  local ft = vim.api.nvim_buf_get_option(buf, "filetype")
  debug.log(string.format("window %d buffer %d filetype: %s", win_id, buf, ft))
  return ft == config.const.filetype
end

-- Helper function to find the relevant split parent using path information
function M.get_dimensional_parent(tree, win_id, want_row)
  local path = M.find_path_to_window(tree, win_id, {})
  if not path then
    return nil
  end

  -- Find first matching split from path
  for _, step in ipairs(path) do
    if step.node[1] == (want_row and "row" or "col") then
      return step.node
    end
  end
  return nil
end

-- Helper function to get the first leaf window ID from a tree node
local function get_first_leaf_win(node)
  local first_leaf = node
  while first_leaf[1] ~= "leaf" do
    first_leaf = first_leaf[2][1]
  end
  return first_leaf[2]
end

-- Helper function to adjust window sizes in a split
function M.adjust_size(current_win, parent, is_row)
  if not parent then
    return
  end

  local siblings = parent[2]
  if #siblings < 2 then
    return
  end

  -- Calculate total size, excluding explorer window when adjusting widths
  local total_size = 0
  local non_explorer_count = 0
  for _, node in ipairs(siblings) do
    local win_id
    if node[1] == "leaf" then
      win_id = node[2]
    else
      win_id = get_first_leaf_win(node)
    end

    local size = is_row and vim.api.nvim_win_get_width(win_id) or vim.api.nvim_win_get_height(win_id)

    -- When adjusting widths (is_row), exclude explorer window from total
    if is_row and M.is_explorer(win_id) then
      debug.log("excluding explorer window from size calculation:", win_id)
    else
      total_size = total_size + size
      non_explorer_count = non_explorer_count + 1
    end
  end

  -- If only one non-explorer window in horizontal split, no need to adjust
  if is_row and non_explorer_count < 2 then
    debug.log("only one non-explorer window, skipping size adjustment")
    return
  end

  -- Calculate target size
  local target_size = math.floor(total_size * config.options.split_ratio)

  -- Adjust window sizes
  for _, node in ipairs(siblings) do
    if node[1] == "leaf" and node[2] == current_win then
      -- Direct adjustment for current window
      if is_row then
        vim.api.nvim_win_set_width(current_win, target_size)
      else
        vim.api.nvim_win_set_height(current_win, target_size)
      end
      break
    elseif node[1] ~= "leaf" then
      -- Check if nested split contains current window
      local found = M.find_window_in_tree(node, current_win, nil)
      if found then
        -- Adjust first leaf window of the nested split
        local first_leaf = node
        while first_leaf[1] ~= "leaf" do
          first_leaf = first_leaf[2][1]
        end
        if is_row then
          vim.api.nvim_win_set_width(first_leaf[2], target_size)
        else
          vim.api.nvim_win_set_height(first_leaf[2], target_size)
        end
        break
      end
    end
  end
end

-- Utility functions for color manipulation
local function hex_to_rgb(hex)
  hex = hex:gsub("#", "")
  return tonumber("0x" .. hex:sub(1, 2)),
    tonumber("0x" .. hex:sub(3, 4)),
    tonumber("0x" .. hex:sub(5, 6))
end

local function rgb_to_hex(r, g, b)
  return string.format("#%02x%02x%02x", r, g, b)
end

function M.adjust_brightness(hex, percent)
  local r, g, b = hex_to_rgb(hex)
  r = math.min(255, math.max(0, r * (1 + percent / 100)))
  g = math.min(255, math.max(0, g * (1 + percent / 100)))
  b = math.min(255, math.max(0, b * (1 + percent / 100)))
  return rgb_to_hex(r, g, b)
end

-- Get current theme's background color
function M.get_background_color()
  local normal_hl = vim.api.nvim_get_hl_by_name("Normal", true)
  return normal_hl.background and string.format("#%06x", normal_hl.background) or "#192330"
end

return M
