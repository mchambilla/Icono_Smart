# SmartSouth Tray

## Estructura

- `dist\SmartSouthTray.exe` es el bootstrapper pequeño que se distribuye a las PC.
- El bootstrapper consulta el último Release público de `mchambilla/Icono_Smart` cada vez que se ejecuta.
- Descarga `SmartSouthTray.zip` solo cuando la versión del Release aún no está instalada, la verifica cuando GitHub publica su SHA-256, la instala en `%LOCALAPPDATA%\SmartSouthTray\versions\<tag>` y ejecuta el programa.
- Si GitHub no está disponible, inicia la última versión instalada. Si no existe una copia local, muestra el error.
- El bootstrapper y la aplicación se publican por separado. Las actualizaciones del script no requieren recompilar ni redistribuir el EXE.

## Compilar el EXE

En Windows con .NET Framework 4.x:

```powershell
.\Build-Bootstrapper.ps1
```

El resultado se genera en `dist\SmartSouthTray.exe`. El EXE no contiene el script de la aplicación ni credenciales de GitHub.

## Publicar una versión de la aplicación

1. Genera el ZIP y el EXE:

   ```powershell
   .\Build-Release.ps1 -Version 1.0.1
   .\Build-Bootstrapper.ps1
   ```

2. En GitHub, crea un Release en `mchambilla/Icono_Smart` con la etiqueta `v1.0.1`.
3. Adjunta `dist\SmartSouthTray.zip` al Release con el nombre exacto `SmartSouthTray.zip` y `dist\SmartSouthTray.exe`.
4. Publica el Release. El bootstrapper descargará esa versión en el próximo inicio.

Distribuye `SmartSouthTray.exe` a las PC. Para actualizar la aplicación no hace falta reemplazar ese EXE: publica un nuevo Release con otra etiqueta y el ZIP actualizado.

El ZIP debe contener `SmartSouthTray.ps1`, `Logo.png` y `version.txt` en la raíz (el script de empaquetado lo prepara así). El repositorio debe ser público y tener al menos un Release publicado para que las PC puedan descargarlo sin credenciales ni tokens.

Las versiones instaladas se conservan en carpetas separadas para no reemplazar archivos que otra instancia del programa pueda estar utilizando.
