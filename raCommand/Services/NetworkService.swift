//
//  NetworkService.swift
//  raCommand
//
//  Custom URLSession utility to bypass SSL/TLS verification for local development
//  hosts (e.g. localhost, 127.0.0.1, and local readyaimgo.biz instances).
//

import Foundation

class LocalDevURLSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            let host = challenge.protectionSpace.host
            
            // Bypass SSL verification for local development hosts
            if host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local") || host.contains("readyaimgo.biz") {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }
        completionHandler(.performDefaultHandling, nil)
    }
}

extension URLSession {
    static let localBypassSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        return URLSession(
            configuration: configuration,
            delegate: LocalDevURLSessionDelegate(),
            delegateQueue: nil
        )
    }()
}
