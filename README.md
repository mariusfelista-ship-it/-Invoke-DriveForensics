# Invoke-DriveForensics

**Enterprise Drive Security Audit & Forensic Hardening Suite**

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)](https://docs.microsoft.com/powershell/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![NIST 800-88](https://img.shields.io/badge/Compliance-NIST%20SP%20800--88-green)]()

Military-grade PowerShell automation for incident response readiness, threat hunting, and forensic integrity. Implements NIST SP 800-88 sanitization standards with cryptographic chain-of-custody logging.

## 🎯 Key Capabilities

- **🔍 Threat Detection**: Alternate Data Stream (ADS) analysis for steganography/malware detection
- **🔐 Integrity Verification**: DISM/SFC with tamper-evident SHA256 hashing
- **🧬 Forensic Analysis**: Bad sector detection, file system corruption identification
- **🛡️ Security Hardening**: NIST-compliant free space sanitization
- **📋 Compliance Reporting**: Automated SOC2/ISO27001 audit trails
- **⚖️ Legal Admissibility**: Chain-of-custody preservation with cryptographic seals

## 🚀 Quick Start

```powershell
# Standard security audit
.\Invoke-DriveSecurityAudit.ps1

# Forensic mode with evidence preservation
.\Invoke-DriveSecurityAudit.ps1 -EvidenceMode -ComplianceStandard NIST80088

# Quick optimization (skip system repair)
.\Invoke-DriveSecurityAudit.ps1 -SkipSystemRepair
