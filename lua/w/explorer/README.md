# Explorer Module

A Neovim module that provides a file explorer with intelligent window management integration.

## Overview

The explorer module provides a file system navigation interface with the following features:
- Fixed-width window that respects the window layout system
- Directory navigation and file operations
- Integration with window management for opening files
- Configurable key mappings and display options
- File truncation for large directories

## Directory Structure

```
lua/w/explorer/
├── init.lua       -- Main entry point and public API
├── actions.lua    -- Core file/directory operations
├── autocmd.lua    -- Auto-commands and key mappings
├── fs.lua         -- File system operations
├── state.lua      -- Explorer state management
└── ui.lua         -- UI creation and management
```

## Module Components

### init.lua
Main entry point that exports the public API:
- `open(dir?)`: Open explorer window, optionally at specified directory
- `close()`: Close explorer window
- `toggle_explorer()`: Toggle explorer window
- `get_window()`: Get explorer window handle
- `get_buffer()`: Get explorer buffer handle
- `get_current_dir()`: Get current directory path
- `get_last_position()`: Get last cursor position

### actions.lua
Core file and directory operations:
- `refresh_display(dir, ignore_max?)`: Refresh explorer with directory contents
- `enter_dir(dir)`: Enter a directory
- `go_up()`: Navigate to parent directory
- `open_current()`: Open file/directory under cursor
- `find_window_for_file(current_win)`: Find appropriate window to open file

### autocmd.lua
Auto-commands and key mapping management:
- `setup_buffer_autocmds(buf)`: Set up buffer auto-commands
- `setup_buffer_keymaps(buf)`: Set up buffer key mappings
- `setup_truncation_keymap(buf, is_truncated)`: Set up truncation handling

### fs.lua
File system operations:
- `read_dir(path, ignore_max?)`: Read directory contents with sorting
- `is_valid_directory(path)`: Check if path is valid directory
- `normalize_path(path)`: Normalize path to absolute form without trailing slash

### state.lua
Explorer state management:
- Window handle management
- Buffer handle management
- Current directory tracking
- Cursor position tracking

### ui.lua
UI management:
- `create_window()`: Create explorer window
- `ensure_buffer()`: Ensure explorer buffer exists
- `display_files(files, is_truncated)`: Display file list
- `highlight_current_file()`: Highlight current file in explorer

## Usage

```lua
-- Open explorer in current directory
require('w.explorer').open()

-- Open explorer in specific directory
require('w.explorer').open('/path/to/dir')

-- Toggle explorer
require('w.explorer').toggle_explorer()
```

## Default Key Mappings

- `q`: Close explorer
- `h`: Go up one directory
- `<CR>`: Open file/directory
- `j`: Load more files (when list is truncated) (not configurable)

## Configuration

The explorer can be configured through the main plugin configuration:

```lua
require('w').setup({
  explorer = {
    window_width = 25,    -- Width of explorer window
    max_files = 100,      -- Maximum files to display by default
    show_hidden = true,   -- Show hidden files
    keymaps = {
      close = { "q" },
      go_up = { "h" },
      open = { "<CR>" }
    }
  }
})
```
