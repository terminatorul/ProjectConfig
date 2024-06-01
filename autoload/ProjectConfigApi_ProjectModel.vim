vim9script

type PropertyList = list<any>
type NameList = list<string>
export type Property = any
export type Module = dict<any>
export type Project = dict<any>
export type CallbackFunction = func(bool, number, bool, Module, bool): void
export type AccessorFunction = func(number, bool, Module, bool): PropertyList
export type ReducerFunction  = func(number, PropertyList, PropertyList): void
export type DescendFunction  = func(number, Module): NameList

# duplicate values that appear sooner have priority and will be kept over
# values that appear later
export def InPlaceAppendUnique(l1: list<any>, l2: list<any>, ...extra: list<list<any>>): list<any>
    for element in [ l2 ]->extend(extra)->flattennew(1)
	if l1->index(element) < 0
	    l1->add(element)
	endif
    endfor

    return l1
enddef

g:ProjectConfig_InPlaceAppendUnique =  InPlaceAppendUnique

# duplicate values that appear sooner have priority and will be kept over
# values that appear later
export def ListAppendUnique(l1: list<any>, l2: list<any>, ...extra: list<list<any>>): list<any>
    return InPlaceAppendUnique->call([ copy(l1), l2 ]->extend(extra))
enddef

g:ProjectConfig_ListAppendUnique =  ListAppendUnique

# duplicate values that appear sooner in the target list have priority over
# values that appear later. The element order in l2 + ... is otherwise
# preserved
export def InPlacePrependUnique(l1: list<any>, l2: list<any>, ...extra: list<list<any>>): list<any>
    for element in [ l2 ]->extend(extra)->flattennew(1)->reverse()
	var element_index: number = l1->index(element)

	if element_index >= 0
	    l1->remove(element_index)
	endif

	eval l1->insert(element)
    endfor

    return l1
enddef

g:ProjectConfig_InPlacePrependUnique = InPlacePrependUnique

# duplicate values that appear sooner in the target list have priority over
# values that appear later. The element order in l2 + ... is otherwise
# preserved
export def ListPrependUnique(l1: list<any>, l2: list<any>, ...extra: list<list<any>>): list<any>
    return InPlacePrependUnique->call([ copy(l1), l2 ]->extend(extra))
enddef

g:ProjectConfig_ListPrependUnique = ListPrependUnique

export enum TraverseMode
    ByLevel,
    InDepth
endenum

export enum TraverseDirection
    TopDown,
    ButtomUp
endenum

export enum SiblingTraversal
    LeftToRight,
    RightToLeft
endenum

