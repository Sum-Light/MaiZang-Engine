Set-StrictMode -Version Latest

function New-BattleJsonError {
    param(
        [Parameter(Mandatory = $true)][hashtable]$State,
        [Parameter(Mandatory = $true)][string]$Message
    )

    return [FormatException]::new(
        "$($State.Label): $Message at UTF-16 offset $($State.Index)."
    )
}

function Skip-BattleJsonWhitespace {
    param([Parameter(Mandatory = $true)][hashtable]$State)

    while ($State.Index -lt $State.Length) {
        $character = $State.Text[$State.Index]
        if ($character -notin @([char]0x20, [char]0x09, [char]0x0a, [char]0x0d)) {
            break
        }
        $State.Index++
    }
}

function Read-BattleJsonString {
    param([Parameter(Mandatory = $true)][hashtable]$State)

    if ($State.Index -ge $State.Length -or $State.Text[$State.Index] -ne '"') {
        throw (New-BattleJsonError -State $State -Message "Expected a JSON string")
    }
    $State.Index++
    $builder = [Text.StringBuilder]::new()
    while ($State.Index -lt $State.Length) {
        $character = $State.Text[$State.Index]
        $State.Index++
        if ($character -eq '"') {
            return $builder.ToString()
        }
        if ([int]$character -lt 0x20) {
            throw (New-BattleJsonError -State $State -Message "Unescaped control character in string")
        }
        if ($character -ne '\') {
            $null = $builder.Append($character)
            continue
        }
        if ($State.Index -ge $State.Length) {
            throw (New-BattleJsonError -State $State -Message "Incomplete string escape")
        }
        $escape = $State.Text[$State.Index]
        $State.Index++
        switch ($escape) {
            '"' { $null = $builder.Append('"'); continue }
            '\' { $null = $builder.Append('\'); continue }
            '/' { $null = $builder.Append('/'); continue }
            'b' { $null = $builder.Append([char]0x08); continue }
            'f' { $null = $builder.Append([char]0x0c); continue }
            'n' { $null = $builder.Append([char]0x0a); continue }
            'r' { $null = $builder.Append([char]0x0d); continue }
            't' { $null = $builder.Append([char]0x09); continue }
            'u' {
                if ($State.Index + 4 -gt $State.Length) {
                    throw (New-BattleJsonError -State $State -Message "Incomplete Unicode escape")
                }
                $hex = $State.Text.Substring($State.Index, 4)
                if ($hex -cnotmatch '^[0-9A-Fa-f]{4}$') {
                    throw (New-BattleJsonError -State $State -Message "Invalid Unicode escape")
                }
                $State.Index += 4
                $codeUnit = [Convert]::ToInt32($hex, 16)
                if ($codeUnit -ge 0xd800 -and $codeUnit -le 0xdbff) {
                    if ($State.Index + 6 -gt $State.Length -or
                        $State.Text.Substring($State.Index, 2) -ne '\u') {
                        throw (New-BattleJsonError -State $State -Message "High surrogate without a low surrogate")
                    }
                    $lowHex = $State.Text.Substring($State.Index + 2, 4)
                    if ($lowHex -cnotmatch '^[0-9A-Fa-f]{4}$') {
                        throw (New-BattleJsonError -State $State -Message "Invalid low-surrogate escape")
                    }
                    $lowUnit = [Convert]::ToInt32($lowHex, 16)
                    if ($lowUnit -lt 0xdc00 -or $lowUnit -gt 0xdfff) {
                        throw (New-BattleJsonError -State $State -Message "Invalid low surrogate")
                    }
                    $State.Index += 6
                    $codePoint = 0x10000 + (($codeUnit - 0xd800) * 0x400) + ($lowUnit - 0xdc00)
                    $null = $builder.Append([char]::ConvertFromUtf32($codePoint))
                    continue
                }
                if ($codeUnit -ge 0xdc00 -and $codeUnit -le 0xdfff) {
                    throw (New-BattleJsonError -State $State -Message "Low surrogate without a high surrogate")
                }
                $null = $builder.Append([char]$codeUnit)
                continue
            }
            default {
                throw (New-BattleJsonError -State $State -Message "Unsupported string escape '\$escape'")
            }
        }
    }
    throw (New-BattleJsonError -State $State -Message "Unterminated JSON string")
}

function Read-BattleJsonInteger {
    param([Parameter(Mandatory = $true)][hashtable]$State)

    $start = $State.Index
    if ($State.Text[$State.Index] -eq '-') {
        $State.Index++
        if ($State.Index -ge $State.Length) {
            throw (New-BattleJsonError -State $State -Message "Incomplete integer")
        }
    }
    if ($State.Text[$State.Index] -eq '0') {
        $State.Index++
        if ($State.Index -lt $State.Length -and $State.Text[$State.Index] -match '[0-9]') {
            throw (New-BattleJsonError -State $State -Message "Leading zero in integer")
        }
    }
    elseif ($State.Text[$State.Index] -match '[1-9]') {
        while ($State.Index -lt $State.Length -and $State.Text[$State.Index] -match '[0-9]') {
            $State.Index++
        }
    }
    else {
        throw (New-BattleJsonError -State $State -Message "Invalid integer")
    }
    if ($State.Index -lt $State.Length -and $State.Text[$State.Index] -in @('.', 'e', 'E')) {
        throw (New-BattleJsonError -State $State -Message "P0 manifests permit bounded integers only")
    }
    $token = $State.Text.Substring($start, $State.Index - $start)
    $value = 0L
    if (-not [Int64]::TryParse(
        $token,
        [Globalization.NumberStyles]::AllowLeadingSign,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$value
    )) {
        throw (New-BattleJsonError -State $State -Message "Integer is outside the signed 64-bit range")
    }
    return $value
}

