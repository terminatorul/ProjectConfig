vim9script

import autoload './ProjectConfigApi_DependencyWalker.vim' as DependencyWalker

export const HasWindows: bool = has('win16') || has('win32') || has('win64')
export const DirectorySeparator: string = exists('+shellslash') ? '\' : '/'
export const DevNull: string = HasWindows ?  'NUL' : '/dev/null'

g:ProjectConfig_DirectorySeparator = DirectorySeparator
g:ProjectConfig_DevNull = DevNull

# Join multiple path components using the directory separator in
# g:ProjectConfig_DirectorySeparator
export def JoinPath(...components: list<string>): string
    return join(components, DirectorySeparator)
enddef

g:ProjectConfig_JoinPath = JoinPath

g:ProjectConfig_Generators = [ ]

export type Property = any
export type Module = dict<any>
export type Project = dict<any>

export interface Generator
    def AddProject(project: Project, project_name: string): void
    def SetConfigEntry(project: Project, name: string): void
    def AddModule(project: Project, module: Module, ...modules: list<Module>): void

    def LocalConfigInit(): void
    def UpdateGlobalConfig(module: Module): void
    def LocalConfigInitModule(module: Module): void
    def UpdateModuleLocalConfig(module: Module): void
    def LocalConfigCompleteModule(module: Module): void
endinterface

class DispatchGenerator implements Generator
    var generators: list<dict<any>>

    def AddProject(project: Project, name: string): void
	this.generators->foreach((_, gen): void => gen.AddProject(name))
    enddef

    def SetConfigEntry(project: Project, name: string): void
	this.generators->foreach((_, gen): void => gen.SetConfigEntry(name))
    enddef

    def AddModule(project: Project, module: Module, ...modules: list<Module>): void
	this.generators->foreach((_, gen): void => gen.AddModule->call([ module ]->extend(modules)))
    enddef

    def LocalConfigInit(): void
	this.generators->foreach((_, gen): void => gen.LocalConfigInit())
    enddef

    def UpdateGlobalConfig(module: Module): void
	this.generators->foreach((_, gen): void => gen.UpdateGlobalConfig(module))
    enddef

    def LocalConfigInitModule(module: Module): void
	this.generators->foreach((_, gen): void => gen.LocalConfigInitModule(module))
    enddef

    def UpdateModuleLocalConfig(module: Module): void
	this.generators->foreach((_, gen): void => gen.UpdateModuleLocalConfig(module))
    enddef

    def LocalConfigCompleteModule(module: Module): void
	this.generators->foreach((_, gen): void => gen.LocalConfigCompleteModule(module))
    enddef
endclass

export var Generators: list<Generator> = [ DispatchGenerator.new(g:ProjectConfig_Generators) ]

# Element-wise comparison for two lists, returns -1, 0, or 1
export def ListCompare(list1: list<any>, list2: list<any>): number
    var len1: number = list1->len()
    var len2: number = list2->len()
    var len:  number = [ len1, len2 ]->min()

    var index: number = 0

    while index < len
	if list1[index] < list2[index]
	    return -1
	else
	    if list1[index] > list2[index]
		return 1
	    endif
	endif

	++index
    endwhile

    if len1 < len2
	return -1
    else
	if len1 > len2
	    return 1
	endif
    endif

    return 0
enddef

g:ProjectConfig_ListCompare =  ListCompare

# duplicate values that appear sooner have priority and will be kept over
# values that appear later
export def InPlaceAppendUnique(l1: list<any>, l2: list<any>, ...extra: list<list<any>>): list<any>
    for element in [ l2 ]->extend(extra)->flattennew(1)
	if l1->index(element) < 0
	    l1->add(element)
	endif
    endfor

    return l1
enddef

g:ProjectConfig_InPlaceAppendUnique =  InPlaceAppendUnique

# duplicate values that appear sooner have priority and will be kept over
# values that appear later
export def ListAppendUnique(l1: list<any>, l2: list<any>, ...extra: list<list<any>>): list<any>
    return InPlaceAppendUnique->call([ copy(l1), l2 ]->extend(extra))
