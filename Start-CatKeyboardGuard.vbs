Option Explicit

Dim shell, fso, scriptDir, executablePath, command
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
executablePath = fso.BuildPath(scriptDir, "CatKeyboardGuard.exe")

If fso.FileExists(executablePath) Then
    command = """" & executablePath & """"
Else
    command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File """ _
        & fso.BuildPath(scriptDir, "CatKeyboardGuard.ps1") & """"
End If

shell.Run command, 0, False
