# ProjectConfig plugin for Vim

Allows you to load a Vim script when entering a project tree or every time a buffer from that
file is opened.

## Installation

### Use a Vim plugin manager
Using a plugin manager for Vim like Vundle or Pathogen is recommended. For Vundle for example 
you should add a line like `Plugin 'terminatorul/ProjectConfig'` to your `.vimrc` file, between
the `vundle#begin()` and `vundle::end()` lines, then run `:PluginInstall` command in Vim.

### Manual commands
Run in a console:
```
    cd ~/.vim
    git clone "https://github.com/terminatorul/ProjectConfig.git"
```
Open Vim and append the following line to your `~/.vimrc` file:
```
    set runtimepath-=~/.vim/ProjectConfig
```

## Usage

Two kinds of vimscript files can be associated with any project tree:
* a `project` script, that will be `:source`d the first time you `:cd ` inside the project 
  directory in Vim, or the first time you `:edit` a file from the project tree
* a `file` script, that will be `:sourced`d every single time you open/edit a file from the
  project tree

By default the `project` script has the same name as the project, with `.vim` extension added,
and is searched in the `~/.vim/project/` directory (`~/vimfiles/project/` for Windows systems).
The `file` script has the name of the project with an appended suffix of `.files.vim`
(`_files.vim` for Windows).

### `ProjectConfig#SetScript('Name', 'Path', 'ProjectScriptPath', 'FileScriptPath)`
### `ProjectConfig#SetScript('Name', 'Path')`
### `ProjectConfig#SetScript('Path')`

Call the function to associate a project tree with a project script and a file script. The only
required argument is the `Path`, other can be omitted. If not specified, the default values are:
* the project `Name` is the last path component from `Path`
* the project script is `~/.vim/project/<Name>.vim`
* the file script is `~/.vim/project/<Name>.file.vim` if file exists, or no file script otherwise.

The `~/.vim/` directory is use for Linux, `~/vimfiles` for Windows. Also the file script for
Windows has a different suffix `_files.vim` instead of `.files.vim`.

Use this function in the user `.vimrc` or `_vimrc` once for every project tree that you want to
associate scripts with.

### `:ProjectConfig Name Path ProjectScript FileScript
### `:ProjectconfigAdd 'Name', 'Path', 'ProjectScript', 'FileScript'

Same as the `ProjectConfig#SetScript` function above, but since these are Vim commands they are
only available after this plugin has been loaded by Vim, most importantly they are not
available yet in the `_vimrc` file. Arguments other the `Path` are optional just like for the
function.

### ` ProjectConfig#FindLoad('Name')`
### `:ProjectConfigEnter Name
### `:ProjectConfigOpen 'Name'

Open the named project tree. The name must be a project from a previous call to
`ProjectConfig#SetScript()` function or `:ProjectConfig`/`:ProjectConfigAdd` command. When the
project tree is opened, the `project` script will be triggered (`:source`d).


### ` ProjectConfig::Completion(arg1, arg2, arg3)`
### `:ProjectConfigList`

Return/display a list with names of all projects from previous calls to `ProjectConfig#SetScript()`
function, or previous uses of `:ProjectConfig`/`:ProjectConfigAdd` command.
