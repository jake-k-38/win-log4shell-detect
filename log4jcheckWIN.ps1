$IOCPatterns = ('jndi:ldap:',
  'jndi:rmi:/',
  'jndi:ldaps:/',
  'jndi:dns:/',
  'jndi:nis:/',
  'jndi:nds:/',
  'jndi:corba:/',
  'jndi:iiop:/',
  'log4j',
  'jndi.LDAPRefServer',
  'jndi:ldap://',
  'env:BARFOO:-j',
  'env:BARFOO:-:',
  'env:BARFOO:-l',
  'env:BARFOO:-:',
  'jndi',
  'jndi:ld',
  'ldap:/',
  'jndi:ldap://127.0.0.1:1099',
  '{date:j}${date:n}${date:d}${date:i}:${date:l}${date:d}${date:a}${date:p}',
  '/Basic/Command/Base64',
  'at java.naming/com.sun.jndi.url.ldap.ldapURLContext.lookup',
  'log4j.core.lookup.JndiLookup.lookup',
  'Reference Class Name: foo',
  'base64:',
  '<Hidden>true</Hidden>',#Next 15 strings are common in APTs in schtasks on infected machines
  '-WindowStyle Hidden',
  'powershell/w 01',
  'powershell/w 01 /ep 0/nop/c',
  'powershell.exe -exec bypass',
  'powershell -c iex',
  'IEX (New-Object Net.WebClient).DownloadString',
  '-NonInteractive',
  '-NoLogo',
  '-ExecutionPolicy bypass',
  '-encodedcommand',
  '-enc',
  'C:\\ProgramData\\Microsoft\\Windows\\Start Menu\\Programs\\StartUp',
  'base64_encode',
  'base64_decode',
  'cmd.exe /c',
  'Scriptrunner.exe',
  'Cscript.exe',
  'WScript.exe',
  'VBscript.Encode',
  'Wscript.Shell')

$temp = ''
$log4j_processtemp = ''
$log4j_adtemp = ''
$ioc_task = ''
$ioc_base64 = ''
$log4j_base64 = ''
$log4j_base64ad = ''
$datestring = (Get-Date).ToString('s').Replace(':','-')

$savedir = 'C:\ioc_log4jScan_' + $datestring + '.txt'
$savedir2 = 'C:\ioc_log4jScanBase64_' + $datestring + '.txt'

$outputGrid = 'True'
$saveToFile = 'False'

#///////////////////////////////////////////////////////////////////////////////////////////////////
# *** THIS MODULE IS REQUIRED FOR SCRIPT TO RUN ***
# Get-Base64RegularExpression https://www.leeholmes.com/searching-for-content-in-base-64-strings/
# Type in powershell Install-Script Get-Base64RegularExpression.ps1
# *** THIS MODULE IS REQUIRED FOR SCRIPT TO RUN ***
#///////////////////////////////////////////////////////////////////////////////////////////////////
# REQUIRES Audit Process Creation logging. By enabling this, in addition to enabling the scanning of success audit events, you'll be able to scan and audit event 4688(S): A new process has been created
# https://www.lansweeper.com/report/log4j-event-log-audit/
# Got the idea from https://github.com/Neo23x0/log4shell-detector
# You can add IOC patterns as the obfuscation of the reverse shells get tougher and more sophisticated

$processfilter = @{
  LogName = 'Security'
  ID = 4688 #New process eventID
  StartTime = [datetime]::Now.AddHours(-24) #How far to look back in logs
}

$taskfilter = @{
  LogName = 'Security'
  ID = 4698 #New ScheduledTasks
  StartTime = [datetime]::Now.AddHours(-24) #How far to look back in logs
}

$adfsfilter = @{
  LogName = 'AD FS Auditing'
  ID = 403 #RequestReceivedSuccessAudit
  StartTime = [datetime]::Now.AddHours(-24) #How far to look back in logs
}

$Width = -1 * ((Measure-Object -Maximum length).maximum + 1)

