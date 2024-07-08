vim9script

import './ProjectConfigApi_ProjectModel.vim' as ProjectModel

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

export type Property = ProjectModel.Property
export type Module   = ProjectModel.Module
export type Project  = ProjectModel.Project

export var Projects: dict<Project> = { }

g:ProjectConfig_Projects = Projects

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

export def LookupModuleList(module_name: any, ...module_names: list<any>): list<Module>
    var project = AddCurrentProject()

    return ProjectModel.LookupProjectModules(project, module_name, module_names)
enddef

# export const null_Module: Module = v:null_dict

export interface Generator
    def AddProject(project: Project, project_name: string): void
    def SetProjectConfig(project: Project, name: string): void
    def AddModule(project: Project, module: Module, ...modules: list<Module>): void

    def LocalConfigInit(module: Module, ...modules: list<Module>): void
    def UpdateGlobalConfig(module: Module): void
    def LocalConfigInitModule(module: Module): void
    def UpdateModuleLocalConfig(module: Module): void
    def LocalConfigCompleteModule(module: Module): void
endinterface

export var Generators: list<Generator> = [ ]

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

g:ProjectConfig_ListCompare = ListCompare

export var InPlaceAppendUnique  = ProjectModel.InPlaceAppendUnique
export var ListAppendUnique     = ProjectModel.ListAppendUnique
export var InPlacePrependUnique = ProjectModel.InPlacePrependUnique
export var ListPrependUnique    = ProjectModel.ListPrependUnique

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

# Add all modules to global g:ProjectConfig_Projects
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

export enum ShellEscapeTarget
    # Use Vim shellescape(), which doubles existing double-quote characters
    # within a quoted argument, but for Windows also moves trailing backslashes
    # outside the closing quote.
    Default,

    # Escape double quotes within a quoted argument with a backslash,
    # and doubles backslashe characterss aready present right before the quote
    WinAPI,

    # Escape double quotes within a quoted argument by duplicating them, with
    # trailing backslashes moved ouside the closing quote. Usually not working
    # if backslashes are present right before the quote, but still needed for
    # running .cmd / .bat scripts.
    DuplicateQuotes,

    # Use caret character (^) to escape cmd special characters that are not already
    # within double quotes (existing backslashes have no effect on double quotes,
    # quotes are still counted even if they appear to be escaped)
    CmdEscape,

    # Escapes !, # and % characters with a single backslash (any preceding
    # backslashes are ignored). Used for Vim ! command (shell execute )
    VimEscape,

    # Applies WinAPI quoting first, and escapes the result using CmdEscape after
    WinAPI_CmdEscape
endenum

def ShellEscape_Default(param: string): string
    if match(param, '\v^[a-zA-Z0-9_\.\,\+\-\=\#\@\:\\\/]+$') >= 0
	return param
    endif

    # Special case for Windows, when command line argument ends with '\' and
    # also needs to be quoted. Because the resulting '\"' at the end, actually
    # escapes the double-quote character

    if HasWindows
	var arg_len: number = param->strchars() - 1

	while arg_len >= 0 && param[arg_len] == '\'
	    --arg_len
	endwhile

	if arg_len >= 0
	    return param[0 : arg_len]->shellescape() .. param[arg_len + 1 : ]
	endif
    endif

    return param->shellescape()
enddef

def ShellEscape_VimEscape(param: string): string
    return param->escape('#!%')
enddef

# Backslash followd by double-quote (\") can not be safely quoted this way,
# but this mode is still needed for .cmd / .bat files
def ShellEscape_DuplicateQuotes(param: string): string
    if match(param, '\v^[a-zA-Z0-9_\.\,\+\-\=\#\@\:\\\/]+$') >= 0
	return param
    endif

    var arg_len: number = param->strchars() - 1

    while arg_len >= 0 && param[arg_len] == '\'
	--arg_len
    endwhile

    return '"' .. param[0 : arg_len]->substitute('\v\"', '""', 'g') .. '"' .. param[arg_len + 1 : ]
enddef

