local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

local grep = require("pinwords.grep")

---@param module_name string
---@param value any
---@param fn fun()
local function with_loaded_module(module_name, value, fn)
  local previous = package.loaded[module_name]
  package.loaded[module_name] = value

  local ok, err = pcall(fn)
  package.loaded[module_name] = previous

  if not ok then
    error(err)
  end
end

---@param slot integer
---@param raw string
---@param pattern string
---@return PinwordsSlot
local function slot_entry(slot, raw, pattern)
  -- Mirror how build_entry derives match semantics so these fixtures match real
  -- slots: whole-word wraps the body in \< \>, and \V\C marks case sensitivity.
  local body = pattern:sub(5)
  return {
    raw = raw,
    pattern = pattern,
    hl_group = "PinWord" .. slot,
    whole_word = body:sub(1, 2) == "\\<" and body:sub(-2) == "\\>",
    case_sensitive = pattern:sub(1, 4) == "\\V\\C",
  }
end

-- ==========================================================================
-- build_rg_pattern
-- ==========================================================================

T["build_rg_pattern returns nil when no slots"] = function()
  local result = grep.build_rg_pattern({}, nil)
  MiniTest.expect.equality(result, nil)
end

T["build_rg_pattern returns nil for missing slot"] = function()
  local slots = { [1] = slot_entry(1, "foo", "\\V\\Cfoo") }
  local result = grep.build_rg_pattern(slots, 5)
  MiniTest.expect.equality(result, nil)
end

T["build_rg_pattern returns single word for one slot"] = function()
  local slots = { [1] = slot_entry(1, "foo", "\\V\\Cfoo") }
  local result = grep.build_rg_pattern(slots, nil)
  MiniTest.expect.equality(result, "foo")
end

T["build_rg_pattern returns specific slot when specified"] = function()
  local slots = {
    [1] = slot_entry(1, "foo", "\\V\\Cfoo"),
    [2] = slot_entry(2, "bar", "\\V\\Cbar"),
  }
  local result = grep.build_rg_pattern(slots, 2)
  MiniTest.expect.equality(result, "bar")
end

T["build_rg_pattern joins multiple words with OR"] = function()
  local slots = {
    [1] = slot_entry(1, "foo", "\\V\\Cfoo"),
    [2] = slot_entry(2, "bar", "\\V\\Cbar"),
    [3] = slot_entry(3, "baz", "\\V\\Cbaz"),
  }
  local result = grep.build_rg_pattern(slots, nil)
  MiniTest.expect.equality(result, "foo|bar|baz")
end

T["build_rg_pattern sorts by slot number"] = function()
  local slots = {
    [3] = slot_entry(3, "baz", "\\V\\Cbaz"),
    [1] = slot_entry(1, "foo", "\\V\\Cfoo"),
  }
  local result = grep.build_rg_pattern(slots, nil)
  MiniTest.expect.equality(result, "foo|baz")
end

T["build_rg_pattern escapes ripgrep metacharacters"] = function()
  local slots = {
    [1] = slot_entry(1, "foo.bar", "\\V\\Cfoo.bar"),
    [2] = slot_entry(2, "a+b*c", "\\V\\Ca+b*c"),
  }
  local result = grep.build_rg_pattern(slots, nil)
  MiniTest.expect.equality(result, "foo\\.bar|a\\+b\\*c")
end

T["build_rg_pattern escapes parentheses and brackets"] = function()
  local slots = {
    [1] = slot_entry(1, "fn(x)", "\\V\\Cfn(x)"),
    [2] = slot_entry(2, "a[0]", "\\V\\Ca[0]"),
  }
  local result = grep.build_rg_pattern(slots, nil)
  MiniTest.expect.equality(result, "fn\\(x\\)|a\\[0\\]")
end

T["build_rg_pattern escapes pipe and backslash"] = function()
  local slots = {
    [1] = slot_entry(1, "a|b", "\\V\\Ca|b"),
    [2] = slot_entry(2, "c\\d", "\\V\\Cc\\\\d"),
  }
  local result = grep.build_rg_pattern(slots, nil)
  MiniTest.expect.equality(result, "a\\|b|c\\\\d")
end