export class DependencyWalker
    var exported: bool
    var target_level: number = 1
    var module_list: list<string> = [ ]
    var parent_chain: list<string> = [ ]
    var project: Project
    var Callback_Function: CallbackFunction
    var Descend_Function: DescendFunction
    var traverse_direction: TraverseDirection
    var sibling_traversal: SiblingTraversal

    def new(project: Project, Callback_Function: CallbackFunction, Descend_Function: DescendFunction)
	this.project = project
	this.Callback_Function = Callback_Function
	this.Descend_Function = Descend_Function
	this.parent_chain = [ ]
    enddef

    def TargetLevel(level: number = -1): number
	if level == -1
	    return this.target_level
	else
	    var previous_level = this.target_level
	    this.target_level = level
	    return previous_level
	endif
    enddef

    def ModuleTreeDepth(module: Module, current_level: number = 1): number
	var deps_list: list<string> = this.Descend_Function(current_level, module)

	if !!deps_list->len()
	    this.parent_chain->add(module.name)

	    var subtree_depth: number =
			\ deps_list
			\   ->filter((_, name) => has_key(this.project.modules, name) && this.parent_chain->index(name) < 0)
			\   ->mapnew((_, name) => this.project.modules[name])
			\	->map((_, submodule) => this.ModuleTreeDepth(submodule, current_level + 1))
			\	->max()

	    this.parent_chain->remove(-1)

	    if !!subtree_depth
		return subtree_depth
	    endif
	endif

	return current_level
    enddef

    def StartTraversal(exported: bool, traverse_direction: TraverseDirection, sibling_traversal: SiblingTraversal)
	this.exported = exported
	this.traverse_direction = traverse_direction
	this.sibling_traversal = sibling_traversal
	this.target_level = 0

	if !!this.module_list
	    this.module_list->remove(0, -1)
	endif
    enddef

    def CheckExchangeDuplicate(module: Module): bool
	if this.module_list->index(module.name) < 0
	    if this.sibling_traversal == SiblingTraversal.LeftToRight
		this.module_list->append(module.name)
	    else
		this.module_list->insert(module.name)
	    endif

	    return false
	endif

	return true
    enddef

    def InDepth_Traverse(modules: list<Module>): void
	for module in this.SubmoduleOrder(modules)
	    var is_cyclic_dependency = this.parent_chain->index(module.name) >= 0

	    if this.traverse_direction == TraverseDirection.TopDown
		this.Callback_Function(this.exported, this.parent_chain->len() + 1, this.CheckExchangeDuplicate(module), module, is_cyclic_dependency)
	    endif

	    var dependency_list = this.Descend_Function(this.parent_chain->len() + 1, module)
				    ->filter((_, name): bool => this.project.modules.has_key(name) && this.parent_chain->index(name) < 0)
				    ->mapnew((_, name): Module => this.project.modules[name])

	    this.parent_chain->add(module.name)

	    try
		this.InDepth_Traverse(this.SubmoduleOrder(dependency_list))
	    finally
		this.parent_chain->remove(-1)
	    endtry

	    if this.traverse_direction == TraverseDirection.ButtomUp
		this.Callback_Function(this.exported, this.parent_chain->len() + 1, this.CheckExchangeDuplicate(module), module, is_cyclic_dependency)
	    endif
	endfor
    enddef

    def Traverse_InDepth_ButtomUp(exported: bool, modules: list<Module>,  sibling_traversal: SiblingTraversal = SiblingTraversal.RightToLeft): void
	this.StartTraversal(exported, TraverseDirection.ButtomUp, sibling_traversal)
	this.InDepth_Traverse(modules)
    enddef

    def Traverse_InDepth_TopDown(exported: bool, modules: list<Module>, sibling_traversal: SiblingTraversal = SiblingTraversal.LeftToRight): void
	this.StartTraversal(exported, TraverseDirection.TopDown,  sibling_traversal)
	this.InDepth_Traverse(modules)
    enddef

    def SubmoduleOrder(submodules: list<Module>): list<Module>
	if this.sibling_traversal == SiblingTraversal.LeftToRight
	    return submodules
	endif

	# BottomUp direction also enumerates siblings by level right-to-left
	return submodules->copy()->reverse()
    enddef

    def TraverseTargetLevel(modules: list<Module>): bool
	if this.parent_chain->len() + 1 == this.target_level
	    var index: number = 0

	    for module in this.SubmoduleOrder(modules)
		var is_cyclic_dependency: bool = !!(this.parent_chain->index(module.name) >= 0)

		this.Callback_Function(this.exported, this.parent_chain->len() + 1, this.CheckExchangeDuplicate(module), module, is_cyclic_dependency)
	    endfor

	    return !!modules
	else
	    var target_level_reached = false

	    for module in this.SubmoduleOrder(modules)
		this.parent_chain->add(module.name)

		try
		    var submodules =
				\ this.Descend_Function(this.parent_chain->len(), module)
				\   ->filter((_, module_name): bool => this.project.modules->has_key(module_name) && this.parent_chain->index(module_name) < 0)
				\   ->mapnew((_, module_name): Module => this.project.modules[module_name])

		    if !!submodules
			var level_reached = this.TraverseTargetLevel(this.SubmoduleOrder(submodules))
			target_level_reached = target_level_reached || level_reached
		    endif
		finally
		    this.parent_chain->remove(-1)
		endtry
	    endfor

	    return target_level_reached
	endif
    enddef

    def Traverse_ByLevel_TopDown(exported: bool, module: Module, modules: list<Module>, sibling_traversal: SiblingTraversal = SiblingTraversal.LeftToRight): list<string>
	this.StartTraversal(exported, TraverseDirection.TopDown, sibling_traversal)

	while this.TraverseTargetLevel([ module ]->extend(modules))
	    ++this.target_level
	endwhile

	this.Callback_Function(exported, 0, v:false, null_dict, false)

	return this.module_list
    enddef

    def Traverse_ByLevel_ButtomUp(exported: bool, module: Module, modules: list<Module>, sibling_traversal: SiblingTraversal = SiblingTraversal.RightToLeft): list<string>
	this.StartTraversal(exported, TraverseDirection.TopDown, sibling_traversal)
	this.target_level = [ module ]->extend(modules)->mapnew((_, mod) => this.ModuleTreeDepth(mod))->max()

	while this.target_level
	    this.TraverseTargetLevel([ module ]->extend(modules))
	    --this.target_level
	endwhile

	this.Callback_Function(exported, 0, false, null_dict, false)

	return this.module_list
    enddef

    static def FullDescend(current_level: number, module: Module): list<string>
	return module['interface']['deps'] + module['public']['deps'] + module['private']['deps']
    enddef

    static def SpecificDescend(current_level: number, module: Module): list<string>
	if current_level == 1
	    return module['private']['deps' ] + module['public']['deps']
	endif

	return module['interface']['deps'] + module['public']['deps']
    enddef
endclass

g:ProjectConfig_FullDescend = DependencyWalker.FullDescend
g:ProjectConfig_SpecificDescend = DependencyWalker.SpecificDescend

