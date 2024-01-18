let g:ProjectConfig_DirectorySeparator = exists('&shellslash') ? '\' : '/'
let s:sep = g:ProjectConfig_DirectorySeparator

" Join multiple path components using the directory separator in
" g:ProjectConfig_DirectorySeprator
function g:ProjectConfig_JoinPath(...)
    return join(a:000, s:sep)
endfunction

let s:Join_Path = funcref('g:ProjectConfig_JoinPath')

" Element-wize comparison for two lists, returns -1, 0, or 1
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

function s:Sort_Version_Dir(Dir_List)
    let l:sort_list = [ ]

    for l:dir in a:Dir_List
	let l:version_string = fnamemodify(l:dir, ':t')

	if match(l:version_string, '\v^[0-9]+(\.[0-9]+)*$') >= 0	" only version numbers, of the form 23.10938.24.02
	    call add(l:sort_list, [ mapnew(split(l:version_string, '\.'), { key, val -> str2nr(val) }), l:dir ])
	endif
    endfor

    call sort(l:sort_list, { v1, v2 -> s:List_Compare(v1[0], v2[0]) })

    return mapnew(l:sort_list, { key, val -> val[1] })
endfunction

function s:MSVC_Tools_Directory(Release, Product, Tools_Version)
    " glob() path 'C:/Program Files/Microsoft Visual Studio/*/*/VC/Tools/MSVC/*/'

    let l:envvar = has('win64') ? 'ProgramFiles' : 'ProgramW6432'
    let l:vs_dir = glob(s:Join_Path(getenv(l:envvar), 'Microsoft Visual Studio', a:Release), v:true, v:true)

    if len(l:vs_dir)
	let l:vs_dir = s:Sort_Version_Dir(l:vs_dir)[-1]	    " Try choosing latest release (currently 2022)
    else
	return [ ]					    " Visual Studio directory not found
    endif

    let l:vs_dir = glob(s:Join_Path(l:vs_dir, a:Product), v:true, v:true)

    if len(l:vs_dir)
	let l:vs_dir = sort(l:vs_dir)[0]		    " 'Community' will sort before 'Enterprise', 'Professional'
    else
	return [ ]					    " Visual Studio directory not found
    endif

    let l:vs_dir = glob(s:Join_Path(l:vs_dir, 'VC', 'Tools', 'MSVC', a:Tools_Version), v:true, v:true)

    if len(l:vs_dir)
	let l:vs_dir = s:Sort_Version_Dir(l:vs_dir)[-1]   " Try choosing latest tools version eg. 14.38.33130
    else
	return [ ]
    endif

    return [ l:vs_dir ]
endfunction

function s:SDK_Include_Directory(Platform_Version, Version)
    let l:envvar = has('win64') ? 'ProgramFiles(x86)' : 'ProgramFiles'
    let l:sdk_dir = glob(s:Join_Path(getenv(l:envvar), 'Windows Kits', a:Platform_Version), v:true, v:true)

    if len(l:sdk_dir)
	let l:sdk_dir = s:Sort_Version_Dir(l:sdk_dir)[-1]
    else
	return [ ]
    endif

    let l:sdk_dir = glob(s:Join_Path(l:sdk_dir, 'Include', a:Version), v:true, v:true)

    if len(l:sdk_dir)
	let l:sdk_dir = s:Sort_Version_Dir(l:sdk_dir)[-1]
    else
	return [ ]
    endif

    return [ l:sdk_dir ]
endfunction

const g:ProjectConfig_DefaultSDKVersion =
	    \#{
	    \	VS:  #{ Release: '*', Product: '*', Tools_Version: '*' },
	    \	SDK: #{ Platform_Version: '[0-9]*', Version: '*' }
	    \ }

