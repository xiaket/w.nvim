local M = {}

-- Dependencies
local config = require("w.config")
local debug = require("w.debug")

-- Private window state management
local window_state = (function()
  local prev_active_window = nil

  return {
    -- Update previous active window
    update = function()
      local current_win = vim.api.nvim_get_current_win()
      if prev_active_window == nil then
        debug.log("setting previous active window to", current_win)
        prev_active_window = current_win
      else
        debug.log("updating previous active window from", prev_active_window, "to", current_win)
      end
      prev_active_window = current_win
    end,

    -- Get previous active window
    get = function()
      return prev_active_window
    end,
  }
end)()

function M.update_previous_active_window()
  window_state.update()
end

function M.get_previous_active_window()
  return window_state.get()
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
  if tree[1] == "leaf" then
    return tree[2]
  end
  -- When direction is "left", return the rightmost leaf node
  -- When direction is "right", return the leftmost leaf node
  local children = tree[2]
  local child_index = direction == "left" and #children or 1
  return M.find_directional_leaf(children[child_index], direction)
end

--- Find path from root to target window
---@param tree table Window layout tree
---@param winid number Window handle to find
---@param path table Path accumulator
---@return table|nil path Array of {node, index} pairs from root to window
function M.find_path_to_window(tree, winid, path)
  debug.log("tree:", vim.inspect(tree), "winid:", winid, "path:", vim.inspect(path))
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

return M
