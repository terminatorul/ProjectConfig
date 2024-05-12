
let g:ProjectConfig_CScope = { }

let g:ProjectConfig_CScopeBuildOptions = [ '-q' ]   " '-b' is always used (hard-coded)
let g:ProjectConfig_CScopeLookupOptions = [ ]

let s:Join_Path = funcref(g:ProjectConfig_JoinPath)
let s:Shell_Escape = funcref(g:ProjectConfig_ShellEscape)

" List of default source file extensions, from cscope source code at:
"   https://sourceforge.net/p/cscope/cscope/ci/master/tree/src/dir.c#l519
"
"   *.bp   breakpoint listing
"   *.ch   Ingres
"   *.sd   SDL
"   *.tcc  C++ template source file
"
if !exists('g:ProjectConfig_CScopeDefaultGlob')
    let g:ProjectConfig_CScopeDefaultGlob =
	\ [
	\	'.[chlyCGHL]',
	\	'.bp',
	\	'.ch',
	\	'.sd',
	\	'.cc',
	\	'.hh',
	\	'.tcc',
	\	'.[ch]pp',
	\	'.[ch]xx'
	\ ]
	\	->mapnew({ _, val -> '**/*' . val })
endif

function s:AddCurrentProject()
    let l:project = g:ProjectConfig_Modules[g:ProjectConfig_Project]

    if !has_key(l:project, 'cscope_args')
	let l:project['cscope_args'] = [ ]
    endif

    if type(l:project.cscope_args) != v:t_list
	let l:project.cscope_args = [ l:project.cscope_args ]
    endif
endfunction

function s:SetConfigEntry(name)
    if a:name == 'cscope_args'
endfunction

if !exists('g:ProjectConfig_CScope_Directory')
    let g:ProjectConfig_CScope_Directory = '.projectConfig'
endif

function s:Expand_CScope_Command_Line()
    if exists('g:ProjectConfig_CScope_Executable')
	if type(g:ProjectConfig_CScope_Executable) == v:t_list
	    let s:ProjectConfig_CScope_Path = exepath(g:ProjectConfig_CScope_Executable[0])
	    let s:ProjectConfig_CScope_Options = g:ProjectConfig_CScope_Executable[1:]
	else
	    let s:ProjectConfig_CScope_Path = exepath(g:ProjectConfig_CScope_Executable)
	    let s:ProjectConfig_CScope_Options = [ ]
	endif
    else
	let s:ProjectConfig_CScope_Path = exepath(&cscopeprg)
	let s:ProjectConfig_CScope_Options = [ ]
    endif

    if exists('g:ProjectConfig_CScope_Options')
	call s:ProjectConfig_CScope_Options->extend(g:ProjectConfig_CScope_Options)
    endif

    let s:ProjectConfig_CScope_Path = s:Shell_Escape(s:ProjectConfig_CScope_Path)
    call map(s:ProjectConfig_CScope_Options, { key, val -> s:Shell_Escape(val) })

    let s:Expand_CScope_Command = { -> 0 }
endfunction

" Populate s:ProjectConfig_CScope_Path and s:ProjectConfig_CScope_Options
let s:Expand_CScope_Command = funcref('s:Expand_CScope_Command_Line')

let s:List_Append_Unique = funcref(g:ProjectConfig_ListAppendUnique)

function s:CScope_Source_Filter(module)
    if has_key(module.cscope, 'glob')
	let l:filters = mapnew(module.cscope.glob, { _, val -> val->glob2regpat() })
    else
	let l:filters = mapnew(g:ProjectConfig_CScopeDefaultGlob, { _, val -> val->glob2regpat() })
    endif

    if has_key(module.cscope, 'regexp')
	l:filters->extend(module.cscope.regexp)
    endif

    return l:filters
endfunction

function s:Apply_Filters(list, filters)
    let l:match_list = [ ]

    for l:filter in a:filters
	for l:idx in mapnew(matchstrlist(a:list, l:filter), { _, val -> val.idx })->sort('n')->reverse()
	    eval l:match_list->add(a:list->remove(l:idx))
	endfor

	if !a:list->len()
	    break
	endif
    endfor

    return l:match_list
endfunction

function s:Expand_CScope_Sources(module)
    let l:source_list = [ ]
    let l:source_filters = s:CScope_Source_Filter(module)

    for l:source_glob in a:module.src + a:module.inc
	let l:run_filter = v:true

	if isdirectory(l:source_glob)
	    if a:module.recurse
		let l:source_glob ..= '/**'
		let l:run_filter = v:false
	    else
		let l:source_glob ..= '/*'
	    endif
	endif

	let l:glob_list = l:source_glob->glob(v:true, v:true)
	let l:file_list = s:Apply_Filters(l:glob_list, l:source_filters)

	if l:run_filter
	    eval l:file_list->filter({ _, val -> !isdirectory(val) })
	endif

	let l:source_list = s:List_Append_Unique(l:source_list, s:Apply_Filters(l:file_list, l:source_filters))
    endfor

    return l:source_list
