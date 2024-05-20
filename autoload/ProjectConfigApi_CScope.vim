vim9script

import './ProjectConfigApi.vim' as ProjectConfig

type Module = ProjectConfig.Module
type Project = ProjectConfig.Project

export var BuildOptions: list<string> = [ '-q' ]   # '-b' is always used (hard-coded)
export var LookupOptions: list<string>  = [ '-U' ]  # check file stamps (update cscope database)

g:ProjectConfig_CScopeBuildOptions = BuildOptions
g:ProjectConfig_CScopeLookupOptions = LookupOptions

var Join_Path = ProjectConfig.JoinPath
var Shell_Escape = ProjectConfig.ShellEscape
var InPlace_Append_Unique = ProjectConfig.InPlaceAppendUnique

# List of default source file extensions, from cscope source code at:
#   https://sourceforge.net/p/cscope/cscope/ci/master/tree/src/dir.c#l519
#
#   *.bp   breakpoint listing
#   *.ch   Ingres
#   *.sd   SDL
#   *.tcc  C++ template source file
#
export var DefaultGlob: list<string> =
	\ [
	\    '.[chlyCGHL]',
	\    '.bp',
	\    '.ch',
	\    '.sd',
	\    '.cc',
	\    '.hh',
	\    '.tcc',
	\    '.[ch]pp',
	\    '.[ch]xx'
	\ ]
	\  ->mapnew((_, val) => '**/*' .. val)

if g:->has_key('ProjectConfig_CScopeDefaultGlob')
    DefaultGlob = g:ProjectConfig_CScopeDefaultGlob
endif

export var CScope_Directory: string = '.projectConfig'

if g:->has_key('ProjectConfig_CScope_Directory')
    CScope_Directory = g:ProjectConfig_CScope_Directory
endif

export var CScope_Path: string = exepath('cscope')
export var CScope_Options: list<string>

var Expand_CScope_Command: func(): void

def Expand_CScope_Command_Line()
    if g:->has_key('ProjectConfig_CScope_Executable')
	if type(g:ProjectConfig_CScope_Executable) == v:t_list
	    CScope_Path = exepath(g:ProjectConfig_CScope_Executable[0])
	    CScope_Options = g:ProjectConfig_CScope_Executable[1 : ]
	else
	    CScope_Path = exepath(g:ProjectConfig_CScope_Executable)
	    CScope_Options = [ ]
	endif
    else
	CScope_Path = exepath(&cscopeprg)
	CScope_Options = [ ]
    endif

    if g:->has_key('ProjectConfig_CScope_Options')
	CScope_Options->extend(g:ProjectConfig_CScope_Options)
    endif

    CScope_Path = Shell_Escape(CScope_Path)
    CScope_Options->map((_, optarg) => Shell_Escape(optarg))

    Expand_CScope_Command = (): void => {
    }
enddef

# Populate CScope_Path and Options
Expand_CScope_Command = Expand_CScope_Command_Line

def CScope_Source_Filter(module: Module): list<string>
    var filters: list<string>
    var globlist: list<string>

    for scope_name in [ 'private', 'public' ]
	if module[scope_name]['cscope']->has_key('glob')
	    globlist->extend(module[scope_name]['cscope']['glob'])
	endif
    endfor

    if empty(globlist)
	globlist = g:ProjectConfig_CScopeDefaultGlob[ : ]
    endif

    filters = globlist->mapnew((_, val) => val->glob2regpat())

    for scope_name in [ 'private', 'public' ]
	if module[scope_name]['cscope']->has_key('regexp')
	    filters->extend(module[scope_name]['cscope'].regexp)
	endif
    endfor

    return filters
enddef

def Apply_Filters(line_list: list<string>, filters: list<string>): void
    var all_filters: string = filters->join('\|')

    line_list->filter((_, name) => name =~ all_filters)
enddef

