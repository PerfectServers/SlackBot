//
//  main.swift
//  Perfect Slack Bot
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

import Regex
import PerfectLib
import PerfectHTTP
import PerfectHTTPServer
import PerfectNet
#if os(Linux)
  import SwiftGlibc
#else
  import Darwin
#endif

let global = Settings()

/// Primary Incoming Slack Message Handler
func WEBMessage(data: [String:Any]) throws -> RequestHandler {
  return {
    request, response in
    do {
      guard
        // Step 1. Get the Slack Post
        let post = request.postBodyString,

        // Step 2. Verify if this message is coming from Slack
        let _ = strstr(post, global.verify_token),

        // Step 3. Decode the JSON post into a dictionary
        let json = try post.jsonDecode() as? [String:Any]
      else
      {
        Print("slack::json(failed)")
        response.completed(status: .forbidden)
        return
      }//end json

      // Step 4. If this is an OAuth challenge, reply it.
      if let challenge = json["challenge"] as? String {
        response.appendBody(string: "\(challenge)\n").completed()
        return
      }//end json

      // Step 5. Confirm it is a valid Slack message calling.
      response.completed()

      // Step 6. Get the Event Object from this message
      guard
        let event = json["event"] as? [String:Any],
        let eventType = event["type"] as? String,
        let now = event["event_ts"] as? String,
        let channel = event["channel"] as? String,
        let sender = event["user"] as? String
      else
      {
        Print("slack::json(event attributes)")
        return
      }//end event

      // Step 7. Ignore the message sent by the bot itself.
      if sender == global.botId { return }

      var depositValue = 0
      switch eventType {

      case "message":
        // Step 8. If the message is a direct message from user, reply him / her
        guard let channelName = global.channels[channel] else
        {
          // in the direct message, ignore the speaker's request
          global.lookup(uid: sender)
          { ret in
            guard let snd = ret else
            {
              Print("sender::unknown")
              return
            }//end guard

            // In this demo, the bot will reply user for his/her own records with a leader board
            let sum = global.about(me: snd)
            let cookies = sum > 1 ? "cookies" : "cookie"
            let msg = sum > 0 ? "You have \(sum) \(cookies)." : "You have no cookies."
            let top = 20
            let table = global.leaderBoard(top: top).reduce("Name\tCookies")
            { previous, next in
              return previous + "\n\(next.name)\t\(next.total)"
            }//end table
            let fullMsg = "\(msg)\n*Top \(top) Cookie Monsters V7*\n```\n\(table)\n```\n"
            global.reply(channel: channel, msg: fullMsg)
          }//end lookup
          return
        }//end if

        // Step 9. Parse the message for a specific pattern.
        // In this demo, the bot will collect all cookies sent by users
        // So it will identify who sent whom with how many cookies
        // You can do whatever kind of message filter / parser in such a form
        guard let text = event["text"] as? String,
          let _ = strstr(text, ":cookie:") else
        {
            // normal message, ignore
            return
        }//end

        // use regular expression to get the receivers and filter out the sender himself / herself
        let receivers = text.matches(pattern: "<@[^>]+>")
          .map { String($0.extraction.characters.dropLast().dropFirst(2)) }
          .filter { $0 != sender }

        // if no valid user name mentioned in this message, simply ignore it.
        guard receivers.count > 0 else { return }

        // get the user display name to store into the database
        global.lookup(uids: receivers)
        { list in
          receivers.forEach
          { uid in
            guard let name = list[uid] else { return }
            global.lookup(uid: sender) { realName in
                guard let senderName  = realName else { return }
                global.deposit(moment: now, channel: channelName, receiver: name, sender: senderName, value: 1)
            }
          }//next
        }//end lookup
        return

      // Step 10. Check if the event is a reaction add or remve operation
      case "reaction_added":
        depositValue = 1
        break
      case "reaction_removed":
        depositValue = -1
        break
      default:
        Print("slack::event(unknown\(eventType))")
        return
      }//end case

      // In this demo, we listed `cookie` as the same as in the text for recording
      guard let reaction = event["reaction"] as? String,
        let itemUser = event["item_user"] as? String,
        let channelFullName = global.channels[channel],
        itemUser != sender,
        reaction == "cookie"
        else
      {
          Print("slack::json(item attributes)")
          return
      }//end if

      global.lookup(uids: [itemUser, sender]) { users in
        guard let objUsr = users[itemUser], let snd = users[sender] else {
          Print("slack::(receiver / sender) not found")
          return
        }//end guard
        let _ = global.deposit(moment: now, channel: channelFullName, receiver: objUsr, sender: snd, value: depositValue)
      }//end lookup

    }catch(let err){
      Print("slack:: \(err)")
      response.completed(status: .forbidden)
    }//end do
  }//end return
}//end handler

/// Slack Confirm URI, required by interactive messaging
func WEBConfirm(data: [String:Any]) throws -> RequestHandler {
	return {
		request, response in
    //do confirm if need
    response.completed()
  }//end return
}//end handler

/// Slack OAuth URI, required & also may be customized (to store the data or present a welcome page) if need.
func WEBOAuth(data: [String:Any]) throws -> RequestHandler {
  return {
    request, response in
    guard let code = request.param(name: "code") else {
      Print("oauth::rejected")
      response.completed(status: .forbidden)
      return
    }//end guard
    let oauth = [
      "client_id":global.client_id,
      "client_secret": global.client_secret,
      "redirect_uri": global.oauth_uri]
    let url = oauth.reduce("https://slack.com/api/oauth.access?code=\(code)") { $0 + "&\($1.key)=\($1.value)".stringByEncodingURL}
    global.Curl(url) { ret in
      guard let b = ret else {
        Print("oauth::url(failed)")
        response.completed(status: .forbidden)
        return
      }//end guard
      Print("oauth returned: \(b)")
      response.appendBody(string:
        "<HTML><TITLE>CookieMonster</TITLE><BODY><H1>Thank you for choosing Perfect!</H1></BODY></HTML>\n")
      response.completed()
    }//end curl
  }//end return
}//end handler

// load the uri into routers
let confData = [
	"servers": [
		[
			"name": global.serverName,
			"port": global.port,
			"routes":[
        ["method":"post", "uri":global.confirm_uri, "handler":WEBConfirm],
        ["method":"get",  "uri":global.oauth_uri, "handler":WEBOAuth],
        ["method":"post", "uri":global.message_uri, "handler":WEBMessage]
			],
			"tlsConfig": [
        "certPath" : global.cerPath,
        "keyPath": global.keyPath
      ],
      "runAs": global.runAs
    ]
	]
]

// run the server
do {
	// Launch the servers based on the configuration data.
	try HTTPServer.launch(configurationData: confData)
} catch(let err) {
  global.close("General Failure: \(err)")
	fatalError("\(err)") // fatal error launching one of the servers
}
