//
//  ViewController.swift
//  RatingApp
//
//  Created by dungvh on 10/19/15.
//  Copyright © 2015 dungvh. All rights reserved.
//

import UIKit
import Alamofire
class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        requestAppstore()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

extension ViewController:iRateDelegate{
    func requestAppstore(){
        iRate.sharedInstance().applicationBundleID = "com.charcoaldesign.rainbowblocks-free"
        iRate.sharedInstance().onlyPromptIfLatestVersion = false
        iRate.sharedInstance().previewMode = true
        iRate.sharedInstance().delegate = self
        iRate.sharedInstance().applicationLaunched()
    
    }
    
    func iRateShouldPromptForRating() -> Bool {
        return true
    }
    
    func iRateShouldOpenAppStore() -> Bool {
        return true
    }
    
    func iRateUserDidDeclineToRateApp() {
        print("\nUser Decline App!!!")
    }
    
    func iRateCouldNotConnectToAppStore(_ error: NSError?) {
        print("\nError Open Appstore : \(error?.localizedDescription ?? "")")
    }
    
    func iRateDidPromptForRating() {
        
    }
    
    func iRateDidOpenAppStore() {
        print("\n Open Appstore")
    }
}