endfunction

function s:Build_CScope_Database(project, module, connections)
    let l:basename =  a:mod['cscope'].db
    let l:cscope_dir = fnamemodify(l:basename, ':h')

    call mkdir(l:cscope_dir, 'p')

    if match(l:basename, '\.out$') > 0
	let l:basename = l:basename[:-5]
    endif

    let l:inputfile = l:basename . '.files'
    let l:cscope_command = [ s:ProjectConfig_CScope_Path ] + s:ProjectConfig_CScopeOptions
		\ + a:project.config['cscope'].build_args + a:mod['cscope'].build_args
		\ + [ '-b', '-i', s:Shell_Escape(l:inputfile), '-f', s:Shell_Escape(a:mod['cscope'].db) ]

    let l:reset_connection = stridx(l:connections, a:mod['cscope'].db) >= 0 ? v:true : v:false

    if l:reset_connection && (has('win32') || has('win64'))
	" On Windows can not rebuild the cscope database while in use in Vim,
	" presumably cygwin and msys/mingw as well
	cscope kill `=fnameescape(a:mod['cscope'].db)`
    endif

    execute '!' . l:cscope_command->join(' ')

    if v:shell_error
	echoerr 'Error generating cscope database ' . a:mod['cscope'].db . ' for module ' . a:mod.name
		    \ . ': shell command exited with code ' . v:shell_error
    else
	if has('win32') || has('win64') || !l:reset_connection
	    cscope add `=fnameescape(a:mod['cscope'].db)`	    " this changes order of connections on Windows
	endif
    endif
endfunction

function s:Build_CScope_Database_By_Depth(current_depth, target_depth, project, module, external, connections, module_list)
    if a:current_depth == a:target_depth
	if a:external == a:module.external
	    if !empty(mod.cscope) && index(a:module_list, a:module.name) < 0
		call s:Build_CScope_Database(project, module, connections)
		eval a:module_list->add(a:module.name)
	    endif
	endif

	return v:true
    endif

    let l:target_depth_reached = v:false

    for l:submodule_name in module.deps
	if has_key(a:project.modules, l:submodule_name)
	    let l:depth_reached = s:Build_CScope_Database_By_Depth
			\ (
			\   current_depth + 1,
			\   target_depth,
			\   project,
			\   a:project.modules[l:submodule_name],
			\   external,
			\   connections
			\ )

	    if l:depth_reached && !l:target_depth_reached
		let l:target_depth_reached = v:true
	    endif
	endif
    endfor

    return l:target_depth_reached
endfunction

function s:Module_Tree_Depth_Traversal(connections, module_list, external, project_name, module_name, module_names)
    if has_key(g:ProjectConfig_Modules, a:project_name)
	call s:Expand_CScope_Command()

	let l:project = g:ProjectConfig_Modules[a:project_name]
	let l:depth_level = 0
	let l:depth_level_reached = v:true

	while l:depth_level_reached
	    let l:depth_level_reached = v:false
	    let l:depth_level += 1

	    for l:module_name in [ a:module_name ] + a:module_names
		if has_key(l:project.modules, l:module_name)
		    let l:depth_reached = s:Build_CScope_Database_By_Depth
				\ (
				\   1,
				\   l:depth_level,
				\   l:project,
				\   l:project.modules[l:module_name],
				\   a:external,
				\   a:connections,
				\   a:module_list
				\ )
		    if l:depth_reached && !l:depth_level_reached
			let l:depth_level_reached = v:true
		    endif
		endif
	    endfor
	endwhile
    endif
endfunction

function g:ProjectConfig_BuildCScopeDatabase(project, module, ...)
    let l:connections = 'cscope show'->execute()
    let l:module_list = [ ]

    call s:Module_Tree_Depth_Traversal(l:connections, l:module_list, v:false, a:project, a:module, a:000)

    if !has('win32') && !has('win64')
	cscope reset
    endif
endfunction

function g:ProjectConfig_BuildAllCScopeDatabase(project, module, ...)
    let l:connections = 'cscope show'->execute()
    let l:module_list = [ ]

    call s:Module_Tree_Depth_Traversal(l:connections, l:module_list, v:false, a:project, a:module, a:000)
    call s:Module_Tree_Depth_Traversal(l:connections, l:module_list, v:true, a:project, a:module, a:000)

    if !has('win32') && !has('win64')
	cscope reset
    endif
endfunction

" eval g:ProjectConfig_Generators->add(g:ProjectConfig_CScope)
