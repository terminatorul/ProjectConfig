# ProjectConfig plugin for Vim

Allows you to load a Vim script when entering a project tree, and when editing files from
that tree.

It is similar to other "project settings" addons, but it finds the project base directory
using settings from local  `.vimrc` file, and not by scanning every path component for
"marker" files (`.project`, `.root`, `.git`), up to the file system root, every time you
`:edit` something.

## Installation

Installation should be easy. The plugin should be found at: [terminatorul/ProjectConfig](https://github.org/terminatorul/ProjectConfig)

Depending on how you use Vim, you can choose one of the options below:

### Use Vimball release

Download the vimball release from Github (search for project
terminatorul/ProjectConfig, then click on Releases). Open the `.vmb` file
with Vim and run `:source %`

### Use a Vim plugin manager
Using a plugin manager for Vim like Vundle or Pathogen is recommended. For
Vundle you should add some lines similar to the following to your local `.vimrc`
file:
```
    call vundle#begin()

	#
	# .. other plugins you use with Vundle
	#

	Plugin 'terminatorul/ProjectConfig
    call vundle#end()
```
then run `:PluginInstall` command in Vim.

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

The `~/.vim/` directory is used for Linux, `~/vimfiles` for Windows. The file script for
Linux has a default suffix of `.files.vim`, and `_files.vim` for Windows.

Use this function in your local  `.vimrc` or `_vimrc`, once for every project tree that you want
to have setup scripts.

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

### Configuration
```
g:ProjectConfig_NERDTreeIntegration
```

By default ProjectConfig knows when you use NERDTree plugin to open a project directory, and will
trigger the project script (if needed) when that happens. Set this variable to `v:false` to
prevent integration with NERDTree plugin.

```
g:ProjectConfig_PluginLoaded
```
Set to `v:true` after the plugin loads. You can set this to `v:true` in your local
.`vimrc` file to prevent the plugin from loading (that is, to disable
ProjectConfig plugin, but still keep it installed). As expected, autoload
functions like `ProjectConfig#SetScript()` above will still be available. What
will be disabled are the Vim commands `:ProjectConfig`, `:ProjectConfigAdd`,
`:ProjectConfigEnter`, `:ProjectConfigOpen`, `:ProjectConfigList`.

