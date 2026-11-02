import Foundation
@preconcurrency import Libbox
import Network
import NetworkExtension

/// sing-box core backed by Libbox.xcframework. The core runs inside a libbox
/// CommandServer; this class is its platform interface inside the extension.
// State is touched from libbox callback threads; libbox serializes start/stop.
final class LibboxCore: NSObject, @unchecked Sendable {
  private static let appGroup = AppConfig.appGroup
  private static var setupDone = false

  private weak var provider: NEPacketTunnelProvider?
  private var server: LibboxCommandServer?
  private var pathMonitor: NWPathMonitor?
  private let monitorQueue = DispatchQueue(label: "com.raycentral.spamurai.PacketTunnel.path")

  func start(provider: NEPacketTunnelProvider, configJson: String) async throws {
    self.provider = provider
    // startOrReloadService blocks until the core is up and calls openTun
    // synchronously, so run it off the provider's calling context.
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try Self.setup()
          #if DEBUG
          SharedStore.diag("core: setup done")
          #endif
          var error: NSError?
          guard let server = LibboxNewCommandServer(self, self, &error) else {
            throw error ?? LibboxCoreError("failed to create command server")
          }
          self.server = server
          // libbox needs the command server to host the service.
          try server.start()
          #if DEBUG
          SharedStore.diag("core: command server up")
          #endif
          try server.startOrReloadService(configJson, options: LibboxOverrideOptions())
          #if DEBUG
          SharedStore.diag("core: service started")
          #endif
          cont.resume()
        } catch {
          cont.resume(throwing: error)
        }
      }
    }
  }

  /// Applies a new config to the running service (custom rules, a fresh list).
  func reload(configJson: String) async throws {
    guard let server else { throw LibboxCoreError("service is not running") }
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try server.startOrReloadService(configJson, options: LibboxOverrideOptions())
          cont.resume()
        } catch {
          cont.resume(throwing: error)
        }
      }
    }
  }

  func stop() {
    if let server {
      try? server.closeService()
      server.close()
    }
    server = nil
    pathMonitor?.cancel()
    pathMonitor = nil
  }

  var version: String { LibboxVersion() }

  private static func setup() throws {
    if setupDone { return }
    guard let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
      throw TunnelError.noAppGroup
    }
    let caches = shared.appendingPathComponent("Library/Caches", isDirectory: true)
    let working = caches.appendingPathComponent("Working", isDirectory: true)
    try FileManager.default.createDirectory(at: working, withIntermediateDirectories: true)

    let options = LibboxSetupOptions()
    options.basePath = shared.path
    options.workingPath = working.path
    options.tempPath = caches.path
    // Only QueryJournal reads the buffer, and it streams lines as they arrive.
    options.logMaxLines = 200
    var error: NSError?
    guard LibboxSetup(options, &error) else {
      throw error ?? LibboxCoreError("libbox setup failed")
    }
    setupDone = true
  }
}

// MARK: - LibboxPlatformInterfaceProtocol: tunnel

