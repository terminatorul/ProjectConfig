
let s:InPlace_Append_Unique = funcref('g:ProjectConfig_InPlaceAppendUnique')
let s:InPlace_Prepend_Unique = funcref('g:ProjectConfig_InPlacePrependUnique')

let s:DependencyWalker =
	    \ {
	    \	'target_level':   1,
	    \   'module_list':    [ ],
	    \   'parent_chain':   [ ]
	    \ }

function s:DependencyWalker.New(project, callback_fn, descend_fn)
    return l:self->copy()->extend
		\ ( {
		\  	'project':      a:project,
	    	\ 	'callback_fn':  a:callback_fn,
		\	'descend_fn':	a:descend_fn
		\ } )
endfunction

function s:DependencyWalker.Module_Tree_Depth(module, current_level = 1)
    let l:deps_list = l:self.descend_fn(a:current_depth, a:module)

    if len(l:deps_list)
	eval l:self.parent_chain->add(a:module.name)

	let l:subtree_depth =
		    \ l:deps_list
		    \   ->filter({ _, name -> has_key(l:self.project.modules, name) && l:self.parent_chain->index(name) < 0 })
		    \   ->map({ _, name -> l:self.project[name] })
		    \	->map({ _, submodule -> l:self.Module_Tree_Depth(submodule, current_depth + 1) })
		    \	->max()

	eval l:self.parent_chain->remove(-1)

	if l:subtree_depth
	    return l:subtree_depth
    endif

    return a:current_depth
endfunction

function s:DependencyWalker.Traverse_Dependencies(modules, current_level = 1)
    if a:current_level == l:self.target_level
	let l:index = 0

	for l:module in a:modules
	    let l:old_index = l:self.module_list->index(l:module.name)

	    if l:old_index < 0
		let l:is_duplicate = v:false
	    else
		let l:is_duplicate = v:true
		eval l:self.module_list->remove(l:old_index)

		if l:old_index < l:index
		    l:index -= 1
		endif
	    endif

	    eval l:self.module_list->insert(l:module.name, l:index)
	    let l:index += 1

	    let l:cyclic_deps =
			\ l:self.descend_fn(a:current_level, l:module)
			\   ->filter({ _, dep_name -> l:self.parent_chain->index(dep_name) >= 0 })

	    call l:self.callback_fn(a:current_level, l:is_duplicate, l:module, l:cyclic_deps)
	endfor
    else
	for l:module in a:modules
	    eval l:self.parent_chain->add(l:module.name)

	    try
		let l:submodules =
			    \ l:self.descend_fn(a:current_level, l:module)
			    \   ->filter({ _, dep_name -> has_key(l:self.project.modules, dep_name) && l:self.parent_chain->index(dep_name) < 0 })
			    \   ->map({ _, dep_name -> l:self.project.modules[dep_name] })

		call l:self.Traverse_Dependencies(l:submodules, a:current_level + 1)
	    finally
		eval l:self.parent_chain->remove(-1)
	    endtry
	endfor
    endif
endfunction

function g:ProjectConfig_FullDescend(current_level, module)
    return a:module['interface'].deps + a:module['public'].deps + a:module['private'].deps
endfunction

let s:FullDescend = funcref('g:ProjectConfig_FullDescend')

function g:ProjectConfig_SpecificDescend(current_level, module)
    if a:current_level == 1
	return a:module['public'].deps + a:module['private'].deps
    endif

    return a:module['interface'].deps + a:module['public'].deps
endfunction

let s:SpecificDescend = funcref('g:ProjectConfig_SpecificDescend')

