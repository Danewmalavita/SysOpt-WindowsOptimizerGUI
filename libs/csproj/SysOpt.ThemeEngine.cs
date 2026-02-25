// ─────────────────────────────────────────────────────────────────────────────
// SysOpt.ThemeEngine — Parsing y metadatos de archivos .theme
// Compilar:  csc /target:library /out:SysOpt.ThemeEngine.dll SysOpt.ThemeEngine.cs
// ─────────────────────────────────────────────────────────────────────────────
using System;
using System.Collections.Generic;
using System.IO;

/// <summary>
/// Motor de temas para SysOpt.  Lee ficheros .theme (formato INI con
/// secciones [meta] y [colors]) y devuelve diccionarios clave→valor.
/// </summary>
public static class ThemeEngine
{
    // ── Parsear sección [colors] ───────────────────────────────────────────
    /// <summary>Devuelve un Dictionary&lt;string,string&gt; con claves de color
    /// (p. ej. BgDeep → #0D0F1A).</summary>
    public static Dictionary<string, string> ParseThemeFile(string path)
    {
        if (string.IsNullOrEmpty(path))
            throw new ArgumentNullException("path");
        if (!File.Exists(path))
            throw new FileNotFoundException("Theme file not found: " + path);

        var colors = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
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
            if (section != "colors") continue;

            int eq = line.IndexOf('=');
            if (eq <= 0) continue;

            string key = line.Substring(0, eq).Trim();
            string val = line.Substring(eq + 1).Trim();

            // Quitar comentarios inline  (#...)
            int hash = val.IndexOf('#', 1);   // ignora el '#' del color
            // Solo cortar si el '#' NO está precedido de nada alfanumérico
            // (es decir, es un comentario, no parte del hex color).
            // Heurística: si el primer carácter es '#' y hash > 0, verificar.
            if (val.Length > 0 && val[0] == '#' && hash > 0)
            {
                // El valor es un color hex; el segundo '#' sería comentario
                // solo si hay espacio antes
                int sp = val.IndexOf(' ', 1);
                if (sp > 0 && sp < hash)
                    val = val.Substring(0, sp).Trim();
            }

            colors[key] = val;
        }
        return colors;
    }

    // ── Parsear sección [meta] ─────────────────────────────────────────────
    /// <summary>Devuelve metadatos del tema (Name, Author, Version).</summary>
    public static Dictionary<string, string> GetThemeMeta(string path)
    {
        if (string.IsNullOrEmpty(path))
            throw new ArgumentNullException("path");
        if (!File.Exists(path))
            throw new FileNotFoundException("Theme file not found: " + path);

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

    // ── Listar temas disponibles ───────────────────────────────────────────
    /// <summary>Devuelve nombres de archivo sin extensión de todos los .theme
    /// en la carpeta indicada.</summary>
    public static string[] ListThemes(string themesFolder)
    {
        if (!Directory.Exists(themesFolder)) return new string[0];
        var files = Directory.GetFiles(themesFolder, "*.theme");
        var names = new string[files.Length];
        for (int i = 0; i < files.Length; i++)
            names[i] = Path.GetFileNameWithoutExtension(files[i]);
        Array.Sort(names, StringComparer.OrdinalIgnoreCase);
        return names;
    }
}
