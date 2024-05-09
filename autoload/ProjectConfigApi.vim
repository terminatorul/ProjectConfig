let g:ProjectConfig_DirectorySeparator = exists('+shellslash') ? '\' : '/'
let s:sep = g:ProjectConfig_DirectorySeparator

" Join multiple path components using the directory separator in
" g:ProjectConfig_DirectorySeparator
function g:ProjectConfig_JoinPath(...)
    return join(a:000, s:sep)
endfunction

let s:Join_Path = funcref('g:ProjectConfig_JoinPath')

let g:ProjectConfig_Generators = [ ]
let s:generators = g:ProjectConfig_Generators

" Element-wise comparison for two lists, returns -1, 0, or 1
function g:ProjectConfig_ListCompare(list1, list2)
    let l:len1 = len(a:list1)
    let l:len2 = len(a:list2)

    if l:len1 < l:len2
	let l:len = l:len1
    else
	let l:len = l:len2
    endif

    let l:index = 0

    while l:index < l:len
	if a:list1[l:index] < a:list2[l:index]
	    return -1
	else
	    if a:list1[l:index] > a:list2[l:index]
		return 1
	    endif
	endif

	let l:index = l:index + 1
    endwhile

    if l:len1 < l:len2
	return -1
    else
	if l:len1 > l:len2
	    return 1
	endif
    endif

    return 0
endfunction

let s:List_Compare = funcref('g:ProjectConfig_ListCompare')

" duplicate values that appear sooner have priority and will be kept over
" values that appear later
function g:ProjectConfig_InPlaceAppendUnique(l1, l2, ...)
    for l:element in [ a:l2 ]->extend(a:000)->flatten(1)
	if a:l1->index(l:element) < 0
	    eval a:l1->add(l:element)
	endif
    endfor

    return a:l1
endfunction

let s:InPlace_Append_Unique = funcref('g:ProjectConfig_InPlaceAppendUnique')

" duplicate values that appear sooner have priority and will be kept over
" values that appear later
function g:ProjectConfig_ListAppendUnique(l1, l2, ...)
    return s:InPlace_Append_Unique->call([ copy(a:l1), a:l2 ]->extend(a:000))
endfunction

let s:List_Append_Unique = funcref('g:ProjectConfig_ListAppendUnique')

" duplicate values that appear sooner in the target list have priority over
" values that appear later. The element order in l2 + ... is otherwise
" preserved
function g:ProjectConfig_InPlacePrependUnique(l1, l2, ...)
    for l:element in [ a:l2 ]->extend(a:000)->flatten(1)->reverse()
	let l:element_index = a:l1->index(l:element)

	if l:element_index >= 0
	    eval a:l1->remove(l:element_index)
	endif

	eval a:l1->insert(l:element)
    endfor

    return a:l1
endfunction

let s:InPlace_Prepend_Unique = funcref('g:ProjectConfig_InPlacePrependUnique')

" duplicate values that appear sooner in the target list have priority over
" values that appear later. The element order in l2 + ... is otherwise
" preserved
function g:ProjectConfig_ListPrependUnique(l1, l2, ...)
    return s:InPlace_Prepend_Unique->call([ copy(l1), l2 ]->extend(a:000))
endfunction

let s:List_Prepend_Unique = funcref('g:ProjectConfig_ListPrependUnique')

function g:ProjectConfig_ExpandModuleSources(project, module)
    let l:source_list = [ ]

    for l:source_glob in a:module.src + a:module.inc
	let l:run_filter = v:true

	if isdirectory(l:source_glob)
	    if a:module.recurse
		let l:source_glob .= '/**'
		let l:run_filter = v:false
	    else
		l:source_glob .= '/*'
	    endif
	endif

	let l:glob_list = l:source_glob->glob(v:true, v:true)

	if l:run_filter
	    eval l:glob_list->filter({ _, val -> !isdirectory(val) })
	endif

	call s:InPlace_Append_Unique(l:source_list, l:glob_list)
    endfor

    return l:source_list
endfunction

let g:ProjectConfig_Modules = { }

if !exists('g:ProjectConfig_CleanPathOption')
    let g:ProjectConfig_CleanPathOption = v:true
endif

function g:ProjectConfig_AddCurrentProject()
    if has_key(g:ProjectConfig_Modules, g:ProjectConfig_Project)
	return
    endif

    let g:ProjectConfig_Modules[g:ProjectConfig_Project] = { 'config': { }, 'modules': { } }

    for l:generator in g:ProjectConfig_Generators
	eval l:generator.AddProject(g:ProjectConfig_Project)
    endfor
endfunction

" Construct and return a new empty project module with given name
function g:ProjectConfig_Module(name, external = v:false)
    let l:module = { 'name': a:name, 'external': a:external }

    for l:scope in [ 'private', 'public', 'interface' ]
	let l:module[l:scope] = { }

	let l:module[l:scope].dir = [ ]
	let l:module[l:scope].src = [ ]
	let l:module[l:scope].inc = [ ]
	let l:module[l:scope].deps = [ ]
    endfor

    return l:module
