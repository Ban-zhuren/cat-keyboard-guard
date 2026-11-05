param(
    [switch]$SelfTest
)

# Cat Keyboard Guard - a small Windows tray utility with no external dependencies.
# The UI strings are JSON escaped so Windows PowerShell 5.1 can load this UTF-8 file safely.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$nativeSource = @'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace CatKeyboardGuard
{
    public static class KeyboardHook
    {
        private const int WH_KEYBOARD_LL = 13;
        private const int WM_KEYDOWN = 0x0100;
        private const int WM_KEYUP = 0x0101;
        private const int WM_SYSKEYDOWN = 0x0104;
        private const int WM_SYSKEYUP = 0x0105;
        private const int VK_LCONTROL = 0xA2;
        private const int VK_RCONTROL = 0xA3;
        private const int VK_LMENU = 0xA4;
        private const int VK_RMENU = 0xA5;
        private const int VK_U = 0x55;
        private const int LLKHF_INJECTED = 0x10;
        private const int SM_REMOTESESSION = 0x1000;

        private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

        private static readonly LowLevelKeyboardProc Callback = HookCallback;
        private static IntPtr hookId = IntPtr.Zero;
        private static bool controlDown;
        private static bool altDown;
        private static bool uDown;
        private static long unlockStarted;
        private static bool blocking;

        public static bool Blocking
        {
            get { return blocking; }
            set
            {
                blocking = value;
                if (!value) ResetUnlockState();
            }
        }

        public static bool AllowRemoteInput { get; set; }
        public static bool UnlockRequested { get; set; }

        public static bool UnlockChordReady
        {
            get
            {
                if (!blocking || !controlDown || !altDown || !uDown || unlockStarted == 0)
                    return false;

                long elapsed = Stopwatch.GetTimestamp() - unlockStarted;
                return elapsed * 1000 / Stopwatch.Frequency >= 2000;
            }
        }

        public static void Install()
        {
            if (hookId != IntPtr.Zero) return;

            using (Process currentProcess = Process.GetCurrentProcess())
            using (ProcessModule currentModule = currentProcess.MainModule)
            {
                IntPtr moduleHandle = GetModuleHandle(currentModule.ModuleName);
                hookId = SetWindowsHookEx(WH_KEYBOARD_LL, Callback, moduleHandle, 0);
            }

            if (hookId == IntPtr.Zero)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to install keyboard hook.");
        }

        public static void Uninstall()
        {
            Blocking = false;
            if (hookId == IntPtr.Zero) return;
            UnhookWindowsHookEx(hookId);
            hookId = IntPtr.Zero;
        }

        private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
        {
            if (nCode >= 0 && Blocking)
            {
                int message = wParam.ToInt32();
                bool isDown = message == WM_KEYDOWN || message == WM_SYSKEYDOWN;
                bool isUp = message == WM_KEYUP || message == WM_SYSKEYUP;
                int vkCode = Marshal.ReadInt32(lParam);
                int flags = Marshal.ReadInt32(lParam, 8);
                bool isInjected = (flags & LLKHF_INJECTED) != 0;

                // RDP input is already isolated from the physical console. Most shared-desktop
                // tools use injected input; let those events through while blocking hardware keys.
                if (AllowRemoteInput && (isInjected || GetSystemMetrics(SM_REMOTESESSION) != 0))
                    return CallNextHookEx(hookId, nCode, wParam, lParam);

                if (vkCode == VK_LCONTROL || vkCode == VK_RCONTROL)
                    controlDown = isDown ? true : (isUp ? false : controlDown);
                if (vkCode == VK_LMENU || vkCode == VK_RMENU)
                    altDown = isDown ? true : (isUp ? false : altDown);
                if (vkCode == VK_U)
                    uDown = isDown ? true : (isUp ? false : uDown);

                if (controlDown && altDown && uDown)
                {
                    if (unlockStarted == 0) unlockStarted = Stopwatch.GetTimestamp();
                    if (UnlockChordReady) UnlockRequested = true;
                }
                else
                {
                    unlockStarted = 0;
                }

                return new IntPtr(1);
            }

            ResetUnlockState();
            return CallNextHookEx(hookId, nCode, wParam, lParam);
        }

        private static void ResetUnlockState()
        {
            controlDown = false;
            altDown = false;
            uDown = false;
            unlockStarted = 0;
        }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc callback, IntPtr module, uint threadId);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnhookWindowsHookEx(IntPtr hook);

        [DllImport("user32.dll")]
        private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern IntPtr GetModuleHandle(string moduleName);

        [DllImport("user32.dll")]
        private static extern int GetSystemMetrics(int index);
    }

    public static class FunctionKeyBlocker
    {
        private const int WM_HOTKEY = 0x0312;
        private const uint MOD_NOREPEAT = 0x4000;
        private const int ERROR_HOTKEY_ALREADY_REGISTERED = 1409;

        // Standard Windows virtual keys emitted by notebook Fn/media controls.
        // OEM airplane-mode keys commonly map to VK_WLAN (0xE0); some vendors
        // expose it as a custom key and cannot be intercepted at this layer.
        private static readonly int[] FunctionKeys = new int[]
        {
            0x77, // VK_F8 (Lenovo airplane-mode row when hotkey mode is enabled)
            0xAD, // VK_VOLUME_MUTE
            0xAE, // VK_VOLUME_DOWN
            0xAF, // VK_VOLUME_UP
            0xB0, // VK_MEDIA_NEXT_TRACK
            0xB1, // VK_MEDIA_PREV_TRACK
            0xB2, // VK_MEDIA_STOP
            0xB3, // VK_MEDIA_PLAY_PAUSE
            0xB4, // VK_LAUNCH_MAIL
            0xB5, // VK_LAUNCH_MEDIA_SELECT
            0xB6, // VK_LAUNCH_APP1
            0xB7, // VK_LAUNCH_APP2
            0xCE, // vendor/Windows brightness down
            0xCF, // vendor/Windows brightness up
            0xE0, // VK_WLAN / wireless radio
            0xE1, // VK_BROWSER_SEARCH (some OEM Fn rows)
            0xE2, // VK_BROWSER_FAVORITES
            0xE3, // VK_BROWSER_HOME / display switch on some laptops
            0xE4, // VK_VOLUME_MUTE on some OEM layouts
            0xE5, // VK_LAUNCH_APP1 on some OEM layouts
            0xE6, // VK_LAUNCH_APP2 on some OEM layouts
            0xE7, // VK_MEDIA_SELECT / power on some OEM layouts
            0x5F  // VK_SLEEP
        };

        private sealed class HotkeyWindow : NativeWindow
        {
            protected override void WndProc(ref Message message)
            {
                if (message.Msg == WM_HOTKEY)
                {
                    // Deliberately swallow the hotkey. RegisterHotKey has already
                    // claimed it, so Windows will not execute the system action.
                    return;
                }

                base.WndProc(ref message);
            }
        }

        private static HotkeyWindow window;
        private static readonly List<int> RegisteredIds = new List<int>();

        public static int InstalledCount { get { return RegisteredIds.Count; } }

        public static void Install()
        {
            if (window != null) return;

            window = new HotkeyWindow();
            window.CreateHandle(new CreateParams());

            for (int index = 0; index < FunctionKeys.Length; index++)
            {
                int id = 0x4B00 + index;
                if (RegisterHotKey(window.Handle, id, MOD_NOREPEAT, (uint)FunctionKeys[index]))
                    RegisteredIds.Add(id);
            }

            if (RegisteredIds.Count == 0)
            {
                window.DestroyHandle();
                window = null;
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to reserve notebook function keys.");
            }
        }

        public static void Uninstall()
        {
            if (window == null) return;

            foreach (int id in RegisteredIds)
                UnregisterHotKey(window.Handle, id);
            RegisteredIds.Clear();
            window.DestroyHandle();
            window = null;
        }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint virtualKey);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    }

    public static class RadioGuard
    {
        // wlan_intf_opcode_radio_state.  Lenovo's Fn+F8 may be handled by
        // firmware/service code and never reach WH_KEYBOARD_LL, so the guard
        // also repairs a software-radio transition while protection is on.
        private const int WLAN_INTF_OPCODE_RADIO_STATE = 4;
        private const int DOT11_RADIO_STATE_ON = 1;
        private const int DOT11_RADIO_STATE_OFF = 2;
        private const int RADIO_ENTRY_SIZE = 12; // phy index + software + hardware

        private static readonly object SyncRoot = new object();
        private static IntPtr clientHandle = IntPtr.Zero;
        private static bool active;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct WlanInterfaceInfo
        {
            public Guid InterfaceGuid;

            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
            public string Description;

            public int State;
        }

        public static bool Available
        {
            get { lock (SyncRoot) return clientHandle != IntPtr.Zero; }
        }

        public static bool Start()
        {
            lock (SyncRoot)
            {
                if (clientHandle != IntPtr.Zero)
                {
                    active = true;
                    return true;
                }

                uint negotiatedVersion;
                IntPtr handle;
                int status = WlanOpenHandle(2, IntPtr.Zero, out negotiatedVersion, out handle);
                if (status != 0 || handle == IntPtr.Zero)
                    return false;

                clientHandle = handle;
                active = true;
                return true;
            }
        }

        public static bool Restore()
        {
            lock (SyncRoot)
            {
                if (!active && !Start())
                    return false;

                IntPtr interfaceList = IntPtr.Zero;
                try
                {
                    int status = WlanEnumInterfaces(clientHandle, IntPtr.Zero, out interfaceList);
                    if (status != 0 || interfaceList == IntPtr.Zero)
                        return false;

                    int interfaceCount = Marshal.ReadInt32(interfaceList);
                    if (interfaceCount < 0 || interfaceCount > 128)
                        return false;

                    IntPtr interfaceItems = IntPtr.Add(interfaceList, 8);
                    int interfaceSize = Marshal.SizeOf(typeof(WlanInterfaceInfo));
                    bool allHealthy = true;

                    for (int index = 0; index < interfaceCount; index++)
                    {
                        WlanInterfaceInfo info = (WlanInterfaceInfo)Marshal.PtrToStructure(
                            IntPtr.Add(interfaceItems, index * interfaceSize),
                            typeof(WlanInterfaceInfo));

                        IntPtr radioState = IntPtr.Zero;
                        try
                        {
                            int dataSize;
                            status = WlanQueryInterface(
                                clientHandle,
                                ref info.InterfaceGuid,
                                WLAN_INTF_OPCODE_RADIO_STATE,
                                IntPtr.Zero,
                                out dataSize,
                                out radioState,
                                IntPtr.Zero);
                            if (status != 0 || radioState == IntPtr.Zero || dataSize < 4)
                            {
                                allHealthy = false;
                                continue;
                            }

                            int radioCount = Marshal.ReadInt32(radioState);
                            int maxRadioCount = (dataSize - 4) / RADIO_ENTRY_SIZE;
                            if (radioCount < 0 || radioCount > maxRadioCount)
                            {
                                allHealthy = false;
                                continue;
                            }

                            bool changed = false;
                            for (int radioIndex = 0; radioIndex < radioCount; radioIndex++)
                            {
                                int entryOffset = 4 + (radioIndex * RADIO_ENTRY_SIZE);
                                int softwareState = Marshal.ReadInt32(radioState, entryOffset + 4);
                                int hardwareState = Marshal.ReadInt32(radioState, entryOffset + 8);

                                // Hardware-off cannot be repaired from user mode;
                                // software-off with hardware still on can.
                                if (softwareState == DOT11_RADIO_STATE_OFF &&
                                    hardwareState != DOT11_RADIO_STATE_OFF)
                                {
                                    Marshal.WriteInt32(radioState, entryOffset + 4, DOT11_RADIO_STATE_ON);
                                    changed = true;
                                }
                            }

                            if (changed)
                            {
                                int setStatus = WlanSetInterface(
                                    clientHandle,
                                    ref info.InterfaceGuid,
                                    WLAN_INTF_OPCODE_RADIO_STATE,
                                    dataSize,
                                    radioState,
                                    IntPtr.Zero);
                                if (setStatus != 0)
                                    allHealthy = false;
                            }
                        }
                        finally
                        {
                            if (radioState != IntPtr.Zero)
                                WlanFreeMemory(radioState);
                        }
                    }

                    return allHealthy;
                }
                finally
                {
                    if (interfaceList != IntPtr.Zero)
                        WlanFreeMemory(interfaceList);
                }
            }
        }

        public static void Stop()
        {
            lock (SyncRoot)
            {
                active = false;
                if (clientHandle != IntPtr.Zero)
                {
                    WlanCloseHandle(clientHandle, IntPtr.Zero);
                    clientHandle = IntPtr.Zero;
                }
            }
        }

        [DllImport("wlanapi.dll", SetLastError = true)]
        private static extern int WlanOpenHandle(
            uint clientVersion,
            IntPtr reserved,
            out uint negotiatedVersion,
            out IntPtr clientHandle);

        [DllImport("wlanapi.dll", SetLastError = true)]
        private static extern int WlanCloseHandle(IntPtr clientHandle, IntPtr reserved);

        [DllImport("wlanapi.dll", SetLastError = true)]
        private static extern int WlanEnumInterfaces(
            IntPtr clientHandle,
            IntPtr reserved,
            out IntPtr interfaceList);

        [DllImport("wlanapi.dll", SetLastError = true)]
        private static extern int WlanQueryInterface(
            IntPtr clientHandle,
            ref Guid interfaceGuid,
            int opcode,
            IntPtr reserved,
            out int dataSize,
            out IntPtr data,
            IntPtr valueType);

        [DllImport("wlanapi.dll", SetLastError = true)]
        private static extern int WlanSetInterface(
            IntPtr clientHandle,
            ref Guid interfaceGuid,
            int opcode,
            int dataSize,
            IntPtr data,
            IntPtr reserved);

        [DllImport("wlanapi.dll")]
        private static extern void WlanFreeMemory(IntPtr memory);
    }

    public static class AppIdentity
    {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
    }
}
'@

