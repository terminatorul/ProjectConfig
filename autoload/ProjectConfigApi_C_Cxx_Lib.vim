vim9script

import './ProjectConfigApi_Generator.vim' as ConfigApi

type Project = ConfigApi.Project
type Module  = ConfigApi.Module

var Join_Path = ConfigApi.JoinPath
var Shell_Escape = ConfigApi.ShellEscape
var List_Compare = ConfigApi.ListCompare

# export def CollectModuleIncludes(project: Project, module: Module, ...modules: list<Module>)
#     var tree_depth = 0
#
#     for module_node in [ module ]->extend(modules)
# 	var subtree_depth = s:ModuleTreeDepth(a:project, l:module_node)
#
# 	if subtree_depth > tree_depth
# 	    tree_depth = subtree_depth
# 	endif
#     endfor
#
#     let l:includes = a:module.if_inc
#
#     eval l:includes->extend(a:is_toplevel || a:module.external ? a:module.inc : [ ])
# endfunction

def Sort_Version_Dir(Dir_List: list<string>): list<string>
    var sort_list = [ ]

    for dirname in Dir_List
	var version_string = dirname->fnamemodify(':t')

	if version_string->match('\v^[0-9]+(\.[0-9]+)*$') >= 0	# only version numbers, of the form 23.10938.24.02
	    sort_list->add([ version_string->split('\.')->mapnew((_, val) => str2nr(val)), dirname ])
	endif
    endfor

    sort_list->sort((v1, v2) => List_Compare(v1[0], v2[0]))

    return sort_list->mapnew((key, val) => val[1])
enddef

def MSVC_Tools_Directory(Release: string, Product: string, Tools_Version: string): list<string>
    # glob() path 'C:/Program Files/Microsoft Visual Studio/*/*/VC/Tools/MSVC/*/'

    var envvar: string = has('win64') ? 'ProgramFiles' : 'ProgramW6432'
    var vs_dir: list<string> = Join_Path(envvar->getenv(), 'Microsoft Visual Studio', Release)->glob(true, true)

    if !!vs_dir->len()
	vs_dir = Sort_Version_Dir(vs_dir)[-1 : -1]	# Try choosing latest release (currently 2022)
    else
	return [ ]					# Visual Studio directory not found
    endif

    vs_dir = Join_Path(vs_dir[0], Product)->glob(true, true)

    if !!vs_dir->len()
	vs_dir = vs_dir->sort()[0 : 0]			# 'Community' will sort before 'Enterprise', 'Professional'
    else
	return [ ]					# Visual Studio directory not found
    endif

    vs_dir = Join_Path(vs_dir[0], 'VC', 'Tools', 'MSVC', Tools_Version)->glob(true, true)

    if !!vs_dir->len()
	vs_dir = Sort_Version_Dir(vs_dir)[-1 : -1]     # Try choosing latest tools version eg. 14.38.33130
    else
	return [ ]
    endif

    return vs_dir
enddef

def SDK_Include_Directory(Platform_Version: string, Version: string): list<string>
    var envvar: string = has('win64') ? 'ProgramFiles(x86)' : 'ProgramFiles'
    var sdk_dir: list<string> = Join_Path(envvar->getenv(), 'Windows Kits', Platform_Version)->glob(true, true)

    if !!sdk_dir->len()
	sdk_dir = Sort_Version_Dir(sdk_dir)[-1 : -1]
    else
	return [ ]
    endif

    sdk_dir = Join_Path(sdk_dir[0], 'Include', Version)->glob(true, true)

    if !!sdk_dir->len()
	sdk_dir = s:Sort_Version_Dir(sdk_dir)[-1 : -1]
    else
	return [ ]
    endif

    return sdk_dir
enddef

export var DefaultSDKVersion: dict<any> =
	    \ {
	    \	'VS':  { 'Release': '*', 'Product': '*', 'Tools_Version': '*' },
	    \	'SDK': { 'Platform_Version': '[0-9]*', 'Version': '*' }
	    \ }

const g:ProjectConfig_DefaultSDKVersion = DefaultSDKVersion

