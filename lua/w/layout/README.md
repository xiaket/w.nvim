# Layout Module

A Neovim module that provides window layout management with intelligent window splitting, focusing and resizing.

## Overview

The layout module consists of three main components:
- Public API for window operations
- Core layout algorithms
- Utility functions for window management

## Directory Structure

```
lua/w/layout/
├── init.lua          -- Main entry point and public API
├── core.lua          -- Core layout algorithms and business logic
└── utils.lua         -- Utility functions for window operations
```

## Module Components

### init.lua

Main entry point that exports public API.

Functions:
- `split(direction)`: Split window or focus existing window in specified direction
  - direction: "left" | "right" | "up" | "down"
- `redraw()`: Recalculate and apply window sizes
- `update_previous_active_window()`: Update previous active window record
- `get_previous_active_window()`: Get previous active window handle

### core.lua

Core layout algorithms and window management logic.

Functions:
- `find_target_window(current_win, direction)`: Find target window for focus in direction
- `can_split(current_win, direction)`: Check if new split is allowed in direction
- `calculate_window_sizes()`: Calculate ideal sizes for all windows
- `calculate_split_sizes(total_space, n_splits, active_index)`: Calculate sizes for splits in a container

### utils.lua

Utility functions for window operations and layout analysis.

Window State:
- `update_previous_active_window()`: Update previous active window record
- `get_previous_active_window()`: Get previous active window handle

Basic Operations:
- `is_explorer(win_id)`: Check if window is an explorer window
- `create_split(direction)`: Create new split
- `apply_window_sizes(sizes)`: Apply calculated sizes to windows

Layout Tree Utils:
- `find_window_in_tree(tree, winid, parent)`: Find window node and its parent in layout tree
- `find_directional_leaf(tree, direction)`: Find leaf window in direction
- `find_path_to_window(tree, winid, path)`: Find path from root to target window
- `get_relative_direction(source_win, target_win)`: Get relative direction between windows
- `is_same_node(node1, node2)`: Check if two nodes are the same

## Usage Examples

```lua
-- Split window to the right
require('w.layout').split('right')

-- Focus window to the left if exists, otherwise create new split
require('w.layout').split('left')

-- Redraw windows with golden ratio
require('w.layout').redraw()
```

## Layout Rules

1. Split tree rules:
   - Each split direction can have at most two splits(apart from explorer window)
   - Splits can be nested
   - A horizontal split can only nest vertical splits inside it, and vice versa

2. Explorer window rules:
   - Has fixed width
   - Only allows splits to the right
   - Not affected by split tree rules

3. Window movement rules:
   - When moving focus, start from current split level
   - Search up the split tree if no target found at current level
   - Prefer last active window if multiple targets exist
