This directory holds the source for the bundled Battery SMC helper.

The helper binary is built as `mactools-battery-smc-helper` and copied into
`BatteryChargeLimit.bundle/Contents/Resources/SMCHelper/` by the generated
Xcode project. The plugin installs it to `/Library/PrivilegedHelperTools` with
root ownership and setuid permissions on first use.

The helper exposes these subcommands:

  probe              Output which charge-control SMC keys are writable
  inhibit [<pct>]    Stop charging (writes CH0B+CH0C/CHIE; BCLM if Intel)
  resume             Clear inhibit keys and stop force-discharge
  discharge on|off   Toggle CH0I (force-discharge while plugged in)
  read <KEY>         Print the current value of a 1-byte SMC key
