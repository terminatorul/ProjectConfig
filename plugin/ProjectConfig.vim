" Vim plugin to apply project specific settings in Vim when working in your
"   project tree.
" Last Change: 2023-jan-22
" Maintainer:  Timothy Madden <terminatorul@gmail.com>
" License:     The unlicense http://unlicense.org/
"
" GetLatestVimScripts: 6093 28595  :AutoInstall: ProjectConfig.vmb

if !has('vim9script')
    finish
endif

vim9script

import autoload '../autoload/ProjectConfig.vim' as Config

command -nargs=+ -bar -complete=file				 ProjectConfig	    Config.SetScript(<f-args>)
command -nargs=+ -bar						 ProjectConfigAdd   Config.SetScript(<args>)

command -nargs=1 -bar -complete=custom,ProjectConfig#Completion  ProjectConfigEnter Config.FindLoad(<f-args>)
command -nargs=1 -bar						 ProjectConfigOpen  Config.FindLoad(<args>)

command -nargs=0 -bar						 ProjectConfigList  echo Config.Completion('', '', '')
