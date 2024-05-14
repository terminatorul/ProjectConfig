vim9script

import './ProjectConfigApi.vim' as ProjectConfig

type Module  = ProjectConfig.Module
type Project = ProjectConfig.Project

export var CxxOptions =
    [
	'--recurse', '--languages=+C,C++', '--kinds-C=+px', '--kinds-C++=+px',
	'--fields=+lzkKErSt', '--extras=+{qualified}{inputFile}{reference}', '--totals'
    ]

if ProjectConfig.HasWindows
    CxxOptions->extend(
	[
	    '-D_M_AMD64', '-D_WINDOWS', '-D_MBCS', '-D_WIN64', '-D_WIN32', '-D_MSC_VER=1933', '-D_MSC_FULL_VER=193331630'
	])
endif

g:ProjectConfig_CTagsCxxOptions = CxxOptions

var Join_Path = ProjectConfig.JoinPath
var Shell_Escape = ProjectConfig.ShellEscape
var List_Append_Unique = ProjectConfig.ListAppendUnique

export var CTags_Path: string
export var CTags_Options: list<string>
export var CTags_Directory: string = '.projectConfig'

if g:->has_key('ProjectConfig_Tags_Directory')
    CTags_Directory = g:ProjectConfig_Tags_Directory
endif

var Expand_CTags_Command: func(): void

def Expand_CTags_Command_Line(): void
    if g:->has_key('ProjectConfig_CTags_Executable')
	if type(g:ProjectConfig_CTags_Executable) == v:t_list
	    CTags_Path = exepath(g:ProjectConfig_CTags_Executable[0])
	    CTags_Options = g:ProjectConfig_CTags_Executable[1 : ]
	else
	    CTags_Path = exepath(g:ProjectConfig_CTags_Executable)
	    CTags_Options = [ ]
	endif
    else
	CTags_Path = exepath('ctags')
	CTags_Options = [ ]
    endif

    if g:->has_key('ProjectConfig_CTags_Options')
	CTags_Options->extend(g:ProjectConfig_CTags_Options)
    endif

    CTags_Path = Shell_Escape(CTags_Path)
    CTags_Options->map((_, option_string) => Shell_Escape(option_string))

    Expand_CTags_Command = (): void => {
    }
enddef

# Populate CTags_Path and CTags_Options
Expand_CTags_Command = Expand_CTags_Command_Line

def Build_Module_Tags(project: Project, module: Module): void
    var ctags_command_list = [ CTags_Path ] + CTags_Options
	 + project.config.ctags_args + module['private'].ctags_args + module['public'].ctags_args + [ '-f', Shell_Escape(module['private'].tags) ]
	 + List_Append_Unique(module['private'].src, module['public'].src, module['private'].inc, module['public'].inc)
		->mapnew((_, optarg) => Shell_Escape(optarg))

    var tags_dir = fnamemodify(module['private'].tags, ':h')
    call mkdir(tags_dir, 'p')
    execute '!' .. ctags_command_list->join(' ')

    if v:shell_error
	echoerr 'Error generating tags for module ' .. module.name .. ': shell command exited with code ' .. v:shell_error
    endif
enddef

def Build_Module_Tree_Tags(module_list: list<string>, project: Project, module: Module, external: bool): void
    if module.external && !external && filereadable(module['private'].tags)	# external libraries do not normally need to rebuild tags, after the first build
	return
    endif

    if module_list->index(module.name) < 0
	for dep_module_name in module['private'].deps + module['public'].deps
	    if project.modules->has_key(dep_module_name)
		Build_Module_Tree_Tags(module_list, project, project.modules[dep_module_name], external)
	    endif
	endfor

	module_list->add(module.name)
	Build_Module_Tags(project, module)
    endif
enddef

def BuildTagsTree(external: bool, project_name: string, module_name: string, ...module_names: list<string>): void
    if ProjectConfig.Projects->has_key(project_name)
	var project = ProjectConfig.Projects[project_name]

	Expand_CTags_Command()

	var module_list: list<string> = [ ]

	for name in [ module_name ]->extend(module_names)
	    if project.modules->has_key(name)
		var module = project.modules[name]
		Build_Module_Tree_Tags(module_list, project, module, external)
	    endif
	endfor
    endif
enddef

export def BuildTags(project_name: string, module_name: string, ...module_names: list<string>): void
    BuildTagsTree->call([ false, project_name, module_name ]->extend(module_names))
enddef

g:ProjectConfig_BuildTags = BuildTags

export def BuildAllTags(project_name: string, module_name: string, module_names: list<string>): void
    BuildTagsTree->call([ true, project_name, module_name ]->extend(module_names))
