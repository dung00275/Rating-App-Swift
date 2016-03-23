//
//  Model.swift
//  RatingApp
//
//  Created by dungvh on 10/19/15.
//  Copyright © 2015 dungvh. All rights reserved.
//

import Foundation
import ObjectMapper

class ModelItunes: Mappable {
    var bundleId:String?
    var primaryGenreName:String?
    var primaryGenreId:Int?
    var userRatingCount:Int?
    var trackId:Int?
    var trackViewUrl:String?
    var version:String?
    
    init(){
        
    }
    
    required init?(_ map: Map) {
        
    }
    
    func mapping(map: Map) {
        bundleId <- map["bundleId"]
        primaryGenreName <- map["primaryGenreName"]
        primaryGenreId <- map["primaryGenreId"]
        userRatingCount <- map["userRatingCount"]
        trackId <- map["trackId"]
        trackViewUrl <- map["trackViewUrl"]
        version <- map["version"]
    }
    
    
}