const SpecificDescend: DescendFunction = DependencyWalker.SpecificDescend

# Enumerate each dependency of the given modules, starting with the bottom
# level of the dependency tree, going up level by level, until the top level
# (consisting of the given module list). Duplicate dependencies are marked as
# such during enumeration, after their first occurrence. Dependency cycles
# are also broken and reported, at the lowest level reached by their loop.
#
# Callback_Function is called for each module and each dependency, with arguments:
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
def TraverseAllDependencies(Callback_Function: CallbackFunction, project: Project, module: Module, ...modules: list<Module>): list<string>
    var tree_walker: DependencyWalker = DependencyWalker.new(project, Callback_Function, DependencyWalker.FullDescend)

    for exported in [ true, false ]
	tree_walker.Traverse_ByLevel_ButtomUp(exported, module, modules)
    endfor

    return tree_walker.module_list
enddef

g:ProjectConfig_TraverseAllDependencies = TraverseAllDependencies

def Default_Reduce(state: dict<any>, level: number, existing_list: PropertyList, new_list: PropertyList): void
    InPlacePrependUnique(existing_list, new_list)
enddef

class CollectProperties
    var properties:  list<PropertyList>
    var accessor_fn: list<AccessorFunction>
    var reducer_fn:  list<ReducerFunction>

    def new(accessor_fn: any, reducer_fn: list<ReducerFunction> = null_list)
	var accessors: list<AccessorFunction> = type(accessor_fn) == v:t_list ? accessor_fn : [ accessor_fn ]
	var reducers: list<ReducerFunction> = null_list

	if empty(reducer_fn)
	    reducers = [ ]

	    for index in accessors->len()->range()
		reducers->add(Default_Reduce->funcref([ { } ]))
	    endfor
	else
	    reducers = reducer_fn
	endif

	this.properties  = [ [ ] ]->repeat(accessors->len())->deepcopy(1)
	this.accessor_fn = accessors
	this.reducer_fn   = reducers
    enddef

    def Dependency_Module_Callback(external: bool, level: number, is_duplicate: bool, module: Module, is_cyclic_dep: bool): void
	if external == module->get('external', false)
	    if !!level
		for [ index, Accessor_Fn ] in this.accessor_fn->items()
		    var new_list: PropertyList = Accessor_Fn(level, is_duplicate, module, is_cyclic_dep)
		    this.reducer_fn[index](level, this.properties[index], new_list)
		endfor
	    else
		for index in this.accessor_fn->len()->range()
		    this.reducer_fn[index](level, this.properties[index], [ ])
		endfor
	    endif
	endif
    enddef
endclass

export def CollectPropertiesWithReducer(
	    accessors:  list<AccessorFunction>,
	    reducers:   list<ReducerFunction>,
	    project:    Project,
	    module:     Module,
	    ...modules: list<Module>
	): list<PropertyList>

    var module_list: list<Module> = [ module ]->extend(modules)
    var collect_props: CollectProperties = CollectProperties.new(accessors, reducers)
    var tree_walker: DependencyWalker = DependencyWalker.new(project, collect_props.Dependency_Module_Callback, SpecificDescend)

    tree_walker.Traverse_ByLevel_ButtomUp(true, module, modules)
    tree_walker.Traverse_ByLevel_ButtomUp(false, module, modules)

    return collect_props.properties
enddef

g:ProjectConfig_CollectPropertiesWithReducer = CollectPropertiesWithReducer

def g:ProjectConfig_CollectProperties(accessor_fn: list<AccessorFunction>, project: Project, module: Module, ...modules: list<Module>): list<PropertyList>
    return CollectPropertiesWithReducer->call([ accessor_fn, v:none, project, module ]->extend(modules))
enddef

def Default_Accessor(members: any, level: number, is_duplicate: bool, module: Module, is_cyclic_dep: bool): PropertyList
    var values: PropertyList = [ ]
    var scope_list: list<dict<any>>

    if level == 1
	scope_list = [ module->get('private', { }), module->get('public', { }) ]
    else
	scope_list = [ module->get('public', { }), module->get('interface', { }) ]
    endif

    var member_sequence: list<string> = type(members) == v:t_string ? members->split('\.') : members

    for scope in scope_list
	var key_missing: bool = false
	var value: any = scope

	for member: string in member_sequence
	    if value->has_key(member)
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

export def ModuleProperties(members: any, project: Project, module: Module, ...modules: list<Module>): list<PropertyList>
    var member_list: list<string> = type(members) == v:t_list ? members : [ members ]
    var accessor_fn: list<AccessorFunction> = member_list->mapnew((_, member) => funcref(Default_Accessor, [ member ]))

    return CollectPropertiesWithReducer->call([ accessor_fn, null_list, project, module ]->extend(modules))
enddef

g:ProjectConfig_ModuleProperties = ModuleProperties

# defcompile
