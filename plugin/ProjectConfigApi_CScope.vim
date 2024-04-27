
let g:ProjectConfig_CScope = { }

let g:ProjectConfig_CScopeOptions = [ '-q' ]

let s:Join_Path = funcref('g:ProjectConfig_JoinPath')
let s:Shell_Escape = funcref('g:ProjectConfig_ShellEscape')

" From https://sourceforge.net/p/cscope/cscope/ci/master/tree/src/dir.c#l519
"
"   *.bp breakpoint listing
"   *.ch Ingres
"   *.sd SDL
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

