import Flutter
import UIKit
import NetworkExtension

public class SwiftOpenVPNFlutterPlugin: NSObject, FlutterPlugin {
    private static var utils : VPNUtils! = VPNUtils()
    
    private static var EVENT_CHANNEL_VPN_STAGE : String = "id.laskarmedia.openvpn_flutter/vpnstage"
    private static var METHOD_CHANNEL_VPN_CONTROL : String = "id.laskarmedia.openvpn_flutter/vpncontrol"
     
    public  static var stage: FlutterEventSink?
    private var initialized : Bool = false
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SwiftOpenVPNFlutterPlugin()
        instance.onRegister(registrar)
        
    }
    
    public func onRegister(_ registrar: FlutterPluginRegistrar){
        let vpnControlM = FlutterMethodChannel(name: SwiftOpenVPNFlutterPlugin.METHOD_CHANNEL_VPN_CONTROL, binaryMessenger: registrar.messenger())
        let vpnStageE = FlutterEventChannel(name: SwiftOpenVPNFlutterPlugin.EVENT_CHANNEL_VPN_STAGE, binaryMessenger: registrar.messenger())
        
        vpnStageE.setStreamHandler(StageHandler())
        vpnControlM.setMethodCallHandler({(call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            switch call.method{
            case "status":
                SwiftOpenVPNFlutterPlugin.utils.getTraffictStats()
                result(UserDefaults.init(suiteName: SwiftOpenVPNFlutterPlugin.utils.groupIdentifier)?.string(forKey: "connectionUpdate"))
                break;
            case "stage":
                result(SwiftOpenVPNFlutterPlugin.utils.currentStatus())
                break;
            case "initialize":
                guard let providerBundleIdentifier = (call.arguments as? [String: Any])?["providerBundleIdentifier"] as? String else {
                    result(FlutterError(code: "-2", message: "providerBundleIdentifier content empty or null", details: nil))
                    return
                }
                guard let localizedDescription = (call.arguments as? [String: Any])?["localizedDescription"] as? String else {
                    result(FlutterError(code: "-3", message: "localizedDescription content empty or null", details: nil));
                    return;
                }
                guard let groupIdentifier = (call.arguments as? [String: Any])?["groupIdentifier"] as? String else {
                    result(FlutterError(code: "-4", message: "groupIdentifier content empty or null", details: nil));
                    return;
                }
                SwiftOpenVPNFlutterPlugin.utils.groupIdentifier = groupIdentifier
                SwiftOpenVPNFlutterPlugin.utils.localizedDescription = localizedDescription
                SwiftOpenVPNFlutterPlugin.utils.providerBundleIdentifier = providerBundleIdentifier
                SwiftOpenVPNFlutterPlugin.utils.loadProviderManager{(err: Error?) in
                    if err == nil {
                        result(SwiftOpenVPNFlutterPlugin.utils.currentStatus())
                    } else {
                        result(FlutterError(code: "-4", message: err.debugDescription, details: err?.localizedDescription));
                    }
                }
                self.initialized = true
                break;
            case "install":
                guard let config = (call.arguments as? [String : Any])? ["config"] as? String else {
                    result(FlutterError(code: "-2", message:"Config is empty or nulled", details: "Config can't be nulled"))
                    return
                }
                let memberId = (call.arguments as? [String : Any])? ["memberId"] as? String ?? ""
                let server = (call.arguments as? [String : Any])? ["server"] as? String ?? ""
                SwiftOpenVPNFlutterPlugin.utils.install(configuration: config, serverAddress: server, memberId: memberId) { err in
                    if err == nil {
                        result(SwiftOpenVPNFlutterPlugin.utils.currentStatus())
                    } else {
                        result(FlutterError(code: "-4", message: err.debugDescription, details: err?.localizedDescription));
                    }
                }
                break;
            case "disconnect":
                SwiftOpenVPNFlutterPlugin.utils.stopVPN()
                break;
            case "connect":
                if !self.initialized {
                    result(FlutterError(code: "-1", message: "VPNEngine need to be initialize", details: nil));
                }
                
                let server = (call.arguments as? [String : Any])? ["server"] as? String ?? ""
                let endpointId = (call.arguments as? [String : Any])? ["endpointId"] as? Int ?? 0
                let webRtcBlock = (call.arguments as? [String : Any])? ["webRtcBlock"] as? Bool ?? false
                SwiftOpenVPNFlutterPlugin.utils.connect(server: server, endpointId: endpointId, isWebRtcBlock: webRtcBlock, completionHandler: { error in
                    if (error == nil) {
                        result(nil)
                    } else {
                        result(FlutterError(code: "-5", message: error?.localizedDescription, details: error.debugDescription))
                    }
                })
//                SwiftOpenVPNFlutterPlugin.utils.configureVPN(config: config, memberId: memberId, server: server, endpointId: endpointId, webRtcBlock: webRtcBlock, completion: {(success:Error?) -> Void in
//                    if(success == nil){
//                        result(nil)
//                    }else{
//                        result(FlutterError(code: "-5", message: success?.localizedDescription, details: success.debugDescription))
//                    }
//                })
                break;
            case "sendServer":
                if let message = (call.arguments as? [String: Any])?["message"] as? Int {
                    SwiftOpenVPNFlutterPlugin.utils.sendServer(message: message)
                }
                break;
            case "isProfileExists":
                result(SwiftOpenVPNFlutterPlugin.utils.isProfileExists);
                break;
            case "dispose":
                self.initialized = false
            default:
                break;
                
            }
        })
    }
    
    
    class StageHandler: NSObject, FlutterStreamHandler {
        func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
            SwiftOpenVPNFlutterPlugin.utils.stage = events
            return nil
        }
        
        func onCancel(withArguments arguments: Any?) -> FlutterError? {
            SwiftOpenVPNFlutterPlugin.utils.stage = nil
            return nil
        }
    }
    
    
}


