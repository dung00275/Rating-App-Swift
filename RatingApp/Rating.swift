//
//  Rating.swift
//  RatingApp
//
//  Created by dungvh on 10/19/15.
//  Copyright © 2015 dungvh. All rights reserved.
//

import Foundation
import UIKit
import SystemConfiguration
import UIKit
import Alamofire
import ObjectMapper

// MARK: - Delegate
@objc protocol iRateDelegate:NSObjectProtocol{
    // Optional
    @objc optional func iRateCouldNotConnectToAppStore(_ error:NSError?)
    @objc optional func iRateDidDetectAppUpdate()
    @objc optional func iRateDidPromptForRating()
    @objc optional func iRateUserDidAttemptToRateApp()
    @objc optional func iRateUserDidDeclineToRateApp()
    @objc optional func iRateUserDidRequestReminderToRateApp()
    @objc optional func iRateDidOpenAppStore()
    
    // Require
    func iRateShouldPromptForRating() -> Bool
    func iRateShouldOpenAppStore() -> Bool
}

// MARK: --- Configure To Check
let iRateAppStoreGameGenreID = 6014
let iRateErrorDomain = "iRateErrorDomain"


let iRateAppStoreIDKey = "iRateAppStoreIDKey"
let iRateRatedVersionKey = "iRateRatedVersionKey"
let iRateDeclinedVersionKey = "iRateDeclinedVersionKey"
let iRateLastRemindedKey = "iRateLastRemindedKey"
let iRateLastVersionUsedKey = "iRateLastVersionUsedKey"
let iRateFirstUsedKey = "iRateFirstUsedKey"
let iRateUseCountKey = "iRateUseCountKey"
let iRateEventCountKey = "iRateEventCountKey"
let iRateItunesValueKey = "iRateItunesValueKey"

let iRateAppLookupURLFormat = "http://itunes.apple.com/%@/lookup"
let iRateiOSAppStoreURLScheme = "itms-apps"
let iRateiOSAppStoreURLFormat = "itms-apps://itunes.apple.com/WebObjects/MZStore.woa/wa/viewContentsUserReviews?type=Purple+Software&id=%@"
let iRateiOS7AppStoreURLFormat = "itms-apps://itunes.apple.com/app/id%@"

let SECONDS_IN_A_DAY:Float = 86400
let SECONDS_IN_A_WEEK:Float = 604800
let REQUEST_TIMEOUT:Float = 60

let kNoInternetCode = 8456

let kFormatRatingMessageGameDefault = "If you enjoy playing %@, would you mind taking a moment to rate it? It won’t take more than a minute. Thanks for your support!"
let kFormatRatingMessageAppDefault = "If you enjoy using %@, would you mind taking a moment to rate it? It won’t take more than a minute. Thanks for your support!"

enum iRateErrorCode:Int{
    case bundleIdDoesNotMatchAppStore = 1,
    applicationNotFoundOnAppStore,
    applicationIsNotLatestVersion,
    couldNotOpenRatingPageURL
}


// MARK:- Check Network
open class Reachability {
    class func isConnectedToNetwork() -> Bool {
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout.size(ofValue: zeroAddress))
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        guard let defaultRouteReachability = (withUnsafePointer(to: &zeroAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {zeroSockAddress in
                SCNetworkReachabilityCreateWithAddress(nil, zeroSockAddress)
            }
        }) else { return false}
        
    
        var flags = SCNetworkReachabilityFlags.connectionAutomatic
        if !SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags) {
            return false
        }
        let isReachable = (flags.rawValue & UInt32(kSCNetworkFlagsReachable)) != 0
        let needsConnection = (flags.rawValue & UInt32(kSCNetworkFlagsConnectionRequired)) != 0
        return (isReachable && !needsConnection)
    }
}

// MARK: - User Default
func getValueFromUserDefault(_ key:String) -> Any?{
    let userDefault = UserDefaults.standard
    return userDefault.object(forKey: key)
}
func setValueToUserdefault(_ obj:Any?,key:String){
    let userDefault = UserDefaults.standard
    userDefault.set(obj, forKey: key)
    userDefault.synchronize()
}

