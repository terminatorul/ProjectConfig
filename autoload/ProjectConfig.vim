
vim9script

var ProjectConfigScript: list<dict<any>> = [ ]
var ProjectConfig_ApplyScript: bool = false	# used to prevent recursion
var LoadedProjects: list<string> = []

if !g:->has_key('ProjectConfig_NERDTreeIntegration')
    g:ProjectConfig_NERDTreeIntegration = true
endif

def ApplyProjectConfigScript(full_path: string, project: bool): void
    if ProjectConfig_ApplyScript
	return
    endif

    ProjectConfig_ApplyScript = true

    try
	for configData in ProjectConfigScript
	    if full_path =~ configData.pathname_pattern
		if configData->has_key('project_script')
		    try
			if !!configData.project_script->strlen()
			    if configData->has_key('directory_name')
				g:ProjectConfig_Directory = configData.directory_name
			    else
				g:ProjectConfig_Directory = ''
			    endif

			    g:ProjectConfig_Project = configData.project_name
			    var WorkingDirectory: string

			    if configData->has_key('cd')
				WorkingDirectory = getcwd()

				if tr(WorkingDirectory, '\', '/') != g:ProjectConfig_Directory
				    lchdir `=g:ProjectConfig_Directory->fnameescape()`    # Triggers ApplyProjectConfig() again
				endif
			    endif

			    if LoadedProjects->index(configData.project_name) < 0
				LoadedProjects->add(configData.project_name)

				try
				    source `=configData.project_script->fnameescape()`
				finally
				    if configData->has_key('cd') && tr(WorkingDirectory, '\', '/') != g:ProjectConfig_Directory
					lchdir `=WorkingDirectory->fnameescape()`
				    endif
				endtry
			    endif

			    unlet g:ProjectConfig_Directory
			    unlet g:ProjectConfig_Project
			endif
		    finally
			unlet configData.project_script
		    endtry
		endif

		if !project && configData->has_key('file_script')
		    var exclude_files = [ ]

		    if configData->has_key('exclude_list')
			exclude_files = configData.exclude_list
		    endif

		    if !!configData.file_script->strlen()
			if exclude_files->index(bufname('%')->fnamemodify(':t')) == -1
			    if configData->has_key('directory_name')
				g:ProjectConfig_Directory = configData.directory_name
			    else
				g:ProjectConfig_Directory = ''
			    endif

			    g:ProjectConfig_Project = configData.project_name

			    source `=configData.file_script->fnameescape()`

			    unlet g:ProjectConfig_Directory
			    unlet g:ProjectConfig_Project
			endif
		    endif
		endif
	    endif
	endfor
    finally
	ProjectConfig_ApplyScript = false
    endtry
enddef

export def Completion(ArgLead: string, CmdLine: string, CursorPos: any): string
    var result_lines: string = ''

    for configData in ProjectConfigScript
	if !!result_lines->strlen()
	    result_lines ..= "\n"
	endif

	result_lines ..= configData.project_name
    endfor

    return result_lines
enddef

export def FindLoad(project_name: string)
    for configData in ProjectConfigScript
	if configData.project_name == project_name && !!configData.directory_name->strlen()
	    configData.directory_name->chdir()

	    if !!g:ProjectConfig_NERDTreeIntegration && exists(':NERDTreeCWD')
		:NERDTreeCWD
	    else
		edit .
	    endif

	    break
	endif
    endfor
enddef

def g:ProjectConfig_NERDTreeListener(event: dict<any>): void
    ApplyProjectConfigScript(tr(event.nerdtree.root.path.str(), '\', '/'), true)
enddef

def AddNERDTreeListener(): void
    if g:->has_key('NERDTreePathNotifier')
	g:NERDTreePathNotifier.AddListener('init',    'ProjectConfig_NERDTreeListener')
	g:NERDTreePathNotifier.AddListener('refresh', 'ProjectConfig_NERDTreeListener')
    endif

    if b:->has_key('NERDTree')
	ApplyProjectConfigScript(tr(b:NERDTree.root.path.str(), '\', '/'), true)
    endif
enddef

var VimListenersAdded: bool = false

def AddVimListeners(): void
    if VimListenersAdded
	return
    endif

    augroup ProjectConfig
	autocmd BufNewFile,BufRead * ApplyProjectConfigScript(expand('%:p:gs#\#/#'), false)
	autocmd DirChanged	   * ApplyProjectConfigScript(tr(getcwd(), '\', '/'), true)
	if g:ProjectConfig_NERDTreeIntegration
	    autocmd VimEnter           * AddNERDTreeListener()
	endif
	autocmd VimEnter           * ApplyProjectConfigScript(tr(getcwd(), '\', '/'), true)
    augroup END
enddef

export def SetScript(project_name_arg: string, ...arg_list: list<any>): void
    var keep_pwd: bool = false
    var directory_name: string = !!arg_list->len() ? arg_list[0] : project_name_arg
    var project_name: string = !!arg_list->len() ? project_name_arg : project_name_arg->fnamemodify(':t:r')
    var project_script: string
    var file_script: string

    if arg_list->len() > 1
	project_script = arg_list[1]

	if arg_list->len() > 2
	    file_script = arg_list[2]
	endif

	if arg_list->len() > 3
	    keep_pwd = !!arg_list[3]
	endif
    else
	if (has('win32') || has('win64')) && isdirectory(expand('~\vimfiles'))
	    project_script = expand('~\vimfiles\project\' .. project_name .. '.vim')
	else
	    project_script = expand('~/.vim/project/' .. project_name .. '.vim')
	endif
    endif

    if empty(file_script)
	if (has('win32') || has('win64')) && filereadable(project_script->fnamemodify(':r') .. '_files.vim')
	    file_script = project_script->fnamemodify(':r') .. '_files.vim'
	else
	    if filereadable(project_script->fnamemodify(':r') .. '.files.vim')
		file_script = project_script->fnamemodify(':r') .. '.files.vim'
	    else
		file_script = ''
	    endif
	endif
    endif

    ProjectConfigScript->add(
	    {
	        'project_name': project_name,
	        'directory_name': directory_name->fnamemodify(':p:gs#\#/#:s#/$##'),
	        'pathname_pattern': '\V\^' .. directory_name->fnamemodify(':p:gs#\#/#:s#/$##') .. '\v((/.*)?/([^.][^/]*))?$',
	        'file_script': !!file_script->strlen() ? file_script->fnamemodify(':p') : '',
	        'exclude_list': [ 'COMMIT_EDITMSG', 'MERGE_MSG' ],
	        'project_script': !!project_script->strlen() ? project_script->fnamemodify(':p') : ''
	    })

    if !keep_pwd
	ProjectConfigScript[-1].cd = true
    endif

    AddVimListeners()
enddef

function g:ProjectConfig_DebugVariables()
    g:ProjectConfigScript = ProjectConfigScript
    g:ProjectConfig_ApplyScript = ProjectConfig_ApplyScript
endfunction
