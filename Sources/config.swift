//
//  config.swift
//  Perfect Slack bot
//
//  Created by Rockford Wei on 2017-03-17.
//	Copyright (C) 2017 PerfectlySoft, Inc.
//
//===----------------------------------------------------------------------===//
//
// This source file is part of the Perfect.org open source project
//
// Copyright (c) 2015 - 2017 PerfectlySoft Inc. and the Perfect project authors
// Licensed under Apache License v2.0
//
// See http://perfect.org/licensing.html for license information
//
//===----------------------------------------------------------------------===//
//

import PerfectLib
import PerfectCURL
import cURL
import PerfectThread
import SQLite

#if os(Linux)
  import SwiftGlibc
#else
  import Darwin
#endif

extension String {
  /// fix some non-zero ending of buffer issue
  public init(buffer: [UInt8]) {
    var buf = buffer
    buf.append(0)
    self = String(cString: buf)
  }//end init
}//end ext

/// Get the current time stamp
public func Now(_ GMT: Bool = false) -> String {
  var t = time(nil)
  let s = GMT ? gmtime(&t) : localtime(&t)
  guard let p = asctime(s) else {
    return ""
  }//end p
  p.advanced(by: Int(strlen(p)) - 1).pointee = 0
  return String(cString: p)
}//end extension

/// A simple log file
let LogLock = Threading.Lock()
let LogFilePath = "/var/run/slackbot.log"
let LogFile = File(LogFilePath)

/// Simple Thread Safe Log Writter
func Print(_ info: String) {
  print(info)
  LogLock.doWithLock {
    do {
      try LogFile.open(.append)
      let now = Now()
      let _ = try LogFile.write(string: "\(now):\t\(info)\n")
      LogFile.close()
    }catch {

    }
  }
}

/// an integrated configuration with db read / write & curl functions
public struct Settings {

  /// oauth token to access slack api
  public var token = ""

  /// your bot name, will display in the channel
  public var bot = ""

  /// your bot slack id, MUST BE mannual acquired from slack app configuration
  public var botId = ""

  /// your app client id
  public var client_id = ""

  /// your app client secret
  public var client_secret = ""

  /// verify token sent by Slack API, optional but essential for preventing
  /// unauthorized access other than slack.com
  public var verify_token = ""

  /// uri for oauth
  public var oauth_uri = ""

  /// uri for incoming message
  public var message_uri = ""

  /// uri for slack interactive message confirmations
  public var confirm_uri = ""

  /// your server name, MUST BE full qualified domain name
  /// with a valid intermediate certificate
  public var serverName = ""

  /// certificate file path, for example, a.crt is your own certificate
  /// and b.crt is the intermediate certificate, then you can merge the
  /// both file by `$ cat a.crt b.crt > c.crt` where c.crt is what we place here
  public var cerPath = ""

  /// your private certificate key
  public var keyPath = ""

  /// your database file path (sqlite3)
  public var dbPath = ""

  /// common user name of the server will run as other than root for security consideration
  public var runAs = ""

  /// the only valid port for a slack api production server is 443: HTTPS
  public let port = 443

  /// cache for channel members [id: name] dictionary
  public static var members:[String:String] = [:]

  /// authroized access channel name; although a bot can join as many channels as need,
  /// this is an example of how to restrict bot to join only authroized channels.
  public var channels: [String:String] = [:]

  /// database handler
  private var db: SQLite

  /// internal configuration handle
  private var json:[String:Any] = [:]

  /// internal configuration path
  private var configurationPath = ""

  /// write configuration if need
  public func saveConfig() {
    do {
      let f = File(configurationPath)
      let config = try json.jsonEncodedString()
      try f.open(.write)
      let _ = try f.write(string: config)
      f.close()
    }catch (let err) {
      Print("Save Config \(configurationPath) failed -> \(err)")
    }//end do
  }//end save