def Update_NameFile(module: Module): string
    var basename =  module['private']['cscope'].db
    var cscope_dir = fnamemodify(basename, ':h')

    mkdir(cscope_dir, 'p')

    if match(basename, '\.out$') > 0
	basename = basename[ : -5]
    endif

    var namefile = basename .. '.files'
    var old_file_list = filereadable(namefile) ? namefile->readfile() : [ ]
    var new_file_list = ProjectConfig.ExpandModuleSources(module, CScope_Source_Filter(module))

    if empty(new_file_list)
	echomsg 'No C or C++ source files for cscope to run'
	return ''
    endif

    if new_file_list != old_file_list
	new_file_list->writefile(namefile)
    endif

    return namefile
enddef

def Build_CScope_Database(project: Project, module: Module, connections: string): void
    var namefile: string = Update_NameFile(module)

    if empty(namefile)
	return
    endif

    var output_file = module['private']['cscope'].db

    var cscope_command = [ CScope_Path ] ->extend(CScope_Options)
		\ + project.config['cscope'].build_args + module['cscope']['private'].build_args + module['cscope']['public'].build_args
		\ + [ '-b', '-i', Shell_Escape(namefile), '-f', Shell_Escape(output_file) ]

    var connection_found = stridx(connections, output_file) >= 0 ? true : false

    if connection_found && ProjectConfig.HasWindows
	# On Windows can not rebuild the cscope database while in use in Vim,
	# presumably cygwin and msys/mingw as well
	execute 'cscope kill ' .. fnameescape(output_file)
    endif

    execute '! echo ' .. cscope_command->join(' ')

    if v:shell_error
	echoerr 'Error generating cscope database ' .. output_file .. ' for module ' .. module.name
		    \ .. ': shell command exited with code ' .. v:shell_error
    else
	if ProjectConfig.HasWindows || !connection_found
	    # this could change order of connections on Windows
	    execute 'cscope add ' .. fnameescape(output_file)
	endif
    endif
enddef

def Build_CScope_Database_By_Level(
	current_depth: number,
	target_depth: number,
	project: Project,
	module: Module,
	external: bool,
	connections: string,
	module_list: list<string>): bool

    if current_depth == target_depth
	if external == module.external
	    if !empty(module['private'].cscope.db) && module_list->index(module.name) < 0
		module_list->add(module.name)
		Build_CScope_Database(project, module, connections)
	    endif
	endif

	return true
    endif

    var target_depth_reached = false

    for submodule_name in module['private'].deps + module['public'].deps
	if project.modules->has_key(submodule_name)
	    var depth_reached = Build_CScope_Database_By_Level(
			current_depth + 1,
			target_depth,
			project,
			project.modules[submodule_name],
			external,
			connections,
			module_list)

	    if depth_reached && !target_depth_reached
		target_depth_reached = true
	    endif
	endif
    endfor

    return target_depth_reached
enddef

def Module_Tree_Level_Traversal(
	connections: string,
	module_list: list<string>,
	external: bool,
	project_name: string,
	module_name: string,
	module_names: list<string>): void

    if g:ProjectConfig_Modules->has_key(project_name)
	Expand_CScope_Command()

	var project: Project = g:ProjectConfig_Modules[project_name]
	var depth_level: number = 0
	var depth_level_reached: bool = true

	while depth_level_reached
	    depth_level_reached = false
	    ++depth_level

	    for name in [ module_name ]->extend(module_names)
		if project.modules->has_key(name)
		    var depth_reached: bool = Build_CScope_Database_By_Level(
				1,
				depth_level,
				project,
				project.modules[name],
				external,
				connections,
				module_list)
		    if depth_reached && !depth_level_reached
			depth_level_reached = true
		    endif
		endif
	    endfor
	endwhile
    endif
enddef

export def BuildCScopeDatabase(project_name: string, module_name: string, ...module_names: list<string>): void
    var connections: string = 'cscope show'->execute()
    var module_list: list<string> = [ ]

    Module_Tree_Level_Traversal(connections, module_list, false, project_name, module_name, module_names)

    if !ProjectConfig.HasWindows
	cscope reset
    endif
enddef

g:ProjectConfig_BuildCScopeDatabase = BuildCScopeDatabase

