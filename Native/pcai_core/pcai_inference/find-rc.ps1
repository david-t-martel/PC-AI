Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin" -Recurse -Filter "rc.exe" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -like "*x64*" } |
    Sort-Object { [version]($_.FullName -replace '^.*\\(\d+\.\d+\.\d+\.\d+)\\.*$', '$1') } -Descending |
    Select-Object -First 1 -ExpandProperty FullName
