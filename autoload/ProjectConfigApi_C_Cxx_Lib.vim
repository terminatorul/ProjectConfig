
function g:ProjectConfig_CollectModuleIncludes(project, module, ...)
    let l:tree_depth = 0

    for l:module_node in [ a:module] + a:000
	let l:subtree_depth = s:ModuleTreeDepth(a:project, l:module_node)

	if l:subtree_depth > l:tree_depth
	    let l:tree_depth = l:subtree_depth
	endif
    endfor

    let l:includes = a:module.if_inc

    eval l:includes->extend(a:is_toplevel || a:module.external ? a:module.inc : [ ])
endfunction

function s:Sort_Version_Dir(Dir_List)
    let l:sort_list = [ ]

    for l:dir in a:Dir_List
	let l:version_string = fnamemodify(l:dir, ':t')

	if match(l:version_string, '\v^[0-9]+(\.[0-9]+)*$') >= 0	" only version numbers, of the form 23.10938.24.02
	    call add(l:sort_list, [ mapnew(split(l:version_string, '\.'), { _, val -> str2nr(val) }), l:dir ])
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
	let l:vs_dir = s:Sort_Version_Dir(l:vs_dir)[-1]     " Try choosing latest tools version eg. 14.38.33130
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
	    \ {
	    \	'VS':  { 'Release': '*', 'Product': '*', 'Tools_Version': '*' },
	    \	'SDK': { 'Platform_Version': '[0-9]*', 'Version': '*' }
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

	for l:inc in [ 'ucrt', 'shared', 'um', 'winrt', 'cppwinrt' ]
	    call extend(l:SDK_UCRT.inc,  glob(s:Join_Path(l:SDK_UCRT.dir[1], l:inc), v:true, v:true))
	endfor
    endif

    let l:SDK_UCRT.ctags_args = [ '--recurse', '--languages=+C,C++', '--map-C++=+.', '--kinds-C=+px', '--kinds-C++=+px' ]
    eval l:SDK_UCRT.ctags_args->extend([ '-D_EXPORT_STD=export', '-D_CONSTEXPR20=constexpr', '-D_STD=::std::', '-D_NODISCARD_=', '-D_NODISCARD=' ])
    eval l:SDK_UCRT.ctags_args->extend([ '-D_STD_BEGIN=namespace std {', '-D_STD_END=}', '-D_STDEXT_BEGIN=namespace stdext {', '-D_STDEXT_END=}' ])
    eval l:SDK_UCRT.ctags_args->extend([ '-D_STDEXT=::stdext::', '-D_CSTD=::', '-D_CHRONO=::std::chrono::', '-D_RANGES=::std::ranges::' ])
    eval l:SDK_UCRT.ctags_args->extend([ '-D_EXTERN_C=', '-D_HAS_CXX17', '-D_HAS_CXX20', '-D_HAS_CXX23', '-D_CONSTEXPR23=constexpr' ])
    eval l:SDK_UCRT.ctags_args->extend([ '-D_INLINE_VAR=inline', '-D__CLR_OR_THIS_CALL=', '-D__CLRCALL_OR_CDECL=', '-D_VCRT_NOALIAS=', '-D_VCRT_RESTRICT=', '-D_VCRTIMP=' ])
    eval l:SDK_UCRT.ctags_args->extend([ '-D_CRT_BEGIN_C_HEADER=', '-D_CRT_END_C_HEADER=', '-D_MSVC_CONSTEXPR=constexpr'])
    eval l:SDK_UCRT.ctags_args->extend([ '-D_CRTIMP2_IMPORT=', '-D_CRTIMP2_PURE_IMPORT=', '-D_CRTDATA2_IMPORT='])
    eval l:SDK_UCRT.ctags_args->extend([ '-DDEFINE_DEVPROPKEY(name, ...)=const DEVPROPKEY name { ... }'])

    let l:SDK_UCRT.external = v:true

    " 	"-include" "vcruntime_string.h"
    "
    "  Internal Microsoft preprocessor SAL (Source Annotation Language)
    " 	"-D__ANNOTATION(...)="
    " 	"-D__PRIMOP(...)="
    " 	"-D__QUALIFIER(...)="
    " 	"-D__MACHINE(...)="
    " 	"-D_Return_type_success_(...)="
    " 	"-D_SAL2_Source_(...)="
    " 	"-D_Function_class_(...)="
    " 	"-D_IRQL_requires_max_(...)="
    " 	"-D_Field_size_bytes_opt_(...)="
    " 	"-D_In_reads_bytes_(...)="
    " 	"-D_Inout_updates_bytes(...)="
    " 	"-D_In_range_(...)="
    "
    " 	"-D_Null_terminated_="
    " 	"-D_NullNull_terminated_="
    " 	"-D_In_="
    " 	"_D_Out_="
    " 	"-D_Inout_="
    " 	"-D__In_impl_="
    " 	"-D__deferTypecheck="
    " 	"-D_Must_inspect_result_="
    " 	"-D_Check_return_"
    " 	"-D_IRQL_requires_same_="
    " 	"-D_Interlocked_operand_="
    " 	"-D_USE_ATTRIBUTES_FOR_SAL=0"
    " 	"-D_USE_DECLSPECS_FOR_SAL=0"
    "
    "	"-DDEFINE_DEVPROPKEY(name, ...)=const DEVPROPKEY name { ... }"
    return l:SDK_UCRT
endfunction

if !exists('g:ProjectConfig_GCC_ShowSpecArgs')
    let g:ProjectConfig_GCC_ShowSpecArgs = [ '-v', '-dM', '-E', '-x' ]
endif

if !exists('g:ProjectConfig_GCC_compiler')
    let g:ProjectConfig_GCC_compiler = [ 'gcc' ]
endif

function s:ProjectConfig_GetGnuCompiler()
    return g:ProjectConfig_GCC_compiler
endfunction

function s:ProjectConfig_LocateGnuCompiler()
    if type(g:ProjectConfig_GCC_compiler) != v:t_list
	let g:ProjectConfig_GCC_compiler = [ g:ProjectConfig_GCC_compiler ]
    endif

    let l:compiler_exe = exepath(g:ProjectConfig_GCC_compiler[0])

    if !empty(l:compiler_exe)
	let g:ProjectConfig_GCC_compiler = [ l:compiler_exe ] + g:ProjectConfig_GCC_compiler[1:]

	let g:ProjectConfig_GnuCompiler = funcref('s:ProjectConfig_GetGnuCompiler')
    endif

    return g:ProjectConfig_GCC_compiler
endfunction

let g:ProjectConfig_GnuCompiler = funcref('s:ProjectConfig_LocateGnuCompiler')

function g:ProjectConfig_Read_gcc_specs(language = 'c', compiler_exe = v:null, compiler_args = [ ])
    if empty(a:compiler_exe)
	let l:compiler_exe = g:ProjectConfig_GnuCompiler()
    else
	if type(a:compiler_exe) == v:t_list
	    let l:compiler_exe = a:compiler_exe
	else
	    let l:compiler_exe = [ a:compiler_exe ]
	endif
    endif

    let l:output_list = (l:compiler_exe + a:compiler_args + g:ProjectConfig_GCC_ShowSpecArgs + [ a:language, g:ProjectConfig_DevNull ])
		\ ->mapnew({ _, val -> s:Shell_Escape(val) })->join(' ')->systemlist()

    let l:idx = -1

    for [l:i, l:line] in l:output_list->items()
	if stridx(l:line, '#include "..."') >= 0
	    let l:idx = l:i
	    break
	endif
    endfor

    let l:include_path = [ ]

    if l:idx >= 0
	let l:idx += 1

	while l:idx < len(l:output_list) && len(l:output_list[l:idx]) > 0
		    \ && (l:output_list[l:idx][0] == ' ' || stridx(l:output_list[l:idx], '#include <...>') >= 0)
	    if l:output_list[l:idx][0] == ' ' " && l:output_path[l:idx] != '/usr/local/include'
		eval l:include_path->add(l:output_list[l:idx][1:])
	    endif

	    let l:idx += 1
	endwhile
    endif

    let l:macro_defs = { }

    for l:line in l:output_list
	let l:matches = l:line->matchlist('\v^\C\s*#\s*define\s+(\h\w*(\(\s*(\h\w*\s*(\,\s*\h\w*\s*)*)?\))?)(\s+(.*))?$')

	if !empty(l:matches)
	    let l:macro_defs[l:matches[1]] = l:matches[6]
	endif
    endfor

    return { 'inc': l:include_path, 'def': l:macro_defs }
endfunction

" dpkg --listfiles libc6-dev
" rpm --query --list glibc-devel
" pacman --query --list mingw-w64-x86_64-headers
" cygcheck --list-package gcc-g++

