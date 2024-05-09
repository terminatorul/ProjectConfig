vim9script

var InPlace_Append_Unique: func = funcref('g:ProjectConfig_InPlaceAppendUnique')
var InPlace_Prepend_Unique: func = funcref('g:ProjectConfig_InPlacePrependUnique')

var DependencyWalker: dict<any> =
	    \ {
	    \	'target_level':   1,
	    \   'module_list':    [ ],
	    \   'parent_chain':   [ ]
	    \ }

type PropertyList = list<any>
type NameList = list<string>
type Module = dict<any>
type Project = dict<any>
export type CallbackFunction = func(number, bool, Module, NameList): void
export type AccessorFunction = func(number, bool, Module, NameList): PropertyList
export type ReduceFunction   = func(number, PropertyList, PropertyList): void
export type DescendFunction  = func(number, Module): NameList

export enum TraversalMode
    None,
    ByLevel_TopDown,
    ByLevel_ButtomUp,
    InDepth_TopDown,
    InDepth_ButtomUp
endenum

def DependencyWalker_New(self: dict<any>, project: Project, Callback_Fn: CallbackFunction, Descend_Fn: DescendFunction): dict<any>
    return self->extendnew({
		\  	'project':      project,
	    	\ 	'callback_fn':  Callback_Fn,
		\	'descend_fn':	Descend_Fn
		\ })
enddef

def DependencyWalker_Module_Tree_Depth(self: dict<any>, module: Module, current_level: number = 1): number
    var deps_list: list<string> = self.descend_fn(current_level, module)

    if !!deps_list->len()
	self.parent_chain->add(module.name)

	var subtree_depth: number =
		    \ deps_list
		    \   ->filter((_, name) => has_key(self.project.modules, name) && self.parent_chain->index(name) < 0)
		    \   ->mapnew((_, name) => self.project.modules[name])
		    \	->map((_, submodule) => DependencyWalker_Module_Tree_Depth(self, submodule, current_level + 1))
		    \	->max()

	self.parent_chain->remove(-1)

	if !!subtree_depth
	    return subtree_depth
	endif
    endif

    return current_level
enddef

def DependencyWalker_Traverse_Dependencies(self: dict<any>, modules: list<Module>, current_level: number = 1): void
    if current_level == self.target_level
	var index: number = 0

	for module in modules
	    var old_index: number = self.module_list->index(module.name)
	    var is_duplicate: bool

	    if old_index < 0
		is_duplicate = v:false
	    else
		is_duplicate = v:true
		self.module_list->remove(old_index)

		if old_index < index
		    --index
		endif
	    endif

	    self.module_list->insert(module.name, index)
	    ++index

	    var cyclic_deps: list<string> = self.descend_fn(current_level, module)
			    ->filter((_, dep_name) => self.parent_chain->index(dep_name) >= 0)

	    self.callback_fn(current_level, is_duplicate, module, cyclic_deps)
	endfor
    else
	for module in modules
	    self.parent_chain->add(module.name)

	    try
		var submodules =
			    \ self.descend_fn(current_level, module)
			    \   ->filter((_, dep_name) => has_key(self.project.modules, dep_name) && self.parent_chain->index(dep_name) < 0)
			    \   ->map((_, dep_name) => self.project.modules[dep_name])

		DependencyWalker_Traverse_Dependencies(self, submodules, current_level + 1)
	    finally
		self.parent_chain->remove(-1)
	    endtry
	endfor
    endif
enddef

def g:ProjectConfig_FullDescend(current_level: number, module: Module): list<string>
    return module['interface'].deps + module['public'].deps + module['private'].deps
enddef

var FullDescend: func(number, dict<any>): list<string> = funcref('g:ProjectConfig_FullDescend')

def g:ProjectConfig_SpecificDescend(current_level: number, module: Module): list<string>
    if current_level == 1
	return module['private'].deps + module['public'].deps
    endif

    return module['interface'].deps + module['public'].deps
enddef

var SpecificDescend: DescendFunction = funcref('g:ProjectConfig_SpecificDescend')

# Enumerate each dependency of the given modules, starting with the bottom
# level of the dependency tree, going up level by level, until the top level
# (consisting of the given module list). Duplicate dependencies are marked as
# such during enumeration, after their first occurrence. Dependency cycles
# are also broken and reported, at the lowest level reached by their loop.
#
# callback_fn is called for each module and each dependency, with arguments:
#   - current level in the module dependency tree
#   - duplicate flag, true if this dependency has been enumerated before
#   - the current node in the tree (the current module)
#   - a list of direct dependencies for the current module, that lead to
#     dependency cycles because they are in the chain of parent nodes for the
#     current module
#
# Returns all module names from the trees, flattened in one list, with
# top-level modules listed first, and next level modules listed after, and so
# on.  Duplicates are listed only once, at the earliest (smaller) position
# where they are first encountered.
def g:ProjectConfig_TraverseAllDependencies(Callback_Fn: CallbackFunction, project: Project, module: Module, ...modules: list<Module>): list<string>
    var mod_list = [ module ]->extend(modules)
    var deps_walker = DependencyWalker_New(DependencyWalker, project, Callback_Fn, FullDescend)

    deps_walker.target_level = mod_list->mapnew((_, mod) => DependencyWalker_Module_Tree_Depth(deps_walker, mod))->max()

    while !!deps_walker.target_level
	DependencyWalker_Traverse_Dependencies(deps_walker, mod_list)
	--deps_walker.target_level
    endwhile

    Callback_Fn(0, v:false, null_dict, [ ])

    return deps_walker.module_list