" Enumerate each dependency of the given modules, starting with the bottom
" level of the dependency tree, going up level by level, until the top level
" (consisting of the given module list). Duplicate dependencies are marked as
" such during enumeration, after their first occurrence. Dependency cycles
" are also broken and reported, at the lowest level reached by their loop.
"
" callback_fn is called for each module and each dependency, with arguments:
"   - current level in the module dependency tree
"   - duplicate flag, true if this dependency has been enumerated before
"   - the current node in the tree (the current module)
"   - a list of direct dependencies for the current module, that lead to
"     dependency cycles because they are in the chain of parent nodes for the
"     current module
"
" Returns all module names from the trees, flattened in one list, with
" top-level modules listed first, and next level modules listed after, and so
" on.  Duplicates are listed only once, at the earliest (smaller) position
" where they are first encountered.
function g:ProjectConfig_TraverseAllDependencies(callback_fn, project, module, ...)
    let l:modules = [ a:module ]->extend(a:000)
    let l:deps_walker = s:DependencyWalker.New(a:project, a:callback_fn, s:FullDescend)
    let l:deps_walker.target_level = l:modules->mapnew({ _, mod -> l:deps_walker.Module_Tree_Depth(mod) })->max()

    while l:deps_walker.target_level
	call l:deps_walker.Traverse_Dependencies(1, l:modules)
	let l:deps_walker.target_level -= 1
    endwhile

    call a:callback_fn(0, v:false, v:null, [ ])

    return l:deps_walker.module_list
endfunction

function s:CollectProperties_DefaultReduce(state, level, existing_list, new_list)
    if a:level < a:state.level
	let a:state.level = a:level

	if a:level == 0
	    call s:InPlace_Append_Unique(a:existing_list, a:state['previous']->remove(0, -1))
	else
	    call s:InPlace_Prepend_Unique(a:state['previous'], a:existing_list->remove(0, -1))
	endif
    endif

    call s:InPlace_Append_Unique(a:existing_list, a:new_list)
endfunction

let s:Default_Reduce = funcref('s:CollectProperties_DefaultReduce')

let s:CollectProperties = { }

function s:CollectProperties.New(accessor_fn, reduce_fn = v:none)
    let l:accessor_fn = type(a:accessor_fn) == v:t_list ? a:accessor_fn : [ a:accessor_fn ]

    if empty(a:reduce_fn)
	let l:reduce_fn = [ ]

	for l:index in range(len(a:accessor_fn))
	    eval l:reduce_fn->add(funcref(s:Default_Reduce, [ { 'level': v:numbermax, 'previous': [ ] } ]))
	endfor
    else
	let l:reduce_fn = a:reduce_fn
    endif

    return
	\ l:self
	\   ->copy()
	\   ->extend
	\	({
	\	    'properties':  [ [ ] ]->repeat(l:accessor_fn->len()),
	\	    'accessor_fn': l:accessor_fn,
	\	    'reduce_fn':   l:reduce_fn
	\	})
endfunction

function s:CollectProperties.Dependency_Module(level, is_duplicate, module, cyclic_deps)
    if a:level
	for [ l:index, l:accessor_fn ] in l:self.accessor_fn->items()
	    let l:new_list = l:accessor_fn(a:level, a:is_duplicate, a:module, a:cyclic_deps)
	    call l:self.reduce_fn[l:index](la:level, :self.properties[l:index], l:new_list)
	endfor
    else
	for l:index in l:self.accessor_fn->keys()
	    call l:self.reduce_fn[l:index](la:level, :self.properties[l:index], [ ])
	endfor
endfunction

function g:ProjectConfig_CollectExplicitProperties(accessor_fn, reduce_fn, project, module, ...)
    let l:modules = [ a:module ]->extend(a:000)
    let l:collect_props = s:CollectProperties.New(a:accessor_fn, reduce_fn)
    let l:deps_walker = s:DependencyWalker.New(a:project, s:collect_props.Dependency_Module, s:SpecificDescend)
    let l:deps_walker.target_level = l:modules->mapnew({ _, mod ->l:deps_walker.Module_Tree_Depth(mod) })->max()

    while l:deps_walker.target_level
	call l:deps_walker.Traverse_Dependencies(1, l:modules)
	let l:deps_walker.target_level -= 1
    endwhile

    call s:collect_props.Dependency_Module(0, v:false, v:null, [ ])

    return l:collect_props.properties
endfunction

let s:Collect_Explicit_Properties = funcref('g:ProjectConfig_CollectExplicitProperties')

function g:ProjectConfig_CollectProperties(accessor_fn, project, module, ...)
    return s:Collect_Explicit_Properties->call([ accessor_fn, v:none, project, module ]->extend(a:000))
endfunction

