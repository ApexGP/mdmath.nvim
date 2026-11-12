local nvim = require'mdmath.nvim'
local util = require'mdmath.util'
local ts = vim.treesitter
local uv = vim.uv
local Equation = require'mdmath.Equation'
local config = require'mdmath.config'.opts
local capability = require'mdmath.capability'

local augroup = nvim.create_augroup('MdMathManager', {clear = true})

local M = {}
---@type fun(bufnr: integer)|nil
local on_update = nil
---@type table<integer, mdmath.overlay.Buffer>
local buffers = {}

---@class mdmath.overlay.Buffer
---@field bufnr integer
---@field equations mdmath.Equation[]
---@field parser vim.treesitter.LanguageTree
---@field active boolean
---@field timer uv.uv_timer_t
---@field _init fun(self: mdmath.overlay.Buffer, bufnr: integer)
---@field new fun(bufnr: integer): mdmath.overlay.Buffer
local Buffer = util.class 'Buffer'

local INLINE_LANG = 'markdown_inline'
---@type vim.treesitter.Query|nil
local inline_query = nil
---@type vim.treesitter.Query|nil
local code_query = nil

-- Compiling the query on every parse tick is wasteful; it only depends on the
-- language, never on the buffer.
---@return vim.treesitter.Query
local function get_inline_query()
    if not inline_query then
        inline_query = vim.treesitter.query.parse(INLINE_LANG, '(latex_block) @block')
    end
    return inline_query
end

--- Code spans are not math even when they contain `\[` (regexes, shell globs).
---@return vim.treesitter.Query
local function get_code_query()
    if not code_query then
        code_query = vim.treesitter.query.parse(INLINE_LANG, '(code_span) @code')
    end
    return code_query
end

-- FIX: Temporary workaround before NeoVim 0.12
---@param bufnr integer
---@param lang string
---@return vim.treesitter.LanguageTree
local function get_parser(bufnr, lang)
    local parser = ts.get_parser(bufnr, lang)
    if not parser then
        error('Parser not found for ' .. lang, 2)
    end

    return parser
end

function Buffer:_init(bufnr)
    self.bufnr = bufnr
    self.equations = {}
    self.parser = get_parser(bufnr, 'markdown')
    self.active = true
    self.timer = assert(uv.new_timer(), 'failed to create a timer')

    self:attach()

    nvim.create_autocmd({'InsertLeave'}, {
        buffer = bufnr,
        group = augroup,
        callback = function()
            self:parse_view()
        end
    })
    nvim.create_autocmd({'WinScrolled'}, {
        buffer = bufnr,
        group = augroup,
        callback = function()
            self:reset_timer()
        end
    })

    self:parse_view()
end

---@param reset boolean|nil restart the update timer
function Buffer:clear(reset)
    for _, eq in ipairs(self.equations) do
        eq:invalidate()
    end
    self.equations = {}

    if reset then
        self:reset_timer()
    end
end

--- Stops parsing and drops every equation of the buffer. Idempotent.
function Buffer:free()
    if not self.active then
        return
    end
    self.active = false
    buffers[self.bufnr] = nil

    self.timer:stop()
    self.timer:close()

    self:clear(false)

    nvim.clear_autocmds {
        group = augroup,
        buffer = self.bufnr
    }
end

--- Debounces `parse_view()` by `update_interval`.
function Buffer:reset_timer()
    self.timer:start(config.update_interval, 0, vim.schedule_wrap(function()
        return self:parse_view()
    end))
end

--- Listens for edits and detaches.
function Buffer:attach()
    nvim.buf_attach(self.bufnr, false, {
        on_lines = function()
            if not self.active then
                return true
            end
            self:reset_timer()
        end,
        on_detach = function()
            self:free()
        end
    })
end

--- Parses the currently visible window range.
function Buffer:parse_view()
    local start_row, end_row = util.get_current_view()
    self:parse(start_row, end_row)
end

