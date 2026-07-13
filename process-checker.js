#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const SPECSHIP_DIR = path.join(process.cwd(), '.specship');
const SPECS_DIR = path.join(SPECSHIP_DIR, 'specs');
const COMPLETED_DIR = path.join(SPECSHIP_DIR, 'completed');
const ARTIFACTS_DIR = path.join(SPECSHIP_DIR, 'artifacts');
const VERDICTS_DIR = path.join(ARTIFACTS_DIR, 'verdicts');
const STATE_FILE = path.join(SPECSHIP_DIR, 'state.json');
const EXPECTED_VALIDATORS_FILE = path.join(ARTIFACTS_DIR, 'expected-validators.txt');
const BUILD_STATUS_FILE = path.join(ARTIFACTS_DIR, 'build-status.json');
const MARKET_RESEARCH_SKIP_FILE = path.join(ARTIFACTS_DIR, 'market-research-skipped.txt');

// === Phase routing ===
// SpecShip transitions are guarded at three boundaries; each gate only asserts
// what should already exist at that point:
//   plan  (PLAN->BUILD)     : plan artifacts + market research (or a skip marker)
//   build (BUILD->VALIDATE) : plan artifacts + all tasks complete + build green + expected-validators written
//   ship  (VALIDATE->SHIP)  : plan artifacts + all tasks complete + every expected verdict present, none SKIPPED, no blocking issues
const VALID_PHASES = ['plan', 'build', 'ship'];

function parsePhase(argv) {
  let phase = 'ship'; // default keeps backward-compatible behavior (the original VALIDATE->SHIP gate)
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--phase') {
      phase = (argv[i + 1] || '').toLowerCase();
      i++;
    } else if (a.startsWith('--phase=')) {
      phase = a.slice('--phase='.length).toLowerCase();
    }
  }
  if (!VALID_PHASES.includes(phase)) {
    console.error(`Invalid --phase "${phase}". Use one of: ${VALID_PHASES.join(', ')}`);
    process.exit(2);
  }
  return phase;
}

// Evidence enforcement is STRICT BY DEFAULT (T17 gate-trusts-agent-evidence,
// T18 validator-independence): a green flag the agent wrote for itself — with no
// command/log evidence, or no proof the validator ran independently — is a hard FAIL,
// not a soft pass. Opt-in security is not security, so this is the default, not a flag.
//
// Escape hatch for genuinely-legacy runs: --lenient (or SPECSHIP_LENIENT_GATE=1)
// downgrades these to loud WARNINGS instead of failures. --strict is still accepted as
// an explicit no-op for backward compatibility. --lenient wins if both are supplied.
function parseStrict(argv) {
  if (process.env.SPECSHIP_LENIENT_GATE === '1') return false;
  if (argv.includes('--lenient')) return false;
  return true;
}
const STRICT = parseStrict(process.argv.slice(2));
const warnings = [];
function warnOrFail(name, message) {
  // In strict mode this is a failing check; otherwise a recorded warning.
  if (STRICT) {
    check(name, false, `[strict] ${message}`);
  } else {
    warnings.push(`${name}: ${message}`);
  }
}

const results = [];

function check(name, passed, reason) {
  results.push({ name, passed, reason });
}

function readJson(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  return JSON.parse(raw);
}

function findSpecDirs() {
  // Look in .specship/specs/ and .specship/completed/ for any spec directory
  for (const base of [SPECS_DIR, COMPLETED_DIR]) {
    if (!fs.existsSync(base)) continue;
    const dirs = fs.readdirSync(base, { withFileTypes: true })
      .filter(d => d.isDirectory())
      .map(d => path.join(base, d.name));
    if (dirs.length > 0) return dirs;
  }
  return [];
}

// === Plan artifacts (PLAN output) — used by all phases ===