enddef

g:ProjectConfig_ListAppendUnique =  ListAppendUnique

# duplicate values that appear sooner in the target list have priority over
# values that appear later. The element order in l2 + ... is otherwise
# preserved
export def InPlacePrependUnique(l1: list<any>, l2: list<any>, ...extra: list<list<any>>): list<any>
    for element in [ l2 ]->extend(extra)->flattennew(1)->reverse()
	var element_index: number = l1->index(element)

	if element_index >= 0
	    l1->remove(element_index)
	endif

	eval l1->insert(element)
    endfor

    return l1
enddef

g:ProjectConfig_InPlacePrependUnique = InPlacePrependUnique

# duplicate values that appear sooner in the target list have priority over
# values that appear later. The element order in l2 + ... is otherwise
# preserved
export def ListPrependUnique(l1: list<any>, l2: list<any>, ...extra: list<list<any>>): list<any>
    return InPlacePrependUnique->call([ copy(l1), l2 ]->extend(extra))
enddef

g:ProjectConfig_ListPrependUnique = ListPrependUnique

export def ExpandModuleSources(module: Module, filters: list<string> = [ ]): list<string>
    var source_list: list<string> = [ ]

    for source_glob in module['private'].src + module['public'].src
	var descend_glob: string
	var run_filter: bool
	var file_list

	if isdirectory(source_glob)
	    if module.recurse
		descend_glob = source_glob .. '/**'
		run_filter = false
	    else
		descend_glob = source_glob .. '/*'
		run_filter = true
	    endif
	else
	    descend_glob = source_glob
	    run_filter = true
	endif

	var file_list: list<string> = descend_glob->glob(true, true)

	if filters
	    Apply_Filters(file_list, filters)
	else

	if run_filter
	    file_list->filter((_, val) => !isdirectory(val))
	endif

	InPlace_Append_Unique(source_list, file_list)
    endfor

    return source_list
enddef

g:ProjectConfig_ExpandModuleSources = ExpandModuleSources

export var Projects: dict<Project> = { }

g:ProjectConfig_Modules = Projects

export def AddCurrentProject(): Project
    if Projects->has_key(g:ProjectConfig_Project)
	return Projects[g:ProjectConfig_Project]
    endif

    Projects[g:ProjectConfig_Project] = { 'config': { }, 'modules': { } }

    var project: Project = Projects[g:ProjectConfig_Project]

    for generator in Generators
	generator.AddProject(project, g:ProjectConfig_Project)
    endfor

    return project
enddef

g:ProjectConfig_AddCurrentProject = AddCurrentProject

# Construct and return a new empty project module with given name
export def CreateModule(name: string, external: bool = false): Module
    var module: Module = { 'name': name, 'external': external }

    for scope in [ 'private', 'public', 'interface' ]
	module[scope] = { }

	var module_scope: dict<any> = module[scope]

	module_scope.dir = [ ]
	module_scope.src = [ ]
	module_scope.inc = [ ]
	module_scope.deps = [ ]
    endfor

    return module
enddef

g:ProjectConfig_Module = CreateModule

