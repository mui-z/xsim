# XSim
[![Swift](https://img.shields.io/badge/Swift-FA7343?style=for-the-badge)](https://github.com/apple/swift)
[![LICENSE: MIT SUSHI-WARE🍣](https://raw.githubusercontent.com/watasuke102/mit-sushi-ware/master/MIT-SUSHI-WARE.svg)](https://github.com/mui-z/xsim/blob/main/LICENSE)


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


List filters and sorting:

```sh
# filter by runtime (flexible):
xsim list --runtime "iOS 26"
xsim list --runtime "26.0"
xsim list --runtime com.apple.CoreSimulator.SimRuntime.iOS-26-0

# runtimes are grouped and sorted by platform (iOS, watchOS, tvOS) and version (desc)
```


List filters and sorting:

```sh
# filter by runtime (flexible)
xsim list --runtime "iOS 26"
xsim list --runtime "26.0"
xsim list --runtime com.apple.CoreSimulator.SimRuntime.iOS-26-0

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


Debug logging:

```sh
# enable verbose debug logs to stderr
XSIM_VERBOSE=1 xsim list
```
