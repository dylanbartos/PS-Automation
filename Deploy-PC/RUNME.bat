if exist "C:\Deploy-PC\" GOTO copyFile
mkdir "C:\Deploy-PC"
:copyFile
xcopy ".\*" "C:\Deploy-PC" /Y
call "C:\Deploy-PC\Deploy-PC.lnk"

