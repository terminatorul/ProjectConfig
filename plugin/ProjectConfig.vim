
command -nargs=+ -bar -complete=file				 ProjectConfig	    call ProjectConfig#SetScript(<f-args>)
command -nargs=+ -bar						 ProjectConfigAdd   call ProjectConfig#SetScript(<args>)

command -nargs=1 -bar -complete=custom,ProjectConfig#Completion  ProjectConfigEnter call ProjectConfig#FindLoad(<f-args>)
command -nargs=1 -bar						 ProjectConfigOpen  call ProjectConfig#FindLoad(<args>)

command -nargs=0 -bar						 ProjectConfigList  echo ProjectConfig#Completion('', '', '')