endfunction

" Add all modules to global g:ProjectConfig_Modules
" and fill in default fields for a module
function g:ProjectConfig_AddModule(module, ...)
    let l:module_list = [ a:module ]->extend(a:000)

    for l:module in l:module_list
	if !has_key(l:module, 'name')
	    echoerr 'Missing module name'
	    return
	endif

	if !has_key(l:module, 'external')
	    let l:module.external = v:false
	endif

	for l:scope_name in [ 'private', 'public', 'interface' ]
	    if !has_key(l:module, l:scope_name)
		let l:module[l:scope_name] = { }
	    endif

	    let l:mod = l:module[l:scope_name]

	    if has_key(l:mod, 'dir')
		if type(l:mod.dir) != v:t_list
		    let l:mod.dir = [ l:mod.dir ]
		endif
	    else
		let l:mod.dir = [ ]
	    endif

	    if has_key(l:mod, 'src')
		if type(l:mod.src) != v:t_list
		    let l:mod.src = [ l:mod.src ]
		endif
	    else
		let l:mod.src = [ ]
	    endif

	    if has_key(l:mod, 'inc')
		if type(l:mod.inc) != v:t_list
		    let l:mod.inc = [ l:mod.inc ]
		endif
	    else
		let l:mod.inc = [ ]
	    endif

	    if has_key(l:mod, 'deps')
		if type(l:mod.deps) != v:t_list
		    let l:mod.deps = [ l:mod.deps ]
		endif
	    else
		let l:mod.deps = [ ]
	    endif
	endfor
    endfor

    for l:generator in g:ProjectConfig_Generators
	eval l:generator.AddModule->call(l:module_list)
    endfor

    call g:ProjectConfig_AddCurrentProject()

    for l:mod in l:module_list
	let g:ProjectConfig_Modules[g:ProjectConfig_Project].modules[l:mod.name] = l:mod
    endfor
endfunction

function g:ProjectConfig_ParsePathOption(value)
    let l:value_list = [ ]
    let l:value_str = ''
    let l:escape_char = v:false

    for l:ch in a:value
	if l:escape_char
	    if l:ch == ' ' || l:ch == '\' || l:ch == ','
		let l:value_str .= l:ch
	    else
		let l:value_str .= '\'
		let l:value_str .= l:ch
	    endif

	    let l:escape_char = v:false
	else
	    if l:ch == '\'
		let l:escape_char = v:true
	    else
		if l:ch == ','
		    eval l:value_list->add(l:value_str)
		    let l:value_str = ''
		else
		    let l:value_str .= l:ch
		endif
	    endif
	endif
    endfor

    eval l:value_list->add(l:value_str)

    return l:value_list
endfunction

function g:ProjectConfig_ShowPath(value = v:none)
    for l:dir in g:ProjectConfig_ParsePathOption(a:value is v:none ? empty(&l:path) ? &g:path : &l:path : a:value)
	echo l:dir
    endfor
endfunction

function g:ProjectConfig_ShellEscape(arg)
    if match(a:arg, '\v^[a-zA-Z0-9_\.\,\+\-\=\#\@\:\\\/]+$') >= 0
	return a:arg
    endif

    " Special case for Windows, when command line argument ends with '\' and
    " also needs to be quoted, because the resulting '\"' at the end actually
    " escapes the double-quote character

    if has('win32') || has('win64')
	let l:len = len(a:arg) - 1

	while l:len >= 0 && a:arg[l:len] == '\'
	    let l:len = l:len - 1
	endwhile

	if l:len >= 0
	    return shellescape(a:arg[0:l:len]) . a:arg[l:len + 1:]
	endif
    endif

    return shellescape(a:arg)
endfunction

let s:Shell_Escape = funcref('g:ProjectConfig_ShellEscape')

function g:ProjectConfig_SetConfigEntry(name, value)
    call g:ProjectConfig_AddCurrentProject()

    let g:ProjectConfig_Modules[g:ProjectConfig_Project].config[a:name] = a:value

    for l:generator in g:ProjectConfig_Generators
	call l:generator.SetConfigEntry(a:name)
    endfor
endfunction

function s:AppendGlobalVimTagsAndPath(generators, module_list, external_modules, mod)
    if a:module_list->index(a:mod.name) < 0
	if !!a:mod.external == !!a:external_modules
	    eval a:module_list->add(a:mod.name)
	endif

	for l:dependency_module in a:mod.private.deps + a:mod['public'].deps + a:mod['interface'].deps
	    if g:ProjectConfig_Modules[g:ProjectConfig_Project].modules->has_key(l:dependency_module)
		let l:dep_mod = g:ProjectConfig_Modules[g:ProjectConfig_Project].modules[l:dependency_module]
		call s:AppendGlobalVimTagsAndPath(a:generators, a:module_list, a:external_modules, l:dep_mod)
	    endif
	endfor

	if !!a:mod.external == !!a:external_modules
	    call mapnew(a:generators, { _, val -> val.UpdateGlobalConfig(a:mod) })	" in-depth traversal for dependency tree
	endif
    endif
