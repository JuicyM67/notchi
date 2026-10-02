; Tar bort Tamanotchis hooks ur Claude Codes settings.json och autostarten innan appen avinstalleras
!macro NSIS_HOOK_PREUNINSTALL
  ExecWait '"$INSTDIR\${MAINBINARYNAME}.exe" --uninstall'
!macroend
