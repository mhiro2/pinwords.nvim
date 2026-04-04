# pinwords.nvim

<a href="https://deepwiki.com/mhiro2/pinwords.nvim"><img src="https://img.shields.io/badge/DeepWiki-mhiro2%2Fpinwords.nvim-blue.svg?logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACwAAAAyCAYAAAAnWDnqAAAAAXNSR0IArs4c6QAAA05JREFUaEPtmUtyEzEQhtWTQyQLHNak2AB7ZnyXZMEjXMGeK/AIi+QuHrMnbChYY7MIh8g01fJoopFb0uhhEqqcbWTp06/uv1saEDv4O3n3dV60RfP947Mm9/SQc0ICFQgzfc4CYZoTPAswgSJCCUJUnAAoRHOAUOcATwbmVLWdGoH//PB8mnKqScAhsD0kYP3j/Yt5LPQe2KvcXmGvRHcDnpxfL2zOYJ1mFwrryWTz0advv1Ut4CJgf5uhDuDj5eUcAUoahrdY/56ebRWeraTjMt/00Sh3UDtjgHtQNHwcRGOC98BJEAEymycmYcWwOprTgcB6VZ5JK5TAJ+fXGLBm3FDAmn6oPPjR4rKCAoJCal2eAiQp2x0vxTPB3ALO2CRkwmDy5WohzBDwSEFKRwPbknEggCPB/imwrycgxX2NzoMCHhPkDwqYMr9tRcP5qNrMZHkVnOjRMWwLCcr8ohBVb1OMjxLwGCvjTikrsBOiA6fNyCrm8V1rP93iVPpwaE+gO0SsWmPiXB+jikdf6SizrT5qKasx5j8ABbHpFTx+vFXp9EnYQmLx02h1QTTrl6eDqxLnGjporxl3NL3agEvXdT0WmEost648sQOYAeJS9Q7bfUVoMGnjo4AZdUMQku50McDcMWcBPvr0SzbTAFDfvJqwLzgxwATnCgnp4wDl6Aa+Ax283gghmj+vj7feE2KBBRMW3FzOpLOADl0Isb5587h/U4gGvkt5v60Z1VLG8BhYjbzRwyQZemwAd6cCR5/XFWLYZRIMpX39AR0tjaGGiGzLVyhse5C9RKC6ai42ppWPKiBagOvaYk8lO7DajerabOZP46Lby5wKjw1HCRx7p9sVMOWGzb/vA1hwiWc6jm3MvQDTogQkiqIhJV0nBQBTU+3okKCFDy9WwferkHjtxib7t3xIUQtHxnIwtx4mpg26/HfwVNVDb4oI9RHmx5WGelRVlrtiw43zboCLaxv46AZeB3IlTkwouebTr1y2NjSpHz68WNFjHvupy3q8TFn3Hos2IAk4Ju5dCo8B3wP7VPr/FGaKiG+T+v+TQqIrOqMTL1VdWV1DdmcbO8KXBz6esmYWYKPwDL5b5FA1a0hwapHiom0r/cKaoqr+27/XcrS5UwSMbQAAAABJRU5ErkJggg==" alt="DeepWiki"></a>
[![GitHub Release](https://img.shields.io/github/release/mhiro2/pinwords.nvim?style=flat)](https://github.com/mhiro2/pinwords.nvim/releases/latest)
[![CI](https://github.com/mhiro2/pinwords.nvim/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/mhiro2/pinwords.nvim/actions/workflows/ci.yaml)
<img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT License">

> Pin words you want to keep in your head.

`pinwords.nvim` is a **Neovim-native, persistent (until cleared) word highlighter** designed to help you externalize your focus while reading or reviewing code.

Unlike navigation-oriented word highlighters, pinwords lets you **explicitly mark and keep multiple keywords visible** until you decide to clear them.

## ✨ Features

- 🔢 **Slot-based highlights** (default: 1–9)
- 🧷 **Auto allocation** for single-key pinning
- ✨ **Visual flash feedback** on pin/unpin success
- 📌 **Persistent** highlights (until cleared; global across all buffers, not saved across sessions)
- 🧠 Designed for **thinking, reading, and reviewing**, not navigation
- 🪟 Correct behavior across **split windows**
- ⚡ Pure **Neovim native API** (Lua-only, no Vim script)
- 🔍 **Grep integration** — search project-wide with pinned words via telescope/snacks/fzf-lua
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
    map("n", "<leader>p", function() pinwords.set() end, { desc = "Pin word toggle" })

    -- Pin selected text in visual mode
    map("x", "<leader>p", ":PinWord<cr>", { desc = "Pin selection" })

    -- Toggle cursor-word highlight (follows cursor, works in insert mode)
    map("n", "<leader>j", function() pinwords.cword_toggle() end, { desc = "Toggle cword highlight" })
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
| `toggle_same` | `true`, `false` | If the same raw text with the same match semantics is already pinned, unpin it instead of adding a new slot. |

#### Custom Highlight Colors

Customize highlight colors per slot:

```lua
require("pinwords").setup({
  colors = {
    [1] = "#ff6b6b",                           -- hex string
    [2] = { bg = "#1dd1a1", fg = "#000000" },  -- with foreground color
    [3] = { bg = "#54a0ff", bold = true },     -- with style attributes
    [4] = { sp = "#ff6b6b", undercurl = true }, -- colored undercurl (no background)
    cword = "#ffd166",                         -- cursor word color
  },
})
```

Available style attributes: `bold`, `italic`, `underline`, `undercurl`, `underdouble`, `underdotted`, `underdashed`, `strikethrough`, `sp`, `ctermbg`, `ctermfg`.

#### Visual Flash Feedback

Show a short flash when pin/unpin operations succeed:

```lua
require("pinwords").setup({
  flash = {
    enabled = true,
    timeout_ms = 120,
    hl_group = "PinWordFlash",
    priority = 250,
  },
})
```

| Option | Type | Default | Behavior |
| --- | --- | --- | --- |
| `enabled` | boolean | `true` | Enables/disables flash feedback. |
| `timeout_ms` | integer | `120` | Flash duration in milliseconds. `0` clears on the next event loop tick. |
| `hl_group` | string | `PinWordFlash` | Highlight group used for flash. |
| `priority` | integer | `250` | Match priority for flash highlighting. |

Default `PinWordFlash` is linked to `IncSearch`.

#### Jump Navigation

Jump between pinned word occurrences:

```lua
-- Recommended key mappings
vim.keymap.set("n", "]p", function() require("pinwords").jump_next() end, { desc = "Next pinned word" })
vim.keymap.set("n", "[p", function() require("pinwords").jump_prev() end, { desc = "Prev pinned word" })

-- Jump to specific slot (optional)
vim.keymap.set("n", "]1", function() require("pinwords").jump_next(1) end, { desc = "Next slot 1" })
vim.keymap.set("n", "[1", function() require("pinwords").jump_prev(1) end, { desc = "Prev slot 1" })
```

#### Grep / Live Grep

Search your project using pinned words while preserving each slot's match semantics:

```lua
vim.keymap.set("n", "<leader>pg", function() require("pinwords").grep() end, { desc = "Grep pinned words" })
vim.keymap.set("n", "<leader>pl", function() require("pinwords").live_grep() end, { desc = "Live grep pinned words" })
```

See the [Grep Integration](#-grep-integration) section for details.

#### Picker Integrations

Enable auto-loading of optional picker extensions (disabled by default to avoid forcing dependencies at startup):

```lua
require("pinwords").setup({
  -- Telescope.nvim integration
  telescope = {
    enabled = true,
  },
  -- Snacks.nvim integration
  snacks = {
    enabled = true,
  },
  -- fzf-lua integration
  fzf_lua = {
    enabled = true,
  },
})
```

See the [Picker Integrations](#-picker-integrations) section for usage details.

## 🛠 Usage

### Commands

| Command                 | Description           |
| ----------------------- | --------------------- |
| `:PinWord`              | Auto pin (toggle same). In visual mode, pins selection. |
| `:PinWord {slot}`       | Pin word under cursor (visual mode uses selection). |
| `:PinWordSymbol`        | Pin symbol at cursor using Treesitter (auto allocation). |
| `:PinWordSymbol {slot}` | Pin symbol at cursor to specific slot. Falls back to cword when no parser or no symbol found. |
| `:UnpinWord`            | Unpin word under cursor (warns when multiple slots share the same raw text) |
| `:UnpinWord {slot}`     | Clear slot            |
| `:UnpinAllWords`        | Clear all             |
| `:PinWordList`          | Interactive picker for global pinned words (falls back to `vim.ui.select`) |
| `:PinWordCwordToggle`   | Toggle cursor-word highlight (current window, follows cursor incl. insert) |
| `:PinWordNext [slot]`   | Jump to next pinned word occurrence |
| `:PinWordPrev [slot]`   | Jump to previous pinned word occurrence |
| `:PinWordGrep [slot]`   | Grep pinned words across project |
| `:PinWordLiveGrep [slot]` | Live grep pinned words across project |

### Health Check

Run `:checkhealth pinwords` to validate current config values and optional picker dependencies.

### Lua API

```lua
require("pinwords").set()          -- auto allocation
require("pinwords").set(slot)
require("pinwords").set(nil, { source = "symbol" }) -- Treesitter symbol pin
require("pinwords").toggle()       -- alias for auto set
require("pinwords").cword_toggle() -- toggle cursor-word highlight
require("pinwords").unpin()        -- unpin word under cursor
require("pinwords").clear(slot)
require("pinwords").clear_all()
require("pinwords").list()
require("pinwords").pick()         -- open interactive picker
require("pinwords").jump_next()    -- jump to next pinned word
require("pinwords").jump_next(slot) -- jump to next occurrence of specific slot
require("pinwords").jump_prev()    -- jump to previous pinned word
require("pinwords").jump_prev(slot)
require("pinwords").grep()         -- grep all pinned words (OR combined, per-slot semantics preserved)
require("pinwords").grep({ slot = 1 }) -- grep specific slot
require("pinwords").live_grep()    -- live grep with pinned words as initial query
require("pinwords").live_grep({ slot = 1 })
```

The second argument to `set()` accepts a table with the following fields:

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `raw` | `string` | word under cursor | Explicit text to pin (bypasses `<cword>`). |
| `whole_word` | `boolean` | config value | Match whole words only (`\<...\>`). |
| `case_sensitive` | `boolean` | config value | Case-sensitive matching. |
| `source` | `"cword"\|"symbol"` | `"cword"` | Use Treesitter symbol instead of `<cword>`. |

```lua
-- Pin an arbitrary string (raw mode)
require("pinwords").set(1, { raw = "TODO", whole_word = true })

-- Pin case-sensitively
require("pinwords").set(nil, { case_sensitive = true })
```

## 🔍 Picker Integrations

pinwords.nvim provides optional integrations with popular picker plugins for browsing and managing pinned words through a fuzzy finder interface.

> [!NOTE]
> All picker integrations are **completely optional**. pinwords.nvim works perfectly without them — when no picker is enabled, `:PinWordList` uses `vim.ui.select` as a built-in fallback.

### Common Features

All picker integrations provide:
- **List all pinned words**: Shows slot number, word, and actual highlight color
- **Unpin individual words**: Select and unpin entries
- **Clear all**: Clear all pinned words at once
- **Fuzzy search**: Filter by slot number or word text
- **Multi-select**: Select multiple entries and unpin them together

### Common Key Mappings

| Key | Action |
|-----|--------|
| `<Tab>` / `<Shift-Tab>` | Toggle multi-selection |
| `<CR>` / `<Enter>` | Unpin selected word(s) - supports multi-select |
| `<C-d>` | Unpin current word |
| `<C-x>` | Clear all pinned words |
| `<Esc>` / `<C-c>` | Close picker |

### 🔭 Telescope.nvim

[Telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) extension for pinwords.

**Setup** (optional auto-loading):
```lua
require("pinwords").setup({
  telescope = {
    enabled = true,
  },
})
```

**Usage:**
```vim
:Telescope pinwords
```

```lua
vim.keymap.set("n", "<leader>fp", function()
  require("telescope").extensions.pinwords.pinwords()
end, { desc = "Telescope: Pinned words" })
```

### 🍿 Snacks.nvim

[Snacks.nvim](https://github.com/folke/snacks.nvim) picker integration for pinwords.

**Setup** (optional auto-loading):
```lua
require("pinwords").setup({
  snacks = {
    enabled = true,
  },
})
```

**Usage:**
```lua
vim.keymap.set("n", "<leader>fp", function()
  require("pinwords.snacks").picker()
end, { desc = "Snacks: Pinned words" })
```

> [!NOTE]
> To keep multi-select stable in Snacks, pinwords assigns a unique `id` to each entry.

### 🔎 fzf-lua

[fzf-lua](https://github.com/ibhagwan/fzf-lua) integration for pinwords.

**Setup** (optional auto-loading):
```lua
require("pinwords").setup({
  fzf_lua = {
    enabled = true,
  },
})
```

**Usage:**
```lua
vim.keymap.set("n", "<leader>fp", function()
  require("pinwords.fzf_lua").picker()
end, { desc = "fzf-lua: Pinned words" })
```

## 🔍 Grep Integration

Search your entire project using pinned words. All pinned words are combined with OR into a single search pattern, while each slot keeps its own `whole_word` / `case_sensitive` behavior.

### Commands

| Command | Description |
|---------|-------------|
| `:PinWordGrep` | Grep all pinned words (OR combined) |
| `:PinWordGrep {slot}` | Grep a specific slot's word only |
| `:PinWordLiveGrep` | Open live grep with pinned words as the initial query |
| `:PinWordLiveGrep {slot}` | Open live grep with a specific slot's word |

### Picker Backend

Grep uses the same priority as other picker features: **snacks → telescope → fzf-lua → vimgrep (quickfix) fallback**.

No additional configuration is needed — if you have a picker enabled for `:PinWordList`, grep will use the same backend automatically.

> [!NOTE]
> Grep backends are line-oriented, so multi-line pinned words are skipped.
> When no picker backend is available, both commands fall back to one-shot quickfix grep via `rg` when available, then `vimgrep`.
## 🎨 Highlight Groups

```vim
PinWord1 .. PinWord9
PinWordCword
PinWordFlash
```

Fully customizable via standard highlight overrides.

## 📦 Requirements

* Neovim >= 0.10
* No external dependencies
* Optional: [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) for telescope integration
* Optional: [snacks.nvim](https://github.com/folke/snacks.nvim) for snacks picker integration
* Optional: [fzf-lua](https://github.com/ibhagwan/fzf-lua) for fzf-lua picker integration

## 📄 License

MIT License. See [LICENSE](./LICENSE).
