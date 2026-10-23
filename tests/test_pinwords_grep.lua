local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

local grep = require("pinwords.grep")

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

---@param case_sensitive boolean
---@param term string
---@return string
local function rg_term(case_sensitive, term)
  return (case_sensitive and "(?-i:" or "(?i:") .. term .. ")"
end

local B = "(?-u:\\b)"

---@param path string
---@param lnum integer
---@param col integer
---@param text string
---@return string
local function rg_line(path, lnum, col, text)
  return ("%s\0%d:%d:%s\n"):format(path, lnum, col, text)
end

---@param path string
---@param lnum integer
---@param col integer
---@param text string
---@return string
local function git_line(path, lnum, col, text)
  return ("%s\0%d\0%d\0%s\n"):format(path, lnum, col, text)
end

---@param path string
---@return string
local function from_cwd(path)
  return vim.fs.normalize(vim.fs.joinpath(vim.fn.getcwd(), path))
end

---Replace backend discovery and process execution for the fallback. Each
---vim.system call is recorded and answered by `respond`; quickfix writes and
---`:copen` are recorded instead of applied.
---@param opts { executables: table<string, boolean>, respond?: fun(argv: string[], on_exit: fun(result: table)) }
---@param fn fun(captured: { argvs: string[][], opts: table[], qf: table[], opened: integer })
local function with_stubbed_backends(opts, fn)
  local captured = { argvs = {}, opts = {}, qf = {}, opened = 0 }
  local orig = {
    executable = vim.fn.executable,
    system = vim.system,
    schedule = vim.schedule,
    setqflist = vim.fn.setqflist,
    nvim_cmd = vim.api.nvim_cmd,
    fs_root = vim.fs.root,
  }

  vim.fn.executable = function(bin)
    return opts.executables[bin] and 1 or 0
  end
  vim.fs.root = function()
    return "/repo"
  end
  vim.system = function(argv, sys_opts, on_exit)
    captured.argvs[#captured.argvs + 1] = argv
    captured.opts[#captured.opts + 1] = sys_opts
    if opts.respond then
      opts.respond(argv, on_exit)
    end
    return {}
  end
  vim.schedule = function(cb)
    cb()
  end
  vim.fn.setqflist = function(_list, action, what)
    captured.qf[#captured.qf + 1] = { action = action, what = what }
  end
  vim.api.nvim_cmd = function(cmd, _opts)
    if cmd.cmd == "copen" then
      captured.opened = captured.opened + 1
    end
  end

  local ok, err = pcall(fn, captured)

  vim.fn.executable = orig.executable
  vim.system = orig.system
  vim.schedule = orig.schedule
  vim.fn.setqflist = orig.setqflist
  vim.api.nvim_cmd = orig.nvim_cmd
  vim.fs.root = orig.fs_root

  if not ok then
    error(err)
  end
end

---@param stdout string
---@return fun(argv: string[], on_exit: fun(result: table))
local function respond_with(stdout)
  return function(_argv, on_exit)
    on_exit({ code = stdout == "" and 1 or 0, stdout = stdout, stderr = "" })
  end
end

---Create a throwaway project, run fn with it as the cwd, then restore the cwd.
---@param files table<string, string[]>
---@param fn fun(root: string)
local function with_project(files, fn)
  local root = vim.fn.resolve(vim.fn.tempname())
  for path, lines in pairs(files) do
    local full = vim.fs.joinpath(root, path)
    vim.fn.mkdir(vim.fs.dirname(full), "p")
    vim.fn.writefile(lines, full)
  end

  local cwd = vim.fn.getcwd()
  vim.cmd.cd(vim.fn.fnameescape(root))
  local ok, err = pcall(fn, root)
  vim.cmd.cd(vim.fn.fnameescape(cwd))
  vim.fn.delete(root, "rf")

  if not ok then
    error(err)
  end
end

---Restrict backend discovery to `available` while fn runs; the backends that
---remain are executed for real.
---@param available table<string, boolean>
---@param fn fun()
local function with_backends(available, fn)
  local orig_executable = vim.fn.executable
  vim.fn.executable = function(bin)
    if available[bin] == nil then
      return orig_executable(bin)
    end
    return available[bin] and orig_executable(bin) or 0
  end
  local ok, err = pcall(fn)
  vim.fn.executable = orig_executable
  if not ok then
    error(err)
  end
end

---Run a fallback grep against the real backends and return the quickfix items
---as project-relative `path:lnum:col:text` strings, sorted, along with the
---notifications and the backends that were started.
---@param root string
---@param slots table<integer, PinwordsSlot>
---@param after_dispatch? fun()  runs right after the search is started
---@return string[] items, table[] notified, string[] backends
local function run_real_grep(root, slots, after_dispatch)
  vim.fn.setqflist({}, " ", { title = "sentinel" })
  -- List ids are unique, unlike numbers, which stop changing once the stack is full.
  local sentinel_id = vim.fn.getqflist({ id = 0 }).id

  local backends = {}
  local orig_system = vim.system
  vim.system = function(argv, ...)
    backends[#backends + 1] = argv[1]
    return orig_system(argv, ...)
  end

  local notified
  local ok, err = pcall(helpers.with_notify_override, function(n)
    notified = n
    grep._fallback_grep(slots, nil)
    if after_dispatch then
      after_dispatch()
    end
    local done = vim.wait(10000, function()
      local last = n[#n]
      return vim.fn.getqflist({ id = 0 }).id ~= sentinel_id or (last ~= nil and not last.msg:find("scanning", 1, true))
    end, 10)
    MiniTest.expect.equality(done, true)
  end)
  vim.system = orig_system
  -- Whatever happened, no callback of this search may touch a later case.
  grep.teardown()
  pcall(vim.cmd.cclose)
  if not ok then
    error(err)
  end

  local items = {}
  if vim.fn.getqflist({ title = 0 }).title == "pinwords grep" then
    for _, item in ipairs(vim.fn.getqflist()) do
      local name = vim.fn.resolve(vim.api.nvim_buf_get_name(item.bufnr))
      items[#items + 1] = ("%s:%d:%d:%s"):format(vim.fs.relpath(root, name) or name, item.lnum, item.col, item.text)
    end
  else
    -- No results: the user's quickfix list stays current.
    MiniTest.expect.equality(vim.fn.getqflist({ id = 0, title = 0 }), { id = sentinel_id, title = "sentinel" })
  end
  table.sort(items)
  return items, notified, backends
end

---@param root string
local function git_init(root)
  if vim.fn.executable("git") ~= 1 then
    error("git is required for the real backend tests")
  end
  local result = vim.system({ "git", "init", "-q" }, { cwd = root }):wait()
  MiniTest.expect.equality(result.code, 0)
end

---@param raw string
---@param opts { whole_word: boolean, case_sensitive: boolean, slot?: integer }
---@return PinwordsSlot
local function pinned(raw, opts)
  local slot = opts.slot or 1
  return {
    raw = raw,
    pattern = require("pinwords.pattern").build(raw, opts),
    hl_group = "PinWord" .. slot,
    whole_word = opts.whole_word,
    case_sensitive = opts.case_sensitive,
  }
end

local function require_rg()
  if vim.fn.executable("rg") ~= 1 then
    error("ripgrep is required for the real backend tests")
  end
end

-- ==========================================================================
-- build_rg_pattern
-- ==========================================================================

T["build_rg_pattern returns nil when no slots"] = function()
  MiniTest.expect.equality(grep.build_rg_pattern({}, nil), nil)
end

T["build_rg_pattern returns nil for missing slot"] = function()
  local slots = { [1] = slot_entry(1, "foo", "\\V\\Cfoo") }
  MiniTest.expect.equality(grep.build_rg_pattern(slots, 5), nil)
end

T["build_rg_pattern returns single word for one slot"] = function()
  local slots = { [1] = slot_entry(1, "foo", "\\V\\Cfoo") }
  MiniTest.expect.equality(grep.build_rg_pattern(slots, nil), rg_term(true, "foo"))
end

T["build_rg_pattern returns specific slot when specified"] = function()
  local slots = {
    [1] = slot_entry(1, "foo", "\\V\\Cfoo"),
    [2] = slot_entry(2, "bar", "\\V\\Cbar"),
  }
  MiniTest.expect.equality(grep.build_rg_pattern(slots, 2), rg_term(true, "bar"))
end

T["build_rg_pattern joins multiple words with OR in slot order"] = function()
  local slots = {
    [3] = slot_entry(3, "baz", "\\V\\Cbaz"),
    [1] = slot_entry(1, "foo", "\\V\\Cfoo"),
    [2] = slot_entry(2, "bar", "\\V\\cbar"),
  }
  MiniTest.expect.equality(
    grep.build_rg_pattern(slots, nil),
    rg_term(true, "foo") .. "|" .. rg_term(false, "bar") .. "|" .. rg_term(true, "baz")
  )
end

T["build_rg_pattern escapes ripgrep metacharacters"] = function()
  local slots = {
    [1] = slot_entry(1, "foo.bar", "\\V\\Cfoo.bar"),
    [2] = slot_entry(2, "a+b*c", "\\V\\Ca+b*c"),
    [3] = slot_entry(3, "fn(x)", "\\V\\Cfn(x)"),
    [4] = slot_entry(4, "a[0]", "\\V\\Ca[0]"),
    [5] = slot_entry(5, "a|b", "\\V\\Ca|b"),
    [6] = slot_entry(6, "c\\d", "\\V\\Cc\\\\d"),
    [7] = slot_entry(7, "^start", "\\V\\C^start"),
    [8] = slot_entry(8, "end$", "\\V\\Cend$"),
  }
  local expected = {}
  for _, term in ipairs({ "foo\\.bar", "a\\+b\\*c", "fn\\(x\\)", "a\\[0\\]", "a\\|b", "c\\\\d", "\\^start", "end\\$" }) do
    expected[#expected + 1] = rg_term(true, term)
  end
  MiniTest.expect.equality(grep.build_rg_pattern(slots, nil), table.concat(expected, "|"))
end

T["build_rg_pattern makes case sensitivity explicit for every slot"] = function()
  local slots = {
    [1] = slot_entry(1, "Foo", "\\V\\CFoo"),
    [2] = slot_entry(2, "foo", "\\V\\C\\<foo\\>"),
    [3] = slot_entry(3, "bar", "\\V\\c\\<bar\\>"),
  }
  MiniTest.expect.equality(
    grep.build_rg_pattern(slots, nil),
    rg_term(true, "Foo") .. "|" .. rg_term(true, B .. "foo" .. B) .. "|" .. rg_term(false, B .. "bar" .. B)
  )
end

T["build_rg_pattern only adds word boundaries next to ASCII word characters"] = function()
  local slots = {
    [1] = slot_entry(1, "-foo", "\\V\\C-foo\\>"),
    [2] = slot_entry(2, "foo-", "\\V\\C\\<foo-"),
    [3] = slot_entry(3, "--", "\\V\\C--"),
    -- Pinned where `-` was a keyword character: the saved pattern bounds both
    -- ends, but `-` is never an ASCII word character for ripgrep.
    [4] = slot_entry(4, "-foo-", "\\V\\C\\<-foo-\\>"),
    -- Multibyte endpoints: Vim and ripgrep disagree on what a word is there.
    [5] = slot_entry(5, "\228\184\128foo\228\184\128", "\\V\\C\\<\228\184\128foo\228\184\128\\>"),
    [6] = slot_entry(6, "\195\132foo", "\\V\\C\\<\195\132foo\\>"),
    [7] = slot_entry(7, "\240\159\152\128foo", "\\V\\C\\<\240\159\152\128foo\\>"),
  }
  for _, entry in pairs(slots) do
    entry.whole_word = true
  end
  local expected = {
    rg_term(true, "-foo" .. B),
    rg_term(true, B .. "foo-"),
    rg_term(true, "--"),
    rg_term(true, "-foo-"),
    rg_term(true, "\228\184\128foo\228\184\128"),
    rg_term(true, "\195\132foo" .. B),
    rg_term(true, "\240\159\152\128foo" .. B),
  }
  MiniTest.expect.equality(grep.build_rg_pattern(slots, nil), table.concat(expected, "|"))
end

T["grep boundaries follow the saved pattern, not the current iskeyword"] = function()
  -- Pattern saved without a leading boundary (pinned as `-foo`): widening
  -- iskeyword afterwards must not add one back.
  local slots = { [1] = slot_entry(1, "-foo", "\\V\\C-foo\\>") }
  slots[1].whole_word = true

  local saved_iskeyword = vim.bo.iskeyword
  vim.bo.iskeyword = saved_iskeyword .. ",-"
  local rg_pattern = grep.build_rg_pattern(slots, nil)
  vim.bo.iskeyword = saved_iskeyword

  MiniTest.expect.equality(rg_pattern, rg_term(true, "-foo" .. B))
end

T["real rg with --smart-case matches each slot's case exactly"] = function()
  require_rg()

  local slots = {
    [1] = pinned("foo", { whole_word = true, case_sensitive = true, slot = 1 }),
    [2] = pinned("Bar", { whole_word = false, case_sensitive = true, slot = 2 }),
    [3] = pinned("baz", { whole_word = true, case_sensitive = false, slot = 3 }),
  }
  local lines = { "foo", "FOO", "Foo", "xfoo", "Bar", "bar", "BAZ", "baz", "bazooka" }

  with_project({ ["a.txt"] = lines }, function(root)
    -- Picker backends run ripgrep with --smart-case, which turns an all-lowercase
    -- pattern case-insensitive unless the pattern says otherwise.
    local result = vim
      .system({ "rg", "--smart-case", "--no-filename", "-e", grep.build_rg_pattern(slots, nil), "a.txt" }, {
        cwd = root,
        text = true,
      })
      :wait()
    local found = vim.split(vim.trim(result.stdout), "\n")
    table.sort(found)
    MiniTest.expect.equality(found, { "BAZ", "Bar", "baz", "foo" })
  end)
end

-- ==========================================================================
-- Picker backends
-- ==========================================================================

T["grep passes per-slot match semantics to the picker"] = function()
  helpers.setup_buffer({ "foo FOO bar BAR" })

  local captured = {}
  local fzf_stub = {
    grep = function(opts)
      captured.grep = opts
    end,
    live_grep = function(opts)
      captured.live_grep = opts
    end,
  }

  local pinwords = require("pinwords")
  helpers.with_loaded_module("fzf-lua", fzf_stub, function()
    helpers.with_loaded_module("pinwords.fzf_lua", nil, function()
      pinwords.setup({
        whole_word = false,
        case_sensitive = false,
        telescope = { enabled = false },
        snacks = { enabled = false },
        fzf_lua = { enabled = true },
      })
      pinwords.set(1, { raw = "foo", whole_word = true, case_sensitive = true })
      pinwords.set(2, { raw = "bar" })
      pinwords.grep()
      pinwords.live_grep({ slot = 1 })
    end)
  end)

  MiniTest.expect.equality(captured.grep.search, rg_term(true, B .. "foo" .. B) .. "|" .. rg_term(false, "bar"))
  MiniTest.expect.equality(captured.grep.no_esc, true)
  -- The case-sensitive lowercase slot stays case-sensitive under --smart-case.
  MiniTest.expect.equality(captured.live_grep.search, rg_term(true, B .. "foo" .. B))
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
  helpers.with_loaded_module("fzf-lua", fzf_stub, function()
    helpers.with_loaded_module("pinwords.fzf_lua", nil, function()
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
        MiniTest.expect.equality(captured.search, rg_term(true, "qux"))
        MiniTest.expect.equality(notified, {
          { msg = "pinwords: grep skipped 1 multi-line pinned word", level = vim.log.levels.WARN },
        })
      end)
    end)
  end)
end

-- ==========================================================================
-- Fallback dispatch (stubbed backends)
-- ==========================================================================

T["fallback grep prefers ripgrep and resolves results against the search cwd"] = function()
  local slots = { [1] = slot_entry(1, "foo/bar", "\\V\\cfoo/bar") }

  with_stubbed_backends({
    executables = { rg = true, git = true },
    respond = respond_with(rg_line("lua/pinwords/init.lua", 1, 1, "foo/bar :12:34: tail")),
  }, function(captured)
    grep._fallback_grep(slots, nil)

    MiniTest.expect.equality(captured.argvs, {
      { "rg", "--vimgrep", "--null", "--color=never", "--no-heading", "-e", rg_term(false, "foo/bar") },
    })
    MiniTest.expect.equality(captured.opts[1], { text = true, cwd = vim.fn.getcwd() })
    MiniTest.expect.equality(captured.qf, {
      {
        action = " ",
        what = {
          title = "pinwords grep",
          items = {
            { filename = from_cwd("lua/pinwords/init.lua"), lnum = 1, col = 1, text = "foo/bar :12:34: tail" },
          },
        },
      },
    })
    MiniTest.expect.equality(captured.opened, 1)
  end)
end

T["fallback grep treats ripgrep no-match as info notification"] = function()
  local slots = { [1] = slot_entry(1, "notfound", "\\V\\cnotfound") }

  with_stubbed_backends({ executables = { rg = true }, respond = respond_with("") }, function(captured)
    helpers.with_notify_override(function(notified)
      grep._fallback_grep(slots, nil)
      MiniTest.expect.equality(notified, {
        { msg = "pinwords: grep found no matches", level = vim.log.levels.INFO },
      })
    end)
    MiniTest.expect.equality(captured.opened, 0)
  end)
end

T["fallback grep uses async git grep per slot when ripgrep is unavailable"] = function()
  local slots = {
    [1] = slot_entry(1, "foo", "\\V\\C\\<foo\\>"),
    [2] = slot_entry(2, "bar", "\\V\\cbar"),
  }
  local stdout_by_term = {
    foo = git_line("lua/b.lua", 2, 5, "has foo here"),
    bar = git_line("lua/a.lua", 1, 1, "bar at start"),
  }

  local callbacks = {}
  with_stubbed_backends({
    executables = { git = true },
    respond = function(argv, on_exit)
      callbacks[#callbacks + 1] = function()
        on_exit({ code = 0, stdout = stdout_by_term[argv[#argv]], stderr = "" })
      end
    end,
  }, function(captured)
    grep._fallback_grep(slots, nil)

    -- Complete in reverse order; the merged list is still sorted by location.
    for i = #callbacks, 1, -1 do
      callbacks[i]()
    end

    local common =
      { "git", "grep", "--no-color", "-I", "-z", "-n", "--column", "--untracked", "--exclude-standard", "-F" }
    MiniTest.expect.equality(captured.argvs, {
      vim.list_extend(vim.deepcopy(common), { "-w", "-e", "foo" }),
      vim.list_extend(vim.deepcopy(common), { "-i", "-e", "bar" }),
    })
    MiniTest.expect.equality(captured.opts[1].cwd, vim.fn.getcwd())
    MiniTest.expect.equality(#captured.qf, 1)
    MiniTest.expect.equality(captured.qf[1].what.items, {
      { filename = from_cwd("lua/a.lua"), lnum = 1, col = 1, text = "bar at start" },
      { filename = from_cwd("lua/b.lua"), lnum = 2, col = 5, text = "has foo here" },
    })
    MiniTest.expect.equality(captured.opened, 1)
  end)
end

T["fallback grep reports no matches when git grep finds nothing"] = function()
  local slots = { [1] = slot_entry(1, "zzz", "\\V\\czzz") }

  with_stubbed_backends({ executables = { git = true }, respond = respond_with("") }, function(captured)
    helpers.with_notify_override(function(notified)
      grep._fallback_grep(slots, nil)
      MiniTest.expect.equality(notified, {
        { msg = "pinwords: grep found no matches", level = vim.log.levels.INFO },
      })
    end)
    MiniTest.expect.equality(captured.opened, 0)
  end)
end

T["fallback grep reads paths verbatim up to the NUL separator"] = function()
  local slots = { [1] = slot_entry(1, "foo", "\\V\\Cfoo") }

  for _, case in ipairs({
    { executables = { rg = true }, line = rg_line },
    { executables = { git = true }, line = git_line },
  }) do
    local stdout = case.line("dir/a\nb.txt", 1, 1, "foo") .. case.line("c:1:2:d.txt", 3, 7, "x:5:6:foo")
    with_stubbed_backends({ executables = case.executables, respond = respond_with(stdout) }, function(captured)
      grep._fallback_grep(slots, nil)
      local items = captured.qf[1].what.items
      table.sort(items, function(a, b)
        return a.filename < b.filename
      end)
      MiniTest.expect.equality(items, {
        { filename = from_cwd("c:1:2:d.txt"), lnum = 3, col = 7, text = "x:5:6:foo" },
        { filename = from_cwd("dir/a\nb.txt"), lnum = 1, col = 1, text = "foo" },
      })
    end)
  end
end

T["git grep fallback enforces one-sided boundaries on its results"] = function()
  local slots = { [1] = slot_entry(1, "-foo", "\\V\\C-foo\\>") }
  slots[1].whole_word = true

  local stdout = git_line("lua/a.lua", 1, 3, "x -foo y")
    .. git_line("lua/b.lua", 2, 1, "-foobar")
    .. git_line("lua/c.lua", 3, 1, "-foobar and -foo")

  with_stubbed_backends({ executables = { git = true }, respond = respond_with(stdout) }, function(captured)
    grep._fallback_grep(slots, nil)

    -- `-w` would demand a boundary on the `-` side, so it must not be passed.
    MiniTest.expect.equality(vim.tbl_contains(captured.argvs[1], "-w"), false)
    -- "-foobar" alone is rejected; the line that also contains a bounded "-foo"
    -- is kept with the column moved to that occurrence.
    MiniTest.expect.equality(captured.qf[1].what.items, {
      { filename = from_cwd("lua/a.lua"), lnum = 1, col = 3, text = "x -foo y" },
      { filename = from_cwd("lua/c.lua"), lnum = 3, col = 13, text = "-foobar and -foo" },
    })
  end)
end

T["git grep results are verified with the slot pattern even when -w was used"] = function()
  local slots = { [1] = slot_entry(1, "foo", "\\V\\C\\<foo\\>") }
  -- The second line could only come back from a looser backend match.
  local stdout = git_line("lua/a.lua", 1, 1, "foo bar") .. git_line("lua/b.lua", 2, 1, "xfoo bar")

  with_stubbed_backends({ executables = { git = true }, respond = respond_with(stdout) }, function(captured)
    grep._fallback_grep(slots, nil)

    MiniTest.expect.equality(vim.tbl_contains(captured.argvs[1], "-w"), true)
    MiniTest.expect.equality(#captured.qf[1].what.items, 1)
    MiniTest.expect.equality(captured.qf[1].what.items[1].filename, from_cwd("lua/a.lua"))
  end)
end

T["ripgrep fallback results are verified against the slot pattern"] = function()
  local slots = { [1] = slot_entry(1, "foo", "\\V\\C\\<foo\\>") }
  local stdout = rg_line("lua/a.lua", 1, 3, "x foo y") .. rg_line("lua/b.lua", 2, 1, "xfoo y")

  with_stubbed_backends({ executables = { rg = true }, respond = respond_with(stdout) }, function(captured)
    grep._fallback_grep(slots, nil)

    MiniTest.expect.equality(captured.argvs[1][#captured.argvs[1]], rg_term(true, B .. "foo" .. B))
    MiniTest.expect.equality(captured.qf[1].what.items, {
      { filename = from_cwd("lua/a.lua"), lnum = 1, col = 3, text = "x foo y" },
    })
  end)
end

T["verification keeps multibyte neighbours and case-folded matches, in order"] = function()
  local slots = {
    -- Whole-word slot whose results sit next to multibyte punctuation.
    [1] = slot_entry(1, "foo", "\\V\\C\\<foo\\>"),
    -- Case-insensitive slot with a non-ASCII letter.
    [2] = slot_entry(2, "\195\132", "\\V\\c\195\132"),
  }
  local stdout = rg_line("lua/z.lua", 5, 2, "\227\128\140foo\227\128\141")
    .. rg_line("lua/a.lua", 1, 1, "\195\164 lower")
    .. rg_line("lua/b.lua", 2, 1, "xfoo")

  with_stubbed_backends({ executables = { rg = true }, respond = respond_with(stdout) }, function(captured)
    grep._fallback_grep(slots, nil)

    local items = captured.qf[1].what.items
    MiniTest.expect.equality(#items, 2)
    -- ripgrep's output order is preserved rather than reordered per slot.
    MiniTest.expect.equality(items[1].filename, from_cwd("lua/z.lua"))
    MiniTest.expect.equality(items[2].filename, from_cwd("lua/a.lua"))
  end)
end

T["verification keeps every match on a line at its own column"] = function()
  local slots = { [1] = slot_entry(1, "foo", "\\V\\C\\<foo\\>") }
  -- rg --vimgrep reports one result per match, so both columns must survive.
  local stdout = rg_line("lua/a.lua", 1, 1, "foo and foo") .. rg_line("lua/a.lua", 1, 9, "foo and foo")

  with_stubbed_backends({ executables = { rg = true }, respond = respond_with(stdout) }, function(captured)
    grep._fallback_grep(slots, nil)

    local items = captured.qf[1].what.items
    MiniTest.expect.equality({ #items, items[1].col, items[2].col }, { 2, 1, 9 })
  end)
end

T["grep warns once about multi-line pins when falling back"] = function()
  helpers.setup_buffer({ "foo bar", "baz qux" })

  local pinwords = require("pinwords")
  pinwords.setup({
    telescope = { enabled = false },
    snacks = { enabled = false },
    fzf_lua = { enabled = false },
  })
  pinwords.set(1, { raw = "foo", whole_word = false })
  pinwords.set(2, { raw = "foo\nbaz", whole_word = false })

  with_stubbed_backends({ executables = { rg = true }, respond = respond_with("") }, function()
    helpers.with_notify_override(function(notified)
      pinwords.grep()
      MiniTest.expect.equality(notified, {
        { msg = "pinwords: grep skipped 1 multi-line pinned word", level = vim.log.levels.WARN },
        { msg = "pinwords: grep found no matches", level = vim.log.levels.INFO },
      })
    end)
  end)
end

T["fallback grep passes the pattern after -e so leading dashes are safe"] = function()
  local slots = { [1] = slot_entry(1, "-foo", "\\V\\C-foo") }

  with_stubbed_backends({ executables = { rg = true }, respond = respond_with("") }, function(captured)
    helpers.with_notify_override(function()
      grep._fallback_grep(slots, nil)
    end)

    local argv = captured.argvs[1]
    MiniTest.expect.equality({ argv[#argv - 1], argv[#argv] }, { "-e", rg_term(true, "-foo") })
  end)
end

T["fallback grep drops results from superseded and torn-down runs"] = function()
  local slots = { [1] = slot_entry(1, "foo", "\\V\\Cfoo") }

  local pending = {}
  local orig = { executable = vim.fn.executable, system = vim.system, schedule = vim.schedule, cmd = vim.api.nvim_cmd }
  local opened = 0
  vim.fn.executable = function(bin)
    return bin == "rg" and 1 or 0
  end
  vim.system = function(_argv, _opts, on_exit)
    pending[#pending + 1] = on_exit
    return {}
  end
  vim.schedule = function(cb)
    cb()
  end
  vim.api.nvim_cmd = function(cmd, _opts)
    if cmd.cmd == "copen" then
      opened = opened + 1
    end
  end

  local ok, err = pcall(function()
    -- A list the stale callbacks must leave alone.
    vim.fn.setqflist(
      {},
      " ",
      { title = "sentinel", items = { { filename = "keep.txt", lnum = 7, col = 1, text = "keep" } } }
    )

    helpers.with_notify_override(function(notified)
      grep._fallback_grep(slots, nil)
      grep._fallback_grep(slots, nil)

      -- The superseded first run completes after the newest one; only the
      -- newest one may write quickfix.
      pending[2]({ code = 0, stdout = rg_line("lua/a.lua", 1, 1, "foo"), stderr = "" })
      local newest = vim.fn.getqflist({ title = 0, items = 0 })
      pending[1]({ code = 0, stdout = rg_line("lua/b.lua", 1, 1, "foo"), stderr = "" })
      MiniTest.expect.equality(vim.fn.getqflist({ title = 0, items = 0 }), newest)
      MiniTest.expect.equality(newest.title, "pinwords grep")
      MiniTest.expect.equality(#newest.items, 1)
      MiniTest.expect.equality(vim.api.nvim_buf_get_name(newest.items[1].bufnr), from_cwd("lua/a.lua"))

      -- After teardown, even the newest in-flight run stops touching quickfix.
      vim.fn.setqflist({}, " ", { title = "after teardown" })
      grep._fallback_grep(slots, nil)
      grep.teardown()
      pending[3]({ code = 0, stdout = rg_line("lua/c.lua", 1, 1, "foo"), stderr = "" })
      MiniTest.expect.equality(vim.fn.getqflist({ title = 0 }).title, "after teardown")

      MiniTest.expect.equality(notified, {})
    end)
  end)

  vim.fn.executable = orig.executable
  vim.system = orig.system
  vim.schedule = orig.schedule
  vim.api.nvim_cmd = orig.cmd
  if not ok then
    error(err)
  end

  MiniTest.expect.equality(opened, 1)
end

T["a later picker-backed grep invalidates an in-flight fallback run"] = function()
  helpers.setup_buffer({ "foo bar" })

  local slots = { [1] = slot_entry(1, "foo", "\\V\\Cfoo") }
  local fzf_calls = 0
  local fzf_stub = {
    grep = function(_opts)
      fzf_calls = fzf_calls + 1
    end,
    live_grep = function(_opts) end,
  }

  local pending
  local orig = { executable = vim.fn.executable, system = vim.system, schedule = vim.schedule, cmd = vim.api.nvim_cmd }
  local opened = 0
  vim.fn.executable = function(bin)
    return bin == "rg" and 1 or 0
  end
  vim.system = function(_argv, _opts, on_exit)
    pending = on_exit
    return {}
  end
  vim.schedule = function(cb)
    cb()
  end
  vim.api.nvim_cmd = function(cmd, _opts)
    if cmd.cmd == "copen" then
      opened = opened + 1
    end
  end

  local ok, err = pcall(function()
    vim.fn.setqflist({}, " ", { title = "sentinel" })
    local pinwords = require("pinwords")
    helpers.with_loaded_module("fzf-lua", fzf_stub, function()
      helpers.with_loaded_module("pinwords.fzf_lua", nil, function()
        grep._fallback_grep(slots, nil)

        -- The next search is served by a picker, so it must still supersede the
        -- fallback that is still running.
        pinwords.setup({
          telescope = { enabled = false },
          snacks = { enabled = false },
          fzf_lua = { enabled = true },
        })
        pinwords.set(1, { raw = "foo" })
        helpers.with_notify_override(function(notified)
          pinwords.grep()
          pending({ code = 0, stdout = rg_line("lua/a.lua", 1, 1, "foo"), stderr = "" })
          MiniTest.expect.equality(notified, {})
        end)
      end)
    end)
  end)

  vim.fn.executable = orig.executable
  vim.system = orig.system
  vim.schedule = orig.schedule
  vim.api.nvim_cmd = orig.cmd
  if not ok then
    error(err)
  end

  MiniTest.expect.equality(fzf_calls, 1)
  MiniTest.expect.equality(opened, 0)
  MiniTest.expect.equality(vim.fn.getqflist({ title = 0 }).title, "sentinel")
end

-- ==========================================================================
-- Fallback against real backends
-- ==========================================================================

local PROJECT = {
  ["a.txt"] = { "foo :12:34:tail", "Foo and foo", "xfoo", "bar BAR" },
  ["日本 語.txt"] = { "foo here" },
  ["sub/c.txt"] = { "nothing", "foo/bar" },
}

T["real backends agree on files, positions, and per-slot case"] = function()
  require_rg()

  local slots = {
    [1] = pinned("foo", { whole_word = true, case_sensitive = true, slot = 1 }),
    [2] = pinned("BAR", { whole_word = true, case_sensitive = false, slot = 2 }),
  }
  local expected = {
    "a.txt:1:1:foo :12:34:tail",
    "a.txt:2:9:Foo and foo",
    "a.txt:4:1:bar BAR",
    "a.txt:4:5:bar BAR",
    "sub/c.txt:2:1:foo/bar",
    "sub/c.txt:2:5:foo/bar",
    "日本 語.txt:1:1:foo here",
  }

  for _, case in ipairs({
    { available = { rg = true }, backends = { "rg" } },
    { available = { rg = false, git = true }, backends = { "git", "git" } },
    { available = { rg = false, git = false }, backends = {} },
  }) do
    with_project(PROJECT, function(root)
      if case.available.git then
        git_init(root)
      end
      with_backends(case.available, function()
        local items, _, backends = run_real_grep(root, slots)
        MiniTest.expect.equality(backends, case.backends)
        MiniTest.expect.equality(items, expected)
      end)
    end)
  end
end

T["real backends keep results tied to the directory the search ran in"] = function()
  require_rg()

  local slots = { [1] = pinned("foo", { whole_word = true, case_sensitive = true }) }
  local elsewhere = vim.fn.resolve(vim.fn.tempname())
  vim.fn.mkdir(elsewhere, "p")

  for _, case in ipairs({
    { available = { rg = true }, backend = "rg" },
    { available = { rg = false, git = true }, backend = "git" },
  }) do
    with_project({ ["a.txt"] = { "foo" } }, function(root)
      if case.available.git then
        git_init(root)
      end
      with_backends(case.available, function()
        local items, _, backends = run_real_grep(root, slots, function()
          -- Change directory before the asynchronous results arrive.
          vim.cmd.cd(vim.fn.fnameescape(elsewhere))
        end)
        MiniTest.expect.equality(backends, { case.backend })
        MiniTest.expect.equality(items, { "a.txt:1:1:foo" })
      end)
    end)
  end
  vim.fn.delete(elsewhere, "rf")
end

T["vimgrep fallback restores wildignore and reports no match"] = function()
  local slots = { [1] = pinned("needle", { whole_word = true, case_sensitive = false }) }

  with_project({ ["a.txt"] = { "haystack" } }, function(root)
    local saved_wildignore = vim.o.wildignore
    vim.o.wildignore = "*.bak"

    local ok, err = pcall(function()
      with_backends({ rg = false, git = false }, function()
        local items, notified = run_real_grep(root, slots)
        MiniTest.expect.equality(items, {})
        MiniTest.expect.equality(notified, {
          {
            msg = "pinwords: ripgrep not available; scanning project files (this may take a moment)",
            level = vim.log.levels.INFO,
          },
          { msg = "pinwords: grep found no matches", level = vim.log.levels.INFO },
        })
      end)
      MiniTest.expect.equality(vim.o.wildignore, "*.bak")
    end)
    vim.o.wildignore = saved_wildignore
    if not ok then
      error(err)
    end
  end)
end

T["vimgrep fallback skips ignored directories"] = function()
  local slots = { [1] = pinned("foo", { whole_word = true, case_sensitive = false }) }
  local files = { ["a.txt"] = { "foo" } }
  for _, dir in ipairs({ ".git", "node_modules", "build" }) do
    files[dir .. "/x.txt"] = { "foo" }
  end

  with_project(files, function(root)
    with_backends({ rg = false, git = false }, function()
      MiniTest.expect.equality(run_real_grep(root, slots), { "a.txt:1:1:foo" })
    end)
  end)
end

T["grep matches what the highlight matches next to multibyte and symbol neighbours"] = function()
  require_rg()

  local slots = { [1] = pinned("foo", { whole_word = true, case_sensitive = false }) }
  local lines = {
    "\228\184\128foo", -- CJK before
    "foo\228\184\128", -- CJK after
    "\195\169foo", -- Latin letter before
    "\240\159\152\128foo", -- emoji before
    "foo\204\129", -- combining accent after
    "x-foo",
    "xfoo",
    "foo_bar",
  }

  -- What the highlight pattern matches in a buffer with the default iskeyword.
  local highlighted = {}
  for lnum, line in ipairs(lines) do
    if vim.fn.match(line, slots[1].pattern) >= 0 then
      highlighted[#highlighted + 1] = lnum
    end
  end

  with_project({ ["a.txt"] = lines }, function(root)
    with_backends({ rg = true }, function()
      local found = {}
      for _, item in ipairs(run_real_grep(root, slots)) do
        found[#found + 1] = tonumber(item:match("^a%.txt:(%d+):"))
      end
      table.sort(found)
      MiniTest.expect.equality(found, highlighted)
    end)

    -- The picker pattern has no verification step, so it must not miss any of them.
    local result = vim
      .system({ "rg", "--smart-case", "-n", "--no-filename", "-e", grep.build_rg_pattern(slots, nil), "a.txt" }, {
        cwd = root,
        text = true,
      })
      :wait()
    for _, lnum in ipairs(highlighted) do
      MiniTest.expect.equality(
        result.stdout:find("^" .. lnum .. ":") ~= nil or result.stdout:find("\n" .. lnum .. ":") ~= nil,
        true
      )
    end
  end)
end

T["grep, highlight, and jump agree for a slot pinned under another iskeyword"] = function()
  require_rg()

  -- Pinned where `-` was a keyword character, so the saved pattern needs a
  -- keyword `-` at the start of the match.
  helpers.setup_buffer({ "x -foo y", "x-foo" })
  vim.bo.iskeyword = vim.bo.iskeyword .. ",-"
  vim.api.nvim_win_set_cursor(0, { 1, 2 })
  local pinwords = require("pinwords")
  pinwords.set(1)
  local slot = pinwords.list()[1]
  MiniTest.expect.equality(slot.pattern, "\\V\\c\\<-foo\\>")

  -- In a buffer with the default iskeyword the highlight and jump find nothing.
  vim.cmd("enew!")
  helpers.setup_buffer({ "x -foo y", "x-foo" })
  MiniTest.expect.equality(vim.fn.searchpos(slot.pattern, "nw"), { 0, 0 })
  MiniTest.expect.equality(pinwords.jump_next(), false)

  -- ...and so does grep over the same text.
  with_project({ ["a.txt"] = { "x -foo y", "x-foo" } }, function(root)
    with_backends({ rg = true }, function()
      local items, notified = run_real_grep(root, { [1] = slot })
      MiniTest.expect.equality(items, {})
      MiniTest.expect.equality(notified[#notified].msg, "pinwords: grep found no matches")
    end)
  end)
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

return T
