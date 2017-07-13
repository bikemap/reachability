# Reachability

Reachability is a dead-simple wrapper for SCNetworkReachability.
It provides very simple interaction with the network status. And
honestly, that is all you need, no-one cares about the 
`interventionRequired` state.

You have three options:
- online
- cellular
- offline

And there is a convenience `isOnline` parameter.

## Usage

### Sync

You can use Reachability to query the current status.

```swift
  let reachability = Reachability()
  print(reachability.status)


  if reachability.isOnline() {
    // True, when on wifi or on cellular network.
  }
```


### Async

If you provide a handler, a listener is going to be setup, and the  closure
is called when there is a change in the network status.

**Simple**

```swift
  Reachability { status, _ in
    print(status)
  }
```

**Based on previous result**

```swift
  Reachability { status, from in
    if status == .online && from == .cellular {
      // User just joined a wifi.
      // Continue download or something.
    }
  }
```