function checkPlanArtifacts() {
  const requiredFiles = ['requirements.md', 'design.md', 'tasks.md'];
  const specDirs = findSpecDirs();

  if (specDirs.length === 0) {
    check('Plan Artifacts Exist', false, 'No spec directories found in .specship/specs/ or .specship/completed/');
    return;
  }

  const missing = [];
  for (const file of requiredFiles) {
    let found = false;
    for (const dir of specDirs) {
      if (fs.existsSync(path.join(dir, file))) { found = true; break; }
    }
    if (!found) missing.push(file);
  }

  if (missing.length === 0) {
    check('Plan Artifacts Exist', true, `Found all required files: ${requiredFiles.join(', ')}`);
  } else {
    check('Plan Artifacts Exist', false, `Missing plan artifacts: ${missing.join(', ')}`);
  }
}

// === Market research (PLAN output) — plan gate only ===
// Market research is mandatory for products with real-world equivalents, but the
// workflow legitimately skips it (pure backend, bugfix, infra). A skip is allowed
// ONLY when the plan phase recorded the reason in market-research-skipped.txt.

function checkMarketResearch() {
  const specDirs = findSpecDirs();
  for (const dir of specDirs) {
    for (const rel of ['market-research.md', path.join('artifacts', 'market-research.md')]) {
      if (fs.existsSync(path.join(dir, rel))) {
        check('Market Research', true, `Found ${rel}`);
        return;
      }
    }
  }
  if (fs.existsSync(MARKET_RESEARCH_SKIP_FILE)) {
    const reason = fs.readFileSync(MARKET_RESEARCH_SKIP_FILE, 'utf8').trim().split(/\r?\n/)[0] || 'no reason given';
    check('Market Research', true, `Skipped on purpose (${MARKET_RESEARCH_SKIP_FILE}): ${reason}`);
    return;
  }
  check('Market Research', false,
    'No market-research.md found and no market-research-skipped.txt marker. ' +
    'Run market research, or record why it was skipped in .specship/artifacts/market-research-skipped.txt');
}

// === Tasks completed (BUILD output) — build + ship phases ===

function checkState() {
  if (!fs.existsSync(STATE_FILE)) {
    check('Tasks Completed', false, `state.json not found at ${STATE_FILE}`);
    return;
  }

  let state;
  try {
    state = readJson(STATE_FILE);
  } catch (e) {
    check('Tasks Completed', false, `state.json is not valid JSON (${e.message})`);
    return;
  }

  const { tasks_completed, tasks_total } = state;
  if (typeof tasks_completed !== 'number' || typeof tasks_total !== 'number') {
    check('Tasks Completed', false, 'state.json missing tasks_completed or tasks_total fields');
    return;
  }

  if (tasks_completed === tasks_total) {
    check('Tasks Completed', true, `${tasks_completed}/${tasks_total} tasks completed`);
  } else {
    check('Tasks Completed', false, `Only ${tasks_completed}/${tasks_total} tasks completed`);
  }
}

// === Build green (BUILD output) — build phase only ===
// The checker does not run polyglot build/test commands itself. The BUILD phase
// records its gate result in build-status.json; this asserts it is green.

