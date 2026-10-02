using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using System.Diagnostics;

internal static class SmartSouthTrayBootstrapper
{
    private const string Repository = "mchambilla/Icono_Smart";
    private const string AssetName = "SmartSouthTray.zip";
    private const string ReleaseApiUrl = "https://api.github.com/repos/" + Repository + "/releases/latest";
    private const long MaximumDownloadBytes = 50L * 1024L * 1024L;
    private const long MaximumExpandedBytes = 100L * 1024L * 1024L;
    private const int MaximumArchiveEntries = 1000;

    [STAThread]
    private static void Main()
    {
        ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;

        string appRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "SmartSouthTray");
        string versionsRoot = Path.Combine(appRoot, "versions");

        try
        {
            Directory.CreateDirectory(versionsRoot);
            string installPath = UpdateIfNeeded(versionsRoot);
            LaunchApplication(installPath);
        }
        catch (Exception updateError)
        {
            string cachedPath = GetCachedApplication(versionsRoot);
            if (cachedPath != null)
            {
                LaunchApplication(cachedPath);
                MessageBox.Show(
                    "No se pudo comprobar o instalar la última versión. Se inició la versión local disponible.\r\n\r\n" +
                    updateError.Message,
                    "Smart South - Actualización",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning);
                return;
            }

            MessageBox.Show(
                "No se pudo descargar Smart South desde GitHub y no hay una versión local disponible.\r\n\r\n" +
                updateError.Message,
                "Smart South - Error de inicio",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

    private static string UpdateIfNeeded(string versionsRoot)
    {
        IDictionary<string, object> release = GetLatestRelease();
        string tag = ReadString(release, "tag_name");
        if (!Regex.IsMatch(tag, @"^[A-Za-z0-9._-]{1,80}$"))
            throw new InvalidDataException("GitHub devolvió un nombre de versión no válido.");

        IDictionary<string, object> asset = FindReleaseAsset(release);
        string downloadUrl = ReadString(asset, "browser_download_url");
        Uri assetUri;
        if (!Uri.TryCreate(downloadUrl, UriKind.Absolute, out assetUri) ||
            assetUri.Scheme != Uri.UriSchemeHttps ||
            !string.Equals(assetUri.Host, "github.com", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("La dirección de descarga del Release no es válida.");

        string installPath = Path.Combine(versionsRoot, tag);
        if (File.Exists(Path.Combine(installPath, "SmartSouthTray.ps1")))
        {
            WriteCurrentVersion(versionsRoot, tag);
            return installPath;
        }

        string temporaryRoot = Path.Combine(versionsRoot, ".staging-" + Guid.NewGuid().ToString("N"));
        string archivePath = Path.Combine(temporaryRoot, AssetName);
        string extractedPath = Path.Combine(temporaryRoot, "app");

        try
        {
            Directory.CreateDirectory(extractedPath);
            DownloadAsset(assetUri, archivePath);
            VerifyDigest(asset, archivePath);
            ExtractArchive(archivePath, extractedPath);

            if (!File.Exists(Path.Combine(extractedPath, "SmartSouthTray.ps1")))
                throw new InvalidDataException("El ZIP del Release no contiene SmartSouthTray.ps1 en su raíz.");

            if (Directory.Exists(installPath))
                Directory.Delete(installPath, true);
            Directory.Move(extractedPath, installPath);
            WriteCurrentVersion(versionsRoot, tag);
            return installPath;
        }
        finally
        {
            if (Directory.Exists(temporaryRoot))
                Directory.Delete(temporaryRoot, true);
        }
    }

    private static IDictionary<string, object> GetLatestRelease()
    {
        HttpWebRequest request = (HttpWebRequest)WebRequest.Create(ReleaseApiUrl);
        request.Method = "GET";
        request.UserAgent = "SmartSouthTrayBootstrapper/1.0";
        request.Accept = "application/vnd.github+json";
        request.Timeout = 15000;
        request.ReadWriteTimeout = 15000;

        using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
        using (Stream stream = response.GetResponseStream())
        using (StreamReader reader = new StreamReader(stream, Encoding.UTF8))
        {
            JavaScriptSerializer serializer = new JavaScriptSerializer();
            object parsed = serializer.DeserializeObject(reader.ReadToEnd());
            IDictionary<string, object> release = parsed as IDictionary<string, object>;
            if (release == null)
                throw new InvalidDataException("La respuesta de GitHub no tiene el formato esperado.");
            return release;
        }
    }

    private static IDictionary<string, object> FindReleaseAsset(IDictionary<string, object> release)
    {
        object rawAssets;
        if (!release.TryGetValue("assets", out rawAssets))
            throw new InvalidDataException("El último Release no contiene archivos descargables.");

        object[] assets = rawAssets as object[];
        if (assets == null)
            throw new InvalidDataException("La lista de archivos del Release no es válida.");

        foreach (object rawAsset in assets)
        {
            IDictionary<string, object> asset = rawAsset as IDictionary<string, object>;
            if (asset != null && string.Equals(ReadString(asset, "name"), AssetName, StringComparison.Ordinal))
                return asset;
        }

        throw new InvalidDataException("El último Release no incluye el archivo " + AssetName + ".");
    }

    private static string ReadString(IDictionary<string, object> values, string key)
    {
        object value;
        if (!values.TryGetValue(key, out value) || value == null)
            throw new InvalidDataException("Falta el campo '" + key + "' en la respuesta de GitHub.");
        return Convert.ToString(value);
    }

    private static void DownloadAsset(Uri uri, string destination)
    {
        HttpWebRequest request = (HttpWebRequest)WebRequest.Create(uri);
        request.Method = "GET";
        request.UserAgent = "SmartSouthTrayBootstrapper/1.0";
        request.Timeout = 30000;
        request.ReadWriteTimeout = 30000;

        using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
        {
            if (response.ContentLength > MaximumDownloadBytes)
                throw new InvalidDataException("El paquete supera el tamaño máximo permitido.");

            using (Stream input = response.GetResponseStream())
            using (FileStream output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write))
            {
                byte[] buffer = new byte[81920];
                long total = 0;
                int read;
                while ((read = input.Read(buffer, 0, buffer.Length)) > 0)
                {
                    total += read;
                    if (total > MaximumDownloadBytes)
                        throw new InvalidDataException("El paquete supera el tamaño máximo permitido.");
                    output.Write(buffer, 0, read);
                }
            }
        }
    }

    private static void VerifyDigest(IDictionary<string, object> asset, string archivePath)
    {
        object rawDigest;
        if (!asset.TryGetValue("digest", out rawDigest) || rawDigest == null)
            return;

        string digest = Convert.ToString(rawDigest);
        Match match = Regex.Match(digest, @"^sha256:([0-9a-fA-F]{64})$");
        if (!match.Success)
            throw new InvalidDataException("GitHub devolvió un checksum SHA-256 no válido.");

        using (SHA256 sha256 = SHA256.Create())
        using (FileStream stream = File.OpenRead(archivePath))
        {
            string actual = BitConverter.ToString(sha256.ComputeHash(stream)).Replace("-", "");
            if (!string.Equals(actual, match.Groups[1].Value, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("El checksum SHA-256 del paquete no coincide.");
        }
    }

    private static void ExtractArchive(string archivePath, string destination)
    {
        string canonicalRoot = Path.GetFullPath(destination) + Path.DirectorySeparatorChar;
        long expandedBytes = 0;
        int entryCount = 0;

        using (FileStream file = File.OpenRead(archivePath))
        using (ZipArchive archive = new ZipArchive(file, ZipArchiveMode.Read))
        {
            foreach (ZipArchiveEntry entry in archive.Entries)
            {
                entryCount++;
                if (entryCount > MaximumArchiveEntries)
                    throw new InvalidDataException("El ZIP contiene demasiados archivos.");

                string relativePath = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
                if (Path.IsPathRooted(relativePath) ||
                    relativePath.Split(Path.DirectorySeparatorChar).Length == 0)
                    throw new InvalidDataException("El ZIP contiene una ruta no permitida.");

                foreach (string part in relativePath.Split(Path.DirectorySeparatorChar))
                {
                    if (part == "..")
                        throw new InvalidDataException("El ZIP contiene una ruta no permitida.");
                }

                string targetPath = Path.GetFullPath(Path.Combine(destination, relativePath));
                if (!targetPath.StartsWith(canonicalRoot, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException("El ZIP contiene una ruta fuera de la carpeta de instalación.");

                if (entry.FullName.EndsWith("/", StringComparison.Ordinal))
                {
                    Directory.CreateDirectory(targetPath);
                    continue;
                }

                expandedBytes += entry.Length;
                if (expandedBytes > MaximumExpandedBytes)
                    throw new InvalidDataException("El contenido expandido supera el tamaño máximo permitido.");

                string parent = Path.GetDirectoryName(targetPath);
                if (!Directory.Exists(parent))
                    Directory.CreateDirectory(parent);

                using (Stream input = entry.Open())
                using (FileStream output = new FileStream(targetPath, FileMode.CreateNew, FileAccess.Write))
                    input.CopyTo(output);
            }
        }
    }

    private static void WriteCurrentVersion(string versionsRoot, string tag)
    {
        string currentPath = Path.Combine(versionsRoot, "current.txt");
        string temporaryPath = currentPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
        File.WriteAllText(temporaryPath, tag, Encoding.UTF8);
        if (File.Exists(currentPath))
            File.Delete(currentPath);
        File.Move(temporaryPath, currentPath);
    }

    private static string GetCachedApplication(string versionsRoot)
    {
        string currentPath = Path.Combine(versionsRoot, "current.txt");
        if (!File.Exists(currentPath))
            return null;

        string tag = File.ReadAllText(currentPath, Encoding.UTF8).Trim();
        if (!Regex.IsMatch(tag, @"^[A-Za-z0-9._-]{1,80}$"))
            return null;

        string appPath = Path.Combine(versionsRoot, tag);
        if (File.Exists(Path.Combine(appPath, "SmartSouthTray.ps1")))
            return appPath;
        return null;
    }

    private static void LaunchApplication(string installPath)
    {
        string scriptPath = Path.Combine(installPath, "SmartSouthTray.ps1");
        ProcessStartInfo startInfo = new ProcessStartInfo();
        startInfo.FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell\\v1.0\\powershell.exe");
        startInfo.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + scriptPath + "\"";
        startInfo.WorkingDirectory = installPath;
        startInfo.UseShellExecute = false;
        startInfo.CreateNoWindow = true;

        Process.Start(startInfo);
    }
}