" Populates a module for Windows SDK headers and Windows Universal CRT (C Run-Time)
" library headers
function g:ProjectConfig_MS_SDK_UCRT_Module(version = g:ProjectConfig_DefaultSDKVersion)
    if has_key(a:version, 'VS')
	let l:VS_Release = has_key(a:version.VS, 'Release') ? a:version.VS.Release : '*'
	let l:VS_Product = has_key(a:version.VS, 'Product') ? a:version.VS.Product : '*'
	let l:VS_Tools_Ver = has_key(a:version.VS, 'Tools_Version') ? a:version.VS.Tools_Version : '*'
    else
	let l:VS_Release =  '*'
	let l:VS_Product =  '*'
	let l:VS_Tools_Ver =  '*'
    endif

    if has_key(a:version, 'SDK')
	let l:SDK_Platform_Ver = has_key(a:version.SDK, 'Platform_Version') ? a:version.SDK.Platform_Version : '[0-9]*'
	let l:SDK_Ver = has_key(a:version.SDK, 'Version') ? a:version.SDK.Version : '*'
    else
	let l:SDK_Platform_Ver = '[0-9]*'
	let l:SDK_Ver = '*'
    endif

    let l:SDK_UCRT = { }
    let l:SDK_UCRT.name = 'SDK-UCRT'

    let l:SDK_UCRT.dir = s:MSVC_Tools_Directory(l:VS_Release, l:VS_Product, l:VS_Tools_Ver) + s:SDK_Include_Directory(l:SDK_Platform_Ver, l:SDK_Ver)

    if len(l:SDK_UCRT.dir) == 2
	let l:SDK_UCRT.inc = glob(s:Join_Path(l:SDK_UCRT.dir[0], 'include'), v:true, v:true)

	let l:auto_cmd = { }
	let l:auto_cmd.group = g:ProjectConfig_Project
	let l:auto_cmd.event = [ 'BufRead' ]
	let l:auto_cmd.pattern = l:SDK_UCRT.inc[0]->fnamemodify(':p:gs?\\?/?') . '*'
	let l:auto_cmd.cmd = 'if fnamemodify("%", ":e") == "" | setlocal filetype=cpp | endif'

	eval [ l:auto_cmd ]->autocmd_add()

	for inc in [ 'ucrt', 'shared', 'um', 'winrt', 'cppwinrt' ]
	    call extend(l:SDK_UCRT.inc,  glob(s:Join_Path(l:SDK_UCRT.dir[1], inc), v:true, v:true))
	endfor
    endif

    let l:SDK_UCRT.ctags_args = [ '--recurse', '--languages=+C,C++', '--map-C++=+.', '--kinds-C=+px', '--kinds-C++=+px' ]
    eval l:SDK_UCRT.ctags_args->extend([ '-D_EXPORT_STD=export', '-D_CONSTEXPR20=constexpr', '-D_STD=::std::', '-D_NODISCARD_=' ])
    eval l:SDK_UCRT.ctags_args->extend([ '-D_STD_BEGIN=namespace std {', '-D_STD_END=}', '-D_STDEXT_BEGIN=namespace stdext {', '-D_STDEXT_END=}' ])
    eval l:SDK_UCRT.ctags_args->extend([ '-D_STDEXT=::stdext::', '-D_CSTD=::', '-D_CHRONO=::std::chrono::', '-D_RANGES=::std::ranges::' ])
    eval l:SDK_UCRT.ctags_args->extend([ '-D_EXTERN_C=', '-D_HAS_CXX17', '-D_HAS_CXX20', '-D_HAS_CXX23', '-D_CONSTEXPR23=constexpr' ])
    eval l:SDK_UCRT.ctags_args->extend([ '-D_INLINE_VAR=inline', '-D__CLR_OR_THIS_CALL=', '-D__CLRCALL_OR_CDECL=', '-D_VCRT_NOALIAS=', '-D_VCRT_RESTRICT=' ])
    eval l:SDK_UCRT.ctags_args->extend([ '-D_CRT_BEGIN_C_HEADER=', '-D_CRT_END_C_HEADER=', '-D_MSVC_CONSTEXPR=constexpr'])
    let l:SDK_UCRT.external = v:true

    return l:SDK_UCRT
endfunction

let g:ProjectConfig_Modules = { }

if !exists('g:ProjectConfig_Tags_Directory')
    let g:ProjectConfig_Tags_Directory = '.tags'
endif

function g:ProjectConfig_AddCurrentProject()
    if !has_key(g:ProjectConfig_Modules, g:ProjectConfig_Project)
	let g:ProjectConfig_Modules[g:ProjectConfig_Project] = #{ config: #{ ctags_args: [ ] }, modules: { } }
    endif
