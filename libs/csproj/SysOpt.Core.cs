// ─────────────────────────────────────────────────────────────────────────────
// SysOpt.Core — Motor de idiomas + helpers de configuración
// Compilar:  csc /target:library /out:SysOpt.Core.dll SysOpt.Core.cs
// ─────────────────────────────────────────────────────────────────────────────
using System;
using System.Collections.Generic;
using System.IO;

// ═══════════════════════════════════════════════════════════════════════════════
// LangEngine — Parsing de archivos .lang (formato INI: [meta] + [ui])
// ═══════════════════════════════════════════════════════════════════════════════
public static class LangEngine
{
    /// <summary>Parsea la sección [ui] de un archivo .lang.
    /// Devuelve Dictionary&lt;string,string&gt; con clave→texto traducido.</summary>
    public static Dictionary<string, string> ParseLangFile(string path)
    {
        if (string.IsNullOrEmpty(path))
            throw new ArgumentNullException("path");
        if (!File.Exists(path))
            throw new FileNotFoundException("Lang file not found: " + path);

        var strings = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        string section = "";

        foreach (var rawLine in File.ReadAllLines(path))
        {
            var line = rawLine.Trim();
            if (line.Length == 0 || line[0] == '#') continue;

            if (line[0] == '[' && line[line.Length - 1] == ']')
            {
                section = line.Substring(1, line.Length - 2).ToLowerInvariant();
                continue;
            }
            if (section != "ui") continue;

            int eq = line.IndexOf('=');
            if (eq <= 0) continue;

            string key = line.Substring(0, eq).Trim();
            string val = line.Substring(eq + 1).Trim();
            // Convertir \n literal a saltos de línea reales
            val = val.Replace("\\n", "\n");
            strings[key] = val;
        }
        return strings;
    }

    /// <summary>Devuelve metadatos del idioma (Name, Code, Author, Version).</summary>
    public static Dictionary<string, string> GetLangMeta(string path)
    {
        if (string.IsNullOrEmpty(path))
            throw new ArgumentNullException("path");
        if (!File.Exists(path))
            throw new FileNotFoundException("Lang file not found: " + path);

        var meta = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        string section = "";

        foreach (var rawLine in File.ReadAllLines(path))
        {
            var line = rawLine.Trim();
            if (line.Length == 0 || line[0] == '#') continue;

            if (line[0] == '[' && line[line.Length - 1] == ']')
            {
                section = line.Substring(1, line.Length - 2).ToLowerInvariant();
                continue;
            }
            if (section != "meta") continue;

            int eq = line.IndexOf('=');
            if (eq <= 0) continue;

            meta[line.Substring(0, eq).Trim()] = line.Substring(eq + 1).Trim();
        }
        return meta;
    }

    /// <summary>Lista idiomas disponibles (nombres de archivo sin extensión).</summary>
    public static string[] ListLanguages(string langFolder)
    {
        if (!Directory.Exists(langFolder)) return new string[0];
        var files = Directory.GetFiles(langFolder, "*.lang");
        var names = new string[files.Length];
        for (int i = 0; i < files.Length; i++)
            names[i] = Path.GetFileNameWithoutExtension(files[i]);
        Array.Sort(names, StringComparer.OrdinalIgnoreCase);
        return names;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// XamlLoader — Carga de archivos .xaml externos desde .\assets\xaml\
// ═══════════════════════════════════════════════════════════════════════════════
public static class XamlLoader
{
    /// <summary>
    /// Carga un archivo .xaml desde la carpeta xamlFolder y devuelve su contenido
    /// como string listo para pasarlo a XamlReader.Load().
    /// name puede ser "MainWindow", "SplashWindow", "DedupWindow", etc.
    /// </summary>
    public static string Load(string xamlFolder, string name)
    {
        if (string.IsNullOrEmpty(xamlFolder))
            throw new ArgumentNullException("xamlFolder");
        if (string.IsNullOrEmpty(name))
            throw new ArgumentNullException("name");

        // Admite nombre con o sin extensión
        string fileName = name.EndsWith(".xaml", StringComparison.OrdinalIgnoreCase)
            ? name : name + ".xaml";
        string path = Path.Combine(xamlFolder, fileName);

        if (!File.Exists(path))
            throw new FileNotFoundException("XAML file not found: " + path);

        return File.ReadAllText(path, System.Text.Encoding.UTF8);
    }

    /// <summary>Lista los nombres (sin extensión) de todos los .xaml disponibles.</summary>
    public static string[] ListXaml(string xamlFolder)
    {
        if (!Directory.Exists(xamlFolder)) return new string[0];
        var files = Directory.GetFiles(xamlFolder, "*.xaml");
        var names = new string[files.Length];
        for (int i = 0; i < files.Length; i++)
            names[i] = Path.GetFileNameWithoutExtension(files[i]);
        Array.Sort(names, StringComparer.OrdinalIgnoreCase);
        return names;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SettingsHelper — Lectura/escritura de configuración JSON simple
// ═══════════════════════════════════════════════════════════════════════════════
public static class SettingsHelper
{
    /// <summary>Lee un valor de un archivo JSON simple (solo primer nivel).</summary>
    public static string ReadKey(string jsonPath, string key)
    {
        if (!File.Exists(jsonPath)) return null;
        // Parseo ligero para no depender de Newtonsoft
        var text = File.ReadAllText(jsonPath);
        string search = "\"" + key + "\"";
        int idx = text.IndexOf(search, StringComparison.OrdinalIgnoreCase);
        if (idx < 0) return null;
        int colon = text.IndexOf(':', idx + search.Length);
        if (colon < 0) return null;
        int start = text.IndexOf('"', colon + 1);
        if (start < 0) return null;
        int end = text.IndexOf('"', start + 1);
        if (end < 0) return null;
        return text.Substring(start + 1, end - start - 1);
    }
}