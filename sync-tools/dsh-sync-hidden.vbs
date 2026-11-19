' Run dsh-sync.sh through Git Bash without showing a console window.
'
' Task Scheduler starts console programs visibly: a scheduled bash.exe pops a
' black window every time it runs. wscript is a GUI process, and passing window
' style 0 to WScript.Shell.Run starts bash with SW_HIDE, so nothing flashes.
'
' Usage (the installer builds exactly this command line):
'   wscript //B //Nologo dsh-sync-hidden.vbs <bash.exe> <dsh-sync.sh> <profile>
'
' The exit code is dsh-sync.sh's own, so Task Scheduler still reports failures.
Option Explicit

Dim shell, bash, script, profile, commandLine, rc

If WScript.Arguments.Count < 3 Then
    WScript.Echo "usage: wscript dsh-sync-hidden.vbs <bash.exe> <dsh-sync.sh> <profile>"
    WScript.Quit 2
End If

bash = WScript.Arguments(0)
script = WScript.Arguments(1)
profile = WScript.Arguments(2)

commandLine = Chr(34) & bash & Chr(34) & " -lc " & Chr(34) & _
    "DSH_SYNC_PROFILE='" & profile & "' '" & script & "' sync" & Chr(34)

Set shell = CreateObject("WScript.Shell")
' 0 = hidden window, True = wait for the exit code.
rc = shell.Run(commandLine, 0, True)
WScript.Quit rc