Add-Type -TypeDefinition $nativeSource -Language CSharp -ReferencedAssemblies ([System.Windows.Forms.Form].Assembly.Location)

if ($SelfTest) {
    [CatKeyboardGuard.KeyboardHook]::Install()
    [CatKeyboardGuard.FunctionKeyBlocker]::Install()
    if ([CatKeyboardGuard.FunctionKeyBlocker]::InstalledCount -lt 1) {
        throw 'FUNCTION_KEY_BLOCKER_NOT_INSTALLED'
    }
    [CatKeyboardGuard.RadioGuard]::Start() | Out-Null
    [CatKeyboardGuard.RadioGuard]::Restore() | Out-Null
    [CatKeyboardGuard.RadioGuard]::Stop()
    [CatKeyboardGuard.KeyboardHook]::Blocking = $false
    [CatKeyboardGuard.FunctionKeyBlocker]::Uninstall()
    [CatKeyboardGuard.KeyboardHook]::Uninstall()
    Write-Output 'SELF_TEST_OK'
    exit 0
}

# Give the PowerShell-hosted window its own taskbar identity instead of grouping it
# under powershell.exe. The WinForms window icon can then be used by the taskbar.
[CatKeyboardGuard.AppIdentity]::SetCurrentProcessExplicitAppUserModelID('CatKeyboardGuard.Desktop') | Out-Null

