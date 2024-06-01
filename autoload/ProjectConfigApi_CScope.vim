vim9script

import './ProjectConfigApi_ProjectModel.vim' as ProjectModel
import './ProjectConfigApi_Generator.vim' as ProjectConfig

type Module = ProjectConfig.Module
type Project = ProjectConfig.Project
type TreeWalker = ProjectModel.DependencyWalker
type CallbackFunction = ProjectModel.CallbackFunction

export var BuildOptions: list<string> = [ '-q' ]   # '-b' is always used (hard-coded)
export var LookupOptions: list<string>  = [ '-U' ]  # check file stamps (update cscope database)

g:ProjectConfig_CScopeBuildOptions = BuildOptions
g:ProjectConfig_CScopeLookupOptions = LookupOptions

var Projects = ProjectConfig.Projects
var Join_Path = ProjectConfig.JoinPath
var Shell_Escape = ProjectConfig.ShellEscape
var InPlace_Append_Unique = ProjectConfig.InPlaceAppendUnique
var ModuleProperties = ProjectModel.ModuleProperties

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

def CScope_Source_Filter(glob_list: list<string>, regexp_list: list<string>): list<string>
    var filters: list<string> = empty(glob_list) ? DefaultGlob[ : ] : glob_list[ : ]

    filters->map((_, val) => val->glob2regpat())

    return filters->extend(regexp_list)
enddef

def Apply_Filters(line_list: list<string>, filters: list<string>): void
    var all_filters: string = filters->join('\|')

    line_list->filter((_, name) => name =~ all_filters)
enddef

def Update_NameFile(cscope_db: string, source_list: list<string>, recurse: bool, glob_list: list<string>, regexp_list: list<string>): string
    var basename = cscope_db
    mkdir(fnamemodify(cscope_db, ':h'), 'p')

    if basename =~ '\.out$'
	basename = basename[ : -5]
    endif

    var namefile = basename .. '.files'
    var old_file_list = filereadable(namefile) ? namefile->readfile() : [ ]
    var new_file_list = ProjectConfig.ExpandModuleSources(recurse, source_list, CScope_Source_Filter(glob_list, regexp_list))

    if empty(new_file_list)
	echomsg 'No C or C++ source files for cscope to run'
	return ''
    endif

    if new_file_list != old_file_list
	new_file_list->writefile(namefile)
    endif

    return namefile
enddef

def Build_CScope_Database(project: Project, connections: string, exported: bool, level: number, is_duplicate: bool, module: Module, is_cyclic: bool): void
    if exported == module.exported && !is_duplicate
	var prop_list: list<list<string>> =
	    [
		[ 'recurse' ],
		[ 'src' ],
		[ 'inc' ],
		[ 'cscope', 'db' ],
		[ 'cscope', 'build_args' ],
		[ 'cscope', 'lookup_args' ],
		[ 'cscope', 'glob' ],
		[ 'cscope', 'regexp' ]
	    ]
	var recurse: list<bool>
	var src_list: list<string>
	var inc_list: list<string>
	var db_list: list<string>
	var build_args: list<string>
	var lookup_args: list<string>
	var glob_list: list<string>
	var regexp_list: list<string>

	[ recurse, src_list, inc_list, db_list, build_args, lookup_args, glob_list, regexp_list ] = ModuleProperties(prop_list, project, module)

	db_list->map((_, file) => fnamemodify(file->resolve(), ':p:~:.:gs?\\?/?'))->uniq()
	recurse->uniq()

	if db_list->len() != 1
	    echoerr "Mismatching values given for cscope database file: " db_list
	endif

	if recurse->len() > 1
	    echoerr "Mismatching values given for module recurese flag: " recurse
	else
	    if empty(recurse)
		recurse = [ false ]
	    endif
	endif

	var output_file = db_list[0]

	var namefile: string = Update_NameFile(output_file, src_list, recurse[0], glob_list, regexp_list)

	if empty(namefile)
	    return
	endif

	var cscope_command: list<string> = [ CScope_Path ]->extend(CScope_Options)->extend(BuildOptions)
		    \ + project.config['cscope'].build_args + build_args + inc_list->mapnew((_, dir) => '-I' .. dir)
		    \ + [ '-b', '-i', Shell_Escape(namefile), '-f', Shell_Escape(output_file) ]

	if stridx(connections, output_file) >= 0
	    # Windows cannot recreate the cscope database file while it is
	    # used. This will also re-order cscope files if need to the
	    # expected sequence
	    execute 'cscope kill ' .. fnameescape(output_file)
	endif

	execute '! echo ' .. cscope_command->join(' ')

	if v:shell_error
	    echoerr 'Error generating cscope database ' .. output_file .. ' for module ' .. module.name
			\ .. ': shell command exited with code ' .. v:shell_error
	else
	    lookup_args->extend(LookupOptions)->extend(project.config['cscope'].lookup_args)

	    if empty(lookup_args)
		execute 'echo cscope add ' .. fnameescape(output_file)
	    else
		execute 'echo cscope add ' .. fnameescape(output_file) .. ' . ' .. lookup_args->join(' ')
	    endif
	endif
    endif
enddef

export def BuildCScopeDatabase(exported_list: list<bool>, project_name: string, module_name: string, ...module_names: list<string>): void
    if ProjectConfig.Projects->has_key(project_name)
	var project: Project = g:ProjectConfig_Modules[project_name]
	var connections: string = 'cscope show'->execute()
	var Callback_Function: CallbackFunction = funcref(Build_CScope_Database, [ project, connections ])
	var treeWalker: TreeWalker = TreeWalker.new(project, Callback_Function, TreeWalker.FullDescend)

	var modules: list<Module> =
	    [ module_name ]->extend(module_names)
		->filter((_, name) => project.modules->has_key(name))
		->mapnew((_, name) => project[name])

	if !empty(modules)
	    for exported in exported_list
		treeWalker.Traverse_ByLevel_TopDown(exported, modules[1], modules[1 : ])
	    endfor
	endif
    endif
enddef

g:ProjectConfig_BuildCScopeDatabase = BuildCScopeDatabase

export def EnableReScopeCommand(module_name: string, ...module_names: list<string>): void
    var arglist: string = "'" .. [ g:ProjectConfig_Project, module_name ]->extend(module_names)->join("', '") .. "'"
    execute "command ReScope" .. g:ProjectConfig_Project .. " call g:ProjectConfig_BuildCScopeDatabase([ false ], " .. arglist .. ")"
    execute "command ReScope" .. g:ProjectConfig_Project .. "All call g:ProjectConfig_BuildCScopeDatabase([ false, true ], " .. arglist .. ")"
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

class CScopeGenerator implements ProjectConfig.Generator
    var name: string = 'cscope'

    def AddProject(project: Project, project_name: string): void
	UpdateProjectConfig(project)
    enddef

    def SetProjectConfig(project: Project, name: string): void
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
	endfor
    enddef

    def LocalConfigInit(module_name: string, ...module_names: list<string>): void
    enddef

    def UpdateGlobalConfig(module: Module): void
    enddef

    def LocalConfigInitModule(module: Module): void
    enddef

    def UpdateModuleLocalConfig(module: Module): void
    enddef

    def LocalConfigCompleteModule(module: Module): void
    enddef
endclass

ProjectConfig.Generators->add(CScopeGenerator.new())

defcompile
