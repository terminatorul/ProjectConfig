let s:ProjectConfigScript = [ ]
let s:ProjectConfig_ApplyScript = v:false	" used to prevent recursion
let s:LoadedProjects = []

if !exists('g:ProjectConfig_NERDTreeIntegration')
    let g:ProjectConfig_NERDTreeIntegration = v:true
endif

function s:LoadProjectConfigApi()
    if v:version < 901
	" ProjectConfigApi uses Vim9 script, but Git Bash cames with vim 8.2
	return
    endif

    let l:script_base = expand('<script>:r')

    source `=fnameescape(l:script_base .. 'Api.vim')`
    source `=fnameescape(l:script_base .. 'Api_DependencyWalker.vim')`
    source `=fnameescape(l:script_base .. 'Api_VimPath.vim')`
    source `=fnameescape(l:script_base .. 'Api_CTags.vim')`
    source `=fnameescape(l:script_base .. 'Api_CScope.vim')`
    source `=fnameescape(l:script_base .. 'Api_C_Cxx_Lib.vim')`

    let s:LoadConfigApi = { -> 0 }
endfunction

let s:LoadConfigApi = funcref('s:LoadProjectConfigApi')

function s:ApplyProjectConfigScript(full_path, project)
    if s:ProjectConfig_ApplyScript
	return
    else
	let s:ProjectConfig_ApplyScript = v:true

	call s:LoadConfigApi()

	try
	    for l:configData in s:ProjectConfigScript
		if a:full_path =~ l:configData.pathname_pattern
		    if has_key(l:configData, 'project_script')
			try
			    if !!strlen(l:configData.project_script)
				if has_key(l:configData, 'directory_name')
				    let g:ProjectConfig_Directory = l:configData.directory_name
				else
				    let g:ProjectConfig_Directory = ''
				endif
				let g:ProjectConfig_Project = l:configData.project_name

				if has_key(l:configData, 'cd')
				    let l:WorkingDirectory = getcwd()

				    if tr(l:WorkingDirectory, '\', '/') != g:ProjectConfig_Directory
					lchdir `=fnameescape(g:ProjectConfig_Directory)`    " Triggers ApplyProjectConfig() again
				    endif
				endif

				if index(s:LoadedProjects, l:configData.project_name) < 0
				    call add(s:LoadedProjects, l:configData.project_name)
				    try
					source `=fnameescape(l:configData.project_script)`
				    finally
					if has_key(l:configData, 'cd') && tr(l:WorkingDirectory, '\', '/') != g:ProjectConfig_Directory
					    lchdir `=fnameescape(l:WorkingDirectory)`
					endif
				    endtry
				endif

				unlet g:ProjectConfig_Directory
				unlet g:ProjectConfig_Project
			    endif
			finally
			    unlet l:configData.project_script
			endtry
		    endif

		    if !a:project && has_key(l:configData, 'file_script')
			if has_key(l:configData, 'exclude_list')
			    let l:exclude_files = l:configData.exclude_list
			else
			    let l:exclude_files = [ ]
			endif

			if !!strlen(l:configData.file_script)
			    if index(l:exclude_files, fnamemodify(bufname('%'), ':t')) == -1
				if has_key(l:configData, 'directory_name')
				    let g:ProjectConfig_Directory = l:configData.directory_name
				else
				    let g:ProjectConfig_Directory = ''
				endif
				let g:ProjectConfig_Project = l:configData.project_name

				source `=fnameescape(l:configData.file_script)`

				unlet g:ProjectConfig_Directory
				unlet g:ProjectConfig_Project
			    endif
			endif
		    endif
		endif
	    endfor
	finally
	    let s:ProjectConfig_ApplyScript = v:false
	endtry
    endif
endfunction

function ProjectConfig#Completion(ArgLead, CmdLine, CursorPos)
    let l:result_lines = ''

    for l:configData in s:ProjectConfigScript
	if strlen(l:result_lines)
	    let l:result_lines .= "\n"
	endif

	let l:result_lines .= l:configData.project_name
    endfor

    return l:result_lines
endfunction

function ProjectConfig#FindLoad(project_name)
    for configData in s:ProjectConfigScript
	if configData.project_name == a:project_name && strlen(configData.directory_name)
	    cd `=fnameescape(configData.directory_name)`
	    if g:ProjectConfig_NERDTreeIntegration && exists(':NERDTreeCWD')
		:NERDTreeCWD
	    else
		edit .
	    endif
	    break
	endif
    endfor
endfunction

function ProjectConfig#NERDTreeListener(event)
    call s:ApplyProjectConfigScript(tr(a:event.nerdtree.root.path.str(), '\', '/'), v:true)
endfunction

function s:AddNERDTreeListener()
    if exists('g:NERDTreePathNotifier')
	call g:NERDTreePathNotifier.AddListener('init', 'ProjectConfig#NERDTreeListener')
	call g:NERDTreePathNotifier.AddListener('refresh', 'ProjectConfig#NERDTreeListener')
    endif

    if exists('b:NERDTree')
	call s:ApplyProjectConfigScript(tr(b:NERDTree.root.path.str(), '\', '/'), v:true)
    endif
endfunction

function s:AddVimListeners()
    if exists('s:VimListenersAdded')
	return
    endif

    let s:VimListenersAdded = v:true

    augroup ProjectConfig
	autocmd BufNewFile,BufRead * call s:ApplyProjectConfigScript(expand('%:p:gs#\#/#'), v:false)
	autocmd DirChanged	   * call s:ApplyProjectConfigScript(tr(getcwd(), '\', '/'), v:true)
	if g:ProjectConfig_NERDTreeIntegration
	    autocmd VimEnter           * call s:AddNERDTreeListener()
	endif
	autocmd VimEnter           * call s:ApplyProjectConfigScript(tr(getcwd(), '\', '/'), v:true)
    augroup END
endfunction

function ProjectConfig#SetScript(project_name, ...)
    let l:keep_pwd = v:false

    if a:0
	let l:project_name = a:project_name
	let l:directory_name = a:1
    else
	let l:directory_name = a:project_name
	let l:project_name = fnamemodify(l:directory_name, ':t:r')
    endif

    if a:0 > 1
	let l:project_script = a:2

	if a:0 > 2
	    let l:file_script = a:3
	endif

	if a:0 > 3
	    let l:keep_pwd = !!a:4
	endif
    else
	if (has('win32') || has('win64')) && isdirectory(expand('~\vimfiles'))
	    let l:project_script = expand('~\vimfiles\project\' .. l:project_name .. '.vim')
	else
	    let l:project_script = expand('~/.vim/project/' .. l:project_name .. '.vim')
	endif
    endif

    if !exists('l:file_script')
	if (has('win32') || has('win64')) && filereadable(fnamemodify(l:project_script, ':r') .. '_files.vim')
		let l:file_script = fnamemodify(l:project_script, ':r') .. '_files.vim'
	else
	    if filereadable(fnamemodify(l:project_script, ':r') .. '.files.vim')
		let l:file_script = fnamemodify(l:project_script, ':r') .. '.files.vim'
	    else
		let l:file_script = ''
	    endif
	endif
    endif

    call add
	\ (
	\     s:ProjectConfigScript,
	\
	\     {
	\	  'project_name'    : l:project_name,
	\	  'directory_name'  : fnamemodify(l:directory_name, ':p:gs#\#/#:s#/$##'),
	\         'pathname_pattern': '\V\^' .. fnamemodify(l:directory_name, ':p:gs#\#/#:s#/$##') .. '\v((/.*)?/([^.][^/]*))?$',
	\         'file_script'     : !!strlen(l:file_script) ? fnamemodify(l:file_script, ':p') : '',
	\         'exclude_list'    : ['COMMIT_EDITMSG', 'MERGE_MSG'],
	\	  'project_script'  : !!strlen(l:project_script) ? fnamemodify(l:project_script, ':p') : ''
	\     }
	\ )

    if !l:keep_pwd
	let s:ProjectConfigScript[-1].cd = v:true
    endif

    call s:AddVimListeners()
endfunction

function g:ProjectConfig_DebugVariables()
    let g:ProjectConfigScript = s:ProjectConfigScript
    let g:ProjectConfig_ApplyScript = s:ProjectConfig_ApplyScript
endfunction