export def BuildAllCScopeDatabase(project_name: string, module_name: string, ...module_names: list<string>): void
    var connections: string = 'cscope show'->execute()
    var module_list: list<string> = [ ]

    if ProjectConfig.Projects->has_key(project_name)
	Module_Tree_Level_Traversal(connections, module_list, false, project_name, module_name, module_names)
	Module_Tree_Level_Traversal(connections, module_list, true,  project_name, module_name, module_names)

	if !ProjectConfig.HasWindows
	    cscope reset
	endif
    endif
enddef

g:ProjectConfig_BuildAllCScopeDatabase = BuildAllCScopeDatabase

export def EnableReScopeCommand(module_name: string, ...module_names: list<string>): void
    var arglist = "'" .. [ g:ProjectConfig_Project, module_name ]->extend(module_names)->join("', '") .. "'"
    execute "command ReTag" .. g:ProjectConfig_Project .. " call g:ProjectConfig_BuildCScopeDatabase(" .. arglist .. ")"
    execute "command ReTag" .. g:ProjectConfig_Project .. "All call g:ProjectConfig_BuildAllCScopeDatabase(" .. arglist .. ")"
enddef

def UpdateProjectConfig(project: Project)
    if !project.config->has_key('cscope')
	project.config['cscope'] = { }
    endif

    if type(project.config['cscope']) != v:t_dict
	project.config['cscope'] = { }
    endif

    if !project.config['cscope']->has_key('build_args')
	project.config['cscope']['build_args'] = [ ]
    endif

    if !project.config['cscope']->has_key('lookup_args')
	project.config['cscope']['lookup_args'] = [ ]
    endif

    if type(project.config['cscope'].build_args) != v:t_list
	project.config['cscope'].build_args = [ project.config['cscope'].build_args ]
    endif

    if type(project.config['cscope'].lookup_args) != v:t_list
	project.config['cscope'].lookup_args = [ project.config['cscope'].lookup_args ]
    endif
enddef

class CScopeGenerator # implements ProjectConfig.Generator
    var name: string = 'cscope'

    def AddProject(project: Project, project_name: string): void
	UpdateProjectConfig(project)
    enddef

    def SetConfigEntry(project: Project, name: string): void
	if name == 'cscope'
	    UpdateProjectConfig(project)

	    project.config['cscope'].build_args->map((_, arg) => Shell_Escape(arg))
	    project.config['cscope'].lookup_args->map((_, arg) => Shell_Escape(arg))
	endif
    enddef

    def AddModule(project: Project, module: Module, ...modules: list<Module>): void
	for this_module in [ module ]->extend(modules)
	    if this_module['private']->has_key('cscope')
		if type(this_module['private']['cscope']) == v:t_bool
		    if this_module['private']['cscope']
			this_module['private']['cscope'] = { db: CScope_Directory }
		    else
			this_module['private']['cscope'] = { db: '' }

			continue
		    endif		   
		endif
	    else
		this_module['private']['cscope'] = { db: '' }

		continue
	    endif

	    if !this_module['private']['cscope']->has_key('db')
		this_module['private']['cscope'].db = CScope_Directory
	    endif

	    for scope_name in [ 'private', 'public' ]
		var scope = this_module[scope_name]

		if !scope->has_key('cscope')
		    scope['cscope'] = { }
		endif

		for key_name in [ 'build_args', 'lookup_args', 'glob', 'regexp' ]
		    if !scope['cscope']->has_key(key_name)
			scope['cscope'][key_name] = [ ]
		    endif

		    if type(scope['cscope'][key_name]) != v:t_list
			scope['cscope'][key_name] = [ scope['cscope'][key_name] ]
		    endif
		endfor
	    endfor
	endfor
    enddef

    # def LocalConfigInit(): void
    # def UpdateGlobalConfig(module: Module): void
    # def LocalConfigInitModule(module: Module): void
    # def UpdateModuleLocalConfig(module: Module): void
    # def LocalConfigCompleteModule(module: Module): void
endclass

# eval g:ProjectConfig_Generators->add(g:ProjectConfig_CScope)

defcompile
