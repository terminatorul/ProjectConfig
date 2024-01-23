" Vim plugin to apply project specific settings in Vim when working in your
"   project tree.
" Last Change: 2023-jan-22
" Maintainer:  Timothy Madden <terminatorul@gmail.com>
" License:     The unlicense http://unlicense.org/
"
" GetLatestVimScripts: 6093 28595  :AutoInstall: ProjectConfig.vmb

if exists('g:ProjectConfig_PluginLoaded')
    finish
endif

let g:ProjectConfig_PluginLoaded = v:true
let s:save_cpo = &cpoptions
set cpoptions&vim

command -nargs=+ -bar -complete=file				 ProjectConfig	    call ProjectConfig#SetScript(<f-args>)
command -nargs=+ -bar						 ProjectConfigAdd   call ProjectConfig#SetScript(<args>)

command -nargs=1 -bar -complete=custom,ProjectConfig#Completion  ProjectConfigEnter call ProjectConfig#FindLoad(<f-args>)
command -nargs=1 -bar						 ProjectConfigOpen  call ProjectConfig#FindLoad(<args>)

command -nargs=0 -bar						 ProjectConfigList  echo ProjectConfig#Completion('', '', '')

let &cpoptions = s:save_cpo
