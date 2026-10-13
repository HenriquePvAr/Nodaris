' SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
' SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
' Launcher GUI minimo: executa o supervisor sem criar janela de console.
Option Explicit

Dim shell, fileSystem, scriptDirectory, repositoryRoot, supervisorPath
Dim powershellPath, commandLine

Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

scriptDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
repositoryRoot = fileSystem.GetAbsolutePathName(fileSystem.BuildPath(scriptDirectory, "..\.."))
supervisorPath = fileSystem.BuildPath(scriptDirectory, "supervisor.ps1")
powershellPath = shell.ExpandEnvironmentStrings("%WINDIR%") & _
  "\System32\WindowsPowerShell\v1.0\powershell.exe"

commandLine = Chr(34) & powershellPath & Chr(34) & _
  " -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File " & _
  Chr(34) & supervisorPath & Chr(34)

shell.CurrentDirectory = repositoryRoot
shell.Run commandLine, 0, False