$createdNew = $false
$instanceMutex = New-Object System.Threading.Mutex($true, 'Local\CatKeyboardGuard-72446786', [ref]$createdNew)
if (-not $createdNew) {
    [System.Windows.Forms.MessageBox]::Show(
        ([char[]](0x7A0B,0x5E8F,0x5DF2,0x5728,0x8FD0,0x884C,0x3002) -join ''),
        'Cat Keyboard Guard',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
    exit 0
}

$ui = ConvertFrom-Json @'
{
  "title": "\u732b\u54aa\u952e\u76d8\u5b88\u62a4",
  "subtitle": "\u62e6\u622a\u672c\u673a\u7269\u7406\u952e\u76d8\uff0c\u4fdd\u7559\u8fdc\u7a0b\u8fde\u63a5\u5de5\u4f5c\u3002",
  "ready": "\u5f53\u524d\u72b6\u6001\uff1a\u672a\u9501\u5b9a",
  "locked": "\u5f53\u524d\u72b6\u6001\uff1a\u952e\u76d8\u5df2\u9501\u5b9a",
  "guardButton": "\u5f00\u542f\u672c\u673a\u952e\u76d8\u4fdd\u62a4",
  "autoUnlock": "\u81ea\u52a8\u89e3\u9501",
  "minutes": "\u5206\u949f",
  "startup": "\u5f00\u673a\u81ea\u52a8\u542f\u52a8",
  "remoteInput": "\u5141\u8bb8\u8fdc\u7a0b\u63a7\u5236\u8f6f\u4ef6\u7684\u952e\u76d8\u8f93\u5165\uff08\u63a8\u8350\uff09",
  "tip": "\u4fdd\u62a4\u5f00\u542f\u540e\uff0c\u97f3\u91cf\u3001\u9759\u97f3\u3001\u4eae\u5ea6\u3001\u5a92\u4f53\u3001\u65e0\u7ebf\u3001F8 \u548c\u7761\u7720\u7b49\u529f\u80fd\u952e\u4f1a\u5c3d\u91cf\u7981\u7528\uff1b\u5982\u679c\u5382\u5546\u670d\u52a1\u4ecd\u5c06\u98de\u884c\u6a21\u5f0f\u5207\u6362\uff0c\u7a0b\u5e8f\u4f1a\u5468\u671f\u5c1d\u8bd5\u6062\u590d WLAN \u65e0\u7ebf\u7535\u3002\u672c\u673a\u9f20\u6807\u548c\u5e38\u89c1\u8fdc\u7a0b\u6ce8\u5165\u6309\u952e\u4ecd\u53ef\u4f7f\u7528\uff0c\u8bf7\u5148\u7528\u4f60\u7684\u8fdc\u7a0b\u8f6f\u4ef6\u5b9e\u6d4b\u3002",
  "trayHint": "\u5173\u95ed\u7a97\u53e3\u540e\u7a0b\u5e8f\u4ecd\u5728\u6258\u76d8\u8fd0\u884c\u3002",
  "overlayTitle": "\u952e\u76d8\u5df2\u9501\u5b9a",
  "overlayHint": "\u957f\u6309\u4e0b\u65b9\u6309\u94ae 3 \u79d2\u89e3\u9501",
  "holdUnlock": "\u6309\u4f4f\u89e3\u9501",
  "menuLock": "\u9501\u5b9a\u952e\u76d8",
  "menuUnlock": "\u89e3\u9501\u952e\u76d8",
  "menuShow": "\u663e\u793a\u4e3b\u7a97\u53e3",
  "menuExit": "\u9000\u51fa",
  "hideWindow": "\u9690\u85cf\u5230\u7cfb\u7edf\u6258\u76d8",
  "trayText": "\u732b\u54aa\u952e\u76d8\u5b88\u62a4",
  "balloonTitle": "\u732b\u54aa\u952e\u76d8\u5b88\u62a4",
  "balloonText": "\u7a0b\u5e8f\u4ecd\u5728\u6258\u76d8\u8fd0\u884c\u3002",
  "autoUnlocked": "\u5df2\u6309\u8bbe\u5b9a\u65f6\u95f4\u81ea\u52a8\u89e3\u9501\u3002",
  "hookError": "\u65e0\u6cd5\u542f\u7528\u952e\u76d8\u5b88\u62a4\u3002\u8bf7\u5c1d\u8bd5\u4ee5\u7ba1\u7406\u5458\u8eab\u4efd\u8fd0\u884c\u3002",
  "startupError": "\u65e0\u6cd5\u66f4\u6539\u5f00\u673a\u542f\u52a8\u8bbe\u7f6e\u3002",
  "emergency": "\u7d27\u6025\u60c5\u51b5\uff1a\u6309 Ctrl+Alt+Delete \u53ef\u8fdb\u5165 Windows \u5b89\u5168\u754c\u9762\u3002"
}
'@

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

$script:locked = $false
$script:exiting = $false
$script:holdStarted = $null
$script:unlockDeadline = $null
$script:suppressStartupChange = $false
$script:hookInstalled = $false
$script:functionKeyBlockerInstalled = $false
$script:radioGuardStarted = $false
$script:nextRadioCheck = [DateTime]::MinValue

$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$launcherPath = Join-Path $baseDir 'Start-CatKeyboardGuard.vbs'
$executablePath = Join-Path $baseDir 'CatKeyboardGuard.exe'
$iconPath = Join-Path $baseDir 'assets\cat-head.ico'
$catImagePath = Join-Path $baseDir 'assets\cat-head.png'
$startupFolder = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
$startupShortcut = Join-Path $startupFolder 'Cat Keyboard Guard.lnk'

$appIcon = [System.Drawing.SystemIcons]::Application
if (Test-Path -LiteralPath $iconPath) {
    try {
        $loadedIcon = New-Object System.Drawing.Icon($iconPath)
        $appIcon = $loadedIcon.Clone()
        $loadedIcon.Dispose()
    }
    catch {
        $appIcon = [System.Drawing.SystemIcons]::Application
    }
}

$catImage = $null
if (Test-Path -LiteralPath $catImagePath) {
    try {
        $loadedImage = [System.Drawing.Image]::FromFile($catImagePath)
        $catImage = New-Object System.Drawing.Bitmap($loadedImage)
        $loadedImage.Dispose()
    }
    catch {
        $catImage = $null
    }
}

function Set-AutoStart([bool]$enabled) {
    if ($enabled) {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($startupShortcut)
        if (Test-Path -LiteralPath $executablePath) {
            $shortcut.TargetPath = $executablePath
            $shortcut.Arguments = ''
        }
        else {
            $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
            $shortcut.Arguments = '"' + $launcherPath + '"'
        }
        $shortcut.WorkingDirectory = $baseDir
        $shortcut.IconLocation = $iconPath + ',0'
        $shortcut.Save()
        [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) | Out-Null
        [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) | Out-Null
    }
    elseif (Test-Path -LiteralPath $startupShortcut) {
        Remove-Item -LiteralPath $startupShortcut -Force
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = $ui.title
$form.ClientSize = New-Object System.Drawing.Size(240, 220)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'None'
$form.Opacity = 0.84
$form.AutoScaleMode = 'Dpi'
$form.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 250)
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8.5)
$form.Icon = $appIcon
$form.ShowIcon = $true

$catPicture = New-Object System.Windows.Forms.PictureBox
$catPicture.Location = New-Object System.Drawing.Point(10, 8)
$catPicture.Size = New-Object System.Drawing.Size(38, 38)
$catPicture.SizeMode = 'Zoom'
$catPicture.BackColor = [System.Drawing.Color]::Transparent
if ($null -ne $catImage) { $catPicture.Image = $catImage }
$form.Controls.Add($catPicture)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = $ui.title
$titleLabel.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = [System.Drawing.Color]::FromArgb(31, 41, 55)
$titleLabel.BackColor = [System.Drawing.Color]::Transparent
$titleLabel.Location = New-Object System.Drawing.Point(53, 8)
$titleLabel.AutoSize = $true
$form.Controls.Add($titleLabel)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = $ui.ready
$statusLabel.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8)
$statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(31, 112, 73)
$statusLabel.BackColor = [System.Drawing.Color]::Transparent
$statusLabel.Location = New-Object System.Drawing.Point(53, 29)
$statusLabel.AutoSize = $true
$form.Controls.Add($statusLabel)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = [char]0x00D7
$closeButton.Font = New-Object System.Drawing.Font('Segoe UI', 11)
$closeButton.Location = New-Object System.Drawing.Point(207, 7)
$closeButton.Size = New-Object System.Drawing.Size(25, 25)
$closeButton.FlatStyle = 'Flat'
$closeButton.BackColor = [System.Drawing.Color]::Transparent
$closeButton.ForeColor = [System.Drawing.Color]::FromArgb(75, 85, 99)
$closeButton.FlatAppearance.BorderSize = 0
$closeButton.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(229, 231, 235)
$form.Controls.Add($closeButton)