function checkBuildStatus() {
  if (!fs.existsSync(BUILD_STATUS_FILE)) {
    check('Build Green', false,
      `build-status.json not found at ${BUILD_STATUS_FILE} — the build phase must record typecheck/tests/build results`);
    return;
  }

  let status;
  try {
    status = readJson(BUILD_STATUS_FILE);
  } catch (e) {
    check('Build Green', false, `build-status.json is not valid JSON (${e.message})`);
    return;
  }

  const failures = [];
  // tests must be explicitly "pass"; typecheck/build must not be "fail" (skip/n/a allowed).
  if (status.tests !== 'pass') failures.push(`tests=${status.tests == null ? 'missing' : status.tests}`);
  if (status.typecheck === 'fail') failures.push('typecheck=fail');
  if (status.build === 'fail') failures.push('build=fail');

  if (failures.length === 0) {
    check('Build Green', true,
      `typecheck=${status.typecheck ?? 'n/a'}, tests=${status.tests}, build=${status.build ?? 'n/a'}`);
  } else {
    check('Build Green', false, `Build not green: ${failures.join(', ')}`);
  }

  // T17 hardening: a bare tests:"pass" is self-attested. Require EVIDENCE — the actual
  // test command that was run plus a log the human can inspect. Without it, the gate is
  // only as honest as the agent that wrote the flag. Evidence-backed status is trusted;
  // evidence-free status warns (or fails under --strict).
  if (status.tests === 'pass') {
    const cmd = typeof status.tests_command === 'string' ? status.tests_command.trim() : '';
    const logRef = typeof status.tests_log === 'string' ? status.tests_log.trim() : '';
    const logExists = logRef && fs.existsSync(path.resolve(SPECSHIP_DIR, logRef));
    if (!cmd || !logRef) {
      warnOrFail('Build Evidence',
        'build-status.json reports tests=pass but carries no evidence ' +
        '(need "tests_command" + "tests_log"). A self-written pass flag is not proof the tests ran.');
    } else if (!logExists) {
      warnOrFail('Build Evidence',
        `build-status.json references tests_log="${logRef}" but no such file exists under .specship/. ` +
        'Cannot corroborate the reported pass.');
    } else {
      check('Build Evidence', true, `Corroborated: tests_command="${cmd}", tests_log="${logRef}" present`);
    }
  }
}

// === Expected validators written (BUILD->VALIDATE handoff) — build phase ===

function getExpectedValidators() {
  if (!fs.existsSync(EXPECTED_VALIDATORS_FILE)) return null;
  return fs.readFileSync(EXPECTED_VALIDATORS_FILE, 'utf8')
    .split(/\r?\n/)
    .map(l => l.trim())
    .filter(l => l.length > 0);
}

function checkExpectedValidatorsWritten() {
  const validators = getExpectedValidators();
  if (validators === null) {
    check('Expected Validators Written', false, `File not found: ${EXPECTED_VALIDATORS_FILE}`);
  } else if (validators.length === 0) {
    check('Expected Validators Written', false, 'expected-validators.txt is empty');
  } else {
    check('Expected Validators Written', true, `${validators.length} validators declared: ${validators.join(', ')}`);
  }
}

// === Verdict files present + clean (VALIDATE output) — ship phase ===

function checkVerdictFilesExist(validators) {
  const missing = [];
  for (const name of validators) {
    if (!fs.existsSync(path.join(VERDICTS_DIR, `${name}.json`))) missing.push(name);
  }
  if (missing.length === 0) {
    check('Verdict Files Exist', true, `All ${validators.length} expected verdict files present`);
  } else {
    check('Verdict Files Exist', false, `Missing verdict files: ${missing.join(', ')}`);
  }
  return missing;
}

