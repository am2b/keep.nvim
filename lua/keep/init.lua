--定义模块
--最终这个M就是require("keep")得到的模块对象
local M = {}

local function get_session_file()
    --获取当前工作目录(cwd),这是一个绝对路径(neovim启动的路径)
    local cwd = vim.loop.cwd()
    --获取neovim的state目录,通常是~/.local/state/nvim
    --vim.fn.stdpath("state"):返回的是一个绝对路径
    local session_dir = vim.fn.stdpath("state") .. "/keep"
    --创建目录,"p"表示递归创建
    vim.fn.mkdir(session_dir, "p")
    --提取工作目录的绝对路径的最后一部分(启动neovim的那个文件夹的名字)来作为会话文件名
    --cwd:是当前工作目录的绝对路径
    --:p(path):将路径转换为绝对路径,虽然cwd本身已经是绝对路径,但这个修饰符确保了这一点
    --:h(head):获取路径的目录部分
    --例如:
    --如果cwd是/home/user/my_project,则:h的结果仍然是/home/user/my_project(因为它是目录本身,没有文件名部分)
    --如果cwd是/home/user/my_project/file.txt,则:h的结果是/home/user/my_project
    --:t(tail):获取路径的最后一部分(文件名或目录名)
    --例如:
    --如果cwd是/home/user/my_project,则:t的结果是my_project
    local session_name = vim.fn.fnamemodify(cwd, ":p:h:t")
    --返回存储会话的文件的绝对路径
    return session_dir .. "/" .. session_name .. ".txt"
end

function M.save_session()
    --获取所有buffer的ID列表(数字数组)
    --每个缓冲区ID代表一个打开的文件,一个帮助文档,一个快速列表等
    local bufs = vim.api.nvim_list_bufs()
    local files = {}

    --buf:缓冲区ID
    for _, buf in ipairs(bufs) do
        --vim.api.nvim_buf_is_loaded():检查给定ID的缓冲区是否已经被加载到内存中(当前正在编辑或查看的文件)
        if vim.api.nvim_buf_is_loaded(buf)
            --vim.api.nvim_buf_get_option(buf,"buftype"):获取给定缓冲区的buftype选项的值
            --常见的buftype值包括:
            --""(空字符串):普通文件缓冲区(通常编辑的实际文件)
            --nofile:没有关联文件的缓冲区,通常用于scratchpad或临时文本
            --nowrite:缓冲区不能被写入,通常用于帮助文件或只读文件
            --quickfix:快速修复列表
            --prompt:提示缓冲区
            --terminal:终端缓冲区
            --== "":这个条件表示我们只对普通文件缓冲区感兴趣,排除掉那些特殊用途的缓冲区
            and vim.api.nvim_buf_get_option(buf, "buftype") == ""
            --vim.api.nvim_buf_get_name(buf):获取给定缓冲区的名称(即它所关联的文件路径)
            --有文件路径的才保存(排除掉一些没有明确文件路径的临时缓冲区)
            and vim.api.nvim_buf_get_name(buf) ~= "" then
            --files:通常存储的是文件的绝对路径
            table.insert(files, vim.api.nvim_buf_get_name(buf))
        end
    end

    local session_file = get_session_file()
    local f = io.open(session_file, "w")
    if f then
        for _, file in ipairs(files) do
            f:write(file .. "\n")
        end
        f:close()
    end
end

function M.load_session()
    local session_file = get_session_file()
    local f = io.open(session_file, "r")
    if not f then
        vim.notify("No session found for this directory.", vim.log.levels.INFO)
        return
    end

    --收集buffer(文件)的路径
    local files = {}
    for line in f:lines() do
        table.insert(files, line)
    end
    f:close()

    --当前buffer的文件路径
    --vim.api.nvim_buf_get_name(0):获取当前缓冲区(0代表当前缓冲区)的文件路径
    --vim.api.nvim_buf_get_name(0):在没有打开文件时会返回空字符串(比如在命令行nvim,这样仅打开了nvim,但是没有打开任何文件)
    --这个路径通常也是绝对路径,我们获取它的目的是为了避免重复打开当前已经打开的文件
    local current = vim.api.nvim_buf_get_name(0)

    --打开所有buffer(排除当前)
    for _, file in ipairs(files) do
        --file ~= current:确保要打开的文件不是当前已经打开的缓冲区,避免不必要的重新加载
        --vim.fn.filereadable(file) == 1:检查给定路径的文件是否可读(避免尝试打开一个已经不存在或没有权限访问的文件),1:表示可读,0:表示不可读
        if file ~= current and vim.fn.filereadable(file) == 1 then
            --vim.cmd():用于执行命令字符串
            --edit:是neovim中用于打开(或切换到)某个文件的命令
            --vim.fn.fnameescape(file):用于转义文件路径中的特殊字符(如空格,%,#等),使其能够安全地作为neovim命令的参数,如果没有这个转义,包含特殊字符的文件路径可能会导致命令解析错误
            vim.cmd("edit " .. vim.fn.fnameescape(file))
        end
    end

    --如果是通过nvim file.txt这样的形式打开的neovim
    if current ~= "" then
        --再次获取当前buffer的文件路径
        local current_after_load = vim.api.nvim_buf_get_name(0)
        --如果加载会话后,当前焦点不在原始的启动文件上,则切换回去
        if current ~= current_after_load then
            --检查要切换过去的buffer所对应的文件是否仍然存在且可读,以提高健壮性
            if vim.fn.filereadable(current) == 1 then
                vim.cmd("buffer " .. vim.fn.fnameescape(current))
                vim.notify("Set focus back to: " .. current, vim.log.levels.INFO)
            else
                vim.notify("Could not set focus back to file: " .. current .. " (file not readable).",
                    vim.log.levels.WARN)
            end
        end
    end

    --vim.notify("Session restored (" .. #files .. " files).", vim.log.levels.INFO)
end

function M.setup()
    --VimLeavePre:在退出neovim之前触发save_session()
    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = M.save_session,
    })

    vim.keymap.set("n", "<space>ls", M.load_session, { desc = "Restore session" })
end

--返回模块表M,供require("keep")使用
return M