// MARK: - Core Init
class iRate {
    //application details - these are set automatically
    var appStoreID:Int?{
        return self.model?.trackId
    }
    var appStoreGenreID:Int = 0
    var appStoreCountry:String?
    var applicationName:String?
    var applicationVersion:String?
    var applicationBundleID:String!
    
    //usage settings - these have sensible defaults
    // Default : -

    var usesUntilPrompt:Int = 10
    var eventsUntilPrompt:Int = 10
    var daysUntilPrompt:Float =  10.0
    var usesPerWeekForPrompt:Float = 0
    var remindPeriod:Float = 1.0

    
    fileprivate var error:NSError?
    fileprivate var model:ModelItunes?{
        didSet{
            guard let value = self.model else{
                return
            }
            self.trackErrorFromReponseServer(value)
        }
    }
    
    //message text, you may wish to customise these
    // MARK: --- Public Variable To Custom Message
    var messageTitle:String!
    fileprivate func getMessageTitle() -> String{
        guard let message = messageTitle else{
            let value = applicationName ?? "AppName"
            return "Rate \(value)"
        }
        return message
    }
    
    var message:String!
    fileprivate func getMessage() -> String{
        guard let message2 = self.message else{
            let kFormat = (appStoreGenreID == iRateAppStoreGameGenreID) ? kFormatRatingMessageGameDefault : kFormatRatingMessageAppDefault
            
            return String(format: kFormat, applicationName ?? "App Name")
        }
        
        return message2
    }
    var cancelButtonLabel:String!
    fileprivate func getCancelButtonLabel() ->String{
        guard let cancelMessage = self.cancelButtonLabel else{
            return "No, Thanks"
        }
        return cancelMessage
    }
    var remindButtonLabel:String!
    fileprivate func getReminderLabel() ->String{
        guard let reminderMessage = self.remindButtonLabel else{
            return "Remind Me Later"
        }
        
        return reminderMessage
    }
    var rateButtonLabel:String!
    fileprivate func getRateButtonLabel() ->String{
        guard let rateMessage = self.rateButtonLabel else{
            return "Rate It Now"
        }
        return rateMessage
        
    }
    
    //debugging and prompt overrides
    var onlyPromptIfLatestVersion:Bool = true
    var onlyPromptIfMainWindowIsAvailable:Bool = true
    var promptAtLaunch:Bool = true
    var verboseLogging:Bool = true
    var previewMode:Bool = false
    var checking:Bool = false
    
    
    //advanced properties for implementing custom behaviour
    var ratingsURL:URL?
    
    fileprivate var firstUsed:Date?{
        set(newValue){
            setValueToUserdefault(newValue, key: iRateFirstUsedKey)
        }
        
        get{
            return getValueFromUserDefault(iRateFirstUsedKey) as? Date
        }
    }
    
    fileprivate var lastReminded:Date?{
        set(newValue){
            setValueToUserdefault(newValue, key: iRateLastRemindedKey)
        }
        
        get{
            return getValueFromUserDefault(iRateLastRemindedKey) as? Date
        }
    }
    
    fileprivate var usesCount:Int{
        set(newValue){
            setValueToUserdefault(newValue, key: iRateUseCountKey)
        }
        
        get{
            guard let value =  getValueFromUserDefault(iRateUseCountKey) as? Int else{
                return 0
            }
            return value
        }
    }
    
    fileprivate var eventCount:Int{
        set(newValue){
            setValueToUserdefault(newValue, key: iRateEventCountKey)
        }
        
        get{
            guard let value =  getValueFromUserDefault(iRateEventCountKey) as? Int else{
                return 0
            }
            return value
        }
    }

    var usesPerWeek:Float = 0
    fileprivate func getUsesPerWeek() -> Float{
        guard let firstUsed = self.firstUsed else{
            return 0
        }
        
        return Float(self.usesCount) / Float(Date().timeIntervalSince(firstUsed)) / SECONDS_IN_A_WEEK
    }
    