endfunction

" Use to add all modules to global g:ProjectConfig_Modules
" and fill in default fields for a module
function g:ProjectConfig_AddModule(mod)
    if !has_key(a:mod, 'name')
	echoerr 'Missing module name'
	return
    endif

    if has_key(a:mod, 'dir')
	if type(a:mod.dir) != v:t_list
	    let a:mod.dir = [ a:mod.dir ]
	endif
    else
	let a:mod.dir = [ ]
    endif

    if has_key(a:mod, 'src')
	if type(a:mod.src) != v:t_list
	    let a:mod.src = [ a:mod.src ]
	endif
    else
	let a:mod.src = [ ]
    endif

    if has_key(a:mod, 'inc')
	if type(a:mod.inc) != v:t_list
	    let a:mod.inc = [ a:mod.inc ]
	endif
    else
	let a:mod.inc = [ ]
    endif

    if has_key(a:mod, 'ctags_args')
	if type(a:mod.ctags_args) != v:t_list
	    let a:mod.ctags_args = [ a:mod.ctags_args ]
	endif

	call map(a:mod.ctags_args, { key, val -> s:Shell_Escape(val) })
    else
	let a:mod.ctags_args = [ ]
    endif

    if has_key(a:mod, 'deps')
	if type(a:mod.deps) != v:t_list
	    let a:mod.deps = [ a:mod.deps ]
	endif
    else
	let a:mod.deps = [ ]
    endif

    if !has_key(a:mod, 'tags')
	let a:mod.tags = s:Join_Path(g:ProjectConfig_Directory, g:ProjectConfig_Tags_Directory, a:mod.name . '.tags')
    endif

    if !has_key(a:mod, 'external')
	let a:mod.external = v:false
    endif

    call g:ProjectConfig_AddCurrentProject()

    let g:ProjectConfig_Modules[g:ProjectConfig_Project].modules[a:mod.name] = a:mod
endfunction

let g:ProjectConfig_CTagsCxxOptions =
    \[
    \	'--recurse', '--languages=+C,C++', '--kinds-C=+px', '--kinds-C++=+px',
    \   '--fields=+lzkKErSt', '--extras=+{qualified}{inputFile}', '--totals'
    \]

if has('win32') || has('win64')
    eval g:ProjectConfig_CTagsCxxOptions->extend([ '-D_M_AMD64', '-D_WINDOWS', '-D_MBCS', '-D_WIN64', '-D_WIN32', '-D_MSC_VER=1933', '-D_MSC_FULL_VER=193331630'])
endif

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

    if a:name == 'ctags_args'
	if type(g:ProjectConfig_Modules[g:ProjectConfig_Project].config[a:name]) != v:t_list
	    let g:ProjectConfig_Modules[g:ProjectConfig_Project].config[a:name] = [ g:ProjectConfig_Modules[g:ProjectConfig_Project].config[a:name] ]
	endif

	call map(g:ProjectConfig_Modules[g:ProjectConfig_Project].config[a:name], { key, val -> s:Shell_Escape(val) })
    endif
endfunction

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

function s:AppendGlobalVimTags(module_list, external_modules, mod)
    if a:module_list->index(a:mod.name) < 0
	for l:dependency_module in a:mod.deps
	    if g:ProjectConfig_Modules[g:ProjectConfig_Project].modules->has_key(l:dependency_module)
		let l:dep_mod = g:ProjectConfig_Modules[g:ProjectConfig_Project].modules[l:dependency_module]
		call s:AppendGlobalVimTags(a:module_list, a:external_modules, l:dep_mod)
	    endif
	endfor

	if !!a:mod.external == !!a:external_modules
	    execute 'set tags ^=' . a:mod.tags->fnameescape()->substitute('\V,', '\\\\\\,', 'g')
	    eval a:module_list->add(a:mod.name)
	endif
    endif
endfunction

