//
//  Helper.swift
//  RatingApp
//
//  Created by Dung Vu on 3/30/17.
//  Copyright © 2017 dungvh. All rights reserved.
//

import Foundation
import RxSwift
import RxAlamofire
import ObjectMapper
import Alamofire

extension NSObject {
    public subscript(key: String) -> Any? {
        get{
            return self.value(forKey:key)
        }
        set{
            self.setValue(newValue, forKey: key)
        }
        
    }
}

extension Bundle {
    var version: String? {
        return self.infoDictionary?["CFBundleShortVersionString"] as? String
    }
    
    var name: String? {
        return (self.infoDictionary?["CFBundleDisplayName"] ?? self.infoDictionary?[String(kCFBundleNameKey)]) as? String
    }
}

extension Reactive where Base: SessionManager {
    public func requestObject<T: Mappable>(with type: T.Type,
                        _ method: Alamofire.HTTPMethod,
                        _ url: URLConvertible,
                        transform: @escaping ((HTTPURLResponse, Any) throws -> Any?),
                        parameters: [String: Any]? = nil,
                        encoding: ParameterEncoding = URLEncoding.default,
                        headers: [String: String]? = nil
        )
        -> Observable<T?>{
            return self.responseJSON(method, url, parameters: parameters, encoding: encoding, headers: headers).map({
                return Mapper<T>().map(JSONObject: try transform($0.0, $0.1))
            })
    }
}
