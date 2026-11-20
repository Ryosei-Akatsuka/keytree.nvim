---@mod keytree Main entry point
---
---Show the currently effective keymaps as an `eza -T` style tree. Each entry is
---tagged with where it comes from: Neovim default, user config or buffer-local.

local M = {}

---@class keytree.Config
---@field group_labels table<string, string> description for key prefixes, e.g. ["<leader>f"] = "Find"

M.defaults = {
  group_labels = {},
}

---@type keytree.Config
M.config = vim.deepcopy(M.defaults)

---@param opts keytree.Config|nil
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

-- 表示するモードの見出し（v は x / s も含む）
local mode_sections = {
  n = { label = "NORMAL", order = 1 },
  v = { label = "VISUAL", order = 2 },
  s = { label = "SELECT", order = 3 },
  o = { label = "OPERATOR", order = 4 },
  i = { label = "INSERT", order = 5 },
  t = { label = "TERMINAL", order = 6 },
  c = { label = "COMMAND", order = 7 },
}

-- nvim_get_keymap() が返す mode を表示用の見出しへ寄せる
local mode_aliases = {
  x = "v",
  ["!"] = "i",
  [" "] = "n",
}

local function section_of(mode)
  local section = mode_aliases[mode] or mode
  if mode_sections[section] then
    return section
  end
  return nil
end

local function fingerprint(lhs, mode, rhs, desc, callback)
  return table.concat({ lhs or "", mode or "", rhs or "", desc or "", callback and "1" or "0" }, "\0")
end

-- Neovim 標準のキーマップを別プロセスから取得する。設定で追加・上書きしたものと区別するため
local default_map_keys

local function load_default_map_keys()
  if default_map_keys then
    return default_map_keys
  end

  local defaults = {}
  local expr =
    'lua local out = {}; for _, mode in ipairs({ "n", "v", "o", "i", "t", "c" }) do for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do out[#out + 1] = { lhs = m.lhs, mode = m.mode, rhs = m.rhs, desc = m.desc, cb = m.callback ~= nil } end end; io.stdout:write(vim.json.encode(out))'

  local ok, res = pcall(function()
    return vim.system({ vim.v.progpath, "--clean", "--headless", "-c", expr, "-c", "qa!" }, { text = true }):wait(5000)
  end)

  if ok and res and res.code == 0 and res.stdout and res.stdout ~= "" then
    local decoded, maps = pcall(vim.json.decode, res.stdout)
    if decoded and type(maps) == "table" then
      for _, m in ipairs(maps) do
        defaults[fingerprint(m.lhs, m.mode, m.rhs, m.desc, m.cb)] = true
      end
      default_map_keys = defaults
      return default_map_keys
    end
  end

  return nil
end

local function key_name(value)
  if value == " " then
    return "<Space>"
  end
  if type(value) == "string" and value ~= "" then
    return value
  end
  return "\\"
end