  /// configration constructor
  /// - parameters:
  ///   - configFilePath, path of configration file
  public init(configFilePath: String = "/etc/slackbot.json") {

    configurationPath = configFilePath
    Print("=============== Starting Slack Bot Server ===============")
    let configFile = File(configFilePath)
    do {
      try configFile.open(.read)
      let config = try configFile.readString()
      guard let jsonConfig = try config.jsonDecode() as? [String:Any] else {
        Print("configuration file \(configFilePath) fault")
        exit(-1)
      }//end guard
      json = jsonConfig
      token = json["token"] as? String ?? ""
      bot = json["bot"] as? String ?? ""
      botId = json["bot_id"] as? String ?? ""
      client_id = json["client_id"] as? String ?? ""
      client_secret = json["client_secret"] as? String ?? ""
      verify_token = json["verify_token"] as? String ?? ""
      oauth_uri = json["oauth_uri"] as? String ?? "/oauth"
      message_uri = json["message_uri"] as? String ?? "/message"
      confirm_uri = json["confirm_uri"] as? String ?? "/confirm"
      serverName = json["serverName"] as? String ?? "localhost"
      // port = json["port"] as? Int ?? 443
      cerPath = json["cerPath"] as? String ?? "/etc/certificates/certificate.crt"
      keyPath = json["keyPath"] as? String ?? "/etc/certificates/private.key"
      dbPath = json["dbPath"] as? String ?? "/var/local/cmweb.db"
      channels = json["channels"] as? [String:String] ?? [:]
      configFile.close()
    }catch(let err) {
      Print("General Failure: Invalid Configuration \(configFilePath) -> \(err)")
      exit(-2)
    }//end do

    /// initialize the database
    do {
      db = try SQLite(dbPath)
      let _ = try db.execute(statement: "CREATE TABLE IF NOT EXISTS bank (id INTEGER PRIMARY KEY AUTOINCREMENT, moment REAL NOT NULL, channel TEXT NOT NULL, receiver TEXT NOT NULL, sender TEXT NOT NULL, value INTEGER NOT NULL);CREATE UNIQUE INDEX IF NOT EXISTS eventIndex on bank (moment, channel, receiver, sender);")
    }catch (let err) {
      Print("General Failure: SQL \(dbPath) -> \(err)")
      exit(-3)
    }//end do
  }// init

  public func close(_ msg: String = "") {
    Print(msg)
    db.close()
  }//end quit

  /// get information from a web api asynchronously.
  /// - parameters:
  ///   - completion: closure for request completion. The parameter is the server response, nil for error.
  public func Curl(_ url: String, completion: @escaping (String?)->Void ) {
    Threading.dispatch {
      let curl = CURL(url: url)
      let _ = curl.setOption(CURLOPT_TIMEOUT, int: 10)
      let (code, _, body) = curl.performFully()
      if code > -1 && body.count > 0 {
        completion( String(buffer: body) )
      } else {
        completion(nil)
      }//end if
      curl.close()
    }//end thread
  }//end Curl

  /// deposit one treat (cookie) into the database
  /// - parameters:
  ///   - moment: time stamp
  ///   - channel: channel of the event taking place
  ///   - receiver: user name who received the treat
  ///   - sender: user name who sent the treat
  ///   - value: quantity of the treat
  public func deposit(moment: String, channel: String, receiver: String, sender: String, value: Int) -> Int {
    let sql = "INSERT INTO bank (moment, channel, receiver, sender, value) VALUES (\(moment), '\(channel)', '\(receiver)', '\(sender)', \(value));"
    do {
      let _ = try db.execute(statement: sql)
    }catch(let err) {
      Print("deposit failed: \(err)")
      db.close()
      exit(0)
    }//end do
    return 0
  }//end deposit

  /// calculate the treats of a user
  /// - parameters:
  ///   - me: the user name in database
  public func about(me: String) -> Int {
    var sum = 0
    do {
      try db.forEachRow(statement: "SELECT SUM(value) FROM bank WHERE receiver = '\(me)'") { stmt, _ in
        sum += stmt.columnInt(position: 0)
      }//end
    }catch(let err) {
      Print("about:: \(err)")
    }//end catch
    return sum
  }//end func