$guardButton = New-Object System.Windows.Forms.Button
$guardButton.Text = $ui.guardButton
$guardButton.Location = New-Object System.Drawing.Point(12, 57)
$guardButton.Size = New-Object System.Drawing.Size(216, 38)
$guardButton.FlatStyle = 'Flat'
$guardButton.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
$guardButton.ForeColor = [System.Drawing.Color]::White
$guardButton.FlatAppearance.BorderSize = 0
$form.Controls.Add($guardButton)

$autoCheck = New-Object System.Windows.Forms.CheckBox
$autoCheck.Text = $ui.autoUnlock
$autoCheck.Checked = $false
$autoCheck.Location = New-Object System.Drawing.Point(12, 132)
$autoCheck.AutoSize = $true
$autoCheck.BackColor = [System.Drawing.Color]::Transparent
$form.Controls.Add($autoCheck)

$minutesInput = New-Object System.Windows.Forms.NumericUpDown
$minutesInput.Minimum = 1
$minutesInput.Maximum = 480
$minutesInput.Value = 30
$minutesInput.Location = New-Object System.Drawing.Point(104, 130)
$minutesInput.Size = New-Object System.Drawing.Size(52, 23)
$minutesInput.Enabled = $false
$form.Controls.Add($minutesInput)

$minutesLabel = New-Object System.Windows.Forms.Label
$minutesLabel.Text = $ui.minutes
$minutesLabel.Location = New-Object System.Drawing.Point(160, 133)
$minutesLabel.AutoSize = $true
$minutesLabel.BackColor = [System.Drawing.Color]::Transparent
$form.Controls.Add($minutesLabel)

