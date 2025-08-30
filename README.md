# XSim
# 🚧🚧Not working properly🚧🚧

simple xcrun simctl wrapper.


## Install

```sh
mint install mui-z/xsim
```


## Usage

```sh
% xsim help

Usage: xsim <command> [options]

Xcode Simulator management tool – shortcuts for simctl commands

Commands:
  list            List available simulators
  start           Start a simulator
  stop            Stop simulators
  create          Create a new simulator
  delete          Delete a simulator
  doctor          Check environment and simctl support
  help            Prints help information
  version         Prints the current version of this app
```

Debug logging:

```sh
# enable verbose debug logs to stderr
XSIM_VERBOSE=1 xsim list
```


List filters and sorting:

```sh
# filter by runtime (flexible):
xsim list --runtime "iOS 17"
xsim list --runtime "17.0"
xsim list --runtime com.apple.CoreSimulator.SimRuntime.iOS-17-0

# runtimes are grouped and sorted by platform (iOS, watchOS, tvOS) and version (desc)
```


List filters and sorting:

```sh
# filter by runtime (flexible)
xsim list --runtime "iOS 17"
xsim list --runtime "17.0"
xsim list --runtime com.apple.CoreSimulator.SimRuntime.iOS-17-0

# filter by device name substring (case-insensitive)
xsim list --name-contains "iPhone"

# runtimes are grouped and sorted by platform (iOS, watchOS, tvOS) and version (desc)
```

Full width by default; compact view:

```sh
# default is full width (no truncation)
xsim list

# opt-in to truncated, aligned columns (legacy):
xsim list --truncate
```
