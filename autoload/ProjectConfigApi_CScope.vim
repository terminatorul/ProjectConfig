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

# Populates CScope_Path and Options on first use
Expand_CScope_Command = Expand_CScope_Command_Line

class CScopeProperties
    var recurse: bool
    var src_list: list<string>
    var inc_list: list<string>
    var db: string
    var build_args: list<string>
    var lookup_args: list<string>
    var cscope_args: list<string>
    var glob_list: list<string>
    var regexp_list: list<string>

    def new(module: Module): void
	var prop_list: list<list<string>> =
	    [
		[ 'recurse' ],
		[ 'src' ],
		[ 'inc' ],
		[ 'cscope', 'db' ],
		[ 'cscope', 'build_args' ],
		[ 'cscope', 'lookup_args' ],
		[ 'cscope', 'args' ],
		[ 'cscope', 'glob' ],
		[ 'cscope', 'regexp' ]
	    ]

	var recurse: list<bool>
	var db_list: list<string>

	[
		 recurse,
	    this.src_list,
	    this.inc_list,
		 db_list,
	    this.build_args,
	    this.lookup_args,
	    this.cscope_args,
	    this.glob_list,
	    this.regexp_list
	]
	    = ModuleProperties(prop_list, project, module)

	recurse->uniq()
	db_list->map((_, file) => fnamemodify(file->resolve(), ':p:~:.:gs?\\?/?'))->uniq()

	if recurse->len() > 1
	    echoerr "Mismatching values given for module recurese flag: " recurse
	endif

	if db_list->len() != 1
	    echoerr "Mismatching values given for cscope database file: " db_list
	endif

	this.recurse = recurse->add(false)[0]
	this.db = db_list->add('')[0]

	if !!this.db
	    if ProjectConfig.DirectorySeparator == '\'
		this.db = this.db->tr('/', '\')
	    endif

	    this.db = Join_Path(this.db, 'cscope.' .. module.name .. '.out')
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
    var properties: CScopeProperties = CScopeProperties.new(module)
    var output_file: string = properties.db

    if empty(output_file)
	# no request for cscope generator for this module
	return
    endif

    var lookup_args = LookupOptions->copy()->extend(project.config['cscope']->get('args', [ ]))->extend(project.config['cscope'].lookup_args)

    lookup_args->extend(properties.lookup_args)

    if empty(lookup_args)
	execute 'echo cscope add ' .. fnameescape(output_file)
    else
	execute 'echo cscope add ' .. fnameescape(output_file) .. ' . ' .. lookup_args->join(' ')
    endif
enddef

def VimConnectCScopeDatabase(project: Project, module: Module, ...modules: list<Module>): void
    def Connect_CScope_Db_Func(exported: bool, level: number, is_duplicate: bool, current_module: Module, is_cyclic: bool): void
	if !!level && exported == current_module.exported && !is_duplicate
	    Vim_Connect_CScope_Database(project, current_module)
	endif
    enddef

    var treeWalker: TreeWalker = TreeWalker.new(project, Connect_CScope_Db_Func, TreeWalker.FullDescend)

    for exported in [ false, true ]
	treeWalker.Traverse_ByLevel_TopDown(exported, module, modules)
    endfor
enddef

def CScope_Source_Filters(glob_list: list<string>, regexp_list: list<string>): list<string>
    var filters: list<string> = !!glob_list ? glob_list[ : ] : DefaultGlob[ : ]

    filters->map((_, val) => val->glob2regpat())

    return filters->extend(regexp_list)
enddef

def Update_NameFile(properties: CScopeProperties): string
    var basename = properties.db
    mkdir(fnamemodify(basename, ':h'), 'p')

    if basename =~ '\.out$'
	basename = basename[ : -5]
    endif

    var namefile = basename .. '.files'
    var old_file_list = filereadable(namefile) ? namefile->readfile() : [ ]
    var new_file_list = ProjectModel.ExpandModuleSources(properties.recurse, properties.src_list, CScope_Source_Filters(properties.glob_list, properties.regexp_list))

    if empty(new_file_list)
	echomsg 'No C or C++ source files for cscope to run'
	return ''
    endif

    if new_file_list != old_file_list
	new_file_list->writefile(namefile)
    endif

    return namefile
enddef

def Build_CScope_Database(project: Project, connections: string, module: Module): void
    var properties: CScopeProperties = CScopeProperties.new(module)
    var output_file: string = properties.db

    if empty(output_file)
	# no request for cscope generator for this module
	return
    endif

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
enddef

export def BuildCScopeDatabase(exported_list: list<bool>, project_name: string, module_name: string, ...module_names: list<string>): void
    if ProjectConfig.Projects->has_key(project_name)
	var project: Project = g:ProjectConfig_Projects[project_name]
	var connections: string = 'cscope show'->execute()

	def Build_CScope_Db_Func(exported: bool, level: number, is_duplicate: bool, module: Module, is_cyclic: bool): void
	    if !!level && exported == module.exported && !is_duplicate
		Build_CScope_Database(project, connections, module)
	    endif
	enddef

	var treeWalker: TreeWalker = TreeWalker.new(project, Build_CScope_Db_Func, TreeWalker.FullDescend)
	var modules: list<Module> = ProjectModel.LookupProjectModules->call([ project, module_name ]->extend(module_names))

	if !!modules
	    for exported in exported_list
		treeWalker.Traverse_ByLevel_ButtomUp(exported, modules[1], modules[1 : ])
	    endfor

	    VimConnectCScopeDatabase->call([ project ]->extend(modules))
	endif
    endif
enddef

echomsg typename(ProjectModel)

g:ProjectConfig_BuildCScopeDatabase = BuildCScopeDatabase

export def EnableReScopeCommand(module_name: string, ...module_names: list<string>): void
    var arglist: string = "'"
	.. (<list<string>>[ g:ProjectConfig_Project ])
		->extend(ProjectModel.ListModuleNames->call([ module_name ]->extend(module_names)))
		->join("', '")
	.. "'"

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
		    endif
		endif
	    else
		this_module['private']['cscope'] = { db: '' }
	    endif
	endfor
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