$remoteCheck = New-Object System.Windows.Forms.CheckBox
$remoteCheck.Text = $ui.remoteInput
$remoteCheck.Location = New-Object System.Drawing.Point(12, 104)
$remoteCheck.Checked = $true
$remoteCheck.AutoSize = $true
$remoteCheck.BackColor = [System.Drawing.Color]::Transparent
$form.Controls.Add($remoteCheck)

$startupCheck = New-Object System.Windows.Forms.CheckBox
$startupCheck.Text = $ui.startup
$startupCheck.Location = New-Object System.Drawing.Point(12, 162)
$startupCheck.AutoSize = $true
$startupCheck.BackColor = [System.Drawing.Color]::Transparent
$script:suppressStartupChange = $true
$startupCheck.Checked = Test-Path -LiteralPath $startupShortcut
$script:suppressStartupChange = $false
$form.Controls.Add($startupCheck)

$trayHintLabel = New-Object System.Windows.Forms.Label
$trayHintLabel.Text = $ui.trayHint
$trayHintLabel.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 7.5)
$trayHintLabel.ForeColor = [System.Drawing.Color]::FromArgb(107, 114, 128)
$trayHintLabel.BackColor = [System.Drawing.Color]::Transparent
$trayHintLabel.Location = New-Object System.Drawing.Point(12, 191)
$trayHintLabel.Size = New-Object System.Drawing.Size(216, 20)
$form.Controls.Add($trayHintLabel)

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 10000
$toolTip.InitialDelay = 350
$toolTip.ReshowDelay = 100
$toolTip.SetToolTip($catPicture, $ui.subtitle)
$toolTip.SetToolTip($guardButton, $ui.tip)
$toolTip.SetToolTip($remoteCheck, $ui.tip)
$toolTip.SetToolTip($closeButton, $ui.hideWindow)