    var declinedThisVersion:Bool {
        
        set(newValue){
            setValueToUserdefault(newValue ? self.applicationVersion: nil , key: iRateDeclinedVersionKey)
        }
        get{
            guard let value = getValueFromUserDefault(iRateDeclinedVersionKey) as? String , let applicationVersion = self.applicationVersion, value == applicationVersion else{
                return false
            }
            
            return true
        }
    }
    var declinedAnyVersion:Bool{
        guard let value = getValueFromUserDefault(iRateDeclinedVersionKey) as? String, value.characters.count > 0 else{
            return false
        }
        
        return true
    }
    
    var ratedThisVersion:Bool{
        set(newValue){
            setValueToUserdefault(newValue ? self.applicationVersion: nil , key: iRateRatedVersionKey)
        }
        get{
            guard let value = getValueFromUserDefault(iRateRatedVersionKey) as? String , let applicationVersion = self.applicationVersion, value == applicationVersion else{
                return false
            }
            
            return true
        }
    }
    var ratedAnyVersion:Bool{
        guard let value = getValueFromUserDefault(iRateRatedVersionKey) as? String, value.characters.count > 0 else{
            return false
        }
        
        return true
    }
    
    fileprivate var checkingForPrompt:Bool = false
    fileprivate var checkingForAppStoreID:Bool = false
    
    weak var delegate:iRateDelegate?
    
// MARK: - Shared Instance
    struct Static {
        static let sharedInstance = iRate()
    }
    
    class func sharedInstance() -> iRate{
        return Static.sharedInstance
    }
    
// MARK: - Init
    init()
    {
        self.appStoreCountry = (Locale.current as NSLocale).object(forKey: NSLocale.Key.countryCode) as? String
        self.applicationVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        
        if applicationVersion == nil || applicationVersion!.characters.count == 0{
            self.applicationVersion = Bundle.main.object(forInfoDictionaryKey: String(kCFBundleVersionKey)) as? String
        }
        
        self.applicationName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        
        if applicationName == nil || applicationName!.characters.count == 0{
            self.applicationName =  Bundle.main.object(forInfoDictionaryKey: String(kCFBundleNameKey)) as? String
        }
        
        self.applicationBundleID = Bundle.main.bundleIdentifier
        #if DEBUG
            self.verboseLogging = true
        #else
            self.verboseLogging = false
        #endif
    }
    
    deinit{
        print("\n iRate \(#function)")
    }
    
}

// MARK: - Public Function
extension iRate{
    func applicationLaunched(){
        
        defer{
            self.incrementUseCount()
            
            if self.promptAtLaunch && self.shouldPromptForRating(){
                self.promptIfNetworkAvailable()
            }
        }
        let value = getValueFromUserDefault(iRateLastVersionUsedKey) as? String
        
        if value == nil || value != applicationVersion{
            setValueToUserdefault(applicationVersion, key: iRateLastVersionUsedKey)
            setValueToUserdefault(Date(), key: iRateFirstUsedKey)
            setValueToUserdefault(0, key: iRateUseCountKey)
            setValueToUserdefault(0, key: iRateEventCountKey)
            setValueToUserdefault(nil, key: iRateLastRemindedKey)
            delegate?.iRateDidDetectAppUpdate?()
        }
    }
}
// MARK: - Helper
private extension iRate{
    func getRatingUrl() -> URL?{
        if self.ratingsURL == nil{
            guard let appId = self.appStoreID else{
                return nil
            }
            return URL(string: String(format: iRateiOS7AppStoreURLFormat, "\(appId)"))
        }
        
        return self.ratingsURL
    }
    
    func incrementUseCount(){
        self.usesCount += 1
    }
    func incrementEventCount(){
        self.eventCount += 1
    }
    
