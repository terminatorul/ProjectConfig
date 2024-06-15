vim9script

import './ProjectConfigApi_ProjectModel.vim' as ProjectModel
import './ProjectConfigApi_Generator.vim' as ProjectConfig

type Property = ProjectConfig.Property
type Module = ProjectConfig.Module
type Project = ProjectConfig.Project
type TreeWalker = ProjectModel.DependencyWalker
type CallbackFunction = ProjectModel.CallbackFunction

export var BuildOptions: list<string> =
    g:->has_key('ProjectConfig_CScopeBuildOptions') ?
	g:ProjectConfig_CScopeBuildOptions :
	[ '-b', '-q' ]   # '-b' is always expected ("build database")

export var LookupOptions: list<string> =
    g:->has_key('ProjectConfig_CScopeLookupOptions') ?
	g:ProjectConfig_CScopeLookupOptions :
	[ '-U' ]  # check file stamps (update cscope database)

function g:BuildCScopeCommand(command_args, namefile, db_file)
    return command_args->extend([ '-i', namefile, '-f', db_file ])
endfuncti

# add namefile and output db file to cscope command line
export var BuildCommand: func(list<string>, string, string): list<string> =
    g:->has_key('ProjectConfig_CScopeBuildCommand') ?
 	(command_args: list<string>, namefile: string, db_file: string): list<string> => g:BuildCScopeCommand(command_args, namefile, db_file) :
	(command_args: list<string>, namefile: string, db_file: string): list<string> => command_args->extend([ '-i', namefile, '-f', db_file ])


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

# Populates CScope_Path and Options
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

# Populates CScope_Path and CScope_Options on first use
Expand_CScope_Command = Expand_CScope_Command_Line

