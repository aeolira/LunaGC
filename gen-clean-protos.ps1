$proto = Get-Content (Join-Path $PSScriptRoot "protos-original\Deobfuscated.proto") -Raw -Encoding UTF8
$msgMap = @{}; $allNames = @{}; $pattern = '(?m)^(message|enum) (\w+)\s*\{'
foreach ($m in [regex]::Matches($proto, $pattern)) { $name=$m.Groups[2].Value; $depth=1; $pos=$m.Index+$m.Length; while($depth -gt 0 -and $pos -lt $proto.Length){ if($proto[$pos]-eq'{'){$depth++}elseif($proto[$pos]-eq'}'){$depth--}; $pos++ }; $body=$proto.Substring($m.Index,$pos-$m.Index); if($m.Groups[1].Value -eq 'message'){$msgMap[$name]=$body}; $allNames[$name]=$true }
$primitives = @("uint32","int32","uint64","int64","float","double","bool","string","bytes","fixed32","fixed64","sfixed32","sfixed64","sint32","sint64","map","repeated","oneof")
foreach ($p in $primitives) { $allNames[$p] = $false }
$readable = @{}; foreach ($k in $allNames.Keys) { if ($k -match '^[A-Z][a-z]' -and $allNames[$k]) { $readable[$k] = $true } }
"Readable: $($readable.Count)"
$imports = Get-ChildItem (Join-Path $PSScriptRoot "src\main") -Recurse -Filter "*.java" | Select-String "import emu\.grasscutter\.net\.proto\.(\w+OuterClass)" | ForEach-Object { $_.Matches.Groups[1].Value -replace 'OuterClass$','' } | Sort-Object -Unique
$used = $imports | Where-Object { $readable.ContainsKey($_) }; "Used: $($used.Count)"
Get-ChildItem (Join-Path $PSScriptRoot "proto") -File -Filter "*.proto" | Remove-Item -Force
$gen = 0
foreach ($name in $used) {
    if (-not $msgMap.ContainsKey($name)) { continue }
    $body = $msgMap[$name]
    $fl = [regex]::Matches($body, '(\w+)\s+\w+\s*=\s*\d+;')
    $deps = @()
    $newBody = $body
    foreach ($f in $fl) {
        $t = $f.Groups[1].Value
        if ($readable.ContainsKey($t)) { $deps += $t }
        elseif ($allNames.ContainsKey($t) -and $allNames[$t]) {
            $newBody = $newBody.Replace($f.Value, "")
        }
    }
    $deps = $deps | Sort-Object -Unique
    $imps = ($deps | ForEach-Object { "import `"$_.proto`";" }) -join "`r`n"
    $ext = if ($newBody -match 'google\.protobuf') { 'import "google/protobuf/descriptor.proto";' + "`r`n" } else { "" }
    Set-Content (Join-Path $PSScriptRoot "proto\$name.proto") -Value "syntax = `"proto3`";`r`n`r`n$ext$imps`r`n`r`n$newBody" -Encoding UTF8 -NoNewline
    $gen++
}
"Generated: $gen"
