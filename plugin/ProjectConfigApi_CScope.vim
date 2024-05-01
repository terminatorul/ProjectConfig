
let g:ProjectConfig_CScope = { }

let g:ProjectConfig_CScopeBuildOptions = [ '-q' ]   " '-b' is always used (hard-coded)
let g:ProjectConfig_CScopeLookupOptions = [ ]

let s:Join_Path = funcref('g:ProjectConfig_JoinPath')
let s:Shell_Escape = funcref('g:ProjectConfig_ShellEscape')

" From https://sourceforge.net/p/cscope/cscope/ci/master/tree/src/dir.c#l519
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

if !exists('g:ProjectConfig_CScope_Directory')
    let g:ProjectConfig_CScope_Directory = '.cscope'
endif

function s:EmptyFunction()
endfunction

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

    let s:Expand_CScope_Command = funcref('s:EmptyFunction')
endfunction

" Populate s:ProjectConfig_CScope_Path and s:ProjectConfig_CScope_Options
let s:Expand_CScope_Command = funcref('s:Expand_CScope_Command_Line')

let s:List_Append_Unique = funcref('g:ProjectConfig_ListAppendUnique')

function s:CScope_Source_Filter(module)
    if has_key(module, 'cscope_glob')
	let l:filters = mapnew(module.cscope_glob, { _, val -> val->glob2regpat() })
    else
	let l:filters = mapnew(g:ProjectConfig_CScopeDefaultGlob, { _, val -> val->glob2regpat() })
    endif

    if has_key(module, 'cscope_regexp')
	l:filters->extend(module.cscope_regexp)
    endif

    return l:filters
endfunction

function s:Apply_Filters(list, filters)
    let l:match_list = [ ]

    for l:filter in a:filters
	for l:idx in mapnew(matchstrlist(a:list, l:filter), { _, val -> val.idx })->sort('n')->reverse()
	    l:match_list->add(a:list->remove(l:idx))
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
		let l:source_glob .= '/**'
		let l:run_filter = v:false
	    else
		let l:source_glob .= '/*'
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

function s:Build_CScope_Database(project, module)
    let l:project = g:ProjectConfig_Modules[a:project]
    let l:mod = l:project.modules[a:module]
    let l:basename =  l:mod['cscope'].db
    let l:cscope_dir = fnamemodify(l:basename, ':h')

    call mkdir(l:cscope_dir, 'p')

    if match(l:basename, '\.out$') > 0
	let l:basename = l:basename[:-5]
    endif

    let l:inputfile = l:basename . '.files'
    let l:cscope_command = [ s:ProjectConfig_CScope_Path ] + s:ProjectConfig_CScopeOptions
		\ + l:project.config['cscope'].build_args + l:mod['cscope'].build_args
		\ + [ '-b', '-i', s:Shell_Escape(l:inputfile), '-f', s:Shell_Escape(l:mod['cscope'].db) ]

    cscope kill `=fnameescape(l:mod['cscope'].db)`

    execute '!' . l:cscope_command->join(' ')

    if v:shell_error
	echoerr 'Error generating cscope database ' . l:mod['cscope'].db . ' for module ' . l:mod.name
		    \ . ': shell command exited with code ' . v:shell_error
    else
	cscope add `=fnameescape(l:mod['cscope'].db)`
    endif
endfunction
