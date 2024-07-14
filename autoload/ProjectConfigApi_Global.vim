vim9script

import './ProjectConfigApi_ProjectModel.vim' as ProjectModel
import './ProjectConfigApi_Generator.vim' as ProjectConfig

type Property = ProjectConfig.Property
type Module = ProjectConfig.Module
type Project = ProjectConfig.Project
type TreeWalker = ProjectModel.DependencyWalker
type CallbackFunction = ProjectModel.CallbackFunction

var JoinPath = ProjectConfig.JoinPath

export var WarnOnEnvironmentOverride = g:->get('ProjectConfig_Global_WarnOnEnvironmentOverride', true)
export var GtagsCommand: list<string> = [ g:->get('ProjectConfig_Global_GtagsCommand', exepath('gtags')) ]->flattennew()
export var GlobalCommand: list<string> = [ g:->get('ProjectConfig_Global_Command', exepath('global')) ]->flattennew()

if (GtagsCommand->empty() || GtagsCommand[0]->empty()) && ProjectConfig.HasWindows
    GtagsCommand = 'C:\msys64\mingw64\bin\gtags.exe'->glob(true, true) ??
	    'C:\msys64\clang64\bin\gtags.exe'->glob(true, true) ??
		'C:\msys64\bin\gtags.exe'->glob(true, true)
endif

if (GlobalCommand->empty() || GlobalCommand[0]->empty()) && ProjectConfig.HasWindows
    GtagsCommand = 'C:\msys64\mingw64\bin\global.exe'->glob(true, true) ??
	    'C:\msys64\clang64\bin\global.exe'->glob(true, true) ??
		'C:\msys64\bin\global.exe'->glob(true, true)
endif

export var GtagsDefaultConfig: string = g:->get('ProjectConfig_Global_GtagsDefaultConfig', JoinPath(GtagsCommand[0]->fnamemodify(':p:h'), 'share', 'gtags.conf'))

# Extensions from default config file gtags.conf, from the label 'builtin-parser'. Only used for the 'default' label.
export var DefaultGlob: list<string> = g:->get('ProjectConfig_Global_DefaultGlob',
    [ '.c', '.h', '.y', '.s', '.S', '.java', '.c++', '.cc', '.hh', '.cpp', '.cxx', '.hxx', '.hpp', '.C', '.H', '.php', '.php3', '.phtml' ]
	->map((_, ext) => '**/*' .. ext))