T["build_rg_pattern escapes caret and dollar"] = function()
  local slots = {
    [1] = slot_entry(1, "^start", "\\V\\C^start"),
    [2] = slot_entry(2, "end$", "\\V\\Cend$"),
  }
  local result = grep.build_rg_pattern(slots, nil)
  MiniTest.expect.equality(result, "\\^start|end\\$")
end

T["build_rg_pattern preserves per-slot match semantics"] = function()
  local slots = {
    [1] = slot_entry(1, "Foo", "\\V\\CFoo"),
    [2] = slot_entry(2, "bar", "\\V\\c\\<bar\\>"),
  }
  local result = grep.build_rg_pattern(slots, nil)
  MiniTest.expect.equality(result, "Foo|(?i:\\bbar\\b)")
end

T["build_rg_pattern only adds word boundaries next to keyword characters"] = function()
  local slots = {
    [1] = slot_entry(1, "-foo", "\\V\\C-foo\\>"),
    [2] = slot_entry(2, "foo-", "\\V\\C\\<foo-"),
    [3] = slot_entry(3, "--", "\\V\\C--"),
  }
  slots[1].whole_word = true
  slots[2].whole_word = true
  slots[3].whole_word = true
  local result = grep.build_rg_pattern(slots, nil)
  MiniTest.expect.equality(result, "-foo\\b|\\bfoo-|--")
end

-- ==========================================================================
-- build_vim_pattern
-- ==========================================================================

T["build_vim_pattern returns nil when no slots"] = function()
  local result = grep.build_vim_pattern({}, nil)
  MiniTest.expect.equality(result, nil)
end

T["build_vim_pattern uses very nomagic with OR alternation"] = function()
  local slots = {
    [1] = slot_entry(1, "foo.bar", "\\V\\Cfoo.bar"),
    [2] = slot_entry(2, "a+b*c", "\\V\\Ca+b*c"),
  }
  local result = grep.build_vim_pattern(slots, nil)
  MiniTest.expect.equality(result, "\\V\\(\\Cfoo.bar\\|\\Ca+b*c\\)")
end

T["build_vim_pattern keeps slash and literal pipe in words"] = function()
  local slots = {
    [1] = slot_entry(1, "foo/bar", "\\V\\Cfoo/bar"),
    [2] = slot_entry(2, "a|b", "\\V\\Ca|b"),
  }
  local result = grep.build_vim_pattern(slots, nil)
  MiniTest.expect.equality(result, "\\V\\(\\Cfoo/bar\\|\\Ca|b\\)")
end

T["build_vim_pattern applies whole-word prefixes"] = function()
  local slots = {
    [1] = slot_entry(1, "foo", "\\V\\C\\<foo\\>"),
  }
  local result = grep.build_vim_pattern(slots, nil)
  MiniTest.expect.equality(result, "\\V\\C\\<foo\\>")
end

T["build_vim_pattern preserves mixed slot semantics"] = function()
  local slots = {
    [1] = slot_entry(1, "Foo", "\\V\\CFoo"),
    [2] = slot_entry(2, "bar", "\\V\\c\\<bar\\>"),
  }
  local result = grep.build_vim_pattern(slots, nil)
  MiniTest.expect.equality(result, "\\V\\(\\CFoo\\|\\c\\<bar\\>\\)")
end

T["build_vim_pattern only adds word boundaries next to keyword characters"] = function()
  local slots = {
    [1] = slot_entry(1, "-foo", "\\V\\C-foo\\>"),
  }
  slots[1].whole_word = true
  local result = grep.build_vim_pattern(slots, nil)
  MiniTest.expect.equality(result, "\\V\\C-foo\\>")
end

-- ==========================================================================
-- Command registration
-- ==========================================================================

T["PinWordGrep command is registered"] = function()
  helpers.setup_buffer({ "foo bar baz" })
  -- Read the description via the API rather than parsing `:command` output,
  -- whose column wrapping/truncation varies across Neovim versions. Newer
  -- Neovim exposes the description in `desc`; older Neovim put it in
  -- `definition`, so check both.
  local cmd = vim.api.nvim_get_commands({ builtin = false }).PinWordGrep
  MiniTest.expect.equality(cmd ~= nil, true)
  local description = (cmd.desc or "") .. (cmd.definition or "")
  MiniTest.expect.equality(description:find("Grep pinned words across project.", 1, true) ~= nil, true)
end

