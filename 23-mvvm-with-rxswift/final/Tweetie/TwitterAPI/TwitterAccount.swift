/*
 * Copyright (c) 2016-2017 Razeware LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

import Foundation

import RxSwift
import RxCocoa

import Alamofire
import Unbox

typealias AccessToken = String

struct TwitterAccount {

  static private var key: String!
  static private var secret: String!
  static public func set(key: String, secret: String) {
    precondition(key != "placeholder", "\n" +
    """
      -----------------------------------\n
      ~> You need to provide your Twitter APP Key and Secret, consult Chapter 23 of the RxSwift book for instructions how to register your own app\n
      -----------------------------------\n\n
    """)
    self.key = key
    self.secret = secret
  }

  private struct Token: Unboxable {
    let tokenString: String
    init(unboxer: Unboxer) throws {
      guard try unboxer.unbox(key: "token_type") == "bearer" else {
        throw Errors.invalidResponse
      }
      tokenString = try unboxer.unbox(key: "access_token")
    }
  }

  // logged or not
  enum AccountStatus {
    case unavailable
    case authorized(AccessToken)
  }

  enum Errors: Error {
    case unableToGetToken, invalidResponse
  }

  // MARK: - Properties

  // MARK: - Getting the current twitter account
  private func oAuth2Token(completion: @escaping (String?)->Void) -> DataRequest {
    let parameters: Parameters = ["grant_type": "client_credentials"]
    var headers: HTTPHeaders = ["Content-Type": "application/x-www-form-urlencoded;charset=UTF-8"]

    if let authorizationHeader = Request.authorizationHeader(user: TwitterAccount.key, password: TwitterAccount.secret) {
      headers[authorizationHeader.key] = authorizationHeader.value
    }

    return Alamofire.request("https://api.twitter.com/oauth2/token",
                      method: .post,
                      parameters: parameters,
                      encoding: URLEncoding.httpBody,
                      headers: headers
      ).responseJSON { response in
        guard response.error == nil, let data = response.data, let token: Token = try? unbox(data: data) else {
          completion(nil)
          return
        }
        completion(token.tokenString)
      }
  }

  var `default`: Driver<AccountStatus> {
    return Observable.create({ observer in
      var request: DataRequest?

      if let storedToken = UserDefaults.standard.string(forKey: "token") {
        observer.onNext(.authorized(storedToken))
      } else {
        request = self.oAuth2Token { token in
          guard let token = token else {
            observer.onNext(.unavailable)
            return
          }
          UserDefaults.standard.set(token, forKey: "token")
          observer.onNext(.authorized(token))
        }
      }

      return Disposables.create {
        request?.cancel()
      }
    })
    .asDriver(onErrorJustReturn: .unavailable)
  }
}
