local api = vim.api
local fn = vim.fn

local spy = require("luassert.spy")

local toggleterm = require("toggleterm")
local constants = require("toggleterm.constants")

local ui = require("toggleterm.ui")
local t = require("toggleterm.terminal")

---@type Terminal
local Terminal = t.Terminal
---@type Terminal[]
local terminals

---Return if a terminal has windows
---@param term table
---@return any
local function term_has_windows(term)
  return ui.find_open_windows(
    function(buf)
      return buf == term.bufnr
    end
  )
end

describe(
  "ToggleTerm tests:",
  function()
    before_each(
      function()
        terminals = require("toggleterm.terminal").get_all()

        toggleterm.setup {
          open_mapping = [[<c-\>]]
        }
      end
    )

    after_each(
      function()
        require("toggleterm.terminal").reset()
      end
    )

    describe(
      "toggling terminals - ",
      function()
        it(
          "new terminals are assigned incremental ids",
          function()
            local test1 = Terminal:new():toggle()
            local test2 = Terminal:new():toggle()
            local test3 = Terminal:new():toggle()
            assert.are.same(test1.id, 1)
            assert.are.same(test2.id, 2)
            assert.are.same(test3.id, 3)
          end
        )

        it(
          "should open a terminal window on toggle",
          function()
            local test1 = Terminal:new()
            test1:toggle()
            assert.is_true(api.nvim_buf_is_valid(test1.bufnr))
            assert.is_true(vim.tbl_contains(api.nvim_list_wins(), test1.window))
          end
        )

        it(
          "should close a terminal window if open",
          function()
            local test1 = Terminal:new()
            test1:toggle()
            assert.is_true(vim.tbl_contains(api.nvim_list_wins(), test1.window))
            test1:toggle()
            assert.is_not_true(vim.tbl_contains(api.nvim_list_wins(), test1.window))
          end
        )

        it(
          "should toggle a specific buffer if a count is passed",
          function()
            toggleterm.toggle(2, 15)
            assert.equals(#terminals, 1)
            local term = terminals[1]
            assert.is_true(term_has_windows(term))
          end
        )
      end
    )

    describe(
      "terminal buffers options - ",
      function()
        before_each(
          function()
            require("toggleterm.config").set {shade_terminals = true}
          end
        )
        it(
          "should give each terminal a winhighlight",
          function()
            local test1 = Terminal:new():toggle()
            local winhighlight = vim.wo[test1.window].winhighlight
            assert.is.truthy(winhighlight:match("Normal:DarkenedPanel"))
          end
        )
        it(
          "should set the correct filetype",
          function()
            local test1 = Terminal:new():toggle()
            local ft = vim.bo[test1.bufnr].filetype
            assert.equals(constants.term_ft, ft)
          end
        )
      end
    )

    describe(
      "executing commands - ",
      function()
        it(
          "should open a terminal to execute commands",
          function()
            toggleterm.exec("ls", 1)
            assert.is_true(#terminals == 1)
            assert.is_true(term_has_windows(terminals[1]))
          end
        )

        it(
          "should change terminal's directory if specified",
          function()
            toggleterm.exec("ls", 1, 15, fn.expand("~/"))
            assert.is_true(#terminals == 1)
            assert.is_true(term_has_windows(terminals[1]))
          end
        )

        ---TODO figure out how to stub class methods
        pending(
          "should send commands to a terminal on exec",
          function()
            local test1 = Terminal:new():toggle()
            spy.on(test1, "send")
            toggleterm.exec('echo "hello world"', 1)
            assert.spy(test1.send).was_called()
          end
        )
      end
    )
  end
)