enddef

g:ProjectConfig_BuildAllTags = BuildAllTags

export def EnableReTagCommand(module_name: string, ...module_names: list<string>): void
    var arglist = "'" .. [ g:ProjectConfig_Project, module_name ]->extend(module_names)->join("', '") .. "'"
    execute "command ReTag" .. g:ProjectConfig_Project .. " call g:ProjectConfig_BuildTags(" .. arglist .. ")"
    execute "command ReTag" .. g:ProjectConfig_Project .. "All call g:ProjectConfig_BuildAllTags(" .. arglist .. ")"
enddef

g:ProjectConfig_EnableReTagCommand = EnableReTagCommand

class CTagsGenerator implements ProjectConfig.Generator
    var name: string =  'ctags'
    var global_tags: string
    var local_tags_list: list<string> = [ ]
    var external_tags_list: list<string> = [ ]

    def AddProject(project: Project, project_name: string): void
	if !project.config->has_key('ctags_args')
	    project.config['ctags_args'] = [ ]
	endif
    enddef

    def SetConfigEntry(project: Project, name: string): void
	if name == 'ctags_args'
	    if type(project.config[name]) != v:t_list
		project.config[name] = [ project.config[name] ]
	    endif

	    project.config[name]->map((_, val) => Shell_Escape(val))
	endif
    enddef

    def AddModule(project: Project, module: Module, ...modules: list<Module>): void
	for this_module in [ module ]->extend(modules)
	    for scope_name in [ 'private', 'public', 'interface' ]
		var scope = this_module[scope_name]

		if scope->has_key('ctags_args')
		    if type(scope.ctags_args) != v:t_list
			scope.ctags_args = [ scope.ctags_args ]
		    endif

		    scope.ctags_args->map((_, optarg) => Shell_Escape(optarg))
		else
		    scope.ctags_args = [ ]
		endif
	    endfor

	    if !this_module['private']->has_key('tags')
		this_module['private']['tags'] = Join_Path(g:ProjectConfig_Directory, CTags_Directory, this_module.name .. '.tags')
	    endif
	endfor
    enddef

    # Notifies the generator is enabled for a new project, and module
    # tree traversal shall start after
    def LocalConfigInit(): void
	var project = ProjectConfig.AddCurrentProject()
	project.config['orig_tags'] = &g:tags

	this.global_tags = &g:tags
    enddef

    # Called with external modules first, and local modules after,
    # Follows In-Depth, ButtomUp module tree traversal
    def UpdateGlobalConfig(module: Module): void
	execute 'set tags^=' .. module['private']['tags']->fnameescape()->substitute('[ \\]', '\\\0', 'g')->substitute('\V,', '\\\\,', 'g')
    enddef

    # Called for each module following In-Depth ButtomUp traversal
    # Notifies nested traversal (By-Depth, TopDown), for a module subtree has started
    def LocalConfigInitModule(module: Module): void
	this.local_tags_list = [ ]
	this.external_tags_list = [ ]
    enddef

    # Notify nested traversal in progress:
    #	- InDepth, ButtomUp enclosing traversal
    #	- ByDepth, TopDown nested traversal
    def UpdateModuleLocalConfig(module: Module): void
	if module.external
	    this.external_tags_list->add(module['private']['tags'])
	else
	    this.local_tags_list->add(module['private']['tags'])
	endif
    enddef

    # Called for each module following In-Depth ButtomUp traversal
    # Notifies nested traversal (By-Depth, TopDown), for a module subtree has
    # completed
    def LocalConfigCompleteModule(module: Module): void
	var tags_list: list<string> = this.local_tags_list + this.external_tags_list
	var tags_path: string = tags_list
		->mapnew((_, val) => val->fnameescape()->substitute('[ \\]', '\\\0', 'g')->substitute('\V,', '\\\\,', 'g'))
		->join(',')

# def ExpandTagBarPaths()
#     let g:tagbar_ctags_bin = exepath('ctags')   " Cache the location of ctags.exe on $PATH
#
#     if !len(g:tagbar_ctags_bin)
# 	unlet g:tagbar_ctags_bin
#     endif
# enddef

	var vim_cmd_set_tags: string  = 'setlocal tags^=' .. tags_path

	if !!len(this.global_tags)
	    vim_cmd_set_tags ..= ',' .. this.global_tags
	endif

	ProjectConfig.AddModuleAutoCmd(module, vim_cmd_set_tags)
    enddef
endclass

ProjectConfig.Generators->add(CTagsGenerator.new())

# defcompile
