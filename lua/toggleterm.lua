local api = vim.api
local fn = vim.fn
local fmt = string.format

local colors = require("toggleterm.colors")
local config = require("toggleterm.config")
local utils = require("toggleterm.utils")
local ui = require("toggleterm.ui")

local T = require("toggleterm.terminal")
local C = require("toggleterm.constants")

---@type Terminal
local Terminal = T.Terminal
local term_ft = C.term_ft
local SHADING_AMOUNT = C.shading_amount
-----------------------------------------------------------
-- Export
-----------------------------------------------------------
local M = {
  __set_highlights = colors.set_highlights
}

-----------------------------------------------------------
-- State
-----------------------------------------------------------
---@type Terminal[]
local terminals = {}

local function echomsg(msg, hl)
  hl = hl or "Title"
  api.nvim_echo({{msg, hl}}, true, {})
end

local function parse_argument(str, result)
  local arg = vim.split(str, "=")
  if #arg > 1 then
    local key, value = arg[1], arg[2]
    if key == "size" then
      value = tonumber(value)
    elseif key == "cmd" then
      -- Remove quotes
      -- TODO: find a better way to do this
      value = string.sub(value, 2, #value - 1)
    end
    result[key] = value
  end
  return result
end

---Take a users command arguments in the format "cmd='git commit' dir=~/dotfiles"
---and parse this into a table of arguments
---{cmd = "git commit", dir = "~/dotfiles"}
---TODO: only the cmd argument can handle quotes!
---@param args string
---@return table<string, string>
local function parse_input(args)
  local result = {}
  if args then
    -- extract the quoted command then remove it from the rest of the argument string
    -- \v - very magic, reduce the amount of escaping needed
    -- \w+\= - match a word followed by an = sign
    -- ("([^"]*)"|'([^']*)') - match double or single quoted text
    -- @see: https://stackoverflow.com/a/5950910
    local regex = [[\v\w+\=%("([^"]*)"|'([^']*)')]]
    local quoted_arg = fn.matchstr(args, regex, "g")
    args = fn.substitute(args, regex, "", "g")
    parse_argument(quoted_arg, result)

    local parts = vim.split(args, " ")
    for _, part in ipairs(parts) do
      parse_argument(part, result)
    end
  end
  return result
end

--- @param win_id number
local function find_window(win_id)
  return fn.win_gotoid(win_id) > 0
end

local function get_term_id()
  return #terminals == 0 and 1 or #terminals + 1
end

---get existing terminal or create an empty term table
---@param num number
---@param dir string
---@return Terminal
---@return boolean
local function get_or_create_term(num, dir)
  if terminals[num] then
    return terminals[num], false
  end
  return Terminal:new {id = get_term_id(), dir = dir}, true
end

--- Find the first open terminal window
--- by iterating all windows and matching the
--- containing buffers filetype with the passed in
--- comparator function or the default which matches
--- the filetype
--- @param comparator function
local function find_open_windows(comparator)
  comparator = comparator or function(buf)
      return vim.bo[buf].filetype == term_ft
    end
  local wins = api.nvim_list_wins()
  local is_open = false
  local term_wins = {}
  for _, win in pairs(wins) do
    local buf = api.nvim_win_get_buf(win)
    if comparator(buf) then
      is_open = true
      table.insert(term_wins, win)
    end
  end
  return is_open, term_wins
end

local function setup_global_mappings()
  local conf = config.get()
  local mapping = conf.open_mapping
  -- v:count1 defaults the count to 1 but if a count is passed in uses that instead
  -- <c-u> allows passing along the count
  api.nvim_set_keymap(
    "n",
    mapping,
    ':<c-u>exe v:count1 . "ToggleTerm"<CR>',
    {
      silent = true,
      noremap = true
    }
  )
  if conf.insert_mappings then
    api.nvim_set_keymap(
      "i",
      mapping,
      '<Esc>:<c-u>exe v:count1 . "ToggleTerm"<CR>',
      {
        silent = true,
        noremap = true
      }
    )
  end
end

--- @param bufnr number
local function find_windows_by_bufnr(bufnr)
  return fn.win_findbuf(bufnr)
end

--Create a new terminal or close beginning from the last opened
---@param _ number
---@param size number
---@param directory string
local function smart_toggle(_, size, directory)
  local already_open = find_open_windows()
  if not already_open then
    M.open(1, size, directory)
  else
    local target = #terminals
    -- count backwards from the end of the list
    for i = #terminals, 1, -1 do
      local term = terminals[i]
      if not term then
        vim.cmd(string.format('echomsg "Term does not exist %s"', vim.inspect(term)))
        break
      end
      local wins = find_windows_by_bufnr(term.bufnr)
      if #wins > 0 then
        target = i
        break
      end
    end
    M.close(target)
  end
end

--- @param num number
--- @param size number
local function toggle_nth_term(num, size, directory)
  local term = get_or_create_term(num, directory)

  ui.update_origin_win(term.window)

  if find_window(term.window) then
    M.close(num)
  else
    M.open(num, size, directory)
  end
end

function M.close_last_window()
  local buf = api.nvim_get_current_buf()
  local only_one_window = fn.winnr("$") == 1
  if only_one_window and vim.bo[buf].filetype == term_ft then
    -- Reset the window id so there are no hanging
    -- references to the terminal window
    for _, term in pairs(terminals) do
      if term.bufnr == buf then
        term.window = -1
        break
      end
    end
    -- FIXME switching causes the buffer
    -- switched to to have no highlighting
    -- no idea why
    vim.cmd("keepalt bnext")
  end
end

function M.on_term_open()
  T.add(
    T.identify(fn.bufname()),
    Terminal:new {
      id = get_term_id(),
      bufnr = api.nvim_get_current_buf(),
      window = api.nvim_get_current_win(),
      job_id = vim.b.terminal_job_id
    },
    function(term)
      term:resize()
    end
  )
end

--- @param num number
--- @param size number
--- @param directory string
function M.open(num, size, directory)
  directory = directory and vim.fn.expand(directory) or fn.getcwd()
  vim.validate {
    num = {num, "number"},
    size = {size, "number", true},
    directory = {directory, "string", true}
  }

  local term, created = get_or_create_term(num, directory)
  term:open(size, created)
end

function M.exec_command(args, count)
  vim.validate {args = {args, "string"}}
  if not args:match("cmd") then
    return echomsg(
      "TermExec requires a cmd specified using the syntax cmd='ls -l' e.g. TermExec cmd='ls -l'",
      "ErrorMsg"
    )
  end
  local parsed = parse_input(args)
  vim.validate {
    cmd = {parsed.cmd, "string"},
    dir = {parsed.dir, "string", true},
    size = {parsed.size, "number", true}
  }
  M.exec(parsed.cmd, count, parsed.size, parsed.dir)
end

--- @param cmd string
--- @param num number
--- @param size number
function M.exec(cmd, num, size, dir)
  vim.validate {
    cmd = {cmd, "string"},
    num = {num, "number"},
    size = {size, "number", true}
  }
  -- count
  num = num < 1 and 1 or num
  local term = get_or_create_term(num, dir)
  local created = false
  if not find_window(term.window) then
    M.open(num, size, dir)
  end
  --- TODO: find a way to do this without calling this function twice
  term, created = get_or_create_term(num, dir)
  if not created and dir and term.dir ~= dir then
    term:change_dir(dir)
  end
  fn.chansend(term.job_id, "clear" .. "\n" .. cmd .. "\n")
  vim.cmd("normal! G")
  vim.cmd("wincmd p")
  vim.cmd("stopinsert!")
end

--- @param num number
function M.close(num)
  local term = get_or_create_term(num)
  term:close()
  ui.update_origin_win(term.window)
end

--- only shade explicitly specified filetypes
function M.__apply_colors()
  local ft = vim.bo.filetype

  if not vim.bo.filetype or vim.bo.filetype == "" then
    ft = "none"
  end

  local allow_list = config.get("shade_filetypes") or {}
  table.insert(allow_list, term_ft)

  local is_enabled_ft = false
  for _, filetype in ipairs(allow_list) do
    if ft == filetype then
      is_enabled_ft = true
      break
    end
  end
  if vim.bo.buftype == "terminal" and is_enabled_ft then
    colors.darken_terminal()
  end
end

function M.toggle_command(args, count)
  local parsed = parse_input(args)
  vim.validate {
    size = {parsed.size, "number", true},
    directory = {parsed.dir, "string", true}
  }
  if parsed.size then
    parsed.size = tonumber(parsed.size)
  end
  M.toggle(count, parsed.size, parsed.dir)
end

--- If a count is provided we operate on the specific terminal buffer
--- i.e. 2ToggleTerm => open or close Term 2
--- if the count is 1 we use a heuristic which is as follows
--- if there is no open terminal window we toggle the first one i.e. assumed
--- to be the primary. However if several are open we close them.
--- this can be used with the count commands to allow specific operations
--- per term or mass actions
--- @param count number
--- @param size number
--- @param dir string
function M.toggle(count, size, dir)
  vim.validate {
    count = {count, "number", true},
    size = {size, "number", true}
  }
  if count > 1 then
    toggle_nth_term(count, size, dir)
  else
    smart_toggle(count, size, dir)
  end
end

function M.setup(user_prefs)
  local conf = config.set(user_prefs)
  setup_global_mappings()
  local autocommands = {
    {
      "BufEnter",
      "term://*toggleterm#*",
      "nested",
      "lua require'toggleterm'.close_last_window()"
    },
    {
      "TermOpen",
      "term://*toggleterm#*",
      "lua require'toggleterm'.on_term_open()"
    }
  }
  if conf.shade_terminals then
    local is_bright = colors.is_bright_background()

    -- if background is light then darken the terminal a lot more to increase contrast
    local factor =
      conf.shading_factor and type(conf.shading_factor) == "number" and conf.shading_factor or
      (is_bright and 3 or 1)

    local amount = factor * SHADING_AMOUNT
    colors.set_highlights(amount)

    vim.list_extend(
      autocommands,
      {
        {
          -- call set highlights once on vim start
          -- as this plugin might not be initialised till
          -- after the colorscheme autocommand has fired
          -- reapply highlights when the colorscheme
          -- is re-applied
          "ColorScheme",
          "*",
          string.format("lua require'toggleterm'.__set_highlights(%d)", amount)
        },
        {
          "TermOpen",
          "term://*zsh*,term://*bash*,term://*toggleterm#*",
          "lua require('toggleterm').__apply_colors()"
        }
      }
    )
  end
  utils.create_augroups({ToggleTerminal = autocommands})
end

return M
