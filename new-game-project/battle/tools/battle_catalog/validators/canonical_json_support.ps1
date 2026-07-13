Set-StrictMode -Version Latest

function ConvertTo-BattleJsonStringLiteral {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    $builder = [Text.StringBuilder]::new()
    $null = $builder.Append('"')
    for ($index = 0; $index -lt $Value.Length; $index++) {
        $character = $Value[$index]
        switch ([int]$character) {
            0x08 { $null = $builder.Append('\b'); continue }
            0x09 { $null = $builder.Append('\t'); continue }
            0x0a { $null = $builder.Append('\n'); continue }
            0x0c { $null = $builder.Append('\f'); continue }
            0x0d { $null = $builder.Append('\r'); continue }
            0x22 { $null = $builder.Append('\"'); continue }
            0x5c { $null = $builder.Append('\\'); continue }
        }
        if ([int]$character -lt 0x20) {
            $null = $builder.AppendFormat(
                [Globalization.CultureInfo]::InvariantCulture,
                '\u{0:x4}',
                [int]$character
            )
            continue
        }
        if ([char]::IsHighSurrogate($character)) {
            if ($index + 1 -ge $Value.Length -or
                -not [char]::IsLowSurrogate($Value[$index + 1])) {
                throw "Canonical JSON cannot encode an unpaired high surrogate."
            }
            $null = $builder.Append($character)
            $index++
            $null = $builder.Append($Value[$index])
            continue
        }
        if ([char]::IsLowSurrogate($character)) {
            throw "Canonical JSON cannot encode an unpaired low surrogate."
        }
        $null = $builder.Append($character)
    }
    $null = $builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-BattleCanonicalJsonValue {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return "null"
    }
    if ($Value -is [bool]) {
        return $(if ([bool]$Value) { "true" } else { "false" })
    }
    if ($Value -is [string] -or $Value -is [char]) {
        return ConvertTo-BattleJsonStringLiteral -Value ([string]$Value)
    }
    if ($Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64]) {
        return ([Convert]::ToInt64($Value)).ToString(
            [Globalization.CultureInfo]::InvariantCulture
        )
    }
    if ($Value -is [uint64]) {
        return ([uint64]$Value).ToString([Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [float] -or $Value -is [double] -or $Value -is [decimal]) {
        throw "Canonical P0 JSON permits bounded integers only."
    }

    $propertyMap = $null
    if ($Value -is [Collections.IDictionary]) {
        $propertyMap = @{}
        foreach ($key in $Value.Keys) {
            if ($key -isnot [string]) {
                throw "Canonical JSON object keys must be strings."
            }
            if ($propertyMap.ContainsKey([string]$key)) {
                throw "Canonical JSON object contains duplicate key '$key'."
            }
            $propertyMap[[string]$key] = $Value[$key]
        }
    }
    elseif ($Value -is [PSCustomObject]) {
        $propertyMap = @{}
        foreach ($property in $Value.PSObject.Properties) {
            if ($propertyMap.ContainsKey($property.Name)) {
                throw "Canonical JSON object contains duplicate key '$($property.Name)'."
            }
            $propertyMap[$property.Name] = $property.Value
        }
    }
    if ($null -ne $propertyMap) {
        $names = @($propertyMap.Keys)
        [Array]::Sort($names, [StringComparer]::Ordinal)
        $parts = [Collections.Generic.List[string]]::new()
        foreach ($name in $names) {
            $parts.Add(
                (ConvertTo-BattleJsonStringLiteral -Value $name) + ":" +
                (ConvertTo-BattleCanonicalJsonValue -Value $propertyMap[$name])
            )
        }
        return "{" + ($parts -join ",") + "}"
    }

    if ($Value -is [Collections.IEnumerable]) {
        $parts = [Collections.Generic.List[string]]::new()
        foreach ($item in $Value) {
            $parts.Add((ConvertTo-BattleCanonicalJsonValue -Value $item))
        }
        return "[" + ($parts -join ",") + "]"
    }

    throw "Canonical JSON does not support value type '$($Value.GetType().FullName)'."
}

function ConvertTo-BattleCanonicalJson {
    param([AllowNull()][object]$Value)

    return (ConvertTo-BattleCanonicalJsonValue -Value $Value) + "`n"
}

function Get-BattleSha256Text {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace(
            "-",
            ""
        ).ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Write-BattleCanonicalJsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowNull()][object]$Value
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }
    $json = ConvertTo-BattleCanonicalJson -Value $Value
    [IO.File]::WriteAllText($fullPath, $json, [Text.UTF8Encoding]::new($false))
    return Get-BattleSha256Text -Text $json
}
