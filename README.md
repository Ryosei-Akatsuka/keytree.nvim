[日本語](README.ja.md)

> [!WARNING]
> This plugin was created by generative AI (Claude).
> The author has not performed a detailed review, and it has only been verified in a limited environment (Neovim 0.12.5 / macOS).
> Use at your own risk. Bug reports and suggestions for improvement are welcome.

# keytree.nvim

A Neovim plugin that displays the currently effective keymaps as a tree in the style of `eza -T`.

```text
Neovim キーマップ  leader = <Space>  localleader = \  73 件
[config] = 設定（グローバル）   [buffer] = 設定（バッファ）   [default] = Neovim 標準

NORMAL  49
├── <leader>
│   └── f  Find
│       ├── f <leader>ff  Find files  [config]
│       └── g <leader>fg  Live grep  [config]
├── <C-l>  :help CTRL-L-default  [default]
...
```

## Features

- Displays the effective keymaps as a tree, one per mode.
- Tags each keymap with its origin:
  - `[config]`: Global keymaps added or overridden in your config
  - `[buffer]`: Buffer-local keymaps (LSP, gitsigns, etc.)
  - `[default]`: Neovim's built-in keymaps
- Lets you add descriptions to key prefixes (e.g. `<leader>f` → `Find`).
- Omits your config keymaps that have no description (`desc`), keeping the output less noisy.

## Requirements

- Neovim 0.10 or later (uses `vim.system`)

## Installation

Example with lazy.nvim:

```lua
{
  "Ryosei-Akatsuka/keytree.nvim",
  cmd = "KeymapTree",
  main = "keytree",
  opts = {
    group_labels = {
      ["<leader>f"] = "Find",
    },
  },
}
```

To load a local directory directly, use `dir = "/path/to/keytree.nvim"` instead of `"Ryosei-Akatsuka/keytree.nvim"`.

## Configuration

Options accepted by `setup(opts)` and their defaults:

```lua
require("keytree").setup({
  -- Descriptions for key prefixes. Prefixes not listed here show only the key
  group_labels = {},
})
```

## Usage

| Command | Description |
| --- | --- |
| `:KeymapTree` | Show the keymap tree in a floating window |

Press `q` or `<Esc>` inside the window to close it.

## Notes

- On the first display, Neovim's built-in keymaps are collected by running `vim.v.progpath --clean --headless` in a separate process. The result is cached so they can be told apart from your own config. As a result, the first display is somewhat slower.
- `<Plug>` and `<SNR>` mappings are not shown.
- Only buffer-local keymaps of normal buffers that are loaded at the time of display are shown.

## License

[MIT](LICENSE)
