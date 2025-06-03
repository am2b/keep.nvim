# keep.nvim

Keep your buffers across Neovim restarts — per working directory.

## ✨ Features

- Automatically saves all open file buffers on exit
- Restore all previously opened files with a single keypress
- Focus remains on the file you launched Neovim with (e.g. `nvim myfile.txt`)
- Uses hashed working directory path to avoid name collisions
- Lightweight and dependency-free

## 📦 Installation (using [lazy.nvim](https://github.com/folke/lazy.nvim))

```lua
{
    "am2b/keep.nvim",
    lazy = false,

    config = function()
        require("keep").setup()
    end,
}
```

## 🚀 Usage

### Automatically saves buffers on exit

Whenever you exit Neovim, `keep.nvim` will record the list of open file buffers in a session file, specific to your current working directory.

The session file name is a SHA256 hash of your full working directory path, which ensures that similarly named folders (like `~/project/foo` and `~/work/foo`) don't conflict.

### Restore buffers manually

After launching Neovim in the same working directory, press:

```
<space>ls
```

This will restore the buffer list from the last session, without changing the focus away from the file you’re currently editing.

### Example

```sh
# Day 1
$ cd my-project
$ nvim main.py utils.py

# Files are saved on exit

# Day 2
$ cd my-project
$ nvim README.md        # you’re editing README.md now
# Press <space>ls       # main.py and utils.py will be restored silently, and the focus will STILL remain on README.md ✅
```

## 🛠️ How it works

- Session files are saved to: `~/.local/state/nvim/keep/<hash>.txt`
- The first line of each file contains the original working directory path (commented)
- Only real files are tracked (no help buffers, terminals, etc.)
- Buffer focus is preserved on restore

## 🧠 Why not use sessions or workspaces?

This plugin is intentionally minimal and non-invasive. It doesn’t try to manage window layout, tab state, or LSP context — just your open files.
