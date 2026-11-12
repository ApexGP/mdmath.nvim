-- Appends every render request/response to /tmp/mdmath-dump.log. Run it before
-- reproducing a rendering problem:
--
--   :luafile tests/manual/dump-requests.lua
--
-- The log shows the exact TeX sent to MathJax (REQ), the response (RES/ERR) and
-- the image id handed to the terminal (IMG). Duplicated images with one REQ mean
-- a terminal-side problem; two REQ with different payloads mean a parser issue.
---@diagnostic disable: duplicate-set-field

local Processor = require'mdmath.Processor'
local Image = require'mdmath.Image'

local LOG = '/tmp/mdmath-dump.log'
local out = assert(io.open(LOG, 'a'), 'cannot open ' .. LOG)

---@param fmt string
local function log(fmt, ...)
    out:write(string.format(fmt, ...):gsub('\n', '\\n') .. '\n')
    out:flush()
end

local real_from_bufnr = Processor.from_bufnr
Processor.from_bufnr = function(bufnr)
    local processor = real_from_bufnr(bufnr)
    if not processor._mdmath_dumped then
        processor._mdmath_dumped = true
        local real_request = processor.request
        function processor:request(data, cell_width, cell_height, width, height, flags, color, callback)
            log('REQ %q flags=%d %dx%d cells color=%s', data, flags, width, height, color)
            return real_request(self, data, cell_width, cell_height, width, height, flags, color,
                function(res, err)
                    if res then
                        log('RES %dx%d %s', res.width, res.height, res.data)
                    else
                        log('ERR %s', tostring(err))
                    end
                    return callback(res, err)
                end)
        end
    end
    return processor
end

local real_new = Image.new
Image.new = function(rows, cols, payload)
    local image = real_new(rows, cols, payload)
    log('IMG id=%s %dx%d %s', image and tostring(image.id) or 'nil', rows, cols, tostring(payload))
    return image
end

log('--- dump start ---')
print('mdmath request dump -> ' .. LOG)
