#!/usr/bin/env bash
# dispatch_signature.sh — map a distillation signature string to the plugin
# file that should be touched by an auto-fix PR.
#
# Stable contract for ccbridge-propose-fix-pr (v4.8.0+):
#   stdin: nothing
#   argv:  $1 = signature (e.g. "watchdog_recovery_started_pid")
#   stdout: plugin-root-relative path of the target file
#   exit:   0 if matched, 1 if no dispatch target, 2 if usage error
#
# Bash 3.2 compatible. Case statement is intentional (associative arrays
# only land in bash 4+, and macOS ships 3.2).

set -u

sig="${1-}"
if [ -z "$sig" ]; then
  exit 2
fi

case "$sig" in
  watchdog_*)            echo "develop-like-sudipta/skills/sd-claude-code-access/scripts/watchdog.sh" ;;
  diagnose_*)            echo "develop-like-sudipta/skills/sd-claude-code-access/scripts/diagnose.sh" ;;
  send_*)                echo "develop-like-sudipta/skills/sd-claude-code-access/scripts/send.sh" ;;
  launch_cc_*)           echo "develop-like-sudipta/skills/sd-claude-code-access/scripts/launch_cc.sh" ;;
  learning_*)            echo "develop-like-sudipta/skills/sd-claude-code-access/scripts/learning.sh" ;;
  state_*)               echo "develop-like-sudipta/skills/sd-claude-code-access/scripts/state.sh" ;;
  audit_*)               echo "develop-like-sudipta/skills/sd-claude-code-access/scripts/audit.sh" ;;
  scheduled_skill_*)     echo "develop-like-sudipta/assets/scheduled-tasks/**/SKILL.md" ;;
  cc_drive_*)            echo "develop-like-sudipta/commands/cc-drive.md" ;;
  directive_template_*)  echo "develop-like-sudipta/skills/sd-claude-code-access/assets/directive_template.md" ;;
  verify_gate_*)         echo "develop-like-sudipta/skills/sd-claude-code-access/references/verify_gate.md" ;;
  bug_driven_tdd_*)      echo "develop-like-sudipta/skills/sd-claude-code-access/references/bug_driven_tdd.md" ;;
  substrate_*)           echo "develop-like-sudipta/skills/sd-claude-code-access/references/substrate_and_access.md" ;;
  *)                     exit 1 ;;
esac
exit 0
