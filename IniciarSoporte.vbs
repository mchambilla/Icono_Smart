Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' ── CONFIGURACION DE RUTAS ───────────────────────────────────────────────────
RutaServidor = "\\SERVIDOR\SmartSouth"  ' <--- Cambia esto por la ruta compartida de tu red
RutaLocal    = "C:\SmartSouth"
' ─────────────────────────────────────────────────────────────────────────────

' Crear carpeta local si no existe
If Not fso.FolderExists(RutaLocal) Then
    fso.CreateFolder(RutaLocal)
End If

' Intentar actualizar desde el servidor si hay conexion
On Error Resume Next
If fso.FolderExists(RutaServidor) Then
    VerServidorFile = RutaServidor & "\version.txt"
    VerLocalFile    = RutaLocal & "\version.txt"
    
    NeedUpdate = False
    
    If Not fso.FileExists(VerLocalFile) Then
        NeedUpdate = True
    Else
        Set f1 = fso.OpenTextFile(VerServidorFile, 1)
        VerServidor = Trim(f1.ReadAll)
        f1.Close
        
        Set f2 = fso.OpenTextFile(VerLocalFile, 1)
        VerLocal = Trim(f2.ReadAll)
        f2.Close
        
        If VerServidor <> VerLocal Then
            NeedUpdate = True
        End If
    End If
    
    ' Si hay versión nueva, copiamos los archivos actualizados
    If NeedUpdate Then
        fso.CopyFile RutaServidor & "\SmartSouthTray.ps1", RutaLocal & "\SmartSouthTray.ps1", True
        fso.CopyFile RutaServidor & "\version.txt", RutaLocal & "\version.txt", True
        If fso.FileExists(RutaServidor & "\logo.png") Then
            fso.CopyFile RutaServidor & "\logo.png", RutaLocal & "\logo.png", True
        End If
    End If
End If
On Error GoTo 0

' Ejecutar el script local actualizado
WshShell.Run "powershell.exe -ExecutionPolicy Bypass -File """ & RutaLocal & "\SmartSouthTray.ps1""", 0, False