# pinwords.nvim

[![GitHub Release](https://img.shields.io/github/release/mhiro2/pinwords.nvim?style=flat)](https://github.com/mhiro2/pinwords.nvim/releases/latest)
[![CI](https://github.com/mhiro2/pinwords.nvim/actions/workflows/ci.yaml/badge.svg)](https://github.com/mhiro2/pinwords.nvim/actions/workflows/ci.yaml)

> Pin words you want to keep in your head.

`pinwords.nvim` is a **Neovim-native, persistent (until cleared) word highlighter** designed to help you externalize your focus while reading or reviewing code.

Unlike navigation-oriented word highlighters, pinwords lets you **explicitly mark and keep multiple keywords visible** until you decide to clear them.

## ✨ Features

- 🔢 **Slot-based highlights** (default: 1–9)
- 🧷 **Auto allocation** for single-key pinning
- 📌 **Persistent** highlights (until cleared; global across all buffers, not saved across sessions)
- 🧠 Designed for **thinking, reading, and reviewing**, not navigation
- 🪟 Correct behavior across **split windows**
- ⚡ Pure **Neovim native API** (Lua-only, no Vim script)
- 🧩 Clean internal design for future extensions

![movie](https://github.com/user-attachments/assets/5b65e319-f309-4f15-b6ff-806c0148cab6)


## 🧠 Philosophy

Many word-highlighting plugins focus on *navigation*.

**pinwords is different.**

- This plugin is not about jumping to the next word.
- It is about **marking concepts you want to keep in mind**.
- Highlights are **stable, intentional, and user-controlled**.

If you liked [`t9md/vim-quickhl`](https://github.com/t9md/vim-quickhl), this plugin follows the same spirit —
but is redesigned from scratch for modern Neovim.

## 🚀 Setup

### Installation

Using lazy.nvim:

```lua
{
  "mhiro2/pinwords.nvim",
  event = "VeryLazy",
  config = function()
    local pinwords = require("pinwords")
    local map = vim.keymap.set

    -- Initialize plugin
    pinwords.setup()

    -- Auto pin/unpin word under cursor (auto allocation)
    map("n", "<leader>p", pinwords.set, { desc = "Pin word toggle" })

    -- Pin selected text in visual mode
    map("x", "<leader>p", ":PinWord<cr>", { desc = "Pin selection" })

    -- Toggle cursor-word highlight (follows cursor, works in insert mode)
    map("n", "<leader>j", pinwords.cword_toggle, { desc = "Toggle cword highlight" })
  end,
}
```

### Advanced Configuration

#### Explicit Slot Mapping

If you want to target specific slots (1-9) instead of auto allocation:

```lua
vim.keymap.set("n", "<leader>1", "<cmd>PinWord 1<cr>", { desc = "Pin slot 1" })
vim.keymap.set("n", "<leader>u1", "<cmd>UnpinWord 1<cr>", { desc = "Unpin slot 1" })
vim.keymap.set("x", "<leader>1", ":PinWord 1<cr>", { desc = "Pin selection to slot 1" })
```

#### Auto Allocation Options

Customize how slots are allocated when using auto pinning:

```lua
require("pinwords").setup({
  auto_allocation = {
    strategy = "first_empty", -- "first_empty" | "cycle" | "lru"
    on_full = "replace_oldest", -- "replace_oldest" | "replace_last" | "no_op"
    toggle_same = true,
  },
})
```

| Option | Values | Behavior |
| --- | --- | --- |
| `strategy` | `first_empty`, `cycle`, `lru` | Slot selection policy (`lru` replaces least-recently used when full). |
| `on_full` | `replace_oldest`, `replace_last`, `no_op` | What to do when no empty slot is found (applies to `first_empty`/`cycle`). |
| `toggle_same` | `true`, `false` | If the same pattern is already pinned, unpin it instead of adding a new slot. |

#### Telescope Integration

Enable auto-loading of the Telescope extension (disabled by default to avoid forcing a Telescope require during startup):

```lua
require("pinwords").setup({
  telescope = {
    enabled = true,
  },
})
```

## 🛠 Usage

### Commands

| Command                 | Description           |
| ----------------------- | --------------------- |
| `:PinWord`              | Auto pin (toggle same). In visual mode, pins selection. |
| `:PinWord {slot}`       | Pin word under cursor (visual mode uses selection). |
| `:UnpinWord`            | Unpin word under cursor |
| `:UnpinWord {slot}`     | Clear slot            |
| `:UnpinAllWords`        | Clear all             |
| `:PinWordList`          | List active pins      |
| `:PinWordCwordToggle`   | Toggle cursor-word highlight (current window, follows cursor incl. insert) |

### Lua API

```lua
require("pinwords").set()          -- auto allocation
require("pinwords").set(slot)
require("pinwords").toggle()       -- alias for auto set
require("pinwords").cword_toggle() -- toggle cursor-word highlight
require("pinwords").unpin()        -- unpin word under cursor
require("pinwords").clear(slot)
require("pinwords").clear_all()
require("pinwords").list()
```

## 🔭 Telescope Integration

pinwords.nvim includes an optional Telescope.nvim extension for browsing and managing pinned words through a fuzzy finder interface.
To auto-load the extension, set `telescope.enabled = true` in `setup()` and ensure Telescope is installed.

> [!NOTE]
> The Telescope extension is **completely optional**. pinwords.nvim works perfectly without Telescope - the extension only provides an alternative interface if you have Telescope installed.

### Usage

**Via Telescope command:**
```vim
:Telescope pinwords
```

**Via Lua:**
```lua
vim.keymap.set("n", "<leader>fp", function()
  require("telescope").extensions.pinwords.pinwords()
end, { desc = "Telescope: Pinned words" })
```

### Features

- **List all pinned words**: Shows slot number, word, and actual highlight color
- **Unpin individual words**: Press `<CR>` or `<C-d>` on an entry to unpin it
- **Clear all**: Press `<C-x>` to clear all pinned words
- **Fuzzy search**: Filter by slot number or word text
- **Multi-select**: Press `<Tab>` to mark multiple entries, then `<CR>` to unpin all selected

### Key Mappings

| Key | Action |
|-----|--------|
| `<Tab>` | Toggle multi-selection |
| `<CR>` / `<Enter>` | Unpin selected word(s) - supports multi-select |
| `<C-d>` | Unpin selected word (single) |
| `<C-x>` | Clear all pinned words |
| `<Esc>` / `<C-c>` | Close picker |

## 🎨 Highlight Groups

```vim
PinWord1 .. PinWord9
PinWordCword
```

Fully customizable via standard highlight overrides.

## 📦 Requirements

* Neovim >= 0.9
* No external dependencies

## 📄 License

MIT License. See [LICENSE](./LICENSE).