  /// a sample leader board
  /// - parameters:
  ///   - top: top listed rows, which restricts the sql result set.
  /// - returns:
  ///   an tuple array - [(name:String, total:Int)] - ordered by the treats
  public func leaderBoard(top: Int = 50) -> [(name:String, total:Int)] {
    var board = [(name:String, total:Int)]()
    do {
      try db.forEachRow(statement: "SELECT receiver, SUM(value) AS total FROM bank GROUP BY receiver ORDER BY total DESC LIMIT \(top)") { stmt, _ in
        let name = stmt.columnText(position: 0)
        let sum =  stmt.columnInt (position: 1)
        board.append((name, sum))
      }//end
    }catch(let err) {
      Print("about:: \(err)")
    }//end catch
    return board
  }//end leaderBoard

  /// get the user display name from a slack query
  /// - parameters:
  ///   - slackReturn: the response from a slack query
  /// - returns:
  ///   user name or nil if failed
  private func parseUserName(_ slackReturn: String?) -> String? {
    do {
      guard let b = slackReturn,
        let info = try b.jsonDecode() as? [String:Any],
        let ok = info["ok"] as? Bool,
        let u = info["user"] as? [String: Any] else {
          Print("parse::ok(fault)")
          return nil
      }//end guard
      guard ok, let user = u["name"] as? String else {
        Print("lookup::ok(\(ok))")
        return nil
      }//end
      return user
    }catch(let err) {
      Print("parseUserName::\(err)")
      return nil
    }// end do
  }//end func

  /// lookup a user name by id asynchronously
  /// - parameters:
  ///   - uid: user id in slack
  ///   - found: closure for query callback, which will return the user name or nil if failed.
  public func lookup(uid: String, found: @escaping (String?)->Void ) {

    if let user = Settings.members[uid] {
      found(user)
      return
    }//end if

    Curl("https://slack.com/api/users.info?token=\(token)&user=\(uid)") { ret in
      found(self.parseUserName(ret))
    }//end curl
  }//end lookupSlackUser

  /// lookup a group of users by a set of IDs
  /// - parameters:
  ///   - uids: [String], the input set of user identifications
  ///   - found: a callback once all user IDs were confirmed; user's name could be found in the result dictionary
  public func lookup(uids: [String], found: @escaping ([String:String]) -> Void) {

    /// the returning dictionary
    var names: [String:String] = [:]

    /// the actual IDs to lookup
    let candidates = uids.filter { uid in
      // check if the uid was in cache
      guard let name = Settings.members[uid] else {
        return true
      }//end guard
      names[uid] = name
      return false
    }//end candidates

    // if fulfilled by cache, then callback & return
    if candidates.isEmpty {
      found(names)
      return
    }//end if

    // preform the real online lookup

    /// thread counter
    var total = 0

    /// lock for thread writing to names / total / cache
    let searchingLock = Threading.Lock()

    candidates.forEach { uid in

      // each lookup is a thread
      self.lookup(uid: uid) { ret in

        // the thread has returned
        searchingLock.doWithLock {

          // inc one for each thread return
          total += 1

          // check the result
          if let name = ret {

            // append it to cache
            Settings.members[uid] = name

            // append it to the return set
            names[uid] = name

          }//end if

          // check if the thread is the last arrival among the jobs
          if total == candidates.count {

            // the last arrival will do the callback
            found(names)
          }//end if
        }//end lock
      }//end lookup
    }//next
  }//end lookup

  /// reply a message to slack
  /// - parameters:
  ///   - channel: the channel id that the message will display
  ///   - msg: message body
  ///   - attachements: a json string for interactive messages, see slack api for more info
  ///   - confirmation: slack callback to confirm receiving this message
  func reply (channel: String, msg: String, attachements: String = "", confirmation: @escaping (String?)-> Void = { _ in }) {
    let m = msg.stringByEncodingURL
    let a = attachements.stringByEncodingURL
    let url = "https://slack.com/api/chat.postMessage?token=\(token)&channel=\(channel)&text=\(m)&username=\(bot)&as_user=true&attachments=\(a)"
    Curl(url) { confirmation($0) }
  }//end reply
}//end config