function s:Module_Tags_List_Per_Level(tags_list, current_depth_level, target_depth_level, external_modules, mod)
    if a:current_depth_level == a:target_depth_level
	if !!a:mod.external == !!a:external_modules && a:tags_list->index(a:mod.name) < 0
	    eval a:tags_list->add(a:mod.tags)
	endif

	return v:true
    else
	let l:depth_level_reached = v:false

	for l:dependency_module in a:mod.deps
	    if g:ProjectConfig_Modules[g:ProjectConfig_Project].modules->has_key(l:dependency_module)
		let l:dep_mod = g:ProjectConfig_Modules[g:ProjectConfig_Project].modules[l:dependency_module]
		let l:level_reached = s:Module_Tags_List_Per_Level(a:tags_list, a:current_depth_level + 1, a:target_depth_level, a:external_modules, l:dep_mod)
		let l:depth_level_reached = l:depth_level_reached && l:level_reached
	    endif
	endfor

	return l:depth_level_reached
    endif
endfunction

function s:Module_Tags_List(external_modules, mod)
    let l:depth_level = 0
    let l:tags_list = [ ]

    while s:Module_Tags_List_Per_Level(l:tags_list, 0, l:depth_level, a:external_modules, a:mod)
	let l:depth_level = l:depth_level + 1
    endwhile

    return l:tags_list
endfunction

function s:SetupLocalVimTags(module_list, mod)
    if a:module_list->index(a:mod.name) < 0
	for l:dependency_module in a:mod.deps
	    if g:ProjectConfig_Modules[g:ProjectConfig_Project].modules->has_key(l:dependency_module)
		let l:dep_mod = g:ProjectConfig_Modules[g:ProjectConfig_Project].modules[l:dependency_module]
		call s:SetupLocalVimTags(a:module_list, l:dep_mod)
	    endif
	endfor

	let l:tags_list = s:Module_Tags_List(v:false, a:mod) + s:Module_Tags_List(v:true, a:mod)

	let l:auto_cmd = { }
	let l:auto_cmd.group = g:ProjectConfig_Project
	let l:auto_cmd.event = a:mod.external ? [ 'BufRead' ] : [ 'BufNewFile', 'BufRead' ]
	let l:auto_cmd.cmd = 'setlocal tags =' . l:tags_list->mapnew({ key, val -> val->fnameescape()->substitute('\V,', '\\\\\\,', 'g') })->join(',')

	if len(g:ProjectConfig_Modules[g:ProjectConfig_Project].config['orig_tags'])
	    let l:auto_cmd.cmd .= ',' . g:ProjectConfig_Modules[g:ProjectConfig_Project].config['orig_tags']
	endif

	let l:auto_cmd.pattern = [ ]

	for l:dir in a:mod.dir
	    eval l:auto_cmd.pattern->add(l:dir->fnamemodify(':p')->substitute('\\', '/', 'g') . '*')
	endfor

	" echomsg l:auto_cmd

	eval [ l:auto_cmd ]->autocmd_add()
	eval a:module_list->add(a:mod.name)
    endif
endfunction

function g:ProjectConfig_EnableVimTags(module, ...)
    let g:ProjectConfig_Modules[g:ProjectConfig_Project].config['orig_tags'] = &tags
    let l:module_list = [ ]

    for l:module in [ a:module ] + a:000
	if g:ProjectConfig_Modules[g:ProjectConfig_Project].modules->has_key(l:module)
	    let l:mod = g:ProjectConfig_Modules[g:ProjectConfig_Project].modules[l:module]
	    call s:AppendGlobalVimTags(l:module_list, v:true, l:mod)
	endif
    endfor

    for l:module in [ a:module ] + a:000
	if g:ProjectConfig_Modules[g:ProjectConfig_Project].modules->has_key(l:module)
	    let l:mod = g:ProjectConfig_Modules[g:ProjectConfig_Project].modules[l:module]
	    call s:AppendGlobalVimTags(l:module_list, v:false, l:mod)
	endif
    endfor

    let l:module_list = [ ]

    for l:module in [ a:module ] + a:000
	if g:ProjectConfig_Modules[g:ProjectConfig_Project].modules->has_key(l:module)
	    let l:mod = g:ProjectConfig_Modules[g:ProjectConfig_Project].modules[l:module]
	    call s:SetupLocalVimTags(l:module_list, l:mod)
	endif
    endfor
endfunction