--- Rebuilds `self.equations` for the range, reusing equations whose source range
--- and text did not change and invalidating the ones that scrolled out.
---@param start_row integer 0-indexed, inclusive
---@param end_row integer 1-indexed, exclusive
function Buffer:parse(start_row, end_row)
    assert(type(start_row) == 'number', 'start_row must be a number')
    assert(type(end_row) == 'number', 'end_row must be a number')

    local bufnr = self.bufnr
    local parser = self.parser
    parser:parse({start_row, end_row})

    local inlines = parser:children()[INLINE_LANG]
    if not inlines then
        return nil
    end
    local query = get_inline_query()

    --- `0` marks an equation that was already claimed by this pass.
    ---@type (mdmath.Equation|0)[]
    local old_equations = self.equations
    local equations = {}

    ---@param sr integer
    ---@param sc integer
    ---@param er integer
    ---@param ec integer
    ---@param text string
    local function process_equation(sr, sc, er, ec, text)
        -- FIXME: Iterating over all equations is not efficient, we can use a hash table
        local equation = nil
        for key, eq in ipairs(old_equations) do
            -- `0` marks an equation that was already claimed by this pass.
            if eq ~= 0 and eq.valid and eq.pos[1] == sr and eq.pos[2] == sc and eq.text == text then
                equation = eq
                old_equations[key] = 0
                break
            end
        end

        equation = equation or Equation.new(bufnr, sr, sc, text)
        if equation then
            table.insert(equations, equation)
        end
    end

    --- Blocks already claimed by this pass, so overlapping injected trees cannot
    --- add the same `\[ ... \]` twice.
    ---@type table<string, boolean>
    local seen_brackets = {}

    --- `\[ ... \]` is display math in LaTeX but not part of the injected
    --- grammar. Scan the lines of this inline tree; the tree is already known to
    --- overlap the viewport, so a block that starts above it is still found.
    --- Matches inside code spans (`\[0-9\]` in a regex) and inside an existing
    --- `$...$` capture are ignored: nesting would put two images on one range.
    ---@param root TSNode
    ---@param sr integer
    ---@param sc integer
    ---@param er integer
    ---@param ec integer
    ---@param latex integer[][] ranges of `$` captures in this tree
    local function scan_bracket_blocks(root, sr, sc, er, ec, latex)
        local protected = latex
        for _, node in get_code_query():iter_captures(root, bufnr) do
            protected[#protected + 1] = {node:range()}
        end

        ---@param row integer
        ---@param col integer
        ---@return boolean
        local function in_protected(row, col)
            for _, range in ipairs(protected) do
                local psr, psc, per, pec = range[1], range[2], range[3], range[4]
                if (row > psr or (row == psr and col >= psc))
                    and (row < per or (row == per and col < pec)) then
                    return true
                end
            end
            return false
        end

        --- A preceding backslash makes the delimiter escaped (`\\[1ex]`).
        ---@param line string
        ---@param pos integer 1-based index of the delimiter's backslash
        ---@return boolean
        local function escaped(line, pos)
            return pos > 1 and line:sub(pos - 1, pos - 1) == '\\'
        end

        local lines = nvim.buf_get_lines(bufnr, sr, er + 1, false)
        local open_row, open_col

        for offset, line in ipairs(lines) do
            local row = sr + offset - 1
            local from = row == sr and sc + 1 or 1
            local to = row == er and ec or #line

            local i = from
            while i <= to do
                local open_at = line:find('\\[', i, true)
                local close_at = line:find('\\]', i, true)

                if open_at and (not close_at or open_at < close_at) then
                    if not escaped(line, open_at) and not in_protected(row, open_at - 1) then
                        open_row, open_col = row, open_at - 1
                    end
                    i = open_at + 2
                elseif close_at then
                    if not escaped(line, close_at)
                        and not in_protected(row, close_at - 1)
                        and open_row then
                        local close_row, close_col = row, close_at + 1
                        local key = open_row .. ':' .. open_col
                        if not seen_brackets[key] and close_row >= start_row and open_row < end_row then
                            seen_brackets[key] = true
                            local text = table.concat(
                                nvim.buf_get_text(bufnr, open_row, open_col, close_row, close_col, {}), '\n')
                            process_equation(open_row, open_col, close_row, close_col, text)
                        end
                        open_row, open_col = nil, nil
                    end
                    i = close_at + 2
                else
                    break
                end
            end
        end
    end

    ---@param tree TSTree
    local function get_queries(tree)
        local root = tree:root()
        local tsr, tsc, ter, tec = root:range()

        -- Each injected `markdown_inline` tree covers one markdown block, so
        -- rejecting the trees that cannot overlap the viewport is far cheaper than
        -- running the query over the whole document on every tick. Unlike passing
        -- the viewport to `iter_captures` (which filters by capture *start* row),
        -- this still sees a block that begins above the viewport and ends inside.
        if ter < start_row or tsr >= end_row then
            return
        end

        local latex = {}
        for _, node in query:iter_captures(root, bufnr) do
            local range = {node:range()}
            latex[#latex + 1] = range
            local sr, sc, er, ec = range[1], range[2], range[3], range[4]
            if er >= start_row and sr < end_row then
                local value = ts.get_node_text(node, bufnr)
                process_equation(sr, sc, er, ec, value)
            end
        end

        scan_bracket_blocks(root, tsr, tsc, ter, tec, latex)
    end
    inlines:for_each_tree(get_queries)

    for _, eq in ipairs(old_equations) do
        if eq ~= 0 then
            ---@cast eq mdmath.Equation
            if eq.valid then
                if (not eq.pos[1] or (start_row <= eq.pos[1] and eq.pos[1] < end_row)) then
                    eq:invalidate()
                else
                    -- add equations out of the range
                    table.insert(equations, eq)
                end
            end
        end
    end

    self.equations = equations

    if on_update then
        on_update(bufnr)
    end
end

--- Callback invoked after a buffer re-parses its equations. Used by the float
--- preview to follow edits in real time.
---@param callback fun(bufnr: integer)|nil
function M.on_update(callback)
    on_update = callback
end

--- Whether the overlay is tracking a buffer (it holds parsed equations).
---@param bufnr integer
---@return boolean
function M.is_enabled(bufnr)
    return buffers[bufnr] ~= nil
end

--- Equation whose source range contains (row, col).
---@param bufnr integer
---@param row integer 0-indexed
---@param col integer 0-indexed
---@return mdmath.Equation|nil
function M.equation_at(bufnr, row, col)
    local buffer = buffers[bufnr]
    if not buffer then
        return nil
    end

    for _, eq in ipairs(buffer.equations) do
        if eq.valid and eq.pos[1] then
            local first = eq.pos[1]
            local line_count = eq.lines and #eq.lines or 1
            if row >= first and row < first + line_count then
                if line_count > 1 then
                    return eq
                end
                local start_col = eq.pos[2]
                if col >= start_col and col <= start_col + #eq.text then
                    return eq
                end
            end
        end
    end

    return nil
end

---@param bufnr integer
---@return mdmath.overlay.Buffer|nil
local function create_buffer(bufnr)
    if not nvim.buf_is_valid(bufnr) then
        return nil
    end

    local buf = Buffer.new(bufnr)
    buffers[bufnr] = buf
    return buf
end

local warned_no_placeholders = false

--- Enables rendering for a buffer, unless the terminal cannot show placeholders.
---@param bufnr integer 0 means the current buffer
function M.enable(bufnr)
    if bufnr == 0 then
        bufnr = nvim.get_current_buf()
    end
    if buffers[bufnr] then
        return
    end

    local supported, reason, confident = capability.supports_placeholders()
    if confident and not supported then
        -- Placeholders are the only text-anchored placement mechanism in the
        -- protocol. Without them the plugin would hide the source text and print
        -- placeholder characters the terminal renders as tofu, so do nothing but
        -- explain once.
        if not warned_no_placeholders then
            warned_no_placeholders = true
            vim.schedule(function()
                vim.notify('mdmath.nvim: ' .. reason .. '\nEquations stay as source text. '
                    .. 'Run :checkhealth mdmath for details.', vim.log.levels.WARN)
            end)
        end
        return
    end

    if not create_buffer(bufnr) then
        error('Invalid buffer: ' .. bufnr)
    end
end

---@param bufnr integer 0 means the current buffer
function M.disable(bufnr)
    if bufnr == 0 then
        bufnr = nvim.get_current_buf()
    end
    local buffer = buffers[bufnr]
    if buffer then
        buffer:free()
    end
end

function M.disable_all()
    for _, buffer in pairs(buffers) do
        buffer:free()
    end
end

--- Re-parses the buffer (invalidates every equation it knows about).
---@param bufnr integer 0 means the current buffer
function M.clear(bufnr)
    if bufnr == 0 then
        bufnr = nvim.get_current_buf()
    end
    local buffer = buffers[bufnr]
    if buffer then
        buffer:clear(true)
    end
end

-- `VimLeave` is not buffer-local. Registering it per buffer would leak one
-- callback for every enabled buffer, so keep a single global one.
nvim.create_autocmd({'VimLeave'}, {
    group = augroup,
    callback = function()
        M.disable_all()
    end,
})

return M