    func checkForConnectivityInBackground(){
        if checking { return }
        checking = true
        
        var iTunesServiceURL = String(format: iRateAppLookupURLFormat, appStoreCountry ?? "US")
        
        if let appStoreID = self.appStoreID {
            iTunesServiceURL = iTunesServiceURL + "?id=\(appStoreID)"
        }else{
            iTunesServiceURL = iTunesServiceURL + "?bundleId=\(applicationBundleID ?? "")"
        }
        
        if verboseLogging{
            print("\niRate is checking \(iTunesServiceURL) to retrieve the App Store details...")
        }
        
        
        let request:DataRequest = SessionManager.default.request(iTunesServiceURL, method: .get)
        
        request.responseJSON(queue: DispatchQueue.global(qos: .background) , options: .allowFragments) { [weak self](r) in
            defer{
                self?.checking = false
                if let error3 = self?.error, !(error3.code == Int(EPERM) && error3.domain == NSPOSIXErrorDomain && self?.appStoreID != nil){
                    self?.connectionError(error3)
                }else{
                    self?.connectionSucceeded()
                }
            }
            
            switch r.result {
            case .success(let v):
                guard let json = v as? [String: Any], let values = json["results"] as? [AnyObject], values.count > 0  else{
                    self?.error = NSError(domain: iRateErrorDomain, code: 4786, userInfo: [NSLocalizedDescriptionKey:"Not have values"])
                    return
                }
                setValueToUserdefault(values, key: iRateItunesValueKey)
                self?.model = Mapper<ModelItunes>().map(JSONObject: values.last)
            case .failure(let e):
                let statusCode = r.response?.statusCode ?? 0
                self?.error = NSError(domain: "HTTPResponseErrorDomain", code: statusCode, userInfo: [NSLocalizedDescriptionKey: e.localizedDescription])
                
            }
        }

    }
    
    func connectionError(_ error:NSError?){
        if self.checkingForPrompt || self.checkingForAppStoreID{
            //no longer checking
            
            self.checkingForPrompt = false
            self.checkingForAppStoreID = false
            
            defer{
                self.delegate?.iRateCouldNotConnectToAppStore?(error)
            }
            
            guard let error1 = error else{
                print("\niRate rating process failed because an unknown error occured")
                return
            }
            
            print("\niRate rating process failed because: \(error1.localizedDescription)")
            
        }
    }
    
    func connectionSucceeded(){
        if self.checkingForAppStoreID{
            //no longer checking
            self.checkingForPrompt = false
            self.checkingForAppStoreID = false
            
            //open app store
            self.openRatingsPageInAppStore()
        }else if self.checkingForPrompt{
            self.checkingForPrompt = false
            
            if let value = self.delegate?.iRateShouldPromptForRating(), value == false{
                if self.verboseLogging{
                    print("\niRate did not display the rating prompt because the iRateShouldPromptForRating delegate method returned false!!!")
                }
                return
                
            }else{
                if self.verboseLogging{
                    print("\niRate did display the rating prompt because the iRateShouldPromptForRating delegate method returned true!!!")
                }
            }
            
            //prompt user
            self.promptForRating()
        }
    }
    
}