# Add all modules to global g:ProjectConfig_Modules
# and fill in default fields for a module
export def AddModule(module: Module, ...modules: list<Module>)
    var module_list: list<Module> = [ module ]->extend(modules)

    for current_module in module_list
	if !current_module->has_key('name')
	    echoerr 'Missing module name'
	    return
	endif

	if !current_module->has_key('external')
	    current_module.external = false
	endif

	if !current_module->has_key('recurse')
	    if current_module->has_key('recursive')
		current_module.recurse = current_module.recursive
	    else
		current_module.recurse = false
	    endif
	endif

	for scope_name in [ 'private', 'public', 'interface' ]
	    if !current_module->has_key(scope_name)
		current_module[scope_name] = { }
	    endif

	    var module_scope = current_module[scope_name]

	    if module_scope->has_key('dir')
		if type(module_scope.dir) != v:t_list
		    module_scope.dir = [ module_scope.dir ]
		endif
	    else
		module_scope.dir = [ ]
	    endif

	    if module_scope->has_key('src')
		if type(module_scope.src) != v:t_list
		    module_scope.src = [ module_scope.src ]
		endif
	    else
		module_scope.src = [ ]
	    endif

	    if module_scope->has_key('inc')
		if type(module_scope.inc) != v:t_list
		    module_scope.inc = [ module_scope.inc ]
		endif
	    else
		module_scope.inc = [ ]
	    endif

	    if module_scope->has_key('deps')
		if type(module_scope.deps) != v:t_list
		    module_scope.deps = [ module_scope.deps ]
		endif
	    else
		module_scope.deps = [ ]
	    endif
	endfor
    endfor

    var project: Project = AddCurrentProject()

    for current_module in module_list
	project.modules[current_module.name] = current_module
    endfor

    for generator in Generators
	generator.AddModule->call([ project ]->extend(module_list))
    endfor
enddef

g:ProjectConfig_AddModule = AddModule

export def AddModuleAutoCmd(module: Module, commands: any, pattern: list<string> = [ ])
    var auto_cmd: dict<any> = { }

    auto_cmd.group   = g:ProjectConfig_Project
    auto_cmd.event   = module.external ? [ 'BufRead' ] : [ 'BufNewFile', 'BufRead' ]
    auto_cmd.cmd     = commands
    auto_cmd.pattern = pattern

    if pattern->len() == 0
	var dir_pattern: string = module.recurse ? '**' : '*'

	for dir_name in module['private'].dir + module['public'].dir
	    auto_cmd.pattern->add(dir_name->fnamemodify(':p')->substitute('\\', '/', 'g') .. dir_pattern)
	endfor
    endif

    # echomsg auto_cmd

    [ auto_cmd ]->autocmd_add()
enddef

g:ProjectConfig_AddModuleAutoCmd = AddModuleAutoCmd

export def ParsePathOption(value: string): list<string>
    var value_list: list<string> = [ ]
    var value_str: string = ''
    var escape_char: bool = false

    for char in value
	if escape_char
	    if char == ' ' || char == '\' || char == ','
		value_str ..= char
	    else
		value_str ..= '\'
		value_str ..= char
	    endif

	    escape_char = false
	else
	    if char == '\'
		escape_char = true
	    else
		if char == ','
		    value_list->add(value_str)
		    value_str = ''
		else
		    value_str ..= char
		endif
	    endif
	endif
    endfor

    value_list->add(value_str)

    return value_list
enddef

g:ProjectConfig_ParsePathOption = ParsePathOption

export def ShowPath(value = v:none): void
    for dir in g:ProjectConfig_ParsePathOption(value ?? &l:path ?? &g:path)
	echo dir
    endfor
enddef

g:ProjectConfig_ShowPath = ShowPath

export def ShellEscape(param: string): string
    if match(param, '\v^[a-zA-Z0-9_\.\,\+\-\=\#\@\:\\\/]+$') >= 0
	return param
    endif

    # Special case for Windows, when command line argument ends with '\' and
    # also needs to be quoted. Because the resulting '\"' at the end, actually
    # escapes the double-quote character

    if HasWindows
	var arg_len: number = param->len() - 1

	while arg_len >= 0 && param[arg_len] == '\'
	    arg_len = arg_len - 1
	endwhile

	if arg_len >= 0
	    return param[0 : arg_len]->shellescape() .. param[arg_len + 1 : ]
	endif
    endif

    return param->shellescape()
enddef

g:ProjectConfig_ShellEscape = ShellEscape

export def SetConfigEntry(name: string, value: any): void
    var project: Project = AddCurrentProject()

    project.config[name] = value

    for generator in Generators
	generator.SetConfigEntry(project, name)
    endfor
enddef

g:ProjectConfig_SetConfigEntry = SetConfigEntry

