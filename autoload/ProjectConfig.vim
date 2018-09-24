let s:ProjectConfigScript = [ ]

function s:ApplyProjectConfigScript(full_path, project)
    for l:configData in s:ProjectConfigScript
	if a:full_path =~ l:configData.pathname_pattern
	    if has_key(l:configData, 'project_script')
		if !!strlen(l:configData.project_script)
		    if has_key(l:configData, 'directory_name')
			let g:ProjectConfig_Directory = l:configData.directory_name
		    else
			let g:ProjectConfig_Directory = ''
		    endif
		    let g:ProjectConfig_Project = l:configData.project_name

		    source `=fnameescape(configData.project_script)`
		    unlet g:ProjectConfig_Directory
		    unlet g:ProjectConfig_Project
		endif

		unlet l:configData.project_script
	    endif

	    if !a:project && has_key(l:config_data, file_script)
		if has_key(l:configData, 'exclude_list')
		    let l:exclude_files = l:configData.exclude_list
		else
		    let l:exclude_files = [ ] 
		endif

		if index(l:exclude_files, fnamemodify(bufname('%'), ':t')) == -1
		    if has_key(l:configData, 'directory_name')
			let g:ProjectConfig_Directory = l:configData.directory_name
		    else
			let g:ProjectConfig_Directory = ''
		    endif
		    let g:ProjectConfig_Project = l:configData.project_name

		    source `=fnameescape(configData.file_script)`
		    unlet g:ProjectConfig_Directory
		    unlet g:ProjectConfig_Project
		endif
	    endif
	endif
    endfor
endfunction

function ProjectConfig#SetScript(project_name, ...)
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
    else
	if has('win32') || has('win64') && isdirectory(expand('~\vimfiles'))
	    let l:project_script = expand('~\vimfiles\project\' . l:project_name . '.vim')
	else
	    let l:project_script = expand('~/.vim/project/' . l:project_name . '.vim')
	endif
    endif

    if !exists('l:file_script')
	if has('win32') || has('win64')
	    if filereadable(fnamemodify(l:project_script, ':r') . '_files.vim')
		let l:file_script = fnamemodify(l:project_script, ':r') . '_files.vim'
	    endif
	endif

	if !exists('l:file_script')
	    if filereadable(fnamemodify(l:project_script, ':r') . '.files.vim')
		let l:file_script = fnamemodify(l:project_script, ':r') . '.files.vim'
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
	\         'pathname_pattern': '\V\^' . fnamemodify(l:directory_name, ':p:gs#\#/#:s#/$##') . '\v((/.*)?/([^.][^/]*))?$',
	\         'file_script'     : !!strlen(l:file_script) ? fnamemodify(l:file_script, ':p') : '',
	\         'exclude_list'    : ['COMMIT_EDITMSG', 'MERGE_MSG'],
	\	  'project_script'  : !!strlen(l:project_script) ? fnamemodify(l:project_script, ':p') : ''
	\     }
	\ )
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
	    edit .
	    break
	endif
    endfor
endfunction

augroup ProjectConfig
    autocmd BufNewFile,BufRead * call s:ApplyProjectConfigScript(expand('%:p:gs#\#/#'), 0)
    autocmd DirChanged	       * call s:ApplyProjectConfigScript(fnamemodify(getcwd(), ':gs#\#/#'), !0)
    autocmd VimEnter           * call s:ApplyProjectConfigScript(fnamemodify(getcwd(), ':gs#\#/#'), !0)
augroup END
