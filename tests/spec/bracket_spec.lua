-- `\[ ... \]` display math is not part of the markdown_inline grammar, so the
-- overlay scans each injected block for it. Code spans must be left alone: a
-- regex like `\[0-9\]` is not an equation.
---@diagnostic disable: duplicate-set-field

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')
local t = dofile(root .. '/tests/helper.lua')
t.bootstrap()

local mdmath = require'mdmath'
mdmath.setup({update_interval = 30})
-- The FileType autocmd would enable buffers behind the spec's back.
vim.api.nvim_clear_autocmds({group = 'MdMath'})
t.stub_image()

local Processor = require'mdmath.Processor'
local requests = {}
Processor.from_bufnr = function()
    return {
        request = function(_, data, _, _, width, height, flags, _, callback)
            requests[#requests + 1] = {data = data, width = width, height = height, flags = flags}
            vim.schedule(function()
                callback({width = width, height = height, data = '/tmp/mdmath-bracket.png'}, nil)
            end)
        end,
    }
end

t.collect_marks()

---@param lines string[]
---@return integer
local function parse(lines)
    requests = {}
    local bufnr = t.markdown_buffer(lines)
    t.full_view(lines)
    mdmath.enable(bufnr)
    return bufnr
end

local bufnr = parse({'x \\[a + b\\] y'})
t.eq(#requests, 1, 'inline bracket equation requested')
t.eq(requests[1].data, 'a + b', 'brackets are stripped from the TeX')
t.eq(requests[1].flags, 2, 'inline bracket math is centred')
mdmath.disable(bufnr)

bufnr = parse({'\\[c^2\\]'})
t.eq(#requests, 1, 'whole-line bracket equation requested')
t.eq(requests[1].data, 'c^2', 'whole-line TeX')
t.eq(requests[1].flags, 1, 'whole-line bracket math is dynamic')
mdmath.disable(bufnr)

bufnr = parse({'\\[', 'd + e', '\\]'})
t.eq(#requests, 1, 'multi-line bracket equation requested')
t.eq(requests[1].data, 'd + e', 'multi-line TeX')
t.eq(requests[1].height, 3, 'multi-line height follows the source rows')
mdmath.disable(bufnr)

bufnr = parse({'`\\[f\\]`'})
t.eq(#requests, 0, 'brackets inside a code span are not math')
mdmath.disable(bufnr)

-- A `\[` inside `$ ... $` is part of that equation: nesting would put two
-- images on the same range.
bufnr = parse({'$a \\[b\\] c$'})
t.eq(#requests, 1, 'brackets inside dollar math are not a second equation')
t.ok(requests[1].data:find('a \\[b\\] c', 1, true) ~= nil, 'the dollar equation keeps its TeX')
mdmath.disable(bufnr)

-- `\\[1ex]` is a LaTeX line break, not a delimiter.
bufnr = parse({'x \\\\[y\\\\] z'})
t.eq(#requests, 0, 'escaped brackets are not math')
mdmath.disable(bufnr)

bufnr = parse({'$g$'})
t.eq(#requests, 1, 'dollar math is unchanged')
t.eq(requests[1].data, 'g', 'dollar delimiters are still stripped')
mdmath.disable(bufnr)

t.finish()