// MARK: - Manually control behaviour
private extension iRate{
    func shouldPromptForRating() -> Bool{
        //preview mode?
        let value1 = self.previewMode
        
        //check if we've rated the app
        let value2 = self.ratedAnyVersion
        
        //check if we've declined to rate the app
        let value3 = self.declinedAnyVersion
        
        //check for first launch
        let value4 = (self.daysUntilPrompt > 0.0 || self.usesPerWeekForPrompt == 0) && self.firstUsed == nil
        
        //check how long we've been using this version
        let value5 = (self.firstUsed != nil) ? Float(Date().timeIntervalSince(self.firstUsed!)) < self.daysUntilPrompt * SECONDS_IN_A_DAY : false
        
        //check how many times we've used it and the number of significant events
        let value6 = self.usesCount < self.usesUntilPrompt && self.eventCount < self.eventsUntilPrompt
        
        //check if usage frequency is high enough
        let value7 = self.getUsesPerWeek() < self.usesPerWeekForPrompt
        
        //check if within the reminder period
        let value8 = (self.lastReminded != nil) ? Float(Date().timeIntervalSince(self.lastReminded!)) < self.remindPeriod * SECONDS_IN_A_DAY : false
        
        switch (value1,value2,value3,value4,value5,value6,value7,value8){
        case (true,_,_,_,_,_,_,_):
            if verboseLogging{
                print("\niRate preview mode is enabled - make sure you disable this for release")
            }
            return true
        case (_,true,_,_,_,_,_,_):
            if verboseLogging{
                print("\niRate did not prompt for rating because the user has already rated the app")
            }
            return false
        case (_,_,true,_,_,_,_,_):
            if verboseLogging{
                print("\niRate did not prompt for rating because the user has declined to rate the app")
            }
            return false
        case (_,_,_,true,_,_,_,_):
            if verboseLogging{
                print("\niRate did not prompt for rating because this is the first time the app has been launched")
            }
            return false
        case (_,_,_,_,true,_,_,_):
            if verboseLogging{
                print("\niRate did not prompt for rating because the app was first used less than \(daysUntilPrompt) days ago")
            }
            return false
        case (_,_,_,_,_,true,_,_):
            if verboseLogging{
                print("\niRate did not prompt for rating because the app has only been used \(usesCount) times and only \(eventCount) events have been logged")
            }
            return false
        case (_,_,_,_,_,_,true,_):
            if verboseLogging{
                print("\niRate did not prompt for rating because the app has only been used \(getUsesPerWeek()) times per week on average since it was installed")
            }
            return false
        case (_,_,_,_,_,_,_,true):
            if verboseLogging{
                print("\niRate did not prompt for rating because the user last asked to be reminded less than \(remindPeriod) days ago")
            }
            return false
        default:
            break
        }
        
        return true
    }
    
    func promptForRating(){
        let alert = UIAlertController(title: self.getMessageTitle(), message: self.getMessage(), preferredStyle: UIAlertControllerStyle.alert)
        let actionRating = UIAlertAction(title: self.getRateButtonLabel(), style: .default) { [weak self](action) -> Void in
            alert.dismiss(animated: true, completion: nil)
            self?.handleAction(iRateAction.rating)
        }
        
        let actionReminder = UIAlertAction(title: self.getReminderLabel(), style: .default) { [weak self](action) -> Void in
            alert.dismiss(animated: true, completion: nil)
            self?.handleAction(iRateAction.reminder)
        }
        
        
        let actionCancel = UIAlertAction(title: self.getCancelButtonLabel(), style: .cancel) { [weak self](action) -> Void in
            alert.dismiss(animated: true, completion: nil)
            self?.handleAction(iRateAction.cancel)
        }
        
        alert.addAction(actionRating)
        alert.addAction(actionReminder)
        alert.addAction(actionCancel)
        DispatchQueue.main.async { () -> Void in
            UIApplication.shared.keyWindow?.rootViewController?.present(alert, animated: true, completion: nil)
        }
    }
    
    func promptIfNetworkAvailable(){
        if !Reachability.isConnectedToNetwork(){
            let error = NSError(domain: iRateErrorDomain, code: kNoInternetCode, userInfo: [NSLocalizedDescriptionKey:"Internet is not available!!!"])
            connectionError(error)
            return
        }
        
        if !self.checkingForPrompt && !self.checkingForAppStoreID{
            self.checkingForPrompt = true
            self.checkForConnectivityInBackground()
        }
    }
    
