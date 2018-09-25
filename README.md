# ProjectConfig plugin for Vim

Allows you to load a Vim script when entering a project tree or every time you edit a file from
that tree.

It is similar to other "project settings" addons, but infers the project directory from local
`.vimrc` settings, not by scanning every path component up to the file system root, every time you
edit a new file.

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
* a `project` script, that will be run the first time you `:cd ` inside the project
  directory in Vim, or the first time you `:edit` a file from the project tree
* a `file` script, that will be run every single time you open/edit a file from the
  project tree

By default the `project` script has the same name as the project, with `.vim` extension added,
and is searched in the `~/.vim/project/` directory (`~/vimfiles/project/` for Windows systems).
The `file` script has the name of the project with an appended suffix of `.files.vim`
(`_files.vim` for Windows).

```
call ProjectConfig#SetScript('Name', 'Path', 'ProjectScriptPath', 'FileScriptPath', KeepPWD)
call ProjectConfig#SetScript('Name', 'Path')
call ProjectConfig#SetScript('Path')
```

Call the function to associate a project tree with a project script and a file script. The only
required argument is the `Path`, other can be omitted. If not specified, the default values are:
* the project `Name` is the last path component from `Path`
* the project script is `~/.vim/project/<Name>.vim`
* the file script is `~/.vim/project/<Name>.file.vim` if file exists, or no file script otherwise.
* the flag to keep current directory is false, that is the project script is always run in the
  project directory, after which the current directory is restored. Beware the file script is
  always run in the user current directory, which can well be outside the project!

The `~/.vim/` directory is used for Linux, `~/vimfiles` for Windows. Also the file script for
Windows has a different suffix `_files.vim` instead of `.files.vim`.

Use this function in the user `.vimrc` or `_vimrc`, once for every project tree that you want to
have setup scripts.

The `Path` and `Name` values given here will be passed to the associated scripts when invoked, in
the global variables `g:ProjectConfig_Directory` and `g:ProjectConfig_Project`


```
:ProjectConfig Name Path ProjectScript FileScript
:ProjectconfigAdd 'Name', 'Path', 'ProjectScript', 'FileScript'
```

Same as the `ProjectConfig#SetScript` function above. But since these are Vim commands, they are
only available after the plugin has been loaded by Vim, that is they are not available yet in
the `.vimrc` file. Arguments other the `Path` are optional, like they are for the function.

```
:call ProjectConfig#FindLoad('Name')
:ProjectConfigEnter Name
:ProjectConfigOpen 'Name'
```

Open the named project tree. Uses `:NERDTreeCWD` to open the directory if available. The name must be
a project from a previous call to `ProjectConfig#SetScript()` function or
`:ProjectConfig`/`:ProjectConfigAdd` command. When the project tree is opened, the `project`
script will be triggered (`:source`d), if the project has not been open before in the same Vim
session.

```
:call ProjectConfig::Completion(v:null, v:null, v:null)
:ProjectConfigList
```

Return/display a list with names of all projects from previous calls to `ProjectConfig#SetScript()`
function, or previous uses of `:ProjectConfig` or `:ProjectConfigAdd` command.

```
g:ProjectConfig_NERDTreeIntegration
```

By default ProjectConfig knows when you use NERDTree plugin to open a project directory, and will
trigger the project script (if needed) when that happens. Set this variable to `v:false` to
prevent integration with NERDTree plugin.
