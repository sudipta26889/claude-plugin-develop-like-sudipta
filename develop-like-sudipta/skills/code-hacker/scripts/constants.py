#!/usr/bin/env python3
"""Shared constants for Code Hacker audit scripts."""

SEVERITY_LEVELS = ("CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO")
SEVERITY_ICONS = {
    "CRITICAL": "💣", "HIGH": "🔴", "MEDIUM": "🟠", "LOW": "🟡", "INFO": "🔵"
}

CATEGORIES = (
    "RECON", "INJECTION", "AUTH", "AUTHZ", "SECRETS", "CRYPTO", "INPUT",
    "API", "DESER", "SUPPLY", "CONFIG", "SSRF", "FILE", "XSS", "ARCH",
    "CONCUR", "LOGGING", "CONTAINER", "AI", "PERF", "PROTO", "QUALITY",
)

SCRIPT_MAP = (
    ("01_recon.sh", "RECON"),
    ("02_injection.sh", "INJECTION"),
    ("03_auth.sh", "AUTH"),
    ("04_authz.sh", "AUTHZ"),
    ("05_secrets.sh", "SECRETS"),
    ("06_crypto.sh", "CRYPTO"),
    ("07_input.sh", "INPUT"),
    ("08_api.sh", "API"),
    ("09_deser.sh", "DESER"),
    ("10_supply.sh", "SUPPLY"),
    ("11_config.sh", "CONFIG"),
    ("12_ssrf.sh", "SSRF"),
    ("13_file.sh", "FILE"),
    ("14_xss.sh", "XSS"),
    ("15_arch.sh", "ARCH"),
    ("16_concur.sh", "CONCUR"),
    ("17_logging.sh", "LOGGING"),
    ("18_container.sh", "CONTAINER"),
    ("19_ai.sh", "AI"),
    ("20_perf.sh", "PERF"),
    ("21_proto.sh", "PROTO"),
    ("22_quality.sh", "QUALITY"),
    ("23_dast_fuzz.sh", "DAST"),
)

# Bounds for CLI arguments
MAX_PARALLEL = 64
MIN_PARALLEL = 1
MAX_TIMEOUT = 3600
MIN_TIMEOUT = 10
MAX_FINDINGS = 50000

# Blocked internal hosts for SSRF prevention
BLOCKED_HOSTS = frozenset({
    "localhost", "127.0.0.1", "::1", "0.0.0.0",
    "169.254.169.254",  # AWS metadata
    "metadata.google.internal",  # GCP metadata
})
