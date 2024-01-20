
let g:ProjectConfig_CTags = { }

let s:Join_Path = funcref('g:ProjectConfig_JoinPath')
let s:Shell_Escape = funcref('g:ProjectConfig_ShellEscape')

if !exists('g:ProjectConfig_Tags_Directory')
    let g:ProjectConfig_Tags_Directory = '.tags'
endif

function s:EmptyFunction()
endfunction

function s:Expand_CTags_Command_Line()
    if exists('g:ProjectConfig_CTags_Executable')
	if type(g:ProjectConfig_CTags_Executable) == v:t_list
	    let s:ProjectConfig_CTags_Path = exepath(g:ProjectConfig_CTags_Executable[0])
	    let s:ProjectConfig_CTags_Options = g:ProjectConfig_CTags_Executable[1:]
	else
	    let s:ProjectConfig_CTags_Path = exepath(g:ProjectConfig_CTags_Executable)
	    let s:ProjectConfig_CTags_Options = [ ]
	endif
    else
	let s:ProjectConfig_CTags_Path = exepath('ctags')
	let s:ProjectConfig_CTags_Options = [ ]
    endif

    if exists('g:ProjectConfig_CTags_Options')
	call extend(s:ProjectConfig_CTags_Options, g:ProjectConfig_CTags_Options)
    endif

    let s:ProjectConfig_CTags_Path = s:Shell_Escape(s:ProjectConfig_CTags_Path)
    call map(s:ProjectConfig_CTags_Options, { key, val -> s:Shell_Escape(val) })

    let s:Expand_CTags_Command = funcref('s:EmptyFunction')
endfunction

" Populate s:ProjectConfig_CTags_Path and s:ProjectConfig_CTags_Options
let s:Expand_CTags_Command = funcref('s:Expand_CTags_Command_Line')

function s:List_Append_Unique(l1, l2)
    let l:list = copy(a:l1)

    for l:element in a:l2
	if index(l:list, l:element) < 0
	    call add(l:list, l:element)
	endif
    endfor

    return l:list
endfunction

function s:Build_Module_Tags(project, module)
    let l:project = g:ProjectConfig_Modules[a:project]
    let l:mod = l:project.modules[a:module]
    let l:ctags_command_list = [ s:ProjectConfig_CTags_Path ] + s:ProjectConfig_CTags_Options
	\ + l:project.config.ctags_args + l:mod.ctags_args + [ '-f', s:Shell_Escape(l:mod.tags) ]
	\ + mapnew(s:List_Append_Unique(l:mod.src, l:mod.inc), { key, val -> s:Shell_Escape(val) })

    let l:tags_dir = fnamemodify(l:mod.tags, ':h')
    call mkdir(l:tags_dir, 'p')
    execute '!' . join(l:ctags_command_list, ' ')

    if v:shell_error
	echoerr 'Error generating tags for module ' . l:mod.name . ': shell command exited with code ' . v:shell_error
    endif
endfunction

function s:Build_Module_Tree_Tags(module_list, project, mod, add_external)
    if a:mod.external && !a:add_external && filereadable(a:mod.tags)	" external libraries do not normally need to rebuild tags, after the first build
	return
    endif

    if index(a:module_list, a:mod.name) < 0
	for l:dep_module in a:mod.deps
	    if has_key(g:ProjectConfig_Modules[a:project].modules, l:dep_module)
		call s:Build_Module_Tree_Tags(a:module_list, a:project, g:ProjectConfig_Modules[a:project].modules[l:dep_module], a:add_external)
	    endif
	endfor

	call s:Build_Module_Tags(a:project, a:mod.name)
	call add(a:module_list, a:mod.name)
    endif
endfunction

function s:ProjectConfig_BuildTagsTree(add_external, project, module, modules)
    if has_key(g:ProjectConfig_Modules, a:project)
	call s:Expand_CTags_Command()

	let l:module_list = [ ]

	for l:module_name in [ a:module ] + a:modules
	    if has_key(g:ProjectConfig_Modules[a:project].modules, l:module_name)
		let l:mod = g:ProjectConfig_Modules[a:project].modules[l:module_name]
		call s:Build_Module_Tree_Tags(l:module_list, a:project, l:mod, a:add_external)
	    endif
	endfor
    endif
endfunction

function g:ProjectConfig_BuildTags(project, module, ...)
    call s:ProjectConfig_BuildTagsTree(v:false, a:project, a:module, a:000)
endfunction