filter MultiSelect-String ([string[]]$Patterns) {
  if ($_ -match '}$' -and ($_ -match "lower" -or $_ -match "upper")) {
    $obfusCheck = $_.Split('}$').Split(':')
  } elseif ($_ -match '}$') {
    $obfusCheck = $_.Split('}$').Split('-')
  }
  $obfusString = ""
  for ($i = 0; $i -lt $obfusCheck.Length; $i++) {
    if ($obfusCheck[$i].Length -ne 1) {
      continue
    }
    $obfusString += -join ($obfusCheck[$i])
  }
  foreach ($Pattern in $Patterns) {
    if ($_ | Select-String 'Task Name') { $temp = $_ } #filter ScheduledTasks and save name
    if ($_ | Select-String -AllMatches -Pattern $Pattern) {
      if ($temp -ne "") { $temp }
      $_ #We found a match!
      $temp = ''
    } elseif ($obfusString | Select-String -AllMatches -Pattern $Pattern) { #check if hidden strings
      Write-Warning ("*OBFUSCATION FOUND* Matched: {0,$Width} {1}" -f $Pattern,$obfusString)
    } else {
      continue
    }
  }
}
filter MultiSelect-Base64String ([string[]]$Patterns) {
  # Check the current item against all patterns.
  foreach ($Pattern in $Patterns) {
    # If one of the patterns does not match, continue checking same item.
    $regex = (Get-Base64RegularExpression $Pattern)
    if ($_ | Select-String -AllMatches -Pattern $regex) {
      $_ #We found a match!
      Write-Warning ("*BASE64 FOUND* Matched: {0,$Width} {1}" -f $Pattern,$_)
    } else { #Keep scanning
      continue
    }
  }
}

Write-Warning ("Checking for suspicious log4j events/IOCs (EventID 4688, EventID 4698, ADFS 403):")
$log4j_processtemp = Get-WinEvent -FilterHashtable $processfilter -ErrorAction Continue | Select-Object -ExpandProperty Message | MultiSelect-String $IOCPatterns
$ioc_task = Get-WinEvent -FilterHashtable $taskfilter -ErrorAction Continue | Select-Object -Property * | Out-String -Stream | Select-String -Pattern 'Task Name','<Hidden>','<Command>','<Arguments>' | MultiSelect-String $IOCPatterns
$log4j_adtemp = Get-WinEvent -FilterHashtable $adfsfilter -ErrorAction Continue | Select-Object -ExpandProperty Message | MultiSelect-String $IOCPatterns

Write-Warning ("Checking for suspicious Base64 encoded log4j events/IOCs:")
$log4j_base64 = Get-WinEvent -FilterHashtable $processfilter -ErrorAction Continue | Select-Object -ExpandProperty Message | MultiSelect-Base64String $IOCPatterns
$log4j_base64ad = Get-WinEvent -FilterHashtable $adfsfilter -ErrorAction Continue | Select-Object -ExpandProperty Message | MultiSelect-Base64String $IOCPatterns
$ioc_base64 = Get-WinEvent -FilterHashtable $taskfilter -ErrorAction Continue | Select-Object -Property * | Out-String -Stream | Select-String -Pattern 'Task Name','<Hidden>','<Command>','<Arguments>' | MultiSelect-Base64String $IOCPatterns

if ($outputGrid) {
  if ($log4j_processtemp -ne "") { $log4j_processtemp | Out-GridView -Title 'IOCs EventID 4688' }
  if ($log4j_adtemp -ne "") { $log4j_adtemp | Out-GridView -Title 'IOCs ADFS 403' }
  if ($ioc_task -ne "") { $ioc_task | Out-GridView -Title 'IOCs EventID 4698' }
  if ($log4j_base64 -ne "") { $log4j_base64 | Out-GridView -Title 'Base64 IOCs EventID 4688' }
  if ($ioc_base64 -ne "") { $ioc_base64 | Out-GridView -Title 'Base64 IOCs EventID 4698' }
  if ($log4j_base64ad -ne "") { $log4j_base64ad | Out-GridView -Title 'Base64 IOCs ADFS 403' }
}

if ($saveToFile) {
  $log4j_temp | Out-File -Append -FilePath $savedir
  $log4j_adtemp | Out-File -Append -FilePath $savedir
  $ioc_task | Out-File -Append -FilePath $savedir
  $log4j_base64 | Out-File -Append -FilePath $savedir2
  $ioc_base64 | Out-File -Append -FilePath $savedir2
  $log4j_base64ad | Out-File -Append -FilePath $savedir2
}