# Populates a module for Windows SDK headers and Windows Universal CRT (C Run-Time)
# library headers
export def MS_SDK_UCRT_Module(version = DefaultSDKVersion): Module
    var VS_Release:   string = version->get('VS', { })->get('Release', '*')
    var VS_Product:   string = version->get('VS', { })->get('Product', '*')
    var VS_Tools_Ver: string = version->get('VS', { })->get('Tools_version', '*')

    var SDK_Platform_Ver: string = version->get('SDK', { })->get('Platform_Version', '[0-9]*')
    var SDK_Ver: string = version->get('SDK', { })->get('Version', '*')

    var SDK_UCRT: Module = ConfigApi.CreateModule('SDK-UCRT', true)

    SDK_UCRT['private']['dir'] = MSVC_Tools_Directory(VS_Release, VS_Product, VS_Tools_Ver) + SDK_Include_Directory(SDK_Platform_Ver, SDK_Ver)

    if SDK_UCRT['private']['dir']->len() == 2
	SDK_UCRT['public'].inc = Join_Path(SDK_UCRT['private']['dir'][0], 'include')->glob(true, true)

	var auto_cmd: dict<any> = { }
	auto_cmd.group = g:ProjectConfig_Project
	auto_cmd.event = [ 'BufRead' ]
	auto_cmd.pattern = SDK_UCRT['public'].inc[0]->fnamemodify(':p:gs?\\?/?') .. '*'
	auto_cmd.cmd = 'if fnamemodify("%", ":e") == "" | setlocal filetype=cpp | endif'

	[ auto_cmd ]->autocmd_add()

	for inc_dir in [ 'ucrt', 'shared', 'um', 'winrt', 'cppwinrt' ]
	    SDK_UCRT['public'].inc->extend(Join_Path(SDK_UCRT['private']['dir'][1], inc_dir)->glob(true, true))
	endfor
    endif

    SDK_UCRT['private'].ctags_args = [ '--recurse', '--languages=+C,C++', '--map-C++=+.', '--kinds-C=+px', '--kinds-C++=+px' ]
    SDK_UCRT['private'].ctags_args->extend([ '-D_EXPORT_STD=export', '-D_CONSTEXPR20=constexpr', '-D_STD=::std::', '-D_NODISCARD_=', '-D_NODISCARD=' ])
    SDK_UCRT['private'].ctags_args->extend([ '-D_STD_BEGIN=namespace std {', '-D_STD_END=}', '-D_STDEXT_BEGIN=namespace stdext {', '-D_STDEXT_END=}' ])
    SDK_UCRT['private'].ctags_args->extend([ '-D_STDEXT=::stdext::', '-D_CSTD=::', '-D_CHRONO=::std::chrono::', '-D_RANGES=::std::ranges::' ])
    SDK_UCRT['private'].ctags_args->extend([ '-D_EXTERN_C=', '-D_HAS_CXX17', '-D_HAS_CXX20', '-D_HAS_CXX23', '-D_CONSTEXPR23=constexpr' ])
    SDK_UCRT['private'].ctags_args->extend([ '-D_INLINE_VAR=inline', '-D__CLR_OR_THIS_CALL=', '-D__CLRCALL_OR_CDECL=', '-D_VCRT_NOALIAS=', '-D_VCRT_RESTRICT=', '-D_VCRTIMP=' ])
    SDK_UCRT['private'].ctags_args->extend([ '-D_CRT_BEGIN_C_HEADER=', '-D_CRT_END_C_HEADER=', '-D_MSVC_CONSTEXPR=constexpr'])
    SDK_UCRT['private'].ctags_args->extend([ '-D_CRTIMP2_IMPORT=', '-D_CRTIMP2_PURE_IMPORT=', '-D_CRTDATA2_IMPORT='])
    SDK_UCRT['private'].ctags_args->extend([ '-DDEFINE_DEVPROPKEY(name, ...)=const DEVPROPKEY name { ... }'])

    # 	"-include" "vcruntime_string.h"
    #
    #  Internal Microsoft preprocessor SAL (Source Annotation Language)
    # 	"-D__ANNOTATION(...)="
    # 	"-D__PRIMOP(...)="
    # 	"-D__QUALIFIER(...)="
    # 	"-D__MACHINE(...)="
    # 	"-D_Return_type_success_(...)="
    # 	"-D_SAL2_Source_(...)="
    # 	"-D_Function_class_(...)="
    # 	"-D_IRQL_requires_max_(...)="
    # 	"-D_Field_size_bytes_opt_(...)="
    # 	"-D_In_reads_bytes_(...)="
    # 	"-D_Inout_updates_bytes(...)="
    # 	"-D_In_range_(...)="
    #
    # 	"-D_Null_terminated_="
    # 	"-D_NullNull_terminated_="
    # 	"-D_In_="
    # 	"_D_Out_="
    # 	"-D_Inout_="
    # 	"-D__In_impl_="
    # 	"-D__deferTypecheck="
    # 	"-D_Must_inspect_result_="
    # 	"-D_Check_return_"
    # 	"-D_IRQL_requires_same_="
    # 	"-D_Interlocked_operand_="
    # 	"-D_USE_ATTRIBUTES_FOR_SAL=0"
    # 	"-D_USE_DECLSPECS_FOR_SAL=0"
    #
    #	"-DDEFINE_DEVPROPKEY(name, ...)=const DEVPROPKEY name { ... }"
    return SDK_UCRT