function g:ProjectConfig_BuildAllTags(project, module, ...)
    call s:ProjectConfig_BuildTagsTree(v:true, a:project, a:module, a:000)
endfunction

function g:ProjectConfig_EnableReTagCommand(module, ...)
    execute "command ReTag" . g:ProjectConfig_Project . " call g:ProjectConfig_BuildTags('" . join([ g:ProjectConfig_Project, a:module ] + a:000, "', '") . "')"
    execute "command ReTag" . g:ProjectConfig_Project . "All call g:ProjectConfig_BuildAllTags('" . join([ g:ProjectConfig_Project, a:module ] + a:000, "', '") . "')"
endfunction

" Notify current project is added to g:ProjectConfig_Modules
function <SID>ProjectConfig_CTags_AddCurrentProject()
    if !has_key(g:ProjectConfig_Modules[g:ProjectConfig_Project].config, 'ctags_args')
	let g:ProjectConfig_Modules[g:ProjectConfig_Project].config['ctags_args'] = [ ]
    endif
endfunction

" Notify project config entry is updated
function <SID>ProjectConfig_CTags_SetConfigEntry(name)
    if a:name == 'ctags_args'
	if type(g:ProjectConfig_Modules[g:ProjectConfig_Project].config[a:name]) != v:t_list
	    let g:ProjectConfig_Modules[g:ProjectConfig_Project].config[a:name] = [ g:ProjectConfig_Modules[g:ProjectConfig_Project].config[a:name] ]
	endif

	call map(g:ProjectConfig_Modules[g:ProjectConfig_Project].config[a:name], { _, val -> s:Shell_Escape(val) })
    endif
endfunction

" Notify new project module is initialized
function <SID>ProjectConfig_CTags_AddModule(mod)
    if has_key(a:mod, 'ctags_args')
	if type(a:mod.ctags_args) != v:t_list
	    let a:mod.ctags_args = [ a:mod.ctags_args ]
	endif

	call map(a:mod.ctags_args, { key, val -> s:Shell_Escape(val) })
    else
	let a:mod.ctags_args = [ ]
    endif

    if !has_key(a:mod, 'tags')
	let a:mod.tags = s:Join_Path(g:ProjectConfig_Directory, g:ProjectConfig_Tags_Directory, a:mod.name . '.tags')
    endif
endfunction

let g:ProjectConfig_CTags.AddCurrentProject = funcref('<SID>ProjectConfig_CTags_AddCurrentProject')
let g:ProjectConfig_CTags.SetConfigEntry = funcref('<SID>ProjectConfig_CTags_SetConfigEntry')
let g:ProjectConfig_CTags.AddModule = funcref('<SID>ProjectConfig_CTags_AddModule')

function g:ProjectConfig_CTags.LocalConfigInit()
    let g:ProjectConfig_Modules[g:ProjectConfig_Project].config['orig_tags'] = &g:tags
    let self.global_tags = &g:tags
    let self.tags_list = { }
endfunction

" Will be called with external modules first, and local modules after,
" each time following in-depth traversal of the module tree
function g:ProjectConfig_CTags.UpdateGlobalConfig(mod)
    execute 'set tags ^=' . a:mod.tags->fnameescape()->substitute('[ \\]', '\\\0', 'g')->substitute('\V,', '\\\\,', 'g')
endfunction

" Notify traversal by depth level, top to bottom, for a module subtree has started
function g:ProjectConfig_CTags.LocalConfigInitModule(mod)
    let self.local_tags_list = [ ]
    let self.external_tags_list = [ ]
endfunction

" Notify next node during traversal by depth level, top to bottom, of a subtree
function g:ProjectConfig_CTags.UpdateModuleLocalConfig(mod)
    if a:mod.external
	eval self.external_tags_list->add(a:mod.tags)
    else
	eval self.local_tags_list->add(a:mod.tags)
    endif
endfunction

" Notify traversal by depth level, top to buttom, for a module subtree is
" complete
function g:ProjectConfig_CTags.LocalConfigCompleteModule(mod)
    let l:tags_list = self.local_tags_list + self.external_tags_list
    let l:cmd = 'setlocal tags^=' . l:tags_list->map({ _, val -> val->fnameescape()->substitute('[ \\]', '\\\0', 'g')->substitute('\V,', '\\\\,', 'g') })->join(',')

    if len(self.global_tags)
	let l:cmd .= ',' . self.global_tags
    endif

    call g:ProjectConfig_AddModuleAutocmd(a:mod, l:cmd)
endfunction