@available(iOS 9.0, *)
class VPNUtils {
    var providerManager: NETunnelProviderManager!
    var providerBundleIdentifier = "com.datacork.vpn.iosNetworkExtension"
    var localizedDescription = "Datacork VPN"
    var groupIdentifier : String?
    var stage : FlutterEventSink!
    var vpnStageObserver : NSObjectProtocol?
    
    public private(set) var isProfileExists: Bool = false

//    func prepare(completionHandler: (() -> Void)?) {
//        find(with: providerBundleIdentifier) {
//            self.providerManager = $0
//            let conf = $0?.protocolConfiguration
////            NotificationCenter.default.post(name: .VPNDidPrepare, object: nil)
//            completionHandler?()
//        }
//    }
    
    func loadProviderManager(completion:@escaping (_ error : Error?) -> Void)  {
        return find(with: providerBundleIdentifier) { manager, err in
            if err == nil {
                self.providerManager = manager ?? NETunnelProviderManager()
                completion(nil)
            } else {
                completion(err)
            }
        }
        
//        NETunnelProviderManager.loadAllFromPreferences { (managers, error)  in
//            if error == nil {
//                self.providerManager = managers?.first ?? NETunnelProviderManager()
//                completion(nil)
//            } else {
//                completion(error)
//            }
//        }
    }
    
    func onVpnStatusChanged(notification : NEVPNStatus) {
        switch notification {
        case NEVPNStatus.connected:
            stage?("connected")
            break;
        case NEVPNStatus.connecting:
            stage?("connecting")
            break;
        case NEVPNStatus.disconnected:
            stage?("disconnected")
            break;
        case NEVPNStatus.disconnecting:
            stage?("disconnecting")
            break;
        case NEVPNStatus.invalid:
            stage?("invalid")
            break;
        case NEVPNStatus.reasserting:
            stage?("reasserting")
            break;
        default:
            stage?("null")
            break;
        }
    }
    
    func onVpnStatusChangedString(notification : NEVPNStatus?) -> String?{
        if notification == nil {
            return "disconnected"
        }
        switch notification! {
        case NEVPNStatus.connected:
            return "connected";
        case NEVPNStatus.connecting:
            return "connecting";
        case NEVPNStatus.disconnected:
            return "disconnected";
        case NEVPNStatus.disconnecting:
            return "disconnecting";
        case NEVPNStatus.invalid:
            return "invalid";
        case NEVPNStatus.reasserting:
            return "reasserting";
        default:
            return "";
        }
    }
    
    func currentStatus() -> String? {
        if self.providerManager != nil {
            return onVpnStatusChangedString(notification: self.providerManager.connection.status)}
        else{
            return "disconnected"
        }
        //        return "DISCONNECTED"
    }
    