$script:dragMouseStart = $null
$script:dragFormStart = $null
$startWindowDrag = {
    if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:dragMouseStart = [System.Windows.Forms.Cursor]::Position
        $script:dragFormStart = $form.Location
    }
}
$continueWindowDrag = {
    if ($null -eq $script:dragMouseStart -or $null -eq $script:dragFormStart) { return }
    if (([System.Windows.Forms.Control]::MouseButtons -band [System.Windows.Forms.MouseButtons]::Left) -eq 0) {
        $script:dragMouseStart = $null
        $script:dragFormStart = $null
        return
    }

    $currentPosition = [System.Windows.Forms.Cursor]::Position
    $form.Location = New-Object System.Drawing.Point(
        ($script:dragFormStart.X + $currentPosition.X - $script:dragMouseStart.X),
        ($script:dragFormStart.Y + $currentPosition.Y - $script:dragMouseStart.Y)
    )
}
$finishWindowDrag = {
    $script:dragMouseStart = $null
    $script:dragFormStart = $null
}

foreach ($dragControl in @($form, $catPicture, $titleLabel, $statusLabel)) {
    $dragControl.Add_MouseDown($startWindowDrag)
    $dragControl.Add_MouseMove($continueWindowDrag)
    $dragControl.Add_MouseUp($finishWindowDrag)
}

$overlay = New-Object System.Windows.Forms.Form
$overlay.Text = $ui.title
$overlay.ClientSize = New-Object System.Drawing.Size(238, 112)
$overlay.FormBorderStyle = 'None'
$overlay.StartPosition = 'Manual'
$overlay.ShowInTaskbar = $false
$overlay.TopMost = $true
$overlay.ControlBox = $false
$overlay.AllowTransparency = $true
$overlayTransparencyKey = [System.Drawing.Color]::FromArgb(255, 0, 255)
$overlay.BackColor = $overlayTransparencyKey
$overlay.TransparencyKey = $overlayTransparencyKey
$overlay.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8.5)

$overlayStatusPanel = New-Object System.Windows.Forms.Panel
$overlayStatusPanel.Location = New-Object System.Drawing.Point(7, 3)
$overlayStatusPanel.Size = New-Object System.Drawing.Size(190, 40)
$overlayStatusPanel.BackColor = [System.Drawing.Color]::FromArgb(31, 41, 55)
$overlay.Controls.Add($overlayStatusPanel)

$overlayCatPicture = New-Object System.Windows.Forms.PictureBox
$overlayCatPicture.Location = New-Object System.Drawing.Point(2, 2)
$overlayCatPicture.Size = New-Object System.Drawing.Size(36, 36)
$overlayCatPicture.SizeMode = 'Zoom'
$overlayCatPicture.BackColor = [System.Drawing.Color]::Transparent
if ($null -ne $catImage) { $overlayCatPicture.Image = $catImage }
$overlayStatusPanel.Controls.Add($overlayCatPicture)

$overlayTitle = New-Object System.Windows.Forms.Label
$overlayTitle.Text = $ui.overlayTitle
$overlayTitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
$overlayTitle.ForeColor = [System.Drawing.Color]::FromArgb(254, 202, 202)
$overlayTitle.BackColor = [System.Drawing.Color]::Transparent
$overlayTitle.Location = New-Object System.Drawing.Point(44, 1)
$overlayTitle.AutoSize = $true
$overlayStatusPanel.Controls.Add($overlayTitle)

$overlayHint = New-Object System.Windows.Forms.Label
$overlayHint.Text = $ui.holdUnlock + ' 3 ' + ([char[]](0x79D2) -join '')
$overlayHint.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 7.5)
$overlayHint.ForeColor = [System.Drawing.Color]::FromArgb(229, 231, 235)
$overlayHint.BackColor = [System.Drawing.Color]::Transparent
$overlayHint.Location = New-Object System.Drawing.Point(44, 21)
$overlayHint.AutoSize = $true
$overlayStatusPanel.Controls.Add($overlayHint)

$holdProgress = New-Object System.Windows.Forms.ProgressBar
$holdProgress.Location = New-Object System.Drawing.Point(8, 48)
$holdProgress.Size = New-Object System.Drawing.Size(222, 6)
$holdProgress.Minimum = 0
$holdProgress.Maximum = 30
$overlay.Controls.Add($holdProgress)