def GlobalUpdate_InDepth_ButtomUp_Traverse_Module(
	    generators:		list<Generator>,
	    processed_modules:	list<string>,
	    external_modules:	bool,
	    module:		Module
	):  void
    if processed_modules->index(module.name) < 0
	if !!module.external == !!external_modules
	    processed_modules->add(module.name)
	endif

	var project: Project = AddCurrentProject()

	for dependency_module in module['private'].deps + module['public'].deps + module['interface'].deps
	    if project.modules->has_key(dependency_module)
		GlobalUpdate_InDepth_ButtomUp_Traverse_Module(
			    generators,
			    processed_modules,
			    external_modules,
			    project.modules[dependency_module]
			)
	    endif
	endfor

	if !!module.external == !!external_modules
	    generators->foreach(( _, gen: Generator): void => gen.UpdateGlobalConfig(module))
	endif
    endif
enddef

def LocalUpdate_Traverse_Module_SubLevel(
	    generators:		 list<Generator>,
	    processed_modules:	 list<string>,
	    current_depth_level: number,
	    target_depth_level:	 number,
	    external_modules:	 bool,
	    module:		 Module
	):  bool
    if current_depth_level == target_depth_level
	if !!module.external == !!external_modules && processed_modules->index(module.name) < 0
	    processed_modules->add(module.name)
	    generators->foreach((_, gen: Generator): void => gen.UpdateModuleLocalConfig(module))
	endif

	return true
    else
	var target_depth_reached: bool = false
	var project = AddCurrentProject()

	for dependency_module in module['private'].deps + module['public'].deps + module['interface'].deps
	    if project.modules->has_key(dependency_module)
		var level_reached: bool = LocalUpdate_Traverse_Module_SubLevel(
			    generators,
			    processed_modules,
			    current_depth_level + 1,
			    target_depth_level,
			    external_modules,
			    project.modules[dependency_module]
			)

		target_depth_reached = target_depth_reached || level_reached
	    endif
	endfor

	return target_depth_reached
    endif
enddef

def LocalUpdate_Level_TopDown_Traverse_Module(generators: list<Generator>, external_modules: bool, module: Module): void
    var depth_level: number = 1
    var processed_modules: list<string> = [ ]

    while LocalUpdate_Traverse_Module_SubLevel(generators, processed_modules, 1, depth_level, external_modules, module)
	++depth_level
    endwhile
enddef

def LocalUpdate_InDepth_ButtomUp_ReTraverse(generators: list<Generator>, processed_modules: list<string>, module: Module)
    if processed_modules->index(module.name) < 0
	processed_modules->add(module.name)

	var project = AddCurrentProject()

	for dependency_module in module['private'].deps + module['public'].deps
	    if project.modules->has_key(dependency_module)
		LocalUpdate_InDepth_ButtomUp_ReTraverse(generators, processed_modules, project.modules[dependency_module])
	    endif
	endfor

	generators->foreach((_, gen: Generator): void => gen.LocalConfigInitModule(module))
	LocalUpdate_Level_TopDown_Traverse_Module(generators, true, module)
	LocalUpdate_Level_TopDown_Traverse_Module(generators, false, module)
	generators->foreach((_, gen: Generator): void => gen.LocalConfigCompleteModule(module))
    endif
enddef

export def EnableProjectModules(module_name: string, ...module_names: list<string>): void
    Generators->foreach((_, gen: Generator): void => gen.LocalConfigInit())

    var project = AddCurrentProject()
    var processed_modules: list<string> = [ ]

    for external in [ true, false ]
	for name in [ module_name ]->extend(module_names)
	    if project.modules->has_key(name)
		GlobalUpdate_InDepth_ButtomUp_Traverse_Module(Generators, processed_modules, external, project.modules[name])
	    endif
	endfor
    endfor

    processed_modules = [ ]

    for name in [ module_name ]->extend(module_names)
	if project.modules->has_key(name)
	    LocalUpdate_InDepth_ButtomUp_ReTraverse(Generators, processed_modules, project.modules[module_name])
	endif
    endfor
enddef

g:ProjectConfig_EnableVimTags = EnableProjectModules

# defcompile