extension LibboxCore: LibboxPlatformInterfaceProtocol {
  func openTun(_ options: LibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
    guard let options, let ret0_ else { throw LibboxCoreError("invalid openTun arguments") }
    guard let provider else { throw LibboxCoreError("tunnel provider is gone") }

    let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
    if options.getAutoRoute() {
      settings.mtu = NSNumber(value: options.getMTU())

      let dnsServers = strings(try options.getDNSServerAddress())
      if !dnsServers.isEmpty {
        let dns = NEDNSSettings(servers: dnsServers)
        // Send all DNS queries through the tunnel; sing-box hijacks them.
        dns.matchDomains = [""]
        dns.matchDomainsNoSearch = true
        settings.dnsSettings = dns
      }

      let inet4 = prefixes(options.getInet4Address())
      if !inet4.isEmpty {
        let ipv4 = NEIPv4Settings(addresses: inet4.map { $0.address() }, subnetMasks: inet4.map { $0.mask() })
        let routes = prefixes(options.getInet4RouteRange())
        ipv4.includedRoutes = routes.isEmpty
          ? [NEIPv4Route.default()]
          : routes.map { NEIPv4Route(destinationAddress: $0.address(), subnetMask: $0.mask()) }
        ipv4.excludedRoutes = prefixes(options.getInet4RouteExcludeAddress())
          .map { NEIPv4Route(destinationAddress: $0.address(), subnetMask: $0.mask()) }
        settings.ipv4Settings = ipv4
      }

      let inet6 = prefixes(options.getInet6Address())
      if !inet6.isEmpty {
        let ipv6 = NEIPv6Settings(
          addresses: inet6.map { $0.address() },
          networkPrefixLengths: inet6.map { NSNumber(value: $0.prefix()) }
        )
        let routes = prefixes(options.getInet6RouteRange())
        ipv6.includedRoutes = routes.isEmpty
          ? [NEIPv6Route.default()]
          : routes.map { NEIPv6Route(destinationAddress: $0.address(), networkPrefixLength: NSNumber(value: $0.prefix())) }
        ipv6.excludedRoutes = prefixes(options.getInet6RouteExcludeAddress())
          .map { NEIPv6Route(destinationAddress: $0.address(), networkPrefixLength: NSNumber(value: $0.prefix())) }
        settings.ipv6Settings = ipv6
      }
    }

    if options.isHTTPProxyEnabled() {
      let proxy = NEProxySettings()
      let server = NEProxyServer(address: options.getHTTPProxyServer(), port: Int(options.getHTTPProxyServerPort()))
      proxy.httpServer = server
      proxy.httpsServer = server
      proxy.httpEnabled = true
      proxy.httpsEnabled = true
      proxy.exceptionList = strings(options.getHTTPProxyBypassDomain())
      let match = strings(options.getHTTPProxyMatchDomain())
      if !match.isEmpty { proxy.matchDomains = match }
      settings.proxySettings = proxy
    }

    #if DEBUG
    SharedStore.diag("core: openTun, applying settings dns=\(settings.dnsSettings?.servers ?? [])")
    #endif
    try Self.waitFor { try await provider.setTunnelNetworkSettings(settings) }

    var fd = LibboxGetTunnelFileDescriptor()
    if fd == -1, let legacy = provider.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
      fd = legacy
    }
    if fd == -1 { throw LibboxCoreError("missing utun file descriptor") }
    ret0_.pointee = fd
    #if DEBUG
    SharedStore.diag("core: tun fd=\(fd)")
    #endif
  }

  /// Sockets created inside a Network Extension already bypass its own tunnel.
  func usePlatformAutoDetectControl() -> Bool { true }
  func autoDetectControl(_ fd: Int32) throws {}

  func underNetworkExtension() -> Bool { true }
  func includeAllNetworks() -> Bool { false }

  /// Bridges an async call into libbox's synchronous callback thread.
  private static func waitFor(_ body: @escaping @Sendable () async throws -> Void) throws {
    let semaphore = DispatchSemaphore(value: 0)
    var failure: Error?
    Task.detached {
      do { try await body() } catch { failure = error }
      semaphore.signal()
    }
    semaphore.wait()
    if let failure { throw failure }
  }
}

// MARK: - LibboxPlatformInterfaceProtocol: network state

extension LibboxCore {
  func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
    guard let listener else { return }
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { path in
      guard path.status != .unsatisfied, let iface = path.availableInterfaces.first else {
        listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
        return
      }
      listener.updateDefaultInterface(
        iface.name,
        interfaceIndex: Int32(iface.index),
        isExpensive: path.isExpensive,
        isConstrained: path.isConstrained
      )
    }
    monitor.start(queue: monitorQueue)
    pathMonitor = monitor
  }

  func closeDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
    pathMonitor?.cancel()
    pathMonitor = nil
  }

  func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
    guard let path = pathMonitor?.currentPath else { return NetworkInterfaceArray([]) }
    let interfaces = path.availableInterfaces.map { iface -> LibboxNetworkInterface in
      let item = LibboxNetworkInterface()
      item.name = iface.name
      item.index = Int32(iface.index)
      switch iface.type {
      case .wifi: item.type = LibboxInterfaceTypeWIFI
      case .cellular: item.type = LibboxInterfaceTypeCellular
      case .wiredEthernet: item.type = LibboxInterfaceTypeEthernet
      default: item.type = LibboxInterfaceTypeOther
      }
      item.metered = path.isExpensive
      return item
    }
    return NetworkInterfaceArray(interfaces)
  }

  func findConnectionOwner(
    _ ipProtocol: Int32, sourceAddress: String?, sourcePort: Int32,
    destinationAddress: String?, destinationPort: Int32
  ) throws -> LibboxConnectionOwner {
    throw LibboxCoreError("process lookup is not available on iOS")
  }

  func localDNSTransport() -> LibboxLocalDNSTransportProtocol? { nil }
  func readWIFIState() -> LibboxWIFIState? { nil }
  func clearDNSCache() {}
  func registerMyInterface(_ name: String?) {}
  func startNeighborMonitor(_ listener: LibboxNeighborUpdateListenerProtocol?) throws {}
  func closeNeighborMonitor(_ listener: LibboxNeighborUpdateListenerProtocol?) throws {}
}

