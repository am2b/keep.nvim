local M = {}

local log_file_name = "keep"
local log_level = "info"

local log_file = vim.fn.stdpath("state") .. "/" .. log_file_name .. ".log"

local level_map = { debug = 1, info = 2, error = 3 }

local function should_log(level)
    return level_map[level] >= level_map[log_level]
end

local function append_line(line)
    local f = io.open(log_file, "a")
    if f then
        f:write(os.date("[%Y-%m-%d_%H:%M:%S] ") .. tostring(line) .. "\n")
        f:close()
    end
end

function M.log(level, msg)
    if should_log(level) then
        append_line("[" .. level:upper() .. "] " .. msg)
        --如果当前日志级别是"error",就将调用栈信息追加到日志中
        if level == "error" then
            --2:从调用者的位置开始记录(跳过当前log()函数)
            append_line(debug.traceback("", 2))
        end
    end
end

function M.debug(msg) M.log("debug", msg) end

function M.info(msg) M.log("info", msg) end

function M.error(msg) M.log("error", msg) end

return M
