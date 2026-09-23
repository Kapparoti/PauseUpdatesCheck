<#
.SYNOPSIS
    Sets the maximum Windows Update pause and reminds the user if more
	than a configured number of days have passed since the last update.
	The threshold is read from the Registry, where it is saved by the installer.

.NOTE
    Must be run with Administrator privileges, otherwise writing to the
    registry for the update pause will fail.
#>

# Check for administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    # Silent log, no popup: the script must terminate cleanly
    Write-Warning "Script not running as administrator: unable to set the update pause."
    exit 1
}

# Read the notification threshold saved by the installer
$configPath    = "HKLM:\SOFTWARE\PauseUpdatesCheck"
$thresholdDays = 30  # fallback if no value has been saved

if (Test-Path $configPath) {
    $configValue = Get-ItemProperty -Path $configPath -Name "ThresholdDays" -ErrorAction SilentlyContinue
    if ($configValue -and $configValue.ThresholdDays) {
        $thresholdDays = [int]$configValue.ThresholdDays
    }
}

# Set the update pause to the maximum allowed (35 days)
$regPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"

if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}

$now      = Get-Date
$maxPause = $now.AddDays(35)  # official maximum pause length allowed via the UI

$nowString = $now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$endString = $maxPause.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$registryValues = @{
    "PauseUpdatesExpiryTime"        = $endString
    "PauseFeatureUpdatesStartTime"  = $nowString
    "PauseFeatureUpdatesEndTime"    = $endString
    "PauseQualityUpdatesStartTime"  = $nowString
    "PauseQualityUpdatesEndTime"    = $endString
}

foreach ($name in $registryValues.Keys) {
    New-ItemProperty -Path $regPath -Name $name -Value $registryValues[$name] -PropertyType String -Force | Out-Null
}

Write-Output "Update pause set until: $maxPause"

# Check whether the last update is older than $thresholdDays days
$lastUpdate = Get-HotFix | Where-Object { $_.InstalledOn } |
              Sort-Object InstalledOn -Descending |
              Select-Object -First 1

$threshold = $now.AddDays(-$thresholdDays)
$showAlert = $false

if (-not $lastUpdate) {
    # No date available: warn anyway, to be safe
    $showAlert = $true
    $lastUpdateDateString = "unknown"
} else {
    $lastUpdateDateString = $lastUpdate.InstalledOn.ToString("yyyy-MM-dd")
    if ($lastUpdate.InstalledOn -lt $threshold) {
        $showAlert = $true
    }
}

# If needed, show a clickable toast notification
if ($showAlert) {
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

        $appId = "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"

        [xml]$toastXml = @"
<toast activationType="protocol" launch="ms-settings:windowsupdate">
  <visual>
    <binding template="ToastGeneric">
      <text>Windows Updates on hold</text>
      <text>No updates have been installed for at least $thresholdDays day(s) (last one: $lastUpdateDateString). Click to open Windows Update.</text>
    </binding>
  </visual>
  <actions>
    <action content="Open Windows Update" activationType="protocol" arguments="ms-settings:windowsupdate"/>
    <action content="Resume updates" activationType="protocol" arguments="ms-settings:windowsupdate-options"/>
  </actions>
</toast>
"@

        $xmlDocument = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xmlDocument.LoadXml($toastXml.OuterXml)

        $toast = New-Object Windows.UI.Notifications.ToastNotification($xmlDocument)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
    }
    catch {
        # Minimal fallback if the toast APIs are not available
        Add-Type -AssemblyName System.Windows.Forms
        $balloon = New-Object System.Windows.Forms.NotifyIcon
        $balloon.Icon = [System.Drawing.SystemIcons]::Warning
        $balloon.Visible = $true
        $balloon.ShowBalloonTip(10000, "Windows Updates on hold",
            "Last update: $lastUpdateDateString. Open Windows Update to check.",
            [System.Windows.Forms.ToolTipIcon]::Warning)
        Start-Sleep -Seconds 10
        $balloon.Dispose()
    }
}

exit 0