// MARK: - LibboxPlatformInterfaceProtocol: features Spamurai does not use

extension LibboxCore {
  func sendNotification(_ notification: LibboxNotification?) throws {}
  func cancelNotification(_ identifier: String?, typeID: Int32) throws {}
  func usePlatformShell() -> Bool { false }
  func checkPlatformShell() throws { throw LibboxCoreError("platform shell is not supported") }

  func openShellSession(
    _ user: LibboxPlatformUser?, command: String?, environ: LibboxStringIteratorProtocol?,
    term: String?, rows: Int32, cols: Int32
  ) throws -> LibboxShellSessionProtocol {
    throw LibboxCoreError("platform shell is not supported")
  }

  func lookupUser(_ username: String?) throws -> LibboxPlatformUser {
    throw LibboxCoreError("not supported")
  }

  func lookupSFTPServer(_ error: NSErrorPointer) -> String {
    error?.pointee = LibboxCoreError("not supported").nsError
    return ""
  }

  func readSystemSSHHostKey(_ error: NSErrorPointer) -> String {
    error?.pointee = LibboxCoreError("not supported").nsError
    return ""
  }

  func tailscaleHostname() -> String { ProcessInfo.processInfo.hostName }
  func usePlatformBridge() -> Bool { false }

  func createBridge(_ options: LibboxBridgeOptions?) throws -> LibboxBridgeSessionProtocol {
    throw LibboxCoreError("bridge is not supported")
  }
}

// MARK: - LibboxCommandServerHandlerProtocol

extension LibboxCore: LibboxCommandServerHandlerProtocol {
  func serviceStop() throws {
    #if DEBUG
    SharedStore.diag("core: serviceStop requested")
    #endif
    provider?.cancelTunnelWithError(nil)
  }

  func serviceReload() throws {
    throw LibboxCoreError("reload is not supported; reconnect instead")
  }

  func getSystemProxyStatus() throws -> LibboxSystemProxyStatus { LibboxSystemProxyStatus() }
  func setSystemProxyEnabled(_ enabled: Bool) throws {}
  func triggerNativeCrash() throws { throw LibboxCoreError("not supported") }
  func writeDebugMessage(_ message: String?) {
    NSLog("[libbox] %@", message ?? "")
    #if DEBUG
    SharedStore.diag("libbox: \(message ?? "")")
    #endif
  }
  func connectSSHAgent(_ ret0_: UnsafeMutablePointer<Int32>?) throws {
    throw LibboxCoreError("not supported")
  }
}

// MARK: - Helpers

struct LibboxCoreError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
  var nsError: NSError {
    NSError(domain: "com.raycentral.spamurai.PacketTunnel", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}

private final class NetworkInterfaceArray: NSObject, LibboxNetworkInterfaceIteratorProtocol {
  private var items: [LibboxNetworkInterface]
  init(_ items: [LibboxNetworkInterface]) { self.items = items }
  func hasNext() -> Bool { !items.isEmpty }
  func next() -> LibboxNetworkInterface? { items.isEmpty ? nil : items.removeFirst() }
}

private func strings(_ iterator: LibboxStringIteratorProtocol?) -> [String] {
  guard let iterator else { return [] }
  var result: [String] = []
  while iterator.hasNext() { result.append(iterator.next()) }
  return result
}

private func prefixes(_ iterator: LibboxRoutePrefixIteratorProtocol?) -> [LibboxRoutePrefix] {
  guard let iterator else { return [] }
  var result: [LibboxRoutePrefix] = []
  while iterator.hasNext() {
    if let prefix = iterator.next() { result.append(prefix) }
  }
  return result
}