local function display_lhs(lhs)
  -- <C-H> のような表記を小文字に揃える
  lhs = lhs:gsub("<C%-(%a)>", function(c)
    return "<C-" .. c:lower() .. ">"
  end)

  local leader = vim.g.mapleader
  if type(leader) == "string" and leader ~= "" and vim.startswith(lhs, leader) then
    return "<leader>" .. lhs:sub(#leader + 1)
  end

  local localleader = vim.g.maplocalleader
  if type(localleader) == "string" and localleader ~= "" and vim.startswith(lhs, localleader) then
    return "<localleader>" .. lhs:sub(#localleader + 1)
  end

  return lhs
end

local function tokenize(lhs)
  local tokens = {}
  local pos = 1
  while pos <= #lhs do
    if lhs:sub(pos, pos) == "<" then
      local close = lhs:find(">", pos, true)
      if close then
        tokens[#tokens + 1] = lhs:sub(pos, close)
        pos = close + 1
      else
        tokens[#tokens + 1] = lhs:sub(pos, pos)
        pos = pos + 1
      end
    else
      local lt = lhs:find("<", pos, true) or (#lhs + 1)
      local ch = vim.fn.strcharpart(lhs:sub(pos, lt - 1), 0, 1)
      if ch == "" then
        break
      end
      tokens[#tokens + 1] = ch
      pos = pos + #ch
    end
  end
  return tokens
end

local origin_priority = { default = 1, config = 2, buffer = 3 }
local origin_tags = {
  config = "[config]",
  buffer = "[buffer]",
  default = "[default]",
}
local origin_highlights = {
  config = "KeymapTreeConfig",
  buffer = "KeymapTreeBuffer",
  default = "KeymapTreeDefault",
}

local function insert(root, tokens, desc, origin)
  local node = root
  for _, token in ipairs(tokens) do
    local child = node.children[token]
    if not child then
      child = { children = {}, entries = {} }
      node.children[token] = child
    end
    node = child
  end

  for _, entry in ipairs(node.entries) do
    if entry.desc == desc then
      if origin_priority[origin] > origin_priority[entry.origin] then
        entry.origin = origin
      end
      return
    end
  end

  node.entries[#node.entries + 1] = { desc = desc, origin = origin }
end

local function collect()
  local defaults = load_default_map_keys()
  if not defaults then
    return nil
  end

  local seen = {}
  local maps = {}
  local query_modes = { "n", "v", "o", "i", "t", "c" }

  local function add(m, is_buffer)
    -- LuaSnip などの内部マッピングは表示しない
    if m.lhs:match("^<Plug>") or m.lhs:match("^<SNR>") then
      return
    end

    local section = section_of(m.mode)
    if not section then
      return
    end

    local origin
    if is_buffer then
      origin = "buffer"
    elseif defaults[fingerprint(m.lhs, m.mode, m.rhs, m.desc, m.callback ~= nil)] then
      origin = "default"
    else
      origin = "config"
    end

    -- 説明のない設定キーマップはノイズになるため除外する。matchit などの標準キーマップは拾う
    local desc = m.desc
    if type(desc) ~= "string" or desc == "" then
      if origin ~= "default" then
        return
      end
      desc = "(説明なし)"
    end

    local lhs = display_lhs(m.lhs)
    local key = section .. "\0" .. lhs .. "\0" .. desc
    if seen[key] then
      local entry = seen[key]
      if origin_priority[origin] > origin_priority[entry.origin] then
        entry.origin = origin
      end
      return
    end

    local map = { section = section, lhs = lhs, desc = desc, origin = origin }
    seen[key] = map
    maps[#maps + 1] = map
  end

  for _, mode in ipairs(query_modes) do
    for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
      add(m, false)
    end
  end

  -- LSP・gitsigns・blink.cmp などのバッファローカルなキーマップを拾う
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" then
      for _, mode in ipairs(query_modes) do
        for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
          add(m, true)
        end
      end
    end
  end

  return maps
end

local function key_rank(key)
  if key == "<leader>" then
    return 0
  end
  if key:match("^<C%-") then
    return 1
  end
  if key:sub(1, 1) == "<" then
    return 2
  end
  if key:match("^[%[%]]") then
    return 3
  end
  return 4
end

local function sorted_children(node)
  local keys = {}
  for key in pairs(node.children) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(a, b)
    local ra, rb = key_rank(a), key_rank(b)
    if ra ~= rb then
      return ra < rb
    end
    local la, lb = a:lower(), b:lower()
    if la ~= lb then
      return la < lb
    end
    return a < b
  end)
  return keys
end

local function desc_text(node)
  local parts = {}
  local marks = {}
  local length = 0
  local function add(text)
    parts[#parts + 1] = text
    length = length + #text
  end

  for i, entry in ipairs(node.entries) do
    if i > 1 then
      add(" / ")
    end
    add(entry.desc)
    add("  ")
    local start = length
    add(origin_tags[entry.origin])
    marks[#marks + 1] = { start, length, origin_highlights[entry.origin] }
  end

  return table.concat(parts), marks
end

local function display_token(token)
  if token == " " then
    return "<Space>"
  end
  if token == "\t" then
    return "<Tab>"
  end
  return token
end

local function render(node, path, shown_path, prefix, out)
  local keys = sorted_children(node)
  for i, key in ipairs(keys) do
    local child = node.children[key]
    local last = i == #keys
    local branch = last and "└── " or "├── "
    local child_path = path .. key
    local key_text = display_token(key)
    local child_shown_path = shown_path .. key_text
    local text = prefix .. branch .. key_text
    local spans = {
      { 0, #prefix + #branch, "KeymapTreeTree" },
      { #prefix + #branch, #text, "KeymapTreeKey" },
    }

    local desc, marks = desc_text(child)
    if desc ~= "" then
      -- 入れ子のキーは先頭からの完全なキー列も表示する
      if child_shown_path ~= key_text then
        text = text .. " " .. child_shown_path
        spans[2][2] = #text
      end
      local desc_start = #text + 2
      text = text .. "  " .. desc
      spans[#spans + 1] = { desc_start, #text, "KeymapTreeDesc" }
      for _, mark in ipairs(marks) do
        spans[#spans + 1] = { desc_start + mark[1], desc_start + mark[2], mark[3], 10 }
      end
    elseif M.config.group_labels[child_path] then
      local label = M.config.group_labels[child_path]
      text = text .. "  " .. label
      spans[#spans + 1] = { #text - #label, #text, "KeymapTreeGroup" }
    end

    out(text, spans)

    if next(child.children) then
      render(child, child_path, child_shown_path, prefix .. (last and "    " or "│   "), out)
    end
  end
end

local function define_highlights()
  vim.api.nvim_set_hl(0, "KeymapTreeHeader", { link = "Title", default = true })
  vim.api.nvim_set_hl(0, "KeymapTreeMode", { link = "Title", default = true })
  vim.api.nvim_set_hl(0, "KeymapTreeGroup", { link = "Directory", default = true })
  vim.api.nvim_set_hl(0, "KeymapTreeKey", { link = "Identifier", default = true })
  vim.api.nvim_set_hl(0, "KeymapTreeDesc", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "KeymapTreeTree", { link = "NonText", default = true })
  vim.api.nvim_set_hl(0, "KeymapTreeConfig", { link = "String", default = true })
  vim.api.nvim_set_hl(0, "KeymapTreeBuffer", { link = "DiagnosticInfo", default = true })
  vim.api.nvim_set_hl(0, "KeymapTreeDefault", { link = "Comment", default = true })
end

local function build()
  local maps = collect()
  if not maps then
    return nil
  end

  local roots = {}
  local counts = {}

  for _, map in ipairs(maps) do
    local root = roots[map.section]
    if not root then
      root = { children = {}, entries = {} }
      roots[map.section] = root
      counts[map.section] = 0
    end
    insert(root, tokenize(map.lhs), map.desc, map.origin)
    counts[map.section] = counts[map.section] + 1
  end

  local lines = {}
  local line_spans = {}
  local function out(text, spans)
    lines[#lines + 1] = text
    line_spans[#lines] = spans or {}
  end

  local header = string.format(
    "Neovim キーマップ  leader = %s  localleader = %s  %d 件",
    key_name(vim.g.mapleader),
    key_name(vim.g.maplocalleader),
    #maps
  )
  out(header, { { 0, #header, "KeymapTreeHeader" } })

  local legend = {
    { "[config]", "KeymapTreeConfig" },
    { " = 設定（グローバル）   ", "KeymapTreeDesc" },
    { "[buffer]", "KeymapTreeBuffer" },
    { " = 設定（バッファ）   ", "KeymapTreeDesc" },
    { "[default]", "KeymapTreeDefault" },
    { " = Neovim 標準", "KeymapTreeDesc" },
  }
  local legend_text = ""
  local legend_spans = {}
  for _, segment in ipairs(legend) do
    legend_spans[#legend_spans + 1] = { #legend_text, #legend_text + #segment[1], segment[2] }
    legend_text = legend_text .. segment[1]
  end
  out(legend_text, legend_spans)

  local sections = {}
  for key, info in pairs(mode_sections) do
    sections[#sections + 1] = { key = key, label = info.label, order = info.order }
  end
  table.sort(sections, function(a, b)
    return a.order < b.order
  end)

  for _, section in ipairs(sections) do
    local root = roots[section.key]
    if root then
      out("")
      local heading = string.format("%s  %d", section.label, counts[section.key])
      out(heading, { { 0, #section.label, "KeymapTreeMode" }, { #section.label, #heading, "KeymapTreeDesc" } })
      render(root, "", "", "", out)
    end
  end

  out("")
  local hint = "q / <Esc> で閉じる"
  out(hint, { { 0, #hint, "KeymapTreeDesc" } })

  return lines, line_spans
end

function M.show()
  define_highlights()
  local lines, line_spans = build()
  if not lines then
    vim.notify("keytree: Neovim 標準のキーマップを取得できませんでした", vim.log.levels.ERROR)
    return
  end

  local max_width = 0
  for _, line in ipairs(lines) do
    max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
  end

  local width = math.min(max_width + 4, math.max(20, math.floor(vim.o.columns * 0.9)))
  local height = math.min(#lines, math.max(1, math.floor((vim.o.lines - 2) * 0.9)))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local ns = vim.api.nvim_create_namespace("keytree")
  for row, spans in ipairs(line_spans) do
    for _, span in ipairs(spans) do
      vim.api.nvim_buf_set_extmark(buf, ns, row - 1, span[1], {
        end_col = span[2],
        hl_group = span[3],
        priority = span[4] or 0,
      })
    end
  end

  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Keymaps ",
    title_pos = "center",
  })

  vim.wo[win].wrap = false
  vim.wo[win].cursorline = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].list = false

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set("n", "q", close, { buffer = buf, desc = "Close keymap tree" })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, desc = "Close keymap tree" })
end

return M
