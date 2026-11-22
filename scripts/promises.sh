#!/bin/zsh
# Product promises, checked by planting one bug at a time behind each and running the tests. A promise is guarded
# only if its bug fails at least one test; "caught by 0" is a promise no test protects. Each file is copied before its
# bug is planted and restored from the copy after; git is never used to undo. Run it before deleting or rewriting
# tests: the number of caught bugs must not drop. Add a line when a product promise is added.
set -u
cd ${0:A:h:h}
touch .promises-running
trap 'rm -f .promises-running' EXIT
trap 'print -u2 "stopped: a planted bug may still be in place; check git diff"' INT TERM
cd Packages
C=WorkbenchCore/Sources/WorkbenchCore
run() { # name file perl-expr packages...
  local name=$1 file=$2 expr=$3; shift 3
  local saved=$(mktemp)
  cp "$file" "$saved"
  perl -0pi -e "$expr" "$file"
  if cmp -s "$file" "$saved"; then echo "$name | NOT APPLIED (the code changed: update this line)"; rm "$saved"; return; fi
  local failed="" unfinished=""
  for pkg in "$@"; do
    out=$(cd $pkg && swift test 2>&1)
    if ! print -r -- "$out" | grep -qE 'Test run with [0-9]+ tests?' || print -r -- "$out" | grep -q "error: .*failed with a nonzero exit\|Build failed"; then
      local raw="${TMPDIR:-/tmp}/promise-${name// /-}-${pkg:t}.log"
      print -r -- "$out" > "$raw"
      unfinished+=" [$pkg: run failed, raw output in $raw]"
      continue
    fi
    failed+=" $(print -r -- "$out" | grep -oE '✘ Test [A-Za-z0-9_]+\(' | sed 's/✘ Test //; s/(//' | sort -u | tr '\n' ' ')"
  done
  cp "$saved" "$file"
  rm "$saved"
  local n=$(print -r -- $failed | wc -w | tr -d ' ')
  if [[ -n $unfinished ]]; then echo "$name | RUN FAILED, no count |$unfinished | partial: $failed"; return; fi
  echo "$name | caught by $n | $failed"
}
run "1 quote check off" $C/Helpers/Evidence.swift 's/quotable\.contains \{ \$0\.contains\(quote: quote\) \}/true/' WorkbenchCore WorkbenchUI ../Testing
run "2 source switches ignored" $C/Capture/CapturePolicy.swift 's/switches\[kind\] \?\? false/true/' WorkbenchCore WorkbenchUI
run "3 WhatsApp allow-list off" $C/Capture/CapturePolicy.swift 's/needsAllowList: Set<SourceKind> = \[\.whatsapp, \.mail\]/needsAllowList: Set<SourceKind> = [.mail]/' WorkbenchCore BaseKit WorkbenchUI
run "4 team-member check off" $C/Helpers/HelperReader.swift 's/context\[set\]\?\.contains\(value\) == true/true/' WorkbenchCore WorkbenchUI
run "5 deleting a source keeps its items" $C/Store/Delete.swift 's/"DELETE FROM item WHERE source = \? AND start_at < \?"/"DELETE FROM item WHERE 0 AND source = ? AND start_at < ?"/' WorkbenchCore
run "6 no held-out days" $C/Runs/Quality.swift 's/Int\(first\) % 10 < Self\.heldOutTenths/false/' WorkbenchCore WorkbenchUI
run "7 audit pick not recorded" $C/Store/ItemStore.swift 's/"UPDATE item SET asked_with = \? WHERE id = \?"/"UPDATE item SET asked_with = ? WHERE 0 AND id = ?"/' WorkbenchCore WorkbenchUI
run "8 expired grants accepted" $C/Store/Store.swift 's/guard grant\.expiresAt > clock\(\) else/guard true else/' WorkbenchCore
run "9 nudge more than once a day" WorkbenchUI/Sources/WorkbenchUI/Workbench/Helpers/NudgeSchedule.swift 's/guard isOn, lastSent != day,/guard isOn,/' WorkbenchUI
run "10 overlapping timeline blocks kept" $C/Helpers/HelperReader.swift 's/spec\.citation == \.one\n\s+\|\| !kept\.contains/true || !kept.contains/' WorkbenchCore WorkbenchUI
run "11 trust threshold loosened to 20%" $C/Runs/Certificate.swift 's/if bound <= Self\.allowedWrong/if bound <= 0.2/' WorkbenchCore
run "13 screen text kept without its switch" $C/Capture/CaptureEngine.swift 's/if policy\.isEnabled\(\.screenText\), !snapshot/if true, !snapshot/' WorkbenchCore WorkbenchUI
run "14 private windows not hidden" $C/Capture/CapturePolicy+Verdict.swift 's/return snapshot\.secureFocus \|\|/return false \&\& snapshot.secureFocus ||/' WorkbenchCore
run "15 30-day retention never runs" BaseKit/Sources/CaptureService/CaptureService.swift 's/loop\.forget\(before: now\.addingTimeInterval\(-CapturePolicy\.retention\)\)/loop.forget(before: .distantPast)/' BaseKit
run "17 rereading drops marked items" $C/Store/ItemStore.swift "s/AND scope = \\? AND state = 'proposed'\\)/AND scope = ?)/" WorkbenchCore WorkbenchUI
run "18 a live call can be deleted" $C/Store/Delete.swift "s/let condition = \"state != 'recording' AND started_at < \\?\"/let condition = \"started_at < ?\"/" WorkbenchCore
run "19 prompt texts not kept" $C/Runs/Quality.swift 's/"INSERT OR IGNORE INTO prompt\(hash/"INSERT OR IGNORE INTO prompt(hash, task, instructions, schema, first_used) SELECT * FROM (SELECT ?,?,?,?,?) WHERE 0 --(hash/' WorkbenchCore
run "21 idle does not end a session" $C/Helpers/Sessions.swift 's/case \.idle, \.sleep:/case .sleep:/; s/case \.text, \.page, \.file:/case .text, .page, .file, .idle:/' WorkbenchCore WorkbenchUI
run "22 nudge fires before its time" WorkbenchUI/Sources/WorkbenchUI/Workbench/Helpers/NudgeSchedule.swift 's/return now >= time/return true/' WorkbenchUI
run "23 a silent call is saved" BaseKit/Sources/LocalSources/CallAudio.swift 's/guard !files\.isEmpty else \{ throw CallAudioError\.emptyTrack\(track\) \}/_ = files/' BaseKit
run "24 WhatsApp reads every chat" BaseKit/Sources/LocalSources/WhatsAppChatReader+Evidence.swift 's/WHERE m\.ZCHATSESSION = \?\n/WHERE (m.ZCHATSESSION = ? OR 1)\n/' BaseKit WorkbenchUI
run "20 API keys passed to the CLI" BaseKit/Sources/AgentCLI/ProcessPlan.swift 's/var environment = \["HOME"/var environment = inherited\n        environment = environment.merging(["HOME"/; s/("PATH": path\.joined\(separator: ":"\)\])/$1) { _, new in new }/; s/forbiddenNames\.contains\(name\) \|\| forbiddenPrefixes\.contains \{ name\.hasPrefix\(\$0\) \}/false/' BaseKit
run "12 model gets tools, guard removed" BaseKit/Sources/AgentCLI/ProcessPlan.swift 's/"--tools", "",/"--tools", "Bash",/; s/"--tools": "", //' BaseKit
run "25 a revoke leaves its words in a quote or run text" $C/Store/EvidenceWriter.swift 's/report\.flaggedItems = try Store\.eraseCopies\(of: \.line\(lineID\), in: db\)/report.flaggedItems = 0/' WorkbenchCore
run "26 Settings WhatsApp delete keeps lines" BaseKit/Sources/CaptureService/CaptureService.swift 's/try store\.delete\(\.kind\(kind, before: nil\)\)/try store.delete(.kind(.typed, before: nil))/' BaseKit WorkbenchUI
run "27 removing a chat keeps its lines" BaseKit/Sources/CaptureService/CaptureService.swift 's/for chat in withdrawn \{ try store\.eraseEvidence/for chat in [String]() { try store.eraseEvidence/' BaseKit
run "28 the native host writes the store" WorkbenchCore/Package.swift 's/executableTarget\(name: "WorkbenchPages", dependencies: \["PagesRelay"\]\)/executableTarget(name: "WorkbenchPages", dependencies: ["PagesRelay", "WorkbenchCore"])/' WorkbenchCore
run "29 WhatsApp Web writes a chat that is not allowed" $C/WhatsApp/WhatsAppWebIntake.swift 's/\.sorted\(\)\.first \{ WhatsAppJID\.canonical\(\$0\) == chat \}/.sorted().first/' WorkbenchCore BaseKit
run "30 both sources write one chat" $C/Source/SourceDescriptor.swift 's/descriptor\.fallbackFor\.map \{ !readable\.contains\(\$0\) \} \?\? true/true/' WorkbenchCore BaseKit
run "31 stop reading keeps the chat's lines" WorkbenchUI/Sources/WorkbenchUI/Workbench/Helpers/WhatsAppSource.swift 's/\{ \$0\.allowList\[\.whatsapp\]\?\.remove\(chat\.jid\) \}/{ _ in }/' WorkbenchUI
run "32 two app copies write the store" $C/Store/StoreLock.swift 's/flock\(file, LOCK_EX \| LOCK_NB\)/flock(file, LOCK_SH | LOCK_NB)/' WorkbenchCore
run "33 stopping a chat leaves it with another machine" WorkbenchUI/Sources/WorkbenchUI/Workbench/Helpers/WhatsAppSource.swift 's/where source\.chats\.contains\(where: \{ \$0\.id == chat\.id \}\)/where false/' WorkbenchUI
echo DONE
