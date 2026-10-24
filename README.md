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

## Vigencia según GLPI-Agent

Al iniciar SmartSouthTray, se configura el inicio de la aplicación en la clave `Run` del usuario actual de Windows para que se abra en su sesión de escritorio al iniciar sesión. También se registra una tarea en el Programador de tareas que comprueba cada hora el servicio de Windows `glpi-agent`, además de hacerlo al iniciar sesión:

- Si el servicio está en ejecución, se reinicia el período de gracia.
- Si está detenido o no está instalado, comienza un período de 15 días.
- Si continúa detenido al vencer ese plazo, se cierran únicamente las instancias de SmartSouthTray de ese usuario, se elimina la tarea y se borra `%LOCALAPPDATA%\SmartSouthTray`.

La comprobación no requiere privilegios de administrador. Si Windows no permite consultar el estado del servicio, la tarea registra el error y no avanza la desinstalación. Si el equipo está apagado, el plazo transcurre igualmente y se aplica en la siguiente comprobación al volver a iniciar sesión.

El icono se carga desde `Logo.png` incluido junto al script en cada versión instalada. El inicio automático y el estado de la política se configuran para la cuenta de Windows que ejecuta SmartSouthTray. La desinstalación elimina los datos de esa cuenta y su configuración de inicio; no elimina el ejecutable bootstrapper si fue guardado en otra ubicación. Tras la baja, un técnico puede volver a ejecutar manualmente `SmartSouthTray.exe` cuando corresponda.
