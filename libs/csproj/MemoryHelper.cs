using System;
using System.Runtime.InteropServices;

/// <summary>
/// SysOpt.MemoryHelper — Win32 API para liberación real de RAM del proceso.
/// Extraído del Add-Type inline de SysOpt v2.5.0 (línea 238).
/// Reemplaza: Add-Type @" ... "@ -ErrorAction SilentlyContinue
/// Uso en PS:  Add-Type -Path ".\libs\SysOpt.MemoryHelper.dll"
/// </summary>
public class MemoryHelper
{
    [DllImport("kernel32.dll")]
    public static extern bool SetSystemFileCacheSize(IntPtr min, IntPtr max, uint flags);

    [DllImport("psapi.dll")]
    public static extern bool EmptyWorkingSet(IntPtr hProcess);

    [DllImport("kernel32.dll")]
    public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);

    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr handle);
}