T["PinWordLiveGrep command is registered"] = function()
  helpers.setup_buffer({ "foo bar baz" })
  local cmd = vim.api.nvim_get_commands({ builtin = false }).PinWordLiveGrep
  MiniTest.expect.equality(cmd ~= nil, true)
  local description = (cmd.desc or "") .. (cmd.definition or "")
  MiniTest.expect.equality(description:find("Live grep pinned words across project.", 1, true) ~= nil, true)
end

-- ==========================================================================
-- API integration (notify on empty / unsupported)
-- ==========================================================================

T["grep notifies when no words pinned"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  helpers.with_notify_override(function(notified)
    require("pinwords").grep()

    MiniTest.expect.equality(#notified > 0, true)
    MiniTest.expect.equality(notified[1].msg:find("no pinned words", 1, true) ~= nil, true)
  end)
end

T["live_grep notifies when no words pinned"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  helpers.with_notify_override(function(notified)
    require("pinwords").live_grep()

    MiniTest.expect.equality(#notified > 0, true)
    MiniTest.expect.equality(notified[1].msg:find("no pinned words", 1, true) ~= nil, true)
  end)
end

T["grep rejects multi-line-only pins"] = function()
  helpers.setup_buffer({ "foo bar", "baz qux" })

  local pinwords = require("pinwords")
  pinwords.set(1, { raw = "foo\nbaz", whole_word = false })

  helpers.with_notify_override(function(notified)
    pinwords.grep()

    MiniTest.expect.equality(#notified > 0, true)
    MiniTest.expect.equality(notified[1].msg:find("supports only single-line pinned words", 1, true) ~= nil, true)
    MiniTest.expect.equality(notified[1].level, vim.log.levels.WARN)
  end)
end

T["grep with invalid slot from command shows error"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  helpers.with_notify_override(function(notified)
    vim.cmd("PinWordGrep 0")
    MiniTest.expect.equality(#notified > 0, true)
  end)
end

T["PinWordLiveGrep with invalid slot shows error"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  helpers.with_notify_override(function(notified)
    vim.cmd("PinWordLiveGrep 0")
    MiniTest.expect.equality(#notified > 0, true)
  end)
end

-- ==========================================================================
-- Backend integration
-- ==========================================================================

T["grep preserves per-slot match semantics in ripgrep pattern"] = function()
  helpers.setup_buffer({ "foo FOO bar BAR" })

  local captured = {}
  local fzf_stub = {
    grep = function(opts)
      captured = opts
    end,
    live_grep = function(_opts) end,
  }

  local pinwords = require("pinwords")
  with_loaded_module("fzf-lua", fzf_stub, function()
    with_loaded_module("pinwords.fzf_lua", nil, function()
      pinwords.setup({
        whole_word = false,
        case_sensitive = true,
        telescope = { enabled = false },
        snacks = { enabled = false },
        fzf_lua = { enabled = true },
      })
      pinwords.set(1, { raw = "Foo" })
      pinwords.set(2, { raw = "bar", whole_word = true, case_sensitive = false })
      pinwords.grep()
    end)
  end)

  MiniTest.expect.equality(captured.search, "Foo|(?i:\\bbar\\b)")
end

T["live_grep uses selected slot semantics"] = function()
  helpers.setup_buffer({ "foo FOO bar BAR" })

  local captured = {}
  local fzf_stub = {
    grep = function(_opts) end,
    live_grep = function(opts)
      captured = opts
    end,
  }

  local pinwords = require("pinwords")
  with_loaded_module("fzf-lua", fzf_stub, function()
    with_loaded_module("pinwords.fzf_lua", nil, function()
      pinwords.setup({
        whole_word = false,
        case_sensitive = false,
        telescope = { enabled = false },
        snacks = { enabled = false },
        fzf_lua = { enabled = true },
      })
      pinwords.set(1, { raw = "foo", whole_word = true, case_sensitive = true })
      pinwords.set(2, { raw = "bar", whole_word = false, case_sensitive = false })
      pinwords.live_grep({ slot = 1 })
    end)
  end)

  MiniTest.expect.equality(captured.search, "\\bfoo\\b")
end

T["grep skips multi-line words when searchable slots remain"] = function()
  helpers.setup_buffer({ "foo bar", "baz qux" })

  local captured = {}
  local fzf_stub = {
    grep = function(opts)
      captured = opts
    end,
    live_grep = function(_opts) end,
  }

  local pinwords = require("pinwords")
  with_loaded_module("fzf-lua", fzf_stub, function()
    with_loaded_module("pinwords.fzf_lua", nil, function()
      pinwords.setup({
        whole_word = false,
        case_sensitive = true,
        telescope = { enabled = false },
        snacks = { enabled = false },
        fzf_lua = { enabled = true },
      })
      pinwords.set(1, { raw = "foo\nbaz", whole_word = false })
      pinwords.set(2, { raw = "qux" })

      helpers.with_notify_override(function(notified)
        pinwords.grep()
        MiniTest.expect.equality(captured.search, "qux")
        MiniTest.expect.equality(#notified > 0, true)
        MiniTest.expect.equality(notified[1].msg:find("skipped 1 multi-line pinned word", 1, true) ~= nil, true)
      end)
    end)
  end)
end

-- ==========================================================================
-- Fallback integration
-- ==========================================================================

T["fallback grep prefers ripgrep quickfix and preserves slot semantics"] = function()
  local slots = {
    [1] = slot_entry(1, "foo/bar", "\\V\\cfoo/bar"),
  }

  local captured = {}
  local orig_executable = vim.fn.executable
  local orig_system = vim.system
  local orig_setqflist = vim.fn.setqflist
  local orig_nvim_cmd = vim.api.nvim_cmd
  local orig_schedule = vim.schedule

  vim.fn.executable = function(bin)
    MiniTest.expect.equality(bin, "rg")
    return 1
  end
  vim.system = function(argv, opts, on_exit)
    captured.argv = argv
    captured.opts = opts
    captured.on_exit_kind = type(on_exit)
    if on_exit then
      on_exit({
        code = 0,
        stdout = "lua/pinwords/init.lua:1:1:matched line\n",
        stderr = "",
      })
    end
    return {}
  end
  vim.fn.setqflist = function(_list, action, what)
    captured.action = action
    captured.what = what
  end
  vim.api.nvim_cmd = function(cmd, opts)
    captured.command = cmd
    captured.command_opts = opts
  end
  vim.schedule = function(fn)
    fn()
  end

  local ok, err = pcall(function()
    grep._fallback_grep(slots, nil)
  end)

  vim.fn.executable = orig_executable
  vim.system = orig_system
  vim.fn.setqflist = orig_setqflist
  vim.api.nvim_cmd = orig_nvim_cmd
  vim.schedule = orig_schedule

  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(err, nil)
  MiniTest.expect.equality(captured.argv, {
    "rg",
    "--vimgrep",
    "--color=never",
    "--no-heading",
    "(?i:foo/bar)",
  })
  MiniTest.expect.equality(captured.opts.text, true)
  MiniTest.expect.equality(captured.on_exit_kind, "function")
  MiniTest.expect.equality(captured.action, " ")
  MiniTest.expect.equality(captured.what.title, "pinwords grep")
  MiniTest.expect.equality(captured.what.items[1].filename, "lua/pinwords/init.lua")
  MiniTest.expect.equality(captured.what.items[1].lnum, 1)
  MiniTest.expect.equality(captured.what.items[1].col, 1)
  MiniTest.expect.equality(captured.what.items[1].text, "matched line")
  MiniTest.expect.equality(captured.command, { cmd = "copen" })
  MiniTest.expect.equality(captured.command_opts, {})
end

T["fallback grep falls back to vimgrep when ripgrep is unavailable"] = function()
  local slots = {
    [1] = slot_entry(1, "foo/bar", "\\V\\cfoo/bar"),
  }

  local captured = {}
  local orig_executable = vim.fn.executable
  local orig_vimgrep = vim.fn.vimgrep
  local orig_getqflist = vim.fn.getqflist
  local orig_nvim_cmd = vim.api.nvim_cmd
  local saved_wildignore = vim.o.wildignore
  vim.o.wildignore = "*.bak"

  vim.fn.executable = function(bin)
    captured.checked = captured.checked or {}
    captured.checked[bin] = true
    return 0
  end
  vim.fn.vimgrep = function(pattern, files, flags)
    captured.pattern = pattern
    captured.files = files
    captured.flags = flags
    captured.wildignore_during_call = vim.o.wildignore
    return 0
  end
  vim.fn.getqflist = function(_opts)
    return { size = 1 }
  end
  vim.api.nvim_cmd = function(cmd, opts)
    captured.command = cmd
    captured.command_opts = opts
  end

  local ok, err
  helpers.with_notify_override(function(notified)
    ok, err = pcall(function()
      grep._fallback_grep(slots, nil)
    end)
    captured.notified = notified
  end)

  vim.fn.executable = orig_executable
  vim.fn.vimgrep = orig_vimgrep
  vim.fn.getqflist = orig_getqflist
  vim.api.nvim_cmd = orig_nvim_cmd
  local wildignore_after = vim.o.wildignore
  vim.o.wildignore = saved_wildignore

  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(err, nil)
  -- Both ripgrep and git are probed before falling back to vimgrep.
  MiniTest.expect.equality(captured.checked.rg, true)
  MiniTest.expect.equality(captured.checked.git, true)
  MiniTest.expect.equality(captured.pattern, "\\V\\cfoo/bar")
  MiniTest.expect.equality(captured.files, "**/*")
  MiniTest.expect.equality(captured.flags, "gj")
  MiniTest.expect.equality(captured.command, { cmd = "copen" })
  MiniTest.expect.equality(captured.command_opts, {})

  -- wildignore is extended during the call and restored afterwards.
  MiniTest.expect.equality(captured.wildignore_during_call:find("**/node_modules/**", 1, true) ~= nil, true)
  MiniTest.expect.equality(captured.wildignore_during_call:find("**/.git/**", 1, true) ~= nil, true)
  MiniTest.expect.equality(captured.wildignore_during_call:find("*.bak", 1, true) ~= nil, true)
  MiniTest.expect.equality(wildignore_after, "*.bak")

  -- The user is notified that the synchronous fallback is about to run.
  local notified = captured.notified or {}
  local saw_scan_notice = false
  for _, entry in ipairs(notified) do
    if entry.msg:find("ripgrep not available", 1, true) then
      saw_scan_notice = true
      break
    end
  end
  MiniTest.expect.equality(saw_scan_notice, true)
end

T["fallback grep restores wildignore even when vimgrep raises"] = function()
  local slots = {
    [1] = slot_entry(1, "needle", "\\V\\cneedle"),
  }

  local orig_executable = vim.fn.executable
  local orig_vimgrep = vim.fn.vimgrep
  local saved_wildignore = vim.o.wildignore
  vim.o.wildignore = "*.tmp"

  vim.fn.executable = function()
    return 0
  end
  vim.fn.vimgrep = function()
    error("E480: No match: needle")
  end

  helpers.with_notify_override(function() end)

  local ok = pcall(function()
    helpers.with_notify_override(function()
      grep._fallback_grep(slots, nil)
    end)
  end)

  local wildignore_after = vim.o.wildignore

  vim.fn.executable = orig_executable
  vim.fn.vimgrep = orig_vimgrep
  vim.o.wildignore = saved_wildignore

  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(wildignore_after, "*.tmp")
end

T["fallback grep treats ripgrep no-match as info notification"] = function()
  local slots = {
    [1] = slot_entry(1, "notfound", "\\V\\cnotfound"),
  }

  local orig_executable = vim.fn.executable
  local orig_system = vim.system
  local orig_schedule = vim.schedule
  vim.fn.executable = function()
    return 1
  end
  vim.system = function(_argv, _opts, on_exit)
    if on_exit then
      on_exit({ code = 1, stdout = "", stderr = "" })
    end
    return {}
  end
  vim.schedule = function(fn)
    fn()
  end

  local ok, err = pcall(function()
    helpers.with_notify_override(function(notified)
      grep._fallback_grep(slots, nil)
      MiniTest.expect.equality(#notified > 0, true)
      MiniTest.expect.equality(notified[1].msg:find("grep found no matches", 1, true) ~= nil, true)
      MiniTest.expect.equality(notified[1].level, vim.log.levels.INFO)
    end)
  end)

  vim.fn.executable = orig_executable
  vim.system = orig_system
  vim.schedule = orig_schedule

  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(err, nil)
end

T["fallback grep uses async git grep when ripgrep is unavailable"] = function()
  local slots = {
    [1] = {
      raw = "foo",
      pattern = "\\V\\C\\<foo\\>",
      hl_group = "PinWord1",
      whole_word = true,
      case_sensitive = true,
    },
    [2] = {
      raw = "bar",
      pattern = "\\V\\cbar",
      hl_group = "PinWord2",
      whole_word = false,
      case_sensitive = false,
    },
  }

  local captured = { argvs = {} }
  local stdout_by_term = {
    foo = "lua/a.lua:2:5:has foo here\n",
    bar = "lua/b.lua:1:1:bar at start\n",
  }

  local orig_executable = vim.fn.executable
  local orig_system = vim.system
  local orig_schedule = vim.schedule
  local orig_setqflist = vim.fn.setqflist
  local orig_nvim_cmd = vim.api.nvim_cmd
  local orig_fs_root = vim.fs.root

  vim.fn.executable = function(bin)
    return bin == "git" and 1 or 0
  end
  vim.fs.root = function()
    return "/repo"
  end
  vim.system = function(argv, opts, on_exit)
    captured.argvs[#captured.argvs + 1] = argv
    captured.opts = opts
    if on_exit then
      on_exit({ code = 0, stdout = stdout_by_term[argv[#argv]] or "", stderr = "" })
    end
    return {}
  end
  vim.schedule = function(fn)
    fn()
  end
  vim.fn.setqflist = function(_list, action, what)
    captured.action = action
    captured.what = what
  end
  vim.api.nvim_cmd = function(cmd, opts)
    captured.command = cmd
    captured.command_opts = opts
  end

  local ok, err = pcall(function()
    grep._fallback_grep(slots, nil)
  end)

  vim.fn.executable = orig_executable
  vim.system = orig_system
  vim.schedule = orig_schedule
  vim.fn.setqflist = orig_setqflist
  vim.api.nvim_cmd = orig_nvim_cmd
  vim.fs.root = orig_fs_root

  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(err, nil)

  -- One invocation per slot, each carrying its own whole-word/case flags.
  MiniTest.expect.equality(#captured.argvs, 2)
  MiniTest.expect.equality(captured.argvs[1], {
    "git",
    "grep",
    "--no-color",
    "-I",
    "-n",
    "--column",
    "--untracked",
    "--exclude-standard",
    "-F",
    "-w",
    "-e",
    "foo",
  })
  MiniTest.expect.equality(captured.argvs[2], {
    "git",
    "grep",
    "--no-color",
    "-I",
    "-n",
    "--column",
    "--untracked",
    "--exclude-standard",
    "-F",
    "-i",
    "-e",
    "bar",
  })
  MiniTest.expect.equality(captured.opts.text, true)

  -- Per-entry matches are merged and sorted into a single quickfix list.
  MiniTest.expect.equality(captured.action, " ")
  MiniTest.expect.equality(captured.what.title, "pinwords grep")
  MiniTest.expect.equality(#captured.what.items, 2)
  MiniTest.expect.equality(captured.what.items[1].filename, "lua/a.lua")
  MiniTest.expect.equality(captured.what.items[2].filename, "lua/b.lua")
  MiniTest.expect.equality(captured.command, { cmd = "copen" })
end

T["fallback grep reports no matches when git grep finds nothing"] = function()
  local slots = {
    [1] = {
      raw = "zzz",
      pattern = "\\V\\czzz",
      hl_group = "PinWord1",
      whole_word = false,
      case_sensitive = false,
    },
  }

  local orig_executable = vim.fn.executable
  local orig_system = vim.system
  local orig_schedule = vim.schedule
  local orig_fs_root = vim.fs.root

  vim.fn.executable = function(bin)
    return bin == "git" and 1 or 0
  end
  vim.fs.root = function()
    return "/repo"
  end
  vim.system = function(_argv, _opts, on_exit)
    if on_exit then
      on_exit({ code = 1, stdout = "", stderr = "" })
    end
    return {}
  end
  vim.schedule = function(fn)
    fn()
  end

  local ok, err = pcall(function()
    helpers.with_notify_override(function(notified)
      grep._fallback_grep(slots, nil)
      MiniTest.expect.equality(#notified > 0, true)
      MiniTest.expect.equality(notified[#notified].msg:find("grep found no matches", 1, true) ~= nil, true)
      MiniTest.expect.equality(notified[#notified].level, vim.log.levels.INFO)
    end)
  end)

  vim.fn.executable = orig_executable
  vim.system = orig_system
  vim.schedule = orig_schedule
  vim.fs.root = orig_fs_root

  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(err, nil)
end

T["grep boundaries follow the saved pattern, not the current iskeyword"] = function()
  -- Pattern saved without a leading boundary (pinned as `-foo`): widening
  -- iskeyword afterwards must not add one back.
  local slots = {
    [1] = {
      raw = "-foo",
      pattern = "\\V\\C-foo\\>",
      hl_group = "PinWord1",
      whole_word = true,
      case_sensitive = true,
    },
  }

  local saved_iskeyword = vim.bo.iskeyword
  vim.bo.iskeyword = saved_iskeyword .. ",-"

  local rg_pattern = grep.build_rg_pattern(slots, nil)
  local vim_pattern = grep.build_vim_pattern(slots, nil)

  vim.bo.iskeyword = saved_iskeyword

  MiniTest.expect.equality(rg_pattern, "-foo\\b")
  MiniTest.expect.equality(vim_pattern, "\\V\\C-foo\\>")
end

T["grep omits ripgrep boundaries that ripgrep cannot satisfy"] = function()
  -- Pinned in a buffer where `-` was a keyword character, so the saved pattern
  -- has boundaries on both ends; ripgrep's \b can never match next to `-`.
  local slots = {
    [1] = {
      raw = "-foo-",
      pattern = "\\V\\C\\<-foo-\\>",
      hl_group = "PinWord1",
      whole_word = true,
      case_sensitive = true,
    },
  }

  MiniTest.expect.equality(grep.build_rg_pattern(slots, nil), "-foo-")
  MiniTest.expect.equality(grep.build_vim_pattern(slots, nil), "\\V\\C\\<-foo-\\>")
end

T["git grep fallback enforces one-sided boundaries on its results"] = function()
  local slots = {
    [1] = {
      raw = "-foo",
      pattern = "\\V\\C-foo\\>",
      hl_group = "PinWord1",
      whole_word = true,
      case_sensitive = true,
    },
  }

  local captured = { argvs = {} }
  local stdout = table.concat({
    "lua/a.lua:1:3:x -foo y",
    "lua/b.lua:2:1:-foobar",
    "lua/c.lua:3:1:-foobar and -foo",
  }, "\n") .. "\n"

  local orig_executable = vim.fn.executable
  local orig_system = vim.system
  local orig_schedule = vim.schedule
  local orig_setqflist = vim.fn.setqflist
  local orig_nvim_cmd = vim.api.nvim_cmd
  local orig_fs_root = vim.fs.root

  vim.fn.executable = function(bin)
    return bin == "git" and 1 or 0
  end
  vim.fs.root = function()
    return "/repo"
  end
  vim.system = function(argv, _opts, on_exit)
    captured.argvs[#captured.argvs + 1] = argv
    if on_exit then
      on_exit({ code = 0, stdout = stdout, stderr = "" })
    end
    return {}
  end
  vim.schedule = function(fn)
    fn()
  end
  vim.fn.setqflist = function(_list, _action, what)
    captured.what = what
  end
  vim.api.nvim_cmd = function(_cmd, _opts) end

  local ok, err = pcall(function()
    grep._fallback_grep(slots, nil)
  end)

  vim.fn.executable = orig_executable
  vim.system = orig_system
  vim.schedule = orig_schedule
  vim.fn.setqflist = orig_setqflist
  vim.api.nvim_cmd = orig_nvim_cmd
  vim.fs.root = orig_fs_root

  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(err, nil)

  -- `-w` would demand a boundary on the `-` side, so it must not be passed.
  MiniTest.expect.equality(vim.tbl_contains(captured.argvs[1], "-w"), false)

  local items = captured.what.items
  MiniTest.expect.equality(#items, 2)
  MiniTest.expect.equality(items[1].filename, "lua/a.lua")
  MiniTest.expect.equality(items[1].col, 3)
  -- "-foobar" alone is rejected; the line that also contains a bounded "-foo"
  -- is kept with the column moved to that occurrence.
  MiniTest.expect.equality(items[2].filename, "lua/c.lua")
  MiniTest.expect.equality(items[2].col, 13)
end

return T
