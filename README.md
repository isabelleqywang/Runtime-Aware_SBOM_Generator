# NYU-DTCC-VIP-Final-Project-2025-Fall-Isabelle Wang

**NYU DTCC VIP Final Project - Fall 2025**  
*Isabelle Wang*

## What This Does

Normal SBOM tools like Syft only see what's in your code folder. They miss libraries that actually load when you run a program. This tool fixes that by watching what happens when the program runs.

## Why It Matters

Example: When you run `curl`, it loads OpenSSL and crypto libraries. Regular SBOM tools don't catch this. For security, you need to know what *actually* runs, not just what's on disk.

## How to Install

```bash
# Install required tools
brew install syft jq

# Clone and setup
git clone https://github.com/IsabelleQYWang/NYU-DTCC-VIP-Final-Project-2025-Fall-Isabelle.git
cd NYU-DTCC-VIP-Final-Project-2025-Fall-Isabelle
chmod +x sbom-generator.sh
```

## How to Use

**Basic usage (finds linked libraries):**
```bash
./sbom-generator.sh -t /bin/ls -o results
```

**With runtime tracing (requires sudo):**
```bash
sudo ./sbom-generator.sh -t /usr/bin/curl -e -o results
```

## What It Does

1. **Syft** scans for packages
2. **otool** finds libraries linked to the binary
3. **dtruss** watches what loads when you actually run it
4. Combines everything into one SBOM

## Example Output

```json
{
  "artifacts": [...],
  "dynamicDependencies": {
    "libraries": [
      {
        "name": "libSystem.B.dylib",
        "path": "/usr/lib/libSystem.B.dylib",
        "source": "otool"
      }
    ],
    "summary": {
      "total": 3,
      "static": 3,
      "runtime": 0
    }
  }
}
```

## Viewing Results

```bash
# See all libraries found
jq '.dynamicDependencies.libraries' results/final-sbom.json

# Count them
jq '.dynamicDependencies.summary' results/final-sbom.json
```

## Known Issues

**macOS System Integrity Protection (SIP)**

macOS blocks `dtruss` from tracing system programs like `/usr/bin/curl`. This is a security feature. What works:
- Static analysis with `otool` - always works
- Runtime tracing on programs you compile yourself
What does not work:
- Runtime tracing on system binaries (blocked by SIP)

The static analysis alone still finds more than Syft does.

## Why This Is Useful

Programs can load libraries in ways static tools miss:
- Plugins loaded at runtime
- Libraries loaded with `dlopen()`
- Dependencies that only load in certain situations

**Real example:** Log4Shell vulnerability. If an app loads Log4j dynamically, static SBOMs won't see it. This tool would catch it running.

## Testing

```bash
# Test on /bin/ls
./sbom-generator.sh -t /bin/ls -o test-output

# Check results
jq '.dynamicDependencies.libraries | length' test-output/final-sbom.json
```

Should find 3 libraries (libSystem, libncurses, libutil).
