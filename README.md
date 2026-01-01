# pinwords.nvim

[![GitHub Release](https://img.shields.io/github/release/mhiro2/pinwords.nvim?style=flat)](https://github.com/mhiro2/pinwords.nvim/releases/latest)
[![CI](https://github.com/mhiro2/pinwords.nvim/actions/workflows/ci.yaml/badge.svg)](https://github.com/mhiro2/pinwords.nvim/actions/workflows/ci.yaml)

> Pin words you want to keep in your head.

`pinwords.nvim` is a **Neovim-native, persistent (until cleared) word highlighter** designed to help you externalize your focus while reading or reviewing code.

Unlike navigation-oriented word highlighters, pinwords lets you **explicitly mark and keep multiple keywords visible** until you decide to clear them.

## ✨ Features

- 🔢 **Slot-based highlights** (default: 1–9)
- 🧷 **Auto allocation** for single-key pinning
- 📌 **Persistent** highlights (until cleared; buffer-local, not saved across sessions)
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
  version = "0.1.0",
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
