' SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
' SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
' Launcher GUI minimo: executa o supervisor sem criar janela de console.
Option Explicit

Dim shell, fileSystem, scriptDirectory, repositoryRoot, supervisorPath
Dim powershellPath, commandLine, processEnvironment, launcherEnteredUtc, launchCallStartedUtc

Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

scriptDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
repositoryRoot = fileSystem.GetAbsolutePathName(fileSystem.BuildPath(scriptDirectory, "..\.."))
supervisorPath = fileSystem.BuildPath(scriptDirectory, "supervisor.ps1")
powershellPath = shell.ExpandEnvironmentStrings("%WINDIR%") & _
  "\System32\WindowsPowerShell\v1.0\powershell.exe"

launcherEnteredUtc = UtcTimestamp()
Set processEnvironment = shell.Environment("PROCESS")
processEnvironment("NODARIS_LAUNCHER_ENTERED_UTC") = launcherEnteredUtc

commandLine = Chr(34) & powershellPath & Chr(34) & _
  " -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File " & _
  Chr(34) & supervisorPath & Chr(34)

shell.CurrentDirectory = repositoryRoot
launchCallStartedUtc = UtcTimestamp()
processEnvironment("NODARIS_LAUNCH_CALL_STARTED_UTC") = launchCallStartedUtc
shell.Run commandLine, 0, False

' A chamada assíncrona retorna após criar o processo; o supervisor registra StartTime
' como referência objetiva do processo criado e remove estas variáveis antes dos filhos.
processEnvironment.Remove("NODARIS_LAUNCHER_ENTERED_UTC")
processEnvironment.Remove("NODARIS_LAUNCH_CALL_STARTED_UTC")

Function UtcTimestamp()
  Dim bias, utcValue
  On Error Resume Next
  bias = CLng(shell.RegRead("HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation\ActiveTimeBias"))
  If Err.Number <> 0 Then
    Err.Clear
    UtcTimestamp = ""
    Exit Function
  End If
  On Error GoTo 0
  utcValue = DateAdd("n", bias, Now)
  UtcTimestamp = Right("0000" & Year(utcValue), 4) & "-" & _
    Right("0" & Month(utcValue), 2) & "-" & Right("0" & Day(utcValue), 2) & "T" & _
    Right("0" & Hour(utcValue), 2) & ":" & Right("0" & Minute(utcValue), 2) & ":" & _
    Right("0" & Second(utcValue), 2) & ".000Z"
End Function
