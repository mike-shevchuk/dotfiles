# Setup nvim


### Install for using notebook

    ```bash
    pip install ipykernel jupytext pynvim jupyter_client cairosvg plotly kaleido pyperclip nbformat pillow

    python -m ipykernel install --user --name nvim_notebook  

    :UpdateRemotePlugins
    :MasonInstallAll
    ```


🛠️ Setting up for the first time
* Warning

DataNvim will only render images if the terminal it's used on is Kitty!

* Install all the listed dependencies
* Install Kitty
* Install luarocks, Lua language's package manager.
* Install the magick rock with: luarocks --local --lua-version=5.1 install magick
Create a virtual environment for Neovim in ~/.virtualenvs/
mkdir ~/.virtualenvs
cd ~/.virtualenvs
python -m venv neovim
Activate the virtual environment and install the beforementioned python packages with:
source ~/.virtualenvs/neovim/bin/activate
pip install ipykernel jupytext pynvim jupyter_client cairosvg plotly kaleido pyperclip nbformat pillow
python -m ipykernel
deactivate
Install ipykernel and jupytext in your project-scoped virtual environment
cd whatever/directory/your/project/is/in
source venv/bin/activate
pip install ipykernel jupytext
python -m ipykernel install --user --name project_name
Backup your current Neovim configuration
mv ~/.config/nvim ~/config/nvim.bak
Install DataNvim's configuration
git clone https://github.com/NoOPeEKS/DataNvim.git ~/.config/nvim && nvim
Run the following commands:
:UpdateRemotePlugins
:MasonInstallAll
Open your notebook with the virtual environment activated and load the kernel with :MoltenInit project_name or Space + m + i.
Start executing cells with Keybindings
⌨️ Keybindings
Vim actions
Key	Mode	Action
Ctrl + h	i	Navigate left in insert mode
Ctrl + j	i	Navigate down in insert mode
Ctrl + k	i	Navigate up in insert mode
Ctrl + l	i	Navigate right in insert mode
Ctrl + s	i, v, n	Save current buffer
Space + x	n	Close current buffer
Tab	n	Go to next buffer
Shift + Tab	n	Go to previous buffer
Plugins
NvimTree
Key	Mode	Action
Ctrl + n	n	Toggle file explorer
Ctrl + j	n	Focus file explorer
None-ls
Key	Mode	Action
Space + g + f	n	Format current buffer
Molten.nvim
Key	Mode	Action
Space + m + i	n	Molten Init Python Kernel
Space + m + l	n	Molten Evaluate Current Line
Space + m + v	v	Molten Evaluate Visual Selection
Space + m + o	n	Molten Enter Cell Output
Space + m + h	n	Molten Hide Output
Telescope
Key	Mode	Action
Space + f + f	n	Telescope Fuzzy Find File
Space + f + w	n	Telescope Fuzzy Find Word
Space + f + b	n	Telescope Fuzzy Find Buffers
Space + f + o	n	Telescope Fuzzy Find Oldfiles
Space + f + z	n	Telescope Fuzzy Find Current Buffer
Space + f + h	n	Telescope Help Tags
LSP
Key	Mode	Action
g + D	n	Go to Declaration
g + d	n	Go to Definition
K	n	Hover
g + i	n	Go to Implementation
leader + c + a	n	Code Action
Ctrl + k	n	Signature Help
Space + w + a	n	Add Workspace Folder
Space + w + r	n	Remove Workspace Folder
Space + w + l	n	List Workspace Folders
Space + D	n	Go to Type Definition
Space + r + n	n	Rename
g + r	n	List References
Space + e	n	Open Diagnostic Float
[ + d	n	Go to Previous Diagnostic
] + d	n	Go to Next Diagnostic
Space + q	n	Set to Quickfix list
