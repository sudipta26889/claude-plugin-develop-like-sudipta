# 📁 FILE — File Upload & Path Traversal Attacks

## Mission
Break file handling — upload malicious files, traverse paths, steal data.

## Detection
```bash
rg -n "upload|multipart|file.*save|write.*file|move_uploaded" -i
rg -n "open\(.*request|open\(.*params|readFile.*req\." 
rg -n "os\.path\.join.*request|path\.join.*req\.|filepath\.Join.*r\." 
```

## Checklist

### File Upload
- [ ] File type validation (extension AND magic bytes/MIME, not just extension)
- [ ] Maximum file size enforced server-side
- [ ] Filename sanitized (no path separators, null bytes, special chars)
- [ ] Upload directory outside webroot (can't access uploaded files directly)
- [ ] No execution permission on upload directory
- [ ] Image files re-processed/re-encoded (strip EXIF, prevent polyglot)
- [ ] Archive extraction: zip bomb, zip slip (path traversal in archive)
- [ ] SVG upload: can contain JavaScript (XSS)
- [ ] HTML upload: can contain scripts

### Path Traversal
- [ ] `../` in file paths from user input
- [ ] Null byte injection (`%00`) to truncate extension checks
- [ ] URL encoding bypass (`%2e%2e%2f`)
- [ ] Absolute paths accepted where relative expected
- [ ] Symlink following (upload symlink → read arbitrary file)
- [ ] Windows-specific: `..\\`, `C:\`, alternate data streams

### Defense Verification
```bash
rg -n "realpath|abspath|canonical|resolve|normalize" 
rg -n "startswith|starts_with|HasPrefix" 
# Good: resolved_path.startswith(base_directory)
```