enddef

def CollectProperties_DefaultReduce(state: dict<any>, level: number, existing_list: PropertyList, new_list: PropertyList): void
    if level < state.level
	state.level = level

	if level == 0
	    if !empty(state['previous'])
		InPlace_Append_Unique(existing_list, state['previous']->remove(0, -1))
	    endif
	else
	    if !empty(existing_list)
		InPlace_Prepend_Unique(state['previous'], existing_list->remove(0, -1))
	    endif
	endif
    endif

    InPlace_Append_Unique(existing_list, new_list)
enddef

var Default_Reduce = funcref('CollectProperties_DefaultReduce')

# var CollectProperties: dict<any> = { }

class CollectProperties
    var properties:  list<PropertyList>
    var accessor_fn: list<AccessorFunction>
    var reduce_fn:   list<ReduceFunction>

    def new(accessor_fn: any, reduce_fn: list<ReduceFunction> = null_list)
	var accessors: list<AccessorFunction> = type(accessor_fn) == v:t_list ? accessor_fn : [ accessor_fn ]
	var reducers: list<ReduceFunction> = null_list

	if empty(reduce_fn)
	    reducers = [ ]

	    for index in accessors->len()->range()
		reducers->add(funcref(Default_Reduce, [ { 'level': v:numbermax, 'previous': [ ] } ]))
	    endfor
	else
	    reducers = reduce_fn
	endif

	this.properties  = [ [ ] ]->repeat(accessors->len())->deepcopy(1)
	this.accessor_fn = accessors
	this.reduce_fn   = reducers
    enddef

    def Dependency_Module(level: number, is_duplicate: bool, module: Module, cyclic_deps: NameList): void
	if !!level
	    for [ index, Accessor_Fn ] in this.accessor_fn->items()
		var new_list: PropertyList = Accessor_Fn(level, is_duplicate, module, cyclic_deps)
		this.reduce_fn[index](level, this.properties[index], new_list)
	    endfor
	else
	    for index in this.accessor_fn->len()->range()
		this.reduce_fn[index](level, this.properties[index], [ ])
	    endfor
	endif
    enddef
endclass

def g:ProjectConfig_CollectExplicitProperties(accessor_fn: list<AccessorFunction>, reduce_fn: list<ReduceFunction>, project: Project, module: Module, ...modules: list<Module>): list<PropertyList>
    var module_list: list<Module> = [ module ]->extend(modules)
    var collect_props: CollectProperties = CollectProperties.new(accessor_fn, reduce_fn)
    var deps_walker: dict<any> = DependencyWalker_New(DependencyWalker, project, collect_props.Dependency_Module, SpecificDescend)

    deps_walker.target_level = module_list->mapnew((_, mod) => DependencyWalker_Module_Tree_Depth(deps_walker, mod))->max()

    while !!deps_walker.target_level
	DependencyWalker_Traverse_Dependencies(deps_walker, module_list)
	--deps_walker.target_level
    endwhile

    deps_walker['callback_fn'](0, v:false, { }, [ ])

    return collect_props.properties
enddef

var Collect_Explicit_Properties = funcref('g:ProjectConfig_CollectExplicitProperties')

def g:ProjectConfig_CollectProperties(accessor_fn: list<AccessorFunction>, project: Project, module: Module, ...modules: list<Module>): list<PropertyList>
    return Collect_Explicit_Properties->call([ accessor_fn, v:none, project, module ]->extend(modules))
enddef

def Default_Accessor_Function(members: any, level: number, is_duplicate: bool, module: Module, cyclic_deps: NameList): PropertyList
    var values: PropertyList = [ ]
    var scope_list: list<dict<any>>

    if level == 1
	scope_list = [ module['private'], module['public'] ]
    else
	scope_list = [ module['public'], module['interface'] ]
    endif

    var member_list: list<string> = type(members) == v:t_string ? members->split('\.') : members

    for scope in scope_list
	var key_missing: bool = false
	var value: any = scope

	for member: string in member_list
	    if has_key(value, member)
		value = value[member]
	    else
		key_missing = true
		break
	    endif
	endfor

	if !key_missing
	    if type(value) == v:t_list
		values->extend(value)
	    else
		values->add(value)
	    endif
	endif
    endfor

    return values
enddef

var Default_Accessor = funcref('Default_Accessor_Function')

def g:ProjectConfig_ModuleProperties(members: any, project: Project, module: Module, ...modules: list<Module>): list<PropertyList>
    var member_list: list<string> = type(members) == v:t_list ? members : [ members ]
    var accessor_fn: list<AccessorFunction> = member_list->mapnew((_, member) => funcref(Default_Accessor, [ member ]))

    return Collect_Explicit_Properties->call([ accessor_fn, null_list, project, module ]->extend(modules))
enddef

# defcompile