$unlockButton = New-Object System.Windows.Forms.Button
$unlockButton.Text = $ui.holdUnlock
$unlockButton.Location = New-Object System.Drawing.Point(8, 64)
$unlockButton.Size = New-Object System.Drawing.Size(222, 38)
$unlockButton.FlatStyle = 'Flat'
$unlockButton.BackColor = [System.Drawing.Color]::FromArgb(220, 38, 38)
$unlockButton.ForeColor = [System.Drawing.Color]::White
$unlockButton.FlatAppearance.BorderSize = 0
$unlockButton.FlatAppearance.BorderColor = $unlockButton.BackColor
$unlockButton.UseVisualStyleBackColor = $false
$unlockButton.TabStop = $false
$overlay.Controls.Add($unlockButton)

$overlayToolTipText = $ui.overlayHint + [Environment]::NewLine + $ui.emergency
$toolTip.SetToolTip($overlayCatPicture, $overlayToolTipText)
$toolTip.SetToolTip($overlayTitle, $overlayToolTipText)
$toolTip.SetToolTip($overlayHint, $overlayToolTipText)
$toolTip.SetToolTip($unlockButton, $overlayToolTipText)

$script:overlayDragMouseStart = $null
$script:overlayDragFormStart = $null
$startOverlayDrag = {
    if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:overlayDragMouseStart = [System.Windows.Forms.Cursor]::Position
        $script:overlayDragFormStart = $overlay.Location
    }
}
$continueOverlayDrag = {
    if ($null -eq $script:overlayDragMouseStart -or $null -eq $script:overlayDragFormStart) { return }
    if (([System.Windows.Forms.Control]::MouseButtons -band [System.Windows.Forms.MouseButtons]::Left) -eq 0) {
        $script:overlayDragMouseStart = $null
        $script:overlayDragFormStart = $null
        return
    }

    $currentPosition = [System.Windows.Forms.Cursor]::Position
    $overlay.Location = New-Object System.Drawing.Point(
        ($script:overlayDragFormStart.X + $currentPosition.X - $script:overlayDragMouseStart.X),
        ($script:overlayDragFormStart.Y + $currentPosition.Y - $script:overlayDragMouseStart.Y)
    )
}
$finishOverlayDrag = {
    $script:overlayDragMouseStart = $null
    $script:overlayDragFormStart = $null
}

foreach ($overlayDragControl in @($overlayStatusPanel, $overlayCatPicture, $overlayTitle, $overlayHint)) {
    $overlayDragControl.Add_MouseDown($startOverlayDrag)
    $overlayDragControl.Add_MouseMove($continueOverlayDrag)
    $overlayDragControl.Add_MouseUp($finishOverlayDrag)
}

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$menuToggle = $trayMenu.Items.Add($ui.menuLock)
$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$menuShow = $trayMenu.Items.Add($ui.menuShow)
$menuExit = $trayMenu.Items.Add($ui.menuExit)

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = $appIcon
$tray.Text = $ui.trayText
$tray.ContextMenuStrip = $trayMenu
$tray.Visible = $true

function Show-MainWindow {
    $form.Show()
    $form.WindowState = 'Normal'
    $form.Activate()
}

function Update-OverlayLocation {
    $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $overlay.Location = New-Object System.Drawing.Point(($area.Right - $overlay.Width - 18), ($area.Bottom - $overlay.Height - 18))
}