function checkVerdictStatuses(validators) {
  const skipped = [];
  const blocked = [];
  const unreadable = [];
  const notIndependent = [];  // T18: verdicts with no proof they came from an independent pass

  for (const name of validators) {
    const verdictPath = path.join(VERDICTS_DIR, `${name}.json`);
    if (!fs.existsSync(verdictPath)) continue;

    let verdict;
    try {
      verdict = readJson(verdictPath);
    } catch (e) {
      unreadable.push(`${name} (${e.message})`);
      continue;
    }

    if (verdict.status === 'SKIPPED') skipped.push(name);
    if (Array.isArray(verdict.blocking_issues) && verdict.blocking_issues.length > 0) {
      blocked.push(`${name} (${verdict.blocking_issues.length} issue${verdict.blocking_issues.length > 1 ? 's' : ''})`);
    }

    // T18 hardening: adversarial validation only holds if the validator ran INDEPENDENTLY
    // of the builder. Require the verdict to attest it — independent:true plus a non-empty
    // method describing how (fresh session, /specship-validate-<name>, gstack skill, ...).
    // A verdict the builder wrote for its own work, with no independence attestation, does
    // not satisfy the guarantee.
    const method = typeof verdict.method === 'string' ? verdict.method.trim() : '';
    if (verdict.independent !== true || !method) {
      notIndependent.push(name);
    }
  }

  if (unreadable.length > 0) {
    check('Verdict Readable', false, `Could not parse: ${unreadable.join(', ')}`);
  }
  if (skipped.length === 0) {
    check('No Skipped Validators', true, 'All validators ran (none SKIPPED)');
  } else {
    check('No Skipped Validators', false, `Skipped validators: ${skipped.join(', ')}`);
  }
  if (blocked.length === 0) {
    check('No Blocking Issues', true, 'No blocking issues in any verdict');
  } else {
    check('No Blocking Issues', false, `Blocking issues found: ${blocked.join(', ')}`);
  }
  if (notIndependent.length === 0) {
    check('Validator Independence', true, 'Every verdict attests an independent pass (independent:true + method)');
  } else {
    warnOrFail('Validator Independence',
      `Verdict(s) without independence proof (need independent:true + "method"): ${notIndependent.join(', ')}. ` +
      'A builder judging its own work does not satisfy adversarial validation.');
  }
}

// === Phase compositions ===

function runPlanGate() {
  checkPlanArtifacts();
  checkMarketResearch();
}

function runBuildGate() {
  checkPlanArtifacts();
  checkState();
  checkBuildStatus();
  checkExpectedValidatorsWritten();
}

function runShipGate() {
  checkState();
  const validators = getExpectedValidators();
  if (validators === null) {
    check('Expected Validators', false, `File not found: ${EXPECTED_VALIDATORS_FILE}`);
  } else if (validators.length === 0) {
    check('Expected Validators', false, 'expected-validators.txt is empty');
  } else {
    const missing = checkVerdictFilesExist(validators);
    const present = validators.filter(v => !missing.includes(v));
    checkVerdictStatuses(present);
  }
  checkPlanArtifacts();
}

// === Run ===

function run() {
  const phase = parsePhase(process.argv.slice(2));

  const titles = {
    plan: 'PLAN -> BUILD gate',
    build: 'BUILD -> VALIDATE gate',
    ship: 'VALIDATE -> SHIP gate',
  };

  console.log('');
  console.log('SpecShip Pipeline Validation');
  console.log('============================');
  console.log(`Phase: ${phase}  (${titles[phase]})${STRICT ? '  [STRICT: evidence required]' : '  [LENIENT: evidence-free self-attestation only warns]'}`);
  console.log('');

  if (phase === 'plan') runPlanGate();
  else if (phase === 'build') runBuildGate();
  else runShipGate();

  console.log('');
  const allPassed = results.every(r => r.passed);
  for (const r of results) {
    console.log(`  ${r.passed ? '✅' : '❌'} ${r.name}`);
    console.log(`     ${r.reason}`);
  }

  // Surface non-strict warnings (evidence-free self-attestation). These do NOT fail the
  // gate unless run with --strict / SPECSHIP_STRICT_GATE=1, but they must never be silent —
  // a green gate that trusted an agent-written flag reads as "verified" when it was not.
  if (warnings.length > 0) {
    console.log('');
    console.log('  ⚠ WARNINGS (self-attested evidence — not independently corroborated):');
    for (const w of warnings) console.log(`     • ${w}`);
    console.log('     Running in --lenient mode: these are warnings. Drop --lenient (the default is strict) to treat them as failures.');
  }

  console.log('');
  if (allPassed) {
    const suffix = warnings.length > 0 ? ` (with ${warnings.length} warning${warnings.length > 1 ? 's' : ''})` : '';
    console.log(`Result: PASS ✅ — ${phase} gate cleared${suffix}.`);
  } else {
    console.log(`Result: FAIL ❌ — ${phase} gate found issues (see above).`);
  }
  console.log('');

  process.exit(allPassed ? 0 : 1);
}

run();
