vim9script

import './ProjectConfigApi_ProjectModel.vim' as ProjectModel
import './ProjectConfigApi_Generator.vim' as ConfigApi
import './ProjectConfigApi_VimPath.vim' as VimPath
import './ProjectConfigApi_CTags.vim' as CTags
import './ProjectConfigApi_CScope.vim' as CScope
import './ProjectConfigApi_Global.vim' as Global

export type Property = ProjectModel.Property
export type Module = ProjectModel.Module
export type Project = ProjectModel.Project

export const HasWindows: bool = ConfigApi.HasWindows
export const DirectorySeparator: string = ConfigApi.DirectorySeparator
export const DevNull: string = ConfigApi.DevNull

export var JoinPath: func(...list<string>): string = ConfigApi.JoinPath
export var SetProjectConfig: func(string, any): void = ConfigApi.SetProjectConfig
export var CreateModule: func(string, bool): Module = ConfigApi.CreateModule
export var AddModule: func(Module, ...list<Module>): void = ConfigApi.AddModule
export var AddModuleAutoCmd: func(Module, any, list<string>): void = ConfigApi.AddModuleAutoCmd
export var EnableProjectModules: func(string, ...list<string>): void = ConfigApi.EnableProjectModules