function Read-BattleJsonLiteral {
    param(
        [Parameter(Mandatory = $true)][hashtable]$State,
        [Parameter(Mandatory = $true)][string]$Token,
        [AllowNull()][object]$Value
    )

    if ($State.Index + $Token.Length -gt $State.Length -or
        $State.Text.Substring($State.Index, $Token.Length) -cne $Token) {
        throw (New-BattleJsonError -State $State -Message "Invalid JSON literal")
    }
    $State.Index += $Token.Length
    return $Value
}

function Read-BattleJsonArray {
    param([Parameter(Mandatory = $true)][hashtable]$State)

    $State.Index++
    $items = [Collections.Generic.List[object]]::new()
    Skip-BattleJsonWhitespace -State $State
    if ($State.Index -lt $State.Length -and $State.Text[$State.Index] -eq ']') {
        $State.Index++
        return ,$items.ToArray()
    }
    while ($true) {
        $items.Add((Read-BattleJsonValue -State $State))
        Skip-BattleJsonWhitespace -State $State
        if ($State.Index -ge $State.Length) {
            throw (New-BattleJsonError -State $State -Message "Unterminated JSON array")
        }
        $delimiter = $State.Text[$State.Index]
        $State.Index++
        if ($delimiter -eq ']') {
            return ,$items.ToArray()
        }
        if ($delimiter -ne ',') {
            throw (New-BattleJsonError -State $State -Message "Expected ',' or ']' in array")
        }
        Skip-BattleJsonWhitespace -State $State
        if ($State.Index -lt $State.Length -and $State.Text[$State.Index] -eq ']') {
            throw (New-BattleJsonError -State $State -Message "Trailing comma in array")
        }
    }
}

function Read-BattleJsonObject {
    param([Parameter(Mandatory = $true)][hashtable]$State)

    $State.Index++
    $properties = [ordered]@{}
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    Skip-BattleJsonWhitespace -State $State
    if ($State.Index -lt $State.Length -and $State.Text[$State.Index] -eq '}') {
        $State.Index++
        return [PSCustomObject]$properties
    }
    while ($true) {
        Skip-BattleJsonWhitespace -State $State
        $name = Read-BattleJsonString -State $State
        if (-not $names.Add($name)) {
            throw (New-BattleJsonError -State $State -Message "Duplicate object key '$name'")
        }
        Skip-BattleJsonWhitespace -State $State
        if ($State.Index -ge $State.Length -or $State.Text[$State.Index] -ne ':') {
            throw (New-BattleJsonError -State $State -Message "Expected ':' after object key")
        }
        $State.Index++
        $properties[$name] = Read-BattleJsonValue -State $State
        Skip-BattleJsonWhitespace -State $State
        if ($State.Index -ge $State.Length) {
            throw (New-BattleJsonError -State $State -Message "Unterminated JSON object")
        }
        $delimiter = $State.Text[$State.Index]
        $State.Index++
        if ($delimiter -eq '}') {
            return [PSCustomObject]$properties
        }
        if ($delimiter -ne ',') {
            throw (New-BattleJsonError -State $State -Message "Expected ',' or '}' in object")
        }
        Skip-BattleJsonWhitespace -State $State
        if ($State.Index -lt $State.Length -and $State.Text[$State.Index] -eq '}') {
            throw (New-BattleJsonError -State $State -Message "Trailing comma in object")
        }
    }
}

function Read-BattleJsonValue {
    param([Parameter(Mandatory = $true)][hashtable]$State)

    Skip-BattleJsonWhitespace -State $State
    if ($State.Index -ge $State.Length) {
        throw (New-BattleJsonError -State $State -Message "Expected a JSON value")
    }
    $character = $State.Text[$State.Index]
    switch ($character) {
        '{' { return Read-BattleJsonObject -State $State }
        '[' { return Read-BattleJsonArray -State $State }
        '"' { return Read-BattleJsonString -State $State }
        't' { return Read-BattleJsonLiteral -State $State -Token "true" -Value $true }
        'f' { return Read-BattleJsonLiteral -State $State -Token "false" -Value $false }
        'n' { return Read-BattleJsonLiteral -State $State -Token "null" -Value $null }
        default {
            if ($character -eq '-' -or $character -match '[0-9]') {
                return Read-BattleJsonInteger -State $State
            }
            throw (New-BattleJsonError -State $State -Message "Unexpected JSON token '$character'")
        }
    }
}

function ConvertFrom-BattleStrictJson {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [string]$Label = "JSON"
    )

    $state = @{
        Text = $Text
        Length = $Text.Length
        Index = 0
        Label = $Label
    }
    if ($state.Length -gt 0 -and $state.Text[0] -eq [char]0xfeff) {
        throw (New-BattleJsonError -State $state -Message "UTF-8 BOM is not permitted")
    }
    $value = Read-BattleJsonValue -State $state
    Skip-BattleJsonWhitespace -State $state
    if ($state.Index -ne $state.Length) {
        throw (New-BattleJsonError -State $state -Message "Unexpected content after the root value")
    }
    return $value
}

function Read-BattleStrictJsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Label = "JSON file"
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "$Label was not found: $fullPath"
    }
    $bytes = [IO.File]::ReadAllBytes($fullPath)
    $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
    try {
        $text = $strictUtf8.GetString($bytes)
    }
    catch {
        throw "$Label is not valid UTF-8: $fullPath"
    }
    return ConvertFrom-BattleStrictJson -Text $text -Label $Label
}