    public func install(configuration: String, serverAddress: String, memberId: String, completionHandler: ((Error?) -> Void)?) {
        let bundleIdentifier = providerBundleIdentifier
        find(with: bundleIdentifier) { manager, err in
            guard let manager = manager else {
                completionHandler?(err)
                return
            }
            
            self.providerManager = manager
            let tunnelProtocol = NETunnelProviderProtocol()
            tunnelProtocol.username = ""
            tunnelProtocol.serverAddress = serverAddress
            tunnelProtocol.providerBundleIdentifier = bundleIdentifier // bundle id of the network extension target
            let dataConfiguration:Data = Data(configuration.utf8)
            tunnelProtocol.providerConfiguration = ["ovpn": dataConfiguration, "memberId":memberId]
            tunnelProtocol.disconnectOnSleep = false
            manager.protocolConfiguration = tunnelProtocol
            manager.localizedDescription = self.localizedDescription // the title of the VPN profile which will appear on Settings
            manager.isEnabled = true
            manager.saveToPreferences { (error) in
                guard error == nil else {
                    manager.isEnabled = false
                    completionHandler?(error)
                    return
                }
                manager.loadFromPreferences { (error) in
                    completionHandler?(error)
                }
            }
        }
    }
    
    private func find(with bundleIdentifier: String, completionHandler: @escaping (NETunnelProviderManager?, Error?) -> Void) {
        self.isProfileExists = false
        NETunnelProviderManager.loadAllFromPreferences { (managers, error) in
            guard error == nil else {
                completionHandler(nil, error)
                return
            }
            let manager = managers?.first {
                guard let ptm = $0.protocolConfiguration as? NETunnelProviderProtocol else {
                    return false
                }
                let find = (ptm.providerBundleIdentifier == bundleIdentifier)
                self.isProfileExists = true
//                log.debug("VPN Profile \(bundleIdentifier) found.")
                return find
            }
            completionHandler(manager ?? NETunnelProviderManager(), nil)
        }
    }
    