    func openRatingsPageInAppStore(){
        guard let ratingsURL = self.getRatingUrl(),let _ = self.appStoreID else{
            self.checkingForAppStoreID = true
            
            if !self.checkingForPrompt{
                self.checkForConnectivityInBackground()
            }
            return
        }
        
        if UIApplication.shared.canOpenURL(ratingsURL){
            if self.verboseLogging{
                print("iRate will open the App Store ratings page using the following URL: \(ratingsURL)")
            }
            let isOpenURL = self.delegate?.iRateShouldOpenAppStore() ?? false
            if isOpenURL { UIApplication.shared.openURL(ratingsURL) }
            
        }else{
            var message = "iRate was unable to open the specified ratings URL: \(ratingsURL)"
            
            if ratingsURL.scheme == iRateiOSAppStoreURLScheme{
                message = "iRate could not open the ratings page because the App Store is not available on the iOS simulator"
            }
            
            let error = NSError(domain: iRateErrorDomain, code: iRateErrorCode.couldNotOpenRatingPageURL.rawValue, userInfo: [NSLocalizedDescriptionKey: message])
            self.delegate?.iRateCouldNotConnectToAppStore?(error)
        }
    }
    
    
    func logEvent(_ deferPrompt:Bool){
        self.incrementEventCount()
        if !deferPrompt && self.shouldPromptForRating(){
            self.promptIfNetworkAvailable()
        }
    }
    
}

// MARK: --- Tracking Error From Model
private extension iRate{
    
    func trackErrorFromReponseServer(_ value:ModelItunes)
    {
        guard let bundleID = value.bundleId else{
            if self.getRatingUrl() == nil {
                if self.verboseLogging{
                    print("\niRate could not find this application on iTunes. If your app is not intended for App Store release then you must specify a custom ratingsURL. If this is the first release of your application then it's not a problem that it cannot be found on the store yet")
                }
                
                if !self.previewMode{
                    self.error = NSError(domain: iRateErrorDomain, code: iRateErrorCode.applicationNotFoundOnAppStore.rawValue, userInfo: [NSLocalizedDescriptionKey:"The application could not be found on the App Store."])
                }
                return
            }
            
            if value.trackId == nil && self.verboseLogging{
                print("iRate could not find your app on iTunes. If your app is not yet on the store or is not intended for App Store release then don't worry about this")
            }
            
            return
        }
        
        guard bundleID == self.applicationBundleID else{
            if self.verboseLogging{
                print("\niRate found that the application bundle ID (\(applicationBundleID)) does not match the bundle ID of the app found on iTunes (%@) with the specified App Store ID (\(bundleID))")
            }
            
            self.error = NSError(domain: iRateErrorDomain, code: iRateErrorCode.bundleIdDoesNotMatchAppStore.rawValue, userInfo: [NSLocalizedDescriptionKey:"Application bundle ID does not match expected value of \(bundleID)"])
            
            return
        }
        
        if self.appStoreGenreID == 0{
            self.appStoreGenreID = value.primaryGenreId ?? 0
        }
        
        if verboseLogging && value.trackId != nil{
            print("iRate found the app on iTunes. The App Store ID is \(value.trackId!)")
        }
        
        if onlyPromptIfLatestVersion && !self.previewMode
        {
            guard let version = value.version , let applicationVersion = self.applicationVersion, version.compare(applicationVersion) == .orderedDescending else{
                return
            }
            
            if verboseLogging{
                print("iRate found that the installed application version (\(applicationVersion)) is not the latest version on the App Store, which is \(version)")
            }
            
            self.error = NSError(domain: iRateErrorDomain, code: iRateErrorCode.applicationIsNotLatestVersion.rawValue, userInfo: [NSLocalizedDescriptionKey:"Installed app is not the latest version available"])
            
        }
    }
}


// MARK: --- Handle Action From User
enum iRateAction:Int{
    case cancel = 0,
    reminder,
    rating
}


private extension iRate{
    func handleAction(_ type:iRateAction){
        switch type{
        case .cancel:
            self.declinedThisVersion = true
            
            self.delegate?.iRateUserDidDeclineToRateApp?()
        case .reminder:
            self.lastReminded = Date()
            
            self.delegate?.iRateUserDidRequestReminderToRateApp?()
        case .rating:
            self.ratedThisVersion = true
            
            self.delegate?.iRateUserDidAttemptToRateApp?()
            
            if let value = self.delegate?.iRateShouldOpenAppStore(), value == true{
                self.openRatingsPageInAppStore()
            }
        }
    }
}
