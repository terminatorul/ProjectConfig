vim9script

import './ProjectConfigApi_ProjectModel.vim' as ProjectModel
import './ProjectConfigApi_Generator.vim' as ProjectConfig

type Module  = ProjectConfig.Module
type Project = ProjectConfig.Project
type ShellEscapeTarget = ProjectConfig.ShellEscapeTarget

var ListModuleNames = ProjectModel.ListModuleNames

export var TagsExtraSort = true

export var CxxOptions: func(): list<string> =
    () =>
	[
	    '--recurse', '--languages=+C,C++', '--kinds-C=+px', '--kinds-C++=+px',
	    '--fields=+lzkKErSt', '--extras=+{qualified}{inputFile}{reference}', '--totals'
	]

export var PhpOptions: list<string> =
    [
	'--languages=+php,sql',
	'--recurse',
	'--fields=+lzkKErSt',
	'--kinds-SQL=+p',
	'--extras=+{qualified}{inputFile}{reference}',
	'--totals'
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

export var ReadTags_Command: list<string>
export var CTags_Path: string
export var CTags_Options: list<string>
export var CTags_Directory: string = '.projectConfig'

if g:->has_key('ProjectConfig_Tags_Directory')
    CTags_Directory = g:ProjectConfig_Tags_Directory
endif

export var BuildReadTagsSortCommand: func(list<string>, string, ...list<string>): list<string> =
    g:->has_key('ProjectConfig_ReadTagsSortCommand') ?
	(command_line: list<string>, tagfile: string, ...other_args: list<string>) => g:ProjectConfig_ReadTagsSortCommand->call([ command_line, tagfile ]->extend(other_args)) :
	(command_line: list<string>, tagfile: string, ...other_args: list<string>) => command_line->extend([ '--tag-file', tagfile ])->extend(other_args)

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

    if g:->has_key('ProjectConfig_ReadTags_Command')
	if type(g:ProjectConfig_ReadTags_Command) == v:t_list
	    ReadTags_Command = g:ProjectConfig_ReadTags_Command
	else
	    ReadTags_Command = [ g:ProjectConfig_ReadTags_Command ]
	endif

	ReadTags_Command[0] = exepath(ReadTags_Command[0])
    else
	var readTagsExe: list<string> = (CTags_Path->fnamemodify('%:h') .. '/readtags' .. (ProjectConfig.HasWindows ? '.exe' : ''))->glob(true, true)

	if !!readTagsExe
	    ReadTags_Command = readTagsExe[0 : 0]
	else
	    readTagsExe = [ exepath('readtags') ]

	    if !!readTagsExe && !!readTagsExe[0]
		ReadTags_Command = readTagsExe[0 : 0]
	    endif
	endif
    endif

    ReadTags_Command->map((_, optarg) => Shell_Escape(optarg))

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
    var tag_sort: bool = module['private']->get('tag_extra_sort', module['public']->get('tag_extra_sort', project.config->get('tag_extra_sort', g:->get('ProjectConfig_CTagsExtraSort', TagsExtraSort))))
    var tags_file_name: string = module['private'].tags .. (tag_sort && !!ReadTags_Command ? '.unsorted' : '')
    var source_list: list<string> = List_Append_Unique(module['private'].src, module['public'].src, module['private'].inc, module['public'].inc)
		->mapnew((_, src) => src->glob(true, true, true))->flattennew(1)
		->mapnew((_, optarg) => Shell_Escape(Shell_Escape(optarg), ShellEscapeTarget.VimEscape))

    if source_list->empty()
	echoerr "Missing ctags input files or directories for module " .. module.name
	return
    endif

    var ctags_command_list: list<string> = [ CTags_Path ] + CTags_Options
	 + project.config.ctags_args + module['private'].ctags_args + module['public'].ctags_args + [ '-f', Shell_Escape(tags_file_name) ]
	 + source_list

    module['private']['tags']->fnamemodify(':h')->mkdir('p')

    execute '!' .. ctags_command_list->join(' ')

    if !!v:shell_error
	echoerr 'Error generating tags for module ' .. module.name .. ': shell command exited with code ' .. v:shell_error
    else
	if tag_sort && !!ReadTags_Command
	    var readtags_command_line: list<string> = BuildReadTagsSortCommand(ReadTags_Command + [ '--extension-fields', '--line-number', '--escape-output' ], tags_file_name,
		    '--with-pseudo-tags',
		    '--sorter', '(if (eq? $name &name) (cond ((and (or (eq? $kind "p") (eq? $kind "prototype")) (or (eq? &kind "f") (eq? &kind "function"))) 1) ((and (or (eq? $kind "f") (eq? $kind "function")) (or (eq? &kind "p") (eq? &kind "prototype"))) -1) (#t 0)) (<> $name &name))',
		    '--list'
		    )
			->map((_, optarg) => Shell_Escape(Shell_Escape(optarg, ShellEscapeTarget.WinAPI_CmdEscape), ShellEscapeTarget.VimEscape))
		+
		[ '>', Shell_Escape(module['private'].tags) ]

	    execute '!' .. readtags_command_line->join(' ')

	    if !!v:shell_error
		echomsg 'Error sorting tags for module ' .. module.name .. ': readtags shell command exited with code ' .. v:shell_error
		rename(tags_file_name, module['private']['tags'])   # keep unsorted tags file if sorting has failed
	    else
		if !!delete(tags_file_name)
		    echomsg "Removing temporary file " .. tags_file_name .. " failed."
		endif
	    endif
	endif
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

export def BuildAllTags(project_name: string, module_name: string, ...module_names: list<string>): void
    BuildTagsTree->call([ true, project_name, module_name ]->extend(module_names))
enddef

g:ProjectConfig_BuildAllTags = BuildAllTags

export def EnableReTagCommand(module_name: any, ...module_names: list<any>): void
    var arglist = "'" .. (<list<string>>[ g:ProjectConfig_Project ])->extend(ListModuleNames->call([ module_name ]->extend(module_names)))->join("', '") .. "'"
    execute "command ReTag" .. g:ProjectConfig_Project .. " call BuildTags(" .. arglist .. ")"
    execute "command ReTag" .. g:ProjectConfig_Project .. "All BuildAllTags(" .. arglist .. ")"
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

    def SetProjectConfig(project: Project, name: string): void
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
    def LocalConfigInit(module: Module, ...modules: list<Module>): void
	var project: Project = ProjectConfig.AddCurrentProject()
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

	var vim_cmd_set_tags: string  = 'setlocal tags^=' .. tags_path

	if !!len(this.global_tags)
	    vim_cmd_set_tags ..= ',' .. this.global_tags
	endif

	ProjectConfig.AddModuleAutoCmd(module, vim_cmd_set_tags)
    enddef
endclass

ProjectConfig.Generators->add(CTagsGenerator.new())

# defcompile
