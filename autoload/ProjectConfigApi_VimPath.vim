
let g:ProjectConfig_VimPath = { 'name': 'include' }

let g:ProjectConfig_VimPath.AddModule = { mod, ... -> 0 }

function g:ProjectConfig_VimPath.LocalConfigInit()
    if exists('g:ProjectConfig_CleanPathOption') && g:ProjectConfig_CleanPathOption
	set path-=
    endif

    let g:ProjectConfig_Modules[g:ProjectConfig_Project].config['orig_path'] = &g:path
    let self.global_path = &g:path
endfunction

" Will be called with external modules first, and local modules after,
" each time following in-depth (recursive) traversal of the module tree
function g:ProjectConfig_VimPath.UpdateGlobalConfig(mod)
    set path-=.

    for l:inc_dir in a:mod.private.inc + a:mod['public'].inc
	execute 'set path-=' . l:inc_dir->fnameescape()->substitute('[ \\]', '\\\0', 'g')->substitute('\V,', '\\\\,', 'g')
	execute 'set path^=' . l:inc_dir->fnameescape()->substitute('[ \\]', '\\\0', 'g')->substitute('\V,', '\\\\,', 'g')
    endfor

    set path^=.
endfunction

" Notify traversal by depth level, top to bottom, for a module subtree has started
function g:ProjectConfig_VimPath.LocalConfigInitModule(mod)
    let self.local_inc_list = [ ]
    let self.external_inc_list = [ ]
endfunction

" Notify next node during traversal by depth level, top to bottom, of a subtree
function g:ProjectConfig_VimPath.UpdateModuleLocalConfig(mod)
    if a:mod.external
	eval self.external_inc_list->extend(a:mod.private.inc + a:mod.public.inc)
    else
	eval self.local_inc_list->extend(a:mod.private.inc + a:mod.public.inc)
    endif
endfunction

" Notify traversal by depth level, top to buttom, for a module subtree is
" complete
function g:ProjectConfig_VimPath.LocalConfigCompleteModule(mod)
    let l:inc_list = self.local_inc_list + self.external_inc_list
    let l:cmd = 'setlocal path^=' . l:inc_list->map({ _, val -> val->fnameescape()->substitute('[ \\]', '\\\0', 'g')->substitute('\V,', '\\\\,', 'g') })->join(',')

    if len(self.global_path)
	let l:cmd .= ',' . self.global_path
    endif

    let l:cmd .= ' | setlocal path-=.'
    let l:cmd .= ' | setlocal path-=.'
    let l:cmd .= ' | setlocal path-=.'
    let l:cmd .= ' | setlocal path^=.'

    if g:ProjectConfig_CleanPathOption
	let l:cmd .= ' | setlocal path-='
	let l:cmd .= ' | setlocal path-='
	let l:cmd .= ' | setlocal path-='
    endif

    call g:ProjectConfig_AddModuleAutocmd(a:mod, l:cmd)
endfunction

function g:ProjectConfig_VimPath.AddProject(project_name)
endfunction

eval g:ProjectConfig_Generators->add(g:ProjectConfig_VimPath)