endfunction

function s:Module_Inc_And_Tags_List_Per_Level(generators, mod_list, current_depth_level, target_depth_level, external_modules, mod)
    if a:current_depth_level == a:target_depth_level
	if !!a:mod.external == !!a:external_modules && a:mod_list->index(a:mod.name) < 0
	    call mapnew(a:generators, { _, val -> val.UpdateModuleLocalConfig(a:mod) })
	    eval a:mod_list->add(a:mod.name)
	endif

	return v:true
    else
	let l:depth_level_reached = v:false

	for l:dependency_module in a:mod.private.deps + a:mod['public'].deps + a:mod['interface'].deps
	    if g:ProjectConfig_Modules[g:ProjectConfig_Project].modules->has_key(l:dependency_module)
		let l:dep_mod = g:ProjectConfig_Modules[g:ProjectConfig_Project].modules[l:dependency_module]
		let l:level_reached = s:Module_Inc_And_Tags_List_Per_Level(a:generators, a:mod_list, a:current_depth_level + 1, a:target_depth_level, a:external_modules, l:dep_mod)
		let l:depth_level_reached = l:depth_level_reached || l:level_reached
	    endif
	endfor

	return l:depth_level_reached
    endif
endfunction

function s:Module_Inc_And_Tags_List(generators, external_modules, mod)
    let l:depth_level = 0
    let l:mod_list = [ ]

    while s:Module_Inc_And_Tags_List_Per_Level(a:generators, l:mod_list, 0, l:depth_level, a:external_modules, a:mod)
	let l:depth_level = l:depth_level + 1
    endwhile
endfunction

function g:ProjectConfig_AddModuleAutocmd(mod, cmd, pat = [ ])
    let l:auto_cmd = { }
    let l:auto_cmd.group   = g:ProjectConfig_Project
    let l:auto_cmd.event   = a:mod.external ? [ 'BufRead' ] : [ 'BufNewFile', 'BufRead' ]
    let l:auto_cmd.cmd     = a:cmd
    let l:auto_cmd.pattern = a:pat

    if len(a:pat) == 0
	for l:dir in a:mod.private.dir + a:mod['public'].dir
	    eval l:auto_cmd.pattern->add(l:dir->fnamemodify(':p')->substitute('\\', '/', 'g') . '*')
	endfor
    endif

    " echomsg l:auto_cmd

    eval [ l:auto_cmd ]->autocmd_add()
endfunction

function s:SetupLocalVimTagsAndPath(generators, module_list, mod)
    if a:module_list->index(a:mod.name) < 0
	eval a:module_list->add(a:mod.name)

	for l:dependency_module in a:mod.private.deps + a:mod['public'].deps
	    if g:ProjectConfig_Modules[g:ProjectConfig_Project].modules->has_key(l:dependency_module)
		let l:dep_mod = g:ProjectConfig_Modules[g:ProjectConfig_Project].modules[l:dependency_module]
		call s:SetupLocalVimTagsAndPath(a:generators, a:module_list, l:dep_mod)
	    endif
	endfor

	eval a:generators->mapnew({ _, val -> val.LocalConfigInitModule(a:mod) })
	call s:Module_Inc_And_Tags_List(a:generators, v:true, a:mod)
	call s:Module_Inc_And_Tags_List(a:generators, v:false, a:mod)
	eval a:generators->mapnew({ _, val -> val.LocalConfigCompleteModule(a:mod) })
    endif
endfunction

function g:ProjectConfig_EnableVimTags(module, ...)
    let s:generators =
		\ [
		\	copy(g:ProjectConfig_VimPath),
		\	copy(g:ProjectConfig_CTags)
		\ ]

    call mapnew(s:generators, { _, val -> val.LocalConfigInit() })

    let l:module_list = [ ]

    for l:external in [ v:true, v:false ]
	for l:module in [ a:module ] + a:000
	    if g:ProjectConfig_Modules[g:ProjectConfig_Project].modules->has_key(l:module)
		let l:mod = g:ProjectConfig_Modules[g:ProjectConfig_Project].modules[l:module]
		call s:AppendGlobalVimTagsAndPath(s:generators, l:module_list, l:external, l:mod)
	    endif
	endfor
    endfor

    let l:module_list = [ ]

    for l:module in [ a:module ] + a:000
	if g:ProjectConfig_Modules[g:ProjectConfig_Project].modules->has_key(l:module)
	    let l:mod = g:ProjectConfig_Modules[g:ProjectConfig_Project].modules[l:module]
	    call s:SetupLocalVimTagsAndPath(s:generators, l:module_list, l:mod)
	endif
    endfor
endfunction

if has('win16') || has('win32') || has('win64')
    let g:ProjectConfig_DevNull = 'NUL'
else
    let g:ProjectConfig_DevNull = '/dev/null'
endif