class CScopeProperties
    var recurse: bool
    var src_list: list<string>
    var inc_list: list<string>
    var enabled: bool
    var db: string
    var build_args: list<string>
    var lookup_args: list<string>
    var cscope_args: list<string>
    var glob_list: list<string>
    var regexp_list: list<string>

    def NameFile(): string
	var basename: string = this.db

	if basename =~ '\.out$'
	    basename = basename[ : -5]
	endif

	return basename .. '.files'
    enddef

    def new(project: Project, module: Module): void
	var prop_list: list<list<string>> =
	    [
		[ 'recurse' ],
		[ 'src' ],
		[ 'inc' ],
		[ 'cscope', 'enabled' ],
		[ 'cscope', 'db' ],
		[ 'cscope', 'build_args' ],
		[ 'cscope', 'lookup_args' ],
		[ 'cscope', 'args' ],
		[ 'cscope', 'glob' ],
		[ 'cscope', 'regexp' ]
	    ]

	var recurse:	  list<bool>
	var db_list: 	  list<string>
	var enabled_list: list<bool>

	  [
	\ 	 recurse,
	\     this.src_list,
	\     this.inc_list,
	\ 	 db_list,
	\ 	 enabled_list,
	\     this.build_args,
	\     this.lookup_args,
	\     this.cscope_args,
	\     this.glob_list,
	\     this.regexp_list
	\ ]
	\     = ModuleProperties(prop_list, project, module)

	if empty(enabled_list) && (!!db_list || !!this.glob_list || !!this.regexp_list)
	    enabled_list->add(true)
	endif

	enabled_list->uniq()
	recurse->uniq()
	db_list->map((_, file) => file->resolve()->fnamemodify(':p:~:.:gs?\\?/?'))->uniq()

	if ProjectConfig.DirectorySeparator == '\'
	    db_list->map((_, file) => file->tr('/', '\'))
	endif

	if enabled_list->len() > 1
	    echoerr "Mismatching values given for cscope enable flag for project module " module.name ": " enabled_list
	endif

	if recurse->len() > 1
	    echoerr "Mismatching values given for module recurse flag for project module " module.name ": " recurse
	endif

	if db_list->len() > 1
	    echoerr "Mismatching values given for cscope database file for project module " module.name ": " db_list
	endif

	this.enabled = enabled_list->get(0, false)	# could check if module has C, C++, flex or bison sources
	this.recurse = recurse->get(0, false)
	this.db = db_list->get(0, '')

	if empty(this.db) && this.enabled
	    this.db = Join_Path(CScope_Directory, 'cscope.' .. module.name .. '.out')
	endif
    enddef
endclass

def Vim_Disconnect_CScope_Database(connections: string, db_file: string)
    if stridx(connections, db_file) >= 0
	# Windows cannot recreate the cscope database file while it is
	# in use. This will also re-order cscope files if needed, to the
	# expected sequence
	execute 'cscope kill ' .. fnameescape(db_file)
    endif
enddef

def Vim_Connect_CScope_Database(project: Project, module: Module): void
    var properties: CScopeProperties = CScopeProperties.new(project, module)
    var output_file: string = properties.db

    if properties.enabled
	var lookup_args = LookupOptions->copy()->extend(project.config['cscope']->get('args', [ ]))->extend(project.config['cscope'].lookup_args)

	lookup_args->extend(properties.lookup_args)

	if empty(lookup_args)
	    execute 'echo cscope add ' .. fnameescape(output_file)
	else
	    execute 'echo cscope add ' .. fnameescape(output_file) .. ' . ' .. lookup_args->join(' ')
	endif
    endif
enddef

def VimConnectCScopeDatabase(project: Project, module: Module, ...modules: list<Module>): void
    def Connect_CScope_Db_Func(external: bool, level: number, is_duplicate: bool, current_module: Module, is_cyclic: bool): void
	if !!level && external == current_module.external && !is_duplicate
	    Vim_Connect_CScope_Database(project, current_module)
	endif
    enddef

    var treeWalker: TreeWalker = TreeWalker.new(project, Connect_CScope_Db_Func, TreeWalker.FullDescend)

    for external in [ false, true ]
	treeWalker.Traverse_ByLevel_TopDown(external, module, modules)
    endfor
enddef

def CScope_Source_Filters(glob_list: list<string>, regexp_list: list<string>): list<string>
    var filters: list<string> = !!glob_list ? glob_list[ : ] : DefaultGlob[ : ]

    filters->map((_, val) => val->glob2regpat())

    return filters->extend(regexp_list)
enddef

def Update_NameFile(properties: CScopeProperties): string
    var namefile: string = properties.NameFile()
    namefile->fnamemodify(':h')->mkdir('p')

    var has_namefile: bool = filereadable(namefile)
    var old_file_list = has_namefile ? namefile->readfile() : [ ]
    var new_file_list = ProjectModel.ExpandModuleSources(properties.recurse, properties.src_list, CScope_Source_Filters(properties.glob_list, properties.regexp_list))

    if empty(new_file_list)
	echomsg 'No C or C++ source files for cscope to run'

	if has_namefile
	    namefile->delete()
	endif

	return ''
    endif

    if new_file_list != old_file_list
	new_file_list->writefile(namefile)
    endif

    return namefile
enddef

def Build_CScope_Database(project: Project, connections: string, module: Module): void
    var properties: CScopeProperties = CScopeProperties.new(project, module)

    if properties.enabled
	var output_file: string = properties.db
	var namefile: string = Update_NameFile(properties)

	if empty(namefile)
	    return
	endif

	var cscope_command: list<string> = [ CScope_Path ]->extend(CScope_Options)->extend(BuildOptions)
		    \ ->extend(project.config['cscope']->get('args', [ ]))->extend(project.config['cscope'].build_args)
		    \ ->extend(properties.cscope_args)->extend(properties.build_args)
		    \ ->extend(properties.inc_list->mapnew((_, dir) => [ '-I',  dir ])->flattennew())

	cscope_command = BuildCommand(cscope_command, Shell_Escape(namefile), Shell_Escape(output_file))

	Vim_Disconnect_CScope_Database(connections, output_file)

	execute '! echo ' .. cscope_command->join(' ')

	if v:shell_error
	    echoerr 'Error generating cscope database ' .. output_file .. ' for module ' .. module.name
			\ .. ': shell command exited with code ' .. v:shell_error
	endif
    endif
enddef

export def BuildCScopeDatabase(external_list: list<bool>, project_name: string, module_name: string, ...module_names: list<string>): void
    if ProjectConfig.Projects->has_key(project_name)
	var project: Project = g:ProjectConfig_Projects[project_name]
	var connections: string = 'cscope show'->execute()

	def Build_CScope_Db_Func(external: bool, level: number, is_duplicate: bool, module: Module, is_cyclic: bool): void
	    if !!level && external == module.external && !is_duplicate
		Build_CScope_Database(project, connections, module)
	    endif
	enddef

	var treeWalker: TreeWalker = TreeWalker.new(project, Build_CScope_Db_Func, TreeWalker.FullDescend)
	var modules: list<Module> = ProjectModel.LookupProjectModules->call([ project, module_name ]->extend(module_names))

	if !!modules
	    for external in external_list
		treeWalker.Traverse_ByLevel_ButtomUp(external, modules[0], modules[1 : ])
	    endfor

	    VimConnectCScopeDatabase->call([ project ]->extend(modules))
	endif
    endif
enddef

g:ProjectConfig_BuildCScopeDatabase = BuildCScopeDatabase

export def ClearCScopeDatabase(external_list: list<bool>, project_name: string, module_name: string, ...module_names: list<string>): void
    if ProjectConfig.Projects->has_key(project_name)
	var project: Project = g:ProjectConfig_Projects[project_name]

	def Clear_CScope_Db_Func(external: bool, level: number, is_duplicate: bool, module: Module, is_cyclic: bool): void
	    if !!level && external == module.external && !is_duplicate
		var properties: CScopeProperties = CScopeProperties.new(project, module)

		if properties.enabled
		    'cscope kill ' .. properties.db->fnameescape()

		    if properties.db =~ '\.out$'
			for db_file in (properties.db[ : -4] .. '*')->glob(true, true, true)
			    db_file->delete()
			    echo 'Removed ' db_file
			endfor
		    else
			for file_path in [ properties.db, properties.NameFile() ]
			    file_path->delete()
			    echo 'Removed ' file_path
			endfor
		    endif
		endif
	    endif
	enddef

	var modules: list<Module> = ProjectModel.LookupProjectModules->call([ project, module_name ]->extend(module_names))

	if !!modules
	    var treeWalker: TreeWalker = TreeWalker.new(project, Clear_CScope_Db_Func, TreeWalker.FullDescend)

	    for external in external_list
		treeWalker.Traverse_ByLevel_ButtomUp(external, modules[0], modules[1 : ])
	    endfor
	endif
    endif

    var db_list: list<string> = (CScope_Directory .. '/cscope.*')->glob(true, true, true)

    for db_file in db_list
	if db_file =~ '\v.*/cscope\..*\.out$'
	    ('cscope kill ' .. db_file->fnameescape())->execute()
	endif
    endfor

    for db_file in db_list
	db_file->delete()
	echo 'Removed ' db_file
    endfor
enddef

g:ProjectConfig_ClearCScopeDatabase = ClearCScopeDatabase

export def EnableReScopeCommand(module_name: any, ...module_names: list<any>): void
    var arglist: string = "'"
	.. (<list<string>>[ g:ProjectConfig_Project ])
		->extend(ProjectModel.ListModuleNames->call([ module_name ]->extend(module_names)))
		->join("', '")
	.. "'"

    execute "command ReScope" .. g:ProjectConfig_Project .. " call g:ProjectConfig_BuildCScopeDatabase([ false ], " .. arglist .. ")"
    execute "command ReScope" .. g:ProjectConfig_Project .. "All call g:ProjectConfig_BuildCScopeDatabase([ false, true ], " .. arglist .. ")"
    execute "command ReScopeClear" .. g:ProjectConfig_Project .. " call g:ProjectConfig_ClearCScopeDatabase([false, true], " .. arglist .. ")"
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
    enddef

    def LocalConfigInit(module: Module, ...modules: list<Module>): void
	var project: Project = ProjectConfig.AddCurrentProject()
	VimConnectCScopeDatabase->call([ project, module ]->extend(modules))
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

# defcompile