def ShellEscape_WinAPI(param: string): string
    if match(param, '\v^[a-zA-Z0-9_\.\,\+\-\=\#\@\:\\\/]+$') >= 0
	return param
    endif

    return '"' .. param->substitute('\v(\\*)\"', '\1\1\\\"', 'g')->substitute('\v(\\+)$', '\1\1', '') .. '"'
enddef

def ShellEscape_Cmd(param: string): string
    var quoted_param: string
    var [ base_index: number, is_quoted: bool, quote_index: number ] = [ 0, false, param->stridx('"') ]

    while quote_index >= 0
	if quote_index > base_index
	    if is_quoted
		quoted_param ..= param[base_index : quote_index - 1]
	    else
		quoted_param ..= param[base_index : quote_index - 1]->substitute('\v[^a-zA-Z0-9_\.\,\+\-\=\#\@\:\\\/ ]', '^\0', 'g')
	    endif
	endif

	quoted_param ..= '"'
	[ base_index, is_quoted, quote_index ] = [ quote_index + 1,  !is_quoted, param->stridx('"', quote_index + 1) ]
    endwhile

    if is_quoted
	quoted_param = quoted_param->substitute('\v\"$', '^"', '')
    endif

    quoted_param ..= param[base_index : ]->substitute('\v[^a-zA-Z0-9_\.\,\+\-\=\#\@\:\\\/ ]', '^\0', 'g')

    return quoted_param
enddef

export def ShellEscape(param: string, target: ShellEscapeTarget = ShellEscapeTarget.Default): string
    if target == ShellEscapeTarget.VimEscape
	return ShellEscape_VimEscape(param)
    elseif target == ShellEscapeTarget.Default || !HasWindows
	return ShellEscape_Default(param)
    elseif target == ShellEscapeTarget.WinAPI
	return ShellEscape_WinAPI(param)
    elseif target == ShellEscapeTarget.CmdEscape
	return ShellEscape_Cmd(param)
    elseif target == ShellEscapeTarget.WinAPI_CmdEscape
	return ShellEscape_Cmd(ShellEscape_WinAPI(param))
    endif

    throw "ShellEscape: bad ShellEscapeTarget argument"
enddef

# const test_strings: list<string> = [
# 	'(if (eq? $name &name) (cond ((and (eq? $kind "p") (eq? &kind "f")) 1)',
# 	'(delta " flayer)',
# 	'(d| & ) ] {elta " flayer)',
# 	'(delta " fl|a&y(e}r)',
# 	'(delta \" flayer)',
# 	'(delta \" flayer\\)',
# 	'(delta \" ""flayer\\)',
# 	'(delta \" ""flayer\\")',
# 	'("delta \" ""flayer\\")'
# ]
#
# for test_str in test_strings
#     echomsg test_str .. ' => ' .. ShellEscape(test_str, ShellEscapeTarget.WinAPI_CmdEscape)
# endfor

g:ProjectConfig_ShellEscape = ShellEscape

export def SetProjectConfig(name: string, value: any): void
    var project: Project = AddCurrentProject()

    project.config[name] = value

    for generator in Generators
	generator.SetProjectConfig(project, name)
    endfor
enddef

g:ProjectConfig_SetConfigEntry = SetProjectConfig

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

export def EnableProjectModules(module_name: any, ...module_names: list<any>): void
    var project = AddCurrentProject()

    var modules: list<Module> = ProjectModel.LookupProjectModules->call([project, module_name ]->extend(module_names))

    Generators->foreach((_, gen: Generator): void => gen.LocalConfigInit->call(modules))

    var processed_modules: list<string> = [ ]

    for external in [ true, false ]
	for current_module in modules
	    GlobalUpdate_InDepth_ButtomUp_Traverse_Module(Generators, processed_modules, external, current_module)
	endfor
    endfor

    processed_modules = [ ]

    for current_module in modules
	LocalUpdate_InDepth_ButtomUp_ReTraverse(Generators, processed_modules, current_module)
    endfor

    lockvar! Projects[g:ProjectConfig_Project]
enddef

g:ProjectConfig_EnableProjectModules = EnableProjectModules

# defcompile
