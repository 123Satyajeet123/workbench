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
run "1 quote check off" $C/Verify/Verifier.swift 's/throw Refusal\(\.quoteNotInLines\)\n    \}\n\n    \/\/\/ Like/return QuoteSpan(line: lines.first?.id ?? 0, part: 0, start: 0, end: 1)\n    }\n\n    \/\/\/ Like/' WorkbenchCore WorkbenchUI ../Testing
run "2 source switches ignored" $C/Capture/CapturePolicy.swift 's/switches\[kind\] \?\? false/true/' WorkbenchCore WorkbenchUI
run "3 WhatsApp allow-list off" $C/Capture/CapturePolicy.swift 's/needsAllowList: Set<SourceKind> = \[\.whatsapp, \.mail\]/needsAllowList: Set<SourceKind> = [.mail]/' WorkbenchCore BaseKit WorkbenchUI
run "4 team-member check off" $C/Verify/Verifier+Spec.swift 's/context\[set\]\?\.contains\(value\) == true/true/' WorkbenchCore WorkbenchUI
run "5 deleting a source keeps its items" $C/Store/Delete.swift 's/"DELETE FROM item WHERE source = \? AND start_at < \?"/"DELETE FROM item WHERE 0 AND source = ? AND start_at < ?"/' WorkbenchCore
run "6 no held-out days" $C/Runs/Quality.swift 's/Int\(first\) % 10 < Self\.heldOutTenths/false/' WorkbenchCore WorkbenchUI
run "7 audit pick not recorded" $C/Store/ItemStore.swift 's/"UPDATE item SET asked_with = \? WHERE id = \?"/"UPDATE item SET asked_with = ? WHERE 0 AND id = ?"/' WorkbenchCore WorkbenchUI
run "8 expired grants accepted" $C/Store/Store.swift 's/guard grant\.expiresAt > clock\(\) else/guard true else/' WorkbenchCore
run "9 nudge more than once a day" WorkbenchUI/Sources/WorkbenchUI/Workbench/Helpers/NudgeSchedule.swift 's/guard isOn, lastSent != day,/guard isOn,/' WorkbenchUI
run "10 overlapping timeline blocks kept" $C/Helpers/HelperReader+Relations.swift 's/spec\.lifecycle == nil && spec\.citation != \.one\n\s+&& kept\.contains/false \&\& kept.contains/' WorkbenchCore WorkbenchUI
run "11 trust threshold loosened to 20%" $C/Runs/Certificate.swift 's/if bound <= Self\.allowedWrong/if bound <= 0.2/' WorkbenchCore
run "13 screen text kept without its switch" $C/Capture/CaptureEngine.swift 's/if policy\.isEnabled\(\.screenText\), !snapshot/if true, !snapshot/' WorkbenchCore WorkbenchUI
run "14 private windows not hidden" $C/Capture/CapturePolicy+Verdict.swift 's/return snapshot\.secureFocus \|\|/return false \&\& snapshot.secureFocus ||/' WorkbenchCore
run "15 30-day retention never runs" BaseKit/Sources/CaptureService/CaptureService.swift 's/loop\.forget\(before: now\.addingTimeInterval\(-CapturePolicy\.retention\)\)/loop.forget(before: .distantPast)/' BaseKit
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
run "31 stop reading keeps the chat's lines" WorkbenchUI/Sources/WorkbenchUI/Workbench/Helpers/WhatsAppSource.swift 's/\{ \$0\.allowList\[\.whatsapp\]\?\.remove\(chat\.jid\) \}/{ _ in }/' WorkbenchUI
run "32 two app copies write the store" $C/Store/StoreLock.swift 's/flock\(file, LOCK_EX \| LOCK_NB\)/flock(file, LOCK_SH | LOCK_NB)/' WorkbenchCore
run "33 stopping a chat leaves it with another machine" WorkbenchUI/Sources/WorkbenchUI/Workbench/Helpers/WhatsAppSource.swift 's/where source\.chats\.contains\(where: \{ \$0\.id == chat\.id \}\)/where false/' WorkbenchUI
run "34 a discovered chat is stored before the person chooses it" WorkbenchUI/Sources/WorkbenchUI/Workbench/Helpers/WhatsAppSource.swift 's/(direct = candidates\.filter \{ \$0\.container\.kind == \.direct \}\.map\(WhatsAppChat\.init\)\n)/$1        try? capture.update { \$0.allowList[.whatsapp, default: []].formUnion(candidates.map(\\.id)) }\n/' WorkbenchUI
run "35 a group line is written without a valid membership observation" $C/Source/Discovery.swift 's/case \.group: membership\.map \{ AudienceDigest\(owner: owner, members: \$0\.members\) \}/case .group: AudienceDigest(owner: owner, members: membership?.members ?? [container.id])/' WorkbenchCore BaseKit
run "41 one chat is listed once per source" $C/Source/ContainerCandidates.swift 's/let id = sighting\.container\.id\n/let id = sighting.container.id + sighting.source\n/' WorkbenchCore WorkbenchUI
run "43 the capture log's delete keeps the window's text" $C/Store/Delete.swift 's/let doomed = matched \+ \(try Self\.screenTextRows\(opened: matched, in: db\)\)/let doomed = matched/' WorkbenchCore
run "44 an app that is not allowed is read by AX" BaseKit/Sources/CaptureService/CaptureService.swift 's/case \.read\(let grant\) = policy\.admission\(ofApp: app\.bundleID, at: now\)/let grant = policy.authorize(CaptureRequest(kind: .screen), at: now).grant/' BaseKit
run "45 AX reads while the screen is locked" $C/Capture/Presence.swift 's/if screenLocked \|\| !sessionOnConsole \{ return \.locked \}\n//' WorkbenchCore BaseKit
run "46 AX reads while the person is idle" $C/Capture/Presence.swift 's/return idleSeconds >= idleAfter \? \.idle : \.active/return .active/' WorkbenchCore BaseKit
run "47 the loop reads before it checks presence" BaseKit/Sources/CaptureService/CaptureService.swift 's/guard presence == \.active, case/guard case/' BaseKit
run "48 an app with no bundle id is read" $C/Capture/CapturePolicy+Verdict.swift 's/guard !bundleID\.isEmpty else \{ return bare\(\.screen, at: now\) \}\n//' WorkbenchCore BaseKit
run "49 deleting a window deletes the next stretch of the same app" $C/Store/Delete.swift 's/AND text\.id < COALESCE\(\(SELECT MIN\(next\.id\) FROM activity next WHERE next\.id > window\.id\n\s+AND next\.kind IN \(.window.,.idle.,.sleep.,.skipped.,.wake.\)\), 9223372036854775807\)/AND 1/' WorkbenchCore
run "50 a true quote with a curly apostrophe is dropped" $C/Model/QuoteFold.swift 's/append\(Self\.marks\[folded\] \?\? folded, from: offset\)/append(folded, from: offset)/' WorkbenchCore
run "51 a dropped proposal leaves no reason" $C/Verify/DropStore.swift 's/\{ try store\.recordDrops\(drops, of: run\) \}/{ _ = drops }/' WorkbenchCore
run "52 the model sets a fact's label" $C/Verify/Verifier+Spec.swift 's/label: standing\.label, authority/label: raw["label"] == nil ? standing.label : nil, authority/' WorkbenchCore
run "53 a fact gets more authority than its weakest cited line" $C/Verify/Standing.swift 's/parts\.map\(\\\.authority\)\.min\(\)/parts.map(\\.authority).max()/' WorkbenchCore
run "54 a quote that nearly matches is accepted" $C/Model/QuoteFold.swift 's/scalars\.firstRange\(of: quote\.scalars\)/scalars.firstRange(of: quote.scalars) ?? (scalars.isEmpty ? nil : 0..<1)/' WorkbenchCore
run "55 a quote's offsets end one early" $C/Model/QuoteFold.swift 's/origins\[range\.upperBound - 1\] \+ 1\)/origins[range.upperBound - 1])/' WorkbenchCore
run "56 a choice outside its values is kept" $C/Verify/Verifier+Spec.swift 's/case \.choice\(let values\): values\.contains\(value\)/case .choice: true/' WorkbenchCore
run "57 a date that is not a day is kept" $C/Verify/Verifier+Spec.swift 's/WorkDay\(value\) != nil/true/' WorkbenchCore
run "58 a failed check names no reason" $C/Verify/Verifier.swift 's/return \.dropped\(\.verifierError\)/return .dropped(.malformed)/' WorkbenchCore
run "60 drop rows outlive the run text" $C/Store/SchemaGroundedFacts.swift 's/REFERENCES run_text\(run_id\) ON DELETE CASCADE/REFERENCES run_text(run_id) ON DELETE NO ACTION/' WorkbenchCore
run "61 a line already read can be cited" $C/Verify/Verifier.swift 's/guard !window\.isRead\(number\), let line/guard let line/' WorkbenchCore
run "62 a fact with an unlabelled line keeps a label" $C/Verify/Standing.swift 's/known\.count == parts\.count \?/true ?/' WorkbenchCore
run "63 a fact's label ignores an uncited window line" $C/Verify/Standing.swift 's/\(lines \+ window\)\.map\(\\\.standing\)/lines.map(\\.standing)/' WorkbenchCore
run "64 a fact the person typed is not their own words" $C/Team/DealAction.swift 's/Authority\.ownWords\.rawValue/Authority.unknown.rawValue/' WorkbenchCore
run "65 a stage may change its meaning" $C/Objects/ObjectType.swift 's/guard changed\.meaning == stage\.meaning else \{ throw ObjectTypeError\.meaningChanged\(stage\.id\) \}/_ = changed/' WorkbenchCore
run "66 a machine moves a deal without citing the required fact" $C/Objects/ObjectMove.swift 's/if mover == \.machine \{/if mover == .machine, false {/' WorkbenchCore
run "67 an old stage label no longer folds to its stage id" $C/Objects/ObjectType.swift 's/stages\.first \{ \$0\.label == text \}/stages.first { \$0.label == text + "!" }/' WorkbenchCore WorkbenchUI
run "68 a deal in a won stage is not followed in the news" $C/News/WatchedCompany.swift 's/deal\.meanings\.contains\(\.won\) \? \.portfolio/deal.meanings.contains(.lost) ? .portfolio/' WorkbenchCore WorkbenchUI
run "69 the reader misses iframe text" ../Extension/manifest.json 's/"all_frames": true,/"all_frames": false,/' WorkbenchCore
run "70 an unknown browser is called Chrome" $C/Capture/PeerBrowser.swift 's/return bundleID\(ofExecutable: path\)\n/return bundleID(ofExecutable: path) ?? "com.google.Chrome"\n/' WorkbenchCore
run "71 a stale adapter writes lines" ../Extension/read/page.js 's/\n    if \(shape\.stale\) return \{[^\n]*\n/\n/' WorkbenchCore
run "72 a class-name selector is used" ../Extension/read/generic.js 's/querySelector\("h1, h2, h3, h4, h5, h6, \[role=.heading.\]"\)/querySelector("h2.hP")/' WorkbenchCore
run "73 a line without an id gets a made-up id" ../Extension/read/page.js 's/id: null, via: null, text/id: text, via: "text", text/' WorkbenchCore
run "74 a replace deletes a fact the founder closed" $C/Store/ItemStore.swift 's/(            let known = try knownItems)/            try db.execute(sql: "DELETE FROM item WHERE task = ? AND day = ?", arguments: [spec.task, day.description])\n$1/' WorkbenchCore
run "75 a model close overrides the founder's later reopen" $C/Store/SchemaFactLifecycle.swift 's/(CREATE VIEW item_status.*?PARTITION BY item_id ORDER BY )valid_at DESC, recorded_at DESC, id DESC/$1id DESC/s' WorkbenchCore
run "76 a changed date makes a new fact" $C/Helpers/HelperReader+Relations.swift 's/(case \.sameAs\(let id\):\n)/$1                items.append(item)\n/' WorkbenchCore
run "77 a handle outside the shown open set is applied" $C/Verify/Verifier+Spec.swift 's/(open\[index - 1\]\.id != nil\n        else \{ )throw Refusal\(\.unknownHandle\)( \})/$1guard let first = open.first else { throw Refusal(.unknownHandle) }; return first$2/' WorkbenchCore WorkbenchUI
run "78 an erased line's words survive in a fact field" $C/Store/EvidenceCopies.swift 's/        try emptyModelWords\(ofItems: itemIDs, in: db\)\n//' WorkbenchCore
run "79 a news feed the machine's spec does not list is fetched" $C/News/NewsFeed.swift 's/guard feeds\.contains\(feed\) else \{ throw FeedError\.notAFeed\(feed\.url\) \}\n//' WorkbenchCore
run "80 a news feed host is named in code outside the template data" $C/News/NewsFeed.swift 's/The feeds are a list in the machine.s spec/The feeds, such as inc42.com, are a list in the machine'"'"'s spec/' WorkbenchCore
run "81 a claim type the spec does not list is kept" $C/Claims/ClaimExtractor.swift 's/\.enumeration\(types\.map\(\\\.id\)\)/.string/' WorkbenchCore
run "82 a store that has machines is started from a template again" $C/Store/CrewStore.swift 's/guard try !queries\.holdsMachine\(\) else \{ return TeamStart\(\) \}\n//' WorkbenchCore
run "83 a template asks for one source twice" $C/Templates/TeamTemplate.swift 's/if !needs\.contains\(where: \{ \$0\.kind == kind \}\) \{/if true {/' WorkbenchCore
run "84 an existing machine loses the feeds of its template" $C/Templates/MachineTemplate.swift 's/spec\.feeds = feeds \?\? template\?\.feeds/spec.feeds = feeds/' WorkbenchCore WorkbenchUI
run "85 a setup answer is not saved into its machine's spec" $C/Store/CrewStore.swift 's/            try apply\(answer, to: machine\)\n//' WorkbenchCore WorkbenchUI
run "86 a claim type list with no type is saved" $C/Store/SpecListStore.swift 's/guard !types\.isEmpty, /guard /' WorkbenchCore
run "87 a news feed with no name is saved" $C/Store/SpecListStore.swift 's/guard feeds\.allSatisfy\(\{ \$0\.name\.cleaned != nil \}\) else \{ return \}\n//' WorkbenchCore
run "88 the set-up step is asked when no machine has a field" WorkbenchUI/Sources/WorkbenchUI/Onboarding/OnboardingModel.swift 's/\{ \$0 != \.setup \|\| !questions\.isEmpty \}/{ _ in true }/' WorkbenchUI
run "89 connect lists a source no machine needs" WorkbenchUI/Sources/WorkbenchUI/Onboarding/ConnectStatus.swift 's/\[\.reader\] \+ needs\.compactMap \{ Self\(\$0\.kind\) \}/[.reader] + Self.sources/' WorkbenchUI
run "90 finishing setup makes no machine" WorkbenchUI/Sources/WorkbenchUI/Onboarding/OnboardingModel.swift 's/            try store\?\.startTeam\(from: template, answers: answers\)\n//' WorkbenchUI
run "91 questions are asked for a store that holds machines" WorkbenchUI/Sources/WorkbenchUI/Onboarding/OnboardingModel.swift 's/startsTeam \? template\.setupQuestions : \[\]/template.setupQuestions/' WorkbenchUI
run "92 the app seeds Pip and Timeline at launch, before the chosen template" WorkbenchUI/Sources/WorkbenchUI/Data/AppLaunch.swift 's/(let identity = IdentityModel\(store: store\)\n)/$1            try store.seedMachines(MachineTemplate.seeded.map { (\$0.spec, \$0.name) })\n/' WorkbenchUI
run "93 machines with different template values share one setup question" $C/Templates/TeamSetup.swift 's/\$0\.kind == kind && \$0\.templateValue == value/\$0.kind == kind/' WorkbenchCore WorkbenchUI
echo DONE
