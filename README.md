# nvpic

Display images alongside code in Neovim. A study-oriented plugin that renders images inline using the Kitty graphics protocol.

## Requirements

- Neovim 0.11+
- macOS (clipboard support via `osascript`)
- Terminal with Kitty graphics protocol support (Ghostty, Kitty, WezTerm)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'leeonardoneves/nvpic',
  opts = {},
}
```

## Usage

### Paste an image from clipboard

Copy an image, then run `:NvpicPaste`. A float opens to set scale and alt text. On confirm, the image is saved to `pics/` and a comment block is inserted:

```lua
-- $$pic-start
-- path: pics/a3f8b2.png
-- scale: 0.5
-- alt: Architecture diagram
-- $$pic-end
```

### Pick an existing image

`:NvpicPick` opens a fuzzy picker listing all images in `pics/`.

### Optional Telescope integration

Set `telescope = true` to make `:NvpicPick` use Telescope instead of `vim.ui.select`.

If you also want the direct Telescope picker, load the extension after setup:

```lua
require('telescope').load_extension('nvpic')
```

### Commands

| Command | Description |
| --- | --- |
| `:NvpicPaste` | Paste image from clipboard |
| `:NvpicPick` | Pick image from `pics/` |
| `:NvpicToggle` | Toggle image rendering on/off |
| `:NvpicRefresh` | Force re-render all images |
| `:NvpicClear` | Clear all rendered images |
| `:NvpicInfo` | Show plugin info |

### Default Keymaps

| Key | Action |
| --- | --- |
| `<leader>ip` | Paste |
| `<leader>if` | Pick |
| `<leader>it` | Toggle |
| `<leader>ir` | Refresh |

## Configuration

```lua
require('nvpic').setup({
  pics_dir = 'pics',
  default_scale = 1.0,
  auto_render = true,
  debounce_ms = 200,
  protocol = nil,
  keymaps = {
    paste = '<leader>ip',
    pick = '<leader>if',
    toggle = '<leader>it',
    refresh = '<leader>ir',
  },
  telescope = false,
})
```

`pics_dir` must stay relative to the project root. Stored marker paths are expected to stay inside that directory.

## License

MIT