    public func connect(server: String, endpointId: Int, isWebRtcBlock: Bool, completionHandler: ((Error?) -> Void)?) {
        
        guard let manager = self.providerManager else { return }
        manager.isEnabled = true
        self.setOnDemand()
        
        guard let protocolConfiguration = manager.protocolConfiguration as! NETunnelProviderProtocol? else {return}
        
        guard var providerConfiguration = protocolConfiguration.providerConfiguration else {return}
        
        providerConfiguration.updateValue(server, forKey: "server")
        providerConfiguration.updateValue(isWebRtcBlock, forKey: "webRtcBlock")
        providerConfiguration.updateValue(endpointId, forKey: "endpointId")
        
        protocolConfiguration.providerConfiguration = providerConfiguration
        manager.protocolConfiguration = protocolConfiguration
        
        manager.saveToPreferences { (error) in
            guard error == nil else {
                self.providerManager!.isEnabled = false
                completionHandler?(error)
                return
            }
            self.providerManager!.loadFromPreferences { (error) in
                completionHandler?(error)
                do {
                    if self.vpnStageObserver != nil {
                        NotificationCenter.default.removeObserver(self.vpnStageObserver!, name: NSNotification.Name.NEVPNStatusDidChange, object: nil)
                    }
                    self.vpnStageObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.NEVPNStatusDidChange, object: nil , queue: nil) { [weak self] notification in
                        let nevpnconn = notification.object as! NEVPNConnection
                        let status = nevpnconn.status
                        self?.onVpnStatusChanged(notification: status)
                    }
                    try self.providerManager?.connection.startVPNTunnel(options: ["server" : server as NSObject, "endpointId" : endpointId as NSObject, "webRtcBlock" : isWebRtcBlock as NSObject])
                    completionHandler?(nil)
                } catch let e {
                    self.stopVPN()
                    completionHandler?(e)
                }
            }
        }
    }
    /*
    func configureVPN(config: String, memberId: String?, server: String?, endpointId: Int?, webRtcBlock: Bool?, completion:@escaping (_ error : Error?) -> Void) {
        guard let configData = config.data(using: .utf8) else {return}
        self.providerManager?.loadFromPreferences { error in
            if error == nil {
                let protocolConfiguration = NETunnelProviderProtocol()
                protocolConfiguration.username = ""
                protocolConfiguration.serverAddress = ""
                protocolConfiguration.providerBundleIdentifier = self.providerBundleIdentifier
                var providerConfiguration = ["ovpn": configData, "webRtcBlock": webRtcBlock ?? false]
                if let server = server {
                    providerConfiguration["server"] = server
                }
                if let endpointId = endpointId {
                    providerConfiguration["endpointId"] = endpointId
                }
                if let server = server {
                    providerConfiguration["server"] = server
                }
                if let memberId = memberId {
                    providerConfiguration["memberId"] = memberId
                }
//                protocolConfiguration.providerConfiguration = [
//                    "config": configData,
//                    "groupIdentifier": self.groupIdentifier?.data(using: .utf8) ?? nullData!,
//                    "username" : username?.data(using: .utf8) ?? nullData!,
//                    "password" : password?.data(using: .utf8) ?? nullData!
//                ]
                protocolConfiguration.providerConfiguration = providerConfiguration
                protocolConfiguration.disconnectOnSleep = false
                self.providerManager.protocolConfiguration = protocolConfiguration
                self.providerManager.localizedDescription = self.localizedDescription // the title of the VPN profile which will appear on Settings
                self.providerManager.isEnabled = true
                self.providerManager.saveToPreferences(completionHandler: { (error) in
                    if error == nil  {
                        self.providerManager.loadFromPreferences(completionHandler: { (error) in
                            if error != nil {
                                self.providerManager.isEnabled = false
                                completion(error);
                                return;
                            }
                            do {
                                if self.vpnStageObserver != nil {
                                    NotificationCenter.default.removeObserver(self.vpnStageObserver!, name: NSNotification.Name.NEVPNStatusDidChange, object: nil)
                                }
                                self.vpnStageObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.NEVPNStatusDidChange, object: nil , queue: nil) { [weak self] notification in
                                    let nevpnconn = notification.object as! NEVPNConnection
                                    let status = nevpnconn.status
                                    self?.onVpnStatusChanged(notification: status)
                                }
                                
                                if let server = server, let endpointId = endpointId {
                                    let options: [String : NSObject] = [
                                        "server": server as NSObject,
                                        "endpointId": endpointId as NSObject,
                                        "webRtcBlock": (webRtcBlock ?? false) as NSObject
                                    ]
                                    try self.providerManager.connection.startVPNTunnel(options: options)
                                } else{
                                    try self.providerManager.connection.startVPNTunnel()
                                }

                                completion(nil);
                            } catch let error {
                                self.stopVPN()
                                print("Error info: \(error)")
                                completion(error);
                            }
                        })
                    }
                })
            }
        }
        
        
    }
    */
    func stopVPN() {
        self.providerManager.connection.stopVPNTunnel();
        self.providerManager.isOnDemandEnabled = false
        self.providerManager.isEnabled = false
    }
    
    func getTraffictStats(){
        if let session = self.providerManager?.connection as? NETunnelProviderSession {
            do {
                try session.sendProviderMessage("OPENVPN_STATS".data(using: .utf8)!) {(data) in
                    //Do nothing
                }
            } catch {
            // some error
            }
        }
    }
    
    func sendServer(message: Int) {
        guard let vpnSession = self.providerManager?.connection as? NETunnelProviderSession else {return}
        let data = String(message).data(using: .utf8)
        do {
            try vpnSession.sendProviderMessage(data!, responseHandler: {data in})
        }
        catch {}
        saveEndpoint(message)
    }
    
    private func saveEndpoint(_ endpointId:Int) {
        guard let manager = self.providerManager else { return }
        manager.isEnabled = true
        self.setOnDemand()
        
        guard let protocolConfiguration = manager.protocolConfiguration as! NETunnelProviderProtocol? else {return}
        guard var providerConfiguration = protocolConfiguration.providerConfiguration else {return}
        
        providerConfiguration.updateValue(endpointId, forKey: "endpointId")
        
        protocolConfiguration.providerConfiguration = providerConfiguration
        manager.protocolConfiguration = protocolConfiguration
        
        manager.saveToPreferences { (error) in
            guard error == nil else {
                self.providerManager!.isEnabled = false
                //completionHandler?(error)
                return
            }
        }
    }

    private func setOnDemand() {
        let connectRule = NEOnDemandRuleConnect()
        connectRule.interfaceTypeMatch = .any
        self.providerManager!.onDemandRules = [connectRule]
        self.providerManager!.isOnDemandEnabled = true //Store().autoStart
        self.providerManager!.onDemandRules = [NEOnDemandRuleConnect()]
    }

}
