vim9script

import './ProjectConfigApi.vim' as ProjectConfig

type Property = ProjectConfig.Property
type Module = ProjectConfig.Module
type Project = ProjectConfig.Project

if !exists('g:ProjectConfig_CleanPathOption')
    g:ProjectConfig_CleanPathOption = true
endif

class VimPathGenerator implements ProjectConfig.Generator
    var name: string = 'include'
    var global_path: string
    var local_inc_list: list<string>
    var external_inc_list: list<string>

    def AddProject(project: Project, project_name: string): void
    enddef

    def SetConfigEntry(project: Project, name: string): void
    enddef

    def AddModule(project: Project, module: Module, ...modules: list<Module>)
    enddef

    # Notifies the generator is enabled for a new project, and module
    # traversal shall start after
    def LocalConfigInit(): void
	if !!g:ProjectConfig_CleanPathOption
	    set path-=
	endif

	var project = ProjectConfig.AddCurrentProject()
	project.config['orig_path'] = &g:path

	this.global_path = &g:path
    enddef

    # Called with external modules first, and local modules after,
    # following In-Depth, ButtomUp module tree traversal
    def UpdateGlobalConfig(module: Module): void
	set path-=.

	for inc_dir in module['private'].inc + module['public'].inc
	    execute 'set path-=' .. inc_dir->fnameescape()->substitute('[ \\]', '\\\0', 'g')->substitute('\V,', '\\\\,', 'g')
	    execute 'set path^=' .. inc_dir->fnameescape()->substitute('[ \\]', '\\\0', 'g')->substitute('\V,', '\\\\,', 'g')
	endfor

	set path^=.
    enddef

    # Notify nested traversal of the module subtree has started
    def LocalConfigInitModule(module: Module): void
	this.local_inc_list = [ ]
	this.external_inc_list = [ ]
    enddef

    # Notify nested traversal in progress:
    #	- InDepth, ButtomUp enclosing traversal
    #	- ByDepth, TopDown nested traversal
    def UpdateModuleLocalConfig(module: Module): void
	if module.external
	    this.external_inc_list->extend(module['private'].inc + module['public'].inc)
	else
	    this.local_inc_list->extend(module['private'].inc + module['public'].inc)
	endif
    enddef

    # Notify traversal by depth level, top to buttom, for a module subtree is
    # complete
    def LocalConfigCompleteModule(module: Module)
	var inc_list: list<Property> = this.local_inc_list + this.external_inc_list
	var inc_path: string = inc_list->mapnew((_, inc_dir) => inc_dir->fnameescape()->substitute('[ \\]', '\\\1', 'g')->substitute('\V,', '\\\\,', 'g'))->join(',')
	var cmd: string = 'setlocal path^=' .. inc_path

	if !!len(this.global_path)
	    cmd ..= ',' .. this.global_path
	endif

	cmd ..= ' | setlocal path-=.'
	cmd ..= ' | setlocal path-=.'
	cmd ..= ' | setlocal path-=.'
	cmd ..= ' | setlocal path^=.'

	if !!g:ProjectConfig_CleanPathOption
	    cmd ..= ' | setlocal path-='
	    cmd ..= ' | setlocal path-='
	    cmd ..= ' | setlocal path-='
	endif

	ProjectConfig.AddModuleAutoCmd(module, cmd)
    enddef
endclass

ProjectConfig.Generators->add(VimPathGenerator.new())

# defcompile