function Set-GuardState([bool]$shouldLock, [string]$notice = '') {
    if ($shouldLock -eq $script:locked) { return }

    if ($shouldLock) {
        if (-not $script:hookInstalled) {
            try {
                [CatKeyboardGuard.KeyboardHook]::Install()
                $script:hookInstalled = $true
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show($ui.hookError, $ui.title, 'OK', 'Error') | Out-Null
                return
            }
        }

        if (-not $script:functionKeyBlockerInstalled) {
            try {
                [CatKeyboardGuard.FunctionKeyBlocker]::Install()
                $script:functionKeyBlockerInstalled = $true
            }
            catch {
                # Some OEM firmware handles Fn keys below the Windows keyboard
                # layer. Keep normal key protection active and continue safely.
                $script:functionKeyBlockerInstalled = $false
            }
        }

        # Lenovo Fn+F8 can be handled by firmware/service code without
        # producing a keyboard event. Keep a WLAN API handle while protected
        # and repair software-radio changes on the UI timer.
        try {
            $script:radioGuardStarted = [CatKeyboardGuard.RadioGuard]::Start()
            if ($script:radioGuardStarted) {
                [CatKeyboardGuard.RadioGuard]::Restore() | Out-Null
                $script:nextRadioCheck = [DateTime]::UtcNow.AddMilliseconds(250)
            }
        }
        catch {
            $script:radioGuardStarted = $false
        }

        [CatKeyboardGuard.KeyboardHook]::UnlockRequested = $false
        [CatKeyboardGuard.KeyboardHook]::AllowRemoteInput = $remoteCheck.Checked
        [CatKeyboardGuard.KeyboardHook]::Blocking = $true
        $script:locked = $true
        $script:holdStarted = $null
        $holdProgress.Value = 0
        if ($autoCheck.Checked) {
            $script:unlockDeadline = [DateTime]::UtcNow.AddMinutes([double]$minutesInput.Value)
        }
        else {
            $script:unlockDeadline = $null
        }

        $statusLabel.Text = $ui.locked
        $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(185, 28, 28)
        $guardButton.Text = $ui.menuUnlock
        $guardButton.BackColor = [System.Drawing.Color]::FromArgb(220, 38, 38)
        $menuToggle.Text = $ui.menuUnlock
        Update-OverlayLocation
        $overlay.Show()
        $overlay.Activate()
        $form.Hide()
    }
    else {
        [CatKeyboardGuard.KeyboardHook]::Blocking = $false
        if ($script:functionKeyBlockerInstalled) {
            [CatKeyboardGuard.FunctionKeyBlocker]::Uninstall()
            $script:functionKeyBlockerInstalled = $false
        }
        if ($script:radioGuardStarted) {
            [CatKeyboardGuard.RadioGuard]::Stop()
            $script:radioGuardStarted = $false
        }
        [CatKeyboardGuard.KeyboardHook]::UnlockRequested = $false
        $script:locked = $false
        $script:holdStarted = $null
        $script:unlockDeadline = $null
        $holdProgress.Value = 0
        $overlay.Hide()
        $statusLabel.Text = $ui.ready
        $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(31, 112, 73)
        $guardButton.Text = $ui.guardButton
        $guardButton.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
        $menuToggle.Text = $ui.menuLock
        if ($notice) {
            $tray.ShowBalloonTip(2500, $ui.balloonTitle, $notice, 'Info')
        }
    }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 100
$timer.Add_Tick({
    if (-not $script:locked) { return }

    if ($script:radioGuardStarted -and [DateTime]::UtcNow -ge $script:nextRadioCheck) {
        try { [CatKeyboardGuard.RadioGuard]::Restore() | Out-Null } catch { }
        $script:nextRadioCheck = [DateTime]::UtcNow.AddMilliseconds(250)
    }

    if ([CatKeyboardGuard.KeyboardHook]::UnlockRequested -or [CatKeyboardGuard.KeyboardHook]::UnlockChordReady) {
        Set-GuardState $false
        Show-MainWindow
        return
    }

    if ($null -ne $script:unlockDeadline -and [DateTime]::UtcNow -ge $script:unlockDeadline) {
        Set-GuardState $false $ui.autoUnlocked
        return
    }

    if ($null -ne $script:holdStarted) {
        if (([System.Windows.Forms.Control]::MouseButtons -band [System.Windows.Forms.MouseButtons]::Left) -eq 0) {
            $script:holdStarted = $null
            $holdProgress.Value = 0
            return
        }

        $elapsed = ([DateTime]::UtcNow - $script:holdStarted).TotalSeconds
        $progress = [Math]::Min(30, [Math]::Floor($elapsed * 10))
        $holdProgress.Value = [int]$progress
        if ($elapsed -ge 3) {
            Set-GuardState $false
            Show-MainWindow
        }
    }
})
$timer.Start()

$guardButton.Add_Click({ Set-GuardState (-not $script:locked) })
$closeButton.Add_Click({ $form.Close() })
$autoCheck.Add_CheckedChanged({ $minutesInput.Enabled = $autoCheck.Checked })
$unlockButton.Add_MouseDown({
    if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:holdStarted = [DateTime]::UtcNow
        $holdProgress.Value = 0
    }
})
$unlockButton.Add_MouseUp({
    $script:holdStarted = $null
    $holdProgress.Value = 0
})
$menuToggle.Add_Click({ Set-GuardState (-not $script:locked) })
$menuShow.Add_Click({ Show-MainWindow })
$tray.Add_DoubleClick({ Show-MainWindow })
$startupCheck.Add_CheckedChanged({
    if ($script:suppressStartupChange) { return }
    try {
        Set-AutoStart $startupCheck.Checked
    }
    catch {
        $script:suppressStartupChange = $true
        $startupCheck.Checked = -not $startupCheck.Checked
        $script:suppressStartupChange = $false
        [System.Windows.Forms.MessageBox]::Show($ui.startupError, $ui.title, 'OK', 'Error') | Out-Null
    }
})
$form.Add_FormClosing({
    if (-not $script:exiting -and $_.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
        $_.Cancel = $true
        $form.Hide()
        $tray.ShowBalloonTip(1800, $ui.balloonTitle, $ui.balloonText, 'Info')
    }
})
$menuExit.Add_Click({
    $script:exiting = $true
    Set-GuardState $false
    $form.Close()
    [System.Windows.Forms.Application]::Exit()
})

try {
    [System.Windows.Forms.Application]::Run($form)
}
finally {
    $timer.Stop()
    [CatKeyboardGuard.KeyboardHook]::Blocking = $false
    if ($script:functionKeyBlockerInstalled) { [CatKeyboardGuard.FunctionKeyBlocker]::Uninstall() }
    if ($script:radioGuardStarted) { [CatKeyboardGuard.RadioGuard]::Stop(); $script:radioGuardStarted = $false }
    if ($script:hookInstalled) { [CatKeyboardGuard.KeyboardHook]::Uninstall() }
    $tray.Visible = $false
    $tray.Dispose()
    $overlay.Dispose()
    $form.Dispose()
    $toolTip.Dispose()
    if ($null -ne $catImage) { $catImage.Dispose() }
    if ($appIcon -ne [System.Drawing.SystemIcons]::Application) { $appIcon.Dispose() }
    $instanceMutex.ReleaseMutex() | Out-Null
    $instanceMutex.Dispose()
}
