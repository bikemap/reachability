//
//  Reachability.swift
//  Bikemap
//
//  Created by Adam Eri on 12/07/2017.
//  Copyright © 2017 Bikemap GmbH. All rights reserved.
//

import Foundation
import SystemConfiguration

/// Possible statuses of reachability
///
/// - reachable: Reachable, there is connection
/// - cellular: Reachable, there is connection via cellular network
/// - offline: Not reachable, we are offline
public enum ReachabilityStatus {
  /// Reachable, there is connection
  case online
  /// Reachable, there is connection via cellular network
  case cellular
  /// Not reachable, we are offline
  case offline
  /// There was an error initiating the network status, so we do not know
  /// if there is a connection.
  case unknown
}

/// Closure for receiveing reachability change events.
/// It receives two statuses, `from` and `to`, so you can have
/// custom logic based on the previous status.
public typealias ReachabilityStatusChangeHandler =
  (ReachabilityStatus, ReachabilityStatus) -> Void

/// Reachability is a dead-simple wrapper for SCNetworkReachability
/// It provides very simple interaction with the network status. And
/// honestly, that is all you need, no-one cares about the 
/// `interventionRequired` state.
///
/// You have three options:
/// - online
/// - cellular
/// - offline
/// 
/// And there is a convenience `isOnline` parameter.
///
/// You can register for receving status by setting the `onChange` closure.
/// See `ReachabilityStatusChangeHandler`
///
/// You need to `init()` the class, and it might throw you an error if there 
/// is a problem. See `ReachabilityError`.
///
final public class Reachability {

  /// The reference to the actual SCNetworkReachability class.
  private var networkReachability: SCNetworkReachability?

  fileprivate let queue = DispatchQueue(label: "net.bikemap.reachability")

  /// The current reachability status.
  public var status: ReachabilityStatus = .offline

  /// Convenience method for checking if we are online and not caring about
  /// whether it is cellular or not.
  public var isOnline: Bool {
    return self.status == .cellular || self.status == .online
  }

  /// Closure executed when there is a change in the network status
  public var onChange: ReachabilityStatusChangeHandler?

  /// Initiates a Reachability object.
  /// Reachability treats the 0.0.0.0 address as a special token that causes 
  /// it to monitor the general routing status of the device,
  /// both IPv4 and IPv6.
  @discardableResult init(onChange: ReachabilityStatusChangeHandler? = nil) {

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)

    self.networkReachability = withUnsafePointer(to: &address, { pointer in
      return pointer.withMemoryRebound(
        to: sockaddr.self,
        capacity: MemoryLayout<sockaddr>.size) {
          return SCNetworkReachabilityCreateWithAddress(nil, $0)
      }
    })

    guard self.networkReachability != nil,
      self.flags != nil else {
      self.status = .unknown
      return
    }

    if self.processReachabilityFlags(self.flags!) == .unknown {
      return
    }

    if onChange != nil {
      self.onChange = onChange
      self.listen()
    }
  }

  /// Stop listener on deinit
  deinit {
    stopListening()
  }

  // MARK: - Private Utils

  /// Processes the incoming SCNetworkReachabilityFlags and returns a
  /// ReachabilityStatus.
  ///
  /// - Parameter flags: SCNetworkReachabilityFlags received from the system
  /// - Returns: ReachabilityStatus
  private func processReachabilityFlags(
    _ flags: SCNetworkReachabilityFlags) -> ReachabilityStatus {

    guard self.isReachable(with: flags) == true else {
      return .offline
    }

    self.status = .online

    #if os(iOS)
      if flags.contains(.isWWAN) {
        self.status = .cellular
      }
    #endif

    return self.status
  }

  private var flags: SCNetworkReachabilityFlags? {
    var flags = SCNetworkReachabilityFlags()

    if SCNetworkReachabilityGetFlags(self.networkReachability!, &flags) {
      return flags
    }

    return nil
  }

  /// Being actually reachable is not trivial...
  private func isReachable(with flags: SCNetworkReachabilityFlags) -> Bool {
    let isReachable = flags.contains(.reachable)
    let needsConnection = flags.contains(.connectionRequired)
    let canConnectAutomatically = flags.contains(.connectionOnDemand) ||
      flags.contains(.connectionOnTraffic)
    let canConnectWithoutUserInteraction = canConnectAutomatically &&
      !flags.contains(.interventionRequired)
    return isReachable && (!needsConnection || canConnectWithoutUserInteraction)
  }

  /// Starts the listener for changes to network reachability
  private func listen() {
    var context = SCNetworkReachabilityContext(
      version: 0,
      info: nil,
      retain: nil,
      release: nil,
      copyDescription: nil)

    // Mind the `passRetained` here. As the class might not be retained at
    // the caller function, we retain it here.
    context.info = UnsafeMutableRawPointer(
      Unmanaged<Reachability>.passRetained(self).toOpaque())

    let callback: SCNetworkReachabilityCallBack? = {
      (reachability: SCNetworkReachability,
      flags: SCNetworkReachabilityFlags,
      info: UnsafeMutableRawPointer?) in

      guard info != nil else {
        return
      }

      let handler = Unmanaged<Reachability>
        .fromOpaque(info!).takeUnretainedValue()

      DispatchQueue.main.async {
        let oldStatus = handler.status
        let newStatus = handler.processReachabilityFlags(flags)
        handler.onChange!(newStatus, oldStatus)
      }
    }

    if SCNetworkReachabilitySetCallback(
      self.networkReachability!, callback, &context) == false {
      self.status = .unknown
    }

    if SCNetworkReachabilitySetDispatchQueue(
      self.networkReachability!, queue) == false {
      self.status = .unknown
    }

    // Initial call of the handler, to notifiy the listener on the current
    // status.

    self.onChange!(self.status, self.status)
  }

  // Stops the listener
  private func stopListening() {
    SCNetworkReachabilitySetCallback(self.networkReachability!, nil, nil)
    SCNetworkReachabilitySetDispatchQueue(self.networkReachability!, nil)
  }
}
