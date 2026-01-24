# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

w.nvim is a Neovim plugin for window management with intelligent split behavior and an integrated file explorer. Written in Lua, it uses mini.test for testing.

## Commands

### Testing
```bash
# Run all tests
make test

# Run a single test file
make test_file FILE=tests/explorer/test_explorer.lua

# Run a single test case
make test_case FILE=tests/layout/test_core.lua CASE="should_handle_complex_split_operations"
```

### Debug Mode
Debug logs are written to `/tmp/w-debug.log`. Enable via:
- Config: `debug = true`
- Environment: `W_DEBUG=1 nvim`

## Architecture

### Module Structure
```
lua/w/
├── init.lua       -- Plugin entry point, creates commands and autocommands
├── config.lua     -- Configuration with validation
├── debug.lua      -- Debug logging utilities
├── layout/        -- Window management
│   ├── init.lua   -- Public API: split(), redraw(), window tracking
│   ├── core.lua   -- Split algorithms: find_target_window(), can_split()
│   └── util.lua   -- Window state analysis, layout tree traversal
└── explorer/      -- File explorer
    ├── init.lua   -- Public API: open(), close(), toggle_explorer()
    ├── actions.lua -- File operations: refresh_display(), enter_dir(), open_current()
    ├── state.lua  -- Explorer state (window, buffer, current_dir, cursor)
    ├── fs.lua     -- File system: read_dir(), is_valid_directory()
    ├── ui.lua     -- Window/buffer creation, file display
    └── autocmd.lua -- Buffer keymaps and autocmds
```

### Key Concepts

**Layout Rules**:
- Maximum two splits per direction (horizontal or vertical)
- Splits can nest: horizontal containing vertical and vice versa
- Golden ratio (0.618) applied to active window sizing
- Explorer window is fixed-width on the left, only allows right splits

**State Management**:
- `layout/util.lua` provides window relationship analysis via layout tree traversal
- `explorer/state.lua` manages explorer-specific state (single instance)
- Previous active window is tracked for smarter focus switching

**Testing Pattern**:
Tests use mini.test framework. Test files mirror source structure under `tests/`. Helper utilities in `tests/helpers.lua`.
