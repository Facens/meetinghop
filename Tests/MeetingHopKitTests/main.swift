import Foundation

// Every suite is wired here once, so no implementation unit has to edit this
// file to add its own tests. Each suite lives in its own file. Shape ported
// from AgentMenu's Tests/AgentMenuKitTests/main.swift.
let runner = TestRunner()

runMeetingLinkTests(runner)
runCalendarRulesTests(runner)
runAllDayRuleTests(runner)
runSchedulerTests(runner)
runConcurrentMeetingTests(runner)
runHandoffWindowTests(runner)
runAppIdentityTests(runner)
runBundleVersionTests(runner)
runReleaseChannelTests(runner)
runAppVersionTests(runner)
runPublishScriptTests(runner)
runVerifySigningTests(runner)
runCheckSourceTests(runner)
runHarnessScriptTests(runner)
runHarnessGuestTests(runner)
runJournalTests(runner)
runSettingsStoreTests(runner)
runAccessibilityIDTests(runner)
runOnboardingTests(runner)
runHarnessFixtureTests(runner)

exit(runner.report())
