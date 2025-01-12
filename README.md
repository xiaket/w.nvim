# w.nvim

A Neovim plugin for efficient window management with intelligent split behavior and an integrated file explorer.

## Features

- **Smart Window Splits**: Automatically manages window splits following intuitive rules:
  - Each split direction (horizontal or vertical) can contain at most two splits
  - Splits can be nested, with horizontal splits containing vertical splits and vice versa
  - Golden ratio-based window sizing for optimal space utilization(configurable)

- **File Explorer**:
  - Dedicated sidebar with configurable width
  - File and directory navigation
  - Directory tree view with icons

- **Window Navigation**:
  - Directional window movement (left, right, up, down)
  - Intelligent focus switching between existing windows

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
  {
    "xiaket/w.nvim",
    cmd = { "WToggleExplorer", "WSplitLeft", "WSplitRight", "WSplitUp", "WSplitDown" },
    opts = {},
  },
```

### Open directory using w.nvim

Please note that with a `BufEnter` event setting, we can open directory using w.nvim. You'll need to:

1. Disable `netrwPlugin` in lazy:

```
require("lazy").setup("packages", {
  -- other settings
  performance = {
    rtp = {
      disabled_plugins = {
        "netrwPlugin",
      },
    },
  },
})
```

2. Enable extra `BufEnter` event in w.nvim:

```
{
  "xiaket/w.nvim",
  cmd = { "WToggleExplorer", "WSplitLeft", "WSplitRight", "WSplitUp", "WSplitDown" },
  event = "BufEnter",
  opts = {},
}
```

### Integration with mini.icons

If you have [mini.icons](https://github.com/echasnovski/mini.icons) installed, the icons in file explorer will use mini.icons instead of the default one. If not, you are encouraged to include it as a dependency:

```
{
  "xiaket/w.nvim",
  cmd = { "WToggleExplorer", "WSplitLeft", "WSplitRight", "WSplitUp", "WSplitDown" },
  event = "BufEnter",
  dependencies = {
    {
      "echasnovski/mini.icons",
      version = false,
    },
  },
  opts = {},
}
```

## Configuration

Here's the default configuration with all available options:

```lua
require('w').setup({
  -- File explorer settings
  explorer_window_width = 25,      -- Width of explorer window
  max_files = 100,                -- Maximum files to show in explorer
  show_hidden = true,             -- Show hidden files
    
  -- Explorer keymaps
  explorer_window_keymaps = {
    close = "q",                -- Close explorer window
    go_up = "h",                -- Go up one directory
    open = "<CR>",              -- Open file/directory
  },
    
  -- Window management settings
  split_ratio = 0.618,            -- Golden ratio for window splits
    
  -- Misc settings
  explorer_window_filetype = "WExplorer", -- Filetype for explorer buffer
  augroup = "W",                  -- Name of autocommand group
})
```

## Usage

### Commands

- `:WToggleExplorer` - Toggle the file explorer
- `:WSplitLeft` - Split window to the left or focus existing left window
- `:WSplitRight` - Split window to the right or focus existing right window
- `:WSplitUp` - Split window upward or focus existing upper window
- `:WSplitDown` - Split window downward or focus existing lower window

### Window Split Rules

1. **Basic Split Behavior**:
   - First split creates two windows
   - Further splits either create new windows or focus existing ones based on direction
   - Explorer window only allows right splits

2. **Layout Examples**:
   ```
   Basic split (A|B):        Nested split:           Complex layout:
   +---+---+               +---+---+               +---+---+---+
   |   |   |               |   | B |               |   |   B   |
   | A | B |               | A +---+               | A +---+---+
   |   |   |               |   | C |               |   | C | D |
   +---+---+               +---+---+               +---+---+---+
   ```

3. **Navigation Rules**:
   - `:WSplitLeft` in B focuses A
   - `:WSplitRight` in A focuses B
   - In nested layouts, navigation follows visual direction
   - Previous active window is tracked for smarter focus switching

### File Explorer Usage

1. **Navigation**:
   - Use `<CR>` (default) to open files or directories
   - Use `h` (default) to go up one directory level

2. **Window Management**:
   - Explorer maintains fixed width
   - Files open in the most recently active window

## Development

### Debug Mode

For development and troubleshooting:

```lua
-- Enable debug logging
require('w.debug').enabled = true

-- Set custom log file path (default: /tmp/w-debug.log)
require('w.debug').log_file_path = '/path/to/debug.log'
```

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Credits

- Layout management inspired by [focus](https://github.com/nvim-focus/focus.nvim)
