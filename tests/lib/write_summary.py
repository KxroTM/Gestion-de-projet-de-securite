#!/usr/bin/env python3
"""Construit le tableau recapitulatif (Exigence | Test | Resultat | Duree) a partir des
reports/*.json et du resultat du job Trivy, et l'ecrit dans $GITHUB_STEP_SUMMARY.
Sort avec le code 1 si une exigence n'est pas OK (sert de porte finale pour la CI)."""
import json
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPORTS_DIR = os.path.join(SCRIPT_DIR, "..", "..", "reports")

# (exigence, nom du test, identifiant du rapport JSON)
ROWS = [
    ("DS09", "test_ports.sh", "ports"),
    ("E06", "test_whitelist.js", "whitelist"),
    ("E09", "test_restart.sh", "restart"),
    ("E08", "test_backup_restore.sh", "backup_restore"),
    ("DS07", "test_backup_restore.sh", "backup_restore"),
    ("DS03", "test_encryption.sh", "encryption"),
    ("DS05", "test_secrets_detection.sh", "secrets_detection"),
]


def load_report(report_id):
    path = os.path.join(REPORTS_DIR, f"{report_id}.json")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def main():
    lines = ["| Exigence | Test | Resultat | Duree |", "| --- | --- | --- | --- |"]
    all_ok = True

    for requirement, test_name, report_id in ROWS:
        report = load_report(report_id)
        if report is None:
            lines.append(f"| {requirement} | {test_name} | MANQUANT | - |")
            all_ok = False
            continue
        result = report.get("result", "FAIL")
        duration = report.get("duration_s", "?")
        if result != "OK":
            all_ok = False
        lines.append(f"| {requirement} | {test_name} | {result} | {duration}s |")

    # Controle supplementaire, sans exigence numerotee dediee : scan Trivy des images.
    images_result = os.environ.get("IMAGES_JOB_RESULT", "unknown")
    images_ok = "OK" if images_result == "success" else "FAIL"
    if images_ok != "OK":
        all_ok = False
    lines.append(f"| -    | Scan des images (Trivy, job images) | {images_ok} | - |")

    output = "\n".join(lines) + "\n"
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as f:
            f.write("## Recapitulatif securite\n\n")
            f.write(output)
    print(output)

    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