enddef

g:ProjectConfig_MS_SDK_UCRT_Module = MS_SDK_UCRT_Module

export var GCC_ShowSpecArgs: list<string> = [ '-v', '-dM', '-E', '-x' ]

if g:->has_key('ProjectConfig_GCC_ShowSpecArgs')
    GCC_ShowSpecArgs = g:ProjectConfig_GCC_ShowSpecArgs
else
    g:ProjectConfig_GCC_ShowSpecArgs = GCC_ShowSpecArgs
endif

export var GCC_Compiler: list<string> = [ 'gcc' ]

if g:->has_key('ProjectConfig_GCC_Compiler')
    GCC_Compiler = g:ProjectConfig_GCC_Compiler
else
    g:ProjectConfig_GCC_compiler = GCC_Compiler
endif

var GnuCompiler: func(): list<string>

def LocateGnuCompiler(): list<string>
    var compiler_exe: string = exepath(GCC_Compiler[0])

    if !empty(compiler_exe)
	GCC_Compiler = [ compiler_exe ] + GCC_Compiler[1 : ]

	GnuCompiler = () => GCC_Compiler
	g:ProjectConfig_GnuCompiler = GnuCompiler
    endif

    return GCC_Compiler
enddef

GnuCompiler = LocateGnuCompiler
g:ProjectConfig_GnuCompiler = GnuCompiler

export def Read_GCC_Specs(language: string = 'c', compiler_exe: any = '', compiler_args: list<string> = [ ]): dict<any>
    var compiler: list<string> =
	empty(compiler_exe) ? GnuCompiler() : type(compiler_exe) == v:t_list ? compiler_exe : [ compiler_exe ]

    var output_list: list<string> = (compiler_exe + compiler_args + GCC_ShowSpecArgs + [ language, ConfigApi.DevNull ])
		->mapnew((_, val) => Shell_Escape(val))->join(' ')->systemlist()

    var idx: number = -1

    for [index, line] in output_list->items()
	if line->stridx('#include "..."') >= 0
	    idx = index
	    break
	endif
    endfor

    var include_path: list<string> = [ ]

    if idx >= 0
	++idx

	while idx < output_list->len() && output_list[idx]->len() > 0
		    \ && (output_list[idx][0] == ' ' || output_list[idx]->stridx('#include <...>') >= 0)
	    if output_list[idx][0] == ' ' # && output_path[idx] != '/usr/local/include'
		include_path->add(output_list[idx][1 : ])
	    endif

	    ++idx
	endwhile
    endif

    var macro_defs: dict<string> = { }

    for line in output_list
	var matches = line->matchlist('\v^\C\s*#\s*define\s+(\h\w*(\(\s*(\h\w*\s*(\,\s*\h\w*\s*)*)?\))?)(\s+(.*))?$')

	if !empty(matches)
	    macro_defs[matches[1]] = matches[6]
	endif
    endfor

    return { 'inc': include_path, 'def': macro_defs }
enddef

g:ProjectConfig_Read_GCC_Specs = Read_GCC_Specs

# dpkg --listfiles libc6-dev
# rpm --query --list glibc-devel
# pacman --query --list mingw-w64-x86_64-headers
# cygcheck --list-package gcc-g++

# defcompile
