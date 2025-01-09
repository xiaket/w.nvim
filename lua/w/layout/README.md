# Layout Module

A Neovim module that provides window layout management with intelligent window splitting, focusing and resizing.

## Overview

The layout module provides:
- Smart window splitting and focusing system
- Golden ratio-based window sizing
- Integration with explorer window
- Window state tracking
- Nested split management

## Directory Structure

```
lua/w/layout/
├── init.lua    -- Main entry point and public API
├── core.lua    -- Core layout algorithms
└── util.lua    -- Utility functions
```

## Module Components

### init.lua

Main entry point that exports:
- `split(direction)`: Split window or focus existing window
- `redraw()`: Apply golden ratio to windows
- `update_previous_active_window()`: Update window tracking
- `get_previous_active_window()`: Get last active window

### core.lua

Core algorithms:
- `find_target_window(current_win, direction)`: Smart window targeting
- `can_split(current_win, direction)`: Split validation
- `create_split(direction)`: Split creation

### util.lua

Utility functions:
- Window state management
- Layout tree analysis
- Window relationship calculations
- Window type checking

## Layout Rules

1. Split Management:
   - Maximum two splits per direction (except explorer)
   - Alternating split directions in nested splits
   - Smart target window selection

2. Window Sizing:
   - Golden ratio (0.618) for active windows
   - Fixed width for explorer window
   - Automatic resizing on window focus

3. Explorer Integration:
   - Fixed position on left side
   - Only allows right splits
   - Preserves layout structure

## Usage Examples

```lua
-- Split into direction or focus existing window
require('w.layout').split('right')
require('w.layout').split('left')
require('w.layout').split('up')
require('w.layout').split('down')

-- Reapply golden ratio
require('w.layout').redraw()

-- Get previous active window
local prev_win = require('w.layout').get_previous_active_window()
```

## Configuration

Configure through main plugin setup:

```lua
require('w').setup({
  split_ratio = 0.618,  -- Golden ratio for window splits
})
